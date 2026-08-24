#!/usr/bin/env bash

# ============================================================
# Ubuntu Web Server Installer
# Version: 0.4
# Target: Ubuntu Server 24.04 LTS
# ============================================================

set -e
# 重置腳本運行計時器
SECONDS=0
# ------------------------------------------------------------
# Checkpoint / 章節狀態檢查機制
# ------------------------------------------------------------
PROGRESS_FILE="/data/.install_progress"
mkdir -p /data

is_step_completed() {
    local step_name="$1"
    if [ -f "$PROGRESS_FILE" ] && grep -q "^${step_name}$" "$PROGRESS_FILE"; then
        return 0
    else
        return 1
    fi
}

mark_step_completed() {
    local step_name="$1"
    echo "$step_name" >> "$PROGRESS_FILE"
}

run_step() {
    local step_id="$1"
    local step_desc="$2"
    local step_func="$3"

    echo "------------------------------------------------------------"
    if is_step_completed "$step_id"; then
        echo "[SKIP] 章節 [${step_id}]: ${step_desc} (先前已成功執行，自動跳過)"
        echo
        return 0
    fi

    echo "==> [EXEC] 開始執行章節 [${step_id}]: ${step_desc}..."
    $step_func
    mark_step_completed "$step_id"
    echo "[OK] 章節 [${step_id}] 執行完成！"
    echo
}

# ------------------------------------------------------------
# 1. 時間同步與日誌準備
# ------------------------------------------------------------
step_timezone_and_log() {
    echo "=== 設定系統時區為 Asia/Taipei ==="
    timedatectl set-timezone Asia/Taipei || true
    echo "=== 透過 HTTP 標頭強制同步時間 ==="
    HTTP_DATE=$(curl -sI https://google.com | grep -i '^date:' | tr -d '\r' | cut -d' ' -f2-)
    if [ -n "$HTTP_DATE" ]; then
        date -u -s "$HTTP_DATE"
        timedatectl set-local-rtc 0 2>/dev/null || true
        echo "時間同步成功！當前系統時間: $(date)"
    fi
}

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

VERSION="0.4"
DATA_DIR="/data"
WEB_ROOT="${DATA_DIR}/www"
MYSQL_DIR="${DATA_DIR}/mysql"
LOG_APACHE="${DATA_DIR}/logs/apache"
LOG_PHP="${DATA_DIR}/logs/php"
CONFIG_DIR="${WEB_ROOT}/my_config"
SSL_DIR="/etc/apache2/ssl"

run_step "STEP_01_TIME" "時間同步與日誌初始化" step_timezone_and_log

# ------------------------------------------------------------
# 2. 系統環境檢查
# ------------------------------------------------------------
step_env_check() {
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
    echo "[OK] Ubuntu ${VERSION_ID} 環境驗證符合"
}

run_step "STEP_02_CHECK" "系統環境檢查" step_env_check

# ------------------------------------------------------------
# 3. 建立 /data 集中化目錄結構
# ------------------------------------------------------------
step_create_dirs() {
    mkdir -p "${WEB_ROOT}"
    mkdir -p "${MYSQL_DIR}"
    mkdir -p "${LOG_APACHE}"
    mkdir -p "${LOG_PHP}"
    mkdir -p "${DATA_DIR}/backup"
    mkdir -p "${DATA_DIR}/my_config"
}

run_step "STEP_03_DIRS" "建立 /data 集中化目錄結構" step_create_dirs

# ------------------------------------------------------------
# 4. 更新套件源與安裝基礎工具
# ------------------------------------------------------------
step_install_base() {
    echo "==> 檢查並等待系統背景更新 (unattended-upgr) 結束..."
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
        echo "系統背景正在更新中，等待 5 秒..."
        sleep 5
    done

    # 暫時停止自動更新服務，避免安裝中途再次搶鎖
    systemctl stop unattended-upgrades 2>/dev/null || true

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
        rsync \
        cron

    systemctl enable cron
    systemctl start cron
}

run_step "STEP_04_BASE" "更新套件源與安裝基礎工具" step_install_base

# ------------------------------------------------------------
# 5. 安裝 Apache
# ------------------------------------------------------------
step_install_apache() {
    apt-get install -y apache2
    systemctl enable apache2
    systemctl start apache2
}

run_step "STEP_05_APACHE" "安裝與啟動 Apache 服務" step_install_apache

# ------------------------------------------------------------
# 6. 安裝與設定 PHP 8.3
# ------------------------------------------------------------
step_install_php() {
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
}

run_step "STEP_06_PHP" "安裝與設定 PHP 8.3" step_install_php

# ------------------------------------------------------------
# 7. 建立維護帳號 (op) 與 SFTP / Samba 權限設定
# ------------------------------------------------------------
step_setup_op_user() {
    # 確保 OP_PASS 有預設值
    OP_PASS="${OP_PASS:-KXP1AEEuAsaqDWn}"

    # 建立 op 帳號
    if ! id "op" &>/dev/null; then
        useradd -d /data -s /bin/bash op
    else
        usermod -s /bin/bash op
    fi

    # 設定密碼並加入 www-data 群組
    echo "op:${OP_PASS}" | chpasswd
    usermod -aG www-data op

    # 設定 /data 權限，同時相容 Chroot SFTP 與 Samba 讀寫
    chown root:www-data /data
    chmod 775 /data

    # 設定 SSH SFTP
    cat > /etc/ssh/sshd_config.d/sftp-op.conf <<EOF
Match User op
    ChrootDirectory /data
    ForceCommand internal-sftp
    AllowTcpForwarding no
    X11Forwarding no
EOF

    systemctl restart ssh || systemctl restart sshd
}

run_step "STEP_07_OP_USER" "建立維護帳號 (op) 並配置權限" step_setup_op_user

# ------------------------------------------------------------
# 8. 重置與安裝 MariaDB，移轉資料目錄至 /data/mysql
# ------------------------------------------------------------
step_install_mariadb() {
    echo "==> 強制停止舊有 MariaDB 服務並徹底清空既有資料檔..."
    systemctl stop mariadb 2>/dev/null || true

    # 強制清空預設與目標 MySQL 資料目錄，確保重複執行時能從零初始
    rm -rf /var/lib/mysql/*
    rm -rf "${MYSQL_DIR}"/*

    apt-get install -y mariadb-server mariadb-client
    systemctl enable mariadb

    systemctl stop mariadb
    if [ -d "/var/lib/mysql" ] && [ -f "/var/lib/mysql/ibdata1" ]; then
        rsync -av /var/lib/mysql/ "${MYSQL_DIR}/"
    fi
    sed -i "s|datadir\s*=\s*/var/lib/mysql|datadir = ${MYSQL_DIR}|g" /etc/mysql/mariadb.conf.d/50-server.cnf
    chown -R mysql:mysql "${MYSQL_DIR}"
    systemctl start mariadb
}

run_step "STEP_08_MARIADB" "清空資料、安裝 MariaDB 並移轉至 /data/mysql" step_install_mariadb

# ------------------------------------------------------------
# 9. 安裝 phpMyAdmin 與安全性設定
# ------------------------------------------------------------
step_install_phpmyadmin() {
    echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2" | debconf-set-selections
    apt-get install -y phpmyadmin

    a2enconf phpmyadmin

    if [ -f /etc/phpmyadmin/config.inc.php ]; then
        if ! grep -q "AllowRoot" /etc/phpmyadmin/config.inc.php; then
            echo "\$cfg['Servers'][\$i]['AllowRoot'] = TRUE;" >> /etc/phpmyadmin/config.inc.php
        fi
    fi

    # 重設 MariaDB root 與 phpmyadmin 控制帳號
    mysql <<EOF
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
}

run_step "STEP_09_PHPMYADMIN" "安裝與配置 phpMyAdmin" step_install_phpmyadmin

# ------------------------------------------------------------
# 10. 配置 SSL 憑證與 Apache VirtualHost
# ------------------------------------------------------------
step_configure_ssl() {
    a2enmod ssl rewrite headers
    mkdir -p "${SSL_DIR}"

    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "${SSL_DIR}/server.key" \
        -out "${SSL_DIR}/server.crt" \
        -subj "/C=TW/ST=Taiwan/L=Taipei/O=WebServer/OU=IT/CN=$(hostname)"

    chmod 600 "${SSL_DIR}/server.key"
    chmod 644 "${SSL_DIR}/server.crt"

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

    Alias /my_config ${DATA_DIR}/my_config
    <Directory ${DATA_DIR}/my_config>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
        DirectoryIndex index.php index.html
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
}

run_step "STEP_10_SSL" "配置 SSL 憑證與 Apache VirtualHost" step_configure_ssl
# ------------------------------------------------------------
# 11. 部署測試頁面與 /my_config 控制台頁面
# ------------------------------------------------------------
step_deploy_testpage() {
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

    CONFIG_DEST_DIR="${DATA_DIR}/my_config"
    mkdir -p "${CONFIG_DEST_DIR}"

    GIT_CONFIG_URL="https://raw.githubusercontent.com/${GIT_ACCOUNT}/${GIT_PROJECT}/main/my_config/index.php"

    echo "==> 自 Git 下載控制台頁面 (index.php)..."
    # 使用 -f 參數確保 HTTP 錯誤 (404) 時不寫入檔案
    if ! curl -sSLf "${GIT_CONFIG_URL}" -o "${CONFIG_DEST_DIR}/index.php"; then
        echo "⚠️ 警告: 自 Git 下載 index.php 失敗 (404 或網路錯誤)，寫入基礎預設頁面..."
        cat > "${CONFIG_DEST_DIR}/index.php" <<'PHP_EOF'
<?php
echo "<h1>/my_config 控制台頁面建置中</h1>";
echo "<p>請確保 GitHub 儲存庫已放置 my_config/index.php 檔案。</p>";
PHP_EOF
    fi

    # 設定目錄與檔案權限
    chown -R www-data:www-data "${CONFIG_DEST_DIR}"
    chmod -R 755 "${CONFIG_DEST_DIR}"
}

run_step "STEP_11_TESTPAGE" "部署測試頁面與 /my_config 控制台頁面" step_deploy_testpage
# ------------------------------------------------------------
# 12. 設定每日 03:00 自動備份排程
# ------------------------------------------------------------
step_setup_backup() {
    cat > /usr/local/bin/backup_www.sh <<'EOF'
#!/usr/bin/env bash
set -e

BACKUP_DIR="/data/backup"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TARGET_FILE="${BACKUP_DIR}/www_backup_${TIMESTAMP}.tar.gz"

mkdir -p "${BACKUP_DIR}"
tar -czf "${TARGET_FILE}" -C /data www
find "${BACKUP_DIR}" -type f -name "www_backup_*.tar.gz" -mtime +7 -delete
EOF

    chmod +x /usr/local/bin/backup_www.sh
    (crontab -l 2>/dev/null | grep -v "/usr/local/bin/backup_www.sh"; echo "0 3 * * * /usr/local/bin/backup_www.sh") | crontab -
    
    # 建立可供網頁讀取的 Crontab 狀態標記檔
    crontab -l > /data/.cron_status
    chmod 644 /data/.cron_status
}

run_step "STEP_12_BACKUP" "設定每日 03:00 自動備份排程" step_setup_backup

# ------------------------------------------------------------
# 13. 設定目錄權限與重啟服務
# ------------------------------------------------------------
step_permissions_and_restart() {
    chown -R op:www-data "${WEB_ROOT}"
    chmod -R 775 "${WEB_ROOT}"
    find "${WEB_ROOT}" -type d -exec chmod g+s {} +

    chown -R mysql:mysql "${MYSQL_DIR}"
    chmod -R 770 "${MYSQL_DIR}"

    chown -R root:op "${DATA_DIR}/backup"
    chmod -R 775 "${DATA_DIR}/backup"

    chown -R www-data:www-data "${DATA_DIR}/logs"
    chmod -R 775 "${DATA_DIR}/logs"

    apache2ctl configtest
    systemctl restart apache2
    systemctl restart mariadb
}

# ------------------------------------------------------------
# 系統權限擴充：允許 www-data 執行一鍵安裝指令
# ------------------------------------------------------------
step_setup_web_sudoers() {
    cat > /etc/sudoers.d/www-data-install <<'EOF'
www-data ALL=(ALL) NOPASSWD: /usr/bin/apt-get update
www-data ALL=(ALL) NOPASSWD: /usr/bin/apt-get install -y *
www-data ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart *
www-data ALL=(ALL) NOPASSWD: /usr/bin/smbpasswd *
www-data ALL=(ALL) NOPASSWD: /usr/bin/pecl *
www-data ALL=(ALL) NOPASSWD: /usr/sbin/phpenmod *
www-data ALL=(ALL) NOPASSWD: /usr/bin/bash *
EOF
    chmod 0440 /etc/sudoers.d/www-data-install
}

run_step "STEP_WEB_SUDO" "設定 www-data 免密碼 Sudo 權限" step_setup_web_sudoers
# ------------------------------------------------------------
# 14. 結算與輸出
# ------------------------------------------------------------
# 直接採用 SECONDS 變數，不受時間同步校正影響
ELAPSED_SEC=$SECONDS
MINUTES=$((ELAPSED_SEC / 60))
SECONDS_LEFT=$((ELAPSED_SEC % 60))

SERVER_IP=$(hostname -I | awk '{print $1}')

echo "=============================================="
echo " 安裝完成！(Installation Completed)"
echo " 總耗時：${MINUTES} 分 ${SECONDS_LEFT} 秒"
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