import sqlite3
import pandas as pd
import os
from tqdm import tqdm

# --- 1. CONFIGURATION (VERIFY THESE PATHS) ---
BASE_DIR = os.path.dirname(os.path.abspath(__file__))

# Path where your images are (Q_1.png, etc.)
PROCESSED_DIR = os.path.join(BASE_DIR, "Processed_Database")

# Path where your PDFs and CSVs are
# (Assuming 'Raw Data' is a sibling folder inside 'Question extractor')
RAW_DIR = os.path.join(BASE_DIR, "Raw Data") 

# Output Database File
DB_PATH = os.path.join(BASE_DIR, "master_question_bank.db")

def build_database():
    print(f"🔧 Starting Hybrid Database Build")
    print(f"   Input Metadata: {RAW_DIR}")
    print(f"   Input Images:   {PROCESSED_DIR}")
    print("-" * 50)

    # Check if folders exist
    if not os.path.exists(PROCESSED_DIR):
        print(f"❌ Error: Processed folder not found: {PROCESSED_DIR}")
        return
    if not os.path.exists(RAW_DIR):
        print(f"❌ Error: Raw Data folder not found: {RAW_DIR}")
        return

    # --- 2. DATABASE SETUP ---
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute('DROP TABLE IF EXISTS questions')
    cursor.execute('''
        CREATE TABLE questions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            test_name TEXT,
            question_num INTEGER,
            exam TEXT,
            subject TEXT,
            difficulty TEXT,
            chapter TEXT,
            topic TEXT,
            q_image_path TEXT,
            sol_image_path TEXT
        )
    ''')
    conn.commit()

    # --- 3. SCAN PROCESSED FOLDERS ---
    # We scan Processed because we only want tests that have images ready
    processed_folders = [f.name for f in os.scandir(PROCESSED_DIR) if f.is_dir()]
    print(f"📂 Found {len(processed_folders)} test folders in Processed Database.")

    records_added = 0

    for test_name in tqdm(processed_folders, desc="Linking Metadata"):
        
        # Define paths for this specific test
        path_to_images = os.path.join(PROCESSED_DIR, test_name)
        path_to_metadata = os.path.join(RAW_DIR, test_name, "metadata.csv")
        
        # 1. Read Metadata from RAW
        if not os.path.exists(path_to_metadata):
            # Fallback: Check if metadata exists in Processed (sometimes it's copied there)
            path_to_metadata_backup = os.path.join(path_to_images, "metadata.csv")
            if os.path.exists(path_to_metadata_backup):
                path_to_metadata = path_to_metadata_backup
            else:
                # print(f"   ⚠️ Metadata missing for: {test_name}") 
                continue

        try:
            df = pd.read_csv(path_to_metadata)
        except Exception as e:
            print(f"   ❌ Error reading CSV for {test_name}: {e}")
            continue

        # Clean Columns
        df.columns = [str(c).strip() for c in df.columns]
        
        # Find 'Q' Column (Case Insensitive)
        q_col = next((c for c in df.columns if c.lower() in ['q', 'question', 'question no.', 'q no']), None)
        if not q_col:
            continue

        # 2. Loop through rows and link to PROCESSED images
        for _, row in df.iterrows():
            q_num = row.get(q_col)
            if pd.isna(q_num): continue
            
            # Construct Image Paths (Pointing to PROCESSED_DIR)
            q_img = os.path.join(path_to_images, f"Q_{q_num}.png")
            sol_img = os.path.join(path_to_images, f"Sol_{q_num}.png")

            # Only add if the Question Image actually exists
            if os.path.exists(q_img):
                cursor.execute('''
                    INSERT INTO questions 
                    (test_name, question_num, exam, subject, difficulty, chapter, topic, q_image_path, sol_image_path)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ''', (
                    test_name,
                    q_num,
                    row.get('Exam', 'Unknown'),
                    row.get('Subject', 'Physics'),
                    row.get('Difficulty_', row.get('Difficulty_tag', 'Medium')),
                    row.get('Chapter', 'Unknown'),
                    row.get('Topic', 'Unknown'),
                    q_img,
                    sol_img if os.path.exists(sol_img) else None
                ))
                records_added += 1

    conn.commit()
    conn.close()
    
    print("-" * 50)
    print(f"✅ FINISHED: Added {records_added} questions to database.")
    print(f"📍 Database: {DB_PATH}")

if __name__ == "__main__":
    build_database()