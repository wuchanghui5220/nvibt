#!/bin/bash

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <path_to_public_key>"
    exit 1
fi

public_key=$1

if [ ! -f "$public_key" ]; then
    echo "Error: Public key file not found: $public_key"
    exit 1
fi

if [ ! -f "hosts.txt" ]; then
    echo "Error: hosts.txt file not found"
    exit 1
fi

copy_ssh_key() {
    local host=$1
    local user=$2
    local pass=$3

    echo "Copying SSH key to $user@$host..."
    sshpass -p "$pass" ssh-copy-id -i "$public_key" -o StrictHostKeyChecking=no "$user@$host"

    if [ $? -eq 0 ]; then
        echo "Successfully copied SSH key to $user@$host"
    else
        echo "Failed to copy SSH key to $user@$host"
    fi
}

while IFS=' ' read -r host user pass
do
    copy_ssh_key "$host" "$user" "$pass"
done < hosts.txt

echo "Batch SSH key copy completed"

