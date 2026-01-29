import pandas as pd
import os
import numpy as np

def calculate_tag_depth(row):
    """
    Calculates Quality Score (0-3).
    Score +1 for valid tags in Chapter, Topic, Topic_L2.
    """
    depth = 0
    tag_columns = ['Chapter', 'Topic', 'Topic_L2']
    invalid_values = {'unknown', '', '0', 'nan', 'none', ' '}

    for col in tag_columns:
        if col not in row.index:
            continue
        val = str(row[col]).strip().lower()
        if val not in invalid_values:
            depth += 1
    return depth

def consolidate_q_column(row):
    """
    Standardizes Question Number.
    Prioritizes 'Q', falls back to 'Question No.'.
    """
    def is_valid(val):
        s = str(val).strip().lower()
        return s not in {'nan', '', 'none', 'nat'} and pd.notna(val)

    val_q = row.get('Q', np.nan)
    val_q_no = row.get('Question No.', np.nan)

    if is_valid(val_q):
        return str(val_q).strip()
    elif is_valid(val_q_no):
        return str(val_q_no).strip()
    
    return val_q

def is_text_valid(val):
    """Checks if text fields are non-empty and useful."""
    s = str(val).strip().lower()
    return s not in {'nan', '', 'none', '0'} and pd.notna(val)

def merge_and_synthesize_questions(input_csv_list, output_csv_name):
    print(f"🚀 Starting Merge & Synthesis for {len(input_csv_list)} files...")
    
    dataframes = []

    # 1. Read all CSVs
    for file_path in input_csv_list:
        if os.path.exists(file_path):
            try:
                # Read csv, force unique_id to string
                df = pd.read_csv(file_path, dtype={'unique_id': str})
                df['_source_file'] = os.path.basename(file_path)
                dataframes.append(df)
                print(f"  -> Loaded: {file_path} ({len(df)} rows)")
            except Exception as e:
                print(f"  ❌ Error reading {file_path}: {e}")
        else:
            print(f"  ⚠️ File not found: {file_path}")

    if not dataframes:
        print("❌ No data found. Exiting.")
        return

    merged_df = pd.concat(dataframes, ignore_index=True, sort=False)
    initial_total = len(merged_df)
    print(f"\n📊 Total rows loaded: {initial_total}")

    # 2. Standardize Columns
    print("🛠️  Standardizing Columns...")
    # Ensure keys exist
    for col in ['Q', 'Question No.', 'Folder', 'OCR_Text', 'PDF_Text']:
        if col not in merged_df.columns:
            merged_df[col] = np.nan

    # Consolidate Q
    merged_df['Q'] = merged_df.apply(consolidate_q_column, axis=1)

    # 3. Create Grouping Key: FolderQKey
    # We only process rows where Folder AND Q are valid
    merged_df['temp_folder_str'] = merged_df['Folder'].astype(str).str.strip()
    merged_df['temp_q_str'] = merged_df['Q'].astype(str).str.strip()
    
    # Filter valid rows (can't group if key is missing)
    valid_mask = (merged_df['temp_folder_str'] != 'nan') & (merged_df['temp_q_str'] != 'nan')
    
    # Create Key: "Magnetism_1"
    merged_df.loc[valid_mask, 'FolderQKey'] = merged_df.loc[valid_mask, 'temp_folder_str'] + "_" + merged_df.loc[valid_mask, 'temp_q_str']
    
    # 4. Calculate Tag Depth
    print("🧠 Calculating Tag Depth...")
    merged_df['Tag_Depth'] = merged_df.apply(calculate_tag_depth, axis=1)

    # Separate valid groups from un-groupable rows (missing Folder/Q)
    grouped_df = merged_df[merged_df['FolderQKey'].notna()].copy()
    ungrouped_df = merged_df[merged_df['FolderQKey'].isna()].copy()
    
    print(f"   -> Identifiable Questions: {len(grouped_df)}")
    print(f"   -> Unidentifiable (Missing Folder/Q): {len(ungrouped_df)}")

    # =========================================================
    # 5. SYNTHESIS LOGIC (The "Best of All Worlds" Step)
    # =========================================================
    print("\n🔬 Synthesizing best rows (Tags + Text)...")

    # Step A: Find the "Skeleton" Row (Best Tags)
    # Sort by FolderQKey, then Tag_Depth (High -> Low)
    grouped_df.sort_values(by=['FolderQKey', 'Tag_Depth'], ascending=[True, False], inplace=True)
    
    # 'best_tagged' is our base dataframe. It has the best Chapter/Topic/L2.
    best_tagged = grouped_df.drop_duplicates(subset=['FolderQKey'], keep='first').copy()
    
    # Step B: Find Best OCR Text Source
    # Filter for rows that actually have valid OCR Text
    has_ocr = grouped_df[grouped_df['OCR_Text'].apply(is_text_valid)].copy()
    # If duplicates exist, pick the first one (since we already sorted by Tag Depth, this picks best tagged valid text)
    best_ocr = has_ocr.drop_duplicates(subset=['FolderQKey'], keep='first')[['FolderQKey', 'OCR_Text']]
    best_ocr.rename(columns={'OCR_Text': 'OCR_Text_Fill'}, inplace=True)
    
    # Step C: Find Best PDF Text Source
    has_pdf = grouped_df[grouped_df['PDF_Text'].apply(is_text_valid)].copy()
    best_pdf = has_pdf.drop_duplicates(subset=['FolderQKey'], keep='first')[['FolderQKey', 'PDF_Text']]
    best_pdf.rename(columns={'PDF_Text': 'PDF_Text_Fill'}, inplace=True)

    # Step D: Merge and Fill
    # Attach the "Filler" columns to the "Skeleton"
    final_grouped = pd.merge(best_tagged, best_ocr, on='FolderQKey', how='left')
    final_grouped = pd.merge(final_grouped, best_pdf, on='FolderQKey', how='left')

    # Inject OCR Text if missing in skeleton but found elsewhere
    # (We only overwrite if the skeleton's text is invalid/empty)
    mask_ocr_missing = ~final_grouped['OCR_Text'].apply(is_text_valid)
    final_grouped.loc[mask_ocr_missing, 'OCR_Text'] = final_grouped.loc[mask_ocr_missing, 'OCR_Text_Fill']

    # Inject PDF Text if missing
    mask_pdf_missing = ~final_grouped['PDF_Text'].apply(is_text_valid)
    final_grouped.loc[mask_pdf_missing, 'PDF_Text'] = final_grouped.loc[mask_pdf_missing, 'PDF_Text_Fill']

    # 6. Final Polish
    final_df = pd.concat([final_grouped, ungrouped_df], ignore_index=True)
    
    print(f"✅ Synthesis Complete.")
    print(f"   -> Before: {initial_total} rows")
    print(f"   -> After:  {len(final_df)} unique questions")

    # Drop helper columns
    cols_to_drop = ['Tag_Depth', '_source_file', 'temp_folder_str', 'temp_q_str', 'FolderQKey', 'OCR_Text_Fill', 'PDF_Text_Fill']
    final_df.drop(columns=[c for c in cols_to_drop if c in final_df.columns], inplace=True)
    
    final_df.to_csv(output_csv_name, index=False)
    print(f"\n💾 Saved merged database to: {output_csv_name}")

    # 7. Rename Input Files
    print("\n🧹 Cleaning up input files...")
    for file_path in input_csv_list:
        if os.path.exists(file_path):
            directory, filename = os.path.split(file_path)
            new_filename = f"Review_and_Delete_{filename}"
            new_path = os.path.join(directory, new_filename)
            try:
                os.rename(file_path, new_path)
                print(f"  -> Renamed: {filename} -> {new_filename}")
            except Exception as e:
                print(f"  ❌ Could not rename {filename}: {e}")

# ==========================================
# CONFIGURATION
# ==========================================

inputs_csv_list = [
    r"D:\Main\3. Work - Teaching\Projects\Question extractor\questionToTagUsingAIResultsCD_JEEAdv.csv",
    r"D:\Main\3. Work - Teaching\Projects\Question extractor\Question Bank CD Adv.csv",
    r"D:\Main\3. Work - Teaching\Projects\Question extractor\Question Bank CD Adv MultipleCorrect.csv",
    r"D:\Main\3. Work - Teaching\Projects\Question extractor\Question Bank CD Adv_SCQ_MSQ.csv",
]

output_csv_name = r"D:\Main\3. Work - Teaching\Projects\Question extractor\Merged_Questions_bank_CD_Adv.csv"

if __name__ == "__main__":
    if inputs_csv_list:
        merge_and_synthesize_questions(inputs_csv_list, output_csv_name)
    else:
        print("Please provide a list of input CSV files.")