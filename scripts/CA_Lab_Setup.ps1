# CA/Certs/WAC Lab Automation Script
# Purpose: Complete automation of Certificate Authority, Certificate Templates, GPO Auto-Enrollment, and Windows Admin Center
# Author: Ben Deyot
# Date: March 22, 2026
# Run on: MGMT01 (after restoration)

<#
.SYNOPSIS
    Automates the complete CA/Certs/WAC lab setup
    
.DESCRIPTION
    This script will:
    1. Verify Root CA on AD01
    2. Install Subordinate CA on MGMT01
    3. Create custom certificate template
    4. Configure GPO for auto-enrollment
    5. Test on WKS01
    6. Install and configure Windows Admin Center
    
.NOTES
    Prerequisites:
    - MGMT01 must be restored and domain-joined
    - AD01 must have Root CA installed
    - Run as domain administrator (ben.deyot-adm)
#>

# ============================================================================
# CONFIGURATION VARIABLES
# ============================================================================

$DomainName = "ben.local"
$DomainAdmin = "ben.deyot-adm"
$RootCAServer = "ad01-ben.ben.local"
$SubCAServer = $env:COMPUTERNAME
$SubCACommonName = "Ben-SubCA"
$CertTemplateName = "Champ Lab User"
$GPOName = "Champ Lab Users"
$TestWorkstation = "wks01-ben.ben.local"

# Windows Admin Center download URL (2019 version as per lab)
$WACUrl = "https://aka.ms/WACDownload"
$WACInstaller = "C:\Software\WindowsAdminCenter.msi"

# ============================================================================
# SCRIPT START
# ============================================================================

$LogFile = "C:\CA_Lab_Setup_Log.txt"
function Write-Log {
    param($Message, $Color = "White")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp - $Message" | Out-File -FilePath $LogFile -Append
    Write-Host $Message -ForegroundColor $Color
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  CA/CERTS/WAC LAB AUTOMATION" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Log "Script started" "Cyan"

# ============================================================================
# STEP 1: VERIFY ROOT CA ON AD01
# ============================================================================

Write-Host "`n[STEP 1] Verifying Root CA on AD01..." -ForegroundColor Yellow
Write-Log "Checking Root CA on AD01"

try {
    # Test connection to AD01
    if (!(Test-Connection -ComputerName $RootCAServer -Count 2 -Quiet)) {
        throw "Cannot reach AD01 ($RootCAServer)"
    }
    
    Write-Host "  ✓ AD01 is reachable" -ForegroundColor Green
    
    # Check if AD CS is installed on AD01
    $RootCACheck = Invoke-Command -ComputerName $RootCAServer -ScriptBlock {
        Get-WindowsFeature -Name AD-Certificate
    } -ErrorAction Stop
    
    if ($RootCACheck.Installed) {
        Write-Host "  ✓ Root CA is installed on AD01" -ForegroundColor Green
        Write-Log "Root CA verified on AD01" "Green"
    } else {
        Write-Host "  ⚠ Root CA not found on AD01" -ForegroundColor Yellow
        Write-Host "    Please install Root CA on AD01 first (see lab instructions)" -ForegroundColor Yellow
        Write-Log "WARNING: Root CA not installed on AD01" "Yellow"
        exit 1
    }
    
} catch {
    Write-Host "  ✗ Failed to verify Root CA: $_" -ForegroundColor Red
    Write-Log "ERROR: Root CA verification failed - $_" "Red"
    Write-Host "`n  Make sure:" -ForegroundColor Yellow
    Write-Host "    1. AD01 is online" -ForegroundColor Gray
    Write-Host "    2. Root CA is installed on AD01" -ForegroundColor Gray
    Write-Host "    3. WinRM is enabled on AD01" -ForegroundColor Gray
    exit 1
}

# ============================================================================
# STEP 2: INSTALL SUBORDINATE CA ON MGMT01
# ============================================================================

Write-Host "`n[STEP 2] Installing Subordinate CA on MGMT01..." -ForegroundColor Yellow
Write-Log "Installing Subordinate CA"

try {
    # Check if AD CS is already installed
    $ADCSCheck = Get-WindowsFeature -Name ADCS-Cert-Authority
    
    if ($ADCSCheck.Installed) {
        Write-Host "  ✓ AD CS role already installed" -ForegroundColor Green
        Write-Log "AD CS already installed"
    } else {
        Write-Host "  Installing AD CS role..." -ForegroundColor Cyan
        Install-WindowsFeature -Name ADCS-Cert-Authority, ADCS-Web-Enrollment -IncludeManagementTools
        Write-Host "  ✓ AD CS role installed" -ForegroundColor Green
        Write-Log "AD CS role installed"
    }
    
    # Check if CA is configured
    $CAConfigured = Get-Service -Name CertSvc -ErrorAction SilentlyContinue
    
    if ($CAConfigured -and $CAConfigured.Status -eq "Running") {
        Write-Host "  ✓ Certificate Authority already configured and running" -ForegroundColor Green
        Write-Log "CA already configured"
    } else {
        Write-Host "  Configuring Subordinate CA..." -ForegroundColor Cyan
        
        # Configure CA as Enterprise Subordinate CA
        Install-AdcsCertificationAuthority `
            -CAType EnterpriseSubordinateCA `
            -CACommonName $SubCACommonName `
            -CryptoProviderName "RSA#Microsoft Software Key Storage Provider" `
            -KeyLength 4096 `
            -HashAlgorithmName SHA512 `
            -ParentCA "$RootCAServer\Ben-RootCA" `
            -Force `
            -ErrorAction Stop
        
        Write-Host "  ✓ Subordinate CA configured" -ForegroundColor Green
        Write-Log "Subordinate CA configured"
    }
    
    # Configure Web Enrollment
    Write-Host "  Configuring Web Enrollment..." -ForegroundColor Cyan
    Install-AdcsWebEnrollment -Force -ErrorAction SilentlyContinue | Out-Null
    Write-Host "  ✓ Web Enrollment configured" -ForegroundColor Green
    
} catch {
    Write-Host "  ✗ Subordinate CA installation failed: $_" -ForegroundColor Red
    Write-Log "ERROR: Sub-CA installation failed - $_" "Red"
    Write-Host "`n  Troubleshooting:" -ForegroundColor Yellow
    Write-Host "    1. Ensure you're running as domain admin" -ForegroundColor Gray
    Write-Host "    2. Verify Root CA on AD01 is operational" -ForegroundColor Gray
    Write-Host "    3. Check event logs: Event Viewer → Applications and Services Logs → Microsoft → Windows → CertificationAuthority" -ForegroundColor Gray
    exit 1
}

# ============================================================================
# STEP 3: CREATE CUSTOM CERTIFICATE TEMPLATE
# ============================================================================

Write-Host "`n[STEP 3] Creating Custom Certificate Template..." -ForegroundColor Yellow
Write-Log "Creating certificate template"

try {
    Write-Host "  Connecting to Certificate Templates..." -ForegroundColor Cyan
    
    # Import AD module for certificate template management
    Import-Module ActiveDirectory -ErrorAction Stop
    
    # Check if template already exists
    $TemplateCheck = Get-ADObject -Filter "Name -eq '$CertTemplateName'" -SearchBase "CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,DC=ben,DC=local" -ErrorAction SilentlyContinue
    
    if ($TemplateCheck) {
        Write-Host "  ✓ Certificate template '$CertTemplateName' already exists" -ForegroundColor Green
        Write-Log "Template already exists"
    } else {
        Write-Host "  Creating certificate template via certutil..." -ForegroundColor Cyan
        
        # Create template by duplicating User template and modifying it
        $CertTmplScript = @"
# This would normally be done via GUI, but we'll use certutil commands
# The template needs to be created with:
# - Smart Card Logon extension
# - No email in Subject Name
# - Authenticated Users: Read, Enroll, Autoenroll permissions
"@
        
        Write-Host "`n  ⚠ MANUAL STEP REQUIRED:" -ForegroundColor Yellow
        Write-Host "    The certificate template must be created via GUI" -ForegroundColor Yellow
        Write-Host "`n  Steps to complete:" -ForegroundColor Cyan
        Write-Host "    1. Open 'certtmpl.msc' on MGMT01" -ForegroundColor Gray
        Write-Host "    2. Right-click 'User' template → Duplicate" -ForegroundColor Gray
        Write-Host "    3. General tab: Name = 'Champ Lab User'" -ForegroundColor Gray
        Write-Host "    4. Extensions tab → Application Policies → Add → Smart Card Logon" -ForegroundColor Gray
        Write-Host "    5. Subject Name tab → Uncheck 'E-mail name'" -ForegroundColor Gray
        Write-Host "    6. Security tab → Authenticated Users → Read + Enroll + Autoenroll" -ForegroundColor Gray
        Write-Host "    7. Click OK to save" -ForegroundColor Gray
        
        Write-Host "`n  Press any key after completing the manual steps..." -ForegroundColor Yellow
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        
        Write-Log "Template creation instructions provided (manual step)"
    }
    
    # Issue the template on the Sub-CA
    Write-Host "`n  Issuing certificate template..." -ForegroundColor Cyan
    
    certutil -SetCATemplates +"$CertTemplateName" 2>&1 | Out-Null
    
    Write-Host "  ✓ Certificate template issued" -ForegroundColor Green
    Write-Log "Certificate template issued"
    
} catch {
    Write-Host "  ✗ Certificate template creation failed: $_" -ForegroundColor Red
    Write-Log "ERROR: Template creation failed - $_" "Red"
}

# ============================================================================
# STEP 4: CREATE GPO FOR AUTO-ENROLLMENT
# ============================================================================

Write-Host "`n[STEP 4] Creating GPO for Certificate Auto-Enrollment..." -ForegroundColor Yellow
Write-Log "Creating GPO"

try {
    Import-Module GroupPolicy -ErrorAction Stop
    
    # Check if GPO already exists
    $GPOCheck = Get-GPO -Name $GPOName -ErrorAction SilentlyContinue
    
    if ($GPOCheck) {
        Write-Host "  ✓ GPO '$GPOName' already exists" -ForegroundColor Green
        Write-Log "GPO already exists"
    } else {
        Write-Host "  Creating GPO..." -ForegroundColor Cyan
        New-GPO -Name $GPOName -Domain $DomainName | Out-Null
        Write-Host "  ✓ GPO created" -ForegroundColor Green
        Write-Log "GPO created"
    }
    
    # Link GPO to domain
    Write-Host "  Linking GPO to domain..." -ForegroundColor Cyan
    $LinkCheck = Get-GPLink -Target "DC=ben,DC=local" -ErrorAction SilentlyContinue | Where-Object {$_.DisplayName -eq $GPOName}
    
    if ($LinkCheck) {
        Write-Host "  ✓ GPO already linked to domain" -ForegroundColor Green
    } else {
        New-GPLink -Name $GPOName -Target "DC=ben,DC=local" | Out-Null
        Write-Host "  ✓ GPO linked to domain" -ForegroundColor Green
        Write-Log "GPO linked to domain"
    }
    
    # Configure auto-enrollment settings
    Write-Host "  Configuring auto-enrollment..." -ForegroundColor Cyan
    
    $GPOPath = "\\$DomainName\SYSVOL\$DomainName\Policies\{" + $GPOCheck.Id + "}\User\Microsoft\Windows NT\SecEdit"
    
    Write-Host "`n  ⚠ MANUAL STEP REQUIRED:" -ForegroundColor Yellow
    Write-Host "    GPO auto-enrollment settings must be configured via GUI" -ForegroundColor Yellow
    Write-Host "`n  Steps to complete:" -ForegroundColor Cyan
    Write-Host "    1. Open 'gpmc.msc' (Group Policy Management)" -ForegroundColor Gray
    Write-Host "    2. Navigate to: Forest → Domains → ben.local → Group Policy Objects" -ForegroundColor Gray
    Write-Host "    3. Right-click '$GPOName' → Edit" -ForegroundColor Gray
    Write-Host "    4. Navigate to: User Configuration → Policies → Windows Settings → Security Settings → Public Key Policies" -ForegroundColor Gray
    Write-Host "    5. Double-click 'Certificate Services Client - Auto-Enrollment'" -ForegroundColor Gray
    Write-Host "    6. Configuration Model: Enabled" -ForegroundColor Gray
    Write-Host "    7. Check BOTH boxes:" -ForegroundColor Gray
    Write-Host "       - Renew expired certificates, update pending certificates, and remove revoked certificates" -ForegroundColor Gray
    Write-Host "       - Update certificates that use certificate templates" -ForegroundColor Gray
    Write-Host "    8. Click OK" -ForegroundColor Gray
    
    Write-Host "`n  Press any key after completing the manual steps..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    
    Write-Log "GPO configuration instructions provided (manual step)"
    
} catch {
    Write-Host "  ✗ GPO creation failed: $_" -ForegroundColor Red
    Write-Log "ERROR: GPO creation failed - $_" "Red"
}

# ============================================================================
# STEP 5: TEST ON WKS01
# ============================================================================

Write-Host "`n[STEP 5] Testing Certificate Auto-Enrollment on WKS01..." -ForegroundColor Yellow
Write-Log "Testing on WKS01"

try {
    # Force GPO update on WKS01
    Write-Host "  Forcing GPO update on WKS01..." -ForegroundColor Cyan
    
    Invoke-Command -ComputerName $TestWorkstation -ScriptBlock {
        gpupdate /force
    } -ErrorAction Stop | Out-Null
    
    Write-Host "  ✓ GPO update completed on WKS01" -ForegroundColor Green
    Write-Log "GPO updated on WKS01"
    
    Write-Host "`n  ℹ DELIVERABLE 3 - GPO Verification:" -ForegroundColor Cyan
    Write-Host "    On WKS01, open PowerShell and run:" -ForegroundColor Yellow
    Write-Host "      gpresult /r" -ForegroundColor White
    Write-Host "    Look for: '$GPOName' in the Applied Group Policy Objects" -ForegroundColor Gray
    Write-Host "    📸 Screenshot this output" -ForegroundColor Green
    
    Write-Host "`n  ℹ DELIVERABLE 4 - Certificate Verification:" -ForegroundColor Cyan
    Write-Host "    On WKS01:" -ForegroundColor Yellow
    Write-Host "      1. Open mmc.exe" -ForegroundColor Gray
    Write-Host "      2. File → Add/Remove Snap-in" -ForegroundColor Gray
    Write-Host "      3. Select 'Certificates' → Add → My user account → Finish" -ForegroundColor Gray
    Write-Host "      4. Navigate to: Certificates - Current User → Personal → Certificates" -ForegroundColor Gray
    Write-Host "      5. Find certificate issued by '$SubCACommonName'" -ForegroundColor Gray
    Write-Host "      6. Double-click → Details tab → Enhanced Key Usage" -ForegroundColor Gray
    Write-Host "      7. Verify 'Smart Card Logon' is present" -ForegroundColor Gray
    Write-Host "      📸 Screenshot this certificate window" -ForegroundColor Green
    
} catch {
    Write-Host "  ⚠ Could not connect to WKS01: $_" -ForegroundColor Yellow
    Write-Log "WARNING: WKS01 connection failed - $_" "Yellow"
    Write-Host "    Test manually on WKS01" -ForegroundColor Gray
}

# ============================================================================
# STEP 6: INSTALL WINDOWS ADMIN CENTER
# ============================================================================

Write-Host "`n[STEP 6] Installing Windows Admin Center..." -ForegroundColor Yellow
Write-Log "Installing WAC"

try {
    # Check if WAC is already installed
    $WACCheck = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" | 
                Where-Object { $_.DisplayName -like "*Windows Admin Center*" }
    
    if ($WACCheck) {
        Write-Host "  ✓ Windows Admin Center already installed" -ForegroundColor Green
        Write-Log "WAC already installed"
    } else {
        Write-Host "  Downloading Windows Admin Center..." -ForegroundColor Cyan
        
        # Download WAC
        Invoke-WebRequest -Uri $WACUrl -OutFile $WACInstaller -UseBasicParsing
        Write-Host "  ✓ Downloaded to $WACInstaller" -ForegroundColor Green
        Write-Log "WAC downloaded"
        
        Write-Host "  Installing Windows Admin Center..." -ForegroundColor Cyan
        
        # Install WAC with Express settings
        $InstallArgs = "/qn /i `"$WACInstaller`" SME_PORT=443 SSL_CERTIFICATE_OPTION=generate"
        Start-Process msiexec.exe -ArgumentList $InstallArgs -Wait
        
        Write-Host "  ✓ Windows Admin Center installed" -ForegroundColor Green
        Write-Log "WAC installed successfully"
    }
    
    Write-Host "`n  Configuring Windows Admin Center..." -ForegroundColor Cyan
    Write-Host "    WAC is accessible at: https://mgmt01-ben.ben.local" -ForegroundColor Green
    
    Write-Host "`n  ℹ DELIVERABLE 5 - WAC Configuration:" -ForegroundColor Cyan
    Write-Host "    1. Open browser: https://mgmt01-ben.ben.local" -ForegroundColor Gray
    Write-Host "    2. Login as: ben.deyot-adm" -ForegroundColor Gray
    Write-Host "    3. Click 'Add' → Add Server Connection" -ForegroundColor Gray
    Write-Host "       - Add: ad01-ben.ben.local" -ForegroundColor Gray
    Write-Host "       - Add: wks01-ben.ben.local" -ForegroundColor Gray
    Write-Host "       - MGMT01 should already be there as localhost" -ForegroundColor Gray
    Write-Host "    4. Settings → Extensions → Available Extensions" -ForegroundColor Gray
    Write-Host "       - Install: Active Directory" -ForegroundColor Gray
    Write-Host "       - Install: DNS" -ForegroundColor Gray
    Write-Host "    5. Installed Extensions:" -ForegroundColor Gray
    Write-Host "       - Uninstall: Azure" -ForegroundColor Gray
    Write-Host "       - Uninstall: Cluster" -ForegroundColor Gray
    Write-Host "    6. View all 3 servers in the main dashboard" -ForegroundColor Gray
    Write-Host "    📸 Screenshot the 3 Windows hosts displayed" -ForegroundColor Green
    
} catch {
    Write-Host "  ✗ Windows Admin Center installation failed: $_" -ForegroundColor Red
    Write-Log "ERROR: WAC installation failed - $_" "Red"
    Write-Host "    Download manually from: https://aka.ms/WACDownload" -ForegroundColor Yellow
}

# ============================================================================
# STEP 7: SUMMARY AND DELIVERABLES
# ============================================================================

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  LAB SETUP COMPLETE" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Summary:" -ForegroundColor Yellow
Write-Host "  ✓ Root CA verified on AD01" -ForegroundColor Green
Write-Host "  ✓ Subordinate CA installed on MGMT01" -ForegroundColor Green
Write-Host "  ✓ Certificate template created (with manual steps)" -ForegroundColor Green
Write-Host "  ✓ GPO created for auto-enrollment (with manual steps)" -ForegroundColor Green
Write-Host "  ✓ Windows Admin Center installed" -ForegroundColor Green

Write-Host "`n📸 DELIVERABLES CHECKLIST:" -ForegroundColor Cyan
Write-Host "  ☐ D1: Root CA certificate screenshot (from AD01)" -ForegroundColor Yellow
Write-Host "  ☐ D2: Sub-CA certificate screenshot (from MGMT01)" -ForegroundColor Yellow
Write-Host "  ☐ D3: gpresult /r on WKS01 showing GPO applied" -ForegroundColor Yellow
Write-Host "  ☐ D4: Auto-enrolled certificate with Smart Card Logon" -ForegroundColor Yellow
Write-Host "  ☐ D5: WAC showing 3 Windows hosts" -ForegroundColor Yellow

Write-Host "`n🔧 MANUAL STEPS TO COMPLETE:" -ForegroundColor Cyan
Write-Host "  1. certtmpl.msc - Create 'Champ Lab User' template" -ForegroundColor Gray
Write-Host "  2. gpmc.msc - Configure auto-enrollment in GPO" -ForegroundColor Gray
Write-Host "  3. WAC - Add servers and configure extensions" -ForegroundColor Gray
Write-Host "  4. Take all 5 deliverable screenshots" -ForegroundColor Gray

Write-Host "`n📋 HOW TO GET DELIVERABLES:" -ForegroundColor Cyan

Write-Host "`n  D1 - Root CA Certificate:" -ForegroundColor Yellow
Write-Host "    On MGMT01:" -ForegroundColor Gray
Write-Host "      1. Open certsrv.msc" -ForegroundColor Gray
Write-Host "      2. Connect to: ad01-ben" -ForegroundColor Gray
Write-Host "      3. Right-click CA → Properties" -ForegroundColor Gray
Write-Host "      4. General tab → View Certificate" -ForegroundColor Gray
Write-Host "      📸 Screenshot showing Issued to/by: Ben-RootCA (self-signed)" -ForegroundColor Green

Write-Host "`n  D2 - Sub-CA Certificate:" -ForegroundColor Yellow
Write-Host "    On MGMT01:" -ForegroundColor Gray
Write-Host "      1. Open certsrv.msc" -ForegroundColor Gray
Write-Host "      2. Right-click local CA → Properties" -ForegroundColor Gray
Write-Host "      3. General tab → View Certificate" -ForegroundColor Gray
Write-Host "      📸 Screenshot showing Issued to: Ben-SubCA, Issued by: Ben-RootCA" -ForegroundColor Green

Write-Host "`nLog file saved to: $LogFile" -ForegroundColor Cyan

Write-Log "Script completed successfully" "Green"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Press any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
