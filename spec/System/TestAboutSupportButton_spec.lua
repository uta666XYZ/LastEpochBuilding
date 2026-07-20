-- @leb-regression-guard: about-support-button-wired
-- Locks the "Support LEB" (Buy Me a Coffee) button in the About popup: a
-- frameless SupportButtonControl that draws only its image and, on a
-- left-button release while moused over, opens the Buy Me a Coffee page.
-- The About popup must keep wiring controls.support to that class, pointed at
-- the shipped Assets/support-leb.png asset and the buymeacoffee.com/yobk0831a
-- URL. Removing the wiring, or breaking the asset path or URL, silently drops
-- the only in-app support link.
--
-- See REGRESSION_GUARDS.md "about-support-button-wired".

describe("AboutSupportButton", function()
	local function readFile(path)
		local f = io.open(path, "r")
		if not f then return nil end
		local s = f:read("*a")
		f:close()
		return s
	end

	-- ===== Behavioral: the frameless image button contract =====
	describe("SupportButtonControl (behavior)", function()
		local function makeButton(onClick)
			return new("SupportButtonControl", nil, 0, 0, 140, 46, "Assets/support-leb.png", onClick or function() end, "tip")
		end

		it("fires onClick on left-button release while moused over", function()
			local fired = 0
			local btn = makeButton(function() fired = fired + 1 end)
			btn.IsMouseOver = function() return true end
			assert.are.equal(btn, btn:OnKeyDown("LEFTBUTTON"))
			assert.is_true(btn.clicked)
			btn:OnKeyUp("LEFTBUTTON")
			assert.are.equal(1, fired)
			assert.is_falsy(btn.clicked)
		end)

		it("does not fire onClick on release without a preceding press", function()
			local fired = 0
			local btn = makeButton(function() fired = fired + 1 end)
			btn.IsMouseOver = function() return true end
			btn:OnKeyUp("LEFTBUTTON")
			assert.are.equal(0, fired)
		end)

		it("does not fire onClick when the release happens off the button", function()
			local fired = 0
			local btn = makeButton(function() fired = fired + 1 end)
			btn.IsMouseOver = function() return false end
			btn:OnKeyDown("LEFTBUTTON")
			btn:OnKeyUp("LEFTBUTTON")
			assert.are.equal(0, fired)
		end)

		it("draws without error", function()
			local btn = makeButton()
			btn.IsMouseOver = function() return false end
			assert.has_no.errors(function()
				btn:Draw({ x = 0, y = 0, width = 800, height = 600 })
			end)
		end)
	end)

	-- ===== Structural: the About popup keeps the button wired =====
	describe("About popup wiring (source)", function()
		local src = readFile("Modules/Main.lua")

		it("has Main.lua source available", function()
			assert.is_not_nil(src, "src/Modules/Main.lua must be readable")
		end)

		it("wires the support button into the About popup", function()
			assert.is_not_nil(src:match('controls%.support%s*=%s*new%("SupportButtonControl"'),
				"About popup must create controls.support as a SupportButtonControl")
		end)

		it("points the support button at the shipped asset", function()
			assert.is_not_nil(src:match('Assets/support%-leb%.png'),
				"support button must reference Assets/support-leb.png")
		end)

		it("opens the Buy Me a Coffee page on click", function()
			assert.is_not_nil(src:match('buymeacoffee%.com/yobk0831a'),
				"support button must OpenURL the Buy Me a Coffee page")
		end)
	end)
end)
