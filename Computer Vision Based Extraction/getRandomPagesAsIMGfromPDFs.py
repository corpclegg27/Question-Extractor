import os
import random
import fitz  # PyMuPDF
from tqdm import tqdm

# --- CONFIGURATION ---
BASE_DIR = r'D:\Main\3. Work - Teaching\Projects\Question extractor\Computer Vision Based Extraction'
PDF_SOURCE_DIR = os.path.join(BASE_DIR, 'pdfs')
OUTPUT_IMAGE_DIR = os.path.join(BASE_DIR, 'Raw images')

# Number of random pages to pick from EACH pdf
N_SAMPLES_PER_PDF = 20 

# Image Quality (DPI)
# 300 DPI is standard for OCR/Vision training
DPI = 300 
ZOOM = DPI / 72  # PyMuPDF default is 72 dpi

def generate_dataset():
    # 1. Create Output Folder
    if not os.path.exists(OUTPUT_IMAGE_DIR):
        os.makedirs(OUTPUT_IMAGE_DIR)
        print(f"📁 Created output folder: {OUTPUT_IMAGE_DIR}")

    # 2. Get list of PDFs
    if not os.path.exists(PDF_SOURCE_DIR):
        print(f"❌ Error: Source folder not found: {PDF_SOURCE_DIR}")
        return

    pdf_files = [f for f in os.listdir(PDF_SOURCE_DIR) if f.lower().endswith('.pdf')]
    
    if not pdf_files:
        print("⚠️ No PDF files found in 'pdfs' folder.")
        return

    print(f"🚀 Found {len(pdf_files)} PDFs. Starting extraction...")

    total_images = 0

    # 3. Process Each PDF
    for pdf_file in pdf_files:
        pdf_path = os.path.join(PDF_SOURCE_DIR, pdf_file)
        safe_name = os.path.splitext(pdf_file)[0].replace(" ", "_")
        
        try:
            doc = fitz.open(pdf_path)
            total_pages = len(doc)
            
            # Determine which pages to pick
            if total_pages <= N_SAMPLES_PER_PDF:
                selected_pages = range(total_pages) # Take all
            else:
                selected_pages = sorted(random.sample(range(total_pages), N_SAMPLES_PER_PDF))
            
            print(f"   📄 {pdf_file}: Extracting {len(selected_pages)} pages...")

            # 4. Render and Save
            mat = fitz.Matrix(ZOOM, ZOOM) # Set high resolution
            
            for pg_num in tqdm(selected_pages, leave=False):
                page = doc.load_page(pg_num)
                pix = page.get_pixmap(matrix=mat, alpha=False)
                
                # Output Filename: PDFName_PageNo.jpg
                out_name = f"{safe_name}_p{pg_num + 1}.jpg"
                out_path = os.path.join(OUTPUT_IMAGE_DIR, out_name)
                
                pix.save(out_path)
                total_images += 1
                
            doc.close()

        except Exception as e:
            print(f"   ❌ Error processing {pdf_file}: {e}")

    print(f"\n✅ DONE. Extracted {total_images} images to '{OUTPUT_IMAGE_DIR}'")

if __name__ == "__main__":
    generate_dataset()