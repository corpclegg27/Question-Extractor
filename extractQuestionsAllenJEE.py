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
ALLEN_CSV_PATH = os.path.join(BASE_PATH, 'Question Bank Allen JEE.csv')
INPUT_CSV_PATH = os.path.join(BASE_PATH, 'Question Bank Allen JEE - Inputs.csv')
RAW_DATA_DIR = os.path.join(BASE_PATH, 'Raw data')
TRIMMED_DIR = os.path.join(RAW_DATA_DIR, 'Trimmed_PDFs')
PROCESSED_BASE = os.path.join(BASE_PATH, 'Processed_Database')

os.makedirs(TRIMMED_DIR, exist_ok=True)
os.makedirs(PROCESSED_BASE, exist_ok=True)

# --- 2. IMAGE & PIXEL UTILITIES ---
def pixel_sensitive_crop(img):
    """Dynamic cropping using vertical pixel projection to strip question numbers."""
    inverted_img = ImageOps.invert(img.convert('L'))
    data = np.array(inverted_img)
    horizontal_projection = np.sum(data, axis=0)
    width = len(horizontal_projection)
    
    crop_x, whitespace_count, in_number_block = 0, 0, False
    for x in range(5, width):
        if horizontal_projection[x] > 500: # Threshold for 'ink'
            in_number_block = True
            whitespace_count = 0
        elif in_number_block:
            whitespace_count += 1
            if whitespace_count >= 15: # Detected whitespace gap after question number
                crop_x = x - whitespace_count + 2
                break
    
    # Safety fallback: if detection fails or is too deep (over 30% of width)
    if crop_x == 0 or crop_x > (width * 0.30): 
        crop_x = int(width * 0.05)
    return img.crop((crop_x, 0, width, img.size[1]))

def trim_whitespace(im):
    try:
        bg = Image.new(im.mode, im.size, im.getpixel((0,0)))
        diff = ImageChops.difference(im, bg)
        diff = ImageChops.add(diff, diff, 2.0, -100)
        bbox = diff.getbbox()
        return im.crop(bbox) if bbox else im
    except: return im

def compress_and_clean(img):
    """Applies Grayscale conversion and noise thresholding for mobile app optimization."""
    gray = img.convert('L')
    return gray.point(lambda p: 255 if p > 170 else p)

# --- 3. PDF TEXT EXTRACTION ---
def capture_text_from_area(pdf_path, start_anchor, end_anchor, footer_val):
    """Extracts raw machine text from specific PDF coordinates."""
    extracted_text = ""
    try:
        with pdfplumber.open(pdf_path) as pdf:
            page = pdf.pages[start_anchor['page_idx']]
            mid = page.width / 2
            left = 0 if start_anchor['col'] == 0 else mid
            right = mid if start_anchor['col'] == 0 else page.width
            
            if start_anchor['page_idx'] == end_anchor['page_idx'] and start_anchor['col'] == end_anchor['col']:
                bbox = (left, start_anchor['top'], right, max(start_anchor['top']+1, end_anchor['top']))
                extracted_text = page.within_bbox(bbox).extract_text() or ""
            else:
                bbox_a = (left, start_anchor['top'], right, footer_val)
                extracted_text += (page.within_bbox(bbox_a).extract_text() or "") + " "
                
                t_page = pdf.pages[end_anchor['page_idx']]
                t_mid = t_page.width / 2
                t_left = 0 if end_anchor['col'] == 0 else t_mid
                t_right = t_mid if end_anchor['col'] == 0 else t_page.width
                bbox_b = (t_left, 50, t_right, end_anchor['top'])
                extracted_text += (t_page.within_bbox(bbox_b).extract_text() or "")
    except: pass
    return " ".join(extracted_text.split())

def parse_answers(pdf_path):
    ans_map = {}
    letter_map = {"1":"A","2":"B","3":"C","4":"D"}
    with pdfplumber.open(pdf_path) as pdf:
        text = pdf.pages[-1].extract_text()
        if not text or "ANSWER KEY" not in text.upper(): return {}
        que_lines = [l for l in text.split('\n') if l.startswith('Que.')]
        ans_lines = [l for l in text.split('\n') if l.startswith('Ans.')]
        for q_l, a_l in zip(que_lines, ans_lines):
            for q, a in zip(re.findall(r'\d+', q_l), re.findall(r'\d+', a_l)):
                ans_map[int(q)] = letter_map.get(a, a)
    return ans_map

# --- 4. THE BATCH PROCESSOR ---
def run_batch_extraction(row_data, source_pdf):
    start_p, end_p = int(row_data['pdf_start_pg']), int(row_data['pdf_end_pg'])
    chapter, subject = row_data['Chapter'], row_data['Subject']
    
    print(f"\n🚀 STARTING BATCH: {chapter} (Pages {start_p}-{end_p})")
    
    # 1. Trim PDF
    input_path = os.path.join(RAW_DATA_DIR, source_pdf)
    trimmed_name = f"Temp_Trimmed_{chapter}_{start_p}.pdf".replace(" ", "_")
    trimmed_path = os.path.join(TRIMMED_DIR, trimmed_name)
    
    reader = PdfReader(input_path); writer = PdfWriter()
    for i in range(start_p - 1, min(end_p, len(reader.pages))):
        writer.add_page(reader.pages[i])
    with open(trimmed_path, "wb") as f: writer.write(f)

    # 2. Config & Output Setup
    with open(CONFIG_PATH, 'r') as f: config = json.load(f)
    curr_id = int(config.get("last_unique_id", 0))
    # Using the trimmed name (folder-safe) for image directory
    folder_name = trimmed_name.replace(".pdf", "")
    output_dir = os.path.join(PROCESSED_BASE, folder_name)
    os.makedirs(output_dir, exist_ok=True)

    # 3. Detect Anchors
    ans_map = parse_answers(trimmed_path)
    anchors = []
    with pdfplumber.open(trimmed_path) as pdf:
        footer_limit = pdf.pages[0].height * 0.91
        for p_idx, page in enumerate(pdf.pages):
            mid = page.width / 2
            for word in page.extract_words():
                if re.match(r'^\d+\.$', word['text']):
                    rel_x = word['x0'] if word['x0'] < mid else (word['x0'] - mid)
                    if rel_x < (page.width * 0.12): # Stricter column margin
                        anchors.append({'q_num': int(word['text'].replace('.','')), 
                                        'page_idx': p_idx, 'top': word['top'], 
                                        'col': 0 if word['x0'] < mid else 1})
    
    anchors = sorted(anchors, key=lambda x: (x['page_idx'], x['col'], x['top']))
    pdf_images = convert_from_path(trimmed_path, dpi=300)
    scale = 300/72
    
    # 4. Loop through questions
    rows = []
    for i, start in tqdm(enumerate(anchors), total=len(anchors), desc=f"   ✂️ {chapter[:15]}"):
        try:
            nxt = anchors[i+1] if i+1 < len(anchors) else {'page_idx': start['page_idx'], 'top': footer_limit, 'col': start['col']}
            
            # --- COORDINATE VALIDATION ---
            y1_val = max(0, (start['top'] * scale) - 15)
            # If logic breaks (next anchor detected above current), cap at footer
            if nxt['page_idx'] == start['page_idx'] and nxt['col'] == start['col'] and nxt['top'] <= start['top']:
                y2_val = footer_limit * scale
            else:
                y2_val = (nxt['top'] * scale) - 15

            mid_px = pdf_images[0].size[0]/2
            l, r = (0, mid_px) if start['col'] == 0 else (mid_px, pdf_images[0].size[0])
            
            # Stitching
            if start['page_idx'] == nxt['page_idx'] and start['col'] == nxt['col']:
                safe_y2 = max(y1_val + 10, min(y2_val, footer_limit * scale))
                stitched = pdf_images[start['page_idx']].crop((l, y1_val, r, safe_y2))
            else:
                stitched = pdf_images[start['page_idx']].crop((l, y1_val, r, footer_limit*scale))

            # Dynamic Content Trimming & Compression
            final_img = compress_and_clean(trim_whitespace(pixel_sensitive_crop(trim_whitespace(stitched))))
            img_w, img_h = final_img.size
            final_img.save(os.path.join(output_dir, f"Q_{start['q_num']}.png"), optimize=True)

            # Build Metadata Row
            curr_id += 1
            raw_text = capture_text_from_area(trimmed_path, start, nxt, footer_limit)
            rows.append({
                'unique_id': curr_id, 'Question No.': start['q_num'], 'Q': start['q_num'], 
                'Folder': folder_name, 'Subject': subject, 'Chapter': chapter, 
                'Topic': row_data.get('Topic', 'Unknown'), 'Topic_L2': row_data.get('Topic_L2', 'Unknown'),
                'Correct Answer': ans_map.get(start['q_num'], ""), 'QC_Status': 'Pending QC', 
                'Exam': row_data.get('Exam', 'NEET'), 'PYQ': row_data.get('PYQ', 'No'), 
                'Difficulty': row_data.get('Difficulty', 'Unknown'),
                'q_width': img_w, 'q_height': img_h,
                'pdf_Text': raw_text, 'PDF_Text_Available': 'Yes' if len(raw_text) > 10 else 'No'
            })
        except Exception as e:
            print(f"⚠️ Skipping Q {start.get('q_num')}: {e}")

    # 5. Incremental DB Save
    df_new = pd.DataFrame(rows)
    if os.path.exists(ALLEN_CSV_PATH):
        pd.concat([pd.read_csv(ALLEN_CSV_PATH), df_new], ignore_index=True).to_csv(ALLEN_CSV_PATH, index=False)
    else: df_new.to_csv(ALLEN_CSV_PATH, index=False)
    
    # 6. Update Unique ID Config
    config["last_unique_id"] = curr_id
    with open(CONFIG_PATH, 'w') as f: json.dump(config, f, indent=4)

    # 7. CLEANUP: Auto-delete the temporary PDF
    if os.path.exists(trimmed_path):
        os.remove(trimmed_path)
        print(f"🗑️ Deleted temporary file: {trimmed_name}")

    return True

# --- 5. MAIN LOOP ---
if __name__ == "__main__":
    SOURCE_PDF = "ALLEN PHYSICS CLASS 12TH 2026 MODULE.pdf"
    
    if not os.path.exists(INPUT_CSV_PATH):
        print(f"❌ Error: Input CSV not found at {INPUT_CSV_PATH}")
    else:
        input_df = pd.read_csv(INPUT_CSV_PATH)
        if 'isProcessed' not in input_df.columns:
            input_df['isProcessed'] = 'No'
        
        pending_batches = input_df[input_df['isProcessed'] != 'Yes']
        print(f"📋 Found {len(pending_batches)} batches to process.")
        
        for index, row in pending_batches.iterrows():
            try:
                if run_batch_extraction(row, SOURCE_PDF):
                    input_df.at[index, 'isProcessed'] = 'Yes'
                    input_df.to_csv(INPUT_CSV_PATH, index=False)
                    print(f"✅ Success: Batch {index} marked as Processed.")
            except Exception as e:
                print(f"❌ Batch failure at row {index}: {e}")
        
        print("\n🏁 ALL TASKS FINISHED.")