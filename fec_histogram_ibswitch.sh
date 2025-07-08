#!/bin/bash

# 优化版并发FEC直方图查询脚本
# 用法: ./fec_histogram_ibswitch.sh [并发数] [输出目录]
# 示例: ./fec_histogram_ibswitch.sh 5 ./results

# 设置默认参数
CONCURRENT_JOBS=${1:-5}
OUTPUT_DIR=${2:-"./fec_results_$(date +%Y%m%d_%H%M%S)"}

# 创建输出目录
mkdir -p "$OUTPUT_DIR"

# 获取所有在线交换机的LID
echo "正在获取所有在线交换机..."
SWITCH_LIDS=$(ibswitches | awk -F'lid' '{print $2}' | awk '{print $1}' | grep -E '^[0-9]+$')

if [ -z "$SWITCH_LIDS" ]; then
    echo "错误: 未找到任何在线交换机"
    exit 1
fi

# 将LID列表转换为数组
LIDS=($SWITCH_LIDS)
TOTAL_SWITCHES=${#LIDS[@]}

echo "发现 $TOTAL_SWITCHES 个在线交换机: ${LIDS[*]}"
echo "并发数: $CONCURRENT_JOBS"
echo "输出目录: $OUTPUT_DIR"
echo "开始时间: $(date)"
echo "=========================================="

# 进度跟踪变量
COMPLETED=0
ACTIVE_JOBS=0
declare -A JOB_LIDS

# 单个交换机查询函数
query_switch() {
    local lid=$1
    local output_dir=$2

    # 获取交换机名称
    local switch_name=$(smpquery nd $lid 2>/dev/null | sed 's/\.//g' | awk -F':' '{print $2}')

    if [ -z "$switch_name" ]; then
        echo "LID $lid: 无法获取交换机名称，跳过"
        return 1
    fi

    # 创建输出文件
    local output_file="$output_dir/switch_${lid}_${switch_name}_fec.txt"

    # 初始化计数器
    local active_ports=0
    local error_ports=0

    # 创建临时文件
    local temp_file=$(mktemp)

    # 遍历所有64个端口
    for module in {1..32}; do
        for port in {1..2}; do
            local port_name="${module}/${port}"

            # 执行mlxlink命令
            local fec_output=$(mlxlink -d lid-$lid -p $port_name --rx_fec_histogram --show_histogram 2>/dev/null)

            if [ $? -eq 0 ] && echo "$fec_output" | grep -q "Histogram of FEC Errors"; then
                active_ports=$((active_ports + 1))

                # 提取直方图数据
                local histogram_data=$(echo "$fec_output" | grep -A 11 "Histogram of FEC Errors")

                # 写入临时文件
                echo "$switch_name (LID: $lid) Port $port_name" >> "$temp_file"
                echo "$histogram_data" >> "$temp_file"
                echo "" >> "$temp_file"

                # 检查FEC错误
                local error_count=$(echo "$histogram_data" | grep -E "Bin [1-7]" | awk '{sum += $NF} END {print sum+0}')

                if [ "$error_count" -gt 0 ]; then
                    error_ports=$((error_ports + 1))
                fi
            fi

            # 小延迟
            sleep 0.02
        done
    done

    # 写入最终结果文件
    {
        echo "交换机: $switch_name (LID: $lid)"
        echo "查询时间: $(date)"
        echo "活跃端口数: $active_ports"
        echo "有FEC错误的端口数: $error_ports"
        echo "=========================================="
        echo ""
        cat "$temp_file"
        echo ""
        echo "=========================================="
        echo "查询完成时间: $(date)"
    } > "$output_file"

    # 清理临时文件
    rm -f "$temp_file"

    # 输出完成信息到指定文件描述符
    echo "COMPLETED:$lid:$switch_name:$active_ports:$error_ports" >&3

    return 0
}

# 启动后台任务的函数
start_job() {
    local lid=$1

    # 创建命名管道用于通信
    local pipe=$(mktemp -u)
    mkfifo "$pipe"

    # 启动后台任务
    {
        query_switch "$lid" "$OUTPUT_DIR" 3>&1 >&4
        echo "JOB_DONE:$lid" >&3
    } 4>&1 3>"$pipe" &

    local job_pid=$!
    JOB_LIDS[$job_pid]=$lid

    # 读取管道输出
    {
        while read line < "$pipe"; do
            echo "$line"
        done
        rm -f "$pipe"
    } &

    return $job_pid
}

# 等待任务完成
wait_for_job() {
    wait
    local job_pid=$1
    unset JOB_LIDS[$job_pid]
    ACTIVE_JOBS=$((ACTIVE_JOBS - 1))
    COMPLETED=$((COMPLETED + 1))
}

# 主循环
echo "开始并发查询..."
echo ""

# 启动初始任务
LID_INDEX=0
while [ $ACTIVE_JOBS -lt $CONCURRENT_JOBS ] && [ $LID_INDEX -lt $TOTAL_SWITCHES ]; do
    lid=${LIDS[$LID_INDEX]}
    switch_name=$(smpquery nd $lid 2>/dev/null | sed 's/\.//g' | awk -F':' '{print $2}')

    if [ -n "$switch_name" ]; then
        echo "启动查询: $switch_name (LID: $lid)"
        start_job "$lid" &
        ACTIVE_JOBS=$((ACTIVE_JOBS + 1))
    fi

    LID_INDEX=$((LID_INDEX + 1))
done

# 处理完成的任务并启动新任务
while [ $COMPLETED -lt $TOTAL_SWITCHES ]; do
    # 检查是否有任务完成
    for job_pid in "${!JOB_LIDS[@]}"; do
        if ! kill -0 $job_pid 2>/dev/null; then
            lid=${JOB_LIDS[$job_pid]}
            switch_name=$(smpquery nd $lid 2>/dev/null | sed 's/\.//g' | awk -F':' '{print $2}')
            echo "完成查询: $switch_name (LID: $lid) [进度: $((COMPLETED + 1))/$TOTAL_SWITCHES]"

            wait_for_job $job_pid

            # 如果还有未处理的交换机，启动新任务
            if [ $LID_INDEX -lt $TOTAL_SWITCHES ]; then
                new_lid=${LIDS[$LID_INDEX]}
                new_switch_name=$(smpquery nd $new_lid 2>/dev/null | sed 's/\.//g' | awk -F':' '{print $2}')

                if [ -n "$new_switch_name" ]; then
                    echo "启动查询: $new_switch_name (LID: $new_lid)"
                    start_job "$new_lid" &
                    ACTIVE_JOBS=$((ACTIVE_JOBS + 1))
                fi

                LID_INDEX=$((LID_INDEX + 1))
            fi

            break
        fi
    done

    sleep 1
done

# 等待所有任务完成
wait

echo ""
echo "=========================================="
echo "所有查询完成！"
echo "总交换机数: $TOTAL_SWITCHES"
echo "结果保存在: $OUTPUT_DIR"
echo "完成时间: $(date)"

# 生成汇总报告
SUMMARY_FILE="$OUTPUT_DIR/summary_report.txt"
{
    echo "FEC直方图查询汇总报告"
    echo "查询时间: $(date)"
    echo "总交换机数: $TOTAL_SWITCHES"
    echo "并发数: $CONCURRENT_JOBS"
    echo "=========================================="
    echo ""

    local total_active_ports=0
    local total_error_ports=0
    local switches_with_errors=0

    for lid in "${LIDS[@]}"; do
        output_file=$(find "$OUTPUT_DIR" -name "switch_${lid}_*_fec.txt" | head -1)
        if [ -f "$output_file" ]; then
            switch_name=$(basename "$output_file" | sed 's/switch_[0-9]*_//; s/_fec.txt//')
            active_ports=$(grep "活跃端口数:" "$output_file" | awk '{print $2}')
            error_ports=$(grep "有FEC错误的端口数:" "$output_file" | awk '{print $2}')

            total_active_ports=$((total_active_ports + active_ports))
            total_error_ports=$((total_error_ports + error_ports))

            if [ "$error_ports" -gt 0 ]; then
                switches_with_errors=$((switches_with_errors + 1))
                echo "⚠️  交换机: $switch_name (LID: $lid) - 活跃端口: $active_ports, 错误端口: $error_ports"
            else
                echo "✅ 交换机: $switch_name (LID: $lid) - 活跃端口: $active_ports, 错误端口: $error_ports"
            fi
        else
            echo "❌ 交换机: LID $lid - 查询失败"
        fi
    done

    echo ""
    echo "=========================================="
    echo "统计汇总:"
    echo "总活跃端口数: $total_active_ports"
    echo "总错误端口数: $total_error_ports"
    echo "有错误的交换机数: $switches_with_errors"
    echo "=========================================="

} > "$SUMMARY_FILE"

echo "汇总报告已生成: $SUMMARY_FILE"
echo ""

# 显示最终统计
error_switches=$(grep "⚠️" "$SUMMARY_FILE" | wc -l)
if [ "$error_switches" -gt 0 ]; then
    echo "⚠️  发现 $error_switches 个交换机有FEC错误，请检查汇总报告"
else
    echo "✅ 所有交换机都没有FEC错误"
fi
