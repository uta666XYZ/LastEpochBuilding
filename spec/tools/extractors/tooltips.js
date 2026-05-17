// Tooltips extractor — captures per-stat hover breakdowns across 5 stats tabs.
// LETools uses jQuery mouseover handlers that render a `.tooltip-v2` floating div.
// General tab uses `.stat-table` + `.stat-row` (handler on row, single value).
// Defense/Minion/Other tabs use `.stat-table2` + `.stat-row2` (handler on each `.stat-value2` cell, multi-column).
// Output schema: { meta:{...}, tabs:{ <TabName>: [ {header, rows:[{name, value, tooltip}]} ] } }
// Multi-column rows are flattened: name suffixed with column header when >1 cell.
// Globals: __LEB_TOOLTIPS_DONE, __LEB_TOOLTIPS, __LEB_TOOLTIPS_ERR.

window.__LEB_TOOLTIPS_DONE = false;
window.__LEB_TOOLTIPS = null;
window.__LEB_TOOLTIPS_ERR = null;
(async () => {
  try {
    const sleep = ms => new Promise(r => setTimeout(r, ms));

    const grabTooltipText = () => {
      const els = [...document.querySelectorAll('.tooltip-v2')].filter(el => {
        const r = el.getBoundingClientRect();
        return r.width > 0 && r.height > 0;
      });
      return els[0]?.innerText.trim() || null;
    };

    const hoverEl = async (el) => {
      jQuery(el).trigger('mouseover');
      await sleep(220);
      const tt = grabTooltipText();
      jQuery(el).trigger('mouseout');
      await sleep(30);
      return tt;
    };

    const visible = el => {
      const r = el.getBoundingClientRect();
      return r.width > 0 && r.height > 0;
    };

    // Collect column headers from a stat-table2: look for header row with `.stat-name2` cells without values.
    const getColumnHeaders = (table) => {
      // Try to find a `.stat-table2-header` or first `.stat-row2` that contains only labels.
      // Fallback: derive from cell count.
      const headerRow = table.querySelector('.stat-table2-header, .stat-row2-header');
      if (headerRow) {
        const cells = [...headerRow.querySelectorAll('.stat-value2, .stat-name2, .stat-header2')]
          .map(c => c.innerText.trim()).filter(Boolean);
        if (cells.length) return cells;
      }
      return null;
    };

    const tabs = [...document.querySelectorAll('a.stats-tab.tab')].filter(t => t.textContent.trim() !== 'Calculations');
    const out = {};
    for (const tab of tabs) {
      const tabName = tab.textContent.trim();
      tab.click();
      await sleep(700);

      const sections = [];
      const headers = [...document.querySelectorAll('.stat-table-header')].filter(visible);
      for (const header of headers) {
        let table = header.nextElementSibling;
        while (table && !table.classList.contains('stat-table') && !table.classList.contains('stat-table2') && !table.classList.contains('stat-table-header')) {
          table = table.nextElementSibling;
        }
        if (!table || !visible(table)) continue;

        const rows = [];

        if (table.classList.contains('stat-table')) {
          for (const row of [...table.querySelectorAll('.stat-row')]) {
            const name = row.querySelector('.stat-name')?.innerText.trim().replace(/:\s*$/, '') || null;
            const value = row.querySelector('.stat-value')?.innerText.trim() || null;
            const tooltip = await hoverEl(row);
            rows.push({ name, value, tooltip });
          }
        } else if (table.classList.contains('stat-table2')) {
          const colHeaders = getColumnHeaders(table);
          for (const row of [...table.querySelectorAll('.stat-row2')]) {
            // Skip header rows
            if (row.classList.contains('stat-table2-header') || row.classList.contains('stat-row2-header')) continue;
            const name = row.querySelector('.stat-name2')?.innerText.trim().replace(/:\s*$/, '') || null;
            const cells = [...row.querySelectorAll('.stat-value2')];
            if (cells.length === 0) continue;
            if (cells.length === 1) {
              const value = cells[0].innerText.trim() || null;
              const tooltip = await hoverEl(cells[0]);
              rows.push({ name, value, tooltip });
            } else {
              for (let i = 0; i < cells.length; i++) {
                const cell = cells[i];
                const colLabel = colHeaders && colHeaders[i] ? ` (${colHeaders[i]})` : ` [col${i}]`;
                const value = cell.innerText.trim() || null;
                const tooltip = await hoverEl(cell);
                rows.push({ name: name ? `${name}${colLabel}` : colLabel.trim(), value, tooltip });
              }
            }
          }
        } else {
          continue;
        }

        sections.push({ header: header.innerText.trim(), rows });
      }
      out[tabName] = sections;
    }

    const buildId = (location.pathname.match(/\/planner\/([^/?#]+)/) || [])[1] || null;
    window.__LEB_TOOLTIPS = JSON.stringify({
      meta: { buildId, url: location.href, scrapedAt: new Date().toISOString() },
      tabs: out,
    }, null, 2);
    window.__LEB_TOOLTIPS_DONE = true;
  } catch (e) {
    window.__LEB_TOOLTIPS_ERR = String(e && e.stack || e);
    window.__LEB_TOOLTIPS_DONE = true;
  }
})();
