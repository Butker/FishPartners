dofile(TESTS .. "/mock.lua")
LOOT_ITEM_PUSHED_SELF="You receive item: %s." LOOT_ITEM_PUSHED_SELF_MULTIPLE="You receive item: %sx%d."
local ns={}
local toc=io.open(ADDON_ROOT .. "/FishPartners.toc"):read("a")
for line in toc:gmatch("[^\r\n]+") do if not line:match("^##") and line:match("%.lua$") then
  assert(loadfile(ADDON_ROOT .. "/"..line:gsub("\\","/")))("FishPartners",ns) end end
fire("PLAYER_LOGIN"); advance(25)
SlashCmdList.FISHPARTNERS("start"); advance(1)
local function items() local t={} for l,it in pairs(ns.cdb.session.items) do t[#t+1]=ns.LinkName(l).."x"..it.qty..(it.reward and "(R)" or "") end table.sort(t) return table.concat(t,", ") end
-- 1) vendor purchase outside a quest: must NOT count
fire("CHAT_MSG_LOOT","You receive item: "..mkLink(2589).."x5."); advance(1); print("after vendor buy:", items())
-- 2) quest turn-in, chosen reward via chat line, then the same item via QUEST_LOOT_RECEIVED (no double)
fire("QUEST_COMPLETE"); fire("QUEST_TURNED_IN", 123, 500, 0); fire("CHAT_MSG_LOOT","You receive item: "..mkLink(1234).."."); fire("QUEST_LOOT_RECEIVED", 123, mkLink(1234), 1); fire("QUEST_FINISHED"); advance(1)
print("after reward (chat then event):", items())
advance(10)
-- 3) other order: event first, then chat line
fire("QUEST_TURNED_IN", 124, 500, 0); fire("QUEST_LOOT_RECEIVED", 124, mkLink(2770), 2); fire("CHAT_MSG_LOOT","You receive item: "..mkLink(2770).."x2."); advance(1)
print("after reward (event then chat):", items())
local st=ns.Session:Stats(); print("items value:", st.items, "tape top:", ns.cdb.session.tape[1].reward)
for _,id in ipairs({"pnl"}) do ns:ShowPage(id) end; ns.HUD:Show(); advance(1)
print("errors:", #ns.errors); print("OK17")
