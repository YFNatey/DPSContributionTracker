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
    local unitTag = "reticleover"
    if DoesUnitExist(unitTag) and IsUnitAttackable(unitTag) then
        local maxHP = GetUnitPower(unitTag, POWERTYPE_HEALTH)
        self.maxEnemyHealth = maxHP
        d("Detected enemy max health: " .. tostring(maxHP))
    else
        d("No valid enemy target detected")
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

        d(string.format("Player hit for %d", hitValue))
    end
end

-- Update enemy health and print DPS info
function DPSContributionTracker:UpdateStatus()
    if not self.inCombat and self.timeElapsed > 0 and self.maxEnemyHealth > 0 and not self.hasReported then
        local expectedDPS = self.maxEnemyHealth / self.timeElapsed / 1
        local actualDPS = self.playerDamage / self.timeElapsed
        local Contribution = (self.playerDamage / self.maxEnemyHealth) * 100
        d(string.format("Enemy HP: %d", self.maxEnemyHealth))
        d(string.format("Your DPS: %.1f | Expected DPS: %.1f | Contribution: %.1f%%", actualDPS, expectedDPS,
            Contribution))
        self.hasReported = true
    end
end

-- INIT addon
local function Initialize()
    d("Initializing addon")

    DPSContributionTracker.savedVars = ZO_SavedVars:NewAccountWide(
        "DPSContributionTracker_SavedVars",
        1,
        nil,
        {
            showNotifications = true,
            dpsHistory = {},
        }
    )

    EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_COMBAT_EVENT,
        function(...) DPSContributionTracker:OnCombatEvent(...) end)

    d("Registered combat event")
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
