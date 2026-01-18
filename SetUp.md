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

## MGMT-01

### Networking
* Open SConfig from CLI as Admin to make changes
* IP Address - 10.0.5.10
* Gateway - 10.0.5.2
* Subnet - 255.255.255.0
* DNS(NEW) - 10.0.5.5
* Hostname - mgmt01-Ben
* Join the domain (either on SConfig or Server Manager)

<img width="654" height="692" alt="image" src="https://github.com/user-attachments/assets/bb70d982-0d78-4190-839e-38a9b2928e62" />

### Installation/Management
* After reeboot relogin as the domain, not local
* Go to Manage -> Add Roles and Features and install the following
<img width="300" height="364" alt="image" src="https://github.com/user-attachments/assets/908f61c9-cfeb-44c0-80a8-626f8eba2a31" />

* Now we go to Manage -> Add servers and ad our AD01 server
<img width="1492" height="608" alt="image" src="https://github.com/user-attachments/assets/2c4f8e52-c9bd-4782-8c5f-702c306cd39a" />

* Now we are creating two users (Ben Deyot(ben.deyot) and Benjamin Deyot(ben.deyot-adm))
* Add ben.deyot-adm to the "Domain Admin" Group
<img width="958" height="170" alt="image" src="https://github.com/user-attachments/assets/d55e0b7b-07f7-472e-943c-917b6078881f" />

* Now we have to do the reverse and forward lookup zones
* This is what your PTR reverse lookup should look like
<img width="920" height="364" alt="image" src="https://github.com/user-attachments/assets/eeac6ccf-0d99-4d58-8e74-aa5374322845" />

* Now, after all that, you can log out and log back in through the -adm account.

## Joining WKS to Domain
* We have to make a change to the DNS of the WKS settings to join it. We are going to change it to the one MGMT has now.
* NEW DNS - 10.0.5.5
* Now go to settings -> System -> About and then change the domain to ben.local
* Restart and WKS should be joined to the domain

## Lecture/Lab 
### DNS
* I feel as if I would like to learn more about the full capabilities of DNS and how it can be used in the work environment. I just have a feeling I'm not fully aware of all the advantages and capabilities of DNS. I feel as though researching DNS would be beneficial for me in the future

### AD PowerShell
* I would want to explore more with this new environment, as we're not used to having no GUI for us to use, but I find it more interesting relying on commands and how to navigate a computer more logically than just searching it up. This could also lead to more usage of a usage for one liners and how to be more efficient in labs.

### Management VM
* I feel like this will obviously be explained more in the future, but I want to know what the usage of this is more for. I know it's for the separation of power and not to have one VM have more than the other, but I feel as though, for now, it's getting in the way more than helping. I feel like I have to go through management and then get access to the AD, but then again, that is more secure. I would just like to know if it gets more practical.

## Conclusion
### Opionons 
* I feel as if this was a good opener for the semester, and I have more of a handle on what we are going to be working with. Obviously, I stated my take on the MGMT server earlier, but I feel like it will come more into play later on in the year, and I will see the usage a lot more. I really liked the no-GUI AD server as it helped me with how I handle commands and be more efficient. This lab also really made me more curious about DNS, as the deliverables opened up some thoughts on what I really do with this other than connections? What doors does DNS really open up for me?

### Final
* We now have the FW, WKS, AD, and MGMT up and running and ready to go for the semester. They have access to each other and can all talk through DNS. The pings going out are going through the LAN, then the WAN Gateway, and then to Cyber.local, so we are secure and ready to go.







