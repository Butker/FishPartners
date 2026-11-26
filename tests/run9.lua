dofile(TESTS .. "/mock.lua")
local ns={}
local toc=io.open(ADDON_ROOT .. "/FishPartners.toc"):read("a")
for line in toc:gmatch("[^\r\n]+") do if not line:match("^##") and line:match("%.lua$") then
  assert(loadfile(ADDON_ROOT .. "/"..line:gsub("\\","/")))("FishPartners",ns) end end
fire("PLAYER_LOGIN"); advance(20)
print("market module gone:", ns.Market == nil)
local hud=_G.FishPartnersHUD
print("hud before start:", hud)
SlashCmdList.FISHPARTNERS("start"); advance(1)
hud=_G.FishPartnersHUD
local function T(fs) return (tostring(fs.text):gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r",""):gsub("|H.-|h",""):gsub("|h","")) end
fire("LOOT_OPENED"); fire("CHAT_MSG_MONEY","x"); setMoney(GetMoney()+12345); fire("LOOT_CLOSED")
fire("CHAT_MSG_LOOT","You receive loot: "..mkLink(2589).."x5.")
advance(75)
print("HUD shown:", hud.shown, "| state", T(hud.state), "| clock", T(hud.clock), "| gph", T(hud.gph), "| total", T(hud.total), "| split", T(hud.split))
for i=1,2 do print("  line", T(hud.lines[i].name), T(hud.lines[i].val)) end
hud.pause.scripts.OnClick(hud.pause); advance(1); print("after pause:", T(hud.state), T(hud.pause.fs))
rawget(hud,"pause") -- noop
-- close button hides, session continues; new session reopens
ns.HUD:Hide(true); print("closed:", hud.shown, "session active:", ns.Session:Stats().active)
hud.stop.scripts.OnClick(hud.stop); advance(1)
SlashCmdList.FISHPARTNERS("start"); advance(1); print("reopened on new session:", hud.shown)
SlashCmdList.FISHPARTNERS("hud"); print("hud toggle ->", hud.shown)
for _,id in ipairs({"pnl","aum","port","rpt","gl","cmpl"}) do ns:ShowPage(id) end
SlashCmdList.FISHPARTNERS("diag")
print("errors:", #ns.errors)
print("OK9")
