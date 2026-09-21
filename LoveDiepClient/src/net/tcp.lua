local ffi = require("ffi")
local bit = require("bit")
local class = require("src.lib.class")
local Tls = require("src.net.tls")

local Tcp = class()
local C
local IS_WIN = ffi.os == "Windows"

local AF_INET = 2
local SOCK_STREAM = 1
local IPPROTO_TCP = 6
local FIONBIO = bit.tobit(0x8004667E)
local WSAEWOULDBLOCK = 10035
local WSAEINPROGRESS = 10036
local WSAEALREADY = 10037
local WSAEISCONN = 10056
local EWOULDBLOCK = 11
local EINPROGRESS = 115
local EAGAIN = 11

if IS_WIN then
    ffi.cdef[[
        typedef uintptr_t SOCKET;
        typedef unsigned int u_int;
        typedef struct fd_set { u_int fd_count; SOCKET fd_array[64]; } fd_set;
        typedef struct timeval { long tv_sec; long tv_usec; } timeval;
        struct in_addr { uint32_t s_addr; };
        struct sockaddr { uint16_t sa_family; char sa_data[14]; };
        struct sockaddr_in {
            int16_t sin_family;
            uint16_t sin_port;
            struct in_addr sin_addr;
            char sin_zero[8];
        };
        struct addrinfo {
            int ai_flags;
            int ai_family;
            int ai_socktype;
            int ai_protocol;
            size_t ai_addrlen;
            char *ai_canonname;
            struct sockaddr *ai_addr;
            struct addrinfo *ai_next;
        };
        int WSAStartup(uint16_t wVersionRequested, void *lpWSAData);
        int WSACleanup(void);
        int WSAGetLastError(void);
        SOCKET socket(int af, int type, int protocol);
        int connect(SOCKET s, const struct sockaddr *name, int namelen);
        int closesocket(SOCKET s);
        int send(SOCKET s, const char *buf, int len, int flags);
        int recv(SOCKET s, char *buf, int len, int flags);
        int ioctlsocket(SOCKET s, long cmd, unsigned long *argp);
        int setsockopt(SOCKET s, int level, int optname, const char *optval, int optlen);
        int select(int nfds, fd_set *readfds, fd_set *writefds, fd_set *exceptfds, const timeval *timeout);
        int getsockopt(SOCKET s, int level, int optname, char *optval, int *optlen);
        uint16_t htons(uint16_t hostshort);
        uint32_t inet_addr(const char *cp);
        int getaddrinfo(const char *node, const char *service, const struct addrinfo *hints, struct addrinfo **res);
        void freeaddrinfo(struct addrinfo *res);
    ]]
    C = ffi.load("ws2_32")
    local wsa = ffi.new("char[512]")
    C.WSAStartup(0x202, wsa)
else
    ffi.cdef[[
        typedef int SOCKET;
        struct in_addr { uint32_t s_addr; };
        struct sockaddr { uint16_t sa_family; char sa_data[14]; };
        struct sockaddr_in {
            uint16_t sin_family;
            uint16_t sin_port;
            struct in_addr sin_addr;
            char sin_zero[8];
        };
        struct addrinfo {
            int ai_flags;
            int ai_family;
            int ai_socktype;
            int ai_protocol;
            uint32_t ai_addrlen;
            char *ai_canonname;
            struct sockaddr *ai_addr;
            struct addrinfo *ai_next;
        };
        int socket(int af, int type, int protocol);
        int connect(int s, const struct sockaddr *name, unsigned int namelen);
        int close(int s);
        long send(int s, const char *buf, unsigned long len, int flags);
        long recv(int s, char *buf, unsigned long len, int flags);
        int fcntl(int fd, int cmd, int arg);
        int setsockopt(int s, int level, int optname, const char *optval, unsigned int optlen);
        uint16_t htons(uint16_t hostshort);
        uint32_t inet_addr(const char *cp);
        int getaddrinfo(const char *node, const char *service, const struct addrinfo *hints, struct addrinfo **res);
        void freeaddrinfo(struct addrinfo *res);
        char *strerror(int errnum);
    ]]
    C = ffi.C
end

local RECV_SIZE = 65536
local recvBuf = ffi.new("char[65536]")

local function lastError()
    if IS_WIN then
        return tonumber(C.WSAGetLastError())
    end
    return ffi.errno()
end

local function errName(code)
    local names = {
        [10061] = "connection refused",
        [10060] = "timed out",
        [10065] = "host unreachable",
        [10051] = "network unreachable",
        [111] = "connection refused",
        [110] = "timed out"
    }
    return names[code] or ("error " .. tostring(code))
end

function Tcp:init()
    self.sock = nil
    self.connected = false
    self.connecting = false
    self.closed = true
    self.sendQ = ""
    self.recvQ = ""
    self.wireQ = ""
    self.err = nil
    self.connectAt = 0
    self.tlsWant = false
    self.tlsReady = false
    self.tlsHost = nil
    self._tls = nil
    self.tlsAt = 0
end

function Tcp:_closeSock()
    if not self.sock then return end
    if IS_WIN then
        C.closesocket(self.sock)
    else
        C.close(self.sock)
    end
    self.sock = nil
end

function Tcp:close()
    if self._tls then
        Tls.close(self._tls)
        self._tls = nil
    end
    self:_closeSock()
    self.connected = false
    self.connecting = false
    self.tlsReady = false
    self.tlsWant = false
    self.closed = true
    self.wireQ = ""
end

local function makeAddr(host, port)
    local addr = ffi.new("struct sockaddr_in")
    addr.sin_family = AF_INET
    addr.sin_port = C.htons(port)
    local ip = C.inet_addr(host)
    if ip ~= 0xFFFFFFFF then
        addr.sin_addr.s_addr = ip
        return ffi.cast("struct sockaddr*", addr), ffi.sizeof(addr), addr
    end
    local hints = ffi.new("struct addrinfo")
    hints.ai_family = AF_INET
    hints.ai_socktype = SOCK_STREAM
    hints.ai_protocol = IPPROTO_TCP
    local res = ffi.new("struct addrinfo*[1]")
    local rc = C.getaddrinfo(host, tostring(port), hints, res)
    if rc ~= 0 or res[0] == nil then
        return nil, nil, nil, "dns failed"
    end
    ffi.copy(addr, res[0].ai_addr, math.min(tonumber(res[0].ai_addrlen) or 16, ffi.sizeof(addr)))
    C.freeaddrinfo(res[0])
    return ffi.cast("struct sockaddr*", addr), ffi.sizeof(addr), addr
end

function Tcp:connect(host, port, tls)
    self:close()
    self.err = nil
    self.sendQ = ""
    self.recvQ = ""
    self.wireQ = ""
    self.closed = false
    self.tlsWant = tls and true or false
    self.tlsReady = false
    self.tlsHost = host
    if self.tlsWant and not Tls.supported() then
        self.err = "tls is not supported on this system"
        self.closed = true
        return false, self.err
    end
    local sa, salen, keep, dnsErr = makeAddr(host, tonumber(port) or 8080)
    self._keepAddr = keep
    if not sa then
        self.err = dnsErr or "invalid address"
        self.closed = true
        return false, self.err
    end
    local s = C.socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    if IS_WIN then
        if s == ffi.cast("SOCKET", -1) then
            self.err = errName(lastError())
            self.closed = true
            return false, self.err
        end
        local nb = ffi.new("unsigned long[1]", 1)
        if C.ioctlsocket(s, FIONBIO, nb) ~= 0 then
            self.err = "socket setup failed"
            C.closesocket(s)
            self.closed = true
            return false, self.err
        end
    else
        if s < 0 then
            self.err = errName(lastError())
            self.closed = true
            return false, self.err
        end
        local F_GETFL, F_SETFL = 3, 4
        local O_NONBLOCK = (ffi.os == "OSX") and 4 or 2048
        local flags = C.fcntl(s, F_GETFL, 0)
        C.fcntl(s, F_SETFL, bit.bor(flags, O_NONBLOCK))
    end
    self.sock = s
    do
        local SOL_SOCKET = IS_WIN and 0xFFFF or 1
        local SO_RCVBUF = IS_WIN and 0x1002 or 8
        local SO_SNDBUF = IS_WIN and 0x1001 or 7
        local SO_KEEPALIVE = IS_WIN and 8 or 9
        local TCP_NODELAY = 1
        local buf = ffi.new("int[1]", 256 * 1024)
        local one = ffi.new("int[1]", 1)
        pcall(function()
            C.setsockopt(s, SOL_SOCKET, SO_RCVBUF, ffi.cast("const char*", buf), 4)
            C.setsockopt(s, SOL_SOCKET, SO_SNDBUF, ffi.cast("const char*", buf), 4)
            C.setsockopt(s, SOL_SOCKET, SO_KEEPALIVE, ffi.cast("const char*", one), 4)
            C.setsockopt(s, IPPROTO_TCP, TCP_NODELAY, ffi.cast("const char*", one), 4)
        end)
    end
    local rc = C.connect(s, sa, salen)
    if rc == 0 then
        self.connecting = false
        self.connected = not self.tlsWant
        return true
    end
    local e = lastError()
    if e == WSAEWOULDBLOCK or e == WSAEINPROGRESS or e == WSAEALREADY
        or e == EINPROGRESS or e == EWOULDBLOCK then
        self.connecting = true
        self.connectAt = love.timer.getTime()
        return true
    end
    self.err = errName(e)
    self:_closeSock()
    self.closed = true
    return false, self.err
end

function Tcp:_flushQueue(field)
    local q = self[field]
    if q == nil or q == "" or not self.sock then return true end
    local n = C.send(self.sock, q, #q, 0)
    n = tonumber(n)
    if n == nil or n < 0 then
        local e = lastError()
        if e == WSAEWOULDBLOCK or e == EWOULDBLOCK or e == EAGAIN then
            return true
        end
        self.err = errName(e)
        self:close()
        return false
    end
    if n >= #q then
        self[field] = ""
    else
        self[field] = q:sub(n + 1)
    end
    return true
end

function Tcp:_flushSend()
    return self:_flushQueue("sendQ")
end

function Tcp:_flushWire()
    return self:_flushQueue("wireQ")
end

function Tcp:_canRecv()
    if not IS_WIN or not self.sock then return true end
    if not self._tv then
        self._tv = ffi.new("timeval")
        self._rfds = ffi.new("fd_set")
    end
    self._tv.tv_sec = 0
    self._tv.tv_usec = 0
    self._rfds.fd_count = 1
    self._rfds.fd_array[0] = self.sock
    local n = tonumber(C.select(0, self._rfds, nil, nil, self._tv)) or 0
    return n > 0
end

function Tcp:_overflow()
    if (self.recvQ and #self.recvQ > 2097152)
        or (self.sendQ and #self.sendQ > 2097152)
        or (self.wireQ and #self.wireQ > 2097152) then
        self.err = "network buffer overflow"
        self:close()
        return true
    end
    return false
end

function Tcp:_tryConnect()
    if not self.connecting or not self.sock then return end
    if IS_WIN then
        local fd = ffi.new("fd_set")
        fd.fd_count = 1
        fd.fd_array[0] = self.sock
        local tv = ffi.new("timeval")
        tv.tv_sec = 0
        tv.tv_usec = 0
        local n = C.select(0, nil, fd, nil, tv)
        if n > 0 then
            local errbuf = ffi.new("int[1]")
            local len = ffi.new("int[1]", 4)
            C.getsockopt(self.sock, 0xFFFF, 0x1007, ffi.cast("char*", errbuf), len)
            if errbuf[0] ~= 0 then
                self.err = errName(tonumber(errbuf[0]))
                self:close()
            else
                self.connecting = false
                self.connected = not self.tlsWant
            end
        elseif love.timer.getTime() - self.connectAt > 8 then
            self.err = "timed out"
            self:close()
        end
    else
        local rc = C.send(self.sock, "", 0, 0)
        if tonumber(rc) >= 0 then
            self.connecting = false
            self.connected = not self.tlsWant
        else
            local e = lastError()
            if e ~= EINPROGRESS and e ~= EWOULDBLOCK and e ~= EAGAIN then
                if love.timer.getTime() - self.connectAt > 8 then
                    self.err = errName(e)
                    self:close()
                end
            elseif love.timer.getTime() - self.connectAt > 8 then
                self.err = "timed out"
                self:close()
            end
        end
    end
end

function Tcp:_readRaw()
    if not self.sock then return "" end
    local chunks = {}
    for _ = 1, 8 do
        if not self:_canRecv() then break end
        local n = C.recv(self.sock, recvBuf, RECV_SIZE, 0)
        n = tonumber(n)
        if n == nil or n < 0 then
            local e = lastError()
            if e == WSAEWOULDBLOCK or e == EWOULDBLOCK or e == EAGAIN then
                break
            end
            self.err = errName(e)
            self:close()
            return table.concat(chunks)
        end
        if n == 0 then
            self:close()
            return table.concat(chunks)
        end
        chunks[#chunks + 1] = ffi.string(recvBuf, n)
        if n < RECV_SIZE then break end
    end
    return table.concat(chunks)
end

function Tcp:_tlsReadOnce()
    if not self.sock or not self._tls then return 0 end
    local state = self._tls
    if state.kind == "openssl" then
        if not self:_canRecv() then return 0 end
        local n = C.recv(self.sock, recvBuf, 16384, 0)
        n = tonumber(n)
        if n == nil or n < 0 then
            local e = lastError()
            if e == WSAEWOULDBLOCK or e == EWOULDBLOCK or e == EAGAIN then
                return 0
            end
            self.err = errName(e)
            self:close()
            return nil
        end
        if n == 0 then
            self:close()
            return nil
        end
        local ok = Tls.feed(state, ffi.string(recvBuf, n))
        if not ok then
            self.err = "tls feed failed"
            self:close()
            return nil
        end
        return n
    end
    local ptr, space = Tls.recvPtr(state)
    if not ptr or space < 1 then
        return 0, "full"
    end
    if not self:_canRecv() then return 0 end
    local n = C.recv(self.sock, ffi.cast("char*", ptr), space, 0)
    n = tonumber(n)
    if n == nil or n < 0 then
        local e = lastError()
        if e == WSAEWOULDBLOCK or e == EWOULDBLOCK or e == EAGAIN then
            return 0
        end
        self.err = errName(e)
        self:close()
        return nil
    end
    if n == 0 then
        self:close()
        return nil
    end
    Tls.commitRecv(state, n)
    return n
end

function Tcp:_tlsEncryptOut()
    if not self._tls or not self.tlsReady or self.sendQ == "" then return end
    local cipher, err = Tls.encrypt(self._tls, self.sendQ)
    if not cipher then
        self.err = err or "tls encrypt failed"
        self:close()
        return
    end
    self.sendQ = self._tls.pendingPlain or ""
    if self._tls.pendingPlain then
        self._tls.pendingPlain = nil
    end
    if cipher ~= "" then
        self.wireQ = self.wireQ .. cipher
    end
end

function Tcp:_tlsBoot()
    local state, err = Tls.start(self.tlsHost or "")
    if not state then
        self.err = err or "tls failed"
        self:close()
        return
    end
    self._tls = state
    self.tlsAt = love.timer.getTime()
    if state.pendingOut and state.pendingOut ~= "" then
        self.wireQ = self.wireQ .. state.pendingOut
        state.pendingOut = ""
    end
    if state.ready then
        self:_tlsOnReady()
    end
end

function Tcp:_tlsOnReady()
    self.tlsReady = true
    self.connected = true
    local leftover, err = Tls.decrypt(self._tls)
    if err then
        self.err = err
        self:close()
        return
    end
    if leftover and leftover ~= "" then
        self.recvQ = self.recvQ .. leftover
    end
    if self._tls.pendingOut and self._tls.pendingOut ~= "" then
        self.wireQ = self.wireQ .. self._tls.pendingOut
        self._tls.pendingOut = ""
    end
end

function Tcp:_tlsPump()
    if not self._tls then return end
    local budget = love.timer.getTime() + 0.008
    self:_flushWire()
    if self.closed then return end
    for _ = 1, 6 do
        if love.timer.getTime() > budget then break end
        local n, why = self:_tlsReadOnce()
        if self.closed then return end
        if why == "full" then
            if self.tlsReady then
                local plain, err = Tls.decrypt(self._tls)
                if err then
                    self.err = err
                    self:close()
                    return
                end
                if plain and plain ~= "" then
                    self.recvQ = self.recvQ .. plain
                end
                if Tls.space(self._tls) < 1 then
                    if (self._tls.received or 0) >= (self._tls.cap or 0) then
                        self.err = "tls buffer stuck"
                        self:close()
                    end
                    break
                end
            else
                local done, token, err = Tls.handshake(self._tls)
                if token and token ~= "" then
                    self.wireQ = self.wireQ .. token
                end
                if err then
                    self.err = err
                    self:close()
                    return
                end
                if done then
                    self:_tlsOnReady()
                    if self.closed then return end
                elseif Tls.space(self._tls) < 1 then
                    self.err = "tls handshake buffer full"
                    self:close()
                    return
                end
            end
        elseif n == nil then
            return
        else
            if not self.tlsReady then
                local done, token, err = Tls.handshake(self._tls)
                if token and token ~= "" then
                    self.wireQ = self.wireQ .. token
                end
                if err then
                    self.err = err
                    self:close()
                    return
                end
                if done then
                    self:_tlsOnReady()
                    if self.closed then return end
                elseif love.timer.getTime() - (self.tlsAt or self.connectAt) > 12 then
                    self.err = "timed out"
                    self:close()
                    return
                end
            end
            if self.tlsReady then
                local plain, err = Tls.decrypt(self._tls)
                if err then
                    self.err = err
                    self:close()
                    return
                end
                if plain and plain ~= "" then
                    self.recvQ = self.recvQ .. plain
                end
            end
            if n == 0 then
                break
            end
        end
    end
    if self._tls and self._tls.pendingOut and self._tls.pendingOut ~= "" then
        self.wireQ = self.wireQ .. self._tls.pendingOut
        self._tls.pendingOut = ""
    end
    self:_tlsEncryptOut()
    if self.closed then return end
    self:_flushWire()
    if self._tls and self._tls.closed then
        self:close()
    end
    self:_overflow()
end

function Tcp:update()
    if self.closed then return end
    if self.connecting then
        self:_tryConnect()
        if self.connecting then return end
        if self.closed then return end
    end
    if self.tlsWant then
        if not self._tls then
            self:_tlsBoot()
            if self.closed then return end
        end
        self:_tlsPump()
        return
    end
    if not self.connected then return end
    self:_flushSend()
    if not self.connected then return end
    self.recvQ = self.recvQ .. self:_readRaw()
    self:_overflow()
end

function Tcp:send(data)
    if self.closed then return false end
    self.sendQ = self.sendQ .. data
    if self.connected and not self.tlsWant then
        self:_flushSend()
    elseif self.tlsReady then
        self:_tlsEncryptOut()
        self:_flushWire()
    end
    return true
end

function Tcp:readAll()
    local q = self.recvQ
    self.recvQ = ""
    return q
end

function Tcp:readSome(n)
    if n >= #self.recvQ then
        return self:readAll()
    end
    local chunk = self.recvQ:sub(1, n)
    self.recvQ = self.recvQ:sub(n + 1)
    return chunk
end

return Tcp
