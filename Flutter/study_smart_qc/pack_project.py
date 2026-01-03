import os

# --- CONFIGURATION ---
TARGET_DIRS = ['lib']  # Folders to scan
EXTRA_FILES = ['pubspec.yaml', 'android/app/build.gradle', 'ios/Runner/Info.plist'] # Critical config files

# Ignore rules
IGNORE_EXTENSIONS = {
    '.g.dart', '.freezed.dart', '.part.dart', # Generated code
    '.png', '.jpg', '.jpeg', '.svg', '.ico', '.ttf', '.otf', # Assets
    '.DS_Store', '.lock'
}
IGNORE_FILES = {
    'firebase_options.dart', 
    'generated_plugin_registrant.dart'
}

OUTPUT_FILENAME = 'project_context_v2.txt'

def is_ignored(filename):
    if filename in IGNORE_FILES:
        return True
    return any(filename.endswith(ext) for ext in IGNORE_EXTENSIONS)

def generate_tree_structure(target_dirs):
    """Generates a string representation of the project structure."""
    tree_lines = ["--- PROJECT STRUCTURE SUMMARY ---"]
    total_files = 0
    
    for target_dir in target_dirs:
        if not os.path.exists(target_dir):
            continue
            
        for root, dirs, files in os.walk(target_dir):
            # Remove hidden dirs (like .git) from traversal
            dirs[:] = [d for d in dirs if not d.startswith('.')]
            
            level = root.replace(target_dir, '').count(os.sep)
            indent = ' ' * 4 * level
            subindent = ' ' * 4 * (level + 1)
            
            folder_name = os.path.basename(root)
            if level == 0: folder_name = target_dir
            
            # Filter files for the count
            valid_files = [f for f in files if not is_ignored(f)]
            
            if valid_files or level == 0:
                tree_lines.append(f"{indent}📂 {folder_name}/")
                for f in valid_files:
                    tree_lines.append(f"{subindent}📄 {f}")
                    total_files += 1
    
    tree_lines.append(f"\nTotal Source Files: {total_files}")
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