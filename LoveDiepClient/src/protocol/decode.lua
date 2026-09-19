local bit = require("bit")
local Fields = require("src.protocol.fields")

local Decode = {}

local function readType(reader, typ)
    if reader:remaining() <= 0 then
        if typ == "entid" then return false end
        return (typ == "stringNT") and "" or 0
    end
    if typ == "u8" then return reader:u8() end
    if typ == "vu" then return reader:vu() end
    if typ == "vi" then return reader:vi() end
    if typ == "float" then return reader:float() end
    if typ == "float64Precision" then return reader:float64Precision() end
    if typ == "stringNT" then return reader:stringNT() end
    if typ == "entid" then return reader:entid() end
    if typ == "vf" then return reader:vf() end
    error("unknown type " .. tostring(typ))
end

local function consumeIndexTable(reader)
    local ids = {}
    local at = -1
    for _ = 1, 16 do
        if reader:remaining() <= 0 then
            reader.bad = true
            break
        end
        local b = reader:u8()
        if b == 1 then return ids end
        local id = bit.bxor(b, 1) + at
        if id < 0 or id > 20 then
            reader.bad = true
            return ids
        end
        ids[#ids + 1] = id
        at = id
    end
    reader.bad = true
    return ids
end

local function ensureGroup(entity, name)
    if not entity[name] then
        entity[name] = Fields.defaults(name)
    end
    return entity[name]
end

local function applyScalar(entity, field, value)
    if value == false then return end
    if field.key == "scoreboardAmount" then
        value = tonumber(value) or 0
        if value ~= value or value < 0 then value = 0 end
        if value > 10 then value = 10 end
        value = math.floor(value)
    end
    local g = ensureGroup(entity, field.group)
    g[field.key] = value
end

local function applyArrayValue(entity, field, index, value)
    local maxIndex = (field.count or 1) - 1
    if index < 0 or index > maxIndex then return end
    local g = ensureGroup(entity, field.group)
    if not g[field.key] then
        g[field.key] = {}
    end
    g[field.key][index] = value
end

function Decode.entity(reader, existing)
    if reader:remaining() <= 0 then
        return nil, false
    end
    local ident = reader:entid()
    if not ident then
        return nil, false
    end
    local isCreate = reader:u8() ~= 0
    local groupIds = consumeIndexTable(reader)
    if reader.bad then
        return nil, false
    end
    local entity = existing or { id = ident.id, hash = ident.hash }
    entity.id = ident.id
    entity.hash = ident.hash

    local oldPlayer = existing and existing.camera and existing.camera.player
    local oldIbar, oldIbarMax, oldIstat = existing and existing.ibar, existing and existing.ibarMax, existing and existing.istat

    if isCreate then
        entity = { id = ident.id, hash = ident.hash }
        if existing then
            entity.ix, entity.iy, entity.ia = existing.ix, existing.iy, existing.ia
            entity.ih, entity.imh = existing.ih, existing.imh
            entity._shootAnim = existing._shootAnim
            entity._hitFlash = existing._hitFlash
            entity._shotFlags = existing._shotFlags
            entity._dmgFlag = existing._dmgFlag
            entity._hpLag = existing._hpLag
            entity._hpLagWait = existing._hpLagWait
            entity._hpPrev = existing._hpPrev
        end
        for i = 1, #groupIds do
            local name = Fields.GROUP[groupIds[i]]
            if name then
                entity[name] = Fields.defaults(name)
            end
        end
        local keptPlayer = false
        for i = 1, #Fields.list do
            if reader.bad then return entity, false end
            local field = Fields.list[i]
            if entity[field.group] then
                if reader:remaining() <= 0 then
                    reader.bad = true
                    return entity, false
                end
                if field.count then
                    for idx = 0, field.count - 1 do
                        applyArrayValue(entity, field, idx, readType(reader, field.type))
                    end
                else
                    local value = readType(reader, field.type)
                    if field.key == "player" then
                        if value == false then keptPlayer = true end
                    end
                    applyScalar(entity, field, value)
                end
            end
        end
        if keptPlayer and entity.camera and type(oldPlayer) == "table" then
            entity.camera.player = oldPlayer
        end
        if oldIbar then entity.ibar = oldIbar end
        if oldIbarMax then entity.ibarMax = oldIbarMax end
        if oldIstat then entity.istat = oldIstat end
        entity._created = true
    else
        local at = -1
        for _ = 1, 96 do
            if reader.bad then return entity, false end
            if reader:remaining() <= 0 then
                reader.bad = true
                return entity, false
            end
            local b = reader:u8()
            if b == 1 then
                entity._created = false
                return entity, true
            end
            local fid = bit.bxor(b, 1) + at
            at = fid
            local field = Fields.byId[fid]
            if not field then
                reader.bad = true
                return entity, false
            end
            local typ = field.updateType or field.type
            if field.count then
                local innerAt = -1
                local foundEnd = false
                for _inner = 1, field.count + 2 do
                    if reader:remaining() <= 0 then
                        reader.bad = true
                        return entity, false
                    end
                    local ib = reader:u8()
                    if ib == 1 then
                        foundEnd = true
                        break
                    end
                    local idx = bit.bxor(ib, 1) + innerAt
                    innerAt = idx
                    if idx < 0 or idx >= field.count then
                        reader.bad = true
                        return entity, false
                    end
                    applyArrayValue(entity, field, idx, readType(reader, typ))
                end
                if not foundEnd then
                    reader.bad = true
                    return entity, false
                end
                at = fid
            else
                applyScalar(entity, field, readType(reader, typ))
            end
        end
        reader.bad = true
        return entity, false
    end
    if reader.bad then return entity, false end
    return entity, true
end

return Decode
