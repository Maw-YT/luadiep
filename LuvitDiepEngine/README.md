# Luvit DiepCustom

A [Luvit](https://luvit.io/) / LuaJIT port of [diepcustom](https://github.com/ABCxFF/diepcustom). It speaks the same diep.io WebSocket protocol.

The intended frontend is **[LoveDiepClient](../LoveDiepClient)**, a LÖVE desktop client. This server no longer serves the diepcustom WASM / browser client.

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
| http://localhost:8080/api/tanks | Tank definitions JSON |
| http://localhost:8080/api/servers | Gamemode list |
| http://localhost:8080/api/colors | Color table |
| ws://localhost:8080/ffa | FFA |
| ws://localhost:8080/sandbox | Sandbox (cheats enabled) |

Then start the client:

```bash
love ../LoveDiepClient
```

Connect to `127.0.0.1:8080` and pick `ffa` or `sandbox`.

## Configuration

See `src/config.lua`. Useful environment variables:

- `PORT` — HTTP / WebSocket port
- `SERVER_INFO` — host id sent to clients
- `DEV_PASSWORD_HASH` — SHA-256 hex of the developer password

`enableClient` is off. HTTP still serves `/api/*` for tank lists and server info. The leftover files in `client/` are the old diepcustom WASM loader and are not used.

## License

AGPL-3.0, same as diepcustom. See [`../LICENSE`](../LICENSE).
