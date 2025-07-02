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
DPSContributionTracker.inCombat = false
DPSContributionTracker.hasReported = false
DPSContributionTracker.bossName = ''

-- get enemy health
function DPSContributionTracker:GetEnemyHealth()
    d("running GetEnemeyHealth()")
    local unitTag

    -- For Console. reticleover is disabled on console
    if IsConsoleUI() then
        unitTag = "boss1"
        self.bossName = GetUnitName(unitTag)
    else
        unitTag = "reticleover"
    end

    if DoesUnitExist(unitTag) and IsUnitAttackable(unitTag) then
        -- For PC
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
    end
end

-- Get combat state
function DPSContributionTracker:OnCombatStateChanged(inCombat)
    if inCombat then
        self.inCombat = true
        self.playerDamage = 0
        self.playerTotalDamage = 0
        self.combatStartTime = GetGameTimeMilliseconds()
        self.hasReported = false
        self:GetEnemyHealth()
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

-- Update enemy health and print DPS info
function DPSContributionTracker:UpdateStatus()
    -- Get user input
    local supportSets = self.savedVars.supportSetReduction or 0
    local adjustedGroupDpsSize = self.savedVars.groupDpsSize - (supportSets * 0.2)

    if adjustedGroupDpsSize < 1 then
        adjustedGroupDpsSize = 1
    end

    if not self.inCombat and self.timeElapsed > 0 and self.maxEnemyHealth > 0 and not self.hasReported then
        local expectedDPS = self.maxEnemyHealth / self.timeElapsed / adjustedGroupDpsSize
        local playerDPS = self.playerDamage / self.timeElapsed
        local playerContribution = (self.playerDamage / self.maxEnemyHealth) * 100
        local expectedDMG = self.maxEnemyHealth / self.savedVars.groupDpsSize
        local expectedContribution = (1 / self.savedVars.groupDpsSize) * 100


        d("group dps size" .. tostring(adjustedGroupDpsSize))
        d(string.format("Enemy HP: %d", self.maxEnemyHealth))
        d(string.format(
            "Damage Done: %.0f | Your DPS: %.1f | Expected Damage Done: %.0f | Expected DPS: %.1f | Your Contribution: %.1f%% | Expected playerContribution: %.1f%%",
            self
            .playerDamage, playerDPS, expectedDMG, expectedDPS,
            playerContribution, expectedContribution))

        -- Update both labels
        local line1Text = string.format(
            "Your Damage Done: %.0f | Expected Damage Done: %.0f",
            self.playerDamage, expectedDMG, playerDPS, expectedDPS)
        -- Update both labels
        local line2Text = string.format(
            "Your DPS: %.1f | Expected DPS: %.1f",
            playerDPS, expectedDPS)
        local line3Text = string.format("Your Contribution: %.1f%% | Expected Contribution: %.1f%%",
            playerContribution, expectedContribution)

        DPSContributionTracker_Label1:SetText(line1Text)
        DPSContributionTracker_Label2:SetText(line2Text)
        DPSContributionTracker_Label3:SetText(line3Text)
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
            groupDpsSize = 1,
            supportSetReduction = 0.0,
            fontSize = 30,
            labelPosX = 100,
            labelPosY = 100
        }
    )

    EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_COMBAT_EVENT,
        function(...) DPSContributionTracker:OnCombatEvent(...) end)

    DPSContributionTracker:CreateSettingsMenu()
end


-- Adjust UI
function DPSContributionTracker:UpdateLabelSettings()
    -- Defaults for initial debugging, will change later
    local fontSize = self.savedVars.fontSize or 48
    local posX = self.savedVars.labelPosX or 500
    local posY = self.savedVars.labelPosY or 300

    DPSContributionTracker_Label:SetFont(string.format("$(BOLD_FONT)|%d", fontSize))
    DPSContributionTracker_Label:ClearAnchors()
    DPSContributionTracker_Label:SetAnchor(CENTER, GuiRoot, CENTER, 0, 0)
end

--Settings Menu
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
