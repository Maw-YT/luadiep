-- Minimal JSON decoder for bundled tank definitions.
local json = {}
json.null = { _json_null = true }

local pos, str, len

local function skip()
    while pos <= len do
        local c = str:byte(pos)
        if c ~= 32 and c ~= 9 and c ~= 10 and c ~= 13 then
            return
        end
        pos = pos + 1
    end
end

local parseValue

local function parseString()
    pos = pos + 1
    local buf = {}
    while pos <= len do
        local c = str:sub(pos, pos)
        if c == '"' then
            pos = pos + 1
            return table.concat(buf)
        elseif c == "\\" then
            local n = str:sub(pos + 1, pos + 1)
            local map = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
            if n == "u" then
                local hex = str:sub(pos + 2, pos + 5)
                buf[#buf + 1] = utf8 and utf8.char(tonumber(hex, 16) or 0) or "?"
                pos = pos + 6
            else
                buf[#buf + 1] = map[n] or n
                pos = pos + 2
            end
        else
            local start = pos
            while pos <= len do
                local b = str:byte(pos)
                if b == 34 or b == 92 then break end
                pos = pos + 1
            end
            buf[#buf + 1] = str:sub(start, pos - 1)
        end
    end
    error("unterminated string")
end

local function parseNumber()
    local start = pos
    if str:sub(pos, pos) == "-" then pos = pos + 1 end
    while pos <= len and str:byte(pos) >= 48 and str:byte(pos) <= 57 do pos = pos + 1 end
    if str:sub(pos, pos) == "." then
        pos = pos + 1
        while pos <= len and str:byte(pos) >= 48 and str:byte(pos) <= 57 do pos = pos + 1 end
    end
    local e = str:sub(pos, pos)
    if e == "e" or e == "E" then
        pos = pos + 1
        local s = str:sub(pos, pos)
        if s == "+" or s == "-" then pos = pos + 1 end
        while pos <= len and str:byte(pos) >= 48 and str:byte(pos) <= 57 do pos = pos + 1 end
    end
    return tonumber(str:sub(start, pos - 1))
end

local function parseArray()
    pos = pos + 1
    local arr = {}
    skip()
    if str:sub(pos, pos) == "]" then
        pos = pos + 1
        return arr
    end
    while true do
        arr[#arr + 1] = parseValue()
        skip()
        local c = str:sub(pos, pos)
        if c == "]" then
            pos = pos + 1
            return arr
        elseif c == "," then
            pos = pos + 1
            skip()
        else
            error("expected comma in array")
        end
    end
end

local function parseObject()
    pos = pos + 1
    local obj = {}
    skip()
    if str:sub(pos, pos) == "}" then
        pos = pos + 1
        return obj
    end
    while true do
        skip()
        if str:sub(pos, pos) ~= '"' then error("expected string key") end
        local key = parseString()
        skip()
        if str:sub(pos, pos) ~= ":" then error("expected colon") end
        pos = pos + 1
        obj[key] = parseValue()
        skip()
        local c = str:sub(pos, pos)
        if c == "}" then
            pos = pos + 1
            return obj
        elseif c == "," then
            pos = pos + 1
        else
            error("expected comma in object")
        end
    end
end

parseValue = function()
    skip()
    local c = str:sub(pos, pos)
    if c == '"' then return parseString() end
    if c == "{" then return parseObject() end
    if c == "[" then return parseArray() end
    if c == "t" and str:sub(pos, pos + 3) == "true" then pos = pos + 4; return true end
    if c == "f" and str:sub(pos, pos + 4) == "false" then pos = pos + 5; return false end
    if c == "n" and str:sub(pos, pos + 3) == "null" then pos = pos + 4; return json.null end
    if c == "-" or (c and c:match("%d")) then return parseNumber() end
    error("unexpected token at " .. tostring(pos))
end

function json.decode(s)
    str = s
    len = #s
    pos = 1
    local value = parseValue()
    return value
end

return json
