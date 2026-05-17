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

local lookup = {'Paladin-Holy','Evoker-Preservation','Unknown-Unknown','Evoker-Augmentation','Evoker-Devastation','Warlock-Destruction','Warlock-Demonology','Monk-Brewmaster','Shaman-Elemental','DemonHunter-Devourer','DemonHunter-Havoc','DemonHunter-Vengeance','Priest-Shadow','Priest-Discipline','Warrior-Protection','Druid-Guardian','Rogue-Subtlety','Mage-Frost','Rogue-Assassination','Warrior-Fury','Rogue-Outlaw','DeathKnight-Blood','Monk-Windwalker','Monk-Mistweaver','Shaman-Restoration','Warlock-Affliction','Paladin-Retribution','DeathKnight-Unholy','Priest-Holy','Druid-Feral','Hunter-BeastMastery','Hunter-Marksmanship','Mage-Fire','Mage-Arcane','Druid-Balance',}
local provider = {region='US',realm='BleedingHollow',name='US',type='subscribers',zone=46,date='2026-05-16',data={Ad='Addex:BAEBLgAFFH8NAAIBAAYJjxPbBwDPAQZoDAAAAwA0AGkMAAACAD0AawwAAAIADQBqDAAAAgAiAGwMAAABACsA6gwAAAMAXgABAAYJjxPbBwDPAQZoDAAAAwA0AGkMAAACAD0AawwAAAIADQBqDAAAAgAiAGwMAAABACsA6gwAAAMAXgABLgAFFAgJKQACAAwdAA==.',
Ae='Aeveracy:BAEALgADCgMJAwABLgAECgIJAgADAAAAAA==.',
Am='Ambient:BAECLgAFFH8pAAMCAAgJDB3PAABkAghoDAAABwBhAGkMAAAHAEUAawwAAAcAUABqDAAABgBLAGwMAAAFAFQAbQwAAAEAJwDqDAAABwBLAG4MAAABAEkAAgAICQwdzwAAZAIIaAwAAAUAYQBpDAAABwBFAGsMAAAHAFAAagwAAAYASwBsDAAABQBUAG0MAAABACcA6gwAAAcASwBuDAAAAQBJAAQAAQk/F34gAFAAAWgMAAACADsALgAECn8dAAMCAAkJcyO+BAADAwACAAgJKyO+BAADAwAFAAEJiBPWOgBEAAAAAA==.',
Br='Briéè:BAEBLgAECn8UAAMGAAYJRxPDFwCtAAZoDAAABQBLAGkMAAAEADMAawwAAAQALwBqDAAAAwAuAGwMAAACADAA6gwAAAIAFgAHAAUJNw8jjQDiAAVoDAAAAwAvAGkMAAADACQAagwAAAEAKgBsDAAAAgAwAOoMAAACABYABgAECc4WwxcArQAEaAwAAAIASwBpDAAAAQAzAGsMAAAEAC8AagwAAAIALgAAAA==.Bruwon:BAECLgAFFH8qAAIIAAgJpiGvAAB0AghoDAAABwBcAGkMAAAHAGIAawwAAAcAWgBqDAAABgBIAGwMAAAFAGIAbQwAAAEATwDqDAAACABeAG4MAAABADIACAAICaYhrwAAdAIIaAwAAAcAXABpDAAABwBiAGsMAAAHAFoAagwAAAYASABsDAAABQBiAG0MAAABAE8A6gwAAAgAXgBuDAAAAQAyAC4ABAp/IQACCAAJCUAhxwQAPgMACAAJCUAhxwQAPgMAAAA=.',
Ca='Captinsaneo:BAEALgAECggJCAAAAA==.',
Ch='Charzie:BAEALgAECgUJBgABLgAFFAgJKgAIAKYhAA==.',
Ci='Ciprox:BAEBLgAECn8VAAIJAAgJqB6VDQBEAghoDAAAAwBVAGkMAAADAEcAawwAAAMAXABqDAAAAwBQAGwMAAADAGAAbQwAAAIAOADqDAAAAwBcAG4MAAABADcACQAICagelQ0ARAIIaAwAAAMAVQBpDAAAAwBHAGsMAAADAFwAagwAAAMAUABsDAAAAwBgAG0MAAACADgA6gwAAAMAXABuDAAAAQA3AAEuAAUUBwkVAAoAfhkA.',
Cy='Cyprexdh:BAECLgAFFH8VAAMKAAcJfhnUCADqAQdoDAAABgBjAGkMAAAEAFoAawwAAAMAQQBqDAAAAwA9AGwMAAABAB0AbQwAAAEADwDqDAAAAwBaAAoABwnLEtQIAOoBB2gMAAADADEAaQwAAAMAWgBrDAAAAgA/AGoMAAADAD0AbAwAAAEAHQBtDAAAAQAPAOoMAAACACcACwAECX8Z7wEAewEEaAwAAAMAYwBpDAAAAQAFAGsMAAABAEEA6gwAAAEAWgAuAAQKfxoABAsACAnwJTkDAFIDAAsACAlbJTkDAFIDAAoAAwmyJJl7ADUBAAwAAQkAALYtACkAAAAA.',
Da='Danilynn:BAEALgADCggJFAABLgAECgcJHQANAIQDAA==.Danitsia:BAEBLgAECn8dAAMNAAcJhAN8PQDEAAdoDAAABQAIAGkMAAAFAAsAawwAAAUACABqDAAABAAUAGwMAAAEAAsAbQwAAAEABADqDAAABQAIAA0ABwmEA3w9AMQAB2gMAAAFAAgAaQwAAAUACwBrDAAABAAIAGoMAAAEABQAbAwAAAMACwBtDAAAAQAEAOoMAAAEAAgADgADCeMAdVEARgADawwAAAEAAgBsDAAAAQADAOoMAAABAAAAAAA=.',
De='Delabrand:BAEALgAECgYJCQABLgAFFAgJHgAPAIkmAA==.Delajuv:BAEBLgAFFH8FAAIQAAUJ1AzACADdAAVoDAAAAQAwAGkMAAABABcAawwAAAEAIgBqDAAAAQAJAOoMAAABABkAEAAFCdQMwAgA3QAFaAwAAAEAMABpDAAAAQAXAGsMAAABACIAagwAAAEACQDqDAAAAQAZAAEuAAUUCAkeAA8AiSYA.Delarage:BAECLgAFFH8eAAIPAAgJiSYdAAAWAwhoDAAABgBjAGkMAAAEAGMAawwAAAQAYwBqDAAABABiAGwMAAADAGQAbQwAAAIAYQDqDAAABgBjAG4MAAABAF4ADwAICYkmHQAAFgMIaAwAAAYAYwBpDAAABABjAGsMAAAEAGMAagwAAAQAYgBsDAAAAwBkAG0MAAACAGEA6gwAAAYAYwBuDAAAAQBeAC4ABAp/IQACDwAJCf4m/QAAkAMADwAJCf4m/QAAkAMAAAA=.Deleerious:BAECLgAFFH8SAAIRAAUJzCXCCAB3AQVoDAAABQBiAGkMAAAFAGEAawwAAAIAXgBqDAAAAQBdAOoMAAAFAGAAEQAFCcwlwggAdwEFaAwAAAUAYgBpDAAABQBhAGsMAAACAF4AagwAAAEAXQDqDAAABQBgAC4ABAp/KgACEQAICR0kogUAOAMAEQAICR0kogUAOAMAAAA=.',
Do='Doriel:BAEALgAECgMJBAABLgAFFAQJDwASAOUUAA==.',
Du='Dubsstree:BAEALgADCgYJBgABLgAFFAcJHQAHANQZAA==.',
Dw='Dwarfwarloc:BAEBLgAECn8ZAAIHAAgJMSJqGwBEAghoDAAABABgAGkMAAAEAFMAawwAAAQAWgBqDAAABABgAGwMAAADAGEAbQwAAAEARADqDAAABABfAG8MAAABAE8ABwAICTEiahsARAIIaAwAAAQAYABpDAAABABTAGsMAAAEAFoAagwAAAQAYABsDAAAAwBhAG0MAAABAEQA6gwAAAQAXwBvDAAAAQBPAAAA.',
Eg='Egirlarmpits:BAEALgAFFAIJAgABLgAFFAQJCwAJAKAQAA==.',
Em='Emellious:BAECLgAFFH8VAAIRAAUJwxuZBwBrAQVoDAAABgBPAGkMAAAFAFsAawwAAAMAGgBqDAAAAgA6AOoMAAAFAFcAEQAFCcMbmQcAawEFaAwAAAYATwBpDAAABQBbAGsMAAADABoAagwAAAIAOgDqDAAABQBXAC4ABAp/HAADEQAICQQhoQwAzgIAEQAICQQhoQwAzgIAEwABCZALgh8ANQAAAAA=.',
Fr='Freddyfletch:BAEALgADCgUJBQAAAA==.',
Fu='Funkaroused:BAEBLgAECn8vAAIUAAgJmRowGADfAQhoDAAABwBbAGkMAAAHAEcAawwAAAcAQABqDAAABgBFAGwMAAAHAEsAbQwAAAEAMADqDAAACABKAG4MAAAEADIAFAAICZkaMBgA3wEIaAwAAAcAWwBpDAAABwBHAGsMAAAHAEAAagwAAAYARQBsDAAABwBLAG0MAAABADAA6gwAAAgASgBuDAAABAAyAAAA.',
Gi='Giantmagic:BAEBLgAECn8bAAISAAcJQh19XQAiAgdoDAAABABOAGkMAAAEAFIAawwAAAQAWwBqDAAABgBOAGwMAAACAD4AbQwAAAIAQgDqDAAABQBEABIABwlCHX1dACICB2gMAAAEAE4AaQwAAAQAUgBrDAAABABbAGoMAAAGAE4AbAwAAAIAPgBtDAAAAgBCAOoMAAAFAEQAAS4ABAoHCRMAAwAAAAA=.',
Gj='Gjlo:BAECLgAFFH8GAAMUAAMJEg+iKgCZAANoDAAABABGAGkMAAABAAAA6gwAAAEALAAUAAIJaxaiKgCZAAJoDAAAAgBGAOoMAAABACwADwACCaQDKA4AZQACaAwAAAIAEQBpDAAAAQAAAC4ABAp/RQADFAAJCSwZzg8AMgIAFAAJCSwZzg8AMgIADwAHCXcPGCEA3AAAAAA=.',
Gl='Gluzzaie:BAEBLgAECn8UAAMHAAgJMxuVXgCtAQhoDAAAAwA7AGkMAAADAE0AawwAAAMANwBqDAAAAwA0AGwMAAACAFQAbQwAAAEANgDqDAAAAwBIAG4MAAACAFIABwAHCQ0blV4ArQEHaAwAAAMAOwBpDAAAAwBNAGsMAAABADQAbAwAAAIAVABtDAAAAQA2AOoMAAADAEgAbgwAAAIAUgAGAAIJmBW4TACHAAJrDAAAAgA3AGoMAAADADQAAAA=.',
Gr='Gronknose:BAEBLgAECn8WAAIVAAcJ0iHgAQCcAgdoDAAAAwBVAGkMAAAEAFwAawwAAAQATABqDAAAAwBeAGwMAAACAFcAbQwAAAEAUgDqDAAABQBfABUABwnSIeABAJwCB2gMAAADAFUAaQwAAAQAXABrDAAABABMAGoMAAADAF4AbAwAAAIAVwBtDAAAAQBSAOoMAAAFAF8AAS4ABAoJCTEACACxJAA=.',
Ha='Hakdh:BAEALgAECgYJBgABLgAFFAYJFQAWAPENAA==.Hakdk:BAECLgAFFH8VAAIWAAYJ8Q3+BQA7AQZoDAAAAwAiAGkMAAADACMAawwAAAMAJwBqDAAABgAaAG0MAAABAAMA6gwAAAUAQAAWAAYJ8Q3+BQA7AQZoDAAAAwAiAGkMAAADACMAawwAAAMAJwBqDAAABgAaAG0MAAABAAMA6gwAAAUAQAAuAAQKfxQAAhYACAkkHtMKAGoCABYACAkkHtMKAGoCAAAA.Hakgek:BAEBLgAFFH8KAAIQAAUJFAyoAwBbAQVoDAAAAgAlAGkMAAACACgAawwAAAIAJgBsDAAAAwAdAG4MAAABAAgAEAAFCRQMqAMAWwEFaAwAAAIAJQBpDAAAAgAoAGsMAAACACYAbAwAAAMAHQBuDAAAAQAIAAEuAAUUBgkVABYA8Q0A.Hakmonk:BAEBLgAFFH8GAAIIAAQJSxHODQAWAQRoDAAAAgAmAGkMAAACAEsAawwAAAEAEQDqDAAAAQAuAAgABAlLEc4NABYBBGgMAAACACYAaQwAAAIASwBrDAAAAQARAOoMAAABAC4AAS4ABRQGCRUAFgDxDQA=.Haksham:BAEALgAECgkJDQABLgAFFAYJFQAWAPENAA==.Hakwar:BAEALgAECgUJBQABLgAFFAYJFQAWAPENAA==.Halosbrew:BAECLgAFFH8JAAIIAAQJqhnoDwADAQRoDAAAAgBLAGkMAAADAFYAawwAAAEAGgDqDAAAAwBKAAgABAmqGegPAAMBBGgMAAACAEsAaQwAAAMAVgBrDAAAAQAaAOoMAAADAEoALgAECn8UAAMIAAgJRx4TFQBjAgAIAAcJzSETFQBjAgAXAAUJaRO9PAAoAQAAAA==.Halosdk:BAEBLgAFFH8LAAIWAAQJ0xbxEAAFAQRoDAAAAwBEAGkMAAACAEsAawwAAAIAGwDqDAAABAA+ABYABAnTFvEQAAUBBGgMAAADAEQAaQwAAAIASwBrDAAAAgAbAOoMAAAEAD4AAS4ABRQECQkACACqGQA=.Halosmage:BAEALgAECggJBwABLgAFFAQJCQAIAKoZAA==.',
He='Heavensfeel:BAEBLgAECn80AAQCAAkJFB8MCAC7AgloDAAACABVAGkMAAAHAD0AawwAAAcASwBqDAAABgBbAGwMAAAGAFYAbQwAAAQAUADqDAAACABVAG4MAAAEAEQAbwwAAAIAUQACAAkJFB8MCAC7AgloDAAABQBVAGkMAAAEAD0AawwAAAQASwBqDAAAAwBbAGwMAAAEAFYAbQwAAAMAUADqDAAABQBVAG4MAAACAEQAbwwAAAEAUQAEAAkJyBsSCQCGAgloDAAAAgBYAGkMAAADAF8AawwAAAMAXQBqDAAAAwBUAGwMAAACAFUAbQwAAAEAKADqDAAAAgApAG4MAAACAF8AbwwAAAEAHAAFAAIJjgtUFQBtAAJoDAAAAQAbAOoMAAABAB8AAS4ABRQECQkACACqGQA=.',
In='Inaríus:BAEALgAECgcJEwAAAA==.Initiative:BAEBLgAECn8aAAMYAAgJcB4FCgCXAghoDAAAAwBXAGkMAAADAFwAawwAAAQAXwBqDAAAAwA8AGwMAAAFAEYAbQwAAAIASQDqDAAABABRAG4MAAACAD0AGAAICXAeBQoAlwIIaAwAAAIAVwBpDAAAAgBcAGsMAAADAF8AagwAAAIAPABsDAAAAgBGAG0MAAACAEkA6gwAAAIAUQBuDAAAAQA9ABcABwmnH1saAA0CB2gMAAABAFkAaQwAAAEAXQBrDAAAAQBeAGoMAAABAFUAbAwAAAMAYADqDAAAAgBQAG4MAAABACAAAAA=.',
It='Itsgrippy:BAEALgAECgYJDgAAAA==.',
Je='Jev:BAEBLgAECn8hAAINAAkJiCKhAgCAAwloDAAABABeAGkMAAAEAF4AawwAAAQAXgBqDAAABABYAGwMAAAEAFsAbQwAAAQAVQDqDAAAAwBVAG4MAAAFAEwAbwwAAAEAVAANAAkJiCKhAgCAAwloDAAABABeAGkMAAAEAF4AawwAAAQAXgBqDAAABABYAGwMAAAEAFsAbQwAAAQAVQDqDAAAAwBVAG4MAAAFAEwAbwwAAAEAVAAAAA==.',
Ke='Keeflan:BAECLgAFFH8LAAIJAAQJoBC7FQAfAQRoDAAAAwA8AGkMAAADABoAawwAAAIAMgDqDAAAAwAhAAkABAmgELsVAB8BBGgMAAADADwAaQwAAAMAGgBrDAAAAgAyAOoMAAADACEALgAECn8cAAMJAAgJcR+5KwC6AQAJAAgJcR+5KwC6AQAZAAcJRg2tQAB+AQAAAA==.',
Ku='Kungfupander:BAEALgADCgMJAwABLgAECgcJEwADAAAAAA==.',
Le='Lewinskibidi:BAEBLgAFFH8HAAIEAAUJ3BSoDQCKAQVoDAAAAgBMAGkMAAACAEUAawwAAAEAOgDqDAAAAQAyAG4MAAABAAsABAAFCdwUqA0AigEFaAwAAAIATABpDAAAAgBFAGsMAAABADoA6gwAAAEAMgBuDAAAAQALAAEuAAUUBwkcAA0Arh4A.',
Ma='Madtheaug:BAEBLgAECn8WAAMFAAgJkyAzEgC+AQhoDAAAAgBPAGkMAAACAEkAawwAAAIAVwBqDAAABABWAGwMAAADAFwAbQwAAAMAUADqDAAABABbAG4MAAACAE4ABQAHCbMYMxIAvgEHaAwAAAIATwBpDAAAAgBJAGsMAAACAFcAagwAAAIAOwBsDAAAAgARAG0MAAACAC8A6gwAAAIASQAEAAUJgSFyIAC9AQVqDAAAAgBWAGwMAAABAFwAbQwAAAEAUADqDAAAAgBbAG4MAAACAE4AAS4ABRQJCScAGgAhJgA=.Madthehunt:BAEALgAFFAEJAQABLgAFFAkJJwAaACEmAA==.Madthelock:BAECLgAFFH8nAAQaAAkJISYXAAAuAgloDAAABQBjAGkMAAAGAGMAawwAAAcAZABqDAAABgBYAGwMAAAEAGQAbQwAAAEAYgDqDAAACABhAG4MAAABAFoAbwwAAAEAXgAGAAcJiSY4AACWAgdoDAAAAQBjAGkMAAADAGMAawwAAAUAZABqDAAAAwBYAGwMAAACAGEAbQwAAAEAYgDqDAAAAwBhAAcACAm/IuEAAFECCGgMAAADAF8AaQwAAAIAYwBrDAAAAQBiAGoMAAABAEcAbAwAAAEALgDqDAAABABhAG4MAAABAFoAbwwAAAEAXgAaAAYJEyYXAAAuAgZoDAAAAQBhAGkMAAABAGMAawwAAAEAXgBqDAAAAgBWAGwMAAABAGQA6gwAAAEAYAAuAAQKfyoABAcACQmxJrcBAGQDAAcACQlNJrcBAGQDABoACAlmJmMAABUDAAYABgkcJl0KABkCAAAA.Magolli:BAEALgAECgQJBAABLgAFFAQJDwASAOUUAA==.Magølli:BAECLgAFFH8PAAISAAQJ5RSFNQBNAQRoDAAABQA5AGkMAAAFAEMAawwAAAMAGgDqDAAAAgA9ABIABAnlFIU1AE0BBGgMAAAFADkAaQwAAAUAQwBrDAAAAwAaAOoMAAACAD0ALgAECn8tAAISAAgJ4CDBHgBpAgASAAgJ4CDBHgBpAgAAAA==.',
Me='Megachud:BAEALgAFFAEJAQABLgAFFAQJCwAJAKAQAA==.',
Mi='Minbä:BAEALgAECgYJEgABLgAFFAcJHQAHANQZAA==.Minigun:BAEALgAECgcJCgAAAQ==.Minipala:BAECLgAFFH8LAAIBAAQJtBtTFQAsAQRoDAAABABPAGkMAAACADMAawwAAAIASwDqDAAAAwBNAAEABAm0G1MVACwBBGgMAAAEAE8AaQwAAAIAMwBrDAAAAgBLAOoMAAADAE0ALgAECn8dAAMBAAgJOCKCBgADAwABAAgJOCKCBgADAwAbAAUJ5w9EswAeAQABLgAFFAcJHQAHANQZAA==.Miniss:BAECLgAFFH8dAAQHAAcJ1BnIBQD+AQdoDAAABwBeAGkMAAAGAE8AawwAAAQAUgBqDAAABABXAGwMAAACABoAbQwAAAEADwDqDAAABQBhAAcABwnUGcgFAP4BB2gMAAAHAF4AaQwAAAMATwBrDAAAAwBSAGoMAAAEAFcAbAwAAAIAGgBtDAAAAQAPAOoMAAAEAGEABgACCYANTA0AowACaQwAAAIAHgBrDAAAAQAmABoAAgl0D4YGAJoAAmkMAAABABMA6gwAAAEAPAAuAAQKf0EABBoACQkjJj4AADcDABoACQk3JT4AADcDAAcACQnfJX0DADUDAAYAAgkRIEVBALAAAAAA.',
Mo='Mobes:BAEBLgAECn8uAAIQAAkJ7hapCQDkAQloDAAABwBCAGkMAAAGAE8AawwAAAYAPwBqDAAABQAiAGwMAAAGADcAbQwAAAUAOwDqDAAABQBOAG4MAAAFACUAbwwAAAEAHQAQAAkJ7hapCQDkAQloDAAABwBCAGkMAAAGAE8AawwAAAYAPwBqDAAABQAiAGwMAAAGADcAbQwAAAUAOwDqDAAABQBOAG4MAAAFACUAbwwAAAEAHQAAAA==.Moosclemommy:BAECLgAFFH8VAAIIAAYJDiIoAwDyAQZoDAAABgBVAGkMAAADAFgAawwAAAMAWQBqDAAAAQAuAGwMAAACAE0A6gwAAAYAXwAIAAYJDiIoAwDyAQZoDAAABgBVAGkMAAADAFgAawwAAAMAWQBqDAAAAQAuAGwMAAACAE0A6gwAAAYAXwAuAAQKfyQAAggACAlOJb4FACwDAAgACAlOJb4FACwDAAEuAAUUCAkQAAIAEA0A.',
My='Mythicalhobo:BAEALgADCgUJCAAAAA==.Mythmaker:BAEALgAECgUJDQABLgAECgcJEwADAAAAAA==.',
Na='Nargrodamus:BAEBLgAECn8hAAIcAAgJMxjJOgDQAQhoDAAABQBGAGkMAAAGAFYAawwAAAQAQABqDAAABQA0AGwMAAADAEkAbQwAAAIAGADqDAAABQA+AG4MAAADADMAHAAICTMYyToA0AEIaAwAAAUARgBpDAAABgBWAGsMAAAEAEAAagwAAAUANABsDAAAAwBJAG0MAAACABgA6gwAAAUAPgBuDAAAAwAzAAAA.',
Ni='Nimueh:BAECLgAFFH8JAAIdAAUJCwlZCgBEAQVoDAAAAgAvAGkMAAABABwAawwAAAEABwBqDAAAAQATAGwMAAAEAA0AHQAFCQsJWQoARAEFaAwAAAIALwBpDAAAAQAcAGsMAAABAAcAagwAAAEAEwBsDAAABAANAC4ABAp/LQADHQAJCS8S6RQANgIAHQAJCS8S6RQANgIADQAHCeAPPCYAQwEAAAA=.Nindë:BAEBLgAFFH8JAAIeAAMJLQl5BwDrAANoDAAAAwAeAGkMAAADABwA6gwAAAMACwAeAAMJLQl5BwDrAANoDAAAAwAeAGkMAAADABwA6gwAAAMACwABLgAFFAcJGAAfAOEUAA==.Niniane:BAECLgAFFH8YAAMfAAcJ4RRlBwCdAQdoDAAABQAhAGkMAAAEAFEAawwAAAQAQQBqDAAAAwARAGwMAAABAAoAbQwAAAEAOADqDAAABgBJAB8ABgkyGGUHAJ0BBmgMAAAEACEAaQwAAAQAUQBrDAAAAgBBAGoMAAABAAgAbQwAAAEAOADqDAAABgBJACAABAkJBCIZAMMABGgMAAABAAoAawwAAAIACQBqDAAAAgARAGwMAAABAAoALgAECn8nAAMfAAkJGyNyCwC2AgAfAAkJGyNyCwC2AgAgAAYJUgq0VgDuAAAAAA==.',
No='Nordsense:BAEALgAECgEJAQAAAA==.Novebear:BAEBLgAFFH8HAAIQAAIJYRsbDQChAAJoDAAABABCAOoMAAADAEkAEAACCWEbGw0AoQACaAwAAAQAQgDqDAAAAwBJAAEuAAUUAwkPAA8A1SUA.Novelus:BAECLgAFFH8PAAIPAAMJ1SX3AwBHAQNoDAAABgBhAGkMAAAEAF8A6gwAAAUAYgAPAAMJ1SX3AwBHAQNoDAAABgBhAGkMAAAEAF8A6gwAAAUAYgAuAAQKfzAAAg8ACQkAJroAAFUDAA8ACQkAJroAAFUDAAAA.',
Ol='Oldbronze:BAECLgAFFH8PAAIPAAQJLBoqCQA/AQRoDAAABQBLAGkMAAAEAEkAawwAAAIAKADqDAAABABOAA8ABAksGioJAD8BBGgMAAAFAEsAaQwAAAQASQBrDAAAAgAoAOoMAAAEAE4ALgAECn8wAAIPAAgJTSIoBQCFAgAPAAgJTSIoBQCFAgAAAA==.',
On='Onenjen:BAEBLgAECn8kAAITAAgJzQNCDwDsAAhoDAAABwAPAGkMAAAHAAgAawwAAAcAEABqDAAABAANAGwMAAAEAAgAbQwAAAEABQDqDAAABQAMAG4MAAABAAIAEwAICc0DQg8A7AAIaAwAAAcADwBpDAAABwAIAGsMAAAHABAAagwAAAQADQBsDAAABAAIAG0MAAABAAUA6gwAAAUADABuDAAAAQACAAAA.',
['Oñ']='Oññayu:BAEALgAECgIJAgAAAA==.',
Pa='Parkercannon:BAECLgAFFH8cAAINAAcJrh4GAQA6AgdoDAAABQBeAGkMAAAEAFwAawwAAAUAUgBqDAAABgBJAGwMAAADAF4AbQwAAAIALgDqDAAAAwA8AA0ABwmuHgYBADoCB2gMAAAFAF4AaQwAAAQAXABrDAAABQBSAGoMAAAGAEkAbAwAAAMAXgBtDAAAAgAuAOoMAAADADwALgAECn8mAAINAAkJ8iPuAADQAwANAAkJ8iPuAADQAwAAAA==.Patrennessy:BAEBLgAECn8xAAIIAAkJsSRgAQA6AwloDAAABgBiAGkMAAAGAGAAawwAAAYAXgBqDAAABQBdAGwMAAAGAGAAbQwAAAUAWgDqDAAABwBdAG4MAAAFAF0AbwwAAAMAVwAIAAkJsSRgAQA6AwloDAAABgBiAGkMAAAGAGAAawwAAAYAXgBqDAAABQBdAGwMAAAGAGAAbQwAAAUAWgDqDAAABwBdAG4MAAAFAF0AbwwAAAMAVwAAAA==.',
Ra='Ramsama:BAEALgAECgkJEQAAAA==.Ramsdh:BAEALgAECggJCQABLgAFFAYJFAARAFEeAA==.Ramsx:BAECLgAFFH8UAAMRAAYJUR51AwDEAQZoDAAABQBaAGkMAAAEAFYAawwAAAMAUgBqDAAAAQAYAGwMAAABACkA6gwAAAYAVgARAAUJziF1AwDEAQVoDAAABQBaAGkMAAACAFYAawwAAAIAUgBqDAAAAQAYAOoMAAAFAFYAEwAECUsSaAIAFgEEaQwAAAIAOgBrDAAAAQA6AGwMAAABACkA6gwAAAEAHAAuAAQKfxcAAxEABwnKJdwUAGsCABEABwnKJdwUAGsCABMAAQk4JJAZAFgAAAAA.Rarelinelk:BAEALgAECgIJAgABLgAFFAYJFQAcACMjAA==.',
Re='Recursively:BAECLgAFFH8bAAQHAAgJ5BOrAwDnAQhoDAAABQBhAGkMAAAEAEAAawwAAAUAQgBqDAAAAwAlAGwMAAABABUAbQwAAAEACADqDAAABwBFAG4MAAABABsABwAHCSEWqwMA5wEHaAwAAAUAYQBpDAAAAwBAAGsMAAADADoAagwAAAIADgBsDAAAAQAVAOoMAAAFAEUAbgwAAAEAGwAGAAQJvg/YAwBaAQRpDAAAAQAsAGsMAAACAEIAbQwAAAEACADqDAAAAgApABoAAQkAAHYFAFcAAWoMAAABACUALgAECn8qAAQHAAkJaSM3CQDcAgAHAAkJSCM3CQDcAgAGAAYJCiKECAA6AgAaAAEJAADYIgBmAAAAAA==.Redxr:BAEALgAECgYJDQABLgAFFAYJDAAOAPoUAA==.Releira:BAEALgAFFAEJAQABLgAFFAQJDwASAOUUAA==.',
Ri='Riversong:BAEALgAECgUJBQABLgAFFAUJCQAdAAsJAA==.',
Sh='Sharrq:BAECLgAFFH8SAAIhAAQJzxqUAABpAQRoDAAABgBJAGkMAAAFACoAawwAAAMASADqDAAABABWACEABAnPGpQAAGkBBGgMAAAGAEkAaQwAAAUAKgBrDAAAAwBIAOoMAAAEAFYALgAECn8gAAMhAAgJxCCoAAASAwAhAAgJxCCoAAASAwAiAAEJKwlZHgA0AAAAAA==.Shotgunarms:BAEALgAECgQJBAABLgAECggJGgAYAHAeAA==.',
Si='Sivvychuckle:BAEALgAECgIJAwABLgAECgcJCwADAAAAAA==.Sivvygrows:BAEALgAECgcJBwABLgAECgcJCwADAAAAAA==.Sivvyrawr:BAEALgAECgcJCwAAAA==.',
Sl='Slammybreath:BAECLgAFFH8JAAMEAAQJ4xNtGAAyAQRoDAAAAwArAGkMAAADAEwAawwAAAIAHADqDAAAAQA3AAQABAnjE20YADIBBGgMAAACACsAaQwAAAMATABrDAAAAgAcAOoMAAABADcABQABCTYBHgwAQwABaAwAAAEAAwAuAAQKfx0AAwQACAloFCQxAD4BAAQABgnOEiQxAD4BAAUACAnaE/ssALQAAAEuAAUUCAkQAAIAEA0A.',
Sp='Spicyhotwing:BAECLgAFFH8QAAMCAAgJEA2KAwDOAQhoDAAAAgAKAGkMAAACAAsAawwAAAIAGwBqDAAAAwAhAGwMAAABAAUAbQwAAAEAWQDqDAAABAAqAG4MAAABAC0AAgAGCaEIigMAzgEGaAwAAAEACgBpDAAAAQALAGsMAAABABsAagwAAAMAIQBsDAAAAQAFAOoMAAAEACoABAAFCc0RjwsAogEFaAwAAAEAPQBpDAAAAQBSAGsMAAABAEYAbQwAAAEABABuDAAAAQAJAC4ABAp/GAAEAgAICesSQBQAAgIAAgAICesSQBQAAgIABAAECbQkOyoAPgEABQABCX0efjgAVQAAAAA=.',
Ta='Tauntinitis:BAEALgAECgUJBQABLgAFFAMJBgAUABIPAA==.',
Te='Tendeyaloran:BAEALgAECgQJCgAAAA==.',
Th='Thanala:BAECLgAFFH8aAAIBAAYJsiJMBQADAgZoDAAABgBSAGkMAAAGAGEAawwAAAQAWABqDAAAAwBLAGwMAAABAGEA6gwAAAYAWwABAAYJsiJMBQADAgZoDAAABgBSAGkMAAAGAGEAawwAAAQAWABqDAAAAwBLAGwMAAABAGEA6gwAAAYAWwAuAAQKfxwAAgEACAlhHnwUAG4CAAEACAlhHnwUAG4CAAAA.',
Tr='Trintu:BAEALgAECgkJAwABLgAFFAYJFQAWAPENAA==.',
Yo='Yoktuah:BAEBLgAFFH8FAAMBAAQJ6gPGDQD9AARoDAAAAgAAAGkMAAABABwAawwAAAEACgDqDAAAAQAAAAEABAnqA8YNAP0ABGgMAAABAAAAaQwAAAEAHABrDAAAAQAKAOoMAAABAAAAGwABCRgRnTEAUgABaAwAAAEAKwABLgAFFAQJCwAJAKAQAA==.',
Yu='Yungdh:BAEBLgAECn8cAAIKAAcJAx29LwC9AQdoDAAABAA8AGkMAAAEAEwAawwAAAUAUgBqDAAABABOAGwMAAAEAEkAbQwAAAEAPADqDAAABgBbAAoABwkDHb0vAL0BB2gMAAAEADwAaQwAAAQATABrDAAABQBSAGoMAAAEAE4AbAwAAAQASQBtDAAAAQA8AOoMAAAGAFsAAS4ABRQHCSAAIwALJgA=.Yungdrood:BAECLgAFFH8gAAIjAAcJCyb/AAA1AgdoDAAABgBjAGkMAAAHAGMAawwAAAYAYwBqDAAABQBhAGwMAAACAF4AbQwAAAEAXADqDAAABQBiACMABwkLJv8AADUCB2gMAAAGAGMAaQwAAAcAYwBrDAAABgBjAGoMAAAFAGEAbAwAAAIAXgBtDAAAAQBcAOoMAAAFAGIALgAECn82AAIjAAkJ1iZBAgCfAwAjAAkJ1iZBAgCfAwAAAA==.Yungmonk:BAEALgAECgQJBAABLgAFFAcJIAAjAAsmAA==.Yungwizard:BAEBLgAECn8WAAISAAYJ2iXfOQCOAgZoDAAABABfAGkMAAAEAGIAawwAAAQAXwBqDAAAAwBhAGwMAAAEAGEA6gwAAAMAYQASAAYJ2iXfOQCOAgZoDAAABABfAGkMAAAEAGIAawwAAAQAXwBqDAAAAwBhAGwMAAAEAGEA6gwAAAMAYQABLgAFFAcJIAAjAAsmAA==.',
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
