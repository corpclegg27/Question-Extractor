import pandas as pd
import easyocr
import os
import json
import warnings

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
    MASTER_PATH = os.path.join(BASE_PATH, 'DB Master.xlsx')
    OUTPUT_CSV = os.path.join(BASE_PATH, 'DB Master_OCR.csv')

    print(f"🔧 CONFIGURATION:")
    print(f"   - Database   : {MASTER_PATH}")
    print(f"   - Images     : {IMG_BASE_DIR}")
    print(f"   - Output CSV : {OUTPUT_CSV}")

    # --- 2. SMART LOAD & MERGE ---
    print(f"\n📂 Loading Master Database...")
    df = pd.read_excel(MASTER_PATH)
    
    if 'OCR_Text' not in df.columns: df['OCR_Text'] = ""
    if 'PDF_Text_Available' not in df.columns: df['PDF_Text_Available'] = "No"

    # Merge existing progress
    if os.path.exists(OUTPUT_CSV):
        print(f"   ↳ Merging progress from {os.path.basename(OUTPUT_CSV)}...")
        df_progress = pd.read_csv(OUTPUT_CSV)
        
        if 'unique_id' in df_progress.columns and 'OCR_Text' in df_progress.columns:
            done_rows = df_progress[df_progress['OCR_Text'].notna() & (df_progress['OCR_Text'].astype(str).str.strip() != "")]
            progress_map = dict(zip(done_rows['unique_id'], done_rows['OCR_Text']))
            
            df['OCR_Text'] = df['unique_id'].map(progress_map).fillna(df['OCR_Text'])
            print(f"   ✅ Merged {len(progress_map)} existing OCR entries.")

    # --- 3. FILTERING ---
    ocr_missing = df['OCR_Text'].isna() | (df['OCR_Text'].astype(str).str.strip() == "")
    pdf_text_missing = df['PDF_Text_Available'].fillna("No").astype(str).str.lower() != "yes"
    
    rows_to_process = df[ocr_missing & pdf_text_missing]

    if rows_to_process.empty:
        print("\n🎉 No pending items! Database is up to date.")
        return

    print(f"\n🎯 Found {len(rows_to_process)} questions needing OCR.")

    # --- 4. INITIALIZE ENGINE ---
    print("🚀 Initializing EasyOCR...")
    if not os.path.exists(MODEL_STORAGE):
        os.makedirs(MODEL_STORAGE, exist_ok=True)
    reader = easyocr.Reader(['en'], model_storage_directory=MODEL_STORAGE, gpu=True) 

    # --- 5. PROCESSING LOOP ---
    print("\n▶️ Starting Batch Processing...")
    processed_count = 0
    try:
        for index in rows_to_process.index:
            folder = str(df.at[index, 'Folder']).strip()
            
            # --- FIX: SMART Q-NUMBER SELECTION ---
            q_num = None
            
            # 1. Try 'Question No.' column first
            if 'Question No.' in df.columns:
                val = df.at[index, 'Question No.']
                if pd.notna(val) and str(val).strip() != "":
                    q_num = str(val).split('.')[0]
            
            # 2. Fallback to 'Q' column if the first one failed
            if not q_num and 'Q' in df.columns:
                val = df.at[index, 'Q']
                if pd.notna(val) and str(val).strip() != "":
                    q_num = str(val).split('.')[0]
            
            # 3. If still nothing, skip
            if not q_num:
                print(f"   ⚠️ Skipping Row {index}: No Question Number found.")
                continue

            img_filename = f"Q_{q_num}.png"
            img_path = os.path.join(IMG_BASE_DIR, folder, img_filename)
            rel_path = os.path.join(folder, img_filename)
            
            print(f"   Processing: {rel_path} ... ", end="", flush=True)
            
            if os.path.exists(img_path):
                try:
                    result = reader.readtext(img_path, detail=0)
                    text_content = " ".join(result)
                    
                    df.at[index, 'OCR_Text'] = text_content
                    
                    # SAVE
                    df.to_csv(OUTPUT_CSV, index=False)
                    print("✅ Saved.")
                    processed_count += 1
                    
                except Exception as e:
                    print(f"❌ Error: {e}")
            else:
                print(f"⚠️ Skipped (File not found)")

    except KeyboardInterrupt:
        print("\n\n🛑 Script stopped by user. Progress saved.")

    print(f"\n✨ Session Complete. Processed {processed_count} images.")

if __name__ == "__main__":
    update_ocr_to_csv()