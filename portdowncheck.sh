#!/bin/bash

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
iblinkinfo --switches-only > iblinkinfo_switches_only_sj.$(date +%m%d.%H%M).txt

# Read spine switch GUIDs into an array
mapfile -t spine_guids < sj_spine.txt

# Read leaf switch GUIDs into an array
mapfile -t leaf40_guids < sj_leaf40.txt
mapfile -t leaf47_48_guids < sj_leaf47-48.txt

# Process the input
current_guid=""
while IFS= read -r line; do
    if [[ $line =~ ^Switch:[[:space:]]*(0x[0-9a-f]+)[[:space:]]+(.*):$ ]]; then
        current_guid="${BASH_REMATCH[1]}"
        switch_name="${BASH_REMATCH[2]}"
    elif [[ $line =~ ^[[:space:]]+[0-9]+[[:space:]]+([0-9]+)\[.*\][[:space:]]+==\([[:space:]]*Down/ ]]; then
        port="${BASH_REMATCH[1]}"
        # Check if it's a spine switch and if the port is <= 48
        if [[ " ${spine_guids[@]} " =~ " ${current_guid} " ]]; then
            if [ "$port" -gt 48 ]; then
                continue
            fi
        # Check if it's a specific leaf switch and if the port is <= 38
        elif [[ " ${leaf40_guids[@]} " =~ " ${current_guid} " ]]; then
            if [ "$port" -gt 38 ]; then
                continue
            fi
        # Check if it's a specific leaf switch and if the port is <= 60
        elif [[ " ${leaf47_48_guids[@]} " =~ " ${current_guid} " ]]; then
            if [ "$port" -gt 60 ]; then
                continue
            fi
        fi
        new_port=$(convert_port "$port")
        if [ "$new_port" != "Skipped" ] && [ "$new_port" != "Invalid port number" ]; then
            echo "$current_guid,$port,$switch_name,$new_port"
        fi
    fi
done < iblinkinfo_switches_only_sj.$(date +%m%d.%H%M).txt > ibswitch_port_down_check_sj.$(date +%m%d.%H%M).txt
