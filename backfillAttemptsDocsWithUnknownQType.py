import firebase_admin
from firebase_admin import credentials, firestore

# ==========================================
# 1. SETUP & CONFIGURATION
# ==========================================
# [IMPORTANT] Ensure "serviceAccountKey.json" is in the same folder
cred = credentials.Certificate("serviceAccountKey.json") 

# Check if app is initialized; if not, initialize it.
if not firebase_admin._apps:
    firebase_admin.initialize_app(cred)

db = firestore.client()
print("✅ Firebase initialized successfully.")

# ==========================================
# 2. HELPER FUNCTIONS
# ==========================================

def get_config():
    """Fetches grading configuration from static_data/option_sets."""
    default_config = {
        'ideal_time_map': {},
        'careless_factor': 0.25,
        'good_skip_factor': 0.20
    }
    
    try:
        doc = db.collection('static_data').document('option_sets').get()
        if doc.exists:
            data = doc.to_dict()
            default_config['ideal_time_map'] = data.get('idealTimePerQuestion', {})
            default_config['careless_factor'] = float(data.get('factorForCarelessAttempt', 0.25))
            
            raw_skip = float(data.get('factorForGoodSkip', 20.0))
            if raw_skip > 1: raw_skip = raw_skip / 100.0
            default_config['good_skip_factor'] = raw_skip
            
    except Exception as e:
        print(f"⚠️ Warning: Could not fetch config, using defaults. Error: {e}")
        
    return default_config

def get_ideal_time(config_map, exam, subject, q_type):
    e_name = (exam or "JEE Main").replace(" ", "_")
    s_name = (subject or "Physics").replace(" ", "_")
    type_str = "Single_Correct"
    if q_type == "Numerical": type_str = "NumericalType"
    elif q_type == "OneOrMoreOptionsCorrect": type_str = "OneOrMoreOptionsCorrect"
    
    keys_to_try = [f"{e_name}_{s_name}_{type_str}", f"{e_name}_{s_name}", f"{exam}_{subject}"]
    for key in keys_to_try:
        if key in config_map and config_map[key] is not None:
            return int(config_map[key])
    return 120

def calculate_smart_tag(status, time_spent, ideal_time, careless_factor, skip_factor):
    fast_threshold = ideal_time * careless_factor
    good_skip_threshold = ideal_time * skip_factor
    
    if status == "CORRECT":
        return "Perfect Attempt (Correct & answered within reasonable time)" if time_spent <= ideal_time else "Overtime Correct (Correct but took too long)"
    elif status == "INCORRECT" or status == "PARTIALLY_CORRECT":
        return "Careless Mistake (Incorrect & answered too fast)" if time_spent < fast_threshold else "Wasted Attempt (Incorrect & took too long)"
    else:
        return "Good Skip (Skipped quickly)" if time_spent < good_skip_threshold else "Time Wasted (Skipped but spent too much time)"

# ==========================================
# 3. MARKS BREAKDOWN LOGIC (NEW)
# ==========================================

def rebuild_marks_breakdown(responses):
    """
    Reconstructs the hierarchical marks breakdown.
    """
    breakdown = {
        "Overall": {"marksObtained": 0, "maxMarks": 0}
    }

    for q_id, resp in responses.items():
        # Data Extraction
        subject = resp.get('subject', 'Unknown Subject')
        q_type = resp.get('questionType', 'Single Correct') 
        marks = resp.get('marksObtained', 0)
        
        # Determine Max Marks (Assuming +4 for Single Correct)
        current_max_marks = 4 
        
        # 1. Update Overall
        breakdown["Overall"]["marksObtained"] += marks
        breakdown["Overall"]["maxMarks"] += current_max_marks

        # 2. Ensure Subject Key Exists
        if subject not in breakdown:
            breakdown[subject] = {"marksObtained": 0, "maxMarks": 0}
        
        # 3. Update Subject Totals
        breakdown[subject]["marksObtained"] += marks
        breakdown[subject]["maxMarks"] += current_max_marks

        # 4. Ensure Section (Type) Key Exists under Subject
        if q_type not in breakdown[subject]:
            breakdown[subject][q_type] = {"marksObtained": 0, "maxMarks": 0}

        # 5. Update Section Totals
        breakdown[subject][q_type]["marksObtained"] += marks
        breakdown[subject][q_type]["maxMarks"] += current_max_marks

    return breakdown

# ==========================================
# 4. MAIN SCRIPT
# ==========================================

def run_comprehensive_fix():
    # --- INPUTS ---
    attempt_refs = [
        '/attempts/3mMTKfbTI90j9365nxMQ',
        '/attempts/WQ2NMW1ZSYFqca0SDmJx',
        # Add more attempt paths here if needed
    ]
    
    config = get_config()
    batch = db.batch()
    batch_count = 0
    
    print(f"🔥 Starting Comprehensive Fix for {len(attempt_refs)} attempts...")

    for attempt_path in attempt_refs:
        doc_id = attempt_path.split('/')[-1]
        attempt_ref = db.collection('attempts').document(doc_id)
        attempt_doc = attempt_ref.get()
        
        if not attempt_doc.exists:
            print(f"❌ Attempt {doc_id} not found.")
            continue

        data = attempt_doc.to_dict()
        responses = data.get('responses', {})
        
        print(f"\nProcessing Attempt: {doc_id}")
        
        # Aggregates Init
        new_score = 0
        counts = {"CORRECT": 0, "INCORRECT": 0, "SKIPPED": 0}
        high_level_time = {"CORRECT": 0, "INCORRECT": 0, "SKIPPED": 0, "PARTIALLY_CORRECT": 0}
        smart_breakdown = {"Perfect Attempt": 0, "Overtime Correct": 0, "Careless Mistake": 0, "Wasted Attempt": 0, "Good Skip": 0, "Time Wasted": 0}
        analysis_counts = {k: 0 for k in smart_breakdown}

        # --- STEP A: PROCESS RESPONSES ---
        for q_id, resp in responses.items():
            
            # 1. Fix "Unknown" Type
            q_type = resp.get('questionType')
            if q_type in [None, 'Unknown', '']:
                print(f"   Refixing QID {q_id} (Type: '{q_type}')")
                try:
                    # Fix source question
                    db.collection('questions').document(q_id).update({'Question type': 'Single Correct', 'questionType': 'Single Correct'})
                except: pass

                # Update local response logic
                q_type = 'Single Correct'
                resp['questionType'] = 'Single Correct'
                
                selected = resp.get('selectedOption')
                correct = resp.get('correctOption')
                
                if selected and selected == correct:
                    resp['status'] = 'CORRECT'
                    resp['marksObtained'] = 4
                elif selected and selected != correct:
                    resp['status'] = 'INCORRECT'
                    resp['marksObtained'] = -1
                else:
                    resp['status'] = 'SKIPPED'
                    resp['marksObtained'] = 0

            # 2. Recalculate Smart Tag
            status = resp.get('status', 'SKIPPED')
            time_spent = resp.get('timeSpent', 0)
            ideal_t = get_ideal_time(config['ideal_time_map'], resp.get('exam'), resp.get('subject'), q_type)
            
            tag = calculate_smart_tag(status, time_spent, ideal_t, config['careless_factor'], config['good_skip_factor'])
            resp['smartTimeAnalysis'] = tag

            # 3. Aggregate
            new_score += resp.get('marksObtained', 0)
            
            if status == "CORRECT" or status == "PARTIALLY_CORRECT":
                counts["CORRECT"] += 1
                high_level_time["CORRECT"] += time_spent
            elif status == "INCORRECT":
                counts["INCORRECT"] += 1
                high_level_time["INCORRECT"] += time_spent
            else:
                counts["SKIPPED"] += 1
                high_level_time["SKIPPED"] += time_spent
                
            short_tag = tag.split(' (')[0].strip()
            if short_tag in analysis_counts:
                analysis_counts[short_tag] += 1
                smart_breakdown[short_tag] += time_spent

        # --- STEP B: REBUILD MARKS BREAKDOWN ---
        new_marks_breakdown = rebuild_marks_breakdown(responses)
        print(f"   Calculated Overall Score in Breakdown: {new_marks_breakdown['Overall']['marksObtained']}")

        # --- STEP C: UPDATE BATCH ---
        updates = {
            'responses': responses,
            'score': new_score,
            'correctCount': counts["CORRECT"],
            'incorrectCount': counts["INCORRECT"],
            'skippedCount': counts["SKIPPED"],
            'secondsBreakdownHighLevel': high_level_time,
            'smartTimeAnalysisCounts': analysis_counts,
            'secondsBreakdownSmartTimeAnalysis': smart_breakdown,
            'marksBreakdown': new_marks_breakdown, 
            'maxMarks': new_marks_breakdown['Overall']['maxMarks'] 
        }
        
        batch.update(attempt_ref, updates)
        batch_count += 1
        
        if batch_count >= 400:
            batch.commit()
            batch = db.batch()
            batch_count = 0

    if batch_count > 0:
        batch.commit()
    
    print("\n✅ Final Fix Complete.")

if __name__ == "__main__":
    run_comprehensive_fix()