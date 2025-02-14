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

# 显示使用方法
usage() {
    echo "Usage: $0 [command] [options]"
    echo "Commands:"
    echo "  download                     Only download packages"
    echo "  install <package_path>       Install from specified package archive"
    echo "  all                         Download and install (default)"
    echo
    echo "Examples:"
    echo "  $0 download                 # Download packages only"
    echo "  $0 install ./drbd_packages.tar.gz  # Install from specified archive"
    echo "  $0 all                      # Download and install"
    exit 1
}

# 检查是否为 root 用户
check_root() {
    if [ "$(id -u)" != "0" ]; then
        error "This script must be run as root"
    fi
}

# 配置仓库
setup_repos() {
    log "Backing up current yum repositories..."
    mkdir -p /etc/yum.repos.d/bak
    mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/bak/ 2>/dev/null || true

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

    log "Cleaning and updating DNF cache..."
    dnf clean all
    dnf makecache
}

# 下载包
download_packages() {
    log "Creating work directory..."
    WORK_DIR=$HOME/drbd_packages
    mkdir -p $WORK_DIR
    cd $WORK_DIR

    # 下载基础工具包
    log "Creating directory for basic tools..."
    mkdir -p $WORK_DIR/basic_tools
    cd $WORK_DIR/basic_tools
    log "Downloading basic tools..."
    dnf download --resolve --alldeps dnf-plugins-core tar gzip

    cd $WORK_DIR
    log "Downloading required packages..."
    dnf download --resolve --alldeps pcs pacemaker corosync resource-agents
    dnf download --resolve --alldeps drbd9x-utils kmod-drbd9x

    log "Creating package archive..."
    tar czf drbd_packages.tar.gz *.rpm
    log "Packages downloaded to: $WORK_DIR/drbd_packages.tar.gz"
}

# 安装包
install_packages() {
    local package_file="$1"
    
    # 检查参数
    if [ -z "$package_file" ]; then
        error "Package file path is required for installation"
    fi
    
    # 检查文件是否存在
    if [ ! -f "$package_file" ]; then
        error "Package file not found: $package_file"
    fi
    
    # 创建临时工作目录
    local temp_dir=$(mktemp -d)
    log "Extracting packages to temporary directory..."
    
    # 解压文件
    tar xzf "$package_file" -C "$temp_dir" || error "Failed to extract package archive"
    cd "$temp_dir"

    # 安装基础工具（如果存在）
    if [ -d "basic_tools" ]; then
        log "Installing basic tools..."
        cd basic_tools
        dnf install -y ./dnf-plugins-core* ./tar* ./gzip* || error "Failed to install basic tools"
        cd ..
        sleep 5
    fi

    # 安装主要包
    log "Installing packages..."
    dnf install -y ./*.rpm || error "Failed to install packages"
    sleep 3

    # 加载 DRBD 模块
    log "Loading DRBD kernel module..."
    modprobe drbd || error "Failed to load DRBD module"
    sleep 3

    # 验证安装
    log "Verifying installation..."
    drbdadm --version
    lsmod | grep drbd
    sleep 3

    # 启用并启动服务
    log "Enabling and starting services..."
    systemctl enable --now pcsd
    sleep 3

    # 清理临时目录
    rm -rf "$temp_dir"

    show_summary
}

# 显示安装摘要
show_summary() {
    log "Installation completed successfully!"
    echo
    echo "=== Installation Summary ==="
    echo "DRBD Version: $(drbdadm --version | head -n 1)"
    echo "Kernel Module: $(lsmod | grep drbd | awk '{print $1 " (size: " $2 ")"}')"
    echo "PCSD Status: $(systemctl is-active pcsd)"
    echo "Package Archive: $WORK_DIR/drbd_packages.tar.gz"
}

# 主程序
main() {
    check_root

    case "$1" in
        "download")
            setup_repos
            download_packages
            ;;
        "install")
            if [ -z "$2" ]; then
                error "Please specify the package archive path"
            fi
            install_packages "$2"
            ;;
        "all"|"")
            setup_repos
            download_packages
            install_packages "$HOME/drbd_packages/drbd_packages.tar.gz"
            ;;
        *)
            usage
            ;;
    esac
}

# 执行主程序
main "$@"
