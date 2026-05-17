-- Debug: trace applyRange + parseMod for various Minion All Resist scenarios.
local itemLib = _G.itemLib
local modLib  = _G.modLib

local cases = {
    { line = "+5% Minion All Resistances",          range = 127.5, scalar = 0.17 },
    { line = "+5% Minion All Resistances",          range = 127.5, scalar = 0.95 },
    { line = "+5% Minion All Resistances",          range = 127.5, scalar = 5.882 },
    { line = "+1% Minion All Resistances",          range = 127.5, scalar = 5.882 },
    { line = "+5% Minion All Resistances",          range = 127.5, scalar = 0.67 },
}

for _, c in ipairs(cases) do
    local out = itemLib.applyRange(c.line, c.range, c.scalar, nil, nil, nil)
    print(string.format("INPUT:  line=%q  range=%s  scalar=%s", c.line, tostring(c.range), tostring(c.scalar)))
    print(string.format("OUT:    %q", out))
    local modList, extra = modLib.parseMod(out)
    if modList then
        for i, m in ipairs(modList) do
            print(string.format("  mod[%d] name=%s type=%s value=%s",
                i, tostring(m.name), tostring(m.type), tostring(m.value)))
            if m.value and type(m.value) == "table" and m.value.mod then
                local im = m.value.mod
                print(string.format("    inner.name=%s inner.type=%s inner.value=%s",
                    tostring(im.name), tostring(im.type), tostring(im.value)))
            end
        end
    else
        print("  parseMod returned nil")
    end
    print("---")
end
