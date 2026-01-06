import subprocess
import sys

# ==========================================
# 👇 UPDATE YOUR COMMIT MESSAGE HERE 👇
# ==========================================
COMMIT_MESSAGE = "MVP Release: Integrated Smart Time Analysis Engine, Coaching UI, and Dynamic Firestore Config"
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
            lines = result.stdout.strip().splitlines()
            if lines:
                print(f"   Output: {lines[0]}...")
            
    except subprocess.CalledProcessError as e:
        if "nothing to commit" in e.stdout.lower() or "nothing to commit" in e.stderr.lower():
            print("⚠️  Nothing to commit (Working tree clean).")
            return
            
        print(f"❌ Error during: {step_name}")
        print(f"   Details: {e.stderr.strip()}")
        sys.exit(1)

if __name__ == "__main__":
    print(f"🚀 Starting Git Push Sequence")
    print(f"📝 Message: '{COMMIT_MESSAGE}'")

    # 1. Check Status (Debugging step to see what Git sees)
    run_command("git status", "Checking repository status")

    # 2. Stage all changes
    # Forced add to ensure untracked files in subdirectories are caught
    run_command("git add --all", "Staging all files (including new folders)")

    # 3. Commit changes
    run_command(f'git commit -m "{COMMIT_MESSAGE}"', "Committing to local repo")

    # 4. Push to remote
    run_command("git push", "Pushing to remote origin")

    print("\n🎉 DONE! Code is live.")