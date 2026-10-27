--[[
DantesCards - 1v1 duel match handler "dantes_match" (authoritative relay, Nakama Lua runtime).

The server does NOT run the card rules (yet): both clients run the deterministic rules engine from
the shared seed and the ordered event stream below. The server owns: who plays, turn order, the
turn timer + rope, disconnect grace / forfeit, the seed and the first player, and the final result.

Created by the matchmaker hook in dantes_core.lua (params: players = {uidA, uidB}, names = {..}).
Only those two users may join. Tick rate 5 Hz.

JOIN METADATA (first join; ignored on a rejoin): deck = '<JSON string {"cls":"pilgrim","cards":[ids]}>', name = "<display name>"
  cls: 1-32 chars [a-z0-9_]; cards: 1-40 ids, each 1-40 chars [a-z0-9_]. A bad deck rejects the join (reason says why).
  name: optional (max 32 chars), else the account display name, else the username.

PHASES: waiting (for both joins) -> mulligan (MULLIGAN_SEC, simultaneous) -> play (turns) -> over.

OP CODES (payloads are JSON objects; *_ms are milliseconds)
client -> server
  1  ACTION    any JSON object (the game action). Only the active player; else ERROR not_your_turn.
  2  END_TURN  {}            active player ends the turn.
  3  CONCEDE   {}            the sender loses.
  6  MULLIGAN  {replace = [hand indices 0-4]}  once per player, only in the mulligan phase.
  4  RESULT    {winner}      the rules engine says the game is over: winner = user_id, or "" for a draw.
                             Both clients send it: if they agree -> END reason "result"; if they disagree
                             -> END reason "desync" (no winner); if only one arrives, it is accepted after 10 s.
  5  RESYNC    {}            ask for the full state again (server answers RESYNC to the sender).
server -> client
  101 START   {seed, players=[uidA, uidB], names=[..], decks=[{cls, cards}, {cls, cards}] (same order as players),
               first, phase="mulligan", mulligan_ms, turn=0, turn_ms, rope_ms, server_time_ms}
              sent when both players have joined (within 30 s of the match creation, else END no_show).
              The mulligan phase starts: ACTION / END_TURN get ERROR not_started until TURN 1.
  108 MULLIGAN {seq, from, data}  a player's mulligan (data = their {replace} verbatim), relayed to both. When both
              are in, or after mulligan_ms (a missing one is sent as {"replace":[]} from that player), TURN 1 follows
              (reason "start", active = first) and the turn timer starts.
  102 ACTION  {seq, turn, from, data}   relayed to BOTH players (sender included). Apply events in seq order.
  103 TURN    {seq, turn, active, reason ("start" | "end_turn" | "timeout"), turn_ms, rope_ms}
              a new turn starts now; the timer is turn_ms, then the rope (rope_ms), then the server ends it.
  104 ROPE    {turn, active, rope_ms}  the rope started: the turn ends in rope_ms.
  105 STATUS  {user_id, connected, grace_ms}  the opponent dropped (grace_ms until forfeit) / came back.
  106 END     {winner, loser, reason}   winner/loser = user_id or "" (draw / cancelled). reasons:
              "result", "desync", "concede", "disconnect", "abandoned", "no_show", "time_limit".
  107 RESYNC  {start = <START payload, decks included>, events = [<MULLIGAN/TURN/ACTION payloads in seq order>],
               seq, phase, turn, active, remaining_ms (mulligan phase: until it ends; play: until the turn
               ends, rope included), roped, over}
              sent to a player who (re)joins after START, or asks with RESYNC.
  199 ERROR   {code, op}  codes: "not_your_turn", "not_started", "bad_payload", "too_many_actions",
              "not_in_mulligan", "already_sent", "unknown_op".

seq is one counter for MULLIGAN, TURN and ACTION events (1, 2, 3, ...): both clients see the same order.
--]]

local nk = require("nakama")

local TICK_RATE = 5
local TURN_SEC = 75            -- turn timer, then the rope
local ROPE_SEC = 15            -- rope: after it the server ends the turn
local GRACE_SEC = 30           -- disconnect grace before forfeit
local JOIN_SEC = 30            -- both players must join within this
local MULLIGAN_SEC = 30        -- simultaneous mulligan before turn 1
local RESULT_WAIT_SEC = 10     -- wait for the second RESULT report
local MAX_MATCH_SEC = 90 * 60  -- hard cap on a duel
local MAX_EVENTS = 5000        -- event log cap (resync)
local MAX_ACTIONS_PER_TURN = 300

local OP_ACTION, OP_END_TURN, OP_CONCEDE, OP_RESULT, OP_RESYNC_REQ, OP_MULLIGAN = 1, 2, 3, 4, 5, 6
local OP_START, OP_EV_ACTION, OP_TURN, OP_ROPE, OP_STATUS, OP_END, OP_RESYNC, OP_EV_MULLIGAN, OP_ERROR = 101, 102, 103, 104, 105, 106, 107, 108, 199
local ID_PATTERN = "^[a-z0-9_]+$"

local M = {}

local function hex_number(s)
  return tonumber(s, 16) or 0
end

local function label_of(state)
  return nk.json_encode({ mode = "duel", a = state.players[1], b = state.players[2], over = state.over and "T" or "F" })
end

local function other(state, uid)
  if state.players[1] == uid then return state.players[2] end
  return state.players[1]
end

local function send(dispatcher, state, op, payload, uid)
  local data = type(payload) == "string" and payload or nk.json_encode(payload)
  if uid then
    local p = state.presences[uid]
    if p then dispatcher.broadcast_message(op, data, { p }, nil, true) end
  else
    dispatcher.broadcast_message(op, data, nil, nil, true)
  end
end

-- returns the deck table {cls, cards}, or nil + the reason
local function parse_deck(raw)
  if type(raw) ~= "string" or raw == "" then return nil, "missing deck" end
  if #raw > 4096 then return nil, "deck too large" end
  local ok, d = pcall(nk.json_decode, raw)
  if not ok or type(d) ~= "table" then return nil, "deck is not valid JSON" end
  if type(d.cls) ~= "string" or #d.cls < 1 or #d.cls > 32 or not string.match(d.cls, ID_PATTERN) then
    return nil, "bad deck class"
  end
  if type(d.cards) ~= "table" or #d.cards < 1 or #d.cards > 40 then return nil, "deck must have 1-40 cards" end
  local cards = {}
  for i, c in ipairs(d.cards) do
    if type(c) ~= "string" or #c > 40 or not string.match(c, ID_PATTERN) then
      return nil, "bad card id at index " .. (i - 1)
    end
    cards[i] = c
  end
  return { cls = d.cls, cards = cards }
end

local function display_name(uid, wanted)
  if type(wanted) == "string" then
    local n = string.sub(string.gsub(wanted, "%c", ""), 1, 32)
    if n ~= "" then return n end
  end
  local ok, acc = pcall(nk.account_get_id, uid)
  if ok and acc and acc.user then
    if acc.user.display_name and acc.user.display_name ~= "" then return acc.user.display_name end
    return acc.user.username or ""
  end
  return ""
end

local function remaining_ms(state, tick)
  local left = state.turn_end_tick - tick
  if state.phase == "mulligan" then left = state.mulligan_end_tick - tick end
  if left < 0 then left = 0 end
  return math.floor(left * 1000 / TICK_RATE)
end

local function log_event(state, json)
  if #state.events < MAX_EVENTS then
    table.insert(state.events, json)
  end
end

local function finish(dispatcher, state, tick, winner, reason)
  if state.over then return end
  state.over = true
  state.end_tick = tick
  local loser = ""
  if winner ~= "" then loser = other(state, winner) end
  send(dispatcher, state, OP_END, { winner = winner, loser = loser, reason = reason })
  dispatcher.match_label_update(label_of(state))
  nk.logger_info(string.format("dantes_match end winner=%s reason=%s turn=%d", winner, reason, state.turn))
end

local function start_turn(dispatcher, state, tick, active, reason)
  state.turn = state.turn + 1
  state.active = active
  state.turn_start_tick = tick
  state.rope_tick = tick + TURN_SEC * TICK_RATE
  state.turn_end_tick = state.rope_tick + ROPE_SEC * TICK_RATE
  state.roped = false
  state.actions_this_turn = 0
  state.phase = "play"
  state.seq = state.seq + 1
  local ev = nk.json_encode({ seq = state.seq, turn = state.turn, active = active, reason = reason,
    turn_ms = TURN_SEC * 1000, rope_ms = ROPE_SEC * 1000 })
  log_event(state, ev)
  send(dispatcher, state, OP_TURN, ev)
end

local function relay_mulligan(dispatcher, state, uid, raw)
  state.mulligans[uid] = true
  state.seq = state.seq + 1
  local ev = '{"seq":' .. state.seq .. ',"from":' .. nk.json_encode(uid) .. ',"data":' .. raw .. '}'
  log_event(state, ev)
  send(dispatcher, state, OP_EV_MULLIGAN, ev)
end

-- both mulligans in, or time up: the missing ones count as {"replace":[]}, then turn 1
local function end_mulligan(dispatcher, state, tick)
  for _, uid in ipairs(state.players) do
    if not state.mulligans[uid] then relay_mulligan(dispatcher, state, uid, '{"replace":[]}') end
  end
  start_turn(dispatcher, state, tick, state.first, "start")
end

local function resync_payload(state, tick)
  -- events are stored as JSON strings: splice them into the array verbatim
  return '{"start":' .. (state.start_json or "null") ..
    ',"events":[' .. table.concat(state.events, ",") .. ']' ..
    ',"seq":' .. state.seq .. ',"phase":' .. nk.json_encode(state.phase) .. ',"turn":' .. state.turn ..
    ',"active":' .. nk.json_encode(state.active or "") ..
    ',"remaining_ms":' .. remaining_ms(state, tick) ..
    ',"roped":' .. tostring(state.roped) .. ',"over":' .. tostring(state.over) .. '}'
end

function M.match_init(context, params)
  local players = params.players or {}
  local names = params.names or {}
  local u = string.gsub(nk.uuid_v4(), "-", "")
  local seed = hex_number(string.sub(u, 1, 8))
  local first = (hex_number(string.sub(u, 9, 10)) % 2) + 1
  local state = {
    players = { players[1], players[2] },
    names = { names[1] or "", names[2] or "" },
    seed = seed,
    first = players[first],
    presences = {},
    connected = {},
    grace_until = {},
    joined_once = {},
    decks = {},
    mulligans = {},
    phase = "waiting",
    turn_end_tick = 0,
    mulligan_end_tick = 0,
    roped = false,
    started = false,
    over = false,
    end_tick = 0,
    created_tick = nil,
    turn = 0,
    active = nil,
    seq = 0,
    events = {},
    reports = {},
    first_report_tick = nil,
  }
  return state, TICK_RATE, label_of(state)
end

function M.match_join_attempt(context, dispatcher, tick, state, presence, metadata)
  if state.over then
    return state, false, "match is over"
  end
  if presence.user_id ~= state.players[1] and presence.user_id ~= state.players[2] then
    return state, false, "not a player of this match"
  end
  local uid = presence.user_id
  if state.decks[uid] == nil then   -- first join: the deck is required (a rejoin keeps the first one)
    local deck, why = parse_deck(metadata and metadata.deck)
    if not deck then
      return state, false, why
    end
    state.decks[uid] = deck
    local i = (uid == state.players[1]) and 1 or 2
    state.names[i] = display_name(uid, metadata and metadata.name)
  end
  return state, true
end

function M.match_join(context, dispatcher, tick, state, presences)
  for _, p in ipairs(presences) do
    local uid = p.user_id
    state.presences[uid] = p
    state.connected[uid] = true
    state.grace_until[uid] = nil
    state.joined_once[uid] = true
    if state.started then
      send(dispatcher, state, OP_STATUS, { user_id = uid, connected = true, grace_ms = 0 }, other(state, uid))
      send(dispatcher, state, OP_RESYNC, resync_payload(state, tick), uid)
    end
  end
  if not state.started and state.connected[state.players[1]] and state.connected[state.players[2]] then
    state.started = true
    state.start_tick = tick
    state.phase = "mulligan"
    state.mulligan_end_tick = tick + MULLIGAN_SEC * TICK_RATE
    state.start_json = nk.json_encode({ seed = state.seed, players = state.players, names = state.names,
      decks = { state.decks[state.players[1]], state.decks[state.players[2]] },
      first = state.first, phase = "mulligan", mulligan_ms = MULLIGAN_SEC * 1000, turn = 0,
      turn_ms = TURN_SEC * 1000, rope_ms = ROPE_SEC * 1000, server_time_ms = nk.time() })
    send(dispatcher, state, OP_START, state.start_json)
    nk.logger_info(string.format("dantes_match start %s vs %s first=%s", state.players[1], state.players[2], state.first))
  end
  return state
end

function M.match_leave(context, dispatcher, tick, state, presences)
  for _, p in ipairs(presences) do
    local uid = p.user_id
    local cur = state.presences[uid]
    if cur == nil or cur.session_id == p.session_id then   -- a newer socket of the same user replaced it: ignore
      state.presences[uid] = nil
      state.connected[uid] = false
      if state.started and not state.over then
        state.grace_until[uid] = tick + GRACE_SEC * TICK_RATE
        send(dispatcher, state, OP_STATUS, { user_id = uid, connected = false, grace_ms = GRACE_SEC * 1000 }, other(state, uid))
      end
    end
  end
  return state
end

local function handle(dispatcher, state, tick, m)
  local uid = m.sender.user_id
  local op = m.op_code
  if state.over then
    if op == OP_RESYNC_REQ then send(dispatcher, state, OP_RESYNC, resync_payload(state, tick), uid) end
    return
  end
  if op == OP_RESYNC_REQ then
    send(dispatcher, state, OP_RESYNC, resync_payload(state, tick), uid)
    return
  end
  if not state.started then
    send(dispatcher, state, OP_ERROR, { code = "not_started", op = op }, uid)
    return
  end
  local raw = m.data or ""
  if raw == "" then raw = "{}" end
  local ok, body = pcall(nk.json_decode, raw)
  if not ok or type(body) ~= "table" then
    send(dispatcher, state, OP_ERROR, { code = "bad_payload", op = op }, uid)
    return
  end
  if op == OP_MULLIGAN then
    if state.phase ~= "mulligan" then
      send(dispatcher, state, OP_ERROR, { code = "not_in_mulligan", op = op }, uid)
      return
    end
    if state.mulligans[uid] then
      send(dispatcher, state, OP_ERROR, { code = "already_sent", op = op }, uid)
      return
    end
    local r = body.replace
    if type(r) ~= "table" or #r > 5 then
      send(dispatcher, state, OP_ERROR, { code = "bad_payload", op = op }, uid)
      return
    end
    local seen = {}
    for _, i in ipairs(r) do
      if type(i) ~= "number" or i ~= math.floor(i) or i < 0 or i > 4 or seen[i] then
        send(dispatcher, state, OP_ERROR, { code = "bad_payload", op = op }, uid)
        return
      end
      seen[i] = true
    end
    relay_mulligan(dispatcher, state, uid, raw)
    if state.mulligans[state.players[1]] and state.mulligans[state.players[2]] then
      end_mulligan(dispatcher, state, tick)
    end
  elseif op == OP_ACTION or op == OP_END_TURN then
    if state.phase ~= "play" then
      send(dispatcher, state, OP_ERROR, { code = "not_started", op = op }, uid)
      return
    end
    if uid ~= state.active then
      send(dispatcher, state, OP_ERROR, { code = "not_your_turn", op = op }, uid)
      return
    end
    if op == OP_END_TURN then
      start_turn(dispatcher, state, tick, other(state, uid), "end_turn")
      return
    end
    state.actions_this_turn = state.actions_this_turn + 1
    if state.actions_this_turn > MAX_ACTIONS_PER_TURN then
      send(dispatcher, state, OP_ERROR, { code = "too_many_actions", op = op }, uid)
      return
    end
    state.seq = state.seq + 1
    -- relay the client's JSON verbatim inside the envelope
    local ev = '{"seq":' .. state.seq .. ',"turn":' .. state.turn .. ',"from":' .. nk.json_encode(uid) .. ',"data":' .. raw .. '}'
    log_event(state, ev)
    send(dispatcher, state, OP_EV_ACTION, ev)
  elseif op == OP_CONCEDE then
    finish(dispatcher, state, tick, other(state, uid), "concede")
  elseif op == OP_RESULT then
    local w = body.winner
    if type(w) ~= "string" or (w ~= "" and w ~= state.players[1] and w ~= state.players[2]) then
      send(dispatcher, state, OP_ERROR, { code = "bad_payload", op = op }, uid)
      return
    end
    state.reports[uid] = w
    local ra, rb = state.reports[state.players[1]], state.reports[state.players[2]]
    if ra ~= nil and rb ~= nil then
      if ra == rb then finish(dispatcher, state, tick, ra, "result")
      else finish(dispatcher, state, tick, "", "desync") end
    elseif state.first_report_tick == nil then
      state.first_report_tick = tick
    end
  else
    send(dispatcher, state, OP_ERROR, { code = "unknown_op", op = op }, uid)
  end
end

function M.match_loop(context, dispatcher, tick, state, messages)
  if state.created_tick == nil then state.created_tick = tick end
  if state.over then
    -- let the END message go out, then close the match
    if tick - state.end_tick > TICK_RATE * 2 then return nil end
    for _, m in ipairs(messages) do handle(dispatcher, state, tick, m) end
    return state
  end

  for _, m in ipairs(messages) do
    handle(dispatcher, state, tick, m)
    if state.over then return state end
  end

  if not state.started then
    if tick - state.created_tick > JOIN_SEC * TICK_RATE then
      finish(dispatcher, state, tick, "", "no_show")
    end
    return state
  end

  -- disconnects
  local a, b = state.players[1], state.players[2]
  if not state.connected[a] and not state.connected[b] then
    finish(dispatcher, state, tick, "", "abandoned")
    return state
  end
  for _, uid in ipairs(state.players) do
    local g = state.grace_until[uid]
    if g and tick >= g and not state.connected[uid] then
      finish(dispatcher, state, tick, other(state, uid), "disconnect")
      return state
    end
  end

  -- a single RESULT report is accepted after RESULT_WAIT_SEC
  if state.first_report_tick and tick - state.first_report_tick > RESULT_WAIT_SEC * TICK_RATE then
    local w = state.reports[a]
    if w == nil then w = state.reports[b] end
    finish(dispatcher, state, tick, w or "", "result")
    return state
  end

  if tick - state.start_tick > MAX_MATCH_SEC * TICK_RATE then
    finish(dispatcher, state, tick, "", "time_limit")
    return state
  end

  if state.phase == "mulligan" then
    if tick >= state.mulligan_end_tick then end_mulligan(dispatcher, state, tick) end
    return state
  end

  -- turn timer + rope
  if not state.roped and tick >= state.rope_tick then
    state.roped = true
    send(dispatcher, state, OP_ROPE, { turn = state.turn, active = state.active, rope_ms = ROPE_SEC * 1000 })
  end
  if tick >= state.turn_end_tick then
    start_turn(dispatcher, state, tick, other(state, state.active), "timeout")
  end
  return state
end

function M.match_terminate(context, dispatcher, tick, state, grace_seconds)
  if not state.over then
    finish(dispatcher, state, tick, "", "abandoned")
  end
  return state
end

function M.match_signal(context, dispatcher, tick, state, data)
  return state, ""
end

return M
