# Last Epoch Building (LEB)

## 🌟 A Path of Building-style offline build planner for **Last Epoch**.

<table>
  <tr>
    <td><img src="./docs/passiveTrees.png" width="400"/></td>
    <td><img src="./docs/skillSelectionWindow.png" width="400"/></td>
  </tr>
  <tr>
    <td><img src="./docs/skillTree.png" width="400"/></td>
    <td><img src="./docs/itemsWindow_v0.13.0.png" width="400"/></td>
  </tr>
  <tr>
    <td><img src="./docs/craftUI_first_v0.13.0.png" width="400"/></td>
    <td><img src="./docs/craftUI_second_v.0.13.0.png" width="400"/></td>
  </tr>
  <tr>
    <td><img src="./docs/importScreen_v0.11.0.png" width="400"/></td>
  </tr>  
</table>

> Not affiliated with Eleventh Hour Games.
> This is a third-party tool. Any in-game issues are not the responsibility of EHG.

> **Forking LEB?** You're welcome to — the MIT license permits it.
> Please keep credit to LEB and its upstream ([PoB Community](https://github.com/PathOfBuildingCommunity/PathOfBuilding), [LastEpochPlanner](https://github.com/Musholic/LastEpochPlanner)) visible in your fork's README.

---

## 🤝 Support Development

If you'd like to support LEB's development:

💖 [GitHub Sponsors](https://github.com/sponsors/uta666XYZ) — monthly support
☕ [Buy Me a Coffee](https://buymeacoffee.com/yobk0831a) — one-time tip
🍵 [Ko-fi](https://ko-fi.com/lastepochbuilding) — one-time tip

The first few supporters will have their names hidden somewhere in LEB as easter eggs.
Since I have a limited number of good hiding spots in mind, I'll add names in supporter order as new spots come to me.

Feedback and bug reports are always welcome — see [Contributing](#contributing).

---

## ✨ Features

- **Passive tree** — all classes and masteries
- **Skill trees** — all skills with full node support
- **Equipment simulation** with crafting UI (left/right split layout, card browser)
- **DPS calculation** with ailments, debuffs, and corruption scaling
- **Defense stats** — armor, dodge, block, ward, resistances, endurance
- **Unique & Legendary items**
- **Set items** (Set bonus effect accuracy may vary — see Roadmap)
- **Idols** — Season 4 Idol Altar with crafting system (affix selection, class filtering, Weaver-specific affixes)
- **Blessings** — visual slot UI with icons and hover detail cards
- **Character import** — offline save files and online characters via Maxroll
- **Build sharing** — generate a short link or offline code to share your build
- **Node search** — Ctrl+F in passive tree, skill tree, and skill selection
- **Config tab** — smart buff suggestions when your build can grant Haste, Frenzy, etc.
- **Steps (Leveling Order)** — record the order in which you allocate passive and skill tree nodes, then toggle **All / Min** display to read back the leveling path (LEB-only feature; useful for build creators sharing leveling guides without writing them out in Notes)
- **Season 4: Shattered Omens** support

> **Note:** Mod recognition rate is 100% as of LEB v0.12.0. Recognized mods
> are not always calculated with full accuracy — calculator improvements are ongoing.
> See [docs/SKILL_STATUS.md](docs/SKILL_STATUS.md) for which skills have been
> verified against community reference builds and which still need validation.
> Development is focused on Last Epoch Season 4 (LE 1.4).
> Limited support exists for 1.2 and 1.3 builds.

---

## 🚀 Installation

LEB is distributed as a **portable zip — no installation required**.

1. Download `LastEpochBuilding-vX.X.X-win.zip` from the [Releases](../../releases) page
2. Extract the zip to any folder
3. Run **`runtime\Last Epoch Building.exe`**

> **Tip:** You can also double-click `Launch.bat` in the root folder as a shortcut.

User data (builds, settings) is stored alongside the executable, so keep all files in the same folder.

### 🐧 Running on Linux (via Wine)

LEB is currently distributed as a Windows build only. A native Linux build is **not** available, but LEB runs well on Linux through [Wine](https://www.winehq.org/) (community-tested; not officially supported).

1. Install Wine (e.g. `sudo apt install wine` on Debian/Ubuntu, `sudo pacman -S wine` on Arch)
2. Extract `LastEpochBuilding-vX.X.X-win.zip` to any folder
3. From the extracted folder, run:
   ```sh
   wine "runtime/Last Epoch Building.exe"
   ```

Tested with recent Wine versions; if you hit issues, please open an issue with your distro and Wine version. A native Linux/Web build is on the [Roadmap](#-roadmap).

---

## 🛠️ Roadmap

- Improve calculation accuracy across all stats and skills
- Auto-populate Config tab from equipped item affixes
  (passive/skill tree detection is live; item affix detection coming)
- Automatic or fast updates when Last Epoch patches release
- Improved support for legacy character import (1.2, 1.3)
- Web version

---

## 🤝 Contributing

Feedback, bug reports, and feature requests are always welcome!

Please see [CONTRIBUTING.md](CONTRIBUTING.md) for details on how to report bugs
and submit pull requests.

## 🛠️ Development Process

See [DEVELOPMENT.md](./DEVELOPMENT.md) for release cadence, testing, and development workflow details.

## 📖 Changelog

Full version history: [CHANGELOG.md](CHANGELOG.md)

## 📖 Credits

Based on [Path of Building Community](https://github.com/PathOfBuildingCommunity/PathOfBuilding),
originally forked from [Musholic/LastEpochPlanner](https://github.com/Musholic/LastEpochPlanner).

Development assisted by [Claude Code](https://claude.ai/code) (Anthropic).

## 💛 Special Thanks

### ☕ Supporters (Buy Me a Coffee)

| Supporter        | Note                                                     |
| ---------------- | -------------------------------------------------------- |
| 👑 WarMachine237 | First ever supporter — a permanent mark in LEB's history |

### 💬 Community Feedback

**v0.13**

- 🏆 **Test Build MVP — u/SottoSopra666** — one person, five builds; single-handedly broke the Blessing system, the Crit calc, and made me question every Resist value (see CHANGELOG for the full story)
- u/ratonbox, u/Bassndy, and u/Mr-Nabokov (thanks for sharing your builds)
- u/pro185, and u/MRosvall (thanks for contributing ideas for the Steps feature)
- u/berethon (thanks for contributing ideas for idol/blessing comparison feature)

---

## 📄 License

[MIT](LICENSE.md) — see LICENSE.md for third-party licenses.
