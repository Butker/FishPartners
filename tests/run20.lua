dofile(TESTS .. "/mock.lua")
local ns={}
local toc=io.open(ADDON_ROOT .. "/FishPartners.toc"):read("a")
for line in toc:gmatch("[^\r\n]+") do if not line:match("^##") and line:match("%.lua$") then
  assert(loadfile(ADDON_ROOT .. "/"..line:gsub("\\","/")))("FishPartners",ns) end end
fire("PLAYER_LOGIN"); advance(25)
print("slash:", SLASH_FISHPARTNERS1, SLASH_FISHPARTNERS2)
SlashCmdList.FISHPARTNERS(""); print("terminal open:", _G.FishPartnersFrame.shown)
SlashCmdList.FISHPARTNERS("hud"); print("errors:", #ns.errors); print("OK20")
