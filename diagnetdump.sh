#!/bin/bash

# Set output directory
OUTPUT_DIR="${1:-$PWD}"
mkdir -p "$OUTPUT_DIR"
CABLE_TEMP_THRESHOLD=${2:-71}  # 使用第一个参数作为电缆温度阈值，默认为 71
NIC_TEMP_THRESHOLD=${3:-69}    # 使用第二个参数作为 NIC 温度阈值，默认为 69

# 设置输入和输出文件路径
input_file="$PWD/ibdiagnet2.net_dump_ext"
temp_file1="ibdiagnet2_temp1.csv"
temp_file2="ibdiagnet2_temp2.csv"
output_file="net_dump_ext_processed.csv"

# Function to display usage
usage() {
    echo "Usage: $0 [output_directory]"
    echo "  If output_directory is not provided, the current directory will be used."
    exit 1
}

# Function for logging
log() {
    echo ""
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$OUTPUT_DIR/script.log"
}

# Check if running as root
if [ "$(id -u)" != "0" ]; then
   log "This script must be run as root" 1>&2
   exit 1
fi


echo "Starting script. Output directory: $OUTPUT_DIR"

# Silence GNU Parallel citation notice
export PARALLEL_HOME=${PARALLEL_HOME:-"$HOME/.parallel"}
mkdir -p "$PARALLEL_HOME"
touch "$PARALLEL_HOME/will-cite"

# Function to get register values
get_reg() {
    local dev=$1
    local reg=$2
    local idx=${3:+--indexes "$3"}
    mlxreg_ext -d "$dev" --reg_name "$reg" --get $idx 2>/dev/null
}

# Function to decode multifield values from register
mstr_dec() {
    local f=$1
    local r=$2
    echo "$r" | awk -v f="$f" '$0 ~ f {gsub(/\[|\]/," "); print}' | sort -k2n | awk '{printf $NF}' | tr -d '\0' | xxd -r -p | tr -d '\0'
}

# Function to get hostname from GUID
get_hostname() {
    local guid=$1
    local lid=$(iblinkinfo -S "$guid" | tail -1 | awk '{print $1}')
    
    if [ -z "$lid" ]; then
        log "Error: Could not find LID for GUID $guid"
        return 1
    fi

    local dev="lid-$lid"

    # Get node description (switch hostname)
    local nd=$(mstr_dec "node_description" "$(get_reg "$dev" SPZR "swid=0x0")")
    
    # Remove trailing null bytes and spaces
    nd=$(echo -n "$nd" | tr -d '\0' | sed 's/[[:space:]]*$//')

    if [[ -z "$nd" ]]; then
        iblinkinfo -G "$guid" | head -1 | awk '{print $2"_"$NF}' | sed 's/://'
    else
        echo "$nd"
    fi
}

# Function to process a single line of cable info
process_cable_info() {
    local line="$1"
    local portguid=$(echo "$line" | cut -d',' -f1)
    local hostname=$(get_hostname "$portguid")
    echo "$line,$hostname"
}

# Main loop
while true; do
    log "Starting new iteration"

    # Run ibdiagnet and wait for the file to be generated
    echo "Running ibdiagnet ..."
    ibdiagnet --sc --extended_speeds all -P all=1 --pm_per_lane --get_cable_info --cable_info_disconnected --phy_cable_disconnected --get_phy_info  -o "$OUTPUT_DIR" > "$OUTPUT_DIR/opt.log" 2>&1
    
    INPUT_FILE="$OUTPUT_DIR/ibdiagnet2.db_csv"
    timeout=60
    while [ ! -f "$INPUT_FILE" ] && [ $timeout -gt 0 ]; do
        sleep 5
        ((timeout-=5))
    done

    if [ ! -f "$INPUT_FILE" ]; then
        log "Error: Input file not found. Retrying in 10 minutes."
        sleep 600
        continue
    fi

    if [ ! -s "$INPUT_FILE" ]; then
        log "Error: Input file is empty. Retrying in 10 minutes."
        sleep 600
        continue
    fi

    #log "Processing cable info"
    # Process cable info
    awk '
    BEGIN { 
        FS=OFS="," 
        start = 0
        header_processed = 0
        port_guid_col = -1
        port_num_col = -1
        temp_col = -1
    }
    /START_CABLE_INFO/ { 
        start = 1
        next 
    }
    /END_CABLE_INFO/ { 
        exit 
    }
    start && !header_processed { 
        for (i=1; i<=NF; i++) {
            if ($i == "PortGuid") port_guid_col = i
            if ($i == "PortNum") port_num_col = i
            if ($i == "Temperature") temp_col = i
        }
        if (port_guid_col != -1 && port_num_col != -1 && temp_col != -1) {
            print "PortGuid,PortNum,Temperature"
            header_processed = 1
        }
        next
    }
    start && header_processed && $1 ~ /^0x/ {
        if (port_guid_col != -1 && port_num_col != -1 && temp_col != -1) {
            print $port_guid_col, $port_num_col, $temp_col
        }
    }
    ' "$INPUT_FILE" > "$OUTPUT_DIR/cable_info_temp.csv"
    
    #log "Cable info temp file contents:"
    #cat "$OUTPUT_DIR/cable_info_temp.csv" | tee -a "$OUTPUT_DIR/script.log"
    
    #log "Cable info temp file line count: $(wc -l < "$OUTPUT_DIR/cable_info_temp.csv")"
    
    # Filter temperatures >= 70°C (integrating filter.sh functionality)
    #log "Filtering high temperatures"
    awk -F',' -v OFS=',' -v cable_temp_thresh="$CABLE_TEMP_THRESHOLD" '
    NR==1 {print; next}  # Print header
    {
        gsub(/^"|"$/, "", $3)  # Remove quotes from Temperature field
        if ($3 >= cable_temp_thresh ) {
            for (i=1; i<=NF; i++) {
                if ($i ~ /,/) {
                    $i = "\"" $i "\""  # Requote fields containing commas
                }
            }
            print  # Print line if Temperature >= 70
        }
    }
    ' "$OUTPUT_DIR/cable_info_temp.csv" > "$OUTPUT_DIR/filtered_cable_info.csv"
    
    #log "Filtered cable info contents:"
    #cat "$OUTPUT_DIR/filtered_cable_info.csv" | tee -a "$OUTPUT_DIR/script.log"
    
    # Process filtered cable info
    #log "Processing filtered cable info"
    {
        # Print header
        head -n 1 "$OUTPUT_DIR/filtered_cable_info.csv"
        
        # Process each line (skipping header)
        tail -n +2 "$OUTPUT_DIR/filtered_cable_info.csv" | while IFS=',' read -r portguid portnum temp; do
            hostname=$(get_hostname "$portguid")
            echo "$portguid,$portnum,$temp,$hostname"
        done
    } > "$OUTPUT_DIR/enriched_cable_info.csv"
    
    #log "Enriched cable info contents:"
    #cat "$OUTPUT_DIR/enriched_cable_info.csv" | tee -a "$OUTPUT_DIR/script.log"
    
    # Prepare final output for cable info
    #log "Preparing final cable info output"
    awk -F',' -v OFS=',' '
    NR > 1 {
        gsub(/^"|"$/, "", $3)  # Remove quotes from Temperature field
        gsub(/C$/, "", $3)     # Remove 'C' from end of Temperature
        print $2, $3, $4       # Print PortNum, Temperature, Hostname
    }
    ' "$OUTPUT_DIR/enriched_cable_info.csv" > "$OUTPUT_DIR/cable_info_output.csv"
    
    log "Final cable info output contents:"
    cat "$OUTPUT_DIR/cable_info_output.csv" | tee -a "$OUTPUT_DIR/script.log"
    
    # Process NIC temperature info
    #log "Processing NIC temperature info"
    sed -n '/START_TEMP_SENSING/,/END_TEMP_SENSING/p' "$INPUT_FILE" | grep -E -v '^START_|^N|^0xfc|^END_' > "$OUTPUT_DIR/nic_temp_sensing.csv"
    
    #log "NIC temp sensing file contents:"
    #cat "$OUTPUT_DIR/nic_temp_sensing.csv" | tee -a "$OUTPUT_DIR/script.log"

    # Filter NIC temperatures >= 68°C and get hostnames
    log "Filtering and processing NIC temperatures"
    while IFS=',' read -r guid temperature; do
        if (( $(echo "$temperature >= $NIC_TEMP_THRESHOLD" | bc -l) )); then
            hostname=$(get_hostname "$guid")
            if [ ! -z "$hostname" ]; then
                echo "$temperature,$hostname"
            else
                log "Warning: Could not get hostname for GUID $guid"
            fi
        fi
    done < "$OUTPUT_DIR/nic_temp_sensing.csv" > "$OUTPUT_DIR/nic_info_output.csv"

    log "NIC info output contents:"
    cat "$OUTPUT_DIR/nic_info_output.csv" | tee -a "$OUTPUT_DIR/script.log"

    # Generate timestamp
    timestamp=$(date "+%Y-%m-%d-%H-%M-%S")
    
    # Copy results to remote server
    #log "Copying results to remote server"
    scp "$OUTPUT_DIR/cable_info_output.csv" 10.13.154.1:/shell/output/trans/sj/${timestamp}
    scp "$OUTPUT_DIR/nic_info_output.csv" 10.13.154.1:/shell/output/nic/sj/${timestamp}
    
    # Clean up temporary files
    #log "Cleaning up temporary files"
    #rm -f "$OUTPUT_DIR/cable_info_temp.csv" "$OUTPUT_DIR/filtered_cable_info.csv" "$OUTPUT_DIR/enriched_cable_info.csv"
    
    #log "Iteration complete. Waiting for 5 minutes before next iteration."

    # 处理ibdiagnet2.net_dump_ext
    # 检查输入文件是否存在
    if [ ! -f "$input_file" ]; then
        echo "Error: Input file not found: $input_file"
        exit 1
    fi
    
    # 1. 删除前14行，将冒号替换为逗号，删除逗号两侧的空格
    tail -n +15 "$input_file" | sed 's/:/ , /g' | sed 's/[[:space:]]*,[[:space:]]*/,/g' > "$temp_file1"
    
    # 2. 找到 "Symbol Err" 和 "Conn LID(#)" 列的索引
    header=$(head -n 1 "$temp_file1")
    IFS=',' read -ra ADDR <<< "$header"
    symbol_err_index=-1
    conn_lid_index=-1
    
    #echo "Found columns:"
    for i in "${!ADDR[@]}"; do
        #echo "$i: ${ADDR[$i]}"
        if [[ "${ADDR[$i]}" == *"Symbol Err"* ]]; then
            symbol_err_index=$i
        elif [[ "${ADDR[$i]}" == *"Conn LID"* ]]; then
            conn_lid_index=$i
        fi
    done
    
    #echo "Symbol Err index: $symbol_err_index"
    #echo "Conn LID index: $conn_lid_index"
    
    if [ $symbol_err_index -eq -1 ] || [ $conn_lid_index -eq -1 ]; then
        echo "Error: Required columns not found"
        exit 1
    fi
    
    # 3. 筛选 "Symbol Err" 列非零且非空的行
    awk -F',' -v col=$((symbol_err_index+1)) 'NR==1 || ($col != "" && $col != "0" && $col != " 0")' "$temp_file1" > "$temp_file2"
    
    # 4. 添加新列 "Conn host"
    #echo "Processing and adding Conn host column..."
    {
        head -n 1 "$temp_file2" | sed 's/$/,Conn host/'
        tail -n +2 "$temp_file2" | while IFS=',' read -ra line; do
            # 提取 LID 值（括号前的数字）
            lid=$(echo "${line[$conn_lid_index]}" | awk '{print $1}')
            conn_host=$(smpquery nd "$lid" | sed 's/\.//g' | awk -F':' '{print $2}')
            # 使用原始的 IFS 来正确输出 CSV
            (IFS=','; echo "${line[*]},$conn_host")
        done
    } > "$output_file"
    
    ber_file="ber_human_read.csv"
    awk -F',' '{print $2","$3","$18","$19}' $output_file >$ber_file
    log  "Processing complete. Final High BER Info file saved to $ber_file "
#    cat $ber_file
    log "Iteration complete. Waiting for 5 minutes before next iteration."
    # 清理临时文件
    rm "$temp_file1" "$temp_file2"
    
    # Wait before next iteration
    sleep 300
done

