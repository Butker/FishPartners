dofile(TESTS .. "/mock.lua")
-- extra item: Thorium Bar, vendor 6s, AH 1g
local ITEMS_EXTRA = true
local oldGII, oldInst = GetItemInfo, GetItemInfoInstant
function GetItemInfo(l) local id=type(l)=="number" and l or tonumber(tostring(l):match("item:(%d+)"))
  if id==12359 then return "Thorium Bar","|cffffffff|Hitem:12359::::::::|h[Thorium Bar]|h|r",1,1,1,"","",20,"",0,600,7,0,0 end
  return oldGII(l) end
function GetItemInfoInstant(l) local id=type(l)=="number" and l or tonumber(tostring(l):match("item:(%d+)"))
  if id==12359 then return id,"","","",0,7,0 end return oldInst(l) end
local TB="|cffffffff|Hitem:12359::::::::|h[Thorium Bar]|h|r"
local apiOld=Auctionator.API.v1.GetAuctionPriceByItemLink
Auctionator.API.v1.GetAuctionPriceByItemLink=function(c,l) if l:find("12359") then return 10000 end return apiOld(c,l) end
-- bags: 20 thorium
local bags={[0]={[1]={TB,20,false,12359}}}
C_Container.GetContainerNumSlots=function(b) return (bags[b] and 4) or 0 end
C_Container.GetContainerItemInfo=function(b,s) local x=bags[b] and bags[b][s]; if not x then return nil end return {hyperlink=x[1],stackCount=x[2],isBound=x[3],itemID=x[4]} end
GetAuctionItemLink=function() return TB end
GetAuctionItemInfo=function() return "Thorium Bar",nil,10,nil,nil,nil,nil,nil,nil,100000 end
GetInboxNumItems=function() return 0 end

local ns={}
local toc=io.open(ADDON_ROOT .. "/FishPartners.toc"):read("a")
for line in toc:gmatch("[^\r\n]+") do if not line:match("^##") and line:match("%.lua$") then
  assert(loadfile(ADDON_ROOT .. "/"..line:gsub("\\","/")))("FishPartners",ns) end end
local function money(m) setMoney(m) end
fire("PLAYER_LOGIN"); advance(6)
fire("BANKFRAME_OPENED"); BankFrame.shown=true; advance(1); fire("BANKFRAME_CLOSED"); BankFrame.shown=false; advance(1)
local P=ns.Portfolio
local function show(tag) local b=P:Basis(12359); print(string.format("%-34s held=%d  basis qty=%s avg=%s  realized=%s", tag, P:Held(12359), b and b.qty or "-", b and ns.MoneyShort(b.avg) or "-", ns.MoneyShort(ns.db.realized))) end
show("install (looted/old stock)")
SlashCmdList.FISHPARTNERS("port")
P:SetBasis(12359, ns.ParseMoney("2g"), 20); advance(1)
show("manual mark: bought @ 2g")
-- check unrealized via page
local pg; for _,f in pairs({}) do end
-- buy 10 @ 1g at AH (buyout)
fire("AUCTION_HOUSE_SHOW"); PlaceAuctionBid("list",1,100000); money(GetMoney()-100000); advance(2)
show("AH buyout 10 @ 1g")
fire("AUCTION_HOUSE_CLOSED"); advance(6)
show("after AH close (10 in mail)")
-- collect mail: items go to bags
GetInboxNumItems=function() return 0 end; fire("MAIL_SHOW"); fire("MAIL_INBOX_UPDATE"); bags[0][2]={TB,10,false,12359}; fire("BAG_UPDATE_DELAYED"); advance(3); fire("MAIL_CLOSED"); advance(8)
show("collected mail, in bags")
-- vendor everything (30 units @ 6s)
fire("MERCHANT_SHOW"); MerchantFrame.shown=true
C_Container.UseContainerItem(0,1); money(GetMoney()+12000); advance(1)
C_Container.UseContainerItem(0,2); money(GetMoney()+6000); advance(1)
bags[0]={}; fire("BAG_UPDATE_DELAYED"); advance(4); fire("MERCHANT_CLOSED"); MerchantFrame.shown=false; advance(6)
show("sold all 30 to vendor")
-- buy again 5 @ 1.2g
fire("AUCTION_HOUSE_SHOW"); GetAuctionItemInfo=function() return "Thorium Bar",nil,5,nil,nil,nil,nil,nil,nil,60000 end
PlaceAuctionBid("list",1,60000); money(GetMoney()-60000); advance(2)
show("re-buy 5 @ 1.2g")
-- render every page
for _,id in ipairs({"pnl","aum","port","gl","cmpl"}) do ns:ShowPage(id) end
-- editor smoke: open + parse
print("parse:", ns.ParseMoney("2g 50s"), ns.ParseMoney("2,5"), ns.ParseMoney("75s"), ns.ParseMoney("abc"))
print("LEDGER:") for _,e in ipairs(ns.db.ledger) do print("  ",e.k,e.a,e.q or "", e.r and ("realized "..ns.MoneyShort(e.r)) or "") end
print("OK")
