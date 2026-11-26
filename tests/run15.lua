dofile(TESTS .. "/run14.lua")
local ns = FishPartners
ns:ShowPage("pnl")
local function btn(text) for _, f in ipairs(MOCK_FRAMES) do if f.kind=="Button" and rawget(f,"text")==text then return f end end end
btn("PARTY").scripts.OnClick(btn("PARTY"))
local function tbl(ncols) for _, f in ipairs(MOCK_FRAMES) do local r=rawget(f,"rows"); if r and r[1] and #r[1].cells==ncols and rawget(f,"data") and #f.data>0 and f.data[1].cells and f.data[1].cells[1] and tostring(f.data[1].cells[1]):find("you") then return f end end end
local board; for _, f in ipairs(MOCK_FRAMES) do local r=rawget(f,"rows"); if r and r[1] and #r[1].cells==7 and rawget(f,"data") and #f.data>0 then board=f end end
local function clean(v) return (tostring(v):gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r",""):gsub("|H.-|h",""):gsub("|h","")) end
local function holdTable() for _, f in ipairs(MOCK_FRAMES) do local r=rawget(f,"rows"); if r and r[1] and #r[1].cells==3 then return f end end end
local function dumpHold(tag) local h=holdTable(); local t={} for _,d in ipairs(h.data) do t[#t+1]=clean(d.cells[1]) end print(tag, table.concat(t, ", ")) end
dumpHold("default:")
-- click Ann's row through the actual row button (as the game does)
for i, row in ipairs(board.rows) do
  if row.item and clean(row.item.cells[1]):find("Bob") then row.scripts.OnClick(row, "LeftButton") end
end
dumpHold("after clicking Bob:")
advance(2) -- 1s ticker refresh
dumpHold("after ticker:")
for i, row in ipairs(board.rows) do
  if row.item and clean(row.item.cells[1]):find("you") then row.scripts.OnClick(row, "LeftButton") end
end
dumpHold("after clicking yourself:")
local sel=0 for _,d in ipairs(board.data) do if d.selected then sel=sel+1; print("highlighted:", clean(d.cells[1])) end end
print("errors:", #ns.errors); print("OK15")
