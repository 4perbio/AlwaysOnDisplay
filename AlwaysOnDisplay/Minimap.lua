local addonName, ns = ...

-- A small draggable button on the minimap edge that opens the settings.
-- Its position is saved as an angle (degrees, 0 = right, counter-clockwise).

local ICON = "Interface\\AddOns\\AlwaysOnDisplay\\Icon"
local atan2 = math.atan2 or math.atan   -- Lua 5.1 (game) / 5.3 (tests)

local button

local function Position()
    local angle = math.rad(ns.db.minimapAngle or ns.defaults.minimapAngle)
    local radius = Minimap:GetWidth() / 2 + 10
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function AngleFromCursor()
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    return math.deg(atan2(cy - my, cx - mx)) % 360
end

local function OnDragUpdate()
    ns.db.minimapAngle = AngleFromCursor()
    Position()
end

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("AlwaysOnDisplay")
    GameTooltip:AddLine("|cffffffffClick|r to open settings", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("|cffffffffDrag|r to move this button", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

local function Create()
    button = CreateFrame("Button", "AlwaysOnDisplayMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetPoint("TOPLEFT", 7, -5)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetTexture(ICON)
    icon:SetPoint("TOPLEFT", 7, -5)
    button.icon = icon

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    button:SetScript("OnClick", function() ns.OpenOptions() end)
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", OnDragUpdate)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    ns.minimapButton = button
end

function ns.UpdateMinimapButton()
    if not ns.db or not Minimap then return end
    if ns.db.minimapButton then
        if not button then Create() end
        Position()
        button:Show()
    elseif button then
        button:Hide()
    end
end

-- Entry in the minimap "AddOns" compartment menu (## AddonCompartmentFunc in the .toc).
function AlwaysOnDisplay_OnAddonCompartmentClick()
    ns.OpenOptions()
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function() ns.UpdateMinimapButton() end)
