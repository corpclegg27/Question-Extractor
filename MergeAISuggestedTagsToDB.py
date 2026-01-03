import pandas as pd
import os
import shutil
from datetime import datetime

def update_single_source_of_truth():
    # --- 1. CONFIGURATION ---
    # BASE_PATH = r"D:\Main\3. Work - Teaching\Projects\Question extractor"
    BASE_PATH = "." 
    
    MASTER_FILENAME = "DB Master.csv" 
    SUGGESTIONS_FILENAME = "questionToTagUsingAITagged.csv" 

    master_path = os.path.join(BASE_PATH, MASTER_FILENAME)
    suggestions_path = os.path.join(BASE_PATH, SUGGESTIONS_FILENAME)
    
    # Define "Empty" markers (Values we are allowed to overwrite)
    empty_markers = ["", "nan", "NaN", "unknown", "Unknown", "None", "none", "0", 0, "Manual_Review_Required"]

    # --- 2. SAFETY: BACKUP ---
    if os.path.exists(master_path):
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup_path = f"{master_path.replace('.csv', '')}_BACKUP_{timestamp}.csv"
        shutil.copy(master_path, backup_path)
        print(f"[SAFETY] Backup created: {backup_path}")
    else:
        print(f"[ERROR] {master_path} not found!")
        return

    # --- 3. LOAD DATABASES ---
    print("Loading datasets...")
    df_master = pd.read_csv(master_path)
    
    if not os.path.exists(suggestions_path):
        print(f"[ERROR] {suggestions_path} not found.")
        return
    
    df_ai = pd.read_csv(suggestions_path)
    print(f"[INFO] Loaded {len(df_ai)} suggestions.")

    # Normalize IDs
    df_master['unique_id'] = df_master['unique_id'].astype(str).str.strip()
    df_ai['unique_id'] = df_ai['unique_id'].astype(str).str.strip()
    
    # --- ENSURE META COLUMNS EXIST ---
    meta_cols = ['Labelled by AI', 'AI_Reasoning', 'Model_Used']
    for col in meta_cols:
        if col not in df_master.columns:
            df_master[col] = ""

    # Initialize Sort Helper Column (0 = Old, 1 = Newly Updated)
    df_master['_temp_newly_updated'] = 0

    # Lookup Dict
    master_lookup = df_master.reset_index().set_index('unique_id')['index'].to_dict()

    # --- 4. MERGE LOGIC ---
    print(f"Merging AI tags (including Model Used)...")
    
    updated_count = 0
    skipped_verified = 0
    
    # Map AI columns to Master columns
    # Note: We handle Model_Used separately as it's metadata
    cols_to_map = {
        'Chapter': 'Chapter',
        'Topic': 'Topic',
        'Topic_L2': 'Topic_L2'
    }

    for index, ai_row in df_ai.iterrows():
        uid = ai_row['unique_id']
        
        if uid not in master_lookup: continue
        master_idx = master_lookup[uid]
        
        # Check Verification Lock
        if 'AI_Tag_Accepted' in df_master.columns:
            val = str(df_master.at[master_idx, 'AI_Tag_Accepted']).strip().lower()
            if val == 'yes':
                skipped_verified += 1
                continue 
            
        row_was_updated = False
        
        # Check if AI result is valid (skip errors)
        ai_reasoning = str(ai_row.get('AI_Reasoning', '')).lower()
        if "missed" in ai_reasoning or "fail" in ai_reasoning:
            continue 

        # Transfer Content Tags
        for ai_col, master_col in cols_to_map.items():
            current_master_val = str(df_master.at[master_idx, master_col]).strip()
            
            if ai_col in ai_row:
                ai_val = str(ai_row[ai_col]).strip()
                
                is_master_empty = current_master_val in [str(x) for x in empty_markers]
                is_ai_valid = ai_val not in [str(x) for x in empty_markers] and ai_val.lower() != "nan"
                
                if is_master_empty and is_ai_valid:
                    df_master.at[master_idx, master_col] = ai_val
                    row_was_updated = True
        
        # If we updated any data, update the Metadata fields
        if row_was_updated:
            df_master.at[master_idx, 'Labelled by AI'] = "Yes"
            df_master.at[master_idx, '_temp_newly_updated'] = 1 # Mark for sorting
            
            # Transfer Meta info if available
            if 'AI_Reasoning' in df_ai.columns:
                 df_master.at[master_idx, 'AI_Reasoning'] = ai_row['AI_Reasoning']
            
            if 'Model_Used' in df_ai.columns:
                 df_master.at[master_idx, 'Model_Used'] = ai_row['Model_Used']

            updated_count += 1

    # --- 5. SORT & SAVE ---
    print(f"Sorting {updated_count} newly updated rows to the top...")
    
    # Sort by: 1. Newly Updated (Desc), 2. Unique ID (Asc)
    df_master = df_master.sort_values(by=['_temp_newly_updated', 'unique_id'], ascending=[False, True])
    
    # Clean up helper column
    df_master.drop(columns=['_temp_newly_updated'], inplace=True)

    print("-" * 50)
    print(f"UPDATE COMPLETE")
    print(f"Rows Skipped (Verified):   {skipped_verified}")
    print(f"Rows Updated & Moved Top:  {updated_count}")
    print(f"Overwriting: {master_path}...")
    
    df_master.to_csv(master_path, index=False)
    print("SUCCESS: Database updated (Model info included).")
    print("-" * 50)

if __name__ == "__main__":
    update_single_source_of_truth()