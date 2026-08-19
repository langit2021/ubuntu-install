# 🚀 Ubuntu 24.04 LTS Web Server 一鍵式極速自動化部署腳本

本專案提供一套專為 **Ubuntu Server 24.04 LTS** 設計的高效能 LAMP (Linux, Apache, MariaDB, PHP) 模組化自動化部署工具。

設計理念強調 **「集中化管理 (/data)」、「狀態可追溯（可中斷後續行）」、「安全性隔離」** 以及 **「輕量視覺化監控 Dashboard」**。適合用於新伺服器建置、測試環境快速復原或標準化維護。

---

## ✨ 核心特色與架構理念

* 集中化架構 (`/data`)
  * **網頁根目錄**：`/data/www`
  * **資料庫目錄**：`/data/mysql` (完全將 MariaDB 資料搬移至此)
  * **集中日誌管理**：`/data/logs/apache` 與 `/data/logs/php`
  * **自動備份目錄**：`/data/backup`
* 斷點續傳機制 (Checkpoint System)
  * 全指令碼分為 14 個章節段落。每次執行完畢會自動記錄進度於 `/data/.install_progress`。
  * 若安裝中途因網路或意外中斷，**重新執行將自動跳過已完成的章節**，節省重複建置時間。
* 資料庫安全重置機制
  * 專為初始建置設計。執行 MariaDB 章節時，會先徹底清理既有資料庫殘留檔案，確保每次重跑都能 100% 成功建置乾淨的環境。
* SFTP 權限限縮 (Chroot Jail)
  * 建立專屬維護帳號 `op`。
  * 透過 OpenSSH 的 Chroot 技術，將 `op` 帳號的 SFTP 活動範圍**嚴格限制在 `/data` 目錄下**，防止任意切換至系統根目錄 `/`[cite: 4]。
* 輕量卡片式管理控制台 (/my_config)
  * 部署完畢後自動提供輕量 Web 監控介面 (`https://IP/my_config/`)。
  * **橫向 4 欄緊湊型卡片設計**，直觀呈現 PHP、Apache、MariaDB 核心參數、SSH 帳密與 Cron 排程狀態。
* 自動化備份排程
  * 內建 Cron 任務，每日凌晨 03:00 自動將 `/data/www` 打包壓縮並備份至 `/data/backup`，並自動循環清理超過 7 天的舊備份。

---

## 🛠️ 環境需求

* **作業系統**：Ubuntu Server 24.04 LTS (x86_64)
* **執行權限**：`root` 權限 (或使用 `sudo`)

---

## 📥 快速使用指南

### 1. 下載專案與執行安裝

直接拉取腳本並以 Root 權限執行：
curl -sL https://raw.githubusercontent.com/langit2021/ubuntu-install/main/install.sh | sudo bash


```bash
git clone [https://github.com/langit2021/ubuntu-install.git](https://github.com/langit2021/ubuntu-install.git)
cd ubuntu-install
chmod +x install.sh my_config.sh
sudo ./install.sh