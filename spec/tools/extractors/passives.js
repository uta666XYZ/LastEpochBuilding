// passives.v2 — clicks each class-diamond, walks taken nodes in each tree, and reads node tooltips via _tippy.show().
// Populates: window.__LEB_PASSIVES (JSON string), window.__LEB_PASSIVES_DONE (bool). Errors → window.__LEB_PASSIVES_ERR.
// Source: LETools 詳細情報習得方法.md L1136-1193.
window.__LEB_PASSIVES_DONE = false;
(async () => {
  try {
  const sleep = ms => new Promise(r => setTimeout(r, ms));

  const tab = document.querySelector('.action-button.passives-panel-tab');
  if (tab && !tab.className.includes('selected')) { tab.click(); await sleep(700); }

  const showAndGetPopper = async (el) => {
    if (!el || !el._tippy) return null;
    el._tippy.show();
    await sleep(60);
    return el._tippy.popper || null;
  };
  const hideTippy = (el) => { try { el?._tippy?.hide(); } catch(e){} };
  const parseNodeTooltip = (popper, hasPoints) => {
    if (!popper) return null;
    const parts = popper.innerText.split('\n').map(s => s.trim()).filter(Boolean);
    if (hasPoints) return {points: parts[0], name: parts[1], desc: parts.slice(2).join(' | ')};
    return {points: null, name: parts[0], desc: parts.slice(1).join(' | ')};
  };

  const diamonds = [...document.querySelectorAll('.passives-panel-left .class-diamond')];
  const trees = [];
  for (const dia of diamonds) {
    const diaText = dia.innerText.trim().replace(/\s+/g, ' ');
    const m = diaText.match(/^(\d+)\s+(.+?)(?:\s+(Base Class|Mastered))?$/);
    const allocated = m ? +m[1] : null;
    const treeName = m ? m[2] : diaText;
    const status = m && m[3] ? m[3] : null;

    dia.click();
    await sleep(700);

    const blk = [...document.querySelectorAll('.passive-tree-block')].find(b => b.getBoundingClientRect().width > 0);
    if (!blk) { trees.push({treeName, allocated, status, error: 'no visible block'}); continue; }

    const taken = [...blk.querySelectorAll('.tree-node.node-taken')];
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
    trees.push({treeName, status, allocated, blockCls: blk.className, nodeCount: nodes.length, nodes});
  }

  window.__LEB_PASSIVES = JSON.stringify({
    meta: {url: location.href, scrapedAt: new Date().toISOString(), treeCount: trees.length},
    trees,
  }, null, 2);
  window.__LEB_PASSIVES_DONE = true;
  } catch (e) { window.__LEB_PASSIVES_ERR = String(e && e.stack || e); window.__LEB_PASSIVES_DONE = true; }
})();
'started'
