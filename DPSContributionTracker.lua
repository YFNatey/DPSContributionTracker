DPSContributionTracker = {}
local ADDON_NAME = "DPSContributionTracker"


DPSContributionTracker.savedVars = nil
DPSContributionTracker.totalBossMaxHealth = 0
DPSContributionTracker.totalBossCurrentHealth = 0
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
