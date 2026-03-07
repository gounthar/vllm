#!/bin/bash

# Build PyTorch 2.10.0 from source on RISC-V 64-bit
# Target: BananaPi F3 (SpacemiT K1, rv64gc, RVV vlen 256, 16 GB RAM)
# Run inside tmux — build takes 2-6 hours
# Usage: ./scripts/build-pytorch-riscv64.sh

set -euo pipefail

PYTORCH_VERSION="2.10.0"
BUILD_DIR="${HOME}/pytorch-build"
LOGFILE="build-pytorch-$(date +%Y%m%d-%H%M%S).log"

echo "=== PyTorch ${PYTORCH_VERSION} RISC-V Build ===" | tee "$LOGFILE"
echo "Date: $(date)" | tee -a "$LOGFILE"
uname -a | tee -a "$LOGFILE"

# Step 0: Check we're on riscv64
ARCH=$(uname -m)
if [ "$ARCH" != "riscv64" ]; then
    echo "ERROR: This script is for riscv64, detected: $ARCH" | tee -a "$LOGFILE"
    exit 1
fi

# Step 1: Install system build dependencies
echo "" | tee -a "$LOGFILE"
echo "--- Installing system dependencies ---" | tee -a "$LOGFILE"
sudo apt-get update 2>&1 | tee -a "$LOGFILE"
sudo apt-get install -y \
    libopenblas-dev liblapack-dev \
    libprotobuf-dev protobuf-compiler \
    python3-dev libnuma-dev \
    git cmake g++ ninja-build \
    2>&1 | tee -a "$LOGFILE"

# Step 2: Clone PyTorch (shallow, with submodules)
echo "" | tee -a "$LOGFILE"
echo "--- Cloning PyTorch v${PYTORCH_VERSION} ---" | tee -a "$LOGFILE"
if [ -d "$BUILD_DIR" ]; then
    echo "  Build dir exists, reusing: $BUILD_DIR" | tee -a "$LOGFILE"
    cd "$BUILD_DIR"
    git fetch --depth 1 origin "v${PYTORCH_VERSION}" 2>&1 | tee -a "$LOGFILE" || true
else
    git clone --depth 1 --branch "v${PYTORCH_VERSION}" \
        https://github.com/pytorch/pytorch.git "$BUILD_DIR" \
        2>&1 | tee -a "$LOGFILE"
    cd "$BUILD_DIR"
fi

echo "  Updating submodules..." | tee -a "$LOGFILE"
git submodule sync 2>&1 | tee -a "$LOGFILE"
git submodule update --init --recursive --depth 1 2>&1 | tee -a "$LOGFILE"

# Step 3: Install Python build dependencies
echo "" | tee -a "$LOGFILE"
echo "--- Installing Python build deps ---" | tee -a "$LOGFILE"
pip3 install --no-cache-dir \
    -r requirements.txt \
    wheel setuptools-scm numpy \
    2>&1 | tee -a "$LOGFILE"

# Step 4: Configure CPU-only build (disable all accelerators and optional deps)
echo "" | tee -a "$LOGFILE"
echo "--- Configuring build ---" | tee -a "$LOGFILE"

export USE_CUDA=0
export USE_ROCM=0
export USE_DISTRIBUTED=0
export USE_MKLDNN=0
export USE_FBGEMM=0
export USE_NNPACK=0
export USE_QNNPACK=0
export USE_XNNPACK=0
export USE_KINETO=0
export BUILD_TEST=0
export MAX_JOBS=$(( $(nproc) - 2 ))  # Leave 2 cores for system stability
[ "$MAX_JOBS" -lt 1 ] && MAX_JOBS=1

export PYTORCH_BUILD_VERSION="${PYTORCH_VERSION}"
export PYTORCH_BUILD_NUMBER=1

# Point to system protoc if available
if command -v protoc &>/dev/null; then
    export PROTOC=$(command -v protoc)
    echo "  PROTOC=$PROTOC" | tee -a "$LOGFILE"
fi

echo "  MAX_JOBS=$MAX_JOBS" | tee -a "$LOGFILE"
echo "  USE_CUDA=$USE_CUDA USE_DISTRIBUTED=$USE_DISTRIBUTED" | tee -a "$LOGFILE"

# Step 5: Build wheel
echo "" | tee -a "$LOGFILE"
echo "--- Building PyTorch wheel (this will take hours) ---" | tee -a "$LOGFILE"
echo "Build start: $(date)" | tee -a "$LOGFILE"

python3 setup.py bdist_wheel 2>&1 | tee -a "$LOGFILE"
BUILD_STATUS=$?

echo "Build end: $(date)" | tee -a "$LOGFILE"

if [ $BUILD_STATUS -eq 0 ]; then
    echo "" | tee -a "$LOGFILE"
    echo "=== BUILD SUCCESS ===" | tee -a "$LOGFILE"
    WHEEL=$(ls dist/torch-*.whl 2>/dev/null | head -1)
    if [ -n "$WHEEL" ]; then
        echo "Wheel: $WHEEL" | tee -a "$LOGFILE"
        echo "Size: $(du -h "$WHEEL" | cut -f1)" | tee -a "$LOGFILE"
        echo "" | tee -a "$LOGFILE"
        echo "To install:" | tee -a "$LOGFILE"
        echo "  pip3 install $WHEEL" | tee -a "$LOGFILE"
    fi
else
    echo "" | tee -a "$LOGFILE"
    echo "=== BUILD FAILED (exit code: $BUILD_STATUS) ===" | tee -a "$LOGFILE"
    echo "Check $LOGFILE for details" | tee -a "$LOGFILE"
    exit 1
fi
