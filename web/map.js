// 경복궁 지도(궁궐 사람들 키트): OpenStreetMap 실제 건물 위치(mapdata.js)를 그대로 그린다. 미션 장소 번호 핀·동선·내 위치 점.
(function () {
  const M = window.MAPDATA, P = M.P;
  const NAME = {
    gwanghwamun: '광화문', heungnyemun: '흥례문', geunjeongmun: '근정문', geunjeongjeon: '근정전', sajeongjeon: '사정전', gangnyeongjeon: '강녕전',
    gyotaejeon: '교태전', amisan: '아미산', heumgyeonggak: '흠경각', jagyeongjeon: '자경전', sojubang: '소주방',
    donggung: '자선당', bihyeongak: '비현각', gyeonghoeru: '경회루', sujeongjeon: '수정전', hyangwonjeong: '향원정', geoncheonggung: '건청궁',
    jibokjae: '집옥재', museum: '국립고궁박물관', sinmumun: '신무문', geonchunmun: '건춘문', yeongchumun: '영추문'
  };
  // 글자 위치 [dx, dy, 정렬]
  const LBL = {
    gwanghwamun: [0, 20, 'middle'], heungnyemun: [17, 4, 'start'], geunjeongmun: [16, 4, 'start'], geunjeongjeon: [0, 25, 'middle'], sajeongjeon: [17, 4, 'start'],
    gangnyeongjeon: [-17, 4, 'end'], gyotaejeon: [17, 4, 'start'], amisan: [14, -1, 'start'], heumgyeonggak: [-9, -7, 'end'],
    jagyeongjeon: [17, 4, 'start'], sojubang: [15, 4, 'start'], donggung: [-2, 15, 'middle'], bihyeongak: [10, -6, 'start'], gyeonghoeru: [0, 38, 'middle'],
    sujeongjeon: [0, 17, 'middle'], hyangwonjeong: [24, 4, 'start'], geoncheonggung: [-26, 4, 'end'], jibokjae: [0, -10, 'middle'],
    museum: [0, 24, 'middle'], sinmumun: [-9, 4, 'end'], geonchunmun: [-10, -9, 'end'], yeongchumun: [10, -9, 'start']
  };
  const GATES = ['gwanghwamun', 'sinmumun', 'geonchunmun', 'yeongchumun'];
  const KEYS = [[/흥례문 광장/, 'heungnyemun'], [/광화문/, 'gwanghwamun'], [/박물관/, 'museum'], [/아미산/, 'amisan'],
    [/흠경각/, 'heumgyeonggak'], [/근정문/, 'geunjeongmun'], [/근정전/, 'geunjeongjeon'], [/사정전/, 'sajeongjeon'], [/교태전/, 'gyotaejeon'],
    [/곤녕합|건청궁/, 'geoncheonggung'], [/비현각/, 'bihyeongak'], [/자선당/, 'donggung'], [/자경전/, 'jagyeongjeon'], [/강녕전/, 'gangnyeongjeon'], [/소주방/, 'sojubang'],
    [/영추문/, 'yeongchumun'], [/경회루/, 'gyeonghoeru'], [/향원정/, 'hyangwonjeong'], [/수정전/, 'sujeongjeon'], [/집옥재/, 'jibokjae']];
  const keyOf = place => (KEYS.find(([re]) => re.test(place)) || [])[1];
  const keyM = m => m.place_key || keyOf(m.place);   // 키트: 미션마다 지도 장소 키(place_key)가 있다
  const base = `<path d="${M.outline}" class="ground"/><path d="${M.woods}" class="wood"/><path d="${M.water}" class="water" fill-rule="evenodd"/>
    <path d="${M.buildings}" class="bd"/><path d="${M.museum || ''}" class="ms"/><path d="${M.walls}" class="wl"/>`;

  window.palaceMap = function (role, done) {
    const ks = role ? role.missions.map(keyM) : [];
    const hot = new Set(ks);
    const route = [P.ticket];
    ks.forEach((k, i) => {
      if (!P[k]) return;
      const prevMuseum = i > 0 && ks[i - 1] === 'museum', nowMuseum = k === 'museum';
      if ((i === 0 && !nowMuseum) || prevMuseum || (nowMuseum && i > 0)) route.push(P.heungnyemun);
      route.push(P[k]);
    });
    const labels = Object.keys(NAME).filter(k => P[k]).map(k => {
      const [x, y] = P[k], [dx, dy, a] = LBL[k];
      const on = hot.has(k), gate = GATES.includes(k);
      return `${gate ? `<rect x="${x - 4}" y="${y - 4}" width="8" height="8" class="gt"/>` : ''}<text x="${(x + dx).toFixed(1)}" y="${(y + dy).toFixed(1)}" text-anchor="${a}" class="${on ? 'lh' : gate ? 'l s' : 'l'}">${NAME[k]}</text>`;
    }).join('');
    const pins = ks.map((k, i) => {
      if (!P[k]) return '';
      const dupe = ks.slice(0, i).filter(x => x === k).length;   // 같은 장소 미션은 옆으로 비켜 그린다
      const x = P[k][0] + dupe * 20, y = P[k][1], ok = done && done[i];
      return `<g class="pin${ok ? ' ok' : ''}"><line x1="${x}" y1="${y}" x2="${x}" y2="${y - 9}"/><circle cx="${x}" cy="${y - 15}" r="9"/><text x="${x}" y="${y - 11.5}" text-anchor="middle">${ok ? '✓' : i + 1}</text></g>`;
    }).join('');
    const [tx, ty] = P.ticket;
    return `<svg class="pmap" viewBox="0 0 ${M.w} ${M.h}" role="img" aria-label="경복궁 지도와 나의 동선">
  ${base}${labels}
  <text x="${tx}" y="${ty + 4}" text-anchor="middle" class="star">★</text><text x="${tx + 9}" y="${ty + 4}" class="tk">매표소·집결</text>
  ${route.length > 1 ? `<polyline points="${route.map(p => p[0] + ',' + p[1]).join(' ')}" class="route"/>` : ''}
  ${pins}
  <g class="me" style="display:none"><circle class="acc" r="0"/><circle class="dot" r="5"/></g>
  <g class="compass"><path d="M${M.w - 20} 12 l6 14 h-12z"/><text x="${M.w - 20}" y="38" text-anchor="middle">북</text></g>
  <text x="4" y="${M.h - 4}" class="osm">© OpenStreetMap</text>
</svg>`;
  };
  // 위도·경도 → 지도 좌표. 지도 밖이면 null.
  window.mapLocate = function (lat, lon, accM) {
    const g = M.geo, x = (lon - g.lonMin) * g.kx, y = (g.latMax - lat) * g.ky;
    if (x < 0 || y < 0 || x > M.w || y > M.h) return null;
    return { x, y, r: Math.min(60, Math.max(4, (accM || 0) * g.ky / 110574)) };
  };
  window.placeKey = keyOf;
  // 관리자 화면의 장소 고르기 목록(지도에 이름이 있는 곳)
  window.PLACES = Object.keys(NAME).filter(k => P[k]).map(k => ({ key: k, name: NAME[k] }));

  // 함께 다니기: 모인 친구들의 궁 미션 장소를 가장 짧게 잇는 순서(매표소 → 흥례문 → 장소들 → 흥례문 → 박물관).
  // 걷는 시간은 직선거리 × 1.3(길 돌아감) ÷ 분당 50m로 어림한다. 머무는 시간은 두 가지로 센다.
  //  full: 장소마다 5분 + (한 사람이 그 장소에서 하는 미션 수 × 4분, 친구끼리는 동시에 함) — 사진과 일기 40자를 그 자리에서 씀
  //  quick: 장소마다 3분 + 미션 하나당 1분 — 사진만 찍고 일기는 박물관에서나 18:00까지 씀
  // 2026-10-16 어림: 혼자는 full로도 최대 60분, 3명은 full이면 대부분 70분을 넘고 quick이면 최대 74분(중앙값 60분).
  const MPX = 110574 / M.geo.ky, WALK = d => d * MPX * 1.3 / 50;
  const dist = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);
  const FLOOR = [[/지하 2층/, '지하 2층', -1], [/왕실의례|궁중서화|과학문화/, '지하', 0], [/대한제국/, '1층', 1], [/조선의 국왕|왕실생활/, '2층', 2]];
  function perms(a) { if (a.length < 2) return [a]; return a.flatMap((x, i) => perms([...a.slice(0, i), ...a.slice(i + 1)]).map(p => [x, ...p])); }
  window.groupPlan = function (members) {
    const stops = {};
    const museum = [];
    members.forEach((mb, wi) => mb.role.missions.forEach((m, i) => {
      if (m.area === '박물관') {
        const f = FLOOR.find(([re]) => re.test(m.place)) || [null, '어느 층이든', 3];
        museum.push({ who: mb.name, me: mb.me, room: m.place.replace(/^국립고궁박물관\s*·?\s*/, '').replace(/[()]/g, '') || '전시실 자유', floor: f[1], fo: f[2] });
        return;
      }
      const k = keyM(m); if (!k || !P[k]) return;
      (stops[k] = stops[k] || { key: k, name: NAME[k], tasks: [] }).tasks.push({ who: mb.name, wi, me: mb.me, n: i + 1, place: m.place });
    }));
    const ks = Object.keys(stops);
    let best = null, bestD = Infinity;
    for (const p of perms(ks)) {
      let d = 0, cur = P.heungnyemun;
      for (const k of p) { d += dist(cur, P[k]); cur = P[k]; }
      d += dist(cur, P.heungnyemun);
      if (d < bestD) { bestD = d; best = p; }
    }
    const fixed = dist(P.ticket, P.heungnyemun) + dist(P.heungnyemun, P.museum);
    const walk = Math.round(WALK(bestD + fixed));
    let full = 0, quick = 0;
    ks.forEach(k => {
      const per = {}; stops[k].tasks.forEach(t => per[t.wi] = (per[t.wi] || 0) + 1);
      full += 5 + 4 * Math.max(...Object.values(per)); quick += 3 + stops[k].tasks.length;
    });
    museum.sort((a, b) => a.fo - b.fo);
    return { order: (best || []).map(k => stops[k]), walk, full: walk + full, quick: walk + quick, museum };
  };
  window.groupMap = function (plan) {
    const route = [P.ticket, P.heungnyemun, ...plan.order.map(s => P[s.key]), P.heungnyemun, P.museum];
    const hot = new Set(plan.order.map(s => s.key));
    const labels = Object.keys(NAME).filter(k => P[k]).map(k => {
      const [x, y] = P[k], [dx, dy, a] = LBL[k], gate = GATES.includes(k);
      return `${gate ? `<rect x="${x - 4}" y="${y - 4}" width="8" height="8" class="gt"/>` : ''}<text x="${(x + dx).toFixed(1)}" y="${(y + dy).toFixed(1)}" text-anchor="${a}" class="${hot.has(k) || k === 'museum' ? 'lh' : gate ? 'l s' : 'l'}">${NAME[k]}</text>`;
    }).join('');
    const pins = plan.order.map((s, i) => {
      const [x, y] = P[s.key], mine = s.tasks.some(t => t.me);
      return `<g class="pin${mine ? '' : ' f'}"><line x1="${x}" y1="${y}" x2="${x}" y2="${y - 9}"/><circle cx="${x}" cy="${y - 15}" r="9"/><text x="${x}" y="${y - 11.5}" text-anchor="middle">${i + 1}</text></g>`;
    }).join('');
    const [tx, ty] = P.ticket;
    return `<svg class="pmap" viewBox="0 0 ${M.w} ${M.h}" role="img" aria-label="경복궁 지도와 함께 다니는 동선">
  ${base}${labels}
  <text x="${tx}" y="${ty + 4}" text-anchor="middle" class="star">★</text><text x="${tx + 9}" y="${ty + 4}" class="tk">매표소·집결</text>
  <polyline points="${route.map(p => p[0] + ',' + p[1]).join(' ')}" class="route"/>
  ${pins}
  <g class="me" style="display:none"><circle class="acc" r="0"/><circle class="dot" r="5"/></g>
  <g class="compass"><path d="M${M.w - 20} 12 l6 14 h-12z"/><text x="${M.w - 20}" y="38" text-anchor="middle">북</text></g>
  <text x="4" y="${M.h - 4}" class="osm">© OpenStreetMap</text>
</svg>`;
  };
})();
