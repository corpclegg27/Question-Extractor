import os
import numpy as np
from PIL import Image
import pandas as pd
from tqdm import tqdm

# --- CONFIGURATION ---
# Put your "perfectly cropped" samples here
SAMPLE_DIR = r'D:\Main\3. Work - Teaching\Projects\Question extractor\Processed_Database\Compressed\CropTest'
OUTPUT_CSV = 'margin_density_report.csv'
MARGIN_CHECK_PERCENT = 0.05
NOISE_THRESHOLD = 170

def get_margin_density(img_path):
    """Calculates black pixel proportion in the left 5% of the image."""
    try:
        with Image.open(img_path) as img:
            # Standardize to RGB then Grayscale
            bw = img.convert('RGB').convert('L').point(lambda p: 0 if p < NOISE_THRESHOLD else 255)
            data = np.array(bw)
            
            height, width = data.shape
            check_width = int(width * MARGIN_CHECK_PERCENT)
            
            # Extract left margin
            margin_strip = data[:, :check_width]
            
            # Count black pixels (value 0)
            black_pixels = np.count_nonzero(margin_strip == 0)
            total_pixels = margin_strip.size
            
            return black_pixels / total_pixels
    except Exception as e:
        return None

def run_calibration():
    print(f"🔍 Analyzing images in {SAMPLE_DIR}...")
    
    results = []
    files = [f for f in os.listdir(SAMPLE_DIR) if f.lower().endswith('.png')]
    
    for filename in tqdm(files, desc="Calculating Densities"):
        file_path = os.path.join(SAMPLE_DIR, filename)
        density = get_margin_density(file_path)
        
        if density is not None:
            results.append({
                'filename': filename,
                'black_pixel_percentage': round(density * 100, 4), # Percentage for readability
                'raw_density': density
            })

    # Save to CSV
    df = pd.DataFrame(results)
    df = df.sort_values(by='raw_density', ascending=False)
    df.to_csv(OUTPUT_CSV, index=False)
    
    print(f"\n✅ Analysis complete. Results saved to {OUTPUT_CSV}")
    print(f"Top 5 highest densities (potentially problematic):")
    print(df.head())

if __name__ == "__main__":
    if not os.path.exists(SAMPLE_DIR):
        os.makedirs(SAMPLE_DIR)
        print(f"📂 Created {SAMPLE_DIR}. Please paste your 'perfect' images there and rerun.")
    else:
        run_calibration()