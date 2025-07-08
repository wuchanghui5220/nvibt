#!/bin/bash
# FEC直方图清理和查询脚本
# 功能：查询FEC直方图，可选择性清理
# 用法：./fec_histogram_ibadapter.sh [选项]
# 选项：
#   -c, --clear     清理FEC直方图后再查询
#   -h, --help      显示帮助信息
#   -l, --log FILE  指定日志文件路径（默认：/mnt/nfs/MOFED_firmware/FEC/fec_histogram.log）
#   -d, --devices   指定设备列表（默认：0,1,2,3,6,7,8,9）

# 默认设置
DEFAULT_LOG_FILE="/mnt/nfs/MOFED_firmware/FEC/fec_histogram.log"
DEFAULT_DEVICES=(0 1 2 3 6 7 8 9)
CLEAR_HISTOGRAM=false
LOG_FILE="$DEFAULT_LOG_FILE"
DEVICES=("${DEFAULT_DEVICES[@]}")

# 显示帮助信息
show_help() {
    echo "FEC直方图查询脚本"
    echo
    echo "用法: $0 [选项]"
    echo
    echo "选项:"
    echo "  -c, --clear                清理FEC直方图后再查询"
    echo "  -h, --help                 显示此帮助信息"
    echo "  -l, --log FILE             指定日志文件路径"
    echo "                             默认: $DEFAULT_LOG_FILE"
    echo "  -d, --devices DEVICE_LIST  指定设备列表，用逗号分隔"
    echo "                             默认: ${DEFAULT_DEVICES[*]}"
    echo
    echo "示例:"
    echo "  $0                         # 仅查询FEC直方图"
    echo "  $0 -c                      # 清理后查询FEC直方图"
    echo "  $0 -c -l /tmp/fec.log      # 清理后查询，并指定日志文件"
    echo "  $0 -d 0,1,2,3              # 仅查询指定设备"
    echo "  $0 -c -d 0,1 -l /tmp/fec.log # 清理指定设备后查询，并指定日志文件"
    echo
}

# 解析命令行参数
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--clear)
                CLEAR_HISTOGRAM=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -l|--log)
                if [[ -z "$2" ]]; then
                    echo "错误: -l/--log 需要指定文件路径" >&2
                    exit 1
                fi
                LOG_FILE="$2"
                shift 2
                ;;
            -d|--devices)
                if [[ -z "$2" ]]; then
                    echo "错误: -d/--devices 需要指定设备列表" >&2
                    exit 1
                fi
                IFS=',' read -ra DEVICES <<< "$2"
                shift 2
                ;;
            *)
                echo "错误: 未知参数 '$1'" >&2
                echo "使用 -h 或 --help 查看帮助信息"
                exit 1
                ;;
        esac
    done
}

# 获取IP地址的函数
get_ip_address() {
    local ip=$(ifconfig bond0.1000 2>/dev/null | grep "inet 10" | awk '{print $2}')
    if [ -z "$ip" ]; then
        # 如果bond0.1000没有IP，尝试其他常见接口
        ip=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' | head -1)
    fi
    echo "${ip:-unknown}"
}

# 清理FEC直方图函数
clear_fec_histogram() {
    echo "开始清理FEC直方图..."
    local failed_devices=()

    for i in "${DEVICES[@]}"; do
        echo "正在清理 mlx5_$i 的FEC直方图..."
        if mlxlink -d mlx5_$i --clear_histogram --rx_fec_histogram >/dev/null 2>&1; then
            echo "mlx5_$i 清理完成"
        else
            echo "mlx5_$i 清理失败" >&2
            failed_devices+=("$i")
        fi
    done

    if [ ${#failed_devices[@]} -gt 0 ]; then
        echo "警告: 以下设备清理失败: ${failed_devices[*]}" >&2
    fi
    echo "清理操作完成"
}

# 查询FEC直方图函数
query_fec_histogram() {
    echo "开始查询FEC直方图..."

    # 创建日志文件目录（如果不存在）
    local log_dir=$(dirname "$LOG_FILE")
    if [ ! -d "$log_dir" ]; then
        mkdir -p "$log_dir" 2>/dev/null || {
            echo "错误: 无法创建日志目录 $log_dir" >&2
            exit 1
        }
    fi

    # 查询并追加结果到日志文件
    {
        echo "===================="
        echo "查询时间: $(date)"
        echo "主机名: $(hostname)"
        echo "IP地址: $(get_ip_address)"
        echo "清理状态: $([ "$CLEAR_HISTOGRAM" = true ] && echo "已清理" || echo "未清理")"
        echo "设备列表: ${DEVICES[*]}"
        echo "===================="

        local failed_queries=()
        for i in "${DEVICES[@]}"; do
            echo "$(hostname) $(get_ip_address) mlx5_$i"
            if ! mlxlink -d mlx5_$i --show_histogram --rx_fec_histogram 2>/dev/null | tail -10 | tr -cd '[:print:]\n\t' | sed '/^$/d'; then
                echo "错误: mlx5_$i 查询失败"
                failed_queries+=("$i")
            fi
            echo ""  # 添加空行分隔
        done

        if [ ${#failed_queries[@]} -gt 0 ]; then
            echo "查询失败的设备: ${failed_queries[*]}"
        fi

        echo "===================="
        echo ""
    } >> "$LOG_FILE"

    echo "查询完成，结果已追加到: $LOG_FILE"
}

# 主函数
main() {
    # 解析命令行参数
    parse_arguments "$@"

    # 显示运行参数
    echo "运行参数:"
    echo "  清理直方图: $([ "$CLEAR_HISTOGRAM" = true ] && echo "是" || echo "否")"
    echo "  日志文件: $LOG_FILE"
    echo "  设备列表: ${DEVICES[*]}"
    echo

    # 检查mlxlink命令是否存在
    if ! command -v mlxlink >/dev/null 2>&1; then
        echo "错误: mlxlink 命令未找到，请确保已安装MLNX_OFED驱动" >&2
        exit 1
    fi

    # 验证设备列表
    for device in "${DEVICES[@]}"; do
        if ! [[ "$device" =~ ^[0-9]+$ ]]; then
            echo "错误: 设备ID '$device' 不是有效的数字" >&2
            exit 1
        fi
    done

    # 如果需要清理，则先清理
    if [ "$CLEAR_HISTOGRAM" = true ]; then
        clear_fec_histogram
        echo
    fi

    # 查询FEC直方图
    query_fec_histogram
}

# 执行主函数
main "$@"
