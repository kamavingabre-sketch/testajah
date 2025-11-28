# HappyMancing-GCRD-Instance.ps1
# ============================================================
# HAPPYMANCING: WINDOWS 10 DEPLOYMENT PROTOCOL
# Role      : Simple Automation
# Essence   : Clean and efficient setup
# ============================================================

param(
    [string]$GateSecret  # Optional: pass as -GateSecret or via env:HappyMancing_Access_Token
)

# ============================================================
# CORE DIRECTIVE: SYSTEM INTEGRITY
# ============================================================
$ErrorActionPreference = "Stop"

# ============================================================
# TELEMETRY CONDUIT
# ============================================================
function Timestamp { (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") }
function Log($msg)  { Write-Host "[HAPPYMANCING $(Timestamp)] $msg" }
function Fail($msg) { Write-Error "[HAPPYMANCING-ERROR $(Timestamp)] $msg"; Exit 1 }

# ============================================================
# BOOT IDENT SEQUENCE
# ============================================================
$now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host @"
------------------------------------------------------------
                HAPPYMANCING // SYSTEM ONLINE
------------------------------------------------------------
  STATUS    : Deployment initializing
  TIME      : $now
  PROFILE   : Windows 10 Basic Workstation
  DOCTRINE  : Simple - Clean - Efficient
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
# ACCESS CONTROL: GATE VERIFICATION
# ============================================================
$GATE_SECRET = if ($PSBoundParameters.ContainsKey('GateSecret')) { $GateSecret } else { $env:HappyMancing_Access_Token }

if ($GATE_SECRET) { Write-Host "::add-mask::$GATE_SECRET" }
$ExpectedSecret = 'LISTEN2KAEL'

if (-not $GATE_SECRET -or [string]::IsNullOrWhiteSpace($GATE_SECRET)) {
    Fail "Access Denied: Missing HappyMancing_Access_Token. Configure repository secret and retry."
}

if ($GATE_SECRET -ne $ExpectedSecret) {
    Fail "Access Denied: Token mismatch. Lockdown enforced."
}
Log "Access Gate: Operator authentication verified and validated."

# ============================================================
# GOOGLE CHROME INSTALLATION
# ============================================================
try {
    Log "Installing Google Chrome (~30s)"
    $downloadPath = Join-Path $env:USERPROFILE 'Downloads\chrome_installer.exe'
    
    if (Test-Path $downloadPath) {
        Start-Process -FilePath $downloadPath -ArgumentList "/silent", "/install" -Wait
        Log "Google Chrome - Installation completed successfully."
    } else {
        Log "Downloading and installing Google Chrome"
        Invoke-WebRequest "https://dl.google.com/chrome/install/latest/chrome_installer.exe" -OutFile $downloadPath
        Start-Process -FilePath $downloadPath -ArgumentList "/silent", "/install" -Wait
        Log "Google Chrome - Downloaded and installed successfully."
    }
} catch { Fail "Google Chrome - Installation failure. $_" }

# ============================================================
# BASIC ENVIRONMENT SETUP
# ============================================================
try {
    Log "Setting up basic environment (~10s)"
    
    # Create basic Data folder on Desktop
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $dataFolderPath = Join-Path $desktopPath "Data"

    if (-not (Test-Path $dataFolderPath)) {
        New-Item -Path $dataFolderPath -ItemType Directory | Out-Null
        Log "Data folder created at $dataFolderPath"
    } else {
        Log "Data folder already exists"
    }
} catch { Fail "Environment setup - Failure encountered. $_" }

# ============================================================
# GCRD SETUP
# ============================================================
try {
    Log "Setting up Chrome Remote Desktop (~60s)"
    
    # Download and install CRD host
    $crdInstaller = Join-Path $env:USERPROFILE 'Downloads\crdhost.msi'
    
    if (-not (Test-Path $crdInstaller)) {
        Invoke-WebRequest "https://dl.google.com/edgedl/chrome-remote-desktop/chromeremotedesktophost.msi" -OutFile $crdInstaller
    }
    
    # Install CRD
    Start-Process msiexec -ArgumentList "/i", "`"$crdInstaller`"", "/qn", "/norestart" -Wait
    Log "Chrome Remote Desktop - Installation completed"
    
    # Wait for service to be ready
    Start-Sleep -Seconds 10
    
} catch { Fail "Chrome Remote Desktop - Setup failure. $_" }

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
    Start-Sleep -Seconds 300  # Fixed 5 minute intervals
}

Log "Mission duration ${totalMinutes}m achieved. Preparing for decommission."

# ============================================================
# TERMINATION SEQUENCE
# ============================================================
Log "Decommission - Initiating final shutdown protocol."

if ($RUNNER_ENV -eq "self-hosted") {
    Stop-Computer -Force
} else {
    Log "Decommission - Hosted environment detected. Exiting gracefully."
    Exit
}
