# COHUE — Phase 0 skeleton

Survivors-like coop game on Roblox (working title). See the design doc, sections 12 and 14.

## Studio ↔ disk mapping (Script Sync)

| Studio | Disk |
| --- | --- |
| `ReplicatedStorage/Shared` | `shared/` |
| `ServerScriptService/Server` | `server/` |
| `StarterPlayer/StarterPlayerScripts/Client` | `client/` |

Naming: `name.luau` = ModuleScript, `name.server.luau` = Script, `name.client.luau` = LocalScript.

**First sync:** in Studio, create the three empty `Folder`s above. Right-click each one, choose **Sync to…**, and pick the matching folder on disk. If Studio shows a conflict, keep the disk version.

## Team rules (design doc 12.6)

- Synced folders hold only scripts and folders. No attributes or tags on scripts (Script Sync drops them).
- One script, one editor at a time.
- **Git branches:** each developer syncs their branch into a **personal dev place** (Save to Roblox As…, a copy). Only `main` syncs into the shared Team Create place. Never switch branches while Studio is syncing: that rewrites the place's scripts for everyone.
- Packages: Script Sync syncs the scripts inside them, but not the `PackageLink`. Package versions are managed in Studio.
- Tools: Luau Language Server (+ Studio companion plugin), selene, StyLua.

## What's in Phase 0

- `shared/Net.luau`: the one list of remotes, created by the server, plus `Net.onServerEvent` with a per-player rate limit.
- `shared/EnemyCodec.luau`: binary snapshots, 7-byte header + 7 bytes per enemy, chunks of 900 bytes max, tick number in each chunk.
- `server/Services/EnemyService.luau`: enemies as data, 15 Hz, spatial grid, density curve, per-player interest radius (80 studs every tick, 160 studs every 3rd tick).
- `client/Controllers/EnemyRenderer.luau`: part pool, interpolation, one `BulkMoveTo` per frame, out-of-order packets dropped.
- `client/Controllers/DebugHud.luau`: FPS + drawn enemy count.

## Perf test (Phase 0 gate: 150 enemies at 60 fps on a mid-range phone)

In `shared/Config/Balance.luau`, set `Debug.ForceAlive = 150`, then Play (or test on a phone with "Test on device"). Read the counter at the top of the screen.

## Decisions made

- **Movement: classic mode** (client movement + server speed checks), pending final confirmation (doc 10.2). Nothing in Phase 0 depends on it yet.
- Enemies don't deal or take damage yet (no weapons): `EnemyService.damage(id, amount)` and `queryRadius` are ready for `WeaponService`.
