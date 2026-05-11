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
local provider = {region='US',realm='Galakrond',name='US',type='daily',zone=46,date='2026-05-10',data={Ae='Aegisthal:BAABLgAECn8XAAIBAAgJcRvPBgAnAghoDAAAAwBYAGkMAAADAFMAawwAAAMAQABqDAAAAwBOAGwMAAADAC4AbQwAAAIAOADqDAAABABRAG4MAAACAEYAAQAICXEbzwYAJwIIaAwAAAMAWABpDAAAAwBTAGsMAAADAEAAagwAAAMATgBsDAAAAwAuAG0MAAACADgA6gwAAAQAUQBuDAAAAgBGAAAA.Aequitasx:BAAALgAECgcJBwAAAA==.',
Ah='Ahrus:BAAALgADCgMJBgABLgAECggJIQACAEMLAA==.',
Al='Alanerazza:BAAALgADCgUJBQAAAA==.Althenzdormu:BAAALgAECgYJEwAAAA==.Altruist:BAAALgAECgYJEAABLgAECgcJHwABAO4ZAA==.',
Am='Amaethon:BAAALgAECgYJCAAAAA==.',
An='Ancaera:BAAALgADCgcJBwAAAA==.Andalikus:BAABLgAECn8mAAIDAAgJ0h9bCACxAghoDAAABwBYAGkMAAAHAFIAawwAAAYAVABqDAAABQBLAGwMAAAEAFgAbQwAAAIAUQDqDAAABQBaAG4MAAACAD0AAwAICdIfWwgAsQIIaAwAAAcAWABpDAAABwBSAGsMAAAGAFQAagwAAAUASwBsDAAABABYAG0MAAACAFEA6gwAAAUAWgBuDAAAAgA9AAAA.Andïea:BAAALgADCgEJAQAAAA==.Anrien:BAABLgAECn8fAAIEAAcJPx61CABfAgdoDAAABQBKAGkMAAAFAE4AawwAAAUARwBqDAAABABZAGwMAAAEAE4A6gwAAAUAUgBuDAAAAwBCAAQABwk/HrUIAF8CB2gMAAAFAEoAaQwAAAUATgBrDAAABQBHAGoMAAAEAFkAbAwAAAQATgDqDAAABQBSAG4MAAADAEIAAAA=.',
Ar='Arathor:BAAALgAECgYJCgAAAA==.Ari:BAABLgAECn8VAAIFAAgJ1gUYOwD6AAhoDAAABAAPAGkMAAADAAEAawwAAAMACgBqDAAAAgAPAGwMAAACACMAbQwAAAEABADqDAAABQAeAG4MAAABAAcABQAICdYFGDsA+gAIaAwAAAQADwBpDAAAAwABAGsMAAADAAoAagwAAAIADwBsDAAAAgAjAG0MAAABAAQA6gwAAAUAHgBuDAAAAQAHAAAA.Ariany:BAAALgADCgcJBwAAAA==.Ariyia:BAAALgAECgYJEgAAAA==.Arms:BAAALgAECgEJAQABLgAECgQJCwAGAAAAAA==.',
As='Asgorath:BAAALgADCgQJBAAAAA==.Asharal:BAABLgAECn8fAAQHAAcJmxQtBgB3AQdoDAAABQAuAGkMAAAFADsAawwAAAUAMABqDAAABABNAGwMAAAEAEEA6gwAAAUAMgBuDAAAAwAtAAcABwmbFC0GAHcBB2gMAAAFAC4AaQwAAAUAOwBrDAAABQAwAGoMAAAEAE0AbAwAAAQAQQDqDAAABQAyAG4MAAABAC0ACAABCYEJJSwAKAABbgwAAAEAGAAJAAEJsQMbZgAnAAFuDAAAAQAJAAAA.Ashlayah:BAAALgAECgYJBwAAAA==.',
Au='Aunyx:BAABLgAECn8fAAIKAAcJUAqiCABUAQdoDAAABQAmAGkMAAAFABwAawwAAAUAHABqDAAABAAYAGwMAAAEAB4A6gwAAAUAFQBuDAAAAwALAAoABwlQCqIIAFQBB2gMAAAFACYAaQwAAAUAHABrDAAABQAcAGoMAAAEABgAbAwAAAQAHgDqDAAABQAVAG4MAAADAAsAAAA=.',
Az='Azbogah:BAAALgADCgYJCAAAAA==.',
Ba='Babyjack:BAAALgADCgcJCAABLgAECgYJFAALAGkVAA==.Balthenor:BAACLgAFFH8GAAIMAAIJqxMmIgCoAAJoDAAAAwAqAGkMAAADADkADAACCasTJiIAqAACaAwAAAMAKgBpDAAAAwA5AC4ABAp/HgACDAAICf4hkhEABAMADAAICf4hkhEABAMAAAA=.',
Be='Beej:BAABLgAECn8WAAIFAAkJAxLZDwD8AQloDAAAAwBGAGkMAAADADgAawwAAAMAOABqDAAAAgAvAGwMAAADACUAbQwAAAIALQDqDAAABAAtAG4MAAABAA8AbwwAAAEAJwAFAAkJAxLZDwD8AQloDAAAAwBGAGkMAAADADgAawwAAAMAOABqDAAAAgAvAGwMAAADACUAbQwAAAIALQDqDAAABAAtAG4MAAABAA8AbwwAAAEAJwAAAA==.Belenjan:BAAALgAECgYJCwAAAA==.Belestius:BAAALgADCgYJCwABLgADCgkJGAAGAAAAAA==.Berse:BAAALgAECgYJEwAAAA==.',
Bi='Bilko:BAAALgADCgEJAQAAAA==.Birdymage:BAAALgAECgQJDAAAAA==.',
Bl='Blightbeard:BAAALgAECgYJEwAAAA==.Blîss:BAAALgADCggJDQAAAA==.',
Bo='Bolong:BAAALgAECgIJAgABLgAFFAUJFAANAH8UAA==.Bonebroth:BAAALgAECgMJAwAAAA==.Bonehealer:BAAALgADCgUJBQAAAA==.',
Br='Brut:BAABLgAECn8YAAIOAAgJdx0BOQAQAghoDAAABABbAGkMAAAFAEgAawwAAAQAQQBqDAAAAwBeAGwMAAACAFUAbQwAAAEAPgDqDAAAAwBMAG4MAAACAEgADgAICXcdATkAEAIIaAwAAAQAWwBpDAAABQBIAGsMAAAEAEEAagwAAAMAXgBsDAAAAgBVAG0MAAABAD4A6gwAAAMATABuDAAAAgBIAAAA.',
Bu='Bustus:BAABLgAECn8cAAIPAAcJeg6lOAA+AQdoDAAABAApAGkMAAAEADwAawwAAAQAIwBqDAAABAAoAGwMAAAEABUA6gwAAAUAJABuDAAAAwAXAA8ABwl6DqU4AD4BB2gMAAAEACkAaQwAAAQAPABrDAAABAAjAGoMAAAEACgAbAwAAAQAFQDqDAAABQAkAG4MAAADABcAAAA=.',
Ca='Caroll:BAAALgAECgUJBgAAAA==.Carsomavra:BAAALgADCggJFQAAAA==.Cathercy:BAAALgAECgUJDgAAAA==.',
Ch='Chilly:BAAALgAECgYJDgABLgAFFAMJAwAGAAAAAA==.Chunt:BAAALgAECgIJAgAAAA==.',
Co='Compliance:BAABLgAECn8fAAIBAAcJ7hmZCwC2AQdoDAAABQBHAGkMAAAFADwAawwAAAUAMgBqDAAABABIAGwMAAAEAEYA6gwAAAUAUgBuDAAAAwA/AAEABwnuGZkLALYBB2gMAAAFAEcAaQwAAAUAPABrDAAABQAyAGoMAAAEAEgAbAwAAAQARgDqDAAABQBSAG4MAAADAD8AAAA=.Corannis:BAABLgAECn8aAAIQAAcJ6ROPHAB2AQdoDAAAAwBHAGkMAAAEAEMAawwAAAQALABqDAAABABBAGwMAAAEAC8A6gwAAAQALgBuDAAAAwAcABAABwnpE48cAHYBB2gMAAADAEcAaQwAAAQAQwBrDAAABAAsAGoMAAAEAEEAbAwAAAQALwDqDAAABAAuAG4MAAADABwAAAA=.Cowabunga:BAAALgADCgkJCQABLgAECgkJHwARAHsPAA==.',
Cr='Cranberries:BAABLgAECn8UAAMSAAcJEBe+FQCxAQdoDAAABABbAGkMAAAEAE4AawwAAAMAQQBqDAAAAgBOAGwMAAACADAA6gwAAAQAIQBuDAAAAQARABIABgmnGL4VALEBBmgMAAADAFsAaQwAAAMATgBrDAAAAgBBAGoMAAABAE4AbAwAAAEAMADqDAAAAwAQAAQABwljD4YYAH4BB2gMAAABACYAaQwAAAEALQBrDAAAAQA0AGoMAAABACkAbAwAAAEALgDqDAAAAQAhAG4MAAABABEAAAA=.Crockett:BAAALgADCgEJAQABLgAECgQJBwAGAAAAAA==.',
Cu='Curtis:BAAALgAECgYJDQABLgAECggJFgATAKUZAA==.',
Da='Daberserker:BAAALgADCgUJBQAAAA==.Dalmas:BAAALgAECgMJBQAAAA==.Darkgenie:BAAALgADCgEJAgAAAA==.Darlàrk:BAABLgAECn8WAAIOAAcJQhocJQC0AQdoDAAABABHAGkMAAAEAD0AawwAAAQAKgBqDAAAAwAqAGwMAAADAD8AbQwAAAEAUADqDAAAAwBTAA4ABwlCGhwlALQBB2gMAAAEAEcAaQwAAAQAPQBrDAAABAAqAGoMAAADACoAbAwAAAMAPwBtDAAAAQBQAOoMAAADAFMAAAA=.',
De='Delderach:BAAALgAECgUJDgAAAA==.Delosine:BAAALgADCgUJCgAAAA==.Demise:BAAALgADCgMJAwAAAA==.Denîn:BAABLgAECn8dAAINAAcJ4heZNACzAQdoDAAABQBHAGkMAAAFAD4AawwAAAUAOgBqDAAABABdAGwMAAAEAD0AbQwAAAEAJADqDAAABQBMAA0ABwniF5k0ALMBB2gMAAAFAEcAaQwAAAUAPgBrDAAABQA6AGoMAAAEAF0AbAwAAAQAPQBtDAAAAQAkAOoMAAAFAEwAAAA=.',
Di='Dirkette:BAABLgAECn8hAAIEAAgJ+QP4IgAiAQhoDAAABgAJAGkMAAAGABUAawwAAAUACwBqDAAABAAKAGwMAAAEAAcAbQwAAAIABgDqDAAABAAJAG4MAAACAAQABAAICfkD+CIAIgEIaAwAAAYACQBpDAAABgAVAGsMAAAFAAsAagwAAAQACgBsDAAABAAHAG0MAAACAAYA6gwAAAQACQBuDAAAAgAEAAAA.Dirksavoid:BAAALgAECgUJBQABLgAECggJIQAEAPkDAA==.Dixonmayas:BAAALgAECgYJDAAAAA==.',
Do='Dokai:BAABLgAECn8dAAIUAAcJLxhFEgCuAQdoDAAABAA8AGkMAAAFADcAawwAAAUAQwBqDAAABAA4AGwMAAAEAEoA6gwAAAQAMgBuDAAAAwBAABQABwkvGEUSAK4BB2gMAAAEADwAaQwAAAUANwBrDAAABQBDAGoMAAAEADgAbAwAAAQASgDqDAAABAAyAG4MAAADAEAAAAA=.',
Dr='Dracmiz:BAAALgADCgYJBgAAAA==.Dragenous:BAAALgAECgMJAwAAAA==.Dragmartigan:BAAALgAECgQJCQABLgAECgUJBQAGAAAAAA==.Dragoran:BAAALgAECgUJBQAAAA==.Drewella:BAAALgADCgcJBwAAAA==.',
El='Elaenei:BAAALgADCggJFAAAAA==.Eliance:BAAALgAECgUJDgAAAA==.Elsewhere:BAABLgAECn8WAAIJAAcJbg2tJAAtAQdoDAAABAAyAGkMAAADACYAawwAAAMAEwBqDAAAAwAjAGwMAAAEACUAbQwAAAEAGwDqDAAABAAgAAkABwluDa0kAC0BB2gMAAAEADIAaQwAAAMAJgBrDAAAAwATAGoMAAADACMAbAwAAAQAJQBtDAAAAQAbAOoMAAAEACAAAAA=.',
Em='Emmily:BAAALgADCgYJDAAAAA==.',
En='Enuia:BAAALgADCgUJBQAAAA==.',
Er='Eririn:BAAALgAECgEJAgAAAA==.Errius:BAABLgAECn8bAAIVAAcJ4xKSGAAUAQdoDAAABQArAGkMAAAFADkAawwAAAUANQBqDAAAAwAgAGwMAAADAB8A6gwAAAUAQgBuDAAAAQAlABUABwnjEpIYABQBB2gMAAAFACsAaQwAAAUAOQBrDAAABQA1AGoMAAADACAAbAwAAAMAHwDqDAAABQBCAG4MAAABACUAAAA=.',
Eu='Eunja:BAEALgADCggJCAAAAQ==.',
Ev='Evangelica:BAAALgAECgMJAwAAAA==.',
Fe='Feeltheburn:BAAALgAECgYJBgAAAA==.',
Fu='Fusaa:BAABLgAECn8fAAIWAAcJzhM8PAB8AQdoDAAABgA0AGkMAAAFADUAawwAAAUAOABqDAAABAAyAGwMAAAEAEQAbQwAAAIAHwDqDAAABQArABYABwnOEzw8AHwBB2gMAAAGADQAaQwAAAUANQBrDAAABQA4AGoMAAAEADIAbAwAAAQARABtDAAAAgAfAOoMAAAFACsAAAA=.',
Ga='Gangry:BAAALgAECgQJCQAAAA==.',
Ge='Gerbzarrion:BAAALgAECgUJDgAAAA==.Gerudo:BAAALgAECgQJBAAAAA==.',
Gi='Gilgador:BAABLgAECn8uAAIXAAgJLBVgCwDcAQhoDAAACABHAGkMAAAHAEEAawwAAAcAPgBqDAAABQBBAGwMAAAGADYAbQwAAAQAPQDqDAAABgArAG4MAAADABMAFwAICSwVYAsA3AEIaAwAAAgARwBpDAAABwBBAGsMAAAHAD4AagwAAAUAQQBsDAAABgA2AG0MAAAEAD0A6gwAAAYAKwBuDAAAAwATAAAA.',
Go='Gord:BAAALgADCgYJBgAAAA==.',
Gr='Gravewalker:BAAALgAECgYJCgAAAA==.Gream:BAAALgADCgcJCgAAAA==.Greepster:BAAALgAECgYJEwAAAA==.',
Ha='Haggrum:BAAALgADCgIJAgAAAA==.Haley:BAAALgAECgEJAQABLgAECgQJCwAGAAAAAA==.Hawknnin:BAAALgAECgUJCwAAAA==.',
He='Hectorjbm:BAAALgADCgMJBAAAAA==.',
Hu='Hunterpulled:BAAALgAECgcJBwAAAA==.Huntrod:BAAALgADCgEJBAAAAA==.Huroona:BAAALgADCgcJEAAAAA==.Huskiè:BAAALgADCgYJDAAAAA==.',
Hy='Hyasinth:BAAALgADCgQJBAABLgAECgkJFAASABAXAA==.',
Ip='Ipwnallnoobs:BAAALgAECgcJDwAAAA==.',
Ir='Irisila:BAAALgAECgEJAQABLgAECgQJCAAGAAAAAA==.Ironfists:BAAALgADCgMJAwAAAA==.',
Ja='Jagel:BAAALgADCgQJBAAAAA==.Jahkwellynn:BAAALgADCgEJAQAAAA==.Jairian:BAAALgADCgkJCQAAAA==.Jakoti:BAAALgADCgUJCQAAAA==.Jaxsi:BAAALgAECgQJCwAAAA==.Jaypharyn:BAAALgAECgYJEwAAAA==.',
['Jå']='Jåsper:BAAALgAECgYJDQAAAA==.',
Ka='Kaileena:BAABLgAECn8kAAIYAAgJ0hfJBADjAQhoDAAABgBDAGkMAAAGAD4AawwAAAYAUQBqDAAABQBPAGwMAAAEADgAbQwAAAIASgDqDAAABQAlAG4MAAACAC8AGAAICdIXyQQA4wEIaAwAAAYAQwBpDAAABgA+AGsMAAAGAFEAagwAAAUATwBsDAAABAA4AG0MAAACAEoA6gwAAAUAJQBuDAAAAgAvAAAA.Kandistars:BAABLgAECn8YAAIZAAcJZAyPJQAbAQdoDAAABQAtAGkMAAAFACoAawwAAAQAFABqDAAAAgAnAGwMAAACAB4A6gwAAAUAIABuDAAAAQASABkABwlkDI8lABsBB2gMAAAFAC0AaQwAAAUAKgBrDAAABAAUAGoMAAACACcAbAwAAAIAHgDqDAAABQAgAG4MAAABABIAAAA=.Kasia:BAAALgAECgYJEwAAAA==.',
Kh='Kharnas:BAAALgADCgYJCQAAAA==.',
Ki='Kierrings:BAABLgAECn8ZAAINAAgJiBbjKQDhAQhoDAAABQBYAGkMAAAFAEYAawwAAAUASABqDAAAAgA8AGwMAAACABkAbQwAAAEAIgDqDAAABABHAG4MAAABACkADQAICYgW4ykA4QEIaAwAAAUAWABpDAAABQBGAGsMAAAFAEgAagwAAAIAPABsDAAAAgAZAG0MAAABACIA6gwAAAQARwBuDAAAAQApAAAA.Kirarah:BAABLgAECn8aAAICAAcJ8iGuEgBCAgdoDAAABQBeAGkMAAAEAFoAawwAAAQAUwBqDAAAAwBfAGwMAAADAF4A6gwAAAUAXwBuDAAAAgA+AAIABwnyIa4SAEICB2gMAAAFAF4AaQwAAAQAWgBrDAAABABTAGoMAAADAF8AbAwAAAMAXgDqDAAABQBfAG4MAAACAD4AAAA=.Kirarose:BAACLgAFFH8NAAMaAAQJfBDzDABDAQRoDAAABQAtAGkMAAAEADYAawwAAAIAEwDqDAAAAgAwABoABAl8EPMMAEMBBGgMAAAEAC0AaQwAAAQANgBrDAAAAgATAOoMAAABADAAEgACCdoBdBwAYwACaAwAAAEAAADqDAAAAQAIAC4ABAp/FQADGgAHCd4dXxYANQIAGgAHCd4dXxYANQIAEgADCYQJa2gAiwAAAAA=.Kitcarson:BAAALgADCgUJCAAAAA==.',
Kl='Klauss:BAABLgAECn8gAAIFAAgJKw+EGACaAQhoDAAABgBUAGkMAAAGACsAawwAAAUAPQBqDAAABAApAGwMAAADABkAbQwAAAIACQDqDAAABAAiAG4MAAACAAsABQAICSsPhBgAmgEIaAwAAAYAVABpDAAABgArAGsMAAAFAD0AagwAAAQAKQBsDAAAAwAZAG0MAAACAAkA6gwAAAQAIgBuDAAAAgALAAAA.Klax:BAAALgAECgYJCgAAAA==.',
Ko='Kordjin:BAAALgADCgIJAgAAAA==.',
Kr='Krornik:BAAALgADCgkJEQAAAA==.',
Ky='Kylia:BAAALgAECgUJDQAAAA==.',
['Kí']='Kíhanna:BAABLgAECn8fAAICAAgJLiDFDwBdAghoDAAABgBaAGkMAAAGAF8AawwAAAQAUwBqDAAABABVAGwMAAADAD0AbQwAAAIAVgDqDAAABABZAG4MAAACAEUAAgAICS4gxQ8AXQIIaAwAAAYAWgBpDAAABgBfAGsMAAAEAFMAagwAAAQAVQBsDAAAAwA9AG0MAAACAFYA6gwAAAQAWQBuDAAAAgBFAAAA.',
La='Larissa:BAAALgAECgYJDAAAAA==.',
Le='Legenddairy:BAABLgAECn8fAAMRAAkJew9jDQBPAQloDAAABQAyAGkMAAAFADkAawwAAAUAKQBqDAAABAA5AGwMAAAEACIAbQwAAAIAJwDqDAAABAA0AG4MAAABABAAbwwAAAEAFgAZAAgJ1w7vLwCIAQhoDAAABAAkAGkMAAADADEAawwAAAMAKQBqDAAAAwAxAGwMAAADACIAbQwAAAEAGwDqDAAAAwA0AG8MAAABABYAEQAICXAOYw0ATwEIaAwAAAEAMgBpDAAAAgA5AGsMAAACACQAagwAAAEAOQBsDAAAAQATAG0MAAABACcA6gwAAAEAJQBuDAAAAQAQAAAA.',
Li='Lizardath:BAABLgAECn8gAAICAAgJAQqkPwBTAQhoDAAABgAmAGkMAAAFABsAawwAAAUAEwBqDAAABAAZAGwMAAAEACsAbQwAAAEABwDqDAAABgAVAG4MAAABABUAAgAICQEKpD8AUwEIaAwAAAYAJgBpDAAABQAbAGsMAAAFABMAagwAAAQAGQBsDAAABAArAG0MAAABAAcA6gwAAAYAFQBuDAAAAQAVAAAA.',
Lj='Ljósálfr:BAABLgAECn8oAAIBAAgJBiNXAwCYAghoDAAABwBfAGkMAAAGAFwAawwAAAYAWwBqDAAABgBVAGwMAAAGAF4AbQwAAAIAUADqDAAABQBeAG4MAAACAE0AAQAICQYjVwMAmAIIaAwAAAcAXwBpDAAABgBcAGsMAAAGAFsAagwAAAYAVQBsDAAABgBeAG0MAAACAFAA6gwAAAUAXgBuDAAAAgBNAAAA.',
Lo='Lochramae:BAABLgAECn8gAAIVAAcJeRXiFQAwAQdoDAAABgBAAGkMAAAGADMAawwAAAYASgBqDAAABAAdAGwMAAAEADcAbQwAAAEAHgDqDAAABQA2ABUABwl5FeIVADABB2gMAAAGAEAAaQwAAAYAMwBrDAAABgBKAGoMAAAEAB0AbAwAAAQANwBtDAAAAQAeAOoMAAAFADYAAAA=.Logarius:BAAALgADCgQJBAAAAA==.Loupe:BAAALgADCgYJBwAAAA==.',
Lu='Lumanoughty:BAAALgADCggJFAAAAA==.Lunargaze:BAABLgAECn8ZAAIOAAcJSCAbEwAuAgdoDAAABABfAGkMAAAEAEsAawwAAAQAVgBqDAAAAwBiAGwMAAAFAEkAbQwAAAEAUwDqDAAABABRAA4ABwlIIBsTAC4CB2gMAAAEAF8AaQwAAAQASwBrDAAABABWAGoMAAADAGIAbAwAAAUASQBtDAAAAQBTAOoMAAAEAFEAAAA=.',
Ma='Madmartigan:BAAALgADCgYJBgABLgAECgUJBQAGAAAAAA==.Mahangi:BAAALgADCgkJCQAAAA==.Mamimisan:BAABLgAECn8eAAIDAAgJnR6XCQCeAghoDAAABgBSAGkMAAAGAFEAawwAAAUARgBqDAAABABRAGwMAAAEAFoAbQwAAAEARgDqDAAAAwBMAG4MAAABAEoAAwAICZ0elwkAngIIaAwAAAYAUgBpDAAABgBRAGsMAAAFAEYAagwAAAQAUQBsDAAABABaAG0MAAABAEYA6gwAAAMATABuDAAAAQBKAAAA.',
Me='Meatball:BAAALgADCgYJBgAAAA==.Mecaris:BAAALgAECgYJBgABLgAFFAIJBgAMAKsTAA==.Medios:BAAALgAECgYJBwAAAA==.Metalicfox:BAAALgADCgQJBAAAAA==.',
Mi='Mitsumi:BAAALgAECgUJDQAAAA==.Miz:BAAALgAECgUJCQAAAA==.Mizkat:BAABLgAECn8eAAQRAAgJSRkfBwDdAQhoDAAABQBIAGkMAAAFAFIAawwAAAQARgBqDAAABAAxAGwMAAAEAEsAbQwAAAIAKgDqDAAABABGAG4MAAACACYAEQAICUkZHwcA3QEIaAwAAAUASABpDAAABQBSAGsMAAAEAEYAagwAAAMAMQBsDAAAAwBLAG0MAAACACoA6gwAAAMARgBuDAAAAgAmABsAAQlLDucoADgAAWwMAAABACQADwACCRwNnM8ALwACagwAAAEAEwDqDAAAAQAwAAAA.',
Mo='Mojomoe:BAAALgADCggJCAAAAA==.Mormra:BAABLgAECn8hAAMCAAgJQwtMOwBjAQhoDAAABwAvAGkMAAAFAC8AawwAAAUALQBqDAAABAAhAGwMAAAEABMAbQwAAAIACADqDAAABAAQAG4MAAACABEAAgAICUMLTDsAYwEIaAwAAAYALwBpDAAABQAvAGsMAAAFAC0AagwAAAQAIQBsDAAABAATAG0MAAACAAgA6gwAAAQAEABuDAAAAgARABwAAQnVAScvAB4AAWgMAAABAAQAAAA=.',
Mu='Mushroom:BAAALgADCgYJCQAAAA==.Mustard:BAEBLgAECn8kAAQdAAcJZiWwBACAAgdoDAAABwBiAGkMAAAFAGAAawwAAAUAXABqDAAABQBiAGwMAAAFAF0A6gwAAAUAYwBuDAAABABeAB0ABwmzJLAEAIACB2gMAAAGAGIAaQwAAAQAYABrDAAABQBcAGoMAAAFAGIAbAwAAAMAUgDqDAAAAwBjAG4MAAAEAF4AHAACCf0jyxIA0AACaQwAAAEAWgBsDAAAAgBdAAIAAgnBJHttAM8AAmgMAAABAF4A6gwAAAIAXQAAAA==.',
Na='Nagsh:BAAALgADCgEJAQAAAA==.Naklus:BAAALgAECgUJBQAAAA==.Nathan:BAAALgADCgcJBwAAAA==.',
Ne='Neilia:BAAALgAECggJCwABLgAECggJLgAXACwVAA==.',
Nl='Nlani:BAAALgAECgYJCgAAAA==.',
Nu='Nuvi:BAAALgAECgMJAwAAAA==.',
Or='Orihime:BAAALgADCgEJAQAAAA==.',
Ox='Oxygentank:BAAALgAECgQJBwAAAA==.',
Pa='Parne:BAAALgADCgUJBQAAAA==.',
Ph='Phatbutfun:BAAALgADCgMJAwAAAA==.',
Pi='Pips:BAAALgADCgcJBwAAAA==.',
Pl='Platura:BAABLgAECn8bAAIeAAcJVRhUGADUAQdoDAAABQBDAGkMAAAEAEsAawwAAAQAOwBqDAAAAwAzAGwMAAAEAEgA6gwAAAQAKQBuDAAAAwBDAB4ABwlVGFQYANQBB2gMAAAFAEMAaQwAAAQASwBrDAAABAA7AGoMAAADADMAbAwAAAQASADqDAAABAApAG4MAAADAEMAAAA=.Plection:BAAALgADCgEJAQAAAA==.',
Ra='Raezune:BAAALgADCgMJAwAAAA==.Rajia:BAABLgAECn8fAAIfAAcJLRDnCABUAQdoDAAABQA+AGkMAAAFACgAawwAAAUAHwBqDAAABAAfAGwMAAAEABYA6gwAAAUAQgBuDAAAAwAZAB8ABwktEOcIAFQBB2gMAAAFAD4AaQwAAAUAKABrDAAABQAfAGoMAAAEAB8AbAwAAAQAFgDqDAAABQBCAG4MAAADABkAAAA=.Rassaphore:BAAALgAECgQJCwAAAA==.Raziik:BAAALgADCgYJBgAAAA==.Raínbow:BAAALgAECgEJAQAAAA==.',
Re='Reapin:BAAALgAECgYJEwAAAA==.',
Ri='Rilorren:BAAALgADCgcJCgABLgAECggJGAAOAHcdAA==.Rionach:BAABLgAECn8fAAIRAAcJDQjoGACyAAdoDAAABQARAGkMAAAFAA4AawwAAAUAFwBqDAAABAASAGwMAAAEABoA6gwAAAUAIABuDAAAAwAJABEABwkNCOgYALIAB2gMAAAFABEAaQwAAAUADgBrDAAABQAXAGoMAAAEABIAbAwAAAQAGgDqDAAABQAgAG4MAAADAAkAAAA=.Ritsara:BAAALgAECgYJDQAAAA==.Riven:BAAALgAECgIJAgABLgAECgYJCgAGAAAAAA==.Rivon:BAABLgAECn8aAAIeAAYJORcKJAB0AQZoDAAABgBIAGkMAAAGAD0AawwAAAUARABqDAAAAwAxAGwMAAACAA4A6gwAAAQAWgAeAAYJORcKJAB0AQZoDAAABgBIAGkMAAAGAD0AawwAAAUARABqDAAAAwAxAGwMAAACAA4A6gwAAAQAWgAAAA==.Rivonsshield:BAAALgADCgYJBgAAAA==.',
Ro='Ro:BAAALgADCgUJBQAAAA==.Rothu:BAAALgAECgUJBQABLgAECgcJGQAOAJ0cAA==.Rowena:BAAALgADCgYJBgAAAA==.',
Ru='Ruka:BAAALgAECgEJAQAAAA==.',
Sa='Salenias:BAAALgADCgkJDAAAAA==.Sannicor:BAAALgADCgEJAQAAAA==.Saonji:BAAALgADCgYJBwAAAA==.',
Sc='Scoop:BAAALgAECgMJBQAAAA==.',
Se='Seanx:BAABLgAECn8fAAMMAAcJ4h+IGwAtAgdoDAAABwBCAGkMAAAFAFIAawwAAAUAWgBqDAAABABRAGwMAAADAEMAbQwAAAIAXADqDAAABQBZAAwABwniH4gbAC0CB2gMAAAGAEIAaQwAAAQAUgBrDAAABABaAGoMAAADADkAbAwAAAIAQwBtDAAAAgBcAOoMAAAEAFkAIAAGCYYSZxQADQEGaAwAAAEAHwBpDAAAAQA1AGsMAAABADQAagwAAAEAUQBsDAAAAQAiAOoMAAABAEAAAAA=.',
Sh='Shenlong:BAABLgAFFH8FAAINAAIJrhlKcgClAAJoDAAAAwBJAOoMAAACADoADQACCa4ZSnIApQACaAwAAAMASQDqDAAAAgA6AAAA.Shigurexx:BAABLgAECn8iAAMCAAgJiRz9EgA/AghoDAAABgBCAGkMAAAGAFUAawwAAAUARQBqDAAABQBBAGwMAAAFAEQAbQwAAAIAXQDqDAAABAA2AG4MAAABAEkAAgAICYkc/RIAPwIIaAwAAAIAQgBpDAAAAgBVAGsMAAACAEUAagwAAAIAQQBsDAAAAgBEAG0MAAACAF0A6gwAAAIANgBuDAAAAQBJABwABgltEroTAMYABmgMAAAEAC0AaQwAAAQAQgBrDAAAAwAlAGoMAAADAC4AbAwAAAMALADqDAAAAgAoAAAA.Shoe:BAABLgAECn8yAAMHAAkJ+xtQAQCMAgloDAAABwBbAGkMAAAIAFUAawwAAAgAUABqDAAABgBgAGwMAAAFAEkAbQwAAAQAOwDqDAAABwBQAG4MAAADACkAbwwAAAIAPAAHAAkJ+xtQAQCMAgloDAAABgBbAGkMAAAHAFUAawwAAAcAUABqDAAABgBgAGwMAAAFAEkAbQwAAAMAOwDqDAAABgBQAG4MAAACACkAbwwAAAIAPAAJAAYJmRAOGwBxAQZoDAAAAQA3AGkMAAABADoAawwAAAEALwBtDAAAAQAYAOoMAAABADAAbgwAAAEAEwAAAA==.',
Si='Sigmandis:BAAALgAECgYJDQAAAA==.Siph:BAAALgAECgYJBgAAAA==.',
Sk='Sklook:BAAALgAECgEJAQAAAA==.Skolam:BAAALgADCgYJDAAAAA==.',
So='Somassen:BAAALgADCgYJCwAAAA==.Sorrengail:BAAALgAECgIJAgAAAA==.Soulforge:BAAALgAECgMJAwAAAA==.',
St='Stalestorn:BAAALgADCgIJAgAAAA==.',
Su='Sunquell:BAAALgAECgMJAwAAAA==.Surii:BAAALgAECgUJCwAAAA==.',
Sw='Sweeneytodd:BAAALgAECgEJAgAAAA==.',
Sy='Sybryn:BAAALgADCgIJAgAAAA==.',
Ta='Taliadrin:BAAALgADCgYJBgAAAA==.Tamarins:BAAALgAECgYJEwAAAA==.Taryeth:BAAALgADCgMJAwAAAA==.',
Te='Terkarakk:BAABLgAECn8aAAIRAAgJsCKRAgCUAghoDAAABQBfAGkMAAAEAFsAawwAAAQAVABqDAAAAwBWAGwMAAADAFMAbQwAAAEAUwDqDAAABABZAG4MAAACAFwAEQAICbAikQIAlAIIaAwAAAUAXwBpDAAABABbAGsMAAAEAFQAagwAAAMAVgBsDAAAAwBTAG0MAAABAFMA6gwAAAQAWQBuDAAAAgBcAAAA.',
Th='Thetamoon:BAAALgADCgUJBQAAAA==.Thireaux:BAAALgAECgQJBQAAAA==.Thorybos:BAAALgAECgMJBAAAAA==.',
To='Toom:BAAALgAECgUJDgAAAA==.',
Tr='Traylinna:BAAALgADCgQJBAAAAA==.Tritas:BAAALgADCggJEAABLgAECggJLgAXACwVAA==.Trophyhubby:BAABLgAECn8bAAMSAAcJpwySKwD6AAdoDAAABQAlAGkMAAAFAAwAawwAAAUAJwBqDAAAAwAkAGwMAAADABIA6gwAAAUAOABuDAAAAQAaABIABgkODZIrAPoABmgMAAADACUAaQwAAAMADABrDAAABAAnAGoMAAACACQAbAwAAAIAEgDqDAAAAgA4ABoABwnYAxovAOgAB2gMAAACAAUAaQwAAAIADABrDAAAAQAJAGoMAAABABMAbAwAAAEADwDqDAAAAwAGAG4MAAABAAkAAAA=.',
Tu='Tuladrin:BAAALgADCgQJBAAAAA==.',
Ty='Tyeren:BAAALgAECgYJDgAAAA==.Tyeriel:BAACLgAFFH8UAAMNAAUJfxRXMABFAQVoDAAABgBLAGkMAAAFAEUAawwAAAMAHABqDAAAAgA3AOoMAAAEACQADQAECX8UVzAARQEEaAwAAAYASwBpDAAABQBFAGsMAAADABwA6gwAAAQAJAAVAAEJAABNLQAAAAFqDAAAAgA3AC4ABAp/HAACDQAICf8e1CIAtAIADQAICf8e1CIAtAIAAAA=.Tyrîel:BAAALgADCgcJBwABLgAFFAUJFAANAH8UAA==.',
Us='Usato:BAAALgAECgUJBQAAAA==.',
Va='Valat:BAAALgADCgYJCwAAAA==.Valkyriefall:BAAALgAECgMJBQAAAA==.Valkyriewing:BAAALgAECgUJCAAAAA==.Valvet:BAAALgADCgkJKQAAAA==.Vardanis:BAAALgADCggJDwAAAA==.',
Vi='Vikril:BAAALgAECgYJBwAAAA==.Vincenzo:BAAALgAECgEJAgAAAA==.Vixer:BAAALgAECgQJBgAAAA==.',
Vo='Vog:BAAALgADCgYJBgAAAA==.Voidquèèn:BAAALgADCgEJAQAAAA==.Volkanoth:BAABLgAECn8VAAIOAAcJFSTiJQBvAgdoDAAABABiAGkMAAADAGAAawwAAAMAWgBqDAAAAgBiAGwMAAABAFgAbQwAAAEAVADqDAAABwBfAA4ABwkVJOIlAG8CB2gMAAAEAGIAaQwAAAMAYABrDAAAAwBaAGoMAAACAGIAbAwAAAEAWABtDAAAAQBUAOoMAAAHAF8AAAA=.',
Vu='Vue:BAAALgADCgcJBwABLgAECgYJCgAGAAAAAA==.',
Vy='Vylus:BAAALgAECgQJBAAAAA==.',
['Vá']='Vásh:BAAALgADCggJCAAAAA==.',
We='Weeblewobble:BAAALgADCgYJAwAAAA==.',
Wi='Wikidblade:BAAALgAECgQJCAAAAA==.William:BAAALgAECgYJDQAAAA==.Windee:BAAALgAECgYJEgAAAA==.',
Wr='Wrast:BAABLgAECn8UAAIcAAcJUwZ5EADvAAdoDAAABAAUAGkMAAAEABoAawwAAAUAHABqDAAAAwAPAGwMAAABAAgAbQwAAAEABwDqDAAAAgAGABwABwlTBnkQAO8AB2gMAAAEABQAaQwAAAQAGgBrDAAABQAcAGoMAAADAA8AbAwAAAEACABtDAAAAQAHAOoMAAACAAYAAAA=.',
Xy='Xyara:BAABLgAECn8bAAQWAAkJzxZHOACKAQloDAAABABCAGkMAAADADMAawwAAAQAOABqDAAAAwBbAGwMAAAEAFsAbQwAAAIAQgDqDAAABAA2AG4MAAACAEIAbwwAAAEADQAWAAYJphJHOACKAQZoDAAABABCAGkMAAACADMAawwAAAEAIgDqDAAABAA2AG4MAAABAEEAbwwAAAEADQALAAQJLx3GDADQAARqDAAAAQBbAGwMAAAEAFsAbQwAAAIAQgBuDAAAAQBCAB8AAwmgE2Y7AMYAA2kMAAABACsAawwAAAMAOABqDAAAAgA7AAAA.Xylaara:BAAALgAECgYJBgAAAA==.',
Ya='Yarine:BAAALgAECgEJAQAAAA==.',
Yo='Yoghurt:BAABLgAECn8lAAIhAAgJdSDoBwB1AghoDAAABgBdAGkMAAAGAFgAawwAAAUASgBqDAAABQBPAGwMAAAGAFYAbQwAAAIATADqDAAABQBOAG4MAAACAFMAIQAICXUg6AcAdQIIaAwAAAYAXQBpDAAABgBYAGsMAAAFAEoAagwAAAUATwBsDAAABgBWAG0MAAACAEwA6gwAAAUATgBuDAAAAgBTAAAA.',
Za='Zabimaru:BAAALgADCgYJCgAAAA==.Zalidus:BAABLgAFFH8FAAIiAAMJ9wulBQDtAANoDAAAAgAdAGkMAAABADQA6gwAAAIACQAiAAMJ9wulBQDtAANoDAAAAgAdAGkMAAABADQA6gwAAAIACQAAAA==.Zatika:BAABLgAECn8iAAMjAAgJkhWqAgC9AQhoDAAABwBHAGkMAAAFAEcAawwAAAUAQgBqDAAABQBOAGwMAAAFADMAbQwAAAIALQDqDAAABABHAG4MAAABAAYAIwAHCbYYqgIAvQEHaAwAAAYARwBpDAAABABHAGsMAAAEAEIAagwAAAQATgBsDAAABAAzAG0MAAABAC0A6gwAAAMARwAkAAgJ0gZeYwBSAQhoDAAAAQAWAGkMAAABABUAawwAAAEAEQBqDAAAAQAgAGwMAAABABMAbQwAAAEACQDqDAAAAQAYAG4MAAABAAYAAAA=.',
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
