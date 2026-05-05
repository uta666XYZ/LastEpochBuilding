# Regression Guards Index

Living index of regression guards. Each entry pairs an inline
`@leb-regression-guard:<id>` source tag with a busted spec and a short
description of the invariant being protected. Add a new entry whenever a
fix is non-obvious enough that a bare commit message would not survive a
later refactor.

Recipe (3 layers):
1. **Inline tag** in source — `-- @leb-regression-guard:<id>` immediately
   above the function / block being protected.
2. **Busted spec** — at least one `it(...)` case under `spec/System/` that
   would fail if the invariant breaks. Cross-reference the same id in the
   spec file's header comment.
3. **This index** — the entry below ties the two together and records the
   why so the next reader doesn't need to dig through git history.

---

## stcdt-conversion-shapes

- **Source**: `src/Modules/CalcActiveSkill.lua` — `calcs.getActiveStcdtBits`
- **Mirror**: `src/Classes/SkillsTab.lua` — `GetDynamicDamageTypesByTreeId`
  (Scaling Tags side; same shape catalogue, different output target).
- **Spec**: `spec/System/TestStcdtParser_spec.lua`
- **What it protects**: the parser recognises every stat / description prose
  shape that introduces, redirects, or removes damage-type bits via skill
  tree allocation. Specifically:
  - **A1**: `<Src> -> <Dst> Damage`
  - **A2**: `<Src> Damage -> <Dst> Damage`
  - **A3**: `<Src> -> <Dst> Conversion` suffix
  - **A4**: bare `<Dst> Conversion`
  - **A5**: multi-source AND-join `<Src1> and <Src2> -> <Dst> Damage`
    (e.g. tree_3 svz81-23 Horrific Vessels)
  - **A6**: multi-source AND-join `... -> <Dst> Conversion` suffix
  - **A7**: `<Delivery> Base Damage -> <Dst>` (e.g. tree bg36nl-7 Pyre Golem)
  - **A8b**: bare `<Src> -> <Dst>` (no Damage suffix; e.g. fw3d-10)
  - **A12**: modifier-only `Increased <Src> Damage -> <Dst> Damage`
    (e.g. tree_3 ds4d3-32 Vile Ghast — promotes destination as scaling tag
    without removing source)
  - **A13**: `<X> -> Elemental Damage` is filtered out — Oil Coating /
    cstri-22 is a *buff modifier*, not a skill-damage conversion. The
    `dst:lower() == "elemental"` guard prevents it from polluting the
    damage-type bitmap (the Elemental aggregate has no own bit in this
    context).
  - **B1**: `Enables <Type> Nova` addition (e.g. en6 Elemental Nova).
  - **D-prose / source removal**: unconditional `<Skill> loses its {X} tag`
    in `node.description` triggers Q3=(a) full-conversion source removal.
    Conditional `if ...` lines (e.g. tree_0 sw1 Swipe, tree_4 srk21-25
    Shurikens) are skipped — partial-state aware removal is intentionally
    not handled here; the conditional `if ...` filter prevents false strips.
  - **Caller wiring**: `src/Modules/CalcSetup.lua` line ~1793 captures the
    `removedBits` second return value and applies it to `minionKW` via
    `bit.band(minionKW, bit.bnot(removedStcdt))` so post-conversion
    "+to <NewType> Skills" affixes match correctly while the stripped
    source no longer matches its own tag.
- **Why this needs a guard**: the parser is text-driven against a long tail
  of skill-tree nodes. Adding a new shape is easy; *removing* one
  accidentally during a refactor (e.g. consolidating the cascading
  `if not dst then` chain into a generic loop) silently regresses Minion
  Tags / Scaling Tags / `+to X Skills` affix matching for whichever
  skills depend on that shape. The spec keeps the catalogue runnable.
