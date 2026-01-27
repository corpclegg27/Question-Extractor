import os
import glob
import pandas as pd
import pdfplumber
import json
import re
import time
import cv2
import csv
import numpy as np
from pdf2image import convert_from_path
from PIL import Image, ImageChops, ImageEnhance
try:
    from tqdm import tqdm
except ImportError:
    from tqdm.notebook import tqdm

# --- 1. CONFIGURATION ---
DEBUG_MODE = True  
CONFIG_PATH = 'config.json'
DEFAULT_BASE_PATH = 'D:/Main/3. Work - Teaching/Projects/Question extractor'

# *** NEW: ADD SPECIFIC FOLDERS HERE ***
# Leave empty [] to scan ALL folders starting with ATPH_NEET
SPECIFIC_TARGETS = [
    "ATPH_NEET_00209_4", 
    "ATPH_NEET_00199_2"
]

config = {}
if os.path.exists(CONFIG_PATH):
    with open(CONFIG_PATH, 'r') as f:
        config = json.load(f)
else:
    print(f"⚠️ Config not found. Using defaults.")

BASE_PATH = config.get('BASE_PATH', DEFAULT_BASE_PATH)
RAW_DATA_PATH = os.path.join(BASE_PATH, 'raw data') 
OUTPUT_BASE = os.path.join(BASE_PATH, 'Processed_Database')
DEBUG_DIR = os.path.join(OUTPUT_BASE, '_DEBUG_VIEWS')
CSV_LOG_PATH = os.path.join(OUTPUT_BASE, 'cutting_diagnostics.csv')
MASTER_DB_PATH = os.path.join(BASE_PATH, 'Question bank CD NEET.csv')

start_id = config.get('last_unique_id', config.get('latest_question_id', 0))

print(f"🔧 CONFIGURATION CHECK:")
print(f"   - Source Folder : {RAW_DATA_PATH}")
print(f"   - Debug Mode    : {'ON' if DEBUG_MODE else 'OFF'}")
if SPECIFIC_TARGETS:
    print(f"   - 🎯 TARGETING SPECIFIC FOLDERS: {SPECIFIC_TARGETS}")

os.makedirs(OUTPUT_BASE, exist_ok=True)
if DEBUG_MODE:
    os.makedirs(DEBUG_DIR, exist_ok=True)
    # Append mode for CSV log so we don't wipe previous runs
    if not os.path.exists(CSV_LOG_PATH):
        with open(CSV_LOG_PATH, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['Filename', 'Type', 'Original_W', 'Original_H', 'Cut_Pos', 'Limit_Pos', 'Reason'])

# --- 2. IMAGE PROCESSING CORE ---

def trim_whitespace(im):
    try:
        bg = Image.new(im.mode, im.size, im.getpixel((0,0)))
        diff = ImageChops.difference(im, bg)
        diff = ImageChops.add(diff, diff, 2.0, -100)
        bbox = diff.getbbox()
        if bbox: return im.crop(bbox)
        return im
    except Exception: return im

def log_debug(filename, img_type, w, h, cut, limit, reason):
    if not DEBUG_MODE: return
    try:
        with open(CSV_LOG_PATH, 'a', newline='') as f:
            writer = csv.writer(f)
            writer.writerow([filename, img_type, w, h, cut, limit, reason])
    except: pass

def save_debug_image(img_np, cut_pos, limit_pos, filename, img_type):
    if not DEBUG_MODE: return
    try:
        debug_img = img_np.copy()
        h, w = debug_img.shape[:2]
        
        if img_type == "Q":
            cv2.line(debug_img, (limit_pos, 0), (limit_pos, h), (255, 0, 0), 1) 
        elif img_type == "Sol":
            cv2.line(debug_img, (0, limit_pos), (w, limit_pos), (255, 0, 0), 1)

        if cut_pos > 0:
            if img_type == "Q":
                cv2.line(debug_img, (cut_pos, 0), (cut_pos, h), (0, 0, 255), 2)
            elif img_type == "Sol":
                cv2.line(debug_img, (0, cut_pos), (w, cut_pos), (0, 0, 255), 2)
            
        cv2.imwrite(os.path.join(DEBUG_DIR, f"DEBUG_{filename}"), debug_img)
    except Exception: pass

def process_image_smart(pil_img, img_type, filename_for_log="unknown"):
    try:
        img_np = cv2.cvtColor(np.array(pil_img), cv2.COLOR_RGB2BGR)
        height, width = img_np.shape[:2]
        
        gray = cv2.cvtColor(img_np, cv2.COLOR_BGR2GRAY)
        _, binary = cv2.threshold(gray, 200, 255, cv2.THRESH_BINARY_INV)
        kernel = np.ones((2,2), np.uint8)
        clean_binary = cv2.morphologyEx(binary, cv2.MORPH_OPEN, kernel, iterations=1)

        cut_val = 0
        limit_val = 0
        reason = "No Cut"

        if img_type == "Q":
            zone_width = int(width * 0.12)
            limit_val = zone_width
            roi = clean_binary[:, :zone_width]
            
            projection = np.sum(roi, axis=0)
            has_ink = projection > 0
            
            blocks = []
            in_block = False; start = 0
            for i, ink in enumerate(has_ink):
                if ink:
                    if not in_block: in_block = True; start = i
                else:
                    if in_block: blocks.append((start, i)); in_block = False
            
            if len(blocks) > 0:
                last_block_end = blocks[-1][1]
                if last_block_end < (zone_width - 3):
                    cut_val = last_block_end + 3
                    reason = "Gap found in Safe Zone"
                else:
                    reason = "Ink touches Safety Limit (Abort)"
            else:
                reason = "No Ink in Safe Zone"

            save_debug_image(img_np, cut_val, limit_val, filename_for_log, img_type)
            log_debug(filename_for_log, img_type, width, height, cut_val, limit_val, reason)

            if cut_val > 0:
                img_np = img_np[:, cut_val:]

        elif img_type == "Sol":
            scan_height = int(height * 0.30)
            limit_val = scan_height
            roi = clean_binary[:scan_height, :]
            projection = np.sum(roi, axis=1)
            has_ink = projection > 0
            
            blocks = []
            in_block = False; start = 0
            for i, ink in enumerate(has_ink):
                if ink:
                    if not in_block: in_block = True; start = i
                else:
                    if in_block: blocks.append((start, i)); in_block = False
            
            if len(blocks) > 0:
                header_end = blocks[0][1]
                if header_end < (height * 0.20):
                    cut_val = header_end + 5
                    reason = "Header Gap"
                else: reason = "Header too tall"
            
            save_debug_image(img_np, 0, cut_val, filename_for_log, img_type)
            log_debug(filename_for_log, img_type, width, height, cut_val, limit_val, reason)

            if cut_val > 0:
                img_np = img_np[cut_val:, :]

        final_pil = Image.fromarray(cv2.cvtColor(img_np, cv2.COLOR_BGR2GRAY))
        enhancer = ImageEnhance.Contrast(final_pil)
        final_pil = enhancer.enhance(1.3)
        return final_pil

    except Exception as e:
        print(f"Smart crop error: {e}")
        try: return pil_img.convert('L')
        except: return pil_img

# --- 3. HELPER FUNCTIONS ---

def find_anchors_robust(pdf_path, max_val=None, is_solution=False):
    anchors = []
    with pdfplumber.open(pdf_path) as pdf:
        for page_idx, page in enumerate(pdf.pages):
            width = page.width; midpoint = width / 2
            words = page.extract_words(keep_blank_chars=False)
            i = 0
            while i < len(words):
                curr_word = words[i]
                text = curr_word['text'].strip()
                x0 = curr_word['x0']
                col = 0 if x0 < midpoint else 1
                relative_x = x0 if col == 0 else (x0 - midpoint)
                found_q_num = None; is_strong_anchor = False 

                match = re.match(r'^(?:Q|Sol|Solution|S)?[\.\s]*(\d+)[\.\s:)]*$', text, re.IGNORECASE)
                if match:
                    found_q_num = int(match.group(1))
                    if text[0].isalpha(): is_strong_anchor = True
                elif text.lower() in ["q", "q.", "sol", "sol.", "solution", "solution:"] and i + 1 < len(words):
                    next_word = words[i+1]
                    match_next = re.match(r'^(\d+)[\.\s:)]*$', next_word['text'])
                    if match_next: found_q_num = int(match_next.group(1)); is_strong_anchor = True; i += 1 

                if found_q_num:
                    if max_val and found_q_num > max_val: found_q_num = None
                    else:
                        limit = 0.20 if is_strong_anchor else 0.05
                        if relative_x > (width * limit): found_q_num = None
                    if found_q_num: anchors.append({'q_num': found_q_num, 'page_idx': page_idx, 'top': curr_word['top'], 'col': col})
                i += 1
    unique_anchors = {}
    for a in anchors:
        if a['q_num'] not in unique_anchors: unique_anchors[a['q_num']] = a
    return sorted(unique_anchors.values(), key=lambda x: x['q_num'])

def extract_text_content(pdf_path, anchors, is_two_column=True):
    extracted_text = {}
    with pdfplumber.open(pdf_path) as pdf:
        pages = pdf.pages
        if not pages: return {}
        width = pages[0].width; height = pages[0].height
        midpoint = width / 2; BOTTOM_LIMIT = height * 0.92

        for i, start in enumerate(anchors):
            q_num = start['q_num']
            text_segments = []
            if i + 1 < len(anchors): end = anchors[i+1]
            else: end = {'page_idx': start['page_idx'], 'top': BOTTOM_LIMIT, 'col': start['col']}

            curr_pidx = start['page_idx']; curr_col = start['col']; curr_top = start['top']
            
            while True:
                page = pages[curr_pidx]
                if is_two_column:
                    x0 = 0 if curr_col == 0 else midpoint
                    x1 = midpoint if curr_col == 0 else width
                else: x0 = 0; x1 = width
                
                if curr_pidx == end['page_idx'] and curr_col == end['col']: bottom = end['top']; done = True
                else: bottom = BOTTOM_LIMIT; done = False
                
                if bottom > curr_top + 1:
                    try:
                        cropped_page = page.crop((x0, curr_top, x1, bottom))
                        text = cropped_page.extract_text()
                        if text: text_segments.append(text)
                    except Exception: pass
                if done: break
                
                if is_two_column:
                    if curr_col == 0: curr_col = 1; curr_top = 50 
                    else: curr_col = 0; curr_pidx += 1; curr_top = 50
                else: curr_pidx += 1; curr_top = 50
                if curr_pidx >= len(pages): break
            extracted_text[q_num] = "\n".join(text_segments).strip()
    return extracted_text

def crop_and_save_standard(pdf_path, anchors, output_folder, suffix_type, is_two_column=True):
    try: pdf_images = convert_from_path(pdf_path, dpi=300)
    except: return
    if not pdf_images: return
    
    page_width, page_height = pdf_images[0].size
    scale = 300 / 72 
    midpoint_px = (page_width / 2) 
    FOOTER_CUTOFF_PX = page_height * 0.92
    VERTICAL_PADDING = 15 
    TOP_MARGIN = 50 * scale 
    
    pbar = tqdm(total=len(anchors), desc=f"   📷 Cropping {suffix_type}", leave=True)
    for i, start in enumerate(anchors):
        q_num = start['q_num']
        if i + 1 < len(anchors): end = anchors[i+1]
        else: end = {'page_idx': start['page_idx'], 'top': FOOTER_CUTOFF_PX / scale, 'col': start['col']} 

        start_top_px = max(0, (start['top'] * scale) - VERTICAL_PADDING)
        end_top_px = (end['top'] * scale) - VERTICAL_PADDING

        try:
            images_to_stitch = []
            def safe_crop(img, coords):
                x1, y1, x2, y2 = coords
                if x2 > x1 and y2 > y1: return img.crop((x1, y1, x2, y2))
                return None

            if is_two_column:
                start_left = 0 if start['col'] == 0 else midpoint_px
                start_right = midpoint_px if start['col'] == 0 else page_width
                end_left = 0 if end['col'] == 0 else midpoint_px
                end_right = midpoint_px if end['col'] == 0 else page_width
            else:
                start_left = 0; start_right = page_width
                end_left = 0; end_right = page_width

            if start['page_idx'] == end['page_idx']:
                if start['col'] == end['col']:
                    bottom = min(end_top_px, FOOTER_CUTOFF_PX)
                    if bottom <= start_top_px: bottom = start_top_px + 100 
                    c = safe_crop(pdf_images[start['page_idx']], (start_left, start_top_px, start_right, bottom))
                    if c: images_to_stitch.append(c)
                else:
                    c1 = safe_crop(pdf_images[start['page_idx']], (start_left, start_top_px, start_right, FOOTER_CUTOFF_PX))
                    c2 = safe_crop(pdf_images[start['page_idx']], (end_left, TOP_MARGIN, end_right, end_top_px))
                    if c1: images_to_stitch.append(c1)
                    if c2: images_to_stitch.append(c2)
            else:
                c1 = safe_crop(pdf_images[start['page_idx']], (start_left, start_top_px, start_right, FOOTER_CUTOFF_PX))
                if c1: images_to_stitch.append(c1)
                for mid_idx in range(start['page_idx'] + 1, end['page_idx']):
                    cm = safe_crop(pdf_images[mid_idx], (start_left, TOP_MARGIN, start_right, FOOTER_CUTOFF_PX))
                    if cm: images_to_stitch.append(cm)
                if end_top_px > TOP_MARGIN:
                    c_end = safe_crop(pdf_images[end['page_idx']], (end_left, TOP_MARGIN, end_right, end_top_px))
                    if c_end: images_to_stitch.append(c_end)

            if images_to_stitch:
                total_height = sum(img.height for img in images_to_stitch)
                max_width = max(img.width for img in images_to_stitch)
                final_img = Image.new('RGB', (max_width, total_height), (255, 255, 255))
                y_offset = 0
                for img in images_to_stitch:
                    final_img.paste(img, (0, y_offset))
                    y_offset += img.height
                
                final_img = trim_whitespace(final_img)
                filename = f"{suffix_type}_{q_num}.png"
                final_img = process_image_smart(final_img, suffix_type, filename) 
                
                final_img.save(os.path.join(output_folder, filename), 
                               "PNG", optimize=True, compress_level=9)
                
        except Exception: pass
        pbar.update(1) 
    pbar.close()

# --- 4. EXECUTION ---
processed_folders = set()
if os.path.exists(MASTER_DB_PATH):
    try:
        df_existing = pd.read_csv(MASTER_DB_PATH, usecols=['Folder'])
        if 'Folder' in df_existing.columns:
            processed_folders = set(df_existing['Folder'].dropna().astype(str).unique())
    except: pass

all_subfolders = [f.path for f in os.scandir(RAW_DATA_PATH) if f.is_dir()]
target_folders = []

print(f"📂 Looking in 'raw data'...")

for folder_path in all_subfolders:
    clean_name = os.path.basename(folder_path).strip()
    
    # --- CHANGED: SPECIFIC TARGET LOGIC ---
    if SPECIFIC_TARGETS:
        # If we have specific targets, ignore "processed" list and force run these
        if clean_name in SPECIFIC_TARGETS:
            print(f"   ✅ FOUND TARGET: {clean_name}")
            target_folders.append(folder_path)
    else:
        # Default behavior: Scan all ATPH_NEET that are NOT processed
        if not clean_name.startswith("ATPH_NEET"): continue
        if clean_name in processed_folders: continue
        print(f"   ✅ FOUND NEW: {clean_name}")
        target_folders.append(folder_path)

if not target_folders:
    print(f"\n⚠️ No folders matching your criteria found.")
    exit()

current_global_id = start_id
for folder in tqdm(target_folders, desc="Processing Batches"):
    test_name = os.path.basename(folder).strip()
    print(f"\n🔹 Processing: {test_name}")
    
    q_papers = glob.glob(os.path.join(folder, "*question_paper.pdf"))
    sol_pdfs = glob.glob(os.path.join(folder, "*solution_pdf.pdf"))
    excel_keys = glob.glob(os.path.join(folder, "*excel_answer_key.xlsx")) + glob.glob(os.path.join(folder, "*excel_answer_key.csv"))

    if not (q_papers and sol_pdfs and excel_keys): continue

    try:
        key_path = excel_keys[0]
        key_df = pd.read_csv(key_path) if key_path.endswith('.csv') else pd.read_excel(key_path)
        total_questions = key_df['Question No.'].max() if 'Question No.' in key_df.columns else len(key_df)
        meta_df = pd.DataFrame({'Question No.': key_df['Question No.']})
        meta_df['Topic'] = "Unknown"; meta_df['Sub-Topic'] = "Unknown"; meta_df['Subject'] = "Unknown"
    except: continue
    
    test_output_dir = os.path.join(OUTPUT_BASE, test_name)
    os.makedirs(test_output_dir, exist_ok=True)
    
    q_anchors = find_anchors_robust(q_papers[0], max_val=total_questions)
    sol_anchors = find_anchors_robust(sol_pdfs[0], max_val=total_questions, is_solution=True)

    crop_and_save_standard(q_papers[0], q_anchors, test_output_dir, "Q", is_two_column=True)
    crop_and_save_standard(sol_pdfs[0], sol_anchors, test_output_dir, "Sol", is_two_column=True)

    print("   📝 Extracting Text...")
    extracted_text_map = extract_text_content(q_papers[0], q_anchors, is_two_column=True)

    meta_df['Folder'] = test_name
    if 'Question No.' in meta_df.columns and 'Question No.' in key_df.columns:
        combined_df = pd.merge(meta_df, key_df, on='Question No.', how='left', suffixes=('', '_key'))
    else: combined_df = pd.concat([meta_df.reset_index(drop=True), key_df.reset_index(drop=True)], axis=1)

    unique_ids_col = []; pdf_text_col = []; text_avail_col = []
    
    for idx, row in combined_df.iterrows():
        q_num = row.get('Question No.')
        if pd.isna(q_num): 
            unique_ids_col.append(None); pdf_text_col.append(None); text_avail_col.append("No")
            continue
        q_num = int(q_num)
        current_global_id += 1
        unique_ids_col.append(current_global_id)
        raw_text = extracted_text_map.get(q_num, "")
        cleaned_text = " ".join(re.sub(r'\b\S*_\S*\b', '', raw_text).split())
        if len(cleaned_text) < 30: pdf_text_col.append(""); text_avail_col.append("No")
        else: pdf_text_col.append(cleaned_text); text_avail_col.append("Yes")

    combined_df['unique_id'] = unique_ids_col
    combined_df['pdf_Text'] = pdf_text_col
    combined_df['PDF_Text_Available'] = text_avail_col
    combined_df['QC_Status'] = "Pass"
    combined_df.fillna("Unknown", inplace=True)
    combined_df = combined_df[combined_df['unique_id'].notna()]

    try:
        file_exists = os.path.exists(MASTER_DB_PATH)
        combined_df.to_csv(MASTER_DB_PATH, mode='a', header=not file_exists, index=False)
        print(f"   💾 Saved {len(combined_df)} rows.")
        config['last_unique_id'] = current_global_id
        with open(CONFIG_PATH, 'w') as f: json.dump(config, f, indent=4)
    except Exception as e: print(f"   ❌ Save Error: {e}")

print("\n🎉 Batch Processing Complete.")