-- 欄位順序就是 log_server 的 INSERT … VALUES 順序，改欄位兩邊一起改。
-- 放在 /docker-entrypoint-initdb.d，只在資料目錄第一次初始化時執行，改 schema 要清資料卷。
CREATE TABLE IF NOT EXISTS history (
  Hostname VARCHAR(50),
  Username VARCHAR(50),
  Time VARCHAR(50),
  Command VARCHAR(255)
);
CREATE TABLE IF NOT EXISTS inotify (
  Hostname VARCHAR(50),
  Time VARCHAR(50),
  Event VARCHAR(20),
  Path VARCHAR(255)
);
