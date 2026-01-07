import os
import re
import json
import pandas as pd
import pdfplumber
from PIL import Image, ImageChops
from pdf2image import convert_from_path

# --- 1. CONFIGURATION ---
BASE_PATH = 'D:/Main/3. Work - Teaching/Projects/Question extractor'
CONFIG_PATH = os.path.join(BASE_PATH, 'config.json')
ALLEN_CSV_PATH = os.path.join(BASE_PATH, 'Question Bank Allen.csv')
SOURCE_DIR = os.path.join(BASE_PATH, 'raw data', 'Trimmed_PDFs')
OUTPUT_BASE = os.path.join(BASE_PATH, 'Processed_Database')

# --- 2. HELPERS ---
def trim_whitespace(im):
    """Removes outer white margins from cropped images."""
    try:
        bg = Image.new(im.mode, im.size, im.getpixel((0,0)))
        diff = ImageChops.difference(im, bg)
        diff = ImageChops.add(diff, diff, 2.0, -100)
        bbox = diff.getbbox()
        if bbox: return im.crop(bbox)
        return im
    except Exception: return im

# --- 3. ANSWER KEY PARSER ---
def parse_allen_tabular_answers(pdf_path):
    """
    Parses the tabular 'Que.' and 'Ans.' string format.
    Converts numerical answers 1,2,3,4 to A,B,C,D.
    """
    ans_map = {}
    letter_map = {"1": "A", "2": "B", "3": "C", "4": "D"}

    with pdfplumber.open(pdf_path) as pdf:
        last_page = pdf.pages[-1]
        text = last_page.extract_text()
    
    if not text or "ANSWER KEY" not in text.upper():
        return {}

    lines = text.split('\n')
    que_lines = [l for l in lines if l.startswith('Que.')]
    ans_lines = [l for l in lines if l.startswith('Ans.')]

    for q_line, a_line in zip(que_lines, ans_lines):
        questions = re.findall(r'\d+', q_line)
        answers = re.findall(r'\d+', a_line)
        
        for q, a in zip(questions, answers):
            ans_val = letter_map.get(a, a) 
            ans_map[int(q)] = ans_val

    return ans_map

# --- 4. ANCHOR DETECTION ---
def find_allen_anchors(pdf_path):
    """Finds question numbers at column starts."""
    anchors = []
    with pdfplumber.open(pdf_path) as pdf:
        for page_idx, page in enumerate(pdf.pages):
            midpoint = page.width / 2
            words = page.extract_words()
            for word in words:
                text = word['text'].strip()
                if re.match(r'^\d+\.$', text):
                    col = 0 if word['x0'] < midpoint else 1
                    rel_x = word['x0'] if col == 0 else (word['x0'] - midpoint)
                    if rel_x < (page.width * 0.15):
                        anchors.append({
                            'q_num': int(text.replace('.', '')),
                            'page_idx': page_idx, 
                            'top': word['top'], 
                            'col': col
                        })
    return sorted(anchors, key=lambda x: x['q_num'])

# --- 5. IMAGE CROP & STITCH ---
def crop_and_save_allen(pdf_path, anchors, output_folder):
    """Handles multi-column question stitching."""
    try:
        pdf_images = convert_from_path(pdf_path, dpi=300)
    except Exception as e:
        print(f"Error converting PDF to image: {e}")
        return

    page_width, page_height = pdf_images[0].size
    scale = 300 / 72 
    midpoint_px = page_width / 2
    FOOTER_CUTOFF_PX = page_height * 0.92
    VERTICAL_PADDING = 15
    TOP_MARGIN = 50 * scale 

    for i, start in enumerate(anchors):
        q_num = start['q_num']
        end = anchors[i+1] if i + 1 < len(anchors) else {'page_idx': start['page_idx'], 'top': FOOTER_CUTOFF_PX/scale, 'col': start['col']}
        
        start_top_px = max(0, (start['top'] * scale) - VERTICAL_PADDING)
        end_top_px = (end['top'] * scale) - VERTICAL_PADDING
        
        images_to_stitch = []
        left = 0 if start['col'] == 0 else midpoint_px
        right = midpoint_px if start['col'] == 0 else page_width
        
        if start['page_idx'] == end['page_idx'] and start['col'] == end['col']:
            images_to_stitch.append(pdf_images[start['page_idx']].crop((left, start_top_px, right, min(end_top_px, FOOTER_CUTOFF_PX))))
        else:
            images_to_stitch.append(pdf_images[start['page_idx']].crop((left, start_top_px, right, FOOTER_CUTOFF_PX)))
            left_e = 0 if end['col'] == 0 else midpoint_px
            right_e = midpoint_px if end['col'] == 0 else page_width
            images_to_stitch.append(pdf_images[end['page_idx']].crop((left_e, TOP_MARGIN, right_e, end_top_px)))

        if images_to_stitch:
            final_img = Image.new('RGB', (int(max(im.width for im in images_to_stitch)), sum(im.height for im in images_to_stitch)), (255, 255, 255))
            y = 0
            for im in images_to_stitch:
                final_img.paste(im, (0, y)); y += im.height
            trim_whitespace(final_img).save(os.path.join(output_folder, f"Q_{q_num}.png"))

# --- 6. EXECUTION ---
def process_allen_batch(pdf_filename, subject, chapter):
    pdf_path = os.path.join(SOURCE_DIR, pdf_filename)
    folder_name = pdf_filename.replace(".pdf", "")
    output_dir = os.path.join(OUTPUT_BASE, folder_name)
    os.makedirs(output_dir, exist_ok=True)

    if os.path.exists(CONFIG_PATH):
        with open(CONFIG_PATH, 'r') as f:
            config = json.load(f)
    else:
        config = {"last_unique_id": 0}
    
    current_id = int(config.get("last_unique_id", 0))

    ans_map = parse_allen_tabular_answers(pdf_path)
    anchors = find_allen_anchors(pdf_path)
    crop_and_save_allen(pdf_path, anchors, output_dir)

    new_rows = []
    for a in anchors:
        current_id += 1
        new_rows.append({
            'unique_id': current_id,
            'Question No.': a['q_num'],
            'Q': a['q_num'],
            'Folder': folder_name,
            'Subject': subject,
            'Chapter': chapter,
            'Correct Answer': ans_map.get(a['q_num'], ""),
            'QC_Status': 'Pending QC',
            'Exam': 'NEET',
            'PDF_Text_Available': 'No'
        })

    df_new = pd.DataFrame(new_rows)
    if os.path.exists(ALLEN_CSV_PATH):
        df_old = pd.read_csv(ALLEN_CSV_PATH)
        pd.concat([df_old, df_new], ignore_index=True).to_csv(ALLEN_CSV_PATH, index=False)
    else:
        df_new.to_csv(ALLEN_CSV_PATH, index=False)

    config["last_unique_id"] = current_id
    with open(CONFIG_PATH, 'w') as f:
        json.dump(config, f, indent=4)

    print(f"✅ Processed {len(new_rows)} questions into '{ALLEN_CSV_PATH}'")

if __name__ == "__main__":
    FILE = "Trimmed_Moving charges_p1030_to_p1041.pdf"
    process_allen_batch(FILE, "Physics", "Moving Charges")