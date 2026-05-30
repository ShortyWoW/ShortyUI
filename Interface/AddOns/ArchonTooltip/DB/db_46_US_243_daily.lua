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

local lookup = {'Warlock-Demonology','Priest-Discipline','Priest-Holy','Unknown-Unknown','DeathKnight-Unholy','DeathKnight-Frost','Paladin-Retribution','Hunter-Marksmanship','Hunter-BeastMastery','Mage-Frost','DemonHunter-Devourer','DemonHunter-Vengeance','Evoker-Augmentation','Paladin-Holy','Monk-Brewmaster','Druid-Restoration','Warrior-Protection','Hunter-Survival','Shaman-Elemental','Shaman-Restoration','Druid-Balance','Rogue-Subtlety','Rogue-Assassination','Evoker-Preservation','Evoker-Devastation','Warrior-Fury','Paladin-Protection','Monk-Mistweaver','Warrior-Arms','Shaman-Enhancement','Mage-Arcane','DeathKnight-Blood','Priest-Shadow','Rogue-Outlaw','Monk-Windwalker',}
local provider = {region='US',realm='Ysondre',name='US',type='daily',zone=46,date='2026-05-29',data={Ak='Akari:BAAALgADCgEJAQAAAA==.',
Al='Alex:BAAALgADCgMJAwAAAA==.',
An='Angalius:BAAALgAECggJCwAAAA==.',
Ap='Apathy:BAAALgAECgIJBAAAAA==.',
Ar='Aralid:BAABLgAECn8WAAIBAAcJ6SKHHwBZAgdoDAAAAwBfAGkMAAADAFoAawwAAAMATwBqDAAAAgBgAGwMAAABAFQA6gwAAAYAWwBuDAAABABeAAEABwnpIocfAFkCB2gMAAADAF8AaQwAAAMAWgBrDAAAAwBPAGoMAAACAGAAbAwAAAEAVADqDAAABgBbAG4MAAAEAF4AAAA=.Ariadné:BAABLgAECn8YAAMCAAgJFx0+DwBaAghoDAAABABHAGkMAAADAEYAawwAAAMATgBqDAAAAwBcAGwMAAACAEgAbQwAAAEASQDqDAAABQBDAG4MAAADAEYAAgAICRcdPg8AWgIIaAwAAAMARwBpDAAAAwBGAGsMAAADAE4AagwAAAMAXABsDAAAAgBIAG0MAAABAEkA6gwAAAQAQwBuDAAAAwBGAAMAAglMCfNzAFgAAmgMAAABACsA6gwAAAEABAAAAA==.Artasha:BAAALgADCgIJAwAAAA==.',
Ba='Badassmf:BAAALgADCgIJAgAAAA==.',
Be='Bearlover:BAAALgAECgcJDwAAAA==.Beau:BAAALgAECgQJBAAAAA==.Belal:BAAALgADCgIJAgAAAA==.',
Bi='Birdflù:BAAALgADCgUJBQAAAA==.Biscuits:BAAALgADCgYJBgAAAA==.',
Bo='Bomi:BAAALgAECgIJAwAAAA==.Boogiesera:BAAALgADCgQJBAABLgAECgcJEwAEAAAAAA==.Bootles:BAAALgAECgcJEwAAAA==.Bowl:BAAALgADCgkJDAAAAA==.',
Br='Brad:BAABLgAFFH8FAAMFAAQJ2R8VXwAcAQRoDAAAAQBdAGoMAAABAC4AbAwAAAEAWgDqDAAAAgA8AAUABAnZHxVfABwBBGgMAAABAF0AagwAAAEALgBsDAAAAQBaAOoMAAABADwABgABCTMHsR8APQAB6gwAAAEAEgAAAA==.Brewslee:BAAALgAECgkJAQAAAA==.',
Bu='Bulltastich:BAAALgADCgUJBgABLgADCgcJBwAEAAAAAA==.Bullwings:BAAALgAECgEJAQAAAA==.Buttholemu:BAAALgADCgYJBgAAAA==.',
Ca='Calanthe:BAAALgAECgYJBwAAAA==.',
Ch='Charrend:BAABLgAECn8lAAIHAAgJQAVKuADzAAhoDAAABwATAGkMAAAGABEAawwAAAYADQBqDAAABQASAGwMAAAFABIAbQwAAAEACQDqDAAABQAJAG4MAAACAAYABwAICUAFSrgA8wAIaAwAAAcAEwBpDAAABgARAGsMAAAGAA0AagwAAAUAEgBsDAAABQASAG0MAAABAAkA6gwAAAUACQBuDAAAAgAGAAAA.',
Cl='Clutchmedic:BAABLgAFFH8IAAMIAAUJEQw2EAAwAQVoDAAAAwA7AGkMAAACABMAawwAAAEAFABqDAAAAQAaAOoMAAABABcACAAECX8NNhAAMAEEaAwAAAMAOwBrDAAAAQAUAGoMAAABABoA6gwAAAEAFwAJAAEJxwc3JgBVAAFpDAAAAgATAAAA.',
Co='Completed:BAAALgADCgUJBQAAAA==.',
Cp='Cptloveme:BAABLgAECn8eAAIKAAYJaRpolwCmAQZoDAAABgBWAGkMAAAGAEUAawwAAAUANgBqDAAABQAxAGwMAAADADoA6gwAAAUARAAKAAYJaRpolwCmAQZoDAAABgBWAGkMAAAGAEUAawwAAAUANgBqDAAABQAxAGwMAAADADoA6gwAAAUARAAAAA==.',
Cr='Crazon:BAAALgAECgMJAwAAAA==.Cropduster:BAACLgAFFH8RAAILAAQJ0g9FPgAPAQRoDAAABgAkAGkMAAAEACsAawwAAAIADQDqDAAABQBFAAsABAnSD0U+AA8BBGgMAAAGACQAaQwAAAQAKwBrDAAAAgANAOoMAAAFAEUALgAECn8fAAMLAAkJHRfDNQAgAgALAAgJ3hnDNQAgAgAMAAEJ2QPsLQAzAAAAAA==.Crushed:BAAALgADCgMJAwABLgAECggJIgABAPkcAA==.',
Ct='Cthulhu:BAACLgAFFH8cAAIBAAUJRhs2MABZAQVoDAAACABMAGkMAAAFAFEAawwAAAYALgBqDAAAAQAEAOoMAAAIAEoAAQAFCUYbNjAAWQEFaAwAAAgATABpDAAABQBRAGsMAAAGAC4AagwAAAEABADqDAAACABKAC4ABAp/LwACAQAICc8esx0ApAIAAQAICc8esx0ApAIAAAA=.',
Cu='Cursedpriest:BAAALgADCgUJBQAAAA==.',
Da='Dad:BAAALgAECgEJAgAAAA==.Darner:BAAALgAECgQJBAAAAA==.',
De='Delnarei:BAAALgADCgEJAQAAAA==.Demise:BAAALgADCgYJCgABLgAFFAMJCQANAEoUAA==.Destiniemonk:BAAALgAFFAEJAQABLgAFFAQJDgAOANYjAA==.Deviant:BAAALgADCgkJDQAAAA==.',
Di='Diosito:BAAALgAECgYJCwAAAA==.',
Do='Dolo:BAAALgADCgIJAgAAAA==.Doloni:BAAALgAECgUJDAAAAA==.Doomd:BAEALgAECgcJEQAAAA==.Doomdtrooper:BAEALgAECgcJDgABLgAECgcJEQAEAAAAAA==.Dotti:BAAALgADCgkJCQABLgAECggJJwAJAIkMAA==.Dotts:BAABLgAECn8dAAIBAAcJ9RJJbwBPAQdoDAAABQBGAGkMAAAFADwAawwAAAUAIgBqDAAABABUAGwMAAAEACsAbQwAAAEAFgDqDAAABQA9AAEABwn1EklvAE8BB2gMAAAFAEYAaQwAAAUAPABrDAAABQAiAGoMAAAEAFQAbAwAAAQAKwBtDAAAAQAWAOoMAAAFAD0AAAA=.',
Dr='Drewied:BAAALgADCgEJAQAAAA==.Drfinger:BAAALgAECgMJAwABLgAECgkJKwAPAOslAA==.Droodorei:BAAALgADCggJJAAAAA==.',
Du='Durianz:BAAALgAECgYJCwAAAA==.',
Dw='Dwnloadedchi:BAAALgAECggJDQAAAA==.Dwnloadedski:BAAALgAECgcJEgAAAA==.',
Eg='Eggenan:BAAALgAECgUJAQAAAA==.',
Ei='Eiskält:BAABLgAECn8bAAIKAAgJTQdHnAAmAQhoDAAABQAIAGkMAAAEABIAawwAAAQAEwBqDAAABAAMAGwMAAAFAAYAbQwAAAIAEADqDAAAAgAmAG4MAAABABYACgAICU0HR5wAJgEIaAwAAAUACABpDAAABAASAGsMAAAEABMAagwAAAQADABsDAAABQAGAG0MAAACABAA6gwAAAIAJgBuDAAAAQAWAAAA.',
El='Ellay:BAABLgAECn8fAAIQAAgJ9RBDOQCdAQhoDAAABQBFAGkMAAAFAC0AawwAAAUAKgBqDAAABAAfAGwMAAADADMAbQwAAAIAMADqDAAABgAtAG4MAAABAAwAEAAICfUQQzkAnQEIaAwAAAUARQBpDAAABQAtAGsMAAAFACoAagwAAAQAHwBsDAAAAwAzAG0MAAACADAA6gwAAAYALQBuDAAAAQAMAAAA.',
Em='Emofumu:BAAALgADCgYJBgABLgAFFAMJBQARAN0hAA==.',
En='Endrin:BAAALgAECgYJDAAAAA==.',
Ew='Eww:BAEBLgAECn8/AAISAAkJLRnTBwCTAgloDAAACgBZAGkMAAAJAFAAawwAAAkAVwBqDAAACQBVAGwMAAAIAEgAbQwAAAUAJQDqDAAACABZAG4MAAADACcAbwwAAAIAEwASAAkJLRnTBwCTAgloDAAACgBZAGkMAAAJAFAAawwAAAkAVwBqDAAACQBVAGwMAAAIAEgAbQwAAAUAJQDqDAAACABZAG4MAAADACcAbwwAAAIAEwAAAA==.',
Ez='Ezzak:BAAALgADCgQJBAAAAA==.',
Fe='Felfirefoxxo:BAAALgAFFAIJAgAAAA==.Felldeeds:BAABLgAECn8kAAIQAAgJlSWrBABhAwhoDAAABwBhAGkMAAAHAGMAawwAAAYAYQBqDAAAAgBgAGwMAAADAGEAbQwAAAIAWwDqDAAACABhAG4MAAABAFoAEAAICZUlqwQAYQMIaAwAAAcAYQBpDAAABwBjAGsMAAAGAGEAagwAAAIAYABsDAAAAwBhAG0MAAACAFsA6gwAAAgAYQBuDAAAAQBaAAAA.Fellphist:BAAALgAECgIJAgABLgAECggJJAAQAJUlAA==.Fellshock:BAAALgAECgYJCwABLgAECggJJAAQAJUlAA==.Felthazzar:BAAALgAECgYJBgAAAA==.Fent:BAACLgAFFH8SAAMTAAUJQw8SIAACAQVoDAAABQApAGkMAAAFACkAawwAAAMAKwBqDAAAAQAkAOoMAAAEAB0AEwAFCUMPEiAAAgEFaAwAAAUAKQBpDAAABQApAGsMAAACACsAagwAAAEAJADqDAAABAAdABQAAQlEC8BrADwAAWsMAAABABwALgAECn8sAAMTAAkJiByAGABRAgATAAcJayCAGABRAgAUAAkJQRfxIAAZAgAAAA==.Fey:BAAALgAECgQJBQAAAA==.',
Fi='Fingerblastn:BAAALgADCgcJBwABLgAECgkJKwAPAOslAA==.Fingerr:BAABLgAECn8rAAIPAAkJ6yW1AABtAwloDAAABwBjAGkMAAAGAGMAawwAAAYAYQBqDAAABgBjAGwMAAAFAGMAbQwAAAEAVADqDAAABwBjAG4MAAAEAGMAbwwAAAEAYQAPAAkJ6yW1AABtAwloDAAABwBjAGkMAAAGAGMAawwAAAYAYQBqDAAABgBjAGwMAAAFAGMAbQwAAAEAVADqDAAABwBjAG4MAAAEAGMAbwwAAAEAYQAAAA==.Finneagan:BAAALgADCgEJAQAAAA==.',
Fl='Flinkorandus:BAAALgAECgEJAgABLgAECgcJFgABAOkiAA==.Flokki:BAAALgAECgcJDwAAAA==.',
Fo='Foxxowo:BAABLgAFFH8FAAIQAAMJogUoQQCcAANoDAAAAgATAGkMAAACABAA6gwAAAEABgAQAAMJogUoQQCcAANoDAAAAgATAGkMAAACABAA6gwAAAEABgAAAA==.',
Fr='Froztbane:BAEALgAECgcJDwABLgAECgkJQwALAK8gAA==.Froztbanshee:BAEBLgAECn9DAAILAAkJryClDAAbAwloDAAACgBbAGkMAAAKAFkAawwAAAoAVgBqDAAACgBRAGwMAAAHAFwAbQwAAAUAWADqDAAACgBeAG4MAAAEAFEAbwwAAAEALAALAAkJryClDAAbAwloDAAACgBbAGkMAAAKAFkAawwAAAoAVgBqDAAACgBRAGwMAAAHAFwAbQwAAAUAWADqDAAACgBeAG4MAAAEAFEAbwwAAAEALAAAAA==.',
Fy='Fynger:BAAALgAECgUJCgABLgAECgkJKwAPAOslAA==.',
Gh='Ghats:BAAALgAECgEJAQAAAA==.Ghuss:BAAALgAECgcJBwAAAA==.',
Gl='Glass:BAAALgAECgYJEQAAAA==.',
Go='Gogo:BAAALgAECgYJDAAAAA==.',
Gr='Grimzyn:BAACLgAFFH8PAAIFAAUJvxSDVwAnAQVoDAAABABZAGkMAAAEACwAawwAAAMAJQBqDAAAAQAEAOoMAAADACkABQAFCb8Ug1cAJwEFaAwAAAQAWQBpDAAABAAsAGsMAAADACUAagwAAAEABADqDAAAAwApAC4ABAp/HAACBQAICWMcwDYAXAIABQAICWMcwDYAXAIAAAA=.Grudge:BAABLgAECn83AAMFAAkJNBJhRQDeAQloDAAACAAtAGkMAAAHADcAawwAAAcAMABqDAAABwAtAGwMAAAHADYAbQwAAAUAHwDqDAAACAAuAG4MAAAFACwAbwwAAAEALgAFAAkJ8hBhRQDeAQloDAAABgAtAGkMAAAFADEAawwAAAUAHgBqDAAABQAqAGwMAAAFADYAbQwAAAMAHwDqDAAABgAsAG4MAAADACwAbwwAAAEALgAGAAgJTBC/BQDVAQhoDAAAAgAhAGkMAAACADcAawwAAAIAMABqDAAAAgAtAGwMAAACACkAbQwAAAIAGADqDAAAAgAuAG4MAAACACoAAAA=.',
Ha='Haircules:BAAALgAECgUJCwAAAA==.Harrowhark:BAACLgAFFH8MAAIFAAQJ2R6bKgCDAQRoDAAABABZAGkMAAADAFYAawwAAAEAMADqDAAABABaAAUABAnZHpsqAIMBBGgMAAAEAFkAaQwAAAMAVgBrDAAAAQAwAOoMAAAEAFoALgAECn8uAAMFAAgJniPdFQCwAgAFAAgJniPdFQCwAgAGAAEJ3BrrKABNAAAAAA==.',
He='Herambae:BAAALgADCgYJBgAAAA==.Herculesátan:BAAALgADCgYJCAAAAA==.',
Ho='Hornstache:BAAALgADCgEJAQAAAA==.',
Hy='Hyacinth:BAABLgAECn8sAAIVAAkJhBbfEgAmAgloDAAABgBGAGkMAAAGAEEAawwAAAYALQBqDAAABQAnAGwMAAAEAEQAbQwAAAIANgDqDAAABgBOAG4MAAAFACsAbwwAAAQAIgAVAAkJhBbfEgAmAgloDAAABgBGAGkMAAAGAEEAawwAAAYALQBqDAAABQAnAGwMAAAEAEQAbQwAAAIANgDqDAAABgBOAG4MAAAFACsAbwwAAAQAIgAAAA==.Hyria:BAAALgADCgkJDwABLgAECgcJEwAEAAAAAA==.Hyun:BAAALgADCgYJBgAAAA==.',
Ia='Iamfinn:BAAALgAECgEJAQAAAA==.Iamomegafox:BAACLgAFFH8LAAIWAAMJaBwWHQANAQNoDAAABABQAGkMAAADACwA6gwAAAQAXQAWAAMJaBwWHQANAQNoDAAABABQAGkMAAADACwA6gwAAAQAXQAuAAQKfzEAAxYACQlGGo8OACgCABYACQnCGI8OACgCABcABgnxF+QLAGgBAAAA.',
Ig='Iggylock:BAAALgADCgYJBgAAAA==.Ignax:BAACLgAFFH8NAAMYAAYJIQgDEABvAQZoDAAAAwAQAGkMAAADABAAawwAAAEAJgBqDAAAAQATAGwMAAABABMA6gwAAAQADgAYAAYJIQgDEABvAQZoDAAAAgAQAGkMAAADABAAawwAAAEAJgBqDAAAAQATAGwMAAABABMA6gwAAAQADgAZAAEJWgUVCwBNAAFoDAAAAQANAC4ABAp/IQADGAAICRAVUBQAAQIAGAAICRAVUBQAAQIAGQAGCVYIXiUA+gAAAAA=.',
Im='Imomeganisha:BAAALgAECgQJBwABLgAFFAMJCwAWAGgcAA==.Imsparticus:BAABLgAECn8VAAMaAAYJxgiIVgDZAAZoDAAABAAkAGkMAAAEAB0AawwAAAQAGABqDAAAAwAPAGwMAAACAAYA6gwAAAQADwAaAAYJxgiIVgDZAAZoDAAAAwAkAGkMAAADAB0AawwAAAMAGABqDAAAAwAPAGwMAAACAAYA6gwAAAMADwARAAQJcAHROwBtAARoDAAAAQABAGkMAAABAAEAawwAAAEABwDqDAAAAQAEAAAA.',
Io='Ionias:BAABLgAECn8jAAQbAAkJ5Bb7FwBXAQloDAAABQAsAGkMAAAFAFAAawwAAAUASABqDAAABAAXAGwMAAAEADYAbQwAAAMAYQDqDAAABQBGAG4MAAADABYAbwwAAAEAGwAbAAYJERn7FwBXAQZoDAAAAQAsAGkMAAABAFAAawwAAAEASABqDAAAAQAXAGwMAAABADYA6gwAAAEARgAOAAgJuQiZNwBVAQhoDAAABAAPAGkMAAAEABMAawwAAAQAEwBqDAAAAwARAGwMAAADABoAbQwAAAMAFADqDAAABAA1AG4MAAACAAUABwACCeMJ4iIBZwACbgwAAAEAFgBvDAAAAQAbAAAA.',
Ja='Jackblack:BAAALgAECgIJBAABLgAFFAQJEQALANIPAA==.Jaquelius:BAAALgAECgUJDgAAAA==.',
Jo='Joeworgen:BAAALgAECgEJAQAAAA==.Johadan:BAABLgAECn8aAAIHAAcJ7QdluQDyAAdoDAAABAARAGkMAAAEABIAawwAAAQAFwBqDAAAAwATAGwMAAAEABEA6gwAAAYADgBuDAAAAQAdAAcABwntB2W5APIAB2gMAAAEABEAaQwAAAQAEgBrDAAABAAXAGoMAAADABMAbAwAAAQAEQDqDAAABgAOAG4MAAABAB0AAAA=.',
Ka='Kade:BAAALgADCgEJAgAAAA==.Kaelx:BAAALgAECgQJCAAAAA==.Kafizz:BAABLgAECn8fAAIBAAkJWxXKPgASAgloDAAABQAsAGkMAAAGAFoAawwAAAYAUABqDAAAAwBOAGwMAAADAEUAbQwAAAEAHwDqDAAAAwAsAG4MAAADADcAbwwAAAEAFgABAAkJWxXKPgASAgloDAAABQAsAGkMAAAGAFoAawwAAAYAUABqDAAAAwBOAGwMAAADAEUAbQwAAAEAHwDqDAAAAwAsAG4MAAADADcAbwwAAAEAFgAAAA==.Kagnara:BAAALgADCgUJBQABLgAFFAQJDAAFANkeAA==.',
Ke='Keely:BAAALgAECgUJCwAAAA==.Keolmont:BAAALgADCgEJAQAAAA==.',
Ki='Kinla:BAAALgAECgQJBAAAAA==.Kirakitsune:BAAALgAECgEJAQAAAA==.Kireag:BAAALgADCgIJAgAAAA==.',
Ko='Kooppa:BAAALgADCgQJBAAAAA==.',
Ku='Kuromigirl:BAABLgAECn8WAAILAAcJ0BKIYwBFAQdoDAAAAwAvAGkMAAADADgAawwAAAMAMgBqDAAAAgAwAGwMAAABADQA6gwAAAYALgBuDAAABAAjAAsABwnQEohjAEUBB2gMAAADAC8AaQwAAAMAOABrDAAAAwAyAGoMAAACADAAbAwAAAEANADqDAAABgAuAG4MAAAEACMAAAA=.',
La='Labchimpette:BAAALgAECgYJDgAAAA==.Lagerthä:BAAALgAECgcJEwABLgAECgkJJAAQADkaAA==.',
Li='Link:BAAALgAECgYJBgAAAA==.Lione:BAABLgAECn8UAAMQAAcJ8hi0LwDtAQdoDAAABAAyAGkMAAADAFUAawwAAAMAUABqDAAAAgBUAGwMAAABAEQA6gwAAAUAOQBuDAAAAgAUABAABwnyGLQvAO0BB2gMAAADADIAaQwAAAMAVQBrDAAAAwBQAGoMAAACAFQAbAwAAAEARADqDAAABAA5AG4MAAACABQAFQACCWAIOXAATQACaAwAAAEAGgDqDAAAAQAQAAAA.Lith:BAACLgAFFH8HAAIYAAMJgRTnDQD9AANoDAAAAwBEAGsMAAACABsA6gwAAAIAPQAYAAMJgRTnDQD9AANoDAAAAwBEAGsMAAACABsA6gwAAAIAPQAuAAQKfycAAxgACAmtGf4JAC8CABgACAmtGf4JAC8CAA0ACAlgEL4dANcBAAAA.Litterbocks:BAAALgAECgMJBAAAAA==.Littlepriest:BAAALgADCgEJAQAAAA==.',
Ly='Lyzandra:BAAALgADCgYJCgAAAA==.',
['Lì']='Lìllyanna:BAABLgAECn8pAAIbAAkJbxMLDgDHAQloDAAABwA1AGkMAAAGADEAawwAAAYARABqDAAAAwAfAGwMAAADACQAbQwAAAIAGADqDAAACABDAG4MAAAEAD0AbwwAAAIAJAAbAAkJbxMLDgDHAQloDAAABwA1AGkMAAAGADEAawwAAAYARABqDAAAAwAfAGwMAAADACQAbQwAAAIAGADqDAAACABDAG4MAAAEAD0AbwwAAAIAJAAAAA==.',
Ma='Mailbox:BAAALgAECgYJBgABLgAFFAgJIwAOAA8iAA==.Malion:BAAALgAECgEJAQAAAA==.Malock:BAAALgADCgkJCQAAAA==.Mango:BAAALgAECgIJAwAAAA==.Matcha:BAABLgAECn8jAAIcAAkJjxwICgDWAgloDAAABAA7AGkMAAAEAEkAawwAAAQAUABqDAAABABOAGwMAAADADsAbQwAAAIASQDqDAAABQBSAG4MAAAFAEkAbwwAAAQASwAcAAkJjxwICgDWAgloDAAABAA7AGkMAAAEAEkAawwAAAQAUABqDAAABABOAGwMAAADADsAbQwAAAIASQDqDAAABQBSAG4MAAAFAEkAbwwAAAQASwAAAA==.Mauler:BAAALgAECgQJCAAAAA==.',
Me='Melinoë:BAAALgADCgUJBQAAAA==.Meowhunter:BAAALgAECgUJCgAAAA==.',
Mi='Miaraa:BAAALgAECgcJEAAAAA==.Minervå:BAAALgADCgMJAwAAAA==.',
Mo='Mogdor:BAABLgAECn8mAAMNAAkJvBn8EABCAgloDAAABQBaAGkMAAAFAEsAawwAAAUAUQBqDAAABgBIAGwMAAAGAEoAbQwAAAIAQADqDAAABQBBAG4MAAADACAAbwwAAAEAKQANAAkJvBn8EABCAgloDAAABQBaAGkMAAAFAEsAawwAAAUAUQBqDAAABQBIAGwMAAAFAEoAbQwAAAIAQADqDAAABABBAG4MAAADACAAbwwAAAEAKQAZAAMJZBRuLAC4AANqDAAAAQAvAGwMAAABADkA6gwAAAEALgAAAA==.Moonpeach:BAABLgAECn8eAAIQAAgJ7Q75PQCGAQhoDAAABgBNAGkMAAAGABcAawwAAAYAQgBqDAAAAwApAGwMAAACACcAbQwAAAEAEADqDAAABQAaAG4MAAABAA4AEAAICe0O+T0AhgEIaAwAAAYATQBpDAAABgAXAGsMAAAGAEIAagwAAAMAKQBsDAAAAgAnAG0MAAABABAA6gwAAAUAGgBuDAAAAQAOAAAA.Motex:BAABLgAECn8eAAIWAAgJ/AKFMwBvAQhoDAAABAAIAGkMAAAEAAgAawwAAAQADQBqDAAABAAJAGwMAAAEAAkAbQwAAAMABQDqDAAABAAFAG4MAAADAAIAFgAICfwChTMAbwEIaAwAAAQACABpDAAABAAIAGsMAAAEAA0AagwAAAQACQBsDAAABAAJAG0MAAADAAUA6gwAAAQABQBuDAAAAwACAAAA.',
Mu='Murgold:BAAALgAECgQJBAAAAA==.',
Na='Naturebug:BAAALgAECgYJCgAAAA==.',
Ne='Neature:BAAALgAFFAEJAQABLgAFFAQJEQALANIPAA==.Ned:BAECLgAFFH8UAAIaAAUJDyVNCQCZAQVoDAAABQBcAGkMAAAFAGMAawwAAAQAXwBqDAAAAgBPAOoMAAAEAFwAGgAFCQ8lTQkAmQEFaAwAAAUAXABpDAAABQBjAGsMAAAEAF8AagwAAAIATwDqDAAABABcAC4ABAp/TwADGgAJCR0mswAAfAMAGgAJCR0mswAAfAMAHQAECWUkhg8AowEAAAA=.Netre:BAAALgAECgYJEQAAAA==.',
Ni='Nimbus:BAAALgAFFAMJAgABLgAFFAgJGAANAIUWAA==.Ninax:BAAALgAECgYJCgAAAA==.',
Ny='Nylian:BAAALgAECgQJCgAAAA==.',
Ob='Obamasmama:BAAALgAFFAIJAgAAAA==.',
Oc='Octomore:BAAALgAFFAEJAgAAAA==.',
Ol='Oldmantom:BAAALgADCgYJBgAAAA==.',
Or='Ormgorg:BAABLgAECn8VAAIeAAcJ9R3iDADEAQdoDAAAAwBTAGkMAAADAF0AawwAAAMATQBqDAAAAwBXAGwMAAACAE8A6gwAAAUAUgBuDAAAAgAqAB4ABwn1HeIMAMQBB2gMAAADAFMAaQwAAAMAXQBrDAAAAwBNAGoMAAADAFcAbAwAAAIATwDqDAAABQBSAG4MAAACACoAAAA=.Orpheus:BAABLgAECn9HAAQUAAkJRCI9BABdAwloDAAACgBSAGkMAAAKAFwAawwAAAoAYQBqDAAACQBfAGwMAAAIAFoAbQwAAAUAVwDqDAAACQBNAG4MAAAGAEwAbwwAAAQAWAAUAAkJRCI9BABdAwloDAAABwBSAGkMAAAHAFwAawwAAAcAYQBqDAAACABfAGwMAAAHAFoAbQwAAAUAVwDqDAAACABNAG4MAAAGAEwAbwwAAAQAWAATAAUJ7hf4RQD9AAVoDAAAAgBOAGkMAAACADEAawwAAAIANABqDAAAAQBLAGwMAAABAEEAHgAECTsNhx8AzgAEaAwAAAEAJgBpDAAAAQAkAGsMAAABABYA6gwAAAEAJQAAAA==.',
Oz='Oza:BAAALgAECgMJBgAAAA==.',
Pa='Pandamoniium:BAAALgAECgcJDQABLgAFFAUJDgAKACAbAA==.Pandamonk:BAACLgAFFH8WAAIPAAUJyyUkCgC0AQVoDAAABgBjAGkMAAAGAGMAawwAAAQAWwBqDAAAAQBbAOoMAAAFAGEADwAFCcslJAoAtAEFaAwAAAYAYwBpDAAABgBjAGsMAAAEAFsAagwAAAEAWwDqDAAABQBhAC4ABAp/OgACDwAJCZglHAEAXAMADwAJCZglHAEAXAMAAAA=.',
Pe='Percy:BAEBLgAECn8bAAIfAAcJCxDiBQBQAQdoDAAABgAqAGkMAAAEADIAawwAAAQAMABqDAAABABJAGwMAAAEACAAbQwAAAEAEwDqDAAABAA1AB8ABwkLEOIFAFABB2gMAAAGACoAaQwAAAQAMgBrDAAABAAwAGoMAAAEAEkAbAwAAAQAIABtDAAAAQATAOoMAAAEADUAAAA=.',
Pi='Pickleswag:BAAALgAECgMJAwAAAA==.',
Pr='Preservation:BAAALgAECgMJAwAAAA==.',
Ra='Raastamon:BAAALgADCgEJAQAAAA==.Raekitty:BAABLgAECn8XAAIQAAgJgR6SFACRAghoDAAABABdAGkMAAAEAGAAawwAAAQAYQBqDAAAAwBQAGwMAAADAFsAbQwAAAEAHQDqDAAAAwBVAG4MAAABADIAEAAICYEekhQAkQIIaAwAAAQAXQBpDAAABABgAGsMAAAEAGEAagwAAAMAUABsDAAAAwBbAG0MAAABAB0A6gwAAAMAVQBuDAAAAQAyAAAA.Rama:BAAALgAECgMJBQABLgAECgYJGQAKAPQcAA==.',
Re='Redrover:BAAALgADCggJDgAAAA==.Reia:BAAALgADCgcJBwAAAA==.',
Rh='Rhara:BAAALgADCgYJEgAAAA==.Rhoem:BAACLgAFFH8HAAIGAAIJ9Qf9FgCIAAJoDAAABAARAGkMAAADABYABgACCfUH/RYAiAACaAwAAAQAEQBpDAAAAwAWAC4ABAp/KQADBgAJCUAdsQUA1wEABgAICcwfsQUA1wEAIAAHCQIYmxUAogEAAAA=.',
Ri='Rin:BAEALgADCgMJAwABLgAECgkJJwAcANshAA==.',
Ro='Roger:BAABLgAECn8iAAMOAAcJJSOxDACuAgdoDAAABwBhAGkMAAAHAF0AawwAAAYAWgBqDAAABgBYAGwMAAADAF8AbQwAAAEATwDqDAAABABVAA4ABwklI7EMAK4CB2gMAAAEAGEAaQwAAAYAXQBrDAAABQBaAGoMAAAFAFgAbAwAAAMAXwBtDAAAAQBPAOoMAAACAFUABwAFCSgNLu4AqwAFaAwAAAMAJwBpDAAAAQAWAGsMAAABABIAagwAAAEALQDqDAAAAgA1AAAA.',
Ru='Rumor:BAACLgAFFH8iAAMXAAgJ+SAaAADQAghoDAAABQBjAGkMAAAHAGIAawwAAAYAUwBqDAAABABbAGwMAAACAFoAbQwAAAEAHQDqDAAACABaAG4MAAABAGEAFwAICfkgGgAA0AIIaAwAAAQAYwBpDAAABQBiAGsMAAAFAFMAagwAAAQAWwBsDAAAAgBaAG0MAAABAB0A6gwAAAYAWgBuDAAAAQBhABYABAmxGXUHAG0BBGgMAAABADoAaQwAAAIAWQBrDAAAAQA6AOoMAAACADgALgAECn85AAMXAAgJySZzAQDhAgAWAAgJ0ySXCgDpAgAXAAgJlSZzAQDhAgAAAA==.Run:BAAALgAECgEJAQAAAA==.',
Se='Secretgrace:BAAALgADCgQJBAABLgAECgcJFQAeAPUdAA==.Seed:BAAALgAECgkJEQAAAA==.Senortickle:BAABLgAECn8XAAILAAcJWhWZUAB7AQdoDAAAAwBIAGkMAAAEADcAawwAAAUAKQBqDAAAAwAsAGwMAAAEAEYAbQwAAAEAIADqDAAAAwA4AAsABwlaFZlQAHsBB2gMAAADAEgAaQwAAAQANwBrDAAABQApAGoMAAADACwAbAwAAAQARgBtDAAAAQAgAOoMAAADADgAAAA=.',
Sh='Shadowmoone:BAABLgAECn8nAAIJAAgJiQwNVgCGAQhoDAAABwAnAGkMAAAHAB0AawwAAAUAFgBqDAAABAAaAGwMAAAFABgAbQwAAAIAGADqDAAABwA6AG4MAAACABkACQAICYkMDVYAhgEIaAwAAAcAJwBpDAAABwAdAGsMAAAFABYAagwAAAQAGgBsDAAABQAYAG0MAAACABgA6gwAAAcAOgBuDAAAAgAZAAAA.Shaki:BAAALgAECgQJBwAAAA==.Shalendris:BAAALgAECgEJAQAAAA==.Shalestrasz:BAABLgAECn8XAAQZAAgJNQg0IQAjAQhoDAAAAwAIAGkMAAADABQAawwAAAMAGABqDAAAAwAJAGwMAAADABAAbQwAAAIACQDqDAAABAAyAG4MAAACABEAGQAICRcFNCEAIwEIaAwAAAMACABpDAAAAwAUAGsMAAADABgAagwAAAMACQBsDAAAAgAQAG0MAAABAAkA6gwAAAIACABuDAAAAQADAA0AAwkWCtFhAIkAA20MAAABAAkA6gwAAAEAMgBuDAAAAQARABgAAglVAU1FAEYAAmwMAAABAAQA6gwAAAEAAgAAAA==.Shibal:BAAALgADCggJCAAAAA==.Shinedown:BAAALgADCgQJBAAAAA==.Shochu:BAAALgAECgcJEAAAAA==.',
Sl='Sloane:BAAALgADCgQJBAAAAA==.',
So='Soju:BAAALgAECgUJBQAAAA==.Somnera:BAAALgAECgEJAQABLgAECgcJFQAeAPUdAA==.Soyboymalfoy:BAABLgAECn8WAAIDAAgJxBPEHgC2AQhoDAAABABFAGkMAAADAD4AawwAAAQAOABqDAAAAwAnAGwMAAACADQA6gwAAAMAPwBuDAAAAgApAG8MAAABABIAAwAICcQTxB4AtgEIaAwAAAQARQBpDAAAAwA+AGsMAAAEADgAagwAAAMAJwBsDAAAAgA0AOoMAAADAD8AbgwAAAIAKQBvDAAAAQASAAAA.',
Sp='Sp:BAACLgAFFH8aAAIDAAUJBB5SBwCoAQVoDAAACQBEAGkMAAAFAD8AawwAAAQAWgBqDAAAAgBCAOoMAAAGAGAAAwAFCQQeUgcAqAEFaAwAAAkARABpDAAABQA/AGsMAAAEAFoAagwAAAIAQgDqDAAABgBgAC4ABAp/RAADAwAICeIkYAMASwMAAwAICeIkYAMASwMAIQABCXkKx3kALwAAAAA=.',
St='Sterility:BAAALgAECgUJEAAAAA==.',
Sw='Switchfoot:BAACLgAFFH8IAAIiAAMJiR3ABQASAQNoDAAAAwBcAGkMAAACADQA6gwAAAMAUQAiAAMJiR3ABQASAQNoDAAAAwBcAGkMAAACADQA6gwAAAMAUQAuAAQKfzYAAyIACQlLITcBAOICACIACQlLITcBAOICABcAAQklE9sbAEkAAAAA.',
['Sï']='Sïeghart:BAAALgADCgUJBQAAAA==.',
Ta='Tallmanbeta:BAAALgAECgUJAwAAAA==.',
Te='Tenzin:BAAALgADCgQJBAABLgAFFAUJHAABAEYbAA==.Tex:BAAALgADCgcJDgAAAA==.',
Ti='Timerunner:BAAALgADCgYJBgAAAA==.',
To='Totingtotems:BAAALgADCgcJDQAAAA==.Touchofdeath:BAABLgAECn8WAAIjAAcJ3As1OQA5AQdoDAAABAAeAGkMAAAEACUAawwAAAQAKQBqDAAAAwAfAGwMAAADACQAbQwAAAEACQDqDAAAAwAbACMABwncCzU5ADkBB2gMAAAEAB4AaQwAAAQAJQBrDAAABAApAGoMAAADAB8AbAwAAAMAJABtDAAAAQAJAOoMAAADABsAAAA=.',
Ug='Ughnga:BAAALgAECgMJAwABLgAECgcJHQABAPUSAA==.',
Va='Vandli:BAAALgAECgMJBAAAAA==.',
Ve='Velzard:BAAALgAECgYJEgAAAA==.Verti:BAAALgAECgYJCwAAAA==.Veylan:BAAALgAECgEJAQAAAA==.',
Vi='Visona:BAAALgADCgQJBAAAAA==.',
Vo='Voíshara:BAAALgADCgUJCwAAAA==.',
['Vö']='Vöre:BAAALgAECgYJBwAAAA==.',
Wa='Wanagi:BAAALgADCgEJAQAAAA==.',
Wh='Whitessin:BAAALgAECgEJAQAAAA==.',
Wi='Wither:BAACLgAFFH8FAAIFAAQJMhF2FQBOAQRoDAAAAQAZAGkMAAABAE0AawwAAAEAIgDqDAAAAgAmAAUABAkyEXYVAE4BBGgMAAABABkAaQwAAAEATQBrDAAAAQAiAOoMAAACACYALgAECn8eAAIFAAgJXSKeNQBgAgAFAAgJXSKeNQBgAgABLgAFFAgJIgAXAPkgAA==.',
Wy='Wyspur:BAAALgADCgYJCgAAAA==.',
Yo='Yofoxxo:BAACLgAFFH8aAAIOAAgJ0RfrAwBhAghoDAAABQBJAGkMAAAEAFkAawwAAAQAUQBqDAAAAwBKAGwMAAABACkAbQwAAAEAIgDqDAAABwBGAG4MAAABABYADgAICdEX6wMAYQIIaAwAAAUASQBpDAAABABZAGsMAAAEAFEAagwAAAMASgBsDAAAAQApAG0MAAABACIA6gwAAAcARgBuDAAAAQAWAC4ABAp/LgAEDgAICV0kPAQAKgMADgAICV0kPAQAKgMABwAFCQ0OoLQAGwEAGwACCYsIvD0ARwAAAAA=.',
Yu='Yulon:BAAALgAFFAEJAQABLgAFFAUJGgADAAQeAA==.',
Za='Zaraerivia:BAABLgAECn8ZAAIJAAYJZgk4jwAEAQZoDAAABQAVAGkMAAAFABoAawwAAAYAFwBqDAAAAgAoAGwMAAADABoA6gwAAAQAFgAJAAYJZgk4jwAEAQZoDAAABQAVAGkMAAAFABoAawwAAAYAFwBqDAAAAgAoAGwMAAADABoA6gwAAAQAFgAAAA==.Zarlon:BAAALgAECgMJBQABLgAECgYJGQAKAPQcAA==.',
Ze='Zengriff:BAABLgAECn8rAAIPAAkJ1iJAAwARAwloDAAABgBbAGkMAAAGAGEAawwAAAYAVwBqDAAABgBiAGwMAAAGAF0AbQwAAAMATQDqDAAABgBhAG4MAAADAFgAbwwAAAEAUAAPAAkJ1iJAAwARAwloDAAABgBbAGkMAAAGAGEAawwAAAYAVwBqDAAABgBiAGwMAAAGAF0AbQwAAAMATQDqDAAABgBhAG4MAAADAFgAbwwAAAEAUAAAAA==.Zerena:BAAALgAECgYJBgAAAA==.',
Zh='Zhule:BAABLgAECn8rAAIJAAkJ1h5UGQB2AgloDAAABgBSAGkMAAAGAEsAawwAAAYASgBqDAAABgBXAGwMAAAGAF8AbQwAAAMARgDqDAAABgBbAG4MAAADAFMAbwwAAAEAOgAJAAkJ1h5UGQB2AgloDAAABgBSAGkMAAAGAEsAawwAAAYASgBqDAAABgBXAGwMAAAGAF8AbQwAAAMARgDqDAAABgBbAG4MAAADAFMAbwwAAAEAOgAAAA==.',
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
