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

local lookup = {'Druid-Balance','Unknown-Unknown','Mage-Frost','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Blood','Druid-Guardian','Paladin-Retribution','DemonHunter-Devourer','DemonHunter-Vengeance','Rogue-Assassination','Rogue-Subtlety','Warlock-Demonology','Druid-Restoration','Warrior-Fury','Monk-Brewmaster','Evoker-Preservation','Monk-Windwalker','DeathKnight-Frost','Priest-Discipline','Paladin-Holy','Rogue-Outlaw','Hunter-BeastMastery','Hunter-Marksmanship','Evoker-Augmentation','Evoker-Devastation','Shaman-Restoration','Druid-Feral','Priest-Holy','Warrior-Arms','Warrior-Protection','Warlock-Destruction','DemonHunter-Havoc','Shaman-Elemental','Shaman-Enhancement',}
local provider = {region='US',realm='Warsong',name='US',type='daily',zone=46,date='2026-05-10',data={Ad='Adònis:BAAALgADCgEJAQAAAA==.',
Ae='Aesudan:BAAALgADCgEJAQAAAA==.',
Ah='Aharan:BAABLgAECn8aAAIBAAYJ4glELgDnAAZoDAAABQAjAGkMAAAFAB8AawwAAAUAEgBqDAAABAATAGwMAAADAAsA6gwAAAQAHQABAAYJ4glELgDnAAZoDAAABQAjAGkMAAAFAB8AawwAAAUAEgBqDAAABAATAGwMAAADAAsA6gwAAAQAHQAAAA==.',
Ai='Aiona:BAAALgADCgYJDAAAAA==.',
Al='Alandrov:BAAALgADCgEJAQAAAA==.Alexanzalone:BAAALgADCggJCAAAAA==.Allenduin:BAAALgAECgEJAQAAAA==.Alodso:BAAALgADCgEJAQAAAA==.',
An='Angryballz:BAAALgAECgYJBwABLgAECgYJCwACAAAAAA==.Angz:BAAALgAECgUJDQAAAA==.Anielor:BAAALgADCgMJAwAAAA==.Anuksuna:BAAALgAECgUJCQABLgAECgYJEwACAAAAAA==.',
Ar='Arcadia:BAAALgAECgYJDgAAAA==.Arcane:BAABLgAECn8eAAMDAAgJCCReEABGAwhoDAAABQBcAGkMAAAEAGIAawwAAAQAYABqDAAABABfAGwMAAAEAGAAbQwAAAMAWQDqDAAABABfAG4MAAACAEsAAwAICQgkXhAARgMIaAwAAAQAXABpDAAAAwBiAGsMAAADAGAAagwAAAIAXwBsDAAAAgBgAG0MAAADAFkA6gwAAAQAXwBuDAAAAgBLAAQABQlDJBcFAOkBBWgMAAABAFoAaQwAAAEAXgBrDAAAAQBeAGoMAAACAFoAbAwAAAIAWwAAAA==.',
As='Asta:BAAALgAECgQJBAAAAA==.',
At='Atulan:BAAALgADCgQJBAAAAA==.',
Au='Austin:BAAALgADCggJEAAAAA==.Automobeer:BAAALgAECgEJAwAAAA==.',
Aw='Awake:BAABLgAECn8aAAMFAAcJZBRASwBlAQdoDAAABAA4AGkMAAAEAEcAawwAAAQANABqDAAABAA0AGwMAAADACQAbQwAAAMAOADqDAAABAAoAAUABwk6D0BLAGUBB2gMAAACABwAaQwAAAIARwBrDAAAAgA0AGoMAAACACoAbAwAAAEABwBtDAAAAwA4AOoMAAACABEABgAGCdoSVB8ASgEGaAwAAAIAOABpDAAAAgA6AGsMAAACADEAagwAAAIANABsDAAAAgAkAOoMAAACACgAAAA=.',
Az='Azazzel:BAAALgADCgEJAQAAAA==.',
Ba='Bambietta:BAAALgADCgkJCQAAAA==.Barebelly:BAAALgAECggJEAAAAA==.',
Be='Bearforce:BAABLgAECn8eAAIHAAkJjxnZCAAbAgloDAAAAgBUAGkMAAACADEAawwAAAIASgBqDAAABQA/AGwMAAAFAFoAbQwAAAMAQwDqDAAABgBQAG4MAAAEABoAbwwAAAEAMgAHAAkJjxnZCAAbAgloDAAAAgBUAGkMAAACADEAawwAAAIASgBqDAAABQA/AGwMAAAFAFoAbQwAAAMAQwDqDAAABgBQAG4MAAAEABoAbwwAAAEAMgAAAA==.',
Bi='Biggbird:BAABLgAECn8WAAIBAAYJNhm2GgBuAQZoDAAABQAxAGkMAAADAEAAawwAAAQARwBqDAAAAwA4AGwMAAADAEAA6gwAAAQASAABAAYJNhm2GgBuAQZoDAAABQAxAGkMAAADAEAAawwAAAQARwBqDAAAAwA4AGwMAAADAEAA6gwAAAQASAAAAA==.',
Bl='Blutwin:BAABLgAECn8eAAIIAAgJXhD0OQCiAQhoDAAABQAXAGkMAAAFACMAawwAAAQAIgBqDAAABAAzAGwMAAAFAEkAbQwAAAEAGwDqDAAABAAzAG4MAAACAC8ACAAICV4Q9DkAogEIaAwAAAUAFwBpDAAABQAjAGsMAAAEACIAagwAAAQAMwBsDAAABQBJAG0MAAABABsA6gwAAAQAMwBuDAAAAgAvAAAA.Bluud:BAAALgADCgMJAwAAAA==.',
Bo='Bossdierr:BAACLgAFFH8MAAIJAAMJFyM3IAAzAQNoDAAABQBiAGkMAAABAE4A6gwAAAYAXAAJAAMJFyM3IAAzAQNoDAAABQBiAGkMAAABAE4A6gwAAAYAXAAuAAQKfyoAAwkACAkPIucXAAcCAAkACAlcIecXAAcCAAoACAlCE2sIAGYBAAAA.Bossdisan:BAACLgAFFH8HAAIDAAMJ6h45KgAMAQNoDAAAAwBcAGkMAAACAFYA6gwAAAIAOgADAAMJ6h45KgAMAQNoDAAAAwBcAGkMAAACAFYA6gwAAAIAOgAuAAQKfyEAAgMABgkXI1VXADMCAAMABgkXI1VXADMCAAAA.Bosswudi:BAABLgAFFH8HAAMLAAIJMRN0BgCpAAJoDAAAAwA+AOoMAAAEACQACwACCbEOdAYAqQACaAwAAAEAPgDqDAAAAQANAAwAAgnKCLEVAKAAAmgMAAACAAgA6gwAAAMAJAAAAA==.',
Br='Brashe:BAAALgAECgUJEgAAAA==.Breakahorde:BAAALgAECgEJAQAAAA==.Breathe:BAAALgAECgQJBAAAAA==.Brickbeard:BAAALgAECgYJBgABLgAECgcJEQACAAAAAA==.Bruv:BAABLgAECn8jAAINAAYJhhW+VQAwAQZoDAAABwBHAGkMAAAGADgAawwAAAYAKwBqDAAABQBUAGwMAAAEACQA6gwAAAcARAANAAYJhhW+VQAwAQZoDAAABwBHAGkMAAAGADgAawwAAAYAKwBqDAAABQBUAGwMAAAEACQA6gwAAAcARAAAAA==.',
Ca='Calathis:BAAALgAECgEJAQAAAA==.Cazadòr:BAAALgAECgIJAgAAAA==.',
Ch='Chromiepip:BAAALgADCgMJAwAAAA==.',
Co='Corbann:BAAALgAECgYJCgAAAA==.',
Cr='Creamcheese:BAABLgAECn8aAAIOAAcJUB2hHQDjAQdoDAAABABSAGkMAAAEAFQAawwAAAQATgBqDAAAAwBSAGwMAAAEAFMAbQwAAAIAFgDqDAAABQBcAA4ABwlQHaEdAOMBB2gMAAAEAFIAaQwAAAQAVABrDAAABABOAGoMAAADAFIAbAwAAAQAUwBtDAAAAgAWAOoMAAAFAFwAAAA=.Creamy:BAABLgAECn8jAAIPAAgJxRhBDwAFAghoDAAABgBfAGkMAAAGADwAawwAAAYAQQBqDAAABQBAAGwMAAAFAFEAbQwAAAEAOADqDAAABQBLAG4MAAABAAkADwAICcUYQQ8ABQIIaAwAAAYAXwBpDAAABgA8AGsMAAAGAEEAagwAAAUAQABsDAAABQBRAG0MAAABADgA6gwAAAUASwBuDAAAAQAJAAAA.Crossbreed:BAAALgAECgQJBQAAAA==.',
Cy='Cyr:BAAALgADCgUJBQAAAA==.Cytosine:BAAALgAECgYJCQAAAA==.',
Da='Daddyhaz:BAABLgAECn8yAAIJAAgJ2iOHBQDcAghoDAAACgBcAGkMAAAHAGAAawwAAAkAVABqDAAACABhAGwMAAAFAGMAbQwAAAIAVwDqDAAABwBfAG4MAAACAFcACQAICdojhwUA3AIIaAwAAAoAXABpDAAABwBgAGsMAAAJAFQAagwAAAgAYQBsDAAABQBjAG0MAAACAFcA6gwAAAcAXwBuDAAAAgBXAAAA.Daddywhyudie:BAAALgADCgEJAQAAAA==.Daelyte:BAAALgAECgYJDwAAAA==.Daghor:BAABLgAFFH8GAAIMAAIJLBpkGgCuAAJoDAAAAwBUAOoMAAADADEADAACCSwaZBoArgACaAwAAAMAVADqDAAAAwAxAAAA.',
De='Deltron:BAAALgAECgEJAQAAAA==.Desetre:BAAALgADCgIJAgAAAA==.',
Di='Dinks:BAABLgAECn8oAAIDAAgJvRcrNgDQAQhoDAAABgBTAGkMAAAGAD0AawwAAAYAQQBqDAAABAA4AGwMAAAGADMAbQwAAAMANADqDAAABgBLAG4MAAADACMAAwAICb0XKzYA0AEIaAwAAAYAUwBpDAAABgA9AGsMAAAGAEEAagwAAAQAOABsDAAABgAzAG0MAAADADQA6gwAAAYASwBuDAAAAwAjAAAA.Ditzy:BAAALgAECgEJAQAAAA==.',
Do='Docc:BAABLgAECn8XAAIMAAkJGA+oFgBXAgloDAAAAwA5AGkMAAADAD4AawwAAAMAOABqDAAAAwAmAGwMAAADADMAbQwAAAEABQDqDAAABAAmAG4MAAACAAgAbwwAAAEAHAAMAAkJGA+oFgBXAgloDAAAAwA5AGkMAAADAD4AawwAAAMAOABqDAAAAwAmAGwMAAADADMAbQwAAAEABQDqDAAABAAmAG4MAAACAAgAbwwAAAEAHAAAAA==.',
Dr='Draan:BAAALgADCgUJBwAAAA==.Dragorr:BAAALgADCgcJBwAAAA==.Dreadpanda:BAAALgADCgMJAwABLgAFFAQJCAAQALIiAA==.Drekkarn:BAAALgADCgMJBAAAAA==.Drood:BAAALgAECgEJAQAAAA==.',
El='Elzath:BAAALgADCggJEAABLgAECgkJIwARAIkUAA==.',
En='Enix:BAAALgADCgYJBgABLgAFFAIJBQAOALwTAA==.',
Er='Erdrick:BAAALgAECgEJAgAAAA==.',
Es='Espeon:BAAALgAECgYJDQAAAA==.',
Eu='Eudisius:BAAALgADCgEJAQAAAA==.',
Ev='Evara:BAABLgAECn8UAAIDAAYJAweNpwDPAAZoDAAABAAQAGkMAAAEABoAawwAAAQAGQBqDAAAAgALAGwMAAACAAcA6gwAAAQADAADAAYJAweNpwDPAAZoDAAABAAQAGkMAAAEABoAawwAAAQAGQBqDAAAAgALAGwMAAACAAcA6gwAAAQADAAAAA==.',
Fa='Fangbot:BAAALgAECgEJAQAAAA==.',
Fe='Felcaas:BAAALgADCgQJBAAAAA==.Felini:BAABLgAECn8bAAIPAAcJvQfQLgAaAQdoDAAABQAVAGkMAAAFABYAawwAAAQAFwBqDAAABAAVAGwMAAAEABAAbQwAAAEACQDqDAAABAAYAA8ABwm9B9AuABoBB2gMAAAFABUAaQwAAAUAFgBrDAAABAAXAGoMAAAEABUAbAwAAAQAEABtDAAAAQAJAOoMAAAEABgAAAA=.Feronar:BAABLgAECn8fAAIPAAgJegg9JQBOAQhoDAAABgAbAGkMAAAFABcAawwAAAUAFQBqDAAABAAnAGwMAAADACQAbQwAAAEADADqDAAABgAXAG4MAAABAAcADwAICXoIPSUATgEIaAwAAAYAGwBpDAAABQAXAGsMAAAFABUAagwAAAQAJwBsDAAAAwAkAG0MAAABAAwA6gwAAAYAFwBuDAAAAQAHAAAA.',
Fl='Fleepity:BAAALgAECgYJCQAAAA==.Floopity:BAAALgADCgYJBwAAAA==.Flowermom:BAAALgAECgEJAQAAAA==.Flume:BAAALgADCgcJBwAAAA==.',
Fu='Fusíon:BAEBLgAECn8zAAIJAAkJdiLrCQCRAgloDAAACABhAGkMAAAHAGMAawwAAAcAXQBqDAAABwBhAGwMAAAGAGEAbQwAAAMAUwDqDAAACQBaAG4MAAADAEQAbwwAAAEATAAJAAkJdiLrCQCRAgloDAAACABhAGkMAAAHAGMAawwAAAcAXQBqDAAABwBhAGwMAAAGAGEAbQwAAAMAUwDqDAAACQBaAG4MAAADAEQAbwwAAAEATAAAAA==.',
Gi='Gin:BAACLgAFFH8FAAISAAMJ0QosEwDPAANoDAAAAgAgAGkMAAABAA4A6gwAAAIAIwASAAMJ0QosEwDPAANoDAAAAgAgAGkMAAABAA4A6gwAAAIAIwAuAAQKfycAAhIACQn2GswIAD4CABIACQn2GswIAD4CAAAA.',
Gj='Gjana:BAAALgAECgQJBAABLgAECgQJDgACAAAAAA==.',
Gl='Glamdring:BAAALgADCgMJAwAAAA==.Glunty:BAAALgAECgUJCAAAAA==.',
Go='Goldpaw:BAAALgADCgEJAQAAAA==.Gorlash:BAAALgAECgYJBwAAAA==.',
Gr='Gridinn:BAAALgADCgIJAgAAAA==.Grimgeth:BAACLgAFFH8IAAIFAAMJcBQpUQD3AANoDAAAAwBVAGkMAAADAB8A6gwAAAIAKAAFAAMJcBQpUQD3AANoDAAAAwBVAGkMAAADAB8A6gwAAAIAKAAuAAQKfyYAAwUACAnQHB01ALEBAAUACAnQHB01ALEBABMAAgnlFzwWAEUAAAAA.Grimwrath:BAAALgAECgUJBwABLgAFFAMJCAAFAHAUAA==.',
Gu='Gugaman:BAAALgADCgcJDgAAAA==.Guishin:BAAALgAECgEJAQAAAA==.',
He='Healpls:BAAALgADCgUJBQAAAA==.Heidriel:BAAALgAECgMJAwAAAA==.Herumesu:BAAALgADCgcJCgABLgAFFAMJCgAFAEsgAA==.',
Ho='Holapes:BAAALgAECgUJCAABLgAECgMJBAACAAAAAA==.',
Hu='Huhbruh:BAAALgAECgIJAgABLgAECgYJIwANAIYVAA==.',
Hw='Hwasa:BAABLgAECn8iAAIQAAgJCR6nCABJAghoDAAABgBOAGkMAAAGAFsAawwAAAUAVwBqDAAABABWAGwMAAAEAFoAbQwAAAIARQDqDAAABQBTAG4MAAACACYAEAAICQkepwgASQIIaAwAAAYATgBpDAAABgBbAGsMAAAFAFcAagwAAAQAVgBsDAAABABaAG0MAAACAEUA6gwAAAUAUwBuDAAAAgAmAAAA.',
Il='Illigari:BAAALgAFFAEJAQAAAA==.',
In='Indy:BAAALgADCgUJCAAAAA==.Insanities:BAABLgAECn8uAAIUAAkJDSAzAgA9AwloDAAABwBZAGkMAAAGAFUAawwAAAYAXABqDAAABgBcAGwMAAAGAFYAbQwAAAMAVADqDAAABwBZAG4MAAADAFAAbwwAAAIAJgAUAAkJDSAzAgA9AwloDAAABwBZAGkMAAAGAFUAawwAAAYAXABqDAAABgBcAGwMAAAGAFYAbQwAAAMAVADqDAAABwBZAG4MAAADAFAAbwwAAAIAJgAAAA==.Inti:BAABLgAECn8WAAIVAAYJZhuAGwC4AQZoDAAAAwBZAGkMAAADADoAawwAAAQAQABqDAAABQBCAGwMAAADADUA6gwAAAQAWAAVAAYJZhuAGwC4AQZoDAAAAwBZAGkMAAADADoAawwAAAQAQABqDAAABQBCAGwMAAADADUA6gwAAAQAWAABLgAFFAIJBQAOALwTAA==.',
Ja='Jaidie:BAAALgAECgMJAwAAAA==.',
Je='Jeffreyx:BAAALgAECgYJCAAAAA==.Jeffreyz:BAAALgADCgYJBgAAAA==.',
Jo='Joak:BAAALgADCgUJBQAAAA==.Jota:BAAALgADCgcJCAAAAA==.',
Ka='Kahlán:BAAALgAECgYJEwAAAA==.Karlangas:BAAALgAECgMJBAAAAA==.',
Ki='Kifu:BAAALgADCgEJAQABLgAECgQJDgACAAAAAA==.Kikipants:BAAALgADCgEJAQAAAA==.Kitrix:BAAALgADCgUJBQAAAA==.Kitty:BAAALgADCgIJAgABLgAFFAMJBwAHAIEIAA==.',
Kr='Krue:BAAALgADCggJDQAAAA==.',
Ku='Kubimage:BAABLgAECn8aAAIDAAkJKhu2MgCoAgloDAAABABcAGkMAAAEAFUAawwAAAQATwBqDAAAAwATAGwMAAADAEMAbQwAAAEATwDqDAAABABTAG4MAAACAB0AbwwAAAEAJgADAAkJKhu2MgCoAgloDAAABABcAGkMAAAEAFUAawwAAAQATwBqDAAAAwATAGwMAAADAEMAbQwAAAEATwDqDAAABABTAG4MAAACAB0AbwwAAAEAJgAAAA==.',
La='Lane:BAAALgADCgEJAQAAAA==.Layona:BAAALgAECgYJCgAAAA==.',
Le='Lerroy:BAAALgADCgcJCQAAAA==.',
Li='Lildar:BAABLgAECn8eAAIFAAgJjxp2IQALAghoDAAABQBNAGkMAAAFAE8AawwAAAUASgBqDAAABABHAGwMAAAEAD8AbQwAAAEALgDqDAAABQBXAG4MAAABAC8ABQAICY8adiEACwIIaAwAAAUATQBpDAAABQBPAGsMAAAFAEoAagwAAAQARwBsDAAABAA/AG0MAAABAC4A6gwAAAUAVwBuDAAAAQAvAAAA.Linelli:BAAALgAECgcJCgABLgAFFAUJEQAWALUkAA==.Lirra:BAAALgAFFAIJAwABLgAFFAIJBQAOALwTAA==.',
Lo='Lorthiel:BAAALgADCgIJAgAAAA==.Lothus:BAABLgAECn8VAAMXAAkJDxswGAB4AgloDAAAAgA7AGkMAAADAFgAawwAAAMARgBqDAAAAQBXAGwMAAABAD4AbQwAAAEAKwDqDAAABABVAG4MAAAFAFEAbwwAAAEAPgAXAAkJDxswGAB4AgloDAAAAQA7AGkMAAADAFgAawwAAAMARgBqDAAAAQBXAGwMAAABAD4AbQwAAAEAKwDqDAAABABVAG4MAAAFAFEAbwwAAAEAPgAYAAEJdgRlkwAnAAFoDAAAAQALAAEuAAUUAgkFAA4AvBMA.',
Ls='Lsblkxd:BAAALgADCgYJBgAAAA==.',
Lu='Lumen:BAAALgADCgcJCAAAAA==.Lumverjvcked:BAAALgAECgYJDAABLgAECgYJIwANAIYVAA==.',
Lx='Lxrbread:BAACLgAFFH8LAAMZAAMJqQuoJADeAANoDAAABgASAGkMAAACACAA6gwAAAMAJgAZAAMJqQuoJADeAANoDAAABAASAGkMAAACACAA6gwAAAMAJgARAAEJ5QPWGAA8AAFoDAAAAgAJAC4ABAp/MQAEGQAICVIWShQArwEAGQAICSwWShQArwEAEQAFCUEF0zcArQAAGgACCagKuRcAOgAAAAA=.',
['Lë']='Lëgitz:BAABLgAECn8dAAIbAAkJuh+SAwAbAwloDAAABQBTAGkMAAAEAFQAawwAAAQASgBqDAAAAwBeAGwMAAADAF0AbQwAAAEATADqDAAABQBdAG4MAAADAEYAbwwAAAEAOwAbAAkJuh+SAwAbAwloDAAABQBTAGkMAAAEAFQAawwAAAQASgBqDAAAAwBeAGwMAAADAF0AbQwAAAEATADqDAAABQBdAG4MAAADAEYAbwwAAAEAOwAAAA==.',
Ma='Maccazilla:BAAALgAECgYJCwAAAA==.Magdalena:BAACLgAFFH8JAAISAAQJhB8JBAB7AQRoDAAAAwBhAGkMAAADAEEAawwAAAEAVADqDAAAAgBLABIABAmEHwkEAHsBBGgMAAADAGEAaQwAAAMAQQBrDAAAAQBUAOoMAAACAEsALgAECn8jAAISAAgJGyW/AgBtAwASAAgJGyW/AgBtAwAAAA==.Magedand:BAAALgAECgMJAwAAAA==.Magnesson:BAAALgAFFAEJAgAAAA==.Manakaren:BAAALgADCggJDAAAAA==.Mazuro:BAACLgAFFH8PAAIMAAUJah1bCQBoAQVoDAAABQBHAGkMAAAEADwAawwAAAIAVwBqDAAAAQA6AOoMAAADAFEADAAFCWodWwkAaAEFaAwAAAUARwBpDAAABAA8AGsMAAACAFcAagwAAAEAOgDqDAAAAwBRAC4ABAp/JwADDAAHCV8fSAsA8gEADAAHCV8fSAsA8gEACwABCUYZWB0AQAAAAAA=.',
Me='Meatkleaver:BAABLgAECn8bAAMTAAkJ0BUhAwBnAgloDAAABABTAGkMAAAEAEAAawwAAAQATwBqDAAAAwAiAGwMAAADAC4AbQwAAAEAJQDqDAAABQBEAG4MAAACACgAbwwAAAEAGgATAAkJ0BUhAwBnAgloDAAABABTAGkMAAADAEAAawwAAAQATwBqDAAAAwAiAGwMAAADAC4AbQwAAAEAJQDqDAAABQBEAG4MAAACACgAbwwAAAEAGgAFAAEJqAGXNgEiAAFpDAAAAQAEAAAA.Meau:BAABLgAECn8iAAIcAAgJax/5AgByAghoDAAABgBYAGkMAAAGAFIAawwAAAUAWABqDAAABABYAGwMAAAEAFYAbQwAAAIAWQDqDAAABQBcAG4MAAACACIAHAAICWsf+QIAcgIIaAwAAAYAWABpDAAABgBSAGsMAAAFAFgAagwAAAQAWABsDAAABABWAG0MAAACAFkA6gwAAAUAXABuDAAAAgAiAAAA.Mechadar:BAAALgAECgMJAwAAAA==.Mechanizedtv:BAACLgAFFH8GAAIHAAMJUxvSBAD/AANoDAAABABEAGkMAAABAD4A6gwAAAEATgAHAAMJUxvSBAD/AANoDAAABABEAGkMAAABAD4A6gwAAAEATgAuAAQKf8MABAcACQmyJhAAAI0DAAcACQmyJhAAAI0DABwABgl4HIMIALIBAAEAAQlmAgxpAB4AAAAA.',
Mi='Mitskí:BAAALgAECgQJBAAAAA==.',
Mo='Monkerooz:BAAALgAECgUJCAAAAA==.Moodeng:BAAALgADCgYJBwAAAA==.Morphîne:BAACLgAFFH8FAAIOAAIJvBMfMwCGAAJoDAAAAgA4AOoMAAADACwADgACCbwTHzMAhgACaAwAAAIAOADqDAAAAwAsAC4ABAp/FwACDgAHCRke7CgAEAIADgAHCRke7CgAEAIAAAA=.',
Mu='Mugwump:BAAALgADCgYJCAAAAA==.Murdøk:BAABLgAECn8VAAMFAAYJKBdIlwBRAQZoDAAABABNAGkMAAAFAEwAawwAAAUAJABqDAAAAQA4AGwMAAACADQA6gwAAAQANAAFAAYJKBdIlwBRAQZoDAAABABNAGkMAAAEAEwAawwAAAUAJABqDAAAAQA4AGwMAAACADQA6gwAAAQANAAGAAEJ6Q02RAA4AAFpDAAAAQAjAAAA.',
My='Mythic:BAABLgAECn8eAAISAAgJMBo3DQDwAQhoDAAABQBTAGkMAAAFAEwAawwAAAQAQwBqDAAAAwBQAGwMAAAEAE0AbQwAAAIANgDqDAAABQBMAG4MAAACAB8AEgAICTAaNw0A8AEIaAwAAAUAUwBpDAAABQBMAGsMAAAEAEMAagwAAAMAUABsDAAABABNAG0MAAACADYA6gwAAAUATABuDAAAAgAfAAAA.',
['Mû']='Mûrdok:BAAALgAECgUJDAABLgAECgYJFQAFACgXAA==.',
['Mü']='Mürdok:BAAALgAECgYJCAABLgAECgYJFQAFACgXAA==.',
Ne='Necromortas:BAAALgAECgcJBwAAAA==.Nefarius:BAAALgAECggJEwAAAA==.Neph:BAABLgAECn8aAAMdAAkJQw95HwDlAQloDAAABAARAGkMAAAEADwAawwAAAQASwBqDAAAAwAsAGwMAAADADwAbQwAAAEAEQDqDAAABAATAG4MAAACADIAbwwAAAEABAAdAAkJQw95HwDlAQloDAAAAwARAGkMAAAEADwAawwAAAQASwBqDAAAAwAsAGwMAAADADwAbQwAAAEAEQDqDAAAAwATAG4MAAACADIAbwwAAAEABAAUAAIJbgNcUABNAAJoDAAAAQAEAOoMAAABAA0AAAA=.',
Ni='Nihilism:BAAALgADCgYJBgAAAA==.Ninsu:BAAALgAECgYJCgAAAA==.Nishale:BAAALgAECgMJBQAAAA==.',
No='Noir:BAAALgADCgQJBAAAAA==.',
Nu='Nutdraggin:BAAALgADCgcJBwAAAA==.',
Ny='Nyki:BAAALgAECgYJBwAAAA==.',
Op='Opius:BAAALgAECgcJDQAAAA==.',
Or='Orcmagic:BAAALgADCgQJBAAAAA==.',
Os='Oshift:BAAALgAECgYJBgAAAA==.',
Pa='Pandinha:BAACLgAFFH8OAAIFAAMJjh6JTAD/AANoDAAABgBTAGkMAAADAEUA6gwAAAUAUQAFAAMJjh6JTAD/AANoDAAABgBTAGkMAAADAEUA6gwAAAUAUQAuAAQKfy4AAgUACQn3ICoMADkDAAUACQn3ICoMADkDAAAA.Pattêrn:BAAALgAECgYJBQAAAA==.',
Pd='Pdr:BAAALgADCgcJBwAAAA==.',
Pe='Pedri:BAABLgAFFH8FAAIFAAIJvyIZYADQAAJoDAAAAgBaAOoMAAADAFcABQACCb8iGWAA0AACaAwAAAIAWgDqDAAAAwBXAAAA.Pedrok:BAAALgAECgMJBAAAAA==.',
Ph='Phoenixashes:BAAALgADCgIJAgAAAA==.',
Po='Pokz:BAAALgADCgEJAQAAAA==.',
Pr='Priestiality:BAAALgAECgIJAwAAAA==.Prowl:BAAALgAECgEJAQABLgAFFAUJEgAeAF0ZAA==.Prscilla:BAAALgADCgcJBgAAAA==.',
Qu='Quixote:BAAALgADCgcJBwAAAA==.',
Ra='Radagast:BAAALgADCgcJDQABLgAECggJIAAJAAATAA==.Radulf:BAAALgAECgQJBAAAAA==.Raph:BAACLgAFFH8KAAIFAAMJSyAQRwAKAQNoDAAABABcAGkMAAACAD8A6gwAAAQAWwAFAAMJSyAQRwAKAQNoDAAABABcAGkMAAACAD8A6gwAAAQAWwAuAAQKfygAAgUABwmJIxUhAA4CAAUABwmJIxUhAA4CAAAA.Raphy:BAAALgAECgcJEAABLgAFFAMJCgAFAEsgAA==.Ravyn:BAAALgADCgUJBQAAAA==.',
Re='Reckon:BAAALgAECgYJDAAAAA==.Redthedeer:BAAALgAECgcJCgAAAA==.Redzone:BAAALgAECgQJBgAAAA==.Refuliya:BAAALgADCgkJBwAAAA==.Remmahcm:BAABLgAECn8VAAIIAAgJUBYxPwApAghoDAAABABTAGkMAAAEADsAawwAAAMAUgBqDAAAAwAyAGwMAAADAE0A6gwAAAIAPABuDAAAAQAOAG8MAAABABYACAAICVAWMT8AKQIIaAwAAAQAUwBpDAAABAA7AGsMAAADAFIAagwAAAMAMgBsDAAAAwBNAOoMAAACADwAbgwAAAEADgBvDAAAAQAWAAAA.Renewing:BAAALgADCgQJBAAAAA==.Renrir:BAAALgADCgcJCAAAAA==.',
Rh='Rhark:BAAALgAECgUJDAAAAA==.',
Ri='Rikku:BAAALgAFFAEJAQAAAA==.',
Ro='Rook:BAABLgAECn8ZAAIIAAgJuCLgCgC4AghoDAAAAwBcAGkMAAAEAFcAawwAAAMAWgBqDAAAAwBSAGwMAAAEAFwAbQwAAAIAVwDqDAAABABeAG4MAAACAEwACAAICbgi4AoAuAIIaAwAAAMAXABpDAAABABXAGsMAAADAFoAagwAAAMAUgBsDAAABABcAG0MAAACAFcA6gwAAAQAXgBuDAAAAgBMAAAA.',
Ru='Runnow:BAAALgADCgYJCwAAAA==.',
Sa='Sagas:BAAALgAECgEJAQAAAA==.Salina:BAAALgAECgEJAQABLgAECgMJBQACAAAAAA==.Sammysam:BAAALgADCgUJBwAAAA==.Sathor:BAAALgADCgkJDgAAAA==.',
Sc='Scotch:BAAALgADCgQJBAABLgAFFAMJBQASANEKAA==.',
Sh='Shelton:BAAALgADCgMJAwABLgADCggJDQACAAAAAA==.Shinjey:BAAALgAECgMJBwAAAA==.',
Si='Sil:BAABLgAECn8ZAAIfAAkJCwr1FwCXAQloDAAABAAuAGkMAAAEAD0AawwAAAQAIwBqDAAAAwAVAGwMAAADAAgAbQwAAAEACwDqDAAAAwAbAG4MAAACAAoAbwwAAAEABAAfAAkJCwr1FwCXAQloDAAABAAuAGkMAAAEAD0AawwAAAQAIwBqDAAAAwAVAGwMAAADAAgAbQwAAAEACwDqDAAAAwAbAG4MAAACAAoAbwwAAAEABAAAAA==.Silents:BAAALgAECgUJBQAAAA==.Siphon:BAAALgAECgYJDAAAAA==.Siphons:BAAALgAECgMJBAAAAA==.',
Sk='Ska:BAACLgAFFH8UAAINAAYJhxSxDgCMAQZoDAAABQA0AGkMAAAFAEgAawwAAAMASQBqDAAAAgAjAGwMAAABABYA6gwAAAQAKQANAAYJhxSxDgCMAQZoDAAABQA0AGkMAAAFAEgAawwAAAMASQBqDAAAAgAjAGwMAAABABYA6gwAAAQAKQAuAAQKfxsAAw0ACAm7H1sYAMICAA0ACAm7H1sYAMICACAAAQkAAJFwADUAAAAA.',
Sl='Slyzete:BAAALgAECgQJBwAAAA==.',
So='Softbutt:BAAALgAECggJDwAAAA==.Sophie:BAAALgADCgcJBwAAAA==.Soulseeker:BAABLgAECn8WAAMNAAYJWBMLgADOAAZoDAAABQA8AGkMAAAGADkAawwAAAIANwBqDAAAAgAwAGwMAAACABAA6gwAAAUAOQANAAUJyhILgADOAAVoDAAABQA8AGkMAAADADkAagwAAAIAMABsDAAAAgAQAOoMAAAFADkAIAACCXwUZlAAfQACaQwAAAMAMQBrDAAAAgA3AAAA.',
St='Stölen:BAAALgAECgEJAQAAAA==.',
Sy='Sylthas:BAAALgADCgMJAwAAAA==.Syrensong:BAAALgAECgQJBAAAAA==.',
Ta='Tankli:BAAALgAECgIJBgAAAA==.Tanriel:BAAALgAECgEJAQAAAA==.Tatl:BAAALgADCgkJCQAAAA==.',
Te='Tertletoes:BAABLgAECn8cAAQhAAkJECXvAAC+AwloDAAABgBjAGkMAAAEAGEAawwAAAQAYABqDAAAAwBfAGwMAAACAGIAbQwAAAEAYgDqDAAABQBgAG4MAAACAFEAbwwAAAEAWwAhAAkJECXvAAC+AwloDAAABABjAGkMAAAEAGEAawwAAAQAYABqDAAAAwBfAGwMAAACAGIAbQwAAAEAYgDqDAAABABgAG4MAAACAFEAbwwAAAEAWwAKAAEJ2x45JwBMAAHqDAAAAQBOAAkAAQn+HdfaADkAAWgMAAACAEwAAAA=.Terts:BAAALgAECgEJAQABLgAECgkJHAAhABAlAA==.Teto:BAAALgAECgYJDgAAAA==.',
Th='Thebartender:BAAALgAECgcJDAAAAA==.Thella:BAAALgAECgQJBgAAAA==.Thopowisiwi:BAAALgAECggJDgAAAA==.',
To='Tog:BAABLgAECn8bAAIOAAkJciLHAwBVAwloDAAABABZAGkMAAAEAF4AawwAAAQAXABqDAAAAwBdAGwMAAADAGAAbQwAAAEATADqDAAABQBgAG4MAAACAFUAbwwAAAEAQwAOAAkJciLHAwBVAwloDAAABABZAGkMAAAEAF4AawwAAAQAXABqDAAAAwBdAGwMAAADAGAAbQwAAAEATADqDAAABQBgAG4MAAACAFUAbwwAAAEAQwAAAA==.Togame:BAAALgAECgUJCAAAAA==.Tognahok:BAAALgADCgYJDgAAAA==.Togy:BAAALgADCgEJAQAAAA==.Tortoisetoes:BAAALgAECgIJAgABLgAECgkJHAAhABAlAA==.',
Tr='Tremboladin:BAABLgAECn8aAAIVAAcJHxo2JgD2AQdoDAAABAA7AGkMAAAEAD0AawwAAAQAQQBqDAAABABhAGwMAAAEAE0AbQwAAAIANADqDAAABAA3ABUABwkfGjYmAPYBB2gMAAAEADsAaQwAAAQAPQBrDAAABABBAGoMAAAEAGEAbAwAAAQATQBtDAAAAgA0AOoMAAAEADcAAS4ABRQDCQUAGQBUBwA=.',
Ts='Tsnt:BAAALgAECgEJAQAAAA==.',
Tu='Turbosocks:BAAALgAECgIJBQAAAA==.Turok:BAAALgADCgMJAwAAAA==.Turtles:BAAALgADCgEJAQABLgAECgkJHAAhABAlAA==.Tuskydin:BAAALgADCgcJCQAAAA==.',
Ty='Tydrin:BAAALgAECgIJAwAAAA==.Tylandord:BAAALgADCgEJAQAAAA==.',
['Tý']='Týråél:BAAALgADCgYJCwAAAA==.',
Ur='Urra:BAABLgAECn8lAAIiAAgJTht1EwDGAQhoDAAABwBWAGkMAAAHAEoAawwAAAcAPQBqDAAABQA8AGwMAAAEADgAbQwAAAIAQwDqDAAAAwA+AG4MAAACAE8AIgAICU4bdRMAxgEIaAwAAAcAVgBpDAAABwBKAGsMAAAHAD0AagwAAAUAPABsDAAABAA4AG0MAAACAEMA6gwAAAMAPgBuDAAAAgBPAAAA.',
Va='Valoo:BAAALgAECgQJCgAAAA==.Valunar:BAAALgADCgUJBQAAAA==.',
Ve='Veyron:BAAALgADCgMJAwAAAA==.',
Vi='Vicar:BAAALgADCggJCQAAAA==.',
Vo='Voidstrider:BAAALgAECggJDgAAAA==.',
We='Weezard:BAAALgAECgQJDgAAAA==.',
Wh='Wheein:BAABLgAECn8iAAIUAAgJjyJ2BADaAghoDAAABgBhAGkMAAAGAGEAawwAAAUAXQBqDAAABABhAGwMAAAEAFwAbQwAAAIAQgDqDAAABQBaAG4MAAACAEcAFAAICY8idgQA2gIIaAwAAAYAYQBpDAAABgBhAGsMAAAFAF0AagwAAAQAYQBsDAAABABcAG0MAAACAEIA6gwAAAUAWgBuDAAAAgBHAAAA.',
Wi='Wingolingo:BAAALgAECgIJAgAAAA==.',
Ya='Yaamoonn:BAAALgADCgUJBQAAAA==.',
Ye='Yenn:BAABLgAECn8bAAMNAAkJXhtJFgDPAgloDAAABABaAGkMAAAEAFoAawwAAAQAOABqDAAAAwBAAGwMAAADAFoAbQwAAAEAOgDqDAAABQBOAG4MAAACADkAbwwAAAEAJQANAAkJXhtJFgDPAgloDAAABABaAGkMAAAEAFoAawwAAAQAOABqDAAAAgA/AGwMAAACAFoAbQwAAAEAOgDqDAAABQBOAG4MAAACADkAbwwAAAEAJQAgAAIJwAEsWgBgAAJqDAAAAQBAAGwMAAABAAQAAAA=.',
Za='Zardnax:BAAALgADCgIJAgAAAA==.',
Ze='Zenin:BAAALgADCggJFQAAAA==.Zenu:BAABLgAECn8eAAMiAAgJ7RsVEgCSAghoDAAABQBfAGkMAAAFAFAAawwAAAUAWgBqDAAAAwBCAGwMAAADAEcAbQwAAAEAGwDqDAAABgBVAG4MAAACADIAIgAICe0bFRIAkgIIaAwAAAQAXwBpDAAABQBQAGsMAAAFAFoAagwAAAMAQgBsDAAAAwBHAG0MAAABABsA6gwAAAYAVQBuDAAAAgAyACMAAQnVFW0fAD4AAWgMAAABADcAAAA=.',
Zu='Zugg:BAAALgADCgEJAQAAAA==.',
['Çh']='Çhakra:BAAALgAECgUJBwAAAA==.',
['Ðð']='Ððn:BAAALgADCgMJAQAAAA==.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end
