# backfillFixedCounts.py
# Description: One-time script to scan 'attempt_items_detailed', count fixed mistakes, 
# and populate 'smartTimeAnalysisFixedCounts' in 'student_deep_analysis'.

import firebase_admin
from firebase_admin import credentials
from firebase_admin import firestore
import time

# --- CONFIGURATION ---
KEY_PATH = 'serviceAccountKey.json' 

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

def run_backfill():
    print("\n🚀 STARTING FIXED COUNTS BACKFILL")
    print("===================================")
    start_time = time.time()

    # 1. DATA STRUCTURE TO HOLD AGGREGATES
    # Structure:
    # {
    #   "userId": {
    #       "chapters": {
    #           "ChapterName": { "Tag": Count }
    #       },
    #       "topics": {
    #           "ChapterName": {
    #               "TopicName": { "Tag": Count }
    #           }
    #       }
    #   }
    # }
    user_aggregates = {}
    total_docs_scanned = 0
    fixed_items_found = 0

    # 2. SCAN ATTEMPT ITEMS DETAILED
    print("... Scanning attempt_items_detailed (This may take a while)")
    
    # Optimization: Only fetch items that are actually fixed to save memory/processing
    # If you want to be 100% sure, remove the where clause, but this is faster.
    query = db.collection('attempt_items_detailed').where('isMistakeFixed', '==', True)
    docs = query.stream()

    for doc in docs:
        total_docs_scanned += 1
        data = doc.to_dict()
        
        user_id = data.get('userId')
        chapter = data.get('chapter')
        topic = data.get('topic')
        raw_tag = data.get('smartTag', '')
        
        if not user_id or not chapter: continue

        # Extract Short Key (e.g., "Careless Mistake")
        tag_key = raw_tag.split('(')[0].strip()
        if not tag_key: continue

        fixed_items_found += 1

        # Init User Level
        if user_id not in user_aggregates:
            user_aggregates[user_id] = { "chapters": {}, "topics": {} }

        # --- A. AGGREGATE BY CHAPTER ---
        if chapter not in user_aggregates[user_id]["chapters"]:
            user_aggregates[user_id]["chapters"][chapter] = {}
        
        chap_counts = user_aggregates[user_id]["chapters"][chapter]
        chap_counts[tag_key] = chap_counts.get(tag_key, 0) + 1

        # --- B. AGGREGATE BY TOPIC (If exists) ---
        if topic:
            if chapter not in user_aggregates[user_id]["topics"]:
                user_aggregates[user_id]["topics"][chapter] = {}
            
            if topic not in user_aggregates[user_id]["topics"][chapter]:
                user_aggregates[user_id]["topics"][chapter][topic] = {}

            topic_counts = user_aggregates[user_id]["topics"][chapter][topic]
            topic_counts[tag_key] = topic_counts.get(tag_key, 0) + 1

    print(f"✅ Scan Complete. Found {fixed_items_found} fixed items across {len(user_aggregates)} users.")

    # 3. WRITE UPDATES TO FIRESTORE
    print("\n... Writing updates to student_deep_analysis")
    
    batch = db.batch()
    batch_count = 0
    writes_count = 0

    for user_id, data in user_aggregates.items():
        doc_ref = db.collection('student_deep_analysis').document(user_id)
        
        # Build the update dictionary (using Dot Notation for nested updates)
        update_payload = {}

        # Chapter Updates
        for chap_name, counts in data["chapters"].items():
            field_path = f"breakdownByChapter.{chap_name}.smartTimeAnalysisFixedCounts"
            update_payload[field_path] = counts

        # Topic Updates
        for chap_name, topic_map in data["topics"].items():
            for topic_name, counts in topic_map.items():
                field_path = f"breakdownByTopic.{chap_name}.{topic_name}.smartTimeAnalysisFixedCounts"
                update_payload[field_path] = counts

        if update_payload:
            batch.update(doc_ref, update_payload)
            batch_count += 1
            writes_count += 1

        if batch_count >= 400:
            batch.commit()
            print(f"   -> Committed batch of 400 user updates...")
            batch = db.batch()
            batch_count = 0

    if batch_count > 0:
        batch.commit()
        print(f"   -> Committed final batch.")

    duration = time.time() - start_time
    print("\n" + "="*40)
    print("🏁 BACKFILL COMPLETE")
    print(f"⏱️  Time: {round(duration, 2)}s")
    print(f"👥 Users Updated: {writes_count}")
    print("="*40)

if __name__ == "__main__":
    run_backfill()