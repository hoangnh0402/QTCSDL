'use strict';
// Kết nối Oracle bằng node-oracledb (chế độ Thin, không cần Instant Client)
const oracledb = require('oracledb');

oracledb.outFormat = oracledb.OUT_FORMAT_OBJECT;
oracledb.fetchAsString = [oracledb.CLOB];

const cfg = {
  connectString: process.env.DB_CONNECT || 'localhost:1521/ORCLPDB1',
  appUser: process.env.DB_APP_USER || 'hf_app',
  appPassword: process.env.DB_APP_PASSWORD || 'HfApp#2026',
  ownerUser: process.env.DB_OWNER_USER || 'hauiform',
  ownerPassword: process.env.DB_OWNER_PASSWORD || 'HaUIForm#2026',
  reportUser: 'hf_report',
  reportPassword: 'BaoCao#2026',
};

let appPool;   // HF_APP: tài khoản ứng dụng, quyền tối thiểu, chịu VPD
let ownerPool; // HAUIFORM: chỉ dùng cho trang Oracle Lab (minh họa quản trị)

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function init() {
  for (let attempt = 1; ; attempt++) {
    try {
      appPool = await oracledb.createPool({
        user: cfg.appUser, password: cfg.appPassword,
        connectString: cfg.connectString, poolMin: 1, poolMax: 16, poolIncrement: 1,
      });
      ownerPool = await oracledb.createPool({
        user: cfg.ownerUser, password: cfg.ownerPassword,
        connectString: cfg.connectString, poolMin: 1, poolMax: 16, poolIncrement: 1,
      });
      const c = await appPool.getConnection();
      await c.execute('SELECT COUNT(*) FROM hauiform.v_form_overview');
      await c.close();
      console.log('Đã kết nối Oracle:', cfg.connectString);
      return;
    } catch (err) {
      console.log(`Chờ Oracle sẵn sàng (lần ${attempt}): ${err.message.split('\n')[0]}`);
      try { if (appPool) await appPool.close(0); } catch (_) { /* bỏ qua */ }
      try { if (ownerPool) await ownerPool.close(0); } catch (_) { /* bỏ qua */ }
      appPool = ownerPool = undefined;
      await sleep(10000);
    }
  }
}

// Mở kết nối HF_APP, gán ngữ cảnh người dùng (HF_CTX) cho VPD rồi chạy fn
async function withApp(userId, fn) {
  const conn = await appPool.getConnection();
  try {
    if (userId) {
      await conn.execute('BEGIN hauiform.pkg_ctx.set_user(:u); END;', { u: Number(userId) });
    } else {
      await conn.execute('BEGIN hauiform.pkg_ctx.clear_user; END;');
    }
    return await fn(conn);
  } finally {
    try { await conn.execute('BEGIN hauiform.pkg_ctx.clear_user; END;'); } catch (_) { /* bỏ qua */ }
    await conn.close();
  }
}

async function withOwner(fn) {
  const conn = await ownerPool.getConnection();
  try {
    return await fn(conn);
  } finally {
    await conn.close();
  }
}

// Chuyển lỗi Oracle thành { code, message } thân thiện
function oraError(err) {
  const msg = String(err.message || err);
  const m = msg.match(/(ORA-\d{5}):\s*([^\n]*)/);
  return {
    code: m ? m[1] : (err.code || 'ERROR'),
    message: m ? m[2].trim() : msg.split('\n')[0],
    full: msg.split('\n').filter((l) => !/^ORA-06512/.test(l)).join('\n'),
  };
}

// Lấy kết nối "thô" (người gọi tự đóng) - dùng cho kịch bản nhiều phiên song song
withApp.__getRaw = async (userId) => {
  const conn = await appPool.getConnection();
  await conn.execute('BEGIN hauiform.pkg_ctx.set_user(:u); END;', { u: Number(userId) });
  return conn;
};
withOwner.__getRaw = () => ownerPool.getConnection();

module.exports = { oracledb, cfg, init, withApp, withOwner, oraError, sleep };
