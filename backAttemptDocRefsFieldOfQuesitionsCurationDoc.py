import firebase_admin
from firebase_admin import credentials
from firebase_admin import firestore
import pandas as pd
import time

# --- CONFIGURATION ---
KEY_PATH = 'serviceAccountKey.json' 
BATCH_SIZE = 400

# Initialize Firebase
if not firebase_admin._apps:
    try:
        cred = credentials.Certificate(KEY_PATH)
        firebase_admin.initialize_app(cred)
        print("✅ Firebase Initialized.")
    except Exception as e:
        print(f"❌ Error initializing Firebase: {e}")
        exit()

db = firestore.client()

def backfill_curation_refs():
    start_time = time.time()
    print("\n🚀 STARTING BACKFILL: Attempt Refs in Questions Curation")
    print("=======================================================")

    # ==============================================================================
    # STEP 1: SCAN ATTEMPTS (SOURCE OF TRUTH)
    # ==============================================================================
    print("\n[Step 1] Scanning 'attempts' collection...")
    
    attempts_ref = db.collection('attempts')
    docs = attempts_ref.stream()
    
    data_list = []
    count = 0

    for doc in docs:
        d = doc.to_dict()
        source_id = d.get('sourceId')
        user_id = d.get('userId')
        
        # We only care about attempts linked to a curation (sourceId)
        if source_id and user_id:
            data_list.append({
                'sourceId': source_id,
                'attemptDocRef': doc.reference,
                'userDocRef': db.collection('users').document(user_id)
            })
            count += 1
            if count % 1000 == 0:
                print(f"   -> Scanned {count} attempts...")

    print(f"✅ Scanned {count} valid attempts.")
    
    if not data_list:
        print("⚠️ No attempts found with sourceId. Exiting.")
        return

    # Create Dataframe
    df = pd.DataFrame(data_list)
    
    # Group by sourceId (Curation ID)
    # converting the rows into a list of dictionaries for the target structure
    grouped = df.groupby('sourceId').apply(
        lambda x: [
            {'attemptDocRef': row['attemptDocRef'], 'userId': row['userDocRef']} 
            for _, row in x.iterrows()
        ]
    ).to_dict()

    print(f"✅ Processed into {len(grouped)} unique Curation IDs.")

    # ==============================================================================
    # STEP 2: UPDATE CURATION DOCUMENTS
    # ==============================================================================
    print("\n[Step 2] Updating 'questions_curation' documents...")

    curation_ref = db.collection('questions_curation')
    curation_docs = curation_ref.stream()

    batch = db.batch()
    batch_count = 0
    total_updated = 0

    for doc in curation_docs:
        curation_id = doc.id
        
        # 1. Get the Correct List from our DataFrame/Dict
        # If no attempts exist for this curation, we set it to empty list []
        # This effectively "deletes" any old legacy list strings or bad data.
        new_ref_list = grouped.get(curation_id, [])

        # 2. Add to Batch
        # We overwrite 'attemptDocRefs' entirely. 
        # This replaces whatever type (List<Ref> or Array<Map>) was there before.
        batch.update(doc.reference, {
            'attemptDocRefs': new_ref_list
        })
        
        batch_count += 1
        total_updated += 1

        # 3. Commit Batch if full
        if batch_count >= BATCH_SIZE:
            batch.commit()
            print(f"   -> Committed batch of {BATCH_SIZE} updates...")
            batch = db.batch()
            batch_count = 0

    # Final Commit
    if batch_count > 0:
        batch.commit()
        print(f"   -> Committed final batch of {batch_count} updates.")

    duration = time.time() - start_time
    print("\n" + "="*40)
    print("🏁 BACKFILL COMPLETE")
    print(f"⏱️  Time Taken   : {round(duration, 2)} seconds")
    print(f"📄 Docs Updated : {total_updated}")
    print("="*40 + "\n")

if __name__ == "__main__":
    backfill_curation_refs()