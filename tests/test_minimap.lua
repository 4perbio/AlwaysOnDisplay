local T = ...
local mock = require("wow_mock")
local test, eq, truthy, falsy = T.test, T.eq, T.truthy, T.falsy

local function loggedIn(opts)
    local env = mock.new(opts)
    mock.login(env)
    return env
end

local function near(actual, expected, msg)
    if math.abs(actual - expected) > 0.01 then
        error((msg or "") .. ": expected ~" .. expected .. ", got " .. actual, 2)
    end
end

-- Offset of the button from the minimap centre.
local function offset(button)
    local p = button.point
    eq(p[1], "CENTER"); truthy(p[2] == Minimap, "anchored to the minimap"); eq(p[3], "CENTER")
    return p[4], p[5]
end

test("creates a shown button on the minimap at login", function()
    local env = loggedIn()
    local b = env.ns.minimapButton
    truthy(b, "button created")
    eq(b.frameType, "Button")
    truthy(b.parent == Minimap, "parented to the minimap")
    truthy(AlwaysOnDisplayMinimapButton == b, "has a global name for minimap button collectors")
    truthy(b:IsShown())
    eq(b.icon.texture, "Interface\\AddOns\\AlwaysOnDisplay\\Icon")
end)

test("is placed on the minimap edge at the default angle (225 degrees)", function()
    local env = loggedIn()
    local x, y = offset(env.ns.minimapButton)
    local r = 140 / 2 + 10
    near(x, math.cos(math.rad(225)) * r, "x")
    near(y, math.sin(math.rad(225)) * r, "y")
end)

test("uses the saved angle", function()
    local env = loggedIn({ savedDB = { minimapAngle = 90 } })
    local x, y = offset(env.ns.minimapButton)
    near(x, 0, "x"); near(y, 80, "y")
end)

test("is not created when disabled in saved settings", function()
    local env = loggedIn({ savedDB = { minimapButton = false } })
    falsy(env.ns.minimapButton)
end)

test("clicking the button opens the settings panel", function()
    local env = loggedIn()
    local b = env.ns.minimapButton
    b:GetScript("OnClick")(b, "LeftButton")
    eq(env.opened[1], 4242)
end)

test("hovering shows a tooltip that explains click and drag", function()
    local env = loggedIn()
    local b = env.ns.minimapButton
    b:GetScript("OnEnter")(b)
    truthy(env.tooltip.shown)
    truthy(env.tooltip.owner == b)
    eq(env.tooltip.lines[1], "AlwaysOnDisplay")
    local all = table.concat(env.tooltip.lines, "\n")
    truthy(all:find("open settings"), "mentions click")
    truthy(all:find("move"), "mentions drag")
    b:GetScript("OnLeave")(b)
    falsy(env.tooltip.shown)
end)

test("dragging moves the button around the minimap and saves the angle", function()
    local env = loggedIn()
    local b = env.ns.minimapButton
    b:GetScript("OnDragStart")(b)
    local update = b:GetScript("OnUpdate")
    truthy(update, "follows the cursor while dragging")

    -- Cursor straight above the minimap centre (1000, 700).
    env.cursor.x, env.cursor.y = 1000, 900
    update(b, 0.016)
    near(AlwaysOnDisplayDB.minimapAngle, 90, "angle")
    local x, y = offset(b)
    near(x, 0, "x"); near(y, 80, "y")

    -- Cursor to the right: 0 degrees. Below-left: 225.
    env.cursor.x, env.cursor.y = 1200, 700
    update(b, 0.016)
    near(AlwaysOnDisplayDB.minimapAngle, 0, "right")
    env.cursor.x, env.cursor.y = 900, 600
    update(b, 0.016)
    near(AlwaysOnDisplayDB.minimapAngle, 225, "below-left")

    b:GetScript("OnDragStop")(b)
    falsy(b:GetScript("OnUpdate"), "stops following the cursor")
end)

test("dragging accounts for the minimap's scale", function()
    local env = loggedIn()
    Minimap.scale = 2
    local b = env.ns.minimapButton
    b:GetScript("OnDragStart")(b)
    -- In screen pixels the centre is at (2000, 1400) when scale is 2.
    env.cursor.x, env.cursor.y = 2000, 1600
    b:GetScript("OnUpdate")(b, 0.016)
    near(AlwaysOnDisplayDB.minimapAngle, 90, "angle")
end)

test("the settings checkbox hides and shows the button", function()
    local env = loggedIn()
    env.settings.minimapButton:SetValue(false)
    falsy(env.ns.minimapButton:IsShown())
    env.settings.minimapButton:SetValue(true)
    truthy(env.ns.minimapButton:IsShown())
end)

test("enabling the button later creates it", function()
    local env = loggedIn({ savedDB = { minimapButton = false } })
    env.settings.minimapButton:SetValue(true)
    truthy(env.ns.minimapButton and env.ns.minimapButton:IsShown())
end)

test("/aod minimap toggles the button", function()
    local env = loggedIn()
    mock.slash(env, "minimap")
    eq(AlwaysOnDisplayDB.minimapButton, false)
    falsy(env.ns.minimapButton:IsShown())
    mock.slash(env, "minimap")
    truthy(env.ns.minimapButton:IsShown())
    eq(#env.opened, 0, "does not open the panel")
end)

test("/aod reset brings the button back to its default place", function()
    local env = loggedIn({ savedDB = { minimapButton = false, minimapAngle = 10 } })
    mock.slash(env, "reset")
    eq(AlwaysOnDisplayDB.minimapAngle, 225)
    truthy(env.ns.minimapButton and env.ns.minimapButton:IsShown())
end)

test("addon compartment entry opens the settings", function()
    local env = loggedIn()
    truthy(mock.toc():find("## AddonCompartmentFunc: AlwaysOnDisplay_OnAddonCompartmentClick", 1, true),
        "declared in the .toc")
    AlwaysOnDisplay_OnAddonCompartmentClick("AlwaysOnDisplay", "LeftButton")
    eq(env.opened[1], 4242)
end)
