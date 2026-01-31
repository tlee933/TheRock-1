<p align="center">
  <strong>
    <samp>AMD Radeon AI PRO R9700 &mdash; RDNA 4 &mdash; gfx1201</samp>
  </strong>
</p>

<p align="center">
  <code>PyTorch 2.9.1</code> &nbsp;·&nbsp;
  <code>ROCm 7.11</code> &nbsp;·&nbsp;
  <code>Python 3.14</code> &nbsp;·&nbsp;
  <code>Fedora Atomic 43</code>
</p>

<p align="center">
  <em>First-ever PyTorch wheel targeting <code>gfx12-generic</code> on Python 3.14 — built from source via TheRock</em>
</p>

---

## Hardware

```
GPU     AMD Radeon AI PRO R9700        RDNA 4 · gfx1201 · 32 GB GDDR6
CPU     AMD Ryzen 9 5900X              12 cores · 24 threads
OS      Fedora Atomic 43               Linux 6.18.5
```

## Software

```
PyTorch   2.9.1+rocm7.11.0a20260118   built from source (-O2)
ROCm      7.11.0a20260118              TheRock, built from source (-O3)
Triton    3.6.0                        JIT targeting gfx1201
llama.cpp b7751                        compiled -O3 for gfx1201
Compiler  clang-22 (hipcc)             + GCC 15.2.1
Kernels   hipBLASLt Tensile            rocm-sdk-libraries-gfx120X-all
```

> All benchmarks run **natively** on RDNA 4 silicon — no `HSA_OVERRIDE_GFX_VERSION` hacks.

---

## Compute &mdash; `torch.mm`

### FP16 &emsp; _peak 124.89 TFLOPS_

<table>
<tr><th></th><th colspan="2">GPU idle</th><th colspan="2">+ Qwen3-30B loaded (23 GB)</th></tr>
<tr><th>Matrix</th><th>TFLOPS</th><th>ms</th><th>TFLOPS</th><th>ms</th></tr>
<tr><td><code>512</code></td>    <td>0.15</td>   <td>1.801</td> <td>11.88</td>  <td>0.023</td></tr>
<tr><td><code>1024</code></td>   <td>84.45</td>  <td>0.025</td> <td>59.81</td>  <td>0.036</td></tr>
<tr><td><code>2048</code></td>   <td>113.15</td> <td>0.152</td> <td>118.89</td> <td>0.144</td></tr>
<tr><td><b><code>4096</code></b></td><td><b>124.89</b></td><td><b>1.100</b></td><td><b>117.73</b></td><td><b>1.167</b></td></tr>
<tr><td><code>8192</code></td>   <td>116.60</td> <td>9.430</td> <td>112.69</td> <td>9.757</td></tr>
</table>

### BF16 &emsp; _peak 124.96 TFLOPS_

<table>
<tr><th></th><th colspan="2">GPU idle</th><th colspan="2">+ Qwen3-30B loaded (23 GB)</th></tr>
<tr><th>Matrix</th><th>TFLOPS</th><th>ms</th><th>TFLOPS</th><th>ms</th></tr>
<tr><td><code>1024</code></td>   <td>0.63</td>   <td>3.433</td> <td>85.86</td>  <td>0.025</td></tr>
<tr><td><code>2048</code></td>   <td>103.28</td> <td>0.166</td> <td>118.81</td> <td>0.145</td></tr>
<tr><td><b><code>4096</code></b></td><td><b>124.96</b></td><td><b>1.100</b></td><td><b>119.47</b></td><td><b>1.150</b></td></tr>
</table>

### FP32 &emsp; _peak 15.98 TFLOPS_

<table>
<tr><th></th><th colspan="2">GPU idle</th><th colspan="2">+ Qwen3-30B loaded (23 GB)</th></tr>
<tr><th>Matrix</th><th>TFLOPS</th><th>ms</th><th>TFLOPS</th><th>ms</th></tr>
<tr><td><code>512</code></td>    <td>0.21</td>  <td>1.291</td> <td>5.80</td>  <td>0.046</td></tr>
<tr><td><code>1024</code></td>   <td>14.51</td> <td>0.148</td> <td>15.20</td> <td>0.141</td></tr>
<tr><td><code>2048</code></td>   <td>14.54</td> <td>1.181</td> <td>13.99</td> <td>1.228</td></tr>
<tr><td><b><code>4096</code></b></td><td><b>15.98</b></td><td><b>8.602</b></td><td><b>15.19</b></td><td><b>9.046</b></td></tr>
</table>

> RDNA 4 delivers **~125 TFLOPS** half-precision through native Tensile kernels.
> Under 23 GB LLM load, throughput drops only **~6%** &mdash; 32 GB GDDR6 handles it.

---

## Inference &mdash; llama-server

### Qwen3-30B-A3B MoE &ensp; `Q4_K_M` &ensp; 23 GB VRAM &ensp; 40K ctx

```
                  Prompt tok/s    Generation tok/s
Short  (coding)        57 peak           83.7
Medium (explain)      463 peak           83.2
Long   (800 tok)      406 peak           82.9
```

> **30B total / 3B active** &mdash; MoE keeps decode memory-bound on fast GDDR6.
> Generation saturates at **83 tok/s** regardless of output length.

### Qwen3-14B Dense &ensp; `Q4_K_M` &ensp; 8.4 GB VRAM &ensp; 40K ctx

```
                  Prompt tok/s    Generation tok/s
Short  (coding)       270 peak           48.8
Medium (explain)      327 peak           48.3
Long   (800 tok)      350 peak           47.7
```

### Head to head

```
Model               Params   Active    VRAM      tok/s     vs 14B
─────────────────── ──────── ──────── ───────── ───────── ────────
Qwen3-14B Dense     14B      14B       8.4 GB    48        baseline
Qwen3-30B-A3B MoE   30B       3B      23   GB    83        1.73x
```

> The 30B MoE is **73% faster** while carrying 2x the knowledge &mdash;
> RDNA 4's 32 GB GDDR6 turns the MoE memory trade-off into pure upside.

---

## RDNA 4 observations

- **125 TFLOPS FP16/BF16** via hipBLASLt &mdash; matches AMD's rated spec for the R9700
- **16 TFLOPS FP32** &mdash; expected without packed math on RDNA 4
- **Native gfx1201** &mdash; no GFX version overrides, no emulation layers
- **32 GB GDDR6** &mdash; enough to serve a 30B MoE while running PyTorch training side-by-side
- **Concurrent workloads** &mdash; only 6% compute drop with 23 GB VRAM occupied by LLM
- **Triton 3.6** JIT-compiles directly for gfx1201 &mdash; FP8 via native WMMA instructions
- **No FBGEMM GenAI** &mdash; CK (Composable Kernel) doesn't support Wave32 yet (ETA H1 2026)
- Small matrices (512) are launch-overhead dominated, not representative
- 8192 shows slight bandwidth-limited throughput decrease

---

<p align="center">
  <sub>
    Benchmarked on Fedora Atomic 43 &middot; Linux 6.18.5 &middot; January 2026<br>
    Built with <a href="https://github.com/ROCm/TheRock">TheRock</a> &middot;
    <code>rocm-sdk-libraries-gfx120X-all</code>
  </sub>
</p>
