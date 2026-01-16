# LAB 01 - Setting up labs

## Summary
In this lab, at the beginning of the year, we always setup or lab environments, which is what I'm going to document right now. I know how to do almost everything now, so it's mostly going to be the specs. I will document some of the steps in detail if I need to. In this lab, we set up our FW, AD, WKS, and MGMT. MGMT is a new one for us, so I'll go over that one later, a little more in detail. The setup includes Networking and DNS, and basic account handling. 

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
