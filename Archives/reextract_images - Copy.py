import os
import glob
import pandas as pd
import pdfplumber
from pdf2image import convert_from_path
from PIL import Image, ImageChops
from tqdm.notebook import tqdm
import re

# --- CONFIGURATION ---
BASE_PATH = 'D:/Main/3. Work - Teaching/Projects/Question extractor/'
OUTPUT_BASE = os.path.join(BASE_PATH, 'Processed_Database')

# Create output directory
os.makedirs(OUTPUT_BASE, exist_ok=True)

# --- SMART PATH FINDER ---
# This block automatically finds your 'raw data' folder, no matter how it's capitalized
detected_raw_path = None
if os.path.exists(BASE_PATH):
    for item in os.listdir(BASE_PATH):
        # Look for "raw data" (case insensitive)
        if "raw data" in item.lower():
            detected_raw_path = os.path.join(BASE_PATH, item)
            print(f"✅ Auto-detected input folder: '{item}'")
            break

if not detected_raw_path:
    print(f"❌ ERROR: Could not find 'Raw data' folder in {BASE_PATH}")
    print("Please run the Diagnostic script above to check your folder names.")
    # Stop execution if path is wrong
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

# --- MAIN EXECUTION ---
subfolders = [f.path for f in os.scandir(RAW_DATA_PATH) if f.is_dir()]
print(f"✅ Found {len(subfolders)} test folders in '{RAW_DATA_PATH}'")

for folder in tqdm(subfolders, desc="Processing Tests"):
    test_name = os.path.basename(folder)
    q_papers = glob.glob(os.path.join(folder, "*question_paper.pdf"))
    sol_pdfs = glob.glob(os.path.join(folder, "*solution_pdf.pdf"))
    excel_keys = glob.glob(os.path.join(folder, "*excel_answer_key.xlsx")) + glob.glob(os.path.join(folder, "*excel_answer_key.csv"))

    if not (q_papers and sol_pdfs and excel_keys):
        print(f"Skipping {test_name}: Missing files")
        continue

    # Metadata
    key_path = excel_keys[0]
    df = pd.read_csv(key_path) if key_path.endswith('.csv') else pd.read_excel(key_path)
    total_questions = df['Question No.'].max() if 'Question No.' in df.columns else len(df)
    
    # Setup Output
    test_output_dir = os.path.join(OUTPUT_BASE, test_name)
    os.makedirs(test_output_dir, exist_ok=True)
    df.to_json(os.path.join(test_output_dir, 'answer_key.json'), orient='records')

    # Process
    print(f"Processing {test_name} ({total_questions} Qs)...")
    crop_and_save(q_papers[0], find_anchors_robust(q_papers[0], max_val=total_questions), test_output_dir, "Q", is_two_column=True)
    crop_and_save(sol_pdfs[0], find_anchors_robust(sol_pdfs[0], max_val=total_questions, is_solution=True), test_output_dir, "Sol", is_two_column=True)

print(f"\n🎉 DONE! Check folder: {OUTPUT_BASE}")


# --- NEW CODE: GENERATE DB MASTER.XLSX ---
print("\n--- Generating DB Master.xlsx ---")

master_df_list = []

# We re-iterate through the subfolders to link Raw Metadata with Processed Outputs
for folder in tqdm(subfolders, desc="Compiling Master DB"):
    test_name = os.path.basename(folder)
    
    # Define paths
    raw_meta_path = os.path.join(folder, 'metadata.csv')
    processed_dir = os.path.join(OUTPUT_BASE, test_name)
    json_key_path = os.path.join(processed_dir, 'answer_key.json')

    # Check if necessary files exist
    if not os.path.exists(raw_meta_path):
        print(f"⚠️ Metadata missing for {test_name}, skipping DB entry.")
        continue
    if not os.path.exists(json_key_path):
        print(f"⚠️ JSON Key missing for {test_name}, skipping DB entry.")
        continue

    # 1. Read Data
    try:
        meta_df = pd.read_csv(raw_meta_path)
        key_df = pd.read_json(json_key_path)
    except Exception as e:
        print(f"❌ Error reading files for {test_name}: {e}")
        continue

    # 2. Add Folder Column
    meta_df['Folder'] = test_name

    # 3. Merge Metadata with Answer Key
    # If both have 'Question No.', we merge on it. Otherwise, we assume they are in the same row order.
    if 'Question No.' in meta_df.columns and 'Question No.' in key_df.columns:
        combined_df = pd.merge(meta_df, key_df, on='Question No.', how='left', suffixes=('', '_key'))
    else:
        # Fallback: Merge by index (side-by-side)
        combined_df = pd.concat([meta_df.reset_index(drop=True), key_df.reset_index(drop=True)], axis=1)

    # 4. Add Image Dimensions (Height/Width)
    q_widths, q_heights = [], []
    sol_widths, sol_heights = [], []

    for idx, row in combined_df.iterrows():
        # Determine Question Number
        q_num = row.get('Question No.')
        # If Question No is missing or NaN, assume sequential (idx + 1)
        if pd.isna(q_num):
            q_num = idx + 1
        
        q_num = int(q_num) # Ensure integer for filename
        
        q_img_path = os.path.join(processed_dir, f"Q_{q_num}.png")
        sol_img_path = os.path.join(processed_dir, f"Sol_{q_num}.png")

        # Get Question Image Dims
        if os.path.exists(q_img_path):
            with Image.open(q_img_path) as img:
                q_widths.append(img.width)
                q_heights.append(img.height)
        else:
            q_widths.append(None)
            q_heights.append(None)

        # Get Solution Image Dims
        if os.path.exists(sol_img_path):
            with Image.open(sol_img_path) as img:
                sol_widths.append(img.width)
                sol_heights.append(img.height)
        else:
            sol_widths.append(None)
            sol_heights.append(None)

    # Assign new columns
    combined_df['q_width'] = q_widths
    combined_df['q_height'] = q_heights
    combined_df['sol_width'] = sol_widths
    combined_df['sol_height'] = sol_heights
    combined_df['QC_Status'] = "Pass"

    # Add to master list
    master_df_list.append(combined_df)

# 5. Concatenate and Save

if master_df_list:
    final_master_df = pd.concat(master_df_list, ignore_index=True)
    output_excel_path = os.path.join(BASE_PATH, 'DB Master.xlsx')

    
    # Save to Excel
    try:
        final_master_df.to_excel(output_excel_path, index=False)
        print(f"✅ DB Master.xlsx successfully created at: {output_excel_path}")
    except Exception as e:
        print(f"❌ Error saving Excel file. Is it open? Error: {e}")
else:
    print("⚠️ No data processed for DB Master.")