import os
import time
import json
import pickle
import pandas as pd
from tqdm import tqdm
from google_auth_oauthlib.flow import InstalledAppFlow
from google.auth.transport.requests import Request
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload
from googleapiclient.errors import HttpError

# --- CONFIGURATION ---
try:
    with open('config.json', 'r') as f:
        config = json.load(f)
        BASE_PATH = config.get('BASE_PATH', os.getcwd())
except FileNotFoundError:
    print("⚠️ config.json not found. Using current directory.")
    BASE_PATH = os.getcwd()

# File Paths
FOLDERS_CSV = os.path.join(BASE_PATH, 'FoldersToUploadToDrive.csv')  
MASTER_FILE_CSV = os.path.join(BASE_PATH, 'FilesToUpload.csv')     
# UPDATED: Pointing to your new OAuth JSON file
CLIENT_SECRETS_FILE = os.path.join(BASE_PATH, 'DriveUploaderOAuth.json') 
TOKEN_FILE = os.path.join(BASE_PATH, 'token.pickle')                 

# Target Shared Folder
SHARED_DRIVE_FOLDER_ID = "1pCo45FQsYAFdwXNBhFCQoZz0p0O3DBLL" 
SCOPES = ['https://www.googleapis.com/auth/drive']

class SmartMigrator:
    def __init__(self):
        self.service = self._authenticate()
        self.folder_cache = {} 
        print(f"📂 Target Drive Folder ID: {SHARED_DRIVE_FOLDER_ID}")

    def _authenticate(self):
        """Authenticates using OAuth (User Account) so quota works."""
        creds = None
        # Load existing login token if available
        if os.path.exists(TOKEN_FILE):
            with open(TOKEN_FILE, 'rb') as token:
                creds = pickle.load(token)
        
        # If no valid token, let user log in via browser
        if not creds or not creds.valid:
            if creds and creds.expired and creds.refresh_token:
                creds.refresh(Request())
            else:
                if not os.path.exists(CLIENT_SECRETS_FILE):
                    print(f"❌ CRITICAL: '{CLIENT_SECRETS_FILE}' missing.")
                    print("   Please check the filename in your folder.")
                    exit()
                    
                flow = InstalledAppFlow.from_client_secrets_file(
                    CLIENT_SECRETS_FILE, SCOPES)
                creds = flow.run_local_server(port=0)
            
            # Save the token for next time
            with open(TOKEN_FILE, 'wb') as token:
                pickle.dump(creds, token)
        
        return build('drive', 'v3', credentials=creds)

    def generate_file_list(self):
        if os.path.exists(MASTER_FILE_CSV):
            print(f"ℹ️  '{MASTER_FILE_CSV}' found. Skipping Scan Phase.")
            return

        print("🔍 Phase 1: Scanning folders...")
        file_list = []
        
        if not os.path.exists(FOLDERS_CSV):
            print(f"❌ Error: {FOLDERS_CSV} not found.")
            return

        try:
            df_folders = pd.read_csv(FOLDERS_CSV)
        except Exception as e:
            print(f"❌ Error reading folders csv: {e}")
            return

        for _, row in df_folders.iterrows():
            raw_path = str(row['FolderPath']).replace('"', '').replace("'", '').strip()
            if os.path.isabs(raw_path):
                base_folder = raw_path
            else:
                base_folder = os.path.join(BASE_PATH, raw_path)

            if not os.path.exists(base_folder):
                print(f"⚠️  Skipping missing: {base_folder}")
                continue

            print(f"    Scanning: {base_folder}")
            
            for root, dirs, files in os.walk(base_folder):
                for file_name in files:
                    full_path = os.path.join(root, file_name)
                    try:
                        f_size = os.path.getsize(full_path)
                    except:
                        f_size = 0
                    
                    file_list.append({
                        'FullPath': full_path,
                        'RootFolder': base_folder,
                        'FileSize': f_size,
                        'Status': 'Pending',
                        'DriveFileID': ''
                    })

        if file_list:
            df = pd.DataFrame(file_list)
            df.to_csv(MASTER_FILE_CSV, index=False)
            total_gb = df['FileSize'].sum() / (1024**3)
            print(f"✅ Scan Complete. Found {len(df)} files ({total_gb:.2f} GB).")
        else:
            print("⚠️  No files found to upload.")

    def _get_or_create_folder(self, folder_name, parent_id):
        cache_key = f"{parent_id}_{folder_name}"
        if cache_key in self.folder_cache:
            return self.folder_cache[cache_key]

        query = f"name = '{folder_name}' and '{parent_id}' in parents and mimeType = 'application/vnd.google-apps.folder' and trashed = false"
        try:
            response = self.service.files().list(q=query, spaces='drive', fields='files(id, name)').execute()
            files = response.get('files', [])
            if files:
                folder_id = files[0]['id']
            else:
                metadata = {'name': folder_name, 'mimeType': 'application/vnd.google-apps.folder', 'parents': [parent_id]}
                folder = self.service.files().create(body=metadata, fields='id').execute()
                folder_id = folder.get('id')
            
            self.folder_cache[cache_key] = folder_id
            return folder_id
        except HttpError:
            return parent_id 

    def upload_file_chunked(self, local_path, parent_id, pbar_bytes):
        file_name = os.path.basename(local_path)
        metadata = {'name': file_name, 'parents': [parent_id]}
        media = MediaFileUpload(local_path, resumable=True)

        try:
            request = self.service.files().create(body=metadata, media_body=media, fields='id')
            response = None
            previous_progress = 0
            
            while response is None:
                status, response = request.next_chunk()
                if status:
                    current_progress = int(status.resumable_progress)
                    chunk_size = current_progress - previous_progress
                    pbar_bytes.update(chunk_size)
                    previous_progress = current_progress
            
            # Update remaining bytes
            total_size = os.path.getsize(local_path)
            if previous_progress < total_size:
                pbar_bytes.update(total_size - previous_progress)
                
            return response.get('id'), None
        except Exception as e:
            return None, str(e)

    def start_upload(self):
        if not os.path.exists(MASTER_FILE_CSV):
            print("❌ Master CSV not found.")
            return

        # Load Data
        df = pd.read_csv(MASTER_FILE_CSV)
        
        # --- RESUME STATE ---
        total_files = len(df)
        total_bytes = df['FileSize'].sum()
        
        # Count what is ALREADY done
        completed_mask = df['Status'] == 'Uploaded'
        completed_files = completed_mask.sum()
        completed_bytes = df.loc[completed_mask, 'FileSize'].sum()
        
        if completed_files == total_files:
            print("🎉 All files are already uploaded!")
            return

        print(f"🚀 Phase 2: Resuming Upload (User Auth)...")
        print(f"   Already Done: {completed_files} files ({completed_bytes / (1024**2):.1f} MB)")
        
        # Initialize Bars
        pbar_files = tqdm(total=total_files, initial=completed_files, unit='file', desc="Files", position=0, leave=True)
        pbar_bytes = tqdm(total=total_bytes, initial=completed_bytes, unit='B', unit_scale=True, desc="Data ", position=1, leave=True)

        try:
            for index, row in df.iterrows():
                
                # SKIP if already done
                if row['Status'] == 'Uploaded':
                    continue

                local_path = row['FullPath']
                root_folder = row['RootFolder']
                
                if not os.path.exists(local_path):
                    df.at[index, 'Status'] = 'Missing Local File'
                    pbar_files.update(1)
                    continue

                try:
                    # 1. Folder Logic
                    rel_path = os.path.relpath(local_path, root_folder)
                    folder_path = os.path.dirname(rel_path)
                    root_name = os.path.basename(root_folder)
                    
                    current_parent_id = self._get_or_create_folder(root_name, SHARED_DRIVE_FOLDER_ID)
                    
                    if folder_path and folder_path != ".":
                        for part in folder_path.split(os.sep):
                            current_parent_id = self._get_or_create_folder(part, current_parent_id)
                    
                    # 2. Upload
                    file_id, error_msg = self.upload_file_chunked(local_path, current_parent_id, pbar_bytes)

                    if file_id:
                        df.at[index, 'Status'] = 'Uploaded'
                        df.at[index, 'DriveFileID'] = file_id
                    else:
                        df.at[index, 'Status'] = f'Failed: {error_msg}'

                except Exception as e:
                    df.at[index, 'Status'] = f'Error: {str(e)}'

                # Update Counter
                pbar_files.update(1)

                # SAVE
                df.to_csv(MASTER_FILE_CSV, index=False)

        except KeyboardInterrupt:
            print("\n🛑 Paused by User. Saving progress...")
        
        finally:
            df.to_csv(MASTER_FILE_CSV, index=False)
            pbar_files.close()
            pbar_bytes.close()
            print("\n✅ Progress Saved.")

if __name__ == '__main__':
    migrator = SmartMigrator()
    migrator.generate_file_list()
    migrator.start_upload()