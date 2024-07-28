#!/bin/bash

# 检查hosts.txt是否存在
if [ ! -f "hosts.txt" ]; then
    echo "Error: hosts.txt file not found"
    exit 1
fi

# 创建一个临时文件
tmp_file=$(mktemp)

# 清理hosts.txt文件
while IFS=$'\t' read -r ip user pass || [[ -n "$ip" ]]; do
    # 移除开头和结尾的空白字符
    ip=$(echo "$ip" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    user=$(echo "$user" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    pass=$(echo "$pass" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    
    # 如果所有字段都非空，则写入临时文件
    if [[ -n "$ip" && -n "$user" && -n "$pass" ]]; then
        echo "$ip $user $pass" >> "$tmp_file"
    fi
done < hosts.txt

# 用清理后的内容替换原文件
mv "$tmp_file" hosts.txt

echo "hosts.txt has been cleaned and formatted."
