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

local lookup = {'Paladin-Holy','Evoker-Preservation','Unknown-Unknown','Evoker-Augmentation','Evoker-Devastation','Warlock-Destruction','Warlock-Demonology','Monk-Brewmaster','Shaman-Elemental','DemonHunter-Devourer','DemonHunter-Havoc','DemonHunter-Vengeance','Priest-Shadow','Priest-Discipline','Warrior-Protection','Druid-Guardian','Rogue-Subtlety','Mage-Frost','Rogue-Assassination','Warrior-Fury','Rogue-Outlaw','DeathKnight-Blood','Monk-Windwalker','Monk-Mistweaver','Shaman-Restoration','Warlock-Affliction','Paladin-Retribution','DeathKnight-Unholy','Priest-Holy','Hunter-BeastMastery','Druid-Feral','Hunter-Marksmanship','Mage-Fire','Mage-Arcane','Druid-Balance',}
local provider = {region='US',realm='BleedingHollow',name='US',type='subscribers',zone=46,date='2026-05-20',data={Ad='Addex:BAEBLgAFFH8NAAIBAAYJjxM5BQCKAQZoDAAAAwA0AGkMAAACAD0AawwAAAIADQBqDAAAAgAiAGwMAAABACsA6gwAAAMAXgABAAYJjxM5BQCKAQZoDAAAAwA0AGkMAAACAD0AawwAAAIADQBqDAAAAgAiAGwMAAABACsA6gwAAAMAXgABLgAFFAkJMQACAFwgAA==.',
Ae='Aeveracy:BAEALgADCgMJAwABLgAECgIJAgADAAAAAA==.',
Am='Ambient:BAECLgAFFH8xAAMCAAkJXCAIAAB1AwloDAAACABhAGkMAAAIAFwAawwAAAcAUABqDAAABwBjAGwMAAAGAFYAbQwAAAIAVQDqDAAACABLAG4MAAACAEkAbwwAAAEAOAACAAkJXCAIAAB1AwloDAAABgBhAGkMAAAIAFwAawwAAAcAUABqDAAABwBjAGwMAAAGAFYAbQwAAAIAVQDqDAAACABLAG4MAAACAEkAbwwAAAEAOAAEAAEJPxd+IABQAAFoDAAAAgA7AC4ABAp/HQADAgAJCXMjvgQAAwMAAgAICSsjvgQAAwMABQABCYgT1joARAAAAAA=.',
Br='Briéè:BAEBLgAECn8UAAMGAAYJRxNoGgCqAAZoDAAABQBLAGkMAAAEADMAawwAAAQALwBqDAAAAwAuAGwMAAACADAA6gwAAAIAFgAHAAUJNw/QnQDiAAVoDAAAAwAvAGkMAAADACQAagwAAAEAKgBsDAAAAgAwAOoMAAACABYABgAECc4WaBoAqgAEaAwAAAIASwBpDAAAAQAzAGsMAAAEAC8AagwAAAIALgAAAA==.Bruwon:BAECLgAFFH8wAAIIAAgJtiELAQB0AghoDAAACABcAGkMAAAIAGMAawwAAAgAWgBqDAAABwBIAGwMAAAGAGIAbQwAAAEATwDqDAAACQBeAG4MAAABADIACAAICbYhCwEAdAIIaAwAAAgAXABpDAAACABjAGsMAAAIAFoAagwAAAcASABsDAAABgBiAG0MAAABAE8A6gwAAAkAXgBuDAAAAQAyAC4ABAp/IQACCAAJCUAhxwQAPgMACAAJCUAhxwQAPgMAAAA=.',
Ch='Charzie:BAEALgAECgUJBgABLgAFFAgJMAAIALYhAA==.',
Ci='Ciprox:BAEBLgAECn8VAAIJAAgJqB54EAA6AghoDAAAAwBVAGkMAAADAEcAawwAAAMAXABqDAAAAwBQAGwMAAADAGAAbQwAAAIAOADqDAAAAwBcAG4MAAABADcACQAICageeBAAOgIIaAwAAAMAVQBpDAAAAwBHAGsMAAADAFwAagwAAAMAUABsDAAAAwBgAG0MAAACADgA6gwAAAMAXABuDAAAAQA3AAEuAAUUBwkaAAoAJhoA.',
Cy='Cyprexdh:BAECLgAFFH8aAAMKAAcJJhpMCAAQAgdoDAAABwBjAGkMAAAFAFoAawwAAAQASwBqDAAABABbAGwMAAABAB0AbQwAAAEADwDqDAAABABaAAoABwlVF0wIABACB2gMAAAEAEAAaQwAAAQAWgBrDAAAAwBLAGoMAAAEAFsAbAwAAAEAHQBtDAAAAQAPAOoMAAADAFIACwAECX8Z7wEAewEEaAwAAAMAYwBpDAAAAQAFAGsMAAABAEEA6gwAAAEAWgAuAAQKfxoABAsACAnwJTkDAFIDAAsACAlbJTkDAFIDAAoAAwmyJJl7ADUBAAwAAQkAALYtACkAAAAA.',
Da='Danilynn:BAEALgADCggJFAABLgAECgcJHQANAIQDAA==.Danitsia:BAEBLgAECn8dAAMNAAcJhANEQwDJAAdoDAAABQAIAGkMAAAFAAsAawwAAAUACABqDAAABAAUAGwMAAAEAAsAbQwAAAEABADqDAAABQAIAA0ABwmEA0RDAMkAB2gMAAAFAAgAaQwAAAUACwBrDAAABAAIAGoMAAAEABQAbAwAAAMACwBtDAAAAQAEAOoMAAAEAAgADgADCeMAdVEARgADawwAAAEAAgBsDAAAAQADAOoMAAABAAAAAAA=.',
De='Delabrand:BAEALgAECgYJCQABLgAFFAgJHwAPAIkmAA==.Delajuv:BAEBLgAFFH8JAAIQAAUJrx4FBABtAQVoDAAAAgBTAGkMAAACAEwAawwAAAIATQBqDAAAAQAJAOoMAAACAEwAEAAFCa8eBQQAbQEFaAwAAAIAUwBpDAAAAgBMAGsMAAACAE0AagwAAAEACQDqDAAAAgBMAAEuAAUUCAkfAA8AiSYA.Delarage:BAECLgAFFH8fAAIPAAgJiSYmAAAPAwhoDAAABgBjAGkMAAAEAGMAawwAAAQAYwBqDAAABQBiAGwMAAADAGQAbQwAAAIAYQDqDAAABgBjAG4MAAABAF4ADwAICYkmJgAADwMIaAwAAAYAYwBpDAAABABjAGsMAAAEAGMAagwAAAUAYgBsDAAAAwBkAG0MAAACAGEA6gwAAAYAYwBuDAAAAQBeAC4ABAp/IQACDwAJCf4m/QAAkAMADwAJCf4m/QAAkAMAAAA=.Deleerious:BAECLgAFFH8TAAIRAAUJzCXqCwBoAQVoDAAABQBiAGkMAAAFAGEAawwAAAIAXgBqDAAAAQBdAOoMAAAGAGAAEQAFCcwl6gsAaAEFaAwAAAUAYgBpDAAABQBhAGsMAAACAF4AagwAAAEAXQDqDAAABgBgAC4ABAp/KgACEQAICR0kogUAOAMAEQAICR0kogUAOAMAAAA=.',
Do='Doriel:BAEALgAECgMJBAABLgAFFAUJEQASAOUUAA==.',
Du='Dubsstree:BAEALgADCgYJBgABLgAFFAcJHQAHANQZAA==.',
Dw='Dwarfwarloc:BAEBLgAECn8aAAIHAAgJKCJCEgCbAghoDAAABABgAGkMAAAEAFMAawwAAAQAWgBqDAAABABgAGwMAAADAGEAbQwAAAEARADqDAAABQBfAG8MAAABAE4ABwAICSgiQhIAmwIIaAwAAAQAYABpDAAABABTAGsMAAAEAFoAagwAAAQAYABsDAAAAwBhAG0MAAABAEQA6gwAAAUAXwBvDAAAAQBOAAAA.',
Eg='Egirlarmpits:BAEALgAFFAMJAwABLgAFFAQJDAAJACgUAA==.',
Em='Emellious:BAECLgAFFH8VAAIRAAUJwxuZBwBrAQVoDAAABgBPAGkMAAAFAFsAawwAAAMAGgBqDAAAAgA6AOoMAAAFAFcAEQAFCcMbmQcAawEFaAwAAAYATwBpDAAABQBbAGsMAAADABoAagwAAAIAOgDqDAAABQBXAC4ABAp/HAADEQAICQQhoQwAzgIAEQAICQQhoQwAzgIAEwABCZALgh8ANQAAAAA=.',
Fr='Freddyfletch:BAEALgADCgUJBQAAAA==.',
Fu='Funkaroused:BAEBLgAECn8vAAIUAAgJmRpVHADaAQhoDAAABwBbAGkMAAAHAEcAawwAAAcAQABqDAAABgBFAGwMAAAHAEsAbQwAAAEAMADqDAAACABKAG4MAAAEADIAFAAICZkaVRwA2gEIaAwAAAcAWwBpDAAABwBHAGsMAAAHAEAAagwAAAYARQBsDAAABwBLAG0MAAABADAA6gwAAAgASgBuDAAABAAyAAAA.',
Gi='Giantmagic:BAEBLgAECn8bAAISAAcJQh19XQAiAgdoDAAABABOAGkMAAAEAFIAawwAAAQAWwBqDAAABgBOAGwMAAACAD4AbQwAAAIAQgDqDAAABQBEABIABwlCHX1dACICB2gMAAAEAE4AaQwAAAQAUgBrDAAABABbAGoMAAAGAE4AbAwAAAIAPgBtDAAAAgBCAOoMAAAFAEQAAS4ABAoHCRMAAwAAAAA=.',
Gj='Gjlo:BAECLgAFFH8JAAMUAAMJzBPsIwDlAANoDAAABQBGAGkMAAACACUA6gwAAAIALAAUAAMJzBPsIwDlAANoDAAAAwBGAGkMAAABACUA6gwAAAIALAAPAAIJpAMoDgBlAAJoDAAAAgARAGkMAAABAAAALgAECn9KAAMUAAkJtxpdCwCEAgAUAAkJtxpdCwCEAgAPAAcJdw/gJADZAAAAAA==.',
Gr='Gronknose:BAEBLgAECn8WAAIVAAcJ0iHgAQCcAgdoDAAAAwBVAGkMAAAEAFwAawwAAAQATABqDAAAAwBeAGwMAAACAFcAbQwAAAEAUgDqDAAABQBfABUABwnSIeABAJwCB2gMAAADAFUAaQwAAAQAXABrDAAABABMAGoMAAADAF4AbAwAAAIAVwBtDAAAAQBSAOoMAAAFAF8AAS4ABAoJCTEACACxJAA=.',
Ha='Hakdh:BAEALgAECgYJBgABLgAFFAYJFwAWACAOAA==.Hakdk:BAECLgAFFH8XAAIWAAYJIA7+BQA7AQZoDAAABAAlAGkMAAADACMAawwAAAMAJwBqDAAABgAaAG0MAAABAAMA6gwAAAYAQAAWAAYJIA7+BQA7AQZoDAAABAAlAGkMAAADACMAawwAAAMAJwBqDAAABgAaAG0MAAABAAMA6gwAAAYAQAAuAAQKfxQAAhYACAkkHtMKAGoCABYACAkkHtMKAGoCAAAA.Hakgek:BAEBLgAFFH8KAAIQAAUJFAxqBABeAQVoDAAAAgAlAGkMAAACACgAawwAAAIAJgBsDAAAAwAdAG4MAAABAAgAEAAFCRQMagQAXgEFaAwAAAIAJQBpDAAAAgAoAGsMAAACACYAbAwAAAMAHQBuDAAAAQAIAAEuAAUUBgkXABYAIA4A.Hakmonk:BAEBLgAFFH8GAAIIAAQJSxHODQAWAQRoDAAAAgAmAGkMAAACAEsAawwAAAEAEQDqDAAAAQAuAAgABAlLEc4NABYBBGgMAAACACYAaQwAAAIASwBrDAAAAQARAOoMAAABAC4AAS4ABRQGCRcAFgAgDgA=.Haksham:BAEALgAECgkJDQABLgAFFAYJFwAWACAOAA==.Hakwar:BAEALgAECgUJBQABLgAFFAYJFwAWACAOAA==.Halosbrew:BAECLgAFFH8JAAIIAAQJqhnoDwADAQRoDAAAAgBLAGkMAAADAFYAawwAAAEAGgDqDAAAAwBKAAgABAmqGegPAAMBBGgMAAACAEsAaQwAAAMAVgBrDAAAAQAaAOoMAAADAEoALgAECn8UAAMIAAgJRx4TFQBjAgAIAAcJzSETFQBjAgAXAAUJaRO9PAAoAQAAAA==.Halosdk:BAEBLgAFFH8NAAIWAAUJFBhWEQASAQVoDAAAAwBEAGkMAAACAEsAawwAAAIAGwBqDAAAAQA/AOoMAAAFAEoAFgAFCRQYVhEAEgEFaAwAAAMARABpDAAAAgBLAGsMAAACABsAagwAAAEAPwDqDAAABQBKAAEuAAUUBQkJAAgAqhkA.Halosmage:BAEALgAECggJDgABLgAFFAUJCQAIAKoZAA==.',
He='Heavensfeel:BAEBLgAECn80AAQCAAkJFB8MCAC7AgloDAAACABVAGkMAAAHAD0AawwAAAcASwBqDAAABgBbAGwMAAAGAFYAbQwAAAQAUADqDAAACABVAG4MAAAEAEQAbwwAAAIAUQACAAkJFB8MCAC7AgloDAAABQBVAGkMAAAEAD0AawwAAAQASwBqDAAAAwBbAGwMAAAEAFYAbQwAAAMAUADqDAAABQBVAG4MAAACAEQAbwwAAAEAUQAEAAkJyBvICQCSAgloDAAAAgBYAGkMAAADAF8AawwAAAMAXQBqDAAAAwBUAGwMAAACAFUAbQwAAAEAKADqDAAAAgApAG4MAAACAF8AbwwAAAEAHAAFAAIJjgtqFwBsAAJoDAAAAQAbAOoMAAABAB8AAS4ABRQFCQkACACqGQA=.',
In='Inaríus:BAEALgAECgcJEwAAAA==.Initiative:BAEBLgAECn8aAAMYAAgJcB7tCwCWAghoDAAAAwBXAGkMAAADAFwAawwAAAQAXwBqDAAAAwA8AGwMAAAFAEYAbQwAAAIASQDqDAAABABRAG4MAAACAD0AGAAICXAe7QsAlgIIaAwAAAIAVwBpDAAAAgBcAGsMAAADAF8AagwAAAIAPABsDAAAAgBGAG0MAAACAEkA6gwAAAIAUQBuDAAAAQA9ABcABwmnH1saAA0CB2gMAAABAFkAaQwAAAEAXQBrDAAAAQBeAGoMAAABAFUAbAwAAAMAYADqDAAAAgBQAG4MAAABACAAAAA=.',
It='Itsgrippy:BAEALgAECgYJDgAAAA==.',
Je='Jev:BAEBLgAECn8hAAINAAkJiCKhAgCAAwloDAAABABeAGkMAAAEAF4AawwAAAQAXgBqDAAABABYAGwMAAAEAFsAbQwAAAQAVQDqDAAAAwBVAG4MAAAFAEwAbwwAAAEAVAANAAkJiCKhAgCAAwloDAAABABeAGkMAAAEAF4AawwAAAQAXgBqDAAABABYAGwMAAAEAFsAbQwAAAQAVQDqDAAAAwBVAG4MAAAFAEwAbwwAAAEAVAABLgAFFAQJBgAPAM4SAA==.',
Ke='Keeflan:BAECLgAFFH8MAAIJAAQJKBSDFgAoAQRoDAAAAwA8AGkMAAADABoAawwAAAIAMgDqDAAABABFAAkABAkoFIMWACgBBGgMAAADADwAaQwAAAMAGgBrDAAAAgAyAOoMAAAEAEUALgAECn8bAAMJAAgJIiC5KwC6AQAJAAcJUCC5KwC6AQAZAAcJRg2tQAB+AQAAAA==.',
Ku='Kungfupander:BAEALgADCgMJAwABLgAECgcJEwADAAAAAA==.',
Le='Lewinskibidi:BAEBLgAFFH8HAAIEAAUJ3BQQEACGAQVoDAAAAgBMAGkMAAACAEUAawwAAAEAOgDqDAAAAQAyAG4MAAABAAsABAAFCdwUEBAAhgEFaAwAAAIATABpDAAAAgBFAGsMAAABADoA6gwAAAEAMgBuDAAAAQALAAEuAAUUBwkfAA0ADx8A.',
Ma='Madtheaug:BAEBLgAECn8WAAMFAAgJkyAzEgC+AQhoDAAAAgBPAGkMAAACAEkAawwAAAIAVwBqDAAABABWAGwMAAADAFwAbQwAAAMAUADqDAAABABbAG4MAAACAE4ABQAHCbMYMxIAvgEHaAwAAAIATwBpDAAAAgBJAGsMAAACAFcAagwAAAIAOwBsDAAAAgARAG0MAAACAC8A6gwAAAIASQAEAAUJgSFyIAC9AQVqDAAAAgBWAGwMAAABAFwAbQwAAAEAUADqDAAAAgBbAG4MAAACAE4AAS4ABRQJCSwABwAkJgA=.Madthehunt:BAEALgAFFAEJAQABLgAFFAkJLAAHACQmAA==.Madthelock:BAECLgAFFH8sAAQHAAkJJCagAADdAgloDAAABQBjAGkMAAAHAGMAawwAAAcAZABqDAAABwBYAGwMAAAFAGQAbQwAAAIAYgDqDAAACABhAG4MAAACAFoAbwwAAAEAXgAHAAkJFyKgAADdAgloDAAAAwBfAGkMAAADAGMAawwAAAEAYgBqDAAAAgBHAGwMAAACAFQAbQwAAAEAJADqDAAABABhAG4MAAACAFoAbwwAAAEAXgAGAAcJiSY4AACWAgdoDAAAAQBjAGkMAAADAGMAawwAAAUAZABqDAAAAwBYAGwMAAACAGEAbQwAAAEAYgDqDAAAAwBhABoABgkTJioAACUCBmgMAAABAGEAaQwAAAEAYwBrDAAAAQBeAGoMAAACAFYAbAwAAAEAZADqDAAAAQBgAC4ABAp/KgAEBwAJCbEmQwIAYQMABwAJCU0mQwIAYQMAGgAICWYmhgAAEQMABgAGCRwmXQoAGQIAAAA=.Magolli:BAEALgAECgQJBAABLgAFFAUJEQASAOUUAA==.Magølli:BAECLgAFFH8RAAISAAUJ5RQfPQBIAQVoDAAABQA5AGkMAAAFAEMAawwAAAMAGgBqDAAAAQBLAOoMAAADAD0AEgAFCeUUHz0ASAEFaAwAAAUAOQBpDAAABQBDAGsMAAADABoAagwAAAEASwDqDAAAAwA9AC4ABAp/LgACEgAICeAgTSYA2QIAEgAICeAgTSYA2QIAAAA=.',
Me='Megachud:BAEALgAFFAEJAQABLgAFFAQJDAAJACgUAA==.',
Mi='Minbä:BAEALgAECgYJEgABLgAFFAcJHQAHANQZAA==.Minigun:BAEALgAECgcJCgAAAQ==.Minipala:BAECLgAFFH8LAAIBAAQJtBtmGAAnAQRoDAAABABPAGkMAAACADMAawwAAAIASwDqDAAAAwBNAAEABAm0G2YYACcBBGgMAAAEAE8AaQwAAAIAMwBrDAAAAgBLAOoMAAADAE0ALgAECn8dAAMBAAgJOCKCBgADAwABAAgJOCKCBgADAwAbAAUJ5w9EswAeAQABLgAFFAcJHQAHANQZAA==.Miniss:BAECLgAFFH8dAAQHAAcJ1BnbCAD0AQdoDAAABwBeAGkMAAAGAE8AawwAAAQAUgBqDAAABABXAGwMAAACABoAbQwAAAEADwDqDAAABQBhAAcABwnUGdsIAPQBB2gMAAAHAF4AaQwAAAMATwBrDAAAAwBSAGoMAAAEAFcAbAwAAAIAGgBtDAAAAQAPAOoMAAAEAGEABgACCYANTA0AowACaQwAAAIAHgBrDAAAAQAmABoAAgl0DxAIAJcAAmkMAAABABMA6gwAAAEAPAAuAAQKf0EABBoACQkjJmUAACoDAAcACQnfJWQEADIDABoACQk3JWUAACoDAAYAAgkRIEVBALAAAAAA.',
Mo='Mobes:BAEBLgAECn8uAAIQAAkJ7hY0CwDkAQloDAAABwBCAGkMAAAGAE8AawwAAAYAPwBqDAAABQAiAGwMAAAGADcAbQwAAAUAOwDqDAAABQBOAG4MAAAFACUAbwwAAAEAHQAQAAkJ7hY0CwDkAQloDAAABwBCAGkMAAAGAE8AawwAAAYAPwBqDAAABQAiAGwMAAAGADcAbQwAAAUAOwDqDAAABQBOAG4MAAAFACUAbwwAAAEAHQAAAA==.Moosclemommy:BAECLgAFFH8VAAIIAAYJDiJ/BADsAQZoDAAABgBVAGkMAAADAFgAawwAAAMAWQBqDAAAAQAuAGwMAAACAE0A6gwAAAYAXwAIAAYJDiJ/BADsAQZoDAAABgBVAGkMAAADAFgAawwAAAMAWQBqDAAAAQAuAGwMAAACAE0A6gwAAAYAXwAuAAQKfyQAAggACAlOJb4FACwDAAgACAlOJb4FACwDAAEuAAUUCAkUAAIAEA0A.',
My='Mythicalhobo:BAEALgADCgUJCAAAAA==.Mythmaker:BAEALgAECgUJDQABLgAECgcJEwADAAAAAA==.',
Na='Nargrodamus:BAEBLgAECn8oAAIcAAgJ8hggOQDyAQhoDAAABgBGAGkMAAAHAFYAawwAAAUAQABqDAAABgA5AGwMAAAEAEkAbQwAAAIAGADqDAAABgBLAG4MAAAEADMAHAAICfIYIDkA8gEIaAwAAAYARgBpDAAABwBWAGsMAAAFAEAAagwAAAYAOQBsDAAABABJAG0MAAACABgA6gwAAAYASwBuDAAABAAzAAAA.',
Ni='Nimueh:BAECLgAFFH8PAAIdAAYJNArdBgCWAQZoDAAAAwAvAGkMAAACABwAawwAAAIAEABqDAAAAgAYAGwMAAAFABMA6gwAAAEAFAAdAAYJNArdBgCWAQZoDAAAAwAvAGkMAAACABwAawwAAAIAEABqDAAAAgAYAGwMAAAFABMA6gwAAAEAFAAuAAQKfy0AAx0ACQkvEukUADYCAB0ACQkvEukUADYCAA0ABwngD8opAEwBAAAA.Nindragosa:BAEALgAFFAQJBAABLgAFFAcJHAAeAIUZAA==.Nindë:BAEBLgAFFH8JAAIfAAMJLQnrCADcAANoDAAAAwAeAGkMAAADABwA6gwAAAMACwAfAAMJLQnrCADcAANoDAAAAwAeAGkMAAADABwA6gwAAAMACwABLgAFFAcJHAAeAIUZAA==.Niniane:BAECLgAFFH8cAAMeAAcJhRnYBADYAQdoDAAABgBOAGkMAAAFAF8AawwAAAUATQBqDAAABAAWAGwMAAABAAoAbQwAAAEAOADqDAAABgBJAB4ABgnEHdgEANgBBmgMAAAFAE4AaQwAAAUAXwBrDAAAAwBNAGoMAAACABYAbQwAAAEAOADqDAAABgBJACAABAkJBCIZAMMABGgMAAABAAoAawwAAAIACQBqDAAAAgARAGwMAAABAAoALgAECn8nAAMeAAkJGyPMDgCnAgAeAAkJGyPMDgCnAgAgAAYJUgq0VgDuAAAAAA==.',
No='Nordsense:BAEALgAECgEJAQAAAA==.Novebear:BAEBLgAFFH8HAAIQAAIJYRs6EAChAAJoDAAABABCAOoMAAADAEkAEAACCWEbOhAAoQACaAwAAAQAQgDqDAAAAwBJAAEuAAUUAwkPAA8AwiUA.Novelus:BAECLgAFFH8PAAIPAAMJwiX3AwBHAQNoDAAABgBhAGkMAAAEAF4A6gwAAAUAYgAPAAMJwiX3AwBHAQNoDAAABgBhAGkMAAAEAF4A6gwAAAUAYgAuAAQKfzEAAg8ACQkAJuoAAFMDAA8ACQkAJuoAAFMDAAAA.',
Ol='Oldbronze:BAECLgAFFH8QAAIPAAUJLBr6CgA1AQVoDAAABQBLAGkMAAAEAEkAawwAAAIAKABqDAAAAQBIAOoMAAAEAE4ADwAFCSwa+goANQEFaAwAAAUASwBpDAAABABJAGsMAAACACgAagwAAAEASADqDAAABABOAC4ABAp/MgACDwAICdUifwUAlAIADwAICdUifwUAlAIAAAA=.',
On='Onenjen:BAEBLgAECn8nAAITAAgJKgRCEADzAAhoDAAACAAPAGkMAAAIAAgAawwAAAgAFwBqDAAABAANAGwMAAAEAAgAbQwAAAEABQDqDAAABQAMAG4MAAABAAIAEwAICSoEQhAA8wAIaAwAAAgADwBpDAAACAAIAGsMAAAIABcAagwAAAQADQBsDAAABAAIAG0MAAABAAUA6gwAAAUADABuDAAAAQACAAAA.',
['Oñ']='Oññayu:BAEALgAECgIJAgAAAA==.',
Pa='Parkercannon:BAECLgAFFH8fAAINAAcJDx8GAQA6AgdoDAAABQBeAGkMAAAEAFwAawwAAAUAUgBqDAAABgBJAGwMAAAEAF4AbQwAAAMALgDqDAAABABBAA0ABwkPHwYBADoCB2gMAAAFAF4AaQwAAAQAXABrDAAABQBSAGoMAAAGAEkAbAwAAAQAXgBtDAAAAwAuAOoMAAAEAEEALgAECn8tAAINAAkJkyTuAADQAwANAAkJkyTuAADQAwAAAA==.Patrennessy:BAEBLgAECn8xAAIIAAkJsSTAAQA3AwloDAAABgBiAGkMAAAGAGAAawwAAAYAXgBqDAAABQBdAGwMAAAGAGAAbQwAAAUAWgDqDAAABwBdAG4MAAAFAF0AbwwAAAMAVwAIAAkJsSTAAQA3AwloDAAABgBiAGkMAAAGAGAAawwAAAYAXgBqDAAABQBdAGwMAAAGAGAAbQwAAAUAWgDqDAAABwBdAG4MAAAFAF0AbwwAAAMAVwAAAA==.',
Ra='Ramsama:BAEALgAECgkJEQAAAA==.Ramsdh:BAEALgAFFAMJAwABLgAFFAcJGwARANcdAA==.Ramsx:BAECLgAFFH8bAAMRAAcJ1x3/AwDvAQdoDAAABwBcAGkMAAAGAF8AawwAAAQAUgBqDAAAAgAuAGwMAAABACkA6gwAAAYAVgBuDAAAAQA7ABEABgmJIP8DAO8BBmgMAAAHAFwAaQwAAAQAXwBrDAAAAwBSAGoMAAACAC4A6gwAAAUAVgBuDAAAAQA7ABMABAlLEmgCABYBBGkMAAACADoAawwAAAEAOgBsDAAAAQApAOoMAAABABwALgAECn8XAAMRAAcJyiXcFABrAgARAAcJyiXcFABrAgATAAEJOCSOGwBWAAAAAA==.Rarelinelk:BAEALgAECgIJAgABLgAECgYJDAADAAAAAA==.',
Re='Recursively:BAECLgAFFH8fAAQHAAgJ8ROrAwDnAQhoDAAABgBhAGkMAAAFAEAAawwAAAYAQgBqDAAAAwAlAGwMAAABABUAbQwAAAEACADqDAAACABGAG4MAAABABsABwAHCTAWqwMA5wEHaAwAAAYAYQBpDAAAAwBAAGsMAAAEADoAagwAAAIADgBsDAAAAQAVAOoMAAAGAEYAbgwAAAEAGwAGAAQJvg/YAwBaAQRpDAAAAQAsAGsMAAACAEIAbQwAAAEACADqDAAAAgApABoAAgkICHYFAFcAAmkMAAABABQAagwAAAEAJQAuAAQKfyoABAcACQlpIzELANgCAAcACQlIIzELANgCAAYABgkKIoQIADoCABoAAQkAANgiAGYAAAAA.Redxr:BAEALgAECgYJDQABLgAFFAcJDgAOAA0WAA==.Releira:BAEALgAFFAIJAwABLgAFFAUJEQASAOUUAA==.',
Ri='Riversong:BAEALgAECgYJBgABLgAFFAYJDwAdADQKAA==.',
Sh='Sharrq:BAECLgAFFH8SAAIhAAQJzxq7AABbAQRoDAAABgBJAGkMAAAFACoAawwAAAMASADqDAAABABWACEABAnPGrsAAFsBBGgMAAAGAEkAaQwAAAUAKgBrDAAAAwBIAOoMAAAEAFYALgAECn8gAAMhAAgJxCCoAAASAwAhAAgJxCCoAAASAwAiAAEJKwlZHgA0AAAAAA==.Shotgunarms:BAEALgAECgQJBAABLgAECggJGgAYAHAeAA==.',
Si='Silversoph:BAEALgADCgMJAwAAAA==.Sivvychuckle:BAEALgAECgIJAwABLgAECgcJCwADAAAAAA==.Sivvygrows:BAEALgAECgcJBwABLgAECgcJCwADAAAAAA==.Sivvyrawr:BAEALgAECgcJCwAAAA==.',
Sl='Slammybreath:BAECLgAFFH8JAAMEAAQJ4xP2GwAtAQRoDAAAAwArAGkMAAADAEwAawwAAAIAHADqDAAAAQA3AAQABAnjE/YbAC0BBGgMAAACACsAaQwAAAMATABrDAAAAgAcAOoMAAABADcABQABCTYBHgwAQwABaAwAAAEAAwAuAAQKfx0AAwQACAloFCQxAD4BAAQABgnOEiQxAD4BAAUACAnaE/ssALQAAAEuAAUUCAkUAAIAEA0A.',
Sp='Spicyhotwing:BAECLgAFFH8UAAMCAAgJEA2KAwDOAQhoDAAAAwAKAGkMAAADAAsAawwAAAMAGwBqDAAABAAhAGwMAAABAAUAbQwAAAEAWQDqDAAABAAqAG4MAAABAC0AAgAGCaEIigMAzgEGaAwAAAEACgBpDAAAAQALAGsMAAABABsAagwAAAQAIQBsDAAAAQAFAOoMAAAEACoABAAFCUgUdQsAwAEFaAwAAAIATwBpDAAAAgBgAGsMAAACAEYAbQwAAAEABABuDAAAAQAJAC4ABAp/GAAEAgAICesSQBQAAgIAAgAICesSQBQAAgIABAAECbQkzzAAPQEABQABCX0efjgAVQAAAAA=.',
Ta='Tauntinitis:BAEALgAECgUJBQABLgAFFAMJCQAUAMwTAA==.',
Te='Tendeyaloran:BAEALgAECgYJEAAAAA==.',
Th='Thanala:BAECLgAFFH8aAAIBAAYJsiL6BgD7AQZoDAAABgBSAGkMAAAGAGEAawwAAAQAWABqDAAAAwBLAGwMAAABAGEA6gwAAAYAWwABAAYJsiL6BgD7AQZoDAAABgBSAGkMAAAGAGEAawwAAAQAWABqDAAAAwBLAGwMAAABAGEA6gwAAAYAWwAuAAQKfyIAAgEACAlhHnwUAG4CAAEACAlhHnwUAG4CAAAA.',
Tr='Trintu:BAEALgAECgkJAwABLgAFFAYJFwAWACAOAA==.',
Yo='Yoktuah:BAEBLgAFFH8GAAMBAAQJ6gPGDQD9AARoDAAAAwAAAGkMAAABABwAawwAAAEACgDqDAAAAQAAAAEABAnqA8YNAP0ABGgMAAABAAAAaQwAAAEAHABrDAAAAQAKAOoMAAABAAAAGwABCRgRnTEAUgABaAwAAAIAKwABLgAFFAQJDAAJACgUAA==.',
Yu='Yungdh:BAEBLgAECn8cAAIKAAcJ+hwTLgDlAQdoDAAABAA8AGkMAAAEAEwAawwAAAUAUgBqDAAABABOAGwMAAAEAEkAbQwAAAEAPADqDAAABgBbAAoABwn6HBMuAOUBB2gMAAAEADwAaQwAAAQATABrDAAABQBSAGoMAAAEAE4AbAwAAAQASQBtDAAAAQA8AOoMAAAGAFsAAS4ABRQHCSAAIwAOJgA=.Yungdrood:BAECLgAFFH8gAAIjAAcJDiY/AQCCAgdoDAAABgBjAGkMAAAHAGMAawwAAAYAYwBqDAAABQBhAGwMAAACAF4AbQwAAAEAXADqDAAABQBiACMABwkOJj8BAIICB2gMAAAGAGMAaQwAAAcAYwBrDAAABgBjAGoMAAAFAGEAbAwAAAIAXgBtDAAAAQBcAOoMAAAFAGIALgAECn82AAIjAAkJ1iZBAgCfAwAjAAkJ1iZBAgCfAwAAAA==.Yungmonk:BAEALgAECgQJBAABLgAFFAcJIAAjAA4mAA==.Yungwizard:BAEBLgAECn8WAAISAAYJ2iXfOQCOAgZoDAAABABfAGkMAAAEAGIAawwAAAQAXwBqDAAAAwBhAGwMAAAEAGEA6gwAAAMAYQASAAYJ2iXfOQCOAgZoDAAABABfAGkMAAAEAGIAawwAAAQAXwBqDAAAAwBhAGwMAAAEAGEA6gwAAAMAYQABLgAFFAcJIAAjAA4mAA==.',
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
