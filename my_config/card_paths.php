<?php
$apache_log_dir = dirname(trim(shell_exec("grep -Ri 'CustomLog' /etc/apache2/sites-enabled/ 2>/dev/null | head -n1 | awk '{print $2}'") ?: '/data/logs/apache'));
$php_log_dir = ini_get('error_log') ? dirname(ini_get('error_log')) : '/data/logs/php';
?>
<!-- 9. 集中化目錄與服務實際路徑 -->
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