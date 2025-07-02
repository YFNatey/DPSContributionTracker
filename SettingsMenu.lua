--Settings Menu

function DPSContributionTracker:CreateSettingsMenu()
    local LAM = LibAddonMenu2
    local panelName = "DPSContributionTrackerSettings"

    local panelData = {
        type = "panel",
        name = "DPS Contribution Tracker",
        displayName = "DPSContributionTracker",
        author = "YFNatey",
        version = "1.0",
        registerForRefresh = true,
        registerForDefaults = true
    }

    local optionsTable = {
        {
            type = "checkbox",
            name = "Enable Notifications",
            tooltip = "Show messages in chat when combat ends.",
            getFunc = function() return self.savedVars.showNotifications end,
            setFunc = function(value) self.savedVars.showNotifications = value end,
            default = true,
        },
        {
            type = "buttaon",
            name = "Reset Saved Data",
            tooltip = "Resets the stored DPS history.",
            func = function()
                self.savedVars.dpsHistory = {}
                d("DPS history reset")
            end,
        },
    }

    LAM:RegisterAddonPanel(panelName, panelData)
    LAM:RegisterOptionControls(panelName, optionsTable)
end
