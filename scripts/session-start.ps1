# scripts/session-start.ps1 — Velociraptor Artifact Workspace SessionStart Hook (Windows)
# Must complete in < 1 second. Called automatically at the start of each session.
# Outputs JSON: systemMessage (user-visible) + additionalContext (Claude context)
#Requires -Version 5.1

$WorkspaceRoot  = Split-Path -Parent $PSScriptRoot
$BinDir         = Join-Path $WorkspaceRoot 'bin'
$ConfigDir      = Join-Path $WorkspaceRoot 'config'
$VenvDir        = Join-Path $WorkspaceRoot 'venv'

$ServerConfig   = Join-Path $ConfigDir 'server.config.yaml'
$ApiConfig      = Join-Path $ConfigDir 'api.config.yaml'
$SessionState   = Join-Path $ConfigDir '.session-state'
$Binary         = Join-Path $BinDir 'velociraptor.exe'

# ─── Health checks ────────────────────────────────────────────────────────────

# 1. Binary present + version
$StatusBinary = ''
if (Test-Path $Binary) {
    try {
        $verOutput = & $Binary version 2>&1
        $ver = ($verOutput | Select-String -Pattern 'v\d+\.\d+\.\d+').Matches[0].Value
        $StatusBinary = "[OK] Velociraptor $ver"
    } catch {
        $StatusBinary = "[!!] Binary present but not executable"
    }
} else {
    $StatusBinary = "[!!] Binary missing -- run /setup"
}

# 2. Server config exists
$StatusServerConfig = if (Test-Path $ServerConfig) {
    "[OK] Server config"
} else {
    "[!!] No server config -- run /setup"
}

# 3. API config exists
$StatusApiConfig = if (Test-Path $ApiConfig) {
    "[OK] API config"
} else {
    "[!!] No API config -- run /setup"
}

# 4. Python venv + pyvelociraptor importable
$VenvPython = Join-Path $VenvDir 'Scripts\python.exe'
$StatusPython = ''
if (Test-Path $VenvPython) {
    $importResult = & $VenvPython -c "import pyvelociraptor" 2>&1
    if ($LASTEXITCODE -eq 0) {
        $StatusPython = "[OK] Python ready"
    } else {
        $StatusPython = "[!!] Python not configured -- run /setup"
    }
} else {
    $StatusPython = "[!!] Python not configured -- run /setup"
}

# 5. Local server reachable
$GuiPort = 8889
if (Test-Path $ServerConfig) {
    $content = Get-Content $ServerConfig -Raw
    if ($content -match 'bind_port:\s*(\d+)') {
        $GuiPort = [int]$Matches[1]
    }
}

$StatusServer = ''
try {
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        $null = Invoke-WebRequest -Uri "https://localhost:${GuiPort}/app/index.html" `
            -TimeoutSec 1 `
            -UseBasicParsing `
            -SkipCertificateCheck `
            -ErrorAction Stop
    } else {
        $prevCallback = [System.Net.ServicePointManager]::ServerCertificateValidationCallback
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
        try {
            $null = Invoke-WebRequest -Uri "https://localhost:${GuiPort}/app/index.html" `
                -TimeoutSec 1 `
                -UseBasicParsing `
                -ErrorAction Stop
        } finally {
            [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $prevCallback
        }
    }
    $StatusServer = "[OK] Server running ($GuiPort)"
} catch {
    $StatusServer = "[ ] Server stopped"
}

# ─── Session state + contextual nudge ────────────────────────────────────────

$Nudge           = ''
$ActiveArtifact  = ''

if (Test-Path $SessionState) {
    $stateContent = Get-Content $SessionState -Raw

    if ($stateContent -match 'active_artifact:\s*(.+)') {
        $ActiveArtifact = $Matches[1].Trim().Trim('"')
    }
    $UpdatedStr = ''
    if ($stateContent -match 'updated:\s*(.+)') {
        $UpdatedStr = $Matches[1].Trim().Trim('"')
    }

    if ($ActiveArtifact -and $ActiveArtifact -ne 'null' -and $ActiveArtifact -ne '~') {
        $AgeSeconds = 9999
        if ($UpdatedStr) {
            try {
                $StateTime  = [datetime]::Parse($UpdatedStr)
                $AgeSeconds = [int]([datetime]::UtcNow - $StateTime.ToUniversalTime()).TotalSeconds
            } catch { }
        }

        if ($AgeSeconds -lt 3600) {
            $Nudge = "Resuming: $ActiveArtifact -- use /check or /test to continue"
        } else {
            $AgeHours = [int]($AgeSeconds / 3600)
            $AgeLabel = if ($AgeHours -lt 24) { "${AgeHours}h ago" } else { "$([int]($AgeHours/24))d ago" }
            $Nudge = "Previous artifact: $ActiveArtifact ($AgeLabel) -- /next to start fresh or /check to continue"
        }
    }
}

# If no session state or no active artifact, nudge based on workspace readiness
if (-not $Nudge) {
    if ($StatusBinary -like '[OK]*' -and $StatusServerConfig -like '[OK]*') {
        $Nudge = "Run /new to create your first artifact"
    } else {
        $Nudge = "Run /setup to configure the workspace"
    }
}

# ─── Build user-visible message ──────────────────────────────────────────────

$Display = @"
Velociraptor Artifact Workspace

Getting started:
  /setup  -- First time? Start here to configure the workspace
  /new    -- Create a new artifact -- describe what you want to collect

Once you're working:
  /check  -- Validate syntax and reformat your artifact
  /test   -- Execute artifact locally or against a server
  /push   -- Deploy artifact to your Velociraptor server
  /next   -- Switch to a different artifact

Status: $StatusBinary
        $StatusServerConfig
        $StatusApiConfig
        $StatusPython
        $StatusServer

--> $Nudge
"@

# ─── Build Claude context ────────────────────────────────────────────────────

$Context = "Velociraptor Artifact Workspace — startup hook success | Status: $StatusBinary | $StatusServerConfig | $StatusApiConfig | $StatusPython | $StatusServer"
if ($ActiveArtifact -and $ActiveArtifact -ne 'null' -and $ActiveArtifact -ne '~') {
    $Context += " | Active artifact: $ActiveArtifact"
}

# ─── Output JSON ──────────────────────────────────────────────────────────────

$output = @{
    systemMessage = $Display
    hookSpecificOutput = @{
        hookEventName = "SessionStart"
        additionalContext = $Context
    }
}

$output | ConvertTo-Json -Depth 3 -Compress
