# NETWORKING — Godot Multiplayer State Sync (Spike)

**Status:** foundation spike. No sockets, no matchmaking, and no gameplay
integration yet. This proves the authoritative snapshot loop, interpolation, and
event dedupe before committing to a transport.

## What is in the tree

| File | Role |
|---|---|
| `scripts/net/net_snapshot.gd` | Versioned snapshot schema + encode/decode |
| `scripts/net/net_server.gd` | Authoritative state, sequenced inputs, cast events, snapshot broadcast |
| `scripts/net/net_client.gd` | Snapshot buffer, interpolation, event dedupe |
| `scripts/net/loopback_link.gd` | In-process transport with tick latency/loss for tests |
| `scripts/debug/net_test.gd` | Headless two-client loopback proof |
| `scenes/NetTest.tscn` | Test entry point |

Run the proof:

```powershell
& "C:\Users\minisforum-zach\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe" --headless --path . res://scenes/NetTest.tscn
```

## Transport decision

| Transport | Browser | Topology | Verdict |
|---|---|---|---|
| **WebSocketMultiplayerPeer** | Yes (wss://) | Client ↔ dedicated server | **Recommended for PVP/BR.** Reliable, works through itch iframes, server-authoritative. Needs a hosted headless Godot server. |
| WebRTC | Yes | P2P with signaling + STUN/TURN | Lower latency, but signaling, NAT traversal, and relay ops are a separate project. Not first. |
| ENet | No | UDP client/server | Desktop only; good for a LAN/build-server mode, not the jam browser build. |

**Recommendation:** a headless Godot server using `WebSocketMultiplayerPeer` on
`wss://`, deployed to Fly.io/Railway/a small VPS. The browser client connects from
the itch page. The `LoopbackLink` interface in the spike is the seam: swap it for a
WebSocket link with the same `send/poll` shape.

## Snapshot schema (version 1)

- `v` schema version
- `tick` server tick
- `phase`, `round`, `ps`, `es` match state
- `w` wizard map:
  - `id`, `pos` (Vector3), `vel`, `aim`
  - `hp/max_hp`, `mana/max_mana`, `shield`
  - `page`, `slot`, `cooldowns[4]`
  - `chant`, `chant_progress`, `chant_text_len`
  - `alive`, `burn`, `slow`, `stun`
- `e` cast events:
  - `id`, `tick`, `kind`, `caster`
  - `spell` (element/form/modifier)
  - `origin`, `direction`

The spike uses Godot's Variant serialization (`var_to_bytes`) for fast iteration.
Measured: **1,188 bytes** for two wizards + one event. A packed codec with
quantized positions/angles should target **<512 bytes** for 2 wizards and
**<1.5 KiB** for 8 wizards.

## Timing

- Simulation: 20 Hz.
- Snapshots: 10 Hz in the spike (every 2 ticks); target 15–20 Hz later.
- Client interpolation: render 4 ticks behind the latest snapshot.
- Events: resent in a 60-tick (3s) window; clients dedupe by event id.
- Inputs: sequence-numbered; the server ignores stale/duplicate sequences.

## Authority rules

- Server owns position, HP, mana, shields, cooldowns, chant state, and spell
  resolution. Clients send intent only.
- Validate move magnitude, cast rate, mana, cooldowns, and range server-side.
- Never accept a client-declared hit or reward.
- Add client-side prediction for the local wizard later; keep remote wizards
  interpolated.

## Integration seam

1. Replace `NetServer`'s stub movement with the real `Arena`/`Wizard` simulation.
2. Serialize each `Wizard` into the schema above; map `cast_fired` to a server
   event.
3. The client applies snapshots to visual `Wizard` nodes (position/aim/HP/mana)
   and plays cast events; local input is predicted, then reconciled.
4. Add a `WebSocketLink` implementing `send`/`poll`; keep `LoopbackLink` for tests.
5. Add connection UI, room codes, and reconnect/resync.

## Known gaps

- No prediction/reconciliation or rollback.
- No real socket, matchmaking, accounts, or hosting.
- `var_to_bytes` is a placeholder; validate and bound untrusted payloads before
  production.
- No anti-cheat beyond the authority rules above.

## Verification

```
NET: 11 checks, 0 failures
  clients received snapshots 32/32
  ticks are monotonic 104/104
  snapshot payload is bounded 1188 bytes
  client 1 converges err=0.000
  client 2 converges err=0.000
  spell event delivered once (both clients)
  duplicate/out-of-order snapshot ignored
  server/rival authoritative at rest
```
