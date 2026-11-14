-- =====================================================================
-- HaUI FORM - Script 09: Cơ chế bảo vệ người dùng và dữ liệu
-- Chạy bằng tài khoản SYS (AS SYSDBA). File lưu dạng UTF-8.
--   1. Profile: chính sách mật khẩu, khóa tài khoản khi đăng nhập sai
--   2. Role + tài khoản ứng dụng theo nguyên tắc đặc quyền tối thiểu
--   3. Application context + Virtual Private Database (mức dòng, mức cột)
--   4. Unified Auditing
-- =====================================================================

-- #region pdb
ALTER SESSION SET CONTAINER = ORCLPDB1;
-- #endregion

-- #region cleanup
-- Cho phép chạy lại script: xóa đối tượng bảo mật cũ nếu có
BEGIN
  FOR p IN (SELECT object_name, policy_name FROM dba_policies
             WHERE object_owner = 'HAUIFORM') LOOP
    DBMS_RLS.DROP_POLICY('HAUIFORM', p.object_name, p.policy_name);
  END LOOP;
  FOR a IN (SELECT DISTINCT policy_name FROM audit_unified_enabled_policies
             WHERE policy_name LIKE 'HF\_%' ESCAPE '\') LOOP
    EXECUTE IMMEDIATE 'NOAUDIT POLICY ' || a.policy_name;
  END LOOP;
  FOR a IN (SELECT DISTINCT policy_name FROM audit_unified_policies
             WHERE policy_name LIKE 'HF\_%' ESCAPE '\') LOOP
    EXECUTE IMMEDIATE 'DROP AUDIT POLICY ' || a.policy_name;
  END LOOP;
  FOR u IN (SELECT username FROM dba_users
             WHERE username IN ('HF_APP', 'HF_REPORT')) LOOP
    EXECUTE IMMEDIATE 'DROP USER ' || u.username || ' CASCADE';
  END LOOP;
  FOR r IN (SELECT role FROM dba_roles
             WHERE role IN ('HF_APP_ROLE', 'HF_REPORT_ROLE')) LOOP
    EXECUTE IMMEDIATE 'DROP ROLE ' || r.role;
  END LOOP;
  FOR p IN (SELECT DISTINCT profile FROM dba_profiles
             WHERE profile IN ('HF_USER_PROFILE', 'HF_APP_PROFILE')) LOOP
    EXECUTE IMMEDIATE 'DROP PROFILE ' || p.profile || ' CASCADE';
  END LOOP;
END;
/
-- #endregion

-- #region profile
-- Profile cho tài khoản con người (cán bộ báo cáo, quản trị)
CREATE PROFILE hf_user_profile LIMIT
  FAILED_LOGIN_ATTEMPTS    3          -- sai mật khẩu 3 lần thì khóa
  PASSWORD_LOCK_TIME       1/1440     -- khóa 1 phút (demo; thực tế 15-30 phút)
  PASSWORD_LIFE_TIME       90         -- đổi mật khẩu sau 90 ngày
  PASSWORD_GRACE_TIME      7
  PASSWORD_REUSE_TIME      365        -- không dùng lại mật khẩu trong 1 năm
  PASSWORD_REUSE_MAX       5
  PASSWORD_VERIFY_FUNCTION ora12c_verify_function   -- độ phức tạp mật khẩu
  SESSIONS_PER_USER        3
  -- ngắt phiên rỗi sau 30 phút
  IDLE_TIME                30;

-- Profile cho tài khoản dịch vụ của ứng dụng web (dùng connection pool)
CREATE PROFILE hf_app_profile LIMIT
  FAILED_LOGIN_ATTEMPTS    10
  PASSWORD_LOCK_TIME       1/24
  PASSWORD_LIFE_TIME       UNLIMITED
  SESSIONS_PER_USER        40;
-- #endregion

-- #region roles
-- Vai trò của ứng dụng: chỉ ĐỌC định nghĩa biểu mẫu và GỌI thủ tục.
-- Không có quyền INSERT / UPDATE / DELETE trên bất kỳ bảng nào:
-- mọi thay đổi dữ liệu phải đi qua gói PL/SQL đã kiểm tra nghiệp vụ.
CREATE ROLE hf_app_role;
GRANT SELECT  ON hauiform.forms              TO hf_app_role;
GRANT SELECT  ON hauiform.questions          TO hf_app_role;
GRANT SELECT  ON hauiform.question_options   TO hf_app_role;
GRANT SELECT  ON hauiform.v_user_public      TO hf_app_role;
GRANT SELECT  ON hauiform.v_form_overview    TO hf_app_role;
GRANT SELECT  ON hauiform.v_option_stats     TO hf_app_role;
GRANT SELECT  ON hauiform.v_numeric_stats    TO hf_app_role;
GRANT SELECT  ON hauiform.v_response_list    TO hf_app_role;
GRANT SELECT  ON hauiform.v_user_submissions TO hf_app_role;
GRANT SELECT  ON hauiform.v_daily_trend      TO hf_app_role;
GRANT EXECUTE ON hauiform.pkg_ctx            TO hf_app_role;
GRANT EXECUTE ON hauiform.pkg_response       TO hf_app_role;

-- Vai trò báo cáo: chỉ xem số liệu tổng hợp
CREATE ROLE hf_report_role;
GRANT SELECT ON hauiform.v_form_overview      TO hf_report_role;
GRANT SELECT ON hauiform.v_option_stats       TO hf_report_role;
GRANT SELECT ON hauiform.v_numeric_stats      TO hf_report_role;
GRANT SELECT ON hauiform.v_daily_trend        TO hf_report_role;
GRANT SELECT ON hauiform.v_response_list      TO hf_report_role;
GRANT SELECT ON hauiform.mv_monthly_responses TO hf_report_role;
-- #endregion

-- #region users
-- Tài khoản dịch vụ của ứng dụng web: không có quota, không tạo được đối tượng
CREATE USER hf_app IDENTIFIED BY "HfApp#2026"
  PROFILE hf_app_profile
  DEFAULT TABLESPACE ts_hf_data;
GRANT CREATE SESSION, hf_app_role TO hf_app;

-- Tài khoản của cán bộ khảo thí: xem báo cáo, chịu chính sách mật khẩu chặt
CREATE USER hf_report IDENTIFIED BY "BaoCao#2026"
  PROFILE hf_user_profile
  DEFAULT TABLESPACE ts_hf_data;
GRANT CREATE SESSION, hf_report_role TO hf_report;

-- Chủ schema chỉ dùng cho bảo trì (không bao giờ dùng cho ứng dụng) nên được miễn VPD.
-- Nếu không, xóa dây chuyền RESPONSES -> ANSWERS bị chặn bởi ORA-42804.
GRANT EXEMPT ACCESS POLICY TO hauiform;

-- Quyền bổ sung cho chủ schema phục vụ Flashback, xem nhật ký kiểm toán, Data Pump
GRANT EXECUTE ON DBMS_FLASHBACK TO hauiform;
GRANT AUDIT_VIEWER TO hauiform;
GRANT READ, WRITE ON DIRECTORY data_pump_dir TO hauiform;
-- #endregion

-- #region context
-- Chỉ gói HAUIFORM.PKG_CTX được phép ghi vào ngữ cảnh HF_CTX
CREATE OR REPLACE CONTEXT hf_ctx USING hauiform.pkg_ctx;
-- #endregion

-- #region vpd
BEGIN
  -- (1) Mức dòng trên RESPONSES
  DBMS_RLS.ADD_POLICY(
    object_schema   => 'HAUIFORM',
    object_name     => 'RESPONSES',
    policy_name     => 'POL_RESPONSES_ROWS',
    function_schema => 'HAUIFORM',
    policy_function => 'PKG_VPD.RESPONSES_ROWS',
    statement_types => 'SELECT',
    policy_type     => DBMS_RLS.CONTEXT_SENSITIVE);

  -- (2) Mức cột: che danh tính người trả lời của biểu mẫu ẩn danh (QT09)
  DBMS_RLS.ADD_POLICY(
    object_schema         => 'HAUIFORM',
    object_name           => 'RESPONSES',
    policy_name           => 'POL_RESPONSES_IDENTITY',
    function_schema       => 'HAUIFORM',
    policy_function       => 'PKG_VPD.RESPONSES_IDENTITY',
    statement_types       => 'SELECT',
    sec_relevant_cols     => 'RESPONDENT_ID, IP_ADDRESS, USER_AGENT',
    sec_relevant_cols_opt => DBMS_RLS.ALL_ROWS,
    policy_type           => DBMS_RLS.CONTEXT_SENSITIVE);

  -- (3) Mức dòng trên ANSWERS
  DBMS_RLS.ADD_POLICY(
    object_schema   => 'HAUIFORM',
    object_name     => 'ANSWERS',
    policy_name     => 'POL_ANSWERS_ROWS',
    function_schema => 'HAUIFORM',
    policy_function => 'PKG_VPD.ANSWERS_ROWS',
    statement_types => 'SELECT',
    policy_type     => DBMS_RLS.CONTEXT_SENSITIVE);
END;
/
-- #endregion

-- #region audit
-- Ghi lại mọi thao tác xóa / sửa dữ liệu khảo sát, bất kể từ công cụ nào
CREATE AUDIT POLICY hf_pol_data_change
  ACTIONS DELETE ON hauiform.responses,
          DELETE ON hauiform.answers,
          UPDATE ON hauiform.forms,
          DELETE ON hauiform.forms,
          UPDATE ON hauiform.users;
AUDIT POLICY hf_pol_data_change;

-- Ghi lại truy cập trực tiếp vào bảng RESPONSES từ ngoài ứng dụng
CREATE AUDIT POLICY hf_pol_direct_read
  ACTIONS SELECT ON hauiform.responses
  WHEN 'SYS_CONTEXT(''USERENV'', ''SESSION_USER'') NOT IN (''HF_APP'', ''HAUIFORM'')'
  EVALUATE PER STATEMENT;
AUDIT POLICY hf_pol_direct_read;

-- Ghi lại các lần đăng nhập thất bại (dò mật khẩu)
CREATE AUDIT POLICY hf_pol_logon ACTIONS LOGON;
AUDIT POLICY hf_pol_logon WHENEVER NOT SUCCESSFUL;

-- Ghi lại thao tác cấp / thu hồi quyền và quản lý tài khoản
CREATE AUDIT POLICY hf_pol_security
  ACTIONS CREATE USER, ALTER USER, DROP USER,
          GRANT, REVOKE, CREATE ROLE, DROP ROLE;
AUDIT POLICY hf_pol_security;
-- #endregion

-- #region check_security
SELECT username, account_status, profile
  FROM dba_users
 WHERE username IN ('HAUIFORM', 'HF_APP', 'HF_REPORT')
 ORDER BY username;

SELECT grantee, privilege, COUNT(*) AS so_doi_tuong
  FROM dba_tab_privs
 WHERE grantee IN ('HF_APP_ROLE', 'HF_REPORT_ROLE')
 GROUP BY grantee, privilege
 ORDER BY grantee, privilege;

SELECT object_name, policy_name, sel, ins, upd, del, policy_type
  FROM dba_policies
 WHERE object_owner = 'HAUIFORM'
 ORDER BY object_name, policy_name;

SELECT policy_name, enabled_option, success, failure
  FROM audit_unified_enabled_policies
 WHERE policy_name LIKE 'HF\_%' ESCAPE '\'
 ORDER BY policy_name;
-- #endregion
