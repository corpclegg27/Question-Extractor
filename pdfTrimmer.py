import os
import json
from pypdf import PdfReader, PdfWriter

# --- 1. CONFIGURATION ---
# Using BASE_PATH directly as requested [cite: 300, 417]
CONFIG_PATH = 'config.json'
BASE_PATH = 'D:/Main/3. Work - Teaching/Projects/Question extractor'

# Load from config if available, otherwise use the hardcoded path above [cite: 74, 259]
if os.path.exists(CONFIG_PATH):
    with open(CONFIG_PATH, 'r') as f:
        config = json.load(f)
    BASE_PATH = config.get('BASE_PATH', BASE_PATH)

SOURCE_DIR = os.path.join(BASE_PATH, 'raw data')
# Dedicated folder for trimmed versions to keep the 'raw data' root clean [cite: 340, 413]
OUTPUT_DIR = os.path.join(SOURCE_DIR, 'Trimmed_PDFs')

os.makedirs(OUTPUT_DIR, exist_ok=True)

def trim_pdf(input_filename, start_page, end_page, chapter_label):
    """
    Extracts a specific page range and saves it as a new 'Trimmed' file.
    """
    input_path = os.path.join(SOURCE_DIR, input_filename)
    
    # Naming convention: Trimmed_[Label]_pages.pdf [cite: 288, 412]
    output_filename = f"Trimmed_{chapter_label}_p{start_page}_to_p{end_page}_{input_filename}.pdf"
    output_path = os.path.join(OUTPUT_DIR, output_filename)

    if not os.path.exists(input_path):
        print(f"❌ Error: Source file not found: {input_path}")
        return

    try:
        reader = PdfReader(input_path)
        writer = PdfWriter()

        total_pages = len(reader.pages)
        # Adjust end_page if it exceeds actual document length [cite: 278, 309]
        actual_end = min(end_page, total_pages)
        
        print(f"📂 Reading: {input_filename}")
        print(f"✂️  Extracting range: {start_page} to {actual_end}...")

        # Add pages (pypdf uses 0-based indexing) [cite: 327, 374]
        for i in range(start_page - 1, actual_end):
            writer.add_page(reader.pages[i])

        with open(output_path, "wb") as output_file:
            writer.write(output_file)

        print(f"✅ Success! Saved as: {output_path}")
        return output_path

    except Exception as e:
        print(f"❌ Extraction failed: {e}")

if __name__ == "__main__":
    # --- UPDATE THESE PARAMETERS FOR EACH CHAPTER ---
    FILE_NAME = "PYQs NEET Disha 33 Years NEET Solved Papers - Physics.pdf" 
    CHAPTER_NAME = "Rotational motion"
    START = 76   # Starting page number (as seen in PDF viewer)
    END = 96    # Ending page number (as seen in PDF viewer)

    trim_pdf(FILE_NAME, START, END, CHAPTER_NAME)