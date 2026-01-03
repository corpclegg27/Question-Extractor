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
BATCH_SIZE = 10  # Small batch size for reliability
VERBOSE = False  # <--- TOGGLE THIS TO FALSE TO HIDE PRINT STATEMENTS

MODEL_QUEUE = [

    "canopylabs/orpheus-arabic-saudi",
    
    "openai/gpt-oss-120b", # OK

    "openai/gpt-oss-safeguard-20b",

    "openai/gpt-oss-20b", # OK


    "meta-llama/llama-4-maverick-17b-128e-instruct", # OK


    "moonshotai/kimi-k2-instruct-0905",

    "llama-3.3-70b-versatile", # OK

    "meta-llama/llama-guard-4-12b", # Rate limit too low


    "meta-llama/llama-prompt-guard-2-22m",

    "qwen/qwen3-32b"
    "meta-llama/llama-4-scout-17b-16e-instruct", # Rubbish    
    "meta-llama/llama-prompt-guard-2-86m",
]

client = Groq(api_key=GROQ_API_KEY)
current_model_index = 0

# --- HELPER: CONDITIONAL PRINT ---
def log(msg):
    if VERBOSE:
        print(msg)

# --- 2. INDEX-BASED MAPPER ---
def load_indexed_syllabus(metadata_path):
    try:
        meta_df = pd.read_excel(metadata_path, sheet_name="Syllabus tree", engine='openpyxl')
        meta_df = meta_df.map(lambda x: str(x).strip() if pd.notna(x) else "nan")
        
        # 1. Build Chapter Index
        chapters = sorted([c for c in meta_df['Chapter'].unique() if c.lower() not in ["nan", "unknown"]])
        chapter_map = {i+1: name for i, name in enumerate(chapters)}
        
        # 2. Build Topic Index per Chapter
        topic_map = {}
        for ch in chapters:
            group = meta_df[meta_df['Chapter'] == ch]
            topics = sorted([t for t in group['Topic'].unique() if t.lower() not in ["nan", "miscellaneous"]])
            topic_map[ch] = {i+1: name for i, name in enumerate(topics)}
            
        return chapter_map, topic_map
    except Exception as e:
        print(f"❌ Error loading syllabus: {e}")
        return {}, {}

def generate_chapter_menu_with_topics(chapter_map, topic_map):
    lines = []
    for cid, cname in chapter_map.items():
        topics_dict = topic_map.get(cname, {})
        t_list = list(topics_dict.values())
        # Context: Show first 20 topics to help AI decide
        t_str = ", ".join(t_list[:20]) 
        lines.append(f"{cid}. {cname}\n   (Includes: {t_str})")
    return "\n".join(lines)

def generate_topic_menu(options_dict):
    return "\n".join([f"{k}. {v}" for k, v in options_dict.items()])

# --- 3. AI INTERACTION ---
def call_ai_with_retry(system_prompt, user_prompt):
    global current_model_index
    
    # Loop through models starting from the current index
    # We try as many times as there are models in the queue
    for _ in range(len(MODEL_QUEUE)):
        # If index goes out of bounds, reset (optional, or stop) - here we clamp to bounds
        if current_model_index >= len(MODEL_QUEUE):
            current_model_index = 0 

        model = MODEL_QUEUE[current_model_index]
        
        try:
            # --- DEBUG: FULL PROMPT LOGGING ---
            if VERBOSE:
                print(f"\n\n{'='*20} SENDING TO {model} {'='*20}")
                print(f"--- SYSTEM PROMPT ---\n{system_prompt}")
                print(f"--- USER PROMPT ---\n{user_prompt}")
                print("="*60)
            
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
            
            # --- DEBUG: FULL RESPONSE LOGGING ---
            if VERBOSE:
                print(f"--- RESPONSE RECEIVED ---\n{raw_resp}\n{'='*60}\n")
            
            return json.loads(raw_resp), model

        except Exception as e:
            err = str(e).lower()
            if "429" in err or "rate limit" in err:
                print(f"⚠️ Rate Limit on {model}. Switching to next model...")
            else:
                print(f"❌ Error on {model}: {e}. Switching to next model...")
            
            # Move to next model for the next iteration of the loop
            current_model_index += 1
            time.sleep(1) # Brief pause before retry

    print("❌ All models failed or exhausted.")
    return None, None

# --- 4. MAIN LOGIC ---
def run_index_tagger():
    target_csv = os.path.join(BASE_PATH, TARGET_FILENAME)
    
    print("1️⃣ Loading Syllabus Indices...")
    chapter_idx_map, topic_master_map = load_indexed_syllabus(os.path.join(BASE_PATH, METADATA_FILENAME))
    chapter_menu_str = generate_chapter_menu_with_topics(chapter_idx_map, topic_master_map)
    
    print("2️⃣ Loading Data...")
    if not os.path.exists(target_csv):
        print(f"❌ Error: {target_csv} does not exist.")
        return
        
    df = pd.read_csv(target_csv)
    
    for c in ['Chapter', 'Topic', 'AI_Reasoning', 'Model_Used']:
        if c not in df.columns: df[c] = None

    if 'OCR_Text' not in df.columns:
        print("❌ CRITICAL ERROR: 'OCR_Text' column missing.")
        return

    # Filter Valid Rows
    def is_bad(val): return str(val).lower().strip() in ["nan", "none", "", "unknown", "ai_missed_id"]
    
    pending_indices = []
    for idx, row in df.iterrows():
        if is_bad(row['Chapter']):
            # Verify OCR text is present
            if pd.notna(row['OCR_Text']) and str(row['OCR_Text']).lower() != 'nan' and str(row['OCR_Text']).strip() != "":
                pending_indices.append(idx)
    
    print(f"👉 Found {len(pending_indices)} valid questions to tag.")
    
    # --- BATCH LOOP ---
    for i in range(0, len(pending_indices), BATCH_SIZE):
        batch_idx = pending_indices[i : i + BATCH_SIZE]
        batch_df = df.loc[batch_idx]
        
        # --- STEP 1: IDENTIFY CHAPTERS ---
        q_block = ""
        for idx, row in batch_df.iterrows():
            text = str(row['OCR_Text']).replace("\n", " ") 
            q_block += f"Q_ID_{idx}: {text}\n"

        chap_system = f"""
You are a Physics Subject Matter Expert for JEE/NEET.
You are provided with a Reference Syllabus List below.

[CONSTRAINT: MUTUALLY EXCLUSIVE, COLLECTIVELY EXHAUSTIVE]
1. The list below is EXHAUSTIVE. Every single physics question belongs to exactly ONE Chapter ID from this list.
2. You CANNOT create new chapters. You CANNOT say "None" or "Other".
3. Force a selection based on the strongest conceptual overlap.

[CHAPTER LIST]
{chapter_menu_str}

[TASK]
1. Identify the Chapter ID for each question.
2. Provide short reasoning explaining the link to the topics in that chapter.
3. OUTPUT JSON ONLY:Example {{ "Q_ID_12": {{ "chapter_id": 5, "reasoning": "..." }} }}
"""
        chap_user = f"Questions:\n{q_block}"
        
        chap_resp, model = call_ai_with_retry(chap_system, chap_user)
        if not chap_resp: break

        # --- STEP 2: PROCESS & GROUP ---
        questions_by_chapter = {} 

        for idx in batch_idx:
            key = f"Q_ID_{idx}"
            if key in chap_resp:
                try:
                    cid = int(chap_resp[key].get('chapter_id'))
                    reason = chap_resp[key].get('reasoning', '')
                    
                    if cid in chapter_idx_map:
                        chapter_name = chapter_idx_map[cid]
                        df.at[idx, 'Chapter'] = chapter_name
                        df.at[idx, 'AI_Reasoning'] = reason
                        df.at[idx, 'Model_Used'] = model
                        
                        if chapter_name not in questions_by_chapter:
                            questions_by_chapter[chapter_name] = []
                        questions_by_chapter[chapter_name].append(idx)
                    else:
                        df.at[idx, 'AI_Reasoning'] = f"Invalid_ID: {cid}"
                except:
                    df.at[idx, 'AI_Reasoning'] = "Format_Error"

        # --- STEP 3: TOPIC DRILL-DOWN ---
        for ch_name, q_indices in questions_by_chapter.items():
            if ch_name not in topic_master_map or not topic_master_map[ch_name]:
                continue
                
            topic_menu = topic_master_map[ch_name]
            topic_menu_str = generate_topic_menu(topic_menu)
            
            sub_q_block = ""
            for idx in q_indices:
                text = str(df.at[idx, 'OCR_Text']).replace("\n", " ")
                sub_q_block += f"Q_ID_{idx}: {text}\n"
            
            topic_system = f"""
You are a Physics Expert.
The following questions have been mapped to Chapter: '{ch_name}'.

[CONSTRAINT: MUTUALLY EXCLUSIVE, COLLECTIVELY EXHAUSTIVE]
1. Below is the COMPLETE list of valid topics for this chapter.
2. You MUST select exactly ONE Topic ID from this list.
3. Do NOT invent topics. Do NOT use "General" or "Misc" unless it appears in the numbered list below.

[TOPIC LIST FOR '{ch_name}']
{topic_menu_str}

[TASK]
Select the Topic ID that best fits the question.
OUTPUT JSON ONLY:Example {{ "Q_ID_12": {{ "topic_id": 3 }} }}
"""
            topic_user = f"Questions:\n{sub_q_block}"
            
            topic_resp, _ = call_ai_with_retry(topic_system, topic_user)
            
            if topic_resp:
                for idx in q_indices:
                    key = f"Q_ID_{idx}"
                    if key in topic_resp:
                        try:
                            tid = int(topic_resp[key].get('topic_id'))
                            if tid in topic_menu:
                                df.at[idx, 'Topic'] = topic_menu[tid]
                            else:
                                df.at[idx, 'Topic'] = "Unknown_ID_Returned"
                        except:
                            pass

        df.to_csv(target_csv, index=False)
        print(f"✅ Batch Saved.")
        time.sleep(1)

if __name__ == "__main__":
    run_index_tagger()