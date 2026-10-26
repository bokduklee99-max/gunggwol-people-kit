/* 관리자 화면: 행사 설정 · 역할·미션·엔딩 · 교사 계정 · 기록 관리. app.js의 window.GP를 쓴다. */
(function () {
  const G = window.GP; if (!G) return;
  const { h, rpc, toast, modal, errText } = G;
  let ADM = null;      // {settings, staff, counts}
  let CON = null;      // 역할 전체(엔딩 포함)
  let EDIT = null;     // 고치는 중인 역할
  let SEDIT = null;    // 고치는 중인 교사 계정
  const SUB = [['settings', '행사 설정'], ['roles', '역할·미션'], ['staff', '교사 계정'], ['records', '기록 관리']];

  // 서울 시각 ↔ datetime-local 칸
  const toLocal = iso => {
    if (!iso) return '';
    const p = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Seoul', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).formatToParts(new Date(iso));
    const g = k => (p.find(x => x.type === k) || {}).value;
    return `${g('year')}-${g('month')}-${g('day')}T${g('hour')}:${g('minute')}`;
  };
  const fromLocal = v => v ? `${v}:00+09:00` : null;
  const paras = t => String(t || '').split(/\n\s*\n/).map(s => s.replace(/\s*\n\s*/g, ' ').trim()).filter(Boolean);
  const lines = t => String(t || '').split('\n').map(s => s.trim()).filter(Boolean);
  const val = id => { const el = document.getElementById(id); return el ? el.value : ''; };
  const SAVE_MSG = {
    bad_time: '시각 순서가 맞지 않소. 미션 시작 < 엔딩 열림 ≤ 미션 마감 ≤ 소감 마감, 역할 마감 ≤ 미션 마감이어야 하오.',
    bad_join: '입장 코드는 영문 대문자·숫자 4~12자로 정하시오.', bad_domain: '학교 도메인 형식이 맞지 않소(예: school.hs.kr).',
    bad_rules: '현장 수칙은 20줄까지 쓸 수 있소.', bad_mode: '로그인 방식을 다시 고르시오.',
    bad_id: '아이디 형식이 맞지 않소(영문 소문자·숫자·._- 3~30자).', bad_name: '이름을 적으시오.', bad_person: '인물 이름을 적으시오.',
    bad_letter: '편지는 8문단까지 쓸 수 있소.', bad_missions: '미션은 3개여야 하오.', bad_place: '미션 장소를 지도 목록에서 고르시오.',
    empty_mission: '미션마다 장소 이름과 일기 질문을 적으시오.', museum_order: '박물관 미션은 궁 미션 뒤에 두시오(흥례문 게이트를 나가면 궁에 다시 들어오지 않소).',
    bad_ending: '엔딩 내용을 다시 확인하시오.', short_pw: '비밀번호는 8자 이상으로 정하시오.', dup_id: '이미 쓰는 아이디요.', dup_email: '이미 등록된 이메일이오.',
    bad_email: '이메일 형식이 맞지 않소.', last_admin: '자기 자신을 담임으로 바꿀 수 없소(관리자가 없어지오).', bad_kind: '종류를 고르시오.',
    in_use: '이 역할을 고른 학생이 있어 지울 수 없소. 대신 [켜기]를 끄시오.', self: '자기 계정은 지울 수 없소.'
  };

  async function load(force) {
    if (ADM && !force) return;
    [ADM, CON] = await Promise.all([rpc('gp_admin_get'), rpc('gp_admin_content')]);
  }
  async function refreshPublic() { await G.loadBase(); G.setContent(await rpc('gp_content')); }

  function adminView() {
    const V = G.V;
    if (!ADM) {
      G.VIEWS.admin && (document.getElementById('app').innerHTML = `${G.staffTabs()}<p class="lead" style="margin-top:14px">불러오는 중…</p>`);
      load().then(() => G.render()).catch(e => { document.getElementById('app').innerHTML = `${G.staffTabs()}<div class="banner no">${h(errText(e))}</div>`; });
      return;
    }
    const sub = V.admin;
    const body = sub === 'roles' ? rolesView() : sub === 'role' ? roleEditor() : sub === 'staff' ? staffView() : sub === 'records' ? recordsView() : settingsView();
    document.getElementById('app').innerHTML = `${G.staffTabs()}
      <p class="eyebrow" style="margin-top:14px">관리자</p><h1>관리</h1><div class="rule"></div>
      <div class="tabs" role="group" aria-label="관리 메뉴">${SUB.map(([k, t]) => `<button data-act="asub" data-v="${k}" aria-pressed="${sub === k || (sub === 'role' && k === 'roles')}">${t}</button>`).join('')}</div>
      ${body}`;
  }

  /* ---------- 행사 설정 ---------- */
  function settingsView() {
    const s = ADM.settings, url = location.origin + location.pathname;
    const t = (id, label, v, hint) => `<div class="field"><label for="${id}">${label}</label><input id="${id}" type="datetime-local" value="${toLocal(v)}" required>${hint ? `<p class="hint">${hint}</p>` : ''}</div>`;
    const n = (id, label, v, min, max, hint) => `<div class="field"><label for="${id}">${label}</label><input id="${id}" type="number" inputmode="numeric" min="${min}" max="${max}" value="${v}" required>${hint ? `<p class="hint">${hint}</p>` : ''}</div>`;
    const x = (id, label, v, hint, ml = 200) => `<div class="field"><label for="${id}">${label}</label><input id="${id}" maxlength="${ml}" value="${h(v)}">${hint ? `<p class="hint">${hint}</p>` : ''}</div>`;
    return `
    <section class="panel"><h3>처음 할 일</h3><ol class="todo">
      <li>아래 <b>날짜·시각</b>과 반 수·정원을 행사에 맞게 고치고 저장하시오.</li>
      <li><b>역할·미션</b>에서 역할 14개를 읽어 보고, 쓰지 않을 역할은 끄거나 문구를 고치시오.</li>
      <li><b>교사 계정</b>에서 담임 선생님 계정을 만들고 아이디·비밀번호를 전하시오.</li>
      <li>위쪽 [현황] → <b>학생으로 체험하기</b>로 학생 화면을 끝까지 해 보시오.</li>
      <li>학생에게 <b>앱 주소</b>와 <b>입장 코드</b>를 알려 주시오: <code>${h(url)}</code> <button class="linkbtn" data-act="copyUrl">주소 복사</button></li>
    </ol></section>
    <form class="form" data-form="asettings">
      <h2>학교·행사</h2>
      ${x('a-school', '학교 이름', s.school_name, '', 60)}
      ${x('a-label', '행사 이름', s.event_label, '로그인 화면 맨 위에 보이오.', 80)}
      ${x('a-meet', '집결 안내', s.meet_text, '예: 9:20까지 경복궁 매표소 앞(3호선 경복궁역 5번 출구)')}
      ${x('a-museum', '박물관 앞 집합 시각', s.museum_time, '예: 10:45 · 궁 미션을 마치고 모이는 시각. 함께 다니기 시간 어림에도 쓰오.', 20)}
      <h2>날짜·시각 (서울 시각)</h2>
      ${window.CFG && CFG.demo ? '<div class="banner info">둘러보기판에서는 날짜·시각을 위쪽 막대의 [행사 전·현장·엔딩 열림]으로 바꾸시오. 아래 칸은 저장해도 바뀌지 않소.</div>' : ''}
      <div class="row2">${t('a-role', '역할 고르기 마감', s.role_change_until, '이때까지 역할을 바꿀 수 있소.')}${t('a-mopen', '미션 시작', s.mission_open_at, '출석·사진·일기를 이때부터 저장하오.')}</div>
      <div class="row2">${t('a-eopen', '엔딩 열림', s.ending_open_at, '모든 학생에게 한꺼번에 열리오.')}${t('a-mclose', '미션 마감', s.mission_close_at, '사진·일기 저장 끝. 늦게 올리는 학생을 생각해 넉넉히.')}</div>
      <div class="row2">${t('a-eclose', '엔딩 한마디·소감 마감', s.ending_close_at, '미션 마감과 같거나 늦게. 늦추면 소감만 더 받을 수 있소.')}<div></div></div>
      <h2>반·정원·글자 수</h2>
      <div class="row2">${n('a-classes', '반 수', s.class_count, 1, 20)}${n('a-maxnum', '번호 최대', s.max_num, 1, 99)}</div>
      <div class="row2">${n('a-cap', '반마다 역할별 정원', s.role_cap, 1, 40, '역할 수 × 정원이 한 반 학생 수보다 넉넉해야 하오.')}${n('a-mind', '일기 최소 글자', s.min_diary, 0, 500)}</div>
      <div class="row2">${n('a-minr', '소감 권장 글자', s.min_reflect, 0, 1000)}<div></div></div>
      <h2>로그인</h2>
      <fieldset class="radios"><legend class="sr">학생 로그인 방식</legend>
        <label><input type="radio" name="a-mode" value="code" ${s.auth_mode === 'code' ? 'checked' : ''}> 입장 코드 + 반·번호·이름 + 숫자 4자리 (추천, 따로 설정할 것 없음)</label>
        <label><input type="radio" name="a-mode" value="google" ${s.auth_mode === 'google' ? 'checked' : ''}> 학교 구글 계정 (Supabase에 Google 로그인을 먼저 설정해야 하오 · 설치 안내 부록)</label></fieldset>
      <div class="row2">${x('a-join', '입장 코드', s.join_code, '영문 대문자·숫자 4~12자. 학생에게만 알려 주시오.', 12)}
        <div class="field"><label>&nbsp;</label><button class="btn line block" type="button" data-act="newJoin">새 코드 만들기</button></div></div>
      ${x('a-domain', '학교 구글 도메인(구글 방식일 때)', s.google_domain || '', '예: school.hs.kr · 비워 두면 모든 구글 계정이 들어올 수 있소.', 60)}
      <h2>안내 문구</h2>
      <div class="field"><label for="a-rules">현장 수칙 (한 줄에 하나)</label><textarea id="a-rules" rows="8">${h((s.rules || []).join('\n'))}</textarea></div>
      <div class="field"><label for="a-privacy">개인정보 안내 (로그인 화면)</label><textarea id="a-privacy" rows="5">${h(s.privacy)}</textarea>
        <p class="hint">수집 항목·이용 목적·보는 사람·지우는 때를 적으시오. 학교 개인정보 처리 기준에 맞추시오.</p></div>
      <div class="actionbar"><button class="btn block" type="submit">설정 저장</button></div>
    </form>`;
  }
  async function saveSettings() {
    const mode = (document.querySelector('input[name="a-mode"]:checked') || {}).value || 'code';
    const p = {
      school_name: val('a-school'), event_label: val('a-label'), meet_text: val('a-meet'), museum_time: val('a-museum'),
      role_change_until: fromLocal(val('a-role')), mission_open_at: fromLocal(val('a-mopen')), ending_open_at: fromLocal(val('a-eopen')),
      mission_close_at: fromLocal(val('a-mclose')), ending_close_at: fromLocal(val('a-eclose')),
      class_count: +val('a-classes'), max_num: +val('a-maxnum'), role_cap: +val('a-cap'), min_diary: +val('a-mind'), min_reflect: +val('a-minr'),
      auth_mode: mode, join_code: val('a-join').trim().toUpperCase(), google_domain: val('a-domain').trim(),
      rules: lines(val('a-rules')), privacy: val('a-privacy').trim()
    };
    if (G.busy) return; G.busy = true;
    try {
      const r = await rpc('gp_admin_save_settings', { p });
      if (r !== 'ok') { toast(SAVE_MSG[r] || r); return; }
      await load(true); await refreshPublic(); G.render(); toast('설정을 저장했소.');
    } catch (e) { toast(errText(e)); } finally { G.busy = false; }
  }

  /* ---------- 역할·미션 ---------- */
  function rolesView() {
    const on = CON.filter(r => r.enabled).length;
    return `
    <p class="lead">켜 둔 역할 ${on}개 · 반마다 역할별 ${ADM.settings.role_cap}명이면 한 반에 ${on * ADM.settings.role_cap}자리요.</p>
    <div style="margin:12px 0;display:flex;gap:10px;flex-wrap:wrap"><button class="btn sm" data-act="newRole">새 역할 만들기</button></div>
    <div class="tblwrap"><table class="tbl"><thead><tr><th class="nw">순서</th><th>역할</th><th>미션 장소</th><th class="nw">고른 학생</th><th class="nw">켜기</th></tr></thead><tbody>
    ${CON.map(r => `<tr><td class="nw">${r.sort}</td>
      <td><button class="namebtn" data-act="editRole" data-v="${h(r.id)}">${G.seal(r, 'xs')}${h(r.name)} ${h(r.person)}</button><span class="sm">${h(r.career)}</span></td>
      <td class="sm2">${r.missions.map((m, i) => `${i + 1}. ${h(m.place)}`).join('<br>')}</td>
      <td class="nw">${r.chosen}</td>
      <td class="nw"><button class="tog" data-act="togRole" data-v="${h(r.id)}" aria-pressed="${r.enabled}">${r.enabled ? '켜짐' : '꺼짐'}</button></td></tr>`).join('')}
    </tbody></table></div>
    <p class="note">역할을 끄면 학생 목록에서 숨기오. 이미 고른 학생은 그대로 쓰오. 미션 문구를 행사 중에 고치면 학생 화면에 바로 반영되오(이미 쓴 답에는 답할 때의 질문이 따로 남소).</p>`;
  }
  const oldPhotos = () => { const m = {}; CON.forEach(r => { const o = r.ending && r.ending.body && r.ending.body.old; if (o && o.src) m[o.src] = o; }); return Object.values(m); };
  function blankRole() {
    const sort = Math.max(0, ...CON.map(r => r.sort)) + 1;
    return { id: 'r' + Date.now().toString(36), sort, enabled: false, name: '', person: '', seal: '人', intro: '', career: '', letter: [], img: false, chosen: 0, isNew: true,
      missions: [{ place_key: 'geunjeongjeon', place: '', clue: '', photo: '', diary: '' }, { place_key: 'gyeonghoeru', place: '', clue: '', photo: '', diary: '' }, { place_key: 'museum', place: '국립고궁박물관 · ', clue: '', photo: '', diary: '' }],
      ending: { photo_mission: 1, body: { then: [], now: '', prompt: '' } } };
  }
  function roleEditor() {
    const r = EDIT, e = (r.ending && r.ending.body) || { then: [], now: '', prompt: '' }, pm = (r.ending && r.ending.photo_mission) || 1;
    const places = (window.PLACES || []);
    const ph = oldPhotos(), old = e.old || null;
    const mf = (m, i) => `<fieldset class="mbox"><legend>미션 ${i + 1}</legend>
      <div class="row2"><div class="field"><label for="m${i}-key">지도 위치</label><select id="m${i}-key">${places.map(p => `<option value="${p.key}" ${m.place_key === p.key ? 'selected' : ''}>${h(p.name)}${p.key === 'museum' ? ' (박물관 미션)' : ''}</option>`).join('')}</select></div>
        <div class="field"><label for="m${i}-place">장소 이름(학생에게 보임)</label><input id="m${i}-place" maxlength="60" value="${h(m.place)}" required></div></div>
      <div class="field"><label for="m${i}-clue">장소 단서</label><textarea id="m${i}-clue" rows="3" maxlength="600">${h(m.clue)}</textarea></div>
      <div class="field"><label for="m${i}-photo">사진 안내</label><textarea id="m${i}-photo" rows="2" maxlength="300">${h(m.photo)}</textarea></div>
      <div class="field"><label for="m${i}-diary">일기 질문</label><textarea id="m${i}-diary" rows="2" maxlength="400" required>${h(m.diary)}</textarea>
        <p class="hint">본 것과 그렇게 생각한 까닭이 함께 나오게 물으면 답이 풍부해지오(예: "○○을 보고, ~한 까닭은 무엇이겠소?").</p></div></fieldset>`;
    return `
    <button class="linkbtn" data-act="asub" data-v="roles">← 역할 목록</button>
    <form class="form" data-form="arole">
      <h2>${r.isNew ? '새 역할' : `${h(r.name)} ${h(r.person)}`}</h2>
      ${r.chosen ? `<div class="banner info">이 역할을 고른 학생이 ${r.chosen}명 있소. 고친 문구는 그 학생들 화면에도 바로 보이오.</div>` : ''}
      <div class="row2"><div class="field"><label for="r-name">역할 이름</label><input id="r-name" maxlength="30" value="${h(r.name)}" placeholder="예: 수문장" required></div>
        <div class="field"><label for="r-person">인물 이름</label><input id="r-person" maxlength="20" value="${h(r.person)}" placeholder="예: 박무겸" required></div></div>
      <div class="row2"><div class="field"><label for="r-seal">인장 글자(한 글자)</label><input id="r-seal" maxlength="2" value="${h(r.seal)}"></div>
        <div class="field"><label for="r-sort">순서</label><input id="r-sort" type="number" min="0" max="999" value="${r.sort}"></div></div>
      <div class="field"><label for="r-intro">한 줄 소개</label><input id="r-intro" maxlength="200" value="${h(r.intro)}"></div>
      <div class="field"><label for="r-career">이어지는 진로</label><input id="r-career" maxlength="100" value="${h(r.career)}" placeholder="예: 경찰·경호·군인"></div>
      <label class="check"><input type="checkbox" id="r-on" ${r.enabled ? 'checked' : ''}> 학생에게 보이기(켜기)</label>
      <div class="field"><label for="r-letter">편지 (문단 사이를 한 줄 띄우시오)</label><textarea id="r-letter" rows="7">${h((r.letter || []).join('\n\n'))}</textarea></div>
      <h2>미션 3개</h2>
      <p class="hint">궁 미션 → 박물관 미션 순서로 두시오. 박물관 미션 앞에 “흥례문 게이트를 나가 박물관 앞에 모이오” 줄이 저절로 들어가오.</p>
      ${r.missions.map(mf).join('')}
      <h2>엔딩</h2>
      <p class="hint">엔딩 시각에 열리오. 학생이 찍은 사진을 세피아로 띄운 채 단락을 하나씩 넘기고, “그리고 지금”에서 원래 색으로 돌아오오.</p>
      <div class="field"><label for="e-pm">다시 띄울 학생 사진</label><select id="e-pm">${[1, 2, 3].map(i => `<option value="${i}" ${pm === i ? 'selected' : ''}>미션 ${i}의 사진</option>`).join('')}</select></div>
      <div class="field"><label for="e-then">그 뒤 이 궁궐에 일어난 일 (단락 사이를 한 줄 띄우시오)</label><textarea id="e-then" rows="8">${h((e.then || []).join('\n\n'))}</textarea></div>
      <div class="field"><label for="e-now">그리고 지금</label><textarea id="e-now" rows="3">${h(e.now)}</textarea></div>
      <div class="field"><label for="e-prompt">인물에게 남길 한마디 질문</label><input id="e-prompt" maxlength="200" value="${h(e.prompt)}"></div>
      <div class="row2"><div class="field"><label for="e-old">옛 사진(선택)</label><select id="e-old"><option value="">쓰지 않음</option>${ph.map(o => `<option value="${h(o.src)}" ${old && old.src === o.src ? 'selected' : ''}>${h(o.cap)}</option>`).join('')}</select>
        <p class="hint">훼손 단락에서 학생 사진 대신 그때의 사진을 띄우오.</p></div>
        <div class="field"><label for="e-oldat">옛 사진을 띄울 단락</label><input id="e-oldat" type="number" min="1" max="8" value="${old ? old.at + 1 : 2}"></div></div>
      <div class="actionbar"><button class="btn block" type="submit">이 역할 저장</button></div>
      ${!r.isNew && !r.chosen ? `<div style="margin-top:12px"><button class="btn line block" type="button" data-act="delRole" data-v="${h(r.id)}">이 역할 지우기</button></div>` : ''}
    </form>`;
  }
  async function saveRole() {
    const r = EDIT;
    const ms = [0, 1, 2].map(i => ({ place_key: val(`m${i}-key`), place: val(`m${i}-place`).trim(), clue: val(`m${i}-clue`).trim(), photo: val(`m${i}-photo`).trim(), diary: val(`m${i}-diary`).trim() }));
    const oldSrc = val('e-old'), oldObj = oldSrc ? oldPhotos().find(o => o.src === oldSrc) : null;
    const body = { then: paras(val('e-then')), now: val('e-now').trim(), prompt: val('e-prompt').trim() };
    if (oldObj) body.old = { ...oldObj, at: Math.max(0, Math.min(body.then.length - 1, (+val('e-oldat') || 2) - 1)) };
    const p = { id: r.id, sort: +val('r-sort') || 0, enabled: document.getElementById('r-on').checked, name: val('r-name').trim(), person: val('r-person').trim(),
      seal: val('r-seal').trim(), intro: val('r-intro').trim(), career: val('r-career').trim(), letter: paras(val('r-letter')), img: !!r.img,
      missions: ms, ending: { photo_mission: +val('e-pm') || 1, body } };
    if (G.busy) return; G.busy = true;
    try {
      const res = await rpc('gp_admin_save_role', { p });
      if (res !== 'ok') { toast(SAVE_MSG[res] || res); return; }
      await load(true); await refreshPublic();
      EDIT = null; G.V.admin = 'roles'; G.render(true); toast('역할을 저장했소.');
    } catch (e) { toast(errText(e)); } finally { G.busy = false; }
  }

  /* ---------- 교사 계정 ---------- */
  function staffView() {
    const cc = ADM.settings.class_count, s = SEDIT;
    const list = ADM.staff.map(x => `<tr><td><button class="namebtn" data-act="editStaff" data-v="${x.id}">${h(x.name)}</button><span class="sm">${h(x.login_id)}${x.email ? ' · ' + h(x.email) : ''}</span></td>
      <td class="nw">${x.kind === 'admin' ? '관리자' : '담임'}</td><td class="nw">${(x.classes || []).join('·') || '-'}</td><td class="nw">${x.locked ? '🔒 잠김' : x.must_change ? '첫 로그인 전' : ''}</td></tr>`).join('');
    const form = s ? `<form class="form panel" data-form="astaff" autocomplete="off">
      <h3>${s.id ? '계정 고치기' : '새 교사 계정'}</h3>
      <div class="row2"><div class="field"><label for="t-name">이름</label><input id="t-name" maxlength="20" value="${h(s.name || '')}" required></div>
        <div class="field"><label for="t-id">아이디</label><input id="t-id" autocapitalize="none" spellcheck="false" value="${h(s.login_id || '')}" placeholder="예: t1-kim" required></div></div>
      <fieldset class="radios"><legend>종류</legend><label><input type="radio" name="t-kind" value="homeroom" ${s.kind !== 'admin' ? 'checked' : ''}> 담임(맡은 반만 봄)</label><label><input type="radio" name="t-kind" value="admin" ${s.kind === 'admin' ? 'checked' : ''}> 관리자(전체·관리 화면)</label></fieldset>
      <fieldset class="radios inline"><legend>맡은 반</legend>${Array.from({ length: cc }, (_, i) => i + 1).map(c => `<label><input type="checkbox" name="t-cls" value="${c}" ${(s.classes || []).includes(c) ? 'checked' : ''}> ${c}반</label>`).join('')}</fieldset>
      <div class="field"><label for="t-email">구글 이메일(선택)</label><input id="t-email" type="email" value="${h(s.email || '')}" placeholder="구글 로그인을 쓸 때만">
        <p class="hint">학교 구글 로그인을 켠 경우, 이 이메일로 로그인하면 바로 선생님 화면이 열리오.</p></div>
      <div class="field"><label for="t-pw">${s.id ? '새 비밀번호(바꿀 때만)' : '처음 비밀번호(8자 이상)'}</label>
        <div class="grow"><input id="t-pw" autocomplete="new-password" spellcheck="false"><button class="btn line" type="button" data-act="genPw">만들기</button></div>
        <p class="hint">저장하면 다시 볼 수 없소. 선생님께 따로 전하시오. 그 선생님은 처음 로그인할 때 이 비밀번호를 자기 비밀번호로 바꾸게 되오.</p></div>
      <div style="display:flex;gap:10px;flex-wrap:wrap"><button class="btn" type="submit">저장</button><button class="btn alt" type="button" data-act="cancelStaff">취소</button>
        ${s.id ? `<button class="btn line" type="button" data-act="delStaff" data-v="${s.id}">계정 지우기</button>` : ''}</div>
    </form>` : '<div style="margin:12px 0"><button class="btn sm" data-act="newStaff">새 교사 계정</button></div>';
    return `<p class="lead">담임 선생님은 맡은 반 학생만 보고, 관리자는 전체와 관리 화면을 보오. 공동 담임은 맡은 반을 여러 개 고르시오.</p>
    ${form}
    <div class="tblwrap"><table class="tbl"><thead><tr><th>이름·아이디</th><th class="nw">종류</th><th class="nw">반</th><th></th></tr></thead><tbody>${list}</tbody></table></div>`;
  }
  async function saveStaff() {
    const p = { id: SEDIT.id || null, name: val('t-name').trim(), login_id: val('t-id').trim().toLowerCase(),
      kind: (document.querySelector('input[name="t-kind"]:checked') || {}).value || 'homeroom',
      classes: [...document.querySelectorAll('input[name="t-cls"]:checked')].map(x => +x.value), email: val('t-email').trim(), password: val('t-pw') };
    if (G.busy) return; G.busy = true;
    try {
      const r = await rpc('gp_admin_save_staff', { p });
      if (r !== 'ok') { toast(SAVE_MSG[r] || r); return; }
      SEDIT = null; await load(true); G.render(); toast(p.password ? `저장했소. 아이디 ${p.login_id}, 비밀번호를 선생님께 전하시오.` : '저장했소.');
    } catch (e) { toast(errText(e)); } finally { G.busy = false; }
  }
  const genPw = () => { const a = 'abcdefghjkmnpqrstuvwxyz23456789', b = new Uint32Array(10); crypto.getRandomValues(b); return Array.from(b, x => a[x % a.length]).join(''); };

  /* ---------- 기록 관리 ---------- */
  function recordsView() {
    const c = ADM.counts;
    return `<div class="stats"><div class="stat"><b>${c.students}</b><span>학생</span></div><div class="stat"><b>${c.entries}</b><span>미션 기록</span></div><div class="stat"><b>${c.photos}</b><span>사진</span></div></div>
    <section class="panel"><h3>내려받기</h3><p>전체 반 응답을 CSV 한 파일로 받소(생기부 근거 정리용).</p><div style="margin-top:10px"><button class="btn line sm" data-act="csvAll">전체 반 CSV</button></div></section>
    <section class="panel danger"><h3>학생 기록 모두 지우기</h3>
      <p>학년도가 끝나면 학생 등록·사진·일기·한마디·소감을 모두 지우시오(개인정보 안내에 적은 때). 교사 계정·역할·미션·설정은 남아 다음 행사에 다시 쓸 수 있소. <b>되돌릴 수 없소.</b> 필요한 기록은 먼저 CSV로 받아 두시오.</p>
      <div class="field" style="margin-top:10px"><label for="w-confirm">확인을 위해 <b>기록 지우기</b>라고 적으시오</label><input id="w-confirm" autocomplete="off"></div>
      <div style="margin-top:10px"><button class="btn sm" data-act="wipe">학생 기록 모두 지우기</button></div><p id="w-msg" class="hint" aria-live="polite"></p></section>`;
  }
  async function wipe() {
    if (val('w-confirm').trim() !== '기록 지우기') { toast('확인 칸에 “기록 지우기”라고 적으시오.'); return; }
    modal('학생 기록 모두 지우기', '사진부터 지우고 기록을 지우오. 되돌릴 수 없소. 계속하겠소?', '모두 지우기', async () => {
      const msg = document.getElementById('w-msg'), say = t => { if (msg) msg.textContent = t; };
      try {
        const paths = await rpc('gp_admin_photo_paths') || [];
        for (let i = 0; i < paths.length; i += 100) {
          say(`사진 지우는 중… ${Math.min(i + 100, paths.length)}/${paths.length}`);
          const { error } = await G.sb.storage.from(G.BUCKET).remove(paths.slice(i, i + 100));
          if (error) throw error;
        }
        const r = await rpc('gp_admin_wipe', { p_confirm: '기록 지우기' });
        if (r !== 'ok') { toast('지우지 못했소.'); return; }
        await load(true); G.render(); toast('학생 기록을 모두 지웠소.');
      } catch (e) { toast(errText(e)); say(''); }
    });
  }

  /* ---------- 연결 ---------- */
  G.VIEWS.admin = adminView;
  Object.assign(G.A, {
    async asub(v) { G.V.admin = v; if (v !== 'role') EDIT = null; if (v === 'records') { try { await load(true); } catch (e) {} } G.render(true); },
    editRole(v) { EDIT = JSON.parse(JSON.stringify(CON.find(r => r.id === v))); G.V.admin = 'role'; G.render(true); },
    newRole() { EDIT = blankRole(); G.V.admin = 'role'; G.render(true); },
    async togRole(v) {
      const r = CON.find(x => x.id === v); if (!r || G.busy) return;
      G.busy = true;
      try { const q = { ...r, enabled: !r.enabled }; if (!q.ending) delete q.ending; const res = await rpc('gp_admin_save_role', { p: q }); if (res !== 'ok') toast(SAVE_MSG[res] || res); await load(true); await refreshPublic(); G.render(); }
      catch (e) { toast(errText(e)); } finally { G.busy = false; }
    },
    delRole(v) { modal('역할 지우기', '이 역할과 미션·엔딩을 지우오. 되돌릴 수 없소.', '지우기', async () => { try { const r = await rpc('gp_admin_delete_role', { p_id: v }); if (r !== 'ok') { toast(SAVE_MSG[r] || r); return; } await load(true); await refreshPublic(); EDIT = null; G.V.admin = 'roles'; G.render(true); toast('지웠소.'); } catch (e) { toast(errText(e)); } }); },
    newJoin() { const a = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789', b = new Uint32Array(6); crypto.getRandomValues(b); document.getElementById('a-join').value = Array.from(b, x => a[x % a.length]).join(''); toast('새 코드를 넣었소. [설정 저장]을 눌러야 바뀌오.'); },
    copyUrl() { const u = location.origin + location.pathname; (navigator.clipboard ? navigator.clipboard.writeText(u) : Promise.reject()).then(() => toast('주소를 복사했소.'), () => toast(u)); },
    newStaff() { SEDIT = { kind: 'homeroom', classes: [] }; G.render(); },
    editStaff(v) { SEDIT = { ...ADM.staff.find(x => x.id === v) }; G.render(); window.scrollTo(0, 0); },
    cancelStaff() { SEDIT = null; G.render(); },
    genPw() { const el = document.getElementById('t-pw'); el.value = genPw(); el.select(); },
    delStaff(v) { modal('계정 지우기', '이 선생님 계정을 지우오. 그 선생님은 더 이상 들어올 수 없소.', '지우기', async () => { try { const r = await rpc('gp_admin_delete_staff', { p_id: v }); if (r !== 'ok') { toast(SAVE_MSG[r] || r); return; } SEDIT = null; await load(true); G.render(); toast('지웠소.'); } catch (e) { toast(errText(e)); } }); },
    wipe() { wipe(); }
  });
  Object.assign(G.FORMS, { asettings: saveSettings, arole: saveRole, astaff: saveStaff });
})();
