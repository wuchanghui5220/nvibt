import pandas as pd

# 加载 device_names.xlsx，读取所有 sheet
device_file = 'device_names_1250_servers.xlsx'
device_sheets = pd.read_excel(device_file, sheet_name=None)

# 加载 switch_port_mapping.xlsx，读取所有 sheet
switch_port_mapping_file = 'switch_port_mappings_1250_servers.xlsx'
switch_sheets = pd.read_excel(switch_port_mapping_file, sheet_name=None)

# 准备一个设备名替换字典
hostname_mapping = {}

# 从每个 sheet 表中提取 "hostname" 和 "new hostname" 进行映射
for sheet_name, df in device_sheets.items():
    for _, row in df.iterrows():
        old_hostname = row['hostname']
        new_hostname = row['new hostname']
        hostname_mapping[old_hostname] = new_hostname

# 创建 ExcelWriter 对象，用于写入多个 sheet
output_file = f'updated_{switch_port_mapping_file}'
with pd.ExcelWriter(output_file) as writer:
    # 遍历处理每个 sheet
    for sheet_name, switch_data in switch_sheets.items():
        # 定义需要替换的列名，包括第一列和 "Connected Device"
        columns_to_replace = [switch_data.columns[0], 'Connected Device']
        
        # 遍历 switch_port_mapping 中的设备名列，并替换匹配的设备名
        for column in columns_to_replace:
            if column in switch_data.columns:  # 确保列存在
                switch_data[column] = switch_data[column].replace(hostname_mapping)
        
        # 将处理后的数据写入到对应的 sheet
        switch_data.to_excel(writer, sheet_name=sheet_name, index=False)

print(f"所有 sheet 的设备名替换完成，结果已保存至 {output_file}")
