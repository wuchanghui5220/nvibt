#!/bin/bash

sysdate=$(date +%m%d.%H%M)
# Function to convert port number to the new format
convert_port() {
    local port=$1
    if [ $port -eq 65 ]; then
        echo "Skipped"
    elif [ $port -le 64 ]; then
        local group=$((($port-1)/2 + 1))
        local subport=$(($port % 2 == 0 ? 2 : 1))
        echo "$group/$subport"
    else
        echo "Invalid port number"
    fi
}

# Generate iblinkinfo output
iblinkinfo --switches-only > iblinkinfo_switches_only_cs.$sysdate.txt


# Read spine switch GUIDs into an array
mapfile -t spine_guids < cs_core.txt

# Read leaf switch GUIDs into an array
mapfile -t leaf_guids < cs_leaf.txt

# Process the input
current_guid=""
while IFS= read -r line; do
    if [[ $line =~ ^Switch:[[:space:]]*(0x[0-9a-f]+)[[:space:]]+(.*):$ ]]; then
        current_guid="${BASH_REMATCH[1]}"
        switch_name="${BASH_REMATCH[2]}"
    elif [[ $line =~ ^[[:space:]]+[0-9]+[[:space:]]+([0-9]+)\[.*\][[:space:]]+==\([[:space:]]*Down/ ]]; then
        port="${BASH_REMATCH[1]}"
        # Check if it's a spine switch and if the port is <= 40
        if [[ " ${spine_guids[@]} " =~ " ${current_guid} " ]]; then
            if [ "$port" -gt 40 ]; then
                continue
            fi
        # Check if it's a specific leaf switch and if the port is <= 34
        elif [[ " ${leaf_guids[@]} " =~ " ${current_guid} " ]]; then
            if [ "$port" -gt 34 ]; then
                continue
            fi
        fi
        new_port=$(convert_port "$port")
        if [ "$new_port" != "Skipped" ] && [ "$new_port" != "Invalid port number" ]; then
            echo "$current_guid,$port,$switch_name,$new_port"
        fi
    fi
done < iblinkinfo_switches_only_cs.$sysdate.txt > ibswitch_port_down_check_cs.$sysdate.txt



