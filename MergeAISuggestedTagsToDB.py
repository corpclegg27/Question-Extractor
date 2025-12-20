import pandas as pd
import os
import shutil
from datetime import datetime

def update_single_source_of_truth():
    # 1. Configuration
    master_path = "DB Master.xlsx"
    suggestions_path = "Suggested_Tags.csv"
    
    # Define what counts as an "Empty" value in your Master DB
    empty_markers = ["", "nan", "NaN", "unknown", "Unknown", "None", "none", "0", 0]

    # 2. Safety First: Create a Backup
    if os.path.exists(master_path):
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup_path = f"DB Master_BACKUP_{timestamp}.xlsx"
        shutil.copy(master_path, backup_path)
        print(f"[SAFETY] Backup created: {backup_path}")
    else:
        print(f"[ERROR] {master_path} not found!")
        return

    # 3. Load Databases
    print("Loading datasets...")
    df_master = pd.read_excel(master_path, engine='openpyxl')
    
    if not os.path.exists(suggestions_path):
        print(f"[ERROR] {suggestions_path} not found. Nothing to merge.")
        return
    
    # Load ALL suggestions (We do not filter out 'No' here)
    df_ai = pd.read_csv(suggestions_path)
    print(f"[INFO] Loaded {len(df_ai)} suggestions from CSV.")

    # Normalize IDs for matching (remove spaces, ensure string)
    df_master['unique_id'] = df_master['unique_id'].astype(str).str.strip()
    df_ai['unique_id'] = df_ai['unique_id'].astype(str).str.strip()
    
    # Initialize Audit Columns in Master if missing (to prevent KeyError)
    if 'Labelled by AI' not in df_master.columns:
        df_master['Labelled by AI'] = ""
    # We DO NOT create 'AI_Tag_Accepted' if it's missing, we just check if it exists below.

    # Create a quick lookup for Master indices using unique_id
    master_lookup = df_master.reset_index().set_index('unique_id')['index'].to_dict()

    # 4. Processing Loop
    print(f"Merging AI data into Single Source of Truth...")
    
    updated_count = 0
    skipped_verified_count = 0
    skipped_no_match_count = 0
    
    # Columns to map: Source (CSV) -> Destination (Master)
    cols_to_map = {
        'Sug_Chapter': 'Chapter',
        'Sug_Topic': 'Topic',
        'Sug_Topic_L2': 'Topic_L2',
        'Sug_Difficulty': 'Difficulty_tag'
    }

    # Iterate through SUGGESTIONS
    for index, ai_row in df_ai.iterrows():
        uid = ai_row['unique_id']
        
        # 4a. Find this ID in Master
        if uid not in master_lookup:
            skipped_no_match_count += 1
            continue
            
        master_idx = master_lookup[uid]
        
        # 4b. CHECK EXISTING VERIFICATION
        # Only check AI_Tag_Accepted if the column actually exists in Master
        if 'AI_Tag_Accepted' in df_master.columns:
            val = str(df_master.at[master_idx, 'AI_Tag_Accepted']).strip().lower()
            if val == 'yes':
                skipped_verified_count += 1
                continue # SKIP: Already verified
            
        # 4c. Merge Data (Only if Master field is empty)
        row_was_updated = False
        
        for ai_col, master_col in cols_to_map.items():
            # Get current value in Master
            current_master_val = str(df_master.at[master_idx, master_col]).strip()
            
            # Only update if Master is effectively EMPTY
            if current_master_val in [str(x) for x in empty_markers]:
                
                ai_val = str(ai_row[ai_col]).strip()
                
                # Only update if AI value is VALID
                if ai_val not in [str(x) for x in empty_markers] and ai_val.lower() != "nan":
                    if ai_val.lower() != "miscellaneous": 
                        df_master.at[master_idx, master_col] = ai_val
                        row_was_updated = True
        
        # 4d. Flag that AI touched this row
        if row_was_updated:
            df_master.at[master_idx, 'Labelled by AI'] = "Yes"
            updated_count += 1

    # 5. Overwrite Master File
    print("-" * 50)
    print(f"UPDATE COMPLETE")
    print(f"Rows Skipped (Master is Verified 'Yes'): {skipped_verified_count}")
    print(f"Rows Skipped (ID not found in Master):   {skipped_no_match_count}")
    print(f"Rows Newly Updated:                      {updated_count}")
    print(f"Overwriting: {master_path}...")
    
    df_master.to_excel(master_path, index=False)
    print("SUCCESS: Single Source of Truth updated.")
    print("-" * 50)

if __name__ == "__main__":
    update_single_source_of_truth()