<?php
$pma_installed = file_exists('/etc/phpmyadmin/config.inc.php');
?>
<!-- 8. phpMyAdmin 管理介面 -->
<div class="card <?php echo $pma_installed ? 'success' : 'danger'; ?>">
    <h2>🗄️ phpMyAdmin 管理介面</h2>
    <ul>
        <li>
            <span>模組狀態</span>
            <?php if ($pma_installed): ?>
                <span class="badge badge-ok">已安裝 (Ready)</span>
            <?php else: ?>
                <span class="badge badge-fail">未安裝 (Missing)</span>
            <?php endif; ?>
        </li>
        <li><span>入口網址</span> <code class="path-code">/phpmyadmin/</code></li>
    </ul>
    <?php if (!$pma_installed): ?>
        <?php if (!$mariadb_installed): ?>
            <button type="button" class="btn-install" style="background:#6c757d; cursor:not-allowed;" disabled>⚠️ 請先安裝 MariaDB</button>
        <?php else: ?>
            <button type="button" class="btn-install" onclick="startInstall('install_phpmyadmin', 'phpMyAdmin 管理介面安裝')">⚡ 一鍵安裝 phpMyAdmin</button>
        <?php endif; ?>
    <?php endif; ?>
</div>