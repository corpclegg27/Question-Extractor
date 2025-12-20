import streamlit as st
import pandas as pd
import os
import glob

# --- CONFIGURATION ---
BASE_PATH = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(os.path.dirname(BASE_PATH), 'DB Master.xlsx')
PROCESSED_PATH = os.path.join(os.path.dirname(BASE_PATH), 'Processed_Database')

st.set_page_config(page_title="Create Paper", layout="wide")

# --- CUSTOM CSS ---
st.markdown("""
    <style>
    .floating-header {
        position: fixed; top: 60px; right: 20px;
        background-color: #f0f2f6; padding: 10px 20px;
        border-radius: 10px; box-shadow: 0px 4px 6px rgba(0,0,0,0.1);
        z-index: 9999; display: flex; align-items: center;
        gap: 15px; border: 1px solid #d6d6d6;
    }
    .floating-count { font-size: 1.2rem; font-weight: bold; color: #1f77b4; }
    
    /* Thicker Divider Style */
    hr {
        border: 0;
        height: 4px;
        background: #e0e0e0;
        margin: 40px 0;
    }

    .stCheckbox {
        background-color: #fcfcfc;
        padding: 12px;
        border-radius: 8px;
        border: 2px solid #eee;
        margin-bottom: 10px;
    }

    .ans-box {
        background-color: #eef9fe;
        padding: 8px 12px;
        border-radius: 6px;
        color: #004a7c;
        font-weight: bold;
        border-left: 6px solid #1f77b4;
        margin-top: 10px;
        margin-bottom: 15px;
    }
    </style>
    """, unsafe_allow_html=True)

# --- SESSION STATE ---
if 'paper_cart' not in st.session_state:
    st.session_state['paper_cart'] = set()
if 'review_mode' not in st.session_state:
    st.session_state['review_mode'] = False
if 'display_limit' not in st.session_state:
    st.session_state['display_limit'] = 50

# --- CALLBACKS ---
def update_qc_status(row_index, widget_key):
    new_status = st.session_state[widget_key]
    st.session_state['df_master'].at[row_index, 'QC_Status'] = new_status
    try:
        st.session_state['df_master'].to_excel(DB_PATH, index=False)
        st.toast(f"Q{st.session_state['df_master'].at[row_index, 'Question No.']} status: {new_status}")
    except Exception as e:
        st.error(f"Error saving QC update: {e}")

def toggle_selection(idx):
    if idx in st.session_state['paper_cart']:
        st.session_state['paper_cart'].remove(idx)
    else:
        st.session_state['paper_cart'].add(idx)

def load_more():
    st.session_state['display_limit'] += 50

# --- HELPERS ---
def get_image_path(folder, prefix_list, q_num):
    if not folder or not q_num: return None
    f_path = os.path.join(PROCESSED_PATH, str(folder))
    if not os.path.exists(f_path): return None
    for pre in prefix_list:
        p = os.path.join(f_path, f"{pre}_{q_num}.png")
        if os.path.exists(p): return p
        matches = glob.glob(os.path.join(f_path, f"*{pre}*_{q_num}.png"))
        if matches: return matches[0]
    return None

def render_filter(label, column, df_current):
    if column not in df_current.columns: return 'All', df_current
    counts = df_current[column].fillna('N/A').astype(str).value_counts()
    sorted_keys = sorted(counts.index.tolist())
    options_map = {'All': f"All ({len(df_current)})"}
    for k in sorted_keys: options_map[k] = f"{k} ({counts[k]})"
    
    # Reset display limit if filter changes
    sel = st.sidebar.selectbox(label, ['All'] + sorted_keys, format_func=lambda x: options_map[x], 
                               on_change=lambda: st.session_state.update({'display_limit': 50}))
    
    return (sel, df_current[df_current[column].fillna('N/A').astype(str) == sel]) if sel != 'All' else ('All', df_current)

# --- LOAD DATA ---
if 'df_master' not in st.session_state:
    if os.path.exists(DB_PATH):
        st.session_state['df_master'] = pd.read_excel(DB_PATH)
    else:
        st.error("❌ DB Master not found!"); st.stop()

df = st.session_state['df_master']
df['unique_id'] = df.index
df_pass = df[df['QC_Status'].astype(str).str.lower() == 'pass'].copy()

# --- MAIN LOGIC ---
if st.session_state['review_mode']:
    st.title("🚀 Review Selected Questions")
    df_review = df_pass[df_pass['unique_id'].isin(list(st.session_state['paper_cart']))]
    
    c_m, c_a = st.columns([2, 1])
    c_m.metric("Selected", len(df_review))
    if c_a.button("✏️ Back to Selection", use_container_width=True): 
        st.session_state['review_mode'] = False
        st.rerun()
    st.divider()

    for idx, row in df_review.iterrows():
        cm, ci = st.columns([1.5, 4])
        with cm:
            st.subheader(f"Q{row['Question No.']}")
            st.markdown(f"**Ans:** {row.get('Correct Answer', 'N/A')}")
            if st.button("🗑️ Remove", key=f"rev_rem_{row['unique_id']}", use_container_width=True):
                toggle_selection(row['unique_id'])
                st.rerun()
        with ci:
            p = get_image_path(row['Folder'], ["Q"], row['Question No.'])
            if p: st.image(p)
        st.markdown("<hr>", unsafe_allow_html=True) # Thick Divider
else:
    # Sidebar Filters
    st.sidebar.header("🔍 Filters")
    df_v = df_pass.copy()
    for l, c in [('Exam', 'Exam'), ('Subject', 'Subject'), ('Type', 'Question type'), 
                 ('Chapter', 'Chapter'), ('Topic', 'Topic'), ('Difficulty', 'Difficulty_tag')]:
        _, df_v = render_filter(l, c, df_v)

    st.title("📝 Create Question Paper")
    st.markdown(f'<div class="floating-header">Selected: <span class="floating-count">{len(st.session_state["paper_cart"])}</span></div>', unsafe_allow_html=True)

    if st.button("🚀 Proceed to Review", type="primary", disabled=len(st.session_state['paper_cart']) == 0):
        st.session_state['review_mode'] = True
        st.rerun()

    st.divider()

    # Display subset based on limit
    total_matches = len(df_v)
    df_display = df_v.iloc[:st.session_state['display_limit']]

    for idx, row in df_display.iterrows():
        c1, c2 = st.columns([1.6, 4])
        with c1:
            st.checkbox(f"**SELECT Q{row['Question No.']}**", key=f"chk_{row['unique_id']}", 
                        value=row['unique_id'] in st.session_state['paper_cart'], 
                        on_change=toggle_selection, args=(row['unique_id'],))
            
            st.markdown(f"**Sub:** {row.get('Subject', 'N/A')}")
            st.markdown(f"**Chap:** {row.get('Chapter', 'N/A')}")
            st.markdown(f"**Topic:** {row.get('Topic', 'N/A')}")
            st.markdown(f"**Question Type:** {row.get('Question type', 'N/A')}")
            st.markdown(f"**Difficulty:** {row.get('Difficulty_tag', 'N/A')}")
            
            qck = f"qc_upd_{row['unique_id']}"
            st.selectbox("QC Update", options=["Pass", "Fail"], index=0, key=qck, 
                         on_change=update_qc_status, args=(idx, qck), label_visibility="collapsed")
            
            st.markdown(f'<div class="ans-box">Correct Ans: {row.get("Correct Answer", "N/A")}</div>', unsafe_allow_html=True)
            
            with st.expander("👁️ View Solution"):
                sp = get_image_path(row['Folder'], ["S", "Sol"], row['Question No.'])
                if sp: st.image(sp)
                else: st.caption("No solution image available.")

        with c2:
            qp = get_image_path(row['Folder'], ["Q"], row['Question No.'])
            if qp: st.image(qp)
        
        # Thicker HTML Divider
        st.markdown("<hr>", unsafe_allow_html=True)

    # Load More Mechanism
    if total_matches > st.session_state['display_limit']:
        st.write(f"Showing {st.session_state['display_limit']} of {total_matches} questions.")
        if st.button("➕ Load More Questions", use_container_width=True):
            load_more()
            st.rerun()
    elif total_matches > 0:
        st.success(f"All {total_matches} questions loaded.")