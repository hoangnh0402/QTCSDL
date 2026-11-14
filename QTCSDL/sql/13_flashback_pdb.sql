-- =====================================================================
-- HaUI FORM - Script 13: Flashback Pluggable Database với điểm khôi phục
-- Chạy bằng SYS AS SYSDBA tại CDB$ROOT. Yêu cầu CSDL ở chế độ ARCHIVELOG
-- (xem docker/oracle/enable_archivelog.sh).
-- Kịch bản: trước khi triển khai phiên bản mới, tạo điểm khôi phục;
-- bản triển khai lỗi xóa mất dữ liệu -> quay cả PDB về điểm khôi phục.
-- =====================================================================

-- #region rp_check
SELECT log_mode, flashback_on FROM v$database;
-- #endregion

-- #region rp_create
ALTER SESSION SET CONTAINER = ORCLPDB1;

-- Điểm khôi phục bảo đảm: Oracle giữ đủ flashback log để quay về thời điểm này
CREATE RESTORE POINT rp_truoc_trien_khai GUARANTEE FLASHBACK DATABASE;

SELECT name, scn, guarantee_flashback_database AS guarantee,
       TO_CHAR(time, 'DD/MM/YYYY HH24:MI:SS') AS thoi_diem
  FROM v$restore_point;
-- #endregion

-- #region rp_damage
-- "Bản triển khai lỗi": xóa sạch dữ liệu khảo sát và một bảng
SELECT COUNT(*) AS so_phan_hoi FROM hauiform.responses;
TRUNCATE TABLE hauiform.answers;
DELETE FROM hauiform.responses;
COMMIT;
DROP TABLE hauiform.audit_logs PURGE;
SELECT COUNT(*) AS so_phan_hoi FROM hauiform.responses;
-- #endregion

-- #region rp_flashback
ALTER SESSION SET CONTAINER = CDB$ROOT;
ALTER PLUGGABLE DATABASE orclpdb1 CLOSE IMMEDIATE;
FLASHBACK PLUGGABLE DATABASE orclpdb1 TO RESTORE POINT rp_truoc_trien_khai;
ALTER PLUGGABLE DATABASE orclpdb1 OPEN RESETLOGS;
-- #endregion

-- #region rp_verify
ALTER SESSION SET CONTAINER = ORCLPDB1;
SELECT COUNT(*) AS so_phan_hoi FROM hauiform.responses;
SELECT COUNT(*) AS so_nhat_ky  FROM hauiform.audit_logs;
DROP RESTORE POINT rp_truoc_trien_khai;
-- #endregion
