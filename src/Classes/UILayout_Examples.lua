--[[
================================================================================
  UILayout 使用例 / Usage Examples
================================================================================

このファイルはUILayout.luaの使い方を説明します。
実際のプロジェクトでは、これらのコードをSkillsTab.luaなどに組み込んでください。

--]]

local UILayout = require("UILayout")

--[[
================================================================================
  基本的な使い方 / Basic Usage
================================================================================
--]]

-- 1. レイアウトを作成
local layout = UILayout.new({
    x = 200,           -- viewport X位置
    y = 50,            -- viewport Y位置
    width = 800,       -- viewport 幅
    height = 600,      -- viewport 高さ
    layoutType = UILayout.VERTICAL,  -- 縦並び
    padding = 10,      -- 内側の余白
    gap = 8            -- アイテム間の隙間
})

-- 2. アイテムを追加
layout:addItem({
    width = 300,
    height = 100,
    draw = function(x, y, w, h)
        -- ここで描画
        SetDrawColor(0.2, 0.2, 0.3)
        DrawImage(nil, x, y, w, h)
        SetDrawColor(1, 1, 1)
        DrawString(x + 10, y + 10, "LEFT", 14, "VAR", "Item 1")
    end
})

layout:addItem({
    width = 300,
    height = 150,
    draw = function(x, y, w, h)
        SetDrawColor(0.3, 0.2, 0.2)
        DrawImage(nil, x, y, w, h)
        SetDrawColor(1, 1, 1)
        DrawString(x + 10, y + 10, "LEFT", 14, "VAR", "Item 2")
    end
})

-- 3. 描画
function onDraw()
    layout:draw()
end

--[[
================================================================================
  スクロール / Scrolling
================================================================================
--]]

-- マウスホイールでスクロール
function onMouseWheel(delta)
    layout:scroll(-delta * 30)  -- 1スクロールで30px移動
end

-- スクロールが必要か確認
if layout:needsScroll() then
    -- スクロールバーを表示
end

--[[
================================================================================
  ヒット検出 / Hit Detection
================================================================================
--]]

function onMouseClick(mouseX, mouseY)
    local index, item = layout:getItemAt(mouseX, mouseY)
    if item then
        print("Clicked item " .. index)
    end
end

--[[
================================================================================
  ビューポートの自動サイズ調整 / Auto-resize Viewport
================================================================================
--]]

-- コンテンツに合わせてビューポートをリサイズ
layout:fitToContent()

-- 幅だけ調整
layout:fitWidthToContent()

-- 高さだけ調整
layout:fitHeightToContent()

--[[
================================================================================
  スキルツリー専用レイアウト / Skill Tree Layout
================================================================================

SkillsTab.luaで使う場合の例：

--]]

function SkillsTabClass:DrawSkillTrees(viewPort, inputEvents)
    -- スキルリストを作成
    local skills = {}
    for i = 1, 5 do
        local socketGroup = self.socketGroupList[i]
        if socketGroup and socketGroup.grantedEffect and socketGroup.grantedEffect.treeId then
            table.insert(skills, {
                index = i,
                name = socketGroup.grantedEffect.name,
                treeId = socketGroup.grantedEffect.treeId,
                level = self:GetSkillLevel(i),
                usedPoints = self:GetUsedSkillPoints(i)
            })
        end
    end
    
    -- レイアウトを作成（毎フレーム作り直すか、キャッシュする）
    if not self.skillTreeLayout then
        self.skillTreeLayout = UILayout.createSkillTreeLayout(
            viewPort,
            skills,
            function(treeViewport, index, skill)
                -- ツリーを描画
                self.skillTreeViewer.selectedSkillIndex = skill.index
                self.skillTreeViewer:Draw(self.build, treeViewport, inputEvents)
            end,
            {
                headerHeight = 36,
                treeHeight = 350,
                padding = 10,
                gap = 8
            }
        )
    end
    
    -- スクロール処理
    for _, event in ipairs(inputEvents) do
        if event.type == "KeyUp" then
            if event.key == "WHEELDOWN" then
                self.skillTreeLayout:scroll(50)
            elseif event.key == "WHEELUP" then
                self.skillTreeLayout:scroll(-50)
            end
        end
    end
    
    -- 描画
    self.skillTreeLayout:drawWithFrame(
        {0.05, 0.05, 0.06},  -- 背景色
        {0.2, 0.2, 0.25}     -- 枠色
    )
end

--[[
================================================================================
  横並びレイアウト / Horizontal Layout
================================================================================
--]]

local horizontalLayout = UILayout.new({
    x = 100,
    y = 100,
    width = 600,
    height = 100,
    layoutType = UILayout.HORIZONTAL,
    padding = 10,
    gap = 10
})

-- アイコンを並べる
for i = 1, 5 do
    horizontalLayout:addItem({
        width = 50,
        height = 50,
        data = { skillIndex = i },
        draw = function(x, y, w, h, data)
            SetDrawColor(0.1, 0.2, 0.3)
            DrawImage(nil, x, y, w, h)
            SetDrawColor(1, 1, 1)
            DrawString(x + w/2 - 5, y + h/2 - 8, "LEFT", 16, "VAR", tostring(data.skillIndex))
        end
    })
end

--[[
================================================================================
  レイアウトのネスト / Nested Layouts
================================================================================

複雑なUIには、レイアウトをネストできます：

    VerticalLayout (全体)
        ├── HorizontalLayout (スキルアイコン行)
        │   ├── アイコン1
        │   ├── アイコン2
        │   └── ...
        └── VerticalLayout (ツリーリスト)
            ├── ツリー1
            ├── ツリー2
            └── ...

--]]

local mainLayout = UILayout.new({
    x = 200,
    y = 50,
    width = 1000,
    height = 700,
    layoutType = UILayout.VERTICAL
})

-- 最初のアイテム: アイコン行
mainLayout:addItem({
    width = 980,
    height = 70,
    draw = function(x, y, w, h)
        -- アイコン行を描画
        local iconLayout = UILayout.new({
            x = x,
            y = y,
            width = w,
            height = h,
            layoutType = UILayout.HORIZONTAL,
            padding = 10,
            gap = 10
        })
        
        for i = 1, 5 do
            iconLayout:addItem({
                width = 50,
                height = 50,
                draw = function(ix, iy, iw, ih)
                    SetDrawColor(0.2, 0.3, 0.4)
                    DrawImage(nil, ix, iy, iw, ih)
                end
            })
        end
        
        iconLayout:draw()
    end
})

--[[
================================================================================
  パフォーマンスのヒント / Performance Tips
================================================================================

1. レイアウトは毎フレーム作り直さない
   → 変更があったときだけ作り直す
   
2. isVisible()を使って見えないアイテムは描画しない
   → UILayout:draw() は自動的にこれをやる
   
3. 大量のアイテムがある場合、仮想化を検討
   → 見えている範囲のアイテムだけを作成

--]]

--[[
================================================================================
  ChatGPTのアドバイスまとめ
================================================================================

問題: 画像がviewportの上にはみ出す
解決: 座標をviewport基準に変換
    local drawX = viewport.x + x
    local drawY = viewport.y + y

問題: viewportの外を描画してしまう
解決: クリッピング
    if drawY + h < viewport.y then return end
    if drawY > viewport.y + viewport.height then return end

問題: viewport幅が画像より大きい
解決: 画像サイズからviewportを計算
    viewport.width = imageWidth + padding * 2

UIの基本パターン:
    Vertical Layout   - 縦に積む
    Horizontal Layout - 横に並べる
    Grid Layout       - グリッド配置

ゲームUIで重要な3つ:
    1. Layout Engine（UI配置）
    2. Hit Detection（クリック判定）
    3. Scroll View（スクロール）

--]]
