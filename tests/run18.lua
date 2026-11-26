dofile(TESTS .. "/run2.lua")      -- me: 5 Thorium @1.2g, bank scanned
local ns = FishPartners; local P = ns.Portfolio
local TB = "|cffffffff|Hitem:12359::::::::|h[Thorium Bar]|h|r"
local function show(tag) local b=P:Basis(12359); local e=ns.db.chars[ns.CharKey()].inv[12359] or {}
  print(string.format("%-34s held=%-3d bags=%-3s ah=%-3s mail=%-3s | basis qty=%s avg=%s", tag, P:Held(12359), tostring(e.b), tostring(e.a), tostring(e.m), b and b.qty or "-", b and ns.MoneyShort(b.avg) or "-")) end
show("start")
-- post all 5 at the AH
P:OnPosted(TB, 5); P:SetLocation("b", {}); advance(1); show("posted 5")
advance(10); show("AH closed, still listed")
-- auction expires: gone from listings, no sale
P:SetLocation("a", {}); advance(1); show("expired (not in mailbox yet)")
advance(30); show("30s later, reconcile ran")
-- open mailbox: the 5 are there; collect into bags
P:SetLocation("m", {[12359]={q=5, link=TB}}); advance(1); show("mailbox opened")
P:SetLocation("m", {}); P:SetLocation("b", {[12359]={q=5, link=TB}}); advance(10); show("collected into bags")
-- recovery tool for people already affected
P:ClearBasis(12359); advance(1)
print("purchases in ledger:", #P:Purchases(12359))
local avg, q, used = P:BasisFromLedger(12359); print("FROM LEDGER ->", q, ns.MoneyShort(avg), used)
ns:ShowPage("port")
print("errors:", #ns.errors); print("OK18")
