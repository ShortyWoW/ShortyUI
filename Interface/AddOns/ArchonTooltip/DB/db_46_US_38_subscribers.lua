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

local lookup = {'Paladin-Holy','Evoker-Preservation','Unknown-Unknown','Evoker-Augmentation','Evoker-Devastation','Monk-Brewmaster','Shaman-Elemental','DemonHunter-Havoc','DemonHunter-Devourer','DemonHunter-Vengeance','Priest-Shadow','Priest-Discipline','Warrior-Protection','Rogue-Subtlety','Mage-Frost','Warlock-Demonology','Rogue-Assassination','Warrior-Fury','Warlock-Destruction','Rogue-Outlaw','DeathKnight-Blood','Druid-Guardian','Monk-Windwalker','Monk-Mistweaver','Shaman-Restoration','Warlock-Affliction','Paladin-Retribution','DeathKnight-Unholy','Priest-Holy','Druid-Feral','Hunter-BeastMastery','Hunter-Marksmanship','Mage-Fire','Mage-Arcane','Druid-Balance',}
local provider = {region='US',realm='BleedingHollow',name='US',type='subscribers',zone=46,date='2026-05-10',data={Ad='Addex:BAEBLgAFFH8LAAIBAAYJzBD8BgC6AQZoDAAAAgA0AGkMAAACAD0AawwAAAIADQBqDAAAAgAiAGwMAAABACsA6gwAAAIANAABAAYJzBD8BgC6AQZoDAAAAgA0AGkMAAACAD0AawwAAAIADQBqDAAAAgAiAGwMAAABACsA6gwAAAIANAABLgAFFAgJKAACAAwdAA==.',
Ae='Aeveracy:BAEALgADCgMJAwABLgAECgIJAgADAAAAAA==.',
Am='Ambient:BAECLgAFFH8oAAMCAAgJDB3PAABkAghoDAAABwBhAGkMAAAHAEUAawwAAAcAUABqDAAABgBLAGwMAAAFAFQAbQwAAAEAJwDqDAAABgBLAG4MAAABAEkAAgAICQwdzwAAZAIIaAwAAAUAYQBpDAAABwBFAGsMAAAHAFAAagwAAAYASwBsDAAABQBUAG0MAAABACcA6gwAAAYASwBuDAAAAQBJAAQAAQk/F3kgAFAAAWgMAAACADsALgAECn8dAAMCAAkJcyO/BAADAwACAAgJKyO/BAADAwAFAAEJiBPWOgBEAAAAAA==.',
Br='Briéè:BAEALgAECgUJDQAAAA==.Bruwon:BAECLgAFFH8kAAIGAAgJMyF2AABuAghoDAAABgBcAGkMAAAGAFsAawwAAAYAWABqDAAABQA+AGwMAAAEAGIAbQwAAAEATwDqDAAABwBeAG4MAAABADIABgAICTMhdgAAbgIIaAwAAAYAXABpDAAABgBbAGsMAAAGAFgAagwAAAUAPgBsDAAABABiAG0MAAABAE8A6gwAAAcAXgBuDAAAAQAyAC4ABAp/IQACBgAJCUAhxgQAPgMABgAJCUAhxgQAPgMAAAA=.',
Ca='Captinsaneo:BAEALgAECggJCAAAAA==.',
Ch='Charzie:BAEALgAECgEJAQABLgAFFAgJJAAGADMhAA==.',
Ci='Ciprox:BAEBLgAECn8VAAIHAAgJqB7MBwBsAghoDAAAAwBVAGkMAAADAEcAawwAAAMAXABqDAAAAwBQAGwMAAADAGAAbQwAAAIAOADqDAAAAwBcAG4MAAABADcABwAICagezAcAbAIIaAwAAAMAVQBpDAAAAwBHAGsMAAADAFwAagwAAAMAUABsDAAAAwBgAG0MAAACADgA6gwAAAMAXABuDAAAAQA3AAEuAAUUBwkPAAgAfhkA.',
Cy='Cyprexdh:BAECLgAFFH8PAAMIAAcJfhnvAQB7AQdoDAAABQBjAGkMAAADAFoAawwAAAIAQQBqDAAAAgA0AGwMAAABAB0AbQwAAAEADwDqDAAAAQBaAAgABAl/Ge8BAHsBBGgMAAADAGMAaQwAAAEABQBrDAAAAQBBAOoMAAABAFoACQAGCTUP/RcAUgEGaAwAAAIAMQBpDAAAAgBaAGsMAAABAAkAagwAAAIANABsDAAAAQAdAG0MAAABAA8ALgAECn8aAAQIAAgJ8CU3AwBSAwAIAAgJWyU3AwBSAwAJAAMJsiSYewA1AQAKAAEJAAC1LQApAAAAAA==.',
Da='Danilynn:BAEALgADCggJFAABLgAECgcJHQALAIQDAA==.Danitsia:BAEBLgAECn8dAAMLAAcJhAOhMQDZAAdoDAAABQAIAGkMAAAFAAsAawwAAAUACABqDAAABAAUAGwMAAAEAAsAbQwAAAEABADqDAAABQAIAAsABwmEA6ExANkAB2gMAAAFAAgAaQwAAAUACwBrDAAABAAIAGoMAAAEABQAbAwAAAMACwBtDAAAAQAEAOoMAAAEAAgADAADCeMAc1EARgADawwAAAEAAgBsDAAAAQADAOoMAAABAAAAAAA=.',
De='Delabrand:BAEALgAECgYJCQABLgAFFAcJGwANAKwmAA==.Delarage:BAECLgAFFH8bAAINAAcJrCYvAACvAgdoDAAABgBjAGkMAAAEAGMAawwAAAQAYwBqDAAABABiAGwMAAACAGQAbQwAAAEAXwDqDAAABgBjAA0ABwmsJi8AAK8CB2gMAAAGAGMAaQwAAAQAYwBrDAAABABjAGoMAAAEAGIAbAwAAAIAZABtDAAAAQBfAOoMAAAGAGMALgAECn8hAAINAAkJ/ib9AACQAwANAAkJ/ib9AACQAwAAAA==.Deleerious:BAECLgAFFH8RAAIOAAUJzCVtBACZAQVoDAAABQBiAGkMAAAFAGEAawwAAAIAXgBqDAAAAQBdAOoMAAAEAGAADgAFCcwlbQQAmQEFaAwAAAUAYgBpDAAABQBhAGsMAAACAF4AagwAAAEAXQDqDAAABABgAC4ABAp/HwACDgAICR0koQUAOAMADgAICR0koQUAOAMAAAA=.',
Do='Doriel:BAEALgAECgMJBAABLgAFFAQJDwAPAOUUAA==.',
Du='Dubsstree:BAEALgADCgYJBgABLgAFFAcJGgAQANQZAA==.',
Dw='Dwarfwarloc:BAEALgAECgYJEQAAAA==.',
Eg='Egirlarmpits:BAEALgAFFAIJAgABLgAFFAQJCgAHAKAQAA==.',
Em='Emellious:BAECLgAFFH8UAAIOAAUJwxuXBwBrAQVoDAAABgBPAGkMAAAFAFsAawwAAAMAGgBqDAAAAgA6AOoMAAAEAFcADgAFCcMblwcAawEFaAwAAAYATwBpDAAABQBbAGsMAAADABoAagwAAAIAOgDqDAAABABXAC4ABAp/HAADDgAICQQhoAwAzwIADgAICQQhoAwAzwIAEQABCZALgB8ANQAAAAA=.',
Fr='Freddyfletch:BAEALgADCgUJBQAAAA==.',
Fu='Funkaroused:BAEBLgAECn8vAAISAAgJmRrHDgAMAghoDAAABwBbAGkMAAAHAEcAawwAAAcAQABqDAAABgBFAGwMAAAHAEsAbQwAAAEAMADqDAAACABKAG4MAAAEADIAEgAICZkaxw4ADAIIaAwAAAcAWwBpDAAABwBHAGsMAAAHAEAAagwAAAYARQBsDAAABwBLAG0MAAABADAA6gwAAAgASgBuDAAABAAyAAAA.',
Gi='Giantmagic:BAEBLgAECn8bAAIPAAcJQh17XQAiAgdoDAAABABOAGkMAAAEAFIAawwAAAQAWwBqDAAABgBOAGwMAAACAD4AbQwAAAIAQgDqDAAABQBEAA8ABwlCHXtdACICB2gMAAAEAE4AaQwAAAQAUgBrDAAABABbAGoMAAAGAE4AbAwAAAIAPgBtDAAAAgBCAOoMAAAFAEQAAAA=.',
Gj='Gjlo:BAECLgAFFH8GAAMSAAMJEg+KIwChAANoDAAABABGAGkMAAABAAAA6gwAAAEALAASAAIJaxaKIwChAAJoDAAAAgBGAOoMAAABACwADQACCaQDJg4AZQACaAwAAAIAEQBpDAAAAQAAAC4ABAp/PgADEgAJCX8XrAsANQIAEgAJCX8XrAsANQIADQAHCXcPMBoA7wAAAAA=.',
Gl='Gluzzaie:BAEBLgAECn8UAAMQAAgJMxuRXgCtAQhoDAAAAwA7AGkMAAADAE0AawwAAAMANwBqDAAAAwA0AGwMAAACAFQAbQwAAAEANgDqDAAAAwBIAG4MAAACAFIAEAAHCQ0bkV4ArQEHaAwAAAMAOwBpDAAAAwBNAGsMAAABADQAbAwAAAIAVABtDAAAAQA2AOoMAAADAEgAbgwAAAIAUgATAAIJmBW2TACHAAJrDAAAAgA3AGoMAAADADQAAAA=.',
Gr='Gronknose:BAEBLgAECn8WAAIUAAcJ0iHgAQCcAgdoDAAAAwBVAGkMAAAEAFwAawwAAAQATABqDAAAAwBeAGwMAAACAFcAbQwAAAEAUgDqDAAABQBfABQABwnSIeABAJwCB2gMAAADAFUAaQwAAAQAXABrDAAABABMAGoMAAADAF4AbAwAAAIAVwBtDAAAAQBSAOoMAAAFAF8AAS4ABAoJCSgABgBBJAA=.',
Ha='Hakdh:BAEALgAECgYJBgABLgAFFAUJDwAVAA8RAA==.Hakdk:BAEBLgAFFH8PAAIVAAUJDxH7BQA7AQVoDAAAAgAiAGkMAAACACMAawwAAAIAJwBqDAAABQAaAOoMAAAEAEAAFQAFCQ8R+wUAOwEFaAwAAAIAIgBpDAAAAgAjAGsMAAACACcAagwAAAUAGgDqDAAABABAAAAA.Hakgek:BAEBLgAFFH8JAAIWAAQJRA5EBAAUAQRoDAAAAgAlAGkMAAACACgAawwAAAIAJgBsDAAAAwAdABYABAlEDkQEABQBBGgMAAACACUAaQwAAAIAKABrDAAAAgAmAGwMAAADAB0AAS4ABRQFCQ8AFQAPEQA=.Hakmonk:BAEBLgAFFH8GAAIGAAQJSxHNDQAWAQRoDAAAAgAmAGkMAAACAEsAawwAAAEAEQDqDAAAAQAuAAYABAlLEc0NABYBBGgMAAACACYAaQwAAAIASwBrDAAAAQARAOoMAAABAC4AAS4ABRQFCQ8AFQAPEQA=.Haksham:BAEALgAECgcJBAABLgAFFAUJDwAVAA8RAA==.Hakwar:BAEALgAECgUJBQABLgAFFAUJDwAVAA8RAA==.Halosbrew:BAECLgAFFH8JAAIGAAQJqhnnDwADAQRoDAAAAgBLAGkMAAADAFYAawwAAAEAGgDqDAAAAwBKAAYABAmqGecPAAMBBGgMAAACAEsAaQwAAAMAVgBrDAAAAQAaAOoMAAADAEoALgAECn8UAAMGAAgJRx4UFQBjAgAGAAcJzSEUFQBjAgAXAAUJaRO3PAAoAQAAAA==.Halosdk:BAEBLgAFFH8LAAIVAAQJ0xYuDQASAQRoDAAAAwBEAGkMAAACAEsAawwAAAIAGwDqDAAABAA+ABUABAnTFi4NABIBBGgMAAADAEQAaQwAAAIASwBrDAAAAgAbAOoMAAAEAD4AAS4ABRQECQkABgCqGQA=.Halosmage:BAEALgAECggJBwABLgAFFAQJCQAGAKoZAA==.',
He='Heavensfeel:BAEBLgAECn8sAAQCAAkJFB8NCAC7AgloDAAABwBVAGkMAAAGAD0AawwAAAYASwBqDAAABQBbAGwMAAAFAFYAbQwAAAMAUADqDAAABwBVAG4MAAADAEQAbwwAAAIAUQACAAkJFB8NCAC7AgloDAAABQBVAGkMAAAEAD0AawwAAAQASwBqDAAAAwBbAGwMAAADAFYAbQwAAAIAUADqDAAABQBVAG4MAAACAEQAbwwAAAEAUQAEAAkJqBvKBACxAgloDAAAAQBYAGkMAAACAF8AawwAAAIAXQBqDAAAAgA6AGwMAAACAFUAbQwAAAEAKADqDAAAAQAnAG4MAAABAF8AbwwAAAEAHAAFAAIJjgsIEgBtAAJoDAAAAQAbAOoMAAABAB8AAS4ABRQECQkABgCqGQA=.',
In='Initiative:BAEBLgAECn8XAAMYAAgJhB26CQBeAghoDAAAAwBXAGkMAAADAFwAawwAAAQAXwBqDAAAAwA8AGwMAAAEADMAbQwAAAEASQDqDAAAAwBRAG4MAAACAD0AGAAICYQdugkAXgIIaAwAAAIAVwBpDAAAAgBcAGsMAAADAF8AagwAAAIAPABsDAAAAQAzAG0MAAABAEkA6gwAAAIAUQBuDAAAAQA9ABcABwmnH1caAA0CB2gMAAABAFkAaQwAAAEAXQBrDAAAAQBeAGoMAAABAFUAbAwAAAMAYADqDAAAAQBQAG4MAAABACAAAAA=.',
It='Itsgrippy:BAEALgAECgYJDgAAAA==.',
Je='Jev:BAEBLgAECn8hAAILAAkJiCKhAgCAAwloDAAABABeAGkMAAAEAF4AawwAAAQAXgBqDAAABABYAGwMAAAEAFsAbQwAAAQAVQDqDAAAAwBVAG4MAAAFAEwAbwwAAAEAVAALAAkJiCKhAgCAAwloDAAABABeAGkMAAAEAF4AawwAAAQAXgBqDAAABABYAGwMAAAEAFsAbQwAAAQAVQDqDAAAAwBVAG4MAAAFAEwAbwwAAAEAVAAAAA==.',
Ke='Keeflan:BAECLgAFFH8KAAIHAAQJoBCwEQApAQRoDAAAAwA8AGkMAAADABoAawwAAAIAMgDqDAAAAgAhAAcABAmgELARACkBBGgMAAADADwAaQwAAAMAGgBrDAAAAgAyAOoMAAACACEALgAECn8ZAAMHAAgJIB+5KwC6AQAHAAYJ4B+5KwC6AQAZAAcJRg2tQAB+AQAAAA==.',
Le='Lewinskibidi:BAEALgAFFAIJBAABLgAFFAcJGwALAK4eAA==.',
Ma='Madtheaug:BAEBLgAECn8WAAMFAAgJkyAzEgC+AQhoDAAAAgBPAGkMAAACAEkAawwAAAIAVwBqDAAABABWAGwMAAADAFwAbQwAAAMAUADqDAAABABbAG4MAAACAE4ABQAHCbMYMxIAvgEHaAwAAAIATwBpDAAAAgBJAGsMAAACAFcAagwAAAIAOwBsDAAAAgARAG0MAAACAC8A6gwAAAIASQAEAAUJgSFtIAC9AQVqDAAAAgBWAGwMAAABAFwAbQwAAAEAUADqDAAAAgBbAG4MAAACAE4AAS4ABRQJCSEAEwABJgA=.Madthehunt:BAEALgAFFAEJAQABLgAFFAkJIQATAAEmAA==.Madthelock:BAECLgAFFH8hAAQTAAkJASY4AACWAgloDAAABABjAGkMAAAFAGMAawwAAAYAZABqDAAABQBYAGwMAAADAGEAbQwAAAEAYgDqDAAABwBhAG4MAAABAFoAbwwAAAEAXgATAAcJiSY4AACWAgdoDAAAAQBjAGkMAAADAGMAawwAAAUAZABqDAAAAwBYAGwMAAACAGEAbQwAAAEAYgDqDAAAAwBhABAABwnSIeAAAFECB2gMAAADAF8AaQwAAAEAXgBqDAAAAQBHAGwMAAABAC4A6gwAAAMAYQBuDAAAAQBaAG8MAAABAF4AGgAECcEl4AAAVAEEaQwAAAEAYwBrDAAAAQBeAGoMAAABAFYA6gwAAAEAYAAuAAQKfyIABBAACQl9JpYAAIADABAACQlNJpYAAIADABMABgkcJl0KABkCABoAAwkBJGQOAEsBAAAA.Magølli:BAECLgAFFH8PAAIPAAQJ5RTKKgBYAQRoDAAABQA5AGkMAAAFAEMAawwAAAMAGgDqDAAAAgA9AA8ABAnlFMoqAFgBBGgMAAAFADkAaQwAAAUAQwBrDAAAAwAaAOoMAAACAD0ALgAECn8kAAIPAAgJWR9NJgDZAgAPAAgJWR9NJgDZAgAAAA==.',
Me='Megachud:BAEALgAECgYJBwABLgAFFAQJCgAHAKAQAA==.',
Mi='Minbä:BAEALgAECgYJEgABLgAFFAcJGgAQANQZAA==.Minigun:BAEALgAECgcJCgAAAQ==.Minipala:BAECLgAFFH8LAAIBAAQJtBsjEABBAQRoDAAABABPAGkMAAACADMAawwAAAIASwDqDAAAAwBNAAEABAm0GyMQAEEBBGgMAAAEAE8AaQwAAAIAMwBrDAAAAgBLAOoMAAADAE0ALgAECn8dAAMBAAgJOCKDBgADAwABAAgJOCKDBgADAwAbAAUJ5w9FswAeAQABLgAFFAcJGgAQANQZAA==.Miniss:BAECLgAFFH8aAAQQAAcJ1BnTAgALAgdoDAAABgBeAGkMAAAFAE8AawwAAAMAUgBqDAAABABXAGwMAAACABoAbQwAAAEADwDqDAAABQBhABAABwnUGdMCAAsCB2gMAAAGAF4AaQwAAAMATwBrDAAAAgBSAGoMAAAEAFcAbAwAAAIAGgBtDAAAAQAPAOoMAAAEAGEAEwACCYANSA0AowACaQwAAAIAHgBrDAAAAQAmABoAAQlyFxwKAFQAAeoMAAABADwALgAECn9BAAQaAAkJIyYTAABxAwAaAAkJNyUTAABxAwAQAAkJ3yXlAQBTAwATAAIJESBGQQCwAAAAAA==.',
Mo='Moosclemommy:BAECLgAFFH8RAAIGAAUJuiDoCAB7AQVoDAAABQBFAGkMAAADAFgAawwAAAMAWQBqDAAAAQAuAOoMAAAFAFcABgAFCbog6AgAewEFaAwAAAUARQBpDAAAAwBYAGsMAAADAFkAagwAAAEALgDqDAAABQBXAC4ABAp/IAACBgAICSAlvwUALAMABgAICSAlvwUALAMAAS4ABRQHCQsAAgBpDAA=.',
My='Mythicalhobo:BAEALgADCgUJCAAAAA==.Mythmaker:BAEALgAECgUJDQABLgAECgcJGwAPAEIdAA==.',
Na='Nargrodamus:BAEBLgAECn8aAAIcAAgJKhbsKQDhAQhoDAAAAwBGAGkMAAAEADEAawwAAAMAQABqDAAABAArAGwMAAACAEkAbQwAAAIAGADqDAAABQA+AG4MAAADADMAHAAICSoW7CkA4QEIaAwAAAMARgBpDAAABAAxAGsMAAADAEAAagwAAAQAKwBsDAAAAgBJAG0MAAACABgA6gwAAAUAPgBuDAAAAwAzAAAA.',
Ni='Nimueh:BAECLgAFFH8IAAIdAAUJCwlwCABIAQVoDAAAAgAvAGkMAAABABwAawwAAAEABwBqDAAAAQATAGwMAAADAA0AHQAFCQsJcAgASAEFaAwAAAIALwBpDAAAAQAcAGsMAAABAAcAagwAAAEAEwBsDAAAAwANAC4ABAp/LQADHQAJCS8S6BQANgIAHQAJCS8S6BQANgIACwAHCeAPARwAaAEAAAA=.Nindë:BAEBLgAFFH8JAAIeAAMJLQnyBQDvAANoDAAAAwAeAGkMAAADABwA6gwAAAMACwAeAAMJLQnyBQDvAANoDAAAAwAeAGkMAAADABwA6gwAAAMACwABLgAFFAYJFgAfAK0UAA==.Niniane:BAECLgAFFH8WAAMfAAYJrRRRFQBQAQZoDAAABQAhAGkMAAAEAFEAawwAAAQAQQBqDAAAAwARAGwMAAABAAoA6gwAAAUASQAfAAUJxRhRFQBQAQVoDAAABAAhAGkMAAAEAFEAawwAAAIAQQBqDAAAAQAIAOoMAAAFAEkAIAAECQkEGxkAwwAEaAwAAAEACgBrDAAAAgAJAGoMAAACABEAbAwAAAEACgAuAAQKfx8AAx8ACAl0H2kQALYCAB8ABwnmImkQALYCACAABglSCrFWAO4AAAAA.',
No='Nordsense:BAEALgAECgEJAQAAAA==.Novebear:BAEBLgAFFH8GAAIWAAIJYRsABACZAAJoDAAAAwBCAOoMAAADAEkAFgACCWEbAAQAmQACaAwAAAMAQgDqDAAAAwBJAAEuAAUUAwkMAA0AGCUA.Novelus:BAECLgAFFH8MAAINAAMJGCX1AwBHAQNoDAAABQBhAGkMAAADAF0A6gwAAAQAXQANAAMJGCX1AwBHAQNoDAAABQBhAGkMAAADAF0A6gwAAAQAXQAuAAQKfysAAg0ACQkAJtAAADUDAA0ACQkAJtAAADUDAAAA.',
Ol='Oldbronze:BAECLgAFFH8LAAINAAQJCRm1BwA6AQRoDAAABABHAGkMAAADAEEAawwAAAEAKADqDAAAAwBOAA0ABAkJGbUHADoBBGgMAAAEAEcAaQwAAAMAQQBrDAAAAQAoAOoMAAADAE4ALgAECn8sAAINAAgJTSIyAwCeAgANAAgJTSIyAwCeAgAAAA==.',
On='Onenjen:BAEBLgAECn8gAAIRAAgJzQOdDAD8AAhoDAAABgAPAGkMAAAGAAgAawwAAAYAEABqDAAABAANAGwMAAAEAAgAbQwAAAEABQDqDAAABAAMAG4MAAABAAIAEQAICc0DnQwA/AAIaAwAAAYADwBpDAAABgAIAGsMAAAGABAAagwAAAQADQBsDAAABAAIAG0MAAABAAUA6gwAAAQADABuDAAAAQACAAAA.',
['Oñ']='Oññayu:BAEALgAECgIJAgAAAA==.',
Pa='Parkercannon:BAECLgAFFH8bAAILAAcJrh4GAQA6AgdoDAAABQBeAGkMAAAEAFwAawwAAAUAUgBqDAAABQBJAGwMAAADAF4AbQwAAAIALgDqDAAAAwA8AAsABwmuHgYBADoCB2gMAAAFAF4AaQwAAAQAXABrDAAABQBSAGoMAAAFAEkAbAwAAAMAXgBtDAAAAgAuAOoMAAADADwALgAECn8mAAILAAkJ8iPvAADQAwALAAkJ8iPvAADQAwAAAA==.Patrennessy:BAEBLgAECn8oAAIGAAkJQSRiAwDPAgloDAAABQBiAGkMAAAFAGAAawwAAAUAXQBqDAAABABdAGwMAAAFAGAAbQwAAAQAUgDqDAAABgBdAG4MAAAEAF0AbwwAAAIAVwAGAAkJQSRiAwDPAgloDAAABQBiAGkMAAAFAGAAawwAAAUAXQBqDAAABABdAGwMAAAFAGAAbQwAAAQAUgDqDAAABgBdAG4MAAAEAF0AbwwAAAIAVwAAAA==.',
Ra='Ramsama:BAEALgAECgkJCAAAAA==.Ramsdh:BAEALgAECggJCQABLgAFFAYJEwAOAFEeAA==.Ramsx:BAECLgAFFH8TAAMOAAYJUR5yAwDEAQZoDAAABQBaAGkMAAAEAFYAawwAAAMAUgBqDAAAAQAYAGwMAAABACkA6gwAAAUAVgAOAAUJziFyAwDEAQVoDAAABQBaAGkMAAACAFYAawwAAAIAUgBqDAAAAQAYAOoMAAAEAFYAEQAECUsSaAIAFgEEaQwAAAIAOgBrDAAAAQA6AGwMAAABACkA6gwAAAEAHAAuAAQKfxYAAw4ABglEJtsUAGsCAA4ABglEJtsUAGsCABEAAQk4JDUWAF0AAAAA.Rarelinelk:BAEALgAECgIJAgABLgAFFAYJEgAcACMjAA==.',
Re='Recursively:BAECLgAFFH8ZAAQQAAgJ4xKqAwDnAQhoDAAABABPAGkMAAAEAEAAawwAAAUAQgBqDAAAAwAlAGwMAAABABUAbQwAAAEACADqDAAABgBFAG4MAAABABsAEAAHCfYUqgMA5wEHaAwAAAQATwBpDAAAAwBAAGsMAAADADoAagwAAAIADgBsDAAAAQAVAOoMAAAEAEUAbgwAAAEAGwATAAQJvg/WAwBaAQRpDAAAAQAsAGsMAAACAEIAbQwAAAEACADqDAAAAgApABoAAQkAAHUFAFcAAWoMAAABACUALgAECn8lAAQQAAkJaSP1DAASAwAQAAkJOiP1DAASAwATAAYJCiKECAA6AgAaAAEJAADYIgBmAAAAAA==.Redxr:BAEALgAECgYJDQABLgAFFAYJCwAMAPoUAA==.',
Sh='Sharrq:BAECLgAFFH8OAAIhAAQJaBl5AABkAQRoDAAABQBJAGkMAAAEACoAawwAAAIASADqDAAAAwBHACEABAloGXkAAGQBBGgMAAAFAEkAaQwAAAQAKgBrDAAAAgBIAOoMAAADAEcALgAECn8gAAMhAAgJxCCoAAASAwAhAAgJxCCoAAASAwAiAAEJKwlaHgA0AAAAAA==.',
Si='Sivvychuckle:BAEALgAECgIJAwABLgAECgcJCwADAAAAAA==.Sivvygrows:BAEALgAECgcJBwABLgAECgcJCwADAAAAAA==.Sivvyrawr:BAEALgAECgcJCwAAAA==.',
Sl='Slammybreath:BAECLgAFFH8JAAMEAAQJ4xNAFABAAQRoDAAAAwArAGkMAAADAEwAawwAAAIAHADqDAAAAQA3AAQABAnjE0AUAEABBGgMAAACACsAaQwAAAMATABrDAAAAgAcAOoMAAABADcABQABCTYBGQwAQwABaAwAAAEAAwAuAAQKfx0AAwQACAloFCIxAD4BAAQABgnOEiIxAD4BAAUACAnaE/ssALQAAAEuAAUUBwkLAAIAaQwA.',
Sp='Spicyhotwing:BAECLgAFFH8LAAMCAAcJaQyJAwDOAQdoDAAAAQAKAGkMAAABAAsAawwAAAEAGwBqDAAAAgAhAGwMAAABAAUAbQwAAAEAWQDqDAAABAAqAAIABgmhCIkDAM4BBmgMAAABAAoAaQwAAAEACwBrDAAAAQAbAGoMAAACACEAbAwAAAEABQDqDAAABAAqAAQAAQmVAYg5AFEAAW0MAAABAAQALgAECn8UAAMCAAgJ6xI8FAACAgACAAgJ6xI8FAACAgAFAAEJfR5+OABVAAAAAA==.',
Ta='Tauntinitis:BAEALgADCgMJAwABLgAFFAMJBgASABIPAA==.',
Te='Tendeyaloran:BAEALgAECgQJBgAAAA==.',
Th='Thanala:BAECLgAFFH8ZAAIBAAYJsiL0AgATAgZoDAAABgBSAGkMAAAGAGEAawwAAAQAWABqDAAAAwBLAGwMAAABAGEA6gwAAAUAWwABAAYJsiL0AgATAgZoDAAABgBSAGkMAAAGAGEAawwAAAQAWABqDAAAAwBLAGwMAAABAGEA6gwAAAUAWwAuAAQKfxwAAgEACAlhHnwUAG4CAAEACAlhHnwUAG4CAAAA.',
Tr='Trintu:BAEALgAECgkJAwABLgAFFAUJDwAVAA8RAA==.',
Yo='Yoktuah:BAEBLgAFFH8FAAMBAAQJ6gPEDQD9AARoDAAAAgAAAGkMAAABABwAawwAAAEACgDqDAAAAQAAAAEABAnqA8QNAP0ABGgMAAABAAAAaQwAAAEAHABrDAAAAQAKAOoMAAABAAAAGwABCRgRmzEAUgABaAwAAAEAKwABLgAFFAQJCgAHAKAQAA==.',
Yu='Yungdh:BAEBLgAECn8UAAIJAAcJmxttHwDVAQdoDAAAAwA8AGkMAAADAEwAawwAAAQAPwBqDAAAAwBOAGwMAAADAEkAbQwAAAEAPADqDAAAAwBYAAkABwmbG20fANUBB2gMAAADADwAaQwAAAMATABrDAAABAA/AGoMAAADAE4AbAwAAAMASQBtDAAAAQA8AOoMAAADAFgAAS4ABRQGCR8AIwB0JgA=.Yungdrood:BAECLgAFFH8fAAIjAAYJdCYxAQAuAgZoDAAABgBjAGkMAAAHAGMAawwAAAYAYwBqDAAABQBhAGwMAAACAF4A6gwAAAUAYgAjAAYJdCYxAQAuAgZoDAAABgBjAGkMAAAHAGMAawwAAAYAYwBqDAAABQBhAGwMAAACAF4A6gwAAAUAYgAuAAQKfy4AAiMACQnTJkECAJ8DACMACQnTJkECAJ8DAAAA.Yungmonk:BAEALgAECgQJBAABLgAFFAYJHwAjAHQmAA==.Yungwizard:BAEBLgAECn8WAAIPAAYJ2iXeOQCOAgZoDAAABABfAGkMAAAEAGIAawwAAAQAXwBqDAAAAwBhAGwMAAAEAGEA6gwAAAMAYQAPAAYJ2iXeOQCOAgZoDAAABABfAGkMAAAEAGIAawwAAAQAXwBqDAAAAwBhAGwMAAAEAGEA6gwAAAMAYQABLgAFFAYJHwAjAHQmAA==.',
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
