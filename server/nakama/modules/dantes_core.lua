--[[
DantesCards - core module (Nakama Lua runtime, instance "dantes-cards", port 7450).

Auth: device auth (and Google, once a client id is configured) only; email / custom / Facebook /
Apple / Game Center authentication and linking are rejected by before-hooks. Steam is added later
(it needs DantesCards' own Steam app id + publisher key in the instance config).

RPCs (all need a user session):
  dantes_ping          {}  -> {ok, server, time_ms, user_id}
  dantes_active_match  {}  -> {match_id}  ("" when none) the duel this user is still part of,
                              to rejoin it after an app restart / reconnect.

Matchmaking: clients add a matchmaker ticket (query "*", min 2, max 2, string property
mode = "duel"); the hook below creates an authoritative "dantes_match" for the 2 players and
the matchmaker_matched message carries its match_id: both clients then join it.
--]]

local nk = require("nakama")

-- Reject every auth / link flow DantesCards does not use (yet).
local function reject(context, payload)
  return nil
end
for _, api in ipairs({
  "AuthenticateEmail", "AuthenticateCustom", "AuthenticateFacebook", "AuthenticateFacebookInstantGame",
  "AuthenticateApple", "AuthenticateGameCenter",
  "LinkEmail", "LinkCustom", "LinkFacebook", "LinkFacebookInstantGame", "LinkApple", "LinkGameCenter",
}) do
  nk.register_req_before(reject, api)
end

local function ping(context, payload)
  return nk.json_encode({ ok = true, server = "dantes-cards", time_ms = nk.time(), user_id = context.user_id or "" })
end
nk.register_rpc(ping, "dantes_ping")

local function active_match(context, payload)
  local uid = context.user_id
  if not uid then
    error("session required")
  end
  -- the label index refreshes about once per second: a duel created < 1 s ago may not be listed yet
  local q = '+label.mode:duel +label.over:F label.a:"' .. uid .. '" label.b:"' .. uid .. '"'
  local matches = nk.match_list(10, true, nil, 0, 2, q)
  for _, m in ipairs(matches or {}) do
    local ok, label = pcall(nk.json_decode, m.label or "")
    if ok and label and (label.a == uid or label.b == uid) and label.over ~= "T" then
      return nk.json_encode({ match_id = m.match_id })
    end
  end
  return nk.json_encode({ match_id = "" })
end
nk.register_rpc(active_match, "dantes_active_match")

local function matchmaker_matched(context, matched_users)
  if #matched_users ~= 2 then
    return nil
  end
  local a = matched_users[1].presence
  local b = matched_users[2].presence
  if a.user_id == b.user_id then
    return nil   -- same account queued twice (two devices): no match
  end
  return nk.match_create("dantes_match", {
    players = { a.user_id, b.user_id },
    names = { a.username, b.username },
  })
end
nk.register_matchmaker_matched(matchmaker_matched)
