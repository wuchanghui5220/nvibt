#!/bin/bash

# 默认值
HCA_LIST="mlx5_0,mlx5_1"
HOST_FILE="hostfile.txt"

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
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# 将HCA_LIST转换为数组
IFS=',' read -ra HCAS <<< "$HCA_LIST"

# 读取主机文件并验证主机数量
HOSTS=($(cat "$HOST_FILE"))
HOST_COUNT=${#HOSTS[@]}

if (( HOST_COUNT % 2 != 0 )); then
    echo "Error: Number of hosts in $HOST_FILE must be even."
    exit 1
fi

# 创建日志文件夹
LOG_DIR="ib_benchmark_logs_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOG_DIR"

# 主日志文件
MAIN_LOG="$LOG_DIR/benchmark_results.log"

{
echo "InfiniBand Benchmark Results - $(date)"
echo "======================================="

# 循环遍历主机对
for (( i=0; i<HOST_COUNT; i+=2 )); do
    SRC="${HOSTS[i]}"
    DEST="${HOSTS[i+1]}"
    
    echo "Testing pair: $SRC <-> $DEST"
    
    # 循环遍历每个网卡
    for (( j=0; j<${#HCAS[@]}; j++ )); do
        HCA="${HCAS[j]}"
        PORT=1  # 假设所有网卡使用端口1
        TEST_PORT=$((18515 + j))

        echo "Testing NIC: $HCA on port $PORT with test port $TEST_PORT"

        HCA_FLAGS="-d $HCA -i $PORT"
        LTFLAGS="-a $HCA_FLAGS -F -p $TEST_PORT"
        BWFLAGS="-a $HCA_FLAGS --report_gbits -F -p $TEST_PORT"

        # 为每个测试创建单独的日志文件
        LAT_LOG="$LOG_DIR/lat_${SRC}_${DEST}_${HCA}_port${PORT}.log"
        BW_LOG="$LOG_DIR/bw_${SRC}_${DEST}_${HCA}_port${PORT}.log"

        # 运行 ib_write_lat 测试
        echo "Running latency test..."
        ssh $SRC " ib_write_lat $LTFLAGS" 2>&1 | tee "$LAT_LOG" &
        LAT_PID=$!
        sleep 1
        ssh $DEST " ib_write_lat $LTFLAGS $SRC" 2>&1 | tee -a "$LAT_LOG"
        wait $LAT_PID

        # 运行 ib_write_bw 测试
        echo "Running bandwidth test..."
        ssh $SRC " ib_write_bw $BWFLAGS" 2>&1 | tee "$BW_LOG" &
        BW_PID=$!
        sleep 1
        ssh $DEST " ib_write_bw $BWFLAGS $SRC" 2>&1 | tee -a "$BW_LOG"
        wait $BW_PID

        echo "Finished testing $HCA between $SRC and $DEST"
        echo "Latency results saved to: $LAT_LOG"
        echo "Bandwidth results saved to: $BW_LOG"
        echo "------------------------"

        # 给进程一些时间来完成和清理
        sleep 5
    done
done

echo "All tests completed. Results are saved in $LOG_DIR"
} 2>&1 | tee "$MAIN_LOG"

echo "Benchmark complete. Main log file: $MAIN_LOG"
