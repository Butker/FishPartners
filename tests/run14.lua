dofile(TESTS .. "/mock.lua")
local party = { party1 = {"Bob", nil, "WARRIOR", "Player-1-AAA"}, party2 = {"Ann", "OtherRealm", "MAGE", "Player-2-BBB"} }
IsInGroup=function() return true end; IsInRaid=function() return false end
GetNumSubgroupMembers=function() return 2 end
UnitExists=function(u) return party[u] ~= nil or u=="player" end
UnitIsUnit=function(a,b) return a==b end
UnitName=function(u) if party[u] then return party[u][1], party[u][2] end return "Fishbro" end
UnitClass=function(u) if party[u] then return "x", party[u][3] end return "Mage","MAGE" end
UnitGUID=function(u) if party[u] then return party[u][4] end if u=="player" then return "Player-0-ME" end end
RAID_CLASS_COLORS.WARRIOR={r=0.78,g=0.61,b=0.43}
LOOT_ITEM="%s receives loot: %s." LOOT_ITEM_MULTIPLE="%s receives loot: %sx%d."
LOOT_ITEM_PUSHED="%s receives item: %s." LOOT_ROLL_WON="%s won: %s"
C_ChatInfo={RegisterAddonMessagePrefix=function() return true end, SendAddonMessage=function() end}
local ns={}
local toc=io.open(ADDON_ROOT .. "/FishPartners.toc"):read("a")
for line in toc:gmatch("[^\r\n]+") do if not line:match("^##") and line:match("%.lua$") then
  assert(loadfile(ADDON_ROOT .. "/"..line:gsub("\\","/")))("FishPartners",ns) end end
fire("PLAYER_LOGIN"); advance(20)
SlashCmdList.FISHPARTNERS("start"); fire("GROUP_ROSTER_UPDATE"); advance(1)
SlashCmdList.FISHPARTNERS("partydebug")
local LC, CO, BL = mkLink(2589), mkLink(2770), mkLink(1234)
local function loot(msg, a2, guid) fire("CHAT_MSG_LOOT", msg, a2 or "", "", "", "", "", 0, 0, "", 0, 1, guid or "") end
-- 1) name as player hyperlink, realm-suffixed, multi qty (skinning-style)
loot("|Hplayer:Bob-Forever:12:LOOT|h[Bob]|h receives loot: "..LC.."x4.", "Bob-Forever", "Player-1-AAA")
-- 2) plain name, same-realm suffix only in arg, no guid (mining)
loot("Bob receives loot: "..CO.."x3.", "Bob-Forever", "")
-- 3) cross-realm, identified by GUID only
loot("Ann-OtherRealm receives loot: "..BL..".", "", "Player-2-BBB")
-- 4) things that must be ignored
loot("Bob won: "..BL, "Bob", "Player-1-AAA")
loot("Bob receives item: "..LC..".", "Bob", "Player-1-AAA")
loot("Stranger receives loot: "..LC.."x9.", "Stranger", "Player-9-ZZZ")
loot("You receive loot: "..CO..".", "Fishbro", "Player-0-ME")
advance(2)
local s = ns.cdb.session
for name, m in pairs(s.party) do local ms = ns.Party:MemberStats(s, m)
  local items = {} for l, it in pairs(m.items) do items[#items+1] = ns.LinkName(l).."x"..it.qty end
  table.sort(items)
  print(string.format("%-16s fills=%d value=%d  [%s]", name, m.fills, ms.value, table.concat(items, ", "))) end
print("tape:", #s.partyTape, "errors:", #ns.errors); print("OK14")
