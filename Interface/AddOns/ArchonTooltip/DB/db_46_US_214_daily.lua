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

local lookup = {'Warrior-Fury','Warrior-Protection','Paladin-Protection','DeathKnight-Frost','Priest-Discipline','Priest-Holy','Paladin-Retribution','Unknown-Unknown','DemonHunter-Havoc','Mage-Frost','DeathKnight-Blood','DemonHunter-Devourer','Warlock-Demonology','Warlock-Destruction','Mage-Fire','Druid-Restoration','Warlock-Affliction','DeathKnight-Unholy','Evoker-Augmentation','Warrior-Arms','Priest-Shadow','Evoker-Devastation','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Assassination','Shaman-Restoration','Monk-Brewmaster','Monk-Windwalker','Druid-Guardian','Evoker-Preservation','Paladin-Holy','Druid-Balance',}
local provider = {region='US',realm='TheForgottenCoast',name='US',type='daily',zone=46,date='2026-05-22',data={Aa='Aaricus:BAAALgAECgYJCAAAAA==.',
Ab='Aberdine:BAACLgAFFH8OAAIBAAQJXQuzHQATAQRoDAAABQA0AGkMAAAEACQAawwAAAIADADqDAAAAwAPAAEABAldC7MdABMBBGgMAAAFADQAaQwAAAQAJABrDAAAAgAMAOoMAAADAA8ALgAECn8qAAMBAAkJqRiKJwAgAgABAAkJqRiKJwAgAgACAAIJZw0SSAAsAAAAAA==.',
Ac='Accar:BAABLgAECn8eAAIDAAgJfhBOEgBxAQhoDAAABQBDAGkMAAAFADUAawwAAAUAKQBqDAAABABGAGwMAAADAEUAbQwAAAIAFADqDAAABQAjAG4MAAABAAcAAwAICX4QThIAcQEIaAwAAAUAQwBpDAAABQA1AGsMAAAFACkAagwAAAQARgBsDAAAAwBFAG0MAAACABQA6gwAAAUAIwBuDAAAAQAHAAAA.Achu:BAAALgAFFAIJBAABLgAFFAQJCQAEANsbAA==.Acylies:BAAALgADCgEJAQAAAA==.',
Ae='Aerìth:BAAALgADCgkJEgAAAA==.',
Ag='Agrias:BAABLgAECn8cAAMFAAgJCBjqDgBRAghoDAAABABMAGkMAAAEAFUAawwAAAQAOQBqDAAABABQAGwMAAAEAD8AbQwAAAEAIwDqDAAABgBQAG4MAAABAAwABQAICQgY6g4AUQIIaAwAAAQATABpDAAABABVAGsMAAAEADkAagwAAAQAUABsDAAAAwA/AG0MAAABACMA6gwAAAYAUABuDAAAAQAMAAYAAQmsDqtgAC8AAWwMAAABACUAAAA=.',
Al='Algodón:BAAALgADCgEJAQAAAA==.Aliera:BAAALgADCgcJCwAAAA==.',
Am='Amaltheah:BAAALgAECgEJAQAAAA==.Ambry:BAAALgAECgQJEgABLgAECgkJJAAHAKcPAA==.Ambryosia:BAABLgAECn8kAAIHAAkJpw9XXgCSAQloDAAABgBBAGkMAAAFAEEAawwAAAQAHgBqDAAABAAkAGwMAAAEACYAbQwAAAMAEADqDAAABgAoAG4MAAADACsAbwwAAAEAEwAHAAkJpw9XXgCSAQloDAAABgBBAGkMAAAFAEEAawwAAAQAHgBqDAAABAAkAGwMAAAEACYAbQwAAAMAEADqDAAABgAoAG4MAAADACsAbwwAAAEAEwAAAA==.',
An='Andras:BAAALgAECgIJAgAAAA==.Angerßane:BAAALgADCgMJAwAAAA==.',
Ap='Apocketheory:BAAALgADCgcJBwAAAA==.',
Ar='Aradora:BAAALgADCgQJBQAAAA==.Arcanyounot:BAAALgADCgcJCgABLgAECgYJDgAIAAAAAA==.',
As='Aspir:BAEALgAECgcJEwABLgAFFAUJFQAEAIceAA==.',
Au='Auh:BAAALgAECgMJAwAAAA==.',
Av='Avera:BAAALgAECgIJAgAAAA==.Aviael:BAABLgAECn8eAAIJAAYJYBGEJwAAAQZoDAAABQAtAGkMAAAGAC8AawwAAAYAMQBqDAAABQAmAGwMAAACACkA6gwAAAYAJQAJAAYJYBGEJwAAAQZoDAAABQAtAGkMAAAGAC8AawwAAAYAMQBqDAAABQAmAGwMAAACACkA6gwAAAYAJQAAAA==.',
Aw='Awfulshotz:BAAALgAFFAEJAQABLgAECgYJIAAKAOAUAA==.',
Ba='Badwolf:BAAALgAECgQJBwAAAA==.Bain:BAAALgADCgMJAwAAAA==.Bananabard:BAAALgADCgUJBQAAAA==.Barricade:BAABLgAECn8aAAMCAAkJJBdLFgCrAQloDAAABQBDAGkMAAADADsAawwAAAMAOQBqDAAAAwBaAGwMAAADACcAbQwAAAIAUgDqDAAABABXAG4MAAACADQAbwwAAAEAGwACAAkJJBdLFgCrAQloDAAABABDAGkMAAADADsAawwAAAIAOQBqDAAAAgBaAGwMAAACACcAbQwAAAIAUgDqDAAABABXAG4MAAACADQAbwwAAAEAGwABAAQJKRDaXgClAARoDAAAAQAiAGsMAAABADMAagwAAAEAHQBsDAAAAQAmAAAA.',
Bc='Bcrogue:BAAALgADCgEJAQABLgAECgcJGwALADIfAA==.Bcwarrior:BAAALgAECgYJCQABLgAECgcJGwALADIfAA==.',
Be='Belgrove:BAAALgADCgEJAQAAAA==.',
Bi='Bigbaauls:BAAALgAECgYJCQAAAA==.',
Bj='Björk:BAAALgAECgUJBQABLgAECgYJEwAIAAAAAA==.',
Bl='Blizzaga:BAAALgAECgQJCQAAAA==.',
Bo='Boiardi:BAAALgAECgQJBAAAAA==.Bootowsky:BAAALgAECgQJBAAAAA==.Boromen:BAAALgADCgEJAQAAAA==.Boutros:BAAALgADCgYJBgAAAA==.Bowberto:BAAALgAECgEJAwAAAA==.',
Br='Brea:BAAALgADCgEJAQAAAA==.Briélle:BAAALgADCgMJAwAAAA==.Brocephus:BAAALgAECgYJDQAAAA==.',
Bu='Burrgold:BAAALgAECgcJDgAAAA==.',
Ca='Cadya:BAAALgAECgYJCQABLgAECggJIwAMAIMZAA==.',
Ce='Celticwoman:BAABLgAECn8jAAMNAAcJywnHggAdAQdoDAAABgAZAGkMAAAGACIAawwAAAYAFgBqDAAABQA3AGwMAAAFACwAbQwAAAEACQDqDAAABgAOAA0ABwnLCceCAB0BB2gMAAAEABkAaQwAAAQAIgBrDAAABAAWAGoMAAAEADcAbAwAAAUALABtDAAAAQAJAOoMAAAEAA4ADgAFCckEeTsAxgAFaAwAAAIAEgBpDAAAAgAKAGsMAAACAAkAagwAAAEADQDqDAAAAgAKAAAA.',
Ch='Champina:BAAALgAECgYJCQAAAA==.Chaoticelf:BAAALgADCgcJBwAAAA==.Chickenugget:BAABLgAECn8iAAIPAAgJ1QUbBgAaAQhoDAAABgAOAGkMAAAGAAwAawwAAAYADQBqDAAABAAPAGwMAAAEAA0AbQwAAAIAGgDqDAAABQAPAG4MAAABAAgADwAICdUFGwYAGgEIaAwAAAYADgBpDAAABgAMAGsMAAAGAA0AagwAAAQADwBsDAAABAANAG0MAAACABoA6gwAAAUADwBuDAAAAQAIAAAA.Choral:BAAALgAECgMJBQAAAA==.Chubzilla:BAAALgADCgUJBQAAAA==.Chuckwagaon:BAAALgAECgEJAQAAAA==.',
Ci='Cinderdorla:BAABLgAFFH8FAAIQAAIJGCKMMQDHAAJoDAAAAgBQAOoMAAADAF4AEAACCRgijDEAxwACaAwAAAIAUADqDAAAAwBeAAEuAAUUAwkOAAcAoB8A.',
Cl='Clockie:BAACLgAFFH8SAAMRAAMJBib5CwBqAANoDAAACABhAGkMAAADAGIA6gwAAAcAYAANAAIJ0iUOKwDFAAJoDAAACABhAOoMAAAHAGAAEQABCW8m+QsAagABaQwAAAMAYgAuAAQKfzsABBEACQneJO8EAAsCAA0ABwkJJCceAFQCABEABglTJe8EAAsCAA4ABAkKH7MjADsBAAEuAAUUBAkJAAQA2xsA.Clõüd:BAABLgAECn8bAAIHAAgJhA/9ZACDAQhoDAAABAAmAGkMAAAEACgAawwAAAQAMABqDAAABAAqAGwMAAAEADcAbQwAAAIAEQDqDAAABAAoAG4MAAABACYABwAICYQP/WQAgwEIaAwAAAQAJgBpDAAABAAoAGsMAAAEADAAagwAAAQAKgBsDAAABAA3AG0MAAACABEA6gwAAAQAKABuDAAAAQAmAAEuAAUUBQkRAAoAGQ0A.',
Co='Coldarc:BAAALgADCgYJBgAAAA==.',
Cu='Cuitlahuac:BAAALgAECgEJAwAAAA==.Cupra:BAAALgADCgUJBQAAAA==.',
['Cô']='Cônky:BAAALgAECgYJEAAAAA==.',
Da='Dade:BAAALgAECgYJCAAAAA==.Dadeleviathn:BAAALgADCgEJAQABLgAECgYJCAAIAAAAAA==.Dagrul:BAAALgADCgUJBQAAAA==.Danteangelo:BAAALgAECgEJAQAAAA==.Darrkmann:BAAALgAECggJEwAAAA==.',
De='Deathrotull:BAAALgADCgUJBwAAAA==.Deathslice:BAAALgADCgMJAwAAAA==.Delita:BAAALgAECgUJDQAAAA==.',
Di='Dietdrkelp:BAAALgADCgUJBQABLgAECgEJAQAIAAAAAA==.',
Dk='Dkcloud:BAABLgAECn8dAAISAAcJUx/sOgDxAQdoDAAABgBTAGkMAAAEAFYAawwAAAQAVABqDAAAAwBIAGwMAAAEAFsAbQwAAAMANQDqDAAABQBSABIABwlTH+w6APEBB2gMAAAGAFMAaQwAAAQAVgBrDAAABABUAGoMAAADAEgAbAwAAAQAWwBtDAAAAwA1AOoMAAAFAFIAAS4ABRQFCREACgAZDQA=.',
Do='Donella:BAAALgADCgIJAgAAAA==.Doughboy:BAAALgAECgQJBwAAAA==.',
Dr='Drawinddy:BAAALgAFFAIJAgAAAA==.Drifty:BAAALgAECgYJCwAAAA==.',
Du='Duoduo:BAABLgAFFH8MAAITAAIJMyEKFQDGAAJoDAAABgBcAOoMAAAGAE0AEwACCTMhChUAxgACaAwAAAYAXADqDAAABgBNAAEuAAUUAwkOAAcAoB8A.Duoduomoney:BAABLgAFFH8HAAMBAAIJSBvPLQCrAAJoDAAABABUAOoMAAADADYAAQACCUgbzy0AqwACaAwAAAIAVADqDAAAAQA2ABQAAgnjDkgjAH4AAmgMAAACACUA6gwAAAIAJgABLgAFFAMJDgAHAKAfAA==.',
['Dø']='Dønut:BAAALgADCgUJBQAAAA==.',
Eb='Eboncelest:BAABLgAFFH8KAAIVAAIJuQ64DwCnAAJoDAAABgAqAOoMAAAEACAAFQACCbkOuA8ApwACaAwAAAYAKgDqDAAABAAgAAEuAAUUBAkJAAQA2xsA.',
Ec='Eclesiastes:BAAALgAECgEJAQAAAA==.',
El='Eldarcirdan:BAABLgAECn8YAAIQAAgJvQd6WAALAQhoDAAABAAYAGkMAAADAA8AawwAAAMAFABqDAAAAgAMAGwMAAACAAkAbQwAAAIACADqDAAABQAlAG4MAAADAB0AEAAICb0HelgACwEIaAwAAAQAGABpDAAAAwAPAGsMAAADABQAagwAAAIADABsDAAAAgAJAG0MAAACAAgA6gwAAAUAJQBuDAAAAwAdAAAA.',
Es='Esme:BAAALgADCgkJDwAAAA==.',
Et='Etrigon:BAAALgAECgEJAQAAAA==.',
Ev='Evajoh:BAAALgADCgUJBQAAAA==.',
Ex='Executioner:BAAALgADCgcJDwAAAA==.',
Fa='Fartstink:BAAALgADCgYJBwAAAA==.',
Fe='Festuss:BAAALgAECgQJCwAAAA==.',
Fi='Fingrwaglr:BAABLgAECn8gAAIWAAYJkwpDDwDwAAZoDAAABgAuAGkMAAAGABcAawwAAAYAGABqDAAABQAiAGwMAAADABUA6gwAAAYAEgAWAAYJkwpDDwDwAAZoDAAABgAuAGkMAAAGABcAawwAAAYAGABqDAAABQAiAGwMAAADABUA6gwAAAYAEgAAAA==.Fizzlebliss:BAAALgADCgYJBgAAAA==.',
Fo='Forlin:BAAALgADCggJEQAAAA==.',
Fr='Frostlowe:BAAALgAECggJCgAAAA==.',
Fu='Fuzziestbutt:BAAALgADCgMJAwAAAA==.',
['Fú']='Fúsion:BAEALgAECgMJCAABLgAECgkJMwAMAHoiAA==.',
Ga='Gambokni:BAAALgADCgcJFAAAAA==.Gamebread:BAAALgAECgUJCAAAAA==.',
Gi='Giganate:BAAALgADCgEJAQABLgAECgQJBAAIAAAAAA==.Gixx:BAAALgAECgYJEAABLgAECggJIAAHAM8UAA==.',
Gl='Glorr:BAAALgAECgEJAQAAAA==.',
Go='Gonamanar:BAAALgAECgYJBAAAAA==.Goth:BAAALgADCgEJAQAAAA==.Gourge:BAAALgAECgcJDAAAAA==.',
Gr='Grimfall:BAABLgAECn8sAAQXAAgJ7hyrDwAYAghoDAAACABNAGkMAAAHAFQAawwAAAcAWABqDAAABgBLAGwMAAAFADYAbQwAAAIAMADqDAAABwBcAG4MAAACAEcAFwAICTQbqw8AGAIIaAwAAAQATABpDAAABABFAGsMAAAEAEkAagwAAAQAMgBsDAAABAA2AG0MAAACADAA6gwAAAQAXABuDAAAAgBHABgABQlyHttAAKwBBWgMAAABAE0AaQwAAAIAVABrDAAAAgBYAGoMAAACAEsA6gwAAAEAPQAZAAUJLBNOTwASAQVoDAAAAwA7AGkMAAABADYAawwAAAEALwBsDAAAAQAcAOoMAAACADYAAAA=.Grimtyr:BAAALgAECgEJAQAAAA==.Grëëdo:BAABLgAECn8gAAMHAAgJzxRDWAChAQhoDAAABQA9AGkMAAAHAEcAawwAAAQAOgBqDAAABABRAGwMAAADADsAbQwAAAEAFgDqDAAABgA6AG4MAAACACgABwAICc8UQ1gAoQEIaAwAAAUAPQBpDAAABgBHAGsMAAADADoAagwAAAMAUQBsDAAAAwA7AG0MAAABABYA6gwAAAYAOgBuDAAAAgAoAAMAAwkzBaY+ADwAA2kMAAABABQAawwAAAEABgBqDAAAAQAKAAAA.',
Gy='Gylvi:BAAALgADCgMJAwABLgAECgYJHgAJAGARAA==.',
He='Hellgrazer:BAAALgAECgEJAQAAAA==.',
Hi='Highlowe:BAAALgAECgEJAQAAAA==.Hikiru:BAAALgADCgkJHgAAAA==.',
Ho='Hollowbane:BAABLgAECn8mAAMaAAgJLBeDFADVAQhoDAAABgA6AGkMAAAGAEIAawwAAAUANABqDAAABABSAGwMAAAFADsAbQwAAAQAQQDqDAAABQBMAG4MAAADACQAGgAICSwXgxQA1QEIaAwAAAQAOgBpDAAABABCAGsMAAAEADQAagwAAAQAUgBsDAAABQA7AG0MAAAEAEEA6gwAAAUATABuDAAAAwAkABsAAwmkFiITAMwAA2gMAAACADoAaQwAAAIAPwBrDAAAAQAzAAAA.Holydh:BAAALgAECgEJAQAAAA==.Holydragonn:BAAALgADCgQJBAAAAA==.Holylock:BAAALgAECgQJCAAAAA==.Holylordpig:BAAALgAFFAIJAgAAAA==.Holyshaman:BAABLgAFFH8FAAIcAAIJRQWkUgBrAAJoDAAABAAWAOoMAAABAAQAHAACCUUFpFIAawACaAwAAAQAFgDqDAAAAQAEAAAA.Holywarrior:BAAALgAFFAEJAQAAAA==.Holyymonk:BAAALgAECgEJAQAAAA==.Homdantor:BAAALgAECgUJBQAAAA==.Horse:BAAALgAECgYJBwABLgAFFAgJFAAMAKkZAA==.Hotyogafire:BAAALgAECgMJAwAAAA==.',
Ia='Iampally:BAAALgADCggJCQAAAA==.',
Im='Imhim:BAAALgAECgEJAQAAAA==.Imogen:BAAALgAECgcJEgAAAA==.',
Ja='Jadeddruid:BAAALgAECgkJCQAAAA==.Jamieson:BAACLgAFFH8RAAIKAAUJGQ0BUQAkAQVoDAAABQA2AGkMAAAEACgAawwAAAIADgBqDAAAAQARAOoMAAAFABcACgAFCRkNAVEAJAEFaAwAAAUANgBpDAAABAAoAGsMAAACAA4AagwAAAEAEQDqDAAABQAXAC4ABAp/NwACCgAJCf0f8xgAFQMACgAJCf0f8xgAFQMAAAA=.Jand:BAAALgAECgYJDQAAAA==.Jazashi:BAAALgAECgYJFwAAAQ==.',
Jo='Jonesknight:BAAALgAECgYJDgAAAA==.Jonnytsunami:BAAALgAFFAIJAgAAAA==.',
Ju='Juicycow:BAAALgAECgYJCwAAAA==.',
Ka='Kahoru:BAAALgADCgcJBwAAAA==.Kailler:BAAALgAECgEJAQAAAA==.Kainn:BAAALgAECgYJEAAAAA==.',
Ke='Keg:BAACLgAFFH8eAAIdAAYJoSZhAgA4AgZoDAAABwBkAGkMAAAHAGMAawwAAAUAYQBqDAAABABhAGwMAAABAGEA6gwAAAYAYwAdAAYJoSZhAgA4AgZoDAAABwBkAGkMAAAHAGMAawwAAAUAYQBqDAAABABhAGwMAAABAGEA6gwAAAYAYwAuAAQKfyMAAx0ACAnRJksCAHcDAB0ACAnRJksCAHcDAB4AAQlVIdplAFkAAAAA.',
Kh='Khakuzu:BAAALgADCgIJAgAAAA==.',
Ki='Kikinak:BAAALgAECgYJCwAAAA==.Killshøt:BAAALgADCgEJAQAAAA==.Kitty:BAACLgAFFH8OAAIfAAQJdgcAEAC3AARoDAAABgAjAGkMAAAEABEAawwAAAEACwDqDAAAAwALAB8ABAl2BwAQALcABGgMAAAGACMAaQwAAAQAEQBrDAAAAQALAOoMAAADAAsALgAECn8ZAAIfAAgJrhE5DwCIAQAfAAgJrhE5DwCIAQAAAA==.Kittyhawk:BAAALgAECggJDwAAAA==.',
Kk='Kk:BAAALgAECgYJEwAAAA==.',
Kl='Klassic:BAAALgAECgQJBgAAAA==.Klixx:BAAALgAECgEJAgAAAA==.',
Ko='Konexx:BAAALgADCgMJAwAAAA==.',
Ks='Kstab:BAABLgAECn8bAAIaAAcJLBuIGgAuAgdoDAAAAwBKAGkMAAAFAEoAawwAAAUAUgBqDAAABAAvAGwMAAABACEA6gwAAAUAOwBuDAAABABcABoABwksG4gaAC4CB2gMAAADAEoAaQwAAAUASgBrDAAABQBSAGoMAAAEAC8AbAwAAAEAIQDqDAAABQA7AG4MAAAEAFwAAAA=.',
Ku='Kuromeow:BAABLgAFFH8HAAIKAAIJYRl9NgC9AAJoDAAAAgAoAOoMAAAFAFkACgACCWEZfTYAvQACaAwAAAIAKADqDAAABQBZAAAA.',
La='Lachasis:BAAALgAECgQJBAAAAA==.Larake:BAABLgAECn8WAAIgAAYJKwwwGgAOAQZoDAAABgAzAGkMAAAEACMAawwAAAQAEQBqDAAAAwAYAGwMAAADACIA6gwAAAIAGAAgAAYJKwwwGgAOAQZoDAAABgAzAGkMAAAEACMAawwAAAQAEQBqDAAAAwAYAGwMAAADACIA6gwAAAIAGAAAAA==.Lazypie:BAAALgAECgUJBQAAAA==.',
Le='Leggomyaggro:BAAALgAECgMJBQABLgAFFAQJEAALACwmAA==.Lesiania:BAAALgAECgEJAgABLgAECgYJCAAIAAAAAA==.',
Li='Licus:BAAALgADCgkJFAAAAA==.Lightkeeper:BAABLgAECn8kAAMVAAgJShdwGADcAQhoDAAABgBMAGkMAAAGAEgAawwAAAUANQBqDAAABQAYAGwMAAAEADkAbQwAAAMAMwDqDAAABQBOAG4MAAACABoAFQAICUoXcBgA3AEIaAwAAAUATABpDAAABQBIAGsMAAAEADUAagwAAAUAGABsDAAABAA5AG0MAAADADMA6gwAAAUATgBuDAAAAgAaAAYAAwnvBO9sAHYAA2gMAAABAAMAaQwAAAEADQBrDAAAAQAUAAAA.Lightning:BAAALgADCgEJAQAAAA==.Limpßrisket:BAAALgAECgMJAgAAAA==.Litdealer:BAAALgAECgYJDgABLgAFFAMJCwAdAFcZAA==.Littlestiffy:BAAALgADCgMJAwAAAA==.',
Lr='Lroux:BAAALgAECgcJDwAAAA==.',
Lu='Lucyah:BAAALgAECgYJCgAAAA==.',
Ma='Malkallam:BAAALgADCgUJBQAAAA==.Manaplague:BAAALgAECgUJCwAAAA==.Manenya:BAAALgAECgYJCAAAAA==.Marotto:BAAALgAECgMJAwAAAA==.Massacar:BAABLgAECn8YAAIMAAYJSgo5igAPAQZoDAAABQArAGkMAAAFACoAawwAAAUAEgBqDAAABAAoAGwMAAACAA4A6gwAAAMADQAMAAYJSgo5igAPAQZoDAAABQArAGkMAAAFACoAawwAAAUAEgBqDAAABAAoAGwMAAACAA4A6gwAAAMADQABLgAECggJIAAHAM8UAA==.',
Me='Meatpuller:BAAALgADCgkJDwAAAA==.Menion:BAABLgAECn8cAAMHAAkJZhuLJgCMAgloDAAABABWAGkMAAAEAF0AawwAAAQAWABqDAAABABQAGwMAAADAD8AbQwAAAEAJQDqDAAABABUAG4MAAADAEQAbwwAAAEAJgAHAAkJZhuLJgCMAgloDAAAAwBWAGkMAAADAF0AawwAAAMAWABqDAAAAwBQAGwMAAACAD8AbQwAAAEAJQDqDAAABABUAG4MAAADAEQAbwwAAAEAJgADAAUJQgwDKgCZAAVoDAAAAQAeAGkMAAABAAsAawwAAAEAMwBqDAAAAQAUAGwMAAABACAAAAA=.Meowmeowmeow:BAAALgADCgcJBwABLgAFFAcJGgASAFoXAA==.Mercadius:BAAALgAECgYJEAAAAA==.Metalx:BAAALgADCgkJFQAAAA==.',
Mi='Minkyu:BAAALgAECgQJCAAAAA==.Misha:BAAALgADCgEJAQAAAA==.',
Mk='Mk:BAEALgAECgcJDgABLgAECggJOwAeAGsjAA==.',
Mo='Monkpig:BAACLgAFFH8QAAIdAAMJNh70IwD+AANoDAAABwBLAGkMAAADAEwA6gwAAAYAUAAdAAMJNh70IwD+AANoDAAABwBLAGkMAAADAEwA6gwAAAYAUAAuAAQKfyoAAh0ACQntHwkLAGMCAB0ACQntHwkLAGMCAAAA.Mooinator:BAAALgADCgYJBgAAAA==.',
My='Myrai:BAAALgADCgEJAQAAAA==.',
Na='Nanashi:BAABLgAECn8YAAIJAAYJTRUrIwAgAQZoDAAABgA2AGkMAAAEADEAawwAAAMAOQBqDAAABAAmAGwMAAAEAD0A6gwAAAMAMQAJAAYJTRUrIwAgAQZoDAAABgA2AGkMAAAEADEAawwAAAMAOQBqDAAABAAmAGwMAAAEAD0A6gwAAAMAMQAAAA==.Nannerz:BAAALgAECgYJEQAAAA==.Natenasty:BAAALgADCgUJBQABLgAECgQJBAAIAAAAAA==.Natenomoney:BAAALgAECgQJBAAAAA==.Nathan:BAAALgAECgMJAwABLgAECgQJBAAIAAAAAA==.',
Nd='Ndeh:BAAALgAFFAEJAQAAAA==.',
Ne='Nena:BAAALgAECgEJAQAAAA==.Nermonhunder:BAAALgAECgQJCAAAAA==.',
Ni='Ninjitsû:BAABLgAECn8aAAIMAAgJuBziHQCeAghoDAAABABLAGkMAAAEAEcAawwAAAQAPwBqDAAABABaAGwMAAADAFgAbQwAAAEAMgDqDAAABABTAG4MAAACAFIADAAICbgc4h0AngIIaAwAAAQASwBpDAAABABHAGsMAAAEAD8AagwAAAQAWgBsDAAAAwBYAG0MAAABADIA6gwAAAQAUwBuDAAAAgBSAAAA.',
Ol='Oldspice:BAAALgAECgMJBAAAAA==.Olex:BAAALgAECgUJBQAAAA==.',
Om='Omgkangel:BAABLgAECn8VAAILAAYJnBa6HABlAQZoDAAABAAzAGkMAAAEADcAawwAAAQASABqDAAAAwBAAGwMAAACACoA6gwAAAQAQgALAAYJnBa6HABlAQZoDAAABAAzAGkMAAAEADcAawwAAAQASABqDAAAAwBAAGwMAAACACoA6gwAAAQAQgAAAA==.Omi:BAAALgADCgYJBgAAAA==.Omie:BAAALgAECgEJBAAAAA==.',
On='Onoos:BAAALgAECgMJBgAAAA==.',
Ov='Overpower:BAAALgADCgIJAgABLgAECgkJKwASAMgUAA==.Ovix:BAAALgADCgMJAQABLgAECgUJDAAIAAAAAA==.',
Ow='Ow:BAAALgADCgEJAQAAAA==.',
Pa='Paulos:BAAALgAECgUJBgAAAA==.',
Pe='Peaf:BAABLgAECn8gAAMBAAYJlyDnKACOAQZoDAAABgBiAGkMAAAGAEAAawwAAAYAXwBqDAAABQBSAGwMAAADAFMA6gwAAAYASwABAAYJlyDnKACOAQZoDAAABQBiAGkMAAAFAEAAawwAAAYAXwBqDAAABABSAGwMAAADAFMA6gwAAAUASwACAAQJnAtfNgBwAARoDAAAAQAbAGkMAAABABkAagwAAAEAEwDqDAAAAQAkAAAA.Petesfeets:BAAALgADCgYJCAAAAA==.',
Pl='Playajizoe:BAAALgAECgQJBwAAAA==.',
Po='Pocketsnacks:BAAALgADCgEJAQAAAA==.Poppabanger:BAAALgAECgQJBwAAAA==.',
Qu='Quill:BAABLgAECn8eAAISAAcJrB1CSwARAgdoDAAABgBYAGkMAAAFAEoAawwAAAUAPABqDAAABQBRAGwMAAADAEYAbQwAAAEAYADqDAAABQBCABIABwmsHUJLABECB2gMAAAGAFgAaQwAAAUASgBrDAAABQA8AGoMAAAFAFEAbAwAAAMARgBtDAAAAQBgAOoMAAAFAEIAAS4ABRQDCQQACAAAAAA=.',
Ra='Raythe:BAABLgAECn8hAAIJAAcJ6BVtHABaAQdoDAAABQBFAGkMAAAHAE0AawwAAAUAPQBqDAAABAAXAGwMAAADACwAbQwAAAEAFADqDAAACAA+AAkABwnoFW0cAFoBB2gMAAAFAEUAaQwAAAcATQBrDAAABQA9AGoMAAAEABcAbAwAAAMALABtDAAAAQAUAOoMAAAIAD4AAAA=.Razzeman:BAAALgAECgEJAQAAAA==.Razzledazzl:BAAALgAECgEJAQAAAA==.',
Ro='Rose:BAAALgAECgcJCgABLgAFFAQJDgAfAHYHAA==.',
Ru='Ruck:BAAALgAECgYJBwABLgAECgkJIQACAIEbAA==.Rucker:BAABLgAECn8hAAMCAAkJgRsNCABXAgloDAAABgA+AGkMAAAGAFwAawwAAAUAPwBqDAAAAgA2AGwMAAADAFsAbQwAAAIAPgDqDAAABQBdAG4MAAADACcAbwwAAAEAOgACAAkJgRsNCABXAgloDAAABgA+AGkMAAAGAFwAawwAAAQAPwBqDAAAAgA2AGwMAAADAFsAbQwAAAIAPgDqDAAABQBdAG4MAAADACcAbwwAAAEAOgABAAEJWAIVtQAdAAFrDAAAAQAGAAAA.Ruckkin:BAAALgAECgMJBgABLgAECgkJIQACAIEbAA==.Rucksy:BAABLgAECn8mAAMDAAgJZh0RBQCrAghoDAAABgBcAGkMAAAHAGIAawwAAAgAXwBqDAAABQBXAGwMAAAFAEsAbQwAAAEAKADqDAAABQBbAG4MAAABAB8AAwAICWYdEQUAqwIIaAwAAAYAXABpDAAABwBiAGsMAAAHAF8AagwAAAQAVwBsDAAABQBLAG0MAAABACgA6gwAAAQAWwBuDAAAAQAfAAcAAwn+Ebf9AJkAA2sMAAABAB4AagwAAAEAOgDqDAAAAQA9AAEuAAQKCQkhAAIAgRsA.Ruxsi:BAAALgAECgUJCAABLgAECgkJIQACAIEbAA==.',
Ry='Ryan:BAABLgAECn8dAAMHAAgJHB96JQBLAghoDAAABQBhAGkMAAAEAFIAawwAAAUAXABqDAAABQBhAGwMAAAEAFwAbQwAAAEAGQDqDAAABABaAG4MAAABAEwABwAHCaIieiUASwIHaAwAAAMAYQBpDAAAAwBSAGsMAAAFAFwAagwAAAEAYQBsDAAAAgBcAOoMAAACAFoAbgwAAAEATAAhAAYJWCJGKgDgAQZoDAAAAgBdAGkMAAABAFUAagwAAAQAXQBsDAAAAgBZAG0MAAABAE0A6gwAAAIAVwAAAA==.',
['Rì']='Rìptide:BAAALgAECgkJEQAAAA==.',
['Rô']='Rôrônoazoro:BAAALgADCgYJCwAAAA==.',
Sa='Saragdan:BAAALgADCgcJCwAAAA==.',
Sc='Scylla:BAAALgAECgYJBgABLgAECgYJDwAIAAAAAA==.',
Se='Seraphae:BAAALgAECgEJAQAAAA==.Sereb:BAAALgAECgQJBAAAAA==.',
Sh='Shadowscurry:BAAALgAECgQJBwAAAA==.Shankzmcgee:BAABLgAECn8cAAIaAAYJcQrDLgDzAAZoDAAABwApAGkMAAAHAB4AawwAAAYAGgBqDAAABAATAGwMAAACABUA6gwAAAIADQAaAAYJcQrDLgDzAAZoDAAABwApAGkMAAAHAB4AawwAAAYAGgBqDAAABAATAGwMAAACABUA6gwAAAIADQABLgAECggJIAAHAM8UAA==.Shardik:BAAALgAECgUJBgAAAA==.Sheero:BAAALgAECgUJBQAAAA==.Sheong:BAAALgAECgkJCwAAAA==.Sheñ:BAAALgADCgkJHAAAAA==.Shindark:BAAALgAECgEJAgAAAA==.Shivah:BAAALgAECgcJCwABLgAFFAMJBAAIAAAAAA==.Shrus:BAAALgAECgYJBgAAAA==.Shrussy:BAAALgADCgMJAwAAAA==.Shèrlock:BAABLgAECn8VAAINAAgJig9zUQCOAQhoDAAAAwAdAGkMAAADAC4AawwAAAMAJQBqDAAAAwBDAGwMAAADADAAbQwAAAIAFQDqDAAAAwAwAG4MAAABAC4ADQAICYoPc1EAjgEIaAwAAAMAHQBpDAAAAwAuAGsMAAADACUAagwAAAMAQwBsDAAAAwAwAG0MAAACABUA6gwAAAMAMABuDAAAAQAuAAAA.',
Si='Silverfox:BAAALgAFFAIJBAABLgAFFAMJDgAHAKAfAA==.',
Sk='Skippydippy:BAAALgAECgQJCwAAAA==.Skye:BAAALgAECgcJBQAAAA==.Skylin:BAAALgAECgEJAwAAAA==.',
Sl='Sleezee:BAAALgAECgMJBwAAAA==.Slushpuppis:BAAALgADCgcJBwAAAA==.',
Sn='Sneeger:BAAALgAECgUJBgAAAA==.',
Sp='Spelldeala:BAAALgAECgYJEAABLgAFFAMJCwAdAFcZAA==.',
St='Stargasm:BAAALgAFFAIJAgAAAA==.Stdmachine:BAAALgAECgYJDAAAAA==.Stonedstoner:BAAALgAECgUJBQAAAA==.',
Su='Superdump:BAAALgAECgcJAgAAAA==.',
Sw='Swiftmend:BAABLgAFFH8JAAIQAAIJtw5jRACAAAJoDAAABAAnAOoMAAAFACMAEAACCbcOY0QAgAACaAwAAAQAJwDqDAAABQAjAAEuAAUUAwkLAB0AVxkA.',
Sy='Syllal:BAAALgADCgQJBAAAAA==.Synisttir:BAAALgAECgQJBAAAAA==.',
Ta='Taft:BAABLgAECn8wAAMiAAkJjBPoFgDpAQloDAAABQA9AGkMAAAIAD8AawwAAAcAOwBqDAAABwA5AGwMAAAGACUAbQwAAAQALQDqDAAABQA4AG4MAAAEADEAbwwAAAIAGwAiAAkJjBPoFgDpAQloDAAABQA9AGkMAAAIAD8AawwAAAcAOwBqDAAABwA5AGwMAAAGACUAbQwAAAQALQDqDAAABAA4AG4MAAAEADEAbwwAAAIAGwAQAAEJDQyTxQAoAAHqDAAAAQAeAAAA.Tardis:BAAALgADCgcJCgAAAA==.Taterz:BAAALgADCgQJBAAAAA==.',
Te='Terrá:BAAALgADCgkJGgAAAA==.Teryn:BAAALgAECgEJAQAAAA==.Tesa:BAAALgADCgMJBQAAAA==.',
Th='Thomassian:BAAALgAECgEJAgAAAA==.',
Ti='Timewing:BAAALgADCggJFAAAAA==.Timtoo:BAAALgAECgMJBQAAAA==.',
To='Toborntwob:BAAALgAECgYJDQAAAA==.',
Tr='Transformer:BAAALgAECgQJBgAAAA==.Triblequest:BAAALgAECgYJEQAAAA==.Tritin:BAAALgAECgYJEgAAAA==.',
Tu='Tugginmypuda:BAAALgAECgQJBAAAAA==.',
Tw='Twiltock:BAAALgAECgYJDAAAAA==.Twizztyd:BAAALgAECgEJAQAAAA==.Twocups:BAAALgAECgUJCgAAAA==.',
Un='Underware:BAAALgADCgYJBgAAAA==.',
Va='Valessa:BAABLgAECn8lAAIKAAgJNwUrnwAhAQhoDAAABgAPAGkMAAAGABQAawwAAAYABABqDAAABQAUAGwMAAAFABIAbQwAAAIACADqDAAABgAQAG4MAAABAAcACgAICTcFK58AIQEIaAwAAAYADwBpDAAABgAUAGsMAAAGAAQAagwAAAUAFABsDAAABQASAG0MAAACAAgA6gwAAAYAEABuDAAAAQAHAAAA.Valiria:BAABLgAECn8eAAIMAAkJXRl2IQAtAgloDAAAAwBQAGkMAAAFAF0AawwAAAQASgBqDAAABABgAGwMAAADAFIAbQwAAAEAJQDqDAAABwBfAG4MAAACABMAbwwAAAEAIwAMAAkJXRl2IQAtAgloDAAAAwBQAGkMAAAFAF0AawwAAAQASgBqDAAABABgAGwMAAADAFIAbQwAAAEAJQDqDAAABwBfAG4MAAACABMAbwwAAAEAIwAAAA==.Varzul:BAAALgADCgYJCwABLgAECgIJAgAIAAAAAA==.',
Ve='Velieda:BAABLgAECn8fAAMHAAgJJxFibwBsAQhoDAAABQAoAGkMAAAEAC0AawwAAAQAKABqDAAAAgA6AGwMAAAEAD8AbQwAAAIAFgDqDAAABQAkAG4MAAAFADkABwAICQcOYm8AbAEIaAwAAAIAJwBpDAAAAgAkAGsMAAACACgAagwAAAEAEgBsDAAAAgAiAG0MAAACABYA6gwAAAIAFABuDAAABQA5AAMABgnGEbMcAP4ABmgMAAADACgAaQwAAAIALQBrDAAAAgAoAGoMAAABADoAbAwAAAIAPwDqDAAAAwAkAAAA.',
Vi='Vindication:BAACLgAFFH8QAAILAAQJLCYaBgC+AQRoDAAABgBiAGkMAAAEAGAAawwAAAEAYgDqDAAABQBhAAsABAksJhoGAL4BBGgMAAAGAGIAaQwAAAQAYABrDAAAAQBiAOoMAAAFAGEALgAECn8jAAILAAgJKCAuBwC9AgALAAgJKCAuBwC9AgAAAA==.Vita:BAAALgAECgYJBwAAAA==.',
Wa='Wackah:BAAALgAECgYJCQAAAA==.Wakana:BAAALgAECgIJAgAAAA==.',
Wi='Windflower:BAAALgADCgQJBAAAAA==.Winteranne:BAAALgAECgEJAQAAAA==.',
Wo='Wolfcarver:BAAALgAECgYJEAAAAA==.Worldbreakèr:BAAALgAECggJAQAAAA==.',
Xi='Xiaobao:BAAALgAFFAMJAwAAAA==.Xiaoduoduo:BAACLgAFFH8OAAMHAAMJoB+bOgARAQNoDAAABgBfAGkMAAACAEAA6gwAAAYAUgAHAAMJoB+bOgARAQNoDAAABQBfAGkMAAACAEAA6gwAAAYAUgAhAAEJuCOjNQBfAAFoDAAAAQBbAC4ABAp/KgACBwAJCaIj8QsA6wIABwAJCaIj8QsA6wIAAAA=.Xiaomak:BAAALgADCgQJBAAAAA==.Xiaoxiongmao:BAAALgADCgcJBwAAAA==.',
Xs='Xschaferr:BAAALgAECgYJDwAAAA==.',
Za='Zabz:BAAALgAECgEJAQABLgAECgkJLQAHAIQfAA==.',
Ze='Zeroskills:BAABLgAECn8kAAMaAAkJ/QegHACEAQloDAAABQAdAGkMAAAFACEAawwAAAUAFwBqDAAABAAlAGwMAAADABgAbQwAAAIAAwDqDAAABgAUAG4MAAAEABMAbwwAAAIACQAaAAkJ/QegHACEAQloDAAABAAdAGkMAAAEACEAawwAAAUAFwBqDAAABAAlAGwMAAADABgAbQwAAAIAAwDqDAAABgAUAG4MAAAEABMAbwwAAAIACQAbAAIJSwR8HABUAAJoDAAAAQAHAGkMAAABAA4AAAA=.',
Zu='Zulinar:BAAALgAECgYJDQAAAA==.Zumoku:BAAALgADCgkJKQAAAA==.',
['Às']='Àsmodeus:BAABLgAECn8oAAQfAAkJchFCEACjAQloDAAABgBMAGkMAAAHAC0AawwAAAgAJgBqDAAABwAyAGwMAAADADMAbQwAAAEAHADqDAAABgA8AG4MAAABACMAbwwAAAEAEwAfAAkJchFCEACjAQloDAAABgBMAGkMAAAHAC0AawwAAAcAJgBqDAAABwAyAGwMAAADADMAbQwAAAEAHADqDAAABQA8AG4MAAABACMAbwwAAAEAEwAiAAEJ8gbJfgAnAAFrDAAAAQARABAAAQkxCqHIACYAAeoMAAABABoAAAA=.',
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
