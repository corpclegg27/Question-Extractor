import streamlit as st
import pandas as pd
import numpy as np
import os
import shutil
import datetime
import sys
from PIL import Image

# --- CONFIGURATION ---
BASE_PATH = 'D:/Main/3. Work - Teaching/Projects/Question extractor/'
DB_PATH = os.path.join(BASE_PATH, 'DB Master.xlsx')
METADATA_PATH = os.path.join(BASE_PATH, 'DB Metadata.xlsx')
BACKUP_DIR = os.path.join(BASE_PATH, 'Backups')
PROCESSED_DIR = os.path.join(BASE_PATH, 'Processed_Database')

st.set_page_config(page_title="Question Bank QC", layout="wide")

# --- HELPER: BACKUP & SAVE ---
def create_backup():
    os.makedirs(BACKUP_DIR, exist_ok=True)
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    backup_path = os.path.join(BACKUP_DIR, f"DB Master_BACKUP_{timestamp}.xlsx")
    try:
        shutil.copy2(DB_PATH, backup_path)
    except Exception: pass

def save_db():
    # Note: Writing to Excel is slow. For instant updates, this pause is unavoidable 
    # unless we switch to a faster DB (like SQLite) in the future.
    df_clean = st.session_state['df_master'].copy()
    cols_to_drop = ['q_image_path', 'sol_image_path']
    df_clean = df_clean.drop(columns=[c for c in cols_to_drop if c in df_clean.columns])
    
    try:
        df_clean.to_excel(DB_PATH, index=False)
        st.toast("✅ Saved!", icon="💾") 
    except PermissionError:
        st.error("❌ Excel file is open! Please close it to save.")
    except Exception as e:
        st.error(f"❌ Save failed: {e}")

# --- CALLBACKS ---
def update_qc_status(row_index):
    new_status = st.session_state[f"qc_{row_index}"]
    st.session_state['df_master'].at[row_index, 'QC_Status'] = new_status
    st.session_state['df_master'].at[row_index, 'QC_Locked'] = 1
    save_db()

def update_tag(row_index, col_name, key):
    new_value = st.session_state[key]
    st.session_state['df_master'].at[row_index, col_name] = new_value
    
    # --- LOGIC UPDATE: Auto-Accept AI Tag on Manual Edit ---
    # If a human manually corrects the Taxonomy, we assume the tag is now verified (Accepted = Yes)
    if col_name in ['Chapter', 'Topic', 'Topic_L2']:
        st.session_state['df_master'].at[row_index, 'AI_Tag_Accepted'] = "Yes"
        st.toast(f"🤖 Auto-updated 'AI Tag Accepted' to Yes for ID {row_index}")

    # Cascading Logic (Reset lower levels on change)
    if col_name == 'Chapter':
        st.session_state['df_master'].at[row_index, 'Topic'] = "Unknown"
        st.session_state['df_master'].at[row_index, 'Topic_L2'] = "Unknown"
    elif col_name == 'Topic':
        st.session_state['df_master'].at[row_index, 'Topic_L2'] = "Unknown"
        
    save_db()
    st.rerun()

# --- LOAD DATA ---
@st.cache_data
def load_taxonomy():
    if not os.path.exists(METADATA_PATH): return {}
    meta_df = pd.read_excel(METADATA_PATH, sheet_name="Syllabus tree")
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
    return taxonomy

if 'taxonomy' not in st.session_state:
    st.session_state['taxonomy'] = load_taxonomy()

if 'df_master' not in st.session_state:
    if os.path.exists(DB_PATH):
        df = pd.read_excel(DB_PATH)
        df.columns = df.columns.str.strip()
        
        # Ensure 'AI_Tag_Accepted' exists
        cols = ['Exam', 'Subject', 'Question type', 'Chapter', 'Topic', 'Topic_L2', 
                'Difficulty_tag', 'QC_Status', 'PYQ', 'Classroom_Illustration', 
                'Labelled by AI', 'Folder', 'Question No.', 'unique_id', 'AI_Tag_Accepted']
        
        for col in cols:
            if col not in df.columns: 
                if col == 'Question No.' and 'Q' in df.columns: df['Question No.'] = df['Q']
                else: df[col] = 'Unknown'
            else:
                if df[col].dtype == 'object':
                    df[col] = df[col].astype(str).str.strip().replace('nan', 'Unknown')
        
        if 'QC_Locked' not in df.columns: df['QC_Locked'] = 0
        st.session_state['df_master'] = df
    else:
        st.error(f"Database not found at {DB_PATH}"); st.stop()

# --- PAGINATION STATE ---
if 'visible_count' not in st.session_state:
    st.session_state['visible_count'] = 20

# --- PATH GENERATOR ---
def get_path(row, prefix):
    q_num = 0
    try:
        if pd.notna(row.get('Question No.')) and row.get('Question No.') != 'Unknown':
            q_num = int(float(row['Question No.']))
        elif pd.notna(row.get('Q')):
            q_num = int(float(row['Q']))
    except: pass
        
    folder = str(row.get('Folder', '')).strip()
    return os.path.join(PROCESSED_DIR, folder, f"{prefix}_{q_num}.png")

st.session_state['df_master']['q_image_path'] = st.session_state['df_master'].apply(lambda r: get_path(r, 'Q'), axis=1)
st.session_state['df_master']['sol_image_path'] = st.session_state['df_master'].apply(lambda r: get_path(r, 'Sol'), axis=1)

# --- FILTERS ---
filter_cols = ['QC_Status', 'Labelled by AI', 'AI_Tag_Accepted', 'Exam', 'Subject', 'Question type', 'Chapter', 'Difficulty_tag']
for col in filter_cols:
    if f"filter_{col}" not in st.session_state: st.session_state[f"filter_{col}"] = "All"

with st.sidebar:
    st.header("🔍 Filters")
    if st.button("Reset Filters"):
        for col in filter_cols: st.session_state[f"filter_{col}"] = "All"
        st.session_state['visible_count'] = 20 # Reset pagination
        st.rerun()
    
    df_view = st.session_state['df_master'].copy()
    for col in filter_cols:
        options = ["All"] + sorted(df_view[col].astype(str).unique().tolist())
        def format_func(x):
            if col == 'Labelled by AI':
                if x in ['1', '1.0', 'Yes', 'True']: return "Yes"
                if x in ['0', '0.0', 'No', 'False', 'Unknown', 'nan']: return "No"
            return str(x)

        current_val = st.session_state[f"filter_{col}"]
        if current_val not in options: current_val = "All"
        
        selected = st.selectbox(f"{col}", options, index=options.index(current_val), key=f"widget_{col}", format_func=format_func)
        st.session_state[f"filter_{col}"] = selected
        
        if selected != "All":
            df_view = df_view[df_view[col].astype(str) == str(selected)]

# --- MAIN UI ---
st.title("✅ Review & Quality Control")
col1, col2 = st.columns([1, 6])
total_filtered = len(df_view)
col1.metric("Count", total_filtered)

if df_view.empty:
    st.warning("No questions match your filters.")
    st.stop()

QC_OPTS = ["Pass", "Fail", "Review Needed"]
DIFF_OPTS = ["Easy", "Medium", "Difficult", "Unknown"]
AI_ACCEPT_OPTS = ["Yes", "No", "Rejected", "Unknown"] 
taxonomy = st.session_state['taxonomy']

# --- PAGINATION LOGIC ---
visible_count = st.session_state['visible_count']
df_display = df_view.head(visible_count)

for i, (idx, row) in enumerate(df_display.iterrows()):
    with st.container():
        c1, c2, c3 = st.columns([0.8, 3.5, 1.5]) 
        
        is_locked = (row.get('QC_Locked', 0) == 1)
        lock_icon = "🔒 " if is_locked else ""
        ai_label = str(row.get('Labelled by AI', '')).lower()
        ai_badge = "🤖" if ai_label in ['yes', 'true', '1'] else ""
        q_num = int(float(row.get('Question No.', 0))) if row.get('Question No.') != 'Unknown' else 0
        
        unique_id = row.get('unique_id', 'N/A')
        c1.markdown(f"## {q_num}")
        c1.markdown(f"<span style='color:grey; font-size:0.8em'>ID: {unique_id}</span>", unsafe_allow_html=True)
        
        c2.markdown(f"**{lock_icon} {ai_badge} {row.get('Chapter', '')}**")
        
        curr_status = str(row.get('QC_Status', 'Unknown'))
        if curr_status not in QC_OPTS: QC_OPTS.append(curr_status)
        c3.selectbox("Status", options=QC_OPTS, index=QC_OPTS.index(curr_status), key=f"qc_{idx}", on_change=update_qc_status, args=(idx,), label_visibility="collapsed")
        
        img_col, data_col = st.columns([2, 1])
        with img_col:
            if os.path.exists(row['q_image_path']):
                st.image(Image.open(row['q_image_path']), use_container_width=True)
            else: st.error(f"Image not found: `{row['q_image_path']}`")
            
            with st.expander("View Solution"):
                if os.path.exists(row['sol_image_path']): st.image(Image.open(row['sol_image_path']), use_container_width=True)
                else: st.warning("No solution image.")

        with data_col:
            st.caption("Taxonomy Editor")
            
            # --- AI ACCEPTANCE DROPDOWN (Renamed) ---
            curr_accept = str(row.get('AI_Tag_Accepted', 'Unknown'))
            if curr_accept not in AI_ACCEPT_OPTS: AI_ACCEPT_OPTS.append(curr_accept)
            st.selectbox("AI Tag Accepted?", AI_ACCEPT_OPTS, index=AI_ACCEPT_OPTS.index(curr_accept), 
                         key=f"ai_acc_{idx}", 
                         on_change=update_tag, args=(idx, 'AI_Tag_Accepted', f"ai_acc_{idx}"))
            # ------------------------------

            # 1. Chapter
            all_chaps = sorted(list(taxonomy.keys()))
            curr_chap = str(row['Chapter'])
            if curr_chap not in all_chaps: all_chaps.insert(0, curr_chap)
            st.selectbox("Chapter", all_chaps, index=all_chaps.index(curr_chap), key=f"ch_{idx}", on_change=update_tag, args=(idx, 'Chapter', f"ch_{idx}"))
            
            # 2. Topic
            avail_topics = sorted(list(taxonomy.get(curr_chap, {}).keys()))
            curr_topic = str(row['Topic'])
            if curr_topic not in avail_topics: avail_topics.insert(0, curr_topic)
            st.selectbox("Topic", avail_topics, index=avail_topics.index(curr_topic), key=f"top_{idx}", on_change=update_tag, args=(idx, 'Topic', f"top_{idx}"))
            
            # 3. L2
            avail_l2 = sorted(taxonomy.get(curr_chap, {}).get(curr_topic, []))
            curr_l2 = str(row['Topic_L2'])
            if curr_l2 not in avail_l2: avail_l2.insert(0, curr_l2)
            st.selectbox("Sub-Topic", avail_l2, index=avail_l2.index(curr_l2), key=f"l2_{idx}", on_change=update_tag, args=(idx, 'Topic_L2', f"l2_{idx}"))
            
            # 4. Difficulty
            curr_diff = str(row['Difficulty_tag'])
            if curr_diff not in DIFF_OPTS: DIFF_OPTS.append(curr_diff)
            st.selectbox("Difficulty", DIFF_OPTS, index=DIFF_OPTS.index(curr_diff), key=f"diff_{idx}", on_change=update_tag, args=(idx, 'Difficulty_tag', f"diff_{idx}"))

    st.divider()

# --- LOAD MORE BUTTON ---
if visible_count < total_filtered:
    if st.button(f"Load More Questions ({visible_count} / {total_filtered} shown)"):
        st.session_state['visible_count'] += 20
        st.rerun()
else:
    st.success("All questions loaded.")