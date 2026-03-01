#!/bin/bash
set -e

# PyTorch 2.9.1 Build Script for ROCm 7.12 + gfx1201
# Part of TheRock custom ROCm build ecosystem
# Builds PyTorch with Flash Attention and FBGEMM optimizations

echo "=========================================="
echo "PyTorch 2.9.1 Build for ROCm 7.12 + gfx1201"
echo "=========================================="
echo ""

# Configuration
PYTORCH_SRC="${PYTORCH_SRC:-/var/mnt/build/TheRock/external-builds/pytorch/pytorch}"
ROCM_PATH="${ROCM_PATH:-/opt/rocm}"
BUILD_DIR="${PYTORCH_SRC}/build"
PATCHES_DIR="$(dirname "$0")/patches"
WHEEL_OUTPUT="${WHEEL_OUTPUT:-/var/mnt/build/TheRock/external-builds/pytorch/wheels}"

# Validation
if [[ ! -d "$PYTORCH_SRC" ]]; then
    echo "ERROR: PyTorch source not found at $PYTORCH_SRC"
    exit 1
fi

if [[ ! -d "$ROCM_PATH" ]]; then
    echo "ERROR: ROCm not found at $ROCM_PATH"
    exit 1
fi

echo "Configuration:"
echo "  PyTorch source: $PYTORCH_SRC"
echo "  ROCm path: $ROCM_PATH"
echo "  Patches: $PATCHES_DIR"
echo "  Output: $WHEEL_OUTPUT"
echo ""

# Apply patches
echo "Applying patches..."
if [[ -f "$PATCHES_DIR/rocprim-half-fix.patch" ]]; then
    echo "  → rocprim __half fix"
    # Backup original if not already backed up
    if [[ ! -f "$ROCM_PATH/include/rocprim/device/detail/device_radix_sort.hpp.backup" ]]; then
        sudo cp "$ROCM_PATH/include/rocprim/device/detail/device_radix_sort.hpp" \
                "$ROCM_PATH/include/rocprim/device/detail/device_radix_sort.hpp.backup"
    fi
    sudo patch -d "$ROCM_PATH" -p1 < "$PATCHES_DIR/rocprim-half-fix.patch" 2>/dev/null || true
fi

if [[ -f "$PATCHES_DIR/flatbuffers-v25-compat.patch" ]]; then
    echo "  → flatbuffers v25 compatibility"
    patch -d "$PYTORCH_SRC" -p1 < "$PATCHES_DIR/flatbuffers-v25-compat.patch" 2>/dev/null || true
fi

# Setup libdrm headers from TheRock build
echo "Setting up libdrm headers..."
THEROCK_BUILD="/mnt/build/TheRock/build/core/ROCR-Runtime/dist/lib/rocm_sysdeps/include"
if [[ -d "$THEROCK_BUILD/libdrm" ]]; then
    if [[ ! -L "$ROCM_PATH/include/libdrm" ]]; then
        echo "  → Symlinking TheRock libdrm headers"
        sudo ln -sf "$THEROCK_BUILD/libdrm" "$ROCM_PATH/include/libdrm"
    fi
else
    echo "  WARNING: TheRock libdrm headers not found at $THEROCK_BUILD/libdrm"
fi

echo ""
echo "Cleaning previous build..."
cd "$PYTORCH_SRC"
rm -rf "$BUILD_DIR"

# Build environment
echo "Configuring build environment..."
export ROCM_PATH
export HIP_DEVICE_LIB_PATH="$ROCM_PATH/lib/llvm/amdgcn/bitcode"
export DEVICE_LIB_PATH="$ROCM_PATH/lib/llvm/amdgcn/bitcode"
export USE_ROCM=1
export PYTORCH_ROCM_ARCH=gfx1201
export USE_FLASH_ATTENTION=1
export USE_FBGEMM_GENAI=ON
export PYTORCH_BUILD_VERSION=2.9.1
export PYTORCH_BUILD_NUMBER=1
export CMAKE_PREFIX_PATH="$ROCM_PATH"

echo "  ROCM_PATH: $ROCM_PATH"
echo "  PYTORCH_ROCM_ARCH: $PYTORCH_ROCM_ARCH"
echo "  USE_FLASH_ATTENTION: $USE_FLASH_ATTENTION"
echo "  USE_FBGEMM_GENAI: $USE_FBGEMM_GENAI"
echo "  HIP_DEVICE_LIB_PATH: $HIP_DEVICE_LIB_PATH"
echo ""

# Build
echo "Starting build (this will take ~2 hours)..."
echo "Build log: $PYTORCH_SRC/build.log"
echo ""
START_TIME=$(date +%s)

python3 setup.py bdist_wheel 2>&1 | tee build.log

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
HOURS=$((DURATION / 3600))
MINUTES=$(((DURATION % 3600) / 60))

echo ""
echo "=========================================="
echo "Build completed in ${HOURS}h ${MINUTES}m"
echo "=========================================="

# Find and copy wheel
WHEEL=$(find dist -name "*.whl" -type f | head -1)
if [[ -n "$WHEEL" ]]; then
    echo ""
    echo "Wheel created: $WHEEL"
    WHEEL_SIZE=$(du -h "$WHEEL" | cut -f1)
    echo "Size: $WHEEL_SIZE"

    # Copy to output directory
    mkdir -p "$WHEEL_OUTPUT"
    cp "$WHEEL" "$WHEEL_OUTPUT/"
    echo "Copied to: $WHEEL_OUTPUT/$(basename "$WHEEL")"

    echo ""
    echo "To install:"
    echo "  python3 -m pip install --force-reinstall '$WHEEL_OUTPUT/$(basename "$WHEEL")'"
else
    echo ""
    echo "ERROR: Wheel not found in dist/"
    exit 1
fi

echo ""
echo "Build artifacts:"
echo "  Wheel: $WHEEL_OUTPUT/$(basename "$WHEEL")"
echo "  Build log: $PYTORCH_SRC/build.log"
echo "  Patches applied:"
echo "    - rocprim __half fix"
echo "    - flatbuffers v25 compatibility"
echo ""
echo "Done!"
