# HappyMancing-GCRD-Instance.ps1
# ============================================================
# HAPPYMANCING: WINDOWS 10 DEPLOYMENT PROTOCOL
# ============================================================

param(
    [string]$Code,
    [string]$Pin,
    [string]$Retries,
    [string]$GateSecret
)

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

function Timestamp { (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") }
function Log($msg)  { Write-Host "[HAPPYMANCING $(Timestamp)] $msg" }
function Fail($msg) { Write-Error "[HAPPYMANCING-ERROR $(Timestamp)] $msg"; Exit 1 }

# ============================================================
# ACCESS CONTROL
# ============================================================
$GATE_SECRET = if ($PSBoundParameters.ContainsKey('GateSecret')) { $GateSecret } else { $env:HappyMancing_Access_Token }

if (-not $GATE_SECRET -or [string]::IsNullOrWhiteSpace($GATE_SECRET)) {
    Fail "Access Denied: Missing HappyMancing_Access_Token."
}

if ($GATE_SECRET -ne 'LISTEN2KAEL') {
    Fail "Access Denied: Token mismatch."
}
Log "Access verified"

# ============================================================
# VALIDATE INPUTS
# ============================================================
$RAW_CODE = if ($Code) { $Code } else { $env:RAW_CODE }
$PIN_INPUT = if ($Pin) { $Pin } else { $env:PIN_INPUT }
$RETRIES_INPUT = if ($Retries) { $Retries } else { $env:RETRIES_INPUT }

if (-not $RAW_CODE) {
    Fail "Missing required input: CODE"
}

if (-not $PIN_INPUT) {
    $PIN_INPUT = "123456"
}

# ============================================================
# INSTALL GOOGLE CHROME
# ============================================================
try {
    Log "Installing Google Chrome"
    $chromeInstaller = "$env:TEMP\chrome_installer.exe"
    
    if (-not (Test-Path $chromeInstaller)) {
        Invoke-WebRequest "https://dl.google.com/chrome/install/latest/chrome_installer.exe" -OutFile $chromeInstaller -UseBasicParsing
    }
    
    $process = Start-Process -FilePath $chromeInstaller -ArgumentList "/silent", "/install" -PassThru -NoNewWindow
    $process | Wait-Process -Timeout 120 -ErrorAction SilentlyContinue
    
    if (-not $process.HasExited) {
        $process | Kill -Force
        Log "Chrome installation timed out"
    }
    
    Start-Sleep -Seconds 10
    Log "Chrome installation completed"
} catch { 
    Log "Chrome installation warning: $($_.Exception.Message)"
}

# ============================================================
# INSTALL CHROME REMOTE DESKTOP
# ============================================================
try {
    Log "Downloading Chrome Remote Desktop"
    $crdInstaller = "$env:TEMP\crdhost.msi"
    
    if (-not (Test-Path $crdInstaller)) {
        Invoke-WebRequest "https://dl.google.com/edgedl/chrome-remote-desktop/chromeremotedesktophost.msi" -OutFile $crdInstaller -UseBasicParsing
    }

    # Uninstall previous versions if exist
    Log "Checking for existing CRD installations"
    Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like "*Chrome Remote Desktop*" } | ForEach-Object {
        Log "Removing existing: $($_.Name)"
        $_.Uninstall() | Out-Null
    }
    
    Start-Sleep -Seconds 5

    # Install with timeout
    Log "Installing Chrome Remote Desktop"
    $installArgs = @(
        "/i",
        "`"$crdInstaller`"",
        "/qn",
        "/norestart",
        "/L*v",
        "`"$env:TEMP\crd_install.log`""
    )
    
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -PassThru -NoNewWindow
    $completed = $process | Wait-Process -Timeout 180 -ErrorAction SilentlyContinue
    
    if (-not $completed) {
        Log "CRD installation taking too long, forcing continue"
        $process | Kill -Force -ErrorAction SilentlyContinue
    }
    
    Start-Sleep -Seconds 10
    
    # Verify installation
    $crdPath = "C:\Program Files\Google\Chrome Remote Desktop\CurrentVersion\remoting_start_host.exe"
    if (Test-Path $crdPath) {
        Log "CRD installation verified successfully"
    } else {
        Log "CRD executable not found, but continuing"
    }
    
} catch { 
    Log "CRD installation warning: $($_.Exception.Message)"
}

# ============================================================
# START CRD SERVICE
# ============================================================
try {
    Log "Starting CRD services"
    
    # Ensure service is running
    $service = Get-Service -Name "chromoting" -ErrorAction SilentlyContinue
    if ($service) {
        if ($service.Status -ne "Running") {
            Start-Service -Name "chromoting" -ErrorAction SilentlyContinue
        }
        Set-Service -Name "chromoting" -StartupType Automatic -ErrorAction SilentlyContinue
        Log "CRD service configured"
    } else {
        Log "CRD service not found"
    }
    
    Start-Sleep -Seconds 5
} catch {
    Log "Service startup warning: $($_.Exception.Message)"
}

# ============================================================
# GCRD REGISTRATION - FIXED QUOTING ISSUE
# ============================================================
try {
    Log "Starting GCRD registration"
    
    $gccCommand = $RAW_CODE.Trim()
    
    # If it's just a token, build the full command
    if ($gccCommand -match '^4/[A-Za-z0-9_-]+$') {
        $token = $gccCommand
        $computerName = "HappyMancing-VM-$((Get-Date).ToString('HHmmss'))"
        
        # FIX: Use proper quoting for paths with spaces
        $crdExecutable = "C:\Program Files\Google\Chrome Remote Desktop\CurrentVersion\remoting_start_host.exe"
        
        if (Test-Path $crdExecutable) {
            Log "Using CRD executable: $crdExecutable"
            
            # Method 1: Direct PowerShell execution (more reliable)
            $registrationArgs = @(
                "--code=`"$token`""
                "--redirect-url=`"https://remotedesktop.google.com/_/oauthredirect`""
                "--name=`"$computerName`""
            )
            
            Log "Executing registration with token: $token"
            
            $process = Start-Process -FilePath "`"$crdExecutable`"" -ArgumentList $registrationArgs -PassThru -NoNewWindow
            $completed = $process | Wait-Process -Timeout 30 -ErrorAction SilentlyContinue
            
            if (-not $completed) {
                Log "Registration process timed out, but may still be running"
            }
            
        } else {
            Log "CRD executable not found at expected path"
        }
    } else {
        # If it's a full command, execute it directly with proper quoting
        Log "Executing provided GCRD command"
        cmd.exe /c $gccCommand
    }
    
    Start-Sleep -Seconds 15
    
    # Check for running processes
    $hostProcesses = Get-Process -Name "remoting_*" -ErrorAction SilentlyContinue
    if ($hostProcesses) {
        Log "SUCCESS: GCRD processes running: $(($hostProcesses.Name | Sort-Object -Unique) -join ', ')"
    } else {
        Log "No GCRD processes detected yet"
        
        # Try alternative method
        Log "Trying alternative registration method"
        $token = $RAW_CODE.Trim()
        if ($token -match '^4/[A-Za-z0-9_-]+$') {
            $altCommand = "`"C:\Program Files\Google\Chrome Remote Desktop\CurrentVersion\remoting_start_host.exe`" --code=`"$token`" --redirect-url=`"https://remotedesktop.google.com/_/oauthredirect`" --name=HappyMancing"
            cmd.exe /c $altCommand
            Start-Sleep -Seconds 20
        }
    }
    
} catch { 
    Log "Registration error: $($_.Exception.Message)"
    
    # Last resort - simple command execution
    try {
        $simpleToken = $RAW_CODE.Trim()
        if ($simpleToken -match '^4/[A-Za-z0-9_-]+$') {
            Log "Trying simple registration as fallback"
            & "C:\Program Files\Google\Chrome Remote Desktop\CurrentVersion\remoting_start_host.exe" "--code=$simpleToken" "--redirect-url=https://remotedesktop.google.com/_/oauthredirect" "--name=HappyMancing-Fallback"
        }
    } catch {
        Log "Fallback registration also failed: $($_.Exception.Message)"
    }
}

# ============================================================
# VERIFICATION AND MONITORING
# ============================================================
try {
    Log "Starting verification"
    
    # Check services
    $services = Get-Service -Name "*chrome*" -ErrorAction SilentlyContinue
    foreach ($service in $services) {
        Log "Service: $($service.Name) - $($service.Status)"
    }
    
    # Check processes
    $processes = Get-Process -Name "*chrome*", "*remoting*" -ErrorAction SilentlyContinue | Group-Object Name
    foreach ($processGroup in $processes) {
        Log "Process: $($processGroup.Name) - Count: $($processGroup.Count)"
    }
    
    # Create data folder
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $dataFolder = Join-Path $desktopPath "Data"
    if (-not (Test-Path $dataFolder)) {
        New-Item -ItemType Directory -Path $dataFolder -Force | Out-Null
        Log "Data folder created: $dataFolder"
    }
    
} catch {
    Log "Verification warning: $($_.Exception.Message)"
}

# ============================================================
# MONITORING LOOP
# ============================================================
$totalMinutes = 2000
$startTime = Get-Date
$endTime = $startTime.AddMinutes($totalMinutes)

Log "Starting monitoring for $totalMinutes minutes"

$checkCount = 0
while ((Get-Date) -lt $endTime) {
    $checkCount++
    $elapsed = [math]::Round((Get-Date - $startTime).TotalMinutes, 1)
    $remaining = [math]::Round(($endTime - (Get-Date)).TotalMinutes, 1)
    
    # Check GCRD status
    $gcrProcesses = Get-Process -Name "remoting_*" -ErrorAction SilentlyContinue
    $gcrCount = @($gcrProcesses).Count
    
    # Check CRD service
    $crdService = Get-Service -Name "chromoting" -ErrorAction SilentlyContinue
    $serviceStatus = if ($crdService) { $crdService.Status } else { "Not Found" }
    
    Log "Check #$checkCount | Elapsed: ${elapsed}m | Remaining: ${remaining}m | GCRD Processes: $gcrCount | Service: $serviceStatus"
    
    # Restart service if needed (every 10 checks ~50 minutes)
    if ($checkCount % 10 -eq 0 -and $crdService -and $serviceStatus -ne "Running") {
        Log "Restarting CRD service"
        Start-Service -Name "chromoting" -ErrorAction SilentlyContinue
    }
    
    Start-Sleep -Seconds 300
}

Log "Monitoring period completed"

# ============================================================
# CLEANUP
# ============================================================
if ($env:RUNNER_ENV -eq "self-hosted") {
    Stop-Computer -Force
} else {
    Log "Exiting workflow"
    Exit 0
}
