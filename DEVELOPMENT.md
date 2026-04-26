# LEB Development Notes

I'm a Japanese solo developer in New Zealand building LEB (Last Epoch Building) —
a Path of Building inspired build planner for Last Epoch.
This document describes how development actually happens, for anyone curious
about the workflow behind weekly releases.

## Release Cadence

LEB ships a new version roughly every week. Each release includes:

- Calculation improvements based on test build verification
- Community-requested features (see Special Thanks in every changelog)
- Bug fixes triaged from Reddit, GitHub Issues, and Discord

Why weekly? Two reasons: it keeps scope tight (anything too big splits across
releases), and it keeps trust high — slow releases are how forks die.

## Community → Roadmap

Most features in LEB started as a Reddit comment or a Discord ping.

The pipeline is simple:

1. Users comment on release posts, file issues, or share builds
2. I read and upvote every comment, and reply to most
3. Common requests get tracked in a public roadmap
4. When a feature ships, the requester is credited in Special Thanks

If you've shared a build with me for testing, or suggested a feature that
got implemented, your name is in the release notes. The first few supporters
also have their names hidden somewhere inside LEB as easter eggs.

## Testing & Quality

Calculation correctness is the whole game. A build planner that lies to you
is worthless. LEB's testing has three layers:

- **Unit tests** in `spec/` for core mechanics (damage, mods, ailments)
- **Test builds** in `spec/TestBuilds/` — real builds with known expected
  numbers, verified against in-game tooltips
- **Community testing** — users share their builds and report discrepancies,
  which become new test cases

Every calculation change goes through all three before shipping.

## Tools I Use

My setup is pragmatic — whatever compresses the time between "I see a problem"
and "it's tested and shipped":

- **Lua 5.1 / LuaJIT** via SimpleGraphic (inherited from Path of Building)
- **Git + worktrees** for parallel feature branches
- **Claude Code** as a pair programmer — helps with code completion, bug
  triage, and overnight test build analysis
- **Obsidian** for design notes and decision logs
- **PowerShell scripts** for release automation, data sync, and version bumps

On Claude Code specifically: every architectural decision, every shipped
commit, every "is this ready" call is mine. The AI accelerates the mechanical
parts — searching the codebase, drafting tests, cross-checking numbers across
dozens of test builds overnight — but the judgments are human. That's how
weekly releases are possible as a solo developer.

## What Only I Do

- Design decisions (what to build, what to cut)
- Architecture (how systems fit together)
- Release readiness (is this good enough to ship?)
- Community relationships (replying, crediting, listening)
- Roadmap priorities
- Final review on every commit

## How to Contribute

You don't need to code to help LEB get better:

- **Share a build** — especially edge cases that break the calculator
- **Report a discrepancy** — "in-game says X, LEB says Y" with a screenshot
- **Suggest a feature** — Reddit, GitHub Issues, or Discord all work
- **Test a release candidate** — pre-release builds get posted before stable

Code contributions are welcome via pull request, but the highest-leverage
help is build sharing and calculation verification.

## Support

LEB is free and open source. If it helped plan your build and you want to
support continued development:

- 💖 [GitHub Sponsors](https://github.com/sponsors/uta666XYZ) — monthly support
- ☕ [Buy Me a Coffee](https://buymeacoffee.com/yobk0831a) — one-time tip
- 🍵 [Ko-fi](https://ko-fi.com/lastepochbuilding) — one-time tip

Goal: cover dev subscription costs so weekly releases keep coming.
No pressure — LEB stays free either way.

---

Thanks for reading. If you have questions about any of this, the best place
to ask is the release thread on r/LastEpoch or the LEB GitHub Issues.
