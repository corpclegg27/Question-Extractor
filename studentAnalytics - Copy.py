import firebase_admin
from firebase_admin import credentials
from firebase_admin import firestore
import copy
import time
from datetime import datetime, timedelta, timezone

# --- CONFIGURATION ---
KEY_PATH = 'serviceAccountKey.json' 

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
    
    print("\n🚀 STARTING ANALYTICS ENGINE (V4 - WITH ROLLING STATS)")
    print("=======================================================")

    # ==============================================================================
    # 1. READ SYLLABUS SKELETON
    # ==============================================================================
    print("\n[Step 1] Reading Syllabus Tree...")
    
    syllabus_skeleton = {
        "breakdownBySubject": {},
        "breakdownByChapter": {}
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
                    stats = _get_empty_stats_object()
                    stats['subject'] = subject_name
                    stats['lastCorrectlySolvedAt'] = None
                    syllabus_skeleton["breakdownByChapter"][chapter_name] = stats
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
    
    # Time boundaries for Rolling Stats
    now = datetime.now(timezone.utc)
    date_30_days_ago = now - timedelta(days=30)
    date_7_days_ago = now - timedelta(days=7)

    for i, user_doc in enumerate(students_list):
        user_id = user_doc.id
        user_data = user_doc.to_dict()
        student_id = str(user_data.get('studentId', 'Unknown'))
        display_name = user_data.get('displayName', 'Unknown')
        
        # --- A. INCREMENTAL UPDATE (ALL TIME STATS) ---
        last_processed_timestamp = analysis_logs.get(user_id)
        
        # Query NEW Attempts (Incremental)
        incremental_query = db.collection('attempts').where('userId', '==', user_id)
        if last_processed_timestamp:
            incremental_query = incremental_query.where('completedAt', '>', last_processed_timestamp)
        
        incremental_query = incremental_query.order_by('completedAt')
        new_attempts_stream = incremental_query.stream()

        new_attempts = []
        latest_attempt_time = last_processed_timestamp 

        for att in new_attempts_stream:
            TOTAL_READS += 1
            data = att.to_dict()
            att_time = data.get('completedAt')
            if att_time: latest_attempt_time = att_time
            new_attempts.append(att)

        # Even if no new attempts, we might need to recalculate Rolling Stats if time passed
        # But for optimization, we usually only run deep analysis if there's activity. 
        # For this script, we'll proceed if there are new attempts OR if it's a manual run.
        if not new_attempts:
            # Uncomment if you want to force update rolling stats even for inactive students
            # pass 
            continue 

        print(f"\n   [{i+1}/{len(students_list)}] Processing: {display_name} ({len(new_attempts)} new)")

        # --- Load Existing Analysis ---
        analysis_ref = db.collection('student_deep_analysis').document(user_id)
        analysis_doc = analysis_ref.get()
        TOTAL_READS += 1
        
        aggregator = {}

        if analysis_doc.exists:
            aggregator = analysis_doc.to_dict()
            # Migrations
            if 'overall' in aggregator: aggregator['summary'] = aggregator.pop('overall')
            if 'chapters' in aggregator: aggregator['breakdownByChapter'] = aggregator.pop('chapters')
            if 'breakdownBySubject' not in aggregator:
                 aggregator['breakdownBySubject'] = copy.deepcopy(syllabus_skeleton["breakdownBySubject"])
        else:
            # Fresh Init
            aggregator = {
                "userId": user_id,
                "studentId": student_id,
                "summary": _get_empty_stats_object(),
                "breakdownBySubject": copy.deepcopy(syllabus_skeleton["breakdownBySubject"]),
                "breakdownByChapter": copy.deepcopy(syllabus_skeleton["breakdownByChapter"])
            }

        aggregator["lastUpdated"] = firestore.SERVER_TIMESTAMP

        # --- Process Incremental Attempts (Global Stats) ---
        for attempt in new_attempts:
            att_data = attempt.to_dict()
            attempt_id = attempt.id
            responses = att_data.get('responses', {})
            completed_at = att_data.get('completedAt')

            if not responses: continue

            for q_id, response in responses.items():
                status = response.get('status', 'SKIPPED')
                subject = response.get('subject', 'Unknown').capitalize() 
                chapter = response.get('chapter', 'Unknown')
                topic = response.get('topic', 'Unknown')
                time_spent = response.get('timeSpent', 0)
                smart_tag = _extract_smart_tag(response.get('smartTimeAnalysis', ""))

                # 1. Update Global Stats
                _increment_stats(aggregator["summary"], status, time_spent, smart_tag)

                if subject not in aggregator["breakdownBySubject"]:
                    aggregator["breakdownBySubject"][subject] = _get_empty_stats_object()
                _increment_stats(aggregator["breakdownBySubject"][subject], status, time_spent, smart_tag)

                if chapter not in aggregator["breakdownByChapter"]:
                    stats = _get_empty_stats_object()
                    stats['subject'] = subject
                    stats['lastCorrectlySolvedAt'] = None
                    aggregator["breakdownByChapter"][chapter] = stats
                _increment_stats(aggregator["breakdownByChapter"][chapter], status, time_spent, smart_tag)

                # 2. Spaced Repetition
                if status == 'CORRECT' and completed_at:
                    current_last = aggregator["breakdownByChapter"][chapter].get('lastCorrectlySolvedAt')
                    if _should_update_timestamp(current_last, completed_at):
                        aggregator["breakdownByChapter"][chapter]['lastCorrectlySolvedAt'] = completed_at

                # 3. Create Granular Detail Doc (Only for new attempts)
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

        # --- B. ROLLING STATS (Recalculate Fresh) ---
        # We perform a separate query for the last 30 days to ensure accuracy.
        # This overwrites whatever was in summary_lastWeek/Month with fresh accurate data.
        
        # Initialize empty containers
        aggregator["summary_lastWeek"] = _get_empty_stats_object()
        aggregator["summary_lastMonth"] = _get_empty_stats_object()

        recent_query = db.collection('attempts')\
            .where('userId', '==', user_id)\
            .where('completedAt', '>=', date_30_days_ago)\
            .stream()
            
        rolling_attempts_found = 0
        
        for recent_att in recent_query:
            TOTAL_READS += 1
            rolling_attempts_found += 1
            r_data = recent_att.to_dict()
            r_responses = r_data.get('responses', {})
            r_completed_at = r_data.get('completedAt')
            
            # Defensive check for timezone aware comparison
            if not r_completed_at: continue
            
            # Ensure timestamps are compatible
            # Firestore returns datetime with tz, our 'date_7_days_ago' has tz
            
            is_in_last_7 = r_completed_at >= date_7_days_ago
            
            for q_id, response in r_responses.items():
                status = response.get('status', 'SKIPPED')
                time_spent = response.get('timeSpent', 0)
                smart_tag = _extract_smart_tag(response.get('smartTimeAnalysis', ""))

                # Always add to Last Month (since query is >= 30 days)
                _increment_stats(aggregator["summary_lastMonth"], status, time_spent, smart_tag)
                
                # Conditionally add to Last Week
                if is_in_last_7:
                    _increment_stats(aggregator["summary_lastWeek"], status, time_spent, smart_tag)

        # --- C. FINALIZE CALCULATIONS ---
        
        # 1. Recalculate Global Percentages
        _recalculate_percentages(aggregator["summary"])
        for s in aggregator["breakdownBySubject"].values():
            _recalculate_percentages(s)
        for c in aggregator["breakdownByChapter"].values():
            _recalculate_percentages(c)
            
        # 2. Recalculate Rolling Percentages
        _recalculate_percentages(aggregator["summary_lastWeek"])
        _recalculate_percentages(aggregator["summary_lastMonth"])

        # --- D. SAVE UPDATES ---
        
        # 1. Update Deep Analysis Doc
        batch.set(analysis_ref, aggregator) 
        batch_op_count += 1
        TOTAL_WRITES += 1
        
        # 2. Update User Profile Stats (High-Level Summary + Rolling)
        user_stats_payload = {
            "stats": aggregator["summary"],
            "stats_lastWeek": aggregator["summary_lastWeek"],
            "stats_lastMonth": aggregator["summary_lastMonth"]
        }
        
        user_ref = db.collection('users').document(user_id)
        batch.set(user_ref, user_stats_payload, merge=True)
        batch_op_count += 1
        TOTAL_WRITES += 1
        
        # Buffer log update
        updated_logs_buffer[user_id] = latest_attempt_time

        if batch_op_count >= BATCH_LIMIT:
            batch.commit()
            batch = db.batch()
            batch_op_count = 0

    # ==============================================================================
    # 5. FINAL COMMIT & LOG UPDATE
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
    print("🏁 INCREMENTAL + ROLLING UPDATE COMPLETE")
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
    """Updates counts in place (Incrementally)."""
    stats_dict["total"] += 1
    stats_dict["timeSpent"] += time_spent
    
    if status == 'CORRECT':
        stats_dict["correct"] += 1
    elif status == 'INCORRECT':
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
    
    # Accuracy: Correct / (Correct + Incorrect)
    attempted_count = correct + incorrect
    if attempted_count > 0:
        stats_dict["accuracyPercentage"] = round((correct / attempted_count) * 100, 2)
    else:
        stats_dict["accuracyPercentage"] = 0.0

    # Attempt Rate: (Correct + Incorrect) / Total Presented
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

# --- ENTRY POINT ---
if __name__ == "__main__":
    generate_analytics()