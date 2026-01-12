import os
import glob
import pandas as pd
import pdfplumber
import json
import re
import time
import numpy as np
from pdf2image import convert_from_path
from PIL import Image, ImageChops, ImageOps
try:
    from tqdm import tqdm
except ImportError:
    from tqdm.notebook import tqdm

# --- 1. CONFIGURATION ---
CONFIG_PATH = 'config.json'
DEFAULT_BASE_PATH = 'D:/Main/3. Work - Teaching/Projects/Question extractor'

config = {}
if os.path.exists(CONFIG_PATH):
    with open(CONFIG_PATH, 'r') as f:
        config = json.load(f)

BASE_PATH = config.get('BASE_PATH', DEFAULT_BASE_PATH)
RAW_DATA_PATH = os.path.join(BASE_PATH, 'Raw data', 'CD JEE Adv') 
OUTPUT_BASE = os.path.join(BASE_PATH, 'Processed_Database')
MASTER_DB_PATH = os.path.join(BASE_PATH, 'Question Bank CD Adv.csv')

start_id = config.get('last_unique_id', 0)

print(f"🔧 CONFIGURATION:")
print(f"   - Input Folder  : {RAW_DATA_PATH}")
print(f"   - Output Folder : {OUTPUT_BASE}")
print(f"   - Master DB     : {MASTER_DB_PATH}")

os.makedirs(OUTPUT_BASE, exist_ok=True)


# --- 2. ADVANCED IMAGE PROCESSING UTILITIES ---

def trim_whitespace(im):
    try:
        bg = Image.new(im.mode, im.size, im.getpixel((0,0)))
        diff = ImageChops.difference(im, bg)
        diff = ImageChops.add(diff, diff, 2.0, -100)
        bbox = diff.getbbox()
        return im.crop(bbox) if bbox else im
    except Exception: return im

def compress_and_clean(img):
    """Standardizes to Grayscale and thresholds to remove gray noise."""
    try:
        gray = img.convert('L')
        return gray.point(lambda p: 255 if p > 190 else p)
    except Exception:
        return img

def pixel_sensitive_left_trim(img):
    """
    For QUESTIONS: Scans columns left-to-right.
    Removes the Question Number (e.g. 'Q.1') block and the whitespace after it.
    """
    try:
        # 1. Convert to binary (Invert so ink is high value)
        inverted_img = ImageOps.invert(img.convert('L'))
        data = np.array(inverted_img)
        
        # 2. Project vertically (sum of pixels in each column)
        horizontal_projection = np.sum(data, axis=0)
        width = len(horizontal_projection)
        
        crop_x = 0
        whitespace_count = 0
        in_number_block = False
        
        # 3. Scan columns (Start at 5 to skip edge artifacts)
        for x in range(5, width):
            # Threshold > 500 means 'Ink' is present in this column
            if horizontal_projection[x] > 500: 
                in_number_block = True
                whitespace_count = 0
            elif in_number_block:
                whitespace_count += 1
                # If we see 15px of whitespace AFTER seeing ink, cut here
                if whitespace_count >= 15: 
                    crop_x = x - whitespace_count + 4
                    break
        
        # Safety: Don't cut if logic fails or cuts > 25% of image
        if crop_x == 0 or crop_x > (width * 0.25): 
            crop_x = int(width * 0.02) # Minimal trim fallback
            
        return img.crop((crop_x, 0, width, img.size[1]))
    except:
        return img

def pixel_sensitive_top_trim(img):
    """
    For SOLUTIONS: Scans rows top-to-bottom.
    Removes the 'Solution' header block and the whitespace below it.
    """
    try:
        inverted_img = ImageOps.invert(img.convert('L'))
        data = np.array(inverted_img)
        
        # Project horizontally (sum of pixels in each row)
        vertical_projection = np.sum(data, axis=1)
        height = len(vertical_projection)
        
        crop_y = 0
        whitespace_count = 0
        in_header_block = False
        
        # Scan rows
        for y in range(5, height):
            if vertical_projection[y] > 500: # Ink detected
                in_header_block = True
                whitespace_count = 0
            elif in_header_block:
                whitespace_count += 1
                # If we see 10px whitespace AFTER header, cut here
                if whitespace_count >= 10:
                    crop_y = y - whitespace_count + 4
                    break
        
        # Safety: Don't cut > 30% of height
        if crop_y == 0 or crop_y > (height * 0.30):
            crop_y = 0
            
        return img.crop((0, crop_y, img.size[0], height))
    except:
        return img

def smart_footer_trim(img):
    """
    Scans from bottom-up. Trims rows that have ink ONLY on the right side.
    (Removes 'UD0001' style codes).
    """
    try:
        gray = img.convert('L')
        inverted = ImageOps.invert(gray)
        data = np.array(inverted)
        height, width = data.shape
        
        cutoff = height
        
        # Scan up from bottom
        for y in range(height - 1, -1, -1):
            row = data[y]
            # Check left 50% of the row for any ink
            left_half_ink = np.any(row[:int(width * 0.5)] > 50)
            
            if left_half_ink:
                # Found real content (text on left), stop trimming
                break
            else:
                # Left side is empty; trim this row
                cutoff = y
        
        if cutoff < height:
            return img.crop((0, 0, width, cutoff))
        return img
    except:
        return img


# --- 3. PDF PARSING LOGIC ---

def find_anchors_robust(pdf_path, max_val=None, is_solution=False):
    """Scans PDF for anchors (Q.1, Solution, etc.)"""
    anchors = []
    print(f"   🔍 Scanning {os.path.basename(pdf_path)}...")
    try:
        with pdfplumber.open(pdf_path) as pdf:
            for page_idx, page in enumerate(pdf.pages):
                width = page.width
                midpoint = width / 2
                
                words = page.extract_words(keep_blank_chars=False)
                i = 0
                while i < len(words):
                    curr_word = words[i]
                    text = curr_word['text'].strip()
                    x0 = curr_word['x0']
                    
                    col = 0 if x0 < midpoint else 1
                    relative_x = x0 if col == 0 else (x0 - midpoint)
                    
                    found_q_num = None
                    is_strong = False

                    # Pattern 1: Combined "Q.1"
                    match = re.match(r'^(?:Q|S|Sol|Solution)?[\.\s]*(\d+)[\.\s:)]*$', text, re.IGNORECASE)
                    if match:
                        found_q_num = int(match.group(1))
                        if text[0].isalpha(): is_strong = True
                    
                    # Pattern 2: Split "Q" ... "1"
                    elif text.lower() in ["q", "q.", "sol", "solution", "question"] and i + 1 < len(words):
                        next_word = words[i+1]
                        match_next = re.match(r'^(\d+)[\.\s:)]*$', next_word['text'])
                        if match_next:
                            found_q_num = int(match_next.group(1))
                            is_strong = True
                            i += 1 

                    if found_q_num:
                        valid = True
                        if max_val and found_q_num > max_val: valid = False
                        
                        # Tolerance: Solutions often have less strict indentation
                        threshold = width * 0.25 if (is_strong or is_solution) else width * 0.10
                        if relative_x > threshold: valid = False

                        if valid:
                            anchors.append({
                                'q_num': found_q_num, 'page_idx': page_idx, 
                                'top': curr_word['top'], 'col': col
                            })
                    i += 1

        unique = {}
        for a in anchors:
            if a['q_num'] not in unique: unique[a['q_num']] = a
        return sorted(unique.values(), key=lambda x: x['q_num'])
        
    except Exception as e:
        print(f"      ❌ Error reading PDF: {e}")
        return []

def extract_text_content(pdf_path, anchors, is_two_column=True):
    extracted_text = {}
    try:
        with pdfplumber.open(pdf_path) as pdf:
            pages = pdf.pages
            if not pages: return {}
            
            width = pages[0].width; height = pages[0].height; midpoint = width / 2
            BOTTOM_LIMIT = height * 0.92

            for i, start in enumerate(anchors):
                q_num = start['q_num']
                text_segments = []
                
                if i + 1 < len(anchors):
                    end = anchors[i+1]
                else:
                    end = {'page_idx': start['page_idx'], 'top': BOTTOM_LIMIT, 'col': start['col']}

                curr_pidx = start['page_idx']; curr_col = start['col']; curr_top = start['top']
                
                while True:
                    if curr_pidx >= len(pages): break
                    page = pages[curr_pidx]
                    
                    x0 = 0 if curr_col == 0 else midpoint
                    x1 = midpoint if curr_col == 0 else width
                    
                    if curr_pidx == end['page_idx'] and curr_col == end['col']:
                        bottom = end['top']; done = True
                    else:
                        bottom = BOTTOM_LIMIT; done = False
                    
                    if bottom > curr_top:
                        try:
                            txt = page.crop((x0, curr_top, x1, bottom)).extract_text()
                            if txt: text_segments.append(txt)
                        except: pass
                    
                    if done: break
                    if curr_col == 0: curr_col = 1; curr_top = 50 
                    else: curr_col = 0; curr_pidx += 1; curr_top = 50
                
                extracted_text[q_num] = "\n".join(text_segments).strip()
        return extracted_text
    except: return {}

def crop_and_save_standard(pdf_path, anchors, output_folder, suffix_type, is_two_column=True):
    try: 
        pdf_images = convert_from_path(pdf_path, dpi=300)
    except Exception as e: 
        print(f"   ❌ Image Conversion Error: {e}"); return

    if not pdf_images: return
    
    page_width, page_height = pdf_images[0].size
    scale = 300 / 72 
    midpoint_px = (page_width / 2) 
    FOOTER_CUTOFF_PX = page_height * 0.92
    TOP_MARGIN = 50 * scale 
    
    pbar = tqdm(total=len(anchors), desc=f"   📷 Cropping {suffix_type}", leave=True)
    
    for i, start in enumerate(anchors):
        q_num = start['q_num']
        
        if i + 1 < len(anchors): 
            end = anchors[i+1]
        else: 
            end = {'page_idx': start['page_idx'], 'top': FOOTER_CUTOFF_PX / scale, 'col': start['col']} 

        start_top_px = max(0, (start['top'] * scale) - 15)
        end_top_px = (end['top'] * scale) - 15

        images_to_stitch = []
        
        def get_crop(pidx, col, top_px, bottom_px):
            left = 0 if col == 0 else midpoint_px
            right = midpoint_px if col == 0 else page_width
            if bottom_px <= top_px: bottom_px = top_px + 50
            return pdf_images[pidx].crop((left, top_px, right, bottom_px))

        # Stitching Logic
        if start['page_idx'] == end['page_idx']:
            if start['col'] == end['col']:
                bottom = min(end_top_px, FOOTER_CUTOFF_PX)
                images_to_stitch.append(get_crop(start['page_idx'], start['col'], start_top_px, bottom))
            else:
                images_to_stitch.append(get_crop(start['page_idx'], start['col'], start_top_px, FOOTER_CUTOFF_PX))
                images_to_stitch.append(get_crop(start['page_idx'], end['col'], TOP_MARGIN, end_top_px))
        else:
            images_to_stitch.append(get_crop(start['page_idx'], start['col'], start_top_px, FOOTER_CUTOFF_PX))
            if end_top_px > TOP_MARGIN:
                    images_to_stitch.append(get_crop(end['page_idx'], end['col'], TOP_MARGIN, end_top_px))

        if images_to_stitch:
            # 1. Stitch
            total_h = sum(img.height for img in images_to_stitch)
            max_w = max(img.width for img in images_to_stitch)
            final_img = Image.new('RGB', (max_w, total_h), (255, 255, 255))
            y_off = 0
            for img in images_to_stitch:
                final_img.paste(img, (0, y_off))
                y_off += img.height
            
            # 2. Trim whitespace before advanced logic
            final_img = trim_whitespace(final_img)

            # 3. Apply Targeted Trimming
            if suffix_type == "Q":
                final_img = pixel_sensitive_left_trim(final_img) # Remove "Q.1" from left
            elif suffix_type == "Sol":
                final_img = pixel_sensitive_top_trim(final_img) # Remove "Solution:" from top
            
            # 4. Remove Footer from both
            final_img = smart_footer_trim(final_img)

            # 5. Final Clean & Save
            final_img = compress_and_clean(trim_whitespace(final_img))
            
            filename = f"{suffix_type}_{q_num}.png"
            final_img.save(os.path.join(output_folder, filename), optimize=True)
                
        pbar.update(1)
    pbar.close()


# --- 4. MAIN WORKFLOW ---

print(f"\n--- 🔍 SCANNING ---")
if not os.path.exists(RAW_DATA_PATH):
    print(f"❌ CRITICAL: Folder not found: {RAW_DATA_PATH}"); exit()

batch_groups = {}
for f in os.listdir(RAW_DATA_PATH):
    if f.lower().endswith(('.pdf', '.xlsx', '.csv')):
        parts = f.split('-')
        if len(parts) > 1:
            title = parts[0].strip()
            if title not in batch_groups:
                batch_groups[title] = {'QP': None, 'SOL': None, 'KEY': None}
            
            full_path = os.path.join(RAW_DATA_PATH, f)
            lower_name = f.lower()
            if 'question_paper' in lower_name and lower_name.endswith('.pdf'):
                batch_groups[title]['QP'] = full_path
            elif 'solution' in lower_name and lower_name.endswith('.pdf'):
                batch_groups[title]['SOL'] = full_path
            elif 'answer_key' in lower_name and lower_name.endswith(('.xlsx', '.csv')):
                batch_groups[title]['KEY'] = full_path

valid_batches = {k: v for k, v in batch_groups.items() if v['QP'] and v['KEY']} 
print(f"✅ Found {len(valid_batches)} valid batches.")

current_global_id = start_id
new_data_list = []

final_master_df = pd.DataFrame()
if os.path.exists(MASTER_DB_PATH):
    try: final_master_df = pd.read_csv(MASTER_DB_PATH)
    except: pass

for title, files in tqdm(valid_batches.items(), desc="Processing Batches", leave=True):
    print(f"\n🔹 Processing: {title}")
    
    qp_path = files['QP']; sol_path = files['SOL']; key_path = files['KEY']
    
    try:
        if key_path.endswith('.csv'): key_df = pd.read_csv(key_path)
        else: key_df = pd.read_excel(key_path)
        key_df.columns = [str(c).strip() for c in key_df.columns]
        if 'Question No.' not in key_df.columns:
            key_df.rename(columns={key_df.columns[0]: 'Question No.'}, inplace=True)
        total_questions = key_df['Question No.'].max()
    except Exception as e:
        print(f"   ❌ Error reading Key: {e}"); continue

    test_output_dir = os.path.join(OUTPUT_BASE, title)
    os.makedirs(test_output_dir, exist_ok=True)
    
    print("   📍 Finding Anchors...")
    q_anchors = find_anchors_robust(qp_path, max_val=total_questions)
    
    sol_anchors = []
    if sol_path:
        sol_anchors = find_anchors_robust(sol_path, max_val=total_questions, is_solution=True)
    
    if not q_anchors: print(f"   ⚠️ No anchors found in QP. Skipping."); continue

    # Process Images
    crop_and_save_standard(qp_path, q_anchors, test_output_dir, "Q", is_two_column=True)
    if sol_path:
        crop_and_save_standard(sol_path, sol_anchors, test_output_dir, "Sol", is_two_column=True)

    print("   📝 Extracting Text...")
    text_map = extract_text_content(qp_path, q_anchors, is_two_column=True)
    
    # Metadata Construction
    batch_rows = []
    for idx, row in key_df.iterrows():
        try:
            q_num = int(row['Question No.'])
            correct_ans = row.get('Correct Answer', '')
            subject = row.get('Subject', 'Unknown')
            
            raw_txt = text_map.get(q_num, "")
            clean_txt = " ".join(raw_txt.split())
            
            current_global_id += 1
            
            entry = {
                'unique_id': current_global_id,
                'Question No.': q_num,
                'Folder': title,
                'Subject': subject,
                'Chapter': 'Unknown',
                'Topic': 'Unknown',
                'Topic_L2': 'Unknown',
                'Question type': 'One or more more options correct',
                'Correct Answer': correct_ans,
                'Source File': os.path.basename(qp_path),
                'pdf_Text': clean_txt,
                'PDF_Text_Available': 'Yes' if len(clean_txt) > 20 else 'No',
                'QC_Status': 'Pass',
                'image_url': f"Q_{q_num}.png"
            }
            batch_rows.append(entry)
        except: pass

    if batch_rows: new_data_list.extend(batch_rows)

print("\n--- Finalizing ---")
if new_data_list:
    new_df = pd.DataFrame(new_data_list)
    if not final_master_df.empty:
        updated_master = pd.concat([final_master_df, new_df], ignore_index=True)
    else:
        updated_master = new_df
        
    updated_master.to_csv(MASTER_DB_PATH, index=False)
    print(f"✅ Master DB Saved: {MASTER_DB_PATH}")
    
    config['last_unique_id'] = current_global_id
    with open(CONFIG_PATH, 'w') as f: json.dump(config, f, indent=4)
else:
    print("⚠️ No new data.")