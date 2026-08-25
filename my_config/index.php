<?php
// ============================================================
// Ubuntu Web Server - Config Page (Modular Version)
// File: my_config/index.php
// ============================================================

// 1. SSE 即時日誌串流處理器
if (isset($_GET['api']) && $_GET['api'] === 'stream_log') {
    header('Content-Type: text/event-stream');
    header('Cache-Control: no-cache');
    header('Connection: keep-alive');

    $log_file = '/tmp/web_install.log';
    $status_file = '/tmp/web_install.status';

    $last_pos = 0;
    while (true) {
        if (file_exists($log_file)) {
            clearstatcache(true, $log_file);
            $current_len = filesize($log_file);
            if ($current_len > $last_pos) {
                $f = fopen($log_file, 'rb');
                fseek($f, $last_pos);
                while (!feof($f)) {
                    $line = fgets($f);
                    if ($line !== false) {
                        echo "data: " . json_encode(['line' => $line]) . "\n\n";
                        ob_flush();
                        flush();
                    }
                }
                $last_pos = ftell($f);
                fclose($f);
            }
        }

        if (file_exists($status_file)) {
            $status = trim(file_get_contents($status_file));
            echo "data: " . json_encode(['status' => $status]) . "\n\n";
            ob_flush();
            flush();
            break;
        }
        usleep(300000);
    }
    exit;
}

// 2. 一鍵更新所有卡片/模組 API (修復 state 與 log 寫入)
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action_async']) && $_POST['action_async'] === 'update_all_modules') {
    header('Content-Type: application/json');
    
    file_put_contents('/tmp/web_install.log', "==> 開始從 GitHub 下載與更新所有卡片組件...\n");
    file_put_contents('/tmp/web_install.status', 'RUNNING');

    $git_account = "langit2021";
    $git_project = "ubuntu-install";
    
    $files = [
        'index.php', 'card_credentials.php', 'card_mssql.php', 'card_samba.php',
        'card_backup.php', 'card_apache.php', 'card_php.php', 'card_mariadb.php',
        'card_pma.php', 'card_paths.php'
    ];
    
    // 設定 HTTP header 避免被 GitHub 阻擋
    $opts = [
        'http' => [
            'method' => "GET",
            'header' => "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64)\r\n"
        ]
    ];
    $context = stream_context_create($opts);

    $success_count = 0;
    $total_files = count($files);

    foreach ($files as $file) {
        $url = "https://raw.githubusercontent.com/{$git_account}/{$git_project}/main/my_config/{$file}";
		$timestamp = time();
		$url = "https://raw.githubusercontent.com/{$git_account}/{$git_project}/main/my_config/{$file}?v={$timestamp}";

        file_put_contents('/tmp/web_install.log', "正在下載: {$file} ... ", FILE_APPEND);
        
        $content = @file_get_contents($url, false, $context);
        if ($content !== false && !empty($content)) {
            $dest = "/data/my_config/{$file}";
            file_put_contents($dest, $content);
            chmod($dest, 0775);
            @chown($dest, 'op');
            file_put_contents('/tmp/web_install.log', "[ OK ]\n", FILE_APPEND);
            $success_count++;
        } else {
            file_put_contents('/tmp/web_install.log', "[ FAILED ]\n", FILE_APPEND);
        }
    }

    if ($success_count === $total_files) {
        file_put_contents('/tmp/web_install.log', "==> 所有卡片組件更新完成！\n", FILE_APPEND);
        file_put_contents('/tmp/web_install.status', 'SUCCESS');
    } else {
        file_put_contents('/tmp/web_install.log', "==> 部分組件下載失敗 ({$success_count}/{$total_files})\n", FILE_APPEND);
        file_put_contents('/tmp/web_install.status', 'FAILED');
    }

    echo json_encode(['status' => 'started']);
    exit;
}

// 3. 非同步背景安裝處理器
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action_async'])) {
    header('Content-Type: application/json');
    $action = $_POST['action_async'];
    
    file_put_contents('/tmp/web_install.log', '');
    file_put_contents('/tmp/web_install.status', 'RUNNING');
    @unlink('/tmp/run_install.sh');

    if ($action === 'install_mssql') {
        $cmd = <<<'SHELL'
#!/usr/bin/env bash
(
set -e
export DEBIAN_FRONTEND=noninteractive
echo "==> 開始設定 Microsoft 套件源..."
if [ ! -f /etc/apt/sources.list.d/mssql-release.list ]; then
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg --yes
    curl -fsSL https://packages.microsoft.com/config/ubuntu/24.04/prod.list | tee /etc/apt/sources.list.d/mssql-release.list
fi
apt-get update
ACCEPT_EULA=Y apt-get install -y msodbcsql18 mssql-tools18 unixodbc-dev php-dev php-pear build-essential
printf "\n" | pecl install sqlsrv pdo_sqlsrv || true
echo "extension=sqlsrv.so" | tee /etc/php/8.3/mods-available/sqlsrv.ini
echo "extension=pdo_sqlsrv.so" | tee /etc/php/8.3/mods-available/pdo_sqlsrv.ini
phpenmod sqlsrv pdo_sqlsrv
systemctl restart apache2
echo "==> MS SQL 驅動安裝完成！"
) > /tmp/web_install.log 2>&1
if [ $? -eq 0 ]; then echo "SUCCESS" > /tmp/web_install.status; else echo "FAILED" > /tmp/web_install.status; fi
SHELL;
    } elseif ($action === 'install_samba') {
        $op_pass = getenv('OP_PASS') ?: 'KXP1AEEuAsaqDWn';
        $cmd = <<<SHELL
#!/usr/bin/env bash
(
set -e
apt-get update && apt-get install -y samba
if ! grep -q '\[web\]' /etc/samba/smb.conf; then
    cat >> /etc/samba/smb.conf <<CONF

[web]
   comment = Data Central Directory
   path = /data
   browseable = yes
   writable = yes
   guest ok = no
   valid users = op
   force user = op
   force group = www-data
   create mask = 0775
   directory mask = 0775
   follow symlinks = yes
   wide links = yes
CONF
fi
printf "${op_pass}\n${op_pass}\n" | smbpasswd -a -s op
smbpasswd -e op
systemctl restart smbd
echo "==> Samba 網路芳鄰建置完成！"
) > /tmp/web_install.log 2>&1
if [ $? -eq 0 ]; then echo "SUCCESS" > /tmp/web_install.status; else echo "FAILED" > /tmp/web_install.status; fi
SHELL;
    } elseif ($action === 'install_mariadb') {
        $mysql_root_pass = getenv('MYSQL_ROOT_PASS') ?: 'KXP1AEEuAsaqDWn';
        $cmd = <<<SHELL
#!/usr/bin/env bash
(
set -e
export DEBIAN_FRONTEND=noninteractive
systemctl stop mariadb 2>/dev/null || true
mkdir -p /data/mysql
rm -rf /var/lib/mysql/* /data/mysql/*
apt-get update && apt-get install -y mariadb-server mariadb-client
systemctl stop mariadb
if [ -d "/var/lib/mysql" ] && [ -f "/var/lib/mysql/ibdata1" ]; then
    rsync -av /var/lib/mysql/ /data/mysql/
fi
sed -i "s|datadir\s*=\s*/var/lib/mysql|datadir = /data/mysql|g" /etc/mysql/mariadb.conf.d/50-server.cnf
chown -R mysql:mysql /data/mysql
systemctl enable mariadb
systemctl start mariadb
mysql <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${mysql_root_pass}';
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
echo "==> MariaDB 安裝與設定完成！"
) > /tmp/web_install.log 2>&1
if [ $? -eq 0 ]; then echo "SUCCESS" > /tmp/web_install.status; else echo "FAILED" > /tmp/web_install.status; fi
SHELL;
    } elseif ($action === 'install_phpmyadmin') {
        $mysql_root_pass = getenv('MYSQL_ROOT_PASS') ?: 'KXP1AEEuAsaqDWn';
        $pma_pass = getenv('PMA_PASS') ?: 'KXP1AEEuAsaqDWn';
        $cmd = <<<SHELL
#!/usr/bin/env bash
(
set -e
export DEBIAN_FRONTEND=noninteractive
echo "phpmyadmin phpmyadmin/dbconfig-install boolean false" | debconf-set-selections
echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2" | debconf-set-selections
apt-get update && apt-get install -y phpmyadmin
a2enconf phpmyadmin
if [ -f /etc/phpmyadmin/config.inc.php ]; then
    if ! grep -q "AllowRoot" /etc/phpmyadmin/config.inc.php; then
        echo "\$cfg['Servers'][\$i]['AllowRoot'] = TRUE;" >> /etc/phpmyadmin/config.inc.php
    fi
fi
mysql -u root -p"${mysql_root_pass}" <<EOF
CREATE DATABASE IF NOT EXISTS phpmyadmin;
CREATE USER IF NOT EXISTS 'phpmyadmin'@'localhost' IDENTIFIED BY '${pma_pass}';
ALTER USER 'phpmyadmin'@'localhost' IDENTIFIED BY '${pma_pass}';
GRANT ALL PRIVILEGES ON phpmyadmin.* TO 'phpmyadmin'@'localhost';
FLUSH PRIVILEGES;
EOF
if [ -f /usr/share/phpmyadmin/sql/create_tables.sql ]; then
    mysql --batch -u root -p"${mysql_root_pass}" phpmyadmin < /usr/share/phpmyadmin/sql/create_tables.sql 2>/dev/null || true
fi
rm -f /etc/phpmyadmin/config-db.php
cat > /etc/phpmyadmin/config-db.php <<EOF
<?php
\$dbuser='phpmyadmin';
\$dbpass='${pma_pass}';
\$basepath='';
\$dbname='phpmyadmin';
\$dbserver='localhost';
\$dbport='3306';
\$dbtype='mysql';
EOF
chmod 660 /etc/phpmyadmin/config-db.php
chown root:www-data /etc/phpmyadmin/config-db.php
systemctl restart apache2
echo "==> phpMyAdmin 安裝與設定完成！"
) > /tmp/web_install.log 2>&1
if [ $? -eq 0 ]; then echo "SUCCESS" > /tmp/web_install.status; else echo "FAILED" > /tmp/web_install.status; fi
SHELL;
    }

    file_put_contents('/tmp/run_install.sh', $cmd);
    chmod('/tmp/run_install.sh', 0777);
    exec("nohup sudo -n /tmp/run_install.sh > /dev/null 2>&1 &");
    echo json_encode(['status' => 'started']);
    exit;
}

$op_pass = getenv('OP_PASS') ?: 'KXP1AEEuAsaqDWn';
$mysql_root_pass = getenv('MYSQL_ROOT_PASS') ?: 'KXP1AEEuAsaqDWn';
$server_ip = $_SERVER['SERVER_ADDR'] ?? $_SERVER['HTTP_HOST'] ?? 'YOUR_SERVER_IP';
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
        .nav-bar a, .nav-bar button { display: inline-block; padding: 6px 12px; margin-left: 6px; border-radius: 4px; text-decoration: none; font-weight: bold; color: #fff; font-size: 0.85rem; border: none; cursor: pointer; }
        .btn-home { background-color: #28a745; }
        .btn-pma { background-color: #17a2b8; }
        .btn-update { background-color: #6c757d; }
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
        .btn-install { background: #007bff; color: white; border: none; padding: 6px 12px; border-radius: 4px; cursor: pointer; font-weight: bold; font-size: 0.8rem; width: 100%; margin-top: 6px; }
        .modal-overlay { display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0, 0, 0, 0.6); z-index: 9999; justify-content: center; align-items: center; }
        .modal-overlay.active { display: flex; }
        .modal-box { background: #1e1e1e; color: #f1f1f1; width: 90%; max-width: 800px; border-radius: 8px; flex-direction: column; max-height: 85vh; display: flex; }
        .modal-header { background: #2d2d2d; padding: 12px 16px; display: flex; justify-content: space-between; align-items: center; }
        .modal-body { padding: 16px; overflow-y: auto; flex: 1; font-family: monospace; font-size: 0.88rem; background: #000; color: #00ff00; white-space: pre-wrap; }
        .modal-footer { background: #2d2d2d; padding: 12px 16px; display: flex; justify-content: space-between; align-items: center; }
        .btn-close-modal { background: #28a745; color: #fff; border: none; padding: 8px 16px; border-radius: 4px; cursor: pointer; display: none; }
        @media (max-width: 1200px) { .card { flex: 0 0 calc(33.333% - 12px); } }
        @media (max-width: 768px) { .card { flex: 0 0 calc(50% - 12px); } }
        @media (max-width: 500px) { .card { flex: 0 0 calc(100% - 12px); } }
    </style>
</head>
<body>

<div class="header-bar">
    <div>
        <h1 style="display:inline-block; margin-right:10px;">Ubuntu Web Server 系統組態資訊</h1>
        <span style="font-size:0.8rem; color:#6c757d; font-weight:normal;">
            主頁面版本: <code><?php echo date("Y-m-d H:i:s", filemtime(__FILE__)); ?></code>
        </span>
    </div>
    <div class="nav-bar">
        <button onclick="updateAllModules()" class="btn-update">🔄 更新卡片組件</button>
        <a href="/" class="btn-home">🏠 返回首頁</a>
        <a href="/phpmyadmin/" target="_blank" class="btn-pma">🗄️ phpMyAdmin</a>
    </div>
</div>

<div class="card-grid">
    <?php
    // 動態載入 8 個獨立卡片組件
    $cards = [
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
    foreach ($cards as $card) {
        $file_path = __DIR__ . '/' . $card;
        if (file_exists($file_path)) {
            include $file_path;
        } else {
            echo "<div class='card danger'><h2>⚠️ 缺失組件</h2><p>無法載入 {$card}</p></div>";
        }
    }
    ?>
</div>

<div id="installModal" class="modal-overlay">
    <div class="modal-box">
        <div class="modal-header">
            <h3 id="modalTitle">⚙️ 程序執行中...</h3>
            <span id="modalStatusBadge" class="badge" style="background:#ffc107; color:#000;">執行中</span>
        </div>
        <div class="modal-body" id="modalLogConsole">初始化中...\n</div>
        <div class="modal-footer">
            <span id="modalHint" style="font-size:0.85rem; color:#aaa;">請稍候...</span>
            <button id="btnCloseModal" type="button" class="btn-close-modal" onclick="closeModalAndReload()">關閉視窗並重新整理</button>
        </div>
    </div>
</div>

<script>
let eventSource = null;
function startInstall(action, title) {
    if (!confirm('確定要執行 ' + title + ' 嗎？')) return;
    document.getElementById('modalTitle').innerText = '⚙️ ' + title;
    document.getElementById('modalLogConsole').innerText = '==> 準備開始執行程序...\n';
    document.getElementById('btnCloseModal').style.display = 'none';
    document.getElementById('installModal').classList.add('active');

    const formData = new FormData();
    formData.append('action_async', action);

    fetch('index.php', { method: 'POST', body: formData })
        .then(res => res.json())
        .then(data => { if (data.status === 'started') listenToStream(); });
}

function updateAllModules() {
    if (!confirm('確定要從 GitHub 重新下載並更新所有獨立卡片組件嗎？')) return;
    startInstall('update_all_modules', '更新所有卡片組件');
}

function listenToStream() {
    if (eventSource) eventSource.close();
    eventSource = new EventSource('index.php?api=stream_log');
    const logConsole = document.getElementById('modalLogConsole');
    eventSource.onmessage = function(e) {
        const data = JSON.parse(e.data);
        if (data.line) {
            logConsole.innerText += data.line;
            logConsole.scrollTop = logConsole.scrollHeight;
        }
        if (data.status) {
            eventSource.close();
            document.getElementById('modalStatusBadge').innerText = (data.status === 'SUCCESS') ? '完成' : '失敗';
            document.getElementById('btnCloseModal').style.display = 'block';
        }
    };
}
function closeModalAndReload() { window.location.reload(); }
</script>

</body>
</html>