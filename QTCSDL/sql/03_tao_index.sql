-- =====================================================================
-- HaUI FORM - Script 03: Tạo chỉ mục (index)
-- Kết nối bằng tài khoản HAUIFORM
-- =====================================================================

-- #region idx_users_forms
-- Tra cứu người dùng theo đơn vị, đồng thời là index cho khóa ngoại
CREATE INDEX ix_users_dept ON users (dept_id)
  TABLESPACE ts_hf_index;

-- Danh sách biểu mẫu của một người tạo, sắp xếp theo thời gian
CREATE INDEX ix_forms_owner ON forms (owner_id, created_at)
  TABLESPACE ts_hf_index;

-- Job tự động đóng biểu mẫu: tìm form OPEN đã quá close_at
CREATE INDEX ix_forms_status_close ON forms (status, close_at)
  TABLESPACE ts_hf_index;

-- Index hàm (function-based) trên thuộc tính JSON "category"
CREATE INDEX ix_forms_category ON forms (
  JSON_VALUE(settings, '$.category'
             RETURNING VARCHAR2(30) ERROR ON ERROR NULL ON EMPTY))
  TABLESPACE ts_hf_index;

-- Các biểu mẫu được chia sẻ cho một người dùng
CREATE INDEX ix_fc_user ON form_collaborators (user_id)
  TABLESPACE ts_hf_index;
-- #endregion

-- #region idx_responses
-- Index cục bộ (LOCAL): mỗi phân vùng của RESPONSES có một phân vùng index
CREATE INDEX ix_responses_form_time
  ON responses (form_id, submitted_at) LOCAL;

CREATE INDEX ix_responses_respondent
  ON responses (respondent_id) LOCAL;

-- Mỗi người chỉ nộp 1 lần với form có limit_one_response = 1.
-- Khi once_key IS NULL, cả hai biểu thức đều NULL nên dòng không
-- được đưa vào index và không bị kiểm tra trùng.
CREATE UNIQUE INDEX ux_responses_once ON responses (
  CASE WHEN once_key IS NOT NULL THEN form_id END,
  once_key)
  TABLESPACE ts_hf_index;
-- #endregion

-- #region idx_answers
-- Không trả lời trùng một phương án / một câu hỏi trong cùng lượt phản hồi;
-- cột dẫn đầu response_id đồng thời là index cho khóa ngoại
CREATE UNIQUE INDEX ux_answers_resp_q_opt
  ON answers (response_id, question_id, option_id)
  TABLESPACE ts_hf_index;

-- Thống kê số lượt chọn theo câu hỏi / phương án
CREATE INDEX ix_answers_question_option
  ON answers (question_id, option_id) LOCAL;
-- #endregion

-- #region idx_audit
CREATE INDEX ix_audit_record ON audit_logs (table_name, record_id)
  TABLESPACE ts_hf_index;

CREATE INDEX ix_audit_time ON audit_logs (action_at)
  TABLESPACE ts_hf_index;
-- #endregion

-- #region check_indexes
-- Kiểm tra các chỉ mục đã tạo (bỏ qua chỉ mục LOB do Oracle tự sinh)
SELECT index_name, table_name, index_type, uniqueness, partitioned
  FROM user_indexes
 WHERE index_type <> 'LOB'
 ORDER BY table_name, index_name;
-- #endregion
