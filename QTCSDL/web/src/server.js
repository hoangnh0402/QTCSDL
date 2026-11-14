'use strict';
const path = require('path');
const express = require('express');
const db = require('./db');
const lab = require('./lab');

const app = express();
app.use(express.json({ limit: '200kb' }));
app.use(express.static(path.join(__dirname, '..', 'public')));

// Người dùng hiện tại (bản demo: chọn tài khoản ở thanh trên cùng).
// Trong hệ thống thật, giá trị này lấy từ phiên đăng nhập SSO của Trường.
const currentUser = (req) => {
  const v = Number(req.get('x-user-id'));
  return Number.isInteger(v) && v > 0 ? v : null;
};

const handle = (fn) => async (req, res) => {
  try {
    res.json(await fn(req, res));
  } catch (err) {
    const e = db.oraError(err);
    res.status(400).json({ error: e });
  }
};

// ---------------------------------------------------------------- API ứng dụng
app.get('/api/users', handle(() => db.withApp(null, async (c) => {
  const r = await c.execute(
    `SELECT user_id, username, full_name, user_type, user_role, dept_code
       FROM hauiform.v_user_public WHERE status = 'ACTIVE' ORDER BY user_id`);
  return r.rows;
})));

app.get('/api/forms', handle((req) => db.withApp(currentUser(req), async (c) => {
  const forms = await c.execute(
    `SELECT f.form_id, f.short_code, f.title, f.description, f.status, f.state_label,
            f.accepting, f.is_anonymous, f.require_login, f.limit_one_response,
            f.max_responses, f.response_count, f.seats_left, f.open_at, f.close_at,
            f.owner_id, f.owner_name, f.owner_dept, f.question_count, f.category, f.theme,
            s.submit_count, s.last_submitted
       FROM hauiform.v_form_overview f
       LEFT JOIN hauiform.v_user_submissions s
              ON s.form_id = f.form_id
             AND s.user_id = SYS_CONTEXT('HF_CTX', 'USER_ID')
      ORDER BY f.form_id`);
  return forms.rows;
})));

app.get('/api/forms/:code', handle((req) => db.withApp(currentUser(req), async (c) => {
  const f = await c.execute(
    `SELECT f.*, s.submit_count, s.last_submitted
       FROM hauiform.v_form_overview f
       LEFT JOIN hauiform.v_user_submissions s
              ON s.form_id = f.form_id
             AND s.user_id = SYS_CONTEXT('HF_CTX', 'USER_ID')
      WHERE f.short_code = :code`, { code: req.params.code });
  if (!f.rows.length) throw new Error('ORA-20010: Biểu mẫu không tồn tại');
  const form = f.rows[0];
  const q = await c.execute(
    `SELECT question_id, sort_order, question_type, title, help_text, is_required, config
       FROM hauiform.questions WHERE form_id = :id ORDER BY sort_order`, { id: form.FORM_ID });
  const o = await c.execute(
    `SELECT o.option_id, o.question_id, o.label
       FROM hauiform.question_options o
       JOIN hauiform.questions q ON q.question_id = o.question_id
      WHERE q.form_id = :id ORDER BY o.question_id, o.sort_order`, { id: form.FORM_ID });
  form.questions = q.rows.map((x) => ({
    ...x,
    CONFIG: x.CONFIG ? JSON.parse(x.CONFIG) : {},
    options: o.rows.filter((op) => op.QUESTION_ID === x.QUESTION_ID),
  }));
  return form;
})));

app.post('/api/forms/:id/submit', handle((req) => db.withApp(currentUser(req), async (c) => {
  const t0 = Date.now();
  const r = await c.execute(
    `BEGIN
       hauiform.pkg_response.submit(
         p_form_id => :form_id, p_user_id => :user_id, p_answers => :answers,
         p_duration => :duration, p_ip => :ip, p_user_agent => :ua,
         p_response_id => :rid);
     END;`,
    {
      form_id: Number(req.params.id),
      user_id: currentUser(req),
      answers: { val: JSON.stringify(req.body.answers || []), type: db.oracledb.CLOB },
      duration: Number(req.body.duration) || null,
      ip: req.ip.replace('::ffff:', ''),
      ua: (req.get('user-agent') || '').slice(0, 500),
      rid: { dir: db.oracledb.BIND_OUT, type: db.oracledb.NUMBER },
    });
  return { responseId: r.outBinds.rid, ms: Date.now() - t0 };
})));

app.get('/api/forms/:id/results', handle((req) => db.withApp(currentUser(req), async (c) => {
  const id = Number(req.params.id);
  const [opt, num, list, trend, overview] = await Promise.all([
    c.execute(`SELECT question_id, question_no, question_title, question_type, option_id, label, votes, pct
                 FROM hauiform.v_option_stats WHERE form_id = :id
                ORDER BY question_no, option_id`, { id }),
    c.execute(`SELECT question_id, question_no, question_title, question_type, answer_count,
                      avg_value, min_value, max_value, median_value
                 FROM hauiform.v_numeric_stats WHERE form_id = :id ORDER BY question_no`, { id }),
    c.execute(`SELECT response_id, respondent_id, respondent, ip_address, submitted_at,
                      duration_sec, answer_count
                 FROM hauiform.v_response_list WHERE form_id = :id
                ORDER BY submitted_at DESC FETCH FIRST 20 ROWS ONLY`, { id }),
    c.execute(`SELECT submit_day, responses, cumulative
                 FROM hauiform.v_daily_trend WHERE form_id = :id
                ORDER BY submit_day DESC FETCH FIRST 14 ROWS ONLY`, { id }),
    c.execute(`SELECT form_id, title, is_anonymous, response_count, owner_id, owner_name
                 FROM hauiform.v_form_overview WHERE form_id = :id`, { id }),
  ]);
  return {
    form: overview.rows[0],
    options: opt.rows, numeric: num.rows, responses: list.rows,
    trend: trend.rows.reverse(),
  };
})));

// ---------------------------------------------------------------- Oracle Lab
app.get('/api/lab', (req, res) => res.json(lab.catalog));
app.post('/api/lab/:action', handle((req) => lab.run(req.params.action, req.body || {})));

const port = Number(process.env.PORT) || 3000;
db.init().then(() => {
  app.listen(port, () => console.log(`HaUI Form web: http://localhost:${port}`));
});
