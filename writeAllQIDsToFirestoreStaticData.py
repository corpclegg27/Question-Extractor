import firebase_admin
from firebase_admin import credentials
from firebase_admin import firestore
import csv
import math

# ================= CONFIGURATION =================
SERVICE_ACCOUNT_KEY_PATH = 'serviceAccountKey.json'
INPUT_CSV_FILENAME = 'Question Bank Firestore Image.csv'
COLLECTION_NAME = 'static_data'
BASE_DOC_NAME = 'questionsInDB'
CHUNK_SIZE = 2000  # Number of questions per document (Safe limit for 1MB)
# =================================================

def initialize_firebase():
    if not firebase_admin._apps:
        cred = credentials.Certificate(SERVICE_ACCOUNT_KEY_PATH)
        firebase_admin.initialize_app(cred)
    print("✅ Firebase initialized successfully.")

def get_preferred_id(row):
    """
    Tries to find the best ID from the available CSV columns.
    """
    if row.get('question_id'): return row['question_id']
    if row.get('questions_id'): return row['questions_id']
    if row.get('__doc_id'): return row['__doc_id']
    return "UNKNOWN_ID"

def main():
    initialize_firebase()
    db = firestore.client()

    print(f"📂 Reading CSV: {INPUT_CSV_FILENAME}...")
    
    metadata_list = []
    
    try:
        with open(INPUT_CSV_FILENAME, mode='r', encoding='utf-8') as csv_file:
            reader = csv.DictReader(csv_file)
            
            for row in reader:
                # Extract only specific fields
                item = {
                    'question_id': get_preferred_id(row),
                    'Exam': row.get('Exam', ''),
                    'Chapter': row.get('Chapter', ''),
                    'Topic': row.get('Topic', '')
                }
                metadata_list.append(item)
                
    except FileNotFoundError:
        print(f"❌ Error: Could not find '{INPUT_CSV_FILENAME}'. Make sure the CSV file exists.")
        return

    total_items = len(metadata_list)
    print(f"📊 Loaded {total_items} questions from CSV.")

    # Calculate chunks
    total_shards = math.ceil(total_items / CHUNK_SIZE)
    print(f"🧩 Splitting into {total_shards} shards (Max {CHUNK_SIZE} items per doc)...")

    batch = db.batch()
    
    for i in range(total_shards):
        start_idx = i * CHUNK_SIZE
        end_idx = start_idx + CHUNK_SIZE
        chunk = metadata_list[start_idx:end_idx]
        
        # Create a document name: questionsInDB_shard_1, questionsInDB_shard_2, etc.
        doc_name = f"{BASE_DOC_NAME}_shard_{i+1}"
        doc_ref = db.collection(COLLECTION_NAME).document(doc_name)
        
        doc_data = {
            'questions_metadata': chunk,
            'shard_index': i + 1,
            'total_shards': total_shards,
            'count': len(chunk),
            'last_updated': firestore.SERVER_TIMESTAMP
        }
        
        batch.set(doc_ref, doc_data)
        print(f"   🔹 Prepared {doc_name} ({len(chunk)} items)")

    # Commit all shards
    print("☁️  Uploading to Firestore...")
    try:
        batch.commit()
        print(f"✅ Successfully uploaded {total_shards} documents to '{COLLECTION_NAME}' collection.")
    except Exception as e:
        print(f"❌ Error uploading to Firestore: {e}")

if __name__ == "__main__":
    main()