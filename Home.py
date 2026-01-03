import streamlit as st
import pandas as pd
import os
import plotly.express as px

# --- CONFIGURATION ---
# Get the folder where THIS script (Home.py) is located
BASE_PATH = os.path.dirname(os.path.abspath(__file__))
# UPDATED: Pointing to CSV now
DB_PATH = os.path.join(BASE_PATH, 'DB Master.csv')

st.set_page_config(
    page_title="Question Bank HQ",
    page_icon="🏫",
    layout="wide"
)

st.title("🏫 Question Bank Command Center")

# --- AUTO-HEAL: Create DB if missing ---
if not os.path.exists(DB_PATH):
    try:
        # Create an empty dataframe with standard schema
        cols = [
            'Question No.', 'Folder', 'Subject', 'Chapter', 'Exam', 
            'Question type', 'Difficulty_tag', 'Correct Answer', 
            'Marks', 'PYQ', 'PYQ_Year', 'QC_Status', 'QC_Locked', 
            'manually updated'
        ]
        df_empty = pd.DataFrame(columns=cols)
        
        # UPDATED: Save as CSV instead of Excel
        df_empty.to_csv(DB_PATH, index=False)
        st.toast("🆕 Database not found, so I created a fresh 'DB Master.csv' for you!", icon="✨")
    except Exception as e:
        st.error(f"❌ Could not create database. Check permissions.\nError: {e}")

# --- QUICK ACTIONS ---
st.subheader("🚀 Quick Actions")
col1, col2, col3 = st.columns(3)

# Note: These filenames must match exactly what is in your 'pages' folder!
with col1:
    if st.button("➕ Add Question Manually", use_container_width=True):
        st.switch_page("pages/1_Add_Question.py")

with col2:
    if st.button("✅ Review & QC", use_container_width=True):
        st.switch_page("pages/2_Review_QC.py")

with col3:
    if st.button("📝 Create Question Paper", use_container_width=True):
        st.switch_page("pages/3_Create_Paper.py")

st.divider()

# --- METRICS DASHBOARD ---
if os.path.exists(DB_PATH):
    try:
        # UPDATED: Read from CSV
        # low_memory=False prevents mixed-type warnings on large files
        df = pd.read_csv(DB_PATH, low_memory=False) 
        
        # --- TOP LEVEL METRICS ---
        total_qs = len(df)
        
        if 'QC_Status' not in df.columns: df['QC_Status'] = 'Pending'
        
        # Normalize status
        pass_count = len(df[df['QC_Status'].astype(str).str.lower() == 'pass'])
        fail_count = len(df[df['QC_Status'].astype(str).str.lower() == 'fail'])
        pending_count = total_qs - pass_count - fail_count
        
        c1, c2, c3, c4 = st.columns(4)
        c1.metric("📚 Total Questions", total_qs)
        c2.metric("✅ Ready (Pass)", pass_count)
        c3.metric("⚠️ Needs Review", pending_count)
        c4.metric("❌ Failed", fail_count)
        
        st.divider()
        
        # --- CHARTS ---
        if total_qs > 0:
            col_charts1, col_charts2 = st.columns(2)
            
            with col_charts1:
                st.subheader("Subject Distribution")
                if 'Subject' in df.columns:
                    # Clean up data for chart
                    sub_counts = df['Subject'].fillna('Unknown').value_counts().reset_index()
                    sub_counts.columns = ['Subject', 'Count']
                    fig_sub = px.pie(sub_counts, values='Count', names='Subject', hole=0.4)
                    st.plotly_chart(fig_sub, use_container_width=True)
                else:
                    st.info("Subject column missing.")

            with col_charts2:
                st.subheader("Exam Source")
                if 'Exam' in df.columns:
                    exam_counts = df['Exam'].fillna('Unknown').value_counts().reset_index()
                    exam_counts.columns = ['Exam', 'Count']
                    exam_counts = exam_counts.sort_values(by='Count', ascending=True)
                    fig_exam = px.bar(exam_counts, x='Count', y='Exam', orientation='h')
                    st.plotly_chart(fig_exam, use_container_width=True)
                else:
                    st.info("Exam column missing.")
        else:
            st.info("Database is empty. Add some questions to see charts!")

    except Exception as e:
        st.error(f"Error reading database: {e}")
else:
    # Fallback debug info if creation failed
    st.error("⚠️ Critical Error: Database file is still missing.")
    st.code(f"Looking for: {DB_PATH}")