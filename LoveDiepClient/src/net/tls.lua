local ffi = require("ffi")
local bit = require("bit")

local Tls = {}
local IS_WIN = ffi.os == "Windows"
local INCOMING_MAX = 32768
local MAX_RECORDS = 24

local schannel
local openssl
local opensslInit = false

local function hr(n)
    return tonumber(ffi.cast("int32_t", n))
end

local SEC_E_OK = 0
local SEC_I_CONTINUE_NEEDED = 0x00090312
local SEC_I_COMPLETE_NEEDED = 0x00090313
local SEC_I_COMPLETE_AND_CONTINUE = 0x00090314
local SEC_I_INCOMPLETE_CREDENTIALS = 0x00090320
local SEC_I_CONTEXT_EXPIRED = 0x00090317
local SEC_I_RENEGOTIATE = 0x0009030C
local SEC_E_INVALID_TOKEN = hr(0x80090308)
local SEC_E_INCOMPLETE_MESSAGE = hr(0x80090318)
local SEC_E_WRONG_PRINCIPAL = hr(0x80090322)
local SEC_E_UNTRUSTED_ROOT = hr(0x80090325)
local SEC_E_CERT_EXPIRED = hr(0x80090328)
local SEC_E_ILLEGAL_MESSAGE = hr(0x80090326)
local SEC_E_ALGORITHM_MISMATCH = hr(0x80090331)
local SEC_E_INTERNAL_ERROR = hr(0x80090304)
local SEC_E_CERT_UNKNOWN = hr(0x80090327)
local SEC_E_UNTRUSTED_NCRYPT_KEY = hr(0x80090429)

local SECBUFFER_EMPTY = 0
local SECBUFFER_DATA = 1
local SECBUFFER_TOKEN = 2
local SECBUFFER_EXTRA = 5
local SECBUFFER_STREAM_TRAILER = 6
local SECBUFFER_STREAM_HEADER = 7
local SECBUFFER_MISSING = 13
local SECBUFFER_VERSION = 0
local SP_PROT_TLS1_2_CLIENT = 0x00000800
local SP_PROT_TLS1_3_CLIENT = 0x00002000

local SECPKG_CRED_OUTBOUND = 2
local SECPKG_ATTR_STREAM_SIZES = 4
local SCHANNEL_CRED_VERSION = 4
local SCH_CRED_MANUAL_CRED_VALIDATION = 0x00000008
local SCH_CRED_NO_DEFAULT_CREDS = 0x00000010
local SCH_CRED_AUTO_CRED_VALIDATION = 0x00000020
local SCH_CRED_IGNORE_NO_REVOCATION_CHECK = 0x00000800
local SCH_CRED_IGNORE_REVOCATION_OFFLINE = 0x00001000
local SCH_USE_STRONG_CRYPTO = 0x00400000
local UNISP_NAME = "Microsoft Unified Security Protocol Provider"

local ISC_FLAGS = bit.bor(
    0x00000010, -- ISC_REQ_CONFIDENTIALITY
    0x00000004, -- ISC_REQ_REPLAY_DETECT
    0x00000008, -- ISC_REQ_SEQUENCE_DETECT
    0x00000100, -- ISC_REQ_ALLOCATE_MEMORY
    0x00008000, -- ISC_REQ_STREAM
    0x00080000  -- ISC_REQ_MANUAL_CRED_VALIDATION (no OCSP/CRL network stall)
)

local function tlsErr(sec)
    if sec == SEC_E_WRONG_PRINCIPAL then return "tls: hostname mismatch" end
    if sec == SEC_E_UNTRUSTED_ROOT then return "tls: untrusted certificate" end
    if sec == SEC_E_CERT_EXPIRED then return "tls: certificate expired" end
    if sec == SEC_E_CERT_UNKNOWN then return "tls: unknown certificate" end
    if sec == SEC_E_ILLEGAL_MESSAGE then return "tls: illegal message" end
    if sec == SEC_E_ALGORITHM_MISMATCH then return "tls: algorithm mismatch" end
    if sec == SEC_E_INVALID_TOKEN then return "tls: invalid handshake token" end
    if sec == SEC_I_INCOMPLETE_CREDENTIALS then return "tls: client certificate required" end
    if sec == SEC_I_RENEGOTIATE then return "tls: renegotiate not supported" end
    if sec == SEC_E_INTERNAL_ERROR then return "tls: internal error" end
    return string.format("tls error %s", bit.tohex(sec or 0))
end

if IS_WIN then
    ffi.cdef[[
        typedef uint32_t ULONG;
        typedef int32_t LONG;
        typedef uintptr_t ULONG_PTR;
        typedef LONG SECURITY_STATUS;
        typedef void *PVOID;
        typedef wchar_t *SEC_WCHAR;
        typedef char SEC_CHAR;

        typedef struct _SecHandle {
            ULONG_PTR dwLower;
            ULONG_PTR dwUpper;
        } SecHandle, *PSecHandle;
        typedef SecHandle CredHandle;
        typedef SecHandle CtxtHandle;
        typedef CredHandle *PCredHandle;
        typedef CtxtHandle *PCtxtHandle;

        typedef struct _SECURITY_INTEGER {
            uint32_t LowPart;
            int32_t HighPart;
        } SECURITY_INTEGER, TimeStamp, *PTimeStamp;

        typedef struct _SecBuffer {
            ULONG cbBuffer;
            ULONG BufferType;
            PVOID pvBuffer;
        } SecBuffer, *PSecBuffer;

        typedef struct _SecBufferDesc {
            ULONG ulVersion;
            ULONG cBuffers;
            PSecBuffer pBuffers;
        } SecBufferDesc, *PSecBufferDesc;

        typedef struct _SCHANNEL_CRED {
            ULONG dwVersion;
            ULONG cCreds;
            PVOID paCred;
            PVOID hRootStore;
            ULONG cMappers;
            PVOID aphMappers;
            ULONG cSupportedAlgs;
            PVOID palgSupportedAlgs;
            ULONG grbitEnabledProtocols;
            ULONG dwMinimumCipherStrength;
            ULONG dwMaximumCipherStrength;
            ULONG dwSessionLifespan;
            ULONG dwFlags;
            ULONG dwCredFormat;
        } SCHANNEL_CRED;

        typedef struct _SecPkgContext_StreamSizes {
            ULONG cbHeader;
            ULONG cbTrailer;
            ULONG cbMaximumMessage;
            ULONG cBuffers;
            ULONG cbBlockSize;
        } SecPkgContext_StreamSizes;

        SECURITY_STATUS __stdcall AcquireCredentialsHandleA(
            const char *pszPrincipal,
            const char *pszPackage,
            ULONG fCredentialUse,
            void *pvLogonId,
            void *pAuthData,
            void *pGetKeyFn,
            void *pvGetKeyArgument,
            PCredHandle phCredential,
            PTimeStamp ptsExpiry
        );
        SECURITY_STATUS __stdcall FreeCredentialsHandle(PCredHandle phCredential);
        SECURITY_STATUS __stdcall InitializeSecurityContextA(
            PCredHandle phCredential,
            PCtxtHandle phContext,
            const char *pszTargetName,
            ULONG fContextReq,
            ULONG Reserved1,
            ULONG TargetDataRep,
            PSecBufferDesc pInput,
            ULONG Reserved2,
            PCtxtHandle phNewContext,
            PSecBufferDesc pOutput,
            ULONG *pfContextAttr,
            PTimeStamp ptsExpiry
        );
        SECURITY_STATUS __stdcall DeleteSecurityContext(PCtxtHandle phContext);
        SECURITY_STATUS __stdcall FreeContextBuffer(PVOID pvContextBuffer);
        SECURITY_STATUS __stdcall QueryContextAttributesA(
            PCtxtHandle phContext,
            ULONG ulAttribute,
            void *pBuffer
        );
        SECURITY_STATUS __stdcall EncryptMessage(
            PCtxtHandle phContext,
            ULONG fQOP,
            PSecBufferDesc pMessage,
            ULONG MessageSeqNo
        );
        SECURITY_STATUS __stdcall DecryptMessage(
            PCtxtHandle phContext,
            PSecBufferDesc pMessage,
            ULONG MessageSeqNo,
            ULONG *pfQOP
        );
    ]]
    schannel = ffi.load("secur32")
end

local function loadOpenSSL()
    if openssl ~= nil then return openssl ~= false and openssl or nil end
    local names = {
        "ssl",
        "libssl.so.3",
        "libssl.so.1.1",
        "libssl.so.1.0.0",
        "libssl.3.dylib",
        "libssl.1.1.dylib"
    }
    for i = 1, #names do
        local ok, lib = pcall(ffi.load, names[i])
        if ok and lib then
            openssl = lib
            return lib
        end
    end
    openssl = false
    return nil
end

if not IS_WIN then
    ffi.cdef[[
        typedef struct ssl_st SSL;
        typedef struct ssl_ctx_st SSL_CTX;
        typedef struct ssl_method_st SSL_METHOD;
        typedef struct bio_st BIO;
        typedef struct bio_method_st BIO_METHOD;
        int OPENSSL_init_ssl(uint64_t opts, void *settings);
        SSL_CTX *SSL_CTX_new(const SSL_METHOD *meth);
        void SSL_CTX_free(SSL_CTX *ctx);
        const SSL_METHOD *TLS_client_method(void);
        int SSL_CTX_set_default_verify_paths(SSL_CTX *ctx);
        void SSL_CTX_set_verify(SSL_CTX *ctx, int mode, void *callback);
        SSL *SSL_new(SSL_CTX *ctx);
        void SSL_free(SSL *ssl);
        void SSL_set_connect_state(SSL *ssl);
        int SSL_do_handshake(SSL *ssl);
        int SSL_get_error(const SSL *ssl, int ret);
        int SSL_write(SSL *ssl, const void *buf, int num);
        int SSL_read(SSL *ssl, void *buf, int num);
        int SSL_shutdown(SSL *ssl);
        long SSL_ctrl(SSL *ssl, int cmd, long larg, void *parg);
        void SSL_set_bio(SSL *ssl, BIO *rbio, BIO *wbio);
        BIO *BIO_new(const BIO_METHOD *type);
        const BIO_METHOD *BIO_s_mem(void);
        int BIO_write(BIO *b, const void *data, int len);
        int BIO_read(BIO *b, void *data, int len);
        long BIO_ctrl(BIO *bp, int cmd, long larg, void *parg);
    ]]
end

local SSL_ERROR_WANT_READ = 2
local SSL_ERROR_WANT_WRITE = 3
local SSL_ERROR_ZERO_RETURN = 6
local SSL_CTRL_SET_TLSEXT_HOSTNAME = 55
local SSL_VERIFY_PEER = 1
local BIO_CTRL_PENDING = 10

function Tls.supported()
    if IS_WIN then return schannel ~= nil end
    return loadOpenSSL() ~= nil
end

local function takeAllocToken(buf)
    if buf.pvBuffer == nil or tonumber(buf.cbBuffer) == 0 then
        return ""
    end
    local token = ffi.string(buf.pvBuffer, tonumber(buf.cbBuffer))
    schannel.FreeContextBuffer(buf.pvBuffer)
    buf.pvBuffer = nil
    buf.cbBuffer = 0
    return token
end

local function compactIncoming(state, extraBuf)
    local extra = tonumber(extraBuf.cbBuffer) or 0
    if extra <= 0 or extraBuf.pvBuffer == nil then
        state.received = 0
        return
    end
    if extra > state.cap then extra = state.cap end
    if extraBuf.pvBuffer ~= state.incoming then
        ffi.copy(state.scratch, extraBuf.pvBuffer, extra)
        ffi.copy(state.incoming, state.scratch, extra)
    end
    state.received = extra
end

local function schannelISC(state, withInput)
    local inbuffers, indesc
    if withInput then
        inbuffers = ffi.new("SecBuffer[2]")
        inbuffers[0].BufferType = SECBUFFER_TOKEN
        inbuffers[0].pvBuffer = state.incoming
        inbuffers[0].cbBuffer = state.received
        inbuffers[1].BufferType = SECBUFFER_EMPTY
        indesc = ffi.new("SecBufferDesc")
        indesc.ulVersion = SECBUFFER_VERSION
        indesc.cBuffers = 2
        indesc.pBuffers = inbuffers
    end

    local outbuffers = ffi.new("SecBuffer[1]")
    outbuffers[0].BufferType = SECBUFFER_TOKEN
    outbuffers[0].pvBuffer = nil
    outbuffers[0].cbBuffer = 0
    local outdesc = ffi.new("SecBufferDesc")
    outdesc.ulVersion = SECBUFFER_VERSION
    outdesc.cBuffers = 1
    outdesc.pBuffers = outbuffers

    local attr = ffi.new("ULONG[1]")
    local oldCtx = state.haveCtx and state.ctx or nil
    local newCtx = state.haveCtx and nil or state.ctx
    local target = state.hostPtr

    local sec = tonumber(schannel.InitializeSecurityContextA(
        state.cred,
        oldCtx,
        target,
        ISC_FLAGS,
        0,
        0,
        indesc,
        0,
        newCtx,
        outdesc,
        attr,
        nil
    ))

    state.haveCtx = true
    local token = takeAllocToken(outbuffers[0])

    if withInput and inbuffers then
        if sec ~= SEC_E_INCOMPLETE_MESSAGE then
            local extraBuf
            for i = 0, 1 do
                if tonumber(inbuffers[i].BufferType) == SECBUFFER_EXTRA then
                    extraBuf = inbuffers[i]
                    break
                end
            end
            if extraBuf then
                compactIncoming(state, extraBuf)
            else
                state.received = 0
            end
        end
    end

    return sec, token
end

local function bioPending(bio)
    return tonumber(openssl.BIO_ctrl(bio, BIO_CTRL_PENDING, 0, nil)) or 0
end

local function bioReadAll(bio)
    local n = bioPending(bio)
    if n <= 0 then return "" end
    local buf = ffi.new("uint8_t[?]", n)
    local got = tonumber(openssl.BIO_read(bio, buf, n)) or 0
    if got <= 0 then return "" end
    return ffi.string(buf, got)
end

local function opensslHandshake(state)
    local ret = tonumber(openssl.SSL_do_handshake(state.ssl)) or 0
    local pending = bioReadAll(state.outbio)
    if ret == 1 then
        state.ready = true
        return true, pending, nil
    end
    local err = tonumber(openssl.SSL_get_error(state.ssl, ret)) or 0
    if err == SSL_ERROR_WANT_READ or err == SSL_ERROR_WANT_WRITE then
        return false, pending, nil
    end
    if err == SSL_ERROR_ZERO_RETURN then
        return false, pending, "tls closed"
    end
    return false, pending, "tls handshake failed"
end

function Tls.start(hostname)
    hostname = tostring(hostname or "")
    if hostname == "" then
        return nil, "tls: missing hostname"
    end
    if IS_WIN then
        if not schannel then
            return nil, "tls is not supported"
        end
        local cred = ffi.new("CredHandle")
        local ctx = ffi.new("CtxtHandle")
        local credData = ffi.new("SCHANNEL_CRED")
        credData.dwVersion = SCHANNEL_CRED_VERSION
        credData.dwFlags = bit.bor(
            SCH_CRED_NO_DEFAULT_CREDS,
            SCH_CRED_MANUAL_CRED_VALIDATION,
            SCH_CRED_IGNORE_NO_REVOCATION_CHECK,
            SCH_CRED_IGNORE_REVOCATION_OFFLINE
        )
        credData.grbitEnabledProtocols = SP_PROT_TLS1_2_CLIENT
        local status = tonumber(schannel.AcquireCredentialsHandleA(
            nil,
            UNISP_NAME,
            SECPKG_CRED_OUTBOUND,
            nil,
            credData,
            nil,
            nil,
            cred,
            nil
        ))
        if status ~= SEC_E_OK then
            return nil, "tls: credentials failed"
        end
        local state = {
            kind = "schannel",
            hostname = hostname,
            hostPtr = ffi.new("char[?]", #hostname + 1, hostname),
            cred = cred,
            ctx = ctx,
            haveCtx = false,
            ready = false,
            closed = false,
            incoming = ffi.new("uint8_t[?]", INCOMING_MAX),
            scratch = ffi.new("uint8_t[?]", INCOMING_MAX),
            received = 0,
            cap = INCOMING_MAX,
            sizes = nil,
            dBuffers = ffi.new("SecBuffer[4]"),
            dDesc = ffi.new("SecBufferDesc"),
            eBuffers = ffi.new("SecBuffer[3]"),
            eDesc = ffi.new("SecBufferDesc")
        }
        local sec, token = schannelISC(state, false)
        if sec ~= SEC_I_CONTINUE_NEEDED and sec ~= SEC_E_OK
            and sec ~= SEC_I_COMPLETE_AND_CONTINUE and sec ~= SEC_I_COMPLETE_NEEDED then
            schannel.FreeCredentialsHandle(cred)
            return nil, tlsErr(sec)
        end
        if sec == SEC_E_OK then
            local sizes = ffi.new("SecPkgContext_StreamSizes")
            local q = tonumber(schannel.QueryContextAttributesA(state.ctx, SECPKG_ATTR_STREAM_SIZES, sizes))
            if q ~= SEC_E_OK then
                schannel.DeleteSecurityContext(state.ctx)
                schannel.FreeCredentialsHandle(cred)
                return nil, "tls: stream sizes failed"
            end
            state.sizes = sizes
            state.ready = true
            local maxm = tonumber(sizes.cbMaximumMessage) or 16384
            if maxm > 16384 then maxm = 16384 end
            state.encBuf = ffi.new("uint8_t[?]", (tonumber(sizes.cbHeader) or 5) + maxm + (tonumber(sizes.cbTrailer) or 16))
            state.encMax = maxm
            state.encHeader = tonumber(sizes.cbHeader) or 5
            state.encTrailer = tonumber(sizes.cbTrailer) or 16
        end
        state.pendingOut = token or ""
        return state
    end

    local sslLib = loadOpenSSL()
    if not sslLib then
        return nil, "tls is not supported on this system"
    end
    if not opensslInit then
        pcall(function() sslLib.OPENSSL_init_ssl(0, nil) end)
        opensslInit = true
    end
    local method = sslLib.TLS_client_method()
    if method == nil then
        return nil, "tls: missing client method"
    end
    local ctx = sslLib.SSL_CTX_new(method)
    if ctx == nil then
        return nil, "tls: context failed"
    end
    pcall(function() sslLib.SSL_CTX_set_default_verify_paths(ctx) end)
    pcall(function() sslLib.SSL_CTX_set_verify(ctx, SSL_VERIFY_PEER, nil) end)
    local ssl = sslLib.SSL_new(ctx)
    if ssl == nil then
        sslLib.SSL_CTX_free(ctx)
        return nil, "tls: ssl failed"
    end
    local hostPtr = ffi.new("char[?]", #hostname + 1, hostname)
    sslLib.SSL_ctrl(ssl, SSL_CTRL_SET_TLSEXT_HOSTNAME, 0, hostPtr)
    local inbio = sslLib.BIO_new(sslLib.BIO_s_mem())
    local outbio = sslLib.BIO_new(sslLib.BIO_s_mem())
    if inbio == nil or outbio == nil then
        sslLib.SSL_free(ssl)
        sslLib.SSL_CTX_free(ctx)
        return nil, "tls: bio failed"
    end
    sslLib.SSL_set_bio(ssl, inbio, outbio)
    sslLib.SSL_set_connect_state(ssl)
    local state = {
        kind = "openssl",
        hostname = hostname,
        hostPtr = hostPtr,
        ctx = ctx,
        ssl = ssl,
        inbio = inbio,
        outbio = outbio,
        ready = false,
        closed = false,
        incoming = ffi.new("uint8_t[?]", INCOMING_MAX),
        received = 0,
        cap = INCOMING_MAX
    }
    local done, pending, err = opensslHandshake(state)
    if err then
        Tls.close(state)
        return nil, err
    end
    state.pendingOut = pending or ""
    return state
end

function Tls.space(state)
    if not state then return 0 end
    if state.kind == "openssl" then return 16384 end
    local space = (state.cap or 0) - (state.received or 0)
    if space < 0 then return 0 end
    return space
end

function Tls.recvPtr(state)
    if not state or state.kind == "openssl" then return nil, 0 end
    return state.incoming + state.received, Tls.space(state)
end

function Tls.commitRecv(state, n)
    n = tonumber(n) or 0
    if n <= 0 then return end
    state.received = (state.received or 0) + n
    if state.received > state.cap then
        state.received = state.cap
    end
end

function Tls.feed(state, bytes)
    if not state or not bytes or bytes == "" then return true, 0 end
    if state.kind == "openssl" then
        local n = openssl.BIO_write(state.inbio, bytes, #bytes)
        if n == nil or n < 0 then
            return false, "tls: bio write failed"
        end
        return true, tonumber(n) or 0
    end
    local space = Tls.space(state)
    if space <= 0 then
        return true, 0
    end
    local n = #bytes
    if n > space then n = space end
    ffi.copy(state.incoming + state.received, bytes, n)
    state.received = state.received + n
    return true, n
end

function Tls.handshake(state)
    if not state then return false, "", "tls: missing state" end
    if state.ready then return true, "", nil end
    if state.kind == "openssl" then
        return opensslHandshake(state)
    end
    if state.received <= 0 then
        return false, "", nil
    end
    local tokens = {}
    for _ = 1, 8 do
        if state.received <= 0 then break end
        local before = state.received
        local sec, token = schannelISC(state, true)
        if token and token ~= "" then
            tokens[#tokens + 1] = token
        end
        if sec == SEC_E_INCOMPLETE_MESSAGE then
            break
        end
        if sec == SEC_I_CONTINUE_NEEDED or sec == SEC_I_COMPLETE_AND_CONTINUE then
            if state.received >= before then
                break
            end
        elseif sec == SEC_E_OK or sec == SEC_I_COMPLETE_NEEDED then
            local sizes = ffi.new("SecPkgContext_StreamSizes")
            local q = tonumber(schannel.QueryContextAttributesA(state.ctx, SECPKG_ATTR_STREAM_SIZES, sizes))
            if q ~= SEC_E_OK then
                return false, table.concat(tokens), "tls: stream sizes failed"
            end
            state.sizes = sizes
            local maxm = tonumber(sizes.cbMaximumMessage) or 16384
            if maxm > 16384 then maxm = 16384 end
            local header = tonumber(sizes.cbHeader) or 5
            local trailer = tonumber(sizes.cbTrailer) or 16
            state.encBuf = ffi.new("uint8_t[?]", header + maxm + trailer)
            state.encMax = maxm
            state.encHeader = header
            state.encTrailer = trailer
            state.ready = true
            return true, table.concat(tokens), nil
        else
            return false, table.concat(tokens), tlsErr(sec)
        end
    end
    return false, table.concat(tokens), nil
end

function Tls.encrypt(state, plain)
    if not state or not state.ready then return nil, "tls not ready" end
    if not plain or plain == "" then return "" end
    if state.kind == "openssl" then
        local n = openssl.SSL_write(state.ssl, plain, #plain)
        if n == nil or n <= 0 then
            local err = tonumber(openssl.SSL_get_error(state.ssl, n or 0)) or 0
            if err == SSL_ERROR_WANT_READ or err == SSL_ERROR_WANT_WRITE then
                return bioReadAll(state.outbio)
            end
            return nil, "tls encrypt failed"
        end
        return bioReadAll(state.outbio)
    end
    local maxm = state.encMax or 16384
    local header = state.encHeader or tonumber(state.sizes.cbHeader) or 5
    local trailer = state.encTrailer or tonumber(state.sizes.cbTrailer) or 16
    if maxm > 16384 then maxm = 16384 end
    if not state.encBuf then
        state.encBuf = ffi.new("uint8_t[?]", header + maxm + trailer)
    end
    if state.pendingPlain and state.pendingPlain ~= "" then
        plain = state.pendingPlain .. plain
        state.pendingPlain = nil
    end
    local buf = state.encBuf
    local buffers = state.eBuffers
    local desc = state.eDesc
    local chunks = {}
    local off = 1
    local steps = 0
    while off <= #plain do
        steps = steps + 1
        if steps > MAX_RECORDS then break end
        local use = #plain - off + 1
        if use > maxm then use = maxm end
        ffi.copy(buf + header, plain:sub(off, off + use - 1), use)
        buffers[0].BufferType = SECBUFFER_STREAM_HEADER
        buffers[0].pvBuffer = buf
        buffers[0].cbBuffer = header
        buffers[1].BufferType = SECBUFFER_DATA
        buffers[1].pvBuffer = buf + header
        buffers[1].cbBuffer = use
        buffers[2].BufferType = SECBUFFER_STREAM_TRAILER
        buffers[2].pvBuffer = buf + header + use
        buffers[2].cbBuffer = trailer
        desc.ulVersion = SECBUFFER_VERSION
        desc.cBuffers = 3
        desc.pBuffers = buffers
        local sec = tonumber(schannel.EncryptMessage(state.ctx, 0, desc, 0))
        if sec ~= SEC_E_OK then
            return nil, "tls encrypt failed"
        end
        local total = tonumber(buffers[0].cbBuffer) + tonumber(buffers[1].cbBuffer) + tonumber(buffers[2].cbBuffer)
        chunks[#chunks + 1] = ffi.string(buf, total)
        off = off + use
    end
    if off <= #plain then
        state.pendingPlain = plain:sub(off)
    end
    return table.concat(chunks)
end

function Tls.decrypt(state)
    if not state or not state.ready then return "", nil end
    if state.kind == "openssl" then
        local out = {}
        local buf = ffi.new("uint8_t[?]", 16384)
        for _ = 1, MAX_RECORDS do
            local n = tonumber(openssl.SSL_read(state.ssl, buf, 16384)) or 0
            if n > 0 then
                out[#out + 1] = ffi.string(buf, n)
            else
                local err = tonumber(openssl.SSL_get_error(state.ssl, n)) or 0
                if err == SSL_ERROR_WANT_READ or err == SSL_ERROR_WANT_WRITE then
                    break
                end
                if err == SSL_ERROR_ZERO_RETURN then
                    state.closed = true
                    break
                end
                if n == 0 then break end
                return nil, "tls decrypt failed"
            end
        end
        return table.concat(out)
    end
    local plains = {}
    local buffers = state.dBuffers
    local desc = state.dDesc
    for _ = 1, MAX_RECORDS do
        if state.received <= 0 then break end
        local before = state.received
        ffi.fill(buffers, ffi.sizeof(buffers), 0)
        buffers[0].BufferType = SECBUFFER_DATA
        buffers[0].pvBuffer = state.incoming
        buffers[0].cbBuffer = state.received
        desc.ulVersion = SECBUFFER_VERSION
        desc.cBuffers = 4
        desc.pBuffers = buffers
        local sec = tonumber(schannel.DecryptMessage(state.ctx, desc, 0, nil))
        if sec == SEC_E_INCOMPLETE_MESSAGE then
            break
        elseif sec == SEC_I_CONTEXT_EXPIRED then
            state.closed = true
            state.received = 0
            break
        elseif sec == SEC_I_RENEGOTIATE then
            return nil, "tls: renegotiate not supported"
        elseif sec == SEC_E_INVALID_TOKEN then
            return nil, tlsErr(sec)
        elseif sec ~= SEC_E_OK then
            return nil, tlsErr(sec)
        else
            local extraBuf
            for i = 0, 3 do
                local t = tonumber(buffers[i].BufferType)
                if t == SECBUFFER_DATA and buffers[i].pvBuffer ~= nil then
                    local n = tonumber(buffers[i].cbBuffer) or 0
                    if n > 0 then
                        plains[#plains + 1] = ffi.string(buffers[i].pvBuffer, n)
                    end
                elseif t == SECBUFFER_EXTRA then
                    extraBuf = buffers[i]
                end
            end
            if extraBuf then
                local extra = tonumber(extraBuf.cbBuffer) or 0
                if extra >= before then
                    break
                end
                compactIncoming(state, extraBuf)
            else
                state.received = 0
            end
            if state.received >= before then
                break
            end
        end
    end
    return table.concat(plains)
end

function Tls.close(state)
    if not state or state.freed then return end
    state.freed = true
    state.ready = false
    if state.kind == "schannel" then
        if state.haveCtx then
            pcall(function() schannel.DeleteSecurityContext(state.ctx) end)
            state.haveCtx = false
        end
        if state.cred then
            pcall(function() schannel.FreeCredentialsHandle(state.cred) end)
            state.cred = nil
        end
    elseif state.kind == "openssl" then
        if state.ssl then
            pcall(function() openssl.SSL_free(state.ssl) end)
            state.ssl = nil
        end
        if state.ctx then
            pcall(function() openssl.SSL_CTX_free(state.ctx) end)
            state.ctx = nil
        end
    end
end

return Tls
