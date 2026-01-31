# PyTorch 2.9.1 Benchmarks on AMD Radeon AI PRO R9700

> Built from source with ROCm 7.11 on Fedora Atomic Linux
> First-ever PyTorch wheel for **Python 3.14** + **RDNA4** (`gfx12-generic`)

---

## System Configuration

| Component | Detail |
|-----------|--------|
| **GPU** | AMD Radeon AI PRO R9700 (gfx1201, RDNA4) |
| **VRAM** | 32 GB GDDR6 |
| **CPU** | 12 threads |
| **OS** | Fedora Atomic (Linux 6.18.5) |
| **Python** | 3.14.2 |
| **PyTorch** | 2.9.1+rocm7.11.0a20260118 |
| **ROCm** | 7.11.0a20260118 |
| **Target Arch** | `gfx12-generic` |
| **Build Type** | Release (-O3 ROCm / -O2 PyTorch) |
| **Compiler** | clang-22 (hipcc) + GCC 15.2.1 |

---

## FP16 Matrix Multiply (torch.mm)

| Matrix Size | TFLOPS | ms/iter |
|:-----------:|:------:|:-------:|
| 512x512 | 0.15 | 1.801 |
| 1024x1024 | 84.45 | 0.025 |
| 2048x2048 | 113.15 | 0.152 |
| **4096x4096** | **124.89** | **1.100** |
| 8192x8192 | 116.60 | 9.430 |

**Peak: 124.89 TFLOPS FP16** at 4096x4096

---

## BF16 Matrix Multiply (torch.mm)

| Matrix Size | TFLOPS | ms/iter |
|:-----------:|:------:|:-------:|
| 1024x1024 | 0.63 | 3.433 |
| 2048x2048 | 103.28 | 0.166 |
| **4096x4096** | **124.96** | **1.100** |

**Peak: 124.96 TFLOPS BF16** at 4096x4096

---

## FP32 Matrix Multiply (torch.mm)

| Matrix Size | TFLOPS | ms/iter |
|:-----------:|:------:|:-------:|
| 512x512 | 0.21 | 1.291 |
| 1024x1024 | 14.51 | 0.148 |
| 2048x2048 | 14.54 | 1.181 |
| **4096x4096** | **15.98** | **8.602** |

**Peak: 15.98 TFLOPS FP32** at 4096x4096

---

## LLM Inference (llama-server)

Running **Qwen3-14B Q4_K_M** (8.4 GB VRAM, 40K context) concurrently:

| Benchmark | Prompt (tok/s) | Generation (tok/s) |
|-----------|:--------------:|:------------------:|
| Short (coding) | 270 peak | **48.8** |
| Medium (explanation) | 327 peak | **48.3** |
| Long (800 tok essay) | 350 peak | **47.7** |

> llama-server build 7751, compiled with `-O3` for `gfx1201`

---

## Notes

- The R9700 delivers ~125 TFLOPS in both FP16 and BF16 via hipBLASLt Tensile kernels
- FP32 peaks at ~16 TFLOPS (expected for RDNA4 without packed math)
- Small matrix sizes (512) are kernel-launch dominated, not representative
- 8192x8192 shows slight throughput decrease likely due to memory bandwidth limits
- LLM inference runs comfortably alongside PyTorch workloads with 32 GB VRAM
- Built against `rocm-sdk-libraries-gfx120X-all` for native gfx1201 Tensile kernel support
