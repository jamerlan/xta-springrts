local versionNumber = "1.3"

function widget:GetInfo()
	return {
		name      = "Nuke Button",
		desc      = "[v" .. string.format("%s", versionNumber ) .. "] Displays Nuke Button",
		author    = "very_bad_soldier",
		date      = "July 19, 2009",
		license   = "GNU GPL v2",
		layer     = 0,
		enabled   = true
	}
end


-- CONFIGURATION
local debug = false		--generates debug message
local updateInt = 1 --seconds for the ::update loop
local baseFontSize = 14


local intConfig = {}
intConfig["fontSize"] = 12
intConfig["buttonSize"] = 25   --half the width
intConfig["defaultScreenResY"] = 1050 --do not change
intConfig["buttonCoords"] = {}
intConfig["buttonCoords"][1] = {}
intConfig["buttonCoords"][2] = {}
intConfig["buttonCoords"]["progress"] = {}
intConfig["mouseOver"] = false
intConfig["nextNuke"] = nil --unitID of nextNuketoFire
intConfig["leftClickTime"] = 0
intConfig["screenx"], intConfig["screeny"] = widgetHandler:GetViewSizes()
-- END OF CONFIG

-- Internal temp vars
local readyNukeCount = 0
local highProgress = -1
local lastTime
local nukeList = {}
local curUnitList


local config = {}
config["buttonXPer"] = 0.935
config["buttonYPer"] = 0.765


--Game Config ------------------------------------
local unitList = {}
unitList["BA"] = {} --initialize table
unitList["BA"]["armsilo"] = {}
unitList["BA"]["corsilo"] = {}

unitList["ADVBA"] = {} --initialize table
unitList["ADVBA"]["armsilo"] = {}
unitList["ADVBA"]["corsilo"] = {}
unitList["ADVBA"]["armtabi"] = {}
unitList["ADVBA"]["corflu"] = {}

unitList["CA"] = {} --initialize table
unitList["CA"]["armsilo"] = {}
unitList["CA"]["corsilo"] = {}

unitList["XTA"] = {} --initialize table
unitList["XTA"]["arm_retaliator"] = {}
unitList["XTA"]["core_silencer"] = {}

--End

local upper                 = string.upper
local floor                 = math.floor
local max					= math.max
local min					= math.min

local udefTab				= UnitDefs
local glColor               = gl.Color
local glDepthTest           = gl.DepthTest
local glTexture             = gl.Texture
local glTexEnv				= gl.TexEnv
local glLineWidth           = gl.LineWidth
local glPopMatrix           = gl.PopMatrix
local glPushMatrix          = gl.PushMatrix
local glTranslate           = gl.Translate
local glFeatureShape		= gl.FeatureShape
local spGetGameSeconds      = Spring.GetGameSeconds
local spGetMyPlayerID       = Spring.GetMyPlayerID
local spGetPlayerInfo       = Spring.GetPlayerInfo
local spGetAllFeatures		= Spring.GetAllFeatures
local spGetFeaturePosition  = Spring.GetFeaturePosition
local spGetFeatureDefID		= Spring.GetFeatureDefID
local spGetMyAllyTeamID		= Spring.GetMyAllyTeamID
local spGetFeatureAllyTeam	= Spring.GetFeatureAllyTeam
local spGetFeatureTeam		= Spring.GetFeatureTeam
local spGetUnitHealth 		= Spring.GetUnitHealth
local spGetFeatureHealth 	= Spring.GetFeatureHealth
local spGetFeatureResurrect = Spring.GetFeatureResurrect
local spGetPositionLosState = Spring.GetPositionLosState
local spGetUnitStockpile	= Spring.GetUnitStockpile
local spIsUnitAllied		= Spring.IsUnitAllied
local spGetUnitPosition     = Spring.GetUnitPosition
local spGetUnitHealth 	    = Spring.GetUnitHealth
local spEcho                = Spring.Echo
local spGetUnitDefID        = Spring.GetUnitDefID
local spGetTeamUnits 		= Spring.GetTeamUnits
local spGetMyTeamID			= Spring.GetMyTeamID
local spGetMouseState       = Spring.GetMouseState
local spGiveOrderToUnit 	= Spring.GiveOrderToUnit
local spSelectUnitArray 	= Spring.SelectUnitArray
local spGetGameSpeed		= Spring.GetGameSpeed
local spSetActiveCommand	= Spring.SetActiveCommand
local DrawGhostFeatures
local DrawGhostSites
local ScanFeatures
local DeleteGhostFeatures
local DeleteGhostSites
local ResetGl
local CheckSpecState
local printDebug


local GL_FILL				= GL.FILL
local GL_LINE_LOOP          = GL.LINE_LOOP
local GL_TRIANGLE_STRIP 	= GL_TRIANGLE_STRIP
local glTexEnv				= gl.TexEnv
local glUnitShape			= gl.UnitShape
local glFeatureShape		= gl.FeatureShape
local glBeginEnd            = gl.BeginEnd
local glBillboard           = gl.Billboard
local glColor               = gl.Color
local glDepthTest           = gl.DepthTest
local glDrawGroundCircle    = gl.DrawGroundCircle
local glDrawGroundQuad      = gl.DrawGroundQuad
local glLineWidth           = gl.LineWidth
local glPopMatrix           = gl.PopMatrix
local glPushMatrix          = gl.PushMatrix
local glTexRect             = gl.TexRect
local glText                = gl.Text
local glTexture             = gl.Texture
local glTranslate           = gl.Translate
local glVertex              = gl.Vertex
local glAlphaTest			= gl.AlphaTest
local glBlending			= gl.Blending
local glRect				= gl.Rect


function widget:Initialize()
	ResizeButtonsToScreen()

	myPlayerID = spGetMyPlayerID() --spGetLocalTeamID()
	curModID = upper(Game.modShortName or "")
	
	if ( unitList[curModID] == nil ) then
		spEcho("<Nuke Icon> Unsupported Game, shutting down...")
		widgetHandler:RemoveWidget()
		return
	end
	
	curUnitList = unitList[curModID]
	
	--add all already existing nukes
	searchAndAddNukes()
end



function widget:Update()
	local timef = spGetGameSeconds()
	local time = floor(timef)

	-- update timers once every <updateInt> seconds
	if (time % updateInt == 0 and time ~= lastTime) then	
		lastTime = time
		--do update stuff:
		
		if ( CheckSpecState() == false ) then
			return false
		end

		highestLoadCount = 0
		readyNukeCount = 0
		highProgress = -1 --magic value: no active nukes
		for unitID, udefID in pairs( nukeList ) do
			local numStockpiled, numStockPQue, buildPercent = spGetUnitStockpile( unitID)
			
			if ( buildPercent == nil ) then
				--unit seems to be gone, delete it
				deleteNuke( unitID )
			else
				--save highest nuke stockpile progress
				readyNukeCount = readyNukeCount + numStockpiled
				if ( numStockPQue > 0 ) then
					highProgress = max( highProgress, buildPercent )
				end
				if ( numStockpiled > highestLoadCount ) then
					intConfig["nextNuke"] = unitID
					highestLoadCount = numStockpiled
				end
			end			
		end
		
		printDebug("HighProgress: " .. highProgress )
		
		updateProgressLayer()
	end
end

function updateProgressLayer()
	--progress layer	
	--fuck, replace half of the "buttonCurrentWidth" by "buttonCurrentHeight"
	intConfig["buttonCoords"]["progress"] = {}
	table.insert( intConfig["buttonCoords"]["progress"], { 0, 0 } )
	table.insert( intConfig["buttonCoords"]["progress"], { 0, intConfig["buttonCurrentWidth"] } )
	
	local localHP = highProgress
	localHP = max( 0, localHP )
	if ( localHP < 0.875 ) then
		table.insert( intConfig["buttonCoords"]["progress"], { -intConfig["buttonCurrentWidth"], intConfig["buttonCurrentWidth"] } )
	end
	if ( localHP < 0.625 ) then
		table.insert( intConfig["buttonCoords"]["progress"], { -intConfig["buttonCurrentWidth"], -intConfig["buttonCurrentWidth"] } )
	end
	if ( localHP < 0.375 ) then
		table.insert( intConfig["buttonCoords"]["progress"], { intConfig["buttonCurrentWidth"], -intConfig["buttonCurrentWidth"] } )
	end
	if ( localHP < 0.125 ) then
		table.insert( intConfig["buttonCoords"]["progress"], { intConfig["buttonCurrentWidth"], intConfig["buttonCurrentWidth"] } )
	end

	local x=0
	local y=0
	if ( localHP < 0.125 ) then
		y = intConfig["buttonCurrentWidth"]
		x = intConfig["buttonCurrentWidth"] * localHP / 0.125 
	elseif ( localHP < 0.375 ) then
		y = intConfig["buttonCurrentWidth"] - 2 * intConfig["buttonCurrentWidth"] * ( localHP - 0.125 ) / 0.25
		x = intConfig["buttonCurrentWidth"] 
	elseif ( localHP < 0.625 ) then
		y = -intConfig["buttonCurrentWidth"]
		x = intConfig["buttonCurrentWidth"] - 2 * intConfig["buttonCurrentWidth"] * ( localHP - 0.375 ) / 0.25
	elseif ( localHP < 0.875 ) then
		y = -intConfig["buttonCurrentWidth"] + 2* intConfig["buttonCurrentWidth"] * ( localHP - 0.625 ) / 0.25
		x = -intConfig["buttonCurrentWidth"]
	elseif ( localHP < 1.0 ) then
		y = intConfig["buttonCurrentWidth"]
		x = -intConfig["buttonCurrentWidth"] + intConfig["buttonCurrentWidth"] * ( localHP - 0.875 ) / 0.125 
	end
	table.insert( intConfig["buttonCoords"]["progress"], { x,y } )
end

function isMouseOver( mx, my )
	if ( mx > intConfig["buttonCoords"][1]["x"] and mx < intConfig["buttonCoords"][2]["x"] ) then
		if ( my < intConfig["buttonCoords"][1]["y"] and my > intConfig["buttonCoords"][2]["y"] ) then
			return true
		end
	end
	
	return false
end

-- needed for GetTooltip
function widget:IsAbove(x, y)
  if (not isMouseOver(x, y)) then
    return false
  end
  return true
end

function widget:GetTooltip(x, y)
	local text = ""
	if ( readyNukeCount > 0 ) then
		text = "Left-Click: Select next nuke\nDouble-Click: Aim next nuke"
	else
		text = "Loading Nuke: " .. string.format("%.2f", highProgress * 100) .. "%"
	end
	
	return text
end


function widget:DrawScreen()
	--printDebug("Count: " .. lastTime )
	local mx,my,lmb,mmb,rmb = spGetMouseState()
	intConfig["mouseOver"] = false
	
	if ( isMouseOver( mx, my ) ) then
		intConfig["mouseOver"] = true	
	end
	
	if ( highProgress > -1 or readyNukeCount > 0 ) then
		
		drawButton( )
	end
end

  
function widget:MousePress(x, y, button)
	if ( isMouseOver( x, y ) and readyNukeCount > 0 and button == 1 ) then
		local timeNow = spGetGameSeconds() 
		spSelectUnitArray( { intConfig["nextNuke"] } , false )
		
		local _,speedfac, _ = spGetGameSpeed()
		if ( timeNow < intConfig["leftClickTime"] + (0.5 * speedfac ) ) then
				--Spring.GiveOrderToUnit ( intConfig["nextNuke"], CMD.ATTACK, {500,500,500}, {} )
				spSetActiveCommand( "Attack" )
		end
		intConfig["leftClickTime"] = timeNow
		
		return true
	end
end


function widget:UnitDestroyed( unitID, unitDefID, unitTeam )
	deleteNuke( unitID )
end


function widget:UnitFinished( unitID, unitDefID, unitTeam )
	if ( unitTeam == spGetMyTeamID() ) then
		addPossibleNuke( unitID, unitDefID )
	end
end

function widget:UnitTaken( unitID, unitDefID, unitTeam, newTeam )
	
	if ( newTeam == spGetMyTeamID() ) then
		addPossibleNuke( unitID, unitDefID )
	end
end

--End OF Callins

function searchAndAddNukes()
	local allUnits = spGetTeamUnits(spGetMyTeamID())
	for _, unitID in pairs(allUnits) do
		local unitDefID = spGetUnitDefID(unitID)
		if ( unitDefID ~= nil ) then
			addPossibleNuke( unitID, unitDefID )
		end
	end
end

--delete nuke from list if we know it
function deleteNuke( unitID )
	if ( nukeList[unitID] ~= nil ) then
		nukeList[unitID] = nil
	end
end

function addPossibleNuke( unitID, unitDefID )
	local udef = UnitDefs[unitDefID]
	printDebug( "Name: " .. udef.name .. " UnitID: " .. unitID .. "udefid: " .. unitDefID  )

	if ( curUnitList[udef.name] ~= nil ) then
		printDebug("Nuke added!")
		nukeList[unitID] = udef.name
	end
end


local buttonConfig = {}
buttonConfig["borderColor"] = { 0, 0, 0, 1.0 }
buttonConfig["highlightColor"] = { 1.0, 0.0, 0.0, 1.0 }

function widget:ViewResize(viewSizeX, viewSizeY)
  intConfig["screenx"] = viewSizeX
  intConfig["screeny"] = viewSizeY

  borderizeButtons()
  ResizeButtonsToScreen()
end

function ResizeButtonsToScreen()
	--printDebug("Old Width:" .. ButtonWidthOrg .. " vsy: " .. vsy )
	intConfig["buttonCurrentWidth"] = ( intConfig["screeny"] / intConfig["defaultScreenResY"] ) * intConfig["buttonSize"]
	intConfig["buttonCurrentHeight"] = intConfig["buttonCurrentWidth"]
	
	intConfig["buttonCoords"][1]["x"] = intConfig["screenx"] * config["buttonXPer"] - intConfig["buttonCurrentWidth"]
	intConfig["buttonCoords"][1]["y"] = intConfig["screeny"] * config["buttonYPer"] + intConfig["buttonCurrentHeight"]

	intConfig["buttonCoords"][2]["x"] = intConfig["screenx"] * config["buttonXPer"] + intConfig["buttonCurrentWidth"]
	intConfig["buttonCoords"][2]["y"] = intConfig["screeny"] * config["buttonYPer"] - intConfig["buttonCurrentHeight"] 

	intConfig["fontSize"] = baseFontSize * ( intConfig["screeny"] / intConfig["defaultScreenResY"] )
	printDebug("Resizing: " .. intConfig["buttonCoords"][1]["x"] )
	
	updateProgressLayer()
end


function drawButton( )
	xmax = intConfig["buttonCoords"][1]["x"]
	ymax = intConfig["buttonCoords"][1]["y"]
	
	xmin = intConfig["buttonCoords"][2]["x"]
	ymin = intConfig["buttonCoords"][2]["y"]
	
	-- draw button body
	local bgColor = { 0.0, 0.0, 0.0 }

 -- draw colored background rectangle
	glColor( bgColor )
	glTexture(false)
	glTexRect( xmin, ymin, xmax, ymax )

 -- draw icon
	glColor( { 1.0, 1.0, 1.0} )
 
	glTexture( ":n:LuaUI/Images/nuke_button_64.png" )

	local texBorder = 0.75
	glTexRect( xmin, ymin, xmax, ymax, 0.0, texBorder, texBorder, 0.0 )
	glTexture(false)

	--draw the progress
	if ( highProgress >= 0 ) then
		DrawButtonProgress( intConfig["buttonCoords"][1]["x"] + intConfig["buttonCurrentWidth"], intConfig["buttonCoords"][1]["y"] - intConfig["buttonCurrentHeight"] )
	end
	
	-- draw the outline
	if ( intConfig["mouseOver"] and readyNukeCount > 0 ) then
		glColor(buttonConfig["highlightColor"])
	else
		glColor(buttonConfig["borderColor"])
	end
  
	local function Draw()
		glVertex(xmin, ymin)
		glVertex(xmax, ymin)
		glVertex(xmax, ymax)
		glVertex(xmin, ymax)
	end
  
	glBeginEnd(GL_LINE_LOOP, Draw)
	
	local centerx = xmin - intConfig["buttonCurrentWidth"]
	glColor(1,0,0, alpha or 1)
	glText( readyNukeCount, centerx, ymin + intConfig["buttonCurrentHeight"] + 0.2 * intConfig["buttonCurrentHeight"], intConfig["fontSize"], "nc")
	glColor(1,1,1,1)

	if ( highProgress >= 0 ) then
		glColor(1 - highProgress, 1 * highProgress,0, alpha or 1)
		glText( string.format( "%.0f", highProgress * 100 ) .. "%", centerx + 0.1 * intConfig["buttonCurrentWidth"], ymin + 0.2 * intConfig["buttonCurrentHeight"], 0.9 * intConfig["fontSize"], "nc")
		glColor(1,1,1,1)
	end
end




function DrawButtonProgress( xcenter, ycenter )
	glTexture(false)
	glColor( { .0, .0, .0, 0.7} )

	local function Draw()
		for id, point in pairs( intConfig["buttonCoords"]["progress"] ) do
			glVertex( xcenter + point[1], ycenter  + point[2] )
		end
	end
  
	glBeginEnd(GL.TRIANGLE_FAN, Draw)
end

--Commons
function ResetGl() 
	glColor( { 1.0, 1.0, 1.0, 1.0 } )
	glLineWidth( 1.0 )
	glDepthTest(false)
	glTexture(false)
end

function CheckSpecState()
	local playerID = spGetMyPlayerID()
	local _, _, spec, _, _, _, _, _ = spGetPlayerInfo(playerID)
		
	if ( spec == true ) then
		Spring.Log("widget", LOG.INFO, "<Nuke Icon> Spectator mode. Widget removed.")
		widgetHandler:RemoveWidget()
		return false
	end
	
	return true	
end

function printDebug( value )
	if ( debug ) then
		if ( type( value ) == "boolean" ) then
			if ( value == true ) then spEcho( "true" )
				else spEcho("false") end
		elseif ( type(value ) == "table" ) then
			spEcho("Dumping table:")
			for key,val in pairs(value) do 
				spEcho(key,val) 
			end
		else
			spEcho( value )
		end
	end
end



--SAVE / LOAD CONFIG FILE
function widget:GetConfigData()
	return config
end

function widget:SetConfigData(data) 
	if (data ~= nil) then
		config = data
		ResizeButtonsToScreen()
		borderizeButtons()
		ResizeButtonsToScreen()
	end
end
--END OF LOAD SAVE

--TWEAK MODE
local inTweakDrag = false
function widget:TweakMousePress(x,y,button)
	inTweakDrag = isMouseOver(x, y)	--allows button movement when mouse moves
	return inTweakDrag
end

function widget:TweakMouseMove(x,y,dx,dy,button)
	if ( inTweakDrag == false ) then
		return
	end
	
	printDebug("Tweak")

	config["buttonXPer"] = config["buttonXPer"] + ( dx / intConfig["screenx"] )
	config["buttonYPer"] = config["buttonYPer"] + ( dy / intConfig["screeny"] )

	borderizeButtons()
	
	ResizeButtonsToScreen()
end

function borderizeButtons()
	if ( config["buttonXPer"] * intConfig["screenx"] - intConfig["buttonCurrentWidth"] < 0.0 ) then
		config["buttonXPer"] = 0.0
	elseif( config["buttonXPer"] * intConfig["screenx"] + intConfig["buttonCurrentWidth"] > intConfig["screenx"] ) then
		config["buttonXPer"] = ( intConfig["screenx"] - intConfig["buttonCurrentWidth"] ) / intConfig["screenx"]
	end

	if ( config["buttonYPer"] * intConfig["screeny"] - intConfig["buttonCurrentHeight"] < 0.0 ) then
		config["buttonYPer"] = 0.0
	elseif( config["buttonYPer"] * intConfig["screeny"] + intConfig["buttonCurrentHeight"] > intConfig["screeny"] ) then
		config["buttonYPer"] = ( intConfig["screeny"] - intConfig["buttonCurrentHeight"] ) / intConfig["screeny"]
	end
end

function widget:TweakMouseRelease(x,y,button)
	inTweakDrag = false
end

function widget:TweakDrawScreen()
	drawButton()
	
	glColor(0.0,0.0,1.0,0.5)                                   
	glRect( intConfig["buttonCoords"][1]["x"], intConfig["buttonCoords"][2]["y"], intConfig["buttonCoords"][2]["x"], intConfig["buttonCoords"][1]["y"])
	glColor(1,1,1,1)
end

function widget:TweakIsAbove(x,y)
  return isMouseOver(x,y)
end

function widget:TweakGetTooltip(x,y)
  return 'Click and hold left mouse button\n'..
         'over button to drag\n'
end

--END OF TWEAK MODE