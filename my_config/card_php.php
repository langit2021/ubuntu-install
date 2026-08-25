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