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

local lookup = {'Paladin-Holy','Evoker-Preservation','Unknown-Unknown','Evoker-Augmentation','Evoker-Devastation','Monk-Brewmaster','Shaman-Elemental','DemonHunter-Devourer','DemonHunter-Havoc','DemonHunter-Vengeance','Priest-Shadow','Priest-Discipline','Warrior-Protection','Druid-Guardian','Rogue-Subtlety','Mage-Frost','Warlock-Demonology','Rogue-Assassination','Warrior-Fury','Warlock-Destruction','Rogue-Outlaw','DeathKnight-Blood','Monk-Windwalker','Monk-Mistweaver','Shaman-Restoration','Warlock-Affliction','Paladin-Retribution','DeathKnight-Unholy','Priest-Holy','Druid-Feral','Hunter-BeastMastery','Hunter-Marksmanship','Mage-Fire','Mage-Arcane','Druid-Balance',}
local provider = {region='US',realm='BleedingHollow',name='US',type='subscribers',zone=46,date='2026-05-13',data={Ad='Addex:BAEBLgAFFH8NAAIBAAYJjxNfBgDSAQZoDAAAAwA0AGkMAAACAD0AawwAAAIADQBqDAAAAgAiAGwMAAABACsA6gwAAAMAXgABAAYJjxNfBgDSAQZoDAAAAwA0AGkMAAACAD0AawwAAAIADQBqDAAAAgAiAGwMAAABACsA6gwAAAMAXgABLgAFFAgJKQACAAwdAA==.',
Ae='Aeveracy:BAEALgADCgMJAwABLgAECgIJAgADAAAAAA==.',
Am='Ambient:BAECLgAFFH8pAAMCAAgJDB3PAABkAghoDAAABwBhAGkMAAAHAEUAawwAAAcAUABqDAAABgBLAGwMAAAFAFQAbQwAAAEAJwDqDAAABwBLAG4MAAABAEkAAgAICQwdzwAAZAIIaAwAAAUAYQBpDAAABwBFAGsMAAAHAFAAagwAAAYASwBsDAAABQBUAG0MAAABACcA6gwAAAcASwBuDAAAAQBJAAQAAQk/F34gAFAAAWgMAAACADsALgAECn8dAAMCAAkJcyO+BAADAwACAAgJKyO+BAADAwAFAAEJiBPWOgBEAAAAAA==.',
Br='Briéè:BAEALgAECgYJDwAAAA==.Bruwon:BAECLgAFFH8qAAIGAAgJqyF4AAB8AghoDAAABwBcAGkMAAAHAGIAawwAAAcAWgBqDAAABgBIAGwMAAAFAGIAbQwAAAEATwDqDAAACABeAG4MAAABADIABgAICasheAAAfAIIaAwAAAcAXABpDAAABwBiAGsMAAAHAFoAagwAAAYASABsDAAABQBiAG0MAAABAE8A6gwAAAgAXgBuDAAAAQAyAC4ABAp/IQACBgAJCUAhxwQAPgMABgAJCUAhxwQAPgMAAAA=.',
Ca='Captinsaneo:BAEALgAECggJCAAAAA==.',
Ch='Charzie:BAEALgAECgEJAQABLgAFFAgJKgAGAKshAA==.',
Ci='Ciprox:BAEBLgAECn8VAAIHAAgJqB7dCABpAghoDAAAAwBVAGkMAAADAEcAawwAAAMAXABqDAAAAwBQAGwMAAADAGAAbQwAAAIAOADqDAAAAwBcAG4MAAABADcABwAICage3QgAaQIIaAwAAAMAVQBpDAAAAwBHAGsMAAADAFwAagwAAAMAUABsDAAAAwBgAG0MAAACADgA6gwAAAMAXABuDAAAAQA3AAEuAAUUBwkVAAgAfhkA.',
Cy='Cyprexdh:BAECLgAFFH8VAAMIAAcJfhniBgDtAQdoDAAABgBjAGkMAAAEAFoAawwAAAMAQQBqDAAAAwA9AGwMAAABAB0AbQwAAAEADwDqDAAAAwBaAAgABwnPEuIGAO0BB2gMAAADADEAaQwAAAMAWgBrDAAAAgA/AGoMAAADAD0AbAwAAAEAHQBtDAAAAQAPAOoMAAACACcACQAECX8Z7wEAewEEaAwAAAMAYwBpDAAAAQAFAGsMAAABAEEA6gwAAAEAWgAuAAQKfxoABAkACAnwJTkDAFIDAAkACAlbJTkDAFIDAAgAAwmyJJl7ADUBAAoAAQkAALYtACkAAAAA.',
Da='Danilynn:BAEALgADCggJFAABLgAECgcJHQALAIQDAA==.Danitsia:BAEBLgAECn8dAAMLAAcJhAMQNQDVAAdoDAAABQAIAGkMAAAFAAsAawwAAAUACABqDAAABAAUAGwMAAAEAAsAbQwAAAEABADqDAAABQAIAAsABwmEAxA1ANUAB2gMAAAFAAgAaQwAAAUACwBrDAAABAAIAGoMAAAEABQAbAwAAAMACwBtDAAAAQAEAOoMAAAEAAgADAADCeMAdVEARgADawwAAAEAAgBsDAAAAQADAOoMAAABAAAAAAA=.',
De='Delabrand:BAEALgAECgYJCQABLgAFFAcJGwANAKwmAA==.Delajuv:BAEBLgAFFH8FAAIOAAUJoAwtBwDdAAVoDAAAAQAvAGkMAAABABcAawwAAAEAIQBqDAAAAQAJAOoMAAABABgADgAFCaAMLQcA3QAFaAwAAAEALwBpDAAAAQAXAGsMAAABACEAagwAAAEACQDqDAAAAQAYAAEuAAUUBwkbAA0ArCYA.Delarage:BAECLgAFFH8bAAINAAcJrCZFAAClAgdoDAAABgBjAGkMAAAEAGMAawwAAAQAYwBqDAAABABiAGwMAAACAGQAbQwAAAEAXwDqDAAABgBjAA0ABwmsJkUAAKUCB2gMAAAGAGMAaQwAAAQAYwBrDAAABABjAGoMAAAEAGIAbAwAAAIAZABtDAAAAQBfAOoMAAAGAGMALgAECn8hAAINAAkJ/ib9AACQAwANAAkJ/ib9AACQAwAAAA==.Deleerious:BAECLgAFFH8SAAIPAAUJzCXwBQCOAQVoDAAABQBiAGkMAAAFAGEAawwAAAIAXgBqDAAAAQBdAOoMAAAFAGAADwAFCcwl8AUAjgEFaAwAAAUAYgBpDAAABQBhAGsMAAACAF4AagwAAAEAXQDqDAAABQBgAC4ABAp/IAACDwAICR0kogUAOAMADwAICR0kogUAOAMAAAA=.',
Do='Doriel:BAEALgAECgMJBAABLgAFFAQJDwAQAOUUAA==.',
Du='Dubsstree:BAEALgADCgYJBgABLgAFFAcJGgARANQZAA==.',
Dw='Dwarfwarloc:BAEALgAECgYJEQAAAA==.',
Eg='Egirlarmpits:BAEALgAFFAIJAgABLgAFFAQJCwAHAKAQAA==.',
Em='Emellious:BAECLgAFFH8VAAIPAAUJwxuZBwBrAQVoDAAABgBPAGkMAAAFAFsAawwAAAMAGgBqDAAAAgA6AOoMAAAFAFcADwAFCcMbmQcAawEFaAwAAAYATwBpDAAABQBbAGsMAAADABoAagwAAAIAOgDqDAAABQBXAC4ABAp/HAADDwAICQQhoQwAzgIADwAICQQhoQwAzgIAEgABCZALgh8ANQAAAAA=.',
Fr='Freddyfletch:BAEALgADCgUJBQAAAA==.',
Fu='Funkaroused:BAEBLgAECn8vAAITAAgJmRpxEQD+AQhoDAAABwBbAGkMAAAHAEcAawwAAAcAQABqDAAABgBFAGwMAAAHAEsAbQwAAAEAMADqDAAACABKAG4MAAAEADIAEwAICZkacREA/gEIaAwAAAcAWwBpDAAABwBHAGsMAAAHAEAAagwAAAYARQBsDAAABwBLAG0MAAABADAA6gwAAAgASgBuDAAABAAyAAAA.',
Gi='Giantmagic:BAEBLgAECn8bAAIQAAcJQh19XQAiAgdoDAAABABOAGkMAAAEAFIAawwAAAQAWwBqDAAABgBOAGwMAAACAD4AbQwAAAIAQgDqDAAABQBEABAABwlCHX1dACICB2gMAAAEAE4AaQwAAAQAUgBrDAAABABbAGoMAAAGAE4AbAwAAAIAPgBtDAAAAgBCAOoMAAAFAEQAAAA=.',
Gj='Gjlo:BAECLgAFFH8GAAMTAAMJEg/dJgCeAANoDAAABABGAGkMAAABAAAA6gwAAAEALAATAAIJaxbdJgCeAAJoDAAAAgBGAOoMAAABACwADQACCaQDKA4AZQACaAwAAAIAEQBpDAAAAQAAAC4ABAp/PgADEwAJCX8XLA4AJQIAEwAJCX8XLA4AJQIADQAHCXcPNhwA5wAAAAA=.',
Gl='Gluzzaie:BAEBLgAECn8UAAMRAAgJMxuVXgCtAQhoDAAAAwA7AGkMAAADAE0AawwAAAMANwBqDAAAAwA0AGwMAAACAFQAbQwAAAEANgDqDAAAAwBIAG4MAAACAFIAEQAHCQ0blV4ArQEHaAwAAAMAOwBpDAAAAwBNAGsMAAABADQAbAwAAAIAVABtDAAAAQA2AOoMAAADAEgAbgwAAAIAUgAUAAIJmBW4TACHAAJrDAAAAgA3AGoMAAADADQAAAA=.',
Gr='Gronknose:BAEBLgAECn8WAAIVAAcJ0iHgAQCcAgdoDAAAAwBVAGkMAAAEAFwAawwAAAQATABqDAAAAwBeAGwMAAACAFcAbQwAAAEAUgDqDAAABQBfABUABwnSIeABAJwCB2gMAAADAFUAaQwAAAQAXABrDAAABABMAGoMAAADAF4AbAwAAAIAVwBtDAAAAQBSAOoMAAAFAF8AAS4ABAoJCTEABgC5JAA=.',
Ha='Hakdh:BAEALgAECgYJBgABLgAFFAYJFQAWAPENAA==.Hakdk:BAEBLgAFFH8VAAIWAAYJ8Q3+BQA7AQZoDAAAAwAiAGkMAAADACMAawwAAAMAJwBqDAAABgAaAG0MAAABAAMA6gwAAAUAQAAWAAYJ8Q3+BQA7AQZoDAAAAwAiAGkMAAADACMAawwAAAMAJwBqDAAABgAaAG0MAAABAAMA6gwAAAUAQAAAAA==.Hakgek:BAEBLgAFFH8JAAIOAAQJRA7SBAAcAQRoDAAAAgAlAGkMAAACACgAawwAAAIAJgBsDAAAAwAdAA4ABAlEDtIEABwBBGgMAAACACUAaQwAAAIAKABrDAAAAgAmAGwMAAADAB0AAS4ABRQGCRUAFgDxDQA=.Hakmonk:BAEBLgAFFH8GAAIGAAQJSxHODQAWAQRoDAAAAgAmAGkMAAACAEsAawwAAAEAEQDqDAAAAQAuAAYABAlLEc4NABYBBGgMAAACACYAaQwAAAIASwBrDAAAAQARAOoMAAABAC4AAS4ABRQGCRUAFgDxDQA=.Haksham:BAEALgAECgcJBAABLgAFFAYJFQAWAPENAA==.Hakwar:BAEALgAECgUJBQABLgAFFAYJFQAWAPENAA==.Halosbrew:BAECLgAFFH8JAAIGAAQJqhnoDwADAQRoDAAAAgBLAGkMAAADAFYAawwAAAEAGgDqDAAAAwBKAAYABAmqGegPAAMBBGgMAAACAEsAaQwAAAMAVgBrDAAAAQAaAOoMAAADAEoALgAECn8UAAMGAAgJRx4TFQBjAgAGAAcJzSETFQBjAgAXAAUJaRO9PAAoAQAAAA==.Halosdk:BAEBLgAFFH8LAAIWAAQJ0xaXDgAPAQRoDAAAAwBEAGkMAAACAEsAawwAAAIAGwDqDAAABAA+ABYABAnTFpcOAA8BBGgMAAADAEQAaQwAAAIASwBrDAAAAgAbAOoMAAAEAD4AAS4ABRQECQkABgCqGQA=.Halosmage:BAEALgAECggJBwABLgAFFAQJCQAGAKoZAA==.',
He='Heavensfeel:BAEBLgAECn80AAQCAAkJFB8MCAC7AgloDAAACABVAGkMAAAHAD0AawwAAAcASwBqDAAABgBbAGwMAAAGAFYAbQwAAAQAUADqDAAACABVAG4MAAAEAEQAbwwAAAIAUQACAAkJFB8MCAC7AgloDAAABQBVAGkMAAAEAD0AawwAAAQASwBqDAAAAwBbAGwMAAAEAFYAbQwAAAMAUADqDAAABQBVAG4MAAACAEQAbwwAAAEAUQAEAAkJyhtjBQCwAgloDAAAAgBYAGkMAAADAF8AawwAAAMAXQBqDAAAAwBUAGwMAAACAFUAbQwAAAEAKADqDAAAAgApAG4MAAACAF8AbwwAAAEAHAAFAAIJjgsTEwBtAAJoDAAAAQAbAOoMAAABAB8AAS4ABRQECQkABgCqGQA=.',
In='Inaríus:BAEALgAECgYJDAABLgAECgcJGwAQAEIdAA==.Initiative:BAEBLgAECn8XAAMYAAgJhB0qCwBaAghoDAAAAwBXAGkMAAADAFwAawwAAAQAXwBqDAAAAwA8AGwMAAAEADMAbQwAAAEASQDqDAAAAwBRAG4MAAACAD0AGAAICYQdKgsAWgIIaAwAAAIAVwBpDAAAAgBcAGsMAAADAF8AagwAAAIAPABsDAAAAQAzAG0MAAABAEkA6gwAAAIAUQBuDAAAAQA9ABcABwmnH1saAA0CB2gMAAABAFkAaQwAAAEAXQBrDAAAAQBeAGoMAAABAFUAbAwAAAMAYADqDAAAAQBQAG4MAAABACAAAAA=.',
It='Itsgrippy:BAEALgAECgYJDgAAAA==.',
Je='Jev:BAEBLgAECn8hAAILAAkJiCKhAgCAAwloDAAABABeAGkMAAAEAF4AawwAAAQAXgBqDAAABABYAGwMAAAEAFsAbQwAAAQAVQDqDAAAAwBVAG4MAAAFAEwAbwwAAAEAVAALAAkJiCKhAgCAAwloDAAABABeAGkMAAAEAF4AawwAAAQAXgBqDAAABABYAGwMAAAEAFsAbQwAAAQAVQDqDAAAAwBVAG4MAAAFAEwAbwwAAAEAVAABLgAFFAMJBQANAHAXAA==.',
Ke='Keeflan:BAECLgAFFH8LAAIHAAQJoBCBEwAmAQRoDAAAAwA8AGkMAAADABoAawwAAAIAMgDqDAAAAwAhAAcABAmgEIETACYBBGgMAAADADwAaQwAAAMAGgBrDAAAAgAyAOoMAAADACEALgAECn8ZAAMHAAgJIB+5KwC6AQAHAAYJ4B+5KwC6AQAZAAcJRg2tQAB+AQAAAA==.',
Ku='Kungfupander:BAEALgADCgMJAwABLgAECgcJGwAQAEIdAA==.',
Le='Lewinskibidi:BAEBLgAFFH8GAAIEAAQJVhTdEwBCAQRoDAAAAgBMAGkMAAACAEUA6gwAAAEAMgBuDAAAAQALAAQABAlWFN0TAEIBBGgMAAACAEwAaQwAAAIARQDqDAAAAQAyAG4MAAABAAsAAS4ABRQHCRsACwCuHgA=.',
Ma='Madtheaug:BAEBLgAECn8WAAMFAAgJkyAzEgC+AQhoDAAAAgBPAGkMAAACAEkAawwAAAIAVwBqDAAABABWAGwMAAADAFwAbQwAAAMAUADqDAAABABbAG4MAAACAE4ABQAHCbMYMxIAvgEHaAwAAAIATwBpDAAAAgBJAGsMAAACAFcAagwAAAIAOwBsDAAAAgARAG0MAAACAC8A6gwAAAIASQAEAAUJgSFyIAC9AQVqDAAAAgBWAGwMAAABAFwAbQwAAAEAUADqDAAAAgBbAG4MAAACAE4AAS4ABRQJCScAGgAhJgA=.Madthehunt:BAEALgAFFAEJAQABLgAFFAkJJwAaACEmAA==.Madthelock:BAECLgAFFH8nAAQaAAkJISYNAAA7AgloDAAABQBjAGkMAAAGAGMAawwAAAcAZABqDAAABgBYAGwMAAAEAGQAbQwAAAEAYgDqDAAACABhAG4MAAABAFoAbwwAAAEAXgAUAAcJiSY4AACWAgdoDAAAAQBjAGkMAAADAGMAawwAAAUAZABqDAAAAwBYAGwMAAACAGEAbQwAAAEAYgDqDAAAAwBhABEACAnAIuEAAFECCGgMAAADAF8AaQwAAAIAYwBrDAAAAQBiAGoMAAABAEcAbAwAAAEALgDqDAAABABhAG4MAAABAFoAbwwAAAEAXgAaAAYJEyYNAAA7AgZoDAAAAQBhAGkMAAABAGMAawwAAAEAXgBqDAAAAgBWAGwMAAABAGQA6gwAAAEAYAAuAAQKfyoABBEACQmxJsIAAH4DABEACQlNJsIAAH4DABoACAlmJkQAACcDABQABgkcJl0KABkCAAAA.Magølli:BAECLgAFFH8PAAIQAAQJ5RQyLwBVAQRoDAAABQA5AGkMAAAFAEMAawwAAAMAGgDqDAAAAgA9ABAABAnlFDIvAFUBBGgMAAAFADkAaQwAAAUAQwBrDAAAAwAaAOoMAAACAD0ALgAECn8lAAIQAAgJWR9NJgDZAgAQAAgJWR9NJgDZAgAAAA==.',
Me='Megachud:BAEALgAFFAEJAQABLgAFFAQJCwAHAKAQAA==.',
Mi='Minbä:BAEALgAECgYJEgABLgAFFAcJGgARANQZAA==.Minigun:BAEALgAECgcJCgAAAQ==.Minipala:BAECLgAFFH8LAAIBAAQJtBvVEgAwAQRoDAAABABPAGkMAAACADMAawwAAAIASwDqDAAAAwBNAAEABAm0G9USADABBGgMAAAEAE8AaQwAAAIAMwBrDAAAAgBLAOoMAAADAE0ALgAECn8dAAMBAAgJOCKCBgADAwABAAgJOCKCBgADAwAbAAUJ5w9EswAeAQABLgAFFAcJGgARANQZAA==.Miniss:BAECLgAFFH8aAAQRAAcJ1BneAwAIAgdoDAAABgBeAGkMAAAFAE8AawwAAAMAUgBqDAAABABXAGwMAAACABoAbQwAAAEADwDqDAAABQBhABEABwnUGd4DAAgCB2gMAAAGAF4AaQwAAAMATwBrDAAAAgBSAGoMAAAEAFcAbAwAAAIAGgBtDAAAAQAPAOoMAAAEAGEAFAACCYANTA0AowACaQwAAAIAHgBrDAAAAQAmABoAAQlyFzUKAFQAAeoMAAABADwALgAECn9BAAQaAAkJIyYgAABlAwAaAAkJNyUgAABlAwARAAkJ3yUzAgBQAwAUAAIJESBFQQCwAAAAAA==.',
Mo='Moosclemommy:BAECLgAFFH8SAAIGAAYJPCCOAwDVAQZoDAAABQBFAGkMAAADAFgAawwAAAMAWQBqDAAAAQAuAGwMAAABAE0A6gwAAAUAVwAGAAYJPCCOAwDVAQZoDAAABQBFAGkMAAADAFgAawwAAAMAWQBqDAAAAQAuAGwMAAABAE0A6gwAAAUAVwAuAAQKfyAAAgYACAkgJb4FACwDAAYACAkgJb4FACwDAAEuAAUUBwkPAAIAaQwA.',
My='Mythicalhobo:BAEALgADCgUJCAAAAA==.Mythmaker:BAEALgAECgUJDQABLgAECgcJGwAQAEIdAA==.',
Na='Nargrodamus:BAEBLgAECn8hAAIcAAgJMxgPKAD7AQhoDAAABQBGAGkMAAAGAFYAawwAAAQAQABqDAAABQA0AGwMAAADAEkAbQwAAAIAGADqDAAABQA+AG4MAAADADMAHAAICTMYDygA+wEIaAwAAAUARgBpDAAABgBWAGsMAAAEAEAAagwAAAUANABsDAAAAwBJAG0MAAACABgA6gwAAAUAPgBuDAAAAwAzAAAA.',
Ni='Nimueh:BAECLgAFFH8JAAIdAAUJCwlxCQBFAQVoDAAAAgAvAGkMAAABABwAawwAAAEABwBqDAAAAQATAGwMAAAEAA0AHQAFCQsJcQkARQEFaAwAAAIALwBpDAAAAQAcAGsMAAABAAcAagwAAAEAEwBsDAAABAANAC4ABAp/LQADHQAJCS8S6RQANgIAHQAJCS8S6RQANgIACwAHCeAPSx4AYwEAAAA=.Nindë:BAEBLgAFFH8JAAIeAAMJLQmrBgDsAANoDAAAAwAeAGkMAAADABwA6gwAAAMACwAeAAMJLQmrBgDsAANoDAAAAwAeAGkMAAADABwA6gwAAAMACwABLgAFFAYJFwAfAK0UAA==.Niniane:BAECLgAFFH8XAAMfAAYJrRSoGABFAQZoDAAABQAhAGkMAAAEAFEAawwAAAQAQQBqDAAAAwARAGwMAAABAAoA6gwAAAYASQAfAAUJxRioGABFAQVoDAAABAAhAGkMAAAEAFEAawwAAAIAQQBqDAAAAQAIAOoMAAAGAEkAIAAECQkEIhkAwwAEaAwAAAEACgBrDAAAAgAJAGoMAAACABEAbAwAAAEACgAuAAQKfx8AAx8ACAl0H2kQALYCAB8ABwnmImkQALYCACAABglSCrRWAO4AAAAA.',
No='Nordsense:BAEALgAECgEJAQAAAA==.Novebear:BAEBLgAFFH8HAAIOAAIJYRveCgCgAAJoDAAABABCAOoMAAADAEkADgACCWEb3goAoAACaAwAAAQAQgDqDAAAAwBJAAEuAAUUAwkMAA0AGCUA.Novelus:BAECLgAFFH8MAAINAAMJGCX3AwBHAQNoDAAABQBhAGkMAAADAF0A6gwAAAQAXQANAAMJGCX3AwBHAQNoDAAABQBhAGkMAAADAF0A6gwAAAQAXQAuAAQKfysAAg0ACQkAJgIBAC8DAA0ACQkAJgIBAC8DAAAA.',
Ol='Oldbronze:BAECLgAFFH8PAAINAAQJYhqPBwBIAQRoDAAABQBMAGkMAAAEAEoAawwAAAIAKQDqDAAABABOAA0ABAliGo8HAEgBBGgMAAAFAEwAaQwAAAQASgBrDAAAAgApAOoMAAAEAE4ALgAECn8wAAINAAgJTSKbAwCdAgANAAgJTSKbAwCdAgAAAA==.',
On='Onenjen:BAEBLgAECn8hAAISAAgJzQORDQD4AAhoDAAABgAPAGkMAAAGAAgAawwAAAYAEABqDAAABAANAGwMAAAEAAgAbQwAAAEABQDqDAAABQAMAG4MAAABAAIAEgAICc0DkQ0A+AAIaAwAAAYADwBpDAAABgAIAGsMAAAGABAAagwAAAQADQBsDAAABAAIAG0MAAABAAUA6gwAAAUADABuDAAAAQACAAAA.',
['Oñ']='Oññayu:BAEALgAECgIJAgAAAA==.',
Pa='Parkercannon:BAECLgAFFH8bAAILAAcJrh4GAQA6AgdoDAAABQBeAGkMAAAEAFwAawwAAAUAUgBqDAAABQBJAGwMAAADAF4AbQwAAAIALgDqDAAAAwA8AAsABwmuHgYBADoCB2gMAAAFAF4AaQwAAAQAXABrDAAABQBSAGoMAAAFAEkAbAwAAAMAXgBtDAAAAgAuAOoMAAADADwALgAECn8mAAILAAkJ8iPuAADQAwALAAkJ8iPuAADQAwAAAA==.Patrennessy:BAEBLgAECn8xAAIGAAkJuSTnAABMAwloDAAABgBiAGkMAAAGAGAAawwAAAYAXgBqDAAABQBdAGwMAAAGAGAAbQwAAAUAWgDqDAAABwBdAG4MAAAFAF0AbwwAAAMAVwAGAAkJuSTnAABMAwloDAAABgBiAGkMAAAGAGAAawwAAAYAXgBqDAAABQBdAGwMAAAGAGAAbQwAAAUAWgDqDAAABwBdAG4MAAAFAF0AbwwAAAMAVwAAAA==.',
Ra='Ramsama:BAEALgAECgkJCAAAAA==.Ramsdh:BAEALgAECggJCQABLgAFFAYJFAAPAGIeAA==.Ramsx:BAECLgAFFH8UAAMPAAYJYh51AwDEAQZoDAAABQBaAGkMAAAEAFYAawwAAAMAUgBqDAAAAQAYAGwMAAABACkA6gwAAAYAVwAPAAUJ4yF1AwDEAQVoDAAABQBaAGkMAAACAFYAawwAAAIAUgBqDAAAAQAYAOoMAAAFAFcAEgAECUsSaAIAFgEEaQwAAAIAOgBrDAAAAQA6AGwMAAABACkA6gwAAAEAHAAuAAQKfxYAAw8ABglEJtwUAGsCAA8ABglEJtwUAGsCABIAAQk4JKAXAFwAAAAA.Rarelinelk:BAEALgAECgIJAgABLgAFFAYJFQAcACMjAA==.',
Re='Recursively:BAECLgAFFH8bAAQRAAgJ5BOrAwDnAQhoDAAABQBhAGkMAAAEAEAAawwAAAUAQgBqDAAAAwAlAGwMAAABABUAbQwAAAEACADqDAAABwBFAG4MAAABABsAEQAHCSEWqwMA5wEHaAwAAAUAYQBpDAAAAwBAAGsMAAADADoAagwAAAIADgBsDAAAAQAVAOoMAAAFAEUAbgwAAAEAGwAUAAQJvg/YAwBaAQRpDAAAAQAsAGsMAAACAEIAbQwAAAEACADqDAAAAgApABoAAQkAAHYFAFcAAWoMAAABACUALgAECn8lAAQRAAkJaSP0DAASAwARAAkJOiP0DAASAwAUAAYJCiKECAA6AgAaAAEJAADYIgBmAAAAAA==.Redxr:BAEALgAECgYJDQABLgAFFAYJDAAMAPoUAA==.',
Sh='Sharrq:BAECLgAFFH8OAAIhAAQJaBmLAABiAQRoDAAABQBJAGkMAAAEACoAawwAAAIASADqDAAAAwBHACEABAloGYsAAGIBBGgMAAAFAEkAaQwAAAQAKgBrDAAAAgBIAOoMAAADAEcALgAECn8gAAMhAAgJxCCoAAASAwAhAAgJxCCoAAASAwAiAAEJKwlZHgA0AAAAAA==.',
Si='Sivvychuckle:BAEALgAECgIJAwABLgAECgcJCwADAAAAAA==.Sivvygrows:BAEALgAECgcJBwABLgAECgcJCwADAAAAAA==.Sivvyrawr:BAEALgAECgcJCwAAAA==.',
Sl='Slammybreath:BAECLgAFFH8JAAMEAAQJ4xPAFQA3AQRoDAAAAwArAGkMAAADAEwAawwAAAIAHADqDAAAAQA3AAQABAnjE8AVADcBBGgMAAACACsAaQwAAAMATABrDAAAAgAcAOoMAAABADcABQABCTYBHgwAQwABaAwAAAEAAwAuAAQKfx0AAwQACAloFCQxAD4BAAQABgnOEiQxAD4BAAUACAnaE/ssALQAAAEuAAUUBwkPAAIAaQwA.',
Sp='Spicyhotwing:BAECLgAFFH8PAAMCAAcJaQyKAwDOAQdoDAAAAgAKAGkMAAACAAsAawwAAAIAGwBqDAAAAwAhAGwMAAABAAUAbQwAAAEAWQDqDAAABAAqAAIABgmhCIoDAM4BBmgMAAABAAoAaQwAAAEACwBrDAAAAQAbAGoMAAADACEAbAwAAAEABQDqDAAABAAqAAQABAlfFR8RAFYBBGgMAAABAD0AaQwAAAEAUgBrDAAAAQBGAG0MAAABAAQALgAECn8UAAMCAAgJ6xJAFAACAgACAAgJ6xJAFAACAgAFAAEJfR5+OABVAAAAAA==.',
Ta='Tauntinitis:BAEALgADCgMJAwABLgAFFAMJBgATABIPAA==.',
Te='Tendeyaloran:BAEALgAECgQJCgAAAA==.',
Th='Thanala:BAECLgAFFH8aAAIBAAYJsiLoAwAJAgZoDAAABgBSAGkMAAAGAGEAawwAAAQAWABqDAAAAwBLAGwMAAABAGEA6gwAAAYAWwABAAYJsiLoAwAJAgZoDAAABgBSAGkMAAAGAGEAawwAAAQAWABqDAAAAwBLAGwMAAABAGEA6gwAAAYAWwAuAAQKfxwAAgEACAlhHnwUAG4CAAEACAlhHnwUAG4CAAAA.',
Tr='Trintu:BAEALgAECgkJAwABLgAFFAYJFQAWAPENAA==.',
Yo='Yoktuah:BAEBLgAFFH8FAAMBAAQJ6gPGDQD9AARoDAAAAgAAAGkMAAABABwAawwAAAEACgDqDAAAAQAAAAEABAnqA8YNAP0ABGgMAAABAAAAaQwAAAEAHABrDAAAAQAKAOoMAAABAAAAGwABCRgRnTEAUgABaAwAAAEAKwABLgAFFAQJCwAHAKAQAA==.',
Yu='Yungdh:BAEBLgAECn8UAAIIAAcJmxuiIgDWAQdoDAAAAwA8AGkMAAADAEwAawwAAAQAPwBqDAAAAwBOAGwMAAADAEkAbQwAAAEAPADqDAAAAwBYAAgABwmbG6IiANYBB2gMAAADADwAaQwAAAMATABrDAAABAA/AGoMAAADAE4AbAwAAAMASQBtDAAAAQA8AOoMAAADAFgAAS4ABRQGCR8AIwB0JgA=.Yungdrood:BAECLgAFFH8fAAIjAAYJdCaeAQAoAgZoDAAABgBjAGkMAAAHAGMAawwAAAYAYwBqDAAABQBhAGwMAAACAF4A6gwAAAUAYgAjAAYJdCaeAQAoAgZoDAAABgBjAGkMAAAHAGMAawwAAAYAYwBqDAAABQBhAGwMAAACAF4A6gwAAAUAYgAuAAQKfy8AAiMACQnTJkECAJ8DACMACQnTJkECAJ8DAAAA.Yungmonk:BAEALgAECgQJBAABLgAFFAYJHwAjAHQmAA==.Yungwizard:BAEBLgAECn8WAAIQAAYJ2iXfOQCOAgZoDAAABABfAGkMAAAEAGIAawwAAAQAXwBqDAAAAwBhAGwMAAAEAGEA6gwAAAMAYQAQAAYJ2iXfOQCOAgZoDAAABABfAGkMAAAEAGIAawwAAAQAXwBqDAAAAwBhAGwMAAAEAGEA6gwAAAMAYQABLgAFFAYJHwAjAHQmAA==.',
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
