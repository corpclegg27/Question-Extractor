import pandas as pd
import os

def calculate_processing_load():
    # --- CONFIGURATION ---
    BASE_PATH = r"D:\Main\3. Work - Teaching\Projects\Question extractor"
    # Change this to "DB Master_OCR.csv" if you want to check the WHOLE database
    INPUT_FILENAME = "DB Master.csv" 
    METADATA_FILENAME = "DB Metadata.xlsx"

    input_csv = os.path.join(BASE_PATH, INPUT_FILENAME)
    metadata_path = os.path.join(BASE_PATH, METADATA_FILENAME)

    # --- 1. LOAD TAXONOMY ---
    print("Loading Taxonomy...")
    try:
        meta_df = pd.read_excel(metadata_path, sheet_name="Syllabus tree", engine='openpyxl')
        meta_df = meta_df.map(lambda x: str(x).strip() if pd.notna(x) else "nan")

        taxonomy = {}
        for ch, group in meta_df.groupby('Chapter'):
            taxonomy[ch] = {}
            for top, sub_group in group.groupby('Topic'):
                if top.lower() != "nan" and top.lower() != ch.lower():
                    l2s = [v for v in sub_group['Topic_L2'].unique() if v.lower() != "nan"]
                    cleaned_l2s = []
                    for item in l2s:
                        cleaned_l2s.extend([i.strip() for i in item.replace('[','').replace(']','').replace("'",'').split(',')])
                    taxonomy[ch][top] = sorted(list(set([x for x in cleaned_l2s if x])))
    except Exception as e:
        print(f"❌ Error loading Metadata: {e}")
        return

    # --- 2. LOAD DATA ---
    if not os.path.exists(input_csv):
        print(f"❌ Input CSV not found: {input_csv}")
        return

    df_main = pd.read_csv(input_csv)
    
    # Exclude already processed ones if you have a results file, otherwise assumes fresh run
    print(f"Analyzing {len(df_main)} questions with new skipping logic...\n")

    # --- 3. COUNTERS ---
    stats = {
        "chapter_ai_calls": 0,
        "topic_ai_calls": 0,
        "l2_ai_calls": 0,
        "total_ai_calls": 0,
        "skipped_stage_2_single_topic": 0,
        "skipped_stage_3_no_l2": 0
    }

    # --- 4. SIMULATION LOOP ---
    for index, row in df_main.iterrows():
        # Variables
        chapter = None
        selected_topic = None
        
        # --- STAGE 1 CHECK (CHAPTER) ---
        existing_chapter = str(row['Chapter']).strip()
        is_chapter_known = existing_chapter.lower() not in ["nan", "unknown", "", "none"] and existing_chapter in taxonomy
        
        if is_chapter_known:
            chapter = existing_chapter
        else:
            stats["chapter_ai_calls"] += 1
            # We can't simulate Stage 2/3 accurately if we don't know the chapter, 
            # so we assume worst case: AI finds a chapter with multiple topics.
            stats["topic_ai_calls"] += 1
            stats["l2_ai_calls"] += 1
            continue # Move to next question as we can't predict the specific taxonomy path

        # --- STAGE 2 CHECK (TOPIC) ---
        topics_available = taxonomy.get(chapter, {})
        existing_topic = str(row['Topic']).strip()
        is_topic_known = existing_topic.lower() not in ["nan", "unknown", "", "none"] and existing_topic in topics_available
        
        if is_topic_known:
            selected_topic = existing_topic
        elif len(topics_available) == 1:
            # SKIP: Only one topic exists
            stats["skipped_stage_2_single_topic"] += 1
            selected_topic = list(topics_available.keys())[0]
        else:
            stats["topic_ai_calls"] += 1
            # Again, assume worst case that AI picks a topic that needs L2
            stats["l2_ai_calls"] += 1
            continue

        # --- STAGE 3 CHECK (L2) ---
        l2_list = topics_available.get(selected_topic, [])
        
        if not l2_list:
            # SKIP: No L2 tags exist for this topic
            stats["skipped_stage_3_no_l2"] += 1
        else:
            stats["l2_ai_calls"] += 1

    # --- 5. REPORT ---
    stats["total_ai_calls"] = stats["chapter_ai_calls"] + stats["topic_ai_calls"] + stats["l2_ai_calls"]
    # Estimate: Llama 3.2 is fast (~1.5s per call on GPU, maybe 3s on CPU)
    est_time_min = (stats["total_ai_calls"] * 1.5) / 60
    est_time_max = (stats["total_ai_calls"] * 4.0) / 60

    print("="*60)
    print("             PRE-RUN SIMULATION REPORT")
    print("="*60)
    print(f"Total Questions:         {len(df_main)}")
    print("-" * 60)
    print(f"AI Calls - Stage 1 (Chapter):   {stats['chapter_ai_calls']}")
    print(f"AI Calls - Stage 2 (Topic):     {stats['topic_ai_calls']}")
    print(f"AI Calls - Stage 3 (L2 Tags):   {stats['l2_ai_calls']}")
    print("-" * 60)
    print(f"TOTAL AI CALLS REQUIRED:        {stats['total_ai_calls']}")
    print(f"ESTIMATED TIME:                 {est_time_min:.1f} to {est_time_max:.1f} minutes")
    print("="*60)
    print("Savings from Logic Upgrades:")
    print(f"• Skipped Topic (Single Choice): {stats['skipped_stage_2_single_topic']}")
    print(f"• Skipped L2 (None Defined):     {stats['skipped_stage_3_no_l2']}")
    print("="*60)

if __name__ == "__main__":
    calculate_processing_load()