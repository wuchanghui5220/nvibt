#!/bin/bash

# 输出文件名称
output_file="iblinkinfo_line2csv.csv"
tmp_file="iblinkinfo_line.txt"
# 添加表头
echo "Source Device,Source Port,Destination Device,Destination Port" > "$output_file"

# 执行 iblinkinfo --switches-only -l 并逐行处理
iblinkinfo --switches-only -l |sed 's/\[\ \ \]//g' |grep -v 'Mellanox Technologies Aggregation Node' > "$tmp_file"
cat "$tmp_file" | while read -r line; do
    # 检查行中是否包含 "mlx5", "hca", "down"
    if echo "$line" | grep -E -i "mlx5|hca" > /dev/null; then
        # 如果包含，则按照第一种情况处理
        echo "$line" | awk '
        BEGIN { OFS="," }
        {
            src_device = $2
            src_port = $4
            dst_device = ($14 != "" ? $14 : "NA")
            dst_port = ($15 != "" ? $15 : "NA")
            print src_device, src_port, dst_device, dst_port
        }' | sed 's/"//g' >> "$output_file"
    else
        # 如果不包含，则按照第二种情况处理
        echo "$line" | awk '
        BEGIN { OFS="," }
        {
            src_device = $2
            src_port = $4
            dst_device = ($14 != "" ? $14 : "NA")
            dst_port = ($13 != "" ? $13 : "NA")
            print src_device, src_port, dst_device, dst_port
        }' | sed 's/"//g' >> "$output_file"
    fi
done

sleep 1
rm -rf "$tmp_file"

echo "Processing complete. Output written to $output_file"
