/* 사용법 카드: 처음 들어온 사람에게 앱 쓰는 법을 카드 몇 장으로 보여 준다(넘기기·건너뛰기·다시 보기).
   window.gpGuide(cards, onDone): cards = [{seal, title, text}] */
(function () {
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  window.gpGuide = function (cards, onDone) {
    if (!cards || !cards.length || document.querySelector('.guide')) return;
    let i = 0, x0 = null;
    const prev = document.activeElement;
    const o = document.createElement('div');
    o.className = 'guide'; o.setAttribute('role', 'dialog'); o.setAttribute('aria-modal', 'true'); o.setAttribute('aria-label', '사용법');
    const close = () => { o.remove(); if (onDone) onDone(); if (prev && prev.focus) prev.focus({ preventScroll: true }); };
    const draw = () => {
      const c = cards[i], last = i === cards.length - 1;
      o.innerHTML = `<div class="gcard" tabindex="-1">
        <div class="gtop"><span class="gstep">${i + 1} / ${cards.length}</span><button class="linkbtn" data-g="skip">건너뛰기</button></div>
        <span class="gseal" aria-hidden="true">${esc(c.seal)}</span>
        <h2>${esc(c.title)}</h2>
        <p>${esc(c.text)}</p>
        <div class="gdots" aria-hidden="true">${cards.map((_, k) => `<span${k === i ? ' class="on"' : ''}></span>`).join('')}</div>
        <div class="grow2">${i ? '<button class="btn alt" data-g="prev">이전</button>' : '<span></span>'}<button class="btn" data-g="${last ? 'done' : 'next'}">${last ? '시작하기' : '다음'}</button></div>
      </div>`;
      o.querySelector(`[data-g="${last ? 'done' : 'next'}"]`).focus({ preventScroll: true });
    };
    o.addEventListener('click', e => {
      const b = e.target.closest('[data-g]'); if (!b) return;
      const g = b.dataset.g;
      if (g === 'next' && i < cards.length - 1) { i++; draw(); }
      else if (g === 'prev' && i > 0) { i--; draw(); }
      else if (g === 'skip' || g === 'done') close();
    });
    o.addEventListener('keydown', e => {
      if (e.key === 'Escape') close();
      else if (e.key === 'ArrowRight' && i < cards.length - 1) { i++; draw(); }
      else if (e.key === 'ArrowLeft' && i > 0) { i--; draw(); }
    });
    o.addEventListener('touchstart', e => { x0 = e.touches[0].clientX; }, { passive: true });
    o.addEventListener('touchend', e => {
      if (x0 === null) return;
      const dx = e.changedTouches[0].clientX - x0; x0 = null;
      if (dx < -50 && i < cards.length - 1) { i++; draw(); } else if (dx > 50 && i > 0) { i--; draw(); }
    });
    document.body.appendChild(o);
    draw();
  };
})();
