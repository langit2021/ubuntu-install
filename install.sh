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
TMP_DIR=$(mktemp -d)

cleanup() {
    rm -rf "$TMP_DIR"
}

trap cleanup EXIT

curl -L  https://github.com/langit2021/ubuntu-install/archive/refs/heads/main.tar.gz \
    -o "$TMP_DIR/install.tar.gz"

tar -xzf "$TMP_DIR/install.tar.gz" -C "$TMP_DIR"
PROJECT_DIR="$TMP_DIR/ubuntu-install-main"
bash "$PROJECT_DIR/scripts/fix-datetime.sh"

# 把  http:// 改 https://  怕有些防火牆會擋
sed -i 's|http://|https://|g' /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list 2>/dev/null
apt update -y
apt install -y iputils-ping net-tools 


echo "=== Installer 完成 ==="
