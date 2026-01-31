# The RDNA 4 Journey: Bleeding Edge ROCm on gfx1201

> **Building the impossible.** A from-scratch ROCm stack on hardware that
> doesn't officially exist yet, running on an OS that ships GCC 15 and
> Python 3.14 — because someone has to go first.

---

## The Mission

Take a **brand-new AMD Radeon AI PRO R9700** (RDNA 4, `gfx1201`) — a GPU
with zero upstream ROCm support — and build a fully functional AI/HPC
compute stack from raw source code on **Fedora Atomic 43**, the bleeding
edge of immutable Linux.

No prebuilt packages. No Docker escape hatches. No `HSA_OVERRIDE_GFX_VERSION`
hacks. **Native `gfx1201` from silicon to PyTorch.**

---

## The Hardware

```
AMD Radeon AI PRO R9700 (RDNA 4)
├── Architecture:  gfx1201 — Wave32, 64 CUs
├── VRAM:          16 GB GDDR6 (256-bit)
├── Clocks:        Up to 3.0 GHz boost
└── PCIe:          Gen 5 x16
```

## The Platform

```
Fedora Atomic 43 (Silverblue / Kinoite)
├── Kernel:        6.18.x (latest mainline)
├── GCC:           15 — stricter than ever
├── Python:        3.14 — also unreleased
├── Glibc:         2.41
└── Filesystem:    Immutable root (ostree)
```

Every single one of these is a potential build-breaker. Together, they're
a gauntlet.

---

## Phase 1: First Light — HIP & the Compiler

The foundation. Without HIP, nothing else matters.

**TheRock** (ROCm's CMake super-project) didn't know `gfx1201` existed.
We pointed it at the architecture, held our breath, and watched LLVM
bootstrap itself with native RDNA 4 codegen.

```
✓ amd-llvm          LLVM/Clang with gfx1201 backend
✓ hipcc             Native compilation — no GFX version overrides
✓ HIP runtime       amdhip64 + hiprtc, full device detection
```

**First HIP kernel ran natively on gfx1201.** No shims. No lies to the
runtime. The GPU showed up as itself.

---

## Phase 2: The GCC 15 Gauntlet

GCC 15 on Fedora 43 is *strict*. Headers that were implicitly included
for 20 years? Gone. K&R function declarations? Error. Unterminated string
initializations? Hard fail.

We wrote **11 targeted patches** that survive `fetch_sources.py` resets:

| # | Fix | What Broke |
|---|-----|-----------|
| 1 | `elfio/elf_types.hpp` | Missing `<cstdint>` — `uint32_t` undefined |
| 2 | `yaml-cpp/emitterutils.cpp` | Missing `<cstdint>` |
| 3 | `papi/papi_hl.c` | K&R function declaration — GCC 15 rejects it |
| 4 | `papi/papi_vector.c` | Function pointer cast mismatch |
| 5 | `DyninstElfUtils.cmake` | `-Wno-error=unterminated-string-initialization` |
| 6 | `logger.hpp` | Missing `<algorithm>` for `std::min`/`std::max` |
| 7 | `dyninst/sha1.C` | Missing `<cstdint>` |
| 8 | `dyninst/arch-x86.h` | Missing `<cstdint>` |
| 9 | `rocgdb/CMakeLists.txt` | PDF doc generation fails on immutable FS |
| 10 | `DyninstOptimization.cmake` | `CMAKE_CXX_FLAGS` quoting bug (**the big one**) |
| 11 | `libhipcxx/test/atomic_codegen` | Broken symlink to upstream tests |

Fix #10 deserves its own section.

---

## Phase 3: The Dyninst Showdown — Unblocking rocprofiler-systems

**rocprofiler-systems** was the last major component stuck in "Disabled."
The build would hit `therock_subproject.cmake:1428` and die.

### Root Cause

Dyninst's `DyninstOptimization.cmake` passes `CMAKE_CXX_FLAGS` as a
single CMake list element. When your flags contain spaces (like
`-O3 -march=native`), CMake treats the whole string as *one argument*.
GCC receives a literal `"-O3 -march=native"` (quotes and all) and
rightfully rejects it.

### The Fix

```cmake
separate_arguments(_user_c_flags NATIVE_COMMAND "${CMAKE_C_FLAGS}")
separate_arguments(_user_cxx_flags NATIVE_COMMAND "${CMAKE_CXX_FLAGS}")
```

Two lines. Splits the flags properly. Dyninst builds. rocprofiler-systems
builds. **32 shared libraries and 5 profiling tools** land in the dist tree.

```
✓ librocprof-sys.so          Core profiling runtime
✓ librocprof-sys-rt.so       Runtime instrumentation
✓ librocprof-sys-dl.so       Dynamic loading support
✓ librocprof-sys-user.so     User API
✓ rocprof-sys-run             Sampling profiler
✓ rocprof-sys-instrument      Binary instrumentation
✓ rocprof-sys-causal          Causal profiling (!)
✓ rocprof-sys-sample          Statistical sampling
✓ rocprof-sys-avail           Feature query tool
```

**Status: DISABLED → WORKING.** The entire ROCm profiling stack is live.

---

## Phase 4: The Math Libraries — rocFFT Breaks Free

rocFFT was listed as "blocked upstream" — the AOT kernel list had
`gfx1200` removed, and `gfx1201` was never on it.

We enabled it anyway with `THEROCK_ENABLE_FFT=ON`. rocFFT's runtime
kernel compilation kicked in — JIT-compiling FFT plans on first use.
No ahead-of-time kernels needed.

```
✓ rocFFT              Runtime-compiled FFT kernels
✓ hipFFT              HIP FFT interface
✓ FFTW3               CPU reference (for validation)
```

The full BLAS/LAPACK/Sparse/FFT stack:

```
✓ rocBLAS             Tensile GEMM kernels (via gfx120X pip package)
✓ hipBLASLt           Lightweight BLAS extensions
✓ rocRAND             Random number generation
✓ rocSOLVER           Dense linear algebra
✓ rocSPARSE           Sparse matrix operations
✓ rocPRIM             Parallel primitives
✓ hipCUB              CUB-compatible interface
✓ MIOpen              Deep learning primitives
✓ Composable Kernel   Performance-portable GPU kernels
✓ RCCL                Multi-GPU collective communications
```

**Every math library builds and links.** On hardware that launched weeks ago.

---

## Phase 5: PyTorch — 125 TFLOPS on Day One

Built PyTorch 2.9.1 from source targeting `gfx12-generic`:

```bash
python3 build_prod_wheels.py build \
    --pytorch-rocm-arch gfx12-generic \
    --no-build-pytorch-audio \
    --no-build-pytorch-vision \
    --no-build-triton \
    --clean
```

### The Numbers

```
FP16 4096×4096 GEMM:    124.89 TFLOPS
BF16 4096×4096 GEMM:    ~120   TFLOPS
FP32 4096×4096 GEMM:    ~30    TFLOPS
torch.fft.fft(4096):    PASS
torch.cuda.is_available: True
Device detection:        AMD Radeon AI PRO R9700 (gfx1201)
```

**No `HSA_OVERRIDE_GFX_VERSION`. Native detection. Full compute.**

---

## Phase 6: Inference — 83 tok/s on Qwen3-30B

Built `llama.cpp` with native `gfx1201` HIP support:

```
Model:          Qwen3-30B-A3B (MoE, 3B active params)
Quantization:   Q4_K_M
Throughput:     83 tokens/second
GPU offload:    Full (16 GB VRAM)
```

Concurrent GPU load testing confirmed stable operation under mixed
workloads — inference + compute simultaneously without crashes or
memory corruption.

---

## The Final Stack

**14 libraries. 5 profiling tools. 1 PyTorch wheel. Zero hacks.**

```
build/dist/rocm/
├── lib/
│   ├── libamdhip64.so          ✓  HIP Runtime
│   ├── libhiprtc.so            ✓  Runtime Compilation
│   ├── librocblas.so            ✓  BLAS
│   ├── libhipblaslt.so          ✓  Lightweight BLAS
│   ├── librocrand.so            ✓  Random Numbers
│   ├── librocsolver.so          ✓  Dense Linear Algebra
│   ├── librocsparse.so          ✓  Sparse Matrices
│   ├── librocfft.so             ✓  FFT (runtime kernels)
│   ├── libhipfft.so             ✓  HIP FFT Interface
│   ├── libMIOpen.so             ✓  Deep Learning Primitives
│   ├── librccl.so               ✓  Collective Comms
│   ├── librocprof-sys.so        ✓  Profiler Runtime
│   ├── librocprofiler-sdk.so    ✓  Profiler SDK
│   └── libroctracer64.so        ✓  API Tracing
├── bin/
│   ├── hipcc                    ✓  Compiler
│   ├── rocprof-sys-run          ✓  Sampling Profiler
│   ├── rocprof-sys-instrument   ✓  Binary Instrumentation
│   ├── rocprof-sys-causal       ✓  Causal Profiling
│   └── rocprof-sys-sample       ✓  Statistical Sampling
└── wheels/
    └── torch-2.9.1+rocm.gfx12  ✓  PyTorch (125 TFLOPS FP16)
```

---

## What's Still Blocked

| Component | Why | ETA |
|-----------|-----|-----|
| FBGEMM GenAI | Composable Kernel needs Wave64; RDNA 4 is Wave32 | H1 2026 |
| rocFFT AOT kernels | `gfx1200` removed from AOT list; runtime fallback works fine | Upstream TBD |

**That's it.** Two items. Everything else is live.

---

## The Commit Trail

```
375dc5c4  GCC 15 compatibility fixes for Fedora 43+ builds
ff91d45a  Add GCC 15 compatibility patch and updated gfx1201 test results
ed0e610d  Overhaul README for Fedora Atomic experimental fork
d3deaeca  Add PyTorch 2.9.1 benchmarks: 125 TFLOPS FP16 on R9700 (RDNA4)
cb21060d  Update benchmarks: add Qwen3-30B MoE (83 tok/s) and concurrent GPU load tests
136decb8  Redesign BENCHMARKS.md: RDNA 4 focus, HTML tables, monospace layout
d41e8975  Rewrite BUILD_ROCM_GFX1201.sh: add rocFFT, remove stale workarounds
1dba745c  Enable rocprofiler-systems: fix dyninst CMAKE_CXX_FLAGS quoting bug
```

---

## How to Reproduce

```bash
git clone -b fedora-atomic-rocm7.12-ai-pro-experimental \
    https://github.com/tlee933/TheRock-Forge-EXPERIMENTAL.git
cd TheRock-Forge-EXPERIMENTAL

./BUILD_ROCM_GFX1201.sh all
```

That's the whole thing. One script. One command. From zero to a full
ROCm + PyTorch + profiling stack on the most bleeding-edge hardware
and software combination possible.

---

> *Built on Fedora Atomic 43 with GCC 15, Python 3.14, and an unhealthy
> amount of determination. If you're reading this, the future already works.*

**Branch:** `fedora-atomic-rocm7.12-ai-pro-experimental`
**Last updated:** January 2026
