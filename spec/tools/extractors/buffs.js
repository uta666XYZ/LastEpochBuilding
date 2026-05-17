// buffs.v2 — opens the Buffs overlay (.action-button.buffs-tab), walks every section/buff-entry, captures effects/sources/settings.
// Populates: window.__LEB_BUFFS (JSON string), window.__LEB_BUFFS_DONE (bool). Errors → window.__LEB_BUFFS_ERR. NOTE: `active` flag is class-name inference; activeFlagWarn is in meta.
// Source: LETools 詳細情報習得方法.md L1395-1467.
window.__LEB_BUFFS_DONE = false;
window.__LEB_MODE_BEFORE_I = document.querySelector('.bottom-tabs .attr-type.tab.selected')?.innerText?.trim();
(async () => {
  try {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  document.querySelector('.action-button.buffs-tab')?.click();
  await sleep(500);
  const ov = document.querySelector('.overlay-form.min-grid-22');
  const ff = ov?.querySelector('.form-fields');
  const sections = [];
  let cur = null;
  for (const child of ff.children) {
    if (child.classList.contains('form-section-header')) {
      if (cur) sections.push(cur);
      cur = { name: child.innerText.trim(), buffs: [] };
    } else if (child.classList.contains('buff-entry-block')) {
      const wrappers = [...child.querySelectorAll('.buff-entry-wrapper')];
      if (wrappers.length === 0) {
        cur && cur.buffs.push({ empty: true, text: child.innerText.trim() });
      } else {
        for (const w of wrappers) {
          const ent = w.querySelector('.buff-entry');
          const fcCls = w.querySelector('.field-checkbox')?.className || null;
          const cbCls = w.querySelector('.checkbox')?.className || null;
          const active = /checked|active/i.test([fcCls, cbCls, w.className].join(' '));
          const iconCls = [...(ent?.querySelector('.buff-icon .icons')?.classList || [])].find(c => c.startsWith('icons-r-')) || null;
          const name = ent?.querySelector('.buff-name')?.innerText.trim();
          const effectsContainer = ent?.querySelector('.buff-effects');
          const effects = effectsContainer ? [...effectsContainer.children].map(c => c.innerText.trim().replace(/\s+/g,' ')).filter(Boolean) : [];
          const sl = ent?.querySelector('.source-list');
          let sources = null, sourcesRaw = null;
          if (sl) {
            sourcesRaw = sl.innerText.trim();
            const groups = [];
            let g = { items: [], nodes: [], headers: [], ailments: [] };
            for (const ch of sl.children) {
              if (ch.classList.contains('source-list-divider')) { groups.push(g); g = { items: [], nodes: [], headers: [], ailments: [] }; continue; }
              g.items.push(...[...ch.querySelectorAll('a.item-link')].map(a => ({
                name: a.innerText.trim(),
                rarity: [...a.classList].find(c=>c.startsWith('rarity'))||null,
                srcType: ch.querySelector('.from-type')?.innerText?.trim() || null
              })));
              g.nodes.push(...[...ch.querySelectorAll('.tree-node-link')].map(a => ({
                text: a.innerText.trim().replace(/\s+/g,' '),
                points: a.innerText.match(/\d+\/\d+/)?.[0] || null
              })));
              g.headers.push(...[...ch.querySelectorAll('.source-highlight')].map(s => s.innerText.trim()));
              g.ailments.push(...[...ch.querySelectorAll('.ailment-link')].map(a => a.innerText.trim()));
            }
            groups.push(g);
            sources = groups.filter(x => x.items.length || x.nodes.length || x.headers.length || x.ailments.length);
          }
          const settings = w.querySelector('.buff-settings')?.innerText.trim().replace(/\s+/g,' ') || null;
          cur && cur.buffs.push({ active, fcCls, cbCls, iconCls, name, effects, sources, sourcesRaw, settings });
        }
      }
    }
  }
  if (cur) sections.push(cur);
  const tabCounter = document.querySelector('.action-button.buffs-tab')?.innerText?.match(/(\d+)/)?.[1];
  ov?.querySelector('.form-close-btn')?.click();
  await sleep(300);
  const modeAfter = document.querySelector('.bottom-tabs .attr-type.tab.selected')?.innerText?.trim();
  window.__LEB_BUFFS = JSON.stringify({
    meta: { url: location.href, scrapedAt: new Date().toISOString(),
      modeBefore: window.__LEB_MODE_BEFORE_I, modeAfter, aborted: modeAfter !== 'Actual',
      sectionCount: sections.length, tabActiveCount: tabCounter ? +tabCounter : null,
      activeFlagWarn: 'class-name-based inference; verify against tabActiveCount > 0 build' },
    sections,
  }, null, 2);
  window.__LEB_BUFFS_DONE = true;
  } catch (e) { window.__LEB_BUFFS_ERR = String(e && e.stack || e); window.__LEB_BUFFS_DONE = true; }
})();
'started'
