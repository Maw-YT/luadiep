# LoveDiepClient

A [LÖVE](https://love2d.org/) 11.5 desktop client for [LuvitDiepEngine](../LuvitDiepEngine). It speaks the same diep.io WebSocket protocol as the engine. It is not the diepcustom WASM / browser client.

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
