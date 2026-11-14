-- =====================================================================
-- HaUI FORM - Script 06: Các gói PL/SQL nghiệp vụ
-- Kết nối bằng tài khoản HAUIFORM. File lưu dạng UTF-8.
--   PKG_CTX      : gán ngữ cảnh người dùng ứng dụng (application context)
--   PKG_VPD      : hàm chính sách cho Virtual Private Database (dùng ở script 09)
--   PKG_RESPONSE : nộp phản hồi trong MỘT giao dịch, kiểm soát nộp trùng
--   PKG_FORM     : sinh mã chia sẻ, mở / đóng / xóa mềm biểu mẫu
-- =====================================================================

-- #region pkg_ctx
-- Ngữ cảnh HF_CTX được SYS tạo ở script 09 bằng lệnh
--   CREATE CONTEXT hf_ctx USING hauiform.pkg_ctx;
-- nên CHỈ gói này mới ghi được giá trị vào HF_CTX.
CREATE OR REPLACE PACKAGE pkg_ctx AUTHID DEFINER AS
  PROCEDURE set_user (p_user_id IN users.user_id%TYPE);
  PROCEDURE clear_user;
END pkg_ctx;
/

CREATE OR REPLACE PACKAGE BODY pkg_ctx AS
  PROCEDURE set_user (p_user_id IN users.user_id%TYPE) IS
    v_role users.user_role%TYPE;
  BEGIN
    SELECT user_role INTO v_role
      FROM users
     WHERE user_id = p_user_id
       AND status  = 'ACTIVE';

    DBMS_SESSION.SET_CONTEXT('HF_CTX', 'USER_ID',   TO_CHAR(p_user_id));
    DBMS_SESSION.SET_CONTEXT('HF_CTX', 'USER_ROLE', v_role);
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      clear_user;
      RAISE_APPLICATION_ERROR(-20001,
        'Tài khoản không tồn tại hoặc đã bị khóa');
  END set_user;

  PROCEDURE clear_user IS
  BEGIN
    DBMS_SESSION.CLEAR_ALL_CONTEXT('HF_CTX');
  END clear_user;
END pkg_ctx;
/
-- #endregion

-- #region pkg_vpd
-- Hàm chính sách trả về một VỊ TỪ (điều kiện WHERE) mà Oracle tự gắn
-- vào mọi câu lệnh truy cập bảng. Trả về NULL nghĩa là không giới hạn.
CREATE OR REPLACE PACKAGE pkg_vpd AUTHID DEFINER AS
  FUNCTION responses_rows     (p_schema IN VARCHAR2, p_object IN VARCHAR2)
    RETURN VARCHAR2;
  FUNCTION responses_identity (p_schema IN VARCHAR2, p_object IN VARCHAR2)
    RETURN VARCHAR2;
  FUNCTION answers_rows       (p_schema IN VARCHAR2, p_object IN VARCHAR2)
    RETURN VARCHAR2;
END pkg_vpd;
/

CREATE OR REPLACE PACKAGE BODY pkg_vpd AS
  -- Tài khoản chủ sở hữu schema và quản trị không bị giới hạn
  FUNCTION is_exempt RETURN BOOLEAN IS
  BEGIN
    RETURN SYS_CONTEXT('USERENV', 'SESSION_USER')
           IN ('HAUIFORM', 'SYS', 'SYSTEM');
  END is_exempt;

  -- (1) Mức dòng: người dùng ứng dụng chỉ thấy phản hồi của chính mình,
  --     của biểu mẫu mình sở hữu hoặc được chia sẻ; ADMIN thấy tất cả.
  FUNCTION responses_rows (p_schema IN VARCHAR2, p_object IN VARCHAR2)
    RETURN VARCHAR2 IS
  BEGIN
    IF is_exempt
       OR SYS_CONTEXT('USERENV', 'SESSION_USER') = 'HF_REPORT'
       OR SYS_CONTEXT('HF_CTX', 'USER_ROLE') = 'ADMIN' THEN
      RETURN NULL;
    END IF;

    IF SYS_CONTEXT('HF_CTX', 'USER_ID') IS NULL THEN
      RETURN '1 = 0';                       -- chưa xác định người dùng
    END IF;

    RETURN 'respondent_id = SYS_CONTEXT(''HF_CTX'', ''USER_ID'')'
        || ' OR form_id IN (SELECT f.form_id FROM hauiform.forms f'
        || '   WHERE f.owner_id = SYS_CONTEXT(''HF_CTX'', ''USER_ID''))'
        || ' OR form_id IN (SELECT c.form_id FROM hauiform.form_collaborators c'
        || '   WHERE c.user_id = SYS_CONTEXT(''HF_CTX'', ''USER_ID''))';
  END responses_rows;

  -- (2) Mức cột: danh tính (respondent_id, ip_address, user_agent) chỉ hiện
  --     khi là phản hồi của chính mình hoặc biểu mẫu KHÔNG ẩn danh.
  --     Các dòng không thỏa vị từ vẫn trả về nhưng các cột này bị thay bằng NULL.
  FUNCTION responses_identity (p_schema IN VARCHAR2, p_object IN VARCHAR2)
    RETURN VARCHAR2 IS
  BEGIN
    IF is_exempt THEN
      RETURN NULL;
    END IF;

    IF SYS_CONTEXT('USERENV', 'SESSION_USER') = 'HF_REPORT' THEN
      RETURN '1 = 0';                       -- tài khoản báo cáo không thấy danh tính
    END IF;

    RETURN 'respondent_id = SYS_CONTEXT(''HF_CTX'', ''USER_ID'')'
        || ' OR form_id IN (SELECT f.form_id FROM hauiform.forms f'
        || '   WHERE f.is_anonymous = 0)';
  END responses_identity;

  -- (3) ANSWERS: chỉ thấy câu trả lời thuộc các phản hồi được phép thấy.
  --     Truy vấn con trên RESPONSES tự động chịu chính sách (1).
  FUNCTION answers_rows (p_schema IN VARCHAR2, p_object IN VARCHAR2)
    RETURN VARCHAR2 IS
  BEGIN
    IF is_exempt OR SYS_CONTEXT('USERENV', 'SESSION_USER') = 'HF_REPORT' THEN
      RETURN NULL;
    END IF;
    RETURN 'response_id IN (SELECT r.response_id FROM hauiform.responses r)';
  END answers_rows;
END pkg_vpd;
/
-- #endregion

-- #region pkg_response_spec
CREATE OR REPLACE PACKAGE pkg_response AUTHID DEFINER AS
  -- Mã lỗi nghiệp vụ (ORA-20010 .. ORA-20029)
  c_err_not_found     CONSTANT PLS_INTEGER := -20010;
  c_err_not_open      CONSTANT PLS_INTEGER := -20011;
  c_err_not_started   CONSTANT PLS_INTEGER := -20012;
  c_err_expired       CONSTANT PLS_INTEGER := -20013;
  c_err_login         CONSTANT PLS_INTEGER := -20014;
  c_err_locked        CONSTANT PLS_INTEGER := -20015;
  c_err_impersonate   CONSTANT PLS_INTEGER := -20016;
  c_err_duplicate     CONSTANT PLS_INTEGER := -20020;
  c_err_full          CONSTANT PLS_INTEGER := -20021;
  c_err_required      CONSTANT PLS_INTEGER := -20022;
  c_err_foreign_q     CONSTANT PLS_INTEGER := -20023;
  c_err_single        CONSTANT PLS_INTEGER := -20024;

  -- Nộp một lượt phản hồi. p_answers là mảng JSON, mỗi phần tử một giá trị:
  --   [{"q":1,"n":5}, {"q":2,"o":1}, {"q":3,"o":6}, {"q":3,"o":7},
  --    {"q":4,"t":"Góp ý"}, {"q":9,"d":"2026-11-14"}]
  --   q = question_id, o = option_id, t = văn bản, n = số, d = ngày
  PROCEDURE submit (
    p_form_id     IN  forms.form_id%TYPE,
    p_user_id     IN  users.user_id%TYPE,
    p_answers     IN  CLOB,
    p_duration    IN  NUMBER   DEFAULT NULL,
    p_ip          IN  VARCHAR2 DEFAULT NULL,
    p_user_agent  IN  VARCHAR2 DEFAULT NULL,
    p_response_id OUT responses.response_id%TYPE,
    p_commit      IN  NUMBER   DEFAULT 1);

  -- Thời điểm người dùng đã nộp biểu mẫu (NULL nếu chưa nộp)
  FUNCTION submitted_at (
    p_form_id IN forms.form_id%TYPE,
    p_user_id IN users.user_id%TYPE) RETURN TIMESTAMP;
END pkg_response;
/
-- #endregion

-- #region pkg_response_body
CREATE OR REPLACE PACKAGE BODY pkg_response AS

  FUNCTION submitted_at (
    p_form_id IN forms.form_id%TYPE,
    p_user_id IN users.user_id%TYPE) RETURN TIMESTAMP IS
    v_time TIMESTAMP;
  BEGIN
    SELECT MAX(submitted_at) INTO v_time
      FROM responses
     WHERE form_id       = p_form_id
       AND respondent_id = p_user_id;
    RETURN v_time;
  END submitted_at;

  PROCEDURE submit (
    p_form_id     IN  forms.form_id%TYPE,
    p_user_id     IN  users.user_id%TYPE,
    p_answers     IN  CLOB,
    p_duration    IN  NUMBER   DEFAULT NULL,
    p_ip          IN  VARCHAR2 DEFAULT NULL,
    p_user_agent  IN  VARCHAR2 DEFAULT NULL,
    p_response_id OUT responses.response_id%TYPE,
    p_commit      IN  NUMBER   DEFAULT 1)
  IS
    v_form      forms%ROWTYPE;
    v_status    users.status%TYPE;
    v_prev      TIMESTAMP;
    v_now       TIMESTAMP := SYSTIMESTAMP;
    v_cnt       PLS_INTEGER;
    v_items     PLS_INTEGER;
    v_ctx_user  VARCHAR2(20) := SYS_CONTEXT('HF_CTX', 'USER_ID');
  BEGIN
    SAVEPOINT sp_submit;

    -- (0) Ứng dụng không được nộp thay người khác
    IF SYS_CONTEXT('USERENV', 'SESSION_USER') = 'HF_APP'
       AND p_user_id IS NOT NULL
       AND (v_ctx_user IS NULL OR TO_NUMBER(v_ctx_user) <> p_user_id) THEN
      RAISE_APPLICATION_ERROR(c_err_impersonate,
        'Không được nộp phản hồi thay cho tài khoản khác');
    END IF;

    -- (1) Đọc biểu mẫu. Nếu biểu mẫu giới hạn số chỗ thì KHÓA DÒNG
    --     để các phiên nộp cùng biểu mẫu phải xếp hàng (QT06).
    BEGIN
      SELECT * INTO v_form
        FROM forms
       WHERE form_id = p_form_id
         AND deleted_at IS NULL;

      IF v_form.max_responses IS NOT NULL THEN
        SELECT * INTO v_form
          FROM forms
         WHERE form_id = p_form_id
           FOR UPDATE WAIT 10;
      END IF;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(c_err_not_found, 'Biểu mẫu không tồn tại');
    END;

    -- (2) Trạng thái và thời gian mở (QT02)
    IF v_form.status <> 'OPEN' THEN
      RAISE_APPLICATION_ERROR(c_err_not_open,
        'Biểu mẫu chưa mở hoặc đã đóng');
    ELSIF v_form.open_at IS NOT NULL AND v_now < v_form.open_at THEN
      RAISE_APPLICATION_ERROR(c_err_not_started,
        'Biểu mẫu chưa đến thời gian nhận phản hồi');
    ELSIF v_form.close_at IS NOT NULL AND v_now > v_form.close_at THEN
      RAISE_APPLICATION_ERROR(c_err_expired,
        'Biểu mẫu đã hết hạn nhận phản hồi');
    END IF;

    -- (3) Yêu cầu đăng nhập, tài khoản phải đang hoạt động
    IF v_form.require_login = 1 THEN
      IF p_user_id IS NULL THEN
        RAISE_APPLICATION_ERROR(c_err_login, 'Biểu mẫu yêu cầu đăng nhập');
      END IF;
      BEGIN
        SELECT status INTO v_status FROM users WHERE user_id = p_user_id;
      EXCEPTION
        WHEN NO_DATA_FOUND THEN
          RAISE_APPLICATION_ERROR(c_err_login, 'Tài khoản không tồn tại');
      END;
      IF v_status <> 'ACTIVE' THEN
        RAISE_APPLICATION_ERROR(c_err_locked, 'Tài khoản đã bị khóa');
      END IF;
    END IF;

    -- (4) Mỗi người một phản hồi (QT05) - kiểm tra sớm để báo lỗi thân thiện.
    --     Hai yêu cầu đồng thời có thể cùng vượt qua bước này; khi đó chỉ mục
    --     duy nhất ux_responses_once là chốt chặn cuối (xử lý ở EXCEPTION).
    IF v_form.limit_one_response = 1 THEN
      v_prev := submitted_at(p_form_id, p_user_id);
      IF v_prev IS NOT NULL THEN
        RAISE_APPLICATION_ERROR(c_err_duplicate,
          'Bạn đã gửi phản hồi cho biểu mẫu này lúc '
          || TO_CHAR(v_prev, 'HH24:MI:SS DD/MM/YYYY')
          || '. Mỗi tài khoản chỉ được gửi một lần.');
      END IF;
    END IF;

    -- (5) Còn chỗ (QT06) - đang giữ khóa dòng nên số liệu không đổi
    IF v_form.max_responses IS NOT NULL
       AND v_form.response_count >= v_form.max_responses THEN
      RAISE_APPLICATION_ERROR(c_err_full,
        'Biểu mẫu đã đủ ' || v_form.max_responses || ' phản hồi');
    END IF;

    -- (6) Kiểm tra dữ liệu gửi lên TRƯỚC khi ghi
    --     a. Câu hỏi bắt buộc phải có giá trị
    SELECT COUNT(*) INTO v_cnt
      FROM questions q
     WHERE q.form_id = p_form_id
       AND q.is_required = 1
       AND NOT EXISTS (
             SELECT 1
               FROM JSON_TABLE(p_answers, '$[*]'
                      COLUMNS (qid NUMBER PATH '$.q',
                               o   NUMBER PATH '$.o',
                               t   VARCHAR2(2000 CHAR) PATH '$.t',
                               n   NUMBER PATH '$.n',
                               d   VARCHAR2(10) PATH '$.d')) j
              WHERE j.qid = q.question_id
                AND (j.o IS NOT NULL OR j.t IS NOT NULL
                     OR j.n IS NOT NULL OR j.d IS NOT NULL));
    IF v_cnt > 0 THEN
      RAISE_APPLICATION_ERROR(c_err_required,
        'Còn ' || v_cnt || ' câu hỏi bắt buộc chưa trả lời');
    END IF;

    --     b. Câu hỏi không phải nhiều lựa chọn chỉ có một giá trị
    SELECT COUNT(*) INTO v_cnt
      FROM (SELECT j.qid
              FROM JSON_TABLE(p_answers, '$[*]'
                     COLUMNS (qid NUMBER PATH '$.q')) j
              JOIN questions q ON q.question_id = j.qid
             WHERE q.question_type <> 'MULTI_CHOICE'
             GROUP BY j.qid
            HAVING COUNT(*) > 1);
    IF v_cnt > 0 THEN
      RAISE_APPLICATION_ERROR(c_err_single,
        'Câu hỏi một lựa chọn nhận nhiều hơn một giá trị');
    END IF;

    -- (7) Ghi lượt phản hồi; once_key do trigger trg_responses_bi gán
    INSERT INTO responses (form_id, respondent_id, submitted_at,
                           duration_sec, ip_address, user_agent)
    VALUES (p_form_id, p_user_id, v_now,
            p_duration, p_ip, SUBSTR(p_user_agent, 1, 500))
    RETURNING response_id INTO p_response_id;

    -- (8) Ghi toàn bộ câu trả lời bằng MỘT câu lệnh INSERT ... SELECT;
    --     chỉ nhận câu hỏi thuộc đúng biểu mẫu
    SELECT COUNT(*) INTO v_items
      FROM JSON_TABLE(p_answers, '$[*]'
             COLUMNS (o NUMBER PATH '$.o', t VARCHAR2(2000 CHAR) PATH '$.t',
                      n NUMBER PATH '$.n', d VARCHAR2(10) PATH '$.d')) j
     WHERE j.o IS NOT NULL OR j.t IS NOT NULL
        OR j.n IS NOT NULL OR j.d IS NOT NULL;

    INSERT INTO answers (response_id, question_id, option_id,
                         answer_text, answer_number, answer_date)
    SELECT p_response_id, j.qid, j.o, j.t, j.n, TO_DATE(j.d, 'YYYY-MM-DD')
      FROM JSON_TABLE(p_answers, '$[*]'
             COLUMNS (qid NUMBER PATH '$.q',
                      o   NUMBER PATH '$.o',
                      t   VARCHAR2(2000 CHAR) PATH '$.t',
                      n   NUMBER PATH '$.n',
                      d   VARCHAR2(10) PATH '$.d')) j
      JOIN questions q
        ON q.question_id = j.qid
       AND q.form_id     = p_form_id
     WHERE j.o IS NOT NULL OR j.t IS NOT NULL
        OR j.n IS NOT NULL OR j.d IS NOT NULL;

    IF SQL%ROWCOUNT <> v_items THEN
      RAISE_APPLICATION_ERROR(c_err_foreign_q,
        'Có câu trả lời không thuộc biểu mẫu này');
    END IF;

    -- (9) Tăng bộ đếm; tự đóng biểu mẫu khi vừa đủ chỗ
    UPDATE forms
       SET response_count = response_count + 1,
           status = CASE
                      WHEN max_responses IS NOT NULL
                       AND response_count + 1 >= max_responses
                      THEN 'CLOSED' ELSE status
                    END
     WHERE form_id = p_form_id;

    IF p_commit = 1 THEN
      COMMIT;
    END IF;

  EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
      ROLLBACK TO sp_submit;
      IF INSTR(SQLERRM, 'UX_RESPONSES_ONCE') > 0 THEN
        RAISE_APPLICATION_ERROR(c_err_duplicate,
          'Bạn đã gửi phản hồi cho biểu mẫu này. '
          || 'Mỗi tài khoản chỉ được gửi một lần.');
      END IF;
      RAISE;
    WHEN OTHERS THEN
      ROLLBACK TO sp_submit;   -- hủy mọi thay đổi của lượt nộp này
      RAISE;
  END submit;

END pkg_response;
/
-- #endregion

-- #region pkg_form
CREATE OR REPLACE PACKAGE pkg_form AUTHID DEFINER AS
  FUNCTION  gen_short_code RETURN VARCHAR2;
  PROCEDURE publish     (p_form_id IN forms.form_id%TYPE);
  PROCEDURE close_form  (p_form_id IN forms.form_id%TYPE);
  PROCEDURE soft_delete (p_form_id IN forms.form_id%TYPE);
  -- Được job JOB_CLOSE_EXPIRED_FORMS gọi định kỳ
  PROCEDURE close_expired;
END pkg_form;
/

CREATE OR REPLACE PACKAGE BODY pkg_form AS

  FUNCTION gen_short_code RETURN VARCHAR2 IS
    v_code  forms.short_code%TYPE;
    v_found PLS_INTEGER;
  BEGIN
    LOOP
      v_code := DBMS_RANDOM.STRING('X', 8);          -- 8 ký tự A-Z, 0-9
      SELECT COUNT(*) INTO v_found FROM forms WHERE short_code = v_code;
      EXIT WHEN v_found = 0;
    END LOOP;
    RETURN v_code;
  END gen_short_code;

  PROCEDURE publish (p_form_id IN forms.form_id%TYPE) IS
    v_questions PLS_INTEGER;
  BEGIN
    SELECT COUNT(*) INTO v_questions FROM questions WHERE form_id = p_form_id;
    IF v_questions = 0 THEN
      RAISE_APPLICATION_ERROR(-20040, 'Biểu mẫu chưa có câu hỏi');
    END IF;
    UPDATE forms SET status = 'OPEN'
     WHERE form_id = p_form_id AND status = 'DRAFT' AND deleted_at IS NULL;
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20041, 'Chỉ biểu mẫu nháp mới được mở');
    END IF;
  END publish;

  PROCEDURE close_form (p_form_id IN forms.form_id%TYPE) IS
  BEGIN
    UPDATE forms SET status = 'CLOSED'
     WHERE form_id = p_form_id AND status = 'OPEN';
  END close_form;

  PROCEDURE soft_delete (p_form_id IN forms.form_id%TYPE) IS
  BEGIN
    UPDATE forms SET deleted_at = SYSTIMESTAMP, status = 'CLOSED'
     WHERE form_id = p_form_id AND deleted_at IS NULL;
  END soft_delete;

  PROCEDURE close_expired IS
  BEGIN
    UPDATE forms SET status = 'CLOSED'
     WHERE status = 'OPEN'
       AND close_at < SYSTIMESTAMP;
    COMMIT;
  END close_expired;

END pkg_form;
/
-- #endregion

-- #region job
-- Job tự động đóng biểu mẫu hết hạn, chạy 5 phút một lần (QT02)
BEGIN
  DBMS_SCHEDULER.DROP_JOB('JOB_CLOSE_EXPIRED_FORMS', force => TRUE);
EXCEPTION
  WHEN OTHERS THEN NULL;                 -- job chưa tồn tại
END;
/

BEGIN
  DBMS_SCHEDULER.CREATE_JOB(
    job_name        => 'JOB_CLOSE_EXPIRED_FORMS',
    job_type        => 'PLSQL_BLOCK',
    job_action      => 'BEGIN pkg_form.close_expired; END;',
    start_date      => SYSTIMESTAMP,
    repeat_interval => 'FREQ=MINUTELY; INTERVAL=5',
    enabled         => TRUE,
    comments        => 'Tự động đóng biểu mẫu đã quá close_at');
END;
/
-- #endregion

-- #region check_plsql
SELECT object_name, object_type, status
  FROM user_objects
 WHERE object_type IN ('PACKAGE', 'PACKAGE BODY')
 ORDER BY object_name, object_type;

SELECT job_name, repeat_interval, enabled, state
  FROM user_scheduler_jobs;
-- #endregion
