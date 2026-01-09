import torch
import sys

def check_cuda():
    print(f"Python Version: {sys.version.split()[0]}")
    print("-" * 30)
    
    # 1. Check if CUDA is available
    is_available = torch.cuda.is_available()
    print(f"✅ CUDA Available: {is_available}")

    if is_available:
        # 2. Get Device Details
        device_id = torch.cuda.current_device()
        gpu_name = torch.cuda.get_device_name(device_id)
        cuda_version = torch.version.cuda
        
        print(f"🚀 GPU Name:      {gpu_name}")
        print(f"🔧 CUDA Version:  {cuda_version}")
        print(f"🧠 GPU Memory:    {torch.cuda.get_device_properties(device_id).total_memory / 1e9:.2f} GB")
        
        # 3. Simple Tensor Test
        try:
            x = torch.rand(5, 3).cuda()
            print("\n✨ Success! Created a Tensor on the GPU.")
        except Exception as e:
            print(f"\n❌ Error using GPU: {e}")
            
    else:
        print("\n⚠️  WARNING: PyTorch cannot find your GPU.")
        print("    EasyOCR will fallback to CPU (10x-20x slower).")
        print("    Solution: Re-install PyTorch with CUDA support from https://pytorch.org/")

if __name__ == "__main__":
    try:
        check_cuda()
    except ImportError:
        print("❌ Error: PyTorch is not installed. Run: pip install torch torchvision torchaudio")