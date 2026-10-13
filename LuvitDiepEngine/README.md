# Luvit DiepCustom

A [Luvit](https://luvit.io/) / LuaJIT port of [diepcustom](https://github.com/ABCxFF/diepcustom). It speaks the same diep.io WebSocket protocol.

The frontend is **[LoveDiepClient](../LoveDiepClient)**, the same LÖVE 11.5 client on the desktop and in the browser. The browser build is that client running under [love.js](https://github.com/2dengine/love.js), served from this process.

## Requirements

Install [Luvit](https://luvit.io/) (includes LuaJIT, libuv, and OpenSSL).

For the client, install [LÖVE 11.5](https://love2d.org/).

## Run

From this directory:

```bash
luvit main.lua
```

The server listens on port **8080** by default (`PORT` env var overrides it).

| Endpoint | Purpose |
| --- | --- |
| http://localhost:8080/ | LÖVE client in the browser |
| http://localhost:8080/api/tanks | Tank definitions JSON |
| http://localhost:8080/api/servers | Gamemode list |
| http://localhost:8080/api/colors | Color table |
| ws://localhost:8080/ffa | FFA |
| ws://localhost:8080/teams | 2TDM |
| ws://localhost:8080/4teams | 4TDM |
| ws://localhost:8080/maze | Maze |
| ws://localhost:8080/survival | Survival |
| ws://localhost:8080/dom | Domination |
| ws://localhost:8080/mot | Mothership |
| ws://localhost:8080/sandbox | Sandbox (cheats enabled) |

Open http://localhost:8080/ for the browser client. It is the LÖVE game, not a separate web port. The page talks to this same server.

The desktop client is unchanged:

```bash
love ../LoveDiepClient
```

Connect to `127.0.0.1:8080` and pick a gamemode.

## Configuration

See `src/config.lua`. Useful environment variables:

- `PORT` — HTTP / WebSocket port
- `SERVER_INFO` — host id sent to clients
- `DEV_PASSWORD_HASH` — SHA-256 hex of the developer password
- `BOTS_PER_GAME` — initial AI-controlled player bots per gamemode (default `0`; FullAccess admins can use `admin_bots [0-64]`)

`enableApi` is on. HTTP serves `/api/*` for tank lists, servers, and changelog, and `/` for the love.js page. `client.love` is zipped from `../LoveDiepClient` on each request. The love.js runtime in `web/` needs `Cross-Origin-Opener-Policy` and `Cross-Origin-Embedder-Policy`; this server sends both.

## License

AGPL-3.0, same as diepcustom. See [`../LICENSE`](../LICENSE).
