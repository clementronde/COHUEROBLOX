# COHUE

Survivors-like coop game on Roblox (working title).

- **Architecture contract** (v2 ids, boot order, service APIs, remotes, Bus events, ownership, Studio and Git rules): [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- **Design dossier**: [docs/dossier/](docs/dossier/) — `00-vision.md` (the design doc), `01-decisions-v2.md` (v2 decisions, they win), then one file per domain.
- **Split of work** (decisions v2 §13): Clément does design, models, effects and UI (placed as objects, plus `client/Controllers/UI/*` and `client/Controllers/Lobby/*`); Ironix does everything technical.
- **Syntax check**: `bash tools/check.sh` (all files) or `bash tools/check.sh path/to/file.luau`.

## Studio ↔ disk mapping (Script Sync)

| Studio | Disk |
| --- | --- |
| `ReplicatedStorage/Shared` | `shared/` |
| `ServerScriptService/Server` | `server/` |
| `StarterPlayer/StarterPlayerScripts/Client` | `client/` |

Naming (Studio Script Sync): `name.luau` = ModuleScript, `name.legacy.luau` = Script, `name.local.luau` = LocalScript. Sync each Studio folder (`Shared`, `Server`, `Client`) to the repo root folder, not to the matching folder. Only Ironix syncs the shared `COHUE` place (from `F:\CohueRoblox`, branch `main`). Never edit a script in Studio; no models in the synced folders, no scripts in models.

**First sync:** in Studio, create the three empty `Folder`s above. Right-click each one, choose **Sync to…**, and pick the matching folder on disk. If Studio shows a conflict, keep the disk version.


**Single game (since 4 Nov 2026):** the only place is the published `COHUE` place. Agents never create their own place copies. After each merge into `main`, Script Sync on Ironix's PC brings the new scripts into `COHUE` (the Studio MCP cannot make HTTP requests, so `tools/studio-load.luau` no longer works from an agent).

## Team rules (design doc 12.6)

- Synced folders hold only scripts and folders. No attributes or tags on scripts (Script Sync drops them).
- One script, one editor at a time.
- **Git branches:** each agent works in its own worktree `F:\CohueRoblox-agents\<id>` on a `claude/<id>-...` branch, never in `F:\CohueRoblox`, never on `main`, never force push. Only `main` syncs into `COHUE`. Never switch branches in `F:\CohueRoblox`: that rewrites the place's scripts for everyone.
- Packages: Script Sync syncs the scripts inside them, but not the `PackageLink`. Package versions are managed in Studio.
- Tools: Luau Language Server (+ Studio companion plugin), selene, StyLua.

## What's in Phase 0

- `shared/Net.luau`: the one list of remotes, created by the server, plus `Net.onServerEvent` with a per-player rate limit.
- `shared/EnemyCodec.luau`: binary snapshots, 7-byte header + 7 bytes per enemy, chunks of 900 bytes max, tick number in each chunk.
- `server/Services/EnemyService.luau`: enemies as data, 15 Hz, spatial grid, density curve, per-player interest radius (80 studs every tick, 160 studs every 3rd tick).
- `client/Controllers/EnemyRenderer.luau`: part pool, interpolation, one `BulkMoveTo` per frame, out-of-order packets dropped.
- `client/Controllers/DebugHud.luau`: FPS + drawn enemy count.

## Perf test (Phase 0 gate: 150 enemies at 60 fps on a mid-range phone)

In `shared/Config/Balance.luau`, set `Debug.ForceAlive = 150`, then Play (or test on a phone with "Test on device"). Read the counter in the bottom-left corner (Studio only).

## Decisions made

- **Movement: classic mode** (client movement + server plausibility checks in `MovementGuard`).
