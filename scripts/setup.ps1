# scripts/setup.ps1 — Velociraptor Artifact Workspace Setup (Windows)
# Usage: .\setup.ps1 -Phase prereqs | .\setup.ps1 -Phase finalize
# Called by /setup slash command (Claude orchestrates between phases)
#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('prereqs', 'finalize')]
    [string]$Phase
)

$ErrorActionPreference = 'Stop'

$WorkspaceRoot = Split-Path -Parent $PSScriptRoot
$BinDir        = Join-Path $WorkspaceRoot 'bin'
$ConfigDir     = Join-Path $WorkspaceRoot 'config'
$VenvDir       = Join-Path $WorkspaceRoot 'venv'
$CustomDir     = Join-Path $WorkspaceRoot 'custom'

# ─── Helpers ──────────────────────────────────────────────────────────────────

function Write-Info    { param([string]$Msg) Write-Host "[INFO]  $Msg" }
function Write-Success { param([string]$Msg) Write-Host "[OK]    $Msg" }
function Write-Fail    { param([string]$Msg) Write-Error "[ERROR] $Msg"; exit 1 }

# ─── Phase: prereqs ───────────────────────────────────────────────────────────

function Invoke-PhasePrereqs {
    Write-Host "=== Phase 1: Prerequisites ==="

    # Platform detection — Windows only for this script
    $arch = $env:PROCESSOR_ARCHITECTURE
    switch ($arch) {
        'AMD64' { $VlArch = 'amd64' }
        'ARM64' { $VlArch = 'arm64' }
        default { Write-Fail "Unsupported architecture: $arch." }
    }
    $VlOs = 'windows'
    Write-Success "Platform detected: $VlOs/$VlArch"

    # Python 3.8+ check
    $PythonBin = $null
    foreach ($candidate in @('python', 'python3')) {
        try {
            $ver = & $candidate --version 2>&1
            if ($ver -match 'Python (\d+)\.(\d+)') {
                $major = [int]$Matches[1]
                $minor = [int]$Matches[2]
                if ($major -gt 3 -or ($major -eq 3 -and $minor -ge 8)) {
                    $PythonBin = $candidate
                    Write-Success "Python $major.$minor found"
                    break
                }
            }
        } catch { }
    }
    if (-not $PythonBin) {
        Write-Fail "Python 3.8+ not found. Install Python 3.8 or later from https://python.org and re-run /setup."
    }

    # Virtual environment
    $VenvPython = Join-Path $VenvDir 'Scripts\python.exe'
    $VenvPip    = Join-Path $VenvDir 'Scripts\pip.exe'

    if (Test-Path $VenvPython) {
        Write-Info "Virtual environment exists — verifying pyvelociraptor..."
        $importOk = & $VenvPython -c "import pyvelociraptor" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Success "pyvelociraptor is importable"
        } else {
            Write-Info "pyvelociraptor missing or broken — reinstalling..."
            & $VenvPip install --quiet pyvelociraptor
            if ($LASTEXITCODE -ne 0) { Write-Fail "Failed to install pyvelociraptor. Check your internet connection." }
            Write-Success "pyvelociraptor installed"
        }
    } else {
        Write-Info "Creating virtual environment..."
        & $PythonBin -m venv $VenvDir
        if ($LASTEXITCODE -ne 0) { Write-Fail "Failed to create virtual environment at $VenvDir." }
        Write-Info "Installing pyvelociraptor..."
        & $VenvPip install --quiet --upgrade pip pyvelociraptor
        if ($LASTEXITCODE -ne 0) { Write-Fail "Failed to install pyvelociraptor. Check your internet connection." }
        Write-Success "Virtual environment created and pyvelociraptor installed"
    }

    # Velociraptor binary
    New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
    $Binary = Join-Path $BinDir 'velociraptor.exe'

    if (Test-Path $Binary) {
        try {
            $verOutput = & $Binary version 2>&1
            $installedVer = ($verOutput | Select-String -Pattern 'v\d+\.\d+\.\d+').Matches[0].Value
            Write-Success "Velociraptor binary found: $installedVer"
            return
        } catch { }
    }

    Write-Info "Fetching latest stable Velociraptor release tag..."

    $ApiUrl = 'https://api.github.com/repos/Velocidex/velociraptor/releases'
    try {
        $releases = Invoke-RestMethod -Uri $ApiUrl -UseBasicParsing
    } catch {
        Write-Fail "Failed to fetch release list from GitHub. Check your internet connection."
    }

    # Find latest stable (non-RC) release
    $latestTag = $null
    foreach ($release in $releases) {
        if ($release.tag_name -notmatch '-rc') {
            $latestTag = $release.tag_name
            break
        }
    }
    if (-not $latestTag) { Write-Fail "Could not determine latest stable release tag." }

    $AssetName   = "velociraptor-${latestTag}-${VlOs}-${VlArch}.exe"
    $DownloadUrl = "https://github.com/Velocidex/velociraptor/releases/download/${latestTag}/${AssetName}"

    Write-Info "Downloading $AssetName..."
    try {
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $Binary -UseBasicParsing
    } catch {
        Write-Fail "Download failed for $DownloadUrl. Check network access or download manually from https://docs.velociraptor.app/downloads/ and place the binary at $Binary."
    }

    # Verify binary executes
    try {
        $verOutput = & $Binary version 2>&1
        $installedVer = ($verOutput | Select-String -Pattern 'v\d+\.\d+\.\d+').Matches[0].Value
        Write-Success "Velociraptor $installedVer downloaded and verified"
    } catch {
        $sha256 = (Get-FileHash -Algorithm SHA256 $Binary).Hash
        Write-Fail "Binary downloaded but failed to execute. SHA-256: $sha256`nPlease verify the download at https://docs.velociraptor.app/downloads/ and replace $Binary manually."
    }

    Write-Host ""
    Write-Host "=== Phase 1 complete ==="
    Write-Host "Next: Claude will generate config/server.config.yaml (if not present), then run -Phase finalize."
}

# ─── Phase: finalize ──────────────────────────────────────────────────────────

function Invoke-PhaseFinalize {
    Write-Host "=== Phase 2: Finalize ==="

    $ServerConfig = Join-Path $ConfigDir 'server.config.yaml'
    $ApiConfig    = Join-Path $ConfigDir 'api.config.yaml'
    $Binary       = Join-Path $BinDir 'velociraptor.exe'

    # API config extraction
    if (Test-Path $ApiConfig) {
        Write-Success "API config already exists: $ApiConfig"
    } else {
        if (-not (Test-Path $ServerConfig)) {
            Write-Fail "Server config not found at $ServerConfig. Run phase prereqs and let Claude generate the config first."
        }
        Write-Info "Extracting API client config from server config..."
        & $Binary --config "$ServerConfig" config api_client --name workspace-client --role analyst "$ApiConfig"
        if ($LASTEXITCODE -ne 0) { Write-Fail "Failed to extract API config. Verify server config is valid." }
        Write-Success "API config created: $ApiConfig"
    }

    # Custom artifact directories
    Write-Info "Creating custom artifact directories..."
    @('Windows', 'MacOS', 'Linux', 'Generic', 'Server') | ForEach-Object {
        New-Item -ItemType Directory -Force -Path (Join-Path $CustomDir $_) | Out-Null
    }
    Write-Success "Custom artifact directories ready"

    # Health summary
    Write-Host ""
    Write-Host "=== Health Check ==="

    $BinaryPath = Join-Path $BinDir 'velociraptor.exe'
    if (Test-Path $BinaryPath) {
        try {
            $verOutput = & $BinaryPath version 2>&1
            $ver = ($verOutput | Select-String -Pattern 'v\d+\.\d+\.\d+').Matches[0].Value
            Write-Host "  [OK] Velociraptor binary: $ver"
        } catch {
            Write-Host "  [!!] Velociraptor binary: present but failed to execute"
        }
    } else {
        Write-Host "  [!!] Velociraptor binary: missing"
    }

    if (Test-Path $ServerConfig) {
        Write-Host "  [OK] Server config: $ServerConfig"
    } else {
        Write-Host "  [!!] Server config: missing"
    }

    if (Test-Path $ApiConfig) {
        Write-Host "  [OK] API config: $ApiConfig"
    } else {
        Write-Host "  [!!] API config: missing"
    }

    $VenvPython = Join-Path $VenvDir 'Scripts\python.exe'
    if (Test-Path $VenvPython) {
        $importOk = & $VenvPython -c "import pyvelociraptor" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [OK] Python venv + pyvelociraptor: ready"
        } else {
            Write-Host "  [!!] Python venv + pyvelociraptor: pyvelociraptor not importable"
        }
    } else {
        Write-Host "  [!!] Python venv + pyvelociraptor: not configured"
    }

    Write-Host ""
    Write-Host "=== Phase 2 complete ==="
    Write-Host "Setup is done. Use /new to create your first artifact."
}

# ─── Entry point ──────────────────────────────────────────────────────────────

switch ($Phase) {
    'prereqs'  { Invoke-PhasePrereqs }
    'finalize' { Invoke-PhaseFinalize }
}
