#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
#  TheRock ROCm Build Script — gfx1201 (AMD Radeon AI PRO R9700 / RDNA 4)
#  Platform: Fedora Atomic 43 · GCC 15 · Python 3.14
#═══════════════════════════════════════════════════════════════════════════════
#
#  Usage:
#    ./BUILD_ROCM_GFX1201.sh [command]
#
#  Commands:
#    update      Pull latest upstream and rebase
#    fixes       Check/apply GCC 15 compatibility patches
#    configure   Configure optimized CMake build
#    build       Build ROCm from source (~3-4 hours with -j4)
#    install     Setup /opt/rocm symlink and environment
#    pip-libs    Install gfx120X ROCm pip packages (Tensile kernels)
#    pytorch     Build PyTorch 2.9.1 wheel for gfx12-generic
#    llama       Build llama.cpp for gfx1201
#    test        Run verification suite
#    push        Push to tlee933 fork
#    status      Show component status
#    all         Run full pipeline
#
#═══════════════════════════════════════════════════════════════════════════════
#
#  STATUS — January 2026
#
#  Working:
#    ✓ HIP runtime / hipcc         Native gfx1201, no HSA_OVERRIDE needed
#    ✓ rocBLAS / hipBLASLt          Tensile kernels via gfx120X pip package
#    ✓ rocRAND / rocSOLVER          Built from source
#    ✓ rocSPARSE / rocPRIM          Built from source
#    ✓ MIOpen / Composable Kernel   Built from source
#    ✓ RCCL                         Multi-GPU comms
#    ✓ rocFFT / hipFFT              Built from source (runtime-compiled kernels)
#    ✓ PyTorch 2.9.1                124.89 TFLOPS FP16 · gfx12-generic wheel
#    ✓ Triton 3.6                   JIT targeting gfx1201
#    ✓ llama.cpp                    83 tok/s Qwen3-30B MoE · native gfx1201
#
#  Disabled:
#    ✗ rocprofiler-systems          dyninst CMAKE_CXX_FLAGS quoting bug
#                                   (therock_subproject.cmake:1428)
#
#  Blocked upstream:
#    ✗ FBGEMM GenAI                 CK needs Wave64, RDNA4 is Wave32 (ETA H1 2026)
#    ✗ rocFFT AOT kernels           gfx1200 removed from AOT list, runtime fallback
#
#═══════════════════════════════════════════════════════════════════════════════

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ─── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[  OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ ERR]${NC} $1"; }
log_step()  { echo -e "\n${BOLD}${CYAN}═══ $1 ═══${NC}\n"; }

# ─── Configuration ───────────────────────────────────────────────────────────
ROCM_INSTALL=/opt/rocm
ROCM_DIST="$SCRIPT_DIR/build/dist/rocm"
PYTORCH_DIR="$SCRIPT_DIR/external-builds/pytorch"
GPU_ARCH=gfx1201
GPU_ARCH_GENERIC=gfx12-generic
ROCM_NIGHTLY_VERSION="7.11.0a20260118"
ROCM_NIGHTLY_INDEX="https://rocm.nightlies.amd.com/v2/gfx120X-all/"

#═══════════════════════════════════════════════════════════════════════════════
# UPDATE: Pull latest upstream and rebase
#═══════════════════════════════════════════════════════════════════════════════
do_update() {
    log_step "UPDATE"
    log_info "Fetching upstream changes..."
    git fetch origin

    local behind=$(git rev-list HEAD..origin/main --count 2>/dev/null || echo 0)
    if [ "$behind" -gt 0 ]; then
        log_info "Main is $behind commits ahead, rebasing..."
        git stash
        git checkout main
        git pull origin main
        git checkout fedora-atomic-rocm7.12-ai-pro-experimental
        git rebase main
        log_ok "Branch rebased on latest main"
    else
        log_ok "Already up to date with main"
    fi
}

#═══════════════════════════════════════════════════════════════════════════════
# FIXES: GCC 15 compatibility patches
#═══════════════════════════════════════════════════════════════════════════════
#
# These patches are needed after running fetch_sources.py (which resets
# submodules). They fix GCC 15's stricter <cstdint> and K&R requirements.
#
do_fixes() {
    log_step "GCC 15 FIXES"

    local applied=0
    local total=0

    apply_fix() {
        local file="$1"
        local check="$2"
        local desc="$3"
        local cmd="$4"
        total=$((total + 1))

        if [ ! -f "$file" ]; then
            log_warn "File not found: $file"
            return
        fi

        if grep -q "$check" "$file" 2>/dev/null; then
            echo -e "  ${DIM}✓ $desc${NC}"
            return
        fi

        log_info "Applying: $desc"
        eval "$cmd"
        applied=$((applied + 1))
    }

    # Fix 1: elfio elf_types.hpp — missing cstdint
    apply_fix \
        "rocm-systems/projects/rocprofiler-sdk/external/elfio/elfio/elf_types.hpp" \
        "#include <cstdint>" \
        "elfio/elf_types.hpp (cstdint)" \
        "sed -i '/#define ELFIO_ELF_TYPES_HPP/a #include <cstdint>' \"\$file\""

    # Fix 2: yaml-cpp emitterutils.cpp — missing cstdint
    apply_fix \
        "rocm-systems/projects/rocprofiler-sdk/external/yaml-cpp/src/emitterutils.cpp" \
        "#include <cstdint>" \
        "yaml-cpp/emitterutils.cpp (cstdint)" \
        "sed -i '/#include <algorithm>/a #include <cstdint>' \"\$file\""

    # Fix 3: PAPI papi_hl.c — K&R function declaration
    apply_fix \
        "rocm-systems/projects/rocprofiler-systems/external/papi/src/high-level/papi_hl.c" \
        "const char \*user_events" \
        "papi/papi_hl.c (K&R declaration)" \
        "sed -i 's/static int _internal_hl_read_user_events();/static int _internal_hl_read_user_events(const char *user_events);/' \"\$file\""

    # Fix 4: PAPI papi_vector.c — function pointer cast
    apply_fix \
        "rocm-systems/projects/rocprofiler-systems/external/papi/src/papi_vector.c" \
        "papi_mdi_t" \
        "papi/papi_vector.c (function pointer)" \
        "sed -i 's/v->get_system_info = ( int ( \* )(  ) ) vec_int_dummy;/v->get_system_info = ( int ( * )( papi_mdi_t * ) ) vec_int_dummy;/' \"\$file\""

    # Fix 5: DyninstElfUtils.cmake — unterminated-string-initialization
    apply_fix \
        "rocm-systems/projects/rocprofiler-systems/cmake/DyninstElfUtils.cmake" \
        "Wno-error=unterminated-string-initialization" \
        "DyninstElfUtils.cmake (elfutils CFLAGS)" \
        "sed -i 's/CFLAGS=-fPIC\\\\ -O3/CFLAGS=-fPIC\\\\ -O3\\\\ -Wno-error=unterminated-string-initialization/' \"\$file\""

    # Fix 6: logger.hpp — missing algorithm header
    apply_fix \
        "rocm-systems/projects/rocprofiler-systems/source/lib/logger/logger.hpp" \
        "#include <algorithm>" \
        "logger.hpp (algorithm)" \
        "sed -i '/#include <spdlog\\/spdlog.h>/a #include <algorithm>' \"\$file\""

    # Fix 7: sha1.C — missing cstdint
    apply_fix \
        "rocm-systems/projects/rocprofiler-systems/external/dyninst/common/src/sha1.C" \
        "#include <cstdint>" \
        "dyninst/sha1.C (cstdint)" \
        "sed -i '1i #include <cstdint>' \"\$file\""

    # Fix 8: arch-x86.h — missing cstdint
    apply_fix \
        "rocm-systems/projects/rocprofiler-systems/external/dyninst/common/src/arch-x86.h" \
        "#include <cstdint>" \
        "dyninst/arch-x86.h (cstdint)" \
        "sed -i '/#include \"dyn_register.h\"/a #include <cstdint>' \"\$file\""

    # Fix 9: rocgdb PDF docs — fails on bootc/atomic systems
    apply_fix \
        "debug-tools/rocgdb/CMakeLists.txt" \
        "# Skipped:" \
        "rocgdb/CMakeLists.txt (skip PDF docs)" \
        "sed -i 's/\${MAKE_EXECUTABLE} -s -C gdb install-pdf install-html/# Skipped: \${MAKE_EXECUTABLE} -s -C gdb install-pdf install-html/' \"\$file\""

    # Fix 10: libhipcxx atomic_codegen symlink
    local link10="math-libs/libhipcxx/test/atomic_codegen"
    total=$((total + 1))
    if [ -L "$link10" ] && [ -e "$link10" ]; then
        echo -e "  ${DIM}✓ libhipcxx/test/atomic_codegen symlink${NC}"
    else
        log_info "Applying: libhipcxx atomic_codegen symlink"
        cd math-libs/libhipcxx/test
        ln -sf ../../._upstream/.upstream-tests/atomic_codegen atomic_codegen
        cd "$SCRIPT_DIR"
        applied=$((applied + 1))
    fi

    echo ""
    if [ "$applied" -eq 0 ]; then
        log_ok "All $total GCC 15 fixes already applied"
    else
        log_ok "Applied $applied of $total fixes"
    fi
}

#═══════════════════════════════════════════════════════════════════════════════
# CONFIGURE: CMake build setup
#═══════════════════════════════════════════════════════════════════════════════
do_configure() {
    log_step "CONFIGURE"
    log_info "Configuring build for $GPU_ARCH..."

    cmake -B build -GNinja \
        -DTHEROCK_AMDGPU_FAMILIES=$GPU_ARCH \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_COMPILER_LAUNCHER=ccache \
        -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
        -DCMAKE_C_FLAGS="-O3 -march=native" \
        -DCMAKE_CXX_FLAGS="-O3 -march=native" \
        -DTHEROCK_ENABLE_FFT=ON \
        -DTHEROCK_ENABLE_FFTW3=ON \
        -DTHEROCK_ENABLE_ROCPROFSYS=OFF

    log_ok "Configuration complete"
}

#═══════════════════════════════════════════════════════════════════════════════
# BUILD: Compile ROCm
#═══════════════════════════════════════════════════════════════════════════════
do_build() {
    log_step "BUILD"

    local jobs="${2:-4}"
    log_info "Building with -j$jobs..."

    if [ "$1" == "--background" ]; then
        nohup ninja -C build -j"$jobs" > build.log 2>&1 &
        echo $! > build.pid
        log_ok "Build started in background (PID: $(cat build.pid))"
        log_info "Monitor: tail -f build.log"
    else
        ninja -C build -j"$jobs" 2>&1 | tee build.log
        log_ok "Build complete"
    fi
}

#═══════════════════════════════════════════════════════════════════════════════
# INSTALL: Setup /opt/rocm symlink and environment
#═══════════════════════════════════════════════════════════════════════════════
do_install() {
    log_step "INSTALL"

    if [ ! -d "$ROCM_DIST" ]; then
        log_error "$ROCM_DIST not found — run build first"
        exit 1
    fi

    # /opt/rocm symlink
    if [ -L "$ROCM_INSTALL" ]; then
        local target=$(readlink -f "$ROCM_INSTALL")
        log_ok "/opt/rocm -> $target"
    else
        log_info "Creating /opt/rocm symlink (requires sudo)"
        sudo ln -sf "$ROCM_DIST" "$ROCM_INSTALL"
        log_ok "/opt/rocm -> $ROCM_DIST"
    fi

    # ldconfig
    if [ ! -f "/etc/ld.so.conf.d/rocm.conf" ]; then
        log_info "Creating ldconfig entry (requires sudo)"
        printf '%s\n' "$ROCM_INSTALL/lib" "$ROCM_INSTALL/lib64" \
            | sudo tee /etc/ld.so.conf.d/rocm.conf > /dev/null
        sudo ldconfig
    fi

    # Environment setup script
    cat > rocm_env.sh << 'ENVEOF'
#!/bin/bash
# ROCm Environment — TheRock 7.11 / gfx1201 / RDNA 4
# No HSA_OVERRIDE_GFX_VERSION needed — native gfx1201 detection

export ROCM_PATH=/opt/rocm
export HIP_PATH=$ROCM_PATH
export HIP_PLATFORM=amd
export HIP_COMPILER=clang

# PATH (guard against duplicates)
[[ ":$PATH:" != *":$ROCM_PATH/bin:"* ]] && export PATH=$ROCM_PATH/bin:$ROCM_PATH/lib/llvm/bin:$PATH

# Libraries (flat assignment, not append)
export LD_LIBRARY_PATH=$ROCM_PATH/lib:$ROCM_PATH/lib64

# GPU tuning
export GPU_DEVICE_ORDINAL=0
export GPU_MAX_HW_QUEUES=8
export HSA_ENABLE_SDMA=0
export AMD_DIRECT_DISPATCH=0
export HSA_XNACK=0

# PyTorch
export PYTORCH_ROCM_ARCH=gfx1201
export HIP_VISIBLE_DEVICES=0
ENVEOF
    chmod +x rocm_env.sh

    log_ok "Installation complete"
    log_info "Source environment: source rocm_env.sh"
}

#═══════════════════════════════════════════════════════════════════════════════
# PIP-LIBS: Install gfx120X ROCm packages (Tensile kernels)
#═══════════════════════════════════════════════════════════════════════════════
do_pip_libs() {
    log_step "PIP LIBRARIES (gfx120X)"

    log_info "Installing ROCm $ROCM_NIGHTLY_VERSION gfx120X packages..."
    log_info "These provide pre-compiled Tensile kernels for hipBLASLt on RDNA 4"

    pip install --force-reinstall --pre \
        --index-url "$ROCM_NIGHTLY_INDEX" \
        "rocm[libraries,devel]==$ROCM_NIGHTLY_VERSION"

    # Verify
    local pkg=$(pip show rocm-sdk-libraries-gfx120X-all 2>/dev/null | grep Version)
    if [ -n "$pkg" ]; then
        log_ok "Installed: $pkg"
    else
        log_warn "gfx120X package may not have installed correctly"
    fi

    # Remove stale gfx110X if present
    if pip show rocm-sdk-libraries-gfx110X-all &>/dev/null; then
        log_info "Removing stale gfx110X package..."
        pip uninstall -y rocm-sdk-libraries-gfx110X-all
        log_ok "gfx110X removed"
    fi
}

#═══════════════════════════════════════════════════════════════════════════════
# PYTORCH: Build PyTorch wheel for gfx12-generic
#═══════════════════════════════════════════════════════════════════════════════
do_pytorch() {
    log_step "PYTORCH BUILD"

    if [ ! -f "$PYTORCH_DIR/build_prod_wheels.py" ]; then
        log_error "PyTorch build script not found at $PYTORCH_DIR"
        log_info "Clone pytorch external build first"
        exit 1
    fi

    cd "$PYTORCH_DIR"

    log_info "Building PyTorch wheel targeting $GPU_ARCH_GENERIC..."
    python3 build_prod_wheels.py build \
        --output-dir "$PYTORCH_DIR/wheels_out_gfx12" \
        --no-build-pytorch-audio \
        --no-build-pytorch-vision \
        --no-build-triton \
        --pytorch-rocm-arch "$GPU_ARCH_GENERIC" \
        --clean

    local whl=$(ls "$PYTORCH_DIR/wheels_out_gfx12/torch-"*.whl 2>/dev/null | head -1)
    if [ -n "$whl" ]; then
        log_ok "Wheel built: $(basename "$whl")"
        log_info "Install with: pip install --no-deps --force-reinstall $whl"
    else
        log_error "No wheel produced"
    fi

    cd "$SCRIPT_DIR"
}

#═══════════════════════════════════════════════════════════════════════════════
# LLAMA: Build llama.cpp for gfx1201
#═══════════════════════════════════════════════════════════════════════════════
do_llama() {
    log_step "LLAMA.CPP BUILD"

    local llama_dir="$SCRIPT_DIR/external-builds/llama.cpp"

    if [ ! -d "$llama_dir" ]; then
        log_info "Cloning llama.cpp..."
        mkdir -p "$SCRIPT_DIR/external-builds"
        git clone https://github.com/ggerganov/llama.cpp.git "$llama_dir"
    fi

    cd "$llama_dir"
    log_info "Building llama.cpp for $GPU_ARCH..."

    cmake -B build -GNinja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="-O3" \
        -DCMAKE_CXX_FLAGS="-O3" \
        -DGGML_HIP=ON \
        -DAMDGPU_TARGETS="$GPU_ARCH" \
        -DCMAKE_PREFIX_PATH="$ROCM_INSTALL"

    ninja -C build -j$(nproc)

    if [ -f build/bin/llama-server ]; then
        log_ok "llama-server built"
        log_info "Install: sudo cp build/bin/llama-server /usr/local/bin/"
    fi

    cd "$SCRIPT_DIR"
}

#═══════════════════════════════════════════════════════════════════════════════
# TEST: Verification suite
#═══════════════════════════════════════════════════════════════════════════════
do_test() {
    log_step "VERIFICATION"

    source rocm_env.sh 2>/dev/null || true

    # GPU Detection
    echo -e "\n${BOLD}GPU Detection${NC}"
    echo "─────────────────────────────────────────"
    rocminfo 2>&1 | grep -E "Name:|Marketing Name:|Device Type:" | head -6

    # HIP Compile + Run
    echo -e "\n${BOLD}HIP Native Compile (gfx1201)${NC}"
    echo "─────────────────────────────────────────"
    cat > /tmp/_test_gfx12.hip << 'HIPEOF'
#include <hip/hip_runtime.h>
#include <stdio.h>
__global__ void hello() { printf("  GPU thread %d says hello\n", threadIdx.x); }
int main() {
    hipDeviceProp_t p;
    hipGetDeviceProperties(&p, 0);
    printf("  Device: %s (%s)\n", p.name, p.gcnArchName);
    hello<<<1, 4>>>();
    hipDeviceSynchronize();
    printf("  HIP compute: PASS\n");
    return 0;
}
HIPEOF
    hipcc --offload-arch=$GPU_ARCH /tmp/_test_gfx12.hip -o /tmp/_test_gfx12 && /tmp/_test_gfx12
    rm -f /tmp/_test_gfx12 /tmp/_test_gfx12.hip

    # Library Check
    echo -e "\n${BOLD}Library Status${NC}"
    echo "─────────────────────────────────────────"
    for lib in amdhip64 hiprtc rocblas hipblaslt rocrand rocsolver rocsparse rocfft hipfft MIOpen rccl; do
        if [ -f "$ROCM_INSTALL/lib/lib${lib}.so" ]; then
            echo -e "  ${GREEN}✓${NC} $lib"
        else
            echo -e "  ${RED}✗${NC} $lib"
        fi
    done

    # PyTorch
    echo -e "\n${BOLD}PyTorch${NC}"
    echo "─────────────────────────────────────────"
    python3 -c "
import torch
print(f'  torch {torch.__version__}')
print(f'  CUDA available: {torch.cuda.is_available()}')
if torch.cuda.is_available():
    print(f'  Device: {torch.cuda.get_device_name(0)}')
    a = torch.randn(1024, 1024, device='cuda', dtype=torch.float16)
    b = torch.randn(1024, 1024, device='cuda', dtype=torch.float16)
    c = torch.mm(a, b)
    torch.cuda.synchronize()
    print(f'  FP16 matmul 1024: PASS')
" 2>&1 || log_warn "PyTorch not installed or GPU unavailable"

    # FFT Test
    echo -e "\n${BOLD}FFT (rocFFT)${NC}"
    echo "─────────────────────────────────────────"
    python3 -c "
import torch
if torch.cuda.is_available():
    x = torch.randn(4096, device='cuda')
    y = torch.fft.fft(x)
    torch.cuda.synchronize()
    print(f'  torch.fft.fft(4096): PASS (output shape {y.shape})')
else:
    print('  GPU not available')
" 2>&1 || log_warn "FFT test failed — rocFFT may not be built"

    # Quick Benchmark
    echo -e "\n${BOLD}Quick Benchmark${NC}"
    echo "─────────────────────────────────────────"
    python3 -c "
import torch, time
for dt, name in [(torch.float16,'FP16'),(torch.bfloat16,'BF16'),(torch.float32,'FP32')]:
    a = torch.randn(4096, 4096, device='cuda', dtype=dt)
    b = torch.randn(4096, 4096, device='cuda', dtype=dt)
    torch.mm(a, b); torch.cuda.synchronize()
    s = time.perf_counter()
    for _ in range(20): torch.mm(a, b)
    torch.cuda.synchronize()
    e = (time.perf_counter() - s) / 20
    t = 2 * 4096**3 / e / 1e12
    print(f'  {name} 4096x4096: {t:.1f} TFLOPS  ({e*1000:.2f} ms)')
" 2>&1 || log_warn "Benchmark failed"

    echo ""
    log_ok "Verification complete"
}

#═══════════════════════════════════════════════════════════════════════════════
# STATUS: Show component status
#═══════════════════════════════════════════════════════════════════════════════
do_status() {
    log_step "COMPONENT STATUS"

    echo -e "${BOLD}ROCm Libraries${NC}"
    echo "─────────────────────────────────────────"
    for lib in amdhip64 hiprtc rocblas hipblaslt rocrand rocsolver rocsparse rocfft hipfft MIOpen rccl; do
        if [ -f "$ROCM_DIST/lib/lib${lib}.so" ]; then
            local ver=$(readelf -d "$ROCM_DIST/lib/lib${lib}.so" 2>/dev/null | grep SONAME | grep -oP '\.so\.\K[0-9.]+' || echo "")
            echo -e "  ${GREEN}✓${NC} ${lib}${ver:+ ($ver)}"
        else
            echo -e "  ${RED}✗${NC} ${lib} (not built)"
        fi
    done

    echo -e "\n${BOLD}Build Configuration${NC}"
    echo "─────────────────────────────────────────"
    if [ -f build/CMakeCache.txt ]; then
        echo "  GPU target:   $(grep 'THEROCK_AMDGPU_FAMILIES:' build/CMakeCache.txt | cut -d= -f2)"
        echo "  Build type:   $(grep 'CMAKE_BUILD_TYPE:' build/CMakeCache.txt | cut -d= -f2)"
        echo "  FFT:          $(grep 'THEROCK_ENABLE_FFT:' build/CMakeCache.txt | cut -d= -f2)"
        echo "  rocprofsys:   $(grep 'THEROCK_ENABLE_ROCPROFSYS:' build/CMakeCache.txt | cut -d= -f2)"
    else
        echo "  (not configured)"
    fi

    echo -e "\n${BOLD}Environment${NC}"
    echo "─────────────────────────────────────────"
    echo "  /opt/rocm:    $(readlink -f /opt/rocm 2>/dev/null || echo 'not set')"
    echo "  hipcc:        $(which hipcc 2>/dev/null || echo 'not found')"
    echo "  GCC:          $(gcc --version 2>/dev/null | head -1)"
    echo "  Python:       $(python3 --version 2>/dev/null)"
    echo "  PyTorch:      $(python3 -c 'import torch; print(torch.__version__)' 2>/dev/null || echo 'not installed')"

    echo -e "\n${BOLD}Blocked Upstream${NC}"
    echo "─────────────────────────────────────────"
    echo "  rocprofiler-systems   dyninst CMAKE_CXX_FLAGS quoting (therock_subproject.cmake:1428)"
    echo "  FBGEMM GenAI          CK Wave32 support missing (RDNA4), ETA H1 2026"
    echo ""
}

#═══════════════════════════════════════════════════════════════════════════════
# PUSH: Push to fork
#═══════════════════════════════════════════════════════════════════════════════
do_push() {
    log_step "PUSH"

    if [ -n "$(git status --porcelain)" ]; then
        log_warn "Uncommitted changes:"
        git status --short
        read -p "Commit? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            git add -A
            git commit -m "Update build script and ROCm status

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
        fi
    fi

    git push fork fedora-atomic-rocm7.12-ai-pro-experimental
    log_ok "Pushed to fork"
}

#═══════════════════════════════════════════════════════════════════════════════
# MAIN
#═══════════════════════════════════════════════════════════════════════════════
case "${1:-help}" in
    update)    do_update ;;
    fixes)     do_fixes ;;
    configure) do_configure ;;
    build)     do_build "${2:-}" "${3:-4}" ;;
    install)   do_install ;;
    pip-libs)  do_pip_libs ;;
    pytorch)   do_pytorch ;;
    llama)     do_llama ;;
    test)      do_test ;;
    status)    do_status ;;
    push)      do_push ;;
    all)
        do_update
        do_fixes
        do_configure
        do_build
        do_install
        do_pip_libs
        do_test
        ;;
    *)
        echo ""
        echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}  TheRock ROCm Build — gfx1201 (RDNA 4)${NC}"
        echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════${NC}"
        echo ""
        echo -e "  ${BOLD}Core Pipeline:${NC}"
        echo -e "    update      ${DIM}Pull latest upstream and rebase${NC}"
        echo -e "    fixes       ${DIM}Check/apply GCC 15 patches${NC}"
        echo -e "    configure   ${DIM}Configure CMake build${NC}"
        echo -e "    build       ${DIM}Build ROCm (-j4, ~3-4 hours)${NC}"
        echo -e "    install     ${DIM}Setup /opt/rocm and environment${NC}"
        echo ""
        echo -e "  ${BOLD}AI Stack:${NC}"
        echo -e "    pip-libs    ${DIM}Install gfx120X ROCm packages (Tensile)${NC}"
        echo -e "    pytorch     ${DIM}Build PyTorch 2.9.1 wheel${NC}"
        echo -e "    llama       ${DIM}Build llama.cpp for gfx1201${NC}"
        echo ""
        echo -e "  ${BOLD}Utilities:${NC}"
        echo -e "    test        ${DIM}Run verification suite${NC}"
        echo -e "    status      ${DIM}Show component status${NC}"
        echo -e "    push        ${DIM}Push to tlee933 fork${NC}"
        echo -e "    all         ${DIM}Run full pipeline${NC}"
        echo ""
        echo -e "  ${BOLD}Quick start:${NC}"
        echo -e "    $0 all"
        echo ""
        echo -e "  ${BOLD}Step by step:${NC}"
        echo -e "    $0 update && $0 fixes && $0 configure"
        echo -e "    $0 build --background"
        echo -e "    $0 install && $0 pip-libs && $0 test"
        echo ""
        ;;
esac
