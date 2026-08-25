<?php
$apache_timeout = trim(shell_exec("apache2ctl -t -D DUMP_RUN_CFG 2>/dev/null | grep -i Timeout || grep -Ri '^Timeout' /etc/apache2/ 2>/dev/null | head -n1 | awk '{print $2}'") ?: '300 (Default)');
$apache_limit_req = trim(shell_exec("grep -Ri '^LimitRequestBody' /etc/apache2/ 2>/dev/null | head -n1 | awk '{print $2}'") ?: '0 (Unlimited)');
if (is_numeric($apache_limit_req) && $apache_limit_req > 0) {
    $apache_limit_req = round($apache_limit_req / 1024 / 1024, 1) . ' MB';
}
?>
<!-- 5. Apache 網頁伺服器參數 -->
<div class="card purple">
    <h2>🌐 Apache 設定參數</h2>
    <ul>
        <li><span>Timeout</span> <code><?php echo htmlspecialchars($apache_timeout); ?></code></li>
        <li><span>LimitRequestBody</span> <code><?php echo htmlspecialchars($apache_limit_req); ?></code></li>
        <li><span>VirtualHost 模式</span> <span class="badge badge-ok">SSL (443)</span></li>
    </ul>
</div>