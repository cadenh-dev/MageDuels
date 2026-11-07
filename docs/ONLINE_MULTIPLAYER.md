# Online multiplayer

SHIFTCAST uses one `NetTransport` interface. Desktop CLI tests use ENet. Normal
play and Web exports use GD-Sync. The host owns simulation, spell resolution,
scoring, drafting, and rematch state. Input frames are unreliable and batched at
about 30 Hz; compressed wizard snapshots are sent at 20 Hz. Online match payloads
use compact fixed point values and are compressed before relay transport.

## GD-Sync setup

The BSD licensed GD-Sync 1.0.2 addon is vendored in `addons/GD-Sync/` and enabled
as a plugin and `GDSync` autoload in `project.godot`. It connects only when the
Online screen opens. The Web export uses the addon's `WebSocketPeer` secure WebSocket
path.

The key helper reads the two local key files and writes the ConfigFile expected by
GD-Sync's `KeyStore`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/gdsync_keys.ps1
```

It verifies that `addons/GD-Sync/keys.cfg` is ignored before writing. Never remove
that ignore rule or stage the generated file. The export plugin includes the keys
file in the Web pack.

Public and private lobby names are random five character codes. Public listing
filters for protocol-compatible waiting lobbies with one player. Starting a match
updates the lobby state tag. If the host leaves, the remaining client returns to
the menu.

## Local testing

```text
--net-host [port]
--net-join <ip:port>
--net-test
--gdsync-probe
--gdsync-duel-host
--gdsync-duel-join
```

The GD-Sync probe connects, creates and joins a private lobby, lists public
lobbies, then leaves. For a relay duel, run the host command first and the join
command in a second process. The host publishes the temporary code under
`user://gdsync_duel_code.txt`. Both commands print compressed application payload
bytes per second and the session RTT.

The Web release can be exported with:

```powershell
New-Item -ItemType Directory -Force build/web
Godot_v4.7.2-stable_win64_console.exe --headless --path . --export-release "Web" build/web/index.html
```
