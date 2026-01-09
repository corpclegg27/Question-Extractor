import pandas as pd
import os
import json
import time
from groq import Groq
from tqdm import tqdm

# --- 1. CONFIGURATION ---
BASE_PATH = r"D:\Main\3. Work - Teaching\Projects\Question extractor"
TARGET_FILENAME = "questionToTagUsingAI.csv"
METADATA_FILENAME = "DB Metadata.xlsx"

# API KEY
GROQ_API_KEY = "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"

# BATCH SETTINGS
BATCH_SIZE = 5
VERBOSE = True 

MODEL_QUEUE = [
    "openai/gpt-oss-120b", 
    "llama-3.3-70b-versatile",
    "meta-llama/llama-4-maverick-17b-128e-instruct", 
    "openai/gpt-oss-20b",
    "qwen/qwen3-32b",
]

client = Groq(api_key=GROQ_API_KEY)
current_model_index = 0

# --- 2. HIERARCHICAL SYLLABUS LOADER ---
def load_hierarchical_syllabus(metadata_path):
    print("⏳ Loading Syllabus Tree...")
    try:
        meta_df = pd.read_excel(metadata_path, sheet_name="Syllabus tree", engine='openpyxl')
        meta_df = meta_df.map(lambda x: str(x).strip() if pd.notna(x) else "nan")
        
        chapter_list = sorted([c for c in meta_df['Chapter'].unique() if c.lower() not in ["nan", "Unknown"]])
        chapter_map = {i+1: name for i, name in enumerate(chapter_list)}
        
        topic_map = {}
        l2_map = {}

        for ch in chapter_list:
            ch_rows = meta_df[meta_df['Chapter'] == ch]
            topics = sorted([t for t in ch_rows['Topic'].unique() if t.lower() not in ["nan", "miscellaneous"]])
            topic_map[ch] = {i+1: name for i, name in enumerate(topics)}
            
            for t in topics:
                t_rows = ch_rows[ch_rows['Topic'] == t]
                l2_options = set()
                
                # --- FIX: Split comma-separated L2 values ---
                if 'Topic_L2' in t_rows.columns:
                    raw_values = t_rows['Topic_L2'].unique()
                    for val in raw_values:
                        if val.lower() not in ["nan", "none", ""]:
                            # Split by comma and clean whitespace
                            parts = [p.strip() for p in val.split(',')]
                            l2_options.update(parts)
                
                # Filter out empty strings after split
                valid_l2s = sorted([x for x in l2_options if x])
                
                if valid_l2s:
                    l2_map[t] = {i+1: name for i, name in enumerate(valid_l2s)}
                else:
                    l2_map[t] = {} 

        print(f"✅ Loaded {len(chapter_map)} Chapters.")
        print(f"✅ Loaded L2 maps for {len(l2_map)} Topics (Split Logic Applied).")
        return chapter_map, topic_map, l2_map

    except Exception as e:
        print(f"❌ Error loading syllabus: {e}")
        return {}, {}, {}

def generate_menu(options_dict):
    return "\n".join([f"{k}. {v}" for k, v in options_dict.items()])

# --- 3. AI INTERACTION (ROBUST) ---
def call_ai_with_retry(system_prompt, user_prompt):
    global current_model_index
    
    for _ in range(len(MODEL_QUEUE)):
        if current_model_index >= len(MODEL_QUEUE):
            current_model_index = 0 

        model = MODEL_QUEUE[current_model_index]
        
        try:
            if VERBOSE:
                print(f"\n--- [SENDING TO {model}] ---")
                print(f"SYSTEM:\n{system_prompt[:300]}...\n") 
                print(f"USER:\n{user_prompt[:500]}\n----------------------------")
            
            completion = client.chat.completions.create(
                model=model,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt}
                ],
                temperature=0, 
                response_format={"type": "json_object"}
            )
            
            raw_resp = completion.choices[0].message.content
            if VERBOSE:
                print(f"RECEIVED:\n{raw_resp}\n")
            
            return json.loads(raw_resp), model

        except Exception as e:
            err = str(e).lower()
            print(f"❌ Error ({model}): {e}")
            current_model_index += 1
            time.sleep(1) 

    return None, None

# --- 4. MAIN TAGGING LOGIC ---
def run_hierarchical_tagger():
    target_csv = os.path.join(BASE_PATH, TARGET_FILENAME)
    meta_path = os.path.join(BASE_PATH, METADATA_FILENAME)
    
    # 1. Load Syllabus
    chapter_idx, topic_idx_map, l2_idx_map = load_hierarchical_syllabus(meta_path)
    if not chapter_idx: return

    # 2. Load Data
    if not os.path.exists(target_csv):
        print(f"❌ Error: {target_csv} missing.")
        return
        
    df = pd.read_csv(target_csv)
    
    for c in ['Chapter', 'Topic', 'Topic_L2', 'AI_Reasoning', 'Model_Used']:
        if c not in df.columns: df[c] = None

    def needs_tagging(val):
        # We treat comma-separated values as "needs tagging" if we want a single value,
        # but here we assume if it's already filled, it's done. 
        # If your CSV currently has the full list in the Topic_L2 column, 
        # you might want to force re-tagging by checking if ',' is in val.
        s_val = str(val).lower().strip()
        return s_val in ["nan", "none", "", "unknown", "ai_missed_id"]

    # Select rows needing ANY tag
    mask_needs_work = (
        (df['Chapter'].apply(needs_tagging) | 
         df['Topic'].apply(needs_tagging) | 
         df['Topic_L2'].apply(needs_tagging)) & 
        (df['OCR_Text'].notna()) & 
        (df['OCR_Text'].astype(str).str.strip() != "")
    )
    
    pending_indices = df[mask_needs_work].index.tolist()
    print(f"👉 Found {len(pending_indices)} questions needing tagging.")

    # --- PROCESS BATCHES ---
    for i in range(0, len(pending_indices), BATCH_SIZE):
        batch_idx = pending_indices[i : i + BATCH_SIZE]
        print(f"\n📦 Processing Batch indices: {batch_idx}")
        
        # ====================================================
        # PHASE 1: FILL MISSING CHAPTERS
        # ====================================================
        missing_chapter_indices = [idx for idx in batch_idx if needs_tagging(df.at[idx, 'Chapter'])]
        
        if missing_chapter_indices:
            print(f"   🔹 Tagging Chapters for {len(missing_chapter_indices)} questions...")
            q_block = ""
            for idx in missing_chapter_indices:
                text = str(df.at[idx, 'OCR_Text']).replace("\n", " ")[:600]
                hint = str(df.at[idx, 'HintForAIChapterTagging']) if 'HintForAIChapterTagging' in df.columns else ""
                
                q_block += f"Q_ID_{idx}: {text}\n"
                if hint and hint.lower() not in ["nan", ""]:
                    q_block += f"   [IMPORTANT HINT: The chapter is likely '{hint}']\n"

            chap_menu_str = generate_menu(chapter_idx)
            
            sys_prompt = f"""
You are a JEE/NEET Physics Classifier.
Map questions to ONE Chapter ID from the list below.

[RULES]
1. Use the EXACT ID number from the list.
2. If a [HINT] is provided, give it extremely high priority.
3. OUTPUT JSON: {{ "Q_ID_x": {{ "chapter_id": 1, "reason": "..." }} }}

[CHAPTER LIST]
{chap_menu_str}
"""
            resp, model = call_ai_with_retry(sys_prompt, f"Questions:\n{q_block}")
            
            if resp:
                for idx in missing_chapter_indices:
                    key = f"Q_ID_{idx}"
                    if key in resp:
                        try:
                            cid = int(resp[key].get('chapter_id'))
                            if cid in chapter_idx:
                                df.at[idx, 'Chapter'] = chapter_idx[cid]
                                df.at[idx, 'AI_Reasoning'] = f"Ch: {resp[key].get('reason')}"
                                df.at[idx, 'Model_Used'] = model
                                print(f"      ✅ Q{idx} -> {chapter_idx[cid]}")
                        except: pass

        # ====================================================
        # PHASE 2: FILL MISSING TOPICS
        # ====================================================
        missing_topic_indices = [idx for idx in batch_idx if 
                                 not needs_tagging(df.at[idx, 'Chapter']) and 
                                 needs_tagging(df.at[idx, 'Topic'])]
        
        chapter_groups = {}
        for idx in missing_topic_indices:
            ch = df.at[idx, 'Chapter']
            if ch in topic_idx_map:
                chapter_groups.setdefault(ch, []).append(idx)

        for ch_name, q_indices in chapter_groups.items():
            topic_menu = topic_idx_map[ch_name]
            if not topic_menu: continue 

            print(f"   🔹 Tagging Topics for {len(q_indices)} questions in '{ch_name}'...")
            q_block = ""
            for idx in q_indices:
                text = str(df.at[idx, 'OCR_Text']).replace("\n", " ")[:400]
                q_block += f"Q_ID_{idx}: {text}\n"

            sys_prompt = f"""
Physics Expert. Chapter: '{ch_name}'.
Select best Topic ID.

[TOPICS]
{generate_menu(topic_menu)}

[OUTPUT]
JSON: {{ "Q_ID_x": {{ "topic_id": 1 }} }}
"""
            resp, _ = call_ai_with_retry(sys_prompt, f"Questions:\n{q_block}")
            
            if resp:
                for idx in q_indices:
                    key = f"Q_ID_{idx}"
                    if key in resp:
                        try:
                            tid = int(resp[key].get('topic_id'))
                            if tid in topic_menu:
                                df.at[idx, 'Topic'] = topic_menu[tid]
                                print(f"      ✅ Q{idx} -> {topic_menu[tid]}")
                        except: pass

        # ====================================================
        # PHASE 3: FILL MISSING TOPIC_L2 (SPLIT LOGIC APPLIED)
        # ====================================================
        missing_l2_indices = [idx for idx in batch_idx if 
                              not needs_tagging(df.at[idx, 'Topic']) and 
                              needs_tagging(df.at[idx, 'Topic_L2'])]

        topic_groups = {}
        for idx in missing_l2_indices:
            t_name = df.at[idx, 'Topic']
            if t_name in l2_idx_map and l2_idx_map[t_name]:
                topic_groups.setdefault(t_name, []).append(idx)
            else:
                df.at[idx, 'Topic_L2'] = "None" 

        for t_name, q_indices in topic_groups.items():
            l2_menu = l2_idx_map[t_name]
            print(f"   🔹 Tagging L2 for {len(q_indices)} questions in '{t_name}'...")
            
            q_block = ""
            for idx in q_indices:
                text = str(df.at[idx, 'OCR_Text']).replace("\n", " ")[:400]
                q_block += f"Q_ID_{idx}: {text}\n"

            sys_prompt = f"""
Topic: '{t_name}'.
Select the specific Sub-Topic (L2).

[SUB-TOPICS]
{generate_menu(l2_menu)}

[OUTPUT]
JSON: {{ "Q_ID_x": {{ "l2_id": 1 }} }}
"""
            resp, _ = call_ai_with_retry(sys_prompt, f"Questions:\n{q_block}")
            
            if resp:
                for idx in q_indices:
                    key = f"Q_ID_{idx}"
                    if key in resp:
                        try:
                            l2id = int(resp[key].get('l2_id'))
                            if l2id in l2_menu:
                                df.at[idx, 'Topic_L2'] = l2_menu[l2id]
                                print(f"      ✅ Q{idx} -> {l2_menu[l2id]}")
                        except: pass

        df.to_csv(target_csv, index=False)
        print("💾 Batch Saved.")

if __name__ == "__main__":
    run_hierarchical_tagger()