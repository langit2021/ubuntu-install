#!/usr/bin/env bash

# ============================================================
# Ubuntu Web Server Installer
# Version: 0.2 (All data configured under /data)
# Target: Ubuntu Server 24.04 LTS
# ============================================================

set -e

echo "=== 設定系統時區為 Asia/Taipei ==="
timedatectl set-timezone Asia/Taipei || true
echo "=== 透過 HTTP 標頭強制同步時間（繞過 NTP 防火牆限制）==="
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
export NEEDRESTART_MODE=a 

sed -i 's|http://|https://|g' /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list 2>/dev/null
apt install -y iputils-ping net-tools 

#=======================================================================
VERSION="0.2"
DATA_DIR="/data"
WEB_ROOT="${DATA_DIR}/www"
LOG_DIR="${DATA_DIR}/logs"
DB_DIR="${DATA_DIR}/database"
CONFIG_DIR="${WEB_ROOT}/my_config"
SSL_DIR="/etc/apache2/ssl"

echo "=============================================="
echo " Ubuntu Web Server Installer"
echo " Version: ${VERSION}"
echo " Target : Ubuntu Server 24.04 LTS"
echo "=============================================="
echo

# ------------------------------------------------------------
# 1. Check root & System
# ------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Please run this script as root."
    exit 1
fi

source /etc/os-release
if [ "$ID" != "ubuntu" ] || [ "$VERSION_ID" != "24.04" ]; then
    echo "ERROR: This script requires Ubuntu 24.04."
    exit 1
fi

# ------------------------------------------------------------
# 2. Update & Install basic packages
# ------------------------------------------------------------
apt-get update
apt-get install -y \
    git unzip zip vim ca-certificates openssl lsb-release \
    software-properties-common apt-transport-https apache2 mariadb-server mariadb-client

# ------------------------------------------------------------
# 3. Create /data structure & Set Permissions Early
# ------------------------------------------------------------
echo "==> Creating /data structure..."
mkdir -p "${WEB_ROOT}"
mkdir -p "${DB_DIR}"
mkdir -p "${LOG_DIR}/apache2"
mkdir -p "${DATA_DIR}/backup"

# ------------------------------------------------------------
# 4. Configure MariaDB Datadir (/data/database)
# ------------------------------------------------------------
echo "==> Configuring MariaDB to use ${DB_DIR}..."

systemctl stop mariadb

# 複製預設資料庫架構至 /data/database (若尚未初始化)
if [ -d "/var/lib/mysql/mysql" ] && [ ! -d "${DB_DIR}/mysql" ]; then
    cp -R /var/lib/mysql/* "${DB_DIR}/"
fi

chown -R mysql:mysql "${DB_DIR}"

# 修改 MariaDB 設定檔中的 datadir
sed -i "s|^datadir\s*=.*|datadir = ${DB_DIR}|g" /etc/mysql/mariadb.conf.d/50-server.cnf

systemctl start mariadb

# --- 4.1 Secure MariaDB & Generate Root Password ---
echo "==> Securing MariaDB & setting root password..."
MYSQL_ROOT_PASS=$(openssl rand -base64 12 | tr -d '/+' | cut -c1-16)

mariadb -e "ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('${MYSQL_ROOT_PASS}');"
mariadb -e "DELETE FROM mysql.user WHERE User='';"
mariadb -e "DROP DATABASE IF EXISTS test;"
mariadb -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
mariadb -e "FLUSH PRIVILEGES;"

echo "[OK] MariaDB data moved to ${DB_DIR} & Secured."
echo

# ------------------------------------------------------------
# 5. Install PHP 8.3
# ------------------------------------------------------------
echo "==> Installing PHP 8.3..."
apt-get install -y \
    php8.3 libapache2-mod-php8.3 php8.3-cli php8.3-common \
    php8.3-mysql php8.3-curl php8.3-gd php8.3-mbstring \
    php8.3-xml php8.3-zip php8.3-bcmath php8.3-intl

a2enmod php8.3

# ------------------------------------------------------------
# 6. Install phpMyAdmin
# ------------------------------------------------------------
echo "==> Installing phpMyAdmin..."
echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
echo "phpmyadmin phpmyadmin/app-password-confirm password " | debconf-set-selections
echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2" | debconf-set-selections

apt-get install -y phpmyadmin

if [ -d /usr/share/phpmyadmin ]; then
    ln -sf /usr/share/phpmyadmin "${WEB_ROOT}/phpmyadmin"
fi

# ------------------------------------------------------------
# 7. Create basic PHP test page
# ------------------------------------------------------------
# 刪除系統預設頁面，確保寫入 /data/www/index.php
rm -f /var/www/html/index.html

cat > "${WEB_ROOT}/index.php" <<'EOF'
<?php
phpinfo();
?>
EOF

# ------------------------------------------------------------
# 8. Enable Apache SSL & Configure VirtualHost
# ------------------------------------------------------------
echo "==> Enabling Apache SSL and redirect..."
a2enmod ssl rewrite headers

mkdir -p "${SSL_DIR}"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "${SSL_DIR}/server.key" \
    -out "${SSL_DIR}/server.crt" \
    -subj "/C=TW/ST=Taiwan/L=Taipei/O=WebServer/OU=IT/CN=$(hostname)"

chmod 600 "${SSL_DIR}/server.key"
chmod 644 "${SSL_DIR}/server.crt"

# 設定 443 埠 (HTTPS) 站點
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

    # Log 檔案指向 /data/logs/apache2
    ErrorLog ${LOG_DIR}/apache2/error.log
    CustomLog ${LOG_DIR}/apache2/access.log combined
</VirtualHost>
EOF

# 設定 80 埠 (HTTP) 強制轉址到 HTTPS
cat > /etc/apache2/sites-available/redirect-ssl.conf <<EOF
<VirtualHost *:80>
    ServerName localhost
    Redirect permanent / https://localhost/
</VirtualHost>
EOF

a2dissite 000-default.conf default-ssl.conf 2>/dev/null || true
a2ensite webserver-ssl.conf redirect-ssl.conf

# ------------------------------------------------------------
# 9. Create my_config Page
# ------------------------------------------------------------
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
        body { font-family: Arial, sans-serif; margin: 30px; }
        .credentials { background-color: #f8f9fa; border-left: 4px solid #07a; padding: 15px; margin: 15px 0; }
        code { font-weight: bold; color: #d9534f; font-size: 1.1em; }
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

<h2>System Status</h2>
<ul>
    <li>Ubuntu: OK</li>
    <li>Apache: OK</li>
    <li>PHP: <?php echo PHP_VERSION; ?></li>
    <li>MariaDB: Installed</li>
    <li>phpMyAdmin: Installed</li>
    <li>/data Status: <?php echo is_dir('/data') ? 'OK' : 'ERROR'; ?></li>
    <li>Web Root: <code>${WEB_ROOT}</code></li>
    <li>DB Data Dir: <code>${DB_DIR}</code></li>
    <li>Log Dir: <code>${LOG_DIR}</code></li>
</ul>

<hr>
<p>Phase 2 configuration wizard will be installed here.</p>

</body>
</html>
EOF

# ------------------------------------------------------------
# 10. Set Permissions & Global Conf
# ------------------------------------------------------------
echo "==> Setting permissions..."
chown -R www-data:www-data "${WEB_ROOT}"
chmod -R 755 "${WEB_ROOT}"

chown -R www-data:adm "${LOG_DIR}/apache2"
chmod -R 755 "${DATA_DIR}"

SERVER_HOSTNAME=$(hostname)
echo "ServerName ${SERVER_HOSTNAME}" > /etc/apache2/conf-available/servername.conf
a2enconf servername

# ------------------------------------------------------------
# 11. Testing & Restart Services
# ------------------------------------------------------------
echo "==> Testing configuration and restarting services..."
apache2ctl configtest

systemctl restart apache2
systemctl restart mariadb

# ------------------------------------------------------------
# 12. Final Output
# ------------------------------------------------------------
SERVER_IP=$(hostname -I | awk '{print $1}')

echo "=============================================="
echo " Installation completed successfully!"
echo "=============================================="
echo
echo "MariaDB Root Credentials:"
echo "  Username: root"
echo "  Password: ${MYSQL_ROOT_PASS}"
echo
echo "Data Storage paths:"
echo "  Web Root : ${WEB_ROOT}"
echo "  Database : ${DB_DIR}"
echo "  Logs     : ${LOG_DIR}"
echo
echo "URL Access:"
echo "  HTTP Access (Auto Redirect): http://${SERVER_IP}/"
echo "  HTTPS Home Page            : https://${SERVER_IP}/"
echo "  Configuration Page         : https://${SERVER_IP}/my_config/"
echo "  phpMyAdmin                 : https://${SERVER_IP}/phpmyadmin/"
echo
echo "=============================================="