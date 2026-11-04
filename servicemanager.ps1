# ==============================================================================
# Unified WinSW Service Manager (Gemma4Service & Bonsai2Service)
# Manages Native Windows Services via WinSW (Windows Service Wrapper):
#   - Gemma4Service  (Google Gemma 4 12B Q4_K_M)
#   - Bonsai2Service (PrismML Ternary Bonsai 2 27B - PTQ1_0 or PQ2_0)
# ==============================================================================
param (
    [Parameter(Position=0, Mandatory=$false)]
    [string]$Action = "menu",

    [Parameter(Position=1, Mandatory=$false)]
    [string]$Target = "",

    [Parameter(Position=2, Mandatory=$false)]
    [int]$CustomPort = 0
)

# Self-elevate to Administrator when running interactive menu so WinSW services can be controlled
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and $Action -eq "menu") {
    Write-Host "[+] Elevating to Administrator to manage WinSW Windows Services..." -ForegroundColor Cyan
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$ScriptDir   = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }

# Dynamic portable path discovery: check local folder first, then fallback to scratch locations
$BonsaiDir   = if (Test-Path (Join-Path $ScriptDir "bin\llama-server.exe")) { $ScriptDir } `
               elseif (Test-Path (Join-Path $ScriptDir "build\bin\Release\llama-server.exe")) { Join-Path $ScriptDir "build\bin\Release" } `
               elseif (Test-Path "C:\Users\vonwa\.gemini\antigravity\scratch\prism_cuda\bin\llama-server.exe") { "C:\Users\vonwa\.gemini\antigravity\scratch\prism_cuda" } `
               else { $ScriptDir }

$GemmaDir    = if (Test-Path "C:\Users\vonwa\.gemini\antigravity\scratch\llama_gemma\Gemma4Service.exe") { "C:\Users\vonwa\.gemini\antigravity\scratch\llama_gemma" } `
               else { $BonsaiDir }

$ModelsDir   = if (Test-Path (Join-Path $GemmaDir "models")) { Join-Path $GemmaDir "models" } `
               elseif (Test-Path (Join-Path $ScriptDir "models")) { Join-Path $ScriptDir "models" } `
               else { Join-Path $BonsaiDir "models" }

$ConfigFile  = if (Test-Path (Join-Path $ScriptDir "winsw_manager_config.json")) { Join-Path $ScriptDir "winsw_manager_config.json" } `
               elseif (Test-Path (Join-Path $GemmaDir "winsw_manager_config.json")) { Join-Path $GemmaDir "winsw_manager_config.json" } `
               else { Join-Path $ScriptDir "winsw_manager_config.json" }

$GemmaExe    = Join-Path $GemmaDir "Gemma4Service.exe"
$GemmaXml    = Join-Path $GemmaDir "Gemma4Service.xml"

$BonsaiExe   = if (Test-Path (Join-Path $BonsaiDir "Bonsai2Service.exe")) { Join-Path $BonsaiDir "Bonsai2Service.exe" } else { Join-Path $ScriptDir "Bonsai2Service.exe" }
$BonsaiXml   = if (Test-Path (Join-Path $BonsaiDir "Bonsai2Service.xml")) { Join-Path $BonsaiDir "Bonsai2Service.xml" } else { Join-Path $ScriptDir "Bonsai2Service.xml" }

$LlamaBench  = if (Test-Path (Join-Path $BonsaiDir "bin\llama-bench.exe")) { Join-Path $BonsaiDir "bin\llama-bench.exe" } else { Join-Path $ScriptDir "bin\llama-bench.exe" }
$LlamaCli    = if (Test-Path (Join-Path $BonsaiDir "bin\llama-cli.exe")) { Join-Path $BonsaiDir "bin\llama-cli.exe" } else { Join-Path $ScriptDir "bin\llama-cli.exe" }

# Default State Config
$State = @{
    GemmaPort     = 8081
    BonsaiPort    = 8080
    BonsaiVariant = "PTQ1_0"  # PTQ1_0 (5.95 GiB, Lowest VRAM, up to 72K f16 ctx) or PQ2_0 (7.21 GiB, up to 48K f16 ctx)
    BonsaiCtx     = 70000    # 70000 f16 default for PTQ1_0 (or 48000 for PQ2_0)
    BonsaiKvType  = "f16"    # f16 (unquantized 16-bit KV required to avoid Flash Attention /////// loops)
    BonsaiNgram   = $false   # OFF by default on Bonsai 2 (GDN recurrent layers do not allocate n_rs_seq for ngram-simple)
}

function Load-Config {
    if (Test-Path $ConfigFile) {
        try {
            $cfg = Get-Content $ConfigFile -Raw | ConvertFrom-Json
            if ($cfg.GemmaPort)     { $State.GemmaPort     = [int]$cfg.GemmaPort }
            if ($cfg.BonsaiPort)    { $State.BonsaiPort    = [int]$cfg.BonsaiPort }
            if ($cfg.BonsaiVariant) { $State.BonsaiVariant = [string]$cfg.BonsaiVariant }
            if ($cfg.BonsaiCtx)     { $State.BonsaiCtx     = [int]$cfg.BonsaiCtx }
            if ($cfg.BonsaiKvType)  { $State.BonsaiKvType  = [string]$cfg.BonsaiKvType }
            if ($null -ne $cfg.BonsaiNgram) { $State.BonsaiNgram = [bool]$cfg.BonsaiNgram }
            return
        } catch {}
    }
    Save-Config
}

function Save-Config {
    $State | ConvertTo-Json | Set-Content $ConfigFile -Encoding UTF8
}

Load-Config

function Ensure-WinSWRegistered {
    if (-not $isAdmin) { return }
    $svcGemma = Get-Service -Name "Gemma4Service" -ErrorAction SilentlyContinue
    if (-not $svcGemma -and (Test-Path $GemmaExe)) {
        Write-Host "[+] Registering Gemma4Service via WinSW..." -ForegroundColor Cyan
        & $GemmaExe install | Out-Null
    }
    $svcBonsai = Get-Service -Name "Bonsai2Service" -ErrorAction SilentlyContinue
    if (-not $svcBonsai -and (Test-Path $BonsaiExe)) {
        Write-Host "[+] Registering Bonsai2Service via WinSW..." -ForegroundColor Cyan
        & $BonsaiExe install | Out-Null
        Set-Service -Name "Bonsai2Service" -StartupType Manual -ErrorAction SilentlyContinue
    }
}

Ensure-WinSWRegistered

function Update-GemmaXml {
    param([string]$StartMode = "Automatic")
    $modelPath = Join-Path $ModelsDir "gemma-4-12B-it-Q4_K_M.gguf"
    $xml = @"
<service>
  <id>Gemma4Service</id>
  <name>Gemma 4 12B llama.cpp Service</name>
  <description>Native Windows Service (WinSW) for Google Gemma 4 12B LLM inference engine with CUDA 13.4 GPU acceleration</description>
  <executable>$GemmaDir\bin\llama-server.exe</executable>
  <arguments>-m "$modelPath" --host 0.0.0.0 --port $($State.GemmaPort) -c 16384 -ngl 99 -fa 1 -t 16 -b 2048 -ub 512 -sps 0.5 --reasoning-budget 0 --spec-type ngram-simple</arguments>
  <workingdirectory>$GemmaDir</workingdirectory>
  <logpath>$GemmaDir\logs</logpath>
  <log mode="roll"></log>
  <startmode>$StartMode</startmode>
  <onfailure action="restart" delay="10 sec"/>
</service>
"@
    Set-Content -Path $GemmaXml -Value $xml -Encoding UTF8
}

function Update-BonsaiXml {
    param([string]$StartMode = "Automatic")
    $modelFile = "Ternary-Bonsai-2-27B-$($State.BonsaiVariant).gguf"
    $modelPath = Join-Path $ModelsDir $modelFile
    $kvFlags   = if ($State.BonsaiKvType -and $State.BonsaiKvType -ne "f16") { " -ctk $($State.BonsaiKvType) -ctv $($State.BonsaiKvType)" } else { "" }
    
    $draftFile = "Ternary-Bonsai-27B-dspark-Q4_1.gguf"
    $draftPath = Join-Path $ModelsDir $draftFile
    $specFlags = if ($State.BonsaiNgram -and (Test-Path $draftPath)) {
        " -md `"$draftPath`" --spec-type draft-dspark"
    } elseif ($State.BonsaiNgram) {
        " --spec-type ngram-simple --spec-ngram-simple-size-m 7"
    } else { "" }

    $xml = @"
<service>
  <id>Bonsai2Service</id>
  <name>Ternary Bonsai 2 27B llama.cpp Service</name>
  <description>Native Windows Service (WinSW) for PrismML Ternary Bonsai 2 27B ($($State.BonsaiVariant)) with CUDA 13.4 GPU acceleration</description>
  <executable>$BonsaiDir\bin\llama-server.exe</executable>
  <arguments>-m "$modelPath" --host 0.0.0.0 --port $($State.BonsaiPort) -c $($State.BonsaiCtx)$kvFlags -np 1 --cache-ram 8192 -ngl 99 -fa on -t 16 -b 2048 -ub 1024 --reasoning off --reasoning-budget 0$specFlags --temp 0.7 --top-p 0.80 --top-k 20 --min-p 0.0 --presence-penalty 1.5</arguments>
  <workingdirectory>$BonsaiDir</workingdirectory>
  <logpath>$BonsaiDir\logs</logpath>
  <log mode="roll"></log>
  <startmode>$StartMode</startmode>
  <onfailure action="restart" delay="10 sec"/>
</service>
"@
    Set-Content -Path $BonsaiXml -Value $xml -Encoding UTF8
}

function Get-NetworkIP {
    $ips = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" }).IPAddress
    $lan = $ips | Where-Object { $_ -like "192.168.*" } | Select-Object -First 1
    if ($lan) { return $lan }
    if ($ips) { return ($ips | Select-Object -First 1) }
    return "127.0.0.1"
}

function Get-PortDetails {
    param([int]$Port)
    $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $conn) { return $null }
    $health = "Warming up..."
    try {
        $r = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 1 -ErrorAction Stop
        $health = "OK ($($r.status))"
    } catch {}
    return [PSCustomObject]@{
        PID    = $conn.OwningProcess
        Health = $health
    }
}

function Show-Dashboard {
    param([bool]$Clear = $false)
    if ($Clear) { try { Clear-Host } catch {} }

    $lanIp = Get-NetworkIP
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "     WinSW AI SERVICE MANAGER (Gemma4Service & Bonsai2Service - CUDA 13.4)      " -ForegroundColor Green
    Write-Host "================================================================================" -ForegroundColor Cyan

    try {
        $gpu = nvidia-smi --query-gpu=name,memory.used,memory.free,memory.total --format=csv,noheader 2>$null
        if ($gpu) { Write-Host " GPU VRAM   : $gpu" -ForegroundColor Yellow }
    } catch {}
    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkCyan

    # 1. Gemma4Service Status
    $svcG = Get-Service -Name "Gemma4Service" -ErrorAction SilentlyContinue
    $gStat = if ($svcG) { $svcG.Status.ToString().ToUpper() } else { "NOT REGISTERED" }
    $gPortInfo = Get-PortDetails -Port $State.GemmaPort
    $gColor = if ($gStat -eq "RUNNING" -or $gPortInfo) { "Green" } else { "DarkYellow" }

    Write-Host (" [1] Gemma4Service  (Gemma 4 12B Q4_K_M - 7.14 GB)      | Port: {0,-5} | " -f $State.GemmaPort) -NoNewline -ForegroundColor White
    if ($gPortInfo) {
        Write-Host ("RUNNING (PID {0}, Health: {1})" -f $gPortInfo.PID, $gPortInfo.Health) -ForegroundColor Green
        Write-Host ("     -> Local: http://127.0.0.1:{0}   |   LAN: http://{1}:{0}   |   WinSW: {2}" -f $State.GemmaPort, $lanIp, $gStat) -ForegroundColor Cyan
    } else {
        Write-Host ("STOPPED (WinSW: {0})" -f $gStat) -ForegroundColor $gColor
    }

    Write-Host ""

    # 2. Bonsai2Service Status
    $svcB = Get-Service -Name "Bonsai2Service" -ErrorAction SilentlyContinue
    $bStat = if ($svcB) { $svcB.Status.ToString().ToUpper() } else { "READY (Click Start)" }
    $bPortInfo = Get-PortDetails -Port $State.BonsaiPort
    $bSize = if ($State.BonsaiVariant -eq "PTQ1_0") { "5.95 GB" } else { "7.21 GB" }
    $ctxK  = [math]::Round($State.BonsaiCtx / 1024)
    $draftFile = "Ternary-Bonsai-27B-dspark-Q4_1.gguf"
    $hasDraft  = Test-Path (Join-Path $ModelsDir $draftFile)
    $ngStr = if ($State.BonsaiNgram -and $hasDraft) { "ON (DSpark Drafter: 2x-3x Speed)" }
             elseif ($State.BonsaiNgram) { "ON (ngram-simple)" }
             else { "OFF" }

    Write-Host (" [2] Bonsai2Service (Ternary Bonsai 2 27B {0} - {1}) | Port: {2,-5} | " -f $State.BonsaiVariant, $bSize, $State.BonsaiPort) -NoNewline -ForegroundColor White
    if ($bPortInfo) {
        Write-Host ("RUNNING (PID {0}, Health: {1})" -f $bPortInfo.PID, $bPortInfo.Health) -ForegroundColor Green
        Write-Host ("     -> Local: http://127.0.0.1:{0}   |   LAN: http://{1}:{0}   |   WinSW: {2}" -f $State.BonsaiPort, $lanIp, $bStat) -ForegroundColor Cyan
    } else {
        Write-Host ("STOPPED (WinSW: {0})" -f $bStat) -ForegroundColor DarkYellow
    }
    Write-Host ("     -> Context: {0} ({1}K, KV={2}) | Speculative: {3} | Thinking: OFF" -f $State.BonsaiCtx, $ctxK, $State.BonsaiKvType, $ngStr) -ForegroundColor Gray

    Write-Host "================================================================================" -ForegroundColor Cyan
}

function Stop-GemmaService {
    Write-Host "[+] Stopping Gemma4Service (Port $($State.GemmaPort))..." -ForegroundColor Yellow
    $p = Get-PortDetails -Port $State.GemmaPort
    Set-Service -Name "Gemma4Service" -StartupType Manual -ErrorAction SilentlyContinue
    if ($p) {
        & taskkill /F /PID $p.PID 2>$null | Out-Null
        Stop-Process -Id $p.PID -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $GemmaExe) { & $GemmaExe stop 2>$null | Out-Null }
    Stop-Service -Name "Gemma4Service" -Force -ErrorAction SilentlyContinue
    for ($i = 0; $i -lt 15; $i++) {
        $svc = Get-Service -Name "Gemma4Service" -ErrorAction SilentlyContinue
        if (-not $svc -or $svc.Status -eq "Stopped") { break }
        Start-Sleep -Milliseconds 500
    }
    Write-Host "[SUCCESS] Gemma4Service stopped." -ForegroundColor Green
}

function Stop-BonsaiService {
    Write-Host "[+] Stopping Bonsai2Service (Port $($State.BonsaiPort))..." -ForegroundColor Yellow
    $p = Get-PortDetails -Port $State.BonsaiPort
    Set-Service -Name "Bonsai2Service" -StartupType Manual -ErrorAction SilentlyContinue
    if ($p) {
        & taskkill /F /PID $p.PID 2>$null | Out-Null
        Stop-Process -Id $p.PID -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $BonsaiExe) { & $BonsaiExe stop 2>$null | Out-Null }
    Stop-Service -Name "Bonsai2Service" -Force -ErrorAction SilentlyContinue
    for ($i = 0; $i -lt 15; $i++) {
        $svc = Get-Service -Name "Bonsai2Service" -ErrorAction SilentlyContinue
        if (-not $svc -or $svc.Status -eq "Stopped") { break }
        Start-Sleep -Milliseconds 500
    }
    Write-Host "[SUCCESS] Bonsai2Service stopped." -ForegroundColor Green
}

function Start-GemmaService {
    for ($i = 0; $i -lt 10; $i++) {
        $svc = Get-Service -Name "Gemma4Service" -ErrorAction SilentlyContinue
        if (-not $svc -or $svc.Status -ne "StopPending") { break }
        Start-Sleep -Milliseconds 500
    }
    $p = Get-PortDetails -Port $State.GemmaPort
    if ($p) {
        $svcG = Get-Service -Name "Gemma4Service" -ErrorAction SilentlyContinue
        if (-not $svcG -or $svcG.Status -ne "Running") {
            & taskkill /F /PID $p.PID 2>$null | Out-Null
            Stop-Process -Id $p.PID -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
        }
    }
    Update-GemmaXml -StartMode "Automatic"
    Ensure-WinSWRegistered
    Set-Service -Name "Gemma4Service" -StartupType Automatic -ErrorAction SilentlyContinue
    Write-Host "[+] Starting Gemma4Service via WinSW on Port $($State.GemmaPort)..." -ForegroundColor Green
    Start-Service -Name "Gemma4Service" -ErrorAction SilentlyContinue
    $svcG = Get-Service -Name "Gemma4Service" -ErrorAction SilentlyContinue
    if (-not $svcG -or $svcG.Status -ne "Running") {
        & $GemmaExe start 2>$null | Out-Null
    }
    Wait-ForPortHealth -Port $State.GemmaPort -Label "Gemma 4 12B"
}

function Start-BonsaiService {
    for ($i = 0; $i -lt 10; $i++) {
        $svc = Get-Service -Name "Bonsai2Service" -ErrorAction SilentlyContinue
        if (-not $svc -or $svc.Status -ne "StopPending") { break }
        Start-Sleep -Milliseconds 500
    }
    $p = Get-PortDetails -Port $State.BonsaiPort
    if ($p) {
        $svcB = Get-Service -Name "Bonsai2Service" -ErrorAction SilentlyContinue
        if (-not $svcB -or $svcB.Status -ne "Running") {
            & taskkill /F /PID $p.PID 2>$null | Out-Null
            Stop-Process -Id $p.PID -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
        }
    }
    Update-BonsaiXml -StartMode "Automatic"
    Ensure-WinSWRegistered
    Set-Service -Name "Bonsai2Service" -StartupType Automatic -ErrorAction SilentlyContinue
    Write-Host "[+] Starting Bonsai2Service ($($State.BonsaiVariant), -c $($State.BonsaiCtx)) via WinSW on Port $($State.BonsaiPort)..." -ForegroundColor Green
    Start-Service -Name "Bonsai2Service" -ErrorAction SilentlyContinue
    $svcB = Get-Service -Name "Bonsai2Service" -ErrorAction SilentlyContinue
    if (-not $svcB -or $svcB.Status -ne "Running") {
        & $BonsaiExe start 2>$null | Out-Null
    }
    Wait-ForPortHealth -Port $State.BonsaiPort -Label "Ternary Bonsai 2 27B ($($State.BonsaiVariant))"
}

function Wait-ForPortHealth {
    param([int]$Port, [string]$Label)
    Write-Host "[+] Waiting for $Label on Port $Port to finish loading into GPU VRAM..." -ForegroundColor Cyan
    for ($i = 1; $i -le 20; $i++) {
        Start-Sleep -Seconds 1
        try {
            $r = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 1 -ErrorAction Stop
            if ($r.status -eq "ok") {
                Write-Host "[SUCCESS] $Label is ONLINE and READY on Port $Port!" -ForegroundColor Green
                return
            }
        } catch {}
    }
    Write-Host "[i] $Label service started on Port $Port (still initializing weights)." -ForegroundColor Yellow
}

function Pause-Console {
    Write-Host ""
    Write-Host "Press Enter to return to menu..." -ForegroundColor DarkGray
    $null = Read-Host
}

function Show-Menu {
    while ($true) {
        Show-Dashboard -Clear $true
        $ctxK = [math]::Round($State.BonsaiCtx / 1024)
        $ngStr = if ($State.BonsaiNgram) { "ON (m=7, 8-col MMVQ)" } else { "OFF" }
        Write-Host " EXCLUSIVE MODE (Runs ONLY One Service for 100% Dedicated GPU VRAM & Max Speed):" -ForegroundColor Yellow
        Write-Host "  [1] Run ONLY Gemma 4 12B           (Stops Bonsai 2, Starts Gemma4Service on Port $($State.GemmaPort))" -ForegroundColor Green
        Write-Host "  [2] Run ONLY Bonsai 2 27B (PTQ1_0) (Stops Gemma 4,  Starts Bonsai2Service PTQ1_0 on Port $($State.BonsaiPort))" -ForegroundColor Green
        Write-Host "  [3] Run ONLY Bonsai 2 27B (PQ2_0)  (Stops Gemma 4,  Starts Bonsai2Service PQ2_0  on Port $($State.BonsaiPort))" -ForegroundColor Green
        Write-Host ""
        Write-Host " INDIVIDUAL & DUAL SERVICE CONTROL (WinSW):" -ForegroundColor Yellow
        Write-Host "  [4] Start Gemma4Service            (Port $($State.GemmaPort))" -ForegroundColor Cyan
        Write-Host "  [5] Stop  Gemma4Service            (Port $($State.GemmaPort))" -ForegroundColor Cyan
        Write-Host "  [6] Start Bonsai2Service           (Port $($State.BonsaiPort) - $($State.BonsaiVariant))" -ForegroundColor Cyan
        Write-Host "  [7] Stop  Bonsai2Service           (Port $($State.BonsaiPort))" -ForegroundColor Cyan
        Write-Host "  [8] Run BOTH Services Simultaneously (Gemma 4 on $($State.GemmaPort) + Bonsai 2 on $($State.BonsaiPort))" -ForegroundColor Magenta
        Write-Host "  [9] Shut Down BOTH Services        (Free 100% GPU VRAM)" -ForegroundColor Red
        Write-Host ""
        Write-Host " TUNING, CONTEXT, N-GRAM & TOOLS:" -ForegroundColor Yellow
        Write-Host "  [K] Change Bonsai 2 Context Size   (Current: $($State.BonsaiCtx) / ${ctxK}K, KV=$($State.BonsaiKvType) -> 32K / 64K / 128K / 262K Max)" -ForegroundColor White
        Write-Host "  [N] Toggle N-Gram Speculative      (Current: $ngStr)" -ForegroundColor White
        Write-Host "  [P] Assign / Swap Ports for Gemma4Service ($($State.GemmaPort)) & Bonsai2Service ($($State.BonsaiPort))" -ForegroundColor White
        Write-Host "  [V] Toggle Bonsai 2 Variant        (Current: $($State.BonsaiVariant) -> PTQ1_0 5.95GB vs PQ2_0 7.21GB)" -ForegroundColor White
        Write-Host "  [B] Run GPU Speed Benchmark (llama-bench)" -ForegroundColor Gray
        Write-Host "  [C] Launch Interactive CLI Chat" -ForegroundColor Gray
        Write-Host "  [R] Refresh Status                 [0 / Q] Exit" -ForegroundColor Gray
        Write-Host ""

        $choice = (Read-Host "Select Option").Trim().ToUpper()
        switch ($choice) {
            "1" {
                Stop-BonsaiService
                Start-GemmaService
                Pause-Console
            }
            "2" {
                $State.BonsaiVariant = "PTQ1_0"
                if ($State.BonsaiCtx -lt 70000) {
                    $State.BonsaiCtx = 70000
                }
                $State.BonsaiKvType = "f16"
                Save-Config
                Stop-GemmaService
                Stop-BonsaiService
                Start-BonsaiService
                Pause-Console
            }
            "3" {
                $State.BonsaiVariant = "PQ2_0"
                if ($State.BonsaiCtx -gt 48000) {
                    Write-Host "[!] Note: PQ2_0 uses 7.21 GB VRAM. Auto-capping context to 48,000 (f16) to fit 12 GB VRAM..." -ForegroundColor Yellow
                    $State.BonsaiCtx = 48000
                }
                $State.BonsaiKvType = "f16"
                Save-Config
                Stop-GemmaService
                Stop-BonsaiService
                Start-BonsaiService
                Pause-Console
            }
            "4" { Start-GemmaService; Pause-Console }
            "5" { Stop-GemmaService; Pause-Console }
            "6" { Start-BonsaiService; Pause-Console }
            "7" { Stop-BonsaiService; Pause-Console }
            "8" {
                if ($State.GemmaPort -eq $State.BonsaiPort) {
                    Write-Host "[!] Both services were set to Port $($State.GemmaPort). Assigning Gemma=8081, Bonsai=8080..." -ForegroundColor Yellow
                    $State.GemmaPort = 8081
                    $State.BonsaiPort = 8080
                    Save-Config
                }
                Start-GemmaService
                Start-BonsaiService
                Pause-Console
            }
            "9" {
                Stop-GemmaService
                Stop-BonsaiService
                Get-Process -Name "llama-server" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                Write-Host "[SUCCESS] Both services stopped and 100% VRAM freed." -ForegroundColor Green
                Pause-Console
            }
            "K" {
                Write-Host ""
                Write-Host "Select Bonsai 2 Context Window Size (RTX 4070 Ti 12 GB VRAM):" -ForegroundColor Cyan
                Write-Host "  [1]  32,768 ( 32K)  - f16 KV Cache (~2.0 GiB KV VRAM - Fast & Stable for both PQ2_0 and PTQ1_0)"
                Write-Host "  [2]  48,000 ( 48K)  - f16 KV Cache (~3.0 GiB KV VRAM - Max safe limit for PQ2_0 7.21GB)"
                Write-Host "  [3]  65,536 ( 64K)  - f16 KV Cache (~4.1 GiB KV VRAM - Standard 64K for PTQ1_0 5.95GB)"
                Write-Host "  [4]  70,000 ( 70K)  - f16 KV Cache (~4.38 GiB KV VRAM - Recommended for DeepSeek Harness on PTQ1_0)"
                Write-Host "  [5]  72,000 ( 72K)  - f16 KV Cache (~4.50 GiB KV VRAM - Maximum tested VRAM limit for PTQ1_0)"
                Write-Host "  [C] Custom Context  - Type any exact token number (e.g. 68000, 70000)"
                $cSel = (Read-Host "Choose [1-5 or C]").Trim().ToUpper()
                switch ($cSel) {
                    "1" { $State.BonsaiCtx = 32768;  $State.BonsaiKvType = "f16" }
                    "2" { $State.BonsaiCtx = 48000;  $State.BonsaiKvType = "f16" }
                    "3" { $State.BonsaiCtx = 65536;  $State.BonsaiKvType = "f16" }
                    "4" { $State.BonsaiCtx = 70000;  $State.BonsaiKvType = "f16" }
                    "5" { $State.BonsaiCtx = 72000;  $State.BonsaiKvType = "f16" }
                    "C" {
                        $cVal = Read-Host "Enter custom context size (e.g. 65600, 68000, 70000)"
                        if ($cVal -match '^\d+$' -and [int]$cVal -gt 1024) {
                            $State.BonsaiCtx = [int]$cVal
                            $State.BonsaiKvType = "f16"
                            Write-Host "[i] Custom context set to $($State.BonsaiCtx) with pure f16 KV cache." -ForegroundColor Cyan
                        } else {
                            Write-Host "[!] Invalid number. Keeping $($State.BonsaiCtx)." -ForegroundColor Yellow
                        }
                    }
                }
                Save-Config
                Update-BonsaiXml
                Write-Host "[SUCCESS] Updated Bonsai2Service context to $($State.BonsaiCtx) (KV=$($State.BonsaiKvType))!" -ForegroundColor Green
                Write-Host "[i] Select [2] or [3] from the menu to restart Bonsai 2 with the new context." -ForegroundColor Yellow
                Pause-Console
            }
            "N" {
                $State.BonsaiNgram = -not $State.BonsaiNgram
                Save-Config
                Update-BonsaiXml
                $draftFile = "Ternary-Bonsai-27B-dspark-Q4_1.gguf"
                $hasDraft  = Test-Path (Join-Path $ModelsDir $draftFile)
                $st = if ($State.BonsaiNgram -and $hasDraft) { "ENABLED with DSpark Drafter (-md $draftFile --spec-type draft-dspark for 2x-3x speed)" }
                      elseif ($State.BonsaiNgram) { "ENABLED (ngram-simple - note: download DSpark drafter via download_models.ps1 for best speed)" }
                      else { "DISABLED" }
                Write-Host "[SUCCESS] Speculative Decoding is now $st." -ForegroundColor Green
                Write-Host "[i] Select [2] or [3] from the menu to restart Bonsai2Service." -ForegroundColor Yellow
                Pause-Console
            }
            "P" {
                Write-Host ""
                Write-Host "Quick Preset: Type 'SWAP' to swap ports ($($State.GemmaPort) <-> $($State.BonsaiPort)), or enter custom port numbers:" -ForegroundColor Cyan
                $inG = (Read-Host "Enter Port for Gemma4Service (Current: $($State.GemmaPort), or type SWAP)").Trim().ToUpper()
                if ($inG -eq "SWAP") {
                    $tmp = $State.GemmaPort
                    $State.GemmaPort = $State.BonsaiPort
                    $State.BonsaiPort = $tmp
                    Write-Host "[+] Swapped Ports! Gemma4Service = $($State.GemmaPort), Bonsai2Service = $($State.BonsaiPort)" -ForegroundColor Green
                } else {
                    if ($inG -match "^\d+$") { $State.GemmaPort = [int]$inG }
                    $inB = (Read-Host "Enter Port for Bonsai2Service (Current: $($State.BonsaiPort))").Trim()
                    if ($inB -match "^\d+$") { $State.BonsaiPort = [int]$inB }
                }
                Save-Config
                Update-GemmaXml
                Update-BonsaiXml
                Write-Host "[SUCCESS] Saved port configuration to Gemma4Service.xml and Bonsai2Service.xml!" -ForegroundColor Green
                Write-Host "[i] Restart any running service from the menu for the new port to take effect." -ForegroundColor Yellow
                Pause-Console
            }
            "V" {
                $State.BonsaiVariant = if ($State.BonsaiVariant -eq "PTQ1_0") { "PQ2_0" } else { "PTQ1_0" }
                Save-Config
                Update-BonsaiXml
                Write-Host "[SUCCESS] Switched Bonsai2Service variant to $($State.BonsaiVariant)." -ForegroundColor Green
                Pause-Console
            }
            "B" {
                $sel = (Read-Host "Benchmark [1] Gemma 4 12B, [2] Bonsai 2 PTQ1_0, [3] Bonsai 2 PQ2_0").Trim()
                $file = switch ($sel) {
                    "1" { Join-Path $ModelsDir "gemma-4-12B-it-Q4_K_M.gguf" }
                    "3" { Join-Path $ModelsDir "Ternary-Bonsai-2-27B-PQ2_0.gguf" }
                    default { Join-Path $ModelsDir "Ternary-Bonsai-2-27B-PTQ1_0.gguf" }
                }
                & $LlamaBench -m $file -p 512 -n 128 -ngl 99 -fa on -r 3
                Pause-Console
            }
            "C" {
                $sel = (Read-Host "Chat with [1] Gemma 4 12B, [2] Bonsai 2 PTQ1_0, [3] Bonsai 2 PQ2_0").Trim()
                $file = switch ($sel) {
                    "1" { Join-Path $ModelsDir "gemma-4-12B-it-Q4_K_M.gguf" }
                    "3" { Join-Path $ModelsDir "Ternary-Bonsai-2-27B-PQ2_0.gguf" }
                    default { Join-Path $ModelsDir "Ternary-Bonsai-2-27B-PTQ1_0.gguf" }
                }
                & $LlamaCli -m $file -ngl 99 -c 16384 -fa on -cnv
                Pause-Console
            }
            "R" { continue }
            "0" { return }
            "Q" { return }
            "EXIT" { return }
        }
    }
}

switch ($Action.ToLower()) {
    "status" { Show-Dashboard -Clear $false }
    "stopall" { Stop-GemmaService; Stop-BonsaiService }
    default  { Show-Menu }
}
