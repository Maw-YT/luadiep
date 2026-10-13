-- Store-only zip of the LÖVE client. A .love file is a zip whose root holds conf.lua.

local uv = require("uv")
local bit = require("bit")

local Pack = {}

local function asString(data)
    if data == nil then
        return ""
    end
    if type(data) == "string" then
        return data
    end
    if type(data) == "table" or type(data) == "userdata" then
        local ok, text = pcall(function()
            return data:toString()
        end)
        if ok and type(text) == "string" then
            return text
        end
    end
    return tostring(data)
end

local function readFile(path)
    local fd, err = uv.fs_open(path, "r", 438)
    if not fd then
        return nil, err or "open failed"
    end
    local stat = uv.fs_fstat(fd)
    local size = stat and stat.size or 0
    if size == 0 then
        uv.fs_close(fd)
        return ""
    end
    local data, readErr = uv.fs_read(fd, size, 0)
    uv.fs_close(fd)
    if not data then
        return nil, readErr or "read failed"
    end
    return asString(data)
end

local function join(dir, rel)
    local sep = package.config:sub(1, 1)
    if rel == "" then
        return dir
    end
    return dir .. sep .. rel:gsub("/", sep)
end

local function listFiles(root)
    local out = {}
    local function walk(rel)
        local req = uv.fs_scandir(join(root, rel))
        if not req then
            return
        end
        while true do
            local name, typ = uv.fs_scandir_next(req)
            if not name then
                break
            end
            if name ~= "." and name ~= ".." and name ~= ".git" and name ~= ".DS_Store" then
                local child = rel == "" and name or (rel .. "/" .. name)
                if typ == "directory" then
                    walk(child)
                elseif typ == "file" then
                    out[#out + 1] = child
                end
            end
        end
    end
    walk("")
    table.sort(out)
    return out
end

local function crc32(data)
    local crc = 4294967295
    for i = 1, #data do
        crc = bit.bxor(crc, data:byte(i))
        for _ = 1, 8 do
            if bit.band(crc, 1) == 1 then
                crc = bit.bxor(bit.rshift(crc, 1), 0xEDB88320)
            else
                crc = bit.rshift(crc, 1)
            end
        end
    end
    local out = bit.bxor(crc, 0xFFFFFFFF)
    if out < 0 then
        out = out + 4294967296
    end
    return out
end

local function u16(n)
    n = n % 65536
    return string.char(n % 256, math.floor(n / 256) % 256)
end

local function u32(n)
    if n < 0 then
        n = n + 4294967296
    end
    n = n % 4294967296
    return string.char(
        n % 256,
        math.floor(n / 256) % 256,
        math.floor(n / 65536) % 256,
        math.floor(n / 16777216) % 256
    )
end

function Pack.zip(root)
    local names = listFiles(root)
    if #names == 0 then
        return nil, "client folder is empty"
    end
    local locals = {}
    local central = {}
    local offset = 0
    for i = 1, #names do
        local name = names[i]:gsub("\\", "/")
        local data, err = readFile(join(root, name))
        if not data then
            return nil, tostring(err) .. " (" .. name .. ")"
        end
        local crc = crc32(data)
        local localHeader = "PK\3\4"
            .. u16(20)
            .. u16(0)
            .. u16(0)
            .. u16(0)
            .. u16(0)
            .. u32(crc)
            .. u32(#data)
            .. u32(#data)
            .. u16(#name)
            .. u16(0)
            .. name
        locals[#locals + 1] = localHeader
        locals[#locals + 1] = data
        central[#central + 1] = "PK\1\2"
            .. u16(20)
            .. u16(20)
            .. u16(0)
            .. u16(0)
            .. u16(0)
            .. u16(0)
            .. u32(crc)
            .. u32(#data)
            .. u32(#data)
            .. u16(#name)
            .. u16(0)
            .. u16(0)
            .. u16(0)
            .. u16(0)
            .. u32(0)
            .. u32(offset)
            .. name
        offset = offset + #localHeader + #data
    end
    local body = table.concat(locals)
    local directory = table.concat(central)
    local endRec = "PK\5\6"
        .. u16(0)
        .. u16(0)
        .. u16(#central)
        .. u16(#central)
        .. u32(#directory)
        .. u32(#body)
        .. u16(0)
    return body .. directory .. endRec
end

return Pack
