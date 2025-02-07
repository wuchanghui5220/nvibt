#!/bin/bash

# Function to check and install required tools
check_and_install_tool() {
    local tool=$1
    local package=$2
    if ! command -v "$tool" &> /dev/null; then
        echo "[$tool] not installed, installing..."
        if command -v apt &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y "$package"
        elif command -v yum &> /dev/null; then
            sudo yum install -y "$package"
        else
            echo "ERROR: Cannot automatically install $tool, please install manually"
            return 1
        fi
    fi
    return 0
}

# Check required tools
required_tools=(
    "dmidecode:dmidecode"
    "smartctl:smartmontools"
    "nvme:nvme-cli"
    "lsblk:util-linux"
)

for tool in "${required_tools[@]}"; do
    IFS=':' read -r cmd pkg <<< "$tool"
    check_and_install_tool "$cmd" "$pkg" || exit 1
done

# Get current timestamp and system serial number
current_time=$(date +"%Y%m%d_%H%M%S")
serial_number=$(dmidecode -t system | grep "Serial Number" | awk -F': ' '{print $2}' | tr -d ' ')
output_file="${serial_number}_${current_time}.txt"

# Function to write section header
write_section() {
    local section_name=$1
    echo -e "\n============== $section_name ==============" >> "$output_file"
}

# Function to write key-value pair
write_info() {
    local key=$1
    local value=$2
    printf "%-20s: %s\n" "$key" "$value" >> "$output_file"
}

# System Information
write_section "System Information"
while IFS=':' read -r key value; do
    [[ -n $value ]] && write_info "$(echo $key | xargs)" "$(echo $value | xargs)"
done < <(dmidecode -t system | grep -E "Manufacturer|Serial Number|Product Name")

# CPU Information
write_section "CPU Information"
while IFS=':' read -r key value; do
    [[ -n $value ]] && write_info "$(echo $key | xargs)" "$(echo $value | xargs)"
done < <(lscpu | grep -E "Model name|Socket|^CPU\(s\):")

# Memory Information
write_section "Memory Information"
temp_file=$(mktemp)
sudo dmidecode -t memory > "$temp_file"

# Get total slots
total_slots=$(grep "Number Of Devices:" "$temp_file" | head -n 1 | awk '{print $4}')
write_info "Total Slots" "$total_slots"

# Process memory information
declare -A memory_info
used_slots=0
current_device=""

while IFS= read -r line; do
    if [[ $line == *"Memory Device"* ]]; then
        current_device="true"
        size=""
        type=""
        speed=""
        manufacturer=""
        part_number=""
    elif [[ $current_device == "true" ]]; then
        case "$line" in
            *"Size:"*)
                size=$(echo "$line" | awk '{print $2 " " $3}')
                ;;
            *"Type:"*)
                type=$(echo "$line" | sed 's/^[[:space:]]*Type: //')
                ;;
            *"Speed:"*)
                speed=$(echo "$line" | sed 's/^[[:space:]]*Speed: //')
                ;;
            *"Manufacturer:"*)
                manufacturer=$(echo "$line" | sed 's/^[[:space:]]*Manufacturer: //')
                ;;
            *"Part Number:"*)
                part_number=$(echo "$line" | sed 's/^[[:space:]]*Part Number: //' | sed 's/[[:space:]]*$//')
                
                if [[ $size != "No Module" && $size != "Not Installed" && \
                      $size != "0 B" && $size != "0 MB" && $size != "0 GB" ]]; then
                    # Standardize to GB
                    if [[ $size == *"MB"* ]]; then
                        size_num=$(echo $size | awk '{print $1}')
                        size="$(awk "BEGIN {printf \"%.1f\", $size_num/1024}") GB"
                    fi
                    
                    mem_key="${size}|${type}|${speed}|${manufacturer}|${part_number}"
                    if [[ -n ${memory_info["$mem_key"]} ]]; then
                        memory_info["$mem_key"]=$((memory_info["$mem_key"] + 1))
                    else
                        memory_info["$mem_key"]=1
                    fi
                    ((used_slots++))
                fi
                current_device=""
                ;;
        esac
    fi
done < "$temp_file"
rm -f "$temp_file"

write_info "Used Slots" "$used_slots"
write_info "Total Memory" "$(free -h | grep "Mem:" | awk '{print $2}')"

# Write memory details
for info in "${!memory_info[@]}"; do
    IFS='|' read -r size type speed manufacturer part_number <<< "$info"
    write_info "Memory Module" "Count: ${memory_info[$info]}"
    write_info "Size" "$size"
    write_info "Type" "$type"
    write_info "Speed" "$speed"
    write_info "Manufacturer" "$manufacturer"
    write_info "Part Number" "$part_number"
    echo "----------------------------------------" >> "$output_file"
done

# Storage Information
write_section "Storage Information"

get_device_info() {
    local device=$1
    local dev_path="/dev/$device"
    
    write_info "Device Path" "$dev_path"
    
    if [[ $device == nvme* ]]; then
        write_info "Device Type" "NVMe SSD"
        
        local nvme_list=$(sudo nvme list | grep -v "^----" | grep "$dev_path")
        if [[ -n "$nvme_list" ]]; then
            local model=$(echo "$nvme_list" | awk '{print $3}' | xargs)
            local sn=$(echo "$nvme_list" | awk '{print $2}' | xargs)
            local fw_rev=$(echo "$nvme_list" | awk '{print $NF}' | xargs)
            local capacity=$(echo "$nvme_list" | awk '{print $8, $9}')
            
            write_info "Model" "$model"
            write_info "Serial Number" "$sn"
            write_info "Firmware Version" "$fw_rev"
            write_info "Capacity" "$capacity"
            write_info "Status" "Normal"
        else
            write_info "Status" "Unknown"
        fi
    else
        local smart_info=$(sudo smartctl -i "$dev_path" 2>/dev/null)
        if [[ $? -eq 0 ]]; then
            while IFS= read -r line; do
                case "$line" in
                    *"Vendor:"*)
                        write_info "Vendor" "$(echo "$line" | sed 's/^.*: *//')"
                        ;;
                    *"Product:"*)
                        write_info "Product" "$(echo "$line" | sed 's/^.*: *//')"
                        ;;
                    *"Revision:"*)
                        write_info "Revision" "$(echo "$line" | sed 's/^.*: *//')"
                        ;;
                    *"User Capacity:"*)
                        local size=$(echo "$line" | grep -o "[0-9,]* bytes" | sed 's/,//g' | awk '{printf "%.2f GB", $1 / (1024*1024*1024)}')
                        write_info "Capacity" "$size"
                        ;;
                    *"Rotation Rate:"*)
                        local type=$(echo "$line" | sed 's/^.*: *//')
                        if [[ "$type" == "Solid State Device" ]]; then
                            write_info "Device Type" "SSD"
                        else
                            write_info "Device Type" "HDD (${type})"
                        fi
                        ;;
                    *"Serial number:"*)
                        write_info "Serial Number" "$(echo "$line" | sed 's/^.*: *//')"
                        ;;
                esac
            done <<< "$smart_info"
        fi
    fi
    echo "----------------------------------------" >> "$output_file"
}

# Process all block devices
lsblk -d -o NAME,SIZE,TYPE | grep -v "loop" | grep -v "ram" | while read -r line; do
    [[ $line =~ NAME ]] && continue
    device=$(echo "$line" | awk '{print $1}')
    get_device_info "$device"
done

# Mellanox Information
write_section "Mellanox Information"
for dev in $(lspci | grep Mellanox | cut -d' ' -f1); do
    while IFS= read -r line; do
        [[ $line =~ (PN|SN) ]] && write_info "$dev" "$(echo "$line" | sed 's/^[[:space:]]*//' | sed 's/ *$//')"
    done < <(lspci -xxxvvv -s "$dev" | grep -E 'PN|SN')
done

# GPU Information
write_section "GPU Information"
if command -v nvidia-smi &> /dev/null; then
    while IFS= read -r line; do
        key=$(echo "$line" | cut -d: -f1 | xargs)
        value=$(echo "$line" | cut -d: -f2- | xargs)
        write_info "$key" "$value"
    done < <(nvidia-smi -q | grep -E -i "Product Name|Serial Number")
else
    write_info "GPU Status" "NVIDIA GPU not found or nvidia-smi not installed"
fi

echo "Information has been saved to $output_file"