# LAB - Automation with Ansible

## Summary
In this lab, we implemented Ansible automation across heterogeneous systems, including three Linux servers (Ubuntu) and two Windows workstations. 
We created a reusable Linux onboarding script to automate initial system configuration, reducing deployment time from 30 minutes to under 5 minutes per system. 
Using Ansible, we deployed services to Linux hosts via Galaxy roles (Webmin and Apache), configured passwordless SSH authentication with passphrase-protected keys and an SSH agent, and automated Windows software deployment through Chocolatey package management. 
The lab demonstrated Infrastructure as Code principles, agentless configuration management, and cross-platform automation capabilities essential for modern system administration.

## Part 1: Linux Onboarding Script

### linux-onboard.sh

I created an interactive bash script that automates the entire onboarding process through a question-and-answer interface. 
The script handles both Ubuntu and Rocky Linux distributions.

**Link to script on GitHub:** (script) [https://github.com/Benjamin20771/Sys-265/blob/main/scripts/linux-onboard.sh]

### Script Features

**Interactive Configuration:**
The script asks questions and validates all inputs before making changes:

```bash
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
The script asks if you want DHCP or static IP. For static, it prompts for all network details. For DHCP, it only asks for DNS and domain. This flexibility allows the script to work in various environments.

**2. Optional Secondary DNS:**
Instead of requiring a secondary DNS server, the script asks if you want one. If you say no, it configures the system with only the primary DNS, avoiding unnecessary configuration.

**3. Input Validation:**
- IP addresses validated against regex pattern
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
```yaml
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
Creates users with home directories, sets passwords securely, adds to sudo group, and sets proper shell (`/bin/bash`).

**Passwordless Sudo:**
Creates `/etc/sudoers.d/sys265`:
```bash
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
```bash
# Clone repository
git clone https://github.com/bendeyot/sys265-repos
cd sys265-repos/scripts

# Make executable
chmod +x linux-onboard.sh

# Run as root
sudo ./linux-onboard.sh
```

**Time Savings:**
- Manual configuration: ~30 minutes per system
- Script configuration: ~5 minutes per system
- Configured 3 systems: Saved 75 minutes total
- Eliminated configuration errors from manual typing

### Why This Matters

**Consistency:**
Every system configured identically. No typos in IP addresses, no forgotten steps, no configuration drift.

**Documentation:**
The script itself documents the exact configuration applied. No need to remember what was done - it's in the code.

**Repeatability:**
Can deploy dozens of systems with identical configuration. Perfect for labs, testing, or production deployments.

**Version Control:**
Script stored in Git. Can track changes, rollback to previous versions, collaborate with team members.

**Infrastructure as Code:**
Treating infrastructure configuration as code enables DevOps practices: review, test, automate, repeat.

## Part 2: Ansible Installation and Setup

### Installing Ansible on Controller

**Installation:**
```bash
sudo apt install ansible sshpass python3-paramiko -y
```

**Package Breakdown:**
- `ansible` - Core automation engine, includes modules and playbook functionality
- `sshpass` - Allows non-interactive SSH password authentication (used for initial key distribution)
- `python3-paramiko` - Python SSH library that Ansible uses for SSH connections

**Why Ansible:**
Ansible is agentless - uses SSH to connect to managed hosts. No agents to install, update, or troubleshoot. Works on any system with SSH and Python (Linux) or SSH with PowerShell (Windows).

**Verification:**
```bash
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
```bash
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
```bash
ssh-copy-id deployer@ansible1-Ben.ben.local
ssh-copy-id deployer@ansible2-Ben.ben.local
```

**What ssh-copy-id does:**
1. Connects via SSH (asks for password once)
2. Copies public key to `~/.ssh/authorized_keys` on remote host
3. Sets correct permissions (700 for .ssh, 600 for authorized_keys)
4. Appends key instead of overwriting (safe for multiple keys)

**Testing:**
```bash
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
```bash
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
4. Checks if key is already loaded
5. If not, loads the key with 4-hour timeout (14400 seconds)

**Result:**
Enter passphrase once per session (or once every 4 hours). All subsequent SSH connections are passwordless and passphrase-less.

**Security benefit:**
Still protected against key theft (passphrase required), but convenient for automation.

## Part 4: Ansible Inventory and Configuration

### Directory Structure

```bash
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
```ini
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
ansible_password=Pepper123!
ansible_connection=ssh
ansible_shell_type=powershell
```

**Key Concepts:**

**Groups:**
- `[linux]` - All Linux hosts
- `[webmin]` - Subset for Webmin installation (just ansible2)
- `[windows]` - All Windows hosts

**Group Variables (`[windows:vars]`):**
Variables that apply to all hosts in the windows group:
- `ansible_user` - Username for authentication
- `ansible_password` - Password (in production, use vault encryption)
- `ansible_connection=ssh` - Use SSH instead of WinRM
- `ansible_shell_type=powershell` - Use PowerShell for commands

**Why SSH for Windows:**
Microsoft introduced OpenSSH for Windows as the modern remote management protocol. More secure than WinRM, works through firewalls easier, consistent with Linux management.

### Ansible Configuration File

**ansible.cfg:**
```ini
[defaults]
host_key_checking = False
```

**Purpose:**
Disables SSH host key verification. On first connection, SSH normally asks "Are you sure you want to continue connecting?" This bypasses that prompt.

**Security Trade-off:**
Less secure (vulnerable to man-in-the-middle attacks) but convenient for lab environments where we're constantly rebuilding systems. In production, you'd pre-populate known_hosts or use proper key management.

### Testing Basic Connectivity

**Ansible Ping Module:**
```bash
ansible -i inventory all -m ping
```

**Expected output:**
```json
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
Ansible tracks whether operations change system state. Ping doesn't change anything, so changed=false. This is idempotency - running the same operation multiple times produces the same result.

## Part 5: Ansible Playbooks and Roles

### Webmin Installation via Ansible Galaxy

**Ansible Galaxy:**
Community repository of pre-built Ansible roles (like Docker Hub for containers). Instead of writing installation steps from scratch, download a role that someone else built and tested.

**Installation:**
```bash
ansible-galaxy install semuadmin.webmin
```

**Playbook (webmin.yml):**
```yaml
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
```bash
ansible-playbook -i inventory webmin.yml
```

**What happens:**
1. Ansible connects to ansible2 via SSH as deployer
2. Escalates to root (become: yes)
3. Downloads and executes the semuadmin.webmin role
4. Role installs Webmin package, configures service, starts it
5. Reports success/failure

**Accessing Webmin:**
```
http://ansible2-Ben.ben.local:10000
Username: root
Password: deployer password
```

**Firewall Issue Encountered:**
Webmin was installed and running but inaccessible from browser. Rocky Linux's firewalld was blocking port 10000.

**Solution:**
```bash
sudo firewall-cmd --permanent --add-port=10000/tcp
sudo firewall-cmd --reload
```

**Lesson:** Always check firewall after installing network services.

### Apache Web Server Installation

**Role:**
```bash
ansible-galaxy install geerlingguy.apache
```

**Playbook (apache.yml):**
```yaml
---
- name: Install Apache Web Server
  hosts: ansible1-Ben.ben.local
  become: yes
  roles:
    - geerlingguy.apache
```

**Execution:**
```bash
ansible-playbook -i inventory apache.yml
```

**Result:**
Apache installed, configured, and started on ansible1. Default Rocky Linux test page accessible at `http://ansible1-Ben.ben.local`.

**Same firewall issue:**
Had to open HTTP port:
```bash
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

Without the role, we'd need to write all those tasks manually.

## Part 6: Windows Automation

### Preparing Windows Hosts

**OpenSSH Installation on Windows:**

Modern Windows includes OpenSSH as an optional feature. Much better than WinRM for remote management.

**Installation (PowerShell as Administrator):**
```powershell
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
```powershell
# Enable console prompting
Set-ItemProperty "HKLM:\Software\Microsoft\Powershell\1\ShellIds" -Name ConsolePrompting -Value $true

# Create OpenSSH registry key
New-Item -Path "HKLM:\SOFTWARE\OpenSSH" -Force

# Set default shell
New-ItemProperty -Path HKLM:\SOFTWARE\OpenSSH -Name DefaultShell -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force
```

**Firewall Rule:**
```powershell
New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
```

**Testing SSH:**
```bash
ssh ben.deyot-adm@mgmt01-Ben.ben.local
```

Should connect and show PowerShell prompt.

**Challenge encountered:**
Registry path `HKLM:\SOFTWARE\OpenSSH` didn't exist, causing error. Had to create it first with `New-Item` before setting the DefaultShell property.

### Windows Ansible Connectivity

**Testing with win_ping:**
```bash
ansible -i inventory windows -m win_ping
```

**Expected output:**
```json
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
Verified netplan had correct DNS settings and applied configuration. systemd-resolved then properly forwarded queries to AD-01, which resolved wks01's DHCP address.

**Verification:**
```bash
nslookup wks01-Ben.ben.local
# Returned: 10.0.5.150
```

### Software Deployment with Chocolatey

**Chocolatey:**
Windows package manager (like apt for Ubuntu, yum for CentOS). Community repository of software packages. Enables scripted, automated Windows software installation.

**Playbook (windows_software.yml):**
```yaml
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
```bash
ansible-playbook -i inventory roles/windows_software.yml
```

**What happens:**
1. Ansible connects via SSH to mgmt01 and wks01
2. Checks if Chocolatey is installed (installs if not)
3. For each package, checks if already installed
4. Installs missing packages
5. Reports changed/unchanged status

**Idempotency:**
First run: All packages installed, changed=true
Second run: Packages already present, changed=false

**Verification:**
```powershell
choco list
```

Shows installed packages: 7zip, git, notepadplusplus

**Rate Limiting:**
Chocolatey's public repository rate limits connections. If playbook fails with rate limit errors, wait 5-10 minutes before retrying.

## Research and Learning

### Topic 1: Ansible Architecture - Agentless vs Agent-Based

#### What I Didn't Know
I wasn't familiar with the differences between agentless configuration management (Ansible) and agent-based systems (Puppet, Chef), or why the architecture choice matters.

#### Research Results

**Agent-Based Systems (Puppet, Chef, SaltStack):**
- Require agent software installed on every managed node
- Agents run continuously in background
- Agents periodically "phone home" to pull configurations (pull model)
- Central server maintains desired state
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
- Requires SSH connectivity from control node to all managed nodes
- Slower at massive scale (1000+ nodes) compared to distributed agents
- Control node becomes single point of failure
- No automatic drift detection (agents can continuously enforce state)

#### Lab Application

This lab used Ansible's agentless architecture:
- Connected via SSH to ansible1, ansible2, mgmt01, wks01
- No software installation required on managed hosts (except Python, already present on Linux)
- Windows hosts used OpenSSH (built into modern Windows)
- Control node (controller) pushed configurations on-demand

#### Why It Matters

**Operational simplicity:**
No agent lifecycle management. One less thing to break, update, or troubleshoot.

**Heterogeneous environments:**
Works with Linux, Windows, network devices, cloud APIs - anything with SSH or API access.

**Getting started quickly:**
No agent deployment phase. Start automating immediately.

**In production:**
For smaller environments (10-100 servers), agentless is simpler. For massive scale (1000+ servers) or strict compliance requirements (continuous state enforcement), agent-based may be better.

### Topic 2: SSH Key Authentication with Passphrases and SSH Agent

#### What I Didn't Know
I understood basic SSH key authentication but didn't fully grasp:
- Why passphrase protection matters
- How SSH agent works
- The security vs convenience trade-off

#### Research Results

**SSH Key Authentication Without Passphrase:**
- Private key is unencrypted file
- Anyone with the file can authenticate
- Like leaving your house key under the doormat
- If file is stolen (laptop theft, backup compromise), attacker has full access
- Common in automation because scripts can't type passphrases

**SSH Key Authentication With Passphrase:**
- Private key encrypted with symmetric encryption
- Passphrase required to decrypt private key
- File theft alone insufficient - attacker also needs passphrase
- Significantly more secure
- But: automation challenge, must enter passphrase for each connection

**SSH Agent - Best of Both Worlds:**
- Decrypts private key once (when loaded into agent)
- Keeps decrypted key in memory
- Provides key to SSH without re-prompting for passphrase
- Can set timeout (14400 seconds = 4 hours in our lab)
- After timeout, passphrase required again

**How SSH Agent Works:**
1. Start ssh-agent (creates Unix socket)
2. Run ssh-add (prompts for passphrase, decrypts key, loads into agent)
3. SSH clients communicate with agent via socket
4. Agent provides decrypted key for authentication
5. No passphrase prompts for subsequent connections

**Security Model:**
- Private key file: Encrypted, useless without passphrase
- Agent memory: Decrypted key, protected by OS memory isolation
- Socket: Only accessible by user who started agent
- Timeout: Limits exposure window

#### Lab Application

**Key generation:**
```bash
ssh-keygen -t rsa -b 4096
# With passphrase protection
```

**Agent configuration in ~/.bashrc:**
Automatically starts agent on login and loads key with 4-hour timeout.

**Result:**
- Enter passphrase once when logging into controller
- All SSH connections (manual and Ansible) work without prompts
- Still protected against key theft
- Ansible playbooks run without interaction

#### Why It Matters

**Security:**
Passphrase protection essential for production. Laptops get stolen, backups get compromised, keys get accidentally committed to GitHub. Passphrase is the last line of defense.

**Automation:**
SSH agent enables automation with passphrase-protected keys. Don't have to choose between security and convenience.

**Compliance:**
Many security frameworks require passphrase-protected keys. SSH agent makes compliance practical.

**Best practice:**
- Development: Passphrase-protected keys with agent
- Production automation: Service accounts with passphrase-protected keys, agent in systemd service, or consider HashiCorp Vault for key management
- Personal systems: Always use passphrases

### Topic 3: Infrastructure as Code and Idempotency

#### What I Didn't Know
I had heard "Infrastructure as Code" and "idempotency" but didn't understand:
- What makes something "Infrastructure as Code"
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
1. SSH to server
2. Run commands manually
3. Document in wiki (maybe)
4. Hope you remember next time
5. Configuration drift over time

**IaC Approach:**
1. Write playbook describing desired state
2. Run playbook
3. Playbook is documentation
4. Re-run anytime
5. Consistent state

**Idempotency:**
An operation is idempotent if running it multiple times produces the same result as running it once.

**Examples:**

**Idempotent:**
```bash
sudo apt install apache2
# First run: Installs Apache
# Second run: Already installed, does nothing
# Result: Same state
```

**NOT Idempotent:**
```bash
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
Run playbook. If changed=false everywhere, system matches desired state. If changed=true, system drifted and was corrected.

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
No "works on my machine" problems. Playbook defines exact state. Every system built from same playbook is identical.

**Disaster recovery:**
Server dies? Run playbook on new VM. Exact configuration restored in minutes.

**Auditing:**
Git history shows who changed what when. No mystery configurations.

**Testing:**
Can test playbooks in dev environment, then run same playbook in production.

**Knowledge retention:**
Playbook is documentation. No "tribal knowledge" required.

**In this lab:**
- linux-onboard.sh: IaC for system initialization
- Ansible playbooks: IaC for application deployment
- Both idempotent: Safe to re-run
- Both version-controlled: Track changes, collaborate

## Challenges and Solutions

### Challenge 1: Running Ansible as Root Instead of Deployer

**Problem:**
Attempted to run Ansible as root user. All commands failed with "Permission denied" trying to SSH to ansible1 and ansible2.

**Symptoms:**
```
Failed to connect to the host via ssh: root@ansible1-Ben.ben.local: Permission denied (publickey,gssapi-keyex,gssapi-with-mic,password)
```

**Cause:**
SSH keys were generated for deployer user (`/home/deployer/.ssh/id_rsa`). When running as root, Ansible tried to use root's SSH keys (`/root/.ssh/id_rsa`), which didn't exist or weren't distributed to ansible hosts.

**Solution:**
1. Switched to deployer user: `su - deployer`
2. Copied ansible-files from /root to /home/deployer
3. Fixed ownership: `sudo chown -R deployer:deployer ~/ansible-files`
4. Re-ran Ansible as deployer

**Learning:**
SSH keys are user-specific. The user running Ansible must have their public key in `~/.ssh/authorized_keys` on managed hosts. Always run Ansible as the user with proper SSH keys configured.

### Challenge 2: SSH Agent Not Retaining Key

**Problem:**
SSH agent configuration added to ~/.bashrc, but `ssh-add -l` showed "The agent has no identities."

**Symptoms:**
Had to enter passphrase on every SSH connection, defeating the purpose of SSH agent.

**Cause:**
SSH keypair was generated as root, stored in `/root/.ssh/`. When switched to deployer user, deployer had no SSH keys in `~/.ssh/`.

**Solution:**
1. Copied root's SSH keys to deployer: `sudo cp /root/.ssh/id_rsa* ~/.ssh/`
2. Fixed ownership: `sudo chown deployer:deployer ~/.ssh/id_rsa*`
3. Fixed permissions: `chmod 600 ~/.ssh/id_rsa`
4. Loaded key into agent: `ssh-add ~/.ssh/id_rsa`

**Learning:**
SSH keys live in user home directories. Keys generated as root are useless for other users. Generate keys as the user who will use them, or copy and fix ownership if already generated.

### Challenge 3: Webmin and Apache Ports Blocked by Firewall

**Problem:**
Webmin installed successfully on ansible2, service running, but web interface inaccessible from browser. Same issue with Apache on ansible1.

**Symptoms:**
- `sudo systemctl status webmin` showed active (running)
- `sudo ss -tulpn | grep 10000` showed port listening
- Browser: "This site can't be reached"

**Cause:**
Rocky Linux uses firewalld (not UFW like Ubuntu). By default, firewalld blocks most incoming ports. Neither Webmin nor Apache roles configured firewalld rules.

**Solution:**
```bash
# For Webmin
sudo firewall-cmd --permanent --add-port=10000/tcp
sudo firewall-cmd --reload

# For Apache  
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --reload
```

**Learning:**
Always check firewall after installing network services. Different distros use different firewall systems:
- Ubuntu: UFW (simple interface to iptables)
- Rocky/CentOS: firewalld (zones-based firewall)

Services can be running and listening but completely inaccessible due to firewall blocks.

### Challenge 4: Windows PowerShell Not Default SSH Shell

**Problem:**
After configuring OpenSSH on Windows and setting registry keys for PowerShell default shell, SSH still connected to cmd.exe instead of PowerShell.

**Symptoms:**
```
C:\Users\ben.deyot-adm>
```
Instead of expected PowerShell prompt.

**Cause:**
Registry path `HKLM:\SOFTWARE\OpenSSH` didn't exist. Command to set DefaultShell property failed silently.

**Solution:**
```powershell
# Create registry key first
New-Item -Path "HKLM:\SOFTWARE\OpenSSH" -Force

# Then set property
New-ItemProperty -Path HKLM:\SOFTWARE\OpenSSH -Name DefaultShell -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force

# Restart SSH
Restart-Service sshd
```

**Learning:**
Windows registry paths must exist before setting properties. PowerShell cmdlets need error checking. In production scripts, use `-ErrorAction Stop` and try/catch blocks.

### Challenge 5: WKS01 DNS Resolution Failure

**Problem:**
Controller could ping and SSH to wks01 by IP (10.0.5.150) but not by hostname (wks01-Ben.ben.local).

**Symptoms:**
```bash
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

### Challenge 6: Chocolatey Command Syntax Change

**Problem:**
Tried to verify Chocolatey packages with `choco list --local-only` but received error: "Invalid argument --local-only. This argument has been removed."

**Cause:**
Newer versions of Chocolatey deprecated the `--local-only` flag.

**Solution:**
```powershell
# New syntax
choco list --localonly

# Or just
choco list
```
Default behavior is to list local packages unless explicitly searching the repository.

**Learning:**
Tools evolve. Commands that worked in tutorials or older documentation may be deprecated. Read error messages carefully - Chocolatey's error explicitly stated the flag was removed.

## Conclusion

### Reflection

This lab provided comprehensive experience in modern infrastructure automation across heterogeneous systems. The combination of bash scripting for initial system setup and Ansible for ongoing configuration management demonstrates how automation tools work together in the system administration lifecycle.

**What Worked Well:**

The linux-onboard.sh script exceeded expectations. Reducing system deployment from 30 minutes to 5 minutes represents a 6x efficiency gain, and the time savings scale linearly with the number of systems. The interactive Q&A approach made the script flexible enough to handle different configurations (DHCP vs static, optional secondary DNS) while remaining simple to use.

Ansible's agentless architecture proved ideal for heterogeneous environments. The same control node managed Ubuntu and Rocky Linux systems identically, and Windows automation via SSH (instead of WinRM) provided a consistent management interface across all platforms.

SSH key authentication with passphrases and SSH agent struck the right balance between security and usability. Passphrase-protected keys defend against key theft, while SSH agent eliminates the need to repeatedly enter passphrases during automation runs.

**Challenges Overcome:**

The most valuable troubleshooting experience came from firewall issues. Rocky Linux's firewalld, unlike Ubuntu's UFW, requires explicit configuration to allow service ports. This is a critical production consideration - services can appear to be running perfectly (process active, port listening) while being completely inaccessible due to firewall rules.

Understanding systemd-resolved's DNS resolution chain on Ubuntu clarified why simple configuration changes sometimes don't take effect. Modern Ubuntu layers DNS resolution through systemd-resolved's stub resolver, and netplan must configure the upstream servers correctly for the entire chain to work.

The experience switching between root and deployer users, and the resulting SSH key issues, reinforced that SSH keys are fundamentally user-specific. This is important for production environments where multiple administrators need access - each admin should have their own keys, not shared service account keys.

**Key Learnings:**

**Infrastructure as Code transforms operations:**
Both the bash script and Ansible playbooks are self-documenting. There's no "tribal knowledge" about how systems are configured. The script IS the documentation. This enables reliable disaster recovery, consistent deployments, and knowledge transfer.

**Idempotency enables confidence:**
Being able to re-run playbooks safely fundamentally changes how you approach automation. Instead of "one-shot" scripts that must be perfect the first time, you can iterate, test, and refine. Playbooks become health checks and remediation tools, not just deployment tools.

**Automation compounds:**
The linux-onboard.sh script saved 75 minutes across three systems. That's valuable. But the real value is the 100th system. Manual processes scale linearly (100 systems = 50 hours of work). Automation scales logarithmically (100 systems = 8 hours to run scripts + minimal debugging).

### Real-World Applications

**Configuration Management at Scale:**
Ansible manages thousands of servers at companies like NASA, Verizon, and Cisco. The same principles from this lab (inventory organization, role-based playbooks, idempotent operations) apply at massive scale.

**Cloud Infrastructure Automation:**
Cloud providers (AWS, Azure, GCP) all support Ansible for infrastructure automation. The same playbooks that configured Apache on a VM can configure EC2 instances, Azure VMs, or GCP Compute instances.

**Compliance and Security:**
Automated configuration enforcement ensures systems maintain security baselines. Instead of quarterly manual audits, Ansible can run daily checks and automatically remediate drift.

**Disaster Recovery:**
Complete infrastructure definition in code enables rapid disaster recovery. New datacenter? Point Ansible at new VMs, run playbooks, infrastructure rebuilt in hours.

**Development Environment Consistency:**
"Works on my machine" problems disappear when developers use the same Ansible playbooks that deploy production. Dev, test, and prod environments become identical.

### Future Exploration

**Advanced Ansible:**
- Ansible Vault for password encryption
- Dynamic inventory from cloud APIs
- Ansible Tower/AWX for web UI and RBAC
- Custom modules for specialized tasks
- Rolling deployments with serial execution

**Container Orchestration:**
- Using Ansible to deploy Kubernetes
- Managing containerized applications
- Integration with Docker Compose
- CI/CD pipelines with Ansible

**Windows Automation:**
- DSC (Desired State Configuration) integration
- Group Policy automation
- Active Directory management
- Advanced PowerShell remoting

**Enhanced Scripting:**
- Add logging to linux-onboard.sh
- Email notifications on completion
- Integration with monitoring systems
- Multi-network support (different subnets)

**Security Hardening:**
- CIS benchmark compliance playbooks
- Automated security patching
- Certificate management
- Secrets management with Vault

### Final Thoughts

This lab demonstrated that automation isn't just about efficiency - it's about reliability, consistency, and sustainability. Manual processes are error-prone, don't scale, and aren't repeatable. Automated processes are consistent, scale efficiently, and are self-documenting.

The most valuable skill developed wasn't learning specific Ansible modules or bash syntax. It was developing the mindset to ask "How can I automate this?" Every repetitive task, every manual configuration, every "documentation step" is an opportunity for automation.

Infrastructure as Code represents a fundamental shift in system administration. Instead of configuring systems, we write code that configures systems. Instead of documenting procedures, we write code that implements procedures. Instead of hoping for consistency, we enforce consistency through automation.

**Current Infrastructure:**
- Three Linux systems configured identically via automation script
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

The investment in automation infrastructure pays dividends immediately (75 minutes saved on three systems) and continues paying dividends forever (every future system deployed, every configuration change applied consistently, every disaster recovery scenario).

This lab has transformed how I approach system administration tasks. The question is no longer "How do I configure this system?" but rather "How do I write code that configures this system - and every future system - correctly every time?"
