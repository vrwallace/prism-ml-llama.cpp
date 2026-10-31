#!/usr/bin/env bash
# ==============================================================================
# All-in-One Linux Installer for PrismML Ternary Bonsai 2 27B & Gemma 4
# Sets up CUDA build environment, compiles llama.cpp, configures systemd,
# and prepares the service manager on Linux (Ubuntu / Debian / Fedora / Arch).
# ==============================================================================

set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo -e "${CYAN}====================================================================${NC}"
echo -e "${GREEN}${BOLD}   PrismML Ternary Bonsai 2 (27B) - Linux Automated Installer      ${NC}"
echo -e "${CYAN}====================================================================${NC}"
echo -e "Working Directory: ${YELLOW}${SCRIPT_DIR}${NC}\n"

# ------------------------------------------------------------------------------
# 1. Check for NVIDIA Driver & GPU
# ------------------------------------------------------------------------------
echo -e "${CYAN}[1/6] Checking GPU and NVIDIA Drivers...${NC}"
if ! command -v nvidia-smi &>/dev/null; then
    echo -e "${RED}[ERROR] 'nvidia-smi' not found!${NC}"
    echo -e "${YELLOW}Please install the NVIDIA proprietary graphics drivers for your system first.${NC}"
    echo -e "On Ubuntu/Debian:  sudo apt update && sudo apt install -y nvidia-driver-550"
    exit 1
fi

GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1 || echo "NVIDIA GPU")
GPU_VRAM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader | head -n1 || echo "Unknown VRAM")
echo -e "${GREEN}[OK] Detected GPU: ${BOLD}${GPU_NAME}${NC} (${GPU_VRAM})\n"

# ------------------------------------------------------------------------------
# 2. Check for CUDA Toolkit (nvcc)
# ------------------------------------------------------------------------------
echo -e "${CYAN}[2/6] Checking CUDA Compiler (nvcc)...${NC}"

# Check standard CUDA paths if not in PATH
if ! command -v nvcc &>/dev/null; then
    for cuda_path in /usr/local/cuda/bin /usr/local/cuda-*/bin; do
        if [ -x "${cuda_path}/nvcc" ]; then
            export PATH="${cuda_path}:${PATH}"
            export LD_LIBRARY_PATH="$(dirname "${cuda_path}")/lib64:${LD_LIBRARY_PATH:-}"
            break
        fi
    done
fi

if ! command -v nvcc &>/dev/null; then
    echo -e "${YELLOW}[!] 'nvcc' (CUDA Compiler) not found in PATH.${NC}"
    echo -e "Attempting to install CUDA development packages..."

    if command -v apt-get &>/dev/null; then
        sudo apt-get update && sudo apt-get install -y nvidia-cuda-toolkit
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y cuda-toolkit
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm cuda
    else
        echo -e "${RED}[ERROR] Could not auto-install CUDA. Please install CUDA Toolkit (>= 12.4 recommended).${NC}"
        exit 1
    fi
fi

if command -v nvcc &>/dev/null; then
    NVCC_VER=$(nvcc --version | grep "release" | sed -n -e 's/^.*release \([0-9\.]*\).*/\1/p')
    echo -e "${GREEN}[OK] CUDA Compiler found: nvcc version ${BOLD}${NVCC_VER}${NC}\n"
else
    echo -e "${RED}[ERROR] 'nvcc' is still unavailable. Please check CUDA installation.${NC}"
    exit 1
fi

# ------------------------------------------------------------------------------
# 3. Install Required Build Tools & Dependencies
# ------------------------------------------------------------------------------
echo -e "${CYAN}[3/6] Installing build dependencies (cmake, git, ccache, libcurl)...${NC}"
if command -v apt-get &>/dev/null; then
    sudo apt-get update
    sudo apt-get install -y build-essential cmake git curl wget ccache pkg-config libcurl4-openssl-dev
elif command -v dnf &>/dev/null; then
    sudo dnf install -y gcc-c++ cmake git curl wget ccache pkgconfig libcurl-devel
elif command -v pacman &>/dev/null; then
    sudo pacman -S --needed --noconfirm base-devel cmake git curl wget ccache curl
fi
echo -e "${GREEN}[OK] Build dependencies installed.${NC}\n"

# ------------------------------------------------------------------------------
# 4. Compile llama.cpp with CUDA Support
# ------------------------------------------------------------------------------
echo -e "${CYAN}[4/6] Configuring and compiling llama.cpp with CUDA & Flash Attention...${NC}"

# Detect CUDA architecture for optimal code generation (89 for RTX 4070 Ti / Ada)
CUDA_ARCH="native"
if echo "${GPU_NAME}" | grep -qiE "40[0-9]{2}|Ada"; then
    CUDA_ARCH="89;native"
fi

cmake -B build \
    -DGGML_CUDA=ON \
    -DGGML_CUDA_FA=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CUDA_ARCHITECTURES="${CUDA_ARCH}"

cmake --build build --config Release -j"$(nproc)"

if [ ! -f "build/bin/llama-server" ]; then
    echo -e "${RED}[ERROR] Compilation failed! 'build/bin/llama-server' was not found.${NC}"
    exit 1
fi

SERVER_VER=$(build/bin/llama-server --version 2>&1 | head -n1 || echo "llama-server ready")
echo -e "${GREEN}[SUCCESS] Compiled successfully: ${BOLD}${SERVER_VER}${NC}\n"

# ------------------------------------------------------------------------------
# 5. Set Up Directories and Permissions
# ------------------------------------------------------------------------------
echo -e "${CYAN}[5/6] Setting up directories and permissions...${NC}"
mkdir -p models logs
chmod +x download_models.sh servicemanager.sh || true

echo -e "${GREEN}[OK] Directory structure initialized.${NC}\n"

# ------------------------------------------------------------------------------
# 6. Install systemd Services (bonsai2.service & gemma4.service)
# ------------------------------------------------------------------------------
echo -e "${CYAN}[6/6] Configuring Linux systemd services...${NC}"

CURRENT_USER=$(id -un)
INSTALL_DIR="${SCRIPT_DIR}"

cat <<EOF | sudo tee /etc/systemd/system/bonsai2.service >/dev/null
[Unit]
Description=PrismML Ternary Bonsai 2 27B llama.cpp Service (CUDA)
After=network.target

[Service]
Type=simple
User=${CURRENT_USER}
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/build/bin/llama-server -m ${INSTALL_DIR}/models/Ternary-Bonsai-2-27B-PTQ1_0.gguf --host 0.0.0.0 --port 8080 -c 70000 -np 1 --cache-ram 8192 -ngl 99 -fa on -t 16 -b 2048 -ub 1024 --reasoning off --reasoning-budget 0 --temp 0.7 --top-p 0.80 --top-k 20 --min-p 0.0 --presence-penalty 1.5
Restart=on-failure
RestartSec=10s
LimitNOFILE=65535
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF | sudo tee /etc/systemd/system/gemma4.service >/dev/null
[Unit]
Description=Google Gemma 4 12B llama.cpp Service (CUDA)
After=network.target

[Service]
Type=simple
User=${CURRENT_USER}
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/build/bin/llama-server -m ${INSTALL_DIR}/models/gemma-4-12B-it-Q4_K_M.gguf --host 0.0.0.0 --port 8081 -c 16384 -ngl 99 -fa 1 -t 16 -b 2048 -ub 512 -sps 0.5 --reasoning-budget 0 --spec-type ngram-simple
Restart=on-failure
RestartSec=10s
LimitNOFILE=65535
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
echo -e "${GREEN}[OK] Registered /etc/systemd/system/bonsai2.service and gemma4.service${NC}\n"

# ------------------------------------------------------------------------------
# Complete!
# ------------------------------------------------------------------------------
echo -e "${GREEN}====================================================================${NC}"
echo -e "${GREEN}${BOLD}               INSTALLATION COMPLETE!                               ${NC}"
echo -e "${GREEN}====================================================================${NC}"
echo -e "Next steps:"
echo -e "  1. Download models:        ${CYAN}./download_models.sh${NC}"
echo -e "  2. Launch Service Manager: ${CYAN}./servicemanager.sh${NC}"
echo -e "     or use systemd directly:"
echo -e "       Start Bonsai 2:       ${YELLOW}sudo systemctl start bonsai2${NC}"
echo -e "       View live logs:       ${YELLOW}journalctl -u bonsai2 -f${NC}"
echo -e "       Stop Bonsai 2:        ${YELLOW}sudo systemctl stop bonsai2${NC}"
echo -e "====================================================================\n"
