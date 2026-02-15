#!/bin/bash
# secure-ssh.sh
# Ben Deyot - SYS-265
# Creates a user with SSH key-only authentication
# Usage: ./secure-ssh.sh <username> <path-to-public-key>

# Check if parameters are provided
if [ -z "$1" ]; then
    echo "Usage: ./secure-ssh.sh <username>"
    exit 1
fi

USERNAME=$1
PUBKEY_PATH="$HOME/Sys-265/linux/web01/id_rsa.pub"

# Check if public key exists
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
