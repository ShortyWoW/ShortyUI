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

local lookup = {'Druid-Balance','Unknown-Unknown','Mage-Frost','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Blood','Druid-Guardian','Paladin-Retribution','DemonHunter-Devourer','DemonHunter-Vengeance','Rogue-Assassination','Rogue-Subtlety','Warlock-Demonology','Druid-Restoration','Warrior-Fury','Monk-Brewmaster','Evoker-Preservation','Monk-Windwalker','DeathKnight-Frost','Priest-Discipline','Paladin-Holy','Rogue-Outlaw','Hunter-BeastMastery','Hunter-Marksmanship','Evoker-Augmentation','Evoker-Devastation','Shaman-Restoration','Shaman-Elemental','Druid-Feral','Priest-Holy','Warrior-Arms','Warrior-Protection','Warlock-Destruction','DemonHunter-Havoc','Shaman-Enhancement',}
local provider = {region='US',realm='Warsong',name='US',type='daily',zone=46,date='2026-05-20',data={Ad='Adònis:BAAALgADCgEJAQAAAA==.',
Ae='Aesudan:BAAALgADCgEJAQAAAA==.',
Ah='Aharan:BAABLgAECn8kAAIBAAcJng3+LwAjAQdoDAAABgAjAGkMAAAGACYAawwAAAYAFwBqDAAABQATAGwMAAAFACEAbQwAAAIAJgDqDAAABgAmAAEABwmeDf4vACMBB2gMAAAGACMAaQwAAAYAJgBrDAAABgAXAGoMAAAFABMAbAwAAAUAIQBtDAAAAgAmAOoMAAAGACYAAAA=.',
Ai='Aiona:BAAALgADCgYJDAAAAA==.',
Al='Alandrov:BAAALgADCgEJAQAAAA==.Alexanzalone:BAAALgADCggJCAAAAA==.Allenduin:BAAALgAECgEJAQAAAA==.Alodso:BAAALgADCgEJAQAAAA==.',
An='Angelique:BAAALgAECgQJBAAAAA==.Angryballz:BAAALgAECgYJBwABLgAECgYJCwACAAAAAA==.Angz:BAAALgAECgUJDQAAAA==.Anielor:BAAALgADCgMJAwAAAA==.Anuksuna:BAAALgAECgUJCQABLgAECgYJEwACAAAAAA==.',
Ar='Arcadia:BAAALgAECgYJDgAAAA==.Arcane:BAACLgAFFH8JAAIDAAUJLh3WKwBqAQVoDAAAAgBeAGkMAAACAEoAawwAAAIAWwBqDAAAAQAuAOoMAAACACYAAwAFCS4d1isAagEFaAwAAAIAXgBpDAAAAgBKAGsMAAACAFsAagwAAAEALgDqDAAAAgAmAC4ABAp/HwADAwAJCeAhXBAARgMAAwAJCeAhXBAARgMABAAFCUMkFwUA6QEAAAA=.',
As='Asta:BAAALgAECgQJBAAAAA==.',
At='Atulan:BAAALgADCgQJBAAAAA==.',
Au='Austin:BAAALgADCggJFgAAAA==.Automobeer:BAAALgAECgEJBAAAAA==.',
Aw='Awake:BAABLgAECn8hAAMFAAcJZBR8aQBoAQdoDAAABQA4AGkMAAAFAEcAawwAAAUANABqDAAABQA0AGwMAAAEACQAbQwAAAQAOADqDAAABQAoAAUABwmNEnxpAGgBB2gMAAADADIAaQwAAAMARwBrDAAAAwA0AGoMAAADACoAbAwAAAIAEABtDAAABAA4AOoMAAADACUABgAGCdoSVh8ASgEGaAwAAAIAOABpDAAAAgA6AGsMAAACADEAagwAAAIANABsDAAAAgAkAOoMAAACACgAAAA=.',
Az='Azazzel:BAAALgADCgEJAQAAAA==.',
Ba='Bambietta:BAAALgADCgkJCQAAAA==.Barebelly:BAAALgAECggJEAAAAA==.',
Be='Bearforce:BAABLgAECn8eAAIHAAkJjxnZCAAbAgloDAAAAgBUAGkMAAACADEAawwAAAIASgBqDAAABQA/AGwMAAAFAFoAbQwAAAMAQwDqDAAABgBQAG4MAAAEABoAbwwAAAEAMgAHAAkJjxnZCAAbAgloDAAAAgBUAGkMAAACADEAawwAAAIASgBqDAAABQA/AGwMAAAFAFoAbQwAAAMAQwDqDAAABgBQAG4MAAAEABoAbwwAAAEAMgAAAA==.',
Bi='Biggbird:BAABLgAECn8gAAIBAAYJJh03HwCVAQZoDAAABwBJAGkMAAAFAFAAawwAAAYARwBqDAAABQA4AGwMAAAEAEAA6gwAAAUAUwABAAYJJh03HwCVAQZoDAAABwBJAGkMAAAFAFAAawwAAAYARwBqDAAABQA4AGwMAAAEAEAA6gwAAAUAUwAAAA==.',
Bl='Blewbawl:BAAALgADCgEJAQAAAA==.Blutwin:BAABLgAECn8rAAIIAAkJTBPQMgALAgloDAAABwAmAGkMAAAHADMAawwAAAYAOwBqDAAABQAzAGwMAAAGAEkAbQwAAAEAGwDqDAAABgBDAG4MAAAEADkAbwwAAAEAEwAIAAkJTBPQMgALAgloDAAABwAmAGkMAAAHADMAawwAAAYAOwBqDAAABQAzAGwMAAAGAEkAbQwAAAEAGwDqDAAABgBDAG4MAAAEADkAbwwAAAEAEwAAAA==.Bluud:BAAALgADCgMJAwAAAA==.',
Bo='Bossdierr:BAACLgAFFH8PAAIJAAMJFyOpKgAxAQNoDAAABgBiAGkMAAACAE4A6gwAAAcAXAAJAAMJFyOpKgAxAQNoDAAABgBiAGkMAAACAE4A6gwAAAcAXAAuAAQKfzIAAwkACQkyIwooAAICAAkACQkyIwooAAICAAoACAlCEzMMAFgBAAAA.Bossdisan:BAACLgAFFH8LAAIDAAQJQxq+MABeAQRoDAAABABcAGkMAAADAFYAawwAAAEAHgDqDAAAAwA7AAMABAlDGr4wAF4BBGgMAAAEAFwAaQwAAAMAVgBrDAAAAQAeAOoMAAADADsALgAECn8oAAIDAAYJbCRhSADaAQADAAYJbCRhSADaAQAAAA==.Bossmasster:BAAALgAFFAIJAgAAAA==.Bosswudi:BAABLgAFFH8JAAMLAAIJMRPmBwChAAJoDAAABAA+AOoMAAAFACQACwACCYoR5gcAoQACaAwAAAEAPgDqDAAAAgAbAAwAAgnBEkgjAJ8AAmgMAAADADsA6gwAAAMAJAAAAA==.',
Br='Brashe:BAABLgAECn8YAAIDAAYJkg4ToAAXAQZoDAAABQA5AGkMAAAEAC0AawwAAAQAIQBqDAAABAAVAGwMAAABABIA6gwAAAYAHwADAAYJkg4ToAAXAQZoDAAABQA5AGkMAAAEAC0AawwAAAQAIQBqDAAABAAVAGwMAAABABIA6gwAAAYAHwAAAA==.Breathe:BAAALgAECgQJBAAAAA==.Brickbeard:BAAALgAECgYJBgABLgAECgcJEQACAAAAAA==.Bruv:BAABLgAECn8jAAINAAYJhhU5bwCCAQZoDAAABwBHAGkMAAAGADgAawwAAAYAKwBqDAAABQBUAGwMAAAEACQA6gwAAAcARAANAAYJhhU5bwCCAQZoDAAABwBHAGkMAAAGADgAawwAAAYAKwBqDAAABQBUAGwMAAAEACQA6gwAAAcARAAAAA==.',
Ca='Calathis:BAAALgAECgEJAQAAAA==.Cazadòr:BAAALgAECgIJAgAAAA==.',
Ch='Chromiepip:BAAALgADCgMJAwAAAA==.',
Co='Corbann:BAAALgAECgYJCgAAAA==.',
Cr='Creamcheese:BAABLgAECn8aAAIOAAcJUB2nKQDaAQdoDAAABABSAGkMAAAEAFQAawwAAAQATgBqDAAAAwBSAGwMAAAEAFMAbQwAAAIAFgDqDAAABQBcAA4ABwlQHacpANoBB2gMAAAEAFIAaQwAAAQAVABrDAAABABOAGoMAAADAFIAbAwAAAQAUwBtDAAAAgAWAOoMAAAFAFwAAAA=.Creamy:BAABLgAECn8rAAIPAAkJ8BlSEgAyAgloDAAABgBfAGkMAAAHADwAawwAAAYAQQBqDAAABQBAAGwMAAAGAFEAbQwAAAIAOADqDAAABwBLAG4MAAADAB0AbwwAAAEAQwAPAAkJ8BlSEgAyAgloDAAABgBfAGkMAAAHADwAawwAAAYAQQBqDAAABQBAAGwMAAAGAFEAbQwAAAIAOADqDAAABwBLAG4MAAADAB0AbwwAAAEAQwAAAA==.Crossbreed:BAAALgAFFAIJAwAAAA==.',
Cy='Cyr:BAAALgADCgUJBQAAAA==.Cytosine:BAAALgAFFAEJAQAAAA==.',
Da='Daddyhaz:BAACLgAFFH8HAAIJAAMJZhYrQADvAANoDAAAAwBKAGkMAAABACAA6gwAAAMAQAAJAAMJZhYrQADvAANoDAAAAwBKAGkMAAABACAA6gwAAAMAQAAuAAQKf0MAAgkACQmzJKQCAEwDAAkACQmzJKQCAEwDAAAA.Daddywhyudie:BAAALgADCgEJAQAAAA==.Daelyte:BAAALgAECgYJDwAAAA==.Daghor:BAABLgAFFH8GAAIMAAIJLBoaIwCgAAJoDAAAAwBUAOoMAAADADEADAACCSwaGiMAoAACaAwAAAMAVADqDAAAAwAxAAAA.',
De='Deltron:BAAALgAECgEJAQAAAA==.Desetre:BAAALgADCgIJAgAAAA==.',
Di='Dinks:BAABLgAECn8xAAIDAAkJ4hbRPAAAAgloDAAABwBTAGkMAAAHAD0AawwAAAcAQQBqDAAABQA4AGwMAAAHADMAbQwAAAQANADqDAAABwBLAG4MAAAEACMAbwwAAAEAKgADAAkJ4hbRPAAAAgloDAAABwBTAGkMAAAHAD0AawwAAAcAQQBqDAAABQA4AGwMAAAHADMAbQwAAAQANADqDAAABwBLAG4MAAAEACMAbwwAAAEAKgAAAA==.Ditzy:BAAALgAECgEJAQAAAA==.',
Do='Docc:BAABLgAECn8XAAIMAAkJGA+nFgBXAgloDAAAAwA5AGkMAAADAD4AawwAAAMAOABqDAAAAwAmAGwMAAADADMAbQwAAAEABQDqDAAABAAmAG4MAAACAAgAbwwAAAEAHAAMAAkJGA+nFgBXAgloDAAAAwA5AGkMAAADAD4AawwAAAMAOABqDAAAAwAmAGwMAAADADMAbQwAAAEABQDqDAAABAAmAG4MAAACAAgAbwwAAAEAHAAAAA==.Domdps:BAAALgAECgEJAQAAAA==.',
Dr='Draan:BAAALgADCgUJBwAAAA==.Dragorr:BAAALgADCgcJBwAAAA==.Dreadpanda:BAAALgADCgMJAwABLgAFFAQJCAAQALIiAA==.Drekkarn:BAAALgADCgMJBgAAAA==.Drood:BAAALgAECgMJBAAAAA==.',
El='Elzath:BAAALgADCggJEAABLgAECgkJIwARAIkUAA==.',
En='Enix:BAAALgADCgYJBgABLgAFFAIJCAAOALwTAA==.',
Er='Erdrick:BAAALgAECgIJBAAAAA==.',
Es='Espeon:BAAALgAECgcJDgAAAA==.',
Eu='Eudisius:BAAALgADCgEJAQAAAA==.',
Ev='Evara:BAABLgAECn8UAAIDAAYJAwdU7gAcAQZoDAAABAAQAGkMAAAEABoAawwAAAQAGQBqDAAAAgALAGwMAAACAAcA6gwAAAQADAADAAYJAwdU7gAcAQZoDAAABAAQAGkMAAAEABoAawwAAAQAGQBqDAAAAgALAGwMAAACAAcA6gwAAAQADAAAAA==.',
Fa='Faded:BAAALgAECgEJAQAAAA==.Fangbot:BAAALgAECgEJAgAAAA==.',
Fe='Felcaas:BAAALgADCgQJBAAAAA==.Felini:BAABLgAECn8cAAIPAAcJvQf7QwACAQdoDAAABQAVAGkMAAAFABYAawwAAAQAFwBqDAAABAAVAGwMAAAEABAAbQwAAAEACQDqDAAABQAYAA8ABwm9B/tDAAIBB2gMAAAFABUAaQwAAAUAFgBrDAAABAAXAGoMAAAEABUAbAwAAAQAEABtDAAAAQAJAOoMAAAFABgAAAA=.Feronar:BAABLgAECn8nAAIPAAkJsgpxJgCVAQloDAAABwAbAGkMAAAGACcAawwAAAYAJABqDAAABQAnAGwMAAAEACoAbQwAAAIAFQDqDAAABwAbAG4MAAABAAcAbwwAAAEAEQAPAAkJsgpxJgCVAQloDAAABwAbAGkMAAAGACcAawwAAAYAJABqDAAABQAnAGwMAAAEACoAbQwAAAIAFQDqDAAABwAbAG4MAAABAAcAbwwAAAEAEQAAAA==.',
Fi='Fizzwater:BAAALgAECgYJCAAAAA==.',
Fl='Fleepity:BAAALgAECgcJDQAAAA==.Floopity:BAAALgADCgYJBwAAAA==.Flowermom:BAAALgAECgEJAwAAAA==.Flume:BAAALgAECgcJBwAAAA==.',
Fu='Fusíon:BAEBLgAECn8zAAIJAAkJdiIwDgANAwloDAAACABhAGkMAAAHAGMAawwAAAcAXQBqDAAABwBhAGwMAAAGAGEAbQwAAAMAUwDqDAAACQBaAG4MAAADAEQAbwwAAAEATAAJAAkJdiIwDgANAwloDAAACABhAGkMAAAHAGMAawwAAAcAXQBqDAAABwBhAGwMAAAGAGEAbQwAAAMAUwDqDAAACQBaAG4MAAADAEQAbwwAAAEATAAAAA==.',
Gi='Gin:BAACLgAFFH8JAAISAAQJMwpaEgD9AARoDAAAAwAgAGkMAAACAA4AawwAAAEAFQDqDAAAAwAjABIABAkzCloSAP0ABGgMAAADACAAaQwAAAIADgBrDAAAAQAVAOoMAAADACMALgAECn8vAAISAAkJ9xp/DgAuAgASAAkJ9xp/DgAuAgAAAA==.',
Gj='Gjana:BAAALgAECgQJBAABLgAECggJJQADAP4RAA==.',
Gl='Glamdring:BAAALgADCgMJAwAAAA==.Glunty:BAAALgAECgUJCAAAAA==.',
Go='Goldpaw:BAAALgADCgEJAQAAAA==.Gorlash:BAAALgAECgcJCAAAAA==.',
Gr='Gridinn:BAAALgADCgIJAgAAAA==.Grimdark:BAAALgAECgMJAwAAAA==.Grimgeth:BAACLgAFFH8PAAIFAAQJeBJ9QQBAAQRoDAAABQBVAGkMAAAFADYAawwAAAEACQDqDAAABAAoAAUABAl4En1BAEABBGgMAAAFAFUAaQwAAAUANgBrDAAAAQAJAOoMAAAEACgALgAECn8wAAQFAAkJniDvDgDNAgAFAAkJwh/vDgDNAgAGAAMJVx+cLQCzAAATAAIJ5RdMJgA5AAAAAA==.Grimwrath:BAAALgAECgUJBwABLgAFFAQJDwAFAHgSAA==.',
Gu='Gugaman:BAAALgADCgcJDgAAAA==.Guishin:BAAALgAECgEJAwAAAA==.',
He='Healpls:BAAALgAECgEJAgAAAA==.Heidriel:BAAALgAECgMJAwAAAA==.Herumesu:BAAALgADCgcJCgABLgAFFAUJEwAFAAIdAA==.',
Ho='Holapes:BAAALgAECgUJDwABLgAECgMJBAACAAAAAA==.',
Hu='Huhbruh:BAAALgAECgIJAgABLgAECgYJIwANAIYVAA==.',
Hw='Hwasa:BAABLgAECn8jAAIQAAkJ4h3wCACBAgloDAAABgBOAGkMAAAGAFsAawwAAAUAVwBqDAAABABWAGwMAAAEAFoAbQwAAAIARQDqDAAABQBTAG4MAAACACYAbwwAAAEASQAQAAkJ4h3wCACBAgloDAAABgBOAGkMAAAGAFsAawwAAAUAVwBqDAAABABWAGwMAAAEAFoAbQwAAAIARQDqDAAABQBTAG4MAAACACYAbwwAAAEASQAAAA==.',
Il='Illigari:BAAALgAFFAEJAQAAAA==.',
In='Indy:BAAALgADCgUJDQAAAA==.Insanities:BAABLgAECn83AAIUAAkJQSGiAwA+AwloDAAACABZAGkMAAAHAFUAawwAAAcAXABqDAAABwBcAGwMAAAHAFYAbQwAAAQAVADqDAAACABZAG4MAAAEAFAAbwwAAAMAQQAUAAkJQSGiAwA+AwloDAAACABZAGkMAAAHAFUAawwAAAcAXABqDAAABwBcAGwMAAAHAFYAbQwAAAQAVADqDAAACABZAG4MAAAEAFAAbwwAAAMAQQAAAA==.Inti:BAABLgAECn8WAAIVAAYJZhvoJgCgAQZoDAAAAwBZAGkMAAADADoAawwAAAQAQABqDAAABQBCAGwMAAADADUA6gwAAAQAWAAVAAYJZhvoJgCgAQZoDAAAAwBZAGkMAAADADoAawwAAAQAQABqDAAABQBCAGwMAAADADUA6gwAAAQAWAABLgAFFAIJCAAOALwTAA==.',
Iz='Izumisakai:BAAALgAECgEJAQABLgAFFAUJEwAFAAIdAA==.',
Ja='Jaidie:BAAALgAECgUJCgAAAA==.',
Je='Jeffreyx:BAAALgAECgYJCAAAAA==.Jeffreyz:BAAALgADCgYJBgAAAA==.',
Jo='Joak:BAAALgADCgUJBQAAAA==.Jota:BAAALgADCgcJCAAAAA==.',
Ka='Kahlán:BAAALgAECgYJEwAAAA==.Karlangas:BAAALgAECgMJBAAAAA==.',
Ki='Kifu:BAAALgADCgEJAQABLgAECggJJQADAP4RAA==.Kikipants:BAAALgADCgEJAQAAAA==.Kitrix:BAAALgADCgUJBQAAAA==.Kitty:BAAALgAECgYJBgABLgAFFAMJDQAHAIEIAA==.',
Kr='Krue:BAAALgADCggJDQAAAA==.',
Ku='Kubimage:BAABLgAECn8aAAIDAAkJKhu2MgCoAgloDAAABABcAGkMAAAEAFUAawwAAAQATwBqDAAAAwATAGwMAAADAEMAbQwAAAEATwDqDAAABABTAG4MAAACAB0AbwwAAAEAJgADAAkJKhu2MgCoAgloDAAABABcAGkMAAAEAFUAawwAAAQATwBqDAAAAwATAGwMAAADAEMAbQwAAAEATwDqDAAABABTAG4MAAACAB0AbwwAAAEAJgAAAA==.',
La='Lane:BAAALgADCgEJAQAAAA==.Layona:BAAALgAECgYJCgAAAA==.',
Le='Lerroy:BAAALgADCgcJCQAAAA==.',
Li='Lildar:BAABLgAECn8gAAIFAAgJjxrEPgDfAQhoDAAABQBNAGkMAAAFAE8AawwAAAUASgBqDAAABABHAGwMAAAEAD8AbQwAAAEALgDqDAAABgBXAG4MAAACAC8ABQAICY8axD4A3wEIaAwAAAUATQBpDAAABQBPAGsMAAAFAEoAagwAAAQARwBsDAAABAA/AG0MAAABAC4A6gwAAAYAVwBuDAAAAgAvAAAA.Linelli:BAAALgAECgcJCwABLgAFFAUJEgAWALUkAA==.Lirra:BAAALgAFFAIJBAABLgAFFAIJCAAOALwTAA==.',
Lo='Lorthiel:BAAALgADCgIJAgAAAA==.Lothus:BAACLgAFFH8IAAIXAAIJgh7qSAC+AAJoDAAABABZAOoMAAAEAEIAFwACCYIe6kgAvgACaAwAAAQAWQDqDAAABABCAC4ABAp/FQADFwAJCQ8bMBgAeAIAFwAJCQ8bMBgAeAIAGAABCXYEY5MAJwAAAS4ABRQCCQgADgC8EwA=.Lox:BAAALgAECgYJCQAAAA==.',
Ls='Lsblkxd:BAAALgADCgYJBgAAAA==.',
Lu='Lumen:BAAALgAECgEJAQAAAA==.Lumverjvcked:BAAALgAECgYJDAABLgAECgYJIwANAIYVAA==.',
Lx='Lxrbread:BAACLgAFFH8OAAMZAAMJbgyrLwDOAANoDAAABwAYAGkMAAADACAA6gwAAAQAJgAZAAMJbgyrLwDOAANoDAAABQAYAGkMAAADACAA6gwAAAQAJgARAAEJ5QPaGAA8AAFoDAAAAgAJAC4ABAp/OQAEGQAJCVAVyR0A1wEAGQAJCS4VyR0A1wEAEQAFCUEF1jcArQAAGgACCagKKB4AOQAAAAA=.',
['Lë']='Lëgitz:BAABLgAECn8lAAMbAAkJuh9HBwAHAwloDAAABgBTAGkMAAAFAFQAawwAAAUASgBqDAAABABeAGwMAAAEAF0AbQwAAAIATADqDAAABgBdAG4MAAAEAEYAbwwAAAEAOwAbAAkJuh9HBwAHAwloDAAABQBTAGkMAAAEAFQAawwAAAQASgBqDAAAAwBeAGwMAAADAF0AbQwAAAEATADqDAAABQBdAG4MAAADAEYAbwwAAAEAOwAcAAgJIBSWIgCWAQhoDAAAAQAzAGkMAAABADoAawwAAAEAOwBqDAAAAQA1AGwMAAABAD4AbQwAAAEAEwDqDAAAAQBEAG4MAAABACgAAAA=.',
Ma='Macca:BAAALgAECgUJBQABLgAECgYJCwACAAAAAA==.Maccazilla:BAAALgAECgYJCwAAAA==.Magdalena:BAACLgAFFH8RAAISAAQJcSQ5AwCtAQRoDAAABQBhAGkMAAAFAF8AawwAAAMAVwDqDAAABABcABIABAlxJDkDAK0BBGgMAAAFAGEAaQwAAAUAXwBrDAAAAwBXAOoMAAAEAFwALgAECn8lAAISAAkJAyW/AgBtAwASAAkJAyW/AgBtAwAAAA==.Magedand:BAAALgAECgMJAwAAAA==.Magnesson:BAAALgAFFAEJAgAAAA==.Manakaren:BAAALgADCggJDAAAAA==.Mazuro:BAACLgAFFH8YAAIMAAUJah3cEABHAQVoDAAABwBHAGkMAAAGADwAawwAAAQAVwBqDAAAAwA6AOoMAAAEAFEADAAFCWod3BAARwEFaAwAAAcARwBpDAAABgA8AGsMAAAEAFcAagwAAAMAOgDqDAAABABRAC4ABAp/LgADDAAJCbkd2QkAWgIADAAJCbkd2QkAWgIACwABCUYZWh0AQAAAAAA=.',
Me='Meatkleaver:BAABLgAECn8bAAMTAAkJ0BUhAwBnAgloDAAABABTAGkMAAAEAEAAawwAAAQATwBqDAAAAwAiAGwMAAADAC4AbQwAAAEAJQDqDAAABQBEAG4MAAACACgAbwwAAAEAGgATAAkJ0BUhAwBnAgloDAAABABTAGkMAAADAEAAawwAAAQATwBqDAAAAwAiAGwMAAADAC4AbQwAAAEAJQDqDAAABQBEAG4MAAACACgAbwwAAAEAGgAFAAEJqAGXNgEiAAFpDAAAAQAEAAAA.Meau:BAABLgAECn8jAAIdAAkJmR6RAwCiAgloDAAABgBYAGkMAAAGAFIAawwAAAUAWABqDAAABABYAGwMAAAEAFYAbQwAAAIAWQDqDAAABQBcAG4MAAACACIAbwwAAAEAPwAdAAkJmR6RAwCiAgloDAAABgBYAGkMAAAGAFIAawwAAAUAWABqDAAABABYAGwMAAAEAFYAbQwAAAIAWQDqDAAABQBcAG4MAAACACIAbwwAAAEAPwAAAA==.Mechadar:BAAALgAECgMJAwAAAA==.Mechanizedtv:BAACLgAFFH8JAAIHAAMJnx8JBwAeAQNoDAAABQBUAGkMAAACAEUA6gwAAAIAWAAHAAMJnx8JBwAeAQNoDAAABQBUAGkMAAACAEUA6gwAAAIAWAAuAAQKf8wABAcACQmyJh4AAIoDAAcACQmyJh4AAIoDAB0ABgl4HGENAJsBAAEAAQlmAqWDABwAAAAA.',
Mi='Mitskí:BAAALgAECgQJBAAAAA==.',
Mo='Monkerooz:BAAALgAECgUJCAAAAA==.Moodeng:BAAALgADCgYJBwAAAA==.Morphîne:BAACLgAFFH8IAAIOAAIJvBN+PwCHAAJoDAAAAwA4AOoMAAAFACwADgACCbwTfj8AhwACaAwAAAMAOADqDAAABQAsAC4ABAp/FwACDgAHCRke8SgAEAIADgAHCRke8SgAEAIAAAA=.',
Mu='Mugwump:BAAALgAECgUJBQAAAA==.Murdøk:BAABLgAECn8VAAMFAAYJKBdMlwBRAQZoDAAABABNAGkMAAAFAEwAawwAAAUAJABqDAAAAQA4AGwMAAACADQA6gwAAAQANAAFAAYJKBdMlwBRAQZoDAAABABNAGkMAAAEAEwAawwAAAUAJABqDAAAAQA4AGwMAAACADQA6gwAAAQANAAGAAEJ6Q04RAA4AAFpDAAAAQAjAAAA.',
My='Mythic:BAABLgAECn8mAAISAAgJ6RoVEAAbAghoDAAABgBTAGkMAAAGAEwAawwAAAUAQwBqDAAABABSAGwMAAAFAFMAbQwAAAMANwDqDAAABgBMAG4MAAADACUAEgAICekaFRAAGwIIaAwAAAYAUwBpDAAABgBMAGsMAAAFAEMAagwAAAQAUgBsDAAABQBTAG0MAAADADcA6gwAAAYATABuDAAAAwAlAAAA.',
['Mû']='Mûrdok:BAAALgAECgUJDAABLgAECgYJFQAFACgXAA==.',
['Mü']='Mürdok:BAAALgAECgYJCAABLgAECgYJFQAFACgXAA==.',
Ne='Necromortas:BAAALgAECgcJBwAAAA==.Nefarius:BAAALgAECggJEwAAAA==.Neph:BAABLgAECn8aAAMeAAkJQw96HwDlAQloDAAABAARAGkMAAAEADwAawwAAAQASwBqDAAAAwAsAGwMAAADADwAbQwAAAEAEQDqDAAABAATAG4MAAACADIAbwwAAAEABAAeAAkJQw96HwDlAQloDAAAAwARAGkMAAAEADwAawwAAAQASwBqDAAAAwAsAGwMAAADADwAbQwAAAEAEQDqDAAAAwATAG4MAAACADIAbwwAAAEABAAUAAIJbgNeUABNAAJoDAAAAQAEAOoMAAABAA0AAAA=.Nezot:BAAALgADCgkJEAAAAA==.',
Ni='Nihilism:BAAALgADCgYJBgAAAA==.Ninsu:BAAALgAECgYJCgAAAA==.Nishale:BAAALgAECgMJBQAAAA==.',
No='Noir:BAAALgADCgQJBAAAAA==.',
Nu='Nutdraggin:BAAALgADCgcJBwAAAA==.',
Ny='Nyki:BAAALgAECgcJDQAAAA==.',
On='Onlyfist:BAAALgAECgEJAgAAAA==.',
Op='Opius:BAAALgAECggJEAAAAA==.',
Or='Orcmagic:BAAALgADCgUJBwAAAA==.',
Os='Oshift:BAAALgAECgYJBgAAAA==.',
Pa='Pandinha:BAACLgAFFH8VAAIFAAQJ8B2lNgBRAQRoDAAABwBTAGkMAAAFAEUAawwAAAIARwDqDAAABwBRAAUABAnwHaU2AFEBBGgMAAAHAFMAaQwAAAUARQBrDAAAAgBHAOoMAAAHAFEALgAECn82AAIFAAkJNSEsDAA5AwAFAAkJNSEsDAA5AwAAAA==.Paolinelli:BAAALgAECgYJCgABLgAFFAUJEgAWALUkAA==.Pattêrn:BAAALgAECgYJCAAAAA==.',
Pd='Pdr:BAAALgADCgcJBwAAAA==.',
Pe='Pedri:BAABLgAFFH8KAAMFAAMJQhn+WAASAQNoDAAABABaAGkMAAABAAQA6gwAAAUAYgAFAAMJQhn+WAASAQNoDAAAAwBaAGkMAAABAAQA6gwAAAUAYgATAAEJlw9rEwBQAAFoDAAAAQAnAAAA.Pedrok:BAAALgAECgQJBwAAAA==.',
Ph='Phoenixashes:BAAALgADCgIJAgAAAA==.',
Pi='Picklestein:BAAALgADCgcJBwAAAA==.',
Po='Pokz:BAAALgADCgEJAQAAAA==.',
Pr='Priestiality:BAAALgAECgIJAwAAAA==.Prowl:BAAALgAECgEJAQABLgAFFAYJFAAfALgYAA==.Prscilla:BAAALgADCgcJBgAAAA==.',
Qu='Quixote:BAAALgAECgUJBQAAAA==.',
Ra='Radagast:BAAALgADCgcJDQABLgAFFAMJCAAJAMIFAA==.Radulf:BAAALgAECgQJBAAAAA==.Raph:BAACLgAFFH8TAAIFAAUJAh1kNQBTAQVoDAAABgBcAGkMAAAEAEMAawwAAAIALQBqDAAAAQANAOoMAAAGAFsABQAFCQIdZDUAUwEFaAwAAAYAXABpDAAABABDAGsMAAACAC0AagwAAAEADQDqDAAABgBbAC4ABAp/KgACBQAICeEfLSoALQIABQAICeEfLSoALQIAAAA=.Raphy:BAAALgAFFAMJAwABLgAFFAUJEwAFAAIdAA==.Ravyn:BAAALgADCgUJBQAAAA==.',
Re='Reckon:BAAALgAECgYJDAAAAA==.Redthedeer:BAAALgAECgcJCgAAAA==.Redzone:BAAALgAECgQJBgAAAA==.Refuliya:BAAALgADCgkJBwAAAA==.Remmahcm:BAABLgAECn8VAAIIAAgJUBYvPwApAghoDAAABABTAGkMAAAEADsAawwAAAMAUgBqDAAAAwAyAGwMAAADAE0A6gwAAAIAPABuDAAAAQAOAG8MAAABABYACAAICVAWLz8AKQIIaAwAAAQAUwBpDAAABAA7AGsMAAADAFIAagwAAAMAMgBsDAAAAwBNAOoMAAACADwAbgwAAAEADgBvDAAAAQAWAAAA.Renewing:BAAALgADCgQJBAAAAA==.Renrir:BAAALgADCgcJCAAAAA==.',
Rh='Rhark:BAAALgAECgUJDQAAAA==.',
Ri='Rikku:BAAALgAFFAIJAwAAAA==.',
Ro='Rook:BAABLgAECn8rAAIIAAkJICJpBwATAwloDAAABQBgAGkMAAAGAFoAawwAAAUAYABqDAAABQBSAGwMAAAGAFwAbQwAAAQAVwDqDAAABgBhAG4MAAAEAFkAbwwAAAIAMQAIAAkJICJpBwATAwloDAAABQBgAGkMAAAGAFoAawwAAAUAYABqDAAABQBSAGwMAAAGAFwAbQwAAAQAVwDqDAAABgBhAG4MAAAEAFkAbwwAAAIAMQAAAA==.',
Ru='Runnow:BAAALgADCgYJCwAAAA==.',
Sa='Sagas:BAAALgAECgEJAQAAAA==.Salina:BAAALgAECgEJAQABLgAECgMJBQACAAAAAA==.Sammysam:BAAALgADCgUJBwAAAA==.Sathor:BAAALgADCgkJDgAAAA==.',
Sc='Scotch:BAAALgADCgQJBAABLgAFFAQJCQASADMKAA==.',
Sh='Shelton:BAAALgADCgMJAwABLgADCggJDQACAAAAAA==.Shinjey:BAAALgAECgMJBwAAAA==.Shocker:BAAALgAECgEJAQAAAA==.',
Si='Sil:BAABLgAECn8ZAAIgAAkJCwr1FwCXAQloDAAABAAuAGkMAAAEAD0AawwAAAQAIwBqDAAAAwAVAGwMAAADAAgAbQwAAAEACwDqDAAAAwAbAG4MAAACAAoAbwwAAAEABAAgAAkJCwr1FwCXAQloDAAABAAuAGkMAAAEAD0AawwAAAQAIwBqDAAAAwAVAGwMAAADAAgAbQwAAAEACwDqDAAAAwAbAG4MAAACAAoAbwwAAAEABAAAAA==.Silents:BAAALgAECgUJBQAAAA==.Siphon:BAAALgAECgYJDAAAAA==.Siphons:BAAALgAECgMJBAAAAA==.',
Sk='Ska:BAACLgAFFH8bAAINAAcJvRbMBwABAgdoDAAABgBGAGkMAAAGAEkAawwAAAQASQBqDAAAAwAjAGwMAAABABYAbQwAAAEAGADqDAAABgBUAA0ABwm9FswHAAECB2gMAAAGAEYAaQwAAAYASQBrDAAABABJAGoMAAADACMAbAwAAAEAFgBtDAAAAQAYAOoMAAAGAFQALgAECn8bAAMNAAgJux9aGADCAgANAAgJux9aGADCAgAhAAEJAACTcAA1AAAAAA==.',
Sl='Slyzete:BAAALgAECgQJBwAAAA==.',
So='Softbutt:BAAALgAECggJDwAAAA==.Sophiae:BAAALgAECgIJAgAAAA==.Sophie:BAAALgADCgcJBwAAAA==.Soulseeker:BAABLgAECn8fAAMNAAcJsRQzWgBvAQdoDAAABQA8AGkMAAAHADkAawwAAAMANwBqDAAABABNAGwMAAADACQA6gwAAAcAOQBuDAAAAgAyAA0ABwljFDNaAG8BB2gMAAAFADwAaQwAAAQAOQBrDAAAAQAyAGoMAAAEAE0AbAwAAAMAJADqDAAABwA5AG4MAAACADIAIQACCXwUaFAAfQACaQwAAAMAMQBrDAAAAgA3AAAA.',
St='Stölen:BAAALgAECgEJAQAAAA==.',
Sy='Sylthas:BAAALgADCgMJAwAAAA==.Syrensong:BAAALgAECgQJBAAAAA==.',
Ta='Tankli:BAAALgAECgIJBgAAAA==.Tanriel:BAAALgAECgEJAQAAAA==.Tatl:BAAALgADCgkJEQAAAA==.',
Te='Tertletoes:BAABLgAECn8cAAQiAAkJECXvAAC+AwloDAAABgBjAGkMAAAEAGEAawwAAAQAYABqDAAAAwBfAGwMAAACAGIAbQwAAAEAYgDqDAAABQBgAG4MAAACAFEAbwwAAAEAWwAiAAkJECXvAAC+AwloDAAABABjAGkMAAAEAGEAawwAAAQAYABqDAAAAwBfAGwMAAACAGIAbQwAAAEAYgDqDAAABABgAG4MAAACAFEAbwwAAAEAWwAKAAEJ2x46JwBMAAHqDAAAAQBOAAkAAQn+HdzaADkAAWgMAAACAEwAAAA=.Terts:BAAALgAECgEJAQABLgAECgkJHAAiABAlAA==.Teto:BAAALgAECgYJDgAAAA==.',
Th='Thanaz:BAAALgAECgIJAgAAAA==.Thebartender:BAAALgAECgcJDAAAAA==.Thella:BAAALgAECgQJBgAAAA==.Thopowisiwi:BAAALgAFFAIJAwAAAA==.',
To='Tog:BAABLgAECn8bAAIOAAkJciLGAwBVAwloDAAABABZAGkMAAAEAF4AawwAAAQAXABqDAAAAwBdAGwMAAADAGAAbQwAAAEATADqDAAABQBgAG4MAAACAFUAbwwAAAEAQwAOAAkJciLGAwBVAwloDAAABABZAGkMAAAEAF4AawwAAAQAXABqDAAAAwBdAGwMAAADAGAAbQwAAAEATADqDAAABQBgAG4MAAACAFUAbwwAAAEAQwAAAA==.Togame:BAAALgAECgUJCAAAAA==.Toggie:BAAALgADCgkJDAAAAA==.Tognahok:BAAALgADCgYJDgAAAA==.Togy:BAAALgADCgEJAQAAAA==.Tortoisetoes:BAAALgAECgIJAgABLgAECgkJHAAiABAlAA==.',
Tr='Tremboladin:BAABLgAECn8aAAIVAAcJHxo1JgD2AQdoDAAABAA7AGkMAAAEAD0AawwAAAQAQQBqDAAABABhAGwMAAAEAE0AbQwAAAIANADqDAAABAA3ABUABwkfGjUmAPYBB2gMAAAEADsAaQwAAAQAPQBrDAAABABBAGoMAAAEAGEAbAwAAAQATQBtDAAAAgA0AOoMAAAEADcAAS4ABRQECRIAGQB7DwA=.',
Ts='Tsnt:BAAALgAECgEJAQAAAA==.',
Tu='Turbosocks:BAAALgAECgIJBQAAAA==.Turok:BAAALgADCgMJAwAAAA==.Turtles:BAAALgADCgEJAQABLgAECgkJHAAiABAlAA==.Tuskydin:BAAALgADCgcJCQAAAA==.',
Ty='Tydrin:BAAALgAECgIJAwAAAA==.Tylandord:BAAALgADCgEJAQAAAA==.',
['Tý']='Týråél:BAAALgADCgYJCwAAAA==.',
Ur='Urra:BAABLgAECn8rAAIcAAgJEh5uFgD5AQhoDAAACABWAGkMAAAIAFMAawwAAAgAUABqDAAABgA8AGwMAAAFAEIAbQwAAAMATwDqDAAAAwA+AG4MAAACAE8AHAAICRIebhYA+QEIaAwAAAgAVgBpDAAACABTAGsMAAAIAFAAagwAAAYAPABsDAAABQBCAG0MAAADAE8A6gwAAAMAPgBuDAAAAgBPAAAA.',
Va='Vai:BAAALgAECgMJBAAAAA==.Valoo:BAAALgAECgQJCgAAAA==.Valunar:BAAALgADCgUJBQAAAA==.',
Ve='Veyron:BAAALgADCgMJAwAAAA==.',
Vi='Vicar:BAAALgAECgMJAwAAAA==.',
Vo='Voidstrider:BAAALgAECggJEAAAAA==.',
We='Weezard:BAABLgAECn8lAAIDAAgJ/hGWVwCuAQhoDAAACAA6AGkMAAAGAEMAawwAAAYALQBqDAAAAwAdAGwMAAADACgAbQwAAAIAEADqDAAABQAwAG4MAAAEAC4AAwAICf4RllcArgEIaAwAAAgAOgBpDAAABgBDAGsMAAAGAC0AagwAAAMAHQBsDAAAAwAoAG0MAAACABAA6gwAAAUAMABuDAAABAAuAAAA.',
Wh='Wheein:BAABLgAECn8jAAIUAAkJ1yHqBAATAwloDAAABgBhAGkMAAAGAGEAawwAAAUAXQBqDAAABABhAGwMAAAEAFwAbQwAAAIAQgDqDAAABQBaAG4MAAACAEcAbwwAAAEARwAUAAkJ1yHqBAATAwloDAAABgBhAGkMAAAGAGEAawwAAAUAXQBqDAAABABhAGwMAAAEAFwAbQwAAAIAQgDqDAAABQBaAG4MAAACAEcAbwwAAAEARwAAAA==.',
Wi='Wingolingo:BAAALgAECgIJAgAAAA==.',
Xe='Xeren:BAAALgADCgEJAQAAAA==.',
Ya='Yaamoonn:BAAALgADCgUJBQAAAA==.',
Ye='Yenn:BAABLgAECn8bAAMNAAkJXhtHFgDPAgloDAAABABaAGkMAAAEAFoAawwAAAQAOABqDAAAAwBAAGwMAAADAFoAbQwAAAEAOgDqDAAABQBOAG4MAAACADkAbwwAAAEAJQANAAkJXhtHFgDPAgloDAAABABaAGkMAAAEAFoAawwAAAQAOABqDAAAAgA/AGwMAAACAFoAbQwAAAEAOgDqDAAABQBOAG4MAAACADkAbwwAAAEAJQAhAAIJwAEuWgBgAAJqDAAAAQBAAGwMAAABAAQAAAA=.',
Za='Zardnax:BAAALgADCgIJBAAAAA==.',
Ze='Zenin:BAAALgADCggJFQAAAA==.Zenu:BAACLgAFFH8IAAMjAAMJohG7BwDpAANoDAAAAwAkAGkMAAADADgA6gwAAAIAKgAjAAMJqg67BwDpAANoDAAAAQAjAGkMAAABADgA6gwAAAEAFQAcAAMJyAyNJADPAANoDAAAAgAkAGkMAAACABMA6gwAAAEAKgAuAAQKfyQAAxwACQnrGhYSAJICABwACQnrGhYSAJICACMABAk1FuccALcAAAAA.',
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
