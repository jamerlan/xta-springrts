function gadget:GetInfo()
    return {
        name      = 'Energy Conversion',
        desc      = 'Handles converting energy to metal',
        author    = 'Niobium(modified by TheFatController, Finkky)',
        version   = 'v2.3',
        date      = 'May 2011',
        license   = 'GNU GPL, v2 or later',
        layer     = 0,
        enabled   = true
    }
end

-- Updates: 2014.09: Made it possible to unload widget and handle mmakers manually. Jools.

----------------------------------------------------------------
-- Synced only
----------------------------------------------------------------
if not gadgetHandler:IsSyncedCode() then
    return false
end

----------------------------------------------------------------
-- Config
----------------------------------------------------------------
local alterLevelRegex = '^' .. string.char(137) .. '(%d+)$'
local operationRegex = '^' .. 'energyconversion:' .. '(%d+)'
local mmLevelParamName = 'mmLevel'
local mmCapacityParamName = 'mmCapacity'
local mmUseParamName = 'mmUse'
local mmAvgEfficiencyParamName = 'mmAvgEfficiency'
local mmAvgEffiParamName = 'mmAvgEffi'

local frameRate = 32
local resourceRefreshRate = 16 -- In Frames
local resourceFraction = resourceRefreshRate / frameRate
local resourceUpdatesPerGameSec = frameRate / resourceRefreshRate

local convertCapacities = include("LuaRules/Configs/maker_defs.lua")
local currentFrameStamp = 0
local widgetLoaded = {}

----------------------------------------------------------------
-- Vars
----------------------------------------------------------------
local teamList = {}
local teamCapacities = {}
local teamUsages = {}
local teamMMList = {}
local teamEfficiencies = {}
local eSteps = {}
local teamActiveMM = {}
local lastPost = {}
local splitMMPointer = 1
local splitMMUpdate = 90

----------------------------------------------------------------
-- Constant
----------------------------------------------------------------

local paralysisRelRate = 75 -- unit HP / paralysisRelRate = paralysis dmg drop rate per slowupdate

----------------------------------------------------------------
-- Speedups
----------------------------------------------------------------
local min = math.min
local spGetPlayerInfo = Spring.GetPlayerInfo
local spGetTeamRulesParam = Spring.GetTeamRulesParam
local spSetTeamRulesParam = Spring.SetTeamRulesParam
local spGetTeamResources = Spring.GetTeamResources
local spGetUnitHealth = Spring.GetUnitHealth
local spSetUnitCOBValue = Spring.SetUnitCOBValue
local spGetUnitTeam = Spring.GetUnitTeam
local spGetUnitDefID = Spring.GetUnitDefID
local ValidUnitID							= Spring.ValidUnitID
local CMD_ONOFF  							= CMD.ONOFF
local CMD_ENERGYCONVERT						= 39310
local Echo 									= Spring.Echo
local EditUnitCmdDesc						= Spring.EditUnitCmdDesc
local FindUnitCmdDesc						= Spring.FindUnitCmdDesc
local InsertUnitCmdDesc						= Spring.InsertUnitCmdDesc
local GetUnitStates							= Spring.GetUnitStates
local GetUnitIsStunned						= Spring.GetUnitIsStunned

----------------------------------------------------------------
-- Functions
----------------------------------------------------------------

local energyConvertCmd = {
  id      = CMD_ENERGYCONVERT,
  type    = CMDTYPE.ICON_MODE,
  name    = 'Energy Convert',
  cursor  = 'Guard',
  tooltip = 'Choose between manually managed or centrally managed metal makers',
  params  = { '1', 'Manual','Managed'},
  hidden = true,
}

local function UpdateMMButtonButton(unitID, newValue)
	local cmdDescID = FindUnitCmdDesc(unitID, CMD_ENERGYCONVERT)
	if (cmdDescID == nil) then
		return
	end
	
	energyConvertCmd.params[1] = newValue
	EditUnitCmdDesc(unitID, cmdDescID, {params  = energyConvertCmd.params})
	Spring.SetUnitRulesParam(unitID,"EnergyConvert",newValue)
end

local function prototype(t)
  local u = { }
  for k, v in pairs(t) do u[k] = v end
  return setmetatable(u, getmetatable(t))
end

local function AdjustTeamCapacity(teamID, adjustment, e)
    local newCapacity = teamCapacities[teamID][e] + adjustment
    teamCapacities[teamID][e] = newCapacity
	
	local totalCapacity = 0
	for j = 1, #eSteps do
		totalCapacity = totalCapacity + teamCapacities[teamID][eSteps[j]]
	end
    spSetTeamRulesParam(teamID, mmCapacityParamName, totalCapacity)
end

local function UpdateMetalMakers(teamID, energyUse)
	if not widgetLoaded[teamID] then 
		return
	end
	
	for j = 1, #eSteps do
		for unitID, defs in pairs(teamMMList[teamID][eSteps[j]]) do
			if (defs.built) then
				if (defs.emped) then
					if (defs.status == 1) then
						spSetUnitCOBValue(unitID,1024,0)
						defs.status = 0
						teamActiveMM[teamID] = (teamActiveMM[teamID] - 1)
					end
				else
					if (energyUse > 0) then
						energyUse = (energyUse - defs.capacity)
						if (defs.status == 0) then
							spSetUnitCOBValue(unitID,1024,1)
							defs.status = 1
							teamActiveMM[teamID] = (teamActiveMM[teamID] + 1)
						end
					else
						if (teamActiveMM[teamID] == 0) then break end
						if (defs.status == 1) then
							spSetUnitCOBValue(unitID,1024,0)
							defs.status = 0
							teamActiveMM[teamID] = (teamActiveMM[teamID] - 1)
						end
					end
				end
			end
		end
	end
end

----------------------------------------------------------------
-- Pseudo Callins
----------------------------------------------------------------

local function UnitParalysed(uID, uDefID, uTeam)
	local cDefs = convertCapacities[uDefID]
    if cDefs then
		if teamMMList[uTeam][cDefs.e][uID] then
			if teamMMList[uTeam][cDefs.e][uID].built then
				teamMMList[uTeam][cDefs.e][uID].emped = true
				AdjustTeamCapacity(uTeam, -cDefs.c, cDefs.e)
			end
		end
    end
end

local function UnitParalysisOver(uID, uDefID, uTeam)
	local cDefs = convertCapacities[uDefID]
    if cDefs then
		local wasManaged = true
		if not teamMMList[uTeam][cDefs.e][uID] then
			wasManaged = false
			local isBuilt = select(5,spGetUnitHealth(uID)) >= 1
			local states = GetUnitStates(uID)
			local state = states.active and 1 or 0
			teamMMList[uTeam][cDefs.e][uID] = {capacity = 0, status = state, built = isBuilt, emped = false}
		end
		
		if teamMMList[uTeam][cDefs.e][uID].built and wasManaged then
			teamMMList[uTeam][cDefs.e][uID].emped = false
			AdjustTeamCapacity(uTeam, cDefs.c, cDefs.e)
		end
    end
end

----------------------------------------------------------------
-- EmpedVector Methods
----------------------------------------------------------------
local EmpedVector = {unitBuffer={}}
local tableInsert = table.insert

function EmpedVector:push(uID, frameID)
	if self.unitBuffer[uID] then
		self.unitBuffer[uID] = frameID
	else
		tableInsert(self.unitBuffer, uID, frameID)
		UnitParalysed(uID, spGetUnitDefID(uID), spGetUnitTeam(uID))
	end
end

function EmpedVector:process(currentFrame)
	for uID, frameID in pairs(self.unitBuffer) do
		if (currentFrame >= frameID) then
			UnitParalysisOver(uID, spGetUnitDefID(uID), spGetUnitTeam(uID))
			
			self.unitBuffer[uID] = nil
		end
	end
end

----------------------------------------------------------------
-- Efficiencies Methods
----------------------------------------------------------------
local Efficiencies = {size =4, buffer={}, pointer=0, tID = -1}

function Efficiencies:avg()
	local sumE = 0
	local sumM = 0
	local nonZeroCount = 0
	for j=1, self.size do
		if not (self.buffer[j] == nil) then
			sumM = sumM + self.buffer[j].m
			sumE = sumE + self.buffer[j].e
			nonZeroCount = nonZeroCount + 1 
		end
	end
	if(nonZeroCount > 0 and sumE > 0) then return sumM/sumE end
	return 0
end

function Efficiencies:push(o)
	self.buffer[self.pointer + 1] = o
	self.pointer = (self.pointer +1) % self.size
end

function Efficiencies:init(tID)
	for j=1, self.size do
		self.buffer[j]=nil
	end
	self.tID = tID
end

----------------------------------------------------------------
-- Callins
----------------------------------------------------------------
function gadget:Initialize()
    local i = 1
    for defid, defs in pairs(convertCapacities) do
		local inTable = false
		for _,e in ipairs(eSteps) do
			if (e == defs.e) then
			  inTable = true
			end
		end
		if (inTable == false) then
			eSteps[i] = defs.e
			i = (i + 1)
		end
    end
    table.sort(eSteps, function(m1,m2) return m1 > m2; end)
    teamList = Spring.GetTeamList()
    for i = 1, #teamList do
        local tID = teamList[i]
        teamCapacities[tID] = {}
		teamEfficiencies[tID] = prototype(Efficiencies)
		teamEfficiencies[tID]:init(tID)
        teamMMList[tID] = {}
        teamActiveMM[tID] = 0
        lastPost[tID] = 0
        for j = 1, #eSteps do
			teamCapacities[tID][eSteps[j]] = 0
			teamMMList[tID][eSteps[j]] = {}
        end
        teamUsages[tID] = 0
        spSetTeamRulesParam(tID, mmLevelParamName, 0.75)
        spSetTeamRulesParam(tID, mmCapacityParamName, 0)
        spSetTeamRulesParam(tID, mmUseParamName, 0)
		spSetTeamRulesParam(tID, mmAvgEffiParamName, teamEfficiencies[tID]:avg())

    end
    splitMMUpdate = math.floor(math.max((90 / #teamList),1))
end

function gadget:AllowCommand(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOptions, cmdTag, synced)
	if cmdID ~= CMD_ONOFF and cmdID ~= CMD_ENERGYCONVERT then
		return true
	end
		
	if cmdID == CMD_ONOFF then
		local _,isStunned = GetUnitIsStunned(unitID)
		if isStunned then 
			return false 
		end
	
		local state = cmdParams and cmdParams[1] or 0
		local cDefs = convertCapacities[unitDefID]
		if cDefs and cDefs.e and teamMMList[unitTeam][cDefs.e] and teamMMList[unitTeam][cDefs.e][unitID] then
			if teamMMList[unitTeam][cDefs.e][unitID].built then
				if teamMMList[unitTeam][cDefs.e][unitID].status ~= state then
					teamMMList[unitTeam][cDefs.e][unitID].status = state
				end
			end
		end
		return true
	
	elseif cmdID == CMD_ENERGYCONVERT then
		
		local newValue = cmdParams[1]
		local cDefs = convertCapacities[unitDefID]
		
		if cDefs and newValue then
			UpdateMMButtonButton(unitID,newValue)
			
			-- add or remove metal maker to/from central command
			local isBuilt = select(5,spGetUnitHealth(unitID)) >= 1
			local _,isEmped = GetUnitIsStunned(unitID)
						
			if newValue == 1 then -- set to managed
				local states = GetUnitStates(unitID)
				local state = states.active and 1 or 0
				
				if not teamMMList[unitTeam][cDefs.e][unitID] then 
					teamMMList[unitTeam][cDefs.e][unitID] = {capacity = cDefs.c, status = state, built = isBuilt, emped = isEmped}
				end
				
				if (not isEmped) and isBuilt then
					teamActiveMM[unitTeam] = teamActiveMM[unitTeam] + 1
					AdjustTeamCapacity(unitTeam, cDefs.c, cDefs.e)
				end
			
			elseif newValue == 0 then -- set to manual
				if teamMMList[unitTeam][cDefs.e][unitID] then				
					if (teamMMList[unitTeam][cDefs.e][unitID].status == 1) then
						teamActiveMM[unitTeam] = teamActiveMM[unitTeam] - 1
					end
					
					if not teamMMList[unitTeam][cDefs.e][unitID].emped then
						AdjustTeamCapacity(unitTeam, -cDefs.c, cDefs.e)
					end
				end
				
				teamMMList[unitTeam][cDefs.e][unitID] = nil
			end
		end
		
		return false
	end
end

function gadget:GameFrame(n)

	if (n % resourceRefreshRate == 0) then
		
		currentFrameStamp = currentFrameStamp + 1
		
		EmpedVector:process(currentFrameStamp)	
		
		for i = 1, #teamList do
			local tID = teamList[i]
			if widgetLoaded[tID] then
			
				local eCur, eStor = spGetTeamResources(tID, 'energy')
				local convertAmount = eCur - eStor * spGetTeamRulesParam(tID, mmLevelParamName)
				local eConvert = 0
				local mConvert = 0
				local eConverted = 0
				local mConverted = 0
				
				for j = 1, #eSteps do
					if(teamCapacities[tID][eSteps[j]] > 1) then
						if (convertAmount > 1) then
							local convertStep = min(teamCapacities[tID][eSteps[j]] * resourceFraction, convertAmount)
							eConverted = convertStep + eConverted
							mConverted = convertStep * eSteps[j] + mConverted
							teamUsages[tID] = teamUsages[tID] + convertStep
							convertAmount = convertAmount - convertStep
						else break end
					end
				end

				teamEfficiencies[tID]:push({m=mConverted, e=eConverted})

				local tUsage = (resourceUpdatesPerGameSec * teamUsages[tID])
				spSetTeamRulesParam(tID, mmUseParamName, tUsage)
				spSetTeamRulesParam(tID, mmAvgEffiParamName, teamEfficiencies[tID]:avg())			
				
				lastPost[tID] = tUsage
				teamUsages[tID] = 0
			end
		end
	end

    if (n%splitMMUpdate == 0) then
		local tID = teamList[splitMMPointer]
		UpdateMetalMakers(tID,lastPost[tID])
		if (splitMMPointer == #teamList) then
			splitMMPointer = 1
		else
			splitMMPointer = splitMMPointer + 1
		end
    end
end

function gadget:UnitCreated(uID, uDefID, uTeam, builderID)
	local cDefs = convertCapacities[uDefID]
    if cDefs then
        InsertUnitCmdDesc(uID, 72, energyConvertCmd)
		teamMMList[uTeam][cDefs.e][uID] = {capacity = 0, status = 0, built = false, emped = false}
    end
end

function gadget:UnitFinished(uID, uDefID, uTeam)
    local cDefs = convertCapacities[uDefID]
	-- added check for presence of uID for that team, otherwise a nil error if a builder that is given to another team finishes
	-- constructing a metal maker.
    if cDefs and ValidUnitID(uID) then
		if not teamMMList[uTeam][cDefs.e][uID] then 
			teamMMList[uTeam][cDefs.e][uID] = {capacity = 0, status = 0, built = false, emped = false}
		end
			
		teamMMList[uTeam][cDefs.e][uID].capacity = cDefs.c
		teamMMList[uTeam][cDefs.e][uID].built = true
		
		if not teamMMList[uTeam][cDefs.e][uID].emped then
			teamMMList[uTeam][cDefs.e][uID].status = 1
			teamActiveMM[uTeam] = teamActiveMM[uTeam] + 1
			spSetUnitCOBValue(uID,1024,1)
			AdjustTeamCapacity(uTeam, cDefs.c, cDefs.e)
		end
    end
end

function gadget:UnitDamaged(uID, uDefID, uTeam, damage, paralyzer)
	local cDefs = convertCapacities[uDefID]

    if paralyzer and cDefs then
		local _, maxHealth, paralyzeDamage, _ ,_ = spGetUnitHealth(uID)
		local relativeParDmg = paralyzeDamage -  maxHealth -- or you could just use Spring.GetUnitIsStunned
		if (relativeParDmg > 0) then 
			EmpedVector:push(uID, currentFrameStamp + math.ceil(relativeParDmg / (maxHealth / paralysisRelRate)))
		end
    end
end

function gadget:UnitDestroyed(uID, uDefID, uTeam)
    local cDefs = convertCapacities[uDefID]
    if cDefs and uID and ValidUnitID(uID) and uTeam and teamMMList[uTeam][cDefs.e][uID] then
		
		if teamMMList[uTeam][cDefs.e][uID].built then
			if (teamMMList[uTeam][cDefs.e][uID].status == 1) then
				teamActiveMM[uTeam] = teamActiveMM[uTeam] - 1
			end
			
			if not teamMMList[uTeam][cDefs.e][uID].emped then
				AdjustTeamCapacity(uTeam, -cDefs.c, cDefs.e)
			end
			
			teamMMList[uTeam][cDefs.e][uID] = nil
		end
    end
end

function gadget:UnitGiven(uID, uDefID, newTeam, oldTeam)
    local cDefs = convertCapacities[uDefID]
    if cDefs then
        if teamMMList[oldTeam][cDefs.e][uID].built then
			
			if not teamMMList[oldTeam][cDefs.e][uID].emped then
				AdjustTeamCapacity(oldTeam, -cDefs.c, cDefs.e)
				AdjustTeamCapacity(newTeam,  cDefs.c, cDefs.e)
			end
            if (teamMMList[oldTeam][cDefs.e][uID].status == 1) then
				teamActiveMM[oldTeam] = teamActiveMM[oldTeam] - 1
				teamActiveMM[newTeam] = teamActiveMM[newTeam] + 1
			end
			
			--teamMMList[newTeam][cDefs.e][uID] = teamMMList[oldTeam][cDefs.e][uID]
			-- using "deep copy" instead 
			
			teamMMList[newTeam][cDefs.e][uID] = {}
			teamMMList[newTeam][cDefs.e][uID].capacity = teamMMList[oldTeam][cDefs.e][uID].capacity
			teamMMList[newTeam][cDefs.e][uID].status = teamMMList[oldTeam][cDefs.e][uID].status
			teamMMList[newTeam][cDefs.e][uID].emped = teamMMList[oldTeam][cDefs.e][uID].emped
			teamMMList[newTeam][cDefs.e][uID].built  = teamMMList[oldTeam][cDefs.e][uID].built
			
            teamMMList[oldTeam][cDefs.e][uID] = nil
        end
    end
end

function gadget:RecvLuaMsg(msg, playerID)
	
    local newLevel = tonumber(msg:match(alterLevelRegex))
	local operationState = tonumber(msg:match(operationRegex))
	
    if newLevel and newLevel >= 0 and newLevel <= 100 then
        local _, _, playerIsSpec, playerTeam = spGetPlayerInfo(playerID)
        if not playerIsSpec then
            spSetTeamRulesParam(playerTeam, mmLevelParamName, newLevel / 100)
            return true
        end
	elseif operationState then
		local _, _, playerIsSpec, playerTeam = spGetPlayerInfo(playerID)
        if not playerIsSpec then
			if operationState == 1 then
				widgetLoaded[playerTeam] = true
			elseif operationState == 0 then
				widgetLoaded[playerTeam] = nil
			end
		end
    end
	
	
end
