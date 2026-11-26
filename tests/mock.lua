-- Minimal WoW API mock for smoke-testing
local frames, timers, now = {}, {}, 1000
MOCK_FRAMES = frames
math.atan2 = math.atan2 or function(y,x) return math.atan(y,x) end
format, floor, tinsert = string.format, math.floor, table.insert
function strsplit(d, s) local out={} for p in (s..d):gmatch("(.-)"..d:gsub("%p","%%%0")) do out[#out+1]=p end return table.unpack(out) end
function wipe(t) for k in pairs(t) do t[k]=nil end return t end
function GetTime() return now end
function time() return os.time() + math.floor(now-1000) end
date = os.date
function geterrorhandler() return function(e) error(e, 0) end end
local function newObj(kind)
  local o = {kind=kind, scripts={}, shown=true, text="", w=100, h=20, points={}, events={}}
  local m = {}
  m.SetScript=function(s,k,f) s.scripts[k]=f end
  m.GetScript=function(s,k) return s.scripts[k] end
  m.HookScript=m.SetScript
  m.RegisterEvent=function(s,e) if e=="BOGUS_EVENT" then error("bad") end s.events[e]=true end
  m.Show=function(s) local was=s.shown; s.shown=true; if not was and s.scripts.OnShow then s.scripts.OnShow(s) end end
  m.Hide=function(s) s.shown=false end
  m.SetShown=function(s,v) if v then s:Show() else s:Hide() end end
  m.IsShown=function(s) return s.shown end
  m.IsVisible=function(s) local p=s; while p do if not rawget(p,"shown") then return false end p=rawget(p,"parent") end return true end
  m.SetText=function(s,t) s.text=t or "" end
  m.GetText=function(s) return s.text end
  m.GetStringWidth=function(s) return #tostring(s.text)*5 end
  m.SetWidth=function(s,w) s.w=w end  m.SetHeight=function(s,h) s.h=h end
  m.SetSize=function(s,w,h) s.w,s.h=w,h end
  m.GetWidth=function(s) return s.w end m.GetHeight=function(s) return s.h end
  m.GetPoint=function(s) return "CENTER", nil, "CENTER", 0, 0 end
  m.GetCenter=function() return 100,100 end
  m.GetFrameLevel=function() return 1 end
  m.SetScale=function(s,v) s.scale=v end
  m.GetScale=function(s) return rawget(s,"scale") or 1 end
  m.GetEffectiveScale=function(s) return rawget(s,"scale") or 1 end
  m.GetLeft=function(s) return rawget(s,"left") or 100 end
  m.GetTop=function(s) return rawget(s,"top") or 500 end
  m.SetPoint=function(s,p,rel,rp,x,y) s.pt={p,rp,x,y} end
  m.CreateTexture=function(s) local t=newObj("Texture"); t.parent=s; return t end
  m.CreateFontString=function(s) local t=newObj("FontString"); t.parent=s; return t end
  m.SetFontString=function(s,fs) s.fs=fs end
  m.SetText=function(s,t) s.text=t or ""; local fs=rawget(s,"fs"); if fs then fs.text=t end end
  m.IsItemEmpty=function() return false end
  m.GetNumRegions=function() return 0 end
  setmetatable(o, {__index=function(t,k) if m[k] then return m[k] end if type(k)=="string" and k:match("^%l") then return nil end return function() end end})
  return o
end
function CreateFrame(kind, name, parent)
  local f=newObj(kind); f.parent=parent; if name then _G[name]=f end
  table.insert(frames,f); return f
end
UIParent=CreateFrame("Frame"); Minimap=CreateFrame("Frame"); Minimap.w=140
GameTooltip=CreateFrame("GameTooltip"); DEFAULT_CHAT_FRAME={AddMessage=function(_,m) print("CHAT: "..m) end}
MerchantFrame=CreateFrame("Frame"); MerchantFrame.shown=false
BankFrame=CreateFrame("Frame"); BankFrame.shown=false
UISpecialFrames={} StaticPopupDialogs={} function StaticPopup_Show(n) local d=StaticPopupDialogs[n]; d.OnAccept() end
SlashCmdList={}
RAID_CLASS_COLORS={MAGE={r=0.25,g=0.78,b=0.92}}
LOOT_ITEM_SELF="You receive loot: %s." LOOT_ITEM_SELF_MULTIPLE="You receive loot: %sx%d."
AUCTION_OUTBID_MAIL_SUBJECT="Outbid on %s"
NUM_BAG_SLOTS=4 NUM_BANKBAGSLOTS=6 BANK_CONTAINER=-1
C_Timer={After=function(d,f) if d==0 then FRAMES_ADVANCED=FRAMES_ADVANCED+1; d=0.016 end table.insert(timers,{at=now+d,f=f}) end,
  NewTicker=function(d,f) local t={every=d,at=now+d,rep=true}; t.f=function() if not t.dead then f() end end; t.Cancel=function() t.dead=true; t.rep=false end; table.insert(timers,t); return t end,
  NewTimer=function(d,f) local t={at=now+d}; t.f=function() if not t.dead then f() end end; t.Cancel=function() t.dead=true end; table.insert(timers,t); return t end}
FRAMES_ADVANCED=0
function advance(sec)
  local target=now+sec
  while true do
    table.sort(timers,function(a,b) return a.at<b.at end)
    local t=timers[1]
    if not t or t.at>target then break end
    table.remove(timers,1); now=t.at; t.f()
    if t.rep then t.at=now+t.every; table.insert(timers,t) end
  end
  now=target
end
local money=50000
function GetMoney() return money end
function setMoney(m) money=m; fire("PLAYER_MONEY") end
function UnitName() return "Fishbro" end function GetRealmName() return "Forever" end
function UnitClass() return "Mage","MAGE" end function UnitFactionGroup() return "Horde" end
function UnitLevel() return 42 end function UnitGUID() return "Player-123-ABCDEF" end
function IsShiftKeyDown() return false end
function hooksecurefunc(t,n,f) if type(t)=="string" then t,n,f=_G,t,n end local o=t[n]; t[n]=function(...) local r={o(...)}; f(...); return table.unpack(r) end end
-- items
local ITEMS={
 [2589]={"Linen Cloth",1,13,0,7,0},   -- vendor 13c, trade goods
 [2770]={"Copper Ore",1,5,0,7,0},
 [1234]={"Blade of Testing",2,500,1,2,2}, -- BoE weapon? bindType 2
 [5555]={"Bound Helm",2,300,1,4,1},   -- BoP armor
}
local function idOf(link) return tonumber(tostring(link):match("item:(%d+)")) end
function mkLink(id) return "|cffffffff|Hitem:"..id.."::::::::|h["..ITEMS[id][1].."]|h|r" end
function GetItemInfo(l) local id=type(l)=="number" and l or idOf(l); local it=ITEMS[id]; if not it then return nil end
  return it[1], mkLink(id), it[2], 20, 1, "", "", 20, "", 0, it[3], it[5], 0, it[6] end
function GetItemInfoInstant(l) local id=type(l)=="number" and l or idOf(l); local it=ITEMS[id]; return id, "", "", "", 0, it and it[5], 0 end
Auctionator={API={v1={GetAuctionPriceByItemLink=function(c,l) local id=idOf(l)
  if id==2589 then return 14 end   -- 7.7% over vendor 13 -> AH
  if id==2770 then return 5 end    -- not > 5%: vendor
  if id==1234 then return 540 end  -- 8% over 500: gear needs 10% -> vendor
  if id==5555 then return 9999 end -- BoP -> vendor
end}}}
local bags={[0]={[1]={mkLink(2589),20,false,2589},[2]={mkLink(5555),1,true,5555}}}
C_Container={GetContainerNumSlots=function(b) return bags[b] and 2 or 0 end,
  GetContainerItemInfo=function(b,s) local x=bags[b] and bags[b][s]; if not x then return nil end return {hyperlink=x[1],stackCount=x[2],isBound=x[3],itemID=x[4]} end,
  UseContainerItem=function() end}
GetInboxHeaderInfo=function(i) return nil,nil,"Auction House","Auction successful: Linen Cloth",1900 end
GetInboxInvoiceInfo=function(i) return "seller","Linen Cloth","Buyer",2000,2000,0,100,0,0,0,20 end
TakeInboxMoney=function() end AutoLootMailItem=function() end SendMail=function() end
PostAuction=function() end
PlaceAuctionBid=function() end GetAuctionItemLink=function() return mkLink(2770) end GetAuctionItemInfo=function() return "Copper Ore",nil,10 end
RepairAllItems=function() end BuyMerchantItem=function() end GetMerchantItemLink=function() return mkLink(2589) end GetMerchantItemInfo=function() return "x",nil,10,1 end
function fire(ev,...) for _,f in ipairs(frames) do if f.events[ev] and f.scripts.OnEvent then f.scripts.OnEvent(f,ev,...) end end end
GetBuildInfo=GetBuildInfo or function() return "1.60.1","70790","x",16001 end
function GetAddOnMetadata(addon, field)
  local toc = io.open(ADDON_ROOT .. "/FishPartners.toc"):read("a")
  return toc:match("## "..field..":%s*([^\r\n]+)")
end
IsInGuild = IsInGuild or function() return true end
