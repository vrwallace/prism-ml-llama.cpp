# PrismML Ternary Bonsai 2 (27B) & Gemma 4 Service Suite

Automated installer and service management suite for running **PrismML Ternary Bonsai 2 27B** (`PTQ1_0` / `PQ2_0`) and **Google Gemma 4 12B** with native CUDA GPU acceleration, system service daemons, and speculative block decoding.

---

## ⚡ Verified Benchmark on RTX 4070 Ti (12 GB VRAM)

| Configuration | VRAM Used | Context Window | Generation Speed | Prompt Processing |
| :--- | :--- | :--- | :--- | :--- |
| **Bonsai 2 PTQ1_0 (Baseline)** | 11.2 GB | **70,144 tokens** (`f16` KV) | ~27.9 tok/s | ~26.0 tok/s |
| **Bonsai 2 PTQ1_0 + Speculative N-Gram Block Drafting** | 11.2 GB | **70,144 tokens** (`f16` KV) | **54.1 – 54.8 tok/s** | **72.9 – 81.9 tok/s** |
| **Bonsai 2 PTQ1_0 + Neural DFlash Drafter** | 11.8 GB | 65,000 tokens (`f16` KV) | **85.0 – 110+ tok/s** | ~85.0 tok/s |

> [!TIP]
> **What is Clover / Speculative Block Decoding?**
> Standard LLM inference is memory-bandwidth bound: the GPU streams all 5.95 GB of weights for every single token (~28 tok/s). 
> Speculative block decoding predicts candidate blocks (up to 7 tokens ahead in parallel) which Bonsai 2 verifies in a **single GPU forward pass**, doubling throughput to **54+ tok/s** with **zero loss in quality** and **0 MB extra VRAM**.

---

## 🐧 Linux Quickstart (Ubuntu / Debian / Fedora / Arch)

### 1. Clone & Run the Installer
```bash
git clone -b bonsai2 https://github.com/vrwallace/prism-ml-llama.cpp.git
cd prism-ml-llama.cpp
chmod +x install_linux.sh servicemanager.sh download_models.sh
./install_linux.sh
```
The installer will automatically:
1. Verify NVIDIA GPU, CUDA driver, and compute architecture (Ada 89 / Ampere 86 / Hopper 90).
2. Install build dependencies (`gcc`, `cmake`, `git`, `ccache`, `libcurl`, `python3`).
3. Compile `llama.cpp` with native CUDA and Flash Attention enabled.
4. Register `bonsai2.service` and `gemma4.service` as native `systemd` background services.

### 2. Download Models
```bash
./download_models.sh
```
* **Option `[1]`**: `Ternary-Bonsai-2-27B-PTQ1_0.gguf` (**5.95 GB** — Lowest VRAM, recommended for 12GB GPUs, supports **70K context**).
* **Option `[2]`**: `Ternary-Bonsai-2-27B-PQ2_0.gguf` (**7.21 GB** — Higher precision, supports up to 48K context in 12GB).
* **Option `[3]`**: `Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf` (**0.63 GB** — Multimodal vision projector).
* **Option `[A]`**: Download all recommended files.

### 3. Launch Service Manager
```bash
./servicemanager.sh
```
The interactive terminal dashboard allows you to:
* Switch between models (`[1]` Gemma 4, `[2]` Bonsai 2 PTQ1_0, `[3]` Bonsai 2 PQ2_0).
* Toggle **Speculative Block Drafting** (`[S]`) on/off.
* Adjust context sizes (`[K]`: 32K, 48K, 64K, 70K).
* View live logs (`[L]`) or run GPU benchmarks (`[B]`).

Or control directly with `systemctl`:
```bash
sudo systemctl start bonsai2       # Start Bonsai 2 on port 8080
sudo systemctl stop bonsai2        # Stop Bonsai 2
sudo systemctl restart bonsai2     # Restart Bonsai 2
journalctl -u bonsai2 -f           # Follow live server output
```

---

## 🪟 Windows Quickstart (Windows 10 / 11 / Server)

### 1. Clone & Run Installer
Open **PowerShell as Administrator**:
```powershell
git clone -b bonsai2 https://github.com/vrwallace/prism-ml-llama.cpp.git
cd prism-ml-llama.cpp
powershell -ExecutionPolicy Bypass -File .\install_windows.ps1
```
The installer will:
1. Set up directories (`models\`, `logs\`, `bin\`).
2. Download and configure the native WinSW service wrappers (`Bonsai2Service.exe` & `Gemma4Service.exe`).
3. Configure Windows Firewall rules to allow LAN connections to Ports 8080 and 8081.
4. Register the background services with Windows Service Control Manager.

### 2. Download Models
```powershell
powershell -ExecutionPolicy Bypass -File .\download_models.ps1
```

### 3. Launch Service Manager
```powershell
powershell -ExecutionPolicy Bypass -File .\servicemanager.ps1
```
* Press **`[2]`** to launch Bonsai 2 (PTQ1_0).
* Press **`[N]`** to toggle Speculative Block Drafting (N-Gram / DFlash).
* Press **`[K]`** to select context preset (Default: **70,000 tokens**).

Or manage via PowerShell:
```powershell
Restart-Service Bonsai2Service     # Apply configuration updates
Get-Content logs\Bonsai2Service.err.log -Tail 30 -Wait   # View live logs
```

---

## 🧠 Speculative Block Decoding Configuration Guide

### Option A: Context N-Gram Speculative Decoding (Default — Zero Setup)
Already pre-configured in `servicemanager.ps1` and `servicemanager.sh`!
* **Command flag**: `--spec-type ngram-simple --spec-ngram-simple-size-m 7`
* **VRAM Overhead**: **0 MB**
* **Speedup**: **54+ tokens/sec** sustained (nearly 2x speedup on coding, structured JSON, and reasoning chains).

### Option B: Neural DFlash Drafter (85 – 110+ tok/s)
To run with a dedicated neural drafter:
1. Download `Ternary-Bonsai-27B-dspark-bf16.gguf` from Hugging Face.
2. Convert it using the included script to modern `dflash` format while dropping redundant shared tensors:
   ```bash
   python gguf-py/gguf/scripts/gguf_dspark_to_dflash.py \
       --drop-shared-tensors \
       models/Ternary-Bonsai-27B-dspark-bf16.gguf \
       models/Ternary-Bonsai-2-27B-PTQ1_0.gguf \
       models/Ternary-Bonsai-27B-dflash-borrowed.gguf
   ```
3. Quantize to `Q4_0` using `llama-quantize`:
   ```bash
   ./build/bin/llama-quantize \
       models/Ternary-Bonsai-27B-dflash-borrowed.gguf \
       models/Ternary-Bonsai-27B-dflash-Q4_0.gguf \
       Q4_0
   ```
4. Place `Ternary-Bonsai-27B-dflash-Q4_0.gguf` in `models/`. The Service Manager will automatically detect it and enable `--spec-type draft-dflash --spec-draft-ngl 99`.

---

## ⚙️ Recommended Agent & Harness Settings

When connecting DeepSeek Harness (`dsh`), Continue, Roo-Code, Cline, or Open WebUI to `http://localhost:8080/v1`:

| Parameter | Recommended Value | Reason |
| :--- | :--- | :--- |
| **API Endpoint** | `http://localhost:8080/v1` | OpenAI-compatible endpoint |
| **Model Name** | `Ternary-Bonsai-2-27B-PTQ1_0.gguf` | Matches server model ID |
| **Context Window** | `65536` | Matches standard 64K agent baseline |
| **Max Output Tokens** | `4096` *(max 8192)* | Leaving room allows context compaction to trigger |
| **Temperature** | `0.7` | Optimal reasoning fidelity |
| **Top-P / Top-K** | `top-p 0.80`, `top-k 20` | Tight sampling eliminates drift |
| **Presence Penalty** | `1.5` | Essential to prevent loop locks |
| **KV Cache** | Pure `f16` (Unquantized) | Prevents Flash Attention repetition errors (`///////`) |

---

## 📡 API Health & Completion Check

Test endpoint with `curl`:
```bash
# Health check
curl -s http://127.0.0.1:8080/health

# Test completion
curl -s http://127.0.0.1:8080/completion \
  -H "Content-Type: application/json" \
  -d '{"prompt": "Write a python fibonacci function.", "n_predict": 100}'
```
