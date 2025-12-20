import os
import pandas as pd
import pdfplumber
from pdf2image import convert_from_path
from PIL import Image, ImageChops
import re
import logging
import glob
from tqdm import tqdm
import json

# --- SUPPRESS WARNINGS ---
logging.getLogger("pdfminer").setLevel(logging.ERROR)

# --- CONFIGURATION (DYNAMIC) ---
# We expect config.json to be in the same folder as this script
CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(CURRENT_DIR, "config.json")

def load_config():
    if not os.path.exists(CONFIG_PATH):
        print(f"❌ Error: config.json not found at {CONFIG_PATH}")
        # Fallback to hardcoded defaults if config fails, just to be safe
        return {
            "BASE_PATH": r'D:\Main\3. Work - Teaching\Projects\Question extractor',
            "SOURCE_DIR": r'D:\Main\3. Work - Teaching\Books\0. Favs\JEE Mains PYQs',
            "DB_FILENAME": "DB Master.xlsx",
            "last_unique_id": 0
        }
    with open(CONFIG_PATH, 'r') as f:
        return json.load(f)

def get_new_unique_id():
    """
    Reads the last ID from config.json, increments it, saves it back,
    and returns the NEW ID.
    """
    if not os.path.exists(CONFIG_PATH):
        return 0 # Should not happen if load_config works

    try:
        with open(CONFIG_PATH, 'r+') as f:
            data = json.load(f)
            current_id = data.get("last_unique_id", 0)
            new_id = int(current_id) + 1
            
            # Update and save immediately
            data["last_unique_id"] = new_id
            f.seek(0)
            json.dump(data, f, indent=4)
            f.truncate()
            return new_id
    except Exception as e:
        print(f"❌ Error updating unique ID: {e}")
        return 0

# Load paths immediately
config = load_config()
BASE_PATH = config.get("BASE_PATH")
SOURCE_DIR = config.get("SOURCE_DIR")
DB_FILENAME = config.get("DB_FILENAME", "DB Master.xlsx")

OUTPUT_BASE = os.path.join(BASE_PATH, 'Processed_Database')
MASTER_DB_PATH = os.path.join(BASE_PATH, DB_FILENAME)


# --- HELPER FUNCTIONS ---

def trim_whitespace(im):
    try:
        bg = Image.new(im.mode, im.size, im.getpixel((0,0)))
        diff = ImageChops.difference(im, bg)
        diff = ImageChops.add(diff, diff, 2.0, -100)
        bbox = diff.getbbox()
        if bbox: return im.crop(bbox)
        return im
    except Exception: return im

def parse_answer_key(pdf_path, total_expected=None):
    """
    Scans the last 5 pages using the proven regex from the debug script.
    Pattern: 1. (2)
    """
    ans_map = {}
    with pdfplumber.open(pdf_path) as pdf:
        total_pages = len(pdf.pages)
        # Scan last 5 pages
        start_scan = max(0, total_pages - 5)
        
        for page_idx in range(start_scan, total_pages):
            page = pdf.pages[page_idx]
            text = page.extract_text()
            if not text: continue
            
            # --- THE PROVEN REGEX ---
            # 1. (\d+)   : Question Number
            # 2. \.      : Literal Dot
            # 3. \s* : Optional Space
            # 4. \(      : Literal Open Parenthesis
            # 5. ([^)]+) : Answer Content (Capture everything until closing paren)
            # 6. \)      : Literal Closing Parenthesis
            pattern = r'(\d+)\.\s*\(([^)]+)\)'
            
            matches = re.findall(pattern, text)
            
            for q_num, ans_val in matches:
                try:
                    q = int(q_num)
                    # Filter: Ignore if Q number is suspiciously large (likely a year "2024")
                    if q < 2000: 
                        ans_map[q] = ans_val
                except: pass
                
    return ans_map

def find_questions_and_tags(pdf_path):
    anchors = []
    with pdfplumber.open(pdf_path) as pdf:
        for page_idx, page in enumerate(pdf.pages):
            height = page.height
            MARGIN_TOP, MARGIN_BOTTOM = height * 0.05, height * 0.92
            words = page.extract_words(x_tolerance=2, y_tolerance=3, keep_blank_chars=False)
            words.sort(key=lambda w: (round(w['top'], 1), w['x0']))
            
            for i, word in enumerate(words):
                if word['top'] < MARGIN_TOP or word['top'] > MARGIN_BOTTOM: continue
                text = word['text'].strip()
                
                # Regex for Question Start (e.g. Q1., Q7*, Q15)
                # Matches "Q" -> digits -> optional symbol (*,^) -> optional separator (.:)
                match = re.match(r'^Q\s*(\d+)[^a-zA-Z0-9]?[\.:]?', text, re.IGNORECASE)
                
                if match:
                    q_num = int(match.group(1))
                    exam_year = "Mixed"
                    
                    # Look ahead for Year Tags
                    search_range = words[i:i+50] 
                    for w in search_range:
                        if w != word and re.match(r'^Q\s*\d+', w['text']): break
                        if re.match(r'20[0-2]\d', w['text']):
                            exam_year = re.sub(r'[^\d]', '', w['text'])
                            break
                    
                    anchors.append({'q_num': q_num, 'page_idx': page_idx, 'top': word['top'], 'year': exam_year})
    
    unique_anchors = {a['q_num']: a for a in anchors}
    return sorted(unique_anchors.values(), key=lambda x: x['q_num'])

def crop_mains_questions(pdf_path, anchors, ans_map, output_folder, file_prefix):
    if not anchors: return []
    try:
        pdf_images = convert_from_path(pdf_path, dpi=300, use_pdftocairo=True, strict=False)
    except: return []
    
    scale = 300 / 72 
    page_height = pdf_images[0].height
    TOP_MARGIN_PX, BOTTOM_MARGIN_PX = (page_height * 0.05), (page_height * 0.92)
    VERTICAL_PADDING = 10 
    processed_data = []

    pbar = tqdm(total=len(anchors), desc="   📸 Cropping", leave=False)

    for i, start in enumerate(anchors):
        q_num = start['q_num']
        next_q_page = anchors[i+1]['page_idx'] if i + 1 < len(anchors) else start['page_idx']
        end_loop_page = min(next_q_page + 1, start['page_idx'] + 3)
        images_to_stitch = []
        
        for p_idx in range(start['page_idx'], end_loop_page):
            if p_idx >= len(pdf_images): break
            img = pdf_images[p_idx]
            w, h = img.size
            if p_idx == start['page_idx']:
                curr_top = max(TOP_MARGIN_PX, (start['top'] * scale) - VERTICAL_PADDING)
                if p_idx == next_q_page and i + 1 < len(anchors):
                    curr_bottom = min((anchors[i+1]['top'] * scale) - VERTICAL_PADDING, BOTTOM_MARGIN_PX)
                else: curr_bottom = BOTTOM_MARGIN_PX
                if curr_bottom > curr_top + 20: images_to_stitch.append(img.crop((0, curr_top, w, curr_bottom)))
            else:
                curr_top = TOP_MARGIN_PX
                if p_idx == next_q_page and i + 1 < len(anchors):
                    curr_bottom = min((anchors[i+1]['top'] * scale) - VERTICAL_PADDING, BOTTOM_MARGIN_PX)
                else: curr_bottom = BOTTOM_MARGIN_PX
                images_to_stitch.append(img.crop((0, curr_top, w, curr_bottom)))
                if p_idx == next_q_page: break

        if images_to_stitch:
            total_h = sum(im.height for im in images_to_stitch)
            max_w = max(im.width for im in images_to_stitch)
            final_img = Image.new('RGB', (max_w, total_h), (255, 255, 255))
            y = 0
            for im in images_to_stitch:
                final_img.paste(im, (0, y)); y += im.height
            final_img = trim_whitespace(final_img)
            
            # Save logic
            if final_img.height > 40:
                final_img.save(os.path.join(output_folder, f"{file_prefix}_{q_num}.png"))
                processed_data.append({
                    'q_num': q_num, 
                    'answer': ans_map.get(q_num, ""), 
                    'year': start.get('year', 'Mixed')
                })
        
        pbar.update(1)
    
    pbar.close()
    return processed_data

def run_batch_extraction():
    print("="*60)
    print("      🧪 JEE MAINS BATCH EXTRACTOR v9.2 (Fixed & Configured)")
    print("="*60)
    print(f"📂 Base Path: {BASE_PATH}")
    print(f"📂 DB Path:   {MASTER_DB_PATH}")

    if not os.path.exists(SOURCE_DIR):
        print(f"❌ Source directory not found: {SOURCE_DIR}")
        return

    pdf_files = glob.glob(os.path.join(SOURCE_DIR, "*.pdf"))
    if not pdf_files:
        print("ℹ️ No PDFs found.")
        return

    processed_folders = set()
    if os.path.exists(MASTER_DB_PATH):
        try:
            df_existing = pd.read_excel(MASTER_DB_PATH)
            if 'Folder' in df_existing.columns:
                processed_folders = set(df_existing['Folder'].unique())
        except: pass

    # --- MAIN LOOP ---
    for pdf_path in tqdm(pdf_files, desc="📂 Total Files Progress", unit="file"):
        filename = os.path.basename(pdf_path)
        parts = [p.strip() for p in filename.replace('.pdf', '').split('-')]
        
        if len(parts) < 2: continue
        
        subject = parts[0]
        chapter = parts[-1]
        safe_chapter = "".join([c for c in chapter if c.isalnum() or c in (' ', '_')]).strip()
        folder_name = f"JEE_Mains_{safe_chapter}"
        
        if folder_name in processed_folders:
            continue

        print(f"\n🚀 Processing: {filename}")
        output_dir = os.path.join(OUTPUT_BASE, folder_name)
        os.makedirs(output_dir, exist_ok=True)

        ans_map = parse_answer_key(pdf_path)
        anchors = find_questions_and_tags(pdf_path)
        
        # Simple stats report
        matched_answers = len([q for q in anchors if q['q_num'] in ans_map])
        print(f"   🔍 Found {len(anchors)} questions. (Matched Answers: {matched_answers}/{len(anchors)})")

        extracted_data = crop_mains_questions(pdf_path, anchors, ans_map, output_dir, "Q")
        
        if extracted_data:
            new_rows = []
            for item in extracted_data:
                
                # --- UPDATE 1: Generate Unique ID & Increment Config ---
                unique_id = get_new_unique_id()
                
                new_rows.append({
                    'Q': item['q_num'],    # --- UPDATE 2: Changed from 'Question No.' to 'Q'
                    'Folder': folder_name,
                    'unique_id': unique_id, # --- UPDATE 3: Added Unique ID
                    'Subject': subject, 
                    'Chapter': chapter, 
                    'Exam': 'JEE Main',
                    'Question type': 'Single Correct', 
                    'Difficulty_tag': 'Medium',
                    'Correct Answer': item['answer'], 
                    'PYQ': 'Yes',
                    'PYQ_Year': item['year'] if len(item['year']) == 4 else "Mixed",
                    'QC_Status': 'Pass', 
                    'QC_Locked': 0, 
                    'manually updated': 0
                })
            
            # Atomic Save
            try:
                if os.path.exists(MASTER_DB_PATH):
                    df_master = pd.read_excel(MASTER_DB_PATH)
                    df_final = pd.concat([df_master, pd.DataFrame(new_rows)], ignore_index=True)
                else:
                    df_final = pd.DataFrame(new_rows)
                
                df_final.to_excel(MASTER_DB_PATH, index=False)
                # Show ID range in logs
                start_id = new_rows[0]['unique_id']
                end_id = new_rows[-1]['unique_id']
                print(f"   ✅ Saved {len(new_rows)} entries to DB. (IDs {start_id} - {end_id})")
            except PermissionError:
                print("   ❌ Error: DB Master.xlsx is open. Could not save.")
                continue

if __name__ == "__main__":
    run_batch_extraction()