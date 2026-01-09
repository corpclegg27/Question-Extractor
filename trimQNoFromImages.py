import os
import numpy as np
from PIL import Image, ImageChops, ImageOps
from tqdm import tqdm

# --- CONFIGURATION ---
TARGET_DIR = r'D:\Main\3. Work - Teaching\Projects\Question extractor\Processed_Database'
FOLDER_PREFIX = 'CollegeDoors'
NOISE_THRESHOLD = 170

def trim_whitespace(im):
    try:
        bg = Image.new(im.mode, im.size, im.getpixel((0,0)))
        diff = ImageChops.difference(im, bg)
        diff = ImageChops.add(diff, diff, 2.0, -100)
        bbox = diff.getbbox()
        return im.crop(bbox) if bbox else im
    except: return im

def pixel_sensitive_left_trim(img):
    """Logic for Q_ images: Removes numbers from the LEFT."""
    inverted_img = ImageOps.invert(img.convert('L'))
    data = np.array(inverted_img)
    horizontal_sum = np.sum(data, axis=0)
    width = len(horizontal_sum)
    
    crop_x, in_num, white_gap = 0, False, 0
    for x in range(5, width):
        if horizontal_sum[x] > 500:
            in_num = True
            white_gap = 0
        elif in_num:
            white_gap += 1
            if white_gap >= 15:
                crop_x = x - white_gap + 2
                break
    if crop_x == 0 or crop_x > (width * 0.3): crop_x = int(width * 0.05)
    return img.crop((crop_x, 0, width, img.size[1]))

def pixel_sensitive_top_trim(img):
    """Logic for Sol_ images: Removes the 'Sol.' header from the TOP."""
    inverted_img = ImageOps.invert(img.convert('L'))
    data = np.array(inverted_img)
    vertical_sum = np.sum(data, axis=1)
    height, width = data.shape

    crop_y, in_header, white_gap = 0, False, 0
    for y in range(5, height):
        row_data = data[y, :]
        ink_positions = np.where(row_data > 128)[0]
        has_widespread_ink = len(ink_positions) > 0 and np.max(ink_positions) > (width * 0.3)
        
        if not in_header and len(ink_positions) > 0:
            in_header = True
        
        if in_header:
            if not has_widespread_ink and np.sum(row_data) < 500:
                white_gap += 1
            if white_gap >= 10 or has_widespread_ink:
                crop_y = y - white_gap + 2
                break

    if crop_y == 0 or crop_y > (height * 0.25): crop_y = int(height * 0.05)
    return img.crop((0, crop_y, width, height))

def run_targeted_refinement(root_dir):
    print(f"🚀 Initializing Targeted Refinement for folders starting with: '{FOLDER_PREFIX}'")
    files_to_process = []
    
    for root, dirs, files in os.walk(root_dir):
        # Extract the folder name from the current path
        folder_name = os.path.basename(root)
        
        # --- NEW LOGIC: ONLY TARGET SPECIFIED PREFIX ---
        if folder_name.startswith(FOLDER_PREFIX):
            for f in files:
                if f.lower().endswith('.png') and (f.startswith('Q_') or f.startswith('Sol_')):
                    files_to_process.append(os.path.join(root, f))

    if not files_to_process:
        print(f"ℹ️ No matching images found in folders starting with '{FOLDER_PREFIX}'.")
        return

    for img_path in tqdm(files_to_process, desc="Refining Targeted Images"):
        try:
            filename = os.path.basename(img_path)
            with Image.open(img_path) as img:
                img = img.convert('RGB')
                img = trim_whitespace(img)
                
                # Route based on Question or Solution prefix
                refined = pixel_sensitive_left_trim(img) if filename.startswith('Q_') else pixel_sensitive_top_trim(img)

                final = trim_whitespace(refined)
                final.convert('L').point(lambda p: 255 if p > NOISE_THRESHOLD else p).save(img_path, "PNG", optimize=True)
        except Exception as e:
            tqdm.write(f"⚠️ Error on {img_path}: {e}")

    print("\n🏁 Targeted Batch Refinement Complete.")

if __name__ == "__main__":
    run_targeted_refinement(TARGET_DIR)