# Files Created for PyTorch 2.9.1 Build

Documentation and build infrastructure added to TheRock repository.

## Documentation

### 📖 JOURNEY.md
**Location:** `/external-builds/pytorch/JOURNEY.md`

The complete story of building PyTorch 2.9.1 for ROCm 7.12 + gfx1201. Chronicles the investigation, challenges, solutions, and breakthroughs. Written to inspire and inform future builders.

**Sections:**
- The Challenge (HIP illegal memory access)
- The Investigation (version mismatch discovery)
- The Build (8,083 compilation steps × 3 attempts)
- Each obstacle overcome (flatbuffers, __half, libdrm)
- The Validation (successful LoRA training)
- Lessons learned

### 📘 PYTORCH_README.md
**Location:** `/external-builds/pytorch/PYTORCH_README.md`

Technical reference for building and using PyTorch with TheRock ROCm 7.12.

**Contents:**
- Quick start guide
- Problem descriptions and solutions
- Build configuration details
- Validation results
- Troubleshooting guide
- Performance benchmarks

## Build Infrastructure

### 🔧 build_pytorch_gfx1201.sh
**Location:** `/external-builds/pytorch/build_pytorch_gfx1201.sh`

Automated build script that:
- Validates environment (PyTorch source, ROCm installation)
- Applies patches automatically
- Sets up libdrm headers from TheRock
- Configures build environment variables
- Compiles PyTorch with all optimizations
- Copies wheel to output directory
- Reports build time and statistics

**Usage:**
```bash
./build_pytorch_gfx1201.sh
# Takes ~2 hours, outputs wheel to wheels/
```

### 🩹 Patches

#### patches/rocprim-half-fix.patch
**Fixes:** Ambiguous `__half` operator overloads in ROCm 7.12 rocprim

**Applied to:** `/opt/rocm/include/rocprim/device/detail/device_radix_sort.hpp`

**Change:** Removes zero addition in `compare_nan_sensitive()` to avoid operator+ ambiguity while preserving sort correctness.

#### patches/flatbuffers-v25-compat.patch
**Fixes:** Version mismatch between PyTorch (v24) and ROCm (v25.9.23)

**Applied to:**
- `torch/csrc/jit/serialization/mobile_bytecode_generated.h`
- `torch/include/torch/csrc/jit/serialization/mobile_bytecode_generated.h`
- `third_party/flatbuffers/include/flatbuffers/base.h`

**Change:** Updates FLATBUFFERS_VERSION_MAJOR from 24 to 25, MINOR from 12 to 9.

## Repository Updates

### 📝 TheRock/README.md
**Section added:** "PyTorch 2.9.1 for ROCm 7.12 + gfx1201"

Added before "Development Manuals" section with:
- Overview of the PyTorch build
- Key features and optimizations
- Validation results
- Quick start commands
- Links to detailed documentation

## Directory Structure

```
external-builds/pytorch/
├── JOURNEY.md                     # Narrative documentation
├── PYTORCH_README.md              # Technical reference
├── FILES_CREATED.md              # This file
├── build_pytorch_gfx1201.sh      # Automated build script (executable)
├── patches/
│   ├── rocprim-half-fix.patch           # __half operator fix
│   └── flatbuffers-v25-compat.patch    # Version alignment
└── wheels/                        # Output directory for built wheels
    └── torch-2.9.1-cp314-cp314-linux_x86_64.whl  # (329 MB, after build)
```

## Integration with TheRock

These files integrate with the existing TheRock build system:

### Dependencies from TheRock
- Device libraries: `/opt/rocm/lib/llvm/amdgcn/bitcode`
- libdrm headers: `/mnt/build/TheRock/build/core/ROCR-Runtime/dist/lib/rocm_sysdeps/include/libdrm`
- ROCm installation: `/opt/rocm` (symlink to TheRock dist)

### Build Environment
All environment variables configured in build script:
- `ROCM_PATH=/opt/rocm`
- `PYTORCH_ROCM_ARCH=gfx1201`
- `HIP_DEVICE_LIB_PATH` and `DEVICE_LIB_PATH` set correctly
- Flash Attention and FBGEMM enabled

## Git Integration

To commit these changes to TheRock:

```bash
cd /var/mnt/build/TheRock
git add external-builds/pytorch/JOURNEY.md
git add external-builds/pytorch/PYTORCH_README.md
git add external-builds/pytorch/FILES_CREATED.md
git add external-builds/pytorch/build_pytorch_gfx1201.sh
git add external-builds/pytorch/patches/
git add README.md

git commit -m "Add PyTorch 2.9.1 build for ROCm 7.12 + gfx1201

- Complete build infrastructure with automated script
- Patches for flatbuffers v25 and rocprim __half compatibility
- Full documentation including JOURNEY narrative
- Validated with successful LoRA training (9min, 0 errors)
- Enables Flash Attention and FBGEMM on gfx1201

Resolves version mismatch issues between PyTorch 2.9.1 and ROCm 7.12
that caused HIP illegal memory access during training."
```

## What's Not Included

**Not committed to git:**
- `wheels/*.whl` - Binary artifacts (329 MB each)
- `pytorch/build/` - Temporary build artifacts (~20 GB)
- `pytorch/build.log` - Build logs (can be large)

These should be in `.gitignore` or generated locally.

## Maintenance Notes

### When to Rebuild
- ROCm version updates (7.12 → 7.13)
- PyTorch version updates (2.9.1 → 2.10)
- New gfx architecture targets
- Compiler updates affecting compatibility

### Patch Maintenance
- Monitor upstream PyTorch for flatbuffers version changes
- Track ROCm rocprim updates that might resolve __half issues
- Test patches against new PyTorch releases

### Documentation Updates
- Update JOURNEY.md if new challenges arise
- Add troubleshooting cases to PYTORCH_README.md
- Record performance benchmarks for different models

---

*Created: February 5, 2026*
*PyTorch: 2.9.1*
*ROCm: 7.12.0a20260203*
*Target: gfx1201 (AMD Radeon AI PRO R9700, 32 GB VRAM)*
