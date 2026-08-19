#!/usr/bin/env bash

# ============================================================
# Ubuntu Web Server - Config Page Generator
# File: my_config.sh
# Description: Generates /data/my_config/index.php (Card Layout)
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
// 取得 MariaDB 系統變數
\$db_vars = [];
try {
    \$mysqli = new mysqli("localhost", "root", "${MYSQL_ROOT_PASS}");
    if (!\$mysqli->connect_error) {
        \$res = \$mysqli->query("SHOW VARIABLES WHERE Variable_name IN ('max_allowed_packet', 'skip_grant_tables', 'wait_timeout', 'max_connections')");
        while (\$row = \$res->fetch_assoc()) {
            \$db_vars[\$row['Variable_name']] = \$row['Value'];
        }
        \$mysqli->close();
    }
} catch (Exception \$e) {
    // 若連線失敗由頁面顯示提示
}

// 檢測 Cron 排程
\$cron_output = shell_exec('crontab -l 2>/dev/null');
\$has_backup_cron = (strpos(\$cron_output, '/usr/local/bin/backup_www.sh') !== false);
?>
<!DOCTYPE html>
<html lang="zh-TW">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Ubuntu Web Server Configuration</title>
    <style>
        * { box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; margin: 0; padding: 20px; background-color: #f4f6f9; color: #333; line-height: 1.5; }
        .header-bar { display: flex; justify-content: space-between; align-items: center; background: #fff; padding: 15px 25px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.05); margin-bottom: 25px; }
        .header-bar h1 { margin: 0; font-size: 1.5rem; color: #1a252f; }
        .nav-bar a { display: inline-block; padding: 8px 16px; margin-left: 10px; border-radius: 5px; text-decoration: none; font-weight: bold; color: #fff; font-size: 0.9rem; transition: background 0.2s; }
        .btn-home { background-color: #28a745; }
        .btn-home:hover { background-color: #218838; }
        .btn-pma { background-color: #17a2b8; }
        .btn-pma:hover { background-color: #138496; }
        
        /* 卡片容器：Flex 排版，橫向 3 張 */
        .card-grid { display: flex; flex-wrap: wrap; margin: -10px; }
        .card { flex: 0 0 calc(33.333% - 20px); margin: 10px; background: #fff; border-radius: 8px; box-shadow: 0 2px 5px rgba(0,0,0,0.05); padding: 20px; border-top: 4px solid #007bff; }
        .card.success { border-top-color: #28a745; }
        .card.warning { border-top-color: #ffc107; }
        .card.info { border-top-color: #17a2b8; }
        .card h2 { margin-top: 0; font-size: 1.15rem; color: #2c3e50; border-bottom: 1px solid #eee; padding-bottom: 10px; }
        .card ul { list-style: none; padding: 0; margin: 0; }
        .card li { padding: 6px 0; border-bottom: 1px dashed #f0f0f0; display: flex; justify-content: space-between; align-items: center; font-size: 0.92rem; }
        .card li:last-child { border-bottom: none; }
        
        code { font-weight: bold; color: #d9534f; background: #f8f9fa; padding: 2px 6px; border-radius: 4px; border: 1px solid #e9ecef; }
        .badge { padding: 3px 8px; border-radius: 12px; font-size: 0.8rem; font-weight: bold; }
        .badge-ok { background: #d4edda; color: #155724; }
        .badge-fail { background: #f8d7da; color: #721c24; }

        /* 響應式調整 */
        @media (max-width: 992px) {
            .card { flex: 0 0 calc(50% - 20px); }
        }
        @media (max-width: 600px) {
            .card { flex: 0 0 calc(100% - 20px); }
            .header-bar { flex-direction: column; gap: 15px; align-items: flex-start; }
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

    <!-- 卡片 1: 系統維護與驗證 -->
    <div class="card info">
        <h2>🔑 系統管理憑證</h2>
        <ul>
            <li><span>SFTP / SSH 帳號</span> <code>op</code></li>
            <li><span>SFTP / SSH 密碼</span> <code>${OP_PASS}</code></li>
            <li><span>MariaDB Root 帳號</span> <code>root</code></li>
            <li><span>MariaDB Root 密碼</span> <code>${MYSQL_ROOT_PASS}</code></li>
        </ul>
    </div>

    <!-- 卡片 2: 備份與 Crontab 排程 -->
    <div class="card <?php echo \$has_backup_cron ? 'success' : 'warning'; ?>">
        <h2>⏰ 系統 Crontab 排程檢測</h2>
        <ul>
            <li>
                <span>每日 03:00 自動備份</span>
                <?php if (\$has_backup_cron): ?>
                    <span class="badge badge-ok">已設定 (OK)</span>
                <?php else: ?>
                    <span class="badge badge-fail">未設定 (Missing)</span>
                <?php endif; ?>
            </li>
            <li><span>備份目標路徑</span> <code>/data/backup</code></li>
            <li><span>備份執行腳本</span> <code>backup_www.sh</code></li>
        </ul>
    </div>

    <!-- 卡片 3: MariaDB 資料庫進階參數 -->
    <div class="card info">
        <h2>🗄️ MariaDB 運作參數</h2>
        <ul>
            <li>
                <span>max_allowed_packet</span>
                <code><?php echo isset(\$db_vars['max_allowed_packet']) ? round(\$db_vars['max_allowed_packet'] / 1024 / 1024, 1) . ' MB' : 'N/A'; ?></code>
            </li>
            <li>
                <span>skip-grant-tables</span>
                <code><?php echo isset(\$db_vars['skip_grant_tables']) ? strtoupper(\$db_vars['skip_grant_tables']) : 'OFF'; ?></code>
            </li>
            <li>
                <span>wait_timeout</span>
                <code><?php echo isset(\$db_vars['wait_timeout']) ? \$db_vars['wait_timeout'] . ' 秒' : 'N/A'; ?></code>
            </li>
            <li>
                <span>max_connections</span>
                <code><?php echo isset(\$db_vars['max_connections']) ? \$db_vars['max_connections'] : 'N/A'; ?></code>
            </li>
        </ul>
    </div>

    <!-- 卡片 4: PHP 關鍵參數 -->
    <div class="card">
        <h2>🐘 PHP 效能與資源</h2>
        <ul>
            <li><span>系統預設時區</span> <code><?php echo date_default_timezone_get(); ?></code></li>
            <li><span>記憶體限制 (memory_limit)</span> <code><?php echo ini_get('memory_limit'); ?></code></li>
            <li><span>單檔上傳上限 (upload_max_filesize)</span> <code><?php echo ini_get('upload_max_filesize'); ?></code></li>
            <li><span>POST 總量上限 (post_max_size)</span> <code><?php echo ini_get('post_max_size'); ?></code></li>
            <li><span>最長執行時間 (max_execution_time)</span> <code><?php echo ini_get('max_execution_time'); ?> 秒</code></li>
        </ul>
    </div>

    <!-- 卡片 5: 核心服務與目錄狀態 -->
    <div class="card success">
        <h2>🟢 集中化目錄與服務</h2>
        <ul>
            <li><span>Ubuntu 版本</span> <span class="badge badge-ok">24.04 LTS</span></li>
            <li><span>PHP 版本</span> <code><?php echo PHP_VERSION; ?></code></li>
            <li><span>網頁目錄 (/data/www)</span> <?php echo is_dir('/data/www') ? '<span class="badge badge-ok">OK</span>' : '<span class="badge badge-fail">Error</span>'; ?></li>
            <li><span>資料庫目錄 (/data/mysql)</span> <?php echo is_dir('/data/mysql') ? '<span class="badge badge-ok">OK</span>' : '<span class="badge badge-fail">Error</span>'; ?></li>
            <li><span>Apache Log Directory</span> <?php echo is_dir('/data/logs/apache') ? '<span class="badge badge-ok">OK</span>' : '<span class="badge badge-fail">Error</span>'; ?></li>
            <li><span>PHP Log Directory</span> <?php echo is_dir('/data/logs/php') ? '<span class="badge badge-ok">OK</span>' : '<span class="badge badge-fail">Error</span>'; ?></li>
        </ul>
    </div>

</div>

</body>
</html>
EOF

# 設定 /data/my_config 權限歸屬
chown -R www-data:www-data "${CONFIG_DIR}"
chmod -R 755 "${CONFIG_DIR}"

echo "[OK] /my_config interface with responsive grid updated successfully"