/* 오프닝: 14명이 한 사람씩 나타나고, 그 뒤로 경복궁 두루마리가 펼쳐진다.
   draw(t)는 t초의 장면을 그린다. 앱은 requestAnimationFrame으로 재생하고(처음 한 번만),
   영상 제작(tools/build_opening.py)은 ?opframe=t 로 한 장면씩 캡처한다. */
(function () {
  const IDS = ['juseo', 'sumunjang', 'hwawon', 'gwansang', 'jimil', 'chimbang', 'uinyeo', 'sukso', 'moksu', 'jeongi', 'tongyeok', 'sigangwon', 'sajin', 'akgong'];
  const SEAL = '記守畵星密針醫膳木電譯講寫樂';
  const KEY = 'gp_opening_v1', DUR = 8.6;
  const BASE = (document.currentScript && document.currentScript.src.replace(/opening\.js.*$/, '')) || '';
  const clamp = v => Math.max(0, Math.min(1, v));
  const seg = (t, a, b) => clamp((t - a) / (b - a));
  const out3 = k => 1 - Math.pow(1 - k, 3);
  const inOut = k => k < .5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2;
  const back = k => { const c = 1.7; return 1 + (c + 1) * Math.pow(k - 1, 3) + c * Math.pow(k - 1, 2); };

  function build(root) {
    const o = document.createElement('div');
    o.className = 'opening';
    o.setAttribute('role', 'dialog'); o.setAttribute('aria-modal', 'true'); o.setAttribute('aria-label', '궁궐 사람들 오프닝');
    o.innerHTML = `<div class="op-pano"><img src="${BASE}img/opening/pano.webp" alt="" draggable="false"></div>
      <span class="op-rod l" aria-hidden="true"></span><span class="op-rod r" aria-hidden="true"></span>
      <div class="op-title"><p class="op-sub">1890년 무렵, 경복궁</p><h1>궁궐 사람들</h1><p class="op-sub2">열네 사람이 그대를 기다리오</p></div>
      <div class="op-people" aria-hidden="true">${IDS.map((id, i) => `<div class="op-p" style="background-image:url(${BASE}img/opening/people.webp);--i:${i}"><span class="op-seal">${SEAL[i]}</span></div>`).join('')}</div>
      <button class="op-skip" type="button">건너뛰기 ›</button>`;
    root.appendChild(o);
    return o;
  }

  function layout(o) {
    const W = o.clientWidth, H = o.clientHeight, wide = W / H >= 1;
    const rows = wide ? [7, 7] : [5, 5, 4];
    const cols = Math.max(...rows);
    const fw = wide ? Math.min(W / 8.6, H * .28) : W / 4.7, fh = fw * 4 / 3;
    const pos = []; let k = 0;
    rows.forEach((n, r) => {
      const depth = rows.length - 1 - r;                      // 0 = 맨 앞줄
      const s = 1 - depth * .12, w = fw * s;
      const gap = wide ? fw * .98 : fw * .8;
      const x0 = W / 2 - (n - 1) * gap * s / 2 + (r % 2 ? gap * s * .25 : -gap * s * .25) * (wide ? 1 : 0);
      const bottom = H + fh * .1 - depth * fh * (wide ? .4 : .36);
      for (let j = 0; j < n; j++) pos[k++] = { x: x0 + j * gap * s - w / 2, y: bottom - fh * s, w, h: fh * s, z: 10 + r };
    });
    return { W, H, wide, fw, fh, pos };
  }

  function draw(o, L, t) {
    const pano = o.firstElementChild, img = pano.firstElementChild;
    const [rl, rr] = o.querySelectorAll('.op-rod');
    const title = o.querySelector('.op-title'), people = o.querySelectorAll('.op-p');
    const { W, H, wide, fw, fh, pos } = L;
    // 두루마리 펼치기 3.0~5.2초
    const u = inOut(seg(t, 3.0, 5.2)), half = 50 * (1 - u);
    pano.style.clipPath = `inset(0 ${half}% 0 ${half}%)`;
    pano.style.opacity = String(seg(t, 2.9, 3.1));
    const zoom = 1.12 - .12 * out3(seg(t, 3.0, 8.6));
    img.style.transform = `translate(-50%,-50%) scale(${zoom})`;
    img.style.objectPosition = wide ? '50% 60%' : '60% 50%';
    const rodOn = seg(t, 2.9, 3.1) * (1 - seg(t, 5.0, 5.5));
    [rl, rr].forEach((r, i) => {
      const x = i ? W * (1 - half / 100) : W * half / 100;
      r.style.transform = `translateX(${x - 7}px)`; r.style.opacity = String(rodOn);
    });
    // 인물 0.3~3.0초에 차례로 등장, 3.0~4.4초에 아래로 물러남
    const settle = inOut(seg(t, 3.0, 4.6));
    const grp = o.querySelector('.op-people'), big = 1 - settle;
    grp.style.transform = `translateY(${-H * (wide ? .22 : .26) * big}px) scale(${1 + (wide ? .18 : .1) * big})`;
    people.forEach((p, i) => {
      const P = pos[i], k = seg(t, .3 + i * .17, .3 + i * .17 + .55);
      const lift = (1 - out3(k)) * fh * .25 + settle * fh * (wide ? .2 : .26);
      const sc = .9 + .1 * back(k);
      Object.assign(p.style, {
        left: `${P.x}px`, top: `${P.y}px`, width: `${P.w}px`, height: `${P.h}px`, zIndex: P.z, opacity: k,
        transform: `translateY(${lift}px) scale(${sc})`,
        backgroundSize: `${P.w * 14}px ${P.h}px`, backgroundPosition: `${-i * P.w}px 0`
      });
      const sk = seg(t, .3 + i * .17 + .35, .3 + i * .17 + .6);
      const s = p.firstElementChild;
      s.style.opacity = String(sk);
      s.style.transform = `scale(${1.8 - .8 * out3(sk)}) rotate(${-12 + 4 * sk}deg)`;
      s.style.fontSize = `${Math.max(9, P.w * .1)}px`;
    });
    // 제목 5.0~6.2초
    const tk = out3(seg(t, 5.0, 6.2)), sk2 = out3(seg(t, 5.6, 6.8));
    title.style.opacity = String(tk);
    title.style.transform = `translateY(${(1 - tk) * 18}px)`;
    title.lastElementChild.style.opacity = String(sk2);
    title.style.fontSize = `${wide ? Math.min(W * .055, H * .1) : W * .11}px`;
    title.style.top = wide ? '9%' : '11%';
    // 끝 8.0~8.6초 사라짐
    o.style.opacity = String(1 - seg(t, 8.0, 8.6));
  }

  function play(opts = {}) {
    const q = new URLSearchParams(location.search);
    const frame = q.has('opframe') ? parseFloat(q.get('opframe')) : null;
    let seen = false;
    try { seen = localStorage.getItem(KEY) === '1'; } catch (e) {}
    const reduced = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (frame === null && !opts.force && !q.has('op') && (seen || reduced)) return;
    try { localStorage.setItem(KEY, '1'); } catch (e) {}
    const o = build(opts.root || document.body);
    let L = layout(o), t0 = null, raf = 0, done = false;
    const end = () => { if (done) return; done = true; cancelAnimationFrame(raf); o.remove(); removeEventListener('resize', onResize); if (opts.onDone) opts.onDone(); };
    const onResize = () => { L = layout(o); };
    addEventListener('resize', onResize);
    if (frame !== null) {                                          // 영상 캡처용: 한 장면만 그리고 멈춤
      o.querySelector('.op-skip').remove();
      const img = o.querySelector('.op-pano img');
      const go = () => { L = layout(o); draw(o, L, frame); document.documentElement.dataset.opReady = '1'; };
      img.complete ? go() : img.addEventListener('load', go);
      return;
    }
    o.querySelector('.op-skip').addEventListener('click', end);
    o.querySelector('.op-skip').focus({ preventScroll: true });
    o.addEventListener('keydown', e => { if (e.key === 'Escape') end(); });
    draw(o, L, 0);
    const imgs = [o.querySelector('.op-pano img'), Object.assign(new Image(), { src: `${BASE}img/opening/people.webp` })];
    let started = false;
    const start = () => {
      if (started) return; started = true;
      const step = now => {
        if (t0 === null) t0 = now;
        const t = (now - t0) / 1000;
        draw(o, L, Math.min(t, DUR));
        if (t >= DUR) end(); else raf = requestAnimationFrame(step);
      };
      raf = requestAnimationFrame(step);
    };
    Promise.all(imgs.map(im => im.decode ? im.decode().catch(() => {}) : null)).then(start);
    setTimeout(start, 2500);                                      // 그림이 늦어도 2.5초 뒤에는 시작
  }

  window.gpOpening = play;
})();
