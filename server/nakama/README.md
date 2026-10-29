# DantesCards Nakama modules

Versioned copy of the Lua runtime modules of the "dantes-cards" Nakama 3.41 instance (its own database `dantes`,
API port 7450). The live files sit in the instance's modules folder on the server PC; this copy is what the
game client is written against.

- `modules/dantes_core.lua`: auth before-hooks (device auth only for now), RPCs `dantes_ping` and
  `dantes_active_match`, and the matchmaker hook that creates a `dantes_match` for two players.
- `modules/dantes_match.lua`: the 1v1 duel relay. The protocol (op codes and payloads) is in its header.
- `modules/dantes_telemetry.lua`: anonymous match statistics (system-owned storage `dantes_telemetry`): every duel
  (from dantes_match), every match against the AI and every lesson (RPC `dantes_report` from the client); totals
  with RPC `dantes_stats` (server to server only, with the http_key).

Secrets (the server key, http key, console credentials) live only on the server PC and in the game's untracked
`config/online.local.cfg`, never in this repo.
