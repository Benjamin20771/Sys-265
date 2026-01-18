# LAB 01 - Setting up labs

## Summary
In this lab, at the beginning of the year, we always setup our lab environments, which is what I'm going to document right now. I know how to do almost everything now, so it's mostly going to be the specs. I will document some of the steps in detail if I need to. In this lab, we set up our FW, AD, WKS, and MGMT. MGMT is a new one for us, so I'll go over that one later, a little more in detail. The setup includes Networking and DNS, and basic account handling. 

## Pre-setup
* Change all networking cables to be on our LAN and have the FW have one LAN and one WAN (remember which is which) (DO THIS FIRST)
* Take snapshots of all VMs and label them pre-setup or Day 1 beginning.

## FW-01
<img width="860" height="203" alt="image" src="https://github.com/user-attachments/assets/d3d6034e-2bbf-4e1c-92dd-44e65b0a147d" />

### Networking
* LAN - 10.0.5.2
* Say no to IPv6, VLANS and DHCP
* WAN - 10.0.17.102
* Upstream Gateway - 10.0.17.2
* Say no to everything except for the upstream
* Notes - Make sure the vtnets are aligned with the cableing numbers (switch cables if needed). Make sure the bits are set to 24 (/24)
* At the end, we should be able to ping 8.8.8.8

## WKS-01

### Pre-Networking
* Make all privacy settings set to no/off
* Go to lusrmgr.msc and add a new local administrator user (Ben.Deyot-loc)
* Make a password and make it so it never changes, but can be changed
* Add it to Administrators in whatever location is above (location\Administrators)
<img width="300" height="278" alt="image" src="https://github.com/user-attachments/assets/32f92e03-160c-4950-b230-e6cd837c3f59" />

### Networking
* IP Address - 10.0.5.100
* Netmask - 255.255.255.0
* Gateway/DNS - 10.0.5.2 (We will be changing this later)
* Hostname - wks01-Ben
<img width="748" height="596" alt="image" src="https://github.com/user-attachments/assets/30948579-38df-4165-aec8-b0cdd7f2c515" />

### FW Wizard Time!
* Navigate to https://10.0.5.2 and use the login admin/pfsense
* hostname: fw01-ben
* Domain: ben.local
* Primary DNS Server: 8.8.8.8
* Uncheck "block RFC1981 Private Networks" (Step 4)
* Change the password to something you'll remember
* Done!
<img width="760" height="162" alt="image" src="https://github.com/user-attachments/assets/eb37325b-593a-439d-8d8a-2616d718d0e8" />
<img width="758" height="170" alt="image" src="https://github.com/user-attachments/assets/12523fd8-6732-467a-a9d2-d6ef39a76c62" />

## AD-01

### Networking
* We're now working with SConfig
* Press 8 for network changes
* IP Address - 10.0.5.5
* Netmask - 255.255.255.0
* Gateway/DNS - 10.0.5.2
* Hostname - ad01-Ben
* Then you should manually update the system

### Installing AD on the Server Core
* Start with "Install-WindowsFeature AD-Domain-Services -IncludeManagmentTools"
* Then we're gonna install the forest with "Install-ADDSForest -DomainName Ben.local"
* Put in the password, go through the installation process, and reboot
* "whoami" should come up as ben\administarator

## MGMT









