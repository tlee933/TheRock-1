# PyTorch 2.9.1 + LLM Inference Benchmarks on AMD Radeon AI PRO R9700

> Built from source with ROCm 7.11 on Fedora Atomic Linux
> First-ever PyTorch wheel for **Python 3.14** + **RDNA4** (`gfx12-generic`)

---

## System Configuration

| Component | Detail |
|-----------|--------|
| **GPU** | AMD Radeon AI PRO R9700 (gfx1201, RDNA4) |
| **VRAM** | 32 GB GDDR6 |
| **CPU** | AMD Ryzen 9 5900X (12C/24T) |
| **OS** | Fedora Atomic 43 (Linux 6.18.5) |
| **Python** | 3.14.2 |
| **PyTorch** | 2.9.1+rocm7.11.0a20260118 |
| **ROCm** | 7.11.0a20260118 (TheRock, built from source) |
| **Target Arch** | `gfx12-generic` |
| **Build Type** | Release (-O3 ROCm / -O2 PyTorch) |
| **Compiler** | clang-22 (hipcc) + GCC 15.2.1 |
| **Triton** | 3.6.0 (JIT for gfx1201) |
| **llama.cpp** | Build 7751, compiled `-O3` for `gfx1201` |

---

## FP16 Matrix Multiply — `torch.mm`

### GPU Idle (full VRAM available)

| Matrix Size | TFLOPS | ms/iter |
|:-----------:|:------:|:-------:|
| 512x512 | 0.15 | 1.801 |
| 1024x1024 | 84.45 | 0.025 |
| 2048x2048 | 113.15 | 0.152 |
| **4096x4096** | **124.89** | **1.100** |
| 8192x8192 | 116.60 | 9.430 |

### Concurrent with Qwen3-30B MoE (23 GB VRAM occupied)

| Matrix Size | TFLOPS | ms/iter |
|:-----------:|:------:|:-------:|
| 512x512 | 11.88 | 0.023 |
| 1024x1024 | 59.81 | 0.036 |
| 2048x2048 | 118.89 | 0.144 |
| **4096x4096** | **117.73** | **1.167** |
| 8192x8192 | 112.69 | 9.757 |

> **Peak: 124.89 TFLOPS FP16** (idle) / **117.73 TFLOPS** (under LLM load)

---

## BF16 Matrix Multiply — `torch.mm`

### GPU Idle

| Matrix Size | TFLOPS | ms/iter |
|:-----------:|:------:|:-------:|
| 1024x1024 | 0.63 | 3.433 |
| 2048x2048 | 103.28 | 0.166 |
| **4096x4096** | **124.96** | **1.100** |

### Concurrent with Qwen3-30B MoE

| Matrix Size | TFLOPS | ms/iter |
|:-----------:|:------:|:-------:|
| 1024x1024 | 85.86 | 0.025 |
| 2048x2048 | 118.81 | 0.145 |
| **4096x4096** | **119.47** | **1.150** |

> **Peak: 124.96 TFLOPS BF16** (idle) / **119.47 TFLOPS** (under LLM load)

---

## FP32 Matrix Multiply — `torch.mm`

### GPU Idle

| Matrix Size | TFLOPS | ms/iter |
|:-----------:|:------:|:-------:|
| 512x512 | 0.21 | 1.291 |
| 1024x1024 | 14.51 | 0.148 |
| 2048x2048 | 14.54 | 1.181 |
| **4096x4096** | **15.98** | **8.602** |

### Concurrent with Qwen3-30B MoE

| Matrix Size | TFLOPS | ms/iter |
|:-----------:|:------:|:-------:|
| 512x512 | 5.80 | 0.046 |
| 1024x1024 | 15.20 | 0.141 |
| 2048x2048 | 13.99 | 1.228 |
| **4096x4096** | **15.19** | **9.046** |

> **Peak: 15.98 TFLOPS FP32** (idle) / **15.19 TFLOPS** (under LLM load)

---

## LLM Inference — llama-server

### Qwen3-30B-A3B MoE (Q4_K_M) — 23 GB VRAM, 40K context

| Benchmark | Prompt (tok/s) | Generation (tok/s) |
|-----------|:--------------:|:------------------:|
| Short (coding) | 57 peak | **83.7** |
| Medium (explanation) | 463 peak | **83.2** |
| Long (800 tok essay) | 406 peak | **82.9** |

> 30B total parameters, 3B active per token (MoE) — **83+ tok/s generation**

### Qwen3-14B Dense (Q4_K_M) — 8.4 GB VRAM, 40K context

| Benchmark | Prompt (tok/s) | Generation (tok/s) |
|-----------|:--------------:|:------------------:|
| Short (coding) | 270 peak | **48.8** |
| Medium (explanation) | 327 peak | **48.3** |
| Long (800 tok essay) | 350 peak | **47.7** |

> Dense 14B model — **48+ tok/s generation**

### Model Comparison

| Model | Parameters | Active | VRAM | Gen tok/s | Speedup |
|-------|:---------:|:------:|:----:|:---------:|:-------:|
| Qwen3-14B Dense | 14B | 14B | 8.4 GB | 48 | baseline |
| **Qwen3-30B-A3B MoE** | **30B** | **3B** | **23 GB** | **83** | **1.73x** |

---

## Notes

- The R9700 delivers **~125 TFLOPS** in both FP16 and BF16 via hipBLASLt Tensile kernels
- Under concurrent LLM load (23 GB VRAM), compute throughput drops only ~6% to ~118 TFLOPS
- FP32 peaks at **~16 TFLOPS** (expected for RDNA4 without packed math)
- Small matrix sizes (512) are kernel-launch dominated, not representative of peak throughput
- 8192x8192 shows slight throughput decrease due to memory bandwidth limits
- The 30B MoE model achieves **1.73x** the generation speed of the dense 14B despite 2.7x more VRAM — the 3B active parameter count keeps decode memory-bound on fast GDDR6
- LLM inference and PyTorch training/inference run comfortably side-by-side with 32 GB VRAM
- Built against `rocm-sdk-libraries-gfx120X-all` for native gfx1201 Tensile kernel support
- All benchmarks run natively — no `HSA_OVERRIDE_GFX_VERSION` hacks required
