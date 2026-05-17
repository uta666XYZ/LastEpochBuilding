"""Probe whether Playwright can reach LETools planner pages.

Run: python spec/tools/probe_letools.py
"""
from playwright.sync_api import sync_playwright

URL = "https://www.lastepochtools.com/planner/A21YaLpz"

def main():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=False, args=["--disable-blink-features=AutomationControlled"])
        ctx = browser.new_context(
            user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
            viewport={"width": 1600, "height": 1000},
        )
        page = ctx.new_page()
        print(f"[probe] navigating to {URL}")
        page.goto(URL, wait_until="domcontentloaded", timeout=60000)
        print(f"[probe] title: {page.title()!r}")
        print(f"[probe] body len after networkidle: {page.evaluate('document.body.innerText.length')}")

        # Poll until tippy is attached to a skill icon
        import time
        for i in range(20):
            res = page.evaluate("""() => {
                const els = document.querySelectorAll('.skill-icon-block');
                let withTippy = 0;
                els.forEach(el => { if (el._tippy) withTippy++; });
                return { total: els.length, withTippy };
            }""")
            print(f"[probe] poll {i}: skill-icon-block total={res['total']} withTippy={res['withTippy']}")
            if res['withTippy'] > 0:
                break
            time.sleep(2)

        # Final sniff
        has_tippy = page.evaluate("""() => {
            const el = document.querySelector('.skill-icon-block');
            const isVisible = el ? el.offsetWidth > 0 && el.offsetHeight > 0 : false;
            return {
                hasEl: !!el,
                hasTippy: !!(el && el._tippy),
                isVisible,
                hadronPresent: !!document.querySelector('script[src*="hadron"]'),
                bodyLen: document.body.innerText.length,
            };
        }""")
        print(f"[probe] final sniff: {has_tippy}")

        browser.close()

if __name__ == "__main__":
    main()
