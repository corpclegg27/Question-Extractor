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

from firebase_admin import credentials, auth

def delete_all_users():
    """
    Lists all users in Firebase Auth and deletes them one by one.
    This effectively clears the 'Users' table in the Firebase Console.
    """
    try:
        # Fetch users in batches to be memory efficient
        page = auth.list_users()
        while page:
            for user in page.users:
                print(f"Deleting user: {user.uid} ({user.email})")
                auth.delete_user(user.uid)
            
            # Get next batch of users if they exist
            page = page.get_next_page()
            
        print("Successfully deleted all users from Firebase Auth.")
    except Exception as e:
        print(f"Error during bulk deletion: {e}")



# The data mapping based on your requirements
# Structure: "Exam_Subject": Seconds
IDEAL_TIME_MAP = {
    "NEET_Physics": 80,
    "JEE Main_Physics": 150,
    
    # You can easily add more here later:
    # "NEET_Chemistry": 60,
    # "JEE Main_Maths": 120,
}

def addIdealTimeMapToOptionSets():
    try:

        
        # 2. Reference the document
        doc_ref = db.collection('static_data').document('option_sets')
        
        # 3. Update the document
        # We use set(..., merge=True) to ensure we don't wipe out 
        # existing fields like 'exams_list' or 'classes_list'.
        doc_ref.set({
            'idealTimePerQuestion': IDEAL_TIME_MAP
        }, merge=True)
        
        print(f"✅ Successfully updated /static_data/option_sets")
        print(f"   Added {len(IDEAL_TIME_MAP)} benchmarks.")
        
    except Exception as e:
        print(f"❌ Error updating Firestore: {e}")



# --- SANITIZE ANSWER KEY ---


def sanitize_correct_answers(file_path):
    """
    1. Converts 'Correct Answer' 1-4 to A-D for 'Single Correct' questions.
    2. If a 'Single Correct' question has a non A-D answer (like 45.5), 
       reclassifies 'Question type' to 'Numerical type'.
    """
    if not os.path.exists(file_path):
        print(f"❌ Error: File not found at {file_path}")
        return

    print(f"🔍 Reading {os.path.basename(file_path)} for sanitization...")
    df = pd.read_csv(file_path)
    
    # Mapping for standard Single Correct options
    ans_map = {
        '1': 'A', '1.0': 'A', 1: 'A', 1.0: 'A',
        '2': 'B', '2.0': 'B', 2: 'B', 2.0: 'B',
        '3': 'C', '3.0': 'C', 3: 'C', 3.0: 'C',
        '4': 'D', '4.0': 'D', 4: 'D', 4.0: 'D'
    }

    type_changes = 0
    ans_changes = 0

    def processing_logic(row):
        nonlocal type_changes, ans_changes
        # Get values and handle potential NaNs
        q_type = str(row.get('Question type', '')).strip()
        ans = str(row.get('Correct Answer', '')).strip()

        if q_type == 'Single Correct':
            # Step 1: Attempt to map 1,2,3,4 to A,B,C,D
            if ans in ans_map:
                new_ans = ans_map[ans]
                row['Correct Answer'] = new_ans
                ans_changes += 1
                ans = new_ans # Update local var for the next check

            # Step 2: Validate if it actually fits 'Single Correct'
            # If answer is not A, B, C, or D (e.g., it's "42.5" or "100")
            if ans not in ['A', 'B', 'C', 'D']:
                row['Question type'] = 'Numerical type'
                type_changes += 1
        
        return row

    # Ensure required columns exist before applying
    if 'Correct Answer' in df.columns and 'Question type' in df.columns:
        df = df.apply(processing_logic, axis=1)
        
        try:
            df.to_csv(file_path, index=False)
            print(f"✅ Sanitization Complete for: {file_path}")
            print(f"📊 Mapped to A-D: {ans_changes} rows")
            print(f"📊 Reclassified to Numerical type: {type_changes} rows")
        except PermissionError:
            print(f"❌ Permission Denied: Please close '{file_path}' in Excel and try again.")
    else:
        print(f"⚠️ Warning: Required columns ('Correct Answer' or 'Question type') not found.")




# --- Delete NEET Questions ---


def delete_neet_questions():

    collection_ref = db.collection('questions')
    
    # 2. Query for the documents
    # Note: Ensure 'Exam' matches the exact case in your DB ('NEET' vs 'neet')
    query = collection_ref.where('Exam', '==', 'NEET')
    docs = query.stream()

    # 3. Batch deletion logic
    batch = db.batch()
    count = 0
    total_deleted = 0
    
    print("⏳ Querying and preparing to delete...")

    for doc in docs:
        batch.delete(doc.reference)
        count += 1

        # Firestore batches allow up to 500 operations. 
        # We commit every 400 to be safe.
        if count >= 400:
            batch.commit()
            print(f"   Deleted a batch of {count} questions...")
            total_deleted += count
            batch = db.batch() # Start a new batch
            count = 0

    # 4. Commit any remaining documents in the final batch
    if count > 0:
        batch.commit()
        total_deleted += count
        print(f"   Deleted final batch of {count} questions.")

    print(f"✅ Operations complete. Total documents deleted: {total_deleted}")


# Backfill attempts documents

def backfill_attempts_docs():
    print("Starting Strict Fix Process for Flutter Compatibility...")

    # 1. Load Configuration for Smart Tags
    ideal_time_map = {}
    careless_factor = 0.25
    good_skip_factor = 20.0
    
    try:
        config_doc = db.collection('static_data').document('option_sets').get()
        if config_doc.exists:
            data = config_doc.to_dict()
            ideal_time_map = data.get('idealTimePerQuestion', {})
            careless_factor = float(data.get('factorForCarelessAttempt', 0.25))
            good_skip_factor = float(data.get('factorForGoodSkip', 20.0))
            print("Loaded Analysis Config.")
    except Exception as e:
        print(f"Warning: Using default config. Error: {e}")

    # 2. Iterate All Attempts
    attempts_ref = db.collection('attempts')
    attempts_stream = attempts_ref.stream()

    batch = db.batch()
    batch_counter = 0
    BATCH_LIMIT = 400
    processed_count = 0

    for attempt_doc in attempts_stream:
        data = attempt_doc.to_dict()
        
        # Safety Check: Must have responses
        responses = data.get('responses', {})
        if not responses:
            continue

        # --- RE-CALCULATION CONTAINERS ---
        new_responses = {}
        
        # Stats
        correct_count = 0
        incorrect_count = 0
        skipped_count = 0
        
        # Breakdowns (Maps required by UI)
        # UI Keys: "Perfect Attempt", "Overtime Correct", etc.
        analysis_counts = {
            "Perfect Attempt": 0, "Overtime Correct": 0, "Careless Mistake": 0,
            "Wasted Attempt": 0, "Good Skip": 0, "Time Wasted": 0
        }
        smart_time_breakdown = {k: 0 for k in analysis_counts}
        
        # UI Keys: "CORRECT", "INCORRECT", "SKIPPED"
        high_level_time = {"CORRECT": 0, "INCORRECT": 0, "SKIPPED": 0}

        total_time_calc = 0

        # --- PROCESS EACH QUESTION ---
        for q_id, response in responses.items():
            # 1. Safe Data Extraction
            selected_option = response.get('selectedOption')
            correct_option = response.get('correctOption')
            time_spent = int(response.get('timeSpent', 0)) # Ensure int
            subject = response.get('subject', 'Physics')
            
            # 2. Strict Status Logic (No REVIEW allowed)
            new_status = 'SKIPPED'
            
            # Logic: If option is valid string and not "null", check it
            if selected_option and str(selected_option).strip() not in ["", "null"]:
                if str(selected_option) == str(correct_option):
                    new_status = 'CORRECT'
                else:
                    new_status = 'INCORRECT'
            
            # 3. Update Counters & Time
            if new_status == 'CORRECT': 
                correct_count += 1
            elif new_status == 'INCORRECT': 
                incorrect_count += 1
            else: 
                skipped_count += 1
            
            high_level_time[new_status] += time_spent
            total_time_calc += time_spent

            # 4. Generate Smart Tag
            # The UI checks: if (tag.contains("Perfect Attempt"))
            smart_tag = generate_smart_tag(
                new_status, time_spent, subject, ideal_time_map, careless_factor, good_skip_factor
            )
            
            if smart_tag:
                # Extract key for the Maps (remove extra text like " (Skipped...)")
                key_for_map = smart_tag.split(' (')[0].strip()
                if key_for_map in analysis_counts:
                    analysis_counts[key_for_map] += 1
                    smart_time_breakdown[key_for_map] += time_spent

            # 5. Update Response Object
            response['status'] = new_status
            response['smartTimeAnalysis'] = smart_tag
            new_responses[q_id] = response
            
            # 6. Queue AttemptItem Update (for Detailed View)
            # Efficiently find specific item
            items_query = db.collection('attempt_items')\
                .where('attemptRef', '==', attempt_doc.reference)\
                .where('questionId', '==', q_id).limit(1).stream()
            
            for item_doc in items_query:
                batch.update(item_doc.reference, {'status': new_status})
                batch_counter += 1

        # --- FINAL CALCULATIONS ---
        total_questions = len(new_responses)
        max_marks = total_questions * 4
        calculated_score = (correct_count * 4) - (incorrect_count * 1)
        
        # Use calculated time to ensure chart consistency, 
        # unless original has a drastically different time (e.g. timed test timeout),
        # but for consistency, calculated is safer for the breakdown charts.
        final_time_taken = total_time_calc

        # --- CONSTRUCT UPDATE PAYLOAD ---
        update_payload = {
            # 1. CORE STATS (camelCase)
            'responses': new_responses,
            'score': calculated_score,
            'maxMarks': max_marks,              # Required by TestResult
            'correctCount': correct_count,      # Required by TestResult
            'incorrectCount': incorrect_count,  # Required by TestResult
            'skippedCount': skipped_count,      # Required by TestResult
            'totalQuestions': total_questions,  # Required by TestResult
            'timeTakenSeconds': final_time_taken, # Required by TestResult
            
            # 2. BREAKDOWN MAPS
            'secondsBreakdownHighLevel': high_level_time,
            'smartTimeAnalysisCounts': analysis_counts,
            'secondsBreakdownSmartTimeAnalysis': smart_time_breakdown,

            # 3. DELETE GARBAGE (snake_case)
            'correct_count': firestore.DELETE_FIELD,
            'incorrect_count': firestore.DELETE_FIELD,
            'skipped_count': firestore.DELETE_FIELD,
            'total_questions': firestore.DELETE_FIELD,
            'max_marks': firestore.DELETE_FIELD,
            'skipped_questions': firestore.DELETE_FIELD # Just in case
        }

        batch.update(attempt_doc.reference, update_payload)
        batch_counter += 1
        processed_count += 1
        
        print(f"Queueing Fix: {attempt_doc.id} | Score: {calculated_score}")

        if batch_counter >= BATCH_LIMIT:
            batch.commit()
            print("Batch committed...")
            batch = db.batch()
            batch_counter = 0

    if batch_counter > 0:
        batch.commit()
    
    print(f"SUCCESS: Fixed {processed_count} attempts.")

def generate_smart_tag(status, time_taken, subject, ideal_map, careless_factor, good_skip_factor):
    # Logic matched to Flutter _behavioralOrder
    ideal_time = ideal_map.get(subject, 60)
    
    if status == 'CORRECT':
        if time_taken <= ideal_time: 
            return "Perfect Attempt"
        else: 
            return "Overtime Correct"
    elif status == 'INCORRECT':
        if time_taken < (ideal_time * careless_factor): 
            return "Careless Mistake"
        else: 
            return "Wasted Attempt"
    elif status == 'SKIPPED':
        if time_taken < good_skip_factor: 
            return "Good Skip"
        else: 
            return "Time Wasted (Skipped but spent too much time)"
            # Note: "Time Wasted" matches the key check .startsWith("Time Wasted")
    return "Time Wasted" # Fallback

# Run



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
        print ("6. Delete all user records from auth system")
        print ("7. Add ideal time per question map")
        print ("8. Sanitize answer key of csv provided")
        print ("9. Delete NEET Questions")
        print ("10. Backfill attempts documents")
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

        if choice == '6':
            delete_all_users()

        if choice == '7':
            addIdealTimeMapToOptionSets()

        if choice == '8':
            sanitize_correct_answers(file_path=r"D:\Main\3. Work - Teaching\Projects\Question extractor\DB Master Firebase.csv")


        if choice == '9':
            delete_neet_questions()

        if choice == '10':
            backfill_attempts_docs()


        elif choice == '0':
            print("Bye! 👋")
            sys.exit()
        else:
            print("❌ Invalid choice. Try again.")

if __name__ == "__main__":
    main()