# Pi-hole + Unbound DNS Firewall - Docker Project

## Summary

This project deploys Pi-hole (DNS firewall) and Unbound (recursive DNS resolver) as a two-container Docker application. Pi-hole blocks advertisements and malicious domains at the DNS level, while Unbound provides privacy-focused DNS resolution without relying on third-party DNS providers like Google or Cloudflare. The system is multi-container orchestration, DNS-based security, and network-wide protection.

## Architecture

**Components:**
- **Pi-hole** - DNS sinkhole and web-based admin interface
- **Unbound** - Recursive DNS resolver for privacy

**Flow:**
```
Client → Pi-hole → Check Blocklist → If Allowed → Unbound → Root DNS Servers → Return IP
```

**Two Containers:**
- Pi-hole handles filtering and blocking
- Unbound handles upstream DNS resolution privately
- Separation of concerns (filtering vs resolution)
- Privacy benefit (no third-party DNS providers)

## Prerequisites

- Docker and Docker Compose installed on docker01-Ben
- docker01 network: 10.0.5.12/24, Gateway: 10.0.5.2
- systemd-resolved disabled (conflicts with port 53)

## Project Setup

### Directory Structure

```
mkdir -p ~/pihole-project/unbound
cd ~/pihole-project
```

### Docker Compose Configuration

Create `docker-compose.yml`:

```
version: '3.8'

services:
  unbound:
    container_name: unbound
    image: mvance/unbound:latest
    ports:
      - "5335:53/tcp"
      - "5335:53/udp"
    volumes:
      - './unbound:/opt/unbound/etc/unbound'
    restart: unless-stopped

  pihole:
    container_name: pihole
    image: pihole/pihole:latest
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "8080:80/tcp"
    environment:
      TZ: 'America/New_York'
      WEBPASSWORD: 'admin123'
      ServerIP: '10.0.5.12'
      DNS1: '127.0.0.1#5335'
      DNS2: 'no'
    volumes:
      - './etc-pihole:/etc/pihole'
      - './etc-dnsmasq.d:/etc/dnsmasq.d'
    depends_on:
      - unbound
    restart: unless-stopped
```

**Key Settings:**
- Unbound on port 5335 (internal)
- Pi-hole DNS points to Unbound (`DNS1: '127.0.0.1#5335'`)
- Pi-hole web interface on port 8080
- `depends_on: unbound` ensures Unbound starts first

### Unbound Configuration

Create `unbound/unbound.conf`:

```
server:
    interface: 0.0.0.0
    port: 53
    do-ip4: yes
    do-udp: yes
    do-tcp: yes
    do-ip6: no
    
    access-control: 0.0.0.0/0 refuse
    access-control: 127.0.0.1 allow
    access-control: 172.16.0.0/12 allow
    
    hide-identity: yes
    hide-version: yes
    verbosity: 1
```

## Deployment

### Disable Conflicting Services

```
# Stop systemd-resolved (uses port 53)
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved

# Update docker01's DNS
sudo rm /etc/resolv.conf
echo "nameserver 10.0.5.5" | sudo tee /etc/resolv.conf
echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf
```

### Start Containers

```
cd ~/pihole-project
sudo docker-compose up -d
sleep 15
sudo docker-compose ps
```

Both containers should show "Up" status.

### Verify Deployment

**Check logs:**
```
sudo docker logs pihole | tail -20
sudo docker logs unbound
```

**Test DNS locally:**
```
nslookup google.com
```

## Accessing Pi-hole

### Web Interface

From MGMT-01 browser:
```
http://10.0.5.12:8080/admin
```

**Password:** `admin123`

**Reset password if needed:**
```
sudo docker exec -it pihole
>pihole setpassword
```

### Dashboard Overview

- Total queries processed
- Queries blocked (percentage)
- Domains on the blocklist
- Real-time query graph
- Top permitted/blocked domains
- Connected clients

## Testing

### Generate Test Queries

**From MGMT-01 PowerShell:**
```
nslookup google.com
nslookup facebook.com
nslookup youtube.com
```

**Watch Pi-hole dashboard** - queries appear slowly.

### Query Log

View all DNS activity:
1. Pi-hole admin → Query Log
2. Green = Allowed
3. Red = Blocked
4. Shows: domain, client, type, timestamp

## Docker Management

```
# View status
sudo docker-compose ps

# View logs
sudo docker-compose logs -f

# Restart services
sudo docker-compose restart

# Stop everything
sudo docker-compose down

# Update images
sudo docker-compose pull
sudo docker-compose up -d
```

## How It Works

### DNS Firewall Concept

**Traditional Firewall:** Blocks by IP address and port  
**DNS Firewall:** Blocks by domain name before connection

**Process:**
1. Client sends DNS query to Pi-hole
2. Pi-hole checks the domain against blocklists
3. If blocked: Returns 0.0.0.0 (connection fails)
4. If allowed: Forwards to Unbound
5. Unbound performs a recursive DNS lookup
6. IP address returned to client
7. All activity logged

### Privacy with Unbound

**Without Unbound:** Queries sent to Google (8.8.8.8) or Cloudflare (1.1.1.1)
- Third parties see all DNS queries
- Privacy concerns about tracking

**With Unbound:** Recursive DNS resolution
- Queries go directly to root DNS servers
- No third-party involvement
- Complete privacy and control

### Multi-Container Benefits

- **Separation of concerns:** Filtering (Pi-hole) vs Resolution (Unbound)
- **Scalability:** Can add more containers (monitoring, logging, etc.)
- **Dependencies:** Docker Compose manages startup order

## Troubleshooting

### Port 53 Already in Use

**Cause:** systemd-resolved using port 53  
**Solution:**
```
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved
sudo docker-compose restart
```

### Containers Won't Start

**Check logs:**
```
sudo docker-compose logs
```

**Common issues:**
- Port conflicts (stop WordPress if running)
- Permission errors on volumes
- Network conflicts

**Fix permissions:**
```
sudo chmod -R 755 unbound/ etc-pihole/ etc-dnsmasq.d/
```

### Web Interface Not Accessible

**Check if container is running:**
```
sudo docker-compose ps
```

**Restart:**
```
sudo docker-compose restart pihole
```

### Unbound Keeps Restarting

**Check logs:**
```
sudo docker logs unbound
```

**Fix permissions:**
```
sudo chmod 755 unbound/
sudo chmod 644 unbound/unbound.conf
```

## Key Learnings

### Docker Multi-Container Orchestration

- Containers communicate via the Docker bridge network
- Volumes persist data across container restarts
- Single `docker-compose.yml` defines entire stack

### DNS-Based Security

- Blocking at the DNS level prevents connections before they start
- More efficient than content-based filtering
- Works on all devices (network-wide)
- No client software needed

### Privacy vs Public DNS

- Public DNS providers (Google, Cloudflare) log queries
- Recursive DNS (Unbound) queries root servers directly
- Trade-off: Privacy vs speed (recursive is slightly slower)
- Enterprise security often requires recursive DNS

## Conclusion

This project successfully deployed a two-container DNS firewall system using Docker Compose. Pi-hole provides network-wide ad and malware blocking through DNS filtering, while Unbound ensures privacy by performing recursive DNS resolution without third-party DNS providers. The system demonstrates Docker orchestration, DNS-based security techniques, and privacy-focused infrastructure.

**Skills Demonstrated:**
- Multi-container Docker deployment
- Container dependencies and networking
- DNS service configuration
- Network security implementation

**Infrastructure Integration:**
- docker01-Ben: 10.0.5.12 (Ubuntu Server - Pi-hole + Unbound)
- Integrates with existing ben.local domain
- Can serve as primary DNS for the entire network
- Monitored alongside other infrastructure

**Project Benefits:**
- Network-wide ad/malware blocking
- Privacy-focused DNS resolution
- Complete visibility into DNS queries
- Easy management via web interface
- Scalable and maintainable Docker deployment
