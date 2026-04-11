-- Last Epoch Building
-- Module: Base85 encoding
-- Produces ~6% shorter output than base64.
-- Codes are prefixed with "!" to distinguish from base64.
--
-- Algorithm: 4 bytes -> 5 chars (vs base64's 3 bytes -> 4 chars)
-- Partial last group: n bytes -> n+1 chars (encode), n+1 chars -> n bytes (decode)

local b85chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!#$%-+;=?@^_,.:()/[]{}~'
-- 10 + 26 + 26 + 23 = 85 chars

local base85 = {}

-- Decode lookup table: char -> 0..84
local b85dec = {}
for i = 1, #b85chars do
    b85dec[b85chars:sub(i, i)] = i - 1
end

local floor = math.floor

-- Encode binary string to base85
function base85.encode(data)
    local out = {}
    local len = #data
    local i = 1
    while i <= len do
        local rem = len - i + 1
        -- Read up to 4 bytes; pad remainder with 0
        local n = data:byte(i) * 16777216
        if rem >= 2 then n = n + data:byte(i + 1) * 65536 end
        if rem >= 3 then n = n + data:byte(i + 2) * 256 end
        if rem >= 4 then n = n + data:byte(i + 3) end
        -- Convert 32-bit value to 5 base85 digits (big-endian)
        local c = { '', '', '', '', '' }
        for j = 5, 1, -1 do
            c[j] = b85chars:sub((n % 85) + 1, (n % 85) + 1)
            n = floor(n / 85)
        end
        -- For a partial last group of rem bytes, output only rem+1 chars
        local need = math.min(rem, 4) + 1
        for j = 1, need do
            out[#out + 1] = c[j]
        end
        i = i + 4
    end
    return table.concat(out)
end

-- Decode base85 string to binary
function base85.decode(data)
    local out = {}
    local len = #data
    local i = 1
    while i <= len do
        local rem = len - i + 1
        -- Read up to 5 chars; pad missing positions with max value (84)
        local c = {
            b85dec[data:sub(i, i)] or 0,
            rem >= 2 and (b85dec[data:sub(i + 1, i + 1)] or 84) or 84,
            rem >= 3 and (b85dec[data:sub(i + 2, i + 2)] or 84) or 84,
            rem >= 4 and (b85dec[data:sub(i + 3, i + 3)] or 84) or 84,
            rem >= 5 and (b85dec[data:sub(i + 4, i + 4)] or 84) or 84,
        }
        local n = ((((c[1] * 85 + c[2]) * 85 + c[3]) * 85 + c[4]) * 85 + c[5])
        -- A group of m chars decodes to m-1 bytes
        local need = math.min(rem, 5) - 1
        if need >= 4 then out[#out + 1] = string.char(floor(n / 16777216) % 256) end
        if need >= 3 then out[#out + 1] = string.char(floor(n / 65536) % 256) end
        if need >= 2 then out[#out + 1] = string.char(floor(n / 256) % 256) end
        if need >= 1 then out[#out + 1] = string.char(n % 256) end
        i = i + 5
    end
    return table.concat(out)
end

return base85
