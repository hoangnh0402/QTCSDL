-- =====================================================================
-- HaUI FORM - Script 01: Tạo tablespace và tài khoản schema HAUIFORM
-- Chạy bằng tài khoản SYS (AS SYSDBA) trên Oracle Database 19c
-- =====================================================================

-- #region pdb
-- Chuyển vào PDB chứa dữ liệu ứng dụng
ALTER SESSION SET CONTAINER = ORCLPDB1;

-- Lấy thư mục datafile của PDB (dùng được cho cả Windows và Linux)
COLUMN dir NEW_VALUE df_dir NOPRINT
SELECT SUBSTR(file_name, 1, GREATEST(INSTR(file_name, '/', -1),
                                     INSTR(file_name, '\', -1))) AS dir
  FROM dba_data_files
 WHERE tablespace_name = 'SYSTEM';
-- #endregion

-- #region tablespace
-- Tablespace chứa dữ liệu bảng và LOB
CREATE TABLESPACE ts_hf_data
  DATAFILE '&df_dir.hf_data01.dbf' SIZE 200M
  AUTOEXTEND ON NEXT 50M MAXSIZE 4G
  EXTENT MANAGEMENT LOCAL
  SEGMENT SPACE MANAGEMENT AUTO;

-- Tablespace riêng cho chỉ mục (index)
CREATE TABLESPACE ts_hf_index
  DATAFILE '&df_dir.hf_index01.dbf' SIZE 100M
  AUTOEXTEND ON NEXT 20M MAXSIZE 2G
  EXTENT MANAGEMENT LOCAL
  SEGMENT SPACE MANAGEMENT AUTO;
-- #endregion

-- #region user
-- Tài khoản sở hữu toàn bộ đối tượng CSDL của ứng dụng
CREATE USER hauiform IDENTIFIED BY "HaUIForm#2026"
  DEFAULT TABLESPACE ts_hf_data
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON ts_hf_data
  QUOTA UNLIMITED ON ts_hf_index;

GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE SEQUENCE,
      CREATE PROCEDURE, CREATE TRIGGER, CREATE TYPE,
      CREATE MATERIALIZED VIEW, CREATE JOB
   TO hauiform;
-- #endregion
