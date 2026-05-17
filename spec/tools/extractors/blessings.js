// blessings.v2 — per-slot hover (rolled value) + click (range min/max) for all 10 blessing slots.
// Populates: window.__LEB_BLESSINGS (JSON string), window.__LEB_BL_DONE (bool). Errors → window.__LEB_BLESSINGS_ERR.
// Source: LETools 詳細情報習得方法.md L696-776. NOTE: doc uses __LEB_BL_DONE (not __LEB_BLESSINGS_DONE) as the completion flag.
(async () => {
  try {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const parseCard = card => {
    if (!card) return null;
    const lines = card.innerText.split('\n').map(s => s.trim()).filter(Boolean);
    const nameEl = card.querySelector('.item-name');
    const tlEl = card.querySelector('.timeline[timeline-id]');
    const tlLine = lines.find(l => l.startsWith('Timeline:'));
    const tlMatch = tlLine?.match(/Timeline:\s*(.+?)\s*\(level\s*(\d+)\)/);
    // range form: "(min to max) ..." or "+(min to max) ..."
    const rangeLine = lines.find(l => /^[+-]?\(.+\s+to\s+.+\)/.test(l));
    const rangeMatch = rangeLine?.match(/^([+-]?)\(([^)]+?)\s+to\s+([^)]+?)\)\s*(.+)$/);
    // roll form: any non-meta line that's not the range form (hover tooltip case)
    const rollLine = lines.find(l =>
      l !== rangeLine && !l.startsWith('Timeline:') &&
      l !== 'Implicits' && l !== 'Blessing' && l !== lines[0]);
    return {
      name: nameEl?.innerText?.trim() || lines[0],
      itemId: nameEl?.getAttribute('item-id') || null,
      timeline: tlMatch ? tlMatch[1] : null,
      timelineLevel: tlMatch ? +tlMatch[2] : null,
      timelineId: tlEl ? +tlEl.getAttribute('timeline-id') : null,
      rangeLine, rollLine,
      sign: rangeMatch ? rangeMatch[1] : null,
      rangeMin: rangeMatch ? rangeMatch[2] : null,
      rangeMax: rangeMatch ? rangeMatch[3] : null,
      statText: rangeMatch ? rangeMatch[4] : null,
    };
  };
  const results = [];
  const equipped = [...document.querySelectorAll('.equipped-item.item-blessing')];
  for (let i = 0; i < equipped.length; i++) {
    const eq = equipped[i];
    const slot = +eq.getAttribute('timeline');
    const bm = eq.querySelector('[class*="itemdb-"]');
    const bmCls = bm ? [...bm.classList].find(c => c.startsWith('itemdb-')) : null;
    const r = eq.getBoundingClientRect();
    const opts = { bubbles: true, cancelable: true, view: window,
                   clientX: r.x + r.width / 2, clientY: r.y + r.height / 2 };
    // 1. HOVER → tooltip (rolled value)
    ['mouseenter', 'mouseover', 'mousemove'].forEach(t =>
      eq.dispatchEvent(new MouseEvent(t, opts)));
    await sleep(350);
    const hoverCard = [...document.querySelectorAll('.item-card.item-blessing')]
      .filter(c => c.getBoundingClientRect().width > 0 && !c.classList.contains('selected'))
      .pop();
    const rollData = parseCard(hoverCard);
    ['mouseleave', 'mouseout'].forEach(t =>
      eq.dispatchEvent(new MouseEvent(t, opts)));
    await sleep(150);
    // 2. CLICK → editor selected card (range)
    eq.click();
    await sleep(450);
    const sel = [...document.querySelectorAll('.item-card.item-blessing')]
      .filter(c => c.getBoundingClientRect().width > 0)
      .find(c => c.classList.contains('selected'));
    const rangeData = parseCard(sel);
    document.querySelector('#btn-cancel')?.click();
    await sleep(400);
    results.push({
      slot, bitmap: bmCls,
      name: rangeData?.name || rollData?.name,
      itemId: rangeData?.itemId || rollData?.itemId,
      timeline: rangeData?.timeline,
      timelineId: rangeData?.timelineId,
      timelineLevel: rangeData?.timelineLevel,
      rangeLine: rangeData?.rangeLine,
      rangeMin: rangeData?.rangeMin,
      rangeMax: rangeData?.rangeMax,
      sign: rangeData?.sign,
      statText: rangeData?.statText,
      rolledLine: rollData?.rollLine,    // e.g. "70% Increased Gold Drop Rate" or "+86 Mana"
    });
  }
  window.__LEB_BLESSINGS = JSON.stringify({
    meta: { url: location.href, scrapedAt: new Date().toISOString(), count: results.length },
    blessings: results,
  }, null, 2);
  window.__LEB_BL_DONE = true;
  } catch (e) { window.__LEB_BLESSINGS_ERR = String(e && e.stack || e); window.__LEB_BL_DONE = true; }
})();
