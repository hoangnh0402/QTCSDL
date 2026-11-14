#!/bin/bash
# Bật ARCHIVELOG + vùng phục hồi (FRA): điều kiện cho RMAN sao lưu trực tuyến
# và Flashback Database / điểm khôi phục bảo đảm.
mkdir -p /opt/oracle/oradata/fra
sqlplus -s / as sysdba <<'SQL'
SET FEEDBACK ON
ALTER SYSTEM SET db_recovery_file_dest_size = 10G SCOPE = BOTH;
ALTER SYSTEM SET db_recovery_file_dest = '/opt/oracle/oradata/fra' SCOPE = BOTH;
SHUTDOWN IMMEDIATE
STARTUP MOUNT
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;
ALTER PLUGGABLE DATABASE ALL OPEN;
ALTER PLUGGABLE DATABASE ALL SAVE STATE;
SELECT log_mode FROM v$database;
EXIT
SQL
