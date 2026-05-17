// idols.v2 — per-idol hover (rolled values) + click (affix range walkthrough) for all equipped idols.
// Populates: window.__LEB_IDOLS (JSON string), window.__LEB_IDOLS_DONE (bool). Errors → window.__LEB_IDOLS_ERR.
// Source: LETools 詳細情報習得方法.md L520-602.
(async () => {
  try {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  // 1. ensure Idols tab is selected (hover/click are no-op on hidden idols)
  const idolTab = [...document.querySelectorAll('.equipment-tab')].find(t => t.innerText.trim() === 'Idols');
  if (idolTab && !idolTab.className.includes('selected-tab')) { idolTab.click(); await sleep(400); }

  const parseHover = card => {
    if (!card) return null;
    const nameEl = card.querySelector('.item-name');
    const typeEl = card.querySelector('.item-type');
    const sizeEl = card.querySelector('.item-implicit .mod-value');
    const mods = [...card.querySelectorAll('.item-mod-unique')].map(m => {
      const slotCls = [...m.classList].filter(c => c !== 'item-mod-unique').join(' ');
      const tier = m.querySelector('.tier')?.innerText.trim() || null;
      const clone = m.cloneNode(true);
      clone.querySelector('.tier')?.remove();
      clone.querySelectorAll('br').forEach(br => br.replaceWith(' | '));
      const text = clone.innerText.replace(/\s+/g, ' ').trim();
      const rolledValues = [...m.querySelectorAll('.mod-value-wrap .mod-value')].map(v => v.innerText.trim());
      return { slot: slotCls, tier, text, rolledValues };
    });
    return {
      name: nameEl?.innerText.trim(),
      itemId: nameEl?.getAttribute('item-id'),
      type: typeEl?.innerText.trim(),
      size: sizeEl?.innerText.trim(),
      mods,
    };
  };

  const idolEls = [...document.querySelectorAll('.idol-bitmap-container.item-idol')];
  const results = [];
  for (let i = 0; i < idolEls.length; i++) {
    const el = idolEls[i];
    const r = el.getBoundingClientRect();
    const pos = { x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height) };
    const opts = { bubbles: true, cancelable: true, view: window,
                   clientX: r.x + r.width / 2, clientY: r.y + r.height / 2 };

    // 2. HOVER → tooltip with rolled values
    ['mouseenter', 'mouseover', 'mousemove'].forEach(t => el.dispatchEvent(new MouseEvent(t, opts)));
    await sleep(400);
    const hoverCard = [...document.querySelectorAll('.item-card.item-idol')].filter(c => c.getBoundingClientRect().width > 0)[0];
    const hover = parseHover(hoverCard);
    ['mouseleave', 'mouseout'].forEach(t => el.dispatchEvent(new MouseEvent(t, opts)));
    await sleep(150);

    // 3. CLICK → fullscreen editor for affix range walkthrough
    el.click();
    await sleep(700);
    const tabBar = document.querySelector('.tab-bar');
    if (!tabBar) {
      results.push({ i, pos, hover, error: 'no tab-bar' });
      document.querySelector('#btn-cancel')?.click();
      await sleep(500);
      continue;
    }
    const tabs = [...tabBar.querySelectorAll('.tab')].map(t => ({ cls: t.className, text: t.textContent.trim() }));
    const sizeLabel = tabBar.previousElementSibling?.textContent?.trim() || '';
    const selectedItemCard = document.querySelector('.basic-items .item-card.selected, .item-card.selected');
    const itemName = selectedItemCard?.querySelector('.item-name')?.textContent.trim() || '';
    const usedTabs = [...tabBar.querySelectorAll('.tab.used')].filter(t => !t.className.includes('items') && !t.className.includes('locked'));
    const affixes = [];
    for (const tab of usedTabs) {
      const tabText = tab.textContent.trim();
      const tabCls = tab.className;
      tab.click();
      await sleep(400);
      const card = document.querySelector('.item-card.item-affix');
      if (!card) { affixes.push({ tab: tabText, tabCls, error: 'no card' }); continue; }
      const name = card.querySelector('.item-name')?.textContent.trim() || '';
      const tierRows = [...card.querySelectorAll('.tier-table .affix, .tier-table > div')].map(rr => ({ cls: rr.className, text: rr.textContent.replace(/\s+/g, ' ').trim() }));
      const bottom = card.querySelector('.bottom-block')?.textContent.replace(/\s+/g, ' ').trim() || '';
      affixes.push({ tab: tabText, tabCls, name, tiers: tierRows, bottom });
    }
    results.push({ i, pos, sizeLabel, itemName, tabs, affixes, hover });
    document.querySelector('#btn-cancel')?.click();
    await sleep(500);
  }
  window.__LEB_IDOLS = JSON.stringify({ meta: { url: location.href, scrapedAt: new Date().toISOString(), count: results.length }, idols: results }, null, 2);
  window.__LEB_IDOLS_DONE = true;
  } catch (e) { window.__LEB_IDOLS_ERR = String(e && e.stack || e); window.__LEB_IDOLS_DONE = true; }
})();
