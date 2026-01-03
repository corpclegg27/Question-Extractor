import pandas as pd
import ollama
import os
import json
import time
import sys

def run_universal_auditor():
    # --- 1. CONFIGURATION ---
    BASE_PATH = r"D:\Main\3. Work - Teaching\Projects\Question extractor"
    TARGET_FILENAME = "questionToTagUsingAI.csv"
    METADATA_FILENAME = "DB Metadata.xlsx"

    target_csv = os.path.join(BASE_PATH, TARGET_FILENAME)
    metadata_path = os.path.join(BASE_PATH, METADATA_FILENAME)
    
    # Using Llama 3.1
    MODEL_NAME = 'llama3.1' 
    client = ollama.Client(host='http://localhost:11434', timeout=180.0)

    # --- 2. BUILD HIERARCHY & SYLLABUS CONTEXT ---
    print("\n[SYSTEM] Initializing Syllabus Hierarchy...")
    syllabus_context_str = ""
    
    try:
        meta_df = pd.read_excel(metadata_path, sheet_name="Syllabus tree", engine='openpyxl')
        meta_df = meta_df.map(lambda x: str(x).strip() if pd.notna(x) else "nan")

        taxonomy = {}
        syllabus_lines = []

        for ch, group in meta_df.groupby('Chapter'):
            if ch.lower() in ["unknown", "nan", "none", "", "miscellaneous"]:
                continue

            taxonomy[ch] = {}
            topics_in_chapter = []
            
            for top, sub_group in group.groupby('Topic'):
                if top.lower() not in ["nan", "unknown", "none", "", "miscellaneous", ch.lower()]:
                    topics_in_chapter.append(top)
                    
                    l2s = [v for v in sub_group['Topic_L2'].unique() if v.lower() != "nan"]
                    cleaned_l2s = []
                    for item in l2s:
                        cleaned_l2s.extend([i.strip() for i in item.replace('[','').replace(']','').replace("'",'').split(',')])
                    
                    valid_l2s = [x for x in cleaned_l2s if x and x.lower() != "miscellaneous"]
                    taxonomy[ch][top] = sorted(list(set(valid_l2s)))
            
            # Create the mapping string: "Chapter Name: Topic 1, Topic 2, Topic 3"
            if topics_in_chapter:
                syllabus_lines.append(f"- {ch}: {', '.join(topics_in_chapter)}")
        
        syllabus_context_str = "\n".join(syllabus_lines)

    except Exception as e:
        print(f"❌ Critical Error loading Metadata: {e}")
        return

    # --- 3. LOAD DATA ---
    if not os.path.exists(target_csv):
        print(f"❌ Target CSV not found: {target_csv}")
        return

    print(f"[SYSTEM] Loading {TARGET_FILENAME}...")
    df_main = pd.read_csv(target_csv)

    ai_meta_cols = ['AI_Reasoning', 'AI_Confidence', 'AI_Tag_Accepted']
    for col in ai_meta_cols:
        if col not in df_main.columns:
            df_main[col] = None 
            if col == 'AI_Tag_Accepted':
                df_main[col] = 'No'

    pending_indices = df_main[df_main['AI_Reasoning'].isna() | (df_main['AI_Reasoning'] == "")].index.tolist()
    
    print(f"\n[SYSTEM] Starting Strict Audit using {MODEL_NAME}.")
    print(f"        Total Rows: {len(df_main)}")
    print(f"        Pending:    {len(pending_indices)}")

    stats = {
        "total_processed": 0,
        "chapter_was_missing": 0,
        "topic_was_missing": 0
    }

    # --- 4. PROCESSING LOOP ---
    try:
        for idx in pending_indices:
            row = df_main.loc[idx]
            q_start = time.perf_counter()
            
            q_num = str(row['Q']).strip()
            ocr_text = str(row['OCR_Text'])[:1200]
            orig_chapter = str(row['Chapter']).strip()
            
            # --- STAGE 1: CHAPTER ---
            # Check if original chapter is valid
            existing_chapter = orig_chapter
            is_chapter_known = existing_chapter.lower() not in ["nan", "unknown", "", "none"] and existing_chapter in taxonomy
            
            if not is_chapter_known:
                stats["chapter_was_missing"] += 1
            
            if is_chapter_known:
                print(f"\n>>> [Q {q_num}] STAGE 1: [SKIPPED] - CHAPTER KNOWN: '{existing_chapter}'")
                chapter = existing_chapter
            else:
                # LIST FOR ENUM (OUTPUT CONSTRAINTS)
                ch_list = sorted(list(taxonomy.keys()))
                
                # *** CORRECTION HERE: Sending syllabus_context_str (Chapter + Topics) instead of just list ***
                ch_prompt = f"""
You are an expert Physics Faculty for JEE/NEET.

[SYLLABUS MAP (Chapter: Topics Included)]
{syllabus_context_str}

[STRICT RULES]
1. You MUST select exactly one Chapter Name from the map above.
2. Read the topics in the map. If the question mentions concepts (e.g., "centripetal acceleration"), find which Chapter contains that Topic.
3. You are FORBIDDEN from creating new categories.
4. Output JSON only: {{"chapter": "Exact Chapter Name"}}

[QUESTION TEXT]
{ocr_text}
"""
                
                print(f"\n{'='*20} FULL PROMPT (CHAPTER) {'='*20}")
                print(ch_prompt)
                print(f"{'='*60}")

                try:
                    ch_resp = client.chat(
                        model=MODEL_NAME, 
                        messages=[{'role': 'user', 'content': ch_prompt}], 
                        format={'type':'object', 'properties':{'chapter':{'enum': ch_list}}, 'required':['chapter']}
                    )
                    chapter = json.loads(ch_resp['message']['content']).get('chapter')
                except Exception as e:
                    print(f"API Error: {e}")
                    chapter = "MANUAL_REVIEW_REQUIRED"
                
                print(f"   [AI SELECTION]: {chapter}")

            # --- STAGE 2: TOPIC ---
            if chapter not in taxonomy:
                selected_topic = "N/A"
                final_l2 = "N/A"
                f_data = {"difficulty": "Unknown", "confidence": 0}
                t_data = {"reasoning": "Chapter invalid or skipped."}
            else:
                topics_available = taxonomy.get(chapter, {})
                topic_list = sorted(list(topics_available.keys()))
                
                existing_topic = str(row['Topic']).strip()
                is_topic_known = existing_topic.lower() not in ["nan", "unknown", "", "none"] and existing_topic in topics_available

                if is_chapter_known and not is_topic_known:
                    stats["topic_was_missing"] += 1
                
                if is_topic_known:
                    print(f">>> [Q {q_num}] STAGE 2: [SKIPPED] - TOPIC KNOWN: '{existing_topic}'")
                    selected_topic = existing_topic
                    t_data = {"reasoning": "Pre-classified in source."}
                
                elif not topic_list:
                    print(f">>> [Q {q_num}] STAGE 2: [SKIPPED] - NO TOPICS DEFINED FOR CHAPTER '{chapter}'")
                    selected_topic = "General"
                    t_data = {"reasoning": "No topics in syllabus."}

                elif len(topic_list) == 1:
                    print(f">>> [Q {q_num}] STAGE 2: [SKIPPED] - SINGLE TOPIC: '{topic_list[0]}'")
                    selected_topic = topic_list[0]
                    t_data = {"reasoning": "Only one topic exists."}
                    
                else:
                    t_prompt = f"""
You are an expert Physics Faculty.

[CONTEXT]
Selected Chapter: {chapter}

[ALLOWED TOPICS]
{', '.join(topic_list)}

[STRICT RULES]
1. Select the BEST fitting topic from the list.
2. NO "Miscellaneous" or "Other".
3. Use keyword matching if the text is unclear.

[QUESTION TEXT]
{ocr_text}
"""
                    print(f"\n{'-'*20} FULL PROMPT (TOPIC) {'-'*20}")
                    print(t_prompt)
                    print(f"{'-'*60}")
                    
                    try:
                        t_resp = client.chat(
                            model=MODEL_NAME, 
                            messages=[{'role': 'user', 'content': t_prompt}], 
                            format={'type':'object', 'properties':{'topic':{'enum': topic_list}, 'reasoning':{'type':'string'}}, 'required':['topic', 'reasoning']}
                        )
                        t_data = json.loads(t_resp['message']['content'])
                        selected_topic = t_data.get('topic')
                    except Exception as e:
                        print(f"API Error: {e}")
                        selected_topic = "MANUAL_REVIEW_REQUIRED"
                        t_data = {"reasoning": "API Error"}

                    print(f"   [AI SELECTION]: {selected_topic}")

                # --- STAGE 3: L2 (SUB-TOPIC) ---
                l2_list = topics_available.get(selected_topic, [])
                
                if not l2_list or selected_topic == "MANUAL_REVIEW_REQUIRED":
                    final_l2 = "N/A"
                    d_prompt = f"Assess difficulty of this physics question: {ocr_text}"
                    try:
                        d_resp = client.chat(model=MODEL_NAME, messages=[{'role': 'user', 'content': d_prompt}],
                                             format={'type':'object', 'properties':{'difficulty':{'enum':['Easy','Medium','Difficult']}, 'confidence':{'type':'integer'}}, 'required':['difficulty']})
                        f_data = json.loads(d_resp['message']['content'])
                    except:
                        f_data = {"difficulty": "Medium", "confidence": 0}

                else:
                    l2_options = sorted(l2_list)
                    
                    f_prompt = f"""
[CONTEXT]
Category: {chapter} > {selected_topic}

[ALLOWED SUB-TOPICS]
{', '.join(l2_options)}

[RULES]
1. Pick exactly one Sub-Topic.
2. NO "Miscellaneous". Force a best fit.
3. Also assess difficulty (Easy/Medium/Difficult).

[QUESTION TEXT]
{ocr_text}
"""
                    print(f"\n{'-'*20} FULL PROMPT (L2) {'-'*20}")
                    print(f_prompt)
                    print(f"{'-'*60}")

                    try:
                        f_resp = client.chat(
                            model=MODEL_NAME, 
                            messages=[{'role': 'user', 'content': f_prompt}], 
                            format={'type':'object', 'properties':{'topic_l2':{'enum': l2_options}, 'difficulty':{'enum':['Easy','Medium','Difficult']}, 'confidence':{'type':'integer','minimum':1}}, 'required':['topic_l2', 'difficulty', 'confidence']}
                        )
                        f_data = json.loads(f_resp['message']['content'])
                        final_l2 = f_data.get('topic_l2')
                    except Exception as e:
                        print(f"API Error: {e}")
                        final_l2 = "MANUAL_REVIEW_REQUIRED"
                        f_data = {"difficulty": "Unknown", "confidence": 0}

                    print(f"   [AI SELECTION]: {final_l2}")

            # --- SAVE ---
            df_main.at[idx, 'Chapter'] = chapter
            df_main.at[idx, 'Topic'] = selected_topic
            df_main.at[idx, 'Topic_L2'] = final_l2
            df_main.at[idx, 'Difficulty_tag'] = f_data.get('difficulty')
            
            df_main.at[idx, 'AI_Reasoning'] = t_data.get('reasoning')
            df_main.at[idx, 'AI_Confidence'] = f_data.get('confidence')
            
            df_main.to_csv(target_csv, index=False)
            
            stats["total_processed"] += 1
            print(f"   [DONE] Time: {(time.perf_counter() - q_start):.2f}s | Confidence: {f_data.get('confidence')}%")
            print("=" * 60)

    except KeyboardInterrupt:
        print("\n\n🛑 STOPPING SCRIPT...")

    finally:
        print(f"\nTotal Processed: {stats['total_processed']}")
        print(f"File saved: {target_csv}")

if __name__ == "__main__":
    run_universal_auditor()