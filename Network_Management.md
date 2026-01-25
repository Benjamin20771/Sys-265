# Network Management
## Summary
In this lab, we started by configuring web01/nmon01 and then did an overall configuration of SNMP on most of our devices. We are configuring SNMP so we can have network management throughout our system. Although it was a simple enough lab, it was easy to get lost and easy to confuse one thing for another, which reinforced my need to have more knowledge on network management. nmon01 is our main system to hold SNMP, while fw01, ad01, web01 had it configured on their systems.

## Web-01/NMON-01 setup
### New User
* sudo useradd Ben
* sudo passwd Ben (Then type password)
* sudo usermod -aG wheel Ben
* Switch to the new user


### NMTUI
#### Web-01
<img width="1006" height="458" alt="image" src="https://github.com/user-attachments/assets/89b1bb6e-79a3-4786-b2e6-e23e24680be2" />

#### NMON-01
<img width="1010" height="452" alt="image" src="https://github.com/user-attachments/assets/f25aab2b-d656-49e7-a65a-94fa8bfb8b10" />

## FW-01 SNMP
### Adding SNMP 
* Log into WKS-01 and go to the system wizard for the firewall
* Go to Services -> SNMP
* Look at screenshots below for refrencing on information to fill out (Community string should be specific to you)
<img width="1898" height="1086" alt="image" src="https://github.com/user-attachments/assets/ad6c8576-aa47-4519-97a0-7b27c0e7708b" />
<img width="1900" height="286" alt="image" src="https://github.com/user-attachments/assets/66eefb7f-bfa7-4039-952f-19110f14a05f" />
* Don't forget to restart SNMP at the top right

## Installing SNMP on NMON-01
### Install SNMP packages
```
dnf install -y net-snmp net-snmp-utils
```
### Backup the original config and create a new one
```
sudo cp /etc/snmp/snmpd.conf /etc/snmp/snmpd.conf.backup
sudo truncate -s 0 /etc/snmp/snmpd.conf
```
### Edit configuration file
```
sudo nano /etc/snmp/snmpd.conf
```
* Add these four lines:
```
com2sec myNetwork 10.0.5.0/24 SYS265/Benji
group myROGroup v2c myNetwork
view all included .1 80
access my ROGroup "" any noauth exact all none none
```

### Enable and start the service
```
sudo systemctl enable snmpd
sudo systemctl start snmpd
sudo systemctl status snmpd
```
### Configure firewall
```
sudo firewall-cmd --permanent --add-service=snmp
sudo firewall-cmd --reload
sudo firewall-cmd --list-all
```
* Note: SNMP uses UDP port 161

## Test SNMP from NMON-01
### Query web01 system information
```
snmpwalk -v2c -c SYS265 web01.ben.local system
```
#### Command breakdown:

* -v2c = SNMP version 2c
* -c SYS265/Benji = community string
* web01.ben = target host
* system = OID (Object Identifier) to query

## Install SNMP on AD-01
### Using Server Manager on MGMT01
* Server Manager → Manage → Add Roles and Features
* Select AD01 as the target server
* Features → Check "SNMP Service"
* Install

## Install SNMP Tools on MGMT-01
### Via Server Manager

* Add Roles and Features
* Features → RSAT → Feature Administration Tools
* Check "SNMP Tools"
* Install 

## Enable Remote Management on AD-01
### Enable firewall rules via PowerShell
#### powershell# Connect to AD01
```
Enter-PSSession -ComputerName ad01
```
#### Enable Remote Event Log Management rules
```
Set-NetFirewallRule -DisplayGroup "Remote Event Log Management" -Enabled True
```
#### Verify rules are enabled
```
Get-NetFirewallRule -DisplayGroup "Remote Event Log Management" | Select-Object DisplayName, Enabled
```
#### Exit session
```
Exit-PSSession
```
### Test Computer management
* Open computer management on AD-01
* No error should pop up


## Configure SNMP on AD-01
*Open Services on AD-01
*Find "SNMP Service" → Properties
* Security tab:
  * Add community: "SYS265/Benji" with READ ONLY rights
  * Under "Accept SNMP packets from these hosts": Add NMON-01's hostname
* Apply and restart the SNMP Service

## Query AD-01 from NMON-01
* Test SNMP connectivity
* Query system information
```
snmpwalk -v2c -c SYS265 ad01.ben.local system
```

### See how many OIDs are available
```
snmpwalk -v2c -c SYS265 ad01.ben.local | wc -l
```
* Should return thousands of lines of SNMP data from AD01

## Capture SNMP Packets with tcpdump
* On web01, start packet capture
* First, find your network interface
```
ip addr show
```

### Run tcpdump 
```
sudo tcpdump -i ens18 -A -c 10 port 161
```
Command breakdown:
* -i ens18 = interface to listen on
* -A = display packets in ASCII format
* -c 10 = capture 10 packets then stop
* port 161 = filter for SNMP traffic only

### On NMON-01, generate SNMP traffic
```
snmpwalk -v2c -c SYS265/Benji web01.ben system
```
#### Result
* tcpdump output will show the community string "SYS265/Benji" in clear-text ASCII, so that anyone sniffing network traffic can see it!

## Research Results on SNMP
### Topic 1: OIDs (Object Identifiers) and MIB Structure
#### What I Didn't Know
* I was unfamiliar with how SNMP organizes data in a hierarchical tree structure using OIDs
#### Research Results
* OID Structure:
  * OIDs are dot-notation addresses in a tree, like 1.3.6.1.2.1.1.5.0
#### Common OID Branches:

* 1.3.6.1.2.1.1 = system (sysName, sysUpTime, sysLocation)
* 1.3.6.1.2.1.2 = interfaces (network stats)
* 1.3.6.1.2.1.25 = host resources (CPU, memory, processes)

#### Lab Examples:
* Query system info
```
snmpwalk -v2c -c SYS265 web01.ben.local system
```

#### Get specific value
```
snmpget -v2c -c SYS265/Benji web01.ben sysUpTime.0
```
#### Why It Matters:
* OIDs are standardized addresses - any device supporting standard MIBs can be queried the same way. Monitoring tools use specific OIDs to collect metrics like CPU, memory, and disk usage.

### Topic 2: SNMP Security Vulnerabilities (SNMPv1/v2c vs SNMPv3)
#### What I Didn't Know
* I didn't realize how insecure SNMPv1/v2c is, transmitting everything in clear text.
#### Research Results
##### SNMPv1/v2c Security Flaws:

* Clear text community strings, passwords visible on the network
* No encryption, all data is readable by anyone sniffing traffic
* No authentication is easy to spoof
* Replay attacks are possible, captured packets can be reused

#### Lab Evidence:
```
sudo tcpdump -i ens18 -A -c 10 port 161
```
#### Clearly showed "SYS265/Benji" community string in ASCII
#### SNMPv3 Improvements:
* Authentication: HMAC-MD5 or HMAC-SHA to verify sender
* Encryption: DES or AES to encrypt SNMP data
* User-based security: Individual user accounts instead of shared community strings

### Topic 3: SNMP Traps vs Polling
#### What I Didn't Know
* I thought SNMP only worked by the manager querying devices. I didn't know about SNMP traps where devices push alerts.
#### Research Results
* Two SNMP Communication Models:
1. Polling (What we used in lab):
* Manager actively queries agents on a schedule
* Uses UDP port 161
* Manager controls when data is collected
```
snmpwalk -v2c -c SYS265/Benji web01.ben system
```
Pros: Predictable, reliable, manager controls timing
Cons: Can miss events between polls, generates constant network traffic
2. Traps (Event-driven):
*Agents send unsolicited alerts to the manager
* Uses UDP port 162
* Device notifies manager when something important happens
Examples: Interface down, high CPU, disk full, unauthorized access attempt

#### What to do:
* Use polling for regular metrics (CPU, memory, bandwidth)
* Use traps for critical events (failures, threshold breaches)
* Reduces network overhead while catching important events immediately

#### Why It Matters:
* Polling alone might miss critical events. Traps enable real-time alerting for issues like interface failures or security violations, allowing faster incident response.

## Conslusion
This lab was a really good command lab in that everything I could do with the GUI, I could also do in commands or on PowerShell. I feel like I learned a little more about how the commands work and what everything means in the command. I feel like the only thing that I left without learning a lot about was the SNMP, and that I understand what it does, but I want to see more of it in action. I understand this is our second lab of the semester, so I need to be patient lol. I really enjoyed the configuration part and setting everything up on the VM. I can't wait to see what we do with SNMP next, as I really enjoy the concept of network monitoring.


















