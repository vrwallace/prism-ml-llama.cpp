# ==============================================================================
# Model Downloader for Ternary Bonsai 2 27B & Gemma 4 12B (Windows / PowerShell)
# Downloads GGUF model weights and vision projector directly to .\models\
# ==============================================================================

param (
    [Parameter(Position=0, Mandatory=$false)]
    [string]$Selection = ""
)

$ScriptDir  = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }
$ModelsDir  = Join-Path $ScriptDir "models"

if (-not (Test-Path $ModelsDir)) {
    New-Item -ItemType Directory -Path $ModelsDir -Force | Out-Null
}

function Download-ModelFile {
    param (
        [string]$Url,
        [string]$FileName,
        [string]$Description
    )

    $targetPath = Join-Path $ModelsDir $FileName
    if (Test-Path $targetPath) {
        $size = (Get-Item $targetPath).Length
        if ($size -gt 100000000) {
            Write-Host "[OK] $Description already exists ($([math]::Round($size/1GB, 2)) GB). Skipping." -ForegroundColor Green
            return
        }
    }

    Write-Host "[+] Downloading $Description..." -ForegroundColor Cyan
    Write-Host "    Source : $Url" -ForegroundColor Gray
    Write-Host "    Target : $targetPath" -ForegroundColor Gray

    # Prefer curl.exe if available for fast multi-threaded/resumable downloads with native progress bar
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
        & curl.exe -L -C - --progress-bar -o "$targetPath" "$Url"
    } else {
        Start-BitsTransfer -Source $Url -Destination $targetPath -DisplayName "Downloading $FileName"
    }

    if (Test-Path $targetPath) {
        $finalSize = (Get-Item $targetPath).Length
        Write-Host "[SUCCESS] Downloaded $FileName ($([math]::Round($finalSize/1GB, 2)) GB)!" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] Failed to download $FileName" -ForegroundColor Red
    }
    Write-Host ""
}

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "   Ternary Bonsai 2 & Gemma 4 Model Downloader (Windows / PowerShell)           " -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "Target Folder: $ModelsDir`n" -ForegroundColor Yellow

if (-not $Selection) {
    Write-Host "Select models to download:" -ForegroundColor White
    Write-Host "  [1] Bonsai 2 27B PTQ1_0  (5.95 GB - Lowest VRAM, Recommended for RTX 4070 Ti 12GB)" -ForegroundColor Cyan
    Write-Host "  [2] Bonsai 2 27B PQ2_0   (7.21 GB - Fastest Prompt/Decode, Fits 12GB VRAM at 48K ctx)" -ForegroundColor Cyan
    Write-Host "  [3] Bonsai 2 Vision Proj (0.63 GB - Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf for Vision)" -ForegroundColor Cyan
    Write-Host "  [4] Gemma 4 12B Q4_K_M   (7.66 GB - Google Gemma 4 IT)" -ForegroundColor Cyan
    Write-Host "  [5] DSpark Drafter Q4_1  (1.95 GB - Ternary-Bonsai-27B-dspark-Q4_1.gguf for 2x-3x Speculative Speed)" -ForegroundColor Cyan
    Write-Host "  [A] Download ALL Recommended Files (PTQ1_0 + PQ2_0 + Vision Projector + DSpark Drafter)" -ForegroundColor Magenta
    Write-Host "  [Q] Quit" -ForegroundColor DarkGray
    Write-Host ""
    $Selection = (Read-Host "Choose [1/2/3/4/5/A/Q]").Trim().ToUpper()
}

switch ($Selection.ToUpper()) {
    "1" {
        Download-ModelFile -Url "https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-GGUF/resolve/main/Ternary-Bonsai-2-27B-PTQ1_0.gguf" `
                           -FileName "Ternary-Bonsai-2-27B-PTQ1_0.gguf" `
                           -Description "Ternary-Bonsai-2-27B PTQ1_0 (5.95 GB)"
    }
    "2" {
        Download-ModelFile -Url "https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-GGUF/resolve/main/Ternary-Bonsai-2-27B-PQ2_0.gguf" `
                           -FileName "Ternary-Bonsai-2-27B-PQ2_0.gguf" `
                           -Description "Ternary-Bonsai-2-27B PQ2_0 (7.21 GB)"
    }
    "3" {
        Download-ModelFile -Url "https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-GGUF/resolve/main/Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf" `
                           -FileName "Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf" `
                           -Description "Ternary-Bonsai-2-27B Multimodal Vision Projector Q8_0 (0.63 GB)"
    }
    "4" {
        Download-ModelFile -Url "https://huggingface.co/bartowski/gemma-4-12B-it-GGUF/resolve/main/gemma-4-12B-it-Q4_K_M.gguf" `
                           -FileName "gemma-4-12B-it-Q4_K_M.gguf" `
                           -Description "Gemma 4 12B IT Q4_K_M (7.66 GB)"
    }
    "5" {
        Download-ModelFile -Url "https://huggingface.co/prism-ml/Ternary-Bonsai-27B-gguf/resolve/main/Ternary-Bonsai-27B-dspark-Q4_1.gguf" `
                           -FileName "Ternary-Bonsai-27B-dspark-Q4_1.gguf" `
                           -Description "Ternary-Bonsai-27B DSpark Drafter Q4_1 (1.95 GB)"
    }
    "A" {
        Download-ModelFile -Url "https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-GGUF/resolve/main/Ternary-Bonsai-2-27B-PTQ1_0.gguf" `
                           -FileName "Ternary-Bonsai-2-27B-PTQ1_0.gguf" `
                           -Description "Ternary-Bonsai-2-27B PTQ1_0 (5.95 GB)"

        Download-ModelFile -Url "https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-GGUF/resolve/main/Ternary-Bonsai-2-27B-PQ2_0.gguf" `
                           -FileName "Ternary-Bonsai-2-27B-PQ2_0.gguf" `
                           -Description "Ternary-Bonsai-2-27B PQ2_0 (7.21 GB)"

        Download-ModelFile -Url "https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-GGUF/resolve/main/Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf" `
                           -FileName "Ternary-Bonsai-2-27B-mmproj-Q8_0.gguf" `
                           -Description "Ternary-Bonsai-2-27B Multimodal Vision Projector Q8_0 (0.63 GB)"

        Download-ModelFile -Url "https://huggingface.co/prism-ml/Ternary-Bonsai-27B-gguf/resolve/main/Ternary-Bonsai-27B-dspark-Q4_1.gguf" `
                           -FileName "Ternary-Bonsai-27B-dspark-Q4_1.gguf" `
                           -Description "Ternary-Bonsai-27B DSpark Drafter Q4_1 (1.95 GB)"
    }
    Default {
        Write-Host "Exiting downloader." -ForegroundColor Yellow
    }
}

Write-Host "Models ready in: $ModelsDir" -ForegroundColor Green
