import streamlit as st
import pandas as pd
import os
import shutil
from datetime import datetime
from PIL import Image
import io

# --- TRY IMPORTING PASTE BUTTON ---
try:
    from streamlit_paste_button import paste_image_button as pbutton
except ImportError:
    st.error("⚠️ Library missing! Please run: pip install streamlit-paste-button")
    st.stop()

# --- CONFIGURATION ---
BASE_PATH = 'D:/Main/3. Work - Teaching/Projects/Question extractor/'
DB_PATH = os.path.join(BASE_PATH, 'DB Master.xlsx')
TOPIC_MAP_PATH = os.path.join(BASE_PATH, 'ChapterTopics.csv')
PROCESSED_DIR = os.path.join(BASE_PATH, 'Processed_Database')
MANUAL_FOLDER_NAME = "Manual_Uploads"

st.set_page_config(page_title="Add New Question", layout="wide") # Changed to Wide for better side-by-side view

# --- SESSION STATE INITIALIZATION ---
if 'step' not in st.session_state: st.session_state['step'] = 1
if 'new_q_data' not in st.session_state: st.session_state['new_q_data'] = {}
if 'q_image_data' not in st.session_state: st.session_state['q_image_data'] = None
if 'sol_image_data' not in st.session_state: st.session_state['sol_image_data'] = None
# Counter ensures unique keys for paste buttons per question
if 'session_counter' not in st.session_state: st.session_state['session_counter'] = 1

# --- HELPERS ---
def load_topics():
    if os.path.exists(TOPIC_MAP_PATH):
        return pd.read_csv(TOPIC_MAP_PATH)
    return pd.DataFrame()

def get_manual_question_no():
    if os.path.exists(DB_PATH):
        df = pd.read_excel(DB_PATH)
        if 'Folder' in df.columns:
            df_manual = df[df['Folder'] == MANUAL_FOLDER_NAME].copy()
            if df_manual.empty: return 1
            df_manual['Question No.'] = pd.to_numeric(df_manual['Question No.'], errors='coerce').fillna(0)
            return int(df_manual['Question No.'].max()) + 1
    return 1

def save_final_question():
    data = st.session_state['new_q_data']
    q_img = st.session_state['q_image_data']
    sol_img = st.session_state['sol_image_data']
    
    q_num = get_manual_question_no()
    
    # Prepare Paths
    target_folder = os.path.join(PROCESSED_DIR, MANUAL_FOLDER_NAME)
    os.makedirs(target_folder, exist_ok=True)
    
    # Save Images
    if q_img:
        q_path = os.path.join(target_folder, f"Q_{q_num}.png")
        q_img.save(q_path)
    if sol_img:
        sol_path = os.path.join(target_folder, f"Sol_{q_num}.png")
        sol_img.save(sol_path)
        
    # Save to Excel
    new_row = {
        'Question No.': q_num,
        'Folder': MANUAL_FOLDER_NAME,
        'Subject': data.get('Subject'),
        'Chapter': data.get('Chapter'),
        'Topic': data.get('Topic'),
        'Topic_L2': data.get('Topic_L2'),
        'Exam': data.get('Exam'),
        'Question type': data.get('Question type'),
        'Difficulty_tag': data.get('Difficulty_tag'),
        'Correct Answer': data.get('Correct Answer'),
        'PYQ': data.get('PYQ'),
        'PYQ_Year': data.get('PYQ_Year'),
        'Classroom_Illustration': data.get('Classroom_Illustration'),
        'QC_Status': 'Pass', 
        'QC_Locked': 1,
        'manually updated': 1
    }
    
    if os.path.exists(DB_PATH):
        df_master = pd.read_excel(DB_PATH)
        df_master = pd.concat([df_master, pd.DataFrame([new_row])], ignore_index=True)
    else:
        df_master = pd.DataFrame([new_row])
        
    try:
        df_master.to_excel(DB_PATH, index=False)
        st.toast(f"✅ Question {q_num} saved!", icon="🎉")
        
        # --- RESET FOR NEXT CYCLE ---
        st.session_state['step'] = 1
        st.session_state['new_q_data'] = {}
        st.session_state['q_image_data'] = None
        st.session_state['sol_image_data'] = None
        st.session_state['session_counter'] += 1
        
        st.rerun()
        
    except PermissionError:
        st.error("❌ Could not save: Excel file is open. Close it and try again.")

# --- NAVIGATION ---
def next_step(): st.session_state['step'] += 1
def prev_step(): st.session_state['step'] -= 1

# =======================
#       UI STEPS
# =======================

# --- STEP 1: LANDING ---
if st.session_state['step'] == 1:
    st.title("Question Entry Wizard")
    next_num = get_manual_question_no()
    st.caption(f"Next Manual ID: #{next_num}")
    
    if st.button("➕ Start Adding Question", type="primary"):
        next_step()
        st.rerun()

# --- STEP 2: THE WORKSPACE (MERGED) ---
elif st.session_state['step'] == 2:
    st.header("New Question Details")
    df_topics = load_topics()
    
    # --- METADATA SECTION ---
    with st.container():
        c1, c2, c3 = st.columns([1, 1, 1])
        
        # Column 1: Basic Tags
        with c1:
            st.subheader("1. Tags")
            exam = st.selectbox("Exam", ["JEE Main", "JEE Advanced", "NEET", "Board"], index=0)
            q_type = st.selectbox("Question Type", ["Single Correct", "Multiple Correct", "Numerical", "Passage", "Matrix Match"])
            difficulty = st.selectbox("Difficulty", ["Easy", "Medium", "Hard"])
            
            st.markdown("---")
            val_pyq = st.selectbox("PYQ", ["No", "Yes"], index=0) 
            pyq_year = st.text_input("PYQ Year", placeholder="e.g. 2023 Shift 1") if val_pyq == "Yes" else ""
            val_class_illus = st.selectbox("Classroom Illustration", ["No", "Yes"], index=0)

        # Column 2: Topic Hierarchy
        with c2:
            st.subheader("2. Topic")
            subjects = df_topics['Subject'].unique().tolist() if not df_topics.empty else ['Physics', 'Chemistry', 'Maths']
            subject = st.selectbox("Subject", subjects, index=subjects.index('Physics') if 'Physics' in subjects else 0)
            
            chapters = df_topics[df_topics['Subject'] == subject]['Chapter'].unique().tolist() if not df_topics.empty else []
            chapter = st.selectbox("Chapter", chapters)
            
            topics = []
            if not df_topics.empty and chapter:
                topics = df_topics[(df_topics['Subject'] == subject) & (df_topics['Chapter'] == chapter)]['Topic'].unique().tolist()
            topic = st.selectbox("Topic", topics) if topics else st.text_input("Topic (Manual)")

            l2_topics = []
            if not df_topics.empty and topic and 'Topic_L2' in df_topics.columns:
                l2_topics = df_topics[(df_topics['Subject'] == subject) & (df_topics['Chapter'] == chapter) & (df_topics['Topic'] == topic)]['Topic_L2'].unique().tolist()
                l2_topics = [x for x in l2_topics if str(x) != 'nan']
            topic_l2 = st.selectbox("Sub-Topic", l2_topics) if l2_topics else st.text_input("Sub-Topic (Manual)")
            
        # Column 3: Images & Answer
        with c3:
            st.subheader("3. Content")
            unique_id = st.session_state['session_counter']
            
            # Question Image
            st.caption("Question Image (Win+Shift+S -> Paste)")
            paste_q = pbutton("📋 Paste Question", background_color="#FF4B4B", hover_background_color="#FF0000", key=f"btn_q_{unique_id}")
            if paste_q.image_data is not None: st.session_state['q_image_data'] = paste_q.image_data
            
            if st.session_state['q_image_data']:
                st.image(st.session_state['q_image_data'], width=200)
            else:
                st.warning("Required")
                
            st.markdown("---")
            
            # Solution Image
            st.caption("Solution Image (Optional)")
            paste_sol = pbutton("📋 Paste Solution", background_color="#4CAF50", hover_background_color="#45a049", key=f"btn_sol_{unique_id}")
            if paste_sol.image_data is not None: st.session_state['sol_image_data'] = paste_sol.image_data
            
            if st.session_state['sol_image_data']:
                st.image(st.session_state['sol_image_data'], width=200)

            st.markdown("---")
            
            # Answer Key
            curr_ans = st.session_state['new_q_data'].get('Correct Answer', "")
            ans_key = st.text_input("Correct Answer", value=curr_ans, placeholder="e.g. A, B, 4")

    st.divider()

    # --- NAVIGATION ---
    c_back, c_next = st.columns([1, 6])
    if c_back.button("⬅️ Cancel"): 
        st.session_state['step'] = 1
        st.rerun()
    
    if st.session_state['q_image_data']:
        if c_next.button("Review & Save ➡️", type="primary"): 
            # Save current state to dict before moving
            st.session_state['new_q_data'] = {
                'Exam': exam, 'Question type': q_type, 'Difficulty_tag': difficulty,
                'Subject': subject, 'Chapter': chapter, 'Topic': topic, 'Topic_L2': topic_l2,
                'PYQ': val_pyq, 'PYQ_Year': pyq_year, 'Classroom_Illustration': val_class_illus,
                'Correct Answer': ans_key
            }
            next_step()
            st.rerun()
    else:
        c_next.warning("⚠️ Please paste a question image.")

# --- STEP 3: REVIEW & SAVE ---
elif st.session_state['step'] == 3:
    st.header("Review & Save")
    
    # 1. Show Metadata Table
    df_sum = pd.DataFrame([st.session_state['new_q_data']]).T
    df_sum.columns = ["Value"]
    st.table(df_sum)
    
    # 2. Show Images Large
    col_img1, col_img2 = st.columns(2)
    with col_img1:
        st.subheader("Question")
        if st.session_state['q_image_data']: st.image(st.session_state['q_image_data'])
    
    with col_img2:
        st.subheader("Solution")
        if st.session_state['sol_image_data']: st.image(st.session_state['sol_image_data'])
    
    st.divider()
    
    b1, b2 = st.columns([1, 4])
    if b1.button("⬅️ Edit"): prev_step(); st.rerun()
    
    if b2.button("💾 CONFIRM SAVE", type="primary", use_container_width=True):
        save_final_question()