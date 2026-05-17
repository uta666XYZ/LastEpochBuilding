// items.v2 (hover pass) — extracts rolled values for the 11 equipment slots via JS-dispatched hover.
// Populates: window.__LEB_EQ_HOVER (JSON string), window.__LEB_EQ_HOVER_DONE (bool). Errors → window.__LEB_EQ_HOVER_ERR.
// TODO: click-tab pass for affix range still needs scripting (merge with this hover output by slot to produce full .letools.items.v2.json).
// Source: LETools 詳細情報習得方法.md L336-387 (hover pass only — no combined v2 script in the doc as of extraction).
(async () => {
  try {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const eqTab = [...document.querySelectorAll('.equipment-tab')].find(t => t.innerText.trim() === 'Equipment');
  if (eqTab && !eqTab.className.includes('selected-tab')) { eqTab.click(); await sleep(400); }
  const parseHover = card => {
    if (!card) return null;
    const nameEl = card.querySelector('.item-name');
    const baseEl = card.querySelector('.item-base');
    const typeEl = card.querySelector('.item-type');
    const rarityCls = [...card.classList].find(c => c.startsWith('item-rarity'));
    const mods = [...card.querySelectorAll('.item-mod-unique')].map(m => {
      const slotCls = [...m.classList].filter(c => c !== 'item-mod-unique').join(' ');
      const tier = m.querySelector('.tier')?.innerText.trim() || null;
      const clone = m.cloneNode(true);
      clone.querySelector('.tier')?.remove();
      clone.querySelectorAll('br').forEach(br => br.replaceWith(' | '));
      const text = clone.innerText.replace(/\s+/g, ' ').trim();
      const rolledValues = [...m.querySelectorAll('.mod-value-wrap .mod-value')].map(v => v.innerText.trim());
      return { slotCls, tier, text, rolledValues };
    });
    return {
      name: nameEl?.innerText.trim() || null,
      itemId: nameEl?.getAttribute('item-id') || null,
      base: baseEl?.innerText.trim() || null,
      type: typeEl?.innerText.trim() || null,
      rarity: rarityCls,
      mods,
    };
  };
  const slots = ['chest','head','hands','feet','waist','weapon1','weapon2','amulet','ring1','ring2','relic'];
  const results = [];
  for (const slot of slots) {
    const eq = document.querySelector('.equipped-item.item-'+slot);
    if (!eq) { results.push({slot, missing:true}); continue; }
    const r = eq.getBoundingClientRect();
    const opts = {bubbles:true, cancelable:true, view:window, clientX:r.x+r.width/2, clientY:r.y+r.height/2};
    ['mouseenter','mouseover','mousemove'].forEach(t => eq.dispatchEvent(new MouseEvent(t, opts)));
    await sleep(380);
    const card = [...document.querySelectorAll('.item-card')].filter(c => {
      const rr = c.getBoundingClientRect();
      return rr.width > 0 && rr.height > 0 && !c.classList.contains('selected');
    }).pop();
    const hover = parseHover(card);
    ['mouseleave','mouseout'].forEach(t => eq.dispatchEvent(new MouseEvent(t, opts)));
    await sleep(120);
    results.push({slot, hover});
  }
  window.__LEB_EQ_HOVER = JSON.stringify({meta:{url:location.href, scrapedAt:new Date().toISOString(), count:results.length}, items:results}, null, 2);
  window.__LEB_EQ_HOVER_DONE = true;
  } catch (e) { window.__LEB_EQ_HOVER_ERR = String(e && e.stack || e); window.__LEB_EQ_HOVER_DONE = true; }
})();
