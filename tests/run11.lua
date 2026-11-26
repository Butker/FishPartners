dofile(TESTS .. "/mock.lua")
local grouped = false
local party = { party1 = {"Bob", nil, "WARRIOR"}, party2 = {"Ann", "OtherRealm", "MAGE"} }
IsInGroup=function() return grouped end; IsInRaid=function() return false end
GetNumSubgroupMembers=function() return 2 end
UnitExists=function(u) return party[u] ~= nil or u=="player" end
UnitIsUnit=function(a,b) return a==b end
local oldUN=UnitName; UnitName=function(u) if party[u] then return party[u][1], party[u][2] end return "Fishbro" end
local oldUC=UnitClass; UnitClass=function(u) if party[u] then return "x", party[u][3] end return "Mage","MAGE" end
RAID_CLASS_COLORS.WARRIOR={r=0.78,g=0.61,b=0.43}
LOOT_ITEM="%s receives loot: %s." LOOT_ITEM_MULTIPLE="%s receives loot: %sx%d."
local sent = {}
C_ChatInfo={RegisterAddonMessagePrefix=function() return true end, SendAddonMessage=function(p,m,c) sent[#sent+1]=c..":"..m end}
local ns={}
local toc=io.open(ADDON_ROOT .. "/FishPartners.toc"):read("a")
for line in toc:gmatch("[^\r\n]+") do if not line:match("^##") and line:match("%.lua$") then
  assert(loadfile(ADDON_ROOT .. "/"..line:gsub("\\","/")))("FishPartners",ns) end end
fire("PLAYER_LOGIN"); advance(20)
print("quest setting on:", ns.S.sessionQuest)
SlashCmdList.FISHPARTNERS("start"); advance(1)
grouped = true; fire("GROUP_ROSTER_UPDATE"); advance(1)
-- quest turn-in 50s
fire("QUEST_COMPLETE"); fire("QUEST_TURNED_IN", 1, 100, 5000); setMoney(GetMoney()+5000); fire("QUEST_FINISHED"); advance(2)
-- shared coin: my share 1g
fire("LOOT_OPENED"); fire("CHAT_MSG_MONEY","Your share of the loot is 1 Gold."); setMoney(GetMoney()+10000); fire("LOOT_CLOSED"); advance(2)
-- party loot
fire("CHAT_MSG_LOOT", "Bob receives loot: "..mkLink(2589).."x10.")
fire("CHAT_MSG_LOOT", "Ann-OtherRealm receives loot: "..mkLink(1234)..".")
fire("CHAT_MSG_LOOT", "Stranger receives loot: "..mkLink(1234)..".")   -- not in group: ignored
fire("CHAT_MSG_LOOT", "You receive loot: "..mkLink(2770).."x2.")
advance(2)
-- Ann runs FPWM and reports her session
fire("CHAT_MSG_ADDON", "FPWM1", "S;123456;20000;5000;98456;3600", "PARTY", "Ann-OtherRealm")
-- Bob leaves; more coin afterwards shouldn't accrue to him
party.party1=nil; fire("GROUP_ROSTER_UPDATE")
fire("LOOT_OPENED"); fire("CHAT_MSG_MONEY","x"); setMoney(GetMoney()+20000); fire("LOOT_CLOSED"); advance(70)
local st = ns.Session:Stats()
print(string.format("ME: coin=%d quest=%d items=%d total=%d", st.coin, st.quest, st.items, st.total))
local s = ns.cdb.session
for name, m in pairs(s.party) do local ms = ns.Party:MemberStats(s, m)
  print(string.format("  %-16s present=%-5s fills=%d value=%d coin~%d total=%d reported=%s", name, tostring(m.present), m.fills, ms.value, ms.coin, ms.total, tostring(ms.reported))) end
-- render party view
ns:ShowPage("pnl")
local function btn(text) for _, f in ipairs(MOCK_FRAMES) do if f.kind=="Button" and rawget(f,"text")==text then return f end end end
btn("PARTY").scripts.OnClick(btn("PARTY")); advance(1)
local function list9() for _, f in ipairs(MOCK_FRAMES) do local r=rawget(f,"rows"); if r and r[1] and #r[1].cells==7 then return f end end end
for _, d in ipairs(list9().data) do local c={} for i,v in ipairs(d.cells) do c[i]=(v:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")) end print("  BOARD", table.concat(c, " | ")) end
btn("MY BOOK").scripts.OnClick(btn("MY BOOK")); advance(1)
print("broadcasts sent:", #sent, sent[#sent])
ns.Session:Stop(); print("archive party:", ns.cdb.archive[1].party and #ns.cdb.archive[1].party, "quest booked:", ns.cdb.archive[1].quest)
print("errors:", #ns.errors); print("OK11")
