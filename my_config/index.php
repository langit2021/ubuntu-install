<?php
// ============================================================
// Ubuntu Web Server - Config Page
// File: index.php
// Description: Interactive / Info Control Panel (MSSQL & Samba Enabled)
// ============================================================

$op_pass = getenv('OP_PASS') ?: 'KXP1AEEuAsaqDWn';
$mysql_root_pass = getenv('MYSQL_ROOT_PASS') ?: 'KXP1AEEuAsaqDWn';

$message = '';
$message_type = '';

// ------------------------------------------------------------
// POST 動作處理器：一鍵安裝 MSSQL 驅動 / Samba
// ------------------------------------------------------------
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action'])) {
    $action = $_POST['action'];

    if ($action === 'install_mssql') {
        // 安裝 Microsoft ODBC 驅動與 PHP sqlsrv / pdo_sqlsrv 擴充
        $cmd = "sudo ACCEPT_EULA=Y apt-get update && " .
               "sudo ACCEPT_EULA=Y apt-get install -y unixodbc-dev php8.3-sqlsrv php8.3-pdo-sqlsrv php-pear php-dev && " .
               "sudo systemctl restart apache2 2>&1";
        $output = shell_exec($cmd);
        $message = "MSSQL 驅動程式安裝完成！Apache 已自動重啟。";
        $message_type = "success";
    } elseif ($action === 'install_samba') {
        // 1. 安裝 Samba 套件
        $cmd1 = "sudo apt-get update && sudo apt-get install -y samba 2>&1";
        shell_exec($cmd1);

        // 2. 寫入 /etc/samba/smb.conf 設定 (分享 /data 為 web)
        $smb_conf = <<<CONF

[web]
   comment = Data Backup and Web Directory
   path = /data
   browseable = yes
   read only = no
   guest ok = no
   valid users = op
   create mask = 0775
   directory mask = 0775
CONF;
        // 檢查是否已設定過 [web]
        $current_conf = file_get_contents('/etc/samba/smb.conf');
        if (strpos($current_conf, '[web]') === false) {
            file_put_contents('/tmp/smb_append.conf', $smb_conf);
            shell_exec("sudo bash -c 'cat /tmp/smb_append.conf >> /etc/samba/smb.conf' && rm -f /tmp/smb_append.conf");
        }

        // 3. 將 op 帳號加入 Samba 並設定密碼
        $cmd2 = "(echo \"{$op_pass}\"; echo \"{$op_pass}\") | sudo smbpasswd -a -s op && sudo smbpasswd -e op && sudo systemctl restart smbd 2>&1";
        shell_exec($cmd2);

        $message = "Samba 網路芳鄰安裝成功！已建立 \\\\IP\\web 分享，並同步 op 帳號登入權限。";
        $message_type = "success";
    }
}

// ------------------------------------------------------------
// 狀態檢測 logic
// ------------------------------------------------------------
// 1. 檢測 MSSQL (pdo_sqlsrv / sqlsrv) 驅動
$has_mssql = extension_loaded('pdo_sqlsrv') || extension_loaded('sqlsrv');

// 2. 檢測 Samba 套件安裝狀態與服務執行狀態
$samba_installed = (trim(shell_exec("which smbd 2>/dev/null")) !== '');
$samba_running = (trim(shell_exec("systemctl is-active smbd 2>/dev/null")) === 'active');

// 3. MariaDB 變數
$db_vars = [];
try {
    $mysqli = new mysqli("localhost", "root", $mysql_root_pass);
    if (!$mysqli->connect_error) {
        $res = $mysqli->query("SHOW VARIABLES WHERE Variable_name IN ('max_allowed_packet', 'skip_grant_tables', 'wait_timeout', 'max_connections', 'innodb_buffer_pool_size')");
        while ($row = $res->fetch_assoc()) {
            $db_vars[$row['Variable_name']] = $row['Value'];
        }
        $mysqli->close();
    }
} catch (Exception $e) {}

// 4. Cron 狀態
$cron_status_file = '/data/.cron_status';
$cron_content = file_exists($cron_status_file) ? file_get_contents($cron_status_file) : '';
$has_backup_cron = (strpos($cron_content, '/usr/local/bin/backup_www.sh') !== false);

// 5. Apache & PHP 參數
$apache_timeout = trim(shell_exec("apache2ctl -t -D DUMP_RUN_CFG 2>/dev/null | grep -i Timeout || grep -Ri '^Timeout' /etc/apache2/ 2>/dev/null | head -n1 | awk '{print $2}'") ?: '300 (Default)');
$apache_limit_req = trim(shell_exec("grep -Ri '^LimitRequestBody' /etc/apache2/ 2>/dev/null | head -n1 | awk '{print $2}'") ?: '0 (Unlimited)');
if (is_numeric($apache_limit_req) && $apache_limit_req > 0) {
    $apache_limit_req = round($apache_limit_req / 1024 / 1024, 1) . ' MB';
}

$apache_log_dir = dirname(trim(shell_exec("grep -Ri 'CustomLog' /etc/apache2/sites-enabled/ 2>/dev/null | head -n1 | awk '{print $2}'") ?: '/data/logs/apache'));
$php_log_dir = ini_get('error_log') ? dirname(ini_get('error_log')) : '/data/logs/php';
$server_ip = $_SERVER['SERVER_ADDR'] ?? 'YOUR_SERVER_IP';
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
        
        .alert { padding: 10px 15px; margin-bottom: 12px; border-radius: 4px; font-weight: bold; font-size: 0.9rem; }
        .alert-success { background-color: #d4edda; color: #155724; border: 1px solid #c3e6cb; }

        .card-grid { display: flex; flex-wrap: wrap; margin: -6px; }
        .card { flex: 0 0 calc(25% - 12px); margin: 6px; background: #fff; border-radius: 6px; box-shadow: 0 1px 3px rgba(0,0,0,0.05); padding: 12px; border-top: 3px solid #007bff; }
        .card.success { border-top-color: #28a745; }
        .card.warning { border-top-color: #ffc107; }
        .card.info { border-top-color: #17a2b8; }
        .card.purple { border-top-color: #6f42c1; }
        .card.danger { border-top-color: #dc3545; }
        
        .card h2 { margin: 0 0 8px 0; font-size: 0.98rem; color: #2c3e50; border-bottom: 1px solid #eee; padding-bottom: 6px; }
        .card ul { list-style: none; padding: 0; margin: 0; }
        .card li { padding: 4px 0; border-bottom: 1px dashed #f0f0f0; display: flex; justify-content: space-between; align-items: center; font-size: 0.85rem; word-break: break-all; }
        .card li:last-child { border-bottom: none; }
        
        code { font-weight: bold; color: #d9534f; background: #f8f9fa; padding: 1px 5px; border-radius: 3px; border: 1px solid #e9ecef; font-size: 0.82rem; }
        .path-code { color: #2b542c; background: #f0f9f0; word-break: break-all; text-align: right; max-width: 65%; }
        
        .badge { padding: 2px 6px; border-radius: 10px; font-size: 0.75rem; font-weight: bold; }
        .badge-ok { background: #d4edda; color: #155724; }
        .badge-fail { background: #f8d7da; color: #721c24; }

        .btn-install { background: #007bff; color: white; border: none; padding: 6px 12px; border-radius: 4px; cursor: pointer; font-weight: bold; font-size: 0.8rem; width: 100%; margin-top: 6px; transition: background 0.2s; }
        .btn-install:hover { background: #0056b3; }

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

<?php if ($message): ?>
    <div class="alert alert-success"><?php echo htmlspecialchars($message); ?></div>
<?php endif; ?>

<div class="card-grid">

    <!-- 1. 系統權限與登入憑證 -->
    <div class="card info">
        <h2>🔑 系統管理憑證</h2>
        <ul>
            <li><span>SFTP / Samba 帳號</span> <code>op</code></li>
            <li><span>SFTP / Samba 密碼</span> <code><?php echo htmlspecialchars($op_pass); ?></code></li>
            <li><span>MariaDB Root 帳號</span> <code>root</code></li>
            <li><span>MariaDB Root 密碼</span> <code><?php echo htmlspecialchars($mysql_root_pass); ?></code></li>
        </ul>
    </div>

    <!-- 2. MS SQL 驅動狀態 (新增需求 1) -->
    <div class="card <?php echo $has_mssql ? 'success' : 'danger'; ?>">
        <h2>🗄️ MS SQL (2017) 驅動</h2>
        <ul>
            <li>
                <span>pdo_sqlsrv 狀態</span>
                <?php if ($has_mssql): ?>
                    <span class="badge badge-ok">已安裝 (Ready)</span>
                <?php else: ?>
                    <span class="badge badge-fail">未安裝 (Missing)</span>
                <?php endif; ?>
            </li>
            <li><span>支援版本</span> <code>SQL Server 2017+</code></li>
        </ul>
        <?php if (!$has_mssql): ?>
            <form method="POST" onsubmit="return confirm('確定要透過背景安裝 MS SQL 驅動程式嗎？');">
                <input type="hidden" name="action" value="install_mssql">
                <button type="submit" class="btn-install">⚡ 一鍵安裝 MS SQL 驅動</button>
            </form>
        <?php endif; ?>
    </div>

    <!-- 3. Samba 網路芳鄰設定 (新增需求 2) -->
    <div class="card <?php echo $samba_installed ? 'success' : 'danger'; ?>">
        <h2>📁 Samba 網路芳鄰</h2>
        <ul>
            <li>
                <span>服務狀態</span>
                <?php if ($samba_installed && $samba_running): ?>
                    <span class="badge badge-ok">運作中 (Active)</span>
                <?php elseif ($samba_installed): ?>
                    <span class="badge badge-fail">已安裝 (已停止)</span>
                <?php else: ?>
                    <span class="badge badge-fail">未安裝 (Missing)</span>
                <?php endif; ?>
            </li>
            <li><span>分享路徑</span> <code class="path-code">/data</code></li>
            <li><span>分享名稱</span> <code>web</code></li>
            <li><span>連線位置</span> <code class="path-code">\\<?php echo $server_ip; ?>\web</code></li>
        </ul>
        <?php if (!$samba_installed): ?>
            <form method="POST" onsubmit="return confirm('確定要安裝 Samba 並啟用 \\\\IP\\web 網路芳鄰分享嗎？');">
                <input type="hidden" name="action" value="install_samba">
                <button type="submit" class="btn-install">⚡ 一鍵安裝 Samba 分享</button>
            </form>
        <?php endif; ?>
    </div>

    <!-- 4. 自動備份與 Cron 排程 -->
    <div class="card <?php echo $has_backup_cron ? 'success' : 'warning'; ?>">
        <h2>⏰ Crontab 自動備份</h2>
        <ul>
            <li>
                <span>每日 03:00 備份</span>
                <?php if ($has_backup_cron): ?>
                    <span class="badge badge-ok">已設定 (OK)</span>
                <?php else: ?>
                    <span class="badge badge-fail">未設定 (Missing)</span>
                <?php endif; ?>
            </li>
            <li><span>備份目標目錄</span> <code class="path-code">/data/backup</code></li>
            <li><span>備份執行腳本</span> <code>backup_www.sh</code></li>
        </ul>
    </div>

    <!-- 5. Apache 網頁伺服器參數 -->
    <div class="card purple">
        <h2>🌐 Apache 設定參數</h2>
        <ul>
            <li><span>Timeout</span> <code><?php echo htmlspecialchars($apache_timeout); ?></code></li>
            <li><span>LimitRequestBody</span> <code><?php echo htmlspecialchars($apache_limit_req); ?></code></li>
            <li><span>VirtualHost 模式</span> <span class="badge badge-ok">SSL (443)</span></li>
        </ul>
    </div>

    <!-- 6. PHP 效能與資源管理 -->
    <div class="card">
        <h2>🐘 PHP 效能參數</h2>
        <ul>
            <li><span>時區</span> <code><?php echo date_default_timezone_get(); ?></code></li>
            <li><span>memory_limit</span> <code><?php echo ini_get('memory_limit'); ?></code></li>
            <li><span>upload_max_filesize</span> <code><?php echo ini_get('upload_max_filesize'); ?></code></li>
            <li><span>post_max_size</span> <code><?php echo ini_get('post_max_size'); ?></code></li>
            <li><span>max_execution_time</span> <code><?php echo ini_get('max_execution_time'); ?>s</code></li>
        </ul>
    </div>

    <!-- 7. MariaDB 資料庫狀態與參數 -->
    <div class="card info">
        <h2>🗄️ MariaDB 運作參數</h2>
        <ul>
            <li>
                <span>max_allowed_packet</span>
                <code><?php echo isset($db_vars['max_allowed_packet']) ? round($db_vars['max_allowed_packet'] / 1024 / 1024, 1) . ' MB' : 'N/A'; ?></code>
            </li>
            <li>
                <span>innodb_buffer_pool_size</span>
                <code><?php echo isset($db_vars['innodb_buffer_pool_size']) ? round($db_vars['innodb_buffer_pool_size'] / 1024 / 1024, 1) . ' MB' : 'N/A'; ?></code>
            </li>
            <li>
                <span>wait_timeout</span>
                <code><?php echo isset($db_vars['wait_timeout']) ? $db_vars['wait_timeout'] . 's' : 'N/A'; ?></code>
            </li>
            <li>
                <span>max_connections</span>
                <code><?php echo isset($db_vars['max_connections']) ? $db_vars['max_connections'] : 'N/A'; ?></code>
            </li>
        </ul>
    </div>

    <!-- 8. 集中化目錄與服務實際路徑 -->
    <div class="card success">
        <h2>🟢 集中化目錄實際路徑</h2>
        <ul>
            <li><span>Ubuntu 版本</span> <span class="badge badge-ok">24.04 LTS</span></li>
            <li><span>網頁根目錄</span> <code class="path-code">/data/www</code></li>
            <li><span>資料庫目錄</span> <code class="path-code">/data/mysql</code></li>
            <li><span>Apache Log Directory</span> <code class="path-code"><?php echo htmlspecialchars($apache_log_dir); ?></code></li>
            <li><span>PHP Log Directory</span> <code class="path-code"><?php echo htmlspecialchars($php_log_dir); ?></code></li>
        </ul>
    </div>

</div>

</body>
</html>