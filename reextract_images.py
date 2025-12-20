import os
import glob
import pandas as pd
import pdfplumber
from pdf2image import convert_from_path
from PIL import Image, ImageChops
from tqdm.notebook import tqdm
import re
import time

# --- CONFIGURATION ---
BASE_PATH = 'D:/Main/3. Work - Teaching/Projects/Question extractor/'
OUTPUT_BASE = os.path.join(BASE_PATH, 'Processed_Database')
MASTER_DB_PATH = os.path.join(BASE_PATH, 'DB Master.xlsx')

# Create output directory
os.makedirs(OUTPUT_BASE, exist_ok=True)

# --- SMART PATH FINDER ---
detected_raw_path = None
if os.path.exists(BASE_PATH):
    for item in os.listdir(BASE_PATH):
        if "raw data" in item.lower():
            detected_raw_path = os.path.join(BASE_PATH, item)
            print(f"✅ Auto-detected input folder: '{item}'")
            break

if not detected_raw_path:
    print(f"❌ ERROR: Could not find 'Raw data' folder in {BASE_PATH}")
    raise FileNotFoundError("Raw data folder missing")

RAW_DATA_PATH = detected_raw_path


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
                found_q_num = None
                
                match_joined = re.match(r'^(?:Q|Sol|Solution)?\.?(\d+)\.?$', text, re.IGNORECASE)
                if match_joined:
                    found_q_num = int(match_joined.group(1))
                elif text.lower() in ["q", "q.", "sol", "sol.", "solution", "solution:"] and i + 1 < len(words):
                    next_word = words[i+1]
                    if next_word['text'].isdigit():
                        found_q_num = int(next_word['text'])
                        i += 1 
                        
                if found_q_num:
                    if max_val and found_q_num > max_val: found_q_num = None
                    if found_q_num:
                        col = 0 if curr_word['x0'] < midpoint else 1
                        anchors.append({'q_num': found_q_num, 'page_idx': page_idx, 'top': curr_word['top'], 'col': col})
                i += 1

    unique_anchors = {}
    for a in anchors:
        if a['q_num'] not in unique_anchors: unique_anchors[a['q_num']] = a
    return sorted(unique_anchors.values(), key=lambda x: x['q_num'])

def crop_and_save(pdf_path, anchors, output_folder, file_prefix, is_two_column=True):
    try: pdf_images = convert_from_path(pdf_path, dpi=300)
    except: return

    if not pdf_images: return
    page_width, _ = pdf_images[0].size
    scale = 300 / 72 
    midpoint_px = (page_width / 2) 
    VERTICAL_PADDING = 15 
    TOP_MARGIN = 50 * scale 
    BOTTOM_MARGIN = pdf_images[0].height - (50 * scale)

    for i, start in enumerate(anchors):
        q_num = start['q_num']
        if i + 1 < len(anchors): end = anchors[i+1]
        else: end = {'page_idx': start['page_idx'], 'top': BOTTOM_MARGIN/scale, 'col': start['col']} 

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
                    bottom = min(end_top_px, BOTTOM_MARGIN)
                    if bottom <= start_top_px: bottom = start_top_px + 100 
                    images_to_stitch.append(pdf_images[start['page_idx']].crop((start_left, start_top_px, start_right, bottom)))
                else:
                    images_to_stitch.append(pdf_images[start['page_idx']].crop((start_left, start_top_px, start_right, BOTTOM_MARGIN)))
                    images_to_stitch.append(pdf_images[start['page_idx']].crop((end_left, TOP_MARGIN, end_right, end_top_px)))
            else:
                images_to_stitch.append(pdf_images[start['page_idx']].crop((start_left, start_top_px, start_right, BOTTOM_MARGIN)))
                for mid_idx in range(start['page_idx'] + 1, end['page_idx']):
                    images_to_stitch.append(pdf_images[mid_idx].crop((start_left, TOP_MARGIN, start_right, BOTTOM_MARGIN)))
                if end_top_px > TOP_MARGIN:
                    images_to_stitch.append(pdf_images[end['page_idx']].crop((end_left, TOP_MARGIN, end_right, end_top_px)))

            if not images_to_stitch: continue
            
            total_height = sum(img.height for img in images_to_stitch)
            max_width = max(img.width for img in images_to_stitch)
            final_img = Image.new('RGB', (max_width, total_height), (255, 255, 255))
            y_offset = 0
            for img in images_to_stitch:
                final_img.paste(img, (0, y_offset))
                y_offset += img.height
            
            final_img = trim_whitespace(final_img)
            final_img.save(f"{output_folder}/{file_prefix}_{q_num}.png")
        except: pass

# --- INITIALIZE DATABASE ---
print("\n--- Initializing Database ---")
processed_folders = set()
final_master_df = pd.DataFrame()

if os.path.exists(MASTER_DB_PATH):
    try:
        final_master_df = pd.read_excel(MASTER_DB_PATH)
        if 'Folder' in final_master_df.columns:
            processed_folders = set(final_master_df['Folder'].unique())
        print(f"✅ Loaded existing DB. Found {len(processed_folders)} processed folders.")
    except Exception as e:
        print(f"⚠️ Could not read existing DB: {e}. Starting fresh.")
else:
    print("ℹ️ No existing DB found. Creating new.")


# --- IDENTIFY NEW FOLDERS ---
all_subfolders = [f.path for f in os.scandir(RAW_DATA_PATH) if f.is_dir()]
new_subfolders = []

for folder_path in all_subfolders:
    folder_name = os.path.basename(folder_path)
    if folder_name not in processed_folders:
        new_subfolders.append(folder_path)

print(f"📂 Total Folders: {len(all_subfolders)}")
print(f"⏭️  Skipping: {len(processed_folders)}")
print(f"🆕 To Process: {len(new_subfolders)}")

if not new_subfolders:
    print("\n🎉 Nothing new to process! Exiting.")
    exit()

# --- PROCESSING LOOP ---
start_time = time.time()
new_questions_count = 0
new_data_list = []

for folder in tqdm(new_subfolders, desc="Processing New Folders"):
    test_name = os.path.basename(folder)
    
    # 1. FILE CHECKS
    q_papers = glob.glob(os.path.join(folder, "*question_paper.pdf"))
    sol_pdfs = glob.glob(os.path.join(folder, "*solution_pdf.pdf"))
    excel_keys = glob.glob(os.path.join(folder, "*excel_answer_key.xlsx")) + glob.glob(os.path.join(folder, "*excel_answer_key.csv"))
    raw_meta_path = os.path.join(folder, 'metadata.csv')

    if not (q_papers and sol_pdfs and excel_keys and os.path.exists(raw_meta_path)):
        print(f"⚠️ Skipping {test_name}: Missing required files (PDFs/Keys/Metadata)")
        continue

    # 2. READ KEY & METADATA
    try:
        key_path = excel_keys[0]
        key_df = pd.read_csv(key_path) if key_path.endswith('.csv') else pd.read_excel(key_path)
        meta_df = pd.read_csv(raw_meta_path)
        total_questions = key_df['Question No.'].max() if 'Question No.' in key_df.columns else len(key_df)
    except Exception as e:
        print(f"❌ Error reading data for {test_name}: {e}")
        continue
    
    # 3. SETUP OUTPUT
    test_output_dir = os.path.join(OUTPUT_BASE, test_name)
    os.makedirs(test_output_dir, exist_ok=True)
    key_df.to_json(os.path.join(test_output_dir, 'answer_key.json'), orient='records')

    # 4. IMAGE EXTRACTION (CROP)
    # print(f"Processing images for {test_name}...")
    crop_and_save(q_papers[0], find_anchors_robust(q_papers[0], max_val=total_questions), test_output_dir, "Q", is_two_column=True)
    crop_and_save(sol_pdfs[0], find_anchors_robust(sol_pdfs[0], max_val=total_questions, is_solution=True), test_output_dir, "Sol", is_two_column=True)

    # 5. GENERATE DATAFRAME ROW DATA
    meta_df['Folder'] = test_name
    
    # Merge Metadata + Key
    if 'Question No.' in meta_df.columns and 'Question No.' in key_df.columns:
        combined_df = pd.merge(meta_df, key_df, on='Question No.', how='left', suffixes=('', '_key'))
    else:
        combined_df = pd.concat([meta_df.reset_index(drop=True), key_df.reset_index(drop=True)], axis=1)

    # Add Image Dimensions
    q_widths, q_heights, sol_widths, sol_heights = [], [], [], []

    for idx, row in combined_df.iterrows():
        q_num = row.get('Question No.')
        if pd.isna(q_num): q_num = idx + 1
        q_num = int(q_num)

        q_img_path = os.path.join(test_output_dir, f"Q_{q_num}.png")
        sol_img_path = os.path.join(test_output_dir, f"Sol_{q_num}.png")

        # Measure Q
        if os.path.exists(q_img_path):
            with Image.open(q_img_path) as img:
                q_widths.append(img.width)
                q_heights.append(img.height)
        else:
            q_widths.append(None); q_heights.append(None)

        # Measure Sol
        if os.path.exists(sol_img_path):
            with Image.open(sol_img_path) as img:
                sol_widths.append(img.width)
                sol_heights.append(img.height)
        else:
            sol_widths.append(None); sol_heights.append(None)

    combined_df['q_width'] = q_widths
    combined_df['q_height'] = q_heights
    combined_df['sol_width'] = sol_widths
    combined_df['sol_height'] = sol_heights
    combined_df['QC_Status'] = "Pass"

    # Append to temporary list
    new_data_list.append(combined_df)
    new_questions_count += len(combined_df)


# --- FINAL UPDATE & STATS ---
end_time = time.time()
duration = end_time - start_time

print("\n--- Finalizing Updates ---")

if new_data_list:
    new_entries_df = pd.concat(new_data_list, ignore_index=True)
    
    # Update Master DF
    final_master_df = pd.concat([final_master_df, new_entries_df], ignore_index=True)
    
    # Save to Excel
    try:
        final_master_df.to_excel(MASTER_DB_PATH, index=False)
        print(f"✅ DB Master.xlsx updated successfully!")
    except Exception as e:
        print(f"❌ Error saving Excel file. Please close it if open. Error: {e}")
else:
    print("⚠️ No valid new data found to append.")

# --- STATISTICS REPORT ---
total_qs_in_db = len(final_master_df)
avg_time = duration / new_questions_count if new_questions_count > 0 else 0

print("\n" + "="*30)
print("       PROCESS STATISTICS       ")
print("="*30)
print(f"1. New Questions Added  : {new_questions_count}")
print(f"2. Time Taken           : {duration:.2f} s")
print(f"3. Avg Time per Q       : {avg_time:.2f} s")
print(f"4. Total Questions in DB: {total_qs_in_db}")
print("="*30)