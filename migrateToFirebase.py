import pandas as pd
import firebase_admin
from firebase_admin import credentials, firestore, storage
import os
import mimetypes
import datetime
import time
import re
import math
import csv

# --- 1. CONFIGURATION ---
CREDENTIALS_FILE = 'studysmart-5da53-firebase-adminsdk-fbsvc-ca5974c5e9.json'
STORAGE_BUCKET = 'studysmart-5da53.firebasestorage.app'
CSV_FILE = 'DB Master Firebase.csv'
LOG_FILE = 'migrationLogs.csv'  # Persistent Log File

# COLLECTION NAME
COLLECTION_NAME = 'questions' 

# Local Base Directory
BASE_DIR = r"D:\Main\3. Work - Teaching\Projects\Question extractor\Processed_Database"

# Cloud Storage Root Folder
STORAGE_ROOT = "Question Bank" 

# SAFETY FLAG: 
ERASE_EXISTING_DATA = False 

# --- COLUMNS TO FIX ---
TEXT_COLUMNS_TO_FIX = [
    "Section Name", "Model_Used", "pdf_Text", "PDF_Text_Available", 
    "AI_Reasoning", "Correct Answer_key", "Sub-Topic", 
    "Q_Image_Path", "Sol_Image_Path", "PYQ", "Chapter", "Question type", 
    "Subject", "OCR_Text", "Labelled by AI", "Topic_L2", "Topic", 
    "image_url", "question_id", "Exam", "Difficulty_tag", "Folder", 
    "Correct Answer", "QC_Status", "AI_Tag_Accepted", "PYQ_Year_Detailed"
]

INT_COLUMNS_TO_FIX = [
    "q_width", "q_height", "sol_width", "sol_height", "Question No.", 
    "QC_Locked", "manually updated"
]

# --- 2. INITIALIZE FIREBASE ---
if not firebase_admin._apps:
    cred = credentials.Certificate(CREDENTIALS_FILE)
    firebase_admin.initialize_app(cred, {
        'storageBucket': STORAGE_BUCKET
    })

db = firestore.client()
bucket = storage.bucket()

# --- 3. HELPER FUNCTIONS ---
def clean_text_field(value):
    """Converts NaNs/Floats to empty strings."""
    if value is None: return ""
    if isinstance(value, float):
        if math.isnan(value): return ""
        return str(value).replace(".0", "") # Remove .0 if it looks like an int
    return str(value).strip()

def clean_int_field(value):
    """Converts floats/strings to safe integers. Returns 0 if invalid."""
    if value is None: return 0
    try:
        if isinstance(value, float) and math.isnan(value): return 0
        return int(float(value))
    except (ValueError, TypeError):
        return 0

def extract_year(text):
    """Extracts year for the new Integer column."""
    if not text: return 0
    text_str = str(text)
    
    # --- FIX APPLIED HERE ---
    # Old: r'\b(19|20)\d{2}\b' (Captures only 19 or 20)
    # New: r'\b(19\d{2}|20\d{2})\b' (Captures the full 19xx or 20xx)
    matches = re.findall(r'\b(19\d{2}|20\d{2})\b', text_str)
    
    if matches:
        return max(map(int, matches))
    return 0

def load_processed_ids(log_file):
    """Reads the log file and returns a set of already processed question_ids."""
    processed = set()
    if not os.path.exists(log_file):
        with open(log_file, 'w', newline='', encoding='utf-8') as f:
            writer = csv.writer(f)
            writer.writerow(['timestamp', 'question_id', 'status'])
        return processed
    
    try:
        df_log = pd.read_csv(log_file)
        if 'question_id' in df_log.columns:
            success_rows = df_log[df_log['status'] == 'Success']
            processed = set(success_rows['question_id'].astype(str).str.strip())
    except Exception as e:
        print(f"⚠️ Warning: Could not read log file. Starting fresh. Error: {e}")
    
    return processed

def log_result(q_id, status):
    """Appends a single result to the log file."""
    with open(LOG_FILE, 'a', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow([datetime.datetime.now(), q_id, status])

# --- 4. CLEANUP FUNCTION ---
def clean_slate():
    print("!!! WARNING: ERASE_EXISTING_DATA is True !!!")
    print(f"Cleaning up collection: {COLLECTION_NAME}...")
    docs = db.collection(COLLECTION_NAME).stream()
    for doc in docs: doc.reference.delete()
    
    blobs = bucket.list_blobs(prefix=STORAGE_ROOT)
    for blob in blobs: blob.delete()
    
    if os.path.exists(LOG_FILE):
        os.remove(LOG_FILE)
        print(" -> Deleted migrationLogs.csv")
    print("Cleanup Complete.\n")

# --- 5. UPLOAD FUNCTION ---
def upload_file_as_is(local_path, destination_path):
    if not os.path.exists(local_path): return None, 0
    try:
        file_size = os.path.getsize(local_path)
        blob = bucket.blob(destination_path)
        content_type, _ = mimetypes.guess_type(local_path)
        if content_type is None: content_type = 'application/octet-stream' 
        blob.upload_from_filename(local_path, content_type=content_type)
        blob.make_public()
        return blob.public_url, file_size
    except Exception as e:
        print(f"    Error uploading {os.path.basename(local_path)}: {e}")
        return None, 0

# --- 6. EXECUTE MIGRATION ---
start_time = time.time()
print(f"--- Migration Started at {datetime.datetime.now()} ---")

if ERASE_EXISTING_DATA:
    clean_slate()
    PROCESSED_IDS = set() 
else:
    PROCESSED_IDS = load_processed_ids(LOG_FILE)
    print(f"🔄 Found {len(PROCESSED_IDS)} already processed questions in logs.")

# Load CSV
try:
    df = pd.read_csv(CSV_FILE)
    if 'unique_id' in df.columns:
        df.rename(columns={'unique_id': 'question_id'}, inplace=True)
    
    df = df[df['question_id'].notna()]
    
    # SORT DESCENDING BY QUESTION_ID
    # Converting to string first to ensure sorting works even if mixed types
    df['question_id'] = df['question_id'].astype(str)
    
    print(f"Loaded Master CSV with {len(df)} rows.")
except Exception as e:
    print(f"CRITICAL ERROR: {e}")
    exit()

stats = {"skipped": 0, "success": 0, "error": 0, "new_images": 0}
cum_count=0

for index, row in df.iterrows():
    try:
        q_id = str(row['question_id']).strip()
        
        # --- SKIP LOGIC ---
        if q_id in PROCESSED_IDS:
            stats["skipped"] += 1
            continue
            
        original_folder = str(row['Folder']).strip()
        q_num = str(row['Q']).strip()
        
        if original_folder.startswith("CollegeDoors"):
            target_folder = original_folder.replace("CollegeDoors", "DC", 1)
        else:
            target_folder = original_folder
            
        print(f"[{cum_count+1}/{len(df)}] Processing: {q_id}")
        cum_count=cum_count+1

        # --- PATHS ---
        local_q_path = os.path.join(BASE_DIR, original_folder, f"Q_{q_num}.png")
        local_sol_path = os.path.join(BASE_DIR, original_folder, f"Sol_{q_num}.png")
        storage_q_path = f"{STORAGE_ROOT}/{target_folder}/Q_{q_num}.png"
        storage_sol_path = f"{STORAGE_ROOT}/{target_folder}/Sol_{q_num}.png"

        # --- PREPARE DATA ---
        raw_data = row.to_dict()
        doc_data = {}

        # 1. Type Cleaning
        for col, val in raw_data.items():
            if col in TEXT_COLUMNS_TO_FIX:
                doc_data[col] = clean_text_field(val)
            elif col in INT_COLUMNS_TO_FIX:
                doc_data[col] = clean_int_field(val)
            else:
                if isinstance(val, float) and math.isnan(val):
                    doc_data[col] = None
                else:
                    doc_data[col] = val

        # 2. Tags Logic
        tags_str = clean_text_field(raw_data.get('tags'))
        if tags_str:
            # Split by pipe, strip whitespace, and filter out empty strings
            doc_data['tags'] = [t.strip() for t in tags_str.split('|') if t.strip()]
        else:
            doc_data['tags'] = []

        # 3. PYQ Logic (FIXED REGEX & COLUMN PRIORITY)
        csv_pyq_year = clean_text_field(raw_data.get('PYQ_Year'))
        csv_pyq_tag = clean_text_field(raw_data.get('PYQ'))
        
        # Pick best source for the DETAILED string
        if len(csv_pyq_year) > 0:
            source_text = csv_pyq_year
        else:
            source_text = csv_pyq_tag

        doc_data['PYQ_Year'] = extract_year(source_text)      # Int (Now correctly returns 2024)
        doc_data['PYQ_Year_Detailed'] = source_text           # Str

        # --- NEW LOGIC: correctAnswersOneOrMore ---
        # We parse the 'Correct Answer' field into a list for consistent usage
        # This creates a new field 'correctAnswersOneOrMore'
        
        raw_answer = doc_data.get('Correct Answer', '')
        q_type = doc_data.get('Question type', '')
        
        # Initialize as empty list
        doc_data['correctAnswersOneOrMore'] = []

        if q_type == 'One or more options correct':
            if raw_answer:
                # Split by comma, strip whitespace from each part
                # e.g., "A, B " -> ["A", "B"]
                doc_data['correctAnswersOneOrMore'] = [x.strip() for x in raw_answer.split(',') if x.strip()]
        
        # Also populate for Single/Numerical so the app always finds a list
        elif q_type == 'Single Correct' or q_type == 'Numerical type':
            if raw_answer:
                doc_data['correctAnswersOneOrMore'] = [str(raw_answer).strip()]

        # 4. Timestamps
        doc_data['lastUpdated'] = firestore.SERVER_TIMESTAMP
        doc_data['createdAt'] = firestore.SERVER_TIMESTAMP

        # 5. Upload Images
        q_url, q_size = upload_file_as_is(local_q_path, storage_q_path)
        if q_url:
            doc_data['image_url'] = q_url
            stats["new_images"] += 1
        else:
            print(f"    -> ❌ Question Image Missing: {local_q_path}")
            log_result(q_id, "Error: Missing Q Image")
            stats["error"] += 1
            continue 

        sol_url, sol_size = upload_file_as_is(local_sol_path, storage_sol_path)
        if sol_url:
            doc_data['solution_url'] = sol_url
            stats["new_images"] += 1
        else:
            doc_data['solution_url'] = None

        # 6. Firestore Write
        doc_ref = db.collection(COLLECTION_NAME).document()
        
        doc_snap = doc_ref.get()
        if doc_snap.exists:
             if 'createdAt' in doc_data:
                 del doc_data['createdAt']
        
        doc_ref.set(doc_data, merge=True)
        
        print(f"    -> ✅ Success! Logged to CSV.")
        log_result(q_id, "Success")
        stats["success"] += 1
            
    except Exception as e:
        print(f"    -> ERROR processing row {index}: {e}")
        log_result(q_id, f"Error: {e}")
        stats["error"] += 1

# --- REPORT ---
end_time = time.time()
print(f"\n--- Batch Complete ---")
print(f"Skipped (Already Done): {stats['skipped']}")
print(f"New Success: {stats['success']}")
print(f"Errors: {stats['error']}")
print(f"Time Taken: {end_time - start_time:.2f}s")