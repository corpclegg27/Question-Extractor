import pandas as pd
import json
import os
import sys

# --- CONFIGURATION ---
# Auto-detect paths based on current file location
CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(CURRENT_DIR, "config.json")

def load_config():
    """Safely load the config file."""
    if not os.path.exists(CONFIG_PATH):
        print(f"❌ CRITICAL: config.json not found at {CONFIG_PATH}")
        return None
    
    try:
        with open(CONFIG_PATH, 'r') as f:
            return json.load(f)
    except json.JSONDecodeError:
        print("❌ CRITICAL: config.json is corrupted or invalid JSON.")
        return None

def save_config(config_data):
    """Safely write back to the config file."""
    try:
        with open(CONFIG_PATH, 'w') as f:
            json.dump(config_data, f, indent=4)
        return True
    except Exception as e:
        print(f"❌ Error saving config: {e}")
        return False

def sanitize_and_sync():
    print("="*50)
    print("      🏥 DATABASE SANITIZER & SYNC TOOL")
    print("="*50)

    # 1. LOAD CONFIG
    config = load_config()
    if not config: return

    base_path = config.get("BASE_PATH", CURRENT_DIR)
    db_filename = config.get("DB_FILENAME", "DB Master.xlsx")
    db_path = os.path.join(base_path, db_filename)

    # 2. LOAD DATABASE
    if not os.path.exists(db_path):
        print(f"❌ Database not found at: {db_path}")
        return

    print(f"📂 Loading Database: {db_filename}...")
    try:
        df = pd.read_excel(db_path)
    except Exception as e:
        print(f"❌ Failed to read Excel file: {e}")
        return

    print(f"   -> Loaded {len(df)} records.")

    # 3. SYNC UNIQUE IDs
    print("\n[TASK 1] Syncing 'last_unique_id'...")
    
    if 'unique_id' in df.columns:
        # Convert to numeric, turning errors (like old string IDs) into NaN
        numeric_ids = pd.to_numeric(df['unique_id'], errors='coerce')
        
        # Drop NaNs to find the highest valid integer
        valid_ids = numeric_ids.dropna()
        
        if not valid_ids.empty:
            max_db_id = int(valid_ids.max())
            config_id = config.get("last_unique_id", 0)
            
            print(f"   ℹ️  Max ID in DB:     {max_db_id}")
            print(f"   ℹ️  Last ID in Config: {config_id}")

            if max_db_id > config_id:
                print(f"   ⚠️  MISMATCH DETECTED. Config is lagging behind.")
                print(f"   🔄  Updating config.json to {max_db_id}...")
                config["last_unique_id"] = max_db_id
                
                if save_config(config):
                    print("   ✅ Sync Successful.")
            elif max_db_id < config_id:
                print("   ⚠️  WARNING: Config ID is HIGHER than DB ID.")
                print("       (This is usually fine; it means some IDs were generated but maybe not saved yet.)")
            else:
                print("   ✅ Config is perfectly in sync.")
        else:
            print("   ⚠️  No valid integer IDs found in DB. (Are they all strings?)")
    else:
        print("   ❌ 'unique_id' column is missing in DB Master.xlsx!")

    # 4. FUTURE CHECKS (Placeholder for expansion)
    # You can add logic here later to check for duplicate IDs, missing files, etc.
    # check_duplicates(df)
    # check_missing_files(df, base_path)

    print("\n" + "="*50)
    print("   🏁 SANITIZATION COMPLETE")
    print("="*50)

if __name__ == "__main__":
    sanitize_and_sync()