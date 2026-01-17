import pandas as pd
import easyocr
import os
import json
import warnings
import numpy as np
from tqdm import tqdm
from datetime import datetime

# Suppress warnings
warnings.filterwarnings("ignore", category=UserWarning)

def update_ocr_incremental():
    # --- 1. CONFIGURATION ---
    CONFIG_PATH = 'config.json'
    config = {
        "BASE_PATH": "D:/Main/3. Work - Teaching/Projects/Question extractor",
        "MODEL_DIR": "models"
    }

    if os.path.exists(CONFIG_PATH):
        with open(CONFIG_PATH, 'r') as f:
            config.update(json.load(f))

    BASE_PATH = os.path.normpath(config['BASE_PATH'])
    
    if os.path.isabs(config['MODEL_DIR']):
        MODEL_STORAGE = os.path.normpath(config['MODEL_DIR'])
    else:
        MODEL_STORAGE = os.path.normpath(os.path.join(BASE_PATH, config['MODEL_DIR']))

    IMG_BASE_DIR = os.path.join(BASE_PATH, 'Processed_Database')
    
    # FILES
    MASTER_DB_PATH = os.path.join(BASE_PATH, 'OCR - Questions for processing.csv')       
    OUTPUT_DB_PATH = os.path.join(BASE_PATH, 'OCR - Processed.csv')   

    print(f"🔧 CONFIGURATION:")
    print(f"   - Master DB (Read) : {MASTER_DB_PATH}")
    print(f"   - Output DB (Append): {OUTPUT_DB_PATH}")

    # --- 2. LOAD MASTER ---
    if not os.path.exists(MASTER_DB_PATH):
        print(f"❌ Error: Master DB not found at {MASTER_DB_PATH}")
        return

    df_master = pd.read_csv(MASTER_DB_PATH)
    print(f"\n📂 Loaded Master: {len(df_master)} rows.")

    if 'unique_id' not in df_master.columns:
        print("❌ CRITICAL: 'unique_id' missing in Master.")
        return
        
    # Standardize ID to string to avoid mismatch
    df_master['unique_id'] = df_master['unique_id'].astype(str).str.strip()

    # --- 3. DETERMINE WHAT IS ALREADY DONE ---
    processed_ids = set()
    
    if os.path.exists(OUTPUT_DB_PATH):
        try:
            # We only read the IDs from the output file to know what to skip
            df_existing = pd.read_csv(OUTPUT_DB_PATH)
            
            # Check for valid OCR text (length > 20)
            if 'OCR_Text' in df_existing.columns and 'unique_id' in df_existing.columns:
                df_existing['OCR_Text'] = df_existing['OCR_Text'].astype(str).replace('nan', '')
                valid_rows = df_existing[df_existing['OCR_Text'].str.len() > 20]
                processed_ids = set(valid_rows['unique_id'].astype(str).str.strip())
                
            print(f"🔄 Found Output DB. Skipping {len(processed_ids)} already completed rows.")
        except Exception as e:
            print(f"⚠️  Could not read existing Output DB ({e}). Starting fresh.")

    # --- 4. FILTER PENDING ---
    # We only keep rows from Master that are NOT in processed_ids
    df_pending = df_master[~df_master['unique_id'].isin(processed_ids)].copy()
    
    # Initialize necessary columns for the pending rows
    if 'OCR_Text' not in df_pending.columns: df_pending['OCR_Text'] = ""
    if 'last_updated' not in df_pending.columns: df_pending['last_updated'] = ""

    total_pending = len(df_pending)
    print(f"   📊 Pending Work: {total_pending} rows.")

    if total_pending == 0:
        print("\n🎉 All done! Database is up to date.")
        return

    # --- 5. INITIALIZE ENGINE ---
    print("\n🚀 Initializing EasyOCR (GPU)...")
    if not os.path.exists(MODEL_STORAGE): os.makedirs(MODEL_STORAGE, exist_ok=True)
    reader = easyocr.Reader(['en'], model_storage_directory=MODEL_STORAGE, gpu=True) 

    # --- 6. ROW-BY-ROW PROCESSING ---
    print(f"\n▶️  Processing {total_pending} images...")
    
    # Check if we need to write the header (only if file doesn't exist)
    write_header = not os.path.exists(OUTPUT_DB_PATH)
    
    try:
        with tqdm(total=total_pending, unit="img") as pbar:
            for idx, row in df_pending.iterrows():
                folder = str(row.get('Folder', '')).strip()
                
                # Q Number Logic
                val = row.get('Question No.') if 'Question No.' in df_pending.columns else row.get('Q')
                q_num = str(val).split('.')[0] if pd.notna(val) and str(val).strip() != "" else None
                
                if not q_num:
                    pbar.update(1)
                    continue

                # --- STEP A: TRY SMART COPY (PDF TEXT) ---
                # Check if PDF text is available and valid
                pdf_avail = str(row.get('PDF_Text_Available', '')).lower() == 'yes'
                pdf_text = str(row.get('pdf_Text', '')).strip()
                
                final_text = ""
                source = ""
                
                if pdf_avail and len(pdf_text) > 20:
                    final_text = pdf_text
                    source = "PDF_COPY"
                else:
                    # --- STEP B: RUN OCR ---
                    img_filename = f"Q_{q_num}.png"
                    img_path = os.path.join(IMG_BASE_DIR, folder, img_filename)
                    
                    if os.path.exists(img_path):
                        try:
                            result = reader.readtext(img_path, detail=0)
                            final_text = " ".join(result)
                            source = "OCR_GPU"
                        except Exception as e:
                            pbar.write(f"❌ Error {img_filename}: {e}")
                    else:
                        # Skip if file missing
                        pbar.update(1)
                        continue

                # --- STEP C: APPEND TO FILE ---
                # Only write if we actually got text (length > 20)
                if len(final_text) > 20:
                    current_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                    
                    # Update the specific fields in the single-row dataframe
                    df_pending.at[idx, 'OCR_Text'] = final_text
                    df_pending.at[idx, 'last_updated'] = current_time
                    
                    # Extract just this row as a DataFrame
                    single_row = df_pending.loc[[idx]]
                    
                    # Append to CSV
                    # mode='a' appends. header=False prevents writing headers repeatedly.
                    single_row.to_csv(OUTPUT_DB_PATH, mode='a', header=write_header, index=False)
                    
                    # Ensure header is only written once (for the very first row of a fresh file)
                    write_header = False
                
                pbar.update(1)

    except KeyboardInterrupt:
        print("\n🛑 Stopped by user.")
    
    print("\n✅ Script finished. Check DB Master_OCR.csv for results.")

if __name__ == "__main__":
    update_ocr_incremental()
    # --- AUTO SHUTDOWN CODE ---
    print("💤 Script finished. Shutting down PC in 60 seconds...")
    # /s = shutdown, /t 60 = timer of 60 seconds (gives you a chance to cancel)
    os.system("shutdown /s /t 60")