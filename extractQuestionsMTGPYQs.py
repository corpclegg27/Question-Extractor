import os
import re
import json
import pandas as pd
import pdfplumber
import fitz  # PyMuPDF
import cv2   # OpenCV
import numpy as np
from pypdf import PdfReader, PdfWriter
from PIL import Image, ImageChops, ImageEnhance
from tqdm import tqdm
from collections import Counter

# --- 1. CONFIGURATION ---
BASE_PATH = r'D:\Main\3. Work - Teaching\Projects\Question extractor'
CONFIG_PATH = os.path.join(BASE_PATH, 'config.json')

OUTPUT_CSV_PATH = os.path.join(BASE_PATH, 'Question Bank MTG Adv PYQs.csv')
INPUT_CSV_PATH = os.path.join(BASE_PATH, 'Question Bank MTG Adv PYQs- Inputs.csv')

RAW_DATA_DIR = os.path.join(BASE_PATH, 'raw data')
TRIMMED_DIR = os.path.join(RAW_DATA_DIR, 'Trimmed_PDFs')
PROCESSED_BASE = os.path.join(BASE_PATH, 'Processed_Database')

os.makedirs(TRIMMED_DIR, exist_ok=True)
os.makedirs(PROCESSED_BASE, exist_ok=True)

# --- 2. ADVANCED IMAGE PROCESSING ---

def process_image_smart(pil_img):
    """
    Applies aggressive cleaning:
    1. Removes Watermarks (Light Grey pixels -> White).
    2. Aggressively crops black footers/artifacts from bottom.
    3. Trims Question Number from left.
    """
    try:
        # Convert to BGR (OpenCV format)
        img_np = cv2.cvtColor(np.array(pil_img), cv2.COLOR_RGB2BGR)
        
        # --- A. WATERMARK REMOVAL ---
        # Target: Light Grey (RGB ~230,230,230). Range: 200-245
        # We define a mask for this range and force those pixels to pure white
        lower_grey = np.array([200, 200, 200], dtype=np.uint8)
        upper_grey = np.array([245, 245, 245], dtype=np.uint8)
        mask = cv2.inRange(img_np, lower_grey, upper_grey)
        img_np[mask > 0] = [255, 255, 255]

        # --- B. AGGRESSIVE BOTTOM CROP ---
        # Convert to binary for structure analysis
        gray = cv2.cvtColor(img_np, cv2.COLOR_BGR2GRAY)
        _, binary = cv2.threshold(gray, 200, 255, cv2.THRESH_BINARY_INV)
        height, width = binary.shape

        # Scan from bottom up
        # We look for the first row that is "mostly empty" (ink density < 1%)
        # This skips over dense black bars, text lines, and noise at the bottom
        crop_bottom = height
        scan_limit = int(height * 0.25) # Only scan bottom 25%
        
        for y in range(height - 1, height - scan_limit, -1):
            row = binary[y, :]
            ink_density = np.count_nonzero(row) / width
            
            # If the row has significant ink (> 50%) OR is a solid line, we keep cutting
            # We stop only when we find a "clean" white gap
            if ink_density > 0.05: 
                crop_bottom = y
            else:
                # We found a white gap. But is it the *real* content end?
                # Check 5 rows above to be sure we aren't just in a text line gap
                if crop_bottom != height: # If we have started cutting
                    # Look ahead (upwards) - if mostly white for 5 rows, we stop here
                    is_safe_gap = True
                    for k in range(1, 6):
                        if (y - k) >= 0:
                            if (np.count_nonzero(binary[y-k, :]) / width) > 0.05:
                                is_safe_gap = False
                                break
                    if is_safe_gap:
                        break
                    else:
                        crop_bottom = y # Continue cutting

        # Apply Bottom Crop
        if crop_bottom < height:
            img_np = img_np[:crop_bottom, :]
            gray = gray[:crop_bottom, :]
            binary = binary[:crop_bottom, :]
            height = crop_bottom 

        # --- C. QUESTION NUMBER TRIM ---
        SCAN_WIDTH_RATIO = 0.30
        INK_THRESHOLD = 2
        MERGE_GAP_TOLERANCE = 15
        CUT_PADDING = 10

        scan_width = int(width * SCAN_WIDTH_RATIO)
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

        cut_x = 0
        if len(blocks) >= 2:
            text_start = blocks[1]['start']
            number_end = blocks[0]['end']
            cut_x = max(text_start - CUT_PADDING, number_end + 1)
        
        if cut_x > 0:
            img_np = img_np[:, cut_x:]

        # Return as PIL (RGB)
        return Image.fromarray(cv2.cvtColor(img_np, cv2.COLOR_BGR2RGB))

    except Exception:
        return pil_img 

# --- 3. UTILITIES ---

def compress_and_clean(img):
    try:
        img = img.convert('L')
        enhancer = ImageEnhance.Contrast(img)
        img = enhancer.enhance(1.3)
        img = img.quantize(colors=32, method=2, dither=Image.NONE)
        return img
    except: return img

def trim_whitespace(im):
    try:
        bg = Image.new("RGB", im.size, (255, 255, 255))
        diff = ImageChops.difference(im.convert("RGB"), bg)
        diff = ImageChops.add(diff, diff, 2.0, -100)
        bbox = diff.getbbox()
        if bbox:
            return im.crop((max(0, bbox[0]-5), max(0, bbox[1]-5), min(im.width, bbox[2]+5), min(im.height, bbox[3]+5)))
        return im
    except: return im

def is_bold_font(fontname):
    fn = fontname.lower()
    return 'bold' in fn or 'bd' in fn or 'black' in fn or 'medi' in fn or '+b' in fn

def sort_words_by_column(words, page_width):
    if not words: return []
    mid = page_width / 2
    gutter_clear = True
    for w in words:
        if w['x0'] < mid < w['x1']:
            gutter_clear = False
            break
    if gutter_clear:
        col1 = [w for w in words if w['x0'] < mid]
        col2 = [w for w in words if w['x0'] >= mid]
        col1.sort(key=lambda w: (w['top'], w['x0']))
        col2.sort(key=lambda w: (w['top'], w['x0']))
        return col1 + col2
    else:
        return sorted(words, key=lambda w: (w['top'], w['x0']))

# --- 4. CLASSIFICATION LOGIC ---

def classify_and_clean_answer(raw_text):
    if not raw_text: return "", "Subjective"

    text = re.sub(r'(Follow us|Visit our|Downloaded from|CopyMyKitab|Chapterwise Solutions).*', '', raw_text, flags=re.IGNORECASE).strip()
    text = text.replace('fi', '').replace('–', '-').strip()
    text = re.sub(r'^[\.:\-\)]+\s*', '', text)
    
    if re.search(r'[P-S][\s:;\-]+[1-4]', text):
        return text.strip(), "Matrix Match" 

    is_matrix = False
    if re.search(r'[a-f][\s:;\-]+[p-u]', text, re.IGNORECASE): is_matrix = True
    
    if is_matrix:
        pairs = []
        pattern = r'([a-fA-F])\s*[\s\-\:;\u2013]+\s*((?:[p-uP-U][\s,]*)+)'
        matches = re.findall(pattern, text)
        if matches:
            for key, val_chunk in matches:
                vals = re.findall(r'[p-uP-U]', val_chunk)
                vals = sorted(list(set(v.upper() for v in vals))) 
                if vals:
                    clean_key = key.upper()
                    clean_vals = ", ".join(vals)
                    pairs.append(f"{clean_key} - {clean_vals}")
            if pairs:
                pairs.sort()
                return " | ".join(pairs), "Matrix Match"
        return text, "Matrix Match"

    matches = re.findall(r'(?:^|[\s,\(])([a-dA-D])(?:[\s,\)]|$)', text)
    if matches:
        unique_opts = sorted(list(set([m.upper() for m in matches])))
        if len(text) < 20 or len(unique_opts) > 0:
            clean_ans = ", ".join(unique_opts)
            if len(unique_opts) == 1: return clean_ans, "Single Correct"
            else: return clean_ans, "One or more options correct"

    clean_num = text.replace(" ", "")
    try:
        float(clean_num)
        return clean_num, "Numerical type"
    except: pass

    return text.strip(), "Subjective"

# --- 5. PARSERS ---

def parse_answer_key_robust(pdf_path, start_page, start_y, end_page, end_y):
    # print(f"      🔑 Parsing Answer Key Region...")
    raw_key_map = {}
    with pdfplumber.open(pdf_path) as pdf:
        all_words_in_order = []
        for p_idx in range(start_page, end_page + 1):
            page = pdf.pages[p_idx]
            width = page.width
            height = page.height
            p_top = start_y if p_idx == start_page else 0
            p_bottom = end_y if p_idx == end_page else height
            words = page.extract_words(keep_blank_chars=False, extra_attrs=["fontname"])
            region_words = [w for w in words if w['top'] >= p_top and w['bottom'] <= p_bottom]
            if not region_words: continue
            sorted_page_words = sort_words_by_column(region_words, width)
            all_words_in_order.extend(sorted_page_words)

        current_q_num = None
        current_text_buffer = []
        for w in all_words_in_order:
            text = w['text'].strip()
            is_bold = is_bold_font(w['fontname'])
            match_num = re.match(r'^(\d+)[\.:]?$', text)
            is_new_anchor = False
            if is_bold and match_num:
                num = int(match_num.group(1))
                if current_q_num is None:
                    if num == 1: is_new_anchor = True
                elif num == current_q_num + 1: is_new_anchor = True
                elif 0 < (num - current_q_num) < 5: is_new_anchor = True
            
            if is_new_anchor:
                if current_q_num is not None:
                    full_ans = " ".join(current_text_buffer).strip()
                    raw_key_map[current_q_num] = full_ans
                current_q_num = int(match_num.group(1))
                current_text_buffer = []
            else:
                if current_q_num is not None: current_text_buffer.append(text)
        
        if current_q_num is not None and current_text_buffer:
             full_ans = " ".join(current_text_buffer).strip()
             raw_key_map[current_q_num] = full_ans

    return raw_key_map

def analyze_and_extract(pdf_path):
    marker_page = -1
    marker_top = -1
    all_bold_anchors = []
    
    with pdfplumber.open(pdf_path) as pdf:
        for p_idx, page in enumerate(pdf.pages):
            if marker_page == -1:
                res = page.search("ANSWER KEY")
                if res:
                    marker_page = p_idx
                    marker_top = res[0]['top']
                    
            words = page.extract_words(keep_blank_chars=False, extra_attrs=["fontname"])
            for w in words:
                if is_bold_font(w['fontname']):
                    text = w['text'].strip()
                    if re.match(r'^(\d+)[\.:]?$', text):
                        num = int(re.findall(r'\d+', text)[0])
                        if 0 < num < 300:
                            all_bold_anchors.append({'q_num': num, 'page': p_idx, 'top': w['top'], 'x0': w['x0'], 'x1': w['x1'], 'bottom': w['bottom']})

    sol_start_page = -1
    sol_start_top = -1
    if marker_page != -1:
        post_key_anchors = [a for a in all_bold_anchors if (a['page'] > marker_page) or (a['page'] == marker_page and a['top'] > marker_top)]
        last_num = 0
        for a in post_key_anchors:
            num = a['q_num']
            if last_num >= 5 and num <= 2:
                sol_start_page = a['page']
                sol_start_top = a['top'] - 10 
                break
            last_num = num

    questions = [a for a in all_bold_anchors if (marker_page == -1) or (a['page'] < marker_page) or (a['page'] == marker_page and a['top'] < marker_top)]
    solutions = []
    if sol_start_page != -1:
        solutions = [a for a in all_bold_anchors if (a['page'] > sol_start_page) or (a['page'] == sol_start_page and a['top'] >= sol_start_top)]
    
    def clean(lst):
        seen = set()
        out = []
        for x in lst:
            if x['q_num'] not in seen:
                out.append(x)
                seen.add(x['q_num'])
        return sorted(out, key=lambda k: k['q_num'])
    
    questions = clean(questions)
    solutions = clean(solutions)
    ans_map = {}
    if marker_page != -1 and sol_start_page != -1:
        ans_map = parse_answer_key_robust(pdf_path, marker_page, marker_top, sol_start_page, sol_start_top)

    return questions, solutions, ans_map

# --- 6. RENDERER ---
def render_list(doc, anchors, output_dir, prefix):
    count = 0
    p0 = doc[0]
    page_h = p0.rect.height
    page_w = p0.rect.width
    mid = page_w / 2

    # TQDM Progress Bar (Added leave=True)
    for i, start in tqdm(enumerate(anchors), total=len(anchors), desc=f"Rendering {prefix}", leave=True):
        try:
            limit_bottom = page_h * 0.95
            for j in range(i + 1, len(anchors)):
                nxt = anchors[j]
                if nxt['page'] == start['page']:
                    if nxt['top'] > start['top']:
                         if abs(nxt['x0'] - start['x0']) < 150:
                             limit_bottom = nxt['top'] - 5
                             break
                else: break

            if start['x0'] < mid: x1, x2 = 0, mid
            else: x1, x2 = mid, page_w

            rect = fitz.Rect(x1, start['top']-2, x2, limit_bottom)
            page = doc[start['page']]
            pix = page.get_pixmap(matrix=fitz.Matrix(300/72, 300/72), clip=rect, alpha=False)
            
            if pix.width > 10 and pix.height > 10:
                img = Image.frombytes("RGB", [pix.width, pix.height], pix.samples)
                img = trim_whitespace(img)
                # Smart Clean (Watermark + Bottom Strip + Number Trim)
                img = process_image_smart(img)
                img = compress_and_clean(img)
                img.save(os.path.join(output_dir, f"{prefix}_{start['q_num']}.png"))
                count += 1
        except: pass
    return count

# --- 7. BATCH RUNNER ---
def run_batch(row_data, source_pdf):
    start_p, end_p = int(row_data['pdf_start_pg']), int(row_data['pdf_end_pg'])
    chapter = str(row_data.get('Chapter', 'Unknown')).strip()
    
    print(f"\n🚀 Processing: {chapter} (Pg {start_p}-{end_p})")
    
    safe_chap = re.sub(r'[^\w\-_\. ]', '_', chapter)
    trimmed_name = f"MTG_{safe_chap}_p{start_p}_p{end_p}"
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
        img = f"Q_{q_num}.png"
        sol = f"Sol_{q_num}.png"
        
        if os.path.exists(os.path.join(out_dir, img)):
            uid += 1
            has_sol = os.path.exists(os.path.join(out_dir, sol))
            raw_ans = ans_map.get(q_num, "")
            clean_ans, q_type = classify_and_clean_answer(raw_ans)
            
            rows.append({
                'unique_id': uid,
                'Question No.': q_num,
                'Folder': trimmed_name,
                'Chapter': chapter,
                'Subject': 'Physics',
                'Exam': 'JEE Advanced',
                'PYQ': 'Yes',
                'Question type': q_type,
                'Correct Answer': clean_ans,
                'Answer key raw': raw_ans,
                'image_url': img,
                'solution_url': sol if has_sol else "",
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
    SOURCE_PDF = "MTG 41 years JEE Advanced Chapterwise Physics.pdf"
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