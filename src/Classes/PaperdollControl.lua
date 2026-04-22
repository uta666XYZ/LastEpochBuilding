-- Last Epoch Building
-- Class: PaperdollControl
-- Draws an equipment paperdoll in ItemsTab below the Craft/Create buttons.
-- Clicking a slot opens CraftItem() for that slot type.

local m_floor = math.floor
local m_min   = math.min
local m_max   = math.max

-- Slot definitions: positions match LETools DOM layout (2026-04-18 analysis).
-- Panel width=288, total height=390. ghost: key into GHOST_SPRITES table.
local SLOT_DEFS = {
    -- row 1: head (center-left), amulet (top-right)
    { slot = "Helmet",     x = 113, y = 14,  w = 76,  h = 76,  ghost = "head"    },
    { slot = "Amulet",     x = 227, y = 29,  w = 46,  h = 46,  ghost = "neck"    },
    -- row 2: weapon (left), body (center), offhand (right)
    { slot = "Weapon 1",   x = 14,  y = 98,  w = 76,  h = 154, ghost = "weapon"  },
    { slot = "Body Armor", x = 98,  y = 98,  w = 106, h = 154, ghost = "body"    },
    { slot = "Weapon 2",   x = 212, y = 98,  w = 76,  h = 154, ghost = "offhand" },
    -- row 3: ring1 (left), belt (center), ring2 (right)
    { slot = "Ring 1",     x = 29,  y = 260, w = 46,  h = 46,  ghost = "finger"  },
    { slot = "Belt",       x = 98,  y = 260, w = 106, h = 46,  ghost = "waist"   },
    { slot = "Ring 2",     x = 227, y = 260, w = 46,  h = 46,  ghost = "finger"  },
    -- row 4: hands (left), feet (center), relic (right)
    { slot = "Gloves",     x = 14,  y = 314, w = 76,  h = 76,  ghost = "hands"   },
    { slot = "Boots",      x = 113, y = 314, w = 76,  h = 76,  ghost = "feet"    },
    { slot = "Relic",      x = 212, y = 314, w = 76,  h = 76,  ghost = "relic"   },
}

local GHOST_SPRITES = {
    head    = "Assets/paperdoll/Soul_Gambler_Helmets.png",
    body    = "Assets/paperdoll/Soul_Gambler_Body Armor.png",
    hands   = "Assets/paperdoll/Soul_Gambler_Gloves.png",
    feet    = "Assets/paperdoll/Soul_Gambler_Boots.png",
    finger  = "Assets/paperdoll/Soul_Gambler_Ring.png",
    neck    = "Assets/paperdoll/Soul_Gambler_Amulet.png",
    waist   = "Assets/paperdoll/Soul_Gambler_Belts.png",
    weapon  = "Assets/paperdoll/Soul_Gambler_1H Swords.png",
    offhand = "Assets/paperdoll/Soul_Gambler_Shield.png",
    relic   = "Assets/paperdoll/Soul_Gambler_Relic.png",
}

-- Weapon 2 ghost key: weapon types use "weapon" sprite, off-hand uses "offhand"
local WEAPON2_OFFHAND_TYPES = { ["Shield"] = true, ["Quiver"] = true, ["Off-Hand Catalyst"] = true }

local function getGhostKey(def, itemsTab)
    if def.slot ~= "Weapon 2" then return def.ghost end
    local slot = itemsTab.slots and itemsTab.slots["Weapon 2"]
    if not slot then return def.ghost end
    local item = itemsTab.items and itemsTab.items[slot.selItemId]
    if item and item.type and not WEAPON2_OFFHAND_TYPES[item.type] and item.base and item.base.weapon then
        return "weapon"
    end
    return "offhand"
end

local PANEL_W   = 288
local TITLE_H   = 22  -- title bar height
local PANEL_H   = 390 + TITLE_H
-- Craft section extends the drawn bg below the paperdoll's anchor area so the
-- dark panel visually wraps the 3 craft shortcut buttons (Idol / Idol Altar /
-- Blessing) that ItemsTab anchors to paperdoll BOTTOMLEFT.
-- Buttons: 48 tall, anchored +8 below the paperdoll, so bg extends 8+48+8=64px.
local CRAFT_SECTION_EXTRA_H = 64
local PAD       = 4   -- slot inner padding for ghost sprite

-- Slot border colours (dark brownish, like in-game equipment panel)
local BORDER_R, BORDER_G, BORDER_B = 0.48, 0.42, 0.32
local FILL_R,   FILL_G,   FILL_B   = 0.02, 0.02, 0.03
local HOV_BORDER_R, HOV_BORDER_G, HOV_BORDER_B = 0.88, 0.72, 0.28
local BG_R,     BG_G,     BG_B     = 0.05, 0.05, 0.07

local PaperdollControlClass = newClass("PaperdollControl", "Control", "TooltipHost",
    function(self, anchor, x, y, itemsTab)
        self.Control(anchor, x, y, PANEL_W, PANEL_H)
        self.TooltipHost()
        self.itemsTab   = itemsTab
        self.imgHandles = {}

        -- Preload ghost sprites
        for key, path in pairs(GHOST_SPRITES) do
            local h = NewImageHandle()
            h:Load(path, "ASYNC")
            self.imgHandles[key] = h
        end
    end
)

function PaperdollControlClass:IsMouseOver()
    if not self:IsShown() then return false end
    return self:IsMouseInBounds()
end

function PaperdollControlClass:GetHoveredSlotDef()
    local cx, cy = self:GetPos()
    -- slots are offset by TITLE_H for the title bar
    local mx, my = GetCursorPos()
    for _, def in ipairs(SLOT_DEFS) do
        local sx = cx + def.x
        local sy = cy + TITLE_H + def.y
        if mx >= sx and mx < sx + def.w and my >= sy and my < sy + def.h then
            return def
        end
    end
    return nil
end

-- Draw a simple slot frame: filled rect + 1px border
local function drawSlotFrame(sx, sy, sw, sh, hov)
    -- Background fill
    SetDrawColor(FILL_R, FILL_G, FILL_B)
    DrawImage(nil, sx, sy, sw, sh)
    -- Border (1px each side via 4 thin rects)
    if hov then
        SetDrawColor(HOV_BORDER_R, HOV_BORDER_G, HOV_BORDER_B)
    else
        SetDrawColor(BORDER_R, BORDER_G, BORDER_B)
    end
    DrawImage(nil, sx,          sy,          sw, 1)        -- top
    DrawImage(nil, sx,          sy + sh - 1, sw, 1)        -- bottom
    DrawImage(nil, sx,          sy,          1,  sh)       -- left
    DrawImage(nil, sx + sw - 1, sy,          1,  sh)       -- right
end

-- Draw a "+" crosshair in the slot center
local function drawPlusMark(sx, sy, sw, sh, hov)
    local cx = sx + m_floor(sw / 2)
    local cy = sy + m_floor(sh / 2)
    local arm = m_min(8, m_floor(m_min(sw, sh) / 6))
    local th  = 1
    if hov then
        SetDrawColor(HOV_BORDER_R, HOV_BORDER_G, HOV_BORDER_B, 0.9)
    else
        SetDrawColor(BORDER_R, BORDER_G, BORDER_B, 0.8)
    end
    DrawImage(nil, cx - m_floor(th/2), cy - arm, th, arm * 2)
    DrawImage(nil, cx - arm, cy - m_floor(th/2), arm * 2, th)
end

function PaperdollControlClass:Draw(viewPort)
    local cx, cy = self:GetPos()

    -- Panel background. Extended beyond the control's own height to cover the
    -- craft shortcut buttons (Craft Idol / Idol Altar / Blessing) that
    -- ItemsTab anchors to paperdoll BOTTOMLEFT — together this forms the
    -- "craft section". ControlHost iterates children via pairs() (undefined
    -- order), so the extended bg is pushed to a lower draw layer to ensure
    -- the buttons render on top regardless of iteration order.
    SetDrawLayer(nil, -10)
    SetDrawColor(BG_R, BG_G, BG_B)
    DrawImage(nil, cx, cy, PANEL_W, PANEL_H + CRAFT_SECTION_EXTRA_H)
    SetDrawLayer(nil, 0)

    -- Title bar
    SetDrawColor(0.12, 0.11, 0.08)
    DrawImage(nil, cx, cy, PANEL_W, TITLE_H)
    SetDrawColor(BORDER_R, BORDER_G, BORDER_B)
    DrawImage(nil, cx, cy + TITLE_H - 1, PANEL_W, 2)
    SetDrawColor(1, 1, 1)
    DrawString(cx + m_floor(PANEL_W / 2), cy + m_floor((TITLE_H - 12) / 2),
        "CENTER_X", 12, "VAR", "^xD4BB88Crafting Items...")

    local hovDef = self:GetHoveredSlotDef()

    for _, def in ipairs(SLOT_DEFS) do
        local sx  = cx + def.x
        local sy  = cy + TITLE_H + def.y
        local hov = (hovDef and hovDef.slot == def.slot)

        drawSlotFrame(sx, sy, def.w, def.h, hov)

        -- Ghost sprite centered in slot (Weapon 2 switches based on equipped type)
        local ghostHandle = self.imgHandles[getGhostKey(def, self.itemsTab)]
        if ghostHandle and ghostHandle:IsValid() then
            local gw, gh = ghostHandle:ImageSize()
            if gw > 0 and gh > 0 then
                local maxW = def.w - PAD * 2
                local maxH = def.h - PAD * 2
                local scale = m_min(maxW / gw, maxH / gh)
                local dw = m_floor(gw * scale)
                local dh = m_floor(gh * scale)
                local ox = m_floor((def.w - dw) / 2)
                local oy = m_floor((def.h - dh) / 2)
                if hov then
                    SetDrawColor(1.0, 0.90, 0.65, 1.0)
                else
                    SetDrawColor(0.72, 0.72, 0.72, 0.90)
                end
                DrawImage(ghostHandle, sx + ox, sy + oy, dw, dh)
            end
        end

        drawPlusMark(sx, sy, def.w, def.h, hov)
    end

    -- Tooltip for the hovered slot: "Craft <Slot>..."
    if hovDef then
        local sx = cx + hovDef.x
        local sy = cy + TITLE_H + hovDef.y
        self.tooltipText = "Craft " .. hovDef.slot .. "..."
        self:DrawTooltip(sx, sy, hovDef.w, hovDef.h, viewPort)
    else
        self.tooltipText = nil
    end
end

function PaperdollControlClass:OnKeyDown(key)
    if not self:IsShown() then return end
    if key == "LEFTBUTTON" then
        local def = self:GetHoveredSlotDef()
        if def then
            self.itemsTab:CraftItem(nil, def.slot)
            return self
        end
    end
end

function PaperdollControlClass:OnKeyUp(key)
end
