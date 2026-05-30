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

local lookup = {'Warrior-Fury','Warrior-Protection','Paladin-Protection','Warlock-Affliction','Priest-Discipline','Priest-Holy','Paladin-Retribution','DeathKnight-Unholy','DeathKnight-Frost','DemonHunter-Havoc','Hunter-BeastMastery','Mage-Frost','DeathKnight-Blood','Unknown-Unknown','DemonHunter-Devourer','Warlock-Demonology','Warlock-Destruction','Mage-Fire','Druid-Restoration','Shaman-Elemental','Evoker-Augmentation','Warrior-Arms','Priest-Shadow','Evoker-Devastation','Hunter-Survival','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Assassination','Shaman-Restoration','Monk-Brewmaster','Monk-Windwalker','Druid-Guardian','Evoker-Preservation','Paladin-Holy','Druid-Balance',}
local provider = {region='US',realm='TheForgottenCoast',name='US',type='daily',zone=46,date='2026-05-30',data={Aa='Aaricus:BAAALgAECgYJCAAAAA==.',
Ab='Aberdine:BAACLgAFFH8QAAIBAAUJiAuYIgAQAQVoDAAABQA0AGkMAAAEACQAawwAAAIADABqDAAAAQAbAOoMAAAEABAAAQAFCYgLmCIAEAEFaAwAAAUANABpDAAABAAkAGsMAAACAAwAagwAAAEAGwDqDAAABAAQAC4ABAp/KgADAQAJCakYiicAIAIAAQAJCakYiicAIAIAAgACCWcNTk4AKwAAAAA=.',
Ac='Accar:BAABLgAECn8kAAIDAAgJ6xBlEwB6AQhoDAAABgBDAGkMAAAGADUAawwAAAYAMQBqDAAABQBZAGwMAAAEAEUAbQwAAAIAFADqDAAABgAjAG4MAAABAAcAAwAICesQZRMAegEIaAwAAAYAQwBpDAAABgA1AGsMAAAGADEAagwAAAUAWQBsDAAABABFAG0MAAACABQA6gwAAAYAIwBuDAAAAQAHAAAA.Achu:BAAALgAFFAIJBAABLgAFFAQJGgAEAM8iAA==.Acylies:BAAALgADCgEJAQAAAA==.',
Ae='Aerìth:BAAALgADCgkJFwAAAA==.',
Ag='Agrias:BAABLgAECn8cAAMFAAgJCBjlEABFAghoDAAABABMAGkMAAAEAFUAawwAAAQAOQBqDAAABABQAGwMAAAEAD8AbQwAAAEAIwDqDAAABgBQAG4MAAABAAwABQAICQgY5RAARQIIaAwAAAQATABpDAAABABVAGsMAAAEADkAagwAAAQAUABsDAAAAwA/AG0MAAABACMA6gwAAAYAUABuDAAAAQAMAAYAAQmvDnloACwAAWwMAAABACUAAAA=.',
Al='Algodón:BAAALgADCgEJAQAAAA==.Aliera:BAAALgADCgcJCwAAAA==.',
Am='Amaltheah:BAAALgAECgQJBAAAAA==.Ambry:BAAALgAECgQJEgABLgAECgkJJQAHAL8QAA==.Ambryosia:BAABLgAECn8lAAIHAAkJvxAHaACFAQloDAAABgBBAGkMAAAFAEEAawwAAAQAHgBqDAAABAAkAGwMAAAEACYAbQwAAAMAEADqDAAABwA+AG4MAAADACsAbwwAAAEAEwAHAAkJvxAHaACFAQloDAAABgBBAGkMAAAFAEEAawwAAAQAHgBqDAAABAAkAGwMAAAEACYAbQwAAAMAEADqDAAABwA+AG4MAAADACsAbwwAAAEAEwAAAA==.',
An='Andras:BAAALgAECgIJAgAAAA==.Angerßane:BAAALgADCgMJAwAAAA==.',
Ar='Aradora:BAAALgADCgQJBQAAAA==.Arcanyounot:BAAALgADCgkJEgABLgAECgYJFAAIABMGAA==.',
As='Aspir:BAEALgAECgcJEwABLgAFFAYJFwAJAMEZAA==.',
Au='Auh:BAAALgAECgMJAwAAAA==.',
Av='Avera:BAAALgAECgIJAgAAAA==.Aviael:BAABLgAECn8eAAIKAAYJYBF9LAD4AAZoDAAABQAtAGkMAAAGAC8AawwAAAYAMQBqDAAABQAmAGwMAAACACkA6gwAAAYAJQAKAAYJYBF9LAD4AAZoDAAABQAtAGkMAAAGAC8AawwAAAYAMQBqDAAABQAmAGwMAAACACkA6gwAAAYAJQAAAA==.',
Aw='Awfulshotz:BAABLgAECn8UAAILAAkJwRtQRgC3AQloDAAAAgBhAGkMAAADAFgAawwAAAMAUQBqDAAAAwBiAGwMAAACAFQAbQwAAAEAMwDqDAAAAwBhAG4MAAACAD8AbwwAAAEABQALAAkJwRtQRgC3AQloDAAAAgBhAGkMAAADAFgAawwAAAMAUQBqDAAAAwBiAGwMAAACAFQAbQwAAAEAMwDqDAAAAwBhAG4MAAACAD8AbwwAAAEABQABLgAECgYJIAAMAOAUAA==.',
Ba='Badwolf:BAAALgAECgQJBwAAAA==.Bain:BAAALgADCgMJAwAAAA==.Bananabard:BAAALgADCgUJBQAAAA==.Barricade:BAABLgAECn8aAAMCAAkJJBdLFgCrAQloDAAABQBDAGkMAAADADsAawwAAAMAOQBqDAAAAwBaAGwMAAADACcAbQwAAAIAUgDqDAAABABXAG4MAAACADQAbwwAAAEAGwACAAkJJBdLFgCrAQloDAAABABDAGkMAAADADsAawwAAAIAOQBqDAAAAgBaAGwMAAACACcAbQwAAAIAUgDqDAAABABXAG4MAAACADQAbwwAAAEAGwABAAQJKRBBZwCiAARoDAAAAQAiAGsMAAABADMAagwAAAEAHQBsDAAAAQAmAAAA.',
Bc='Bcrogue:BAAALgADCgEJAQABLgAECgcJGwANADIfAA==.Bcwarrior:BAAALgAECgYJCQABLgAECgcJGwANADIfAA==.',
Be='Bearymanalow:BAAALgAECgEJAQAAAA==.Belgrove:BAAALgADCgEJAQAAAA==.',
Bh='Bheap:BAAALgAECgMJAwAAAA==.',
Bi='Bigbaauls:BAAALgAECgYJCQAAAA==.',
Bj='Björk:BAAALgAECgUJBQABLgAECgYJEwAOAAAAAA==.',
Bl='Blizzaga:BAAALgAECgYJDgAAAA==.',
Bo='Boiardi:BAAALgAECgYJCgAAAA==.Bootowsky:BAAALgAECgQJBAAAAA==.Boromen:BAAALgADCgEJAQAAAA==.Boutros:BAAALgADCgYJBgAAAA==.Bowberto:BAAALgAECgEJAwAAAA==.',
Br='Brea:BAAALgADCgEJAQAAAA==.Briélle:BAAALgADCgMJAwAAAA==.Brocephus:BAAALgAECgYJDwAAAA==.',
Bu='Burrgold:BAAALgAECggJDgAAAA==.',
Ca='Cadya:BAAALgAECgYJCQABLgAFFAMJBQAPAN4IAA==.',
Ce='Celticwoman:BAABLgAECn8jAAMQAAcJywknjAAYAQdoDAAABgAZAGkMAAAGACIAawwAAAYAFgBqDAAABQA3AGwMAAAFACwAbQwAAAEACQDqDAAABgAOABAABwnLCSeMABgBB2gMAAAEABkAaQwAAAQAIgBrDAAABAAWAGoMAAAEADcAbAwAAAUALABtDAAAAQAJAOoMAAAEAA4AEQAFCckEeTsAxgAFaAwAAAIAEgBpDAAAAgAKAGsMAAACAAkAagwAAAEADQDqDAAAAgAKAAAA.',
Ch='Champina:BAAALgAECgYJCQAAAA==.Chaoticelf:BAAALgADCgcJBwAAAA==.Chickenugget:BAABLgAECn8rAAISAAgJvgbuBgAUAQhoDAAABwAOAGkMAAAHAA4AawwAAAcADQBqDAAABQAPAGwMAAAGAA0AbQwAAAMAGwDqDAAABgAcAG4MAAACAAgAEgAICb4G7gYAFAEIaAwAAAcADgBpDAAABwAOAGsMAAAHAA0AagwAAAUADwBsDAAABgANAG0MAAADABsA6gwAAAYAHABuDAAAAgAIAAAA.Choral:BAAALgAECgMJBQAAAA==.Chubzilla:BAAALgADCgUJBQAAAA==.Chuckwagaon:BAAALgAECgEJAQAAAA==.',
Ci='Cinderdorla:BAABLgAFFH8FAAITAAIJGCJPNgDEAAJoDAAAAgBQAOoMAAADAF4AEwACCRgiTzYAxAACaAwAAAIAUADqDAAAAwBeAAEuAAUUBAkIABQALxQA.',
Cl='Clockie:BAACLgAFFH8aAAMEAAQJzyJuBwDeAARoDAAACgBhAGkMAAAFAGIAawwAAAIAPgDqDAAACQBhABAAAwlqIXNIACMBA2gMAAAKAGEAawwAAAIAPgDqDAAABwBgAAQAAglbJm4HAN4AAmkMAAAFAGIA6gwAAAIAYQAuAAQKfzsABAQACQneJOYFAAQCABAABwkJJOUhAE0CAAQABglTJeYFAAQCABEABAkKH7MjADsBAAAA.Clõüd:BAABLgAECn8bAAIHAAgJhA+TdgBmAQhoDAAABAAmAGkMAAAEACgAawwAAAQAMABqDAAABAAqAGwMAAAEADcAbQwAAAIAEQDqDAAABAAoAG4MAAABACYABwAICYQPk3YAZgEIaAwAAAQAJgBpDAAABAAoAGsMAAAEADAAagwAAAQAKgBsDAAABAA3AG0MAAACABEA6gwAAAQAKABuDAAAAQAmAAEuAAUUBgkSAAwAiAwA.',
Co='Coldarc:BAAALgADCgYJBgAAAA==.',
Cu='Cuitlahuac:BAAALgAECgEJAwAAAA==.Cupra:BAAALgADCgUJBQAAAA==.',
Cy='Cynthigosa:BAAALgAECgEJAQAAAA==.',
['Cô']='Cônky:BAAALgAECgYJEAAAAA==.',
Da='Dade:BAAALgAECgYJCAAAAA==.Dadeleviathn:BAAALgADCgEJAQABLgAECgYJCAAOAAAAAA==.Dagrul:BAAALgADCgUJBQAAAA==.Danteangelo:BAAALgAECgEJAQAAAA==.Darrkmann:BAAALgAECgkJEwAAAA==.',
De='Deathrotull:BAAALgADCgUJBwAAAA==.Deathslice:BAAALgADCgMJAwAAAA==.Delita:BAAALgAECgUJDQAAAA==.',
Di='Dietdrkelp:BAAALgADCgUJBQABLgAECgEJAQAOAAAAAA==.Dinkster:BAAALgAECgEJAQAAAA==.',
Dk='Dkcloud:BAABLgAECn8dAAIIAAcJUx8LQQDtAQdoDAAABgBTAGkMAAAEAFYAawwAAAQAVABqDAAAAwBIAGwMAAAEAFsAbQwAAAMANQDqDAAABQBSAAgABwlTHwtBAO0BB2gMAAAGAFMAaQwAAAQAVgBrDAAABABUAGoMAAADAEgAbAwAAAQAWwBtDAAAAwA1AOoMAAAFAFIAAS4ABRQGCRIADACIDAA=.',
Do='Donella:BAAALgADCgIJAgAAAA==.Doughboy:BAAALgAECgQJBwAAAA==.',
Dr='Drawinddy:BAAALgAFFAIJAgAAAA==.Drifty:BAAALgAECgYJCwAAAA==.',
Du='Duoduo:BAABLgAFFH8MAAIVAAIJMyEKFQDGAAJoDAAABgBcAOoMAAAGAE0AFQACCTMhChUAxgACaAwAAAYAXADqDAAABgBNAAEuAAUUBAkIABQALxQA.Duoduomoney:BAABLgAFFH8HAAMBAAIJSBuRNQCjAAJoDAAABABUAOoMAAADADYAAQACCUgbkTUAowACaAwAAAIAVADqDAAAAQA2ABYAAgnjDnMrAHwAAmgMAAACACUA6gwAAAIAJgABLgAFFAQJCAAUAC8UAA==.',
['Dø']='Dønut:BAAALgADCgUJBQAAAA==.',
Eb='Eboncelest:BAABLgAFFH8MAAIXAAMJlhXvHADnAANoDAAABwBKAGkMAAABADoA6gwAAAQAIAAXAAMJlhXvHADnAANoDAAABwBKAGkMAAABADoA6gwAAAQAIAABLgAFFAQJGgAEAM8iAA==.',
Ec='Eclesiastes:BAAALgAECgEJAQAAAA==.',
El='Eldarcirdan:BAABLgAECn8YAAITAAgJvQffXQAKAQhoDAAABAAYAGkMAAADAA8AawwAAAMAFABqDAAAAgAMAGwMAAACAAkAbQwAAAIACADqDAAABQAlAG4MAAADAB0AEwAICb0H310ACgEIaAwAAAQAGABpDAAAAwAPAGsMAAADABQAagwAAAIADABsDAAAAgAJAG0MAAACAAgA6gwAAAUAJQBuDAAAAwAdAAAA.',
Es='Esme:BAAALgADCgkJDwAAAA==.',
Et='Etrigon:BAAALgAECgEJAQAAAA==.',
Ev='Evajoh:BAAALgADCgUJBQAAAA==.',
Ex='Executioner:BAAALgADCgcJDwAAAA==.',
Fa='Fartstink:BAAALgADCgYJBwAAAA==.',
Fe='Festuss:BAAALgAECgQJDgAAAA==.',
Fi='Fingrwaglr:BAABLgAECn8gAAIYAAYJkwqqEADsAAZoDAAABgAuAGkMAAAGABcAawwAAAYAGABqDAAABQAiAGwMAAADABUA6gwAAAYAEgAYAAYJkwqqEADsAAZoDAAABgAuAGkMAAAGABcAawwAAAYAGABqDAAABQAiAGwMAAADABUA6gwAAAYAEgAAAA==.Fintan:BAAALgADCgMJAwAAAA==.Fizzlebliss:BAAALgADCgYJBgAAAA==.',
Fo='Forlin:BAAALgADCggJEQAAAA==.',
Fr='Frostlowe:BAAALgAECggJCgAAAA==.',
Fu='Fuzziestbutt:BAAALgADCgMJAwAAAA==.',
['Fú']='Fúsion:BAEALgAECgMJCQABLgAECgkJMwAPAHoiAA==.',
Ga='Gambokni:BAAALgADCgcJFAAAAA==.Gamebread:BAAALgAECgUJCAAAAA==.',
Gi='Giganate:BAAALgADCgEJAQABLgAECgQJBAAOAAAAAA==.Gixx:BAAALgAECgYJEAABLgAECggJIAAHAM8UAA==.',
Gl='Glorr:BAAALgAECgEJAQAAAA==.',
Go='Gonamanar:BAAALgAECgcJBQAAAA==.Goth:BAAALgADCgEJAQAAAA==.Gourge:BAAALgAECgkJDwAAAA==.',
Gr='Grimfall:BAABLgAECn8sAAQZAAgJ7hzsEQAOAghoDAAACABNAGkMAAAHAFQAawwAAAcAWABqDAAABgBLAGwMAAAFADYAbQwAAAIAMADqDAAABwBcAG4MAAACAEcAGQAICTQb7BEADgIIaAwAAAQATABpDAAABABFAGsMAAAEAEkAagwAAAQAMgBsDAAABAA2AG0MAAACADAA6gwAAAQAXABuDAAAAgBHAAsABQlyHttAAKwBBWgMAAABAE0AaQwAAAIAVABrDAAAAgBYAGoMAAACAEsA6gwAAAEAPQAaAAUJLBNOTwASAQVoDAAAAwA7AGkMAAABADYAawwAAAEALwBsDAAAAQAcAOoMAAACADYAAAA=.Grimtyr:BAAALgAECgEJAQAAAA==.Grëëdo:BAABLgAECn8gAAMHAAgJzxTtYgCRAQhoDAAABQA9AGkMAAAHAEcAawwAAAQAOgBqDAAABABRAGwMAAADADsAbQwAAAEAFgDqDAAABgA6AG4MAAACACgABwAICc8U7WIAkQEIaAwAAAUAPQBpDAAABgBHAGsMAAADADoAagwAAAMAUQBsDAAAAwA7AG0MAAABABYA6gwAAAYAOgBuDAAAAgAoAAMAAwkzBZdEADwAA2kMAAABABQAawwAAAEABgBqDAAAAQAKAAAA.',
Gy='Gylvi:BAAALgADCgMJAwABLgAECgYJHgAKAGARAA==.',
Ha='Hastor:BAAALgADCgcJBwAAAA==.',
He='Hellgrazer:BAAALgAECgUJCAAAAA==.',
Hi='Highlowe:BAAALgAECgUJBQAAAA==.Hikiru:BAAALgADCgkJJAAAAA==.',
Ho='Hollowbane:BAABLgAECn8oAAMbAAkJdxgRDgAvAgloDAAABgA6AGkMAAAGAEIAawwAAAUANABqDAAABABSAGwMAAAFADsAbQwAAAQAQQDqDAAABQBMAG4MAAAEACQAbwwAAAEAVQAbAAkJdxgRDgAvAgloDAAABAA6AGkMAAAEAEIAawwAAAQANABqDAAABABSAGwMAAAFADsAbQwAAAQAQQDqDAAABQBMAG4MAAAEACQAbwwAAAEAVQAcAAMJpBarFADJAANoDAAAAgA6AGkMAAACAD8AawwAAAEAMwAAAA==.Holydh:BAAALgAECgIJAgAAAA==.Holydragonn:BAAALgAFFAEJAQAAAA==.Holylock:BAAALgAFFAIJAgAAAA==.Holylordpig:BAAALgAFFAIJAgAAAA==.Holyshaman:BAABLgAFFH8FAAIdAAIJRQVQYABlAAJoDAAABAAWAOoMAAABAAQAHQACCUUFUGAAZQACaAwAAAQAFgDqDAAAAQAEAAAA.Holywarrior:BAAALgAFFAMJBAAAAA==.Holyymonk:BAAALgAECgEJAgAAAA==.Holyyseeker:BAAALgAFFAEJAQAAAA==.Homdantor:BAAALgAECgUJBQAAAA==.Horse:BAAALgAECgYJBwABLgAFFAgJFwAPACEbAA==.Hotyogafire:BAAALgAECgMJAwAAAA==.',
Ia='Iampally:BAAALgADCggJCQAAAA==.',
Im='Imhim:BAAALgAECgEJAQAAAA==.Imogen:BAAALgAECgcJEgAAAA==.',
Ja='Jadeddruid:BAAALgAECgkJCQAAAA==.Jamieson:BAACLgAFFH8SAAIMAAYJiAzuNABsAQZoDAAABQA2AGkMAAAEACgAawwAAAIADgBqDAAAAQARAGwMAAABABoA6gwAAAUAFwAMAAYJiAzuNABsAQZoDAAABQA2AGkMAAAEACgAawwAAAIADgBqDAAAAQARAGwMAAABABoA6gwAAAUAFwAuAAQKfzcAAgwACQn9H/MYABUDAAwACQn9H/MYABUDAAAA.Jand:BAAALgAECgYJDQAAAA==.Jazashi:BAAALgAECgYJFwAAAQ==.',
Jo='Jonesknight:BAABLgAECn8UAAIIAAYJEwYxzgDTAAZoDAAAAwAHAGkMAAADABEAawwAAAMAEwBqDAAAAgASAGwMAAAEAA0A6gwAAAUAFAAIAAYJEwYxzgDTAAZoDAAAAwAHAGkMAAADABEAawwAAAMAEwBqDAAAAgASAGwMAAAEAA0A6gwAAAUAFAAAAA==.Jonnytsunami:BAAALgAFFAIJAwAAAA==.',
Ju='Juicycow:BAAALgAECgYJCwAAAA==.',
Ka='Kahoru:BAAALgADCgcJBwAAAA==.Kailler:BAAALgAECgEJAQAAAA==.Kainn:BAAALgAECgYJEAAAAA==.',
Ke='Keg:BAACLgAFFH8hAAIeAAcJgyYNAQCjAgdoDAAABwBkAGkMAAAHAGMAawwAAAUAYQBqDAAABABhAGwMAAABAGEAbQwAAAEAYQDqDAAACABjAB4ABwmDJg0BAKMCB2gMAAAHAGQAaQwAAAcAYwBrDAAABQBhAGoMAAAEAGEAbAwAAAEAYQBtDAAAAQBhAOoMAAAIAGMALgAECn8jAAMeAAgJ0SZLAgB3AwAeAAgJ0SZLAgB3AwAfAAEJVSHzcABYAAAAAA==.',
Kh='Khakuzu:BAAALgADCgIJAgAAAA==.',
Ki='Kikinak:BAAALgAECgYJCwAAAA==.Killshøt:BAAALgADCgEJAQAAAA==.Kitty:BAACLgAFFH8OAAIgAAQJdgfgFQCwAARoDAAABgAjAGkMAAAEABEAawwAAAEACwDqDAAAAwALACAABAl2B+AVALAABGgMAAAGACMAaQwAAAQAEQBrDAAAAQALAOoMAAADAAsALgAECn8ZAAIgAAgJrhE5DwCIAQAgAAgJrhE5DwCIAQAAAA==.Kittyhawk:BAAALgAECggJDwAAAA==.',
Kk='Kk:BAAALgAECgYJEwAAAA==.',
Kl='Klassic:BAAALgAECgQJBgAAAA==.Klixx:BAAALgAECgYJDAAAAA==.',
Ko='Konexx:BAAALgADCgMJAwAAAA==.',
Ks='Kstab:BAABLgAECn8bAAIbAAcJLBuIGgAuAgdoDAAAAwBKAGkMAAAFAEoAawwAAAUAUgBqDAAABAAvAGwMAAABACEA6gwAAAUAOwBuDAAABABcABsABwksG4gaAC4CB2gMAAADAEoAaQwAAAUASgBrDAAABQBSAGoMAAAEAC8AbAwAAAEAIQDqDAAABQA7AG4MAAAEAFwAAAA=.',
Ku='Kuromeow:BAABLgAFFH8HAAIMAAIJYRl9NgC9AAJoDAAAAgAoAOoMAAAFAFkADAACCWEZfTYAvQACaAwAAAIAKADqDAAABQBZAAAA.',
La='Lachasis:BAAALgAECgQJBAAAAA==.Larake:BAABLgAECn8bAAIhAAYJnw4ZGQAvAQZoDAAABwAzAGkMAAAFACMAawwAAAUAEQBqDAAABAAYAGwMAAADACIA6gwAAAMAPgAhAAYJnw4ZGQAvAQZoDAAABwAzAGkMAAAFACMAawwAAAUAEQBqDAAABAAYAGwMAAADACIA6gwAAAMAPgAAAA==.Lazypie:BAAALgAECgUJBQAAAA==.',
Le='Leggomyaggro:BAAALgAECgMJBQABLgAFFAQJEwANACwmAA==.Lesiania:BAAALgAECgEJAwABLgAECgYJCAAOAAAAAA==.',
Li='Licus:BAAALgADCgkJFAAAAA==.Lightkeeper:BAABLgAECn8kAAMXAAgJShdPGwDOAQhoDAAABgBMAGkMAAAGAEgAawwAAAUANQBqDAAABQAYAGwMAAAEADkAbQwAAAMAMwDqDAAABQBOAG4MAAACABoAFwAICUoXTxsAzgEIaAwAAAUATABpDAAABQBIAGsMAAAEADUAagwAAAUAGABsDAAABAA5AG0MAAADADMA6gwAAAUATgBuDAAAAgAaAAYAAwnvBO9sAHYAA2gMAAABAAMAaQwAAAEADQBrDAAAAQAUAAAA.Lightning:BAAALgADCgEJAQAAAA==.Limpßrisket:BAAALgAECgMJAgAAAA==.Litdealer:BAAALgAECgYJDgABLgAFFAMJCwAeAFcZAA==.Littlestiffy:BAAALgADCgMJAwAAAA==.',
Lr='Lroux:BAAALgAECgcJDwAAAA==.',
Lu='Lucyah:BAAALgAECgYJCgAAAA==.',
Ma='Malkallam:BAAALgADCgUJBQAAAA==.Manaplague:BAAALgAECgUJCwAAAA==.Manenya:BAAALgAECgYJCAAAAA==.Marotto:BAAALgAECgMJAwAAAA==.Massacar:BAABLgAECn8YAAIPAAYJSgo5igAPAQZoDAAABQArAGkMAAAFACoAawwAAAUAEgBqDAAABAAoAGwMAAACAA4A6gwAAAMADQAPAAYJSgo5igAPAQZoDAAABQArAGkMAAAFACoAawwAAAUAEgBqDAAABAAoAGwMAAACAA4A6gwAAAMADQABLgAECggJIAAHAM8UAA==.',
Me='Meatpuller:BAAALgADCgkJDwAAAA==.Menion:BAABLgAECn8cAAMHAAkJZhuLJgCMAgloDAAABABWAGkMAAAEAF0AawwAAAQAWABqDAAABABQAGwMAAADAD8AbQwAAAEAJQDqDAAABABUAG4MAAADAEQAbwwAAAEAJgAHAAkJZhuLJgCMAgloDAAAAwBWAGkMAAADAF0AawwAAAMAWABqDAAAAwBQAGwMAAACAD8AbQwAAAEAJQDqDAAABABUAG4MAAADAEQAbwwAAAEAJgADAAUJQgzuLQCZAAVoDAAAAQAeAGkMAAABAAsAawwAAAEAMwBqDAAAAQAUAGwMAAABACAAAAA=.Meowmeowmeow:BAAALgADCgcJBwABLgAFFAcJIAAIABwfAA==.Mercadius:BAAALgAECgYJEAAAAA==.Metalx:BAAALgADCgkJFQAAAA==.',
Mi='Minkyu:BAAALgAECgQJCAAAAA==.Misha:BAAALgADCgEJAQAAAA==.',
Mk='Mk:BAEALgAECgcJEQABLgAECggJPQAfAGsjAA==.',
Mo='Monkpig:BAACLgAFFH8UAAIeAAQJzx1AFABbAQRoDAAACABTAGkMAAAEAEwAawwAAAEAQADqDAAABwBQAB4ABAnPHUAUAFsBBGgMAAAIAFMAaQwAAAQATABrDAAAAQBAAOoMAAAHAFAALgAECn8qAAIeAAkJ7R9NDABeAgAeAAkJ7R9NDABeAgAAAA==.Mooinator:BAAALgADCgYJBgAAAA==.',
My='Myrai:BAAALgADCgEJAQAAAA==.',
Na='Nanashi:BAABLgAECn8YAAIKAAYJTRU/JwAbAQZoDAAABgA2AGkMAAAEADEAawwAAAMAOQBqDAAABAAmAGwMAAAEAD0A6gwAAAMAMQAKAAYJTRU/JwAbAQZoDAAABgA2AGkMAAAEADEAawwAAAMAOQBqDAAABAAmAGwMAAAEAD0A6gwAAAMAMQAAAA==.Nannerz:BAAALgAECgYJEQAAAA==.Natenasty:BAAALgADCgUJBQABLgAECgQJBAAOAAAAAA==.Natenomoney:BAAALgAECgQJBAAAAA==.Nathan:BAAALgAECgMJAwABLgAECgQJBAAOAAAAAA==.',
Nd='Ndeh:BAAALgAFFAEJAQAAAA==.',
Ne='Nena:BAAALgAECgEJAQAAAA==.Nermonhunder:BAAALgAECgQJCAAAAA==.',
Ni='Ninjitsû:BAABLgAECn8aAAIPAAgJuBziHQCeAghoDAAABABLAGkMAAAEAEcAawwAAAQAPwBqDAAABABaAGwMAAADAFgAbQwAAAEAMgDqDAAABABTAG4MAAACAFIADwAICbgc4h0AngIIaAwAAAQASwBpDAAABABHAGsMAAAEAD8AagwAAAQAWgBsDAAAAwBYAG0MAAABADIA6gwAAAQAUwBuDAAAAgBSAAAA.',
Ol='Oldspice:BAAALgAECgMJBAAAAA==.Olex:BAAALgAECgUJBQAAAA==.',
Om='Omgkangel:BAABLgAECn8VAAINAAYJnBa6HABlAQZoDAAABAAzAGkMAAAEADcAawwAAAQASABqDAAAAwBAAGwMAAACACoA6gwAAAQAQgANAAYJnBa6HABlAQZoDAAABAAzAGkMAAAEADcAawwAAAQASABqDAAAAwBAAGwMAAACACoA6gwAAAQAQgAAAA==.Omi:BAAALgADCgYJBgAAAA==.Omie:BAAALgAECgEJBAAAAA==.',
On='Onoos:BAAALgAECgMJBgAAAA==.',
Ov='Overpower:BAAALgADCgIJAgABLgAECgkJKwAIAMgUAA==.Ovix:BAAALgADCgMJAQABLgAECgUJDAAOAAAAAA==.',
Ow='Ow:BAAALgADCgEJAQAAAA==.',
Pa='Paulos:BAAALgAECgUJCQAAAA==.',
Pe='Peaf:BAABLgAECn8gAAMBAAYJlyB1LQCIAQZoDAAABgBiAGkMAAAGAEAAawwAAAYAXwBqDAAABQBSAGwMAAADAFMA6gwAAAYASwABAAYJlyB1LQCIAQZoDAAABQBiAGkMAAAFAEAAawwAAAYAXwBqDAAABABSAGwMAAADAFMA6gwAAAUASwACAAQJnAssOwBtAARoDAAAAQAbAGkMAAABABkAagwAAAEAEwDqDAAAAQAkAAAA.Petesfeets:BAAALgADCgYJCAAAAA==.',
Pl='Playajizoe:BAAALgAECgQJBwAAAA==.',
Po='Pocketsnacks:BAAALgADCgEJAQAAAA==.Poppabanger:BAAALgAECgQJBwAAAA==.',
Qu='Quill:BAABLgAECn8eAAIIAAcJrB1CSwARAgdoDAAABgBYAGkMAAAFAEoAawwAAAUAPABqDAAABQBRAGwMAAADAEYAbQwAAAEAYADqDAAABQBCAAgABwmsHUJLABECB2gMAAAGAFgAaQwAAAUASgBrDAAABQA8AGoMAAAFAFEAbAwAAAMARgBtDAAAAQBgAOoMAAAFAEIAAS4ABRQDCQQADgAAAAA=.',
Ra='Raythe:BAABLgAECn8hAAIKAAcJ6BUQIABTAQdoDAAABQBFAGkMAAAHAE0AawwAAAUAPQBqDAAABAAXAGwMAAADACwAbQwAAAEAFADqDAAACAA+AAoABwnoFRAgAFMBB2gMAAAFAEUAaQwAAAcATQBrDAAABQA9AGoMAAAEABcAbAwAAAMALABtDAAAAQAUAOoMAAAIAD4AAAA=.Razzeman:BAAALgAECgEJAQAAAA==.Razzledazzl:BAAALgAECgEJAQAAAA==.',
Ro='Rose:BAAALgAECgcJCgABLgAFFAQJDgAgAHYHAA==.',
Ru='Ruck:BAAALgAECgcJDQABLgAECgkJIQACAIEbAA==.Rucker:BAABLgAECn8hAAMCAAkJgRueCQBFAgloDAAABgA+AGkMAAAGAFwAawwAAAUAPwBqDAAAAgA2AGwMAAADAFsAbQwAAAIAPgDqDAAABQBdAG4MAAADACcAbwwAAAEAOgACAAkJgRueCQBFAgloDAAABgA+AGkMAAAGAFwAawwAAAQAPwBqDAAAAgA2AGwMAAADAFsAbQwAAAIAPgDqDAAABQBdAG4MAAADACcAbwwAAAEAOgABAAEJWAIVtQAdAAFrDAAAAQAGAAAA.Ruckkin:BAAALgAECgMJBgABLgAECgkJIQACAIEbAA==.Rucksy:BAABLgAECn8oAAMDAAgJoB0RBQCrAghoDAAABwBcAGkMAAAHAGIAawwAAAgAXwBqDAAABQBXAGwMAAAFAEsAbQwAAAEAKADqDAAABQBbAG4MAAACACMAAwAICaAdEQUAqwIIaAwAAAcAXABpDAAABwBiAGsMAAAHAF8AagwAAAQAVwBsDAAABQBLAG0MAAABACgA6gwAAAQAWwBuDAAAAgAjAAcAAwn+Ebf9AJkAA2sMAAABAB4AagwAAAEAOgDqDAAAAQA9AAEuAAQKCQkhAAIAgRsA.Ruckuhs:BAAALgADCgkJDAABLgAECgkJIQACAIEbAA==.Ruxsi:BAAALgAECgUJCAABLgAECgkJIQACAIEbAA==.',
Ry='Ryan:BAABLgAECn8gAAMHAAgJ8h+wJgBQAghoDAAABQBhAGkMAAAFAGEAawwAAAYAXABqDAAABQBhAGwMAAAEAFwAbQwAAAEAGQDqDAAABQBaAG4MAAABAEwABwAHCZwjsCYAUAIHaAwAAAMAYQBpDAAABABhAGsMAAAGAFwAagwAAAEAYQBsDAAAAgBcAOoMAAADAFoAbgwAAAEATAAiAAYJWCJGKgDgAQZoDAAAAgBdAGkMAAABAFUAagwAAAQAXQBsDAAAAgBZAG0MAAABAE0A6gwAAAIAVwAAAA==.',
['Rì']='Rìptide:BAAALgAECgkJEQAAAA==.',
['Rô']='Rôrônoazoro:BAAALgADCgYJCwAAAA==.',
Sa='Saragdan:BAAALgADCgcJCwAAAA==.',
Sc='Scylla:BAAALgAECgYJBgABLgAECgYJDwAOAAAAAA==.',
Se='Seraphae:BAAALgAECgEJAgAAAA==.Sereb:BAAALgAECgQJBQAAAA==.',
Sh='Shadowscurry:BAAALgAECgQJBwAAAA==.Shankzmcgee:BAABLgAECn8cAAIbAAYJcQpHMwDvAAZoDAAABwApAGkMAAAHAB4AawwAAAYAGgBqDAAABAATAGwMAAACABUA6gwAAAIADQAbAAYJcQpHMwDvAAZoDAAABwApAGkMAAAHAB4AawwAAAYAGgBqDAAABAATAGwMAAACABUA6gwAAAIADQABLgAECggJIAAHAM8UAA==.Shardik:BAAALgAECgUJCQAAAA==.Sheero:BAAALgAECgUJBQAAAA==.Sheong:BAAALgAECgkJCwAAAA==.Sheñ:BAAALgADCgkJIAAAAA==.Shindark:BAAALgAECgEJAgAAAA==.Shivah:BAAALgAECgcJCwABLgAFFAMJBAAOAAAAAA==.Shrus:BAAALgAECgYJBgAAAA==.Shrussy:BAAALgADCgMJAwAAAA==.Shèrlock:BAABLgAECn8hAAIQAAkJ8BAPPADdAQloDAAABAAuAGkMAAAFAC8AawwAAAUAMABqDAAABQBDAGwMAAAEADAAbQwAAAMAHADqDAAABABEAG4MAAACAC4AbwwAAAEACwAQAAkJ8BAPPADdAQloDAAABAAuAGkMAAAFAC8AawwAAAUAMABqDAAABQBDAGwMAAAEADAAbQwAAAMAHADqDAAABABEAG4MAAACAC4AbwwAAAEACwAAAA==.',
Si='Silverfox:BAABLgAFFH8IAAMUAAQJLxTbGwAYAQRoDAAAAwA9AGkMAAABACIAawwAAAEANwDqDAAAAwA3ABQABAkvFNsbABgBBGgMAAABAD0AaQwAAAEAIgBrDAAAAQA3AOoMAAABADcAHQACCSga5k4AmQACaAwAAAIAMADqDAAAAgBVAAAA.',
Sk='Skippydippy:BAAALgAECgQJCwAAAA==.Skye:BAAALgAECgcJBQAAAA==.Skylin:BAAALgAECgEJBAAAAA==.',
Sl='Sleezee:BAAALgAECgQJCQAAAA==.Slushpuppis:BAAALgADCgcJBwAAAA==.',
Sn='Sneeger:BAAALgAECgYJDQAAAA==.',
Sp='Spelldeala:BAAALgAECgYJEAABLgAFFAMJCwAeAFcZAA==.',
St='Stargasm:BAABLgAFFH8FAAIGAAIJqgtPJgBoAAJoDAAAAgAWAGkMAAADACUABgACCaoLTyYAaAACaAwAAAIAFgBpDAAAAwAlAAAA.Stdmachine:BAAALgAECgYJDAAAAA==.Stonedstoner:BAAALgAECgUJCAAAAA==.',
Su='Superdump:BAAALgAECgcJAgAAAA==.',
Sw='Swiftmend:BAABLgAFFH8JAAITAAIJtw5rTAB4AAJoDAAABAAnAOoMAAAFACMAEwACCbcOa0wAeAACaAwAAAQAJwDqDAAABQAjAAEuAAUUAwkLAB4AVxkA.',
Sy='Syleyn:BAAALgAECgIJAgABLgAFFAQJEwANACwmAA==.Syllal:BAAALgADCgQJBAAAAA==.Synisttir:BAAALgAECgYJDQAAAA==.',
Ta='Taft:BAABLgAECn8wAAMjAAkJjBOTGQDnAQloDAAABQA9AGkMAAAIAD8AawwAAAcAOwBqDAAABwA5AGwMAAAGACUAbQwAAAQALQDqDAAABQA4AG4MAAAEADEAbwwAAAIAGwAjAAkJjBOTGQDnAQloDAAABQA9AGkMAAAIAD8AawwAAAcAOwBqDAAABwA5AGwMAAAGACUAbQwAAAQALQDqDAAABAA4AG4MAAAEADEAbwwAAAIAGwATAAEJDQyw0AAoAAHqDAAAAQAeAAAA.Tardis:BAAALgADCgcJCgAAAA==.Taterz:BAAALgADCgQJBAAAAA==.',
Te='Terrá:BAAALgADCgkJHwAAAA==.Teryn:BAAALgAECgEJAQAAAA==.Tesa:BAAALgADCgMJBQAAAA==.',
Th='Thomassian:BAAALgAECgEJAgAAAA==.',
Ti='Timewing:BAAALgADCggJFAAAAA==.Timtoo:BAAALgAECgMJBQAAAA==.',
To='Toborntwob:BAAALgAECgYJEwAAAA==.',
Tr='Transformer:BAAALgAECgQJBgAAAA==.Triblequest:BAABLgAECn8WAAIUAAYJBhXgNgBCAQZoDAAABQBGAGkMAAAEAEYAawwAAAQANQBqDAAAAwBKAGwMAAABAAcA6gwAAAUARAAUAAYJBhXgNgBCAQZoDAAABQBGAGkMAAAEAEYAawwAAAQANQBqDAAAAwBKAGwMAAABAAcA6gwAAAUARAAAAA==.Tritin:BAABLgAECn8VAAIHAAgJmAZ9vADwAAhoDAAAAwAVAGkMAAADABIAawwAAAIADwBqDAAAAgATAGwMAAAEABwAbQwAAAEADgDqDAAABQASAG4MAAABAAEABwAICZgGfbwA8AAIaAwAAAMAFQBpDAAAAwASAGsMAAACAA8AagwAAAIAEwBsDAAABAAcAG0MAAABAA4A6gwAAAUAEgBuDAAAAQABAAAA.Trotndot:BAAALgADCgQJBAAAAA==.',
Tu='Tugginmypuda:BAAALgAECgQJBAAAAA==.',
Tw='Twiltock:BAAALgAECgYJDAAAAA==.Twizztyd:BAAALgAECgYJDAAAAA==.Twocups:BAAALgAECgUJCgAAAA==.',
Un='Underware:BAAALgADCgYJBgAAAA==.',
Va='Valessa:BAABLgAECn8sAAIMAAgJ6wWOqAASAQhoDAAABgAPAGkMAAAGABQAawwAAAcABQBqDAAABgAUAGwMAAAHABIAbQwAAAMAEgDqDAAABwAQAG4MAAACAAkADAAICesFjqgAEgEIaAwAAAYADwBpDAAABgAUAGsMAAAHAAUAagwAAAYAFABsDAAABwASAG0MAAADABIA6gwAAAcAEABuDAAAAgAJAAAA.Valiria:BAACLgAFFH8FAAIPAAMJlxOxUADZAANoDAAAAgA/AGkMAAACACQA6gwAAAEAMgAPAAMJlxOxUADZAANoDAAAAgA/AGkMAAACACQA6gwAAAEAMgAuAAQKfx8AAg8ACQldGQwmACACAA8ACQldGQwmACACAAAA.Varzul:BAAALgADCgYJCwABLgAECgIJAgAOAAAAAA==.',
Ve='Velieda:BAABLgAECn8mAAMHAAgJ0xH2gABSAQhoDAAABgAoAGkMAAAGAC0AawwAAAYANABqDAAAAwA6AGwMAAAFAD8AbQwAAAIAFgDqDAAABQAkAG4MAAAFADkABwAICQcO9oAAUgEIaAwAAAIAJwBpDAAAAgAkAGsMAAACACgAagwAAAEAEgBsDAAAAgAiAG0MAAACABYA6gwAAAIAFABuDAAABQA5AAMABgm3ErgdAA0BBmgMAAAEACgAaQwAAAQALQBrDAAABAA0AGoMAAACADoAbAwAAAMAPwDqDAAAAwAkAAAA.',
Vi='Vindication:BAACLgAFFH8TAAINAAQJLCaGCAC3AQRoDAAABwBiAGkMAAAFAGAAawwAAAIAYgDqDAAABQBhAA0ABAksJoYIALcBBGgMAAAHAGIAaQwAAAUAYABrDAAAAgBiAOoMAAAFAGEALgAECn8nAAINAAgJKCAuBwC9AgANAAgJKCAuBwC9AgAAAA==.Vita:BAAALgAECgYJBwAAAA==.',
Wa='Wackah:BAAALgAECgYJCQAAAA==.Wafflez:BAAALgAECgIJAgAAAA==.Wakana:BAAALgAECgIJAgAAAA==.',
Wi='Windflower:BAAALgADCgQJBAAAAA==.Winteranne:BAAALgAECgEJAQAAAA==.',
Wo='Wolfcarver:BAAALgAECgYJEAAAAA==.Worldbreakèr:BAAALgAECggJAQAAAA==.',
['Wÿ']='Wÿcked:BAAALgAECgUJBQAAAA==.',
Xi='Xiaobao:BAABLgAFFH8IAAIgAAQJOg08EADYAARoDAAAAwBEAGkMAAACACoAawwAAAEABgDqDAAAAgASACAABAk6DTwQANgABGgMAAADAEQAaQwAAAIAKgBrDAAAAQAGAOoMAAACABIAAAA=.Xiaoduoduo:BAACLgAFFH8OAAMHAAMJoB+XRwADAQNoDAAABgBfAGkMAAACAEAA6gwAAAYAUgAHAAMJoB+XRwADAQNoDAAABQBfAGkMAAACAEAA6gwAAAYAUgAiAAEJuCMYOwBdAAFoDAAAAQBbAC4ABAp/KgACBwAJCaIjvQ4A2gIABwAJCaIjvQ4A2gIAAS4ABRQECQgAFAAvFAA=.Xiaomak:BAAALgADCgQJBAABLgAFFAQJCAAUAC8UAA==.Xiaoxiongmao:BAAALgADCgcJBwAAAA==.',
Xs='Xschaferr:BAABLgAECn8WAAIHAAcJmAWP3ADDAAdoDAAAAwARAGkMAAADABMAawwAAAMADwBqDAAABAASAGwMAAAFABEAbQwAAAEAAQDqDAAAAwAPAAcABwmYBY/cAMMAB2gMAAADABEAaQwAAAMAEwBrDAAAAwAPAGoMAAAEABIAbAwAAAUAEQBtDAAAAQABAOoMAAADAA8AAAA=.',
Za='Zabz:BAAALgAECgEJAgABLgAECgkJNgAHAMAgAA==.',
Ze='Zeroskills:BAABLgAECn8kAAMbAAkJ/QflHwB8AQloDAAABQAdAGkMAAAFACEAawwAAAUAFwBqDAAABAAlAGwMAAADABgAbQwAAAIAAwDqDAAABgAUAG4MAAAEABMAbwwAAAIACQAbAAkJ/QflHwB8AQloDAAABAAdAGkMAAAEACEAawwAAAUAFwBqDAAABAAlAGwMAAADABgAbQwAAAIAAwDqDAAABgAUAG4MAAAEABMAbwwAAAIACQAcAAIJSwSnHgBUAAJoDAAAAQAHAGkMAAABAA4AAAA=.',
Zu='Zulinar:BAAALgAECgYJEgAAAA==.Zumoku:BAAALgADCgkJLwAAAA==.',
['Às']='Àsmodeus:BAABLgAECn80AAQgAAkJwhIwEADDAQloDAAACABMAGkMAAAJAC0AawwAAAoALQBqDAAACQBAAGwMAAAEADMAbQwAAAEAHADqDAAACABRAG4MAAACACMAbwwAAAEAEwAgAAkJwhIwEADDAQloDAAACABMAGkMAAAJAC0AawwAAAkALQBqDAAACQBAAGwMAAADADMAbQwAAAEAHADqDAAABwBRAG4MAAACACMAbwwAAAEAEwAjAAIJrgXicwBHAAJrDAAAAQARAGwMAAABAAsAEwABCTEK6tMAJgAB6gwAAAEAGgAAAA==.',
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
