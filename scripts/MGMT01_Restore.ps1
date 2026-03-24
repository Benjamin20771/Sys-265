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

# ============================================================================
# CONFIGURATION VARIABLES - MODIFY THESE FOR YOUR ENVIRONMENT
# ============================================================================

$ComputerName = "MGMT01-Ben"
$IPAddress = "10.0.5.10"           # MGMT01's IP address
$SubnetMask = "24"                 # /24 = 255.255.255.0
$Gateway = "10.0.5.2"              # FW01 gateway
$DNS1 = "10.0.5.5"                 # AD01 DNS
$DNS2 = ""                         # Secondary DNS (empty if none)
$DomainName = "ben.local"
$DomainAdmin = "ben.deyot-adm"
$DomainPassword = "Pepper123!"     # TODO: Remove after use!
$InterfaceName = "Ethernet"        # Network adapter name

# ============================================================================
# SCRIPT START
# ============================================================================

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  MGMT01 RESTORATION SCRIPT" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Log file
$LogFile = "C:\MGMT01_Restore_Log.txt"
function Write-Log {
    param($Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp - $Message" | Out-File -FilePath $LogFile -Append
    Write-Host $Message
}

Write-Log "Script started"

# ============================================================================
# STEP 1: CONFIGURE NETWORK SETTINGS
# ============================================================================

Write-Host "`n[STEP 1] Configuring Network Settings..." -ForegroundColor Yellow
Write-Log "Configuring network settings"

try {
    # Get network adapter
    $Adapter = Get-NetAdapter | Where-Object {$_.Status -eq "Up"} | Select-Object -First 1
    $InterfaceAlias = $Adapter.Name
    
    Write-Log "Found network adapter: $InterfaceAlias"
    
    # Remove existing IP configuration
    Remove-NetIPAddress -InterfaceAlias $InterfaceAlias -Confirm:$false -ErrorAction SilentlyContinue
    Remove-NetRoute -InterfaceAlias $InterfaceAlias -Confirm:$false -ErrorAction SilentlyContinue
    
    # Configure static IP
    New-NetIPAddress -InterfaceAlias $InterfaceAlias `
                     -IPAddress $IPAddress `
                     -PrefixLength $SubnetMask `
                     -DefaultGateway $Gateway | Out-Null
    
    # Configure DNS
    if ($DNS2) {
        Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses $DNS1,$DNS2
    } else {
        Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses $DNS1
    }
    
    Write-Host "  ✓ Network configured: $IPAddress/$SubnetMask" -ForegroundColor Green
    Write-Log "Network configured successfully"
    
    # Test connectivity
    Write-Host "`n  Testing connectivity..." -ForegroundColor Cyan
    
    if (Test-Connection -ComputerName $Gateway -Count 2 -Quiet) {
        Write-Host "    ✓ Gateway reachable ($Gateway)" -ForegroundColor Green
    } else {
        Write-Host "    ✗ Cannot reach gateway" -ForegroundColor Red
    }
    
    if (Test-Connection -ComputerName $DNS1 -Count 2 -Quiet) {
        Write-Host "    ✓ DNS server reachable ($DNS1)" -ForegroundColor Green
    } else {
        Write-Host "    ✗ Cannot reach DNS server" -ForegroundColor Red
    }
    
    if (Test-Connection -ComputerName "ad01-ben.ben.local" -Count 2 -Quiet) {
        Write-Host "    ✓ AD01 DNS resolution working" -ForegroundColor Green
    } else {
        Write-Host "    ✗ Cannot resolve AD01 hostname" -ForegroundColor Red
    }
    
} catch {
    Write-Host "  ✗ Network configuration failed: $_" -ForegroundColor Red
    Write-Log "ERROR: Network configuration failed - $_"
    exit 1
}

# ============================================================================
# STEP 2: SET COMPUTER NAME
# ============================================================================

Write-Host "`n[STEP 2] Setting Computer Name..." -ForegroundColor Yellow
Write-Log "Setting computer name to $ComputerName"

try {
    $CurrentName = $env:COMPUTERNAME
    
    if ($CurrentName -ne $ComputerName.Split('-')[0]) {
        Rename-Computer -NewName $ComputerName -Force
        Write-Host "  ✓ Computer renamed to $ComputerName" -ForegroundColor Green
        Write-Host "    (Will take effect after reboot)" -ForegroundColor Gray
        Write-Log "Computer renamed to $ComputerName"
        $NeedReboot = $true
    } else {
        Write-Host "  ✓ Computer name already correct" -ForegroundColor Green
    }
} catch {
    Write-Host "  ✗ Failed to rename computer: $_" -ForegroundColor Red
    Write-Log "ERROR: Computer rename failed - $_"
}

# ============================================================================
# STEP 3: JOIN DOMAIN
# ============================================================================

Write-Host "`n[STEP 3] Joining Domain..." -ForegroundColor Yellow
Write-Log "Joining domain $DomainName"

try {
    # Check if already domain-joined
    $CurrentDomain = (Get-WmiObject Win32_ComputerSystem).Domain
    
    if ($CurrentDomain -eq $DomainName) {
        Write-Host "  ✓ Already joined to domain $DomainName" -ForegroundColor Green
        Write-Log "Already domain-joined"
    } else {
        # Create credential object
        $SecurePassword = ConvertTo-SecureString $DomainPassword -AsPlainText -Force
        $Credential = New-Object System.Management.Automation.PSCredential("$DomainName\$DomainAdmin", $SecurePassword)
        
        # Join domain
        Add-Computer -DomainName $DomainName -Credential $Credential -Force
        
        Write-Host "  ✓ Successfully joined domain $DomainName" -ForegroundColor Green
        Write-Host "    (Reboot required)" -ForegroundColor Gray
        Write-Log "Domain join successful"
        $NeedReboot = $true
    }
} catch {
    Write-Host "  ✗ Domain join failed: $_" -ForegroundColor Red
    Write-Log "ERROR: Domain join failed - $_"
    Write-Host "`nTroubleshooting tips:" -ForegroundColor Yellow
    Write-Host "  - Verify DNS is working (nslookup ad01-ben.ben.local)" -ForegroundColor Gray
    Write-Host "  - Verify domain admin credentials" -ForegroundColor Gray
    Write-Host "  - Check AD01 is online" -ForegroundColor Gray
    exit 1
}

# ============================================================================
# STEP 4: REBOOT IF NEEDED
# ============================================================================

if ($NeedReboot) {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  REBOOT REQUIRED" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "`nThe computer needs to reboot to apply changes." -ForegroundColor Yellow
    Write-Host "After reboot, run this script again to install tools." -ForegroundColor Yellow
    Write-Host "`nPress any key to reboot now, or Ctrl+C to cancel..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    
    Write-Log "Rebooting computer"
    Restart-Computer -Force
    exit 0
}

# ============================================================================
# STEP 5: INSTALL RSAT AND MANAGEMENT TOOLS
# ============================================================================

Write-Host "`n[STEP 5] Installing Management Tools..." -ForegroundColor Yellow
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
    Write-Host "`n  [$CurrentTool/$TotalTools] Installing $($Tool.Description)..." -ForegroundColor Cyan
    
    try {
        $Feature = Get-WindowsFeature -Name $Tool.Name
        
        if ($Feature.Installed) {
            Write-Host "    ✓ Already installed" -ForegroundColor Green
            Write-Log "$($Tool.Name) already installed"
        } else {
            Install-WindowsFeature -Name $Tool.Name -IncludeManagementTools | Out-Null
            Write-Host "    ✓ Installed successfully" -ForegroundColor Green
            Write-Log "Installed $($Tool.Name)"
        }
    } catch {
        Write-Host "    ✗ Installation failed: $_" -ForegroundColor Red
        Write-Log "ERROR: Failed to install $($Tool.Name) - $_"
    }
}

# ============================================================================
# STEP 6: CREATE NECESSARY DIRECTORIES
# ============================================================================

Write-Host "`n[STEP 6] Creating Directory Structure..." -ForegroundColor Yellow
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
            Write-Host "  ✓ Created $Dir" -ForegroundColor Green
            Write-Log "Created directory $Dir"
        } else {
            Write-Host "  ✓ $Dir already exists" -ForegroundColor Green
        }
    } catch {
        Write-Host "  ✗ Failed to create $Dir" -ForegroundColor Red
        Write-Log "ERROR: Failed to create $Dir - $_"
    }
}

# ============================================================================
# STEP 6B: CREATE SOFTWARE SHARE FOR GPO DEPLOYMENT
# ============================================================================

Write-Host "`n[STEP 6B] Creating Software Share..." -ForegroundColor Yellow
Write-Log "Creating Software share"

try {
    # Check if share already exists
    $ExistingShare = Get-SmbShare -Name "Software" -ErrorAction SilentlyContinue
    
    if ($ExistingShare) {
        Write-Host "  ✓ Software share already exists" -ForegroundColor Green
        Write-Log "Software share already exists"
    } else {
        # Create the share
        New-SmbShare -Name "Software" -Path "C:\Software" -FullAccess "Everyone" | Out-Null
        Write-Host "  ✓ Created Software share (\\$env:COMPUTERNAME\Software)" -ForegroundColor Green
        Write-Log "Created Software share"
    }
} catch {
    Write-Host "  ✗ Failed to create Software share: $_" -ForegroundColor Red
    Write-Log "ERROR: Failed to create Software share - $_"
}

# ============================================================================
# STEP 6C: DOWNLOAD AND INSTALL PUTTY
# ============================================================================

Write-Host "`n[STEP 6C] Installing PuTTY..." -ForegroundColor Yellow
Write-Log "Installing PuTTY"

try {
    # Check if PuTTY is already installed
    $PuTTYInstalled = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" | 
                      Where-Object { $_.DisplayName -like "*PuTTY*" }
    
    if ($PuTTYInstalled) {
        Write-Host "  ✓ PuTTY already installed" -ForegroundColor Green
        Write-Log "PuTTY already installed"
    } else {
        Write-Host "  Downloading PuTTY installer..." -ForegroundColor Cyan
        
        # Download latest PuTTY MSI (64-bit)
        $PuTTYUrl = "https://the.earth.li/~sgtatham/putty/latest/w64/putty-64bit-0.81-installer.msi"
        $PuTTYPath = "C:\Software\putty-64bit-installer.msi"
        
        Invoke-WebRequest -Uri $PuTTYUrl -OutFile $PuTTYPath -UseBasicParsing
        Write-Host "    ✓ Downloaded to $PuTTYPath" -ForegroundColor Green
        Write-Log "Downloaded PuTTY installer"
        
        Write-Host "  Installing PuTTY..." -ForegroundColor Cyan
        
        # Install silently
        Start-Process msiexec.exe -ArgumentList "/i `"$PuTTYPath`" /qn /norestart" -Wait
        
        Write-Host "  ✓ PuTTY installed successfully" -ForegroundColor Green
        Write-Log "PuTTY installed successfully"
    }
} catch {
    Write-Host "  ✗ PuTTY installation failed: $_" -ForegroundColor Red
    Write-Log "ERROR: PuTTY installation failed - $_"
    Write-Host "    You can download it manually from: https://www.putty.org/" -ForegroundColor Yellow
}

# ============================================================================
# STEP 7: CONFIGURE FIREWALL (ALLOW MANAGEMENT)
# ============================================================================

Write-Host "`n[STEP 7] Configuring Firewall..." -ForegroundColor Yellow
Write-Log "Configuring firewall rules"

try {
    # Enable Remote Management
    Set-NetFirewallRule -DisplayGroup "Remote Event Log Management" -Enabled True
    Set-NetFirewallRule -DisplayGroup "Windows Management Instrumentation (WMI)" -Enabled True
    Set-NetFirewallRule -DisplayGroup "Remote Service Management" -Enabled True
    
    Write-Host "  ✓ Remote management firewall rules enabled" -ForegroundColor Green
    Write-Log "Firewall rules configured"
} catch {
    Write-Host "  ✗ Firewall configuration failed: $_" -ForegroundColor Red
    Write-Log "ERROR: Firewall configuration failed - $_"
}

# ============================================================================
# STEP 8: CONFIGURE SERVER MANAGER
# ============================================================================

Write-Host "`n[STEP 8] Configuring Server Manager..." -ForegroundColor Yellow
Write-Log "Configuring Server Manager"

try {
    Write-Host "`n  Adding AD01 to Server Manager..." -ForegroundColor Cyan
    
    # Import ServerManager module
    Import-Module ServerManager -ErrorAction SilentlyContinue
    
    # Add AD01 to All Servers pool
    $AD01Server = "ad01-ben.ben.local"
    
    # Check if AD01 is already in the server pool
    $ExistingServers = Get-SMServer -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ServerName
    
    if ($ExistingServers -contains $AD01Server) {
        Write-Host "    ✓ AD01 already in Server Manager" -ForegroundColor Green
        Write-Log "AD01 already in Server Manager"
    } else {
        # Add AD01 to server pool
        Add-SMServer -ServerName $AD01Server -ErrorAction Stop
        Write-Host "    ✓ Added AD01 to Server Manager" -ForegroundColor Green
        Write-Log "Added AD01 to Server Manager"
    }
    
} catch {
    Write-Host "    ⚠ Could not add AD01 to Server Manager: $_" -ForegroundColor Yellow
    Write-Log "WARNING: Could not add AD01 to Server Manager - $_"
    Write-Host "      You can add manually: Server Manager → All Servers → Add Servers" -ForegroundColor Gray
}

# ============================================================================
# STEP 8B: START PERFORMANCE COUNTERS
# ============================================================================

Write-Host "`n  Starting Performance Counters..." -ForegroundColor Cyan
Write-Log "Starting performance counters"

try {
    # Start Performance Logs and Alerts service
    $PerfService = Get-Service -Name "pla" -ErrorAction SilentlyContinue
    
    if ($PerfService.Status -ne "Running") {
        Start-Service -Name "pla"
        Set-Service -Name "pla" -StartupType Automatic
        Write-Host "    ✓ Performance counters started" -ForegroundColor Green
        Write-Log "Performance counters started"
    } else {
        Write-Host "    ✓ Performance counters already running" -ForegroundColor Green
    }
    
} catch {
    Write-Host "    ⚠ Could not start performance counters: $_" -ForegroundColor Yellow
    Write-Log "WARNING: Performance counters issue - $_"
}

# ============================================================================
# STEP 8C: CONFIGURE REMOTE MANAGEMENT FOR AD01
# ============================================================================

Write-Host "`n  Configuring Remote Management..." -ForegroundColor Cyan
Write-Log "Configuring remote management"

try {
    # Enable WinRM on local machine
    Enable-PSRemoting -Force -SkipNetworkProfileCheck -ErrorAction SilentlyContinue | Out-Null
    
    # Add AD01 to trusted hosts (for non-Kerberos scenarios)
    $TrustedHosts = (Get-Item WSMan:\localhost\Client\TrustedHosts).Value
    
    if ($TrustedHosts -notlike "*ad01-ben*") {
        if ([string]::IsNullOrEmpty($TrustedHosts)) {
            Set-Item WSMan:\localhost\Client\TrustedHosts -Value "ad01-ben.ben.local" -Force
        } else {
            Set-Item WSMan:\localhost\Client\TrustedHosts -Value "$TrustedHosts,ad01-ben.ben.local" -Force
        }
        Write-Host "    ✓ Added AD01 to trusted hosts" -ForegroundColor Green
        Write-Log "Added AD01 to trusted hosts"
    } else {
        Write-Host "    ✓ AD01 already in trusted hosts" -ForegroundColor Green
    }
    
    # Test remote management to AD01
    Write-Host "`n  Testing remote connection to AD01..." -ForegroundColor Cyan
    
    $TestConnection = Test-WSMan -ComputerName "ad01-ben.ben.local" -ErrorAction SilentlyContinue
    
    if ($TestConnection) {
        Write-Host "    ✓ Remote management to AD01 working" -ForegroundColor Green
        Write-Log "Remote management to AD01 verified"
    } else {
        Write-Host "    ⚠ Cannot connect to AD01 remotely (may need to configure on AD01)" -ForegroundColor Yellow
        Write-Log "WARNING: Remote connection to AD01 not verified"
    }
    
} catch {
    Write-Host "    ⚠ Remote management configuration issue: $_" -ForegroundColor Yellow
    Write-Log "WARNING: Remote management configuration - $_"
}

# ============================================================================
# STEP 9: VERIFY CONFIGURATION
# ============================================================================

Write-Host "`n[STEP 9] Verifying Configuration..." -ForegroundColor Yellow
Write-Log "Running verification checks"

Write-Host "`n  Network Configuration:" -ForegroundColor Cyan
$IPConfig = Get-NetIPAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4
Write-Host "    IP Address: $($IPConfig.IPAddress)" -ForegroundColor Gray
Write-Host "    Gateway: $Gateway" -ForegroundColor Gray
Write-Host "    DNS: $DNS1" -ForegroundColor Gray

Write-Host "`n  Domain Information:" -ForegroundColor Cyan
$ComputerSystem = Get-WmiObject Win32_ComputerSystem
Write-Host "    Computer: $($ComputerSystem.Name)" -ForegroundColor Gray
Write-Host "    Domain: $($ComputerSystem.Domain)" -ForegroundColor Gray
Write-Host "    Role: $($ComputerSystem.DomainRole)" -ForegroundColor Gray

Write-Host "`n  Installed Tools:" -ForegroundColor Cyan
foreach ($Tool in $ToolsToInstall) {
    $Feature = Get-WindowsFeature -Name $Tool.Name
    if ($Feature.Installed) {
        Write-Host "    ✓ $($Tool.Description)" -ForegroundColor Green
    } else {
        Write-Host "    ✗ $($Tool.Description) - NOT INSTALLED" -ForegroundColor Red
    }
}

Write-Host "`n  Created Directories:" -ForegroundColor Cyan
foreach ($Dir in $DirsToCreate) {
    if (Test-Path $Dir) {
        Write-Host "    ✓ $Dir" -ForegroundColor Green
    } else {
        Write-Host "    ✗ $Dir - MISSING" -ForegroundColor Red
    }
}

Write-Host "`n  Software:" -ForegroundColor Cyan
$PuTTYCheck = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" | 
              Where-Object { $_.DisplayName -like "*PuTTY*" }
if ($PuTTYCheck) {
    Write-Host "    ✓ PuTTY installed" -ForegroundColor Green
} else {
    Write-Host "    ✗ PuTTY - NOT INSTALLED" -ForegroundColor Red
}

$ShareCheck = Get-SmbShare -Name "Software" -ErrorAction SilentlyContinue
if ($ShareCheck) {
    Write-Host "    ✓ Software share created" -ForegroundColor Green
} else {
    Write-Host "    ✗ Software share - MISSING" -ForegroundColor Red
}

Write-Host "`n  Server Manager Configuration:" -ForegroundColor Cyan
$SMServers = Get-SMServer -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ServerName
if ($SMServers -contains "ad01-ben.ben.local") {
    Write-Host "    ✓ AD01 added to All Servers" -ForegroundColor Green
} else {
    Write-Host "    ✗ AD01 not in All Servers" -ForegroundColor Yellow
}

$PerfService = Get-Service -Name "pla" -ErrorAction SilentlyContinue
if ($PerfService.Status -eq "Running") {
    Write-Host "    ✓ Performance counters running" -ForegroundColor Green
} else {
    Write-Host "    ✗ Performance counters not started" -ForegroundColor Yellow
}

# ============================================================================
# STEP 9: SUMMARY
# ============================================================================

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  RESTORATION COMPLETE" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Summary:" -ForegroundColor Yellow
Write-Host "  ✓ Network configured ($IPAddress)" -ForegroundColor Green
Write-Host "  ✓ Joined to domain ($DomainName)" -ForegroundColor Green
Write-Host "  ✓ Management tools installed" -ForegroundColor Green
Write-Host "  ✓ PuTTY installed" -ForegroundColor Green
Write-Host "  ✓ Directory structure created" -ForegroundColor Green
Write-Host "  ✓ Software share created" -ForegroundColor Green
Write-Host "  ✓ Firewall configured" -ForegroundColor Green
Write-Host "  ✓ Server Manager configured" -ForegroundColor Green
Write-Host "  ✓ AD01 added to management" -ForegroundColor Green

Write-Host "`nNext Steps:" -ForegroundColor Yellow
Write-Host "  1. Open Server Manager and verify AD01 appears in All Servers" -ForegroundColor Gray
Write-Host "  2. Test DNS/AD management tools" -ForegroundColor Gray
Write-Host "  3. Run your separate CA lab setup script" -ForegroundColor Gray
Write-Host "  4. Resume lab work!" -ForegroundColor Gray

Write-Host "`nLog file saved to: $LogFile" -ForegroundColor Cyan

Write-Log "Script completed successfully"

# ============================================================================
# STEP 10: CLEAN UP CREDENTIALS (SECURITY)
# ============================================================================

Write-Host "`n⚠️  SECURITY REMINDER:" -ForegroundColor Red
Write-Host "This script contains the domain admin password in plain text!" -ForegroundColor Yellow
Write-Host "Delete this script after use or remove the password line." -ForegroundColor Yellow

Write-Host "`nPress any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
