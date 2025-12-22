import os
import glob
import pandas as pd
import json

def count_questions():
    # --- 1. CONFIGURATION ---
    CONFIG_PATH = 'config.json'
    DEFAULT_BASE_PATH = 'D:/Main/3. Work - Teaching/Projects/Question extractor'
    
    # Load Config or use default
    config = {}
    if os.path.exists(CONFIG_PATH):
        with open(CONFIG_PATH, 'r') as f:
            config = json.load(f)
            
    BASE_PATH = config.get('BASE_PATH', DEFAULT_BASE_PATH)
    RAW_DATA_PATH = os.path.join(BASE_PATH, 'raw data')
    OUTPUT_CSV = os.path.join(BASE_PATH, 'CD_QuestionCount.csv')

    print(f"📂 Scanning: {RAW_DATA_PATH}")

    if not os.path.exists(RAW_DATA_PATH):
        print("❌ Error: Raw data folder not found.")
        return

    # --- 2. SCANNING LOOP ---
    results = []
    
    # Get all subfolders
    subfolders = [f.path for f in os.scandir(RAW_DATA_PATH) if f.is_dir()]
    
    print(f"🔍 Found {len(subfolders)} total folders. Filtering for 'CollegeDoors'...")

    for folder_path in subfolders:
        folder_name = os.path.basename(folder_path).strip()
        
        # Filter logic
        if not folder_name.startswith("CollegeDoors"):
            continue

        # Look for the answer key
        excel_files = glob.glob(os.path.join(folder_path, "*answer_key.xlsx"))
        
        # Fallback for CSV if XLSX isn't found (just in case)
        if not excel_files:
            excel_files = glob.glob(os.path.join(folder_path, "*answer_key.csv"))

        count = 0
        file_used = "None"
        status = "Missing Key"

        if excel_files:
            file_used = os.path.basename(excel_files[0])
            try:
                # Read the file
                if file_used.endswith('.csv'):
                    df = pd.read_csv(excel_files[0])
                else:
                    df = pd.read_excel(excel_files[0])
                
                # Count logic: prefer 'Question No.' column, otherwise just row count
                if 'Question No.' in df.columns:
                    count = df['Question No.'].nunique()
                else:
                    count = len(df)
                
                status = "Success"
            except Exception as e:
                status = f"Error: {str(e)}"
        
        results.append({
            "Folder": folder_name,
            "Question_Count": count,
            "File_Used": file_used,
            "Status": status
        })
        
        print(f"   👉 {folder_name}: {count}")

    # --- 3. SAVE RESULTS ---
    if results:
        df_results = pd.DataFrame(results)
        df_results.to_csv(OUTPUT_CSV, index=False)
        print(f"\n✅ Done. Summary saved to: {OUTPUT_CSV}")
        print(f"   Total Questions Found: {df_results['Question_Count'].sum()}")
    else:
        print("\n⚠️ No matching folders found.")

if __name__ == "__main__":
    count_questions()