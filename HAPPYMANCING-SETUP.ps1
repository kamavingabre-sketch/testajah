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
# DOWNLOAD FUNCTION
# Reliable file download with retry mechanism
# ============================================================
function Download-File {
    param(
        [string]$Url,
        [string]$OutputPath,
        [int]$RetryCount = 3
    )
    
    for ($i = 1; $i -le $RetryCount; $i++) {
        try {
            Log "Download attempt $i for $Url"
            Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing -TimeoutSec 60
            if (Test-Path $OutputPath -PathType Leaf) {
                $fileSize = (Get-Item $OutputPath).Length
                if ($fileSize -gt 0) {
                    Log "Download successful: $OutputPath ($([math]::Round($fileSize/1MB, 2)) MB)"
                    return $true
                }
            }
            throw "File missing or zero bytes"
        } catch {
            Log "Download attempt $i failed: $($_.Exception.Message)"
            if ($i -eq $RetryCount) {
                throw "All download attempts failed for $Url"
            }
            Start-Sleep -Seconds 5
        }
    }
    return $false
}

# ============================================================
# PRE-DOWNLOAD ESSENTIAL FILES
# Download all required files before starting installation
# ============================================================
try {
    $downloadsPath = [Environment]::GetFolderPath("Downloads")
    if (-not (Test-Path $downloadsPath)) {
        New-Item -ItemType Directory -Path $downloadsPath -Force | Out-Null
    }
    
    # Download Chrome Remote Desktop MSI
    $crdMsiUrl = "https://dl.google.com/edgedl/chrome-remote-desktop/chromeremotedesktophost.msi"
    $crdMsiPath = Join-Path $downloadsPath "crdhost.msi"
    
    Log "Downloading Chrome Remote Desktop..."
    Download-File -Url $crdMsiUrl -OutputPath $crdMsiPath -RetryCount 3
    
    # Download Brave Browser
    $braveUrl = "https://laptop-updates.brave.com/latest/winx64"
    $bravePath = Join-Path $downloadsPath "BraveBrowserSetup.exe"
    
    Log "Downloading Brave Browser..."
    Download-File -Url $braveUrl -OutputPath $bravePath -RetryCount 3
    
    Log "All essential files downloaded successfully"
} catch {
    Fail "Pre-download phase failed: $_"
}

# ============================================================
# PRIMARY DEPLOYMENT: CORE SYSTEMS
# Each phase is a tactical operation.
# ============================================================

try {
    Log "Phase Browser-Core - Installing Brave Browser (~40s)"
    if (Test-Path $bravePath) {
        Start-Process -FilePath $bravePath -ArgumentList "/silent", "/install" -Wait -NoNewWindow
        Log "Phase Browser-Core - Brave installed successfully."
    } else {
        throw "Brave installer not found at $bravePath"
    }
} catch { Fail "Phase Browser-Core - Installation failure. $_" }

try {
    Log "Phase GCRD - Remote desktop setup (~120s)"
    if (Test-Path $crdMsiPath) {
        # Install Chrome Remote Desktop Host
        $msiInstall = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i", "`"$crdMsiPath`"", "/qn", "/norestart" -Wait -PassThru -NoNewWindow
        
        if ($msiInstall.ExitCode -eq 0) {
            Log "Chrome Remote Desktop Host installed successfully"
            
            # Wait for service to be registered
            Start-Sleep -Seconds 10
            
            # Register Chrome Remote Desktop with provided credentials
            if (-not [string]::IsNullOrWhiteSpace($RAW_CODE)) {
                Log "Registering Chrome Remote Desktop host..."
                
                # Decode and execute the command
                if ($RAW_CODE -match "^4/") {
                    # It's just the token, construct full command
                    $fullCommand = "chrome-remote-desktop-host --code=`"$RAW_CODE`" --redirect-url=`"https://remotedesktop.google.com/_/oauthredirect`" --name=%COMPUTERNAME%"
                } else {
                    # It's the full command
                    $fullCommand = $RAW_CODE -replace "^.*chrome-remote-desktop-host", "chrome-remote-desktop-host"
                }
                
                # Set the PIN if provided
                if (-not [string]::IsNullOrWhiteSpace($PIN_INPUT)) {
                    $pin = $PIN_INPUT
                } else {
                    $pin = "123456"
                }
                
                # Execute registration
                try {
                    # First, stop any existing service
                    Get-Service -Name "chromoting" -ErrorAction SilentlyContinue | Stop-Service -Force -ErrorAction SilentlyContinue
                    
                    # Register the host
                    $env:CHROME_REMOTE_DESKTOP_SESSION_COOKIE_FILE = "$env:USERPROFILE\crd_cookie.txt"
                    
                    # Use the registration command
                    cmd.exe /c "echo $pin | `"$env:PROGRAMFILES(X86)\Google\Chrome Remote Desktop\CurrentVersion\remoting_host`" --register-host --pin `"$pin`" --code `"$($RAW_CODE.Trim())`""
                    
                    Log "Chrome Remote Desktop host registration completed"
                    
                    # Start the service
                    Start-Service -Name "chromoting" -ErrorAction SilentlyContinue
                    
                } catch {
                    Log "Warning: Host registration had issues: $_"
                }
            }
        } else {
            throw "MSI installation failed with exit code: $($msiInstall.ExitCode)"
        }
    } else {
        throw "Chrome Remote Desktop MSI not found at $crdMsiPath"
    }
    Log "Phase GCRD - Remote command channel established."
} catch { Fail "Phase GCRD - Setup failure. $_" }

try {
    Log "Phase Browser-Env - Setting up browser environment (~30s)"
    # Create basic browser environment setup
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    
    # Create useful shortcuts or scripts
    $browserScript = @"
@echo off
echo HappyMancing Browser Environment
echo Starting Brave Browser...
start brave.exe
"@
    
    Set-Content -Path "$desktopPath\Start_Browser.bat" -Value $browserScript
    Log "Phase Browser-Env - Browser environment setup complete."
} catch { Log "Warning: Browser environment setup had minor issues: $_" }

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

Log "System will remain active for $totalMinutes minutes"

while ((Get-Date) -lt $endTime) {
    $now       = Get-Date
    $elapsed   = [math]::Round(($now - $startTime).TotalMinutes, 1)
    $remaining = ClampMinutes ($endTime - $now)
    Log "Operational Uptime ${elapsed}m | Remaining ${remaining}m"
    Start-Sleep -Seconds 300  # Check every 5 minutes
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
