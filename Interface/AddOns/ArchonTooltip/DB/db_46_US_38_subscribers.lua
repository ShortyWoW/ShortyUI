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

local lookup = {'Paladin-Holy','Evoker-Preservation','Unknown-Unknown','Evoker-Augmentation','Evoker-Devastation','Monk-Brewmaster','DemonHunter-Havoc','DemonHunter-Devourer','DemonHunter-Vengeance','Priest-Shadow','Priest-Discipline','Warrior-Protection','Rogue-Subtlety','Mage-Frost','Warlock-Demonology','Shaman-Elemental','Rogue-Assassination','Warrior-Fury','Warlock-Destruction','Rogue-Outlaw','DeathKnight-Blood','Druid-Guardian','Monk-Windwalker','Monk-Mistweaver','Shaman-Restoration','Warlock-Affliction','Paladin-Retribution','DeathKnight-Unholy','Priest-Holy','Hunter-BeastMastery','Hunter-Marksmanship','Mage-Fire','Mage-Arcane','Druid-Balance',}
local provider = {region='US',realm='BleedingHollow',name='US',type='subscribers',zone=46,date='2026-05-01',data={Ad='Addex:BAEBLgAFFH8LAAIBAAYJyRAfAwDWAQZoDAAAAgA0AGkMAAACAD0AawwAAAIADQBqDAAAAgAiAGwMAAABACsA6gwAAAIANAABAAYJyRAfAwDWAQZoDAAAAgA0AGkMAAACAD0AawwAAAIADQBqDAAAAgAiAGwMAAABACsA6gwAAAIANAABLgAFFAgJIgACAAQcAA==.',
Ae='Aeveracy:BAEALgADCgMJAwABLgAECgIJAgADAAAAAA==.',
Am='Ambient:BAECLgAFFH8iAAMCAAgJBBxwAABxAghoDAAABgBhAGkMAAAGAEAAawwAAAYAQABqDAAABQBLAGwMAAAEAFQAbQwAAAEAJwDqDAAABQBLAG4MAAABAEkAAgAICQQccAAAcQIIaAwAAAQAYQBpDAAABgBAAGsMAAAGAEAAagwAAAUASwBsDAAABABUAG0MAAABACcA6gwAAAUASwBuDAAAAQBJAAQAAQk/F3AgAFAAAWgMAAACADsALgAECn8dAAMCAAkJcyPBBAADAwACAAgJKyPBBAADAwAFAAEJiBPNOgBEAAAAAA==.',
Br='Briéè:BAEALgAECgQJCAAAAA==.Bruwon:BAECLgAFFH8dAAIGAAcJDSOSAAAYAgdoDAAABQBXAGkMAAAFAFoAawwAAAUAVwBqDAAABAA8AGwMAAADAGIAbQwAAAEATwDqDAAABgBeAAYABwkNI5IAABgCB2gMAAAFAFcAaQwAAAUAWgBrDAAABQBXAGoMAAAEADwAbAwAAAMAYgBtDAAAAQBPAOoMAAAGAF4ALgAECn8hAAIGAAkJPyHHBAA+AwAGAAkJPyHHBAA+AwAAAA==.',
Ca='Captinsaneo:BAEALgAECggJCAAAAA==.',
Ch='Charzie:BAEALgAECgEJAQABLgAFFAcJHQAGAA0jAA==.',
Ci='Ciprox:BAEALgAECggJDgABLgAFFAYJDgAHAEwdAA==.',
Cy='Cyprexdh:BAECLgAFFH8OAAMHAAYJTB3vAQB7AQZoDAAABQBjAGkMAAADAFoAawwAAAIAQQBqDAAAAgA0AGwMAAABABwA6gwAAAEAWgAHAAQJfxnvAQB7AQRoDAAAAwBjAGkMAAABAAUAawwAAAEAQQDqDAAAAQBaAAgABQlkEVkUADABBWgMAAACADEAaQwAAAIAWgBrDAAAAQAJAGoMAAACADQAbAwAAAEAHAAuAAQKfxoABAcACAnwJTUDAFIDAAcACAlbJTUDAFIDAAgAAwmyJJF7ADUBAAkAAQkAALotACkAAAAA.',
Da='Danilynn:BAEALgADCggJFAABLgAECgYJFgAKAFYDAA==.Danitsia:BAEBLgAECn8WAAMKAAYJVgMkKAC+AAZoDAAABAAEAGkMAAAEAAkAawwAAAQACABqDAAAAwAUAGwMAAADAAsA6gwAAAQACAAKAAYJVgMkKAC+AAZoDAAABAAEAGkMAAAEAAkAawwAAAMACABqDAAAAwAUAGwMAAACAAsA6gwAAAMACAALAAMJ4wBxUQBGAANrDAAAAQACAGwMAAABAAMA6gwAAAEAAAAAAA==.',
De='Delabrand:BAEALgAECgYJCQABLgAFFAYJGQAMAMMmAA==.Delarage:BAECLgAFFH8ZAAIMAAYJwyZKAABCAgZoDAAABgBjAGkMAAAEAGMAawwAAAQAYwBqDAAABABiAGwMAAACAGQA6gwAAAUAYQAMAAYJwyZKAABCAgZoDAAABgBjAGkMAAAEAGMAawwAAAQAYwBqDAAABABiAGwMAAACAGQA6gwAAAUAYQAuAAQKfx8AAgwACAn5Jv4AAJADAAwACAn5Jv4AAJADAAAA.Deleerious:BAECLgAFFH8NAAINAAQJtSVxAQC1AQRoDAAABQBiAGkMAAAEAGAAawwAAAEAXgDqDAAAAwBgAA0ABAm1JXEBALUBBGgMAAAFAGIAaQwAAAQAYABrDAAAAQBeAOoMAAADAGAALgAECn8dAAINAAgJ+iCgBQA4AwANAAgJ+iCgBQA4AwAAAA==.',
Do='Doriel:BAEALgAECgMJBAABLgAFFAMJBwAOAOQQAA==.',
Du='Dubsstree:BAEALgADCgYJBgABLgAFFAYJGAAPALAdAA==.',
Dw='Dwarfwarloc:BAEALgAECgYJEQAAAA==.',
Eg='Egirlarmpits:BAEALgAFFAIJAgABLgAFFAQJBgAQACcLAA==.',
Em='Emellious:BAECLgAFFH8QAAINAAUJzxmVBwBrAQVoDAAABQBPAGkMAAAFAFsAawwAAAIAGgBqDAAAAQA6AOoMAAADAEMADQAFCc8ZlQcAawEFaAwAAAUATwBpDAAABQBbAGsMAAACABoAagwAAAEAOgDqDAAAAwBDAC4ABAp/HAADDQAICQMhnQwAzwIADQAICQMhnQwAzwIAEQABCZALgB8ANQAAAAA=.',
Fr='Freddyfletch:BAEALgADCgUJBQAAAA==.',
Fu='Funkaroused:BAEBLgAECn8lAAISAAcJYxp9KwAIAgdoDAAABgBbAGkMAAAGAEcAawwAAAYAQABqDAAABQBFAGwMAAAGAEsA6gwAAAYANABuDAAAAgAyABIABwljGn0rAAgCB2gMAAAGAFsAaQwAAAYARwBrDAAABgBAAGoMAAAFAEUAbAwAAAYASwDqDAAABgA0AG4MAAACADIAAAA=.',
Gi='Giantmagic:BAEBLgAECn8WAAIOAAcJthl/XQAiAgdoDAAAAwBOAGkMAAADAEoAawwAAAMAWwBqDAAABQBOAGwMAAACAD4AbQwAAAEAEwDqDAAABQBEAA4ABwm2GX9dACICB2gMAAADAE4AaQwAAAMASgBrDAAAAwBbAGoMAAAFAE4AbAwAAAIAPgBtDAAAAQATAOoMAAAFAEQAAAA=.',
Gj='Gjlo:BAEBLgAECn85AAMSAAkJixZdBwA5AgloDAAACABQAGkMAAAKAEwAawwAAAcATQBqDAAABwBGAGwMAAAHAEEAbQwAAAUAGQDqDAAABgBGAG4MAAAFADcAbwwAAAIACQASAAkJixZdBwA5AgloDAAABgBQAGkMAAAIAEwAawwAAAUATQBqDAAABABGAGwMAAADAEEAbQwAAAMAGQDqDAAABABGAG4MAAAFADcAbwwAAAIACQAMAAcJ/Q6cEwDzAAdoDAAAAgBCAGkMAAACADgAawwAAAIAJQBqDAAAAwArAGwMAAAEACsAbQwAAAIACADqDAAAAgARAAAA.',
Gl='Gluzzaie:BAEBLgAECn8UAAMPAAgJMhuLXgCtAQhoDAAAAwA7AGkMAAADAE0AawwAAAMANwBqDAAAAwA0AGwMAAACAFQAbQwAAAEANgDqDAAAAwBIAG4MAAACAFIADwAHCQ0bi14ArQEHaAwAAAMAOwBpDAAAAwBNAGsMAAABADQAbAwAAAIAVABtDAAAAQA2AOoMAAADAEgAbgwAAAIAUgATAAIJmBWxTACHAAJrDAAAAgA3AGoMAAADADQAAAA=.',
Gr='Gronknose:BAEBLgAECn8WAAIUAAcJ0iHgAQCcAgdoDAAAAwBVAGkMAAAEAFwAawwAAAQATABqDAAAAwBeAGwMAAACAFcAbQwAAAEAUgDqDAAABQBfABQABwnSIeABAJwCB2gMAAADAFUAaQwAAAQAXABrDAAABABMAGoMAAADAF4AbAwAAAIAVwBtDAAAAQBSAOoMAAAFAF8AAS4ABAoJCSMABgDWIwA=.',
Ha='Hakdh:BAEALgAECgYJBgABLgAFFAUJCgAVAG8QAA==.Hakdk:BAEBLgAFFH8KAAIVAAUJbxD3BQA7AQVoDAAAAQAiAGkMAAABACMAawwAAAEAJwBqDAAABAAaAOoMAAADADoAFQAFCW8Q9wUAOwEFaAwAAAEAIgBpDAAAAQAjAGsMAAABACcAagwAAAQAGgDqDAAAAwA6AAAA.Hakgek:BAEBLgAFFH8IAAIWAAQJMA53AgAlAQRoDAAAAgAlAGkMAAACACgAawwAAAIAJgBsDAAAAgAdABYABAkwDncCACUBBGgMAAACACUAaQwAAAIAKABrDAAAAgAmAGwMAAACAB0AAS4ABRQFCQoAFQBvEAA=.Hakmonk:BAEBLgAFFH8GAAIGAAQJSxHJDQAWAQRoDAAAAgAmAGkMAAACAEsAawwAAAEAEQDqDAAAAQAuAAYABAlLEckNABYBBGgMAAACACYAaQwAAAIASwBrDAAAAQARAOoMAAABAC4AAS4ABRQFCQoAFQBvEAA=.Haksham:BAEALgAECgcJBAABLgAFFAUJCgAVAG8QAA==.Hakwar:BAEALgAECgUJBQABLgAFFAUJCgAVAG8QAA==.Halosbrew:BAECLgAFFH8JAAIGAAQJrBnjDwADAQRoDAAAAgBLAGkMAAADAFYAawwAAAEAGgDqDAAAAwBKAAYABAmsGeMPAAMBBGgMAAACAEsAaQwAAAMAVgBrDAAAAQAaAOoMAAADAEoALgAECn8UAAMGAAgJRx4VFQBjAgAGAAcJzSEVFQBjAgAXAAUJaRO1PAAoAQAAAA==.Halosdk:BAEALgAFFAIJBAABLgAFFAQJCQAGAKwZAA==.Halosmage:BAEALgAECggJBwABLgAFFAQJCQAGAKwZAA==.',
He='Heavensfeel:BAEBLgAECn8jAAQCAAkJBx8MCAC7AgloDAAABgBVAGkMAAAFAD0AawwAAAUASwBqDAAABABbAGwMAAAEAFYAbQwAAAIAUADqDAAABgBVAG4MAAACAEMAbwwAAAEAUQACAAkJBx8MCAC7AgloDAAABQBVAGkMAAAEAD0AawwAAAQASwBqDAAAAwBbAGwMAAADAFYAbQwAAAIAUADqDAAABQBVAG4MAAACAEMAbwwAAAEAUQAEAAQJnw1KMACgAARpDAAAAQAHAGsMAAABADEAagwAAAEAOgBsDAAAAQAvAAUAAglDC4sNAHgAAmgMAAABABoA6gwAAAEAHgABLgAFFAQJCQAGAKwZAA==.',
In='Initiative:BAEBLgAECn8VAAMYAAgJhR04BgBjAghoDAAAAwBXAGkMAAADAFwAawwAAAQAYABqDAAAAwA8AGwMAAAEADMAbQwAAAEASQDqDAAAAgBRAG4MAAABAD0AGAAICYUdOAYAYwIIaAwAAAIAVwBpDAAAAgBcAGsMAAADAGAAagwAAAIAPABsDAAAAQAzAG0MAAABAEkA6gwAAAIAUQBuDAAAAQA9ABcABQl2JFIaAA0CBWgMAAABAFkAaQwAAAEAXQBrDAAAAQBeAGoMAAABAFUAbAwAAAMAYAAAAA==.',
It='Itsgrippy:BAEALgAECgYJDgAAAA==.',
Ke='Keeflan:BAECLgAFFH8GAAIQAAQJJwsMDQAlAQRoDAAAAgAbAGkMAAACABIAawwAAAEAMgDqDAAAAQASABAABAknCwwNACUBBGgMAAACABsAaQwAAAIAEgBrDAAAAQAyAOoMAAABABIALgAECn8ZAAMQAAgJIB+6KwC6AQAQAAYJ4B+6KwC6AQAZAAcJRg2uQAB+AQAAAA==.',
Le='Lewinskibidi:BAEALgAFFAIJBAABLgAFFAcJFQAKAIsbAA==.',
Ma='Madtheaug:BAEBLgAECn8WAAMFAAgJkyAsEgC+AQhoDAAAAgBPAGkMAAACAEkAawwAAAIAVwBqDAAABABWAGwMAAADAFwAbQwAAAMAUADqDAAABABbAG4MAAACAE4ABQAHCbMYLBIAvgEHaAwAAAIATwBpDAAAAgBJAGsMAAACAFcAagwAAAIAOwBsDAAAAgARAG0MAAACAC8A6gwAAAIASQAEAAUJgSFqIAC9AQVqDAAAAgBWAGwMAAABAFwAbQwAAAEAUADqDAAAAgBbAG4MAAACAE4AAS4ABRQJCR0AEwD/JQA=.Madthehunt:BAEALgAFFAEJAQABLgAFFAkJHQATAP8lAA==.Madthelock:BAECLgAFFH8dAAMTAAkJ/yU3AACWAgloDAAABABjAGkMAAAEAGMAawwAAAUAZABqDAAABABYAGwMAAADAGEAbQwAAAEAYgDqDAAABgBhAG4MAAABAFoAbwwAAAEAXgATAAcJiSY3AACWAgdoDAAAAQBjAGkMAAADAGMAawwAAAUAZABqDAAAAwBYAGwMAAACAGEAbQwAAAEAYgDqDAAAAwBhAA8ABwnQId8AAFECB2gMAAADAF8AaQwAAAEAXgBqDAAAAQBHAGwMAAABAC4A6gwAAAMAYQBuDAAAAQBaAG8MAAABAF4ALgAECn8ZAAQPAAkJhyRhDAAYAwAPAAkJkyFhDAAYAwATAAYJHCZdCgAZAgAaAAMJASRkDgBLAQAAAA==.Magølli:BAECLgAFFH8HAAIOAAMJ5BA2PQCxAANoDAAAAwAtAGkMAAADADgAawwAAAEAGgAOAAMJ5BA2PQCxAANoDAAAAwAtAGkMAAADADgAawwAAAEAGgAuAAQKfyEAAg4ACAk1H0gmANkCAA4ACAk1H0gmANkCAAAA.',
Mi='Minbä:BAEALgAECgYJEgABLgAFFAYJGAAPALAdAA==.Minigun:BAEALgAECgcJCgAAAQ==.Minipala:BAECLgAFFH8GAAIBAAMJvhgPEgDlAANoDAAAAwBPAGkMAAACADMA6gwAAAEAOwABAAMJvhgPEgDlAANoDAAAAwBPAGkMAAACADMA6gwAAAEAOwAuAAQKfx0AAwEACAk4IoMGAAMDAAEACAk4IoMGAAMDABsABQnnDz6zAB4BAAEuAAUUBgkYAA8AsB0A.Miniss:BAECLgAFFH8YAAMPAAYJsB3bAgDYAQZoDAAABgBeAGkMAAAFAE8AawwAAAMAUQBqDAAABABXAGwMAAACABoA6gwAAAQAYQAPAAYJsB3bAgDYAQZoDAAABgBeAGkMAAADAE8AawwAAAIAUQBqDAAABABXAGwMAAACABoA6gwAAAQAYQATAAIJgA1BDQCjAAJpDAAAAgAeAGsMAAABACYALgAECn84AAQPAAkJ1SXEAABiAwAPAAkJ0yXEAABiAwATAAIJESBBQQCwAAAaAAIJcCRiDABlAAAAAA==.',
Mo='Moosclemommy:BAECLgAFFH8PAAIGAAQJsiCpBACJAQRoDAAABQBFAGkMAAADAFgAawwAAAMAWQDqDAAABABXAAYABAmyIKkEAIkBBGgMAAAFAEUAaQwAAAMAWABrDAAAAwBZAOoMAAAEAFcALgAECn8gAAIGAAgJICXABQAsAwAGAAgJICXABQAsAwABLgAFFAYJCgACAKEIAA==.',
My='Mythicalhobo:BAEALgADCgUJCAAAAA==.Mythmaker:BAEALgAECgUJCgABLgAECgcJFgAOALYZAA==.',
Na='Nargrodamus:BAEBLgAECn8VAAIcAAgJiBLwTAAZAQhoDAAAAwBGAGkMAAAEADIAawwAAAMAQABqDAAABAArAGwMAAABAEkAbQwAAAEAGADqDAAAAwArAG4MAAACAAUAHAAICYgS8EwAGQEIaAwAAAMARgBpDAAABAAxAGsMAAADAEAAagwAAAQAKwBsDAAAAQBJAG0MAAABABgA6gwAAAMAKwBuDAAAAgAFAAAA.',
Ni='Nimueh:BAECLgAFFH8IAAIdAAUJEwllBABiAQVoDAAAAgAvAGkMAAABABwAawwAAAEABwBqDAAAAQATAGwMAAADAA0AHQAFCRMJZQQAYgEFaAwAAAIALwBpDAAAAQAcAGsMAAABAAcAagwAAAEAEwBsDAAAAwANAC4ABAp/JwADHQAJCS8S6BQANgIAHQAJCS8S6BQANgIACgAGCZ4NBRoALgEAAAA=.Nindë:BAEALgAFFAMJAwABLgAFFAUJFAAeAMEYAA==.Niniane:BAECLgAFFH8UAAMeAAUJwRjWCABiAQVoDAAABQAhAGkMAAAEAFEAawwAAAQAQQBqDAAAAwARAOoMAAAEAEkAHgAFCcEY1ggAYgEFaAwAAAQAIQBpDAAABABRAGsMAAACAEEAagwAAAEACADqDAAABABJAB8AAwnnAw0ZAMMAA2gMAAABAAoAawwAAAIACQBqDAAAAgARAC4ABAp/HwADHgAICXQfbRAAtgIAHgAHCeYibRAAtgIAHwAGCVIKkVYA7gAAAAA=.',
No='Nordsense:BAEALgAECgEJAQAAAA==.Novebear:BAEALgAFFAIJAwABLgAFFAMJCAAMABglAA==.Novelus:BAECLgAFFH8IAAIMAAMJGCXxAwBHAQNoDAAAAwBhAGkMAAABAF0A6gwAAAQAXQAMAAMJGCXxAwBHAQNoDAAAAwBhAGkMAAABAF0A6gwAAAQAXQAuAAQKfyYAAgwACAnzJJMBALcCAAwACAnzJJMBALcCAAAA.',
Ol='Oldbronze:BAECLgAFFH8FAAIMAAMJWxWxCQDjAANoDAAAAgBHAGkMAAACADwA6gwAAAEAHwAMAAMJWxWxCQDjAANoDAAAAgBHAGkMAAACADwA6gwAAAEAHwAuAAQKfygAAgwACAluIC4IAKICAAwACAluIC4IAKICAAAA.',
On='Onenjen:BAEBLgAECn8VAAIRAAcJkAIIDAC6AAdoDAAABAAHAGkMAAAEAAcAawwAAAQACQBqDAAAAgAFAGwMAAADAAgA6gwAAAMABABuDAAAAQACABEABwmQAggMALoAB2gMAAAEAAcAaQwAAAQABwBrDAAABAAJAGoMAAACAAUAbAwAAAMACADqDAAAAwAEAG4MAAABAAIAAAA=.',
['Oñ']='Oññayu:BAEALgAECgIJAgAAAA==.',
Pa='Parkercannon:BAECLgAFFH8VAAIKAAcJixsFAQA6AgdoDAAABABeAGkMAAAEAFwAawwAAAQAUABqDAAABABJAGwMAAACAF4AbQwAAAEAAQDqDAAAAgA8AAoABwmLGwUBADoCB2gMAAAEAF4AaQwAAAQAXABrDAAABABQAGoMAAAEAEkAbAwAAAIAXgBtDAAAAQABAOoMAAACADwALgAECn8mAAIKAAkJ8iPuAADQAwAKAAkJ8iPuAADQAwAAAA==.Patrennessy:BAEBLgAECn8jAAIGAAkJ1iPuAQDQAgloDAAABQBiAGkMAAAFAGAAawwAAAUAXQBqDAAABABdAGwMAAAEAGAAbQwAAAMAUgDqDAAABQBdAG4MAAADAFwAbwwAAAEAUAAGAAkJ1iPuAQDQAgloDAAABQBiAGkMAAAFAGAAawwAAAUAXQBqDAAABABdAGwMAAAEAGAAbQwAAAMAUgDqDAAABQBdAG4MAAADAFwAbwwAAAEAUAAAAA==.',
Ra='Ramsama:BAEALgAECgkJCAAAAA==.Ramsdh:BAEALgAECggJCAABLgAFFAYJEgANAGceAA==.Ramsx:BAECLgAFFH8SAAMNAAYJZx5xAwDEAQZoDAAABQBaAGkMAAAEAFYAawwAAAMAUQBqDAAAAQAYAGwMAAABACsA6gwAAAQAVgANAAUJtiFxAwDEAQVoDAAABQBaAGkMAAACAFYAawwAAAIAUQBqDAAAAQAYAOoMAAADAFYAEQAECX8SZgIAFgEEaQwAAAIAOgBrDAAAAQA6AGwMAAABACsA6gwAAAEAHAAuAAQKfxYAAw0ABglEJtwUAGsCAA0ABglEJtwUAGsCABEAAQk4JIYQAF4AAAAA.Rarelinelk:BAEALgAECgIJAgABLgAFFAYJEQAcACAjAA==.',
Re='Recursively:BAECLgAFFH8ZAAQPAAgJ4BKnAwDnAQhoDAAABABPAGkMAAAEAD8AawwAAAUAQgBqDAAAAwAlAGwMAAABABUAbQwAAAEACADqDAAABgBFAG4MAAABABsADwAHCfEUpwMA5wEHaAwAAAQATwBpDAAAAwA/AGsMAAADADoAagwAAAIADgBsDAAAAQAVAOoMAAAEAEUAbgwAAAEAGwATAAQJvg/QAwBaAQRpDAAAAQAsAGsMAAACAEIAbQwAAAEACADqDAAAAgApABoAAQkAAG8FAFcAAWoMAAABACUALgAECn8lAAQPAAkJXiP2DAASAwAPAAkJLyP2DAASAwATAAYJCiKCCAA6AgAaAAEJAADWIgBmAAAAAA==.Redxr:BAEALgAECgYJDQABLgAFFAYJCgALAPYUAA==.',
Sh='Sharrq:BAECLgAFFH8KAAIgAAQJ7xROAABZAQRoDAAABABJAGkMAAADAB4AawwAAAEAJgDqDAAAAgBIACAABAnvFE4AAFkBBGgMAAAEAEkAaQwAAAMAHgBrDAAAAQAmAOoMAAACAEgALgAECn8gAAMgAAgJwiCoAAASAwAgAAgJwiCoAAASAwAhAAEJKwlYHgA0AAAAAA==.',
Si='Sivvychuckle:BAEALgAECgIJAwABLgAECgcJCwADAAAAAA==.Sivvygrows:BAEALgAECgcJBwABLgAECgcJCwADAAAAAA==.Sivvyrawr:BAEALgAECgcJCwAAAA==.',
Sl='Slammybreath:BAEBLgAECn8dAAMEAAgJZxQiMQA+AQhoDAAABAAjAGkMAAAEADIAawwAAAQAQABqDAAABAArAGwMAAAEAE4AbQwAAAIAHwDqDAAABgA6AG4MAAABAC4ABAAGCcwSIjEAPgEGaAwAAAIAIwBpDAAAAgAxAGsMAAACADUAagwAAAIAKwBsDAAAAgArAOoMAAADADoABQAICdoT9CwAtAAIaAwAAAIAHwBpDAAAAgAyAGsMAAACAEAAagwAAAIAIgBsDAAAAgBOAG0MAAACAB8A6gwAAAMANQBuDAAAAQAuAAEuAAUUBgkKAAIAoQgA.',
Sp='Spicyhotwing:BAECLgAFFH8KAAICAAYJoQiFAwDOAQZoDAAAAQAKAGkMAAABAAsAawwAAAEAGwBqDAAAAgAhAGwMAAABAAUA6gwAAAQAKgACAAYJoQiFAwDOAQZoDAAAAQAKAGkMAAABAAsAawwAAAEAGwBqDAAAAgAhAGwMAAABAAUA6gwAAAQAKgAuAAQKfxQAAwIACAnrEjcUAAICAAIACAnrEjcUAAICAAUAAQl9Hnk4AFUAAAAA.',
Ta='Tauntinitis:BAEALgADCgMJAwABLgAECgkJOQASAIsWAA==.',
Te='Tendeyaloran:BAEALgAECgIJAgAAAA==.',
Th='Thanala:BAECLgAFFH8TAAIBAAUJDCLTAwDBAQVoDAAABQBSAGkMAAAFAGEAawwAAAMAWABqDAAAAgBLAOoMAAAEAFsAAQAFCQwi0wMAwQEFaAwAAAUAUgBpDAAABQBhAGsMAAADAFgAagwAAAIASwDqDAAABABbAC4ABAp/HAACAQAICWIefRQAbgIAAQAICWIefRQAbgIAAAA=.',
Tr='Trintu:BAEALgAECgkJAwABLgAFFAUJCgAVAG8QAA==.',
Yo='Yoktuah:BAEBLgAFFH8FAAMBAAQJ6gPBDQD9AARoDAAAAgAAAGkMAAABABwAawwAAAEACgDqDAAAAQAAAAEABAnqA8ENAP0ABGgMAAABAAAAaQwAAAEAHABrDAAAAQAKAOoMAAABAAAAGwABCRgRmTEAUgABaAwAAAEAKwABLgAFFAQJBgAQACcLAA==.',
Yu='Yungdh:BAEBLgAECn8UAAIIAAcJOBtNEgDaAQdoDAAAAwA4AGkMAAADAEwAawwAAAQAPwBqDAAAAwBMAGwMAAADAEkAbQwAAAEAPADqDAAAAwBWAAgABwk4G00SANoBB2gMAAADADgAaQwAAAMATABrDAAABAA/AGoMAAADAEwAbAwAAAMASQBtDAAAAQA8AOoMAAADAFYAAS4ABRQGCRUAIgBrJQA=.Yungdrood:BAECLgAFFH8VAAIiAAYJayX9AAA1AgZoDAAABQBjAGkMAAAFAGMAawwAAAQAYwBqDAAAAwBhAGwMAAABAF4A6gwAAAMAVQAiAAYJayX9AAA1AgZoDAAABQBjAGkMAAAFAGMAawwAAAQAYwBqDAAAAwBhAGwMAAABAF4A6gwAAAMAVQAuAAQKfywAAiIACAnQJkMCAJ8DACIACAnQJkMCAJ8DAAAA.Yungmonk:BAEALgAECgQJBAABLgAFFAYJFQAiAGslAA==.Yungwizard:BAEBLgAECn8WAAIOAAYJ2iXhOQCOAgZoDAAABABfAGkMAAAEAGIAawwAAAQAXwBqDAAAAwBhAGwMAAAEAGEA6gwAAAMAYQAOAAYJ2iXhOQCOAgZoDAAABABfAGkMAAAEAGIAawwAAAQAXwBqDAAAAwBhAGwMAAAEAGEA6gwAAAMAYQABLgAFFAYJFQAiAGslAA==.',
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
