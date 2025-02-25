#!/bin/bash
# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}
log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}
# 下载函数
download_packages() {
    # 安装必要工具
    dnf install -y tar wget curl
    # 创建工作目录
    mkdir -p docker-files
    cd docker-files
    # 下载 Docker 二进制文件（使用阿里云镜像）
    log_info "下载 Docker 二进制文件..."
    wget https://mirrors.aliyun.com/docker-ce/linux/static/stable/x86_64/docker-23.0.6.tgz || {
        log_error "Docker 下载失败，尝试备用链接..."
        wget https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/static/stable/x86_64/docker-23.0.6.tgz || {
            log_error "Docker 下载失败"
            exit 1
        }
    }
    # 创建 systemd 服务文件
    log_info "创建服务文件..."
    cat > docker.service << 'EOF'
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target docker.socket
Wants=network-online.target
Requires=docker.socket

[Service]
Type=notify
ExecStart=/usr/bin/dockerd
ExecReload=/bin/kill -s HUP $MAINPID
TimeoutSec=0
RestartSec=2
Restart=always
StartLimitBurst=3
StartLimitInterval=60s
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
Delegate=yes
KillMode=process

[Install]
WantedBy=multi-user.target
EOF

    # 创建 docker.socket 文件
    log_info "创建 docker.socket 文件..."
    cat > docker.socket << 'EOF'
[Unit]
Description=Docker Socket for the API
PartOf=docker.service

[Socket]
ListenStream=/var/run/docker.sock
SocketMode=0660
SocketUser=root
SocketGroup=docker

[Install]
WantedBy=sockets.target
EOF

    # 打包文件
    cd ..
    tar czf docker-offline.tar.gz docker-files
    rm -rf docker-files
    log_info "下载完成！文件已保存为：docker-offline.tar.gz"
}
# 安装函数
install_packages() {
    if [ ! -f "docker-offline.tar.gz" ]; then
        log_error "未找到安装包：docker-offline.tar.gz"
        exit 1
    fi
    # 解压文件
    log_info "解压安装包..."
    tar xzf docker-offline.tar.gz
    cd docker-files
    # 解压并安装 Docker 二进制文件
    log_info "安装 Docker..."
    tar xzf docker-*.tgz
    cp docker/* /usr/bin/
    # 安装 systemd 服务文件
    log_info "安装服务文件..."
    cp docker.service /etc/systemd/system/
    cp docker.socket /etc/systemd/system/
    # 创建 docker 组
    groupadd docker 2>/dev/null || true
    # 配置 Docker
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << 'EOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m",
        "max-file": "3"
    },
    "registry-mirrors": [
        "https://mirror.ccs.tencentyun.com",
        "https://hub-mirror.c.163.com",
        "https://mirror.baidubce.com"
    ]
}
EOF
    # 启动服务
    log_info "启动 Docker 服务..."
    systemctl daemon-reload
    systemctl enable docker.socket
    systemctl enable docker
    systemctl start docker.socket
    systemctl start docker
    # 验证安装
    if docker --version >/dev/null 2>&1; then
        log_info "Docker 安装成功！"
        log_info "Docker 版本: $(docker --version)"
        log_info "Docker 服务状态: $(systemctl is-active docker)"
        log_info "Docker Socket 状态: $(systemctl is-active docker.socket)"
    else
        log_error "Docker 安装失败"
        exit 1
    fi
    # 清理
    cd ..
    rm -rf docker-files
    log_info "安装完成！"
}
# 一键安装函数
install_all() {
    log_info "开始一键安装 Docker..."
    download_packages
    if [ $? -eq 0 ]; then
        install_packages
    else
        log_error "下载失败，安装终止"
        exit 1
    fi
}
# 主程序
case "$1" in
    "download")
        download_packages
        ;;
    "install")
        install_packages
        ;;
    "all")
        install_all
        ;;
    *)
        echo "用法："
        echo "  下载安装包：         $0 download   # 仅下载离线安装包"
        echo "  离线安装：           $0 install    # 使用已下载的安装包安装"
        echo "  在线下载并安装：     $0 all        # 一键下载并安装"
        ;;
esac
