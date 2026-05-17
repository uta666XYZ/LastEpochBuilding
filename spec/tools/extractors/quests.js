// quests.v2 — opens the Quests window and reports completion of "Apophis and Majasa" / "Temple of Eterra" (attribute reward triangulation).
// Populates: window.__LEB_QUESTS (JSON string), window.__LEB_QUESTS_DONE (bool). Errors → window.__LEB_QUESTS_ERR.
// Source: LETools 詳細情報習得方法.md L829-871.
(async () => {
  try {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  // Open quest window if not already open
  const form0 = document.querySelector('.quest-list-form');
  if (!form0 || form0.getBoundingClientRect().width === 0) {
    document.querySelector('.action-button.quests-tab')?.click();
    await sleep(400);
  }
  const list = document.querySelector('.quest-list');
  if (!list) { console.error('quest-list not visible'); return; }
  const findQuest = name => {
    const row = [...list.children].find(c =>
      c.classList?.contains('item-block') &&
      c.querySelector('.quest-name')?.innerText?.trim() === name);
    if (!row) return { found: false };
    return {
      found: true,
      questId: row.getAttribute('quest-id'),
      completed: row.classList.contains('selected'),
      attributePoints: +(row.querySelector('.quest-attribute-count')?.innerText.trim()) || 0,
      passivePoints:   +(row.querySelector('.quest-passive-count')?.innerText.trim()) || 0,
    };
  };
  const apophis = findQuest('Apophis and Majasa');
  const eterra  = findQuest('Temple of Eterra');
  const apophisOn = apophis.completed && apophis.attributePoints > 0;
  const eterraOn  = eterra.completed  && eterra.attributePoints  > 0;
  const total = (apophisOn ? 1 : 0) + (eterraOn ? 1 : 0);
  // close form to leave planner clean
  document.querySelector('.quest-list-form .form-close-btn')?.click();
  window.__LEB_QUESTS = JSON.stringify({
    meta: { url: location.href, scrapedAt: new Date().toISOString() },
    quests: { apophis, eterra },
    attributeReward: `${total}/2`,
    lebConfig: {
      'Apophis and Majasa?': apophisOn,
      'Temple of Eterra?':   eterraOn,
    },
  }, null, 2);
  window.__LEB_QUESTS_DONE = true;
  } catch (e) { window.__LEB_QUESTS_ERR = String(e && e.stack || e); window.__LEB_QUESTS_DONE = true; }
})();
