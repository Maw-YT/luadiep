# LuaDiep

A Lua port of [diepcustom](https://github.com/ABCxFF/diepcustom): a Luvit / LuaJIT server and a [LÖVE](https://love2d.org/) 11.5 desktop client. Both speak the diep.io WebSocket protocol.

## Layout

| Path | What it is |
| --- | --- |
| [`LuvitDiepEngine/`](LuvitDiepEngine) | Game server (FFA and Sandbox) |
| [`LoveDiepClient/`](LoveDiepClient) | Desktop client |

## Requirements

- [Luvit](https://luvit.io/) (LuaJIT, libuv, OpenSSL)
- [LÖVE 11.5](https://love2d.org/)

## Run

From this folder, start the server:

```bash
cd LuvitDiepEngine
luvit main.lua
```

It listens on port **8080** by default (`PORT` overrides it).

In another terminal, start the client:

```bash
love LoveDiepClient
```

Connect to `127.0.0.1` port `8080`, then pick **FFA** or **Sandbox**.

## License

AGPL-3.0. See [`LICENSE`](LICENSE).
