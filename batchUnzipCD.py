import pandas as pd
import zipfile
import os
import json
import warnings
from tqdm import tqdm

# Suppress openpyxl warnings
warnings.filterwarnings("ignore", category=UserWarning) 

def batch_unzip():
    # --- 1. CONFIGURATION ---
    CONFIG_PATH = 'config.json'
    
    config = {
        "BASE_PATH": r"D:\Main\3. Work - Teaching\Projects\Question extractor",
        "METADATA_FILENAME": "DB Metadata.xlsx"
    }
    
    if os.path.exists(CONFIG_PATH):
        with open(CONFIG_PATH, 'r') as f:
            config.update(json.load(f))
            
    BASE_PATH = os.path.normpath(config['BASE_PATH'])
    RAW_DATA_PATH = os.path.join(BASE_PATH, 'raw data')
    METADATA_PATH = os.path.join(BASE_PATH, config.get("METADATA_FILENAME", "DB Metadata.xlsx"))

    print(f"🔧 CONFIGURATION:")
    print(f"   - Raw Data Dir : {RAW_DATA_PATH}")
    print(f"   - Metadata     : {METADATA_PATH}")

    # --- 2. LOAD METADATA ---
    if not os.path.exists(METADATA_PATH):
        print(f"❌ Metadata file not found: {METADATA_PATH}")
        return

    try:
        df = pd.read_excel(METADATA_PATH, sheet_name='CD_Metadata')
        df.columns = df.columns.str.strip()
        
        col_map = {
            'Zip_File': 'Zip_Prefix',
            'Zip_Filepath': 'Zip_Prefix', 
            'Unzip Folder name': 'Target_Name'
        }
        df = df.rename(columns=col_map)
        
        if 'Zip_Prefix' not in df.columns or 'Target_Name' not in df.columns:
            print(f"❌ Error: Sheet must contain 'Zip_File' and 'Unzip Folder name'")
            return
            
        df = df.dropna(subset=['Zip_Prefix', 'Target_Name'])
        
    except Exception as e:
        print(f"❌ Error reading Excel: {e}")
        return

    # --- 3. SCAN FILES ---
    try:
        all_files = [f for f in os.listdir(RAW_DATA_PATH) if f.lower().endswith('.zip')]
    except Exception as e:
        print(f"❌ Error accessing raw data folder: {e}")
        return

    print(f"\n📂 Metadata has {len(df)} entries. Scanning {len(all_files)} zip files on disk...")

    # --- 4. PROCESSING LOOP ---
    success_count = 0
    skipped_count = 0
    
    for index, row in tqdm(df.iterrows(), total=len(df), desc="Processing"):
        zip_prefix = str(row['Zip_Prefix']).strip()
        clean_name = str(row['Target_Name']).strip()
        
        # Define Target Path
        final_folder_name = f"CollegeDoors - {clean_name}"
        target_full_path = os.path.join(RAW_DATA_PATH, final_folder_name)

        # --- SKIP LOGIC ---
        # If folder exists AND has files in it, skip.
        if os.path.exists(target_full_path) and len(os.listdir(target_full_path)) > 0:
            skipped_count += 1
            continue

        # Find matching zips
        matching_zips = [f for f in all_files if f.startswith(zip_prefix)]
        
        if not matching_zips:
            continue

        # Create Folder
        os.makedirs(target_full_path, exist_ok=True)

        # Extract
        for zip_filename in matching_zips:
            zip_full_path = os.path.join(RAW_DATA_PATH, zip_filename)
            try:
                with zipfile.ZipFile(zip_full_path, 'r') as zip_ref:
                    members = [m for m in zip_ref.namelist() if not m.startswith('__MACOSX')]
                    zip_ref.extractall(target_full_path, members=members)
            except Exception as e:
                print(f"\n   ❌ Error extracting {zip_filename}: {e}")
        
        success_count += 1

    print(f"\n✨ Task Complete.")
    print(f"   ✅ Extracted: {success_count}")
    print(f"   ⏩ Skipped:   {skipped_count} (Already done)")

if __name__ == "__main__":
    batch_unzip()