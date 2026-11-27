-- Fish & Partners: desk-to-desk messages
-- One place for every hidden addon message the desks send each other:
--   * picks the right channel (party, raid, or instance chat for Group Finder groups)
--   * paces messages under the game's limit (about 10 at once, then 1 per second)
--     and merges or replaces queued ones, so a loot burst can't crowd anything out
--   * records what the game answered, so /fp sync can say exactly what's wrong
--   * turns a sender's name into the same name the party board uses

local _, ns = ...
local CM = {}
ns.Comm = CM

CM.PREFIX = "FPWM1"
local PREFIX = CM.PREFIX
local function getSend() return (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage end

CM.stats = { sent = 0, failed = 0, heard = 0, rejected = 0, lastFail = nil, lastFailT = nil, from = {}, unknown = {} }
local queue = {}        -- { msg, chan, target, tag }
local tokens, MAXTOK, REGEN = 6, 6, 1.2 -- stay safely under the game's 10 / 1 per second

local RESULT = {
    [0] = "Success", [1] = "InvalidPrefix", [2] = "InvalidMessage", [3] = "AddonMessageThrottle",
    [4] = "InvalidChatType", [5] = "NotInGroup", [6] = "TargetRequired", [7] = "InvalidChannel",
    [8] = "ChannelThrottle", [9] = "GeneralError", [10] = "NotInGuild", [11] = "AddOnMessageLockdown",
    [12] = "TargetOffline",
}
local EXPLAIN = {
    AddonMessageThrottle = "too many messages at once (the desk retries)",
    ChannelThrottle = "too many messages at once (the desk retries)",
    NotInGroup = "you're not in a group the game will deliver to",
    InvalidChatType = "the game refused the group channel",
    AddOnMessageLockdown = "the game blocks addon messages here (e.g. inside an instance)",
    GeneralError = "the game refused the message",
}

function CM.Registered()
    if C_ChatInfo and C_ChatInfo.IsAddonMessagePrefixRegistered then
        local ok, r = pcall(C_ChatInfo.IsAddonMessagePrefixRegistered, PREFIX)
        if ok then return r end
    end
    return CM.registered
end

local function register()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        local ok, r = pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
        CM.registered = ok and (r ~= false and r ~= 2) -- 2 = MaxPrefixes on some clients
    elseif RegisterAddonMessagePrefix then
        CM.registered = pcall(RegisterAddonMessagePrefix, PREFIX)
    end
end
register() -- at load, so nothing is missed before login

-- Trial and veteran accounts can't send addon messages on WoW Forever (since 1.60.1)
function CM.Restricted()
    for _, f in ipairs({ "IsTrialAccount", "IsVeteranTrialAccount" }) do
        local fn = _G[f]
        if fn then
            local ok, r = pcall(fn)
            if ok and r then return f == "IsTrialAccount" and "trial" or "veteran" end
        end
    end
end

-- The group channel the game will deliver to
function CM.GroupChannel()
    if not (IsInGroup and IsInGroup()) then return nil end
    local home = LE_PARTY_CATEGORY_HOME and IsInGroup(LE_PARTY_CATEGORY_HOME)
    local inst = LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
    if inst and not home then return "INSTANCE_CHAT" end
    return (IsInRaid and IsInRaid()) and "RAID" or "PARTY"
end

-- Same names as the party board: "Name" for your realm, "Name-Realm" for others
function CM.Who(sender)
    if not sender or sender == "" then return nil end
    local roster = ns.Party and ns.Party.Roster() or {}
    if roster[sender] then return sender end
    local base, realm = sender:match("^([^%-]+)%-(.+)$")
    if not base then return sender end
    if roster[base] then return base end
    for key in pairs(roster) do
        local kb, kr = key:match("^([^%-]+)%-(.+)$")
        if kb == base and kr and kr:gsub("[%s']", "") == realm:gsub("[%s']", "") then return key end
    end
    local mine = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName() or ""):gsub("[%s']", "")
    if realm == mine then return base end
    return sender
end

function CM.IsMe(sender)
    local me = UnitName("player")
    return sender == me or (sender and sender:match("^([^%-]+)") == me and CM.Who(sender) == me)
end

local function deliver(item)
    local send = getSend()
    if not send then return true end
    if not CM.Registered() then register() end
    local ok, r = pcall(send, PREFIX, item.msg, item.chan, item.target)
    local code
    if not ok then code = "GeneralError"
    elseif r == nil or r == true or r == 0 then code = "Success"
    elseif r == false then code = "GeneralError"
    else code = RESULT[r] or tostring(r) end
    if code == "Success" then
        CM.stats.sent = CM.stats.sent + 1
        return true
    end
    if code == "AddonMessageThrottle" or code == "ChannelThrottle" then return false, true end -- retry later
    CM.stats.failed = CM.stats.failed + 1
    CM.stats.lastFail, CM.stats.lastFailT, CM.stats.lastFailChan = code, time(), item.chan
    return true -- give up on this one
end

local function pump()
    tokens = math.min(MAXTOK, tokens + 0.25 / REGEN)
    while #queue > 0 and tokens >= 1 do
        local item = queue[1]
        local done, retry = deliver(item)
        if retry then tokens = 0; break end
        table.remove(queue, 1)
        tokens = tokens - 1
    end
end
C_Timer.NewTicker(0.25, pump)

-- Send to the group (chan nil) or a channel / whisper.
-- tag: a queued message with the same tag is replaced (latest wins), e.g. session totals.
function CM:Send(msg, chan, target, tag)
    chan = chan or CM.GroupChannel()
    if not chan then return end
    if tag then
        for _, q in ipairs(queue) do
            if q.tag == tag and q.chan == chan then q.msg, q.target = msg, target; return end
        end
    end
    queue[#queue + 1] = { msg = msg, chan = chan, target = target, tag = tag }
    if #queue > 40 then table.remove(queue, 1) end
    pump()
end

-- Merge small records into as few messages as possible: kind;rec;rec;...
local batches = {}
function CM:SendBatched(kind, record)
    local b = batches[kind]
    if not b then
        b = {}
        batches[kind] = b
        C_Timer.After(1, function()
            batches[kind] = nil
            local cur = kind
            for _, r in ipairs(b) do
                if #cur + 1 + #r > 250 then CM:Send(cur); cur = kind end
                cur = cur .. ";" .. r
            end
            if cur ~= kind then CM:Send(cur) end
        end)
    end
    b[#b + 1] = record
end

ns:On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
    if prefix ~= PREFIX then return end
    if CM.IsMe(sender) then return end
    CM.stats.heard = CM.stats.heard + 1
    local who = CM.Who(sender) or "?"
    local roster = ns.Party and ns.Party.Roster() or {}
    local f = CM.stats.from[who] or { n = 0 }
    f.n, f.t, f.chan, f.kind = f.n + 1, time(), channel, type(text) == "string" and text:match("^(%a)") or "?"
    if not roster[who] and channel ~= "GUILD" and channel ~= "WHISPER" then
        f.outside = true
        CM.stats.unknown[sender] = time()
    end
    CM.stats.from[who] = f
end)

ns:OnInit(function()
    register()
    local r = CM.Restricted()
    if r then
        C_Timer.After(12, function()
            ns.Print(ns.Color("amber", "Heads up: ") .. "this is a " .. r .. " account. WoW Forever doesn't let " .. r ..
                " accounts send addon messages, so friends' desks can't hear yours (you can still hear theirs). " ..
                "Party sync and group loot rules need a full account on at least one side.")
        end)
    end
end)

-- /fp sync
function CM:Print()
    local P = ns.Print
    P(ns.Color("orange", "DESK SYNC"))
    P("Channel: " .. (CM.GroupChannel() or ns.Color("grey", "not in a group")) ..
        "   ·   Listening: " .. (CM.Registered() and ns.Color("green", "yes") or ns.Color("red", "NO (prefix not registered)")))
    local r = CM.Restricted()
    if r then P(ns.Color("red", "Your account is a " .. r .. " account: WoW Forever blocks it from sending addon messages.")) end
    P(("Sent: %d   ·   Failed: %d   ·   Waiting: %d   ·   Heard: %d"):format(CM.stats.sent, CM.stats.failed, #queue, CM.stats.heard))
    if CM.stats.lastFail then
        P(ns.Color("red", "Last failure: ") .. CM.stats.lastFail .. " on " .. (CM.stats.lastFailChan or "?") ..
            ns.Color("grey", " (" .. date("%H:%M", CM.stats.lastFailT) .. ") " .. (EXPLAIN[CM.stats.lastFail] or "")))
    end
    local roster = ns.Party and ns.Party.Roster() or {}
    local any = false
    for name in pairs(roster) do
        any = true
        local f = CM.stats.from[name]
        if f then
            P("  " .. name .. ": " .. ns.Color("green", "heard " .. f.n .. "x") .. ns.Color("grey", ", last " .. (time() - f.t) .. "s ago on " .. tostring(f.chan)))
        else
            P("  " .. name .. ": " .. ns.Color("grey", "nothing heard (not running Fish & Partners 2.1+, or their messages can't get through)"))
        end
    end
    if not any then P(ns.Color("grey", "  (no group members)")) end
    for sender in pairs(CM.stats.unknown) do
        P(ns.Color("amber", "  Heard from " .. sender .. " but couldn't match them to your group.") .. ns.Color("grey", " Please report this."))
    end
    P(ns.Color("grey", "Both of you: type /fp sync. A ping was just sent; replies show up above within a few seconds if you run it again."))
    CM:Send("I;" .. (ns.VERSION or "dev"))
end

-- ping / pong so /fp sync can prove the link works both ways
ns:On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
    if prefix ~= PREFIX or type(text) ~= "string" or CM.IsMe(sender) then return end
    if text:sub(1, 2) == "I;" then
        CM:Send("O;" .. (ns.VERSION or "dev"), nil, nil, "pong")
        ns.Print(ns.Color("grey", "Desk sync check from " .. (CM.Who(sender) or sender) .. ": answered."))
    elseif text:sub(1, 2) == "O;" then
        ns.Print(ns.Color("green", "Desk sync: ") .. (CM.Who(sender) or sender) .. " hears you, and you hear them " ..
            ns.Color("grey", "(v" .. (text:sub(3) or "?") .. ")."))
    end
end)
