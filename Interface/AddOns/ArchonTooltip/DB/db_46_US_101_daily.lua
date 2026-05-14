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

local lookup = {'Warrior-Protection','Hunter-BeastMastery','Shaman-Restoration','Priest-Discipline','Monk-Mistweaver','Unknown-Unknown','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Rogue-Assassination','Warlock-Affliction','Paladin-Retribution','DeathKnight-Unholy','DemonHunter-Devourer','Druid-Restoration','Shaman-Elemental','Druid-Guardian','Priest-Holy','Monk-Brewmaster','DemonHunter-Havoc','Monk-Windwalker','DeathKnight-Blood','Warlock-Demonology','DemonHunter-Vengeance','Druid-Balance','Priest-Shadow','Druid-Feral','Hunter-Marksmanship','Hunter-Survival','Paladin-Holy','Warlock-Destruction','Paladin-Protection','Warrior-Fury','Shaman-Enhancement','Mage-Arcane','Mage-Frost',}
local provider = {region='US',realm='Galakrond',name='US',type='daily',zone=46,date='2026-05-13',data={Ae='Aegisthal:BAABLgAECn8XAAIBAAgJcRuxBwAdAghoDAAAAwBYAGkMAAADAFMAawwAAAMAQABqDAAAAwBOAGwMAAADAC4AbQwAAAIAOADqDAAABABRAG4MAAACAEYAAQAICXEbsQcAHQIIaAwAAAMAWABpDAAAAwBTAGsMAAADAEAAagwAAAMATgBsDAAAAwAuAG0MAAACADgA6gwAAAQAUQBuDAAAAgBGAAAA.Aequitasx:BAAALgAECgcJCQAAAA==.Aeristella:BAAALgADCgcJBwAAAA==.',
Ah='Ahrus:BAAALgADCgMJBgABLgAECggJJAACAEMLAA==.',
Al='Alanerazza:BAAALgADCgYJBgAAAA==.Althenzdormu:BAAALgAECgcJEwAAAA==.Altruist:BAAALgAECgYJEAABLgAECgcJJgABAO4ZAA==.',
Am='Amaethon:BAAALgAECgYJDgAAAA==.',
An='Ancaera:BAAALgADCgcJBwAAAA==.Andalikus:BAABLgAECn8nAAIDAAgJ0h/GCQCvAghoDAAABwBYAGkMAAAHAFIAawwAAAYAVABqDAAABQBLAGwMAAAEAFgAbQwAAAIAUQDqDAAABQBaAG4MAAADAD0AAwAICdIfxgkArwIIaAwAAAcAWABpDAAABwBSAGsMAAAGAFQAagwAAAUASwBsDAAABABYAG0MAAACAFEA6gwAAAUAWgBuDAAAAwA9AAAA.Andorra:BAAALgADCgUJBAAAAA==.Andïea:BAAALgADCgEJAQAAAA==.Anrien:BAABLgAECn8mAAIEAAcJDh/0CABuAgdoDAAABgBPAGkMAAAGAE4AawwAAAYAUQBqDAAABQBZAGwMAAAFAE4A6gwAAAYAUgBuDAAABABCAAQABwkOH/QIAG4CB2gMAAAGAE8AaQwAAAYATgBrDAAABgBRAGoMAAAFAFkAbAwAAAUATgDqDAAABgBSAG4MAAAEAEIAAAA=.',
Ar='Arathor:BAAALgAECgYJCgAAAA==.Ari:BAABLgAECn8WAAIFAAgJTAgWOwD6AAhoDAAABQBBAGkMAAADAAEAawwAAAMACgBqDAAAAgAPAGwMAAACACMAbQwAAAEABADqDAAABQAeAG4MAAABAAcABQAICUwIFjsA+gAIaAwAAAUAQQBpDAAAAwABAGsMAAADAAoAagwAAAIADwBsDAAAAgAjAG0MAAABAAQA6gwAAAUAHgBuDAAAAQAHAAAA.Ariany:BAAALgADCgcJBwAAAA==.Ariyia:BAAALgAECgYJEgAAAA==.Arms:BAAALgAECgEJAQABLgAECgQJCwAGAAAAAA==.',
As='Asgorath:BAAALgADCgQJBAAAAA==.Asharal:BAABLgAECn8mAAQHAAcJuRbzBQCRAQdoDAAABgBOAGkMAAAGADsAawwAAAYAMABqDAAABQBNAGwMAAAFAEEA6gwAAAYAMgBuDAAABAAtAAcABwm5FvMFAJEBB2gMAAAGAE4AaQwAAAYAOwBrDAAABgAwAGoMAAAEAE0AbAwAAAQAQQDqDAAABQAyAG4MAAABAC0ACAAECacUIRYA/wAEagwAAAEAIABsDAAAAQBBAOoMAAABAEUAbgwAAAIALAAJAAEJsQPLawAnAAFuDAAAAQAJAAAA.Ashlayah:BAAALgAECgYJBwAAAA==.',
Au='Aunyx:BAABLgAECn8mAAIKAAcJLw2DCABjAQdoDAAABgAmAGkMAAAGABwAawwAAAYAHgBqDAAABQAhAGwMAAAFACQA6gwAAAYANQBuDAAABAAPAAoABwkvDYMIAGMBB2gMAAAGACYAaQwAAAYAHABrDAAABgAeAGoMAAAFACEAbAwAAAUAJADqDAAABgA1AG4MAAAEAA8AAAA=.',
Az='Azbogah:BAAALgADCgkJEAAAAA==.',
Ba='Babyjack:BAAALgADCgcJCAABLgAECgYJFAALAGkVAA==.Balthenor:BAACLgAFFH8GAAIMAAIJqxMpIgCoAAJoDAAAAwAqAGkMAAADADkADAACCasTKSIAqAACaAwAAAMAKgBpDAAAAwA5AC4ABAp/HgACDAAICf4hkxEABAMADAAICf4hkxEABAMAAAA=.',
Be='Beej:BAABLgAECn8WAAIFAAkJAxIYEgD4AQloDAAAAwBGAGkMAAADADgAawwAAAMAOABqDAAAAgAvAGwMAAADACUAbQwAAAIALQDqDAAABAAtAG4MAAABAA8AbwwAAAEAJwAFAAkJAxIYEgD4AQloDAAAAwBGAGkMAAADADgAawwAAAMAOABqDAAAAgAvAGwMAAADACUAbQwAAAIALQDqDAAABAAtAG4MAAABAA8AbwwAAAEAJwAAAA==.Belenjan:BAAALgAECgYJCwAAAA==.Belestius:BAAALgADCgYJCwABLgADCgkJGAAGAAAAAA==.Berse:BAAALgAECgcJEwAAAA==.',
Bi='Bilko:BAAALgADCgEJAQAAAA==.Birdymage:BAAALgAECgUJEQAAAA==.',
Bl='Blightbeard:BAAALgAECgYJEwAAAA==.Blîss:BAAALgADCggJDQAAAA==.',
Bo='Bolong:BAAALgAECgMJAwABLgAFFAUJGQANAH8UAA==.Bonebroth:BAAALgAECgMJAwAAAA==.Bonehealer:BAAALgADCgcJCgAAAA==.',
Br='Brut:BAABLgAECn8YAAIOAAgJdx0EOQAQAghoDAAABABbAGkMAAAFAEgAawwAAAQAQQBqDAAAAwBeAGwMAAACAFUAbQwAAAEAPgDqDAAAAwBMAG4MAAACAEgADgAICXcdBDkAEAIIaAwAAAQAWwBpDAAABQBIAGsMAAAEAEEAagwAAAMAXgBsDAAAAgBVAG0MAAABAD4A6gwAAAMATABuDAAAAgBIAAAA.',
Bu='Bustus:BAABLgAECn8jAAIPAAcJeg7qOwA/AQdoDAAABQApAGkMAAAFADwAawwAAAUAIwBqDAAABQAoAGwMAAAFABUA6gwAAAYAJABuDAAABAAXAA8ABwl6Duo7AD8BB2gMAAAFACkAaQwAAAUAPABrDAAABQAjAGoMAAAFACgAbAwAAAUAFQDqDAAABgAkAG4MAAAEABcAAAA=.',
Ca='Carmasutra:BAAALgADCgYJBQAAAA==.Caroll:BAAALgAECgUJBgAAAA==.Carsomavra:BAAALgADCggJFQAAAA==.Cathercy:BAAALgAECgUJDgAAAA==.',
Ch='Chenzhen:BAAALgADCgYJBgAAAA==.Chilly:BAAALgAECgYJDgABLgAFFAMJAwAGAAAAAA==.Chunt:BAAALgAECgIJAgAAAA==.',
Co='Compliance:BAABLgAECn8mAAIBAAcJ7hm7DACuAQdoDAAABgBHAGkMAAAGADwAawwAAAYAMgBqDAAABQBIAGwMAAAFAEYA6gwAAAYAUgBuDAAABAA/AAEABwnuGbsMAK4BB2gMAAAGAEcAaQwAAAYAPABrDAAABgAyAGoMAAAFAEgAbAwAAAUARgDqDAAABgBSAG4MAAAEAD8AAAA=.Corannis:BAABLgAECn8aAAIQAAcJ6RNLHwByAQdoDAAAAwBHAGkMAAAEAEMAawwAAAQALABqDAAABABBAGwMAAAEAC8A6gwAAAQALgBuDAAAAwAcABAABwnpE0sfAHIBB2gMAAADAEcAaQwAAAQAQwBrDAAABAAsAGoMAAAEAEEAbAwAAAQALwDqDAAABAAuAG4MAAADABwAAAA=.Cowabunga:BAAALgADCgkJCQABLgAECgkJJAARAJwQAA==.',
Cr='Cranberries:BAABLgAECn8UAAMSAAcJEBd/FwCvAQdoDAAABABbAGkMAAAEAE4AawwAAAMAQQBqDAAAAgBOAGwMAAACADAA6gwAAAQAIQBuDAAAAQARABIABgmnGH8XAK8BBmgMAAADAFsAaQwAAAMATgBrDAAAAgBBAGoMAAABAE4AbAwAAAEAMADqDAAAAwAQAAQABwljD9IaAHgBB2gMAAABACYAaQwAAAEALQBrDAAAAQA0AGoMAAABACkAbAwAAAEALgDqDAAAAQAhAG4MAAABABEAAAA=.Crockett:BAAALgADCgIJAgABLgAECgUJCwAGAAAAAA==.',
Cu='Curtis:BAAALgAECgYJDQABLgAECggJGAATAMgaAA==.',
Da='Daberserker:BAAALgADCgUJBQAAAA==.Dalmas:BAAALgAECgMJBQAAAA==.Dalra:BAAALgADCgUJBQABLgAECggJMAAUACwVAA==.Darkgenie:BAAALgADCgEJAgAAAA==.Darlàrk:BAABLgAECn8bAAIOAAcJQhqFKAC1AQdoDAAABQBHAGkMAAAFAD0AawwAAAUAKgBqDAAABAAqAGwMAAADAD8AbQwAAAEAUADqDAAABABTAA4ABwlCGoUoALUBB2gMAAAFAEcAaQwAAAUAPQBrDAAABQAqAGoMAAAEACoAbAwAAAMAPwBtDAAAAQBQAOoMAAAEAFMAAAA=.',
De='Delderach:BAAALgAECgUJDgAAAA==.Delosine:BAAALgADCgUJCgAAAA==.Demise:BAAALgADCgMJAwAAAA==.Denîn:BAABLgAECn8kAAINAAcJbhgJNwC5AQdoDAAABgBHAGkMAAAGAEYAawwAAAYAOgBqDAAABQBdAGwMAAAFAD0AbQwAAAIAJADqDAAABgBMAA0ABwluGAk3ALkBB2gMAAAGAEcAaQwAAAYARgBrDAAABgA6AGoMAAAFAF0AbAwAAAUAPQBtDAAAAgAkAOoMAAAGAEwAAAA=.',
Di='Dirkette:BAABLgAECn8iAAIEAAgJ+QOsJQAfAQhoDAAABgAJAGkMAAAGABUAawwAAAUACwBqDAAABAAKAGwMAAAEAAcAbQwAAAIABgDqDAAABAAJAG4MAAADAAQABAAICfkDrCUAHwEIaAwAAAYACQBpDAAABgAVAGsMAAAFAAsAagwAAAQACgBsDAAABAAHAG0MAAACAAYA6gwAAAQACQBuDAAAAwAEAAAA.Dirknelf:BAAALgADCgEJAQABLgAECggJIgAEAPkDAA==.Dirksavoid:BAAALgAECgUJBQABLgAECggJIgAEAPkDAA==.Dixonmayas:BAAALgAECgYJDAAAAA==.',
Do='Dokai:BAABLgAECn8iAAIVAAcJAhmfEgC3AQdoDAAABAA8AGkMAAAFADcAawwAAAYAQwBqDAAABQA4AGwMAAAFAEoA6gwAAAUAPgBuDAAABABAABUABwkCGZ8SALcBB2gMAAAEADwAaQwAAAUANwBrDAAABgBDAGoMAAAFADgAbAwAAAUASgDqDAAABQA+AG4MAAAEAEAAAAA=.',
Dr='Dracmiz:BAAALgADCgYJBgAAAA==.Dragenous:BAAALgAECgMJAwAAAA==.Dragmartigan:BAAALgAECgQJCQABLgAECgUJBQAGAAAAAA==.Dragoran:BAAALgAECgUJBQAAAA==.Drewella:BAAALgADCgcJBwAAAA==.',
El='Elaenei:BAAALgADCggJFAAAAA==.Eliance:BAAALgAECgUJDgAAAA==.Elienn:BAAALgADCgcJBwAAAA==.Elsewhere:BAABLgAECn8XAAIJAAgJAA38HwBYAQhoDAAABAAyAGkMAAADACYAawwAAAMAEwBqDAAAAwAjAGwMAAAEACUAbQwAAAEAGwDqDAAABAAgAG4MAAABABoACQAICQAN/B8AWAEIaAwAAAQAMgBpDAAAAwAmAGsMAAADABMAagwAAAMAIwBsDAAABAAlAG0MAAABABsA6gwAAAQAIABuDAAAAQAaAAAA.',
Em='Emmily:BAAALgADCgYJDAAAAA==.',
En='Enuia:BAAALgADCgUJBQAAAA==.',
Er='Eririn:BAAALgAECgEJAgAAAA==.Errius:BAABLgAECn8fAAIWAAgJ8RQQEgBzAQhoDAAABQArAGkMAAAFADkAawwAAAUANQBqDAAAAwAgAGwMAAAEADMAbQwAAAEAMQDqDAAABgBCAG4MAAACADYAFgAICfEUEBIAcwEIaAwAAAUAKwBpDAAABQA5AGsMAAAFADUAagwAAAMAIABsDAAABAAzAG0MAAABADEA6gwAAAYAQgBuDAAAAgA2AAAA.',
Eu='Eunja:BAEALgAECgYJBgAAAQ==.',
Ev='Evangelica:BAAALgAECgMJAwAAAA==.',
Fe='Feeltheburn:BAAALgAECgYJBgAAAA==.Feloras:BAAALgAECgUJBQAAAA==.',
Fu='Fusaa:BAABLgAECn8gAAIXAAgJshP9LwC4AQhoDAAABgA0AGkMAAAFADUAawwAAAUAOABqDAAABAAyAGwMAAAEAEQAbQwAAAIAHwDqDAAABQArAG4MAAABADAAFwAICbIT/S8AuAEIaAwAAAYANABpDAAABQA1AGsMAAAFADgAagwAAAQAMgBsDAAABABEAG0MAAACAB8A6gwAAAUAKwBuDAAAAQAwAAAA.',
Ga='Gangry:BAAALgAECgQJCQAAAA==.',
Ge='Gelst:BAAALgADCgUJBQAAAA==.Gerbzarrion:BAAALgAECgUJDgAAAA==.Gerudo:BAAALgAECgQJBAAAAA==.',
Gi='Gilgador:BAABLgAECn8wAAIUAAgJLBV+DADZAQhoDAAACABHAGkMAAAIAEEAawwAAAcAPgBqDAAABQBBAGwMAAAHADYAbQwAAAQAPQDqDAAABgArAG4MAAADABMAFAAICSwVfgwA2QEIaAwAAAgARwBpDAAACABBAGsMAAAHAD4AagwAAAUAQQBsDAAABwA2AG0MAAAEAD0A6gwAAAYAKwBuDAAAAwATAAAA.',
Go='Gord:BAAALgADCgYJBgAAAA==.',
Gr='Gravewalker:BAAALgAECgYJCgAAAA==.Gream:BAAALgADCgcJCgAAAA==.Greepster:BAAALgAECgYJEwAAAA==.',
Ha='Haggrum:BAAALgADCgIJAgAAAA==.Haley:BAAALgAECgEJAQABLgAECgQJCwAGAAAAAA==.Hawknnin:BAAALgAECgUJCwAAAA==.',
He='Hectorjbm:BAAALgADCgMJBAAAAA==.',
Hu='Hunterpulled:BAAALgAECgcJBwAAAA==.Huntrod:BAAALgADCgEJBQAAAA==.Huroona:BAAALgADCgcJEAAAAA==.Huskiè:BAAALgADCgYJDAAAAA==.',
Hy='Hyasinth:BAAALgADCgQJBAABLgAECgkJFAASABAXAA==.',
Ip='Ipwnallnoobs:BAABLgAECn8VAAINAAgJEQyDRACJAQhoDAAAAwAhAGkMAAADACYAawwAAAMAJwBqDAAAAwAWAGwMAAAEACIAbQwAAAEAKgDqDAAAAwAPAG4MAAABAAwADQAICREMg0QAiQEIaAwAAAMAIQBpDAAAAwAmAGsMAAADACcAagwAAAMAFgBsDAAABAAiAG0MAAABACoA6gwAAAMADwBuDAAAAQAMAAAA.',
Ir='Irisila:BAAALgAECgEJAQABLgAECgQJCAAGAAAAAA==.Ironfists:BAAALgADCgMJAwAAAA==.',
Ja='Jagel:BAAALgADCgQJBAAAAA==.Jahkwellynn:BAAALgADCgEJAQAAAA==.Jairian:BAAALgADCgkJCQAAAA==.Jakoti:BAAALgADCgUJCQAAAA==.Jaxsi:BAAALgAECgQJCwAAAA==.Jaypharyn:BAAALgAECgcJEwAAAA==.',
Jo='Johalea:BAAALgADCgYJBQAAAA==.',
['Jå']='Jåsper:BAAALgAECgcJDQAAAA==.',
Ka='Kaileena:BAABLgAECn8kAAIYAAgJ0hdKBQDgAQhoDAAABgBDAGkMAAAGAD4AawwAAAYAUQBqDAAABQBPAGwMAAAEADgAbQwAAAIASgDqDAAABQAlAG4MAAACAC8AGAAICdIXSgUA4AEIaAwAAAYAQwBpDAAABgA+AGsMAAAGAFEAagwAAAUATwBsDAAABAA4AG0MAAACAEoA6gwAAAUAJQBuDAAAAgAvAAAA.Kaimare:BAAALgADCgUJBgAAAA==.Kandistars:BAABLgAECn8cAAIZAAgJIgzJIABLAQhoDAAABQAtAGkMAAAFACoAawwAAAQAFABqDAAAAgAnAGwMAAADACsAbQwAAAEADQDqDAAABgAgAG4MAAACABIAGQAICSIMySAASwEIaAwAAAUALQBpDAAABQAqAGsMAAAEABQAagwAAAIAJwBsDAAAAwArAG0MAAABAA0A6gwAAAYAIABuDAAAAgASAAAA.Kasia:BAAALgAECgcJEwAAAA==.',
Kh='Kharnas:BAAALgADCgYJCQAAAA==.',
Ki='Kierrings:BAABLgAECn8ZAAINAAgJiBb7LgDbAQhoDAAABQBYAGkMAAAFAEYAawwAAAUASABqDAAAAgA8AGwMAAACABkAbQwAAAEAIgDqDAAABABHAG4MAAABACkADQAICYgW+y4A2wEIaAwAAAUAWABpDAAABQBGAGsMAAAFAEgAagwAAAIAPABsDAAAAgAZAG0MAAABACIA6gwAAAQARwBuDAAAAQApAAAA.Kirarah:BAABLgAECn8hAAICAAcJmSO2EABqAgdoDAAABgBeAGkMAAAFAFoAawwAAAUAVgBqDAAABABfAGwMAAAEAF4A6gwAAAYAYABuDAAAAwBTAAIABwmZI7YQAGoCB2gMAAAGAF4AaQwAAAUAWgBrDAAABQBWAGoMAAAEAF8AbAwAAAQAXgDqDAAABgBgAG4MAAADAFMAAAA=.Kirarose:BAACLgAFFH8NAAMaAAQJfBA/DgA+AQRoDAAABQAtAGkMAAAEADYAawwAAAIAEwDqDAAAAgAwABoABAl8ED8OAD4BBGgMAAAEAC0AaQwAAAQANgBrDAAAAgATAOoMAAABADAAEgACCdoBrR4AYgACaAwAAAEAAADqDAAAAQAIAC4ABAp/FQADGgAHCd4dYRYANQIAGgAHCd4dYRYANQIAEgADCYQJbGgAiwAAAAA=.Kitcarson:BAAALgADCgUJCAAAAA==.',
Kl='Klauss:BAABLgAECn8hAAIFAAgJhw+0GgCbAQhoDAAABgBUAGkMAAAGACsAawwAAAUAPQBqDAAABAApAGwMAAADABkAbQwAAAIACQDqDAAABAAiAG4MAAADABMABQAICYcPtBoAmwEIaAwAAAYAVABpDAAABgArAGsMAAAFAD0AagwAAAQAKQBsDAAAAwAZAG0MAAACAAkA6gwAAAQAIgBuDAAAAwATAAAA.Klax:BAAALgAECgYJCgAAAA==.',
Ko='Kordjin:BAAALgADCgIJAgAAAA==.',
Kr='Krornik:BAAALgADCgkJGAAAAA==.',
Ky='Kylia:BAAALgAECgYJEAAAAA==.',
['Kí']='Kíhanna:BAABLgAECn8gAAICAAgJLiBgEgBbAghoDAAABgBaAGkMAAAGAF8AawwAAAQAUwBqDAAABABVAGwMAAADAD0AbQwAAAIAVgDqDAAABABZAG4MAAADAEUAAgAICS4gYBIAWwIIaAwAAAYAWgBpDAAABgBfAGsMAAAEAFMAagwAAAQAVQBsDAAAAwA9AG0MAAACAFYA6gwAAAQAWQBuDAAAAwBFAAAA.',
La='Larissa:BAAALgAECgYJDAAAAA==.',
Le='Legenddairy:BAABLgAECn8kAAMRAAkJnBABDwBQAQloDAAABQAyAGkMAAAFADkAawwAAAUAKQBqDAAABQA5AGwMAAAFACkAbQwAAAMAJwDqDAAABQA0AG4MAAACACAAbwwAAAEAFgAZAAkJBg/xLwCIAQloDAAABAAkAGkMAAADADEAawwAAAMAKQBqDAAABAAxAGwMAAAEACkAbQwAAAIAHQDqDAAABAA0AG4MAAABACAAbwwAAAEAFgARAAgJcA4BDwBQAQhoDAAAAQAyAGkMAAACADkAawwAAAIAJABqDAAAAQA5AGwMAAABABMAbQwAAAEAJwDqDAAAAQAlAG4MAAABABAAAAA=.',
Li='Lizardath:BAABLgAECn8gAAICAAgJAQqoQwBdAQhoDAAABgAmAGkMAAAFABsAawwAAAUAEwBqDAAABAAZAGwMAAAEACsAbQwAAAEABwDqDAAABgAVAG4MAAABABUAAgAICQEKqEMAXQEIaAwAAAYAJgBpDAAABQAbAGsMAAAFABMAagwAAAQAGQBsDAAABAArAG0MAAABAAcA6gwAAAYAFQBuDAAAAQAVAAAA.',
Lj='Ljósálfr:BAABLgAECn8qAAIBAAgJBiPTAwCUAghoDAAABwBfAGkMAAAGAFwAawwAAAYAWwBqDAAABgBVAGwMAAAGAF4AbQwAAAIAUADqDAAABgBeAG4MAAADAE0AAQAICQYj0wMAlAIIaAwAAAcAXwBpDAAABgBcAGsMAAAGAFsAagwAAAYAVQBsDAAABgBeAG0MAAACAFAA6gwAAAYAXgBuDAAAAwBNAAAA.',
Lo='Lochramae:BAABLgAECn8nAAIWAAcJKBf6FABMAQdoDAAABwBAAGkMAAAHADMAawwAAAcASgBqDAAABQAyAGwMAAAFADcAbQwAAAIAOADqDAAABgA2ABYABwkoF/oUAEwBB2gMAAAHAEAAaQwAAAcAMwBrDAAABwBKAGoMAAAFADIAbAwAAAUANwBtDAAAAgA4AOoMAAAGADYAAAA=.Logarius:BAAALgADCgQJBAAAAA==.Loupe:BAAALgADCgYJBwAAAA==.',
Lu='Lumanoughty:BAAALgADCggJFAAAAA==.Lunargaze:BAABLgAECn8aAAIOAAcJSCCIFQAuAgdoDAAABABfAGkMAAAEAEsAawwAAAQAVgBqDAAAAwBiAGwMAAAFAEkAbQwAAAIAUwDqDAAABABRAA4ABwlIIIgVAC4CB2gMAAAEAF8AaQwAAAQASwBrDAAABABWAGoMAAADAGIAbAwAAAUASQBtDAAAAgBTAOoMAAAEAFEAAAA=.',
Ly='Lyssena:BAAALgAECgUJBQAAAA==.',
Ma='Madmartigan:BAAALgADCgYJBgABLgAECgUJBQAGAAAAAA==.Mahangi:BAAALgADCgkJEAAAAA==.Mamimisan:BAABLgAECn8eAAIDAAgJnR4aCwCbAghoDAAABgBSAGkMAAAGAFEAawwAAAUARgBqDAAABABRAGwMAAAEAFoAbQwAAAEARgDqDAAAAwBMAG4MAAABAEoAAwAICZ0eGgsAmwIIaAwAAAYAUgBpDAAABgBRAGsMAAAFAEYAagwAAAQAUQBsDAAABABaAG0MAAABAEYA6gwAAAMATABuDAAAAQBKAAAA.',
Me='Meatball:BAAALgADCgYJBgAAAA==.Mecaris:BAAALgAECgYJBgABLgAFFAIJBgAMAKsTAA==.Medios:BAAALgAECgYJBwAAAA==.Metalicfox:BAAALgADCgQJBQAAAA==.',
Mi='Mitsumi:BAAALgAECgUJDQAAAA==.Miz:BAAALgAECgYJDwAAAA==.Mizkat:BAABLgAECn8eAAQRAAgJSRn1BwDhAQhoDAAABQBIAGkMAAAFAFIAawwAAAQARgBqDAAABAAxAGwMAAAEAEsAbQwAAAIAKgDqDAAABABGAG4MAAACACYAEQAICUkZ9QcA4QEIaAwAAAUASABpDAAABQBSAGsMAAAEAEYAagwAAAMAMQBsDAAAAwBLAG0MAAACACoA6gwAAAMARgBuDAAAAgAmABsAAQlLDl0tADYAAWwMAAABACQADwACCRwNm88ALwACagwAAAEAEwDqDAAAAQAwAAAA.',
Mo='Mojomoe:BAAALgADCggJCAAAAA==.Mormra:BAABLgAECn8kAAMCAAgJQwvuPwBrAQhoDAAACAAvAGkMAAAGAC8AawwAAAYALQBqDAAABAAhAGwMAAAEABMAbQwAAAIACADqDAAABAAQAG4MAAACABEAAgAICUML7j8AawEIaAwAAAcALwBpDAAABgAvAGsMAAAGAC0AagwAAAQAIQBsDAAABAATAG0MAAACAAgA6gwAAAQAEABuDAAAAgARABwAAQnVATIxAB4AAWgMAAABAAQAAAA=.',
Mu='Mushroom:BAAALgADCgYJCQAAAA==.Mustard:BAEBLgAECn8rAAQdAAcJ5yUhBQCEAgdoDAAACABiAGkMAAAGAGAAawwAAAYAYQBqDAAABgBjAGwMAAAGAF0A6gwAAAYAYwBuDAAABQBgAB0ABwniJCEFAIQCB2gMAAAGAGIAaQwAAAQAYABrDAAABQBcAGoMAAAFAGIAbAwAAAMAUgDqDAAABABjAG4MAAAFAGAAAgAFCdIkDC8ArAEFaAwAAAIAXgBpDAAAAQBbAGsMAAABAGEAagwAAAEAYwDqDAAAAgBdABwAAgn9I9ATAM4AAmkMAAABAFoAbAwAAAMAXQAAAA==.',
['Më']='Mërcy:BAAALgADCgcJBwAAAA==.',
Na='Naklus:BAAALgAECgUJBQAAAA==.Nathan:BAAALgADCgcJBwAAAA==.',
Ne='Neilia:BAAALgAECggJDAABLgAECggJMAAUACwVAA==.Nekra:BAAALgAECgEJAQAAAA==.Nezot:BAAALgADCgEJAQAAAA==.',
Ni='Nixilia:BAAALgADCgUJBQAAAA==.',
Nl='Nlani:BAAALgAECgYJCgAAAA==.',
Nu='Nuvi:BAAALgAECgMJAwAAAA==.',
Or='Orihime:BAAALgADCgEJAQAAAA==.',
Ox='Oxygentank:BAAALgAECgQJBwAAAA==.',
Pa='Parne:BAAALgADCgUJBQAAAA==.',
Ph='Phatbutfun:BAAALgADCgMJAwAAAA==.',
Pi='Pips:BAAALgADCgcJBwAAAA==.',
Pl='Platura:BAABLgAECn8bAAIeAAcJVRiSGgDNAQdoDAAABQBDAGkMAAAEAEsAawwAAAQAOwBqDAAAAwAzAGwMAAAEAEgA6gwAAAQAKQBuDAAAAwBDAB4ABwlVGJIaAM0BB2gMAAAFAEMAaQwAAAQASwBrDAAABAA7AGoMAAADADMAbAwAAAQASADqDAAABAApAG4MAAADAEMAAAA=.Plection:BAAALgADCgEJAQAAAA==.',
Ra='Raezune:BAAALgADCgMJAwAAAA==.Rajia:BAABLgAECn8mAAIfAAcJ6RD5CQBIAQdoDAAABgA+AGkMAAAGACgAawwAAAYAJABqDAAABQAmAGwMAAAFABwA6gwAAAYAQgBuDAAABAAZAB8ABwnpEPkJAEgBB2gMAAAGAD4AaQwAAAYAKABrDAAABgAkAGoMAAAFACYAbAwAAAUAHADqDAAABgBCAG4MAAAEABkAAAA=.Rassaphore:BAAALgAECgUJDQAAAA==.Raziik:BAAALgADCgYJBgAAAA==.Raínbow:BAAALgAECgEJAQAAAA==.',
Re='Reapin:BAAALgAECgcJEwAAAA==.',
Ri='Rilorren:BAAALgADCgcJCgABLgAECggJGAAOAHcdAA==.Rionach:BAABLgAECn8mAAIRAAcJDwijHACzAAdoDAAABgARAGkMAAAGAA4AawwAAAYAFwBqDAAABQASAGwMAAAFABoA6gwAAAYAIABuDAAABAAKABEABwkPCKMcALMAB2gMAAAGABEAaQwAAAYADgBrDAAABgAXAGoMAAAFABIAbAwAAAUAGgDqDAAABgAgAG4MAAAEAAoAAAA=.Ritsara:BAAALgAECgcJDQAAAA==.Riven:BAAALgAECgIJAgABLgAECgYJCgAGAAAAAA==.Rivon:BAABLgAECn8aAAIeAAYJORfRJgBtAQZoDAAABgBIAGkMAAAGAD0AawwAAAUARABqDAAAAwAxAGwMAAACAA4A6gwAAAQAWgAeAAYJORfRJgBtAQZoDAAABgBIAGkMAAAGAD0AawwAAAUARABqDAAAAwAxAGwMAAACAA4A6gwAAAQAWgAAAA==.Rivonsshield:BAAALgADCgYJBgAAAA==.',
Ro='Ro:BAAALgADCgYJBgAAAA==.Rothu:BAAALgAECgUJBwABLgAECgcJGQAOAJ0cAA==.Rowena:BAAALgADCgYJBgAAAA==.',
Ru='Ruka:BAAALgAECgEJAQAAAA==.',
Sa='Salenias:BAAALgADCgkJDAAAAA==.Sannicor:BAAALgADCgEJAQAAAA==.Saonji:BAAALgADCgcJDgAAAA==.',
Sc='Scoop:BAAALgAECgMJBQAAAA==.',
Se='Seanx:BAABLgAECn8gAAMMAAgJfh4AFQBrAghoDAAABwBCAGkMAAAFAFIAawwAAAUAWgBqDAAABABRAGwMAAADAEMAbQwAAAIAXADqDAAABQBZAG4MAAABADgADAAICX4eABUAawIIaAwAAAYAQgBpDAAABABSAGsMAAAEAFoAagwAAAMAOQBsDAAAAgBDAG0MAAACAFwA6gwAAAQAWQBuDAAAAQA4ACAABgmGEqgVAAoBBmgMAAABAB8AaQwAAAEANQBrDAAAAQA0AGoMAAABAFEAbAwAAAEAIgDqDAAAAQBAAAAA.',
Sh='Shenlong:BAABLgAFFH8FAAINAAIJrhk8ewCjAAJoDAAAAwBJAOoMAAACADoADQACCa4ZPHsAowACaAwAAAMASQDqDAAAAgA6AAAA.Shigurexx:BAABLgAECn8kAAMCAAgJbx6dEQBiAghoDAAABgBCAGkMAAAGAFUAawwAAAUARQBqDAAABQBBAGwMAAAFAEQAbQwAAAIAXQDqDAAABQBYAG4MAAACAEkAAgAICW8enREAYgIIaAwAAAIAQgBpDAAAAgBVAGsMAAACAEUAagwAAAIAQQBsDAAAAgBEAG0MAAACAF0A6gwAAAMAWABuDAAAAgBJABwABgltEpgUAMYABmgMAAAEAC0AaQwAAAQAQgBrDAAAAwAlAGoMAAADAC4AbAwAAAMALADqDAAAAgAoAAAA.Shoe:BAABLgAECn8yAAMHAAkJ+xuHAQCHAgloDAAABwBbAGkMAAAIAFUAawwAAAgAUABqDAAABgBgAGwMAAAFAEkAbQwAAAQAOwDqDAAABwBQAG4MAAADACkAbwwAAAIAPAAHAAkJ+xuHAQCHAgloDAAABgBbAGkMAAAHAFUAawwAAAcAUABqDAAABgBgAGwMAAAFAEkAbQwAAAMAOwDqDAAABgBQAG4MAAACACkAbwwAAAIAPAAJAAYJmRBDHQBtAQZoDAAAAQA3AGkMAAABADoAawwAAAEALwBtDAAAAQAYAOoMAAABADAAbgwAAAEAEwAAAA==.Shootup:BAAALgADCgYJBgAAAA==.',
Si='Sigmandis:BAAALgAECgcJDQAAAA==.Siph:BAAALgAECgYJBgAAAA==.',
Sk='Sklook:BAAALgAECgEJAQAAAA==.Skolam:BAAALgADCgYJDAAAAA==.',
So='Somassen:BAAALgADCgcJEQAAAA==.Sorrengail:BAAALgAECgIJAgAAAA==.Soulforge:BAAALgAECgMJAwAAAA==.',
Sq='Squanchy:BAAALgADCgMJAwAAAA==.',
St='Stalestorn:BAAALgADCgIJAgAAAA==.',
Su='Sunquell:BAAALgAECgMJAwAAAA==.Surii:BAAALgAECgUJCwAAAA==.',
Sw='Sweeneytodd:BAAALgAECgEJAgAAAA==.',
Sy='Sybryn:BAAALgADCgQJBAAAAA==.',
Ta='Taliadrin:BAAALgAECgIJAgAAAA==.Tamarins:BAAALgAECgcJEwAAAA==.Taryeth:BAAALgADCgMJAwAAAA==.',
Te='Terkarakk:BAABLgAECn8aAAIRAAgJsCL0AgCXAghoDAAABQBfAGkMAAAEAFsAawwAAAQAVABqDAAAAwBWAGwMAAADAFMAbQwAAAEAUwDqDAAABABZAG4MAAACAFwAEQAICbAi9AIAlwIIaAwAAAUAXwBpDAAABABbAGsMAAAEAFQAagwAAAMAVgBsDAAAAwBTAG0MAAABAFMA6gwAAAQAWQBuDAAAAgBcAAAA.',
Th='Thetamoon:BAAALgADCgUJBQAAAA==.Thireaux:BAAALgAECgQJBQAAAA==.Thorybos:BAAALgAECgMJBAAAAA==.',
To='Toom:BAAALgAECgUJDgAAAA==.',
Tr='Traylinna:BAAALgADCgQJBAAAAA==.Tritas:BAAALgADCggJEAABLgAECggJMAAUACwVAA==.Trophyhubby:BAABLgAECn8fAAMaAAgJZARKKwAOAQhoDAAABQAFAGkMAAAFAAwAawwAAAUACQBqDAAAAwATAGwMAAAEABIAbQwAAAEACQDqDAAABgANAG4MAAACAAkAGgAICWQESisADgEIaAwAAAIABQBpDAAAAgAMAGsMAAABAAkAagwAAAEAEwBsDAAAAgASAG0MAAABAAkA6gwAAAQADQBuDAAAAgAJABIABgkODTwuAPgABmgMAAADACUAaQwAAAMADABrDAAABAAnAGoMAAACACQAbAwAAAIAEgDqDAAAAgA4AAAA.',
Tu='Tuknark:BAAALgADCgYJBgAAAA==.Tuladrin:BAAALgADCgQJBAAAAA==.',
Ty='Tyeren:BAAALgAECgYJDgAAAA==.Tyeriel:BAACLgAFFH8ZAAMNAAUJfxR0MwBHAQVoDAAABwBLAGkMAAAGAEUAawwAAAQAHABqDAAAAwA3AOoMAAAFACQADQAECX8UdDMARwEEaAwAAAcASwBpDAAABgBFAGsMAAAEABwA6gwAAAUAJAAWAAEJAAAZMQAAAAFqDAAAAwA3AC4ABAp/HwADDQAJCdke2SIAtAIADQAICf8e2SIAtAIAFgADCQwaZR4A7gAAAAA=.Tyrîel:BAAALgADCgcJBwABLgAFFAUJGQANAH8UAA==.',
Us='Usato:BAAALgAECgUJBQAAAA==.',
Va='Valat:BAAALgADCgkJFAAAAA==.Valkyriefall:BAAALgAECgMJBQAAAA==.Valkyriewing:BAAALgAECgUJCAAAAA==.Valvet:BAAALgADCgkJKQAAAA==.Vardanis:BAAALgADCggJDwAAAA==.',
Vi='Vikril:BAAALgAECgYJBwAAAA==.Vincenzo:BAAALgAECgEJAgAAAA==.Vixer:BAAALgAECgQJBgAAAA==.',
Vo='Vog:BAAALgADCgYJBgAAAA==.Voidquèèn:BAAALgADCgEJAQAAAA==.Volkanoth:BAABLgAECn8VAAIOAAcJFSTjJQBvAgdoDAAABABiAGkMAAADAGAAawwAAAMAWgBqDAAAAgBiAGwMAAABAFgAbQwAAAEAVADqDAAABwBfAA4ABwkVJOMlAG8CB2gMAAAEAGIAaQwAAAMAYABrDAAAAwBaAGoMAAACAGIAbAwAAAEAWABtDAAAAQBUAOoMAAAHAF8AAAA=.',
Vu='Vue:BAAALgADCgcJBwABLgAECgYJCgAGAAAAAA==.',
Vy='Vylus:BAAALgAECgQJBAAAAA==.',
['Vá']='Vásh:BAAALgADCggJCAAAAA==.',
We='Weeblewobble:BAAALgADCggJCgAAAA==.',
Wi='Wikidblade:BAAALgAECgQJCAAAAA==.William:BAABLgAECn8UAAICAAcJuh3xHAALAgdoDAAAAwA/AGkMAAADAFcAawwAAAMAQgBqDAAAAwBFAGwMAAADAFQAbQwAAAEAQwDqDAAABABWAAIABwm6HfEcAAsCB2gMAAADAD8AaQwAAAMAVwBrDAAAAwBCAGoMAAADAEUAbAwAAAMAVABtDAAAAQBDAOoMAAAEAFYAAAA=.Windee:BAAALgAECgYJEgAAAA==.',
Wr='Wrast:BAABLgAECn8XAAIcAAcJkgYOEQDwAAdoDAAABQAUAGkMAAAFABoAawwAAAUAHABqDAAAAwAPAGwMAAABAAgAbQwAAAEABwDqDAAAAwAJABwABwmSBg4RAPAAB2gMAAAFABQAaQwAAAUAGgBrDAAABQAcAGoMAAADAA8AbAwAAAEACABtDAAAAQAHAOoMAAADAAkAAAA=.Wravyn:BAAALgADCgcJBwAAAA==.',
Xy='Xyara:BAABLgAECn8eAAQXAAkJ5xfAPQCFAQloDAAABABCAGkMAAADADMAawwAAAUATwBqDAAABABbAGwMAAAFAFsAbQwAAAIAQgDqDAAABAA2AG4MAAACAEIAbwwAAAEADQAXAAYJphLAPQCFAQZoDAAABABCAGkMAAACADMAawwAAAEAIgDqDAAABAA2AG4MAAABAEEAbwwAAAEADQALAAUJmx0LCQA6AQVrDAAAAQBPAGoMAAACAFsAbAwAAAUAWwBtDAAAAgBCAG4MAAABAEIAHwADCaATZjsAxgADaQwAAAEAKwBrDAAAAwA4AGoMAAACADsAAAA=.Xylaara:BAAALgAECgYJBgAAAA==.',
Ya='Yarine:BAAALgAECgEJAQAAAA==.',
Yo='Yoghurt:BAABLgAECn8nAAIhAAgJwyAzCACAAghoDAAABgBdAGkMAAAGAFgAawwAAAUASgBqDAAABQBPAGwMAAAGAFYAbQwAAAIATADqDAAABgBTAG4MAAADAFMAIQAICcMgMwgAgAIIaAwAAAYAXQBpDAAABgBYAGsMAAAFAEoAagwAAAUATwBsDAAABgBWAG0MAAACAEwA6gwAAAYAUwBuDAAAAwBTAAAA.',
Za='Zabimaru:BAAALgADCgYJCgAAAA==.Zalidus:BAABLgAFFH8FAAIiAAMJ9wtOBgDrAANoDAAAAgAdAGkMAAABADQA6gwAAAIACQAiAAMJ9wtOBgDrAANoDAAAAgAdAGkMAAABADQA6gwAAAIACQAAAA==.Zatika:BAABLgAECn8pAAMjAAgJERbsAgC6AQhoDAAACABHAGkMAAAGAEcAawwAAAYAQgBqDAAABgBOAGwMAAAGADwAbQwAAAMALQDqDAAABQBHAG4MAAABAAYAIwAHCbYY7AIAugEHaAwAAAYARwBpDAAABABHAGsMAAAEAEIAagwAAAQATgBsDAAABAAzAG0MAAABAC0A6gwAAAMARwAkAAgJ3g9LSACjAQhoDAAAAgAwAGkMAAACAB8AawwAAAIANgBqDAAAAgBAAGwMAAACADwAbQwAAAIAGwDqDAAAAgA3AG4MAAABAAYAAAA=.',
Ze='Zehnia:BAAALgADCgYJBgAAAA==.',
Zi='Zibzab:BAAALgAECgUJDgAAAA==.',
Zm='Zmija:BAAALgAECgIJAgAAAA==.',
Zo='Zoeya:BAAALgADCgkJCQAAAA==.',
['Él']='Élsa:BAAALgADCgUJBAAAAA==.',
['ßr']='ßristle:BAAALgADCgEJAQAAAA==.',
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
