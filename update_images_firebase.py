import pandas as pd
import firebase_admin
from firebase_admin import credentials, firestore, storage
import os
import mimetypes
import datetime
import time

# --- 1. CONFIGURATION ---
# CREDENTIALS
CREDENTIALS_FILE = 'studysmart-5da53-firebase-adminsdk-fbsvc-ca5974c5e9.json'
STORAGE_BUCKET = 'studysmart-5da53.firebasestorage.app'

# FILES
UPDATE_CSV_FILE = 'Question to update images.csv'
LOG_FILE = 'updateLogs.csv'

# FIREBASE CONFIG
COLLECTION_NAME = 'questions'
STORAGE_ROOT = "Question Bank"

# LOCAL PATHS
BASE_DIR = r"D:\Main\3. Work - Teaching\Projects\Question extractor\Processed_Database"

# --- 2. INITIALIZE FIREBASE ---
if not firebase_admin._apps:
    cred = credentials.Certificate(CREDENTIALS_FILE)
    firebase_admin.initialize_app(cred, {
        'storageBucket': STORAGE_BUCKET
    })

db = firestore.client()
bucket = storage.bucket()

# --- 3. HELPER: UPLOAD ---
def upload_file_overwrite(local_path, destination_path):
    """
    Uploads a file to Firebase Storage, overwriting any existing file at that path.
    Returns the public URL.
    """
    if not os.path.exists(local_path):
        return None
    
    try:
        blob = bucket.blob(destination_path)
        
        # Detect Mime Type
        content_type, _ = mimetypes.guess_type(local_path)
        if content_type is None:
            content_type = 'application/octet-stream'
            
        # Upload
        blob.upload_from_filename(local_path, content_type=content_type)
        blob.make_public()
        
        # Return the fresh URL
        return blob.public_url
    except Exception as e:
        print(f"    ❌ Upload Error: {e}")
        return None

# --- 4. MAIN EXECUTION ---
def run_safe_update():
    print(f"--- 🚀 STARTING SAFE IMAGE UPDATE ---")
    
    # 1. Load CSV
    if not os.path.exists(UPDATE_CSV_FILE):
        print(f"❌ Critical: CSV file '{UPDATE_CSV_FILE}' not found.")
        return

    df = pd.read_csv(UPDATE_CSV_FILE)
    
    # Clean column names
    df.columns = [c.strip() for c in df.columns]
    
    # Rename 'unique_id' to 'question_id' if present, to standardize
    if 'unique_id' in df.columns:
        df.rename(columns={'unique_id': 'question_id'}, inplace=True)

    # --- CLEAN DATAFRAME ---
    # 1. Drop rows where question_id is strictly NaN/None
    df = df.dropna(subset=['question_id'])
    
    # 2. Convert to string and strip whitespace
    df['question_id'] = df['question_id'].astype(str).str.strip()
    
    # 3. Filter out rows that became "nan" string or empty string
    df = df[df['question_id'].str.lower() != 'nan']
    df = df[df['question_id'] != '']
    
    print(f"📋 Loaded {len(df)} VALID rows to process.")
    
    stats = {"updated": 0, "skipped_no_doc": 0, "error": 0, "missing_local_file": 0}
    
    for index, row in df.iterrows():
        try:
            q_id = str(row['question_id']).strip()
            folder_name = str(row['Folder']).strip()
            q_num = str(row['Q']).strip()
            
            print(f"\n[{index+1}/{len(df)}] Processing ID: {q_id}")

            # --- A. RESOLVE PATHS ---
            local_q_path = os.path.join(BASE_DIR, folder_name, f"Q_{q_num}.png")
            local_sol_path = os.path.join(BASE_DIR, folder_name, f"Sol_{q_num}.png")

            # --- STRICT CHECK: SKIP IF Q IMAGE MISSING ---
            if not os.path.exists(local_q_path):
                print(f"    ❌ SKIP: Question image not found locally: {local_q_path}")
                stats["missing_local_file"] += 1
                continue  # <--- Jumps to next row immediately

            # 2. Storage Paths (Apply 'CollegeDoors' -> 'DC' fix)
            if folder_name.startswith("CollegeDoors"):
                target_storage_folder = folder_name.replace("CollegeDoors", "DC", 1)
            else:
                target_storage_folder = folder_name

            storage_q_path = f"{STORAGE_ROOT}/{target_storage_folder}/Q_{q_num}.png"
            storage_sol_path = f"{STORAGE_ROOT}/{target_storage_folder}/Sol_{q_num}.png"

            # --- B. UPLOAD IMAGES (Storage Overwrite) ---
            update_payload = {}
            
            # Question Image (We know it exists because of check above)
            print(f"    found local Q image.. uploading")
            new_q_url = upload_file_overwrite(local_q_path, storage_q_path)
            if new_q_url:
                update_payload['image_url'] = new_q_url

            # Solution Image (Optional - Upload if exists)
            if os.path.exists(local_sol_path):
                 print(f"    found local Sol image.. uploading")
                 new_sol_url = upload_file_overwrite(local_sol_path, storage_sol_path)
                 if new_sol_url:
                     update_payload['solution_url'] = new_sol_url

            # Final Safety: If upload failed for some network reason
            if not update_payload:
                print("    ⚠️ Upload failed (Network?). Skipping Firestore update.")
                continue

            # Add timestamp
            update_payload['lastUpdated'] = firestore.SERVER_TIMESTAMP

            # --- C. UPDATE FIRESTORE (Query & Patch) ---
            docs = db.collection(COLLECTION_NAME).where('question_id', '==', q_id).stream()
            
            doc_found = False
            for doc in docs:
                doc_found = True
                doc_ref = doc.reference
                
                # SAFE UPDATE: Only touches fields in 'update_payload'
                doc_ref.update(update_payload)
                print(f"    ✅ Updated Document: {doc.id}")
                
            if doc_found:
                stats["updated"] += 1
            else:
                print(f"    ⚠️ Warning: No document found in Firestore with question_id='{q_id}'")
                stats["skipped_no_doc"] += 1

        except Exception as e:
            print(f"    ❌ Error: {e}")
            stats["error"] += 1

    # --- REPORT ---
    print(f"\n--- Update Complete ---")
    print(f"Documents Updated: {stats['updated']}")
    print(f"Skipped (ID not found): {stats['skipped_no_doc']}")
    print(f"Skipped (Missing File): {stats['missing_local_file']}")
    print(f"Errors: {stats['error']}")

if __name__ == "__main__":
    run_safe_update()