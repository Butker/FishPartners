-- 2.1.4 WoW Forever name format: "Name Realm" (space) in addon senders and loot lines
dofile(TESTS .. "/mock.lua")
local party = { party1 = { "Qin", "Shock", "MONK" }, party2 = { "Elvanas", "Darkmoon", "PRIEST" },
  party3 = { "Baraca", "One", "WARRIOR" }, party4 = { "Céll", "Cat", "MAGE" } }
IsInGroup = function() return true end; IsInRaid = function() return false end
GetNumSubgroupMembers = function() return 4 end
UnitExists = function(u) return party[u] ~= nil or u == "player" end
UnitIsUnit = function(a, b) return a == b end
UnitName = function(u) if party[u] then return party[u][1], party[u][2] end return "Fish" end
UnitFullName = function(u) if u == "player" then return "Fish", "Weaver" end return UnitName(u) end
UnitClass = function(u) if party[u] then return "x", party[u][3] end return "Mage", "MAGE" end
GetRealmName = function() return "Weaver" end
GetNormalizedRealmName = function() return "Weaver" end
for _, c in ipairs({ "MONK", "PRIEST", "WARRIOR" }) do RAID_CLASS_COLORS[c] = { r = 1, g = 1, b = 1 } end
LOOT_ITEM = "%s receives loot: %s." LOOT_ITEM_MULTIPLE = "%s receives loot: %sx%d."
local sent = {}
C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end, IsAddonMessagePrefixRegistered = function() return true end,
  SendAddonMessage = function(p, m, c) sent[#sent + 1] = m; return 0 end }
local printed = {}
local ns = {}
local toc = io.open(ADDON_ROOT .. "/FishPartners.toc"):read("a")
for line in toc:gmatch("[^\r\n]+") do if not line:match("^##") and line:match("%.lua$") then
  assert(loadfile(ADDON_ROOT .. "/" .. line:gsub("\\", "/")))("FishPartners", ns) end end
fire("PLAYER_LOGIN"); advance(25)
local oldPrint = ns.Print; ns.Print = function(m) printed[#printed + 1] = m; oldPrint(m) end
local function check(name, cond, detail) print((cond and "PASS " or "FAIL ") .. name .. (detail and ("  [" .. detail .. "]") or "")) end
local CM = ns.Comm

check("'Céll Cat' is Céll-Cat", CM.Who("Céll Cat") == "Céll-Cat", tostring(CM.Who("Céll Cat")))
check("'Céll-Cat' still works", CM.Who("Céll-Cat") == "Céll-Cat")
check("no-break space works", CM.Who("Céll\194\160Cat") == "Céll-Cat")
check("'Fish Weaver' is me", CM.IsMe("Fish Weaver"))
check("'Fish-Weaver' is me", CM.IsMe("Fish-Weaver"))
check("Céll is not me", not CM.IsMe("Céll Cat"))

SlashCmdList.FISHPARTNERS("start"); advance(3)
local s = ns.cdb.session
-- my own ping echoed back is ignored
printed = {}
fire("CHAT_MSG_ADDON", "FPWM1", "I;2.1.4", "PARTY", "Fish Weaver"); advance(1)
check("own ping ignored", not table.concat(printed, " "):find("answered"))
-- Céll's desk talks
fire("CHAT_MSG_ADDON", "FPWM1", "H;2.1.4", "PARTY", "Céll Cat")
fire("CHAT_MSG_ADDON", "FPWM1", "S;50000;20000;0;30000;600", "PARTY", "Céll Cat"); advance(3)
check("Céll's session totals accepted", s.party["Céll-Cat"] and s.party["Céll-Cat"].sync ~= nil)
check("house rules on with Céll", s.groupRules == true and ns.Group:PeerList()[1] == "Céll-Cat")
-- cross-realm loot line with a space
fire("CHAT_MSG_LOOT", "Baraca One receives loot: " .. mkLink(2589) .. "x3."); advance(3)
check("'Baraca One' loot credited to Baraca-One", s.party["Baraca-One"] and s.party["Baraca-One"].items[mkLink(2589)] ~= nil)
-- prices from Céll accepted
fire("CHAT_MSG_ADDON", "FPWM1", "P;2589;30;" .. math.floor(time() / 86400), "PARTY", "Céll Cat"); advance(1)
check("Céll's price used", s.party["Baraca-One"].items[mkLink(2589)].unit == 30, tostring(s.party["Baraca-One"].items[mkLink(2589)].unit))
-- the board shows Céll's own reported numbers (50000 total)
local pv = CreateFrame("Frame", nil, UIParent)
ns.Party:BuildView(pv)
local captured
local orig = pv.board.SetData
pv.board.SetData = function(self, rows, ...) captured = rows; return orig(self, rows, ...) end
ns.Party:RefreshView(pv)
local cellRow
for _, r in ipairs(captured or {}) do if tostring(r.cells[1]):find("Céll") then cellRow = r end end
check("board shows Céll's reported total", cellRow and tostring(cellRow.cells[5]):find(ns.MoneyShort(50000), 1, true) ~= nil,
  cellRow and tostring(cellRow.cells[5]))
printed = {}
SlashCmdList.FISHPARTNERS("sync"); advance(1)
local out = table.concat(printed, "\n"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
check("sync: Céll heard", out:find("Céll%-Cat: heard") ~= nil)
check("sync: nothing unmatched", out:find("couldn't match") == nil)
check("sync: house rules on", out:find("House rules: ON") ~= nil)
ns:ShowPage("pnl")
print("errors:", #ns.errors)
for _, e in ipairs(ns.errors) do print(e.msg or e) end
print("OK24")
