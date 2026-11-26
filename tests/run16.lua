dofile(TESTS .. "/mock.lua")
local sent = {}
C_ChatInfo={RegisterAddonMessagePrefix=function() return true end, SendAddonMessage=function(p,m,c,t) sent[#sent+1]=c..(t and (">"..t) or "")..":"..m end}
IsInGroup=function() return false end
local ns={}
local toc=io.open(ADDON_ROOT .. "/FishPartners.toc"):read("a")
for line in toc:gmatch("[^\r\n]+") do if not line:match("^##") and line:match("%.lua$") then
  assert(loadfile(ADDON_ROOT .. "/"..line:gsub("\\","/")))("FishPartners",ns) end end
fire("PLAYER_LOGIN"); advance(25)
print("my version (from toc):", ns.VERSION, "| announced:", table.concat(sent, ", "))
print("compare:", ns.Update.Compare("1.9.0","1.10.0"), ns.Update.Compare("1.9","1.9.0"), ns.Update.Compare("2.0.0","1.9.9"))
-- an older friend pings: we reply by whisper
fire("CHAT_MSG_ADDON","FPWM1","V;1.8.4","GUILD","Oldfriend")
print("reply:", sent[#sent])
-- a newer friend: we get a notice once
fire("CHAT_MSG_ADDON","FPWM1","V;1.10.0","GUILD","Newfriend-Forever")
fire("CHAT_MSG_ADDON","FPWM1","V;1.10.0","PARTY","Otherfriend")
print("newer seen:", ns.Update.newer)
-- session sync messages still work alongside
fire("CHAT_MSG_ADDON","FPWM1","S;1;2;3;4;5","PARTY","Nobody")
SlashCmdList.FISHPARTNERS("update"); SlashCmdList.FISHPARTNERS("diag")
print("errors:", #ns.errors); print("OK16")
