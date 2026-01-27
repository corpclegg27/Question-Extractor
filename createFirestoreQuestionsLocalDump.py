import firebase_admin
from firebase_admin import credentials
from firebase_admin import firestore
import csv
import datetime

# ================= CONFIGURATION =================
# Path to your Firebase Service Account Key JSON file
SERVICE_ACCOUNT_KEY_PATH = 'serviceAccountKey.json' 

# Collection to scrape
COLLECTION_NAME = 'questions'

# Output filename
OUTPUT_FILENAME = 'Question Bank Firestore Image.csv'

# Limit for testing (Set to None for full export)
LIMIT = None 
# =================================================

def initialize_firebase():
    """Initializes Firebase Admin SDK."""
    if not firebase_admin._apps:
        cred = credentials.Certificate(SERVICE_ACCOUNT_KEY_PATH)
        firebase_admin.initialize_app(cred)
    print("✅ Firebase initialized successfully.")

def format_value(value):
    """
    Helper to format values for CSV.
    - Joins lists with ' | '
    - Converts Timestamps to string
    - Handles None values
    """
    if value is None:
        return ""
    
    if isinstance(value, list):
        # Handle lists (e.g., tags, correctAnswersOneOrMore)
        return " | ".join([str(v) for v in value])
    
    if isinstance(value, datetime.datetime):
        # Handle Firestore Timestamps
        return value.strftime('%Y-%m-%d %H:%M:%S')
    
    return str(value)

def main():
    initialize_firebase()
    db = firestore.client()

    print(f"🚀 Starting scrape of '{COLLECTION_NAME}' collection...")
    if LIMIT:
        print(f"⚠️  TEST MODE: Limiting to {LIMIT} documents.")
    else:
        print("⚠️  FULL MODE: Fetching ALL documents. This may consume significant reads.")

    # 1. Query Firestore
    collection_ref = db.collection(COLLECTION_NAME)
    
    if LIMIT:
        docs = collection_ref.limit(LIMIT).stream()
    else:
        docs = collection_ref.stream()

    # 2. Process Data
    all_rows = []
    all_field_names = set()
    
    # [NEW] List to store the summary metadata for Firestore upload
    questions_summary_list = []
    
    read_count = 0

    print("⏳ Fetching documents...", end="", flush=True)

    for doc in docs:
        read_count += 1
        if read_count % 100 == 0:
            print(f".", end="", flush=True) # Progress dot every 100 docs

        doc_data = doc.to_dict()
        
        # Add the document ID explicitly (useful for QC)
        doc_data['__doc_id'] = doc.id
        
        # --- [NEW] Collect Metadata for static_data ---
        # We try to get 'question_id', falling back to the doc ID if missing
        q_id = doc_data.get('question_id') or doc_data.get('questions_id') or doc.id
        
        summary_item = {
            'question_id': str(q_id),
            'Exam': str(doc_data.get('Exam', '')),
            'Chapter': str(doc_data.get('Chapter', '')),
            'Topic': str(doc_data.get('Topic', ''))
        }
        questions_summary_list.append(summary_item)
        # ---------------------------------------------

        # Process fields for CSV format
        processed_row = {}
        for key, value in doc_data.items():
            processed_row[key] = format_value(value)
            all_field_names.add(key)
        
        all_rows.append(processed_row)

    print(f"\n✅ Fetch complete.")
    print(f"📊 Total Reads Consumed: {read_count}")

    # 3. Sort Headers (Ensure __doc_id is first)
    sorted_headers = sorted(list(all_field_names))
    if '__doc_id' in sorted_headers:
        sorted_headers.remove('__doc_id')
        sorted_headers.insert(0, '__doc_id')

    # 4. Write to CSV
    print(f"💾 Saving to '{OUTPUT_FILENAME}'...")
    try:
        with open(OUTPUT_FILENAME, mode='w', newline='', encoding='utf-8') as csv_file:
            writer = csv.DictWriter(csv_file, fieldnames=sorted_headers)
            
            writer.writeheader()
            writer.writerows(all_rows)
            
        print(f"🎉 Success! Exported {len(all_rows)} rows to {OUTPUT_FILENAME}")
        
    except IOError as e:
        print(f"❌ Error writing CSV file: {e}")

    # 5. [NEW] Write Summary to Firestore
    if questions_summary_list:
        print(f"☁️  Uploading summary ({len(questions_summary_list)} items) to static_data/questionsInDB...")
        try:
            # Note: Firestore documents have a 1MB limit. 
            # If you have > 5,000 questions, this might fail and require chunking.
            summary_ref = db.collection('static_data').document('questionsInDB')
            summary_ref.set({
                'questions_metadata': questions_summary_list,
                'last_updated': firestore.SERVER_TIMESTAMP
            })
            print("✅ Summary uploaded successfully.")
        except Exception as e:
            print(f"❌ Error uploading summary to Firestore: {e}")

if __name__ == "__main__":
    main()