#!/bin/bash

echo "================================"
echo " Ubuntu Install Framework"
echo " Version 0.1"
echo " curl -sL https://raw.githubusercontent.com/langit2021/ubuntu-install/main/install.sh | bash   "
echo "================================"

echo "Hello World  pc 2.0"



#!/usr/bin/env bash
set -e

echo "=== [1/5] 設定系統時區為 Asia/Taipei ==="
timedatectl set-timezone Asia/Taipei || true

echo "=== [2/5] 透過 HTTP 標頭強制同步時間（繞過 NTP 防火牆限制）==="
# 使用 tlsdate 或 curl 取得伺服器 Date Header，直接寫入系統時間
HTTP_DATE=$(curl -sI https://google.com | grep -i '^date:' | cut -d' ' -f2-)
if [ -n "$HTTP_DATE" ]; then
    date -s "$HTTP_DATE"
    hwclock --systohc
    echo "時間同步成功！當前系統時間: $(date)"
else
    echo "警告: 無法讀取 HTTP 時間，跳過時間強制校正。"
fi

echo "=== [3/5] 設定公共 DNS (8.8.8.8) ==="
echo "nameserver 8.8.8.8" | tee /etc/resolv.conf > /dev/null

echo "=== [4/5] 將 APT 來源切換為 HTTPS 通道 ==="
sed -i 's|http://|https://|g' /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list 2>/dev/null || true

echo "=== [5/5] 清除舊 APT 快取並執行更新 ==="
rm -rf /var/lib/apt/lists/*
apt-get update

echo "=== [完成] 安裝基礎網路工具 (ping, curl, net-tools) ==="
apt-get install -y iputils-ping net-tools curl wget

echo "系統已修復完畢，時間與 APT 源皆已正常運作！"



sudo systemctl restart systemd-timesyncd
sudo timedatectl set-timezone Asia/Taipei
# 把  http:// 改 https://  怕有些防火牆會擋
sudo sed -i 's|http://|https://|g' /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list 2>/dev/null
sudo apt update -y
sudo apt install -y iputils-ping net-tools 
