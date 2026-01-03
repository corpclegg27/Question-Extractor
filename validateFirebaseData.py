import firebase_admin
from firebase_admin import credentials, firestore
import pandas as pd
from collections import defaultdict

# --- CONFIGURATION ---
CREDENTIALS_FILE = 'studysmart-5da53-firebase-adminsdk-fbsvc-ca5974c5e9.json'
COLLECTION_NAME = 'questions'

# --- DEFINING EXPECTED SCHEMA ---
# Define the strict type you expect for each field.
# Use (int, float) if a field can be either.
# Use type(None) if a field is allowed to be null.

EXPECTED_SCHEMA = {
    'question_id': str,
    'Folder': str,
    'image_url': str,         # Must be a string (URL)
    'solution_url': (str, type(None)), # Can be string OR null
    
    # Fields from your CSV (Adjust these based on what you want)
    'Q': (int, float, str),   # Often mixed; best to enforce one, but we check for all here
    'Topic': str,
    'Subtopic': str
}

# Fields that MUST exist in every document
REQUIRED_FIELDS = ['question_id', 'image_url', 'Folder']

# --- INITIALIZE ---
if not firebase_admin._apps:
    cred = credentials.Certificate(CREDENTIALS_FILE)
    firebase_admin.initialize_app(cred)

db = firestore.client()

def get_type_name(value):
    return type(value).__name__

print(f"--- Starting Validation on '{COLLECTION_NAME}' ---")

# 1. Fetch All Documents
docs_stream = db.collection(COLLECTION_NAME).stream()

total_docs = 0
error_log = []
type_distribution = defaultdict(lambda: defaultdict(int))

print("Scanning documents...")

for doc in docs_stream:
    total_docs += 1
    data = doc.to_dict()
    doc_id = doc.id
    
    # A. Check Required Fields
    for field in REQUIRED_FIELDS:
        if field not in data:
            error_log.append({
                "doc_id": doc_id, 
                "error": "Missing Required Field", 
                "field": field, 
                "value": "MISSING"
            })
            continue

        # Check for Null in Required Fields
        if data[field] is None:
            error_log.append({
                "doc_id": doc_id,
                "error": "Required Field is Null",
                "field": field,
                "value": "None"
            })

    # B. Check Data Types & Schema
    for key, value in data.items():
        # Record the type distribution (for summary stats)
        val_type = type(value)
        type_distribution[key][val_type.__name__] += 1
        
        # If we have a rule for this field, validate it
        if key in EXPECTED_SCHEMA:
            expected = EXPECTED_SCHEMA[key]
            if not isinstance(value, expected):
                # If it's a float equivalent to an int (e.g., 10.0), it might be okay, but we flag it strict
                error_log.append({
                    "doc_id": doc_id,
                    "error": f"Type Mismatch (Expected {expected})",
                    "field": key,
                    "value": f"{value} ({type(value).__name__})"
                })

# --- REPORTING ---

print(f"\n--- Validation Complete: Scanned {total_docs} documents ---")

# 1. Show Type Distribution (To catch "Mixed" fields)
print("\n[Field Type Summary]")
print(f"{'Field':<20} | {'Types Found (Count)'}")
print("-" * 60)
for field, types in type_distribution.items():
    type_desc = ", ".join([f"{t} ({c})" for t, c in types.items()])
    print(f"{field:<20} | {type_desc}")
    
    # Warn if a field has multiple types (excluding None)
    non_none_types = [t for t in types.keys() if t != 'NoneType']
    if len(non_none_types) > 1:
        print(f"   >>> WARNING: Field '{field}' has mixed types! {non_none_types}")

# 2. Show Errors
if error_log:
    print(f"\n[Found {len(error_log)} Specific Errors]")
    df_errors = pd.DataFrame(error_log)
    
    # Display first 10 errors
    print(df_errors.head(10).to_string(index=False))
    
    # Save to CSV
    csv_filename = "validation_errors.csv"
    df_errors.to_csv(csv_filename, index=False)
    print(f"\nFull error log saved to: {csv_filename}")
else:
    print("\n[SUCCESS] No schema violations found.")