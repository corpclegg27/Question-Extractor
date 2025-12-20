import streamlit as st
import pandas as pd
import numpy as np  # Added for safe type conversion
import os
import shutil
import datetime
import sys
from PIL import Image

# --- CONFIGURATION ---
BASE_PATH = 'D:/Main/3. Work - Teaching/Projects/Question extractor/'
DB_PATH = os.path.join(BASE_PATH, 'DB Master.xlsx')
BACKUP_DIR = os.path.join(BASE_PATH, 'Backups')
PROCESSED_DIR = os.path.join(BASE_PATH, 'Processed_Database')

# --- DETECT DEBUG MODE ---
IS_DEBUG = "--debug" in sys.argv

st.set_page_config(page_title="Question Bank QC", layout="wide")

# --- HELPER: BACKUP & SAVE ---
def create_backup():
    """Creates a timestamped backup before saving."""
    os.makedirs(BACKUP_DIR, exist_ok=True)
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    backup_path = os.path.join(BACKUP_DIR, f"DB Master_BACKUP_{timestamp}.xlsx")
    try:
        shutil.copy2(DB_PATH, backup_path)
        # Keep last 5 backups
        backups = sorted([os.path.join(BACKUP_DIR, f) for f in os.listdir(BACKUP_DIR) if f.startswith("DB Master_BACKUP")])
        if len(backups) > 5:
            for old in backups[:-5]:
                try: os.remove(old)
                except: pass
    except Exception: pass

def save_db(df_to_save):
    """Writes the dataframe back to Excel."""
    create_backup()

    df_clean = df_to_save.copy()
    # Drop image path columns (they are generated dynamically)
    cols_to_drop = ['q_image_path', 'sol_image_path']
    df_clean = df_clean.drop(columns=[c for c in cols_to_drop if c in df_clean.columns])
    
    try:
        df_clean.to_excel(DB_PATH, index=False)
        st.toast("✅ Saved & Locked!", icon="🔒") 
    except PermissionError:
        st.error("❌ Excel file is open! Please close it to save.")
    except Exception as e:
        st.error(f"❌ Save failed: {e}")

# --- CALLBACK: UPDATE QC ---
def update_qc_status(row_index):
    """Callback to update session state, LOCK the row (Set to 1), and save."""
    # 1. Get the new value from the widget
    new_status = st.session_state[f"qc_{row_index}"]
    
    # 2. Update Status in DataFrame
    st.session_state['df_master'].at[row_index, 'QC_Status'] = new_status
    
    # 3. FORCE LOCK (Set to integer 1)
    # This ensures AutoQC knows a human touched it.
    st.session_state['df_master'].at[row_index, 'QC_Locked'] = 1
    
    # 4. Save immediately
    save_db(st.session_state['df_master'])

# --- LOAD DATA ---
if 'df_master' not in st.session_state:
    if os.path.exists(DB_PATH):
        df = pd.read_excel(DB_PATH)
        df.columns = df.columns.str.strip()
        
        # --- UPDATED: Ensure Standard Columns (Added new filter fields) ---
        cols = [
            'Exam', 'Subject', 'Question type', 'Chapter', 'Topic', 'Topic_L2', 
            'Difficulty_tag', 'QC_Status', 
            'PYQ', 'Classroom_Illustration', 'manually updated' # Added here
        ]
        
        for col in cols:
            if col not in df.columns: 
                df[col] = 'Unknown'
            else: 
                # Convert to string but keep 'manually updated' distinct if needed later
                # For filter UI consistency, we treat them as strings ('nan' -> 'Unknown')
                df[col] = df[col].astype(str).str.strip().replace('nan', 'Unknown')
        
        # --- FIX: ROBUST 0/1 INITIALIZATION ---
        if 'QC_Locked' not in df.columns:
            df['QC_Locked'] = 0
        
        # 1. Replace any old Booleans with Integers
        df['QC_Locked'] = df['QC_Locked'].replace({True: 1, False: 0, 'True': 1, 'False': 0})
        # 2. Convert to Numeric (coercing errors to NaN)
        df['QC_Locked'] = pd.to_numeric(df['QC_Locked'], errors='coerce')
        # 3. Fill NaNs with 0 and cast to Integer
        df['QC_Locked'] = df['QC_Locked'].fillna(0).astype(int)

        if 'QC_Status' not in df.columns: df['QC_Status'] = 'Pass'
        
        st.session_state['df_master'] = df
    else:
        st.error("Database not found."); st.stop()

# Alias for easier access
df_master = st.session_state['df_master']

# Dynamic Paths
def get_path(row, prefix):
    # Safe conversion to int for filename
    try:
        q_num = int(row.get('Question No.', 0))
    except:
        q_num = 0
    return os.path.join(PROCESSED_DIR, str(row['Folder']), f"{prefix}_{q_num}.png")

df_master['q_image_path'] = df_master.apply(lambda r: get_path(r, 'Q'), axis=1)
df_master['sol_image_path'] = df_master.apply(lambda r: get_path(r, 'Sol'), axis=1)

# --- SIDEBAR FILTERS ---
with st.sidebar:
    st.header("🔍 Filters")
    if IS_DEBUG:
        st.caption("🛠️ **DEBUG MODE**")
    
    if st.button("Reset Filters"):
        for key in list(st.session_state.keys()):
            if key.startswith("filter_"): del st.session_state[key]
        st.rerun()

# --- UPDATED FILTER ORDER ---
filter_order = [
    'QC_Status', 'Exam', 'Subject', 'Question type', 'Chapter', 
    'Difficulty_tag', 
    'PYQ', 'Classroom_Illustration', 'manually updated' # New filters added
]
df_view = df_master.copy()
selected_filters = {}

# --- HELPER: FORMAT LABELS ---
def get_label(option, counts_dict):
    # Optional: Make 'manually updated' look cleaner (1 -> Yes, 0/Unknown -> No/Unknown)
    label = str(option)
    if label == '1' or label == '1.0': label = "Yes"
    elif label == '0' or label == '0.0': label = "No"
    
    if option == 'All': return f"All ({sum(counts_dict.values())})"
    if IS_DEBUG: return str(option)
    return f"{label} ({counts_dict.get(option, 0)})"

for col in filter_order:
    # Get counts but handle potential missing columns safely
    if col in df_view.columns:
        counts = df_view[col].value_counts().to_dict()
        options = sorted(list(counts.keys()))
        val = st.sidebar.selectbox(col, ['All'] + options, format_func=lambda x: get_label(x, counts), key=f"filter_{col}")
        if val != 'All':
            df_view = df_view[df_view[col] == val]
            selected_filters[col] = val

# --- MAIN AREA ---
c1, c2 = st.columns([6, 2])
c1.metric("Questions Found", len(df_view))
if selected_filters: c2.caption("Active: " + ", ".join([f"{k}={v}" for k,v in selected_filters.items()]))
st.divider()

if df_view.empty: st.warning("No questions match."); st.stop()

# --- QUESTION FEED ---
MAX_DISPLAY = 50
QC_OPTS = ["Pass", "Fail", "Review Needed"]

# Note: We iterate over df_view, but we need the original index 'idx' to update the master DF
for i, (idx, row) in enumerate(df_view.head(MAX_DISPLAY).iterrows()):
    c1, c2 = st.columns([3, 1])
    tags = [row[c] for c in ['Exam', 'Chapter', 'Difficulty_tag'] if row[c] != 'Unknown']
    
    # Visual indicator if locked (Check for 1)
    is_locked = (row.get('QC_Locked', 0) == 1)
    lock_icon = "🔒 " if is_locked else ""
    
    c1.markdown(f"#### {lock_icon}Q{int(row.get('Question No.', 0))} : {' | '.join(tags)}")
    
    curr = row['QC_Status']
    # Handle cases where curr is NaN or not in options
    if pd.isna(curr) or curr == 'nan': curr = 'Pass' 
    if curr not in QC_OPTS: QC_OPTS.append(str(curr))
    
    c2.selectbox(
        "QC", options=QC_OPTS, 
        index=QC_OPTS.index(curr),
        key=f"qc_{idx}",          # Unique key based on original index
        on_change=update_qc_status, 
        args=(idx,),              # Pass original index to callback
        label_visibility="collapsed"
    )

    if os.path.exists(row['q_image_path']): st.image(Image.open(row['q_image_path']))
    else: st.error(f"Image missing: {row['q_image_path']}")
    
    with st.expander("Solution"):
        if os.path.exists(row['sol_image_path']): st.image(Image.open(row['sol_image_path']))
        else: st.info("No solution image found.")
    st.divider()

if len(df_view) > MAX_DISPLAY: st.info(f"Showing first {MAX_DISPLAY} questions.")