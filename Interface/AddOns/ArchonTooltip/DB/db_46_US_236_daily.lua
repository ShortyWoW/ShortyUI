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

local lookup = {'Druid-Balance','Unknown-Unknown','Paladin-Holy','Mage-Frost','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Blood','Druid-Guardian','Paladin-Retribution','DemonHunter-Devourer','DemonHunter-Vengeance','Rogue-Assassination','Rogue-Subtlety','Warlock-Demonology','Druid-Restoration','Warrior-Fury','Monk-Brewmaster','Evoker-Preservation','Monk-Windwalker','DeathKnight-Frost','Priest-Discipline','Rogue-Outlaw','Hunter-BeastMastery','Hunter-Marksmanship','Evoker-Augmentation','Evoker-Devastation','Shaman-Restoration','Shaman-Elemental','Druid-Feral','Warlock-Destruction','Priest-Holy','Warrior-Arms','Warrior-Protection','DemonHunter-Havoc','Shaman-Enhancement',}
local provider = {region='US',realm='Warsong',name='US',type='daily',zone=46,date='2026-05-22',data={Ad='Adònis:BAAALgADCgEJAQAAAA==.',
Ae='Aesudan:BAAALgADCgEJAQAAAA==.',
Ah='Aharan:BAABLgAECn8lAAIBAAgJ2w2uKQBRAQhoDAAABgAjAGkMAAAGACYAawwAAAYAFwBqDAAABQATAGwMAAAFACEAbQwAAAIAJgDqDAAABgAmAG4MAAABACcAAQAICdsNrikAUQEIaAwAAAYAIwBpDAAABgAmAGsMAAAGABcAagwAAAUAEwBsDAAABQAhAG0MAAACACYA6gwAAAYAJgBuDAAAAQAnAAAA.',
Ai='Aiona:BAAALgADCgYJDAAAAA==.',
Al='Alandrov:BAAALgADCgEJAQAAAA==.Alexanzalone:BAAALgADCggJCAAAAA==.Allenduin:BAAALgAECgEJAQAAAA==.Alodso:BAAALgADCgEJAQAAAA==.',
An='Angelique:BAAALgAECgQJBAAAAA==.Angryballz:BAAALgAECgYJBwABLgAECgYJCwACAAAAAA==.Angz:BAAALgAECgUJDQAAAA==.Anielor:BAAALgADCgMJAwAAAA==.Anuksuna:BAAALgAECgUJCQABLgAECggJHAADANUXAA==.',
Ar='Arcadia:BAAALgAECgYJDgAAAA==.Arcane:BAACLgAFFH8OAAIEAAUJox6cJwCBAQVoDAAAAwBfAGkMAAADAFIAawwAAAMAWwBqDAAAAgAuAOoMAAADACwABAAFCaMenCcAgQEFaAwAAAMAXwBpDAAAAwBSAGsMAAADAFsAagwAAAIALgDqDAAAAwAsAC4ABAp/HwADBAAJCeAhXBAARgMABAAJCeAhXBAARgMABQAFCUMkFwUA6QEAAAA=.',
As='Asta:BAAALgAECgQJBAAAAA==.',
At='Atulan:BAAALgADCgQJBAAAAA==.',
Au='Austin:BAAALgADCggJFgAAAA==.Automobeer:BAAALgAECgEJBAAAAA==.',
Aw='Awake:BAABLgAECn8mAAMGAAcJthVPYwB8AQdoDAAABgBIAGkMAAAGAEcAawwAAAUANABqDAAABQA0AGwMAAAEACQAbQwAAAYAOADqDAAABgAsAAYABwlsFE9jAHwBB2gMAAAEAEgAaQwAAAQARwBrDAAAAwA0AGoMAAADACoAbAwAAAIAEABtDAAABgA4AOoMAAAEACwABwAGCdoSVh8ASgEGaAwAAAIAOABpDAAAAgA6AGsMAAACADEAagwAAAIANABsDAAAAgAkAOoMAAACACgAAAA=.',
Az='Azazzel:BAAALgADCgEJAQAAAA==.',
Ba='Bambietta:BAAALgADCgkJCQAAAA==.Barebelly:BAAALgAECggJEAAAAA==.',
Be='Bearforce:BAABLgAECn8eAAIIAAkJjxnZCAAbAgloDAAAAgBUAGkMAAACADEAawwAAAIASgBqDAAABQA/AGwMAAAFAFoAbQwAAAMAQwDqDAAABgBQAG4MAAAEABoAbwwAAAEAMgAIAAkJjxnZCAAbAgloDAAAAgBUAGkMAAACADEAawwAAAIASgBqDAAABQA/AGwMAAAFAFoAbQwAAAMAQwDqDAAABgBQAG4MAAAEABoAbwwAAAEAMgAAAA==.',
Bi='Biggbird:BAABLgAECn8gAAIBAAYJJh3hIACRAQZoDAAABwBJAGkMAAAFAFAAawwAAAYARwBqDAAABQA4AGwMAAAEAEAA6gwAAAUAUwABAAYJJh3hIACRAQZoDAAABwBJAGkMAAAFAFAAawwAAAYARwBqDAAABQA4AGwMAAAEAEAA6gwAAAUAUwAAAA==.',
Bl='Blewbawl:BAAALgADCgEJAQAAAA==.Blutwin:BAABLgAECn8sAAIJAAkJThOCNgAFAgloDAAABwAmAGkMAAAHADMAawwAAAYAOwBqDAAABQAzAGwMAAAGAEkAbQwAAAEAGwDqDAAABgBDAG4MAAAEADkAbwwAAAIAEwAJAAkJThOCNgAFAgloDAAABwAmAGkMAAAHADMAawwAAAYAOwBqDAAABQAzAGwMAAAGAEkAbQwAAAEAGwDqDAAABgBDAG4MAAAEADkAbwwAAAIAEwAAAA==.Bluud:BAAALgADCgMJAwAAAA==.',
Bo='Bossdierr:BAACLgAFFH8PAAIKAAMJFyNkLgAsAQNoDAAABgBiAGkMAAACAE4A6gwAAAcAXAAKAAMJFyNkLgAsAQNoDAAABgBiAGkMAAACAE4A6gwAAAcAXAAuAAQKfzIAAwoACQkyIxYNAMACAAoACQkyIxYNAMACAAsACAlCE80MAFUBAAAA.Bossdisan:BAACLgAFFH8LAAIEAAQJQxp/NQBWAQRoDAAABABcAGkMAAADAFYAawwAAAEAHgDqDAAAAwA7AAQABAlDGn81AFYBBGgMAAAEAFwAaQwAAAMAVgBrDAAAAQAeAOoMAAADADsALgAECn8oAAIEAAYJbCRXVwAzAgAEAAYJbCRXVwAzAgAAAA==.Bossmasster:BAAALgAFFAIJAgAAAA==.Bosswudi:BAABLgAFFH8JAAMMAAIJMRNICACgAAJoDAAABAA+AOoMAAAFACQADQACCcEStBUAoAACaAwAAAMAOwDqDAAAAwAkAAwAAgmKEUgIAKAAAmgMAAABAD4A6gwAAAIAGwAAAA==.',
Br='Brashe:BAABLgAECn8dAAIEAAcJEA7bhgBMAQdoDAAABgA5AGkMAAAFAC0AawwAAAUAIQBqDAAABAAVAGwMAAABABIA6gwAAAcAJwBuDAAAAQAVAAQABwkQDtuGAEwBB2gMAAAGADkAaQwAAAUALQBrDAAABQAhAGoMAAAEABUAbAwAAAEAEgDqDAAABwAnAG4MAAABABUAAAA=.Breathe:BAAALgAECgQJBAABLgAECgYJCgACAAAAAA==.Brickbeard:BAAALgAECgYJBgABLgAECgcJEQACAAAAAA==.Bruv:BAABLgAECn8jAAIOAAYJhhU5bwCCAQZoDAAABwBHAGkMAAAGADgAawwAAAYAKwBqDAAABQBUAGwMAAAEACQA6gwAAAcARAAOAAYJhhU5bwCCAQZoDAAABwBHAGkMAAAGADgAawwAAAYAKwBqDAAABQBUAGwMAAAEACQA6gwAAAcARAAAAA==.',
Ca='Calathis:BAAALgAECgEJAQAAAA==.Cazadòr:BAAALgAECgIJAgAAAA==.',
Ch='Chromiepip:BAAALgADCgMJAwAAAA==.',
Co='Corbann:BAAALgAECgYJCgAAAA==.',
Cr='Creamcheese:BAABLgAECn8aAAIPAAcJUB27LAD8AQdoDAAABABSAGkMAAAEAFQAawwAAAQATgBqDAAAAwBSAGwMAAAEAFMAbQwAAAIAFgDqDAAABQBcAA8ABwlQHbssAPwBB2gMAAAEAFIAaQwAAAQAVABrDAAABABOAGoMAAADAFIAbAwAAAQAUwBtDAAAAgAWAOoMAAAFAFwAAAA=.Creamy:BAABLgAECn8sAAIQAAkJ8Bn+EwAqAgloDAAABgBfAGkMAAAHADwAawwAAAYAQQBqDAAABQBAAGwMAAAGAFEAbQwAAAIAOADqDAAABwBLAG4MAAADAB0AbwwAAAIAQwAQAAkJ8Bn+EwAqAgloDAAABgBfAGkMAAAHADwAawwAAAYAQQBqDAAABQBAAGwMAAAGAFEAbQwAAAIAOADqDAAABwBLAG4MAAADAB0AbwwAAAIAQwAAAA==.Crossbreed:BAAALgAFFAIJAwAAAA==.',
Cy='Cyr:BAAALgADCgUJBQAAAA==.Cytosine:BAAALgAFFAEJAQAAAA==.',
Da='Daddyhaz:BAACLgAFFH8HAAIKAAMJZhYtRADpAANoDAAAAwBKAGkMAAABACAA6gwAAAMAQAAKAAMJZhYtRADpAANoDAAAAwBKAGkMAAABACAA6gwAAAMAQAAuAAQKf0MAAgoACQmzJO0CAEkDAAoACQmzJO0CAEkDAAAA.Daddywhyudie:BAAALgADCgEJAQAAAA==.Daelyte:BAAALgAECgYJDwAAAA==.Daghor:BAABLgAFFH8GAAINAAIJLBoXJQCgAAJoDAAAAwBUAOoMAAADADEADQACCSwaFyUAoAACaAwAAAMAVADqDAAAAwAxAAAA.',
De='Deltron:BAAALgAECgEJAQAAAA==.Desetre:BAAALgADCgIJAgAAAA==.',
Di='Diabos:BAAALgAECgMJBAAAAA==.Dinks:BAABLgAECn86AAIEAAkJXxhhLABIAgloDAAACABTAGkMAAAIAEYAawwAAAgAQQBqDAAABgA4AGwMAAAIADQAbQwAAAUAQQDqDAAACABLAG4MAAAFACUAbwwAAAIAMQAEAAkJXxhhLABIAgloDAAACABTAGkMAAAIAEYAawwAAAgAQQBqDAAABgA4AGwMAAAIADQAbQwAAAUAQQDqDAAACABLAG4MAAAFACUAbwwAAAIAMQAAAA==.Ditzy:BAAALgAECgEJAQAAAA==.',
Do='Docc:BAABLgAECn8XAAINAAkJGA+nFgBXAgloDAAAAwA5AGkMAAADAD4AawwAAAMAOABqDAAAAwAmAGwMAAADADMAbQwAAAEABQDqDAAABAAmAG4MAAACAAgAbwwAAAEAHAANAAkJGA+nFgBXAgloDAAAAwA5AGkMAAADAD4AawwAAAMAOABqDAAAAwAmAGwMAAADADMAbQwAAAEABQDqDAAABAAmAG4MAAACAAgAbwwAAAEAHAAAAA==.Domdps:BAAALgAECgEJAQAAAA==.',
Dr='Draan:BAAALgADCgUJBwAAAA==.Dragorr:BAAALgADCgcJBwAAAA==.Dreadpanda:BAAALgADCgMJAwABLgAFFAQJCAARALIiAA==.Drekkarn:BAAALgADCgMJBgAAAA==.Drood:BAAALgAECgMJBAAAAA==.',
El='Elzath:BAAALgADCggJEAABLgAECgkJIwASAIkUAA==.',
En='Enix:BAAALgADCgYJBgABLgAFFAIJCAAPALwTAA==.',
Er='Erdrick:BAAALgAECgIJBAAAAA==.',
Es='Espeon:BAAALgAECgcJDgAAAA==.',
Eu='Eudisius:BAAALgADCgEJAQAAAA==.',
Ev='Evara:BAABLgAECn8UAAIEAAYJAwdU7gAcAQZoDAAABAAQAGkMAAAEABoAawwAAAQAGQBqDAAAAgALAGwMAAACAAcA6gwAAAQADAAEAAYJAwdU7gAcAQZoDAAABAAQAGkMAAAEABoAawwAAAQAGQBqDAAAAgALAGwMAAACAAcA6gwAAAQADAAAAA==.',
Fa='Faded:BAAALgAECgYJBwAAAA==.Fangbot:BAAALgAECgEJAgAAAA==.',
Fe='Felcaas:BAAALgADCgQJBAAAAA==.Felini:BAABLgAECn8cAAIQAAcJvgdlRgD/AAdoDAAABQAVAGkMAAAFABYAawwAAAQAFwBqDAAABAAVAGwMAAAEABAAbQwAAAEACQDqDAAABQAYABAABwm+B2VGAP8AB2gMAAAFABUAaQwAAAUAFgBrDAAABAAXAGoMAAAEABUAbAwAAAQAEABtDAAAAQAJAOoMAAAFABgAAAA=.Feronar:BAABLgAECn8uAAIQAAkJ+wt2JQCjAQloDAAACAAsAGkMAAAHACcAawwAAAcAJABqDAAABgAnAGwMAAAFACwAbQwAAAMAFQDqDAAACAAjAG4MAAABAAcAbwwAAAEAEQAQAAkJ+wt2JQCjAQloDAAACAAsAGkMAAAHACcAawwAAAcAJABqDAAABgAnAGwMAAAFACwAbQwAAAMAFQDqDAAACAAjAG4MAAABAAcAbwwAAAEAEQAAAA==.',
Fi='Fizzwater:BAAALgAECgYJCAAAAA==.',
Fl='Fleepity:BAAALgAECgcJDwAAAA==.Floopity:BAAALgADCgYJBwAAAA==.Flowermom:BAAALgAECgEJAwAAAA==.Flume:BAAALgAECgcJBwAAAA==.',
Fu='Fusíon:BAEBLgAECn8zAAIKAAkJeiIwDgANAwloDAAACABhAGkMAAAHAGMAawwAAAcAXQBqDAAABwBhAGwMAAAGAGEAbQwAAAMAUwDqDAAACQBaAG4MAAADAEQAbwwAAAEATAAKAAkJeiIwDgANAwloDAAACABhAGkMAAAHAGMAawwAAAcAXQBqDAAABwBhAGwMAAAGAGEAbQwAAAMAUwDqDAAACQBaAG4MAAADAEQAbwwAAAEATAAAAA==.',
Gi='Gin:BAACLgAFFH8NAAITAAQJFA8cEQAPAQRoDAAABAA8AGkMAAADACQAawwAAAIAFQDqDAAABAAjABMABAkUDxwRAA8BBGgMAAAEADwAaQwAAAMAJABrDAAAAgAVAOoMAAAEACMALgAECn8vAAITAAkJ9xpvDwAoAgATAAkJ9xpvDwAoAgAAAA==.',
Gj='Gjana:BAAALgAECgQJCAABLgAECggJJgAEAD8SAA==.',
Gl='Glamdring:BAAALgADCgMJAwAAAA==.Glunty:BAAALgAECgUJCAAAAA==.',
Go='Goldpaw:BAAALgADCgEJAQAAAA==.Gorlash:BAAALgAECgcJCAAAAA==.',
Gr='Gridinn:BAAALgADCgIJAgAAAA==.Grimdark:BAAALgAECgQJBAAAAA==.Grimgeth:BAACLgAFFH8PAAIGAAQJeBIpRwA3AQRoDAAABQBVAGkMAAAFADYAawwAAAEACQDqDAAABAAoAAYABAl4EilHADcBBGgMAAAFAFUAaQwAAAUANgBrDAAAAQAJAOoMAAAEACgALgAECn80AAQGAAkJsyCxDwDOAgAGAAkJ2B+xDwDOAgAHAAMJVx8/LwCxAAAUAAIJ5RdBKAA4AAAAAA==.Grimwrath:BAAALgAECgUJBwABLgAFFAQJDwAGAHgSAA==.',
Gu='Gugaman:BAAALgADCgcJDgAAAA==.Guishin:BAAALgAECgEJAwAAAA==.',
He='Healpls:BAAALgAECgEJAgAAAA==.Heidriel:BAAALgAECgMJAwAAAA==.Herumesu:BAAALgADCgcJCgABLgAFFAUJEwAGAAIdAA==.',
Ho='Holapes:BAAALgAECgUJDwABLgAECgMJBAACAAAAAA==.',
Hu='Huhbruh:BAAALgAECgIJAgABLgAECgYJIwAOAIYVAA==.',
Hw='Hwasa:BAABLgAECn8jAAIRAAkJ4h2/CQB5AgloDAAABgBOAGkMAAAGAFsAawwAAAUAVwBqDAAABABWAGwMAAAEAFoAbQwAAAIARQDqDAAABQBTAG4MAAACACYAbwwAAAEASQARAAkJ4h2/CQB5AgloDAAABgBOAGkMAAAGAFsAawwAAAUAVwBqDAAABABWAGwMAAAEAFoAbQwAAAIARQDqDAAABQBTAG4MAAACACYAbwwAAAEASQAAAA==.',
Il='Illigari:BAAALgAFFAEJAQAAAA==.',
In='Indy:BAAALgADCgUJDQAAAA==.Insanities:BAABLgAECn83AAIVAAkJQSH1AwA7AwloDAAACABZAGkMAAAHAFUAawwAAAcAXABqDAAABwBcAGwMAAAHAFYAbQwAAAQAVADqDAAACABZAG4MAAAEAFAAbwwAAAMAQQAVAAkJQSH1AwA7AwloDAAACABZAGkMAAAHAFUAawwAAAcAXABqDAAABwBcAGwMAAAHAFYAbQwAAAQAVADqDAAACABZAG4MAAAEAFAAbwwAAAMAQQAAAA==.Inti:BAABLgAECn8WAAIDAAYJZhuNKACeAQZoDAAAAwBZAGkMAAADADoAawwAAAQAQABqDAAABQBCAGwMAAADADUA6gwAAAQAWAADAAYJZhuNKACeAQZoDAAAAwBZAGkMAAADADoAawwAAAQAQABqDAAABQBCAGwMAAADADUA6gwAAAQAWAABLgAFFAIJCAAPALwTAA==.',
Iz='Izumisakai:BAAALgAECgEJAQABLgAFFAUJEwAGAAIdAA==.',
Ja='Jaidie:BAAALgAECgcJEQAAAA==.',
Je='Jeffreyx:BAAALgAECgYJCAAAAA==.Jeffreyz:BAAALgADCgYJBgAAAA==.',
Jo='Joak:BAAALgADCgUJBQAAAA==.Jota:BAAALgADCgcJCAAAAA==.',
Ka='Kahlán:BAABLgAECn8cAAIDAAgJ1Rc+OACZAQhoDAAABQBSAGkMAAAGAFcAawwAAAUANQBqDAAAAgA6AGwMAAADACUAbQwAAAEAJwDqDAAABQArAG4MAAABAFMAAwAICdUXPjgAmQEIaAwAAAUAUgBpDAAABgBXAGsMAAAFADUAagwAAAIAOgBsDAAAAwAlAG0MAAABACcA6gwAAAUAKwBuDAAAAQBTAAAA.Karlangas:BAAALgAECgMJBAAAAA==.',
Ki='Kifu:BAAALgADCgEJAQABLgAECggJJgAEAD8SAA==.Kikipants:BAAALgADCgEJAQAAAA==.Kitrix:BAAALgADCgUJBQAAAA==.Kitty:BAAALgAECgYJBgABLgAFFAQJDgAIAHYHAA==.',
Kr='Krue:BAAALgADCggJDQAAAA==.',
Ku='Kubimage:BAABLgAECn8aAAIEAAkJKhu2MgCoAgloDAAABABcAGkMAAAEAFUAawwAAAQATwBqDAAAAwATAGwMAAADAEMAbQwAAAEATwDqDAAABABTAG4MAAACAB0AbwwAAAEAJgAEAAkJKhu2MgCoAgloDAAABABcAGkMAAAEAFUAawwAAAQATwBqDAAAAwATAGwMAAADAEMAbQwAAAEATwDqDAAABABTAG4MAAACAB0AbwwAAAEAJgAAAA==.',
La='Lane:BAAALgADCgEJAQAAAA==.Layona:BAAALgAECgYJCgAAAA==.',
Le='Lerroy:BAAALgADCgcJCQAAAA==.',
Li='Lildar:BAABLgAECn8nAAIGAAgJnhrwNAAGAghoDAAABgBNAGkMAAAGAE8AawwAAAYASgBqDAAABQBHAGwMAAAFAEAAbQwAAAIALgDqDAAABwBXAG4MAAACAC8ABgAICZ4a8DQABgIIaAwAAAYATQBpDAAABgBPAGsMAAAGAEoAagwAAAUARwBsDAAABQBAAG0MAAACAC4A6gwAAAcAVwBuDAAAAgAvAAAA.Linelli:BAAALgAECgcJCwABLgAFFAUJEgAWALUkAA==.Lirra:BAAALgAFFAIJBAABLgAFFAIJCAAPALwTAA==.',
Lo='Lorthiel:BAAALgADCgIJAgAAAA==.Lothus:BAACLgAFFH8IAAIXAAIJgh7rTgC1AAJoDAAABABZAOoMAAAEAEIAFwACCYIe604AtQACaAwAAAQAWQDqDAAABABCAC4ABAp/FQADFwAJCQ8bMBgAeAIAFwAJCQ8bMBgAeAIAGAABCXYEY5MAJwAAAS4ABRQCCQgADwC8EwA=.Lox:BAAALgAECgYJCQAAAA==.',
Ls='Lsblkxd:BAAALgADCgYJBgAAAA==.',
Lu='Lumen:BAAALgAECgEJAQAAAA==.Lumverjvcked:BAAALgAECgYJDAABLgAECgYJIwAOAIYVAA==.',
Lx='Lxrbread:BAACLgAFFH8OAAMZAAMJbgxtMgDKAANoDAAABwAYAGkMAAADACAA6gwAAAQAJgAZAAMJbgxtMgDKAANoDAAABQAYAGkMAAADACAA6gwAAAQAJgASAAEJ5QPaGAA8AAFoDAAAAgAJAC4ABAp/OQAEGQAJCVAVQRsA2AEAGQAJCS4VQRsA2AEAEgAFCUEF1jcArQAAGgACCagK6h4AOQAAAAA=.',
['Lë']='Lëgitz:BAABLgAECn8lAAMbAAkJuR8uCAACAwloDAAABgBTAGkMAAAFAFQAawwAAAUASgBqDAAABABeAGwMAAAEAF0AbQwAAAIATADqDAAABgBdAG4MAAAEAEYAbwwAAAEAOwAbAAkJuR8uCAACAwloDAAABQBTAGkMAAAEAFQAawwAAAQASgBqDAAAAwBeAGwMAAADAF0AbQwAAAEATADqDAAABQBdAG4MAAADAEYAbwwAAAEAOwAcAAgJIBS3JACSAQhoDAAAAQAzAGkMAAABADoAawwAAAEAOwBqDAAAAQA1AGwMAAABAD4AbQwAAAEAEwDqDAAAAQBEAG4MAAABACgAAAA=.',
Ma='Macca:BAAALgAECgUJBQABLgAECgYJCwACAAAAAA==.Maccazilla:BAAALgAECgYJCwAAAA==.Magdalena:BAACLgAFFH8RAAITAAQJcSTNAwCpAQRoDAAABQBhAGkMAAAFAF8AawwAAAMAVwDqDAAABABcABMABAlxJM0DAKkBBGgMAAAFAGEAaQwAAAUAXwBrDAAAAwBXAOoMAAAEAFwALgAECn8lAAITAAkJAyW/AgBtAwATAAkJAyW/AgBtAwAAAA==.Magedand:BAAALgAECgMJAwAAAA==.Magnesson:BAAALgAFFAEJAgAAAA==.Manakaren:BAAALgADCggJDAAAAA==.Mazuro:BAACLgAFFH8ZAAINAAYJGhnDCACaAQZoDAAABwBHAGkMAAAGADwAawwAAAQAVwBqDAAAAwA6AGwMAAABABQA6gwAAAQAUQANAAYJGhnDCACaAQZoDAAABwBHAGkMAAAGADwAawwAAAQAVwBqDAAAAwA6AGwMAAABABQA6gwAAAQAUQAuAAQKfy4AAw0ACQm5HbcKAFMCAA0ACQm5HbcKAFMCAAwAAQlGGVodAEAAAAAA.',
Me='Meatkleaver:BAABLgAECn8bAAMUAAkJ0BUhAwBnAgloDAAABABTAGkMAAAEAEAAawwAAAQATwBqDAAAAwAiAGwMAAADAC4AbQwAAAEAJQDqDAAABQBEAG4MAAACACgAbwwAAAEAGgAUAAkJ0BUhAwBnAgloDAAABABTAGkMAAADAEAAawwAAAQATwBqDAAAAwAiAGwMAAADAC4AbQwAAAEAJQDqDAAABQBEAG4MAAACACgAbwwAAAEAGgAGAAEJqAGXNgEiAAFpDAAAAQAEAAAA.Meau:BAABLgAECn8jAAIdAAkJmh7wAwCgAgloDAAABgBYAGkMAAAGAFIAawwAAAUAWABqDAAABABYAGwMAAAEAFYAbQwAAAIAWQDqDAAABQBcAG4MAAACACIAbwwAAAEAPwAdAAkJmh7wAwCgAgloDAAABgBYAGkMAAAGAFIAawwAAAUAWABqDAAABABYAGwMAAAEAFYAbQwAAAIAWQDqDAAABQBcAG4MAAACACIAbwwAAAEAPwAAAA==.Mechadar:BAAALgAECgMJAwAAAA==.Mechanizedtv:BAACLgAFFH8JAAIIAAMJnx8WCAAbAQNoDAAABQBUAGkMAAACAEUA6gwAAAIAWAAIAAMJnx8WCAAbAQNoDAAABQBUAGkMAAACAEUA6gwAAAIAWAAuAAQKf8wABAgACQmwJiQAAIkDAAgACQmwJiQAAIkDAB0ABgl4HB8OAJoBAAEAAQlmAsOHABwAAAAA.',
Mi='Mitskí:BAAALgAECgQJBAAAAA==.',
Mo='Monkerooz:BAAALgAECgUJCAAAAA==.Moodeng:BAAALgADCgYJBwAAAA==.Morphîne:BAACLgAFFH8IAAIPAAIJvBPQQQCHAAJoDAAAAwA4AOoMAAAFACwADwACCbwT0EEAhwACaAwAAAMAOADqDAAABQAsAC4ABAp/FwACDwAHCRke8SgAEAIADwAHCRke8SgAEAIAAAA=.',
Mu='Mugwump:BAAALgAECgUJBQAAAA==.Murdøk:BAABLgAECn8aAAMGAAgJsRdMlwBRAQhoDAAABQBNAGkMAAAGAEwAawwAAAYAJABqDAAAAQA4AGwMAAACADQAbQwAAAEANgDqDAAABAA0AG4MAAABAEkABgAICbEXTJcAUQEIaAwAAAUATQBpDAAABQBMAGsMAAAGACQAagwAAAEAOABsDAAAAgA0AG0MAAABADYA6gwAAAQANABuDAAAAQBJAAcAAQnpDThEADgAAWkMAAABACMAAAA=.',
My='Mythic:BAABLgAECn8mAAITAAgJ6xoUEQAVAghoDAAABgBTAGkMAAAGAEwAawwAAAUAQwBqDAAABABSAGwMAAAFAFMAbQwAAAMANwDqDAAABgBMAG4MAAADACUAEwAICesaFBEAFQIIaAwAAAYAUwBpDAAABgBMAGsMAAAFAEMAagwAAAQAUgBsDAAABQBTAG0MAAADADcA6gwAAAYATABuDAAAAwAlAAAA.',
['Mû']='Mûrdok:BAAALgAECgUJDAABLgAECggJGgAGALEXAA==.',
['Mü']='Mürdok:BAAALgAECgYJDAABLgAECggJGgAGALEXAA==.',
Ne='Necromortas:BAAALgAECgcJBwAAAA==.Nefarius:BAABLgAECn8UAAMOAAkJpxi5XwBpAQloDAAAAgA4AGkMAAADAD0AawwAAAIAQABqDAAAAgA1AGwMAAAEAFoAbQwAAAEAPgDqDAAABABIAG4MAAABACEAbwwAAAEAPgAOAAgJpxi5XwBpAQhoDAAAAgA4AGkMAAADAD0AawwAAAEAQABsDAAAAgBaAG0MAAABAD4A6gwAAAQASABuDAAAAQAhAG8MAAABAD4AHgADCVsUYDsAxgADawwAAAEALwBqDAAAAgA1AGwMAAACADgAAAA=.Neph:BAABLgAECn8aAAMfAAkJQw96HwDlAQloDAAABAARAGkMAAAEADwAawwAAAQASwBqDAAAAwAsAGwMAAADADwAbQwAAAEAEQDqDAAABAATAG4MAAACADIAbwwAAAEABAAfAAkJQw96HwDlAQloDAAAAwARAGkMAAAEADwAawwAAAQASwBqDAAAAwAsAGwMAAADADwAbQwAAAEAEQDqDAAAAwATAG4MAAACADIAbwwAAAEABAAVAAIJbgNeUABNAAJoDAAAAQAEAOoMAAABAA0AAAA=.Nezot:BAAALgADCgkJEAAAAA==.',
Ni='Nihilism:BAAALgADCgYJBgAAAA==.Ninsu:BAAALgAECgYJCgAAAA==.Nishale:BAAALgAECgMJBQAAAA==.',
No='Noir:BAAALgADCgQJBAAAAA==.',
Nu='Nutdraggin:BAAALgADCgcJBwAAAA==.',
Ny='Nyki:BAAALgAECgcJDQAAAA==.',
On='Onlyfist:BAAALgAECgEJAgAAAA==.',
Op='Opius:BAAALgAECggJEAAAAA==.',
Or='Orcmagic:BAAALgADCgUJBwAAAA==.',
Os='Oshift:BAAALgAECgYJBgAAAA==.',
Pa='Pandinha:BAACLgAFFH8XAAIGAAQJ8B2rPQBGAQRoDAAABwBTAGkMAAAFAEUAawwAAAQARwDqDAAABwBRAAYABAnwHas9AEYBBGgMAAAHAFMAaQwAAAUARQBrDAAABABHAOoMAAAHAFEALgAECn82AAIGAAkJNSEsDAA5AwAGAAkJNSEsDAA5AwAAAA==.Paolinelli:BAAALgAFFAEJAQABLgAFFAUJEgAWALUkAA==.Pattêrn:BAAALgAECgYJCAAAAA==.',
Pd='Pdr:BAAALgADCgcJBwAAAA==.',
Pe='Pedri:BAABLgAFFH8KAAMGAAMJQhmuXgAMAQNoDAAABABaAGkMAAABAAQA6gwAAAUAYgAGAAMJQhmuXgAMAQNoDAAAAwBaAGkMAAABAAQA6gwAAAUAYgAUAAEJlw9dFgBNAAFoDAAAAQAnAAAA.Pedrok:BAAALgAECgQJBwAAAA==.',
Ph='Phoenixashes:BAAALgADCgIJAgAAAA==.',
Pi='Picklestein:BAAALgADCgcJCAAAAA==.',
Po='Pokz:BAAALgADCgEJAQAAAA==.',
Pr='Priestiality:BAAALgAECgIJBAAAAA==.Prowl:BAAALgAECgEJAQABLgAFFAYJFAAgALgYAA==.Prscilla:BAAALgADCgcJBgAAAA==.',
Qu='Quixote:BAAALgAECgUJBQAAAA==.',
Ra='Radagast:BAAALgADCgcJDQABLgAFFAMJCAAKAMIFAA==.Radulf:BAAALgAECgQJBAAAAA==.Raph:BAACLgAFFH8TAAIGAAUJAh2zOwBKAQVoDAAABgBcAGkMAAAEAEMAawwAAAIALQBqDAAAAQANAOoMAAAGAFsABgAFCQIdszsASgEFaAwAAAYAXABpDAAABABDAGsMAAACAC0AagwAAAEADQDqDAAABgBbAC4ABAp/KgACBgAICeYfOi0AJgIABgAICeYfOi0AJgIAAAA=.Raphy:BAAALgAFFAMJAwABLgAFFAUJEwAGAAIdAA==.Ravyn:BAAALgADCgUJBQAAAA==.',
Re='Reckon:BAAALgAECgYJDAAAAA==.Redthedeer:BAAALgAFFAIJAgAAAA==.Redthedragon:BAAALgAECgEJAQAAAA==.Redzone:BAAALgAECgQJBgAAAA==.Refuliya:BAAALgADCgkJBwAAAA==.Remmahcm:BAABLgAECn8VAAIJAAgJUBYvPwApAghoDAAABABTAGkMAAAEADsAawwAAAMAUgBqDAAAAwAyAGwMAAADAE0A6gwAAAIAPABuDAAAAQAOAG8MAAABABYACQAICVAWLz8AKQIIaAwAAAQAUwBpDAAABAA7AGsMAAADAFIAagwAAAMAMgBsDAAAAwBNAOoMAAACADwAbgwAAAEADgBvDAAAAQAWAAAA.Renewing:BAAALgADCgQJBAAAAA==.Renrir:BAAALgADCgcJCAAAAA==.',
Rh='Rhark:BAAALgAECgUJDQAAAA==.',
Ri='Rikku:BAAALgAFFAIJAwAAAA==.',
Ro='Rook:BAABLgAECn8rAAIJAAkJISJ2CAANAwloDAAABQBgAGkMAAAGAFoAawwAAAUAYABqDAAABQBSAGwMAAAGAFwAbQwAAAQAVwDqDAAABgBhAG4MAAAEAFkAbwwAAAIAMQAJAAkJISJ2CAANAwloDAAABQBgAGkMAAAGAFoAawwAAAUAYABqDAAABQBSAGwMAAAGAFwAbQwAAAQAVwDqDAAABgBhAG4MAAAEAFkAbwwAAAIAMQAAAA==.',
Ru='Runnow:BAAALgADCgYJCwAAAA==.',
Sa='Sagas:BAAALgAECgEJAQAAAA==.Salina:BAAALgAECgEJAQABLgAECgMJBQACAAAAAA==.Sammysam:BAAALgADCgUJBwAAAA==.Sathor:BAAALgADCgkJDgAAAA==.',
Sc='Scotch:BAAALgADCgQJBAABLgAFFAQJDQATABQPAA==.',
Sh='Shelton:BAAALgADCgMJAwABLgADCggJDQACAAAAAA==.Shinjey:BAAALgAECgMJBwAAAA==.Shocker:BAAALgAECgEJAQAAAA==.',
Si='Sil:BAABLgAECn8ZAAIhAAkJCwr1FwCXAQloDAAABAAuAGkMAAAEAD0AawwAAAQAIwBqDAAAAwAVAGwMAAADAAgAbQwAAAEACwDqDAAAAwAbAG4MAAACAAoAbwwAAAEABAAhAAkJCwr1FwCXAQloDAAABAAuAGkMAAAEAD0AawwAAAQAIwBqDAAAAwAVAGwMAAADAAgAbQwAAAEACwDqDAAAAwAbAG4MAAACAAoAbwwAAAEABAAAAA==.Silents:BAAALgAECgUJBQAAAA==.Siphon:BAAALgAECgYJDAAAAA==.Siphons:BAAALgAECgMJBAAAAA==.',
Sk='Ska:BAACLgAFFH8bAAIOAAcJvBbYCQD6AQdoDAAABgBGAGkMAAAGAEkAawwAAAQASQBqDAAAAwAjAGwMAAABABYAbQwAAAEAGADqDAAABgBUAA4ABwm8FtgJAPoBB2gMAAAGAEYAaQwAAAYASQBrDAAABABJAGoMAAADACMAbAwAAAEAFgBtDAAAAQAYAOoMAAAGAFQALgAECn8bAAMOAAgJux9aGADCAgAOAAgJux9aGADCAgAeAAEJAACTcAA1AAAAAA==.',
Sl='Slyzete:BAAALgAECgQJBwAAAA==.',
So='Softbutt:BAAALgAECggJDwAAAA==.Sophiae:BAAALgAECgIJAgAAAA==.Sophie:BAAALgADCgcJBwAAAA==.Soulseeker:BAABLgAECn8hAAMOAAcJsRR6XQBvAQdoDAAABQA8AGkMAAAIADkAawwAAAQANwBqDAAABABNAGwMAAADACQA6gwAAAcAOQBuDAAAAgAyAA4ABwljFHpdAG8BB2gMAAAFADwAaQwAAAUAOQBrDAAAAgAyAGoMAAAEAE0AbAwAAAMAJADqDAAABwA5AG4MAAACADIAHgACCXwUaFAAfQACaQwAAAMAMQBrDAAAAgA3AAAA.',
St='Stölen:BAAALgAECgEJAQAAAA==.',
Sy='Sylthas:BAAALgADCgMJAwAAAA==.Syrensong:BAAALgAECgQJBAAAAA==.',
Ta='Tankli:BAAALgAECgIJBgAAAA==.Tanriel:BAAALgAECgEJAQAAAA==.Tatl:BAAALgAECgEJAQAAAA==.',
Te='Tertletoes:BAABLgAECn8cAAQiAAkJECXvAAC+AwloDAAABgBjAGkMAAAEAGEAawwAAAQAYABqDAAAAwBfAGwMAAACAGIAbQwAAAEAYgDqDAAABQBgAG4MAAACAFEAbwwAAAEAWwAiAAkJECXvAAC+AwloDAAABABjAGkMAAAEAGEAawwAAAQAYABqDAAAAwBfAGwMAAACAGIAbQwAAAEAYgDqDAAABABgAG4MAAACAFEAbwwAAAEAWwALAAEJ2x46JwBMAAHqDAAAAQBOAAoAAQn+HdzaADkAAWgMAAACAEwAAAA=.Terts:BAAALgAECgEJAQABLgAECgkJHAAiABAlAA==.Teto:BAAALgAECgYJDgAAAA==.',
Th='Thanaz:BAAALgAECgIJAgAAAA==.Thebartender:BAAALgAECgcJDAAAAA==.Thella:BAAALgAECgQJBgAAAA==.Thopowisiwi:BAAALgAFFAIJAwAAAA==.',
To='Tog:BAABLgAECn8bAAIPAAkJciLGAwBVAwloDAAABABZAGkMAAAEAF4AawwAAAQAXABqDAAAAwBdAGwMAAADAGAAbQwAAAEATADqDAAABQBgAG4MAAACAFUAbwwAAAEAQwAPAAkJciLGAwBVAwloDAAABABZAGkMAAAEAF4AawwAAAQAXABqDAAAAwBdAGwMAAADAGAAbQwAAAEATADqDAAABQBgAG4MAAACAFUAbwwAAAEAQwAAAA==.Togame:BAAALgAECgUJCAAAAA==.Toggie:BAAALgADCgkJDgAAAA==.Tognahok:BAAALgADCgYJDgAAAA==.Togy:BAAALgADCgEJAQAAAA==.Tortoisetoes:BAAALgAECgIJAgABLgAECgkJHAAiABAlAA==.',
Tr='Tremboladin:BAABLgAECn8aAAIDAAcJHxo1JgD2AQdoDAAABAA7AGkMAAAEAD0AawwAAAQAQQBqDAAABABhAGwMAAAEAE0AbQwAAAIANADqDAAABAA3AAMABwkfGjUmAPYBB2gMAAAEADsAaQwAAAQAPQBrDAAABABBAGoMAAAEAGEAbAwAAAQATQBtDAAAAgA0AOoMAAAEADcAAS4ABAoDCQQAAgAAAAA=.',
Ts='Tsnt:BAAALgAECgEJAQAAAA==.',
Tu='Turbosocks:BAAALgAECgIJBQAAAA==.Turok:BAAALgADCgMJAwAAAA==.Turtles:BAAALgADCgEJAQABLgAECgkJHAAiABAlAA==.Tuskydin:BAAALgADCgcJCQAAAA==.',
Ty='Tydrin:BAAALgAECgIJAwAAAA==.Tylandord:BAAALgADCgEJAQAAAA==.',
['Tý']='Týråél:BAAALgADCgYJCwAAAA==.',
Ur='Urra:BAABLgAECn8rAAIcAAgJEB76FwD0AQhoDAAACABWAGkMAAAIAFMAawwAAAgAUABqDAAABgA8AGwMAAAFAEIAbQwAAAMATwDqDAAAAwA+AG4MAAACAE8AHAAICRAe+hcA9AEIaAwAAAgAVgBpDAAACABTAGsMAAAIAFAAagwAAAYAPABsDAAABQBCAG0MAAADAE8A6gwAAAMAPgBuDAAAAgBPAAAA.',
Va='Vai:BAAALgAECgMJBAAAAA==.Valoo:BAAALgAECgQJCgAAAA==.Valunar:BAAALgADCgUJBQAAAA==.',
Ve='Veyron:BAAALgADCgMJAwAAAA==.',
Vi='Vicar:BAAALgAECgMJAwAAAA==.',
Vo='Voidstrider:BAAALgAECggJEAAAAA==.',
We='Weezard:BAABLgAECn8mAAIEAAgJPxIAWgCxAQhoDAAACAA6AGkMAAAGAEMAawwAAAYALQBqDAAAAwAdAGwMAAADACgAbQwAAAMAFADqDAAABQAwAG4MAAAEAC4ABAAICT8SAFoAsQEIaAwAAAgAOgBpDAAABgBDAGsMAAAGAC0AagwAAAMAHQBsDAAAAwAoAG0MAAADABQA6gwAAAUAMABuDAAABAAuAAAA.',
Wh='Wheein:BAABLgAECn8jAAIVAAkJ1iFdBQAPAwloDAAABgBhAGkMAAAGAGEAawwAAAUAXQBqDAAABABhAGwMAAAEAFwAbQwAAAIAQgDqDAAABQBaAG4MAAACAEcAbwwAAAEARwAVAAkJ1iFdBQAPAwloDAAABgBhAGkMAAAGAGEAawwAAAUAXQBqDAAABABhAGwMAAAEAFwAbQwAAAIAQgDqDAAABQBaAG4MAAACAEcAbwwAAAEARwAAAA==.',
Wi='Wingolingo:BAAALgAECgIJAgAAAA==.',
Xe='Xeren:BAAALgADCgEJAQAAAA==.',
Ya='Yaamoonn:BAAALgADCgUJBQAAAA==.',
Ye='Yenn:BAABLgAECn8bAAMOAAkJXhtHFgDPAgloDAAABABaAGkMAAAEAFoAawwAAAQAOABqDAAAAwBAAGwMAAADAFoAbQwAAAEAOgDqDAAABQBOAG4MAAACADkAbwwAAAEAJQAOAAkJXhtHFgDPAgloDAAABABaAGkMAAAEAFoAawwAAAQAOABqDAAAAgA/AGwMAAACAFoAbQwAAAEAOgDqDAAABQBOAG4MAAACADkAbwwAAAEAJQAeAAIJwAEuWgBgAAJqDAAAAQBAAGwMAAABAAQAAAA=.',
Za='Zardnax:BAAALgADCgIJBAAAAA==.',
Ze='Zenin:BAAALgADCggJFQAAAA==.Zenu:BAACLgAFFH8JAAMcAAQJFxDBHAAKAQRoDAAAAwAkAGkMAAADADgAawwAAAEAHQDqDAAAAgAqABwABAl0DMEcAAoBBGgMAAACACQAaQwAAAIAEwBrDAAAAQAdAOoMAAABACoAIwADCaoOmAgA4wADaAwAAAEAIwBpDAAAAQA4AOoMAAABABUALgAECn8kAAMcAAkJ6xoWEgCSAgAcAAkJ6xoWEgCSAgAjAAQJNRY9HgC2AAAAAA==.',
Zu='Zugg:BAAALgADCgEJAQAAAA==.',
['Çh']='Çhakra:BAAALgAECgUJBwAAAA==.',
['Ðð']='Ððn:BAAALgADCgMJAQAAAA==.',
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
