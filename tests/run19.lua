dofile(TESTS .. "/mock.lua")
local QI = "|cffffffff|Hitem:7777::::::::|h[Gnoll Paw]|h|r"
local oldGII, oldInst = GetItemInfo, GetItemInfoInstant
function GetItemInfo(l) local id=type(l)=="number" and l or tonumber(tostring(l):match("item:(%d+)"))
  if id==7777 then return "Gnoll Paw",QI,1,1,1,"Quest","Quest",20,"",0,0,12,0,4 end return oldGII(l) end
function GetItemInfoInstant(l) local id=type(l)=="number" and l or tonumber(tostring(l):match("item:(%d+)"))
  if id==7777 then return id,"Quest","Quest","",0,12,0 end return oldInst(l) end
-- bags: 3 Gnoll Paws + 20 linen
local bags={[0]={[1]={QI,3,true,7777},[2]={mkLink(2589),20,false,2589}}}
C_Container.GetContainerNumSlots=function(b) return bags[b] and 2 or 0 end
C_Container.GetContainerItemInfo=function(b,s) local x=bags[b] and bags[b][s]; if not x then return nil end return {hyperlink=x[1],stackCount=x[2],isBound=x[3],itemID=x[4]} end
local ns={}
local toc=io.open(ADDON_ROOT .. "/FishPartners.toc"):read("a")
for line in toc:gmatch("[^\r\n]+") do if not line:match("^##") and line:match("%.lua$") then
  assert(loadfile(ADDON_ROOT .. "/"..line:gsub("\\","/")))("FishPartners",ns) end end
-- pretend an older version saved a quest item in the portfolio
FishPartnersDB = { chars = { ["Fishbro-Forever"] = { inv = { [7777] = { b = 9 } } } } }
fire("PLAYER_LOGIN"); advance(25)
print("IsQuestItem:", ns.IsQuestItem(QI), ns.IsQuestItem(mkLink(2589)), ns.IsQuestItem(7777))
local inv = ns.db.chars["Fishbro-Forever"].inv
print("portfolio after scan+cleanup: quest item present?", inv[7777] ~= nil, "| linen:", inv[2589] and inv[2589].b)
SlashCmdList.FISHPARTNERS("start"); advance(1)
fire("CHAT_MSG_LOOT","You receive loot: "..QI.."x2."); fire("CHAT_MSG_LOOT","You receive loot: "..mkLink(2770)..".") advance(2)
local n=0 for l in pairs(ns.cdb.session.items) do n=n+1; print("  session item:", ns.LinkName(l)) end
print("session items:", n, "loot count:", ns.cdb.session.lootCount)
ns:ShowPage("port"); ns:ShowPage("pnl")
print("errors:", #ns.errors); print("OK19")
