import firebase_admin
from firebase_admin import credentials
from firebase_admin import firestore
from google.cloud.firestore import FieldFilter
import csv
import sys

# ================= CONFIGURATION =================
SERVICE_ACCOUNT_KEY = 'serviceAccountKey.json' 
OUTPUT_FILENAME = 'Firestore Questions Pivot.csv'

TARGET_EXAMS = ['NEET', 'JEE Main', 'JEE Advanced']
TARGET_TYPES = ['Single Correct', 'One or more options correct', 'Numerical type']
# =================================================

def initialize_firebase():
    if not firebase_admin._apps:
        cred = credentials.Certificate(SERVICE_ACCOUNT_KEY)
        firebase_admin.initialize_app(cred)
    print("✅ Firebase initialized.")

def get_count_safe(db, exam, q_type):
    collection_ref = db.collection('questions')
    
    # [FINAL FIX] Manually quote the field with backticks (`).
    # The error 400 explicitly requested a "quoted property path" for fields with spaces.
    # We leave 'Exam' unquoted as it has no spaces.
    
    try:
        # Filter 1: Exam (No spaces, safe)
        f1 = FieldFilter("Exam", "==", exam)
        
        # Filter 2: Question type (Has spaces, MUST be backticked for Aggregations)
        f2 = FieldFilter("`Question type`", "==", q_type)

        # Apply filters
        query = collection_ref.where(filter=f1).where(filter=f2)
        
        # Aggregation
        aggregate_query = query.count()
        snapshot = aggregate_query.get()
        
        return snapshot[0][0].value
        
    except Exception as e:
        # Fallback: Try without backticks if the specific library version double-escapes
        try:
            f2_fallback = FieldFilter("Question type", "==", q_type)
            query = collection_ref.where(filter=f1).where(filter=f2_fallback)
            aggregate_query = query.count()
            snapshot = aggregate_query.get()
            return snapshot[0][0].value
        except:
            print(f"   [Debug] Failed query for '{q_type}'. Error: {e}")
            return 0

def main():
    initialize_firebase()
    db = firestore.client()

    print(f"🚀 Starting Pivot Analysis (0 Reads Strategy)...")
    print(f"📋 Targets: {len(TARGET_EXAMS)} Exams, {len(TARGET_TYPES)} Types")
    print("-" * 60)

    rows = []
    
    for exam in TARGET_EXAMS:
        print(f"🔎 Analyzing {exam}...", end=" ", flush=True)
        row = {'Exam': exam}
        total = 0
        
        for q_type in TARGET_TYPES:
            count = get_count_safe(db, exam, q_type)
            row[q_type] = count
            total += count
                
        row['Total Count'] = total
        rows.append(row)
        print(f"Done. (Total: {total})")

    # Export
    print("-" * 60)
    print(f"💾 Saving to '{OUTPUT_FILENAME}'...")
    
    headers = ['Exam', 'Total Count'] + TARGET_TYPES
    
    try:
        with open(OUTPUT_FILENAME, mode='w', newline='', encoding='utf-8') as f:
            writer = csv.DictWriter(f, fieldnames=headers)
            writer.writeheader()
            writer.writerows(rows)
        print(f"🎉 Success! File generated.")
    except IOError as e:
        print(f"❌ File Error: {e}")

if __name__ == "__main__":
    main()