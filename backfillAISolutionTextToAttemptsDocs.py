import firebase_admin
from firebase_admin import credentials
from firebase_admin import firestore
import time

# ================= CONFIGURATION =================
SERVICE_ACCOUNT_PATH = 'serviceAccountKey.json'
BATCH_SIZE = 400  

# [CRITICAL] SET TO False ONLY WHEN YOU ARE SURE
# True = Will only print logs, won't touch DB.
# False = Will write changes to DB.
DRY_RUN = False 
# =================================================

def initialize_firebase():
    if not firebase_admin._apps:
        cred = credentials.Certificate(SERVICE_ACCOUNT_PATH)
        firebase_admin.initialize_app(cred)
    return firestore.client()

def chunk_list(lst, n):
    for i in range(0, len(lst), n):
        yield lst[i:i + n]

def backfill_solutions():
    db = initialize_firebase()
    
    print("🛡️  SAFETY MODE: " + ("ON (DRY RUN)" if DRY_RUN else "OFF (LIVE UPDATES)"))
    print("🚀 Starting AI Solution Backfill...")

    # --- STEP 1: Scan Attempts & Collect Unique Question IDs ---
    print("\n[Step 1] Scanning attempts to find missing solutions...")
    attempts_ref = db.collection('attempts')
    # Using stream() is memory efficient
    all_attempts = list(attempts_ref.stream())
    
    unique_question_ids = set()
    attempt_map = {} # Map attempt_id -> list of questions needing update

    for att in all_attempts:
        data = att.to_dict()
        responses = data.get('responses', {})
        
        if not responses:
            continue

        questions_needing_update = []
        for q_id, resp_data in responses.items():
            # SAFETY CHECK: Only target items missing the field
            if 'AIgenSolutionText' not in resp_data:
                unique_question_ids.add(q_id)
                questions_needing_update.append(q_id)
        
        if questions_needing_update:
            attempt_map[att.id] = questions_needing_update

    print(f"   📋 Scanned {len(all_attempts)} attempts.")
    print(f"   🔍 Found {len(unique_question_ids)} unique questions referenced that need checking.")

    if not unique_question_ids:
        print("   ✅ All attempts already have solution text. Exiting.")
        return

    # --- STEP 2: Fetch AI Solutions for these Questions ---
    print("\n[Step 2] Fetching available solutions from 'questions' collection...")
    
    solutions_map = {} # q_id -> AIgenSolutionText
    # Convert string IDs to Document References
    question_refs = [db.collection('questions').document(qid) for qid in unique_question_ids]
    
    found_count = 0
    
    # Process in chunks of 100 to avoid 'Request payload size exceeds the limit'
    for chunk in chunk_list(question_refs, 100):
        docs = db.get_all(chunk)
        for doc in docs:
            if doc.exists:
                q_data = doc.to_dict()
                sol_text = q_data.get('AIgenSolutionText')
                # Only care if solution text actually exists and is not empty
                if sol_text and isinstance(sol_text, str) and len(sol_text) > 0:
                    solutions_map[doc.id] = sol_text
                    found_count += 1

    print(f"   💡 Found {found_count} questions that actually have AI Solutions generated.")

    if found_count == 0:
        print("   ⚠️ No solutions found in questions collection. Run the generation script first.")
        return

    # --- STEP 3: Update Attempts Documents ---
    print("\n[Step 3] Preparing updates...")
    
    batch = db.batch()
    batch_op_count = 0
    total_docs_updated = 0

    for att_doc in all_attempts:
        att_id = att_doc.id
        
        if att_id not in attempt_map:
            continue

        relevant_q_ids = attempt_map[att_id]
        updates = {}
        
        for q_id in relevant_q_ids:
            if q_id in solutions_map:
                # ---------------------------------------------------------
                # SAFETY MECHANISM: DOT NOTATION
                # e.g. "responses.17915.AIgenSolutionText"
                # This ensures we DO NOT overwrite the entire 'responses' map.
                # We only inject this one specific field into the specific map item.
                # ---------------------------------------------------------
                field_path = f"responses.{q_id}.AIgenSolutionText"
                updates[field_path] = solutions_map[q_id]

        if updates:
            doc_ref = db.collection('attempts').document(att_id)
            
            if DRY_RUN:
                print(f"   [DRY RUN] Would update doc {att_id}: Adding {len(updates)} solution fields.")
                # print(f"       Example Path: {list(updates.keys())[0]}") 
            else:
                batch.update(doc_ref, updates)
                batch_op_count += 1
            
            total_docs_updated += 1

            # Commit batch if limit reached
            if not DRY_RUN and batch_op_count >= BATCH_SIZE:
                batch.commit()
                print(f"   💾 Committed batch of {batch_op_count} documents...")
                batch = db.batch()
                batch_op_count = 0
                time.sleep(0.5)

    # Final commit
    if not DRY_RUN and batch_op_count > 0:
        batch.commit()
        print(f"   💾 Committed final batch of {batch_op_count} documents.")

    if DRY_RUN:
        print(f"\n🏁 DRY RUN COMPLETE. {total_docs_updated} documents would have been updated.")
        print("   👉 Set DRY_RUN = False in the script to apply these changes.")
    else:
        print(f"\n🏁 SUCCESS. Updated {total_docs_updated} attempts with new solution text.")

if __name__ == "__main__":
    backfill_solutions()