import pandas as pd
import ollama
import os
import json
import time

def run_universal_auditor():
    # 1. Configuration
    input_csv = "DB Master_OCR.csv"
    metadata_path = "DB Metadata.xlsx"
    suggested_csv = "Suggested_Tags.csv"
    BASE_PATH = r"D:\Main\3. Work - Teaching\Projects\Question extractor\Processed_Database" 
    client = ollama.Client(host='http://localhost:11434', timeout=180.0)

    # 2. Build Hierarchy
    print("\n[SYSTEM] Initializing Syllabus Hierarchy...")
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
                taxonomy[ch][top] = sorted(list(set(cleaned_l2s)))

    # 3. Load Data & FIX SCHEMA
    df_main = pd.read_csv(input_csv)
    output_cols = ['Q', 'Exam', 'Subject', 'Difficulty_tag', 'Chapter', 'Topic', 'Topic_L2', 
                   'unique_id', 'OCR_Text', 'Sug_Chapter', 'Sug_Topic', 'Sug_Topic_L2', 
                   'Sug_Difficulty', 'AI_Reasoning', 'AI_Confidence', 'AI_Tag_Accepted']

    processed_ids = set()
    
    # --- START FIX: Check for existing file and fix columns if needed ---
    if os.path.exists(suggested_csv):
        try:
            res_df = pd.read_csv(suggested_csv)
            
            # Check if schema is outdated (missing the new column)
            if 'AI_Tag_Accepted' not in res_df.columns:
                print("[SYSTEM] Updating existing CSV schema to include 'AI_Tag_Accepted'...")
                res_df['AI_Tag_Accepted'] = 'No' # Default value for old records
                # Reorder columns to match output_cols to be safe
                res_df = res_df.reindex(columns=output_cols) 
                res_df.to_csv(suggested_csv, index=False)
                print("[SYSTEM] Schema updated successfully.")
            
            processed_ids = set(res_df['unique_id'].astype(str).unique())
        except Exception as e:
            print(f"[ERROR] Could not read existing results file: {e}")
            print("[SYSTEM] Starting fresh to avoid corruption.")
            pd.DataFrame(columns=output_cols).to_csv(suggested_csv, index=False)
    else:
        pd.DataFrame(columns=output_cols).to_csv(suggested_csv, index=False)
    # --- END FIX ---

    df_to_do = df_main[~df_main['unique_id'].astype(str).isin(processed_ids)].copy()
    
    print(f"\n[SYSTEM] Starting Audit: {len(df_to_do)} questions remaining.\n")

    for index, row in df_to_do.iterrows():
        q_start = time.perf_counter()
        
        # --- VARIABLES ---
        q_num = str(row['Q']).strip()
        u_id = str(row['unique_id']).strip()
        folder = str(row['Folder']).strip()
        ocr_text = str(row['OCR_Text'])[:1200]
        
        # --- STAGE 1: CHAPTER ---
        chapter = str(row['Chapter']).strip()
        if chapter.lower() not in ["nan", "unknown", "", "none"]:
            print(f"\n>>> [Q {q_num}] STAGE 1: [SKIPPED] - CHAPTER KNOWN: '{chapter}'")
        else:
            ch_list = sorted(list(taxonomy.keys()))
            ch_prompt = f"""
            ### ROLE: Senior Physics Faculty
            ### QUESTION:
            {ocr_text}

            ### TASK:
            Identify the single Chapter this question belongs to.
            """
            print(f"\n>>> [Q {q_num}] STAGE 1 PROMPT (CHAPTER):\n{ch_prompt}")
            try:
                ch_resp = client.chat(model='llama3.1', messages=[{'role': 'user', 'content': ch_prompt}], 
                                       format={'type':'object', 'properties':{'chapter':{'enum': ch_list + ["Miscellaneous"]}}, 'required':['chapter']})
                chapter = json.loads(ch_resp['message']['content']).get('chapter')
            except:
                chapter = "Miscellaneous"
            print(f"   [AI SELECTION]: {chapter}")

        # --- STAGE 2: TOPIC (UNIVERSAL LOGIC) ---
        topics_available = taxonomy.get(chapter, {})
        topic_list = sorted(list(topics_available.keys())) + ["Miscellaneous"]
        
        t_prompt = f"""
        ### ROLE: Senior Physics Faculty
        ### QUESTION:
        {ocr_text}

        ### CONTEXT:
        Chapter: {chapter}

        ### ALLOWED TOPICS:
        {topic_list}

        ### TASK:
        Analyze the physical setup and select the most specific Topic.

        ### GENERAL GUIDELINES:
        1. **Keyword Matching:** Look for specific physics terms in the question (e.g., 'Flux', 'Inertia', 'Interference') and match them to the Topic list.
        2. **Process vs. Property:** - If the question asks to calculate a static value (like Resistance, Inductance, Moment of Inertia), choose the Topic representing that property.
           - If the question involves a change or interaction (like Conservation, Decay, Collision), choose the Topic representing that process.
        3. **Fallback:** Only use 'Miscellaneous' if the concept is completely absent from the list.
        """
        print(f"\n>>> [Q {q_num}] STAGE 2 PROMPT (TOPIC):\n{t_prompt}")
        
        try:
            t_resp = client.chat(model='llama3.1', messages=[{'role': 'user', 'content': t_prompt}], 
                                 format={'type':'object', 'properties':{'topic':{'enum': topic_list}, 'reasoning':{'type':'string'}}, 'required':['topic', 'reasoning']})
            t_data = json.loads(t_resp['message']['content'])
            selected_topic = t_data.get('topic')
        except:
            selected_topic = "Miscellaneous"
            t_data = {"reasoning": "Error in AI response"}

        print(f"   [AI SELECTION]: {selected_topic}")
        print(f"   [REASONING]:    {t_data.get('reasoning')}")

        # --- STAGE 3: L2 (PATTERN MATCHING) ---
        l2_list = topics_available.get(selected_topic, [])
        if not l2_list:
            final_l2 = "N/A"
            f_prompt = f"### QUESTION:\n{ocr_text}\n\nTASK: Assess Difficulty."
            f_resp = client.chat(model='llama3.1', messages=[{'role': 'user', 'content': f_prompt}], 
                                 format={'type':'object', 'properties':{'difficulty':{'enum':['Easy','Medium','Difficult']}, 'confidence':{'type':'integer','minimum':1}}, 'required':['difficulty', 'confidence']})
            f_data = json.loads(f_resp['message']['content'])
        else:
            l2_options = l2_list + ["Miscellaneous"]
            f_prompt = f"""
            ### ROLE: JEE Physics Subject Matter Expert
            ### QUESTION:
            {ocr_text}

            ### CATEGORY:
            {chapter} > {selected_topic}

            ### ALLOWED SUB-TOPICS (L2):
            {l2_options}

            ### GUIDELINES:
            1. **Specificity:** Choose the sub-topic that describes the specific *case* or *object* in the question (e.g., 'Solenoid' vs 'Toroid', 'Sphere' vs 'Disc').
            2. **Theorem Application:** If the solution requires a specific named theorem/law mentioned in the list, select that.
            3. **Standard Cases:** If the question refers to a standard textbook setup, choose the sub-topic that matches that setup.
            
            ### TASK:
            Select the most precise L2 tag.
            """
            print(f"\n>>> [Q {q_num}] STAGE 3 PROMPT (L2):\n{f_prompt}")
            
            try:
                f_resp = client.chat(model='llama3.1', messages=[{'role': 'user', 'content': f_prompt}], 
                                     format={'type':'object', 'properties':{'topic_l2':{'enum': l2_options}, 'difficulty':{'enum':['Easy','Medium','Difficult']}, 'confidence':{'type':'integer','minimum':1}}, 'required':['topic_l2', 'difficulty', 'confidence']})
                f_data = json.loads(f_resp['message']['content'])
                final_l2 = f_data.get('topic_l2')
            except:
                final_l2 = "Miscellaneous"
                f_data = {"difficulty": "Unknown", "confidence": 0}

            print(f"   [AI SELECTION]: {final_l2}")

        # --- SAVE ---
        new_row = {
            'Q': q_num, 'Exam': row['Exam'], 'Subject': row['Subject'], 
            'Difficulty_tag': row['Difficulty_tag'], 'Chapter': row['Chapter'], 
            'Topic': row['Topic'], 'Topic_L2': row['Topic_L2'], 'unique_id': u_id, 
            'OCR_Text': ocr_text, 'Sug_Chapter': chapter, 'Sug_Topic': selected_topic, 
            'Sug_Topic_L2': final_l2, 'Sug_Difficulty': f_data.get('difficulty'), 
            'AI_Reasoning': t_data.get('reasoning'), 'AI_Confidence': f_data.get('confidence'),
            'AI_Tag_Accepted': 'No' # Default value for new runs
        }
        
        # Ensure row is a DataFrame with correct columns order
        save_df = pd.DataFrame([new_row])
        save_df = save_df[output_cols] # Enforce column order
        save_df.to_csv(suggested_csv, mode='a', header=False, index=False)

        q_time = time.perf_counter() - q_start
        
        # --- FINAL BLOCK ---
        print("\n" + "#" * 100)
        print(f"   RESULTS FOR QUESTION {q_num} (ID: {u_id})")
        print("#" * 100)
        print(f" >> TIME TAKEN:    {q_time:.2f}s")
        print(f" >> FILEPATH:      {os.path.join(BASE_PATH, folder, f'Q_{q_num}.png')}")
        print(f" >> FINAL TAGS:    [{chapter}] -> [{selected_topic}] -> [{final_l2}]")
        print(f" >> ASSESSMENT:    {f_data.get('difficulty')} (Confidence: {f_data.get('confidence')}%)")
        print("-" * 100)
        print(f" >> REASONING:     {t_data.get('reasoning')}")
        print("#" * 100 + "\n\n")

if __name__ == "__main__":
    run_universal_auditor()