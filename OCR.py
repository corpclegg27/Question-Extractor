import pandas as pd
import easyocr
import os

def update_ocr_to_csv():
    # 1. Configuration
    master_path = "DB Master.xlsx" 
    output_csv = "DB Master_OCR.csv"
    BASE_PATH = r"D:\Main\3. Work - Teaching\Projects\Question extractor\Processed_Database" 
    model_storage = r"D:\Main\3. Work - Teaching\Projects\Question extractor\models"
    
    # 2. Load Logic: Check if we have an existing CSV to resume from
    if os.path.exists(output_csv):
        print(f"Resuming from existing CSV: {output_csv}")
        df = pd.read_csv(output_csv)
    else:
        print(f"Reading fresh from Master: {master_path}")
        # We still read the Master XLSX (Read-Only)
        df = pd.read_excel(master_path, engine='openpyxl')
    
    if 'OCR_Text' not in df.columns:
        df['OCR_Text'] = ""

    # 3. Filter for blank rows
    is_blank = df['OCR_Text'].isna() | (df['OCR_Text'].astype(str).str.strip() == "")
    rows_to_process = df[is_blank]

    if rows_to_process.empty:
        print("No blank rows found. Everything is already OCR-ed in the CSV.")
        return

    print(f"Found {len(rows_to_process)} rows to process.\n")

    # 4. Initialize Engine
    reader = easyocr.Reader(['en'], model_storage_directory=model_storage)

    # 5. Processing Loop
    try:
        for index in rows_to_process.index:
            folder_name = str(df.at[index, 'Folder']).strip()
            q_number = str(df.at[index, 'Q']).strip() 
            img_filename = f"Q_{q_number}.png"
            img_path = os.path.join(BASE_PATH, folder_name, img_filename)
            
            print(f"Processing: {img_path}")
            
            if os.path.exists(img_path):
                try:
                    result = reader.readtext(img_path, detail=0)
                    df.at[index, 'OCR_Text'] = " ".join(result)
                    
                    # SAVE TO CSV IMMEDIATELY (Highly reliable)
                    df.to_csv(output_csv, index=False)
                    print(f"Success. Saved to {output_csv}\n")
                    
                except Exception as e:
                    print(f"!!! OCR Error on row {index}: {e}\n")
            else:
                print(f"SKIP: File not found.\n")
    except KeyboardInterrupt:
        print("\nScript stopped by user. Progress is saved in the CSV.")

    print(f"Task complete. Master file remains safe. Data is in {output_csv}")

if __name__ == "__main__":
    update_ocr_to_csv()