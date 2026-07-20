-- Last Epoch Building
--
-- Class: Support Button Control
-- Frameless image button used for the "Support LEB" (Buy Me a Coffee) link.
-- Unlike ButtonControl it draws only the image (no border box) so branded
-- button art such as the Buy Me a Coffee pill renders cleanly.
--
local SupportButtonClass = newClass("SupportButtonControl", "Control", "TooltipHost", function(self, anchor, x, y, width, height, imagePath, onClick, tooltipText)
	self.Control(anchor, x, y, width, height)
	self.TooltipHost(tooltipText)
	self.onClick = onClick
	if imagePath then
		self.image = NewImageHandle()
		self.image:Load(imagePath, "ASYNC")
	end
end)

function SupportButtonClass:IsMouseOver()
	if not self:IsShown() then
		return false
	end
	return self:IsMouseInBounds()
end

function SupportButtonClass:Draw(viewPort, noTooltip)
	local x, y = self:GetPos()
	local width, height = self:GetSize()
	local enabled = self:IsEnabled()
	local mOver = self:IsMouseOver()
	if self.image and self.image:IsValid() then
		if not enabled then
			SetDrawColor(0.4, 0.4, 0.4)
		elseif self.clicked and mOver then
			SetDrawColor(0.7, 0.7, 0.7)
		elseif mOver then
			SetDrawColor(1, 1, 1)
		else
			-- Slightly dimmed at rest so hover reads as a highlight.
			SetDrawColor(0.85, 0.85, 0.85)
		end
		DrawImage(self.image, x, y, width, height)
	end
	if mOver then
		if not noTooltip then
			SetDrawLayer(nil, 100)
			self:DrawTooltip(x, y, width, height, viewPort)
			SetDrawLayer(nil, 0)
		end
	end
end

function SupportButtonClass:OnKeyDown(key)
	if not self:IsShown() or not self:IsEnabled() then
		return
	end
	if key == "LEFTBUTTON" then
		self.clicked = true
	end
	return self
end

function SupportButtonClass:OnKeyUp(key)
	if not self:IsShown() or not self:IsEnabled() then
		return
	end
	if key == "LEFTBUTTON" and self.clicked then
		self.clicked = false
		if self:IsMouseOver() and self.onClick then
			return self.onClick()
		end
	end
	self.clicked = false
end
