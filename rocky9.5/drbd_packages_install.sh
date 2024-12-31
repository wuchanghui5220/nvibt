#!/bin/bash

# install_drbd.sh

# 设置错误时退出
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# 日志函数
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# 检查是否为 root 用户
if [ "$(id -u)" != "0" ]; then
    error "This script must be run as root"
fi

# 创建工作目录
WORK_DIR=~/drbd_packages
mkdir -p $WORK_DIR
cd $WORK_DIR

# 备份现有 yum 源
log "Backing up current yum repositories..."
mkdir -p /etc/yum.repos.d/bak
mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/bak/ 2>/dev/null || true

# 创建新的 yum 源配置
log "Creating new repository configurations..."
cat > /etc/yum.repos.d/rocky.repo << 'EOF'
[baseos]
name=Rocky Linux $releasever - BaseOS
baseurl=https://mirrors.aliyun.com/rockylinux/$releasever/BaseOS/$basearch/os/
gpgcheck=1
enabled=1
gpgkey=https://mirrors.aliyun.com/rockylinux/RPM-GPG-KEY-Rocky-9

[appstream]
name=Rocky Linux $releasever - AppStream
baseurl=https://mirrors.aliyun.com/rockylinux/$releasever/AppStream/$basearch/os/
gpgcheck=1
enabled=1
gpgkey=https://mirrors.aliyun.com/rockylinux/RPM-GPG-KEY-Rocky-9

[ha]
name=Rocky Linux $releasever - HighAvailability
baseurl=https://mirrors.aliyun.com/rockylinux/$releasever/HighAvailability/$basearch/os/
gpgcheck=1
enabled=1
gpgkey=https://mirrors.aliyun.com/rockylinux/RPM-GPG-KEY-Rocky-9
EOF

cat > /etc/yum.repos.d/elrepo.repo << 'EOF'
[elrepo]
name=ELRepo.org Community Enterprise Linux Repository - el9
baseurl=https://mirrors.tuna.tsinghua.edu.cn/elrepo/elrepo/el9/$basearch/
enabled=1
gpgcheck=0

[elrepo-extras]
name=ELRepo.org Community Enterprise Linux Extras Repository - el9
baseurl=https://mirrors.tuna.tsinghua.edu.cn/elrepo/extras/el9/$basearch/
enabled=1
gpgcheck=0

[elrepo-kernel]
name=ELRepo.org Community Enterprise Linux Kernel Repository - el9
baseurl=https://mirrors.tuna.tsinghua.edu.cn/elrepo/kernel/el9/$basearch/
enabled=1
gpgcheck=0
EOF

# 清理并更新缓存
log "Cleaning and updating DNF cache..."
dnf clean all
dnf makecache

# 创建基础工具目录
log "Creating directory for basic tools..."
mkdir -p $WORK_DIR/basic_tools
cd $WORK_DIR/basic_tools

# 下载基础工具包
log "Downloading basic tools..."
dnf download --resolve --alldeps dnf-plugins-core tar gzip

# 安装基础工具
log "Installing basic tools..."
dnf install -y ./dnf-plugins-core* ./tar* ./gzip*

sleep 5

cd $WORK_DIR

# 下载所需的包
log "Downloading required packages..."
dnf download --resolve --alldeps pcs pacemaker corosync resource-agents
dnf download --resolve --alldeps drbd9x-utils kmod-drbd9x

# 创建打包文件
log "Creating package archive..."
tar czf drbd_packages.tar.gz *.rpm

# 安装所有下载的包
log "Installing packages..."
dnf install -y ./*.rpm

sleep 3
echo ""

# 加载 DRBD 模块
log "Loading DRBD kernel module..."
modprobe drbd || error "Failed to load DRBD module"

sleep 3
echo "

# 验证安装
log "Verifying installation..."
drbdadm --version
lsmod | grep drbd


sleep 3
echo ""

# 启用并启动服务
log "Enabling and starting services..."
systemctl enable --now pcsd

sleep 3
echo "

log "Installation completed successfully!"
log "Package archive is available at: $WORK_DIR/drbd_packages.tar.gz"

# 显示安装结果摘要
echo
echo "=== Installation Summary ==="
echo "DRBD Version: $(drbdadm --version | head -n 1)"
echo "Kernel Module: $(lsmod | grep drbd | awk '{print $1 " (size: " $2 ")"}')"
echo "PCSD Status: $(systemctl is-active pcsd)"
echo "Package Archive: $WORK_DIR/drbd_packages.tar.gz"
