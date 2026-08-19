#!/usr/bin/env bash

# ============================================================
# Ubuntu Web Server Installer
# Version: 0.3
# Target: Ubuntu Server 24.04 LTS
#
# Phase 1:
#   - Basic system packages & timezone fix
#   - Apache + PHP 8.3 + MariaDB + phpMyAdmin
#   - Centralized /data structure (www, mysql, logs/apache, logs/php)
#   - Maintenance user (op) & random password generation
#   - Self-signed HTTPS & /my_config info page
# ============================================================

set -e

# ------------------------------------------------------------
# 1. 時間同步與日誌準備
# ------------------------------------------------------------
echo "=== 設定系統時區為 Asia/Taipei ==="
timedatectl set-timezone Asia/Taipei || true
echo "=== 透過 HTTP 標頭強制同步時間 ==="
HTTP_DATE=$(curl -sI https://google.com | grep -i '^date:' | tr -d '\r' | cut -d' ' -f2-)
if [ -n "$HTTP_DATE" ]; then
    date -u -s "$HTTP_DATE"
    timedatectl set-local-rtc 0 2>/dev/null || true
    echo "時間同步成功！當前系統時間: $(date)"
fi

GIT_ACCOUNT=langit2021
GIT_PROJECT=ubuntu-install

START_TIME=$(date '+%Y%m%d_%H%M')
START_SEC=$(date +%s)
LOG_FILE="$(pwd)/install_${START_TIME}.log"

exec > >(tee -a "$LOG_FILE") 2>&1
echo "=============================================="
echo " Installation Log"
echo " Started: $(date '+%Y-%m-%d %H:%M:%S')"
echo " Log: ${LOG_FILE}"
echo "=============================================="
echo

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

VERSION="0.3"
DATA_DIR="/data"
WEB_ROOT="${DATA_DIR}/www"
MYSQL_DIR="${DATA_DIR}/mysql"
LOG_APACHE="${DATA_DIR}/logs/apache"
LOG_PHP="${DATA_DIR}/logs/php"
CONFIG_DIR="${WEB_ROOT}/my_config"
SSL_DIR="/etc/apache2/ssl"

echo "=============================================="
echo " Ubuntu Web Server Installer"
echo " Version: ${VERSION}"
echo " Target : Ubuntu Server 24.04 LTS"
echo "=============================================="
echo

# ------------------------------------------------------------
# 2. 系統環境檢查
# ------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Please run this script as root."
    exit 1
fi

if [ ! -f /etc/os-release ]; then
    echo "ERROR: Cannot detect operating system."
    exit 1
fi

source /etc/os-release

if [ "$ID" != "ubuntu" ] || [ "$VERSION_ID" != "24.04" ]; then
    echo "ERROR: This script requires Ubuntu 24.04 LTS."
    exit 1
fi

echo "[OK] Ubuntu ${VERSION_ID}"
echo

# ------------------------------------------------------------
# 3. 建立 /data 集中化目錄結構
# ------------------------------------------------------------
echo "==> Creating /data directory structure..."
mkdir -p "${WEB_ROOT}"
mkdir -p "${MYSQL_DIR}"
mkdir -p "${LOG_APACHE}"
mkdir -p "${LOG_PHP}"
mkdir -p "${DATA_DIR}/backup"
mkdir -p "${DATA_DIR}/my_config"
echo "[OK] Directory structure created"
echo

# ------------------------------------------------------------
# 4. 更新套件源與安裝基礎工具
# ------------------------------------------------------------
echo "==> Updating package information and installing base packages..."
sed -i 's|http://|https://|g' /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list 2>/dev/null
apt-get update
apt-get install -y \
    iputils-ping \
    net-tools \
    git \
    unzip \
    zip \
    vim \
    ca-certificates \
    openssl \
    lsb-release \
    software-properties-common \
    apt-transport-https \
    rsync

echo "[OK] Base packages installed"
echo

# ------------------------------------------------------------
# 5. 安裝 Apache
# ------------------------------------------------------------
echo "==> Installing Apache..."
apt-get install -y apache2
systemctl enable apache2
systemctl start apache2
echo "[OK] Apache installed"
echo

# ------------------------------------------------------------
# 6. 安裝與設定 PHP 8.3
# ------------------------------------------------------------
echo "==> Installing PHP 8.3 and configuring logs/timezone..."
apt-get install -y \
    php8.3 \
    libapache2-mod-php8.3 \
    php8.3-cli \
    php8.3-common \
    php8.3-mysql \
    php8.3-curl \
    php8.3-gd \
    php8.3-mbstring \
    php8.3-xml \
    php8.3-zip \
    php8.3-bcmath \
    php8.3-intl

a2enmod php8.3

# 配置 PHP Log 存放於 /data/logs/php/
sed -i "s|;error_log = php_errors.log|error_log = ${LOG_PHP}/php_errors.log|g" /etc/php/8.3/apache2/php.ini
sed -i "s|;error_log = php_errors.log|error_log = ${LOG_PHP}/php_errors.log|g" /etc/php/8.3/cli/php.ini
touch "${LOG_PHP}/php_errors.log"

# 配置 PHP 時區為 Asia/Taipei
sed -i "s|;date.timezone =|date.timezone = Asia/Taipei|g" /etc/php/8.3/apache2/php.ini
sed -i "s|;date.timezone =|date.timezone = Asia/Taipei|g" /etc/php/8.3/cli/php.ini

systemctl restart apache2
echo "[OK] PHP 8.3 installed, logs and timezone configured"
echo

# ------------------------------------------------------------
# 7. 建立維護帳號 (op) 與產出隨機密碼
# ------------------------------------------------------------
echo "==> Creating maintenance user (op) and generating credentials..."

#OP_PASS=$(openssl rand -base64 12 | tr -d '/+' | cut -c1-16)
#MYSQL_ROOT_PASS=$(openssl rand -base64 12 | tr -d '/+' | cut -c1-16)
# 測試階段固定密碼 (預計於 PHP 階段調整為動態管理)
OP_PASS="KXP1AEEuAsaqDWn"
MYSQL_ROOT_PASS="KXP1AEEuAsaqDWn"
PMA_PASS=$(openssl rand -base64 12 | tr -d '/+' | cut -c1-16)

if ! id "op" &>/dev/null; then
    useradd -m -s /bin/bash op
fi
echo "op:${OP_PASS}" | chpasswd
usermod -aG www-data op

# 在 /home/op 建立快捷軟連結 (SFTP 登入即可直達)
ln -sfn "${WEB_ROOT}" /home/op/www
ln -sfn "${DATA_DIR}/backup" /home/op/backup
chown -h op:op /home/op/www /home/op/backup

# 設定 SSH 終端機登入時預設自動進入 /data/www
if ! grep -q "cd /data/www" /home/op/.bashrc 2>/dev/null; then
    echo "cd /data/www" >> /home/op/.bashrc
fi

echo "[OK] Maintenance user created with shortcuts (www, backup)"
echo

# ------------------------------------------------------------
# 8. 安裝 MariaDB 並移轉資料目錄至 /data/mysql
# ------------------------------------------------------------
echo "==> Installing MariaDB & migrating datadir to /data/mysql..."
apt-get install -y mariadb-server mariadb-client
systemctl enable mariadb

# 停止服務進行目錄轉移
systemctl stop mariadb
if [ -d "/var/lib/mysql" ] && [ ! -f "${MYSQL_DIR}/ibdata1" ]; then
    rsync -av /var/lib/mysql/ "${MYSQL_DIR}/"
fi
sed -i "s|datadir\s*=\s*/var/lib/mysql|datadir = ${MYSQL_DIR}|g" /etc/mysql/mariadb.conf.d/50-server.cnf
chown -R mysql:mysql "${MYSQL_DIR}"
systemctl start mariadb

echo "[OK] MariaDB installed and relocated to /data/mysql"
echo

# ------------------------------------------------------------
# 9. 安裝 phpMyAdmin 與安全性設定
# ------------------------------------------------------------
echo "==> Installing and configuring phpMyAdmin..."
echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2" | debconf-set-selections
apt-get install -y phpmyadmin

# 啟用 phpMyAdmin 官方提供的 Apache Alias 設定檔
a2enconf phpmyadmin

# 設定 phpMyAdmin 允許 root 密碼登入
if [ -f /etc/phpmyadmin/config.inc.php ]; then
    if ! grep -q "AllowRoot" /etc/phpmyadmin/config.inc.php; then
        echo "\$cfg['Servers'][\$i]['AllowRoot'] = TRUE;" >> /etc/phpmyadmin/config.inc.php
    fi
fi

# 1. 重設 MariaDB root 與 phpmyadmin 控制帳號
# 使用 alter user 與 flush privileges 確保權限即時生效
sudo mysql <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASS}';
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';

CREATE DATABASE IF NOT EXISTS phpmyadmin;
CREATE USER IF NOT EXISTS 'phpmyadmin'@'localhost' IDENTIFIED BY '${PMA_PASS}';
ALTER USER 'phpmyadmin'@'localhost' IDENTIFIED BY '${PMA_PASS}';
GRANT ALL PRIVILEGES ON phpmyadmin.* TO 'phpmyadmin'@'localhost';

FLUSH PRIVILEGES;
EOF

# 2. 匯入 phpMyAdmin 基礎資料表
if [ -f /usr/share/phpmyadmin/sql/create_tables.sql ]; then
    mysql -u root -p"${MYSQL_ROOT_PASS}" phpmyadmin < /usr/share/phpmyadmin/sql/create_tables.sql 2>/dev/null || true
fi

# 3. 強制同步寫入 config-db.php 檔，確保密碼一致
cat > /etc/phpmyadmin/config-db.php <<EOF
<?php
\$dbuser='phpmyadmin';
\$dbpass='${PMA_PASS}';
\$basepath='';
\$dbname='phpmyadmin';
\$dbserver='localhost';
\$dbport='3306';
\$dbtype='mysql';
EOF

chmod 660 /etc/phpmyadmin/config-db.php
chown root:www-data /etc/phpmyadmin/config-db.php

echo "[OK] phpMyAdmin configured successfully"
echo
# ------------------------------------------------------------
# 10. 配置 SSL 憑證與 Apache VirtualHost
# ------------------------------------------------------------
echo "==> Configuring Apache SSL and VirtualHost..."
a2enmod ssl rewrite headers
mkdir -p "${SSL_DIR}"

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "${SSL_DIR}/server.key" \
    -out "${SSL_DIR}/server.crt" \
    -subj "/C=TW/ST=Taiwan/L=Taipei/O=WebServer/OU=IT/CN=$(hostname)"

chmod 600 "${SSL_DIR}/server.key"
chmod 644 "${SSL_DIR}/server.crt"

# VirtualHost 組態：加上 /my_config Alias 別名
cat > /etc/apache2/sites-available/webserver-ssl.conf <<EOF
<VirtualHost *:443>
    ServerName localhost
    DocumentRoot ${WEB_ROOT}
    DirectoryIndex index.php index.html

    SSLEngine on
    SSLCertificateFile ${SSL_DIR}/server.crt
    SSLCertificateKeyFile ${SSL_DIR}/server.key

    # 主網頁目錄權限
    <Directory ${WEB_ROOT}>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    # 虛擬目錄：my_config 對應至 /data/my_config
    Alias /my_config ${DATA_DIR}/my_config
    <Directory ${DATA_DIR}/my_config>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog ${LOG_APACHE}/error.log
    CustomLog ${LOG_APACHE}/access.log combined
</VirtualHost>
EOF

cat > /etc/apache2/sites-available/redirect-ssl.conf <<EOF
<VirtualHost *:80>
    ServerName localhost
    Redirect permanent / https://localhost/
</VirtualHost>
EOF

a2ensite redirect-ssl.conf
a2dissite 000-default.conf 2>/dev/null || true
a2dissite default-ssl.conf 2>/dev/null || true
a2ensite webserver-ssl.conf

SERVER_HOSTNAME=$(hostname)
echo "ServerName ${SERVER_HOSTNAME}" > /etc/apache2/conf-available/servername.conf
a2enconf servername

echo "[OK] Apache VirtualHost and Aliases configured"
echo

# ------------------------------------------------------------
# 11. 部署測試頁面與自動取得 my_config.sh
# ------------------------------------------------------------
echo "==> Creating test page and getting my_config.sh..."

# 1. 部署首頁
cat > "${WEB_ROOT}/index.php" <<'EOF'
<!DOCTYPE html>
<html lang="zh-TW">
<head>
    <meta charset="UTF-8">
    <style>
        .top-bar { background: #333; color: #fff; padding: 10px 20px; font-family: Arial, sans-serif; }
        .top-bar a { color: #5bc0de; text-decoration: none; font-weight: bold; }
        .top-bar a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <div class="top-bar">
        🚀 Web Server 測試頁面 | <a href="/my_config/">👉 前往系統組態控制台 (/my_config)</a>
    </div>
    <?php phpinfo(); ?>
</body>
</html>
EOF

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MY_CONFIG_FILE="${SCRIPT_DIR}/my_config.sh"

# 2. 若本地不存在 my_config.sh，則自動從 Git 儲存庫下載 (請替換為您的 Git Raw 網址)
GIT_RAW_URL="https://raw.githubusercontent.com/${GIT_ACCOUNT}/${GIT_PROJECT}/main/my_config.sh"

if [ ! -f "${MY_CONFIG_FILE}" ]; then
    echo "==> my_config.sh not found locally, downloading from Git..."
    curl -sSL "${GIT_RAW_URL}" -o "${MY_CONFIG_FILE}" || wget -q "${GIT_RAW_URL}" -O "${MY_CONFIG_FILE}"
fi

# 3. 執行 my_config.sh
if [ -f "${MY_CONFIG_FILE}" ]; then
    chmod +x "${MY_CONFIG_FILE}"
    OP_PASS="${OP_PASS}" MYSQL_ROOT_PASS="${MYSQL_ROOT_PASS}" "${MY_CONFIG_FILE}"
else
    echo "ERROR: Failed to obtain my_config.sh, skipping config page deployment."
fi

echo "[OK] Test page & external my_config script execution completed"
echo

# ------------------------------------------------------------
# 12. 設定目錄權限與重啟服務
# ------------------------------------------------------------
echo "==> Setting permissions & restarting services..."

# 網頁目錄：op 擁有，www-data 群組，設定 g+s 確保未來新檔自動繼承群組
chown -R op:www-data "${WEB_ROOT}"
chmod -R 775 "${WEB_ROOT}"
find "${WEB_ROOT}" -type d -exec chmod g+s {} +

# 資料庫目錄：mysql 專屬
chown -R mysql:mysql "${MYSQL_DIR}"
chmod -R 770 "${MYSQL_DIR}"

# 備份目錄：root 擁有，op 群組可讀取下載
chown -R root:op "${DATA_DIR}/backup"
chmod -R 775 "${DATA_DIR}/backup"

# Log 目錄：www-data 寫入權限
chown -R www-data:www-data "${DATA_DIR}/logs"
chmod -R 775 "${DATA_DIR}/logs"

apache2ctl configtest
systemctl restart apache2
systemctl restart mariadb

echo "[OK] Services restarted successfully"
echo
# ------------------------------------------------------------
# 13. 建立自動備份腳本與 Cron 排程
# ------------------------------------------------------------
echo "==> Setting up daily automated backup at 03:00..."

cat > /usr/local/bin/backup_www.sh <<'EOF'
#!/usr/bin/env bash
set -e

BACKUP_DIR="/data/backup"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TARGET_FILE="${BACKUP_DIR}/www_backup_${TIMESTAMP}.tar.gz"

mkdir -p "${BACKUP_DIR}"

# 備份 /data/www 目錄
tar -czf "${TARGET_FILE}" -C /data www

# 清除超過 7 天的歷史備份
find "${BACKUP_DIR}" -type f -name "www_backup_*.tar.gz" -mtime +7 -delete
EOF

chmod +x /usr/local/bin/backup_www.sh

# 設定 Cron 排程：每日 03:00 執行
(crontab -l 2>/dev/null | grep -v "/usr/local/bin/backup_www.sh"; echo "0 3 * * * /usr/local/bin/backup_www.sh") | crontab -

echo "[OK] Daily backup job set for 03:00 AM"
# ------------------------------------------------------------
# 14. 計算耗時並輸出終端資訊
# ------------------------------------------------------------
END_SEC=$(date +%s)
ELAPSED_SEC=$((END_SEC - START_SEC))
MINUTES=$((ELAPSED_SEC / 60))
SECONDS=$((ELAPSED_SEC % 60))

SERVER_IP=$(hostname -I | awk '{print $1}')

echo "=============================================="
echo " 安裝完成！(Installation Completed)"
echo " 總耗時：${MINUTES} 分 ${SECONDS} 秒"
echo "=============================================="
echo
echo "HTTP 網址:       http://${SERVER_IP}/"
echo "HTTPS 網址:      https://${SERVER_IP}/"
echo "控制台 (/my_config): https://${SERVER_IP}/my_config/"
echo "phpMyAdmin:        https://${SERVER_IP}/phpmyadmin/"
echo 
echo "系統維護帳號 (SSH / SFTP):"
echo "  帳號: op"
echo "  密碼: ${OP_PASS}"
echo
echo "MariaDB Root 憑證:"
echo "  帳號: root"
echo "  密碼: ${MYSQL_ROOT_PASS}"
echo "=============================================="