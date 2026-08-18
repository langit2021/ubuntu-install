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
echo " Fix date time"
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

echo "================================"

# 把  http:// 改 https://  怕有些防火牆會擋
sed -i 's|http://|https://|g' /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list 2>/dev/null
apt update -y
apt install -y iputils-ping net-tools 


echo "=== Installer 完成 ==="
