# ============================================================
# HAPPYMANCING: WINDOWS 10 GCRD DEPLOYMENT
# Role      : Deployment Commander
# Doctrine  : Simplicity - Efficiency - Reliability
# Essence   : Straightforward and functional deployment
# ============================================================

param(
    [string]$GateSecret  # Optional: pass as -GateSecret or via env:HappyMancing_Access_Token
)

# ============================================================
# CORE DIRECTIVE: SYSTEM INTEGRITY
# ============================================================
$ErrorActionPreference = "Stop"

# ============================================================
# TIMESTAMP GENERATOR
# ============================================================
function Timestamp { (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") }

# ============================================================
# LOGGING FUNCTION
# ============================================================
function Log($msg)  { Write-Host "[HAPPYMANCING $(Timestamp)] $msg" }

# ============================================================
# ERROR HANDLER
# ============================================================
function Fail($msg) { Write-Error "[HAPPYMANCING-ERROR $(Timestamp)] $msg"; Exit 1 }

# ============================================================
# SIMPLE TEXT VALIDATION
# ============================================================
function Validate-Secret([Parameter(Mandatory)] [string]$Text) {
    return $Text -eq "LISTEN2KAEL"
}

# ============================================================
# INITIATION SEQUENCE
# ============================================================
$now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host @"
------------------------------------------------------------
                HAPPYMANCING // GCRD ONLINE
------------------------------------------------------------
  STATUS    : Deployment initializing
  TIME      : $now
  PROFILE   : Windows 10 GCRD Instance
  DOCTRINE  : Simplicity - Efficiency - Reliability
------------------------------------------------------------
"@

# ============================================================
# CONTEXT SNAPSHOT
# ============================================================
$RUNNER_ENV     = $env:RUNNER_ENV
$RAW_CODE       = $env:RAW_CODE
$PIN_INPUT      = $env:PIN_INPUT
$RETRIES_INPUT  = $env:RETRIES_INPUT

# ============================================================
# ACCESS CONTROL: SIMPLE TEXT VALIDATION
# ============================================================
$GATE_SECRET = if ($PSBoundParameters.ContainsKey('GateSecret')) { $GateSecret } else { $env:HappyMancing_Access_Token }

if ($GATE_SECRET) { Write-Host "::add-mask::$GATE_SECRET" }

if (-not $GATE_SECRET -or [string]::IsNullOrWhiteSpace($GATE_SECRET)) {
    Fail "Access Denied: Missing HappyMancing_Access_Token. Configure repository secret and retry."
}

if (-not (Validate-Secret $GATE_SECRET)) {
    Fail "Access Denied: Token validation failed. Expected: LISTEN2KAEL"
}
Log "Access Control: Validation successful."

# ============================================================
# DOWNLOAD GCRD INSTALLER
# ============================================================
try {
    Log "Downloading Chrome Remote Desktop installer..."
    $downloadUrl = "https://dl.google.com/edgedl/chrome-remote-desktop/chromeremotedesktophost.msi"
    $downloadPath = Join-Path $env:USERPROFILE "Downloads\crdhost.msi"
    
    # Create Downloads folder if not exists
    $downloadsDir = Split-Path $downloadPath -Parent
    if (-not (Test-Path $downloadsDir)) {
        New-Item -ItemType Directory -Path $downloadsDir -Force | Out-Null
    }
    
    Invoke-WebRequest -Uri $downloadUrl -OutFile $downloadPath -UseBasicParsing
    Log "GCRD installer downloaded successfully to $downloadPath"
} catch {
    Fail "Failed to download GCRD installer: $_"
}

# ============================================================
# PRIMARY DEPLOYMENT: GCRD SETUP ONLY
# ============================================================

try {
    Log "Phase GCRD - Initializing Google Chrome Remote Desktop (~120s)"
    Invoke-WebRequest "https://gitlab.com/Shahzaib-YT/enigmano-win10-gcrd-instance/-/raw/main/GCRD-setup.ps1" -OutFile GCRD-setup.ps1
    .\GCRD-setup.ps1
    Log "Phase GCRD - Remote desktop setup completed successfully."
} catch { Fail "Phase GCRD - Setup failure. $_" }

# ============================================================
# DATA FOLDER CREATION
# ============================================================
try {
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $dataFolderPath = Join-Path $desktopPath "Data"

    if (-not (Test-Path $dataFolderPath)) {
        New-Item -Path $dataFolderPath -ItemType Directory | Out-Null
        Log "Data folder created at $dataFolderPath"
    } else {
        Log "Data folder already exists."
    }
} catch { Fail "Data folder creation failed. $_" }

# ============================================================
# EXECUTION WINDOW
# ============================================================
$totalMinutes = 2000
$startTime    = Get-Date
$endTime      = $startTime.AddMinutes($totalMinutes)

function ClampMinutes([TimeSpan]$ts) {
    $mins = [math]::Round($ts.TotalMinutes, 1)
    if ($mins -lt 0) { return 0 }
    return $mins
}

while ((Get-Date) -lt $endTime) {
    $now       = Get-Date
    $elapsed   = [math]::Round(($now - $startTime).TotalMinutes, 1)
    $remaining = ClampMinutes ($endTime - $now)
    Log "Operational Uptime ${elapsed}m | Remaining ${remaining}m"
    Start-Sleep -Seconds ((Get-Random -Minimum 300 -Maximum 800))
}

Log "Mission duration ${totalMinutes}m achieved. Preparing for shutdown."

# ============================================================
# TERMINATION SEQUENCE
# ============================================================
Log "Initiating shutdown protocol."

if ($RUNNER_ENV -eq "self-hosted") {
    Stop-Computer -Force
} else {
    Log "Hosted environment detected. Exiting gracefully."
    Exit
}
