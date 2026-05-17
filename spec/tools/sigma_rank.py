#!/usr/bin/env python3
# @leb-tooling: sigma-rank
# Compute Σ|Δ%| per build across all spec/TestBuilds/1.4/*.letools.json,
# then assign G1..G6 groups via descending-Σ "横割り" batches.
#
# Canonical reference: Obsidian "Development/テストビルド G分類定義.md"
#
# Usage:
#   python spec/tools/sigma_rank.py                # ranks all builds with both .lua + .letools.json
#   python spec/tools/sigma_rank.py --emit-json    # also write .tmp/sigma_ranking.json + groups_by_sigma.json
#   python spec/tools/sigma_rank.py --group G2     # print only G2 members
#   python spec/tools/sigma_rank.py --include-missing-lua  # report builds missing .lua snapshot
#
# Σ|Δ%| definition: for each stat in diff_letools.py MAPPING, compute
#   pct = |LEB − LETools| / max(|LETools|, eps) * 100
# Skip pct when |LETools| < eps and |Δ| < eps (both zero → no diff). When LETools
# is 0 but LEB nonzero (or vice versa), pct = inf → clipped to CLIP_INF for sigma
# stability.

import argparse, json, os, sys
from collections import OrderedDict

# Force UTF-8 stdout on Windows (cp1252 default blows up on Σ)
if sys.stdout.encoding and sys.stdout.encoding.lower() != 'utf-8':
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass

# Import the MAPPING + parsers from diff_letools.py (sibling file)
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from diff_letools import MAPPING, extract_output, parse_letools, num, find_root  # noqa

CLIP_INF = 10000.0  # cap inf %s so a single bad stat doesn't dominate Σ

def sigma_for_build(lua_path, json_path):
    leb = extract_output(lua_path)
    letools = parse_letools(json_path)
    sigma = 0.0
    max_pct = 0.0
    n_stats = 0
    n_diff = 0  # |Δ%| > 2.0
    for (tab, name), key in MAPPING.items():
        lt = num(letools.get(tab, {}).get(name))
        lv = leb.get(key)
        if lt is None or lv is None:
            continue
        n_stats += 1
        d = lv - lt
        if abs(lt) < 1e-9:
            pct = 0.0 if abs(d) < 1e-9 else CLIP_INF
        else:
            pct = abs(d) / abs(lt) * 100.0
            if pct > CLIP_INF:
                pct = CLIP_INF
        sigma += pct
        if pct > max_pct:
            max_pct = pct
        if pct > 2.0:
            n_diff += 1
    return sigma, max_pct, n_stats, n_diff

def list_builds(root):
    d = os.path.join(root, 'spec', 'TestBuilds', '1.4')
    builds = []
    for fn in sorted(os.listdir(d)):
        if not fn.endswith('.letools.json'):
            continue
        if '.blessings' in fn or '.recorded_tooltips' in fn:
            continue
        base = fn[:-len('.letools.json')]
        builds.append(base)
    return builds

def assign_groups(ranked):
    # ranked = [(build, sigma, ...), ...] desc-sorted
    # 119 builds → 20/20/20/20/20/19 split (top-heavier groups slightly larger)
    n = len(ranked)
    sizes = [20, 20, 20, 20, 20, max(0, n - 100)]
    if n <= 100:
        # fallback: equal-ish 6-split
        base = n // 6
        rem = n - base * 6
        sizes = [base + (1 if i < rem else 0) for i in range(6)]
    groups = OrderedDict()
    idx = 0
    for gi, sz in enumerate(sizes, start=1):
        gname = f'G{gi}'
        groups[gname] = []
        for _ in range(sz):
            if idx >= n: break
            groups[gname].append(ranked[idx])
            idx += 1
    return groups

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', default=None)
    ap.add_argument('--emit-json', action='store_true')
    ap.add_argument('--group', default=None, help='Print only this group (e.g. G2)')
    ap.add_argument('--include-missing-lua', action='store_true')
    args = ap.parse_args()

    root = args.root or find_root(HERE)
    if not root:
        print('ERROR: no spec/TestBuilds/1.4 dir', file=sys.stderr); sys.exit(2)
    d = os.path.join(root, 'spec', 'TestBuilds', '1.4')

    builds = list_builds(root)
    ranked = []
    missing_lua = []
    for base in builds:
        lua = os.path.join(d, base + '.lua')
        js = os.path.join(d, base + '.letools.json')
        if not os.path.isfile(lua):
            missing_lua.append(base)
            continue
        try:
            sigma, mx, ns, nd = sigma_for_build(lua, js)
        except Exception as e:
            print(f'WARN: {base}: {e}', file=sys.stderr); continue
        ranked.append((base, sigma, mx, ns, nd))

    ranked.sort(key=lambda r: -r[1])
    groups = assign_groups(ranked)

    if args.group:
        members = groups.get(args.group, [])
        for rank, (base, sigma, mx, ns, nd) in enumerate(members, start=1):
            global_rank = sum(len(groups[k]) for k in groups if k < args.group) + rank
            print(f'{global_rank:>3d}  {base:60s}  Σ={sigma:>10.1f}  max={mx:>8.1f}  stats={ns:>3d}  diff>2%={nd:>2d}')
        print(f'\n{args.group}: {len(members)} builds')
    else:
        for gname, members in groups.items():
            print(f'\n=== {gname} ({len(members)} builds) ===')
            for rank, (base, sigma, mx, ns, nd) in enumerate(members, start=1):
                global_rank = sum(len(groups[k]) for k in groups if k < gname) + rank
                print(f'{global_rank:>3d}  {base:60s}  Σ={sigma:>10.1f}  max={mx:>8.1f}  stats={ns:>3d}  diff>2%={nd:>2d}')
        print(f'\nTotal ranked: {len(ranked)} builds')
        if missing_lua:
            print(f'Missing .lua (excluded from ranking): {len(missing_lua)}')
            if args.include_missing_lua:
                for b in missing_lua:
                    print(f'  - {b}')

    if args.emit_json:
        tmp = os.path.join(root, '.tmp')
        os.makedirs(tmp, exist_ok=True)
        # sigma_ranking.json: flat ordered list
        rank_out = []
        for rank, (base, sigma, mx, ns, nd) in enumerate(ranked, start=1):
            rank_out.append({
                'rank': rank, 'build': base, 'sigma_abs_pct': round(sigma, 2),
                'max_abs_pct': round(mx, 2), 'mapped_stats': ns,
                'stats_over_2pct': nd,
            })
        with open(os.path.join(tmp, 'sigma_ranking.json'), 'w', encoding='utf-8') as f:
            json.dump({'generated_at': __import__('datetime').datetime.now().isoformat(),
                       'total': len(ranked), 'missing_lua': missing_lua,
                       'ranking': rank_out}, f, indent=2, ensure_ascii=False)
        # groups_by_sigma.json
        group_out = OrderedDict()
        for gname, members in groups.items():
            group_out[gname] = [{'rank': sum(len(groups[k]) for k in groups if k < gname) + i + 1,
                                 'build': base, 'sigma_abs_pct': round(sigma, 2)}
                                for i, (base, sigma, mx, ns, nd) in enumerate(members)]
        with open(os.path.join(tmp, 'groups_by_sigma.json'), 'w', encoding='utf-8') as f:
            json.dump({'generated_at': __import__('datetime').datetime.now().isoformat(),
                       'canonical_definition': 'Obsidian/Development/テストビルド G分類定義.md',
                       'split': [len(groups[k]) for k in groups],
                       'groups': group_out}, f, indent=2, ensure_ascii=False)
        print(f'\nWrote {tmp}/sigma_ranking.json and {tmp}/groups_by_sigma.json')

if __name__ == '__main__':
    main()
