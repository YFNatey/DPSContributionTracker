local defaults = {
    groupDpsSize = 1,
    supportSetReduction = 0.0,
    fontSize = 30,
    labelPosX = 100,
    labelPosY = 100
}

DPSContributionTracker = {}
local ADDON_NAME = "DPSContributionTracker"

DPSContributionTracker.savedVars = nil
DPSContributionTracker.combatStartTime = 0
DPSContributionTracker.combatEndTime = 0
DPSContributionTracker.timeElapsed = 0
DPSContributionTracker.playerDamage = 0
DPSContributionTracker.currentEnemyHealth = 0
DPSContributionTracker.maxEnemyHealth = 0
DPSContributionTracker.lowestEnemyHealth = 0
DPSContributionTracker.inCombat = false
DPSContributionTracker.hasReported = false
DPSContributionTracker.bossName = ''
DPSContributionTracker.lastHealthCheck = 0
DPSContributionTracker.healthCheckInterval = 2000


--=============================================================================
-- GET ENEMY HEALTH
--=============================================================================
function DPSContributionTracker:GetEnemyHealth()
    d("running GetEnemeyHealth()")
    local unitTag

    -- For Console. reticleover is disabled on console
    if IsConsoleUI() then
        unitTag = "boss1"
        if not self.bossName or self.bossName == '' then
            self.bossName = GetUnitName(unitTag)
        end
    end


    if DoesUnitExist(unitTag) and IsUnitAttackable(unitTag) then
        -- For console

        local current, max, effectiveMax = GetUnitPower(unitTag, COMBAT_MECHANIC_FLAGS_HEALTH)
        if max and max > 0 then
            self.maxEnemyHealth = max
            self.currentEnemyHealth = current

            -- If group wipes
            if current < self.lowestEnemyHealth or self.lowestEnemyHealth == 0 then
                self.lowestEnemyHealth = current
            end
        end
    end
end

--=============================================================================
-- RESET AT START OF FIGHT
--=============================================================================
function DPSContributionTracker:OnCombatStateChanged(inCombat)
    if inCombat then
        self.inCombat = true
        self.playerDamage = 0
        self.playerTotalDamage = 0
        self.combatStartTime = GetGameTimeMilliseconds()
        self.hasReported = false
        self.lowestEnemyHealth = 0
        self:GetEnemyHealth()
        d("Combat Started")
    else
        self.inCombat = false
        self.combatEndTime = GetGameTimeMilliseconds()
        self.timeElapsed = (self.combatEndTime - self.combatStartTime) / 1000
        d(string.format("Combat Ended. Time: %.1f seconds", self.timeElapsed))
    end
end

--=============================================================================
-- TRACK PLAYER DAMAGE
--=============================================================================
function DPSContributionTracker:OnCombatEvent(eventCode, result, isError, abilityName, abilityGraphic,
                                              abilityActionSlotType,
                                              sourceName, sourceType, targetName, targetType,
                                              hitValue, powerType, damageType, combatMechanic,
                                              sourceUnitId, targetUnitId, abilityId, overflow)
    -- table of acceptable damage types
    local DAMAGE_RESULTS = {
        [ACTION_RESULT_DAMAGE] = true,
        [ACTION_RESULT_DOT_TICK_CRITICAL] = true,
        [ACTION_RESULT_DAMAGE_SHIELDED] = true,
        [ACTION_RESULT_DOT_TICK] = true,
        [ACTION_RESULT_CRITICAL_DAMAGE] = true,
    }

    -- Reformat targetName to remove the gender suffix and match the unitTag string
    local formattedTargetName = targetName:match("([^%^]+)")

    -- Sum the player damage to the boss
    if DAMAGE_RESULTS[result] and sourceType == 1 and hitValue > 0 and formattedTargetName == self.bossName then
        self.playerDamage = self.playerDamage + hitValue

        d(string.format("Player hit for %d", hitValue))
    end
end

--=============================================================================
-- GENERATE REPORT
--=============================================================================
function DPSContributionTracker:UpdateStatus()
    if self.inCombat and self.bossName ~= '' then
        local currentTime = GetGameTimeMilliseconds()
        if currentTime - self.lastHealthCheck >= self.healthCheckInterval then
            self:GetEnemyHealth()
            self.lastHealthCheck = currentTime
        end
    end

    -- Get user input
    local supportSets = self.savedVars.supportSetReduction or 0
    local adjustedGroupDpsSize = self.savedVars.groupDpsSize - (supportSets * 0.2)

    if adjustedGroupDpsSize < 1 then
        adjustedGroupDpsSize = 1
    end

    -- Calculate at end of fight
    if not self.inCombat and self.timeElapsed > 0 and self.maxEnemyHealth > 0 and not self.hasReported then
        local actualBossDamage = self.maxEnemyHealth - self.lowestEnemyHealth
        local bossDamagePercent = (actualBossDamage / self.maxEnemyHealth) * 100

        if actualBossDamage <= 0 then
            actualBossDamage = 1
        end

        local expectedDPS = actualBossDamage / self.timeElapsed / adjustedGroupDpsSize
        local playerDPS = self.playerDamage / self.timeElapsed
        local groupDPS = actualBossDamage / self.timeElapsed
        local playerContribution = (self.playerDamage / actualBossDamage) * 100
        local expectedDMG = actualBossDamage / self.savedVars.groupDpsSize
        local expectedContribution = (1 / self.savedVars.groupDpsSize) * 100

        -- Display in GUI
        local outcome = self.lowestEnemyHealth == 0 and "KILL" or
            string.format("WIPE (%.1f%% remaining)",
                (self.lowestEnemyHealth / self.maxEnemyHealth) * 100
            )

        local bossText = string.format("%s - %s - HP: %s - Fight Time: %.1fs",
            self.bossName,
            outcome,
            string.format("%d", self.maxEnemyHealth),
            self.timeElapsed
        )

        local groupText = string.format("Group: %d DPS Players - Support Sets: %d (%.0f%%) - Group DPS: %.1f",
            self.savedVars.groupDpsSize,
            supportSets,
            supportSets * 20,
            groupDPS
        )

        local damageText = string.format(
            "Your Damage Done: %.0f - Expected Damage Done: %.0f",
            self.playerDamage,
            expectedDMG
        )

        local dpsText = string.format("Your DPS: %.1f - Expected DPS: %.1f",
            playerDPS,
            expectedDPS
        )

        local contributionText = string.format("Your Contribution: %.1f%% - Expected Contribution: %.1f%%",
            playerContribution,
            expectedContribution
        )

        line1_BossInfo:SetText(bossText)
        line2_GroupSetup:SetText(groupText)
        line3_DamageComparison:SetText(damageText)
        line4_DPSComparison:SetText(dpsText)
        line5_Contribution:SetText(contributionText)


        -- Debug info
        d(string.format("Debug: MaxHP=%d, LowestHP=%d, Damage to boss=%d",
            self.maxEnemyHealth, self.lowestEnemyHealth, actualBossDamage))
        self.hasReported = true
    end
end

--=============================================================================
-- INITIALIZE DEFAULTS
--=============================================================================
local function Initialize()
    DPSContributionTracker.savedVars = ZO_SavedVars:NewAccountWide(
        "DPSContributionTracker_SavedVars",
        1,
        nil,
        {
            showNotifications = true,
            dpsHistory = {},
            groupDpsSize = 1,
            supportSetReduction = 0.0,
            fontSize = 30,
            labelPosX = 100,
            labelPosY = 100
        }
    )
    local labels = DPSContributionTracker:GetLabels()
    for i, label in ipairs(labels) do
        if label then
            label:SetHidden(false)
        end
    end

    DPSContributionTracker:UpdateLabelSettings()

    EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_COMBAT_EVENT,
        function(...) DPSContributionTracker:OnCombatEvent(...) end)

    DPSContributionTracker:CreateSettingsMenu()
end


--=============================================================================
-- UI MANAGEMENT
--=============================================================================
-- Get all labels
function DPSContributionTracker:GetLabels()
    return {
        _G["line1_BossInfo"],
        _G["line2_GroupSetup"],
        _G["line3_DamageComparison"],
        _G["line4_DPSComparison"],
        _G["line5_Contribution"]
    }
end

function DPSContributionTracker:UpdateLabelSettings()
    local fontSize = self.savedVars.fontSize or 48
    local posX = self.savedVars.labelPosX or 100
    local posY = self.savedVars.labelPosY or 100
    local labels = self:GetLabels()

    for i, label in ipairs(labels) do
        if label then
            label:SetFont(string.format("$(BOLD_FONT)|%d", fontSize))
            label:ClearAnchors()
            local yOffset = posY + (i - 1) * 30
            label:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, posX, yOffset)
        else
            d("Warning: Label " .. i .. " not found")
        end
    end
end

--=============================================================================
-- SETTINGS MENU
--=============================================================================
function DPSContributionTracker:CreateSettingsMenu()
    local LAM = LibAddonMenu2
    local panelName = "DPSContributionTrackerSettings"

    local panelData = {
        type = "panel",
        name = "DPS playerContribution Tracker",
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
        [4] = {
            type = "slider",
            name = "Nmmber of DPS support sets in group",
            tooltip = "Each support set is estimated to be a 20% damage loss",
            min = 0,
            max = 4,
            step = 1,
            getFunc = function() return self.savedVars.supportSetReduction end,
            setFunc = function(value) self.savedVars.supportSetReduction = value end,
            default = defaults.supportSetReduction,
        },
        [5] = {
            type = "slider",
            name = "Font Size",
            tooltip = "Adjust label font size.",
            min = 10,
            max = 48,
            step = 1,
            getFunc = function() return self.savedVars.fontSize end,
            setFunc = function(value)
                self.savedVars.fontSize = value
                self:UpdateLabelSettings()
            end,
            default = 24,
        },
        [6] = {
            type = "slider",
            name = "Label X Position",
            min = 0,
            max = 1920,
            step = 10,
            getFunc = function() return self.savedVars.labelPosX end,
            setFunc = function(value)
                self.savedVars.labelPosX = value
                self:UpdateLabelSettings()
            end,
            default = 100,
        },
        [7] = {
            type = "slider",
            name = "Label Y Position",
            min = 0,
            max = 1080,
            step = 10,
            getFunc = function() return self.savedVars.labelPosY end,
            setFunc = function(value)
                self.savedVars.labelPosY = value
                self:UpdateLabelSettings()
            end,
            default = 100,
        },
    }

    LAM:RegisterAddonPanel(panelName, panelData)
    LAM:RegisterOptionControls(panelName, optionsTable)
end

--=============================================================================
-- EVENT MANAGERS
--=============================================================================
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
