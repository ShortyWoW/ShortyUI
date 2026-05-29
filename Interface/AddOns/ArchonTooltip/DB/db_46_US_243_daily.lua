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
local provider = {region='US',realm='Ysondre',name='US',type='daily',zone=46,date='2026-05-28',data={Ak='Akari:BAAALgADCgEJAQAAAA==.',
Al='Alex:BAAALgADCgMJAwAAAA==.',
An='Angalius:BAAALgAECggJCwAAAA==.',
Ap='Apathy:BAAALgAECgIJBAAAAA==.',
Ar='Aralid:BAABLgAECn8WAAIBAAcJ6SIEHwBbAgdoDAAAAwBfAGkMAAADAFoAawwAAAMATwBqDAAAAgBgAGwMAAABAFQA6gwAAAYAWwBuDAAABABeAAEABwnpIgQfAFsCB2gMAAADAF8AaQwAAAMAWgBrDAAAAwBPAGoMAAACAGAAbAwAAAEAVADqDAAABgBbAG4MAAAEAF4AAAA=.Ariadné:BAABLgAECn8YAAMCAAgJFx3+DgBaAghoDAAABABHAGkMAAADAEYAawwAAAMATgBqDAAAAwBcAGwMAAACAEgAbQwAAAEASQDqDAAABQBDAG4MAAADAEYAAgAICRcd/g4AWgIIaAwAAAMARwBpDAAAAwBGAGsMAAADAE4AagwAAAMAXABsDAAAAgBIAG0MAAABAEkA6gwAAAQAQwBuDAAAAwBGAAMAAglMCfNzAFgAAmgMAAABACsA6gwAAAEABAAAAA==.Artasha:BAAALgADCgIJAwAAAA==.',
Ba='Badassmf:BAAALgADCgIJAgAAAA==.',
Be='Bearlover:BAAALgAECgcJDwAAAA==.Beau:BAAALgAECgQJBAAAAA==.Belal:BAAALgADCgIJAgAAAA==.',
Bi='Birdflù:BAAALgADCgUJBQAAAA==.Biscuits:BAAALgADCgYJBgAAAA==.',
Bo='Bomi:BAAALgAECgIJAwAAAA==.Boogiesera:BAAALgADCgQJBAABLgAECgcJEwAEAAAAAA==.Bootles:BAAALgAECgcJEwAAAA==.Bowl:BAAALgADCgkJDAAAAA==.',
Br='Brad:BAABLgAFFH8FAAMFAAQJ2R9lXAAhAQRoDAAAAQBdAGoMAAABAC4AbAwAAAEAWgDqDAAAAgA8AAUABAnZH2VcACEBBGgMAAABAF0AagwAAAEALgBsDAAAAQBaAOoMAAABADwABgABCTMHYR4APQAB6gwAAAEAEgAAAA==.Brewslee:BAAALgAECgkJAQAAAA==.',
Bu='Bulltastich:BAAALgADCgUJBgABLgADCgcJBwAEAAAAAA==.Bullwings:BAAALgAECgEJAQAAAA==.Buttholemu:BAAALgADCgYJBgAAAA==.',
Ca='Calanthe:BAAALgAECgYJBwAAAA==.',
Ch='Charrend:BAABLgAECn8lAAIHAAgJQAVjtQD4AAhoDAAABwATAGkMAAAGABEAawwAAAYADQBqDAAABQASAGwMAAAFABIAbQwAAAEACQDqDAAABQAJAG4MAAACAAYABwAICUAFY7UA+AAIaAwAAAcAEwBpDAAABgARAGsMAAAGAA0AagwAAAUAEgBsDAAABQASAG0MAAABAAkA6gwAAAUACQBuDAAAAgAGAAAA.',
Cl='Clutchmedic:BAABLgAFFH8IAAMIAAUJEQw2EAAwAQVoDAAAAwA7AGkMAAACABMAawwAAAEAFABqDAAAAQAaAOoMAAABABcACAAECX8NNhAAMAEEaAwAAAMAOwBrDAAAAQAUAGoMAAABABoA6gwAAAEAFwAJAAEJxwc3JgBVAAFpDAAAAgATAAAA.',
Co='Completed:BAAALgADCgUJBQAAAA==.',
Cp='Cptloveme:BAABLgAECn8eAAIKAAYJaRpolwCmAQZoDAAABgBWAGkMAAAGAEUAawwAAAUANgBqDAAABQAxAGwMAAADADoA6gwAAAUARAAKAAYJaRpolwCmAQZoDAAABgBWAGkMAAAGAEUAawwAAAUANgBqDAAABQAxAGwMAAADADoA6gwAAAUARAAAAA==.',
Cr='Crazon:BAAALgAECgMJAwAAAA==.Cropduster:BAACLgAFFH8RAAILAAQJ0g8xPQARAQRoDAAABgAkAGkMAAAEACsAawwAAAIADQDqDAAABQBFAAsABAnSDzE9ABEBBGgMAAAGACQAaQwAAAQAKwBrDAAAAgANAOoMAAAFAEUALgAECn8fAAMLAAkJHRfDNQAgAgALAAgJ3hnDNQAgAgAMAAEJ2QPVLQAyAAAAAA==.Crushed:BAAALgADCgMJAwABLgAECggJIgABAPkcAA==.',
Ct='Cthulhu:BAACLgAFFH8bAAIBAAQJRhs5LgBbAQRoDAAACABMAGkMAAAFAFEAawwAAAYALgDqDAAACABKAAEABAlGGzkuAFsBBGgMAAAIAEwAaQwAAAUAUQBrDAAABgAuAOoMAAAIAEoALgAECn8vAAIBAAgJzx6zHQCkAgABAAgJzx6zHQCkAgAAAA==.',
Cu='Cursedpriest:BAAALgADCgUJBQAAAA==.',
Da='Dad:BAAALgAECgEJAgAAAA==.Darner:BAAALgAECgQJBAAAAA==.',
De='Delnarei:BAAALgADCgEJAQAAAA==.Demise:BAAALgADCgYJCgABLgAFFAMJCAANAC0NAA==.Destiniemonk:BAAALgAFFAEJAQABLgAFFAQJDgAOANYjAA==.Deviant:BAAALgADCgkJDQAAAA==.',
Di='Diosito:BAAALgAECgYJCwAAAA==.',
Do='Dolo:BAAALgADCgIJAgAAAA==.Doloni:BAAALgAECgUJDAAAAA==.Doomd:BAEALgAECgcJEQAAAA==.Doomdtrooper:BAEALgAECgcJDgABLgAECgcJEQAEAAAAAA==.Dotti:BAAALgADCgkJCQABLgAECggJJwAJAIkMAA==.Dotts:BAABLgAECn8dAAIBAAcJ9RJPbgBRAQdoDAAABQBGAGkMAAAFADwAawwAAAUAIgBqDAAABABUAGwMAAAEACsAbQwAAAEAFgDqDAAABQA9AAEABwn1Ek9uAFEBB2gMAAAFAEYAaQwAAAUAPABrDAAABQAiAGoMAAAEAFQAbAwAAAQAKwBtDAAAAQAWAOoMAAAFAD0AAAA=.',
Dr='Drewied:BAAALgADCgEJAQAAAA==.Drfinger:BAAALgAECgMJAwABLgAECgkJKwAPAOslAA==.Droodorei:BAAALgADCggJJAAAAA==.',
Du='Durianz:BAAALgAECgYJCwAAAA==.',
Dw='Dwnloadedchi:BAAALgAECggJDQAAAA==.Dwnloadedski:BAAALgAECgcJEgAAAA==.',
Eg='Eggenan:BAAALgAECgUJAQAAAA==.',
Ei='Eiskält:BAABLgAECn8bAAIKAAgJTQcYmwAmAQhoDAAABQAIAGkMAAAEABIAawwAAAQAEwBqDAAABAAMAGwMAAAFAAYAbQwAAAIAEADqDAAAAgAmAG4MAAABABYACgAICU0HGJsAJgEIaAwAAAUACABpDAAABAASAGsMAAAEABMAagwAAAQADABsDAAABQAGAG0MAAACABAA6gwAAAIAJgBuDAAAAQAWAAAA.',
El='Ellay:BAABLgAECn8eAAIQAAcJqhKRPgCCAQdoDAAABQBFAGkMAAAFAC0AawwAAAUAKgBqDAAABAAfAGwMAAADADMAbQwAAAIAMADqDAAABgAtABAABwmqEpE+AIIBB2gMAAAFAEUAaQwAAAUALQBrDAAABQAqAGoMAAAEAB8AbAwAAAMAMwBtDAAAAgAwAOoMAAAGAC0AAAA=.',
Em='Emofumu:BAAALgADCgYJBgABLgAFFAMJBQARAN0hAA==.',
En='Endrin:BAAALgAECgYJDAAAAA==.',
Ew='Eww:BAEBLgAECn85AAISAAkJkxgOCACOAgloDAAACQBZAGkMAAAIAFAAawwAAAgAVwBqDAAACABVAGwMAAAHAEgAbQwAAAQAGADqDAAACABZAG4MAAADACcAbwwAAAIAEwASAAkJkxgOCACOAgloDAAACQBZAGkMAAAIAFAAawwAAAgAVwBqDAAACABVAGwMAAAHAEgAbQwAAAQAGADqDAAACABZAG4MAAADACcAbwwAAAIAEwAAAA==.',
Ez='Ezzak:BAAALgADCgQJBAAAAA==.',
Fe='Felfirefoxxo:BAAALgAFFAIJAgAAAA==.Felldeeds:BAABLgAECn8kAAIQAAgJlSWSBABhAwhoDAAABwBhAGkMAAAHAGMAawwAAAYAYQBqDAAAAgBgAGwMAAADAGEAbQwAAAIAWwDqDAAACABhAG4MAAABAFoAEAAICZUlkgQAYQMIaAwAAAcAYQBpDAAABwBjAGsMAAAGAGEAagwAAAIAYABsDAAAAwBhAG0MAAACAFsA6gwAAAgAYQBuDAAAAQBaAAAA.Fellphist:BAAALgAECgIJAgABLgAECggJJAAQAJUlAA==.Fellshock:BAAALgAECgYJCwABLgAECggJJAAQAJUlAA==.Felthazzar:BAAALgAECgYJBgAAAA==.Fent:BAACLgAFFH8SAAMTAAUJQw9UHwADAQVoDAAABQApAGkMAAAFACkAawwAAAMAKwBqDAAAAQAkAOoMAAAEAB0AEwAFCUMPVB8AAwEFaAwAAAUAKQBpDAAABQApAGsMAAACACsAagwAAAEAJADqDAAABAAdABQAAQlEC8BpADwAAWsMAAABABwALgAECn8sAAMTAAkJiByAGABRAgATAAcJayCAGABRAgAUAAkJQRfxIAAZAgAAAA==.Fey:BAAALgAECgQJBQAAAA==.',
Fi='Fingerblastn:BAAALgADCgcJBwABLgAECgkJKwAPAOslAA==.Fingerr:BAABLgAECn8rAAIPAAkJ6yWsAABuAwloDAAABwBjAGkMAAAGAGMAawwAAAYAYQBqDAAABgBjAGwMAAAFAGMAbQwAAAEAVADqDAAABwBjAG4MAAAEAGMAbwwAAAEAYQAPAAkJ6yWsAABuAwloDAAABwBjAGkMAAAGAGMAawwAAAYAYQBqDAAABgBjAGwMAAAFAGMAbQwAAAEAVADqDAAABwBjAG4MAAAEAGMAbwwAAAEAYQAAAA==.Finneagan:BAAALgADCgEJAQAAAA==.',
Fl='Flinkorandus:BAAALgAECgEJAgABLgAECgcJFgABAOkiAA==.Flokki:BAAALgAECgcJDwAAAA==.',
Fo='Foxxowo:BAABLgAFFH8FAAIQAAMJogXEPwCiAANoDAAAAgATAGkMAAACABAA6gwAAAEABgAQAAMJogXEPwCiAANoDAAAAgATAGkMAAACABAA6gwAAAEABgAAAA==.',
Fr='Froztbane:BAEALgAECgcJDwABLgAECgkJQwALAK8gAA==.Froztbanshee:BAEBLgAECn9DAAILAAkJryClDAAbAwloDAAACgBbAGkMAAAKAFkAawwAAAoAVgBqDAAACgBRAGwMAAAHAFwAbQwAAAUAWADqDAAACgBeAG4MAAAEAFEAbwwAAAEALAALAAkJryClDAAbAwloDAAACgBbAGkMAAAKAFkAawwAAAoAVgBqDAAACgBRAGwMAAAHAFwAbQwAAAUAWADqDAAACgBeAG4MAAAEAFEAbwwAAAEALAAAAA==.',
Fy='Fynger:BAAALgAECgUJCgABLgAECgkJKwAPAOslAA==.',
Gh='Ghats:BAAALgAECgEJAQAAAA==.Ghuss:BAAALgAECgcJBwAAAA==.',
Gl='Glass:BAAALgAECgYJEQAAAA==.',
Go='Gogo:BAAALgAECgYJDAAAAA==.',
Gr='Grimzyn:BAACLgAFFH8PAAIFAAUJvxTWUwAuAQVoDAAABABZAGkMAAAEACwAawwAAAMAJQBqDAAAAQAEAOoMAAADACkABQAFCb8U1lMALgEFaAwAAAQAWQBpDAAABAAsAGsMAAADACUAagwAAAEABADqDAAAAwApAC4ABAp/HAACBQAICWMcwDYAXAIABQAICWMcwDYAXAIAAAA=.Grudge:BAABLgAECn83AAMFAAkJNBJ/RADeAQloDAAACAAtAGkMAAAHADcAawwAAAcAMABqDAAABwAtAGwMAAAHADYAbQwAAAUAHwDqDAAACAAuAG4MAAAFACwAbwwAAAEALgAFAAkJ8hB/RADeAQloDAAABgAtAGkMAAAFADEAawwAAAUAHgBqDAAABQAqAGwMAAAFADYAbQwAAAMAHwDqDAAABgAsAG4MAAADACwAbwwAAAEALgAGAAgJTBC/BQDVAQhoDAAAAgAhAGkMAAACADcAawwAAAIAMABqDAAAAgAtAGwMAAACACkAbQwAAAIAGADqDAAAAgAuAG4MAAACACoAAAA=.',
Ha='Haircules:BAAALgAECgUJCwAAAA==.Harrowhark:BAACLgAFFH8MAAIFAAQJ2R7FKACGAQRoDAAABABZAGkMAAADAFYAawwAAAEAMADqDAAABABaAAUABAnZHsUoAIYBBGgMAAAEAFkAaQwAAAMAVgBrDAAAAQAwAOoMAAAEAFoALgAECn8uAAMFAAgJniOMFQCxAgAFAAgJniOMFQCxAgAGAAEJ3BrIKABOAAAAAA==.',
He='Herambae:BAAALgADCgYJBgAAAA==.Herculesátan:BAAALgADCgYJCAAAAA==.',
Ho='Hornstache:BAAALgADCgEJAQAAAA==.',
Hy='Hyacinth:BAABLgAECn8sAAIVAAkJhBaMEgAoAgloDAAABgBGAGkMAAAGAEEAawwAAAYALQBqDAAABQAnAGwMAAAEAEQAbQwAAAIANgDqDAAABgBOAG4MAAAFACsAbwwAAAQAIgAVAAkJhBaMEgAoAgloDAAABgBGAGkMAAAGAEEAawwAAAYALQBqDAAABQAnAGwMAAAEAEQAbQwAAAIANgDqDAAABgBOAG4MAAAFACsAbwwAAAQAIgAAAA==.Hyria:BAAALgADCgkJDwABLgAECgcJEwAEAAAAAA==.Hyun:BAAALgADCgYJBgAAAA==.',
Ia='Iamfinn:BAAALgAECgEJAQAAAA==.Iamomegafox:BAACLgAFFH8LAAIWAAMJaBxlHAAQAQNoDAAABABQAGkMAAADACwA6gwAAAQAXQAWAAMJaBxlHAAQAQNoDAAABABQAGkMAAADACwA6gwAAAQAXQAuAAQKfzAAAxYACQlGGj0OACkCABYACQnCGD0OACkCABcABgnxF+QLAGgBAAAA.',
Ig='Iggylock:BAAALgADCgYJBgAAAA==.Ignax:BAACLgAFFH8NAAMYAAYJIQiUDwBwAQZoDAAAAwAQAGkMAAADABAAawwAAAEAJgBqDAAAAQATAGwMAAABABMA6gwAAAQADgAYAAYJIQiUDwBwAQZoDAAAAgAQAGkMAAADABAAawwAAAEAJgBqDAAAAQATAGwMAAABABMA6gwAAAQADgAZAAEJWgUVCwBNAAFoDAAAAQANAC4ABAp/IQADGAAICRAVUBQAAQIAGAAICRAVUBQAAQIAGQAGCVYIXiUA+gAAAAA=.',
Im='Imomeganisha:BAAALgAECgQJBwABLgAFFAMJCwAWAGgcAA==.Imsparticus:BAABLgAECn8VAAMaAAYJxgjMVQDZAAZoDAAABAAkAGkMAAAEAB0AawwAAAQAGABqDAAAAwAPAGwMAAACAAYA6gwAAAQADwAaAAYJxgjMVQDZAAZoDAAAAwAkAGkMAAADAB0AawwAAAMAGABqDAAAAwAPAGwMAAACAAYA6gwAAAMADwARAAQJcAHROwBtAARoDAAAAQABAGkMAAABAAEAawwAAAEABwDqDAAAAQAEAAAA.',
Io='Ionias:BAABLgAECn8jAAQbAAkJ5Bb7FwBXAQloDAAABQAsAGkMAAAFAFAAawwAAAUASABqDAAABAAXAGwMAAAEADYAbQwAAAMAYQDqDAAABQBGAG4MAAADABYAbwwAAAEAGwAbAAYJERn7FwBXAQZoDAAAAQAsAGkMAAABAFAAawwAAAEASABqDAAAAQAXAGwMAAABADYA6gwAAAEARgAOAAgJuQgpNwBVAQhoDAAABAAPAGkMAAAEABMAawwAAAQAEwBqDAAAAwARAGwMAAADABoAbQwAAAMAFADqDAAABAA1AG4MAAACAAUABwACCeMJzhsBbQACbgwAAAEAFgBvDAAAAQAbAAAA.',
Ja='Jackblack:BAAALgAECgIJBAABLgAFFAQJEQALANIPAA==.Jaquelius:BAAALgAECgUJDgAAAA==.',
Jo='Joeworgen:BAAALgAECgEJAQAAAA==.Johadan:BAABLgAECn8aAAIHAAcJ7QdutQD3AAdoDAAABAARAGkMAAAEABIAawwAAAQAFwBqDAAAAwATAGwMAAAEABEA6gwAAAYADgBuDAAAAQAdAAcABwntB261APcAB2gMAAAEABEAaQwAAAQAEgBrDAAABAAXAGoMAAADABMAbAwAAAQAEQDqDAAABgAOAG4MAAABAB0AAAA=.',
Ka='Kade:BAAALgADCgEJAgAAAA==.Kaelx:BAAALgAECgQJCAAAAA==.Kafizz:BAABLgAECn8fAAIBAAkJWxXKPgASAgloDAAABQAsAGkMAAAGAFoAawwAAAYAUABqDAAAAwBOAGwMAAADAEUAbQwAAAEAHwDqDAAAAwAsAG4MAAADADcAbwwAAAEAFgABAAkJWxXKPgASAgloDAAABQAsAGkMAAAGAFoAawwAAAYAUABqDAAAAwBOAGwMAAADAEUAbQwAAAEAHwDqDAAAAwAsAG4MAAADADcAbwwAAAEAFgAAAA==.Kagnara:BAAALgADCgUJBQABLgAFFAQJDAAFANkeAA==.',
Ke='Keely:BAAALgAECgUJCwAAAA==.Keolmont:BAAALgADCgEJAQAAAA==.',
Ki='Kinla:BAAALgAECgQJBAAAAA==.Kirakitsune:BAAALgAECgEJAQAAAA==.Kireag:BAAALgADCgIJAgAAAA==.',
Ko='Kooppa:BAAALgADCgQJBAAAAA==.',
Ku='Kuromigirl:BAABLgAECn8WAAILAAcJ0BLvYgBGAQdoDAAAAwAvAGkMAAADADgAawwAAAMAMgBqDAAAAgAwAGwMAAABADQA6gwAAAYALgBuDAAABAAjAAsABwnQEu9iAEYBB2gMAAADAC8AaQwAAAMAOABrDAAAAwAyAGoMAAACADAAbAwAAAEANADqDAAABgAuAG4MAAAEACMAAAA=.',
La='Labchimpette:BAAALgAECgYJDgAAAA==.Lagerthä:BAAALgAECgcJEwABLgAECgkJJAAQADkaAA==.',
Li='Link:BAAALgAECgYJBgAAAA==.Lione:BAABLgAECn8UAAMQAAcJ8hi0LwDtAQdoDAAABAAyAGkMAAADAFUAawwAAAMAUABqDAAAAgBUAGwMAAABAEQA6gwAAAUAOQBuDAAAAgAUABAABwnyGLQvAO0BB2gMAAADADIAaQwAAAMAVQBrDAAAAwBQAGoMAAACAFQAbAwAAAEARADqDAAABAA5AG4MAAACABQAFQACCWAING8ATQACaAwAAAEAGgDqDAAAAQAQAAAA.Lith:BAACLgAFFH8HAAIYAAMJgRTnDQD9AANoDAAAAwBEAGsMAAACABsA6gwAAAIAPQAYAAMJgRTnDQD9AANoDAAAAwBEAGsMAAACABsA6gwAAAIAPQAuAAQKfycAAxgACAmtGekJAC8CABgACAmtGekJAC8CAA0ACAlgEL4dANcBAAAA.Litterbocks:BAAALgAECgMJBAAAAA==.Littlepriest:BAAALgADCgEJAQAAAA==.',
Ly='Lyzandra:BAAALgADCgYJCgAAAA==.',
['Lì']='Lìllyanna:BAABLgAECn8pAAIbAAkJbxPSDQDHAQloDAAABwA1AGkMAAAGADEAawwAAAYARABqDAAAAwAfAGwMAAADACQAbQwAAAIAGADqDAAACABDAG4MAAAEAD0AbwwAAAIAJAAbAAkJbxPSDQDHAQloDAAABwA1AGkMAAAGADEAawwAAAYARABqDAAAAwAfAGwMAAADACQAbQwAAAIAGADqDAAACABDAG4MAAAEAD0AbwwAAAIAJAAAAA==.',
Ma='Mailbox:BAAALgAECgYJBgABLgAFFAgJIgAOAA8iAA==.Malion:BAAALgAECgEJAQAAAA==.Malock:BAAALgADCgkJCQAAAA==.Mango:BAAALgAECgIJAwAAAA==.Matcha:BAABLgAECn8jAAIcAAkJjxzYCQDWAgloDAAABAA7AGkMAAAEAEkAawwAAAQAUABqDAAABABOAGwMAAADADsAbQwAAAIASQDqDAAABQBSAG4MAAAFAEkAbwwAAAQASwAcAAkJjxzYCQDWAgloDAAABAA7AGkMAAAEAEkAawwAAAQAUABqDAAABABOAGwMAAADADsAbQwAAAIASQDqDAAABQBSAG4MAAAFAEkAbwwAAAQASwAAAA==.Mauler:BAAALgAECgQJCAAAAA==.',
Me='Melinoë:BAAALgADCgUJBQAAAA==.Meowhunter:BAAALgAECgUJCgAAAA==.',
Mi='Miaraa:BAAALgAECgcJEAAAAA==.Minervå:BAAALgADCgMJAwAAAA==.',
Mo='Mogdor:BAABLgAECn8mAAMNAAkJvBm/EABCAgloDAAABQBaAGkMAAAFAEsAawwAAAUAUQBqDAAABgBIAGwMAAAGAEoAbQwAAAIAQADqDAAABQBBAG4MAAADACAAbwwAAAEAKQANAAkJvBm/EABCAgloDAAABQBaAGkMAAAFAEsAawwAAAUAUQBqDAAABQBIAGwMAAAFAEoAbQwAAAIAQADqDAAABABBAG4MAAADACAAbwwAAAEAKQAZAAMJZBRuLAC4AANqDAAAAQAvAGwMAAABADkA6gwAAAEALgAAAA==.Moonpeach:BAABLgAECn8dAAIQAAcJQhChQwBqAQdoDAAABgBNAGkMAAAGABcAawwAAAYAQgBqDAAAAwApAGwMAAACACcAbQwAAAEAEADqDAAABQAaABAABwlCEKFDAGoBB2gMAAAGAE0AaQwAAAYAFwBrDAAABgBCAGoMAAADACkAbAwAAAIAJwBtDAAAAQAQAOoMAAAFABoAAAA=.Motex:BAABLgAECn8eAAIWAAgJ/AKFMwBvAQhoDAAABAAIAGkMAAAEAAgAawwAAAQADQBqDAAABAAJAGwMAAAEAAkAbQwAAAMABQDqDAAABAAFAG4MAAADAAIAFgAICfwChTMAbwEIaAwAAAQACABpDAAABAAIAGsMAAAEAA0AagwAAAQACQBsDAAABAAJAG0MAAADAAUA6gwAAAQABQBuDAAAAwACAAAA.',
Na='Naturebug:BAAALgAECgYJCgAAAA==.',
Ne='Neature:BAAALgAFFAEJAQABLgAFFAQJEQALANIPAA==.Ned:BAECLgAFFH8TAAIaAAUJDyV8CACbAQVoDAAABQBcAGkMAAAFAGMAawwAAAQAXwBqDAAAAgBPAOoMAAADAFwAGgAFCQ8lfAgAmwEFaAwAAAUAXABpDAAABQBjAGsMAAAEAF8AagwAAAIATwDqDAAAAwBcAC4ABAp/TwADGgAJCR0mpQAAfQMAGgAJCR0mpQAAfQMAHQAECWUkhg8AowEAAAA=.Netre:BAAALgAECgYJEQAAAA==.',
Ni='Nimbus:BAAALgAFFAMJAgABLgAFFAgJGAANAIUWAA==.Ninax:BAAALgAECgYJCgAAAA==.',
Ny='Nylian:BAAALgAECgQJCgAAAA==.',
Ob='Obamasmama:BAAALgAFFAIJAgAAAA==.',
Oc='Octomore:BAAALgAFFAEJAgAAAA==.',
Ol='Oldmantom:BAAALgADCgYJBgAAAA==.',
Or='Ormgorg:BAABLgAECn8VAAIeAAcJ9R2UDADFAQdoDAAAAwBTAGkMAAADAF0AawwAAAMATQBqDAAAAwBXAGwMAAACAE8A6gwAAAUAUgBuDAAAAgAqAB4ABwn1HZQMAMUBB2gMAAADAFMAaQwAAAMAXQBrDAAAAwBNAGoMAAADAFcAbAwAAAIATwDqDAAABQBSAG4MAAACACoAAAA=.Orpheus:BAABLgAECn9HAAQUAAkJRCIPBABfAwloDAAACgBSAGkMAAAKAFwAawwAAAoAYQBqDAAACQBfAGwMAAAIAFoAbQwAAAUAVwDqDAAACQBNAG4MAAAGAEwAbwwAAAQAWAAUAAkJRCIPBABfAwloDAAABwBSAGkMAAAHAFwAawwAAAcAYQBqDAAACABfAGwMAAAHAFoAbQwAAAUAVwDqDAAACABNAG4MAAAGAEwAbwwAAAQAWAATAAUJ7hczRQD9AAVoDAAAAgBOAGkMAAACADEAawwAAAIANABqDAAAAQBLAGwMAAABAEEAHgAECTsNCR8AzgAEaAwAAAEAJgBpDAAAAQAkAGsMAAABABYA6gwAAAEAJQAAAA==.',
Oz='Oza:BAAALgAECgMJBgAAAA==.',
Pa='Pandamoniium:BAAALgAECgcJDQAAAA==.Pandamonk:BAACLgAFFH8WAAIPAAUJyyWaCQC1AQVoDAAABgBjAGkMAAAGAGMAawwAAAQAWwBqDAAAAQBbAOoMAAAFAGEADwAFCcslmgkAtQEFaAwAAAYAYwBpDAAABgBjAGsMAAAEAFsAagwAAAEAWwDqDAAABQBhAC4ABAp/OgACDwAJCZglFAEAXAMADwAJCZglFAEAXAMAAAA=.',
Pe='Percy:BAEBLgAECn8bAAIfAAcJCxDFBQBQAQdoDAAABgAqAGkMAAAEADIAawwAAAQAMABqDAAABABJAGwMAAAEACAAbQwAAAEAEwDqDAAABAA1AB8ABwkLEMUFAFABB2gMAAAGACoAaQwAAAQAMgBrDAAABAAwAGoMAAAEAEkAbAwAAAQAIABtDAAAAQATAOoMAAAEADUAAAA=.',
Pi='Pickleswag:BAAALgAECgMJAwAAAA==.',
Pr='Preservation:BAAALgAECgMJAwAAAA==.',
Ra='Raastamon:BAAALgADCgEJAQAAAA==.Raekitty:BAABLgAECn8XAAIQAAgJgR6SFACRAghoDAAABABdAGkMAAAEAGAAawwAAAQAYQBqDAAAAwBQAGwMAAADAFsAbQwAAAEAHQDqDAAAAwBVAG4MAAABADIAEAAICYEekhQAkQIIaAwAAAQAXQBpDAAABABgAGsMAAAEAGEAagwAAAMAUABsDAAAAwBbAG0MAAABAB0A6gwAAAMAVQBuDAAAAQAyAAAA.Rama:BAAALgAECgMJBQABLgAECgYJGQAKAPQcAA==.',
Re='Redrover:BAAALgADCggJDgAAAA==.Reia:BAAALgADCgcJBwAAAA==.',
Rh='Rhara:BAAALgADCgYJEgAAAA==.Rhoem:BAACLgAFFH8HAAIGAAIJ9Qf9FQCIAAJoDAAABAARAGkMAAADABYABgACCfUH/RUAiAACaAwAAAQAEQBpDAAAAwAWAC4ABAp/KQADBgAJCUAdsQUA1wEABgAICcwfsQUA1wEAIAAHCQIYOBUAowEAAAA=.',
Ri='Rin:BAEALgADCgMJAwABLgAECgkJJwAcANshAA==.',
Ro='Roger:BAABLgAECn8iAAMOAAcJJSN5DACvAgdoDAAABwBhAGkMAAAHAF0AawwAAAYAWgBqDAAABgBYAGwMAAADAF8AbQwAAAEATwDqDAAABABVAA4ABwklI3kMAK8CB2gMAAAEAGEAaQwAAAYAXQBrDAAABQBaAGoMAAAFAFgAbAwAAAMAXwBtDAAAAQBPAOoMAAACAFUABwAFCSgNZOsArQAFaAwAAAMAJwBpDAAAAQAWAGsMAAABABIAagwAAAEALQDqDAAAAgA1AAAA.',
Ru='Rumor:BAACLgAFFH8hAAMXAAcJHyBYAABiAgdoDAAABQBjAGkMAAAHAGIAawwAAAYAUwBqDAAABABbAGwMAAACAFoAbQwAAAEAHQDqDAAACABaABcABwkfIFgAAGICB2gMAAAEAGMAaQwAAAUAYgBrDAAABQBTAGoMAAAEAFsAbAwAAAIAWgBtDAAAAQAdAOoMAAAGAFoAFgAECbEZdQcAbQEEaAwAAAEAOgBpDAAAAgBZAGsMAAABADoA6gwAAAIAOAAuAAQKfzkAAxcACAnJJmQBAOICABYACAnTJJcKAOkCABcACAmVJmQBAOICAAAA.Run:BAAALgAECgEJAQAAAA==.',
Se='Secretgrace:BAAALgADCgQJBAABLgAECgcJFQAeAPUdAA==.Seed:BAAALgAECgkJDgAAAA==.Senortickle:BAABLgAECn8XAAILAAcJWhUPTwB/AQdoDAAAAwBIAGkMAAAEADcAawwAAAUAKQBqDAAAAwAsAGwMAAAEAEYAbQwAAAEAIADqDAAAAwA4AAsABwlaFQ9PAH8BB2gMAAADAEgAaQwAAAQANwBrDAAABQApAGoMAAADACwAbAwAAAQARgBtDAAAAQAgAOoMAAADADgAAAA=.',
Sh='Shadowmoone:BAABLgAECn8nAAIJAAgJiQyyVACHAQhoDAAABwAnAGkMAAAHAB0AawwAAAUAFgBqDAAABAAaAGwMAAAFABgAbQwAAAIAGADqDAAABwA6AG4MAAACABkACQAICYkMslQAhwEIaAwAAAcAJwBpDAAABwAdAGsMAAAFABYAagwAAAQAGgBsDAAABQAYAG0MAAACABgA6gwAAAcAOgBuDAAAAgAZAAAA.Shaki:BAAALgAECgQJBwAAAA==.Shalendris:BAAALgAECgEJAQAAAA==.Shalestrasz:BAABLgAECn8XAAQZAAgJNQg0IQAjAQhoDAAAAwAIAGkMAAADABQAawwAAAMAGABqDAAAAwAJAGwMAAADABAAbQwAAAIACQDqDAAABAAyAG4MAAACABEAGQAICRcFNCEAIwEIaAwAAAMACABpDAAAAwAUAGsMAAADABgAagwAAAMACQBsDAAAAgAQAG0MAAABAAkA6gwAAAIACABuDAAAAQADAA0AAwkWCgVhAIoAA20MAAABAAkA6gwAAAEAMgBuDAAAAQARABgAAglVAU1FAEYAAmwMAAABAAQA6gwAAAEAAgAAAA==.Shibal:BAAALgADCggJCAAAAA==.Shinedown:BAAALgADCgQJBAAAAA==.Shochu:BAAALgAECgcJEAAAAA==.',
Sl='Sloane:BAAALgADCgQJBAAAAA==.',
So='Soju:BAAALgAECgUJBQAAAA==.Somnera:BAAALgAECgEJAQABLgAECgcJFQAeAPUdAA==.Soyboymalfoy:BAABLgAECn8WAAIDAAgJxBNVHgC6AQhoDAAABABFAGkMAAADAD4AawwAAAQAOABqDAAAAwAnAGwMAAACADQA6gwAAAMAPwBuDAAAAgApAG8MAAABABIAAwAICcQTVR4AugEIaAwAAAQARQBpDAAAAwA+AGsMAAAEADgAagwAAAMAJwBsDAAAAgA0AOoMAAADAD8AbgwAAAIAKQBvDAAAAQASAAAA.',
Sp='Sp:BAACLgAFFH8aAAIDAAUJBB7lBgCuAQVoDAAACQBEAGkMAAAFAD8AawwAAAQAWgBqDAAAAgBCAOoMAAAGAGAAAwAFCQQe5QYArgEFaAwAAAkARABpDAAABQA/AGsMAAAEAFoAagwAAAIAQgDqDAAABgBgAC4ABAp/RAADAwAICeIkSAMATQMAAwAICeIkSAMATQMAIQABCXkK5ngALwAAAAA=.',
St='Sterility:BAAALgAECgUJEAAAAA==.',
Sw='Switchfoot:BAACLgAFFH8IAAIiAAMJiR2wBQAVAQNoDAAAAwBcAGkMAAACADQA6gwAAAMAUQAiAAMJiR2wBQAVAQNoDAAAAwBcAGkMAAACADQA6gwAAAMAUQAuAAQKfzYAAyIACQlLIS8BAOICACIACQlLIS8BAOICABcAAQklE9sbAEkAAAAA.',
['Sï']='Sïeghart:BAAALgADCgUJBQAAAA==.',
Ta='Tallmanbeta:BAAALgAECgQJAgAAAA==.',
Te='Tenzin:BAAALgADCgQJBAABLgAFFAQJGwABAEYbAA==.Tex:BAAALgADCgcJDgAAAA==.',
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
Wi='Wither:BAACLgAFFH8FAAIFAAQJMhF2FQBOAQRoDAAAAQAZAGkMAAABAE0AawwAAAEAIgDqDAAAAgAmAAUABAkyEXYVAE4BBGgMAAABABkAaQwAAAEATQBrDAAAAQAiAOoMAAACACYALgAECn8eAAIFAAgJXSKeNQBgAgAFAAgJXSKeNQBgAgABLgAFFAcJIQAXAB8gAA==.',
Wy='Wyspur:BAAALgADCgYJCgAAAA==.',
Yo='Yofoxxo:BAACLgAFFH8aAAIOAAgJ0ReYAwBnAghoDAAABQBJAGkMAAAEAFkAawwAAAQAUQBqDAAAAwBKAGwMAAABACkAbQwAAAEAIgDqDAAABwBGAG4MAAABABYADgAICdEXmAMAZwIIaAwAAAUASQBpDAAABABZAGsMAAAEAFEAagwAAAMASgBsDAAAAQApAG0MAAABACIA6gwAAAcARgBuDAAAAQAWAC4ABAp/LgAEDgAICV0kPAQAKgMADgAICV0kPAQAKgMABwAFCQ0OoLQAGwEAGwACCYsIvD0ARwAAAAA=.',
Yu='Yulon:BAAALgAFFAEJAQABLgAFFAUJGgADAAQeAA==.',
Za='Zaraerivia:BAABLgAECn8ZAAIJAAYJZgmtjQAEAQZoDAAABQAVAGkMAAAFABoAawwAAAYAFwBqDAAAAgAoAGwMAAADABoA6gwAAAQAFgAJAAYJZgmtjQAEAQZoDAAABQAVAGkMAAAFABoAawwAAAYAFwBqDAAAAgAoAGwMAAADABoA6gwAAAQAFgAAAA==.Zarlon:BAAALgAECgMJBQABLgAECgYJGQAKAPQcAA==.',
Ze='Zengriff:BAABLgAECn8rAAIPAAkJ1iIsAwARAwloDAAABgBbAGkMAAAGAGEAawwAAAYAVwBqDAAABgBiAGwMAAAGAF0AbQwAAAMATQDqDAAABgBhAG4MAAADAFgAbwwAAAEAUAAPAAkJ1iIsAwARAwloDAAABgBbAGkMAAAGAGEAawwAAAYAVwBqDAAABgBiAGwMAAAGAF0AbQwAAAMATQDqDAAABgBhAG4MAAADAFgAbwwAAAEAUAAAAA==.Zerena:BAAALgAECgYJBgAAAA==.',
Zh='Zhule:BAABLgAECn8rAAIJAAkJ1h6PGAB3AgloDAAABgBSAGkMAAAGAEsAawwAAAYASgBqDAAABgBXAGwMAAAGAF8AbQwAAAMARgDqDAAABgBbAG4MAAADAFMAbwwAAAEAOgAJAAkJ1h6PGAB3AgloDAAABgBSAGkMAAAGAEsAawwAAAYASgBqDAAABgBXAGwMAAAGAF8AbQwAAAMARgDqDAAABgBbAG4MAAADAFMAbwwAAAEAOgAAAA==.',
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
