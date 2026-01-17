import os
import glob
import pandas as pd
import pdfplumber
import json
import re
import time
import numpy as np
import fitz  # PyMuPDF
from pypdf import PdfReader, PdfWriter
from PIL import Image, ImageChops, ImageOps, ImageEnhance
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


# --- 2. UTILITIES ---

def sanitize_filename(name):
    """Ensure folder name is safe for Windows/Linux."""
    # Remove invalid chars: < > : " / \ | ? *
    name = re.sub(r'[<>:"/\\|?*]', '', name)
    return name.strip()

def trim_whitespace(im):
    try:
        bg = Image.new("RGB", im.size, (255, 255, 255))
        diff = ImageChops.difference(im.convert("RGB"), bg)
        diff = ImageChops.add(diff, diff, 2.0, -100)
        bbox = diff.getbbox()
        return im.crop(bbox) if bbox else im
    except Exception: return im

def compress_and_clean(img):
    try:
        img = img.convert('L')
        enhancer = ImageEnhance.Contrast(img)
        img = enhancer.enhance(1.3) 
        img = img.quantize(colors=32, method=2, dither=Image.NONE)
        return img
    except Exception:
        return img

def pixel_sensitive_left_trim(img):
    try:
        inverted_img = ImageOps.invert(img.convert('L'))
        data = np.array(inverted_img)
        horizontal_projection = np.sum(data, axis=0)
        width = len(horizontal_projection)
        
        crop_x = 0
        whitespace_count = 0
        in_number_block = False
        
        for x in range(5, width):
            if horizontal_projection[x] > 500: 
                in_number_block = True
                whitespace_count = 0
            elif in_number_block:
                whitespace_count += 1
                if whitespace_count >= 15: 
                    crop_x = x - whitespace_count + 4
                    break
        
        if crop_x == 0 or crop_x > (width * 0.25): 
            crop_x = int(width * 0.02)
            
        return img.crop((crop_x, 0, width, img.size[1]))
    except:
        return img

def pixel_sensitive_top_trim(img):
    try:
        inverted_img = ImageOps.invert(img.convert('L'))
        data = np.array(inverted_img)
        vertical_projection = np.sum(data, axis=1)
        height = len(vertical_projection)
        
        crop_y = 0
        whitespace_count = 0
        in_header_block = False
        
        for y in range(5, height):
            if vertical_projection[y] > 500: 
                in_header_block = True
                whitespace_count = 0
            elif in_header_block:
                whitespace_count += 1
                if whitespace_count >= 10:
                    crop_y = y - whitespace_count + 4
                    break
        
        if crop_y == 0 or crop_y > (height * 0.30):
            crop_y = 0
            
        return img.crop((0, crop_y, img.size[0], height))
    except:
        return img

def smart_footer_trim(img):
    try:
        gray = img.convert('L')
        bw = gray.point(lambda p: 0 if p > 150 else 1, mode='1')
        data = np.array(bw)
        height, width = data.shape
        cutoff = height
        
        for y in range(height - 1, -1, -1):
            row = data[y]
            left_half_ink = np.any(row[:int(width * 0.5)])
            if left_half_ink:
                break
            else:
                cutoff = y
        
        if cutoff < height:
            return img.crop((0, 0, width, cutoff))
        return img
    except:
        return img


# --- 3. PDF PARSING ---

def is_bold(word):
    fontname = word.get('fontname', '').lower()
    return 'bold' in fontname or 'bd' in fontname or 'black' in fontname

def find_anchors_robust(pdf_path, max_val=None, is_solution=False):
    anchors = []
    print(f"   🔍 Scanning {os.path.basename(pdf_path)}...")
    try:
        with pdfplumber.open(pdf_path) as pdf:
            for page_idx, page in enumerate(pdf.pages):
                width = page.width
                midpoint = width / 2
                words = page.extract_words(keep_blank_chars=False, extra_attrs=["fontname", "size"])
                
                col1_words = [w for w in words if w['x0'] < midpoint]
                col2_words = [w for w in words if w['x0'] >= midpoint]
                
                for col_idx, col_words in enumerate([col1_words, col2_words]):
                    i = 0
                    while i < len(col_words):
                        curr_word = col_words[i]
                        text = curr_word['text'].strip()
                        relative_x = curr_word['x0'] - (midpoint if col_idx == 1 else 0)
                        found_q_num = None
                        
                        match_explicit = re.match(r'^(?:Q|Sol|Solution)[\.\-\s]*(\d+)[\.\s:)]*$', text, re.IGNORECASE)
                        match_loose = re.match(r'^(\d+)[\.\s:)]*$', text)
                        
                        if match_explicit:
                            found_q_num = int(match_explicit.group(1))
                        elif match_loose:
                            num = int(match_loose.group(1))
                            is_at_margin = relative_x < 40 
                            is_year = num > 1900 and num < 2100
                            is_bold_font = is_bold(curr_word)
                            if is_at_margin and not is_year:
                                if is_bold_font or text.endswith('.'):
                                    found_q_num = num
                                    
                        if found_q_num:
                            if max_val and found_q_num > max_val: found_q_num = None
                            if found_q_num:
                                anchors.append({'q_num': found_q_num, 'page_idx': page_idx, 'top': curr_word['top'], 'col': col_idx})
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
                if i + 1 < len(anchors): end = anchors[i+1]
                else: end = {'page_idx': start['page_idx'], 'top': BOTTOM_LIMIT, 'col': start['col']}

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
    print(f"   🖼️ Rendering with PyMuPDF (High Quality)...")
    try:
        doc = fitz.open(pdf_path)
    except Exception as e:
        print(f"   ❌ PDF Open Error: {e}"); return

    ZOOM = 300 / 72 
    mat = fitz.Matrix(ZOOM, ZOOM)
    
    first_page = doc[0]
    page_width_pts = first_page.rect.width
    page_height_pts = first_page.rect.height
    midpoint_pts = page_width_pts / 2
    FOOTER_CUTOFF_PTS = page_height_pts * 0.92
    TOP_MARGIN_PTS = 50 
    
    pbar = tqdm(total=len(anchors), desc=f"   📷 Cropping {suffix_type}", leave=True)
    
    for i, start in enumerate(anchors):
        q_num = start['q_num']
        
        if i + 1 < len(anchors): 
            end = anchors[i+1]
            if end['page_idx'] == start['page_idx'] and end['col'] == start['col']:
                limit_bottom = end['top'] - 5 
            else:
                limit_bottom = FOOTER_CUTOFF_PTS
        else: 
            limit_bottom = FOOTER_CUTOFF_PTS

        start_top_pts = max(0, start['top'] - 5)
        images_to_stitch = []
        
        def get_crop(pidx, col, top_pts, bottom_pts):
            left = 0 if col == 0 else midpoint_pts
            right = midpoint_pts if col == 0 else page_width_pts
            if bottom_pts <= top_pts: bottom_pts = top_pts + 100 
            rect = fitz.Rect(left, top_pts, right, bottom_pts)
            page = doc[pidx]
            pix = page.get_pixmap(matrix=mat, clip=rect, alpha=False)
            return Image.frombytes("RGB", [pix.width, pix.height], pix.samples)

        if start['page_idx'] == end['page_idx'] if i+1<len(anchors) else True: 
             if (i+1 >= len(anchors)) or (end['page_idx'] != start['page_idx']) or (end['col'] != start['col']):
                 images_to_stitch.append(get_crop(start['page_idx'], start['col'], start_top_pts, FOOTER_CUTOFF_PTS))
             else:
                 images_to_stitch.append(get_crop(start['page_idx'], start['col'], start_top_pts, limit_bottom))
        
        if images_to_stitch:
            total_h = sum(img.height for img in images_to_stitch)
            max_w = max(img.width for img in images_to_stitch)
            final_img = Image.new('RGB', (max_w, total_h), (255, 255, 255))
            y_off = 0
            for img in images_to_stitch:
                final_img.paste(img, (0, y_off))
                y_off += img.height
            
            final_img = trim_whitespace(final_img)
            
            if suffix_type == "Q":
                final_img = pixel_sensitive_left_trim(final_img)
            elif suffix_type == "Sol":
                final_img = pixel_sensitive_top_trim(final_img)
            
            #final_img = smart_footer_trim(final_img)
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
            raw_title = parts[0].strip()
            # Ensure folder name is safe and distinct
            title = sanitize_filename(raw_title)
            
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

    # Create safe output folder
    test_output_dir = os.path.join(OUTPUT_BASE, title)
    os.makedirs(test_output_dir, exist_ok=True)
    print(f"   📂 Output Directory: {test_output_dir}")
    
    print("   📍 Finding Anchors...")
    q_anchors = find_anchors_robust(qp_path, max_val=total_questions)
    
    sol_anchors = []
    if sol_path:
        sol_anchors = find_anchors_robust(sol_path, max_val=total_questions, is_solution=True)
    
    if not q_anchors: print(f"   ⚠️ No anchors found in QP. Skipping."); continue

    crop_and_save_standard(qp_path, q_anchors, test_output_dir, "Q", is_two_column=True)
    if sol_path:
        crop_and_save_standard(sol_path, sol_anchors, test_output_dir, "Sol", is_two_column=True)

    print("   📝 Extracting Text...")
    text_map = extract_text_content(qp_path, q_anchors, is_two_column=True)
    
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
                'Subject': 'Physics',
                'Exam':'JEE Advanced',
                'Chapter': 'Unknown',
                'Topic': 'Unknown',
                'Topic_L2': 'Unknown',
                'Question type': 'Unknown',
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