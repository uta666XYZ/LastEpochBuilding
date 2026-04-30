-- One-off: parse minion-bleed affix lines and print mod structure
local testLines = {
    "+43% Chance to inflict Bleed on Hit",
    "+43% Chance to inflict Bleed on Minion Hit",
    "+112% Chance to inflict Bleed on Minion Hit",
    "+45% Chance to inflict Bleed on Hit",
    "+45% Chance to inflict Bleed on Minion Hit",
    "+127% Chance to inflict Bleed on Minion Hit",
    "100% Increased Bleed Duration for Minions",
    "+84% Physical Penetration with Bleed for Minions",
    "+84% Physical Penetration for Bleed inflicted by Minions",
}
local function dumpMod(prefix, m)
    if type(m) ~= "table" then
        print(prefix .. tostring(m))
        return
    end
    local tagInfo = ""
    for ti = 1, #m do
        local t = m[ti]
        if type(t) == "table" then
            tagInfo = tagInfo .. " ["..(t.type or "?")
            for k, v in pairs(t) do
                if k ~= "type" then tagInfo = tagInfo .. " "..k.."="..tostring(v) end
            end
            tagInfo = tagInfo .. "]"
        end
    end
    print(string.format("%sname=%s type=%s value=%s flags=%s kw=%s tags=%s",
        prefix, tostring(m.name), tostring(m.type), tostring(m.value),
        tostring(m.flags or 0), tostring(m.keywordFlags or 0), tagInfo))
    if m.name == "MinionModifier" and type(m.value) == "table" and m.value.mod then
        dumpMod(prefix .. "    inner: ", m.value.mod)
    end
end
for _, line in ipairs(testLines) do
    print("=== " .. line .. " ===")
    local mods, extra = modLib.parseMod(line)
    if mods and #mods > 0 then
        for i, m in ipairs(mods) do
            dumpMod("  ["..i.."] ", m)
        end
    else
        print("  (no mods, extra=" .. tostring(extra) .. ")")
    end
end
