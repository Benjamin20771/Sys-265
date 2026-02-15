# LAB - Git Version Control and SSH Hardening

## Summary
In this lab, I implemented Git version control across three systems (docker01, mgmt01, web01) and created an SSH hardening script for passwordless authentication. I learned Git, including clone, add, commit, push, and pull commands, while having a centralized repository on GitHub. The second part focused on SSH key-based authentication, where we generated RSA key pairs and automated the creation of secure, password-free user accounts through a script. 

## Part 1: Git Version Control

### Installing Git on docker01

**Installation:**
```
sudo apt update
sudo apt install git -y
git --version
```

**Git Configuration:**
```
git config --global user.name "Benjamin20771"
git config --global user.email "benjamin.deyot@mymail.champlain.edu"
git config --list
```

**Why Configuration Matters:**
- Git tracks who makes changes (audit trail)
- Commit history shows author information
- Good for collaborative development
- Email used for GitHub association

### Cloning Repository on docker01

**GitHub Personal Access Token:**
GitHub deprecated password authentication in 2021 (fun fact). Must use Personal Access Tokens (PAT):
1. GitHub → Settings → Developer settings → Personal access tokens
2. Generate new token (classic)
3. Select `repo` scope for repository access
4. Copy token immediately (won't see again) (know from experience)
5. Use the token as a password when git wants one

**Clone Process:**
```
cd ~
git clone (Go to Code -> Copy link that's there)
cd Sys265
ls -la
```

**What Cloning Does:**
- Downloads entire repository history
- Creates local working copy
- Establishes connection to remote (origin)
- Sets up tracking between local and remote branches

### Creating Directory Structure

```
mkdir -p linux/docker01
mkdir -p linux/web01
mkdir -p windows/mgmt01
mkdir -p scripts
```

**Organizational Strategy:**
- `linux/` - Linux system configurations
- `windows/` - Windows system configurations  
- `scripts/` - Automation scripts
- Separates by OS and function for clarity

**Created README.md:**
```
echo "# SYS-265 Configuration Repository" > README.md
echo "Ben Deyot - Champlain College" >> README.md
echo "" >> README.md
echo "This repository contains configuration files and scripts for my SYS-265 lab environment." >> README.md
```

**Why README.md:**
- Markdown format renders on GitHub
- First thing visitors see
- Documents repository purpose
- Professional presentation

### Adding Configuration Files

```
# Copy Pi-hole docker-compose as example configuration
cp ~/pihole-project/docker-compose.yml linux/docker01/

# Create documentation
echo "# docker01 Configuration" > linux/docker01/README.md
echo "IP: 10.0.5.12" >> linux/docker01/README.md
echo "Hostname: docker01-Ben" >> linux/docker01/README.md
```

**Purpose:**
- Version control for infrastructure configurations
- Track changes over time
- Easy recovery if configurations break
- Share configurations across team

### Git Add, Commit, Push Workflow

```
# Check what's changed
git status

# Stage all changes
git add .

# Commit with descriptive message
git commit -m "Added directory structure and docker01 configurations"

# Push to GitHub
git push origin main
```

**Git Workflow Explained:**

**git status:**
- Shows modified, new, and deleted files
- Indicates staged vs unstaged changes
- Shows which branch you're on

**git add:**
- Stages files for commit
- `git add .` stages everything
- `git add filename` stages a specific file
- Prepares snapshot of changes

**git commit:**
- Creates a snapshot of staged changes
- Requires descriptive message
- Stores in local repository
- Includes author, timestamp, message

**git push:**
- Uploads local commits to remote (GitHub)
- `origin` = remote repository name
- `main` = branch name
- Makes changes available to others

### Git Checkout - Recovering Deleted Files

**Delete README.md:**
```
rm README.md
ls -la  # Verify gone
git status  # Shows as deleted
```

**Recover File:**
```
git checkout README.md
# Or newer git syntax:
git restore README.md

ls -la README.md  # File is back
```

**How This Works:**
- Git maintains the history of all committed files
- `checkout` restores the file from the last commit
- Only works for committed files
- Uncommitted changes are lost forever

**Why This Matters:**
- Accidental deletion protection
- Quick recovery without backup restore
- No need for file recovery tools
- One of Git's core safety features

## Part 2: Git on Windows (mgmt01)

### Installing Git for Windows

**Download and Install:**
- Downloaded 64-bit Git for Windows from git-scm.com
- Used default settings throughout installation
- Includes Git Bash (Linux-like terminal for Windows)
- Integrates with Windows Explorer

**Git Bash vs Command Prompt:**
- Git Bash provides Linux commands (ls, pwd, etc.)
- Better for Git operations
- Consistent with Linux Git experience
- Includes SSH client

### Cloning on mgmt01

**In Git Bash:**
```
cd ~
git clone (That URL)
cd Sys265
ls -la
```

**Credential Caching on Windows:**
Git for Windows automatically caches credentials using Windows Credential Manager:
- Stores GitHub token securely
- No need to re-enter every push
- Can manage in Windows Credential Manager
- More secure than plain text storage

### Creating mgmt01 Content

```
mkdir -p windows/mgmt01
echo "# MGMT-01 Configuration" > windows/mgmt01/README.md
echo "This is the management workstation" >> windows/mgmt01/README.md
```

**Initial Commit:**
```
git add .
git commit -m "Added mgmt01 directory and README"
git push origin main
```

### Fixing README with Hostname

**The "Oops" Moment:**
The README should include the actual hostname, not generic text.

**Windows Hostname in Git Bash:**
```
# Works in Git Bash on Windows
echo "Hostname: $COMPUTERNAME" >> windows/mgmt01/README.md

# Verify
cat windows/mgmt01/README.md
```

**Re-commit:**
```
git add windows/mgmt01/README.md
git commit -m "oops"
git push origin main
```

**Lesson Learned:**
- Commits are permanent in history
- Can't truly "delete" commits (they're in history)
- Descriptive commit messages help track changes
- "Oops" commits happen to everyone

## Part 3: Git Pull - Synchronization

### The Problem

After pushing from mgmt01, docker01's local repository is out of sync:
- GitHub has the latest version (mgmt01 changes)
- docker01 has an old version (no mgmt01 directory)
- Need to synchronize

### Git Pull Operation

**On docker01:**
```
cd ~/Sys265
git status  # Shows "Your branch is behind"
git pull origin main
```

**What Pull Does:**
1. Fetches changes from remote (GitHub)
2. Merges changes into the local branch
3. Updates working directory
4. Fast-forward merge if no conflicts

**Output:**
```
Updating abc1234..def5678
Fast-forward
 windows/mgmt01/README.md | 3 +++
 1 file changed, 3 insertions(+)
 create mode 100644 windows/mgmt01/README.md
```

**Verify:**
```
ls -la windows/mgmt01/
cat windows/mgmt01/README.md
```

**Why Pull is Critical:**
- Keeps the local repository synchronized
- Prevents conflicts from outdated code
- Essential for team collaboration
- Good practice before starting work

## Part 4: SSH Hardening on web01

### Installing Git on web01

**Rocky Linux Installation:**
```
sudo dnf install git -y
git config --global user.name "Benjamin20771"
git config --global user.email "benjamin.deyot@mymail.champlain.edu"
git --version
```

**Clone Repository:**
```
cd ~
git clone (URL)
cd sys265-repos
```

### Creating secure-ssh.sh Script

**Directory Setup:**
```
mkdir -p linux/web01
mkdir -p scripts
```

**Initial Script Version:**
```
vi scripts/secure-ssh.sh
```

```
#!/bin/bash
# secure-ssh.sh
# Ben Deyot - SYS-265
# Creates user with SSH key-only authentication

if [ -z "$1" ]; then
    echo "Usage: ./secure-ssh.sh <username>"
    exit 1
fi

USERNAME=$1

# Create user with no password
sudo useradd -m -s /bin/bash $USERNAME

# Create .ssh directory
sudo mkdir -p /home/$USERNAME/.ssh

# Set permissions
sudo chmod 700 /home/$USERNAME/.ssh

echo "User $USERNAME created successfully"
```

**Make Executable:**
```
chmod +x scripts/secure-ssh.sh
```

**Push to GitHub:**
```
git add scripts/secure-ssh.sh
git commit -m "Added secure-ssh.sh script"
git push origin main
```

### SSH Keypair Generation

**Generate RSA Keypair on web01:**
```
ssh-keygen -t rsa -b 4096
```

**Prompts:**
- Location: Press Enter (default ~/.ssh/id_rsa)
- Passphrase: Press Enter (no passphrase for automation)
- Confirm: Press Enter

**Files Created:**
- `~/.ssh/id_rsa` - **PRIVATE KEY** (never share!)
- `~/.ssh/id_rsa.pub` - **PUBLIC KEY** (safe to share)

**View Public Key:**
```
cat ~/.ssh/id_rsa.pub
```

### Understanding Public/Private Key Cryptography

**How It Works:**
1. Private key stays on web01 (client)
2. Public key copied to docker01 (server)
3. During SSH connection:
   - Server sends encrypted challenge using public key
   - Client decrypts with private key
   - Proves identity without sending a password

**Why It's Secure:**
- Private key never transmitted
- Public key alone can't decrypt
- Mathematically linked, but can't derive one from the other
- 4096-bit RSA is extremely difficult to break

**Security Rules:**
- **NEVER** commit private keys to Git
- Public keys are safe to share
- Private key = your identity
- Losing private key = locked out

### Adding Public Key to Repository

```
cd ~/Sys265
cp ~/.ssh/id_rsa.pub linux/web01/

git add linux/web01/id_rsa.pub
git commit -m "Added web01 public SSH key"
git push origin main
```

### Manual SSH Key Authentication Test

**Pull Changes on docker01:**
```
cd ~/Sys-265
git pull origin main
```

**Manually Create Test User:**
```
# Create user SYS265
sudo useradd -m -s /bin/bash SYS265

# Create .ssh directory
sudo mkdir -p /home/SYS265/.ssh

# Copy public key to authorized_keys
sudo cp ~/sys265-repos/linux/web01/id_rsa.pub /home/SYS265/.ssh/authorized_keys

# Critical permissions
sudo chmod 700 /home/SYS265/.ssh
sudo chmod 600 /home/SYS265/.ssh/authorized_keys
sudo chown -R SYS265:SYS265 /home/SYS265/.ssh
```

**Why These Permissions Matter:**

**700 on .ssh directory:**
- Owner: read, write, execute (rwx)
- Group: no permissions (---)
- Others: no permissions (---)
- Only the user can access their .ssh directory

**600 on authorized_keys:**
- Owner: read, write (rw-)
- Group: no permissions (---)
- Others: no permissions (---)
- SSH refuses to work if permissions are too open (security feature)

**Test Passwordless Login from web01:**
```
ssh SYS265@docker01-Ben.ben.local
```

Should log in immediately without a  password prompt. (Might have to say yes to confirm first time)

### Automating with Complete Script

**Enhanced secure-ssh.sh:**
```
#!/bin/bash
# secure-ssh.sh
# Ben Deyot - SYS-265
# Creates user with SSH key-only authentication
# Usage: ./secure-ssh.sh <username>

if [ -z "$1" ]; then
    echo "Usage: ./secure-ssh.sh <username>"
    exit 1
fi

USERNAME=$1
PUBKEY_PATH="$HOME/Sys265/linux/web01/id_rsa.pub"

# Verify public key exists
if [ ! -f "$PUBKEY_PATH" ]; then
    echo "Error: Public key not found at $PUBKEY_PATH"
    exit 1
fi

echo "Creating user: $USERNAME"

# Create user with no password
sudo useradd -m -s /bin/bash $USERNAME

# Create .ssh directory
sudo mkdir -p /home/$USERNAME/.ssh

# Copy public key to authorized_keys
sudo cp $PUBKEY_PATH /home/$USERNAME/.ssh/authorized_keys

# Set correct permissions
sudo chmod 700 /home/$USERNAME/.ssh
sudo chmod 600 /home/$USERNAME/.ssh/authorized_keys
sudo chown -R $USERNAME:$USERNAME /home/$USERNAME/.ssh

echo "User $USERNAME created successfully with SSH key authentication"
echo "Test with: ssh $USERNAME@docker01-Ben.ben.local"
```

**Script Breakdown:**

**Parameter Validation:**
```
if [ -z "$1" ]; then
    echo "Usage: ./secure-ssh.sh <username>"
    exit 1
fi
```
- `-z` tests if parameter is empty
- Provides usage message if no username given
- `exit 1` indicates an error

**File Existence Check:**
```bash
if [ ! -f "$PUBKEY_PATH" ]; then
    echo "Error: Public key not found"
    exit 1
fi
```
- `-f` tests if file exists
- `!` negates the test
- Prevents script from failing silently

**User Creation:**
```
sudo useradd -m -s /bin/bash $USERNAME
```
- `-m` creates home directory
- `-s /bin/bash` sets login shell
- No password set = passwordless account

**Automated Permission Setting:**
```
sudo chmod 700 /home/$USERNAME/.ssh
sudo chmod 600 /home/$USERNAME/.ssh/authorized_keys
sudo chown -R $USERNAME:$USERNAME /home/$USERNAME/.ssh
```
- Sets proper permissions automatically
- `-R` recursive ownership change
- Ensures SSH will accept the configuration

### Testing the Script

**Run Script:**
```
cd ~/Sys-265
./scripts/secure-ssh.sh testuser12
```

**Expected Output:**
```
Creating user: testuser12
User testuser12 created successfully with SSH key authentication
Test with: ssh testuser12@docker01-Ben.ben.local
```

**Test from web01:**
```
ssh testuser12@docker01-Ben.ben.local
```

Should log in immediately without a password!

### Pushing Final Script

```
git add scripts/secure-ssh.sh
git commit -m "Completed secure-ssh.sh with automated SSH key setup"
git push origin main
```

## Research and Learning

### Topic 1: Git Distributed Version Control

#### What I Didn't Know
I wasn't familiar with Git's distributed architecture versus centralized version control systems.

#### Research Results

**Git's Three-Tree Architecture:**
1. Working Directory - files being edited
2. Staging Area - changes ready to commit
3. Repository - committed history

**Workflow:** Working Directory → (add) → Staging → (commit) → Repository → (push) → Remote

**Why Distributed:**
- Full history on every machine
- Work offline, commit locally
- No single point of failure
- Industry standard (GitHub, GitLab)

#### Lab Application
Used Git workflow across docker01, mgmt01, and web01, all through GitHub remote repository.

#### Why It Matters
Essential for Infrastructure as Code, configuration management, disaster recovery, and team collaboration.

### Topic 2: Bash Script Error Handling

#### What I Didn't Know
How to properly validate input and handle errors in scripts.

#### Research Results

**Input Validation:**
```bash
if [ -z "$1" ]; then
    echo "Usage: $0 <parameter>"
    exit 1
fi
```

**File Testing:**
- `-f` file exists
- `-d` directory exists
- `-e` exists (any type)
- `!` negates the test

**Best Practices:**
- Validate all parameters
- Check file existence before operations
- Return meaningful exit codes (0=success, 1=error)
- Quote variables for spaces

#### Lab Application
secure-ssh.sh validates the username parameter, checks public key exists, provides error messages, uses proper exit codes.

#### Why It Matters
Automation reduces errors, ensures consistency, provides documentation, and scales across systems.

## Conclusion

### Reflections

Working with Git across Ubuntu, Windows, and Rocky Linux helped with cross-platform development skills. The SSH hardening showed security.

**What Went Well:**
- Git workflow is easy and similar after initial setup
- SSH key authentication worked perfectly
- Script automation is always good, even after the first use

**Challenges:**
- 403 error until the Personal Access Token was understood
- SSH permissions must be exact (700/600)
- Understanding commit vs push timing

**Key Learnings:**

1. **Version Control Essential:** Configurations, scripts, and documentation all benefit from Git tracking
2. **SSH Keys > Passwords:** Eliminates entire attack classes
3. **Automation Value:** secure-ssh.sh reduces 6 commands to a single execution
4. **Cross-Platform Consistency:** Git provides same workflow everywhere

### Final

**Infrastructure:**
- Git on all systems (docker01, mgmt01, web01)
- SSH key-based authentication web01 -> docker01
- Automated user provisioning (secure-ssh.sh)

**Skills Demonstrated:**
- Git workflow (clone, add, commit, push, pull)
- Cross-platform version control
- SSH keypair generation and deployment
- Bash automation and error handling
- Secure authentication configuration
