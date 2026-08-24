<?php
// ============================================================
// Ubuntu Web Server - Config Page
// File: my_config/index.php
// Description: Interactive Control Panel with MS SQL & Samba Setup (with SSE Log Streaming Modal)
// ============================================================

// ------------------------------------------------------------
// 1. SSE 即時安裝進度串流處理器
// ------------------------------------------------------------
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

        usleep(300000); // 0.3 秒輪詢
    }
    exit;
}

// ------------------------------------------------------------
// 2. 非同步背景安裝觸發器 (修復執行流程與權限卡死問題)
// ------------------------------------------------------------
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

echo "==> 更新套件並安裝編譯依賴 (unixodbc-dev / php-dev)..."
apt-get update
ACCEPT_EULA=Y apt-get install -y msodbcsql18 mssql-tools18 unixodbc-dev php-dev php-pear build-essential

echo "==> 透過 PECL 編譯 sqlsrv / pdo_sqlsrv..."
printf "\n" | pecl install sqlsrv pdo_sqlsrv || true

echo "==> 啟用 PHP 模組並重啟 Apache..."
echo "extension=sqlsrv.so" | tee /etc/php/8.3/mods-available/sqlsrv.ini
echo "extension=pdo_sqlsrv.so" | tee /etc/php/8.3/mods-available/pdo_sqlsrv.ini
phpenmod sqlsrv pdo_sqlsrv
systemctl restart apache2
echo "==> MS SQL 驅動安裝完成！"
) > /tmp/web_install.log 2>&1
if [ $? -eq 0 ]; then
    echo "SUCCESS" > /tmp/web_install.status
else
    echo "FAILED" > /tmp/web_install.status
fi
SHELL;
    } elseif ($action === 'install_samba') {
        $op_pass = getenv('OP_PASS') ?: 'KXP1AEEuAsaqDWn';
        $cmd = <<<SHELL
#!/usr/bin/env bash
(
set -e
echo "==> 開始安裝 Samba 套件..."
apt-get update && apt-get install -y samba

echo "==> 配置 /etc/samba/smb.conf ..."
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

echo "==> 設定 op 帳號與 Samba 密碼..."
printf "${op_pass}\n${op_pass}\n" | smbpasswd -a -s op
smbpasswd -e op
systemctl restart smbd
echo "==> Samba 網路芳鄰建置完成！"
) > /tmp/web_install.log 2>&1
if [ $? -eq 0 ]; then
    echo "SUCCESS" > /tmp/web_install.status
else
    echo "FAILED" > /tmp/web_install.status
fi
SHELL;
    }

    file_put_contents('/tmp/run_install.sh', $cmd);
    chmod('/tmp/run_install.sh', 0777);
    
    // 背景觸發：利用 sudo -n 免密碼直接調用生成好的 Shell 腳本
    exec("nohup sudo -n /tmp/run_install.sh > /dev/null 2>&1 &");

    echo json_encode(['status' => 'started']);
    exit;
}

$op_pass = getenv('OP_PASS') ?: 'KXP1AEEuAsaqDWn';
$mysql_root_pass = getenv('MYSQL_ROOT_PASS') ?: 'KXP1AEEuAsaqDWn';

// ------------------------------------------------------------
// 狀態檢測 Logic
// ------------------------------------------------------------
$has_mssql = extension_loaded('pdo_sqlsrv') || extension_loaded('sqlsrv');
$samba_installed = (trim(shell_exec("which smbd 2>/dev/null")) !== '');
$samba_running = (trim(shell_exec("systemctl is-active smbd 2>/dev/null")) === 'active');

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

$cron_status_file = '/data/.cron_status';
$cron_content = file_exists($cron_status_file) ? file_get_contents($cron_status_file) : '';
$has_backup_cron = (strpos($cron_content, '/usr/local/bin/backup_www.sh') !== false);

$apache_timeout = trim(shell_exec("apache2ctl -t -D DUMP_RUN_CFG 2>/dev/null | grep -i Timeout || grep -Ri '^Timeout' /etc/apache2/ 2>/dev/null | head -n1 | awk '{print $2}'") ?: '300 (Default)');
$apache_limit_req = trim(shell_exec("grep -Ri '^LimitRequestBody' /etc/apache2/ 2>/dev/null | head -n1 | awk '{print $2}'") ?: '0 (Unlimited)');
if (is_numeric($apache_limit_req) && $apache_limit_req > 0) {
    $apache_limit_req = round($apache_limit_req / 1024 / 1024, 1) . ' MB';
}

$apache_log_dir = dirname(trim(shell_exec("grep -Ri 'CustomLog' /etc/apache2/sites-enabled/ 2>/dev/null | head -n1 | awk '{print $2}'") ?: '/data/logs/apache'));
$php_log_dir = ini_get('error_log') ? dirname(ini_get('error_log')) : '/data/logs/php';
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
        .nav-bar a { display: inline-block; padding: 6px 12px; margin-left: 6px; border-radius: 4px; text-decoration: none; font-weight: bold; color: #fff; font-size: 0.85rem; }
        .btn-home { background-color: #28a745; }
        .btn-pma { background-color: #17a2b8; }

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

        /* Modal 浮動視窗樣式 */
        .modal-overlay { display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0, 0, 0, 0.6); z-index: 9999; justify-content: center; align-items: center; }
        .modal-overlay.active { display: flex; }
        .modal-box { background: #1e1e1e; color: #f1f1f1; width: 90%; max-width: 800px; border-radius: 8px; box-shadow: 0 4px 20px rgba(0,0,0,0.5); overflow: hidden; display: flex; flex-direction: column; max-height: 85vh; }
        .modal-header { background: #2d2d2d; padding: 12px 16px; display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #444; }
        .modal-header h3 { margin: 0; font-size: 1.1rem; color: #61dafb; }
        .modal-body { padding: 16px; overflow-y: auto; flex: 1; font-family: "Courier New", Courier, monospace; font-size: 0.88rem; background: #000; color: #00ff00; white-space: pre-wrap; word-break: break-all; }
        .modal-footer { background: #2d2d2d; padding: 12px 16px; display: flex; justify-content: space-between; align-items: center; border-top: 1px solid #444; }
        .btn-close-modal { background: #28a745; color: #fff; border: none; padding: 8px 16px; border-radius: 4px; cursor: pointer; font-weight: bold; display: none; }
        .btn-close-modal:hover { background: #218838; }

        @media (max-width: 1200px) { .card { flex: 0 0 calc(33.333% - 12px); } }
        @media (max-width: 768px) { .card { flex: 0 0 calc(50% - 12px); } }
        @media (max-width: 500px) { 
            .card { flex: 0 0 calc(100% - 12px); }
            .header-bar { flex-direction: column; gap: 8px; align-items: flex-start; }
        }
		/* 新增於 <style> 區段中 */
		@keyframes pulse-animation {
			0% { opacity: 0.3; }
			50% { opacity: 1; }
			100% { opacity: 0.3; }
		}
		.loading-pulse {
			animation: pulse-animation 1.5s infinite ease-in-out;
			color: #5bc0de !important;
			font-weight: bold;
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
            <li><span>SFTP / Samba 帳號</span> <code>op</code></li>
            <li><span>SFTP / Samba 密碼</span> <code><?php echo htmlspecialchars($op_pass); ?></code></li>
            <li><span>MariaDB Root 帳號</span> <code>root</code></li>
            <li><span>MariaDB Root 密碼</span> <code><?php echo htmlspecialchars($mysql_root_pass); ?></code></li>
        </ul>
    </div>

    <!-- 2. MS SQL 驅動狀態 -->
    <div class="card <?php echo $has_mssql ? 'success' : 'danger'; ?>">
        <h2>🗄️ MS SQL (2017+) 驅動</h2>
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
            <button type="button" class="btn-install" onclick="startInstall('install_mssql', 'MS SQL (2017+) 驅動安裝')">⚡ 一鍵安裝 MS SQL 驅動</button>
        <?php endif; ?>
    </div>

    <!-- 3. Samba 網路芳鄰設定 -->
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
            <li><span>連線位置</span> <code class="path-code">\\<?php echo htmlspecialchars($server_ip); ?>\web</code></li>
        </ul>
        <?php if (!$samba_installed): ?>
            <button type="button" class="btn-install" onclick="startInstall('install_samba', 'Samba 網路芳鄰設定')">⚡ 一鍵安裝 Samba 分享</button>
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

<!-- 安裝進度浮動視窗 (Modal) -->
<div id="installModal" class="modal-overlay">
    <div class="modal-box">
        <div class="modal-header">
            <h3 id="modalTitle">⚙️ 套件安裝中...</h3>
            <span id="modalStatusBadge" class="badge" style="background:#ffc107; color:#000;">執行中</span>
        </div>
        <div class="modal-body" id="modalLogConsole">正在初始化安裝程序...\n</div>
        <div class="modal-footer">
            <span id="modalHint" style="font-size:0.85rem; color:#aaa;">請勿關閉網頁，安裝執行中...</span>
            <button id="btnCloseModal" type="button" class="btn-close-modal" onclick="closeModalAndReload()">關閉視窗並重新整理</button>
        </div>
    </div>
</div>

<script>
let eventSource = null;

function startInstall(action, title) {
    if (!confirm('確定要開始執行 ' + title + ' 嗎？')) return;

    // 1. 初始化 Modal 標題與紀錄面板
    document.getElementById('modalTitle').innerText = '⚙️ ' + title;
    document.getElementById('modalLogConsole').innerText = '==> 準備開始執行程序...\n==> 正在建立背景任務，請稍候...\n';
    
    // 2. 設定狀態標籤
    const badge = document.getElementById('modalStatusBadge');
    badge.innerText = '執行中';
    badge.style.background = '#ffc107';
    badge.style.color = '#000';

    // 3. 設定提示文字與動態動畫
    const hint = document.getElementById('modalHint');
    hint.className = 'loading-pulse';
    hint.innerText = '⏳ 系統正在背景編譯與套件安裝中，請勿關閉網頁...';

    // 4. 隱藏關閉按鈕
    document.getElementById('btnCloseModal').style.display = 'none';

    // 5. 顯示 Modal 視窗
    document.getElementById('installModal').classList.add('active');

    // 6. 發送非同步請求觸發背景安裝
    const formData = new FormData();
    formData.append('action_async', action);

    fetch('index.php', { method: 'POST', body: formData })
        .then(res => res.json())
        .then(data => {
            if (data.status === 'started') {
                listenToStream();
            }
        })
        .catch(err => {
            document.getElementById('modalLogConsole').innerText += '\n❌ 觸發背景任務失敗，請重新整理頁面再試。';
            hint.className = '';
            hint.innerText = '發生錯誤，請重試。';
            document.getElementById('btnCloseModal').style.display = 'block';
        });
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
            const badge = document.getElementById('modalStatusBadge');
            const hint = document.getElementById('modalHint');
            const closeBtn = document.getElementById('btnCloseModal');

            if (data.status === 'SUCCESS') {
                badge.innerText = '完成';
                badge.style.background = '#28a745';
                badge.style.color = '#fff';
                hint.innerText = '安裝已成功完成！請點擊右側按鈕關閉視窗。';
            } else {
                badge.innerText = '失敗';
                badge.style.background = '#dc3545';
                badge.style.color = '#fff';
                hint.innerText = '安裝過程中發生錯誤，請檢查 Log 訊息。';
            }
            closeBtn.style.display = 'block';
        }
    };
}

function closeModalAndReload() {
    document.getElementById('installModal').classList.remove('active');
    window.location.reload();
}
</script>

</body>
</html>