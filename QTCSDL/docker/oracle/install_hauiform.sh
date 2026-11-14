#!/bin/bash
# =====================================================================
# Cài đặt toàn bộ CSDL HaUI Form vào PDB (chạy bên trong container Oracle)
#   docker exec hauiform-oracle bash /opt/hauiform/docker/install_hauiform.sh
# Được gọi tự động lần đầu qua /opt/oracle/scripts/setup.
# =====================================================================
set -u
export NLS_LANG=AMERICAN_AMERICA.AL32UTF8
SQL_DIR=/opt/hauiform/sql
PDB=${ORACLE_PDB:-ORCLPDB1}
APP_PWD='HaUIForm#2026'
LOG=/opt/oracle/oradata/hauiform_install.log
MARK=/opt/oracle/oradata/.hauiform_installed

run_sys() {
  echo ">>> [SYS] $1"
  sqlplus -s /nolog <<SQL
SET ECHO OFF FEEDBACK ON LINESIZE 200 PAGESIZE 100
CONNECT / AS SYSDBA
@${SQL_DIR}/$1
EXIT
SQL
}

run_app() {
  echo ">>> [HAUIFORM] $1"
  sqlplus -s /nolog <<SQL
SET ECHO OFF FEEDBACK ON LINESIZE 200 PAGESIZE 100
CONNECT hauiform/"${APP_PWD}"@//localhost:1521/${PDB}
@${SQL_DIR}/$1
EXIT
SQL
}

{
  echo "=== HaUI Form install: $(date)"
  run_sys 01_tao_tablespace_user.sql
  run_app 02_tao_bang.sql
  run_app 03_tao_index.sql
  run_app 04_du_lieu_mau.sql
  run_app 06_plsql.sql
  run_app 07_trigger.sql
  run_app 08_view.sql
  run_sys 09_bao_mat.sql
  run_app 10_du_lieu_demo.sql
  # Flashback Table cần ROW MOVEMENT (bật sẵn để trang Oracle Lab dùng được)
  sqlplus -s /nolog <<SQL
CONNECT hauiform/"${APP_PWD}"@//localhost:1521/${PDB}
ALTER TABLE forms ENABLE ROW MOVEMENT;
EXIT
SQL
  echo "=== Done: $(date)"
} 2>&1 | tee -a "$LOG"

touch "$MARK"
