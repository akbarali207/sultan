// Hikvision ISAPI mijozi — HTTP Digest autentifikatsiya bilan (qo'shimcha kutubxonasiz).
// Node 18+ global fetch va crypto ishlatadi.
const crypto = require('crypto');

const CFG = {
  ip: process.env.HIK_IP || '192.0.0.64',
  user: process.env.HIK_USER || 'admin',
  pass: process.env.HIK_PASS || '',
  protocol: process.env.HIK_PROTOCOL || 'http', // http yoki https
};

const md5 = (s) => crypto.createHash('md5').update(s).digest('hex');

function parseAuthHeader(header) {
  const out = {};
  // WWW-Authenticate: Digest qop="auth", realm="...", nonce="...", ...
  const re = /(\w+)=(?:"([^"]*)"|([^,]*))/g;
  let m;
  while ((m = re.exec(header)) !== null) {
    out[m[1]] = m[2] !== undefined ? m[2] : m[3];
  }
  return out;
}

function buildDigestHeader(authParams, { method, uri, user, pass }) {
  const { realm, nonce, qop, opaque } = authParams;
  const ha1 = md5(`${user}:${realm}:${pass}`);
  const ha2 = md5(`${method}:${uri}`);
  const nc = '00000001';
  const cnonce = crypto.randomBytes(8).toString('hex');
  let response;
  if (qop) {
    response = md5(`${ha1}:${nonce}:${nc}:${cnonce}:${qop}:${ha2}`);
  } else {
    response = md5(`${ha1}:${nonce}:${ha2}`);
  }
  let h = `Digest username="${user}", realm="${realm}", nonce="${nonce}", uri="${uri}", response="${response}"`;
  if (qop) h += `, qop=${qop}, nc=${nc}, cnonce="${cnonce}"`;
  if (opaque) h += `, opaque="${opaque}"`;
  return h;
}

// Digest bilan so'rov yuborish (avval 401 olib nonce'ni oladi, keyin avtorizatsiyalangan so'rov)
async function digestRequest(method, path, { body = null, contentType = 'application/json' } = {}) {
  const base = `${CFG.protocol}://${CFG.ip}`;
  const url = base + path;
  const opts = { method, headers: {} };
  if (body !== null) {
    opts.body = typeof body === 'string' ? body : JSON.stringify(body);
    opts.headers['Content-Type'] = contentType;
  }

  // 1-urinish: nonce olish uchun
  let res = await fetch(url, opts);
  if (res.status === 401) {
    const wa = res.headers.get('www-authenticate');
    if (!wa) throw new Error('WWW-Authenticate yo\'q');
    const authParams = parseAuthHeader(wa);
    const authHeader = buildDigestHeader(authParams, {
      method, uri: path, user: CFG.user, pass: CFG.pass,
    });
    const opts2 = { method, headers: { ...opts.headers, Authorization: authHeader } };
    if (body !== null) opts2.body = opts.body;
    res = await fetch(url, opts2);
  }
  const text = await res.text();
  return { status: res.status, body: text };
}

// Qurilma ma'lumotini olish (ulanish testi uchun)
async function getDeviceInfo() {
  const r = await digestRequest('GET', '/ISAPI/System/deviceInfo');
  return r;
}

// Kirish/chiqish (Access Control) eventlarini olish — JSON format
// startTime/endTime: ISO local (masalan 2026-06-18T00:00:00+05:00)
async function fetchAcsEvents(startTime, endTime, searchPosition = 0, maxResults = 50) {
  const searchID = crypto.randomBytes(8).toString('hex');
  const payload = {
    AcsEventCond: {
      searchID,
      searchResultPosition: searchPosition,
      maxResults,
      major: 5,      // 5 = Event (access control)
      minor: 0,      // 0 = barchasi
      startTime,
      endTime,
    },
  };
  const r = await digestRequest('POST', '/ISAPI/AccessControl/AcsEvent?format=json', { body: payload });
  let json = null;
  try { json = JSON.parse(r.body); } catch (_) {}
  return { status: r.status, json, raw: r.body };
}

// Qurilmaga foydalanuvchi (xodim) qo'shish — employeeNo = ilovadagi Face ID raqami.
// Yuz keyin qurilmada shu Employee No ostiga qo'shiladi (yoki rasm yuklanadi).
async function addDeviceUser({ employeeNo, name }) {
  const payload = {
    UserInfo: {
      employeeNo: String(employeeNo),
      name: String(name || `ID${employeeNo}`),
      userType: 'normal',
      Valid: {
        enable: true,
        beginTime: '2024-01-01T00:00:00',
        endTime: '2037-12-31T23:59:59',
        timeType: 'local',
      },
      doorRight: '1',
      RightPlan: [{ doorNo: 1, planTemplateNo: '1' }],
    },
  };
  const r = await digestRequest('POST', '/ISAPI/AccessControl/UserInfo/Record?format=json', { body: payload });
  let json = null;
  try { json = JSON.parse(r.body); } catch (_) {}
  const ok = !!json && (json.statusCode === 1 || json.statusString === 'OK');
  return { ok, status: r.status, json, raw: r.body };
}

// Qurilmadan foydalanuvchini o'chirish (employeeNo bo'yicha)
async function deleteDeviceUser(employeeNo) {
  const payload = {
    UserInfoDetail: { mode: 'byEmployeeNo', EmployeeNoList: [{ employeeNo: String(employeeNo) }] },
  };
  const r = await digestRequest('PUT', '/ISAPI/AccessControl/UserInfoDetail/Delete?format=json', { body: payload });
  let json = null;
  try { json = JSON.parse(r.body); } catch (_) {}
  return { ok: !!json && (json.statusCode === 1 || json.statusString === 'OK'), status: r.status, json, raw: r.body };
}

module.exports = { CFG, digestRequest, getDeviceInfo, fetchAcsEvents, addDeviceUser, deleteDeviceUser };
