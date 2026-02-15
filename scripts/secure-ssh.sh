#!/bin/bash
# secure-ssh.sh
# Ben Deyot - SYS-265
# This script creates a user with SSH key-only authentication

# Check if username parameter is provided
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
echo "Next: Copy public key to /home/$USERNAME/.ssh/authorized_keys"
