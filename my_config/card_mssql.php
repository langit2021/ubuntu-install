<?php $has_mssql = extension_loaded('pdo_sqlsrv') || extension_loaded('sqlsrv'); ?>
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