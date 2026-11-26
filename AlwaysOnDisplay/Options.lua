local addonName, ns = ...

local category

function ns.RegisterOptions()
    category = Settings.RegisterVerticalLayoutCategory("AlwaysOnDisplay")

    local function OnChanged() ns.Refresh() end

    local function Setting(key, name)
        local setting = Settings.RegisterAddOnSetting(category, addonName .. "_" .. key, key, ns.db,
            type(ns.defaults[key]), name, ns.defaults[key])
        setting:SetValueChangedCallback(OnChanged)
        return setting
    end

    Settings.CreateCheckbox(category, Setting("playerHealth", "Player health"),
        "Always show your health value on the player frame.")
    Settings.CreateCheckbox(category, Setting("playerPower", "Player resource"),
        "Always show your mana, energy or rage value on the player frame.")
    Settings.CreateCheckbox(category, Setting("targetHealth", "Target health"),
        "Always show your target's health value on the target frame.")
    Settings.CreateCheckbox(category, Setting("targetPower", "Target resource"),
        "Always show your target's mana, energy or rage value on the target frame.")

    local function FormatOptions()
        local container = Settings.CreateControlTextContainer()
        container:Add("VALUE", "1234 / 2000")
        container:Add("BOTH", "1234 / 2000 (62%)")
        container:Add("PERCENT", "62%")
        return container:GetData()
    end
    local CreateDropdown = Settings.CreateDropdown or Settings.CreateDropDown
    CreateDropdown(category, Setting("format", "Text format"), FormatOptions,
        "How the values are written on the bars.")

    Settings.CreateCheckbox(category, Setting("shortNumbers", "Short numbers"),
        "Abbreviate large numbers (12.3k, 1.2m).")

    local minimap = Setting("minimapButton", "Show minimap button")
    minimap:SetValueChangedCallback(function() ns.UpdateMinimapButton() end)
    Settings.CreateCheckbox(category, minimap,
        "Show a button on the minimap that opens these settings. Drag it to move it.")

    Settings.RegisterAddOnCategory(category)
end

function ns.OpenOptions()
    if category then Settings.OpenToCategory(category:GetID()) end
end

SLASH_ALWAYSONDISPLAY1 = "/aod"
SlashCmdList.ALWAYSONDISPLAY = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "reset" then
        for k, v in pairs(ns.defaults) do ns.db[k] = v end
        ns.Refresh()
        if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
        print("|cff33ff99AlwaysOnDisplay|r: settings reset (reopen the options panel to see them).")
    elseif msg == "debug" then
        ns.Debug()
    elseif msg == "minimap" then
        ns.db.minimapButton = not ns.db.minimapButton
        ns.UpdateMinimapButton()
    else
        ns.OpenOptions()
    end
end
