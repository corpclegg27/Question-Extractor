# migrateToFirebaseAllen.py

import pandas as pd
import firebase_admin
from firebase_admin import credentials, firestore, storage
import os
import datetime
import json
import csv
from tqdm import tqdm

# --- 1. CONFIGURATION ---
CREDENTIALS_FILE = 'studysmart-5da53-firebase-adminsdk-fbsvc-ca5974c5e9.json'
STORAGE_BUCKET = 'studysmart-5da53.firebasestorage.app'
ALLEN_CSV_PATH = 'Question Bank Allen - Firebase.csv'
LOG_FILE_PATH = 'migrationLogsAllen.csv'
COLLECTION_NAME = 'questions'

# Local Base Directory for images
BASE_IMAGE_DIR = r"D:\Main\3. Work - Teaching\Projects\Question extractor\Processed_Database"
STORAGE_ROOT = "Question Bank"

# Initialize Firebase
if not firebase_admin._apps:
    cred = credentials.Certificate(CREDENTIALS_FILE)
    firebase_admin.initialize_app(cred, {'storageBucket': STORAGE_BUCKET})

db = firestore.client()
bucket = storage.bucket()

def upload_image_to_storage(local_path, remote_path):
    if not os.path.exists(local_path):
        return None
    blob = bucket.blob(remote_path)
    blob.upload_from_filename(local_path)
    blob.make_public()
    return blob.public_url

def log_migration(q_id, doc_ref):
    """Appends migration success to the Allen log file."""
    file_exists = os.path.isfile(LOG_FILE_PATH)
    with open(LOG_FILE_PATH, mode='a', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        if not file_exists:
            writer.writerow(['question_id', 'lastUpdated', 'firestore_doc_ref'])
        writer.writerow([q_id, datetime.datetime.now().isoformat(), doc_ref])

def run_migration():
    if not os.path.exists(ALLEN_CSV_PATH):
        print(f"❌ CSV not found: {ALLEN_CSV_PATH}")
        return

    # Load data
    df = pd.read_csv(ALLEN_CSV_PATH)

    # Ensure columns exist and fix the float64/object dtype warning
    if 'toBeUploadedtoFirebase' not in df.columns:
        df['toBeUploadedtoFirebase'] = 'No'
    
    if 'uploadedtoFirebase' not in df.columns:
        df['uploadedtoFirebase'] = 'No'
    
    # Cast to object to prevent "FutureWarning: Setting an item of incompatible dtype"
    df['uploadedtoFirebase'] = df['uploadedtoFirebase'].astype(str)

    # Filter targets
    target_df = df[(df['toBeUploadedtoFirebase'] == 'Yes') & (df['uploadedtoFirebase'] != 'Yes')]
    
    if target_df.empty:
        print("ℹ️ No questions ready for upload.")
        return

    print(f"🚀 Found {len(target_df)} questions to migrate...")

    for index, row in tqdm(target_df.iterrows(), total=len(target_df), desc="Migrating"):
        try:
            # Use unique_id as the document ID and the question_id field
            q_id = str(int(row['unique_id']))
            folder_name = str(row['Folder'])
            q_num = str(int(row['Question No.']))
            
            # 1. Construct local image path
            local_img_path = os.path.join(BASE_IMAGE_DIR, folder_name, f"Q_{q_num}.png")
            
            if not os.path.exists(local_img_path):
                continue

            # 2. Upload to Storage
            storage_path = f"{STORAGE_ROOT}/{folder_name}/Q_{q_num}.png"
            image_url = upload_image_to_storage(local_img_path, storage_path)
            
            if not image_url:
                continue

            # 3. Prepare Firestore Data (Schema Mapping)
            current_time = datetime.datetime.now()
            doc_data = {
                'question_id': int(row['unique_id']), # Replaced unique_id with question_id
                'Question No.': int(row['Question No.']),
                'Subject': str(row['Subject']),
                'Chapter': str(row['Chapter']),
                'Topic': str(row.get('Topic', 'Unknown')),
                'Topic_L2': str(row.get('Topic_L2', 'Unknown')),
                'Correct Answer': str(row['Correct Answer']),
                'Exam': str(row['Exam']),
                'Difficulty': str(row.get('Difficulty', 'Medium')),
                'PYQ': str(row.get('PYQ', 'No')),
                'pdf_Text': str(row.get('pdf_Text', '')),
                'image_url': image_url,
                'q_width': int(row.get('q_width', 0)),
                'q_height': int(row.get('q_height', 0)),
                'lastUpdated': current_time,          # Added lastUpdated field
                'createdAt': current_time,
                'source': 'Allen Module'
            }

            # 4. Firestore Write
            doc_ref = db.collection(COLLECTION_NAME).document(q_id)
            
            # Don't overwrite createdAt if it already exists
            snap = doc_ref.get()
            if snap.exists:
                if 'createdAt' in doc_data:
                    del doc_data['createdAt']

            doc_ref.set(doc_data, merge=True)

            # 5. Log & Update CSV
            log_migration(q_id, f"{COLLECTION_NAME}/{q_id}")
            
            df.at[index, 'uploadedtoFirebase'] = 'Yes'
            
            # Save CSV status incrementally
            try:
                df.to_csv(ALLEN_CSV_PATH, index=False)
            except PermissionError:
                print(f"\n❌ Error: Close {ALLEN_CSV_PATH} in Excel to allow status updates!")
                break

        except Exception as e:
            print(f"\n❌ Failed ID {row.get('unique_id')}: {e}")

    print("\n🏁 Migration task complete.")

if __name__ == "__main__":
    run_migration()