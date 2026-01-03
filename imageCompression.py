import os
import csv
from PIL import Image
from tqdm import tqdm

def get_all_folders(base_dir, exclude_folder="Compressed"):
    """
    Scans the base directory and returns a list of all subfolders 
    excluding the 'Compressed' folder.
    """
    if not os.path.exists(base_dir):
        return []
    
    all_items = os.listdir(base_dir)
    folders = []
    
    for item in all_items:
        item_path = os.path.join(base_dir, item)
        
        # We only want directories, and we MUST skip the 'Compressed' folder
        if os.path.isdir(item_path) and item != exclude_folder:
            folders.append(item)
            
    return folders

def clean_and_compress_all(noise_threshold=170):
    # --- SETUP ---
    base_dir = "Processed_Database"
    compressed_base_dir = os.path.join(base_dir, "Compressed")
    csv_report_path = os.path.join(base_dir, "compression_stats.csv")

    # 1. Auto-discover folders
    folders_to_process = get_all_folders(base_dir, exclude_folder="Compressed")

    if not folders_to_process:
        print(f"No folders found in {base_dir} to process!")
        return

    # Data collection for stats
    stats_data = []
    grand_total_orig_bytes = 0
    grand_total_new_bytes = 0

    print(f"Found {len(folders_to_process)} folders to process.")
    print(f"Report will be saved to: {csv_report_path}\n")

    # --- OUTER LOOP: FOLDERS ---
    for folder_name in tqdm(folders_to_process, desc="Overall Progress", unit="folder", position=0, leave=True):
        input_dir = os.path.join(base_dir, folder_name)
        output_dir = os.path.join(compressed_base_dir, folder_name)

        if not os.path.exists(output_dir):
            os.makedirs(output_dir)

        files = [f for f in os.listdir(input_dir) if f.lower().endswith('.png')]
        
        if not files:
            continue

        folder_orig_bytes = 0
        folder_new_bytes = 0

        # --- INNER LOOP: FILES ---
        for filename in tqdm(files, desc=f"  Processing {folder_name}", leave=True, unit="img", position=1):
            file_path = os.path.join(input_dir, filename)
            save_path = os.path.join(output_dir, filename)

            try:
                # 1. Capture Original Size
                orig_size = os.path.getsize(file_path)
                folder_orig_bytes += orig_size

                # 2. Compress (Smart Grayscale)
                with Image.open(file_path) as img:
                    gray = img.convert('L')
                    # Smart Thresholding
                    cleaned = gray.point(lambda p: 255 if p > noise_threshold else p)
                    cleaned.save(save_path, "PNG", optimize=True)

                # 3. Capture New Size
                new_size = os.path.getsize(save_path)
                folder_new_bytes += new_size

                # 4. Log Data
                savings_pct = ((orig_size - new_size) / orig_size) * 100 if orig_size > 0 else 0
                stats_data.append([
                    folder_name,
                    filename,
                    round(orig_size / 1024, 2),  # KB
                    round(new_size / 1024, 2),   # KB
                    round(savings_pct, 2)
                ])

            except Exception as e:
                tqdm.write(f"❌ Error on {filename}: {e}")

        # Update Grand Totals
        grand_total_orig_bytes += folder_orig_bytes
        grand_total_new_bytes += folder_new_bytes

        # Print Folder Summary
        if folder_orig_bytes > 0:
            folder_savings_pct = ((folder_orig_bytes - folder_new_bytes) / folder_orig_bytes) * 100
            tqdm.write(
                f"✅ {folder_name}: "
                f"Saved {folder_savings_pct:.1f}% "
                f"({folder_orig_bytes/1024/1024:.2f}MB ➝ {folder_new_bytes/1024/1024:.2f}MB)"
            )
        
        tqdm.write("\n") # Spacer

    # --- FINAL REPORT ---
    total_savings_bytes = grand_total_orig_bytes - grand_total_new_bytes
    total_savings_pct = (total_savings_bytes / grand_total_orig_bytes * 100) if grand_total_orig_bytes > 0 else 0

    print("\n" + "="*45)
    print(f"       FINAL COMPRESSION REPORT")
    print("="*45)
    print(f"• Total Images:    {len(stats_data)}")
    print(f"• Original Size:   {grand_total_orig_bytes / 1024 / 1024:.2f} MB")
    print(f"• New Size:        {grand_total_new_bytes / 1024 / 1024:.2f} MB")
    print(f"• Space Saved:     {total_savings_bytes / 1024 / 1024:.2f} MB ({total_savings_pct:.2f}%)")
    print(f"• CSV Report:      {csv_report_path}")
    print("="*45)


clean_and_compress_all()