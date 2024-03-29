--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
--  file:    game_spawn.lua
--  brief:   spawns start unit and sets storage levels
--           (special version for XTA)
--  author:  Tobi Vollebregt
--
--  Copyright (C) 2010.
--  Licensed under the terms of the GNU GPL, v2 or later.
--
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function gadget:GetInfo()
    return {
        name      = "Spawn",
        desc      = "spawns start unit and sets storage levels",
        author    = "Tobi Vollebregt/TheFatController",
        date      = "January, 2010",
        license   = "GNU GPL, v2 or later",
        layer     = 0,
        enabled   = true  --  loaded by default?
    }
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

-- synced only
if (not gadgetHandler:IsSyncedCode()) then
    return false
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local startUnitParamName = 'startUnit'
local spGetTeamRulesParam = Spring.GetTeamRulesParam
local spSetTeamRulesParam = Spring.SetTeamRulesParam


-- Maps 'commander' mod option to ARM start unit.
local arm_start_unit = {
    autoupgrade = "arm_commander",
    halfupgrade = "arm_u2commander",
    fullupgrade = "arm_u4commander",
    noupgrade = "arm_u0commander",
    comshooter = "armcom",
    decoystart = "arm_decoy_commander",
    capturethebase = "arm_base",
    nincom = "arm_nincommander",
	plain = "arm_scommander",
}

local core_start_unit = {
    autoupgrade = "core_commander",
    halfupgrade = "core_u2commander",
    fullupgrade = "core_u4commander",
    noupgrade = "core_u0commander",
    comshooter = "corcom",
    decoystart = "core_decoy_commander",
    capturethebase = "core_base",
    nincom = "core_nincommander",
	plain = "core_scommander",
}

-- Maps sideName (as specified in side data) to table of start units.
local start_unit_table = {
    arm = arm_start_unit,
    core = core_start_unit,
}

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local modOptions = Spring.GetModOptions()

local coopMode = tonumber(modOptions.mo_coop) or 0
local commType = modOptions.commander

--[[
local enabled = tonumber(modOptions.mo_coop) or 0
if enabled ~= 0 then
    commType = "zeroupgrade"
end
]]--

--  Always use manual upgrade com when no modoptions present. Reason: easier for testing.
if not commType then
    commType = "noupgrade"
end


local function GetStartUnit(teamID)

	local defaultStartUnit = spGetTeamRulesParam(teamID, startUnitParamName)
	
	if (Spring.GetModOptions() or {}).commander == 'choose' and defaultStartUnit then
		return defaultStartUnit
	else	
		local side = select(5, Spring.GetTeamInfo(teamID))
		if (side == "") then
			-- startscript didn't specify a side for this team
			local sidedata = Spring.GetSideData()
			if (sidedata and #sidedata > 0) then
				side = sidedata[1 + teamID % #sidedata].sideName
			end
		end
		local startUnit
		if start_unit_table[side] then
			-- Arm or Core.
			startUnit = start_unit_table[side][commType]
		else
			-- Unknown side.
			startUnit = Spring.GetSideData(side)
		end
		spSetTeamRulesParam(teamID, startUnitParamName, UnitDefNames[startUnit].id)
		return startUnit
	end
end

local function SpawnStartUnit(teamID)
	local startUnit = GetStartUnit(teamID)
	if (startUnit and startUnit ~= "") then
		-- spawn the specified start unit
		local x,y,z = Spring.GetTeamStartPosition(teamID)
		-- snap to 16x16 grid
		x, z = 16*math.floor((x+8)/16), 16*math.floor((z+8)/16)
		y = Spring.GetGroundHeight(x, z)
		-- facing toward map center
		local facing=math.abs(Game.mapSizeX/2 - x) > math.abs(Game.mapSizeZ/2 - z)
			and ((x>Game.mapSizeX/2) and "west" or "east")
			or ((z>Game.mapSizeZ/2) and "north" or "south")
		local commanderID = Spring.CreateUnit(startUnit, x, y, z, facing, teamID)
		Spring.GiveOrderToUnit(commanderID, CMD.MOVE_STATE, { 0 }, {})
		
		-- set start resources, either from mod options or custom team keys
		local teamOptions = select(7, Spring.GetTeamInfo(teamID))
		local m = teamOptions.startmetal  or modOptions.startmetal  or 1000
		local e = teamOptions.startenergy or modOptions.startenergy or 1000

		if (m and tonumber(m) ~= 0) then
			Spring.SetUnitResourcing(commanderID, "m", 0)
			Spring.SetTeamResource(teamID, "m", 0)
			Spring.AddTeamResource(teamID, "m", tonumber(m))
		end
		
		if (e and tonumber(e) ~= 0) then
			Spring.SetUnitResourcing(commanderID, "e", 0)
			Spring.SetTeamResource(teamID, "e", 0)
			Spring.AddTeamResource(teamID, "e", tonumber(e))
		end
	
	end
end

function gadget:GameStart()
	local excludeTeams = {}

	if (coopMode == 1) then
		for _, teamID in ipairs(Spring.GetTeamList()) do
			local playerCount = 0
			for _, playerID in ipairs(Spring.GetPlayerList(teamID)) do
				if not select(3,Spring.GetPlayerInfo(playerID)) then
					playerCount = playerCount + 1
				end
			end
			if (playerCount > 1) then excludeTeams[teamID] = true end
		end
	
	end

    -- spawn start units
    local gaiaTeamID = Spring.GetGaiaTeamID()
    local teams = Spring.GetTeamList()
	for i = 1,#teams do
        local teamID = teams[i]
        -- don't spawn a start unit for the Gaia team
        if (teamID ~= gaiaTeamID) and (not excludeTeams[teamID]) then
			Spring.SetTeamResource(teamID, "ms", 0)
			Spring.SetTeamResource(teamID, "es", 0)
            SpawnStartUnit(teamID)
        end
    end
end

function gadget:Initialize()
	--disable start unit spawn for mission mode, or use default behaviour if error in mission script
    if modOptions.mission and modOptions.mission ~= "" then 
		local mission = "Missions/" .. modOptions.mission .. ".lua"
		if VFS.FileExists(mission) then
			local spawnData = include(mission)
			if spawnData.map == Game.mapName then
				gadgetHandler:RemoveGadget()
				return
			end
		end
	end
end