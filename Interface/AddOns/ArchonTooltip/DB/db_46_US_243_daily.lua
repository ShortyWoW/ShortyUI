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

local lookup = {'Priest-Discipline','Priest-Holy','Unknown-Unknown','Paladin-Retribution','Hunter-Marksmanship','Hunter-BeastMastery','Mage-Frost','DemonHunter-Devourer','Warlock-Demonology','Paladin-Holy','Monk-Brewmaster','Druid-Restoration','Warrior-Protection','Hunter-Survival','Shaman-Elemental','Shaman-Restoration','DeathKnight-Unholy','DeathKnight-Frost','Druid-Balance','Rogue-Subtlety','Rogue-Assassination','Evoker-Preservation','Evoker-Devastation','Warrior-Fury','Paladin-Protection','Evoker-Augmentation','Monk-Mistweaver','Warrior-Arms','Shaman-Enhancement','Mage-Arcane','DeathKnight-Blood','Priest-Shadow','Rogue-Outlaw','Monk-Windwalker',}
local provider = {region='US',realm='Ysondre',name='US',type='daily',zone=46,date='2026-05-20',data={Ak='Akari:BAAALgADCgEJAQAAAA==.',
Al='Alex:BAAALgADCgMJAwAAAA==.',
An='Angalius:BAAALgAECgYJCgAAAA==.',
Ap='Apathy:BAAALgAECgIJAwAAAA==.',
Ar='Aralid:BAAALgAECgYJEQAAAA==.Ariadné:BAABLgAECn8YAAMBAAgJGR2yDABpAghoDAAABABHAGkMAAADAEYAawwAAAMATgBqDAAAAwBcAGwMAAACAEgAbQwAAAEASQDqDAAABQBDAG4MAAADAEYAAQAICRkdsgwAaQIIaAwAAAMARwBpDAAAAwBGAGsMAAADAE4AagwAAAMAXABsDAAAAgBIAG0MAAABAEkA6gwAAAQAQwBuDAAAAwBGAAIAAglMCfNzAFgAAmgMAAABACsA6gwAAAEABAAAAA==.Artasha:BAAALgADCgIJAwAAAA==.',
Ba='Badassmf:BAAALgADCgIJAgAAAA==.',
Be='Bearlover:BAAALgAECgcJDwAAAA==.Beau:BAAALgAECgQJBAAAAA==.Belal:BAAALgADCgIJAgAAAA==.',
Bi='Birdflù:BAAALgADCgUJBQAAAA==.Biscuits:BAAALgADCgYJBgAAAA==.',
Bo='Bomi:BAAALgAECgIJAwAAAA==.Boogiesera:BAAALgADCgQJBAABLgAECgcJEwADAAAAAA==.Bootles:BAAALgAECgcJEwAAAA==.Bowl:BAAALgADCgkJDAAAAA==.',
Br='Brewslee:BAAALgAECgkJAQAAAA==.',
Bu='Bulltastich:BAAALgADCgUJBgABLgADCgcJBwADAAAAAA==.Bullwings:BAAALgAECgEJAQAAAA==.Buttholemu:BAAALgADCgYJBgAAAA==.',
Ca='Calanthe:BAAALgAECgYJBwAAAA==.',
Ch='Charrend:BAABLgAECn8gAAIEAAgJQAUSnQARAQhoDAAABgATAGkMAAAFABEAawwAAAUADQBqDAAABAASAGwMAAAEABIAbQwAAAEACQDqDAAABQAJAG4MAAACAAYABAAICUAFEp0AEQEIaAwAAAYAEwBpDAAABQARAGsMAAAFAA0AagwAAAQAEgBsDAAABAASAG0MAAABAAkA6gwAAAUACQBuDAAAAgAGAAAA.',
Cl='Clutchmedic:BAABLgAFFH8IAAMFAAUJEQw2EAAwAQVoDAAAAwA7AGkMAAACABMAawwAAAEAFABqDAAAAQAaAOoMAAABABcABQAECX8NNhAAMAEEaAwAAAMAOwBrDAAAAQAUAGoMAAABABoA6gwAAAEAFwAGAAEJxwc3JgBVAAFpDAAAAgATAAAA.',
Co='Codus:BAAALgADCgEJAQAAAA==.Completed:BAAALgADCgUJBQAAAA==.',
Cp='Cptloveme:BAABLgAECn8eAAIHAAYJaRpolwCmAQZoDAAABgBWAGkMAAAGAEUAawwAAAUANgBqDAAABQAxAGwMAAADADoA6gwAAAUARAAHAAYJaRpolwCmAQZoDAAABgBWAGkMAAAGAEUAawwAAAUANgBqDAAABQAxAGwMAAADADoA6gwAAAUARAAAAA==.',
Cr='Crazon:BAAALgAECgMJAwAAAA==.Cropduster:BAACLgAFFH8OAAIIAAQJmgz8NwALAQRoDAAABQAkAGkMAAADAAoAawwAAAIADQDqDAAABABFAAgABAmaDPw3AAsBBGgMAAAFACQAaQwAAAMACgBrDAAAAgANAOoMAAAEAEUALgAECn8eAAIIAAgJ3hnDNQAgAgAIAAgJ3hnDNQAgAgAAAA==.Crushed:BAAALgADCgMJAwABLgAECggJIgAJAPYcAA==.',
Ct='Cthulhu:BAACLgAFFH8WAAIJAAQJMhikMwAyAQRoDAAABwBGAGkMAAAEADwAawwAAAUALgDqDAAABgBGAAkABAkyGKQzADIBBGgMAAAHAEYAaQwAAAQAPABrDAAABQAuAOoMAAAGAEYALgAECn8vAAIJAAgJzx6zHQCkAgAJAAgJzx6zHQCkAgAAAA==.',
Cu='Cursedpriest:BAAALgADCgUJBQAAAA==.',
Da='Dad:BAAALgAECgEJAgAAAA==.Darner:BAAALgAECgQJBAAAAA==.',
De='Delnarei:BAAALgADCgEJAQAAAA==.Demise:BAAALgADCgYJCgABLgAECggJHwAHALkdAA==.Destiniemonk:BAAALgAECgYJCwABLgAFFAMJCgAKAEYmAA==.Deviant:BAAALgADCgcJBwAAAA==.',
Di='Diosito:BAAALgAECgYJBgAAAA==.',
Do='Dolo:BAAALgADCgIJAgAAAA==.Doloni:BAAALgAECgUJDAAAAA==.Doomd:BAEALgAECgcJEQAAAA==.Doomdtrooper:BAEALgAECgcJDgABLgAECgcJEQADAAAAAA==.Dotti:BAAALgADCgkJCQABLgAECggJIwAGAPwJAA==.Dotts:BAABLgAECn8dAAIJAAcJ8hLaYwBXAQdoDAAABQBGAGkMAAAFADwAawwAAAUAIgBqDAAABABUAGwMAAAEACsAbQwAAAEAFQDqDAAABQA9AAkABwnyEtpjAFcBB2gMAAAFAEYAaQwAAAUAPABrDAAABQAiAGoMAAAEAFQAbAwAAAQAKwBtDAAAAQAVAOoMAAAFAD0AAAA=.',
Dr='Drewied:BAAALgADCgEJAQAAAA==.Drfinger:BAAALgAECgEJAQABLgAECgkJKgALAL4lAA==.Droodorei:BAAALgADCggJJAAAAA==.',
Du='Durianz:BAAALgAECgYJCwAAAA==.',
Dw='Dwnloadedchi:BAAALgAECggJDQAAAA==.Dwnloadedski:BAAALgAECgcJEgAAAA==.',
Eg='Eggenan:BAAALgAECgUJAQAAAA==.',
Ei='Eiskält:BAABLgAECn8VAAIHAAcJCgXXrgD+AAdoDAAABQAIAGkMAAAEABIAawwAAAMAEwBqDAAAAwAMAGwMAAAEAAUAbQwAAAEAEADqDAAAAQAIAAcABwkKBdeuAP4AB2gMAAAFAAgAaQwAAAQAEgBrDAAAAwATAGoMAAADAAwAbAwAAAQABQBtDAAAAQAQAOoMAAABAAgAAAA=.',
El='Ellay:BAABLgAECn8XAAIMAAcJJg9TQgBaAQdoDAAABABFAGkMAAAEAC0AawwAAAQAKgBqDAAAAwAfAGwMAAACABUAbQwAAAEADwDqDAAABQAtAAwABwkmD1NCAFoBB2gMAAAEAEUAaQwAAAQALQBrDAAABAAqAGoMAAADAB8AbAwAAAIAFQBtDAAAAQAPAOoMAAAFAC0AAAA=.',
Em='Emofumu:BAAALgADCgYJBgABLgAECgkJHgANAEMkAA==.',
En='Endrin:BAAALgAECgYJDAAAAA==.',
Ew='Eww:BAEBLgAECn80AAIOAAkJZhbUCgBPAgloDAAACABJAGkMAAAHAE0AawwAAAcAVwBqDAAABwBRAGwMAAAGAC4AbQwAAAQAGADqDAAACABZAG4MAAADACcAbwwAAAIAEwAOAAkJZhbUCgBPAgloDAAACABJAGkMAAAHAE0AawwAAAcAVwBqDAAABwBRAGwMAAAGAC4AbQwAAAQAGADqDAAACABZAG4MAAADACcAbwwAAAIAEwAAAA==.',
Ez='Ezzak:BAAALgADCgQJBAAAAA==.',
Fe='Felfirefoxxo:BAAALgAFFAIJAgAAAA==.Felldeeds:BAABLgAECn8kAAIMAAgJliXQAwBjAwhoDAAABwBhAGkMAAAHAGMAawwAAAYAYQBqDAAAAgBgAGwMAAADAGEAbQwAAAIAWwDqDAAACABhAG4MAAABAFoADAAICZYl0AMAYwMIaAwAAAcAYQBpDAAABwBjAGsMAAAGAGEAagwAAAIAYABsDAAAAwBhAG0MAAACAFsA6gwAAAgAYQBuDAAAAQBaAAAA.Fellshock:BAAALgAECgQJBgABLgAECggJJAAMAJYlAA==.Felthazzar:BAAALgAECgYJBgAAAA==.Fent:BAACLgAFFH8NAAMPAAQJEw73GQAWAQRoDAAABAApAGkMAAAEACkAawwAAAIAHwDqDAAAAwAdAA8ABAkTDvcZABYBBGgMAAAEACkAaQwAAAQAKQBrDAAAAQAfAOoMAAADAB0AEAABCUQLYVoAQAABawwAAAEAHAAuAAQKfywAAw8ACQmHHIAYAFECAA8ABwlrIIAYAFECABAACQlAF/EgABkCAAAA.Fey:BAAALgAECgEJAQAAAA==.',
Fi='Fingerblastn:BAAALgADCgcJBwABLgAECgkJKgALAL4lAA==.Fingerr:BAABLgAECn8qAAILAAkJviWdAABtAwloDAAABwBjAGkMAAAGAGMAawwAAAYAYQBqDAAABgBjAGwMAAAEAF8AbQwAAAEAVADqDAAABwBjAG4MAAAEAGMAbwwAAAEAYQALAAkJviWdAABtAwloDAAABwBjAGkMAAAGAGMAawwAAAYAYQBqDAAABgBjAGwMAAAEAF8AbQwAAAEAVADqDAAABwBjAG4MAAAEAGMAbwwAAAEAYQAAAA==.Finneagan:BAAALgADCgEJAQAAAA==.',
Fl='Flinkorandus:BAAALgAECgEJAgABLgAECgYJEQADAAAAAA==.Flokki:BAAALgAECgcJDwAAAA==.',
Fo='Foxxowo:BAAALgAFFAMJAwAAAA==.',
Fr='Froztbane:BAEALgAECgcJDwABLgAECgkJPgAIAK0gAA==.Froztbanshee:BAEBLgAECn8+AAIIAAkJrSClDAAbAwloDAAACQBbAGkMAAAJAFkAawwAAAkAVgBqDAAACQBRAGwMAAAHAFwAbQwAAAUAVwDqDAAACQBeAG4MAAAEAFEAbwwAAAEALAAIAAkJrSClDAAbAwloDAAACQBbAGkMAAAJAFkAawwAAAkAVgBqDAAACQBRAGwMAAAHAFwAbQwAAAUAVwDqDAAACQBeAG4MAAAEAFEAbwwAAAEALAAAAA==.',
Gh='Ghats:BAAALgAECgEJAQAAAA==.Ghuss:BAAALgAECgcJBwAAAA==.',
Gl='Glass:BAAALgAECgUJDAAAAA==.',
Go='Gogo:BAAALgAECgYJDAAAAA==.',
Gr='Grimzyn:BAACLgAFFH8PAAIRAAUJvxQ4QABCAQVoDAAABABZAGkMAAAEACwAawwAAAMAJQBqDAAAAQAEAOoMAAADACkAEQAFCb8UOEAAQgEFaAwAAAQAWQBpDAAABAAsAGsMAAADACUAagwAAAEABADqDAAAAwApAC4ABAp/HAACEQAICWMcwDYAXAIAEQAICWMcwDYAXAIAAAA=.Grudge:BAABLgAECn8uAAMSAAgJFxG/BQDVAQhoDAAABwAtAGkMAAAGADcAawwAAAYAMABqDAAABgAtAGwMAAAGACkAbQwAAAQAGADqDAAABwAuAG4MAAAEACwAEgAICUwQvwUA1QEIaAwAAAIAIQBpDAAAAgA3AGsMAAACADAAagwAAAIALQBsDAAAAgApAG0MAAACABgA6gwAAAIALgBuDAAAAgAqABEACAmSDsxlAHEBCGgMAAAFAC0AaQwAAAQAMQBrDAAABAAeAGoMAAAEACAAbAwAAAQAHgBtDAAAAgAQAOoMAAAFACwAbgwAAAIALAAAAA==.',
Ha='Haircules:BAAALgAECgQJCAAAAA==.Harrowhark:BAACLgAFFH8IAAIRAAMJRR0eWAAUAQNoDAAAAwBZAGkMAAACADQA6gwAAAMAUgARAAMJRR0eWAAUAQNoDAAAAwBZAGkMAAACADQA6gwAAAMAUgAuAAQKfy0AAhEACAmeI1QRALoCABEACAmeI1QRALoCAAAA.',
He='Herambae:BAAALgADCgYJBgAAAA==.Herculesátan:BAAALgADCgYJCAAAAA==.',
Ho='Hornstache:BAAALgADCgEJAQAAAA==.',
Hy='Hyacinth:BAABLgAECn8mAAITAAkJrRLnFAD1AQloDAAABgBGAGkMAAAGAEEAawwAAAYALQBqDAAABQAnAGwMAAADABwAbQwAAAEAIADqDAAABQBKAG4MAAAEACAAbwwAAAIAIQATAAkJrRLnFAD1AQloDAAABgBGAGkMAAAGAEEAawwAAAYALQBqDAAABQAnAGwMAAADABwAbQwAAAEAIADqDAAABQBKAG4MAAAEACAAbwwAAAIAIQAAAA==.Hyria:BAAALgADCgkJDwABLgAECgcJEwADAAAAAA==.Hyun:BAAALgADCgYJBgAAAA==.',
Ia='Iamfinn:BAAALgAECgEJAQAAAA==.Iamomegafox:BAACLgAFFH8IAAIUAAMJaBz2FgAbAQNoDAAAAwBQAGkMAAACACwA6gwAAAMAXQAUAAMJaBz2FgAbAQNoDAAAAwBQAGkMAAACACwA6gwAAAMAXQAuAAQKfy8AAxQACAnLGqwRAO4BABQACAkQGawRAO4BABUABgnxF+QLAGgBAAAA.',
Ig='Iggylock:BAAALgADCgYJBgAAAA==.Ignax:BAACLgAFFH8MAAMWAAUJNAgjEQA5AQVoDAAAAwAQAGkMAAADABAAawwAAAEAJgBqDAAAAQATAOoMAAAEAA4AFgAFCTQIIxEAOQEFaAwAAAIAEABpDAAAAwAQAGsMAAABACYAagwAAAEAEwDqDAAABAAOABcAAQlaBRULAE0AAWgMAAABAA0ALgAECn8hAAMWAAgJEhVQFAABAgAWAAgJEhVQFAABAgAXAAYJVgheJQD6AAAAAA==.',
Im='Imomeganisha:BAAALgAECgQJBwABLgAFFAMJCAAUAGgcAA==.Imsparticus:BAABLgAECn8VAAMYAAYJxgh0TQDdAAZoDAAABAAkAGkMAAAEAB0AawwAAAQAGABqDAAAAwAPAGwMAAACAAYA6gwAAAQADwAYAAYJxgh0TQDdAAZoDAAAAwAkAGkMAAADAB0AawwAAAMAGABqDAAAAwAPAGwMAAACAAYA6gwAAAMADwANAAQJcAHROwBtAARoDAAAAQABAGkMAAABAAEAawwAAAEABwDqDAAAAQAEAAAA.',
Io='Ionias:BAABLgAECn8jAAQKAAkJ6AlDMgBXAQloDAAABQAPAGkMAAAFABMAawwAAAUAEwBqDAAABAARAGwMAAAEABoAbQwAAAMAFADqDAAABQA1AG4MAAADAAUAbwwAAAEAMQAKAAgJuQhDMgBXAQhoDAAABAAPAGkMAAAEABMAawwAAAQAEwBqDAAAAwARAGwMAAADABoAbQwAAAMAFADqDAAABAA1AG4MAAACAAUAGQAGCREZ+xcAVwEGaAwAAAEALABpDAAAAQBQAGsMAAABAEgAagwAAAEAFwBsDAAAAQA2AOoMAAABAEYABAACCeMJDAMBcwACbgwAAAEAFgBvDAAAAQAbAAAA.',
Ja='Jackblack:BAAALgAECgIJBAABLgAFFAQJDgAIAJoMAA==.Jaquelius:BAAALgAECgUJDgAAAA==.',
Jo='Joeworgen:BAAALgAECgEJAQAAAA==.Johadan:BAABLgAECn8YAAIEAAYJMQfZvQDdAAZoDAAABAARAGkMAAAEABIAawwAAAQAFwBqDAAAAwATAGwMAAAEABEA6gwAAAUADgAEAAYJMQfZvQDdAAZoDAAABAARAGkMAAAEABIAawwAAAQAFwBqDAAAAwATAGwMAAAEABEA6gwAAAUADgAAAA==.',
Ka='Kade:BAAALgADCgEJAgAAAA==.Kaelx:BAAALgAECgQJCAAAAA==.Kafizz:BAABLgAECn8fAAIJAAkJWxXKPgASAgloDAAABQAsAGkMAAAGAFoAawwAAAYAUABqDAAAAwBOAGwMAAADAEUAbQwAAAEAHwDqDAAAAwAsAG4MAAADADcAbwwAAAEAFgAJAAkJWxXKPgASAgloDAAABQAsAGkMAAAGAFoAawwAAAYAUABqDAAAAwBOAGwMAAADAEUAbQwAAAEAHwDqDAAAAwAsAG4MAAADADcAbwwAAAEAFgAAAA==.Kagnara:BAAALgADCgUJBQAAAA==.',
Ke='Keely:BAAALgAECgUJBQAAAA==.Keolmont:BAAALgADCgEJAQAAAA==.',
Ki='Kinla:BAAALgAECgQJBAAAAA==.Kirakitsune:BAAALgADCgcJBwAAAA==.Kireag:BAAALgADCgIJAgAAAA==.',
Ko='Kooppa:BAAALgADCgQJBAAAAA==.',
Ku='Kuromigirl:BAAALgAECgYJEAAAAA==.',
La='Labchimpette:BAAALgAECgYJDgAAAA==.Lagerthä:BAAALgAECgcJEgABLgAECgkJJAAMADgaAA==.',
Li='Link:BAAALgADCgcJBwAAAA==.Lione:BAABLgAECn8UAAMMAAcJ8hi0LwDtAQdoDAAABAAyAGkMAAADAFUAawwAAAMAUABqDAAAAgBUAGwMAAABAEQA6gwAAAUAOQBuDAAAAgAUAAwABwnyGLQvAO0BB2gMAAADADIAaQwAAAMAVQBrDAAAAwBQAGoMAAACAFQAbAwAAAEARADqDAAABAA5AG4MAAACABQAEwACCWAIR2QATwACaAwAAAEAGgDqDAAAAQAQAAAA.Lith:BAACLgAFFH8HAAIWAAMJgRTnDQD9AANoDAAAAwBEAGsMAAACABsA6gwAAAIAPQAWAAMJgRTnDQD9AANoDAAAAwBEAGsMAAACABsA6gwAAAIAPQAuAAQKfycAAxYACAmuGcIIADICABYACAmuGcIIADICABoACAlgEL4dANcBAAAA.Litterbocks:BAAALgAECgMJBAAAAA==.Littlepriest:BAAALgADCgEJAQAAAA==.',
Ly='Lyzandra:BAAALgADCgYJCgAAAA==.',
['Lì']='Lìllyanna:BAABLgAECn8lAAIZAAkJ8BF8DgCeAQloDAAABwA1AGkMAAAGADEAawwAAAYARABqDAAAAwAfAGwMAAADACQAbQwAAAIAGADqDAAABgAsAG4MAAADADUAbwwAAAEAJAAZAAkJ8BF8DgCeAQloDAAABwA1AGkMAAAGADEAawwAAAYARABqDAAAAwAfAGwMAAADACQAbQwAAAIAGADqDAAABgAsAG4MAAADADUAbwwAAAEAJAAAAA==.',
Ma='Mailbox:BAAALgAECgEJAQABLgAFFAgJIQAKAAwiAA==.Malion:BAAALgAECgEJAQAAAA==.Malock:BAAALgADCgkJCQAAAA==.Mango:BAAALgAECgEJAQAAAA==.Matcha:BAABLgAECn8dAAIbAAkJ8RrMCgCqAgloDAAABAA7AGkMAAAEAEkAawwAAAQAUABqDAAABABOAGwMAAACADEAbQwAAAEAOwDqDAAABABFAG4MAAAEAEkAbwwAAAIASwAbAAkJ8RrMCgCqAgloDAAABAA7AGkMAAAEAEkAawwAAAQAUABqDAAABABOAGwMAAACADEAbQwAAAEAOwDqDAAABABFAG4MAAAEAEkAbwwAAAIASwAAAA==.Mauler:BAAALgAECgQJCAAAAA==.',
Me='Melinoë:BAAALgADCgUJBQAAAA==.Meowhunter:BAAALgAECgUJCgAAAA==.',
Mi='Miaraa:BAAALgAECgcJEAAAAA==.Minervå:BAAALgADCgMJAwAAAA==.',
Mo='Mogdor:BAABLgAECn8mAAMaAAkJuRmWDgBPAgloDAAABQBaAGkMAAAFAEsAawwAAAUAUQBqDAAABgBIAGwMAAAGAEoAbQwAAAIAPwDqDAAABQBBAG4MAAADACAAbwwAAAEAKQAaAAkJuRmWDgBPAgloDAAABQBaAGkMAAAFAEsAawwAAAUAUQBqDAAABQBIAGwMAAAFAEoAbQwAAAIAPwDqDAAABABBAG4MAAADACAAbwwAAAEAKQAXAAMJZBRuLAC4AANqDAAAAQAvAGwMAAABADkA6gwAAAEALgAAAA==.Moonpeach:BAABLgAECn8bAAIMAAYJ5RH0RwBCAQZoDAAABgBNAGkMAAAGABcAawwAAAYAQgBqDAAAAwApAGwMAAACACcA6gwAAAQAGgAMAAYJ5RH0RwBCAQZoDAAABgBNAGkMAAAGABcAawwAAAYAQgBqDAAAAwApAGwMAAACACcA6gwAAAQAGgAAAA==.Motex:BAABLgAECn8eAAIUAAgJ8QKFMwBvAQhoDAAABAAIAGkMAAAEAAgAawwAAAQADQBqDAAABAAJAGwMAAAEAAkAbQwAAAMABQDqDAAABAAFAG4MAAADAAIAFAAICfEChTMAbwEIaAwAAAQACABpDAAABAAIAGsMAAAEAA0AagwAAAQACQBsDAAABAAJAG0MAAADAAUA6gwAAAQABQBuDAAAAwACAAAA.',
Na='Naturebug:BAAALgAECgYJCgAAAA==.',
Ne='Neature:BAAALgAECgIJBAABLgAFFAQJDgAIAJoMAA==.Ned:BAECLgAFFH8QAAIYAAUJDyXyBACrAQVoDAAABQBcAGkMAAAEAGMAawwAAAMAXwBqDAAAAQA/AOoMAAADAFwAGAAFCQ8l8gQAqwEFaAwAAAUAXABpDAAABABjAGsMAAADAF8AagwAAAEAPwDqDAAAAwBcAC4ABAp/RQADGAAICdElVgMAeQMAGAAICdElVgMAeQMAHAAECWUkhg8AowEAAAA=.Netre:BAAALgAECgYJEQAAAA==.',
Ni='Nimbus:BAAALgAFFAMJAgABLgAFFAgJFgAaAEwWAA==.Ninax:BAAALgAECgYJCgAAAA==.',
Ny='Nylian:BAAALgAECgQJBwAAAA==.',
Ob='Obamasmama:BAAALgAFFAEJAQAAAA==.',
Oc='Octomore:BAAALgAFFAEJAgAAAA==.',
Ol='Oldmantom:BAAALgADCgYJBgAAAA==.',
Or='Ormgorg:BAABLgAECn8VAAIdAAcJ9R0KCgDTAQdoDAAAAwBTAGkMAAADAF0AawwAAAMATQBqDAAAAwBXAGwMAAACAE8A6gwAAAUAUgBuDAAAAgAqAB0ABwn1HQoKANMBB2gMAAADAFMAaQwAAAMAXQBrDAAAAwBNAGoMAAADAFcAbAwAAAIATwDqDAAABQBSAG4MAAACACoAAAA=.Orpheus:BAABLgAECn8+AAQQAAkJASFYBABAAwloDAAACQBSAGkMAAAJAFwAawwAAAkAYQBqDAAACABfAGwMAAAHAFoAbQwAAAQAUQDqDAAACABNAG4MAAAFAEwAbwwAAAMAQQAQAAkJASFYBABAAwloDAAABgBSAGkMAAAGAFwAawwAAAYAYQBqDAAABwBfAGwMAAAGAFoAbQwAAAQAUQDqDAAABwBNAG4MAAAFAEwAbwwAAAMAQQAPAAUJ7hfIPQAAAQVoDAAAAgBOAGkMAAACADEAawwAAAIANABqDAAAAQBLAGwMAAABAEEAHQAECTsNwxoAzgAEaAwAAAEAJgBpDAAAAQAkAGsMAAABABYA6gwAAAEAJQAAAA==.',
Oz='Oza:BAAALgAECgMJBgAAAA==.',
Pa='Pandamoniium:BAAALgAECgcJDQABLgAFFAQJCAAHACAbAA==.Pandamonk:BAACLgAFFH8RAAILAAQJyyXRBgC8AQRoDAAABQBjAGkMAAAFAGMAawwAAAMAWwDqDAAABABhAAsABAnLJdEGALwBBGgMAAAFAGMAaQwAAAUAYwBrDAAAAwBbAOoMAAAEAGEALgAECn86AAILAAkJmCXPAABiAwALAAkJmCXPAABiAwAAAA==.',
Pe='Percy:BAEBLgAECn8VAAIeAAcJzg22BQBFAQdoDAAABQApAGkMAAADACgAawwAAAMALABqDAAAAwBJAGwMAAADACAAbQwAAAEAEwDqDAAAAwAhAB4ABwnODbYFAEUBB2gMAAAFACkAaQwAAAMAKABrDAAAAwAsAGoMAAADAEkAbAwAAAMAIABtDAAAAQATAOoMAAADACEAAAA=.',
Pi='Pickleswag:BAAALgAECgMJAwAAAA==.',
Pr='Preservation:BAAALgAECgMJAwAAAA==.',
Ra='Raastamon:BAAALgADCgEJAQAAAA==.Raekitty:BAABLgAECn8XAAIMAAgJgR6SFACRAghoDAAABABdAGkMAAAEAGAAawwAAAQAYQBqDAAAAwBQAGwMAAADAFsAbQwAAAEAHQDqDAAAAwBVAG4MAAABADIADAAICYEekhQAkQIIaAwAAAQAXQBpDAAABABgAGsMAAAEAGEAagwAAAMAUABsDAAAAwBbAG0MAAABAB0A6gwAAAMAVQBuDAAAAQAyAAAA.Rama:BAAALgAECgMJBQABLgAECgYJGQAHAPQcAA==.',
Re='Redrover:BAAALgADCggJDgAAAA==.Reia:BAAALgADCgcJBwAAAA==.',
Rh='Rhara:BAAALgADCgYJEgAAAA==.Rhoem:BAABLgAECn8pAAMfAAkJQB0vEgCuAQloDAAABQBOAGkMAAAFAF0AawwAAAUAUgBqDAAABQBQAGwMAAAGAFQAbQwAAAMARADqDAAACABbAG4MAAADAEYAbwwAAAEAHQASAAgJzB+xBQDXAQhoDAAABABOAGkMAAAEAF0AawwAAAQAUgBqDAAABABQAGwMAAAFAFQAbQwAAAMARADqDAAACABbAG4MAAACAEYAHwAHCQIYLxIArgEHaAwAAAEALQBpDAAAAQBJAGsMAAABAE8AagwAAAEARQBsDAAAAQBHAG4MAAABAEQAbwwAAAEAHQAAAA==.',
Ri='Rin:BAEALgADCgMJAwABLgAECggJIwAbADUhAA==.',
Ro='Roger:BAABLgAECn8XAAMKAAYJySEQFQAvAgZoDAAABQBhAGkMAAAFAF0AawwAAAQAWgBqDAAABABYAGwMAAACAF8A6gwAAAMANQAKAAYJySEQFQAvAgZoDAAAAgBhAGkMAAAEAF0AawwAAAMAWgBqDAAAAwBYAGwMAAACAF8A6gwAAAEANQAEAAUJKA3gzwDCAAVoDAAAAwAnAGkMAAABABYAawwAAAEAEgBqDAAAAQAtAOoMAAACADUAAAA=.',
Ru='Rumor:BAACLgAFFH8fAAMVAAcJth89AABiAgdoDAAABABjAGkMAAAHAGIAawwAAAYAUwBqDAAABABbAGwMAAACAFoAbQwAAAEAHQDqDAAABwBUABUABwm2Hz0AAGICB2gMAAADAGMAaQwAAAUAYgBrDAAABQBTAGoMAAAEAFsAbAwAAAIAWgBtDAAAAQAdAOoMAAAFAFQAFAAECbEZdQcAbQEEaAwAAAEAOgBpDAAAAgBZAGsMAAABADoA6gwAAAIAOAAuAAQKfzkAAxUACAnJJigBAOsCABUACAmVJigBAOsCABQACAnTJJcKAOkCAAAA.Run:BAAALgAECgEJAQAAAA==.',
Se='Secretgrace:BAAALgADCgQJBAABLgAECgcJFQAdAPUdAA==.Seed:BAAALgAECgkJDAAAAA==.Senortickle:BAAALgAECgcJEwAAAA==.',
Sh='Shadowmoone:BAABLgAECn8jAAIGAAgJ/AlzUwBtAQhoDAAABgAnAGkMAAAGAB0AawwAAAUAFgBqDAAABAAaAGwMAAAFABgAbQwAAAIAGADqDAAABgAdAG4MAAABAAkABgAICfwJc1MAbQEIaAwAAAYAJwBpDAAABgAdAGsMAAAFABYAagwAAAQAGgBsDAAABQAYAG0MAAACABgA6gwAAAYAHQBuDAAAAQAJAAAA.Shaki:BAAALgAECgQJBwAAAA==.Shalendris:BAAALgAECgEJAQAAAA==.Shalestrasz:BAABLgAECn8XAAQXAAgJNQg0IQAjAQhoDAAAAwAIAGkMAAADABQAawwAAAMAGABqDAAAAwAJAGwMAAADABAAbQwAAAIACQDqDAAABAAyAG4MAAACABEAFwAICRcFNCEAIwEIaAwAAAMACABpDAAAAwAUAGsMAAADABgAagwAAAMACQBsDAAAAgAQAG0MAAABAAkA6gwAAAIACABuDAAAAQADABoAAwkVCmpbAIwAA20MAAABAAkA6gwAAAEAMgBuDAAAAQARABYAAglVAU1FAEYAAmwMAAABAAQA6gwAAAEAAgAAAA==.Shibal:BAAALgADCggJCAAAAA==.Shinedown:BAAALgADCgQJBAAAAA==.Shochu:BAAALgAECgcJEAAAAA==.',
Sl='Sloane:BAAALgADCgQJBAAAAA==.',
So='Soju:BAAALgAECgUJBQAAAA==.Somnera:BAAALgAECgEJAQABLgAECgcJFQAdAPUdAA==.Soyboymalfoy:BAABLgAECn8WAAICAAgJxBOJGgDCAQhoDAAABABFAGkMAAADAD4AawwAAAQAOABqDAAAAwAnAGwMAAACADQA6gwAAAMAPwBuDAAAAgApAG8MAAABABIAAgAICcQTiRoAwgEIaAwAAAQARQBpDAAAAwA+AGsMAAAEADgAagwAAAMAJwBsDAAAAgA0AOoMAAADAD8AbgwAAAIAKQBvDAAAAQASAAAA.',
Sp='Sp:BAACLgAFFH8YAAICAAQJCh9qCQBqAQRoDAAACQBEAGkMAAAFAD8AawwAAAQAWgDqDAAABgBgAAIABAkKH2oJAGoBBGgMAAAJAEQAaQwAAAUAPwBrDAAABABaAOoMAAAGAGAALgAECn9AAAMCAAgJ1ySxAgBPAwACAAgJ1ySxAgBPAwAgAAEJeQoMbgAvAAAAAA==.',
St='Sterility:BAAALgAECgUJEAAAAA==.',
Sw='Switchfoot:BAACLgAFFH8FAAIhAAMJ9RyfBAAeAQNoDAAAAgBcAGkMAAABAC8A6gwAAAIAUQAhAAMJ9RyfBAAeAQNoDAAAAgBcAGkMAAABAC8A6gwAAAIAUQAuAAQKfzIAAyEACQn8IAkBAOUCACEACQn8IAkBAOUCABUAAQklE9sbAEkAAAAA.',
['Sï']='Sïeghart:BAAALgADCgUJBQAAAA==.',
Ta='Tallmanbeta:BAAALgADCgEJAQAAAA==.',
Te='Tenzin:BAAALgADCgQJBAABLgAFFAQJFgAJADIYAA==.Tex:BAAALgADCgcJDgAAAA==.',
Ti='Timerunner:BAAALgADCgYJBgAAAA==.',
To='Totingtotems:BAAALgADCgcJDQAAAA==.Touchofdeath:BAABLgAECn8WAAIiAAcJ3As1OQA5AQdoDAAABAAeAGkMAAAEACUAawwAAAQAKQBqDAAAAwAfAGwMAAADACQAbQwAAAEACQDqDAAAAwAbACIABwncCzU5ADkBB2gMAAAEAB4AaQwAAAQAJQBrDAAABAApAGoMAAADAB8AbAwAAAMAJABtDAAAAQAJAOoMAAADABsAAAA=.',
Ug='Ughnga:BAAALgAECgMJAwABLgAECgcJHQAJAPISAA==.',
Va='Vandli:BAAALgAECgMJBAAAAA==.',
Ve='Velzard:BAAALgAECgYJEgAAAA==.Verti:BAAALgAECgYJCwAAAA==.Veylan:BAAALgAECgEJAQAAAA==.',
Vi='Visona:BAAALgADCgQJBAAAAA==.',
Vo='Voíshara:BAAALgADCgUJCwAAAA==.',
['Vö']='Vöre:BAAALgAECgYJBwAAAA==.',
Wa='Wanagi:BAAALgADCgEJAQAAAA==.',
Wh='Whitessin:BAAALgADCgcJBwAAAA==.',
Wi='Wither:BAACLgAFFH8FAAIRAAQJMhF2FQBOAQRoDAAAAQAZAGkMAAABAE0AawwAAAEAIgDqDAAAAgAmABEABAkyEXYVAE4BBGgMAAABABkAaQwAAAEATQBrDAAAAQAiAOoMAAACACYALgAECn8eAAIRAAgJXSKeNQBgAgARAAgJXSKeNQBgAgABLgAFFAcJHwAVALYfAA==.',
Wy='Wyspur:BAAALgADCgYJCgAAAA==.',
Yo='Yofoxxo:BAACLgAFFH8UAAIKAAcJoxnWAwCoAQdoDAAABABJAGkMAAADAFkAawwAAAMAUQBqDAAAAgBKAGwMAAABACkAbQwAAAEAIgDqDAAABgBAAAoABwmjGdYDAKgBB2gMAAAEAEkAaQwAAAMAWQBrDAAAAwBRAGoMAAACAEoAbAwAAAEAKQBtDAAAAQAiAOoMAAAGAEAALgAECn8uAAQKAAgJXSQ8BAAqAwAKAAgJXSQ8BAAqAwAEAAUJDQ6gtAAbAQAZAAIJiwi8PQBHAAAAAA==.',
Yu='Yulon:BAAALgAECgYJDgABLgAFFAQJGAACAAofAA==.',
Za='Zaraerivia:BAAALgAECgYJDwAAAA==.Zarlon:BAAALgAECgMJBQABLgAECgYJGQAHAPQcAA==.',
Ze='Zengriff:BAABLgAECn8rAAILAAkJ1SKAAgAZAwloDAAABgBbAGkMAAAGAGEAawwAAAYAVwBqDAAABgBiAGwMAAAGAF0AbQwAAAMATQDqDAAABgBhAG4MAAADAFgAbwwAAAEAUAALAAkJ1SKAAgAZAwloDAAABgBbAGkMAAAGAGEAawwAAAYAVwBqDAAABgBiAGwMAAAGAF0AbQwAAAMATQDqDAAABgBhAG4MAAADAFgAbwwAAAEAUAAAAA==.Zerena:BAAALgAECgYJBgAAAA==.',
Zh='Zhule:BAABLgAECn8rAAIGAAkJ1R4CEgCMAgloDAAABgBSAGkMAAAGAEsAawwAAAYASgBqDAAABgBXAGwMAAAGAF8AbQwAAAMARgDqDAAABgBbAG4MAAADAFMAbwwAAAEAOgAGAAkJ1R4CEgCMAgloDAAABgBSAGkMAAAGAEsAawwAAAYASgBqDAAABgBXAGwMAAAGAF8AbQwAAAMARgDqDAAABgBbAG4MAAADAFMAbwwAAAEAOgAAAA==.',
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
