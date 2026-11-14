'use strict';
// "Oracle Lab": các kịch bản minh họa trực tiếp trên CSDL cho buổi báo cáo.
// Mỗi kịch bản trả về danh sách bước: câu lệnh SQL, tài khoản chạy, kết quả / lỗi.
const db = require('./db');
const { oracledb, oraError } = db;

const ARR = { outFormat: oracledb.OUT_FORMAT_ARRAY };

const ANSWERS = {
  1: '[{"q":1,"n":4},{"q":2,"o":2},{"q":3,"o":6},{"q":3,"o":8},{"q":4,"t":"Gửi từ Oracle Lab"}]',
  2: '[{"q":5,"t":"0901234567"},{"q":6,"o":10},{"q":7,"o":12}]',
};

const SUBMIT_SQL = `BEGIN
  hauiform.pkg_response.submit(
    p_form_id     => :f,
    p_user_id     => :u,
    p_answers     => :a,
    p_response_id => :rid);
END;`;

const submitBinds = (formId, userId, answers) => ({
  f: formId, u: userId,
  a: { val: answers || ANSWERS[formId], type: oracledb.CLOB },
  rid: { dir: oracledb.BIND_OUT, type: oracledb.NUMBER },
});

const state = { scn: null, scnAt: null };

// ------------------------------------------------------------------ tiện ích
async function exec(conn, opts) {
  const t0 = Date.now();
  const base = { title: opts.title, as: opts.as, sql: opts.show || opts.sql.trim(), note: opts.note };
  try {
    const r = await conn.execute(opts.sql, opts.binds || {}, ARR);
    const out = { ...base, ok: true, ms: Date.now() - t0 };
    if (r.metaData) {
      out.columns = r.metaData.map((m) => m.name);
      out.rows = r.rows;
    } else if (r.rowsAffected !== undefined && /^\s*(INSERT|UPDATE|DELETE|MERGE)/i.test(opts.sql)) {
      out.message = `${r.rowsAffected} dòng bị tác động`;
    } else if (r.outBinds && r.outBinds.rid !== undefined) {
      out.message = `Thành công - response_id = ${r.outBinds.rid}`;
    } else {
      out.message = 'Thành công';
    }
    return out;
  } catch (err) {
    return { ...base, ok: false, ms: Date.now() - t0, error: oraError(err) };
  }
}

const ownerStep = (opts) => db.withOwner((c) => exec(c, { as: 'HAUIFORM', ...opts }));
const appStep = (userId, opts) =>
  db.withApp(userId, (c) => exec(c, { as: `HF_APP (người dùng ${userId ?? 'khách'})`, ...opts }));

// Mở sẵn n kết nối HF_APP (đã gán ngữ cảnh), rồi bắn đồng thời n yêu cầu
async function parallelApp(userIds, sql, bindsFor) {
  const pool = [];
  for (const u of userIds) {
    const conn = await db.withApp.__getRaw(u);
    pool.push({ u, conn });
  }
  const t0 = Date.now();
  const res = await Promise.all(pool.map(async ({ u, conn }, i) => {
    const s = Date.now();
    try {
      const r = await conn.execute(sql, bindsFor(u, i));
      return { i: i + 1, u, ok: true, ms: Date.now() - s, rid: r.outBinds && r.outBinds.rid };
    } catch (err) {
      return { i: i + 1, u, ok: false, ms: Date.now() - s, error: oraError(err) };
    }
  }));
  await Promise.all(pool.map(({ conn }) => conn.close()));
  return { res, total: Date.now() - t0 };
}

async function parallelOwner(n, sql, bindsFor) {
  const conns = [];
  for (let i = 0; i < n; i++) conns.push(await db.withOwner.__getRaw());
  const res = await Promise.all(conns.map(async (conn, i) => {
    const s = Date.now();
    try {
      await conn.execute(sql, bindsFor(i));
      return { i: i + 1, ok: true, ms: Date.now() - s };
    } catch (err) {
      return { i: i + 1, ok: false, ms: Date.now() - s, error: oraError(err) };
    }
  }));
  await Promise.all(conns.map((c) => c.close()));
  return res;
}

const resetRace = () => ownerStep({
  title: 'Đặt lại biểu mẫu 2: còn 1/3 chỗ, mở đăng ký 30 ngày',
  sql: 'BEGIN hauiform.pkg_demo.reset_race; END;',
});
const resetDup = (u) => ownerStep({
  title: `Đặt lại: xóa phản hồi của người dùng ${u} trên biểu mẫu 1`,
  sql: 'BEGIN hauiform.pkg_demo.reset_duplicate(:u); END;', binds: { u },
});

// ------------------------------------------------------------------ kịch bản
const actions = {
  // ===== Kiểm soát nộp trùng =====
  async 'dup-sequential'({ userId = 14 }) {
    const u = Number(userId);
    return [
      await resetDup(u),
      await appStep(u, { title: 'Lần gửi thứ nhất', sql: SUBMIT_SQL, binds: submitBinds(1, u) }),
      await appStep(u, {
        title: 'Lần gửi thứ hai (sinh viên bấm Gửi lại / mở tab khác)',
        sql: SUBMIT_SQL, binds: submitBinds(1, u),
        note: 'Thủ tục phát hiện ở bước (4) và báo lỗi nghiệp vụ ORA-20020',
      }),
      await ownerStep({
        title: 'Kiểm tra: số phản hồi của người dùng trên biểu mẫu 1',
        sql: 'SELECT respondent_id, COUNT(*) AS so_lan_nop FROM hauiform.responses WHERE form_id = 1 AND respondent_id = :u GROUP BY respondent_id',
        binds: { u },
      }),
    ];
  },

  async 'dup-parallel'({ userId = 15, n = 6 }) {
    const u = Number(userId);
    n = Math.min(Math.max(Number(n) || 6, 2), 12);
    const steps = [await resetDup(u)];
    const { res, total } = await parallelApp(Array(n).fill(u), SUBMIT_SQL, () => submitBinds(1, u));
    steps.push({
      title: `${n} yêu cầu gửi ĐỒNG THỜI của cùng một sinh viên (giả lập bấm đúp, nhiều tab)`,
      as: `HF_APP (${n} phiên song song, người dùng ${u})`,
      sql: SUBMIT_SQL, ok: true, ms: total,
      columns: ['YEU_CAU', 'KET_QUA', 'THOI_GIAN_MS', 'CHAN_BOI'],
      rows: res.map((r) => [
        `#${r.i}`,
        r.ok ? `Thành công (response_id ${r.rid})` : `${r.error.code}: ${r.error.message}`,
        r.ms,
        r.ok ? '-' : (/lúc/.test(r.error.message)
          ? 'Bước (4) trong thủ tục'
          : 'Chỉ mục duy nhất UX_RESPONSES_ONCE'),
      ]),
      note: 'Các phiên cùng vượt qua bước kiểm tra (4) sẽ phải chờ ở chỉ mục duy nhất; khi phiên đầu COMMIT, các phiên còn lại nhận ORA-00001 và được thủ tục đổi thành ORA-20020.',
    });
    steps.push(await ownerStep({
      title: 'Kết quả cuối cùng trong CSDL',
      sql: 'SELECT respondent_id, once_key, COUNT(*) AS so_lan_nop FROM hauiform.responses WHERE form_id = 1 AND respondent_id = :u GROUP BY respondent_id, once_key',
      binds: { u },
    }));
    return steps;
  },

  async 'dup-bypass'() {
    const u = 16;
    const pre = [
      await resetDup(u),
      await appStep(u, { title: 'Sinh viên 16 nộp hợp lệ qua thủ tục', sql: SUBMIT_SQL, binds: submitBinds(1, u) }),
    ];
    return db.withOwner(async (c) => {
      const steps = pre;
      steps.push(await exec(c, {
        as: 'HAUIFORM', title: 'Lách thủ tục: INSERT trực tiếp lần nữa, cố tình để once_key = NULL',
        sql: 'INSERT INTO hauiform.responses (form_id, respondent_id, once_key) VALUES (1, 16, NULL)',
        note: 'Trigger TRG_RESPONSES_BI gán lại once_key = respondent_id nên chỉ mục duy nhất vẫn chặn',
      }));
      steps.push(await exec(c, {
        as: 'HAUIFORM', title: 'Biểu mẫu không giới hạn (biểu mẫu 3): trigger để once_key = NULL',
        sql: `SELECT limit_one_response, (SELECT COUNT(*) FROM hauiform.responses r
                WHERE r.form_id = 3 AND r.once_key IS NOT NULL) AS dong_co_once_key
                FROM hauiform.forms WHERE form_id = 3`,
      }));
      await c.execute('ROLLBACK');
      return steps;
    });
  },

  // ===== Tranh chấp chỗ cuối cùng =====
  async 'race-naive'() {
    const users = [3, 4, 6, 8, 9, 10, 11, 12];
    const steps = [await resetRace()];
    const res = await parallelOwner(users.length,
      'BEGIN hauiform.pkg_demo.submit_naive(2, :u); END;', (i) => ({ u: users[i] }));
    steps.push({
      title: '8 người đăng ký cùng lúc bằng thủ tục SAI (đọc COUNT rồi mới INSERT, không khóa)',
      as: 'HAUIFORM (8 phiên song song)', ok: true,
      sql: `SELECT COUNT(*) INTO v_count FROM responses WHERE form_id = 2;
IF v_count >= v_max THEN RAISE_APPLICATION_ERROR(-20021, 'Đủ chỗ'); END IF;
DBMS_SESSION.SLEEP(0.5);
INSERT INTO responses (form_id, respondent_id) VALUES (2, :u);
COMMIT;`,
      columns: ['PHIEN', 'NGUOI_DUNG', 'KET_QUA', 'THOI_GIAN_MS'],
      rows: res.map((r) => [`#${r.i}`, users[r.i - 1],
        r.ok ? 'Đăng ký thành công' : `${r.error.code}: ${r.error.message}`, r.ms]),
    });
    steps.push(await ownerStep({
      title: 'Kết quả: số đăng ký thực tế vượt số chỗ',
      sql: `SELECT max_responses AS so_cho,
       (SELECT COUNT(*) FROM hauiform.responses WHERE form_id = 2) AS so_dang_ky_thuc_te
  FROM hauiform.forms WHERE form_id = 2`,
      note: 'Lost update / race condition: mọi phiên đều đọc thấy COUNT = 2 < 3 trước khi phiên nào kịp ghi.',
    }));
    return steps;
  },

  async 'race-safe'() {
    const users = [3, 4, 6, 8, 9, 10, 11, 12];
    const steps = [await resetRace()];
    const { res, total } = await parallelApp(users, SUBMIT_SQL, (u) => submitBinds(2, u));
    steps.push({
      title: '8 người đăng ký cùng lúc qua PKG_RESPONSE.SUBMIT (SELECT ... FOR UPDATE)',
      as: 'HF_APP (8 phiên song song)', ok: true, ms: total, sql: SUBMIT_SQL,
      columns: ['PHIEN', 'NGUOI_DUNG', 'KET_QUA', 'THOI_GIAN_MS'],
      rows: res.map((r) => [`#${r.i}`, r.u,
        r.ok ? `Thành công (response_id ${r.rid})` : `${r.error.code}: ${r.error.message}`, r.ms]),
      note: 'Phiên đầu tiên khóa dòng biểu mẫu; các phiên khác xếp hàng. Khi phiên đầu COMMIT, biểu mẫu vừa đủ chỗ và tự chuyển CLOSED.',
    });
    steps.push(await ownerStep({
      title: 'Kết quả: đúng 3/3 chỗ, biểu mẫu tự đóng',
      sql: `SELECT status, max_responses AS so_cho, response_count,
       (SELECT COUNT(*) FROM hauiform.responses WHERE form_id = 2) AS so_dang_ky_thuc_te
  FROM hauiform.forms WHERE form_id = 2`,
    }));
    return steps;
  },

  // ===== Giao dịch =====
  async 'tx-atomic'() {
    const u = 10;
    return [
      await resetDup(u),
      await ownerStep({ title: 'Trước khi nộp', sql: 'SELECT response_count, (SELECT MAX(response_id) FROM hauiform.responses) AS max_response_id FROM hauiform.forms WHERE form_id = 1' }),
      await appStep(u, {
        title: 'Nộp phiếu có câu trả lời cho câu hỏi 5 (thuộc biểu mẫu 2)',
        sql: SUBMIT_SQL,
        binds: submitBinds(1, u, '[{"q":1,"n":3},{"q":2,"o":1},{"q":3,"o":5},{"q":5,"t":"0912345678"}]'),
        note: 'RESPONSES và ANSWERS đã được INSERT ở bước (7), (8) rồi mới phát hiện lỗi; ROLLBACK TO SAVEPOINT hủy toàn bộ.',
      }),
      await ownerStep({ title: 'Sau khi lỗi: không còn dữ liệu dở dang', sql: 'SELECT response_count, (SELECT COUNT(*) FROM hauiform.responses WHERE form_id = 1 AND respondent_id = 10) AS phan_hoi_sv10 FROM hauiform.forms WHERE form_id = 1' }),
    ];
  },

  async 'tx-lock'() {
    const steps = [];
    const a = await db.withOwner.__getRaw();
    const b = await db.withOwner.__getRaw();
    try {
      steps.push(await exec(a, { as: 'Phiên A', title: 'Phiên A khóa dòng biểu mẫu 2 (chưa COMMIT)', sql: 'SELECT form_id, response_count, max_responses FROM hauiform.forms WHERE form_id = 2 FOR UPDATE' }));
      steps.push(await exec(b, { as: 'Phiên B', title: 'Phiên B xin khóa, không chờ (NOWAIT)', sql: 'SELECT form_id FROM hauiform.forms WHERE form_id = 2 FOR UPDATE NOWAIT' }));
      steps.push(await exec(b, { as: 'Phiên B', title: 'Phiên B chờ tối đa 2 giây (WAIT 2)', sql: 'SELECT form_id FROM hauiform.forms WHERE form_id = 2 FOR UPDATE WAIT 2' }));
      steps.push(await exec(b, { as: 'Phiên B', title: 'Phiên B vẫn ĐỌC được (người đọc không bị chặn bởi người ghi)', sql: 'SELECT form_id, response_count FROM hauiform.forms WHERE form_id = 2' }));
      steps.push(await exec(a, { as: 'Phiên A', title: 'Phiên A kết thúc giao dịch, nhả khóa', sql: 'ROLLBACK' }));
      steps.push(await exec(b, { as: 'Phiên B', title: 'Phiên B xin khóa lại', sql: 'SELECT form_id FROM hauiform.forms WHERE form_id = 2 FOR UPDATE NOWAIT' }));
      await b.execute('ROLLBACK');
    } finally {
      await a.close();
      await b.close();
    }
    return steps;
  },

  async 'tx-isolation'() {
    const steps = [await resetDup(14), await resetDup(15)];
    const a = await db.withOwner.__getRaw();
    const count = 'SELECT COUNT(*) AS so_phan_hoi FROM hauiform.responses WHERE form_id = 1';
    try {
      steps.push(await exec(a, { as: 'Phiên A', title: 'READ COMMITTED (mặc định) - lần đọc 1', sql: count }));
      steps.push(await appStep(14, { title: 'Phiên B: sinh viên 14 nộp và COMMIT', sql: SUBMIT_SQL, binds: submitBinds(1, 14) }));
      steps.push(await exec(a, { as: 'Phiên A', title: 'READ COMMITTED - lần đọc 2: thấy ngay dữ liệu mới', sql: count }));
      await a.execute('COMMIT');
      steps.push(await exec(a, { as: 'Phiên A', title: 'Bắt đầu giao dịch SERIALIZABLE', sql: 'SET TRANSACTION ISOLATION LEVEL SERIALIZABLE' }));
      steps.push(await exec(a, { as: 'Phiên A', title: 'SERIALIZABLE - lần đọc 1', sql: count }));
      steps.push(await appStep(15, { title: 'Phiên B: sinh viên 15 nộp và COMMIT', sql: SUBMIT_SQL, binds: submitBinds(1, 15) }));
      steps.push(await exec(a, { as: 'Phiên A', title: 'SERIALIZABLE - lần đọc 2: vẫn là ảnh chụp lúc bắt đầu', sql: count }));
      steps.push(await exec(a, { as: 'Phiên A', title: 'Phiên A ghi vào dòng mà phiên B đã sửa', sql: 'UPDATE hauiform.forms SET description = description WHERE form_id = 1' }));
      steps.push(await exec(a, { as: 'Phiên A', title: 'Kết thúc giao dịch', sql: 'ROLLBACK' }));
      steps.push(await exec(a, { as: 'Phiên A', title: 'Giao dịch mới: thấy dữ liệu của phiên B', sql: count }));
    } finally {
      await a.close();
    }
    return steps;
  },

  // ===== Trigger =====
  async trigger() {
    return db.withOwner(async (c) => {
      const s = [];
      s.push(await exec(c, { as: 'HAUIFORM', title: 'TRG_RESPONSES_BU: sửa một phản hồi đã nộp', sql: 'UPDATE hauiform.responses SET duration_sec = 1 WHERE form_id = 3 AND ROWNUM = 1' }));
      s.push(await exec(c, { as: 'HAUIFORM', title: 'TRG_QUESTIONS_GUARD: xóa câu hỏi của biểu mẫu đã có phản hồi', sql: 'DELETE FROM hauiform.questions WHERE question_id = 4' }));
      s.push(await exec(c, { as: 'HAUIFORM', title: 'TRG_FORMS_BU: tắt "mỗi người một lần" khi đã có phản hồi', sql: 'UPDATE hauiform.forms SET limit_one_response = 0 WHERE form_id = 1' }));
      s.push(await exec(c, { as: 'HAUIFORM', title: 'TRG_USERS_AUDIT: nâng quyền một sinh viên lên ADMIN rồi hạ lại', sql: "UPDATE hauiform.users SET user_role = CASE user_role WHEN 'USER' THEN 'ADMIN' ELSE 'USER' END WHERE user_id = 16" }));
      s.push(await exec(c, { as: 'HAUIFORM', title: '', sql: "UPDATE hauiform.users SET user_role = 'USER' WHERE user_id = 16" }));
      await c.execute('COMMIT');
      s.push(await exec(c, {
        as: 'HAUIFORM', title: 'Nhật ký AUDIT_LOGS do trigger ghi',
        sql: `SELECT log_id, table_name, operation, record_id,
       JSON_VALUE(old_values, '$.user_role') AS role_cu,
       JSON_VALUE(new_values, '$.user_role') AS role_moi,
       db_user, TO_CHAR(action_at, 'HH24:MI:SS') AS luc
  FROM hauiform.audit_logs
 ORDER BY log_id DESC FETCH FIRST 6 ROWS ONLY`,
      }));
      return s.filter((x) => x.title);
    });
  },

  // ===== View =====
  async views() {
    return [
      await appStep(2, { title: 'V_FORM_OVERVIEW: trạng thái tính toán, số chỗ còn lại', sql: 'SELECT form_id, short_code, state_label, accepting, max_responses, response_count, seats_left, question_count, category FROM hauiform.v_form_overview ORDER BY form_id' }),
      await appStep(2, { title: 'V_OPTION_STATS: tỷ lệ chọn từng phương án (biểu mẫu 1)', sql: 'SELECT question_no, label, votes, pct FROM hauiform.v_option_stats WHERE form_id = 1 ORDER BY question_no, option_id' }),
      await appStep(3, { title: 'V_NUMERIC_STATS: thống kê câu hỏi số (biểu mẫu 3)', sql: 'SELECT form_id, question_no, question_type, answer_count, avg_value, min_value, max_value, median_value FROM hauiform.v_numeric_stats WHERE form_id = 3' }),
      await appStep(3, { title: 'V_DAILY_TREND: lũy kế theo ngày (7 ngày cuối của biểu mẫu 3)', sql: 'SELECT submit_day, responses, avg_duration_sec, cumulative FROM hauiform.v_daily_trend WHERE form_id = 3 ORDER BY submit_day DESC FETCH FIRST 7 ROWS ONLY' }),
      await ownerStep({ title: 'View WITH READ ONLY: kể cả chủ sở hữu cũng không sửa được qua view', sql: "UPDATE hauiform.v_form_overview SET title = 'x' WHERE form_id = 1" }),
      await ownerStep({ title: 'Làm mới materialized view MV_MONTHLY_RESPONSES', sql: "BEGIN DBMS_MVIEW.REFRESH('HAUIFORM.MV_MONTHLY_RESPONSES', 'C'); END;" }),
      await ownerStep({ title: 'Đọc materialized view (dữ liệu đã tổng hợp sẵn)', sql: "SELECT form_id, TO_CHAR(month_start, 'MM/YYYY') AS thang, responses, avg_duration_sec, distinct_ip FROM hauiform.mv_monthly_responses ORDER BY form_id, month_start" }),
    ];
  },

  // ===== Bảo vệ người dùng =====
  async 'sec-privs'() {
    return [
      await appStep(5, { title: 'Vai trò của tài khoản ứng dụng HF_APP', sql: 'SELECT role FROM session_roles' }),
      await appStep(5, { title: 'Quyền hệ thống: chỉ có CREATE SESSION', sql: 'SELECT privilege FROM session_privs' }),
      await appStep(5, { title: 'Quyền đối tượng được cấp qua HF_APP_ROLE', sql: "SELECT table_name, privilege FROM role_tab_privs WHERE role = 'HF_APP_ROLE' ORDER BY privilege, table_name" }),
      await appStep(5, { title: 'Thử đọc mật khẩu băm trong bảng USERS', sql: 'SELECT username, password_hash FROM hauiform.users' }),
      await appStep(5, { title: 'Thử xóa dữ liệu phản hồi trực tiếp', sql: 'DELETE FROM hauiform.responses WHERE form_id = 1' }),
      await appStep(5, { title: 'Thử đóng biểu mẫu trực tiếp (chỉ có quyền SELECT)', sql: "UPDATE hauiform.forms SET status = 'CLOSED' WHERE form_id = 1" }),
      await appStep(5, { title: 'Thử nộp thay người khác (ngữ cảnh là sinh viên 5, p_user_id = 6)', sql: SUBMIT_SQL, binds: submitBinds(1, 6) }),
    ];
  },

  async 'sec-vpd'() {
    const sql = `SELECT response_id, form_id, respondent_id, respondent, ip_address
  FROM hauiform.v_response_list
 WHERE form_id IN (1, 2)
 ORDER BY response_id`;
    const steps = [
      await ownerStep({ title: 'Chủ schema HAUIFORM (không chịu VPD) - thấy toàn bộ danh tính', sql }),
      await appStep(2, { title: 'GV Trần Minh Đức - chủ biểu mẫu 1 (ẩn danh): thấy phản hồi nhưng danh tính bị che', sql }),
      await appStep(4, { title: 'CB Phạm Văn Long - chủ biểu mẫu 2 (không ẩn danh): chỉ thấy phản hồi của biểu mẫu 2, có danh tính', sql }),
      await appStep(5, { title: 'SV Nguyễn Thị Mai Anh: chỉ thấy phản hồi của chính mình', sql }),
      await appStep(1, { title: 'Quản trị viên (ADMIN): thấy mọi dòng, danh tính phiếu ẩn danh vẫn bị che', sql }),
    ];
    try {
      const c = await oracledb.getConnection({ user: db.cfg.reportUser, password: db.cfg.reportPassword, connectString: db.cfg.connectString });
      try {
        steps.push(await exec(c, { as: 'HF_REPORT', title: 'Tài khoản báo cáo HF_REPORT: thấy số liệu, không thấy danh tính', sql }));
      } finally { await c.close(); }
    } catch (err) {
      steps.push({ title: 'Tài khoản báo cáo HF_REPORT', as: 'HF_REPORT', sql, ok: false, error: oraError(err) });
    }
    return steps;
  },

  async 'sec-lockout'() {
    const steps = [];
    const tries = [
      ['Sai mật khẩu lần 1', 'sai_mat_khau_1'],
      ['Sai mật khẩu lần 2', 'sai_mat_khau_2'],
      ['Sai mật khẩu lần 3 (đạt FAILED_LOGIN_ATTEMPTS = 3)', 'sai_mat_khau_3'],
      ['Đăng nhập ĐÚNG mật khẩu ngay sau đó', db.cfg.reportPassword],
    ];
    for (const [title, pw] of tries) {
      const t0 = Date.now();
      try {
        const c = await oracledb.getConnection({ user: db.cfg.reportUser, password: pw, connectString: db.cfg.connectString });
        await c.close();
        steps.push({ title, as: 'HF_REPORT', sql: `CONNECT hf_report/******@${db.cfg.connectString}`, ok: true, ms: Date.now() - t0, message: 'Đăng nhập thành công' });
      } catch (err) {
        steps.push({ title, as: 'HF_REPORT', sql: `CONNECT hf_report/******@${db.cfg.connectString}`, ok: false, ms: Date.now() - t0, error: oraError(err) });
      }
    }
    steps.push(await ownerStep({
      title: 'Unified Auditing ghi lại các lần đăng nhập thất bại (chính sách HF_POL_LOGON)',
      sql: `SELECT TO_CHAR(event_timestamp, 'HH24:MI:SS') AS luc, dbusername, action_name,
       return_code, client_program_name
  FROM unified_audit_trail
 WHERE dbusername = 'HF_REPORT' AND action_name = 'LOGON'
 ORDER BY event_timestamp DESC FETCH FIRST 6 ROWS ONLY`,
      note: 'Tài khoản tự mở khóa sau PASSWORD_LOCK_TIME = 1 phút (giá trị demo).',
    }));
    return steps;
  },

  async audit() {
    return [
      await ownerStep({
        title: 'Nhật ký Unified Auditing của các chính sách HF_*',
        sql: `SELECT TO_CHAR(event_timestamp, 'DD/MM HH24:MI:SS') AS luc, dbusername,
       action_name, object_name, unified_audit_policies AS chinh_sach, return_code
  FROM unified_audit_trail
 WHERE unified_audit_policies LIKE '%HF_POL%'
 ORDER BY event_timestamp DESC FETCH FIRST 15 ROWS ONLY`,
      }),
    ];
  },

  // ===== Flashback =====
  async 'fb-mark'() {
    const s = await ownerStep({
      title: 'Ghi mốc SCN hiện tại',
      sql: `SELECT DBMS_FLASHBACK.GET_SYSTEM_CHANGE_NUMBER AS scn,
       TO_CHAR(SYSTIMESTAMP, 'HH24:MI:SS') AS thoi_diem,
       (SELECT COUNT(*) FROM hauiform.responses WHERE form_id = 1) AS phan_hoi_bm1
  FROM dual`,
    });
    if (s.ok) { state.scn = Number(s.rows[0][0]); state.scnAt = s.rows[0][1]; }
    return [s];
  },

  async 'fb-delete'() {
    return db.withOwner(async (c) => [
      await exec(c, { as: 'HAUIFORM', title: 'Xóa nhầm toàn bộ phản hồi của biểu mẫu 1 và COMMIT', sql: 'DELETE FROM hauiform.responses WHERE form_id = 1' }),
      await exec(c, { as: 'HAUIFORM', title: '', sql: 'COMMIT' }),
      await exec(c, { as: 'HAUIFORM', title: 'Dữ liệu hiện tại', sql: 'SELECT COUNT(*) AS phan_hoi_bm1 FROM hauiform.responses WHERE form_id = 1' }),
    ].filter((x) => x.title));
  },

  async 'fb-update'() {
    return db.withOwner(async (c) => [
      await exec(c, { as: 'HAUIFORM', title: 'Cập nhật tiêu đề nhưng QUÊN mệnh đề WHERE', sql: "UPDATE hauiform.forms SET title = 'Khảo sát thử nghiệm'" }),
      await exec(c, { as: 'HAUIFORM', title: '', sql: 'COMMIT' }),
      await exec(c, { as: 'HAUIFORM', title: 'Dữ liệu hiện tại', sql: 'SELECT form_id, title FROM hauiform.forms ORDER BY form_id' }),
    ].filter((x) => x.title));
  },

  async 'fb-asof'() {
    if (!state.scn) throw new Error('ORA-20099: Chưa ghi mốc SCN (bấm "1. Ghi mốc SCN" trước)');
    return [
      await ownerStep({ title: 'Hiện tại', sql: 'SELECT COUNT(*) AS phan_hoi_bm1 FROM hauiform.responses WHERE form_id = 1' }),
      await ownerStep({ title: `Flashback Query: phản hồi biểu mẫu 1 tại SCN ${state.scn} (${state.scnAt})`, sql: 'SELECT response_id, respondent_id, submitted_at FROM hauiform.responses AS OF SCN :scn WHERE form_id = 1 ORDER BY response_id', binds: { scn: state.scn } }),
      await ownerStep({ title: 'Flashback Query: tiêu đề biểu mẫu tại mốc SCN', sql: 'SELECT form_id, title FROM hauiform.forms AS OF SCN :scn ORDER BY form_id', binds: { scn: state.scn } }),
    ];
  },

  async 'fb-versions'() {
    if (!state.scn) throw new Error('ORA-20099: Chưa ghi mốc SCN');
    return [await ownerStep({
      title: 'Flashback Version Query: lịch sử dòng biểu mẫu 1 kể từ mốc SCN',
      sql: `SELECT versions_startscn AS scn_bat_dau, versions_endscn AS scn_ket_thuc,
       versions_operation AS thao_tac, RAWTOHEX(versions_xid) AS ma_giao_dich, title
  FROM hauiform.forms VERSIONS BETWEEN SCN :scn AND MAXVALUE
 WHERE form_id = 1
 ORDER BY versions_startscn NULLS FIRST`,
      binds: { scn: state.scn },
    })];
  },

  async 'fb-restore'() {
    if (!state.scn) throw new Error('ORA-20099: Chưa ghi mốc SCN');
    const scn = Math.trunc(state.scn);
    return db.withOwner(async (c) => [
      await exec(c, { as: 'HAUIFORM', title: 'Khôi phục cột title bằng Flashback Query + MERGE', sql: `MERGE INTO hauiform.forms f
USING (SELECT form_id, title FROM hauiform.forms AS OF SCN ${scn}) o
   ON (f.form_id = o.form_id)
 WHEN MATCHED THEN UPDATE SET f.title = o.title
                   WHERE DECODE(f.title, o.title, 0, 1) = 1` }),
      await exec(c, { as: 'HAUIFORM', title: '', sql: 'COMMIT' }),
      await exec(c, {
        as: 'HAUIFORM', title: `Thử FLASHBACK TABLE hai bảng cha - con về SCN ${scn}`,
        sql: `FLASHBACK TABLE hauiform.responses, hauiform.answers TO SCN ${scn}`,
        note: 'Flashback Table không hỗ trợ bảng phân vùng tham chiếu (ANSWERS) nên chuyển sang khôi phục có chọn lọc bằng Flashback Query.',
      }),
      await exec(c, { as: 'HAUIFORM', title: 'Chép lại các lượt phản hồi đã mất từ ảnh AS OF SCN', sql: `INSERT INTO hauiform.responses (response_id, form_id, respondent_id, once_key,
                                submitted_at, duration_sec, ip_address, user_agent)
SELECT response_id, form_id, respondent_id, once_key,
       submitted_at, duration_sec, ip_address, user_agent
  FROM hauiform.responses AS OF SCN ${scn}
 WHERE form_id = 1
   AND response_id NOT IN (SELECT response_id FROM hauiform.responses)` }),
      await exec(c, { as: 'HAUIFORM', title: 'Chép lại các câu trả lời tương ứng', sql: `INSERT INTO hauiform.answers (answer_id, response_id, question_id, option_id,
                              answer_text, answer_number, answer_date)
SELECT a.answer_id, a.response_id, a.question_id, a.option_id,
       a.answer_text, a.answer_number, a.answer_date
  FROM hauiform.answers AS OF SCN ${scn} a
 WHERE a.response_id IN (SELECT response_id FROM hauiform.responses WHERE form_id = 1)
   AND a.answer_id NOT IN (SELECT answer_id FROM hauiform.answers)` }),
      await exec(c, { as: 'HAUIFORM', title: '', sql: 'COMMIT' }),
      await exec(c, { as: 'HAUIFORM', title: 'Sau khi khôi phục', sql: `SELECT (SELECT COUNT(*) FROM hauiform.responses WHERE form_id = 1) AS phan_hoi_bm1,
       (SELECT COUNT(*) FROM hauiform.answers a JOIN hauiform.responses r ON r.response_id = a.response_id WHERE r.form_id = 1) AS cau_tra_loi_bm1,
       (SELECT SUBSTR(title, 1, 40) FROM hauiform.forms WHERE form_id = 1) AS tieu_de_bm1
  FROM dual` }),
      await exec(c, { as: 'HAUIFORM', title: 'Dấu vết thao tác xóa vẫn còn trong AUDIT_LOGS', sql: `SELECT log_id, table_name, operation, record_id, db_user, TO_CHAR(action_at, 'HH24:MI:SS') AS luc
  FROM hauiform.audit_logs WHERE table_name = 'RESPONSES'
 ORDER BY log_id DESC FETCH FIRST 5 ROWS ONLY` }),
    ].filter((x) => x.title));
  },

  async 'fb-drop'() {
    return db.withOwner(async (c) => {
      await c.execute(`BEGIN EXECUTE IMMEDIATE 'DROP TABLE hauiform.kq_hk1_2026 PURGE'; EXCEPTION WHEN OTHERS THEN NULL; END;`);
      const s = [];
      s.push(await exec(c, { as: 'HAUIFORM', title: 'Tạo bảng kết quả học kỳ', sql: 'CREATE TABLE hauiform.kq_hk1_2026 AS SELECT form_id, question_no, label, votes, pct FROM hauiform.v_option_stats' }));
      s.push(await exec(c, { as: 'HAUIFORM', title: 'Xóa nhầm bảng', sql: 'DROP TABLE hauiform.kq_hk1_2026' }));
      s.push(await exec(c, { as: 'HAUIFORM', title: 'Bảng nằm trong thùng rác (RECYCLE BIN)', sql: "SELECT object_name, original_name, operation, droptime FROM user_recyclebin WHERE original_name = 'KQ_HK1_2026'" }));
      s.push(await exec(c, { as: 'HAUIFORM', title: 'Flashback Drop', sql: 'FLASHBACK TABLE hauiform.kq_hk1_2026 TO BEFORE DROP' }));
      s.push(await exec(c, { as: 'HAUIFORM', title: 'Bảng đã trở lại', sql: 'SELECT COUNT(*) AS so_dong FROM hauiform.kq_hk1_2026' }));
      await c.execute('DROP TABLE hauiform.kq_hk1_2026 PURGE');
      return s;
    });
  },

  async reset() {
    return [await ownerStep({ title: 'Đưa dữ liệu minh họa về trạng thái ban đầu', sql: 'BEGIN hauiform.pkg_demo.reset_all; END;' })];
  },
};

const catalog = [
  { group: 'Kiểm soát nộp trùng (1 sinh viên - 1 lần)', items: [
    { id: 'dup-sequential', title: 'Gửi 2 lần liên tiếp', desc: 'Sinh viên gửi xong lại bấm Gửi lần nữa' },
    { id: 'dup-parallel', title: 'Gửi đồng thời 6 yêu cầu', desc: 'Bấm đúp / nhiều tab cùng lúc' },
    { id: 'dup-bypass', title: 'Lách thủ tục bằng INSERT', desc: 'Trigger + chỉ mục duy nhất vẫn chặn' },
  ] },
  { group: 'Giao dịch và đồng thời', items: [
    { id: 'race-naive', title: 'Tranh chấp chỗ - cách làm SAI', desc: '8 người, 1 chỗ, không khóa' },
    { id: 'race-safe', title: 'Tranh chấp chỗ - SELECT FOR UPDATE', desc: '8 người, 1 chỗ, có khóa dòng' },
    { id: 'tx-atomic', title: 'Tính nguyên tử', desc: 'Lỗi giữa chừng, không để dữ liệu dở dang' },
    { id: 'tx-lock', title: 'Khóa dòng NOWAIT / WAIT', desc: 'Hai phiên tranh khóa' },
    { id: 'tx-isolation', title: 'READ COMMITTED vs SERIALIZABLE', desc: 'Đọc nhất quán, ORA-08177' },
  ] },
  { group: 'Trigger và View', items: [
    { id: 'trigger', title: 'Trigger nghiệp vụ và nhật ký', desc: 'Bất biến, khóa cấu trúc, audit' },
    { id: 'views', title: 'View và Materialized View', desc: 'Truy vấn thống kê' },
  ] },
  { group: 'Cơ chế bảo vệ người dùng', items: [
    { id: 'sec-privs', title: 'Đặc quyền tối thiểu', desc: 'HF_APP chỉ có SELECT + EXECUTE' },
    { id: 'sec-vpd', title: 'Virtual Private Database', desc: 'Cùng câu lệnh, mỗi người thấy khác nhau' },
    { id: 'sec-lockout', title: 'Khóa tài khoản khi sai mật khẩu', desc: 'Profile + Unified Auditing' },
    { id: 'audit', title: 'Nhật ký Unified Auditing', desc: 'Ai đã làm gì, lúc nào' },
  ] },
  { group: 'Flashback - phục hồi sau thao tác nhầm', items: [
    { id: 'fb-mark', title: '1. Ghi mốc SCN', desc: 'Thời điểm dữ liệu còn đúng' },
    { id: 'fb-delete', title: '2a. Xóa nhầm phản hồi', desc: 'DELETE + COMMIT' },
    { id: 'fb-update', title: '2b. UPDATE quên WHERE', desc: 'Sửa tiêu đề mọi biểu mẫu' },
    { id: 'fb-asof', title: '3. Flashback Query', desc: 'SELECT ... AS OF SCN' },
    { id: 'fb-versions', title: '4. Flashback Version Query', desc: 'Lịch sử các phiên bản dòng' },
    { id: 'fb-restore', title: '5. Khôi phục', desc: 'MERGE / INSERT từ ảnh AS OF SCN' },
    { id: 'fb-drop', title: 'Flashback Drop', desc: 'Lấy lại bảng đã DROP' },
  ] },
  { group: 'Tiện ích', items: [
    { id: 'reset', title: 'Đặt lại dữ liệu minh họa', desc: 'pkg_demo.reset_all' },
  ] },
];

async function run(action, body) {
  const fn = actions[action];
  if (!fn) throw new Error(`ORA-20098: Không có kịch bản ${action}`);
  const t0 = Date.now();
  const steps = await fn(body);
  return { action, ms: Date.now() - t0, steps };
}

module.exports = { catalog, run };
