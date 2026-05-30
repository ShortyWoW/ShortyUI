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

local lookup = {'Warrior-Fury','Warrior-Protection','Paladin-Protection','Warlock-Affliction','Priest-Discipline','Priest-Holy','Paladin-Retribution','DeathKnight-Unholy','DeathKnight-Frost','DemonHunter-Havoc','Hunter-BeastMastery','Mage-Frost','DeathKnight-Blood','Unknown-Unknown','DemonHunter-Devourer','Warlock-Demonology','Warlock-Destruction','Mage-Fire','Druid-Restoration','Evoker-Augmentation','Warrior-Arms','Priest-Shadow','Evoker-Devastation','Hunter-Survival','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Assassination','Shaman-Restoration','Monk-Brewmaster','Monk-Windwalker','Druid-Guardian','Evoker-Preservation','Paladin-Holy','Druid-Balance','Shaman-Elemental',}
local provider = {region='US',realm='TheForgottenCoast',name='US',type='daily',zone=46,date='2026-05-29',data={Aa='Aaricus:BAAALgAECgYJCAAAAA==.',
Ab='Aberdine:BAACLgAFFH8QAAIBAAUJiAsRIgARAQVoDAAABQA0AGkMAAAEACQAawwAAAIADABqDAAAAQAbAOoMAAAEABAAAQAFCYgLESIAEQEFaAwAAAUANABpDAAABAAkAGsMAAACAAwAagwAAAEAGwDqDAAABAAQAC4ABAp/KgADAQAJCakYiicAIAIAAQAJCakYiicAIAIAAgACCWcNtk0AKwAAAAA=.',
Ac='Accar:BAABLgAECn8kAAIDAAgJ6xA1EwB7AQhoDAAABgBDAGkMAAAGADUAawwAAAYAMQBqDAAABQBZAGwMAAAEAEUAbQwAAAIAFADqDAAABgAjAG4MAAABAAcAAwAICesQNRMAewEIaAwAAAYAQwBpDAAABgA1AGsMAAAGADEAagwAAAUAWQBsDAAABABFAG0MAAACABQA6gwAAAYAIwBuDAAAAQAHAAAA.Achu:BAAALgAFFAIJBAABLgAFFAQJFgAEAFoiAA==.Acylies:BAAALgADCgEJAQAAAA==.',
Ae='Aerìth:BAAALgADCgkJFwAAAA==.',
Ag='Agrias:BAABLgAECn8cAAMFAAgJCBi6EABFAghoDAAABABMAGkMAAAEAFUAawwAAAQAOQBqDAAABABQAGwMAAAEAD8AbQwAAAEAIwDqDAAABgBQAG4MAAABAAwABQAICQgYuhAARQIIaAwAAAQATABpDAAABABVAGsMAAAEADkAagwAAAQAUABsDAAAAwA/AG0MAAABACMA6gwAAAYAUABuDAAAAQAMAAYAAQmvDt1nACwAAWwMAAABACUAAAA=.',
Al='Algodón:BAAALgADCgEJAQAAAA==.Aliera:BAAALgADCgcJCwAAAA==.',
Am='Amaltheah:BAAALgAECgQJBAAAAA==.Ambry:BAAALgAECgQJEgABLgAECgkJJQAHAL8QAA==.Ambryosia:BAABLgAECn8lAAIHAAkJvxDzZgCFAQloDAAABgBBAGkMAAAFAEEAawwAAAQAHgBqDAAABAAkAGwMAAAEACYAbQwAAAMAEADqDAAABwA+AG4MAAADACsAbwwAAAEAEwAHAAkJvxDzZgCFAQloDAAABgBBAGkMAAAFAEEAawwAAAQAHgBqDAAABAAkAGwMAAAEACYAbQwAAAMAEADqDAAABwA+AG4MAAADACsAbwwAAAEAEwAAAA==.',
An='Andras:BAAALgAECgIJAgAAAA==.Angerßane:BAAALgADCgMJAwAAAA==.',
Ar='Aradora:BAAALgADCgQJBQAAAA==.Arcanyounot:BAAALgADCgkJEgABLgAECgYJFAAIABMGAA==.',
As='Aspir:BAEALgAECgcJEwABLgAFFAYJFwAJAMEZAA==.',
Au='Auh:BAAALgAECgMJAwAAAA==.',
Av='Avera:BAAALgAECgIJAgAAAA==.Aviael:BAABLgAECn8eAAIKAAYJYBH5KwD5AAZoDAAABQAtAGkMAAAGAC8AawwAAAYAMQBqDAAABQAmAGwMAAACACkA6gwAAAYAJQAKAAYJYBH5KwD5AAZoDAAABQAtAGkMAAAGAC8AawwAAAYAMQBqDAAABQAmAGwMAAACACkA6gwAAAYAJQAAAA==.',
Aw='Awfulshotz:BAABLgAECn8UAAILAAkJwRt1RQC3AQloDAAAAgBhAGkMAAADAFgAawwAAAMAUQBqDAAAAwBiAGwMAAACAFQAbQwAAAEAMwDqDAAAAwBhAG4MAAACAD8AbwwAAAEABQALAAkJwRt1RQC3AQloDAAAAgBhAGkMAAADAFgAawwAAAMAUQBqDAAAAwBiAGwMAAACAFQAbQwAAAEAMwDqDAAAAwBhAG4MAAACAD8AbwwAAAEABQABLgAECgYJIAAMAOAUAA==.',
Ba='Badwolf:BAAALgAECgQJBwAAAA==.Bain:BAAALgADCgMJAwAAAA==.Bananabard:BAAALgADCgUJBQAAAA==.Barricade:BAABLgAECn8aAAMCAAkJJBdLFgCrAQloDAAABQBDAGkMAAADADsAawwAAAMAOQBqDAAAAwBaAGwMAAADACcAbQwAAAIAUgDqDAAABABXAG4MAAACADQAbwwAAAEAGwACAAkJJBdLFgCrAQloDAAABABDAGkMAAADADsAawwAAAIAOQBqDAAAAgBaAGwMAAACACcAbQwAAAIAUgDqDAAABABXAG4MAAACADQAbwwAAAEAGwABAAQJKRAhZgCkAARoDAAAAQAiAGsMAAABADMAagwAAAEAHQBsDAAAAQAmAAAA.',
Bc='Bcrogue:BAAALgADCgEJAQABLgAECgcJGwANADIfAA==.Bcwarrior:BAAALgAECgYJCQABLgAECgcJGwANADIfAA==.',
Be='Belgrove:BAAALgADCgEJAQAAAA==.',
Bh='Bheap:BAAALgADCgcJCgAAAA==.',
Bi='Bigbaauls:BAAALgAECgYJCQAAAA==.',
Bj='Björk:BAAALgAECgUJBQABLgAECgYJEwAOAAAAAA==.',
Bl='Blizzaga:BAAALgAECgYJDgAAAA==.',
Bo='Boiardi:BAAALgAECgYJCgAAAA==.Bootowsky:BAAALgAECgQJBAAAAA==.Boromen:BAAALgADCgEJAQAAAA==.Boutros:BAAALgADCgYJBgAAAA==.Bowberto:BAAALgAECgEJAwAAAA==.',
Br='Brea:BAAALgADCgEJAQAAAA==.Briélle:BAAALgADCgMJAwAAAA==.Brocephus:BAAALgAECgYJDwAAAA==.',
Bu='Burrgold:BAAALgAECggJDgAAAA==.',
Ca='Cadya:BAAALgAECgYJCQABLgAFFAMJBQAPAN4IAA==.',
Ce='Celticwoman:BAABLgAECn8jAAMQAAcJywk9iwAYAQdoDAAABgAZAGkMAAAGACIAawwAAAYAFgBqDAAABQA3AGwMAAAFACwAbQwAAAEACQDqDAAABgAOABAABwnLCT2LABgBB2gMAAAEABkAaQwAAAQAIgBrDAAABAAWAGoMAAAEADcAbAwAAAUALABtDAAAAQAJAOoMAAAEAA4AEQAFCckEeTsAxgAFaAwAAAIAEgBpDAAAAgAKAGsMAAACAAkAagwAAAEADQDqDAAAAgAKAAAA.',
Ch='Champina:BAAALgAECgYJCQAAAA==.Chaoticelf:BAAALgADCgcJBwAAAA==.Chickenugget:BAABLgAECn8rAAISAAgJvgbFBgAUAQhoDAAABwAOAGkMAAAHAA4AawwAAAcADQBqDAAABQAPAGwMAAAGAA0AbQwAAAMAGwDqDAAABgAcAG4MAAACAAgAEgAICb4GxQYAFAEIaAwAAAcADgBpDAAABwAOAGsMAAAHAA0AagwAAAUADwBsDAAABgANAG0MAAADABsA6gwAAAYAHABuDAAAAgAIAAAA.Choral:BAAALgAECgMJBQAAAA==.Chubzilla:BAAALgADCgUJBQAAAA==.Chuckwagaon:BAAALgAECgEJAQAAAA==.',
Ci='Cinderdorla:BAABLgAFFH8FAAITAAIJGCJ/NQDEAAJoDAAAAgBQAOoMAAADAF4AEwACCRgifzUAxAACaAwAAAIAUADqDAAAAwBeAAEuAAUUAwkOAAcAoB8A.',
Cl='Clockie:BAACLgAFFH8WAAMEAAQJWiIyBwDeAARoDAAACQBhAGkMAAAEAGIAawwAAAEAOgDqDAAACABhABAAAwnOILlJAB4BA2gMAAAJAGEAawwAAAEAOgDqDAAABwBgAAQAAglbJjIHAN4AAmkMAAAEAGIA6gwAAAEAYQAuAAQKfzsABAQACQneJNoFAAYCABAABwkJJKYhAE4CAAQABglTJdoFAAYCABEABAkKH7MjADsBAAAA.Clõüd:BAABLgAECn8bAAIHAAgJhA9SdQBmAQhoDAAABAAmAGkMAAAEACgAawwAAAQAMABqDAAABAAqAGwMAAAEADcAbQwAAAIAEQDqDAAABAAoAG4MAAABACYABwAICYQPUnUAZgEIaAwAAAQAJgBpDAAABAAoAGsMAAAEADAAagwAAAQAKgBsDAAABAA3AG0MAAACABEA6gwAAAQAKABuDAAAAQAmAAEuAAUUBgkSAAwAiAwA.',
Co='Coldarc:BAAALgADCgYJBgAAAA==.',
Cu='Cuitlahuac:BAAALgAECgEJAwAAAA==.Cupra:BAAALgADCgUJBQAAAA==.',
Cy='Cynthigosa:BAAALgADCgEJAQAAAA==.',
['Cô']='Cônky:BAAALgAECgYJEAAAAA==.',
Da='Dade:BAAALgAECgYJCAAAAA==.Dadeleviathn:BAAALgADCgEJAQABLgAECgYJCAAOAAAAAA==.Dagrul:BAAALgADCgUJBQAAAA==.Danteangelo:BAAALgAECgEJAQAAAA==.Darrkmann:BAAALgAECgkJEwAAAA==.',
De='Deathrotull:BAAALgADCgUJBwAAAA==.Deathslice:BAAALgADCgMJAwAAAA==.Delita:BAAALgAECgUJDQAAAA==.',
Di='Dietdrkelp:BAAALgADCgUJBQABLgAECgEJAQAOAAAAAA==.Dinkster:BAAALgAECgEJAQAAAA==.',
Dk='Dkcloud:BAABLgAECn8dAAIIAAcJUx+xQADtAQdoDAAABgBTAGkMAAAEAFYAawwAAAQAVABqDAAAAwBIAGwMAAAEAFsAbQwAAAMANQDqDAAABQBSAAgABwlTH7FAAO0BB2gMAAAGAFMAaQwAAAQAVgBrDAAABABUAGoMAAADAEgAbAwAAAQAWwBtDAAAAwA1AOoMAAAFAFIAAS4ABRQGCRIADACIDAA=.',
Do='Donella:BAAALgADCgIJAgAAAA==.Doughboy:BAAALgAECgQJBwAAAA==.',
Dr='Drawinddy:BAAALgAFFAIJAgAAAA==.Drifty:BAAALgAECgYJCwAAAA==.',
Du='Duoduo:BAABLgAFFH8MAAIUAAIJMyEKFQDGAAJoDAAABgBcAOoMAAAGAE0AFAACCTMhChUAxgACaAwAAAYAXADqDAAABgBNAAEuAAUUAwkOAAcAoB8A.Duoduomoney:BAABLgAFFH8HAAMBAAIJSBukNACkAAJoDAAABABUAOoMAAADADYAAQACCUgbpDQApAACaAwAAAIAVADqDAAAAQA2ABUAAgnjDo8qAHwAAmgMAAACACUA6gwAAAIAJgABLgAFFAMJDgAHAKAfAA==.',
['Dø']='Dønut:BAAALgADCgUJBQAAAA==.',
Eb='Eboncelest:BAABLgAFFH8MAAIWAAMJlhV1HADnAANoDAAABwBKAGkMAAABADoA6gwAAAQAIAAWAAMJlhV1HADnAANoDAAABwBKAGkMAAABADoA6gwAAAQAIAABLgAFFAQJFgAEAFoiAA==.',
Ec='Eclesiastes:BAAALgAECgEJAQAAAA==.',
El='Eldarcirdan:BAABLgAECn8YAAITAAgJvQdrXQAKAQhoDAAABAAYAGkMAAADAA8AawwAAAMAFABqDAAAAgAMAGwMAAACAAkAbQwAAAIACADqDAAABQAlAG4MAAADAB0AEwAICb0Ha10ACgEIaAwAAAQAGABpDAAAAwAPAGsMAAADABQAagwAAAIADABsDAAAAgAJAG0MAAACAAgA6gwAAAUAJQBuDAAAAwAdAAAA.',
Es='Esme:BAAALgADCgkJDwAAAA==.',
Et='Etrigon:BAAALgAECgEJAQAAAA==.',
Ev='Evajoh:BAAALgADCgUJBQAAAA==.',
Ex='Executioner:BAAALgADCgcJDwAAAA==.',
Fa='Fartstink:BAAALgADCgYJBwAAAA==.',
Fe='Festuss:BAAALgAECgQJDgAAAA==.',
Fi='Fingrwaglr:BAABLgAECn8gAAIXAAYJkwqIEADsAAZoDAAABgAuAGkMAAAGABcAawwAAAYAGABqDAAABQAiAGwMAAADABUA6gwAAAYAEgAXAAYJkwqIEADsAAZoDAAABgAuAGkMAAAGABcAawwAAAYAGABqDAAABQAiAGwMAAADABUA6gwAAAYAEgAAAA==.Fintan:BAAALgADCgMJAwAAAA==.Fizzlebliss:BAAALgADCgYJBgAAAA==.',
Fo='Forlin:BAAALgADCggJEQAAAA==.',
Fr='Frostlowe:BAAALgAECggJCgAAAA==.',
Fu='Fuzziestbutt:BAAALgADCgMJAwAAAA==.',
['Fú']='Fúsion:BAEALgAECgMJCQABLgAECgkJMwAPAHoiAA==.',
Ga='Gambokni:BAAALgADCgcJFAAAAA==.Gamebread:BAAALgAECgUJCAAAAA==.',
Gi='Giganate:BAAALgADCgEJAQABLgAECgQJBAAOAAAAAA==.Gixx:BAAALgAECgYJEAABLgAECggJIAAHAM8UAA==.',
Gl='Glorr:BAAALgAECgEJAQAAAA==.',
Go='Gonamanar:BAAALgAECgcJBQAAAA==.Goth:BAAALgADCgEJAQAAAA==.Gourge:BAAALgAECgkJDwAAAA==.',
Gr='Grimfall:BAABLgAECn8sAAQYAAgJ7hyzEQAPAghoDAAACABNAGkMAAAHAFQAawwAAAcAWABqDAAABgBLAGwMAAAFADYAbQwAAAIAMADqDAAABwBcAG4MAAACAEcAGAAICTQbsxEADwIIaAwAAAQATABpDAAABABFAGsMAAAEAEkAagwAAAQAMgBsDAAABAA2AG0MAAACADAA6gwAAAQAXABuDAAAAgBHAAsABQlyHttAAKwBBWgMAAABAE0AaQwAAAIAVABrDAAAAgBYAGoMAAACAEsA6gwAAAEAPQAZAAUJLBNOTwASAQVoDAAAAwA7AGkMAAABADYAawwAAAEALwBsDAAAAQAcAOoMAAACADYAAAA=.Grimtyr:BAAALgAECgEJAQAAAA==.Grëëdo:BAABLgAECn8gAAMHAAgJzxTdYQCRAQhoDAAABQA9AGkMAAAHAEcAawwAAAQAOgBqDAAABABRAGwMAAADADsAbQwAAAEAFgDqDAAABgA6AG4MAAACACgABwAICc8U3WEAkQEIaAwAAAUAPQBpDAAABgBHAGsMAAADADoAagwAAAMAUQBsDAAAAwA7AG0MAAABABYA6gwAAAYAOgBuDAAAAgAoAAMAAwkzBfxDADwAA2kMAAABABQAawwAAAEABgBqDAAAAQAKAAAA.',
Gy='Gylvi:BAAALgADCgMJAwABLgAECgYJHgAKAGARAA==.',
Ha='Hastor:BAAALgADCgcJBwAAAA==.',
He='Hellgrazer:BAAALgAECgUJCAAAAA==.',
Hi='Highlowe:BAAALgAECgUJBQAAAA==.Hikiru:BAAALgADCgkJJAAAAA==.',
Ho='Hollowbane:BAABLgAECn8oAAMaAAkJdxjrDQAwAgloDAAABgA6AGkMAAAGAEIAawwAAAUANABqDAAABABSAGwMAAAFADsAbQwAAAQAQQDqDAAABQBMAG4MAAAEACQAbwwAAAEAVQAaAAkJdxjrDQAwAgloDAAABAA6AGkMAAAEAEIAawwAAAQANABqDAAABABSAGwMAAAFADsAbQwAAAQAQQDqDAAABQBMAG4MAAAEACQAbwwAAAEAVQAbAAMJpBaBFADJAANoDAAAAgA6AGkMAAACAD8AawwAAAEAMwAAAA==.Holydh:BAAALgAECgIJAgAAAA==.Holydragonn:BAAALgAFFAEJAQAAAA==.Holylock:BAAALgAFFAIJAgAAAA==.Holylordpig:BAAALgAFFAIJAgAAAA==.Holyshaman:BAABLgAFFH8FAAIcAAIJRQUBXwBlAAJoDAAABAAWAOoMAAABAAQAHAACCUUFAV8AZQACaAwAAAQAFgDqDAAAAQAEAAAA.Holywarrior:BAAALgAFFAMJBAAAAA==.Holyymonk:BAAALgAECgEJAgAAAA==.Homdantor:BAAALgAECgUJBQAAAA==.Horse:BAAALgAECgYJBwABLgAFFAgJFwAPACEbAA==.Hotyogafire:BAAALgAECgMJAwAAAA==.',
Ia='Iampally:BAAALgADCggJCQAAAA==.',
Im='Imhim:BAAALgAECgEJAQAAAA==.Imogen:BAAALgAECgcJEgAAAA==.',
Ja='Jadeddruid:BAAALgAECgkJCQAAAA==.Jamieson:BAACLgAFFH8SAAIMAAYJiAy4MwBsAQZoDAAABQA2AGkMAAAEACgAawwAAAIADgBqDAAAAQARAGwMAAABABoA6gwAAAUAFwAMAAYJiAy4MwBsAQZoDAAABQA2AGkMAAAEACgAawwAAAIADgBqDAAAAQARAGwMAAABABoA6gwAAAUAFwAuAAQKfzcAAgwACQn9H/MYABUDAAwACQn9H/MYABUDAAAA.Jand:BAAALgAECgYJDQAAAA==.Jazashi:BAAALgAECgYJFwAAAQ==.',
Jo='Jonesknight:BAABLgAECn8UAAIIAAYJEwajzADTAAZoDAAAAwAHAGkMAAADABEAawwAAAMAEwBqDAAAAgASAGwMAAAEAA0A6gwAAAUAFAAIAAYJEwajzADTAAZoDAAAAwAHAGkMAAADABEAawwAAAMAEwBqDAAAAgASAGwMAAAEAA0A6gwAAAUAFAAAAA==.Jonnytsunami:BAAALgAFFAIJAwAAAA==.',
Ju='Juicycow:BAAALgAECgYJCwAAAA==.',
Ka='Kahoru:BAAALgADCgcJBwAAAA==.Kailler:BAAALgAECgEJAQAAAA==.Kainn:BAAALgAECgYJEAAAAA==.',
Ke='Keg:BAACLgAFFH8hAAIdAAcJgyYDAQCkAgdoDAAABwBkAGkMAAAHAGMAawwAAAUAYQBqDAAABABhAGwMAAABAGEAbQwAAAEAYQDqDAAACABjAB0ABwmDJgMBAKQCB2gMAAAHAGQAaQwAAAcAYwBrDAAABQBhAGoMAAAEAGEAbAwAAAEAYQBtDAAAAQBhAOoMAAAIAGMALgAECn8jAAMdAAgJ0SZLAgB3AwAdAAgJ0SZLAgB3AwAeAAEJVSHYbwBYAAAAAA==.',
Kh='Khakuzu:BAAALgADCgIJAgAAAA==.',
Ki='Kikinak:BAAALgAECgYJCwAAAA==.Killshøt:BAAALgADCgEJAQAAAA==.Kitty:BAACLgAFFH8OAAIfAAQJdgdHFQCwAARoDAAABgAjAGkMAAAEABEAawwAAAEACwDqDAAAAwALAB8ABAl2B0cVALAABGgMAAAGACMAaQwAAAQAEQBrDAAAAQALAOoMAAADAAsALgAECn8ZAAIfAAgJrhE5DwCIAQAfAAgJrhE5DwCIAQAAAA==.Kittyhawk:BAAALgAECggJDwAAAA==.',
Kk='Kk:BAAALgAECgYJEwAAAA==.',
Kl='Klassic:BAAALgAECgQJBgAAAA==.Klixx:BAAALgAECgYJDAAAAA==.',
Ko='Konexx:BAAALgADCgMJAwAAAA==.',
Ks='Kstab:BAABLgAECn8bAAIaAAcJLBuIGgAuAgdoDAAAAwBKAGkMAAAFAEoAawwAAAUAUgBqDAAABAAvAGwMAAABACEA6gwAAAUAOwBuDAAABABcABoABwksG4gaAC4CB2gMAAADAEoAaQwAAAUASgBrDAAABQBSAGoMAAAEAC8AbAwAAAEAIQDqDAAABQA7AG4MAAAEAFwAAAA=.',
Ku='Kuromeow:BAABLgAFFH8HAAIMAAIJYRl9NgC9AAJoDAAAAgAoAOoMAAAFAFkADAACCWEZfTYAvQACaAwAAAIAKADqDAAABQBZAAAA.',
La='Lachasis:BAAALgAECgQJBAAAAA==.Larake:BAABLgAECn8bAAIgAAYJnw7xGAAvAQZoDAAABwAzAGkMAAAFACMAawwAAAUAEQBqDAAABAAYAGwMAAADACIA6gwAAAMAPgAgAAYJnw7xGAAvAQZoDAAABwAzAGkMAAAFACMAawwAAAUAEQBqDAAABAAYAGwMAAADACIA6gwAAAMAPgAAAA==.Lazypie:BAAALgAECgUJBQAAAA==.',
Le='Leggomyaggro:BAAALgAECgMJBQABLgAFFAQJEwANACwmAA==.Lesiania:BAAALgAECgEJAwABLgAECgYJCAAOAAAAAA==.',
Li='Licus:BAAALgADCgkJFAAAAA==.Lightkeeper:BAABLgAECn8kAAMWAAgJShcXGwDOAQhoDAAABgBMAGkMAAAGAEgAawwAAAUANQBqDAAABQAYAGwMAAAEADkAbQwAAAMAMwDqDAAABQBOAG4MAAACABoAFgAICUoXFxsAzgEIaAwAAAUATABpDAAABQBIAGsMAAAEADUAagwAAAUAGABsDAAABAA5AG0MAAADADMA6gwAAAUATgBuDAAAAgAaAAYAAwnvBO9sAHYAA2gMAAABAAMAaQwAAAEADQBrDAAAAQAUAAAA.Lightning:BAAALgADCgEJAQAAAA==.Limpßrisket:BAAALgAECgMJAgAAAA==.Litdealer:BAAALgAECgYJDgABLgAFFAMJCwAdAFcZAA==.Littlestiffy:BAAALgADCgMJAwAAAA==.',
Lr='Lroux:BAAALgAECgcJDwAAAA==.',
Lu='Lucyah:BAAALgAECgYJCgAAAA==.',
Ma='Malkallam:BAAALgADCgUJBQAAAA==.Manaplague:BAAALgAECgUJCwAAAA==.Manenya:BAAALgAECgYJCAAAAA==.Marotto:BAAALgAECgMJAwAAAA==.Massacar:BAABLgAECn8YAAIPAAYJSgo5igAPAQZoDAAABQArAGkMAAAFACoAawwAAAUAEgBqDAAABAAoAGwMAAACAA4A6gwAAAMADQAPAAYJSgo5igAPAQZoDAAABQArAGkMAAAFACoAawwAAAUAEgBqDAAABAAoAGwMAAACAA4A6gwAAAMADQABLgAECggJIAAHAM8UAA==.',
Me='Meatpuller:BAAALgADCgkJDwAAAA==.Menion:BAABLgAECn8cAAMHAAkJZhuLJgCMAgloDAAABABWAGkMAAAEAF0AawwAAAQAWABqDAAABABQAGwMAAADAD8AbQwAAAEAJQDqDAAABABUAG4MAAADAEQAbwwAAAEAJgAHAAkJZhuLJgCMAgloDAAAAwBWAGkMAAADAF0AawwAAAMAWABqDAAAAwBQAGwMAAACAD8AbQwAAAEAJQDqDAAABABUAG4MAAADAEQAbwwAAAEAJgADAAUJQgyHLQCZAAVoDAAAAQAeAGkMAAABAAsAawwAAAEAMwBqDAAAAQAUAGwMAAABACAAAAA=.Meowmeowmeow:BAAALgADCgcJBwABLgAFFAcJIAAIABwfAA==.Mercadius:BAAALgAECgYJEAAAAA==.Metalx:BAAALgADCgkJFQAAAA==.',
Mi='Minkyu:BAAALgAECgQJCAAAAA==.Misha:BAAALgADCgEJAQAAAA==.',
Mk='Mk:BAEALgAECgcJEQABLgAECggJPQAeAGsjAA==.',
Mo='Monkpig:BAACLgAFFH8QAAIdAAMJNh7pJwD1AANoDAAABwBLAGkMAAADAEwA6gwAAAYAUAAdAAMJNh7pJwD1AANoDAAABwBLAGkMAAADAEwA6gwAAAYAUAAuAAQKfyoAAh0ACQntHy0MAF8CAB0ACQntHy0MAF8CAAAA.Mooinator:BAAALgADCgYJBgAAAA==.',
My='Myrai:BAAALgADCgEJAQAAAA==.',
Na='Nanashi:BAABLgAECn8YAAIKAAYJTRXOJgAbAQZoDAAABgA2AGkMAAAEADEAawwAAAMAOQBqDAAABAAmAGwMAAAEAD0A6gwAAAMAMQAKAAYJTRXOJgAbAQZoDAAABgA2AGkMAAAEADEAawwAAAMAOQBqDAAABAAmAGwMAAAEAD0A6gwAAAMAMQAAAA==.Nannerz:BAAALgAECgYJEQAAAA==.Natenasty:BAAALgADCgUJBQABLgAECgQJBAAOAAAAAA==.Natenomoney:BAAALgAECgQJBAAAAA==.Nathan:BAAALgAECgMJAwABLgAECgQJBAAOAAAAAA==.',
Nd='Ndeh:BAAALgAFFAEJAQAAAA==.',
Ne='Nena:BAAALgAECgEJAQAAAA==.Nermonhunder:BAAALgAECgQJCAAAAA==.',
Ni='Ninjitsû:BAABLgAECn8aAAIPAAgJuBziHQCeAghoDAAABABLAGkMAAAEAEcAawwAAAQAPwBqDAAABABaAGwMAAADAFgAbQwAAAEAMgDqDAAABABTAG4MAAACAFIADwAICbgc4h0AngIIaAwAAAQASwBpDAAABABHAGsMAAAEAD8AagwAAAQAWgBsDAAAAwBYAG0MAAABADIA6gwAAAQAUwBuDAAAAgBSAAAA.',
Ol='Oldspice:BAAALgAECgMJBAAAAA==.Olex:BAAALgAECgUJBQAAAA==.',
Om='Omgkangel:BAABLgAECn8VAAINAAYJnBa6HABlAQZoDAAABAAzAGkMAAAEADcAawwAAAQASABqDAAAAwBAAGwMAAACACoA6gwAAAQAQgANAAYJnBa6HABlAQZoDAAABAAzAGkMAAAEADcAawwAAAQASABqDAAAAwBAAGwMAAACACoA6gwAAAQAQgAAAA==.Omi:BAAALgADCgYJBgAAAA==.Omie:BAAALgAECgEJBAAAAA==.',
On='Onoos:BAAALgAECgMJBgAAAA==.',
Ov='Overpower:BAAALgADCgIJAgABLgAECgkJKwAIAMgUAA==.Ovix:BAAALgADCgMJAQABLgAECgUJDAAOAAAAAA==.',
Ow='Ow:BAAALgADCgEJAQAAAA==.',
Pa='Paulos:BAAALgAECgUJCQAAAA==.',
Pe='Peaf:BAABLgAECn8gAAMBAAYJlyAaLQCJAQZoDAAABgBiAGkMAAAGAEAAawwAAAYAXwBqDAAABQBSAGwMAAADAFMA6gwAAAYASwABAAYJlyAaLQCJAQZoDAAABQBiAGkMAAAFAEAAawwAAAYAXwBqDAAABABSAGwMAAADAFMA6gwAAAUASwACAAQJnAu4OgBtAARoDAAAAQAbAGkMAAABABkAagwAAAEAEwDqDAAAAQAkAAAA.Petesfeets:BAAALgADCgYJCAAAAA==.',
Pl='Playajizoe:BAAALgAECgQJBwAAAA==.',
Po='Pocketsnacks:BAAALgADCgEJAQAAAA==.Poppabanger:BAAALgAECgQJBwAAAA==.',
Qu='Quill:BAABLgAECn8eAAIIAAcJrB1CSwARAgdoDAAABgBYAGkMAAAFAEoAawwAAAUAPABqDAAABQBRAGwMAAADAEYAbQwAAAEAYADqDAAABQBCAAgABwmsHUJLABECB2gMAAAGAFgAaQwAAAUASgBrDAAABQA8AGoMAAAFAFEAbAwAAAMARgBtDAAAAQBgAOoMAAAFAEIAAS4ABRQDCQQADgAAAAA=.',
Ra='Raythe:BAABLgAECn8hAAIKAAcJ6BWiHwBUAQdoDAAABQBFAGkMAAAHAE0AawwAAAUAPQBqDAAABAAXAGwMAAADACwAbQwAAAEAFADqDAAACAA+AAoABwnoFaIfAFQBB2gMAAAFAEUAaQwAAAcATQBrDAAABQA9AGoMAAAEABcAbAwAAAMALABtDAAAAQAUAOoMAAAIAD4AAAA=.Razzeman:BAAALgAECgEJAQAAAA==.Razzledazzl:BAAALgAECgEJAQAAAA==.',
Ro='Rose:BAAALgAECgcJCgABLgAFFAQJDgAfAHYHAA==.',
Ru='Ruck:BAAALgAECgcJDQABLgAECgkJIQACAIEbAA==.Rucker:BAABLgAECn8hAAMCAAkJgRtiCQBJAgloDAAABgA+AGkMAAAGAFwAawwAAAUAPwBqDAAAAgA2AGwMAAADAFsAbQwAAAIAPgDqDAAABQBdAG4MAAADACcAbwwAAAEAOgACAAkJgRtiCQBJAgloDAAABgA+AGkMAAAGAFwAawwAAAQAPwBqDAAAAgA2AGwMAAADAFsAbQwAAAIAPgDqDAAABQBdAG4MAAADACcAbwwAAAEAOgABAAEJWAIVtQAdAAFrDAAAAQAGAAAA.Ruckkin:BAAALgAECgMJBgABLgAECgkJIQACAIEbAA==.Rucksy:BAABLgAECn8oAAMDAAgJoB0RBQCrAghoDAAABwBcAGkMAAAHAGIAawwAAAgAXwBqDAAABQBXAGwMAAAFAEsAbQwAAAEAKADqDAAABQBbAG4MAAACACMAAwAICaAdEQUAqwIIaAwAAAcAXABpDAAABwBiAGsMAAAHAF8AagwAAAQAVwBsDAAABQBLAG0MAAABACgA6gwAAAQAWwBuDAAAAgAjAAcAAwn+Ebf9AJkAA2sMAAABAB4AagwAAAEAOgDqDAAAAQA9AAEuAAQKCQkhAAIAgRsA.Ruckuhs:BAAALgADCgkJDAABLgAECgkJIQACAIEbAA==.Ruxsi:BAAALgAECgUJCAABLgAECgkJIQACAIEbAA==.',
Ry='Ryan:BAABLgAECn8gAAMHAAgJ8h8pJgBQAghoDAAABQBhAGkMAAAFAGEAawwAAAYAXABqDAAABQBhAGwMAAAEAFwAbQwAAAEAGQDqDAAABQBaAG4MAAABAEwABwAHCZwjKSYAUAIHaAwAAAMAYQBpDAAABABhAGsMAAAGAFwAagwAAAEAYQBsDAAAAgBcAOoMAAADAFoAbgwAAAEATAAhAAYJWCJGKgDgAQZoDAAAAgBdAGkMAAABAFUAagwAAAQAXQBsDAAAAgBZAG0MAAABAE0A6gwAAAIAVwAAAA==.',
['Rì']='Rìptide:BAAALgAECgkJEQAAAA==.',
['Rô']='Rôrônoazoro:BAAALgADCgYJCwAAAA==.',
Sa='Saragdan:BAAALgADCgcJCwAAAA==.',
Sc='Scylla:BAAALgAECgYJBgABLgAECgYJDwAOAAAAAA==.',
Se='Seraphae:BAAALgAECgEJAgAAAA==.Sereb:BAAALgAECgQJBQAAAA==.',
Sh='Shadowscurry:BAAALgAECgQJBwAAAA==.Shankzmcgee:BAABLgAECn8cAAIaAAYJcQrMMgDvAAZoDAAABwApAGkMAAAHAB4AawwAAAYAGgBqDAAABAATAGwMAAACABUA6gwAAAIADQAaAAYJcQrMMgDvAAZoDAAABwApAGkMAAAHAB4AawwAAAYAGgBqDAAABAATAGwMAAACABUA6gwAAAIADQABLgAECggJIAAHAM8UAA==.Shardik:BAAALgAECgUJCQAAAA==.Sheero:BAAALgAECgUJBQAAAA==.Sheong:BAAALgAECgkJCwAAAA==.Sheñ:BAAALgADCgkJIAAAAA==.Shindark:BAAALgAECgEJAgAAAA==.Shivah:BAAALgAECgcJCwABLgAFFAMJBAAOAAAAAA==.Shrus:BAAALgAECgYJBgAAAA==.Shrussy:BAAALgADCgMJAwAAAA==.Shèrlock:BAABLgAECn8eAAIQAAkJ8BBeOwDfAQloDAAABAAuAGkMAAAEAC8AawwAAAQAMABqDAAABABDAGwMAAAEADAAbQwAAAMAHADqDAAABABEAG4MAAACAC4AbwwAAAEACwAQAAkJ8BBeOwDfAQloDAAABAAuAGkMAAAEAC8AawwAAAQAMABqDAAABABDAGwMAAAEADAAbQwAAAMAHADqDAAABABEAG4MAAACAC4AbwwAAAEACwAAAA==.',
Si='Silverfox:BAAALgAFFAIJBAABLgAFFAMJDgAHAKAfAA==.',
Sk='Skippydippy:BAAALgAECgQJCwAAAA==.Skye:BAAALgAECgcJBQAAAA==.Skylin:BAAALgAECgEJBAAAAA==.',
Sl='Sleezee:BAAALgAECgQJCQAAAA==.Slushpuppis:BAAALgADCgcJBwAAAA==.',
Sn='Sneeger:BAAALgAECgYJDQAAAA==.',
Sp='Spelldeala:BAAALgAECgYJEAABLgAFFAMJCwAdAFcZAA==.',
St='Stargasm:BAABLgAFFH8FAAIGAAIJqgvbJQBoAAJoDAAAAgAWAGkMAAADACUABgACCaoL2yUAaAACaAwAAAIAFgBpDAAAAwAlAAAA.Stdmachine:BAAALgAECgYJDAAAAA==.Stonedstoner:BAAALgAECgUJCAAAAA==.',
Su='Superdump:BAAALgAECgcJAgAAAA==.',
Sw='Swiftmend:BAABLgAFFH8JAAITAAIJtw6BSwB4AAJoDAAABAAnAOoMAAAFACMAEwACCbcOgUsAeAACaAwAAAQAJwDqDAAABQAjAAEuAAUUAwkLAB0AVxkA.',
Sy='Syllal:BAAALgADCgQJBAAAAA==.Synisttir:BAAALgAECgYJDQAAAA==.',
Ta='Taft:BAABLgAECn8wAAMiAAkJjBNNGQDoAQloDAAABQA9AGkMAAAIAD8AawwAAAcAOwBqDAAABwA5AGwMAAAGACUAbQwAAAQALQDqDAAABQA4AG4MAAAEADEAbwwAAAIAGwAiAAkJjBNNGQDoAQloDAAABQA9AGkMAAAIAD8AawwAAAcAOwBqDAAABwA5AGwMAAAGACUAbQwAAAQALQDqDAAABAA4AG4MAAAEADEAbwwAAAIAGwATAAEJDQyozwAoAAHqDAAAAQAeAAAA.Tardis:BAAALgADCgcJCgAAAA==.Taterz:BAAALgADCgQJBAAAAA==.',
Te='Terrá:BAAALgADCgkJHwAAAA==.Teryn:BAAALgAECgEJAQAAAA==.Tesa:BAAALgADCgMJBQAAAA==.',
Th='Thomassian:BAAALgAECgEJAgAAAA==.',
Ti='Timewing:BAAALgADCggJFAAAAA==.Timtoo:BAAALgAECgMJBQAAAA==.',
To='Toborntwob:BAAALgAECgYJEwAAAA==.',
Tr='Transformer:BAAALgAECgQJBgAAAA==.Triblequest:BAABLgAECn8VAAIjAAYJrRRbNwA9AQZoDAAABQBGAGkMAAAEAEYAawwAAAQANQBqDAAAAwBKAGwMAAABAAcA6gwAAAQAPwAjAAYJrRRbNwA9AQZoDAAABQBGAGkMAAAEAEYAawwAAAQANQBqDAAAAwBKAGwMAAABAAcA6gwAAAQAPwAAAA==.Tritin:BAABLgAECn8VAAIHAAgJmAbLugDwAAhoDAAAAwAVAGkMAAADABIAawwAAAIADwBqDAAAAgATAGwMAAAEABwAbQwAAAEADgDqDAAABQASAG4MAAABAAEABwAICZgGy7oA8AAIaAwAAAMAFQBpDAAAAwASAGsMAAACAA8AagwAAAIAEwBsDAAABAAcAG0MAAABAA4A6gwAAAUAEgBuDAAAAQABAAAA.Trotndot:BAAALgADCgQJBAAAAA==.',
Tu='Tugginmypuda:BAAALgAECgQJBAAAAA==.',
Tw='Twiltock:BAAALgAECgYJDAAAAA==.Twizztyd:BAAALgAECgYJDAAAAA==.Twocups:BAAALgAECgUJCgAAAA==.',
Un='Underware:BAAALgADCgYJBgAAAA==.',
Va='Valessa:BAABLgAECn8sAAIMAAgJ6wWhpwATAQhoDAAABgAPAGkMAAAGABQAawwAAAcABQBqDAAABgAUAGwMAAAHABIAbQwAAAMAEgDqDAAABwAQAG4MAAACAAkADAAICesFoacAEwEIaAwAAAYADwBpDAAABgAUAGsMAAAHAAUAagwAAAYAFABsDAAABwASAG0MAAADABIA6gwAAAcAEABuDAAAAgAJAAAA.Valiria:BAACLgAFFH8FAAIPAAMJlxN6TwDZAANoDAAAAgA/AGkMAAACACQA6gwAAAEAMgAPAAMJlxN6TwDZAANoDAAAAgA/AGkMAAACACQA6gwAAAEAMgAuAAQKfx8AAg8ACQldGaUlACACAA8ACQldGaUlACACAAAA.Varzul:BAAALgADCgYJCwABLgAECgIJAgAOAAAAAA==.',
Ve='Velieda:BAABLgAECn8mAAMHAAgJ0xGjfwBSAQhoDAAABgAoAGkMAAAGAC0AawwAAAYANABqDAAAAwA6AGwMAAAFAD8AbQwAAAIAFgDqDAAABQAkAG4MAAAFADkABwAICQcOo38AUgEIaAwAAAIAJwBpDAAAAgAkAGsMAAACACgAagwAAAEAEgBsDAAAAgAiAG0MAAACABYA6gwAAAIAFABuDAAABQA5AAMABgm3EnsdAA4BBmgMAAAEACgAaQwAAAQALQBrDAAABAA0AGoMAAACADoAbAwAAAMAPwDqDAAAAwAkAAAA.',
Vi='Vindication:BAACLgAFFH8TAAINAAQJLCY5CAC4AQRoDAAABwBiAGkMAAAFAGAAawwAAAIAYgDqDAAABQBhAA0ABAksJjkIALgBBGgMAAAHAGIAaQwAAAUAYABrDAAAAgBiAOoMAAAFAGEALgAECn8jAAINAAgJKCAuBwC9AgANAAgJKCAuBwC9AgAAAA==.Vita:BAAALgAECgYJBwAAAA==.',
Wa='Wackah:BAAALgAECgYJCQAAAA==.Wafflez:BAAALgAECgIJAgAAAA==.Wakana:BAAALgAECgIJAgAAAA==.',
Wi='Windflower:BAAALgADCgQJBAAAAA==.Winteranne:BAAALgAECgEJAQAAAA==.',
Wo='Wolfcarver:BAAALgAECgYJEAAAAA==.Worldbreakèr:BAAALgAECggJAQAAAA==.',
['Wÿ']='Wÿcked:BAAALgAECgUJBQAAAA==.',
Xi='Xiaobao:BAABLgAFFH8FAAIfAAMJJwbmHACAAANoDAAAAgAYAGkMAAABAAQA6gwAAAIAEgAfAAMJJwbmHACAAANoDAAAAgAYAGkMAAABAAQA6gwAAAIAEgAAAA==.Xiaoduoduo:BAACLgAFFH8OAAMHAAMJoB/xRQAEAQNoDAAABgBfAGkMAAACAEAA6gwAAAYAUgAHAAMJoB/xRQAEAQNoDAAABQBfAGkMAAACAEAA6gwAAAYAUgAhAAEJuCN9OgBeAAFoDAAAAQBbAC4ABAp/KgACBwAJCaIjeQ4A2gIABwAJCaIjeQ4A2gIAAAA=.Xiaomak:BAAALgADCgQJBAABLgAFFAMJDgAHAKAfAA==.Xiaoxiongmao:BAAALgADCgcJBwAAAA==.',
Xs='Xschaferr:BAABLgAECn8WAAIHAAcJmAWb2gDDAAdoDAAAAwARAGkMAAADABMAawwAAAMADwBqDAAABAASAGwMAAAFABEAbQwAAAEAAQDqDAAAAwAPAAcABwmYBZvaAMMAB2gMAAADABEAaQwAAAMAEwBrDAAAAwAPAGoMAAAEABIAbAwAAAUAEQBtDAAAAQABAOoMAAADAA8AAAA=.',
Za='Zabz:BAAALgAECgEJAgABLgAECgkJNgAHAMAgAA==.',
Ze='Zeroskills:BAABLgAECn8kAAMaAAkJ/Qd5HwB8AQloDAAABQAdAGkMAAAFACEAawwAAAUAFwBqDAAABAAlAGwMAAADABgAbQwAAAIAAwDqDAAABgAUAG4MAAAEABMAbwwAAAIACQAaAAkJ/Qd5HwB8AQloDAAABAAdAGkMAAAEACEAawwAAAUAFwBqDAAABAAlAGwMAAADABgAbQwAAAIAAwDqDAAABgAUAG4MAAAEABMAbwwAAAIACQAbAAIJSwRkHgBUAAJoDAAAAQAHAGkMAAABAA4AAAA=.',
Zu='Zulinar:BAAALgAECgYJEgAAAA==.Zumoku:BAAALgADCgkJLwAAAA==.',
['Às']='Àsmodeus:BAABLgAECn8vAAQfAAkJwhLwDwDDAQloDAAABwBMAGkMAAAIAC0AawwAAAkALQBqDAAACAAyAGwMAAADADMAbQwAAAEAHADqDAAACABRAG4MAAACACMAbwwAAAEAEwAfAAkJwhLwDwDDAQloDAAABwBMAGkMAAAIAC0AawwAAAgALQBqDAAACAAyAGwMAAADADMAbQwAAAEAHADqDAAABwBRAG4MAAACACMAbwwAAAEAEwAiAAEJ8gZxiQAnAAFrDAAAAQARABMAAQkxCt3SACYAAeoMAAABABoAAAA=.',
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
