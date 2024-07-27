#!/bin/bash

# 禁用 GNU Parallel 引用通知
export PARALLEL_HOME="$HOME/.parallel"
mkdir -p "$PARALLEL_HOME"
touch "$PARALLEL_HOME/will-cite"

# 检查是否提供了输入文件参数
if [ $# -eq 0 ]; then
    echo "使用方法: $0 <输入文件名>"
    exit 1
fi

# 设置输入文件和输出文件名
host_file="$1"
prefix=$(basename "$host_file" .txt)
reachable_file="${prefix}_reachable_hosts.txt"
unreachable_file="${prefix}_unreachable_hosts.txt"

# 检查输入文件是否存在
if [ ! -f "$host_file" ]; then
    echo "Error: 文件 $host_file 不存在。"
    exit 1
fi

# 检查 parallel 是否安装
if ! command -v parallel &> /dev/null
then
    echo "parallel 未安装。请安装 parallel 后再运行此脚本。"
    exit 1
fi

# 清空或创建输出文件
> "$reachable_file"
> "$unreachable_file"

# 定义 ping 函数
do_ping() {
    local ip=$1
    local hostname=$2
    result=$(ping -c 4 -W 2 $ip 2>&1)
    if [ $? -eq 0 ]; then
        avg_time=$(echo "$result" | tail -1 | awk '{print $4}' | cut -d '/' -f 2)
        echo "$hostname ($ip) is reachable (avg time: ${avg_time}ms)"
        echo "$hostname,$ip,${avg_time}ms" >> "$reachable_file"
    else
        echo "$hostname ($ip) is unreachable"
        echo "$hostname,$ip" >> "$unreachable_file"
    fi
}

export -f do_ping
export reachable_file unreachable_file

# 使用 parallel 执行 ping 测试
cat "$host_file" | parallel -C ',' --jobs 50 'do_ping {2} {1}'

# 显示可达和不可达主机的数量
reachable_count=$(wc -l < "$reachable_file")
unreachable_count=$(wc -l < "$unreachable_file")
echo "Total reachable hosts: $reachable_count"
echo "Total unreachable hosts: $unreachable_count"
echo "Reachable hosts have been recorded in $reachable_file"
echo "Unreachable hosts have been recorded in $unreachable_file"
