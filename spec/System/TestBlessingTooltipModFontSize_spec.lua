-- @leb-regression-guard: blessing-tooltip-mod-font-size
-- Blessing hover tooltip modifier text uses the same 16px size as item
-- affix modifier lines, while the blessing title remains independently sized.

describe("BlessingTooltipModFontSize", function()
    it("renders blessing implicit mod lines at size 16", function()
        local path = "Classes/BlessingGridControl.lua"
        local file = io.open(path, "r") or io.open("src/" .. path, "r")
        local source
        assert.is_not_nil(file)
        source = file:read("*a")
        file:close()

        assert.is_truthy(source:find(
            'self.tooltip:AddLine(16, "^xCCCCCC" .. lineText)', 1, true))
    end)
end)
