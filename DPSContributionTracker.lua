DPSContributionTracker = {}
local ADDON_NAME = "DPSContributionTracker"


DPSContributionTracker.savedVars = nil

DPSContributionTracker.playerDamage = 0
DPSContributionTracker.currentBossHealth = 0
DPSContributionTracker.maxBossHealth = 0

--Get total boss health
function DPSContributionTracker:GetBossHealth()
    self.currentBossHealth = 0
    self.maxBossHealth = 0
    for i = 1, 5 do
        local unitTag = "boss" .. i
        if DoesUnitExist(unitTag) then
            self.currentBossHealth = self.currentBossHealth + GetUnitHealth(unitTag)
            self.maxBossHealth = self.maxBossHealth + GetUnitMaxHealth(unitTag)
        end
    end
end

-- Called every combat event to track player damage
function DPSContributionTracker:OnCombatEvent(_, _, _, _, _, _, sourceName, _, _, _, hitValue, _, _, _, _, targetUnitId,
                                              _, _)
    if sourceName == GetUnitName("player") and hitValue > 0 and (targetUnitId and IsUnitBoss(targetUnitId)) then
        self.playerDamage = self.playerDamage + hitValue
    end
end

-- Called to update the boss health and print DPS info
function DPSContributionTracker:UpdateStatus()
    self.GetBossHealth()
    if self.maxBossHealth > 0 then
        local damageDone = self.maxBossHealth - self.currentBossHealth
        local damagePercent = (damageDone / self.maxBossHealth) * 100
        d(string.format("Boss HP: %d / %d (%.2f%%)", self.currentBossHealth, self.maxBossHealth, damagePercent))
        d(string.format("Your damage: %d", self.playerDamage))

        local expectedDPS = self.maxBossHealth / self.playerDamage / 7.6
    end
end

DPSContributionTracker.combatStartTime = 0
DPSContributionTracker.combatEndTime = 0
DPSContributionTracker.timeElapsed = 0

function DPSContributionTracker:OnCombatStateChanged(inCombat)
    if inCombat then
        self.playerDamage = 0
        self.combatStartTime = GetGameTimeMilliseconds()
        d("Combat Started")
    else
        self.combatEndTime = GetGameTimeMilliseconds()
        self.timeElapsed = (self.combatEndTime - self.combatStartTime) / 1000
        d(string.format("Combat Ended. Time: %.1f seconds", self.timeElapsed))
    end
end

local function Initialize()
    -- Initialize saved variables
    DPSContributionTracker.savedVars = ZO_SavedVars:NewAccountWide(
        "DPSContributionTracker_SavedVars",
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

-- Register start and stop for combat state
EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_PLAYER_COMBAT_STATE,
    function(_, inCombat)
        DPSContributionTracker:OnCombatStateChanged(inCombat)
    end)

local function OnAddOnLoaded(event, addonName)
    if addonName == ADDON_NAME then
        EVENT_MANAGER:UnregisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED, OnAddOnLoaded)
        Initialize()
    end
end

EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED, OnAddOnLoaded)
