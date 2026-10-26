/* 둘러보기판: 서버(Supabase) 없이 이 기기 안에서만 도는 가짜 백엔드.
   config.js에 window.CFG = { demo: true } 일 때만 쓴다. app.js·admin.js가 부르는 sb.rpc / sb.auth / sb.storage를 흉내 낸다.
   기록은 이 기기의 localStorage에만 남고 어디로도 보내지 않는다. 기본 역할·미션·엔딩은 demo/content.json(설치 SQL과 같은 원본). */
(function () {
  if (!(window.CFG && window.CFG.demo)) return;
  const KEY = 'gp-demo-v1', H = 3600e3, D = 24 * H;
  let S = null, ready = null;
  const listeners = [];
  const uid = () => (crypto.randomUUID ? crypto.randomUUID() : 'x' + Math.random().toString(36).slice(2) + Date.now().toString(36));
  const iso = t => new Date(t).toISOString();
  const err = message => ({ data: null, error: { message } });
  const ok = data => ({ data, error: null });
  const save = () => { try { localStorage.setItem(KEY, JSON.stringify(S)); } catch (e) { /* 저장 공간이 모자라면 이번 화면에서만 유지 */ } };

  // 예시 사진: 장소 이름이 적힌 그림(실제 사진 아님)
  const fakePhoto = (place, hue) => 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(
    `<svg xmlns="http://www.w3.org/2000/svg" width="800" height="600"><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="hsl(${hue},35%,62%)"/><stop offset="1" stop-color="hsl(${hue + 30},30%,38%)"/></linearGradient></defs><rect width="800" height="600" fill="url(#g)"/><text x="400" y="285" font-size="44" text-anchor="middle" fill="#fff" font-family="sans-serif">예시 사진</text><text x="400" y="345" font-size="30" text-anchor="middle" fill="#fff" font-family="sans-serif">${String(place).replace(/[<&>]/g, '')}</text></svg>`);

  // 시각 세 가지: 행사 전 / 현장(미션 중) / 엔딩 열림
  function times(phase) {
    const n = Date.now();
    if (phase === 'before') return { role_change_until: iso(n + D), mission_open_at: iso(n + 2 * D), ending_open_at: iso(n + 2 * D + 2.5 * H), mission_close_at: iso(n + 2 * D + 9 * H), ending_close_at: iso(n + 2 * D + 9 * H) };
    if (phase === 'ending') return { role_change_until: iso(n + 3 * H), mission_open_at: iso(n - 3 * H), ending_open_at: iso(n - 5 * 60e3), mission_close_at: iso(n + 5 * H), ending_close_at: iso(n + 5 * H) };
    return { role_change_until: iso(n + 3 * H), mission_open_at: iso(n - H), ending_open_at: iso(n + 2 * H), mission_close_at: iso(n + 8 * H), ending_close_at: iso(n + 8 * H) };
  }

  // 예시 반(1반 8명, 2반 2명). 이름은 모두 "예시학생", 글은 둘러보기용으로 지어낸 예시.
  const SAMPLE = [
    { num: 1, role: 'sukso', checkin: true, done: 3, note: '박만복 숙수님, 소주방이 다시 지어져 오늘 내가 그 앞에 섰소. 부엌을 나눈 까닭을 이제 알겠소.', refl: '요리를 좋아해서 숙수를 골랐다. 와서 보니 소주방이 생각보다 넓고 칸이 많았다. 엔딩에서 박람회 때 헐렸다가 2015년에 다시 지어졌다는 것을 알고, 앞으로 궁궐의 부엌도 눈여겨볼 것 같다.',
      diaries: ['부엌을 내소주방과 외소주방으로 나눈 것은 임금님 수라와 잔치 음식이 섞이지 않게 하려는 까닭이라 보오. 일도 빨라졌을 것이오.', '강녕전 문턱이 높아 수라상을 들고 넘을 때 가장 조심했을 것이오. 국물이 넘치면 큰일이었을 테니까.', '넓고 얕은 그릇에는 전이나 떡처럼 펼쳐 담는 음식을, 깊은 그릇에는 국을 올렸을 것이라 짐작하오.'] },
    { num: 2, role: 'sumunjang', checkin: true, done: 2,
      diaries: ['문이 세 칸이라 드나드는 사람을 나눠 살피기 좋지만, 한꺼번에 몰리면 지키기 어려울 것 같소.', '영추문은 문이 하나뿐이고 돌을 높이 쌓아 그 위에 문루를 올렸소. 관리들이 날마다 드나드는 문이라 실용적으로 지은 것 같소.'] },
    { num: 3, role: 'hwawon', checkin: true, done: 1, diaries: ['굴뚝에 새긴 것은 소나무와 학이오. 연기가 나가는 곳에도 오래 살기를 바라는 뜻을 담은 것이라 보오.'] },
    { num: 4, role: 'jeongi', checkin: true, done: 3, note: '정순길 조수님, 지금은 스위치 하나로 온 집에 불을 켜오. 그날 물불이 시작이었소.',
      diaries: ['연못물을 끌어 기계를 돌리려면 물을 퍼 올리는 펌프와 불을 때는 보일러가 있어야 했을 것이오.', '건청궁 처마 밑에 전등을 달면 밤에 드나드는 문턱이 잘 보여 넘어지지 않을 것이오.', '자동차가 들어오면 먼 길이 빨라지지만, 사람과 수레가 섞이지 않게 길을 넓히고 다니는 규칙을 새로 정해야 했을 것이오.'] },
    { num: 5, role: 'sajin', checkin: false, done: 0 },
    { num: 6, role: 'uinyeo', checkin: true, done: 0 },
    { num: 7, role: 'akgong', checkin: true, done: 3, note: '함덕보 악공님, 오늘 근정전 마당은 조용했지만 그날의 편종 소리를 떠올려 보았소.', refl: '음악을 좋아해서 악공을 골랐다. 근정전 마당에 서서 귀를 기울이니 바람 소리만 들렸는데, 조회 날 편종이 울렸을 모습을 상상하니 다르게 보였다.',
      diaries: ['지금은 사람들 말소리와 바람 소리가 들렸소. 조회 날에는 편종과 편경이 느리고 엄숙하게 울렸을 것이오.', '물 위의 누각이니 소리가 물결을 따라 퍼지게 대금처럼 맑은 소리가 어울릴 것이오.', '호랑이 모양 악기(어)는 등의 톱니를 긁어 드르륵 소리를 냈을 것 같소. 음악을 끝낼 때 썼다 하오.'] },
    { num: 8, role: null, checkin: false, done: 0 },
    { cls: 2, num: 1, role: 'moksu', checkin: true, done: 1, diaries: ['잡상은 지붕을 지키는 수호신 같소. 목수라면 나쁜 기운을 막으려고 이런 모습으로 만들었을 것이오.'] },
    { cls: 2, num: 2, role: 'tongyeok', checkin: true, done: 0 }
  ];

  function seed(content) {
    const roles = content.map(r => ({ ...r, enabled: true }));
    const RB = Object.fromEntries(roles.map(r => [r.id, r]));
    S = { v: 1, who: null, anon: false, phase: 'open', roles, staff: [
        { id: 'st-admin', login_id: 'demo-admin', name: '체험 관리자', kind: 'admin', classes: [], email: null, must_change: false },
        { id: 'st-t1', login_id: 'demo-t1', name: '체험 담임', kind: 'homeroom', classes: [1], email: null, must_change: false }],
      settings: { school_name: '둘러보기고등학교', event_label: '1학년 경복궁 현장체험학습', meet_text: '9:20까지 경복궁 매표소 앞(3호선 경복궁역 5번 출구)', museum_time: '10:45',
        rules: ['정해진 시각까지 집결 장소에 모이시오. 도착하면 앱에서 출석 확인을 누르시오.', '궁 미션을 마치고 정해진 시각까지 국립고궁박물관 앞에 모이오. 흥례문 게이트로 나간 뒤에는 궁에 다시 들어오지 않소.', '박물관 미션과 엔딩을 마치면 담임 선생님께 종례를 받고 해산하오.', '사진은 장소와 사물만 찍으시오. 다른 사람 얼굴이 크게 나오면 안 되오.', '문화유산을 만지거나 올라가지 말고, 출입 금지 구역에 들어가지 마시오.', '휴대폰을 충전해 오시오. 사진과 글은 미션 마감 시각까지 나중에 올릴 수 있소.', '길을 잃거나 몸이 안 좋으면 바로 담임 선생님께 전화하시오.'],
        privacy: '둘러보기판이오. 여기서 쓴 글과 고른 사진은 이 기기 안에만 남고 어디로도 보내지 않소. 실제 학생 이름이나 개인정보는 넣지 마시오.\n실제 학교에서 쓸 때는 학교마다 따로 설치하고, 기록은 그 학교 DB에만 저장되오.',
        class_count: 7, max_num: 40, role_cap: 3, min_diary: 40, min_reflect: 80, join_code: 'DEMO26', auth_mode: 'code', google_domain: null },
      students: [], entries: {}, final: {}, photos: {}, groups: {} };
    const t0 = Date.now() - 50 * 60e3;
    SAMPLE.forEach((x, i) => {
      const id = 'sample-' + (i + 1), r = x.role && RB[x.role];
      S.students.push({ id, class_no: x.cls || 1, num: x.num, name: `예시학생 ${String(x.num).padStart(2, '0')}`, role_id: x.role, role_at: x.role ? iso(t0 - 3 * D) : null,
        checkin_at: x.checkin ? iso(t0 + i * 60e3) : null, checkout_at: null, staff_id: null, locked_until: null });
      if (!r) return;
      S.entries[id] = {};
      (x.diaries || []).forEach((d, k) => {
        const m = r.missions[k], path = `${id}/m${k + 1}-${t0}.jpg`;
        S.photos[path] = fakePhoto(m.place, (i * 47 + k * 23) % 360);
        S.entries[id][k + 1] = { role_id: r.id, place: m.place, question: m.diary, photo_path: k < x.done ? path : null, diary: d, updated_at: iso(t0 + (k + 1) * 15 * 60e3) };
      });
      if (x.note || x.refl) S.final[id] = { note: x.note || null, note_prompt: r.ending && r.ending.body.prompt, note_at: x.note ? iso(Date.now() - 20 * 60e3) : null, reflection: x.refl || null, reflection_at: x.refl ? iso(Date.now() - 10 * 60e3) : null };
    });
  }
  async function load() {
    try { S = JSON.parse(localStorage.getItem(KEY) || 'null'); } catch (e) { S = null; }
    if (!S || S.v !== 1) { const c = await (await fetch('demo/content.json')).json(); seed(c); save(); }
  }

  /* ---------- 질의 도우미 ---------- */
  const st = () => S.settings;
  const T = () => times(S.phase);
  const cfg = () => ({ ...st(), ...T() });
  const me = () => S.who && S.who.kind === 'staff' ? S.staff.find(x => x.id === S.who.id) : null;
  const sidOf = () => S.who ? (S.who.kind === 'student' ? S.who.id : (S.students.find(s => s.staff_id === S.who.id) || {}).id) : null;
  const stu = id => S.students.find(s => s.id === id);
  const role = id => S.roles.find(r => r.id === id);
  const now = () => Date.now();
  const tester = s => !!(s && s.staff_id);
  const canWrite = s => s && (tester(s) || (now() >= +new Date(T().mission_open_at) && now() <= +new Date(T().mission_close_at)));
  const canFinal = s => s && (tester(s) || (now() >= +new Date(T().ending_open_at) && now() <= +new Date(T().ending_close_at)));
  const canView = s => { const m = me(); if (!m || !s) return false; if (m.kind === 'admin') return true; if (s.staff_id) return s.staff_id === m.id; return m.classes.includes(s.class_no); };
  const canViewClass = c => { const m = me(); return !!m && (m.kind === 'admin' || m.classes.includes(c)); };
  const done = s => Object.values(S.entries[s.id] || {}).filter(e => e.photo_path && (e.diary || '').length >= st().min_diary).length;
  const pub = r => ({ id: r.id, sort: r.sort, enabled: r.enabled, name: r.name, person: r.person, seal: r.seal, intro: r.intro, career: r.career, letter: r.letter, img: r.img,
    missions: r.missions.map((m, i) => ({ n: i + 1, place_key: m.place_key, place: m.place, area: m.area, clue: m.clue, photo: m.photo, diary: m.diary })) });
  const sorted = () => [...S.roles].sort((a, b) => a.sort - b.sort || (a.id < b.id ? -1 : 1));
  const upsertEntry = (s, n) => {
    const r = role(s.role_id); if (!r) throw 'no_role';
    const m = r.missions[n - 1];
    S.entries[s.id] = S.entries[s.id] || {};
    const e = S.entries[s.id][n] = S.entries[s.id][n] || {};
    Object.assign(e, { role_id: r.id, place: m.place, question: m.diary });
    return e;
  };

  /* ---------- 가짜 RPC ---------- */
  const R = {
    gp_public() {
      return { ...cfg(), join_code: undefined, setup_needed: false, setup_expired: false, now: iso(now()) };
    },
    gp_content() { return sorted().filter(r => r.enabled || me() || (stu(sidOf()) || {}).role_id === r.id).map(pub); },
    gp_me() {
      const m = me(), s = stu(sidOf());
      return { staff: m ? { id: m.id, name: m.name, kind: m.kind, classes: m.classes, login_id: m.login_id, must_change: false } : null,
        student: s ? { id: s.id, class_no: s.class_no, num: s.num, name: s.name, role_id: s.role_id, checkin_at: s.checkin_at, checkout_at: s.checkout_at, tester: tester(s) } : null,
        google: null, now: iso(now()) };
    },
    gp_logout() { S.who = null; return null; },
    gp_role_counts({ p_class } = {}) {
      const c = p_class != null && canViewClass(p_class) ? p_class : (stu(sidOf()) || {}).class_no;
      if (!c) return [];
      const n = {}; S.students.filter(s => s.class_no === c && s.role_id).forEach(s => n[s.role_id] = (n[s.role_id] || 0) + 1);
      return Object.entries(n).map(([role_id, k]) => ({ role_id, n: k }));
    },
    gp_choose_role({ p_role }) {
      const s = stu(sidOf()); if (!s) throw 'not_registered';
      const r = role(p_role); if (!r || !r.enabled) throw 'bad_role';
      if (s.role_id === p_role) return 'ok';
      if (!tester(s)) {
        if (now() > +new Date(T().role_change_until)) throw 'role_closed';
        if (S.students.filter(x => x.class_no === s.class_no && x.role_id === p_role && x.id !== s.id).length >= st().role_cap) return 'full';
      } else S.entries[s.id] = {};
      s.role_id = p_role; s.role_at = iso(now());
      return 'ok';
    },
    gp_my_records() {
      const id = sidOf(), E = S.entries[id] || {}, f = S.final[id];
      return { entries: Object.keys(E).map(k => ({ mission: +k, photo_path: E[k].photo_path, diary: E[k].diary, updated_at: E[k].updated_at })),
        final: f ? { note: f.note, note_at: f.note_at, reflection: f.reflection, reflection_at: f.reflection_at } : null };
    },
    gp_save_diary({ p_mission, p_diary }) {
      const s = stu(sidOf()); if (!s) throw 'not_registered'; if (!canWrite(s)) throw 'not_open';
      const e = upsertEntry(s, p_mission); e.diary = String(p_diary || '').trim().slice(0, 2000); e.updated_at = iso(now()); return e.updated_at;
    },
    gp_save_photo({ p_mission, p_path }) {
      const s = stu(sidOf()); if (!s) throw 'not_registered'; if (!canWrite(s)) throw 'not_open';
      if (!String(p_path).startsWith(s.id + '/m' + p_mission + '-')) throw 'bad_path';
      const e = upsertEntry(s, p_mission), old = e.photo_path; e.photo_path = p_path; e.updated_at = iso(now());
      return old && old !== p_path ? old : null;
    },
    gp_save_note({ p_text }) {
      const s = stu(sidOf()); if (!s) throw 'not_registered'; if (!canFinal(s)) throw 'ending_locked';
      const r = role(s.role_id), f = S.final[s.id] = S.final[s.id] || {};
      Object.assign(f, { note: String(p_text || '').trim().slice(0, 1000), note_prompt: r && r.ending && r.ending.body.prompt, note_at: iso(now()) }); return f.note_at;
    },
    gp_save_reflection({ p_text }) {
      const s = stu(sidOf()); if (!s) throw 'not_registered'; if (!canFinal(s)) throw 'ending_locked';
      const f = S.final[s.id] = S.final[s.id] || {}; Object.assign(f, { reflection: String(p_text || '').trim().slice(0, 3000), reflection_at: iso(now()) }); return f.reflection_at;
    },
    gp_checkin({ p_kind }) {
      const s = stu(sidOf()); if (!s) throw 'not_registered'; if (!canWrite(s) && !canFinal(s)) throw 'not_open';
      if (p_kind === 'in') s.checkin_at = s.checkin_at || iso(now()); else s.checkout_at = s.checkout_at || iso(now()); return null;
    },
    gp_get_ending({ p_role } = {}) {
      let r;
      if (p_role && me()) r = role(p_role);
      else { const s = stu(sidOf()); if (!s || !s.role_id) throw 'no_role'; if (!tester(s) && now() < +new Date(T().ending_open_at)) throw 'ending_locked'; r = role(s.role_id); }
      const e = (r && r.ending) || { photo_mission: 1, body: { then: [], now: '', prompt: '' } };
      return { role_id: r.id, photo_mission: e.photo_mission, body: e.body };
    },
    gp_group_open() { return false; },
    gp_group_mine() { return null; },
    gp_group_create() { throw 'group_closed'; },
    gp_group_join() { throw 'group_closed'; },
    gp_group_leave() { return null; },
    gp_class_status({ p_class }) {
      const m = me(); if (!m) throw 'not_staff';
      const list = p_class === 0 ? S.students.filter(s => s.staff_id && (m.kind === 'admin' || s.staff_id === m.id))
        : (canViewClass(p_class) ? S.students.filter(s => s.class_no === p_class && !s.staff_id) : (() => { throw 'not_staff'; })());
      return list.sort((a, b) => a.num - b.num).map(s => ({ sid: s.id, num: s.num, name: s.name, role_id: s.role_id, role_at: s.role_at, checkin_at: s.checkin_at, checkout_at: s.checkout_at,
        missions: done(s), final_done: !!(S.final[s.id] && S.final[s.id].note), reflect_len: ((S.final[s.id] || {}).reflection || '').length, locked: false, has_pin: true, google: false }));
    },
    gp_student_detail({ p_sid }) {
      const s = stu(p_sid); if (!canView(s)) throw 'not_staff';
      const E = S.entries[s.id] || {}, f = S.final[s.id];
      return { student: { id: s.id, class_no: s.class_no, num: s.num, name: s.name, role_id: s.role_id, checkin_at: s.checkin_at, checkout_at: s.checkout_at, tester: tester(s) },
        entries: Object.keys(E).sort().map(k => ({ mission: +k, ...E[k] })), final: f || null };
    },
    gp_class_export({ p_class }) {
      const m = me(); if (!m) throw 'not_staff';
      if (p_class == null && m.kind !== 'admin') throw 'not_admin';
      if (p_class != null && !canViewClass(p_class)) throw 'not_staff';
      return S.students.filter(s => !s.staff_id && (p_class == null || s.class_no === p_class)).sort((a, b) => a.class_no - b.class_no || a.num - b.num).map(s => {
        const E = S.entries[s.id] || {}, f = S.final[s.id] || {}, o = { class_no: s.class_no, num: s.num, name: s.name, role_id: s.role_id, checkin_at: s.checkin_at, checkout_at: s.checkout_at, note: f.note, reflection: f.reflection, group_code: null };
        [1, 2, 3].forEach(i => { const e = E[i] || {}; o[`m${i}_place`] = e.place; o[`m${i}_question`] = e.question; o[`m${i}_photo`] = !!e.photo_path; o[`m${i}_diary`] = e.diary; });
        return o;
      });
    },
    gp_class_groups({ p_class }) { if (!canViewClass(p_class)) throw 'not_staff'; return []; },
    gp_reset_pin({ p_sid }) { if (!canView(stu(p_sid))) throw 'not_staff'; return null; },
    gp_delete_student({ p_sid }) {
      const s = stu(p_sid); if (!canView(s)) throw 'not_staff';
      S.students = S.students.filter(x => x.id !== p_sid); delete S.entries[p_sid]; delete S.final[p_sid]; return [];
    },
    gp_try_student() {
      const m = me(); if (!m) throw 'not_staff';
      if (!S.students.some(s => s.staff_id === m.id)) S.students.push({ id: 'tester-' + m.id, class_no: 0, num: S.students.filter(s => s.class_no === 0).length + 1, name: m.name + '(체험)', role_id: null, role_at: null, checkin_at: null, checkout_at: null, staff_id: m.id });
      return null;
    },
    gp_staff_password({ p_new }) { if (!me()) throw 'not_staff'; return String(p_new || '').length < 8 ? 'short_pw' : 'ok'; },
    gp_student_update({ p_class, p_num, p_name }) {
      const s = stu(sidOf()); if (!s) throw 'not_registered'; if (tester(s)) return 'ok';
      if (S.students.some(x => x.class_no === p_class && x.num === p_num && x.id !== s.id)) return 'taken';
      if (s.class_no !== p_class) { s.role_id = null; s.role_at = null; }
      Object.assign(s, { class_no: p_class, num: p_num, name: String(p_name || '').trim().slice(0, 20) }); return 'ok';
    },
    gp_admin_get() {
      const m = me(); if (!m || m.kind !== 'admin') throw 'not_admin';
      return { settings: { ...cfg() }, staff: S.staff.map(x => ({ ...x, has_pw: true, locked: false })),
        counts: { students: S.students.filter(s => !s.staff_id).length, entries: Object.values(S.entries).reduce((a, e) => a + Object.keys(e).length, 0), photos: Object.keys(S.photos).length } };
    },
    gp_admin_save_settings({ p }) {
      const m = me(); if (!m || m.kind !== 'admin') throw 'not_admin';
      const keep = ['school_name', 'event_label', 'meet_text', 'museum_time', 'rules', 'privacy', 'class_count', 'max_num', 'role_cap', 'min_diary', 'min_reflect', 'join_code', 'auth_mode', 'google_domain'];
      keep.forEach(k => { if (p[k] !== undefined && p[k] !== null && p[k] !== '') st()[k] = p[k]; });
      return 'ok';   // 둘러보기판의 날짜·시각은 위쪽 막대의 [행사 전·현장·엔딩 열림]으로 바꾼다
    },
    gp_admin_content() {
      const m = me(); if (!m || m.kind !== 'admin') throw 'not_admin';
      return sorted().map(r => ({ ...pub(r), chosen: S.students.filter(s => s.role_id === r.id && !s.staff_id).length, ending: r.ending || null }));
    },
    gp_admin_save_role({ p }) {
      const m = me(); if (!m || m.kind !== 'admin') throw 'not_admin';
      if (!/^[a-z0-9_-]{2,30}$/.test(p.id || '')) return 'bad_id';
      if (!(p.name || '').trim()) return 'bad_name'; if (!(p.person || '').trim()) return 'bad_person';
      if (!Array.isArray(p.missions) || p.missions.length !== 3) return 'bad_missions';
      let museum = false;
      for (const x of p.missions) { if (!x.place || !x.diary) return 'empty_mission'; if (x.place_key === 'museum') museum = true; else if (museum) return 'museum_order'; }
      const old = role(p.id), r = { ...(old || {}), id: p.id, sort: +p.sort || 0, enabled: p.enabled !== false, name: p.name.trim(), person: p.person.trim(), seal: (p.seal || '人').slice(0, 2), intro: p.intro || '', career: p.career || '', letter: p.letter || [], img: old ? old.img : false,
        missions: p.missions.map(x => ({ place_key: x.place_key, place: x.place, area: x.place_key === 'museum' ? '박물관' : '궁', clue: x.clue || '', photo: x.photo || '', diary: x.diary })) };
      if (p.ending) r.ending = p.ending;
      S.roles = S.roles.filter(x => x.id !== p.id).concat(r);
      return 'ok';
    },
    gp_admin_delete_role({ p_id }) {
      const m = me(); if (!m || m.kind !== 'admin') throw 'not_admin';
      if (S.students.some(s => s.role_id === p_id && !s.staff_id)) return 'in_use';
      S.roles = S.roles.filter(r => r.id !== p_id); return 'ok';
    },
    gp_admin_save_staff({ p }) {
      const m = me(); if (!m || m.kind !== 'admin') throw 'not_admin';
      const id = (p.login_id || '').toLowerCase().trim(); if (!/^[a-z0-9_.-]{3,30}$/.test(id)) return 'bad_id';
      if (!(p.name || '').trim()) return 'bad_name';
      if (p.password && p.password.length < 8) return 'short_pw';
      if (S.staff.some(x => x.login_id === id && x.id !== p.id)) return 'dup_id';
      if (p.id === m.id && p.kind !== 'admin') return 'last_admin';
      const x = S.staff.find(y => y.id === p.id) || (() => { if (!p.password) return null; const y = { id: uid() }; S.staff.push(y); return y; })();
      if (!x) return 'short_pw';
      Object.assign(x, { login_id: id, name: p.name.trim(), kind: p.kind, classes: p.classes || [], email: p.email || null, must_change: !!p.password && x.id !== m.id });
      return 'ok';
    },
    gp_admin_delete_staff({ p_id }) { const m = me(); if (!m || m.kind !== 'admin') throw 'not_admin'; if (p_id === m.id) return 'self'; S.staff = S.staff.filter(x => x.id !== p_id); return 'ok'; },
    gp_admin_photo_paths() { return Object.keys(S.photos); },
    gp_admin_wipe({ p_confirm }) {
      if (p_confirm !== '기록 지우기') return 'confirm';
      S.students = []; S.entries = {}; S.final = {}; S.photos = {}; S.who = S.who && S.who.kind === 'staff' ? S.who : null; return 'ok';
    }
  };

  // 사진은 800px로 줄여 이 기기에만 담는다(저장 공간 아끼기)
  async function smallDataURL(blob) {
    const bmp = await createImageBitmap(blob), k = Math.min(1, 800 / Math.max(bmp.width, bmp.height));
    const c = document.createElement('canvas'); c.width = Math.round(bmp.width * k); c.height = Math.round(bmp.height * k);
    c.getContext('2d').drawImage(bmp, 0, 0, c.width, c.height);
    return c.toDataURL('image/jpeg', 0.72);
  }

  const session = () => (S && (S.who || S.anon) ? { access_token: 'demo', user: { id: 'demo' } } : null);
  const client = {
    async rpc(fn, args) {
      await ready;
      if (!R[fn]) return err('unknown');
      try { const d = R[fn](args || {}); save(); return ok(d === undefined ? null : d); }
      catch (e) { return err(typeof e === 'string' ? e : (e && e.message) || 'error'); }
    },
    auth: {
      async getSession() { await ready; return { data: { session: session() }, error: null }; },
      async signInAnonymously() { await ready; S.anon = true; save(); return { data: { session: session() }, error: null }; },
      async signOut() { await ready; S.who = null; S.anon = false; save(); listeners.forEach(f => f('SIGNED_OUT', null)); return { error: null }; },
      onAuthStateChange(f) { listeners.push(f); return { data: { subscription: { unsubscribe() {} } } }; },
      async signInWithOAuth() { return { error: { message: '둘러보기판에서는 구글 로그인을 쓰지 않소.' } }; }
    },
    storage: {
      from() {
        return {
          async upload(path, blob) { await ready; try { S.photos[path] = await smallDataURL(blob); save(); return { error: null }; } catch (e) { return { error: { message: 'image' } }; } },
          async remove(paths) { await ready; (paths || []).forEach(p => delete S.photos[p]); save(); return { error: null }; },
          async createSignedUrls(paths) { await ready; return { data: (paths || []).filter(p => S.photos[p]).map(p => ({ path: p, signedUrl: S.photos[p] })), error: null }; }
        };
      }
    },
    // 둘러보기 시작: 학생 / 담임 / 관리자
    async demoAs(kind) {
      await ready;
      if (kind === 'student') {
        let s = S.students.find(x => x.id === 'me');
        if (!s) { s = { id: 'me', class_no: 1, num: 30, name: '체험 학생', role_id: null, role_at: null, checkin_at: null, checkout_at: null, staff_id: null }; S.students.push(s); }
        S.who = { kind: 'student', id: 'me' };
      } else S.who = { kind: 'staff', id: kind === 'admin' ? 'st-admin' : 'st-t1' };
      S.anon = true; save();
    },
    get phase() { return S && S.phase; },
    async setPhase(p) { await ready; S.phase = p; save(); },
    reset() { try { localStorage.removeItem(KEY); } catch (e) {} }
  };
  ready = load();
  window.gpDemo = client;

  // 위쪽 막대: 둘러보기판 안내 · 시각 바꾸기 · 처음부터
  function bar() {
    const b = document.createElement('div');
    b.className = 'demobar';
    const P = [['before', '행사 전'], ['open', '현장'], ['ending', '엔딩 열림']];
    const draw = () => {
      b.innerHTML = `<div class="wrap dbin"><span class="dbt"><b>둘러보기판</b> · 기록은 이 기기에만 남소</span>
        <span class="dbp" role="group" aria-label="시각 바꾸기">${P.map(([k, t]) => `<button data-demo-phase="${k}" aria-pressed="${S && S.phase === k}">${t}</button>`).join('')}</span>
        <button class="dbr" data-demo-reset>처음부터</button></div>`;
    };
    ready.then(draw);
    b.addEventListener('click', async e => {
      const p = e.target.closest('[data-demo-phase]'), r = e.target.closest('[data-demo-reset]');
      if (p) { await client.setPhase(p.dataset.demoPhase); location.reload(); }
      if (r) { client.reset(); location.reload(); }
    });
    document.body.insertBefore(b, document.body.firstChild);
  }
  if (document.body) bar(); else document.addEventListener('DOMContentLoaded', bar);
})();
