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

$ErrorActionPreference = "Stop"

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
    $chromeInstaller = Join-Path $env:USERPROFILE 'Downloads\chrome_installer.exe'
    
    if (-not (Test-Path $chromeInstaller)) {
        Invoke-WebRequest "https://dl.google.com/chrome/install/latest/chrome_installer.exe" -OutFile $chromeInstaller -UseBasicParsing
    }
    
    Start-Process -FilePath $chromeInstaller -ArgumentList "/silent", "/install" -Wait -NoNewWindow
    Start-Sleep -Seconds 15
    Log "Google Chrome installed"
} catch { 
    Log "Warning: Chrome installation issue - $($_.Exception.Message)"
}

# ============================================================
# INSTALL CHROME REMOTE DESKTOP
# ============================================================
try {
    Log "Installing Chrome Remote Desktop"
    $crdInstaller = Join-Path $env:USERPROFILE 'Downloads\crdhost.msi'
    
    if (-not (Test-Path $crdInstaller)) {
        Invoke-WebRequest "https://dl.google.com/edgedl/chrome-remote-desktop/chromeremotedesktophost.msi" -OutFile $crdInstaller -UseBasicParsing
    }
    
    # Uninstall previous version first
    $existingProduct = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like "*Chrome Remote Desktop Host*" }
    if ($existingProduct) {
        Log "Removing existing CRD installation"
        $existingProduct.Uninstall() | Out-Null
        Start-Sleep -Seconds 10
    }
    
    # Install fresh
    Start-Process msiexec -ArgumentList "/i", "`"$crdInstaller`"", "/qn", "/norestart" -Wait -NoNewWindow
    Start-Sleep -Seconds 20
    
    # Ensure service is running
    Start-Service -Name "chromoting" -ErrorAction SilentlyContinue
    Set-Service -Name "chromoting" -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 10
    
    Log "Chrome Remote Desktop installed"
} catch { 
    Fail "CRD installation failed: $_"
}

# ============================================================
# FIX FOR GetConsoleMode ERROR
# ============================================================
try {
    Log "Applying console mode fix"
    
    # Create a hidden console window to avoid GetConsoleMode errors
    Add-Type -TypeDefinition @"
    using System;
    using System.Runtime.InteropServices;
    
    public class ConsoleFix {
        [DllImport("kernel32.dll")]
        static extern IntPtr GetConsoleWindow();
        
        [DllImport("user32.dll")]
        static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
        
        [DllImport("kernel32.dll")]
        static extern bool AllocConsole();
        
        public static void ApplyFix() {
            // Always ensure console exists
            AllocConsole();
            
            // Hide the console window to avoid UI issues
            IntPtr handle = GetConsoleWindow();
            if (handle != IntPtr.Zero) {
                ShowWindow(handle, 0); // 0 = SW_HIDE
            }
        }
    }
"@ -Language CSharp

    [ConsoleFix]::ApplyFix()
    Log "Console fix applied"
} catch {
    Log "Console fix skipped: $($_.Exception.Message)"
}

# ============================================================
# GCRD REGISTRATION - FIXED VERSION
# ============================================================
try {
    Log "Starting GCRD registration process"
    
    $gccCommand = $RAW_CODE.Trim()
    
    # If it's just a token, build the full command
    if ($gccCommand -match '^4/[A-Za-z0-9_-]+$') {
        $decodedMessage = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('SABvAHMAdAAgAGkAcwAgAHIAZQBhAGQAeQAuACAATgBvAHcAIABJACAAYwBhAG4AIABzAGUAZQAgAHkAbwB1AHIAIABkAGUAcwBrAHQAbwBwAA=='))
        $gccCommand = "`"$decodedMessage`"; `"C:\Program Files\Google\Chrome Remote Desktop\CurrentVersion\remoting_start_host.exe`" --code=`"$gccCommand`" --redirect-url=`"https://remotedesktop.google.com/_/oauthredirect`" --name=%COMPUTERNAME%"
    }

    Log "Executing registration command (first 100 chars): $($gccCommand.Substring(0, [Math]::Min(100, $gccCommand.Length)))..."

    # METHOD 1: Try direct execution with hidden window
    $retryCount = 0
    $maxRetries = if ($RETRIES_INPUT) { [int]$RETRIES_INPUT } else { 3 }

    while ($retryCount -lt $maxRetries) {
        try {
            Log "Registration attempt $($retryCount + 1) of $maxRetries"
            
            # Use Start-Process with hidden window to avoid console issues
            $process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $gccCommand -PassThru -NoNewWindow -Wait
            
            Start-Sleep -Seconds 15
            
            # Check if host processes are running
            $hostProcesses = Get-Process -Name "remoting_*" -ErrorAction SilentlyContinue
            if ($hostProcesses) {
                Log "GCRD host processes detected: $(($hostProcesses | ForEach-Object { $_.Name }) -join ', ')"
                break
            } else {
                Log "No GCRD processes detected, will retry..."
            }
        } catch {
            Log "Attempt $($retryCount + 1) failed: $($_.Exception.Message)"
        }
        
        $retryCount++
        if ($retryCount -lt $maxRetries) {
            Start-Sleep -Seconds 10
        }
    }

    # METHOD 2: Alternative approach if above fails
    if (-not (Get-Process -Name "remoting_*" -ErrorAction SilentlyContinue)) {
        Log "Trying alternative registration method"
        
        # Extract just the token from command
        $token = if ($gccCommand -match '--code=([^\s]+)') { $matches[1].Trim('"') } else { $RAW_CODE.Trim() }
        
        $altCommand = "`"C:\Program Files\Google\Chrome Remote Desktop\CurrentVersion\remoting_start_host.exe`" --code=`"$token`" --redirect-url=`"https://remotedesktop.google.com/_/oauthredirect`" --name=HappyMancing-VM-$((Get-Date).ToString('HHmmss'))"
        
        Log "Alternative command: $altCommand"
        
        Start-Process -FilePath "C:\Program Files\Google\Chrome Remote Desktop\CurrentVersion\remoting_start_host.exe" `
            -ArgumentList "--code=`"$token`"", "--redirect-url=`"https://remotedesktop.google.com/_/oauthredirect`"", "--name=HappyMancing-VM" `
            -NoNewWindow -Wait
        Start-Sleep -Seconds 20
    }

    # Final verification
    $finalProcesses = Get-Process -Name "remoting_*" -ErrorAction SilentlyContinue
    if ($finalProcesses) {
        Log "SUCCESS: GCRD registration completed. Processes running: $(($finalProcesses | ForEach-Object { $_.Name }) -join ', ')"
    } else {
        Log "WARNING: GCRD processes not detected. Registration may have failed."
        
        # Try one more time with simple approach
        Log "Attempting final registration with simple method"
        $simpleToken = $RAW_CODE -replace '^.*--code=([^\s]+).*$', '$1' -replace '"', ''
        if ($simpleToken -eq $RAW_CODE) {
            $simpleToken = $RAW_CODE.Trim()
        }
        
        $simpleCommand = "C:\Program Files\Google\Chrome Remote Desktop\CurrentVersion\remoting_start_host.exe --code=`"$simpleToken`" --redirect-url=`"https://remotedesktop.google.com/_/oauthredirect`" --name=HappyMancing"
        cmd.exe /c $simpleCommand
        Start-Sleep -Seconds 30
    }

} catch { 
    Log "ERROR during GCRD registration: $($_.Exception.Message)"
}

# ============================================================
# CREATE DATA FOLDER
# ============================================================
try {
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $dataFolderPath = Join-Path $desktopPath "Data"
    if (-not (Test-Path $dataFolderPath)) {
        New-Item -Path $dataFolderPath -ItemType Directory | Out-Null
        Log "Data folder created"
    }
} catch { 
    Log "Warning: Could not create data folder"
}

# ============================================================
# MONITORING LOOP
# ============================================================
$totalMinutes = 2000
$startTime = Get-Date
$endTime = $startTime.AddMinutes($totalMinutes)

Log "Starting monitoring for $totalMinutes minutes"

while ((Get-Date) -lt $endTime) {
    $elapsed = [math]::Round((Get-Date - $startTime).TotalMinutes, 1)
    $remaining = [math]::Round(($endTime - (Get-Date)).TotalMinutes, 1)
    
    # Monitor GCRD processes
    $gcrProcesses = Get-Process -Name "remoting_*" -ErrorAction SilentlyContinue
    $gcrCount = @($gcrProcesses).Count
    
    # Monitor CRD service
    $crdService = Get-Service -Name "chromoting" -ErrorAction SilentlyContinue
    $serviceStatus = if ($crdService) { $crdService.Status } else { "Not Found" }
    
    Log "Uptime: ${elapsed}m | Remaining: ${remaining}m | GCRD Processes: $gcrCount | Service: $serviceStatus"
    
    # Restart service if needed
    if ($serviceStatus -ne "Running" -and $crdService) {
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
    Exit 0
}
