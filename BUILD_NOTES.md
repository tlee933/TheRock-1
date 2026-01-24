# TheRock ROCm 7.11 Build Notes

## System Info
- OS: Fedora 43 Aurora (Atomic/Kinoite-based)
- GPU: Radeon AI PRO R9700 (gfx1201, RDNA4, 32GB VRAM)
- Date: 2026-01-11

## Dependencies (Fedora 43 Aurora)

Install via rpm-ostree:
```bash
rpm-ostree install gcc-c++ autoconf automake cmake libtool ninja-build patchelf libquadmath-devel --apply-live --allow-replacement
```

- `libquadmath-devel` - Required for flang-rt (Fortran runtime) F128 math
  - Provides: /usr/lib/gcc/x86_64-redhat-linux/15/include/quadmath.h

## CMake 3.31 Workaround

Fedora 43 ships cmake 3.31.10 which has a FujitsuClang preprocessor bug that breaks the amd-llvm build:
```
CMake Error at cmake/Modules/CMakeDetermineCompilerABI.cmake
No preprocessor test for "FujitsuClang"
```

### Solution
Download cmake 3.29.2 and use it instead of system cmake:

```bash
# Download (one-time)
cd /mnt/build
wget https://github.com/Kitware/CMake/releases/download/v3.29.2/cmake-3.29.2-linux-x86_64.tar.gz
tar xzf cmake-3.29.2-linux-x86_64.tar.gz

# Use in PATH before system cmake
export PATH=/mnt/build/cmake-3.29.2-linux-x86_64/bin:$PATH
```

## Build Commands

```bash
cd /var/mnt/build/TheRock
source .venv/bin/activate
export PATH=/mnt/build/cmake-3.29.2-linux-x86_64/bin:$PATH

# Configure for RDNA4 (gfx1201)
cmake -B build -GNinja . \
  -DTHEROCK_AMDGPU_TARGETS=gfx1201 \
  -DTHEROCK_DIST_AMDGPU_FAMILIES=gfx120X-all

# Build
cmake --build build
```

## Notes
- hipSPARSELt is excluded for gfx1201 (manually marked in therock_amdgpu_targets.cmake - RDNA4 too new)
- rocgdb built without Python support (venv Python not compiled with --enable-shared)
- Build takes several hours (amd-llvm alone is 8000+ objects)

## Post-Build
- Install location: /var/mnt/build/TheRock/install
- Test with: rocminfo, hipinfo
- Then configure Ollama/llama.cpp to use ROCm
