# studentAnalytics.py
# Description: Analytics Engine V6.3 (Daily Insights + Time Tracking + Question References).
# - Renamed 'dailyQuestionsBreakdownbyStatus' -> 'dailyQuestionsBreakdown'.
# - Added 'timeSpent' to daily breakdown.
# - [NEW] Added 'qRefAssigned': Maps of lists storing all attempted Question IDs by status.
# - PRESERVES all existing Chapter/Subject/Topic/Detailed Item logic.

import firebase_admin
from firebase_admin import credentials
from firebase_admin import firestore
import copy
import time
from datetime import datetime, timedelta, timezone

# --- CONFIGURATION ---
KEY_PATH = 'serviceAccountKey.json' 

# Set to True to re-read ALL history. 
# CRITICAL: Keep TRUE for this run to populate the new 'timeSpent' field for past dates.
FORCE_FULL_RECALCULATION = True 

# --- GLOBAL METRICS ---
TOTAL_READS = 0
TOTAL_WRITES = 0

# Initialize Firebase
if not firebase_admin._apps:
    try:
        cred = credentials.Certificate(KEY_PATH)
        firebase_admin.initialize_app(cred)
        print("✅ Firebase Initialized Successfully.")
    except Exception as e:
        print(f"❌ Error initializing Firebase: {e}")
        exit()

db = firestore.client()

# Batch config
BATCH_LIMIT = 400

# Valid Smart Categories
SMART_CATEGORIES = [
    "Perfect Attempt", "Overtime Correct", "Careless Mistake", 
    "Wasted Attempt", "Good Skip", "Time Wasted"
]

def generate_analytics():
    global TOTAL_READS, TOTAL_WRITES
    start_time = time.time()
    
    print("\n🚀 STARTING ANALYTICS ENGINE (V6.3 - QREF BUCKETING)")
    print("=====================================================")
    if FORCE_FULL_RECALCULATION:
        print("⚠️  MODE: FORCE FULL RECALCULATION (Reading ALL history)")

    # ==============================================================================
    # 1. READ SYLLABUS SKELETON
    # ==============================================================================
    print("\n[Step 1] Reading Syllabus Tree...")
    
    syllabus_skeleton = {
        "breakdownBySubject": {},
        "breakdownByChapter": {},
        "breakdownByTopic": {} 
    }
    
    try:
        syllabus_doc = db.collection('static_data').document('syllabus').get()
        TOTAL_READS += 1
        
        if syllabus_doc.exists:
            data = syllabus_doc.to_dict()
            raw_subjects = data.get('subjects', {})

            for subj_key, subj_data in raw_subjects.items():
                subject_name = subj_key.capitalize() 
                syllabus_skeleton["breakdownBySubject"][subject_name] = _get_empty_stats_object()

                raw_chapters = subj_data.get('chapters', {})
                for chap_key, chap_data in raw_chapters.items():
                    chapter_name = chap_data.get('name', chap_key)
                    
                    # Init Chapter Stats
                    stats = _get_empty_stats_object()
                    stats['subject'] = subject_name
                    stats['lastCorrectlySolvedAt'] = None
                    syllabus_skeleton["breakdownByChapter"][chapter_name] = stats
                    
                    # Init nested Topic container
                    syllabus_skeleton["breakdownByTopic"][chapter_name] = {}

            print(f"   -> Syllabus Loaded: {len(syllabus_skeleton['breakdownByChapter'])} chapters.")
        else:
            print("   ⚠️ Warning: Syllabus document not found.")
            return
    except Exception as e:
        print(f"   ❌ Error reading syllabus: {e}")
        return

    # ==============================================================================
    # 2. READ ANALYSIS LOGS
    # ==============================================================================
    print("\n[Step 2] Reading Processing Logs...")
    logs_ref = db.collection('static_data').document('studentAnalysisLogs')
    logs_doc = logs_ref.get()
    TOTAL_READS += 1
    
    analysis_logs = {}
    if logs_doc.exists:
        analysis_logs = logs_doc.to_dict()

    # ==============================================================================
    # 3. FETCH STUDENTS
    # ==============================================================================
    print("\n[Step 3] Fetching Student List...")
    users_ref = db.collection('users')
    students_stream = users_ref.where('role', '==', 'student').stream()
    
    students_list = []
    for s in students_stream:
        students_list.append(s)
        TOTAL_READS += 1
        
    print(f"   -> Found {len(students_list)} students.")

    # ==============================================================================
    # 4. PROCESS EACH STUDENT
    # ==============================================================================
    
    batch = db.batch()
    batch_op_count = 0
    updated_logs_buffer = {} 
    
    # Time boundaries
    now = datetime.now(timezone.utc)
    date_30_days_ago = now - timedelta(days=30)
    date_7_days_ago = now - timedelta(days=7)

    for i, user_doc in enumerate(students_list):
        user_id = user_doc.id
        user_data = user_doc.to_dict()
        student_id = str(user_data.get('studentId', 'Unknown'))
        display_name = user_data.get('displayName', 'Unknown')
        
        # --- A. DETERMINE QUERY SCOPE ---
        last_processed_timestamp = analysis_logs.get(user_id)
        
        incremental_query = db.collection('attempts').where('userId', '==', user_id)
        
        if not FORCE_FULL_RECALCULATION and last_processed_timestamp:
            incremental_query = incremental_query.where('completedAt', '>', last_processed_timestamp)
        
        incremental_query = incremental_query.order_by('completedAt')
        new_attempts_stream = incremental_query.stream()

        new_attempts = []
        latest_attempt_time = last_processed_timestamp 

        for att in new_attempts_stream:
            TOTAL_READS += 1
            data = att.to_dict()
            att_time = data.get('completedAt')
            if att_time: 
                if latest_attempt_time is None or att_time > latest_attempt_time:
                    latest_attempt_time = att_time
            new_attempts.append(att)

        if not new_attempts and not FORCE_FULL_RECALCULATION:
            continue 

        print(f"\n   [{i+1}/{len(students_list)}] Processing: {display_name} ({len(new_attempts)} items)")

        # --- Load Existing Analysis ---
        analysis_ref = db.collection('student_deep_analysis').document(user_id)
        analysis_doc = analysis_ref.get()
        TOTAL_READS += 1
        
        aggregator = {}

        if analysis_doc.exists and not FORCE_FULL_RECALCULATION:
            # Incremental Mode: Load existing state
            aggregator = analysis_doc.to_dict()
            
            # Ensure new fields exist if migrating
            if 'breakdownByTopic' not in aggregator:
                aggregator['breakdownByTopic'] = copy.deepcopy(syllabus_skeleton["breakdownByTopic"])
            
            if 'dailyQuestionsBreakdown' not in aggregator:
                aggregator['dailyQuestionsBreakdown'] = {}
            
            if 'dailyQuestionsBreakdownbyChapter' not in aggregator:
                aggregator['dailyQuestionsBreakdownbyChapter'] = {}
                
            if 'qRefAssigned' not in aggregator:
                aggregator['qRefAssigned'] = {
                    "CORRECT": [], "INCORRECT": [], "SKIPPED": [], "PARTIALLY_CORRECT": []
                }
        else:
            # Full Recalc Mode or New User: Start Fresh
            aggregator = {
                "userId": user_id,
                "studentId": student_id,
                "summary": _get_empty_stats_object(),
                "breakdownBySubject": copy.deepcopy(syllabus_skeleton["breakdownBySubject"]),
                "breakdownByChapter": copy.deepcopy(syllabus_skeleton["breakdownByChapter"]),
                "breakdownByTopic": copy.deepcopy(syllabus_skeleton["breakdownByTopic"]),
                "dailyQuestionsBreakdown": {},          
                "dailyQuestionsBreakdownbyChapter": {},
                # [NEW] Add bucket container
                "qRefAssigned": {
                    "CORRECT": [], "INCORRECT": [], "SKIPPED": [], "PARTIALLY_CORRECT": []
                }
            }

        aggregator["lastUpdated"] = firestore.SERVER_TIMESTAMP

        # [NEW] Convert qRefAssigned lists to Sets for O(1) lookups and uniqueness
        q_ref_sets = {
            "CORRECT": set(aggregator.get("qRefAssigned", {}).get("CORRECT", [])),
            "INCORRECT": set(aggregator.get("qRefAssigned", {}).get("INCORRECT", [])),
            "SKIPPED": set(aggregator.get("qRefAssigned", {}).get("SKIPPED", [])),
            "PARTIALLY_CORRECT": set(aggregator.get("qRefAssigned", {}).get("PARTIALLY_CORRECT", [])),
        }

        # --- Process Attempts (Global Stats + Daily) ---
        for attempt in new_attempts:
            att_data = attempt.to_dict()
            attempt_id = attempt.id
            responses = att_data.get('responses', {})
            completed_at = att_data.get('completedAt') # Firestore Timestamp

            if not responses: continue

            # Format Date Key (YYYY-MM-DD)
            date_key = "Unknown"
            if completed_at:
                dt = completed_at
                if hasattr(dt, 'date'): 
                    date_key = dt.strftime("%Y-%m-%d")
                else:
                    date_key = str(dt)[:10]

            for q_id, response in responses.items():
                status = response.get('status', 'SKIPPED')
                subject = response.get('subject', 'Unknown').capitalize() 
                chapter = response.get('chapter', 'Unknown')
                topic = response.get('topic', 'Unknown')
                time_spent = response.get('timeSpent', 0)
                smart_tag = _extract_smart_tag(response.get('smartTimeAnalysis', ""))

                # 1. Global Updates
                _increment_stats(aggregator["summary"], status, time_spent, smart_tag)

                # 2. Subject Updates
                if subject not in aggregator["breakdownBySubject"]:
                    aggregator["breakdownBySubject"][subject] = _get_empty_stats_object()
                _increment_stats(aggregator["breakdownBySubject"][subject], status, time_spent, smart_tag)

                # 3. Chapter Updates
                if chapter not in aggregator["breakdownByChapter"]:
                    stats = _get_empty_stats_object()
                    stats['subject'] = subject
                    stats['lastCorrectlySolvedAt'] = None
                    aggregator["breakdownByChapter"][chapter] = stats
                _increment_stats(aggregator["breakdownByChapter"][chapter], status, time_spent, smart_tag)

                # 4. Topic Updates
                if chapter not in aggregator["breakdownByTopic"]:
                    aggregator["breakdownByTopic"][chapter] = {}
                if topic not in aggregator["breakdownByTopic"][chapter]:
                    aggregator["breakdownByTopic"][chapter][topic] = _get_empty_stats_object()
                _increment_stats(aggregator["breakdownByTopic"][chapter][topic], status, time_spent, smart_tag)

                # 5. Daily Breakdown with Time Spent
                if date_key != "Unknown":
                    if date_key not in aggregator["dailyQuestionsBreakdown"]:
                        aggregator["dailyQuestionsBreakdown"][date_key] = {
                            "total": 0, "correct": 0, "incorrect": 0, "skipped": 0,
                            "timeSpent": 0, 
                            "accuracyPercentage": 0.0, "attemptPercentage": 0.0
                        }
                    
                    daily_stats = aggregator["dailyQuestionsBreakdown"][date_key]
                    daily_stats["total"] += 1
                    daily_stats["timeSpent"] += time_spent
                    
                    if status == 'CORRECT':
                        daily_stats["correct"] += 1
                    elif status == 'INCORRECT' or status == 'PARTIALLY_CORRECT': 
                        daily_stats["incorrect"] += 1
                    else:
                        daily_stats["skipped"] += 1

                # 6. Daily Breakdown by Chapter
                if date_key != "Unknown" and chapter != "Unknown":
                    if date_key not in aggregator["dailyQuestionsBreakdownbyChapter"]:
                        aggregator["dailyQuestionsBreakdownbyChapter"][date_key] = {}
                    
                    daily_chap_map = aggregator["dailyQuestionsBreakdownbyChapter"][date_key]
                    if chapter not in daily_chap_map:
                        daily_chap_map[chapter] = 0
                    daily_chap_map[chapter] += 1

                # 7. Spaced Repetition
                if status == 'CORRECT' and completed_at:
                    current_last = aggregator["breakdownByChapter"][chapter].get('lastCorrectlySolvedAt')
                    if _should_update_timestamp(current_last, completed_at):
                        aggregator["breakdownByChapter"][chapter]['lastCorrectlySolvedAt'] = completed_at

                # 8. [NEW] Update qRefAssigned Sets (Additive)
                # Normalize status to ensure it matches our bucket keys
                bucket_key = status
                if bucket_key not in q_ref_sets:
                    bucket_key = "SKIPPED" # Fallback
                q_ref_sets[bucket_key].add(q_id)

                # 9. Detailed Log
                if not FORCE_FULL_RECALCULATION:
                    detailed_item = {
                        "userId": user_id,
                        "studentId": student_id,
                        "questionId": q_id,
                        "attemptId": attempt_id,
                        "attemptedAt": completed_at,
                        "subject": subject,
                        "chapter": chapter,
                        "topic": topic,
                        "exam": response.get('exam'),
                        "difficulty": response.get('difficultyTag'),
                        "isPyq": response.get('pyq') == "Yes",
                        "status": status,
                        "timeSpent": time_spent,
                        "selectedOption": response.get('selectedOption'),
                        "correctOption": response.get('correctOption'),
                        "smartTag": response.get('smartTimeAnalysis', ""), 
                        "mistakeCategory": response.get('mistakeCategory'),
                        "mistakeNote": response.get('mistakeNote')
                    }
                    
                    new_doc_ref = db.collection('attempt_items_detailed').document()
                    batch.set(new_doc_ref, detailed_item)
                    batch_op_count += 1
                    TOTAL_WRITES += 1

                    if batch_op_count >= BATCH_LIMIT:
                        batch.commit()
                        batch = db.batch()
                        batch_op_count = 0

        # --- D. ROLLING STATS ---
        aggregator["summary_lastWeek"] = _get_empty_stats_object()
        aggregator["summary_lastMonth"] = _get_empty_stats_object()

        recent_query = db.collection('attempts')\
            .where('userId', '==', user_id)\
            .where('completedAt', '>=', date_30_days_ago)\
            .stream()
            
        for recent_att in recent_query:
            TOTAL_READS += 1
            r_data = recent_att.to_dict()
            r_responses = r_data.get('responses', {})
            r_completed_at = r_data.get('completedAt')
            
            if not r_completed_at: continue
            is_in_last_7 = r_completed_at >= date_7_days_ago
            
            for q_id, response in r_responses.items():
                status = response.get('status', 'SKIPPED')
                time_spent = response.get('timeSpent', 0)
                smart_tag = _extract_smart_tag(response.get('smartTimeAnalysis', ""))

                _increment_stats(aggregator["summary_lastMonth"], status, time_spent, smart_tag)
                if is_in_last_7:
                    _increment_stats(aggregator["summary_lastWeek"], status, time_spent, smart_tag)

        # --- E. FINALIZE CALCULATIONS ---
        
        # 1. Standard aggregations
        _recalculate_percentages(aggregator["summary"])
        for s in aggregator["breakdownBySubject"].values():
            _recalculate_percentages(s)
        for c in aggregator["breakdownByChapter"].values():
            _recalculate_percentages(c)
        for chap_key, topic_map in aggregator["breakdownByTopic"].items():
            for topic_key, topic_stats in topic_map.items():
                _recalculate_percentages(topic_stats)

        # 2. Rolling aggregations
        _recalculate_percentages(aggregator["summary_lastWeek"])
        _recalculate_percentages(aggregator["summary_lastMonth"])

        # 3. Daily Breakdown Percentages
        if "dailyQuestionsBreakdown" in aggregator:
            for date_key, daily_stats in aggregator["dailyQuestionsBreakdown"].items():
                _recalculate_percentages(daily_stats)

        # 4. [NEW] Convert Sets back to Lists for Firestore Storage
        aggregator["qRefAssigned"] = {
            "CORRECT": list(q_ref_sets["CORRECT"]),
            "INCORRECT": list(q_ref_sets["INCORRECT"]),
            "SKIPPED": list(q_ref_sets["SKIPPED"]),
            "PARTIALLY_CORRECT": list(q_ref_sets["PARTIALLY_CORRECT"])
        }

        # --- F. SAVE UPDATES ---
        
        batch.set(analysis_ref, aggregator) 
        batch_op_count += 1
        TOTAL_WRITES += 1
        
        user_stats_payload = {
            "stats": aggregator["summary"],
            "stats_lastWeek": aggregator["summary_lastWeek"],
            "stats_lastMonth": aggregator["summary_lastMonth"]
        }
        
        user_ref = db.collection('users').document(user_id)
        batch.set(user_ref, user_stats_payload, merge=True)
        batch_op_count += 1
        TOTAL_WRITES += 1
        
        if latest_attempt_time:
            updated_logs_buffer[user_id] = latest_attempt_time

        if batch_op_count >= BATCH_LIMIT:
            batch.commit()
            batch = db.batch()
            batch_op_count = 0

    # ==============================================================================
    # 5. FINAL COMMIT
    # ==============================================================================
    
    if batch_op_count > 0:
        batch.commit()
        print("   -> Committed final data batch.")

    if updated_logs_buffer:
        print(f"   -> Updating Logs for {len(updated_logs_buffer)} students...")
        logs_ref.set(updated_logs_buffer, merge=True)
        TOTAL_WRITES += 1

    end_time = time.time()
    duration = end_time - start_time

    print("\n" + "="*40)
    print("🏁 UPDATE COMPLETE")
    print("="*40)
    print(f"⏱️  Time Taken   : {round(duration, 2)} seconds")
    print(f"📖 Total Reads  : {TOTAL_READS}")
    print(f"✍️  Total Writes : {TOTAL_WRITES}")
    print("="*40 + "\n")


# --- HELPER FUNCTIONS ---

def _get_empty_stats_object():
    """Returns a fresh dictionary for stats counting."""
    smart_counts = { tag: 0 for tag in SMART_CATEGORIES }
    return {
        "total": 0,
        "correct": 0,
        "incorrect": 0,
        "skipped": 0,
        "timeSpent": 0,
        "accuracyPercentage": 0.0,
        "attemptPercentage": 0.0,
        "smartTimeAnalysisCounts": smart_counts
    }

def _extract_smart_tag(raw_tag):
    if not raw_tag: return "Unknown"
    return raw_tag.split('(')[0].strip()

def _increment_stats(stats_dict, status, time_spent, smart_tag):
    """Updates counts in place."""
    stats_dict["total"] += 1
    stats_dict["timeSpent"] += time_spent
    
    if status == 'CORRECT':
        stats_dict["correct"] += 1
    elif status == 'INCORRECT' or status == 'PARTIALLY_CORRECT':
        stats_dict["incorrect"] += 1
    else:
        stats_dict["skipped"] += 1
        
    if "smartTimeAnalysisCounts" not in stats_dict:
        stats_dict["smartTimeAnalysisCounts"] = { tag: 0 for tag in SMART_CATEGORIES }
        
    if smart_tag in SMART_CATEGORIES:
        stats_dict["smartTimeAnalysisCounts"][smart_tag] += 1

def _recalculate_percentages(stats_dict):
    """Calculates accuracy and attempt % based on current totals."""
    total = stats_dict["total"]
    correct = stats_dict["correct"]
    incorrect = stats_dict["incorrect"]
    
    # Attempted = Correct + Incorrect (Skipped is ignored for attempted count)
    attempted_count = correct + incorrect
    
    if attempted_count > 0:
        stats_dict["accuracyPercentage"] = round((correct / attempted_count) * 100, 2)
    else:
        stats_dict["accuracyPercentage"] = 0.0

    if total > 0:
        stats_dict["attemptPercentage"] = round((attempted_count / total) * 100, 2)
    else:
        stats_dict["attemptPercentage"] = 0.0

def _should_update_timestamp(current, new):
    if current is None: return True
    try:
        return new > current
    except:
        return True

if __name__ == "__main__":
    generate_analytics()