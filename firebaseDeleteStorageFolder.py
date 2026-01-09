import firebase_admin
from firebase_admin import credentials, storage
from concurrent.futures import ThreadPoolExecutor
from tqdm import tqdm

# --- 1. CONFIGURATION ---
CREDENTIALS_FILE = 'studysmart-5da53-firebase-adminsdk-fbsvc-ca5974c5e9.json'
STORAGE_BUCKET = 'studysmart-5da53.firebasestorage.app'

# The folder you want to wipe (prefix). 
# Be careful: "Question Bank/" will delete everything inside it.
FOLDER_TO_DELETE = "Question Bank/" 

# --- 2. INITIALIZE FIREBASE ---
if not firebase_admin._apps:
    cred = credentials.Certificate(CREDENTIALS_FILE)
    firebase_admin.initialize_app(cred, {
        'storageBucket': STORAGE_BUCKET
    })

bucket = storage.bucket()

# --- 3. WORKER FUNCTION ---
def delete_blob(blob):
    """Worker function to delete a single file."""
    try:
        blob.delete()
        return True
    except Exception as e:
        # We use tqdm.write to print errors without breaking the progress bar
        tqdm.write(f"⚠️ Error deleting {blob.name}: {e}")
        return False

# --- 4. EXECUTION LOGIC ---
def run_fast_delete(prefix):
    print(f"🔍 Scanning storage for files with prefix: '{prefix}'...")
    
    # We first list all blobs to get a total count for the progress bar
    blobs = list(bucket.list_blobs(prefix=prefix))
    total_files = len(blobs)

    if total_files == 0:
        print(f"ℹ️ No files found in '{prefix}'.")
        return

    print(f"🗑️ Found {total_files} files. Starting parallel deletion...")

    # max_workers=30 allows 30 simultaneous delete requests to Firebase
    with ThreadPoolExecutor(max_workers=30) as executor:
        # wrap executor.map with tqdm to generate the progress bar
        results = list(tqdm(
            executor.map(delete_blob, blobs), 
            total=total_files, 
            desc="Wiping Storage", 
            unit="file"
        ))

    success_count = sum(1 for r in results if r)
    print(f"\n✅ Cleanup Complete.")
    print(f"Successfully deleted {success_count} / {total_files} files.")

if __name__ == "__main__":
    run_fast_delete(FOLDER_TO_DELETE)