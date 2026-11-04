# PrismML Ternary Bonsai 2 (27B) & Gemma 4 Service Suite

Automated installer and service management suite for running **PrismML Ternary Bonsai 2 27B** (`PTQ1_0` / `PQ2_0`) and **Google Gemma 4 12B** with native CUDA GPU acceleration and system service daemons.

---

## 🐧 Linux Quickstart (Ubuntu / Debian / Fedora / Arch)

### 1. Clone & Run the Installer
```bash
git clone -b bonsai2 https://github.com/vrwallace/prism-ml-llama.cpp.git
cd prism-ml-llama.cpp
chmod +x install_linux.sh
./install_linux.sh
```
The installer will:
1. Verify your NVIDIA GPU and drivers (`nvidia-smi`).
2. Detect/install `nvcc` and CUDA build dependencies (`cmake`, `ccache`, `libcurl`).
3. Compile `llama.cpp` with native CUDA and Flash Attention enabled.
4. Register `bonsai2.service` and `gemma4.service` with Linux `systemd`.

### 2. Download Models
```bash
./download_models.sh
```
Choose `[1]` for `PTQ1_0` (5.95 GB), `[2]` for `PQ2_0` (7.21 GB), `[5]` for the `DSpark Drafter` (1.95 GB), or `[A]` for all recommended files (including the multimodal vision projector and DSpark speculative drafter).

> [!TIP]
> **Combining Bonsai 2 with DSpark Drafter (2x–3x Speed Boost)**:
> Downloading `Ternary-Bonsai-27B-dspark-Q4_1.gguf` enables speculative parallel block decoding. It generates candidate token blocks in parallel, boosting generation speed on your RTX 4070 Ti from **42 tok/s up to 80–110+ tok/s** while using only ~7.9 GB total VRAM! Toggle it in Service Manager via option `[S]` (Linux) or `[N]` (Windows).

### 3. Launch Service Manager
```bash
./servicemanager.sh
```
Or manage via native `systemd`:
```bash
sudo systemctl start bonsai2       # Start Bonsai 2
sudo systemctl stop bonsai2        # Stop Bonsai 2
journalctl -u bonsai2 -f           # Follow live server logs
```

---

## 🪟 Windows Quickstart (Windows 10 / 11 / Server)

### 1. Clone & Run the Installer
Open PowerShell as Administrator:
```powershell
git clone -b bonsai2 https://github.com/vrwallace/prism-ml-llama.cpp.git
cd prism-ml-llama.cpp
powershell -ExecutionPolicy Bypass -File .\install_windows.ps1
```
The installer will:
1. Verify your GPU and VRAM.
2. Initialize directories and WinSW service executables.
3. Automatically configure Windows Firewall for incoming LAN connections (Ports 8080 & 8081).
4. Register `Bonsai2Service` and `Gemma4Service` as background Windows services.

### 2. Download Models
```powershell
powershell -ExecutionPolicy Bypass -File .\download_models.ps1
```

### 3. Launch Service Manager
```powershell
powershell -ExecutionPolicy Bypass -File .\servicemanager.ps1
```

---

## ⚙️ Recommended DeepSeek Harness (`dsh`) Configuration

When connecting an automated evaluation harness or agent to your Bonsai 2 endpoint (`http://localhost:8080/v1`):

| Setting | Recommended Value | Why |
| :--- | :--- | :--- |
| **Context Window** | `65536` | Matches standard 64K agent baseline. |
| **Max Output Tokens** | `4096` *(or 8192 max)* | **Do NOT set to 65536.** Leaving room allows automatic context compaction to trigger properly. |
| **Context Compaction** | **Enabled (`ON`)** | Automatically condenses conversation history around ~52,000 tokens so requests never overflow. |
| **KV Cache Type** | `f16` (Unquantized) | Prevents Hadamard attention drift and eliminates slash (`///////`) repetition loops. |
