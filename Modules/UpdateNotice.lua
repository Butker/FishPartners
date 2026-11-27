-- Fish & Partners: update notice
-- Copies of the addon quietly tell each other their version (guild + group, hidden
-- addon messages). If anyone you meet runs a newer version, you get one notice.
-- Copies that see an older version reply with theirs, so the news spreads.

local _, ns = ...
local U = {}
ns.Update = U

local PREFIX = "FPWM1"
U.REPO_URL = "https://github.com/Butker/FishPartners"
U.UPDATER_URL = "https://github.com/Butker/FishPartners/raw/main/tools/Update-FishPartners.bat"

local function parts(v)
    local out = {}
    for n in tostring(v or ""):gmatch("%d+") do out[#out + 1] = tonumber(n) end
    return out
end

-- -1 if a < b, 0 if equal, 1 if a > b (nil if either isn't a version)
function U.Compare(a, b)
    local pa, pb = parts(a), parts(b)
    if #pa == 0 or #pb == 0 then return nil end
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x < y and -1 or 1 end
    end
    return 0
end

local function say(chan, target)
    if ns.VERSION == "dev" then return end
    ns.Comm:Send("V;" .. ns.VERSION, chan, target, "V" .. tostring(chan) .. tostring(target))
end

local lastGroupSend = 0
local function announceGroup()
    if not (IsInGroup and IsInGroup()) then return end
    if GetTime() - lastGroupSend < 60 then return end
    lastGroupSend = GetTime()
    say(ns.Comm.GroupChannel())
end

local function announceGuild()
    if IsInGuild and IsInGuild() then say("GUILD") end
end

function U:Notify()
    local v = U.newer
    if not v then return end
    ns.Print(ns.Color("amber", "UPDATE AVAILABLE") .. "  Fish & Partners " .. ns.Color("green", v) ..
        " is out (you have " .. ns.VERSION .. ").")
    ns.Print("Close the game and run " .. ns.Color("amber", "Update-FishPartners") ..
        ", or type " .. ns.Color("amber", "/fp update") .. " for the download link.")
end

local replied = {}
ns:On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
    if prefix ~= PREFIX or type(text) ~= "string" then return end
    local kind, version = strsplit(";", text)
    if kind ~= "V" or not version then return end
    if not sender or ns.Comm.IsMe(sender) then return end
    local cmp = U.Compare(ns.VERSION, version)
    if cmp == nil then return end
    if cmp < 0 then
        -- they're ahead
        if not U.newer or U.Compare(U.newer, version) < 0 then
            U.newer = version
            U.newerFrom = sender
            U:Notify()
        end
    elseif cmp > 0 and sender then
        -- we're ahead: tell them (once per person per 15 min)
        local t = replied[sender]
        if not t or GetTime() - t > 900 then
            replied[sender] = GetTime()
            say("WHISPER", sender)
        end
    end
end)

ns:OnInit(function()
    C_Timer.After(20, function() announceGuild(); announceGroup() end)
    C_Timer.NewTicker(1800, announceGuild) -- every 30 min, for people who log in later
end)
ns:On("GROUP_ROSTER_UPDATE", function() if ns.db then C_Timer.After(5, announceGroup) end end)

ns:AddTicker(function()
    if U.newer then return ns.Color("amber", "UPDATE AVAILABLE: v" .. U.newer .. "  (/fp update)") end
end)
