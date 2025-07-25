#!/bin/bash
# 脚本名称: ibperf.sh
# 描述: 使用sshpass进行InfiniBand网络性能测试，无需密钥认证，并提供路径查询功能

# 默认参数
HCA_LIST="mlx5_0,mlx5_1"
HOST_FILE="hostfile.txt"
USER="root"
PASSWORD="123456"
LAT_SIZE="2"  # 默认延迟测试大小为2字节
BW_SIZE="4194304"  # 默认带宽测试大小为4MB
ITERATIONS=5000
OUTPUT_FORMAT="human"  # 可选: human, csv, json
TEST_TYPE="all"  # 可选: latency, bandwidth, all
CROSS_HCA_TEST=false   # 默认不启用交叉测试
ROUTE_QUERY=true       # 默认启用路径查询
BW_THREADS=1          # 默认带宽测试线程数为1
BIDIRECTIONAL=false   # 默认不启用双向带宽测试

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
    echo "  --bw_size SIZE            带宽测试的消息大小，以字节为单位 (默认: 4194304)"
    echo "  --iterations N            每次测试的迭代次数 (默认: 5000)"
    echo "  --output FORMAT           输出格式: human, csv, json, all (默认: human)"
    echo "  --test_type TYPE          测试类型: latency, bandwidth, all (默认: all)"
    echo "  --cross_hca               启用交叉HCA测试 (默认: 不启用)"
    echo "  --no_route_query          禁用路径查询功能 (默认: 启用)"
    echo "  --bw_threads N            带宽测试的线程数/队列数 (默认: 1)"
    echo "  --bidirectional           启用双向带宽测试 (默认: 不启用)"
    echo "  --help                    显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 --bw_threads 2         使用2个线程进行带宽测试"
    echo "  $0 --bw_threads 4 --test_type bandwidth  只进行4线程带宽测试"
    echo "  $0 --bidirectional        启用双向带宽测试"
    echo "  $0 --bw_threads 2 --bidirectional        使用2线程进行双向带宽测试"
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
        --cross_hca)
            CROSS_HCA_TEST=true
            shift
            ;;
        --no_route_query)
            ROUTE_QUERY=false
            shift
            ;;
        --bw_threads)
            BW_THREADS="$2"
            # 验证线程数是否为正整数
            if ! [[ "$BW_THREADS" =~ ^[1-9][0-9]*$ ]]; then
                echo -e "${RED}错误:${NC} 带宽测试线程数必须是正整数"
                exit 1
            fi
            shift 2
            ;;
        --bidirectional)
            BIDIRECTIONAL=true
            shift
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

# 读取主机文件并过滤掉注释行
HOSTS=()
while IFS= read -r line; do
    # 跳过空行和注释行
    if [[ -n "$line" && ! "$line" =~ ^[[:space:]]*# ]]; then
        HOSTS+=("$line")
    fi
done < "$HOST_FILE"

HOST_COUNT=${#HOSTS[@]}

if [ $HOST_COUNT -lt 2 ]; then
    echo -e "${RED}错误:${NC} 主机文件必须至少包含两个主机（去除注释行后）"
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
ROUTE_LOG="$LOG_DIR/route_summary.log"

# 初始化CSV和JSON文件
if [[ "$TEST_TYPE" == "latency" || "$TEST_TYPE" == "all" ]]; then
    if [[ "$OUTPUT_FORMAT" == "csv" || "$OUTPUT_FORMAT" == "all" ]]; then
        echo "源主机,目标主机,源HCA,目标HCA,消息大小(B),最小延迟(us),最大延迟(us),平均延迟(us),标准差" > "$LAT_CSV"
    fi

    if [[ "$OUTPUT_FORMAT" == "json" || "$OUTPUT_FORMAT" == "all" ]]; then
        echo "{\"tests\": [" > "$LAT_JSON"
    fi
fi

if [[ "$TEST_TYPE" == "bandwidth" || "$TEST_TYPE" == "all" ]]; then
    if [[ "$OUTPUT_FORMAT" == "csv" || "$OUTPUT_FORMAT" == "all" ]]; then
        echo "源主机,目标主机,源HCA,目标HCA,线程数,双向模式,消息大小(B),BW峰值(Gbps),BW平均值(Gbps),消息率(Mpps)" > "$BW_CSV"
    fi

    if [[ "$OUTPUT_FORMAT" == "json" || "$OUTPUT_FORMAT" == "all" ]]; then
        echo "{\"tests\": [" > "$BW_JSON"
    fi
fi

# 存储测试结果的数组
declare -a LAT_RESULTS
declare -a BW_RESULTS
declare -a ROUTE_RESULTS

# 初始化摘要文件
{
    echo "╔════════════════════════════════════════════════════════════════════════╗"
    echo "║                    InfiniBand 性能测试结果摘要                         ║"
    echo "║                      $(date +"%Y-%m-%d %H:%M:%S")                               ║"
    echo "╚════════════════════════════════════════════════════════════════════════╝"
    echo ""
} > "$SUMMARY_TXT"

# 测试SSH连接
test_ssh_connection() {
    local host="$1"
    if ! ssh_cmd "$host" "echo 'SSH test successful'" &>/dev/null; then
        echo -e "${RED}错误:${NC} 无法通过SSH连接到 $host"
        return 1
    fi
    # 检查ib工具是否可用
    if ! ssh_cmd "$host" "command -v ib_send_lat" &>/dev/null; then
        echo -e "${RED}错误:${NC} 在 $host 上找不到 ib_send_lat，请确保安装了perftest或rdma-core包"
        return 1
    fi
    return 0
}

# 路径查询函数
query_route() {
    local src="$1"
    local dest="$2"
    local src_hca="$3"
    local dest_hca="$4"
    local test_log="$5"    # 测试日志文件，可能包含LID信息
    local route_log_file="$6"

    echo -e "${BLUE}[路径查询]${NC} 查询路径 ${src}:${src_hca} -> ${dest}:${dest_hca}"

    # 首先检查是否可以使用ibtracert
    if ! ssh_cmd "$src" "command -v ibtracert" &>/dev/null; then
        echo -e "${YELLOW}警告:${NC} 在 $src 上找不到 ibtracert 命令，跳过路径查询"
        return 1
    fi

    # 尝试方法1：从测试日志中提取源和目标LID
    local src_lid_hex=$(grep "local address:" "$test_log" 2>/dev/null | awk '{print $4}')
    local dest_lid_hex=$(grep "remote address:" "$test_log" 2>/dev/null | awk '{print $4}')

    # 如果从日志中提取失败，尝试方法2：直接使用ibaddr命令获取LID
    if [[ -z "$src_lid_hex" || -z "$dest_lid_hex" ]]; then
        echo -e "${YELLOW}[信息]${NC} 无法从测试日志中提取LID信息，尝试使用ibaddr命令获取"

        # 获取源和目标主机的LID（十六进制格式）
        src_lid_hex=$(ssh_cmd "$src" "ibaddr -L $src_hca | awk '{print \$3}'" 2>/dev/null)
        dest_lid_hex=$(ssh_cmd "$dest" "ibaddr -L $dest_hca | awk '{print \$3}'" 2>/dev/null)

        # 确保获取到的LID是十六进制格式（如果不是，添加0x前缀）
        if [[ -n "$src_lid_hex" && ! "$src_lid_hex" == 0x* ]]; then
            src_lid_hex="0x$src_lid_hex"
        fi

        if [[ -n "$dest_lid_hex" && ! "$dest_lid_hex" == 0x* ]]; then
            dest_lid_hex="0x$dest_lid_hex"
        fi
    fi

    # 再次检查是否成功获取了LID
    if [[ -z "$src_lid_hex" || -z "$dest_lid_hex" ]]; then
        echo -e "${YELLOW}警告:${NC} 无法获取LID信息，跳过路径查询"
        return 1
    fi

    # 构建完整的命令字符串
    local cmd_str="ibtracert ${src_lid_hex} ${dest_lid_hex}"

    # 执行命令并将结果保存到临时文件
    local trace_output=$(ssh_cmd "$src" "$cmd_str" 2>&1)
    local cmd_status=$?

    # 将命令输出保存到日志文件
    echo "命令: $cmd_str" > "$route_log_file"
    echo "$trace_output" >> "$route_log_file"

    # 检查命令是否成功
    if [ $cmd_status -ne 0 ]; then
        echo -e "${RED}错误:${NC} 执行ibtracert命令失败，查看详细错误:"
        echo "$trace_output"
        return 1
    fi

    # 使用awk处理ibtracert的输出
    local route_output=$(echo "$trace_output" | awk '
    # 跳过 To ca 行，只处理 From ca 和跳转信息
    /^From ca/ {
        if (match($0, /lid ([0-9]+-[0-9]+) "([^"]+)"/, arr)) {
            src_lid = substr(arr[1], 1, index(arr[1], "-") - 1);
            src_name = arr[2];
        }
    }

    # 收集所有路径跳转行
    /^\[[0-9]+\] ->/ {
        hops[hop_count++] = $0;
    }

    END {
        # 提取第一个端口
        if (hop_count > 0 && match(hops[0], /^\[([0-9]+)\]/, port)) {
            result = src_lid " " src_name " [" port[1] "]";
        } else {
            result = "无法解析路径";
            exit;
        }

        # 处理所有中间跳
        for (i = 0; i < hop_count; i++) {
            # 最后一跳特殊处理
            if (i == hop_count - 1 && hops[i] ~ /-> ca port/) {
                if (match(hops[i], /^\[([0-9]+)\] -> ca port [^{]*{[^}]*}\[([0-9]+)\] lid ([0-9]+-[0-9]+) "([^"]+)"/, last)) {
                    last_out_port = last[1];
                    last_in_port = last[2];
                    last_lid = substr(last[3], 1, index(last[3], "-") - 1);
                    last_name = last[4];

                    result = result " [" last_out_port "]->[" last_in_port "] " last_lid " " last_name;
                }
            }
            # 处理中间跳
            else if (match(hops[i], /-> [^ ]+ port [^{]*{[^}]*}\[([0-9]+)\] lid ([0-9]+-[0-9]+) "([^"]+)"/, hop)) {
                out_port = hop[1];
                next_lid = substr(hop[2], 1, index(hop[2], "-") - 1);
                next_name = hop[3];

                result = result " -> [" out_port "] " next_lid " " next_name;

                # 如果下一跳不是最后一跳，添加入端口
                if (i < hop_count - 1 && !(hops[i+1] ~ /-> ca port/)) {
                    if (match(hops[i+1], /^\[([0-9]+)\]/, next_in)) {
                        result = result " [" next_in[1] "]";
                    }
                }
            }
        }

        # 移除所有引号
        gsub(/"/, "", result);

        print result;
    }')

    # 记录解析结果到日志文件
    echo "解析后的路径: $route_output" >> "$route_log_file"

    # 添加到路径结果数组
    if [ -n "$route_output" ]; then
        ROUTE_RESULTS+=("$src|$dest|$src_hca|$dest_hca|$route_output")
    else
        echo -e "${YELLOW}警告:${NC} 解析ibtracert输出失败，无法获取路径信息"
        ROUTE_RESULTS+=("$src|$dest|$src_hca|$dest_hca|路径解析失败")
    fi

    # 返回路径查询输出
    echo "$route_output"
    return 0
}

# 运行延迟测试
run_latency_test() {
    local src="$1"
    local dest="$2"
    local src_hca="$3"
    local dest_hca="$4"
    local port="$5"
    local size="$6"
    local test_port="$7"
    local log_file="$8"
    local json_first="$9"

    # 设置测试参数
    local src_hca_flags="-d $src_hca -i $port"
    local dest_hca_flags="-d $dest_hca -i $port"

    echo -e "${BLUE}[测试]${NC} 运行延迟测试 (${src}:${src_hca} -> ${dest}:${dest_hca}, 消息大小: $size 字节, 端口: $test_port)"

    # 在服务器端启动测试
    ssh_cmd "$src" "ib_send_lat $src_hca_flags -s $size -n $ITERATIONS -F -p $test_port" > "$log_file" 2>&1 &
    local server_pid=$!

    # 给服务器一些时间来启动
    sleep 2

    # 在客户端启动测试
    ssh_cmd "$dest" "ib_send_lat $dest_hca_flags -s $size -n $ITERATIONS -F -p $test_port $src" >> "$log_file" 2>&1

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
            echo -e "${GREEN}[结果]${NC} 延迟测试 (${src}:${src_hca} -> ${dest}:${dest_hca}):"
            echo "---------------------------------------------------------------------------------------"
            echo "#bytes     #iterations    t_min[usec]      t_max[usec]    t_avg[usec]      t_stdev[usec]"
            printf "%-10s %-15s %-16s %-15s %-16s %-15s\n" "$size" "$ITERATIONS" "$min_lat" "$max_lat" "$avg_lat" "$stdev"
            echo "---------------------------------------------------------------------------------------"

            # 添加到延迟结果数组
            LAT_RESULTS+=("$src|$dest|$src_hca|$dest_hca|$size|$min_lat|$max_lat|$avg_lat|$stdev")

            # 添加到CSV摘要
            if [[ "$OUTPUT_FORMAT" == "csv" || "$OUTPUT_FORMAT" == "all" ]]; then
                echo "$src,$dest,$src_hca,$dest_hca,$size,$min_lat,$max_lat,$avg_lat,$stdev" >> "$LAT_CSV"
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
        "source_hca": "$src_hca",
        "destination_hca": "$dest_hca",
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
    local src_hca="$3"
    local dest_hca="$4"
    local port="$5"
    local size="$6"
    local test_port="$7"
    local log_file="$8"
    local json_first="$9"
    local threads="${10:-1}"  # 第10个参数是线程数，默认为1
    local bidirectional="${11:-false}"  # 第11个参数是是否双向测试，默认为false

    # 设置测试参数
    local src_hca_flags="-d $src_hca -i $port"
    local dest_hca_flags="-d $dest_hca -i $port"

    # 添加线程/队列参数
    if [ "$threads" -gt 1 ]; then
        src_hca_flags="$src_hca_flags -q $threads"
        dest_hca_flags="$dest_hca_flags -q $threads"
    fi

    # 添加双向测试参数
    if [ "$bidirectional" == "true" ]; then
        src_hca_flags="$src_hca_flags -b"
        dest_hca_flags="$dest_hca_flags -b"
    fi

    local test_mode_desc="单向"
    if [ "$bidirectional" == "true" ]; then
        test_mode_desc="双向"
    fi

    echo -e "${BLUE}[测试]${NC} 运行${test_mode_desc}带宽测试 (${src}:${src_hca} -> ${dest}:${dest_hca}, 消息大小: $size 字节, 端口: $test_port, 线程数: $threads)"

    # 在服务器端启动测试
    ssh_cmd "$src" "ib_write_bw $src_hca_flags -s $size -n $ITERATIONS --report_gbits -F -p $test_port" > "$log_file" 2>&1 &
    local server_pid=$!

    # 给服务器一些时间来启动
    sleep 2

    # 在客户端启动测试
    ssh_cmd "$dest" "ib_write_bw $dest_hca_flags -s $size -n $ITERATIONS --report_gbits -F -p $test_port $src" >> "$log_file" 2>&1

    # 等待服务器进程完成
    wait $server_pid

    # 解析带宽测试结果 - 直接在日志文件中搜索数据行
    if [ -f "$log_file" ]; then
        # 使用精确的搜索找到带宽结果行
        local result_line=$(cat "$log_file" | grep -A2 "#bytes.*BW peak" | grep -E "^[[:space:]]*$size" | tail -1)

        if [ -n "$result_line" ]; then
            # 使用awk提取需要的字段
            local bw_peak=$(echo "$result_line" | awk '{print $3}')
            local bw_avg=$(echo "$result_line" | awk '{print $4}')
            local msg_rate=$(echo "$result_line" | awk '{print $5}')

            # 输出带宽测试结果表格
            echo -e "${GREEN}[结果]${NC} ${test_mode_desc}带宽测试 (${src}:${src_hca} -> ${dest}:${dest_hca}, 线程数: $threads):"
            echo "---------------------------------------------------------------------------------------"
            echo "#bytes     #iterations    BW peak[Gb/sec]    BW average[Gb/sec]   MsgRate[Mpps]"
            echo "$result_line"
            echo "---------------------------------------------------------------------------------------"

            # 如果启用了路径查询，则执行路径查询
            if [ "$ROUTE_QUERY" == "true" ]; then
                local route_log_file="$LOG_DIR/route_${src}_${dest}_${src_hca}_${dest_hca}_bw_t${threads}_$([ "$bidirectional" == "true" ] && echo "bidir" || echo "unidir").log"
                local route_result=$(query_route "$src" "$dest" "$src_hca" "$dest_hca" "$log_file" "$route_log_file")

                if [ -n "$route_result" ]; then
                    echo -e "${GREEN}[路径]${NC} $route_result"
                    echo "---------------------------------------------------------------------------------------"
                fi
            fi

            # 计算MB大小进行显示
            local size_mb=$(echo "scale=2; $size/1048576" | bc)

            # 添加到带宽结果数组（包含线程数和双向信息）
            BW_RESULTS+=("$src|$dest|$src_hca|$dest_hca|$threads|$test_mode_desc|$size_mb|$bw_peak|$bw_avg|$msg_rate")

            # 添加到CSV摘要
            if [[ "$OUTPUT_FORMAT" == "csv" || "$OUTPUT_FORMAT" == "all" ]]; then
                echo "$src,$dest,$src_hca,$dest_hca,$threads,$test_mode_desc,$size,$bw_peak,$bw_avg,$msg_rate" >> "$BW_CSV"
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
        "source_hca": "$src_hca",
        "destination_hca": "$dest_hca",
        "threads": $threads,
        "bidirectional": $([ "$bidirectional" == "true" ] && echo "true" || echo "false"),
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
            local any_num_line=$(cat "$log_file" | grep -A10 "#bytes.*BW peak" | grep -E "^[[:space:]]*[0-9]+" | tail -1)

            if [ -n "$any_num_line" ]; then
                # 解析这个行
                local bw_peak=$(echo "$any_num_line" | awk '{print $3}')
                local bw_avg=$(echo "$any_num_line" | awk '{print $4}')
                local msg_rate=$(echo "$any_num_line" | awk '{print $5}')

                echo -e "${GREEN}[结果]${NC} ${test_mode_desc}带宽测试 (${src}:${src_hca} -> ${dest}:${dest_hca}, 线程数: $threads):"
                echo "---------------------------------------------------------------------------------------"
                echo "#bytes     #iterations    BW peak[Gb/sec]    BW average[Gb/sec]   MsgRate[Mpps]"
                echo "$any_num_line"
                echo "---------------------------------------------------------------------------------------"

                # 如果启用了路径查询，则执行路径查询
                if [ "$ROUTE_QUERY" == "true" ]; then
                    local route_log_file="$LOG_DIR/route_${src}_${dest}_${src_hca}_${dest_hca}_bw_t${threads}_$([ "$bidirectional" == "true" ] && echo "bidir" || echo "unidir").log"
                    local route_result=$(query_route "$src" "$dest" "$src_hca" "$dest_hca" "$log_file" "$route_log_file")

                    if [ -n "$route_result" ]; then
                        echo -e "${GREEN}[路径]${NC} $route_result"
                        echo "---------------------------------------------------------------------------------------"
                    fi
                fi

                # 计算MB大小
                local size_mb=$(echo "scale=2; $size/1048576" | bc)

                # 添加到带宽结果数组
                BW_RESULTS+=("$src|$dest|$src_hca|$dest_hca|$threads|$test_mode_desc|$size_mb|$bw_peak|$bw_avg|$msg_rate")

                # 添加到CSV摘要
                if [[ "$OUTPUT_FORMAT" == "csv" || "$OUTPUT_FORMAT" == "all" ]]; then
                    echo "$src,$dest,$src_hca,$dest_hca,$threads,$test_mode_desc,$size,$bw_peak,$bw_avg,$msg_rate" >> "$BW_CSV"
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
        "source_hca": "$src_hca",
        "destination_hca": "$dest_hca",
        "threads": $threads,
        "bidirectional": $([ "$bidirectional" == "true" ] && echo "true" || echo "false"),
        "message_size": $size,
        "bw_peak_gbps": $bw_peak,
        "bw_avg_gbps": $bw_avg,
        "message_rate_mpps": $msg_rate
    }
EOF
                fi

                return 0
            else
                # 实在找不到任何结果，将错误写入日志
                echo "无法从带宽测试日志中提取结果: $log_file" >> "$MAIN_LOG"
                return 1
            fi
        fi
    else
        echo -e "${RED}[错误]${NC} 日志文件 $log_file 不存在"
        return 1
    fi
}

# 生成摘要报告
generate_summary() {
    # 打印延迟测试结果表格
    if [[ "$TEST_TYPE" == "latency" || "$TEST_TYPE" == "all" ]] && [ ${#LAT_RESULTS[@]} -gt 0 ]; then
        {
            echo "┌───────────────────────────────────── 延迟测试结果 ──────────────────────────────────────────┐"
            echo "│ 源主机        目标主机       源HCA  目标HCA  大小(B)  最小(us)  最大(us)  平均(us)   标准差 │"
            echo "├─────────────────────────────────────────────────────────────────────────────────────────────┤"

            for result in "${LAT_RESULTS[@]}"; do
                IFS='|' read -r src dest src_hca dest_hca size min_lat max_lat avg_lat stdev <<< "$result"
                printf "│ %-13s %-13s %-7s %-7s %8s %9.2f %9.2f %9.2f %8.2f │\n" \
                    "$src" "$dest" "$src_hca" "$dest_hca" "$size" "$min_lat" "$max_lat" "$avg_lat" "$stdev"
            done

            echo "└─────────────────────────────────────────────────────────────────────────────────────────────┘"
        } >> "$SUMMARY_TXT"
    fi

    # 打印带宽测试结果表格（更新以包含线程数和双向模式）
    if [[ "$TEST_TYPE" == "bandwidth" || "$TEST_TYPE" == "all" ]] && [ ${#BW_RESULTS[@]} -gt 0 ]; then
        {
            echo ""
            echo "┌──────────────────────────────────── 带宽测试结果 ────────────────────────────────────────────┐"
            echo "│ 源主机        目标主机       源HCA  目标HCA  线程 模式   大小(MB) 峰值(Gbps) 平均(Gbps) 消息率(Mpps)│"
            echo "├─────────────────────────────────────────────────────────────────────────────────────────────┤"

            for result in "${BW_RESULTS[@]}"; do
                IFS='|' read -r src dest src_hca dest_hca threads mode size_mb bw_peak bw_avg msg_rate <<< "$result"
                printf "│ %-13s %-13s %-7s %-7s %4s %-5s %8s %10.2f %10.2f %12s │\n" \
                    "$src" "$dest" "$src_hca" "$dest_hca" "$threads" "$mode" "$size_mb" "$bw_peak" "$bw_avg" "$msg_rate"
            done

            echo "└─────────────────────────────────────────────────────────────────────────────────────────────┘"
        } >> "$SUMMARY_TXT"
    fi

    # 打印路径查询结果表格（如果启用）
    if [ "$ROUTE_QUERY" == "true" ] && [ ${#ROUTE_RESULTS[@]} -gt 0 ]; then
        {
            echo ""
            echo "┌───────────────────────────────────── 路径查询结果 ──────────────────────────────────────────┐"
            echo "│ 源主机        目标主机       源HCA  目标HCA  路径                                           │"
            echo "├─────────────────────────────────────────────────────────────────────────────────────────────┤"

            for result in "${ROUTE_RESULTS[@]}"; do
                IFS='|' read -r src dest src_hca dest_hca route_path <<< "$result"
                # 将路径截断以适应固定宽度表格
                local max_path_len=70
                local path_display="$route_path"
                if [ ${#route_path} -gt $max_path_len ]; then
                    path_display="${route_path:0:$max_path_len-3}..."
                fi
                printf "│ %-13s %-13s %-7s %-7s %-71s │\n" \
                    "$src" "$dest" "$src_hca" "$dest_hca" "$path_display"
            done

            echo "└─────────────────────────────────────────────────────────────────────────────────────────────┘"
        } >> "$SUMMARY_TXT"
    fi

    # 添加测试完成时间
    echo "" >> "$SUMMARY_TXT"
    echo "测试完成时间: $(date +"%Y-%m-%d %H:%M:%S")" >> "$SUMMARY_TXT"
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
        echo "  交叉HCA测试: $([ "$CROSS_HCA_TEST" == "true" ] && echo "启用" || echo "不启用")"
        echo "  路径查询: $([ "$ROUTE_QUERY" == "true" ] && echo "启用" || echo "不启用")"
        echo "  带宽测试线程数: $BW_THREADS"
        echo "  双向带宽测试: $([ "$BIDIRECTIONAL" == "true" ] && echo "启用" || echo "不启用")"
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

            # 设置基本端口
            BASE_PORT=18515
            PORT=1  # 假设所有网卡使用端口1

            # 交叉HCA测试
            if [ "$CROSS_HCA_TEST" == "true" ]; then
                # 对于每个源HCA
                for SRC_HCA in "${HCAS[@]}"; do
                    # 对于每个目标HCA
                    for DEST_HCA in "${HCAS[@]}"; do
                        echo -e "\n${BOLD}[HCA交叉测试]${NC} 测试 $SRC:$SRC_HCA -> $DEST:$DEST_HCA"

                        # 延迟测试 - 只使用指定的大小
                        if [[ "$TEST_TYPE" == "latency" || "$TEST_TYPE" == "all" ]]; then
                            # 为每个HCA对使用不同的端口以避免冲突
                            LAT_TEST_PORT=$((BASE_PORT + 10))

                            LAT_LOG="$LOG_DIR/lat_${SRC}_${DEST}_${SRC_HCA}_${DEST_HCA}_size${LAT_SIZE}.log"
                            run_latency_test "$SRC" "$DEST" "$SRC_HCA" "$DEST_HCA" "$PORT" "$LAT_SIZE" "$LAT_TEST_PORT" "$LAT_LOG" "$lat_json_first"
                            if [ "$lat_json_first" == "true" ]; then
                                lat_json_first=false
                            fi

                            # 给进程一些时间来完成和清理
                            sleep 3
                        fi

                        # 带宽测试 - 只使用指定的大小和线程数
                        if [[ "$TEST_TYPE" == "bandwidth" || "$TEST_TYPE" == "all" ]]; then
                            # 为带宽测试使用不同的端口
                            BW_TEST_PORT=$((BASE_PORT + 20))

                            local bw_suffix=""
                            if [ "$BIDIRECTIONAL" == "true" ]; then
                                bw_suffix="_bidir"
                            fi

                            BW_LOG="$LOG_DIR/bw_${SRC}_${DEST}_${SRC_HCA}_${DEST_HCA}_size${BW_SIZE}_t${BW_THREADS}${bw_suffix}.log"
                            run_bandwidth_test "$SRC" "$DEST" "$SRC_HCA" "$DEST_HCA" "$PORT" "$BW_SIZE" "$BW_TEST_PORT" "$BW_LOG" "$bw_json_first" "$BW_THREADS" "$BIDIRECTIONAL"
                            if [ "$bw_json_first" == "true" ]; then
                                bw_json_first=false
                            fi

                            # 给进程一些时间来完成和清理
                            sleep 3
                        fi
                    done
                done
            else
                # 原始的非交叉测试模式 - 每个主机上相同的HCA相互测试
                for HCA in "${HCAS[@]}"; do
                    echo -e "\n${BOLD}[HCA]${NC} 测试 $HCA 网卡 (端口 $PORT)"

                    # 延迟测试 - 只使用指定的大小
                    if [[ "$TEST_TYPE" == "latency" || "$TEST_TYPE" == "all" ]]; then
                        # 为每个HCA使用不同的端口以避免冲突
                        LAT_TEST_PORT=$((BASE_PORT + 10))

                        LAT_LOG="$LOG_DIR/lat_${SRC}_${DEST}_${HCA}_size${LAT_SIZE}.log"
                        run_latency_test "$SRC" "$DEST" "$HCA" "$HCA" "$PORT" "$LAT_SIZE" "$LAT_TEST_PORT" "$LAT_LOG" "$lat_json_first"
                        if [ "$lat_json_first" == "true" ]; then
                            lat_json_first=false
                        fi

                        # 给进程一些时间来完成和清理
                        sleep 3
                    fi

                    # 带宽测试 - 只使用指定的大小和线程数
                    if [[ "$TEST_TYPE" == "bandwidth" || "$TEST_TYPE" == "all" ]]; then
                        # 为带宽测试使用不同的端口
                        BW_TEST_PORT=$((BASE_PORT + 20))

                        local bw_suffix=""
                        if [ "$BIDIRECTIONAL" == "true" ]; then
                            bw_suffix="_bidir"
                        fi

                        BW_LOG="$LOG_DIR/bw_${SRC}_${DEST}_${HCA}_size${BW_SIZE}_t${BW_THREADS}${bw_suffix}.log"
                        run_bandwidth_test "$SRC" "$DEST" "$HCA" "$HCA" "$PORT" "$BW_SIZE" "$BW_TEST_PORT" "$BW_LOG" "$bw_json_first" "$BW_THREADS" "$BIDIRECTIONAL"
                        if [ "$bw_json_first" == "true" ]; then
                            bw_json_first=false
                        fi

                        # 给进程一些时间来完成和清理
                        sleep 3
                    fi

                    echo -e "${BLUE}[完成]${NC} $HCA 测试完成"
                done
            fi
        done

        # 生成摘要报告
        generate_summary

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

        if [ "$ROUTE_QUERY" == "true" ]; then
            echo -e "${BOLD}路径查询日志:${NC} $ROUTE_LOG"
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
