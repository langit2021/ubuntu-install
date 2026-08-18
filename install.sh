#!/usr/bin/env bash
set -e
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root."
    exit 1
fi
echo "================================"
echo " Ubuntu Install Framework"
echo " Version 0.12"
echo " curl -sL https://raw.githubusercontent.com/langit2021/ubuntu-install/main/install.sh | sudo bash"
echo "================================"
echo "----------------"
bash scripts/fix-datetime.sh

# 把  http:// 改 https://  怕有些防火牆會擋
sed -i 's|http://|https://|g' /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list 2>/dev/null
apt update -y
apt install -y iputils-ping net-tools 


echo "=== Installer 完成 ==="
