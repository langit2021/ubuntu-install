#!/usr/bin/env bash

# ============================================================
# Ubuntu Web Server Installer
# Version: 0.1
# Target: Ubuntu Server 24.04 LTS
#
# Phase 1:
#   - Basic system packages
#   - Apache
#   - PHP 8.3
#   - MariaDB
#   - phpMyAdmin
#   - Git
#   - /data directory structure
#   - Self-signed HTTPS
#   - /my_config initial page
#
# Phase 2 will be handled by PHP Web Configurator
# ============================================================
# ------------------------------------------------------------
# Logging
# ------------------------------------------------------------




set -e

echo " Fix date time"
echo "=== 設定系統時區為 Asia/Taipei ==="
timedatectl set-timezone Asia/Taipei || true
echo "=== 透過 HTTP 標頭強制同步時間（繞過 NTP 防火牆限制）==="
# 使用 tlsdate 或 curl 取得伺服器 Date Header，直接寫入系統時間
HTTP_DATE=$(curl -sI https://google.com | grep -i '^date:' | tr -d '\r' | cut -d' ' -f2-)
if [ -n "$HTTP_DATE" ]; then
    date -u -s "$HTTP_DATE"
    timedatectl set-local-rtc 0 2>/dev/null || true
    echo "時間同步成功！當前系統時間: $(date)"
fi

START_TIME=$(date '+%Y%m%d_%H%M')
LOG_FILE="$(pwd)/install_${START_TIME}.log"

exec > >(tee -a "$LOG_FILE") 2>&1
echo "=============================================="
echo " Installation Log"
echo " Started: $(date '+%Y-%m-%d %H:%M:%S')"
echo " Log: ${LOG_FILE}"
echo "=============================================="
echo
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a # 自動重啟不受影響的服務，避免跳出紫底藍字的彈出選單
echo "================================"
echo " Ubuntu Install Framework"
echo " Version 0.12"
echo " curl -sL https://raw.githubusercontent.com/langit2021/ubuntu-install/main/install.sh | sudo bash"
echo "================================"
# 把  http:// 改 https://  怕有些防火牆會擋
sed -i 's|http://|https://|g' /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list 2>/dev/null

apt install -y iputils-ping net-tools 


#=======================================================================
VERSION="0.1"
DATA_DIR="/data"
WEB_ROOT="/var/www/html"
CONFIG_DIR="${WEB_ROOT}/my_config"
SSL_DIR="/etc/apache2/ssl"

echo "=============================================="
echo " Ubuntu Web Server Installer"
echo " Version: ${VERSION}"
echo " Target : Ubuntu Server 24.04 LTS"
echo "=============================================="
echo

# ------------------------------------------------------------
# 1. Check root
# ------------------------------------------------------------

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Please run this script as root."
    exit 1
fi

# ------------------------------------------------------------
# 2. Check Ubuntu version
# ------------------------------------------------------------

if [ ! -f /etc/os-release ]; then
    echo "ERROR: Cannot detect operating system."
    exit 1
fi

source /etc/os-release

if [ "$ID" != "ubuntu" ]; then
    echo "ERROR: This script only supports Ubuntu."
    exit 1
fi

if [ "$VERSION_ID" != "24.04" ]; then
    echo "ERROR: This script requires Ubuntu 24.04."
    echo "Detected: Ubuntu ${VERSION_ID}"
    exit 1
fi

echo "[OK] Ubuntu ${VERSION_ID}"
echo

# ------------------------------------------------------------
# 3. Update package information
# ------------------------------------------------------------

echo "==> Updating package information..."

apt-get update

echo "[OK] apt update"
echo

# ------------------------------------------------------------
# 4. Install basic packages
# ------------------------------------------------------------

echo "==> Installing basic packages..."

apt-get install -y \
    git \
    unzip \
    zip \
    vim \
    ca-certificates \
    openssl \
    lsb-release \
    software-properties-common \
    apt-transport-https

echo "[OK] Basic packages installed"
echo

# ------------------------------------------------------------
# 5. Install Apache
# ------------------------------------------------------------

echo "==> Installing Apache..."

apt-get install -y apache2

systemctl enable apache2
systemctl start apache2

echo "[OK] Apache installed"
echo

# ------------------------------------------------------------
# 6. Install PHP 8.3
# ------------------------------------------------------------

echo "==> Installing PHP..."

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

systemctl restart apache2

echo "[OK] PHP 8.3 installed"
echo

# ------------------------------------------------------------
# 7. Install MariaDB
# ------------------------------------------------------------

echo "==> Installing MariaDB..."

apt-get install -y mariadb-server mariadb-client

systemctl enable mariadb
systemctl start mariadb

echo "[OK] MariaDB installed"
echo
# ------------------------------------------------------------
# 7.1 Secure MariaDB & Generate Root Password
# ------------------------------------------------------------

echo "==> Securing MariaDB & setting root password..."

# 自動生成 16 位高強度隨機密碼 (包含大小寫字母、數字)
MYSQL_ROOT_PASS=$(openssl rand -base64 12 | tr -d '/+' | cut -c1-16)

# 清除匿名使用者、刪除測試資料庫，並設定 root 密碼與切換密碼驗證模式
mariadb -e "ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('${MYSQL_ROOT_PASS}');"
mariadb -e "DELETE FROM mysql.user WHERE User='';"
mariadb -e "DROP DATABASE IF EXISTS test;"
mariadb -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
mariadb -e "FLUSH PRIVILEGES;"

echo "[OK] MariaDB secured. Root password generated."
echo
# ------------------------------------------------------------
# 8. Install phpMyAdmin
# ------------------------------------------------------------

echo "==> Installing phpMyAdmin..."

export DEBIAN_FRONTEND=noninteractive
echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
echo "phpmyadmin phpmyadmin/app-password-confirm password " | debconf-set-selections
echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2" | debconf-set-selections
apt-get install -y phpmyadmin

if [ -d /usr/share/phpmyadmin ]; then
    if [ ! -e /var/www/html/phpmyadmin ]; then
        ln -s /usr/share/phpmyadmin /var/www/html/phpmyadmin
    fi
fi

systemctl restart apache2

echo "[OK] phpMyAdmin installed"
echo

# ------------------------------------------------------------
# 9. Create /data structure
# ------------------------------------------------------------

echo "==> Creating /data structure..."

mkdir -p "${DATA_DIR}/www"
mkdir -p "${DATA_DIR}/database"
mkdir -p "${DATA_DIR}/logs"
mkdir -p "${DATA_DIR}/backup"

echo "[OK] /data structure created"
echo

# ------------------------------------------------------------
# 10. Create basic PHP test
# ------------------------------------------------------------

echo "==> Creating PHP test page... 安裝階段測試用"

cat > "${WEB_ROOT}/index.php" <<'EOF'
<?php
phpinfo();
?>
EOF

echo "[OK] PHP test page created"
echo

# ------------------------------------------------------------
# 11. Enable Apache SSL
# ------------------------------------------------------------

echo "==> Enabling Apache SSL..."

a2enmod ssl
a2enmod rewrite
a2enmod headers

mkdir -p "${SSL_DIR}"

# ------------------------------------------------------------
# 12. Create self-signed certificate
# ------------------------------------------------------------

echo "==> Creating self-signed certificate...  僅供第一階段初始用"

openssl req \
    -x509 \
    -nodes \
    -days 365 \
    -newkey rsa:2048 \
    -keyout "${SSL_DIR}/server.key" \
    -out "${SSL_DIR}/server.crt" \
    -subj "/C=TW/ST=Taiwan/L=Taipei/O=WebServer/OU=IT/CN=$(hostname)"

chmod 600 "${SSL_DIR}/server.key"
chmod 644 "${SSL_DIR}/server.crt"

echo "[OK] Self-signed certificate created"
echo

# ------------------------------------------------------------
# 13. Create basic HTTPS VirtualHost
# ------------------------------------------------------------

echo "==> Configuring HTTPS..."

cat > /etc/apache2/sites-available/webserver-ssl.conf <<EOF
<VirtualHost *:443>

    ServerName localhost

    DocumentRoot ${WEB_ROOT}

    SSLEngine on
    SSLCertificateFile ${SSL_DIR}/server.crt
    SSLCertificateKeyFile ${SSL_DIR}/server.key

    <Directory ${WEB_ROOT}>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/webserver-error.log
    CustomLog \${APACHE_LOG_DIR}/webserver-access.log combined

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

systemctl reload apache2

echo "[OK] HTTPS configured"
echo

# ------------------------------------------------------------
# 14. Create my_config
# ------------------------------------------------------------

echo "==> Creating my_config..."

mkdir -p "${CONFIG_DIR}"

cat > "${CONFIG_DIR}/index.php" <<EOF
<?php
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Ubuntu Web Server Configuration</title>
    <style>
        .credentials { background-color: #f8f9fa; border-left: 4px solid #07a; padding: 10px; margin: 15px 0; }
        code { font-weight: bold; color: #d9534f; }
    </style>
</head>

<body>

<h1>Ubuntu Web Server</h1>

<p>Base installation completed.</p>

<hr>

<h2>Database Credentials (MariaDB)</h2>
<div class="credentials">
    <p><strong>Username:</strong> <code>root</code></p>
    <p><strong>Password:</strong> <code>${MYSQL_ROOT_PASS}</code></p>
</div>

<hr>

<h2>System</h2>

<ul>
    <li>Ubuntu: OK</li>
    <li>Apache: OK</li>
    <li>PHP: <?php echo PHP_VERSION; ?></li>
    <li>MariaDB: Installed</li>
    <li>phpMyAdmin: Installed</li>
    <li>/data: <?php echo is_dir('/data') ? 'OK' : 'ERROR'; ?></li>
</ul>

<hr>

<p>Phase 2 configuration wizard will be installed here.</p>

</body>
</html>
EOF

echo "[OK] my_config created"
echo

# ------------------------------------------------------------
# 15. Set basic permissions
# ------------------------------------------------------------

echo "==> Setting basic permissions..."

chown -R www-data:www-data "${WEB_ROOT}"
chmod 755 "${WEB_ROOT}"

chmod 755 "${DATA_DIR}"
chmod 755 "${DATA_DIR}/www"
chmod 755 "${DATA_DIR}/database"
chmod 755 "${DATA_DIR}/logs"
chmod 755 "${DATA_DIR}/backup"

echo "[OK] Basic permissions configured"
echo


# ------------------------------------------------------------
# Set global Apache ServerName
# ------------------------------------------------------------

SERVER_HOSTNAME=$(hostname)

echo "ServerName ${SERVER_HOSTNAME}" > /etc/apache2/conf-available/servername.conf

a2enconf servername

# ------------------------------------------------------------
# 16. Apache configuration test
# ------------------------------------------------------------

echo "==> Testing Apache configuration..."

apache2ctl configtest

echo

# ------------------------------------------------------------
# 17. Restart services
# ------------------------------------------------------------

echo "==> Restarting services..."

systemctl restart apache2
systemctl restart mariadb

echo

# ------------------------------------------------------------
# 18. Final status
# ------------------------------------------------------------

echo "=============================================="
echo " Installation completed"
echo "=============================================="
echo

echo "Apache:"
systemctl is-active apache2

echo
echo "MariaDB:"
systemctl is-active mariadb

echo
echo "PHP:"
php -v | head -n 1

echo
echo "Data:"
ls -ld /data

# ------------------------------------------------------------
# Detect Server IP
# ------------------------------------------------------------

SERVER_IP=$(hostname -I | awk '{print $1}')

echo "=============================================="
echo " Next step .."
echo "=============================================="
echo
echo "HTTP:"
echo "  http://${SERVER_IP}/"
echo "HTTPS:"
echo "  https://${SERVER_IP}/"
echo "Configuration:"
echo "  https://${SERVER_IP}/my_config/"
echo
echo "phpMyAdmin:"
echo "  https://${SERVER_IP}/phpmyadmin/"
echo 
echo "MariaDB Root Credentials:"
echo "  Username: root"
echo "  Password: ${MYSQL_ROOT_PASS}"
echo "=============================================="

