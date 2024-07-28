# nvibt
nvidia infiniband network management tools

# 批量SSH密钥部署和SCP文件传输指南

本指南包含三个主要脚本，用于批量部署SSH密钥和进行SCP文件传输。以下是使用这些脚本的步骤和说明。

## 1. 格式化 hosts.txt文件

首先，hosts.txt 文件是从excel 表格中复制到文本文件的，带有制表符的3列文本，IP\tusername\tpassword，保存到文本文件后，使用以下脚本清理文件，使其为空格分隔。

### clean_hosts.sh

使用方法：

1. 保存脚本为 `clean_hosts.sh`
2. 运行 `chmod +x clean_hosts.sh` 使其可执行
3. 执行 `./clean_hosts.sh`

确保hosts.txt文件每行格式为：`IP_address username password`

## 2. 批量部署SSH密钥

使用以下脚本将您的SSH公钥部署到所有目标服务器：

### batch_ssh_key_copy.sh

使用方法：

1. 保存脚本为 `batch_ssh_key_copy.sh`
2. 运行 `chmod +x batch_ssh_key_copy.sh` 使其可执行
3. 执行 `./batch_ssh_key_copy.sh ~/.ssh/id_rsa.pub`

注意：此脚本需要安装 `sshpass`。您可以使用 `sudo apt-get install sshpass` (Debian/Ubuntu) 或 `sudo yum install sshpass` (CentOS/RHEL) 来安装。

## 3. 批量SCP文件传输

在完成SSH密钥部署后，使用以下脚本进行批量文件传输：

### batch_scp.sh

使用方法：

1. 保存脚本为 `batch_scp.sh`
2. 运行 `chmod +x batch_scp.sh` 使其可执行
3. 执行 `./batch_scp.sh /path/to/local/file`

注意：此脚本需要安装 GNU Parallel。您可以使用 `sudo apt-get install parallel` (Debian/Ubuntu) 或 `sudo yum install parallel` (CentOS/RHEL) 来安装。

## 操作步骤总结

1. 准备 hosts.txt 文件，包含所有目标服务器的信息。
2. 运行 `clean_hosts.sh` 清理 hosts.txt 文件。
3. 运行 `batch_ssh_key_copy.sh` 部署SSH公钥到所有服务器。
4. 运行 `batch_scp.sh` 批量传输文件到所有服务器。

## 安全注意事项

- 在完成SSH密钥部署后，建议删除或安全存储包含密码的 hosts.txt 文件。
- 考虑使用更安全的方法进行初始SSH密钥设置，如物理访问或已建立的安全通道。
- 对于大规模部署，考虑使用配置管理工具如Ansible、Puppet或Chef。
