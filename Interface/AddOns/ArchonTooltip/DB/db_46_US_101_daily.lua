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

local lookup = {'Warrior-Protection','Hunter-BeastMastery','Shaman-Restoration','Priest-Discipline','Monk-Mistweaver','Unknown-Unknown','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Rogue-Assassination','Warlock-Affliction','Paladin-Retribution','DeathKnight-Unholy','DemonHunter-Devourer','Druid-Restoration','Shaman-Elemental','Druid-Guardian','Priest-Holy','Monk-Brewmaster','Monk-Windwalker','DeathKnight-Blood','Warlock-Demonology','DemonHunter-Havoc','DemonHunter-Vengeance','Druid-Balance','Priest-Shadow','Druid-Feral','Hunter-Marksmanship','Hunter-Survival','Paladin-Holy','Warlock-Destruction','Paladin-Protection','Warrior-Fury','Shaman-Enhancement','Mage-Arcane','Mage-Frost',}
local provider = {region='US',realm='Galakrond',name='US',type='daily',zone=46,date='2026-05-12',data={Ae='Aegisthal:BAABLgAECn8XAAIBAAgJcRtRBwAhAghoDAAAAwBYAGkMAAADAFMAawwAAAMAQABqDAAAAwBOAGwMAAADAC4AbQwAAAIAOADqDAAABABRAG4MAAACAEYAAQAICXEbUQcAIQIIaAwAAAMAWABpDAAAAwBTAGsMAAADAEAAagwAAAMATgBsDAAAAwAuAG0MAAACADgA6gwAAAQAUQBuDAAAAgBGAAAA.Aequitasx:BAAALgAECgcJBwAAAA==.Aeristella:BAAALgADCgcJBwAAAA==.',
Ah='Ahrus:BAAALgADCgMJBgABLgAECggJIQACAEMLAA==.',
Al='Alanerazza:BAAALgADCgYJBgAAAA==.Althenzdormu:BAAALgAECgcJEwAAAA==.Altruist:BAAALgAECgYJEAABLgAECgcJHwABAO4ZAA==.',
Am='Amaethon:BAAALgAECgYJCAAAAA==.',
An='Ancaera:BAAALgADCgcJBwAAAA==.Andalikus:BAABLgAECn8mAAIDAAgJ0h8dCQCxAghoDAAABwBYAGkMAAAHAFIAawwAAAYAVABqDAAABQBLAGwMAAAEAFgAbQwAAAIAUQDqDAAABQBaAG4MAAACAD0AAwAICdIfHQkAsQIIaAwAAAcAWABpDAAABwBSAGsMAAAGAFQAagwAAAUASwBsDAAABABYAG0MAAACAFEA6gwAAAUAWgBuDAAAAgA9AAAA.Andorra:BAAALgADCgUJBAAAAA==.Andïea:BAAALgADCgEJAQAAAA==.Anrien:BAABLgAECn8fAAIEAAcJPx5FCQBeAgdoDAAABQBKAGkMAAAFAE4AawwAAAUARwBqDAAABABZAGwMAAAEAE4A6gwAAAUAUgBuDAAAAwBCAAQABwk/HkUJAF4CB2gMAAAFAEoAaQwAAAUATgBrDAAABQBHAGoMAAAEAFkAbAwAAAQATgDqDAAABQBSAG4MAAADAEIAAAA=.',
Ar='Arathor:BAAALgAECgYJCgAAAA==.Ari:BAABLgAECn8WAAIFAAgJTAgWOwD6AAhoDAAABQBBAGkMAAADAAEAawwAAAMACgBqDAAAAgAPAGwMAAACACMAbQwAAAEABADqDAAABQAeAG4MAAABAAcABQAICUwIFjsA+gAIaAwAAAUAQQBpDAAAAwABAGsMAAADAAoAagwAAAIADwBsDAAAAgAjAG0MAAABAAQA6gwAAAUAHgBuDAAAAQAHAAAA.Ariany:BAAALgADCgcJBwAAAA==.Ariyia:BAAALgAECgYJEgAAAA==.Arms:BAAALgAECgEJAQABLgAECgQJCwAGAAAAAA==.',
As='Asgorath:BAAALgADCgQJBAAAAA==.Asharal:BAABLgAECn8fAAQHAAcJmxR6BgB3AQdoDAAABQAuAGkMAAAFADsAawwAAAUAMABqDAAABABNAGwMAAAEAEEA6gwAAAUAMgBuDAAAAwAtAAcABwmbFHoGAHcBB2gMAAAFAC4AaQwAAAUAOwBrDAAABQAwAGoMAAAEAE0AbAwAAAQAQQDqDAAABQAyAG4MAAABAC0ACAABCYEJhS0AKAABbgwAAAEAGAAJAAEJsQPFaQAnAAFuDAAAAQAJAAAA.Ashlayah:BAAALgAECgYJBwAAAA==.',
Au='Aunyx:BAABLgAECn8fAAIKAAcJUAoCCQBUAQdoDAAABQAmAGkMAAAFABwAawwAAAUAHABqDAAABAAYAGwMAAAEAB4A6gwAAAUAFQBuDAAAAwALAAoABwlQCgIJAFQBB2gMAAAFACYAaQwAAAUAHABrDAAABQAcAGoMAAAEABgAbAwAAAQAHgDqDAAABQAVAG4MAAADAAsAAAA=.',
Az='Azbogah:BAAALgADCgYJCAAAAA==.',
Ba='Babyjack:BAAALgADCgcJCAABLgAECgYJFAALAGkVAA==.Balthenor:BAACLgAFFH8GAAIMAAIJqxMpIgCoAAJoDAAAAwAqAGkMAAADADkADAACCasTKSIAqAACaAwAAAMAKgBpDAAAAwA5AC4ABAp/HgACDAAICf4hkxEABAMADAAICf4hkxEABAMAAAA=.',
Be='Beej:BAABLgAECn8WAAIFAAkJAxLqEAD8AQloDAAAAwBGAGkMAAADADgAawwAAAMAOABqDAAAAgAvAGwMAAADACUAbQwAAAIALQDqDAAABAAtAG4MAAABAA8AbwwAAAEAJwAFAAkJAxLqEAD8AQloDAAAAwBGAGkMAAADADgAawwAAAMAOABqDAAAAgAvAGwMAAADACUAbQwAAAIALQDqDAAABAAtAG4MAAABAA8AbwwAAAEAJwAAAA==.Belenjan:BAAALgAECgYJCwAAAA==.Belestius:BAAALgADCgYJCwABLgADCgkJGAAGAAAAAA==.Berse:BAAALgAECgcJEwAAAA==.',
Bi='Bilko:BAAALgADCgEJAQAAAA==.Birdymage:BAAALgAECgQJDAAAAA==.',
Bl='Blightbeard:BAAALgAECgYJEwAAAA==.Blîss:BAAALgADCggJDQAAAA==.',
Bo='Bolong:BAAALgAECgMJAwABLgAFFAUJFAANAH8UAA==.Bonebroth:BAAALgAECgMJAwAAAA==.Bonehealer:BAAALgADCgcJCgAAAA==.',
Br='Brut:BAABLgAECn8YAAIOAAgJdx0EOQAQAghoDAAABABbAGkMAAAFAEgAawwAAAQAQQBqDAAAAwBeAGwMAAACAFUAbQwAAAEAPgDqDAAAAwBMAG4MAAACAEgADgAICXcdBDkAEAIIaAwAAAQAWwBpDAAABQBIAGsMAAAEAEEAagwAAAMAXgBsDAAAAgBVAG0MAAABAD4A6gwAAAMATABuDAAAAgBIAAAA.',
Bu='Bustus:BAABLgAECn8cAAIPAAcJeg6iOgA/AQdoDAAABAApAGkMAAAEADwAawwAAAQAIwBqDAAABAAoAGwMAAAEABUA6gwAAAUAJABuDAAAAwAXAA8ABwl6DqI6AD8BB2gMAAAEACkAaQwAAAQAPABrDAAABAAjAGoMAAAEACgAbAwAAAQAFQDqDAAABQAkAG4MAAADABcAAAA=.',
Ca='Carmasutra:BAAALgADCgYJBQAAAA==.Caroll:BAAALgAECgUJBgAAAA==.Carsomavra:BAAALgADCggJFQAAAA==.Cathercy:BAAALgAECgUJDgAAAA==.',
Ch='Chilly:BAAALgAECgYJDgABLgAFFAMJAwAGAAAAAA==.Chunt:BAAALgAECgIJAgAAAA==.',
Co='Compliance:BAABLgAECn8fAAIBAAcJ7hk5DACxAQdoDAAABQBHAGkMAAAFADwAawwAAAUAMgBqDAAABABIAGwMAAAEAEYA6gwAAAUAUgBuDAAAAwA/AAEABwnuGTkMALEBB2gMAAAFAEcAaQwAAAUAPABrDAAABQAyAGoMAAAEAEgAbAwAAAQARgDqDAAABQBSAG4MAAADAD8AAAA=.Corannis:BAABLgAECn8aAAIQAAcJ6RP4HQB1AQdoDAAAAwBHAGkMAAAEAEMAawwAAAQALABqDAAABABBAGwMAAAEAC8A6gwAAAQALgBuDAAAAwAcABAABwnpE/gdAHUBB2gMAAADAEcAaQwAAAQAQwBrDAAABAAsAGoMAAAEAEEAbAwAAAQALwDqDAAABAAuAG4MAAADABwAAAA=.Cowabunga:BAAALgADCgkJCQABLgAECgkJHwARAHsPAA==.',
Cr='Cranberries:BAABLgAECn8UAAMSAAcJEBeOFgC1AQdoDAAABABbAGkMAAAEAE4AawwAAAMAQQBqDAAAAgBOAGwMAAACADAA6gwAAAQAIQBuDAAAAQARABIABgmnGI4WALUBBmgMAAADAFsAaQwAAAMATgBrDAAAAgBBAGoMAAABAE4AbAwAAAEAMADqDAAAAwAQAAQABwljD7wZAH4BB2gMAAABACYAaQwAAAEALQBrDAAAAQA0AGoMAAABACkAbAwAAAEALgDqDAAAAQAhAG4MAAABABEAAAA=.Crockett:BAAALgADCgIJAgABLgAECgQJBwAGAAAAAA==.',
Cu='Curtis:BAAALgAECgYJDQABLgAECggJFgATAKUZAA==.',
Da='Daberserker:BAAALgADCgUJBQAAAA==.Dalmas:BAAALgAECgMJBQAAAA==.Darkgenie:BAAALgADCgEJAgAAAA==.Darlàrk:BAABLgAECn8WAAIOAAcJQhquJgC3AQdoDAAABABHAGkMAAAEAD0AawwAAAQAKgBqDAAAAwAqAGwMAAADAD8AbQwAAAEAUADqDAAAAwBTAA4ABwlCGq4mALcBB2gMAAAEAEcAaQwAAAQAPQBrDAAABAAqAGoMAAADACoAbAwAAAMAPwBtDAAAAQBQAOoMAAADAFMAAAA=.',
De='Delderach:BAAALgAECgUJDgAAAA==.Delosine:BAAALgADCgUJCgAAAA==.Demise:BAAALgADCgMJAwAAAA==.Denîn:BAABLgAECn8dAAINAAcJ4hdGNwCzAQdoDAAABQBHAGkMAAAFAD4AawwAAAUAOgBqDAAABABdAGwMAAAEAD0AbQwAAAEAJADqDAAABQBMAA0ABwniF0Y3ALMBB2gMAAAFAEcAaQwAAAUAPgBrDAAABQA6AGoMAAAEAF0AbAwAAAQAPQBtDAAAAQAkAOoMAAAFAEwAAAA=.',
Di='Dirkette:BAABLgAECn8hAAIEAAgJ+QN9JAAiAQhoDAAABgAJAGkMAAAGABUAawwAAAUACwBqDAAABAAKAGwMAAAEAAcAbQwAAAIABgDqDAAABAAJAG4MAAACAAQABAAICfkDfSQAIgEIaAwAAAYACQBpDAAABgAVAGsMAAAFAAsAagwAAAQACgBsDAAABAAHAG0MAAACAAYA6gwAAAQACQBuDAAAAgAEAAAA.Dirknelf:BAAALgADCgEJAQABLgAECggJIQAEAPkDAA==.Dirksavoid:BAAALgAECgUJBQABLgAECggJIQAEAPkDAA==.Dixonmayas:BAAALgAECgYJDAAAAA==.',
Do='Dokai:BAABLgAECn8dAAIUAAcJLxhDEwCsAQdoDAAABAA8AGkMAAAFADcAawwAAAUAQwBqDAAABAA4AGwMAAAEAEoA6gwAAAQAMgBuDAAAAwBAABQABwkvGEMTAKwBB2gMAAAEADwAaQwAAAUANwBrDAAABQBDAGoMAAAEADgAbAwAAAQASgDqDAAABAAyAG4MAAADAEAAAAA=.',
Dr='Dracmiz:BAAALgADCgYJBgAAAA==.Dragenous:BAAALgAECgMJAwAAAA==.Dragmartigan:BAAALgAECgQJCQABLgAECgUJBQAGAAAAAA==.Dragoran:BAAALgAECgUJBQAAAA==.Drewella:BAAALgADCgcJBwAAAA==.',
El='Elaenei:BAAALgADCggJFAAAAA==.Eliance:BAAALgAECgUJDgAAAA==.Elienn:BAAALgADCgcJBwAAAA==.Elsewhere:BAABLgAECn8WAAIJAAcJbg09JgAtAQdoDAAABAAyAGkMAAADACYAawwAAAMAEwBqDAAAAwAjAGwMAAAEACUAbQwAAAEAGwDqDAAABAAgAAkABwluDT0mAC0BB2gMAAAEADIAaQwAAAMAJgBrDAAAAwATAGoMAAADACMAbAwAAAQAJQBtDAAAAQAbAOoMAAAEACAAAAA=.',
Em='Emmily:BAAALgADCgYJDAAAAA==.',
En='Enuia:BAAALgADCgUJBQAAAA==.',
Er='Eririn:BAAALgAECgEJAgAAAA==.Errius:BAABLgAECn8bAAIVAAcJ4xKOGQAUAQdoDAAABQArAGkMAAAFADkAawwAAAUANQBqDAAAAwAgAGwMAAADAB8A6gwAAAUAQgBuDAAAAQAlABUABwnjEo4ZABQBB2gMAAAFACsAaQwAAAUAOQBrDAAABQA1AGoMAAADACAAbAwAAAMAHwDqDAAABQBCAG4MAAABACUAAAA=.',
Eu='Eunja:BAEALgADCggJCAAAAQ==.',
Ev='Evangelica:BAAALgAECgMJAwAAAA==.',
Fe='Feeltheburn:BAAALgAECgYJBgAAAA==.',
Fu='Fusaa:BAABLgAECn8gAAIWAAgJshP4LQC7AQhoDAAABgA0AGkMAAAFADUAawwAAAUAOABqDAAABAAyAGwMAAAEAEQAbQwAAAIAHwDqDAAABQArAG4MAAABADAAFgAICbIT+C0AuwEIaAwAAAYANABpDAAABQA1AGsMAAAFADgAagwAAAQAMgBsDAAABABEAG0MAAACAB8A6gwAAAUAKwBuDAAAAQAwAAAA.',
Ga='Gangry:BAAALgAECgQJCQAAAA==.',
Ge='Gelst:BAAALgADCgUJBQAAAA==.Gerbzarrion:BAAALgAECgUJDgAAAA==.Gerudo:BAAALgAECgQJBAAAAA==.',
Gi='Gilgador:BAABLgAECn8wAAIXAAgJLBX2CwDaAQhoDAAACABHAGkMAAAIAEEAawwAAAcAPgBqDAAABQBBAGwMAAAHADYAbQwAAAQAPQDqDAAABgArAG4MAAADABMAFwAICSwV9gsA2gEIaAwAAAgARwBpDAAACABBAGsMAAAHAD4AagwAAAUAQQBsDAAABwA2AG0MAAAEAD0A6gwAAAYAKwBuDAAAAwATAAAA.',
Go='Gord:BAAALgADCgYJBgAAAA==.',
Gr='Gravewalker:BAAALgAECgYJCgAAAA==.Gream:BAAALgADCgcJCgAAAA==.Greepster:BAAALgAECgYJEwAAAA==.',
Ha='Haggrum:BAAALgADCgIJAgAAAA==.Haley:BAAALgAECgEJAQABLgAECgQJCwAGAAAAAA==.Hawknnin:BAAALgAECgUJCwAAAA==.',
He='Hectorjbm:BAAALgADCgMJBAAAAA==.',
Hu='Hunterpulled:BAAALgAECgcJBwAAAA==.Huntrod:BAAALgADCgEJBQAAAA==.Huroona:BAAALgADCgcJEAAAAA==.Huskiè:BAAALgADCgYJDAAAAA==.',
Hy='Hyasinth:BAAALgADCgQJBAABLgAECgkJFAASABAXAA==.',
Ip='Ipwnallnoobs:BAABLgAECn8VAAINAAgJEQxrQQCNAQhoDAAAAwAhAGkMAAADACYAawwAAAMAJwBqDAAAAwAWAGwMAAAEACIAbQwAAAEAKgDqDAAAAwAPAG4MAAABAAwADQAICREMa0EAjQEIaAwAAAMAIQBpDAAAAwAmAGsMAAADACcAagwAAAMAFgBsDAAABAAiAG0MAAABACoA6gwAAAMADwBuDAAAAQAMAAAA.',
Ir='Irisila:BAAALgAECgEJAQABLgAECgQJCAAGAAAAAA==.Ironfists:BAAALgADCgMJAwAAAA==.',
Ja='Jagel:BAAALgADCgQJBAAAAA==.Jahkwellynn:BAAALgADCgEJAQAAAA==.Jairian:BAAALgADCgkJCQAAAA==.Jakoti:BAAALgADCgUJCQAAAA==.Jaxsi:BAAALgAECgQJCwAAAA==.Jaypharyn:BAAALgAECgcJEwAAAA==.',
Jo='Johalea:BAAALgADCgYJBQAAAA==.',
['Jå']='Jåsper:BAAALgAECgcJDQAAAA==.',
Ka='Kaileena:BAABLgAECn8kAAIYAAgJ0hcMBQDiAQhoDAAABgBDAGkMAAAGAD4AawwAAAYAUQBqDAAABQBPAGwMAAAEADgAbQwAAAIASgDqDAAABQAlAG4MAAACAC8AGAAICdIXDAUA4gEIaAwAAAYAQwBpDAAABgA+AGsMAAAGAFEAagwAAAUATwBsDAAABAA4AG0MAAACAEoA6gwAAAUAJQBuDAAAAgAvAAAA.Kaimare:BAAALgADCgUJBgAAAA==.Kandistars:BAABLgAECn8YAAIZAAcJZAyzJwAXAQdoDAAABQAtAGkMAAAFACoAawwAAAQAFABqDAAAAgAnAGwMAAACAB4A6gwAAAUAIABuDAAAAQASABkABwlkDLMnABcBB2gMAAAFAC0AaQwAAAUAKgBrDAAABAAUAGoMAAACACcAbAwAAAIAHgDqDAAABQAgAG4MAAABABIAAAA=.Kasia:BAAALgAECgcJEwAAAA==.',
Kh='Kharnas:BAAALgADCgYJCQAAAA==.',
Ki='Kierrings:BAABLgAECn8ZAAINAAgJiBZILADhAQhoDAAABQBYAGkMAAAFAEYAawwAAAUASABqDAAAAgA8AGwMAAACABkAbQwAAAEAIgDqDAAABABHAG4MAAABACkADQAICYgWSCwA4QEIaAwAAAUAWABpDAAABQBGAGsMAAAFAEgAagwAAAIAPABsDAAAAgAZAG0MAAABACIA6gwAAAQARwBuDAAAAQApAAAA.Kirarah:BAABLgAECn8aAAICAAcJ8iFSFABCAgdoDAAABQBeAGkMAAAEAFoAawwAAAQAUwBqDAAAAwBfAGwMAAADAF4A6gwAAAUAXwBuDAAAAgA+AAIABwnyIVIUAEICB2gMAAAFAF4AaQwAAAQAWgBrDAAABABTAGoMAAADAF8AbAwAAAMAXgDqDAAABQBfAG4MAAACAD4AAAA=.Kirarose:BAACLgAFFH8NAAMaAAQJfBC6DQBCAQRoDAAABQAtAGkMAAAEADYAawwAAAIAEwDqDAAAAgAwABoABAl8ELoNAEIBBGgMAAAEAC0AaQwAAAQANgBrDAAAAgATAOoMAAABADAAEgACCdoB5h0AYwACaAwAAAEAAADqDAAAAQAIAC4ABAp/FQADGgAHCd4dYRYANQIAGgAHCd4dYRYANQIAEgADCYQJbGgAiwAAAAA=.Kitcarson:BAAALgADCgUJCAAAAA==.',
Kl='Klauss:BAABLgAECn8gAAIFAAgJKw/QGQCbAQhoDAAABgBUAGkMAAAGACsAawwAAAUAPQBqDAAABAApAGwMAAADABkAbQwAAAIACQDqDAAABAAiAG4MAAACAAsABQAICSsP0BkAmwEIaAwAAAYAVABpDAAABgArAGsMAAAFAD0AagwAAAQAKQBsDAAAAwAZAG0MAAACAAkA6gwAAAQAIgBuDAAAAgALAAAA.Klax:BAAALgAECgYJCgAAAA==.',
Ko='Kordjin:BAAALgADCgIJAgAAAA==.',
Kr='Krornik:BAAALgADCgkJEQAAAA==.',
Ky='Kylia:BAAALgAECgYJEAAAAA==.',
['Kí']='Kíhanna:BAABLgAECn8fAAICAAgJLiB7EQBcAghoDAAABgBaAGkMAAAGAF8AawwAAAQAUwBqDAAABABVAGwMAAADAD0AbQwAAAIAVgDqDAAABABZAG4MAAACAEUAAgAICS4gexEAXAIIaAwAAAYAWgBpDAAABgBfAGsMAAAEAFMAagwAAAQAVQBsDAAAAwA9AG0MAAACAFYA6gwAAAQAWQBuDAAAAgBFAAAA.',
La='Larissa:BAAALgAECgYJDAAAAA==.',
Le='Legenddairy:BAABLgAECn8fAAMRAAkJew9ZDgBQAQloDAAABQAyAGkMAAAFADkAawwAAAUAKQBqDAAABAA5AGwMAAAEACIAbQwAAAIAJwDqDAAABAA0AG4MAAABABAAbwwAAAEAFgAZAAgJ1w7xLwCIAQhoDAAABAAkAGkMAAADADEAawwAAAMAKQBqDAAAAwAxAGwMAAADACIAbQwAAAEAGwDqDAAAAwA0AG8MAAABABYAEQAICXAOWQ4AUAEIaAwAAAEAMgBpDAAAAgA5AGsMAAACACQAagwAAAEAOQBsDAAAAQATAG0MAAABACcA6gwAAAEAJQBuDAAAAQAQAAAA.',
Li='Lizardath:BAABLgAECn8gAAICAAgJAQp+QQBfAQhoDAAABgAmAGkMAAAFABsAawwAAAUAEwBqDAAABAAZAGwMAAAEACsAbQwAAAEABwDqDAAABgAVAG4MAAABABUAAgAICQEKfkEAXwEIaAwAAAYAJgBpDAAABQAbAGsMAAAFABMAagwAAAQAGQBsDAAABAArAG0MAAABAAcA6gwAAAYAFQBuDAAAAQAVAAAA.',
Lj='Ljósálfr:BAABLgAECn8oAAIBAAgJBiOuAwCTAghoDAAABwBfAGkMAAAGAFwAawwAAAYAWwBqDAAABgBVAGwMAAAGAF4AbQwAAAIAUADqDAAABQBeAG4MAAACAE0AAQAICQYjrgMAkwIIaAwAAAcAXwBpDAAABgBcAGsMAAAGAFsAagwAAAYAVQBsDAAABgBeAG0MAAACAFAA6gwAAAUAXgBuDAAAAgBNAAAA.',
Lo='Lochramae:BAABLgAECn8gAAIVAAcJeRXaFgAwAQdoDAAABgBAAGkMAAAGADMAawwAAAYASgBqDAAABAAdAGwMAAAEADcAbQwAAAEAHgDqDAAABQA2ABUABwl5FdoWADABB2gMAAAGAEAAaQwAAAYAMwBrDAAABgBKAGoMAAAEAB0AbAwAAAQANwBtDAAAAQAeAOoMAAAFADYAAAA=.Logarius:BAAALgADCgQJBAAAAA==.Loupe:BAAALgADCgYJBwAAAA==.',
Lu='Lumanoughty:BAAALgADCggJFAAAAA==.Lunargaze:BAABLgAECn8aAAIOAAcJSCBGFAAxAgdoDAAABABfAGkMAAAEAEsAawwAAAQAVgBqDAAAAwBiAGwMAAAFAEkAbQwAAAIAUwDqDAAABABRAA4ABwlIIEYUADECB2gMAAAEAF8AaQwAAAQASwBrDAAABABWAGoMAAADAGIAbAwAAAUASQBtDAAAAgBTAOoMAAAEAFEAAAA=.',
Ma='Madmartigan:BAAALgADCgYJBgABLgAECgUJBQAGAAAAAA==.Mahangi:BAAALgADCgkJCQAAAA==.Mamimisan:BAABLgAECn8eAAIDAAgJnR5gCgCdAghoDAAABgBSAGkMAAAGAFEAawwAAAUARgBqDAAABABRAGwMAAAEAFoAbQwAAAEARgDqDAAAAwBMAG4MAAABAEoAAwAICZ0eYAoAnQIIaAwAAAYAUgBpDAAABgBRAGsMAAAFAEYAagwAAAQAUQBsDAAABABaAG0MAAABAEYA6gwAAAMATABuDAAAAQBKAAAA.',
Me='Meatball:BAAALgADCgYJBgAAAA==.Mecaris:BAAALgAECgYJBgABLgAFFAIJBgAMAKsTAA==.Medios:BAAALgAECgYJBwAAAA==.Metalicfox:BAAALgADCgQJBQAAAA==.',
Mi='Mitsumi:BAAALgAECgUJDQAAAA==.Miz:BAAALgAECgUJCgAAAA==.Mizkat:BAABLgAECn8eAAQRAAgJSRmaBwDhAQhoDAAABQBIAGkMAAAFAFIAawwAAAQARgBqDAAABAAxAGwMAAAEAEsAbQwAAAIAKgDqDAAABABGAG4MAAACACYAEQAICUkZmgcA4QEIaAwAAAUASABpDAAABQBSAGsMAAAEAEYAagwAAAMAMQBsDAAAAwBLAG0MAAACACoA6gwAAAMARgBuDAAAAgAmABsAAQlLDoArADgAAWwMAAABACQADwACCRwNm88ALwACagwAAAEAEwDqDAAAAQAwAAAA.',
Mo='Mojomoe:BAAALgADCggJCAAAAA==.Mormra:BAABLgAECn8hAAMCAAgJQwvQPQBsAQhoDAAABwAvAGkMAAAFAC8AawwAAAUALQBqDAAABAAhAGwMAAAEABMAbQwAAAIACADqDAAABAAQAG4MAAACABEAAgAICUML0D0AbAEIaAwAAAYALwBpDAAABQAvAGsMAAAFAC0AagwAAAQAIQBsDAAABAATAG0MAAACAAgA6gwAAAQAEABuDAAAAgARABwAAQnVAVUwAB4AAWgMAAABAAQAAAA=.',
Mu='Mushroom:BAAALgADCgYJCQAAAA==.Mustard:BAEBLgAECn8kAAQdAAcJZiUSBQB/AgdoDAAABwBiAGkMAAAFAGAAawwAAAUAXABqDAAABQBiAGwMAAAFAF0A6gwAAAUAYwBuDAAABABeAB0ABwmzJBIFAH8CB2gMAAAGAGIAaQwAAAQAYABrDAAABQBcAGoMAAAFAGIAbAwAAAMAUgDqDAAAAwBjAG4MAAAEAF4AAgACCcEk93MA0gACaAwAAAEAXgDqDAAAAgBdABwAAgn9I00TAM8AAmkMAAABAFoAbAwAAAIAXQAAAA==.',
['Më']='Mërcy:BAAALgADCgcJBwAAAA==.',
Na='Nagsh:BAAALgADCgEJAQAAAA==.Naklus:BAAALgAECgUJBQAAAA==.Nathan:BAAALgADCgcJBwAAAA==.',
Ne='Neilia:BAAALgAECggJDAABLgAECggJMAAXACwVAA==.',
Ni='Nixilia:BAAALgADCgUJBQAAAA==.',
Nl='Nlani:BAAALgAECgYJCgAAAA==.',
Nu='Nuvi:BAAALgAECgMJAwAAAA==.',
Or='Orihime:BAAALgADCgEJAQAAAA==.',
Ox='Oxygentank:BAAALgAECgQJBwAAAA==.',
Pa='Parne:BAAALgADCgUJBQAAAA==.',
Ph='Phatbutfun:BAAALgADCgMJAwAAAA==.',
Pi='Pips:BAAALgADCgcJBwAAAA==.',
Pl='Platura:BAABLgAECn8bAAIeAAcJVRizGQDQAQdoDAAABQBDAGkMAAAEAEsAawwAAAQAOwBqDAAAAwAzAGwMAAAEAEgA6gwAAAQAKQBuDAAAAwBDAB4ABwlVGLMZANABB2gMAAAFAEMAaQwAAAQASwBrDAAABAA7AGoMAAADADMAbAwAAAQASADqDAAABAApAG4MAAADAEMAAAA=.Plection:BAAALgADCgEJAQAAAA==.',
Ra='Raezune:BAAALgADCgMJAwAAAA==.Rajia:BAABLgAECn8fAAIfAAcJLRDaCQBGAQdoDAAABQA+AGkMAAAFACgAawwAAAUAHwBqDAAABAAfAGwMAAAEABYA6gwAAAUAQgBuDAAAAwAZAB8ABwktENoJAEYBB2gMAAAFAD4AaQwAAAUAKABrDAAABQAfAGoMAAAEAB8AbAwAAAQAFgDqDAAABQBCAG4MAAADABkAAAA=.Rassaphore:BAAALgAECgQJCwAAAA==.Raziik:BAAALgADCgYJBgAAAA==.Raínbow:BAAALgAECgEJAQAAAA==.',
Re='Reapin:BAAALgAECgcJEwAAAA==.',
Ri='Rilorren:BAAALgADCgcJCgABLgAECggJGAAOAHcdAA==.Rionach:BAABLgAECn8fAAIRAAcJDQhtGwCyAAdoDAAABQARAGkMAAAFAA4AawwAAAUAFwBqDAAABAASAGwMAAAEABoA6gwAAAUAIABuDAAAAwAJABEABwkNCG0bALIAB2gMAAAFABEAaQwAAAUADgBrDAAABQAXAGoMAAAEABIAbAwAAAQAGgDqDAAABQAgAG4MAAADAAkAAAA=.Ritsara:BAAALgAECgcJDQAAAA==.Riven:BAAALgAECgIJAgABLgAECgYJCgAGAAAAAA==.Rivon:BAABLgAECn8aAAIeAAYJORe+JQBuAQZoDAAABgBIAGkMAAAGAD0AawwAAAUARABqDAAAAwAxAGwMAAACAA4A6gwAAAQAWgAeAAYJORe+JQBuAQZoDAAABgBIAGkMAAAGAD0AawwAAAUARABqDAAAAwAxAGwMAAACAA4A6gwAAAQAWgAAAA==.Rivonsshield:BAAALgADCgYJBgAAAA==.',
Ro='Ro:BAAALgADCgYJBgAAAA==.Rothu:BAAALgAECgUJBgABLgAECgcJGQAOAJ0cAA==.Rowena:BAAALgADCgYJBgAAAA==.',
Ru='Ruka:BAAALgAECgEJAQAAAA==.',
Sa='Salenias:BAAALgADCgkJDAAAAA==.Sannicor:BAAALgADCgEJAQAAAA==.Saonji:BAAALgADCgcJDgAAAA==.',
Sc='Scoop:BAAALgAECgMJBQAAAA==.',
Se='Seanx:BAABLgAECn8gAAMMAAgJfh69EwBxAghoDAAABwBCAGkMAAAFAFIAawwAAAUAWgBqDAAABABRAGwMAAADAEMAbQwAAAIAXADqDAAABQBZAG4MAAABADgADAAICX4evRMAcQIIaAwAAAYAQgBpDAAABABSAGsMAAAEAFoAagwAAAMAOQBsDAAAAgBDAG0MAAACAFwA6gwAAAQAWQBuDAAAAQA4ACAABgmGEj0VAA0BBmgMAAABAB8AaQwAAAEANQBrDAAAAQA0AGoMAAABAFEAbAwAAAEAIgDqDAAAAQBAAAAA.',
Sh='Shenlong:BAABLgAFFH8FAAINAAIJrhnEeACjAAJoDAAAAwBJAOoMAAACADoADQACCa4ZxHgAowACaAwAAAMASQDqDAAAAgA6AAAA.Shigurexx:BAABLgAECn8iAAMCAAgJiRxkFABBAghoDAAABgBCAGkMAAAGAFUAawwAAAUARQBqDAAABQBBAGwMAAAFAEQAbQwAAAIAXQDqDAAABAA2AG4MAAABAEkAAgAICYkcZBQAQQIIaAwAAAIAQgBpDAAAAgBVAGsMAAACAEUAagwAAAIAQQBsDAAAAgBEAG0MAAACAF0A6gwAAAIANgBuDAAAAQBJABwABgltEjQUAMYABmgMAAAEAC0AaQwAAAQAQgBrDAAAAwAlAGoMAAADAC4AbAwAAAMALADqDAAAAgAoAAAA.Shoe:BAABLgAECn8yAAMHAAkJ+xtuAQCLAgloDAAABwBbAGkMAAAIAFUAawwAAAgAUABqDAAABgBgAGwMAAAFAEkAbQwAAAQAOwDqDAAABwBQAG4MAAADACkAbwwAAAIAPAAHAAkJ+xtuAQCLAgloDAAABgBbAGkMAAAHAFUAawwAAAcAUABqDAAABgBgAGwMAAAFAEkAbQwAAAMAOwDqDAAABgBQAG4MAAACACkAbwwAAAIAPAAJAAYJmRAtHAByAQZoDAAAAQA3AGkMAAABADoAawwAAAEALwBtDAAAAQAYAOoMAAABADAAbgwAAAEAEwAAAA==.Shootup:BAAALgADCgYJBgAAAA==.',
Si='Sigmandis:BAAALgAECgcJDQAAAA==.Siph:BAAALgAECgYJBgAAAA==.',
Sk='Sklook:BAAALgAECgEJAQAAAA==.Skolam:BAAALgADCgYJDAAAAA==.',
So='Somassen:BAAALgADCgcJEQAAAA==.Sorrengail:BAAALgAECgIJAgAAAA==.Soulforge:BAAALgAECgMJAwAAAA==.',
St='Stalestorn:BAAALgADCgIJAgAAAA==.',
Su='Sunquell:BAAALgAECgMJAwAAAA==.Surii:BAAALgAECgUJCwAAAA==.',
Sw='Sweeneytodd:BAAALgAECgEJAgAAAA==.',
Sy='Sybryn:BAAALgADCgQJBAAAAA==.',
Ta='Taliadrin:BAAALgAECgIJAgAAAA==.Tamarins:BAAALgAECgcJEwAAAA==.Taryeth:BAAALgADCgMJAwAAAA==.',
Te='Terkarakk:BAABLgAECn8aAAIRAAgJsCLIAgCXAghoDAAABQBfAGkMAAAEAFsAawwAAAQAVABqDAAAAwBWAGwMAAADAFMAbQwAAAEAUwDqDAAABABZAG4MAAACAFwAEQAICbAiyAIAlwIIaAwAAAUAXwBpDAAABABbAGsMAAAEAFQAagwAAAMAVgBsDAAAAwBTAG0MAAABAFMA6gwAAAQAWQBuDAAAAgBcAAAA.',
Th='Thetamoon:BAAALgADCgUJBQAAAA==.Thireaux:BAAALgAECgQJBQAAAA==.Thorybos:BAAALgAECgMJBAAAAA==.',
To='Toom:BAAALgAECgUJDgAAAA==.',
Tr='Traylinna:BAAALgADCgQJBAAAAA==.Tritas:BAAALgADCggJEAABLgAECggJMAAXACwVAA==.Trophyhubby:BAABLgAECn8bAAMSAAcJpwx2LQD6AAdoDAAABQAlAGkMAAAFAAwAawwAAAUAJwBqDAAAAwAkAGwMAAADABIA6gwAAAUAOABuDAAAAQAaABIABgkODXYtAPoABmgMAAADACUAaQwAAAMADABrDAAABAAnAGoMAAACACQAbAwAAAIAEgDqDAAAAgA4ABoABwnYAyYxAOgAB2gMAAACAAUAaQwAAAIADABrDAAAAQAJAGoMAAABABMAbAwAAAEADwDqDAAAAwAGAG4MAAABAAkAAAA=.',
Tu='Tuknark:BAAALgADCgYJBgAAAA==.Tuladrin:BAAALgADCgQJBAAAAA==.',
Ty='Tyeren:BAAALgAECgYJDgAAAA==.Tyeriel:BAACLgAFFH8UAAMNAAUJfxTmMwBFAQVoDAAABgBLAGkMAAAFAEUAawwAAAMAHABqDAAAAgA3AOoMAAAEACQADQAECX8U5jMARQEEaAwAAAYASwBpDAAABQBFAGsMAAADABwA6gwAAAQAJAAVAAEJAADxLwAAAAFqDAAAAgA3AC4ABAp/HwADDQAJCdke2SIAtAIADQAICf8e2SIAtAIAFQADCQwaaB0A7wAAAAA=.Tyrîel:BAAALgADCgcJBwABLgAFFAUJFAANAH8UAA==.',
Us='Usato:BAAALgAECgUJBQAAAA==.',
Va='Valat:BAAALgADCgYJCwAAAA==.Valkyriefall:BAAALgAECgMJBQAAAA==.Valkyriewing:BAAALgAECgUJCAAAAA==.Valvet:BAAALgADCgkJKQAAAA==.Vardanis:BAAALgADCggJDwAAAA==.',
Vi='Vikril:BAAALgAECgYJBwAAAA==.Vincenzo:BAAALgAECgEJAgAAAA==.Vixer:BAAALgAECgQJBgAAAA==.',
Vo='Vog:BAAALgADCgYJBgAAAA==.Voidquèèn:BAAALgADCgEJAQAAAA==.Volkanoth:BAABLgAECn8VAAIOAAcJFSTjJQBvAgdoDAAABABiAGkMAAADAGAAawwAAAMAWgBqDAAAAgBiAGwMAAABAFgAbQwAAAEAVADqDAAABwBfAA4ABwkVJOMlAG8CB2gMAAAEAGIAaQwAAAMAYABrDAAAAwBaAGoMAAACAGIAbAwAAAEAWABtDAAAAQBUAOoMAAAHAF8AAAA=.',
Vu='Vue:BAAALgADCgcJBwABLgAECgYJCgAGAAAAAA==.',
Vy='Vylus:BAAALgAECgQJBAAAAA==.',
['Vá']='Vásh:BAAALgADCggJCAAAAA==.',
We='Weeblewobble:BAAALgADCggJCgAAAA==.',
Wi='Wikidblade:BAAALgAECgQJCAAAAA==.William:BAAALgAECgYJDQAAAA==.Windee:BAAALgAECgYJEgAAAA==.',
Wr='Wrast:BAABLgAECn8UAAIcAAcJUwYSEQDsAAdoDAAABAAUAGkMAAAEABoAawwAAAUAHABqDAAAAwAPAGwMAAABAAgAbQwAAAEABwDqDAAAAgAGABwABwlTBhIRAOwAB2gMAAAEABQAaQwAAAQAGgBrDAAABQAcAGoMAAADAA8AbAwAAAEACABtDAAAAQAHAOoMAAACAAYAAAA=.Wravyn:BAAALgADCgcJBwAAAA==.',
Xy='Xyara:BAABLgAECn8eAAQWAAkJ5xcFOwCJAQloDAAABABCAGkMAAADADMAawwAAAUATwBqDAAABABbAGwMAAAFAFsAbQwAAAIAQgDqDAAABAA2AG4MAAACAEIAbwwAAAEADQAWAAYJphIFOwCJAQZoDAAABABCAGkMAAACADMAawwAAAEAIgDqDAAABAA2AG4MAAABAEEAbwwAAAEADQALAAUJmx1QCAA/AQVrDAAAAQBPAGoMAAACAFsAbAwAAAUAWwBtDAAAAgBCAG4MAAABAEIAHwADCaATZjsAxgADaQwAAAEAKwBrDAAAAwA4AGoMAAACADsAAAA=.Xylaara:BAAALgAECgYJBgAAAA==.',
Ya='Yarine:BAAALgAECgEJAQAAAA==.',
Yo='Yoghurt:BAABLgAECn8lAAIhAAgJdSC5CABvAghoDAAABgBdAGkMAAAGAFgAawwAAAUASgBqDAAABQBPAGwMAAAGAFYAbQwAAAIATADqDAAABQBOAG4MAAACAFMAIQAICXUguQgAbwIIaAwAAAYAXQBpDAAABgBYAGsMAAAFAEoAagwAAAUATwBsDAAABgBWAG0MAAACAEwA6gwAAAUATgBuDAAAAgBTAAAA.',
Za='Zabimaru:BAAALgADCgYJCgAAAA==.Zalidus:BAABLgAFFH8FAAIiAAMJ9wsOBgDtAANoDAAAAgAdAGkMAAABADQA6gwAAAIACQAiAAMJ9wsOBgDtAANoDAAAAgAdAGkMAAABADQA6gwAAAIACQAAAA==.Zatika:BAABLgAECn8iAAMjAAgJkhXPAgC8AQhoDAAABwBHAGkMAAAFAEcAawwAAAUAQgBqDAAABQBOAGwMAAAFADMAbQwAAAIALQDqDAAABABHAG4MAAABAAYAIwAHCbYYzwIAvAEHaAwAAAYARwBpDAAABABHAGsMAAAEAEIAagwAAAQATgBsDAAABAAzAG0MAAABAC0A6gwAAAMARwAkAAgJ0gZPZgBXAQhoDAAAAQAWAGkMAAABABUAawwAAAEAEQBqDAAAAQAgAGwMAAABABMAbQwAAAEACQDqDAAAAQAYAG4MAAABAAYAAAA=.',
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
