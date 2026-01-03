import pandas as pd
import os
import sys
from PIL import Image
try:
    from tqdm import tqdm
except ImportError:
    # Fallback if tqdm is missing
    def tqdm(iterable, **kwargs): return iterable

# --- CONFIGURATION ---
BASE_PATH = 'D:/Main/3. Work - Teaching/Projects/Question extractor/'
DB_PATH = os.path.join(BASE_PATH, 'DB Master.csv')
IMG_DIR = os.path.join(BASE_PATH, 'Processed_Database')

# --- UTILITIES ---
def load_db():
    if not os.path.exists(DB_PATH):
        print(f"❌ Database not found at: {DB_PATH}")
        return None
    try:
        # Support both CSV and Excel for legacy reasons, though we moved to CSV
        if DB_PATH.endswith('.csv'):
            return pd.read_csv(DB_PATH)
        else:
            return pd.read_excel(DB_PATH)
    except Exception as e:
        print(f"❌ Error loading database: {e}")
        return None

def save_db(df):
    try:
        df.to_csv(DB_PATH, index=False)
        print("✅ Database saved successfully.")
    except PermissionError:
        print("❌ ERROR: File is open. Close 'DB Master.csv' and try again.")
    except Exception as e:
        print(f"❌ Save failed: {e}")

def get_image_dims(folder, filename):
    """Returns (width, height) or (None, None)"""
    try:
        path = os.path.join(IMG_DIR, str(folder).strip(), filename)
        if os.path.exists(path) and os.path.getsize(path) > 0:
            with Image.open(path) as img:
                return img.width, img.height
    except Exception:
        pass
    return None, None

# --- FUNCTIONS ---

def func_populate_dimensions():
    print("\n📐 POPULATING IMAGE DIMENSIONS (Q & SOL)...")
    df = load_db()
    if df is None: return

    # 1. Initialize Columns if missing
    targets = ['q_width', 'q_height', 'sol_width', 'sol_height']
    for col in targets:
        if col not in df.columns:
            df[col] = None
            print(f"   ℹ️ Created new column: {col}")

    # 2. Iterate
    updates = 0
    print(f"   🚀 Scanning {len(df)} questions...")
    
    for idx, row in tqdm(df.iterrows(), total=len(df), unit="row"):
        folder = row.get('Folder')
        if pd.isna(folder) or str(folder).strip() == "": continue

        # Smart Q-Number Fetch (Handles 'Q' or 'Question No.')
        q_val = row.get('Question No.')
        if pd.isna(q_val) or str(q_val).strip() == "":
            q_val = row.get('Q')
        
        if pd.isna(q_val): continue
        
        # Normalize Q number to integer if possible
        try:
            q_num = int(float(q_val))
        except:
            q_num = str(q_val).strip()

        # A. Get Question Dims
        qw, qh = get_image_dims(folder, f"Q_{q_num}.png")
        if qw: 
            df.at[idx, 'q_width'] = qw
            df.at[idx, 'q_height'] = qh
            updates += 1

        # B. Get Solution Dims
        sw, sh = get_image_dims(folder, f"Sol_{q_num}.png")
        if sw:
            df.at[idx, 'sol_width'] = sw
            df.at[idx, 'sol_height'] = sh

    # 3. Save
    print(f"\n   ✨ Processed dimensions for {updates} questions.")
    save_db(df)

import pandas as pd
import firebase_admin
from firebase_admin import credentials, firestore
from pathlib import Path

# --- CONFIG ---
# Path to your EXISTING local Excel file
EXCEL_PATH = Path(r'D:/Main/3. Work - Teaching/Projects/Question extractor/DB Metadata.xlsx')

# Initialize Firebase (same as before)
cred = credentials.Certificate('studysmart-5da53-firebase-adminsdk-fbsvc-ca5974c5e9.json')
if not firebase_admin._apps:
    firebase_admin.initialize_app(cred)
db = firestore.client()


import firebase_admin
from firebase_admin import credentials
from firebase_admin import firestore
import pandas as pd
import re

# --- CONFIGURATION ---
EXCEL_FILE = 'DB Metadata.xlsx'
SHEET_NAME = 'Syllabus tree'
KEY_PATH = 'serviceAccountKey.json' # Path to your downloaded Firebase key

# Initialize Firebase (only if not already initialized)
if not firebase_admin._apps:
    cred = credentials.Certificate(KEY_PATH)
    firebase_admin.initialize_app(cred)

db = firestore.Client.from_service_account_json('serviceAccountKey.json')

def generate_slug(text):
    """
    Cleaner Slug Generator:
    'Moment of Inertia' -> 'moment_of_inertia'
    """
    if not isinstance(text, str): return "unknown"
    slug = text.lower().strip()
    slug = re.sub(r'[^a-z0-9\s-]', '', slug) # Allow hyphens too
    slug = re.sub(r'[\s-]+', '_', slug)      # Replace spaces/hyphens with underscore
    return slug

def update_syllabus_tree():
    print(f"📂 Reading {EXCEL_FILE}...")
    
    try:
        df = pd.read_excel(EXCEL_FILE, sheet_name=SHEET_NAME)
        
        # We start with a cleaner root structure
        syllabus_tree = {"subjects": {}}

        print("⚙️  Processing rows with Clean IDs...")
        
        for index, row in df.iterrows():
            subject_name = str(row['Subject']).strip()
            chapter_name = str(row['Chapter']).strip()
            topic_name = str(row['Topic']).strip()

            # --- GENERATE SHORT IDs ---
            # We treat the input text as the source of truth for the ID
            
            sub_id = generate_slug(subject_name)   # e.g., "physics"
            chap_id = generate_slug(chapter_name)  # e.g., "rotational_motion"
            topic_id = generate_slug(topic_name)   # e.g., "moment_of_inertia"

            # --- BUILD THE HIERARCHY ---
            
            # 1. Subject Level
            if sub_id not in syllabus_tree["subjects"]:
                syllabus_tree["subjects"][sub_id] = {
                    "name": subject_name,
                    "chapters": {}
                }
            
            # 2. Chapter Level (Scoped inside Subject)
            if chap_id not in syllabus_tree["subjects"][sub_id]["chapters"]:
                syllabus_tree["subjects"][sub_id]["chapters"][chap_id] = {
                    "name": chapter_name,
                    "topics": {}
                }
            
            # 3. Topic Level (Scoped inside Chapter)
            # Just "topic_id": "Topic Name"
            syllabus_tree["subjects"][sub_id]["chapters"][chap_id]["topics"][topic_id] = topic_name

        # --- UPLOAD ---
        print("☁️  Uploading cleaned data to Firestore...")
        db.collection('static_data').document('syllabus').set(syllabus_tree)
        
        print("✅ SUCCESS! Database updated with clean, readable IDs.")
        print("Example path: subjects -> physics -> chapters -> rotational_motion -> topics -> moment_of_inertia")

    except Exception as e:
        print(f"❌ Error: {e}")

def generate_slug(text):
    """
    Cleaner Slug Generator:
    'Parallel  Axis Theorem ' -> 'parallel_axis_theorem'
    """
    if not isinstance(text, str): return None
    slug = text.lower().strip()
    slug = re.sub(r'[^a-z0-9\s-]', '', slug) # Remove special chars
    slug = re.sub(r'[\s-]+', '_', slug)      # Replace spaces with underscore
    return slug

def add_ids_to_existing_questions():
    print("🚀 Starting Migration: Adding IDs (Chapter, Topic, Topic_L2)...")

    # --- STEP 1: Build Lookup Maps for verified Syllabus items ---
    print("📖 Reading Syllabus...")
    syllabus_doc = db.collection('static_data').document('syllabus').get()
    
    chapter_name_to_id = {}
    topic_name_to_id = {}

    if syllabus_doc.exists:
        data = syllabus_doc.to_dict()
        subjects = data.get('subjects', {})
        
        for sub_id, sub_data in subjects.items():
            chapters = sub_data.get('chapters', {})
            for chap_id, chap_data in chapters.items():
                c_name = chap_data.get('name', '').strip()
                if c_name:
                    chapter_name_to_id[c_name] = chap_id
                
                topics = chap_data.get('topics', {})
                for topic_id, topic_name in topics.items():
                    t_name = str(topic_name).strip()
                    if t_name:
                        topic_name_to_id[t_name] = topic_id
    else:
        print("⚠️ Warning: Syllabus not found. Only L2 IDs will be generated.")

    print(f"✅ Loaded lookup tables: {len(chapter_name_to_id)} Chapters, {len(topic_name_to_id)} Topics.")

    # --- STEP 2: Update Questions ---
    print("📥 Fetching all questions...")
    questions_ref = db.collection('questions')
    docs = list(questions_ref.stream()) 
    
    print(f"🔄 Scanning {len(docs)} questions...")
    
    batch = db.batch()
    batch_count = 0
    updated_total = 0
    
    for doc in tqdm(docs, desc="Processing", unit="q"):
        q_data = doc.to_dict()
        
        # Get existing fields
        current_chap_name = q_data.get('Chapter', '').strip()
        current_topic_name = q_data.get('Topic', '').strip()
        current_l2_name = q_data.get('Topic_L2', '').strip()
        
        updates = {}
        
        # 1. Chapter ID (Lookup)
        if current_chap_name in chapter_name_to_id:
            updates['chapterId'] = chapter_name_to_id[current_chap_name]

        # 2. Topic ID (Lookup)
        if current_topic_name in topic_name_to_id:
            updates['topicId'] = topic_name_to_id[current_topic_name]

        # 3. Topic L2 ID (Generate on the fly)
        # Since this isn't in our master syllabus, we standardize whatever string exists
        if current_l2_name:
            generated_id = generate_slug(current_l2_name)
            if generated_id:
                updates['topicL2Id'] = generated_id

        # Add to Batch
        if updates:
            doc_ref = questions_ref.document(doc.id)
            batch.update(doc_ref, updates)
            batch_count += 1
            updated_total += 1
        
        if batch_count >= 400:
            batch.commit()
            batch = db.batch()
            batch_count = 0

    if batch_count > 0:
        batch.commit()
    
    print("\n" + "="*40)
    print(f"🎉 MIGRATION COMPLETE!")
    print(f"✅ Documents Updated: {updated_total} / {len(docs)}")
    print("="*40)



# --- Create option_set ---

def seed_static_data():
    # The reference to the document we want to create
    doc_ref = db.collection('static_data').document('option_sets')
    
    # Check if it already exists to prevent overwriting live data
    if doc_ref.get().exists:
        print("⚠️  Aborting: 'static_data/option_sets' already exists.")
        print("   If you really want to reset it, delete the document in the console first.")
        return

    # 2. DATA: The Master Configuration
    # Note: target_years is dynamic in real apps, but static here as requested
    data = {
        "exams_list": [
            "NEET", 
            "JEE Main", 
            "JEE Advanced"
        ],
        "target_years": [
            2026, 
            2027, 
            2028, 
            2029
        ],
        "classes_list": [
            "Class XI", 
            "Class XII", 
            "Class XII (Passed)"
        ],
        "subjects_list": [
            "Physics", 
            "Chemistry", 
            "Maths", 
            "Biology"
        ],
        # CRITICAL: The atomic counter for generating student_ids
        "last_assigned_student_id": 0 
    }

    # 3. WRITE: Commit to database
    try:
        doc_ref.set(data)
        print("✅ Success: 'static_data/option_sets' created.")
        print("   Initial Student ID counter set to 0.")
        print("   Dropdown options populated.")
    except Exception as e:
        print(f"❌ Error: {e}")



# --- ClearCollections ---


def clearCollections(collection_names, batch_size=50):
    """
    Deletes all documents in the specified list of collections.
    
    Args:
        collection_names (list): List of strings (collection names).
        batch_size (int): Number of docs to delete in one batch (default 50).
    """
    db = firestore.Client.from_service_account_json('serviceAccountKey.json')

    for coll_name in collection_names:
        print(f"Starting cleanup for collection: {coll_name}")
        coll_ref = db.collection(coll_name)
        
        while True:
            # Get a batch of documents
            docs = list(coll_ref.limit(batch_size).stream())
            deleted = 0

            if not docs:
                break

            batch = db.batch()
            for doc in docs:
                batch.delete(doc.reference)
                deleted += 1

            # Commit the batch
            batch.commit()
            print(f"Deleted {deleted} documents from '{coll_name}'...")

        print(f"Successfully cleared: {coll_name}")


# --- MAIN MENU ---

def main():
    while True:
        print("\n" + "="*40)
        print("      🛠️  ADHOC UTILITY MENU")
        print("="*40)
        print("1. Add Image Dimensions (Q & Sol) to DB (local csv)")
        print("2. Add Sylabbus tree to firebase")
        print("3. Add chapterID, topicID, topic_l2ID to existing questions in firebase")
        print("4. Create option sets document in static_data collection")
        print ("5. clearCollection [names already provided in file]")
        print("0. Exit")
        print("-" * 40)
        
        choice = input("Enter choice: ").strip()
        
        if choice == '1':
            func_populate_dimensions()
        
        if choice == '2':
            update_syllabus_tree()

        if choice == '3':
            add_ids_to_existing_questions()

        if choice == '4':
            seed_static_data()

        if choice == '5':
            clearCollections(['users','attempts','attempt_items','questions_curation','student_question_tracker'])


        elif choice == '0':
            print("Bye! 👋")
            sys.exit()
        else:
            print("❌ Invalid choice. Try again.")

if __name__ == "__main__":
    main()