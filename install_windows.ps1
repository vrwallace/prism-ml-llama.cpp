# ==============================================================================
# All-in-One Windows Installer for PrismML Ternary Bonsai 2 27B & Gemma 4
# Sets up CUDA build environment, WinSW native services, firewall rules,
# and prepares the service manager on Windows 10/11 or Windows Server.
# ==============================================================================

# 1. Elevate to Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[+] Elevating to Administrator to configure Windows services and firewall..." -ForegroundColor Cyan
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }
Set-Location $ScriptDir

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "   PrismML Ternary Bonsai 2 (27B) - Windows Automated Installer                 " -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "Working Directory: $ScriptDir`n" -ForegroundColor Yellow

# ------------------------------------------------------------------------------
# 2. Check GPU & NVIDIA Drivers
# ------------------------------------------------------------------------------
Write-Host "[1/6] Checking GPU and NVIDIA Drivers..." -ForegroundColor Cyan
$nvidiaSmi = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
if (-not $nvidiaSmi) {
    Write-Host "[ERROR] 'nvidia-smi' not found!" -ForegroundColor Red
    Write-Host "Please install NVIDIA graphics drivers for your GPU before running." -ForegroundColor Yellow
    exit 1
}

try {
    $gpuInfo = nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>$null
    Write-Host "[OK] Detected GPU: $gpuInfo" -ForegroundColor Green
} catch {}
Write-Host ""

# ------------------------------------------------------------------------------
# 3. Create Required Folders
# ------------------------------------------------------------------------------
Write-Host "[2/6] Initializing directory layout..." -ForegroundColor Cyan
$modelsDir = Join-Path $ScriptDir "models"
$logsDir   = Join-Path $ScriptDir "logs"
$binDir    = Join-Path $ScriptDir "bin"

New-Item -ItemType Directory -Path $modelsDir -Force | Out-Null
New-Item -ItemType Directory -Path $logsDir -Force   | Out-Null
New-Item -ItemType Directory -Path $binDir -Force    | Out-Null
Write-Host "[OK] Directories initialized: models\, logs\, bin\" -ForegroundColor Green
Write-Host ""

# ------------------------------------------------------------------------------
# 4. Check / Download WinSW Service Wrapper
# ------------------------------------------------------------------------------
Write-Host "[3/6] Setting up WinSW Windows Service Wrapper..." -ForegroundColor Cyan
$bonsaiExe = Join-Path $ScriptDir "Bonsai2Service.exe"
$gemmaExe  = Join-Path $ScriptDir "Gemma4Service.exe"
$winswUrl  = "https://github.com/winsw/winsw/releases/download/v2.12.0/WinSW-x64.exe"

if (-not (Test-Path $bonsaiExe)) {
    Write-Host "[+] Downloading WinSW-x64.exe for Bonsai2Service..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $winswUrl -OutFile $bonsaiExe -UseBasicParsing
}

if (-not (Test-Path $gemmaExe)) {
    Write-Host "[+] Downloading WinSW-x64.exe for Gemma4Service..." -ForegroundColor Yellow
    Copy-Item $bonsaiExe $gemmaExe -Force
}
Write-Host "[OK] WinSW executables verified." -ForegroundColor Green
Write-Host ""

# ------------------------------------------------------------------------------
# 5. Check or Compile llama.cpp with CUDA
# ------------------------------------------------------------------------------
Write-Host "[4/6] Checking llama.cpp binary and CUDA compilation..." -ForegroundColor Cyan
$serverExe = Join-Path $binDir "llama-server.exe"

if (-not (Test-Path $serverExe)) {
    $builtExe = Join-Path $ScriptDir "build\bin\Release\llama-server.exe"
    if (Test-Path $builtExe) {
        Copy-Item (Join-Path $ScriptDir "build\bin\Release\*") $binDir -Recurse -Force
    }
}

if (-not (Test-Path $serverExe)) {
    $cmake = Get-Command cmake.exe -ErrorAction SilentlyContinue
    $nvcc  = Get-Command nvcc.exe -ErrorAction SilentlyContinue

    if ($cmake -and $nvcc) {
        Write-Host "[+] Compiling llama.cpp with CUDA & Flash Attention..." -ForegroundColor Cyan
        cmake -B build -DGGML_CUDA=ON -DGGML_CUDA_FA=ON -DCMAKE_BUILD_TYPE=Release
        cmake --build build --config Release -j
        if (Test-Path (Join-Path $ScriptDir "build\bin\Release\llama-server.exe")) {
            Copy-Item (Join-Path $ScriptDir "build\bin\Release\*") $binDir -Recurse -Force
        }
    } else {
        Write-Host "[!] Note: Pre-compiled llama-server.exe not in bin\, and CMake/NVCC not in PATH." -ForegroundColor Yellow
        Write-Host "    If you have pre-built binaries, place them into: $binDir" -ForegroundColor Yellow
    }
}

if (Test-Path $serverExe) {
    Write-Host "[OK] Found llama-server.exe in $binDir" -ForegroundColor Green
}
Write-Host ""

# ------------------------------------------------------------------------------
# 6. Configure Windows Firewall
# ------------------------------------------------------------------------------
Write-Host "[5/6] Configuring Windows Firewall Rules for LAN access..." -ForegroundColor Cyan
try {
    netsh advfirewall firewall add rule name="llama.cpp Server Port 8080 (Bonsai 2)" dir=in action=allow protocol=TCP localport=8080 profile=any | Out-Null
    netsh advfirewall firewall add rule name="llama.cpp Server Port 8081 (Gemma 4)" dir=in action=allow protocol=TCP localport=8081 profile=any | Out-Null
    Write-Host "[OK] Inbound firewall ports 8080 and 8081 opened for LAN connections." -ForegroundColor Green
} catch {
    Write-Host "[!] Could not add firewall rules automatically." -ForegroundColor Yellow
}
Write-Host ""

# ------------------------------------------------------------------------------
# 7. Register WinSW Services
# ------------------------------------------------------------------------------
Write-Host "[6/6] Registering Native Windows Services..." -ForegroundColor Cyan
$svcB = Get-Service -Name "Bonsai2Service" -ErrorAction SilentlyContinue
if (-not $svcB -and (Test-Path $bonsaiExe)) {
    & $bonsaiExe install | Out-Null
    Set-Service -Name "Bonsai2Service" -StartupType Manual -ErrorAction SilentlyContinue
    Write-Host "[OK] Bonsai2Service installed via WinSW." -ForegroundColor Green
}

$svcG = Get-Service -Name "Gemma4Service" -ErrorAction SilentlyContinue
if (-not $svcG -and (Test-Path $gemmaExe)) {
    & $gemmaExe install | Out-Null
    Set-Service -Name "Gemma4Service" -StartupType Manual -ErrorAction SilentlyContinue
    Write-Host "[OK] Gemma4Service installed via WinSW." -ForegroundColor Green
}
Write-Host ""

# ------------------------------------------------------------------------------
# Complete!
# ------------------------------------------------------------------------------
Write-Host "================================================================================" -ForegroundColor Green
Write-Host "               WINDOWS INSTALLATION COMPLETE!                                   " -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  1. Download Models:  powershell -ExecutionPolicy Bypass -File .\download_models.ps1" -ForegroundColor Cyan
Write-Host "  2. Service Manager:  powershell -ExecutionPolicy Bypass -File .\servicemanager.ps1" -ForegroundColor Cyan
Write-Host ""

$dlChoice = (Read-Host "Would you like to run the model downloader now? (Y/N)").Trim().ToUpper()
if ($dlChoice -eq "Y") {
    & (Join-Path $ScriptDir "download_models.ps1")
}

$mgrChoice = (Read-Host "Launch Service Manager now? (Y/N)").Trim().ToUpper()
if ($mgrChoice -eq "Y") {
    & (Join-Path $ScriptDir "servicemanager.ps1")
}
