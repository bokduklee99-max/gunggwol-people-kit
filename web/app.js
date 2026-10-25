'use strict';
/* 궁궐 사람들 키트 · 학생·교사 화면.
   행사 설정(gp_public)과 역할·미션(gp_content)은 DB에서 읽는다. 관리자 화면은 admin.js, 사용법 카드는 guide.js.
   로그인: 학생은 입장 코드+반·번호·이름+4자리 비밀번호(또는 학교 구글 계정), 교사는 아이디·비밀번호(또는 등록된 구글 계정).
   둘 다 Supabase 익명 세션에 학생·교사를 연결하는 방식이다(gp_bind). */
const BUCKET = 'gp-photos';
const $app = document.getElementById('app');
const $info = document.getElementById('topinfo');
const READY = !!(window.CFG && CFG.url && CFG.key);
const sb = READY ? window.supabase.createClient(CFG.url, CFG.key, { auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true, flowType: 'pkce' } }) : null;

/* ---------- 상태 ---------- */
let P = null;        // gp_public(): 행사 설정
let R = [], RB = {}; // 역할(미션 포함)
let ME = null;       // gp_me()
let TOKEN = null;    // 화면을 떠날 때 마지막 저장에 쓰는 접속 토큰
let SKEW = 0;        // 서버 시각 - 이 기기 시각(ms)
let COUNTS = {};     // 역할별 인원(내 반)
let ENT = {};        // 미션 번호 -> {photo_path, diary, updated_at, url}
let FINAL = null;    // {note, note_at, reflection, reflection_at}
let DRAFT = {};      // 미션 번호 -> {blob, preview, uploading, failed}
let END = null;      // 엔딩 화면 상태
let V = { view: 'boot', role: null, cls: 1, onlyOpen: false, mode: 'student', tab: 'student', admin: 'settings' };
let STAFF = null, DETAIL = null, LOGIN_MSG = '';
let busy = false, tick = null, poll = null;
let GEO = null, GROUP = null;

const h = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const fmtParts = (t, o) => { const p = new Intl.DateTimeFormat('ko-KR', { timeZone: 'Asia/Seoul', hour12: false, ...o }).formatToParts(new Date(t)); return k => (p.find(x => x.type === k) || {}).value; };
const kst = t => { if (!t) return ''; const g = fmtParts(t, { month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit' }); return `${g('month')}/${g('day')} ${g('hour')}:${g('minute')}`; };
const hm = t => { if (!t) return ''; const g = fmtParts(t, { hour: '2-digit', minute: '2-digit' }); return `${g('hour')}:${g('minute')}`; };
const day = t => { if (!t) return ''; const g = fmtParts(t, { month: 'numeric', day: 'numeric', weekday: 'short' }); return `${g('month')}월 ${g('day')}일(${g('weekday')})`; };
const now = () => Date.now() + SKEW;
const stu = () => ME && ME.student;
const staff = () => ME && ME.staff;
const isAdmin = () => !!(staff() && staff().kind === 'admin');
const cap = () => (P && P.role_cap) || 3;
const minD = () => (P ? P.min_diary : 40);
const minR = () => (P ? P.min_reflect : 80);
const endAt = () => hm(P && P.ending_open_at);
const staffClasses = () => { const st = staff(); return st && st.classes ? st.classes : []; };
const staffLabel = () => { const st = staff(); return st.kind === 'admin' ? `${st.name} · 관리자` : `${st.name} · ${staffClasses().join('·') || '-'}반 담임`; };
const tester = () => !!(stu() && stu().tester);
const groupOpen = () => tester() || (P && now() > +new Date(P.role_change_until) && now() < +new Date(P.mission_close_at));
const roleOpen = () => tester() || (P && now() <= +new Date(P.role_change_until));
const phase = () => {           // before | open | ending | late(미션 마감 뒤 엔딩·소감만) | closed
  if (!P) return 'before';
  if (tester()) return 'ending';
  const t = now();
  if (t < +new Date(P.mission_open_at)) return 'before';
  if (t > +new Date(P.mission_close_at)) return t <= +new Date(P.ending_close_at || P.mission_close_at) ? 'late' : 'closed';
  return t >= +new Date(P.ending_open_at) ? 'ending' : 'open';
};
const endOpen = ph => ph === 'ending' || ph === 'late';
const done = i => { const e = ENT[i]; return !!(e && e.photo_path && (e.diary || '').trim().length >= minD()); };
const reduced = () => window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
const museumAt = r => { const i = r.missions.findIndex(m => m.area === '박물관'); return i > 0 ? i : -1; };

function toast(msg) {
  const t = document.getElementById('toast');
  t.textContent = msg; t.hidden = false;
  clearTimeout(toast._h); toast._h = setTimeout(() => t.hidden = true, 4500);
}
function errText(e) {
  const m = (e && (e.message || e.error_description || e.msg)) || '';
  if (/not_staff|not_admin/.test(m)) return '이 일은 선생님 계정으로만 할 수 있소.';
  if (/role_closed/.test(m)) return '역할 고르기가 마감되었소.';
  if (/not_registered/.test(m)) return '먼저 들어오시오(반·번호·이름).';
  if (/group_closed/.test(m)) return '함께 다니기는 역할 고르기가 마감된 뒤에 열리오.';
  if (/in_group/.test(m)) return '이미 모임에 들어가 있소. 먼저 나오시오.';
  if (/no_role/.test(m)) return '역할을 먼저 고르시오.';
  if (/bad_role/.test(m)) return '지금은 고를 수 없는 역할이오.';
  if (/not_open/.test(m)) return '지금은 미션을 저장할 수 있는 시간이 아니오.';
  if (/ending_locked/.test(m)) return '엔딩은 아직 열리지 않았소.';
  if (/Anonymous sign-ins are disabled/i.test(m)) return '아직 로그인 설정이 끝나지 않았소. 담당 선생님께 알려 주시오(설치 안내: 익명 로그인 켜기).';
  if (/rate limit|too many/i.test(m)) return '지금 들어오는 사람이 많소. 1분쯤 뒤 다시 해 보시오.';
  if (/Payload too large|exceeded|too large/i.test(m)) return '사진이 너무 크오. 다른 사진으로 해 보시오.';
  if (/Failed to fetch|NetworkError|network|Load failed/i.test(m)) return '인터넷 연결을 확인하시오. 쓰던 글은 이 기기에 남아 있소.';
  return '서버와 통신하지 못했소. 잠시 뒤 다시 해 보시오.';
}
async function rpc(fn, args) {
  const { data, error } = await sb.rpc(fn, args);
  if (error) throw error;
  return data;
}
function modal(title, msg, okLabel, onOk, cancelLabel = '취소') {
  const m = document.createElement('div');
  m.className = 'modal';
  m.innerHTML = `<div class="box" role="dialog" aria-modal="true" aria-label="${h(title)}"><h2>${h(title)}</h2><p>${msg}</p><div class="row"><button class="btn alt" data-m="no">${h(cancelLabel)}</button><button class="btn" data-m="ok">${h(okLabel)}</button></div></div>`;
  const close = () => m.remove();
  m.addEventListener('click', e => {
    const b = e.target.closest('[data-m]');
    if (b) { close(); if (b.dataset.m === 'ok') onOk(); } else if (e.target === m) close();
  });
  m.addEventListener('keydown', e => { if (e.key === 'Escape') close(); });
  document.body.appendChild(m);
  m.querySelector('[data-m=ok]').focus();
}
const opts = (n, cur, from = 1) => Array.from({ length: n - from + 1 }, (_, i) => i + from).map(v => `<option value="${v}" ${+cur === v ? 'selected' : ''}>${v}</option>`).join('');

/* ---------- 행사 설정·내용 ---------- */
async function loadBase() {
  const t0 = Date.now();
  const [p, c] = await Promise.all([rpc('gp_public'), rpc('gp_content')]);
  P = p; SKEW = +new Date(p.now) - Math.round((t0 + Date.now()) / 2);
  setContent(c);
}
function setContent(list) { R = list || []; RB = Object.fromEntries(R.map(r => [r.id, r])); }
const openRoles = () => R.filter(r => r.enabled);

/* ---------- 자동 저장: 입력을 멈추면 1.5초 뒤 서버에 저장, 기기에도 임시본을 남긴다 ---------- */
const SV = {};       // 키(m1·m2·m3·note·refl) -> {val, state, at, timer, inflight}
const LKEY = k => `gp:d:${stu() && stu().id}:${k}`;
function localPut(k, v) { try { localStorage.setItem(LKEY(k), JSON.stringify({ v, t: Date.now() })); } catch (e) {} }
function localGet(k) { try { return JSON.parse(localStorage.getItem(LKEY(k)) || 'null'); } catch (e) { return null; } }
function localDel(k) { try { localStorage.removeItem(LKEY(k)); } catch (e) {} }
function serverVal(k) { return k[0] === 'm' ? ((ENT[+k.slice(1)] || {}).diary || '') : k === 'note' ? ((FINAL && FINAL.note) || '') : ((FINAL && FINAL.reflection) || ''); }
function serverAt(k) { return k[0] === 'm' ? (ENT[+k.slice(1)] || {}).updated_at : k === 'note' ? FINAL && FINAL.note_at : FINAL && FINAL.reflection_at; }
// 화면에 보일 값: 이 화면에서 쓰는 중인 값 → 서버보다 새 임시본 → 서버 값
function curVal(k) {
  const s = SV[k]; if (s && s.val != null) return s.val;
  const l = localGet(k), sv = serverVal(k), at = serverAt(k);
  if (l && l.v !== sv && (!at || l.t > +new Date(at))) { SV[k] = { val: l.v, state: 'dirty' }; schedule1(k); return l.v; }
  return sv;
}
function schedule1(k, ms = 1500) { const s = SV[k]; clearTimeout(s.timer); s.timer = setTimeout(() => flush(k), ms); }
function edit(k, v) {
  const s = SV[k] = SV[k] || {};
  s.val = v; s.state = 'dirty'; localPut(k, v); schedule1(k); paintAs(k);
}
function saveArgs(k, v) {
  return k[0] === 'm' ? ['gp_save_diary', { p_mission: +k.slice(1), p_diary: v }] : k === 'note' ? ['gp_save_note', { p_text: v }] : ['gp_save_reflection', { p_text: v }];
}
async function flush(k) {
  const s = SV[k]; if (!s || s.val == null) return;
  clearTimeout(s.timer); clearTimeout(s.retry);
  if (s.inflight) { s.again = true; return; }
  const v = s.val;
  if (!v.trim() && !serverVal(k)) { s.state = 'idle'; localDel(k); paintAs(k); return; }
  s.inflight = true; s.state = 'saving'; paintAs(k);
  try {
    const [fn, args] = saveArgs(k, v);
    const t = await rpc(fn, args);
    if (k[0] === 'm') { const n = +k.slice(1); ENT[n] = { ...(ENT[n] || {}), diary: v.trim(), updated_at: t }; }
    else if (k === 'note') FINAL = { ...(FINAL || {}), note: v.trim(), note_at: t };
    else FINAL = { ...(FINAL || {}), reflection: v.trim(), reflection_at: t };
    s.at = t;
    if (s.val === v) { s.state = 'saved'; localDel(k); } else s.state = 'dirty';
  } catch (e) {
    s.state = 'error'; s.err = errText(e);
    if (!/not_open|ending_locked|no_role|not_registered/.test(e && e.message || '')) s.retry = setTimeout(() => flush(k), 15000);
  } finally {
    s.inflight = false; paintAs(k); paintDone(k);
    if (s.again || s.state === 'dirty') { s.again = false; if (s.state === 'dirty') schedule1(k, 300); }
  }
}
function asText(k) {
  const s = SV[k];
  if (!s || s.state === 'idle') { const at = serverAt(k); return at && serverVal(k) ? `저장됨 ${hm(at)}` : ''; }
  if (s.state === 'dirty') return '쓰는 중…';
  if (s.state === 'saving') return '저장하는 중…';
  if (s.state === 'saved') return `자동 저장됨 ${hm(s.at)}`;
  return `저장하지 못했소 · 이 기기에 남아 있소. ${s.err || ''}`;
}
function paintAs(k) {
  document.querySelectorAll(`[data-as="${k}"]`).forEach(el => {
    el.textContent = asText(k); el.className = 'as' + (SV[k] && SV[k].state === 'error' ? ' bad' : SV[k] && SV[k].state === 'saved' ? ' ok' : '');
  });
}
function paintDone(k) {
  if (k[0] !== 'm') return;
  const n = +k.slice(1), li = document.getElementById('m' + n);
  if (li) { li.classList.toggle('done', done(n)); const st = li.querySelector('.stamp'); if (st) st.hidden = !done(n); }
  const c = document.querySelector('[data-mcount]'); if (c) c.textContent = `📷 미션 ${[1, 2, 3].filter(done).length}/3`;
}
function flushAll() { Object.keys(SV).forEach(k => { if (SV[k].state === 'dirty' || SV[k].state === 'error') flush(k); }); }
// 화면을 닫거나 다른 앱으로 넘어갈 때: 저장하지 못한 글을 keepalive 요청으로 한 번 더 보낸다.
function flushBeacon() {
  if (!TOKEN) return;
  Object.keys(SV).forEach(k => {
    const s = SV[k]; if (!(s.state === 'dirty' || s.state === 'error') || s.val == null) return;
    const [fn, args] = saveArgs(k, s.val);
    try { fetch(`${CFG.url}/rest/v1/rpc/${fn}`, { method: 'POST', keepalive: true, headers: { 'Content-Type': 'application/json', apikey: CFG.key, Authorization: `Bearer ${TOKEN}` }, body: JSON.stringify(args) }); } catch (e) {}
  });
}
document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'hidden') flushBeacon(); else flushAll(); });
window.addEventListener('pagehide', flushBeacon);
window.addEventListener('online', flushAll);

/* ---------- 로그인 ---------- */
async function ensureSession() {
  const { data } = await sb.auth.getSession();
  if (data.session) return data.session;
  const { data: d, error } = await sb.auth.signInAnonymously();
  if (error) throw error;
  TOKEN = d.session && d.session.access_token;
  return d.session;
}
const ENTER_MSG = {
  bad_join: '입장 코드가 맞지 않소. 선생님께 다시 확인하시오.',
  mismatch: '이름이나 비밀번호가 맞지 않소. 처음 정한 숫자 4자리를 넣으시오. 잊었거나, 반·번호를 잘못 고른 친구가 먼저 들어온 것 같으면 담임 선생님께 말씀드리시오.',
  locked: '비밀번호를 5번 틀려 15분 동안 잠겼소. 15분 뒤 다시 하거나, 담임 선생님께 풀어 달라고 하시오.',
  slow_down: '너무 여러 번 틀렸소. 10분 뒤 다시 해 보시오.',
  google_only: '이 행사는 학교 구글 계정으로 들어오오.',
  code_only: '이 행사는 입장 코드로 들어오오.',
  not_school: '학교 계정이 아니오. 학교 구글 계정으로 다시 로그인하시오.',
  taken: '그 반·번호로 이미 다른 친구가 들어와 있소. 번호를 확인하고, 맞으면 담임 선생님께 말씀드리시오.',
  bad_class: '반을 다시 고르시오.', bad_num: '번호를 다시 고르시오.', bad_name: '이름을 적으시오(20자까지).',
  bad_pin: '비밀번호는 숫자 4자리로 정하시오.', bad_code: '설치 코드가 맞지 않소. SQL 실행 결과 칸의 코드를 넣으시오.',
  bad_id: '아이디는 영문 소문자·숫자·._- 3~30자로 정하시오.', short_pw: '비밀번호는 8자 이상으로 정하시오.', already: '이미 관리자가 있소. 로그인하시오.',
  expired: '설치 코드의 유효 시간(24시간)이 지났소. Supabase SQL Editor에서 supabase/new_setup_code.sql을 실행해 새 코드를 받으시오.'
};
function login() {
  const google = P.auth_mode === 'google', t = V.tab;
  $app.innerHTML = `
  <p class="eyebrow">${h(P.school_name)} · ${h(P.event_label)} · ${h(day(P.mission_open_at))}</p>
  <h1>궁궐 사람들</h1><div class="rule"></div>
  <p class="lead">그대는 오늘 고종 시대 경복궁의 한 사람이 되오.</p>
  ${LOGIN_MSG ? `<div class="banner no" role="alert" style="margin-top:14px">${LOGIN_MSG}</div>` : ''}
  <div class="seg" role="group" aria-label="누구인가"><button data-act="ltab" data-v="student" aria-pressed="${t === 'student'}">학생</button><button data-act="ltab" data-v="staff" aria-pressed="${t === 'staff'}">선생님</button></div>
  ${t === 'student' ? (google ? `
    <div style="margin-top:20px"><button class="btn block" data-act="google">학교 구글 계정으로 로그인</button></div>
    <p class="muted" style="margin-top:8px;font-size:14px">${P.google_domain ? `@${h(P.google_domain)} 계정만 들어올 수 있소.` : ''}</p>` : `
    <form class="form" data-form="enter" autocomplete="off">
      <div class="field"><label for="f-join">입장 코드</label><input id="f-join" autocapitalize="characters" spellcheck="false" maxlength="12" placeholder="선생님이 알려 준 코드" required></div>
      <div class="row2">
        <div class="field"><label for="f-class">반</label><select id="f-class" required><option value="">선택</option>${opts(P.class_count)}</select></div>
        <div class="field"><label for="f-num">번호</label><select id="f-num" required><option value="">선택</option>${opts(P.max_num)}</select></div>
      </div>
      <div class="field"><label for="f-name">이름</label><input id="f-name" maxlength="20" autocomplete="name" required></div>
      <div class="field"><label for="f-pin">비밀번호 (숫자 4자리)</label><input id="f-pin" type="password" inputmode="numeric" pattern="[0-9]{4}" maxlength="4" autocomplete="off" required>
        <p class="muted" style="font-size:14px;margin-top:6px">처음 들어오면 지금 넣은 숫자가 내 비밀번호가 되오. 다른 기기에서 이어 쓸 때 같은 값을 넣으시오.</p></div>
      <button class="btn block" type="submit">들어가기</button>
    </form>`) : `
    <form class="form" data-form="slogin" autocomplete="on">
      <div class="field"><label for="f-sid">아이디</label><input id="f-sid" autocapitalize="none" spellcheck="false" autocomplete="username" required></div>
      <div class="field"><label for="f-spw">비밀번호</label><input id="f-spw" type="password" autocomplete="current-password" required></div>
      <button class="btn block" type="submit">선생님으로 들어가기</button>
    </form>
    ${google ? '<div style="margin-top:10px"><button class="btn line block" data-act="google">등록된 구글 계정으로 들어가기</button></div>' : ''}
    <p class="muted" style="margin-top:10px;font-size:14px">계정은 담당(관리자) 선생님이 만들어 드리오. 로그인은 12시간 뒤 저절로 끊기오. 공용 PC·전자칠판에서는 다 쓰면 꼭 로그아웃하시오.</p>`}
  <div style="margin-top:16px"><button class="btn line block" data-act="guide">📖 사용법 보기</button></div>
  <section class="panel"><h3>개인정보 안내</h3>${String(P.privacy || '').split('\n').filter(Boolean).map(p => `<p>${h(p)}</p>`).join('')}</section>`;
}
async function submitEnter() {
  const v = id => (document.getElementById(id).value || '').trim();
  const a = { p_join: v('f-join'), p_class: +v('f-class'), p_num: +v('f-num'), p_name: v('f-name'), p_pin: v('f-pin') };
  if (!a.p_join || !a.p_class || !a.p_num || !a.p_name) { toast('입장 코드·반·번호·이름을 모두 적으시오.'); return; }
  if (!/^[0-9]{4}$/.test(a.p_pin)) { toast(ENTER_MSG.bad_pin); return; }
  if (busy) return; busy = true;
  try {
    await ensureSession();
    const r = await rpc('gp_student_enter', a);
    if (r !== 'ok' && r !== 'new') { LOGIN_MSG = h(ENTER_MSG[r] || r); render(); return; }
    LOGIN_MSG = ''; if (r === 'new') toast('들어왔소. 비밀번호 숫자 4자리를 잊지 마시오.');
    await enter();
  } catch (e) { LOGIN_MSG = h(errText(e)); render(); } finally { busy = false; }
}
async function submitStaffLogin() {
  const id = (document.getElementById('f-sid').value || '').trim(), pw = document.getElementById('f-spw').value || '';
  if (!id || !pw) return;
  if (busy) return; busy = true;
  try {
    await ensureSession();
    const r = await rpc('gp_staff_login', { p_login_id: id, p_pw: pw });
    const M = { mismatch: '아이디나 비밀번호가 맞지 않소.', locked: '여러 번 틀려 15분 동안 잠겼소. 관리자 선생님께 풀어 달라고 하시오.', slow_down: '너무 여러 번 틀렸소. 10분 뒤 다시 해 보시오.' };
    if (r !== 'ok') { LOGIN_MSG = h(M[r] || r); render(); return; }
    LOGIN_MSG = ''; try { localStorage.setItem('gp:staff', '1'); } catch (e) {}
    await enter();
  } catch (e) { LOGIN_MSG = h(errText(e)); render(); } finally { busy = false; }
}
async function signInGoogle() {
  const q = { prompt: 'select_account' }; if (P.google_domain) q.hd = P.google_domain;
  const { error } = await sb.auth.signInWithOAuth({ provider: 'google', options: { redirectTo: location.origin + location.pathname, queryParams: q } });
  if (error) toast(errText(error));
}
async function signOut() {
  flushAll();
  try { await rpc('gp_logout'); } catch (e) {}
  await sb.auth.signOut();
  resetState(); V.view = 'login'; render(true);
}
function resetState() {
  ME = null; GROUP = null; COUNTS = {}; ENT = {}; FINAL = null; DRAFT = {}; END = null; STAFF = null; DETAIL = null; LOGIN_MSG = '';
  Object.keys(SV).forEach(k => { clearTimeout(SV[k].timer); clearTimeout(SV[k].retry); delete SV[k]; });
  V = { view: 'login', role: null, cls: 1, onlyOpen: false, mode: 'student', tab: V.tab || 'student', admin: 'settings' };
}

/* ---------- 첫 설치: 관리자 만들기 ---------- */
function setup() {
  $app.innerHTML = `
  <p class="eyebrow">처음 설치</p><h1>관리자 계정 만들기</h1><div class="rule"></div>
  <p class="lead">설치 SQL을 실행했을 때 결과 칸에 나온 <b>설치 코드</b>(12자리, 24시간 유효)를 넣고, 담당 선생님이 쓸 관리자 아이디와 비밀번호를 정하시오. 한 번만 하는 일이오.</p>
  ${P.setup_expired ? `<div class="banner no" role="alert" style="margin-top:14px">${h(ENTER_MSG.expired)} 그다음 이 화면을 새로 고치시오.</div>` : ''}
  ${LOGIN_MSG ? `<div class="banner no" role="alert" style="margin-top:14px">${LOGIN_MSG}</div>` : ''}
  <form class="form" data-form="setup" autocomplete="off">
    <div class="field"><label for="s-code">설치 코드</label><input id="s-code" autocapitalize="characters" spellcheck="false" required></div>
    <div class="field"><label for="s-name">이름(화면에 보일 이름)</label><input id="s-name" maxlength="20" required></div>
    <div class="field"><label for="s-id">관리자 아이디</label><input id="s-id" autocapitalize="none" spellcheck="false" autocomplete="username" placeholder="영문 소문자·숫자 3~30자" required></div>
    <div class="field"><label for="s-pw">비밀번호(8자 이상)</label><input id="s-pw" type="password" autocomplete="new-password" required></div>
    <div class="field"><label for="s-pw2">비밀번호 다시</label><input id="s-pw2" type="password" autocomplete="new-password" required></div>
    <button class="btn block" type="submit">관리자 만들기</button>
  </form>`;
}
async function submitSetup() {
  const v = id => document.getElementById(id).value || '';
  if (v('s-pw') !== v('s-pw2')) { toast('비밀번호 두 칸이 다르오.'); return; }
  if (busy) return; busy = true;
  try {
    await ensureSession();
    const r = await rpc('gp_setup', { p_code: v('s-code').trim(), p_login_id: v('s-id').trim(), p_name: v('s-name').trim(), p_pw: v('s-pw') });
    if (r !== 'ok') { LOGIN_MSG = h(ENTER_MSG[r] || r); if (r === 'already') { await loadBase(); V.view = 'login'; V.tab = 'staff'; } render(); return; }
    LOGIN_MSG = ''; await loadBase(); toast('관리자를 만들었소. [관리]에서 행사 날짜부터 정하시오.');
    await enter(); V.view = 'admin'; render(true);
  } catch (e) { LOGIN_MSG = h(errText(e)); render(); } finally { busy = false; }
}

/* ---------- 교사 첫 로그인: 관리자가 정해 준 비밀번호 바꾸기 ---------- */
function pwchange() {
  $app.innerHTML = `
  <p class="eyebrow">${h(staff().name)} 선생님</p><h1>비밀번호 바꾸기</h1><div class="rule"></div>
  <p class="lead">관리자 선생님이 정해 준 비밀번호로 처음 들어오셨소. 나만 아는 비밀번호로 바꾼 뒤 쓰시오.</p>
  ${LOGIN_MSG ? `<div class="banner no" role="alert" style="margin-top:14px">${LOGIN_MSG}</div>` : ''}
  <form class="form" data-form="pwfirst" autocomplete="on">
    <div class="field"><label for="c-old">받은 비밀번호</label><input id="c-old" type="password" autocomplete="current-password" required></div>
    <div class="field"><label for="c-new">새 비밀번호(8자 이상)</label><input id="c-new" type="password" autocomplete="new-password" required></div>
    <div class="field"><label for="c-new2">새 비밀번호 다시</label><input id="c-new2" type="password" autocomplete="new-password" required></div>
    <button class="btn block" type="submit">바꾸고 시작하기</button>
    <button class="btn line block" type="button" data-act="signout">로그아웃</button>
  </form>`;
}
const PW_MSG = { mismatch: '받은 비밀번호가 맞지 않소.', short_pw: '새 비밀번호는 8자 이상으로 정하시오.', same_pw: '받은 비밀번호와 다르게 정하시오.' };
async function submitPwFirst() {
  const o = document.getElementById('c-old').value, n = document.getElementById('c-new').value, n2 = document.getElementById('c-new2').value;
  if (n !== n2) { LOGIN_MSG = '새 비밀번호 두 칸이 다르오.'; render(); return; }
  if (busy) return; busy = true;
  try {
    const r = await rpc('gp_staff_password', { p_old: o, p_new: n });
    if (r !== 'ok') { LOGIN_MSG = h(PW_MSG[r] || r); render(); return; }
    LOGIN_MSG = ''; toast('비밀번호를 바꿨소.'); await enter();
  } catch (e) { LOGIN_MSG = h(errText(e)); render(); } finally { busy = false; }
}

/* ---------- 로그인 직후 ---------- */
async function enter() {
  try {
    const t0 = Date.now();
    ME = await rpc('gp_me');
    SKEW = +new Date(ME.now) - Math.round((t0 + Date.now()) / 2);
    setContent(await rpc('gp_content'));           // 교사는 꺼 둔 역할까지 받는다
  } catch (e) { LOGIN_MSG = h(errText(e)); V.view = 'login'; render(); return; }
  if (staff() && staff().must_change) { V.mode = 'staff'; V.view = 'pwchange'; render(true); return; }
  if (staff() && !(stu() && V.mode === 'student' && V.view !== 'login')) {
    try { localStorage.setItem('gp:staff', '1'); } catch (e) {}
    V.mode = 'staff'; V.cls = staffClasses()[0] || (isAdmin() ? 1 : 0);
    await openStaff(); staffGuideOnce(); return;
  }
  if (stu()) { await loadStudent(); goStudentHome(); return; }
  if (P.auth_mode === 'google' && ME.google) { V.view = 'register'; render(true); return; }
  staffExpired();
}
// 교사 로그인은 12시간 뒤 끊긴다(공용 PC 대비). 끊긴 기기에서는 안내와 함께 선생님 로그인 화면으로.
function staffExpired() {
  let was = false; try { was = !!localStorage.getItem('gp:staff'); localStorage.removeItem('gp:staff'); } catch (e) {}
  if (was) { LOGIN_MSG = '로그인한 지 12시간이 지나 저절로 로그아웃되었소. 다시 로그인하시오.'; V.tab = 'staff'; }
  V.mode = 'student'; V.view = 'login'; render(true);
}
async function reloadMe() { ME = await rpc('gp_me'); }
async function loadStudent() {
  await loadCounts();
  if (stu().role_id) await loadEntries();
  await loadGroup();
}
async function loadCounts() {
  if (tester()) { COUNTS = {}; return; }
  const rows = await rpc('gp_role_counts', {});
  COUNTS = {}; (rows || []).forEach(r => COUNTS[r.role_id] = r.n);
}
async function loadGroup() {
  GROUP = null;
  if (!stu() || !stu().role_id || !groupOpen()) return;
  try { GROUP = await rpc('gp_group_mine', {}); } catch (e) { GROUP = null; }
}
async function loadEntries() {
  const d = await rpc('gp_my_records');
  ENT = {}; (d.entries || []).forEach(r => ENT[r.mission] = { photo_path: r.photo_path, diary: r.diary || '', updated_at: r.updated_at });
  FINAL = d.final || null;
  const paths = Object.values(ENT).map(x => x.photo_path).filter(Boolean);
  if (paths.length) {
    const { data } = await sb.storage.from(BUCKET).createSignedUrls(paths, 3600);
    (data || []).forEach(x => { const k = Object.keys(ENT).find(i => ENT[i].photo_path === x.path); if (k && x.signedUrl) ENT[k].url = x.signedUrl; });
  }
}
function goStudentHome() {
  V.mode = 'student';
  if (!stu().role_id || !RB[stu().role_id]) { V.view = 'roles'; render(true); return; }
  V.view = 'home'; render(true);
  try { if (!localStorage.getItem(introKey())) showIntro(); } catch (e) {}
}
const introKey = () => `gp:intro:${stu() && stu().id}:${stu() && stu().role_id}`;

/* ---------- 반·번호·이름 (구글 첫 등록·고치기) ---------- */
function register() {
  const s = stu();
  $app.innerHTML = `
  <p class="eyebrow">${s ? '내 정보 고치기' : '처음 오셨소'}</p>
  <h1>반·번호·이름</h1><div class="rule"></div>
  <p class="lead">담임 선생님이 출석을 확인할 때 쓰오. 정확히 적으시오.</p>
  ${s && s.role_id ? '<div class="banner info">반을 바꾸면 고른 역할이 풀리오. 새 반에서 다시 골라야 하오.</div>' : ''}
  ${LOGIN_MSG ? `<div class="banner no" role="alert">${LOGIN_MSG}</div>` : ''}
  <form class="form" data-form="reg">
    <div class="row2">
      <div class="field"><label for="f-class">반</label><select id="f-class" required><option value="">선택</option>${opts(P.class_count, s && s.class_no)}</select></div>
      <div class="field"><label for="f-num">번호</label><select id="f-num" required><option value="">선택</option>${opts(P.max_num, s && s.num)}</select></div>
    </div>
    <div class="field"><label for="f-name">이름</label><input id="f-name" maxlength="20" autocomplete="name" required value="${h(s ? s.name : '')}"></div>
    <button class="btn block" type="submit">${s ? '저장' : '다음'}</button>
    ${s ? '<button class="btn alt block" type="button" data-act="home">취소</button>' : '<button class="btn line block" type="button" data-act="signout">다른 계정으로 로그인</button>'}
  </form>`;
}
async function submitReg() {
  const c = +document.getElementById('f-class').value, n = +document.getElementById('f-num').value, nm = document.getElementById('f-name').value.trim();
  if (!c || !n || !nm) { toast('반·번호·이름을 모두 적으시오.'); return; }
  if (busy) return; busy = true;
  try {
    const r = await rpc(stu() ? 'gp_student_update' : 'gp_student_google', { p_class: c, p_num: n, p_name: nm });
    if (r !== 'ok') { LOGIN_MSG = h(ENTER_MSG[r] || r); render(); return; }
    LOGIN_MSG = ''; await reloadMe(); await loadStudent(); goStudentHome();
  } catch (e) { toast(errText(e)); } finally { busy = false; }
}

/* ---------- 역할 고르기 ---------- */
function seatTag(r) {
  const s = stu(); if (!s || tester()) return '';
  const n = COUNTS[r.id] || 0;
  if (s.role_id === r.id) return '<span class="tag mine">내 역할</span>';
  return n >= cap() ? '<span class="tag full">자리 없음</span>' : `<span class="tag left">남은 자리 ${cap() - n}</span>`;
}
const isFull = r => { const s = stu(); return s && !tester() && s.role_id !== r.id && (COUNTS[r.id] || 0) >= cap(); };
const seal = (r, c) => `<span class="seal${c ? ' ' + c : ''}" aria-hidden="true">${h(r.seal)}</span>`;
// 인물 그림(img/roles/<id>.webp)은 기본 역할 14개에만 있다. 없으면 인장만 보인다.
const face = r => r.img ? `<span class="pt" aria-hidden="true"><img src="img/roles/${h(r.id)}-s.webp" alt="" width="64" height="64" loading="lazy" decoding="async">${seal(r, 'xs')}</span>` : `<span class="pt nopic" aria-hidden="true">${seal(r, 'xs')}</span>`;
const portrait = r => r.img ? `<figure class="rfig"><img src="img/roles/${h(r.id)}.webp" alt="${h(r.name)} ${h(r.person)} 상상 그림" width="480" height="640" decoding="async"></figure>` : '';
document.addEventListener('error', e => {
  const im = e.target;
  if (!(im instanceof HTMLImageElement)) return;
  if (im.closest('.pt')) { im.parentNode.classList.add('nopic'); im.remove(); }
  else if (im.closest('.rfig')) { const f = im.closest('.rfig'); f.parentNode.classList.add('nopic'); f.remove(); }
  else if (im.classList.contains('ipic')) im.remove();
}, true);
function roles() {
  const s = stu(), mine = s && s.role_id, preview = !s || V.mode === 'staff';
  const all = V.mode === 'staff' ? R : openRoles();
  const list = all.filter(r => !V.onlyOpen || !isFull(r));
  $app.innerHTML = `
  <p class="eyebrow">${preview ? '역할 미리보기' : tester() ? '체험 · 정원 없음' : `${s.class_no}반 · 반마다 역할별 ${cap()}명`}</p>
  <h1>누가 되겠소?</h1><div class="rule"></div>
  <p class="lead">역할을 눌러 편지와 미션을 읽어 보고 정하시오. ${preview || tester() ? '' : `먼저 정한 사람이 그 자리를 갖소. ${roleOpen() ? `${kst(P.role_change_until)}까지 바꿀 수 있소.` : '역할 고르기는 마감되었소.'}`}</p>
  ${preview || tester() ? '' : `<div class="seg" role="group" aria-label="보기"><button data-act="only" data-v="0" aria-pressed="${!V.onlyOpen}">전체 ${all.length}</button><button data-act="only" data-v="1" aria-pressed="${V.onlyOpen}">자리 있는 역할 ${all.filter(r => !isFull(r)).length}</button></div>`}
  ${list.length ? '' : '<div class="banner info" style="margin-top:14px">아직 고를 수 있는 역할이 없소. 선생님께 알려 주시오.</div>'}
  <div class="roles">${list.map(r => `<button class="rcard ${mine === r.id ? 'mine' : ''}" data-act="detail" data-v="${h(r.id)}" ${isFull(r) && !preview ? 'disabled aria-disabled="true"' : ''}>
      ${face(r)}
      <span class="body"><span class="nm">${h(r.name)}<small>${h(r.person)}</small></span>
      <span class="in" style="display:block">${h(r.intro)}</span>
      <span class="tags">${seatTag(r)}${r.career ? `<span class="tag">${h(r.career)}</span>` : ''}${!r.enabled ? '<span class="tag full">꺼 둠</span>' : ''}</span></span></button>`).join('')}</div>
  ${mine && V.mode !== 'staff' ? '<div style="margin-top:18px"><button class="btn alt block" data-act="home">내 역할로 돌아가기</button></div>' : ''}
  ${V.mode === 'staff' ? '<div style="margin-top:18px"><button class="btn alt block" data-act="staffback">현황으로 돌아가기</button></div>' : ''}`;
}
const gateLine = () => `<li class="gate">⬇ ${h(P.museum_time)}까지 흥례문 게이트를 나가 박물관 앞에 모이오 · 반별로 입장 (궁에 다시 들어오지 않소)</li>`;
function missionPreview(r) {
  const g = museumAt(r);
  return `<ol class="missions">${r.missions.map((m, i) => `
    ${i === g ? gateLine() : ''}
    <li class="mission"><div class="mh"><span class="no">${i + 1}</span><span><span class="pl">${h(m.place)}</span> <span class="tag ${m.area === '박물관' ? 'museum' : 'palace'}">${h(m.area)}</span></span></div>
      <p class="clue">${h(m.clue)}</p>
      <dl><dt>📷 사진</dt><dd>${h(m.photo)}</dd><dt>✍️ 일기</dt><dd>${h(m.diary)} <span class="muted">(${minD()}자 이상)</span></dd></dl></li>`).join('')}</ol>`;
}
function letter(r) {
  return `<div class="letter">${(r.letter || []).map(p => `<p>${h(p)}</p>`).join('')}<p class="sign">— ${h(r.name)} ${h(r.person)}</p></div>`;
}
function hopae(r, s) {
  return `<div class="hopae" aria-label="호패: ${h(r.name)} ${h(r.person)}"><span class="hole" aria-hidden="true"></span>
    <span class="hv">${h(r.name)}</span><span class="hv big">${h(r.person)}</span>
    ${s ? `<span class="hf">${s.class_no ? `${s.class_no}-${s.num}` : '체험'} ${h(s.name)}</span>` : ''}</div>`;
}
function detail() {
  const r = RB[V.role], s = stu(), isMine = s && s.role_id === r.id, asStaff = V.mode === 'staff';
  const canChoose = !asStaff && s && !isMine && !isFull(r) && roleOpen() && r.enabled;
  $app.innerHTML = `
  <button class="linkbtn" data-act="roles">← 역할 목록</button>
  <div class="rolehead" style="margin-top:8px">${portrait(r)}<div>${seal(r, 'lg')}<p class="eyebrow">${h(r.name)}</p><h1>${h(r.person)}</h1></div></div>
  <div class="tags">${seatTag(r)}${r.career ? `<span class="tag">진로 · ${h(r.career)}</span>` : ''}</div>
  ${letter(r)}
  <h2 style="margin-top:26px">나의 동선</h2>
  <div class="mapbox">${window.palaceMap(r)}</div>
  <h2 style="margin-top:22px">미션 미리보기</h2>
  ${missionPreview(r)}
  <div class="lock"><span class="ic" aria-hidden="true">🔒</span><p>미션을 마치고 나면 이 사람에게 그 뒤 무슨 일이 있었는지 알게 되오. 엔딩은 ${h(day(P.ending_open_at))} ${endAt()}에 열리오.</p></div>
  <div style="margin-top:18px"><button class="btn alt block" data-act="roles">다른 역할 보기</button></div>
  ${canChoose || (isMine && !asStaff) ? `<div class="actionbar">${canChoose ? `<button class="btn block" data-act="choose" data-v="${h(r.id)}">${s.role_id ? '이 역할로 바꾸기' : '이 역할로 정하기'}</button>` : '<button class="btn block" data-act="home">내 역할 화면으로</button>'}</div>` : ''}`;
}
async function choose(id) {
  const r = RB[id], s = stu();
  const go = async () => {
    if (busy) return; busy = true;
    try {
      const res = await rpc('gp_choose_role', { p_role: id });
      await reloadMe(); await loadStudent();
      if (res === 'full') { toast('방금 다른 친구가 그 자리를 가져갔소. 다른 역할을 고르시오.'); V.view = 'roles'; render(true); }
      else { V.view = 'home'; render(true); showIntro(); }
    } catch (e) { toast(errText(e)); } finally { busy = false; }
  };
  modal(`${r.name} ${r.person}`, s.role_id && RB[s.role_id] ? `지금 역할(${h(RB[s.role_id].name)})을 내려놓고 이 역할로 바꾸겠소? 지금 자리는 다른 친구가 가져갈 수 있소.${tester() ? ' 체험 기록은 지워지오.' : ''}` : tester() ? '체험은 언제든 바꿀 수 있소.' : `이 역할로 정하겠소? ${h(kst(P.role_change_until))}까지는 바꿀 수 있소.`, '정하기', go);
}

/* ---------- 시간여행 연출 ---------- */
function showIntro() {
  const s = stu(), r = s && RB[s.role_id]; if (!r) return;
  try { localStorage.setItem(introKey(), '1'); } catch (e) {}
  const o = document.createElement('div');
  o.className = 'intro'; o.setAttribute('role', 'dialog'); o.setAttribute('aria-modal', 'true'); o.setAttribute('aria-label', '시간여행');
  o.innerHTML = `<div class="iwrap"><p class="iyear" aria-live="polite">2026</p><p class="isub">년, 서울 경복궁</p>
    <div class="iafter" hidden><p class="iline">그대는 이제</p><div class="ipair">${hopae(r, s)}${r.img ? `<img class="ipic" src="img/roles/${h(r.id)}.webp" alt="" width="120" height="160">` : ''}</div><p class="iline"><b>${h(r.name)} ${h(r.person)}</b>이오.</p>
    <button class="btn block" data-intro="close">편지 읽기</button></div></div>`;
  document.body.appendChild(o);
  const y = o.querySelector('.iyear'), sub = o.querySelector('.isub'), after = o.querySelector('.iafter');
  const from = new Date().getFullYear();
  y.textContent = String(from);
  const finish = () => { y.textContent = '1890'; sub.textContent = '년 무렵, 고종 시대 경복궁'; after.hidden = false; o.querySelector('[data-intro]').focus(); };
  if (reduced()) finish();
  else {
    const t0 = performance.now(), dur = 1800;
    const step = t => {
      const k = Math.min(1, (t - t0) / dur), e = 1 - Math.pow(1 - k, 3);
      y.textContent = String(Math.round(from - (from - 1890) * e));
      if (k < 1) requestAnimationFrame(step); else setTimeout(finish, 250);
    };
    requestAnimationFrame(step);
  }
  o.addEventListener('click', e => { if (e.target.closest('[data-intro=close]')) { o.classList.add('out'); setTimeout(() => o.remove(), reduced() ? 0 : 350); } });
}

/* ---------- 내 역할(현장) ---------- */
function countdown(t) {
  const ms = +new Date(t) - now(); if (ms <= 0) return '';
  const d = Math.floor(ms / 864e5), hh = Math.floor(ms % 864e5 / 36e5), mm = Math.floor(ms % 36e5 / 6e4);
  return d > 0 ? `${d}일 ${hh}시간` : hh > 0 ? `${hh}시간 ${mm}분` : `${mm}분`;
}
function statusCard() {
  const s = stu(), ph = phase();
  if (ph === 'before') return `<div class="day"><p class="dl">현장체험학습까지</p><p class="dn">${countdown(P.mission_open_at) || '곧'}</p><p class="ds">${h(day(P.mission_open_at))} ${h(P.meet_text)}. 미션은 그날 ${hm(P.mission_open_at)}에 열리오.</p></div>`;
  const ci = s.checkin_at ? `<span class="chk ok">📍 출석 ${hm(s.checkin_at)}</span>` : '';
  const co = s.checkout_at ? `<span class="chk ok">🏁 종례 ${hm(s.checkout_at)}</span>` : '';
  const n = [1, 2, 3].filter(done).length;
  return `<div class="day open">
    <div class="drow"><span class="chk" data-mcount>📷 미션 ${n}/3</span>${ci}${reflDone() ? '<span class="chk ok">📝 소감</span>' : ''}${co}${tester() ? '<span class="chk test">체험 모드</span>' : ''}</div>
    ${ph !== 'closed' && ph !== 'late' && !s.checkin_at ? '<button class="btn block" data-act="checkin">📍 출석 확인 (집결 장소에서 누르시오)</button>' : ''}
    ${ph === 'open' ? `<p class="ds">엔딩까지 ${countdown(P.ending_open_at)} · ${endAt()}에 열리오</p>` : ''}
  </div>`;
}
function missionCard(r, m, i) {
  const n = i + 1, e = ENT[n] || {}, d = DRAFT[n] || {}, k = 'm' + n;
  const editable = phase() === 'open' || phase() === 'ending';
  const img = d.preview || e.url;
  const ok = done(n);
  const head = `<div class="mh"><span class="no">${n}</span><span><span class="pl">${h(m.place)}</span> <span class="tag ${m.area === '박물관' ? 'museum' : 'palace'}">${h(m.area)}</span></span><span class="stamp" aria-label="완료" ${ok ? '' : 'hidden'}>畢</span></div>`;
  if (!editable) {
    const diary = curVal(k);
    return `<li class="mission${ok ? ' done' : ''}" id="m${n}">${head}
      <p class="clue">${h(m.clue)}</p>
      <dl><dt>📷 사진</dt><dd>${h(m.photo)}</dd><dt>✍️ 일기</dt><dd>${h(m.diary)} <span class="muted">(${minD()}자 이상)</span></dd></dl>
      ${img ? `<img class="ph" src="${h(img)}" alt="미션 ${n} 사진">` : ''}${diary ? `<p class="mydiary">${h(diary)}</p>` : ''}</li>`;
  }
  const diary = curVal(k);
  return `<li class="mission${ok ? ' done' : ''}" id="m${n}">${head}
    <p class="clue">${h(m.clue)}</p>
    <p class="task">📷 ${h(m.photo)}</p>
    <label class="shot">${img ? `<img class="ph" src="${h(img)}" alt="미션 ${n} 사진">` : '<span class="ph empty">사진을 찍거나 고르시오</span>'}
      <input type="file" accept="image/*" data-photo="${n}" hidden><span class="btn line sm">${img ? '사진 바꾸기' : '📷 사진 찍기·고르기'}</span></label>
    ${d.uploading ? '<p class="as">사진을 올리는 중…</p>' : d.failed ? `<p class="as bad">사진을 올리지 못했소. <button class="linkbtn" data-act="retryPhoto" data-v="${n}">다시 올리기</button></p>` : e.photo_path ? '<p class="as ok">사진 저장됨</p>' : ''}
    <p class="task">✍️ ${h(m.diary)}</p>
    <textarea data-save="${k}" rows="4" maxlength="2000" placeholder="${h(r.person)}의 마음으로, 본 것과 그렇게 생각한 까닭을 적어 보시오. 쓰는 대로 저절로 저장되오.">${h(diary)}</textarea>
    <div class="mrow"><span class="cnt${diary.trim().length >= minD() ? ' ok' : ''}" data-cnt="${k}">${diary.trim().length}/${minD()}자</span><span class="as" data-as="${k}">${h(asText(k))}</span></div>
    </li>`;
}
function home() {
  const s = stu(), r = RB[s.role_id], ph = phase(), g = museumAt(r);
  const fin = !!(FINAL && FINAL.note);
  $app.innerHTML = `
  <div class="homehead"><div class="hpic${r.img ? '' : ' nopic'}">${portrait(r)}${hopae(r, s)}</div><div><p class="eyebrow">${tester() ? '체험 모드' : `${s.class_no}반 ${s.num}번 ${h(s.name)}`}</p><h1>${h(r.name)}<br>${h(r.person)}</h1></div></div>
  ${statusCard()}
  ${endOpen(ph) ? `<button class="endingcall" data-act="ending">${fin ? '📜 엔딩 다시 보기' : '🔓 엔딩이 열렸소 · 눌러서 보시오'}</button>` : ''}
  ${endOpen(ph) && fin ? reflectBox(false) : ''}
  ${ph === 'ending' && fin && !s.checkout_at ? '<button class="btn block" style="margin-top:10px" data-act="checkout">🏁 종례 확인 (담임 선생님 앞에서 누르시오)</button>' : ''}
  <details class="fold" ${ph === 'before' ? 'open' : ''}><summary>📜 ${h(r.person)}의 편지</summary>${letter(r)}</details>
  <details class="fold" ${ph === 'before' || GEO ? 'open' : ''}><summary>🗺️ 나의 동선</summary><div class="mapbox">${window.palaceMap(r, [1, 2, 3].map(done))}
    <div class="geo"><button class="btn line sm" data-act="locate">${GEO ? '내 위치 끄기' : '📍 내 위치 보기'}</button><span class="gm" id="geomsg">${GEO ? geoMsg() : '궁 안에서는 10~30m쯤 어긋날 수 있소.'}</span></div></div></details>
  ${groupOpen() && ph !== 'closed' ? groupBox() : ''}
  <h2 style="margin-top:22px">${ph === 'before' ? `${h(day(P.mission_open_at))} 나의 미션` : '나의 미션'}</h2>
  <p class="lead">${g > 0 ? `출석 확인 뒤 <b>궁 안</b>부터 가시오. 궁 미션을 마치고 <b>${h(P.museum_time)}까지 국립고궁박물관 앞</b>에 모이오. 반별로 함께 들어가 박물관 미션을 하오.` : '출석 확인 뒤 차례대로 미션 장소를 찾아가시오.'} 일기는 쓰는 대로 저절로 저장되오.</p>
  <ol class="missions">${r.missions.map((m, i) => (i === g ? gateLine() : '') + missionCard(r, m, i)).join('')}</ol>
  ${ph === 'before' || ph === 'open' ? `<div class="lock"><span class="ic" aria-hidden="true">🔒</span><p>엔딩은 ${h(day(P.ending_open_at))} ${endAt()}에 열리오. 그대가 찍은 사진 한 장이 그때 다시 나타날 것이오.</p></div>` : ''}
  <section class="panel"><h3>현장 수칙</h3><ul>${(P.rules || []).map(x => `<li>${h(x)}</li>`).join('')}</ul></section>
  <div style="margin-top:18px;display:grid;gap:10px">
    ${roleOpen() && ph === 'before' || tester() ? '<button class="btn alt block" data-act="roles">역할 바꾸기</button>' : ''}
    <button class="btn line block" data-act="guide">📖 사용법 다시 보기</button>
    ${ph === 'before' ? '<button class="btn line block" data-act="replay">시간여행 다시 보기</button>' : ''}
    ${tester() ? '<button class="btn line block" data-act="staffback">현황으로 돌아가기</button>' : '<button class="btn line block" data-act="editInfo">반·번호·이름 고치기</button>'}
  </div>`;
}

/* ---------- 함께 다니기(역할 마감 뒤, 같은 반 최대 3명) ---------- */
function groupMinutes() {   // 출석 뒤 출발(미션 시작 + 35분 어림) ~ 박물관 집합까지 쓸 수 있는 시간
  const m = /^(\d{1,2}):(\d{2})$/.exec(P.museum_time || ''); if (!m) return 70;
  const g = fmtParts(P.mission_open_at, { hour: '2-digit', minute: '2-digit' });
  const v = (+m[1] * 60 + +m[2]) - (+g('hour') * 60 + +g('minute') + 35);
  return v > 20 ? v : 70;
}
function groupBox() {
  const g = GROUP, LIM = groupMinutes();
  if (!g) return `<details class="fold" id="group"><summary>👫 함께 다니기</summary><div class="gbox">
    <p>같은 반 친구와 <b>최대 3명</b>이 모이면, 모두의 궁 미션 장소를 한 번에 도는 동선을 알려 주오. 사진·일기·엔딩은 지금처럼 각자 남기오.</p>
    <button class="btn block" data-act="gcreate">모임 만들기 (코드 받기)</button>
    <form class="gjoin" data-form="gjoin"><label for="g-code">친구에게 받은 코드</label>
      <div class="grow"><input id="g-code" inputmode="numeric" pattern="[0-9]{4}" maxlength="4" autocomplete="off" placeholder="4자리 숫자"><button class="btn line" type="submit">들어가기</button></div></form>
  </div></details>`;
  const mem = g.members.filter(m => RB[m.role_id]);
  const plan = mem.length > 1 ? window.groupPlan(mem.map(m => ({ name: m.me ? '나' : m.name, me: m.me, role: RB[m.role_id] }))) : null;
  const who = t => t.me ? '<b>나</b>' : h(t.who);
  const circ = n => '①②③'[n - 1];
  let advice = '';
  if (plan) advice = plan.full <= LIM ? '<div class="banner ok">일기까지 그 자리에서 써도 시간이 되오.</div>'
    : plan.quick <= LIM ? '<div class="banner info">궁에서는 <b>사진만 찍고</b> 다음 장소로 가시오. 일기는 박물관에서나 미션 마감 전까지 쓰면 되오.</div>'
    : '<div class="banner no">셋이 다 돌기에는 시간이 모자라오. 먼 곳은 나눠서 다녀온 뒤 다시 만나거나, 둘씩 다니시오.</div>';
  const rooms = {};
  if (plan) plan.museum.forEach(x => { const k = `${x.floor} ${x.room}`; (rooms[k] = rooms[k] || []).push(x.me ? '<b>나</b>' : h(x.who)); });
  return `<details class="fold" id="group" open><summary>👫 함께 다니기 · 코드 ${h(g.code)}</summary><div class="gbox">
    <p class="gcode">모임 코드 <b>${h(g.code)}</b>${mem.length < 3 ? ' · 친구에게 알려 주시오' : ' · 가득 찼소'}</p>
    <div class="gmem">${mem.map(m => `<span class="chip${m.me ? ' me' : ''}">${seal(RB[m.role_id], 'xs')}${m.me ? '나' : h(m.name)} · ${h(RB[m.role_id].name)}</span>`).join('')}</div>
    ${plan ? `<p class="gtime">궁 안에서 약 <b>${plan.quick}분</b>(사진만 찍고 이동) · 일기까지 쓰면 약 ${plan.full}분 <span class="muted">· 쓸 수 있는 시간 약 ${LIM}분</span></p>${advice}
    <ol class="groute">${plan.order.map(st => `<li><span class="pl">${h(st.name)}</span><span class="tk">${st.tasks.map(t => `${who(t)} ${circ(t.n)}`).join(' · ')}</span></li>`).join('')}
      <li class="gt">흥례문 게이트로 나와 <b>${h(P.museum_time)}까지 박물관 앞</b></li></ol>
    <p class="gmus">박물관(반별 입장 뒤): ${Object.entries(rooms).map(([k, v]) => `${h(k)}(${v.join('·')})`).join(' → ')}</p>
    <div class="mapbox">${window.groupMap(plan)}</div>
    <p class="muted" style="font-size:13px">빨간 핀에 내 미션이 있고, 흐린 핀은 친구 미션이오. 시간은 걸음과 머무는 시간을 어림한 것이오.</p>`
    : '<p class="lead">친구가 이 코드를 넣으면 함께 다닐 동선이 나오오.</p>'}
    <div class="grow"><button class="btn line sm" data-act="grefresh">새로 고침</button><button class="btn line sm" data-act="gleave">모임 나가기</button></div>
  </div></details>`;
}
async function groupAct(fn) {
  if (busy) return; busy = true;
  try { const r = await fn(); await loadGroup(); render(); if (r) toast(r); const el = document.getElementById('group'); if (el) el.scrollIntoView({ block: 'start' }); }
  catch (e) { toast(errText(e)); } finally { busy = false; }
}
const GJOIN = { no_group: '그런 코드가 없소. 다시 확인하시오.', other_class: '다른 반 모임이오. 같은 반 친구끼리만 모일 수 있소.', full: '그 모임은 3명이 다 찼소.' };

/* ---------- 내 위치(누를 때만 켬, 화면을 떠나면 끔) ---------- */
function geoMsg() {
  if (!GEO || !GEO.fix) return '위치를 찾는 중…';
  const p = window.mapLocate(GEO.fix.lat, GEO.fix.lon, GEO.fix.acc);
  return p ? `파란 점이 지금 그대요(오차 약 ${Math.round(GEO.fix.acc)}m).` : '지금은 경복궁 밖에 있소.';
}
function drawMe() {
  const p = GEO && GEO.fix ? window.mapLocate(GEO.fix.lat, GEO.fix.lon, GEO.fix.acc) : null;
  document.querySelectorAll('.pmap .me').forEach(g => {
    if (!p) { g.style.display = 'none'; return; }
    g.style.display = '';
    g.querySelector('.dot').setAttribute('cx', p.x); g.querySelector('.dot').setAttribute('cy', p.y);
    const a = g.querySelector('.acc'); a.setAttribute('cx', p.x); a.setAttribute('cy', p.y); a.setAttribute('r', p.r);
  });
  const m = document.getElementById('geomsg'); if (m) m.textContent = geoMsg();
}
function stopGeo() { if (GEO) { navigator.geolocation.clearWatch(GEO.id); GEO = null; } }
function toggleGeo() {
  if (GEO) { stopGeo(); render(); return; }
  if (!navigator.geolocation) { toast('이 휴대폰에서는 위치를 쓸 수 없소.'); return; }
  GEO = { id: null, fix: null };
  GEO.id = navigator.geolocation.watchPosition(
    pos => { if (!GEO) return; GEO.fix = { lat: pos.coords.latitude, lon: pos.coords.longitude, acc: pos.coords.accuracy }; drawMe(); },
    err => { stopGeo(); render(); toast(err.code === 1 ? '위치 사용을 허락해야 볼 수 있소. 휴대폰 설정에서 허락하시오.' : '위치를 찾지 못했소. 잠시 뒤 다시 해 보시오.'); },
    { enableHighAccuracy: true, maximumAge: 5000, timeout: 20000 });
  render();
}

/* ---------- 사진: 줄여서 고르자마자 올린다 ---------- */
async function shrink(file) {
  const max = 1600;
  let src;
  try { src = await createImageBitmap(file, { imageOrientation: 'from-image' }); }
  catch (e) {
    src = await new Promise((ok, no) => { const im = new Image(); im.onload = () => ok(im); im.onerror = no; im.src = URL.createObjectURL(file); });
  }
  const w = src.width || src.naturalWidth, hh = src.height || src.naturalHeight, k = Math.min(1, max / Math.max(w, hh));
  const c = document.createElement('canvas'); c.width = Math.round(w * k); c.height = Math.round(hh * k);
  c.getContext('2d').drawImage(src, 0, 0, c.width, c.height);
  let q = 0.82, blob;
  do { blob = await new Promise(ok => c.toBlob(ok, 'image/jpeg', q)); q -= 0.12; } while (blob && blob.size > 900000 && q > 0.4);
  if (!blob) throw new Error('image');
  return blob;
}
function repaintMission(n) {
  const li = document.getElementById('m' + n), r = RB[stu().role_id];
  if (li && r) li.outerHTML = missionCard(r, r.missions[n - 1], n - 1);
}
async function pickPhoto(n, input) {
  const f = input.files && input.files[0]; if (!f) return;
  let blob;
  try { blob = await shrink(f); } catch (e) { toast('이 사진은 열 수 없소. 다른 사진으로 해 보시오.'); return; }
  if (DRAFT[n] && DRAFT[n].preview && DRAFT[n].preview !== (ENT[n] || {}).url) URL.revokeObjectURL(DRAFT[n].preview);
  DRAFT[n] = { blob, preview: URL.createObjectURL(blob) };
  await uploadPhoto(n);
}
async function uploadPhoto(n) {
  const d = DRAFT[n]; if (!d || !d.blob || d.uploading) return;
  d.uploading = true; d.failed = false; repaintMission(n);
  try {
    const path = `${stu().id}/m${n}-${Date.now()}.jpg`;
    const up = await sb.storage.from(BUCKET).upload(path, d.blob, { contentType: 'image/jpeg', upsert: false });
    if (up.error) throw up.error;
    const old = await rpc('gp_save_photo', { p_mission: n, p_path: path });
    if (old) sb.storage.from(BUCKET).remove([old]).catch(() => {});
    ENT[n] = { ...(ENT[n] || {}), photo_path: path, url: d.preview };
    DRAFT[n] = { preview: d.preview };
    toast(done(n) ? `미션 ${n} 완료! ${n < 3 ? '다음 장소로 가시오.' : '모든 미션을 마쳤소. ' + endAt() + ' 엔딩을 기다리시오.'}` : `사진을 저장했소. 일기를 ${minD()}자 넘게 쓰면 완료 도장이 찍히오.`);
  } catch (e) { d.failed = true; toast(errText(e)); }
  finally { d.uploading = false; repaintMission(n); paintDone('m' + n); }
}

/* ---------- 오늘의 소감(학생 자신의 말) ---------- */
const closeText = () => { if (tester() || !P) return '언제든'; return `${day(P.ending_close_at || P.mission_close_at)} ${hm(P.ending_close_at || P.mission_close_at)}`; };
const reflDone = () => !!(FINAL && FINAL.reflection && FINAL.reflection.trim().length >= minR());
function reflectBox(dark) {
  const v = curVal('refl'), n = v.trim().length;
  return `<section class="reflect${dark ? ' dark' : ''}" id="reflect">
    <h3>📝 오늘의 소감</h3>
    <p class="rguide">이제 역할에서 나와 <b>나 자신의 말</b>로 적어 보시오. 말투는 편하게 써도 되오.</p>
    <ul class="rq"><li>이 역할을 고른 까닭, 그리고 해 보니 어땠는지</li><li>와서 보니 생각과 달랐던 것</li><li>엔딩을 보고 든 생각, 앞으로 궁궐이 다르게 보일 것 같은 점</li></ul>
    <textarea data-save="refl" rows="6" maxlength="3000" placeholder="오늘 나는…">${h(v)}</textarea>
    <div class="mrow"><span class="cnt${n >= minR() ? ' ok' : ''}" data-cnt="refl">${n}/${minR()}자</span><span class="as" data-as="refl">${h(asText('refl'))}</span></div>
    <p class="${dark ? 'esaved' : 'muted'}" style="margin-top:6px;font-size:14px">쓰는 대로 저절로 저장되오. ${h(closeText())}까지 고칠 수 있소.</p>
  </section>`;
}

/* ---------- 엔딩 ---------- */
async function openEnding() {
  if (busy) return; busy = true;
  try {
    const data = await rpc('gp_get_ending', {});
    const ent = ENT[data.photo_mission];
    END = { data, step: 0, url: ent && (DRAFT[data.photo_mission] || {}).preview || ent && ent.url };
    if (data.body.old) new Image().src = data.body.old.src;   // 훼손 단락의 옛 사진 미리 받기
    V.view = 'ending'; render(true);
  } catch (e) { toast(errText(e)); } finally { busy = false; }
}
function ending() {
  const r = RB[stu().role_id], b = END.data.body, m = r.missions[END.data.photo_mission - 1] || r.missions[0];
  const then = b.then || [];
  const total = then.length + 2;          // 그 뒤 단락들 + 그리고 지금 + 한마디
  const st = END.step, isNow = st >= then.length, isLast = st >= then.length + 1;
  const shown = then.slice(0, Math.min(st + 1, then.length));
  const old = b.old && st >= b.old.at && !isNow;   // 훼손 단락: 내 사진 대신 그때의 사진
  const noteV = curVal('note'), fin = !!(FINAL && FINAL.note);
  document.body.classList.add('night');
  $app.innerHTML = `
  <div class="ending">
    <p class="eyebrow light">${h(r.name)} ${h(r.person)} · 그 뒤 이 궁궐에 일어난 일</p>
    ${old ? `<figure class="efig old${st === b.old.at ? ' fade' : ''}"><img src="${h(b.old.src)}" alt="${h(b.old.cap)}">
      <figcaption>${h(b.old.cap)}<small>${h(b.old.credit)}</small></figcaption></figure>`
    : `<figure class="efig${isNow ? ' nowc' : ''}">${END.url ? `<img src="${h(END.url)}" alt="내가 찍은 ${h(m.place)}">` : `<div class="noimg">${h(m.place)}<br><small>사진이 없소. 오늘 그 자리를 떠올려 보시오.</small></div>`}
      <figcaption>${isNow && b.old ? '그리고 지금, ' : ''}오늘 그대가 찍은 ${h(m.place)}</figcaption></figure>`}
    <div class="etext">${shown.map(p => `<p>${h(p)}</p>`).join('')}
      ${isNow ? `<p class="enow"><b>그리고 지금</b> ${h(b.now)}</p>` : ''}</div>
    ${isLast ? `<div class="efinal"><label for="note">✍️ ${h(b.prompt || `${r.person}에게 한마디를 남기시오.`)}</label>
      <textarea id="note" data-save="note" rows="4" maxlength="1000" placeholder="${h(r.person)}에게 하고 싶은 말">${h(noteV)}</textarea>
      <div class="mrow"><span class="as" data-as="note">${h(asText('note'))}</span></div>
      ${fin ? '' : '<button class="btn block" data-act="noteDone">다 썼소 · 오늘의 소감 쓰기</button>'}
      ${fin ? '<p class="esaved">남겼소. 이어서 오늘의 소감을 적고, 종례 때 담임 선생님 앞에서 종례 확인을 누르시오.</p>' : ''}</div>
      ${fin ? reflectBox(true) : ''}` : `<button class="btn block" data-act="next">${st + 1 >= then.length && !isNow ? '그리고 지금' : '다음'} (${st + 1}/${total})</button>`}
    <button class="linkbtn light" data-act="home">내 역할 화면으로</button>
  </div>`;
}
async function noteDone() {
  const v = curVal('note').trim();
  if (v.length < 5) { toast('조금 더 적어 주시오.'); return; }
  edit('note', v); await flush('note');
  if (SV.note && SV.note.state === 'error') { toast(SV.note.err || '저장하지 못했소.'); return; }
  render(); const r = document.getElementById('reflect'); if (r) r.scrollIntoView({ behavior: reduced() ? 'auto' : 'smooth', block: 'start' });
  toast('남겼소. 이제 오늘의 소감을 적어 보시오.');
}

/* ---------- 교사 ---------- */
async function openStaff(quiet) {
  V.mode = 'staff'; V.view = 'staff';
  if (!quiet) $app.innerHTML = '<p class="lead">불러오는 중…</p>';
  try {
    const [rows, cnt, grp] = await Promise.all([rpc('gp_class_status', { p_class: V.cls }), V.cls ? rpc('gp_role_counts', { p_class: V.cls }) : [], V.cls ? rpc('gp_class_groups', { p_class: V.cls }).catch(() => []) : []]);
    const counts = {}; (cnt || []).forEach(r => counts[r.role_id] = r.n);
    const groups = {}; (grp || []).forEach(r => groups[r.sid] = r.code);
    STAFF = { cls: V.cls, rows: rows || [], counts, groups, at: Date.now() };
  } catch (e) {
    if (/not_staff/.test(e && e.message || '')) { ME = null; STAFF = null; staffExpired(); return; }
    STAFF = { cls: V.cls, rows: [], counts: {}, err: errText(e) };
  }
  render(!quiet);
}
function staffTabs() {
  return isAdmin() ? `<div class="seg" role="group" aria-label="화면"><button data-act="sview" data-v="staff" aria-pressed="${V.view !== 'admin'}">현황</button><button data-act="sview" data-v="admin" aria-pressed="${V.view === 'admin'}">관리</button></div>` : '';
}
function staffView() {
  const admin = isAdmin(), S = STAFF, ph = phase();
  const chosen = S.rows.filter(r => r.role_id).length;
  const dup = {}; S.rows.forEach(r => dup[r.num] = (dup[r.num] || 0) + 1);
  const field = ph === 'open' || ph === 'ending';
  const noIn = S.rows.filter(r => !r.checkin_at), noOut = S.rows.filter(r => r.checkin_at && !r.checkout_at);
  const tabs = admin ? [...Array.from({ length: P.class_count }, (_, i) => i + 1), 0] : [...staffClasses(), 0];
  $app.innerHTML = `
  ${staffTabs()}
  <p class="eyebrow" style="margin-top:14px">${h(staffLabel())}</p>
  <h1>${S.cls ? `${S.cls}반` : '체험'} 현황</h1><div class="rule"></div>
  ${tabs.length > 1 ? `<div class="tabs" role="group" aria-label="반 고르기">${tabs.map(c => `<button data-act="cls" data-v="${c}" aria-pressed="${c === S.cls}">${c ? c + '반' : '체험'}</button>`).join('')}</div>` : ''}
  ${!admin && !staffClasses().length ? '<div class="banner info">맡은 반이 아직 없소. 관리자 선생님께 반을 정해 달라고 하시오.</div>' : ''}
  ${S.err ? `<div class="banner no">${h(S.err)}</div>` : ''}
  <p class="muted" style="font-size:13.5px;margin-top:6px">🔒 공용 PC·전자칠판에서는 다 쓰면 오른쪽 위 <b>로그아웃</b>을 누르시오. 로그인은 12시간 뒤 저절로 끊기오.</p>
  <div class="stats four">
    <div class="stat"><b>${S.rows.length}</b><span>등록</span></div>
    <div class="stat"><b>${chosen}</b><span>역할</span></div>
    <div class="stat"><b>${S.rows.length - noIn.length}</b><span>출석</span></div>
    <div class="stat"><b>${S.rows.filter(r => r.checkout_at).length}</b><span>종례</span></div>
  </div>
  ${field && S.rows.length && S.cls ? `<div class="alert"><b>출석 안 한 학생 ${noIn.length}명</b> ${noIn.map(r => `<span class="chip">${r.num} ${h(r.name)}</span>`).join('') || '<span class="muted">없음</span>'}
    ${ph === 'ending' ? `<br><b>종례 확인 안 한 학생 ${noOut.length}명</b> ${noOut.map(r => `<span class="chip">${r.num} ${h(r.name)}</span>`).join('') || '<span class="muted">없음</span>'}` : ''}
    <p class="muted" style="margin-top:6px;font-size:13px">30초마다 저절로 새로 고치오 · 마지막 ${hm(S.at)}</p></div>` : ''}
  ${S.cls ? `<details class="fold"><summary>역할별 인원</summary><div class="rolegrid">${openRoles().map(r => { const n = S.counts[r.id] || 0; return `<div class="${n >= cap() ? 'f' : ''}"><span>${seal(r, 'xs')}${h(r.name)}</span><b>${n}/${cap()}</b></div>`; }).join('')}</div></details>` : ''}
  <h2 style="margin-top:20px">학생 목록</h2>
  <p class="lead">이름을 누르면 사진과 일기를 볼 수 있소. 번호가 겹치면 빨간색, 🔒는 비밀번호를 여러 번 틀려 잠긴 학생이오(이름을 눌러 풀 수 있소).</p>
  <div class="tblwrap"><table class="tbl"><thead><tr><th class="nw">번호</th><th>이름</th><th>역할</th><th class="nw">진행</th></tr></thead><tbody>
  ${S.rows.length ? S.rows.map(r => `<tr><td class="nw" style="${dup[r.num] > 1 ? 'color:var(--bad);font-weight:700' : ''}">${r.num}</td>
    <td><button class="namebtn" data-act="student" data-v="${r.sid}">${h(r.name)}</button>${r.locked ? ' 🔒' : ''}${S.groups && S.groups[r.sid] ? `<span class="sm">👫 모임 ${h(S.groups[r.sid])} · ${S.rows.filter(x => S.groups[x.sid] === S.groups[r.sid] && x.sid !== r.sid).map(x => h(x.name)).join(', ') || '혼자'}</span>` : ''}</td>
    <td>${r.role_id && RB[r.role_id] ? `<span class="nw">${seal(RB[r.role_id], 'xs')}${h(RB[r.role_id].name)}</span><span class="sm">${kst(r.role_at)}</span>` : '<span class="muted">아직</span>'}</td>
    <td class="nw prog"><span class="${r.checkin_at ? 'y' : ''}" title="출석">📍${r.checkin_at ? hm(r.checkin_at) : '–'}</span><span class="${r.missions === 3 ? 'y' : ''}">📷${r.missions}/3</span><span class="${r.final_done ? 'y' : ''}">✍️${r.final_done ? '✓' : '–'}</span><span class="${r.reflect_len >= minR() ? 'y' : ''}">📝${r.reflect_len ? r.reflect_len + '자' : '–'}</span><span class="${r.checkout_at ? 'y' : ''}">🏁${r.checkout_at ? hm(r.checkout_at) : '–'}</span></td></tr>`).join('') : '<tr><td colspan="4" class="muted">아직 들어온 학생이 없소.</td></tr>'}
  </tbody></table></div>
  <div style="margin-top:16px;display:flex;gap:10px;flex-wrap:wrap">
    <button class="btn line sm" data-act="refresh">새로 고침</button>
    ${S.cls ? '<button class="btn line sm" data-act="csv">응답 CSV 내려받기</button>' : ''}
    ${admin ? '<button class="btn line sm" data-act="csvAll">전체 반 CSV</button>' : ''}
    <button class="btn line sm" data-act="preview">역할 미리보기</button>
    <button class="btn sm" data-act="try">학생으로 체험하기</button>
    <button class="btn line sm" data-act="sguide">📖 사용법</button>
  </div>
  <p class="note">응답 CSV는 학생 한 줄에 역할·미션 질문과 일기 3개·엔딩 한마디·소감을 담소(엑셀·구글 시트에서 열기). 질문은 학생이 답할 때의 문구 그대로요. ‘학생으로 체험하기’는 시간·정원 제한 없이 학생 화면을 해 보는 기능이고, 실제 반에는 들어가지 않소.</p>
  <section class="panel"><h3>엔딩 미리보기</h3><p>학생에게는 ${h(day(P.ending_open_at))} ${endAt()} 전에는 보이지 않소.</p>
    <div class="tabs">${R.map(r => `<button data-act="endingPrev" data-v="${h(r.id)}">${seal(r, 'xs')}${h(r.name)}</button>`).join('')}</div><div id="endingbox"></div></section>
  <details class="fold"><summary>🔑 내 비밀번호 바꾸기</summary><form class="form" data-form="mypw" style="margin:0 16px 16px">
    <div class="field"><label for="p-old">지금 비밀번호</label><input id="p-old" type="password" autocomplete="current-password"></div>
    <div class="field"><label for="p-new">새 비밀번호(8자 이상)</label><input id="p-new" type="password" autocomplete="new-password" required></div>
    <button class="btn sm" type="submit">바꾸기</button></form></details>`;
}
async function openStudent(sid) {
  V.view = 'student'; $app.innerHTML = '<p class="lead">불러오는 중…</p>';
  try {
    const d = await rpc('gp_student_detail', { p_sid: sid });
    const paths = d.entries.map(e => e.photo_path).filter(Boolean), urls = {};
    if (paths.length) { const { data } = await sb.storage.from(BUCKET).createSignedUrls(paths, 3600); (data || []).forEach(x => urls[x.path] = x.signedUrl); }
    DETAIL = { ...d, urls, row: (STAFF && STAFF.rows.find(r => r.sid === sid)) || {} };
  } catch (e) { DETAIL = { err: errText(e) }; }
  render(true);
}
function studentView() {
  const D = DETAIL;
  if (D.err) { $app.innerHTML = `<button class="linkbtn" data-act="staffback">← 현황</button><div class="banner no">${h(D.err)}</div>`; return; }
  const s = D.student, r = s.role_id && RB[s.role_id], byM = {}; D.entries.forEach(e => byM[e.mission] = e);
  $app.innerHTML = `
  <button class="linkbtn" data-act="staffback">← ${s.class_no ? s.class_no + '반' : '체험'} 현황</button>
  <p class="eyebrow" style="margin-top:8px">${s.class_no ? `${s.class_no}반 ${s.num}번` : '체험'}</p><h1>${h(s.name)}</h1>
  <p class="lead">${r ? `${seal(r, 'xs')}${h(r.name)} ${h(r.person)}` : '역할 아직'} · 출석 ${hm(s.checkin_at) || '–'} · 종례 ${hm(s.checkout_at) || '–'}</p>
  <ol class="missions">${[1, 2, 3].map(i => { const e = byM[i] || {}, m = r && r.missions[i - 1]; return `<li class="mission"><div class="mh"><span class="no">${i}</span><span class="pl">${h(e.place || (m && m.place) || '')}</span></div>
    <p class="task">✍️ ${h(e.question || (m && m.diary) || '')}</p>
    ${e.photo_path && D.urls[e.photo_path] ? `<img class="ph" src="${h(D.urls[e.photo_path])}" alt="미션 ${i} 사진">` : '<p class="muted">사진 없음</p>'}
    <p class="mydiary">${e.diary ? h(e.diary) : '<span class="muted">일기 없음</span>'}</p>${e.updated_at ? `<p class="muted" style="font-size:13px">${kst(e.updated_at)}</p>` : ''}</li>`; }).join('')}</ol>
  <section class="panel"><h3>엔딩 한마디</h3>${D.final && D.final.note_prompt ? `<p class="muted">${h(D.final.note_prompt)}</p>` : ''}<p>${D.final && D.final.note ? h(D.final.note) : '아직 없음'}</p></section>
  <section class="panel"><h3>📝 오늘의 소감 ${D.final && D.final.reflection ? `<span class="muted" style="font-weight:400;font-size:13px">${D.final.reflection.length}자 · ${kst(D.final.reflection_at)}</span>` : ''}</h3><p class="mydiary">${D.final && D.final.reflection ? h(D.final.reflection) : '아직 없음'}</p></section>
  ${s.tester ? '' : `<section class="panel"><h3>학생 계정</h3>
    ${P.auth_mode === 'code' ? `<p>비밀번호를 잊었거나 잠긴 학생은 <b>비밀번호 지우기</b>를 누르시오. 학생이 입장 코드·반·번호·이름과 <b>새 숫자 4자리</b>로 다시 들어오면 그것이 새 비밀번호가 되오.</p>
    <div style="display:flex;gap:10px;flex-wrap:wrap;margin-top:10px"><button class="btn line sm" data-act="resetPin" data-v="${s.id}">비밀번호 지우기${D.row.locked ? '(잠김 풀기)' : ''}</button>` : '<div style="display:flex;gap:10px;flex-wrap:wrap;margin-top:10px">'}
    <button class="btn line sm" data-act="delStudent" data-v="${s.id}">이 학생 지우기</button></div>
    <p class="muted" style="font-size:13px;margin-top:8px">반·번호를 잘못 골라 다른 친구 자리에 들어간 경우에만 지우시오. 사진·일기·소감이 모두 지워지오.</p></section>`}`;
}
async function showEndingPrev(id) {
  const box = document.getElementById('endingbox');
  box.innerHTML = '<p class="lead">불러오는 중…</p>';
  try {
    const e = await rpc('gp_get_ending', { p_role: id }), r = RB[id], b = e.body, m = r.missions[e.photo_mission - 1];
    box.innerHTML = `<div class="letter"><p>${h(r.name)} ${h(r.person)} · 다시 띄울 사진: 미션 ${e.photo_mission} (${h(m ? m.place : '')})</p>
      ${(b.then || []).map((p, i) => `${b.old && i === b.old.at ? `<img class="prevold" src="${h(b.old.src)}" alt="${h(b.old.cap)}"><p class="muted">옛 사진: ${h(b.old.cap)} · ${h(b.old.credit)}</p>` : ''}<p>${h(p)}</p>`).join('')}<p><b>그리고 지금</b> — ${h(b.now)}</p><p class="sign">✍️ ${h(b.prompt)}</p></div>`;
  } catch (err) { box.innerHTML = `<div class="banner no">${h(errText(err))}</div>`; }
}
async function tryAsStudent() {
  if (busy) return; busy = true;
  try { await rpc('gp_try_student'); await reloadMe(); V.mode = 'student'; V.view = 'roles'; await loadStudent(); goStudentHome(); }
  catch (e) { toast(errText(e)); } finally { busy = false; }
}
// 생기부용: 학생 한 줄에 역할·미션(질문은 답할 때의 문구)·엔딩 한마디·소감 전문.
async function csvDownload(all) {
  if (busy) return; busy = true;
  try {
    const cls = all ? null : STAFF.cls, rows = await rpc('gp_class_export', { p_class: cls }) || [];
    const q = v => { const s = String(v ?? ''); return `"${(/^[=+\-@\t\r]/.test(s) ? "'" + s : s).replace(/"/g, '""')}"`; };
    const head = ['반', '번호', '이름', '역할', '인물', '출석', '종례'];
    [1, 2, 3].forEach(i => head.push(`미션${i} 장소`, `미션${i} 질문`, `미션${i} 사진`, `미션${i} 일기`));
    head.push('엔딩 한마디', '오늘의 소감', '소감 글자수', '함께 다닌 모임');
    const body = rows.map(r => {
      const role = r.role_id && RB[r.role_id], line = [r.class_no, r.num, r.name, role ? role.name : '', role ? role.person : '', kst(r.checkin_at), kst(r.checkout_at)];
      [1, 2, 3].forEach(i => line.push(r[`m${i}_place`] || '', r[`m${i}_question`] || '', r[`m${i}_photo`] ? 'O' : '', r[`m${i}_diary`] || ''));
      line.push(r.note || '', r.reflection || '', r.reflection ? r.reflection.length : 0, r.group_code || '');
      return line.map(q).join(',');
    });
    const blob = new Blob(['﻿' + [head.map(q).join(',')].concat(body).join('\r\n')], { type: 'text/csv;charset=utf-8' });
    const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = `궁궐사람들_${all ? '전체' : cls + '반'}_응답.csv`; a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 2000);
  } catch (e) { toast(errText(e)); } finally { busy = false; }
}

/* ---------- 사용법 카드 ---------- */
function studentCards() {
  const code = P.auth_mode === 'code';
  return [
    { seal: '人', title: '궁궐 사람들', text: `그대는 ${day(P.mission_open_at)}, 1890년 무렵 고종 시대 경복궁의 한 사람이 되오. 역할 하나를 골라 그 사람의 눈으로 궁과 박물관을 둘러보오. 경쟁은 없소.` },
    { seal: '入', title: '들어오기', text: code ? '선생님이 알려 준 입장 코드와 반·번호·이름을 넣고, 나만 아는 숫자 4자리 비밀번호를 정하시오. 다른 휴대폰에서도 같은 값을 넣으면 이어서 쓸 수 있소.' : `학교 구글 계정${P.google_domain ? `(@${P.google_domain})` : ''}으로 로그인하고 반·번호·이름을 적으시오.` },
    { seal: '擇', title: '역할 고르기', text: `역할마다 편지와 미션 3개가 있소. 읽어 보고 정하시오. 반마다 역할별 ${cap()}명까지, 먼저 정한 사람이 자리를 갖소. ${kst(P.role_change_until)}까지 바꿀 수 있소.` },
    { seal: '寫', title: '미션', text: `장소 단서를 보고 찾아가서 → 사진 한 장(장소·사물만) → 그 사람의 마음으로 일기 ${minD()}자 이상. 사진은 고르자마자 올라가고, 일기는 쓰는 대로 저절로 저장되오. 글 아래 ‘자동 저장됨’을 확인하시오.` },
    { seal: '終', title: '엔딩과 소감', text: `${endAt()}에 엔딩이 열리오. 그대가 찍은 사진이 다시 나타나고, 그 뒤 이 궁궐에 일어난 일을 알게 되오. 인물에게 한마디를 남기고, 나 자신의 말로 오늘의 소감을 적으시오.` },
    { seal: '守', title: '지킬 것', text: (P.rules || []).filter(x => /사진|문화유산|길을/.test(x)).slice(0, 3).join(' ') || '사진은 장소와 사물만 찍고, 문화유산을 만지지 마시오.' }
  ];
}
function staffCards() {
  const c = [
    { seal: '班', title: '반 현황', text: '맡은 반 학생의 등록·역할·출석·미션·소감을 한눈에 보오. 현장 시간에는 30초마다 저절로 새로 고치고, 출석·종례 확인을 안 한 학생 이름이 위에 나오오.' },
    { seal: '錄', title: '학생 기록', text: '학생 이름을 누르면 사진·일기·한마디·소감 전문을 보오. 응답 CSV에는 학생이 답할 때의 질문 문구가 함께 들어가 생기부 근거로 쓰기 좋소.' },
    { seal: '鍵', title: '비밀번호를 잊은 학생', text: '학생 이름 → 비밀번호 지우기. 학생이 새 숫자 4자리로 다시 들어오면 되오. 번호를 잘못 골라 남의 자리에 들어간 학생은 지우고 다시 들어오게 하시오.' },
    { seal: '試', title: '학생으로 체험하기', text: '시간·정원 제한 없이 학생 화면 전체(역할·미션·엔딩)를 해 볼 수 있소. 실제 반에는 들어가지 않소.' },
    { seal: '鎖', title: '로그아웃', text: '로그인은 12시간 뒤 저절로 끊기오. 교무실 공용 PC나 교실 전자칠판에서 썼다면 다 쓴 뒤 오른쪽 위 로그아웃을 꼭 누르시오. 학생 기록이 다음 사람에게 보일 수 있소.' }
  ];
  if (isAdmin()) c.push({ seal: '管', title: '관리', text: '위쪽 [관리]에서 행사 날짜·시각, 반 수, 정원, 입장 코드, 안내 문구, 역할·미션·엔딩, 담임 계정, 기록 지우기를 다루오. 처음이면 [행사 설정]부터 하시오.' });
  return c;
}
function showGuide(cards, key) { if (window.gpGuide) window.gpGuide(cards, () => { try { localStorage.setItem(key, '1'); } catch (e) {} }); }
function studentGuideOnce() { try { if (!localStorage.getItem('gp:guide:v1')) showGuide(studentCards(), 'gp:guide:v1'); } catch (e) {} }
function staffGuideOnce() { const k = `gp:sguide:${staff().id}`; try { if (!localStorage.getItem(k)) showGuide(staffCards(), k); } catch (e) {} }
function whenOpeningDone(cb) { const t = setInterval(() => { if (!document.querySelector('.opening')) { clearInterval(t); cb(); } }, 300); }

/* ---------- 렌더 ---------- */
function topinfo() {
  if (!ME || (!stu() && !staff())) { $info.innerHTML = ''; return; }
  const s = stu(), st = staff();
  const who = V.mode === 'staff' && st ? staffLabel() : s ? (s.tester ? '체험 모드' : `${s.class_no}반 ${s.num}번`) : '';
  $info.innerHTML = `<span>${h(who)}</span><button class="linkbtn" data-act="signout">로그아웃</button>`;
}
const VIEWS = { login, setup, register, roles, detail, home, ending, pwchange, staff: staffView, student: studentView };
function render(push) {
  if (V.view !== 'ending') document.body.classList.remove('night');
  if (V.view !== 'home') stopGeo();
  topinfo();
  if (V.view === 'boot') { $app.innerHTML = '<p class="lead">불러오는 중…</p>'; return; }
  (VIEWS[V.view] || login)();
  if (push) window.scrollTo(0, 0);
  if (GEO) drawMe();
  schedule();
}
// 학생: 1분마다 화면의 남은 시간·엔딩 열림만 다시 그림(서버 요청 없음, 글 쓰는 중이면 건너뜀). 교사: 현장 시간에만 30초마다 현황 요청.
function schedule() {
  clearInterval(tick); clearInterval(poll); tick = poll = null;
  if (V.view === 'home') {
    const before = phase();
    tick = setInterval(() => { if (document.hidden || busy || document.activeElement && document.activeElement.tagName === 'TEXTAREA') return; if (phase() !== before || before !== 'ending') render(); }, 60000);
  }
  if (V.view === 'staff' && P && now() > +new Date(P.mission_open_at) && now() < +new Date(P.mission_close_at)) {
    poll = setInterval(() => { if (!document.hidden) openStaff(true); }, 30000);
  }
}

/* ---------- 이벤트 ---------- */
const A = {
  ltab(v) { V.tab = v; LOGIN_MSG = ''; render(); },
  google() { signInGoogle(); },
  signout() { signOut(); },
  guide() { showGuide(studentCards(), 'gp:guide:v1'); },
  sguide() { showGuide(staffCards(), `gp:sguide:${staff().id}`); },
  async roles() { V.view = 'roles'; if (stu() && V.mode !== 'staff') { try { await loadCounts(); } catch (e) {} } render(true); },
  detail(v) { V.role = v; V.view = 'detail'; render(true); },
  choose(v) { choose(v); },
  home() { if (V.mode === 'staff') { openStaff(); return; } if (!stu()) { V.view = 'login'; render(true); return; } V.view = stu().role_id ? 'home' : 'roles'; render(true); },
  editInfo() { V.view = 'register'; LOGIN_MSG = ''; render(true); },
  only(v) { V.onlyOpen = v === '1'; render(); },
  replay() { showIntro(); },
  async checkin() { if (busy) return; busy = true; try { await rpc('gp_checkin', { p_kind: 'in' }); await reloadMe(); render(); toast('출석을 확인했소. 첫 미션 장소로 가시오.'); } catch (e) { toast(errText(e)); } finally { busy = false; } },
  checkout() { modal('종례 확인', '담임 선생님께 종례를 받았소?', '받았소', async () => { try { await rpc('gp_checkin', { p_kind: 'out' }); await reloadMe(); render(); toast('수고했소. 오늘 하루 고마웠소.'); } catch (e) { toast(errText(e)); } }, '아직'); },
  retryPhoto(v) { uploadPhoto(+v); },
  ending() { flushAll(); openEnding(); },
  next() { END.step++; render(); window.scrollTo({ top: document.body.scrollHeight, behavior: reduced() ? 'auto' : 'smooth' }); },
  noteDone() { noteDone(); },
  cls(v) { V.cls = +v; openStaff(); },
  sview(v) { if (v === 'admin') { V.view = 'admin'; render(true); } else openStaff(); },
  refresh() { openStaff(); },
  csv() { csvDownload(false); },
  csvAll() { csvDownload(true); },
  preview() { V.view = 'roles'; V.mode = 'staff'; render(true); },
  endingPrev(v) { showEndingPrev(v); },
  student(v) { openStudent(v); },
  staffback() { V.mode = 'staff'; openStaff(); },
  try() { tryAsStudent(); },
  locate() { toggleGeo(); },
  resetPin(v) { modal('비밀번호 지우기', '이 학생의 비밀번호를 지우고 잠김을 푸오. 학생이 다음에 들어올 때 새 숫자 4자리를 정하오.', '지우기', async () => { try { await rpc('gp_reset_pin', { p_sid: v }); toast('지웠소. 학생에게 새 숫자로 다시 들어오라고 하시오.'); openStudent(v); } catch (e) { toast(errText(e)); } }); },
  delStudent(v) {
    modal('이 학생 지우기', '이 학생의 등록·역할·사진·일기·소감이 모두 지워지오. 되돌릴 수 없소.', '지우기', async () => {
      try {
        const paths = (DETAIL && DETAIL.entries || []).map(e => e.photo_path).filter(Boolean);
        if (paths.length) await sb.storage.from(BUCKET).remove(paths);
        const left = await rpc('gp_delete_student', { p_sid: v });
        if (left && left.length) await sb.storage.from(BUCKET).remove(left).catch(() => {});
        toast('지웠소.'); openStaff();
      } catch (e) { toast(errText(e)); }
    });
  },
  gcreate() { groupAct(async () => { const c = await rpc('gp_group_create', {}); return `모임을 만들었소. 코드 ${c}를 친구에게 알려 주시오.`; }); },
  grefresh() { groupAct(async () => ''); },
  gleave() { modal('모임 나가기', '이 모임에서 나오겠소? 동선 추천이 내 미션만으로 돌아가오.', '나가기', () => groupAct(async () => { await rpc('gp_group_leave', {}); return '모임에서 나왔소.'; })); }
};
document.addEventListener('click', e => {
  const el = e.target.closest('[data-act]');
  if (el && !el.disabled && A[el.dataset.act]) A[el.dataset.act](el.dataset.v, el);
});
const FORMS = {
  enter: submitEnter, slogin: submitStaffLogin, setup: submitSetup, reg: submitReg, pwfirst: submitPwFirst,
  gjoin() {
    const v = (document.getElementById('g-code').value || '').trim();
    if (!/^[0-9]{4}$/.test(v)) { toast('코드 4자리 숫자를 넣으시오.'); return; }
    groupAct(async () => { const r = await rpc('gp_group_join', { p_code: v }); return r === 'ok' ? '모임에 들어갔소. 아래 동선을 보시오.' : GJOIN[r] || '들어가지 못했소.'; });
  },
  async mypw() {
    const o = document.getElementById('p-old').value, n = document.getElementById('p-new').value;
    try { const r = await rpc('gp_staff_password', { p_old: o, p_new: n }); toast(r === 'ok' ? '바꿨소.' : r === 'mismatch' ? '지금 비밀번호가 맞지 않소.' : PW_MSG[r] || r); if (r === 'ok') render(); }
    catch (e) { toast(errText(e)); }
  }
};
document.addEventListener('submit', e => {
  const f = FORMS[e.target.dataset.form];
  if (f) { e.preventDefault(); f(e); }
});
document.addEventListener('change', e => {
  const n = e.target.dataset && e.target.dataset.photo;
  if (n) pickPhoto(+n, e.target);
});
document.addEventListener('input', e => {
  const k = e.target.dataset && e.target.dataset.save;
  if (!k) return;
  const v = e.target.value;
  edit(k, v);
  const c = document.querySelector(`[data-cnt="${k}"]`), min = k === 'refl' ? minR() : minD();
  if (c) { c.textContent = `${v.trim().length}/${min}자`; c.classList.toggle('ok', v.trim().length >= min); }
});
document.addEventListener('focusout', e => { const k = e.target.dataset && e.target.dataset.save; if (k && SV[k] && SV[k].state === 'dirty') flush(k); });

/* ---------- 관리자 화면(admin.js)이 쓰는 것 ---------- */
window.GP = {
  sb, rpc, h, toast, modal, errText, opts, render, setContent, loadBase, kst, hm, day, fmtParts,
  get P() { return P; }, get R() { return R; }, get V() { return V; }, get busy() { return busy; }, set busy(v) { busy = v; },
  isAdmin, staffTabs, VIEWS, A, FORMS, BUCKET, seal
};

/* ---------- 시작 ---------- */
if (sb) sb.auth.onAuthStateChange((ev, session) => {
  TOKEN = session ? session.access_token : null;
  if (ev === 'SIGNED_OUT' && ME) { resetState(); V.view = 'login'; render(true); }
});
(async () => {
  if (!READY) { $app.innerHTML = '<h1>설정이 필요하오</h1><div class="rule"></div><p class="lead">config.js에 Supabase 주소와 공개 키가 없소. 설치 안내서의 Vercel 환경변수(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY)를 확인하시오.</p>'; return; }
  render();
  const opening = window.gpOpening && !location.search.includes('code=') && window.gpOpening();
  try { await loadBase(); }
  catch (e) { $app.innerHTML = `<h1>연결하지 못했소</h1><div class="rule"></div><p class="lead">${h(errText(e))}</p><p class="muted" style="margin-top:10px">설치 SQL을 실행했는지, Vercel 환경변수의 주소·키가 맞는지 확인하시오.</p>`; return; }
  const { data, error } = await sb.auth.getSession();
  if (location.search.includes('code=') || location.hash.includes('access_token')) history.replaceState(null, '', location.pathname);
  TOKEN = data && data.session ? data.session.access_token : null;
  if (P.setup_needed || P.setup_expired) { V.view = 'setup'; render(); return; }
  if (error || !data.session) { V.view = 'login'; render(); }
  else await enter();
  if (!staff()) whenOpeningDone(studentGuideOnce);
  void opening;
})();
