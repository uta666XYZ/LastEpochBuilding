-- Last Epoch Building
--
-- Class: Label Control
-- Simple text label.
--
local LabelClass = newClass("LabelControl", "Control", function(self, anchor, x, y, width, height, label)
	self.Control(anchor, x, y, width, height)
	self.label = label
	self.width = function()
		return DrawStringWidth(self:GetProperty("height"), "VAR", self:GetProperty("label"))
	end
end)

function LabelClass:Draw()
	local x, y = self:GetPos()
	local size = self:GetProperty("height")
	local label = self:GetProperty("label") or ""
	if label:find("\n") then
		for line in (label .. "\n"):gmatch("([^\n]*)\n") do
			DrawString(x, y, "LEFT", size, "VAR", line)
			y = y + size + 2
		end
	else
		DrawString(x, y, "LEFT", size, "VAR", label)
	end
end