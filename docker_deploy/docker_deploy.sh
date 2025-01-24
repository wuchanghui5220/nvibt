#!/bin/bash

# 设置颜色输出
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 检查tar命令是否存在
check_tar_command() {
    if ! command -v tar &> /dev/null; then
        echo -e "${RED}错误: tar命令未安装。请先安装tar工具。${NC}" >&2
        exit 1
    fi
}

# 检查是否具有root权限
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}此脚本必须以root权限运行${NC}" 
   exit 1
fi

# 日志记录函数
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

# 错误处理函数
error_exit() {
    echo -e "${RED}错误: $1${NC}" >&2
    exit 1
}

# 检查并解压Docker安装包
deploy_docker() {
    # 首先检查tar命令
    check_tar_command

    log "开始部署Docker 27.5.1..."
    
    # 检查安装包是否存在
    if [[ ! -f "docker-27.5.1.tgz" ]]; then
        error_exit "Docker安装包 docker-27.5.1.tgz 未找到"
    fi

    # 解压Docker安装包
    tar -xzf docker-27.5.1.tgz || error_exit "Docker安装包解压失败"
    
    # 复制Docker二进制文件
    cp docker/* /usr/local/bin/ || error_exit "复制Docker二进制文件失败"
    
    log "Docker二进制文件安装完成"
}

# 配置Docker服务
config_docker_service() {
    log "配置Docker系统服务..."

    # 创建Docker服务配置文件
    cat > /etc/systemd/system/docker.service <<EOF
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network.target

[Service]
ExecStart=/usr/local/bin/dockerd
ExecReload=/bin/kill -s HUP \$MAINPID
LimitNOFILE=1048576
LimitNPROC=512
TimeoutSec=0
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

    # 重新加载服务配置
    systemctl daemon-reload || error_exit "服务配置重载失败"
    
    log "Docker服务配置完成"
}

# 安装Docker Compose
install_docker_compose() {
    log "安装Docker Compose..."

    # 检查Compose二进制文件是否存在
    if [[ ! -f "docker-compose-linux-x86_64" ]]; then
        error_exit "Docker Compose二进制文件未找到"
    fi

    # 创建CLI插件目录
    mkdir -p /usr/local/lib/docker/cli-plugins/

    # 复制并授权Docker Compose
    cp docker-compose-linux-x86_64 /usr/local/lib/docker/cli-plugins/docker-compose || error_exit "Docker Compose安装失败"
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

    # 验证Docker Compose版本
    docker compose version || error_exit "Docker Compose版本验证失败"
    
    log "Docker Compose安装完成"
}

# 启动并设置开机自启
start_docker_service() {
    log "启动Docker服务..."

    # 启动Docker服务
    systemctl start docker || error_exit "Docker服务启动失败"

    # 设置开机自启
    systemctl enable docker || error_exit "Docker开机自启设置失败"

    # 重启Docker服务
    systemctl restart docker || error_exit "Docker服务重启失败"

    log "Docker服务启动并设置开机自启完成"
}

# 主执行流程
main() {
    deploy_docker
    config_docker_service
    install_docker_compose
    start_docker_service

    log "Docker 27.5.1 部署成功！"
}

# 执行主函数
main
