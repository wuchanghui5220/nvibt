# 停止所有正在运行的容器
docker stop $(docker ps -aq) 2>/dev/null || true

# 停止 Docker 服务
systemctl stop docker
systemctl stop docker.socket 2>/dev/null || true

# 禁用 Docker 服务
systemctl disable docker
systemctl disable docker.socket 2>/dev/null || true

# 删除 Docker 服务文件
rm -f /etc/systemd/system/docker.service
rm -f /etc/systemd/system/docker.socket
rm -f /etc/systemd/system/docker.service.d/* 2>/dev/null || true
rm -rf /etc/systemd/system/docker.service.d 2>/dev/null || true

# 重新加载 systemd 配置
systemctl daemon-reload
systemctl reset-failed

# 删除 Docker 二进制文件
rm -f /usr/bin/docker*
rm -f /usr/bin/containerd*
rm -f /usr/bin/ctr
rm -f /usr/bin/runc

# 删除 Docker 配置
rm -rf /etc/docker

# 删除 Docker 数据目录
rm -rf /var/lib/docker
rm -rf /var/run/docker.sock

# 删除 Docker 组（可选）
# groupdel docker 2>/dev/null || true

echo "Docker 已完全卸载，现在可以运行新的安装脚本了"
