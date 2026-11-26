-- Fish & Partners: Valuation desk
-- Prices an item at vendor or Auctionator AH value using a premium threshold:
--   * Weapons / armor: AH must beat vendor by >= gearMargin %  (default 10)
--   * Everything else: AH must beat vendor by >= otherMargin % (default 5)
--   * Soulbound / BoP: always vendor (can't be listed)

local _, ns = ...
local floor = math.floor

local CLASS_WEAPON, CLASS_ARMOR = 2, 4

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

-- Quest items (the "Quest" item class, or bound-to-quest) can't be sold and are
-- worth nothing, so the desk never tracks them. Works on uncached items too.
local CLASS_QUEST = (Enum and Enum.ItemClass and Enum.ItemClass.Questitem) or 12
function ns.IsQuestItem(item)
    if not item then return false end
    local classID = select(6, ns.GetItemInfoInstant(item))
    if classID == CLASS_QUEST then return true end
    local bindType = select(14, ns.GetItemInfo(item))
    return bindType == 4
end

function ns.IsGear(link)
    local classID = select(6, ns.GetItemInfoInstant(link))
    return classID == CLASS_WEAPON or classID == CLASS_ARMOR
end

-- Returns: unitValue, source ("AH" | "VND" | "---"), ahPrice, vendorPrice, isGear
function ns.Valuate(link, isBound)
    if not link then return 0, "---" end
    local name, _, _, _, _, _, _, _, _, _, vendor, classID, _, bindType = ns.GetItemInfo(link)
    if not name then return nil end -- not cached yet
    vendor = vendor or 0
    local isGear = classID == CLASS_WEAPON or classID == CLASS_ARMOR
    local S = ns.S

    if isBound or bindType == 1 or bindType == 4 then
        return vendor, vendor > 0 and "VND" or "---", nil, vendor, isGear
    end

    local itemID = select(1, ns.GetItemInfoInstant(link))
    local ah = ns.GetAHPrice(link, itemID)
    local ahNet = ah
    if ah and S.deductAHCut then ahNet = floor(ah * (1 - (S.ahCut or 5) / 100)) end

    local margin = (isGear and S.gearMargin or S.otherMargin) or 0
    if ahNet and ahNet > 0 and ahNet >= vendor * (1 + margin / 100) then
        return ahNet, "AH", ah, vendor, isGear
    end
    return vendor, vendor > 0 and "VND" or "---", ah, vendor, isGear
end
