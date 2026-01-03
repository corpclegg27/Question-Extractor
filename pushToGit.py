import subprocess
import sys

# ==========================================
# 👇 UPDATE YOUR COMMIT MESSAGE HERE 👇
# ==========================================
COMMIT_MESSAGE = "Added flutter code"
# ==========================================

def run_command(command, step_name):
    print(f"\n🔄 {step_name}...")
    try:
        # Run command and capture output
        result = subprocess.run(
            command,
            check=True,
            text=True,
            capture_output=True,
            shell=True  # Ensures compatibility with Windows command line
        )
        print(f"✅ Success.")
        if result.stdout:
            # Print first few lines of output for context
            print(f"   Output: {result.stdout.strip().splitlines()[0]}...")
            
    except subprocess.CalledProcessError as e:
        # Handle "Nothing to commit" gracefully
        if "nothing to commit" in e.stdout.lower() or "nothing to commit" in e.stderr.lower():
            print("⚠️  Nothing to commit (Working tree clean).")
            return
            
        print(f"❌ Error during: {step_name}")
        print(f"   Details: {e.stderr.strip()}")
        sys.exit(1)

if __name__ == "__main__":
    print(f"🚀 Starting Git Push Sequence")
    print(f"📝 Message: '{COMMIT_MESSAGE}'")

    # 1. Stage all changes
    run_command("git add .", "Staging all files")

    # 2. Commit changes
    run_command(f'git commit -m "{COMMIT_MESSAGE}"', "Committing to local repo")

    # 3. Push to remote
    run_command("git push", "Pushing to remote origin")

    print("\n🎉 DONE! Code is live.")