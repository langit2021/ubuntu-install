#!/usr/bin/env bash

# ============================================================
# Ubuntu Web Server Installer
# Version: 0.6
# Target: Ubuntu Server 24.04 LTS
# ============================================================

set -e
SECONDS=0

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

step_timezone_and_log

GIT_ACCOUNT=langit2021
GIT_PROJECT=ubuntu-install

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

DATA_DIR="/data"
WEB_ROOT="${DATA_DIR}/www"
MYSQL_DIR="${DATA_DIR}/mysql"
LOG_APACHE="${DATA_DIR}/logs/apache"
LOG_PHP="${DATA_DIR}/logs/php"
SSL_DIR="/etc/apache2/ssl"
PROGRESS_FILE="/data/.install_progress"

mkdir -p /data

# ------------------------------------------------------------
# Checkpoint 檢查機制
# ------------------------------------------------------------
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

    sed -i "s|;error_log = php_errors.log|error_log = ${LOG_PHP}/php_errors.log|g" /etc/php/8.3/apache2/php.ini
    sed -i "s|;error_log = php_errors.log|error_log = ${LOG_PHP}/php_errors.log|g" /etc/php/8.3/cli/php.ini
    touch "${LOG_PHP}/php_errors.log"

    sed -i "s|;date.timezone =|date.timezone = Asia/Taipei|g" /etc/php/8.3/apache2/php.ini
    sed -i "s|;date.timezone =|date.timezone = Asia/Taipei|g" /etc/php/8.3/cli/php.ini

    systemctl restart apache2
}

run_step "STEP_06_PHP" "安裝與設定 PHP 8.3" step_install_php

# ------------------------------------------------------------
# 7. 建立維護帳號 (op) 與 SFTP 權限設定
# ------------------------------------------------------------
step_setup_op_user() {
    OP_PASS="${OP_PASS:-KXP1AEEuAsaqDWn}"

    if ! id "op" &>/dev/null; then
        useradd -d /data -s /bin/bash op
    else
        usermod -s /bin/bash op
    fi

    echo "op:${OP_PASS}" | chpasswd
    usermod -aG www-data op

    chown root:www-data /data
    chmod 755 /data

    rm -f /etc/ssh/sshd_config.d/sftp-op.conf
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
# 8. [移至 Web 控制台] MariaDB 服務
# 9. [移至 Web 控制台] phpMyAdmin 服務
# 註：MariaDB 與 phpMyAdmin 已改由 /my_config 控制台提供一鍵部署
# ------------------------------------------------------------

# ------------------------------------------------------------
# 10. 配置 SSL 憑證與 Apache VirtualHost
# ------------------------------------------------------------
step_configure_ssl() {
    a2enmod ssl rewrite headers
    
    rm -rf "${SSL_DIR}"
    mkdir -p "${SSL_DIR}"

    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "${SSL_DIR}/server.key" \
        -out "${SSL_DIR}/server.crt" \
        -subj "/C=TW/ST=Taiwan/L=Taipei/O=WebServer/OU=IT/CN=$(hostname)"

    chmod 600 "${SSL_DIR}/server.key"
    chmod 644 "${SSL_DIR}/server.crt"

    a2dissite webserver-ssl.conf redirect-ssl.conf 2>/dev/null || true
    rm -f /etc/apache2/sites-available/webserver-ssl.conf /etc/apache2/sites-available/redirect-ssl.conf

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
# 11. 部署測試頁面與 /my_config 精簡引導頁面 (替換原 step_deploy_testpage)
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

    # 寫入初次安裝精簡版引導頁 (簡潔架構，僅保留一鍵掛載/更新功能)
    cat > "${CONFIG_DEST_DIR}/index.php" <<'PHP_EOF'
<?php
$git_account = "langit2021";
$git_project = "ubuntu-install";

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action']) && $_POST['action'] === 'mount_modules') {
    header('Content-Type: application/json');
    
    // 模組檔案清單
    $files = [
        'index.php',
        'card_credentials.php',
        'card_mssql.php',
        'card_samba.php',
        'card_backup.php',
        'card_apache.php',
        'card_php.php',
        'card_mariadb.php',
        'card_pma.php',
        'card_paths.php'
    ];
    
    $success = true;
    $errors = [];

    foreach ($files as $file) {
        $url = "https://raw.githubusercontent.com/{$git_account}/{$git_project}/main/my_config/{$file}";
        $dest = "/data/my_config/{$file}";
        $content = @file_get_contents($url);
        
        if ($content !== false && !empty($content)) {
            file_put_contents($dest, $content);
            chmod($dest, 0775);
            chown($dest, 'op');
        } else {
            $success = false;
            $errors[] = "無法下載 {$file}";
        }
    }

    if ($success) {
        echo json_encode(['status' => 'success', 'message' => '所有控制台模組卡片已成功掛載與更新！']);
    } else {
        echo json_encode(['status' => 'error', 'message' => implode(', ', $errors)]);
    }
    exit;
}
?>
<!DOCTYPE html>
<html lang="zh-TW">
<head>
    <meta charset="UTF-8">
    <title>控制台模組掛載引導</title>
    <style>
        body { font-family: system-ui, sans-serif; background: #f4f6f9; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }
        .setup-card { background: #fff; padding: 30px; border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.1); text-align: center; max-width: 450px; width: 100%; }
        h2 { margin-top: 0; color: #1a252f; }
        p { color: #666; font-size: 0.95rem; line-height: 1.5; }
        .btn-mount { background: #007bff; color: white; border: none; padding: 12px 24px; font-size: 1rem; font-weight: bold; border-radius: 5px; cursor: pointer; transition: background 0.2s; width: 100%; margin-top: 15px; }
        .btn-mount:hover { background: #0056b3; }
        #msg { margin-top: 15px; font-weight: bold; font-size: 0.9rem; }
    </style>
</head>
<body>
    <div class="setup-card">
        <h2>🚀 控制台未初始化</h2>
        <p>當前系統處於初始狀態。點擊下方按鈕將自動從 GitHub 下載最新版控制台主結構檔與 8 個獨立卡片組件。</p>
        <button class="btn-mount" onclick="mountModules()">⚡ 一鍵掛載與更新控制台模組</button>
        <div id="msg"></div>
    </div>
    <script>
    function mountModules() {
        const msg = document.getElementById('msg');
        msg.style.color = '#007bff';
        msg.innerText = '⏳ 正在從 GitHub 下載與掛載卡片組件...';
        
        const fd = new FormData();
        fd.append('action', 'mount_modules');
        
        fetch('index.php', { method: 'POST', body: fd })
            .then(res => res.json())
            .then(data => {
                if (data.status === 'success') {
                    msg.style.color = '#28a745';
                    msg.innerText = data.message + ' 即將自動重新整理...';
                    setTimeout(() => window.location.reload(), 1500);
                } else {
                    msg.style.color = '#dc3545';
                    msg.innerText = '❌ ' + data.message;
                }
            })
            .catch(() => {
                msg.style.color = '#dc3545';
                msg.innerText = '❌ 下載發生錯誤，請檢查網路連線或 GitHub 檔案是否存在。';
            });
    }
    </script>
</body>
</html>
PHP_EOF

    chown -R op:www-data "${CONFIG_DEST_DIR}"
    chmod -R 775 "${CONFIG_DEST_DIR}"
    find "${CONFIG_DEST_DIR}" -type d -exec chmod g+s {} +
}

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

    if [ -d "${MYSQL_DIR}" ]; then
        chown -R mysql:mysql "${MYSQL_DIR}" 2>/dev/null || true
        chmod -R 770 "${MYSQL_DIR}" 2>/dev/null || true
    fi

    chown -R root:op "${DATA_DIR}/backup"
    chmod -R 775 "${DATA_DIR}/backup"

    chown -R www-data:www-data "${DATA_DIR}/logs"
    chmod -R 775 "${DATA_DIR}/logs"

    apache2ctl configtest
    systemctl restart apache2
    
    # 僅在 MariaDB 服務存在且已安裝時重啟
    if systemctl is-active --quiet mariadb || systemctl is-enabled --quiet mariadb 2>/dev/null; then
        systemctl restart mariadb
    fi
}

# ------------------------------------------------------------
# 14. 系統權限擴充：允許 www-data 免密碼執行控制台腳本
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
www-data ALL=(ALL) NOPASSWD: /tmp/run_install.sh
EOF
    chmod 0440 /etc/sudoers.d/www-data-install
}

run_step "STEP_WEB_SUDO" "設定 www-data 免密碼 Sudo 權限" step_setup_web_sudoers

# ------------------------------------------------------------
# 15. 結算與輸出
# ------------------------------------------------------------
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
echo "  密碼: ${OP_PASS:-KXP1AEEuAsaqDWn}"
echo
echo "MariaDB Root 憑證:"
echo "  帳號: root"
echo "  密碼: ${MYSQL_ROOT_PASS:-KXP1AEEuAsaqDWn}"
echo "=============================================="