-- =====================================================================
-- HaUI FORM - Script 11: Minh họa giao dịch và kiểm soát nộp trùng
-- Kết nối bằng tài khoản HAUIFORM. Chạy SAU script 10.
-- Kịch bản nhiều phiên song song (bấm Gửi liên tục, tranh chấp chỗ cuối)
-- được minh họa bằng ứng dụng web: trang "Oracle Lab".
-- =====================================================================

-- #region tx_setup
SET SERVEROUTPUT ON
VARIABLE rid NUMBER
EXEC pkg_demo.reset_all;
-- #endregion

-- #region tx_submit_ok
-- (1) Sinh viên 9 nộp biểu mẫu 1: RESPONSES + ANSWERS + FORMS trong MỘT giao dịch
BEGIN
  pkg_response.submit(
    p_form_id     => 1,
    p_user_id     => 9,
    p_answers     => '[{"q":1,"n":5},{"q":2,"o":1},{"q":3,"o":6},'
                  || '{"q":3,"o":7},{"q":4,"t":"Học phần rất bổ ích"}]',
    p_duration    => 140,
    p_ip          => '10.10.1.90',
    p_response_id => :rid);
  DBMS_OUTPUT.PUT_LINE('Đã ghi nhận phản hồi số ' || :rid);
END;
/

SELECT r.response_id, r.respondent_id, r.once_key,
       COUNT(a.answer_id) AS so_cau_tra_loi
  FROM responses r
  JOIN answers a ON a.response_id = r.response_id
 WHERE r.response_id = :rid
 GROUP BY r.response_id, r.respondent_id, r.once_key;
-- #endregion

-- #region tx_dup_again
-- (2) Sinh viên 9 bấm Gửi lần thứ hai
BEGIN
  pkg_response.submit(1, 9, '[{"q":1,"n":1},{"q":2,"o":4},{"q":3,"o":5}]',
                      p_response_id => :rid);
END;
/
-- ORA-20020: Bạn đã gửi phản hồi cho biểu mẫu này lúc ...
-- #endregion

-- #region tx_dup_bypass
-- (3) Cố tình lách thủ tục: INSERT trực tiếp và để once_key = NULL
INSERT INTO responses (form_id, respondent_id, once_key)
VALUES (1, 9, NULL);
-- trg_responses_bi gán lại once_key = 9 nên chỉ mục duy nhất vẫn chặn:
-- ORA-00001: unique constraint (HAUIFORM.UX_RESPONSES_ONCE) violated
-- #endregion

-- #region tx_atomic
-- (4) Tính nguyên tử: phiếu chứa câu hỏi 5 của biểu mẫu khác.
--     Dòng RESPONSES và các dòng ANSWERS đã được ghi ở bước (7), (8)
--     của thủ tục nhưng bị hủy toàn bộ khi phát hiện lỗi.
SELECT response_count FROM forms WHERE form_id = 1;

BEGIN
  pkg_response.submit(1, 10,
    '[{"q":1,"n":3},{"q":2,"o":1},{"q":3,"o":5},{"q":5,"t":"0912345678"}]',
    p_response_id => :rid);
END;
/
-- ORA-20023: Có câu trả lời không thuộc biểu mẫu này

SELECT (SELECT COUNT(*) FROM responses
         WHERE form_id = 1 AND respondent_id = 10) AS phan_hoi_sv10,
       (SELECT response_count FROM forms
         WHERE form_id = 1)                        AS response_count
  FROM dual;
-- #endregion

-- #region tx_savepoint
-- (5) SAVEPOINT: hủy một phần giao dịch khi soạn câu hỏi cho biểu mẫu nháp
DELETE FROM questions WHERE form_id = 4 AND sort_order > 1;
COMMIT;

INSERT INTO questions (form_id, sort_order, question_type, title, is_required)
VALUES (4, 2, 'PARAGRAPH', 'Mô tả ngắn gọn nội dung đề tài', 0);
SAVEPOINT sp_cau_2;

INSERT INTO questions (form_id, sort_order, question_type, title, is_required)
VALUES (4, 3, 'SHORT_TEXT', 'Câu hỏi nhập nhầm', 0);

-- Chỉ hủy câu hỏi thứ 3, giữ câu hỏi thứ 2
ROLLBACK TO SAVEPOINT sp_cau_2;
COMMIT;

SELECT sort_order, question_type, title
  FROM questions WHERE form_id = 4 ORDER BY sort_order;
-- #endregion

-- #region tx_lock
-- (6) Khóa dòng: phiên hiện tại giữ khóa biểu mẫu 2, phiên khác xin khóa NOWAIT
SELECT form_id, response_count, max_responses
  FROM forms
 WHERE form_id = 2
   FOR UPDATE;

SELECT pkg_demo.other_session_lock(2) AS ket_qua FROM dual;
-- Phiên khác bị từ chối: ORA-00054: resource busy and acquire with NOWAIT ...

-- Kết thúc giao dịch, nhả khóa
ROLLBACK;

SELECT pkg_demo.other_session_lock(2) AS ket_qua FROM dual;
-- #endregion

-- #region tx_read_committed
-- (7a) READ COMMITTED (mặc định): mỗi câu lệnh thấy dữ liệu đã COMMIT
--      tại thời điểm câu lệnh bắt đầu
SELECT COUNT(*) AS lan_doc_1 FROM responses WHERE form_id = 1;
EXEC pkg_demo.other_session_submit(1, 11);
SELECT COUNT(*) AS lan_doc_2 FROM responses WHERE form_id = 1;
COMMIT;
-- #endregion

-- #region tx_serializable
-- (7b) SERIALIZABLE: cả giao dịch thấy một ảnh chụp nhất quán
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
SELECT COUNT(*) AS lan_doc_1 FROM responses WHERE form_id = 1;
EXEC pkg_demo.other_session_submit(1, 12);
SELECT COUNT(*) AS lan_doc_2 FROM responses WHERE form_id = 1;
COMMIT;
SELECT COUNT(*) AS sau_commit FROM responses WHERE form_id = 1;
-- #endregion

-- #region tx_08177
-- (7c) SERIALIZABLE và xung đột ghi: phiên khác đã sửa dòng biểu mẫu 2
--      sau khi giao dịch bắt đầu
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
SELECT response_count FROM forms WHERE form_id = 2;
EXEC pkg_demo.other_session_submit(2, 13);
UPDATE forms SET description = description WHERE form_id = 2;
-- ORA-08177: can't serialize access for this transaction
ROLLBACK;
-- #endregion
