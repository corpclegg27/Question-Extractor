import pandas as pd
import os

# --- CONFIGURATION ---
BASE_PATH = r"D:\Main\3. Work - Teaching\Projects\Question extractor"
MASTER_FILENAME = "questionToTagUsingAITagged.csv"
METADATA_FILENAME = "DB Metadata.xlsx"
OUTPUT_FILENAME = "questionToTagUsingAITagged.csv"  # New file to avoid overwriting Master

# Helper to normalize strings for comparison (strip spaces)
def normalize(val):
    if pd.isna(val) or val is None:
        return ""
    return str(val).strip()

def run_validation():
    master_path = os.path.join(BASE_PATH, MASTER_FILENAME)
    metadata_path = os.path.join(BASE_PATH, METADATA_FILENAME)
    output_path = os.path.join(BASE_PATH, OUTPUT_FILENAME)

    # 1. LOAD SYLLABUS TREE (The Source of Truth)
    print("LOADING SYLLABUS...")
    try:
        meta_df = pd.read_excel(metadata_path, sheet_name="Syllabus tree", engine='openpyxl')
        
        # Build a Dictionary: { "ChapterName": {"Topic1", "Topic2", ...} }
        valid_syllabus = {}
        
        for ch, group in meta_df.groupby('Chapter'):
            ch_name = normalize(ch)
            if not ch_name or ch_name.lower() in ["nan", "unknown"]: continue
            
            # Get all valid topics for this chapter
            valid_topics = set()
            for t in group['Topic'].unique():
                t_norm = normalize(t)
                if t_norm and t_norm.lower() not in ["nan", "miscellaneous"]:
                    valid_topics.add(t_norm)
            
            valid_syllabus[ch_name] = valid_topics
            
        print(f"✅ Loaded {len(valid_syllabus)} valid chapters from Metadata.")

    except Exception as e:
        print(f"❌ Error loading Metadata: {e}")
        return

    # 2. LOAD MASTER DB
    print("\nLOADING MASTER DATABASE...")
    if not os.path.exists(master_path):
        print("❌ Master DB not found.")
        return
    
    df = pd.read_csv(master_path)
    
    # Initialize Flag Column (Default = "Yes")
    df['TagFromValidList'] = "Yes"
    
    # Statistics counters
    invalid_chapter_count = 0
    invalid_topic_count = 0

    # 3. RUN VALIDATION LOGIC
    print("VALIDATING ROWS...")
    
    for idx, row in df.iterrows():
        # Get current tags from the row
        row_chap = normalize(row.get('Chapter'))
        row_topic = normalize(row.get('Topic'))
        
        is_valid = True
        
        # CHECK 1: Is Chapter in Syllabus?
        if row_chap not in valid_syllabus:
            is_valid = False
            invalid_chapter_count += 1
            # Optional: You can log the reason if you want
            # df.at[idx, 'Validation_Error'] = f"Invalid Chapter: '{row_chap}'"
        
        # CHECK 2: If Chapter is valid, is Topic in that Chapter's list?
        else:
            valid_topics_for_chapter = valid_syllabus[row_chap]
            
            if row_topic not in valid_topics_for_chapter:
                is_valid = False
                invalid_topic_count += 1
                # df.at[idx, 'Validation_Error'] = f"Invalid Topic: '{row_topic}' not in {row_chap}"

        # SET FLAG
        if not is_valid:
            df.at[idx, 'TagFromValidList'] = "No"

    # 4. SAVE TO NEW CSV
    print("-" * 40)
    print(f"VALIDATION COMPLETE")
    print(f"Rows with Invalid Chapters: {invalid_chapter_count}")
    print(f"Rows with Valid Chapter but Invalid Topic: {invalid_topic_count}")
    print(f"Total Invalid Rows Flagged: {invalid_chapter_count + invalid_topic_count}")
    print("-" * 40)
    
    df.to_csv(output_path, index=False)
    print(f"✅ Saved validated data to: {OUTPUT_FILENAME}")

if __name__ == "__main__":
    run_validation()