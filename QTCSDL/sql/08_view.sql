-- =====================================================================
-- HaUI FORM - Script 08: View và Materialized View
-- Kết nối bằng tài khoản HAUIFORM. File lưu dạng UTF-8.
-- =====================================================================

-- #region v_user_public
-- Thông tin người dùng cho tầng ứng dụng, KHÔNG có cột password_hash.
-- Tài khoản ứng dụng chỉ được cấp quyền trên view này, không phải bảng USERS.
CREATE OR REPLACE VIEW v_user_public AS
SELECT u.user_id, u.username, u.full_name, u.email,
       u.user_type, u.user_role, u.status,
       d.dept_code, d.dept_name
  FROM users u
  LEFT JOIN departments d ON d.dept_id = u.dept_id
WITH READ ONLY;
-- #endregion

-- #region v_form_overview
-- Danh sách biểu mẫu kèm trạng thái tính toán, số chỗ còn lại
CREATE OR REPLACE VIEW v_form_overview AS
SELECT f.form_id, f.short_code, f.title, f.description, f.status,
       f.is_anonymous, f.require_login, f.limit_one_response,
       f.max_responses, f.response_count,
       f.max_responses - f.response_count               AS seats_left,
       f.open_at, f.close_at,
       CASE
         WHEN f.status = 'DRAFT'  THEN 'Bản nháp'
         WHEN f.status = 'CLOSED' THEN 'Đã đóng'
         WHEN f.open_at  > SYSTIMESTAMP THEN 'Chưa mở'
         WHEN f.close_at < SYSTIMESTAMP THEN 'Hết hạn'
         WHEN f.response_count >= f.max_responses THEN 'Đủ chỗ'
         ELSE 'Đang nhận phản hồi'
       END                                              AS state_label,
       CASE
         WHEN f.status = 'OPEN'
          AND (f.open_at  IS NULL OR f.open_at  <= SYSTIMESTAMP)
          AND (f.close_at IS NULL OR f.close_at >= SYSTIMESTAMP)
          AND (f.max_responses IS NULL
               OR f.response_count < f.max_responses)
         THEN 1 ELSE 0
       END                                              AS accepting,
       f.owner_id, u.full_name                          AS owner_name,
       d.dept_name                                      AS owner_dept,
       (SELECT COUNT(*) FROM questions q
         WHERE q.form_id = f.form_id)                   AS question_count,
       JSON_VALUE(f.settings, '$.category'
         RETURNING VARCHAR2(30) ERROR ON ERROR NULL ON EMPTY) AS category,
       JSON_VALUE(f.settings, '$.theme')                AS theme,
       JSON_VALUE(f.settings, '$.confirmationMessage')  AS confirm_message,
       f.created_at
  FROM forms f
  JOIN users u            ON u.user_id = f.owner_id
  LEFT JOIN departments d ON d.dept_id = u.dept_id
 WHERE f.deleted_at IS NULL
WITH READ ONLY;
-- #endregion

-- #region v_option_stats
-- Số lượt chọn và tỷ lệ từng phương án (hàm phân tích RATIO_TO_REPORT)
CREATE OR REPLACE VIEW v_option_stats AS
SELECT q.form_id,
       q.question_id,
       q.sort_order                                     AS question_no,
       q.title                                          AS question_title,
       q.question_type,
       o.option_id,
       o.sort_order                                     AS option_no,
       o.label,
       COUNT(a.answer_id)                               AS votes,
       ROUND(100 * RATIO_TO_REPORT(COUNT(a.answer_id))
                   OVER (PARTITION BY q.question_id), 1) AS pct
  FROM questions q
  JOIN question_options o ON o.question_id = q.question_id
  LEFT JOIN answers a     ON a.question_id = o.question_id
                         AND a.option_id   = o.option_id
 GROUP BY q.form_id, q.question_id, q.sort_order, q.title, q.question_type,
          o.option_id, o.sort_order, o.label;
-- #endregion

-- #region v_numeric_stats
-- Thống kê câu hỏi thang đo và câu hỏi số
CREATE OR REPLACE VIEW v_numeric_stats AS
SELECT q.form_id,
       q.question_id,
       q.sort_order                   AS question_no,
       q.title                        AS question_title,
       q.question_type,
       COUNT(a.answer_number)         AS answer_count,
       ROUND(AVG(a.answer_number), 2) AS avg_value,
       MIN(a.answer_number)           AS min_value,
       MAX(a.answer_number)           AS max_value,
       MEDIAN(a.answer_number)        AS median_value
  FROM questions q
  LEFT JOIN answers a ON a.question_id = q.question_id
 WHERE q.question_type IN ('LINEAR_SCALE', 'NUMBER')
 GROUP BY q.form_id, q.question_id, q.sort_order, q.title, q.question_type;
-- #endregion

-- #region v_response_list
-- Danh sách lượt phản hồi. View này KHÔNG tự che danh tính:
-- việc che respondent_id do chính sách VPD trên bảng RESPONSES đảm nhiệm,
-- nên mọi đường truy cập (view, báo cáo, công cụ SQL) đều được bảo vệ như nhau.
CREATE OR REPLACE VIEW v_response_list AS
SELECT r.response_id,
       r.form_id,
       f.title                                       AS form_title,
       f.is_anonymous,
       r.respondent_id,
       CASE
         WHEN r.respondent_id IS NOT NULL
           THEN u.full_name || ' (' || u.username || ')'
         WHEN f.require_login = 0 THEN 'Khách'
         ELSE '*** ẩn danh ***'
       END                                           AS respondent,
       r.ip_address,
       r.submitted_at,
       r.duration_sec,
       (SELECT COUNT(*) FROM answers a
         WHERE a.response_id = r.response_id)        AS answer_count
  FROM responses r
  JOIN forms f      ON f.form_id = r.form_id
  LEFT JOIN users u ON u.user_id = r.respondent_id;
-- #endregion

-- #region v_user_submissions
-- Mỗi người đã nộp biểu mẫu nào, bao nhiêu lần (giao diện dùng để ẩn nút Gửi)
CREATE OR REPLACE VIEW v_user_submissions AS
SELECT r.respondent_id      AS user_id,
       r.form_id,
       COUNT(*)             AS submit_count,
       MIN(r.submitted_at)  AS first_submitted,
       MAX(r.submitted_at)  AS last_submitted
  FROM responses r
 WHERE r.respondent_id IS NOT NULL
 GROUP BY r.respondent_id, r.form_id;
-- #endregion

-- #region v_daily_trend
-- Xu hướng theo ngày và lũy kế (hàm cửa sổ SUM ... OVER)
CREATE OR REPLACE VIEW v_daily_trend AS
SELECT form_id,
       TRUNC(submitted_at)                         AS submit_day,
       COUNT(*)                                    AS responses,
       ROUND(AVG(duration_sec))                    AS avg_duration_sec,
       SUM(COUNT(*)) OVER (PARTITION BY form_id
                           ORDER BY TRUNC(submitted_at)) AS cumulative
  FROM responses
 GROUP BY form_id, TRUNC(submitted_at);
-- #endregion

-- #region mv_monthly
-- Materialized view tổng hợp theo tháng: lưu sẵn kết quả, làm mới mỗi đêm
BEGIN
  EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW mv_monthly_responses';
EXCEPTION
  WHEN OTHERS THEN NULL;
END;
/

CREATE MATERIALIZED VIEW mv_monthly_responses
  TABLESPACE ts_hf_data
  BUILD IMMEDIATE
  REFRESH COMPLETE ON DEMAND
AS
SELECT r.form_id,
       TRUNC(r.submitted_at, 'MM')    AS month_start,
       COUNT(*)                       AS responses,
       ROUND(AVG(r.duration_sec), 1)  AS avg_duration_sec,
       COUNT(DISTINCT r.ip_address)   AS distinct_ip
  FROM responses r
 GROUP BY r.form_id, TRUNC(r.submitted_at, 'MM');

BEGIN
  DBMS_SCHEDULER.DROP_JOB('JOB_REFRESH_MV_MONTHLY', force => TRUE);
EXCEPTION
  WHEN OTHERS THEN NULL;
END;
/

BEGIN
  DBMS_SCHEDULER.CREATE_JOB(
    job_name        => 'JOB_REFRESH_MV_MONTHLY',
    job_type        => 'PLSQL_BLOCK',
    job_action      => 'BEGIN DBMS_MVIEW.REFRESH(''MV_MONTHLY_RESPONSES'', ''C''); END;',
    start_date      => TRUNC(SYSTIMESTAMP) + INTERVAL '1' DAY + INTERVAL '1' HOUR,
    repeat_interval => 'FREQ=DAILY; BYHOUR=1',
    enabled         => TRUE,
    comments        => 'Làm mới thống kê theo tháng lúc 01:00 hằng ngày');
END;
/
-- #endregion

-- #region check_views
SELECT view_name, read_only FROM user_views ORDER BY view_name;

SELECT mview_name, refresh_method, refresh_mode, last_refresh_date
  FROM user_mviews;
-- #endregion
