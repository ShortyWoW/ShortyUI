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
local provider = {region='US',realm='Warsong',name='US',type='daily',zone=46,date='2026-05-23',data={Ad='Adònis:BAAALgADCgEJAQAAAA==.',
Ae='Aesudan:BAAALgADCgEJAQAAAA==.',
Ah='Aharan:BAABLgAECn8lAAIBAAgJ2w0oKgBRAQhoDAAABgAjAGkMAAAGACYAawwAAAYAFwBqDAAABQATAGwMAAAFACEAbQwAAAIAJgDqDAAABgAmAG4MAAABACcAAQAICdsNKCoAUQEIaAwAAAYAIwBpDAAABgAmAGsMAAAGABcAagwAAAUAEwBsDAAABQAhAG0MAAACACYA6gwAAAYAJgBuDAAAAQAnAAAA.',
Ai='Aiona:BAAALgADCgYJDAAAAA==.',
Al='Alandrov:BAAALgADCgEJAQAAAA==.Alexanzalone:BAAALgADCggJCAAAAA==.Allenduin:BAAALgAECgEJAQAAAA==.Alodso:BAAALgADCgEJAQAAAA==.',
An='Angelique:BAAALgAECgQJBAAAAA==.Angryballz:BAAALgAECgYJBwABLgAECgYJCwACAAAAAA==.Angz:BAAALgAECgUJDQAAAA==.Anielor:BAAALgADCgMJAwAAAA==.Anuksuna:BAAALgAECgUJCQABLgAECgkJHQADAPoWAA==.',
Ar='Arcadia:BAAALgAECgYJDgAAAA==.Arcane:BAACLgAFFH8OAAIEAAUJox6xKQB9AQVoDAAAAwBfAGkMAAADAFIAawwAAAMAWwBqDAAAAgAuAOoMAAADACwABAAFCaMesSkAfQEFaAwAAAMAXwBpDAAAAwBSAGsMAAADAFsAagwAAAIALgDqDAAAAwAsAC4ABAp/HwADBAAJCeAhXBAARgMABAAJCeAhXBAARgMABQAFCUMkFwUA6QEAAAA=.',
As='Asta:BAAALgAECgQJBAAAAA==.',
At='Atulan:BAAALgADCgQJBAAAAA==.',
Au='Austin:BAAALgADCggJFgAAAA==.Automobeer:BAAALgAECgEJBAAAAA==.',
Aw='Awake:BAABLgAECn8mAAMGAAcJthVAZAB7AQdoDAAABgBIAGkMAAAGAEcAawwAAAUANABqDAAABQA0AGwMAAAEACQAbQwAAAYAOADqDAAABgAsAAYABwlsFEBkAHsBB2gMAAAEAEgAaQwAAAQARwBrDAAAAwA0AGoMAAADACoAbAwAAAIAEABtDAAABgA4AOoMAAAEACwABwAGCdoSVh8ASgEGaAwAAAIAOABpDAAAAgA6AGsMAAACADEAagwAAAIANABsDAAAAgAkAOoMAAACACgAAAA=.',
Az='Azazzel:BAAALgADCgEJAQAAAA==.',
Ba='Bambietta:BAAALgADCgkJCQAAAA==.Barebelly:BAAALgAECggJEAAAAA==.',
Be='Bearforce:BAABLgAECn8eAAIIAAkJjxnZCAAbAgloDAAAAgBUAGkMAAACADEAawwAAAIASgBqDAAABQA/AGwMAAAFAFoAbQwAAAMAQwDqDAAABgBQAG4MAAAEABoAbwwAAAEAMgAIAAkJjxnZCAAbAgloDAAAAgBUAGkMAAACADEAawwAAAIASgBqDAAABQA/AGwMAAAFAFoAbQwAAAMAQwDqDAAABgBQAG4MAAAEABoAbwwAAAEAMgAAAA==.',
Bi='Biggbird:BAABLgAECn8gAAIBAAYJJh1VIQCRAQZoDAAABwBJAGkMAAAFAFAAawwAAAYARwBqDAAABQA4AGwMAAAEAEAA6gwAAAUAUwABAAYJJh1VIQCRAQZoDAAABwBJAGkMAAAFAFAAawwAAAYARwBqDAAABQA4AGwMAAAEAEAA6gwAAAUAUwAAAA==.',
Bl='Blewbawl:BAAALgADCgEJAQAAAA==.Blutwin:BAABLgAECn8sAAIJAAkJThM1OAABAgloDAAABwAmAGkMAAAHADMAawwAAAYAOwBqDAAABQAzAGwMAAAGAEkAbQwAAAEAGwDqDAAABgBDAG4MAAAEADkAbwwAAAIAEwAJAAkJThM1OAABAgloDAAABwAmAGkMAAAHADMAawwAAAYAOwBqDAAABQAzAGwMAAAGAEkAbQwAAAEAGwDqDAAABgBDAG4MAAAEADkAbwwAAAIAEwAAAA==.Bluud:BAAALgADCgMJAwAAAA==.',
Bo='Bossdierr:BAACLgAFFH8PAAIKAAMJFyPWLwArAQNoDAAABgBiAGkMAAACAE4A6gwAAAcAXAAKAAMJFyPWLwArAQNoDAAABgBiAGkMAAACAE4A6gwAAAcAXAAuAAQKfzIAAwoACQkyI2wNAL8CAAoACQkyI2wNAL8CAAsACAlCExQNAFQBAAAA.Bossdisan:BAACLgAFFH8LAAIEAAQJQxoZOABSAQRoDAAABABcAGkMAAADAFYAawwAAAEAHgDqDAAAAwA7AAQABAlDGhk4AFIBBGgMAAAEAFwAaQwAAAMAVgBrDAAAAQAeAOoMAAADADsALgAECn8oAAIEAAYJbCRXVwAzAgAEAAYJbCRXVwAzAgAAAA==.Bossmasster:BAAALgAFFAIJAgAAAA==.Bosswudi:BAABLgAFFH8JAAMMAAIJMRNnCACgAAJoDAAABAA+AOoMAAAFACQADQACCcEStBUAoAACaAwAAAMAOwDqDAAAAwAkAAwAAgmKEWcIAKAAAmgMAAABAD4A6gwAAAIAGwAAAA==.',
Br='Brashe:BAABLgAECn8dAAIEAAcJEA7ziABJAQdoDAAABgA5AGkMAAAFAC0AawwAAAUAIQBqDAAABAAVAGwMAAABABIA6gwAAAcAJwBuDAAAAQAVAAQABwkQDvOIAEkBB2gMAAAGADkAaQwAAAUALQBrDAAABQAhAGoMAAAEABUAbAwAAAEAEgDqDAAABwAnAG4MAAABABUAAAA=.Breathe:BAAALgAECgQJBAABLgAECgYJCgACAAAAAA==.Brickbeard:BAAALgAECgYJBgABLgAECgcJEQACAAAAAA==.Bruv:BAABLgAECn8jAAIOAAYJhhU5bwCCAQZoDAAABwBHAGkMAAAGADgAawwAAAYAKwBqDAAABQBUAGwMAAAEACQA6gwAAAcARAAOAAYJhhU5bwCCAQZoDAAABwBHAGkMAAAGADgAawwAAAYAKwBqDAAABQBUAGwMAAAEACQA6gwAAAcARAAAAA==.',
Ca='Calathis:BAAALgAECgEJAQAAAA==.Cazadòr:BAAALgAECgIJAgAAAA==.',
Ch='Chromiepip:BAAALgADCgMJAwAAAA==.',
Co='Corbann:BAAALgAECgYJCgAAAA==.',
Cr='Creamcheese:BAABLgAECn8aAAIPAAcJUB27LAD8AQdoDAAABABSAGkMAAAEAFQAawwAAAQATgBqDAAAAwBSAGwMAAAEAFMAbQwAAAIAFgDqDAAABQBcAA8ABwlQHbssAPwBB2gMAAAEAFIAaQwAAAQAVABrDAAABABOAGoMAAADAFIAbAwAAAQAUwBtDAAAAgAWAOoMAAAFAFwAAAA=.Creamy:BAABLgAECn8yAAIQAAkJABtnFAApAgloDAAABwBfAGkMAAAIAFEAawwAAAcAQQBqDAAABgBAAGwMAAAHAFEAbQwAAAMAOADqDAAABwBLAG4MAAADAB0AbwwAAAIAQwAQAAkJABtnFAApAgloDAAABwBfAGkMAAAIAFEAawwAAAcAQQBqDAAABgBAAGwMAAAHAFEAbQwAAAMAOADqDAAABwBLAG4MAAADAB0AbwwAAAIAQwAAAA==.Crossbreed:BAAALgAFFAIJAwAAAA==.',
Cy='Cyr:BAAALgADCgUJBQAAAA==.Cytosine:BAAALgAFFAEJAQAAAA==.',
Da='Daddyhaz:BAACLgAFFH8HAAIKAAMJZhaYRQDpAANoDAAAAwBKAGkMAAABACAA6gwAAAMAQAAKAAMJZhaYRQDpAANoDAAAAwBKAGkMAAABACAA6gwAAAMAQAAuAAQKf0MAAgoACQmzJAgDAEgDAAoACQmzJAgDAEgDAAAA.Daddywhyudie:BAAALgADCgEJAQAAAA==.Daelyte:BAAALgAECgYJDwAAAA==.Daghor:BAABLgAFFH8GAAINAAIJLBrLJQCgAAJoDAAAAwBUAOoMAAADADEADQACCSwayyUAoAACaAwAAAMAVADqDAAAAwAxAAAA.',
De='Deltron:BAAALgAECgEJAQAAAA==.Desetre:BAAALgADCgIJAgAAAA==.',
Di='Diabos:BAAALgAECgYJBwAAAA==.Dinks:BAABLgAECn86AAIEAAkJXxguLQBHAgloDAAACABTAGkMAAAIAEYAawwAAAgAQQBqDAAABgA4AGwMAAAIADQAbQwAAAUAQQDqDAAACABLAG4MAAAFACUAbwwAAAIAMQAEAAkJXxguLQBHAgloDAAACABTAGkMAAAIAEYAawwAAAgAQQBqDAAABgA4AGwMAAAIADQAbQwAAAUAQQDqDAAACABLAG4MAAAFACUAbwwAAAIAMQAAAA==.Ditzy:BAAALgAECgEJAQAAAA==.',
Do='Docc:BAABLgAECn8XAAINAAkJGA+nFgBXAgloDAAAAwA5AGkMAAADAD4AawwAAAMAOABqDAAAAwAmAGwMAAADADMAbQwAAAEABQDqDAAABAAmAG4MAAACAAgAbwwAAAEAHAANAAkJGA+nFgBXAgloDAAAAwA5AGkMAAADAD4AawwAAAMAOABqDAAAAwAmAGwMAAADADMAbQwAAAEABQDqDAAABAAmAG4MAAACAAgAbwwAAAEAHAAAAA==.Domdps:BAAALgAECgEJAQAAAA==.',
Dr='Draan:BAAALgADCgUJBwAAAA==.Dragorr:BAAALgADCgcJBwAAAA==.Dreadpanda:BAAALgADCgMJAwABLgAFFAQJCAARALIiAA==.Drekkarn:BAAALgADCgMJBgAAAA==.Drood:BAAALgAECgMJBAAAAA==.',
El='Elzath:BAAALgADCggJEAABLgAECgkJIwASAIkUAA==.',
En='Enix:BAAALgADCgYJBgABLgAFFAIJCAAPALwTAA==.',
Er='Erdrick:BAAALgAECgIJBAAAAA==.',
Es='Espeon:BAAALgAECgcJDgAAAA==.',
Eu='Eudisius:BAAALgADCgEJAQAAAA==.',
Ev='Evara:BAABLgAECn8UAAIEAAYJAwdU7gAcAQZoDAAABAAQAGkMAAAEABoAawwAAAQAGQBqDAAAAgALAGwMAAACAAcA6gwAAAQADAAEAAYJAwdU7gAcAQZoDAAABAAQAGkMAAAEABoAawwAAAQAGQBqDAAAAgALAGwMAAACAAcA6gwAAAQADAAAAA==.',
Fa='Faded:BAAALgAECgYJBwAAAA==.Fangbot:BAAALgAECgEJAgAAAA==.',
Fe='Felcaas:BAAALgADCgQJBAAAAA==.Felini:BAABLgAECn8cAAIQAAcJvgdoRwD/AAdoDAAABQAVAGkMAAAFABYAawwAAAQAFwBqDAAABAAVAGwMAAAEABAAbQwAAAEACQDqDAAABQAYABAABwm+B2hHAP8AB2gMAAAFABUAaQwAAAUAFgBrDAAABAAXAGoMAAAEABUAbAwAAAQAEABtDAAAAQAJAOoMAAAFABgAAAA=.Feronar:BAABLgAECn8uAAIQAAkJ+wsZJgCiAQloDAAACAAsAGkMAAAHACcAawwAAAcAJABqDAAABgAnAGwMAAAFACwAbQwAAAMAFQDqDAAACAAjAG4MAAABAAcAbwwAAAEAEQAQAAkJ+wsZJgCiAQloDAAACAAsAGkMAAAHACcAawwAAAcAJABqDAAABgAnAGwMAAAFACwAbQwAAAMAFQDqDAAACAAjAG4MAAABAAcAbwwAAAEAEQAAAA==.',
Fi='Fizzwater:BAAALgAECgYJCAAAAA==.',
Fl='Fleepity:BAAALgAECgcJDwAAAA==.Floopity:BAAALgADCgYJBwAAAA==.Flowermom:BAAALgAECgEJAwAAAA==.Flume:BAAALgAECgcJBwAAAA==.',
Fu='Fusíon:BAEBLgAECn8zAAIKAAkJeiIwDgANAwloDAAACABhAGkMAAAHAGMAawwAAAcAXQBqDAAABwBhAGwMAAAGAGEAbQwAAAMAUwDqDAAACQBaAG4MAAADAEQAbwwAAAEATAAKAAkJeiIwDgANAwloDAAACABhAGkMAAAHAGMAawwAAAcAXQBqDAAABwBhAGwMAAAGAGEAbQwAAAMAUwDqDAAACQBaAG4MAAADAEQAbwwAAAEATAAAAA==.',
Gi='Gin:BAACLgAFFH8NAAITAAQJFA+PEQAPAQRoDAAABAA8AGkMAAADACQAawwAAAIAFQDqDAAABAAjABMABAkUD48RAA8BBGgMAAAEADwAaQwAAAMAJABrDAAAAgAVAOoMAAAEACMALgAECn8vAAITAAkJ9xrDDwAnAgATAAkJ9xrDDwAnAgAAAA==.',
Gj='Gjana:BAAALgAECgUJCQABLgAECggJJgAEAD8SAA==.',
Gl='Glamdring:BAAALgADCgMJAwAAAA==.Glunty:BAAALgAECgUJCAAAAA==.',
Go='Goldpaw:BAAALgADCgEJAQAAAA==.Gorlash:BAAALgAECgcJCAAAAA==.',
Gr='Gridinn:BAAALgADCgIJAgAAAA==.Grimdark:BAAALgAECgQJBAAAAA==.Grimgeth:BAACLgAFFH8PAAIGAAQJeBI3SgA0AQRoDAAABQBVAGkMAAAFADYAawwAAAEACQDqDAAABAAoAAYABAl4EjdKADQBBGgMAAAFAFUAaQwAAAUANgBrDAAAAQAJAOoMAAAEACgALgAECn80AAQGAAkJsyAhEADMAgAGAAkJ2B8hEADMAgAHAAMJVx8CMACxAAAUAAIJ5RdLKQA4AAAAAA==.Grimwrath:BAAALgAECgUJBwABLgAFFAQJDwAGAHgSAA==.',
Gu='Gugaman:BAAALgADCgcJDgAAAA==.Guishin:BAAALgAECgEJAwAAAA==.',
He='Healpls:BAAALgAECgEJAgAAAA==.Heidriel:BAAALgAECgMJAwAAAA==.Herumesu:BAAALgADCgcJCgABLgAFFAUJEwAGAAIdAA==.',
Ho='Holapes:BAAALgAECgUJDwABLgAECgMJBAACAAAAAA==.',
Hu='Huhbruh:BAAALgAECgIJAgABLgAECgYJIwAOAIYVAA==.',
Hw='Hwasa:BAABLgAECn8jAAIRAAkJ4h3kCQB5AgloDAAABgBOAGkMAAAGAFsAawwAAAUAVwBqDAAABABWAGwMAAAEAFoAbQwAAAIARQDqDAAABQBTAG4MAAACACYAbwwAAAEASQARAAkJ4h3kCQB5AgloDAAABgBOAGkMAAAGAFsAawwAAAUAVwBqDAAABABWAGwMAAAEAFoAbQwAAAIARQDqDAAABQBTAG4MAAACACYAbwwAAAEASQAAAA==.',
Il='Illigari:BAAALgAFFAEJAQAAAA==.',
In='Indy:BAAALgADCgUJDQAAAA==.Insanities:BAABLgAECn8/AAIVAAkJIiPTAQCTAwloDAAACQBZAGkMAAAIAFUAawwAAAgAXABqDAAACABgAGwMAAAIAGEAbQwAAAUAYADqDAAACQBZAG4MAAAFAGAAbwwAAAMAQQAVAAkJIiPTAQCTAwloDAAACQBZAGkMAAAIAFUAawwAAAgAXABqDAAACABgAGwMAAAIAGEAbQwAAAUAYADqDAAACQBZAG4MAAAFAGAAbwwAAAMAQQAAAA==.Inti:BAABLgAECn8WAAIDAAYJZhsqKQCdAQZoDAAAAwBZAGkMAAADADoAawwAAAQAQABqDAAABQBCAGwMAAADADUA6gwAAAQAWAADAAYJZhsqKQCdAQZoDAAAAwBZAGkMAAADADoAawwAAAQAQABqDAAABQBCAGwMAAADADUA6gwAAAQAWAABLgAFFAIJCAAPALwTAA==.',
Iz='Izumisakai:BAAALgAECgEJAQABLgAFFAUJEwAGAAIdAA==.',
Ja='Jaidie:BAAALgAECgcJEQAAAA==.',
Je='Jeffreyx:BAAALgAECgYJCAAAAA==.Jeffreyz:BAAALgADCgYJBgAAAA==.',
Jo='Joak:BAAALgADCgUJBQAAAA==.Jota:BAAALgADCgcJCAAAAA==.',
Ka='Kahlán:BAABLgAECn8dAAIDAAkJ+hajGwAAAgloDAAABQBSAGkMAAAGAFcAawwAAAUANQBqDAAAAgA6AGwMAAADACUAbQwAAAEAJwDqDAAABQArAG4MAAABAFMAbwwAAAEAKQADAAkJ+hajGwAAAgloDAAABQBSAGkMAAAGAFcAawwAAAUANQBqDAAAAgA6AGwMAAADACUAbQwAAAEAJwDqDAAABQArAG4MAAABAFMAbwwAAAEAKQAAAA==.Karlangas:BAAALgAECgMJBAAAAA==.',
Ki='Kifu:BAAALgADCgEJAQABLgAECggJJgAEAD8SAA==.Kikipants:BAAALgADCgEJAQAAAA==.Kitrix:BAAALgADCgUJBQAAAA==.Kitty:BAAALgAECgYJBgABLgAFFAQJDgAIAHYHAA==.',
Kr='Krue:BAAALgADCggJDQAAAA==.',
Ku='Kubimage:BAABLgAECn8aAAIEAAkJKhu2MgCoAgloDAAABABcAGkMAAAEAFUAawwAAAQATwBqDAAAAwATAGwMAAADAEMAbQwAAAEATwDqDAAABABTAG4MAAACAB0AbwwAAAEAJgAEAAkJKhu2MgCoAgloDAAABABcAGkMAAAEAFUAawwAAAQATwBqDAAAAwATAGwMAAADAEMAbQwAAAEATwDqDAAABABTAG4MAAACAB0AbwwAAAEAJgAAAA==.',
La='Lane:BAAALgADCgEJAQAAAA==.Layona:BAAALgAECgYJCgAAAA==.',
Le='Lerroy:BAAALgADCgcJCQAAAA==.',
Li='Lildar:BAABLgAECn8nAAIGAAgJnhqsNQAFAghoDAAABgBNAGkMAAAGAE8AawwAAAYASgBqDAAABQBHAGwMAAAFAEAAbQwAAAIALgDqDAAABwBXAG4MAAACAC8ABgAICZ4arDUABQIIaAwAAAYATQBpDAAABgBPAGsMAAAGAEoAagwAAAUARwBsDAAABQBAAG0MAAACAC4A6gwAAAcAVwBuDAAAAgAvAAAA.Linelli:BAAALgAECgcJCwABLgAFFAUJEgAWALUkAA==.Lirra:BAAALgAFFAIJBAABLgAFFAIJCAAPALwTAA==.',
Lo='Lorthiel:BAAALgADCgIJAgAAAA==.Lothus:BAACLgAFFH8IAAIXAAIJgh4YUQC0AAJoDAAABABZAOoMAAAEAEIAFwACCYIeGFEAtAACaAwAAAQAWQDqDAAABABCAC4ABAp/FQADFwAJCQ8bMBgAeAIAFwAJCQ8bMBgAeAIAGAABCXYEY5MAJwAAAS4ABRQCCQgADwC8EwA=.Lox:BAAALgAECgYJCQAAAA==.',
Ls='Lsblkxd:BAAALgADCgYJBgAAAA==.',
Lu='Lumen:BAAALgAECgEJAQAAAA==.Lumverjvcked:BAAALgAECgYJDAABLgAECgYJIwAOAIYVAA==.',
Lx='Lxrbread:BAACLgAFFH8OAAMZAAMJbgzRMwDEAANoDAAABwAYAGkMAAADACAA6gwAAAQAJgAZAAMJbgzRMwDEAANoDAAABQAYAGkMAAADACAA6gwAAAQAJgASAAEJ5QPaGAA8AAFoDAAAAgAJAC4ABAp/OgAEGQAJCfgVDhoA5QEAGQAJCdYVDhoA5QEAEgAFCUEF1jcArQAAGgACCagKQR8AOQAAAAA=.',
['Lë']='Lëgitz:BAABLgAECn8lAAMbAAkJuR9yCAACAwloDAAABgBTAGkMAAAFAFQAawwAAAUASgBqDAAABABeAGwMAAAEAF0AbQwAAAIATADqDAAABgBdAG4MAAAEAEYAbwwAAAEAOwAbAAkJuR9yCAACAwloDAAABQBTAGkMAAAEAFQAawwAAAQASgBqDAAAAwBeAGwMAAADAF0AbQwAAAEATADqDAAABQBdAG4MAAADAEYAbwwAAAEAOwAcAAgJIBRRJQCSAQhoDAAAAQAzAGkMAAABADoAawwAAAEAOwBqDAAAAQA1AGwMAAABAD4AbQwAAAEAEwDqDAAAAQBEAG4MAAABACgAAAA=.',
Ma='Macca:BAAALgAECgUJBQABLgAECgYJCwACAAAAAA==.Maccazilla:BAAALgAECgYJCwAAAA==.Magdalena:BAACLgAFFH8RAAITAAQJcST/AwCoAQRoDAAABQBhAGkMAAAFAF8AawwAAAMAVwDqDAAABABcABMABAlxJP8DAKgBBGgMAAAFAGEAaQwAAAUAXwBrDAAAAwBXAOoMAAAEAFwALgAECn8lAAITAAkJAyW/AgBtAwATAAkJAyW/AgBtAwAAAA==.Magedand:BAAALgAECgMJAwAAAA==.Magnesson:BAAALgAFFAEJAgAAAA==.Manakaren:BAAALgADCggJDAAAAA==.Mazuro:BAACLgAFFH8ZAAINAAYJGhkxCQCaAQZoDAAABwBHAGkMAAAGADwAawwAAAQAVwBqDAAAAwA6AGwMAAABABQA6gwAAAQAUQANAAYJGhkxCQCaAQZoDAAABwBHAGkMAAAGADwAawwAAAQAVwBqDAAAAwA6AGwMAAABABQA6gwAAAQAUQAuAAQKfy4AAw0ACQm5HfsKAFECAA0ACQm5HfsKAFECAAwAAQlGGVodAEAAAAAA.',
Me='Meatkleaver:BAABLgAECn8bAAMUAAkJ0BUhAwBnAgloDAAABABTAGkMAAAEAEAAawwAAAQATwBqDAAAAwAiAGwMAAADAC4AbQwAAAEAJQDqDAAABQBEAG4MAAACACgAbwwAAAEAGgAUAAkJ0BUhAwBnAgloDAAABABTAGkMAAADAEAAawwAAAQATwBqDAAAAwAiAGwMAAADAC4AbQwAAAEAJQDqDAAABQBEAG4MAAACACgAbwwAAAEAGgAGAAEJqAGXNgEiAAFpDAAAAQAEAAAA.Meau:BAABLgAECn8jAAIdAAkJmh4FBACgAgloDAAABgBYAGkMAAAGAFIAawwAAAUAWABqDAAABABYAGwMAAAEAFYAbQwAAAIAWQDqDAAABQBcAG4MAAACACIAbwwAAAEAPwAdAAkJmh4FBACgAgloDAAABgBYAGkMAAAGAFIAawwAAAUAWABqDAAABABYAGwMAAAEAFYAbQwAAAIAWQDqDAAABQBcAG4MAAACACIAbwwAAAEAPwAAAA==.Mechadar:BAAALgAECgMJAwAAAA==.Mechanizedtv:BAACLgAFFH8MAAIIAAQJ6x6BBAB0AQRoDAAABgBcAGkMAAADAFoAawwAAAEALQDqDAAAAgBYAAgABAnrHoEEAHQBBGgMAAAGAFwAaQwAAAMAWgBrDAAAAQAtAOoMAAACAFgALgAECn/MAAQIAAkJsCYlAACJAwAIAAkJsCYlAACJAwAdAAYJeBxjDgCZAQABAAEJZgKViQAcAAAAAA==.',
Mi='Mitskí:BAAALgAECgQJBAAAAA==.',
Mo='Mongerasta:BAAALgAECgEJAQAAAA==.Monkerooz:BAAALgAECgUJCAAAAA==.Moodeng:BAAALgADCgYJBwAAAA==.Morphîne:BAACLgAFFH8IAAIPAAIJvBPTQgCHAAJoDAAAAwA4AOoMAAAFACwADwACCbwT00IAhwACaAwAAAMAOADqDAAABQAsAC4ABAp/FwACDwAHCRke8SgAEAIADwAHCRke8SgAEAIAAAA=.',
Mu='Mugwump:BAAALgAECgUJBQAAAA==.Murdøk:BAABLgAECn8bAAMGAAkJ3hecUACuAQloDAAABQBNAGkMAAAGAEwAawwAAAYAJABqDAAAAQA4AGwMAAACADQAbQwAAAEANgDqDAAABAA0AG4MAAABAEkAbwwAAAEAQAAGAAkJ3hecUACuAQloDAAABQBNAGkMAAAFAEwAawwAAAYAJABqDAAAAQA4AGwMAAACADQAbQwAAAEANgDqDAAABAA0AG4MAAABAEkAbwwAAAEAQAAHAAEJ6Q04RAA4AAFpDAAAAQAjAAAA.',
My='Mythic:BAABLgAECn8oAAITAAgJbRsgEQAYAghoDAAABgBTAGkMAAAGAEwAawwAAAUAQwBqDAAABABSAGwMAAAFAFMAbQwAAAMANwDqDAAABwBMAG4MAAAEAC8AEwAICW0bIBEAGAIIaAwAAAYAUwBpDAAABgBMAGsMAAAFAEMAagwAAAQAUgBsDAAABQBTAG0MAAADADcA6gwAAAcATABuDAAABAAvAAAA.',
['Mû']='Mûrdok:BAAALgAECgUJDAABLgAECgkJGwAGAN4XAA==.',
['Mü']='Mürdok:BAAALgAECgYJDAABLgAECgkJGwAGAN4XAA==.',
Ne='Necromortas:BAAALgAECgcJBwAAAA==.Nefarius:BAABLgAECn8UAAMOAAkJpxjJYABoAQloDAAAAgA4AGkMAAADAD0AawwAAAIAQABqDAAAAgA1AGwMAAAEAFoAbQwAAAEAPgDqDAAABABIAG4MAAABACEAbwwAAAEAPgAOAAgJpxjJYABoAQhoDAAAAgA4AGkMAAADAD0AawwAAAEAQABsDAAAAgBaAG0MAAABAD4A6gwAAAQASABuDAAAAQAhAG8MAAABAD4AHgADCVsUYDsAxgADawwAAAEALwBqDAAAAgA1AGwMAAACADgAAAA=.Neph:BAABLgAECn8aAAMfAAkJQw96HwDlAQloDAAABAARAGkMAAAEADwAawwAAAQASwBqDAAAAwAsAGwMAAADADwAbQwAAAEAEQDqDAAABAATAG4MAAACADIAbwwAAAEABAAfAAkJQw96HwDlAQloDAAAAwARAGkMAAAEADwAawwAAAQASwBqDAAAAwAsAGwMAAADADwAbQwAAAEAEQDqDAAAAwATAG4MAAACADIAbwwAAAEABAAVAAIJbgNeUABNAAJoDAAAAQAEAOoMAAABAA0AAAA=.Nezot:BAAALgADCgkJEAAAAA==.',
Ni='Nihilism:BAAALgADCgYJBgAAAA==.Ninsu:BAAALgAECgYJCgAAAA==.Nishale:BAAALgAECgMJBQAAAA==.',
No='Noir:BAAALgADCgQJBAAAAA==.',
Nu='Nutdraggin:BAAALgADCgcJBwAAAA==.',
Ny='Nyki:BAAALgAECgcJDQAAAA==.',
On='Onlyfist:BAAALgAECgEJAgAAAA==.',
Op='Opius:BAAALgAECggJEAAAAA==.',
Or='Orcmagic:BAAALgADCgUJBwAAAA==.',
Os='Oshift:BAAALgAECgYJBgAAAA==.',
Pa='Pandinha:BAACLgAFFH8XAAIGAAQJ8B0XQABEAQRoDAAABwBTAGkMAAAFAEUAawwAAAQARwDqDAAABwBRAAYABAnwHRdAAEQBBGgMAAAHAFMAaQwAAAUARQBrDAAABABHAOoMAAAHAFEALgAECn82AAIGAAkJNSEsDAA5AwAGAAkJNSEsDAA5AwAAAA==.Paolinelli:BAAALgAFFAEJAQABLgAFFAUJEgAWALUkAA==.Pattêrn:BAAALgAECgYJCAAAAA==.',
Pd='Pdr:BAAALgADCgcJBwAAAA==.',
Pe='Pedri:BAABLgAFFH8KAAMGAAMJQhkKYQAKAQNoDAAABABaAGkMAAABAAQA6gwAAAUAYgAGAAMJQhkKYQAKAQNoDAAAAwBaAGkMAAABAAQA6gwAAAUAYgAUAAEJlw9JFwBNAAFoDAAAAQAnAAAA.Pedrok:BAAALgAECgQJBwAAAA==.',
Ph='Phoenixashes:BAAALgADCgIJAgAAAA==.',
Pi='Picklestein:BAAALgAECgEJAQAAAA==.',
Po='Pokz:BAAALgADCgEJAQAAAA==.',
Pr='Priestiality:BAAALgAECgIJBAAAAA==.Prowl:BAAALgAECgEJAQABLgAFFAYJFAAgALgYAA==.Prscilla:BAAALgADCgcJBgAAAA==.',
Qu='Quixote:BAAALgAECgUJBQAAAA==.',
Ra='Radagast:BAAALgADCgcJDQABLgAFFAMJCAAKAMIFAA==.Radulf:BAAALgAECgQJBAAAAA==.Raph:BAACLgAFFH8TAAIGAAUJAh3BPQBIAQVoDAAABgBcAGkMAAAEAEMAawwAAAIALQBqDAAAAQANAOoMAAAGAFsABgAFCQIdwT0ASAEFaAwAAAYAXABpDAAABABDAGsMAAACAC0AagwAAAEADQDqDAAABgBbAC4ABAp/KgACBgAICeYfES4AJAIABgAICeYfES4AJAIAAAA=.Raphy:BAAALgAFFAMJAwABLgAFFAUJEwAGAAIdAA==.Ravyn:BAAALgADCgUJBQAAAA==.',
Re='Reckon:BAAALgAECgYJDAAAAA==.Redthedeer:BAAALgAFFAIJAgAAAA==.Redthedragon:BAAALgAECgEJAQAAAA==.Redzone:BAAALgAECgQJBgAAAA==.Refuliya:BAAALgADCgkJBwAAAA==.Remmahcm:BAABLgAECn8VAAIJAAgJUBYvPwApAghoDAAABABTAGkMAAAEADsAawwAAAMAUgBqDAAAAwAyAGwMAAADAE0A6gwAAAIAPABuDAAAAQAOAG8MAAABABYACQAICVAWLz8AKQIIaAwAAAQAUwBpDAAABAA7AGsMAAADAFIAagwAAAMAMgBsDAAAAwBNAOoMAAACADwAbgwAAAEADgBvDAAAAQAWAAAA.Renewing:BAAALgADCgQJBAAAAA==.Renrir:BAAALgADCgcJCAAAAA==.',
Rh='Rhark:BAAALgAECgUJDQAAAA==.',
Ri='Rikku:BAAALgAFFAIJAwAAAA==.',
Ro='Rook:BAABLgAECn8rAAIJAAkJISL4CAAJAwloDAAABQBgAGkMAAAGAFoAawwAAAUAYABqDAAABQBSAGwMAAAGAFwAbQwAAAQAVwDqDAAABgBhAG4MAAAEAFkAbwwAAAIAMQAJAAkJISL4CAAJAwloDAAABQBgAGkMAAAGAFoAawwAAAUAYABqDAAABQBSAGwMAAAGAFwAbQwAAAQAVwDqDAAABgBhAG4MAAAEAFkAbwwAAAIAMQAAAA==.',
Ru='Runnow:BAAALgADCgYJCwAAAA==.',
Sa='Sagas:BAAALgAECgEJAQAAAA==.Salina:BAAALgAECgEJAQABLgAECgMJBQACAAAAAA==.Sammysam:BAAALgADCgUJBwAAAA==.Sathor:BAAALgADCgkJDgAAAA==.',
Sc='Scotch:BAAALgADCgQJBAABLgAFFAQJDQATABQPAA==.',
Sh='Shelton:BAAALgADCgMJAwABLgADCggJDQACAAAAAA==.Shinjey:BAAALgAECgMJBwAAAA==.Shocker:BAAALgAECgEJAQAAAA==.',
Si='Sil:BAABLgAECn8ZAAIhAAkJCwr1FwCXAQloDAAABAAuAGkMAAAEAD0AawwAAAQAIwBqDAAAAwAVAGwMAAADAAgAbQwAAAEACwDqDAAAAwAbAG4MAAACAAoAbwwAAAEABAAhAAkJCwr1FwCXAQloDAAABAAuAGkMAAAEAD0AawwAAAQAIwBqDAAAAwAVAGwMAAADAAgAbQwAAAEACwDqDAAAAwAbAG4MAAACAAoAbwwAAAEABAAAAA==.Silents:BAAALgAECgUJBQAAAA==.Siphon:BAAALgAECgYJDAAAAA==.Siphons:BAAALgAECgMJBAAAAA==.',
Sk='Ska:BAACLgAFFH8bAAIOAAcJvBaxCgD4AQdoDAAABgBGAGkMAAAGAEkAawwAAAQASQBqDAAAAwAjAGwMAAABABYAbQwAAAEAGADqDAAABgBUAA4ABwm8FrEKAPgBB2gMAAAGAEYAaQwAAAYASQBrDAAABABJAGoMAAADACMAbAwAAAEAFgBtDAAAAQAYAOoMAAAGAFQALgAECn8bAAMOAAgJux9aGADCAgAOAAgJux9aGADCAgAeAAEJAACTcAA1AAAAAA==.',
Sl='Slyzete:BAAALgAECgQJBwAAAA==.',
So='Softbutt:BAAALgAECggJDwAAAA==.Sophiae:BAAALgAECgIJAgAAAA==.Sophie:BAAALgADCgcJBwAAAA==.Soulseeker:BAABLgAECn8iAAMOAAcJsRSRXgBuAQdoDAAABQA8AGkMAAAIADkAawwAAAQANwBqDAAABQBNAGwMAAADACQA6gwAAAcAOQBuDAAAAgAyAA4ABwljFJFeAG4BB2gMAAAFADwAaQwAAAUAOQBrDAAAAgAyAGoMAAAFAE0AbAwAAAMAJADqDAAABwA5AG4MAAACADIAHgACCXwUaFAAfQACaQwAAAMAMQBrDAAAAgA3AAAA.',
St='Stölen:BAAALgAECgEJAQAAAA==.',
Sy='Sylthas:BAAALgADCgMJAwAAAA==.Syrensong:BAAALgAECgQJBAAAAA==.',
Ta='Tankli:BAAALgAECgIJBgAAAA==.Tanriel:BAAALgAECgEJAQAAAA==.Tatl:BAAALgAECgEJAQAAAA==.',
Te='Tertletoes:BAABLgAECn8cAAQiAAkJECXvAAC+AwloDAAABgBjAGkMAAAEAGEAawwAAAQAYABqDAAAAwBfAGwMAAACAGIAbQwAAAEAYgDqDAAABQBgAG4MAAACAFEAbwwAAAEAWwAiAAkJECXvAAC+AwloDAAABABjAGkMAAAEAGEAawwAAAQAYABqDAAAAwBfAGwMAAACAGIAbQwAAAEAYgDqDAAABABgAG4MAAACAFEAbwwAAAEAWwALAAEJ2x46JwBMAAHqDAAAAQBOAAoAAQn+HdzaADkAAWgMAAACAEwAAAA=.Terts:BAAALgAECgEJAQABLgAECgkJHAAiABAlAA==.Teto:BAAALgAECgYJDgAAAA==.',
Th='Thanaz:BAAALgAECgIJAgAAAA==.Thebartender:BAAALgAECgcJDAAAAA==.Thella:BAAALgAECgQJBgAAAA==.Thopowisiwi:BAAALgAFFAIJAwAAAA==.',
To='Tog:BAABLgAECn8bAAIPAAkJciLGAwBVAwloDAAABABZAGkMAAAEAF4AawwAAAQAXABqDAAAAwBdAGwMAAADAGAAbQwAAAEATADqDAAABQBgAG4MAAACAFUAbwwAAAEAQwAPAAkJciLGAwBVAwloDAAABABZAGkMAAAEAF4AawwAAAQAXABqDAAAAwBdAGwMAAADAGAAbQwAAAEATADqDAAABQBgAG4MAAACAFUAbwwAAAEAQwAAAA==.Togame:BAAALgAECgUJCAAAAA==.Toggie:BAAALgADCgkJDgAAAA==.Tognahok:BAAALgADCgYJDgAAAA==.Togy:BAAALgADCgEJAQAAAA==.Tortoisetoes:BAAALgAECgIJAgABLgAECgkJHAAiABAlAA==.',
Tr='Tremboladin:BAABLgAECn8aAAIDAAcJHxo1JgD2AQdoDAAABAA7AGkMAAAEAD0AawwAAAQAQQBqDAAABABhAGwMAAAEAE0AbQwAAAIANADqDAAABAA3AAMABwkfGjUmAPYBB2gMAAAEADsAaQwAAAQAPQBrDAAABABBAGoMAAAEAGEAbAwAAAQATQBtDAAAAgA0AOoMAAAEADcAAS4ABAoGCQcAAgAAAAA=.',
Ts='Tsnt:BAAALgAECgEJAQAAAA==.',
Tu='Turbosocks:BAAALgAECgIJBQAAAA==.Turok:BAAALgADCgMJAwAAAA==.Turtles:BAAALgADCgEJAQABLgAECgkJHAAiABAlAA==.Tuskydin:BAAALgADCgcJCQAAAA==.',
Ty='Tydrin:BAAALgAECgIJAwAAAA==.Tylandord:BAAALgADCgEJAQAAAA==.',
['Tý']='Týråél:BAAALgADCgYJCwAAAA==.',
Ur='Urra:BAABLgAECn8rAAIcAAgJEB5mGAD0AQhoDAAACABWAGkMAAAIAFMAawwAAAgAUABqDAAABgA8AGwMAAAFAEIAbQwAAAMATwDqDAAAAwA+AG4MAAACAE8AHAAICRAeZhgA9AEIaAwAAAgAVgBpDAAACABTAGsMAAAIAFAAagwAAAYAPABsDAAABQBCAG0MAAADAE8A6gwAAAMAPgBuDAAAAgBPAAAA.',
Va='Vai:BAAALgAECgMJBAAAAA==.Valoo:BAAALgAECgQJCgAAAA==.Valunar:BAAALgADCgUJBQAAAA==.',
Ve='Veyron:BAAALgADCgMJAwAAAA==.',
Vi='Vicar:BAAALgAECgMJAwAAAA==.',
Vo='Voidstrider:BAAALgAECggJEAAAAA==.',
We='Weezard:BAABLgAECn8mAAIEAAgJPxJ+WwCvAQhoDAAACAA6AGkMAAAGAEMAawwAAAYALQBqDAAAAwAdAGwMAAADACgAbQwAAAMAFADqDAAABQAwAG4MAAAEAC4ABAAICT8SflsArwEIaAwAAAgAOgBpDAAABgBDAGsMAAAGAC0AagwAAAMAHQBsDAAAAwAoAG0MAAADABQA6gwAAAUAMABuDAAABAAuAAAA.',
Wh='Wheein:BAABLgAECn8jAAIVAAkJ1iGABQANAwloDAAABgBhAGkMAAAGAGEAawwAAAUAXQBqDAAABABhAGwMAAAEAFwAbQwAAAIAQgDqDAAABQBaAG4MAAACAEcAbwwAAAEARwAVAAkJ1iGABQANAwloDAAABgBhAGkMAAAGAGEAawwAAAUAXQBqDAAABABhAGwMAAAEAFwAbQwAAAIAQgDqDAAABQBaAG4MAAACAEcAbwwAAAEARwAAAA==.',
Wi='Wingolingo:BAAALgAECgIJAgAAAA==.',
Xe='Xeren:BAAALgADCgEJAQAAAA==.',
Ya='Yaamoonn:BAAALgADCgUJBQAAAA==.',
Ye='Yenn:BAABLgAECn8bAAMOAAkJXhtHFgDPAgloDAAABABaAGkMAAAEAFoAawwAAAQAOABqDAAAAwBAAGwMAAADAFoAbQwAAAEAOgDqDAAABQBOAG4MAAACADkAbwwAAAEAJQAOAAkJXhtHFgDPAgloDAAABABaAGkMAAAEAFoAawwAAAQAOABqDAAAAgA/AGwMAAACAFoAbQwAAAEAOgDqDAAABQBOAG4MAAACADkAbwwAAAEAJQAeAAIJwAEuWgBgAAJqDAAAAQBAAGwMAAABAAQAAAA=.',
Za='Zardnax:BAAALgADCgIJBAAAAA==.',
Ze='Zenin:BAAALgADCggJFQAAAA==.Zenu:BAACLgAFFH8JAAMcAAQJFxB0HQAKAQRoDAAAAwAkAGkMAAADADgAawwAAAEAHQDqDAAAAgAqABwABAl0DHQdAAoBBGgMAAACACQAaQwAAAIAEwBrDAAAAQAdAOoMAAABACoAIwADCaoO2wgA4wADaAwAAAEAIwBpDAAAAQA4AOoMAAABABUALgAECn8kAAMcAAkJ6xoWEgCSAgAcAAkJ6xoWEgCSAgAjAAQJNRbLHgC2AAAAAA==.',
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
