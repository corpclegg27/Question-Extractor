import os
import re
import json
import pandas as pd
import pdfplumber
import fitz  # PyMuPDF
import cv2   # OpenCV
import numpy as np
import logging
from pypdf import PdfReader, PdfWriter
from PIL import Image, ImageChops, ImageEnhance
from tqdm import tqdm
from collections import Counter, defaultdict

# --- 0. SUPPRESS PDF WARNINGS ---
logging.getLogger("pdfminer").setLevel(logging.ERROR)

# --- 1. CONFIGURATION ---
BASE_PATH = r'D:\Main\3. Work - Teaching\Projects\Question extractor'
CONFIG_PATH = os.path.join(BASE_PATH, 'config.json')

OUTPUT_CSV_PATH = os.path.join(BASE_PATH, 'Question Bank Disha Mains PYQs.csv')
INPUT_CSV_PATH = os.path.join(BASE_PATH, 'Question Bank Disha Mains PYQs- Inputs.csv')

RAW_DATA_DIR = os.path.join(BASE_PATH, 'raw data')
TRIMMED_DIR = os.path.join(RAW_DATA_DIR, 'Trimmed_PDFs')
PROCESSED_BASE = os.path.join(BASE_PATH, 'Processed_Database')

os.makedirs(TRIMMED_DIR, exist_ok=True)
os.makedirs(PROCESSED_BASE, exist_ok=True)

# --- 2. IMAGE PROCESSING (ULTRA-SAFE MODE) ---

def process_image_smart(pil_img):
    """
    Applies:
    1. Watermark Removal (Light Grey).
    2. Left Trim (Question Number) - Using Vertical Projection.
    3. Bottom Trim - ULTRA SAFE (Only removes solid black bars).
    """
    try:
        # Convert PIL to OpenCV (BGR)
        img_np = cv2.cvtColor(np.array(pil_img), cv2.COLOR_RGB2BGR)
        height, width, _ = img_np.shape
        
        # --- A. WATERMARK REMOVAL ---
        # Target light grey backgrounds (210-255)
        lower_grey = np.array([210, 210, 210], dtype=np.uint8)
        upper_grey = np.array([255, 255, 255], dtype=np.uint8)
        mask = cv2.inRange(img_np, lower_grey, upper_grey)
        img_np[mask > 0] = [255, 255, 255]

        # --- B. SAFE BOTTOM STRIP REMOVAL (Fix for Over-Cropping) ---
        # We only check the BOTTOM 50 pixels.
        # We only cut if we see a SOLID BLACK BAR (>50% density).
        # We do NOT cut based on whitespace gaps anymore.
        gray = cv2.cvtColor(img_np, cv2.COLOR_BGR2GRAY)
        _, binary = cv2.threshold(gray, 200, 255, cv2.THRESH_BINARY_INV)
        
        crop_bottom = height
        scan_limit = min(50, int(height * 0.1)) # Only look at very bottom
        
        for y in range(height - 1, height - scan_limit, -1):
            row = binary[y, :]
            ink_density = np.count_nonzero(row) / width
            
            # STRICT: Only cut if it looks like a footer line (>50% ink)
            if ink_density > 0.50: 
                crop_bottom = y
            else:
                # Stop immediately if it's not a bar. Preserves text.
                break

        if crop_bottom < height:
            img_np = img_np[:crop_bottom, :]
            # Update binary for next step
            gray = gray[:crop_bottom, :]
            binary = binary[:crop_bottom, :]
            height = crop_bottom

        # --- C. QUESTION NUMBER TRIM (Vertical Projection) ---
        SCAN_WIDTH_RATIO = 0.30
        INK_THRESHOLD = 2
        MERGE_GAP_TOLERANCE = 15
        CUT_PADDING = 10

        scan_width = int(width * SCAN_WIDTH_RATIO)
        
        # Re-calc projection on the (possibly cropped) binary image
        projection = np.sum(binary[:, :scan_width], axis=0) / 255
        has_ink = projection > INK_THRESHOLD

        blocks = []
        in_block = False
        start_x = 0
        
        x = 0
        while x < len(has_ink):
            if has_ink[x]:
                if not in_block:
                    in_block = True
                    start_x = x
            else:
                if in_block:
                    # Look-Ahead logic
                    is_real_gap = True
                    look_ahead_range = min(x + MERGE_GAP_TOLERANCE, len(has_ink))
                    
                    for k in range(x + 1, look_ahead_range):
                        if has_ink[k]:
                            is_real_gap = False
                            x = k - 1 
                            break
                    
                    if is_real_gap:
                        in_block = False
                        end_x = x
                        if (end_x - start_x) > 3:
                            blocks.append({'start': start_x, 'end': end_x})
            x += 1
            
        if in_block:
            end_x = len(has_ink)
            if (end_x - start_x) > 3:
                blocks.append({'start': start_x, 'end': end_x})

        # Determine Cut
        cut_x = 0
        if len(blocks) >= 2:
            text_start = blocks[1]['start']
            number_end = blocks[0]['end']
            cut_x = max(text_start - CUT_PADDING, number_end + 1)
        
        # Apply Left Crop
        if cut_x > 0:
            img_np = img_np[:, cut_x:]

        # Return as PIL
        return Image.fromarray(cv2.cvtColor(img_np, cv2.COLOR_BGR2RGB))

    except Exception:
        return pil_img 

def compress_and_clean(img):
    try:
        img = img.convert('L')
        # Gentle Contrast (1.2) - Preserves details
        enhancer = ImageEnhance.Contrast(img)
        img = enhancer.enhance(1.2) 
        return img
    except: return img

def trim_whitespace(im):
    try:
        bg = Image.new("RGB", im.size, (255, 255, 255))
        diff = ImageChops.difference(im.convert("RGB"), bg)
        diff = ImageChops.add(diff, diff, 2.0, -100)
        bbox = diff.getbbox()
        if bbox:
            # 5px Padding to ensure nothing touches the edge
            return im.crop((max(0, bbox[0]-5), max(0, bbox[1]-5), min(im.width, bbox[2]+5), min(im.height, bbox[3]+5)))
        return im
    except: return im

def is_bold_font(fontname):
    fn = fontname.lower()
    return 'bold' in fn or 'bd' in fn or 'black' in fn or 'medi' in fn or '+b' in fn

# --- 3. CLASSIFICATION ---

def classify_and_clean_answer(raw_text):
    if not raw_text: return "", "Subjective"
    text = re.sub(r'[\(\)]', '', raw_text).strip().upper()
    if re.match(r'^[A-D]$', text): return text, "Single Correct"
    try:
        float(text)
        return text, "Numerical type"
    except: pass
    return raw_text, "Subjective"

def extract_answers_from_solutions(pdf_path, solution_anchors):
    print(f"      🔑 Extracting Answers from Solutions...")
    ans_map = {}
    if not solution_anchors: return ans_map

    with pdfplumber.open(pdf_path) as pdf:
        anchors_by_page = defaultdict(list)
        for a in solution_anchors:
            anchors_by_page[a['page']].append(a)

        for p_idx, anchors in anchors_by_page.items():
            page = pdf.pages[p_idx]
            words = page.extract_words(keep_blank_chars=False)
            
            for anchor in anchors:
                candidates = []
                for w in words:
                    # Look right of anchor
                    if w['x0'] > anchor['x1'] and \
                       abs(w['top'] - anchor['top']) < 5 and \
                       w['x0'] < (anchor['x1'] + 100):
                        candidates.append(w['text'])
                
                if candidates:
                    line_start = "".join(candidates[:2]) 
                    match = re.search(r'\((?P<ans>[a-zA-Z0-9\.]+)\)', line_start)
                    if match:
                        ans_map[anchor['q_num']] = match.group('ans')
    return ans_map

# --- 4. ROBUST STRUCTURE ANALYSIS (SEQUENTIAL SPLIT) ---

def analyze_and_extract(pdf_path):
    print(f"   🔍 Scanning Structure: {os.path.basename(pdf_path)}")
    all_raw_anchors = []
    sol_header_page = -1
    
    with pdfplumber.open(pdf_path) as pdf:
        page_count = len(pdf.pages)
        for p_idx, page in enumerate(pdf.pages):
            height = page.height
            text = page.extract_text() or ""
            
            # Header Check
            if sol_header_page == -1:
                if re.search(r'(HINTS|ANSWERS|SOLUTIONS|EXPLANATIONS)\s*(&|and)?\s*(SOLUTIONS|KEY)?', text, re.IGNORECASE):
                    if p_idx > (page_count * 0.2): 
                        sol_header_page = p_idx
                        print(f"      📍 'SOLUTIONS' Header found at Page {p_idx+1}")

            # ANCHOR HARVESTING
            words = page.extract_words(keep_blank_chars=False, extra_attrs=["fontname"])
            for w in words:
                if w['top'] < 50 or w['bottom'] > (height - 50): continue
                
                if is_bold_font(w['fontname']):
                    text = w['text'].strip()
                    
                    # --- STRICT LENGTH CHECK ---
                    if len(text) >= 7: continue 
                    
                    # --- STRICT REGEX MATCH (1., 2.) ---
                    if re.match(r'^(?:Q[\.\s]?)?(\d+)[\.:]?$', text, re.IGNORECASE):
                        num = int(re.findall(r'\d+', text)[0])
                        if 0 < num < 300:
                            all_raw_anchors.append({
                                'q_num': num, 
                                'page': p_idx, 
                                'top': w['top'], 
                                'x0': w['x0'], 
                                'x1': w['x1'], 
                                'bottom': w['bottom']
                            })

    # --- SEQUENTIAL SPLIT LOGIC ---
    # We find the *One True Split Point* in the master list.
    
    split_index = -1
    
    # Strategy 1: Header Page Barrier
    # If we found a header, the first "1" on or after that page is the start of solutions.
    if sol_header_page != -1:
        for i, a in enumerate(all_raw_anchors):
            if a['page'] >= sol_header_page and a['q_num'] == 1:
                split_index = i
                break
    
    # Strategy 2: Sequence Reset (Backup)
    # Scan for the largest drop (e.g. 77 -> 1)
    if split_index == -1:
        last_num = 0
        for i, a in enumerate(all_raw_anchors):
            num = a['q_num']
            # Strict Drop: > 20 to 1
            if last_num > 20 and num == 1 and a['page'] > 0:
                print(f"      📍 Sequence Reset detected: {last_num} -> {num} at Page {a['page']+1}")
                split_index = i
                break
            last_num = num

    # --- ASSIGN LISTS ---
    if split_index != -1:
        questions = all_raw_anchors[:split_index]
        solutions = all_raw_anchors[split_index:]
    else:
        # No split found -> All are questions
        questions = all_raw_anchors
        solutions = []

    ans_map = {}
    if solutions:
        ans_map = extract_answers_from_solutions(pdf_path, solutions)

    return questions, solutions, ans_map

# --- 5. RENDERER (ANCHOR-LOCKED) ---

def render_list(doc, anchors, output_dir, prefix):
    count = 0
    p0 = doc[0]
    page_h = p0.rect.height
    page_w = p0.rect.width
    mid = page_w / 2
    
    q_counts = Counter()

    for i, start in tqdm(enumerate(anchors), total=len(anchors), desc=f"Rendering {prefix}", leave=True):
        try:
            q_num = start['q_num']
            q_counts[q_num] += 1
            suffix = f"_{q_counts[q_num]}" if q_counts[q_num] > 1 else ""
            fname = f"{prefix}_{q_num}{suffix}.png"
            start['filename'] = fname 

            # EXACT CROP (Anchor Locked)
            crop_top = max(0, start['top'] - 2)
            crop_left = max(0, start['x0'] - 2)
            limit_bottom = page_h * 0.95
            
            for j in range(i + 1, len(anchors)):
                nxt = anchors[j]
                if nxt['page'] == start['page']:
                    if nxt['top'] > start['top']:
                         # Col check (approx 100px tolerance)
                         if abs(nxt['x0'] - start['x0']) < 100:
                             limit_bottom = nxt['top'] - 5
                             break
                else: break

            if start['x0'] < mid: crop_right = mid
            else: crop_right = page_w

            max_h = page_h * 0.8
            if (limit_bottom - crop_top) > max_h:
                limit_bottom = crop_top + max_h

            rect = fitz.Rect(crop_left, crop_top, crop_right, limit_bottom)
            
            page = doc[start['page']]
            pix = page.get_pixmap(matrix=fitz.Matrix(300/72, 300/72), clip=rect, alpha=False)
            
            if pix.width > 10 and pix.height > 10:
                img = Image.frombytes("RGB", [pix.width, pix.height], pix.samples)
                
                # PIPELINE
                img = trim_whitespace(img)
                img = process_image_smart(img) # Safe Bottom + Left Trim
                img = compress_and_clean(img) # Quality
                
                img.save(os.path.join(output_dir, fname))
                count += 1
        except: pass
    return count

# --- 6. BATCH RUNNER ---

def run_batch(row_data, source_pdf):
    start_p, end_p = int(row_data['pdf_start_pg']), int(row_data['pdf_end_pg'])
    chapter = str(row_data.get('Chapter', 'Unknown')).strip()
    
    print(f"\n🚀 Processing: {chapter} (Pg {start_p}-{end_p})")
    
    safe_chap = re.sub(r'[^\w\-_\. ]', '_', chapter)
    trimmed_name = f"Disha_{safe_chap}_p{start_p}_p{end_p}"
    trimmed_path = os.path.join(TRIMMED_DIR, f"{trimmed_name}.pdf")
    
    if not os.path.exists(trimmed_path):
        master = os.path.join(RAW_DATA_DIR, source_pdf)
        if os.path.exists(master):
            r = PdfReader(master); w = PdfWriter()
            for i in range(max(0, start_p-1), min(len(r.pages), end_p)): w.add_page(r.pages[i])
            with open(trimmed_path, "wb") as f: w.write(f)
        else: return False

    q_list, sol_list, ans_map = analyze_and_extract(trimmed_path)
    
    print(f"      📋 Questions: {len(q_list)} | Solutions: {len(sol_list)}")
    print(f"      🔑 Answer Keys Found: {len(ans_map)}")

    out_dir = os.path.join(PROCESSED_BASE, trimmed_name)
    os.makedirs(out_dir, exist_ok=True)
    doc = fitz.open(trimmed_path)
    
    render_list(doc, q_list, out_dir, "Q")
    render_list(doc, sol_list, out_dir, "Sol")
    
    rows = []
    with open(CONFIG_PATH, 'r') as f: conf = json.load(f)
    uid = int(conf.get("last_unique_id", 0))
    
    for q in q_list:
        q_num = q['q_num']
        img_name = q.get('filename', "")
        
        # --- STRICT DUPLICATE FILTER ---
        if img_name.count('_') > 1:
            continue
            
        if not img_name: continue 
        
        sol_name = img_name.replace("Q_", "Sol_")
        has_sol = os.path.exists(os.path.join(out_dir, sol_name))
        
        uid += 1
        raw_ans = ans_map.get(q_num, "")
        clean_ans, q_type = classify_and_clean_answer(raw_ans)
        
        rows.append({
            'unique_id': uid,
            'Question No.': q_num,
            'Folder': trimmed_name,
            'Chapter': chapter,
            'Subject': 'Physics',
            'Exam': 'JEE Main',
            'PYQ': 'Yes',
            'Question type': q_type,
            'Correct Answer': clean_ans,
            'Answer key raw': raw_ans,
            'image_url': img_name,
            'solution_url': sol_name if has_sol else "",
            'Source File': source_pdf
        })
            
    if rows:
        df = pd.DataFrame(rows)
        cols = ['unique_id', 'Question No.', 'Folder', 'Chapter', 'Subject', 'Exam', 'PYQ', 
                'Question type', 'Correct Answer', 'Answer key raw', 
                'image_url', 'solution_url', 'Source File']
        for c in cols:
             if c not in df.columns: df[c] = ""
        df = df[cols]
        
        if os.path.exists(OUTPUT_CSV_PATH):
            pd.concat([pd.read_csv(OUTPUT_CSV_PATH), df], ignore_index=True).to_csv(OUTPUT_CSV_PATH, index=False)
        else:
            df.to_csv(OUTPUT_CSV_PATH, index=False)
            
        conf["last_unique_id"] = uid
        with open(CONFIG_PATH, 'w') as f: json.dump(conf, f, indent=4)
        print(f"      💾 Saved {len(rows)} entries.")
        return True
    
    return False

if __name__ == "__main__":
    SOURCE_PDF = "PYQs JEE Mains Disha Experts - JEE Main Physics Online (2020 - 2012) & Offline (2018 - 2002).pdf"
    if os.path.exists(INPUT_CSV_PATH):
        indf = pd.read_csv(INPUT_CSV_PATH)
        indf.columns = indf.columns.str.strip()
        if 'isProcessed' not in indf.columns: indf['isProcessed'] = 'No'
        indf['isProcessed'] = indf['isProcessed'].astype(str)
        
        pending = indf[indf['isProcessed'] != 'Yes']
        for i, r in pending.iterrows():
            if run_batch(r, SOURCE_PDF):
                indf.at[i, 'isProcessed'] = 'Yes'
                indf.to_csv(INPUT_CSV_PATH, index=False)
        print("\n🏁 DONE.")