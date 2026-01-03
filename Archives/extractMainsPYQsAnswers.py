import pdfplumber
import os
import re
import pandas as pd

# --- CONFIGURATION ---
DEFAULT_PATH = r"D:\Main\3. Work - Teaching\Books\0. Favs\JEE Mains PYQs\Physics - 02 - Capacitance.pdf"

def extract_and_debug_answers(pdf_path):
    if not os.path.exists(pdf_path):
        print(f"❌ File not found: {pdf_path}")
        return

    print(f"📂 Reading: {os.path.basename(pdf_path)}")
    print("-" * 50)

    extracted_data = []
    
    with pdfplumber.open(pdf_path) as pdf:
        total_pages = len(pdf.pages)
        
        # Scan last 5 pages
        start_page = max(0, total_pages - 5)
        
        for i in range(start_page, total_pages):
            page = pdf.pages[i]
            text = page.extract_text()
            if not text: continue
            
            # --- THE STRICT REGEX ---
            # Matches: "1. (2)", "4. (93)", "86. (A)"
            # Group 1: Question Number
            # Group 2: Answer content inside ()
            pattern = r'(\d+)\.\s*\(([^)]+)\)'
            
            matches = re.findall(pattern, text)
            
            for q_num, ans_val in matches:
                extracted_data.append({
                    'Page': i + 1,
                    'Raw_Match': f"{q_num}. ({ans_val})",
                    'Question No.': int(q_num),
                    'Answer': ans_val
                })

    # --- DATAFRAME CREATION ---
    if extracted_data:
        df = pd.DataFrame(extracted_data)
        
        # Sort by Question Number to spot gaps easily
        df = df.sort_values(by='Question No.').reset_index(drop=True)
        
        print(f"\n✅ Extraction Complete. Found {len(df)} answers.")
        print("-" * 50)
        
        # Display options to show all rows
        pd.set_option('display.max_rows', None)
        pd.set_option('display.max_columns', None)
        pd.set_option('display.width', 1000)
        
        print(df[['Question No.', 'Answer', 'Page']])
        print("-" * 50)
        
        # Check for duplicates
        if df['Question No.'].duplicated().any():
            print("⚠️ WARNING: Duplicate Question Numbers found!")
            print(df[df['Question No.'].duplicated(keep=False)])
            
    else:
        print("❌ No answers found. Regex didn't match anything.")

if __name__ == "__main__":
    user_input = input(f"Enter PDF Path (Press Enter for default): ").strip().strip('"')
    path = user_input if user_input else DEFAULT_PATH
    
    extract_and_debug_answers(path)