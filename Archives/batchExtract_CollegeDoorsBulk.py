import os
import glob
import pandas as pd
import pdfplumber
import json
import re
import time
from pdf2image import convert_from_path
from PIL import Image, ImageChops
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
    print(f"✅ Loaded config file.")
else:
    print(f"⚠️ Config not found. Using defaults.")

BASE_PATH = config.get('BASE_PATH', DEFAULT_BASE_PATH)
RAW_DATA_PATH = os.path.join(BASE_PATH, 'raw data') 
OUTPUT_BASE = os.path.join(BASE_PATH, 'Processed_Database')

# PATHS FOR DB
MASTER_XLSX_PATH = os.path.join(BASE_PATH, 'DB Master.xlsx') # Read-Only Source
MASTER_CSV_PATH = os.path.join(BASE_PATH, 'DB Master.csv')   # Active Write Target

METADATA_FILE_PATH = os.path.join(BASE_PATH, 'DB Metadata.xlsx')

start_id = config.get('last_unique_id', config.get('latest_question_id', 0))

print(f"🔧 CONFIGURATION CHECK:")
print(f"   - Source Folder : {RAW_DATA_PATH}")
print(f"   - Metadata File : {METADATA_FILE_PATH}")
print(f"   - Master CSV    : {MASTER_CSV_PATH}")
print(f"   - ID Counter    : Starts at {start_id}")

os.makedirs(OUTPUT_BASE, exist_ok=True)


# --- 2. HELPER FUNCTIONS ---

def trim_whitespace(im):
    try:
        bg = Image.new(im.mode, im.size, im.getpixel((0,0)))
        diff = ImageChops.difference(im, bg)
        diff = ImageChops.add(diff, diff, 2.0, -100)
        bbox = diff.getbbox()
        if bbox: return im.crop(bbox)
        return im
    except Exception: return im

def find_anchors_robust(pdf_path, max_val=None, is_solution=False):
    anchors = []
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
                is_strong_anchor = False 

                match = re.match(r'^(?:Q|Sol|Solution|S)?[\.\s]*(\d+)[\.\s:)]*$', text, re.IGNORECASE)
                if match:
                    found_q_num = int(match.group(1))
                    if text[0].isalpha(): is_strong_anchor = True
                
                elif text.lower() in ["q", "q.", "sol", "sol.", "solution", "solution:"] and i + 1 < len(words):
                    next_word = words[i+1]
                    match_next = re.match(r'^(\d+)[\.\s:)]*$', next_word['text'])
                    if match_next:
                        found_q_num = int(match_next.group(1))
                        is_strong_anchor = True 
                        i += 1 

                if found_q_num:
                    if max_val and found_q_num > max_val: 
                        found_q_num = None
                    else:
                        if is_strong_anchor:
                            if relative_x > (width * 0.20): found_q_num = None 
                        else:
                            if relative_x > (width * 0.05): found_q_num = None

                    if found_q_num:
                        anchors.append({'q_num': found_q_num, 'page_idx': page_idx, 'top': curr_word['top'], 'col': col})
                i += 1

    unique_anchors = {}
    for a in anchors:
        if a['q_num'] not in unique_anchors: unique_anchors[a['q_num']] = a
    return sorted(unique_anchors.values(), key=lambda x: x['q_num'])

def extract_text_content(pdf_path, anchors, is_two_column=True):
    extracted_text = {}
    with pdfplumber.open(pdf_path) as pdf:
        pages = pdf.pages
        if not pages: return {}
        
        width = pages[0].width
        height = pages[0].height
        midpoint = width / 2
        BOTTOM_LIMIT = height * 0.92

        for i, start in enumerate(anchors):
            q_num = start['q_num']
            text_segments = []
            
            if i + 1 < len(anchors):
                end = anchors[i+1]
            else:
                end = {'page_idx': start['page_idx'], 'top': BOTTOM_LIMIT, 'col': start['col']}

            curr_pidx = start['page_idx']
            curr_col = start['col']
            curr_top = start['top']
            
            while True:
                page = pages[curr_pidx]
                if is_two_column:
                    x0 = 0 if curr_col == 0 else midpoint
                    x1 = midpoint if curr_col == 0 else width
                else:
                    x0 = 0; x1 = width
                
                if curr_pidx == end['page_idx'] and curr_col == end['col']:
                    bottom = end['top']
                    done = True
                else:
                    bottom = BOTTOM_LIMIT
                    done = False
                
                if bottom > curr_top:
                    try:
                        cropped_page = page.crop((x0, curr_top, x1, bottom))
                        text = cropped_page.extract_text()
                        if text: text_segments.append(text)
                    except Exception: pass
                
                if done: break
                
                if is_two_column:
                    if curr_col == 0:
                        curr_col = 1; curr_top = 50 
                    else:
                        curr_col = 0; curr_pidx += 1; curr_top = 50
                else:
                    curr_pidx += 1; curr_top = 50
                
                if curr_pidx >= len(pages): break

            full_text = "\n".join(text_segments).strip()
            extracted_text[q_num] = full_text
            
    return extracted_text

def crop_and_save_standard(pdf_path, anchors, output_folder, suffix_type, is_two_column=True):
    try: 
        pdf_images = convert_from_path(pdf_path, dpi=300)
    except: 
        print(f"❌ Error converting PDF: {os.path.basename(pdf_path)}")
        return

    if not pdf_images: return
    page_width, page_height = pdf_images[0].size
    scale = 300 / 72 
    midpoint_px = (page_width / 2) 
    FOOTER_CUTOFF_PX = page_height * 0.92
    VERTICAL_PADDING = 15 
    TOP_MARGIN = 50 * scale 
    
    pbar = tqdm(total=len(anchors), desc=f"   📷 Cropping {suffix_type}", leave=True)
    
    for i, start in enumerate(anchors):
        q_num = start['q_num']
        
        if i + 1 < len(anchors): 
            end = anchors[i+1]
        else: 
            end = {'page_idx': start['page_idx'], 'top': FOOTER_CUTOFF_PX / scale, 'col': start['col']} 

        start_top_px = max(0, (start['top'] * scale) - VERTICAL_PADDING)
        end_top_px = (end['top'] * scale) - VERTICAL_PADDING

        try:
            images_to_stitch = []
            if is_two_column:
                start_left = 0 if start['col'] == 0 else midpoint_px
                start_right = midpoint_px if start['col'] == 0 else page_width
                end_left = 0 if end['col'] == 0 else midpoint_px
                end_right = midpoint_px if end['col'] == 0 else page_width
            else:
                start_left = 0; start_right = page_width
                end_left = 0; end_right = page_width

            if start['page_idx'] == end['page_idx']:
                if start['col'] == end['col']:
                    bottom = min(end_top_px, FOOTER_CUTOFF_PX)
                    if bottom <= start_top_px: bottom = start_top_px + 10 
                    images_to_stitch.append(pdf_images[start['page_idx']].crop((start_left, start_top_px, start_right, bottom)))
                else:
                    if FOOTER_CUTOFF_PX > start_top_px:
                        images_to_stitch.append(pdf_images[start['page_idx']].crop((start_left, start_top_px, start_right, FOOTER_CUTOFF_PX)))
                    if end_top_px > TOP_MARGIN:
                        images_to_stitch.append(pdf_images[start['page_idx']].crop((end_left, TOP_MARGIN, end_right, end_top_px)))
            else:
                if FOOTER_CUTOFF_PX > start_top_px:
                    images_to_stitch.append(pdf_images[start['page_idx']].crop((start_left, start_top_px, start_right, FOOTER_CUTOFF_PX)))
                for mid_idx in range(start['page_idx'] + 1, end['page_idx']):
                    if FOOTER_CUTOFF_PX > TOP_MARGIN:
                        images_to_stitch.append(pdf_images[mid_idx].crop((start_left, TOP_MARGIN, start_right, FOOTER_CUTOFF_PX)))
                if end_top_px > TOP_MARGIN:
                    images_to_stitch.append(pdf_images[end['page_idx']].crop((end_left, TOP_MARGIN, end_right, end_top_px)))

            if images_to_stitch:
                total_height = sum(img.height for img in images_to_stitch)
                if total_height > 0:
                    max_width = max(img.width for img in images_to_stitch)
                    final_img = Image.new('RGB', (max_width, total_height), (255, 255, 255))
                    y_offset = 0
                    for img in images_to_stitch:
                        final_img.paste(img, (0, y_offset))
                        y_offset += img.height
                    
                    final_img = trim_whitespace(final_img)
                    filename = f"{suffix_type}_{q_num}.png"
                    final_img.save(os.path.join(output_folder, filename))
                
        except Exception as e:
            print(f"❌ Error Saving {suffix_type}_{q_num}: {e}")
            
        pbar.update(1)
    pbar.close()

# --- 3. TARGETING ---
print(f"\n--- 🔍 SCANNING ---")
processed_folders = set()
final_master_df = pd.DataFrame()

# 1. Load Processed List (Switching to CSV logic)
if os.path.exists(MASTER_CSV_PATH):
    try:
        final_master_df = pd.read_csv(MASTER_CSV_PATH)
        print(f"✅ Active CSV Loaded ({len(final_master_df)} rows).")
    except Exception as e:
        print(f"⚠️ Error reading Master CSV: {e}")

elif os.path.exists(MASTER_XLSX_PATH):
    # Fallback: Initialize CSV from Read-Only Excel if CSV doesn't exist
    try:
        print(f"ℹ️ CSV not found. Initializing from DB Master.xlsx...")
        final_master_df = pd.read_excel(MASTER_XLSX_PATH)
        # Save immediately to establish the CSV
        final_master_df.to_csv(MASTER_CSV_PATH, index=False)
        print(f"✅ Created DB Master.csv from Excel source.")
    except Exception as e:
        print(f"⚠️ Error reading Master XLSX: {e}")

if 'Folder' in final_master_df.columns:
    processed_folders = set(final_master_df['Folder'].dropna().astype(str).unique())
    print(f"   Found {len(processed_folders)} processed folders in DB.")

# 2. Load Central Metadata
central_meta_df = pd.DataFrame()
valid_folders_set = set()

if os.path.exists(METADATA_FILE_PATH):
    try:
        central_meta_df = pd.read_excel(METADATA_FILE_PATH, sheet_name='CD_Metadata')
        central_meta_df.columns = central_meta_df.columns.str.strip()
        
        if 'Folder' in central_meta_df.columns:
            central_meta_df['Folder'] = central_meta_df['Folder'].astype(str).str.strip()
            valid_folders_set = set(central_meta_df['Folder'].unique())
            
        print(f"✅ Metadata Loaded. Found {len(central_meta_df)} rows. {len(valid_folders_set)} valid folders.")
    except Exception as e:
        print(f"⚠️ Warning: Could not load 'CD_Metadata' from Excel. {e}")
else:
    print("⚠️ Warning: DB Metadata.xlsx not found.")

if not os.path.exists(RAW_DATA_PATH):
    print(f"❌ CRITICAL: Folder not found: {RAW_DATA_PATH}")
    exit()

all_subfolders = [f.path for f in os.scandir(RAW_DATA_PATH) if f.is_dir()]
target_folders = []

print(f"📂 Looking in 'raw data'...")

for folder_path in all_subfolders:
    folder_name = os.path.basename(folder_path)
    clean_name = folder_name.strip()
    
    if not clean_name.startswith("CollegeDoors"): 
        continue
    
    if clean_name not in valid_folders_set:
        continue

    if clean_name in processed_folders: 
        continue

    print(f"   ✅ FOUND NEW: {clean_name}")
    target_folders.append(folder_path)

if not target_folders:
    print("\n🎉 All valid folders from Metadata are processed! Exiting.")
    exit()

# --- 4. PROCESSING LOOP ---
start_time = time.time()
current_global_id = start_id
new_data_list = []

for folder in tqdm(target_folders, desc="Processing Batches"):
    test_name = os.path.basename(folder).strip()
    print(f"\n🔹 Processing: {test_name}")
    
    q_papers = glob.glob(os.path.join(folder, "*question_paper.pdf"))
    sol_pdfs = glob.glob(os.path.join(folder, "*solution_pdf.pdf"))
    excel_keys = glob.glob(os.path.join(folder, "*excel_answer_key.xlsx")) + glob.glob(os.path.join(folder, "*excel_answer_key.csv"))
    
    if not (q_papers and sol_pdfs and excel_keys):
        print(f"   ⚠️ Missing required files. Skipping.")
        continue

    try:
        key_path = excel_keys[0]
        key_df = pd.read_csv(key_path) if key_path.endswith('.csv') else pd.read_excel(key_path)
        total_questions = key_df['Question No.'].max() if 'Question No.' in key_df.columns else len(key_df)
        
        # --- METADATA LOGIC ---
        folder_specific_meta = pd.DataFrame()
        if not central_meta_df.empty:
            folder_specific_meta = central_meta_df[central_meta_df['Folder'] == test_name].copy()
        
        if not folder_specific_meta.empty:
            meta_df = folder_specific_meta
            if 'Q' in meta_df.columns:
                meta_df = meta_df.rename(columns={'Q': 'Question No.'})
            print(f"   ℹ️ Loaded metadata from Central Sheet ({len(meta_df)} rows).")
        else:
            print(f"   ⚠️ Metadata missing in Excel. Creating fallback.")
            meta_df = pd.DataFrame({'Question No.': key_df['Question No.']})
            meta_df['Topic'] = "Unknown"
            meta_df['Sub-Topic'] = "Unknown"
            meta_df['Subject'] = "Unknown"

    except Exception as e:
        print(f"   ❌ Data Load Error: {e}")
        continue
    
    test_output_dir = os.path.join(OUTPUT_BASE, test_name)
    os.makedirs(test_output_dir, exist_ok=True)
    
    # 1. Calculate Anchors
    q_anchors = find_anchors_robust(q_papers[0], max_val=total_questions)
    sol_anchors = find_anchors_robust(sol_pdfs[0], max_val=total_questions, is_solution=True)

    # 2. Extract Images
    crop_and_save_standard(q_papers[0], q_anchors, test_output_dir, "Q", is_two_column=True)
    crop_and_save_standard(sol_pdfs[0], sol_anchors, test_output_dir, "Sol", is_two_column=True)

    # 3. Extract Text
    print("   📝 Extracting & Cleaning Text...")
    extracted_text_map = extract_text_content(q_papers[0], q_anchors, is_two_column=True)

    # DataFrame Logic
    meta_df['Folder'] = test_name
    
    if 'Question No.' in meta_df.columns and 'Question No.' in key_df.columns:
        combined_df = pd.merge(meta_df, key_df, on='Question No.', how='left', suffixes=('', '_key'))
    else:
        combined_df = pd.concat([meta_df.reset_index(drop=True), key_df.reset_index(drop=True)], axis=1)

    unique_ids_col = []
    pdf_text_col = []
    text_avail_col = []
    
    for idx, row in combined_df.iterrows():
        q_num = row.get('Question No.')
        if pd.isna(q_num): 
            unique_ids_col.append(None)
            pdf_text_col.append(None)
            text_avail_col.append("No")
            continue
            
        q_num = int(q_num)
        
        current_global_id += 1
        unique_ids_col.append(current_global_id)
        
        raw_text = extracted_text_map.get(q_num, "")
        cleaned_text = re.sub(r'\b\S*_\S*\b', '', raw_text)
        cleaned_text = " ".join(cleaned_text.split())
        
        if len(cleaned_text) < 30:
            pdf_text_col.append("")
            text_avail_col.append("No")
        else:
            pdf_text_col.append(cleaned_text)
            text_avail_col.append("Yes")

    combined_df['unique_id'] = unique_ids_col
    combined_df['pdf_Text'] = pdf_text_col
    combined_df['PDF_Text_Available'] = text_avail_col
    combined_df['QC_Status'] = "Pass"
    
    combined_df.fillna("Unknown", inplace=True)
    combined_df = combined_df[combined_df['unique_id'].notna()]

    # --- INCREMENTAL SAVE (DB MASTER CSV & CONFIG) ---
    if not combined_df.empty:
        try:
            # 1. Update Master DF in memory
            final_master_df = pd.concat([final_master_df, combined_df], ignore_index=True)
            
            # 2. Write to CSV (Instead of Excel)
            final_master_df.to_csv(MASTER_CSV_PATH, index=False)
            
            # 3. Update Config Counter
            config['last_unique_id'] = current_global_id
            with open(CONFIG_PATH, 'w') as f:
                json.dump(config, f, indent=4)
                
            print(f"   💾 SAVED: Added {len(combined_df)} questions to DB Master.csv. (Current ID: {current_global_id})")
            
        except Exception as e:
            print(f"   ❌ FATAL SAVE ERROR: {e}")

print("\n--- Finalizing ---")
print("✅ All folders processed and saved.")