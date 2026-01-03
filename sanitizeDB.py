import pandas as pd
import os

def run_sanity_update():
    # --- CONFIG ---
    BASE_PATH = "D:/Main/3. Work - Teaching/Projects/Question extractor"
    DB_PATH = os.path.join(BASE_PATH, "DB Master.csv")

    print(f"📂 Loading {DB_PATH}...")
    try:
        df = pd.read_csv(DB_PATH)
    except FileNotFoundError:
        print("❌ Error: DB Master.csv not found.")
        return

    # =================================================================
    # TASK 1: CONSOLIDATE 'Q' and 'Question No.'
    # =================================================================
    print("\nProcessing Column cleanup...")
    
    if 'Question No.' in df.columns:
        # Standardize empty values to NaN
        df['Q'] = df['Q'].replace(r'^\s*$', pd.NA, regex=True)
        
        # Identify rows where Q is missing AND Question No. exists
        missing_q_mask = df['Q'].isna() & df['Question No.'].notna()
        fill_count = missing_q_mask.sum()
        
        if fill_count > 0:
            print(f"   ↳ Found {fill_count} rows with missing 'Q'. Filling from 'Question No.'...")
            df.loc[missing_q_mask, 'Q'] = df.loc[missing_q_mask, 'Question No.']
        else:
            print("   ↳ 'Q' column is fully populated (or 'Question No.' provided no new data).")

        # Drop 'Question No.'
        print("   ↳ Dropping 'Question No.' column...")
        df.drop(columns=['Question No.'], inplace=True)
        
    else:
        print("   ⚠️ Column 'Question No.' not found. Skipping consolidation.")

    # =================================================================
    # TASK 2: CHECK UNIQUE_ID DUPLICATES (READ ONLY)
    # =================================================================
    print("\nChecking 'unique_id' uniqueness...")
    
    if 'unique_id' in df.columns:
        duplicate_ids = df[df.duplicated('unique_id', keep=False)]
        num_duplicates = len(duplicate_ids)
        
        if num_duplicates > 0:
            unique_vals = duplicate_ids['unique_id'].nunique()
            print(f"   ⚠️ WARNING: Found {num_duplicates} rows involved in duplication.")
            print(f"      ({unique_vals} unique IDs repeated).")
            print("      NO CHANGES made to 'unique_id' (as requested).")
        else:
            print("   ✅ PASSED: All 'unique_id' entries are unique.")
    else:
        print("   ❌ Error: 'unique_id' column missing!")

    # =================================================================
    # SAVE OVERWRITE
    # =================================================================
    print(f"\n💾 Overwriting {DB_PATH}...")
    try:
        df.to_csv(DB_PATH, index=False)
        print("✅ Database updated successfully.")
    except PermissionError:
        print("❌ ERROR: Could not save file. Is 'DB Master.csv' open in Excel?")

if __name__ == "__main__":
    run_sanity_update()