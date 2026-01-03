import streamlit as st
import pandas as pd
import numpy as np
from pathlib import Path
from PIL import Image
from streamlit_cropper import st_cropper

# --- 1. CONFIGURATION ---
BASE_PATH = Path(r'D:/Main/3. Work - Teaching/Projects/Question extractor/')
DB_PATH = BASE_PATH / 'DB Master.csv'
AI_TAG_PATH = BASE_PATH / 'questionToTagUsingAITagged.csv'
METADATA_PATH = BASE_PATH / 'DB Metadata.xlsx'
IMG_DIR = BASE_PATH / 'Processed_Database'

st.set_page_config(page_title="Review & QC", layout="wide", initial_sidebar_state="expanded")

# --- 2. SESSION STATE & CSS ---
defaults = {
    'visible_count': 20,
    'shuffle_seed': 42,
    'toast_msg': None,
    'reset_target': None,
    'df_master': pd.DataFrame(),
    'df_ai': pd.DataFrame(), # New DF for AI Tags
    'taxonomy': {},
    'ai_review_batch': [], # Stores unique_ids of the current AI review batch
    'show_ai_results': False, # Toggle for the results page
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
    if target_key in st.session_state:
        st.session_state[target_key] = False
    st.session_state['reset_target'] = None

if st.session_state.get('toast_msg'):
    st.toast(st.session_state['toast_msg'], icon="✅")
    st.session_state['toast_msg'] = None

st.markdown("""
    <style>
    .stApp { background-color: #FAF9F6; }
    [data-testid="stVerticalBlock"] > [style*="flex-direction: column;"] > [data-testid="stVerticalBlock"] {
        background-color: white; border-radius: 12px; padding: 24px;
        box-shadow: 0 2px 8px rgba(0,0,0,0.06); margin-bottom: 24px; border: 1px solid #eee;
    }
    div[data-testid="stImage"] { overflow: hidden; border: 1px solid #ddd; border-radius: 4px; background-color: #fcfcfc; }
    canvas, img { max-width: 100% !important; display: block; }
    button[kind="primary"] { background-color: #111 !important; color: white !important; border: none; }
    </style>
    """, unsafe_allow_html=True)

# --- 3. DATA LOGIC ---
def load_csv_generic(path):
    if not path.exists():
        # If AI file doesn't exist yet, return empty DF without stopping app
        if path == AI_TAG_PATH:
            return pd.DataFrame()
        st.error(f"❌ File not found at: {path}")
        return pd.DataFrame()
    try:
        df = pd.read_csv(path)
        df.columns = df.columns.str.strip()
        
        # Ensure ID column exists or create generic one
        if 'unique_id' not in df.columns:
            df['unique_id'] = range(1, len(df) + 1)
        
        # Normalize Question No.
        if 'Question No.' not in df.columns and 'Q' in df.columns:
            df['Question No.'] = df['Q']
            
        return df
    except Exception as e:
        st.error(f"Error reading CSV {path}: {e}")
        return pd.DataFrame()

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

def save_db(df, path):
    if df.empty: return False
    try:
        df_to_save = df.copy()
        cols_to_drop = ['q_image_path', 'sol_image_path']
        df_to_save = df_to_save.drop(columns=[c for c in cols_to_drop if c in df_to_save.columns])
        df_to_save.to_csv(path, index=False)
        return True
    except PermissionError:
        st.error(f"❌ {path.name} is open in Excel! Close it.")
        return False
    except Exception as e:
        st.error(f"❌ Save failed: {e}")
        return False

# --- 4. INITIALIZATION ---
if not st.session_state['taxonomy']:
    st.session_state['taxonomy'] = load_taxonomy()
if st.session_state['df_master'].empty:
    st.session_state['df_master'] = load_csv_generic(DB_PATH)
if st.session_state['df_ai'].empty:
    st.session_state['df_ai'] = load_csv_generic(AI_TAG_PATH)

# --- 5. HELPER: IMAGE PATHS ---
def get_image_path(row, prefix):
    try:
        folder = str(row.get('Folder', '')).strip()
        raw_num = row.get('Question No.')
        try: q_num = int(float(raw_num))
        except: q_num = raw_num
        fname = f"{prefix}_{q_num}.png"
        return str(IMG_DIR / folder / fname)
    except: return None

# Apply paths to both DFs
for df_key in ['df_master', 'df_ai']:
    if not st.session_state[df_key].empty:
        st.session_state[df_key]['q_image_path'] = st.session_state[df_key].apply(lambda r: get_image_path(r, 'Q'), axis=1)
        st.session_state[df_key]['sol_image_path'] = st.session_state[df_key].apply(lambda r: get_image_path(r, 'Sol'), axis=1)

# --- 6. CALLBACKS ---
def update_row_generic(row_index, col_name, key, df_key, path):
    """Generic updater that works for both DBs"""
    new_value = st.session_state[key]
    st.session_state[df_key].at[row_index, col_name] = new_value
    
    if 'QC_Locked' in st.session_state[df_key].columns:
        st.session_state[df_key].at[row_index, 'QC_Locked'] = 1

    real_uid = st.session_state[df_key].at[row_index, 'unique_id']

    # Auto-Reject AI logic (only if changing taxonomy)
    if col_name in ['Chapter', 'Topic', 'Topic_L2']:
        st.session_state[df_key].at[row_index, 'AI_Tag_Accepted'] = "Rejected"
        st.toast(f"✏️ Updated & AI Rejected (ID: {real_uid})")
    else:
        st.toast(f"✅ Saved (ID: {real_uid})")
        
    save_db(st.session_state[df_key], path)

# --- SHARED: ROW RENDERER (Full Functionality) ---
def render_question_rows(df_to_show, df_key, save_path):
    QC_OPTS = ["Pass", "Fail", "Review Needed", "Pending QC", "Auto-Pass", "Auto-Fail"]
    DIFF_OPTS = ["Easy", "Medium", "Difficult", "Unknown"]
    AI_ACCEPT_OPTS = ["Yes", "No", "Rejected", "Unknown"] 

    for i, row in df_to_show.iterrows():
        # Get the index in the MASTER dataframe to ensure updates stick
        real_idx = st.session_state[df_key].index[st.session_state[df_key]['unique_id'] == row['unique_id']].tolist()
        if not real_idx: continue
        idx = real_idx[0] 

        with st.container():
            c_left, c_right = st.columns([1.5, 1])
            
            # --- LEFT: IMAGES & CROP ---
            with c_left:
                h1, h2 = st.columns([1, 1.5])
                with h1:
                    st.subheader(f"Q. {row.get('Question No.', '?')}")
                    st.caption(f"ID: {row.get('unique_id', 'N/A')}")
                with h2:
                    curr_status = str(row.get('QC_Status', 'Pending QC'))
                    if curr_status not in QC_OPTS: QC_OPTS.append(curr_status)
                    st.selectbox("👉 QC Status", options=QC_OPTS, index=QC_OPTS.index(curr_status), 
                                 key=f"qc_{df_key}_{idx}", 
                                 on_change=update_row_generic, args=(idx, 'QC_Status', f"qc_{df_key}_{idx}", df_key, save_path), 
                                 label_visibility="collapsed")
                st.markdown("---")
                
                # Question Image with CROP Logic
                q_path_str = row.get('q_image_path')
                q_path = Path(q_path_str) if q_path_str else None
                
                if q_path and q_path.exists():
                    img_q = Image.open(q_path)
                    
                    toggle_key = f"crop_q_{df_key}_{idx}"
                    do_crop_q = st.toggle("✂️ Crop Mode", key=toggle_key)
                    
                    if do_crop_q:
                        cropped_img_q = st_cropper(img_q, realtime_update=False, aspect_ratio=None, key=f"cropper_q_{df_key}_{idx}")
                        if st.button("💾 Save Crop", key=f"save_q_{df_key}_{idx}", type="primary", use_container_width=True):
                            try:
                                cropped_img_q.save(q_path)
                                st.session_state['toast_msg'] = "Saved!"
                                st.session_state['reset_target'] = toggle_key
                                st.rerun() 
                            except Exception as e:
                                st.error(f"Error saving: {e}")
                    else:
                        st.image(img_q, use_container_width=True)
                else:
                    st.error(f"❌ Missing Image: {row.get('Folder','')}")

                # Solution Image
                with st.expander("View Solution"):
                    sol_path_str = row.get('sol_image_path')
                    sol_path = Path(sol_path_str) if sol_path_str else None
                    if sol_path and sol_path.exists():
                        img_sol = Image.open(sol_path)
                        st.image(img_sol, use_container_width=True)
                    else:
                        st.warning("No solution image.")

            # --- RIGHT: METADATA & TAXONOMY ---
            with c_right:
                st.markdown("##### 🏷️ Taxonomy")
                with st.container(border=True):
                    # 1. CHAPTER
                    all_chaps = sorted(list(st.session_state['taxonomy'].keys()))
                    curr_chap = str(row.get('Chapter', ''))
                    if curr_chap not in all_chaps: all_chaps.insert(0, curr_chap)
                    
                    st.selectbox("Chapter", all_chaps, index=all_chaps.index(curr_chap), 
                                 key=f"ch_{df_key}_{idx}", 
                                 on_change=update_row_generic, args=(idx, 'Chapter', f"ch_{df_key}_{idx}", df_key, save_path))
                    
                    # 2. TOPIC (Dependent on Chapter)
                    avail_topics = sorted(list(st.session_state['taxonomy'].get(curr_chap, {}).keys()))
                    curr_topic = str(row.get('Topic', ''))
                    if curr_topic not in avail_topics: avail_topics.insert(0, curr_topic)

                    st.selectbox("Topic", avail_topics, index=avail_topics.index(curr_topic),
                                 key=f"top_{df_key}_{idx}",
                                 on_change=update_row_generic, args=(idx, 'Topic', f"top_{df_key}_{idx}", df_key, save_path))

                    # 3. SUB-TOPIC / L2 (Dependent on Topic)
                    avail_l2 = sorted(st.session_state['taxonomy'].get(curr_chap, {}).get(curr_topic, []))
                    curr_l2 = str(row.get('Topic_L2', ''))
                    if curr_l2 not in avail_l2: avail_l2.insert(0, curr_l2)

                    st.selectbox("Sub-Topic", avail_l2, index=avail_l2.index(curr_l2),
                                 key=f"l2_{df_key}_{idx}",
                                 on_change=update_row_generic, args=(idx, 'Topic_L2', f"l2_{df_key}_{idx}", df_key, save_path))

                st.markdown("##### 🤖 AI Insights")
                with st.container(border=True):
                    model_used = str(row.get('Model_Used', 'Unknown'))
                    st.caption(f"**Tagged by:** `{model_used}`")

                    if pd.notna(row.get('AI_Reasoning', '')):
                         with st.popover("See AI Reasoning"):
                             st.write(row['AI_Reasoning'])

                    curr_accept = str(row.get('AI_Tag_Accepted', 'Unknown'))
                    if curr_accept not in AI_ACCEPT_OPTS: AI_ACCEPT_OPTS.append(curr_accept)
                    
                    st.selectbox("Accept AI Tag?", AI_ACCEPT_OPTS, index=AI_ACCEPT_OPTS.index(curr_accept), 
                                 key=f"ai_acc_{df_key}_{idx}", 
                                 on_change=update_row_generic, args=(idx, 'AI_Tag_Accepted', f"ai_acc_{df_key}_{idx}", df_key, save_path))
                
                # Difficulty Tag
                curr_diff = str(row.get('Difficulty_tag', 'Unknown'))
                if curr_diff not in DIFF_OPTS: DIFF_OPTS.append(curr_diff)
                st.selectbox("Difficulty", DIFF_OPTS, index=DIFF_OPTS.index(curr_diff), 
                             key=f"diff_{df_key}_{idx}",
                             on_change=update_row_generic, args=(idx, 'Difficulty_tag', f"diff_{df_key}_{idx}", df_key, save_path))

                st.markdown("""<hr style="height:4px;border:none;color:#333;background-color:#333;" />""", unsafe_allow_html=True)

# --- PAGE: STANDARD QC ---
def render_standard_qc():
    with st.sidebar:
        st.divider()
        st.subheader("🔍 Filters")
        
        filter_cols = ['QC_Status', 'Labelled by AI', 'Model_Used', 'AI_Tag_Accepted', 'Exam', 'Subject', 'Chapter']
        
        if st.button("Reset Filters", icon="🗑️", use_container_width=True):
            for col in filter_cols: st.session_state[f"filter_{col}"] = "All"
            st.session_state['visible_count'] = 20
            st.rerun()
        
        df_view = st.session_state['df_master'].copy()
        for col in filter_cols:
            if col not in df_view.columns: continue
            key = f"filter_{col}"
            if key not in st.session_state: st.session_state[key] = "All"

            unique_vals = sorted(df_view[col].astype(str).unique().tolist())
            options = ["All"] + unique_vals
            
            selected = st.selectbox(f"{col}", options, index=options.index(st.session_state[key]) if st.session_state[key] in options else 0, key=f"widget_{col}")
            st.session_state[key] = selected
            if selected != "All":
                df_view = df_view[df_view[col].astype(str) == str(selected)]
        
        enable_shuffle = st.checkbox("🔀 Randomize Order", value=False)
        if enable_shuffle:
            df_view = df_view.sample(frac=1, random_state=st.session_state['shuffle_seed'])
            if st.button("🔄 Shuffle Again", use_container_width=True):
                st.session_state['shuffle_seed'] += 1
                st.rerun()

    # Display Logic
    st.title("✅ Review & Quality Control")
    st.caption("Standard Database Review")
    
    if df_view.empty:
        st.info("No questions match your filters.")
        return

    visible_count = st.session_state['visible_count']
    df_display = df_view.head(visible_count)
    
    # Render Rows
    render_question_rows(df_display, 'df_master', DB_PATH)

    if visible_count < len(df_view):
        if st.button(f"🔽 Load More ({visible_count} / {len(df_view)})", use_container_width=True):
            st.session_state['visible_count'] += 20
            st.rerun()

# --- PAGE: REVIEW AI TAGS ---
def render_ai_tags_page():
    st.title("🤖 Review AI Tags")
    
    if st.session_state['show_ai_results']:
        render_ai_results()
        return

    # 1. Inputs
    col_input, col_act = st.columns([1, 3])
    with col_input:
        samples_per_model = st.number_input("Samples per Model", min_value=1, value=5)
    with col_act:
        st.write("") # Spacer
        if st.button("🎲 Generate New Batch", type="primary"):
            generate_ai_batch(samples_per_model)
            st.rerun()

    # 2. Get Batch Data
    df_full = st.session_state['df_ai']
    batch_ids = st.session_state['ai_review_batch']
    
    if not batch_ids:
        st.info("👈 Click 'Generate New Batch' to start reviewing.")
        return

    # Filter DF by batch IDs (preserve order if possible)
    df_batch = df_full[df_full['unique_id'].isin(batch_ids)].copy()
    
    if df_batch.empty:
        st.warning("Batch is empty. Try generating again.")
        return

    # 3. Render Batch
    st.markdown(f"### Reviewing {len(df_batch)} Questions")
    render_question_rows(df_batch, 'df_ai', AI_TAG_PATH)

    # 4. Verify Button
    st.divider()
    if st.button("✅ AI Tags Verified, See Results", type="primary", use_container_width=True):
        st.session_state['show_ai_results'] = True
        st.rerun()

def generate_ai_batch(n_samples):
    df = st.session_state['df_ai']
    if df.empty:
        st.error("AI Database is empty!")
        return

    if 'Model_Used' not in df.columns or 'AI_Tag_Accepted' not in df.columns:
        st.error("Missing columns: 'Model_Used' or 'AI_Tag_Accepted'")
        return

    # Filter: Not Accepted yet (No, Unknown, NaN)
    mask = df['AI_Tag_Accepted'].fillna('Unknown').isin(['No', 'Unknown', 'nan'])
    candidates = df[mask]
    
    if candidates.empty:
        st.warning("🎉 No pending AI tags found!")
        st.session_state['ai_review_batch'] = []
        return

    selected_ids = []
    
    # Group by Model and Sample
    models = candidates['Model_Used'].unique()
    for model in models:
        model_group = candidates[candidates['Model_Used'] == model]
        if len(model_group) > n_samples:
            sampled = model_group.sample(n=n_samples)
        else:
            sampled = model_group
        selected_ids.extend(sampled['unique_id'].tolist())
    
    st.session_state['ai_review_batch'] = selected_ids
    st.toast(f"Generated batch with {len(selected_ids)} questions across {len(models)} models.")

def render_ai_results():
    st.button("🔙 Back to Review", on_click=lambda: st.session_state.update({'show_ai_results': False}))
    st.subheader("📊 AI Model Performance Summary")
    
    df = st.session_state['df_ai']
    
    # Pivot Table
    if 'Model_Used' in df.columns and 'AI_Tag_Accepted' in df.columns:
        # Fill NA for cleaner table
        df_chart = df.copy()
        df_chart['AI_Tag_Accepted'] = df_chart['AI_Tag_Accepted'].fillna('Unknown')
        
        summary = pd.crosstab(df_chart['Model_Used'], df_chart['AI_Tag_Accepted'])
        
        # Add totals
        summary['Total'] = summary.sum(axis=1)
        
        # Calculate Accuracy if columns exist
        if 'Yes' in summary.columns:
            summary['Accuracy %'] = (summary['Yes'] / summary['Total'] * 100).round(1)
            
        st.dataframe(summary, use_container_width=True)
        
        # Chart (Drop calculations for clean visual)
        st.bar_chart(summary.drop(columns=['Total', 'Accuracy %'], errors='ignore'))
    else:
        st.error("Cannot generate summary: Missing required columns.")

# --- MAIN ROUTER ---
def main():
    st.sidebar.title("🎛️ App Mode")
    page = st.sidebar.radio("Select Workflow", ["Standard QC", "Review AI Tags"])
    
    if page == "Standard QC":
        render_standard_qc()
    elif page == "Review AI Tags":
        render_ai_tags_page()

if __name__ == "__main__":
    main()