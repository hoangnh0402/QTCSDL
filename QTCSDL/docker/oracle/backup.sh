#!/bin/bash
# =====================================================================
# Sao lưu HaUI Form (chạy trong container):
#   docker exec hauiform-oracle bash /opt/hauiform/docker/backup.sh
#   1. RMAN: sao lưu vật lý toàn bộ CSDL + archived log (trực tuyến)
#   2. Data Pump: sao lưu logic schema HAUIFORM
# =====================================================================
export NLS_LANG=AMERICAN_AMERICA.AL32UTF8
STAMP=$(date +%Y%m%d_%H%M)

echo "===== RMAN ====="
rman target / <<RMAN
CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 7 DAYS;
CONFIGURE CONTROLFILE AUTOBACKUP ON;
BACKUP AS COMPRESSED BACKUPSET DATABASE PLUS ARCHIVELOG TAG 'HF_FULL_${STAMP}';
LIST BACKUP SUMMARY;
REPORT OBSOLETE;
RMAN

echo "===== DATA PUMP ====="
expdp hauiform/'"HaUIForm#2026"'@//localhost:1521/${ORACLE_PDB:-ORCLPDB1} \
  SCHEMAS=hauiform DIRECTORY=data_pump_dir \
  DUMPFILE=hauiform_${STAMP}.dmp LOGFILE=hauiform_${STAMP}_exp.log \
  EXCLUDE=STATISTICS
