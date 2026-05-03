-- Last Epoch Building
--
-- Data: Idol Altar Layouts (S4 / Shattered Omens)
--
-- グリッド仕様 (5×5):
--   0 = blocked    (使用不可セル)
--   1 = normal     (通常アイドルスロット)
--   2 = refracted  (紫スロット、S4新規 / Omen Idol用)
--
-- row順・col順、各 row は左→右 (列1〜5)
--
-- isMirrored        = true の場合、ドロップダウンに " (Mirrored)" が付く
-- mirrorOf          = "<altar name>" の場合、grid は指定アルターを左右反転して自動生成
-- omenIdolCapacity  = そのアルターが提供する Omen Idol スロット数のベース値。
--                     ゲーム内 tooltip ヘッダ「N Omen Idol capacity」の値。
--                     Refracted cell の数とは **別概念**。詳細:
--                     `Development/Idol Altar Concepts.md`
--
-- 旧名 `baseCapacity` は誤って refracted cell 数を入れていた。
-- 2026-05-03 に概念を分離し omenIdolCapacity に rename。
-- Ocular Altar 以外は未確認のため、各アルターの値は in-game tooltip
-- で要検証 (TODO コメント付き)。

-- ────────────────────────────────────────────────────────────
-- ここにアルターを追加してください
-- ────────────────────────────────────────────────────────────
local layouts = {

    -- --------------------------------------------------------
    -- Lunar Altar  (非対称 → ミラーあり)
    -- --------------------------------------------------------
    ["Lunar Altar"] = {
        isMirrored   = false,
        omenIdolCapacity = 1,  -- in-game tooltip 確認済 (2026-05-03)
        grid = {
            { 0, 1, 1, 1, 1 },  -- row 1
            { 1, 1, 1, 1, 0 },  -- row 2
            { 2, 2, 2, 0, 0 },  -- row 3
            { 1, 1, 1, 1, 0 },  -- row 4
            { 0, 1, 1, 1, 1 },  -- row 5
        },
    },
    ["Lunar Altar (Mirrored)"] = {
        mirrorOf     = "Lunar Altar",
        isMirrored   = true,
        omenIdolCapacity = 1,  -- in-game tooltip 確認済 (2026-05-03, mirror継承)
    },

    -- --------------------------------------------------------
    -- Skyward Altar  (対称レイアウト)
    -- --------------------------------------------------------
    ["Skyward Altar"] = {
        isMirrored   = false,
        omenIdolCapacity = 1,  -- in-game tooltip 確認済 (2026-05-03)
        grid = {
            { 0, 0, 2, 0, 0 },  -- row 1
            { 0, 1, 1, 1, 0 },  -- row 2
            { 2, 1, 1, 1, 2 },  -- row 3
            { 1, 1, 2, 1, 1 },  -- row 4
            { 1, 1, 0, 1, 1 },  -- row 5
        },
    },

    -- --------------------------------------------------------
    -- Spire Altar  (非対称 → ミラーあり)
    -- --------------------------------------------------------
    ["Spire Altar"] = {
        isMirrored   = false,
        omenIdolCapacity = 1,  -- in-game tooltip 確認済 (2026-05-03)
        grid = {
            { 2, 0, 0, 1, 1 },  -- row 1
            { 1, 1, 0, 1, 1 },  -- row 2
            { 1, 1, 2, 1, 1 },  -- row 3
            { 1, 1, 0, 1, 1 },  -- row 4
            { 1, 1, 0, 0, 2 },  -- row 5
        },
    },
    ["Spire Altar (Mirrored)"] = {
        mirrorOf     = "Spire Altar",
        isMirrored   = true,
        omenIdolCapacity = 1,  -- in-game tooltip 確認済 (2026-05-03, mirror継承)
    },

    -- --------------------------------------------------------
    -- Twisted Altar  (非対称 → ミラーあり)
    -- --------------------------------------------------------
    ["Twisted Altar"] = {
        isMirrored   = false,
        omenIdolCapacity = 1,  -- LETools planner data 確認済 (2026-05-03): 全アルター base=1
        grid = {
            { 0, 2, 1, 1, 1 },  -- row 1
            { 1, 1, 0, 0, 1 },  -- row 2
            { 1, 2, 0, 2, 1 },  -- row 3
            { 1, 0, 0, 1, 1 },  -- row 4
            { 1, 1, 1, 2, 0 },  -- row 5
        },
    },
    ["Twisted Altar (Mirrored)"] = {
        mirrorOf     = "Twisted Altar",
        isMirrored   = true,
        omenIdolCapacity = 1,  -- LETools planner data 確認済 (2026-05-03, mirror継承)
    },

    -- --------------------------------------------------------
    -- Visage Altar  (対称レイアウト)
    -- --------------------------------------------------------
    ["Visage Altar"] = {
        isMirrored   = false,
        omenIdolCapacity = 1,  -- in-game tooltip 確認済 (2026-05-03)
        grid = {
            { 0, 1, 1, 1, 0 },  -- row 1
            { 2, 2, 1, 2, 2 },  -- row 2
            { 1, 0, 1, 0, 1 },  -- row 3
            { 1, 1, 1, 1, 1 },  -- row 4
            { 0, 1, 1, 1, 0 },  -- row 5
        },
    },

    -- --------------------------------------------------------
    -- Carcinised Altar  (対称レイアウト)
    -- --------------------------------------------------------
    ["Carcinised Altar"] = {
        isMirrored   = false,
        omenIdolCapacity = 1,  -- LETools planner data 確認済 (2026-05-03): 全アルター base=1
        grid = {
            { 1, 1, 0, 1, 1 },  -- row 1
            { 1, 0, 0, 0, 1 },  -- row 2
            { 1, 2, 1, 2, 1 },  -- row 3
            { 0, 1, 1, 1, 0 },  -- row 4
            { 1, 1, 1, 1, 1 },  -- row 5
        },
    },

    -- --------------------------------------------------------
    -- Ocular Altar  (対称レイアウト)
    -- --------------------------------------------------------
    ["Ocular Altar"] = {
        isMirrored   = false,
        omenIdolCapacity = 1,  -- in-game tooltip 確認済 (2026-05-03)
        grid = {
            { 2, 1, 1, 1, 2 },  -- row 1
            { 1, 1, 0, 1, 1 },  -- row 2
            { 1, 0, 0, 0, 1 },  -- row 3
            { 1, 1, 0, 1, 1 },  -- row 4
            { 2, 1, 1, 1, 2 },  -- row 5
        },
    },

    -- --------------------------------------------------------
    -- Archair Altar  (対称レイアウト)
    -- --------------------------------------------------------
    ["Archair Altar"] = {
        isMirrored   = false,
        omenIdolCapacity = 1,  -- in-game tooltip 確認済 (2026-05-03, "Archaic Altar of Heresy")
        grid = {
            { 0, 1, 2, 1, 0 },  -- row 1
            { 1, 1, 1, 1, 1 },  -- row 2
            { 1, 1, 0, 1, 1 },  -- row 3
            { 1, 1, 1, 1, 1 },  -- row 4
            { 0, 1, 2, 1, 0 },  -- row 5
        },
    },

    -- --------------------------------------------------------
    -- Prophesied Altar  (対称レイアウト)
    -- --------------------------------------------------------
    ["Prophesied Altar"] = {
        isMirrored   = false,
        omenIdolCapacity = 1,  -- in-game tooltip 確認済 (2026-05-03)
        grid = {
            { 0, 1, 1, 1, 0 },  -- row 1
            { 1, 1, 1, 1, 1 },  -- row 2
            { 1, 1, 2, 1, 1 },  -- row 3
            { 1, 1, 1, 1, 1 },  -- row 4
            { 0, 1, 1, 1, 0 },  -- row 5
        },
    },

    -- --------------------------------------------------------
    -- Impervious Altar  (対称レイアウト)
    -- --------------------------------------------------------
    ["Impervious Altar"] = {
        isMirrored   = false,
        omenIdolCapacity = 1,  -- LETools planner data 確認済 (2026-05-03)
        grid = {
            { 0, 1, 1, 1, 0 },  -- row 1
            { 0, 1, 0, 1, 0 },  -- row 2
            { 1, 2, 2, 2, 1 },  -- row 3
            { 1, 2, 2, 2, 1 },  -- row 4
            { 1, 1, 1, 1, 1 },  -- row 5
        },
    },

    -- --------------------------------------------------------
    -- Jagged Altar  (対称レイアウト)
    -- --------------------------------------------------------
    ["Jagged Altar"] = {
        isMirrored   = false,
        omenIdolCapacity = 1,  -- in-game tooltip 確認済 (2026-05-03)
        grid = {
            { 0, 1, 1, 1, 0 },  -- row 1
            { 2, 1, 1, 1, 2 },  -- row 2
            { 0, 1, 1, 1, 0 },  -- row 3
            { 2, 1, 1, 1, 2 },  -- row 4
            { 0, 1, 1, 1, 0 },  -- row 5
        },
    },

    -- --------------------------------------------------------
    -- Pyramidal Altar  (対称レイアウト)
    -- --------------------------------------------------------
    ["Pyramidal Altar"] = {
        isMirrored   = false,
        omenIdolCapacity = 1,  -- LETools planner data 確認済 (2026-05-03)
        grid = {
            { 0, 0, 1, 0, 0 },  -- row 1
            { 0, 1, 2, 1, 0 },  -- row 2
            { 1, 1, 2, 1, 1 },  -- row 3
            { 1, 2, 1, 2, 1 },  -- row 4
            { 2, 1, 1, 1, 2 },  -- row 5
        },
    },

    -- --------------------------------------------------------
    -- Auric Altar  (対称レイアウト)
    -- --------------------------------------------------------
    ["Auric Altar"] = {
        isMirrored   = false,
        omenIdolCapacity = 1,  -- LETools planner data 確認済 (2026-05-03)
        grid = {
            { 1, 1, 2, 1, 1 },  -- row 1
            { 1, 1, 0, 1, 1 },  -- row 2
            { 0, 1, 2, 1, 0 },  -- row 3
            { 1, 1, 0, 1, 1 },  -- row 4
            { 1, 1, 2, 1, 1 },  -- row 5
        },
    },
}

return layouts
