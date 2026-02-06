# PyTorch 2.9.1 for ROCm 7.12 + gfx1201

Custom PyTorch build optimized for AMD RDNA4 architecture (gfx1201) with TheRock ROCm 7.12.

## Quick Start

```bash
# Build PyTorch (takes ~2 hours)
./build_pytorch_gfx1201.sh

# Install the wheel
python3 -m pip install --force-reinstall wheels/torch-2.9.1-cp314-cp314-linux_x86_64.whl

# Verify
python3 -c "import torch; print(f'PyTorch {torch.__version__}, ROCm: {torch.cuda.is_available()}')"
```

## What's Different

This build addresses three critical compatibility issues between PyTorch 2.9.1 and ROCm 7.12:

### 1. Flatbuffers Version Alignment
**Problem:** PyTorch expected flatbuffers v24, ROCm 7.12 provides v25.9.23
**Solution:** [`patches/flatbuffers-v25-compat.patch`](patches/flatbuffers-v25-compat.patch)

### 2. rocprim Half-Precision Fix
**Problem:** Ambiguous `__half` operator overloads in radix sort
**Solution:** [`patches/rocprim-half-fix.patch`](patches/rocprim-half-fix.patch)

### 3. libdrm Headers
**Solution:** Symlink from TheRock build artifacts

## Features Enabled

- ✅ **Flash Attention** - Optimized transformer attention for gfx1201
- ✅ **FBGEMM GenAI** - Accelerated GEMM operations for inference
- ✅ **ROCm 7.12** - Full compatibility with TheRock custom build
- ✅ **FP16 Support** - Half-precision training and inference

## Build Configuration

```bash
PYTORCH_ROCM_ARCH=gfx1201
USE_FLASH_ATTENTION=1
USE_FBGEMM_GENAI=ON
ROCM_PATH=/opt/rocm
```

## Validation

Successfully tested with LoRA fine-tuning:
- **Model:** Qwen2.5-0.5B
- **Dataset:** 1,500 examples
- **Training time:** 9 minutes (3 epochs)
- **Final loss:** 0.3367
- **Stability:** Zero HIP errors, clean completion

Previous builds (ROCm 7.11) crashed at step 3 with illegal memory access.

## Directory Structure

```
pytorch/
├── build_pytorch_gfx1201.sh      # Automated build script
├── patches/
│   ├── rocprim-half-fix.patch    # __half operator fix
│   └── flatbuffers-v25-compat.patch  # Version alignment
├── wheels/                        # Built wheels stored here
├── JOURNEY.md                     # Detailed build story
└── PYTORCH_README.md              # This file
```

## Requirements

- TheRock ROCm 7.12 build installed at `/opt/rocm`
- Python 3.14
- ~20 GB disk space for build artifacts
- 2-3 hours for compilation

## Dependencies from TheRock

This build leverages TheRock's custom ROCm 7.12:
- **Device libraries:** `/opt/rocm/lib/llvm/amdgcn/bitcode`
- **libdrm headers:** From ROCR-Runtime build artifacts
- **ROCm stack:** Compiled for gfx1201 with RDNA4 optimizations

## Troubleshooting

**Build fails at flatbuffers check:**
```bash
# Ensure patches are applied
cd /var/mnt/build/TheRock/external-builds/pytorch/pytorch
git status  # Check if files are modified
```

**Missing libdrm headers:**
```bash
# Verify symlink exists
ls -la /opt/rocm/include/libdrm
# Should point to TheRock build
```

**HIP errors during training:**
```bash
# Verify ROCm version matches
rocminfo | grep "Marketing Name"
python3 -c "import torch; print(torch.version.hip)"
# Both should show ROCm 7.12
```

## Performance Notes

On AMD Radeon AI PRO R9700 (gfx1201):
- **LoRA training:** ~1.0 it/s (batch size 2, gradient accumulation 4)
- **Flash Attention:** Enabled for self-attention layers
- **FP16:** Mixed precision supported
- **Memory:** 32 GB VRAM (excellent headroom for large models)

## Further Reading

- [JOURNEY.md](JOURNEY.md) - Complete story of the build process
- [../../README.md](../../README.md) - TheRock main documentation
- [PyTorch ROCm docs](https://pytorch.org/docs/stable/notes/hip.html)

## Credits

Built as part of the TheRock ROCm 7.12 ecosystem for RDNA4 support.

---

*Last updated: February 5, 2026*
*PyTorch version: 2.9.1*
*ROCm version: 7.12.0a20260203*
*Target: gfx1201 (RDNA4)*
