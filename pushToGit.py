import subprocess
import sys
import os

# ==========================================
# 👇 UPDATE YOUR COMMIT MESSAGE HERE 👇
# ==========================================
COMMIT_MESSAGE = "Platform is now compliant with JEE Advanced. Added Full paper review in results"
# ==========================================

def run_command(command, step_name):
    print(f"\n🔄 {step_name}...")
    try:
        result = subprocess.run(
            command,
            check=True,
            text=True,
            capture_output=True,
            shell=True 
        )
        print(f"✅ Success.")
        if result.stdout:
            # Print first few lines of output for verification
            lines = result.stdout.strip().splitlines()
            if lines:
                print(f"   Output: {lines[0]}...")
            
    except subprocess.CalledProcessError as e:
        # Ignore "nothing to commit" errors, but stop on others
        if "nothing to commit" in e.stdout.lower() or "nothing to commit" in e.stderr.lower():
            print("⚠️  Nothing to commit (Working tree clean).")
            return
            
        print(f"❌ Error during: {step_name}")
        print(f"   Details: {e.stderr.strip()}")
        sys.exit(1)

if __name__ == "__main__":
    print(f"🚀 Starting Git Push Sequence")
    print(f"📝 Message: '{COMMIT_MESSAGE}'")

    # 1. Check Status
    run_command("git status", "Checking repository status")

    # 2. Stage all standard changes
    run_command("git add --all", "Staging all standard files")

    # 2.5 FORCE ADD MODELS
    # The '-f' flag overrides .gitignore
    if os.path.exists("models"):
        run_command("git add -f models/", "⚠️ Force adding 'models' folder (overriding .gitignore)")
    else:
        print("\n⚠️ 'models' folder not found, skipping force add.")

    # 3. Commit changes
    run_command(f'git commit -m "{COMMIT_MESSAGE}"', "Committing to local repo")

    # 4. Push to remote
    run_command("git push", "Pushing to remote origin")

    print("\n🎉 DONE! Code is live.")