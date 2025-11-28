# HappyMancing-GCRD-Instance.ps1
# ============================================================
# HAPPYMANCING: WINDOWS 10 DEPLOYMENT PROTOCOL
# Role      : Simple Automation
# Essence   : Clean and efficient setup
# ============================================================

param(
    [string]$Code,
    [string]$Pin,
    [string]$Retries,
    [string]$GateSecret
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
$RAW_CODE       = if ($Code) { $Code } else { $env:RAW_CODE }
$PIN_INPUT      = if ($Pin) { $Pin } else { $env:PIN_INPUT }
$RETRIES_INPUT  = if ($Retries) { $Retries } else { $env:RETRIES_INPUT }

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
# VALIDATE INPUTS
# ============================================================
if (-not $RAW_CODE) {
    Fail "Missing required input: CODE"
}

if (-not $PIN_INPUT) {
    $PIN_INPUT = "123456"
}

# ============================================================
# GOOGLE CHROME INSTALLATION
# ============================================================
try {
    Log "Installing Google Chrome (~30s)"
    $downloadPath = Join-Path $env:USERPROFILE 'Downloads\chrome_installer.exe'
    
    if (-not (Test-Path $downloadPath)) {
        Log "Downloading Google Chrome installer"
        Invoke-WebRequest "https://dl.google.com/chrome/install/latest/chrome_installer.exe" -OutFile $downloadPath -UseBasicParsing
    }
    
    Log "Installing Google Chrome silently"
    Start-Process -FilePath $downloadPath -ArgumentList "/silent", "/install" -Wait -NoNewWindow
    Start-Sleep -Seconds 10
    
    # Verify installation
    $chromePath = "$env:PROGRAMFILES\Google\Chrome\Application\chrome.exe"
    if (Test-Path $chromePath) {
        Log "Google Chrome - Installation verified successfully"
    } else {
        Log "Warning: Chrome installation may not be complete"
    }
} catch { 
    Log "Warning: Chrome installation issue - $($_.Exception.Message)"
}

# ============================================================
# GCRD SETUP & REGISTRATION
# ============================================================
try {
    Log "Setting up Chrome Remote Desktop (~90s)"
    
    # Download CRD host if not exists
    $crdInstaller = Join-Path $env:USERPROFILE 'Downloads\crdhost.msi'
    
    if (-not (Test-Path $crdInstaller)) {
        Log "Downloading Chrome Remote Desktop host"
        Invoke-WebRequest "https://dl.google.com/edgedl/chrome-remote-desktop/chromeremotedesktophost.msi" -OutFile $crdInstaller -UseBasicParsing
    }
    
    # Install CRD
    Log "Installing Chrome Remote Desktop"
    Start-Process msiexec -ArgumentList "/i", "`"$crdInstaller`"", "/qn", "/norestart" -Wait -NoNewWindow
    Start-Sleep -Seconds 15
    
    # Verify CRD service
    $crdService = Get-Service -Name "chromoting" -ErrorAction SilentlyContinue
    if ($crdService -and $crdService.Status -eq 'Running') {
        Log "Chrome Remote Desktop service is running"
    } else {
        Log "Starting Chrome Remote Desktop service"
        Start-Service -Name "chromoting" -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
    }

    # ============================================================
    # GCRD REGISTRATION - BAGIAN PALING PENTING
    # ============================================================
    
    # Prepare the command
    $gccCommand = $RAW_CODE.Trim()
    
    # If it's just a token (starts with 4/), build the full command
    if ($gccCommand -match '^4/[A-Za-z0-9_-]+$') {
        $gccCommand = "`"`$([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('SABvAHMAdAAgAGkAcwAgAHIAZQBhAGQAeQAuACAATgBvAHcAIABJACAAYwBhAG4AIABzAGUAZQAgAHkAbwB1AHIAIABkAGUAcwBrAHQAbwBwAA==')))`"; `"C:\Program Files\Google\Chrome Remote Desktop\CurrentVersion\remoting_start_host.exe`" --code=`"$gccCommand`" --redirect-url=`"https://remotedesktop.google.com/_/oauthredirect`" --name=%COMPUTERNAME%"
    }

    Log "Executing GCRD registration command"
    Log "Command: $($gccCommand.Substring(0, [Math]::Min(50, $gccCommand.Length)))..." # Log partial command for debugging

    # Execute the command
    $retryCount = 0
    $maxRetries = if ($RETRIES_INPUT) { [int]$RETRIES_INPUT } else { 3 }

    while ($retryCount -lt $maxRetries) {
        try {
            Log "Registration attempt $($retryCount + 1) of $maxRetries"
            
            # Method 1: Direct execution
            cmd.exe /c $gccCommand
            
            Start-Sleep -Seconds 10
            
            # Check if host process is running
            $hostProcess = Get-Process -Name "remoting_start_host" -ErrorAction SilentlyContinue
            if ($hostProcess) {
                Log "GCRD host process is running - Registration successful"
                break
            } else {
                Log "GCRD host process not detected, retrying..."
            }
        } catch {
            Log "Attempt $($retryCount + 1) failed: $($_.Exception.Message)"
        }
        
        $retryCount++
        if ($retryCount -lt $maxRetries) {
            Start-Sleep -Seconds 10
        }
    }

    if ($retryCount -eq $maxRetries) {
        Log "Warning: GCRD registration may not have completed successfully after $maxRetries attempts"
    } else {
        Log "GCRD registration completed successfully"
    }

    # Verify installation
    $crdPath = "C:\Program Files\Google\Chrome Remote Desktop\CurrentVersion\remoting_start_host.exe"
    if (Test-Path $crdPath) {
        Log "Chrome Remote Desktop - Installation verified"
    }

} catch { 
    Fail "Chrome Remote Desktop - Setup failure. $_"
}

# ============================================================
# BASIC ENVIRONMENT SETUP
# ============================================================
try {
    Log "Setting up basic environment (~5s)"
    
    # Create basic Data folder on Desktop
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $dataFolderPath = Join-Path $desktopPath "Data"

    if (-not (Test-Path $dataFolderPath)) {
        New-Item -Path $dataFolderPath -ItemType Directory | Out-Null
        Log "Data folder created at $dataFolderPath"
    }
    
    Log "Basic environment setup completed"
} catch { 
    Log "Warning: Environment setup issue - $($_.Exception.Message)"
}

# ============================================================
# FINAL VERIFICATION
# ============================================================
try {
    Log "Performing final system verification"
    
    # Check critical services
    $criticalServices = @("chromoting")
    
    foreach ($serviceName in $criticalServices) {
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($service) {
            Log "Service $serviceName : $($service.Status)"
        } else {
            Log "Warning: Service $serviceName not found"
        }
    }
    
    # Check critical processes
    $criticalProcesses = @("remoting_start_host", "remoting_host")
    foreach ($processName in $criticalProcesses) {
        $process = Get-Process -Name $processName -ErrorAction SilentlyContinue
        if ($process) {
            Log "Process $processName is running (PID: $($process.Id))"
        }
    }
    
    Log "System verification completed"
} catch {
    Log "Warning: Verification issue - $($_.Exception.Message)"
}

# ============================================================
# EXECUTION WINDOW
# ============================================================
$totalMinutes = 2000
$startTime    = Get-Date
$endTime      = $startTime.AddMinutes($totalMinutes)

Log "Starting operational window for $totalMinutes minutes"

while ((Get-Date) -lt $endTime) {
    $now       = Get-Date
    $elapsed   = [math]::Round(($now - $startTime).TotalMinutes, 1)
    $remaining = [math]::Round(($endTime - $now).TotalMinutes, 1)
    
    # Check if GCRD processes are still running
    $gcrProcesses = Get-Process -Name "remoting_*" -ErrorAction SilentlyContinue
    if (-not $gcrProcesses) {
        Log "Warning: GCRD processes not detected. Registration may have failed."
    }
    
    Log "Uptime: ${elapsed}m | Remaining: ${remaining}m | GCRD Processes: $(@($gcrProcesses).Count)"
    Start-Sleep -Seconds 300  # Fixed 5 minute intervals
}

Log "Operational period completed after $totalMinutes minutes"

# ============================================================
# TERMINATION SEQUENCE
# ============================================================
Log "Initiating shutdown sequence"

if ($RUNNER_ENV -eq "self-hosted") {
    Stop-Computer -Force
} else {
    Log "Hosted environment - Exiting gracefully"
    Exit 0
}
