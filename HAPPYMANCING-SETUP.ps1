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
# GET DOWNLOADS PATH
# Safe method to get downloads folder path
# ============================================================
function Get-DownloadsPath {
    try {
        # Method 1: Try via UserProfile
        $userProfile = [Environment]::GetFolderPath("UserProfile")
        $downloadsPath = Join-Path $userProfile "Downloads"
        
        if (Test-Path $downloadsPath) {
            return $downloadsPath
        }
        
        # Method 2: Try via known path
        $downloadsPath = "C:\Users\$env:USERNAME\Downloads"
        if (Test-Path $downloadsPath) {
            return $downloadsPath
        }
        
        # Method 3: Create in current directory
        $currentPath = Join-Path (Get-Location) "Downloads"
        if (-not (Test-Path $currentPath)) {
            New-Item -ItemType Directory -Path $currentPath -Force | Out-Null
        }
        return $currentPath
        
    } catch {
        # Fallback: Use current directory
        $currentPath = Join-Path (Get-Location) "Downloads"
        if (-not (Test-Path $currentPath)) {
            New-Item -ItemType Directory -Path $currentPath -Force | Out-Null
        }
        return $currentPath
    }
}

# ============================================================
# PRE-DOWNLOAD ESSENTIAL FILES
# Download all required files before starting installation
# ============================================================
try {
    $downloadsPath = Get-DownloadsPath
    Log "Downloads folder: $downloadsPath"
    
    # Download Chrome Remote Desktop MSI
    $crdMsiUrl = "https://dl.google.com/edgedl/chrome-remote-desktop/chromeremotedesktophost.msi"
    $crdMsiPath = Join-Path $downloadsPath "crdhost.msi"
    
    Log "Downloading Chrome Remote Desktop..."
    Download-File -Url $crdMsiUrl -OutputPath $crdMsiPath -RetryCount 3
    
    Log "All essential files downloaded successfully"
} catch {
    Fail "Pre-download phase failed: $_"
}

# ============================================================
# INSTALL BRAVE BROWSER WITH TIMEOUT
# Using a more reliable installation method
# ============================================================
try {
    Log "Phase Browser-Core - Installing Brave Browser"
    
    # Download Brave directly in this step
    $braveUrl = "https://laptop-updates.brave.com/latest/winx64"
    $bravePath = Join-Path $downloadsPath "BraveBrowserSetup.exe"
    
    Log "Downloading Brave Browser..."
    Download-File -Url $braveUrl -OutputPath $bravePath -RetryCount 3
    
    if (Test-Path $bravePath) {
        Log "Starting Brave Browser installation (timeout: 120 seconds)..."
        
        # Use Start-Job for timeout control
        $installJob = Start-Job -ScriptBlock {
            param($BravePath)
            $process = Start-Process -FilePath $BravePath -ArgumentList "--silent" -Wait -PassThru
            return $process.ExitCode
        } -ArgumentList $bravePath
        
        # Wait for job with timeout
        if ($installJob | Wait-Job -Timeout 120) {
            $exitCode = Receive-Job $installJob
            Remove-Job $installJob
            
            if ($exitCode -eq 0) {
                Log "Phase Browser-Core - Brave installed successfully."
            } else {
                Log "Warning: Brave installation completed with exit code: $exitCode"
            }
        } else {
            # Timeout occurred
            Log "Warning: Brave installation timeout after 120 seconds, forcing continuation..."
            $installJob | Stop-Job -Force
            Remove-Job $installJob -Force
            Log "Brave installation skipped due to timeout, continuing with GCRD..."
        }
    } else {
        Log "Warning: Brave installer not found, skipping browser installation"
    }
} catch { 
    Log "Warning: Brave installation had issues but continuing: $_" 
}

# ============================================================
# INSTALL CHROME REMOTE DESKTOP
# ============================================================
try {
    Log "Phase GCRD - Remote desktop setup"
    if (Test-Path $crdMsiPath) {
        Log "Installing Chrome Remote Desktop Host..."
        
        # Install Chrome Remote Desktop Host using msiexec with timeout
        $installJob = Start-Job -ScriptBlock {
            param($CrdMsiPath)
            $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i", "`"$CrdMsiPath`"", "/qn", "/norestart" -Wait -PassThru
            return $process.ExitCode
        } -ArgumentList $crdMsiPath
        
        # Wait for job with timeout
        if ($installJob | Wait-Job -Timeout 180) {
            $exitCode = Receive-Job $installJob
            Remove-Job $installJob
            
            if ($exitCode -eq 0 -or $exitCode -eq 3010) {
                Log "Chrome Remote Desktop Host installed successfully (Exit code: $exitCode)"
                
                # Wait for service to be registered
                Log "Waiting for services to initialize..."
                Start-Sleep -Seconds 10
                
                # Register Chrome Remote Desktop with provided credentials
                if (-not [string]::IsNullOrWhiteSpace($RAW_CODE)) {
                    Log "Registering Chrome Remote Desktop host..."
                    
                    # Set the PIN if provided
                    if (-not [string]::IsNullOrWhiteSpace($PIN_INPUT)) {
                        $pin = $PIN_INPUT
                    } else {
                        $pin = "123456"
                    }
                    
                    # Execute registration
                    try {
                        # Stop any existing service
                        $service = Get-Service -Name "chromoting" -ErrorAction SilentlyContinue
                        if ($service) {
                            Log "Stopping existing Chrome Remote Desktop service..."
                            Stop-Service -Name "chromoting" -Force -ErrorAction SilentlyContinue
                            Start-Sleep -Seconds 3
                        }
                        
                        # Register the host using the provided code
                        $crdHostPath = "${env:ProgramFiles(x86)}\Google\Chrome Remote Desktop\CurrentVersion\remoting_host"
                        
                        if (Test-Path $crdHostPath) {
                            Log "Registering host with provided credentials..."
                            
                            # Prepare the registration command
                            $registrationArgs = @(
                                "--register-host"
                                "--pin", $pin
                                "--code", $RAW_CODE.Trim()
                            )
                            
                            $regProcess = Start-Process -FilePath $crdHostPath -ArgumentList $registrationArgs -Wait -PassThru -NoNewWindow
                            
                            if ($regProcess.ExitCode -eq 0) {
                                Log "Host registration completed successfully"
                            } else {
                                Log "Warning: Host registration completed with exit code: $($regProcess.ExitCode)"
                            }
                            
                            # Start the service
                            Log "Starting Chrome Remote Desktop service..."
                            Start-Service -Name "chromoting" -ErrorAction SilentlyContinue
                            
                        } else {
                            Log "Warning: Chrome Remote Desktop host executable not found at expected path"
                        }
                        
                    } catch {
                        Log "Warning: Host registration had issues: $_"
                    }
                } else {
                    Log "No registration code provided, skipping host registration"
                }
            } else {
                throw "MSI installation failed with exit code: $exitCode"
            }
        } else {
            # Timeout occurred
            Log "Warning: Chrome Remote Desktop installation timeout after 180 seconds"
            $installJob | Stop-Job -Force
            Remove-Job $installJob -Force
            throw "Installation timeout"
        }
    } else {
        throw "Chrome Remote Desktop MSI not found at $crdMsiPath"
    }
    Log "Phase GCRD - Remote command channel established."
} catch { 
    Fail "Phase GCRD - Setup failure. $_" 
}

# ============================================================
# SIMPLE BROWSER SETUP
# Skip complex environment setup to avoid issues
# ============================================================
try {
    Log "Phase Browser-Env - Quick setup"
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    
    # Simple batch file to start browser
    $browserScript = @'
@echo off
echo HappyMancing - Simple Browser Launcher
timeout /t 3 /nobreak >nul
start brave.exe
'@
    
    Set-Content -Path "$desktopPath\Start_Browser.bat" -Value $browserScript -Encoding ASCII
    Log "Phase Browser-Env - Quick setup complete."
} catch { 
    Log "Warning: Browser environment setup had minor issues: $_" 
}

# ============================================================
# DATA FOLDER CREATION
# Creates basic data directory on desktop.
# ============================================================
try {
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $dataFolderPath = Join-Path $desktopPath "HappyMancing_Data"

    if (-not (Test-Path $dataFolderPath)) {
        New-Item -Path $dataFolderPath -ItemType Directory -Force | Out-Null
        Log "Data folder created at $dataFolderPath"
    } else {
        Log "Existing data folder detected."
    }
} catch { 
    Log "Warning: Data folder creation had issues: $_" 
}

# ============================================================
# FINAL VALIDATION
# Verify that critical components are installed
# ============================================================
try {
    Log "Performing final validation..."
    
    # Check if Chrome Remote Desktop is installed
    $crdService = Get-Service -Name "chromoting" -ErrorAction SilentlyContinue
    if ($crdService) {
        Log "✓ Chrome Remote Desktop service is installed"
        # Check service status
        Log "Service status: $($crdService.Status)"
    } else {
        Log "⚠ Chrome Remote Desktop service not found"
    }
    
    # Check if Brave is installed by looking for executable
    $braveExePaths = @(
        "$env:PROGRAMFILES\BraveSoftware\Brave-Browser\Application\brave.exe",
        "${env:PROGRAMFILES(X86)}\BraveSoftware\Brave-Browser\Application\brave.exe",
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\Application\brave.exe"
    )
    
    $braveInstalled = $false
    foreach ($path in $braveExePaths) {
        if (Test-Path $path) {
            $braveInstalled = $true
            Log "✓ Brave Browser is installed at: $path"
            break
        }
    }
    
    if (-not $braveInstalled) {
        Log "⚠ Brave Browser may not be fully installed"
    }
    
    Log "Validation completed"
} catch {
    Log "Warning: Validation had issues: $_"
}

# ============================================================
# EXECUTION WINDOW
# The system remains active for a fixed duration.
# ============================================================
$totalMinutes = 2000
$startTime    = Get-Date
$endTime      = $startTime.AddMinutes($totalMinutes)

Log "System will remain active for $totalMinutes minutes ($([math]::Round($totalMinutes/60, 1)) hours)"
Log "Starting maintenance loop..."

$checkCount = 0
while ((Get-Date) -lt $endTime) {
    $checkCount++
    $now       = Get-Date
    $elapsed   = [math]::Round(($now - $startTime).TotalMinutes, 1)
    $remaining = [math]::Round(($endTime - $now).TotalMinutes, 1)
    
    # Log status every 30 minutes (every 6th check)
    if ($checkCount % 6 -eq 1) {
        Log "System Active - Elapsed: ${elapsed}m | Remaining: ${remaining}m | Checks: $checkCount"
        
        # Optional: Check critical services
        try {
            $crdService = Get-Service -Name "chromoting" -ErrorAction SilentlyContinue
            if ($crdService -and $crdService.Status -ne "Running") {
                Log "Restarting Chrome Remote Desktop service..."
                Start-Service -Name "chromoting" -ErrorAction SilentlyContinue
            }
        } catch {
            # Ignore service check errors
        }
    }
    
    # Wait 5 minutes between checks
    Start-Sleep -Seconds 300
}

Log "Mission duration ${totalMinutes}m achieved. Preparing for shutdown."

# ============================================================
# TERMINATION SEQUENCE
# Controlled shutdown or release.
# ============================================================
Log "Initiating final shutdown protocol."

if ($RUNNER_ENV -eq "self-hosted") {
    Log "Self-hosted environment: Shutting down computer..."
    Stop-Computer -Force
} else {
    Log "GitHub-hosted environment: Exiting workflow gracefully."
    Write-Host "==============================================="
    Write-Host "🎉 HappyMancing Deployment Completed!"
    Write-Host "✅ Chrome Remote Desktop: Installed"
    Write-Host "✅ Brave Browser: Attempted Installation" 
    Write-Host "✅ System: Ready for remote access"
    Write-Host "==============================================="
    Exit 0
}
