--[[
DantesCards - match statistics (Nakama Lua runtime, instance "dantes-cards").

Anonymous: no names, no e-mail, no device ids. A player is a pseudonym (the first 12 hex digits of a SHA-256 of
the user id), enough to count distinct players and repeat games, not to tell who they are. Every finished game is
one system-owned storage object (collection "dantes_telemetry", key "<unix ms>_<random>", nobody can read it from
a client):
  duel (written by dantes_match when a duel ends):
    {kind="duel", t, secs, turns, reason, desync, draw, first_won, players={{p, cls, deck_hash, won, cards}, {...}}}
  ai / lesson (reported by the client through the RPC below, after a match against the AI or a lesson):
    {kind="ai"|"lesson", t, p, v, os, cls, hero, deck, enemy_cls, enemy_deck, difficulty, lesson, result, turns,
     secs, conceded, cards_left, hand}

RPCs
  dantes_report  (a player session) one finished match against the AI or a lesson. Fields are checked and capped;
                 at most REPORTS_PER_HOUR per player.
  dantes_stats   (server to server only: called with the http_key, no user session) the totals so far:
                 {games, players, by_kind, by_day, ai={per class: {games, wins}}, duels={...}, decks={...}, ...}
--]]

local nk = require("nakama")

local M = {}

local SYSTEM = "00000000-0000-0000-0000-000000000000"
local COLLECTION = "dantes_telemetry"
local REPORTS_PER_HOUR = 30
local ID = "^[a-z0-9_:]+$"

function M.pseudonym(uid)
  return string.sub(nk.sha256_hash("dantes-telemetry:" .. (uid or "")), 1, 12)
end

local function key_now()
  return string.format("%d_%s", nk.time(), string.sub(string.gsub(nk.uuid_v4(), "-", ""), 1, 8))
end

function M.write(value)
  value.t = value.t or nk.time()
  local ok, err = pcall(nk.storage_write, { {
    collection = COLLECTION, key = key_now(), user_id = SYSTEM, value = value,
    permission_read = 0, permission_write = 0,
  } })
  if not ok then
    nk.logger_warn("dantes_telemetry write failed: " .. tostring(err))
  end
end

local function deck_hash(deck)
  if type(deck) ~= "table" or type(deck.cards) ~= "table" then return "" end
  local ids = {}
  for _, id in ipairs(deck.cards) do table.insert(ids, tostring(id)) end
  table.sort(ids)
  return string.sub(nk.sha256_hash((deck.cls or "") .. ":" .. table.concat(ids, ",")), 1, 10)
end

-- A finished duel (called from dantes_match's finish). Never raises: statistics must not break a duel.
function M.duel(state, winner, reason, tick, tick_rate)
  pcall(function()
    if not state.start_tick then return end -- nobody played (no_show)
    local players = {}
    for i = 1, 2 do
      local uid = state.players[i]
      local deck = state.decks[uid] or {}
      players[i] = { p = M.pseudonym(uid), cls = deck.cls or "", deck_hash = deck_hash(deck), won = (winner == uid),
        cards = deck.cards or {} }
    end
    M.write({ kind = "duel", secs = math.floor((tick - state.start_tick) / tick_rate), turns = state.turn,
      reason = reason, desync = (reason == "desync"), first_won = (winner ~= "" and winner == state.first),
      draw = (winner == "" and reason == "result"), players = players })
  end)
end

local function str(v, max)
  if type(v) ~= "string" then return "" end
  return string.sub(v, 1, max)
end

local function id(v)
  local s = str(v, 40)
  if s ~= "" and not string.match(s, ID) then return "" end
  return s
end

local function int(v, lo, hi)
  local n = tonumber(v) or 0
  n = math.floor(n)
  if n < lo then n = lo end
  if n > hi then n = hi end
  return n
end

local function report(context, payload)
  local uid = context.user_id
  if not uid then error("session required") end
  local ok, b = pcall(nk.json_decode, payload or "")
  if not ok or type(b) ~= "table" then error("bad payload") end
  -- a small per-player budget, kept in the player's own (server-only) storage object
  local now = nk.time()
  local got = nk.storage_read({ { collection = "dantes_telemetry_budget", key = "hour", user_id = uid } })
  local budget = (got and got[1] and got[1].value) or {}
  if (budget.since or 0) < now - 3600 * 1000 then budget = { since = now, n = 0 } end
  if (budget.n or 0) >= REPORTS_PER_HOUR then return nk.json_encode({ ok = false, reason = "budget" }) end
  budget.n = (budget.n or 0) + 1
  nk.storage_write({ { collection = "dantes_telemetry_budget", key = "hour", user_id = uid, value = budget,
    permission_read = 0, permission_write = 0 } })
  local kind = (b.kind == "lesson") and "lesson" or "ai"
  local result = b.result
  if result ~= "win" and result ~= "loss" and result ~= "draw" and result ~= "left" then result = "" end
  M.write({ kind = kind, p = M.pseudonym(uid), v = str(b.v, 16), os = id(string.lower(str(b.os, 16))),
    cls = id(b.cls), hero = id(b.hero), deck = id(b.deck), enemy_cls = id(b.enemy_cls), enemy_deck = id(b.enemy_deck),
    difficulty = int(b.difficulty, 0, 9), lesson = id(b.lesson), result = result, turns = int(b.turns, 0, 200),
    secs = int(b.secs, 0, 4 * 3600), conceded = (b.conceded == true), cards_left = int(b.cards_left, 0, 60),
    hand = int(b.hand, 0, 10) })
  return nk.json_encode({ ok = true })
end
nk.register_rpc(report, "dantes_report")

-- "YYYY-MM-DD" (UTC) of a unix time in ms, without the os library (the runtime's sandbox may not have it).
local function day_of(ms)
  local z = math.floor((ms or 0) / 86400000) + 719468
  local era = math.floor(z / 146097)
  local doe = z - era * 146097
  local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
  local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
  local mp = math.floor((5 * doy + 2) / 153)
  local d = doy - math.floor((153 * mp + 2) / 5) + 1
  local m = mp < 10 and mp + 3 or mp - 9
  local y = yoe + era * 400 + (m <= 2 and 1 or 0)
  return string.format("%04d-%02d-%02d", y, m, d)
end

local function bump(t, k, n)
  t[k] = (t[k] or 0) + (n or 1)
end

local function stats(context, payload)
  if context.user_id and context.user_id ~= "" then error("server only") end
  local out = { games = 0, players = 0, by_kind = {}, by_day = {}, by_os = {}, ai = {}, ai_decks = {}, lessons = {},
    duels = { games = 0, desync = 0, first_won = 0, reasons = {}, classes = {} }, versions = {} }
  local seen = {}
  local cursor = nil
  repeat
    local objs, next_cursor = nk.storage_list(SYSTEM, COLLECTION, 100, cursor)
    for _, o in ipairs(objs or {}) do
      local v = o.value or {}
      out.games = out.games + 1
      bump(out.by_kind, v.kind or "?")
      bump(out.by_day, day_of(v.t))
      if v.kind == "duel" then
        local d = out.duels
        d.games = d.games + 1
        bump(d.reasons, v.reason or "?")
        if v.desync then d.desync = d.desync + 1 end
        if v.first_won then d.first_won = d.first_won + 1 end
        for _, pl in ipairs(v.players or {}) do
          seen[pl.p or "?"] = true
          local c = d.classes[pl.cls or "?"] or { games = 0, wins = 0 }
          c.games = c.games + 1
          if pl.won then c.wins = c.wins + 1 end
          d.classes[pl.cls or "?"] = c
        end
      else
        seen[v.p or "?"] = true
        bump(out.by_os, v.os or "?")
        bump(out.versions, v.v or "?")
        if v.kind == "lesson" then
          local l = out.lessons[v.lesson or "?"] or { games = 0, wins = 0 }
          l.games = l.games + 1
          if v.result == "win" then l.wins = l.wins + 1 end
          out.lessons[v.lesson or "?"] = l
        else
          local c = out.ai[v.cls or "?"] or { games = 0, wins = 0, turns = 0, secs = 0, conceded = 0, hand = 0 }
          c.games = c.games + 1
          if v.result == "win" then c.wins = c.wins + 1 end
          if v.conceded then c.conceded = c.conceded + 1 end
          c.turns = c.turns + (v.turns or 0)
          c.secs = c.secs + (v.secs or 0)
          c.hand = c.hand + (v.hand or 0)
          out.ai[v.cls or "?"] = c
          local dk = out.ai_decks[v.deck or "?"] or { games = 0, wins = 0 }
          dk.games = dk.games + 1
          if v.result == "win" then dk.wins = dk.wins + 1 end
          out.ai_decks[v.deck or "?"] = dk
        end
      end
    end
    cursor = next_cursor
  until cursor == nil or cursor == ""
  for _ in pairs(seen) do out.players = out.players + 1 end
  return nk.json_encode(out)
end
nk.register_rpc(stats, "dantes_stats")

return M
