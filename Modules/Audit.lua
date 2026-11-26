-- Fish & Partners: self-checks
-- The desk audits its own books at login (after things settle) and once an hour.
-- If anything fails it says so once in chat; /fp check shows every check.
--
--   1. Gold balance   the ledger's total since login = your real gold change since login
--   2. Session        no negative positions; the clock never runs ahead of the wall clock
--   3. Cost basis     units with a buy price never exceed units held (+ parked units)
--   4. Inventory      no negative counts anywhere
--   5. Unexplained    how many units are waiting for you to resolve

local _, ns = ...
local A = {}
ns.Audit = A

local loginMoney, loginTime

ns:OnInit(function()
    loginMoney, loginTime = GetMoney(), time()
end)

local function check(results, ok, name, detail)
    results[#results + 1] = { ok = ok, name = name, detail = detail }
end

function A:Run()
    local results = {}
    local me = ns.CharKey()

    -- 1. Gold balance (only meaningful when no gold change is still being classified)
    if ns.Ledger and ns.Ledger.PendingCount and ns.Ledger.PendingCount() == 0 and loginMoney then
        local sum = 0
        for i = #ns.db.ledger, 1, -1 do
            local e = ns.db.ledger[i]
            if e.t < loginTime then break end
            if e.c == me then sum = sum + e.a end
        end
        local real = GetMoney() - loginMoney
        check(results, sum == real, "Gold balance",
            sum == real and ("ledger matches your gold since login (" .. ns.MoneyShort(real, true) .. ")")
            or ("ledger says " .. ns.MoneyShort(sum, true) .. ", your gold changed " .. ns.MoneyShort(real, true)))
    end

    -- 2. Session
    local s = ns.cdb and ns.cdb.session
    if s and s.active then
        local bad = 0
        for _, it in pairs(s.items or {}) do
            if (it.qty or 0) < 0 or (it.unit or 0) < 0 then bad = bad + 1 end
        end
        local elapsed = ns.Session:Elapsed()
        local wall = time() - (s.started or time())
        check(results, bad == 0, "Session positions", bad == 0 and "no negative positions" or (bad .. " negative position(s)"))
        check(results, elapsed <= wall + 5, "Session clock", elapsed <= wall + 5 and "clock is consistent"
            or ("clock shows " .. ns.Duration(elapsed) .. " but the session started " .. ns.Duration(wall) .. " ago"))
    end

    -- 3. Cost basis
    if ns.Portfolio and ns.Portfolio:SafeToReconcile() then
        local over = {}
        for key, b in pairs(ns.db.basis or {}) do
            local held = ns.Portfolio:Held(key)
            local live = (b.qty or 0) - (b.parked or 0)
            if (b.parked or 0) < 0 or live > held + 0.001 then over[#over + 1] = key end
        end
        check(results, #over == 0, "Cost basis", #over == 0 and "never covers more units than you hold"
            or (#over .. " item(s) have a buy price on more units than you hold"))
    end

    -- 4. Inventory
    local neg = 0
    for _, ch in pairs(ns.db.chars or {}) do
        for _, e in pairs(ch.inv or {}) do
            for _, loc in ipairs({ "b", "k", "m", "a" }) do
                if e[loc] and e[loc] < 0 then neg = neg + 1 end
            end
        end
    end
    check(results, neg == 0, "Inventory", neg == 0 and "no negative counts" or (neg .. " negative count(s)"))

    -- 5. Unexplained (informational: not a failure)
    local open = ns.Portfolio and ns.Portfolio:OpenUnexplained() or 0
    results[#results + 1] = { ok = true, info = true, name = "Unexplained",
        detail = open == 0 and "every item is accounted for" or (open .. " unit(s) waiting in Portfolio → UNEXPLAINED") }

    A.last = { t = time(), results = results }
    return results
end

function A:Failures(results)
    local n = 0
    for _, r in ipairs(results or {}) do if not r.ok then n = n + 1 end end
    return n
end

function A:Print(results)
    results = results or self:Run()
    ns.Print(ns.Color("orange", "SELF-CHECK") .. ns.Color("grey", "  ·  " .. date("%H:%M")))
    for _, r in ipairs(results) do
        local mark = r.info and ns.Color("cyan", "INFO") or (r.ok and ns.Color("green", "PASS") or ns.Color("red", "FAIL"))
        ns.Print(mark .. "  " .. r.name .. ns.Color("grey", ": " .. r.detail))
    end
end

local warned = {}
local function quietRun()
    local results = A:Run()
    local n = A:Failures(results)
    if n > 0 then
        local key = {}
        for _, r in ipairs(results) do if not r.ok then key[#key + 1] = r.name end end
        key = table.concat(key, ",")
        if not warned[key] then
            warned[key] = true
            ns.Print(ns.Color("red", "Self-check: " .. n .. " problem" .. (n == 1 and "" or "s") .. " found.") ..
                " Type " .. ns.Color("amber", "/fp check") .. " for details.")
        end
    end
end

ns:OnInit(function()
    C_Timer.After(45, quietRun)
    C_Timer.NewTicker(3600, quietRun)
end)
