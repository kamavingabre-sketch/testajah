# ============================================================
# HAPPYMANCING: WINDOWS 10 GCRD DEPLOYMENT PROTOCOL
# Role      : Deployment Manager
# Doctrine  : Simplicity - Efficiency - Reliability
# Essence   : Simple and effective deployment
# ============================================================

param(
    [string]$GateSecret  # Optional: pass as -GateSecret or via env:HappyMancing_Access_Token
)

# ============================================================
# CORE DIRECTIVE: SYSTEM INTEGRITY
# Fail immediately on unhandled errors.
# ============================================================
$ErrorActionPreference = "Stop"

# ============================================================
# TIMESTAMP GENERATOR
# Generates unified timestamps for event tracking.
# ============================================================
function Timestamp { (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") }

# ============================================================
# LOGGING FUNCTION
# Each message passes through the HappyMancing console.
# ============================================================
function Log($msg)  { Write-Host "[HAPPYMANCING $(Timestamp)] $msg" }

# ============================================================
# ERROR HANDLER
# All unrecoverable faults converge here.
# ============================================================
function Fail($msg) { Write-Error "[HAPPYMANCING-ERROR $(Timestamp)] $msg"; Exit 1 }

# ============================================================
# SIMPLE ACCESS VALIDATION
# Basic text-based authentication.
# ============================================================
$GATE_SECRET = if ($PSBoundParameters.ContainsKey('GateSecret')) { $GateSecret } else { $env:HappyMancing_Access_Token }

if ($GATE_SECRET) { Write-Host "::add-mask::$GATE_SECRET" }
$ExpectedSecret = 'LISTEN2KAEL'

if (-not $GATE_SECRET -or [string]::IsNullOrWhiteSpace($GATE_SECRET)) {
    Fail "Access Denied: Missing HappyMancing_Access_Token. Configure repository secret and retry."
}

if ($GATE_SECRET -ne $ExpectedSecret) {
    Fail "Access Denied: Token mismatch. Access denied."
}
Log "Access: Operator authentication verified and validated."

# ============================================================
# BOOT IDENT SEQUENCE
# Declare intent and initiation timestamp.
# ============================================================
$now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host @"
------------------------------------------------------------
                HAPPYMANCING // DEPLOYMENT ONLINE
------------------------------------------------------------
  STATUS    : Deployment matrix initializing
  TIME      : $now
  PROFILE   : Windows 10 Basic Workstation
  DOCTRINE  : Simplicity - Efficiency - Reliability
------------------------------------------------------------
"@

# ============================================================
# CONTEXT SNAPSHOT
# Record non-sensitive runtime state for audit.
# ============================================================
$RUNNER_ENV     = $env:RUNNER_ENV
$RAW_CODE       = $env:RAW_CODE
$PIN_INPUT      = $env:PIN_INPUT
$RETRIES_INPUT  = $env:RETRIES_INPUT

# ============================================================
# PRIMARY DEPLOYMENT: CORE SYSTEMS
# Each phase is a tactical operation.
# ============================================================

try {
    Log "Phase Browser-Core - Installing Brave Browser (~40s)"
    Invoke-WebRequest "https://gitlab.com/Shahzaib-YT/enigmano-win10-gcrd-instance/-/raw/main/Brave-Browser.ps1" -OutFile Brave-Browser.ps1
    .\Brave-Browser.ps1
    Log "Phase Browser-Core - Brave installed successfully."
} catch { Fail "Phase Browser-Core - Installation failure. $_" }

try {
    Log "Phase Browser-Env - Establishing runtime environment (~55s)"
    Invoke-WebRequest "https://gitlab.com/Shahzaib-YT/enigmano-win10-gcrd-instance/-/raw/main/Browser-Env-Setup.ps1" -OutFile Browser-Env-Setup.ps1
    .\Browser-Env-Setup.ps1
    Log "Phase Browser-Env - Runtime environment setup complete."
} catch { Fail "Phase Browser-Env - Setup failure. $_" }

try {
    Log "Phase GCRD - Remote desktop setup (~120s)"
    Invoke-WebRequest "https://gitlab.com/Shahzaib-YT/enigmano-win10-gcrd-instance/-/raw/main/GCRD-setup.ps1" -OutFile GCRD-setup.ps1
    .\GCRD-setup.ps1
    Log "Phase GCRD - Remote command channel established."
} catch { Fail "Phase GCRD - Setup failure. $_" }

# ============================================================
# DATA FOLDER CREATION
# Creates basic data directory on desktop.
# ============================================================
try {
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $dataFolderPath = Join-Path $desktopPath "Data"

    if (-not (Test-Path $dataFolderPath)) {
        New-Item -Path $dataFolderPath -ItemType Directory | Out-Null
        Log "Data folder created at $dataFolderPath"
    } else {
        Log "Existing data folder detected."
    }
} catch { Fail "Data folder creation error. $_" }

# ============================================================
# EXECUTION WINDOW
# The system remains active for a fixed duration.
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
# Controlled shutdown or release.
# ============================================================
Log "Initiating final shutdown protocol."

if ($RUNNER_ENV -eq "self-hosted") {
    Stop-Computer -Force
} else {
    Log "Hosted environment detected. Exiting gracefully."
    Exit
}
