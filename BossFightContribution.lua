local defaults = {
    groupDpsSize = 1,
    supportSetReduction = 0.0,
    fontSize = 28,
    labelPosX = 560,
    labelPosY = 60,
    showNotifications = false,
    bossHistory = {},
    fightCount = 0
}

BossFightContribution = {}
local ADDON_NAME = "BossFightContribution"

BossFightContribution.savedVars = nil
BossFightContribution.combatStartTime = 0
BossFightContribution.combatEndTime = 0
BossFightContribution.timeElapsed = 0
BossFightContribution.playerDamage = 0
BossFightContribution.currentEnemyHealth = 0
BossFightContribution.maxEnemyHealth = 0
BossFightContribution.lowestEnemyHealth = 0
BossFightContribution.inCombat = false
BossFightContribution.hasReported = false
BossFightContribution.bossName = ''
BossFightContribution.lastHealthCheck = 0
BossFightContribution.healthCheckInterval = 250
BossFightContribution.testLabelsVisible = false

--=============================================================================
-- DEBUG HELPER
--=============================================================================
function BossFightContribution:DebugPrint(message)
    if self.savedVars and self.savedVars.showNotifications then
        d(message)
    end
end

--=============================================================================
-- GET ENEMY HEALTH
--=============================================================================
function BossFightContribution:GetEnemyHealth()
    self:DebugPrint("running GetEnemeyHealth()")
    local unitTag

    if IsConsoleUI() then
        unitTag = "boss1"
        if not self.bossName or self.bossName == '' then
            self.bossName = GetUnitName(unitTag)
        end
    end

    if DoesUnitExist(unitTag) and IsUnitAttackable(unitTag) then
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
-- RESET VARIABLES
--=============================================================================
function BossFightContribution:OnCombatStateChanged(inCombat)
    if inCombat then
        self.inCombat = true
        self.playerDamage = 0
        self.playerTotalDamage = 0
        self.combatStartTime = GetGameTimeMilliseconds()
        self.hasReported = false
        self.lowestEnemyHealth = 0
        self:GetEnemyHealth()
        self:DebugPrint("Combat Started")
    else
        self.inCombat = false
        self.combatEndTime = GetGameTimeMilliseconds()
        self.timeElapsed = (self.combatEndTime - self.combatStartTime) / 1000
        self:DebugPrint(string.format("Combat Ended. Time: %.1f seconds", self.timeElapsed))
    end
end

--=============================================================================
-- TRACK PLAYER DAMAGE
--=============================================================================
function BossFightContribution:OnCombatEvent(eventCode, result, isError, abilityName, abilityGraphic,
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

        self:DebugPrint(string.format("Player hit for %d", hitValue))
    end
end

--=============================================================================
-- UPDATE STATUS
--=============================================================================
function BossFightContribution:UpdateStatus()
    if self.inCombat and self.bossName ~= '' then
        local currentTime = GetGameTimeMilliseconds()
        if currentTime - self.lastHealthCheck >= self.healthCheckInterval then
            self:GetEnemyHealth()
            self.lastHealthCheck = currentTime
        end
    end

    -- Calculate at end of fight
    if not self.inCombat and self.timeElapsed > 0 and self.maxEnemyHealth > 0 and not self.hasReported then
        -- Get user settings
        local supportSets = self.savedVars.supportSetReduction or 0
        local adjustedGroupDpsSize = self.savedVars.groupDpsSize - (supportSets * 0.2)
        if adjustedGroupDpsSize < 1 then
            adjustedGroupDpsSize = 1
        end

        -- Handle group wipe scenarios
        local actualBossDamage = self.maxEnemyHealth - self.lowestEnemyHealth
        if actualBossDamage <= 0 then
            actualBossDamage = 1
        end

        local playerDPS = self.playerDamage / self.timeElapsed
        local groupDPS = actualBossDamage / self.timeElapsed
        local expectedDPS = actualBossDamage / self.timeElapsed / adjustedGroupDpsSize
        local playerContribution = (self.playerDamage / actualBossDamage) * 100
        local expectedDMG = actualBossDamage / self.savedVars.groupDpsSize
        local expectedContribution = (1 / self.savedVars.groupDpsSize) * 100
        local outcome = self.lowestEnemyHealth == 0 and "KILL" or "WIPE"

        -- Format for GUI
        local outcomeDisplay = outcome == "KILL" and "KILL" or
            string.format("WIPE (%.1f%% remaining)", (self.lowestEnemyHealth / self.maxEnemyHealth) * 100)

        local bossText = string.format("%s - %s - HP: %d - Fight Time: %.1fs",
            self.bossName, outcomeDisplay, self.maxEnemyHealth, self.timeElapsed)

        local groupText = string.format("Group: %d DPS Players - Support Sets: %d (%.0f%%) - Group DPS: %.1f",
            self.savedVars.groupDpsSize, supportSets, supportSets * 20, groupDPS)

        local damageText = string.format("Your Damage Done: %.0f - Expected Damage Done: %.0f",
            self.playerDamage, expectedDMG)

        local dpsText = string.format("Your DPS: %.1f - Expected DPS: %.1f",
            playerDPS, expectedDPS)

        local contributionText = string.format("Your Contribution: %.1f%% - Expected Contribution: %.1f%%",
            playerContribution, expectedContribution)

        -- Create bossData object
        local bossData = {
            bossText,
            groupText,
            damageText,
            dpsText,
            contributionText
        }

        -- Save to table
        table.insert(self.savedVars.bossHistory, 1, bossData)

        self:DebugPrint(string.format("Debug: MaxHP=%d, LowestHP=%d, Damage=%d",
            self.maxEnemyHealth, self.lowestEnemyHealth, actualBossDamage))

        self:DebugPrint(string.format("Saved boss fight: %s - %s", self.bossName, outcome))

        self.hasReported = true
    end
end

--=============================================================================
-- DISPLAY LOG
--=============================================================================
function BossFightContribution:DisplayFight(fightData)
    line1_BossInfo:SetText(fightData[1])
    line2_GroupSetup:SetText(fightData[2])
    line3_DamageComparison:SetText(fightData[3])
    line4_DPSComparison:SetText(fightData[4])
    line5_Contribution:SetText(fightData[5])
end

--=============================================================================
-- INITIALIZE DEFAULTS
--=============================================================================
local function Initialize()
    BossFightContribution.savedVars = ZO_SavedVars:NewAccountWide(
        "DPSContributionTracker_SavedVars",
        1,
        nil,
        {
            groupDpsSize = 1,
            supportSetReduction = 0.0,
            fontSize = 18,
            labelPosX = 560,
            labelPosY = 60,
            showNotifications = false,
            bossHistory = {},
            fightCount = 0
        }
    )
    local labels = BossFightContribution:GetLabels()
    for i, label in ipairs(labels) do
        if label then
            label:SetHidden(true)
        end
    end

    BossFightContribution:UpdateLabelSettings()

    EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_COMBAT_EVENT,
        function(...) BossFightContribution:OnCombatEvent(...) end)

    BossFightContribution:CreateSettingsMenu()
end


--=============================================================================
-- UI MANAGEMENT
--=============================================================================
-- Get all labels
function BossFightContribution:GetLabels()
    return {
        _G["line1_BossInfo"],
        _G["line2_GroupSetup"],
        _G["line3_DamageComparison"],
        _G["line4_DPSComparison"],
        _G["line5_Contribution"]
    }
end

function BossFightContribution:UpdateLabelSettings()
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
            self:DebugPrint("Warning: Label " .. i .. " not found")
        end
    end
end

-- test labels
function BossFightContribution:ShowTestLabels()
    local testData = {
        "TEST LABEL: Molag Kena - KILL - HP: 850,000 - Fight Time: 45.2s",
        "Group: 4 DPS Players - Support Sets: 1 (20%) - Group DPS: 18.8k",
        "Your Damage Done: 242,500 - Expected Damage Done: 212,500",
        "Your DPS: 5.4k - Expected DPS: 4.7k",
        "Your Contribution: 114% - Expected Contribution: 100%"
    }
    return testData
end

function BossFightContribution:ClearTestLabels()
    local labels = self:GetLabels()
    for i, label in ipairs(labels) do
        if label then
            label:SetText("")
        end
    end
end

--=============================================================================
-- SETTINGS MENU
--=============================================================================
function BossFightContribution:CreateSettingsMenu()
    local LAM = LibAddonMenu2
    local panelName = "BossContributionSettings"
    local tutorialText = [[How Boss Contribution Works:

• 100% Contribution = Matching your group's average DPS (pulling your weight)
• Above 100% = Outperforming your group
• Below 100% = Underperforming compared to your group
• Off-boss mechanics (like portals), resurrections, adjustments are in development

]]

    local panelData = {
        type = "panel",
        name = "Boss Contribution",
        author = "YFNatey",
        version = "1.0",
        registerForRefresh = true,
        registerForDefaults = true
    }

    local optionsTable = {

        [1] = {
            type = "button",
            name = "Toggle UI",
            tooltip = tutorialText,

            func = function()
                local labels = self:GetLabels()
                local isCurrentlyHidden = labels[1] and labels[1]:IsHidden()

                if isCurrentlyHidden then
                    -- Unhide
                    for i, label in ipairs(labels) do
                        if label then
                            label:SetHidden(false)
                        end
                    end

                    -- Display most recent log
                    if self.savedVars.bossHistory and #self.savedVars.bossHistory > 0 then
                        self:DisplayFight(self.savedVars.bossHistory[1])
                    else
                        local testLabel = self:ShowTestLabels()
                        self:DisplayFight(testLabel)
                    end
                else
                    for i, label in ipairs(labels) do
                        if label then
                            label:SetHidden(true)
                        end
                    end
                    self:ClearTestLabels()
                end
            end
        },
        [2] = {
            type = "description",
            text = '|cF5DEB3|In development',
            tooltip =
            [[This addon currently only displays the most recent fight, Logging multiple fights is being worked on.
Enemy detection and DPS calcuations are being tested.
Currently testing for full damage DD only.
           ]]

        },

        [3] = {
            type = "divider",
        },
        [4] = {
            type = "description",
            text = "Fight Logs (In Development)"
        },
        [5] = {

        },
        [6] = {
            type = "button",
            name = "Clear Boss History",
            func = function()
                self.savedVars.bossHistory = {}
                d("Boss fight history cleared")
            end,
        },
        [7] = {
            type = "divider",
        },
        [8] = {
            type = "description",
            text = "Group Composition"
        },
        [9] = {
            type = "slider",
            name = "Number of DPS Players in group",
            tooltip = "Adjust the number of full damage DPS in group.\n Affects your expected DPS.",
            min = 1,
            max = 10,
            step = 1,
            getFunc = function() return self.savedVars.groupDpsSize end,
            setFunc = function(value) self.savedVars.groupDpsSize = value end,
            default = defaults.groupDpsSize,
        },
        [10] = {
            type = "slider",
            name = "Number of DPS support sets in group",
            tooltip = "Each support set is estimated to be a 20% damage loss",
            min = 0,
            max = 4,
            step = 1,
            getFunc = function() return self.savedVars.supportSetReduction end,
            setFunc = function(value) self.savedVars.supportSetReduction = value end,
            default = defaults.supportSetReduction,
        },

        [11] = {
            type = "divider",
        },
        [12] = {
            type = "description",
            text = "Adjust UI"
        },
        [13] = {
            type = "slider",
            name = "Font Size",
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
        [14] = {
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
        [15] = {
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
        [16] = {
            type = "divider",
        },
        [17] = {
            type = "checkbox",
            name = "Enable Debug Notifications",
            getFunc = function() return self.savedVars.showNotifications end,
            setFunc = function(value) self.savedVars.showNotifications = value end,
            default = defaults.showNotifications,
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
        BossFightContribution:OnCombatStateChanged(inCombat)
    end)

local function OnAddOnLoaded(event, addonName)
    if addonName == ADDON_NAME then
        EVENT_MANAGER:UnregisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED, OnAddOnLoaded)
        Initialize()
    end
end

EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED, OnAddOnLoaded)

-- Periodic update
EVENT_MANAGER:RegisterForUpdate(ADDON_NAME .. "_UpdateStatus", 1000, function()
    BossFightContribution:UpdateStatus()
end)
