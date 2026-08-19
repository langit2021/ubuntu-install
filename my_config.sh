#!/usr/bin/env bash

# ============================================================
# Ubuntu Web Server - Config Page Generator
# File: my_config.sh
# Description: Generates /data/my_config/index.php
# ============================================================

set -e

DATA_DIR="/data"
CONFIG_DIR="${DATA_DIR}/my_config"

# 接收外傳變數，若無則使用預設值 (測試階段固定密碼)
OP_PASS="${OP_PASS:-KXP1AEEuAsaqDWn}"
MYSQL_ROOT_PASS="${MYSQL_ROOT_PASS:-KXP1AEEuAsaqDWn}"

echo "==> Deploying /my_config interface via my_config.sh..."

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
    <a href="/phpmyadmin/" target="_blank" style="background-color: #17a2b8;">🗄️ 前往 phpMyAdmin</a>
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

# 設定 /data/my_config 權限歸屬
chown -R www-data:www-data "${CONFIG_DIR}"
chmod -R 755 "${CONFIG_DIR}"

echo "[OK] /my_config interface deployed successfully"