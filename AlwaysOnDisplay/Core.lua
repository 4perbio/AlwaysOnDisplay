local addonName, ns = ...

ns.defaults = {
    playerHealth = true,
    playerPower  = true,
    targetHealth = true,
    targetPower  = true,
    format       = "VALUE",  -- "VALUE" | "PERCENT" | "BOTH"
    shortNumbers = true,
    minimapButton = true,
    minimapAngle = 225,      -- not shown in the panel; set by dragging the button
}

-- key -> { unit, kind, setting, bar, overlay, text }
ns.displays = {
    { key = "playerHealth", unit = "player", kind = "health" },
    { key = "playerPower",  unit = "player", kind = "power"  },
    { key = "targetHealth", unit = "target", kind = "health" },
    { key = "targetPower",  unit = "target", kind = "power"  },
}

local function Path(root, ...)
    local node = _G[root]
    for i = 1, select("#", ...) do
        if not node then return nil end
        node = node[select(i, ...)]
    end
    return node
end

local BAR_CANDIDATES = {
    player = {
        health = function()
            return _G.PlayerFrameHealthBar
                or Path("PlayerFrame", "PlayerFrameContent", "PlayerFrameContentMain", "HealthBarsContainer", "HealthBar")
                or Path("PlayerFrame", "healthbar")
        end,
        power = function()
            return _G.PlayerFrameManaBar
                or Path("PlayerFrame", "PlayerFrameContent", "PlayerFrameContentMain", "ManaBarArea", "ManaBar")
                or Path("PlayerFrame", "manabar")
        end,
    },
    target = {
        health = function()
            return _G.TargetFrameHealthBar
                or Path("TargetFrame", "TargetFrameContent", "TargetFrameContentMain", "HealthBarsContainer", "HealthBar")
                or Path("TargetFrame", "healthbar")
        end,
        power = function()
            return _G.TargetFrameManaBar
                or Path("TargetFrame", "TargetFrameContent", "TargetFrameContentMain", "ManaBar")
                or Path("TargetFrame", "manabar")
        end,
    },
}

local function ShortNumber(n)
    if not ns.db.shortNumbers then return tostring(n) end
    if n >= 1e6 then
        return (string.format("%.1fm", n / 1e6):gsub("%.0m", "m"))
    elseif n >= 1e4 then
        return (string.format("%.1fk", n / 1e3):gsub("%.0k", "k"))
    end
    return tostring(n)
end

---------------------------------------------------------------------------
-- Secret values
--
-- On WoW Forever, UnitHealth/UnitPower (and sometimes their max) can return
-- "secret" numbers. Addon code may not do arithmetic, comparisons or boolean
-- tests on them, but may hand them to FontString:SetText. So: never touch a
-- secret directly, try the formatting calls that are documented to accept
-- secrets inside pcall, and fall back to showing the raw current value.
---------------------------------------------------------------------------
local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

-- nil-check that is safe on secrets (type() is allowed, == / and / or are not).
local function Has(v)
    return type(v) ~= "nil"
end

-- string.format that never raises; nil when the client refuses the arguments.
local function TryFormat(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    if ok then return s end
end

-- Formats with plain string.format when nothing is secret, otherwise via TryFormat.
local function Join(fmt, ...)
    for i = 1, select("#", ...) do
        if IsSecret((select(i, ...))) then return TryFormat(fmt, ...) end
    end
    return string.format(fmt, ...)
end

local function Short(v)
    if not IsSecret(v) then return ShortNumber(v) end
    if ns.db.shortNumbers and AbbreviateLargeNumbers then
        local ok, s = pcall(AbbreviateLargeNumbers, v)
        if ok and Has(s) then return s end
    end
    return v
end

-- Percentage as a plain whole number, a secret number, or nil if unavailable.
local function Percent(d, cur, max)
    if not IsSecret(cur) and not IsSecret(max) then
        return math.floor(cur / max * 100 + 0.5)
    end
    local scale = CurveConstants and CurveConstants.ScaleTo100
    local ok, pct
    if d.kind == "health" and UnitHealthPercent and scale then
        ok, pct = pcall(UnitHealthPercent, d.unit, false, scale)
    elseif d.kind == "power" and UnitPowerPercent and scale then
        -- (unit, powerType, usePredicted, curve): without usePredicted the curve is
        -- ignored and a 0-1 fraction comes back, which showed as "(1%)" at full mana.
        ok, pct = pcall(UnitPowerPercent, d.unit, UnitPowerType(d.unit), false, scale)
    end
    if not ok or type(pct) ~= "number" then return nil end
    if IsSecret(pct) then return pct end
    return math.floor(pct + 0.5)
end

local function PercentText(pct)
    if not Has(pct) then return nil end
    if IsSecret(pct) then return TryFormat("%.0f%%", pct) end
    return pct .. "%"
end

-- Returns the text to show (possibly a secret string) and how it was built.
local function BuildText(d, cur, max, percentOnly)
    local secret = IsSecret(cur) or IsSecret(max)
    local how = secret and "secret" or "plain"
    local format = percentOnly and "PERCENT" or ns.db.format

    local valueText, pctText
    if format ~= "PERCENT" then valueText = Join("%s / %s", Short(cur), Short(max)) end
    if format ~= "VALUE" then pctText = PercentText(Percent(d, cur, max)) end

    local text
    if Has(valueText) and Has(pctText) then
        text = Join("%s (%s)", valueText, pctText)
        if not Has(text) then text = valueText end
    elseif Has(valueText) then
        text = valueText
    else
        text = pctText
    end
    if not Has(text) then
        -- Nothing could be formatted: the bare current value is always allowed.
        return cur, how .. ", raw value only"
    end
    if format ~= "VALUE" and not Has(pctText) then how = how .. ", no percent available" end
    return text, how
end

-- Blizzard's own hover text on a bar; muted while ours is shown so they don't overlap.
local function SetBlizzardTextAlpha(bar, alpha)
    for _, field in ipairs({ "TextString", "LeftText", "RightText" }) do
        local fs = bar[field]
        if fs and fs.SetAlpha then fs:SetAlpha(alpha) end
    end
end

local function Setup(d)
    if d.bar then return true end
    local bar = BAR_CANDIDATES[d.unit][d.kind]()
    if not bar then return false end
    d.bar = bar
    local overlay = CreateFrame("Frame", nil, bar)
    overlay:SetAllPoints(bar)
    overlay:SetFrameLevel(bar:GetFrameLevel() + 5)
    local text = overlay:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
    text:SetPoint("CENTER", overlay, "CENTER", 0, 0)
    d.overlay, d.text = overlay, text
    return true
end

-- Shows our text on a bar, or hides it; returns a short status for /aod debug.
local function UpdateDisplay(d)
    local unit = d.unit
    if not ns.db[d.key] then
        d.overlay:Hide()
        SetBlizzardTextAlpha(d.bar, 1)
        return "disabled"
    end

    if not UnitExists(unit) then
        d.overlay:Hide()
        return "no unit"
    end

    local cur, max
    if d.kind == "health" then
        if UnitIsDeadOrGhost(unit) then
            d.text:SetText(UnitIsGhost(unit) and "Ghost" or "Dead")
            d.overlay:Show()
            SetBlizzardTextAlpha(d.bar, 0)
            return "dead"
        end
        cur, max = UnitHealth(unit), UnitHealthMax(unit)
    else
        local powerType = UnitPowerType(unit)
        cur, max = UnitPower(unit, powerType), UnitPowerMax(unit, powerType)
    end

    -- A secret max means the unit has this resource; only a readable max can be checked.
    if not Has(max) or (not IsSecret(max) and max <= 0) then
        d.overlay:Hide()
        return "no resource"
    end

    -- Classic-style servers report enemy health as a 0-100 percentage.
    local percentOnly = d.kind == "health" and not IsSecret(max) and max == 100
        and not UnitIsUnit(unit, "player") and not UnitPlayerOrPetInParty(unit)
        and not UnitPlayerOrPetInRaid(unit)

    local text, how = BuildText(d, cur, max, percentOnly)
    d.text:SetText(text)
    d.overlay:Show()
    SetBlizzardTextAlpha(d.bar, 0)
    return "shown (" .. how .. ")"
end

function ns.Refresh(unit)
    for _, d in ipairs(ns.displays) do
        if d.text and (not unit or d.unit == unit) then
            local ok, status = pcall(UpdateDisplay, d)
            if ok then
                d.status, d.lastOK = status, true
            else
                -- Never leave the bar blank: give it back to Blizzard's text.
                d.overlay:Hide()
                SetBlizzardTextAlpha(d.bar, 1)
                d.status, d.lastOK = "error: " .. tostring(status), false
                if not d.reported then
                    d.reported = true
                    print("|cff33ff99AlwaysOnDisplay|r: could not show " .. d.key
                        .. " text, using the game's own text instead. Type /aod debug for details.")
                end
            end
        end
    end
end

-- /aod debug: what this client supports and what each bar is doing.
function ns.Debug()
    local p = function(s) print("|cff33ff99AOD|r " .. s) end
    p("issecretvalue: " .. tostring(issecretvalue ~= nil)
        .. ", UnitHealthPercent: " .. tostring(UnitHealthPercent ~= nil)
        .. ", UnitPowerPercent: " .. tostring(UnitPowerPercent ~= nil)
        .. ", CurveConstants.ScaleTo100: " .. tostring(CurveConstants ~= nil and CurveConstants.ScaleTo100 ~= nil)
        .. ", AbbreviateLargeNumbers: " .. tostring(AbbreviateLargeNumbers ~= nil))
    ns.Refresh()
    for _, d in ipairs(ns.displays) do
        local secrets = ""
        if d.bar and UnitExists(d.unit) then
            local okC, cur = pcall(d.kind == "health" and UnitHealth or function(u) return UnitPower(u, UnitPowerType(u)) end, d.unit)
            local okM, max = pcall(d.kind == "health" and UnitHealthMax or function(u) return UnitPowerMax(u, UnitPowerType(u)) end, d.unit)
            secrets = " | cur secret: " .. tostring(okC and IsSecret(cur)) .. ", max secret: " .. tostring(okM and IsSecret(max))
        end
        p(d.key .. ": " .. (d.bar and "bar found" or "BAR NOT FOUND") .. " | " .. tostring(d.status or "not updated") .. secrets)
    end
end

function ns.SetupAll()
    local missing
    for _, d in ipairs(ns.displays) do
        if not Setup(d) then missing = true end
    end
    if missing and not ns.warned then
        ns.warned = true
        print("|cff33ff99AlwaysOnDisplay|r: could not find some unit frame bars. Use /fstack over the bar and report its frame name.")
    end
    ns.Refresh()
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:RegisterUnitEvent("UNIT_HEALTH", "player", "target")
f:RegisterUnitEvent("UNIT_MAXHEALTH", "player", "target")
f:RegisterUnitEvent("UNIT_POWER_UPDATE", "player", "target")
f:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player", "target")
f:RegisterUnitEvent("UNIT_MAXPOWER", "player", "target")
f:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player", "target")
f:RegisterUnitEvent("UNIT_FLAGS", "player", "target")

f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then return end
        AlwaysOnDisplayDB = AlwaysOnDisplayDB or {}
        ns.db = AlwaysOnDisplayDB
        -- Up to v1.0.3 every default was written into the saved table, so "BOTH"
        -- there is almost always the old default, not a choice: move it to the new one.
        if ns.db.dbVersion == nil and ns.db.format == "BOTH" then ns.db.format = "VALUE" end
        ns.db.dbVersion = 2
        for k, v in pairs(ns.defaults) do
            if ns.db[k] == nil then ns.db[k] = v end
        end
        if ns.RegisterOptions then ns.RegisterOptions() end
        f:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        ns.SetupAll()
    elseif event == "PLAYER_TARGET_CHANGED" then
        ns.Refresh("target")
    elseif ns.db then
        ns.Refresh(arg1)
    end
end)
