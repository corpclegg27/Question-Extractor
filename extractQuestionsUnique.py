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
    Applies ONLY to the top part of the question.
    """
    try:
        inverted_img = ImageOps.invert(img.convert('L'))
        data = np.array(inverted_img)
        horizontal_projection = np.sum(data, axis=0)
        width = len(horizontal_projection)
        
        crop_x, whitespace_count, in_number_block = 0, 0, False
        
        # Scan left-to-right to find the gap after "1." or "25."
        for x in range(5, width):
            if horizontal_projection[x] > 500: # Ink detected
                in_number_block = True
                whitespace_count = 0
            elif in_number_block:
                whitespace_count += 1
                if whitespace_count >= 15: # Gap detected
                    crop_x = x - whitespace_count + 2
                    break
        
        # Safety: Don't crop if detection is too wide (>30%)
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

def stitch_images(img1, img2):
    """Vertically concatenates two images."""
    if img2 is None or img2.height < 5: return img1
    
    # Resize to same width if necessary (should be rare in standard cols)
    w = max(img1.width, img2.width)
    h = img1.height + img2.height
    new_im = Image.new('L', (w, h), 255) # White bg
    
    new_im.paste(img1, (0, 0))
    new_im.paste(img2, (0, img1.height))
    return new_im

# --- 3. PARSING LOGIC ---

def extract_answer_key(pdf_path):
    ans_map = {}
    print("🔍 Scanning for Answer Key...")
    with pdfplumber.open(pdf_path) as pdf:
        start_check = max(0, len(pdf.pages) - 3)
        for i in range(start_check, len(pdf.pages)):
            text = pdf.pages[i].extract_text() or ""
            matches = re.findall(r'(\d+)\.\s*\(([^)]+)\)', text)
            for q_num, ans_val in matches:
                ans_map[int(q_num)] = ans_val.strip()
    return ans_map

def find_anchors_on_page(page, p_idx, last_q_num):
    width = page.width
    mid_line = width / 2
    words = page.extract_words()
    candidates = []
    
    for w in words:
        text = w['text'].strip()
        if re.match(r'^\d+\.$', text):
            try:
                num = int(text.replace('.', ''))
                # Strict Sequence: e.g., 1, 2... or jump < 50
                if (num == 1) or (0 < (num - last_q_num) < 50):
                    candidates.append({
                        'q_num': num, 'top': w['top'], 'bottom': w['bottom'],
                        'x0': w['x0'], 'page': p_idx
                    })
            except: pass

    # Assign Columns
    anchors = []
    for cand in candidates:
        if cand['x0'] < mid_line:
            cand['col_idx'] = 0; cand['col_x'] = 0; cand['col_w'] = mid_line
        else:
            cand['col_idx'] = 1; cand['col_x'] = mid_line; cand['col_w'] = width - mid_line
        anchors.append(cand)

    anchors.sort(key=lambda x: (x['col_idx'], x['top']))
    new_last = max([a['q_num'] for a in anchors]) if anchors else last_q_num
    return anchors, new_last

def parse_document_structure(pdf_path):
    structure = []
    last_q_num = 0
    print("🔍 Global Document Scan...")
    
    with pdfplumber.open(pdf_path) as pdf:
        for p_idx, page in enumerate(pdf.pages):
            header = page.within_bbox((0, 0, page.width, page.height*0.2)).extract_text() or ""
            if "ANSWER KEY" in header.upper():
                print(f"   🛑 Answer Key found on Page {p_idx+1}. Stopping.")
                break
            
            page_anchors, last_q_num = find_anchors_on_page(page, p_idx, last_q_num)
            structure.extend(page_anchors)
    return structure

# --- 4. MAIN EXTRACTION ROUTINE ---
def run_extraction():
    full_pdf_path = os.path.join(RAW_DATA_DIR, SOURCE_PDF_NAME)
    if not os.path.exists(full_pdf_path):
        print(f"❌ File not found: {full_pdf_path}"); return

    # 1. Parsing
    ans_key = extract_answer_key(full_pdf_path)
    anchors = parse_document_structure(full_pdf_path)
    print(f"   ✅ Identified {len(anchors)} Questions.")

    # 2. Setup
    folder_name = "JEE_Unique_Practice"
    output_dir = os.path.join(PROCESSED_BASE, folder_name)
    os.makedirs(output_dir, exist_ok=True)
    
    print("🖼️ Converting PDF to Images (High Res)...")
    pdf_images = convert_from_path(full_pdf_path, dpi=300)
    scale = 300 / 72
    
    curr_id = 0
    if os.path.exists(CONFIG_PATH):
        with open(CONFIG_PATH, 'r') as f:
            curr_id = int(json.load(f).get('last_unique_id', 0))

    rows = []
    print("✂️ Cropping, Stitching & Extracting...")

    with pdfplumber.open(full_pdf_path) as pdf:
        for i, start in tqdm(enumerate(anchors), total=len(anchors)):
            try:
                # --- IDENTIFY NEXT ANCHOR & SPLIT ---
                if i + 1 < len(anchors):
                    nxt = anchors[i+1]
                else:
                    # Fake end anchor
                    nxt = {'page': start['page'], 'col_idx': start['col_idx'], 'top': 9999}

                is_split = (start['page'] != nxt['page']) or (start['col_idx'] != nxt['col_idx'])
                
                parts = [] # Will hold (Text, Image) tuples
                
                # --- PART 1: Start -> End of Current Column ---
                p1_page = pdf.pages[start['page']]
                p1_footer = p1_page.height * 0.93 # Footer Limit
                
                # If NOT split, we stop at nxt['top']. If split, we go to Footer.
                p1_bottom = nxt['top'] - 5 if not is_split else p1_footer
                if p1_bottom <= start['top']: p1_bottom = start['top'] + 100 # Safety

                # Text 1
                t1 = p1_page.within_bbox((start['col_x'], start['top']-5, 
                                          start['col_x']+start['col_w'], p1_bottom)).extract_text() or ""
                
                # Image 1
                im1 = pdf_images[start['page']].crop((
                    start['col_x'] * scale, (start['top']-5) * scale,
                    (start['col_x'] + start['col_w']) * scale, p1_bottom * scale
                ))
                # Remove Number from Part 1
                im1 = pixel_sensitive_crop(im1)
                parts.append((t1, im1))

                # --- PART 2: Top of Next Column -> Next Anchor (ONLY IF SPLIT) ---
                if is_split:
                    # Define "Next Column" coordinates
                    p2_page_idx = nxt['page']
                    # If it's a huge jump (e.g. skipped pages), ignore stitch
                    if p2_page_idx - start['page'] <= 1:
                        p2_page = pdf.pages[p2_page_idx]
                        p2_col_x = nxt['col_x']
                        p2_col_w = nxt['col_w'] # Assume same width logic
                        
                        # Top of column is 0 + margin. Stop at nxt['top']
                        p2_top = 20 # Header margin
                        p2_bottom = nxt['top'] - 5
                        
                        if p2_bottom > p2_top + 10: # Only if there is content
                            # Text 2
                            t2 = p2_page.within_bbox((p2_col_x, p2_top, 
                                                      p2_col_x+p2_col_w, p2_bottom)).extract_text() or ""
                            # Image 2
                            im2 = pdf_images[p2_page_idx].crop((
                                p2_col_x * scale, p2_top * scale,
                                (p2_col_x+p2_col_w) * scale, p2_bottom * scale
                            ))
                            parts.append((t2, im2))

                # --- MERGE & SAVE ---
                # Combine Text
                full_text = " ".join([p[0] for p in parts]).replace('\n', ' ')
                full_text = " ".join(full_text.split())

                # Combine Images (Stitch)
                final_img = parts[0][1]
                if len(parts) > 1:
                    final_img = stitch_images(final_img, parts[1][1])
                
                final_img = compress_and_clean(trim_whitespace(final_img))
                
                fname = f"Q_{start['q_num']}.png"
                final_img.save(os.path.join(output_dir, fname), optimize=True)
                
                curr_id += 1
                rows.append({
                    'unique_id': curr_id,
                    'Question No.': start['q_num'],
                    'Folder': folder_name,
                    'Exam': 'JEE Main',
                    'Subject': 'Physics',
                    'Source File': SOURCE_PDF_NAME,
                    'Correct Answer': ans_key.get(start['q_num'], ""),
                    'image_url': fname,
                    'q_width': final_img.width,
                    'q_height': final_img.height,
                    'pdf_Text': full_text,
                    'PDF_Text_Available': 'Yes' if len(full_text) > 10 else 'No'
                })

            except Exception as e:
                print(f"⚠️ Error Q{start.get('q_num')}: {e}")

    # --- 5. POST-PROCESSING (Merged) ---
    if rows:
        df = pd.DataFrame(rows)
        print("\n⚙️ Applying Post-Processing Logic...")
        
        df['PYQ'] = 'Yes'
        
        # 1. Year Extraction
        def get_year(txt):
            m = re.search(r'\[JEE \(Main\)-(\d{4})\]', str(txt), re.IGNORECASE)
            return int(m.group(1)) if m else 0
        df['PYQ_Year'] = df['pdf_Text'].apply(get_year)
        
        # 2. Question Type
        def get_type(ans):
            if pd.isna(ans): return "Numerical type"
            return "Single Correct" if str(ans).split('.')[0].strip() in ['1','2','3','4'] else "Numerical type"
        df['Question type'] = df['Correct Answer'].apply(get_type)

        # 3. Save
        if os.path.exists(OUTPUT_CSV_PATH):
            pd.concat([pd.read_csv(OUTPUT_CSV_PATH), df], ignore_index=True) \
              .drop_duplicates(subset=['Question No.', 'Folder'], keep='last') \
              .to_csv(OUTPUT_CSV_PATH, index=False)
        else:
            df.to_csv(OUTPUT_CSV_PATH, index=False)
            
        print(f"✅ Saved {len(rows)} Stitched Questions.")
        with open(CONFIG_PATH, 'w') as f: json.dump({"last_unique_id": curr_id}, f, indent=4)

if __name__ == "__main__":
    run_extraction()