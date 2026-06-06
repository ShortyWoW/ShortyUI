local V2_TAG_NUMBER = 4

---@param v2Rankings ProviderProfileV2Rankings
---@return ProviderProfileSpec
local function convertRankingsToV1Format(v2Rankings, difficultyId, sizeId)
	---@type ProviderProfileSpec
	local v1Rankings = {}
	v1Rankings.progress = v2Rankings.progressKilled
	v1Rankings.total = v2Rankings.progressPossible
	v1Rankings.average = v2Rankings.bestAverage
	v1Rankings.spec = v2Rankings.spec
	v1Rankings.asp = v2Rankings.allStarPoints
	v1Rankings.rank = v2Rankings.allStarRank
	v1Rankings.difficulty = difficultyId
	v1Rankings.size = sizeId

	v1Rankings.encounters = {}
	for id, encounter in pairs(v2Rankings.encountersById) do
		v1Rankings.encounters[id] = {
			kills = encounter.kills,
			best = encounter.best,
		}
	end

	return v1Rankings
end

---Convert a v2 profile to a v1 profile
---@param v2 ProviderProfileV2
---@return ProviderProfile
local function convertToV1Format(v2)
	---@type ProviderProfile
	local v1 = {}
	v1.subscriber = v2.isSubscriber
	v1.perSpec = {}

	if v2.summary ~= nil then
		v1.progress = v2.summary.progressKilled
		v1.total = v2.summary.progressPossible
		v1.totalKillCount = v2.summary.totalKills
		v1.difficulty = v2.summary.difficultyId
		v1.size = v2.summary.sizeId
	else
		local bestSection = v2.sections[1]
		v1.progress = bestSection.anySpecRankings.progressKilled
		v1.total = bestSection.anySpecRankings.progressPossible
		v1.average = bestSection.anySpecRankings.bestAverage
		v1.totalKillCount = bestSection.totalKills
		v1.difficulty = bestSection.difficultyId
		v1.size = bestSection.sizeId
		v1.anySpec = convertRankingsToV1Format(bestSection.anySpecRankings, bestSection.difficultyId, bestSection.sizeId)
		for i, rankings in pairs(bestSection.perSpecRankings) do
			v1.perSpec[i] = convertRankingsToV1Format(rankings, bestSection.difficultyId, bestSection.sizeId)
		end
		v1.encounters = v1.anySpec.encounters
	end

	if v2.mainCharacter ~= nil then
		v1.mainCharacter = {}
		v1.mainCharacter.spec = v2.mainCharacter.spec
		v1.mainCharacter.average = v2.mainCharacter.bestAverage
		v1.mainCharacter.difficulty = v2.mainCharacter.difficultyId
		v1.mainCharacter.size = v2.mainCharacter.sizeId
		v1.mainCharacter.progress = v2.mainCharacter.progressKilled
		v1.mainCharacter.total = v2.mainCharacter.progressPossible
		v1.mainCharacter.totalKillCount = v2.mainCharacter.totalKills
	end

	return v1
end

---Parse a single set of rankings from `state`
---@param decoder BitDecoder
---@param state ParseState
---@param lookup table<number, string>
---@return ProviderProfileV2Rankings
local function parseRankings(decoder, state, lookup)
	---@type ProviderProfileV2Rankings
	local result = {}
	result.spec = decoder.decodeString(state, lookup)
	result.progressKilled = decoder.decodeInteger(state, 1)
	result.progressPossible = decoder.decodeInteger(state, 1)
	result.bestAverage = decoder.decodePercentileFixed(state)
	result.allStarRank = decoder.decodeInteger(state, 3)
	result.allStarPoints = decoder.decodeInteger(state, 2)

	local encounterCount = decoder.decodeInteger(state, 1)
	result.encountersById = {}
	for i = 1, encounterCount do
		local id = decoder.decodeInteger(state, 4)
		local kills = decoder.decodeInteger(state, 2)
		local best = decoder.decodeInteger(state, 1)
		local isHidden = decoder.decodeBoolean(state)

		result.encountersById[id] = { kills = kills, best = best, isHidden = isHidden }
	end

	return result
end

---Parse a binary-encoded data string into a provider profile
---@param decoder BitDecoder
---@param content string
---@param lookup table<number, string>
---@param formatVersion number
---@return ProviderProfile|ProviderProfileV2|nil
local function parse(decoder, content, lookup, formatVersion) -- luacheck: ignore 211
	-- For backwards compatibility. The existing addon will leave this as nil
	-- so we know to use the old format. The new addon will specify this as 2.
	formatVersion = formatVersion or 1
	if formatVersion > 2 then
		return nil
	end

	---@type ParseState
	local state = { content = content, position = 1 }

	local tag = decoder.decodeInteger(state, 1)
	if tag ~= V2_TAG_NUMBER then
		return nil
	end

	---@type ProviderProfileV2
	local result = {}
	result.isSubscriber = decoder.decodeBoolean(state)
	result.summary = nil
	result.sections = {}
	result.progressOnly = false
	result.mainCharacter = nil

	local sectionsCount = decoder.decodeInteger(state, 1)
	if sectionsCount == 0 then
		---@type ProviderProfileV2Summary
		local summary = {}
		summary.zoneId = decoder.decodeInteger(state, 2)
		summary.difficultyId = decoder.decodeInteger(state, 1)
		summary.sizeId = decoder.decodeInteger(state, 1)
		summary.progressKilled = decoder.decodeInteger(state, 1)
		summary.progressPossible = decoder.decodeInteger(state, 1)
		summary.totalKills = decoder.decodeInteger(state, 2)

		result.summary = summary
	else
		for i = 1, sectionsCount do
			---@type ProviderProfileV2Section
			local section = {}
			section.zoneId = decoder.decodeInteger(state, 2)
			section.difficultyId = decoder.decodeInteger(state, 1)
			section.sizeId = decoder.decodeInteger(state, 1)
			section.partitionId = decoder.decodeInteger(state, 1) - 128
			section.totalKills = decoder.decodeInteger(state, 2)

			local specCount = decoder.decodeInteger(state, 1)
			section.anySpecRankings = parseRankings(decoder, state, lookup)

			section.perSpecRankings = {}
			for j = 1, specCount - 1 do
				local specRankings = parseRankings(decoder, state, lookup)
				table.insert(section.perSpecRankings, specRankings)
			end

			table.insert(result.sections, section)
		end
	end

	local hasMainCharacter = decoder.decodeBoolean(state)
	if hasMainCharacter then
		---@type ProviderProfileV2MainCharacter
		local mainCharacter = {}
		mainCharacter.zoneId = decoder.decodeInteger(state, 2)
		mainCharacter.difficultyId = decoder.decodeInteger(state, 1)
		mainCharacter.sizeId = decoder.decodeInteger(state, 1)
		mainCharacter.progressKilled = decoder.decodeInteger(state, 1)
		mainCharacter.progressPossible = decoder.decodeInteger(state, 1)
		mainCharacter.totalKills = decoder.decodeInteger(state, 2)
		mainCharacter.spec = decoder.decodeString(state, lookup)
		mainCharacter.bestAverage = decoder.decodePercentileFixed(state)

		result.mainCharacter = mainCharacter
	end

	local progressOnly = decoder.decodeBoolean(state)
	result.progressOnly = progressOnly

	if formatVersion == 1 then
		return convertToV1Format(result)
	end

	return result
end
--- the utf8 global is not available, so we polyfill utf8.offset so we can correctly find prefixes of utf8 strings
---@param str string
---@param index number
---@return number|nil
local function Utf8Offset(str, index)
	local len = #str

	if index <= 0 or index > len then
		return nil -- Out of bounds
	end

	-- Move forward to the nth character
	local count = 0
	for i = 1, len do
		local byte = string.byte(str, i)
		local isContinuationByte = byte >= 128 and byte < 192
		if not isContinuationByte then
			count = count + 1
			if count == index then
				return i
			end
		end
	end

	return nil -- If the nth character is not found
end

---@param table table<string, string> raw data table with character name prefixes as keys
---@param length number the number of complete characters to include in the prefix
---@return fun(characterName: string):string|nil getChunk function to retrieve a character chunk by prefix using a complete character name
local function getChunkLookup(table, length)
	return function(characterName)
		local startOfNextCharacter = Utf8Offset(characterName, length + 1)

		local prefix
		if startOfNextCharacter == nil then
			prefix = characterName
		else
			prefix = string.sub(characterName, 1, startOfNextCharacter - 1)
		end

		return table[prefix]
	end
end

local lookup = {'Warlock-Demonology','Priest-Discipline','Priest-Holy','Unknown-Unknown','DeathKnight-Unholy','DeathKnight-Frost','Paladin-Retribution','Hunter-Marksmanship','Hunter-BeastMastery','Mage-Frost','DemonHunter-Devourer','DemonHunter-Vengeance','Druid-Feral','Paladin-Holy','Monk-Brewmaster','Druid-Restoration','Warrior-Protection','Hunter-Survival','Shaman-Elemental','Shaman-Restoration','Druid-Balance','Rogue-Subtlety','Rogue-Assassination','Evoker-Preservation','Evoker-Devastation','Warrior-Fury','Paladin-Protection','Evoker-Augmentation','Monk-Mistweaver','Warrior-Arms','Shaman-Enhancement','Mage-Arcane','DeathKnight-Blood','Priest-Shadow','Rogue-Outlaw','Monk-Windwalker',}
local provider = {region='US',realm='Ysondre',name='US',type='daily',zone=46,date='2026-06-05',data={Ak='Akari:BAAALgADCgEJAQAAAA==.',
Al='Alex:BAAALgADCgMJAwAAAA==.',
An='Angalius:BAAALgAECgkJDQAAAA==.',
Ap='Apathy:BAAALgAECgIJBAAAAA==.',
Ar='Aralid:BAABLgAECn8YAAIBAAcJUyOTHwBhAgdoDAAAAwBfAGkMAAADAFoAawwAAAMATwBqDAAAAgBgAGwMAAABAFQA6gwAAAgAYQBuDAAABABeAAEABwlTI5MfAGECB2gMAAADAF8AaQwAAAMAWgBrDAAAAwBPAGoMAAACAGAAbAwAAAEAVADqDAAACABhAG4MAAAEAF4AAAA=.Ariadné:BAABLgAECn8YAAMCAAgJFx2XEABcAghoDAAABABHAGkMAAADAEYAawwAAAMATgBqDAAAAwBcAGwMAAACAEgAbQwAAAEASQDqDAAABQBDAG4MAAADAEYAAgAICRcdlxAAXAIIaAwAAAMARwBpDAAAAwBGAGsMAAADAE4AagwAAAMAXABsDAAAAgBIAG0MAAABAEkA6gwAAAQAQwBuDAAAAwBGAAMAAglMCfNzAFgAAmgMAAABACsA6gwAAAEABAAAAA==.Artasha:BAAALgADCgIJAwAAAA==.',
Ba='Badassmf:BAAALgADCgIJAgAAAA==.',
Be='Bearlover:BAAALgAECgcJDwAAAA==.Beau:BAAALgAECgQJBAAAAA==.Belal:BAAALgADCgIJAgAAAA==.',
Bi='Birdflù:BAAALgADCgUJBQAAAA==.Biscuits:BAAALgADCgYJBgAAAA==.',
Bo='Bomi:BAAALgAECgIJAwAAAA==.Boogiesera:BAAALgADCgQJBAABLgAECgcJEwAEAAAAAA==.Bootles:BAAALgAECgcJEwAAAA==.Bowl:BAAALgAECgMJAwAAAA==.',
Br='Brad:BAABLgAFFH8FAAMFAAQJ2R8VbgAUAQRoDAAAAQBdAGoMAAABAC4AbAwAAAEAWgDqDAAAAgA8AAUABAnZHxVuABQBBGgMAAABAF0AagwAAAEALgBsDAAAAQBaAOoMAAABADwABgABCTMH9iQAOgAB6gwAAAEAEgAAAA==.Brewslee:BAAALgAECgkJAQAAAA==.',
Bu='Bulltastich:BAAALgADCgUJBgABLgADCgcJBwAEAAAAAA==.Bullwings:BAAALgAECgEJAQAAAA==.Buttholemu:BAAALgADCgYJBgAAAA==.',
Ca='Calanthe:BAAALgAECgYJBwAAAA==.',
Ch='Charrend:BAABLgAECn8sAAIHAAgJRwWnvAAAAQhoDAAACAATAGkMAAAHABEAawwAAAcADQBqDAAABgAXAGwMAAAGABIAbQwAAAEACQDqDAAABgAJAG4MAAADAAYABwAICUcFp7wAAAEIaAwAAAgAEwBpDAAABwARAGsMAAAHAA0AagwAAAYAFwBsDAAABgASAG0MAAABAAkA6gwAAAYACQBuDAAAAwAGAAAA.',
Cl='Clutchmedic:BAABLgAFFH8IAAMIAAUJEQw2EAAwAQVoDAAAAwA7AGkMAAACABMAawwAAAEAFABqDAAAAQAaAOoMAAABABcACAAECX8NNhAAMAEEaAwAAAMAOwBrDAAAAQAUAGoMAAABABoA6gwAAAEAFwAJAAEJxwc3JgBVAAFpDAAAAgATAAAA.',
Co='Codus:BAAALgAECgEJAQAAAA==.Completed:BAAALgADCgUJBQAAAA==.',
Cp='Cptloveme:BAABLgAECn8eAAIKAAYJaRpolwCmAQZoDAAABgBWAGkMAAAGAEUAawwAAAUANgBqDAAABQAxAGwMAAADADoA6gwAAAUARAAKAAYJaRpolwCmAQZoDAAABgBWAGkMAAAGAEUAawwAAAUANgBqDAAABQAxAGwMAAADADoA6gwAAAUARAAAAA==.',
Cr='Crazon:BAAALgAECgMJAwAAAA==.Cropduster:BAACLgAFFH8WAAILAAQJ0g9eRQAKAQRoDAAABwAkAGkMAAAFACsAawwAAAQADQDqDAAABgBFAAsABAnSD15FAAoBBGgMAAAHACQAaQwAAAUAKwBrDAAABAANAOoMAAAGAEUALgAECn8fAAMLAAkJHRfDNQAgAgALAAgJ3hnDNQAgAgAMAAEJ2QPXMgAsAAAAAA==.Crushed:BAAALgADCgMJAwABLgAECggJIgABAPkcAA==.',
Ct='Cthulhu:BAACLgAFFH8kAAIBAAUJiB8+LAB3AQVoDAAACQBMAGkMAAAHAFoAawwAAAgASwBqDAAAAwAeAOoMAAAJAFEAAQAFCYgfPiwAdwEFaAwAAAkATABpDAAABwBaAGsMAAAIAEsAagwAAAMAHgDqDAAACQBRAC4ABAp/MAACAQAICeAgsx0ApAIAAQAICeAgsx0ApAIAAAA=.',
Cu='Cursedpriest:BAAALgADCgUJBQAAAA==.',
Da='Dad:BAAALgAECgEJAgAAAA==.Darling:BAAALgAECgMJAwABLgAFFAQJDQANAPUZAA==.Darner:BAAALgAECgQJBAAAAA==.',
De='Delnarei:BAAALgADCgEJAQAAAA==.Demise:BAAALgADCgYJCgABLgAFFAMJBAAEAAAAAA==.Destiniemonk:BAAALgAFFAEJAQABLgAFFAUJEwAOAGQlAA==.Deviant:BAAALgADCgkJDwAAAA==.',
Di='Diosito:BAAALgAECgYJCwAAAA==.',
Do='Dolo:BAAALgADCgIJAgAAAA==.Doloni:BAAALgAECgUJDAAAAA==.Doomd:BAEALgAECgcJEQAAAA==.Doomdtrooper:BAEALgAECgcJDgABLgAECgcJEQAEAAAAAA==.Dotti:BAAALgADCgkJCQABLgAECgkJMgAJALsOAA==.Dotts:BAABLgAECn8dAAIBAAcJ9RIAdABNAQdoDAAABQBGAGkMAAAFADwAawwAAAUAIgBqDAAABABUAGwMAAAEACsAbQwAAAEAFgDqDAAABQA9AAEABwn1EgB0AE0BB2gMAAAFAEYAaQwAAAUAPABrDAAABQAiAGoMAAAEAFQAbAwAAAQAKwBtDAAAAQAWAOoMAAAFAD0AAAA=.',
Dr='Drewied:BAAALgADCgEJAQAAAA==.Drfinger:BAAALgAECgMJAwABLgAECgkJLQAPAOslAA==.Droodorei:BAAALgADCggJJAAAAA==.',
Du='Durianz:BAAALgAECgYJCwAAAA==.',
Dw='Dwnloadedchi:BAAALgAECggJDQAAAA==.Dwnloadedski:BAAALgAECgcJEgAAAA==.',
Eg='Eggenan:BAAALgAECgUJAQAAAA==.',
Ei='Eiskält:BAABLgAECn8eAAIKAAgJbgcCnQA6AQhoDAAABQAIAGkMAAAEABIAawwAAAQAEwBqDAAABAAMAGwMAAAFAAYAbQwAAAMAEgDqDAAAAwAmAG4MAAACABYACgAICW4HAp0AOgEIaAwAAAUACABpDAAABAASAGsMAAAEABMAagwAAAQADABsDAAABQAGAG0MAAADABIA6gwAAAMAJgBuDAAAAgAWAAAA.',
El='Ellay:BAABLgAECn8iAAIQAAkJ/w8SMgDMAQloDAAABQBFAGkMAAAFAC0AawwAAAUAKgBqDAAABAAfAGwMAAADADMAbQwAAAIAMADqDAAABwAtAG4MAAACAA0AbwwAAAEAFAAQAAkJ/w8SMgDMAQloDAAABQBFAGkMAAAFAC0AawwAAAUAKgBqDAAABAAfAGwMAAADADMAbQwAAAIAMADqDAAABwAtAG4MAAACAA0AbwwAAAEAFAAAAA==.',
Em='Emofumu:BAAALgADCgYJBgABLgAFFAMJBQARAN0hAA==.',
En='Endrin:BAAALgAECgYJDAAAAA==.',
Ew='Eww:BAEBLgAECn9DAAISAAkJnh/qAwDvAgloDAAACgBZAGkMAAAJAFAAawwAAAkAVwBqDAAACQBVAGwMAAAJAFwAbQwAAAUAJQDqDAAACABZAG4MAAAFAGIAbwwAAAMARwASAAkJnh/qAwDvAgloDAAACgBZAGkMAAAJAFAAawwAAAkAVwBqDAAACQBVAGwMAAAJAFwAbQwAAAUAJQDqDAAACABZAG4MAAAFAGIAbwwAAAMARwAAAA==.',
Ez='Ezzak:BAAALgADCgQJBAAAAA==.',
Fe='Felfirefoxxo:BAAALgAFFAIJAgAAAA==.Felldeeds:BAABLgAECn8kAAIQAAgJlSUQBQBfAwhoDAAABwBhAGkMAAAHAGMAawwAAAYAYQBqDAAAAgBgAGwMAAADAGEAbQwAAAIAWwDqDAAACABhAG4MAAABAFoAEAAICZUlEAUAXwMIaAwAAAcAYQBpDAAABwBjAGsMAAAGAGEAagwAAAIAYABsDAAAAwBhAG0MAAACAFsA6gwAAAgAYQBuDAAAAQBaAAAA.Fellphist:BAAALgAECgUJBgABLgAECggJJAAQAJUlAA==.Fellshock:BAAALgAECgYJCwABLgAECggJJAAQAJUlAA==.Felthazzar:BAAALgAECgYJBgAAAA==.Fent:BAACLgAFFH8UAAMTAAYJUxHLFQBVAQZoDAAABQApAGkMAAAFACkAawwAAAMAKwBqDAAAAQAkAGwMAAABAEEA6gwAAAUAHQATAAYJUxHLFQBVAQZoDAAABQApAGkMAAAFACkAawwAAAIAKwBqDAAAAQAkAGwMAAABAEEA6gwAAAQAHQAUAAIJ2AkdYgBsAAJrDAAAAQAcAOoMAAABABUALgAECn8sAAMTAAkJiByAGABRAgATAAcJayCAGABRAgAUAAkJQRfxIAAZAgAAAA==.Fey:BAAALgAECgUJCgAAAA==.',
Fi='Fingerblastn:BAAALgADCgcJBwABLgAECgkJLQAPAOslAA==.Fingerr:BAABLgAECn8tAAIPAAkJ6yXBAABuAwloDAAABwBjAGkMAAAGAGMAawwAAAYAYQBqDAAABgBjAGwMAAAFAGMAbQwAAAIAVADqDAAABwBjAG4MAAAEAGMAbwwAAAIAYQAPAAkJ6yXBAABuAwloDAAABwBjAGkMAAAGAGMAawwAAAYAYQBqDAAABgBjAGwMAAAFAGMAbQwAAAIAVADqDAAABwBjAG4MAAAEAGMAbwwAAAIAYQAAAA==.Finneagan:BAAALgAECgEJAQAAAA==.',
Fl='Flinkorandus:BAAALgAECgEJAgABLgAECgcJGAABAFMjAA==.Flokki:BAAALgAECgcJDwAAAA==.',
Fo='Foxxowo:BAABLgAFFH8FAAIQAAMJogXERgCUAANoDAAAAgATAGkMAAACABAA6gwAAAEABgAQAAMJogXERgCUAANoDAAAAgATAGkMAAACABAA6gwAAAEABgAAAA==.',
Fr='Froztbane:BAEALgAECgcJDwABLgAECgkJSwALAM4gAA==.Froztbanshee:BAEBLgAECn9LAAILAAkJziC1DgDDAgloDAAACwBbAGkMAAALAFkAawwAAAsAVgBqDAAACwBSAGwMAAAIAFwAbQwAAAUAWADqDAAACwBeAG4MAAAFAFEAbwwAAAIALwALAAkJziC1DgDDAgloDAAACwBbAGkMAAALAFkAawwAAAsAVgBqDAAACwBSAGwMAAAIAFwAbQwAAAUAWADqDAAACwBeAG4MAAAFAFEAbwwAAAIALwAAAA==.',
Fy='Fynger:BAAALgAECgUJCgABLgAECgkJLQAPAOslAA==.',
Gh='Ghats:BAAALgAECgEJAQAAAA==.Ghuss:BAAALgAECgcJBwAAAA==.',
Gl='Glass:BAAALgAECgcJEgAAAA==.',
Go='Gogo:BAAALgAECgYJDAAAAA==.',
Gr='Grimzyn:BAACLgAFFH8PAAIFAAUJvxTzYgAlAQVoDAAABABZAGkMAAAEACwAawwAAAMAJQBqDAAAAQAEAOoMAAADACkABQAFCb8U82IAJQEFaAwAAAQAWQBpDAAABAAsAGsMAAADACUAagwAAAEABADqDAAAAwApAC4ABAp/HAACBQAICWMcwDYAXAIABQAICWMcwDYAXAIAAAA=.Grudge:BAABLgAECn83AAMFAAkJNBJ/SQDdAQloDAAACAAtAGkMAAAHADcAawwAAAcAMABqDAAABwAtAGwMAAAHADYAbQwAAAUAHwDqDAAACAAuAG4MAAAFACwAbwwAAAEALgAFAAkJ8hB/SQDdAQloDAAABgAtAGkMAAAFADEAawwAAAUAHgBqDAAABQAqAGwMAAAFADYAbQwAAAMAHwDqDAAABgAsAG4MAAADACwAbwwAAAEALgAGAAgJTBC/BQDVAQhoDAAAAgAhAGkMAAACADcAawwAAAIAMABqDAAAAgAtAGwMAAACACkAbQwAAAIAGADqDAAAAgAuAG4MAAACACoAAAA=.',
Ha='Haircules:BAAALgAECgUJCwAAAA==.Harrowhark:BAACLgAFFH8QAAIFAAQJ2R7XNQB5AQRoDAAABQBZAGkMAAAEAFYAawwAAAIAMADqDAAABQBaAAUABAnZHtc1AHkBBGgMAAAFAFkAaQwAAAQAVgBrDAAAAgAwAOoMAAAFAFoALgAECn8vAAMFAAgJgCQhEQDbAgAFAAgJgCQhEQDbAgAGAAEJ3BoELwBMAAAAAA==.',
He='Herambae:BAAALgADCgYJBgAAAA==.Herculesátan:BAAALgADCgYJCAAAAA==.',
Ho='Hornstache:BAAALgADCgEJAQAAAA==.',
Hy='Hyacinth:BAABLgAECn8sAAIVAAkJhBZlFAAiAgloDAAABgBGAGkMAAAGAEEAawwAAAYALQBqDAAABQAnAGwMAAAEAEQAbQwAAAIANgDqDAAABgBOAG4MAAAFACsAbwwAAAQAIgAVAAkJhBZlFAAiAgloDAAABgBGAGkMAAAGAEEAawwAAAYALQBqDAAABQAnAGwMAAAEAEQAbQwAAAIANgDqDAAABgBOAG4MAAAFACsAbwwAAAQAIgAAAA==.Hyria:BAAALgADCgkJDwABLgAECgcJEwAEAAAAAA==.Hyun:BAAALgADCgYJBgAAAA==.',
Ia='Iamfinn:BAAALgAECgEJAQAAAA==.Iamomegafox:BAACLgAFFH8PAAIWAAQJgxkNFABYAQRoDAAABQBQAGkMAAAEACwAawwAAAEAKwDqDAAABQBdABYABAmDGQ0UAFgBBGgMAAAFAFAAaQwAAAQALABrDAAAAQArAOoMAAAFAF0ALgAECn8xAAMWAAkJRhrVDwAjAgAWAAkJwhjVDwAjAgAXAAYJ8RfkCwBoAQAAAA==.',
Ig='Iggylock:BAAALgADCgYJBgAAAA==.Ignax:BAACLgAFFH8OAAMYAAYJZAh0EgBVAQZoDAAAAwAQAGkMAAADABAAawwAAAEAJgBqDAAAAQATAGwMAAABABMA6gwAAAUAEgAYAAYJZAh0EgBVAQZoDAAAAgAQAGkMAAADABAAawwAAAEAJgBqDAAAAQATAGwMAAABABMA6gwAAAUAEgAZAAEJWgUVCwBNAAFoDAAAAQANAC4ABAp/IQADGAAICRAVUBQAAQIAGAAICRAVUBQAAQIAGQAGCVYIXiUA+gAAAAA=.',
Im='Imomeganisha:BAAALgAECgQJBwABLgAFFAQJDwAWAIMZAA==.Imsparticus:BAABLgAECn8VAAMaAAYJxghKWwDXAAZoDAAABAAkAGkMAAAEAB0AawwAAAQAGABqDAAAAwAPAGwMAAACAAYA6gwAAAQADwAaAAYJxghKWwDXAAZoDAAAAwAkAGkMAAADAB0AawwAAAMAGABqDAAAAwAPAGwMAAACAAYA6gwAAAMADwARAAQJcAHROwBtAARoDAAAAQABAGkMAAABAAEAawwAAAEABwDqDAAAAQAEAAAA.',
Io='Ionias:BAABLgAECn8jAAQbAAkJ5Bb7FwBXAQloDAAABQAsAGkMAAAFAFAAawwAAAUASABqDAAABAAXAGwMAAAEADYAbQwAAAMAYQDqDAAABQBGAG4MAAADABYAbwwAAAEAGwAbAAYJERn7FwBXAQZoDAAAAQAsAGkMAAABAFAAawwAAAEASABqDAAAAQAXAGwMAAABADYA6gwAAAEARgAOAAgJuQgUOgBVAQhoDAAABAAPAGkMAAAEABMAawwAAAQAEwBqDAAAAwARAGwMAAADABoAbQwAAAMAFADqDAAABAA1AG4MAAACAAUABwACCeMJSTMBZwACbgwAAAEAFgBvDAAAAQAbAAAA.',
Ja='Jackblack:BAAALgAECgIJBAABLgAFFAQJFgALANIPAA==.Jaquelius:BAAALgAECgUJDgAAAA==.Jaz:BAAALgAECgIJAgAAAA==.',
Jo='Joeworgen:BAAALgAECgEJAQAAAA==.Johadan:BAABLgAECn8dAAIHAAgJ5wcvnAAxAQhoDAAABAARAGkMAAAEABIAawwAAAQAFwBqDAAAAwATAGwMAAAEABEA6gwAAAcADgBuDAAAAgAdAG8MAAABABMABwAICecHL5wAMQEIaAwAAAQAEQBpDAAABAASAGsMAAAEABcAagwAAAMAEwBsDAAABAARAOoMAAAHAA4AbgwAAAIAHQBvDAAAAQATAAAA.',
Ka='Kade:BAAALgADCgEJAgAAAA==.Kaelx:BAAALgAECgQJCAAAAA==.Kafizz:BAABLgAECn8fAAIBAAkJWxXKPgASAgloDAAABQAsAGkMAAAGAFoAawwAAAYAUABqDAAAAwBOAGwMAAADAEUAbQwAAAEAHwDqDAAAAwAsAG4MAAADADcAbwwAAAEAFgABAAkJWxXKPgASAgloDAAABQAsAGkMAAAGAFoAawwAAAYAUABqDAAAAwBOAGwMAAADAEUAbQwAAAEAHwDqDAAAAwAsAG4MAAADADcAbwwAAAEAFgAAAA==.Kagnara:BAAALgADCgUJBQABLgAFFAQJEAAFANkeAA==.Karoh:BAAALgADCgEJAQAAAA==.',
Ke='Keely:BAAALgAECgUJCwAAAA==.Keolmont:BAAALgADCgEJAQAAAA==.',
Ki='Kinla:BAAALgAECgQJBAAAAA==.Kirakitsune:BAAALgAECgEJAQAAAA==.Kireag:BAAALgADCgIJAgAAAA==.',
Ko='Kooppa:BAAALgADCgQJBAAAAA==.',
Ku='Kuromigirl:BAABLgAECn8YAAILAAcJwRQRWgBsAQdoDAAAAwAvAGkMAAADADgAawwAAAMAMgBqDAAAAgAwAGwMAAABADQA6gwAAAgATABuDAAABAAjAAsABwnBFBFaAGwBB2gMAAADAC8AaQwAAAMAOABrDAAAAwAyAGoMAAACADAAbAwAAAEANADqDAAACABMAG4MAAAEACMAAAA=.',
La='Labchimpette:BAAALgAECgYJDgAAAA==.Lagerthä:BAAALgAECgcJEwABLgAECgkJJQAQAFgaAA==.',
Li='Link:BAAALgAECgYJBgAAAA==.Lione:BAABLgAECn8UAAMQAAcJ8hi0LwDtAQdoDAAABAAyAGkMAAADAFUAawwAAAMAUABqDAAAAgBUAGwMAAABAEQA6gwAAAUAOQBuDAAAAgAUABAABwnyGLQvAO0BB2gMAAADADIAaQwAAAMAVQBrDAAAAwBQAGoMAAACAFQAbAwAAAEARADqDAAABAA5AG4MAAACABQAFQACCWAI8XUATQACaAwAAAEAGgDqDAAAAQAQAAAA.Lith:BAACLgAFFH8HAAIYAAMJgRTnDQD9AANoDAAAAwBEAGsMAAACABsA6gwAAAIAPQAYAAMJgRTnDQD9AANoDAAAAwBEAGsMAAACABsA6gwAAAIAPQAuAAQKfycAAxgACAmtGXsKADACABgACAmtGXsKADACABwACAlgEL4dANcBAAAA.Litterbocks:BAAALgAECgMJBAAAAA==.Littlepriest:BAAALgADCgEJAQAAAA==.',
Ly='Lyzandra:BAAALgADCgYJCgAAAA==.',
['Lì']='Lìllyanna:BAABLgAECn8pAAIbAAkJbxM2DwDBAQloDAAABwA1AGkMAAAGADEAawwAAAYARABqDAAAAwAfAGwMAAADACQAbQwAAAIAGADqDAAACABDAG4MAAAEAD0AbwwAAAIAJAAbAAkJbxM2DwDBAQloDAAABwA1AGkMAAAGADEAawwAAAYARABqDAAAAwAfAGwMAAADACQAbQwAAAIAGADqDAAACABDAG4MAAAEAD0AbwwAAAIAJAAAAA==.',
Ma='Mailbox:BAAALgAECgYJBgABLgAFFAgJJAAOAA8iAA==.Malion:BAAALgAECgEJAQAAAA==.Malock:BAAALgADCgkJCQAAAA==.Mango:BAAALgAECgIJAwAAAA==.Matcha:BAABLgAECn8jAAIdAAkJjxwLCwDVAgloDAAABAA7AGkMAAAEAEkAawwAAAQAUABqDAAABABOAGwMAAADADsAbQwAAAIASQDqDAAABQBSAG4MAAAFAEkAbwwAAAQASwAdAAkJjxwLCwDVAgloDAAABAA7AGkMAAAEAEkAawwAAAQAUABqDAAABABOAGwMAAADADsAbQwAAAIASQDqDAAABQBSAG4MAAAFAEkAbwwAAAQASwAAAA==.Mauler:BAAALgAECgQJCAAAAA==.',
Me='Melinoë:BAAALgADCgUJBQAAAA==.Meowhunter:BAAALgAECgUJCwAAAA==.',
Mi='Miaraa:BAAALgAECgcJEAAAAA==.Minervå:BAAALgADCgMJAwAAAA==.',
Mo='Mogdor:BAABLgAECn8mAAMcAAkJvBkdEgBIAgloDAAABQBaAGkMAAAFAEsAawwAAAUAUQBqDAAABgBIAGwMAAAGAEoAbQwAAAIAQADqDAAABQBBAG4MAAADACAAbwwAAAEAKQAcAAkJvBkdEgBIAgloDAAABQBaAGkMAAAFAEsAawwAAAUAUQBqDAAABQBIAGwMAAAFAEoAbQwAAAIAQADqDAAABABBAG4MAAADACAAbwwAAAEAKQAZAAMJZBRuLAC4AANqDAAAAQAvAGwMAAABADkA6gwAAAEALgAAAA==.Moonpeach:BAABLgAECn8eAAIQAAgJ7Q4zQACGAQhoDAAABgBNAGkMAAAGABcAawwAAAYAQgBqDAAAAwApAGwMAAACACcAbQwAAAEAEADqDAAABQAaAG4MAAABAA4AEAAICe0OM0AAhgEIaAwAAAYATQBpDAAABgAXAGsMAAAGAEIAagwAAAMAKQBsDAAAAgAnAG0MAAABABAA6gwAAAUAGgBuDAAAAQAOAAAA.Motex:BAABLgAECn8eAAIWAAgJ/AKFMwBvAQhoDAAABAAIAGkMAAAEAAgAawwAAAQADQBqDAAABAAJAGwMAAAEAAkAbQwAAAMABQDqDAAABAAFAG4MAAADAAIAFgAICfwChTMAbwEIaAwAAAQACABpDAAABAAIAGsMAAAEAA0AagwAAAQACQBsDAAABAAJAG0MAAADAAUA6gwAAAQABQBuDAAAAwACAAAA.',
Mu='Murgold:BAAALgAECgcJCwAAAA==.',
Na='Naturebug:BAAALgAECgYJCgAAAA==.',
Ne='Neature:BAAALgAFFAEJAwABLgAFFAQJFgALANIPAA==.Necrolyte:BAAALgAECgEJAQABLgAFFAUJJAABAIgfAA==.Ned:BAECLgAFFH8UAAIaAAUJDyWMDACOAQVoDAAABQBcAGkMAAAFAGMAawwAAAQAXwBqDAAAAgBPAOoMAAAEAFwAGgAFCQ8ljAwAjgEFaAwAAAUAXABpDAAABQBjAGsMAAAEAF8AagwAAAIATwDqDAAABABcAC4ABAp/TwADGgAJCR0m7gAAeAMAGgAJCR0m7gAAeAMAHgAECWUkhg8AowEAAS4ABRQGCRMAHQALJgA=.Netre:BAAALgAECgYJEQAAAA==.',
Ni='Nimbus:BAAALgAFFAMJAgABLgAFFAgJHgAcAPIbAA==.Ninax:BAAALgAECgYJCgAAAA==.',
Ny='Nylian:BAAALgAECgQJCgAAAA==.',
Ob='Obamasmama:BAAALgAFFAIJBAAAAA==.',
Oc='Octomore:BAAALgAFFAEJAgAAAA==.',
Ol='Oldmantom:BAAALgADCgYJBgAAAA==.',
Or='Ormgorg:BAABLgAECn8VAAIfAAcJ9R0ADgDBAQdoDAAAAwBTAGkMAAADAF0AawwAAAMATQBqDAAAAwBXAGwMAAACAE8A6gwAAAUAUgBuDAAAAgAqAB8ABwn1HQAOAMEBB2gMAAADAFMAaQwAAAMAXQBrDAAAAwBNAGoMAAADAFcAbAwAAAIATwDqDAAABQBSAG4MAAACACoAAAA=.Orpheus:BAABLgAECn9JAAQUAAkJRCLvBABaAwloDAAACgBSAGkMAAAKAFwAawwAAAoAYQBqDAAACQBfAGwMAAAIAFoAbQwAAAUAVwDqDAAACQBNAG4MAAAHAEwAbwwAAAUAWAAUAAkJRCLvBABaAwloDAAABwBSAGkMAAAHAFwAawwAAAcAYQBqDAAACABfAGwMAAAHAFoAbQwAAAUAVwDqDAAACABNAG4MAAAHAEwAbwwAAAUAWAATAAUJ7hcOSgD7AAVoDAAAAgBOAGkMAAACADEAawwAAAIANABqDAAAAQBLAGwMAAABAEEAHwAECTsNSCIAzgAEaAwAAAEAJgBpDAAAAQAkAGsMAAABABYA6gwAAAEAJQAAAA==.',
Oz='Oza:BAAALgAECgMJBgAAAA==.',
Pa='Pandamoniium:BAAALgAECgcJDQABLgAFFAUJEwAKAGwcAA==.Pandamonk:BAACLgAFFH8YAAIPAAYJ2yVXBQAhAgZoDAAABgBjAGkMAAAGAGMAawwAAAQAWwBqDAAAAQBbAGwMAAABAGEA6gwAAAYAYQAPAAYJ2yVXBQAhAgZoDAAABgBjAGkMAAAGAGMAawwAAAQAWwBqDAAAAQBbAGwMAAABAGEA6gwAAAYAYQAuAAQKfzoAAg8ACQmYJUwBAFkDAA8ACQmYJUwBAFkDAAAA.',
Pe='Percy:BAEBLgAECn8bAAIgAAcJCxBeBgBLAQdoDAAABgAqAGkMAAAEADIAawwAAAQAMABqDAAABABJAGwMAAAEACAAbQwAAAEAEwDqDAAABAA1ACAABwkLEF4GAEsBB2gMAAAGACoAaQwAAAQAMgBrDAAABAAwAGoMAAAEAEkAbAwAAAQAIABtDAAAAQATAOoMAAAEADUAAAA=.',
Pi='Pickleswag:BAAALgAECgMJAwAAAA==.',
Pr='Preservation:BAAALgAECgMJAwAAAA==.',
Ra='Raastamon:BAAALgADCgEJAQAAAA==.Raekitty:BAABLgAECn8XAAIQAAgJgR6SFACRAghoDAAABABdAGkMAAAEAGAAawwAAAQAYQBqDAAAAwBQAGwMAAADAFsAbQwAAAEAHQDqDAAAAwBVAG4MAAABADIAEAAICYEekhQAkQIIaAwAAAQAXQBpDAAABABgAGsMAAAEAGEAagwAAAMAUABsDAAAAwBbAG0MAAABAB0A6gwAAAMAVQBuDAAAAQAyAAAA.Rama:BAAALgAECgMJBQABLgAECgYJGQAKAPQcAA==.Ramminass:BAAALgADCgEJAQABLgAFFAQJEAAYABshAA==.Rawrkevin:BAAALgADCgYJBgABLgAFFAQJEAAYABshAA==.',
Re='Redrover:BAAALgADCggJDgAAAA==.Reia:BAAALgADCgcJBwAAAA==.',
Rh='Rhara:BAAALgADCgYJEgAAAA==.Rhoem:BAACLgAFFH8JAAIGAAIJOwxhGQCQAAJoDAAABQAnAGkMAAAEABYABgACCTsMYRkAkAACaAwAAAUAJwBpDAAABAAWAC4ABAp/KQADBgAJCUAdsQUA1wEABgAICcwfsQUA1wEAIQAHCQIYSBcAngEAAAA=.',
Ri='Rin:BAEALgADCgMJAwABLgAECgkJLwAdAFciAA==.',
Ro='Roger:BAABLgAECn8iAAMOAAcJJSOxDQCsAgdoDAAABwBhAGkMAAAHAF0AawwAAAYAWgBqDAAABgBYAGwMAAADAF8AbQwAAAEATwDqDAAABABVAA4ABwklI7ENAKwCB2gMAAAEAGEAaQwAAAYAXQBrDAAABQBaAGoMAAAFAFgAbAwAAAMAXwBtDAAAAQBPAOoMAAACAFUABwAFCSgN8/YAswAFaAwAAAMAJwBpDAAAAQAWAGsMAAABABIAagwAAAEALQDqDAAAAgA1AAAA.',
Ru='Rumor:BAACLgAFFH8iAAMXAAgJ+SAlAADGAghoDAAABQBjAGkMAAAHAGIAawwAAAYAUwBqDAAABABbAGwMAAACAFoAbQwAAAEAHQDqDAAACABaAG4MAAABAGEAFwAICfkgJQAAxgIIaAwAAAQAYwBpDAAABQBiAGsMAAAFAFMAagwAAAQAWwBsDAAAAgBaAG0MAAABAB0A6gwAAAYAWgBuDAAAAQBhABYABAmxGXUHAG0BBGgMAAABADoAaQwAAAIAWQBrDAAAAQA6AOoMAAACADgALgAECn85AAMXAAgJySacAQDdAgAWAAgJ0ySXCgDpAgAXAAgJlSacAQDdAgAAAA==.Run:BAAALgAECgEJAQAAAA==.',
Se='Secretgrace:BAAALgADCgQJBAABLgAECgcJFQAfAPUdAA==.Seed:BAABLgAECn8XAAMGAAkJxB2hAgDGAgloDAAABABVAGkMAAADAFgAawwAAAMATQBqDAAAAgBQAGwMAAADAFQAbQwAAAEAGwDqDAAAAwBWAG4MAAACAFoAbwwAAAIARgAGAAkJxB2hAgDGAgloDAAABABVAGkMAAADAFgAawwAAAMATQBqDAAAAgBQAGwMAAACAFQAbQwAAAEAGwDqDAAAAwBWAG4MAAACAFoAbwwAAAIARgAFAAEJgBLYVwE3AAFsDAAAAQAvAAAA.Senortickle:BAABLgAECn8XAAILAAcJWhWCVAB7AQdoDAAAAwBIAGkMAAAEADcAawwAAAUAKQBqDAAAAwAsAGwMAAAEAEYAbQwAAAEAIADqDAAAAwA4AAsABwlaFYJUAHsBB2gMAAADAEgAaQwAAAQANwBrDAAABQApAGoMAAADACwAbAwAAAQARgBtDAAAAQAgAOoMAAADADgAAAA=.',
Sh='Shadowmoone:BAABLgAECn8yAAIJAAkJuw7pPQDeAQloDAAACAAvAGkMAAAIAB0AawwAAAYAJQBqDAAABQAaAGwMAAAGACYAbQwAAAMAGADqDAAACQA6AG4MAAAEAC4AbwwAAAEAEgAJAAkJuw7pPQDeAQloDAAACAAvAGkMAAAIAB0AawwAAAYAJQBqDAAABQAaAGwMAAAGACYAbQwAAAMAGADqDAAACQA6AG4MAAAEAC4AbwwAAAEAEgAAAA==.Shaki:BAAALgAECgQJBwAAAA==.Shalendris:BAAALgAECgEJAQAAAA==.Shalestrasz:BAABLgAECn8XAAQZAAgJNQg0IQAjAQhoDAAAAwAIAGkMAAADABQAawwAAAMAGABqDAAAAwAJAGwMAAADABAAbQwAAAIACQDqDAAABAAyAG4MAAACABEAGQAICRcFNCEAIwEIaAwAAAMACABpDAAAAwAUAGsMAAADABgAagwAAAMACQBsDAAAAgAQAG0MAAABAAkA6gwAAAIACABuDAAAAQADABwAAwkWCn9rAIgAA20MAAABAAkA6gwAAAEAMgBuDAAAAQARABgAAglVAU1FAEYAAmwMAAABAAQA6gwAAAEAAgAAAA==.Shibal:BAAALgADCggJCAAAAA==.Shinedown:BAAALgADCgQJBAAAAA==.Shochu:BAAALgAECgcJEAAAAA==.',
Sl='Sloane:BAAALgADCgQJBAAAAA==.',
So='Soju:BAAALgAECgUJBQAAAA==.Somnera:BAAALgAECgEJAQABLgAECgcJFQAfAPUdAA==.Soyboymalfoy:BAABLgAECn8WAAIDAAgJxBNuIACwAQhoDAAABABFAGkMAAADAD4AawwAAAQAOABqDAAAAwAnAGwMAAACADQA6gwAAAMAPwBuDAAAAgApAG8MAAABABIAAwAICcQTbiAAsAEIaAwAAAQARQBpDAAAAwA+AGsMAAAEADgAagwAAAMAJwBsDAAAAgA0AOoMAAADAD8AbgwAAAIAKQBvDAAAAQASAAAA.',
Sp='Sp:BAACLgAFFH8bAAIDAAUJBB4hCQCcAQVoDAAACQBEAGkMAAAFAD8AawwAAAQAWgBqDAAAAgBCAOoMAAAHAGAAAwAFCQQeIQkAnAEFaAwAAAkARABpDAAABQA/AGsMAAAEAFoAagwAAAIAQgDqDAAABwBgAC4ABAp/RAADAwAICeIkywMARAMAAwAICeIkywMARAMAIgABCXkKFIIALwAAAAA=.',
St='Sterility:BAAALgAECgUJEAAAAA==.',
Sw='Switchfoot:BAACLgAFFH8LAAIjAAMJDR6lBgAQAQNoDAAABABcAGkMAAADADgA6gwAAAQAUQAjAAMJDR6lBgAQAQNoDAAABABcAGkMAAADADgA6gwAAAQAUQAuAAQKf0EAAyMACQlfItIAABEDACMACQlfItIAABEDABcAAQklE9sbAEkAAAAA.',
['Sï']='Sïeghart:BAAALgADCgUJBQAAAA==.',
Ta='Tallmanbeta:BAAALgAECggJDgAAAA==.',
Te='Tenzin:BAAALgADCgQJBAABLgAFFAUJJAABAIgfAA==.Tex:BAAALgADCgcJDgAAAA==.',
Ti='Timerunner:BAAALgADCgYJBgAAAA==.',
To='Totingtotems:BAAALgADCgcJDQAAAA==.Touchofdeath:BAABLgAECn8WAAIkAAcJ3As1OQA5AQdoDAAABAAeAGkMAAAEACUAawwAAAQAKQBqDAAAAwAfAGwMAAADACQAbQwAAAEACQDqDAAAAwAbACQABwncCzU5ADkBB2gMAAAEAB4AaQwAAAQAJQBrDAAABAApAGoMAAADAB8AbAwAAAMAJABtDAAAAQAJAOoMAAADABsAAAA=.',
Tu='Turdle:BAAALgAECgYJBgABLgAFFAQJDwAcAPkNAA==.',
Ug='Ughnga:BAAALgAECgMJAwABLgAECgcJHQABAPUSAA==.',
Va='Vandli:BAAALgAECgMJBAAAAA==.',
Ve='Velzard:BAAALgAECgYJEgAAAA==.Verti:BAAALgAECgYJCwAAAA==.Vexie:BAAALgAECgYJBgABLgAFFAQJEAAFANkeAA==.Veylan:BAAALgAECgEJAQAAAA==.',
Vi='Visona:BAAALgADCgQJBAAAAA==.',
Vo='Voíshara:BAAALgADCgUJCwAAAA==.',
['Vö']='Vöre:BAAALgAECgcJCgAAAA==.',
Wa='Wanagi:BAAALgADCgEJAQAAAA==.',
Wh='Whitessin:BAAALgAECgEJAQAAAA==.',
Wi='Wither:BAACLgAFFH8FAAIFAAQJMhF2FQBOAQRoDAAAAQAZAGkMAAABAE0AawwAAAEAIgDqDAAAAgAmAAUABAkyEXYVAE4BBGgMAAABABkAaQwAAAEATQBrDAAAAQAiAOoMAAACACYALgAECn8eAAIFAAgJXSKeNQBgAgAFAAgJXSKeNQBgAgABLgAFFAgJIgAXAPkgAA==.',
Wy='Wyspur:BAAALgADCgYJCgAAAA==.',
Yo='Yofoxxo:BAACLgAFFH8aAAIOAAgJ0RfTBQBLAghoDAAABQBJAGkMAAAEAFkAawwAAAQAUQBqDAAAAwBKAGwMAAABACkAbQwAAAEAIgDqDAAABwBGAG4MAAABABYADgAICdEX0wUASwIIaAwAAAUASQBpDAAABABZAGsMAAAEAFEAagwAAAMASgBsDAAAAQApAG0MAAABACIA6gwAAAcARgBuDAAAAQAWAC4ABAp/LgAEDgAICV0kPAQAKgMADgAICV0kPAQAKgMABwAFCQ0OoLQAGwEAGwACCYsIvD0ARwAAAAA=.',
Yu='Yulon:BAAALgAFFAEJAQABLgAFFAUJGwADAAQeAA==.',
Za='Zaraerivia:BAABLgAECn8eAAIJAAcJXAivigAdAQdoDAAABgAVAGkMAAAGABoAawwAAAcAFwBqDAAAAgAoAGwMAAAEABoAbQwAAAEACADqDAAABAAWAAkABwlcCK+KAB0BB2gMAAAGABUAaQwAAAYAGgBrDAAABwAXAGoMAAACACgAbAwAAAQAGgBtDAAAAQAIAOoMAAAEABYAAAA=.Zarlon:BAAALgAECgMJBwABLgAECgYJGQAKAPQcAA==.',
Ze='Zengriff:BAABLgAECn8rAAIPAAkJ1iKlAwANAwloDAAABgBbAGkMAAAGAGEAawwAAAYAVwBqDAAABgBiAGwMAAAGAF0AbQwAAAMATQDqDAAABgBhAG4MAAADAFgAbwwAAAEAUAAPAAkJ1iKlAwANAwloDAAABgBbAGkMAAAGAGEAawwAAAYAVwBqDAAABgBiAGwMAAAGAF0AbQwAAAMATQDqDAAABgBhAG4MAAADAFgAbwwAAAEAUAAAAA==.Zerena:BAAALgAECgYJBgAAAA==.',
Zh='Zhule:BAABLgAECn8rAAIJAAkJ1h5VHABwAgloDAAABgBSAGkMAAAGAEsAawwAAAYASgBqDAAABgBXAGwMAAAGAF8AbQwAAAMARgDqDAAABgBbAG4MAAADAFMAbwwAAAEAOgAJAAkJ1h5VHABwAgloDAAABgBSAGkMAAAGAEsAawwAAAYASgBqDAAABgBXAGwMAAAGAF8AbQwAAAMARgDqDAAABgBbAG4MAAADAFMAbwwAAAEAOgAAAA==.',
Zy='Zyklonbarbie:BAAALgAECgcJBwAAAA==.',
['År']='Årthás:BAAALgAECgIJAgAAAA==.',
['Ær']='Æres:BAAALgADCgEJAQAAAA==.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

provider.splitId = 0
provider.splitCount = 1
provider.splitType = 'none'

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end
