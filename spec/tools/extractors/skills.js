// Skills v2 extractor — walks every specced skill slot, captures level breakdown + node tooltips.
// Globals: __LEB_SKILLS_DONE, __LEB_SKILLS, __LEB_SKILLS_ERR.
window.__LEB_SKILLS_DONE = false;
window.__LEB_SKILLS = null;
window.__LEB_SKILLS_ERR = null;
(async () => {
  try {
    const sleep = ms => new Promise(r => setTimeout(r, ms));

    const idToName = {};
    [...document.querySelectorAll('.skill-icon-block')].forEach(b => {
      const ic = b.querySelector('.skill-icon .icons');
      if (!ic) return;
      const id = [...ic.classList].find(c => c.startsWith('icons-r-'))?.replace('icons-r-','');
      const n = b.querySelector('.skill-name')?.innerText.trim();
      if (id && n) idToName[id] = n;
    });

    const showAndGetPopper = async (el) => {
      if (!el || !el._tippy) return null;
      el._tippy.show();
      await sleep(60);
      return el._tippy.popper || null;
    };
    const hideTippy = (el) => { try { el?._tippy?.hide(); } catch(e){} };

    const parseLevelTooltip = (popper) => {
      if (!popper) return null;
      const header = popper.querySelector('.sources-header');
      const headerName = header?.querySelector('.stat-name')?.innerText.trim().replace(/:\s*$/, '');
      const headerVal = +header?.querySelector('.stat-value')?.innerText.trim();
      const sources = [...popper.querySelectorAll('.sources-list .source-row')].map(r => {
        const itemLink = r.querySelector('.item-link');
        const itemSrc = r.querySelector('.item-src');
        if (itemLink) {
          return {
            source: `${itemLink.innerText.trim()} - ${itemSrc?.innerText.trim() || ''}`,
            value: r.querySelector(':scope > .source-value')?.innerText.trim() || null,
          };
        }
        return {
          source: r.querySelector('.source-name')?.innerText.trim().replace(/:\s*$/, '') || null,
          value: r.querySelector(':scope > .stat-value')?.innerText.trim() || null,
        };
      });
      return {header: headerName, total: isNaN(headerVal) ? null : headerVal, sources};
    };

    const parseNodeTooltip = (popper, hasPoints) => {
      if (!popper) return null;
      const parts = popper.innerText.split('\n').map(s => s.trim()).filter(Boolean);
      if (hasPoints) return {points: parts[0], name: parts[1], desc: parts.slice(2).join(' | ')};
      return {points: null, name: parts[0], desc: parts.slice(1).join(' | ')};
    };

    const specSlots = [...document.querySelectorAll('.skill-spec-slot.slot-with-skill')];
    const results = [];
    for (let i = 0; i < specSlots.length; i++) {
      const slot = specSlots[i];
      const ic = slot.querySelector('.slot-icon .icons');
      const iconId = [...ic.classList].find(c => c.startsWith('icons-r-'))?.replace('icons-r-','');
      const level = slot.querySelector('.slot-level')?.innerText.trim();
      const unspent = slot.querySelector('.slot-points')?.innerText.trim();
      const dmgTypes = [...slot.querySelectorAll('.skill-damage-types-inner > div')]
        .filter(d => getComputedStyle(d).display !== 'none' && d.getBoundingClientRect().width > 0)
        .map(d => [...d.classList].find(c => c.startsWith('panels_ui-skill-damage-'))?.replace('panels_ui-skill-damage-',''));
      slot.click();
      await sleep(900);

      const lvlEl = [...document.querySelectorAll('.skill-level')].find(e => e.getBoundingClientRect().width > 0);
      const lvlPopper = await showAndGetPopper(lvlEl);
      const levelBreakdown = parseLevelTooltip(lvlPopper);
      hideTippy(lvlEl);

      const taken = [...document.querySelectorAll('.tree-node.node-taken')];
      const nodes = [];
      for (const n of taken) {
        const nodeId = n.getAttribute('node-id');
        const nIcon = n.querySelector('.tree-node-icon .icons');
        const iconCls = nIcon ? [...nIcon.classList].find(c => c.startsWith('icons-r-')) : null;
        const points = n.querySelector('.tree-node-points')?.innerText.trim() || null;
        const popper = await showAndGetPopper(n);
        const tip = parseNodeTooltip(popper, !!points);
        hideTippy(n);
        nodes.push({nodeId, iconCls, points, name: tip?.name, desc: tip?.desc});
      }
      results.push({
        i, iconId, name: idToName[iconId] || `(unknown ${iconId})`,
        level, unspent, dmgTypes, levelBreakdown, nodeCount: nodes.length, nodes,
      });
      const back = [...document.querySelectorAll('.back-button')].find(b => b.getBoundingClientRect().width > 0);
      if (back) back.click();
      await sleep(700);
    }
    window.__LEB_SKILLS = JSON.stringify({
      meta: {url: location.href, scrapedAt: new Date().toISOString(), count: results.length},
      skills: results,
    }, null, 2);
    window.__LEB_SKILLS_DONE = true;
  } catch (e) {
    window.__LEB_SKILLS_ERR = String(e && e.stack || e);
    window.__LEB_SKILLS_DONE = true;
  }
})();
