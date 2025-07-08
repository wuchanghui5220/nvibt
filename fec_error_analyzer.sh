#!/bin/bash

# FEC错误分析脚本
# 用法: ./fec_error_analyzer.sh [选项] [日志文件]
# 示例: ./fec_error_analyzer.sh -b 6 -t 10 fec_histogram.log

# 默认参数
LOG_FILE=""
BIN_NUMBER=6
THRESHOLD=10
OUTPUT_FILE=""
SHOW_ALL=false
VERBOSE=false

# 显示帮助信息
show_help() {
    cat << EOF
FEC错误分析脚本

用法: $0 [选项] [日志文件]

选项:
  -b, --bin NUMBER     指定要检查的Bin号 (默认: 6)
  -t, --threshold NUM  设置错误数量阈值 (默认: 10)
  -o, --output FILE    输出结果到文件
  -a, --all           显示所有Bin的错误统计
  -v, --verbose       显示详细信息
  -h, --help          显示此帮助信息

示例:
  $0 fec_histogram.log                    # 检查Bin 6错误 >= 10
  $0 -b 5 -t 50 fec_histogram.log        # 检查Bin 5错误 >= 50
  $0 -a fec_histogram.log                 # 显示所有Bin的统计
  $0 -o report.txt fec_histogram.log      # 结果输出到文件

支持的文件类型: .log, .txt 以及目录中的FEC结果文件
EOF
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -b|--bin)
            BIN_NUMBER="$2"
            shift 2
            ;;
        -t|--threshold)
            THRESHOLD="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -a|--all)
            SHOW_ALL=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        -*)
            echo "错误: 未知选项 $1"
            show_help
            exit 1
            ;;
        *)
            if [ -z "$LOG_FILE" ]; then
                LOG_FILE="$1"
            else
                echo "错误: 只能指定一个日志文件"
                exit 1
            fi
            shift
            ;;
    esac
done

# 如果没有指定文件，尝试自动查找
if [ -z "$LOG_FILE" ]; then
    # 查找当前目录和子目录中的FEC文件
    POSSIBLE_FILES=(
        "fec_histogram.log"
        "*.log"
        "*fec*.log"
        "*fec*.txt"
        "fec_results_*/summary_report.txt"
        "fec_results_*/*.txt"
    )
    
    for pattern in "${POSSIBLE_FILES[@]}"; do
        FILES=$(find . -name "$pattern" -type f 2>/dev/null | head -5)
        if [ -n "$FILES" ]; then
            echo "发现可能的FEC文件:"
            echo "$FILES" | nl
            echo ""
            read -p "请选择文件编号 (1-5) 或输入文件路径: " choice
            
            if [[ "$choice" =~ ^[1-5]$ ]]; then
                LOG_FILE=$(echo "$FILES" | sed -n "${choice}p")
                break
            elif [ -f "$choice" ]; then
                LOG_FILE="$choice"
                break
            fi
        fi
    done
    
    if [ -z "$LOG_FILE" ]; then
        echo "错误: 未找到FEC日志文件"
        echo ""
        echo "请指定日志文件:"
        echo "$0 [选项] <日志文件>"
        exit 1
    fi
fi

# 检查文件是否存在
if [ ! -f "$LOG_FILE" ]; then
    echo "错误: 文件 '$LOG_FILE' 不存在"
    exit 1
fi

# 设置输出重定向
if [ -n "$OUTPUT_FILE" ]; then
    exec 1> >(tee "$OUTPUT_FILE")
fi

# 显示分析信息
echo "FEC错误分析报告"
echo "================"
echo "日志文件: $LOG_FILE"
echo "文件大小: $(du -h "$LOG_FILE" | cut -f1)"
echo "分析时间: $(date)"

if [ "$SHOW_ALL" = true ]; then
    echo "模式: 显示所有Bin统计"
else
    echo "检查目标: Bin $BIN_NUMBER"
    echo "错误阈值: >= $THRESHOLD"
fi

echo ""

# 分析函数
analyze_bin_errors() {
    local bin_num=$1
    local threshold=$2
    
    if [ "$VERBOSE" = true ]; then
        echo "正在分析 Bin $bin_num 错误..."
    fi
    
    # 执行分析
    local results=$(grep --text -B 10 "Bin $bin_num" "$LOG_FILE" | awk -v threshold="$threshold" -v bin="$bin_num" '
    /mlx5_|LID:|Port/ {device=$0}
    ($1 == "Bin" && $2 == bin) && $5 >= threshold {
        print device " -> " $0
    }
    ')
    
    if [ -n "$results" ]; then
        echo "⚠️  Bin $bin_num 错误数量 >= $threshold 的设备:"
        echo "=============================================="
        echo "$results"
        
        # 统计信息
        local device_count=$(echo "$results" | wc -l)
        local max_errors=$(echo "$results" | awk '{print $NF}' | sort -n | tail -1)
        local total_errors=$(echo "$results" | awk '{sum += $NF} END {print sum+0}')
        
        echo ""
        echo "Bin $bin_num 统计:"
        echo "----------------"
        echo "受影响设备数: $device_count"
        echo "最大错误数: $max_errors"
        echo "总错误数: $total_errors"
        echo ""
    else
        echo "✅ Bin $bin_num: 未发现错误数量 >= $threshold 的设备"
        echo ""
    fi
}

# 显示所有Bin统计
show_all_bins() {
    echo "所有Bin错误统计"
    echo "================"
    
    for bin in {0..7}; do
        local total_errors=$(grep --text "Bin $bin" "$LOG_FILE" | awk '{sum += $5} END {print sum+0}')
        local device_count=$(grep --text "Bin $bin" "$LOG_FILE" | wc -l)
        local max_errors=$(grep --text "Bin $bin" "$LOG_FILE" | awk '{print $5}' | sort -n | tail -1)
        
        printf "Bin %d: 总错误数=%s, 设备数=%s, 最大错误数=%s\n" \
               "$bin" "${total_errors:-0}" "${device_count:-0}" "${max_errors:-0}"
    done
    
    echo ""
    echo "详细分析 (阈值 >= $THRESHOLD):"
    echo "=========================="
}

# 执行分析
if [ "$SHOW_ALL" = true ]; then
    show_all_bins
    
    # 分析所有Bin
    for bin in {0..7}; do
        analyze_bin_errors "$bin" "$THRESHOLD"
    done
else
    # 只分析指定的Bin
    analyze_bin_errors "$BIN_NUMBER" "$THRESHOLD"
fi

# 生成建议
echo "分析建议"
echo "========"

# 检查是否有严重错误
CRITICAL_ERRORS=$(grep --text -E "Bin [3-7]" "$LOG_FILE" | awk -v threshold="100" '$5 >= threshold' | wc -l)

if [ "$CRITICAL_ERRORS" -gt 0 ]; then
    echo "🚨 发现严重FEC错误 (Bin 3-7, 错误数 >= 100)"
    echo "   建议立即检查相关链路和设备"
elif grep --text -E "Bin [1-7]" "$LOG_FILE" | awk '$5 >= 10' | head -1 >/dev/null; then
    echo "⚠️  发现中等FEC错误"
    echo "   建议定期监控，考虑预防性维护"
else
    echo "✅ FEC错误水平正常"
    echo "   网络链路质量良好"
fi

echo ""
echo "分析完成: $(date)"

if [ -n "$OUTPUT_FILE" ]; then
    echo "结果已保存到: $OUTPUT_FILE"
fi
