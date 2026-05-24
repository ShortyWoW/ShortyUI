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
local provider = {region='US',realm='TheForgottenCoast',name='US',type='daily',zone=46,date='2026-05-23',data={Aa='Aaricus:BAAALgAECgYJCAAAAA==.',
Ab='Aberdine:BAACLgAFFH8OAAIBAAQJXQtmHgARAQRoDAAABQA0AGkMAAAEACQAawwAAAIADADqDAAAAwAPAAEABAldC2YeABEBBGgMAAAFADQAaQwAAAQAJABrDAAAAgAMAOoMAAADAA8ALgAECn8qAAMBAAkJqRiKJwAgAgABAAkJqRiKJwAgAgACAAIJZw3gSAAsAAAAAA==.',
Ac='Accar:BAABLgAECn8eAAIDAAgJfhCREgBxAQhoDAAABQBDAGkMAAAFADUAawwAAAUAKQBqDAAABABGAGwMAAADAEUAbQwAAAIAFADqDAAABQAjAG4MAAABAAcAAwAICX4QkRIAcQEIaAwAAAUAQwBpDAAABQA1AGsMAAAFACkAagwAAAQARgBsDAAAAwBFAG0MAAACABQA6gwAAAUAIwBuDAAAAQAHAAAA.Achu:BAAALgAFFAIJBAABLgAFFAQJCgAEANsbAA==.Acylies:BAAALgADCgEJAQAAAA==.',
Ae='Aerìth:BAAALgADCgkJEgAAAA==.',
Ag='Agrias:BAABLgAECn8cAAMFAAgJCBg9DwBPAghoDAAABABMAGkMAAAEAFUAawwAAAQAOQBqDAAABABQAGwMAAAEAD8AbQwAAAEAIwDqDAAABgBQAG4MAAABAAwABQAICQgYPQ8ATwIIaAwAAAQATABpDAAABABVAGsMAAAEADkAagwAAAQAUABsDAAAAwA/AG0MAAABACMA6gwAAAYAUABuDAAAAQAMAAYAAQmsDqFhAC8AAWwMAAABACUAAAA=.',
Al='Algodón:BAAALgADCgEJAQAAAA==.Aliera:BAAALgADCgcJCwAAAA==.',
Am='Amaltheah:BAAALgAECgEJAQAAAA==.Ambry:BAAALgAECgQJEgABLgAECgkJJAAHAKcPAA==.Ambryosia:BAABLgAECn8kAAIHAAkJpw/hYACPAQloDAAABgBBAGkMAAAFAEEAawwAAAQAHgBqDAAABAAkAGwMAAAEACYAbQwAAAMAEADqDAAABgAoAG4MAAADACsAbwwAAAEAEwAHAAkJpw/hYACPAQloDAAABgBBAGkMAAAFAEEAawwAAAQAHgBqDAAABAAkAGwMAAAEACYAbQwAAAMAEADqDAAABgAoAG4MAAADACsAbwwAAAEAEwAAAA==.',
An='Andras:BAAALgAECgIJAgAAAA==.Angerßane:BAAALgADCgMJAwAAAA==.',
Ap='Apocketheory:BAAALgADCgcJBwAAAA==.',
Ar='Aradora:BAAALgADCgQJBQAAAA==.Arcanyounot:BAAALgADCgkJEgABLgAECgYJDgAIAAAAAA==.',
As='Aspir:BAEALgAECgcJEwABLgAFFAUJFQAEAIceAA==.',
Au='Auh:BAAALgAECgMJAwAAAA==.',
Av='Avera:BAAALgAECgIJAgAAAA==.Aviael:BAABLgAECn8eAAIJAAYJYBFRKAD+AAZoDAAABQAtAGkMAAAGAC8AawwAAAYAMQBqDAAABQAmAGwMAAACACkA6gwAAAYAJQAJAAYJYBFRKAD+AAZoDAAABQAtAGkMAAAGAC8AawwAAAYAMQBqDAAABQAmAGwMAAACACkA6gwAAAYAJQAAAA==.',
Aw='Awfulshotz:BAAALgAFFAEJAQABLgAECgYJIAAKAOAUAA==.',
Ba='Badwolf:BAAALgAECgQJBwAAAA==.Bain:BAAALgADCgMJAwAAAA==.Bananabard:BAAALgADCgUJBQAAAA==.Barricade:BAABLgAECn8aAAMCAAkJJBdLFgCrAQloDAAABQBDAGkMAAADADsAawwAAAMAOQBqDAAAAwBaAGwMAAADACcAbQwAAAIAUgDqDAAABABXAG4MAAACADQAbwwAAAEAGwACAAkJJBdLFgCrAQloDAAABABDAGkMAAADADsAawwAAAIAOQBqDAAAAgBaAGwMAAACACcAbQwAAAIAUgDqDAAABABXAG4MAAACADQAbwwAAAEAGwABAAQJKRAgYAClAARoDAAAAQAiAGsMAAABADMAagwAAAEAHQBsDAAAAQAmAAAA.',
Bc='Bcrogue:BAAALgADCgEJAQABLgAECgcJGwALADIfAA==.Bcwarrior:BAAALgAECgYJCQABLgAECgcJGwALADIfAA==.',
Be='Belgrove:BAAALgADCgEJAQAAAA==.',
Bh='Bheap:BAAALgADCgMJAwAAAA==.',
Bi='Bigbaauls:BAAALgAECgYJCQAAAA==.',
Bj='Björk:BAAALgAECgUJBQABLgAECgYJEwAIAAAAAA==.',
Bl='Blizzaga:BAAALgAECgQJCQAAAA==.',
Bo='Boiardi:BAAALgAECgQJBAAAAA==.Bootowsky:BAAALgAECgQJBAAAAA==.Boromen:BAAALgADCgEJAQAAAA==.Boutros:BAAALgADCgYJBgAAAA==.Bowberto:BAAALgAECgEJAwAAAA==.',
Br='Brea:BAAALgADCgEJAQAAAA==.Briélle:BAAALgADCgMJAwAAAA==.Brocephus:BAAALgAECgYJDwAAAA==.',
Bu='Burrgold:BAAALgAECgcJDgAAAA==.',
Ca='Cadya:BAAALgAECgYJCQABLgAECggJIwAMAIMZAA==.',
Ce='Celticwoman:BAABLgAECn8jAAMNAAcJywllhAAcAQdoDAAABgAZAGkMAAAGACIAawwAAAYAFgBqDAAABQA3AGwMAAAFACwAbQwAAAEACQDqDAAABgAOAA0ABwnLCWWEABwBB2gMAAAEABkAaQwAAAQAIgBrDAAABAAWAGoMAAAEADcAbAwAAAUALABtDAAAAQAJAOoMAAAEAA4ADgAFCckEeTsAxgAFaAwAAAIAEgBpDAAAAgAKAGsMAAACAAkAagwAAAEADQDqDAAAAgAKAAAA.',
Ch='Champina:BAAALgAECgYJCQAAAA==.Chaoticelf:BAAALgADCgcJBwAAAA==.Chickenugget:BAABLgAECn8iAAIPAAgJ1QUzBgAZAQhoDAAABgAOAGkMAAAGAAwAawwAAAYADQBqDAAABAAPAGwMAAAEAA0AbQwAAAIAGgDqDAAABQAPAG4MAAABAAgADwAICdUFMwYAGQEIaAwAAAYADgBpDAAABgAMAGsMAAAGAA0AagwAAAQADwBsDAAABAANAG0MAAACABoA6gwAAAUADwBuDAAAAQAIAAAA.Choral:BAAALgAECgMJBQAAAA==.Chubzilla:BAAALgADCgUJBQAAAA==.Chuckwagaon:BAAALgAECgEJAQAAAA==.',
Ci='Cinderdorla:BAABLgAFFH8FAAIQAAIJGCJqMgDHAAJoDAAAAgBQAOoMAAADAF4AEAACCRgiajIAxwACaAwAAAIAUADqDAAAAwBeAAEuAAUUAwkOAAcAoB8A.',
Cl='Clockie:BAACLgAFFH8SAAMRAAMJBiZxDABpAANoDAAACABhAGkMAAADAGIA6gwAAAcAYAANAAIJ0iUOKwDFAAJoDAAACABhAOoMAAAHAGAAEQABCW8mcQwAaQABaQwAAAMAYgAuAAQKfzsABBEACQneJBEFAAoCAA0ABwkJJK4eAFMCABEABglTJREFAAoCAA4ABAkKH7MjADsBAAEuAAUUBAkKAAQA2xsA.Clõüd:BAABLgAECn8bAAIHAAgJhA+YZgCCAQhoDAAABAAmAGkMAAAEACgAawwAAAQAMABqDAAABAAqAGwMAAAEADcAbQwAAAIAEQDqDAAABAAoAG4MAAABACYABwAICYQPmGYAggEIaAwAAAQAJgBpDAAABAAoAGsMAAAEADAAagwAAAQAKgBsDAAABAA3AG0MAAACABEA6gwAAAQAKABuDAAAAQAmAAEuAAUUBQkRAAoAGQ0A.',
Co='Coldarc:BAAALgADCgYJBgAAAA==.',
Cu='Cuitlahuac:BAAALgAECgEJAwAAAA==.Cupra:BAAALgADCgUJBQAAAA==.',
['Cô']='Cônky:BAAALgAECgYJEAAAAA==.',
Da='Dade:BAAALgAECgYJCAAAAA==.Dadeleviathn:BAAALgADCgEJAQABLgAECgYJCAAIAAAAAA==.Dagrul:BAAALgADCgUJBQAAAA==.Danteangelo:BAAALgAECgEJAQAAAA==.Darrkmann:BAAALgAECggJEwAAAA==.',
De='Deathrotull:BAAALgADCgUJBwAAAA==.Deathslice:BAAALgADCgMJAwAAAA==.Delita:BAAALgAECgUJDQAAAA==.',
Di='Dietdrkelp:BAAALgADCgUJBQABLgAECgEJAQAIAAAAAA==.',
Dk='Dkcloud:BAABLgAECn8dAAISAAcJUx+3OwDvAQdoDAAABgBTAGkMAAAEAFYAawwAAAQAVABqDAAAAwBIAGwMAAAEAFsAbQwAAAMANQDqDAAABQBSABIABwlTH7c7AO8BB2gMAAAGAFMAaQwAAAQAVgBrDAAABABUAGoMAAADAEgAbAwAAAQAWwBtDAAAAwA1AOoMAAAFAFIAAS4ABRQFCREACgAZDQA=.',
Do='Donella:BAAALgADCgIJAgAAAA==.Doughboy:BAAALgAECgQJBwAAAA==.',
Dr='Drawinddy:BAAALgAFFAIJAgAAAA==.Drifty:BAAALgAECgYJCwAAAA==.',
Du='Duoduo:BAABLgAFFH8MAAITAAIJMyEKFQDGAAJoDAAABgBcAOoMAAAGAE0AEwACCTMhChUAxgACaAwAAAYAXADqDAAABgBNAAEuAAUUAwkOAAcAoB8A.Duoduomoney:BAABLgAFFH8HAAMBAAIJSBuxLgCqAAJoDAAABABUAOoMAAADADYAAQACCUgbsS4AqgACaAwAAAIAVADqDAAAAQA2ABQAAgnjDlEkAH4AAmgMAAACACUA6gwAAAIAJgABLgAFFAMJDgAHAKAfAA==.',
['Dø']='Dønut:BAAALgADCgUJBQAAAA==.',
Eb='Eboncelest:BAABLgAFFH8KAAIVAAIJuQ64DwCnAAJoDAAABgAqAOoMAAAEACAAFQACCbkOuA8ApwACaAwAAAYAKgDqDAAABAAgAAEuAAUUBAkKAAQA2xsA.',
Ec='Eclesiastes:BAAALgAECgEJAQAAAA==.',
El='Eldarcirdan:BAABLgAECn8YAAIQAAgJvQdJWQALAQhoDAAABAAYAGkMAAADAA8AawwAAAMAFABqDAAAAgAMAGwMAAACAAkAbQwAAAIACADqDAAABQAlAG4MAAADAB0AEAAICb0HSVkACwEIaAwAAAQAGABpDAAAAwAPAGsMAAADABQAagwAAAIADABsDAAAAgAJAG0MAAACAAgA6gwAAAUAJQBuDAAAAwAdAAAA.',
Es='Esme:BAAALgADCgkJDwAAAA==.',
Et='Etrigon:BAAALgAECgEJAQAAAA==.',
Ev='Evajoh:BAAALgADCgUJBQAAAA==.',
Ex='Executioner:BAAALgADCgcJDwAAAA==.',
Fa='Fartstink:BAAALgADCgYJBwAAAA==.',
Fe='Festuss:BAAALgAECgQJCwAAAA==.',
Fi='Fingrwaglr:BAABLgAECn8gAAIWAAYJkwp4DwDwAAZoDAAABgAuAGkMAAAGABcAawwAAAYAGABqDAAABQAiAGwMAAADABUA6gwAAAYAEgAWAAYJkwp4DwDwAAZoDAAABgAuAGkMAAAGABcAawwAAAYAGABqDAAABQAiAGwMAAADABUA6gwAAAYAEgAAAA==.Fizzlebliss:BAAALgADCgYJBgAAAA==.',
Fo='Forlin:BAAALgADCggJEQAAAA==.',
Fr='Frostlowe:BAAALgAECggJCgAAAA==.',
Fu='Fuzziestbutt:BAAALgADCgMJAwAAAA==.',
['Fú']='Fúsion:BAEALgAECgMJCAABLgAECgkJMwAMAHoiAA==.',
Ga='Gambokni:BAAALgADCgcJFAAAAA==.Gamebread:BAAALgAECgUJCAAAAA==.',
Gi='Giganate:BAAALgADCgEJAQABLgAECgQJBAAIAAAAAA==.Gixx:BAAALgAECgYJEAABLgAECggJIAAHAM8UAA==.',
Gl='Glorr:BAAALgAECgEJAQAAAA==.',
Go='Gonamanar:BAAALgAECgYJBAAAAA==.Goth:BAAALgADCgEJAQAAAA==.Gourge:BAAALgAECgcJDAAAAA==.',
Gr='Grimfall:BAABLgAECn8sAAQXAAgJ7hz3DwAXAghoDAAACABNAGkMAAAHAFQAawwAAAcAWABqDAAABgBLAGwMAAAFADYAbQwAAAIAMADqDAAABwBcAG4MAAACAEcAFwAICTQb9w8AFwIIaAwAAAQATABpDAAABABFAGsMAAAEAEkAagwAAAQAMgBsDAAABAA2AG0MAAACADAA6gwAAAQAXABuDAAAAgBHABgABQlyHttAAKwBBWgMAAABAE0AaQwAAAIAVABrDAAAAgBYAGoMAAACAEsA6gwAAAEAPQAZAAUJLBNOTwASAQVoDAAAAwA7AGkMAAABADYAawwAAAEALwBsDAAAAQAcAOoMAAACADYAAAA=.Grimtyr:BAAALgAECgEJAQAAAA==.Grëëdo:BAABLgAECn8gAAMHAAgJzxSbWQCgAQhoDAAABQA9AGkMAAAHAEcAawwAAAQAOgBqDAAABABRAGwMAAADADsAbQwAAAEAFgDqDAAABgA6AG4MAAACACgABwAICc8Um1kAoAEIaAwAAAUAPQBpDAAABgBHAGsMAAADADoAagwAAAMAUQBsDAAAAwA7AG0MAAABABYA6gwAAAYAOgBuDAAAAgAoAAMAAwkzBXs/ADwAA2kMAAABABQAawwAAAEABgBqDAAAAQAKAAAA.',
Gy='Gylvi:BAAALgADCgMJAwABLgAECgYJHgAJAGARAA==.',
He='Hellgrazer:BAAALgAECgEJAQAAAA==.',
Hi='Highlowe:BAAALgAECgEJAQAAAA==.Hikiru:BAAALgADCgkJJAAAAA==.',
Ho='Hollowbane:BAABLgAECn8mAAMaAAgJLBfwFADTAQhoDAAABgA6AGkMAAAGAEIAawwAAAUANABqDAAABABSAGwMAAAFADsAbQwAAAQAQQDqDAAABQBMAG4MAAADACQAGgAICSwX8BQA0wEIaAwAAAQAOgBpDAAABABCAGsMAAAEADQAagwAAAQAUgBsDAAABQA7AG0MAAAEAEEA6gwAAAUATABuDAAAAwAkABsAAwmkFlgTAMwAA2gMAAACADoAaQwAAAIAPwBrDAAAAQAzAAAA.Holydh:BAAALgAECgIJAgAAAA==.Holydragonn:BAAALgADCgQJBAAAAA==.Holylock:BAAALgAECgQJCAAAAA==.Holylordpig:BAAALgAFFAIJAgAAAA==.Holyshaman:BAABLgAFFH8FAAIcAAIJRQVHVABrAAJoDAAABAAWAOoMAAABAAQAHAACCUUFR1QAawACaAwAAAQAFgDqDAAAAQAEAAAA.Holywarrior:BAAALgAFFAEJAQAAAA==.Holyymonk:BAAALgAECgEJAgAAAA==.Homdantor:BAAALgAECgUJBQAAAA==.Horse:BAAALgAECgYJBwABLgAFFAgJFwAMACEbAA==.Hotyogafire:BAAALgAECgMJAwAAAA==.',
Ia='Iampally:BAAALgADCggJCQAAAA==.',
Im='Imhim:BAAALgAECgEJAQAAAA==.Imogen:BAAALgAECgcJEgAAAA==.',
Ja='Jadeddruid:BAAALgAECgkJCQAAAA==.Jamieson:BAACLgAFFH8RAAIKAAUJGQ22UgAiAQVoDAAABQA2AGkMAAAEACgAawwAAAIADgBqDAAAAQARAOoMAAAFABcACgAFCRkNtlIAIgEFaAwAAAUANgBpDAAABAAoAGsMAAACAA4AagwAAAEAEQDqDAAABQAXAC4ABAp/NwACCgAJCf0f8xgAFQMACgAJCf0f8xgAFQMAAAA=.Jand:BAAALgAECgYJDQAAAA==.Jazashi:BAAALgAECgYJFwAAAQ==.',
Jo='Jonesknight:BAAALgAECgYJDgAAAA==.Jonnytsunami:BAAALgAFFAIJAgAAAA==.',
Ju='Juicycow:BAAALgAECgYJCwAAAA==.',
Ka='Kahoru:BAAALgADCgcJBwAAAA==.Kailler:BAAALgAECgEJAQAAAA==.Kainn:BAAALgAECgYJEAAAAA==.',
Ke='Keg:BAACLgAFFH8eAAIdAAYJoSaDAgA3AgZoDAAABwBkAGkMAAAHAGMAawwAAAUAYQBqDAAABABhAGwMAAABAGEA6gwAAAYAYwAdAAYJoSaDAgA3AgZoDAAABwBkAGkMAAAHAGMAawwAAAUAYQBqDAAABABhAGwMAAABAGEA6gwAAAYAYwAuAAQKfyMAAx0ACAnRJksCAHcDAB0ACAnRJksCAHcDAB4AAQlVIWFnAFkAAAAA.',
Kh='Khakuzu:BAAALgADCgIJAgAAAA==.',
Ki='Kikinak:BAAALgAECgYJCwAAAA==.Killshøt:BAAALgADCgEJAQAAAA==.Kitty:BAACLgAFFH8OAAIfAAQJdgfCEAC3AARoDAAABgAjAGkMAAAEABEAawwAAAEACwDqDAAAAwALAB8ABAl2B8IQALcABGgMAAAGACMAaQwAAAQAEQBrDAAAAQALAOoMAAADAAsALgAECn8ZAAIfAAgJrhE5DwCIAQAfAAgJrhE5DwCIAQAAAA==.Kittyhawk:BAAALgAECggJDwAAAA==.',
Kk='Kk:BAAALgAECgYJEwAAAA==.',
Kl='Klassic:BAAALgAECgQJBgAAAA==.Klixx:BAAALgAECgEJAgAAAA==.',
Ko='Konexx:BAAALgADCgMJAwAAAA==.',
Ks='Kstab:BAABLgAECn8bAAIaAAcJLBuIGgAuAgdoDAAAAwBKAGkMAAAFAEoAawwAAAUAUgBqDAAABAAvAGwMAAABACEA6gwAAAUAOwBuDAAABABcABoABwksG4gaAC4CB2gMAAADAEoAaQwAAAUASgBrDAAABQBSAGoMAAAEAC8AbAwAAAEAIQDqDAAABQA7AG4MAAAEAFwAAAA=.',
Ku='Kuromeow:BAABLgAFFH8HAAIKAAIJYRl9NgC9AAJoDAAAAgAoAOoMAAAFAFkACgACCWEZfTYAvQACaAwAAAIAKADqDAAABQBZAAAA.',
La='Lachasis:BAAALgAECgQJBAAAAA==.Larake:BAABLgAECn8WAAIgAAYJKwx5GgANAQZoDAAABgAzAGkMAAAEACMAawwAAAQAEQBqDAAAAwAYAGwMAAADACIA6gwAAAIAGAAgAAYJKwx5GgANAQZoDAAABgAzAGkMAAAEACMAawwAAAQAEQBqDAAAAwAYAGwMAAADACIA6gwAAAIAGAAAAA==.Lazypie:BAAALgAECgUJBQAAAA==.',
Le='Leggomyaggro:BAAALgAECgMJBQABLgAFFAQJEAALACwmAA==.Lesiania:BAAALgAECgEJAgABLgAECgYJCAAIAAAAAA==.',
Li='Licus:BAAALgADCgkJFAAAAA==.Lightkeeper:BAABLgAECn8kAAMVAAgJShfaGADaAQhoDAAABgBMAGkMAAAGAEgAawwAAAUANQBqDAAABQAYAGwMAAAEADkAbQwAAAMAMwDqDAAABQBOAG4MAAACABoAFQAICUoX2hgA2gEIaAwAAAUATABpDAAABQBIAGsMAAAEADUAagwAAAUAGABsDAAABAA5AG0MAAADADMA6gwAAAUATgBuDAAAAgAaAAYAAwnvBO9sAHYAA2gMAAABAAMAaQwAAAEADQBrDAAAAQAUAAAA.Lightning:BAAALgADCgEJAQAAAA==.Limpßrisket:BAAALgAECgMJAgAAAA==.Litdealer:BAAALgAECgYJDgABLgAFFAMJCwAdAFcZAA==.Littlestiffy:BAAALgADCgMJAwAAAA==.',
Lr='Lroux:BAAALgAECgcJDwAAAA==.',
Lu='Lucyah:BAAALgAECgYJCgAAAA==.',
Ma='Malkallam:BAAALgADCgUJBQAAAA==.Manaplague:BAAALgAECgUJCwAAAA==.Manenya:BAAALgAECgYJCAAAAA==.Marotto:BAAALgAECgMJAwAAAA==.Massacar:BAABLgAECn8YAAIMAAYJSgo5igAPAQZoDAAABQArAGkMAAAFACoAawwAAAUAEgBqDAAABAAoAGwMAAACAA4A6gwAAAMADQAMAAYJSgo5igAPAQZoDAAABQArAGkMAAAFACoAawwAAAUAEgBqDAAABAAoAGwMAAACAA4A6gwAAAMADQABLgAECggJIAAHAM8UAA==.',
Me='Meatpuller:BAAALgADCgkJDwAAAA==.Menion:BAABLgAECn8cAAMHAAkJZhuLJgCMAgloDAAABABWAGkMAAAEAF0AawwAAAQAWABqDAAABABQAGwMAAADAD8AbQwAAAEAJQDqDAAABABUAG4MAAADAEQAbwwAAAEAJgAHAAkJZhuLJgCMAgloDAAAAwBWAGkMAAADAF0AawwAAAMAWABqDAAAAwBQAGwMAAACAD8AbQwAAAEAJQDqDAAABABUAG4MAAADAEQAbwwAAAEAJgADAAUJQgyZKgCZAAVoDAAAAQAeAGkMAAABAAsAawwAAAEAMwBqDAAAAQAUAGwMAAABACAAAAA=.Meowmeowmeow:BAAALgADCgcJBwABLgAFFAcJGgASAFoXAA==.Mercadius:BAAALgAECgYJEAAAAA==.Metalx:BAAALgADCgkJFQAAAA==.',
Mi='Minkyu:BAAALgAECgQJCAAAAA==.Misha:BAAALgADCgEJAQAAAA==.',
Mk='Mk:BAEALgAECgcJDgABLgAECggJOwAeAGsjAA==.',
Mo='Monkpig:BAACLgAFFH8QAAIdAAMJNh6AJAD9AANoDAAABwBLAGkMAAADAEwA6gwAAAYAUAAdAAMJNh6AJAD9AANoDAAABwBLAGkMAAADAEwA6gwAAAYAUAAuAAQKfyoAAh0ACQntHzYLAGMCAB0ACQntHzYLAGMCAAAA.Mooinator:BAAALgADCgYJBgAAAA==.',
My='Myrai:BAAALgADCgEJAQAAAA==.',
Na='Nanashi:BAABLgAECn8YAAIJAAYJTRWjIwAfAQZoDAAABgA2AGkMAAAEADEAawwAAAMAOQBqDAAABAAmAGwMAAAEAD0A6gwAAAMAMQAJAAYJTRWjIwAfAQZoDAAABgA2AGkMAAAEADEAawwAAAMAOQBqDAAABAAmAGwMAAAEAD0A6gwAAAMAMQAAAA==.Nannerz:BAAALgAECgYJEQAAAA==.Natenasty:BAAALgADCgUJBQABLgAECgQJBAAIAAAAAA==.Natenomoney:BAAALgAECgQJBAAAAA==.Nathan:BAAALgAECgMJAwABLgAECgQJBAAIAAAAAA==.',
Nd='Ndeh:BAAALgAFFAEJAQAAAA==.',
Ne='Nena:BAAALgAECgEJAQAAAA==.Nermonhunder:BAAALgAECgQJCAAAAA==.',
Ni='Ninjitsû:BAABLgAECn8aAAIMAAgJuBziHQCeAghoDAAABABLAGkMAAAEAEcAawwAAAQAPwBqDAAABABaAGwMAAADAFgAbQwAAAEAMgDqDAAABABTAG4MAAACAFIADAAICbgc4h0AngIIaAwAAAQASwBpDAAABABHAGsMAAAEAD8AagwAAAQAWgBsDAAAAwBYAG0MAAABADIA6gwAAAQAUwBuDAAAAgBSAAAA.',
Ol='Oldspice:BAAALgAECgMJBAAAAA==.Olex:BAAALgAECgUJBQAAAA==.',
Om='Omgkangel:BAABLgAECn8VAAILAAYJnBa6HABlAQZoDAAABAAzAGkMAAAEADcAawwAAAQASABqDAAAAwBAAGwMAAACACoA6gwAAAQAQgALAAYJnBa6HABlAQZoDAAABAAzAGkMAAAEADcAawwAAAQASABqDAAAAwBAAGwMAAACACoA6gwAAAQAQgAAAA==.Omi:BAAALgADCgYJBgAAAA==.Omie:BAAALgAECgEJBAAAAA==.',
On='Onoos:BAAALgAECgMJBgAAAA==.',
Ov='Overpower:BAAALgADCgIJAgABLgAECgkJKwASAMgUAA==.Ovix:BAAALgADCgMJAQABLgAECgUJDAAIAAAAAA==.',
Ow='Ow:BAAALgADCgEJAQAAAA==.',
Pa='Paulos:BAAALgAECgUJBgAAAA==.',
Pe='Peaf:BAABLgAECn8gAAMBAAYJlyCZKQCNAQZoDAAABgBiAGkMAAAGAEAAawwAAAYAXwBqDAAABQBSAGwMAAADAFMA6gwAAAYASwABAAYJlyCZKQCNAQZoDAAABQBiAGkMAAAFAEAAawwAAAYAXwBqDAAABABSAGwMAAADAFMA6gwAAAUASwACAAQJnAv2NgBwAARoDAAAAQAbAGkMAAABABkAagwAAAEAEwDqDAAAAQAkAAAA.Petesfeets:BAAALgADCgYJCAAAAA==.',
Pl='Playajizoe:BAAALgAECgQJBwAAAA==.',
Po='Pocketsnacks:BAAALgADCgEJAQAAAA==.Poppabanger:BAAALgAECgQJBwAAAA==.',
Qu='Quill:BAABLgAECn8eAAISAAcJrB1CSwARAgdoDAAABgBYAGkMAAAFAEoAawwAAAUAPABqDAAABQBRAGwMAAADAEYAbQwAAAEAYADqDAAABQBCABIABwmsHUJLABECB2gMAAAGAFgAaQwAAAUASgBrDAAABQA8AGoMAAAFAFEAbAwAAAMARgBtDAAAAQBgAOoMAAAFAEIAAS4ABRQDCQQACAAAAAA=.',
Ra='Raythe:BAABLgAECn8hAAIJAAcJ6BXmHABYAQdoDAAABQBFAGkMAAAHAE0AawwAAAUAPQBqDAAABAAXAGwMAAADACwAbQwAAAEAFADqDAAACAA+AAkABwnoFeYcAFgBB2gMAAAFAEUAaQwAAAcATQBrDAAABQA9AGoMAAAEABcAbAwAAAMALABtDAAAAQAUAOoMAAAIAD4AAAA=.Razzeman:BAAALgAECgEJAQAAAA==.Razzledazzl:BAAALgAECgEJAQAAAA==.',
Ro='Rose:BAAALgAECgcJCgABLgAFFAQJDgAfAHYHAA==.',
Ru='Ruck:BAAALgAECgYJBwABLgAECgkJIQACAIEbAA==.Rucker:BAABLgAECn8hAAMCAAkJgRtNCABTAgloDAAABgA+AGkMAAAGAFwAawwAAAUAPwBqDAAAAgA2AGwMAAADAFsAbQwAAAIAPgDqDAAABQBdAG4MAAADACcAbwwAAAEAOgACAAkJgRtNCABTAgloDAAABgA+AGkMAAAGAFwAawwAAAQAPwBqDAAAAgA2AGwMAAADAFsAbQwAAAIAPgDqDAAABQBdAG4MAAADACcAbwwAAAEAOgABAAEJWAIVtQAdAAFrDAAAAQAGAAAA.Ruckkin:BAAALgAECgMJBgABLgAECgkJIQACAIEbAA==.Rucksy:BAABLgAECn8nAAMDAAgJZh0RBQCrAghoDAAABwBcAGkMAAAHAGIAawwAAAgAXwBqDAAABQBXAGwMAAAFAEsAbQwAAAEAKADqDAAABQBbAG4MAAABAB8AAwAICWYdEQUAqwIIaAwAAAcAXABpDAAABwBiAGsMAAAHAF8AagwAAAQAVwBsDAAABQBLAG0MAAABACgA6gwAAAQAWwBuDAAAAQAfAAcAAwn+Ebf9AJkAA2sMAAABAB4AagwAAAEAOgDqDAAAAQA9AAEuAAQKCQkhAAIAgRsA.Ruxsi:BAAALgAECgUJCAABLgAECgkJIQACAIEbAA==.',
Ry='Ryan:BAABLgAECn8dAAMHAAgJHB8XJgBKAghoDAAABQBhAGkMAAAEAFIAawwAAAUAXABqDAAABQBhAGwMAAAEAFwAbQwAAAEAGQDqDAAABABaAG4MAAABAEwABwAHCaIiFyYASgIHaAwAAAMAYQBpDAAAAwBSAGsMAAAFAFwAagwAAAEAYQBsDAAAAgBcAOoMAAACAFoAbgwAAAEATAAhAAYJWCJGKgDgAQZoDAAAAgBdAGkMAAABAFUAagwAAAQAXQBsDAAAAgBZAG0MAAABAE0A6gwAAAIAVwAAAA==.',
['Rì']='Rìptide:BAAALgAECgkJEQAAAA==.',
['Rô']='Rôrônoazoro:BAAALgADCgYJCwAAAA==.',
Sa='Saragdan:BAAALgADCgcJCwAAAA==.',
Sc='Scylla:BAAALgAECgYJBgABLgAECgYJDwAIAAAAAA==.',
Se='Seraphae:BAAALgAECgEJAQAAAA==.Sereb:BAAALgAECgQJBAAAAA==.',
Sh='Shadowscurry:BAAALgAECgQJBwAAAA==.Shankzmcgee:BAABLgAECn8cAAIaAAYJcQqALwDyAAZoDAAABwApAGkMAAAHAB4AawwAAAYAGgBqDAAABAATAGwMAAACABUA6gwAAAIADQAaAAYJcQqALwDyAAZoDAAABwApAGkMAAAHAB4AawwAAAYAGgBqDAAABAATAGwMAAACABUA6gwAAAIADQABLgAECggJIAAHAM8UAA==.Shardik:BAAALgAECgUJBgAAAA==.Sheero:BAAALgAECgUJBQAAAA==.Sheong:BAAALgAECgkJCwAAAA==.Sheñ:BAAALgADCgkJHAAAAA==.Shindark:BAAALgAECgEJAgAAAA==.Shivah:BAAALgAECgcJCwABLgAFFAMJBAAIAAAAAA==.Shrus:BAAALgAECgYJBgAAAA==.Shrussy:BAAALgADCgMJAwAAAA==.Shèrlock:BAABLgAECn8cAAINAAkJjRCPNwDiAQloDAAABAAuAGkMAAAEAC8AawwAAAQAMABqDAAABABDAGwMAAADADAAbQwAAAIAFQDqDAAABABEAG4MAAACAC4AbwwAAAEACwANAAkJjRCPNwDiAQloDAAABAAuAGkMAAAEAC8AawwAAAQAMABqDAAABABDAGwMAAADADAAbQwAAAIAFQDqDAAABABEAG4MAAACAC4AbwwAAAEACwAAAA==.',
Si='Silverfox:BAAALgAFFAIJBAABLgAFFAMJDgAHAKAfAA==.',
Sk='Skippydippy:BAAALgAECgQJCwAAAA==.Skye:BAAALgAECgcJBQAAAA==.Skylin:BAAALgAECgEJBAAAAA==.',
Sl='Sleezee:BAAALgAECgMJBwAAAA==.Slushpuppis:BAAALgADCgcJBwAAAA==.',
Sn='Sneeger:BAAALgAECgUJBwAAAA==.',
Sp='Spelldeala:BAAALgAECgYJEAABLgAFFAMJCwAdAFcZAA==.',
St='Stargasm:BAAALgAFFAIJAgAAAA==.Stdmachine:BAAALgAECgYJDAAAAA==.Stonedstoner:BAAALgAECgUJBQAAAA==.',
Su='Superdump:BAAALgAECgcJAgAAAA==.',
Sw='Swiftmend:BAABLgAFFH8JAAIQAAIJtw5jRQCAAAJoDAAABAAnAOoMAAAFACMAEAACCbcOY0UAgAACaAwAAAQAJwDqDAAABQAjAAEuAAUUAwkLAB0AVxkA.',
Sy='Syllal:BAAALgADCgQJBAAAAA==.Synisttir:BAAALgAECgQJBAAAAA==.',
Ta='Taft:BAABLgAECn8wAAMiAAkJjBM3FwDpAQloDAAABQA9AGkMAAAIAD8AawwAAAcAOwBqDAAABwA5AGwMAAAGACUAbQwAAAQALQDqDAAABQA4AG4MAAAEADEAbwwAAAIAGwAiAAkJjBM3FwDpAQloDAAABQA9AGkMAAAIAD8AawwAAAcAOwBqDAAABwA5AGwMAAAGACUAbQwAAAQALQDqDAAABAA4AG4MAAAEADEAbwwAAAIAGwAQAAEJDQw7xwAoAAHqDAAAAQAeAAAA.Tardis:BAAALgADCgcJCgAAAA==.Taterz:BAAALgADCgQJBAAAAA==.',
Te='Terrá:BAAALgADCgkJGgAAAA==.Teryn:BAAALgAECgEJAQAAAA==.Tesa:BAAALgADCgMJBQAAAA==.',
Th='Thomassian:BAAALgAECgEJAgAAAA==.',
Ti='Timewing:BAAALgADCggJFAAAAA==.Timtoo:BAAALgAECgMJBQAAAA==.',
To='Toborntwob:BAAALgAECgYJEgAAAA==.',
Tr='Transformer:BAAALgAECgQJBgAAAA==.Triblequest:BAAALgAECgYJEQAAAA==.Tritin:BAAALgAECgYJEgAAAA==.Trotndot:BAAALgADCgQJBAAAAA==.',
Tu='Tugginmypuda:BAAALgAECgQJBAAAAA==.',
Tw='Twiltock:BAAALgAECgYJDAAAAA==.Twizztyd:BAAALgAECgEJAQAAAA==.Twocups:BAAALgAECgUJCgAAAA==.',
Un='Underware:BAAALgADCgYJBgAAAA==.',
Va='Valessa:BAABLgAECn8lAAIKAAgJNwUMoQAfAQhoDAAABgAPAGkMAAAGABQAawwAAAYABABqDAAABQAUAGwMAAAFABIAbQwAAAIACADqDAAABgAQAG4MAAABAAcACgAICTcFDKEAHwEIaAwAAAYADwBpDAAABgAUAGsMAAAGAAQAagwAAAUAFABsDAAABQASAG0MAAACAAgA6gwAAAYAEABuDAAAAQAHAAAA.Valiria:BAABLgAECn8eAAIMAAkJXRk4IgArAgloDAAAAwBQAGkMAAAFAF0AawwAAAQASgBqDAAABABgAGwMAAADAFIAbQwAAAEAJQDqDAAABwBfAG4MAAACABMAbwwAAAEAIwAMAAkJXRk4IgArAgloDAAAAwBQAGkMAAAFAF0AawwAAAQASgBqDAAABABgAGwMAAADAFIAbQwAAAEAJQDqDAAABwBfAG4MAAACABMAbwwAAAEAIwAAAA==.Varzul:BAAALgADCgYJCwABLgAECgIJAgAIAAAAAA==.',
Ve='Velieda:BAABLgAECn8kAAMHAAgJ1hEBcQBsAQhoDAAABgAoAGkMAAAFAC0AawwAAAUANABqDAAAAwA6AGwMAAAFAD8AbQwAAAIAFgDqDAAABQAkAG4MAAAFADkABwAICQcOAXEAbAEIaAwAAAIAJwBpDAAAAgAkAGsMAAACACgAagwAAAEAEgBsDAAAAgAiAG0MAAACABYA6gwAAAIAFABuDAAABQA5AAMABgm7EhIdAP4ABmgMAAAEACgAaQwAAAMALQBrDAAAAwA0AGoMAAACADoAbAwAAAMAPwDqDAAAAwAkAAAA.',
Vi='Vindication:BAACLgAFFH8QAAILAAQJLCZ1BgC9AQRoDAAABgBiAGkMAAAEAGAAawwAAAEAYgDqDAAABQBhAAsABAksJnUGAL0BBGgMAAAGAGIAaQwAAAQAYABrDAAAAQBiAOoMAAAFAGEALgAECn8jAAILAAgJKCAuBwC9AgALAAgJKCAuBwC9AgAAAA==.Vita:BAAALgAECgYJBwAAAA==.',
Wa='Wackah:BAAALgAECgYJCQAAAA==.Wakana:BAAALgAECgIJAgAAAA==.',
Wi='Windflower:BAAALgADCgQJBAAAAA==.Winteranne:BAAALgAECgEJAQAAAA==.',
Wo='Wolfcarver:BAAALgAECgYJEAAAAA==.Worldbreakèr:BAAALgAECggJAQAAAA==.',
['Wÿ']='Wÿcked:BAAALgAECgUJBQAAAA==.',
Xi='Xiaobao:BAAALgAFFAMJBAAAAA==.Xiaoduoduo:BAACLgAFFH8OAAMHAAMJoB+BPAAQAQNoDAAABgBfAGkMAAACAEAA6gwAAAYAUgAHAAMJoB+BPAAQAQNoDAAABQBfAGkMAAACAEAA6gwAAAYAUgAhAAEJuCMzNgBfAAFoDAAAAQBbAC4ABAp/KgACBwAJCaIjOQwA6AIABwAJCaIjOQwA6AIAAAA=.Xiaomak:BAAALgADCgQJBAAAAA==.Xiaoxiongmao:BAAALgADCgcJBwAAAA==.',
Xs='Xschaferr:BAAALgAECgYJDwAAAA==.',
Za='Zabz:BAAALgAECgEJAQABLgAECgkJLQAHAIQfAA==.',
Ze='Zeroskills:BAABLgAECn8kAAMaAAkJ/QcJHQCDAQloDAAABQAdAGkMAAAFACEAawwAAAUAFwBqDAAABAAlAGwMAAADABgAbQwAAAIAAwDqDAAABgAUAG4MAAAEABMAbwwAAAIACQAaAAkJ/QcJHQCDAQloDAAABAAdAGkMAAAEACEAawwAAAUAFwBqDAAABAAlAGwMAAADABgAbQwAAAIAAwDqDAAABgAUAG4MAAAEABMAbwwAAAIACQAbAAIJSwTMHABUAAJoDAAAAQAHAGkMAAABAA4AAAA=.',
Zu='Zulinar:BAAALgAECgYJDQAAAA==.Zumoku:BAAALgADCgkJLwAAAA==.',
['Às']='Àsmodeus:BAABLgAECn8oAAQfAAkJchGhEACjAQloDAAABgBMAGkMAAAHAC0AawwAAAgAJgBqDAAABwAyAGwMAAADADMAbQwAAAEAHADqDAAABgA8AG4MAAABACMAbwwAAAEAEwAfAAkJchGhEACjAQloDAAABgBMAGkMAAAHAC0AawwAAAcAJgBqDAAABwAyAGwMAAADADMAbQwAAAEAHADqDAAABQA8AG4MAAABACMAbwwAAAEAEwAiAAEJ8gaBgAAnAAFrDAAAAQARABAAAQkxCk7KACYAAeoMAAABABoAAAA=.',
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
