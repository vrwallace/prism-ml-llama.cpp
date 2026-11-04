#!/usr/bin/env bash
# ==============================================================================
# Linux AI Service Manager (Bonsai 2 & Gemma 4 - CUDA 13.x / systemd)
# Interactive dashboard to control, tune, and monitor LLM services on Linux.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/winsw_manager_config.json"
MODELS_DIR="${SCRIPT_DIR}/models"
BIN_DIR="${SCRIPT_DIR}/build/bin"
LOGS_DIR="${SCRIPT_DIR}/logs"

mkdir -p "${MODELS_DIR}" "${LOGS_DIR}"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
MAGENTA='\033[0;35m'
GRAY='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m'

# Default Configuration State
BONSAI_PORT=8080
GEMMA_PORT=8081
BONSAI_VARIANT="PTQ1_0"
BONSAI_CTX=70000
BONSAI_KV="f16"
BONSAI_NGRAM=true

load_config() {
    if [ -f "${CONFIG_FILE}" ] && command -v jq &>/dev/null; then
        BONSAI_PORT=$(jq -r '.BonsaiPort // 8080' "${CONFIG_FILE}")
        GEMMA_PORT=$(jq -r '.GemmaPort // 8081' "${CONFIG_FILE}")
        BONSAI_VARIANT=$(jq -r '.BonsaiVariant // "PTQ1_0"' "${CONFIG_FILE}")
        BONSAI_CTX=$(jq -r '.BonsaiCtx // 70000' "${CONFIG_FILE}")
        BONSAI_KV=$(jq -r '.BonsaiKvType // "f16"' "${CONFIG_FILE}")
        BONSAI_NGRAM=$(jq -r '.BonsaiNgram // false' "${CONFIG_FILE}")
    fi
}

save_config() {
    cat <<EOF > "${CONFIG_FILE}"
{
    "BonsaiPort": ${BONSAI_PORT},
    "BonsaiVariant": "${BONSAI_VARIANT}",
    "BonsaiCtx": ${BONSAI_CTX},
    "BonsaiKvType": "${BONSAI_KV}",
    "GemmaPort": ${GEMMA_PORT},
    "BonsaiNgram": ${BONSAI_NGRAM}
}
EOF
}

load_config

get_lan_ip() {
    ip route get 1.1.1.1 2>/dev/null | awk '{print $7}' || hostname -I | awk '{print $1}' || echo "127.0.0.1"
}

check_port() {
    local port="$1"
    if command -v ss &>/dev/null; then
        ss -tulpn 2>/dev/null | grep -q ":${port} " && return 0
    elif command -v netstat &>/dev/null; then
        netstat -tulpn 2>/dev/null | grep -q ":${port} " && return 0
    elif command -v lsof &>/dev/null; then
        lsof -i ":${port}" &>/dev/null && return 0
    fi
    return 1
}

check_health() {
    local port="$1"
    if curl -s -m 1 "http://127.0.0.1:${port}/health" | grep -q '"status":"ok"'; then
        echo "OK"
    elif check_port "${port}"; then
        echo "Warming up..."
    else
        echo "STOPPED"
    fi
}

update_systemd_bonsai() {
    local kv_flags=""
    if [ "${BONSAI_KV}" != "f16" ]; then
        kv_flags=" -ctk ${BONSAI_KV} -ctv ${BONSAI_KV}"
    fi

    local spec_flags=""
    local dflash_path="${MODELS_DIR}/Ternary-Bonsai-27B-dflash-Q4_0.gguf"
    if [ "${BONSAI_NGRAM}" = "true" ] && [ -f "${dflash_path}" ]; then
        spec_flags=" -md ${dflash_path} --spec-type draft-dflash --spec-draft-ngl 99"
    elif [ "${BONSAI_NGRAM}" = "true" ]; then
        spec_flags=" --spec-type ngram-simple --spec-ngram-simple-size-m 7"
    fi

    local model_path="${MODELS_DIR}/Ternary-Bonsai-2-27B-${BONSAI_VARIANT}.gguf"
    local current_user
    current_user=$(id -un)

    cat <<EOF | sudo tee /etc/systemd/system/bonsai2.service >/dev/null
[Unit]
Description=PrismML Ternary Bonsai 2 27B llama.cpp Service (${BONSAI_VARIANT})
After=network.target

[Service]
Type=simple
User=${current_user}
WorkingDirectory=${SCRIPT_DIR}
ExecStart=${BIN_DIR}/llama-server -m ${model_path} --host 0.0.0.0 --port ${BONSAI_PORT} -c ${BONSAI_CTX}${kv_flags} -np 1 --cache-ram 8192 -ngl 99 -fa on -t 16 -b 2048 -ub 1024 --reasoning off --reasoning-budget 0${spec_flags} --temp 0.7 --top-p 0.80 --top-k 20 --min-p 0.0 --presence-penalty 1.5
Restart=on-failure
RestartSec=10s
LimitNOFILE=65535
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
}

stop_gemma() {
    echo -e "${YELLOW}[+] Stopping Gemma4Service (Port ${GEMMA_PORT})...${NC}"
    sudo systemctl stop gemma4 2>/dev/null || true
    pkill -f "llama-server.*${GEMMA_PORT}" 2>/dev/null || true
    echo -e "${GREEN}[OK] Gemma4 stopped.${NC}"
}

stop_bonsai() {
    echo -e "${YELLOW}[+] Stopping Bonsai2Service (Port ${BONSAI_PORT})...${NC}"
    sudo systemctl stop bonsai2 2>/dev/null || true
    pkill -f "llama-server.*${BONSAI_PORT}" 2>/dev/null || true
    echo -e "${GREEN}[OK] Bonsai2 stopped.${NC}"
}

start_gemma() {
    stop_gemma
    echo -e "${GREEN}[+] Starting Gemma4Service on Port ${GEMMA_PORT}...${NC}"
    sudo systemctl start gemma4
    wait_health "${GEMMA_PORT}" "Gemma 4 12B"
}

start_bonsai() {
    stop_bonsai
    update_systemd_bonsai
    echo -e "${GREEN}[+] Starting Bonsai2Service (${BONSAI_VARIANT}, -c ${BONSAI_CTX}) on Port ${BONSAI_PORT}...${NC}"
    sudo systemctl start bonsai2
    wait_health "${BONSAI_PORT}" "Ternary Bonsai 2 27B (${BONSAI_VARIANT})"
}

wait_health() {
    local port="$1"
    local label="$2"
    echo -e "${CYAN}[+] Waiting for ${label} on Port ${port} to finish loading weights into VRAM...${NC}"
    for i in {1..25}; do
        sleep 1
        if curl -s -m 1 "http://127.0.0.1:${port}/health" | grep -q '"status":"ok"'; then
            echo -e "${GREEN}[SUCCESS] ${label} is ONLINE and READY!${NC}"
            return 0
        fi
    done
    echo -e "${YELLOW}[i] ${label} service started (still loading into VRAM).${NC}"
}

show_dashboard() {
    clear
    local lan_ip
    lan_ip=$(get_lan_ip)

    echo -e "${CYAN}================================================================================"
    echo -e "${GREEN}${BOLD}     Linux AI SERVICE MANAGER (Gemma4 & Bonsai2 - CUDA / systemd)               ${NC}"
    echo -e "${CYAN}================================================================================${NC}"

    if command -v nvidia-smi &>/dev/null; then
        local gpu_info
        gpu_info=$(nvidia-smi --query-gpu=name,memory.used,memory.total --format=csv,noheader 2>/dev/null || true)
        if [ -n "${gpu_info}" ]; then
            echo -e "${YELLOW} GPU VRAM   : ${gpu_info}${NC}"
        fi
    fi
    echo -e "${CYAN}--------------------------------------------------------------------------------${NC}"

    # Gemma Status
    local g_health
    g_health=$(check_health "${GEMMA_PORT}")
    local g_color="${YELLOW}"
    [ "${g_health}" = "OK" ] && g_color="${GREEN}"

    printf " [1] Gemma4Service  (Gemma 4 12B Q4_K_M - 7.66 GB)       | Port: %-5s | " "${GEMMA_PORT}"
    if [ "${g_health}" = "OK" ] || [ "${g_health}" = "Warming up..." ]; then
        echo -e "${GREEN}RUNNING (${g_health})${NC}"
        echo -e "     -> Local: ${CYAN}http://127.0.0.1:${GEMMA_PORT}${NC}   |   LAN: ${CYAN}http://${lan_ip}:${GEMMA_PORT}${NC}"
    else
        echo -e "${g_color}STOPPED${NC}"
    fi
    echo ""

    # Bonsai Status
    local b_health
    b_health=$(check_health "${BONSAI_PORT}")
    local b_color="${YELLOW}"
    [ "${b_health}" = "OK" ] && b_color="${GREEN}"
    local b_size="5.95 GB"
    [ "${BONSAI_VARIANT}" = "PQ2_0" ] && b_size="7.21 GB"
    local ctx_k=$(( BONSAI_CTX / 1024 ))

    printf " [2] Bonsai2Service (Ternary Bonsai 2 27B %s - %s) | Port: %-5s | " "${BONSAI_VARIANT}" "${b_size}" "${BONSAI_PORT}"
    if [ "${b_health}" = "OK" ] || [ "${b_health}" = "Warming up..." ]; then
        echo -e "${GREEN}RUNNING (${b_health})${NC}"
        echo -e "     -> Local: ${CYAN}http://127.0.0.1:${BONSAI_PORT}${NC}   |   LAN: ${CYAN}http://${lan_ip}:${BONSAI_PORT}${NC}"
    else
        echo -e "${b_color}STOPPED${NC}"
    fi
    echo -e "     -> Context: ${BONSAI_CTX} (${ctx_k}K, KV=${BONSAI_KV}) | Thinking: OFF | Fast Hadamard Kernels: ON"
    echo -e "${CYAN}================================================================================${NC}"
}

pause() {
    echo ""
    read -rp "Press Enter to return to menu..." _
}

while true; do
    show_dashboard
    ctx_k=$(( BONSAI_CTX / 1024 ))
    dflash_path="${MODELS_DIR}/Ternary-Bonsai-27B-dflash-Q4_0.gguf"
    spec_status="OFF"
    if [ "${BONSAI_NGRAM}" = "true" ] && [ -f "${dflash_path}" ]; then
        spec_status="ON (Neural DFlash Drafter: 85-110+ tok/s)"
    elif [ "${BONSAI_NGRAM}" = "true" ]; then
        spec_status="ON (ngram-simple: 54+ tok/s sustained, 0 MB extra VRAM)"
    fi
    echo -e "${YELLOW} EXCLUSIVE MODE (100% Dedicated GPU VRAM & Max Speed):${NC}"
    echo -e "  ${GREEN}[1] Run ONLY Gemma 4 12B${NC}           (Stops Bonsai, Starts Gemma4 on Port ${GEMMA_PORT})"
    echo -e "  ${GREEN}[2] Run ONLY Bonsai 2 27B (PTQ1_0)${NC} (Stops Gemma,  Starts Bonsai2 PTQ1_0 on Port ${BONSAI_PORT})"
    echo -e "  ${GREEN}[3] Run ONLY Bonsai 2 27B (PQ2_0)${NC}  (Stops Gemma,  Starts Bonsai2 PQ2_0  on Port ${BONSAI_PORT})"
    echo ""
    echo -e "${YELLOW} INDIVIDUAL SERVICE CONTROL (systemd):${NC}"
    echo -e "  ${CYAN}[4] Start Gemma4Service${NC}            (Port ${GEMMA_PORT})"
    echo -e "  ${CYAN}[5] Stop  Gemma4Service${NC}            (Port ${GEMMA_PORT})"
    echo -e "  ${CYAN}[6] Start Bonsai2Service${NC}           (Port ${BONSAI_PORT} - ${BONSAI_VARIANT})"
    echo -e "  ${CYAN}[7] Stop  Bonsai2Service${NC}           (Port ${BONSAI_PORT})"
    echo -e "  ${MAGENTA}[8] Run BOTH Simultaneously${NC}        (Gemma on ${GEMMA_PORT} + Bonsai on ${BONSAI_PORT})"
    echo -e "  ${RED}[9] Shut Down BOTH Services${NC}        (Free 100% GPU VRAM)"
    echo ""
    echo -e "${YELLOW} TUNING, CONTEXT, LOGS & TOOLS:${NC}"
    echo -e "  [K] Change Bonsai 2 Context Size   (Current: ${BONSAI_CTX} / ${ctx_k}K, KV=${BONSAI_KV} -> 32K / 48K / 64K / 70K / 72K)"
    echo -e "  [V] Toggle Bonsai 2 Variant        (Current: ${BONSAI_VARIANT} -> PTQ1_0 5.95GB vs PQ2_0 7.21GB)"
    echo -e "  [S] Toggle Speculative Drafter     (Current: ${spec_status})"
    echo -e "  [L] Live Server Logs               (journalctl -u bonsai2 -f)"
    echo -e "  [B] Run GPU Speed Benchmark        (llama-bench)"
    echo -e "  [C] Launch Interactive CLI Chat    (llama-cli)"
    echo -e "  [R] Refresh Status                 [0 / Q] Exit"
    echo ""

    read -rp "Select Option: " choice
    choice=$(echo "${choice}" | tr '[:lower:]' '[:upper:]')

    case "${choice}" in
        1)
            stop_bonsai
            start_gemma
            pause
            ;;
        2)
            BONSAI_VARIANT="PTQ1_0"
            if [ "${BONSAI_CTX}" -lt 70000 ]; then
                BONSAI_CTX=70000
            fi
            BONSAI_KV="f16"
            save_config
            stop_gemma
            start_bonsai
            pause
            ;;
        3)
            BONSAI_VARIANT="PQ2_0"
            if [ "${BONSAI_CTX}" -gt 48000 ]; then
                echo -e "${YELLOW}[!] Note: PQ2_0 uses 7.21 GB VRAM. Auto-capping context to 48,000 (f16) for 12GB VRAM...${NC}"
                BONSAI_CTX=48000
            fi
            BONSAI_KV="f16"
            save_config
            stop_gemma
            start_bonsai
            pause
            ;;
        4)
            start_gemma
            pause
            ;;
        5)
            stop_gemma
            pause
            ;;
        6)
            start_bonsai
            pause
            ;;
        7)
            stop_bonsai
            pause
            ;;
        8)
            start_gemma
            start_bonsai
            pause
            ;;
        9)
            stop_gemma
            stop_bonsai
            pkill -f "llama-server" 2>/dev/null || true
            echo -e "${GREEN}[SUCCESS] Both services stopped and 100% VRAM freed.${NC}"
            pause
            ;;
        K)
            echo ""
            echo -e "${CYAN}Select Bonsai 2 Context Window Size (RTX 4070 Ti 12 GB VRAM):${NC}"
            echo -e "  [1]  32,768 ( 32K)  - f16 KV Cache (~2.0 GiB KV VRAM - Fast & Stable for both PQ2_0 and PTQ1_0)"
            echo -e "  [2]  48,000 ( 48K)  - f16 KV Cache (~3.0 GiB KV VRAM - Max safe limit for PQ2_0 7.21GB)"
            echo -e "  [3]  65,536 ( 64K)  - f16 KV Cache (~4.1 GiB KV VRAM - Standard 64K for PTQ1_0 5.95GB)"
            echo -e "  [4]  70,000 ( 70K)  - f16 KV Cache (~4.38 GiB KV VRAM - Recommended for DeepSeek Harness on PTQ1_0)"
            echo -e "  [5]  72,000 ( 72K)  - f16 KV Cache (~4.50 GiB KV VRAM - Maximum tested VRAM limit for PTQ1_0)"
            echo -e "  [C] Custom Context  - Type any exact token number (e.g. 68000, 70000)"
            read -rp "Choose [1-5 or C]: " csel
            csel=$(echo "${csel}" | tr '[:lower:]' '[:upper:]')
            case "${csel}" in
                1) BONSAI_CTX=32768; BONSAI_KV="f16" ;;
                2) BONSAI_CTX=48000; BONSAI_KV="f16" ;;
                3) BONSAI_CTX=65536; BONSAI_KV="f16" ;;
                4) BONSAI_CTX=70000; BONSAI_KV="f16" ;;
                5) BONSAI_CTX=72000; BONSAI_KV="f16" ;;
                C)
                    read -rp "Enter custom context size (e.g. 65600, 68000, 70000): " cval
                    if [[ "${cval}" =~ ^[0-9]+$ ]] && [ "${cval}" -gt 1024 ]; then
                        BONSAI_CTX=${cval}
                        BONSAI_KV="f16"
                    fi
                    ;;
            esac
            save_config
            update_systemd_bonsai
            echo -e "${GREEN}[SUCCESS] Context set to ${BONSAI_CTX} (KV=${BONSAI_KV}).${NC}"
            echo -e "${YELLOW}[i] Select [2] or [3] to restart Bonsai with the new context.${NC}"
            pause
            ;;
        V)
            if [ "${BONSAI_VARIANT}" = "PTQ1_0" ]; then
                BONSAI_VARIANT="PQ2_0"
                if [ "${BONSAI_CTX}" -gt 48000 ]; then
                    BONSAI_CTX=48000
                fi
            else
                BONSAI_VARIANT="PTQ1_0"
                if [ "${BONSAI_CTX}" -lt 70000 ]; then
                    BONSAI_CTX=70000
                fi
            fi
            save_config
            update_systemd_bonsai
            echo -e "${GREEN}[SUCCESS] Switched variant to ${BONSAI_VARIANT} (Context: ${BONSAI_CTX}).${NC}"
            pause
            ;;
        S)
            if [ "${BONSAI_NGRAM}" = "true" ]; then
                BONSAI_NGRAM="false"
            else
                BONSAI_NGRAM="true"
            fi
            save_config
            update_systemd_bonsai
            dpath="${MODELS_DIR}/Ternary-Bonsai-27B-dspark-Q4_1.gguf"
            if [ "${BONSAI_NGRAM}" = "true" ] && [ -f "${dpath}" ]; then
                echo -e "${GREEN}[SUCCESS] Speculative decoding ENABLED with DSpark drafter!${NC}"
            elif [ "${BONSAI_NGRAM}" = "true" ]; then
                echo -e "${YELLOW}[!] Speculative decoding enabled (ngram). Download DSpark drafter via ./download_models.sh for 2x-3x speed!${NC}"
            else
                echo -e "${YELLOW}[OK] Speculative decoding DISABLED.${NC}"
            fi
            echo -e "${YELLOW}[i] Select [2] or [3] to restart Bonsai with updated flags.${NC}"
            pause
            ;;
        L)
            echo -e "${CYAN}Displaying live logs for Bonsai2Service (Ctrl+C to return)...${NC}"
            sudo journalctl -u bonsai2 -f -n 50
            ;;
        B)
            if [ -x "${BIN_DIR}/llama-bench" ]; then
                "${BIN_DIR}/llama-bench" -m "${MODELS_DIR}/Ternary-Bonsai-2-27B-${BONSAI_VARIANT}.gguf" -p 512,2048 -n 128 -ngl 99 -fa 1
            else
                echo -e "${RED}[!] llama-bench not compiled yet.${NC}"
            fi
            pause
            ;;
        C)
            if [ -x "${BIN_DIR}/llama-cli" ]; then
                "${BIN_DIR}/llama-cli" -m "${MODELS_DIR}/Ternary-Bonsai-2-27B-${BONSAI_VARIANT}.gguf" -c 8192 -ngl 99 -fa 1 --temp 0.7
            else
                echo -e "${RED}[!] llama-cli not compiled yet.${NC}"
            fi
            pause
            ;;
        R)
            continue
            ;;
        0|Q)
            echo -e "${GREEN}Goodbye!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid selection.${NC}"
            sleep 1
            ;;
    esac
done
