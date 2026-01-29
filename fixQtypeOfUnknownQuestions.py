import firebase_admin
from firebase_admin import credentials, firestore
import os

# ==========================================
# 1. SETUP
# ==========================================
key_filename = "serviceAccountKey.json"
if not os.path.exists(key_filename):
    raise FileNotFoundError(f"❌ '{key_filename}' not found. Please add it to this folder.")

cred = credentials.Certificate(key_filename)
if not firebase_admin._apps:
    firebase_admin.initialize_app(cred)

db = firestore.client()
print("✅ Firebase initialized.")

# ==========================================
# 2. INPUT DATA
# ==========================================
# List of 'question_id' strings (from your 'Unknown' array)
question_ids_to_fix = [
    "38667", "38917", "38756", "38776", "38905", 
    "38820", "38836", "39204", "38829", "38789", 
    "38896", "39239", "39215", "38678", "39171"
]

# ==========================================
# 3. UPDATE LOGIC
# ==========================================
def fix_question_types():
    print(f"🔥 Starting fix for {len(question_ids_to_fix)} questions...")
    
    batch = db.batch()
    batch_count = 0
    updated_count = 0
    
    # We must query because we don't know the Doc ID, only the 'question_id' field
    collection_ref = db.collection('questions')

    for q_custom_id in question_ids_to_fix:
        # 1. Query for the document where question_id == value
        # Note: Depending on your DB, 'question_id' might be stored as string or number.
        # We try string first as per your input.
        query = collection_ref.where('question_id', '==', q_custom_id).limit(1)
        results = list(query.stream())

        # fallback: try as integer if string search fails
        if not results:
            try:
                int_id = int(q_custom_id)
                query = collection_ref.where('question_id', '==', int_id).limit(1)
                results = list(query.stream())
            except ValueError:
                pass

        if not results:
            print(f"   ❌ Question with custom ID '{q_custom_id}' NOT FOUND.")
            continue

        # 2. Prepare Update
        doc_snapshot = results[0]
        doc_ref = doc_snapshot.reference
        
        # Update both casing conventions to be safe
        batch.update(doc_ref, {
            'Question type': 'Single Correct', 
            'questionType': 'Single Correct'
        })
        
        print(f"   ✅ Queued update for ID: {q_custom_id} (Doc: {doc_snapshot.id})")
        updated_count += 1
        batch_count += 1

        # 3. Commit in batches of 400
        if batch_count >= 400:
            batch.commit()
            print("   --- Batch Committed ---")
            batch = db.batch()
            batch_count = 0

    # Final Commit
    if batch_count > 0:
        batch.commit()
        print("   --- Final Batch Committed ---")

    print(f"\n✨ Job Complete. Updated {updated_count} documents.")

if __name__ == "__main__":
    fix_question_types()