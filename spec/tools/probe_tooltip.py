"""Probe tooltip attachment on stat-row elements."""
from playwright.sync_api import sync_playwright

with sync_playwright() as p:
    browser = p.chromium.connect_over_cdp("http://localhost:9222")
    tab = None
    for ctx in browser.contexts:
        for pg in ctx.pages:
            if "lastepochtools.com/planner/" in pg.url:
                tab = pg
    print(f"tab: {tab.url}")
    res = tab.evaluate("""() => {
        const row = document.querySelector('.stat-row');
        if (!row) return {error: 'no .stat-row'};
        const name = row.querySelector('.stat-name');
        const val = row.querySelector('.stat-value');
        return {
            rowHasTippy: !!row._tippy,
            nameHasTippy: !!name?._tippy,
            valHasTippy: !!val?._tippy,
            rowDataTippy: row.getAttribute('data-tippy-content'),
            valHasMouseOver: val ? val.onmouseover !== null : null,
            statName: name?.innerText,
            statValue: val?.innerText,
            rowOuterHTML: row.outerHTML.slice(0, 400),
            anyTippyOnPage: document.querySelectorAll('[data-tippy-root]').length,
        };
    }""")
    for k, v in res.items():
        print(f"  {k}: {v}")
    # Try dispatch mouseover + check
    res2 = tab.evaluate("""async () => {
        const sleep = ms => new Promise(r => setTimeout(r, ms));
        const row = document.querySelector('.stat-row');
        const val = row.querySelector('.stat-value');
        const r = val.getBoundingClientRect();
        const opts = {bubbles:true, cancelable:true, view:window, clientX:r.x+5, clientY:r.y+5};
        ['mouseenter','mouseover','mousemove'].forEach(t => val.dispatchEvent(new MouseEvent(t, opts)));
        await sleep(400);
        const poppers = [...document.querySelectorAll('.tippy-box, [data-tippy-root]')];
        return {
            popperCount: poppers.length,
            rowHasTippyAfter: !!row._tippy,
            valHasTippyAfter: !!val._tippy,
            firstPopperText: poppers[0]?.innerText?.slice(0, 300),
        };
    }""")
    print('after-hover:')
    for k, v in res2.items():
        print(f"  {k}: {v}")
