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

local lookup = {'Warrior-Fury','Warrior-Protection','Paladin-Protection','Warlock-Affliction','Priest-Discipline','Priest-Holy','Paladin-Retribution','Unknown-Unknown','DeathKnight-Frost','DemonHunter-Havoc','Mage-Frost','DeathKnight-Blood','Warlock-Demonology','Warlock-Destruction','Mage-Fire','Druid-Restoration','DeathKnight-Unholy','Evoker-Augmentation','Warrior-Arms','Priest-Shadow','Evoker-Devastation','DemonHunter-Devourer','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Assassination','Monk-Brewmaster','Monk-Windwalker','Druid-Guardian','Paladin-Holy','Druid-Balance',}
local provider = {region='US',realm='TheForgottenCoast',name='US',type='daily',zone=46,date='2026-05-16',data={Aa='Aaricus:BAAALgAECgYJCAAAAA==.',
Ab='Aberdine:BAACLgAFFH8OAAIBAAQJXQtfGAAaAQRoDAAABQA0AGkMAAAEACQAawwAAAIADADqDAAAAwAPAAEABAldC18YABoBBGgMAAAFADQAaQwAAAQAJABrDAAAAgAMAOoMAAADAA8ALgAECn8qAAMBAAkJqRiKJwAgAgABAAkJqRiKJwAgAgACAAIJZw2dQQAsAAAAAA==.',
Ac='Accar:BAABLgAECn8aAAIDAAcJJhH7EwA3AQdoDAAABQBDAGkMAAAFADUAawwAAAUAKQBqDAAABABGAGwMAAACADIAbQwAAAEADgDqDAAABAAjAAMABwkmEfsTADcBB2gMAAAFAEMAaQwAAAUANQBrDAAABQApAGoMAAAEAEYAbAwAAAIAMgBtDAAAAQAOAOoMAAAEACMAAAA=.Achu:BAAALgAFFAIJAgABLgAFFAMJEAAEAAYmAA==.Acylies:BAAALgADCgEJAQAAAA==.',
Ae='Aerìth:BAAALgADCggJDQAAAA==.',
Ag='Agrias:BAABLgAECn8WAAMFAAgJHBeODQBAAghoDAAAAwBMAGkMAAADAFUAawwAAAMALwBqDAAAAwBQAGwMAAADAD8AbQwAAAEAIwDqDAAABQBHAG4MAAABAAwABQAICRwXjg0AQAIIaAwAAAMATABpDAAAAwBVAGsMAAADAC8AagwAAAMAUABsDAAAAgA/AG0MAAABACMA6gwAAAUARwBuDAAAAQAMAAYAAQmsDgtZAC8AAWwMAAABACUAAAA=.',
Al='Algodón:BAAALgADCgEJAQAAAA==.Aliera:BAAALgADCgcJCwAAAA==.',
Am='Ambry:BAAALgAECgQJDgABLgAECggJIgAHAPYOAA==.Ambryosia:BAABLgAECn8iAAIHAAgJ9g6WcgA/AQhoDAAABgBBAGkMAAAFAEEAawwAAAQAHgBqDAAABAAkAGwMAAAEACYAbQwAAAMAEADqDAAABgAoAG4MAAACAAoABwAICfYOlnIAPwEIaAwAAAYAQQBpDAAABQBBAGsMAAAEAB4AagwAAAQAJABsDAAABAAmAG0MAAADABAA6gwAAAYAKABuDAAAAgAKAAAA.',
An='Andras:BAAALgAECgIJAgAAAA==.Angerßane:BAAALgADCgMJAwAAAA==.',
Ap='Apocketheory:BAAALgADCgcJBwAAAA==.',
Ar='Aradora:BAAALgADCgQJBQAAAA==.Arcanyounot:BAAALgADCgUJBQABLgAECgYJCgAIAAAAAA==.',
As='Aspir:BAEALgAECgcJEwABLgAFFAUJEAAJAIceAA==.',
Au='Auh:BAAALgAECgMJAwAAAA==.',
Av='Avera:BAAALgAECgIJAgAAAA==.Aviael:BAABLgAECn8eAAIKAAYJYBGzIAAMAQZoDAAABQAtAGkMAAAGAC8AawwAAAYAMQBqDAAABQAmAGwMAAACACkA6gwAAAYAJQAKAAYJYBGzIAAMAQZoDAAABQAtAGkMAAAGAC8AawwAAAYAMQBqDAAABQAmAGwMAAACACkA6gwAAAYAJQAAAA==.',
Aw='Awfulshotz:BAAALgAECgMJAwABLgAECgYJIAALAOAUAA==.',
Ba='Badwolf:BAAALgAECgQJBwAAAA==.Bain:BAAALgADCgMJAwAAAA==.Bananabard:BAAALgADCgUJBQAAAA==.Barricade:BAABLgAECn8aAAMCAAkJHRdLFgCrAQloDAAABQBDAGkMAAADADsAawwAAAMAOQBqDAAAAwBaAGwMAAADACcAbQwAAAIAUgDqDAAABABXAG4MAAACADQAbwwAAAEAGwACAAkJHRdLFgCrAQloDAAABABDAGkMAAADADsAawwAAAIAOQBqDAAAAgBaAGwMAAACACcAbQwAAAIAUgDqDAAABABXAG4MAAACADQAbwwAAAEAGwABAAQJKRCkUwCnAARoDAAAAQAiAGsMAAABADMAagwAAAEAHQBsDAAAAQAmAAAA.',
Bc='Bcrogue:BAAALgADCgEJAQABLgAECgcJGwAMADIfAA==.Bcwarrior:BAAALgAECgYJCQABLgAECgcJGwAMADIfAA==.',
Be='Belgrove:BAAALgADCgEJAQAAAA==.',
Bi='Bigbaauls:BAAALgAECgYJCQAAAA==.',
Bj='Björk:BAAALgAECgUJBQABLgAECgYJEwAIAAAAAA==.',
Bl='Blizzaga:BAAALgAECgQJCAAAAA==.',
Bo='Boiardi:BAAALgAECgEJAQAAAA==.Bootowsky:BAAALgAECgQJBAAAAA==.Boromen:BAAALgADCgEJAQAAAA==.Boutros:BAAALgADCgYJBgAAAA==.Bowberto:BAAALgAECgEJAwAAAA==.',
Br='Brea:BAAALgADCgEJAQAAAA==.Briélle:BAAALgADCgMJAwAAAA==.Brocephus:BAAALgAECgQJCQAAAA==.',
Bu='Burrgold:BAAALgAECgcJDgAAAA==.',
Ca='Cadya:BAAALgAECgUJBQAAAA==.',
Ce='Celticwoman:BAABLgAECn8jAAMNAAcJyglRdQAVAQdoDAAABgAZAGkMAAAGACIAawwAAAYAFgBqDAAABQA3AGwMAAAFACwAbQwAAAEACQDqDAAABgAOAA0ABwnKCVF1ABUBB2gMAAAEABkAaQwAAAQAIgBrDAAABAAWAGoMAAAEADcAbAwAAAUALABtDAAAAQAJAOoMAAAEAA4ADgAFCckEeTsAxgAFaAwAAAIAEgBpDAAAAgAKAGsMAAACAAkAagwAAAEADQDqDAAAAgAKAAAA.',
Ch='Champina:BAAALgAECgYJCQAAAA==.Chaoticelf:BAAALgADCgcJBwAAAA==.Chickenugget:BAABLgAECn8dAAIPAAYJcwVPBwDFAAZoDAAABgAOAGkMAAAGAAwAawwAAAYADQBqDAAABAAPAGwMAAADAA0A6gwAAAQADwAPAAYJcwVPBwDFAAZoDAAABgAOAGkMAAAGAAwAawwAAAYADQBqDAAABAAPAGwMAAADAA0A6gwAAAQADwAAAA==.Choral:BAAALgAECgMJBQAAAA==.Chubzilla:BAAALgADCgUJBQAAAA==.Chuckwagaon:BAAALgAECgEJAQAAAA==.',
Ci='Cinderdorla:BAABLgAFFH8FAAIQAAIJGCKjKwDIAAJoDAAAAgBQAOoMAAADAF4AEAACCRgioysAyAACaAwAAAIAUADqDAAAAwBeAAEuAAUUAwkMAAcAoB8A.',
Cl='Clockie:BAACLgAFFH8QAAMEAAMJBiYUCABuAANoDAAABwBhAGkMAAACAGIA6gwAAAcAYAANAAIJ0iUOKwDFAAJoDAAABwBhAOoMAAAHAGAABAABCW8mFAgAbgABaQwAAAIAYgAuAAQKfzsABA0ACQnoJOgoAPsBAA0ABwkUJOgoAPsBAAQABglaJTYIAMgBAA4ABAkKH7MjADsBAAAA.Clõüd:BAABLgAECn8UAAIHAAgJuQ4FXQBwAQhoDAAAAwAYAGkMAAADACgAawwAAAMAMABqDAAAAwAqAGwMAAADADcAbQwAAAEAEQDqDAAAAwAoAG4MAAABACYABwAICbkOBV0AcAEIaAwAAAMAGABpDAAAAwAoAGsMAAADADAAagwAAAMAKgBsDAAAAwA3AG0MAAABABEA6gwAAAMAKABuDAAAAQAmAAEuAAUUBQkRAAsAGQ0A.',
Co='Coldarc:BAAALgADCgYJBgAAAA==.',
Cu='Cuitlahuac:BAAALgAECgEJAwAAAA==.Cupra:BAAALgADCgUJBQAAAA==.',
['Cô']='Cônky:BAAALgAECgYJEAAAAA==.',
Da='Dade:BAAALgAECgYJCAAAAA==.Dadeleviathn:BAAALgADCgEJAQABLgAECgYJCAAIAAAAAA==.Dagrul:BAAALgADCgUJBQAAAA==.Danteangelo:BAAALgAECgEJAQAAAA==.Darrkmann:BAAALgAECggJEwAAAA==.',
De='Deathrotull:BAAALgADCgUJBwAAAA==.Deathslice:BAAALgADCgMJAwAAAA==.Delita:BAAALgAECgQJBwAAAA==.',
Di='Dietdrkelp:BAAALgADCgUJBQABLgAECgEJAQAIAAAAAA==.',
Dk='Dkcloud:BAABLgAECn8cAAIRAAcJUx+5MAD3AQdoDAAABgBTAGkMAAAEAFYAawwAAAQAVABqDAAAAwBIAGwMAAAEAFsAbQwAAAIANQDqDAAABQBSABEABwlTH7kwAPcBB2gMAAAGAFMAaQwAAAQAVgBrDAAABABUAGoMAAADAEgAbAwAAAQAWwBtDAAAAgA1AOoMAAAFAFIAAS4ABRQFCREACwAZDQA=.',
Do='Donella:BAAALgADCgIJAgAAAA==.Doughboy:BAAALgAECgQJBwAAAA==.',
Dr='Drawinddy:BAAALgAFFAIJAgAAAA==.Drifty:BAAALgAECgYJCwAAAA==.',
Du='Duoduo:BAABLgAFFH8KAAISAAIJMyEKFQDGAAJoDAAABQBcAOoMAAAFAE0AEgACCTMhChUAxgACaAwAAAUAXADqDAAABQBNAAEuAAUUAwkMAAcAoB8A.Duoduomoney:BAABLgAFFH8GAAMTAAIJfBOIGwCEAAJoDAAAAwAtAOoMAAADADYAAQACCXwTgSsAlwACaAwAAAEALQDqDAAAAQA2ABMAAgnjDogbAIQAAmgMAAACACUA6gwAAAIAJgABLgAFFAMJDAAHAKAfAA==.',
['Dø']='Dønut:BAAALgADCgUJBQAAAA==.',
Eb='Eboncelest:BAABLgAFFH8JAAIUAAIJVQ64DwCnAAJoDAAABQAoAOoMAAAEACAAFAACCVUOuA8ApwACaAwAAAUAKADqDAAABAAgAAEuAAUUAwkQAAQABiYA.',
Ec='Eclesiastes:BAAALgAECgEJAQAAAA==.',
El='Eldarcirdan:BAAALgAECggJDgAAAA==.',
Es='Esme:BAAALgADCgkJDwAAAA==.',
Et='Etrigon:BAAALgAECgEJAQAAAA==.',
Ev='Evajoh:BAAALgADCgUJBQAAAA==.',
Ex='Executioner:BAAALgADCgcJDwAAAA==.',
Fa='Fartstink:BAAALgADCgYJBwAAAA==.',
Fe='Festuss:BAAALgAECgQJCgAAAA==.',
Fi='Fingrwaglr:BAABLgAECn8gAAIVAAYJkwoiDQD3AAZoDAAABgAuAGkMAAAGABcAawwAAAYAGABqDAAABQAiAGwMAAADABUA6gwAAAYAEgAVAAYJkwoiDQD3AAZoDAAABgAuAGkMAAAGABcAawwAAAYAGABqDAAABQAiAGwMAAADABUA6gwAAAYAEgAAAA==.Fizzlebliss:BAAALgADCgYJBgAAAA==.',
Fo='Forlin:BAAALgADCggJEQAAAA==.',
Fr='Frostlowe:BAAALgAECggJCQAAAA==.',
Fu='Fuzziestbutt:BAAALgADCgMJAwAAAA==.',
['Fú']='Fúsion:BAEALgAECgMJBgABLgAECgkJMwAWAHYiAA==.',
Ga='Gambokni:BAAALgADCgcJFAAAAA==.Gamebread:BAAALgAECgUJCAAAAA==.',
Gi='Giganate:BAAALgADCgEJAQABLgAECgQJBAAIAAAAAA==.Gixx:BAAALgAECgYJEAABLgAECggJIAAHAM4UAA==.',
Gl='Glorr:BAAALgAECgEJAQAAAA==.',
Go='Gonamanar:BAAALgAECgYJBAAAAA==.Goth:BAAALgADCgEJAQAAAA==.Gourge:BAAALgAECgcJDAAAAA==.',
Gr='Grimfall:BAABLgAECn8sAAQXAAgJ7hyKDAAcAghoDAAACABNAGkMAAAHAFQAawwAAAcAWABqDAAABgBLAGwMAAAFADYAbQwAAAIAMADqDAAABwBcAG4MAAACAEcAFwAICTQbigwAHAIIaAwAAAQATABpDAAABABFAGsMAAAEAEkAagwAAAQAMgBsDAAABAA2AG0MAAACADAA6gwAAAQAXABuDAAAAgBHABgABQlyHttAAKwBBWgMAAABAE0AaQwAAAIAVABrDAAAAgBYAGoMAAACAEsA6gwAAAEAPQAZAAUJLBNOTwASAQVoDAAAAwA7AGkMAAABADYAawwAAAEALwBsDAAAAQAcAOoMAAACADYAAAA=.Grimtyr:BAAALgAECgEJAQAAAA==.Grëëdo:BAABLgAECn8gAAMHAAgJzhSySwCdAQhoDAAABQA9AGkMAAAHAEcAawwAAAQAOgBqDAAABABRAGwMAAADADsAbQwAAAEAFgDqDAAABgA6AG4MAAACACgABwAICc4UsksAnQEIaAwAAAUAPQBpDAAABgBHAGsMAAADADoAagwAAAMAUQBsDAAAAwA7AG0MAAABABYA6gwAAAYAOgBuDAAAAgAoAAMAAwkzBbg3ADwAA2kMAAABABQAawwAAAEABgBqDAAAAQAKAAAA.',
Gy='Gylvi:BAAALgADCgMJAwABLgAECgYJHgAKAGARAA==.',
Hi='Hikiru:BAAALgADCgkJHgAAAA==.',
Ho='Hollowbane:BAABLgAECn8eAAMaAAgJIBZ9FQCdAQhoDAAABQA6AGkMAAAFAEIAawwAAAQANABqDAAAAwBSAGwMAAADACkAbQwAAAMAQQDqDAAABQBMAG4MAAACACQAGgAICXsVfRUAnQEIaAwAAAMALwBpDAAAAwBCAGsMAAADADQAagwAAAMAUgBsDAAAAwApAG0MAAADAEEA6gwAAAUATABuDAAAAgAkABsAAwmkFi8RAM8AA2gMAAACADoAaQwAAAIAPwBrDAAAAQAzAAAA.Holydh:BAAALgAECgEJAQAAAA==.Holydragonn:BAAALgADCgQJBAAAAA==.Holylock:BAAALgAECgQJCAAAAA==.Holylordpig:BAAALgAFFAIJAgAAAA==.Holyshaman:BAAALgAFFAIJAwAAAA==.Holywarrior:BAAALgAFFAEJAQAAAA==.Holyymonk:BAAALgAECgEJAQAAAA==.Homdantor:BAAALgAECgUJBQAAAA==.Horse:BAAALgAECgYJBwABLgAFFAgJFAAWAKcZAA==.Hotyogafire:BAAALgAECgMJAwAAAA==.',
Ia='Iampally:BAAALgADCggJCQAAAA==.',
Im='Imhim:BAAALgAECgEJAQAAAA==.Imogen:BAAALgAECgcJEgAAAA==.',
Ja='Jadeddruid:BAAALgAECgkJCQAAAA==.Jamieson:BAACLgAFFH8RAAILAAUJGQ1pRAAwAQVoDAAABQA2AGkMAAAEACgAawwAAAIADgBqDAAAAQARAOoMAAAFABcACwAFCRkNaUQAMAEFaAwAAAUANgBpDAAABAAoAGsMAAACAA4AagwAAAEAEQDqDAAABQAXAC4ABAp/NAACCwAJCf0f4hEAugIACwAJCf0f4hEAugIAAAA=.Jand:BAAALgAECgYJDQAAAA==.Jazashi:BAAALgAECgYJFwAAAQ==.',
Jo='Jonesknight:BAAALgAECgYJCgAAAA==.Jonnytsunami:BAAALgAECgQJBwAAAA==.',
Ju='Juicycow:BAAALgAECgYJCwAAAA==.',
Ka='Kahoru:BAAALgADCgcJBwAAAA==.Kailler:BAAALgAECgEJAQAAAA==.Kainn:BAAALgAECgYJEAAAAA==.',
Ke='Keg:BAACLgAFFH8eAAIcAAYJoSZmAQA8AgZoDAAABwBkAGkMAAAHAGMAawwAAAUAYQBqDAAABABhAGwMAAABAGEA6gwAAAYAYwAcAAYJoSZmAQA8AgZoDAAABwBkAGkMAAAHAGMAawwAAAUAYQBqDAAABABhAGwMAAABAGEA6gwAAAYAYwAuAAQKfyAAAxwACAnPJksCAHcDABwACAnPJksCAHcDAB0AAQlVITVaAFsAAAAA.',
Kh='Khakuzu:BAAALgADCgIJAgAAAA==.',
Ki='Kikinak:BAAALgAECgQJBAAAAA==.Killshøt:BAAALgADCgEJAQAAAA==.Kitty:BAACLgAFFH8KAAIeAAMJgQiKDgCSAANoDAAABQAjAGkMAAADABEA6gwAAAIACwAeAAMJgQiKDgCSAANoDAAABQAjAGkMAAADABEA6gwAAAIACwAuAAQKfxkAAh4ACAmuETkPAIgBAB4ACAmuETkPAIgBAAAA.Kittyhawk:BAAALgAECggJDgAAAA==.',
Kk='Kk:BAAALgAECgYJEwAAAA==.',
Kl='Klassic:BAAALgAECgQJBQAAAA==.Klixx:BAAALgAECgEJAgAAAA==.',
Ko='Konexx:BAAALgADCgMJAwAAAA==.',
Ks='Kstab:BAABLgAECn8YAAIaAAcJLBuIGgAuAgdoDAAAAwBKAGkMAAAEAEoAawwAAAQAUgBqDAAABAAvAGwMAAABACEA6gwAAAQAOwBuDAAABABcABoABwksG4gaAC4CB2gMAAADAEoAaQwAAAQASgBrDAAABABSAGoMAAAEAC8AbAwAAAEAIQDqDAAABAA7AG4MAAAEAFwAAAA=.',
Ku='Kuromeow:BAABLgAFFH8HAAILAAIJYRl9NgC9AAJoDAAAAgAoAOoMAAAFAFkACwACCWEZfTYAvQACaAwAAAIAKADqDAAABQBZAAAA.',
La='Lachasis:BAAALgAECgQJBAAAAA==.Larake:BAAALgAECgYJEAAAAA==.Lazypie:BAAALgAECgUJBQAAAA==.',
Le='Leggomyaggro:BAAALgAECgMJBQABLgAFFAMJDAAMAAkkAA==.Lesiania:BAAALgAECgEJAQABLgAECgYJCAAIAAAAAA==.',
Li='Licus:BAAALgADCgkJFAAAAA==.Lightkeeper:BAABLgAECn8eAAMUAAgJTRcEFADgAQhoDAAABQBMAGkMAAAFAEgAawwAAAQANQBqDAAABAAXAGwMAAADADkAbQwAAAMAMwDqDAAABABOAG4MAAACABoAFAAICU0XBBQA4AEIaAwAAAQATABpDAAABABIAGsMAAADADUAagwAAAQAFwBsDAAAAwA5AG0MAAADADMA6gwAAAQATgBuDAAAAgAaAAYAAwnvBO9sAHYAA2gMAAABAAMAaQwAAAEADQBrDAAAAQAUAAAA.Lightning:BAAALgADCgEJAQAAAA==.Limpßrisket:BAAALgAECgMJAgAAAA==.Litdealer:BAAALgAECgYJDgABLgAFFAMJCQAcALcVAA==.Littlestiffy:BAAALgADCgMJAwAAAA==.',
Lr='Lroux:BAAALgAECgYJDQAAAA==.',
Lu='Lucyah:BAAALgAECgMJBAAAAA==.',
Ma='Malkallam:BAAALgADCgUJBQAAAA==.Manaplague:BAAALgAECgUJCwAAAA==.Manenya:BAAALgAECgYJCAAAAA==.Marotto:BAAALgAECgMJAwAAAA==.Massacar:BAABLgAECn8YAAIWAAYJSgo5igAPAQZoDAAABQArAGkMAAAFACoAawwAAAUAEgBqDAAABAAoAGwMAAACAA4A6gwAAAMADQAWAAYJSgo5igAPAQZoDAAABQArAGkMAAAFACoAawwAAAUAEgBqDAAABAAoAGwMAAACAA4A6gwAAAMADQABLgAECggJIAAHAM4UAA==.',
Me='Meatpuller:BAAALgADCgkJDwAAAA==.Menion:BAABLgAECn8cAAMHAAkJZhuLJgCMAgloDAAABABWAGkMAAAEAF0AawwAAAQAWABqDAAABABQAGwMAAADAD8AbQwAAAEAJQDqDAAABABUAG4MAAADAEQAbwwAAAEAJgAHAAkJZhuLJgCMAgloDAAAAwBWAGkMAAADAF0AawwAAAMAWABqDAAAAwBQAGwMAAACAD8AbQwAAAEAJQDqDAAABABUAG4MAAADAEQAbwwAAAEAJgADAAUJQgy7JACdAAVoDAAAAQAeAGkMAAABAAsAawwAAAEAMwBqDAAAAQAUAGwMAAABACAAAAA=.Meowmeowmeow:BAAALgADCgcJBwABLgAFFAYJGAARAFoXAA==.Mercadius:BAAALgAECgYJEAAAAA==.Metalx:BAAALgADCgkJFQAAAA==.',
Mi='Minkyu:BAAALgAECgMJBAAAAA==.Misha:BAAALgADCgEJAQAAAA==.',
Mk='Mk:BAEALgADCggJCAABLgAECggJNwAdAGsjAA==.',
Mo='Monkpig:BAACLgAFFH8OAAIcAAMJJR4GIAD8AANoDAAABgBKAGkMAAACAEwA6gwAAAYAUAAcAAMJJR4GIAD8AANoDAAABgBKAGkMAAACAEwA6gwAAAYAUAAuAAQKfyoAAhwACQn5H8IPAAUCABwACQn5H8IPAAUCAAAA.Mooinator:BAAALgADCgYJBgAAAA==.',
My='Myrai:BAAALgADCgEJAQAAAA==.',
Na='Nanashi:BAABLgAECn8YAAIKAAYJTRWDHQAoAQZoDAAABgA2AGkMAAAEADEAawwAAAMAOQBqDAAABAAmAGwMAAAEAD0A6gwAAAMAMQAKAAYJTRWDHQAoAQZoDAAABgA2AGkMAAAEADEAawwAAAMAOQBqDAAABAAmAGwMAAAEAD0A6gwAAAMAMQAAAA==.Nannerz:BAAALgAECgYJEQAAAA==.Natenasty:BAAALgADCgUJBQABLgAECgQJBAAIAAAAAA==.Natenomoney:BAAALgAECgQJBAAAAA==.Nathan:BAAALgAECgMJAwABLgAECgQJBAAIAAAAAA==.',
Nd='Ndeh:BAAALgAFFAEJAQAAAA==.',
Ne='Nena:BAAALgAECgEJAQAAAA==.Nermonhunder:BAAALgAECgQJCAAAAA==.',
Ni='Ninjitsû:BAABLgAECn8aAAIWAAgJuBziHQCeAghoDAAABABLAGkMAAAEAEcAawwAAAQAPwBqDAAABABaAGwMAAADAFgAbQwAAAEAMgDqDAAABABTAG4MAAACAFIAFgAICbgc4h0AngIIaAwAAAQASwBpDAAABABHAGsMAAAEAD8AagwAAAQAWgBsDAAAAwBYAG0MAAABADIA6gwAAAQAUwBuDAAAAgBSAAAA.',
Ol='Oldspice:BAAALgAECgMJBAAAAA==.Olex:BAAALgAECgUJBQAAAA==.',
Om='Omgkangel:BAABLgAECn8VAAIMAAYJnBZCHAAMAQZoDAAABAAzAGkMAAAEADcAawwAAAQASABqDAAAAwBAAGwMAAACACoA6gwAAAQAQgAMAAYJnBZCHAAMAQZoDAAABAAzAGkMAAAEADcAawwAAAQASABqDAAAAwBAAGwMAAACACoA6gwAAAQAQgAAAA==.Omi:BAAALgADCgYJBgAAAA==.Omie:BAAALgAECgEJBAAAAA==.',
On='Onoos:BAAALgAECgMJBgAAAA==.',
Ov='Overpower:BAAALgADCgIJAgABLgAECgkJKwARAMcUAA==.Ovix:BAAALgADCgMJAQABLgAECgUJDAAIAAAAAA==.',
Ow='Ow:BAAALgADCgEJAQAAAA==.',
Pa='Paulos:BAAALgAECgUJBgAAAA==.',
Pe='Peaf:BAABLgAECn8gAAMBAAYJlyD4IACdAQZoDAAABgBiAGkMAAAGAEAAawwAAAYAXwBqDAAABQBSAGwMAAADAFMA6gwAAAYASwABAAYJlyD4IACdAQZoDAAABQBiAGkMAAAFAEAAawwAAAYAXwBqDAAABABSAGwMAAADAFMA6gwAAAUASwACAAQJnAuvMABzAARoDAAAAQAbAGkMAAABABkAagwAAAEAEwDqDAAAAQAkAAAA.Petesfeets:BAAALgADCgYJCAAAAA==.',
Pl='Playajizoe:BAAALgAECgQJBwAAAA==.',
Po='Pocketsnacks:BAAALgADCgEJAQAAAA==.Poppabanger:BAAALgAECgQJBwAAAA==.',
Qu='Quill:BAABLgAECn8eAAIRAAcJrB1CSwARAgdoDAAABgBYAGkMAAAFAEoAawwAAAUAPABqDAAABQBRAGwMAAADAEYAbQwAAAEAYADqDAAABQBCABEABwmsHUJLABECB2gMAAAGAFgAaQwAAAUASgBrDAAABQA8AGoMAAAFAFEAbAwAAAMARgBtDAAAAQBgAOoMAAAFAEIAAS4ABRQDCQQACAAAAAA=.',
Ra='Raythe:BAABLgAECn8cAAIKAAcJ5hVDGABaAQdoDAAABABFAGkMAAAGAE0AawwAAAQAPQBqDAAABAAXAGwMAAADACwAbQwAAAEAFADqDAAABgA+AAoABwnmFUMYAFoBB2gMAAAEAEUAaQwAAAYATQBrDAAABAA9AGoMAAAEABcAbAwAAAMALABtDAAAAQAUAOoMAAAGAD4AAAA=.Razzeman:BAAALgAECgEJAQAAAA==.Razzledazzl:BAAALgAECgEJAQAAAA==.',
Ro='Rose:BAAALgAECgcJCgABLgAFFAMJCgAeAIEIAA==.',
Ru='Rucker:BAABLgAECn8hAAMCAAkJfRtVBgBlAgloDAAABgA+AGkMAAAGAFwAawwAAAUAPwBqDAAAAgA2AGwMAAADAFsAbQwAAAIAPgDqDAAABQBdAG4MAAADACcAbwwAAAEAOgACAAkJfRtVBgBlAgloDAAABgA+AGkMAAAGAFwAawwAAAQAPwBqDAAAAgA2AGwMAAADAFsAbQwAAAIAPgDqDAAABQBdAG4MAAADACcAbwwAAAEAOgABAAEJWAIVtQAdAAFrDAAAAQAGAAAA.Ruckkin:BAAALgAECgMJAwABLgAECgkJIQACAH0bAA==.Rucksy:BAABLgAECn8kAAMDAAgJZh0RBQCrAghoDAAABgBcAGkMAAAGAGIAawwAAAcAXwBqDAAABQBXAGwMAAAFAEsAbQwAAAEAKADqDAAABQBbAG4MAAABAB8AAwAICWYdEQUAqwIIaAwAAAYAXABpDAAABgBiAGsMAAAGAF8AagwAAAQAVwBsDAAABQBLAG0MAAABACgA6gwAAAQAWwBuDAAAAQAfAAcAAwn+Ebf9AJkAA2sMAAABAB4AagwAAAEAOgDqDAAAAQA9AAEuAAQKCQkhAAIAfRsA.Ruxsi:BAAALgAECgUJCAABLgAECgkJIQACAH0bAA==.',
Ry='Ryan:BAABLgAECn8XAAMfAAcJ+yFGKgDgAQdoDAAABQBdAGkMAAADAFUAawwAAAQAYgBqDAAABABdAGwMAAADAEgAbQwAAAEATQDqDAAAAwBXAB8ABgk/IUYqAOABBmgMAAACAF0AaQwAAAEAVQBqDAAAAwBdAGwMAAABAEgAbQwAAAEATQDqDAAAAgBXAAcABgmYIt85ANUBBmgMAAADAGEAaQwAAAIATABrDAAABABYAGoMAAABAGEAbAwAAAIAXADqDAAAAQBYAAAA.',
['Rì']='Rìptide:BAAALgAECgkJEQAAAA==.',
['Rô']='Rôrônoazoro:BAAALgADCgYJCwAAAA==.',
Sa='Saragdan:BAAALgADCgcJCwAAAA==.',
Sc='Scylla:BAAALgAECgYJBgABLgAECgYJDwAIAAAAAA==.',
Se='Seraphae:BAAALgADCgQJBAAAAA==.Sereb:BAAALgAECgQJBAAAAA==.',
Sh='Shadowscurry:BAAALgAECgQJBAAAAA==.Shankzmcgee:BAABLgAECn8cAAIaAAYJcQrRJwD7AAZoDAAABwApAGkMAAAHAB4AawwAAAYAGgBqDAAABAATAGwMAAACABUA6gwAAAIADQAaAAYJcQrRJwD7AAZoDAAABwApAGkMAAAHAB4AawwAAAYAGgBqDAAABAATAGwMAAACABUA6gwAAAIADQABLgAECggJIAAHAM4UAA==.Shardik:BAAALgAECgEJAQAAAA==.Sheero:BAAALgAECgUJBQAAAA==.Sheong:BAAALgAECgkJCwAAAA==.Sheñ:BAAALgADCgkJGAAAAA==.Shindark:BAAALgAECgEJAgAAAA==.Shivah:BAAALgAECgcJCwABLgAFFAMJBAAIAAAAAA==.Shrus:BAAALgAECgYJBgAAAA==.Shrussy:BAAALgADCgMJAwAAAA==.Shèrlock:BAAALgAECgcJDgAAAA==.',
Sk='Skippydippy:BAAALgAECgQJCwAAAA==.Skylin:BAAALgAECgEJAwAAAA==.',
Sl='Sleezee:BAAALgAECgMJBgAAAA==.Slushpuppis:BAAALgADCgcJBwAAAA==.',
Sn='Sneeger:BAAALgADCgYJDAAAAA==.',
Sp='Spelldeala:BAAALgAECgYJEAABLgAFFAMJCQAcALcVAA==.',
St='Stargasm:BAAALgAFFAEJAQAAAA==.Stdmachine:BAAALgAECgYJDAAAAA==.Stonedstoner:BAAALgAECgUJBQAAAA==.',
Su='Superdump:BAAALgAECgcJAgAAAA==.',
Sw='Swiftmend:BAABLgAFFH8JAAIQAAIJtw7UPACAAAJoDAAABAAnAOoMAAAFACMAEAACCbcO1DwAgAACaAwAAAQAJwDqDAAABQAjAAEuAAUUAwkJABwAtxUA.',
Sy='Syllal:BAAALgADCgQJBAAAAA==.Synisttir:BAAALgAECgEJAQAAAA==.',
Ta='Taft:BAABLgAECn8vAAIgAAkJjBNaEwDoAQloDAAABQA9AGkMAAAIAD8AawwAAAcAOwBqDAAABwA5AGwMAAAGACUAbQwAAAQALQDqDAAABAA4AG4MAAAEADEAbwwAAAIAGwAgAAkJjBNaEwDoAQloDAAABQA9AGkMAAAIAD8AawwAAAcAOwBqDAAABwA5AGwMAAAGACUAbQwAAAQALQDqDAAABAA4AG4MAAAEADEAbwwAAAIAGwAAAA==.Tardis:BAAALgADCgcJCgAAAA==.Taterz:BAAALgADCgQJBAAAAA==.',
Te='Terrá:BAAALgADCgkJFQAAAA==.Teryn:BAAALgAECgEJAQAAAA==.Tesa:BAAALgADCgMJBQAAAA==.',
Th='Thomassian:BAAALgAECgEJAgAAAA==.',
Ti='Timewing:BAAALgADCggJFAAAAA==.Timtoo:BAAALgAECgMJBQAAAA==.',
To='Toborntwob:BAAALgAECgYJCwAAAA==.',
Tr='Transformer:BAAALgAECgQJBgAAAA==.Triblequest:BAAALgAECgYJDwAAAA==.Tritin:BAAALgAECgYJDwAAAA==.',
Tw='Twiltock:BAAALgAECgYJDAAAAA==.Twizztyd:BAAALgAECgEJAQAAAA==.Twocups:BAAALgAECgUJCgAAAA==.',
Un='Underware:BAAALgADCgYJBgAAAA==.',
Va='Valessa:BAABLgAECn8gAAILAAYJCAZGtgDcAAZoDAAABgAPAGkMAAAGABQAawwAAAYABABqDAAABQAUAGwMAAAEABIA6gwAAAUAEAALAAYJCAZGtgDcAAZoDAAABgAPAGkMAAAGABQAawwAAAYABABqDAAABQAUAGwMAAAEABIA6gwAAAUAEAAAAA==.Valiria:BAABLgAECn8ZAAIWAAcJnRxZMQA1AgdoDAAAAwBQAGkMAAAFAF0AawwAAAQASgBqDAAABABgAGwMAAACAE4A6gwAAAYAXwBuDAAAAQAQABYABwmdHFkxADUCB2gMAAADAFAAaQwAAAUAXQBrDAAABABKAGoMAAAEAGAAbAwAAAIATgDqDAAABgBfAG4MAAABABAAAAA=.Varzul:BAAALgADCgYJCwABLgAECgIJAgAIAAAAAA==.',
Ve='Velieda:BAABLgAECn8cAAMHAAgJ7Q89YQBmAQhoDAAABQAoAGkMAAAEAC0AawwAAAQAKABqDAAAAgA6AGwMAAADADEAbQwAAAIAFgDqDAAABAAcAG4MAAAEADkABwAICQYOPWEAZgEIaAwAAAIAJwBpDAAAAgAkAGsMAAACACgAagwAAAEAEgBsDAAAAgAiAG0MAAACABYA6gwAAAIAFABuDAAABAA5AAMABgkQEEgbAOgABmgMAAADACgAaQwAAAIALQBrDAAAAgAoAGoMAAABADoAbAwAAAEAMQDqDAAAAgAcAAAA.',
Vi='Vindication:BAACLgAFFH8MAAIMAAMJCSRlDAA2AQNoDAAABQBgAGkMAAADAGAA6gwAAAQAUwAMAAMJCSRlDAA2AQNoDAAABQBgAGkMAAADAGAA6gwAAAQAUwAuAAQKfyAAAgwACAkJIC4HAL0CAAwACAkJIC4HAL0CAAAA.Vita:BAAALgAECgYJBwAAAA==.',
Wa='Wackah:BAAALgAECgYJCQAAAA==.Wakana:BAAALgAECgIJAgAAAA==.',
Wi='Windflower:BAAALgADCgQJBAAAAA==.',
Wo='Wolfcarver:BAAALgAECgYJEAAAAA==.Worldbreakèr:BAAALgAECggJAQAAAA==.',
Xi='Xiaobao:BAAALgAECgQJBAAAAA==.Xiaoduoduo:BAACLgAFFH8MAAMHAAMJoB8WMQAWAQNoDAAABQBfAGkMAAABAEAA6gwAAAYAUgAHAAMJoB8WMQAWAQNoDAAABABfAGkMAAABAEAA6gwAAAYAUgAfAAEJuCNpLwBhAAFoDAAAAQBbAC4ABAp/KgACBwAJCaUjDxQAkAIABwAJCaUjDxQAkAIAAAA=.Xiaomak:BAAALgADCgQJBAAAAA==.Xiaoxiongmao:BAAALgADCgcJBwAAAA==.',
Xs='Xschaferr:BAAALgAECgYJCQAAAA==.',
Za='Zabz:BAAALgADCgQJBAABLgAECggJJwAHAHsgAA==.',
Ze='Zeroskills:BAABLgAECn8dAAMaAAkJJQZqGwBgAQloDAAABAAKAGkMAAAEABEAawwAAAQAEwBqDAAAAwAQAGwMAAADABgAbQwAAAIAAwDqDAAABQAUAG4MAAADABMAbwwAAAEACQAaAAkJJQZqGwBgAQloDAAAAwAKAGkMAAADABEAawwAAAQAEwBqDAAAAwAQAGwMAAADABgAbQwAAAIAAwDqDAAABQAUAG4MAAADABMAbwwAAAEACQAbAAIJSwQ2GgBUAAJoDAAAAQAHAGkMAAABAA4AAAA=.',
Zu='Zulinar:BAAALgAECgYJBwAAAA==.Zumoku:BAAALgADCgkJKQAAAA==.',
['Às']='Àsmodeus:BAABLgAECn8oAAQeAAkJcxELDQCoAQloDAAABgBMAGkMAAAHAC0AawwAAAgAJgBqDAAABwAyAGwMAAADADMAbQwAAAEAHADqDAAABgA8AG4MAAABACMAbwwAAAEAEwAeAAkJcxELDQCoAQloDAAABgBMAGkMAAAHAC0AawwAAAcAJgBqDAAABwAyAGwMAAADADMAbQwAAAEAHADqDAAABQA8AG4MAAABACMAbwwAAAEAEwAgAAEJ8gaJcAAoAAFrDAAAAQARABAAAQkxCrq4ACYAAeoMAAABABoAAAA=.',
['Æn']='Ænimá:BAAALgADCgEJAQAAAA==.',
['ßi']='ßiggysmalls:BAAALgADCgUJBQAAAA==.',
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
