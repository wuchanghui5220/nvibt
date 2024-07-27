#!/bin/bash

#lids=$(ibswitches |awk -F'lid' '{print }' |awk '{print }') 
# Function to display usage
usage() {
    echo "Usage: $0 -d <device>"
    echo "  <device> should be in the format 'lid-XX' (e.g., lid-39)"
    exit 1
}

# Check if running as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Parse command line options
while getopts "d:" opt; do
    case $opt in
        d) dev=$OPTARG ;;
        *) usage ;;
    esac
done

# Check if device is provided and in correct format
if [ -z "$dev" ] || [[ ! $dev =~ ^lid-[0-9]+$ ]]; then
    usage
fi

# Function to get register values
get_reg() {
    local reg=$1
    local idx=${2:+--indexes "$2"}
    mlxreg_ext -d "$dev" --reg_name "$reg" --get $idx 2>/dev/null
}

# Function to decode multifield values from register
mstr_dec() {
    local f=$1
    local r=$2
    echo "$r" | awk -v f="$f" '$0 ~ f {gsub(/\[|\]/," "); print}' | sort -k2n | awk '{printf $NF}' | tr -d '\0' | xxd -r -p | tr -d '\0'
}

# Get node description (switch hostname)
nd=$(mstr_dec "node_description" "$(get_reg SPZR "swid=0x0")")

# Get serial number
sn=$(mstr_dec "serial_number" "$(get_reg MSGI)")

# Get GUID
guid=$(get_reg SPZR "swid=0x0" | awk '/node_guid/ {gsub(/0x/,"",$NF); g=g$NF} END {print "0x"g}')

# Remove trailing null bytes and spaces
nd=$(echo -n "$nd" | tr -d '\0' | sed 's/[[:space:]]*$//')
sn=$(echo -n "$sn" | tr -d '\0' | sed 's/[[:space:]]*$//')
guid=$(echo -n "$guid" | tr -d '\0' | sed 's/[[:space:]]*$//')

# Output serial number, GUID and node description in one line
echo "$sn $guid $nd"
