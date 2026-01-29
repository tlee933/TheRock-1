#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
#  TheRock ROCm Build Script for gfx1201 (AMD Radeon AI PRO R9700)
#  Platform: Fedora 43+ Atomic/Silverblue/Aurora with GCC 15
#═══════════════════════════════════════════════════════════════════════════════
#
#  Usage:
#    ./BUILD_ROCM_GFX1201.sh [command]
#
#  Commands:
#    update    - Pull latest upstream and rebase
#    fixes     - Check/apply GCC 15 compatibility fixes
#    configure - Configure optimized build
#    build     - Build ROCm (3-4 hours with -j4)
#    install   - Setup /opt/rocm symlink and environment
#    test      - Run test suite and benchmarks
#    push      - Push to tlee933 fork
#    all       - Run full pipeline
#
#═══════════════════════════════════════════════════════════════════════════════
#
#  KNOWN ISSUES (to fix later):
#  - rocprofiler-systems fails to build: dyninst component gets CMAKE_CXX_FLAGS
#    passed with quotes, causing: cc1plus: error: argument to '-O' should be...
#    Workaround: Disable with -DTHEROCK_ENABLE_ROCPROFSYS=OFF
#    Impact: Profiling tools only, not required for HIP/ROCm runtime
#
#  - rocFFT and rccl fail with GCC 15: GCC 15's <cstdint> header expects types
#    like int_fast8_t in global namespace, but HIP device code doesn't provide them.
#    Error: "no member named 'int_fast8_t' in the global namespace"
#    Workaround: Disable with -DTHEROCK_ENABLE_CORE_MATH_LIBS=OFF or build individual libs
#    Impact: FFT and collective communications libraries
#
#═══════════════════════════════════════════════════════════════════════════════

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

#───────────────────────────────────────────────────────────────────────────────
# UPDATE: Pull latest upstream and rebase branch
#───────────────────────────────────────────────────────────────────────────────
do_update() {
    log_info "Fetching upstream changes..."
    git fetch origin

    local behind=$(git rev-list HEAD..origin/main --count)
    if [ "$behind" -gt 0 ]; then
        log_info "Main is $behind commits ahead, rebasing..."
        git stash
        git checkout main
        git pull origin main
        git checkout fedora-atomic-rocm7.12-ai-pro-experimental
        git rebase main
        log_ok "Branch rebased on latest main"
    else
        log_ok "Already up to date"
    fi
}

#───────────────────────────────────────────────────────────────────────────────
# FIXES: Check and apply GCC 15 compatibility patches
#───────────────────────────────────────────────────────────────────────────────
do_fixes() {
    log_info "Checking GCC 15 compatibility fixes..."

    local fixes_needed=0

    # Fix 1: elfio elf_types.hpp - cstdint
    local file1="rocm-systems/projects/rocprofiler-sdk/external/elfio/elfio/elf_types.hpp"
    if ! grep -q "#include <cstdint>" "$file1" 2>/dev/null; then
        log_warn "Applying fix: $file1 (cstdint)"
        sed -i '/#define ELFIO_ELF_TYPES_HPP/a #include <cstdint>' "$file1"
        fixes_needed=1
    fi

    # Fix 2: yaml-cpp emitterutils.cpp - cstdint
    local file2="rocm-systems/projects/rocprofiler-sdk/external/yaml-cpp/src/emitterutils.cpp"
    if ! grep -q "#include <cstdint>" "$file2" 2>/dev/null; then
        log_warn "Applying fix: $file2 (cstdint)"
        sed -i '/#include <algorithm>/a #include <cstdint>' "$file2"
        fixes_needed=1
    fi

    # Fix 3: PAPI papi_hl.c - K&R function declaration
    local file3="rocm-systems/projects/rocprofiler-systems/external/papi/src/high-level/papi_hl.c"
    if grep -q "static int _internal_hl_read_user_events();" "$file3" 2>/dev/null; then
        log_warn "Applying fix: $file3 (K&R declaration)"
        sed -i 's/static int _internal_hl_read_user_events();/static int _internal_hl_read_user_events(const char *user_events);/' "$file3"
        fixes_needed=1
    fi

    # Fix 4: PAPI papi_vector.c - function pointer cast
    local file4="rocm-systems/projects/rocprofiler-systems/external/papi/src/papi_vector.c"
    if grep -q "v->get_system_info = ( int ( \* )(  ) ) vec_int_dummy;" "$file4" 2>/dev/null; then
        log_warn "Applying fix: $file4 (function pointer)"
        sed -i 's/v->get_system_info = ( int ( \* )(  ) ) vec_int_dummy;/v->get_system_info = ( int ( * )( papi_mdi_t * ) ) vec_int_dummy;/' "$file4"
        fixes_needed=1
    fi

    # Fix 5: DyninstElfUtils.cmake - unterminated string warning
    local file5="rocm-systems/projects/rocprofiler-systems/cmake/DyninstElfUtils.cmake"
    if ! grep -q "Wno-error=unterminated-string-initialization" "$file5" 2>/dev/null; then
        log_warn "Applying fix: $file5 (elfutils CFLAGS)"
        sed -i 's/CFLAGS=-fPIC\\ -O3/CFLAGS=-fPIC\\ -O3\\ -Wno-error=unterminated-string-initialization/' "$file5"
        fixes_needed=1
    fi

    # Fix 6: logger.hpp - algorithm header
    local file6="rocm-systems/projects/rocprofiler-systems/source/lib/logger/logger.hpp"
    if ! grep -q "#include <algorithm>" "$file6" 2>/dev/null; then
        log_warn "Applying fix: $file6 (algorithm)"
        sed -i '/#include <spdlog\/spdlog.h>/a #include <algorithm>' "$file6"
        fixes_needed=1
    fi

    # Fix 7: sha1.C - cstdint
    local file7="rocm-systems/projects/rocprofiler-systems/external/dyninst/common/src/sha1.C"
    if ! grep -q "#include <cstdint>" "$file7" 2>/dev/null; then
        log_warn "Applying fix: $file7 (cstdint)"
        sed -i '1i #include <cstdint>' "$file7"
        fixes_needed=1
    fi

    # Fix 8: arch-x86.h - cstdint
    local file8="rocm-systems/projects/rocprofiler-systems/external/dyninst/common/src/arch-x86.h"
    if ! grep -q "#include <cstdint>" "$file8" 2>/dev/null; then
        log_warn "Applying fix: $file8 (cstdint)"
        sed -i '/#include "dyn_register.h"/a #include <cstdint>' "$file8"
        fixes_needed=1
    fi

    # Fix 9: rocgdb PDF docs (bootc systems)
    local file9="debug-tools/rocgdb/CMakeLists.txt"
    if grep -q '${MAKE_EXECUTABLE} -s -C gdb install-pdf install-html' "$file9" 2>/dev/null; then
        log_warn "Applying fix: $file9 (skip PDF docs)"
        sed -i 's/${MAKE_EXECUTABLE} -s -C gdb install-pdf install-html/# Skipped: ${MAKE_EXECUTABLE} -s -C gdb install-pdf install-html/' "$file9"
        fixes_needed=1
    fi

    # Fix 10: libhipcxx atomic_codegen symlink
    local link10="math-libs/libhipcxx/test/atomic_codegen"
    if [ ! -L "$link10" ] || [ ! -e "$link10" ]; then
        log_warn "Applying fix: $link10 (symlink)"
        cd math-libs/libhipcxx/test
        ln -sf ../../._upstream/.upstream-tests/atomic_codegen atomic_codegen
        cd "$SCRIPT_DIR"
        fixes_needed=1
    fi

    # Fix 11: libhipcxx cuobjdump check (already in .upstream-tests/test/CMakeLists.txt)
    local file11="math-libs/libhipcxx/.upstream-tests/test/CMakeLists.txt"
    if ! grep -q "cuobjdump_check" "$file11" 2>/dev/null; then
        log_warn "Fix needed: $file11 (cuobjdump check) - apply manually"
        fixes_needed=1
    fi

    # Fix 12: __clang_hip_math.h - GCC 15 cstdint compatibility for HIP device code
    local file12="compiler/amd-llvm/clang/lib/Headers/__clang_hip_math.h"
    if ! grep -q "GCC 15 compatibility" "$file12" 2>/dev/null; then
        log_warn "Applying fix: $file12 (GCC 15 cstdint)"
        sed -i '/#include <stdint.h>/a \
// GCC 15 compatibility: ensure cstdint types are available\n\
#if defined(__cplusplus) \&\& __has_include(<cstdint>)\n\
#include <cstdint>\n\
using std::uint8_t;\n\
using std::uint16_t;\n\
using std::uint32_t;\n\
using std::uint64_t;\n\
using std::int8_t;\n\
using std::int16_t;\n\
using std::int32_t;\n\
using std::int64_t;\n\
#endif' "$file12"
        fixes_needed=1
    fi

    if [ "$fixes_needed" -eq 0 ]; then
        log_ok "All GCC 15 fixes already applied"
    else
        log_ok "Fixes applied"
    fi
}

#───────────────────────────────────────────────────────────────────────────────
# CONFIGURE: Setup optimized CMake build
#───────────────────────────────────────────────────────────────────────────────
do_configure() {
    log_info "Configuring optimized build for gfx1201..."

    cmake -B build -GNinja \
        -DTHEROCK_AMDGPU_FAMILIES=gfx1201 \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_COMPILER_LAUNCHER=ccache \
        -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
        -DCMAKE_C_FLAGS="-O3 -march=native" \
        -DCMAKE_CXX_FLAGS="-O3 -march=native" \
        -DTHEROCK_ENABLE_ROCPROFSYS=OFF  # Disabled: dyninst build issue with -O flags

    log_ok "Configuration complete"
}

#───────────────────────────────────────────────────────────────────────────────
# BUILD: Compile ROCm (use -j4 to avoid OOM)
#───────────────────────────────────────────────────────────────────────────────
do_build() {
    log_info "Starting build with -j4 (this takes 3-4 hours)..."
    log_info "Monitor with: tail -f build.log"

    if [ "$1" == "--background" ]; then
        nohup ninja -C build -j4 > build.log 2>&1 &
        echo $! > build.pid
        log_ok "Build started in background (PID: $(cat build.pid))"
    else
        ninja -C build -j4 2>&1 | tee build.log
        log_ok "Build complete"
    fi
}

#───────────────────────────────────────────────────────────────────────────────
# INSTALL: Setup /opt/rocm symlink and environment
#───────────────────────────────────────────────────────────────────────────────
do_install() {
    log_info "Setting up ROCm installation..."

    # Check if dist exists
    if [ ! -d "build/dist/rocm" ]; then
        log_error "build/dist/rocm not found - run build first"
        exit 1
    fi

    # Setup /opt/rocm symlink (requires sudo)
    if [ -L "/opt/rocm" ]; then
        log_info "/opt/rocm symlink exists"
    else
        log_warn "Creating /opt/rocm symlink (requires sudo)"
        sudo ln -sf "$SCRIPT_DIR/build/dist/rocm" /opt/rocm
    fi

    # Create environment setup script
    cat > rocm_env.sh << 'ENVEOF'
#!/bin/bash
# ROCm Environment Setup for gfx1201
export ROCM_PATH=/opt/rocm
export HIP_PATH=/opt/rocm
export PATH=$ROCM_PATH/bin:$PATH
export LD_LIBRARY_PATH=$ROCM_PATH/lib:$ROCM_PATH/lib64:$LD_LIBRARY_PATH
export HSA_OVERRIDE_GFX_VERSION=12.0.1
export GPU_MAX_HW_QUEUES=8

# For PyTorch
export PYTORCH_ROCM_ARCH=gfx1201
export HIP_VISIBLE_DEVICES=0
ENVEOF
    chmod +x rocm_env.sh

    # Update ldconfig
    if [ ! -f "/etc/ld.so.conf.d/rocm.conf" ]; then
        log_warn "Creating ldconfig entry (requires sudo)"
        echo "/opt/rocm/lib" | sudo tee /etc/ld.so.conf.d/rocm.conf
        echo "/opt/rocm/lib64" | sudo tee -a /etc/ld.so.conf.d/rocm.conf
        sudo ldconfig
    fi

    log_ok "Installation complete"
    log_info "Source environment with: source rocm_env.sh"
}

#───────────────────────────────────────────────────────────────────────────────
# TEST: Run test suite and benchmarks
#───────────────────────────────────────────────────────────────────────────────
do_test() {
    log_info "Running ROCm tests..."

    source rocm_env.sh 2>/dev/null || true

    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "                      GPU DETECTION                            "
    echo "═══════════════════════════════════════════════════════════════"
    /opt/rocm/bin/rocminfo 2>&1 | grep -E "Name:|Marketing Name:|Device Type:" | head -6

    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "                      HIP COMPUTE TEST                         "
    echo "═══════════════════════════════════════════════════════════════"
    cat > /tmp/hip_test.cpp << 'HIPEOF'
#include <hip/hip_runtime.h>
#include <stdio.h>
__global__ void hello() { printf("Hello from GPU thread %d!\n", threadIdx.x); }
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
HIPEOF
    /opt/rocm/bin/hipcc /tmp/hip_test.cpp -o /tmp/hip_test && /tmp/hip_test

    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "                      ROCRAND TESTS                            "
    echo "═══════════════════════════════════════════════════════════════"
    /opt/rocm/bin/test_rocrand_basic 2>&1 | tail -5

    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "                      BENCHMARKS                               "
    echo "═══════════════════════════════════════════════════════════════"
    echo "hipBLASLt FP16 2048³:"
    /opt/rocm/bin/hipblaslt-bench -f matmul -r f16_r -m 2048 -n 2048 -k 2048 --cold_iters 2 --iters 10 2>&1 | tail -2

    echo ""
    echo "hipBLASLt BF16 4096³:"
    /opt/rocm/bin/hipblaslt-bench -f matmul -r bf16_r -m 4096 -n 4096 -k 4096 --cold_iters 2 --iters 10 2>&1 | tail -2

    echo ""
    echo "rocrand throughput:"
    /opt/rocm/bin/benchmark_rocrand_generate --engine xorwow --size 1048576 --trials 10 2>&1 | tail -3

    log_ok "Tests complete"
}

#───────────────────────────────────────────────────────────────────────────────
# PUSH: Push changes to tlee933 fork
#───────────────────────────────────────────────────────────────────────────────
do_push() {
    log_info "Pushing to tlee933 fork..."

    # Check for uncommitted changes
    if [ -n "$(git status --porcelain)" ]; then
        log_warn "Uncommitted changes detected"
        git status --short
        read -p "Commit these changes? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            git add -A
            git commit -m "Update GCC 15 fixes and test results

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
        fi
    fi

    git push fork fedora-atomic-rocm7.12-ai-pro-experimental
    log_ok "Pushed to fork"
}

#───────────────────────────────────────────────────────────────────────────────
# MAIN
#───────────────────────────────────────────────────────────────────────────────
case "${1:-help}" in
    update)    do_update ;;
    fixes)     do_fixes ;;
    configure) do_configure ;;
    build)     do_build "${2:-}" ;;
    install)   do_install ;;
    test)      do_test ;;
    push)      do_push ;;
    all)
        do_update
        do_fixes
        do_configure
        do_build
        do_install
        do_test
        do_push
        ;;
    *)
        echo "═══════════════════════════════════════════════════════════════"
        echo "  TheRock ROCm Build Script for gfx1201"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  update     Pull latest upstream and rebase"
        echo "  fixes      Check/apply GCC 15 compatibility fixes"
        echo "  configure  Configure optimized build"
        echo "  build      Build ROCm (-j4, ~3-4 hours)"
        echo "  install    Setup /opt/rocm and environment"
        echo "  test       Run test suite and benchmarks"
        echo "  push       Push to tlee933 fork"
        echo "  all        Run full pipeline"
        echo ""
        echo "Quick start:"
        echo "  $0 all"
        echo ""
        echo "Or step by step:"
        echo "  $0 update && $0 fixes && $0 configure"
        echo "  $0 build --background"
        echo "  # wait 3-4 hours..."
        echo "  $0 install && $0 test && $0 push"
        echo ""
        ;;
esac
