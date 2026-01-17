import os
import re
import json
import numpy as np
import pandas as pd
from pypdf import PdfReader, PdfWriter
import pdfplumber
import fitz  # PyMuPDF: The new, superior renderer
from PIL import Image, ImageChops, ImageOps, ImageEnhance
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

# --- 2. IMAGE UTILITIES ---

def compress_and_clean(img):
    """
    NON-DESTRUCTIVE COMPRESSION:
    Old logic wiped thin lines. New logic:
    1. Convert to Grayscale.
    2. Slight Contrast Boost (make thin lines darker).
    3. Quantize to 32 colors (Keep visual quality, drop file size).
    """
    try:
        # 1. Grayscale
        img = img.convert('L')
        
        # 2. Contrast Boost (Helps thin lines stand out against background)
        enhancer = ImageEnhance.Contrast(img)
        img = enhancer.enhance(1.3) 
        
        # 3. Quantize (The key to size reduction without data loss)
        # We allow 32 shades of gray. This preserves anti-aliasing (smooth lines)
        # while removing the millions of colors that bloat file size.
        img = img.quantize(colors=32, method=2, dither=Image.NONE)
        
        return img
    except:
        return img

def smart_left_number_trim(img):
    """Scans Left-to-Right. Crops if Bottom Half is empty (< 5%)."""
    try:
        gray = img.convert('L')
        # Binarize just for analysis (not for final output)
        bw = gray.point(lambda p: 0 if p > 150 else 1, mode='1')
        data = np.array(bw)
        
        height, width = data.shape
        mid_h = height // 2
        crop_x = 0
        scan_limit = int(width * 0.25)
        
        for x in range(scan_limit):
            col = data[:, x]
            bottom_half = col[mid_h:]
            ink = np.count_nonzero(bottom_half)
            density = ink / bottom_half.size if bottom_half.size > 0 else 0
            
            if density < 0.05:
                crop_x = x
            else:
                break
        
        if crop_x > 0:
            return img.crop((crop_x + 2, 0, width, height))
        return img
    except: return img

def smart_bottom_trim(img):
    """Scans Bottom-Up. Crops if Right Half is empty (< 5%)."""
    try:
        gray = img.convert('L')
        bw = gray.point(lambda p: 0 if p > 150 else 1, mode='1')
        data = np.array(bw)
        
        height, width = data.shape
        midpoint = width // 2
        crop_y = height
        
        for y in range(height - 1, -1, -1):
            right_strip = data[y, midpoint:]
            right_ink = np.count_nonzero(right_strip)
            right_density = right_ink / right_strip.size if right_strip.size > 0 else 0
            
            if right_density < 0.05:
                crop_y = y
            else:
                break
        
        if crop_y < height:
            return img.crop((0, 0, width, min(height, crop_y + 2)))
        return img
    except: return img

def trim_whitespace(im):
    try:
        # Convert to RGB to safely diff (Quantized images can behave oddly with diff)
        bg = Image.new("RGB", im.size, (255, 255, 255))
        diff = ImageChops.difference(im.convert("RGB"), bg)
        diff = ImageChops.add(diff, diff, 2.0, -100)
        bbox = diff.getbbox()
        return im.crop(bbox) if bbox else im
    except: return im

def is_bold(word_dict):
    font = word_dict.get('fontname', '').lower()
    return 'bold' in font or 'bd' in font or 'black' in font or 'medi' in font

# --- 3. STRUCTURE PARSING ---

def get_answer_key(full_text):
    ans_map = {}
    target_text = ""
    if "Answers" in full_text and "Explanations" in full_text:
        start_idx = full_text.find("Answers") + len("Answers")
        end_idx = full_text.find("Explanations")
        if end_idx > start_idx: target_text = full_text[start_idx:end_idx].strip()

    if not target_text:
        for marker in ["Answers", "Explanations", "Hints & Solutions"]:
            if marker in full_text:
                target_text = full_text.split(marker)[-1]
                if marker == "Answers" and "Explanations" in target_text:
                    target_text = target_text.split("Explanations")[0]
                break
            
    matches = re.findall(r'(?:^|\s)(\d+)\s*[\.\-\)]?\s*[\(\[]([a-e])[\]\)]', target_text, re.IGNORECASE)
    for q, opt in matches: ans_map[int(q)] = opt.upper()
    return ans_map

def extract_column_anchors(page, col_bbox):
    anchors = []
    try:
        col_crop = page.within_bbox(col_bbox)
        words = col_crop.extract_words(extra_attrs=["fontname"])
        for w in words:
            text = w['text'].strip().replace('.', '')
            if not text.isdigit(): continue
            num = int(text)
            if num > 2000: continue 
            
            rel_x = w['x0'] - col_bbox[0]
            if is_bold(w):
                if rel_x < 100: 
                    anchors.append({
                        'q_num': num,
                        'top': w['top'],
                        'bottom': w['bottom'],
                        'col_x': col_bbox[0],
                        'col_w': col_bbox[2] - col_bbox[0],
                        'confidence': 'high'
                    })
    except: pass 
    return anchors

def filter_sequential_anchors(raw_anchors):
    if not raw_anchors: return []
    raw_anchors.sort(key=lambda x: (x['page'], x['col_idx'], x['top']))
    clean_anchors = []
    last_num = 0
    seen = set()
    for anchor in raw_anchors:
        q = anchor['q_num']
        if q in seen: continue
        if last_num == 0:
            if q < 100: clean_anchors.append(anchor); last_num = q; seen.add(q)
        else:
            if 0 < (q - last_num) < 20: clean_anchors.append(anchor); last_num = q; seen.add(q)
            elif q == 1: clean_anchors.append(anchor); last_num = q; seen.add(q)
    return clean_anchors

def parse_pdf_structure(pdf_path):
    raw_structure = []
    topic_name = "Unknown"
    with pdfplumber.open(pdf_path) as pdf:
        for p_idx, page in enumerate(pdf.pages):
            width = page.width
            height = page.height
            text = page.extract_text() or ""
            topic_match = re.search(r'Topic\s+\d+\s+([A-Za-z\s]+)', text)
            if topic_match: topic_name = topic_match.group(1).strip()
            
            page_bottom = height * 0.93
            for marker in ["Answers", "Explanations", "Hints & Solutions"]:
                hits = page.search(marker)
                if hits: page_bottom = min(page_bottom, hits[0]['top'])
            
            if page_bottom < 50: continue 
            mid = width / 2
            cols = [(0, 0, mid, page_bottom), (mid, 0, width, page_bottom)]
            for col_idx, bbox in enumerate(cols):
                col_anchors = extract_column_anchors(page, bbox)
                for a in col_anchors:
                    a['page'] = p_idx
                    a['col_idx'] = col_idx
                    a['limit_bottom'] = bbox[3]
                    a['topic'] = topic_name
                    raw_structure.append(a)
    return filter_sequential_anchors(raw_structure)

# --- 4. BATCH PROCESSOR ---
def run_batch_extraction(row_data, source_pdf):
    start_p = int(row_data['pdf_start_pg'])
    end_p = int(row_data['pdf_end_pg'])
    chapter_name = str(row_data.get('Chapter', '')).strip()
    topic_name = str(row_data.get('Topic', '')).strip()
    
    print(f"\n🚀 Processing Batch: {chapter_name} (Pg {start_p}-{end_p})")
    
    # 1. Trimming (PyPDF)
    trimmed_name = f"Trimmed_{chapter_name}_{start_p}_{end_p}".replace(" ", "_")
    trimmed_path = os.path.join(TRIMMED_DIR, f"{trimmed_name}.pdf")
    
    if not os.path.exists(trimmed_path):
        master_pdf_path = os.path.join(RAW_DATA_DIR, source_pdf)
        if os.path.exists(master_pdf_path):
            reader = PdfReader(master_pdf_path); writer = PdfWriter()
            for i in range(start_p-1, min(len(reader.pages), end_p)):
                writer.add_page(reader.pages[i])
            with open(trimmed_path, "wb") as f: writer.write(f)
        else: return False

    # 2. Extract Metadata
    anchors = parse_pdf_structure(trimmed_path)
    full_text = ""
    with pdfplumber.open(trimmed_path) as pdf:
        for p in pdf.pages: full_text += (p.extract_text() or "") + "\n"
    answer_key = get_answer_key(full_text)
    
    print(f"   🔑 Found {len(answer_key)} answers.")
    print(f"   🔎 Found {len(anchors)} Valid Questions.")

    # 3. RENDER IMAGES (Using PyMuPDF for High Fidelity)
    print("   🖼️ Rendering with PyMuPDF (High Quality)...")
    output_dir = os.path.join(PROCESSED_BASE, trimmed_name)
    os.makedirs(output_dir, exist_ok=True)
    
    # Open doc with Fitz
    doc = fitz.open(trimmed_path)
    # 300 DPI Scale (72 pts * 4.166 = 300 px)
    ZOOM = 300 / 72 
    mat = fitz.Matrix(ZOOM, ZOOM)
    
    rows = []
    with open(CONFIG_PATH, 'r') as f: config = json.load(f)
    curr_id = int(config.get("last_unique_id", 0))

    for i, start in tqdm(enumerate(anchors), total=len(anchors)):
        try:
            # Get coordinates from pdfplumber (pts)
            # Add slight buffer (-2 top) to ensure full character capture
            y1_pts = start['top'] - 2
            y2_pts = start['limit_bottom']
            x1_pts = start['col_x']
            x2_pts = start['col_x'] + start['col_w']
            
            # Find dynamic bottom (Next Question)
            for j in range(i+1, len(anchors)):
                nxt = anchors[j]
                if nxt['page'] == start['page'] and nxt['col_idx'] == start['col_idx']:
                    if nxt['top'] > start['top']:
                        y2_pts = nxt['top'] - 2
                        break
            
            # Safety for last question in column
            if y2_pts <= y1_pts + 5: y2_pts = y1_pts + 100
            
            # --- RENDER STRATEGY (FITZ) ---
            # Define crop rectangle in PDF coordinates
            page = doc[start['page']]
            rect = fitz.Rect(x1_pts, y1_pts, x2_pts, y2_pts)
            
            # Render High-Res Pixmap
            pix = page.get_pixmap(matrix=mat, clip=rect, alpha=False)
            
            # Convert to PIL
            img = Image.frombytes("RGB", [pix.width, pix.height], pix.samples)
            
            # --- POST PROCESSING ---
            # 1. Trim outer white
            img = trim_whitespace(img)
            # 2. Remove bottom noise (Years)
            img = smart_bottom_trim(img)
            # 3. Remove question number (Left)
            img = smart_left_number_trim(img)
            # 4. Final Compress (Non-Destructive)
            final_img = compress_and_clean(trim_whitespace(img))
            
            filename = f"Q_{start['q_num']}.png"
            final_img.save(os.path.join(output_dir, filename), optimize=True)
            
            curr_id += 1
            rows.append({
                'unique_id': curr_id,
                'Question No.': start['q_num'],
                'Folder': trimmed_name,
                'Chapter': chapter_name, 
                'Topic': topic_name,     
                'Subject': row_data.get('Subject', 'Physics'),
                'Correct Answer': answer_key.get(start['q_num'], ""),
                'Question type': 'Single Correct', 
                'PYQ': 'Yes',                       
                'q_width': final_img.width,         
                'q_height': final_img.height,       
                'image_url': filename
            })
        except Exception as e: pass

    if rows:
        df_new = pd.DataFrame(rows)
        ordered_cols = ['unique_id', 'Question No.', 'Folder', 'Chapter', 'Topic', 'Subject', 
                        'Question type', 'Correct Answer', 'PYQ', 'q_width', 'q_height', 'image_url']
        df_final = df_new[ordered_cols] if set(ordered_cols).issubset(df_new.columns) else df_new
        
        if os.path.exists(OUTPUT_CSV_PATH):
            pd.concat([pd.read_csv(OUTPUT_CSV_PATH), df_final], ignore_index=True).to_csv(OUTPUT_CSV_PATH, index=False)
        else:
            df_final.to_csv(OUTPUT_CSV_PATH, index=False)

        config["last_unique_id"] = curr_id
        with open(CONFIG_PATH, 'w') as f: json.dump(config, f, indent=4)
        print(f"   💾 Saved {len(rows)} questions.")
    
    return True

# --- 5. MAIN LOOP ---
if __name__ == "__main__":
    SOURCE_PDF = "PYQ NEET Digvijay.pdf"
    if not os.path.exists(INPUT_CSV_PATH): print(f"❌ Input CSV missing: {INPUT_CSV_PATH}")
    else:
        try:
            input_df = pd.read_csv(INPUT_CSV_PATH, skipinitialspace=True)
            input_df.columns = input_df.columns.str.strip()
            if 'isProcessed' not in input_df.columns: input_df['isProcessed'] = 'No'
            pending = input_df[input_df['isProcessed'] != 'Yes']
            print(f"📋 Found {len(pending)} batches.")
            for idx, row in pending.iterrows():
                if run_batch_extraction(row, SOURCE_PDF):
                    input_df.at[idx, 'isProcessed'] = 'Yes'
                    input_df.to_csv(INPUT_CSV_PATH, index=False)
            print("\n🏁 DONE.")
        except Exception as e: print(f"❌ Error: {e}")