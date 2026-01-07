import os
import pandas as pd
import pdfplumber
import json
import re
import time
from pdf2image import convert_from_path
from PIL import Image, ImageChops
from tqdm import tqdm

# --- 1. CONFIGURATION ---
BASE_PATH = 'D:/Main/3. Work - Teaching/Projects/Question extractor'
CONFIG_PATH = os.path.join(BASE_PATH, 'config.json')
# Experimental CSV to avoid overwriting production DB Master
ALLEN_CSV_PATH = os.path.join(BASE_PATH, 'Question Bank Allen.csv')
SOURCE_DIR = os.path.join(BASE_PATH, 'raw data', 'Trimmed_PDFs')
OUTPUT_BASE = os.path.join(BASE_PATH, 'Processed_Database')

# --- 2. IMAGE UTILITIES ---
def trim_whitespace(im):
    """Removes outer white margins from cropped images[cite: 301]."""
    try:
        bg = Image.new(im.mode, im.size, im.getpixel((0,0)))
        diff = ImageChops.difference(im, bg)
        diff = ImageChops.add(diff, diff, 2.0, -100)
        bbox = diff.getbbox()
        if bbox: return im.crop(bbox)
        return im
    except Exception: return im

# --- 3. ANCHOR & ANSWER KEY LOGIC ---
def find_allen_anchors(pdf_path):
    """Detects question numbers at the start of columns[cite: 306, 311]."""
    anchors = []
    with pdfplumber.open(pdf_path) as pdf:
        for page_idx, page in enumerate(pdf.pages):
            midpoint = page.width / 2
            words = page.extract_words(keep_blank_chars=False)
            for word in words:
                text = word['text'].strip()
                # Pattern: "1." or "25."
                if re.match(r'^\d+\.$', text):
                    col = 0 if word['x0'] < midpoint else 1
                    rel_x = word['x0'] if col == 0 else (word['x0'] - midpoint)
                    # Relaxed tolerance for Allen layout (approx 15% of column width) [cite: 311]
                    if rel_x < (page.width * 0.15):
                        anchors.append({
                            'q_num': int(text.replace('.', '')),
                            'page_idx': page_idx,
                            'top': word['top'],
                            'col': col
                        })
    return sorted(anchors, key=lambda x: x['q_num'])

def parse_allen_answer_key(pdf_path):
    """Scans the last page for the 'ANSWER KEY' section[cite: 265, 266]."""
    ans_map = {}
    with pdfplumber.open(pdf_path) as pdf:
        page = pdf.pages[-1]
        text = page.extract_text()
        if text and "ANSWER KEY" in text.upper():
            # Regex for Allen format: "1. (2)" or "1. 2" [cite: 268]
            matches = re.findall(r'(\d+)\.\s*\(?([1-4A-D])\)?', text)
            for q, a in matches:
                ans_map[int(q)] = a
    return ans_map

# --- 4. CROP & STITCH LOGIC ---
def crop_and_save_allen(pdf_path, anchors, output_folder):
    """Ported stitching logic from CollegeDoorsBulk[cite: 327, 335]."""
    try:
        pdf_images = convert_from_path(pdf_path, dpi=300)
    except: return

    page_width, page_height = pdf_images[0].size
    scale = 300 / 72 
    midpoint_px = page_width / 2
    FOOTER_CUTOFF_PX = page_height * 0.92
    VERTICAL_PADDING = 15
    TOP_MARGIN = 50 * scale 

    for i, start in enumerate(anchors):
        q_num = start['q_num']
        end = anchors[i+1] if i + 1 < len(anchors) else {'page_idx': start['page_idx'], 'top': FOOTER_CUTOFF_PX/scale, 'col': start['col']}
        
        start_top_px = max(0, (start['top'] * scale) - VERTICAL_PADDING)
        end_top_px = (end['top'] * scale) - VERTICAL_PADDING
        
        images_to_stitch = []
        # Logic handles cross-column and cross-page questions [cite: 333, 334]
        if start['page_idx'] == end['page_idx'] and start['col'] == end['col']:
            # Single column segment
            bottom = min(end_top_px, FOOTER_CUTOFF_PX)
            left = 0 if start['col'] == 0 else midpoint_px
            right = midpoint_px if start['col'] == 0 else page_width
            images_to_stitch.append(pdf_images[start['page_idx']].crop((left, start_top_px, right, bottom)))
        else:
            # Multi-segment stitching [cite: 336, 383]
            # 1. Start fragment
            left = 0 if start['col'] == 0 else midpoint_px
            right = midpoint_px if start['col'] == 0 else page_width
            images_to_stitch.append(pdf_images[start['page_idx']].crop((left, start_top_px, right, FOOTER_CUTOFF_PX)))
            
            # 2. End fragment
            left_e = 0 if end['col'] == 0 else midpoint_px
            right_e = midpoint_px if end['col'] == 0 else page_width
            images_to_stitch.append(pdf_images[end['page_idx']].crop((left_e, TOP_MARGIN, right_e, end_top_px)))

        if images_to_stitch:
            total_h = sum(im.height for im in images_to_stitch)
            max_w = max(im.width for im in images_to_stitch)
            final_img = Image.new('RGB', (max_w, total_h), (255, 255, 255))
            y = 0
            for im in images_to_stitch:
                final_img.paste(im, (0, y))
                y += im.height
            final_img = trim_whitespace(final_img)
            final_img.save(os.path.join(output_folder, f"Q_{q_num}.png"))

# --- 5. MAIN PROCESSING ---
def process_allen_trimmed(pdf_filename, subject, chapter):
    pdf_path = os.path.join(SOURCE_DIR, pdf_filename)
    # Using PDF name as folder name as requested [cite: 340, 500]
    folder_name = pdf_filename.replace(".pdf", "")
    output_dir = os.path.join(OUTPUT_BASE, folder_name)
    os.makedirs(output_dir, exist_ok=True)

    # 1. Load config and pick last unique id [cite: 261, 351]
    with open(CONFIG_PATH, 'r') as f:
        config = json.load(f)
    current_id = int(config.get("last_unique_id", 0))

    # 2. Run Detectors
    anchors = find_allen_anchors(pdf_path)
    ans_map = parse_allen_answer_key(pdf_path)

    # 3. Crop Images
    crop_and_save_allen(pdf_path, anchors, output_dir)

    # 4. Prepare Data with Production Schema [cite: 292, 293]
    new_rows = []
    for a in anchors:
        current_id += 1
        new_rows.append({
            'unique_id': current_id,
            'Question No.': a['q_num'],
            'Q': a['q_num'],
            'Folder': folder_name,
            'Subject': subject,
            'Chapter': chapter,
            'Correct Answer': ans_map.get(a['q_num'], ""),
            'QC_Status': 'Pending QC',
            'Exam': 'NEET',
            'PDF_Text_Available': 'No'
        })

    # 5. Isolated Experimental Write 
    df_new = pd.DataFrame(new_rows)
    if os.path.exists(ALLEN_CSV_PATH):
        df_old = pd.read_csv(ALLEN_CSV_PATH)
        pd.concat([df_old, df_new], ignore_index=True).to_csv(ALLEN_CSV_PATH, index=False)
    else:
        df_new.to_csv(ALLEN_CSV_PATH, index=False)

    # 6. Increment Config and Save [cite: 263, 405]
    config["last_unique_id"] = current_id
    with open(CONFIG_PATH, 'w') as f:
        json.dump(config, f, indent=4)

    print(f"✅ Processed {len(new_rows)} questions.")
    print(f"📁 Images: {output_dir}")
    print(f"📊 CSV: {ALLEN_CSV_PATH}")

if __name__ == "__main__":
    # TARGET FILE
    FILE = "Trimmed_Moving charges_p1030_to_p1041.pdf"
    process_allen_trimmed(FILE, "Physics", "Moving Charges and Magnetism")