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

OP_PASS=$(openssl rand -base64 12 | tr -d '/+' | cut -c1-16)
MYSQL_ROOT_PASS=$(openssl rand -base64 12 | tr -d '/+' | cut -c1-16)
PMA_PASS=$(openssl rand -base64 12 | tr -d '/+' | cut -c1-16)

if ! id "op" &>/dev/null; then
    useradd -m -s /bin/bash op
fi
echo "op:${OP_PASS}" | chpasswd
usermod -aG www-data op

echo "[OK] Maintenance user created"
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
echo "==> Installing phpMyAdmin..."
echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2" | debconf-set-selections
apt-get install -y phpmyadmin

# 建立軟連結至網頁根目錄
if [ -d /usr/share/phpmyadmin ]; then
    ln -sfn /usr/share/phpmyadmin "${WEB_ROOT}/phpmyadmin"
fi

# 設定 phpMyAdmin 允許 root 密碼登入
if [ -f /etc/phpmyadmin/config.inc.php ]; then
    if ! grep -q "AllowRoot" /etc/phpmyadmin/config.inc.php; then
        echo "\$cfg['Servers'][\$i]['AllowRoot'] = TRUE;" >> /etc/phpmyadmin/config.inc.php
    fi
fi

# 初始化 MariaDB 帳號與權限 (已修正 MariaDB 語法)
sudo mysql <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASS}';
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';

CREATE DATABASE IF NOT EXISTS phpmyadmin;
CREATE USER IF NOT EXISTS 'phpmyadmin'@'localhost' IDENTIFIED BY '${PMA_PASS}';
GRANT ALL PRIVILEGES ON phpmyadmin.* TO 'phpmyadmin'@'localhost';

FLUSH PRIVILEGES;
EOF

if [ -f /usr/share/phpmyadmin/sql/create_tables.sql ]; then
    mysql -u root -p"${MYSQL_ROOT_PASS}" phpmyadmin < /usr/share/phpmyadmin/sql/create_tables.sql 2>/dev/null || true
fi

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

echo "[OK] phpMyAdmin configured"
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

# VirtualHost 組態指向 /data/www 及 /data/logs/apache/
cat > /etc/apache2/sites-available/webserver-ssl.conf <<EOF
<VirtualHost *:443>
    ServerName localhost
    DocumentRoot ${WEB_ROOT}
    DirectoryIndex index.php index.html

    SSLEngine on
    SSLCertificateFile ${SSL_DIR}/server.crt
    SSLCertificateKeyFile ${SSL_DIR}/server.key

    <Directory ${WEB_ROOT}>
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

echo "[OK] Apache VirtualHost configured"
echo

# ------------------------------------------------------------
# 11. 部署測試頁面與 /my_config 頁面
# ------------------------------------------------------------
echo "==> Creating test page and /my_config interface..."

# 部署首頁 (頂端帶有 /my_config 快捷連結)
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

# 部署 /my_config 頁面 (包含首頁按鈕與 PHP 上傳/記憶體參數)
mkdir -p "${CONFIG_DIR}"
cat > "${CONFIG_DIR}/index.php" <<EOF
<?php
?>
<!DOCTYPE html>
<html lang="zh-TW">
<head>
    <meta charset="UTF-8">
    <title>Ubuntu Web Server Configuration</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 30px; line-height: 1.6; }
        .credentials { background-color: #f8f9fa; border-left: 4px solid #007bff; padding: 12px; margin: 15px 0; }
        .nav-bar { margin-bottom: 20px; }
        .nav-bar a { display: inline-block; padding: 8px 16px; background-color: #28a745; color: white; text-decoration: none; border-radius: 4px; font-weight: bold; }
        .nav-bar a:hover { background-color: #218838; }
        code { font-weight: bold; color: #d9534f; background: #eee; padding: 2px 6px; border-radius: 4px; }
    </style>
</head>
<body>

<div class="nav-bar">
    <a href="/">🏠 返回網站首頁</a>
</div>

<h1>Ubuntu Web Server 系統組態資訊</h1>
<p>第一階段自動化部署已完成。</p>

<hr>

<h2>系統維護帳號 (SFTP / SSH)</h2>
<div class="credentials">
    <p><strong>帳號：</strong> <code>op</code></p>
    <p><strong>密碼：</strong> <code>${OP_PASS}</code></p>
</div>

<h2>資料庫管理帳號 (MariaDB)</h2>
<div class="credentials">
    <p><strong>帳號：</strong> <code>root</code></p>
    <p><strong>密碼：</strong> <code>${MYSQL_ROOT_PASS}</code></p>
</div>

<hr>

<h2>PHP 關鍵效能與資源參數</h2>
<ul>
    <li><strong>系統預設時區 (date.timezone)：</strong> <?php echo date_default_timezone_get(); ?></li>
    <li><strong>記憶體限制 (memory_limit)：</strong> <?php echo ini_get('memory_limit'); ?></li>
    <li><strong>單檔案上傳上限 (upload_max_filesize)：</strong> <?php echo ini_get('upload_max_filesize'); ?></li>
    <li><strong>POST 請求總量上限 (post_max_size)：</strong> <?php echo ini_get('post_max_size'); ?></li>
    <li><strong>腳本最長執行時間 (max_execution_time)：</strong> <?php echo ini_get('max_execution_time'); ?> 秒</li>
</ul>

<hr>

<h2>集中化目錄與服務狀態</h2>
<ul>
    <li>Ubuntu 版本：OK (24.04 LTS)</li>
    <li>Apache：OK</li>
    <li>PHP 版本：<?php echo PHP_VERSION; ?></li>
    <li>MariaDB：OK</li>
    <li>phpMyAdmin：Installed</li>
    <li>網頁目錄 (/data/www)：<?php echo is_dir('/data/www') ? 'OK' : 'ERROR'; ?></li>
    <li>資料庫目錄 (/data/mysql)：<?php echo is_dir('/data/mysql') ? 'OK' : 'ERROR'; ?></li>
    <li>Apache Log (/data/logs/apache)：<?php echo is_dir('/data/logs/apache') ? 'OK' : 'ERROR'; ?></li>
    <li>PHP Log (/data/logs/php)：<?php echo is_dir('/data/logs/php') ? 'OK' : 'ERROR'; ?></li>
</ul>

<hr>
<p>第二階段互動式控制台將於此頁面擴充。</p>

</body>
</html>
EOF

echo "[OK] Test page & my_config created"
echo

# ------------------------------------------------------------
# 12. 設定目錄權限與重啟服務
# ------------------------------------------------------------
echo "==> Setting permissions & restarting services..."

chown -R op:www-data "${WEB_ROOT}"
chmod -R 775 "${WEB_ROOT}"

chown -R mysql:mysql "${MYSQL_DIR}"
chmod -R 770 "${MYSQL_DIR}"

chown -R www-data:www-data "${DATA_DIR}/logs"
chmod -R 775 "${DATA_DIR}/logs"

apache2ctl configtest
systemctl restart apache2
systemctl restart mariadb

echo "[OK] Services restarted successfully"
echo

# ------------------------------------------------------------
# 13. 計算耗時並輸出終端資訊
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