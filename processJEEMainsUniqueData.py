import pandas as pd
import os
import re

# --- CONFIGURATION ---
BASE_PATH = r'D:\Main\3. Work - Teaching\Projects\Question extractor'
# This matches the output from the extraction script
CSV_PATH = os.path.join(BASE_PATH, 'JEE_Mains_Unique_Questions.csv')

def process_jee_data():
    if not os.path.exists(CSV_PATH):
        print(f"❌ File not found: {CSV_PATH}")
        return

    print(f"📂 Loading {CSV_PATH}...")
    df = pd.read_csv(CSV_PATH)
    print(f"   Loaded {len(df)} rows.")
    
    # --- 1. SET DEFAULTS ---
    print("   🔹 Setting PYQ='Yes' and initializing PYQ_Year=0...")
    df['PYQ'] = 'Yes'
    
    # Initialize Year as 0 (int)
    df['PYQ_Year'] = 0

    # --- 2. DETERMINE QUESTION TYPE ---
    print("   🔹 Classifying Question Types...")
    
    def get_question_type(val):
        # Handle Empty/NaN -> Default to Numerical per instructions
        if pd.isna(val) or str(val).strip() == "":
            return "Numerical type"
            
        # Convert to string and clean (handle 4.0 -> "4")
        s_val = str(val).split('.')[0].strip()
        
        # Check against Single Correct keys
        if s_val in ['1', '2', '3', '4']:
            return "Single Correct"
        else:
            return "Numerical type"

    df['Question type'] = df['Correct Answer'].apply(get_question_type)

    # --- 3. EXTRACT PYQ YEAR FROM TEXT ---
    print("   🔹 Extracting Years from pdf_Text...")
    
    def extract_year(text):
        if pd.isna(text): return 0
        
        # Regex to find [JEE (Main)-2019] pattern
        # Captures the 4 digits inside the parenthesis
        match = re.search(r'\[JEE \(Main\)-(\d{4})\]', str(text))
        if match:
            return int(match.group(1))
        return 0 # Default if pattern not found

    # Apply extraction logic
    df['PYQ_Year'] = df['pdf_Text'].apply(extract_year)

    # --- 4. STATS & SAVE ---
    print(f"\n   📊 Processing Summary:")
    print(f"      - Single Correct Questions: {sum(df['Question type'] == 'Single Correct')}")
    print(f"      - Numerical Type Questions: {sum(df['Question type'] == 'Numerical type')}")
    print(f"      - Years Successfully Extracted: {sum(df['PYQ_Year'] > 0)}")

    # Overwrite the file with processed data
    df.to_csv(CSV_PATH, index=False)
    print(f"\n✅ Updated CSV saved to: {CSV_PATH}")

if __name__ == "__main__":
    process_jee_data()