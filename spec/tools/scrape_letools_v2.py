"""Unified LETools v2 scraper via CDP attach.

Pre-req:
  - Brave/Chrome running with --remote-debugging-port=9222
  - One tab will be reused/navigated by this script; no manual UI ops required.

Usage:
  python spec/tools/scrape_letools_v2.py [--manifest PATH] [--code CODE] [--types t1,t2,...] [--out-dir DIR]

Default manifest: .tmp/scrape_v2_manifest.txt  (lines: <code>|<basename>)
Default out-dir : $LEB_SCRAPE_OUT_DIR  (env var)
                  or repo-root `.tmp/scrape_v2_out/` if unset (gitignored
                  staging; move artifacts to `spec/TestBuilds/<ver>/` after
                  validation).
Default types   : all 9 (tooltips, items, idols, idol_grid, blessings, quests, skills, passives, buffs)

Progress is tracked in .tmp/scrape_v2_progress.json so re-running resumes.
"""
from __future__ import annotations
import argparse
import json
import os
import sys
import time
from pathlib import Path
from playwright.sync_api import sync_playwright, Page

CDP_URL = "http://localhost:9222"
REPO_ROOT = Path(__file__).resolve().parents[2]
EXTRACTORS_DIR = Path(__file__).parent / "extractors"
DEFAULT_MANIFEST = REPO_ROOT / ".tmp" / "scrape_v2_manifest.txt"
DEFAULT_PROGRESS = REPO_ROOT / ".tmp" / "scrape_v2_progress.json"
# Avoid hard-coding personal paths in the public repo. Override with the
# LEB_SCRAPE_OUT_DIR env var; otherwise stage under the gitignored .tmp/.
DEFAULT_OUT_DIR = Path(os.environ.get("LEB_SCRAPE_OUT_DIR")) if os.environ.get("LEB_SCRAPE_OUT_DIR") else REPO_ROOT / ".tmp" / "scrape_v2_out"

# Per-extractor metadata.
#   file       : JS filename under extractors/
#   global     : window.__LEB_<X> JSON-string global
#   done       : window.__LEB_<X>_DONE boolean
#   err        : window.__LEB_<X>_ERR optional error string
#   nav_js     : JS run before injecting extractor (panel/tab navigation)
#   precheck_js: JS that returns truthy when the panel is ready
#   suffix     : output filename suffix appended to "<basename>"
#   timeout_s  : extractor poll timeout in seconds
EXTRACTORS = {
    "tooltips": {
        "file": "tooltips.js",
        "global": "__LEB_TOOLTIPS",
        "done": "__LEB_TOOLTIPS_DONE",
        "err": "__LEB_TOOLTIPS_ERR",
        "nav_js": "() => { document.querySelector('a.stats-tab.tab')?.click(); }",
        "precheck_js": "() => document.querySelectorAll('a.stats-tab.tab').length > 0",
        "suffix": ".letools.tooltips.json",
        "timeout_s": 240,
    },
    "items": {
        "file": "items.js",
        "global": "__LEB_EQ_HOVER",
        "done": "__LEB_EQ_HOVER_DONE",
        "err": "__LEB_EQ_HOVER_ERR",
        "nav_js": "() => { [...document.querySelectorAll('.equipment-tab')].find(t => t.innerText.trim()==='Equipment')?.click(); }",
        "precheck_js": "() => document.querySelectorAll('.equipped-item').length > 0",
        "suffix": ".letools.items.v2.json",
        "timeout_s": 240,
    },
    "idols": {
        "file": "idols.js",
        "global": "__LEB_IDOLS",
        "done": "__LEB_IDOLS_DONE",
        "err": "__LEB_IDOLS_ERR",
        "nav_js": "() => { [...document.querySelectorAll('.equipment-tab')].find(t => t.innerText.trim()==='Idols')?.click(); }",
        "precheck_js": "() => document.querySelectorAll('.idol-bitmap-container.item-idol').length > 0",
        "suffix": ".letools.idols.v2.json",
        "timeout_s": 360,
    },
    "idol_grid": {
        "file": "idol_grid.js",
        "global": "__LEB_IDOL_GRID",
        "done": "__LEB_IDOL_GRID_DONE",
        "err": "__LEB_IDOL_GRID_ERR",
        "nav_js": "() => { [...document.querySelectorAll('.equipment-tab')].find(t => t.innerText.trim()==='Idols')?.click(); }",
        "precheck_js": "() => document.querySelectorAll('.idol-slot').length > 0",
        "suffix": ".letools.idol-grid.v2.json",
        "timeout_s": 120,
    },
    "blessings": {
        "file": "blessings.js",
        "global": "__LEB_BLESSINGS",
        "done": "__LEB_BL_DONE",
        "err": "__LEB_BLESSINGS_ERR",
        "nav_js": "() => { [...document.querySelectorAll('.equipment-tab')].find(t => t.innerText.trim()==='Blessings')?.click(); }",
        "precheck_js": "() => document.querySelectorAll('.equipped-item.item-blessing').length > 0",
        "suffix": ".letools.blessings.v2.json",
        "timeout_s": 240,
    },
    "quests": {
        "file": "quests.js",
        "global": "__LEB_QUESTS",
        "done": "__LEB_QUESTS_DONE",
        "err": "__LEB_QUESTS_ERR",
        "nav_js": "() => { document.querySelector('.action-button.quests-tab')?.click(); }",
        "precheck_js": "() => document.querySelectorAll('.action-button.quests-tab').length > 0",
        "suffix": ".letools.quests.v2.json",
        "timeout_s": 180,
    },
    "skills": {
        "file": "skills.js",
        "global": "__LEB_SKILLS",
        "done": "__LEB_SKILLS_DONE",
        "err": "__LEB_SKILLS_ERR",
        "nav_js": "() => { document.querySelector('.action-button.skills-panel-tab')?.click(); }",
        "precheck_js": "() => document.querySelectorAll('.skill-spec-slot.slot-with-skill').length > 0",
        "suffix": ".letools.skills.v2.json",
        "timeout_s": 300,
    },
    "passives": {
        "file": "passives.js",
        "global": "__LEB_PASSIVES",
        "done": "__LEB_PASSIVES_DONE",
        "err": "__LEB_PASSIVES_ERR",
        "nav_js": "() => { document.querySelector('.action-button.passives-panel-tab')?.click(); }",
        "precheck_js": "() => document.querySelectorAll('.passive-node, .tree-node').length > 0",
        "suffix": ".letools.passives.v2.json",
        "timeout_s": 360,
    },
    "buffs": {
        "file": "buffs.js",
        "global": "__LEB_BUFFS",
        "done": "__LEB_BUFFS_DONE",
        "err": "__LEB_BUFFS_ERR",
        "nav_js": "() => { /* buffs.js handles its own tab click */ }",
        "precheck_js": "() => document.querySelectorAll('.action-button.buffs-tab').length > 0",
        "suffix": ".letools.buffs.v2.json",
        "timeout_s": 180,
    },
}

ALL_TYPES = list(EXTRACTORS.keys())


def load_manifest(path: Path) -> list[tuple[str, str]]:
    out = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "|" not in line:
            continue
        code, basename = line.split("|", 1)
        out.append((code.strip(), basename.strip()))
    return out


def load_progress(path: Path) -> dict:
    if path.exists():
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            pass
    return {"completed": {}}


def save_progress(path: Path, progress: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(progress, indent=2), encoding="utf-8")


def find_planner_tab(browser, code: str) -> Page | None:
    for ctx in browser.contexts:
        for pg in ctx.pages:
            if f"/planner/{code}" in pg.url:
                return pg
    return None


def get_any_planner_tab(browser) -> Page | None:
    for ctx in browser.contexts:
        for pg in ctx.pages:
            if "lastepochtools.com/planner/" in pg.url:
                return pg
    return None


def navigate_to(tab: Page, code: str) -> None:
    target = f"https://www.lastepochtools.com/planner/{code}"
    if f"/planner/{code}" in tab.url:
        return
    print(f"[scrape-v2] navigating tab -> {target}")
    tab.goto(target, wait_until="domcontentloaded", timeout=60000)
    # Wait for hydration.
    for _ in range(40):
        n = tab.evaluate("() => document.querySelectorAll('.skill-icon-block, .equipped-item, .stats-tab').length")
        if n > 0:
            break
        time.sleep(0.5)


def run_extractor(tab: Page, name: str, meta: dict) -> tuple[str | None, str | None]:
    """Run one extractor. Returns (json_string, err_or_none)."""
    js_path = EXTRACTORS_DIR / meta["file"]
    if not js_path.exists():
        return None, f"missing extractor JS: {js_path}"
    extractor_js = js_path.read_text(encoding="utf-8")

    # Reset globals.
    tab.evaluate(f"() => {{ window.{meta['global']} = null; window.{meta['done']} = false; window.{meta['err']} = null; }}")

    # Navigate panel.
    tab.evaluate(meta["nav_js"])
    # Precheck.
    ok = False
    for _ in range(40):
        if tab.evaluate(meta["precheck_js"]):
            ok = True
            break
        time.sleep(0.5)
    if not ok:
        return None, f"precheck failed for {name}"

    tab.evaluate(extractor_js)
    deadline = time.time() + meta["timeout_s"]
    while time.time() < deadline:
        if tab.evaluate(f"() => window.{meta['done']} === true"):
            break
        time.sleep(2)
    else:
        return None, f"timeout after {meta['timeout_s']}s"

    err = tab.evaluate(f"() => window.{meta['err']}")
    if err:
        return None, f"extractor error: {err}"
    result = tab.evaluate(f"() => window.{meta['global']}")
    if not result:
        return None, "extractor returned null"
    return result, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    ap.add_argument("--progress", type=Path, default=DEFAULT_PROGRESS)
    ap.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    ap.add_argument("--code", help="run only this single build code")
    ap.add_argument("--types", default=",".join(ALL_TYPES), help="comma-separated extractor names")
    ap.add_argument("--force", action="store_true", help="re-run even if output file exists")
    args = ap.parse_args()

    types = [t.strip() for t in args.types.split(",") if t.strip()]
    for t in types:
        if t not in EXTRACTORS:
            print(f"[scrape-v2] unknown type: {t} (valid: {ALL_TYPES})")
            sys.exit(2)

    manifest = load_manifest(args.manifest)
    if args.code:
        manifest = [(c, b) for c, b in manifest if c == args.code]
        if not manifest:
            print(f"[scrape-v2] code {args.code} not in manifest")
            sys.exit(2)

    progress = load_progress(args.progress)
    if not isinstance(progress.get("done_by_code"), dict):
        progress["done_by_code"] = {}
    args.out_dir.mkdir(parents=True, exist_ok=True)

    with sync_playwright() as p:
        browser = p.chromium.connect_over_cdp(CDP_URL)
        tab = get_any_planner_tab(browser)
        if not tab:
            print("[scrape-v2] no lastepochtools planner tab open; please open any /planner/<code> URL first")
            sys.exit(3)
        print(f"[scrape-v2] using tab: {tab.url}")

        for code, basename in manifest:
            print(f"\n[scrape-v2] === {code} ({basename}) ===")
            navigate_to(tab, code)
            tab.wait_for_timeout(800)

            done_for_build = set(progress["done_by_code"].get(code, []))
            for t in types:
                meta = EXTRACTORS[t]
                out_path = args.out_dir / f"{basename}{meta['suffix']}"
                if not args.force and out_path.exists():
                    print(f"[scrape-v2]   skip {t} (exists: {out_path.name})")
                    done_for_build.add(t)
                    continue
                if not args.force and t in done_for_build:
                    print(f"[scrape-v2]   skip {t} (progress marker)")
                    continue
                print(f"[scrape-v2]   run {t}...", flush=True)
                t0 = time.time()
                result_json, err = run_extractor(tab, t, meta)
                elapsed = time.time() - t0
                if err:
                    print(f"[scrape-v2]   FAIL {t} ({elapsed:.1f}s): {err}")
                    continue
                out_path.write_text(result_json, encoding="utf-8")
                print(f"[scrape-v2]   OK {t} ({elapsed:.1f}s, {len(result_json)} bytes) -> {out_path.name}")
                done_for_build.add(t)
                progress["done_by_code"][code] = sorted(done_for_build)
                save_progress(args.progress, progress)


if __name__ == "__main__":
    main()
