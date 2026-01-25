# 🚀 ROCm 7.12 Test Results

## AMD Radeon AI PRO R9700 (gfx1201) on Fedora Atomic

> **Status: ✅ ALL TESTS PASSING**

---

### 📋 Test Environment

| Component | Details |
|:----------|:--------|
| **Test Date** | 2026-01-25 |
| **Platform** | Fedora 43 (Aurora/Atomic) |
| **Compiler** | GCC 15.2.1 |
| **Target GPU** | AMD Radeon AI PRO R9700 |
| **Architecture** | gfx1201 (RDNA 4) |
| **GPU Memory** | 34.2 GB |
| **Host CPU** | AMD Ryzen 9 5900X 12-Core |

---

### 🧪 Test Results

```
╔═══════════════════════════════════════════════════════════════╗
║                    TEST SUITE RESULTS                        ║
╠═══════════════════════════════════════════════════════════════╣
║  rocrand basic .................... 44/44   ✅ PASSED        ║
║  rocrand C++ API .................. 30/30   ✅ PASSED        ║
║  rocrand generate ................. 47/47   ✅ PASSED        ║
║  rocrand hipgraphs ................ 57/57   ✅ PASSED        ║
║  normal distribution .............. 12/12   ✅ PASSED        ║
║  HIP compute kernel ...............  1/1    ✅ PASSED        ║
║  LLM inference (Qwen 30B) .........  1/1    ✅ PASSED        ║
╠═══════════════════════════════════════════════════════════════╣
║  TOTAL                              192     ✅ 100% PASS     ║
╚═══════════════════════════════════════════════════════════════╝
```

---

### ⚡ Performance Benchmarks

#### hipBLASLt Matrix Multiplication

| Precision | Matrix Size | TFLOPS | Latency | Status |
|:---------:|:-----------:|:------:|:-------:|:------:|
| **FP16** | 2048³ | **122.1** | 140.7 µs | 🟢 |
| **BF16** | 4096³ | **120.4** | 1141.5 µs | 🟢 |

#### rocrand Random Number Generation

| Engine | Sample Size | Throughput | Status |
|:------:|:-----------:|:----------:|:------:|
| xorwow | 1M samples | **243.9 GB/s** | 🟢 |

---

### 🖥️ GPU Detection

```
┌─────────────────────────────────────────────────────────────┐
│  AMD Radeon AI PRO R9700                                    │
├─────────────────────────────────────────────────────────────┤
│  Architecture      │  gfx1201 (RDNA 4)                      │
│  Memory            │  34.2 GB                               │
│  Max Shader Clock  │  2350 MHz                              │
│  Max Memory Clock  │  1258 MHz                              │
│  Compute Cap.      │  12.0                                  │
│  Max Grid Dim X    │  2,147,483,647                         │
│  Shared Mem/Block  │  65.5 KB                               │
│  Max Threads/Block │  1024                                  │
│  Warp Size         │  32                                    │
└─────────────────────────────────────────────────────────────┘
```

---

### 🔬 HIP Compute Verification

<details>
<summary>Click to expand test code</summary>

```cpp
#include <hip/hip_runtime.h>
#include <stdio.h>

__global__ void hello() {
    printf("Hello from GPU thread %d!\n", threadIdx.x);
}

int main() {
    int count;
    hipGetDeviceCount(&count);
    printf("Found %d GPU(s)\n", count);

    hipDeviceProp_t props;
    hipGetDeviceProperties(&props, 0);
    printf("GPU 0: %s (arch: %s)\n", props.name, props.gcnArchName);

    hello<<<1, 4>>>();
    hipDeviceSynchronize();
    printf("GPU compute test passed!\n");
    return 0;
}
```

</details>

**Output:**
```
Found 1 GPU(s)
GPU 0: AMD Radeon AI PRO R9700 (arch: gfx1201)
Hello from GPU thread 0!
Hello from GPU thread 1!
Hello from GPU thread 2!
Hello from GPU thread 3!
GPU compute test passed!
```

---

### 🤖 LLM Inference Test

| Parameter | Value |
|:----------|:------|
| **Model** | Qwen3-30B-A3B (Q4_K_M) |
| **Backend** | llama.cpp + ROCm/HIP |
| **Context Size** | 65,536 tokens |
| **GPU Offload** | 100% (all layers) |
| **Result** | ✅ Inference working |

---

### 📦 Components Built

<details>
<summary>Click to expand full component list</summary>

| Category | Components |
|:---------|:-----------|
| **Compiler** | amd-llvm (LLVM/Clang) |
| **Runtime** | HIP, CLR, ROCR-Runtime |
| **Math Libraries** | rocBLAS, rocSOLVER, hipBLAS, hipBLASLt, rocFFT, rocRAND |
| **ML Libraries** | MIOpen |
| **Communication** | RCCL |
| **Profiling** | rocprofiler-systems |
| **Debug** | rocgdb |

</details>

---

### ⚠️ Known Limitations

| Issue | Workaround |
|:------|:-----------|
| PDF docs require TeX | Disabled on atomic systems |
| atomic_codegen tests need cuobjdump | Skipped (CUDA-only tool) |
| GCC 15 strictness | Fixes documented in `GCC15_FIXES.md` |

---

### 🔧 Build Configuration

```bash
cmake -B build -GNinja \
  -DTHEROCK_AMDGPU_FAMILIES=gfx1201 \
  -DCMAKE_C_COMPILER_LAUNCHER=ccache \
  -DCMAKE_CXX_COMPILER_LAUNCHER=ccache
```

---

<div align="center">

**🧪 EXPERIMENTAL BUILD 🧪**

*This is an experimental build for gfx1201 (RDNA 4) on Fedora Atomic.*
*See `GCC15_FIXES.md` for required patches.*

</div>
