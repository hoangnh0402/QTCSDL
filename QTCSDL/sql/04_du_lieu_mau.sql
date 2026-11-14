-- =====================================================================
-- HaUI FORM - Script 04: Nhập dữ liệu mẫu
-- Kết nối bằng tài khoản HAUIFORM. File lưu dạng UTF-8.
-- SQL*Plus trên Windows: đặt NLS_LANG=AMERICAN_AMERICA.AL32UTF8 trước khi chạy
-- =====================================================================

-- #region data_departments
INSERT INTO departments (dept_id, dept_code, dept_name) VALUES
  (1, 'CNTT', 'Trường Công nghệ Thông tin và Truyền thông');
INSERT INTO departments (dept_id, dept_code, dept_name) VALUES
  (2, 'CKOT', 'Trường Cơ khí – Ô tô');
INSERT INTO departments (dept_id, dept_code, dept_name) VALUES
  (3, 'DDT',  'Trường Điện – Điện tử');
INSERT INTO departments (dept_id, dept_code, dept_name) VALUES
  (4, 'KT',   'Trường Kinh tế');
INSERT INTO departments (dept_id, dept_code, dept_name) VALUES
  (5, 'PDT',  'Phòng Đào tạo');
INSERT INTO departments (dept_id, dept_code, dept_name) VALUES
  (6, 'DTN',  'Đoàn Thanh niên');
-- #endregion

-- #region data_users
-- password_hash là giá trị băm bcrypt minh họa (mật khẩu gốc không lưu trong CSDL)
INSERT INTO users (user_id, username, full_name, email, password_hash,
                   user_type, user_role, dept_id)
VALUES (1, 'admin', 'Quản trị hệ thống', 'admin@haui.edu.vn',
        '$2b$12$9xJ1pQeVt0kL3mN5bR7cOe1yZ2uW4sA6dF8gH0jK2lM4nP6qR8sT0',
        'STAFF', 'ADMIN', 5);
INSERT INTO users (user_id, username, full_name, email, password_hash,
                   user_type, user_role, dept_id)
VALUES (2, 'gv.tranminhduc', 'Trần Minh Đức', 'tranminhduc@haui.edu.vn',
        '$2b$12$4aB6cD8eF0gH2iJ4kL6mNuO8pQ0rS2tU4vW6xY8zA0bC2dE4fG6hI',
        'LECTURER', 'USER', 1);
INSERT INTO users (user_id, username, full_name, email, password_hash,
                   user_type, user_role, dept_id)
VALUES (3, 'gv.lethuha', 'Lê Thu Hà', 'lethuha@haui.edu.vn',
        '$2b$12$7jK9lM1nO3pQ5rS7tU9vWuX1yZ3aB5cD7eF9gH1iJ3kL5mN7oP9qR',
        'LECTURER', 'USER', 4);
INSERT INTO users (user_id, username, full_name, email, password_hash,
                   user_type, user_role, dept_id)
VALUES (4, 'cb.phamvanlong', 'Phạm Văn Long', 'phamvanlong@haui.edu.vn',
        '$2b$12$2sT4uV6wX8yZ0aB2cD4eFuG6hI8jK0lM2nO4pQ6rS8tU0vW2xY4zA',
        'STAFF', 'USER', 6);
INSERT INTO users (user_id, username, full_name, email, password_hash,
                   user_type, user_role, dept_id)
VALUES (5, '2026600101', 'Nguyễn Thị Mai Anh', '2026600101@sv.haui.edu.vn',
        '$2b$12$6bC8dE0fG2hI4jK6lM8nOuP0qR2sT4uV6wX8yZ0aB2cD4eF6gH8iJ',
        'STUDENT', 'USER', 1);
INSERT INTO users (user_id, username, full_name, email, password_hash,
                   user_type, user_role, dept_id)
VALUES (6, '2026600102', 'Hoàng Quốc Bảo', '2026600102@sv.haui.edu.vn',
        '$2b$12$1kL3mN5oP7qR9sT1uV3wXuY5zA7bC9dE1fG3hI5jK7lM9nO1pQ3rS',
        'STUDENT', 'USER', 1);
INSERT INTO users (user_id, username, full_name, email, password_hash,
                   user_type, user_role, dept_id)
VALUES (7, '2026600103', 'Đặng Thùy Linh', '2026600103@sv.haui.edu.vn',
        '$2b$12$5tU7vW9xY1zA3bC5dE7fGuH9iJ1kL3mN5oP7qR9sT1uV3wX5yZ7aB',
        'STUDENT', 'USER', 4);
INSERT INTO users (user_id, username, full_name, email, password_hash,
                   user_type, user_role, dept_id)
VALUES (8, '2026600104', 'Vũ Minh Khang', '2026600104@sv.haui.edu.vn',
        '$2b$12$8cD0eF2gH4iJ6kL8mN0oPuQ2rS4tU6vW8xY0zA2bC4dE6fG8hI0jK',
        'STUDENT', 'USER', 2);
-- #endregion

-- #region data_forms
INSERT INTO forms (form_id, owner_id, short_code, title, description, status,
                   is_anonymous, require_login, limit_one_response,
                   max_responses, open_at, close_at, settings)
VALUES (1, 2, 'Ks7Qd2Xa',
  'Lấy ý kiến người học về học phần Quản trị cơ sở dữ liệu nâng cao',
  'Phiếu khảo sát ẩn danh, kết quả chỉ dùng để cải tiến chất lượng giảng dạy.',
  'OPEN', 1, 1, 1, NULL,
  TIMESTAMP '2026-10-01 00:00:00', TIMESTAMP '2026-11-30 23:59:59',
  '{"category":"DANH_GIA_GIANG_DAY","theme":"#0A5DA8",
    "confirmationMessage":"Cảm ơn bạn đã đóng góp ý kiến!",
    "shuffleQuestions":false,"showSummaryToRespondents":false}');

INSERT INTO forms (form_id, owner_id, short_code, title, description, status,
                   is_anonymous, require_login, limit_one_response,
                   max_responses, open_at, close_at, settings)
VALUES (2, 4, 'Ht2026AI',
  'Đăng ký tham dự hội thảo "Ứng dụng AI trong quản trị dữ liệu"',
  'Hội thảo giới hạn số chỗ, hệ thống tự đóng đăng ký khi đủ số lượng.',
  'OPEN', 0, 1, 1, 3,
  TIMESTAMP '2026-10-15 08:00:00', TIMESTAMP '2026-11-05 17:00:00',
  '{"category":"DANG_KY_SU_KIEN","theme":"#C62828",
    "confirmationMessage":"Đăng ký thành công. Hẹn gặp bạn tại hội thảo!",
    "notifyEmails":["phamvanlong@haui.edu.vn"]}');

INSERT INTO forms (form_id, owner_id, short_code, title, description, status,
                   is_anonymous, require_login, limit_one_response,
                   max_responses, open_at, close_at, settings)
VALUES (3, 3, 'PtHoc26x',
  'Khảo sát nhu cầu sử dụng phòng tự học',
  'Khảo sát mở cho mọi người học, không yêu cầu đăng nhập.',
  'CLOSED', 1, 0, 0, NULL,
  TIMESTAMP '2026-01-05 00:00:00', TIMESTAMP '2026-10-20 23:59:59',
  '{"category":"KHAO_SAT_CHUNG","theme":"#2E7D32",
    "confirmationMessage":"Cảm ơn bạn đã tham gia khảo sát."}');

INSERT INTO forms (form_id, owner_id, short_code, title, status)
VALUES (4, 2, 'Dx9Lp3Qr', 'Đăng ký đề tài bài tập lớn học kỳ 2', 'DRAFT');

INSERT INTO form_collaborators (form_id, user_id, permission)
VALUES (1, 3, 'VIEWER');
INSERT INTO form_collaborators (form_id, user_id, permission)
VALUES (2, 6, 'EDITOR');
-- #endregion

-- #region data_questions
-- Biểu mẫu 1: lấy ý kiến người học
INSERT INTO questions (question_id, form_id, sort_order, question_type,
                       title, is_required, config)
VALUES (1, 1, 1, 'LINEAR_SCALE',
  'Mức độ hài lòng chung của bạn về học phần', 1,
  '{"min":1,"max":5,"minLabel":"Rất không hài lòng","maxLabel":"Rất hài lòng"}');
INSERT INTO questions (question_id, form_id, sort_order, question_type,
                       title, is_required)
VALUES (2, 1, 2, 'SINGLE_CHOICE',
  'Giảng viên đảm bảo thời gian lên lớp theo kế hoạch', 1);
INSERT INTO questions (question_id, form_id, sort_order, question_type,
                       title, is_required, config)
VALUES (3, 1, 3, 'MULTI_CHOICE',
  'Những hoạt động giúp bạn tiếp thu tốt nhất', 1,
  '{"minSelect":1,"maxSelect":3}');
INSERT INTO questions (question_id, form_id, sort_order, question_type,
                       title, is_required, config)
VALUES (4, 1, 4, 'PARAGRAPH',
  'Góp ý khác để học phần được tốt hơn', 0, '{"maxLength":1000}');

-- Biểu mẫu 2: đăng ký hội thảo
INSERT INTO questions (question_id, form_id, sort_order, question_type,
                       title, is_required, config)
VALUES (5, 2, 1, 'SHORT_TEXT', 'Số điện thoại liên hệ', 1,
  '{"pattern":"^0[0-9]{9}$","maxLength":10}');
INSERT INTO questions (question_id, form_id, sort_order, question_type,
                       title, is_required)
VALUES (6, 2, 2, 'DROPDOWN', 'Bạn biết đến hội thảo qua kênh nào?', 1);
INSERT INTO questions (question_id, form_id, sort_order, question_type,
                       title, is_required)
VALUES (7, 2, 3, 'SINGLE_CHOICE',
  'Bạn có cần giấy chứng nhận tham dự không?', 1);

-- Biểu mẫu 3: khảo sát phòng tự học
INSERT INTO questions (question_id, form_id, sort_order, question_type,
                       title, is_required)
VALUES (8, 3, 1, 'SINGLE_CHOICE',
  'Khung giờ bạn thường sử dụng phòng tự học', 1);
INSERT INTO questions (question_id, form_id, sort_order, question_type,
                       title, is_required, config)
VALUES (9, 3, 2, 'NUMBER', 'Số giờ tự học trung bình mỗi tuần', 1,
  '{"min":0,"max":80}');

-- Biểu mẫu 4: bản nháp
INSERT INTO questions (question_id, form_id, sort_order, question_type,
                       title, is_required)
VALUES (10, 4, 1, 'SHORT_TEXT', 'Tên đề tài dự kiến', 1);
-- #endregion

-- #region data_options
INSERT INTO question_options (option_id, question_id, sort_order, label)
  VALUES (1, 2, 1, 'Luôn luôn');
INSERT INTO question_options (option_id, question_id, sort_order, label)
  VALUES (2, 2, 2, 'Thường xuyên');
INSERT INTO question_options (option_id, question_id, sort_order, label)
  VALUES (3, 2, 3, 'Thỉnh thoảng');
INSERT INTO question_options (option_id, question_id, sort_order, label)
  VALUES (4, 2, 4, 'Hiếm khi');
INSERT INTO question_options (option_id, question_id, sort_order, label)
  VALUES (5, 3, 1, 'Bài giảng lý thuyết');
INSERT INTO question_options (option_id, question_id, sort_order, label)
  VALUES (6, 3, 2, 'Thực hành trên Oracle');
INSERT INTO question_options (option_id, question_id, sort_order, label)
  VALUES (7, 3, 3, 'Làm bài tập lớn theo nhóm');
INSERT INTO question_options (option_id, question_id, sort_order, label)
  VALUES (8, 3, 4, 'Thảo luận trên lớp');
INSERT INTO question_options (option_id, question_id, sort_order, label)
  VALUES (9, 6, 1, 'Fanpage Đoàn Thanh niên');
INSERT INTO question_options (option_id, question_id, sort_order, label)
  VALUES (10, 6, 2, 'Email của Nhà trường');
INSERT INTO question_options (option_id, question_id, sort_order, label)
  VALUES (11, 6, 3, 'Bạn bè giới thiệu');
INSERT INTO question_options (option_id, question_id, sort_order, label)
  VALUES (12, 7, 1, 'Có');
INSERT INTO question_options (option_id, question_id, sort_order, label)
  VALUES (13, 7, 2, 'Không');
INSERT INTO question_options (option_id, question_id, sort_order, label)
  VALUES (14, 8, 1, 'Sáng (7h – 11h)');
INSERT INTO question_options (option_id, question_id, sort_order, label)
  VALUES (15, 8, 2, 'Chiều (13h – 17h)');
INSERT INTO question_options (option_id, question_id, sort_order, label)
  VALUES (16, 8, 3, 'Tối (18h – 21h)');
-- #endregion

-- #region data_responses
-- Biểu mẫu 1 giới hạn 1 phản hồi/người nên once_key = respondent_id
INSERT INTO responses (response_id, form_id, respondent_id, once_key,
                       submitted_at, duration_sec, ip_address)
VALUES (1, 1, 5, 5, TIMESTAMP '2026-10-02 08:15:00', 185, '10.10.1.25');
INSERT INTO responses (response_id, form_id, respondent_id, once_key,
                       submitted_at, duration_sec, ip_address)
VALUES (2, 1, 6, 6, TIMESTAMP '2026-10-03 20:40:00', 240, '10.10.1.31');
INSERT INTO responses (response_id, form_id, respondent_id, once_key,
                       submitted_at, duration_sec, ip_address)
VALUES (3, 1, 7, 7, TIMESTAMP '2026-10-10 09:05:00', 150, '10.10.2.14');
INSERT INTO responses (response_id, form_id, respondent_id, once_key,
                       submitted_at, duration_sec, ip_address)
VALUES (4, 1, 8, 8, TIMESTAMP '2026-10-21 14:30:00', 320, '10.10.3.77');

-- Biểu mẫu 2: đã có 2/3 chỗ được đăng ký
INSERT INTO responses (response_id, form_id, respondent_id, once_key,
                       submitted_at, duration_sec, ip_address)
VALUES (5, 2, 5, 5, TIMESTAMP '2026-10-16 10:00:00', 60, '10.10.1.25');
INSERT INTO responses (response_id, form_id, respondent_id, once_key,
                       submitted_at, duration_sec, ip_address)
VALUES (6, 2, 7, 7, TIMESTAMP '2026-10-18 19:22:00', 75, '10.10.2.14');

-- Biểu mẫu 3: không yêu cầu đăng nhập nên respondent_id để trống
INSERT INTO responses (response_id, form_id, submitted_at,
                       duration_sec, ip_address)
VALUES (7, 3, TIMESTAMP '2026-09-12 07:45:00', 40, '10.10.4.8');
INSERT INTO responses (response_id, form_id, submitted_at,
                       duration_sec, ip_address)
VALUES (8, 3, TIMESTAMP '2026-09-25 21:10:00', 35, '10.10.5.19');
-- #endregion

-- #region data_answers
-- Phản hồi 1
INSERT INTO answers (response_id, question_id, answer_number) VALUES (1, 1, 5);
INSERT INTO answers (response_id, question_id, option_id)     VALUES (1, 2, 1);
INSERT INTO answers (response_id, question_id, option_id)     VALUES (1, 3, 6);
INSERT INTO answers (response_id, question_id, option_id)     VALUES (1, 3, 7);
INSERT INTO answers (response_id, question_id, answer_text)   VALUES (1, 4,
  'Nên tăng thời lượng thực hành sao lưu và phục hồi bằng RMAN.');
-- Phản hồi 2
INSERT INTO answers (response_id, question_id, answer_number) VALUES (2, 1, 4);
INSERT INTO answers (response_id, question_id, option_id)     VALUES (2, 2, 2);
INSERT INTO answers (response_id, question_id, option_id)     VALUES (2, 3, 6);
INSERT INTO answers (response_id, question_id, option_id)     VALUES (2, 3, 8);
-- Phản hồi 3
INSERT INTO answers (response_id, question_id, answer_number) VALUES (3, 1, 3);
INSERT INTO answers (response_id, question_id, option_id)     VALUES (3, 2, 1);
INSERT INTO answers (response_id, question_id, option_id)     VALUES (3, 3, 5);
INSERT INTO answers (response_id, question_id, answer_text)   VALUES (3, 4,
  'Mong giảng viên chia sẻ thêm tình huống thực tế khi vận hành CSDL.');
-- Phản hồi 4
INSERT INTO answers (response_id, question_id, answer_number) VALUES (4, 1, 5);
INSERT INTO answers (response_id, question_id, option_id)     VALUES (4, 2, 1);
INSERT INTO answers (response_id, question_id, option_id)     VALUES (4, 3, 6);
INSERT INTO answers (response_id, question_id, option_id)     VALUES (4, 3, 7);
INSERT INTO answers (response_id, question_id, option_id)     VALUES (4, 3, 8);
-- Phản hồi 5, 6 (đăng ký hội thảo)
INSERT INTO answers (response_id, question_id, answer_text) VALUES (5, 5, '0912345678');
INSERT INTO answers (response_id, question_id, option_id)   VALUES (5, 6, 9);
INSERT INTO answers (response_id, question_id, option_id)   VALUES (5, 7, 12);
INSERT INTO answers (response_id, question_id, answer_text) VALUES (6, 5, '0987654321');
INSERT INTO answers (response_id, question_id, option_id)   VALUES (6, 6, 11);
INSERT INTO answers (response_id, question_id, option_id)   VALUES (6, 7, 13);
-- Phản hồi 7, 8 (phòng tự học)
INSERT INTO answers (response_id, question_id, option_id)     VALUES (7, 8, 14);
INSERT INTO answers (response_id, question_id, answer_number) VALUES (7, 9, 10);
INSERT INTO answers (response_id, question_id, option_id)     VALUES (8, 8, 16);
INSERT INTO answers (response_id, question_id, answer_number) VALUES (8, 9, 15);

COMMIT;
-- #endregion

-- #region identity_sync
-- Đồng bộ bộ đếm IDENTITY sau khi đã chèn khóa chính tường minh
ALTER TABLE departments MODIFY dept_id
  GENERATED BY DEFAULT ON NULL AS IDENTITY (START WITH LIMIT VALUE);
ALTER TABLE users MODIFY user_id
  GENERATED BY DEFAULT ON NULL AS IDENTITY (START WITH LIMIT VALUE);
ALTER TABLE forms MODIFY form_id
  GENERATED BY DEFAULT ON NULL AS IDENTITY (START WITH LIMIT VALUE);
ALTER TABLE questions MODIFY question_id
  GENERATED BY DEFAULT ON NULL AS IDENTITY (START WITH LIMIT VALUE);
ALTER TABLE question_options MODIFY option_id
  GENERATED BY DEFAULT ON NULL AS IDENTITY (START WITH LIMIT VALUE);
ALTER TABLE responses MODIFY response_id
  GENERATED BY DEFAULT ON NULL AS IDENTITY (START WITH LIMIT VALUE);
-- #endregion

-- #region bulk_data
-- Sinh 3.000 phản hồi cho biểu mẫu 3, rải từ 05/01/2026 đến 19/10/2026
DECLARE
  v_response_id  responses.response_id%TYPE;
  v_submitted    TIMESTAMP;
BEGIN
  FOR i IN 1 .. 3000 LOOP
    v_submitted := TIMESTAMP '2026-01-05 07:00:00'
      + NUMTODSINTERVAL(TRUNC(DBMS_RANDOM.VALUE(0, 288)), 'DAY')
      + NUMTODSINTERVAL(TRUNC(DBMS_RANDOM.VALUE(0, 14 * 60)), 'MINUTE');

    INSERT INTO responses (form_id, submitted_at, duration_sec, ip_address)
    VALUES (3, v_submitted, TRUNC(DBMS_RANDOM.VALUE(20, 180)),
            '10.10.' || TRUNC(DBMS_RANDOM.VALUE(1, 255))
                     || '.' || TRUNC(DBMS_RANDOM.VALUE(1, 255)))
    RETURNING response_id INTO v_response_id;

    -- Câu 8: chọn ngẫu nhiên 1 trong 3 khung giờ (option 14..16)
    INSERT INTO answers (response_id, question_id, option_id)
    VALUES (v_response_id, 8, 14 + TRUNC(DBMS_RANDOM.VALUE(0, 3)));

    -- Câu 9: số giờ tự học từ 2 đến 29
    INSERT INTO answers (response_id, question_id, answer_number)
    VALUES (v_response_id, 9, TRUNC(DBMS_RANDOM.VALUE(2, 30)));
  END LOOP;

  -- Cập nhật bộ đếm phản hồi của từng biểu mẫu
  UPDATE forms f
     SET response_count = (SELECT COUNT(*)
                             FROM responses r
                            WHERE r.form_id = f.form_id);
  COMMIT;
END;
/
-- #endregion

-- #region check_counts
SELECT 'DEPARTMENTS' AS bang, COUNT(*) AS so_dong FROM departments
UNION ALL SELECT 'USERS',              COUNT(*) FROM users
UNION ALL SELECT 'FORMS',              COUNT(*) FROM forms
UNION ALL SELECT 'FORM_COLLABORATORS', COUNT(*) FROM form_collaborators
UNION ALL SELECT 'QUESTIONS',          COUNT(*) FROM questions
UNION ALL SELECT 'QUESTION_OPTIONS',   COUNT(*) FROM question_options
UNION ALL SELECT 'RESPONSES',          COUNT(*) FROM responses
UNION ALL SELECT 'ANSWERS',            COUNT(*) FROM answers;
-- #endregion

-- #region check_partitions
-- Thu thập thống kê rồi xem số dòng trên từng phân vùng
EXEC DBMS_STATS.GATHER_SCHEMA_STATS('HAUIFORM');

SELECT table_name, partition_name, high_value, num_rows
  FROM user_tab_partitions
 WHERE table_name IN ('RESPONSES', 'ANSWERS')
 ORDER BY table_name, partition_position;
-- #endregion

-- #region check_json
-- Đọc thuộc tính trong cột JSON settings của biểu mẫu
SELECT f.form_id,
       f.short_code,
       JSON_VALUE(f.settings, '$.category')            AS category,
       JSON_VALUE(f.settings, '$.theme')               AS theme,
       JSON_VALUE(f.settings, '$.confirmationMessage') AS confirm_msg
  FROM forms f
 WHERE JSON_VALUE(f.settings, '$.category'
         RETURNING VARCHAR2(30) ERROR ON ERROR NULL ON EMPTY)
       IN ('DANH_GIA_GIANG_DAY', 'DANG_KY_SU_KIEN');
-- #endregion
