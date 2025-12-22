import pandas as pd
import os
import json
from tqdm import tqdm

def merge_answer_keys():
    # --- 1. CONFIGURATION ---
    CONFIG_PATH = 'config.json'
    DEFAULT_BASE_PATH = 'D:/Main/3. Work - Teaching/Projects/Question extractor'
    
    # Load Config
    config = {}
    if os.path.exists(CONFIG_PATH):
        with open(CONFIG_PATH, 'r') as f:
            config = json.load(f)
            
    BASE_PATH = config.get('BASE_PATH', DEFAULT_BASE_PATH)
    RAW_DATA_PATH = os.path.join(BASE_PATH, 'raw data')
    SUMMARY_CSV = os.path.join(BASE_PATH, 'CD_QuestionCount.csv')
    OUTPUT_CSV = os.path.join(BASE_PATH, 'CQ_Questions_Master.csv')

    print(f"🔧 CONFIGURATION:")
    print(f"   - Reading Map  : {SUMMARY_CSV}")
    print(f"   - Raw Data Dir : {RAW_DATA_PATH}")
    print(f"   - Output File  : {OUTPUT_CSV}")

    # --- 2. LOAD SUMMARY ---
    if not os.path.exists(SUMMARY_CSV):
        print(f"❌ Error: {SUMMARY_CSV} not found. Please run count_questions.py first.")
        return

    summary_df = pd.read_csv(SUMMARY_CSV)
    
    # Check for 'Chapter' column
    if 'Chapter' not in summary_df.columns:
        print("⚠️ Warning: 'Chapter' column not found in CD_QuestionCount.csv. Columns will be empty.")
        summary_df['Chapter'] = "Unknown"

    print(f"\n📂 Found {len(summary_df)} folders to process.")

    # --- 3. MERGE LOOP ---
    all_data_frames = []
    success_count = 0
    missing_count = 0

    for index, row in tqdm(summary_df.iterrows(), total=len(summary_df), desc="Merging"):
        folder_name = str(row['Folder']).strip()
        filename = str(row['File_Used']).strip()
        chapter_name = str(row['Chapter']).strip()
        
        # Skip if no valid file was found previously
        if filename.lower() in ['none', 'nan', '']:
            continue

        file_path = os.path.join(RAW_DATA_PATH, folder_name, filename)

        if os.path.exists(file_path):
            try:
                # Read the individual answer key
                if filename.lower().endswith('.csv'):
                    df = pd.read_csv(file_path)
                else:
                    df = pd.read_excel(file_path)
                
                # --- ENRICHMENT ---
                # Add the Chapter info from your summary CSV
                df['Chapter_From_Summary'] = chapter_name 
                # Add Folder name for traceability
                df['Source_Folder'] = folder_name
                
                all_data_frames.append(df)
                success_count += 1
                
            except Exception as e:
                print(f"\n❌ Error reading {filename}: {e}")
        else:
            # print(f"\n⚠️ File not found: {file_path}")
            missing_count += 1

    # --- 4. CONCATENATE & SAVE ---
    if all_data_frames:
        print(f"\n🔄 Concatenating {len(all_data_frames)} files...")
        master_df = pd.concat(all_data_frames, ignore_index=True)
        
        # Move key columns to the front for better visibility
        cols = list(master_df.columns)
        priorities = ['Source_Folder', 'Chapter_From_Summary', 'Question No.', 'Q']
        for p in reversed(priorities):
            if p in cols:
                cols.insert(0, cols.pop(cols.index(p)))
        master_df = master_df[cols]

        master_df.to_csv(OUTPUT_CSV, index=False)
        print(f"\n✅ Success! Master CSV created at: {OUTPUT_CSV}")
        print(f"   Total Rows: {len(master_df)}")
        print(f"   Files Merged: {success_count}")
        if missing_count > 0:
            print(f"   Missing Files: {missing_count}")
    else:
        print("\n⚠️ No data collected. Check your paths and summary CSV.")

if __name__ == "__main__":
    merge_answer_keys()