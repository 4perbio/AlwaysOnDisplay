-- The "current only" format and the absorb shield shown next to current health.
local T = ...
local mock = require("wow_mock")
local test, eq, truthy, falsy = T.test, T.eq, T.truthy, T.falsy
local S = mock.secret

local function loggedIn(opts)
    local env = mock.new(opts)
    mock.login(env)
    return env
end

local function shield(s) return "|cff8fd8ff" .. s .. "|r" end

local function withShield(env, amount, unit)
    unit = unit or "player"
    env.units[unit].absorbs = amount
    mock.fire(env, "UNIT_ABSORB_AMOUNT_CHANGED", unit)
end

local function plain(v)
    if mock.isSecret(v) then return rawget(v, "v") end
    return v
end

---------------------------------------------------------------------------
-- Current-only format
---------------------------------------------------------------------------
test("CURRENT format shows only the current value", function()
    local env = loggedIn({ savedDB = { format = "CURRENT" } })
    eq(mock.visibleText(env, "playerHealth"), "1234")
    eq(mock.visibleText(env, "playerPower"), "500")
end)

test("CURRENT format uses short numbers", function()
    local env = loggedIn({ savedDB = { format = "CURRENT" } })
    env.units.player.health, env.units.player.maxHealth = 123456, 200000
    mock.fire(env, "UNIT_HEALTH", "player")
    eq(mock.visibleText(env, "playerHealth"), "123.5k")
end)

test("CURRENT format still shows enemy health as a percentage", function()
    local env = loggedIn({ savedDB = { format = "CURRENT" } })
    env.units.target = { health = 45, maxHealth = 100, powerType = 1, power = 0, maxPower = 100 }
    mock.fire(env, "PLAYER_TARGET_CHANGED")
    eq(mock.visibleText(env, "targetHealth"), "45%")
end)

test("CURRENT format with secret values shows the current value", function()
    local env = loggedIn({ savedDB = { format = "CURRENT" } })
    env.units.player.health, env.units.player.maxHealth = S(1234), S(2000)
    mock.fire(env, "UNIT_HEALTH", "player")
    eq(plain(mock.visibleText(env, "playerHealth")), "1234")
end)

---------------------------------------------------------------------------
-- Shield, readable values
---------------------------------------------------------------------------
test("no shield: nothing extra is shown", function()
    local env = loggedIn()
    eq(mock.visibleText(env, "playerHealth"), "1234 / 2000")
end)

test("shield next to current health in every format", function()
    local cases = {
        VALUE   = "1234 " .. shield("+300") .. " / 2000",
        CURRENT = "1234 " .. shield("+300"),
        BOTH    = "1234 " .. shield("+300") .. " / 2000 (62%)",
        PERCENT = "62% " .. shield("+300"),
    }
    for format, expected in pairs(cases) do
        local env = loggedIn({ savedDB = { format = format, dbVersion = 2 } })
        withShield(env, 300)
        eq(mock.visibleText(env, "playerHealth"), expected, format)
    end
end)

test("shield uses short numbers", function()
    local env = loggedIn()
    withShield(env, 12345)
    eq(mock.visibleText(env, "playerHealth"), "1234 " .. shield("+12.3k") .. " / 2000")
end)

test("shield is shown on the target too, including enemy percent health", function()
    local env = loggedIn()
    env.units.target = { health = 45, maxHealth = 100, powerType = 1, power = 0, maxPower = 100, absorbs = 50 }
    mock.fire(env, "PLAYER_TARGET_CHANGED")
    eq(mock.visibleText(env, "targetHealth"), "45% " .. shield("+50"))
end)

test("shield is never added to resource bars", function()
    local env = loggedIn()
    withShield(env, 300)
    eq(mock.visibleText(env, "playerPower"), "500 / 1000")
end)

test("shield goes away when it breaks", function()
    local env = loggedIn()
    withShield(env, 300)
    withShield(env, 0)
    eq(mock.visibleText(env, "playerHealth"), "1234 / 2000")
end)

test("dead units still show Dead, not a shield", function()
    local env = loggedIn()
    env.units.player.absorbs, env.units.player.dead = 300, true
    mock.fire(env, "UNIT_HEALTH", "player")
    eq(mock.visibleText(env, "playerHealth"), "Dead")
end)

---------------------------------------------------------------------------
-- Opt-out
---------------------------------------------------------------------------
test("shield is on by default and can be turned off", function()
    local env = loggedIn()
    eq(AlwaysOnDisplayDB.showShield, true)
    withShield(env, 300)
    env.settings.showShield:SetValue(false)
    eq(mock.visibleText(env, "playerHealth"), "1234 / 2000", "hidden right away")
    env.settings.showShield:SetValue(true)
    eq(mock.visibleText(env, "playerHealth"), "1234 " .. shield("+300") .. " / 2000", "back right away")
end)

test("saved opt-out is respected", function()
    local env = loggedIn({ savedDB = { showShield = false } })
    withShield(env, 300)
    eq(mock.visibleText(env, "playerHealth"), "1234 / 2000")
end)

---------------------------------------------------------------------------
-- Clients without the API, and secret shields
---------------------------------------------------------------------------
test("client without UnitGetTotalAbsorbs: no shield, no error", function()
    local env = loggedIn({ noAbsorbAPI = true })
    env.units.player.absorbs = 300
    mock.fire(env, "UNIT_HEALTH", "player")
    eq(mock.visibleText(env, "playerHealth"), "1234 / 2000")
    eq(#env.printed, 0)
end)

test("secret shield without zero-aware helpers is left out, health still shown", function()
    local env = loggedIn()
    withShield(env, S(300))
    eq(plain(mock.visibleText(env, "playerHealth")), "1234 / 2000")
    eq(#env.printed, 0, "no error reported")
end)

test("secret shield with C_StringUtil helpers is shown", function()
    local env = loggedIn({ stringUtil = true })
    withShield(env, S(300))
    eq(plain(mock.visibleText(env, "playerHealth")), "1234 " .. shield("+300") .. " / 2000")
end)

test("secret zero shield with C_StringUtil helpers shows no '+'", function()
    local env = loggedIn({ stringUtil = true })
    withShield(env, S(0))
    local text = plain(mock.visibleText(env, "playerHealth"))
    falsy(text:find("+", 1, true), "no plus sign in " .. text)
end)

test("secret health and secret shield together", function()
    local env = loggedIn({ stringUtil = true })
    local p = env.units.player
    p.health, p.maxHealth, p.absorbs = S(1234), S(2000), S(300)
    mock.fire(env, "UNIT_HEALTH", "player")
    eq(plain(mock.visibleText(env, "playerHealth")), "1234 " .. shield("+300") .. " / 2000")
end)
