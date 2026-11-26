local T = ...
local mock = require("wow_mock")
local test, eq, truthy, falsy = T.test, T.eq, T.truthy, T.falsy

local function loggedIn(opts)
    local env = mock.new(opts)
    mock.login(env)
    return env
end

local function withTarget(env, target)
    env.units.target = target
    mock.fire(env, "PLAYER_TARGET_CHANGED")
end

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------
test("fills a fresh saved-variables table with defaults", function()
    local env = loggedIn()
    for k, v in pairs(env.ns.defaults) do eq(AlwaysOnDisplayDB[k], v, k) end
    truthy(env.ns.db == AlwaysOnDisplayDB, "ns.db is the SavedVariable")
end)

test("keeps saved values and only fills missing keys", function()
    loggedIn({ savedDB = { playerHealth = false, format = "PERCENT", legacy = 1 } })
    eq(AlwaysOnDisplayDB.playerHealth, false)
    eq(AlwaysOnDisplayDB.format, "PERCENT")
    eq(AlwaysOnDisplayDB.playerPower, true)
    eq(AlwaysOnDisplayDB.legacy, 1, "unknown keys are left alone")
end)

test("ignores ADDON_LOADED for other addons", function()
    local env = mock.new()
    mock.fire(env, "ADDON_LOADED", "SomeOtherAddon")
    falsy(env.ns.db, "db must not be set yet")
    falsy(env.category, "options must not be registered yet")
end)

test("unit events before ADDON_LOADED do not error", function()
    local env = mock.new()
    mock.fire(env, "UNIT_HEALTH", "player")
end)

---------------------------------------------------------------------------
-- Finding the bars
---------------------------------------------------------------------------
for _, layout in ipairs({ "classic", "modern", "fields" }) do
    test("finds all four bars with the " .. layout .. " frame layout", function()
        local env = loggedIn({ layout = layout })
        withTarget(env, { health = 50, maxHealth = 100, powerType = 1, power = 30, maxPower = 100 })
        eq(#env.printed, 0, "no warning expected")
        truthy(mock.visibleText(env, "playerHealth"), "player health")
        truthy(mock.visibleText(env, "playerPower"), "player power")
        truthy(mock.visibleText(env, "targetHealth"), "target health")
        truthy(mock.visibleText(env, "targetPower"), "target power")
    end)
end

test("warns once when bars cannot be found and does not error", function()
    local env = loggedIn({ layout = "none" })
    mock.fire(env, "PLAYER_ENTERING_WORLD")
    mock.fire(env, "UNIT_HEALTH", "player")
    mock.fire(env, "PLAYER_TARGET_CHANGED")
    eq(#env.printed, 1)
    truthy(env.printed[1]:find("could not find"), "warning text")
end)

test("creates the overlay once, above the bar, with the status bar font", function()
    local env = loggedIn()
    mock.fire(env, "PLAYER_ENTERING_WORLD")
    mock.fire(env, "PLAYER_ENTERING_WORLD")
    local count = 0
    for _, f in ipairs(env.frames) do
        if f.parent == env.bars.playerHealth then count = count + 1 end
    end
    eq(count, 1, "overlay frames on player health bar")
    local fs, overlay = mock.overlayText(env, "playerHealth")
    eq(fs.template, "TextStatusBarText")
    eq(overlay:GetFrameLevel(), env.bars.playerHealth:GetFrameLevel() + 5)
    truthy(overlay.allPoints == env.bars.playerHealth, "overlay covers the bar")
end)

---------------------------------------------------------------------------
-- Formatting
---------------------------------------------------------------------------
test("default format shows value and max, without percent", function()
    local env = loggedIn()
    eq(AlwaysOnDisplayDB.format, "VALUE")
    eq(mock.visibleText(env, "playerHealth"), "1234 / 2000")
    eq(mock.visibleText(env, "playerPower"), "500 / 1000")
end)

test("BOTH format adds the percent", function()
    local env = loggedIn({ savedDB = { format = "BOTH", dbVersion = 2 } })
    eq(mock.visibleText(env, "playerHealth"), "1234 / 2000 (62%)")
end)

test("old saved 'BOTH' (written as the default up to v1.0.3) moves to the new default once", function()
    local env = loggedIn({ savedDB = { format = "BOTH", playerHealth = true } })
    eq(AlwaysOnDisplayDB.format, "VALUE")
    eq(AlwaysOnDisplayDB.dbVersion, 2)
    eq(mock.visibleText(env, "playerHealth"), "1234 / 2000")
end)

test("choosing 'BOTH' again after the migration is kept", function()
    loggedIn({ savedDB = { format = "BOTH", dbVersion = 2 } })
    eq(AlwaysOnDisplayDB.format, "BOTH")
end)

test("old saved non-default formats are kept", function()
    loggedIn({ savedDB = { format = "PERCENT" } })
    eq(AlwaysOnDisplayDB.format, "PERCENT")
end)

test("PERCENT format", function()
    local env = loggedIn({ savedDB = { format = "PERCENT" } })
    eq(mock.visibleText(env, "playerHealth"), "62%")
end)

test("short numbers abbreviate from 10k and drop trailing .0", function()
    local env = loggedIn()
    local p = env.units.player
    p.health, p.maxHealth = 12345, 20000
    mock.fire(env, "UNIT_HEALTH", "player")
    eq(mock.visibleText(env, "playerHealth"), "12.3k / 20k")

    p.health, p.maxHealth = 1500000, 2000000
    mock.fire(env, "UNIT_MAXHEALTH", "player")
    eq(mock.visibleText(env, "playerHealth"), "1.5m / 2m")

    p.health, p.maxHealth = 9999, 9999
    mock.fire(env, "UNIT_HEALTH", "player")
    eq(mock.visibleText(env, "playerHealth"), "9999 / 9999")
end)

test("short numbers off shows full values", function()
    local env = loggedIn({ savedDB = { shortNumbers = false } })
    env.units.player.health, env.units.player.maxHealth = 12345, 20000
    mock.fire(env, "UNIT_HEALTH", "player")
    eq(mock.visibleText(env, "playerHealth"), "12345 / 20000")
end)

test("rounds the percentage to the nearest whole number", function()
    local env = loggedIn({ savedDB = { format = "PERCENT" } })
    env.units.player.health, env.units.player.maxHealth = 1, 3
    mock.fire(env, "UNIT_HEALTH", "player")
    eq(mock.visibleText(env, "playerHealth"), "33%")
    env.units.player.health = 2
    mock.fire(env, "UNIT_HEALTH", "player")
    eq(mock.visibleText(env, "playerHealth"), "67%")
end)

---------------------------------------------------------------------------
-- Target
---------------------------------------------------------------------------
test("target text is hidden with no target and shown once targeted", function()
    local env = loggedIn()
    falsy(mock.visibleText(env, "targetHealth"))
    falsy(mock.visibleText(env, "targetPower"))
    withTarget(env, { health = 800, maxHealth = 1000, powerType = 0, power = 200, maxPower = 400, inParty = true })
    eq(mock.visibleText(env, "targetHealth"), "800 / 1000")
    eq(mock.visibleText(env, "targetPower"), "200 / 400")
    withTarget(env, nil)
    falsy(mock.visibleText(env, "targetHealth"))
    falsy(mock.visibleText(env, "targetPower"))
end)

test("enemy health reported as 0-100 is shown as a percentage only", function()
    local env = loggedIn()
    withTarget(env, { health = 45, maxHealth = 100, powerType = 1, power = 0, maxPower = 100 })
    eq(mock.visibleText(env, "targetHealth"), "45%")
end)

test("a party member with exactly 100 max health still shows values", function()
    local env = loggedIn()
    withTarget(env, { health = 45, maxHealth = 100, powerType = 0, power = 10, maxPower = 50, inParty = true })
    eq(mock.visibleText(env, "targetHealth"), "45 / 100")
end)

test("targeting yourself with 100 max health shows values", function()
    local env = loggedIn()
    env.units.player.health, env.units.player.maxHealth = 70, 100
    withTarget(env, env.units.player)
    eq(mock.visibleText(env, "targetHealth"), "70 / 100")
end)

test("target with no resource hides the resource text", function()
    local env = loggedIn()
    withTarget(env, { health = 50, maxHealth = 100, powerType = 0, power = 0, maxPower = 0 })
    eq(mock.visibleText(env, "targetHealth"), "50%")
    falsy(mock.visibleText(env, "targetPower"))
end)

test("dead target shows Dead", function()
    local env = loggedIn()
    withTarget(env, { health = 0, maxHealth = 100, powerType = 0, power = 0, maxPower = 0, dead = true })
    eq(mock.visibleText(env, "targetHealth"), "Dead")
end)

test("player ghost shows Ghost", function()
    local env = loggedIn()
    env.units.player.ghost = true
    mock.fire(env, "UNIT_HEALTH", "player")
    eq(mock.visibleText(env, "playerHealth"), "Ghost")
end)

---------------------------------------------------------------------------
-- Live updates
---------------------------------------------------------------------------
test("UNIT_POWER_FREQUENT updates energy live", function()
    local env = loggedIn()
    local p = env.units.player
    p.powerType, p.power, p.maxPower = 3, 40, 100
    mock.fire(env, "UNIT_DISPLAYPOWER", "player")
    eq(mock.visibleText(env, "playerPower"), "40 / 100")
    p.power = 60
    mock.fire(env, "UNIT_POWER_FREQUENT", "player", "ENERGY")
    eq(mock.visibleText(env, "playerPower"), "60 / 100")
end)

test("shapeshift (UNIT_DISPLAYPOWER) switches mana to rage", function()
    local env = loggedIn()
    eq(mock.visibleText(env, "playerPower"), "500 / 1000")
    local p = env.units.player
    p.powerType, p.power, p.maxPower = 1, 15, 100
    mock.fire(env, "UNIT_DISPLAYPOWER", "player")
    eq(mock.visibleText(env, "playerPower"), "15 / 100")
end)

test("a player event only refreshes the player frame", function()
    local env = loggedIn()
    withTarget(env, { health = 50, maxHealth = 100, powerType = 0, power = 0, maxPower = 0 })
    env.units.target.health = 10
    mock.fire(env, "UNIT_HEALTH", "player")
    eq(mock.visibleText(env, "targetHealth"), "50%", "target not refreshed by player event")
    mock.fire(env, "UNIT_HEALTH", "target")
    eq(mock.visibleText(env, "targetHealth"), "10%")
end)

test("events for other units are ignored", function()
    local env = loggedIn()
    env.units.player.health = 1
    mock.fire(env, "UNIT_HEALTH", "party1")
    eq(mock.visibleText(env, "playerHealth"), "1234 / 2000")
end)

---------------------------------------------------------------------------
-- Enable / disable and Blizzard text
---------------------------------------------------------------------------
test("disabled bars show no text", function()
    local env = loggedIn({ savedDB = { playerPower = false, targetHealth = false } })
    withTarget(env, { health = 50, maxHealth = 100, powerType = 0, power = 5, maxPower = 10 })
    truthy(mock.visibleText(env, "playerHealth"))
    falsy(mock.visibleText(env, "playerPower"))
    falsy(mock.visibleText(env, "targetHealth"))
    truthy(mock.visibleText(env, "targetPower"))
end)

test("mutes Blizzard's text only on bars where ours is enabled", function()
    local env = loggedIn({ savedDB = { playerPower = false } })
    for _, field in ipairs({ "TextString", "LeftText", "RightText" }) do
        eq(env.bars.playerHealth[field]:GetAlpha(), 0, "health " .. field)
        eq(env.bars.playerPower[field]:GetAlpha(), 1, "power " .. field)
    end
end)

test("ns.Refresh() with no unit updates everything", function()
    local env = loggedIn()
    withTarget(env, { health = 50, maxHealth = 100, powerType = 0, power = 0, maxPower = 0 })
    env.units.player.health = 1000
    env.units.target.health = 20
    env.ns.Refresh()
    eq(mock.visibleText(env, "playerHealth"), "1000 / 2000")
    eq(mock.visibleText(env, "targetHealth"), "20%")
end)
