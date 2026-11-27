-- 2.0 hardening scenarios
dofile(TESTS .. "/mock.lua")
debugprofilestop = function() return os.clock() * 1000 end
local function L(id, name, col) return "|cff" .. (col or "ffffff") .. "|Hitem:" .. id .. "::::::::|h[" .. name .. "]|h|r" end
local TB, CLAM, PEARL, DUST = L(12359, "Thorium Bar"), L(5523, "Small Barnacled Clam"), L(5498, "Small Lustrous Pearl"), L(10940, "Strange Dust")
local CHEAP = L(4000, "Cheap Trinket")
local SUFFIX = "|cff1eff00|Hitem:1234:0:0:0:0:0:-19:0|h[Blade of Testing of the Bear]|h|r"
local extra = {
  [12359] = { "Thorium Bar", 600, 7, 0 }, [5523] = { "Small Barnacled Clam", 0, 15, 0 },
  [5498] = { "Small Lustrous Pearl", 200, 7, 0 }, [10940] = { "Strange Dust", 50, 7, 0 },
  [4000] = { "Cheap Trinket", 100, 15, 0 },
}
local oldGII, oldInst = GetItemInfo, GetItemInfoInstant
function GetItemInfo(l) local id = type(l) == "number" and l or tonumber(tostring(l):match("item:(%d+)"))
  local e = extra[id]; if e then return e[1], L(id, e[1]), 1, 1, 1, "", "", 20, "", 0, e[2], e[3], 0, e[4] end return oldGII(l) end
function GetItemInfoInstant(l) local id = type(l) == "number" and l or tonumber(tostring(l):match("item:(%d+)"))
  local e = extra[id]; if e then return id, "", "", "", 0, e[3], 0 end return oldInst(l) end
ITEM_OPENABLE = "<Right Click to Open>"
C_TooltipInfo = { GetHyperlink = function(link) local lines = { { leftText = "x" } }
  if tostring(link):find("item:5523") then lines[2] = { leftText = ITEM_OPENABLE } end return { lines = lines } end }
local ahPrices = { [12359] = 10000, [4000] = 99990000 }  -- trinket: one absurd 9,999g listing
Auctionator.API.v1.GetAuctionPriceByItemLink = function(c, l) return ahPrices[tonumber(l:match("item:(%d+)"))] end
-- bags
local bags = { [0] = {} }
local function setBag(list) bags[0] = list end
C_Container.GetContainerNumSlots = function(b) return b == 0 and 8 or 0 end
C_Container.GetContainerItemInfo = function(b, s) local x = bags[b] and bags[b][s]; if not x then return nil end
  return { hyperlink = x[1], stackCount = x[2], isBound = false, itemID = tonumber(x[1]:match("item:(%d+)")) } end
local cursor = false; CursorHasItem = function() return cursor end
-- crash scenario: a session that was running when the game died 2h ago
FishPartnersCharDB = { session = { active = true, paused = false, started = time() - 7300, resumed = time() - 7300,
  elapsed = 0, beat = time() - 7000, coin = 0, quest = 0, items = {}, tape = {}, curve = {}, lootCount = 0 } }
local ns = {}
local toc = io.open(ADDON_ROOT .. "/FishPartners.toc"):read("a")
for line in toc:gmatch("[^\r\n]+") do if not line:match("^##") and line:match("%.lua$") then
  assert(loadfile(ADDON_ROOT .. "/" .. line:gsub("\\", "/")))("FishPartners", ns) end end
fire("PLAYER_LOGIN"); advance(2)
local function check(name, cond, detail) print((cond and "PASS " or "FAIL ") .. name .. (detail and ("  [" .. detail .. "]") or "")) end
local s = ns.cdb.session
check("crash: clock stopped at last heartbeat", s.paused and math.abs(s.elapsed - 300) < 5, "elapsed " .. tostring(s.elapsed))
ns.Session:Stop(); ns.Session:Start(); advance(1); s = ns.cdb.session
check("data version set", ns.db.schema == 3, tostring(ns.db.schema))

-- rulebook + keys
check("suffix gear gets its own key", ns.ItemKey(SUFFIX) == "1234:-19", tostring(ns.ItemKey(SUFFIX)))
check("plain item key is the id", ns.ItemKey(TB) == 12359)
check("clam is a container", ns.Eligibility(CLAM) == "zero")
local v, src, _, _, _, info = ns.Valuate(CHEAP)
check("value is exactly Auctionator's price (no cap)", v == 99990000 and src == "AH", ns.MoneyShort(v) .. " " .. tostring(src))
-- with 14 days of history around 10g, a 99g price is flagged but not changed
ns.db.prices[4000] = {}
for i = 1, 5 do ns.db.prices[4000][date("%Y-%m-%d", time() - i * 86400)] = 100000 end
ahPrices[4000] = 990000
v, src, _, _, _, info = ns.Valuate(CHEAP)
check("unusual price flagged, value unchanged", v == 990000 and info.unusual and ns.ValuationNote(info):find("9.9x"), tostring(ns.ValuationNote(info)))

-- session: clam (0) -> open -> pearl counts once
fire("CHAT_MSG_LOOT", "You receive loot: " .. CLAM .. "."); advance(1)
check("looted clam counts as 0", ns.Session:Stats().items == 0, tostring(ns.Session:Stats().items))
GetNumLootItems = function() return 1 end
GetLootSourceInfo = function(i) return "Item-1-0-ABC", 1 end
C_Item = C_Item or {}; C_Item.GetItemLinkByGUID = function(g) return CLAM end
fire("LOOT_OPENED"); fire("CHAT_MSG_LOOT", "You receive loot: " .. PEARL .. "."); fire("LOOT_CLOSED"); advance(1)
local st = ns.Session:Stats()
check("opened clam: pearl counts, clam gone", st.items == 200 and not s.items[CLAM], "items " .. st.items)
GetLootSourceInfo = function() return "Creature-0-1", 1 end

-- disenchant a blade looted this session
fire("CHAT_MSG_LOOT", "You receive loot: " .. mkLink(1234) .. "."); advance(1)
local before = ns.Session:Stats().items
SpellIsTargeting = function() return true end
setBag({ [1] = { mkLink(1234), 1 } })
C_Container.UseContainerItem(0, 1); SpellIsTargeting = function() return false end
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "x", 13262)
GetLootSourceInfo = nil
fire("LOOT_OPENED"); fire("CHAT_MSG_LOOT", "You receive loot: " .. DUST .. "x2."); advance(1)
local after = ns.Session:Stats().items
check("disenchant is a swap (blade out, dust in)", after == before - 500 + 100, ("%d -> %d"):format(before, after))

-- AFK pause takes the 5 idle minutes off
UnitIsAFK = function() return true end
s.resumed = time() - 900; s.started = time() - 900; s.elapsed = 0
fire("PLAYER_FLAGS_CHANGED", "player")
check("AFK pauses and removes idle time", s.paused and math.abs(s.elapsed - 600) < 3, "elapsed " .. s.elapsed)
UnitIsAFK = function() return false end; fire("PLAYER_FLAGS_CHANGED", "player")
check("back from AFK resumes", not s.paused)

-- ledger: bulk vendor sales merged into one gold change
setBag({ [1] = { mkLink(2589), 20 }, [2] = { mkLink(2770), 5 }, [3] = { PEARL, 1 } })
fire("MERCHANT_SHOW"); MerchantFrame.shown = true
local n0 = #ns.db.ledger
C_Container.UseContainerItem(0, 1); C_Container.UseContainerItem(0, 2); C_Container.UseContainerItem(0, 3)
setMoney(GetMoney() + 260 + 25 + 200); advance(2)   -- all three arrive as ONE gold change
local items = {}
for i = n0 + 1, #ns.db.ledger do local e = ns.db.ledger[i]; items[#items + 1] = e.k .. ":" .. ns.LinkName(e.i or "?") .. "=" .. e.a end
check("merged vendor sales split per item", #items == 3 and items[1]:find("Linen") and items[3]:find("Pearl"), table.concat(items, ", "))
-- damaged gear sells below vendor price
setBag({ [1] = { mkLink(1234), 1 } }); n0 = #ns.db.ledger
C_Container.UseContainerItem(0, 1); setMoney(GetMoney() + 400); advance(2)
local e = ns.db.ledger[#ns.db.ledger]
check("damaged gear sale still matched", e.k == "VENDOR_SALE" and e.i and e.i:find("Blade"), e.k .. " " .. tostring(e.i and ns.LinkName(e.i)))
-- repair with exact cost
GetRepairAllCost = function() return 1234 end; RepairAllItems(); setMoney(GetMoney() - 1234); advance(2)
check("repair matched by amount", ns.db.ledger[#ns.db.ledger].k == "REPAIR")
fire("MERCHANT_CLOSED"); MerchantFrame.shown = false
-- recategorize
ns.Ledger.SetCategory(ns.db.ledger[#ns.db.ledger], "OTHER_OUT")
check("recategorize an entry", ns.db.ledger[#ns.db.ledger].k == "OTHER_OUT" and ns.db.ledger[#ns.db.ledger].manual)

-- portfolio journal (bank seen so the basis may change)
local P = ns.Portfolio
local me = ns.CharKey(); ns.db.chars[me].bankT = time()
setBag({ [1] = { TB, 10 } }); ns.Wealth:ScanBags(); advance(5)
P:SetBasis(12359, 20000, 10); advance(2)
-- cursor holds 4 bars while bags are scanned: nothing changes
cursor = true; setBag({ [1] = { TB, 6 } }); ns.Wealth:ScanBags(); advance(2)
check("scan waits while an item is on the cursor", P:Held(12359) == 10, "held " .. P:Held(12359))
cursor = false; setBag({ [1] = { TB, 10 } }); advance(3)
-- 3 bars vanish with no reason -> parked + unexplained, basis kept
setBag({ [1] = { TB, 7 } }); ns.Wealth:ScanBags(); advance(10)
local b = P:Basis(12359)
check("unexplained drop keeps the buy price", b.qty == 10 and b.parked == 3 and P:OpenUnexplained() == 3, ("qty %d parked %d open %d"):format(b.qty, b.parked, P:OpenUnexplained()))
-- they come back (were in a bag we hadn't scanned)
setBag({ [1] = { TB, 10 } }); ns.Wealth:ScanBags(); advance(10)
check("returned units are matched automatically", b.parked == 0 and P:OpenUnexplained() == 0, ("parked %d open %d"):format(b.parked, P:OpenUnexplained()))
-- crafting uses 4 bars (a spell cast explains it)
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "y", 9999)
setBag({ [1] = { TB, 6 } }); ns.Wealth:ScanBags(); advance(10)
check("explained use shrinks the basis", b.qty == 6 and b.parked == 0, ("qty %d parked %d"):format(b.qty, b.parked))
-- trade 2 bars to your own alt: still yours
ns.db.chars["Altgirl-Forever"] = { name = "Altgirl", realm = "Forever", inv = {}, bankT = time() }
UnitName = function(u) if u == "NPC" then return "Altgirl" end return "Fishbro" end
GetTradePlayerItemLink = function(i) return i == 1 and TB or nil end
GetTradePlayerItemInfo = function(i) return "Thorium Bar", nil, 2 end
ERR_TRADE_COMPLETE = "Trade complete."
fire("TRADE_SHOW"); fire("TRADE_PLAYER_ITEM_CHANGED"); fire("TRADE_ACCEPT_UPDATE", 1, 1); fire("UI_INFO_MESSAGE", 0, "Trade complete.")
fire("TRADE_CLOSED"); setBag({ [1] = { TB, 4 } }); ns.Wealth:ScanBags(); advance(15)
check("trade to own alt keeps the buy price", b.qty == 6 and P:Held(12359) == 6 and P:OpenUnexplained() == 0, ("qty %d held %d"):format(b.qty, P:Held(12359)))
-- resolve flow
setBag({ [1] = { TB, 3 } }); ns.Wealth:ScanBags(); advance(10)
local u = ns.db.unexplained[#ns.db.unexplained]
P:ResolveUnexplained(u, "used"); advance(1)
check("resolve as used shrinks the basis", b.qty == 5 and b.parked == 0, ("qty %d parked %d"):format(b.qty, b.parked))

-- self-checks
local res = ns.Audit:Run()
local fails = ns.Audit:Failures(res)
for _, r in ipairs(res) do if not r.ok then print("   audit fail:", r.name, r.detail) end end
check("self-checks pass", fails == 0, fails .. " failing")
for _, id in ipairs({ "pnl", "aum", "port", "rpt", "gl", "cmpl" }) do ns:ShowPage(id) end
SlashCmdList.FISHPARTNERS("check")
print("errors:", #ns.errors)
print("OK21")
