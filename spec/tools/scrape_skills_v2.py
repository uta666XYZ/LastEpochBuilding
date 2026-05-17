"""POC scraper for .letools.skills.v2.json via CDP attach.

Pre-req: Brave/Chrome running with --remote-debugging-port=9222, planner tab open on Skills tab.

Usage:
  python spec/tools/scrape_skills_v2.py <build_code> <output_path>

Example:
  python spec/tools/scrape_skills_v2.py A21YaLpz "spec/TestBuilds/1.4/A21YaLpz lv98 Necromancer.letools.skills.v2.poc.json"
"""
import sys
import time
from pathlib import Path
from playwright.sync_api import sync_playwright

CDP_URL = "http://localhost:9222"

EXTRACTOR_JS = r"""
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
"""


def find_planner_tab(browser, build_code: str):
    for ctx in browser.contexts:
        for pg in ctx.pages:
            if f"/planner/{build_code}" in pg.url:
                return pg
    return None


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    build_code = sys.argv[1]
    out_path = Path(sys.argv[2])

    with sync_playwright() as p:
        browser = p.chromium.connect_over_cdp(CDP_URL)
        tab = find_planner_tab(browser, build_code)
        if not tab:
            print(f"[scrape-skills] no planner tab for {build_code}; tabs:")
            for ctx in browser.contexts:
                for pg in ctx.pages:
                    print(f"  - {pg.url}")
            sys.exit(2)
        print(f"[scrape-skills] using tab: {tab.url}")

        # Auto-navigate to Skills panel
        tab.evaluate("""() => {
            const btn = document.querySelector('.action-button.skills-panel-tab');
            if (btn) btn.click();
        }""")
        # Wait for spec slots to appear
        for _ in range(20):
            precheck = tab.evaluate("""() => ({
                specSlots: document.querySelectorAll('.skill-spec-slot.slot-with-skill').length,
                iconBlocks: document.querySelectorAll('.skill-icon-block').length,
            })""")
            if precheck['specSlots'] > 0:
                break
            time.sleep(0.5)
        print(f"[scrape-skills] after-navigate: {precheck}")
        if precheck['specSlots'] == 0:
            print("[scrape-skills] navigation failed — no spec slots after clicking Skills tab")
            sys.exit(3)

        # Inject extractor
        tab.evaluate(EXTRACTOR_JS)
        print("[scrape-skills] extractor injected, polling...")

        deadline = time.time() + 180
        while time.time() < deadline:
            done = tab.evaluate("() => window.__LEB_SKILLS_DONE === true")
            if done:
                break
            time.sleep(2)
        else:
            print("[scrape-skills] timeout waiting for extractor")
            sys.exit(4)

        err = tab.evaluate("() => window.__LEB_SKILLS_ERR")
        if err:
            print(f"[scrape-skills] extractor error: {err}")
            sys.exit(5)

        result_json = tab.evaluate("() => window.__LEB_SKILLS")
        print(f"[scrape-skills] result size: {len(result_json)} bytes")

        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(result_json, encoding="utf-8")
        print(f"[scrape-skills] saved → {out_path}")


if __name__ == "__main__":
    main()
