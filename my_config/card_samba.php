<?php
$samba_installed = (trim(shell_exec("which smbd 2>/dev/null")) !== '');
$samba_running = (trim(shell_exec("systemctl is-active smbd 2>/dev/null")) === 'active');
?>
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