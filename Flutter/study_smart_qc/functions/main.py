# functions/main.py
from firebase_functions import https_fn, options
from firebase_admin import initialize_app, firestore, get_app
from groq import Groq
import os

initialize_app()

# [CRITICAL CHANGE] Switch to "Maverick" (128 Experts) for better reasoning.
# Scout (16 Experts) is too weak for complex physics.
MODEL_ID = "meta-llama/llama-4-maverick-17b-128e-instruct"

@https_fn.on_call(
    secrets=["GROQ_API_KEY"], 
    region="us-central1",
    timeout_sec=60, 
    memory=options.MemoryOption.GB_1
)
def generate_ai_solution(req: https_fn.CallableRequest) -> dict:
    """
    Generates a textbook-quality solution using Llama 4 Maverick (Vision).
    """
    db = firestore.client()
    
    question_id = req.data.get("questionId")
    if not question_id:
        raise https_fn.HttpsError(code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT, message="Missing questionId")

    doc_ref = db.collection("questions").document(question_id)
    doc = doc_ref.get()

    if not doc.exists:
        raise https_fn.HttpsError(code=https_fn.FunctionsErrorCode.NOT_FOUND, message="Question not found")

    data = doc.to_dict()
    
    # Check Cache
    existing_solution = data.get("AIgenSolutionText")
    if existing_solution and len(str(existing_solution).strip()) > 20:
        return {"solution": existing_solution, "source": "cache"}

    # Validate Image URL (Primary Input)
    image_url = data.get("image_url")
    if not image_url or not image_url.startswith("http"):
        raise https_fn.HttpsError(code=https_fn.FunctionsErrorCode.FAILED_PRECONDITION, message="Invalid Image URL")

    # Metadata
    exam = data.get("exam", "Competitive Exam")
    topic = data.get("topic", "Physics")
    correct_ans = data.get("correctAnswer", "Unknown")

    # [PROMPT] optimized for Natural Flow (No "Step 1" headers)
    prompt = f"""
    You are an expert Physics professor writing a solution for a {exam} textbook.

    **Task:**
    Analyze the image provided and solve the problem.
    
    **Guidelines:**
    1. **Primary Source:** Read the numbers and circuit diagram directly from the image.
    2. **Tone:** Write a continuous, natural explanation. Do NOT use numbered lists like "Step 1", "Phase 1". 
       - Bad: "Step 1: Identify variables. Step 2: Formula."
       - Good: "For a potentiometer circuit, the internal resistance is given by..."
    3. **Math:** Use LaTeX for all equations (e.g., $V = IR$).
    4. **Goal:** Derive the result that matches Option '{correct_ans}'. Bold the final answer.
    """

    try:
        api_key = os.environ.get("GROQ_API_KEY")
        client = Groq(api_key=api_key)
        
        completion = client.chat.completions.create(
            model=MODEL_ID,
            messages=[
                {
                    "role": "user", 
                    "content": [
                        {"type": "text", "text": prompt}, 
                        # [IMAGE PRIMARY] Llama 4 Maverick supports this natively
                        {"type": "image_url", "image_url": {"url": image_url}}
                    ]
                }
            ],
            temperature=0.1, # Low temperature for precision
            max_tokens=1024
        )
        
        solution_text = completion.choices[0].message.content
        
        doc_ref.update({
            "AIgenSolutionText": solution_text,
            "lastUpdated": firestore.SERVER_TIMESTAMP
        })
        
        return {"solution": solution_text, "source": "generated"}

    except Exception as e:
        print(f"AI Error: {e}")
        raise https_fn.HttpsError(code=https_fn.FunctionsErrorCode.INTERNAL, message=f"AI Error: {str(e)}")