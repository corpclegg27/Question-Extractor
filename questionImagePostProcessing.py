import os
import cv2
import numpy as np
import csv
from tqdm import tqdm

# --- CONFIGURATION ---
TARGET_ROOT_FOLDER = r"D:\Main\3. Work - Teaching\Projects\Question extractor\Processed_Database\Question Number Edge Cases"
ERROR_LOG_FILE = "processing_errors.csv"

# --- LOGIC PARAMETERS ---
SCAN_WIDTH_RATIO = 0.30
INK_THRESHOLD = 2
MERGE_GAP_TOLERANCE = 15
CUT_PADDING = 10

def process_and_overwrite(image_path):
    try:
        # 1. Load Image (Safe for Unicode paths)
        stream = open(image_path, "rb")
        bytes = bytearray(stream.read())
        numpyarray = np.asarray(bytes, dtype=np.uint8)
        img = cv2.imdecode(numpyarray, cv2.IMREAD_UNCHANGED)
        stream.close()
        
        if img is None: return "Error: Read Failed"
        
        # BUG FIX: Handle Grayscale Images safely
        # Check if image has 3 dimensions (Color) and 4 channels (Alpha)
        if len(img.shape) == 3 and img.shape[2] == 4:
            trans_mask = img[:,:,3] == 0
            img[trans_mask] = [255, 255, 255, 255]
            img = cv2.cvtColor(img, cv2.COLOR_BGRA2BGR)
        
        # 2. Binary Conversion
        if len(img.shape) == 3:
            gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        else:
            gray = img # Already grayscale
            
        _, binary = cv2.threshold(gray, 200, 255, cv2.THRESH_BINARY_INV)
        height, width = binary.shape

        # 3. Vertical Projection
        scan_width = int(width * SCAN_WIDTH_RATIO)
        projection = np.sum(binary[:, :scan_width], axis=0) / 255
        has_ink = projection > INK_THRESHOLD

        # 4. Smart Block Finding
        blocks = [] 
        in_block = False
        start_x = 0
        
        x = 0
        while x < len(has_ink):
            if has_ink[x]:
                if not in_block:
                    in_block = True
                    start_x = x
            else:
                if in_block:
                    # Look-Ahead logic
                    is_real_gap = True
                    look_ahead_range = min(x + MERGE_GAP_TOLERANCE, len(has_ink))
                    
                    for k in range(x + 1, look_ahead_range):
                        if has_ink[k]:
                            is_real_gap = False
                            x = k - 1 
                            break
                    
                    if is_real_gap:
                        in_block = False
                        end_x = x
                        if (end_x - start_x) > 3:
                            blocks.append({'start': start_x, 'end': end_x})
            x += 1
            
        if in_block:
            end_x = len(has_ink)
            if (end_x - start_x) > 3:
                blocks.append({'start': start_x, 'end': end_x})

        # 5. Determine Cut
        cut_x = 0
        if len(blocks) >= 2:
            text_start = blocks[1]['start']
            number_end = blocks[0]['end']
            cut_x = max(text_start - CUT_PADDING, number_end + 1)
        
        # 6. Apply & Overwrite
        if cut_x > 0:
            cropped_img = img[:, cut_x:]
            
            is_success, im_buf_arr = cv2.imencode(".png", cropped_img)
            if is_success:
                with open(image_path, "wb") as f:
                    im_buf_arr.tofile(f)
                return "Cropped"
            else:
                return "Error: Write Failed"
        
        return "Skipped"

    except Exception as e:
        return f"Error: {e}"

# --- MAIN EXECUTION ---
if __name__ == "__main__":
    print(f"\n🚀 RECURSIVE QUESTION TRIMMER (PRODUCTION)")
    print(f"📂 Target: {TARGET_ROOT_FOLDER}")
    
    user_input = input("🔴 Type 'YES' to confirm: ")
    
    if user_input.strip() == "YES":
        image_files = []
        print("\n🔍 Scanning directories...")
        for root, dirs, files in os.walk(TARGET_ROOT_FOLDER):
            for file in files:
                if file.lower().endswith(('.png', '.jpg', '.jpeg', '.bmp')):
                    image_files.append(os.path.join(root, file))
        
        print(f"📋 Found {len(image_files)} images.")
        
        stats = {"Cropped": 0, "Skipped": 0, "Error": 0}
        errors_list = []
        
        # --- PROGRESS BAR SETUP ---
        # We assign tqdm to a variable 'pbar' so we can manipulate it inside the loop
        pbar = tqdm(image_files, unit="img")
        
        for img_path in pbar:
            # DYNAMIC UPDATE: Shows relative path (e.g. "Folder\Q_1.png")
            # This overwrites the previous line, preventing scroll flood.
            rel_path = os.path.relpath(img_path, TARGET_ROOT_FOLDER)
            pbar.set_description(f"Processing: {rel_path[:30]:<30}") # Truncate to 30 chars for neatness
            
            status = process_and_overwrite(img_path)
            
            if status == "Cropped":
                stats["Cropped"] += 1
            elif status == "Skipped":
                stats["Skipped"] += 1
            else:
                stats["Error"] += 1
                errors_list.append([img_path, status])
        
        if errors_list:
            with open(ERROR_LOG_FILE, 'w', newline='', encoding='utf-8') as f:
                writer = csv.writer(f)
                writer.writerow(["File Path", "Error Message"])
                writer.writerows(errors_list)
        
        print("\n🏁 BATCH COMPLETE")
        print(f"✂️  Images Trimmed: {stats['Cropped']}")
        print(f"⏭️  Already Clean:  {stats['Skipped']}")
        print(f"❌ Errors:         {stats['Error']}")
        
        if stats['Error'] > 0:
            print(f"⚠️ Check '{ERROR_LOG_FILE}' for details.")
        
    else:
        print("❌ Operation Aborted.")