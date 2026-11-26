dofile(TESTS .. "/mock.lua")
local ns={}
local toc=io.open(ADDON_ROOT .. "/FishPartners.toc"):read("a")
for line in toc:gmatch("[^\r\n]+") do if not line:match("^##") and line:match("%.lua$") then
  assert(loadfile(ADDON_ROOT .. "/"..line:gsub("\\","/")))("FishPartners",ns) end end
fire("PLAYER_LOGIN"); advance(6)
AUCTION_SOLD_MAIL_SUBJECT="Auction successful: %s"
local inbox = {
  { "Auction House", "Auction successful: Linen Cloth (20)", 1900, inv={"seller","Linen Cloth","Bob",2000,2000,0,100,0,0,0,20} },
  { "Auction House", "Auction successful: Copper Ore (10)", 4750, inv={"seller","Copper Ore","Ann",5000,5000,0,250,0,0,0,10}, needsText=true },
  { "Altbro", "here u go", 100000 },
  { "Auction House", "Outbid on Thorium Bar", 7000 },
}
local textLoaded = {}
GetInboxNumItems=function() return #inbox end
GetInboxHeaderInfo=function(i) local m=inbox[i]; if not m then return end return nil,nil,m[1],m[2],m[3],0,29.5 end
GetInboxInvoiceInfo=function(i) local m=inbox[i]; if not m or not m.inv then return nil end
  if m.needsText and not textLoaded[i] then return nil end return table.unpack(m.inv) end
GetInboxText=function(i) textLoaded[i]=true end
local function take(i) TakeInboxMoney(i) end
fire("MAIL_SHOW"); fire("MAIL_INBOX_UPDATE")
local m = GetMoney()
-- take all four quickly; a stray loot tag too (CHAT_MSG_MONEY) to try to confuse
take(1); take(2); take(3); take(4); fire("CHAT_MSG_MONEY","x")
-- server: mail 1 alone, mails 2+3 merged into one update, mail 4 alone (out of order)
m=m+1900; setMoney(m); advance(0.2)
m=m+7000; setMoney(m); advance(0.2)          -- outbid refund arrives before the merged one
m=m+4750+100000; setMoney(m); advance(2)
fire("MAIL_CLOSED"); advance(1)
for _,e in ipairs(ns.db.ledger) do print(string.format("  %-10s %7d  %-12s %-4s %s", e.k, e.a, e.i or "", e.q or "", e.n or "")) end
print("OK5")
