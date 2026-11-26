dofile(TESTS .. "/run2.lua")   -- me (Fishbro): 5 Thorium
local ns = FishPartners; local P = ns.Portfolio
ns.db.chars["Altgirl-Forever"] = { name="Altgirl", realm="Forever", class="MAGE", money=100000, bankT=1,
  inv = { [12359] = { k = 15 }, [2589] = { b = 40 } } }
P:SetBasis(12359, 20000, 20); advance(1)    -- 20 units @ 2g account-wide
ns:ShowPage("port")
local function btn(text) for _, f in ipairs(MOCK_FRAMES) do if f.kind=="Button" and rawget(f,"text")==text then return f end end end
local function list() for _, f in ipairs(MOCK_FRAMES) do local r=rawget(f,"rows"); if r and r[1] and #r[1].cells==9 then return f end end end
local function dump(tag)
  print("== "..tag)
  for _, d in ipairs(list().data) do
    local c = {}; for i,v in ipairs(d.cells) do c[i] = (v:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r",""):gsub("|H.-|h",""):gsub("|h","")) end
    print(string.format("  %-40s %-8s %-8s %-10s %-10s %s", c[1], c[2], c[3], c[6], c[7], c[8]))
  end
end
btn("BY CHAR").scripts.OnClick(btn("BY CHAR")); dump("BY CHAR (me open by default)")
-- click Altgirl header to unfold
for _, d in ipairs(list().data) do if d.header and d.cells[1]:find("Altgirl") then d.onClick("LeftButton") end end
dump("after unfolding Altgirl")
btn("ALL CHARS").scripts.OnClick(btn("ALL CHARS")); dump("ALL CHARS")
btn("THIS CHAR").scripts.OnClick(btn("THIS CHAR")); dump("THIS CHAR")
print("OK4")
