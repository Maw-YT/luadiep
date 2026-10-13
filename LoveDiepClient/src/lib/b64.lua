local B64 = {}

local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local map = {}
for i = 1, #chars do
    map[chars:sub(i, i)] = i - 1
end

function B64.encode(data)
    data = data or ""
    local out = {}
    local n = #data
    for i = 1, n, 3 do
        local a, b, c = data:byte(i, i + 2)
        b = b or 0
        c = c or 0
        local n24 = a * 65536 + b * 256 + c
        local pad = (i + 1 > n) and 2 or (i + 2 > n) and 1 or 0
        out[#out + 1] = chars:sub(math.floor(n24 / 262144) + 1, math.floor(n24 / 262144) + 1)
            .. chars:sub(math.floor(n24 / 4096) % 64 + 1, math.floor(n24 / 4096) % 64 + 1)
            .. (pad == 2 and "=" or chars:sub(math.floor(n24 / 64) % 64 + 1, math.floor(n24 / 64) % 64 + 1))
            .. (pad >= 1 and "=" or chars:sub(n24 % 64 + 1, n24 % 64 + 1))
    end
    return table.concat(out)
end

function B64.decode(data)
    data = tostring(data or ""):gsub("%s", "")
    if data == "" then
        return ""
    end
    local out = {}
    for i = 1, #data, 4 do
        local a = map[data:sub(i, i)] or 0
        local b = map[data:sub(i + 1, i + 1)] or 0
        local cch = data:sub(i + 2, i + 2)
        local dch = data:sub(i + 3, i + 3)
        local c = (cch == "" or cch == "=") and nil or (map[cch] or 0)
        local d = (dch == "" or dch == "=") and nil or (map[dch] or 0)
        local n24 = a * 262144 + b * 4096 + (c or 0) * 64 + (d or 0)
        out[#out + 1] = string.char(math.floor(n24 / 65536) % 256)
        if c ~= nil then
            out[#out + 1] = string.char(math.floor(n24 / 256) % 256)
        end
        if d ~= nil then
            out[#out + 1] = string.char(n24 % 256)
        end
    end
    return table.concat(out)
end

return B64
