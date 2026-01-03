import streamlit as st
import pandas as pd
import numpy as np
import shutil
from pathlib import Path
from PIL import Image
from streamlit_cropper import st_cropper

# --- 1. CONFIGURATION ---
BASE_PATH = Path(r'D:/Main/3. Work - Teaching/Projects/Question extractor/')
DB_PATH = BASE_PATH / 'DB Master.csv'
METADATA_PATH = BASE_PATH / 'DB Metadata.xlsx'
IMG_DIR = BASE_PATH / 'Processed_Database'

st.set_page_config(page_title="Review & QC", layout="wide", initial_sidebar_state="expanded")

# --- 2. SESSION STATE ---
defaults = {
    'visible_count': 20,
    'shuffle_seed': 42,
    'toast_msg': None,
    'reset_target': None,
    'df_master': pd.DataFrame(),
    'taxonomy': {},
    # Filters
    'filter_QC_Status': 'All',
    'filter_Labelled by AI': 'All',
    'filter_Model_Used': 'All',
    'filter_AI_Tag_Accepted': 'All',
    'filter_Exam': 'All',
    'filter_Subject': 'All',
    'filter_Chapter': 'All'
}

for key, val in defaults.items():
    if key not in st.session_state:
        st.session_state[key] = val

if st.session_state['reset_target']:
    target_key = st.session_state['reset_target']
    st.session_state[target_key] = False
    st.session_state['reset_target'] = None

if st.session_state.get('toast_msg'):
    st.toast(st.session_state['toast_msg'], icon="✅")
    st.session_state['toast_msg'] = None

# --- 3. CSS ---
st.markdown("""
    <style>
    .stApp { background-color: #FAF9F6; }
    [data-testid="stVerticalBlock"] > [style*="flex-direction: column;"] > [data-testid="stVerticalBlock"] {
        background-color: white; border-radius: 12px; padding: 24px;
        box-shadow: 0 2px 8px rgba(0,0,0,0.06); margin-bottom: 24px; border: 1px solid #eee;
    }
    div[data-testid="stImage"] { overflow: hidden; border: 1px solid #ddd; border-radius: 4px; background-color: #fcfcfc; }
    canvas, img { max-width: 100% !important; display: block; }
    [data-testid="stColumn"]:first-child [data-testid="stSelectbox"] div[data-baseweb="select"] > div {
        border: 2px solid #000 !important; border-radius: 6px !important; background-color: #fff !important;
    }
    button[kind="primary"] { background-color: #111 !important; color: white !important; border: none; }
    </style>
    """, unsafe_allow_html=True)

# --- 4. DATA LOGIC ---
def load_data():
    if not DB_PATH.exists():
        st.error(f"❌ Database not found at: {DB_PATH}")
        st.stop()
    try:
        df = pd.read_csv(DB_PATH)
        df.columns = df.columns.str.strip()
        
        required_cols = [
            'Exam', 'Subject', 'Question type', 'Chapter', 'Topic', 'Topic_L2', 
            'Difficulty_tag', 'QC_Status', 'QC_Locked', 'Labelled by AI', 
            'Folder', 'Question No.', 'unique_id', 'AI_Tag_Accepted',
            'Model_Used', 'AI_Reasoning'
        ]
        
        for col in required_cols:
            if col not in df.columns:
                if col == 'Question No.' and 'Q' in df.columns:
                    df['Question No.'] = df['Q']
                else:
                    df[col] = None

        df['QC_Locked'] = pd.to_numeric(df['QC_Locked'], errors='coerce').fillna(0)
        return df
    except Exception as e:
        st.error(f"Error reading CSV: {e}")
        st.stop()

@st.cache_data
def load_taxonomy():
    if not METADATA_PATH.exists(): return {}
    try:
        meta_df = pd.read_excel(METADATA_PATH, sheet_name="Syllabus tree")
        meta_df = meta_df.map(lambda x: str(x).strip() if pd.notna(x) else "nan")
        taxonomy = {}
        for ch, group in meta_df.groupby('Chapter'):
            taxonomy[ch] = {}
            for top, sub_group in group.groupby('Topic'):
                if top.lower() not in ["nan", ch.lower()]:
                    l2s = [v for v in sub_group['Topic_L2'].unique() if v.lower() != "nan"]
                    cleaned_l2s = []
                    for item in l2s:
                        cleaned_l2s.extend([i.strip() for i in item.replace('[','').replace(']','').replace("'",'').split(',')])
                    taxonomy[ch][top] = sorted(list(set(cleaned_l2s)))
        return taxonomy
    except: return {}

def save_db():
    if st.session_state['df_master'].empty: return False
    try:
        df_to_save = st.session_state['df_master'].copy()
        cols_to_drop = ['q_image_path', 'sol_image_path']
        df_to_save = df_to_save.drop(columns=[c for c in cols_to_drop if c in df_to_save.columns])
        df_to_save.to_csv(DB_PATH, index=False)
        return True
    except PermissionError:
        st.error("❌ CSV file is open in Excel! Close it.")
        return False
    except Exception as e:
        st.error(f"❌ Save failed: {e}")
        return False

# --- 5. INITIALIZATION ---
if not st.session_state['taxonomy']:
    st.session_state['taxonomy'] = load_taxonomy()
if st.session_state['df_master'].empty:
    st.session_state['df_master'] = load_data()

# --- 6. HELPER: IMAGE PATHS ---
def get_image_path(row, prefix):
    try:
        folder = str(row.get('Folder', '')).strip()
        raw_num = row.get('Question No.')
        try: q_num = int(float(raw_num))
        except: q_num = raw_num
        fname = f"{prefix}_{q_num}.png"
        return str(IMG_DIR / folder / fname)
    except: return None

st.session_state['df_master']['q_image_path'] = st.session_state['df_master'].apply(lambda r: get_image_path(r, 'Q'), axis=1)
st.session_state['df_master']['sol_image_path'] = st.session_state['df_master'].apply(lambda r: get_image_path(r, 'Sol'), axis=1)

# --- 7. CALLBACKS ---
def update_qc_status(row_index):
    new_status = st.session_state[f"qc_{row_index}"]
    st.session_state['df_master'].at[row_index, 'QC_Status'] = new_status
    st.session_state['df_master'].at[row_index, 'QC_Locked'] = 1
    if save_db(): st.toast("Status Updated!", icon="💾")

def update_tag(row_index, col_name, key):
    new_value = st.session_state[key]
    st.session_state['df_master'].at[row_index, col_name] = new_value
    
    # [FIX] LOCK QC ROW ON EDIT
    st.session_state['df_master'].at[row_index, 'QC_Locked'] = 1

    # Get the ACTUAL unique_id for the toast
    real_uid = st.session_state['df_master'].at[row_index, 'unique_id']

    # Auto-Reject AI tag if human touches it
    if col_name in ['Chapter', 'Topic', 'Topic_L2']:
        st.session_state['df_master'].at[row_index, 'AI_Tag_Accepted'] = "Rejected"
        st.toast(f"✏️ Tag Updated (AI Rejected) for ID {real_uid}")
    
    # Or just confirm generic update
    elif col_name == 'AI_Tag_Accepted':
        st.toast(f"✅ AI Verification Updated for ID {real_uid}")
        
    save_db()
    st.rerun()

# --- 8. SIDEBAR ---
with st.sidebar:
    st.title("🎛️ Controls")
    enable_shuffle = st.checkbox("🔀 Randomize Order", value=False)
    if enable_shuffle:
        if st.button("🔄 Shuffle Again", use_container_width=True):
            st.session_state['shuffle_seed'] += 1
            st.rerun()
    
    st.divider()
    
    filter_cols = ['QC_Status', 'Labelled by AI', 'Model_Used', 'AI_Tag_Accepted', 'Exam', 'Subject', 'Chapter']
    
    if st.button("Reset Filters", icon="🗑️", use_container_width=True):
        for col in filter_cols: st.session_state[f"filter_{col}"] = "All"
        st.session_state['visible_count'] = 20
        st.rerun()
    
    df_view = st.session_state['df_master'].copy()
    for col in filter_cols:
        key = f"filter_{col}"
        if key not in st.session_state: st.session_state[key] = "All"
        
        unique_vals = sorted(df_view[col].astype(str).unique().tolist())
        options = ["All"] + unique_vals
        
        selected = st.selectbox(f"{col}", options, index=options.index(st.session_state[key]) if st.session_state[key] in options else 0, key=f"widget_{col}")
        st.session_state[key] = selected
        if selected != "All":
            df_view = df_view[df_view[col].astype(str) == str(selected)]

    if enable_shuffle:
        df_view = df_view.sample(frac=1, random_state=st.session_state['shuffle_seed'])

# --- 9. MAIN UI ---
col_head_1, col_head_2 = st.columns([4,1])
col_head_1.title("✅ Review & Quality Control")
total_filtered = len(df_view)
col_head_2.metric("Matches", total_filtered)

if df_view.empty:
    st.info("No questions match your filters.")
    st.stop()

QC_OPTS = ["Pass", "Fail", "Review Needed", "Pending QC", "Auto-Pass", "Auto-Fail"]
DIFF_OPTS = ["Easy", "Medium", "Difficult", "Unknown"]
AI_ACCEPT_OPTS = ["Yes", "No", "Rejected", "Unknown"] 

visible_count = st.session_state['visible_count']
df_display = df_view.head(visible_count)

for i, (idx, row) in enumerate(df_display.iterrows()):
    with st.container():
        c_left, c_right = st.columns([1.5, 1])
        
        # --- LEFT: IMAGES ---
        with c_left:
            h1, h2 = st.columns([1, 1.5])
            with h1:
                st.subheader(f"Q. {row.get('Question No.', '?')}")
                st.caption(f"ID: {row.get('unique_id', 'N/A')}")
            with h2:
                curr_status = str(row.get('QC_Status', 'Pending QC'))
                if curr_status not in QC_OPTS: QC_OPTS.append(curr_status)
                st.selectbox("👉 QC Status", options=QC_OPTS, index=QC_OPTS.index(curr_status), 
                             key=f"qc_{idx}", on_change=update_qc_status, args=(idx,), label_visibility="collapsed")
            st.markdown("---")
            
            # Question Image
            q_path = Path(row['q_image_path'])
            if q_path.exists():
                img_q = Image.open(q_path)
                toggle_key = f"crop_q_{idx}"
                do_crop_q = st.toggle("✂️ Crop Mode", key=toggle_key)
                if do_crop_q:
                    cropped_img_q = st_cropper(img_q, realtime_update=False, aspect_ratio=None, key=f"cropper_q_{idx}")
                    if st.button("💾 Save Crop", key=f"save_q_{idx}", type="primary", use_container_width=True):
                        try:
                            cropped_img_q.save(q_path)
                            st.session_state['toast_msg'] = "Saved!"
                            st.session_state['reset_target'] = toggle_key
                            st.rerun() 
                        except: pass
                else:
                    st.image(img_q, use_container_width=True)
            else:
                st.error(f"❌ Missing: {q_path.name}")

            # Solution Image
            with st.expander("View Solution"):
                sol_path = Path(row['sol_image_path'])
                if sol_path.exists():
                    img_sol = Image.open(sol_path)
                    st.image(img_sol, use_container_width=True)
                else:
                    st.warning("No solution image.")

        # --- RIGHT: METADATA & AI ---
        with c_right:
            st.markdown("##### 🏷️ Taxonomy")
            with st.container(border=True):
                all_chaps = sorted(list(st.session_state['taxonomy'].keys()))
                curr_chap = str(row['Chapter'])
                if curr_chap not in all_chaps: all_chaps.insert(0, curr_chap)
                st.selectbox("Chapter", all_chaps, index=all_chaps.index(curr_chap), key=f"ch_{idx}", on_change=update_tag, args=(idx, 'Chapter', f"ch_{idx}"))
                
                avail_topics = sorted(list(st.session_state['taxonomy'].get(curr_chap, {}).keys()))
                curr_topic = str(row['Topic'])
                if curr_topic not in avail_topics: avail_topics.insert(0, curr_topic)
                st.selectbox("Topic", avail_topics, index=avail_topics.index(curr_topic), key=f"top_{idx}", on_change=update_tag, args=(idx, 'Topic', f"top_{idx}"))
                
                avail_l2 = sorted(st.session_state['taxonomy'].get(curr_chap, {}).get(curr_topic, []))
                curr_l2 = str(row['Topic_L2'])
                if curr_l2 not in avail_l2: avail_l2.insert(0, curr_l2)
                st.selectbox("Sub-Topic", avail_l2, index=avail_l2.index(curr_l2), key=f"l2_{idx}", on_change=update_tag, args=(idx, 'Topic_L2', f"l2_{idx}"))

            # --- AI METADATA ---
            st.markdown("##### 🤖 AI Insights")
            with st.container(border=True):
                # Model Badge
                model_used = str(row.get('Model_Used', 'Unknown'))
                if model_used.lower() in ['nan', 'none', '']:
                    st.caption("No AI Model recorded.")
                else:
                    st.caption(f"**Tagged by:** `{model_used}`")

                # AI Acceptance
                curr_accept = str(row.get('AI_Tag_Accepted', 'Unknown'))
                if curr_accept not in AI_ACCEPT_OPTS: AI_ACCEPT_OPTS.append(curr_accept)
                
                st.selectbox("Accept AI Tag?", AI_ACCEPT_OPTS, index=AI_ACCEPT_OPTS.index(curr_accept), 
                             key=f"ai_acc_{idx}", on_change=update_tag, args=(idx, 'AI_Tag_Accepted', f"ai_acc_{idx}"))

            st.markdown("##### ⚙️ Status")
            with st.container(border=True):
                curr_diff = str(row['Difficulty_tag'])
                if curr_diff not in DIFF_OPTS: DIFF_OPTS.append(curr_diff)
                st.selectbox("Difficulty", DIFF_OPTS, index=DIFF_OPTS.index(curr_diff), key=f"diff_{idx}", on_change=update_tag, args=(idx, 'Difficulty_tag', f"diff_{idx}"))
                
                if row.get('QC_Locked', 0) == 1: st.caption("🔒 **Locked:** Manual review recorded.")

            st.info(f"**Source:** {row.get('Folder', 'Unknown')}")

    # --- CUSTOM THICK DIVIDER ---
    st.markdown("""<hr style="height:4px;border:none;color:#333;background-color:#333;" />""", unsafe_allow_html=True)

if visible_count < total_filtered:
    if st.button(f"🔽 Load More ({visible_count} / {total_filtered})", use_container_width=True):
        st.session_state['visible_count'] += 20
        st.rerun()
else:
    st.success("✅ End of list")