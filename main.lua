--[[
	ActionSets, a module for saving and loading action slots
--]]

local Dominos = LibStub('AceAddon-3.0'):GetAddon('Dominos')
local ActionSets = Dominos:NewModule('ActionSets', 'AceEvent-3.0', 'AceConsole-3.0'); Dominos.ActionSets = ActionSets
local MAX_BUTTONS = 120
local PLAYER_CLASS = UnitClass('player')


--[[ Events ]]--

function ActionSets:OnInitialize()
	self:InitDatabase()
end

function ActionSets:OnEnable()
	self:RefreshMountCache()
	self:SaveActions()
	self:RegisterEvent('ACTIONBAR_SLOT_CHANGED', 'ACTIONBAR_SLOT_CHANGED')
end

function ActionSets:OnNewProfile()
	self:SaveActions()
end

function ActionSets:OnProfileChanged()
	self:RestoreActions()
end

function ActionSets:OnProfileCopied()
	self:RestoreActions()
end

function ActionSets:OnProfileReset()
	self:SaveActions()
end

function ActionSets:ACTIONBAR_SLOT_CHANGED(event, slot)
	self:SaveAction(slot, GetActionInfo(slot))
end


--[[ DB Settings ]]--

function ActionSets:InitDatabase()
	local db = Dominos.db:RegisterNamespace('ActionSets', self:GetDatabaseDefaults())

	db.RegisterCallback(self, 'OnNewProfile')
	db.RegisterCallback(self, 'OnProfileChanged')
	db.RegisterCallback(self, 'OnProfileCopied')
	db.RegisterCallback(self, 'OnProfileReset')

	self.db = db
end

function ActionSets:GetDatabaseDefaults()
	return {
		profile = {
			[PLAYER_CLASS] = {
				actionSets = {},
			}
		}
	}
end

function ActionSets:GetActionSetProfile()
	return self.db.profile[PLAYER_CLASS].actionSets
end


--[[ Storage API ]]--

function ActionSets:SaveActions()
	for slot = 1, MAX_BUTTONS do
		self:SaveAction(slot, GetActionInfo(slot))
	end
end

function ActionSets:SaveAction(slot, ...)
	local actionSets = self:GetActionSetProfile()

	if select('#', ...) > 0 then
		actionSets[slot] = strjoin('|', GetActionInfo(slot))
	else
		actionSets[slot] = nil
	end
end

function ActionSets:GetSavedActionInfo(slot)
	local savedInfo = self:GetActionSetProfile()[slot]

	if savedInfo then
		return strsplit('|', savedInfo)
	end
end

function ActionSets:RestoreActions()
	self:UnregisterEvent('ACTIONBAR_SLOT_CHANGED')

	for slot = 1, MAX_BUTTONS do
		self:RestoreAction(slot)
	end

	self:RegisterEvent('ACTIONBAR_SLOT_CHANGED', 'ACTIONBAR_SLOT_CHANGED')
end

function ActionSets:RestoreAction(slot)
	self:SetAction(slot, self:GetSavedActionInfo(slot))
end


--[[
	mount id -> mount index cache.  Needed because C_MountJournal.Pickup doesn't work on mountIds
--]]

do
	local SUMMON_RANDOM_MOUNT_ID = 268435455
	local SUMMON_RANDOM_MOUNT_INDEX = 0

	local mountCache = {}
	local pickupMount = C_MountJournal.Pickup
	local getCursorInfo = GetCursorInfo
	local clearCursor = ClearCursor

	function ActionSets:GetMountIndex(mountId)
		return mountCache[mountId]
	end

	function ActionSets:PickoutMountId(mountId)
		local mountIndex = ActionSets:GetMountIndex(mountId)

		if mountIndex then
			pickupMount(mountIndex)
			return true
		end
	end

	function ActionSets:RefreshMountCache()
		mountCache = {[SUMMON_RANDOM_MOUNT_ID] = SUMMON_RANDOM_MOUNT_INDEX}

		for mountIndex = 1, C_MountJournal.GetNumMounts() do
			pickupMount(mountIndex)

			local mountId = select(2, getCursorInfo())
			if mountId then
				mountCache[mountId] = mountIndex
			end

			clearCursor()
		end
	end
end

--[[ Action Button API ]]--

local setActionMethods = {
	clear = function(slot)
		if HasAction(slot) then
			PickupAction(slot)
			ClearCursor()
		end
	end,

	item = function(slot, itemId, ...)
		local itemId = tonumber(itemId) or itemId
		local currentType, currentItemId = GetActionInfo(slot)

		if not(currentType  == 'item' and currentItemId == itemId) then
			PickupItem(itemId)
			return true
		end
	end,

	macro = function(slot, macroId)
		local macroId = tonumber(macroId) or macroId
		local currentType, currentMacroId = GetActionInfo(slot)

		if not(currentType  == 'macro' and currentMacroId == macroId) then
			PickupMacro(macroId)
			return true
		end
	end,

	petaction = function(slot, petActionId)
		local petActionId = tonumber(petActionId) or petActionId
		local currentType, currentPetActionId = GetActionInfo(slot)

		if not(currentType  == 'petaction' and currentPetActionId == petActionId) then
			PickupPetAction(petActionId)
			return true
		end
	end,

	spell = function(slot, spellId)
		local spellId = tonumber(spellId) or spellId
		local currentType, currentSpellId = GetActionInfo(slot)

		if not(currentType  == 'spell' and currentSpellId == spellId) then
			PickupSpell(spellId)
			return true
		end
	end,

	companion = function(slot, companionId, companionType)
		local companionId = tonumber(companionId) or companionId
		local currentType, currentCompanionId, currentCompanionType = GetActionInfo(slot)

		if not(currentType  == 'companion' and currentCompanionId == companionId and currentCompanionType == companionType) then
			PickupCompanion(companionType, companionId)
			return true
		end
	end,

	equipmentset = function(slot, setId)
		local setId = tonumber(setId) or setId
		local currentType, currentSetId = GetActionInfo(slot)

		if not(currentType == 'equipmentset' and currentSetId == setId) then
			PickupEquipmentSet(setId)
			return true
		end
	end,

	summonmount = function(slot, mountId)
		local mountId = tonumber(mountId) or mountId
		local currentType, currentMountId = GetActionInfo(slot)

		if not(currentType == 'summonmount' and currentMountId == mountId) then
			if ActionSets:PickoutMountId(mountId) then
				return true
			end

			ActionSets:Printf('Could not set slot %d to mountId %s', slot, mountId)
		end
	end,

	summonpet = function(slot, petId)
		local petId = tonumber(petId) or petId
		local currentType, currentPetId = GetActionInfo(slot)

		if not(currentType == 'summonpet' and currentPetId == petId) then
			C_PetJournal.PickupPet(petId)
			return true
		end
	end
}

function ActionSets:SetAction(slot, ...)
	local type = (select(1, ...))
	local pickupActionFunc = setActionMethods[type or 'clear']

	if pickupActionFunc then
		if pickupActionFunc(slot, select(2, ...)) then
			PlaceAction(slot)
		end
	else
		self:Print('Unhandled action type:', ...)
	end
end
