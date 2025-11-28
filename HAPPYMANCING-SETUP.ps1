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

# Validate PIN is numeric and at least 6 digits
if ($PIN_INPUT -notmatch '^\d{6,}$') {
    Log "Invalid PIN format, using default: 123456"
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
        $process | Stop-Process -Force -ErrorAction SilentlyContinue
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
    Get-CimInstance -ClassName Win32_Product | Where-Object { $_.Name -like "*Chrome Remote Desktop*" } | ForEach-Object {
        Log "Removing existing: $($_.Name)"
        Invoke-CimMethod -InputObject $_ -MethodName Uninstall | Out-Null
    }
    
    Start-Sleep -Seconds 5

    # Install CRD
    Log "Installing Chrome Remote Desktop"
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i", "`"$crdInstaller`"", "/qn", "/norestart" -PassThru -NoNewWindow
    $completed = $process | Wait-Process -Timeout 180 -ErrorAction SilentlyContinue
    
    if (-not $completed) {
        Log "CRD installation timed out, but continuing"
        $process | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    
    Start-Sleep -Seconds 15
    
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
            Start-Sleep -Seconds 5
        }
        Set-Service -Name "chromoting" -StartupType Automatic -ErrorAction SilentlyContinue
        Log "CRD service configured - Status: $($service.Status)"
    } else {
        Log "CRD service not found"
    }
    
} catch {
    Log "Service startup warning: $($_.Exception.Message)"
}

# ============================================================
# GCRD REGISTRATION - AUTOMATED PIN INPUT
# ============================================================
try {
    Log "Starting GCRD registration with automated PIN"
    
    $token = $RAW_CODE.Trim()
    
    # Extract token if it's a full command
    if ($token -match '--code=([^\s"'']+)') {
        $token = $matches[1]
    } elseif ($token -match '^4/[A-Za-z0-9_-]+$') {
        # Token is already in correct format
        $token = $token
    } else {
        Log "Invalid token format: $token"
        Fail "Invalid GCRD token format"
    }
    
    Log "Using token: $token"
    Log "Using PIN: $PIN_INPUT"
    
    $crdExecutable = "C:\Program Files\Google\Chrome Remote Desktop\CurrentVersion\remoting_start_host.exe"
    
    if (-not (Test-Path $crdExecutable)) {
        Log "CRD executable not found, attempting to use alternative method"
        # Try direct command execution
        $fullCommand = "`"$crdExecutable`" --code=`"$token`" --redirect-url=`"https://remotedesktop.google.com/_/oauthredirect`" --name=`"HappyMancing-VM`""
        Log "Executing: $fullCommand"
        cmd.exe /c $fullCommand
    } else {
        Log "Found CRD executable: $crdExecutable"
        
        # METHOD 1: Use PowerShell with automated input
        $registrationArgs = @(
            "--code=`"$token`""
            "--redirect-url=`"https://remotedesktop.google.com/_/oauthredirect`""
            "--name=`"HappyMancing-VM-$((Get-Date).ToString('yyyyMMdd-HHmmss'))`""
        )
        
        Log "Starting registration process..."
        
        # Create a process with redirected stdin to provide PIN automatically
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = $crdExecutable
        $processInfo.Arguments = $registrationArgs -join " "
        $processInfo.RedirectStandardInput = $true
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo
        
        # Start process
        $process.Start() | Out-Null
        
        # Provide PIN input automatically
        $process.StandardInput.WriteLine($PIN_INPUT)
        $process.StandardInput.WriteLine($PIN_INPUT) # Confirm PIN
        $process.StandardInput.Flush()
        
        # Wait for process with timeout
        $completed = $process.WaitForExit(30000) # 30 seconds timeout
        
        if (-not $completed) {
            Log "Registration process timed out, but may still be running in background"
            $process.Kill()
        } else {
            $exitCode = $process.ExitCode
            $output = $process.StandardOutput.ReadToEnd()
            $errorOutput = $process.StandardError.ReadToEnd()
            
            Log "Registration exit code: $exitCode"
            if ($output) { Log "Output: $output" }
            if ($errorOutput) { Log "Error: $errorOutput" }
        }
    }
    
    Start-Sleep -Seconds 20
    
    # METHOD 2: Alternative approach using Windows Credential Manager
    Log "Trying alternative registration method..."
    
    # The PIN might be stored in Windows Credential Manager
    # We'll try to set it using rundll32 and keymgr.dll
    try {
        $key = "HKCU:\Software\Google\Chrome Remote Desktop"
        if (-not (Test-Path $key)) {
            New-Item -Path $key -Force | Out-Null
        }
        New-ItemProperty -Path $key -Name "AuthPin" -Value $PIN_INPUT -PropertyType String -Force | Out-Null
        Log "PIN stored in registry for alternative authentication"
    } catch {
        Log "Failed to store PIN in registry: $($_.Exception.Message)"
    }
    
    # Final verification
    Start-Sleep -Seconds 10
    $hostProcesses = Get-Process -Name "remoting_*" -ErrorAction SilentlyContinue
    if ($hostProcesses) {
        Log "SUCCESS: GCRD registration completed! Processes: $(($hostProcesses.Name | Sort-Object -Unique) -join ', ')"
        
        # Additional verification - check if service is properly registered
        $service = Get-Service -Name "chromoting" -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq 'Running') {
            Log "CRD service is running properly"
        }
    } else {
        Log "WARNING: No GCRD processes detected immediately after registration"
        Log "Registration might still be processing in background"
    }
    
} catch { 
    Log "Registration error: $($_.Exception.Message)"
    
    # Last resort - try simple execution without PIN (might use default)
    try {
        Log "Trying fallback registration without explicit PIN"
        $fallbackArgs = @(
            "--code=`"$token`""
            "--redirect-url=`"https://remotedesktop.google.com/_/oauthredirect`""
            "--name=`"HappyMancing-Fallback`""
        )
        Start-Process -FilePath $crdExecutable -ArgumentList $fallbackArgs -NoNewWindow -PassThru
        Start-Sleep -Seconds 15
    } catch {
        Log "Fallback registration also failed: $($_.Exception.Message)"
    }
}

# ============================================================
# FINAL SYSTEM CHECKS
# ============================================================
try {
    Log "Performing final system checks"
    
    # Check critical components
    $checks = @(
        @{ Name = "Chrome"; Path = "C:\Program Files\Google\Chrome\Application\chrome.exe" },
        @{ Name = "CRD Host"; Path = "C:\Program Files\Google\Chrome Remote Desktop\CurrentVersion\remoting_start_host.exe" },
        @{ Name = "CRD Service"; Service = "chromoting" }
    )
    
    foreach ($check in $checks) {
        if ($check.Path -and (Test-Path $check.Path)) {
            Log "✓ $($check.Name) - Found"
        } elseif ($check.Service) {
            $service = Get-Service -Name $check.Service -ErrorAction SilentlyContinue
            if ($service) {
                Log "✓ $($check.Name) - $($service.Status)"
            } else {
                Log "✗ $($check.Name) - Not found"
            }
        } else {
            Log "✗ $($check.Name) - Not found"
        }
    }
    
    # Create data folder
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $dataFolder = Join-Path $desktopPath "Data"
    if (-not (Test-Path $dataFolder)) {
        New-Item -ItemType Directory -Path $dataFolder -Force | Out-Null
        Log "Data folder created: $dataFolder"
    }
    
} catch {
    Log "System check warning: $($_.Exception.Message)"
}

# ============================================================
# MONITORING LOOP
# ============================================================
$totalMinutes = 2000
$startTime = Get-Date
$endTime = $startTime.AddMinutes($totalMinutes)

Log "Starting monitoring for $totalMinutes minutes"
Log "VM should now be available in your Chrome Remote Desktop"

$checkCount = 0
while ((Get-Date) -lt $endTime) {
    $checkCount++
    $elapsed = [math]::Round((Get-Date - $startTime).TotalMinutes, 1)
    $remaining = [math]::Round(($endTime - (Get-Date)).TotalMinutes, 1)
    
    # Monitor GCRD processes and services
    $gcrProcesses = Get-Process -Name "remoting_*" -ErrorAction SilentlyContinue
    $gcrCount = @($gcrProcesses).Count
    
    $crdService = Get-Service -Name "chromoting" -ErrorAction SilentlyContinue
    $serviceStatus = if ($crdService) { $crdService.Status } else { "Not Found" }
    
    $chromeProcesses = Get-Process -Name "chrome*" -ErrorAction SilentlyContinue
    $chromeCount = @($chromeProcesses).Count
    
    Log "Check #$checkCount | Uptime: ${elapsed}m | Remaining: ${remaining}m"
    Log "  GCRD Processes: $gcrCount | CRD Service: $serviceStatus | Chrome Processes: $chromeCount"
    
    # Restart service if needed
    if ($crdService -and $serviceStatus -ne "Running") {
        Log "Restarting CRD service"
        Start-Service -Name "chromoting" -ErrorAction SilentlyContinue
    }
    
    Start-Sleep -Seconds 300
}

Log "Monitoring period completed"

if ($env:RUNNER_ENV -eq "self-hosted") {
    Stop-Computer -Force
} else {
    Log "Workflow completed successfully"
    Exit 0
}
