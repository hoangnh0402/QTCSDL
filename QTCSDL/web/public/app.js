'use strict';
// HaUI Form - giao diện một trang (vanilla JS)

const $app = document.getElementById('app');
const $user = document.getElementById('userSelect');
const state = { user: '', users: [] };

const store = {
  get(k) { try { return localStorage.getItem(k); } catch (_) { return null; } },
  set(k, v) { try { localStorage.setItem(k, v); } catch (_) { /* bỏ qua */ } },
};

// Cho phép chọn người dùng qua URL: ...?as=5#/lab
const urlAs = new URLSearchParams(location.search).get('as');
state.user = urlAs !== null ? urlAs : (store.get('hf_user') || '');

const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => (
  { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

async function api(path, opts = {}) {
  const res = await fetch(path, {
    method: opts.method || 'GET',
    headers: { 'Content-Type': 'application/json', 'X-User-Id': state.user || '' },
    body: opts.body ? JSON.stringify(opts.body) : undefined,
  });
  const data = await res.json();
  if (!res.ok) {
    const e = new Error(data.error ? data.error.message : res.statusText);
    e.ora = data.error;
    throw e;
  }
  return data;
}

function toast(msg) {
  const t = document.getElementById('toast');
  t.textContent = msg; t.hidden = false;
  clearTimeout(toast.h); toast.h = setTimeout(() => { t.hidden = true; }, 4000);
}

const fmtTime = (v) => {
  if (!v) return '';
  const d = new Date(v);
  if (isNaN(d)) return esc(v);
  const p = (n) => String(n).padStart(2, '0');
  return `${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())} ${p(d.getDate())}/${p(d.getMonth() + 1)}/${d.getFullYear()}`;
};
const fmtDate = (v) => {
  if (!v) return '';
  const d = new Date(v); const p = (n) => String(n).padStart(2, '0');
  return isNaN(d) ? esc(v) : `${p(d.getDate())}/${p(d.getMonth() + 1)}/${d.getFullYear()}`;
};
const errBox = (e) => `<div class="alert err"><b>${esc(e.ora ? e.ora.code : 'Lỗi')}</b>: ${esc(e.message)}</div>`;
const currentUser = () => state.users.find((u) => String(u.USER_ID) === String(state.user));

// ------------------------------------------------------------------ người dùng
async function loadUsers() {
  try {
    state.users = await api('/api/users');
    $user.innerHTML = '<option value="">Khách (chưa đăng nhập)</option>' + state.users.map((u) =>
      `<option value="${u.USER_ID}">${esc(u.full_name || u.FULL_NAME)} · ${esc(u.USERNAME)} · ${esc(u.USER_TYPE)}${u.USER_ROLE === 'ADMIN' ? ' · ADMIN' : ''}</option>`).join('');
    $user.value = state.user;
  } catch (e) { toast('Không tải được danh sách người dùng: ' + e.message); }
}
$user.addEventListener('change', () => {
  state.user = $user.value; store.set('hf_user', state.user); route();
});

// ------------------------------------------------------------------ trang danh sách
async function pageForms() {
  $app.innerHTML = '<p class="muted">Đang tải biểu mẫu…</p>';
  const forms = await api('/api/forms');
  const u = currentUser();
  $app.innerHTML = `
    <h1>Biểu mẫu khảo sát</h1>
    <p class="sub">${u ? `Xin chào <b>${esc(u.FULL_NAME)}</b>. ` : 'Bạn đang xem với tư cách khách. '}
      Dữ liệu đọc từ view <code>V_FORM_OVERVIEW</code> và <code>V_USER_SUBMISSIONS</code> qua tài khoản <code>HF_APP</code>.</p>
    <div class="grid">${forms.map(cardForm).join('')}</div>`;
}

function cardForm(f) {
  const stateCls = f.ACCEPTING ? 'ok' : (f.STATUS === 'DRAFT' ? 'gray' : 'err');
  const seats = f.MAX_RESPONSES
    ? `<div class="meta">Đã đăng ký ${f.RESPONSE_COUNT}/${f.MAX_RESPONSES} chỗ</div>
       <div class="seats"><i style="width:${Math.min(100, 100 * f.RESPONSE_COUNT / f.MAX_RESPONSES)}%"></i></div>`
    : `<div class="meta">${f.RESPONSE_COUNT.toLocaleString('vi-VN')} phản hồi</div>`;
  const done = f.SUBMIT_COUNT
    ? `<div class="alert ok" style="padding:6px 10px;font-size:13px">Bạn đã gửi lúc ${fmtTime(f.LAST_SUBMITTED)}</div>` : '';
  const isOwner = String(f.OWNER_ID) === String(state.user) || (currentUser() || {}).USER_ROLE === 'ADMIN';
  return `<article class="card">
    <div class="stripe" style="background:${esc(f.THEME || '#0a5da8')}"></div>
    <div><span class="badge ${stateCls}">${esc(f.STATE_LABEL)}</span>
      ${f.IS_ANONYMOUS ? '<span class="badge gray">Ẩn danh</span>' : ''}
      ${f.LIMIT_ONE_RESPONSE ? '<span class="badge warn">1 người / 1 lần</span>' : ''}
      ${f.REQUIRE_LOGIN ? '' : '<span class="badge gray">Không cần đăng nhập</span>'}</div>
    <h3>${esc(f.TITLE)}</h3>
    <div class="meta">${esc(f.OWNER_NAME)} · ${esc(f.OWNER_DEPT || '')}<br>
      Mã: <b>${esc(f.SHORT_CODE)}</b> · ${f.QUESTION_COUNT} câu hỏi${f.CLOSE_AT ? ` · Hạn: ${fmtTime(f.CLOSE_AT)}` : ''}</div>
    ${seats}${done}
    <div class="actions">
      ${f.STATUS !== 'DRAFT' ? `<a class="btn" href="#/f/${esc(f.SHORT_CODE)}">${f.SUBMIT_COUNT ? 'Xem biểu mẫu' : 'Trả lời'}</a>` : ''}
      ${isOwner || f.SUBMIT_COUNT ? `<a class="btn ghost" href="#/r/${f.FORM_ID}">Kết quả</a>` : `<a class="btn ghost" href="#/r/${f.FORM_ID}">Kết quả (thử VPD)</a>`}
    </div>
  </article>`;
}

// ------------------------------------------------------------------ trang trả lời
async function pageFill(code) {
  $app.innerHTML = '<p class="muted">Đang tải…</p>';
  const f = await api('/api/forms/' + encodeURIComponent(code));
  const started = Date.now();
  const submitted = !!f.SUBMIT_COUNT;
  $app.innerHTML = `
    <p><a href="#/">← Danh sách biểu mẫu</a></p>
    <section class="form-head"><div class="bar" style="background:${esc(f.THEME || '#0a5da8')}"></div>
      <div class="inner">
        <h1>${esc(f.TITLE)}</h1>
        <p class="sub" style="margin:6px 0 10px">${esc(f.DESCRIPTION || '')}</p>
        <span class="badge ${f.ACCEPTING ? 'ok' : 'err'}">${esc(f.STATE_LABEL)}</span>
        ${f.LIMIT_ONE_RESPONSE ? '<span class="badge warn">Mỗi tài khoản chỉ gửi 1 lần</span>' : ''}
        ${f.IS_ANONYMOUS ? '<span class="badge gray">Ẩn danh với người tạo biểu mẫu</span>' : ''}
        ${f.MAX_RESPONSES ? `<span class="badge">Còn ${f.SEATS_LEFT} / ${f.MAX_RESPONSES} chỗ</span>` : ''}
      </div></section>
    <div id="banner" style="margin-top:12px">${submitted
      ? `<div class="alert info">Bạn đã gửi phản hồi lúc <b>${fmtTime(f.LAST_SUBMITTED)}</b>. Giao diện khóa nút Gửi (lớp kiểm soát 1).
         Bấm <b>"Thử gửi lại"</b> để xem CSDL vẫn từ chối dù giao diện bị vượt qua.</div>`
      : (!state.user && f.REQUIRE_LOGIN ? '<div class="alert warn">Biểu mẫu yêu cầu đăng nhập. Chọn tài khoản ở góc trên bên phải.</div>' : '')}</div>
    <form id="fill">${f.questions.map(renderQuestion).join('')}
      <div class="submit-row">
        <button class="btn" type="submit" ${submitted ? 'disabled' : ''}>Gửi phản hồi</button>
        <button class="btn ghost" type="button" id="again">Thử gửi lại (bỏ qua giao diện)</button>
        <button class="btn ghost" type="button" id="burst">Gửi 5 lần cùng lúc</button>
      </div>
    </form>
    <div id="result" style="margin-top:14px"></div>`;

  const collect = () => {
    const fd = new FormData(document.getElementById('fill'));
    const out = [];
    for (const q of f.questions) {
      const key = 'q' + q.QUESTION_ID;
      const vals = fd.getAll(key).filter((v) => v !== '');
      for (const v of vals) {
        if (['SINGLE_CHOICE', 'MULTI_CHOICE', 'DROPDOWN'].includes(q.QUESTION_TYPE)) out.push({ q: q.QUESTION_ID, o: Number(v) });
        else if (['LINEAR_SCALE', 'NUMBER'].includes(q.QUESTION_TYPE)) out.push({ q: q.QUESTION_ID, n: Number(v) });
        else if (q.QUESTION_TYPE === 'DATE') out.push({ q: q.QUESTION_ID, d: v });
        else out.push({ q: q.QUESTION_ID, t: v });
      }
    }
    return out;
  };
  const send = () => api(`/api/forms/${f.FORM_ID}/submit`, {
    method: 'POST', body: { answers: collect(), duration: Math.round((Date.now() - started) / 1000) },
  });
  const $res = document.getElementById('result');

  const once = async () => {
    try {
      const r = await send();
      $res.innerHTML = `<div class="alert ok"><b>${esc(f.CONFIRM_MESSAGE || 'Đã ghi nhận phản hồi.')}</b><br>
        Mã phản hồi: ${r.responseId} · thời gian xử lý ${r.ms} ms</div>`;
      document.querySelector('#fill button[type=submit]').disabled = true;
    } catch (e) { $res.innerHTML = errBox(e); }
  };
  document.getElementById('fill').addEventListener('submit', (ev) => { ev.preventDefault(); once(); });
  document.getElementById('again').addEventListener('click', once);
  document.getElementById('burst').addEventListener('click', async () => {
    $res.innerHTML = '<p class="muted">Đang gửi 5 yêu cầu đồng thời…</p>';
    const rs = await Promise.allSettled([1, 2, 3, 4, 5].map(() => send()));
    $res.innerHTML = `<h2>Kết quả 5 yêu cầu gửi cùng lúc</h2><div class="table-wrap"><table class="data">
      <tr><th>#</th><th>Kết quả</th></tr>
      ${rs.map((r, i) => `<tr><td>${i + 1}</td><td>${r.status === 'fulfilled'
        ? `<span class="badge ok">Thành công</span> response_id = ${r.value.responseId}`
        : `<span class="badge err">${esc(r.reason.ora ? r.reason.ora.code : 'Lỗi')}</span> ${esc(r.reason.message)}`}</td></tr>`).join('')}
    </table></div>`;
  });
}

function renderQuestion(q) {
  const name = 'q' + q.QUESTION_ID;
  const c = q.CONFIG || {};
  let body = '';
  switch (q.QUESTION_TYPE) {
    case 'SINGLE_CHOICE':
      body = `<div class="opts">${q.options.map((o) => `<label><input type="radio" name="${name}" value="${o.OPTION_ID}"> ${esc(o.LABEL)}</label>`).join('')}</div>`; break;
    case 'MULTI_CHOICE':
      body = `<div class="opts">${q.options.map((o) => `<label><input type="checkbox" name="${name}" value="${o.OPTION_ID}"> ${esc(o.LABEL)}</label>`).join('')}</div>`; break;
    case 'DROPDOWN':
      body = `<select name="${name}"><option value="">-- Chọn --</option>${q.options.map((o) => `<option value="${o.OPTION_ID}">${esc(o.LABEL)}</option>`).join('')}</select>`; break;
    case 'LINEAR_SCALE': {
      const min = c.min ?? 1; const max = c.max ?? 5; const opts = [];
      for (let i = min; i <= max; i++) opts.push(`<label><span>${i}</span><input type="radio" name="${name}" value="${i}"></label>`);
      body = `<div class="scale"><span>${esc(c.minLabel || '')}</span>${opts.join('')}<span>${esc(c.maxLabel || '')}</span></div>`; break;
    }
    case 'PARAGRAPH': body = `<textarea name="${name}" maxlength="${c.maxLength || 2000}"></textarea>`; break;
    case 'NUMBER': body = `<input type="number" name="${name}" ${c.min !== undefined ? `min="${c.min}"` : ''} ${c.max !== undefined ? `max="${c.max}"` : ''}>`; break;
    case 'DATE': body = `<input type="date" name="${name}">`; break;
    default: body = `<input type="text" name="${name}" maxlength="${c.maxLength || 500}">`;
  }
  return `<div class="q"><div class="title">${q.SORT_ORDER}. ${esc(q.TITLE)} ${q.IS_REQUIRED ? '<span class="req">*</span>' : ''}</div>
    ${q.HELP_TEXT ? `<div class="help">${esc(q.HELP_TEXT)}</div>` : ''}${body}</div>`;
}

// ------------------------------------------------------------------ trang kết quả
async function pageResults(id) {
  $app.innerHTML = '<p class="muted">Đang tải…</p>';
  const r = await api(`/api/forms/${id}/results`);
  const u = currentUser();
  const byQ = {};
  r.options.forEach((o) => { (byQ[o.QUESTION_ID] = byQ[o.QUESTION_ID] || { title: `${o.QUESTION_NO}. ${o.QUESTION_TITLE}`, rows: [] }).rows.push(o); });
  const visible = r.responses.length;
  $app.innerHTML = `
    <p><a href="#/">← Danh sách biểu mẫu</a></p>
    <h1>Kết quả: ${esc(r.form ? r.form.TITLE : '')}</h1>
    <p class="sub">Đang xem với tư cách <b>${esc(u ? u.FULL_NAME : 'khách')}</b>. Mọi số liệu đi qua chính sách
      <b>Virtual Private Database</b> trên RESPONSES và ANSWERS: mỗi người chỉ thấy phần dữ liệu được phép.</p>
    ${!visible ? '<div class="alert warn">VPD không trả về dòng nào cho tài khoản này (không phải chủ biểu mẫu, người cộng tác, ADMIN, và chưa từng gửi).</div>' : ''}
    ${r.form && r.form.IS_ANONYMOUS ? '<div class="alert info">Biểu mẫu ẩn danh: cột người trả lời bị VPD thay bằng NULL (trừ phản hồi của chính bạn).</div>' : ''}
    ${Object.values(byQ).map((q) => `<h2>${esc(q.title)}</h2>${q.rows.map((o) => `
      <div class="bar-row"><div class="label">${esc(o.LABEL)}</div>
        <div class="track"><div class="fill" style="width:${o.PCT || 0}%"></div></div>
        <div class="num">${o.VOTES} · ${o.PCT ?? 0}%</div></div>`).join('')}`).join('')}
    ${r.numeric.length ? `<h2>Câu hỏi thang đo / số</h2><div class="table-wrap">${table(
      ['Câu', 'Số trả lời', 'Trung bình', 'Nhỏ nhất', 'Lớn nhất', 'Trung vị'],
      r.numeric.map((n) => [`${n.QUESTION_NO}. ${n.QUESTION_TITLE}`, n.ANSWER_COUNT, n.AVG_VALUE, n.MIN_VALUE, n.MAX_VALUE, n.MEDIAN_VALUE]))}</div>` : ''}
    <h2>Phản hồi gần nhất (view V_RESPONSE_LIST)</h2>
    <div class="table-wrap">${table(['Mã', 'respondent_id', 'Người trả lời', 'IP', 'Thời điểm', 'Thời gian (s)', 'Số câu'],
      r.responses.map((x) => [x.RESPONSE_ID, x.RESPONDENT_ID ?? 'NULL', x.RESPONDENT, x.IP_ADDRESS ?? 'NULL', fmtTime(x.SUBMITTED_AT), x.DURATION_SEC, x.ANSWER_COUNT]))}</div>
    ${r.trend.length ? `<h2>Xu hướng theo ngày (V_DAILY_TREND)</h2><div class="table-wrap">${table(['Ngày', 'Phản hồi', 'Lũy kế'],
      r.trend.map((t) => [fmtDate(t.SUBMIT_DAY), t.RESPONSES, t.CUMULATIVE]))}</div>` : ''}`;
}

function table(cols, rows) {
  return `<table class="data"><tr>${cols.map((c) => `<th>${esc(c)}</th>`).join('')}</tr>
    ${rows.map((r) => `<tr>${r.map((v) => `<td class="${typeof v === 'number' ? 'num' : ''}">${v === null || v === undefined ? '<span class="muted">NULL</span>' : esc(v)}</td>`).join('')}</tr>`).join('')}
    ${rows.length ? '' : `<tr><td colspan="${cols.length}" class="muted">(không có dòng nào)</td></tr>`}</table>`;
}

// ------------------------------------------------------------------ Oracle Lab
const SQL_KW = /\b(SELECT|FROM|WHERE|AND|OR|NOT|IN|INSERT|INTO|VALUES|UPDATE|SET|DELETE|MERGE|USING|ON|WHEN|MATCHED|THEN|BEGIN|END|IF|ELSE|CASE|AS|OF|SCN|FOR|NOWAIT|WAIT|COMMIT|ROLLBACK|FLASHBACK|TABLE|TO|BEFORE|DROP|CREATE|ORDER|BY|GROUP|JOIN|FETCH|FIRST|ROWS|ONLY|COUNT|NULL|IS|VERSIONS|BETWEEN|MAXVALUE|TRANSACTION|ISOLATION|LEVEL|SERIALIZABLE|CONNECT|RAISE_APPLICATION_ERROR|DESC|NULLS|DECODE)\b/g;
function hl(sql) {
  return esc(sql)
    .replace(/(&#39;[^&]*?&#39;)/g, '<span class="str">$1</span>')
    .replace(SQL_KW, '<span class="kw">$1</span>')
    .replace(/(--[^\n]*)/g, '<span class="cmt">$1</span>');
}

async function pageLab(active) {
  const cat = await api('/api/lab');
  $app.innerHTML = `
    <h1>Oracle Lab</h1>
    <p class="sub">Chạy trực tiếp các kịch bản minh họa trên Oracle Database 19c: kiểm soát nộp trùng, giao dịch,
      trigger, view, cơ chế bảo vệ người dùng và Flashback. Mỗi bước hiển thị câu lệnh, tài khoản thực thi và kết quả thật.</p>
    <div class="lab">
      <aside>${cat.map((g) => `<div class="group"><h4>${esc(g.group)}</h4>${g.items.map((i) =>
        `<button class="item${i.id === active ? ' active' : ''}" data-id="${i.id}"><b>${esc(i.title)}</b><span>${esc(i.desc)}</span></button>`).join('')}</div>`).join('')}
      </aside>
      <section id="labOut"><div class="alert info">Chọn một kịch bản ở cột bên trái.</div></section>
    </div>`;
  $app.querySelectorAll('.item').forEach((b) => b.addEventListener('click', () => {
    history.replaceState(null, '', '#/lab/' + b.dataset.id);
    $app.querySelectorAll('.item').forEach((x) => x.classList.toggle('active', x === b));
    runLab(b.dataset.id, b.querySelector('b').textContent);
  }));
  if (active) {
    const b = $app.querySelector(`.item[data-id="${active}"]`);
    if (b) runLab(active, b.querySelector('b').textContent);
  }
}

async function runLab(id, title) {
  const out = document.getElementById('labOut');
  out.innerHTML = `<p class="muted">Đang chạy "${esc(title)}"…</p>`;
  try {
    const r = await api('/api/lab/' + id, { method: 'POST', body: {} });
    out.innerHTML = `<h2 style="margin-top:0">${esc(title)} <span class="badge gray">${r.ms} ms</span></h2>` +
      r.steps.map((s, i) => `<div class="step">
        <header><span class="n">${i + 1}</span><span class="t">${esc(s.title)}</span>
          <span class="as">${esc(s.as || '')}</span>
          ${s.ok ? '<span class="badge ok">OK</span>' : `<span class="badge err">${esc(s.error.code)}</span>`}
          ${s.ms !== undefined ? `<span class="badge gray">${s.ms} ms</span>` : ''}</header>
        <pre>${hl(s.sql || '')}</pre>
        <div class="res">
          ${s.ok && s.columns ? `<div class="table-wrap">${table(s.columns, s.rows.map((row) => row.map((v) =>
            (typeof v === 'string' && /^\d{4}-\d\d-\d\dT/.test(v)) ? fmtTime(v) : v)))}</div>` : ''}
          ${s.ok && !s.columns ? `<div class="alert ok">${esc(s.message || 'Thành công')}</div>` : ''}
          ${!s.ok ? `<div class="alert err"><b>${esc(s.error.code)}</b>: ${esc(s.error.message)}</div>` : ''}
          ${s.note ? `<div class="note">💡 ${esc(s.note)}</div>` : ''}
        </div></div>`).join('');
  } catch (e) { out.innerHTML = errBox(e); }
}

// ------------------------------------------------------------------ router
async function route() {
  const h = location.hash || '#/';
  document.querySelectorAll('[data-nav]').forEach((a) =>
    a.classList.toggle('active', (a.dataset.nav === 'lab') === h.startsWith('#/lab')));
  try {
    let m;
    if ((m = h.match(/^#\/f\/(\w+)/))) await pageFill(m[1]);
    else if ((m = h.match(/^#\/r\/(\d+)/))) await pageResults(m[1]);
    else if ((m = h.match(/^#\/lab(?:\/([\w-]+))?/))) await pageLab(m[1]);
    else await pageForms();
  } catch (e) { $app.innerHTML = errBox(e); }
}
window.addEventListener('hashchange', route);
loadUsers().then(route);
