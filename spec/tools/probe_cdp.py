"""Probe CDP attach to user's running Chrome.

Pre-req: launch Chrome with --remote-debugging-port=9222 and a planner tab open.

Run: python spec/tools/probe_cdp.py
"""
from playwright.sync_api import sync_playwright

CDP_URL = "http://localhost:9222"
PLANNER_HOST = "lastepochtools.com/planner/"

def main():
    with sync_playwright() as p:
        browser = p.chromium.connect_over_cdp(CDP_URL)
        print(f"[probe-cdp] connected; contexts: {len(browser.contexts)}")
        ctx = browser.contexts[0]
        print(f"[probe-cdp] pages in context 0: {len(ctx.pages)}")
        target = None
        for pg in ctx.pages:
            print(f"  - {pg.url}")
            if PLANNER_HOST in pg.url:
                target = pg
        if not target:
            print("[probe-cdp] no planner tab found")
            return
        print(f"[probe-cdp] using tab: {target.url}")
        sniff = target.evaluate("""() => {
            const els = document.querySelectorAll('.skill-icon-block');
            let withTippy = 0;
            els.forEach(el => { if (el._tippy) withTippy++; });
            return {
                skillIcons: els.length,
                withTippy,
                bodyLen: document.body.innerText.length,
                htmlLen: document.documentElement.outerHTML.length,
                title: document.title,
                webdriver: navigator.webdriver,
                itemSlots: document.querySelectorAll('.item-slot').length,
                tippyEls: document.querySelectorAll('[data-tippy-content]').length,
                bodyFirst200: document.body.innerText.slice(0, 200),
            };
        }""")
        print(f"[probe-cdp] sniff: {sniff}")

        # Look for iframes & a representative interactive element
        deeper = target.evaluate("""() => {
            const iframes = [...document.querySelectorAll('iframe')].map(f => ({src: f.src, w: f.clientWidth, h: f.clientHeight}));
            const allDivs = document.querySelectorAll('div').length;
            const hadronBlocked = !!window.__hadron_blocked;
            return {
                iframes,
                allDivs,
                hadronBlocked,
                href: location.href,
                hasJquery: typeof jQuery !== 'undefined',
                hasTippy: typeof tippy !== 'undefined',
                readyState: document.readyState,
            };
        }""")
        print(f"[probe-cdp] deeper: {deeper}")

        # Selectors used by extractor scripts
        sels = target.evaluate("""() => {
            const q = s => document.querySelectorAll(s).length;
            return {
                'tippyContent[data-tippy-content]': q('[data-tippy-content]'),
                'div.tippy-content': q('div.tippy-content'),
                'div.skill-icon-block': q('div.skill-icon-block'),
                'div.skill-slot': q('div.skill-slot'),
                'div.item-slot': q('div.item-slot'),
                'div.spec-skill-slot': q('div.spec-skill-slot'),
                'div.specSlot': q('div.specSlot'),
                '#tab-skills': q('#tab-skills'),
                '.tab-skills': q('.tab-skills'),
                'div.passive-tree': q('div.passive-tree'),
                'div.passive-node': q('div.passive-node'),
                '#tabSkills_btn': q('#tabSkills_btn'),
            };
        }""")
        print(f"[probe-cdp] selectors:")
        for k, v in sels.items():
            print(f"    {k}: {v}")

        # Probe panel-switch buttons (Skills/Passives/Quests etc.)
        buttons = target.evaluate("""() => {
            const out = [];
            document.querySelectorAll('.action-button, .panel-button, button, .btn').forEach(b => {
                const txt = (b.innerText || b.textContent || '').trim();
                if (txt && txt.length < 40) {
                    out.push({tag: b.tagName, cls: b.className, txt});
                }
            });
            return out.filter(b => /Skills|Passives|Weaver|Conditions|Buffs|Quests|Equipment|Idols/i.test(b.txt));
        }""")
        print(f"[probe-cdp] nav buttons:")
        for b in buttons:
            print(f"    [{b['tag']}] cls={b['cls']!r:60s} txt={b['txt']!r}")

        # Sample the actual class names present
        classes = target.evaluate("""() => {
            const counts = {};
            document.querySelectorAll('*').forEach(el => {
                if (el.className && typeof el.className === 'string') {
                    el.className.split(/\\s+/).forEach(c => {
                        if (c) counts[c] = (counts[c] || 0) + 1;
                    });
                }
            });
            const sorted = Object.entries(counts).sort((a,b) => b[1]-a[1]).slice(0, 40);
            return sorted;
        }""")
        print(f"[probe-cdp] top 40 classes:")
        for c, n in classes:
            print(f"    {n:4d}  {c}")

if __name__ == "__main__":
    main()
