--several other ways do not work because:
--when UnitDestroyed() is called, Spring.GetUnitIsTransporting is already empty -> meh
--checking newDamage>health in UnitDamaged() does not work because UnitDamaged() does not trigger on selfdestruct -> meh
--with releaseHeld, on death of a transport UnitUnload is called before UnitDestroyed
--when UnitUnload is called due to transport death, Spring.GetUnitIsDead (transportID) is still false

function gadget:GetInfo()
  return {
    name      = "workaround for airtrans-com-death crash",
    desc      = "less crashing, hopefully",
    author    = "knorke",
    date      = "Dec 2011",
    license   = "horse has fallen over",
    layer     = -2,
    enabled   = true
  }
end

if (not gadgetHandler:IsSyncedCode()) then return end

transportedBy = {} -- [passengerID]  = transporterID

transporting = {} -- [transportID] = [pID]=true [pID2]=true


--function gadget:UnitDestroyed(unitID, unitDefID, teamID, attackerID, attackerDefID, attackerTeamID)
	--Spring.Echo ("unit " .. unitID .. " kaputt")
--end

toKill = {} -- [frame] [1]=unitID
currentFrame = 0
function gadget:GameFrame (f)
	currentFrame = f
	if (toKill[f]) then
		for i,u in pairs (toKill[f]) do
			Spring.Echo ("delay killing " ..i)
			--***FIXME: copy more closely how units normaly die in destroyed transports: normal explosion + no wreck
			--Spring.AddUnitDamage (i, math.huge) --this makes it use normal death epxlo but leave wreck. -> would change balance
			Spring.DestroyUnit (i, true, true) --this uses selfd explo but no wreck. good compromise?
		end
	toKill[f] = nil
	end
end

function gadget:UnitUnloaded(unitID, unitDefID, teamID, transportID)
	--Spring.Echo ("unloaded " .. unitID .. " from a DEAD transport")
	if (Spring.GetUnitSelfDTime (transportID) > 0 or Spring.GetUnitHealth (transportID) < 0) then	--***not sure what happens with transports with selfDestructTime=0
		local transDefID =Spring.GetUnitDefID(transportID)
		local transDef = UnitDefs [transDefID]
		--if (not transDef) then Spring.Echo ("transDef = nil!!!!!!!!!!!!!!!!!!!!!!!!") end
		if (not (transDef.customParams and transDef.customParams.releaseheld)) then
			--Spring.Echo ("BOOM PASSENGER IS DEAD!")
			--Spring.AddUnitDamage (unitID, math.huge)	--simply doing this here will still result in crash
			if (not toKill[currentFrame+1]) then toKill[currentFrame+1] = {} end
			toKill[currentFrame+1][unitID] = true			
		end		
	end
end