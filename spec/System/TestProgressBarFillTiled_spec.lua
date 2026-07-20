-- @leb-regression-guard: progress-bar-fill-tiled-per-point
-- Drives TreeTab:Draw and counts how many times the `progress-fill` image is
-- drawn on the mastery skill-unlock bar. The fill must be tiled ONE copy per
-- allocated point (flip-book style), not a single image stretched across the
-- whole fill. So N points spent => N fill draws (capped at the bar's point
-- length). Reverting to the old single stretched DrawImage would draw it once.
--
-- busted insulates each spec file, so the app modules read the REAL global
-- table; getfenv(newBuild) is that table -- override DrawImage there so the
-- module's own draw calls route through the probe.

describe("ProgressBarFillTiled", function()
	before_each(function()
		newBuild()
	end)

	-- Force `masteryPointsSpent` (base-class tree, selMastery 0) to `points` by
	-- injecting one allocated base-class node, then return the number of times the
	-- progress-fill image is drawn by TreeTab:Draw.
	local function fillDrawsForPoints(points)
		local G = getfenv(newBuild)
		local spec = build.spec
		local cls = spec.curClassName
		local nodeId, node
		for id, n in pairs(spec.nodes) do
			if type(id) == "string" and id:match("^" .. cls)
				and n.type ~= "ClassStart" and n.type ~= "AscendClassStart" then
				nodeId, node = id, n
				break
			end
		end
		assert.is_not_nil(node, "no base-class node found to allocate")
		node.alloc = points
		node.mastery = 0
		spec.allocNodes[nodeId] = node

		local fillHandle = build.treeTab:GetSpriteHandle("progress-fill")
		assert.is_not_nil(fillHandle)

		local origDrawImage = G.DrawImage
		local count = 0
		G.DrawImage = function(handle, ...)
			if handle == fillHandle then count = count + 1 end
		end
		local ok, err = pcall(function()
			build.treeTab:Draw({ x = 0, y = 0, width = 1920, height = 1080 }, {})
		end)
		G.DrawImage = origDrawImage
		assert(ok, "treeTab:Draw errored: " .. tostring(err))
		return count
	end

	it("draws one fill image per allocated point (5 points => 5 fills, not 1)", function()
		assert.are.equal(5, fillDrawsForPoints(5))
	end)

	it("draws one fill image per allocated point (3 points => 3 fills)", function()
		assert.are.equal(3, fillDrawsForPoints(3))
	end)

	it("caps the tiled fills at the bar's point length (base class = 25)", function()
		-- 30 points spent, but the base-class bar only spans 25 points.
		assert.are.equal(25, fillDrawsForPoints(30))
	end)
end)
