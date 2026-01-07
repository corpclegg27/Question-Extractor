import os

# --- CONFIGURATION ---
OUTPUT_FILENAME = 'project_context.txt'

# Ignore this script itself so it doesn't pack its own code
MY_NAME = os.path.basename(__file__)

def pack_python_files():
    print(f"📦 Packing all .py files in current folder into {OUTPUT_FILENAME}...")
    
    # Get all .py files in the current directory (excludes subdirectories)
    py_files = [
        f for f in os.listdir('.') 
        if os.path.isfile(f) and f.endswith('.py') and f != MY_NAME and f != OUTPUT_FILENAME
    ]

    if not py_files:
        print("⚠️ No .py files found in the current directory.")
        return

    try:
        with open(OUTPUT_FILENAME, 'w', encoding='utf-8') as outfile:
            # 1. Write a Summary Header
            outfile.write("--- PROJECT STRUCTURE SUMMARY ---\n")
            outfile.write(f"Location: {os.getcwd()}\n")
            for f in py_files:
                outfile.write(f" 📄 {f}\n")
            outfile.write(f"\nTotal Files: {len(py_files)}\n")
            outfile.write("-" * 50 + "\n\n")

            outfile.write("--- FILE CONTENTS ---\n\n")

            # 2. Write Contents of each .py file
            file_count = 0
            for file_path in py_files:
                outfile.write(f"{'='*80}\nFILE: {file_path}\n{'='*80}\n")
                
                try:
                    with open(file_path, 'r', encoding='utf-8') as f:
                        outfile.write(f.read())
                        file_count += 1
                except Exception as e:
                    outfile.write(f"[Error reading file: {e}]")
                
                outfile.write("\n\n")

        print(f"✅ Success! Packed {file_count} files.")
        print(f"👉 Upload '{OUTPUT_FILENAME}' to the chat.")

    except Exception as e:
        print(f"❌ Error: {e}")

if __name__ == "__main__":
    pack_python_files()