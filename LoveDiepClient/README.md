# LoveDiepClient

A [LÖVE](https://love2d.org/) 11.5 client for [LuvitDiepEngine](../LuvitDiepEngine). It speaks the same diep.io WebSocket protocol as the engine. The desktop build uses LÖVE directly. The browser build is this same project, loaded by the server's love.js page.

## Requirements

- [LÖVE 11.5](https://love2d.org/)
- A running LuvitDiepEngine server

## Run

```bash
# terminal 1
cd LuvitDiepEngine
luvit main.lua

# terminal 2
love LoveDiepClient
```

Connect to `127.0.0.1:8080` (or any `ws://host:port/path`), then pick a gamemode.

## Browser

With the server running, open http://localhost:8080/. That page runs this client inside LÖVE 11.5 compiled for the web. The address field starts as the page host, and play connects back to that server. LuaJIT `ffi` sockets are desktop-only; the browser uses the page's WebSocket and `fetch`.

## Controls

| Input | Action |
| --- | --- |
| WASD / arrows | Move |
| Mouse | Aim |
| Left click | Fire |
| Right click | Alt fire / repel |
| Enter | Spawn / dismiss death screen |
| U | Level up (sandbox / cheats) |
| K | Suicide (sandbox / cheats) |
| G | God mode (sandbox / cheats) |
| Esc | Disconnect to menu |

Click the green tank buttons to upgrade. Click the blue stat rows to spend points.

## License

AGPL-3.0, same protocol family as LuvitDiepEngine / diepcustom. See [`../LICENSE`](../LICENSE).
