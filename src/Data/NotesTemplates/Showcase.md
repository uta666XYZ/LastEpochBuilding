# LEB Markdown - Feature Showcase

```
db       .d8b.  .d8888. d888888b      d88888b d8888b.  .d88b.   .o88b. db   db      d8888b. db    db d888888b db      d8888b. d888888b d8b   db  d888b
88      d8' `8b 88'  YP `~~88~~'      88'     88  `8D .8P  Y8. d8P  Y8 88   88      88  `8D 88    88   `88'   88      88  `8D   `88'   888o  88 88' Y8b
88      88ooo88 `8bo.      88         88ooooo 88oodD' 88    88 8P      88ooo88      88oooY' 88    88    88    88      88   88    88    88V8o 88 88
88      88~~~88   `Y8b.    88         88~~~~~ 88~~~   88    88 8b      88~~~88      88~~~b. 88    88    88    88      88   88    88    88 V8o88 88  ooo
88booo. 88   88 db   8D    88         88.     88      `8b  d8' Y8b  d8 88   88      88   8D 88b  d88   .88.   88booo. 88  .8D   .88.   88  V888 88. ~8~
Y88888P YP   YP `8888Y'    YP         Y88888P 88       `Y88P'   `Y88P' YP   YP      Y8888P' ~Y8888P' Y888888P Y88888P Y8888D' Y888888P VP   V8P  Y888P
```

![Pointing](Data/NotesImages/Pointing.jpg)

> ^xE8C871**LEB Markdown** ^7- everything the Notes renderer can do, in one page.
> Open this in **Preview** mode (and also try toggling **Show Color Codes**) to see each feature side by side.

[[TOC]]

---

## 1. Headings

# H1 - largest, bold white

## H2 - section level

### H3 - subsection level

Use `#` / `##` / `###` at line start. Anything deeper (`####`) is rendered as plain text.

## 2. Inline emphasis

- **bold text** with `**bold**`
- _italic text_ with `*italic*` (rendered as a soft tint - the bitmap font has no italic glyphs)
- `inline code` with backticks - subtle background highlight

You can mix them: a sentence with **bold**, _italic_, and `code()` all together.

## 3. Lists

Bullet list (`-` or `*`):

- First item
- Second item with **bold** and a [link to Last Epoch](https://lastepoch.com)
- Third item

Numbered list:

1. Step one
2. Step two
3. Step three

## 4. Tables

Pipe-separated tables with header row and separator:

| Slot   | Affix Priority           | Source       |
| ------ | ------------------------ | ------------ |
| Helm   | Health, Resists          | CoF / Bazaar |
| Body   | Endurance, Health        | Monolith     |
| Weapon | Crit Multi, Added Damage | Crafted      |

Cell content supports **bold** and `code` inline.

## 5. Blockquotes

> Single-line blockquote with a vertical bar on the left.

> Multi-line blockquote.
> Each line keeps its own `>` prefix.
>
> Blank `>` lines insert paragraph breaks inside the quote.

## 6. Code blocks

Fenced with triple backticks. Renders monospace with a dark background:

```

function NotesTabClass:OpenSaveTemplatePopup()
local body = self.controls.edit.buf or ""
main:OpenPopup(420, 155, "Save as Template", controls)
end

```

```

# A second block - language tag is ignored, content rendered as-is

SELECT \* FROM uniques WHERE class = 'Sentinel';

```

## 7. Links

- External URL: [Last Epoch Tools](https://www.lastepochtools.com/)
- Anchor jump: [Skip to Color Codes](#9-color-codes) - clicks scroll the preview to that heading
- **Loadout switch** (Tree+Items+Skills+Config): [[Loadout: Endgame]]
- **Tree spec switch** only: [[Tree: Campaign]]

> Loadout / Tree links require an existing entry of the same name. They render in green / gold respectively.

## 8. Images

Embedded images are downloaded once, cached on disk, and auto-resized (Word-style cap):

![Last Epoch Logo](https://www.lastepochtools.com/img/le-logo.png)

Use `![alt](https://...)` - any of png / jpg / gif / bmp / tga.

## 9. Color Codes

LEB passes Path-of-Building style color codes straight through:

- ^xFF6B6BHex codes^7 with `^xRRGGBB` reset to `^7` (default)
- Preset palette: ^11red^7 ^22green^7 ^33blue^7 ^44yellow^7 ^55purple^7 ^66aqua^7 ^77white^7 ^88grey^7 ^99orange^7
- Combine inside any block: a **^xE8C871gold bold word^7** in the middle of a sentence

Toggle **Show Color Codes** to see the raw `^x` markers and edit them.

## 10. Horizontal Rule

Three or more dashes on their own line render a divider:

---

(That's a horizontal rule above this paragraph.)

## 11. Loadouts and Trees - quick reference

Common pattern for a build guide:

- **Budget** -> [[Loadout: Budget]]
- **Standard** -> [[Loadout: Standard]]
- **Endgame** -> [[Loadout: Endgame]]

Per-phase tree only (without changing items / skills):

- **Phase 1 (Campaign)** -> [[Tree: Campaign]]
- **Phase 2 (Lvl 80)** -> [[Tree: Lvl80]]
- **Phase 3 (Empowered)** -> [[Tree: Empowered]]

## 12. Combination test

A single paragraph using **bold**, _italic_, `code`, [link](https://lastepoch.com), [[Loadout: Endgame]], [[Tree: Campaign]], ^xFF6B6Bcolor^7, and a footnote-style [jump to top](#leb-markdown-feature-showcase) all in one line.

---

## FAQ

**Q: My color codes show as raw text**
A: Toggle **Show Color Codes** off, or make sure you're in **Preview** mode.

**Q: An image won't load**
A: Check `Data/NotesImageCache/` - LEB may have failed to download it. Re-open the file or check the URL extension (png / jpg / gif / bmp / tga only).

**Q: My Loadout / Tree link does nothing**
A: The target name must match an existing Loadout (or passive tree spec) exactly. Create it first via the Loadouts dropdown / Tree tab.

```

---

(c).-.(c) (c).-.(c) (c).-.(c) (c).-.(c) (c).-.(c) (c).-.(c) (c).-.(c) (c).-.(c) (c).-.(c) (c).-.(c) (c).-.(c) (c).-.(c) (c).-.(c) (c).-.(c) (c).-.(c) (c).-.(c) (c).-.(c)
/ ._. \ / ._. \ / ._. \ / ._. \ / ._. \ / ._. \ / ._. \ / ._. \ / ._. \ / ._. \ / ._. \ / ._. \ / ._. \ / ._. \ / ._. \ / ._. \ / ._. \
 **\( Y )/** **\( Y )/** **\( Y )/** **\( Y )/** **\( Y )/** **\( Y )/** **\( Y )/** **\( Y )/** **\( Y )/** **\( Y )/** **\( Y )/** **\( Y )/** **\( Y )/** **\( Y )/** **\( Y )/** **\( Y )/** **\( Y )/**
(_.-/'-'\-._)(_.-/'-'\-._)(_.-/'-'\-._)(_.-/'-'\-._) (_.-/'-'\-._)(_.-/'-'\-._)(_.-/'-'\-._)(_.-/'-'\-._)(_.-/'-'\-._) (_.-/'-'\-._)(_.-/'-'\-._)(_.-/'-'\-._)(_.-/'-'\-._)(_.-/'-'\-._)(_.-/'-'\-._)(_.-/'-'\-._)(_.-/'-'\-._)
|| L || || A || || S || || T || || E || || P || || O || || C || || H || || B || || U || || I || || L || || D || || I || || N || || G ||
_.' `-' '._  _.' `-' '.\_ _.' `-' '._ _.' `-' '._ _.' `-' '._ _.' `-' '._ _.' `-' '._ _.' `-' '._ _.' `-' '._ _.' `-' '._ _.' `-' '._ _.' `-' '._ _.' `-' '._ _.' `-' '._ _.' `-' '._ _.' `-' '._ _.' `-' '._
(.-./`-'\.-.)(.-./`-'\.-.)(.-./`-`\.-.)(.-./`-'\.-.) (.-./`-'\.-.)(.-./`-'\.-.)(.-./`-'\.-.)(.-./`-'\.-.)(.-./`-'\.-.) (.-./`-'\.-.)(.-./`-'\.-.)(.-./`-'\.-.)(.-./`-'\.-.)(.-./`-'\.-.)(.-./`-'\.-.)(.-./`-'\.-.)(.-./`-'\.-.)
`-'     `-' `-'     `-' `-'     `-' `-'     `-' `-'     `-' `-'     `-' `-'     `-' `-'     `-' `-'     `-' `-'     `-' `-'     `-' `-'     `-' `-'     `-' `-'     `-' `-'     `-' `-'     `-' `-'     `-'

```

## References

- [Markdown Help (`?` button next to template dropdown)](https://daringfireball.net/projects/markdown/)
- [ASCII Arts were generated in patorjk.com](https://patorjk.com)

```

```
