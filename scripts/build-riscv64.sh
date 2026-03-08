#!/bin/bash

# Build vLLM on RISC-V 64-bit (Phase 1: pure Python, no C++ extensions)
# Target: BananaPi F3 (K1, rv64gc, RVV vlen 256)
# Strategy: CPU-only, skip C++ kernels, use pre-built riscv64 wheels

set -euo pipefail

LOGFILE="build-riscv64-$(date +%Y%m%d-%H%M%S).log"
RISCV_WHEEL_INDEX="https://gounthar.github.io/riscv64-python-wheels/simple/"

echo "=== vLLM RISC-V Build ===" | tee "$LOGFILE"
echo "Date: $(date)" | tee -a "$LOGFILE"
uname -a | tee -a "$LOGFILE"

# Step 0: Check prerequisites
echo "--- Checking prerequisites ---" | tee -a "$LOGFILE"
for tool in python3 pip3 gcc g++ cmake git; do
    if command -v "$tool" &>/dev/null; then
        echo "  $tool: $($tool --version 2>&1 | head -1)" | tee -a "$LOGFILE"
    else
        echo "  ERROR: $tool not found" | tee -a "$LOGFILE"
        exit 1
    fi
done

python3 -c "import torch; print(f'  PyTorch: {torch.__version__}')" 2>&1 | tee -a "$LOGFILE" || {
    echo "" | tee -a "$LOGFILE"
    echo "  ERROR: PyTorch not installed. Install it first:" | tee -a "$LOGFILE"
    echo "  Debian/Ubuntu: sudo apt install python3-torch" | tee -a "$LOGFILE"
    echo "  Or build from source for your platform." | tee -a "$LOGFILE"
    exit 1
}

# Step 1: Set environment for CPU-only build
echo "" | tee -a "$LOGFILE"
echo "--- Setting up CPU-only build ---" | tee -a "$LOGFILE"
export VLLM_TARGET_DEVICE=cpu
NPROC=$(nproc)
export MAX_JOBS=$(( NPROC / 2 ))
[ "$MAX_JOBS" -lt 1 ] && MAX_JOBS=1  # Clamp to 1 on single-core systems

echo "  VLLM_TARGET_DEVICE=$VLLM_TARGET_DEVICE" | tee -a "$LOGFILE"
echo "  MAX_JOBS=$MAX_JOBS" | tee -a "$LOGFILE"

# Step 2: Install build dependencies (setuptools required by setup.py)
echo "" | tee -a "$LOGFILE"
echo "--- Installing build dependencies ---" | tee -a "$LOGFILE"
pip3 install --no-cache-dir \
    "setuptools>=77.0.3" setuptools-scm packaging wheel ninja jinja2 \
    maturin \
    2>&1 | tee -a "$LOGFILE"

# Step 3: Install Python dependencies using pre-built riscv64 wheels
echo "" | tee -a "$LOGFILE"
echo "--- Installing Python dependencies ---" | tee -a "$LOGFILE"
echo "  Using riscv64 wheel index: $RISCV_WHEEL_INDEX" | tee -a "$LOGFILE"
pip3 install --no-cache-dir \
    --extra-index-url "$RISCV_WHEEL_INDEX" \
    numpy sentencepiece transformers tokenizers \
    fastapi aiohttp pydantic requests tqdm \
    prometheus_client pillow psutil cachetools \
    protobuf tiktoken filelock regex blake3 \
    safetensors pyyaml cffi cryptography watchfiles \
    2>&1 | tee -a "$LOGFILE"

# Step 4: Build vLLM (--no-build-isolation to use system torch)
echo "" | tee -a "$LOGFILE"
echo "--- Building vLLM ---" | tee -a "$LOGFILE"
echo "Build start: $(date)" | tee -a "$LOGFILE"

set +e
pip3 install -e . --no-build-isolation \
    --extra-index-url "$RISCV_WHEEL_INDEX" \
    2>&1 | tee -a "$LOGFILE"
BUILD_STATUS=${PIPESTATUS[0]}
set -e

echo "Build end: $(date)" | tee -a "$LOGFILE"

if [ $BUILD_STATUS -eq 0 ]; then
    echo "=== BUILD SUCCESS ===" | tee -a "$LOGFILE"
    python3 -c "import vllm; print(f'vLLM version: {vllm.__version__}')" 2>&1 | tee -a "$LOGFILE"
else
    echo "=== BUILD FAILED (exit code: $BUILD_STATUS) ===" | tee -a "$LOGFILE"
    echo "Check $LOGFILE for details" | tee -a "$LOGFILE"
    exit 1
fi
