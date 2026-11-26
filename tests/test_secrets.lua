-- WoW Forever returns "secret" health/power values that addon code may not do
-- math or comparisons on. These tests run the addon against such values under
-- every behaviour the documentation disagrees about.
local T = ...
local mock = require("wow_mock")
local test, eq, truthy, falsy = T.test, T.eq, T.truthy, T.falsy
local S = mock.secret

local function display(env, key)
    for _, d in ipairs(env.ns.displays) do
        if d.key == key then return d end
    end
end

local function secretPlayer(env, opts)
    local p = env.units.player
    p.health, p.maxHealth = S(1234), (opts and opts.plainMax) and 2000 or S(2000)
    p.power, p.maxPower = S(500), S(1000)
    mock.fire(env, "UNIT_HEALTH", "player")
    mock.fire(env, "UNIT_POWER_UPDATE", "player")
end

-- These tests use the value + percent format unless they pick another, so every
-- formatting path (values, percent, joining them) runs against secrets.
local function loggedIn(opts)
    opts = opts or {}
    opts.savedDB = opts.savedDB or { format = "BOTH", dbVersion = 2 }
    local env = mock.new(opts)
    mock.login(env)
    return env
end

local function assertShownWithoutError(env, key)
    local d = display(env, key)
    truthy(d.lastOK, key .. " updated without error (" .. tostring(d.status) .. ")")
    eq(env.bars[key].TextString:GetAlpha(), 0, key .. ": Blizzard text muted while ours shows")
end

test("mock refuses arithmetic and comparisons on secrets", function()
    falsy(pcall(function() return S(1) + 1 end), "arithmetic")
    falsy(pcall(function() return S(1) <= 0 end), "comparison")
    falsy(pcall(function() return S(1) .. "" end), "concatenation")
end)

test("secret values with no percent API: value text, no percent", function()
    local env = loggedIn()
    secretPlayer(env)
    eq(mock.visibleText(env, "playerHealth"), "1234 / 2000")
    eq(mock.visibleText(env, "playerPower"), "500 / 1000")
    assertShownWithoutError(env, "playerHealth")
    assertShownWithoutError(env, "playerPower")
    truthy(display(env, "playerHealth").status:find("no percent available"), "status explains it")
end)

test("secret values with a plain percent API: full text", function()
    local env = loggedIn({ percentAPI = "plain" })
    secretPlayer(env)
    eq(mock.visibleText(env, "playerHealth"), "1234 / 2000 (62%)")
    eq(mock.visibleText(env, "playerPower"), "500 / 1000 (50%)")
    assertShownWithoutError(env, "playerHealth")
end)

test("secret values with a secret percent API: full text", function()
    local env = loggedIn({ percentAPI = "secret" })
    secretPlayer(env)
    eq(mock.visibleText(env, "playerHealth"), "1234 / 2000 (62%)")
    truthy(mock.overlayText(env, "playerHealth").secretText, "handed to SetText as a secret")
    assertShownWithoutError(env, "playerHealth")
end)

test("PERCENT format with secret values uses the percent API", function()
    local env = loggedIn({ percentAPI = "secret", savedDB = { format = "PERCENT" } })
    secretPlayer(env)
    eq(mock.visibleText(env, "playerHealth"), "62%")
end)

test("VALUE format with secret values never asks for a percent", function()
    local env = loggedIn({ savedDB = { format = "VALUE" } })
    secretPlayer(env)
    eq(mock.visibleText(env, "playerHealth"), "1234 / 2000")
    falsy(display(env, "playerHealth").status:find("no percent"), "no percent warning for VALUE")
end)

test("if formatting refuses secrets, shows the bare current value", function()
    local env = loggedIn({ secretFormat = "reject", percentAPI = "secret" })
    secretPlayer(env)
    eq(mock.visibleText(env, "playerHealth"), "1234")
    truthy(display(env, "playerHealth").status:find("raw value only"))
    assertShownWithoutError(env, "playerHealth")
end)

test("PERCENT format with no percent API falls back to the current value", function()
    local env = loggedIn({ savedDB = { format = "PERCENT" } })
    secretPlayer(env)
    eq(mock.visibleText(env, "playerHealth"), "1234")
end)

test("only the current value secret (max readable)", function()
    local env = loggedIn({ percentAPI = "plain" })
    secretPlayer(env, { plainMax = true })
    eq(mock.visibleText(env, "playerHealth"), "1234 / 2000 (62%)")
end)

test("short numbers on secrets use AbbreviateLargeNumbers when available", function()
    local env = loggedIn({ abbreviate = true })
    local p = env.units.player
    p.health, p.maxHealth = S(12345), S(20000)
    mock.fire(env, "UNIT_HEALTH", "player")
    eq(mock.visibleText(env, "playerHealth"), "12.3 K / 20.0 K")
end)

test("short numbers on secrets without AbbreviateLargeNumbers show full values", function()
    local env = loggedIn()
    local p = env.units.player
    p.health, p.maxHealth = S(12345), S(20000)
    mock.fire(env, "UNIT_HEALTH", "player")
    eq(mock.visibleText(env, "playerHealth"), "12345 / 20000")
end)

test("secret target with secret max power is shown, not compared", function()
    local env = loggedIn({ percentAPI = "secret" })
    env.units.target = { health = S(45), maxHealth = S(100), powerType = 0, power = S(30), maxPower = S(60) }
    mock.fire(env, "PLAYER_TARGET_CHANGED")
    eq(mock.visibleText(env, "targetHealth"), "45 / 100 (45%)", "secret max: can't tell it's a percentage, shows values")
    eq(mock.visibleText(env, "targetPower"), "30 / 60 (50%)")
    assertShownWithoutError(env, "targetPower")
end)

test("enemy with secret health but readable max of 100 shows a percentage", function()
    local env = loggedIn({ percentAPI = "secret" })
    env.units.target = { health = S(45), maxHealth = 100, powerType = 0, power = 0, maxPower = 0 }
    mock.fire(env, "PLAYER_TARGET_CHANGED")
    eq(mock.visibleText(env, "targetHealth"), "45%")
    falsy(mock.visibleText(env, "targetPower"), "readable max power 0 still hides")
end)

test("an unexpected error gives the bar back to Blizzard's text and warns once", function()
    local env = loggedIn()
    _G.UnitHealth = function() error("boom") end
    mock.fire(env, "UNIT_HEALTH", "player")
    mock.fire(env, "UNIT_HEALTH", "player")
    local d = display(env, "playerHealth")
    falsy(d.lastOK)
    truthy(d.status:find("boom"), "error kept for /aod debug")
    falsy(mock.visibleText(env, "playerHealth"), "our text hidden")
    eq(env.bars.playerHealth.TextString:GetAlpha(), 1, "Blizzard text restored")
    eq(#env.printed, 1, "warned once")
    truthy(env.printed[1]:find("/aod debug"))
    eq(mock.visibleText(env, "playerPower"), "500 / 1000 (50%)", "other bars unaffected")
end)

test("/aod debug reports capabilities and per-bar status", function()
    local env = loggedIn({ percentAPI = "secret" })
    secretPlayer(env)
    mock.slash(env, "debug")
    local out = table.concat(env.printed, "\n")
    truthy(out:find("issecretvalue: true"), "capability line")
    truthy(out:find("UnitHealthPercent: true"))
    truthy(out:find("playerHealth: bar found | shown %(secret%) | cur secret: true, max secret: true"), out)
    truthy(out:find("targetHealth: bar found | no unit"), out)
end)
