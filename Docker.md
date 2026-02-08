# LAB - Docker Containerization

## Summary
In this lab, I set up a new Ubuntu Server VM (docker01-Ben) and configured Docker containerization. This was my first experience with Ubuntu Server networking (Netplan), and I learned the differences between traditional virtualization and containerization. We deployed multiple containers, including nginx and a full WordPress stack using Docker Compose.

* Create a new VM named docker01 in Proxmox
* Connect to the LAN network (same as other VMs)
* Take a snapshot labeled "Beginning - Pre-setup"

## docker01-Ben Initial Setup

### Ubuntu Installation
* Boot from Ubuntu Server ISO
* Follow installation prompts
* Create initial user: champuser
* Complete installation and reboot
* Login as champuser

### Network Configuration with Netplan

#### Finding Network Interface
```
ip addr show
```
* Interface name: ens18

#### Configuring Static IP with Netplan
The configuration file is located at `/etc/netplan/00-installer-config.yaml` and uses YAML format.

```
sudo vi /etc/netplan/00-installer-config.yaml
```

**Critical YAML Rules:**
* MUST use spaces, NEVER tabs
* Each indent level is exactly 2 spaces
* Colons must have a space after them
* One wrong space breaks everything

**Configuration:**
```
network:
  version: 2
  ethernets:
    ens18:
      dhcp4: no
      addresses:
        - 10.0.5.12/24
      routes:
        - to: default
          via: 10.0.5.2
      nameservers:
        addresses:
          - 10.0.5.5
        search:
          - ben.local
```

**Apply Configuration:**
```
sudo netplan apply
```

**Verify Networking:**
```
ip addr show
ping 10.0.5.2    # Gateway
ping 10.0.5.5    # DNS
ping 8.8.8.8     # Internet
```

### Hostname Configuration

#### Setting Hostname
```
sudo hostnamectl set-hostname docker01-Ben
hostnamectl  # Verify
```

#### Updating /etc/hosts
```
sudo vi /etc/hosts
```

```
127.0.0.1 localhost
127.0.1.1 docker01-Ben.ben.local docker01-Ben
10.0.5.12 docker01-Ben.ben.local docker01-Ben
```

#### Preserving Hostname in cloud.cfg
Ubuntu's cloud-init can reset hostnames on reboot. To prevent this:

```
sudo vi /etc/cloud/cloud.cfg
```

Find and modify:
```
preserve_hostname: true
```

**Reboot and verify:**
```
sudo reboot
```

After reboot:
```
hostname      # Should show: docker01-Ben
hostname -f   # Should show: docker01-Ben.ben.local
```

## Creating Named Admin User

### Understanding Ubuntu Admin Groups
Ubuntu uses the `sudo` group. This is a difference between Linux.

#### Identifying Admin Groups
```
id champuser
```

Output shows groups including `sudo`. This is what gives admin privileges on Ubuntu.

#### Creating User Ben
```
sudo useradd -m -s /bin/bash Ben
```
* `-m` creates home directory
* `-s /bin/bash` sets the default shell

#### Setting Password
```
sudo passwd Ben
```

#### Adding to Admin Groups
```
sudo usermod -aG sudo Ben
sudo usermod -aG adm,cdrom,dip,plugdev Ben
```

#### Testing Sudo Access
```
su - Ben
sudo whoami  # Should return 'root'
```

## SSH Security Configuration

### Disabling Root SSH Login
```
sudo vi /etc/ssh/sshd_config
```

Find and modify:
```
PermitRootLogin no
```

Remove `#` if the line is commented out.

### Restarting SSH Service
```
sudo systemctl restart sshd
sudo systemctl status sshd
```

## DNS Configuration (On MGMT-01)

### Creating Forward Lookup (A Record)
* Move to MGMT-01 as ben.deyot-adm
* Server Manager → Tools → DNS
* Forward Lookup Zones → ben.local
* Right-click → New Host (A or AAAA)
* Name: docker01-Ben
* IP: 10.0.5.12
* Check the PTR 
* Add Host

### Verification from WKS-01
```
nslookup docker01-Ben.ben.local
ping docker01-Ben.ben.local
```

## System Updates
```
sudo apt update
sudo apt upgrade -y
```

## Installing Docker

### Prerequisites
```
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
```

### Adding Docker Repository
```
# Add Docker's GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Add Docker repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

### Installing Docker Engine
```
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io
```

### Verifying Installation
```
sudo systemctl status docker
docker --version
```

### Adding User to Docker Group
```
sudo usermod -aG docker Ben
```
* Log out and back in for this to take effect
* Allows running Docker commands without sudo

### Testing Docker
```
sudo docker run hello-world
```

## Installing Docker Compose

### Download and Install
```
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

### Verification
```
docker-compose --version
```

## Container Deployments

### Nginx Web Server
```
sudo docker run -d -p 80:80 --name my-nginx nginx
```

**Command Breakdown:**
* `-d` = detached mode (runs in background)
* `-p 80:80` = maps container port 80 to host port 80
* `--name my-nginx` = names the container
* `nginx` = the image to use

**Verification:**
```
sudo docker ps
curl localhost
```

**Testing from MGMT-01:**
* Navigate to http://docker01-Ben.ben.local
* Should see the nginx welcome page

<img width="800" alt="nginx from browser" src="placeholder" />

### Arch Linux Hello Message
```bash
sudo docker run --rm archlinux /bin/echo "HELLO SYS-265 SNOWY DAYS"
```

**Command Breakdown:**
* `--rm` = automatically remove container after it exits
* `archlinux` = the image to use
* `/bin/echo "..."` = command to run inside container

<img width="800" alt="arch linux hello message" src="placeholder" />

### Listing Images
```bash
sudo docker images
```

Shows all downloaded Docker images including archlinux.

## Container vs VM: Kernel Investigation

### Host System Information
```bash
lsb_release -a    # Ubuntu version
uname -r          # Kernel version
```

### Running Interactive Ubuntu Container
```bash
sudo docker run -it ubuntu /bin/bash
```

Inside the container:
```bash
uname -r  # Check kernel version
exit
```

**Critical Discovery:**
The kernel version inside the container is **identical** to the host system's kernel. This reveals a fundamental difference between containers and virtual machines:

* **Virtual Machines:** Each VM runs its own complete operating system with its own kernel. A Windows VM runs a Windows kernel, a Linux VM runs a Linux kernel, etc.
* **Containers:** Containers share the host's kernel. They provide process and filesystem isolation but run directly on the host kernel.

This is why containers are so lightweight - they don't need to boot an entire OS or manage a separate kernel. They're essentially isolated processes running on the host kernel with their own filesystem and network namespace.

<img width="800" alt="kernel comparison" src="placeholder" />

## Python Web Application

### Deploying the App
```bash
sudo docker run -d -P training/webapp python app.py
```

**Understanding the Flags:**
* `-d` (detached): Runs container in background. The container runs as a daemon and doesn't occupy your terminal. You get your command prompt back immediately after starting the container.
* `-P` (publish-all): Publishes all exposed container ports to random high-numbered ports on the host (typically 32768+). Docker automatically maps exposed ports without manual specification.

### Checking Port Assignment
```bash
sudo docker ps
```

Output shows something like:
```
PORTS: 0.0.0.0:32770->5000/tcp
```

This means container port 5000 is mapped to host port 32770 (your port will vary).

### Configuring Firewall
```bash
sudo ufw allow 32770/tcp  # Use YOUR actual port
sudo ufw status
```

### Testing from MGMT-01
Navigate to: http://docker01-Ben.ben.local:32770

<img width="800" alt="python webapp from browser" src="placeholder" />

### Stopping the Container
```bash
sudo docker ps  # Get container name/ID
sudo docker stop <container_name_or_id>
```

## WordPress Deployment with Docker Compose

### Project Setup
```bash
mkdir ~/wordpress
cd ~/wordpress
```

### Creating docker-compose.yml

**CRITICAL:** Never use tabs in YAML files. Use spaces only. One tab will break the entire file.

```bash
vi docker-compose.yml
```

**Pro Tips for Editing:**
* Type `i` to enter insert mode
* Right-click to paste (or Shift+Insert)
* Press `Esc` to exit insert mode
* Type `:wq` to save and quit
* If you mess up: `:q!` to quit without saving

**Configuration File:**
```yaml
version: '3.3'

services:
  db:
    image: mysql:5.7
    volumes:
      - db_data:/var/lib/mysql
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: somewordpress
      MYSQL_DATABASE: wordpress
      MYSQL_USER: wordpress
      MYSQL_PASSWORD: wordpress

  wordpress:
    depends_on:
      - db
    image: wordpress:latest
    ports:
      - "80:80"
    restart: always
    environment:
      WORDPRESS_DB_HOST: db:3306
      WORDPRESS_DB_USER: wordpress
      WORDPRESS_DB_PASSWORD: wordpress
      WORDPRESS_DB_NAME: wordpress

volumes:
  db_data:
```

### Stopping Nginx (Free Port 80)
```bash
sudo docker stop my-nginx
```

### Starting WordPress Stack
```bash
sudo docker-compose up -d
```

This command:
* Downloads MySQL and WordPress images
* Creates containers for both services
* Sets up networking between containers
* Starts both services in detached mode

### Verifying Deployment
```bash
sudo docker-compose ps
sudo docker ps
```

Should show two containers running:
* wordpress_db_1 (MySQL database)
* wordpress_wordpress_1 (WordPress application)

### WordPress Installation via Browser

**Accessing WordPress:**
* From MGMT-01, navigate to: http://docker01-Ben.ben.local
* Follow WordPress installation wizard

**Installation Steps:**
1. Select language (English)
2. Click Continue
3. Fill out site information:
   * Site Title: SYS-265 Docker Lab - Ben Deyot
   * Username: ben.deyot
   * Password: (create secure password)
   * Email: ben.deyot@ben.local
4. Click "Install WordPress"
5. Log in with credentials

**Creating Content:**
* Create a post titled "Docker Containerization Lab"
* Include references to SYS-265 and your name
* Demonstrate WordPress is fully functional

<img width="800" alt="wordpress installation" src="placeholder" />

## Frequently Used Docker Commands

### Container Management
```bash
# Run a container
docker run [options] <image> [command]

# List running containers
docker ps

# List all containers (including stopped)
docker ps -a

# Stop a container
docker stop <container_id_or_name>

# Start a stopped container
docker start <container_id_or_name>

# Remove a container
docker rm <container_id_or_name>

# View container logs
docker logs <container_id_or_name>

# Execute command in running container (interactive shell)
docker exec -it <container_id_or_name> /bin/bash

# Remove all stopped containers
docker container prune
```

### Image Management
```bash
# List images
docker images

# Pull an image from Docker Hub
docker pull <image_name>

# Remove an image
docker rmi <image_name>

# Remove unused images
docker image prune
```

### Docker Compose Commands
```bash
# Start services (detached)
docker-compose up -d

# Stop and remove services
docker-compose down

# View running services
docker-compose ps

# View logs
docker-compose logs

# Restart services
docker-compose restart
```

### Useful Options
* `-d` = detached mode (background)
* `-it` = interactive terminal
* `-p 8080:80` = port mapping (host:container)
* `-P` = publish all exposed ports automatically
* `--name` = assign a name to the container
* `--rm` = remove container automatically after exit
* `-v` = volume mounting for persistent data

### Docker Networking
```bash
# List networks
docker network ls

# Inspect a network
docker network inspect <network_name>

# Create a network
docker network create <network_name>
```

## Network Configuration Comparison: Ubuntu vs Rocky Linux

### Configuration Method
**Rocky Linux:**
* Uses `nmtui` (Network Manager Text User Interface)
* Interactive GUI-like interface in terminal
* Configuration stored in `/etc/sysconfig/network-scripts/`

**Ubuntu:**
* Uses Netplan
* YAML configuration files
* Configuration in `/etc/netplan/`
* More declarative approach

### Configuration File Differences

**Rocky Linux (nmtui generates):**
```
BOOTPROTO=none
IPADDR=10.0.5.50
PREFIX=24
GATEWAY=10.0.5.2
DNS1=10.0.5.5
```

**Ubuntu (Netplan YAML):**
```yaml
network:
  version: 2
  ethernets:
    ens18:
      dhcp4: no
      addresses:
        - 10.0.5.12/24
      routes:
        - to: default
          via: 10.0.5.2
      nameservers:
        addresses:
          - 10.0.5.5
```

### Applying Changes

**Rocky Linux:**
```bash
nmtui  # Make changes in interface
# Changes apply automatically or:
sudo systemctl restart NetworkManager
```

**Ubuntu:**
```bash
sudo vi /etc/netplan/00-installer-config.yaml  # Edit YAML
sudo netplan apply  # Apply changes
```

### Troubleshooting

**Rocky Linux:**
```bash
nmcli connection show
nmcli device status
```

**Ubuntu:**
```bash
sudo netplan --debug apply
ip addr show
```

## User Administration: Ubuntu vs Rocky Linux

### Admin Group Difference

**Rocky Linux:**
* Admin group: `wheel`
* Command: `sudo usermod -aG wheel username`
* Historical Unix convention

**Ubuntu:**
* Admin group: `sudo`
* Command: `sudo usermod -aG sudo username`
* Debian-based convention

### User Creation Comparison

**Rocky Linux:**
```bash
sudo useradd username
sudo passwd username
sudo usermod -aG wheel username
```

**Ubuntu:**
```bash
sudo useradd -m -s /bin/bash username
sudo passwd username
sudo usermod -aG sudo username
```

**Key Differences:**
* Ubuntu requires explicit `-m` flag for home directory creation
* Ubuntu requires explicit `-s /bin/bash` for shell specification
* Different admin group names (wheel vs sudo)

### Verifying Admin Access

**Both Systems:**
```bash
id username  # Check groups
su - username
sudo whoami  # Should return 'root'
```

## Docker Networking Deep Dive

### How Docker Manages Networking

Docker creates a virtual bridge network (docker0) on the host. Containers connect to this bridge and can communicate with each other and the outside world through NAT (Network Address Translation).

### Port Mapping Types

**Manual Port Mapping (-p):**
```bash
docker run -p 8080:80 nginx
```
* Host port 8080 maps to container port 80
* Predictable and explicit
* Can cause conflicts if port already in use

**Automatic Port Publishing (-P):**
```bash
docker run -P training/webapp
```
* Docker assigns random high port (32768-60999)
* No conflicts, but less predictable
* Must check `docker ps` to see assigned port

### Firewall Configuration

Docker modifies iptables rules automatically, but Ubuntu's UFW (Uncomplicated Firewall) operates at a different level. You must explicitly allow traffic to mapped ports:

```bash
sudo ufw allow <port>/tcp
sudo ufw status
```

### Docker Compose Networking

Docker Compose automatically creates a network for services defined in the compose file. Services can communicate using service names as hostnames:

```yaml
wordpress:
  environment:
    WORDPRESS_DB_HOST: db:3306  # 'db' is the service name
```

## Research and Learning

### Topic 1: Container Architecture vs Virtual Machines

#### What I Didn't Know
I wasn't clear on the fundamental architectural differences between containers and VMs, particularly regarding the kernel.

#### Research Results

**Virtual Machines:**
* Full OS stack including kernel
* Hardware virtualization through hypervisor
* Each VM boots complete OS
* Larger resource footprint (GBs)
* Slower startup (minutes)
* Strong isolation at hardware level

**Containers:**
* Share host kernel
* OS-level virtualization
* Isolated user space
* Smaller footprint (MBs)
* Near-instant startup (seconds)
* Process-level isolation

#### Lab Evidence
The kernel investigation clearly showed both the host (docker01) and the Ubuntu container were running the same kernel version. This proved containers don't have their own kernel - they're isolated processes running on the host kernel.

#### Why It Matters
* Containers can't run a different OS type (can't run Windows containers on Linux host without special setup)
* Containers are portable but kernel-dependent
* Much more efficient resource usage
* Better for microservices architecture
* VMs better for full OS isolation or running different OS types

### Topic 2: Docker Compose and Multi-Container Applications

#### What I Didn't Know
I didn't understand how Docker Compose orchestrates multiple containers and manages their dependencies.

#### Research Results

**Docker Compose Features:**
* Defines multi-container apps in single YAML file
* Manages service dependencies (`depends_on`)
* Creates isolated networks for services
* Manages volumes for persistent data
* Can scale services up/down

**WordPress Example Architecture:**
* Database service (MySQL)
* Application service (WordPress)
* Shared network for communication
* Persistent volume for database data
* Environment variables for configuration

#### Key Concepts
**Services:** Containers defined in compose file
**Networks:** Docker creates default network for all services
**Volumes:** Named volumes persist data beyond container lifecycle
**Dependencies:** `depends_on` ensures MySQL starts before WordPress

#### Why It Matters
* Simplifies multi-container deployments
* Version control for entire application stack
* Reproducible environments
* Easy scaling and updates
* Industry standard for local development

### Topic 3: YAML Syntax and Configuration Management

#### What I Didn't Know
I had minimal experience with YAML and didn't realize how strict the parsing is.

#### Research Results

**YAML (YAML Ain't Markup Language):**
* Human-readable data serialization format
* Widely used in Docker, Kubernetes, Ansible, CI/CD
* Strict syntax enforcement

**Critical Rules:**
* Spaces only, no tabs
* Indentation matters (like Python)
* Colons must have space after them
* Lists use hyphens
* Quotes usually optional for strings

**Common Mistakes:**
* Mixing tabs and spaces (invisible errors)
* Wrong indentation level
* Missing spaces after colons
* Inconsistent list formatting

#### Lab Application
The docker-compose.yml file was unforgiving. One wrong space caused the entire stack to fail. This taught me the importance of:
* Using proper text editors (vi with visible whitespace)
* Copy-paste carefully (tabs can sneak in)
* Validating YAML before deploying
* Understanding structure hierarchy

#### Why It Matters
YAML is everywhere in modern DevOps. Mastering it is essential for:
* Docker Compose
* Kubernetes manifests
* Ansible playbooks
* GitLab/GitHub CI/CD pipelines
* Configuration as code practices

## Troubleshooting Log

### Issue 1: Netplan Not Applying
**Problem:** After editing netplan config, changes didn't apply.
**Cause:** Had a tab character in YAML file.
**Solution:** 
```bash
sudo netplan --debug apply  # Showed syntax error
# Recreated file with spaces only
sudo netplan apply  # Worked
```
**Lesson:** YAML is unforgiving. Use spaces only.

### Issue 2: Hostname Not Persisting
**Problem:** Hostname reset to default after reboot.
**Cause:** cloud.cfg had `preserve_hostname: false`.
**Solution:**
```bash
sudo vi /etc/cloud/cloud.cfg
# Changed to preserve_hostname: true
sudo reboot
```
**Lesson:** Ubuntu's cloud-init has specific behaviors that need configuration.

### Issue 3: WordPress Port 80 Conflict
**Problem:** WordPress wouldn't start, port 80 already in use.
**Cause:** nginx container still running.
**Solution:**
```bash
sudo docker ps  # Found nginx container
sudo docker stop my-nginx
sudo docker-compose up -d  # Success
```
**Lesson:** Only one service can bind to a port at a time. Check running containers first.

### Issue 4: Can't Access Containers from MGMT-01
**Problem:** Could access containers locally but not from other VMs.
**Cause:** UFW firewall blocking ports.
**Solution:**
```bash
sudo ufw allow 80/tcp
sudo ufw allow 32770/tcp  # For Python app
sudo ufw reload
```
**Lesson:** Docker manages iptables but doesn't configure UFW. Must explicitly allow ports.

## Conclusion

### Opinions and Reflections

This lab was significantly different from our previous work because it introduced containerization - a fundamentally different approach to application deployment than traditional VMs. The shift from Rocky Linux to Ubuntu also provided valuable exposure to different Linux distributions and their quirks.

**What Went Well:**
* The step-by-step progression from basic Docker to Docker Compose was logical
* Kernel investigation clearly demonstrated container architecture
* WordPress deployment showed real-world application of multi-container orchestration
* Documentation was thorough and deliverables were clear

**Challenges:**
* YAML syntax in docker-compose.yml was frustrating initially - invisible tabs caused errors
* Ubuntu's Netplan was less intuitive than nmtui, but more powerful once understood
* Understanding when to use sudo with docker commands (before adding user to docker group)
* Firewall configuration - Docker modifies iptables but UFW operates differently

**Key Learnings:**

1. **Containers vs VMs:** Containers share the host kernel and are fundamentally lightweight process isolation, not full virtualization. This makes them incredibly efficient but kernel-dependent.

2. **Ubuntu Administration:** Different from Rocky Linux in meaningful ways (sudo vs wheel group, Netplan vs nmtui, apt vs dnf). Understanding these differences is crucial for multi-distribution environments.

3. **Docker Networking:** Port mapping can be manual (-p) or automatic (-P). Firewall rules must be explicit. Container-to-container communication works by service name in Docker Compose.

4. **Infrastructure as Code:** docker-compose.yml represents infrastructure as code - the entire WordPress stack defined in ~30 lines. This is version-controllable, reproducible, and portable.

5. **YAML Mastery:** Critical skill for modern DevOps. Strict syntax teaches attention to detail and precision in configuration management.

### Real-World Applications

This lab demonstrated practical skills used in production environments:

* **Microservices Deployment:** Docker Compose patterns scale to Kubernetes
* **Development Environments:** Containers provide consistent dev/prod parity
* **CI/CD Pipelines:** Container images are standard deployment artifacts
* **Multi-Distribution Support:** Understanding Ubuntu and Rocky prepares for diverse environments

### Future Exploration

I'd like to explore:
* **Docker volumes in detail:** How to properly handle persistent data and backups
* **Docker networks:** Custom networks, network isolation, service discovery
* **Docker security:** Image scanning, secrets management, least privilege
* **Kubernetes:** How Docker Compose concepts translate to K8s
* **Container monitoring:** How to integrate containers with our existing SNMP monitoring

### Final

We successfully deployed docker01-Ben running Ubuntu Server with full Docker and Docker Compose capability. The system integrates with our existing infrastructure (DNS, networking, domain) and hosts multiple containerized applications including nginx, a Python web app, and a full WordPress stack with MySQL. The lab provided essential foundation in containerization technology and cross-distribution Linux administration.

**Current Infrastructure:**
* FW-01: 10.0.5.2 (pfSense)
* AD-01: 10.0.5.5 (Windows Server Core)
* MGMT-01: 10.0.5.10 (Windows Server)
* WKS-01: 10.0.5.100 (Windows 10)
* WEB-01: 10.0.5.50 (Rocky Linux)
* NMON-01: 10.0.5.51 (Rocky Linux)
* **docker01-Ben: 10.0.5.12 (Ubuntu Server) - NEW**

All systems communicate via DNS (ben.local), route through FW-01, and are monitored via SNMP on NMON-01. We now have experience with three different operating systems in our infrastructure: Windows Server, Rocky Linux, and Ubuntu Server.
