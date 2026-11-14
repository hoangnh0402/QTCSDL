-- =====================================================================
-- HaUI FORM - Script 14: Truy vấn minh họa Trigger và View
-- Kết nối bằng tài khoản HAUIFORM. Chạy SAU script 10.
-- =====================================================================

-- #region q_trigger_block
-- (1) Sửa một phản hồi đã nộp -> TRG_RESPONSES_BU
UPDATE responses SET duration_sec = 1 WHERE response_id = 1;

-- (2) Xóa câu hỏi của biểu mẫu đã có phản hồi -> TRG_QUESTIONS_GUARD
DELETE FROM questions WHERE question_id = 4;

-- (3) Tắt "mỗi người một lần" khi đã có phản hồi -> TRG_FORMS_BU
UPDATE forms SET limit_one_response = 0 WHERE form_id = 1;

-- (4) Đưa biểu mẫu đã đóng về nháp -> TRG_FORMS_BU
UPDATE forms SET status = 'DRAFT' WHERE form_id = 3;
-- #endregion

-- #region q_trigger_audit
-- (5) Nâng quyền sinh viên 16 lên ADMIN rồi hạ lại, đóng biểu mẫu 2
UPDATE users SET user_role = 'ADMIN' WHERE user_id = 16;
UPDATE users SET user_role = 'USER'  WHERE user_id = 16;
UPDATE forms SET status = 'CLOSED'   WHERE form_id = 2;
COMMIT;

-- Nhật ký do TRG_USERS_AUDIT và TRG_FORMS_AUDIT ghi tự động
SELECT log_id, table_name AS bang, operation AS thao_tac, record_id AS ma,
       COALESCE(JSON_VALUE(old_values, '$.user_role'),
                JSON_VALUE(old_values, '$.status'))  AS gia_tri_cu,
       COALESCE(JSON_VALUE(new_values, '$.user_role'),
                JSON_VALUE(new_values, '$.status'))  AS gia_tri_moi,
       db_user, TO_CHAR(action_at, 'HH24:MI:SS')    AS luc
  FROM audit_logs
 WHERE table_name IN ('USERS', 'FORMS')
 ORDER BY log_id DESC
 FETCH FIRST 3 ROWS ONLY;

EXEC pkg_demo.reset_race;
-- #endregion

-- #region q_view_overview
-- Danh sách biểu mẫu với trạng thái tính toán từ view
SELECT form_id, short_code, state_label, accepting,
       max_responses AS so_cho, response_count AS da_nhan,
       seats_left AS con_lai, question_count AS so_cau, category
  FROM v_form_overview
 ORDER BY form_id;
-- #endregion

-- #region q_view_options
-- Tỷ lệ chọn từng phương án của biểu mẫu 1
SELECT question_no AS cau, label AS phuong_an, votes AS so_luot, pct AS ty_le
  FROM v_option_stats
 WHERE form_id = 1
 ORDER BY question_no, option_no;
-- #endregion

-- #region q_view_numeric
-- Thống kê câu hỏi số và xu hướng 5 ngày cuối của biểu mẫu 3
SELECT question_no AS cau, question_type, answer_count AS so_tl,
       avg_value AS tb, min_value AS nho_nhat, max_value AS lon_nhat,
       median_value AS trung_vi
  FROM v_numeric_stats
 WHERE form_id IN (1, 3)
 ORDER BY form_id, question_no;

SELECT TO_CHAR(submit_day, 'DD/MM/YYYY') AS ngay, responses AS phan_hoi,
       avg_duration_sec AS tg_tb_giay, cumulative AS luy_ke
  FROM v_daily_trend
 WHERE form_id = 3
 ORDER BY submit_day DESC
 FETCH FIRST 5 ROWS ONLY;
-- #endregion

-- #region q_view_readonly
-- View khai báo WITH READ ONLY không cho phép DML
UPDATE v_form_overview SET title = 'Sửa qua view' WHERE form_id = 1;
-- #endregion

-- #region q_mv
-- Làm mới và đọc materialized view tổng hợp theo tháng
EXEC DBMS_MVIEW.REFRESH('MV_MONTHLY_RESPONSES', 'C');

SELECT form_id, TO_CHAR(month_start, 'MM/YYYY') AS thang,
       responses AS phan_hoi, avg_duration_sec AS tg_tb_giay
  FROM mv_monthly_responses
 WHERE form_id = 3 AND month_start >= DATE '2026-06-01'
 ORDER BY month_start;

SELECT mview_name, refresh_method,
       TO_CHAR(last_refresh_date, 'DD/MM/YYYY HH24:MI:SS') AS lan_lam_moi
  FROM user_mviews;
-- #endregion
