import subprocess
import sys
import os

# ==========================================
# 👇 UPDATE YOUR COMMIT MESSAGE HERE 👇
# ==========================================
COMMIT_MESSAGE = "30 Jan: Improved test UI to have summary bottom sheet | fixed issues with unknown question types | improved student chapter view"

# Set this to True to fix the "Secret detected" error by undoing the last local commit
FIX_BROKEN_COMMIT = False 
# ==========================================

def run_command(command, step_name, ignore_error=False):
    print(f"\n🔄 {step_name}...")
    try:
        result = subprocess.run(
            command,
            check=not ignore_error,
            text=True,
            capture_output=True,
            shell=True 
        )
        if result.returncode == 0:
            print(f"✅ Success.")
            if result.stdout:
                lines = result.stdout.strip().splitlines()
                if lines: print(f"   Output: {lines[0]}...")
        else:
            if ignore_error:
                print(f"⚠️  Ignored error (safe to proceed).")
            else:
                raise subprocess.CalledProcessError(result.returncode, command, result.stdout, result.stderr)

    except subprocess.CalledProcessError as e:
        if "nothing to commit" in e.stdout.lower() or "nothing to commit" in e.stderr.lower():
            print("⚠️  Nothing to commit (Working tree clean).")
            return
            
        print(f"❌ Error during: {step_name}")
        print(f"   Details: {e.stderr.strip()}")
        sys.exit(1)

def ensure_gitignore():
    print("\n🛡️  Securing credentials...")
    ignore_file = ".gitignore"
    secret_file = "serviceAccountKey.json"
    
    # 1. Add to .gitignore if missing
    if os.path.exists(ignore_file):
        with open(ignore_file, "r") as f:
            content = f.read()
        if secret_file not in content:
            with open(ignore_file, "a") as f:
                f.write(f"\n{secret_file}")
            print(f"   -> Added {secret_file} to .gitignore")
    else:
        with open(ignore_file, "w") as f:
            f.write(f"{secret_file}")
        print(f"   -> Created .gitignore with {secret_file}")

    # 2. Force remove from git cache (stops tracking it)
    run_command(f"git rm --cached {secret_file}", "Unstaging secret key", ignore_error=True)

if __name__ == "__main__":
    print(f"🚀 Starting Git Push Sequence")
    print(f"📝 Message: '{COMMIT_MESSAGE}'")

    # --- SAFETY FIX FOR BLOCKED PUSH ---
    if FIX_BROKEN_COMMIT:
        print("\n🚑 RUNNING EMERGENCY FIX (Undoing last bad commit)...")
        # Soft reset undoes the commit but keeps your file changes
        run_command("git reset --soft HEAD~1", "Undoing last commit", ignore_error=True)

    # 1. Secure Secrets
    ensure_gitignore()

    # 2. Check Status
    run_command("git status", "Checking repository status")

    # 3. Stage all standard changes
    run_command("git add .", "Staging all files")

    # 3.5 FORCE ADD MODELS (If needed)
    if os.path.exists("models"):
        run_command("git add -f models/", "⚠️ Force adding 'models' folder")

    # 4. Commit changes
    run_command(f'git commit -m "{COMMIT_MESSAGE}"', "Committing to local repo")

    # 5. Push to remote
    run_command("git push", "Pushing to remote origin")

    print("\n🎉 DONE! Code is live.")