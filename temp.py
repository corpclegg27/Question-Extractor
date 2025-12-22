import pandas as pd
import numpy as np
import os
import shutil
from datetime import datetime

# --- CONFIGURATION ---
BASE_PATH = 'D:/Main/3. Work - Teaching/Projects/Question extractor/'
DB_PATH = os.path.join(BASE_PATH, 'DB Master.xlsx')
BACKUP_DIR = os.path.join(BASE_PATH, 'Backups')

def create_backup():
    os.makedirs(BACKUP_DIR, exist_ok=True)
    timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    backup_path = os.path.join(BACKUP_DIR, f"DB Master_PreQC_{timestamp}.xlsx")
    try:
        shutil.copy2(DB_PATH, backup_path)
        print(f"✅ Backup created: {os.path.basename(backup_path)}")
    except Exception as e:
        print(f"⚠️ Backup failed: {e}")

def run_auto_qc():
    if not os.path.exists(DB_PATH):
        print(f"❌ Database not found: {DB_PATH}")
        return

    print("📂 Reading database...")
    df = pd.read_excel(DB_PATH)

    # 1. CLEAN DIMENSIONS (Force numeric)
    df['q_width'] = pd.to_numeric(df['q_width'], errors='coerce')
    df['q_height'] = pd.to_numeric(df['q_height'], errors='coerce')
    
    # 2. STANDARDIZE LOCKING (Using 1 and 0)
    # If column missing, add it with 0
    if 'QC_Locked' not in df.columns: 
        df['QC_Locked'] = 0
    
    # Convert anything weird (NaN, empty strings) to 0, then ensure integer type
    df['QC_Locked'] = df['QC_Locked'].fillna(0)
    # This handles "True"/"False" strings if they exist by coercion, otherwise strict replace
    df['QC_Locked'] = df['QC_Locked'].replace({'True': 1, 'False': 0, True: 1, False: 0})
    df['QC_Locked'] = pd.to_numeric(df['QC_Locked'], errors='coerce').fillna(0).astype(int)

    # 3. DEFINE ROWS TO PROCESS
    # Logic: If it is NOT Locked (0), we re-evaluate it. 
    # (Even if it currently says "Pass", we check it again to be safe)
    process_mask = (df['QC_Locked'] == 0)
    
    locked_count = (~process_mask).sum()
    active_count = process_mask.sum()
    
    print(f"ℹ️  Locked Rows: {locked_count} (Skipping)")
    print(f"ℹ️  Active Rows: {active_count} (Re-evaluating QC rules...)")

    if active_count > 0:
        # --- DEFINE CONDITIONS ---
        # Fail: Missing dims OR extreme size
        cond_fail = (
            (df['q_width'].isna()) | 
            (df['q_height'].isna()) |
            (df['q_width'] < 50) | 
            (df['q_height'] > 4000)
        )

        # Review: Suspicious size
        cond_review = (
            ((df['q_width'] >= 50) & (df['q_width'] < 100)) |
            ((df['q_height'] > 1000) & (df['q_height'] <= 4000))
        )

        # --- APPLY LOGIC (Vectorized) ---
        # Order matters: Fail overrides Review, Review overrides Pass.
        
        conditions = [
            process_mask & cond_fail,      # Priority 1
            process_mask & cond_review,    # Priority 2
            process_mask                   # Priority 3 (Default for processed rows)
        ]
        
        choices = [
            'Fail',
            'Review Needed',
            'Pass'
        ]
        
        # Apply logic. 'default' preserves values for Locked rows.
        df['QC_Status'] = np.select(conditions, choices, default=df['QC_Status'])

    # --- SAVE ---
    print("💾 Saving updates...")
    create_backup()
    
    try:
        df.to_excel(DB_PATH, index=False)
        print("✅ DB Master.xlsx updated successfully.")
    except PermissionError:
        print("❌ ERROR: Excel file is open. Close it and run again.")
        return

    # --- REPORT ---
    print("\n" + "="*35)
    print("      FINAL QC STATUS COUNTS      ")
    print("="*35)
    print(df['QC_Status'].value_counts(dropna=False))
    print("="*35)

if __name__ == "__main__":
    run_auto_qc()