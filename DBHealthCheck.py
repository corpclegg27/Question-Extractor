import pandas as pd
import os
from pathlib import Path
from tqdm import tqdm

# --- CONFIGURATION ---
# BASE_PATH = Path(r"D:/Main/3. Work - Teaching/Projects/Question extractor")
BASE_PATH = Path(".") # Use this if running inside the folder

CSV_PATH = BASE_PATH / "DB Master.csv"
METADATA_PATH = BASE_PATH / "DB Metadata.xlsx"
IMG_BASE_DIR = BASE_PATH / "Processed_Database"
COMPRESSED_BASE_DIR = IMG_BASE_DIR / "Compressed"

OUTPUT_REPORT = BASE_PATH / "DB Health Check.csv"

def load_chapter_topic_map():
    """
    Loads metadata into a simple dictionary: { 'Chapter': {'Topic1', 'Topic2'} }
    """
    if not METADATA_PATH.exists():
        print(f"❌ Error: Metadata file not found at {METADATA_PATH}")
        return {}

    try:
        df_meta = pd.read_excel(METADATA_PATH, sheet_name="Syllabus tree")
        df_meta = df_meta.map(lambda x: str(x).strip() if pd.notna(x) else "nan")
        
        chapter_map = {}
        for _, row in df_meta.iterrows():
            chap = row.get('Chapter', 'nan')
            top = row.get('Topic', 'nan')

            if chap == 'nan': continue

            if chap not in chapter_map: 
                chapter_map[chap] = set()
            
            if top != 'nan':
                chapter_map[chap].add(top)
                
        print(f"✅ Loaded {len(chapter_map)} Chapters from Metadata.")
        return chapter_map
    except Exception as e:
        print(f"❌ Error reading metadata: {e}")
        return {}

def check_db_health():
    # 1. Load Data
    if not CSV_PATH.exists():
        print(f"❌ Master DB not found at {CSV_PATH}")
        return

    print("⏳ Loading DB Master...")
    df = pd.read_csv(CSV_PATH)
    
    # Normalize Inputs
    df.columns = df.columns.str.strip()
    df['unique_id'] = df['unique_id'].astype(str).str.strip()
    
    valid_chapters = load_chapter_topic_map()
    
    report_data = []
    
    print(f"🚀 Validating {len(df)} records...")

    for idx, row in tqdm(df.iterrows(), total=len(df), unit="q"):
        uid = row.get('unique_id', f"Unknown_{idx}")
        folder = str(row.get('Folder', '')).strip()
        q_num = str(row.get('Question No.', '')).strip()
        
        # --- A. HIERARCHY VALIDATION ---
        chap = str(row.get('Chapter', '')).strip()
        top = str(row.get('Topic', '')).strip()
        
        chap_issue = "None"
        topic_issue = "None"
        is_tag_valid = True
        
        # 1. Check Chapter
        if chap == '' or chap.lower() == 'nan':
             chap_issue = "Missing"
             is_tag_valid = False
        elif chap not in valid_chapters:
            chap_issue = "Unknown" # Typo or not in Tree
            is_tag_valid = False
            
        # 2. Check Topic (Only checks if Chapter is valid)
        if chap_issue == "None":
            # If topic exists, it MUST be in the allowed list for this chapter
            if top and top.lower() != 'nan':
                allowed_topics = valid_chapters[chap]
                if allowed_topics and top not in allowed_topics:
                    topic_issue = "Invalid"
                    is_tag_valid = False
        else:
            # If chapter is invalid, we can't validate topic strictly
            if top and top.lower() != 'nan':
                 topic_issue = "Cannot Validate (Bad Chapter)"

        # --- B. ASSET VALIDATION (Compressed Only) ---
        fname_q = f"Q_{q_num}.png"
        fname_sol = f"Sol_{q_num}.png"
        
        path_comp_q = COMPRESSED_BASE_DIR / folder / fname_q
        path_comp_sol = COMPRESSED_BASE_DIR / folder / fname_sol
        
        has_comp_q = path_comp_q.exists()
        has_comp_sol = path_comp_sol.exists()
        
        # --- C. STATUS ---
        # Ready if: Tags Valid AND Compressed Question Exists
        is_ready = is_tag_valid and has_comp_q

        report_data.append({
            'unique_id': uid,
            'Folder': folder,
            'Question No.': q_num,
            'Chapter': chap,
            'Topic': top,
            'Chapter_Tag_Issue': chap_issue,
            'Topic_Tag_Issue': topic_issue,
            'Comp_Q_Found': has_comp_q,
            'Comp_Sol_Found': has_comp_sol,
            'OVERALL_STATUS': "READY" if is_ready else "FAIL"
        })

    # --- SAVE REPORT ---
    df_report = pd.DataFrame(report_data)
    df_report.to_csv(OUTPUT_REPORT, index=False)
    
    # --- SUMMARY ---
    print("\n" + "="*40)
    print("      HEALTH CHECK SUMMARY")
    print("="*40)
    
    total = len(df_report)
    passed = df_report[df_report['OVERALL_STATUS'] == "READY"].shape[0]
    failed = total - passed
    
    print(f"Total Records:      {total}")
    print(f"✅ READY to Migrate: {passed} ({(passed/total)*100:.1f}%)")
    print(f"❌ FAILED Check:     {failed} ({(failed/total)*100:.1f}%)")
    print("-" * 40)
    
    if failed > 0:
        chap_fails = df_report[df_report['Chapter_Tag_Issue'] != "None"].shape[0]
        topic_fails = df_report[df_report['Topic_Tag_Issue'] == "Invalid"].shape[0]
        missing_imgs = df_report[~df_report['Comp_Q_Found']].shape[0]
        
        print("Failure Breakdown:")
        print(f" • Chapter Issues: {chap_fails}")
        print(f" • Topic Issues:   {topic_fails}")
        print(f" • Missing Images: {missing_imgs}")
        
    print(f"\nDetailed report saved to: {OUTPUT_REPORT}")
    print("="*40)

if __name__ == "__main__":
    check_db_health()