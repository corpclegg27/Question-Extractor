import os
import numpy as np
from PIL import Image, ImageChops, ImageOps
from tqdm import tqdm

# --- CONFIGURATION ---
TARGET_DIR = r'D:\Main\3. Work - Teaching\Projects\Question extractor\Processed_Database\Compressed\CropTest'
FOLDER_PREFIX = 'CollegeDoors'
NOISE_THRESHOLD = 170
MARGIN_CHECK_PERCENT = 0.05  # Check the first 5% of width
DENSITY_THRESHOLD = 0.01     # If > 1% pixels are black, keep cropping
MAX_TRIES = 5

def trim_whitespace(im):
    try:
        bg = Image.new(im.mode, im.size, im.getpixel((0,0)))
        diff = ImageChops.difference(im, bg)
        diff = ImageChops.add(diff, diff, 2.0, -100)
        bbox = diff.getbbox()
        return im.crop(bbox) if bbox else im
    except: return im

def get_margin_density(img):
    """Calculates the proportion of black pixels in the left margin."""
    # Convert to grayscale and threshold to binary (Black/White)
    bw = img.convert('L').point(lambda p: 0 if p < NOISE_THRESHOLD else 255)
    data = np.array(bw)
    
    width = data.shape[1]
    check_width = int(width * MARGIN_CHECK_PERCENT)
    
    # Extract the left strip
    margin_strip = data[:, :check_width]
    
    # Count black pixels (value 0)
    black_pixels = np.count_nonzero(margin_strip == 0)
    total_pixels = margin_strip.size
    
    return black_pixels / total_pixels

def pixel_sensitive_left_trim(img):
    """Logic for Q_ images: Removes numbers from the LEFT."""
    inverted_img = ImageOps.invert(img.convert('L'))
    data = np.array(inverted_img)
    horizontal_sum = np.sum(data, axis=0)
    width = len(horizontal_sum)
    
    crop_x, in_num, white_gap = 0, False, 0
    # Start scanning from pixel 2 to avoid edge noise
    for x in range(2, width):
        if horizontal_sum[x] > 500:
            in_num = True
            white_gap = 0
        elif in_num:
            white_gap += 1
            if white_gap >= 12: # Slightly tighter gap for iterative pass
                crop_x = x - white_gap + 2
                break
    
    if crop_x == 0: return img
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
    print(f"🚀 Iterative Refinement starting for folders: '{FOLDER_PREFIX}'")
    files_to_process = []
    
    for root, _, files in os.walk(root_dir):
        if os.path.basename(root).startswith(FOLDER_PREFIX):
            for f in files:
                if f.lower().endswith('.png') and (f.startswith('Q_') or f.startswith('Sol_')):
                    files_to_process.append(os.path.join(root, f))

    for img_path in tqdm(files_to_process, desc="Refining"):
        try:
            filename = os.path.basename(img_path)
            with Image.open(img_path) as img:
                current_img = img.convert('RGB')
                current_img = trim_whitespace(current_img)
                
                if filename.startswith('Q_'):
                    # --- ENHANCED ITERATIVE CROPPING ---
                    for attempt in range(MAX_TRIES):
                        density = get_margin_density(current_img)
                        
                        # If the margin is clean enough, stop cropping
                        if density < DENSITY_THRESHOLD:
                            break
                            
                        # Apply crop and re-trim whitespace
                        current_img = pixel_sensitive_left_trim(current_img)
                        current_img = trim_whitespace(current_img)
                
                else: # Handle Sol_ images normally
                    current_img = pixel_sensitive_top_trim(current_img)
                    current_img = trim_whitespace(current_img)

                # Final compression and save
                current_img.convert('L').point(lambda p: 255 if p > NOISE_THRESHOLD else p).save(img_path, "PNG", optimize=True)
                
        except Exception as e:
            tqdm.write(f"⚠️ Error on {img_path}: {e}")

    print("\n🏁 Iterative Refinement Complete.")

if __name__ == "__main__":
    run_targeted_refinement(TARGET_DIR)