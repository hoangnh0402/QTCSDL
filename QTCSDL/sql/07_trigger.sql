-- =====================================================================
-- HaUI FORM - Script 07: Trigger
-- Kết nối bằng tài khoản HAUIFORM. File lưu dạng UTF-8.
-- =====================================================================

-- #region trg_responses_bi
-- Tự gán once_key theo cấu hình của biểu mẫu (QT05).
-- Ứng dụng KHÔNG thể lách quy tắc "mỗi người một lần" bằng cách để
-- once_key = NULL khi INSERT trực tiếp: giá trị luôn do trigger quyết định.
CREATE OR REPLACE TRIGGER trg_responses_bi
BEFORE INSERT ON responses
FOR EACH ROW
DECLARE
  v_limit forms.limit_one_response%TYPE;
BEGIN
  SELECT limit_one_response INTO v_limit
    FROM forms
   WHERE form_id = :NEW.form_id;

  IF v_limit = 1 THEN
    IF :NEW.respondent_id IS NULL THEN
      RAISE_APPLICATION_ERROR(-20030,
        'Biểu mẫu giới hạn một phản hồi, bắt buộc có người trả lời');
    END IF;
    :NEW.once_key := :NEW.respondent_id;
  ELSE
    :NEW.once_key := NULL;
  END IF;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    NULL;            -- form_id sai: để khóa ngoại fk_responses_form báo lỗi
END;
/
-- #endregion

-- #region trg_responses_bu
-- Phản hồi đã nộp là bất biến: không ai được sửa nội dung lượt nộp
CREATE OR REPLACE TRIGGER trg_responses_bu
BEFORE UPDATE ON responses
FOR EACH ROW
BEGIN
  RAISE_APPLICATION_ERROR(-20031,
    'Phản hồi đã nộp không được phép chỉnh sửa');
END;
/
-- #endregion

-- #region trg_forms_bu
-- Ràng buộc chuyển trạng thái và khóa cấu hình khi đã có phản hồi
CREATE OR REPLACE TRIGGER trg_forms_bu
BEFORE UPDATE ON forms
FOR EACH ROW
BEGIN
  IF :OLD.status = 'CLOSED' AND :NEW.status = 'DRAFT' THEN
    RAISE_APPLICATION_ERROR(-20032,
      'Biểu mẫu đã đóng không thể trở lại trạng thái nháp');
  END IF;

  -- Bật / tắt "mỗi người một lần" giữa chừng sẽ làm sai lệch dữ liệu đã thu
  IF :OLD.response_count > 0
     AND (:NEW.limit_one_response <> :OLD.limit_one_response
          OR :NEW.is_anonymous   <> :OLD.is_anonymous) THEN
    RAISE_APPLICATION_ERROR(-20033,
      'Biểu mẫu đã có phản hồi, không được đổi chế độ giới hạn / ẩn danh');
  END IF;

  -- Chỉ cập nhật updated_at khi thay đổi nội dung, không phải bộ đếm
  IF UPDATING('TITLE') OR UPDATING('DESCRIPTION') OR UPDATING('SETTINGS')
     OR UPDATING('OPEN_AT') OR UPDATING('CLOSE_AT')
     OR UPDATING('MAX_RESPONSES') OR UPDATING('DELETED_AT') THEN
    :NEW.updated_at := SYSTIMESTAMP;
  END IF;
END;
/
-- #endregion

-- #region trg_questions_guard
-- Không cho thêm / xóa câu hỏi hoặc đổi loại câu hỏi khi biểu mẫu đã có
-- phản hồi. Đọc bảng RESPONSES (không phải FORMS) để tránh lỗi bảng đang
-- biến đổi ORA-04091 khi xóa biểu mẫu nháp theo dây chuyền.
CREATE OR REPLACE TRIGGER trg_questions_guard
BEFORE INSERT OR DELETE OR UPDATE OF question_type, form_id, is_required
ON questions
FOR EACH ROW
DECLARE
  v_has PLS_INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_has
    FROM responses
   WHERE form_id = NVL(:OLD.form_id, :NEW.form_id)
     AND ROWNUM = 1;

  IF v_has > 0 THEN
    RAISE_APPLICATION_ERROR(-20034,
      'Biểu mẫu đã có phản hồi, không được thay đổi cấu trúc câu hỏi');
  END IF;
END;
/
-- #endregion

-- #region trg_forms_audit
-- Ghi nhật ký thay đổi biểu mẫu (QT10)
CREATE OR REPLACE TRIGGER trg_forms_audit
AFTER INSERT OR UPDATE OR DELETE ON forms
FOR EACH ROW
DECLARE
  v_op  audit_logs.operation%TYPE;
  v_old CLOB;
  v_new CLOB;
  -- So sánh có xét NULL (hai giá trị NULL được coi là bằng nhau)
  FUNCTION same (a VARCHAR2, b VARCHAR2) RETURN BOOLEAN IS
  BEGIN RETURN (a = b) OR (a IS NULL AND b IS NULL); END;
  FUNCTION same (a NUMBER, b NUMBER) RETURN BOOLEAN IS
  BEGIN RETURN (a = b) OR (a IS NULL AND b IS NULL); END;
  FUNCTION same (a TIMESTAMP, b TIMESTAMP) RETURN BOOLEAN IS
  BEGIN RETURN (a = b) OR (a IS NULL AND b IS NULL); END;
BEGIN
  IF UPDATING THEN
    -- Bỏ qua lần cập nhật chỉ thay đổi bộ đếm response_count
    IF  same(:OLD.title,              :NEW.title)
    AND same(:OLD.status,             :NEW.status)
    AND same(:OLD.is_anonymous,       :NEW.is_anonymous)
    AND same(:OLD.require_login,      :NEW.require_login)
    AND same(:OLD.limit_one_response, :NEW.limit_one_response)
    AND same(:OLD.max_responses,      :NEW.max_responses)
    AND same(:OLD.open_at,            :NEW.open_at)
    AND same(:OLD.close_at,           :NEW.close_at)
    AND same(:OLD.deleted_at,         :NEW.deleted_at)
    THEN
      RETURN;
    END IF;
  END IF;

  v_op := CASE WHEN INSERTING THEN 'INSERT'
               WHEN UPDATING  THEN 'UPDATE'
               ELSE 'DELETE' END;

  IF NOT INSERTING THEN
    SELECT JSON_OBJECT('title'         VALUE :OLD.title,
                       'status'        VALUE :OLD.status,
                       'is_anonymous'  VALUE :OLD.is_anonymous,
                       'limit_one'     VALUE :OLD.limit_one_response,
                       'max_responses' VALUE :OLD.max_responses,
                       'close_at'      VALUE :OLD.close_at,
                       'deleted_at'    VALUE :OLD.deleted_at
                       RETURNING CLOB)
      INTO v_old FROM dual;
  END IF;

  IF NOT DELETING THEN
    SELECT JSON_OBJECT('title'         VALUE :NEW.title,
                       'status'        VALUE :NEW.status,
                       'is_anonymous'  VALUE :NEW.is_anonymous,
                       'limit_one'     VALUE :NEW.limit_one_response,
                       'max_responses' VALUE :NEW.max_responses,
                       'close_at'      VALUE :NEW.close_at,
                       'deleted_at'    VALUE :NEW.deleted_at
                       RETURNING CLOB)
      INTO v_new FROM dual;
  END IF;

  INSERT INTO audit_logs (table_name, operation, record_id,
                          old_values, new_values, app_user_id)
  VALUES ('FORMS', v_op, TO_CHAR(NVL(:NEW.form_id, :OLD.form_id)),
          v_old, v_new, TO_NUMBER(SYS_CONTEXT('HF_CTX', 'USER_ID')));
END;
/
-- #endregion

-- #region trg_responses_audit
-- Mọi thao tác XÓA phản hồi đều để lại dấu vết
CREATE OR REPLACE TRIGGER trg_responses_audit
AFTER DELETE ON responses
FOR EACH ROW
DECLARE
  v_old CLOB;
BEGIN
  SELECT JSON_OBJECT('form_id'       VALUE :OLD.form_id,
                     'respondent_id' VALUE :OLD.respondent_id,
                     'submitted_at'  VALUE :OLD.submitted_at
                     RETURNING CLOB)
    INTO v_old FROM dual;

  INSERT INTO audit_logs (table_name, operation, record_id,
                          old_values, app_user_id)
  VALUES ('RESPONSES', 'DELETE', TO_CHAR(:OLD.response_id),
          v_old, TO_NUMBER(SYS_CONTEXT('HF_CTX', 'USER_ID')));
END;
/
-- #endregion

-- #region trg_users_audit
-- Theo dõi thay đổi vai trò / trạng thái tài khoản (phát hiện leo thang đặc quyền)
CREATE OR REPLACE TRIGGER trg_users_audit
AFTER UPDATE OF user_role, status ON users
FOR EACH ROW
DECLARE
  v_old CLOB;
  v_new CLOB;
BEGIN
  SELECT JSON_OBJECT('user_role' VALUE :OLD.user_role,
                     'status'    VALUE :OLD.status RETURNING CLOB),
         JSON_OBJECT('user_role' VALUE :NEW.user_role,
                     'status'    VALUE :NEW.status RETURNING CLOB)
    INTO v_old, v_new FROM dual;

  INSERT INTO audit_logs (table_name, operation, record_id,
                          old_values, new_values, app_user_id)
  VALUES ('USERS', 'UPDATE', TO_CHAR(:NEW.user_id),
          v_old, v_new, TO_NUMBER(SYS_CONTEXT('HF_CTX', 'USER_ID')));
END;
/
-- #endregion

-- #region check_triggers
SELECT trigger_name, table_name, trigger_type, triggering_event, status
  FROM user_triggers
 ORDER BY table_name, trigger_name;
-- #endregion
