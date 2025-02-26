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
    local device_size=$(lsblk -dn -o SIZE "/dev/$device" 2>/dev/null | tr -d ' ')
    
    write_info "Device Path" "$dev_path"
    
    if [[ $device == nvme* ]]; then
        write_info "Device Type" "NVMe SSD"
        
        local nvme_info=$(sudo nvme id-ctrl "$dev_path" -H 2>/dev/null)
        if [[ $? -eq 0 ]]; then
            local model=$(echo "$nvme_info" | grep -i "mn " | sed 's/^.*: *//' | xargs)
            local sn=$(echo "$nvme_info" | grep -i "sn " | sed 's/^.*: *//' | xargs)
            local fw_rev=$(echo "$nvme_info" | grep -i "fr " | sed 's/^.*: *//' | xargs)
            
            write_info "Model" "$model"
            write_info "Serial Number" "$sn"
            write_info "Firmware Version" "$fw_rev"
            write_info "Capacity" "$device_size"
            write_info "Status" "Normal"
        else
            local nvme_list=$(sudo nvme list | grep "$dev_path" | grep -v "^Device")
            if [[ -n "$nvme_list" ]]; then
                local model=$(echo "$nvme_list" | awk '{print $3}' | xargs)
                local sn=$(echo "$nvme_list" | awk '{print $2}' | xargs)
                local fw_rev=$(sudo nvme list -o json | grep -A15 "$device" | grep "firmware_rev" | cut -d'"' -f4)
                
                write_info "Model" "$model"
                write_info "Serial Number" "$sn"
                write_info "Firmware Version" "$fw_rev"
                write_info "Capacity" "$device_size"
                write_info "Status" "Normal"
            else
                write_info "Status" "Unknown"
                write_info "Capacity" "$device_size"
            fi
        fi
    else
        local smart_info=$(sudo smartctl -i "$dev_path" 2>/dev/null)
        if [[ $? -eq 0 ]]; then
            local device_type=""
            local vendor=""
            local product=""
            local revision=""
            local serial=""
            
            while IFS= read -r line; do
                case "$line" in
                    *"Vendor:"*)
                        vendor=$(echo "$line" | sed 's/^.*: *//')
                        ;;
                    *"Product:"*)
                        product=$(echo "$line" | sed 's/^.*: *//')
                        ;;
                    *"Model Family:"*)
                        vendor=$(echo "$line" | sed 's/^.*: *//')
                        ;;
                    *"Device Model:"*)
                        product=$(echo "$line" | sed 's/^.*: *//')
                        ;;
                    *"Revision:"*)
                        revision=$(echo "$line" | sed 's/^.*: *//')
                        ;;
                    *"Firmware Version:"*)
                        revision=$(echo "$line" | sed 's/^.*: *//')
                        ;;
                    *"Serial number:"*|*"Serial Number:"*)
                        serial=$(echo "$line" | sed 's/^.*: *//')
                        ;;
                    *"Rotation Rate:"*)
                        local rotation=$(echo "$line" | sed 's/^.*: *//')
                        if [[ "$rotation" == "Solid State Device" ]]; then
                            device_type="SSD"
                        else
                            device_type="HDD (${rotation})"
                        fi
                        ;;
                esac
            done <<< "$smart_info"
            
            [[ -z "$device_type" ]] && device_type=$(lsblk -d -o NAME,ROTA | grep "$device" | awk '{print ($2 == "0" ? "SSD" : "HDD")}')
            
            write_info "Device Type" "$device_type"
            [[ -n "$vendor" ]] && write_info "Vendor" "$vendor"
            [[ -n "$product" ]] && write_info "Model" "$product"
            [[ -n "$revision" ]] && write_info "Firmware Version" "$revision"
            [[ -n "$serial" ]] && write_info "Serial Number" "$serial"
            write_info "Capacity" "$device_size"
        else
            # Fallback if smartctl doesn't work
            local device_type=$(lsblk -d -o NAME,ROTA | grep "$device" | awk '{print ($2 == "0" ? "SSD" : "HDD")}')
            write_info "Device Type" "$device_type"
            write_info "Capacity" "$device_size"
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

# Network Interface Information
write_section "Network Interface Information"
while read -r line; do
    if [[ $line =~ Ethernet ]]; then
        pci_addr=$(echo "$line" | cut -d' ' -f1)
        nic_info=$(echo "$line" | sed 's/^[^ ]* //')
        write_info "PCI Address" "$pci_addr"
        write_info "Controller" "$nic_info"
        
        # Get Part Number and Serial Number
        while IFS= read -r detail; do
            if [[ $detail =~ "Part number" ]]; then
                write_info "Part Number" "$(echo "$detail" | sed -n 's/.*Part number\: *//p' | xargs)"
            elif [[ $detail =~ "Serial number" ]]; then
                write_info "Serial Number" "$(echo "$detail" | sed -n 's/.*Serial number\: *//p' | xargs)"
            fi
        done < <(lspci -s "$pci_addr" -vvxx | grep -E -i "serial number:|part number")
        echo "----------------------------------------" >> "$output_file"
    fi
done < <(lspci | grep -i Ethernet)

# Mellanox Information
write_section "Mellanox Information"
while read -r line; do
    if [[ $line =~ Mellanox ]]; then
        pci_addr=$(echo "$line" | cut -d' ' -f1)
        nic_info=$(echo "$line" | sed 's/^[^ ]* //')
        write_info "PCI Address" "$pci_addr"
        write_info "Controller" "$nic_info"
        
        # Get Part Number and Serial Number
        while IFS= read -r detail; do
            if [[ $detail =~ "PN" ]]; then
                write_info "Part Number" "$(echo "$detail" | sed 's/.*\[PN\]//' | xargs)"
            elif [[ $detail =~ "SN" ]]; then
                write_info "Serial Number" "$(echo "$detail" | sed 's/.*\[SN\]//' | xargs)"
            fi
        done < <(lspci -xxxvvv -s "$pci_addr" | grep -E 'PN|SN')
        echo "----------------------------------------" >> "$output_file"
    fi
done < <(lspci | grep Mellanox)

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
