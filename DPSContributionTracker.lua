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
DPSContributionTracker.currentBossHealth = 0
DPSContributionTracker.maxEnemyHealth = 1000000
DPSContributionTracker.inCombat = false


-- get enemy health
function DPSContributionTracker:GetEnemyHealth()
    local unitTag = "reticleover"
    if DoesUnitExist(unitTag) and IsUnitAttackable(unitTag) then
        local maxHP = GetUnitAttributeVisualizerValue(unitTag, ATTRIBUTE_HEALTH)
        self.maxEnemyHealth = maxHP
    end
end

-- Get combat state
function DPSContributionTracker:OnCombatStateChanged(inCombat)
    if inCombat then
        self:GetEnemyHealth()
        self.inCombat = true
        self.playerDamage = 0
        self.combatStartTime = GetGameTimeMilliseconds()
        d("Combat Started")
    else
        self.inCombat = false
        self.combatEndTime = GetGameTimeMilliseconds()
        self.timeElapsed = (self.combatEndTime - self.combatStartTime) / 1000
        d(string.format("Combat Ended. Time: %.1f seconds", self.timeElapsed))
    end
end

-- track player damage
function DPSContributionTracker:OnCombatEvent(_, _, _, _, _, _, sourceName, _, _, _, hitValue, _, _, _, _, targetUnitId,
                                              _, _)
    if sourceName == GetUnitName("player") and hitValue > 0 then
        self.playerDamage = self.playerDamage + hitValue
        debug(string.format("source: %s | hit: %d | targetID: %s", sourceName, hitValue, tostring(targetUnitId)))
    end
end

-- Update enemy health and print DPS info
function DPSContributionTracker:UpdateStatus()
    if not self.inCombat and self.timeElapsed > 0 and self.maxEnemyHealth then
        local expectedDPS = self.maxEnemyHealth / self.timeElapsed / 7.6
        local actualDPS = self.playerDamage / self.timeElapsed
        local contributionDiff = ((actualDPS - expectedDPS) / expectedDPS) * 100

        d(string.format("Enemy HP: %d", self.maxEnemyHealth))
        d(string.format("Your DPS: %.1f | Expected: %.1f | Difference: %.1f%%", actualDPS, expectedDPS, contributionDiff))
    end
end

-- INIT addon
local function Initialize()
    debug("Initializing addon")

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

    debug("Registered combat event")
end

-- Event Managers
-- Register start and stop for combat state
EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_PLAYER_COMBAT_STATE,
    function(_, inCombat)
        DPSContributionTracker:OnCombatStateChanged(inCombat)
    end)

local function OnAddOnLoaded(event, addonName)
    if addonName == ADDON_NAME then
        debug("AddOn Loaded: " .. addonName)
        EVENT_MANAGER:UnregisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED, OnAddOnLoaded)
        Initialize()
    end
end

EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED, OnAddOnLoaded)

-- Periodic update
EVENT_MANAGER:RegisterForUpdate(ADDON_NAME .. "_UpdateStatus", 1000, function()
    DPSContributionTracker:UpdateStatus()
end)
