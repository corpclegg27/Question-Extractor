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
ALLEN_CSV_PATH = os.path.join(BASE_PATH, 'Question Bank Allen.csv')
RAW_DATA_DIR = os.path.join(BASE_PATH, 'raw data')
TRIMMED_DIR = os.path.join(RAW_DATA_DIR, 'Trimmed_PDFs')
PROCESSED_BASE = os.path.join(BASE_PATH, 'Processed_Database')

os.makedirs(TRIMMED_DIR, exist_ok=True)
os.makedirs(PROCESSED_BASE, exist_ok=True)

# --- 2. ADVANCED PIXEL-SENSITIVE CROP ---
def pixel_sensitive_crop(img):
    """
    Scans from left to right to find the first block of 'ink' (Q Num),
    finds the subsequent whitespace gap, and crops there.
    """
    # Convert to Grayscale and Invert (Text = White, BG = Black)
    inverted_img = ImageOps.invert(img.convert('L'))
    data = np.array(inverted_img)

    # Sum pixels vertically: horizontal_projection[x] > 0 means ink is present
    horizontal_projection = np.sum(data, axis=0)
    width = len(horizontal_projection)

    start_search = 5 
    in_number_block = False
    crop_x = 0
    whitespace_count = 0
    MIN_GAP_WIDTH = 15 # Minimum pixels of whitespace after the number

    for x in range(start_search, width):
        if horizontal_projection[x] > 500: # Found 'ink'
            in_number_block = True
            whitespace_count = 0
        else: # Found whitespace
            if in_number_block:
                whitespace_count += 1
                if whitespace_count >= MIN_GAP_WIDTH:
                    # We found the end of the number and a sufficient gap
                    crop_x = x - whitespace_count + 2 # +2 for slight breathing room
                    break

    # Safety: If detection is weird (crops > 30% of image), use a conservative 5% fallback
    if crop_x == 0 or crop_x > (width * 0.30):
        crop_x = int(width * 0.05)

    return img.crop((crop_x, 0, width, img.size[1]))

# --- 3. IMAGE UTILITIES ---
def trim_whitespace(im):
    try:
        bg = Image.new(im.mode, im.size, im.getpixel((0,0)))
        diff = ImageChops.difference(im, bg)
        diff = ImageChops.add(diff, diff, 2.0, -100)
        bbox = diff.getbbox()
        return im.crop(bbox) if bbox else im
    except: return im

def compress_and_clean(img, noise_threshold=170):
    """Grayscale + Thresholding for app optimization."""
    gray = img.convert('L')
    return gray.point(lambda p: 255 if p > noise_threshold else p)

# --- 4. PDF PROCESSING ---
def trim_pdf_allen(input_filename, start_p, end_p, chapter):
    input_path = os.path.join(RAW_DATA_DIR, input_filename)
    output_name = f"Trimmed_{chapter}_p{start_p}_to{end_p}.pdf"
    output_path = os.path.join(TRIMMED_DIR, output_name)
    
    reader = PdfReader(input_path)
    writer = PdfWriter()
    for i in range(start_p - 1, min(end_p, len(reader.pages))):
        writer.add_page(reader.pages[i])
    with open(output_path, "wb") as f:
        writer.write(f)
    return output_name

def parse_answers(pdf_path):
    ans_map = {}
    letter_map = {"1": "A", "2": "B", "3": "C", "4": "D"}
    with pdfplumber.open(pdf_path) as pdf:
        text = pdf.pages[-1].extract_text()
    if not text or "ANSWER KEY" not in text.upper(): return {}
    
    que_lines = [l for l in text.split('\n') if l.startswith('Que.')]
    ans_lines = [l for l in text.split('\n') if l.startswith('Ans.')]
    for q_l, a_l in zip(que_lines, ans_lines):
        qs, ans = re.findall(r'\d+', q_l), re.findall(r'\d+', a_l)
        for q, a in zip(qs, ans):
            ans_map[int(q)] = letter_map.get(a, a)
    return ans_map

def find_anchors(pdf_path):
    anchors = []
    with pdfplumber.open(pdf_path) as pdf:
        for p_idx, page in enumerate(pdf.pages):
            mid = page.width / 2
            for word in page.extract_words():
                if re.match(r'^\d+\.$', word['text']):
                    col = 0 if word['x0'] < mid else 1
                    rel_x = word['x0'] if col == 0 else (word['x0'] - mid)
                    if rel_x < (page.width * 0.15):
                        anchors.append({'q_num': int(word['text'].replace('.','')), 'page_idx': p_idx, 'top': word['top'], 'col': col})
    return sorted(anchors, key=lambda x: x['q_num'])

# --- 5. STITCHING & SAVING ---
def crop_and_save_allen(pdf_path, anchors, output_folder):
    debug_dir = os.path.join(output_folder, "debug_crops")
    os.makedirs(debug_dir, exist_ok=True)
    
    print("⏳ Converting PDF to Images...")
    pdf_images = convert_from_path(pdf_path, dpi=300)
    scale = 300/72
    mid_px = pdf_images[0].size[0]/2
    footer_px = pdf_images[0].size[1] * 0.92

    for i, start in tqdm(enumerate(anchors), total=len(anchors), desc="✂️ Processing Qs"):
        q_num = start['q_num']
        nxt = anchors[i+1] if i+1 < len(anchors) else {'page_idx': start['page_idx'], 'top': footer_px/scale, 'col': start['col']}
        
        y1, y2 = max(0, (start['top']*scale)-15), (nxt['top']*scale)-15
        l, r = (0, mid_px) if start['col'] == 0 else (mid_px, pdf_images[0].size[0])
        
        if start['page_idx'] == nxt['page_idx'] and start['col'] == nxt['col']:
            stitched = pdf_images[start['page_idx']].crop((l, y1, r, min(y2, footer_px)))
        else:
            frag1 = pdf_images[start['page_idx']].crop((l, y1, r, footer_px))
            l2, r2 = (0, mid_px) if nxt['col'] == 0 else (mid_px, pdf_images[0].size[0])
            frag2 = pdf_images[nxt['page_idx']].crop((l2, 50*scale, r2, y2))
            stitched = Image.new('RGB', (frag1.width, frag1.height + frag2.height))
            stitched.paste(frag1, (0,0)); stitched.paste(frag2, (0, frag1.height))

        # 1. Trim whitespace first
        stitched = trim_whitespace(stitched)
        stitched.save(os.path.join(debug_dir, f"Q_{q_num}_BEFORE.png"))
        
        # 2. Apply Dynamic Pixel Crop
        final_crop = pixel_sensitive_crop(stitched)
        
        # 3. Compress and Save
        final_clean = trim_whitespace(final_crop)
        compressed = compress_and_clean(final_clean)
        compressed.save(os.path.join(output_folder, f"Q_{q_num}.png"), "PNG", optimize=True)

# --- 6. RUNNER ---
def run_allen_extractor(source_pdf, start_p, end_p, chapter, subject):
    print(f"\n🚀 STARTING: {chapter}")
    trimmed_file = trim_pdf_allen(source_pdf, start_p, end_p, chapter)
    trimmed_path = os.path.join(TRIMMED_DIR, trimmed_file)
    output_dir = os.path.join(PROCESSED_BASE, trimmed_file.replace(".pdf", ""))
    os.makedirs(output_dir, exist_ok=True)

    with open(CONFIG_PATH, 'r') as f: config = json.load(f)
    curr_id = int(config.get("last_unique_id", 0))

    ans_map = parse_answers(trimmed_path)
    anchors = find_anchors(trimmed_path)
    crop_and_save_allen(trimmed_path, anchors, output_dir)

    rows = []
    for a in anchors:
        curr_id += 1
        rows.append({'unique_id': curr_id, 'Question No.': a['q_num'], 'Q': a['q_num'], 'Folder': trimmed_file.replace(".pdf", ""), 'Subject': subject, 'Chapter': chapter, 'Correct Answer': ans_map.get(a['q_num'], ""), 'QC_Status': 'Pending QC', 'Exam': 'NEET', 'PDF_Text_Available': 'No'})

    df_new = pd.DataFrame(rows)
    if os.path.exists(ALLEN_CSV_PATH):
        pd.concat([pd.read_csv(ALLEN_CSV_PATH), df_new], ignore_index=True).to_csv(ALLEN_CSV_PATH, index=False)
    else:
        df_new.to_csv(ALLEN_CSV_PATH, index=False)

    config["last_unique_id"] = curr_id
    with open(CONFIG_PATH, 'w') as f: json.dump(config, f, indent=4)
    print(f"✅ DONE. Check Processed_Database for {chapter}")

if __name__ == "__main__":
    run_allen_extractor("Allen NEET Physics Module.pdf", 1030, 1041, "Moving Charges", "Physics")