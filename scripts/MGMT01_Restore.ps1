# MGMT01 Complete Restoration Script
# Purpose: Automatically restore MGMT01 after snapshot rollback to Day 1
# Author: Ben Deyot
# Date: March 22, 2026

<#
.SYNOPSIS
    Complete restoration of MGMT01 after rolling back to Day 1 snapshot
    
.DESCRIPTION
    This script will:
    1. Configure network settings (static IP)
    2. Join domain ben.local
    3. Install all RSAT and management tools
    4. Recreate necessary folders
    5. Verify all configurations
    
.NOTES
    Run this script AS ADMINISTRATOR immediately after snapshot rollback
#>

# Configuration Variables
$ComputerName = "MGMT01-Ben"
$IPAddress = "10.0.5.10"
$SubnetMask = "24"
$Gateway = "10.0.5.2"
$DNS1 = "10.0.5.5"
$DNS2 = ""
$DomainName = "ben.local"
$DomainAdmin = "ben.deyot-adm"
$DomainPassword = "Pepper123!"
$InterfaceName = "Ethernet"

# Script Start
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  MGMT01 RESTORATION SCRIPT" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$LogFile = "C:\MGMT01_Restore_Log.txt"
function Write-Log {
    param($Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp - $Message" | Out-File -FilePath $LogFile -Append
    Write-Host $Message
}

Write-Log "Script started"

# STEP 1: Configure Network Settings
Write-Host ""
Write-Host "[STEP 1] Configuring Network Settings..." -ForegroundColor Yellow
Write-Log "Configuring network settings"

try {
    $Adapter = Get-NetAdapter | Where-Object {$_.Status -eq "Up"} | Select-Object -First 1
    $InterfaceAlias = $Adapter.Name
    
    Write-Log "Found network adapter: $InterfaceAlias"
    
    Remove-NetIPAddress -InterfaceAlias $InterfaceAlias -Confirm:$false -ErrorAction SilentlyContinue
    Remove-NetRoute -InterfaceAlias $InterfaceAlias -Confirm:$false -ErrorAction SilentlyContinue
    
    New-NetIPAddress -InterfaceAlias $InterfaceAlias -IPAddress $IPAddress -PrefixLength $SubnetMask -DefaultGateway $Gateway | Out-Null
    
    if ($DNS2) {
        Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses $DNS1,$DNS2
    } else {
        Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses $DNS1
    }
    
    Write-Host "  [OK] Network configured: $IPAddress/$SubnetMask" -ForegroundColor Green
    Write-Log "Network configured successfully"
    
    Write-Host ""
    Write-Host "  Testing connectivity..." -ForegroundColor Cyan
    
    if (Test-Connection -ComputerName $Gateway -Count 2 -Quiet) {
        Write-Host "    [OK] Gateway reachable ($Gateway)" -ForegroundColor Green
    } else {
        Write-Host "    [FAIL] Cannot reach gateway" -ForegroundColor Red
    }
    
    if (Test-Connection -ComputerName $DNS1 -Count 2 -Quiet) {
        Write-Host "    [OK] DNS server reachable ($DNS1)" -ForegroundColor Green
    } else {
        Write-Host "    [FAIL] Cannot reach DNS server" -ForegroundColor Red
    }
    
    if (Test-Connection -ComputerName "ad01-ben.ben.local" -Count 2 -Quiet) {
        Write-Host "    [OK] AD01 DNS resolution working" -ForegroundColor Green
    } else {
        Write-Host "    [FAIL] Cannot resolve AD01 hostname" -ForegroundColor Red
    }
    
} catch {
    Write-Host "  [FAIL] Network configuration failed: $_" -ForegroundColor Red
    Write-Log "ERROR: Network configuration failed - $_"
    exit 1
}

# STEP 2: Set Computer Name
Write-Host ""
Write-Host "[STEP 2] Setting Computer Name..." -ForegroundColor Yellow
Write-Log "Setting computer name to $ComputerName"

try {
    $CurrentName = $env:COMPUTERNAME
    
    if ($CurrentName -ne $ComputerName.Split('-')[0]) {
        Rename-Computer -NewName $ComputerName -Force
        Write-Host "  [OK] Computer renamed to $ComputerName" -ForegroundColor Green
        Write-Host "    (Will take effect after reboot)" -ForegroundColor Gray
        Write-Log "Computer renamed to $ComputerName"
        $NeedReboot = $true
    } else {
        Write-Host "  [OK] Computer name already correct" -ForegroundColor Green
    }
} catch {
    Write-Host "  [FAIL] Failed to rename computer: $_" -ForegroundColor Red
    Write-Log "ERROR: Computer rename failed - $_"
}

# STEP 3: Join Domain
Write-Host ""
Write-Host "[STEP 3] Joining Domain..." -ForegroundColor Yellow
Write-Log "Joining domain $DomainName"

try {
    $CurrentDomain = (Get-WmiObject Win32_ComputerSystem).Domain
    
    if ($CurrentDomain -eq $DomainName) {
        Write-Host "  [OK] Already joined to domain $DomainName" -ForegroundColor Green
        Write-Log "Already domain-joined"
    } else {
        $SecurePassword = ConvertTo-SecureString $DomainPassword -AsPlainText -Force
        $Credential = New-Object System.Management.Automation.PSCredential("$DomainName\$DomainAdmin", $SecurePassword)
        
        Add-Computer -DomainName $DomainName -Credential $Credential -Force
        
        Write-Host "  [OK] Successfully joined domain $DomainName" -ForegroundColor Green
        Write-Host "    (Reboot required)" -ForegroundColor Gray
        Write-Log "Domain join successful"
        $NeedReboot = $true
    }
} catch {
    Write-Host "  [FAIL] Domain join failed: $_" -ForegroundColor Red
    Write-Log "ERROR: Domain join failed - $_"
    Write-Host ""
    Write-Host "Troubleshooting tips:" -ForegroundColor Yellow
    Write-Host "  - Verify DNS is working (nslookup ad01-ben.ben.local)" -ForegroundColor Gray
    Write-Host "  - Verify domain admin credentials" -ForegroundColor Gray
    Write-Host "  - Check AD01 is online" -ForegroundColor Gray
    exit 1
}

# STEP 4: Reboot if Needed
if ($NeedReboot) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  REBOOT REQUIRED" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "The computer needs to reboot to apply changes." -ForegroundColor Yellow
    Write-Host "After reboot, run this script again to install tools." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Press any key to reboot now, or Ctrl+C to cancel..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    
    Write-Log "Rebooting computer"
    Restart-Computer -Force
    exit 0
}

# STEP 5: Install RSAT and Management Tools
Write-Host ""
Write-Host "[STEP 5] Installing Management Tools..." -ForegroundColor Yellow
Write-Log "Starting management tools installation"

$ToolsToInstall = @(
    @{Name="RSAT-AD-Tools"; Description="Active Directory Tools"},
    @{Name="RSAT-DNS-Server"; Description="DNS Management Tools"},
    @{Name="RSAT-DHCP"; Description="DHCP Management Tools"},
    @{Name="GPMC"; Description="Group Policy Management Console"},
    @{Name="RSAT-ADDS"; Description="AD DS Management Tools"},
    @{Name="RSAT-File-Services"; Description="File Services Tools"}
)

$TotalTools = $ToolsToInstall.Count
$CurrentTool = 0

foreach ($Tool in $ToolsToInstall) {
    $CurrentTool++
    Write-Host ""
    Write-Host "  [$CurrentTool/$TotalTools] Installing $($Tool.Description)..." -ForegroundColor Cyan
    
    try {
        $Feature = Get-WindowsFeature -Name $Tool.Name
        
        if ($Feature.Installed) {
            Write-Host "    [OK] Already installed" -ForegroundColor Green
            Write-Log "$($Tool.Name) already installed"
        } else {
            Install-WindowsFeature -Name $Tool.Name -IncludeManagementTools | Out-Null
            Write-Host "    [OK] Installed successfully" -ForegroundColor Green
            Write-Log "Installed $($Tool.Name)"
        }
    } catch {
        Write-Host "    [FAIL] Installation failed: $_" -ForegroundColor Red
        Write-Log "ERROR: Failed to install $($Tool.Name) - $_"
    }
}

# STEP 6: Create Necessary Directories
Write-Host ""
Write-Host "[STEP 6] Creating Directory Structure..." -ForegroundColor Yellow
Write-Log "Creating directories"

$DirsToCreate = @(
    "C:\Certs",
    "C:\Scripts",
    "C:\Logs",
    "C:\Backups",
    "C:\Software"
)

foreach ($Dir in $DirsToCreate) {
    try {
        if (!(Test-Path $Dir)) {
            New-Item -Path $Dir -ItemType Directory -Force | Out-Null
            Write-Host "  [OK] Created $Dir" -ForegroundColor Green
            Write-Log "Created directory $Dir"
        } else {
            Write-Host "  [OK] $Dir already exists" -ForegroundColor Green
        }
    } catch {
        Write-Host "  [FAIL] Failed to create $Dir" -ForegroundColor Red
        Write-Log "ERROR: Failed to create $Dir - $_"
    }
}

# STEP 6B: Create Software Share
Write-Host ""
Write-Host "[STEP 6B] Creating Software Share..." -ForegroundColor Yellow
Write-Log "Creating Software share"

try {
    $ExistingShare = Get-SmbShare -Name "Software" -ErrorAction SilentlyContinue
    
    if ($ExistingShare) {
        Write-Host "  [OK] Software share already exists" -ForegroundColor Green
        Write-Log "Software share already exists"
    } else {
        New-SmbShare -Name "Software" -Path "C:\Software" -FullAccess "Everyone" | Out-Null
        Write-Host "  [OK] Created Software share" -ForegroundColor Green
        Write-Log "Created Software share"
    }
} catch {
    Write-Host "  [FAIL] Failed to create Software share: $_" -ForegroundColor Red
    Write-Log "ERROR: Failed to create Software share - $_"
}

# STEP 6C: Download and Install PuTTY
Write-Host ""
Write-Host "[STEP 6C] Installing PuTTY..." -ForegroundColor Yellow
Write-Log "Installing PuTTY"

try {
    $PuTTYInstalled = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" | Where-Object { $_.DisplayName -like "*PuTTY*" }
    
    if ($PuTTYInstalled) {
        Write-Host "  [OK] PuTTY already installed" -ForegroundColor Green
        Write-Log "PuTTY already installed"
    } else {
        Write-Host "  Downloading PuTTY installer..." -ForegroundColor Cyan
        
        $PuTTYUrl = "https://the.earth.li/~sgtatham/putty/latest/w64/putty-64bit-0.81-installer.msi"
        $PuTTYPath = "C:\Software\putty-64bit-installer.msi"
        
        Invoke-WebRequest -Uri $PuTTYUrl -OutFile $PuTTYPath -UseBasicParsing
        Write-Host "    [OK] Downloaded to $PuTTYPath" -ForegroundColor Green
        Write-Log "Downloaded PuTTY installer"
        
        Write-Host "  Installing PuTTY..." -ForegroundColor Cyan
        
        Start-Process msiexec.exe -ArgumentList "/i `"$PuTTYPath`" /qn /norestart" -Wait
        
        Write-Host "  [OK] PuTTY installed successfully" -ForegroundColor Green
        Write-Log "PuTTY installed successfully"
    }
} catch {
    Write-Host "  [FAIL] PuTTY installation failed: $_" -ForegroundColor Red
    Write-Log "ERROR: PuTTY installation failed - $_"
    Write-Host "    You can download it manually from: https://www.putty.org/" -ForegroundColor Yellow
}

# STEP 7: Configure Firewall
Write-Host ""
Write-Host "[STEP 7] Configuring Firewall..." -ForegroundColor Yellow
Write-Log "Configuring firewall rules"

try {
    Set-NetFirewallRule -DisplayGroup "Remote Event Log Management" -Enabled True
    Set-NetFirewallRule -DisplayGroup "Windows Management Instrumentation (WMI)" -Enabled True
    Set-NetFirewallRule -DisplayGroup "Remote Service Management" -Enabled True
    
    Write-Host "  [OK] Remote management firewall rules enabled" -ForegroundColor Green
    Write-Log "Firewall rules configured"
} catch {
    Write-Host "  [FAIL] Firewall configuration failed: $_" -ForegroundColor Red
    Write-Log "ERROR: Firewall configuration failed - $_"
}

# STEP 8: Configure Server Manager
Write-Host ""
Write-Host "[STEP 8] Configuring Server Manager..." -ForegroundColor Yellow
Write-Log "Configuring Server Manager"

try {
    Write-Host ""
    Write-Host "  Verifying AD01 connectivity..." -ForegroundColor Cyan
    
    $AD01Server = "ad01-ben.ben.local"
    
    if (Test-Connection -ComputerName $AD01Server -Count 2 -Quiet) {
        Write-Host "    [OK] AD01 is reachable" -ForegroundColor Green
        Write-Log "AD01 connectivity verified"
    } else {
        Write-Host "    [WARN] Cannot reach AD01" -ForegroundColor Yellow
        Write-Log "WARNING: Cannot reach AD01"
    }
    
} catch {
    Write-Host "    [WARN] Server Manager configuration issue: $_" -ForegroundColor Yellow
    Write-Log "WARNING: Server Manager configuration - $_"
}

# STEP 8B: Start Performance Counters
Write-Host ""
Write-Host "  Starting Performance Counters..." -ForegroundColor Cyan
Write-Log "Starting performance counters"

try {
    $PerfService = Get-Service -Name "pla" -ErrorAction SilentlyContinue
    
    if ($PerfService.Status -ne "Running") {
        Start-Service -Name "pla"
        Set-Service -Name "pla" -StartupType Automatic
        Write-Host "    [OK] Performance counters started" -ForegroundColor Green
        Write-Log "Performance counters started"
    } else {
        Write-Host "    [OK] Performance counters already running" -ForegroundColor Green
    }
    
} catch {
    Write-Host "    [WARN] Could not start performance counters: $_" -ForegroundColor Yellow
    Write-Log "WARNING: Performance counters issue - $_"
}

# STEP 8C: Configure Remote Management
Write-Host ""
Write-Host "  Configuring Remote Management..." -ForegroundColor Cyan
Write-Log "Configuring remote management"

try {
    Enable-PSRemoting -Force -SkipNetworkProfileCheck -ErrorAction SilentlyContinue | Out-Null
    
    $TrustedHosts = (Get-Item WSMan:\localhost\Client\TrustedHosts).Value
    
    if ($TrustedHosts -notlike "*ad01-ben*") {
        if ([string]::IsNullOrEmpty($TrustedHosts)) {
            Set-Item WSMan:\localhost\Client\TrustedHosts -Value "ad01-ben.ben.local" -Force
        } else {
            Set-Item WSMan:\localhost\Client\TrustedHosts -Value "$TrustedHosts,ad01-ben.ben.local" -Force
        }
        Write-Host "    [OK] Added AD01 to trusted hosts" -ForegroundColor Green
        Write-Log "Added AD01 to trusted hosts"
    } else {
        Write-Host "    [OK] AD01 already in trusted hosts" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "  Testing remote connection to AD01..." -ForegroundColor Cyan
    
    $TestConnection = Test-WSMan -ComputerName "ad01-ben.ben.local" -ErrorAction SilentlyContinue
    
    if ($TestConnection) {
        Write-Host "    [OK] Remote management to AD01 working" -ForegroundColor Green
        Write-Log "Remote management to AD01 verified"
    } else {
        Write-Host "    [WARN] Cannot connect to AD01 remotely" -ForegroundColor Yellow
        Write-Log "WARNING: Remote connection to AD01 not verified"
    }
    
} catch {
    Write-Host "    [WARN] Remote management configuration issue: $_" -ForegroundColor Yellow
    Write-Log "WARNING: Remote management configuration - $_"
}

# STEP 9: Verify Configuration
Write-Host ""
Write-Host "[STEP 9] Verifying Configuration..." -ForegroundColor Yellow
Write-Log "Running verification checks"

Write-Host ""
Write-Host "  Network Configuration:" -ForegroundColor Cyan
$IPConfig = Get-NetIPAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4
Write-Host "    IP Address: $($IPConfig.IPAddress)" -ForegroundColor Gray
Write-Host "    Gateway: $Gateway" -ForegroundColor Gray
Write-Host "    DNS: $DNS1" -ForegroundColor Gray

Write-Host ""
Write-Host "  Domain Information:" -ForegroundColor Cyan
$ComputerSystem = Get-WmiObject Win32_ComputerSystem
Write-Host "    Computer: $($ComputerSystem.Name)" -ForegroundColor Gray
Write-Host "    Domain: $($ComputerSystem.Domain)" -ForegroundColor Gray

Write-Host ""
Write-Host "  Installed Tools:" -ForegroundColor Cyan
foreach ($Tool in $ToolsToInstall) {
    $Feature = Get-WindowsFeature -Name $Tool.Name
    if ($Feature.Installed) {
        Write-Host "    [OK] $($Tool.Description)" -ForegroundColor Green
    } else {
        Write-Host "    [FAIL] $($Tool.Description) - NOT INSTALLED" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "  Created Directories:" -ForegroundColor Cyan
foreach ($Dir in $DirsToCreate) {
    if (Test-Path $Dir) {
        Write-Host "    [OK] $Dir" -ForegroundColor Green
    } else {
        Write-Host "    [FAIL] $Dir - MISSING" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "  Software:" -ForegroundColor Cyan
$PuTTYCheck = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" | Where-Object { $_.DisplayName -like "*PuTTY*" }
if ($PuTTYCheck) {
    Write-Host "    [OK] PuTTY installed" -ForegroundColor Green
} else {
    Write-Host "    [FAIL] PuTTY - NOT INSTALLED" -ForegroundColor Red
}

$ShareCheck = Get-SmbShare -Name "Software" -ErrorAction SilentlyContinue
if ($ShareCheck) {
    Write-Host "    [OK] Software share created" -ForegroundColor Green
} else {
    Write-Host "    [FAIL] Software share - MISSING" -ForegroundColor Red
}

$PerfService = Get-Service -Name "pla" -ErrorAction SilentlyContinue
if ($PerfService.Status -eq "Running") {
    Write-Host "    [OK] Performance counters running" -ForegroundColor Green
} else {
    Write-Host "    [FAIL] Performance counters not started" -ForegroundColor Yellow
}

# STEP 10: Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  RESTORATION COMPLETE" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Summary:" -ForegroundColor Yellow
Write-Host "  [OK] Network configured ($IPAddress)" -ForegroundColor Green
Write-Host "  [OK] Joined to domain ($DomainName)" -ForegroundColor Green
Write-Host "  [OK] Management tools installed" -ForegroundColor Green
Write-Host "  [OK] PuTTY installed" -ForegroundColor Green
Write-Host "  [OK] Directory structure created" -ForegroundColor Green
Write-Host "  [OK] Software share created" -ForegroundColor Green
Write-Host "  [OK] Firewall configured" -ForegroundColor Green
Write-Host "  [OK] Server Manager configured" -ForegroundColor Green
Write-Host "  [OK] AD01 added to management" -ForegroundColor Green

Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Open Server Manager" -ForegroundColor Gray
Write-Host "  2. Add AD01 to All Servers: Manage -> Add Servers -> search ad01-ben" -ForegroundColor Gray
Write-Host "  3. Test DNS/AD management tools" -ForegroundColor Gray
Write-Host "  4. Run your separate CA lab setup script" -ForegroundColor Gray
Write-Host "  5. Resume lab work!" -ForegroundColor Gray

Write-Host ""
Write-Host "Log file saved to: $LogFile" -ForegroundColor Cyan

Write-Log "Script completed successfully"

Write-Host ""
Write-Host "WARNING: SECURITY REMINDER" -ForegroundColor Red
Write-Host "This script contains the domain admin password in plain text!" -ForegroundColor Yellow
Write-Host "Delete this script after use or remove the password line." -ForegroundColor Yellow

Write-Host ""
Write-Host "Press any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
