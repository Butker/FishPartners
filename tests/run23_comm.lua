-- 2.1.2 desk-to-desk messages: channels, throttling, names, failures, diagnostics
dofile(TESTS .. "/mock.lua")
local grouped, instOnly = true, false
local party = { party1 = { "Bob", nil, "WARRIOR" } }
LE_PARTY_CATEGORY_HOME, LE_PARTY_CATEGORY_INSTANCE = 1, 2
IsInGroup = function(cat)
  if cat == 1 then return grouped and not instOnly end
  if cat == 2 then return grouped and instOnly end
  return grouped
end
IsInRaid = function() return false end
GetNumSubgroupMembers = function() return 1 end
UnitExists = function(u) return party[u] ~= nil or u == "player" end
UnitIsUnit = function(a, b) return a == b end
UnitName = function(u) if party[u] then return party[u][1], party[u][2] end return "Fishbro" end
UnitClass = function(u) if party[u] then return "x", party[u][3] end return "Mage", "MAGE" end
GetRealmName = function() return "Living Flame" end
GetNormalizedRealmName = function() return "LivingFlame" end
RAID_CLASS_COLORS.WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }
LOOT_ITEM = "%s receives loot: %s." LOOT_ITEM_MULTIPLE = "%s receives loot: %sx%d."
local trial = false
IsTrialAccount = function() return trial end
local sent, mode, throttleLeft = {}, "ok", 0
C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end,
  IsAddonMessagePrefixRegistered = function() return true end,
  SendAddonMessage = function(p, m, c, t)
    if mode == "lockdown" then return 11 end
    if throttleLeft > 0 then throttleLeft = throttleLeft - 1; return 3 end
    sent[#sent + 1] = { m = m, c = c }; return 0
  end }
local printed = {}
local ns = {}
local toc = io.open(ADDON_ROOT .. "/FishPartners.toc"):read("a")
for line in toc:gmatch("[^\r\n]+") do if not line:match("^##") and line:match("%.lua$") then
  assert(loadfile(ADDON_ROOT .. "/" .. line:gsub("\\", "/")))("FishPartners", ns) end end
fire("PLAYER_LOGIN"); advance(25)
local oldPrint = ns.Print; ns.Print = function(m) printed[#printed + 1] = m; oldPrint(m) end
local function check(name, cond, detail) print((cond and "PASS " or "FAIL ") .. name .. (detail and ("  [" .. detail .. "]") or "")) end
local CM = ns.Comm

-- names: same-realm sender arrives as Name-NormalizedRealm
check("same realm sender -> board name", CM.Who("Bob-LivingFlame") == "Bob", tostring(CM.Who("Bob-LivingFlame")))
check("me with realm is me", CM.IsMe("Fishbro-LivingFlame"))
party.party2 = { "Ann", "Pyrewood Village", "MAGE" }; GetNumSubgroupMembers = function() return 2 end
check("other realm with spaces matched", CM.Who("Ann-PyrewoodVillage") == "Ann-Pyrewood Village", tostring(CM.Who("Ann-PyrewoodVillage")))

-- session totals from Bob (same realm, realm suffix in sender) reach the board
SlashCmdList.FISHPARTNERS("start"); advance(2)
fire("CHAT_MSG_ADDON", "FPWM1", "S;50000;20000;0;30000;600", "PARTY", "Bob-LivingFlame"); advance(1)
local s = ns.cdb.session
check("Bob's session sync accepted", s.party.Bob and s.party.Bob.sync and s.party.Bob.sync.total == 50000)
check("house rules from Bob's S message", s.groupRules == true)

-- channel: Group Finder group -> INSTANCE_CHAT
instOnly = true
check("instance group uses INSTANCE_CHAT", CM.GroupChannel() == "INSTANCE_CHAT", tostring(CM.GroupChannel()))
instOnly = false
check("normal party uses PARTY", CM.GroupChannel() == "PARTY")

-- throttling: game refuses 5 sends, nothing is lost
sent = {}; throttleLeft = 5
for i = 1, 4 do CM:Send("X;" .. i) end
advance(15)
local got = {}
for _, x in ipairs(sent) do if x.m:find("^X;") then got[#got + 1] = x.m end end
check("throttled messages retried in order", table.concat(got, ",") == "X;1,X;2,X;3,X;4", table.concat(got, ","))

-- session totals waiting in the queue are replaced, not stacked
sent = {}; throttleLeft = 100
CM:Send("S;1;0;0;0;0", nil, nil, "S"); CM:Send("S;2;0;0;0;0", nil, nil, "S"); CM:Send("S;3;0;0;0;0", nil, nil, "S")
throttleLeft = 0; advance(5)
local nS = 0
for _, x in ipairs(sent) do if x.m:find("^S;") then nS = nS + 1; got = x.m end end
check("only the latest session total is sent", nS == 1 and got == "S;3;0;0;0;0", nS .. " " .. tostring(got))

-- loot burst: 12 drops share their prices in very few messages
sent = {}
for i = 1, 12 do fire("CHAT_MSG_LOOT", "Bob receives loot: " .. mkLink(i == 1 and 2589 or 2770) .. "x" .. i .. ".") end
for i = 1, 12 do CM:SendBatched("P", ("%d;%d;%d"):format(5000 + i, 100 + i, 20000)) end
advance(6)
local nP, recs = 0, 0
for _, x in ipairs(sent) do if x.m:find("^P;") then nP = nP + 1; local _, c = x.m:gsub(";", ""); recs = recs + c / 3 end end
check("12 prices batched into few messages", nP <= 2 and recs >= 12, nP .. " msgs, " .. recs .. " records")
-- receiving a batched message stores every record
fire("CHAT_MSG_ADDON", "FPWM1", "P;7001;111;" .. math.floor(time() / 86400) .. ";7002;222;" .. math.floor(time() / 86400), "PARTY", "Bob-LivingFlame")
check("batched prices received", s.groupPrices[7001] and s.groupPrices[7002] and s.groupPrices[7002].p == 222)

-- the game refusing a message is recorded and explained
mode = "lockdown"; CM:Send("X;locked"); advance(2); mode = "ok"
check("failure recorded", CM.stats.lastFail == "AddOnMessageLockdown", tostring(CM.stats.lastFail))
printed = {}
SlashCmdList.FISHPARTNERS("sync"); advance(2)
local out = table.concat(printed, "\n"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
check("/fp sync shows the failure", out:find("AddOnMessageLockdown") ~= nil)
check("/fp sync shows Bob was heard", out:find("Bob: heard") ~= nil)
check("/fp sync shows Ann silent", out:find("Ann%-Pyrewood Village: nothing heard") ~= nil)
check("/fp sync shows Bob's session totals", out:find("session totals: received") ~= nil)
check("/fp sync shows house rules state", out:find("House rules: ON") ~= nil, out:match("House rules:[^\n]*"))
check("/fp sync shows the raw sender", out:find("as Bob%-LivingFlame") ~= nil)
local ping = false
for _, x in ipairs(sent) do if x.m:find("^I;") then ping = true end end
check("/fp sync sends a ping", ping)
printed = {}
fire("CHAT_MSG_ADDON", "FPWM1", "O;2.1.2", "PARTY", "Bob-LivingFlame")
check("pong reported", table.concat(printed, " "):find("hears you") ~= nil)
sent = {}
fire("CHAT_MSG_ADDON", "FPWM1", "I;2.1.2", "PARTY", "Bob-LivingFlame"); advance(2)
check("ping answered", sent[1] and sent[1].m:find("^O;") ~= nil)

-- trial accounts get a clear warning
trial = true; printed = {}
SlashCmdList.FISHPARTNERS("sync")
check("trial account explained", table.concat(printed, " "):find("trial account") ~= nil)
trial = false

for _, id in ipairs({ "pnl", "aum", "port", "rpt", "gl", "cmpl" }) do ns:ShowPage(id) end
print("errors:", #ns.errors)
for _, e in ipairs(ns.errors) do print(e.msg or e) end
print("OK23")
