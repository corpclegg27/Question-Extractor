import os

# --- CONFIGURATION ---
# folders to scan recursively
TARGET_DIRS = ['lib'] 

# specific files to always include (crucial for context)
EXTRA_FILES = ['pubspec.yaml'] 

# file extensions or names to IGNORE (noise reduction)
IGNORE_EXTENSIONS = [
    '.g.dart',          # Generated JSON code
    '.freezed.dart',    # Generated Freezed code
    '.png', '.jpg', '.jpeg', '.svg', '.ico', '.ttf', # Assets
    '.DS_Store'         # Mac system files
]
IGNORE_FILES = [
    'firebase_options.dart', # Security/Config noise
    'generated_plugin_registrant.dart'
]

OUTPUT_FILENAME = 'project_context.txt'

def is_ignored(filename):
    if filename in IGNORE_FILES:
        return True
    if any(filename.endswith(ext) for ext in IGNORE_EXTENSIONS):
        return True
    return False

def pack_project():
    print(f"📦 Packing project into {OUTPUT_FILENAME}...")
    
    try:
        with open(OUTPUT_FILENAME, 'w', encoding='utf-8') as outfile:
            outfile.write("--- FLUTTER PROJECT CONTEXT ---\n\n")

            # 1. Add key configuration files first
            for extra_file in EXTRA_FILES:
                if os.path.exists(extra_file):
                    outfile.write(f"================================================================================\n")
                    outfile.write(f"FILE: {extra_file}\n")
                    outfile.write(f"================================================================================\n")
                    try:
                        with open(extra_file, 'r', encoding='utf-8') as f:
                            outfile.write(f.read())
                    except Exception as e:
                        outfile.write(f"Error reading file: {e}")
                    outfile.write("\n\n")

            # 2. Walk through the target directories
            file_count = 0
            for target_dir in TARGET_DIRS:
                if not os.path.exists(target_dir):
                    print(f"⚠️ Warning: Directory '{target_dir}' not found.")
                    continue

                for root, _, files in os.walk(target_dir):
                    for file in files:
                        if is_ignored(file):
                            continue

                        file_path = os.path.join(root, file)
                        # Normalize path separators for clarity (windows vs mac)
                        relative_path = os.path.relpath(file_path, '.') .replace('\\', '/')
                        
                        outfile.write(f"================================================================================\n")
                        outfile.write(f"FILE: {relative_path}\n")
                        outfile.write(f"================================================================================\n")
                        
                        try:
                            with open(file_path, 'r', encoding='utf-8') as f:
                                content = f.read()
                                outfile.write(content)
                                file_count += 1
                        except Exception as e:
                            outfile.write(f"Error reading file: {e}")
                        
                        outfile.write("\n\n")

        print(f"✅ Success! Packed {file_count} files into '{OUTPUT_FILENAME}'.")
        print("👉 Please upload this file to the chat.")

    except Exception as e:
        print(f"❌ Error creating output file: {e}")

if __name__ == "__main__":
    pack_project()