dofile(TESTS .. "/mock.lua")
local inside, iid, iname = false, nil, nil
IsInInstance=function() if inside then return true, "party" end return false, "none" end
GetInstanceInfo=function() return iname,"party",1,"Normal",5,0,false,iid end
GetZoneText=function() return iname or "Elwynn Forest" end
INSTANCE_RESET_SUCCESS="%s has been reset."
local ns={}
local toc=io.open(ADDON_ROOT .. "/FishPartners.toc"):read("a")
for line in toc:gmatch("[^\r\n]+") do if not line:match("^##") and line:match("%.lua$") then
  assert(loadfile(ADDON_ROOT .. "/"..line:gsub("\\","/")))("FishPartners",ns) end end
fire("PLAYER_LOGIN"); fire("PLAYER_ENTERING_WORLD", true, false); advance(20)
local function T(fs) return (tostring(fs.text):gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")) end
local function enter(id,name) inside, iid, iname = true, id, name; fire("PLAYER_ENTERING_WORLD", false, false); advance(2) end
local function leave() inside=false; fire("PLAYER_ENTERING_WORLD", false, false); advance(2) end
local function show(tag) local d=_G.FishPartnersBell
  if d and d.shown then print(tag..": ["..T(d.kicker).."] "..T(d.title).." | "..T(d.stats).." | buttons: "..T(d.b1.fs).." / "..T(d.b2.fs)..(d.b3.shown and (" / "..T(d.b3.fs)) or ""))
  else print(tag..": (no popup)") end end
enter(36,"The Deadmines"); show("1 enter, no session")
_G.FishPartnersBell.b1.scripts.OnClick(_G.FishPartnersBell.b1); advance(1)
print("   session active:", ns.Session:Stats().active)
_G.FishPartnersBell:Hide()
leave(); enter(36,"The Deadmines"); show("2 corpse run same instance")
leave(); fire("CHAT_MSG_SYSTEM","The Deadmines has been reset."); enter(36,"The Deadmines"); show("3 after reset, session running")
_G.FishPartnersBell.b1.scripts.OnClick(_G.FishPartnersBell.b1); advance(1)
print("   archive:", #ns.cdb.archive, "new session active:", ns.Session:Stats().active)
_G.FishPartnersBell:Hide()
ns.Session:TogglePause(); leave(); enter(43,"Wailing Caverns"); show("4 other dungeon, paused")
_G.FishPartnersBell.b2.scripts.OnClick(_G.FishPartnersBell.b2); advance(1); print("   resumed:", not ns.Session:Stats().paused)
_G.FishPartnersBell:Hide(); leave(); inside,iid,iname=true,99,"Scholomance"; fire("PLAYER_ENTERING_WORLD", false, true); advance(2); show("5 /reload inside")
for _,id in ipairs({"pnl","cmpl"}) do ns:ShowPage(id) end
print("errors:", #ns.errors); print("OK10")
