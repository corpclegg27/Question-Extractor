import os
import re
import json
import numpy as np
import pandas as pd
import pdfplumber
from pypdf import PdfReader, PdfWriter
from PIL import Image, ImageChops, ImageOps
from pdf2image import convert_from_path
from tqdm import tqdm

# --- 1. CONFIGURATION ---
BASE_PATH = 'D:/Main/3. Work - Teaching/Projects/Question extractor'
CONFIG_PATH = os.path.join(BASE_PATH, 'config.json')
DIGVIJAY_CSV_PATH = os.path.join(BASE_PATH, 'Question Bank Digvijay.csv')
INPUT_CSV_PATH = os.path.join(BASE_PATH, 'Question Bank Digvijay - Inputs.csv')
RAW_DATA_DIR = os.path.join(BASE_PATH, 'raw data')
TRIMMED_DIR = os.path.join(RAW_DATA_DIR, 'Trimmed_PDFs')
PROCESSED_BASE = os.path.join(BASE_PATH, 'Processed_Database')

os.makedirs(TRIMMED_DIR, exist_ok=True)
os.makedirs(PROCESSED_BASE, exist_ok=True)

# --- 2. UTILITIES ---
def slugify(text):
    """Clean topic name for filenames."""
    if not text: return "General"
    return re.sub(r'\W+', '_', text).strip('_')

def trim_whitespace(im):
    try:
        bg = Image.new(im.mode, im.size, im.getpixel((0,0)))
        diff = ImageChops.difference(im, bg)
        diff = ImageChops.add(diff, diff, 2.0, -100)
        bbox = diff.getbbox()
        return im.crop(bbox) if bbox else im
    except: return im

def compress_and_clean(img):
    gray = img.convert('L')
    return gray.point(lambda p: 255 if p > 170 else p)

# --- 3. COLUMN-AWARE PARSER ---

def get_page_layout_mode(text):
    """Decides if page is mostly Questions (2-col) or Explanations (3-col)."""
    if "Explanations" in text or "Hints & Solutions" in text:
        return "EXPLANATION_MODE"
    return "QUESTION_MODE"

def extract_anchors_from_column(page, col_bbox, mode="QUESTION"):
    """
    Scans a specific vertical strip of the PDF for question numbers.
    col_bbox = (x0, y0, x1, y1)
    """
    anchors = []
    # Crop the page object to the column
    col_crop = page.within_bbox(col_bbox)
    words = col_crop.extract_words()
    
    for w in words:
        text = w['text'].strip().replace('.', '')
        
        # STRICT REGEX: 1 or 2 digits only. 
        # Prevents "2011", "2015" from being seen as Q#
        if re.match(r'^\d{1,2}$', text):
            # Check for font size or X-position to confirm it's a number bullet
            # usually bullets are at the far left of the column
            rel_x = w['x0'] - col_bbox[0]
            if rel_x < 40: # It must be at the start of the line/column
                anchors.append({
                    'q_num': int(text),
                    'top': w['top'],
                    'bottom': w['bottom'],
                    'col_x': col_bbox[0], # Offset for image cropping later
                    'mode': mode
                })
    return anchors

def parse_digvijay_structure(pdf_path):
    structure = []
    current_topic = "General"
    
    with pdfplumber.open(pdf_path) as pdf:
        for p_idx, page in enumerate(pdf.pages):
            width = page.width
            height = page.height
            text = page.extract_text() or ""

            # 1. Topic Detection (Look at top 20% of page)
            header_text = page.within_bbox((0,0,width, height*0.2)).extract_text()
            topic_match = re.search(r'Topic\s+\d+\s+(.*)', header_text)
            if topic_match:
                current_topic = topic_match.group(1).split('\n')[0].strip()

            mode = get_page_layout_mode(text)
            page_anchors = []

            if mode == "QUESTION_MODE":
                # Split into 2 Columns
                mid = width / 2
                cols = [
                    (0, 0, mid, height),      # Col 1
                    (mid, 0, width, height)   # Col 2
                ]
            else: 
                # Split into 3 Columns for Explanations
                one_third = width / 3
                cols = [
                    (0, 0, one_third, height),           # Col 1
                    (one_third, 0, one_third*2, height), # Col 2
                    (one_third*2, 0, width, height)      # Col 3
                ]

            for col_idx, bbox in enumerate(cols):
                col_anchors = extract_anchors_from_column(page, bbox, mode)
                for a in col_anchors:
                    a['page'] = p_idx
                    a['col_idx'] = col_idx
                    a['topic'] = current_topic
                    # Store the crop box width for later
                    a['crop_width'] = bbox[2] - bbox[0] 
                    page_anchors.append(a)
            
            # Sort anchors by Column then Top Position
            page_anchors.sort(key=lambda x: (x['col_idx'], x['top']))
            structure.extend(page_anchors)

    return structure

# --- 4. BATCH PROCESSOR ---
def run_batch_extraction(row_data, source_pdf):
    start_p, end_p = int(row_data['pdf_start_pg']), int(row_data['pdf_end_pg'])
    chapter = row_data['Chapter']
    
    print(f"\n🚀 STARTING BATCH: {chapter}")
    
    # 1. Trim PDF
    input_path = os.path.join(RAW_DATA_DIR, source_pdf)
    trimmed_name = f"Trimmed_{chapter}_{start_p}".replace(" ", "_")
    trimmed_path = os.path.join(TRIMMED_DIR, f"{trimmed_name}.pdf")
    
    reader = PdfReader(input_path); writer = PdfWriter()
    for i in range(start_p - 1, min(end_p, len(reader.pages))):
        writer.add_page(reader.pages[i])
    with open(trimmed_path, "wb") as f: writer.write(f)

    # 2. Config Setup
    with open(CONFIG_PATH, 'r') as f: config = json.load(f)
    curr_id = int(config.get("last_unique_id", 0))
    
    # 3. Parse Structure
    anchors = parse_digvijay_structure(trimmed_path)
    
    # 4. Image Conversion
    pdf_images = convert_from_path(trimmed_path, dpi=300)
    scale = 300/72 # PDF Point to Pixel scale
    
    output_dir = os.path.join(PROCESSED_BASE, trimmed_name)
    os.makedirs(output_dir, exist_ok=True)
    
    rows = []
    
    print(f"   found {len(anchors)} potential items...")

    # 5. Crop Loop
    for i, start in tqdm(enumerate(anchors), total=len(anchors)):
        try:
            # Determine End Point (y2)
            # Logic: y2 is the top of the next anchor IN THE SAME COLUMN
            # If no next anchor in column, y2 is page bottom
            
            y1 = (start['top'] * scale) - 5
            
            # Look ahead for next anchor in same page & same column
            next_anchor = None
            for j in range(i+1, len(anchors)):
                if anchors[j]['page'] == start['page'] and anchors[j]['col_idx'] == start['col_idx']:
                    next_anchor = anchors[j]
                    break
            
            if next_anchor:
                y2 = (next_anchor['top'] * scale) - 5
            else:
                # End of column -> Use footer margin
                y2 = pdf_images[start['page']].height * 0.92

            # Calculate X coordinates based on Column
            col_w_px = start['crop_width'] * scale
            x1 = start['col_x'] * scale
            x2 = x1 + col_w_px

            # Crop
            img = pdf_images[start['page']].crop((x1, y1, x2, y2))
            final_img = compress_and_clean(trim_whitespace(img))
            
            # Filename Logic
            topic_slug = slugify(start['topic'])
            prefix = "Sol" if start['mode'] == "EXPLANATION_MODE" else "Q"
            filename = f"{prefix}_{start['q_num']}_{topic_slug}.png"
            
            save_path = os.path.join(output_dir, filename)
            final_img.save(save_path, optimize=True)
            
            # Only add to CSV if it's a Question (avoid dupe rows for solutions)
            if start['mode'] == "QUESTION_MODE":
                curr_id += 1
                rows.append({
                    'unique_id': curr_id,
                    'Question No.': start['q_num'],
                    'Folder': trimmed_name,
                    'Topic': start['topic'],
                    'Chapter': chapter,
                    'Subject': row_data['Subject'],
                    'image_url': filename,
                    'pdf_Text': f"Topic: {start['topic']} | Q{start['q_num']}"
                })

        except Exception as e:
            print(f"Skipped {start.get('q_num')}: {e}")

    # 6. Save Data
    df_new = pd.DataFrame(rows)
    if os.path.exists(DIGVIJAY_CSV_PATH):
        pd.concat([pd.read_csv(DIGVIJAY_CSV_PATH), df_new], ignore_index=True).to_csv(DIGVIJAY_CSV_PATH, index=False)
    else:
        df_new.to_csv(DIGVIJAY_CSV_PATH, index=False)

    config["last_unique_id"] = curr_id
    with open(CONFIG_PATH, 'w') as f: json.dump(config, f, indent=4)
    
    if os.path.exists(trimmed_path): os.remove(trimmed_path)
    return True

if __name__ == "__main__":
    SOURCE_PDF = "PYQ NEET Digvijay.pdf"
    
    if os.path.exists(INPUT_CSV_PATH):
        input_df = pd.read_csv(INPUT_CSV_PATH)
        if 'isProcessed' not in input_df.columns: input_df['isProcessed'] = 'No'
        
        # Process only unprocessed rows
        for idx, row in input_df[input_df['isProcessed'] != 'Yes'].iterrows():
            if run_batch_extraction(row, SOURCE_PDF):
                input_df.at[idx, 'isProcessed'] = 'Yes'
                input_df.to_csv(INPUT_CSV_PATH, index=False)