#!/bin/bash

# 服务器信息配置文件
cat > servers.txt << EOF
172.16.0.1 root lgtest2024
172.16.0.2 root lgtest2024
172.16.0.3 root lgtest2024
172.16.0.4 root lgtest2024
172.16.0.5 root lgtest2024
172.16.0.6 root lgtest2024
172.16.0.7 root lgtest2024
172.16.0.8 root lgtest2024
EOF

# 安装sshpass(如果需要)
if ! command -v sshpass &> /dev/null; then
    echo "正在安装sshpass..."
    if command -v apt &> /dev/null; then
        sudo apt update && sudo apt install -y sshpass
    elif command -v yum &> /dev/null; then
        sudo yum install -y sshpass
    else
        echo "无法安装sshpass，请手动安装"
        exit 1
    fi
fi

# 在每台服务器上生成密钥并收集公钥
echo "开始在各服务器上生成密钥..."
declare -A public_keys
while read server_ip username password; do
    echo "正在处理服务器: $server_ip"
    
    # 在远程服务器上生成密钥（如果不存在）
    sshpass -p "$password" ssh -o StrictHostKeyChecking=no "$username@$server_ip" \
        "if [ ! -f ~/.ssh/id_rsa ]; then mkdir -p ~/.ssh; ssh-keygen -t rsa -N \"\" -f ~/.ssh/id_rsa; fi"
    
    # 获取公钥
    public_keys["$server_ip"]=$(sshpass -p "$password" ssh "$username@$server_ip" "cat ~/.ssh/id_rsa.pub")
done < servers.txt

# 在每台服务器上配置其他服务器的免密登录
echo "开始配置服务器间互相免密登录..."
while read server1_ip username1 password1; do
    while read server2_ip username2 password2; do
        # 跳过同一台服务器
        if [ "$server1_ip" == "$server2_ip" ]; then
            continue
        fi
        
        echo "配置 $server1_ip -> $server2_ip"
        
        # 将server2的公钥添加到server1的authorized_keys中
        sshpass -p "$password1" ssh -o StrictHostKeyChecking=no "$username1@$server1_ip" \
            "mkdir -p ~/.ssh; echo '${public_keys[$server2_ip]}' >> ~/.ssh/authorized_keys; \
             chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys"
        
        if [ $? -eq 0 ]; then
            echo "配置成功: $server1_ip -> $server2_ip"
        else
            echo "配置失败: $server1_ip -> $server2_ip"
        fi
    done < servers.txt
done < servers.txt

echo "配置完成!"

# 测试连接
echo "测试服务器间SSH连接..."
while read server1_ip username1 password1; do
    while read server2_ip username2 password2; do
        if [ "$server1_ip" == "$server2_ip" ]; then
            continue
        fi
        
        echo "测试 $server1_ip -> $server2_ip"
        sshpass -p "$password1" ssh -o BatchMode=yes -o ConnectTimeout=5 "$username1@$server1_ip" \
            "ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no $username2@$server2_ip 'echo \"连接成功\"'"
        
        if [ $? -eq 0 ]; then
            echo "测试通过: $server1_ip -> $server2_ip"
        else
            echo "测试失败: $server1_ip -> $server2_ip"
        fi
    done < servers.txt
done < servers.txt
