local defaults = {
    groupDpsSize = 1
}


DPSContributionTracker = {}
local ADDON_NAME = "DPSContributionTracker"

-- Debug print helper
local function debug(msg)
    d("[DPS Tracker] " .. tostring(msg))
end

DPSContributionTracker.savedVars = nil
DPSContributionTracker.combatStartTime = 0
DPSContributionTracker.combatEndTime = 0
DPSContributionTracker.timeElapsed = 0
DPSContributionTracker.playerDamage = 0
DPSContributionTracker.currentEnemyHealth = 0
DPSContributionTracker.maxEnemyHealth = 0
DPSContributionTracker.inCombat = false
DPSContributionTracker.hasReported = false

-- get enemy health
function DPSContributionTracker:GetEnemyHealth()
    d("running GetEnemeyHealth()")
    local unitTag
    if IsConsoleUI() then
        unitTag = "boss1"
    else
        unitTag = "reticleover"
    end
    d("unitTag = " .. tostring(unitTag))
    d("Exists: " .. tostring(DoesUnitExist(unitTag)))
    d("Attackable: " .. tostring(IsUnitAttackable(unitTag)))
    if DoesUnitExist(unitTag) and IsUnitAttackable(unitTag) then
        if not IsConsoleUI() then
            local maxHP = GetUnitPower(unitTag, POWERTYPE_HEALTH, POWERVAR_MAX)

            if maxHP and maxHP > 0 then
                self.maxEnemyHealth = maxHP
                d("PC: Detected enemy max health: " .. tostring(maxHP))
            end
            -- For console
        else
            local current, max, effectiveMax = GetUnitPower(unitTag, COMBAT_MECHANIC_FLAGS_HEALTH)
            d(string.format("Console: Current HP: %.0f | Max HP: %.0f | Effective Max: %.0f", current, max, effectiveMax))
            if max and max > 0 then
                self.maxEnemyHealth = max
                d("Console: Detected enemy max health: " .. tostring(max))
            else
                d("Console: Failed to detect max enemy HP")
            end
        end
    else
        d("Unit does not exist or is not attackable")
    end
end

-- Get combat state
function DPSContributionTracker:OnCombatStateChanged(inCombat)
    if inCombat then
        self:GetEnemyHealth()
        self.inCombat = true
        self.playerDamage = 0
        self.playerTotalDamage = 0
        self.combatStartTime = GetGameTimeMilliseconds()
        self.hasReported = false
        d("Combat Started")
    else
        self.inCombat = false
        self.combatEndTime = GetGameTimeMilliseconds()
        self.timeElapsed = (self.combatEndTime - self.combatStartTime) / 1000
        d(string.format("Combat Ended. Time: %.1f seconds", self.timeElapsed))
    end
end

-- track player damage
function DPSContributionTracker:OnCombatEvent(eventCode, result, isError, abilityName, abilityGraphic,
                                              abilityActionSlotType,
                                              sourceName, sourceType, targetName, targetType,
                                              hitValue, powerType, damageType, combatMechanic,
                                              sourceUnitId, targetUnitId, abilityId, overflow)
    if sourceType == COMBAT_UNIT_TYPE_PLAYER and hitValue > 0 then
        self.playerDamage = self.playerDamage + hitValue
        self:GetEnemyHealth()

        d(string.format("Player hit for %d", hitValue))
    end
end

-- Update enemy health and print DPS info
function DPSContributionTracker:UpdateStatus()
    if not self.inCombat and self.timeElapsed > 0 and self.maxEnemyHealth > 0 and not self.hasReported then
        local expectedDPS = self.maxEnemyHealth / self.timeElapsed / self.savedVars.groupDpsSize
        local actualDPS = self.playerDamage / self.timeElapsed
        local Contribution = (self.playerDamage / self.maxEnemyHealth) * 100
        local expectedDMG = self.maxEnemyHealth / self.savedVars.groupDpsSize
        local baselineContribution = (1 / self.savedVars.groupDpsSize) * 100
        d("group dps size" .. tostring(self.savedVars.groupDpsSize))
        d(string.format("Enemy HP: %d", self.maxEnemyHealth))
        d(string.format(
            "Damage Done: %.0f | Your DPS: %.1f | Expected Damage Done: %.0f | Expected DPS: %.1f | Contribution: %.1f%% | Baseline Contribution: %.1f%%",
            self
            .playerDamage, actualDPS, expectedDMG, expectedDPS,
            Contribution, baselineContribution))
        self.hasReported = true
    end
end

-- INIT addon
local function Initialize()
    DPSContributionTracker.savedVars = ZO_SavedVars:NewAccountWide(
        "DPSContributionTracker_SavedVars",
        1,
        nil,
        {
            showNotifications = true,
            dpsHistory = {},
            groupDpsSize = 1
        }
    )

    EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_COMBAT_EVENT,
        function(...) DPSContributionTracker:OnCombatEvent(...) end)
    DPSContributionTracker:CreateSettingsMenu()
end

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
        [1] = {
            type = "checkbox",
            name = "Enable Notifications",
            tooltip = "Show messages in chat when combat ends.",
            getFunc = function() return self.savedVars.showNotifications end,
            setFunc = function(value) self.savedVars.showNotifications = value end,
            default = true,
        },
        [2] = {
            type = "button",
            name = "Reset Saved Data",
            tooltip = "Resets the stored DPS history.",
            func = function()
                self.savedVars.dpsHistory = {}
                d("DPS history reset")
            end,
        },
        [3] = {
            type = "slider",
            name = "Nmmber of DPS Players in group",
            tooltip = "Adjust the number of full damage DPS in group. Affects the expeccted DPS",
            min = 1,
            max = 10,
            step = 1,
            getFunc = function() return self.savedVars.groupDpsSize end,
            setFunc = function(value) self.savedVars.groupDpsSize = value end,
            default = defaults.groupDpsSize,
        },
    }

    LAM:RegisterAddonPanel(panelName, panelData)
    LAM:RegisterOptionControls(panelName, optionsTable)
end

-- Event Managers
-- Register start and stop for combat state
EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_PLAYER_COMBAT_STATE,
    function(_, inCombat)
        DPSContributionTracker:OnCombatStateChanged(inCombat)
    end)

local function OnAddOnLoaded(event, addonName)
    if addonName == ADDON_NAME then
        d("AddOn Loaded: " .. addonName)
        EVENT_MANAGER:UnregisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED, OnAddOnLoaded)
        Initialize()
    end
end

EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED, OnAddOnLoaded)

-- Periodic update
EVENT_MANAGER:RegisterForUpdate(ADDON_NAME .. "_UpdateStatus", 1000, function()
    DPSContributionTracker:UpdateStatus()
end)
