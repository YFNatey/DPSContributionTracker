DPSContributionTracker = {}
local ADDON_NAME = "DPSContributionTracker"

local function Initialize()
    -- Initialize saved variables
    DPSContributionTracker.savedVars = ZO_SavedVars:NewAccountWide(
        "DPSBaselineTracker_SavedVars",
        1,
        nil,
        {
            showNotifications = true,
            dpsHistory = {},
        }
    )

    DPSContributionTracker.playerDamage = 0

    -- Register combat event
    EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_COMBAT_EVENT,
        function(...)
            DPSContributionTracker.OnCombatEvent(...)
        end)
end

EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED, Initialize)
--- Callback for the EVENT_ADD_ON_LOADED event.
-- @param event number - The numeric ID of the triggered event.
-- @param addonName string - The name of the addon that was just loaded.

local function OnAddOnLoaded(event, addonName)
    if addonName == ADDON_NAME then
        EVENT_MANAGER:UnregisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED, OnAddOnLoaded)
        Initialize()
    end
end

EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED, OnAddOnLoaded)
