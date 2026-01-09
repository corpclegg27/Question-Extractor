import subprocess
import sys

def get_amd_gpu_info():
    print("🔍 Detecting GPU...")
    try:
        # Run Windows command to get GPU info
        cmd = 'wmic path win32_videocontroller get name'
        output = subprocess.check_output(cmd, shell=True).decode()
        
        # Clean up output
        gpus = [line.strip() for line in output.split('\n') if line.strip() and "Name" not in line]
        
        print(f"✅ Found {len(gpus)} GPU(s):")
        for i, gpu in enumerate(gpus):
            print(f"   {i+1}. {gpu}")
            
        return gpus
    except Exception as e:
        print(f"❌ Error detecting GPU: {e}")
        return []

if __name__ == "__main__":
    get_amd_gpu_info()