-- =====================================================================
-- HaUI FORM - Script 12: Flashback - bảo vệ dữ liệu khỏi lỗi người dùng
-- Kết nối bằng tài khoản HAUIFORM. Chạy SAU script 10.
-- Cơ chế dùng dữ liệu UNDO (Flashback Query, Version Query, Table)
-- và thùng rác RECYCLE BIN (Flashback Drop).
-- =====================================================================

-- #region fb_prepare
-- Flashback Table cần cho phép Oracle di chuyển dòng (ROWID có thể thay đổi)
ALTER TABLE forms ENABLE ROW MOVEMENT;

EXEC pkg_demo.reset_all;

-- Ghi lại SCN (System Change Number) hiện tại vào biến thay thế &scn_truoc
COLUMN scn NEW_VALUE scn_truoc
SELECT DBMS_FLASHBACK.GET_SYSTEM_CHANGE_NUMBER AS scn,
       TO_CHAR(SYSTIMESTAMP, 'HH24:MI:SS') AS thoi_diem
  FROM dual;
-- #endregion

-- #region fb_query
-- Tình huống 1: cán bộ cập nhật tiêu đề nhưng QUÊN mệnh đề WHERE
UPDATE forms SET title = 'Khảo sát thử nghiệm';
COMMIT;

SELECT form_id, title FROM forms ORDER BY form_id;

-- Flashback Query: xem dữ liệu như tại SCN trước khi cập nhật nhầm
SELECT form_id, title
  FROM forms AS OF SCN &scn_truoc
 ORDER BY form_id;
-- #endregion

-- #region fb_versions
-- Flashback Version Query: lịch sử mọi phiên bản của dòng biểu mẫu 1
SELECT versions_startscn                          AS scn_bat_dau,
       versions_endscn                            AS scn_ket_thuc,
       versions_operation                         AS thao_tac,
       versions_xid                               AS ma_giao_dich,
       SUBSTR(title, 1, 45)                       AS title
  FROM forms
       VERSIONS BETWEEN SCN &scn_truoc AND MAXVALUE
 WHERE form_id = 1
 ORDER BY versions_startscn NULLS FIRST;
-- #endregion

-- #region fb_table
-- Flashback Table: đưa cả bảng FORMS về SCN trước khi cập nhật nhầm
FLASHBACK TABLE forms TO SCN &scn_truoc;

SELECT form_id, SUBSTR(title, 1, 60) AS title FROM forms ORDER BY form_id;
-- #endregion

-- #region fb_delete
-- Tình huống 2: xóa nhầm toàn bộ phản hồi của biểu mẫu 1 (ANSWERS xóa theo dây chuyền)
COLUMN scn NEW_VALUE scn_truoc_xoa
SELECT DBMS_FLASHBACK.GET_SYSTEM_CHANGE_NUMBER AS scn FROM dual;

SELECT (SELECT COUNT(*) FROM responses WHERE form_id = 1) AS so_phan_hoi,
       (SELECT COUNT(*) FROM answers a JOIN responses r
                 ON r.response_id = a.response_id
         WHERE r.form_id = 1)                              AS so_cau_tra_loi
  FROM dual;

DELETE FROM responses WHERE form_id = 1;
COMMIT;

SELECT COUNT(*) AS so_phan_hoi_sau_xoa FROM responses WHERE form_id = 1;

-- Flashback Table không áp dụng được cho bảng phân vùng tham chiếu
FLASHBACK TABLE responses, answers TO SCN &scn_truoc_xoa;
-- ORA-08199: Flashback Table operation is not supported on this object
-- #endregion

-- #region fb_restore
-- Khôi phục có chọn lọc bằng Flashback Query: chỉ chép lại các dòng đã mất
INSERT INTO responses (response_id, form_id, respondent_id, once_key,
                       submitted_at, duration_sec, ip_address, user_agent)
SELECT response_id, form_id, respondent_id, once_key,
       submitted_at, duration_sec, ip_address, user_agent
  FROM responses AS OF SCN &scn_truoc_xoa
 WHERE form_id = 1
   AND response_id NOT IN (SELECT response_id FROM responses);

INSERT INTO answers (answer_id, response_id, question_id, option_id,
                     answer_text, answer_number, answer_date)
SELECT a.answer_id, a.response_id, a.question_id, a.option_id,
       a.answer_text, a.answer_number, a.answer_date
  FROM answers AS OF SCN &scn_truoc_xoa a
 WHERE a.response_id IN (SELECT response_id FROM responses
                          WHERE form_id = 1)
   AND a.answer_id NOT IN (SELECT answer_id FROM answers);
COMMIT;

SELECT (SELECT COUNT(*) FROM responses WHERE form_id = 1) AS so_phan_hoi,
       (SELECT COUNT(*) FROM answers a JOIN responses r
                 ON r.response_id = a.response_id
         WHERE r.form_id = 1)                              AS so_cau_tra_loi
  FROM dual;
-- #endregion

-- #region fb_audit
-- Dấu vết của thao tác xóa vẫn còn trong AUDIT_LOGS (bảng không bị quay lui)
SELECT table_name, operation, record_id,
       JSON_VALUE(old_values, '$.respondent_id') AS respondent_id,
       db_user, TO_CHAR(action_at, 'HH24:MI:SS') AS luc
  FROM audit_logs
 WHERE table_name = 'RESPONSES'
   AND action_at > SYSTIMESTAMP - INTERVAL '10' MINUTE
 ORDER BY log_id;
-- #endregion

-- #region fb_drop
-- Tình huống 3: xóa nhầm cả một bảng (Flashback Drop từ thùng rác)
CREATE TABLE kq_hk1_2026 AS
  SELECT form_id, question_no, label, votes, pct FROM v_option_stats;

DROP TABLE kq_hk1_2026;

SELECT object_name, original_name, operation,
       TO_CHAR(TO_DATE(droptime, 'YYYY-MM-DD:HH24:MI:SS'), 'HH24:MI:SS') AS luc_xoa
  FROM user_recyclebin
 WHERE original_name = 'KQ_HK1_2026';

FLASHBACK TABLE kq_hk1_2026 TO BEFORE DROP;

SELECT COUNT(*) AS so_dong FROM kq_hk1_2026;

-- Dọn dẹp: PURGE xóa hẳn, không đưa vào thùng rác
DROP TABLE kq_hk1_2026 PURGE;
-- #endregion
