<?php
$cron_status_file = '/data/.cron_status';
$cron_content = file_exists($cron_status_file) ? file_get_contents($cron_status_file) : '';
$has_backup_cron = (strpos($cron_content, '/usr/local/bin/backup_www.sh') !== false);
?>
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