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
BASE_PATH = r'D:\Main\3. Work - Teaching\Projects\Question extractor'
CONFIG_PATH = os.path.join(BASE_PATH, 'config.json')

OUTPUT_CSV_PATH = os.path.join(BASE_PATH, 'Question Bank Digvijay.csv')
INPUT_CSV_PATH = os.path.join(BASE_PATH, 'Question Bank Digvijay - Inputs.csv')

RAW_DATA_DIR = os.path.join(BASE_PATH, 'raw data')
TRIMMED_DIR = os.path.join(RAW_DATA_DIR, 'Trimmed_PDFs')
PROCESSED_BASE = os.path.join(BASE_PATH, 'Processed_Database')

os.makedirs(TRIMMED_DIR, exist_ok=True)
os.makedirs(PROCESSED_BASE, exist_ok=True)

# --- 2. UTILITIES ---
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
    return gray.point(lambda p: 255 if p > 180 else p)

# --- 3. STRUCTURE PARSING ---

def get_answer_key(page_text):
    """Parses '1 (c) 2 (a)' or '1\n(c)' formats."""
    ans_map = {}
    # Matches: 1 (a), 1(a), 1\n(a)
    matches = re.findall(r'(\d+)\s*[\n\r]*\(([a-d])\)', page_text.lower())
    for q, opt in matches:
        ans_map[int(q)] = opt.upper()
    return ans_map

def extract_anchors(page, col_bbox, current_topic_id):
    """Scans a vertical column strip for Question Numbers."""
    anchors = []
    try:
        col_crop = page.within_bbox(col_bbox)
        words = col_crop.extract_words()
        
        for w in words:
            text = w['text'].strip().replace('.', '')
            
            # Validation: Digits only, 1-3 chars (avoids years like 2019)
            if re.match(r'^\d{1,3}$', text):
                rel_x = w['x0'] - col_bbox[0]
                
                # Indentation check: Q numbers are usually on the left edge (< 35px)
                if rel_x < 35: 
                    anchors.append({
                        'q_num': int(text),
                        'top': w['top'],
                        'bottom': w['bottom'],
                        'col_x': col_bbox[0],
                        'col_w': col_bbox[2] - col_bbox[0],
                        'topic_id': current_topic_id
                    })
    except Exception as e:
        pass 
    return anchors

def parse_pdf_structure(pdf_path):
    structure = []
    
    # State Variables
    topic_counter = 0  # Will become Topic_1, Topic_2...
    
    with pdfplumber.open(pdf_path) as pdf:
        for p_idx, page in enumerate(pdf.pages):
            width = page.width
            height = page.height
            text = page.extract_text() or ""
            
            # --- 1. DETECT TOPIC ---
            # Simple check: If "Topic" appears, increment counter
            # We ignore the actual text name to avoid parsing errors
            if re.search(r'Topic\s+\d+', text, re.IGNORECASE):
                topic_counter += 1
            
            current_topic_slug = f"Topic_{max(1, topic_counter)}" # Default to Topic_1 if none found yet

            # --- 2. DETECT BOUNDARIES (Questions Only) ---
            page_top = 0
            page_bottom = height * 0.93 # Default Footer
            
            # If "Answers" or "Explanations" appears, STOP questions there
            # We only care about questions above this line
            stop_markers = ["Answers", "Explanations", "Answer Key"]
            for marker in stop_markers:
                hits = page.search(marker)
                if hits:
                    # Use the top of the marker as the absolute bottom limit
                    page_bottom = min(page_bottom, hits[0]['top'])

            # --- 3. DEFINE COLUMNS (2-Column Layout for Questions) ---
            # If the stop marker is at the very top (e.g., page is full of solutions), skip page
            if page_bottom < 50:
                continue

            mid = width / 2
            cols = [
                (0, page_top, mid, page_bottom),      # Left Column
                (mid, page_top, width, page_bottom)   # Right Column
            ]

            # --- 4. EXTRACT ANCHORS ---
            page_anchors = []
            for col_idx, bbox in enumerate(cols):
                col_anchors = extract_anchors(page, bbox, current_topic_slug)
                for a in col_anchors:
                    a['page'] = p_idx
                    a['col_idx'] = col_idx
                    a['limit_bottom'] = bbox[3] # Hard limit for this column
                    page_anchors.append(a)
            
            # Sort: Column 0 -> Column 1 -> Top Y
            page_anchors.sort(key=lambda x: (x['col_idx'], x['top']))
            structure.extend(page_anchors)

    return structure

# --- 4. BATCH PROCESSOR ---
def run_batch_extraction(row_data, source_pdf):
    start_p = int(row_data['pdf_start_pg'])
    end_p = int(row_data['pdf_end_pg'])
    chapter = str(row_data['Chapter']).strip()
    
    print(f"\n🚀 Processing Batch: {chapter} (Pg {start_p}-{end_p})")
    
    # --- FILE HANDLING ---
    trimmed_name = f"Trimmed_{chapter}_{start_p}_{end_p}".replace(" ", "_")
    trimmed_filename = f"{trimmed_name}.pdf"
    trimmed_path = os.path.join(TRIMMED_DIR, trimmed_filename)
    
    if not os.path.exists(trimmed_path):
        master_pdf_path = os.path.join(RAW_DATA_DIR, source_pdf)
        if os.path.exists(master_pdf_path):
            print(f"   ✂️ Trimming master PDF...")
            reader = PdfReader(master_pdf_path)
            writer = PdfWriter()
            s = max(0, start_p - 1)
            e = min(len(reader.pages), end_p)
            for i in range(s, e):
                writer.add_page(reader.pages[i])
            with open(trimmed_path, "wb") as f: writer.write(f)
        else:
            print(f"   ❌ Master PDF not found: {master_pdf_path}")
            return False

    # --- 2. EXTRACTION ---
    anchors = parse_pdf_structure(trimmed_path)
    
    # Get Answer Key (Global for this batch)
    full_text = ""
    with pdfplumber.open(trimmed_path) as pdf:
        for p in pdf.pages: full_text += (p.extract_text() or "") + "\n"
    answer_key = get_answer_key(full_text)
    
    print("   🖼️ Converting PDF to images...")
    pdf_images = convert_from_path(trimmed_path, dpi=300)
    scale = 300 / 72 
    
    output_dir = os.path.join(PROCESSED_BASE, trimmed_name)
    os.makedirs(output_dir, exist_ok=True)
    
    rows = []
    
    with open(CONFIG_PATH, 'r') as f: config = json.load(f)
    curr_id = int(config.get("last_unique_id", 0))

    print(f"   🔎 Found {len(anchors)} Questions. Cropping...")
    
    for i, start in tqdm(enumerate(anchors), total=len(anchors)):
        try:
            # Smart Bottom Detection
            y1 = (start['top'] * scale) - 10
            y2 = start['limit_bottom'] * scale # Default to boundary (e.g., "Answers")
            
            # Look ahead for NEXT anchor in SAME column to close the crop
            for j in range(i+1, len(anchors)):
                nxt = anchors[j]
                # Must be same page, same column
                if nxt['page'] == start['page'] and nxt['col_idx'] == start['col_idx']:
                    if nxt['top'] > start['top']:
                        y2 = (nxt['top'] * scale) - 10
                        break
            
            # Validate Coordinates
            x1 = start['col_x'] * scale
            x2 = (start['col_x'] + start['col_w']) * scale
            
            if y2 <= y1 + 20: y2 = y1 + 150 # Safety minimum height
            
            # Crop & Save
            img = pdf_images[start['page']].crop((x1, y1, x2, y2))
            final_img = compress_and_clean(trim_whitespace(img))
            
            # Filename: Q_1_Topic_1.png
            filename = f"Q_{start['q_num']}_{start['topic_id']}.png"
            
            final_img.save(os.path.join(output_dir, filename), optimize=True)
            
            # Metadata
            curr_id += 1
            rows.append({
                'unique_id': curr_id,
                'Question No.': start['q_num'],
                'Folder': trimmed_name,
                'Chapter': chapter,
                'Topic': start['topic_id'], # Now saves as "Topic_1"
                'Subject': row_data.get('Subject', 'Physics'),
                'Correct Answer': answer_key.get(start['q_num'], ""),
                'image_url': filename,
                'Type': 'Question'
            })
        except Exception as e:
            print(f"   ⚠️ Skipped Q{start.get('q_num')}: {e}")

    # --- 3. SAVE ---
    if rows:
        df_new = pd.DataFrame(rows)
        if os.path.exists(OUTPUT_CSV_PATH):
            pd.concat([pd.read_csv(OUTPUT_CSV_PATH), df_new], ignore_index=True).to_csv(OUTPUT_CSV_PATH, index=False)
        else:
            df_new.to_csv(OUTPUT_CSV_PATH, index=False)

        config["last_unique_id"] = curr_id
        with open(CONFIG_PATH, 'w') as f: json.dump(config, f, indent=4)
        print(f"   💾 Saved {len(rows)} questions.")
    
    return True

# --- 5. MAIN LOOP ---
if __name__ == "__main__":
    SOURCE_PDF = "PYQ NEET Digvijay.pdf"
    
    if not os.path.exists(INPUT_CSV_PATH):
        print(f"❌ Error: Input CSV not found at {INPUT_CSV_PATH}")
    else:
        try:
            # Robust CSV Reading
            input_df = pd.read_csv(INPUT_CSV_PATH, skipinitialspace=True)
            input_df.columns = input_df.columns.str.strip()
            
            if 'isProcessed' not in input_df.columns:
                input_df['isProcessed'] = 'No'
            
            input_df['isProcessed'] = input_df['isProcessed'].astype(str).str.strip()
            
            pending = input_df[input_df['isProcessed'] != 'Yes']
            print(f"📋 Found {len(pending)} batches to process.")
            
            for idx, row in pending.iterrows():
                try:
                    if run_batch_extraction(row, SOURCE_PDF):
                        input_df.at[idx, 'isProcessed'] = 'Yes'
                        input_df.to_csv(INPUT_CSV_PATH, index=False)
                except Exception as e:
                    print(f"❌ Batch Failed: {e}")
                    
            print("\n🏁 ALL TASKS FINISHED.")
            
        except Exception as e:
            print(f"❌ Critical CSV Error: {e}")