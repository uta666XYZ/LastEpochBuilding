-- Last Epoch Building
--
-- Class: Label Control
-- Simple text label.
--
local m_max = math.max

local LabelClass = newClass("LabelControl", "Control", function(self, anchor, x, y, width, height, label)
	self.Control(anchor, x, y, width, height)
	self.label = label
	-- @leb-regression-guard: config-label-fit
	-- Multi-line label support (widest-line width + opt-in rightAlignLines Draw)
	-- lets the Config tab wrap long labels instead of overflowing the box.
	-- Test: spec/System/TestConfigLabelFit_spec.lua, TestConfigTabDrawSmoke_spec.lua
	self.width = function()
		local size = self:GetProperty("height")
		local text = self:GetProperty("label")
		if text and text:find("\n") then
			-- Multi-line label: width is the widest line, not the width of the
			-- whole newline-joined string (which would be meaningless and, for a
			-- right-anchored label, mis-position it far to the left).
			local maxW = 0
			for line in (text .. "\n"):gmatch("([^\n]*)\n") do
				maxW = m_max(maxW, DrawStringWidth(size, "VAR", line))
			end
			return maxW
		end
		return DrawStringWidth(size, "VAR", text)
	end
end)

function LabelClass:Draw()
	local x, y = self:GetPos()
	local size = self:GetProperty("height")
	local label = self:GetProperty("label") or ""
	if label:find("\n") then
		-- rightAlignLines (opt-in, set by callers such as the config tab) draws
		-- each wrapped line flush to the label's right edge, so a right-anchored
		-- multi-line label stays aligned with its control. Default is the
		-- historic left-aligned behaviour used by other multi-line labels.
		local rightX = self.rightAlignLines and (x + self:GetProperty("width")) or nil
		for line in (label .. "\n"):gmatch("([^\n]*)\n") do
			if rightX then
				DrawString(rightX, y, "RIGHT_X", size, "VAR", line)
			else
				DrawString(x, y, "LEFT", size, "VAR", line)
			end
			y = y + size + 2
		end
	else
		DrawString(x, y, "LEFT", size, "VAR", label)
	end
end