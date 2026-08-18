#!/usr/bin/env bash
set -e
echo "================================"
echo " Fix date time"



#set -e

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