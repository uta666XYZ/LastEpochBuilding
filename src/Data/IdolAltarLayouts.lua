-- Last Epoch Building
--
-- Data: Idol Altar Layouts (S4 / Shattered Omens)
--
-- グリッド仕様 (5×5):
--   0 = blocked    (使用不可セル)
--   1 = normal     (通常アイドルスロット)
--   2 = refracted  (紫スロット、S4新規 / Omen Idol用)
--
-- refractedRanks = { [row] = { [col] = rank } }
--   refracted セルの「活性化 rank」。game data の unlockMatrix は refracted を
--   `100 + rank` でエンコードする (IdolsContainerGridData: RefractedSlotIdJump=100,
--   MaxIdolSlotUnlockRewards=8; resources.assets IdolsContainerGridDataList
--   path_id 270533 の 2026-06-10 decode、13/13 altar が本ファイルの
--   blocked/refracted 配置と一致)。altar の unlock rank がその値に達するまで、
--   そのセルは refracted でなく NORMAL スロットとして振る舞う (StarSeaVnV
--   3-layer 照合: Ocular (5,1) rank1 = boost 適用 / (1,1) rank7 = 非適用)。
--   Config `idolAltarUnlockRank` (default 8 = 全活性) が gate を駆動。
--   mirrorOf 展開時は列反転 (c -> 6-c) で自動生成 (ItemsTab)。
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
-- 2026-05-03 に概念を分離し omenIdolCapacity に rename。全 altar の値は
-- in-game tooltip / LETools planner data で確認済（各 entry の inline
-- コメント参照）。

-- ────────────────────────────────────────────────────────────
-- ここにアルターを追加してください
-- ────────────────────────────────────────────────────────────
local layouts = {

    -- --------------------------------------------------------
    -- Lunar Altar  (非対称 → ミラーあり)
    -- --------------------------------------------------------
    ["Lunar Altar"] = {
        isMirrored   = false,
        -- refracted cell activation ranks (game data: unlockMatrix value - 100;
        -- cell acts as a NORMAL slot until the altar unlock rank reaches it)
        refractedRanks = { [3] = { [1] = 1, [2] = 2, [3] = 6 } },
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
        -- refracted cell activation ranks (game data: unlockMatrix value - 100;
        -- cell acts as a NORMAL slot until the altar unlock rank reaches it)
        refractedRanks = { [1] = { [3] = 6 }, [3] = { [1] = 7, [5] = 7 }, [4] = { [3] = 3 } },
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
        -- refracted cell activation ranks (game data: unlockMatrix value - 100;
        -- cell acts as a NORMAL slot until the altar unlock rank reaches it)
        refractedRanks = { [1] = { [1] = 3 }, [3] = { [3] = 1 }, [5] = { [5] = 3 } },
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
        -- refracted cell activation ranks (game data: unlockMatrix value - 100;
        -- cell acts as a NORMAL slot until the altar unlock rank reaches it)
        refractedRanks = { [1] = { [2] = 8 }, [3] = { [2] = 4, [4] = 5 }, [5] = { [4] = 1 } },
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
        -- refracted cell activation ranks (game data: unlockMatrix value - 100;
        -- cell acts as a NORMAL slot until the altar unlock rank reaches it)
        refractedRanks = { [2] = { [1] = 7, [2] = 4, [4] = 4, [5] = 7 } },
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
        -- refracted cell activation ranks (game data: unlockMatrix value - 100;
        -- cell acts as a NORMAL slot until the altar unlock rank reaches it)
        refractedRanks = { [3] = { [2] = 3, [4] = 3 } },
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
        -- refracted cell activation ranks (game data: unlockMatrix value - 100;
        -- cell acts as a NORMAL slot until the altar unlock rank reaches it)
        refractedRanks = { [1] = { [1] = 7, [5] = 5 }, [5] = { [1] = 1, [5] = 3 } },
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
    -- Archaic Altar  (対称レイアウト)
    -- --------------------------------------------------------
    ["Archaic Altar"] = {
        isMirrored   = false,
        -- refracted cell activation ranks (game data: unlockMatrix value - 100;
        -- cell acts as a NORMAL slot until the altar unlock rank reaches it)
        refractedRanks = { [1] = { [3] = 8 }, [5] = { [3] = 1 } },
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
        -- refracted cell activation ranks (game data: unlockMatrix value - 100;
        -- cell acts as a NORMAL slot until the altar unlock rank reaches it)
        refractedRanks = { [3] = { [3] = 1 } },
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
        -- refracted cell activation ranks (game data: unlockMatrix value - 100;
        -- cell acts as a NORMAL slot until the altar unlock rank reaches it)
        refractedRanks = { [3] = { [2] = 2, [3] = 3, [4] = 3 }, [4] = { [2] = 1, [3] = 8, [4] = 2 } },
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
        -- refracted cell activation ranks (game data: unlockMatrix value - 100;
        -- cell acts as a NORMAL slot until the altar unlock rank reaches it)
        refractedRanks = { [2] = { [1] = 5, [5] = 6 }, [4] = { [1] = 1, [5] = 3 } },
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
        -- refracted cell activation ranks (game data: unlockMatrix value - 100;
        -- cell acts as a NORMAL slot until the altar unlock rank reaches it)
        refractedRanks = { [2] = { [3] = 6 }, [3] = { [3] = 4 }, [4] = { [2] = 3, [4] = 3 }, [5] = { [1] = 2, [5] = 2 } },
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
        -- refracted cell activation ranks (game data: unlockMatrix value - 100;
        -- cell acts as a NORMAL slot until the altar unlock rank reaches it)
        refractedRanks = { [1] = { [3] = 4 }, [3] = { [3] = 1 }, [5] = { [3] = 4 } },
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
