-- Minimal fake of the WoW client API, just enough to load and drive the addon.
local M = {}

local ADDON_DIR = (ROOT or ".") .. "/AlwaysOnDisplay/"
local ADDON_NAME = "AlwaysOnDisplay"

---------------------------------------------------------------------------
-- Frames and font strings
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Secret values: like the client, any arithmetic, comparison, concatenation
-- or length on them raises. tostring gives the real value so the tests can
-- see what a FontString would render.
---------------------------------------------------------------------------
local SecretMT = {}
local function refuse(what)
    return function() error("attempt to " .. what .. " a secret value (mock)", 2) end
end
for _, mm in ipairs({ "__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm", "__idiv" }) do
    SecretMT[mm] = refuse("perform arithmetic on")
end
SecretMT.__lt = refuse("compare")
SecretMT.__le = refuse("compare")
SecretMT.__eq = refuse("compare")
SecretMT.__concat = refuse("concatenate")
SecretMT.__len = refuse("get length of")
SecretMT.__index = function() error("attempt to index a secret value (mock)", 2) end
SecretMT.__tostring = function(s) return tostring(rawget(s, "v")) end

function M.secret(v) return setmetatable({ v = v }, SecretMT) end
function M.isSecret(v) return getmetatable(v) == SecretMT end
local function unwrap(v)
    if M.isSecret(v) then return rawget(v, "v") end
    return v
end
M.unwrap = unwrap

-- type() reports a secret's real type, as in the client.
local rawType = type
_G.type = function(v)
    if M.isSecret(v) then return rawType(rawget(v, "v")) end
    return rawType(v)
end

local rawFormat = string.format

local FontString = {}
FontString.__index = FontString

local function newFontString(parent, layer, template)
    return setmetatable({ parent = parent, layer = layer, template = template, alpha = 1 }, FontString)
end
function FontString:SetText(t)
    self.secretText = M.isSecret(t)
    self.text = t ~= nil and tostring(unwrap(t)) or nil
end
function FontString:GetText() return self.text end
function FontString:SetPoint(...) self.point = { ... } end
function FontString:SetAlpha(a) self.alpha = a end
function FontString:GetAlpha() return self.alpha end

local Frame = {}
Frame.__index = Frame

function Frame:RegisterEvent(e) self.events[e] = true end
function Frame:UnregisterEvent(e) self.events[e] = nil; self.unitEvents[e] = nil end
function Frame:RegisterUnitEvent(e, ...) self.unitEvents[e] = { ... } end
function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:SetAllPoints(target) self.allPoints = target end
function Frame:SetPoint(...) self.point = { ... } end
function Frame:SetFrameLevel(l) self.level = l end
function Frame:GetFrameLevel() return self.level end
function Frame:Show() self.shown = true end
function Frame:Hide() self.shown = false end
function Frame:SetSize(w, h) self.width, self.height = w, h end
function Frame:GetWidth() return self.width or 0 end
function Frame:SetFrameStrata(s) self.strata = s end
function Frame:RegisterForClicks(...) self.clicks = { ... } end
function Frame:RegisterForDrag(...) self.drag = { ... } end
function Frame:SetHighlightTexture(t) self.highlight = t end
function Frame:ClearAllPoints() self.point = nil end
function Frame:GetCenter() return self.cx or 0, self.cy or 0 end
function Frame:GetEffectiveScale() return self.scale or 1 end
function Frame:GetScript(name) return self.scripts[name] end
function Frame:CreateTexture(name, layer)
    local tex = { layer = layer }
    function tex:SetSize(w, h) self.width, self.height = w, h end
    function tex:SetTexture(t) self.texture = t end
    function tex:SetPoint(...) self.point = { ... } end
    self.textures = self.textures or {}
    table.insert(self.textures, tex)
    return tex
end
function Frame:IsShown() return self.shown end
function Frame:CreateFontString(name, layer, template)
    local fs = newFontString(self, layer, template)
    table.insert(self.fontStrings, fs)
    return fs
end

---------------------------------------------------------------------------
-- Environment
---------------------------------------------------------------------------
local GLOBALS_TO_RESET = {
    "PlayerFrameHealthBar", "PlayerFrameManaBar", "TargetFrameHealthBar", "TargetFrameManaBar",
    "PlayerFrame", "TargetFrame", "AlwaysOnDisplayDB", "SLASH_ALWAYSONDISPLAY1", "SlashCmdList",
    "Settings", "CreateFrame", "Minimap", "GameTooltip", "GetCursorPosition",
    "AlwaysOnDisplay_OnAddonCompartmentClick", "AlwaysOnDisplayMinimapButton",
    "issecretvalue", "UnitHealthPercent", "UnitPowerPercent", "CurveConstants", "AbbreviateLargeNumbers",
    "UnitGetTotalAbsorbs", "C_StringUtil",
}

-- Lua files in the order the .toc lists them, as the client loads them.
function M.tocFiles()
    local files = {}
    for line in M.toc():gmatch("[^\r\n]+") do
        if line:match("%.lua$") and not line:match("^#") then table.insert(files, line) end
    end
    return files
end

-- Raw text of the .toc file (READ_FILE is provided by tests/run.js).
function M.toc()
    return READ_FILE(ADDON_DIR .. ADDON_NAME .. ".toc")
end

-- opts.layout: "classic" (default) | "modern" | "fields" | "none"
-- opts.savedDB: table restored as the SavedVariable before load
function M.new(opts)
    opts = opts or {}
    for _, name in ipairs(GLOBALS_TO_RESET) do _G[name] = nil end

    local env = {
        frames = {},
        printed = {},
        bars = {},
        settings = {},       -- key -> setting object
        controls = {},       -- ordered list of { kind, setting, tooltip, options }
        opened = {},
        units = {
            player = { health = 1234, maxHealth = 2000, powerType = 0, power = 500, maxPower = 1000, isSelf = true },
        },
    }

    local function newFrame(parent)
        local f = setmetatable({
            parent = parent, shown = true, level = parent and (parent.level or 1) or 1,
            events = {}, unitEvents = {}, scripts = {}, fontStrings = {},
        }, Frame)
        table.insert(env.frames, f)
        return f
    end
    env.newFrame = newFrame

    _G.CreateFrame = function(frameType, name, parent)
        local f = newFrame(parent)
        f.frameType = frameType
        if name then _G[name] = f end
        return f
    end

    -- Minimap: 140 wide, centred at (1000, 700) on screen.
    _G.Minimap = newFrame(nil)
    Minimap.width, Minimap.cx, Minimap.cy = 140, 1000, 700
    env.cursor = { x = 0, y = 0 }
    _G.GetCursorPosition = function() return env.cursor.x, env.cursor.y end

    env.tooltip = { lines = {} }
    _G.GameTooltip = {
        SetOwner = function(self, owner) env.tooltip.owner = owner; env.tooltip.lines = {} end,
        SetText = function(self, t) table.insert(env.tooltip.lines, t) end,
        AddLine = function(self, t) table.insert(env.tooltip.lines, t) end,
        Show = function() env.tooltip.shown = true end,
        Hide = function() env.tooltip.shown = false end,
    }

    -- Bars, with Blizzard's own hover text strings.
    local function newBar(level)
        local bar = newFrame(nil)
        bar.level = level or 3
        bar.TextString = newFontString(bar, "OVERLAY", "TextStatusBarText")
        bar.LeftText = newFontString(bar, "OVERLAY", "TextStatusBarText")
        bar.RightText = newFontString(bar, "OVERLAY", "TextStatusBarText")
        return bar
    end
    local layout = opts.layout or "classic"
    if layout ~= "none" then
        env.bars.playerHealth = newBar(3)
        env.bars.playerPower = newBar(4)
        env.bars.targetHealth = newBar(5)
        env.bars.targetPower = newBar(6)
    end
    if layout == "classic" then
        _G.PlayerFrameHealthBar = env.bars.playerHealth
        _G.PlayerFrameManaBar = env.bars.playerPower
        _G.TargetFrameHealthBar = env.bars.targetHealth
        _G.TargetFrameManaBar = env.bars.targetPower
    elseif layout == "modern" then
        _G.PlayerFrame = { PlayerFrameContent = { PlayerFrameContentMain = {
            HealthBarsContainer = { HealthBar = env.bars.playerHealth },
            ManaBarArea = { ManaBar = env.bars.playerPower },
        } } }
        _G.TargetFrame = { TargetFrameContent = { TargetFrameContentMain = {
            HealthBarsContainer = { HealthBar = env.bars.targetHealth },
            ManaBar = env.bars.targetPower,
        } } }
    elseif layout == "fields" then
        _G.PlayerFrame = { healthbar = env.bars.playerHealth, manabar = env.bars.playerPower }
        _G.TargetFrame = { healthbar = env.bars.targetHealth, manabar = env.bars.targetPower }
    end

    -- Unit API
    local units = env.units
    local function u(unit) return units[unit] end
    _G.UnitExists = function(unit) return u(unit) ~= nil end
    _G.UnitHealth = function(unit) return u(unit).health end
    _G.UnitHealthMax = function(unit) return u(unit).maxHealth end
    _G.UnitPowerType = function(unit) return u(unit).powerType end
    _G.UnitPower = function(unit, pt)
        assert(pt == u(unit).powerType, "UnitPower queried with wrong power type")
        return u(unit).power
    end
    _G.UnitPowerMax = function(unit, pt)
        assert(pt == u(unit).powerType, "UnitPowerMax queried with wrong power type")
        return u(unit).maxPower
    end
    _G.UnitIsDeadOrGhost = function(unit) return u(unit).dead or u(unit).ghost or false end
    _G.UnitIsGhost = function(unit) return u(unit).ghost or false end
    _G.UnitIsUnit = function(a, b)
        if a == b then return true end
        local ua, ub = u(a), u(b)
        return ua ~= nil and ua == ub
    end
    _G.UnitPlayerOrPetInParty = function(unit) return u(unit).inParty or false end
    _G.UnitPlayerOrPetInRaid = function(unit) return u(unit).inRaid or false end
    -- opts.noAbsorbAPI: client without UnitGetTotalAbsorbs.
    if not opts.noAbsorbAPI then
        _G.UnitGetTotalAbsorbs = function(unit) return u(unit).absorbs or 0 end
    end

    _G.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        table.insert(env.printed, table.concat(parts, " "))
    end

    -- Settings API
    _G.SlashCmdList = {}
    _G.Settings = {
        VarType = { Boolean = "boolean", Number = "number", String = "string" },
        RegisterVerticalLayoutCategory = function(name)
            env.category = { name = name, GetID = function() return 4242 end }
            return env.category
        end,
        RegisterAddOnSetting = function(category, variable, key, tbl, varType, name, default)
            local s = {
                category = category, variable = variable, key = key, tbl = tbl,
                varType = varType, name = name, default = default,
            }
            function s:SetValueChangedCallback(cb) self.cb = cb end
            function s:SetValue(v)
                self.tbl[self.key] = v
                if self.cb then self.cb(self, v) end
            end
            function s:GetValue() return self.tbl[self.key] end
            env.settings[key] = s
            return s
        end,
        CreateCheckbox = function(category, setting, tooltip)
            table.insert(env.controls, { kind = "checkbox", setting = setting, tooltip = tooltip })
        end,
        CreateDropdown = function(category, setting, optionsFn, tooltip)
            table.insert(env.controls, { kind = "dropdown", setting = setting, tooltip = tooltip, options = optionsFn() })
        end,
        CreateControlTextContainer = function()
            local c = { items = {} }
            function c:Add(value, label) table.insert(self.items, { value = value, label = label }) end
            function c:GetData() return self.items end
            return c
        end,
        RegisterAddOnCategory = function(category) env.registeredCategory = category end,
        OpenToCategory = function(id) table.insert(env.opened, id) end,
    }

    -- Secret-value API, as on WoW Forever.
    --   opts.secretFormat: "accept" (default) -> string.format takes secrets and returns a secret string
    --                      "reject"           -> string.format raises on secrets
    --   opts.percentAPI:   nil | "plain" | "secret"  (UnitHealthPercent / UnitPowerPercent)
    --   opts.abbreviate:   true -> AbbreviateLargeNumbers exists and accepts secrets
    _G.issecretvalue = function(v) return M.isSecret(v) end
    string.format = function(fmt, ...)
        local args, secret = { ... }, false
        for i = 1, select("#", ...) do
            if M.isSecret(args[i]) then secret = true; args[i] = rawget(args[i], "v") end
        end
        if secret and opts.secretFormat == "reject" then
            error("bad argument to 'format' (secret values not allowed) (mock)", 2)
        end
        local s = rawFormat(fmt, table.unpack(args, 1, select("#", ...)))
        if secret then return M.secret(s) end
        return s
    end
    --   opts.stringUtil:   true -> C_StringUtil.TruncateWhenZero / WrapString exist and accept secrets
    if opts.stringUtil then
        local function keep(v, s) if M.isSecret(v) then return M.secret(s) end return s end
        _G.C_StringUtil = {
            TruncateWhenZero = function(n)
                local raw = M.isSecret(n) and rawget(n, "v") or n
                return keep(n, raw == 0 and "" or tostring(raw))
            end,
            WrapString = function(s, prefix, suffix)
                local raw = M.isSecret(s) and rawget(s, "v") or s
                return keep(s, raw == "" and "" or (prefix .. raw .. suffix))
            end,
        }
    end
    if opts.percentAPI then
        _G.CurveConstants = { ScaleTo100 = "ScaleTo100" }
        -- Like the client: without the ScaleTo100 curve the result is a 0-1 fraction
        -- (seen in game as "3664 / 3664 (1%)" when the curve was passed in the wrong slot).
        local function pct(cur, max, curve)
            local p = unwrap(cur) / unwrap(max)
            if curve == "ScaleTo100" then p = p * 100 end
            if opts.percentAPI == "secret" then return M.secret(p) end
            return p
        end
        _G.UnitHealthPercent = function(unit, usePredicted, curve)
            assert(type(usePredicted) == "boolean", "UnitHealthPercent(unit, usePredicted, curve)")
            return pct(u(unit).health, u(unit).maxHealth, curve)
        end
        _G.UnitPowerPercent = function(unit, powerType, usePredicted, curve)
            assert(powerType == u(unit).powerType, "UnitPowerPercent queried with wrong power type")
            assert(type(usePredicted) == "boolean", "UnitPowerPercent(unit, powerType, usePredicted, curve)")
            return pct(u(unit).power, u(unit).maxPower, curve)
        end
    end
    if opts.abbreviate then
        _G.AbbreviateLargeNumbers = function(v)
            local n = unwrap(v)
            local s = n >= 1000 and rawFormat("%.1f K", n / 1000) or tostring(n)
            if M.isSecret(v) then return M.secret(s) end
            return s
        end
    end

    if opts.savedDB then _G.AlwaysOnDisplayDB = opts.savedDB end

    -- Load the addon files the way the client does: (addonName, namespace).
    env.ns = {}
    for _, file in ipairs(M.tocFiles()) do
        local chunk = assert(loadfile(ADDON_DIR .. file))
        chunk(ADDON_NAME, env.ns)
    end

    return env
end

---------------------------------------------------------------------------
-- Driving helpers
---------------------------------------------------------------------------
-- Deliver an event to every frame registered for it (honouring unit filters).
function M.fire(env, event, ...)
    local arg1 = ...
    for _, f in ipairs(env.frames) do
        local handler = f.scripts.OnEvent
        if handler then
            local units = f.unitEvents[event]
            local wanted = f.events[event]
            if units then
                for _, unit in ipairs(units) do
                    if unit == arg1 then wanted = true end
                end
            end
            if wanted then handler(f, event, ...) end
        end
    end
end

function M.login(env)
    M.fire(env, "ADDON_LOADED", ADDON_NAME)
    M.fire(env, "PLAYER_LOGIN")
    M.fire(env, "PLAYER_ENTERING_WORLD")
end

-- The addon's font string drawn on a given bar (nil if none was created).
function M.overlayText(env, key)
    local bar = env.bars[key]
    if not bar then return nil end
    for _, f in ipairs(env.frames) do
        if f.parent == bar and f.fontStrings[1] then return f.fontStrings[1], f end
    end
end

-- Text currently visible on a bar, or nil when the overlay is hidden.
function M.visibleText(env, key)
    local fs, overlay = M.overlayText(env, key)
    if not fs or not overlay:IsShown() then return nil end
    return fs:GetText()
end

function M.slash(env, msg)
    SlashCmdList.ALWAYSONDISPLAY(msg)
end

return M
