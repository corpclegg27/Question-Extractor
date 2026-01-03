import pandas as pd
import easyocr
import os
import json
import warnings
import numpy as np
from tqdm import tqdm
from datetime import datetime

# Suppress specific warnings for cleaner output
warnings.filterwarnings("ignore", category=UserWarning)

def update_ocr_to_csv():
    # --- 1. CONFIGURATION ---
    CONFIG_PATH = 'config.json'
    config = {
        "BASE_PATH": "D:/Main/3. Work - Teaching/Projects/Question extractor",
        "MODEL_DIR": "models"
    }

    if os.path.exists(CONFIG_PATH):
        with open(CONFIG_PATH, 'r') as f:
            loaded = json.load(f)
            config.update(loaded)

    # Normalize Paths
    BASE_PATH = os.path.normpath(config['BASE_PATH'])
    
    if os.path.isabs(config['MODEL_DIR']):
        MODEL_STORAGE = os.path.normpath(config['MODEL_DIR'])
    else:
        MODEL_STORAGE = os.path.normpath(os.path.join(BASE_PATH, config['MODEL_DIR']))

    IMG_BASE_DIR = os.path.join(BASE_PATH, 'Processed_Database')
    
    # SAFE IO SETUP
    MASTER_DB_PATH = os.path.join(BASE_PATH, 'DB Master.csv')       # READ ONLY
    OUTPUT_DB_PATH = os.path.join(BASE_PATH, 'DB Master_OCR.csv')   # READ/WRITE

    print(f"🔧 CONFIGURATION:")
    print(f"   - Master DB (Read) : {MASTER_DB_PATH}")
    print(f"   - Output DB (Write): {OUTPUT_DB_PATH}")

    # --- 2. LOAD DATABASE SAFELY ---
    print(f"\n📂 Loading Master Database...")
    if not os.path.exists(MASTER_DB_PATH):
        print(f"❌ Error: Master Database not found at {MASTER_DB_PATH}")
        return

    try:
        df_master = pd.read_csv(MASTER_DB_PATH)
        print(f"   ✅ Loaded {len(df_master)} rows from Master DB.")
    except Exception as e:
        print(f"❌ Error reading Master CSV: {e}")
        return

    # --- 3. MERGE EXISTING PROGRESS ---
    if os.path.exists(OUTPUT_DB_PATH):
        print(f"🔄 Found existing Output DB. Merging progress...")
        try:
            df_progress = pd.read_csv(OUTPUT_DB_PATH)
            
            if 'unique_id' in df_master.columns and 'unique_id' in df_progress.columns:
                df_progress.drop_duplicates(subset=['unique_id'], keep='last', inplace=True)
                
                df_master.set_index('unique_id', inplace=True, drop=False)
                df_progress.set_index('unique_id', inplace=True, drop=False)
                
                df_master.update(df_progress)
                
                df_master.reset_index(drop=True, inplace=True)
                print(f"   ✅ Merged progress. Current Row Count: {len(df_master)}")
            else:
                print("   ⚠️ 'unique_id' missing. Cannot safely merge. Starting from Master data.")
        except Exception as e:
            print(f"   ⚠️ Could not read Output DB: {e}")
    
    df = df_master

    # --- 4. DATA PREP & INDEX FIX ---
    # Critical: Reset index to ensure 0..n sequence
    df.reset_index(drop=True, inplace=True)

    if 'OCR_Text' not in df.columns: 
        df['OCR_Text'] = ""
    if 'last_updated' not in df.columns:
        df['last_updated'] = ""
        
    # Convert to string, replace 'nan' text with empty string for cleaner logic
    df['OCR_Text'] = df['OCR_Text'].astype(str).replace('nan', '')

    # --- 5. DEFINE "BAD OCR" LOGIC ---
    # A row needs processing if:
    # 1. It is empty
    # 2. It is just "0"
    # 3. It is shorter than 30 characters
    
    # Calculate text length series
    text_len = df['OCR_Text'].str.strip().str.len()
    
    # Create the mask for "Needs Work"
    mask_needs_work = (
        (df['OCR_Text'].str.strip() == "") | 
        (df['OCR_Text'].str.strip() == "0") | 
        (text_len < 30)
    )
    
    print(f"   📊 Initial check: {mask_needs_work.sum()} rows identified as having missing/bad OCR.")

    # --- 6. SMART COPY: PDF_TEXT -> OCR_TEXT ---
    print("🔄 Checking for PDF Text to fast-fill...")

    cols_map = {c.lower(): c for c in df.columns}
    col_pdf_text = cols_map.get('pdf_text')            
    col_pdf_flag = cols_map.get('pdf_text_available')  

    if col_pdf_text and col_pdf_flag:
        # Conditions for Smart Copy:
        # 1. Row needs work (as defined above)
        # 2. PDF_Text_Available == "Yes"
        # 3. PDF_Text actually has content
        
        pdf_available_mask = df[col_pdf_flag].astype(str).str.strip().str.lower() == "yes"
        pdf_content_exists = df[col_pdf_text].notna() & (df[col_pdf_text].astype(str).str.strip() != "")
        
        mask_smart_copy = mask_needs_work & pdf_available_mask & pdf_content_exists
        
        count_copied = mask_smart_copy.sum()

        if count_copied > 0:
            print(f"   ↳ ⚡ Fast-filled {count_copied} rows from '{col_pdf_text}'.")
            df.loc[mask_smart_copy, 'OCR_Text'] = df.loc[mask_smart_copy, col_pdf_text]
            current_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            df.loc[mask_smart_copy, 'last_updated'] = current_time
        else:
            print("   ↳ No rows qualified for Smart Copy.")
    else:
        print(f"   ⚠️ Could not find '{col_pdf_text}' or '{col_pdf_flag}' columns.")

    # --- 7. RE-CALCULATE PENDING LIST ---
    # Re-run the check to see what is STILL missing after the smart copy
    text_len = df['OCR_Text'].astype(str).str.strip().str.len()
    mask_still_needs_work = (
        (df['OCR_Text'].astype(str).str.strip() == "") | 
        (df['OCR_Text'].astype(str).str.strip() == "0") | 
        (text_len < 30)
    )
    
    pending_indices = df[mask_still_needs_work].index

    if len(pending_indices) == 0:
        print("\n🎉 No pending items! Database is up to date.")
        df.sort_values(by='last_updated', ascending=False, inplace=True)
        df.to_csv(OUTPUT_DB_PATH, index=False)
        print(f"✅ Saved clean DB to: {OUTPUT_DB_PATH}")
        return

    print(f"\n🎯 Found {len(pending_indices)} questions needing actual OCR (GPU).")

    # --- 8. INITIALIZE ENGINE ---
    print("🚀 Initializing EasyOCR...")
    if not os.path.exists(MODEL_STORAGE):
        os.makedirs(MODEL_STORAGE, exist_ok=True)
        
    reader = easyocr.Reader(['en'], model_storage_directory=MODEL_STORAGE, gpu=True) 

    # --- 9. PROCESSING LOOP ---
    print("\n▶️  Starting Batch Processing...")
    
    processed_count = 0
    save_frequency = 5
    
    try:
        with tqdm(total=len(pending_indices), unit="img") as pbar:
            
            for index in pending_indices:
                folder = str(df.at[index, 'Folder']).strip()
                
                # --- Get Question Number ---
                q_num = None
                if 'Question No.' in df.columns:
                    val = df.at[index, 'Question No.']
                    if pd.notna(val) and str(val).strip() != "":
                        q_num = str(val).split('.')[0]
                
                if not q_num and 'Q' in df.columns:
                    val = df.at[index, 'Q']
                    if pd.notna(val) and str(val).strip() != "":
                        q_num = str(val).split('.')[0]
                
                if not q_num:
                    pbar.write(f"⚠️  Skipping Row {index}: No Question Number found.")
                    pbar.update(1)
                    continue

                img_filename = f"Q_{q_num}.png"
                img_path = os.path.join(IMG_BASE_DIR, folder, img_filename)
                
                if os.path.exists(img_path):
                    try:
                        result = reader.readtext(img_path, detail=0)
                        text_content = " ".join(result)
                        
                        df.at[index, 'OCR_Text'] = text_content
                        df.at[index, 'last_updated'] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                        
                        processed_count += 1
                        
                        if processed_count % save_frequency == 0:
                            df_save = df.sort_values(by='last_updated', ascending=False)
                            df_save.to_csv(OUTPUT_DB_PATH, index=False)
                            
                    except Exception as e:
                        pbar.write(f"❌ Error on {img_filename}: {e}")
                else:
                    pass

                pbar.update(1)

    except KeyboardInterrupt:
        print("\n\n🛑 Script stopped by user.")
    
    # --- 10. FINAL SORT & SAVE ---
    print("💾 Performing final sort and save...")
    try:
        df.sort_values(by='last_updated', ascending=False, inplace=True)
        df.to_csv(OUTPUT_DB_PATH, index=False)
        print(f"✅ Saved successfully to: {OUTPUT_DB_PATH}")
        print(f"📊 Total processed: {processed_count}")
    except PermissionError:
        print(f"❌ ERROR: Could not save to {OUTPUT_DB_PATH}. Is the file open?")

if __name__ == "__main__":
    update_ocr_to_csv()