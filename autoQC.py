import pandas as pd
import numpy as np
import shutil
from pathlib import Path
from datetime import datetime
from PIL import Image

# --- CONFIGURATION ---
# Use raw strings (r'...') or forward slashes for paths
BASE_PATH = Path(r'D:/Main/3. Work - Teaching/Projects/Question extractor/')
DB_PATH = BASE_PATH / 'DB Master.csv'
IMG_DIR = BASE_PATH / 'Processed_Database'
BACKUP_DIR = BASE_PATH / 'Backups'

# --- GEOMETRY RULES ---
LIMITS = {
    'MIN_HEIGHT_NUMERICAL': 50,  # Single line questions
    'MIN_HEIGHT_MCQ': 100,       # Needs space for options
    'MIN_HEIGHT_DEFAULT': 75,    # Fallback
    'MAX_HEIGHT': 3000,          # Uncropped full page
    'MIN_ASPECT': 0.25,          # Too thin (Vertical sliver)
    'MAX_ASPECT': 20.0           # Too wide (Horizontal bar)
}

def create_backup(file_path):
    """Creates a timestamped backup of the database."""
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    backup_path = BACKUP_DIR / f"DB_Master_AutoQC_{timestamp}.csv"
    
    try:
        shutil.copy2(file_path, backup_path)
        print(f"✅ Backup created: {backup_path.name}")
    except Exception as e:
        print(f"⚠️ Backup failed: {e}")

def get_image_metadata(folder, q_num):
    """
    Attempts to find the image and return dimensions.
    Handles '1' vs '1.0' discrepancy automatically.
    Returns: (width, height, status_message)
    """
    if pd.isna(folder) or pd.isna(q_num):
        return None, None, "Invalid Metadata"

    folder_path = IMG_DIR / str(folder).strip()
    
    # Normalize q_num: "1.0" -> "1"
    try:
        q_clean = str(int(float(q_num)))
    except ValueError:
        q_clean = str(q_num)

    file_name = f"Q_{q_clean}.png"
    img_path = folder_path / file_name

    if not img_path.exists():
        return None, None, "Missing File"
    
    if img_path.stat().st_size == 0:
        return None, None, "Corrupt (0 KB)"

    try:
        with Image.open(img_path) as img:
            return img.width, img.height, "Found"
    except Exception:
        return None, None, "Read Error"

def evaluate_row(row):
    """
    Applies geometry rules to a single row.
    Returns: (New_Status, Fail_Reason)
    """
    # 1. Check File Integrity
    if row['img_status'] != "Found":
        return "Auto-Fail", row['img_status']

    w, h = row['q_width'], row['q_height']
    q_type = str(row.get('Question type', '')).lower()
    reasons = []

    # 2. Determine Height Limit based on Context
    if "numerical" in q_type:
        limit = LIMITS['MIN_HEIGHT_NUMERICAL']
        lbl = "Numerical"
    elif "single" in q_type or "multiple" in q_type:
        limit = LIMITS['MIN_HEIGHT_MCQ']
        lbl = "MCQ"
    else:
        limit = LIMITS['MIN_HEIGHT_DEFAULT']
        lbl = "General"

    # 3. Check Height Rules
    if h < limit:
        reasons.append(f"Too Short for {lbl} ({h}px < {limit}px)")
    if h > LIMITS['MAX_HEIGHT']:
        reasons.append(f"Too Tall ({h}px)")

    # 4. Check Aspect Ratio Rules
    aspect = w / h
    if aspect < LIMITS['MIN_ASPECT']:
        reasons.append(f"Too Thin (Ratio {aspect:.2f})")
    elif aspect > LIMITS['MAX_ASPECT']:
        reasons.append(f"Too Wide (Ratio {aspect:.2f})")

    # 5. Final Verdict
    if reasons:
        return "Auto-Fail", "; ".join(reasons)
    else:
        return "Auto-Pass", ""

def run_geometry_check():
    print("="*60)
    print("      📐 GEOMETRIC AUTO-QC AUDITOR (v2.0)")
    print("="*60)

    if not DB_PATH.exists():
        print(f"❌ Database not found at: {DB_PATH}")
        return

    # --- LOAD ---
    print("📂 Loading Database...")
    try:
        if DB_PATH.suffix == '.csv':
            df = pd.read_csv(DB_PATH)
        else:
            df = pd.read_excel(DB_PATH)
    except Exception as e:
        print(f"❌ Error reading DB: {e}")
        return

    # --- PREPARE ---
    # Ensure columns exist
    cols_to_ensure = ['QC_Status', 'QC_Fail_Reason', 'q_width', 'q_height', 'QC_Locked']
    for col in cols_to_ensure:
        if col not in df.columns:
            df[col] = None

    # Clean QC_Locked (Force to 0 or 1)
    df['QC_Locked'] = pd.to_numeric(df['QC_Locked'], errors='coerce').fillna(0).astype(int)

    # Filter Active Rows (Not Locked)
    # We use the index to update the main DF later
    active_mask = (df['QC_Locked'] == 0)
    active_idx = df[active_mask].index

    print(f"   -> Analyzing {len(active_idx)} active questions...")

    if len(active_idx) == 0:
        print("✅ No active questions to process.")
        return

    # --- EXECUTE: IO PHASE (Get Sizes) ---
    print("🔍 Phase 1: verifying images dimensions...")
    
    # We create a temporary DataFrame for calculation to avoid fragmentation
    temp_df = df.loc[active_idx].copy()
    
    # Apply is cleaner than iterrows. 
    # It returns a Series of tuples which we break into columns.
    meta_results = temp_df.apply(
        lambda x: get_image_metadata(x['Folder'], x['Question No.']), axis=1
    )
    
    # Unpack results into the temp dataframe
    temp_df[['q_width', 'q_height', 'img_status']] = pd.DataFrame(meta_results.tolist(), index=temp_df.index)

    # --- EXECUTE: LOGIC PHASE (Check Rules) ---
    print("🧠 Phase 2: Applying geometry rules...")
    
    qc_results = temp_df.apply(evaluate_row, axis=1)
    
    # Unpack results
    temp_df[['QC_Status', 'QC_Fail_Reason']] = pd.DataFrame(qc_results.tolist(), index=temp_df.index)

    # --- UPDATE MAIN DATAFRAME ---
    # Update only the specific columns for the active rows
    cols_to_update = ['q_width', 'q_height', 'QC_Status', 'QC_Fail_Reason']
    df.loc[active_idx, cols_to_update] = temp_df[cols_to_update]

    # --- REPORT ---
    print("\n📊 AUDIT RESULTS:")
    print(df.loc[active_idx, 'QC_Status'].value_counts())

    fails = df[(df['QC_Status'] == 'Auto-Fail') & (df.index.isin(active_idx))]
    if not fails.empty:
        print("\n❌ Top Fail Reasons:")
        print(fails['QC_Fail_Reason'].value_counts().head(5))

    # --- SAVE ---
    print("\n💾 Saving updates...")
    create_backup(DB_PATH)
    
    try:
        df.to_csv(DB_PATH, index=False)
        print("✅ Database Updated Successfully.")
    except PermissionError:
        print("❌ ERROR: Could not save. Is the CSV file open in Excel?")

if __name__ == "__main__":
    run_geometry_check()