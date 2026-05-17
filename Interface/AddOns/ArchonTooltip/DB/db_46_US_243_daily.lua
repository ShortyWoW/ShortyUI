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

local lookup = {'Priest-Discipline','Priest-Holy','Unknown-Unknown','Paladin-Retribution','Hunter-Marksmanship','Hunter-BeastMastery','Mage-Frost','DemonHunter-Devourer','Warlock-Demonology','Evoker-Augmentation','Paladin-Holy','Monk-Brewmaster','Druid-Restoration','Warrior-Protection','Hunter-Survival','Shaman-Elemental','Shaman-Restoration','DeathKnight-Unholy','DeathKnight-Frost','Druid-Balance','Rogue-Subtlety','Rogue-Assassination','Evoker-Preservation','Evoker-Devastation','Warrior-Fury','Paladin-Protection','Monk-Mistweaver','Warrior-Arms','Shaman-Enhancement','Mage-Arcane','DeathKnight-Blood','Priest-Shadow','Rogue-Outlaw','Monk-Windwalker',}
local provider = {region='US',realm='Ysondre',name='US',type='daily',zone=46,date='2026-05-16',data={Al='Alex:BAAALgADCgMJAwAAAA==.',
An='Angalius:BAAALgAECgYJCgAAAA==.',
Ap='Apathy:BAAALgAECgEJAQAAAA==.',
Ar='Aralid:BAAALgAECgUJDwAAAA==.Ariadné:BAABLgAECn8XAAMBAAgJGR2kDwAgAghoDAAABABHAGkMAAADAEYAawwAAAMATgBqDAAAAwBcAGwMAAACAEgAbQwAAAEASQDqDAAABABDAG4MAAADAEYAAQAICRkdpA8AIAIIaAwAAAMARwBpDAAAAwBGAGsMAAADAE4AagwAAAMAXABsDAAAAgBIAG0MAAABAEkA6gwAAAMAQwBuDAAAAwBGAAIAAglMCfNzAFgAAmgMAAABACsA6gwAAAEABAAAAA==.Artasha:BAAALgADCgIJAwAAAA==.',
Ba='Badassmf:BAAALgADCgIJAgAAAA==.',
Be='Bearlover:BAAALgAECgcJDwAAAA==.Beau:BAAALgAECgQJBAAAAA==.Belal:BAAALgADCgIJAgAAAA==.',
Bi='Birdflù:BAAALgADCgUJBQAAAA==.Biscuits:BAAALgADCgYJBgAAAA==.',
Bo='Bomi:BAAALgAECgIJAwAAAA==.Boogiesera:BAAALgADCgQJBAABLgAECgcJEwADAAAAAA==.Bootles:BAAALgAECgcJEwAAAA==.Bowl:BAAALgADCgkJDAAAAA==.',
Br='Brewslee:BAAALgAECgkJAQAAAA==.',
Bu='Bulltastich:BAAALgADCgUJBgABLgADCgcJBwADAAAAAA==.Bullwings:BAAALgAECgEJAQAAAA==.Buttholemu:BAAALgADCgYJBgAAAA==.',
Ca='Calanthe:BAAALgAECgYJBwAAAA==.',
Ch='Charrend:BAABLgAECn8eAAIEAAgJJQWSkwACAQhoDAAABgATAGkMAAAFABEAawwAAAUADQBqDAAABAASAGwMAAAEABIAbQwAAAEACQDqDAAABAAJAG4MAAABAAQABAAICSUFkpMAAgEIaAwAAAYAEwBpDAAABQARAGsMAAAFAA0AagwAAAQAEgBsDAAABAASAG0MAAABAAkA6gwAAAQACQBuDAAAAQAEAAAA.',
Cl='Clutchmedic:BAABLgAFFH8IAAMFAAUJEQw2EAAwAQVoDAAAAwA7AGkMAAACABMAawwAAAEAFABqDAAAAQAaAOoMAAABABcABQAECX8NNhAAMAEEaAwAAAMAOwBrDAAAAQAUAGoMAAABABoA6gwAAAEAFwAGAAEJxwc3JgBVAAFpDAAAAgATAAAA.',
Co='Codus:BAAALgADCgEJAQAAAA==.Completed:BAAALgADCgUJBQAAAA==.',
Cp='Cptloveme:BAABLgAECn8eAAIHAAYJaRpolwCmAQZoDAAABgBWAGkMAAAGAEUAawwAAAUANgBqDAAABQAxAGwMAAADADoA6gwAAAUARAAHAAYJaRpolwCmAQZoDAAABgBWAGkMAAAGAEUAawwAAAUANgBqDAAABQAxAGwMAAADADoA6gwAAAUARAAAAA==.',
Cr='Crazon:BAAALgAECgMJAwAAAA==.Cropduster:BAACLgAFFH8JAAIIAAMJ1wz1QwDSAANoDAAABAAkAGkMAAACAAoA6gwAAAMANAAIAAMJ1wz1QwDSAANoDAAABAAkAGkMAAACAAoA6gwAAAMANAAuAAQKfx4AAggACAneGcM1ACACAAgACAneGcM1ACACAAAA.Crushed:BAAALgADCgMJAwABLgAECggJIgAJAPYcAA==.',
Ct='Cthulhu:BAACLgAFFH8WAAIJAAQJMhjfLAA3AQRoDAAABwBGAGkMAAAEADwAawwAAAUALgDqDAAABgBGAAkABAkyGN8sADcBBGgMAAAHAEYAaQwAAAQAPABrDAAABQAuAOoMAAAGAEYALgAECn8vAAIJAAgJzx6zHQCkAgAJAAgJzx6zHQCkAgAAAA==.',
Cu='Cursedpriest:BAAALgADCgUJBQAAAA==.',
Da='Dad:BAAALgAECgEJAgAAAA==.Darner:BAAALgAECgQJBAAAAA==.',
De='Delnarei:BAAALgADCgEJAQAAAA==.Demise:BAAALgADCgYJCgABLgAFFAMJBQAKAFYJAA==.Destiniemonk:BAAALgAECgYJCwABLgAFFAMJBwALAEYmAA==.Deviant:BAAALgADCgcJBwAAAA==.',
Do='Dolo:BAAALgADCgIJAgAAAA==.Doloni:BAAALgAECgUJDAAAAA==.Doomd:BAEALgAECgcJEQAAAA==.Doomdtrooper:BAEALgAECgcJDgABLgAECgcJEQADAAAAAA==.Dotti:BAAALgADCgkJCQABLgAECgcJGgAGAIcIAA==.Dotts:BAABLgAECn8dAAIJAAcJ8hIdXABOAQdoDAAABQBGAGkMAAAFADwAawwAAAUAIgBqDAAABABUAGwMAAAEACsAbQwAAAEAFQDqDAAABQA9AAkABwnyEh1cAE4BB2gMAAAFAEYAaQwAAAUAPABrDAAABQAiAGoMAAAEAFQAbAwAAAQAKwBtDAAAAQAVAOoMAAAFAD0AAAA=.',
Dr='Drewied:BAAALgADCgEJAQAAAA==.Drfinger:BAAALgAECgEJAQABLgAECggJJwAMAKslAA==.Droodorei:BAAALgADCggJJAAAAA==.',
Du='Durianz:BAAALgAECgYJCwAAAA==.',
Dw='Dwnloadedchi:BAAALgAECggJDQAAAA==.Dwnloadedski:BAAALgAECgcJEgAAAA==.',
Eg='Eggenan:BAAALgAECgEJAQAAAA==.',
Ei='Eiskält:BAAALgAECgUJDgAAAA==.',
El='Ellay:BAABLgAECn8XAAINAAcJJg8GPQBYAQdoDAAABABFAGkMAAAEAC0AawwAAAQAKgBqDAAAAwAfAGwMAAACABUAbQwAAAEADwDqDAAABQAtAA0ABwkmDwY9AFgBB2gMAAAEAEUAaQwAAAQALQBrDAAABAAqAGoMAAADAB8AbAwAAAIAFQBtDAAAAQAPAOoMAAAFAC0AAAA=.',
Em='Emofumu:BAAALgADCgYJBgABLgAECgkJHgAOAEMkAA==.',
En='Endrin:BAAALgAECgYJDAAAAA==.',
Ew='Eww:BAEBLgAECn8zAAIPAAkJCxaeCQBIAgloDAAACABJAGkMAAAHAE0AawwAAAcAVwBqDAAABwBRAGwMAAAGAC4AbQwAAAQAGADqDAAABwBRAG4MAAADACcAbwwAAAIAEwAPAAkJCxaeCQBIAgloDAAACABJAGkMAAAHAE0AawwAAAcAVwBqDAAABwBRAGwMAAAGAC4AbQwAAAQAGADqDAAABwBRAG4MAAADACcAbwwAAAIAEwAAAA==.',
Ez='Ezzak:BAAALgADCgQJBAAAAA==.',
Fe='Felfirefoxxo:BAAALgAFFAIJAgAAAA==.Felldeeds:BAABLgAECn8hAAINAAcJ0yU9CAD6AgdoDAAABwBhAGkMAAAHAGMAawwAAAYAYQBqDAAAAgBgAGwMAAADAGEAbQwAAAEAWQDqDAAABwBhAA0ABwnTJT0IAPoCB2gMAAAHAGEAaQwAAAcAYwBrDAAABgBhAGoMAAACAGAAbAwAAAMAYQBtDAAAAQBZAOoMAAAHAGEAAAA=.Fellshock:BAAALgAECgQJBQABLgAECgcJIQANANMlAA==.Felthazzar:BAAALgAECgYJBgAAAA==.Fent:BAACLgAFFH8NAAMQAAQJEw48FwAXAQRoDAAABAApAGkMAAAEACkAawwAAAIAHwDqDAAAAwAdABAABAkTDjwXABcBBGgMAAAEACkAaQwAAAQAKQBrDAAAAQAfAOoMAAADAB0AEQABCUQL61AAQAABawwAAAEAHAAuAAQKfywAAxEACQlAF/EgABkCABEACQlAF/EgABkCABAABwlrIBwWAOQBAAAA.Fey:BAAALgAECgEJAQAAAA==.',
Fi='Fingerblastn:BAAALgADCgcJBwABLgAECggJJwAMAKslAA==.Fingerr:BAABLgAECn8nAAIMAAgJqyUFAwD5AghoDAAABwBjAGkMAAAGAGMAawwAAAYAYQBqDAAABgBjAGwMAAAEAF8AbQwAAAEAVADqDAAABgBiAG4MAAADAGIADAAICaslBQMA+QIIaAwAAAcAYwBpDAAABgBjAGsMAAAGAGEAagwAAAYAYwBsDAAABABfAG0MAAABAFQA6gwAAAYAYgBuDAAAAwBiAAAA.Finneagan:BAAALgADCgEJAQAAAA==.',
Fl='Flinkorandus:BAAALgAECgEJAQABLgAECgUJDwADAAAAAA==.Flokki:BAAALgAECgcJDwAAAA==.',
Fo='Foxxowo:BAAALgAECgYJDAAAAA==.',
Fr='Froztbane:BAEALgAECgcJDwABLgAECgkJNgAIAK0gAA==.Froztbanshee:BAEBLgAECn82AAIIAAkJrSClDAAbAwloDAAACABbAGkMAAAIAFkAawwAAAgAVgBqDAAACABRAGwMAAAGAFwAbQwAAAQAVwDqDAAACABeAG4MAAADAFEAbwwAAAEALAAIAAkJrSClDAAbAwloDAAACABbAGkMAAAIAFkAawwAAAgAVgBqDAAACABRAGwMAAAGAFwAbQwAAAQAVwDqDAAACABeAG4MAAADAFEAbwwAAAEALAAAAA==.',
Gh='Ghats:BAAALgAECgEJAQAAAA==.Ghuss:BAAALgAECgcJBwAAAA==.',
Gl='Glass:BAAALgAECgUJCwAAAA==.',
Go='Gogo:BAAALgAECgYJDAAAAA==.',
Gr='Grimzyn:BAACLgAFFH8OAAISAAUJvxQDMwD5AAVoDAAABABZAGkMAAAEACwAawwAAAMAJQBqDAAAAQAEAOoMAAACACkAEgAFCb8UAzMA+QAFaAwAAAQAWQBpDAAABAAsAGsMAAADACUAagwAAAEABADqDAAAAgApAC4ABAp/HAACEgAICWMcwDYAXAIAEgAICWMcwDYAXAIAAAA=.Grudge:BAABLgAECn8mAAMTAAgJmxC/BQDVAQhoDAAABgAtAGkMAAAFADcAawwAAAUAMABqDAAABQAnAGwMAAAFACkAbQwAAAMAEADqDAAABgAuAG4MAAADACwAEwAICaUOvwUA1QEIaAwAAAEAIQBpDAAAAQA3AGsMAAABADAAagwAAAEAJwBsDAAAAQApAG0MAAABAA4A6gwAAAEALgBuDAAAAQAXABIACAmSDg5dAGoBCGgMAAAFAC0AaQwAAAQAMQBrDAAABAAeAGoMAAAEACAAbAwAAAQAHgBtDAAAAgAQAOoMAAAFACwAbgwAAAIALAAAAA==.',
Ha='Haircules:BAAALgAECgQJBwAAAA==.Harrowhark:BAACLgAFFH8FAAISAAMJDxtnWwCqAANoDAAAAgBIAGkMAAABADQA6gwAAAIAUgASAAMJDxtnWwCqAANoDAAAAgBIAGkMAAABADQA6gwAAAIAUgAuAAQKfyYAAhIACAmgIdkYAHACABIACAmgIdkYAHACAAAA.',
He='Herambae:BAAALgADCgYJBgAAAA==.Herculesátan:BAAALgADCgYJCAAAAA==.',
Ho='Hornstache:BAAALgADCgEJAQAAAA==.',
Hy='Hyacinth:BAABLgAECn8gAAIUAAkJLhI8FADeAQloDAAABQBGAGkMAAAFAEEAawwAAAUALQBqDAAABAAYAGwMAAADABwAbQwAAAEAIADqDAAABABAAG4MAAADACAAbwwAAAIAIQAUAAkJLhI8FADeAQloDAAABQBGAGkMAAAFAEEAawwAAAUALQBqDAAABAAYAGwMAAADABwAbQwAAAEAIADqDAAABABAAG4MAAADACAAbwwAAAIAIQAAAA==.Hyria:BAAALgADCgkJDwABLgAECgcJEwADAAAAAA==.Hyun:BAAALgADCgYJBgAAAA==.',
Ia='Iamfinn:BAAALgAECgEJAQAAAA==.Iamomegafox:BAACLgAFFH8FAAIVAAMJIgzpGgDlAANoDAAAAgBBAGkMAAABAAcA6gwAAAIAFAAVAAMJIgzpGgDlAANoDAAAAgBBAGkMAAABAAcA6gwAAAIAFAAuAAQKfy8AAxUACAnLGgIPAOwBABUACAkQGQIPAOwBABYABgnxF+QLAGgBAAAA.',
Ig='Ignax:BAACLgAFFH8MAAMXAAUJNAh1DwA9AQVoDAAAAwAQAGkMAAADABAAawwAAAEAJgBqDAAAAQATAOoMAAAEAA4AFwAFCTQIdQ8APQEFaAwAAAIAEABpDAAAAwAQAGsMAAABACYAagwAAAEAEwDqDAAABAAOABgAAQlaBRULAE0AAWgMAAABAA0ALgAECn8hAAMXAAgJEhVQFAABAgAXAAgJEhVQFAABAgAYAAYJVgheJQD6AAAAAA==.',
Im='Imomeganisha:BAAALgAECgQJBwABLgAFFAMJBQAVACIMAA==.Imsparticus:BAABLgAECn8VAAMZAAYJxggzRQDfAAZoDAAABAAkAGkMAAAEAB0AawwAAAQAGABqDAAAAwAPAGwMAAACAAYA6gwAAAQADwAZAAYJxggzRQDfAAZoDAAAAwAkAGkMAAADAB0AawwAAAMAGABqDAAAAwAPAGwMAAACAAYA6gwAAAMADwAOAAQJcAHROwBtAARoDAAAAQABAGkMAAABAAEAawwAAAEABwDqDAAAAQAEAAAA.',
Io='Ionias:BAABLgAECn8dAAQaAAkJ5Bb7FwBXAQloDAAABAAsAGkMAAAEAFAAawwAAAQASABqDAAAAwAXAGwMAAADADYAbQwAAAMAYQDqDAAABABGAG4MAAADABYAbwwAAAEAGwAaAAYJERn7FwBXAQZoDAAAAQAsAGkMAAABAFAAawwAAAEASABqDAAAAQAXAGwMAAABADYA6gwAAAEARgALAAgJagW6NAAwAQhoDAAAAwAPAGkMAAADABMAawwAAAMAEwBqDAAAAgARAGwMAAACAAcAbQwAAAMAFADqDAAAAwAEAG4MAAACAAUABAACCeMJcesAcwACbgwAAAEAFgBvDAAAAQAbAAAA.',
Ja='Jackblack:BAAALgAECgIJBAABLgAFFAMJCQAIANcMAA==.Jaquelius:BAAALgAECgUJDgAAAA==.',
Jo='Joeworgen:BAAALgAECgEJAQAAAA==.Johadan:BAABLgAECn8YAAIEAAYJMQfBqADeAAZoDAAABAARAGkMAAAEABIAawwAAAQAFwBqDAAAAwATAGwMAAAEABEA6gwAAAUADgAEAAYJMQfBqADeAAZoDAAABAARAGkMAAAEABIAawwAAAQAFwBqDAAAAwATAGwMAAAEABEA6gwAAAUADgAAAA==.',
Ka='Kade:BAAALgADCgEJAgAAAA==.Kaelx:BAAALgAECgEJBAAAAA==.Kafizz:BAABLgAECn8fAAIJAAkJWxXKPgASAgloDAAABQAsAGkMAAAGAFoAawwAAAYAUABqDAAAAwBOAGwMAAADAEUAbQwAAAEAHwDqDAAAAwAsAG4MAAADADcAbwwAAAEAFgAJAAkJWxXKPgASAgloDAAABQAsAGkMAAAGAFoAawwAAAYAUABqDAAAAwBOAGwMAAADAEUAbQwAAAEAHwDqDAAAAwAsAG4MAAADADcAbwwAAAEAFgAAAA==.Kagnara:BAAALgADCgUJBQAAAA==.',
Ke='Keely:BAAALgAECgQJBAAAAA==.Keolmont:BAAALgADCgEJAQAAAA==.',
Ki='Kinla:BAAALgAECgQJBAAAAA==.Kirakitsune:BAAALgADCgcJBwAAAA==.Kireag:BAAALgADCgIJAgAAAA==.',
Ko='Kooppa:BAAALgADCgQJBAAAAA==.',
Ku='Kuromigirl:BAAALgAECgUJDgAAAA==.',
La='Labchimpette:BAAALgAECgYJDgAAAA==.Lagerthä:BAAALgAECgcJDAABLgAECgkJIgANADgaAA==.',
Li='Link:BAAALgADCgcJBwAAAA==.Lione:BAABLgAECn8UAAMNAAcJ8hi0LwDtAQdoDAAABAAyAGkMAAADAFUAawwAAAMAUABqDAAAAgBUAGwMAAABAEQA6gwAAAUAOQBuDAAAAgAUAA0ABwnyGLQvAO0BB2gMAAADADIAaQwAAAMAVQBrDAAAAwBQAGoMAAACAFQAbAwAAAEARADqDAAABAA5AG4MAAACABQAFAACCWAIHFsAUgACaAwAAAEAGgDqDAAAAQAQAAAA.Lith:BAACLgAFFH8HAAIXAAMJgRTnDQD9AANoDAAAAwBEAGsMAAACABsA6gwAAAIAPQAXAAMJgRTnDQD9AANoDAAAAwBEAGsMAAACABsA6gwAAAIAPQAuAAQKfycAAxcACAmuGcgHADUCABcACAmuGcgHADUCAAoACAlgEL4dANcBAAAA.Litterbocks:BAAALgAECgMJBAAAAA==.Littlepriest:BAAALgADCgEJAQAAAA==.',
Ly='Lyzandra:BAAALgADCgYJCgAAAA==.',
['Lì']='Lìllyanna:BAABLgAECn8iAAIaAAkJ8BHlDACgAQloDAAABgA1AGkMAAAFADEAawwAAAUARABqDAAAAwAfAGwMAAADACQAbQwAAAIAGADqDAAABgAsAG4MAAADADUAbwwAAAEAJAAaAAkJ8BHlDACgAQloDAAABgA1AGkMAAAFADEAawwAAAUARABqDAAAAwAfAGwMAAADACQAbQwAAAIAGADqDAAABgAsAG4MAAADADUAbwwAAAEAJAAAAA==.',
Ma='Mailbox:BAAALgAECgEJAQABLgAFFAgJIQALAAwiAA==.Malock:BAAALgADCgkJCQAAAA==.Mango:BAAALgAECgEJAQAAAA==.Matcha:BAABLgAECn8XAAIbAAkJMRpRCgCTAgloDAAAAwA7AGkMAAADADgAawwAAAMAUABqDAAAAwBOAGwMAAACADEAbQwAAAEAOwDqDAAAAwBFAG4MAAADAEkAbwwAAAIASwAbAAkJMRpRCgCTAgloDAAAAwA7AGkMAAADADgAawwAAAMAUABqDAAAAwBOAGwMAAACADEAbQwAAAEAOwDqDAAAAwBFAG4MAAADAEkAbwwAAAIASwAAAA==.Mauler:BAAALgAECgQJCAAAAA==.',
Me='Melinoë:BAAALgADCgUJBQAAAA==.Meowhunter:BAAALgAECgUJCQAAAA==.',
Mi='Miaraa:BAAALgAECgcJEAAAAA==.Minervå:BAAALgADCgMJAwAAAA==.',
Mo='Mogdor:BAABLgAECn8gAAMKAAkJuRl8DABPAgloDAAABABaAGkMAAAEAEsAawwAAAQAUQBqDAAABQBIAGwMAAAFAEoAbQwAAAIAPwDqDAAABABBAG4MAAADACAAbwwAAAEAKQAKAAkJuRl8DABPAgloDAAABABaAGkMAAAEAEsAawwAAAQAUQBqDAAABABIAGwMAAAEAEoAbQwAAAIAPwDqDAAAAwBBAG4MAAADACAAbwwAAAEAKQAYAAMJZBRuLAC4AANqDAAAAQAvAGwMAAABADkA6gwAAAEALgAAAA==.Moonpeach:BAABLgAECn8bAAINAAYJ5RFAQgBAAQZoDAAABgBNAGkMAAAGABcAawwAAAYAQgBqDAAAAwApAGwMAAACACcA6gwAAAQAGgANAAYJ5RFAQgBAAQZoDAAABgBNAGkMAAAGABcAawwAAAYAQgBqDAAAAwApAGwMAAACACcA6gwAAAQAGgAAAA==.Motex:BAABLgAECn8eAAIVAAgJ8QKFMwBvAQhoDAAABAAIAGkMAAAEAAgAawwAAAQADQBqDAAABAAJAGwMAAAEAAkAbQwAAAMABQDqDAAABAAFAG4MAAADAAIAFQAICfEChTMAbwEIaAwAAAQACABpDAAABAAIAGsMAAAEAA0AagwAAAQACQBsDAAABAAJAG0MAAADAAUA6gwAAAQABQBuDAAAAwACAAAA.',
Na='Naturebug:BAAALgAECgYJCgAAAA==.',
Ne='Neature:BAAALgAECgEJAgABLgAFFAMJCQAIANcMAA==.Ned:BAECLgAFFH8PAAIZAAQJHSWdAwCxAQRoDAAABQBcAGkMAAAEAGMAawwAAAMAXwDqDAAAAwBcABkABAkdJZ0DALEBBGgMAAAFAFwAaQwAAAQAYwBrDAAAAwBfAOoMAAADAFwALgAECn9FAAMZAAgJ0yVWAwB5AwAZAAgJ0yVWAwB5AwAcAAQJZSSGDwCjAQABLgAFFAUJCgAbAHwjAA==.Netre:BAAALgAECgYJEQAAAA==.',
Ni='Nimbus:BAAALgAECggJCAABLgAFFAgJFgAKAEwWAA==.Ninax:BAAALgAECgYJCgAAAA==.',
Ny='Nylian:BAAALgAECgQJBQAAAA==.',
Ob='Obamasmama:BAAALgAECgcJEQAAAA==.',
Oc='Octomore:BAAALgAFFAEJAgAAAA==.',
Ol='Oldmantom:BAAALgADCgYJBgAAAA==.',
Or='Ormgorg:BAABLgAECn8UAAIdAAcJ9R1vCADbAQdoDAAAAwBTAGkMAAADAF0AawwAAAMATQBqDAAAAwBXAGwMAAACAE8A6gwAAAQAUgBuDAAAAgAqAB0ABwn1HW8IANsBB2gMAAADAFMAaQwAAAMAXQBrDAAAAwBNAGoMAAADAFcAbAwAAAIATwDqDAAABABSAG4MAAACACoAAAA=.Orpheus:BAABLgAECn81AAMRAAkJASFyAwBEAwloDAAACABSAGkMAAAIAFwAawwAAAgAYQBqDAAABwBfAGwMAAAGAFoAbQwAAAMAUQDqDAAABwBNAG4MAAAEAEwAbwwAAAIAQQARAAkJASFyAwBEAwloDAAABgBSAGkMAAAGAFwAawwAAAYAYQBqDAAABgBfAGwMAAAFAFoAbQwAAAMAUQDqDAAABwBNAG4MAAAEAEwAbwwAAAIAQQAQAAUJ7herNgAGAQVoDAAAAgBOAGkMAAACADEAawwAAAIANABqDAAAAQBLAGwMAAABAEEAAAA=.',
Oz='Oza:BAAALgAECgMJBgAAAA==.',
Pa='Pandamoniium:BAAALgAECgcJDQAAAA==.Pandamonk:BAACLgAFFH8RAAIMAAQJyyVVBQC+AQRoDAAABQBjAGkMAAAFAGMAawwAAAMAWwDqDAAABABhAAwABAnLJVUFAL4BBGgMAAAFAGMAaQwAAAUAYwBrDAAAAwBbAOoMAAAEAGEALgAECn86AAIMAAkJmCWxAABjAwAMAAkJmCWxAABjAwAAAA==.',
Pe='Percy:BAEBLgAECn8VAAIeAAcJzg1BBQBJAQdoDAAABQApAGkMAAADACgAawwAAAMALABqDAAAAwBJAGwMAAADACAAbQwAAAEAEwDqDAAAAwAhAB4ABwnODUEFAEkBB2gMAAAFACkAaQwAAAMAKABrDAAAAwAsAGoMAAADAEkAbAwAAAMAIABtDAAAAQATAOoMAAADACEAAAA=.',
Pi='Pickleswag:BAAALgAECgMJAwAAAA==.',
Pr='Preservation:BAAALgAECgMJAwAAAA==.',
Ra='Raastamon:BAAALgADCgEJAQAAAA==.Raekitty:BAABLgAECn8XAAINAAgJgR6SFACRAghoDAAABABdAGkMAAAEAGAAawwAAAQAYQBqDAAAAwBQAGwMAAADAFsAbQwAAAEAHQDqDAAAAwBVAG4MAAABADIADQAICYEekhQAkQIIaAwAAAQAXQBpDAAABABgAGsMAAAEAGEAagwAAAMAUABsDAAAAwBbAG0MAAABAB0A6gwAAAMAVQBuDAAAAQAyAAAA.Rama:BAAALgAECgMJBQABLgAECgYJGQAHAPQcAA==.',
Re='Redrover:BAAALgADCggJDgAAAA==.Reia:BAAALgADCgcJBwAAAA==.',
Rh='Rhara:BAAALgADCgYJEgAAAA==.Rhoem:BAABLgAECn8pAAMTAAkJQB2xBQDXAQloDAAABQBOAGkMAAAFAF0AawwAAAUAUgBqDAAABQBQAGwMAAAGAFQAbQwAAAMARADqDAAACABbAG4MAAADAEYAbwwAAAEAHQATAAgJzB+xBQDXAQhoDAAABABOAGkMAAAEAF0AawwAAAQAUgBqDAAABABQAGwMAAAFAFQAbQwAAAMARADqDAAACABbAG4MAAACAEYAHwAHCQIYrRIAbAEHaAwAAAEALQBpDAAAAQBJAGsMAAABAE8AagwAAAEARQBsDAAAAQBHAG4MAAABAEQAbwwAAAEAHQAAAA==.',
Ri='Rin:BAEALgADCgMJAwABLgAECggJIwAbADUhAA==.',
Ro='Roger:BAABLgAECn8XAAMLAAYJySGgEgAzAgZoDAAABQBhAGkMAAAFAF0AawwAAAQAWgBqDAAABABYAGwMAAACAF8A6gwAAAMANQALAAYJySGgEgAzAgZoDAAAAgBhAGkMAAAEAF0AawwAAAMAWgBqDAAAAwBYAGwMAAACAF8A6gwAAAEANQAEAAUJKA2DuQDEAAVoDAAAAwAnAGkMAAABABYAawwAAAEAEgBqDAAAAQAtAOoMAAACADUAAAA=.',
Ru='Rumor:BAACLgAFFH8bAAMWAAcJVh88AABFAgdoDAAAAwBjAGkMAAAGAGAAawwAAAUAUABqDAAAAwBYAGwMAAACAFoAbQwAAAEAHQDqDAAABwBUABYABwlWHzwAAEUCB2gMAAACAGMAaQwAAAQAYABrDAAABABQAGoMAAADAFgAbAwAAAIAWgBtDAAAAQAdAOoMAAAFAFQAFQAECbEZdQcAbQEEaAwAAAEAOgBpDAAAAgBZAGsMAAABADoA6gwAAAIAOAAuAAQKfzkAAxYACAnJJvsAAPACABYACAmVJvsAAPACABUACAnTJJcKAOkCAAAA.Run:BAAALgAECgEJAQAAAA==.',
Se='Secretgrace:BAAALgADCgQJBAABLgAECgcJFAAdAPUdAA==.Seed:BAAALgAECgkJBAAAAA==.Senortickle:BAAALgAECgcJEgAAAA==.',
Sh='Shadowmoone:BAABLgAECn8aAAIGAAcJhwgxZgAdAQdoDAAABQAnAGkMAAAFABcAawwAAAQAFgBqDAAAAwAWAGwMAAAEABEAbQwAAAEADQDqDAAABAAOAAYABwmHCDFmAB0BB2gMAAAFACcAaQwAAAUAFwBrDAAABAAWAGoMAAADABYAbAwAAAQAEQBtDAAAAQANAOoMAAAEAA4AAAA=.Shaki:BAAALgAECgQJBwAAAA==.Shalendris:BAAALgAECgEJAQAAAA==.Shalestrasz:BAABLgAECn8XAAQYAAgJNQg0IQAjAQhoDAAAAwAIAGkMAAADABQAawwAAAMAGABqDAAAAwAJAGwMAAADABAAbQwAAAIACQDqDAAABAAyAG4MAAACABEAGAAICRcFNCEAIwEIaAwAAAMACABpDAAAAwAUAGsMAAADABgAagwAAAMACQBsDAAAAgAQAG0MAAABAAkA6gwAAAIACABuDAAAAQADAAoAAwkVCphVAIEAA20MAAABAAkA6gwAAAEAMgBuDAAAAQARABcAAglVAU1FAEYAAmwMAAABAAQA6gwAAAEAAgAAAA==.Shibal:BAAALgADCggJCAAAAA==.Shochu:BAAALgAECgcJEAAAAA==.',
So='Soju:BAAALgAECgUJBQAAAA==.Somnera:BAAALgAECgEJAQABLgAECgcJFAAdAPUdAA==.Soyboymalfoy:BAABLgAECn8WAAICAAgJxBPJFwDHAQhoDAAABABFAGkMAAADAD4AawwAAAQAOABqDAAAAwAnAGwMAAACADQA6gwAAAMAPwBuDAAAAgApAG8MAAABABIAAgAICcQTyRcAxwEIaAwAAAQARQBpDAAAAwA+AGsMAAAEADgAagwAAAMAJwBsDAAAAgA0AOoMAAADAD8AbgwAAAIAKQBvDAAAAQASAAAA.',
Sp='Sp:BAACLgAFFH8SAAICAAQJCh/vBwBtAQRoDAAABwBEAGkMAAADAD8AawwAAAIAWgDqDAAABgBgAAIABAkKH+8HAG0BBGgMAAAHAEQAaQwAAAMAPwBrDAAAAgBaAOoMAAAGAGAALgAECn8yAAMCAAgJryO9AwAZAwACAAgJryO9AwAZAwAgAAEJeQq0ZQAvAAAAAA==.',
St='Sterility:BAAALgAECgUJEAAAAA==.',
Sw='Switchfoot:BAABLgAECn8rAAMhAAkJlSAFAQDRAgloDAAABgBaAGkMAAAGAFEAawwAAAYAXQBqDAAABwBKAGwMAAAEAFMAbQwAAAMAUADqDAAABwBWAG4MAAADAEgAbwwAAAEATwAhAAkJlSAFAQDRAgloDAAABgBaAGkMAAAGAFEAawwAAAYAXQBqDAAABwBKAGwMAAAEAFMAbQwAAAIAUADqDAAABwBWAG4MAAADAEgAbwwAAAEATwAWAAEJJRPbGwBJAAFtDAAAAQAxAAAA.',
['Sï']='Sïeghart:BAAALgADCgUJBQAAAA==.',
Te='Tenzin:BAAALgADCgQJBAABLgAFFAQJFgAJADIYAA==.Tex:BAAALgADCgcJDgAAAA==.',
Ti='Timerunner:BAAALgADCgYJBgAAAA==.',
To='Totingtotems:BAAALgADCgcJDQAAAA==.Touchofdeath:BAABLgAECn8WAAIiAAcJ3As1OQA5AQdoDAAABAAeAGkMAAAEACUAawwAAAQAKQBqDAAAAwAfAGwMAAADACQAbQwAAAEACQDqDAAAAwAbACIABwncCzU5ADkBB2gMAAAEAB4AaQwAAAQAJQBrDAAABAApAGoMAAADAB8AbAwAAAMAJABtDAAAAQAJAOoMAAADABsAAAA=.',
Ug='Ughnga:BAAALgAECgMJAwABLgAECgcJHQAJAPISAA==.',
Va='Vandli:BAAALgAECgMJBAAAAA==.',
Ve='Velzard:BAAALgAECgYJEgAAAA==.Verti:BAAALgAECgYJCwAAAA==.Veylan:BAAALgAECgEJAQAAAA==.',
Vi='Visona:BAAALgADCgMJAwAAAA==.',
Vo='Voíshara:BAAALgADCgUJCwAAAA==.',
['Vö']='Vöre:BAAALgAECgYJBwAAAA==.',
Wa='Wanagi:BAAALgADCgEJAQAAAA==.',
Wh='Whitessin:BAAALgADCgcJBwAAAA==.',
Wi='Wither:BAACLgAFFH8FAAISAAQJMhF2FQBOAQRoDAAAAQAZAGkMAAABAE0AawwAAAEAIgDqDAAAAgAmABIABAkyEXYVAE4BBGgMAAABABkAaQwAAAEATQBrDAAAAQAiAOoMAAACACYALgAECn8ZAAISAAgJXSKeNQBgAgASAAgJXSKeNQBgAgABLgAFFAcJGwAWAFYfAA==.',
Wy='Wyspur:BAAALgADCgYJCgAAAA==.',
Yo='Yofoxxo:BAACLgAFFH8UAAILAAcJoxnWAwCoAQdoDAAABABJAGkMAAADAFkAawwAAAMAUQBqDAAAAgBKAGwMAAABACkAbQwAAAEAIgDqDAAABgBAAAsABwmjGdYDAKgBB2gMAAAEAEkAaQwAAAMAWQBrDAAAAwBRAGoMAAACAEoAbAwAAAEAKQBtDAAAAQAiAOoMAAAGAEAALgAECn8uAAQLAAgJXSQ8BAAqAwALAAgJXSQ8BAAqAwAEAAUJDQ6gtAAbAQAaAAIJiwi8PQBHAAAAAA==.',
Yu='Yulon:BAAALgAECgYJDgABLgAFFAQJEgACAAofAA==.',
Za='Zaraerivia:BAAALgAECgYJDwAAAA==.Zarlon:BAAALgAECgMJBQABLgAECgYJGQAHAPQcAA==.',
Ze='Zengriff:BAABLgAECn8lAAIMAAkJ1SJAAgAVAwloDAAABQBbAGkMAAAFAGEAawwAAAUAVwBqDAAABQBiAGwMAAAFAF0AbQwAAAMATQDqDAAABQBhAG4MAAADAFgAbwwAAAEAUAAMAAkJ1SJAAgAVAwloDAAABQBbAGkMAAAFAGEAawwAAAUAVwBqDAAABQBiAGwMAAAFAF0AbQwAAAMATQDqDAAABQBhAG4MAAADAFgAbwwAAAEAUAAAAA==.Zerena:BAAALgAECgYJBgAAAA==.',
Zh='Zhule:BAABLgAECn8lAAIGAAkJ1R7GDgCVAgloDAAABQBSAGkMAAAFAEsAawwAAAUASgBqDAAABQBXAGwMAAAFAF8AbQwAAAMARgDqDAAABQBbAG4MAAADAFMAbwwAAAEAOgAGAAkJ1R7GDgCVAgloDAAABQBSAGkMAAAFAEsAawwAAAUASgBqDAAABQBXAGwMAAAFAF8AbQwAAAMARgDqDAAABQBbAG4MAAADAFMAbwwAAAEAOgAAAA==.',
Zy='Zyklonbarbie:BAAALgAECgcJBwAAAA==.',
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
