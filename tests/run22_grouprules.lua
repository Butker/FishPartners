-- 2.1 group loot rules: house rules + shared prices (newest scan wins)
dofile(TESTS .. "/mock.lua")
local grouped = false
local party = { party1 = { "Bob", nil, "WARRIOR" } }
IsInGroup = function() return grouped end; IsInRaid = function() return false end
GetNumSubgroupMembers = function() return 1 end
UnitExists = function(u) return party[u] ~= nil or u == "player" end
UnitIsUnit = function(a, b) return a == b end
UnitName = function(u) if party[u] then return party[u][1], party[u][2] end return "Fishbro" end
UnitClass = function(u) if party[u] then return "x", party[u][3] end return "Mage", "MAGE" end
RAID_CLASS_COLORS.WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }
LOOT_ITEM = "%s receives loot: %s." LOOT_ITEM_MULTIPLE = "%s receives loot: %sx%d."
local sent = {}
C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end, SendAddonMessage = function(p, m, c) sent[#sent + 1] = m end }
local ages = { [2589] = 3, [2770] = 0 }
local ns = {}
local toc = io.open(ADDON_ROOT .. "/FishPartners.toc"):read("a")
for line in toc:gmatch("[^\r\n]+") do if not line:match("^##") and line:match("%.lua$") then
  assert(loadfile(ADDON_ROOT .. "/" .. line:gsub("\\", "/")))("FishPartners", ns) end end
Auctionator.API.v1.GetAuctionAgeByItemLink = function(c, l) return ages[tonumber(l:match("item:(%d+)"))] end
fire("PLAYER_LOGIN"); advance(25)
local function check(name, cond, detail) print((cond and "PASS " or "FAIL ") .. name .. (detail and ("  [" .. detail .. "]") or "")) end
local function lastSent(prefix) for i = #sent, 1, -1 do if sent[i]:sub(1, #prefix) == prefix then return sent[i] end end end
local today = math.floor(time() / 86400)
local LINEN, ORE = mkLink(2589), mkLink(2770)

-- personal settings that differ from the house rules
ns.S.otherMargin = 50; ns.S.sessionQuest = false
SlashCmdList.FISHPARTNERS("start"); advance(1)
grouped = true; fire("GROUP_ROSTER_UPDATE"); advance(3)
check("hello sent to the group", lastSent("H;") ~= nil)
fire("CHAT_MSG_LOOT", "Bob receives loot: " .. LINEN .. "x10."); advance(3)
local s = ns.cdb.session
local bob = s.party.Bob
check("no other desk yet: personal rules", not s.groupRules and bob.items[LINEN].unit == 13, tostring(bob.items[LINEN].unit))

-- Bob turns out to run Fish & Partners
fire("CHAT_MSG_ADDON", "FPWM1", "H;2.1.0", "PARTY", "Bob"); advance(2)
check("house rules switch on", s.groupRules == true)
check("earlier loot re-marked with house rules", bob.items[LINEN].unit == 14 and s.partyTape[1].v == 140, bob.items[LINEN].unit .. " / " .. s.partyTape[1].v)
check("bell toast shown", FishPartnersHouseRules and FishPartnersHouseRules:IsShown())

-- my linen drops: my scan (3 days old) is the best the group has, so I share it
fire("CHAT_MSG_LOOT", "You receive loot: " .. LINEN .. "x2."); advance(3)
check("I share my price", lastSent("P;2589;") == ("P;2589;14;" .. (today - 3)), tostring(lastSent("P;2589;")))
-- Bob has a newer scan
fire("CHAT_MSG_ADDON", "FPWM1", "P;2589;20;" .. today, "PARTY", "Bob"); advance(1)
check("newer scan wins for my items", s.items[LINEN].unit == 20, tostring(s.items[LINEN].unit))
check("... and for the party board", bob.items[LINEN].unit == 20)
check("tape re-marked", s.tape[1].v == 40, tostring(s.tape[1].v))
check("tooltip says whose scan", (s.items[LINEN].note or ""):find("Bob") ~= nil, tostring(s.items[LINEN].note))
-- an older price is ignored
fire("CHAT_MSG_ADDON", "FPWM1", "P;2589;9;" .. (today - 5), "PARTY", "Bob"); advance(1)
check("older scan ignored", s.items[LINEN].unit == 20)
-- next drop: my scan is older than Bob's, so I stay quiet
local n = #sent
fire("CHAT_MSG_LOOT", "You receive loot: " .. LINEN .. "."); advance(3)
local said = false
for i = n + 1, #sent do if sent[i]:find("^P;2589") then said = true end end
check("no message when the group has a newer price", not said)

-- same-day scans: the lower price wins on both desks
fire("CHAT_MSG_ADDON", "FPWM1", "P;2770;8;" .. today, "PARTY", "Bob"); advance(1)
fire("CHAT_MSG_LOOT", "You receive loot: " .. ORE .. "x4."); advance(3)
check("same day: lower price kept", s.items[ORE].src == "VND" or s.items[ORE].unit <= 8, s.items[ORE].unit .. " " .. s.items[ORE].src)
check("... and shared so Bob uses it too", lastSent("P;2770;") == ("P;2770;5;" .. today), tostring(lastSent("P;2770;")))

-- house rules: quest gold counts even though my setting is off
s.quest = 5000
check("quest gold counts under house rules", ns.Session:Stats().quest == 5000)
-- portfolio / net worth keep personal rules
check("portfolio uses personal rules", ns.Valuate(LINEN) == 13, tostring(ns.Valuate(LINEN)))

-- off switch
ns.Session:Stop(); ns.S.groupRules = false; ns.Session:Start(); advance(3)
fire("CHAT_MSG_ADDON", "FPWM1", "H;2.1.0", "PARTY", "Bob"); advance(2)
check("setting off: personal rules", not ns.cdb.session.groupRules)
ns.S.groupRules = true
-- Bob leaves: a new session starts with personal rules
party.party1 = nil; fire("GROUP_ROSTER_UPDATE"); advance(3)
ns.Session:Stop(); ns.Session:Start(); advance(3)
check("solo: personal rules", not ns.cdb.session.groupRules)

SlashCmdList.FISHPARTNERS("rules")
for _, id in ipairs({ "pnl", "aum", "port", "rpt", "gl", "cmpl" }) do ns:ShowPage(id) end
print("errors:", #ns.errors)
for _, e in ipairs(ns.errors) do print(e.msg or e) end
print("OK22")
