import pandas as pd
import os

def update_database_from_metadata():
    # --- 1. CONFIGURATION ---
    base_path = r"D:\Main\3. Work - Teaching\Projects\Question extractor"
    main_db_path = os.path.join(base_path, "DB Master.csv") # Assuming csv based on your prompt
    metadata_path = os.path.join(base_path, "DB Metadata.xlsx")
    output_path = os.path.join(base_path, "DB Master_Updated.csv")

    print("Loading databases...")
    
    # Load Main DB
    if not os.path.exists(main_db_path):
        # Fallback to xlsx if csv doesn't exist, just in case
        main_db_path = os.path.join(base_path, "DB Master.xlsx")
        if not os.path.exists(main_db_path):
            print(f"❌ Error: Could not find DB Master at {base_path}")
            return
        main_df = pd.read_excel(main_db_path)
    else:
        main_df = pd.read_csv(main_db_path)

    # Load Tagged Metadata
    try:
        tagged_df = pd.read_excel(metadata_path, sheet_name="CD_Metadata")
    except Exception as e:
        print(f"❌ Error loading metadata sheet: {e}")
        return

    # --- 2. CREATE TEMP KEYS ---
    print("Creating temporary keys for matching...")
    
    # Ensure columns are strings to avoid type mismatch errors
    main_df['Folder'] = main_df['Folder'].fillna('').astype(str).str.strip()
    main_df['Q'] = main_df['Q'].fillna('').astype(str).str.strip()
    
    tagged_df['Folder'] = tagged_df['Folder'].fillna('').astype(str).str.strip()
    tagged_df['Q'] = tagged_df['Q'].fillna('').astype(str).str.strip()

    # Create Key: "Folder_Q"
    main_df['Temp_Key'] = main_df['Folder'] + "_" + main_df['Q']
    tagged_df['Temp_Key'] = tagged_df['Folder'] + "_" + tagged_df['Q']

    # Index tagged_df for faster lookup
    tagged_df.set_index('Temp_Key', inplace=True)

    # --- 3. FILL MISSING DATA ---
    print("Merging data...")
    
    # Counter for stats
    updates_count = 0
    missing_before = 0
    
    # Columns to check and fill
    target_columns = ['Chapter', 'Topic']

    for index, row in main_df.iterrows():
        key = row['Temp_Key']
        
        # Check if we have manual tags for this question
        if key in tagged_df.index:
            source_row = tagged_df.loc[key]
            
            # Handle duplicates in tagged_df (just take the first one if multiple exist)
            if isinstance(source_row, pd.DataFrame):
                source_row = source_row.iloc[0]

            row_updated = False
            
            for col in target_columns:
                current_val = str(row[col]).strip().lower()
                
                # Condition: If current value is missing, nan, or unknown
                if current_val in ['nan', 'unknown', '', 'none']:
                    
                    # Check if new value exists
                    new_val = str(source_row.get(col, '')).strip()
                    
                    if new_val and new_val.lower() not in ['nan', 'unknown', '', 'none']:
                        main_df.at[index, col] = new_val
                        row_updated = True
            
            if row_updated:
                updates_count += 1

    # --- 4. CLEANUP & SAVE ---
    # Remove the temporary key before saving
    main_df.drop(columns=['Temp_Key'], inplace=True)
    
    print(f"Saving updated database to: {output_path}")
    main_df.to_csv(output_path, index=False)

    # --- 5. INSIGHTS ---
    total_questions = len(main_df)
    
    # Calculate how many still need tags
    missing_chapter = main_df['Chapter'].map(lambda x: str(x).lower() in ['nan', 'unknown', '', 'none']).sum()
    missing_topic = main_df['Topic'].map(lambda x: str(x).lower() in ['nan', 'unknown', '', 'none']).sum()

    print("\n" + "="*50)
    print("            MIGRATION SUMMARY")
    print("="*50)
    print(f"• Total Questions processed:   {total_questions}")
    print(f"• Rows updated with new tags:  {updates_count}")
    print("-" * 50)
    print(f"• Questions still missing Chapter: {missing_chapter}")
    print(f"• Questions still missing Topic:   {missing_topic}")
    print("="*50)

if __name__ == "__main__":
    update_database_from_metadata()