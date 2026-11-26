-- Fish & Partners: Valuation desk + the rulebook
--
-- ONE place decides what an item is and what it's worth. Every module asks here.
--
-- Item identity (ns.ItemKey):
--   * normally the itemID (a number)
--   * gear with a random suffix ("of the Bear") gets "itemID:suffixID", because each
--     variant has its own price
--
-- Eligibility (ns.Eligibility):
--   "skip"  quest items: never tracked anywhere (no value, can't be sold)
--   "zero"  openable containers (clams, lockboxes, bags of loot): tracked at 0,
--           their contents count when you open them
--   "count" everything else
--
-- Value (ns.Valuate):
--   * bound / BoP items: vendor price
--   * otherwise the Auctionator price if it beats vendor by the premium setting
--     (gear 10%, everything else 5%), else vendor price
--   * thin-market cap: an AH price is capped at 3x the item's recent median
--     (14 days of daily prices), or 50x vendor price when there's no history yet
--   * stale flag: Auctionator prices older than the "stale after" setting are marked

local _, ns = ...
local floor, max, min = math.floor, math.max, math.min

local CLASS_WEAPON, CLASS_ARMOR = 2, 4
local CLASS_QUEST = (Enum and Enum.ItemClass and Enum.ItemClass.Questitem) or 12

---------------------------------------------------------------------------
-- Item identity
---------------------------------------------------------------------------
-- Fields of an item link: item:id:enchant:gem1:gem2:gem3:gem4:suffixID:unique:...
local function linkFields(link)
    local s = type(link) == "string" and link:match("item:([%-%d:]*)")
    if not s then return nil end
    local f = {}
    for v in (s .. ":"):gmatch("([^:]*):") do f[#f + 1] = v end
    return f
end

-- The key every module stores items under
function ns.ItemKey(x)
    if x == nil then return nil end
    if type(x) == "number" then return x end
    if type(x) == "string" and x:match("^%d+$") then return tonumber(x) end
    if type(x) == "string" and x:match("^%d+:%-?%d+$") then return x end -- already a key
    local f = linkFields(x)
    if not f then return nil end
    local id = tonumber(f[1])
    if not id then return nil end
    local suffix = tonumber(f[7] or "")
    if suffix and suffix ~= 0 then return id .. ":" .. suffix end
    return id
end

-- The plain itemID behind a key (for APIs that want a number)
function ns.KeyItemID(key)
    if type(key) == "number" then return key end
    if type(key) == "string" then return tonumber(key:match("^(%d+)")) end
end

---------------------------------------------------------------------------
-- Rulebook
---------------------------------------------------------------------------
function ns.IsQuestItem(item)
    if not item then return false end
    local id = (type(item) == "string" and not item:find("|H")) and ns.KeyItemID(item) or item
    if not id then return false end
    local classID = select(6, ns.GetItemInfoInstant(id))
    if classID == CLASS_QUEST then return true end
    local bindType = select(14, ns.GetItemInfo(id))
    return bindType == 4
end

function ns.IsGear(link)
    local classID = select(6, ns.GetItemInfoInstant(link))
    return classID == CLASS_WEAPON or classID == CLASS_ARMOR
end

-- Openable container? Read from the item's tooltip ("<Right Click to Open>"), cached.
local openableCache = {}
local scanTip
local function tooltipLines(link)
    if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
        local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
        if ok and type(data) == "table" and type(data.lines) == "table" then
            local out = {}
            for _, l in ipairs(data.lines) do out[#out + 1] = l.leftText end
            return out
        end
    end
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "FishPartnersScanTip", UIParent, "GameTooltipTemplate")
    end
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTip:ClearLines()
    local ok = pcall(scanTip.SetHyperlink, scanTip, link)
    if not ok then return nil end
    local out = {}
    for i = 1, (scanTip:NumLines() or 0) do
        local fs = _G["FishPartnersScanTipTextLeft" .. i]
        out[#out + 1] = fs and fs:GetText()
    end
    scanTip:Hide()
    return out
end

function ns.IsOpenable(link)
    local id = ns.KeyItemID(ns.ItemKey(link))
    if not id then return false end
    if openableCache[id] ~= nil then return openableCache[id] end
    local lines = tooltipLines(type(link) == "string" and link or ("item:" .. id))
    if not lines or #lines == 0 then return false end -- not loaded yet: don't cache
    local marker = _G.ITEM_OPENABLE or "<Right Click to Open>"
    local found = false
    for _, t in ipairs(lines) do
        if t and t == marker then found = true break end
    end
    openableCache[id] = found
    return found
end

-- "skip" | "zero" | "count"
function ns.Eligibility(item)
    if not item then return "skip" end
    if ns.IsQuestItem(item) then return "skip" end
    if type(item) == "string" and item:find("|H") and ns.IsOpenable(item) then return "zero" end
    return "count"
end

---------------------------------------------------------------------------
-- Prices
---------------------------------------------------------------------------
function ns.HasAuctionator()
    return type(Auctionator) == "table" and type(Auctionator.API) == "table" and type(Auctionator.API.v1) == "table"
end

function ns.GetAHPrice(link, itemID)
    if not ns.HasAuctionator() then return nil end
    local api = Auctionator.API.v1
    local ok, p
    if link and api.GetAuctionPriceByItemLink then
        ok, p = pcall(api.GetAuctionPriceByItemLink, ns.CALLER, link)
        if ok and type(p) == "number" and p > 0 then return p end
    end
    if itemID and api.GetAuctionPriceByItemID then
        ok, p = pcall(api.GetAuctionPriceByItemID, ns.CALLER, itemID)
        if ok and type(p) == "number" and p > 0 then return p end
    end
    return nil
end

-- Days since Auctionator last saw the item (nil = unknown)
function ns.GetAHAge(link)
    if not (link and ns.HasAuctionator() and Auctionator.API.v1.GetAuctionAgeByItemLink) then return nil end
    local ok, age = pcall(Auctionator.API.v1.GetAuctionAgeByItemLink, ns.CALLER, link)
    if ok and type(age) == "number" then return age end
end

-- Daily AH price memory per item key (feeds the thin-market cap)
local function priceStore()
    if not ns.db then return nil end
    ns.db.prices = ns.db.prices or {}
    return ns.db.prices
end

local function recordPrice(key, price)
    local store = priceStore()
    if not store or not key or not price then return end
    local h = store[key]
    if not h then h = {}; store[key] = h end
    h[ns.Today()] = floor(price)
end

function ns.RecentMedian(key, days)
    local store = priceStore()
    local h = store and store[key]
    if not h then return nil end
    local vals = {}
    for i = 1, days or 14 do
        local v = h[date("%Y-%m-%d", time() - i * 86400)]
        if v then vals[#vals + 1] = v end
    end
    if #vals < 3 then return nil end
    table.sort(vals)
    local n = #vals
    if n % 2 == 1 then return vals[(n + 1) / 2] end
    return floor((vals[n / 2] + vals[n / 2 + 1]) / 2)
end

ns:OnInit(function()
    local store = priceStore()
    local cutoff = date("%Y-%m-%d", time() - 30 * 86400)
    for _, h in pairs(store) do
        for d in pairs(h) do if d < cutoff then h[d] = nil end end
    end
end)

---------------------------------------------------------------------------
-- Valuate
-- Returns: unitValue, source, ahPrice, vendorPrice, isGear, info
--   source = "AH" | "VND" | "BOX" (container) | "---"
--   info   = { capped = bool, stale = bool, age = days, cap = copper }
---------------------------------------------------------------------------
function ns.Valuate(link, isBound)
    if not link then return 0, "---" end
    local name, _, _, _, _, _, _, _, _, _, vendor, classID, _, bindType = ns.GetItemInfo(link)
    if not name then return nil end -- not cached yet
    vendor = vendor or 0
    local isGear = classID == CLASS_WEAPON or classID == CLASS_ARMOR
    local S = ns.S
    local info = {}

    if ns.IsQuestItem(link) then return 0, "---", nil, 0, isGear, info end
    if type(link) == "string" and link:find("|H") and ns.IsOpenable(link) then
        return 0, "BOX", nil, vendor, isGear, info
    end
    if isBound or bindType == 1 then
        return vendor, vendor > 0 and "VND" or "---", nil, vendor, isGear, info
    end

    local key = ns.ItemKey(link)
    local itemID = ns.KeyItemID(key)
    local ah = ns.GetAHPrice(link, itemID)
    if ah then
        local age = ns.GetAHAge(link)
        info.age = age
        info.stale = age ~= nil and age > (S.priceStaleDays or 7)
        -- remember fresh prices (today's scan) for the thin-market cap
        if age == nil or age <= 1 then recordPrice(key, ah) end
        -- thin-market cap
        local med = ns.RecentMedian(key, 14)
        local cap
        if med then cap = med * 3
        elseif vendor > 0 then cap = vendor * 50 end
        if cap and ah > cap then
            info.capped, info.cap = true, cap
            ah = cap
        end
    end

    local ahNet = ah
    if ah and S.deductAHCut then ahNet = floor(ah * (1 - (S.ahCut or 5) / 100)) end
    local margin = (isGear and S.gearMargin or S.otherMargin) or 0
    if ahNet and ahNet > 0 and ahNet >= vendor * (1 + margin / 100) then
        return ahNet, "AH", ah, vendor, isGear, info
    end
    return vendor, vendor > 0 and "VND" or "---", ah, vendor, isGear, info
end

-- One line describing a valuation's caveats, for tooltips (or nil)
function ns.ValuationNote(info)
    if not info then return nil end
    local parts = {}
    if info.capped then parts[#parts + 1] = "capped at " .. ns.MoneyShort(info.cap) .. " (thin market)" end
    if info.stale then parts[#parts + 1] = "AH price " .. (info.age or "?") .. " days old" end
    if #parts == 0 then return nil end
    return table.concat(parts, " · ")
end
