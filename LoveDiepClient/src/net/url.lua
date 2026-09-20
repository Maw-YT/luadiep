local Url = {}

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function isIpOrLocal(host)
    local h = tostring(host or ""):lower()
    if h == "localhost" or h == "0.0.0.0" then return true end
    if h:match("^%d+%.%d+%.%d+%.%d+$") then return true end
    if host:find(":", 1, true) then return true end
    return false
end

local function knownSet(modes)
    local set = {}
    if type(modes) ~= "table" then return set end
    for i = 1, #modes do
        local id = modes[i]
        if type(id) == "table" then id = id.id end
        if type(id) == "string" and id ~= "" then
            set[id:lower()] = true
        end
    end
    return set
end

function Url.lastSegment(path)
    path = tostring(path or "/"):gsub("/+$", "")
    if path == "" or path == "/" then return "" end
    return path:match("([^/]+)$") or ""
end

function Url.parentPath(path)
    path = tostring(path or "/"):gsub("/+$", "")
    if path == "" or path == "/" then return "/" end
    local parent = path:match("^(.*)/[^/]+$")
    if not parent or parent == "" then return "/" end
    return parent
end

function Url.joinPath(base, extra)
    extra = tostring(extra or ""):gsub("^/+", "")
    base = tostring(base or ""):gsub("/+$", "")
    if extra == "" then
        return (base == "" or base == "/") and "/" or base
    end
    if base == "" or base == "/" then
        return "/" .. extra
    end
    return base .. "/" .. extra
end

function Url.hostHeader(parsed)
    if not parsed then return "" end
    local host = parsed.host or ""
    if host:find(":", 1, true) then
        host = "[" .. host .. "]"
    end
    local port = tonumber(parsed.port)
    local scheme = parsed.scheme or ""
    if (scheme == "http" or scheme == "ws") and port == 80 then
        return host
    end
    if (scheme == "https" or scheme == "wss" or parsed.tls) and port == 443 then
        return host
    end
    if port then
        return host .. ":" .. tostring(port)
    end
    return host
end

function Url.requestPath(parsed)
    if not parsed then return "/" end
    local path = parsed.path
    if type(path) ~= "string" or path == "" then
        path = "/"
    elseif path:sub(1, 1) ~= "/" then
        path = "/" .. path
    end
    if parsed.query and parsed.query ~= "" then
        return path .. "?" .. parsed.query
    end
    return path
end

function Url.origin(parsed)
    if not parsed then return "" end
    local scheme = "http"
    if parsed.tls or parsed.scheme == "https" or parsed.scheme == "wss" then
        scheme = "https"
    end
    return scheme .. "://" .. Url.hostHeader(parsed)
end

function Url.parse(raw)
    raw = trim(raw)
    if raw == "" then
        return nil, "empty url"
    end
    raw = raw:gsub("#.*$", "")

    local scheme
    local rest = raw
    local sch, after = raw:match("^([A-Za-z][A-Za-z0-9+.-]*)://(.+)$")
    if sch then
        scheme = sch:lower()
        rest = after
    end
    rest = rest:gsub("^[^@/?#]+@", "")

    local host, port, pathquery
    if rest:sub(1, 1) == "[" then
        local ipv6, more = rest:match("^%[([^%]]+)%](.*)$")
        if not ipv6 or ipv6 == "" then
            return nil, "invalid ipv6 url"
        end
        host = ipv6
        if more:sub(1, 1) == ":" then
            local p, tail = more:match("^:(%d+)(.*)$")
            if not p then
                return nil, "invalid port"
            end
            port = tonumber(p)
            pathquery = tail
        else
            pathquery = more
        end
    else
        local hp, tail = rest:match("^([^/?#]*)(.*)$")
        hp = hp or rest
        pathquery = tail or ""
        local h, p = hp:match("^(.+):(%d+)$")
        if h and h ~= "" then
            host = h
            port = tonumber(p)
        else
            host = hp
        end
    end

    host = trim(host)
    if host == "" then
        return nil, "missing host"
    end

    local path, query = "/", ""
    pathquery = pathquery or ""
    if pathquery ~= "" then
        local qpos = pathquery:find("?", 1, true)
        if qpos then
            path = pathquery:sub(1, qpos - 1)
            query = pathquery:sub(qpos + 1)
        else
            path = pathquery
        end
    end
    if path == "" then
        path = "/"
    elseif path:sub(1, 1) ~= "/" then
        path = "/" .. path
    end

    local tls = (scheme == "wss" or scheme == "https")
    if not port then
        if scheme == "http" or scheme == "ws" then
            port = 80
        elseif tls then
            port = 443
        elseif isIpOrLocal(host) then
            port = 8080
        else
            port = 443
            tls = true
            scheme = scheme or "wss"
        end
    elseif not scheme and port == 443 then
        tls = true
        scheme = "wss"
    end
    if port < 1 or port > 65535 then
        return nil, "invalid port"
    end

    return {
        scheme = scheme or (tls and "wss" or "ws"),
        host = host,
        port = port,
        path = path,
        query = query,
        tls = tls
    }
end

function Url.resolvePlay(raw, gamemode, modes)
    local parsed, err = Url.parse(raw)
    if not parsed then return nil, err end
    gamemode = tostring(gamemode or "ffa")
    local known = knownSet(modes)
    local last = Url.lastSegment(parsed.path)
    if last == "" then
        parsed.path = "/" .. gamemode
    elseif known[last:lower()] then
        parsed.path = Url.joinPath(Url.parentPath(parsed.path), gamemode)
    end
    return parsed
end

function Url.resolveApi(raw, apiPath, modes)
    local parsed, err = Url.parse(raw)
    if not parsed then return nil, err end
    local path = parsed.path or "/"
    local last = Url.lastSegment(path)
    local known = knownSet(modes)
    if last ~= "" and known[last:lower()] then
        path = Url.parentPath(path)
    end
    parsed.path = Url.joinPath(path, apiPath or "/api/commands")
    parsed.query = ""
    return parsed
end

return Url
