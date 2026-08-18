#!/bin/bash

echo "================================"
echo " Ubuntu Install Framework"
echo " Version 0.1"
echo " curl -sL https://raw.githubusercontent.com/langit2021/ubuntu-install/main/install.sh | bash   "
echo "================================"

echo "Hello World  pc 2.0"



sudo systemctl restart systemd-timesyncd
sudo timedatectl set-timezone Asia/Taipei
# 把  http:// 改 https://  怕有些防火牆會擋
sudo sed -i 's|http://|https://|g' /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list 2>/dev/null
sudo apt update -y
sudo apt install -y iputils-ping net-tools 
