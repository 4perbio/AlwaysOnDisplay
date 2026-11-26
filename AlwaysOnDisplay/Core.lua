local addonName, ns = ...

ns.defaults = {
    playerHealth = true,
    playerPower  = true,
    targetHealth = true,
    targetPower  = true,
    format       = "BOTH",   -- "VALUE" | "PERCENT" | "BOTH"
    shortNumbers = true,
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

local function FormatValue(cur, max, percentOnly)
    local pct = math.floor(cur / max * 100 + 0.5)
    if percentOnly or ns.db.format == "PERCENT" then
        return pct .. "%"
    elseif ns.db.format == "VALUE" then
        return ShortNumber(cur) .. " / " .. ShortNumber(max)
    end
    return ShortNumber(cur) .. " / " .. ShortNumber(max) .. " (" .. pct .. "%)"
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

local function UpdateDisplay(d)
    if not d.text then return end
    local unit = d.unit
    if not ns.db[d.key] then
        d.overlay:Hide()
        SetBlizzardTextAlpha(d.bar, 1)
        return
    end
    SetBlizzardTextAlpha(d.bar, 0)

    if not UnitExists(unit) then
        d.overlay:Hide()
        return
    end

    local cur, max
    if d.kind == "health" then
        if UnitIsDeadOrGhost(unit) then
            d.text:SetText(UnitIsGhost(unit) and "Ghost" or "Dead")
            d.overlay:Show()
            return
        end
        cur, max = UnitHealth(unit), UnitHealthMax(unit)
    else
        local powerType = UnitPowerType(unit)
        cur, max = UnitPower(unit, powerType), UnitPowerMax(unit, powerType)
    end

    if not max or max <= 0 then
        d.overlay:Hide()
        return
    end

    -- Classic servers report enemy health as a 0-100 percentage.
    local percentOnly = d.kind == "health" and max == 100 and unit ~= "player"
        and not UnitIsUnit(unit, "player") and not UnitPlayerOrPetInParty(unit)
        and not UnitPlayerOrPetInRaid(unit)

    d.text:SetText(FormatValue(cur, max, percentOnly))
    d.overlay:Show()
end

function ns.Refresh(unit)
    for _, d in ipairs(ns.displays) do
        if not unit or d.unit == unit then UpdateDisplay(d) end
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
