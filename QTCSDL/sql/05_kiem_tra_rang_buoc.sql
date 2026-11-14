-- =====================================================================
-- HaUI FORM - Script 05: Kiểm tra ràng buộc toàn vẹn
-- Mỗi câu lệnh dưới đây được thiết kế để BỊ TỪ CHỐI (trừ phép thử 7a)
-- =====================================================================

-- #region test_fk_option
-- (1) Ghi nhận lựa chọn 14 (thuộc câu 8) cho câu hỏi 2
INSERT INTO answers (response_id, question_id, option_id)
VALUES (2, 2, 14);
-- ORA-02291: integrity constraint (HAUIFORM.FK_ANSWERS_OPTION) violated
--            - parent key not found
-- #endregion

-- #region test_once
-- (2) Sinh viên user_id = 5 nộp lần thứ hai cho biểu mẫu 1
INSERT INTO responses (form_id, respondent_id, once_key)
VALUES (1, 5, 5);
-- ORA-00001: unique constraint (HAUIFORM.UX_RESPONSES_ONCE) violated
-- #endregion

-- #region test_json
-- (3) Cấu hình JSON sai cú pháp (thiếu dấu đóng ngoặc)
UPDATE forms SET settings = '{"theme":"#FFFFFF"' WHERE form_id = 4;
-- ORA-40441: JSON syntax error (ràng buộc IS JSON từ chối văn bản sai cú pháp)
-- #endregion

-- #region test_quota
-- (4) Biểu mẫu 2 chỉ có 3 chỗ, không thể ghi nhận 4 phản hồi
UPDATE forms SET response_count = 4 WHERE form_id = 2;
-- ORA-02290: check constraint (HAUIFORM.CK_FORMS_QUOTA) violated

-- (5) Bỏ yêu cầu đăng nhập trong khi vẫn giới hạn 1 phản hồi/người
UPDATE forms SET require_login = 0 WHERE form_id = 1;
-- ORA-02290: check constraint (HAUIFORM.CK_FORMS_ONE_RESP) violated
-- #endregion

-- #region test_empty_answer
-- (6) Câu trả lời không mang giá trị nào
INSERT INTO answers (response_id, question_id) VALUES (2, 4);
-- ORA-02290: check constraint (HAUIFORM.CK_ANSWERS_VALUE) violated
-- #endregion

-- #region test_deferred
-- (7a) Đổi chỗ câu 1 và câu 2: trạng thái trùng thứ tự tạm thời được chấp nhận
UPDATE questions SET sort_order = 2 WHERE question_id = 1;
UPDATE questions SET sort_order = 1 WHERE question_id = 2;
-- Yêu cầu kiểm tra ngay: trạng thái sau hai lệnh UPDATE là hợp lệ
SET CONSTRAINT uq_questions_order IMMEDIATE;
ROLLBACK;

-- (7b) Chỉ cập nhật một câu rồi COMMIT: vi phạm bị phát hiện khi kết thúc giao dịch
UPDATE questions SET sort_order = 2 WHERE question_id = 1;
COMMIT;
-- ORA-02091: transaction rolled back
-- ORA-00001: unique constraint (HAUIFORM.UQ_QUESTIONS_ORDER) violated
-- #endregion
