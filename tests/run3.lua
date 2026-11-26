dofile(TESTS .. "/run2.lua")
local ns = FishPartners
local P = ns.Portfolio
function IsControlKeyDown() return true end
local function aum() local t,c,i = ns.Wealth:Totals(); return i end
-- put thorium back in bags + bank
print("before hide: inv value", aum())
ns:ShowPage("port")
local page = ns.Portfolio and nil
-- simulate ctrl-click via SetHidden like the row does
P:SetHidden(12359, true); advance(1)
print("after hide:  inv value", aum(), "hidden?", P:IsHidden(12359))
ns:ShowPage("port")
P:SetHidden(12359, false); advance(1)
print("after restore: inv value", aum(), "hidden?", P:IsHidden(12359))
print("OK3")
