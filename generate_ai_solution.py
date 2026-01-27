import firebase_admin
from firebase_admin import credentials
from firebase_admin import firestore
import csv
import time
from groq import Groq

# ================= CONFIGURATION =================
SERVICE_ACCOUNT_PATH = 'serviceAccountKey.json'
INPUT_CSV = 'Add AI Generated Solutions.csv'
GROQ_API_KEY = "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"

# Use a Vision-capable model. Llama 3.2 90b Vision is excellent for this.
MODEL_ID = "meta-llama/llama-4-scout-17b-16e-instruct" 
# =================================================

# Initialize Firebase
if not firebase_admin._apps:
    cred = credentials.Certificate(SERVICE_ACCOUNT_PATH)
    firebase_admin.initialize_app(cred)

db = firestore.client()
groq_client = Groq(api_key=GROQ_API_KEY)

def get_solution_from_ai(image_url, context_data):
    """
    Sends image + context to Groq Vision model to generate a solution.
    """
    exam = context_data.get('Exam', 'Competitive Exam')
    subject = context_data.get('Subject', 'Science')
    topic = context_data.get('Topic', '')
    correct_ans = context_data.get('Correct Answer', 'Unknown')

    prompt = f"""
    You are an expert tutor for {exam} {subject}. 
    
    **Task:** Solve the question provided in the image step-by-step.
    
    **Context:**
    - Topic: {topic}
    - The Correct Option is: {correct_ans} (Use this to verify your logic).
    
    **Formatting Rules (CRITICAL):**
    1. Output purely the solution. No conversational filler ("Here is the solution...").
    2. Use **Markdown** for text formatting (bold key terms).
    3. Use **LaTeX** for ALL mathematical expressions, formulas, and units.
    4. Wrap inline math in single dollar signs (e.g., $F = ma$).
    5. Wrap block equations in double dollar signs (e.g., $$ E = mc^2 $$).
    6. Keep the explanation concise but clear, suitable for a high school student.
    """

    try:
        completion = groq_client.chat.completions.create(
            model=MODEL_ID,
            messages=[
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": prompt},
                        {"type": "image_url", "image_url": {"url": image_url}}
                    ]
                }
            ],
            temperature=0.3,
            max_tokens=1024,
            top_p=1,
            stream=False,
        )
        return completion.choices[0].message.content
    except Exception as e:
        print(f"   ❌ AI Error: {e}")
        return None

def process_questions():
    print(f"🚀 Starting AI Solution Generation using {MODEL_ID}...")
    
    try:
        with open(INPUT_CSV, mode='r', encoding='utf-8-sig') as csv_file:
            reader = csv.DictReader(csv_file)
            rows = list(reader)
    except FileNotFoundError:
        print(f"❌ Error: Could not find {INPUT_CSV}")
        return

    total = len(rows)
    print(f"📋 Found {total} questions to process.\n")

    for i, row in enumerate(rows):
        q_id_short = row.get('question_id', '').strip()
        q_ref_long = row.get('question_ref', '').strip()
        
        doc_ref = None
        doc_snapshot = None

        # 1. Fetch Document
        if q_ref_long:
            doc_ref = db.collection('questions').document(q_ref_long)
            doc_snapshot = doc_ref.get()
        
        if (not doc_snapshot or not doc_snapshot.exists) and q_id_short:
            query = db.collection('questions').where('question_id', '==', q_id_short).limit(1).stream()
            for doc in query:
                doc_snapshot = doc
                doc_ref = doc.reference
                break
        
        if not doc_snapshot or not doc_snapshot.exists:
            print(f"[{i+1}/{total}] ⚠️  Skipping: Document not found ({q_id_short or q_ref_long})")
            continue

        data = doc_snapshot.to_dict()
        
        # ==============================================================================
        # 2. CHECK: SKIP IF SOLUTION EXISTS (SAVES TOKENS)
        # ==============================================================================
        existing_solution = data.get('AIgenSolutionText')
        if existing_solution and len(str(existing_solution).strip()) > 10:
            print(f"[{i+1}/{total}] ⏭️  Skipping: AI Solution already exists for {doc_snapshot.id}")
            continue
        # ==============================================================================

        image_url = data.get('image_url')
        if not image_url or not image_url.startswith('http'):
            print(f"[{i+1}/{total}] ⚠️  Skipping: Invalid Image URL for {doc_snapshot.id}")
            continue

        print(f"[{i+1}/{total}] 🧠 Solving Question {q_id_short} ({doc_snapshot.id})...")

        # 3. Generate Solution
        solution_text = get_solution_from_ai(image_url, data)

        if solution_text:
            # 4. Update Firestore
            doc_ref.update({
                'AIgenSolutionText': solution_text,
                'lastUpdated': firestore.SERVER_TIMESTAMP
            })
            print(f"   ✅ Saved Solution! (Length: {len(solution_text)} chars)")
            time.sleep(1) # Rate limiting
        else:
            print("   ❌ Failed to generate solution.")

    print("\n🏁 Process Complete.")

if __name__ == "__main__":
    process_questions()