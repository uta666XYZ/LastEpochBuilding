// idol-grid.v2 — derives (row,col,rows,cols) layout of equipped idols on the 45px-cell grid, plus blocked cells.
// Populates: window.__LEB_IDOL_GRID (JSON string), window.__LEB_IDOL_GRID_DONE (bool). Errors → window.__LEB_IDOL_GRID_ERR.
// Source: LETools 詳細情報習得方法.md L1268-1305. Note: original is a sync IIFE assigned to __LEB_IDOL_GRID; we wrap in try/catch.
try {
window.__LEB_IDOL_GRID = (() => {
  const idolTab = [...document.querySelectorAll('.equipment-tab')].find(t => t.innerText.trim() === 'Idols');
  if (idolTab && !idolTab.className.includes('selected-tab')) idolTab.click();
  const allSlots = [...document.querySelectorAll('.idol-slot')].map(s => ({cls: s.className, r: s.getBoundingClientRect()}));
  const visible = allSlots.filter(s => s.r.width > 0);
  if (!visible.length) return null;
  const minX = Math.min(...visible.map(s => s.r.x));
  const minY = Math.min(...visible.map(s => s.r.y));
  const cell = 45; // LETools 固定値
  const toCell = r => ({
    row:  Math.round((r.y - minY) / cell),
    col:  Math.round((r.x - minX) / cell),
    rows: Math.max(1, Math.round(r.height / cell)),
    cols: Math.max(1, Math.round(r.width  / cell)),
  });
  const blocked = allSlots.filter(s => s.cls.includes('blocked')).map(s => {
    const c = toCell(s.r);
    return {row: c.row, col: c.col};
  });
  const idols = [...document.querySelectorAll('.idol-bitmap-container.item-idol')].map((el, idx) => {
    const r = el.getBoundingClientRect();
    const c = toCell(r);
    const cells = [];
    for (let dr = 0; dr < c.rows; dr++)
      for (let dc = 0; dc < c.cols; dc++)
        cells.push([c.row + dr, c.col + dc]);
    return {idx, ...c, x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height), cells};
  });
  const usedCellCount = idols.reduce((s, i) => s + i.rows * i.cols, 0);
  return JSON.stringify({
    meta: {scrapedAt: new Date().toISOString()},
    gridMeta: {origin: {x: Math.round(minX), y: Math.round(minY)}, cell, totalSlots: allSlots.length},
    idols, blocked,
    sanity: {usedCells: usedCellCount, blockedCells: blocked.length, total: usedCellCount + blocked.length},
  }, null, 2);
})();
window.__LEB_IDOL_GRID_DONE = true;
} catch (e) { window.__LEB_IDOL_GRID_ERR = String(e && e.stack || e); window.__LEB_IDOL_GRID_DONE = true; }
