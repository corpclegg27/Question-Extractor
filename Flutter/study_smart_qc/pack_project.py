import os

# --- CONFIGURATION ---
TARGET_DIRS = ['lib']  # Folders to scan
EXTRA_FILES = ['pubspec.yaml', 'android/app/build.gradle', 'ios/Runner/Info.plist'] 

# Ignore rules
IGNORE_EXTENSIONS = {
    '.g.dart', '.freezed.dart', '.part.dart', # Generated code
    '.png', '.jpg', '.jpeg', '.svg', '.ico', '.ttf', '.otf', # Assets
    '.DS_Store', '.lock', '.env'
}
IGNORE_FILES = {
    'firebase_options.dart', 
    'generated_plugin_registrant.dart',
    '.gitignore',
    '.gitkeep'
}

OUTPUT_FILENAME = 'project_context_v2.txt'

def is_ignored(filename):
    if filename in IGNORE_FILES:
        return True
    return any(filename.endswith(ext) for ext in IGNORE_EXTENSIONS)

def generate_tree_structure(target_dirs):
    """Generates a string representation of the project structure showing full paths."""
    tree_lines = ["--- PROJECT STRUCTURE SUMMARY ---"]
    total_files = 0
    
    # 1. Add Extra Files to the summary first
    if EXTRA_FILES:
        tree_lines.append("📂 (Root Config Files)")
        for ef in EXTRA_FILES:
            if os.path.exists(ef):
                tree_lines.append(f"   📄 {ef}")
                total_files += 1
        tree_lines.append("")

    # 2. Walk through Target Directories
    for target_dir in target_dirs:
        if not os.path.exists(target_dir):
            continue
            
        for root, dirs, files in os.walk(target_dir):
            # Remove hidden dirs (like .git) from traversal
            dirs[:] = [d for d in dirs if not d.startswith('.')]
            
            # Filter files for the count
            valid_files = [f for f in files if not is_ignored(f)]
            
            # Only display the folder if it contains valid files
            if valid_files:
                # Normalize path separators to forward slashes for consistency
                display_path = root.replace(os.sep, '/')
                
                # Print the Full Path relative to project root
                tree_lines.append(f"📂 {display_path}/")
                
                for f in valid_files:
                    tree_lines.append(f"   📄 {f}")
                    total_files += 1
                
                # Add a spacer line between folders for readability
                tree_lines.append("") 
    
    tree_lines.append(f"Total Source Files: {total_files}")
    tree_lines.append("-" * 50 + "\n")
    return "\n".join(tree_lines)

def pack_project():
    print(f"📦 Packing project into {OUTPUT_FILENAME}...")
    
    try:
        with open(OUTPUT_FILENAME, 'w', encoding='utf-8') as outfile:
            # 1. Write the Tree Structure first
            tree_view = generate_tree_structure(TARGET_DIRS)
            outfile.write(tree_view)
            print("✅ Structure map generated.")

            outfile.write("--- FILE CONTENTS ---\n\n")

            # 2. Add Config Files
            for extra_file in EXTRA_FILES:
                if os.path.exists(extra_file):
                    outfile.write(f"{'='*80}\nFILE: {extra_file}\n{'='*80}\n")
                    try:
                        with open(extra_file, 'r', encoding='utf-8') as f:
                            outfile.write(f.read())
                    except Exception as e:
                        outfile.write(f"[Error reading file: {e}]")
                    outfile.write("\n\n")

            # 3. Walk and Write Source Code
            file_count = 0
            for target_dir in TARGET_DIRS:
                for root, _, files in os.walk(target_dir):
                    for file in files:
                        if is_ignored(file):
                            continue

                        file_path = os.path.join(root, file)
                        # Normalize path for Windows/Mac consistency
                        relative_path = os.path.relpath(file_path, '.').replace('\\', '/')
                        
                        outfile.write(f"{'='*80}\nFILE: {relative_path}\n{'='*80}\n")
                        
                        try:
                            with open(file_path, 'r', encoding='utf-8') as f:
                                outfile.write(f.read())
                                file_count += 1
                        except UnicodeDecodeError:
                            outfile.write("[Binary or Non-UTF8 file skipped]")
                        except Exception as e:
                            outfile.write(f"[Error reading file: {e}]")
                        
                        outfile.write("\n\n")

        print(f"✅ Success! Packed {file_count} files.")
        print(f"👉 Upload '{OUTPUT_FILENAME}' to the chat.")

    except Exception as e:
        print(f"❌ Error: {e}")

if __name__ == "__main__":
    pack_project()