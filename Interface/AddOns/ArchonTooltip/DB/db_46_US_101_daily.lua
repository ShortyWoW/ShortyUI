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
local provider = {region='US',realm='Galakrond',name='US',type='daily',zone=46,date='2026-05-11',data={Ae='Aegisthal:BAABLgAECn8XAAIBAAgJcRsfBwAlAghoDAAAAwBYAGkMAAADAFMAawwAAAMAQABqDAAAAwBOAGwMAAADAC4AbQwAAAIAOADqDAAABABRAG4MAAACAEYAAQAICXEbHwcAJQIIaAwAAAMAWABpDAAAAwBTAGsMAAADAEAAagwAAAMATgBsDAAAAwAuAG0MAAACADgA6gwAAAQAUQBuDAAAAgBGAAAA.Aequitasx:BAAALgAECgcJBwAAAA==.',
Ah='Ahrus:BAAALgADCgMJBgABLgAECggJIQACAEMLAA==.',
Al='Alanerazza:BAAALgADCgYJBgAAAA==.Althenzdormu:BAAALgAECgcJEwAAAA==.Altruist:BAAALgAECgYJEAABLgAECgcJHwABAO4ZAA==.',
Am='Amaethon:BAAALgAECgYJCAAAAA==.',
An='Ancaera:BAAALgADCgcJBwAAAA==.Andalikus:BAABLgAECn8mAAIDAAgJ0h/ICACxAghoDAAABwBYAGkMAAAHAFIAawwAAAYAVABqDAAABQBLAGwMAAAEAFgAbQwAAAIAUQDqDAAABQBaAG4MAAACAD0AAwAICdIfyAgAsQIIaAwAAAcAWABpDAAABwBSAGsMAAAGAFQAagwAAAUASwBsDAAABABYAG0MAAACAFEA6gwAAAUAWgBuDAAAAgA9AAAA.Andïea:BAAALgADCgEJAQAAAA==.Anrien:BAABLgAECn8fAAIEAAcJPx4QCQBeAgdoDAAABQBKAGkMAAAFAE4AawwAAAUARwBqDAAABABZAGwMAAAEAE4A6gwAAAUAUgBuDAAAAwBCAAQABwk/HhAJAF4CB2gMAAAFAEoAaQwAAAUATgBrDAAABQBHAGoMAAAEAFkAbAwAAAQATgDqDAAABQBSAG4MAAADAEIAAAA=.',
Ar='Arathor:BAAALgAECgYJCgAAAA==.Ari:BAABLgAECn8VAAIFAAgJ1gUZOwD6AAhoDAAABAAPAGkMAAADAAEAawwAAAMACgBqDAAAAgAPAGwMAAACACMAbQwAAAEABADqDAAABQAeAG4MAAABAAcABQAICdYFGTsA+gAIaAwAAAQADwBpDAAAAwABAGsMAAADAAoAagwAAAIADwBsDAAAAgAjAG0MAAABAAQA6gwAAAUAHgBuDAAAAQAHAAAA.Ariany:BAAALgADCgcJBwAAAA==.Ariyia:BAAALgAECgYJEgAAAA==.Arms:BAAALgAECgEJAQABLgAECgQJCwAGAAAAAA==.',
As='Asgorath:BAAALgADCgQJBAAAAA==.Asharal:BAABLgAECn8fAAQHAAcJmxRZBgB3AQdoDAAABQAuAGkMAAAFADsAawwAAAUAMABqDAAABABNAGwMAAAEAEEA6gwAAAUAMgBuDAAAAwAtAAcABwmbFFkGAHcBB2gMAAAFAC4AaQwAAAUAOwBrDAAABQAwAGoMAAAEAE0AbAwAAAQAQQDqDAAABQAyAG4MAAABAC0ACAABCYEJ4SwAKAABbgwAAAEAGAAJAAEJsQMcaAAnAAFuDAAAAQAJAAAA.Ashlayah:BAAALgAECgYJBwAAAA==.',
Au='Aunyx:BAABLgAECn8fAAIKAAcJUArVCABUAQdoDAAABQAmAGkMAAAFABwAawwAAAUAHABqDAAABAAYAGwMAAAEAB4A6gwAAAUAFQBuDAAAAwALAAoABwlQCtUIAFQBB2gMAAAFACYAaQwAAAUAHABrDAAABQAcAGoMAAAEABgAbAwAAAQAHgDqDAAABQAVAG4MAAADAAsAAAA=.',
Az='Azbogah:BAAALgADCgYJCAAAAA==.',
Ba='Babyjack:BAAALgADCgcJCAABLgAECgYJFAALAGkVAA==.Balthenor:BAACLgAFFH8GAAIMAAIJqxMmIgCoAAJoDAAAAwAqAGkMAAADADkADAACCasTJiIAqAACaAwAAAMAKgBpDAAAAwA5AC4ABAp/HgACDAAICf4hkhEABAMADAAICf4hkhEABAMAAAA=.',
Be='Beej:BAABLgAECn8WAAIFAAkJAxJ6EAD8AQloDAAAAwBGAGkMAAADADgAawwAAAMAOABqDAAAAgAvAGwMAAADACUAbQwAAAIALQDqDAAABAAtAG4MAAABAA8AbwwAAAEAJwAFAAkJAxJ6EAD8AQloDAAAAwBGAGkMAAADADgAawwAAAMAOABqDAAAAgAvAGwMAAADACUAbQwAAAIALQDqDAAABAAtAG4MAAABAA8AbwwAAAEAJwAAAA==.Belenjan:BAAALgAECgYJCwAAAA==.Belestius:BAAALgADCgYJCwABLgADCgkJGAAGAAAAAA==.Berse:BAAALgAECgcJEwAAAA==.',
Bi='Bilko:BAAALgADCgEJAQAAAA==.Birdymage:BAAALgAECgQJDAAAAA==.',
Bl='Blightbeard:BAAALgAECgYJEwAAAA==.Blîss:BAAALgADCggJDQAAAA==.',
Bo='Bolong:BAAALgAECgMJAwABLgAFFAUJFAANAH8UAA==.Bonebroth:BAAALgAECgMJAwAAAA==.Bonehealer:BAAALgADCgcJCgAAAA==.',
Br='Brut:BAABLgAECn8YAAIOAAgJdx0BOQAQAghoDAAABABbAGkMAAAFAEgAawwAAAQAQQBqDAAAAwBeAGwMAAACAFUAbQwAAAEAPgDqDAAAAwBMAG4MAAACAEgADgAICXcdATkAEAIIaAwAAAQAWwBpDAAABQBIAGsMAAAEAEEAagwAAAMAXgBsDAAAAgBVAG0MAAABAD4A6gwAAAMATABuDAAAAgBIAAAA.',
Bu='Bustus:BAABLgAECn8cAAIPAAcJeg7LOQA/AQdoDAAABAApAGkMAAAEADwAawwAAAQAIwBqDAAABAAoAGwMAAAEABUA6gwAAAUAJABuDAAAAwAXAA8ABwl6Dss5AD8BB2gMAAAEACkAaQwAAAQAPABrDAAABAAjAGoMAAAEACgAbAwAAAQAFQDqDAAABQAkAG4MAAADABcAAAA=.',
Ca='Caroll:BAAALgAECgUJBgAAAA==.Carsomavra:BAAALgADCggJFQAAAA==.Cathercy:BAAALgAECgUJDgAAAA==.',
Ch='Chilly:BAAALgAECgYJDgABLgAFFAMJAwAGAAAAAA==.Chunt:BAAALgAECgIJAgAAAA==.',
Co='Compliance:BAABLgAECn8fAAIBAAcJ7hn+CwC1AQdoDAAABQBHAGkMAAAFADwAawwAAAUAMgBqDAAABABIAGwMAAAEAEYA6gwAAAUAUgBuDAAAAwA/AAEABwnuGf4LALUBB2gMAAAFAEcAaQwAAAUAPABrDAAABQAyAGoMAAAEAEgAbAwAAAQARgDqDAAABQBSAG4MAAADAD8AAAA=.Corannis:BAABLgAECn8aAAIQAAcJ6RN3HQB1AQdoDAAAAwBHAGkMAAAEAEMAawwAAAQALABqDAAABABBAGwMAAAEAC8A6gwAAAQALgBuDAAAAwAcABAABwnpE3cdAHUBB2gMAAADAEcAaQwAAAQAQwBrDAAABAAsAGoMAAAEAEEAbAwAAAQALwDqDAAABAAuAG4MAAADABwAAAA=.Cowabunga:BAAALgADCgkJCQABLgAECgkJHwARAHsPAA==.',
Cr='Cranberries:BAABLgAECn8UAAMSAAcJEBcJFgC1AQdoDAAABABbAGkMAAAEAE4AawwAAAMAQQBqDAAAAgBOAGwMAAACADAA6gwAAAQAIQBuDAAAAQARABIABgmnGAkWALUBBmgMAAADAFsAaQwAAAMATgBrDAAAAgBBAGoMAAABAE4AbAwAAAEAMADqDAAAAwAQAAQABwljDz4ZAH4BB2gMAAABACYAaQwAAAEALQBrDAAAAQA0AGoMAAABACkAbAwAAAEALgDqDAAAAQAhAG4MAAABABEAAAA=.Crockett:BAAALgADCgIJAgABLgAECgQJBwAGAAAAAA==.',
Cu='Curtis:BAAALgAECgYJDQABLgAECggJFgATAKUZAA==.',
Da='Daberserker:BAAALgADCgUJBQAAAA==.Dalmas:BAAALgAECgMJBQAAAA==.Darkgenie:BAAALgADCgEJAgAAAA==.Darlàrk:BAABLgAECn8WAAIOAAcJQhoIJgC2AQdoDAAABABHAGkMAAAEAD0AawwAAAQAKgBqDAAAAwAqAGwMAAADAD8AbQwAAAEAUADqDAAAAwBTAA4ABwlCGggmALYBB2gMAAAEAEcAaQwAAAQAPQBrDAAABAAqAGoMAAADACoAbAwAAAMAPwBtDAAAAQBQAOoMAAADAFMAAAA=.',
De='Delderach:BAAALgAECgUJDgAAAA==.Delosine:BAAALgADCgUJCgAAAA==.Demise:BAAALgADCgMJAwAAAA==.Denîn:BAABLgAECn8dAAINAAcJ4hckNgCzAQdoDAAABQBHAGkMAAAFAD4AawwAAAUAOgBqDAAABABdAGwMAAAEAD0AbQwAAAEAJADqDAAABQBMAA0ABwniFyQ2ALMBB2gMAAAFAEcAaQwAAAUAPgBrDAAABQA6AGoMAAAEAF0AbAwAAAQAPQBtDAAAAQAkAOoMAAAFAEwAAAA=.',
Di='Dirkette:BAABLgAECn8hAAIEAAgJ+QPcIwAiAQhoDAAABgAJAGkMAAAGABUAawwAAAUACwBqDAAABAAKAGwMAAAEAAcAbQwAAAIABgDqDAAABAAJAG4MAAACAAQABAAICfkD3CMAIgEIaAwAAAYACQBpDAAABgAVAGsMAAAFAAsAagwAAAQACgBsDAAABAAHAG0MAAACAAYA6gwAAAQACQBuDAAAAgAEAAAA.Dirknelf:BAAALgADCgEJAQABLgAECggJIQAEAPkDAA==.Dirksavoid:BAAALgAECgUJBQABLgAECggJIQAEAPkDAA==.Dixonmayas:BAAALgAECgYJDAAAAA==.',
Do='Dokai:BAABLgAECn8dAAIUAAcJLxjMEgCtAQdoDAAABAA8AGkMAAAFADcAawwAAAUAQwBqDAAABAA4AGwMAAAEAEoA6gwAAAQAMgBuDAAAAwBAABQABwkvGMwSAK0BB2gMAAAEADwAaQwAAAUANwBrDAAABQBDAGoMAAAEADgAbAwAAAQASgDqDAAABAAyAG4MAAADAEAAAAA=.',
Dr='Dracmiz:BAAALgADCgYJBgAAAA==.Dragenous:BAAALgAECgMJAwAAAA==.Dragmartigan:BAAALgAECgQJCQABLgAECgUJBQAGAAAAAA==.Dragoran:BAAALgAECgUJBQAAAA==.Drewella:BAAALgADCgcJBwAAAA==.',
El='Elaenei:BAAALgADCggJFAAAAA==.Eliance:BAAALgAECgUJDgAAAA==.Elsewhere:BAABLgAECn8WAAIJAAcJbg2GJQAtAQdoDAAABAAyAGkMAAADACYAawwAAAMAEwBqDAAAAwAjAGwMAAAEACUAbQwAAAEAGwDqDAAABAAgAAkABwluDYYlAC0BB2gMAAAEADIAaQwAAAMAJgBrDAAAAwATAGoMAAADACMAbAwAAAQAJQBtDAAAAQAbAOoMAAAEACAAAAA=.',
Em='Emmily:BAAALgADCgYJDAAAAA==.',
En='Enuia:BAAALgADCgUJBQAAAA==.',
Er='Eririn:BAAALgAECgEJAgAAAA==.Errius:BAABLgAECn8bAAIVAAcJ4xI+GQAUAQdoDAAABQArAGkMAAAFADkAawwAAAUANQBqDAAAAwAgAGwMAAADAB8A6gwAAAUAQgBuDAAAAQAlABUABwnjEj4ZABQBB2gMAAAFACsAaQwAAAUAOQBrDAAABQA1AGoMAAADACAAbAwAAAMAHwDqDAAABQBCAG4MAAABACUAAAA=.',
Eu='Eunja:BAEALgADCggJCAAAAQ==.',
Ev='Evangelica:BAAALgAECgMJAwAAAA==.',
Fe='Feeltheburn:BAAALgAECgYJBgAAAA==.',
Fu='Fusaa:BAABLgAECn8fAAIWAAcJzhNKPQB+AQdoDAAABgA0AGkMAAAFADUAawwAAAUAOABqDAAABAAyAGwMAAAEAEQAbQwAAAIAHwDqDAAABQArABYABwnOE0o9AH4BB2gMAAAGADQAaQwAAAUANQBrDAAABQA4AGoMAAAEADIAbAwAAAQARABtDAAAAgAfAOoMAAAFACsAAAA=.',
Ga='Gangry:BAAALgAECgQJCQAAAA==.',
Ge='Gerbzarrion:BAAALgAECgUJDgAAAA==.Gerudo:BAAALgAECgQJBAAAAA==.',
Gi='Gilgador:BAABLgAECn8wAAIXAAgJLBWvCwDcAQhoDAAACABHAGkMAAAIAEEAawwAAAcAPgBqDAAABQBBAGwMAAAHADYAbQwAAAQAPQDqDAAABgArAG4MAAADABMAFwAICSwVrwsA3AEIaAwAAAgARwBpDAAACABBAGsMAAAHAD4AagwAAAUAQQBsDAAABwA2AG0MAAAEAD0A6gwAAAYAKwBuDAAAAwATAAAA.',
Go='Gord:BAAALgADCgYJBgAAAA==.',
Gr='Gravewalker:BAAALgAECgYJCgAAAA==.Gream:BAAALgADCgcJCgAAAA==.Greepster:BAAALgAECgYJEwAAAA==.',
Ha='Haggrum:BAAALgADCgIJAgAAAA==.Haley:BAAALgAECgEJAQABLgAECgQJCwAGAAAAAA==.Hawknnin:BAAALgAECgUJCwAAAA==.',
He='Hectorjbm:BAAALgADCgMJBAAAAA==.',
Hu='Hunterpulled:BAAALgAECgcJBwAAAA==.Huntrod:BAAALgADCgEJBAAAAA==.Huroona:BAAALgADCgcJEAAAAA==.Huskiè:BAAALgADCgYJDAAAAA==.',
Hy='Hyasinth:BAAALgADCgQJBAABLgAECgkJFAASABAXAA==.',
Ip='Ipwnallnoobs:BAAALgAECgcJDwAAAA==.',
Ir='Irisila:BAAALgAECgEJAQABLgAECgQJCAAGAAAAAA==.Ironfists:BAAALgADCgMJAwAAAA==.',
Ja='Jagel:BAAALgADCgQJBAAAAA==.Jahkwellynn:BAAALgADCgEJAQAAAA==.Jairian:BAAALgADCgkJCQAAAA==.Jakoti:BAAALgADCgUJCQAAAA==.Jaxsi:BAAALgAECgQJCwAAAA==.Jaypharyn:BAAALgAECgcJEwAAAA==.',
['Jå']='Jåsper:BAAALgAECgcJDQAAAA==.',
Ka='Kaileena:BAABLgAECn8kAAIYAAgJ0hfrBADjAQhoDAAABgBDAGkMAAAGAD4AawwAAAYAUQBqDAAABQBPAGwMAAAEADgAbQwAAAIASgDqDAAABQAlAG4MAAACAC8AGAAICdIX6wQA4wEIaAwAAAYAQwBpDAAABgA+AGsMAAAGAFEAagwAAAUATwBsDAAABAA4AG0MAAACAEoA6gwAAAUAJQBuDAAAAgAvAAAA.Kandistars:BAABLgAECn8YAAIZAAcJZAz4JgAXAQdoDAAABQAtAGkMAAAFACoAawwAAAQAFABqDAAAAgAnAGwMAAACAB4A6gwAAAUAIABuDAAAAQASABkABwlkDPgmABcBB2gMAAAFAC0AaQwAAAUAKgBrDAAABAAUAGoMAAACACcAbAwAAAIAHgDqDAAABQAgAG4MAAABABIAAAA=.Kasia:BAAALgAECgcJEwAAAA==.',
Kh='Kharnas:BAAALgADCgYJCQAAAA==.',
Ki='Kierrings:BAABLgAECn8ZAAINAAgJiBZGKwDhAQhoDAAABQBYAGkMAAAFAEYAawwAAAUASABqDAAAAgA8AGwMAAACABkAbQwAAAEAIgDqDAAABABHAG4MAAABACkADQAICYgWRisA4QEIaAwAAAUAWABpDAAABQBGAGsMAAAFAEgAagwAAAIAPABsDAAAAgAZAG0MAAABACIA6gwAAAQARwBuDAAAAQApAAAA.Kirarah:BAABLgAECn8aAAICAAcJ8iGYEwBDAgdoDAAABQBeAGkMAAAEAFoAawwAAAQAUwBqDAAAAwBfAGwMAAADAF4A6gwAAAUAXwBuDAAAAgA+AAIABwnyIZgTAEMCB2gMAAAFAF4AaQwAAAQAWgBrDAAABABTAGoMAAADAF8AbAwAAAMAXgDqDAAABQBfAG4MAAACAD4AAAA=.Kirarose:BAACLgAFFH8NAAMaAAQJfBBmDQBDAQRoDAAABQAtAGkMAAAEADYAawwAAAIAEwDqDAAAAgAwABoABAl8EGYNAEMBBGgMAAAEAC0AaQwAAAQANgBrDAAAAgATAOoMAAABADAAEgACCdoBUh0AYwACaAwAAAEAAADqDAAAAQAIAC4ABAp/FQADGgAHCd4dXxYANQIAGgAHCd4dXxYANQIAEgADCYQJbGgAiwAAAAA=.Kitcarson:BAAALgADCgUJCAAAAA==.',
Kl='Klauss:BAABLgAECn8gAAIFAAgJKw80GQCaAQhoDAAABgBUAGkMAAAGACsAawwAAAUAPQBqDAAABAApAGwMAAADABkAbQwAAAIACQDqDAAABAAiAG4MAAACAAsABQAICSsPNBkAmgEIaAwAAAYAVABpDAAABgArAGsMAAAFAD0AagwAAAQAKQBsDAAAAwAZAG0MAAACAAkA6gwAAAQAIgBuDAAAAgALAAAA.Klax:BAAALgAECgYJCgAAAA==.',
Ko='Kordjin:BAAALgADCgIJAgAAAA==.',
Kr='Krornik:BAAALgADCgkJEQAAAA==.',
Ky='Kylia:BAAALgAECgUJDQAAAA==.',
['Kí']='Kíhanna:BAABLgAECn8fAAICAAgJLiC4EABeAghoDAAABgBaAGkMAAAGAF8AawwAAAQAUwBqDAAABABVAGwMAAADAD0AbQwAAAIAVgDqDAAABABZAG4MAAACAEUAAgAICS4guBAAXgIIaAwAAAYAWgBpDAAABgBfAGsMAAAEAFMAagwAAAQAVQBsDAAAAwA9AG0MAAACAFYA6gwAAAQAWQBuDAAAAgBFAAAA.',
La='Larissa:BAAALgAECgYJDAAAAA==.',
Le='Legenddairy:BAABLgAECn8fAAMRAAkJew/jDQBQAQloDAAABQAyAGkMAAAFADkAawwAAAUAKQBqDAAABAA5AGwMAAAEACIAbQwAAAIAJwDqDAAABAA0AG4MAAABABAAbwwAAAEAFgAZAAgJ1w7uLwCIAQhoDAAABAAkAGkMAAADADEAawwAAAMAKQBqDAAAAwAxAGwMAAADACIAbQwAAAEAGwDqDAAAAwA0AG8MAAABABYAEQAICXAO4w0AUAEIaAwAAAEAMgBpDAAAAgA5AGsMAAACACQAagwAAAEAOQBsDAAAAQATAG0MAAABACcA6gwAAAEAJQBuDAAAAQAQAAAA.',
Li='Lizardath:BAABLgAECn8gAAICAAgJAQr0PwBgAQhoDAAABgAmAGkMAAAFABsAawwAAAUAEwBqDAAABAAZAGwMAAAEACsAbQwAAAEABwDqDAAABgAVAG4MAAABABUAAgAICQEK9D8AYAEIaAwAAAYAJgBpDAAABQAbAGsMAAAFABMAagwAAAQAGQBsDAAABAArAG0MAAABAAcA6gwAAAYAFQBuDAAAAQAVAAAA.',
Lj='Ljósálfr:BAABLgAECn8oAAIBAAgJBiOLAwCXAghoDAAABwBfAGkMAAAGAFwAawwAAAYAWwBqDAAABgBVAGwMAAAGAF4AbQwAAAIAUADqDAAABQBeAG4MAAACAE0AAQAICQYjiwMAlwIIaAwAAAcAXwBpDAAABgBcAGsMAAAGAFsAagwAAAYAVQBsDAAABgBeAG0MAAACAFAA6gwAAAUAXgBuDAAAAgBNAAAA.',
Lo='Lochramae:BAABLgAECn8gAAIVAAcJeRWEFgAwAQdoDAAABgBAAGkMAAAGADMAawwAAAYASgBqDAAABAAdAGwMAAAEADcAbQwAAAEAHgDqDAAABQA2ABUABwl5FYQWADABB2gMAAAGAEAAaQwAAAYAMwBrDAAABgBKAGoMAAAEAB0AbAwAAAQANwBtDAAAAQAeAOoMAAAFADYAAAA=.Logarius:BAAALgADCgQJBAAAAA==.Loupe:BAAALgADCgYJBwAAAA==.',
Lu='Lumanoughty:BAAALgADCggJFAAAAA==.Lunargaze:BAABLgAECn8ZAAIOAAcJSCDGEwAwAgdoDAAABABfAGkMAAAEAEsAawwAAAQAVgBqDAAAAwBiAGwMAAAFAEkAbQwAAAEAUwDqDAAABABRAA4ABwlIIMYTADACB2gMAAAEAF8AaQwAAAQASwBrDAAABABWAGoMAAADAGIAbAwAAAUASQBtDAAAAQBTAOoMAAAEAFEAAAA=.',
Ma='Madmartigan:BAAALgADCgYJBgABLgAECgUJBQAGAAAAAA==.Mahangi:BAAALgADCgkJCQAAAA==.Mamimisan:BAABLgAECn8eAAIDAAgJnR4HCgCdAghoDAAABgBSAGkMAAAGAFEAawwAAAUARgBqDAAABABRAGwMAAAEAFoAbQwAAAEARgDqDAAAAwBMAG4MAAABAEoAAwAICZ0eBwoAnQIIaAwAAAYAUgBpDAAABgBRAGsMAAAFAEYAagwAAAQAUQBsDAAABABaAG0MAAABAEYA6gwAAAMATABuDAAAAQBKAAAA.',
Me='Meatball:BAAALgADCgYJBgAAAA==.Mecaris:BAAALgAECgYJBgABLgAFFAIJBgAMAKsTAA==.Medios:BAAALgAECgYJBwAAAA==.Metalicfox:BAAALgADCgQJBQAAAA==.',
Mi='Mitsumi:BAAALgAECgUJDQAAAA==.Miz:BAAALgAECgUJCQAAAA==.Mizkat:BAABLgAECn8eAAQRAAgJSRlsBwDfAQhoDAAABQBIAGkMAAAFAFIAawwAAAQARgBqDAAABAAxAGwMAAAEAEsAbQwAAAIAKgDqDAAABABGAG4MAAACACYAEQAICUkZbAcA3wEIaAwAAAUASABpDAAABQBSAGsMAAAEAEYAagwAAAMAMQBsDAAAAwBLAG0MAAACACoA6gwAAAMARgBuDAAAAgAmABsAAQlLDmIqADgAAWwMAAABACQADwACCRwNms8ALwACagwAAAEAEwDqDAAAAQAwAAAA.',
Mo='Mojomoe:BAAALgADCggJCAAAAA==.Mormra:BAABLgAECn8hAAMCAAgJQwtQPABtAQhoDAAABwAvAGkMAAAFAC8AawwAAAUALQBqDAAABAAhAGwMAAAEABMAbQwAAAIACADqDAAABAAQAG4MAAACABEAAgAICUMLUDwAbQEIaAwAAAYALwBpDAAABQAvAGsMAAAFAC0AagwAAAQAIQBsDAAABAATAG0MAAACAAgA6gwAAAQAEABuDAAAAgARABwAAQnVAd4vAB4AAWgMAAABAAQAAAA=.',
Mu='Mushroom:BAAALgADCgYJCQAAAA==.Mustard:BAEBLgAECn8kAAQdAAcJZiXjBACAAgdoDAAABwBiAGkMAAAFAGAAawwAAAUAXABqDAAABQBiAGwMAAAFAF0A6gwAAAUAYwBuDAAABABeAB0ABwmzJOMEAIACB2gMAAAGAGIAaQwAAAQAYABrDAAABQBcAGoMAAAFAGIAbAwAAAMAUgDqDAAAAwBjAG4MAAAEAF4AAgACCcEkxXEA0gACaAwAAAEAXgDqDAAAAgBdABwAAgn9Iy4TANAAAmkMAAABAFoAbAwAAAIAXQAAAA==.',
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
Pl='Platura:BAABLgAECn8bAAIeAAcJVRj+GADRAQdoDAAABQBDAGkMAAAEAEsAawwAAAQAOwBqDAAAAwAzAGwMAAAEAEgA6gwAAAQAKQBuDAAAAwBDAB4ABwlVGP4YANEBB2gMAAAFAEMAaQwAAAQASwBrDAAABAA7AGoMAAADADMAbAwAAAQASADqDAAABAApAG4MAAADAEMAAAA=.Plection:BAAALgADCgEJAQAAAA==.',
Ra='Raezune:BAAALgADCgMJAwAAAA==.Rajia:BAABLgAECn8fAAIfAAcJLRBFCQBTAQdoDAAABQA+AGkMAAAFACgAawwAAAUAHwBqDAAABAAfAGwMAAAEABYA6gwAAAUAQgBuDAAAAwAZAB8ABwktEEUJAFMBB2gMAAAFAD4AaQwAAAUAKABrDAAABQAfAGoMAAAEAB8AbAwAAAQAFgDqDAAABQBCAG4MAAADABkAAAA=.Rassaphore:BAAALgAECgQJCwAAAA==.Raziik:BAAALgADCgYJBgAAAA==.Raínbow:BAAALgAECgEJAQAAAA==.',
Re='Reapin:BAAALgAECgcJEwAAAA==.',
Ri='Rilorren:BAAALgADCgcJCgABLgAECggJGAAOAHcdAA==.Rionach:BAABLgAECn8fAAIRAAcJDQhMGgCyAAdoDAAABQARAGkMAAAFAA4AawwAAAUAFwBqDAAABAASAGwMAAAEABoA6gwAAAUAIABuDAAAAwAJABEABwkNCEwaALIAB2gMAAAFABEAaQwAAAUADgBrDAAABQAXAGoMAAAEABIAbAwAAAQAGgDqDAAABQAgAG4MAAADAAkAAAA=.Ritsara:BAAALgAECgcJDQAAAA==.Riven:BAAALgAECgIJAgABLgAECgYJCgAGAAAAAA==.Rivon:BAABLgAECn8aAAIeAAYJORf5JABvAQZoDAAABgBIAGkMAAAGAD0AawwAAAUARABqDAAAAwAxAGwMAAACAA4A6gwAAAQAWgAeAAYJORf5JABvAQZoDAAABgBIAGkMAAAGAD0AawwAAAUARABqDAAAAwAxAGwMAAACAA4A6gwAAAQAWgAAAA==.Rivonsshield:BAAALgADCgYJBgAAAA==.',
Ro='Ro:BAAALgADCgYJBgAAAA==.Rothu:BAAALgAECgUJBQABLgAECgcJGQAOAJ0cAA==.Rowena:BAAALgADCgYJBgAAAA==.',
Ru='Ruka:BAAALgAECgEJAQAAAA==.',
Sa='Salenias:BAAALgADCgkJDAAAAA==.Sannicor:BAAALgADCgEJAQAAAA==.Saonji:BAAALgADCgcJDgAAAA==.',
Sc='Scoop:BAAALgAECgMJBQAAAA==.',
Se='Seanx:BAABLgAECn8fAAMMAAcJ4h+THAAuAgdoDAAABwBCAGkMAAAFAFIAawwAAAUAWgBqDAAABABRAGwMAAADAEMAbQwAAAIAXADqDAAABQBZAAwABwniH5McAC4CB2gMAAAGAEIAaQwAAAQAUgBrDAAABABaAGoMAAADADkAbAwAAAIAQwBtDAAAAgBcAOoMAAAEAFkAIAAGCYYS2xQADQEGaAwAAAEAHwBpDAAAAQA1AGsMAAABADQAagwAAAEAUQBsDAAAAQAiAOoMAAABAEAAAAA=.',
Sh='Shenlong:BAABLgAFFH8FAAINAAIJrhmjdQClAAJoDAAAAwBJAOoMAAACADoADQACCa4Zo3UApQACaAwAAAMASQDqDAAAAgA6AAAA.Shigurexx:BAABLgAECn8iAAMCAAgJiRyCEwBEAghoDAAABgBCAGkMAAAGAFUAawwAAAUARQBqDAAABQBBAGwMAAAFAEQAbQwAAAIAXQDqDAAABAA2AG4MAAABAEkAAgAICYkcghMARAIIaAwAAAIAQgBpDAAAAgBVAGsMAAACAEUAagwAAAIAQQBsDAAAAgBEAG0MAAACAF0A6gwAAAIANgBuDAAAAQBJABwABgltEhgUAMYABmgMAAAEAC0AaQwAAAQAQgBrDAAAAwAlAGoMAAADAC4AbAwAAAMALADqDAAAAgAoAAAA.Shoe:BAABLgAECn8yAAMHAAkJ+xthAQCMAgloDAAABwBbAGkMAAAIAFUAawwAAAgAUABqDAAABgBgAGwMAAAFAEkAbQwAAAQAOwDqDAAABwBQAG4MAAADACkAbwwAAAIAPAAHAAkJ+xthAQCMAgloDAAABgBbAGkMAAAHAFUAawwAAAcAUABqDAAABgBgAGwMAAAFAEkAbQwAAAMAOwDqDAAABgBQAG4MAAACACkAbwwAAAIAPAAJAAYJmRCwGwBxAQZoDAAAAQA3AGkMAAABADoAawwAAAEALwBtDAAAAQAYAOoMAAABADAAbgwAAAEAEwAAAA==.',
Si='Sigmandis:BAAALgAECgcJDQAAAA==.Siph:BAAALgAECgYJBgAAAA==.',
Sk='Sklook:BAAALgAECgEJAQAAAA==.Skolam:BAAALgADCgYJDAAAAA==.',
So='Somassen:BAAALgADCgYJCwAAAA==.Sorrengail:BAAALgAECgIJAgAAAA==.Soulforge:BAAALgAECgMJAwAAAA==.',
St='Stalestorn:BAAALgADCgIJAgAAAA==.',
Su='Sunquell:BAAALgAECgMJAwAAAA==.Surii:BAAALgAECgUJCwAAAA==.',
Sw='Sweeneytodd:BAAALgAECgEJAgAAAA==.',
Sy='Sybryn:BAAALgADCgQJBAAAAA==.',
Ta='Taliadrin:BAAALgAECgIJAgAAAA==.Tamarins:BAAALgAECgcJEwAAAA==.Taryeth:BAAALgADCgMJAwAAAA==.',
Te='Terkarakk:BAABLgAECn8aAAIRAAgJsCKyAgCVAghoDAAABQBfAGkMAAAEAFsAawwAAAQAVABqDAAAAwBWAGwMAAADAFMAbQwAAAEAUwDqDAAABABZAG4MAAACAFwAEQAICbAisgIAlQIIaAwAAAUAXwBpDAAABABbAGsMAAAEAFQAagwAAAMAVgBsDAAAAwBTAG0MAAABAFMA6gwAAAQAWQBuDAAAAgBcAAAA.',
Th='Thetamoon:BAAALgADCgUJBQAAAA==.Thireaux:BAAALgAECgQJBQAAAA==.Thorybos:BAAALgAECgMJBAAAAA==.',
To='Toom:BAAALgAECgUJDgAAAA==.',
Tr='Traylinna:BAAALgADCgQJBAAAAA==.Tritas:BAAALgADCggJEAABLgAECggJMAAXACwVAA==.Trophyhubby:BAABLgAECn8bAAMSAAcJpwy9LAD7AAdoDAAABQAlAGkMAAAFAAwAawwAAAUAJwBqDAAAAwAkAGwMAAADABIA6gwAAAUAOABuDAAAAQAaABIABgkODb0sAPsABmgMAAADACUAaQwAAAMADABrDAAABAAnAGoMAAACACQAbAwAAAIAEgDqDAAAAgA4ABoABwnYA0UwAOgAB2gMAAACAAUAaQwAAAIADABrDAAAAQAJAGoMAAABABMAbAwAAAEADwDqDAAAAwAGAG4MAAABAAkAAAA=.',
Tu='Tuladrin:BAAALgADCgQJBAAAAA==.',
Ty='Tyeren:BAAALgAECgYJDgAAAA==.Tyeriel:BAACLgAFFH8UAAMNAAUJfxQ5MgBFAQVoDAAABgBLAGkMAAAFAEUAawwAAAMAHABqDAAAAgA3AOoMAAAEACQADQAECX8UOTIARQEEaAwAAAYASwBpDAAABQBFAGsMAAADABwA6gwAAAQAJAAVAAEJAAC0LgAAAAFqDAAAAgA3AC4ABAp/HgADDQAICf8e1CIAtAIADQAICf8e1CIAtAIAFQACCSkY8SgAlgAAAAA=.Tyrîel:BAAALgADCgcJBwABLgAFFAUJFAANAH8UAA==.',
Us='Usato:BAAALgAECgUJBQAAAA==.',
Va='Valat:BAAALgADCgYJCwAAAA==.Valkyriefall:BAAALgAECgMJBQAAAA==.Valkyriewing:BAAALgAECgUJCAAAAA==.Valvet:BAAALgADCgkJKQAAAA==.Vardanis:BAAALgADCggJDwAAAA==.',
Vi='Vikril:BAAALgAECgYJBwAAAA==.Vincenzo:BAAALgAECgEJAgAAAA==.Vixer:BAAALgAECgQJBgAAAA==.',
Vo='Vog:BAAALgADCgYJBgAAAA==.Voidquèèn:BAAALgADCgEJAQAAAA==.Volkanoth:BAABLgAECn8VAAIOAAcJFSTiJQBvAgdoDAAABABiAGkMAAADAGAAawwAAAMAWgBqDAAAAgBiAGwMAAABAFgAbQwAAAEAVADqDAAABwBfAA4ABwkVJOIlAG8CB2gMAAAEAGIAaQwAAAMAYABrDAAAAwBaAGoMAAACAGIAbAwAAAEAWABtDAAAAQBUAOoMAAAHAF8AAAA=.',
Vu='Vue:BAAALgADCgcJBwABLgAECgYJCgAGAAAAAA==.',
Vy='Vylus:BAAALgAECgQJBAAAAA==.',
['Vá']='Vásh:BAAALgADCggJCAAAAA==.',
We='Weeblewobble:BAAALgADCgYJAwAAAA==.',
Wi='Wikidblade:BAAALgAECgQJCAAAAA==.William:BAAALgAECgYJDQAAAA==.Windee:BAAALgAECgYJEgAAAA==.',
Wr='Wrast:BAABLgAECn8UAAIcAAcJUwbIEADvAAdoDAAABAAUAGkMAAAEABoAawwAAAUAHABqDAAAAwAPAGwMAAABAAgAbQwAAAEABwDqDAAAAgAGABwABwlTBsgQAO8AB2gMAAAEABQAaQwAAAQAGgBrDAAABQAcAGoMAAADAA8AbAwAAAEACABtDAAAAQAHAOoMAAACAAYAAAA=.',
Xy='Xyara:BAABLgAECn8eAAQWAAkJ5xfVOQCKAQloDAAABABCAGkMAAADADMAawwAAAUATwBqDAAABABbAGwMAAAFAFsAbQwAAAIAQgDqDAAABAA2AG4MAAACAEIAbwwAAAEADQAWAAYJphLVOQCKAQZoDAAABABCAGkMAAACADMAawwAAAEAIgDqDAAABAA2AG4MAAABAEEAbwwAAAEADQALAAUJmx0YCABAAQVrDAAAAQBPAGoMAAACAFsAbAwAAAUAWwBtDAAAAgBCAG4MAAABAEIAHwADCaATZzsAxgADaQwAAAEAKwBrDAAAAwA4AGoMAAACADsAAAA=.Xylaara:BAAALgAECgYJBgAAAA==.',
Ya='Yarine:BAAALgAECgEJAQAAAA==.',
Yo='Yoghurt:BAABLgAECn8lAAIhAAgJdSBYCABxAghoDAAABgBdAGkMAAAGAFgAawwAAAUASgBqDAAABQBPAGwMAAAGAFYAbQwAAAIATADqDAAABQBOAG4MAAACAFMAIQAICXUgWAgAcQIIaAwAAAYAXQBpDAAABgBYAGsMAAAFAEoAagwAAAUATwBsDAAABgBWAG0MAAACAEwA6gwAAAUATgBuDAAAAgBTAAAA.',
Za='Zabimaru:BAAALgADCgYJCgAAAA==.Zalidus:BAABLgAFFH8FAAIiAAMJ9wvdBQDtAANoDAAAAgAdAGkMAAABADQA6gwAAAIACQAiAAMJ9wvdBQDtAANoDAAAAgAdAGkMAAABADQA6gwAAAIACQAAAA==.Zatika:BAABLgAECn8iAAMjAAgJkhW9AgC9AQhoDAAABwBHAGkMAAAFAEcAawwAAAUAQgBqDAAABQBOAGwMAAAFADMAbQwAAAIALQDqDAAABABHAG4MAAABAAYAIwAHCbYYvQIAvQEHaAwAAAYARwBpDAAABABHAGsMAAAEAEIAagwAAAQATgBsDAAABAAzAG0MAAABAC0A6gwAAAMARwAkAAgJ0gaxZABXAQhoDAAAAQAWAGkMAAABABUAawwAAAEAEQBqDAAAAQAgAGwMAAABABMAbQwAAAEACQDqDAAAAQAYAG4MAAABAAYAAAA=.',
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
