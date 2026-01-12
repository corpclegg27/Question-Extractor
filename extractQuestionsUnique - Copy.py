import os
import re
import json
import numpy as np
import pandas as pd
import pdfplumber
from pdf2image import convert_from_path
from PIL import Image, ImageChops, ImageOps
from tqdm import tqdm

# --- 1. CONFIGURATION ---
BASE_PATH = r'D:\Main\3. Work - Teaching\Projects\Question extractor'
SOURCE_PDF_NAME = "JEE Mains Unique Practice Questions_Physics (Que. & Ans.).pdf"

RAW_DATA_DIR = os.path.join(BASE_PATH, 'Raw data') 
PROCESSED_BASE = os.path.join(BASE_PATH, 'Processed_Database')
OUTPUT_CSV_PATH = os.path.join(BASE_PATH, 'JEE_Mains_Unique_Questions.csv')
CONFIG_PATH = os.path.join(BASE_PATH, 'config.json')

os.makedirs(PROCESSED_BASE, exist_ok=True)

# --- 2. IMAGE UTILITIES ---

def pixel_sensitive_crop(img):
    """
    Dynamic cropping using vertical pixel projection to strip question numbers.
    Retrieved from: extractQuestionsAllenFinal.py
    """
    try:
        inverted_img = ImageOps.invert(img.convert('L'))
        data = np.array(inverted_img)
        horizontal_projection = np.sum(data, axis=0)
        width = len(horizontal_projection)
        
        crop_x, whitespace_count, in_number_block = 0, 0, False
        
        # Scan from left to right (starting at pixel 5 to avoid edge noise)
        for x in range(5, width):
            if horizontal_projection[x] > 500: # Threshold for 'ink' (the number)
                in_number_block = True
                whitespace_count = 0
            elif in_number_block:
                whitespace_count += 1
                # If we see enough whitespace after the number block, cut here
                if whitespace_count >= 15: 
                    crop_x = x - whitespace_count + 2
                    break
        
        # Safety: If cut is too deep (>30% width) or 0, just take a safe 5% margin
        if crop_x == 0 or crop_x > (width * 0.30): 
            crop_x = int(width * 0.05)
            
        return img.crop((crop_x, 0, width, img.size[1]))
    except:
        return img

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
    return gray.point(lambda p: 255 if p > 190 else p)

# --- 3. PARSING LOGIC ---

def extract_answer_key(pdf_path):
    """Scans LAST pages for Answer Key tables."""
    ans_map = {}
    print("🔍 Scanning for Answer Key...")
    
    with pdfplumber.open(pdf_path) as pdf:
        start_check = max(0, len(pdf.pages) - 3)
        for i in range(start_check, len(pdf.pages)):
            page = pdf.pages[i]
            text = page.extract_text()
            if not text: continue

            matches = re.findall(r'(\d+)\.\s*\(([^)]+)\)', text)
            for q_num, ans_val in matches:
                ans_map[int(q_num)] = ans_val.strip()
            
    print(f"   ✅ Found {len(ans_map)} answers in key.")
    return ans_map

def find_anchors_on_page(page, p_idx, last_q_num):
    """Finds all question numbers on a page, sorting them into columns."""
    width = page.width
    mid_line = width / 2
    
    words = page.extract_words()
    candidates = []
    
    for w in words:
        text = w['text'].strip()
        if re.match(r'^\d+\.$', text):
            try:
                num = int(text.replace('.', ''))
                # Strict sequence check to ignore years (e.g. 2019)
                if (num == 1) or (0 < (num - last_q_num) < 50):
                    candidates.append({
                        'q_num': num,
                        'top': w['top'],
                        'bottom': w['bottom'],
                        'x0': w['x0'],
                        'page': p_idx
                    })
            except: pass

    anchors = []
    for cand in candidates:
        if cand['x0'] < mid_line:
            cand['col_idx'] = 0
            cand['col_x'] = 0
            cand['col_w'] = mid_line
        else:
            cand['col_idx'] = 1
            cand['col_x'] = mid_line
            cand['col_w'] = width - mid_line
        
        anchors.append(cand)

    anchors.sort(key=lambda x: (x['col_idx'], x['top']))
    
    if anchors:
        new_last_q = max(a['q_num'] for a in anchors)
        return anchors, new_last_q
    
    return anchors, last_q_num

def parse_document_structure(pdf_path):
    structure = []
    last_q_num = 0
    
    print("🔍 Analyzing Document Structure (Global Scan)...")
    
    with pdfplumber.open(pdf_path) as pdf:
        for p_idx, page in enumerate(pdf.pages):
            # Check for Answer Key Header to stop scan
            header_crop = page.within_bbox((0, 0, page.width, page.height*0.2))
            header_text = header_crop.extract_text() or ""
            
            if "ANSWER KEY" in header_text.upper():
                print(f"   🛑 Answer Key detected on Page {p_idx+1}. Stopping scan.")
                break

            page_anchors, last_q_num = find_anchors_on_page(page, p_idx, last_q_num)
            structure.extend(page_anchors)
            
    return structure

# --- 4. MAIN EXTRACTION ROUTINE ---
def run_extraction():
    full_pdf_path = os.path.join(RAW_DATA_DIR, SOURCE_PDF_NAME)
    
    if not os.path.exists(full_pdf_path):
        print(f"❌ Error: File not found at {full_pdf_path}")
        return

    # 1. Get Answers
    ans_key = extract_answer_key(full_pdf_path)
    
    # 2. Get Question Locations
    anchors = parse_document_structure(full_pdf_path)
    print(f"   ✅ Identified {len(anchors)} Questions.")

    # 3. Setup Output
    folder_name = "JEE_Unique_Practice"
    output_dir = os.path.join(PROCESSED_BASE, folder_name)
    os.makedirs(output_dir, exist_ok=True)
    
    print("🖼️ Converting PDF to Images...")
    pdf_images = convert_from_path(full_pdf_path, dpi=300)
    scale = 300 / 72
    
    curr_id = 0
    if os.path.exists(CONFIG_PATH):
        with open(CONFIG_PATH, 'r') as f:
            curr_id = int(json.load(f).get('last_unique_id', 0))

    rows = []
    
    print("✂️ Cropping & Extracting Text...")
    with pdfplumber.open(full_pdf_path) as pdf:
        
        for i, start in tqdm(enumerate(anchors), total=len(anchors)):
            try:
                # --- COORDINATE CALCULATION ---
                pt_y1 = start['top'] - 5 
                pt_y2 = pdf.pages[start['page']].height * 0.93 
                
                for j in range(i+1, len(anchors)):
                    nxt = anchors[j]
                    if nxt['page'] != start['page'] or nxt['col_idx'] != start['col_idx']: break
                    if nxt['page'] == start['page'] and nxt['col_idx'] == start['col_idx']:
                        pt_y2 = nxt['top'] - 5
                        break

                if pt_y2 <= pt_y1 + 10: pt_y2 = pt_y1 + 100

                # --- TEXT EXTRACTION ---
                raw_text = ""
                try:
                    target_page = pdf.pages[start['page']]
                    # Define text bbox slightly wider to catch full lines
                    text_bbox = (start['col_x'], pt_y1, start['col_x'] + start['col_w'], pt_y2)
                    raw_text = target_page.within_bbox(text_bbox).extract_text() or ""
                    raw_text = " ".join(raw_text.split())
                except: raw_text = ""

                # --- IMAGE PROCESSING ---
                px_x1 = start['col_x'] * scale
                px_x2 = (start['col_x'] + start['col_w']) * scale
                px_y1 = pt_y1 * scale
                px_y2 = pt_y2 * scale
                
                # 1. Base Crop
                img = pdf_images[start['page']].crop((px_x1, px_y1, px_x2, px_y2))
                
                # 2. **REMOVE QUESTION NUMBER** (Added Step)
                img = pixel_sensitive_crop(img)
                
                # 3. Clean and Save
                final_img = compress_and_clean(trim_whitespace(img))
                q_w, q_h = final_img.size
                
                img_filename = f"Q_{start['q_num']}.png"
                final_img.save(os.path.join(output_dir, img_filename), optimize=True)
                
                curr_id += 1
                rows.append({
                    'unique_id': curr_id,
                    'Question No.': start['q_num'],
                    'Folder': folder_name,
                    'Exam': 'JEE Main',
                    'Subject': 'Physics',
                    'Source File': SOURCE_PDF_NAME,
                    'Correct Answer': ans_key.get(start['q_num'], ""),
                    'image_url': img_filename,
                    'q_width': q_w,
                    'q_height': q_h,
                    'pdf_Text': raw_text,
                    'PDF_Text_Available': 'Yes' if len(raw_text) > 10 else 'No'
                })
                
            except Exception as e:
                print(f"⚠️ Error Q{start.get('q_num')}: {e}")

    # --- 5. DATA POST-PROCESSING (Merged Logic) ---
    if rows:
        df = pd.DataFrame(rows)
        
        print("\n⚙️ Applying Post-Processing Logic...")
        
        # 1. Set Defaults
        df['PYQ'] = 'Yes'
        
        # 2. Extract PYQ Year from Text
        def extract_year(text):
            if pd.isna(text): return 0
            # Matches [JEE (Main)-2019]
            match = re.search(r'\[JEE \(Main\)-(\d{4})\]', str(text), re.IGNORECASE)
            if match:
                return int(match.group(1))
            return 0
            
        df['PYQ_Year'] = df['pdf_Text'].apply(extract_year)
        
        # 3. Determine Question Type
        def get_q_type(val):
            if pd.isna(val): return "Numerical type"
            s_val = str(val).split('.')[0].strip()
            if s_val in ['1', '2', '3', '4']:
                return "Single Correct"
            return "Numerical type"

        df['Question type'] = df['Correct Answer'].apply(get_q_type)

        # 4. Save
        if os.path.exists(OUTPUT_CSV_PATH):
            existing = pd.read_csv(OUTPUT_CSV_PATH)
            combined = pd.concat([existing, df], ignore_index=True)
            combined.drop_duplicates(subset=['Question No.', 'Folder'], keep='last', inplace=True)
            combined.to_csv(OUTPUT_CSV_PATH, index=False)
        else:
            df.to_csv(OUTPUT_CSV_PATH, index=False)
            
        print(f"✅ Saved {len(rows)} processed questions to {OUTPUT_CSV_PATH}")
        print(f"   - Years Extracted: {sum(df['PYQ_Year'] > 0)}")
        print(f"   - Numerical Types: {sum(df['Question type'] == 'Numerical type')}")
        
        with open(CONFIG_PATH, 'w') as f:
            json.dump({"last_unique_id": curr_id}, f, indent=4)

if __name__ == "__main__":
    run_extraction()