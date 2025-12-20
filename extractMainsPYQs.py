import os
import pandas as pd
import pdfplumber
from pdf2image import convert_from_path
from PIL import Image, ImageChops
import re
import logging

# --- SUPPRESS WARNINGS ---
logging.getLogger("pdfminer").setLevel(logging.ERROR)

# --- CONFIGURATION ---
BASE_PATH = 'D:/Main/3. Work - Teaching/Projects/Question extractor/'
OUTPUT_BASE = os.path.join(BASE_PATH, 'Processed_Database')
MASTER_DB_PATH = os.path.join(BASE_PATH, 'DB Master.xlsx')

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
    Scans the last 5 pages. 
    Improved Regex matches:
    - Standard: "1. (3)"
    - Numerical: "22. 50" or "22. (50)" or "22. 50.0"
    """
    print("🔑 Scanning for Answer Key...")
    ans_map = {}
    
    with pdfplumber.open(pdf_path) as pdf:
        total_pages = len(pdf.pages)
        start_scan = max(0, total_pages - 5)
        
        for page_idx in range(start_scan, total_pages):
            page = pdf.pages[page_idx]
            text = page.extract_text()
            if not text: continue
            
            # --- IMPROVED REGEX ---
            # 1. (\d+)       -> Question Number
            # 2. \s*[\.:]?   -> Separator (Dot, Colon, or space)
            # 3. \s* -> Space
            # 4. (?:\(? ... \)?) -> Optional parentheses wrapper
            # 5. ([a-dA-D0-9]+(?:\.\d+)?) -> The Content:
            #       - [a-dA-D] : Option chars
            #       - 0-9+     : Integer numbers (multi-digit supported!)
            #       - (?:\.\d+)? : Optional decimal part (e.g. 0.5)
            
            pattern = r'(\d+)\s*[\.:]?\s*\(?([a-dA-D0-9]+(?:\.\d+)?)\)?'
            
            matches = re.findall(pattern, text)
            
            for q_num, ans in matches:
                try:
                    q = int(q_num)
                    # Filter: Ignore if Q number is suspiciously large (likely a year "2024" misread as Q number)
                    # Heuristic: If we expect ~300 questions, anything > 2000 is probably a year.
                    if q < 2000:
                        ans_map[q] = ans
                except: pass
                
    found = len(ans_map)
    print(f"   -> Successfully extracted {found} answers.")
    
    if total_expected and found < total_expected:
        missing = [i for i in range(1, total_expected+1) if i not in ans_map]
        if missing:
            print(f"   ⚠️ Missing {len(missing)} answers: {missing[:10]}... (Check if format differs)")
            
    return ans_map

def find_questions_and_tags(pdf_path):
    anchors = []
    print(f"🔍 Scanning for Questions & Tags...")
    
    with pdfplumber.open(pdf_path) as pdf:
        for page_idx, page in enumerate(pdf.pages):
            width = page.width
            height = page.height
            
            MARGIN_TOP = height * 0.05
            MARGIN_BOTTOM = height * 0.92
            
            words = page.extract_words(x_tolerance=2, y_tolerance=3, keep_blank_chars=False)
            words.sort(key=lambda w: (round(w['top'], 1), w['x0']))
            
            for i, word in enumerate(words):
                if word['top'] < MARGIN_TOP or word['top'] > MARGIN_BOTTOM: continue
                text = word['text'].strip()
                
                # Detect Question Start "Q1."
                match = re.match(r'^Q\s*(\d+)\s*[\.:]', text, re.IGNORECASE)
                if match:
                    q_num = int(match.group(1))
                    
                    # --- TAG DETECTION ---
                    # Look for Year pattern (e.g. "2019", "2024") in nearby text
                    exam_year = "Mixed"
                    search_range = words[i:i+50] 
                    for w in search_range:
                        if w != word and re.match(r'^Q\s*\d+', w['text']): break
                        if re.match(r'20[0-2]\d', w['text']):
                            exam_year = w['text']
                            # Clean punctuation from year (e.g. "2024)" -> "2024")
                            exam_year = re.sub(r'[^\d]', '', exam_year)
                            break
                    
                    anchors.append({
                        'q_num': q_num,
                        'page_idx': page_idx,
                        'top': word['top'],
                        'bottom': word['bottom'],
                        'year': exam_year
                    })

    # Deduplicate
    unique_anchors = {}
    for a in anchors:
        if a['q_num'] not in unique_anchors:
            unique_anchors[a['q_num']] = a
            
    return sorted(unique_anchors.values(), key=lambda x: x['q_num'])

def crop_mains_questions(pdf_path, anchors, ans_map, output_folder, file_prefix):
    if not anchors: return []

    print(f"📸 Converting PDF...")
    try:
        pdf_images = convert_from_path(pdf_path, dpi=300, use_pdftocairo=True, strict=False)
    except Exception as e:
        print(f"❌ Conversion Error: {e}")
        return []

    if not pdf_images: return []

    scale = 300 / 72 
    page_height = pdf_images[0].height
    
    TOP_MARGIN_PX = (page_height * 0.05)
    BOTTOM_MARGIN_PX = (page_height * 0.90)
    VERTICAL_PADDING = 10 

    processed_data = []

    for i, start in enumerate(anchors):
        q_num = start['q_num']
        
        if i + 1 < len(anchors):
            end = anchors[i+1]
            if start['page_idx'] == end['page_idx']:
                end_target = end['top']
            else:
                end_target = BOTTOM_MARGIN_PX/scale
        else:
            end_target = BOTTOM_MARGIN_PX/scale
            
        start_page = start['page_idx']
        
        # Limit stitch to 2 pages
        if i + 1 < len(anchors):
            next_q_page = anchors[i+1]['page_idx']
        else:
            next_q_page = start_page 
            
        end_loop_page = min(next_q_page + 1, start_page + 3)
        
        images_to_stitch = []
        
        for p_idx in range(start_page, end_loop_page):
            if p_idx >= len(pdf_images): break
            img = pdf_images[p_idx]
            w, h = img.size
            
            if p_idx == start_page:
                curr_top = max(TOP_MARGIN_PX, (start['top'] * scale) - VERTICAL_PADDING)
                if p_idx == next_q_page and i + 1 < len(anchors):
                    next_top = (anchors[i+1]['top'] * scale) - VERTICAL_PADDING
                    curr_bottom = min(next_top, BOTTOM_MARGIN_PX)
                else:
                    curr_bottom = BOTTOM_MARGIN_PX
                
                if curr_bottom > curr_top + 20:
                    images_to_stitch.append(img.crop((0, curr_top, w, curr_bottom)))
            else:
                curr_top = TOP_MARGIN_PX
                if p_idx == next_q_page and i + 1 < len(anchors):
                    next_top = (anchors[i+1]['top'] * scale) - VERTICAL_PADDING
                    curr_bottom = min(next_top, BOTTOM_MARGIN_PX)
                else:
                    curr_bottom = BOTTOM_MARGIN_PX
                    
                images_to_stitch.append(img.crop((0, curr_top, w, curr_bottom)))
                if p_idx == next_q_page: break

        if not images_to_stitch: continue
        
        total_h = sum(im.height for im in images_to_stitch)
        max_w = max(im.width for im in images_to_stitch)
        final_img = Image.new('RGB', (max_w, total_h), (255, 255, 255))
        y = 0
        for im in images_to_stitch:
            final_img.paste(im, (0, y))
            y += im.height
            
        final_img = trim_whitespace(final_img)

        if final_img.height > 40:
            save_path = f"{output_folder}/{file_prefix}_{q_num}.png"
            final_img.save(save_path)
            
            ans = ans_map.get(q_num, "")
            processed_data.append({
                'q_num': q_num, 
                'answer': ans,
                'year': start.get('year', 'Mixed')
            })
            print(f"   -> Captured Q{q_num} (Ans: {ans}) [{start.get('year', '')}]")

    return processed_data

# --- MAIN EXECUTION ---
def run_mains_extraction():
    print("="*40)
    print("      🧪 JEE MAINS PYQ EXTRACTOR v6.0   ")
    print("="*40)

    pdf_path = input("Enter PDF Path (drag & drop): ").strip().strip('"')
    if not os.path.exists(pdf_path): return

    filename = os.path.basename(pdf_path)
    parts = filename.replace('.pdf', '').split('-')
    chapter_guess = parts[-1].strip() if len(parts) > 1 else "General"

    subject = input("Subject: ").strip() or "Physics"
    chapter = input(f"Chapter [{chapter_guess}]: ").strip() or chapter_guess
    
    safe_chapter = "".join([c for c in chapter if c.isalnum() or c in (' ', '_')]).strip()
    folder_name = f"JEE_Mains_{safe_chapter}"
    
    counter = 1
    final_folder = folder_name
    while os.path.exists(os.path.join(OUTPUT_BASE, final_folder)):
        counter += 1
        final_folder = f"{folder_name}_{counter}"
    
    output_dir = os.path.join(OUTPUT_BASE, final_folder)
    os.makedirs(output_dir, exist_ok=True)
    
    print(f"\n📂 Output: {final_folder}")

    # 1. Find Questions
    anchors = find_questions_and_tags(pdf_path)
    total_q = len(anchors)
    print(f"✅ Found {total_q} questions.")
    
    # 2. Parse Keys
    ans_map = parse_answer_key(pdf_path, total_expected=total_q)
    
    # 3. Crop
    extracted_data = crop_mains_questions(pdf_path, anchors, ans_map, output_dir, "Q")
    
    # 4. Save
    if extracted_data:
        new_rows = []
        for item in extracted_data:
            # If no year found, keep "Mixed"
            year_val = item['year'] if len(item['year']) == 4 else "Mixed"
            
            new_rows.append({
                'Question No.': item['q_num'],
                'Folder': final_folder,
                'Subject': subject,
                'Chapter': chapter,
                'Exam': 'JEE Main',
                'Question type': 'Single Correct',
                'Difficulty_tag': 'Medium',
                'Correct Answer': item['answer'],
                'PYQ': 'Yes',
                'PYQ_Year': year_val, 
                'QC_Status': 'Pass',
                'QC_Locked': 1,
                'manually updated': 0
            })
        
        df_new = pd.DataFrame(new_rows)
        if os.path.exists(MASTER_DB_PATH):
            df_master = pd.read_excel(MASTER_DB_PATH)
            df_final = pd.concat([df_master, df_new], ignore_index=True)
        else:
            df_final = df_new
            
        try:
            df_final.to_excel(MASTER_DB_PATH, index=False)
            print("💾 Database updated!")
        except Exception as e: print(e)

if __name__ == "__main__":
    run_mains_extraction()