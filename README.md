# TheRock — Forge EXPERIMENTAL

![ROCm](https://img.shields.io/badge/ROCm-7.12-red?logo=amd&logoColor=white)
![GPU](https://img.shields.io/badge/GPU-gfx1201_(RDNA4)-orange)
![Fedora](https://img.shields.io/badge/Fedora-43_Atomic-blue?logo=fedora&logoColor=white)
![GCC](https://img.shields.io/badge/GCC-15.2-green?logo=gnu&logoColor=white)
![Python](https://img.shields.io/badge/Python-3.14-yellow?logo=python&logoColor=white)
![Build](https://img.shields.io/badge/Build-✅_Passing-brightgreen)
![LLM](https://img.shields.io/badge/LLM-123_t/s-purple)

> **🔥 EXPERIMENTAL FORK** — Custom ROCm 7.12 build for gfx1201 (RDNA 4) on Fedora 43 Atomic with GCC 15 and Python 3.14

---

TheRock (The HIP Environment and ROCm Kit) is a lightweight open source build platform for HIP and ROCm. This fork is a **bleeding-edge experimental build** targeting hardware and software combinations not yet officially supported upstream.

### What's Different Here

| Feature | Upstream | This Fork |
|:--------|:---------|:----------|
| **GPU** | gfx900–gfx1100 | **gfx1201 (RDNA 4)** |
| **OS** | Ubuntu 24.04 | **Fedora 43 Aurora (Atomic)** |
| **Compiler** | GCC 12–14 | **GCC 15.2.1** |
| **Python** | 3.10–3.12 | **3.14** |
| **GCC 15 Patch** | ❌ | ✅ cstdint fix included |

### Test Results

See **[TEST_RESULTS_GFX1201.md](TEST_RESULTS_GFX1201.md)** for full benchmarks, NVIDIA comparisons, and the GCC 15 compatibility saga.

---

## Quick Start — Fedora 43 Atomic

### Prerequisites

```bash
# Fedora Atomic / Aurora / Bazzite — install build deps
# Use rpm-ostree or toolbox depending on your setup

# Option A: Layer packages (persistent across reboots)
sudo rpm-ostree install gcc gcc-c++ gcc-gfortran ninja-build cmake \
  pkgconf xxd patchelf automake libtool python3-devel mesa-libEGL-devel \
  texinfo bison flex git

# Option B: Use a toolbox container (no layering needed)
toolbox create rocm-build
toolbox enter rocm-build
sudo dnf install gcc gcc-c++ gcc-gfortran ninja-build cmake \
  pkgconf xxd patchelf automake libtool python3-devel mesa-libEGL-devel \
  texinfo bison flex git
```

### Clone and Setup

```bash
# Clone this fork
git clone https://github.com/tlee933/TheRock-Forge-EXPERIMENTAL.git
cd TheRock-Forge-EXPERIMENTAL
git checkout fedora-atomic-rocm7.12-ai-pro-experimental

# Python virtual environment
python3 -m venv .venv && source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

# Fetch submodules and apply patches (including GCC 15 fix)
python3 ./build_tools/fetch_sources.py
```

### Build

```bash
# Configure for gfx1201 (AMD Radeon AI PRO R9700 / RDNA 4)
cmake -B build -GNinja . -DTHEROCK_AMDGPU_FAMILIES=gfx1201

# Build with ccache (highly recommended)
eval "$(./build_tools/setup_ccache.py)"
cmake -B build -GNinja . \
  -DTHEROCK_AMDGPU_FAMILIES=gfx1201 \
  -DCMAKE_C_COMPILER_LAUNCHER=ccache \
  -DCMAKE_CXX_COMPILER_LAUNCHER=ccache

cmake --build build
```

### Install

```bash
# Install to /opt/rocm
sudo cp -a build/dist/rocm /opt/rocm

# Configure library paths
echo "/opt/rocm/lib" | sudo tee /etc/ld.so.conf.d/rocm.conf
echo "/opt/rocm/lib/llvm/lib" | sudo tee -a /etc/ld.so.conf.d/rocm.conf
sudo ldconfig

# Set environment (add to ~/.bashrc for persistence)
export PATH=/opt/rocm/bin:/opt/rocm/lib/llvm/bin:$PATH
export ROCM_PATH=/opt/rocm
export HIP_PATH=/opt/rocm

# Verify
rocminfo | grep -E "Name:|Marketing"
hipcc --version
```

### Verify with LLM Inference

```bash
# If you have llama.cpp built with ROCm:
llama-bench -m your_model.gguf -p 512 -n 128 -ngl 99
```

---

## Build Configuration

The build can be customized through cmake feature flags.

### Required: GPU Target

```bash
-DTHEROCK_AMDGPU_FAMILIES=gfx1201    # RDNA 4 (this fork)
```

> [!NOTE]
> This fork targets **gfx1201** specifically. See
> [therock_amdgpu_targets.cmake](cmake/therock_amdgpu_targets.cmake)
> for all available options.

### Optional: Component Flags

By default, the project builds everything. Use these to build subsets:

| Group Flag | Description |
|:-----------|:------------|
| `-DTHEROCK_ENABLE_ALL=OFF` | Disables all optional components |
| `-DTHEROCK_ENABLE_CORE=OFF` | Disables all core components |
| `-DTHEROCK_ENABLE_COMM_LIBS=OFF` | Disables communication libraries |
| `-DTHEROCK_ENABLE_DEBUG_TOOLS=OFF` | Disables debug tools |
| `-DTHEROCK_ENABLE_MATH_LIBS=OFF` | Disables math libraries |
| `-DTHEROCK_ENABLE_ML_LIBS=OFF` | Disables ML libraries |
| `-DTHEROCK_ENABLE_PROFILER=OFF` | Disables profilers |
| `-DTHEROCK_ENABLE_DC_TOOLS=OFF` | Disables data center tools |

<details>
<summary>Individual component flags</summary>

| Component Flag | Description |
|:---------------|:------------|
| `-DTHEROCK_ENABLE_AMD_DBGAPI=ON` | ROCm debug API library |
| `-DTHEROCK_ENABLE_COMPILER=ON` | GPU+host compiler toolchain |
| `-DTHEROCK_ENABLE_HIPIFY=ON` | hipify tool |
| `-DTHEROCK_ENABLE_CORE_RUNTIME=ON` | Core runtime components |
| `-DTHEROCK_ENABLE_HIP_RUNTIME=ON` | HIP runtime |
| `-DTHEROCK_ENABLE_OCL_RUNTIME=ON` | OpenCL runtime |
| `-DTHEROCK_ENABLE_ROCGDB=ON` | ROCm debugger |
| `-DTHEROCK_ENABLE_ROCPROFV3=ON` | rocprofv3 |
| `-DTHEROCK_ENABLE_ROCPROFSYS=ON` | rocprofiler-systems |
| `-DTHEROCK_ENABLE_RCCL=ON` | RCCL |
| `-DTHEROCK_ENABLE_PRIM=ON` | PRIM library |
| `-DTHEROCK_ENABLE_BLAS=ON` | BLAS libraries |
| `-DTHEROCK_ENABLE_RAND=ON` | RAND libraries |
| `-DTHEROCK_ENABLE_SOLVER=ON` | SOLVER libraries |
| `-DTHEROCK_ENABLE_SPARSE=ON` | SPARSE libraries |
| `-DTHEROCK_ENABLE_MIOPEN=ON` | MIOpen |
| `-DTHEROCK_ENABLE_HIPDNN=ON` | hipDNN |
| `-DTHEROCK_ENABLE_ROCWMMA=ON` | rocWMMA |
| `-DTHEROCK_ENABLE_LIBHIPCXX=ON` | libhipcxx |

</details>

> [!TIP]
> Enabling any feature implicitly enables its minimum dependencies.
> A report of enabled/disabled features is printed on every CMake configure.

### CCache (Highly Recommended)

```bash
# Fedora: install ccache
sudo dnf install ccache    # or: sudo rpm-ostree install ccache

# Setup and build with ccache
eval "$(./build_tools/setup_ccache.py)"
cmake -B build -GNinja -DTHEROCK_AMDGPU_FAMILIES=gfx1201 \
  -DCMAKE_C_COMPILER_LAUNCHER=ccache \
  -DCMAKE_CXX_COMPILER_LAUNCHER=ccache .
cmake --build build
```

### Running Tests

```bash
ctest --test-dir build
```

---

## GCC 15 Compatibility Patch

This fork includes a patch for GCC 15's stricter `<cstdint>` header compliance:

```
patches/amd-mainline/rocm-libraries/
└── 0001-rocm-libraries-Fix-GCC-15-cstdint-compatibility-in-f.patch
```

The patch adds `#include <stdint.h>` before `#include <cstdint>` in 6 headers
across rocBLAS, rocSPARSE, hipBLASLt, and Tensile. Without this fix, the build
fails with:

```
error: no member named 'intptr_t' in the global namespace
```

The patch is automatically applied by `fetch_sources.py`.

---

## Development Manuals

- [FAQ](docs/faq.md): Frequently asked questions
- [Contribution Guidelines](CONTRIBUTING.md): How to contribute
- [Development Guide](docs/development/development_guide.md): Daily driver development
- [Build System](docs/development/build_system.md): Build system internals
- [Environment Setup Guide](docs/environment_setup_guide.md): Environment setup and workarounds
- [Dependencies](docs/development/dependencies.md): ROCm dependency standards
- [Build Artifacts](docs/development/artifacts.md): Build output documentation

---

<div align="center">

**🔥 EXPERIMENTAL BUILD 🔥**

*Forked from [ROCm/TheRock](https://github.com/ROCm/TheRock) — targeting bleeding-edge hardware and software.*

*Built and tested on AMD Radeon AI PRO R9700 (gfx1201) — Fedora 43 Atomic — GCC 15 — Python 3.14*

---

*Special thanks to [Linus Torvalds](https://github.com/torvalds) for the vibing encouragements.*
*"Talk is cheap. Show me the code." — and so we did.*

</div>
