import pandas as pd
import os
from tqdm import tqdm

# ================= CONFIGURATION =================
CSV_FILE_PATH = 'FilesToUpload.csv'  # Path to your log file
DRY_RUN = False  # Set to False to actually delete files
# =================================================

def clean_up_files():
    if not os.path.exists(CSV_FILE_PATH):
        print(f"Error: Log file '{CSV_FILE_PATH}' not found.")
        return

    print("Reading log file...")
    try:
        df = pd.read_csv(CSV_FILE_PATH)
    except Exception as e:
        print(f"Error reading CSV: {e}")
        return

    # Filter only files that were successfully uploaded
    files_to_delete = df[df['Status'] == 'Uploaded']
    
    total_files = len(files_to_delete)
    deleted_count = 0
    errors_count = 0
    bytes_cleared = 0
    
    print(f"Found {total_files} files marked as 'Uploaded'.")
    
    if total_files == 0:
        print("No files to delete.")
        return

    if DRY_RUN:
        print("\n--- DRY RUN MODE: No files will be deleted ---")
    else:
        print("\n--- DELETING FILES ---")

    # Iterate with progress bar
    for index, row in tqdm(files_to_delete.iterrows(), total=total_files, unit="file"):
        file_path = row['FullPath']
        
        # Check if file exists locally
        if os.path.exists(file_path):
            try:
                file_size = os.path.getsize(file_path)
                
                if not DRY_RUN:
                    os.remove(file_path)
                
                bytes_cleared += file_size
                deleted_count += 1
                
            except Exception as e:
                errors_count += 1
                # tqdm.write allows printing without breaking the progress bar layout
                tqdm.write(f"Error deleting {file_path}: {e}")
        else:
            # File might already be deleted or moved
            if DRY_RUN:
                 tqdm.write(f"Skipping (Not Found): {file_path}")
            errors_count += 1

    # Final Report
    mb_cleared = bytes_cleared / (1024 * 1024)
    gb_cleared = mb_cleared / 1024
    
    print("\n" + "="*30)
    print("       SUMMARY       ")
    print("="*30)
    if DRY_RUN:
        print(f"Mode:          DRY RUN (Simulation)")
        print(f"Would Delete:  {deleted_count} files")
        print(f"Would Reclaim: {mb_cleared:.2f} MB ({gb_cleared:.2f} GB)")
    else:
        print(f"Mode:          LIVE DELETION")
        print(f"Deleted:       {deleted_count} files")
        print(f"Errors/Missing:{errors_count} files")
        print(f"Space Cleared: {mb_cleared:.2f} MB ({gb_cleared:.2f} GB)")
    print("="*30)

if __name__ == "__main__":
    clean_up_files()