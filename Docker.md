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

### Arch Linux Hello Message
```
sudo docker run --rm archlinux /bin/echo "HELLO SYS-265 SNOWY DAYS"
```

**Command Breakdown:**
* `--rm` = automatically remove container after it exits
* `archlinux` = the image to use
* `/bin/echo "..."` = command to run inside container

### Listing Images
```
sudo docker images
```

Shows all downloaded Docker images, including archlinux.

### Deploying the App
```
sudo docker run -d -P docker/getting-started
```

**Understanding the Flags:**
* `-d` (detached): Runs container in background. The container runs as a daemon and doesn't occupy your terminal. You get your command prompt back immediately after starting the container.
* `-P` (publish-all): Publishes all exposed container ports to random high-numbered ports on the host (typically 32768+). Docker automatically maps exposed ports without manual specification.

### Checking Port Assignment
```
sudo docker ps
```

Output shows something like:
```
PORTS: 0.0.0.0:32768->80/tcp
```

This means container port 80 is mapped to host port 32768.

### Configuring Firewall
```bash
sudo ufw allow 32768/tcp 
sudo ufw status
```

### Testing from MGMT-01
Navigate to: http://docker01-Ben.ben.local:32770

### Stopping the Container
```
sudo docker ps
sudo docker stop <container_name_or_id>
```

## WordPress Deployment with Docker Compose

### Project Setup
```
mkdir ~/wordpress
cd ~/wordpress
```

### Creating docker-compose.yml

```
vi docker-compose.yml
```

**Configuration File:**
```
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
```
sudo docker stop my-nginx
```

### Starting WordPress Stack
```
sudo docker-compose up -d
```

This command:
* Downloads MySQL and WordPress images
* Creates containers for both services
* Sets up networking between containers
* Starts both services in detached mode

### Verifying Deployment
```
sudo docker-compose ps
sudo docker ps
```

Should show two containers running:
* wordpress_db_1 (MySQL database)
* wordpress_wordpress_1 (WordPress application)

### WordPress Installation via Browser

**Accessing WordPress:**
* From MGMT-01, navigate to: http://docker01-Ben.ben.local
* Follow the WordPress installation wizard

**Installation Steps:**
1. Select language (English)
2. Click Continue
3. Fill out site information:
   * Site Title: SYS-265 Docker Lab - Ben Deyot
   * Username: ben.deyot
   * Password: (create a secure password)
   * Email: bdeyot@icloud.com
4. Click "Install WordPress"
5. Log in with credentials

**Creating Content:**
* Create a post titled "SYS-265 B.A.D"
* SYS-265 Ben Deyot

## Frequently Used Docker Commands

### Container Management
```
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

## User Administration: Ubuntu 

**Ubuntu:**
* Admin group: `sudo`
* Command: `sudo usermod -aG sudo username`
* Debian-based convention

### User Creation Comparison

**Ubuntu:**
```
sudo useradd -m -s /bin/bash username
sudo passwd username
sudo usermod -aG sudo username
```

### Verifying Admin Access

**Ubuntu:**
```
id username  # Check groups
su - username
sudo whoami  # Should return 'root'
```

## Research, Learning, and Troubleshooting

### Topic 1: YAML Syntax and Configuration Management

#### What I Didn't Know
I had minimal experience with YAML and didn't realize how strict the parsing is.

#### Research Results

**YAML (YAML Ain't Markup Language):**
* Human-readable data serialization format
* Widely used in Docker, Kubernetes, Ansible, CI/CD
* Strict syntax enforcement

**Common Mistakes(what I did lol):**
* Mixing tabs and spaces (invisible errors)
* Wrong indentation level
* Missing spaces after colons
* Inconsistent list formatting

## Conclusion

### Opinions and Reflections

This lab was significantly different from our previous work because it introduced containerization, which is a fundamentally different approach to application deployment than VMs. The shift from Rocky Linux to Ubuntu also provided exposure to different Linux distributions and their funny differences.

**What Went Well:**
* The step-by-step progression from basic Docker to Docker Compose was easy
* WordPress deployment was straightforward

**Challenges:**
* YAML syntax in dockern-compose.yml was frustrating initially
* Firewall configuration, Docker modifies iptables, but UFW operates differently

**Key Learnings:**

1. **Containers vs VMs:** Containers share the host kernel and are fundamentally lightweight process isolation, not full virtualization. This makes them incredibly efficient but kernel-dependent.

2. **Ubuntu Administration:** Different from Rocky Linux in meaningful ways (sudo vs wheel group, Netplan vs nmtui, apt vs dnf). 

3. **Docker Networking:** Port mapping can be manual (-p) or automatic (-P). Firewall rules must be explicit. Container-to-container communication works by service name in Docker Compose.

4. **YAML Mastery:** Critical skill for cyber. Strict syntax teaches attention to detail and precision in configuration management.

### Final

I successfully deployed docker01-Ben running Ubuntu Server with full Docker and Docker Compose capability. The system integrates with our existing infrastructure (DNS, networking, and domain) and hosts multiple containerized applications, including nginx and a full WordPress stack with MySQL.

**Current Infrastructure:**
* FW-01: 10.0.5.2 (pfSense)
* AD-01: 10.0.5.5 (Windows Server Core)
* MGMT-01: 10.0.5.10 (Windows Server)
* WKS-01: 10.0.5.100 (Windows 10)
* WEB-01: 10.0.5.50 (Rocky Linux)
* NMON-01: 10.0.5.51 (Rocky Linux)
* **docker01-Ben: 10.0.5.12 (Ubuntu Server) - NEW**

All systems communicate via DNS (ben.local), route through FW-01, and are monitored via SNMP on NMON-01. All OS's include: Windows Server, Rocky Linux, and Ubuntu Server.
