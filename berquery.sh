#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status.

# Function to convert port number to QM9790 format
convert_port() {
    local port=$1
    local group=$(( (port-1)/2 + 1 ))
    local subport=$(( port % 2 == 0 ? 2 : 1 ))
    echo "${group}/${subport}"
}

# Function to query BER info
query_ber_info() {
    local device=$1
    local switch_port=$2
    local switch_lid=$3
    local device_name=$4
    local switch_name=$5

    echo -e "\n$device_name"
    mlxlink -d $device -c | grep -A10 "BER Info"

    echo -e "\n$switch_name port $switch_port (LID: $switch_lid)"
    mlxlink -d lid-$switch_lid -p $switch_port -c | grep -A10 "BER Info"
    echo
}

# Function to perform smpquery nd and extract node description
get_node_description() {
    local lid=$1
    smpquery nd $lid | sed 's/Node Description:*//; s/\.//g' | tr -d '[:space:]'
}

# Main script
if [ $# -ne 1 ]; then
    echo "Usage: $0 <mlx5_x>"
    echo "Example: $0 mlx5_0"
    exit 1
fi

device=$1

if [[ ! $device =~ ^mlx5_[0-9]+$ ]]; then
    echo "Error: Invalid device format. It should be mlx5_x where x is a number."
    exit 1
fi

# Get base LID and SM LID
ibstat_output=$(ibstat $device)
base_lid=$(echo "$ibstat_output" | grep "Base lid:" | awk '{print $3}')
sm_lid=$(echo "$ibstat_output" | grep "SM lid:" | awk '{print $3}')

if [ -z "$base_lid" ] || [ -z "$sm_lid" ]; then
    echo "Error: Could not retrieve base LID or SM LID for $device"
    exit 1
fi

# Get the first hop information
ibtracert_output=$(ibtracert $base_lid $sm_lid | sed -n '2p')

# Extract the port number from the second set of square brackets
switch_port=$(echo "$ibtracert_output" | grep -oP '\}\[\K\d+(?=\])')
switch_lid=$(echo "$ibtracert_output" | grep -oP 'lid \K\d+(?=-\d+)')

if [ -z "$switch_port" ] || [ -z "$switch_lid" ]; then
    echo "Error: Could not retrieve switch port or LID information"
    exit 1
fi

#echo "Original switch port: $switch_port"
#echo "Switch LID: $switch_lid"

# Convert switch port to QM9790 format
qm9790_port=$(convert_port $switch_port)
#echo "Converted QM9790 Port: $qm9790_port"

# Get node descriptions
device_name=$(get_node_description $base_lid)
switch_name=$(get_node_description $switch_lid)

# Query BER info
query_ber_info $device $qm9790_port $switch_lid "$device_name" "$switch_name"
