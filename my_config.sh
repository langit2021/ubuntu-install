#!/usr/bin/env bash

# ============================================================
# Ubuntu Web Server - Config Page Generator
# File: my_config.sh
# Description: Generates /data/my_config/index.php (4-Column Compact Layout)
# ============================================================

set -e

DATA_DIR="/data"
CONFIG_DIR="${DATA_DIR}/my_config"

# 接收外傳變數，若無則使用預設值
OP_PASS="${OP_PASS:-KXP1AEEuAsaqDWn}"
MYSQL_ROOT_PASS="${MYSQL_ROOT_PASS:-KXP1AEEuAsaqDWn}"

echo "==> Deploying /my_config interface via my_config.sh..."

mkdir -p "${CONFIG_DIR}"

cat > "${CONFIG_DIR}/index.php" <<EOF
<?php
// 1. 取得 MariaDB 系統變數
\$db_vars = [];
try {
    \$mysqli = new mysqli("localhost", "root", "${MYSQL_ROOT_PASS}");
    if (!\$mysqli->connect_error) {
        \$res = \$mysqli->query("SHOW VARIABLES WHERE Variable_name IN ('max_allowed_packet', 'skip_grant_tables', 'wait_timeout', 'max_connections', 'innodb_buffer_pool_size')");
        while (\$row = \$res->fetch_assoc()) {
            \$db_vars[\$row['Variable_name']] = \$row['Value'];
        }
        \$mysqli->close();
    }
} catch (Exception \$e) {
    // 忽略資料庫連線例外
}

// 2. 檢測 Cron 排程 (直接檢測系統 Root 的 crontab 檔案或備份檔是否存在)
\$root_cron = @file_get_contents('/var/spool/cron/crontabs/root');
if ($root_cron === false) {
    // 若無權限直接讀取，改用 sudo / cat 或系統檔案判斷
    \$root_cron = shell_exec('cat /var/spool/cron/crontabs/root 2>/dev/null');
}
\$has_backup_cron = ($root_cron !== null && $root_cron !== false && strpos($root_cron, '/usr/local/bin/backup_www.sh') !== false);



// 3. 取得 Apache 參數設定
\$apache_timeout = shell_exec("apache2ctl -t -D DUMP_RUN_CFG 2>/dev/null | grep -i Timeout || grep -Ri '^Timeout' /etc/apache2/ 2>/dev/null | head -n1 | awk '{print \$2}'") ?: '300 (Default)';
\$apache_timeout = trim(\$apache_timeout);

\$apache_limit_req = shell_exec("grep -Ri '^LimitRequestBody' /etc/apache2/ 2>/dev/null | head -n1 | awk '{print \$2}'") ?: '0 (Unlimited)';
\$apache_limit_req = trim(\$apache_limit_req);
if (is_numeric(\$apache_limit_req) && \$apache_limit_req > 0) {
    \$apache_limit_req = round(\$apache_limit_req / 1024 / 1024, 1) . ' MB';
}

// 4. 取得實際 Log 目錄設定
\$apache_log_dir = shell_exec("grep -Ri 'CustomLog' /etc/apache2/sites-enabled/ 2>/dev/null | head -n1 | awk '{print \$2}'") ?: '/data/logs/apache';
\$apache_log_dir = dirname(trim(\$apache_log_dir));

\$php_log_dir = ini_get('error_log') ? dirname(ini_get('error_log')) : '/data/logs/php';
?>
<!DOCTYPE html>
<html lang="zh-TW">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Ubuntu Web Server Configuration</title>
    <style>
        * { box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; margin: 0; padding: 12px; background-color: #f4f6f9; color: #333; line-height: 1.3; }
        
        .header-bar { display: flex; justify-content: space-between; align-items: center; background: #fff; padding: 10px 16px; border-radius: 6px; box-shadow: 0 1px 3px rgba(0,0,0,0.05); margin-bottom: 12px; }
        .header-bar h1 { margin: 0; font-size: 1.25rem; color: #1a252f; }
        .nav-bar a { display: inline-block; padding: 6px 12px; margin-left: 6px; border-radius: 4px; text-decoration: none; font-weight: bold; color: #fff; font-size: 0.85rem; }
        .btn-home { background-color: #28a745; }
        .btn-pma { background-color: #17a2b8; }
        
        /* 橫向 4 張卡片（使用 Flexbox，縮減留白） */
        .card-grid { display: flex; flex-wrap: wrap; margin: -6px; }
        .card { flex: 0 0 calc(25% - 12px); margin: 6px; background: #fff; border-radius: 6px; box-shadow: 0 1px 3px rgba(0,0,0,0.05); padding: 12px; border-top: 3px solid #007bff; }
        .card.success { border-top-color: #28a745; }
        .card.warning { border-top-color: #ffc107; }
        .card.info { border-top-color: #17a2b8; }
        .card.purple { border-top-color: #6f42c1; }
        
        .card h2 { margin: 0 0 8px 0; font-size: 0.98rem; color: #2c3e50; border-bottom: 1px solid #eee; padding-bottom: 6px; }
        .card ul { list-style: none; padding: 0; margin: 0; }
        .card li { padding: 4px 0; border-bottom: 1px dashed #f0f0f0; display: flex; justify-content: space-between; align-items: center; font-size: 0.85rem; word-break: break-all; }
        .card li:last-child { border-bottom: none; }
        
        code { font-weight: bold; color: #d9534f; background: #f8f9fa; padding: 1px 5px; border-radius: 3px; border: 1px solid #e9ecef; font-size: 0.82rem; }
        .path-code { color: #2b542c; background: #f0f9f0; word-break: break-all; text-align: right; max-width: 65%; }
        
        .badge { padding: 2px 6px; border-radius: 10px; font-size: 0.75rem; font-weight: bold; }
        .badge-ok { background: #d4edda; color: #155724; }
        .badge-fail { background: #f8d7da; color: #721c24; }

        /* 響應式斷點調整 */
        @media (max-width: 1200px) { .card { flex: 0 0 calc(33.333% - 12px); } }
        @media (max-width: 768px) { .card { flex: 0 0 calc(50% - 12px); } }
        @media (max-width: 500px) { 
            .card { flex: 0 0 calc(100% - 12px); }
            .header-bar { flex-direction: column; gap: 8px; align-items: flex-start; }
        }
    </style>
</head>
<body>

<div class="header-bar">
    <h1>Ubuntu Web Server 系統組態資訊</h1>
    <div class="nav-bar">
        <a href="/" class="btn-home">🏠 返回首頁</a>
        <a href="/phpmyadmin/" target="_blank" class="btn-pma">🗄️ phpMyAdmin</a>
    </div>
</div>

<div class="card-grid">

    <!-- 1. 系統權限與登入憑證 -->
    <div class="card info">
        <h2>🔑 系統管理憑證</h2>
        <ul>
            <li><span>SFTP/SSH 帳號</span> <code>op</code></li>
            <li><span>SFTP/SSH 密碼</span> <code>${OP_PASS}</code></li>
            <li><span>MariaDB Root 帳號</span> <code>root</code></li>
            <li><span>MariaDB Root 密碼</span> <code>${MYSQL_ROOT_PASS}</code></li>
        </ul>
    </div>

    <!-- 2. 自動備份與 Cron 排程 -->
    <div class="card <?php echo \$has_backup_cron ? 'success' : 'warning'; ?>">
        <h2>⏰ Crontab 自動備份</h2>
        <ul>
            <li>
                <span>每日 03:00 備份</span>
                <?php if (\$has_backup_cron): ?>
                    <span class="badge badge-ok">已設定 (OK)</span>
                <?php else: ?>
                    <span class="badge badge-fail">未設定 (Missing)</span>
                <?php endif; ?>
            </li>
            <li><span>備份目標目錄</span> <code class="path-code">/data/backup</code></li>
            <li><span>備份執行腳本</span> <code>backup_www.sh</code></li>
        </ul>
    </div>

    <!-- 3. Apache 網頁伺服器參數 -->
    <div class="card purple">
        <h2>🌐 Apache 設定參數</h2>
        <ul>
            <li><span>Timeout</span> <code><?php echo \$apache_timeout; ?></code></li>
            <li><span>LimitRequestBody</span> <code><?php echo \$apache_limit_req; ?></code></li>
            <li><span>VirtualHost 模式</span> <span class="badge badge-ok">SSL (443)</span></li>
        </ul>
    </div>

    <!-- 4. PHP 效能與資源管理 -->
    <div class="card">
        <h2>🐘 PHP 效能參數</h2>
        <ul>
            <li><span>時區</span> <code><?php echo date_default_timezone_get(); ?></code></li>
            <li><span>memory_limit</span> <code><?php echo ini_get('memory_limit'); ?></code></li>
            <li><span>upload_max_filesize</span> <code><?php echo ini_get('upload_max_filesize'); ?></code></li>
            <li><span>post_max_size</span> <code><?php echo ini_get('post_max_size'); ?></code></li>
            <li><span>max_execution_time</span> <code><?php echo ini_get('max_execution_time'); ?>s</code></li>
            <li><span>max_input_time</span> <code><?php echo ini_get('max_input_time'); ?>s</code></li>
        </ul>
    </div>

    <!-- 5. MariaDB 資料庫狀態與參數 -->
    <div class="card info">
        <h2>🗄️ MariaDB 運作參數</h2>
        <ul>
            <li>
                <span>max_allowed_packet</span>
                <code><?php echo isset(\$db_vars['max_allowed_packet']) ? round(\$db_vars['max_allowed_packet'] / 1024 / 1024, 1) . ' MB' : 'N/A'; ?></code>
            </li>
            <li>
                <span>innodb_buffer_pool_size</span>
                <code><?php echo isset(\$db_vars['innodb_buffer_pool_size']) ? round(\$db_vars['innodb_buffer_pool_size'] / 1024 / 1024, 1) . ' MB' : 'N/A'; ?></code>
            </li>
            <li>
                <span>skip-grant-tables</span>
                <code><?php echo isset(\$db_vars['skip_grant_tables']) ? strtoupper(\$db_vars['skip_grant_tables']) : 'OFF'; ?></code>
            </li>
            <li>
                <span>wait_timeout</span>
                <code><?php echo isset(\$db_vars['wait_timeout']) ? \$db_vars['wait_timeout'] . 's' : 'N/A'; ?></code>
            </li>
            <li>
                <span>max_connections</span>
                <code><?php echo isset(\$db_vars['max_connections']) ? \$db_vars['max_connections'] : 'N/A'; ?></code>
            </li>
        </ul>
    </div>

    <!-- 6. 集中化目錄與服務實際路徑 -->
    <div class="card success">
        <h2>🟢 集中化目錄實際路徑</h2>
        <ul>
            <li><span>Ubuntu 版本</span> <span class="badge badge-ok">24.04 LTS</span></li>
            <li><span>網頁根目錄</span> <code class="path-code">/data/www</code></li>
            <li><span>資料庫目錄</span> <code class="path-code">/data/mysql</code></li>
            <li><span>Apache Log Directory</span> <code class="path-code"><?php echo \$apache_log_dir; ?></code></li>
            <li><span>PHP Log Directory</span> <code class="path-code"><?php echo \$php_log_dir; ?></code></li>
        </ul>
    </div>

</div>

</body>
</html>
EOF

# 設定 /data/my_config 權限歸屬
chown -R www-data:www-data "${CONFIG_DIR}"
chmod -R 755 "${CONFIG_DIR}"

echo "[OK] /my_config interface with compact 4-column grid updated successfully"