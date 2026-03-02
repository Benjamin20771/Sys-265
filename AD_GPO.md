# LAB - Active Directory Group Policy & Software Deployment

## Summary
This lab demonstrated using Active Directory Group Policy Objects (GPOs) to automate software deployment across domain-joined computers. 
I created Organizational Units using PowerShell, established a network share for software distribution, configured a GPO to automatically deploy PuTTY to WKS01, and verified successful installation through Event Viewer using both GUI and PowerShell methods.

## Part 1: Creating OUs with PowerShell

### Creating Test OU (GUI)

**On MGMT01 via Active Directory Users and Computers:**
- Created "Test OU" at domain root
- Unchecked "Protect container from accidental deletion" (required for later PowerShell deletion)

### Remote PowerShell Management

**From WKS01, connected to AD01:**

```powershell
Enter-PSSession -ComputerName AD01-Ben
```

This established a remote PowerShell session to AD01, allowing management without RDP.

### Creating Software Deploy OU

```powershell
New-ADOrganizationalUnit -Name "Software Deploy" -Path "DC=ben,DC=local"
Get-ADOrganizationalUnit -Filter 'Name -like "Software Deploy"'
```

The `-Path` parameter uses LDAP Distinguished Name format, where `DC=ben,DC=local` represents the ben.local domain root.

### Moving Objects Between OUs

**Moved WKS01 computer:**
```powershell
Move-ADObject -Identity "CN=WKS01-Ben,CN=Computers,DC=ben,DC=local" -TargetPath "OU=Software Deploy,DC=ben,DC=local"
```

**Moved user account:**
```powershell
Move-ADObject -Identity "CN=ben.deyot,CN=Users,DC=ben,DC=local" -TargetPath "OU=Software Deploy,DC=ben,DC=local"
```

Distinguished Names uniquely identify objects in Active Directory. Format: `CN=ObjectName,OU=OUName,DC=domain,DC=local`

### Deleting Test OU

```powershell
# Disable protection first
Set-ADOrganizationalUnit -Identity "OU=Test OU,DC=ben,DC=local" -ProtectedFromAccidentalDeletion $false

# Delete
Remove-ADOrganizationalUnit -Identity "OU=Test OU,DC=ben,DC=local" -Confirm:$false
```

The `-Confirm:$false` parameter skips the confirmation prompt.

## Part 2: Software Share Setup

### Downloaded PuTTY

**On MGMT01:**
- Downloaded `putty-64bit-0.80-installer.msi` from the official site
- Placed in `C:\Software\`

**Why .msi is required:** Group Policy software deployment requires Windows Installer packages. MSI files support silent installation, rollback, and state tracking - essential for automated deployment.

### Created Network Share

1. Right-clicked `C:\Software` → Properties → Sharing → Advanced Sharing
2. Share name: `Software`
3. Permissions: Everyone - Read
4. UNC path: `\\MGMT01-Ben\Software`

**Why Everyone - Read is safe:** Combined with NTFS permissions, this allows domain computer accounts (like `BEN\WKS01-Ben$`) to access the share during GPO application.

### Tested Share Access

From WKS01, accessed `\\MGMT01-Ben\Software` and verified PuTTY .msi was visible.

## Part 3: Group Policy Management

### Challenge: MGMT01 Feature Installation Failed

Attempted to install Group Policy Management Console on MGMT01:

```powershell
Install-WindowsFeature -Name GPMC
```

**Error received:** 0x80073701 - "The referenced assembly could not be found."

**Root cause:** MGMT01's Windows component store was corrupted. DISM repair attempts failed because source files were missing.

**Solution:** Installed RSAT (Remote Server Administration Tools) on WKS01 instead.

**This is actually best practice** - administrators typically manage servers from workstations, not by logging into servers directly.

### Installing GPMC on WKS01

**Settings → Apps → Optional features → Add a feature:**
- Selected "RSAT: Group Policy Management Tools"
- Installed successfully in 2-3 minutes

## Part 4: Creating and Deploying GPO

### Created GPO

**On WKS01 via Group Policy Management:**

1. Navigated to Software Deploy OU
2. Right-clicked → "Create a GPO in this domain, and Link it here..."
3. Name: `Deploy SW`

### Configured Software Installation

1. Right-clicked Deploy SW → Edit
2. **Computer Configuration** → Policies → Software Settings → Software installation
3. Right-clicked → New → Package
4. Entered UNC path: `\\MGMT01-Ben\Software`
5. Selected PuTTY .msi file
6. Deployment method: **Assigned**

**Why UNC path matters:** GPO executes on the target computer during startup. Local paths like `C:\Software` wouldn't work because the computer needs to access the file from MGMT01's share.

**Assigned vs Published:**
- Assigned (Computer): Installs automatically at startup
- Published: Available for optional installation in the Control Panel

### Applied GPO

**On WKS01, Command Prompt as Administrator:**

```cmd
gpupdate /force
shutdown /r /t 10
```

During the restart, Windows installed PuTTY automatically via Group Policy before the login screen appeared.

**Verified installation:** Opened Start menu, typed "putty" - application appeared.

## Part 5: Event Log Verification

### Method 1: Event Viewer GUI

1. Opened Event Viewer → Windows Logs → System
2. Actions → Filter Current Log
3. Event sources: "Application Management Group Policy."
4. Found event with message: "The installation of application PuTTY release 0.80 (64-bit) from policy Deploy SW succeeded."

### Method 2: PowerShell

```powershell
Get-WinEvent -FilterHashtable @{
    LogName='System';
    ProviderName='Application Management Group Policy'
} | Where-Object {$_.Message -like "*PuTTY*succeeded*"} | Select-Object TimeCreated, Message | Format-List
```

**Command breakdown:**
- `Get-WinEvent` - Modern cmdlet for querying event logs
- `-FilterHashtable` - Efficient filtering at the source (not in pipeline)
- `Where-Object` - Additional filtering for specific message text
- `Format-List` - Display output in a readable list format

**Why FilterHashtable is better:** Filters at the event log service level before sending data to PowerShell, much faster than retrieving all events and filtering afterward.

## Research Topics

### Topic 1: Distinguished Names in Active Directory

**What I Didn't Know:**
How to construct and read the LDAP Distinguished Name format.

**Research Results:**

Distinguished Names uniquely identify objects using a hierarchical format:
- `CN=` Common Name (the object)
- `OU=` Organizational Unit
- `DC=` Domain Component

Read right to left: `CN=WKS01-Ben,OU=Software Deploy,DC=ben,DC=local`
- WKS01-Ben computer, in Software Deploy OU, in ben.local domain

**Why it matters:** PowerShell AD commands require exact Distinguished Names to ensure you're modifying the correct object, especially in large environments with duplicate names.

### Topic 2: Group Policy Processing Order

**What I Didn't Know:**
How Windows applies multiple GPOs and resolves conflicts.

**Research Results:**

GPOs apply in LSDOU order:
1. **L**ocal - Local Group Policy on the computer
2. **S**ite - Policies linked to AD site
3. **D**omain - Domain-level policies
4. **O**U - OU policies (parent to child)

Later policies override earlier ones. Can be modified with:
- **Enforced** - GPO cannot be overridden by child OUs
- **Block Inheritance** - OU blocks parent GPO inheritance

**Why it matters:** Understanding processing order is critical for troubleshooting why settings aren't applying correctly in complex environments with multiple GPOs.

## Challenges Encountered

### Challenge 1: MGMT01 Component Store Corruption

**Problem:** Could not install GPMC on MGMT01. Error 0x80073701 indicated missing assembly files.

**Attempted solutions:**
- DISM /RestoreHealth - failed (source files not found)
- Installing .NET Framework - failed with the same error
- Windows Update - no improvement

**Solution:** Installed RSAT on WKS01 instead. This actually follows IT best practice. Manage servers remotely from workstations rather than logging into servers directly.

## Conclusion

This lab demonstrated centralized software deployment through Active Directory Group Policy. 
Combining PowerShell automation for OU management, network file sharing for software distribution, and GPO configuration for automatic deployment.
- GPO software deployment eliminates manual installation on individual computers
- MSI packages provide standardized, silent installation for automated deployment
- Event logs with PowerShell queries enable verification and troubleshooting at scale
- Pragmatic problem-solving often means finding alternative approaches rather than fixing every issue

This lab overall helps with pushing out installations over a large area and for future labs as well. Automation is something to remember for this...
