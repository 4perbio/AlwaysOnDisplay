local T = ...
local mock = require("wow_mock")
local test, eq, truthy, falsy = T.test, T.eq, T.truthy, T.falsy

local function loggedIn(opts)
    local env = mock.new(opts)
    mock.login(env)
    return env
end

test("registers the AlwaysOnDisplay category", function()
    local env = loggedIn()
    eq(env.category.name, "AlwaysOnDisplay")
    truthy(env.registeredCategory == env.category, "category added to the AddOns list")
end)

test("registers one setting per option, bound to the saved variables", function()
    local env = loggedIn()
    local n = 0
    for key, default in pairs(env.ns.defaults) do
        local s = env.settings[key]
        truthy(s, "setting for " .. key)
        eq(s.variable, "AlwaysOnDisplay_" .. key)
        truthy(s.tbl == AlwaysOnDisplayDB, key .. " bound to the DB")
        eq(s.varType, type(default), key .. " type")
        eq(s.default, default, key .. " default")
        truthy(s.cb, key .. " has a change callback")
        n = n + 1
    end
    eq(n, 6)
end)

test("checkboxes for the boolean options, dropdown for format", function()
    local env = loggedIn()
    local kinds = {}
    for _, c in ipairs(env.controls) do kinds[c.setting.key] = c end
    for _, key in ipairs({ "playerHealth", "playerPower", "targetHealth", "targetPower", "shortNumbers" }) do
        eq(kinds[key].kind, "checkbox", key)
        truthy(kinds[key].tooltip, key .. " tooltip")
    end
    local dd = kinds.format
    eq(dd.kind, "dropdown")
    eq(#dd.options, 3)
    local values = {}
    for _, o in ipairs(dd.options) do values[o.value] = o.label end
    truthy(values.BOTH and values.VALUE and values.PERCENT, "all three formats offered")
end)

test("unchecking a setting hides its text immediately", function()
    local env = loggedIn()
    truthy(mock.visibleText(env, "playerHealth"))
    env.settings.playerHealth:SetValue(false)
    falsy(mock.visibleText(env, "playerHealth"))
    env.settings.playerHealth:SetValue(true)
    eq(mock.visibleText(env, "playerHealth"), "1234 / 2000 (62%)")
end)

test("changing the format updates the text immediately", function()
    local env = loggedIn()
    env.settings.format:SetValue("PERCENT")
    eq(mock.visibleText(env, "playerHealth"), "62%")
end)

test("/aod opens the options panel", function()
    local env = loggedIn()
    mock.slash(env, "")
    eq(env.opened[1], 4242)
end)

test("/aod reset restores defaults and refreshes", function()
    local env = loggedIn({ savedDB = { playerHealth = false, format = "VALUE" } })
    falsy(mock.visibleText(env, "playerHealth"))
    mock.slash(env, "  RESET ")
    eq(AlwaysOnDisplayDB.playerHealth, true)
    eq(AlwaysOnDisplayDB.format, "BOTH")
    eq(mock.visibleText(env, "playerHealth"), "1234 / 2000 (62%)")
    eq(#env.opened, 0, "reset does not open the panel")
    truthy(env.printed[1] and env.printed[1]:find("reset"), "confirmation printed")
end)
