#!/bin/bash
# 脚本名称: ibperf.sh
# 描述: 使用sshpass进行InfiniBand网络性能测试，无需密钥认证

# 默认参数
HCA_LIST="mlx5_0,mlx5_1"
HOST_FILE="hostfile.txt"
USER="root"
PASSWORD="123456"
LAT_SIZE="2"  # 默认延迟测试大小为2字节
BW_SIZE="2097152"  # 默认带宽测试大小为2MB
ITERATIONS=5000
OUTPUT_FORMAT="human"  # 可选: human, csv, json
TEST_TYPE="all"  # 可选: latency, bandwidth, all

# 终端颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# 帮助函数
show_help() {
    echo -e "${BOLD}用法:${NC} $0 [选项]"
    echo "选项:"
    echo "  --hca_list HCA1,HCA2,...  指定要测试的HCA设备列表 (默认: mlx5_0,mlx5_1)"
    echo "  --host_file FILE          包含主机名的文件 (默认: hostfile.txt)"
    echo "  --user USER               SSH用户名 (默认: root)"
    echo "  --password PASSWORD       SSH密码 (默认: 123456)"
    echo "  --lat_size SIZE           延迟测试的消息大小，以字节为单位 (默认: 2)"
    echo "  --bw_size SIZE            带宽测试的消息大小，以字节为单位 (默认: 2097152)"
    echo "  --iterations N            每次测试的迭代次数 (默认: 5000)"
    echo "  --output FORMAT           输出格式: human, csv, json, all (默认: human)"
    echo "  --test_type TYPE          测试类型: latency, bandwidth, all (默认: all)"
    echo "  --help                    显示此帮助信息"
    exit 0
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --hca_list)
            HCA_LIST="$2"
            shift 2
            ;;
        --host_file)
            HOST_FILE="$2"
            shift 2
            ;;
        --user)
            USER="$2"
            shift 2
            ;;
        --password)
            PASSWORD="$2"
            shift 2
            ;;
        --lat_size)
            LAT_SIZE="$2"
            shift 2
            ;;
        --bw_size)
            BW_SIZE="$2"
            shift 2
            ;;
        --iterations)
            ITERATIONS="$2"
            shift 2
            ;;
        --output)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        --test_type)
            TEST_TYPE="$2"
            shift 2
            ;;
        --help)
            show_help
            ;;
        *)
            echo -e "${RED}错误:${NC} 未知选项 $1"
            show_help
            ;;
    esac
done

# 检查是否安装了sshpass
if ! command -v sshpass &> /dev/null; then
    echo -e "${RED}错误:${NC} sshpass 未安装。请先安装它。"
    echo "在 Debian/Ubuntu 上: sudo apt-get install sshpass"
    echo "在 RHEL/CentOS 上: sudo yum install sshpass"
    exit 1
fi

# 检查主机文件是否存在
if [ ! -f "$HOST_FILE" ]; then
    echo -e "${RED}错误:${NC} 主机文件 $HOST_FILE 不存在"
    exit 1
fi

# SSH命令包装函数
ssh_cmd() {
    local host="$1"
    local cmd="$2"
    sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$USER@$host" "$cmd"
}

# 将HCA_LIST转换为数组
IFS=',' read -ra HCAS <<< "$HCA_LIST"

# 读取主机文件并验证主机数量
HOSTS=($(cat "$HOST_FILE"))
HOST_COUNT=${#HOSTS[@]}

if [ $HOST_COUNT -lt 2 ]; then
    echo -e "${RED}错误:${NC} 主机文件必须至少包含两个主机"
    exit 1
fi

if (( HOST_COUNT % 2 != 0 )); then
    echo -e "${YELLOW}警告:${NC} 主机数量为奇数。最后一个主机将不会被测试。"
    HOST_COUNT=$((HOST_COUNT - 1))
fi

# 创建唯一的时间戳标识符
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="ib_test_${TIMESTAMP}"
mkdir -p "$LOG_DIR"

# 创建主日志文件和摘要文件
MAIN_LOG="$LOG_DIR/summary_results.log"
SUMMARY_TXT="$LOG_DIR/results_summary.txt"
LAT_CSV="$LOG_DIR/latency_summary.csv"
BW_CSV="$LOG_DIR/bandwidth_summary.csv"
LAT_JSON="$LOG_DIR/latency_summary.json"
BW_JSON="$LOG_DIR/bandwidth_summary.json"

# 初始化CSV和JSON文件
if [[ "$TEST_TYPE" == "latency" || "$TEST_TYPE" == "all" ]]; then
    if [[ "$OUTPUT_FORMAT" == "csv" || "$OUTPUT_FORMAT" == "all" ]]; then
        echo "源主机,目标主机,HCA,消息大小(B),最小延迟(us),最大延迟(us),平均延迟(us),标准差" > "$LAT_CSV"
    fi
    
    if [[ "$OUTPUT_FORMAT" == "json" || "$OUTPUT_FORMAT" == "all" ]]; then
        echo "{\"tests\": [" > "$LAT_JSON"
    fi
fi

if [[ "$TEST_TYPE" == "bandwidth" || "$TEST_TYPE" == "all" ]]; then
    if [[ "$OUTPUT_FORMAT" == "csv" || "$OUTPUT_FORMAT" == "all" ]]; then
        echo "源主机,目标主机,HCA,消息大小(B),BW峰值(Gbps),BW平均值(Gbps),消息率(Mpps)" > "$BW_CSV"
    fi
    
    if [[ "$OUTPUT_FORMAT" == "json" || "$OUTPUT_FORMAT" == "all" ]]; then
        echo "{\"tests\": [" > "$BW_JSON"
    fi
fi

# 初始化摘要文件
{
    echo "╔══════════════════════════════════════════════════════════════════════╗"
    echo "║                    InfiniBand 性能测试结果摘要                       ║"
    echo "║                      $(date +"%Y-%m-%d %H:%M:%S")                         ║"
    echo "╚══════════════════════════════════════════════════════════════════════╝"
    echo ""
    
    if [[ "$TEST_TYPE" == "latency" || "$TEST_TYPE" == "all" ]]; then
        echo "┌─────────────────────────────────── 延迟测试结果 ───────────────────────────────────┐"
        echo "│ 源主机          目标主机        HCA     大小(B)  最小(us)  最大(us)  平均(us)  标准差  │"
        echo "├──────────────────────────────────────────────────────────────────────────────────┤"
    fi
} > "$SUMMARY_TXT"

# 测试SSH连接
test_ssh_connection() {
    local host="$1"
    if ! ssh_cmd "$host" "echo 'SSH test successful'" &>/dev/null; then
        echo -e "${RED}错误:${NC} 无法通过SSH连接到 $host"
        return 1
    fi
    # 检查ib工具是否可用
    if ! ssh_cmd "$host" "command -v ib_write_lat" &>/dev/null; then
        echo -e "${RED}错误:${NC} 在 $host 上找不到 ib_write_lat，请确保安装了perftest或rdma-core包"
        return 1
    fi
    return 0
}

# 运行延迟测试
run_latency_test() {
    local src="$1"
    local dest="$2"
    local hca="$3"
    local port="$4"
    local size="$5"
    local test_port="$6"
    local log_file="$7"
    local json_first="$8"
    
    # 设置测试参数
    local hca_flags="-d $hca -i $port"
    local lat_flags="$hca_flags -s $size -n $ITERATIONS -F -p $test_port"
    
    echo -e "${BLUE}[测试]${NC} 运行延迟测试 (消息大小: $size 字节, 端口: $test_port)"
    
    # 在服务器端启动测试
    ssh_cmd "$src" "ib_write_lat $lat_flags" > "$log_file" 2>&1 &
    local server_pid=$!
    
    # 给服务器一些时间来启动
    sleep 2
    
    # 在客户端启动测试
    ssh_cmd "$dest" "ib_write_lat $lat_flags $src" >> "$log_file" 2>&1
    
    # 等待服务器进程完成
    wait $server_pid
    
    # 解析测试结果
    if [ -f "$log_file" ]; then
        # 提取延迟结果 - 使用客户端的输出
        local client_results=$(grep -A1 "#bytes #iterations" "$log_file" | tail -1)
        
        if [ -n "$client_results" ]; then
            # 解析结果行
            local min_lat=$(echo "$client_results" | awk '{print $3}')
            local max_lat=$(echo "$client_results" | awk '{print $4}')
            local avg_lat=$(echo "$client_results" | awk '{print $6}')
            local stdev=$(echo "$client_results" | awk '{print $7}')
            
            # 格式化输出结果 - 使用与带宽测试类似的表格形式
            echo -e "${GREEN}[结果]${NC} 延迟测试 (${src} -> ${dest}, ${hca}):"
            echo "---------------------------------------------------------------------------------------"
            echo "#bytes     #iterations    t_min[usec]      t_max[usec]    t_avg[usec]      t_stdev[usec]"
            printf "%-10s %-15s %-16s %-15s %-16s %-15s\n" "$size" "$ITERATIONS" "$min_lat" "$max_lat" "$avg_lat" "$stdev"
            echo "---------------------------------------------------------------------------------------"
            
            # 添加到摘要文件
            printf "│ %-15s %-15s %-7s %8s %9.2f %9.2f %9.2f %8.2f │\n" \
                "$src" "$dest" "$hca" "$size" "$min_lat" "$max_lat" "$avg_lat" "$stdev" >> "$SUMMARY_TXT"
            
            # 添加到CSV摘要
            if [[ "$OUTPUT_FORMAT" == "csv" || "$OUTPUT_FORMAT" == "all" ]]; then
                echo "$src,$dest,$hca,$size,$min_lat,$max_lat,$avg_lat,$stdev" >> "$LAT_CSV"
            fi
            
            # 添加到JSON摘要
            if [[ "$OUTPUT_FORMAT" == "json" || "$OUTPUT_FORMAT" == "all" ]]; then
                if [ "$json_first" == "true" ]; then
                    json_first=false
                else
                    echo "," >> "$LAT_JSON"
                fi
                cat >> "$LAT_JSON" << EOF
    {
        "source": "$src",
        "destination": "$dest",
        "hca": "$hca",
        "message_size": $size,
        "min_latency": $min_lat,
        "max_latency": $max_lat,
        "avg_latency": $avg_lat,
        "stdev": $stdev
    }
EOF
            fi
            
            return 0
        else
            # 错误信息输出到日志，屏幕上不显示
            echo "无法解析延迟测试结果，请检查日志文件: $log_file" >> "$MAIN_LOG"
            return 1
        fi
    else
        echo -e "${RED}[错误]${NC} 日志文件 $log_file 不存在"
        return 1
    fi
}

# 运行带宽测试
run_bandwidth_test() {
    local src="$1"
    local dest="$2"
    local hca="$3"
    local port="$4"
    local size="$5"
    local test_port="$6"
    local log_file="$7"
    local json_first="$8"
    
    # 设置测试参数
    local hca_flags="-d $hca -i $port"
    local bw_flags="$hca_flags -s $size -n $ITERATIONS --report_gbits -F -p $test_port"
    
    echo -e "${BLUE}[测试]${NC} 运行带宽测试 (消息大小: $size 字节, 端口: $test_port)"
    
    # 在服务器端启动测试
    ssh_cmd "$src" "ib_write_bw $bw_flags" > "$log_file" 2>&1 &
    local server_pid=$!
    
    # 给服务器一些时间来启动
    sleep 2
    
    # 在客户端启动测试
    ssh_cmd "$dest" "ib_write_bw $bw_flags $src" >> "$log_file" 2>&1
    
    # 等待服务器进程完成
    wait $server_pid
    
    # 解析带宽测试结果 - 直接在日志文件中搜索数据行
    if [ -f "$log_file" ]; then
        # 使用精确的搜索找到带宽结果行 - 关键点是搜索处理过的日志
        # 首先找到包含"#bytes"和"BW peak"的行后面的数字行
        local result_line=$(cat "$log_file" | grep -A2 "#bytes.*BW peak" | grep -E "^[[:space:]]*$size")
        
        if [ -n "$result_line" ]; then
            # 使用awk提取需要的字段
            local size_col=$(echo "$result_line" | awk '{print $1}')
            local iter_col=$(echo "$result_line" | awk '{print $2}')
            local bw_peak=$(echo "$result_line" | awk '{print $3}')
            local bw_avg=$(echo "$result_line" | awk '{print $4}')
            local msg_rate=$(echo "$result_line" | awk '{print $5}')
            
            # 输出带宽测试结果表格
            echo -e "${GREEN}[结果]${NC} 带宽测试 (${src} -> ${dest}, ${hca}):"
            echo "---------------------------------------------------------------------------------------"
            echo "#bytes     #iterations    BW peak[Gb/sec]    BW average[Gb/sec]   MsgRate[Mpps]"
            echo "$result_line"
            echo "---------------------------------------------------------------------------------------"
            
            # 在摘要中添加带宽结果
            if [[ "$TEST_TYPE" == "all" ]] && [[ $(grep -c "带宽测试结果" "$SUMMARY_TXT") -eq 0 ]]; then
                echo "" >> "$SUMMARY_TXT"
                echo "┌─────────────────────────────────── 带宽测试结果 ───────────────────────────────────┐" >> "$SUMMARY_TXT"
                echo "│ 源主机          目标主机        HCA     大小(MB)  峰值(Gbps)  平均(Gbps)  消息率(Mpps) │" >> "$SUMMARY_TXT"
                echo "├──────────────────────────────────────────────────────────────────────────────────┤" >> "$SUMMARY_TXT"
            fi
            
            # 计算MB大小进行显示
            local size_mb=$(echo "scale=2; $size/1048576" | bc)
            
            # 添加到摘要文件
            printf "│ %-15s %-15s %-7s %8.2f %11.2f %11.2f %13s │\n" \
                "$src" "$dest" "$hca" "$size_mb" "$bw_peak" "$bw_avg" "$msg_rate" >> "$SUMMARY_TXT"
            
            # 添加到CSV摘要
            if [[ "$OUTPUT_FORMAT" == "csv" || "$OUTPUT_FORMAT" == "all" ]]; then
                echo "$src,$dest,$hca,$size,$bw_peak,$bw_avg,$msg_rate" >> "$BW_CSV"
            fi
            
            # 添加到JSON摘要
            if [[ "$OUTPUT_FORMAT" == "json" || "$OUTPUT_FORMAT" == "all" ]]; then
                if [ "$json_first" == "true" ]; then
                    json_first=false
                else
                    echo "," >> "$BW_JSON"
                fi
                cat >> "$BW_JSON" << EOF
    {
        "source": "$src",
        "destination": "$dest",
        "hca": "$hca",
        "message_size": $size,
        "bw_peak_gbps": $bw_peak,
        "bw_avg_gbps": $bw_avg,
        "message_rate_mpps": $msg_rate
    }
EOF
            fi
            
            return 0
        else
            # 如果找不到精确匹配，尝试使用更宽松的匹配，只获取数字行
            local any_num_line=$(cat "$log_file" | grep -A10 "#bytes.*BW peak" | grep -E "^[[:space:]]*[0-9]+" | head -1)
            
            if [ -n "$any_num_line" ]; then
                # 解析这个行
                local bw_peak=$(echo "$any_num_line" | awk '{print $3}')
                local bw_avg=$(echo "$any_num_line" | awk '{print $4}')
                local msg_rate=$(echo "$any_num_line" | awk '{print $5}')
                
                echo -e "${GREEN}[结果]${NC} 带宽测试 (${src} -> ${dest}, ${hca}):"
                echo "---------------------------------------------------------------------------------------"
                echo "#bytes     #iterations    BW peak[Gb/sec]    BW average[Gb/sec]   MsgRate[Mpps]"
                echo "$any_num_line"
                echo "---------------------------------------------------------------------------------------"
                
                # 在摘要中添加带宽结果
                if [[ "$TEST_TYPE" == "all" ]] && [[ $(grep -c "带宽测试结果" "$SUMMARY_TXT") -eq 0 ]]; then
                    echo "" >> "$SUMMARY_TXT"
                    echo "┌─────────────────────────────────── 带宽测试结果 ───────────────────────────────────┐" >> "$SUMMARY_TXT"
                    echo "│ 源主机          目标主机        HCA     大小(MB)  峰值(Gbps)  平均(Gbps)  消息率(Mpps) │" >> "$SUMMARY_TXT"
                    echo "├──────────────────────────────────────────────────────────────────────────────────┤" >> "$SUMMARY_TXT"
                fi
                
                # 计算MB大小
                local size_mb=$(echo "scale=2; $size/1048576" | bc)
                
                # 添加到摘要文件
                printf "│ %-15s %-15s %-7s %8.2f %11.2f %11.2f %13s │\n" \
                    "$src" "$dest" "$hca" "$size_mb" "$bw_peak" "$bw_avg" "$msg_rate" >> "$SUMMARY_TXT"
                
                # 添加到CSV摘要
                if [[ "$OUTPUT_FORMAT" == "csv" || "$OUTPUT_FORMAT" == "all" ]]; then
                    echo "$src,$dest,$hca,$size,$bw_peak,$bw_avg,$msg_rate" >> "$BW_CSV"
                fi
                
                # 添加到JSON摘要
                if [[ "$OUTPUT_FORMAT" == "json" || "$OUTPUT_FORMAT" == "all" ]]; then
                    if [ "$json_first" == "true" ]; then
                        json_first=false
                    else
                        echo "," >> "$BW_JSON"
                    fi
                    cat >> "$BW_JSON" << EOF
    {
        "source": "$src",
        "destination": "$dest",
        "hca": "$hca",
        "message_size": $size,
        "bw_peak_gbps": $bw_peak,
        "bw_avg_gbps": $bw_avg,
        "message_rate_mpps": $msg_rate
    }
EOF
                fi
                
                return 0
            else
                # 最后尝试，直接搜索日志中任何包含数字的行
                local last_resort=$(cat "$log_file" | grep -E "^[[:space:]]*[0-9]+" | tail -1)
                
                if [ -n "$last_resort" ]; then
                    local bw_peak=$(echo "$last_resort" | awk '{print $3}')
                    local bw_avg=$(echo "$last_resort" | awk '{print $4}')
                    local msg_rate=$(echo "$last_resort" | awk '{print $5}')
                    
                    echo -e "${GREEN}[结果]${NC} 带宽测试 (${src} -> ${dest}, ${hca}):"
                    echo "---------------------------------------------------------------------------------------"
                    echo "#bytes     #iterations    BW peak[Gb/sec]    BW average[Gb/sec]   MsgRate[Mpps]"
                    echo "$last_resort"
                    echo "---------------------------------------------------------------------------------------"
                    
                    # 在摘要中添加带宽结果
                    if [[ "$TEST_TYPE" == "all" ]] && [[ $(grep -c "带宽测试结果" "$SUMMARY_TXT") -eq 0 ]]; then
                        echo "" >> "$SUMMARY_TXT"
                        echo "┌─────────────────────────────────── 带宽测试结果 ───────────────────────────────────┐" >> "$SUMMARY_TXT"
                        echo "│ 源主机          目标主机        HCA     大小(MB)  峰值(Gbps)  平均(Gbps)  消息率(Mpps) │" >> "$SUMMARY_TXT"
                        echo "├──────────────────────────────────────────────────────────────────────────────────┤" >> "$SUMMARY_TXT"
                    fi
                    
                    # 计算MB大小
                    local size_mb=$(echo "scale=2; $size/1048576" | bc)
                    
                    # 添加到摘要文件
                    printf "│ %-15s %-15s %-7s %8.2f %11.2f %11.2f %13s │\n" \
                        "$src" "$dest" "$hca" "$size_mb" "$bw_peak" "$bw_avg" "$msg_rate" >> "$SUMMARY_TXT"
                    
                    # 添加到CSV摘要
                    if [[ "$OUTPUT_FORMAT" == "csv" || "$OUTPUT_FORMAT" == "all" ]]; then
                        echo "$src,$dest,$hca,$size,$bw_peak,$bw_avg,$msg_rate" >> "$BW_CSV"
                    fi
                    
                    # 添加到JSON摘要
                    if [[ "$OUTPUT_FORMAT" == "json" || "$OUTPUT_FORMAT" == "all" ]]; then
                        if [ "$json_first" == "true" ]; then
                            json_first=false
                        else
                            echo "," >> "$BW_JSON"
                        fi
                        cat >> "$BW_JSON" << EOF
    {
        "source": "$src",
        "destination": "$dest",
        "hca": "$hca",
        "message_size": $size,
        "bw_peak_gbps": $bw_peak,
        "bw_avg_gbps": $bw_avg,
        "message_rate_mpps": $msg_rate
    }
EOF
                    fi
                    
                    return 0
                else
                    # 实在找不到任何结果，写入日志但不显示错误
                    echo "无法从带宽测试日志中提取结果: $log_file" >> "$MAIN_LOG"
                    # 把日志内容输出到屏幕下，便于调试
                    echo "日志内容（最后20行）:"
                    tail -20 "$log_file"
                    return 1
                fi
            fi
        fi
    else
        echo -e "${RED}[错误]${NC} 日志文件 $log_file 不存在"
        return 1
    fi
}

# 主测试函数
run_tests() {
    local lat_json_first=true
    local bw_json_first=true
    
    {
        echo -e "${BOLD}InfiniBand 性能测试${NC} - $(date)"
        echo "========================================="
        echo -e "${BOLD}使用的参数:${NC}"
        echo "  HCA 设备: $HCA_LIST"
        echo "  主机文件: $HOST_FILE"
        echo "  延迟测试大小: $LAT_SIZE 字节"
        echo "  带宽测试大小: $BW_SIZE 字节 ($(echo "scale=2; $BW_SIZE/1048576" | bc) MB)"
        echo "  每次测试的迭代次数: $ITERATIONS"
        echo "  测试类型: $TEST_TYPE"
        echo "  输出格式: $OUTPUT_FORMAT"
        echo "========================================="
        
        # 循环遍历主机对
        for (( i=0; i<HOST_COUNT; i+=2 )); do
            SRC="${HOSTS[i]}"
            DEST="${HOSTS[i+1]}"
            
            echo -e "\n${BOLD}[测试对]${NC} $SRC <-> $DEST"
            
            # 测试SSH连接
            if ! test_ssh_connection "$SRC"; then
                echo -e "${YELLOW}[跳过]${NC} 主机对 $SRC <-> $DEST"
                continue
            fi
            
            if ! test_ssh_connection "$DEST"; then
                echo -e "${YELLOW}[跳过]${NC} 主机对 $SRC <-> $DEST"
                continue
            fi
            
            # 循环遍历每个HCA
            for HCA in "${HCAS[@]}"; do
                PORT=1  # 假设所有网卡使用端口1
                BASE_PORT=18515
                
                echo -e "\n${BOLD}[HCA]${NC} 测试 $HCA 网卡 (端口 $PORT)"
                
                # 延迟测试 - 只使用指定的大小
                if [[ "$TEST_TYPE" == "latency" || "$TEST_TYPE" == "all" ]]; then
                    # 为每个HCA使用不同的端口以避免冲突
                    LAT_TEST_PORT=$((BASE_PORT + 10))
                    
                    LAT_LOG="$LOG_DIR/lat_${SRC}_${DEST}_${HCA}_size${LAT_SIZE}.log"
                    run_latency_test "$SRC" "$DEST" "$HCA" "$PORT" "$LAT_SIZE" "$LAT_TEST_PORT" "$LAT_LOG" "$lat_json_first"
                    if [ "$lat_json_first" == "true" ]; then
                        lat_json_first=false
                    fi
                    
                    # 给进程一些时间来完成和清理
                    sleep 3
                fi
                
                # 带宽测试 - 只使用指定的大小
                if [[ "$TEST_TYPE" == "bandwidth" || "$TEST_TYPE" == "all" ]]; then
                    # 为带宽测试使用不同的端口
                    BW_TEST_PORT=$((BASE_PORT + 20))
                    
                    BW_LOG="$LOG_DIR/bw_${SRC}_${DEST}_${HCA}_size${BW_SIZE}.log"
                    run_bandwidth_test "$SRC" "$DEST" "$HCA" "$PORT" "$BW_SIZE" "$BW_TEST_PORT" "$BW_LOG" "$bw_json_first"
                    if [ "$bw_json_first" == "true" ]; then
                        bw_json_first=false
                    fi
                    
                    # 给进程一些时间来完成和清理
                    sleep 3
                fi
                
                echo -e "${BLUE}[完成]${NC} $HCA 测试完成"
            done
        done
        
        # 完成摘要表格
        {
            if [[ "$TEST_TYPE" == "latency" || "$TEST_TYPE" == "all" ]]; then
                echo "└──────────────────────────────────────────────────────────────────────────────────┘"
            fi
            
            if [[ "$TEST_TYPE" == "bandwidth" || "$TEST_TYPE" == "all" ]]; then
                echo "└──────────────────────────────────────────────────────────────────────────────────┘"
            fi
            
            echo ""
            echo "测试完成时间: $(date +"%Y-%m-%d %H:%M:%S")"
        } >> "$SUMMARY_TXT"
        
        echo -e "\n${GREEN}[完成]${NC} 所有测试完成。结果保存在 $LOG_DIR 目录中"
        echo -e "${BOLD}摘要报告:${NC} $SUMMARY_TXT"
        
        if [[ "$TEST_TYPE" == "latency" || "$TEST_TYPE" == "all" ]]; then
            if [[ "$OUTPUT_FORMAT" == "csv" || "$OUTPUT_FORMAT" == "all" ]]; then
                echo -e "${BOLD}延迟测试 CSV 摘要:${NC} $LAT_CSV"
            fi
            
            if [[ "$OUTPUT_FORMAT" == "json" || "$OUTPUT_FORMAT" == "all" ]]; then
                echo -e "${BOLD}延迟测试 JSON 摘要:${NC} $LAT_JSON"
            fi
        fi
        
        if [[ "$TEST_TYPE" == "bandwidth" || "$TEST_TYPE" == "all" ]]; then
            if [[ "$OUTPUT_FORMAT" == "csv" || "$OUTPUT_FORMAT" == "all" ]]; then
                echo -e "${BOLD}带宽测试 CSV 摘要:${NC} $BW_CSV"
            fi
            
            if [[ "$OUTPUT_FORMAT" == "json" || "$OUTPUT_FORMAT" == "all" ]]; then
                echo -e "${BOLD}带宽测试 JSON 摘要:${NC} $BW_JSON"
            fi
        fi
        
        # 显示摘要内容
        echo -e "\n${BOLD}结果摘要:${NC}"
        cat "$SUMMARY_TXT"
        
    } 2>&1 | tee "$MAIN_LOG"
}

# 完成JSON文件
finish_json() {
    if [[ "$TEST_TYPE" == "latency" || "$TEST_TYPE" == "all" ]]; then
        if [[ "$OUTPUT_FORMAT" == "json" || "$OUTPUT_FORMAT" == "all" ]]; then
            echo -e "\n]}" >> "$LAT_JSON"
        fi
    fi
    
    if [[ "$TEST_TYPE" == "bandwidth" || "$TEST_TYPE" == "all" ]]; then
        if [[ "$OUTPUT_FORMAT" == "json" || "$OUTPUT_FORMAT" == "all" ]]; then
            echo -e "\n]}" >> "$BW_JSON"
        fi
    fi
}

# 主执行流程
echo -e "${BOLD}开始 InfiniBand 性能测试...${NC}"
run_tests
finish_json
echo -e "${GREEN}测试完成。${NC}所有结果已保存到 ${BOLD}$LOG_DIR${NC} 目录"
