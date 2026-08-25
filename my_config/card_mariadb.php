<?php
$mariadb_installed = (trim(shell_exec("which mariadb 2>/dev/null || which mysql 2>/dev/null")) !== '');
$mariadb_running = (trim(shell_exec("systemctl is-active mariadb 2>/dev/null")) === 'active');
$db_vars = [];
if ($mariadb_running) {
    try {
        $mysqli = @new mysqli("localhost", "root", $mysql_root_pass);
        if (!$mysqli->connect_error) {
            $res = $mysqli->query("SHOW VARIABLES WHERE Variable_name IN ('max_allowed_packet', 'max_connections')");
            while ($row = $res->fetch_assoc()) {
                $db_vars[$row['Variable_name']] = $row['Value'];
            }
            $mysqli->close();
        }
    } catch (Exception $e) {}
}
?>
<!-- 7. MariaDB 資料庫狀態與參數 -->
<div class="card <?php echo ($mariadb_installed && $mariadb_running) ? 'info' : 'danger'; ?>">
    <h2>🗄️ MariaDB 運作狀態</h2>
    <ul>
        <li>
            <span>服務狀態</span>
            <?php if ($mariadb_installed && $mariadb_running): ?>
                <span class="badge badge-ok">運作中 (Active)</span>
            <?php elseif ($mariadb_installed): ?>
                <span class="badge badge-fail">已安裝 (已停止)</span>
            <?php else: ?>
                <span class="badge badge-fail">未安裝 (Missing)</span>
            <?php endif; ?>
        </li>
        <li><span>資料庫路徑</span> <code class="path-code">/data/mysql</code></li>
        <li><span>max_allowed_packet</span> <code><?php echo isset($db_vars['max_allowed_packet']) ? round($db_vars['max_allowed_packet'] / 1024 / 1024, 1) . ' MB' : 'N/A'; ?></code></li>
    </ul>
    <?php if (!$mariadb_installed): ?>
        <button type="button" class="btn-install" onclick="startInstall('install_mariadb', 'MariaDB 資料庫服務安裝')">⚡ 一鍵安裝 MariaDB</button>
    <?php endif; ?>
</div>