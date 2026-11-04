#!/usr/bin/env bash
# ==============================================================================
# Model Downloader for Ternary Bonsai 2 27B & Gemma 4 12B
# Downloads GGUF model weights and vision projector directly to ./models/
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="${SCRIPT_DIR}/models"
mkdir -p "${MODELS_DIR}"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}====================================================================${NC}"
echo -e "${GREEN}    Ternary Bonsai 2 & Gemma 4 Model Downloader (Linux / Bash)     ${NC}"
echo -e "${CYAN}====================================================================${NC}"
echo -e "Models will be saved to: ${YELLOW}${MODELS_DIR}${NC}\n"

download_file() {
    local url="$1"
    local output="$2"
    local desc="$3"

    if [ -f "${output}" ]; then
        local size
        size=$(stat -c%s "${output}" 2>/dev/null || stat -f%z "${output}" 2>/dev/null || echo "0")
        if [ "${size}" -gt 1000000 ]; then
            echo -e "${GREEN}[OK] ${desc} already exists (${size} bytes). Skipping.${NC}"
            return 0
        fi
    fi

    echo -e "${CYAN}[+] Downloading ${desc}...${NC}"
    if command -v curl &>/dev/null; then
        curl -L -C - --progress-bar -o "${output}" "${url}"
    elif command -v wget &>/dev/null; then
        wget -c --progress=bar:force -O "${output}" "${url}"
    else
        echo -e "${RED}[ERROR] Neither curl nor wget found. Please install one.${NC}"
        exit 1
    fi
    echo -e "${GREEN}[SUCCESS] Downloaded ${desc}${NC}\n"
}

echo -e "Select models to download:"
echo -e "  [1] Bonsai 2 27B PTQ1_0  (5.95 GB - Lowest VRAM, Recommended for RTX 4070 Ti 12GB)"
echo -e "  [2] Bonsai 2 27B PQ2_0   (7.21 GB - Fastest Prompt/Decode, Fits 12GB VRAM at 48K ctx)"
echo -e "  [3] Bonsai 2 Vision Proj (0.63 GB - Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf for Multimodal)"
echo -e "  [4] Gemma 4 12B Q4_K_M   (7.66 GB - Google Gemma 4 IT)"
echo -e "  [5] DSpark Drafter Q4_1  (1.95 GB - Ternary-Bonsai-27B-dspark-Q4_1.gguf for 2x-3x Speculative Speed)"
echo -e "  [A] Download ALL recommended Bonsai 2 files (PTQ1_0 + PQ2_0 + Vision Projector + DSpark Drafter)"
echo -e "  [Q] Quit"
echo ""
read -rp "Select option [1/2/3/4/5/A/Q]: " choice

choice=$(echo "${choice}" | tr '[:lower:]' '[:upper:]')

case "${choice}" in
    1)
        download_file \
            "https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-GGUF/resolve/main/Ternary-Bonsai-2-27B-PTQ1_0.gguf" \
            "${MODELS_DIR}/Ternary-Bonsai-2-27B-PTQ1_0.gguf" \
            "Ternary-Bonsai-2-27B-PTQ1_0.gguf"
        ;;
    2)
        download_file \
            "https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-GGUF/resolve/main/Ternary-Bonsai-2-27B-PQ2_0.gguf" \
            "${MODELS_DIR}/Ternary-Bonsai-2-27B-PQ2_0.gguf" \
            "Ternary-Bonsai-2-27B-PQ2_0.gguf"
        ;;
    3)
        download_file \
            "https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-GGUF/resolve/main/Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf" \
            "${MODELS_DIR}/Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf" \
            "Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf"
        ;;
    4)
        download_file \
            "https://huggingface.co/bartowski/gemma-4-12B-it-GGUF/resolve/main/gemma-4-12B-it-Q4_K_M.gguf" \
            "${MODELS_DIR}/gemma-4-12B-it-Q4_K_M.gguf" \
            "gemma-4-12B-it-Q4_K_M.gguf"
        ;;
    5)
        download_file \
            "https://huggingface.co/prism-ml/Ternary-Bonsai-27B-gguf/resolve/main/Ternary-Bonsai-27B-dspark-Q4_1.gguf" \
            "${MODELS_DIR}/Ternary-Bonsai-27B-dspark-Q4_1.gguf" \
            "Ternary-Bonsai-27B-dspark-Q4_1.gguf"
        ;;
    A)
        download_file \
            "https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-GGUF/resolve/main/Ternary-Bonsai-2-27B-PTQ1_0.gguf" \
            "${MODELS_DIR}/Ternary-Bonsai-2-27B-PTQ1_0.gguf" \
            "Ternary-Bonsai-2-27B-PTQ1_0.gguf"
        download_file \
            "https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-GGUF/resolve/main/Ternary-Bonsai-2-27B-PQ2_0.gguf" \
            "${MODELS_DIR}/Ternary-Bonsai-2-27B-PQ2_0.gguf" \
            "Ternary-Bonsai-2-27B-PQ2_0.gguf"
        download_file \
            "https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-GGUF/resolve/main/Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf" \
            "${MODELS_DIR}/Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf" \
            "Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf"
        download_file \
            "https://huggingface.co/prism-ml/Ternary-Bonsai-27B-gguf/resolve/main/Ternary-Bonsai-27B-dspark-Q4_1.gguf" \
            "${MODELS_DIR}/Ternary-Bonsai-27B-dspark-Q4_1.gguf" \
            "Ternary-Bonsai-27B-dspark-Q4_1.gguf"
        ;;
            "Ternary-Bonsai-2-27B-PTQ1_0.gguf"
        download_file \
            "https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-GGUF/resolve/main/Ternary-Bonsai-2-27B-PQ2_0.gguf" \
            "${MODELS_DIR}/Ternary-Bonsai-2-27B-PQ2_0.gguf" \
            "Ternary-Bonsai-2-27B-PQ2_0.gguf"
        download_file \
            "https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-GGUF/resolve/main/Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf" \
            "${MODELS_DIR}/Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf" \
            "Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf"
        ;;
    *)
        echo -e "${YELLOW}Exiting.${NC}"
        exit 0
        ;;
esac

echo -e "${GREEN}[DONE] Models ready in ${MODELS_DIR}${NC}"
