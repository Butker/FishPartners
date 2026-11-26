dofile(TESTS .. "/mock.lua")
local ns = {}
local toc = io.open(ADDON_ROOT .. "/FishPartners.toc"):read("a")
for line in toc:gmatch("[^\r\n]+") do
  if not line:match("^##") and line:match("%.lua$") then
    local path = ADDON_ROOT .. "/"..line:gsub("\\","/")
    local fn = assert(loadfile(path)); fn("FishPartners", ns)
  end
end
fire("PLAYER_LOGIN")
SlashCmdList.FISHPARTNERS("")         -- open terminal
for _,id in ipairs({"pnl","aum","gl","cmpl"}) do ns:ShowPage(id) end
SlashCmdList.FISHPARTNERS("start")
fire("LOOT_OPENED"); fire("CHAT_MSG_MONEY","You loot 1 Silver"); setMoney(50100); fire("LOOT_CLOSED")
fire("CHAT_MSG_LOOT","You receive loot: "..mkLink(2589).."x5.")
fire("CHAT_MSG_LOOT","You receive loot: "..mkLink(2770).."x3.")
fire("CHAT_MSG_LOOT","You receive loot: "..mkLink(1234)..".")
fire("CHAT_MSG_LOOT","You receive loot: "..mkLink(5555)..".")
advance(130)
-- AH buy
fire("AUCTION_HOUSE_SHOW"); PlaceAuctionBid("list",1,500); setMoney(49600); advance(2); fire("AUCTION_HOUSE_CLOSED")
-- Mail sale
fire("MAIL_SHOW"); TakeInboxMoney(1); setMoney(51500); advance(2); fire("MAIL_CLOSED")
-- vendor sale
fire("MERCHANT_SHOW"); MerchantFrame.shown=true; C_Container.UseContainerItem(0,1); setMoney(51760); advance(2)
RepairAllItems(); setMoney(51000); advance(2); fire("MERCHANT_CLOSED"); MerchantFrame.shown=false
advance(5)
local st = ns.Session:Stats()
print(string.format("SESSION coin=%d items=%d total=%d gph=%s elapsed=%d", st.coin, st.items, st.total, tostring(st.gph), st.elapsed))
for link,it in pairs(ns.cdb.session.items) do print("  ", ns.LinkName(link), it.qty, it.unit, it.src) end
print("LEDGER:")
for _,e in ipairs(ns.db.ledger) do print("  ", e.k, e.a, e.i and ns.LinkName(e.i) or "", e.q or "", e.n or "") end
for _,id in ipairs({"pnl","aum","gl","cmpl"}) do ns:ShowPage(id) end
ns.S.gearMargin=5; ns:Fire("VALUATION_CHANGED")
for link,it in pairs(ns.cdb.session.items) do if it.qty==1 then print("  after 5% gear:", ns.LinkName(link), it.unit, it.src) end end
print("AUM total:", ns.Wealth:Totals())
SlashCmdList.FISHPARTNERS("stop")
print("archive:", #ns.cdb.archive)
-- logout/login auto-pause path
SlashCmdList.FISHPARTNERS("start"); fire("PLAYER_LOGOUT"); print("autopaused:", ns.cdb.session.paused)
-- ticker run
local f = _G.FishPartnersFrame; advance(1)
print("OK — smoke test passed")
