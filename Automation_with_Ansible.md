# LAB - Automation with Ansible

## Summary
In this lab, I implemented Ansible automation across heterogeneous systems, including three Linux servers (Ubuntu) and two Windows workstations. 
I created a reusable Linux onboarding script to automate initial system configuration, reducing deployment time from 30 minutes to under 5 minutes per system. 
Using Ansible, we deployed services to Linux hosts via Galaxy roles (Webmin and Apache), configured passwordless SSH authentication with passphrase-protected keys and an SSH agent, and automated Windows software deployment through Chocolatey package management. 

## Part 1: Linux Onboarding Script

### linux-onboard.sh

I created an interactive bash script that automates the entire onboarding process through a question-and-answer interface. 
The script handles both Ubuntu and Rocky Linux distributions.

**Link to script on GitHub:** [Script](https://github.com/Benjamin20771/Sys-265/blob/main/scripts/linux-onboard.sh)

### Script Features

**Interactive Configuration:**
The script asks questions and validates all inputs before making changes:

```
=== Network Configuration ===
Detected network interface: ens18
Use detected interface (ens18)? (Y/n): y

Do you want to use DHCP (automatic IP)? (y/N): n

What is the IP address for this system?: 10.0.5.90
You entered: 10.0.5.90
Is this correct? (Y/n): y

What is the subnet mask in CIDR notation?: 24
What is the gateway IP address?: 10.0.5.2
What is the PRIMARY DNS server IP?: 10.0.5.5
Do you want to configure a secondary DNS server? (y/N): n
What is the domain name?: ben.local

=== System Identity ===
What should the hostname be?: controller-Ben

=== User Configuration ===
What is the username for the first user?: Ben
Set password for Ben: [hidden]
Should Ben have sudo privileges? (Y/n): y

Do you want to create another user account? (y/N): y
What is the username for this user?: deployer
```

**Key Design Decisions:**

**1. DHCP vs Static IP Choice:**
The script asks if you want a DHCP or a static IP. For static, it prompts for all network details. For DHCP, it only asks for DNS and the domain. This flexibility allows the script to work in various environments.

**2. Optional Secondary DNS:**
Instead of requiring a secondary DNS server, the script asks if you want one. If you say no, it configures the system with only the primary DNS, avoiding unnecessary configuration.

**3. Input Validation:**
- IP addresses validated against a regex pattern
- Hostname validated for proper format (no spaces, valid characters)
- Passwords confirmed with re-entry
- Empty inputs rejected with error messages

**4. OS Detection:**
The script detects whether it's running on Ubuntu or Rocky Linux and adjusts its configuration commands accordingly:
- Ubuntu uses `netplan` and `apt`
- Rocky uses `nmcli` and `dnf`

### What the Script Does

**Network Configuration (Ubuntu):**
Creates netplan YAML configuration:
```
network:
  version: 2
  ethernets:
    ens18:
      dhcp4: no
      dhcp6: no
      addresses:
        - 10.0.5.90/24
      routes:
        - to: default
          via: 10.0.5.2
      nameservers:
        addresses:
          - 10.0.5.5
        search:
          - ben.local
```

Applies configuration with `netplan apply` and updates `/etc/resolv.conf`.

**Hostname Configuration:**
Sets hostname with `hostnamectl set-hostname` and updates `/etc/hosts`:
```
127.0.0.1 localhost
127.0.1.1 controller-Ben.ben.local controller-Ben
10.0.5.90 controller-Ben.ben.local controller-Ben
```

**User Creation:**
Creates users with home directories, sets passwords securely, adds to the sudo group, and sets the proper shell (`/bin/bash`).

**Passwordless Sudo:**
Creates `/etc/sudoers.d/sys265`:
```
deployer ALL=(ALL) NOPASSWD: ALL
```
This allows the deployer user to run sudo commands without password prompts, essential for Ansible automation.

**SSH Hardening:**
- Installs OpenSSH server
- Enables and starts sshd service
- Disables root SSH login (sets `PermitRootLogin no`)
- Configures firewall to allow port 22

**Firewall Configuration:**
- Ubuntu: Configures UFW, allows SSH
- Rocky: Configures firewalld, allows SSH service

**System Updates:**
Runs full system update:
- Ubuntu: `apt update && apt upgrade -y`
- Rocky: `dnf update -y`

**Connectivity Testing:**
Tests network configuration by pinging:
- Gateway
- DNS servers
- External connectivity (8.8.8.8)
- DNS resolution (google.com)

**Configuration Summary:**
Displays all settings before applying and asks for confirmation. Also provides detailed logging to `/var/log/linux-onboard.log`.

### Script Usage

**Deployment:**
```
# Clone repository
git clone https://github.com/Benjamin20771/Sys265
cd Sys265/scripts

# Make executable
chmod +x linux-onboard.sh

# Run as root
sudo ./linux-onboard.sh
```

## Part 2: Ansible Installation and Setup

### Installing Ansible on Controller

**Installation:**
```
sudo apt install ansible sshpass python3-paramiko -y
```

**Package Breakdown:**
- `ansible` - Core automation engine, includes modules and playbook functionality
- `sshpass` - Allows non-interactive SSH password authentication (used for initial key distribution)
- `python3-paramiko` - Python SSH library that Ansible uses for SSH connections

**Verification:**
```
ansible --version
```

Output shows:
- Ansible version (2.x.x)
- Python version
- Config file location (`/etc/ansible/ansible.cfg`)
- Module search paths

## Part 3: SSH Key Authentication Setup

### Generating SSH Keypair with Passphrase

**Why passphrase-protected keys:**
A private key without a passphrase is like leaving your house key under the doormat. Anyone who gets the file can use it. A passphrase encrypts the private key, so even if stolen, it's useless without the passphrase.

**Generation:**
```
ssh-keygen -t rsa -b 4096
# File location: /home/deployer/.ssh/id_rsa (default)
# Passphrase: [entered and confirmed]
```

**Parameters:**
- `-t rsa` - Use RSA algorithm
- `-b 4096` - 4096-bit key length (very secure)

**Files Created:**
- `~/.ssh/id_rsa` - Private key (NEVER share, NEVER commit to Git)
- `~/.ssh/id_rsa.pub` - Public key (safe to share)

### Distributing Public Keys

**Using ssh-copy-id:**
```
ssh-copy-id deployer@ansible1-Ben.ben.local
ssh-copy-id deployer@ansible2-Ben.ben.local
```

**What ssh-copy-id does:**
1. Connects via SSH (asks for password once)
2. Copies public key to `~/.ssh/authorized_keys` on remote host
3. Sets correct permissions (700 for .ssh, 600 for authorized_keys)
4. Appends key instead of overwriting (safe for multiple keys)

**Testing:**
```
ssh deployer@ansible1-Ben.ben.local
# Should login without password prompt
# (will ask for passphrase to decrypt private key)
```

### SSH Agent Configuration

**The Problem:**
With a passphrase-protected key, you'd need to enter the passphrase every time you SSH. For Ansible running 50 commands, that's 50 passphrase prompts.

**The Solution: SSH Agent**
SSH Agent decrypts the private key once, keeps it in memory, and reuses it for all SSH connections.

**Configuration in ~/.bashrc:**
```
# SSH Agent for Ansible
if ! pgrep -u "$USER" ssh-agent > /dev/null; then
    ssh-agent > ~/.ssh-agent-thing
fi
if [[ ! "$SSH_AUTH_SOCK" ]]; then
    eval "$(<~/.ssh-agent-thing)"
fi
ssh-add -l &>/dev/null || ssh-add -t 14400 ~/.ssh/id_rsa 2>/dev/null
```

**How it works:**
1. Checks if ssh-agent is running for this user
2. If not, starts ssh-agent and saves connection info
3. Loads the agent connection info
4. Checks if the key is already loaded
5. If not, loads the key with a 4-hour timeout (14400 seconds)

**Result:**
Enter passphrase once per session (or once every 4 hours). All subsequent SSH connections are passwordless and passphraseless.

**Security benefit:**
Still protected against key theft (passphrase required), but convenient for automation.

## Part 4: Ansible Inventory and Configuration

### Directory Structure

```
~/ansible-files/
├── inventory           # Host definitions
├── ansible.cfg         # Ansible settings
├── webmin.yml         # Webmin playbook
├── apache.yml         # Apache playbook
└── roles/
    └── windows_software.yml  # Chocolatey playbook
```

### Inventory File

**Purpose:**
Defines which hosts Ansible manages and organizes them into groups.

**Content:**
```
[linux]
ansible1-Ben.ben.local
ansible2-Ben.ben.local

[webmin]
ansible2-Ben.ben.local

[windows]
mgmt01-Ben.ben.local
wks01-Ben.ben.local

[windows:vars]
ansible_user=ben.deyot-adm
ansible_password=[classified]
ansible_connection=ssh
ansible_shell_type=powershell
```

**Key Concepts:**

**Groups:**
- `[linux]` - All Linux hosts
- `[webmin]` - Subset for Webmin installation (just ansible2)
- `[windows]` - All Windows hosts

**Group Variables (`[windows:vars]`):**
Variables that apply to all hosts in the Windows group:
- `ansible_user` - Username for authentication
- `ansible_password` - Password (in production, use vault encryption)
- `ansible_connection=ssh` - Use SSH instead of WinRM
- `ansible_shell_type=powershell` - Use PowerShell for commands

**Why SSH for Windows:**
Microsoft introduced OpenSSH for Windows as the modern remote management protocol. More secure than WinRM, it works through firewalls more easily, consistent with Linux management.

### Ansible Configuration File

**ansible.cfg:**
```
[defaults]
host_key_checking = False
```

**Purpose:**
Disables SSH host key verification. On first connection, SSH normally asks, "Are you sure you want to continue connecting?" This bypasses that prompt.

**Security Trade-off:**
Less secure (vulnerable to man-in-the-middle attacks) but convenient for lab environments where we're constantly rebuilding systems. In production, you'd pre-populate known_hosts or use proper key management.

### Testing Basic Connectivity

**Ansible Ping Module:**
```
ansible -i inventory all -m ping
```

**Expected output:**
```
ansible1-Ben.ben.local | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
ansible2-Ben.ben.local | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

**What "ping" does:**
NOT ICMP ping. Ansible's ping module:
1. Connects via SSH
2. Checks Python is installed
3. Runs a minimal Python script
4. Returns "pong" if successful

**"changed": false means:**
Ansible tracks whether operations change the system state. Ping doesn't change anything, so changed=false.

## Part 5: Ansible Playbooks and Roles

### Webmin Installation via Ansible Galaxy

**Ansible Galaxy:**
Community repository of pre-built Ansible roles (like Docker Hub for containers). Instead of writing installation steps from scratch, download a role that someone else built and tested.

**Installation:**
```
ansible-galaxy install semuadmin.webmin
```

**Playbook (webmin.yml):**
```
---
- name: Install Webmin
  hosts: webmin
  become: yes
  roles:
    - semuadmin.webmin
```

**YAML Syntax:**
- `---` - YAML document start
- `name` - Human-readable description
- `hosts: webmin` - Target the webmin group (ansible2)
- `become: yes` - Use sudo/root privileges
- `roles:` - Include external roles

**Execution:**
```
ansible-playbook -i inventory webmin.yml
```

**What happens:**
1. Ansible connects to ansible2 via SSH as deployer
2. Escalates to root (become: yes)
3. Downloads and executes the semuadmin.webmin role
4. Role installs Webmin package, configures service, and starts it
5. Reports success/failure

**Accessing Webmin:**
```
http://ansible2-Ben.ben.local:10000
Username: root
Password: deployer password
```

**Firewall Issue Encountered:**
Webmin was installed and running, but inaccessible from the browser. Rocky Linux's firewalld was blocking port 10000.

**Solution:**
```
sudo firewall-cmd --permanent --add-port=10000/tcp
sudo firewall-cmd --reload
```

**Lesson:** Always check the firewall after installing network services.

### Apache Web Server Installation

**Role:**
```
ansible-galaxy install geerlingguy.apache
```

**Playbook (apache.yml):**
```
---
- name: Install Apache Web Server
  hosts: ansible1-Ben.ben.local
  become: yes
  roles:
    - geerlingguy.apache
```

**Execution:**
```
ansible-playbook -i inventory apache.yml
```

**Result:**
Apache installed, configured, and started on ansible1. Default Rocky Linux test page accessible at `http://ansible1-Ben.ben.local`.

**Same firewall issue:**
Had to open HTTP port:
```
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --reload
```

**Why roles are powerful:**
The geerlingguy.apache role handles:
- Package installation (httpd on Rocky)
- Configuration files
- Service enablement
- Firewall rules (though this didn't work due to our specific setup)
- Multiple OS support (Ubuntu, CentOS, etc.)

## Part 6: Windows Automation

### Preparing Windows Hosts

**OpenSSH Installation on Windows:**

Modern Windows includes OpenSSH as an optional feature. Much better than WinRM for remote management.

**Installation (PowerShell as Administrator):**
```
# Add Windows capability
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

# Start service
Start-Service sshd

# Set automatic startup
Set-Service -Name sshd -StartupType 'Automatic'

# Verify
Get-Service sshd
```

**Setting PowerShell as Default Shell:**

By default, Windows SSH uses cmd.exe. Ansible needs PowerShell for Windows modules.

**Registry modification:**
```
# Enable console prompting
Set-ItemProperty "HKLM:\Software\Microsoft\Powershell\1\ShellIds" -Name ConsolePrompting -Value $true

# Create OpenSSH registry key
New-Item -Path "HKLM:\SOFTWARE\OpenSSH" -Force

# Set default shell
New-ItemProperty -Path HKLM:\SOFTWARE\OpenSSH -Name DefaultShell -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force
```

**Firewall Rule:**
```
New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
```

**Testing SSH:**
```
ssh ben.deyot-adm@mgmt01-Ben.ben.local
```

Should connect and show a PowerShell prompt.

**Challenge encountered:**
Registry path `HKLM:\SOFTWARE\OpenSSH` didn't exist, causing an error. Had to create it first with `New-Item` before setting the DefaultShell property.

### Windows Ansible Connectivity

**Testing with win_ping:**
```
ansible -i inventory windows -m win_ping
```

**Expected output:**
```
mgmt01-Ben.ben.local | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
wks01-Ben.ben.local | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

**DNS Challenge with wks01:**
WKS01 was on DHCP (10.0.5.150). Controller couldn't resolve `wks01-Ben.ben.local` initially.

**Problem:**
Controller's `/etc/resolv.conf` was pointing to systemd-resolved stub (127.0.0.53) instead of AD-01 (10.0.5.5).

**Solution:**
Verified netplan had correct DNS settings and applied the configuration. systemd-resolved then properly forwarded queries to AD-01, which resolved wks01's DHCP address.

**Verification:**
```
nslookup wks01-Ben.ben.local
# Returned: 10.0.5.150
```

### Software Deployment with Chocolatey

**Chocolatey:**
Windows package manager (like apt for Ubuntu, yum for CentOS). Community repository of software packages. Enables scripted, automated Windows software installation.

**Playbook (windows_software.yml):**
```
---
- name: Install Windows Software via Chocolatey
  hosts: windows
  tasks:
    - name: Install Chocolatey packages
      win_chocolatey:
        name:
          - 7zip
          - git
          - notepadplusplus
        state: present
```

**Key points:**
- `win_chocolatey` module handles Chocolatey operations
- `name:` list of packages
- `state: present` ensures packages are installed

**Execution:**
```
ansible-playbook -i inventory roles/windows_software.yml
```

**What happens:**
1. Ansible connects via SSH to mgmt01 and wks01
2. Checks if Chocolatey is installed (installs if not)
3. For each package, check if already installed
4. Installs missing packages
5. Reports changed/unchanged status

**Idempotency:**
First run: All packages installed, changed=true
Second run: Packages already present, changed=false

**Verification:**
```
choco list
```

Shows installed packages: 7zip, git, notepadplusplus

**Rate Limiting:**
Chocolatey's public repository rate limits connections. If the playbook fails with rate limit errors, wait 5-10 minutes before retrying.

## Research and Learning

### Topic 1: Ansible Architecture - Agentless vs Agent-Based

#### What I Didn't Know
I wasn't familiar with the differences between agentless configuration management (Ansible) and agent-based systems (Puppet, Chef), or why the architecture choice matters.

#### Research Results

**Agent-Based Systems (Puppet, Chef, SaltStack):**
- Require agent software installed on every managed node
- Agents run continuously in the background
- Agents periodically "phone home" to pull configurations (pull model)
- Central server maintains the desired state
- Agents enforce configuration locally

**Agentless Systems (Ansible):**
- No software required on managed nodes (just SSH and Python)
- Control node pushes configurations to managed nodes (push model)
- Commands executed on-demand, not continuously
- Uses existing infrastructure (SSH)

**Advantages of Agentless:**
- No agent installation, updates, or troubleshooting
- No resource consumption from running agents
- Works immediately on any SSH-capable system
- No "agent out of sync with server" issues
- Simpler architecture, fewer moving parts

**Disadvantages of Agentless:**
- Requires SSH connectivity from the control node to all managed nodes
- Slower at massive scale (1000+ nodes) compared to distributed agents
- Control node becomes a single point of failure
- No automatic drift detection (agents can continuously enforce the state)

#### Lab Application

This lab used Ansible's agentless architecture:
- Connected via SSH to ansible1, ansible2, mgmt01, wks01
- No software installation required on managed hosts (except Python, already present on Linux)
- Windows hosts used OpenSSH (built into modern Windows)
- Control node (controller) pushed configurations on-demand

#### Why It Matters

**Getting started quickly:**
No agent deployment phase. Start automating immediately.

**In production:**
For smaller environments (10-100 servers), agentless is simpler. For massive scale (1000+ servers) or strict compliance requirements (continuous state enforcement), agent-based may be better.

### Topic 2: Infrastructure as Code and Idempotency

#### What I Didn't Know
I had heard "Infrastructure as Code" and "idempotency" but didn't understand:
- What makes something "Infrastructure as Code."
- Why idempotency matters
- How it changes operational practices

#### Research Results

**Infrastructure as Code (IaC):**
- Defining infrastructure in machine-readable files
- Treating infrastructure configuration like application code
- Version control for infrastructure
- Automated, repeatable deployments
- Declarative (what you want) vs imperative (how to do it)

**Traditional Approach:**
1. SSH to the server
2. Run commands manually
3. Document in wiki (maybe)
4. Hope you remember next time
5. Configuration drift over time

**IaC Approach:**
1. Write a playbook describing the desired state
2. Run playbook
3. Playbook is documentation
4. Re-run anytime
5. Consistent state

**Idempotency:**
An operation is idempotent if running it multiple times produces the same result as running it once.

**Examples:**

**Idempotent:**
```
sudo apt install apache2
# First run: Installs Apache
# Second run: Already installed, does nothing
# Result: Same state
```

**NOT Idempotent:**
```
echo "PermitRootLogin no" >> /etc/ssh/sshd_config
# First run: Adds line
# Second run: Adds duplicate line
# Result: Different states
```

**Ansible ensures idempotency:**
- Checks current state before taking action
- Only makes changes if needed
- Reports "changed" vs "ok"
- Safe to run multiple times

**Benefits:**

**Drift detection:**
Run playbook. If changed=false everywhere, the system matches the desired state. If changed=true, the system drifted and was corrected.

**Safe re-runs:**
Can re-run playbooks as health checks or remediation without fear of breaking things.

**Declarative intent:**
Playbook says "Apache should be installed and running." Ansible figures out how to achieve that state.

#### Lab Application

**Playbook re-runs:**
First run of apache.yml: Installed packages, configured Apache, changed=true
Second run of apache.yml: Everything already configured, changed=false

**Windows software:**
First run: Installed 7zip, git, notepadplusplus
Second run: Already present, no changes

**Safe iteration:**
Could run playbooks repeatedly while debugging without causing issues.

#### Why It Matters

**Production reliability:**
No "works on my machine" problems. Playbook defines the exact state. Every system built from the same playbook is identical.

**Disaster recovery:**
Server dies? Run playbook on new VM. Exact configuration restored in minutes.

**Testing:**
Can test playbooks in the dev environment, then run the same playbook in production.

**Knowledge retention:**
Playbook is documentation. 

**In this lab:**
- linux-onboard.sh: IaC for system initialization
- Ansible playbooks: IaC for application deployment
- Both idempotent: Safe to re-run
- Both version-controlled: Track changes, collaborate

## Challenges and Solutions

### Challenge 1: Running Ansible as Root Instead of Deployer

**Problem:**
Attempted to run Ansible as the root user. All commands failed with "Permission denied" when trying to SSH to ansible1 and ansible2.

**Symptoms:**
```
Failed to connect to the host via ssh: root@ansible1-Ben.ben.local: Permission denied (publickey,gssapi-keyex,gssapi-with-mic,password)
```

**Cause:**
SSH keys were generated for the deployer user (`/home/deployer/.ssh/id_rsa`). When running as root, Ansible tried to use root's SSH keys (`/root/.ssh/id_rsa`), which didn't exist or weren't distributed to Ansible hosts.

**Solution:**
1. Switched to deployer user: `su - deployer`
2. Copied ansible-files from /root to /home/deployer
3. Fixed ownership: `sudo chown -R deployer:deployer ~/ansible-files`
4. Re-ran Ansible as deployer

### Challenge 2: Windows PowerShell Not Default SSH Shell

**Problem:**
After configuring OpenSSH on Windows and setting registry keys for PowerShell default shell, SSH still connected to cmd.exe instead of PowerShell.

**Symptoms:**
```
C:\Users\ben.deyot-adm>
```
Instead of the expected PowerShell prompt.

**Cause:**
Registry path `HKLM:\SOFTWARE\OpenSSH` didn't exist. Command to set the DefaultShell property failed silently.

**Solution:**
```
# Create registry key first
New-Item -Path "HKLM:\SOFTWARE\OpenSSH" -Force

# Then set property
New-ItemProperty -Path HKLM:\SOFTWARE\OpenSSH -Name DefaultShell -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force

# Restart SSH
Restart-Service sshd
```

**Learning:**
Windows registry paths must exist before setting properties. PowerShell cmdlets need error checking. In production scripts, use `-ErrorAction Stop` and try/catch blocks.

### Challenge 3: WKS01 DNS Resolution Failure

**Problem:**
Controller could ping and SSH to wks01 by IP (10.0.5.150) but not by hostname (wks01-Ben.ben.local).

**Symptoms:**
```
nslookup wks01-Ben.ben.local
# Server: 127.0.0.53
# Address: 127.0.0.53#53
# Non-authoritative answer
```
But Ansible couldn't reach wks01 by hostname.

**Cause:**
Controller's DNS was configured to use 10.0.5.5 (AD-01) in netplan, but systemd-resolved was using its stub resolver (127.0.0.53) and wasn't properly forwarding to AD-01.

**Solution:**
1. Verified netplan configuration was correct
2. Applied netplan: `sudo netplan apply`
3. Verified systemd-resolved status: `resolvectl status`
4. Tested DNS: `nslookup wks01-Ben.ben.local`

After netplan apply, systemd-resolved properly forwarded queries to AD-01, which resolved wks01's DHCP address.

**Learning:**
Ubuntu's DNS resolution is layered:
1. Applications query systemd-resolved (127.0.0.53)
2. systemd-resolved forwards to configured DNS servers
3. Netplan configures which DNS servers to use

Must ensure the entire chain is configured correctly. Simple `cat /etc/resolv.conf` doesn't show the full picture on modern Ubuntu.

### Challenge 4: Chocolatey Command Syntax Change

**Problem:**
Tried to verify Chocolatey packages with `choco list --local-only` but received error: "Invalid argument --local-only. This argument has been removed."

**Cause:**
Newer versions of Chocolatey deprecated the `--local-only` flag.

**Solution:**
```
# New syntax
choco list --localonly

# Or just
choco list
```
The default behavior is to list local packages unless explicitly searching the repository.

**Learning:**
Commands that worked in tutorials or older documentation may be deprecated. Read error messages carefully - Chocolatey's error explicitly stated the flag was removed.

## Conclusion

### Reflection

This lab provided a comprehensive experience in modern infrastructure automation across heterogeneous systems. The combination of bash scripting for initial system setup and Ansible for ongoing configuration management demonstrates how automation tools work together in the system administration lifecycle.

**Key Learnings:**

**Infrastructure as Code transforms operations:**
Both the bash script and Ansible playbooks are self-documenting. There's no "tribal knowledge" about how systems are configured. The script IS the documentation. This enables reliable disaster recovery, consistent deployments, and knowledge transfer.

**Idempotency enables confidence:**
Being able to re-run playbooks safely fundamentally changes how you approach automation. Instead of "one-shot" scripts that must be perfect the first time, you can iterate, test, and refine. Playbooks become health checks and remediation tools, not just deployment tools.

**Automation compounds:**
The linux-onboard.sh script saved 75 minutes(ish) across three systems. That's valuable. But the real value is the 100th system. 

### Final Thoughts

This lab demonstrated that automation isn't just about efficiency. It's about reliability, consistency, and sustainability. Manual processes are error-prone, don't scale, and aren't repeatable. Automated processes are consistent, scale efficiently, and are self-documenting.

Infrastructure as Code represents a fundamental shift in system administration. Instead of configuring systems, we write code that configures systems. Instead of documenting procedures, we write code that implements procedures. Instead of hoping for consistency, we enforce consistency through automation.

**Current Infrastructure:**
- Three Linux systems configured identically via an automation script
- Ansible control node managing five systems (3 Linux, 2 Windows)
- All configurations version-controlled in GitHub
- Playbooks for service deployment, software management, and configuration
- SSH key infrastructure for secure, passwordless authentication

**Skills Demonstrated:**
- Bash scripting with input validation and error handling
- Ansible inventory management and host grouping
- Playbook creation and execution
- Cross-platform automation (Linux and Windows)
- SSH key generation, distribution, and agent configuration
- Troubleshooting firewall, DNS, and authentication issues
- Infrastructure as Code principles
- Idempotent configuration management
