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

local lookup = {'Rogue-Subtlety','Evoker-Augmentation','Shaman-Elemental','Paladin-Holy','Warlock-Demonology','Hunter-Survival','Hunter-BeastMastery','Monk-Mistweaver','DeathKnight-Unholy','DeathKnight-Frost','Druid-Restoration','Druid-Feral','Shaman-Restoration','Warrior-Arms','Warrior-Fury','Evoker-Devastation','Evoker-Preservation','Priest-Holy','Druid-Guardian','Monk-Windwalker','DeathKnight-Blood','Hunter-Marksmanship','Unknown-Unknown','Priest-Shadow','Paladin-Protection','Paladin-Retribution','DemonHunter-Havoc','Shaman-Enhancement','Druid-Balance','Warlock-Destruction','Mage-Frost','Monk-Brewmaster','Rogue-Outlaw','Rogue-Assassination','Warrior-Protection','Warlock-Affliction',}
local provider = {region='US',realm='TheScryers',name='US',type='daily',zone=46,date='2026-05-12',data={Ae='Aelin:BAAALgAECgYJBwAAAA==.',
Ai='Airo:BAABLgAECn8wAAIBAAkJQxcUCAA0AgloDAAACABXAGkMAAAGAD4AawwAAAYAPgBqDAAABAA/AGwMAAAHAC4AbQwAAAQAVgDqDAAACQA6AG4MAAADACsAbwwAAAEAHQABAAkJQxcUCAA0AgloDAAACABXAGkMAAAGAD4AawwAAAYAPgBqDAAABAA/AGwMAAAHAC4AbQwAAAQAVgDqDAAACQA6AG4MAAADACsAbwwAAAEAHQAAAA==.',
Ak='Akaris:BAABLgAECn8WAAICAAYJXwXLOwDEAAZoDAAABQAJAGkMAAAEAA4AawwAAAQAFgBqDAAAAwALAGwMAAACAAwA6gwAAAQACQACAAYJXwXLOwDEAAZoDAAABQAJAGkMAAAEAA4AawwAAAQAFgBqDAAAAwALAGwMAAACAAwA6gwAAAQACQAAAA==.',
Al='Alainea:BAABLgAECn8VAAIDAAgJbgUILgARAQhoDAAABAAOAGkMAAADAA8AawwAAAMABgBqDAAAAgAMAGwMAAACABcAbQwAAAIACQDqDAAAAgAQAG4MAAADAAsAAwAICW4FCC4AEQEIaAwAAAQADgBpDAAAAwAPAGsMAAADAAYAagwAAAIADABsDAAAAgAXAG0MAAACAAkA6gwAAAIAEABuDAAAAwALAAAA.Alispia:BAAALgADCgUJBQAAAA==.',
Am='Amaterasu:BAABLgAFFH8JAAIEAAMJViBYFgAPAQNoDAAAAwBWAGkMAAADAFsA6gwAAAMARwAEAAMJViBYFgAPAQNoDAAAAwBWAGkMAAADAFsA6gwAAAMARwABLgAFFAMJCQAEAFYgAA==.Ambre:BAAALgAECgcJDQAAAA==.Amerdro:BAAALgAECgQJCQAAAA==.Amoreesa:BAAALgAECgQJBAAAAA==.',
An='Andross:BAAALgADCgcJEgABLgAECgcJGwAFAHQHAA==.Angrytestie:BAAALgAECgUJBQAAAA==.Anomaly:BAABLgAECn8sAAMGAAgJJSLzBACDAghoDAAABwBbAGkMAAAGAGAAawwAAAYAVgBqDAAABwBiAGwMAAAGAE8AbQwAAAIASADqDAAACABYAG4MAAACAGAABgAICSUi8wQAgwIIaAwAAAcAWwBpDAAABQBgAGsMAAAGAFYAagwAAAcAYgBsDAAABgBPAG0MAAACAEgA6gwAAAcAWABuDAAAAgBgAAcAAgl2Dja5AFAAAmkMAAABAAMA6gwAAAEARgAAAA==.Anthousai:BAAALgADCgQJBAAAAA==.',
Ar='Ara:BAABLgAFFH8MAAIIAAYJARqAAwC7AQZoDAAAAgA8AGkMAAACAEsAawwAAAIAUgBqDAAAAQA+AGwMAAABACUA6gwAAAQAUgAIAAYJARqAAwC7AQZoDAAAAgA8AGkMAAACAEsAawwAAAIAUgBqDAAAAQA+AGwMAAABACUA6gwAAAQAUgAAAA==.',
As='Asylum:BAAALgADCgcJDQAAAA==.',
Au='Aura:BAAALgAECgMJAwAAAA==.',
Ax='Axl:BAABLgAECn8WAAMJAAYJ7gbzhgDqAAZoDAAABQAMAGkMAAAEABcAawwAAAQAEgBqDAAAAwAOAGwMAAACABEA6gwAAAQAEAAJAAYJ7gbzhgDqAAZoDAAABAAMAGkMAAAEABcAawwAAAQAEgBqDAAAAwAOAGwMAAACABEA6gwAAAQAEAAKAAEJ8QF2GgAhAAFoDAAAAQAEAAAA.',
Ay='Aylíth:BAAALgAFFAEJAQABLgAFFAMJCQAEAFYgAA==.',
Ba='Bacon:BAAALgADCgkJCQAAAA==.Bahdeeps:BAAALgAECgEJAQAAAA==.Bahheals:BAABLgAECn8UAAMLAAcJzgQ1YAC1AAdoDAAAAwAZAGkMAAADAA0AawwAAAMABABqDAAAAgAEAGwMAAADAAYAbQwAAAEABADqDAAABQAaAAsABwnOBDVgALUAB2gMAAACABkAaQwAAAIADQBrDAAAAgAEAGoMAAACAAQAbAwAAAIABgBtDAAAAQAEAOoMAAAEABoADAAFCYUBKCAAeAAFaAwAAAEABABpDAAAAQAIAGsMAAABAAAAbAwAAAEAAADqDAAAAQAFAAAA.Banjoo:BAABLgAECn8aAAILAAgJfBtLGwAAAghoDAAABAA8AGkMAAADAFAAawwAAAMAUgBqDAAAAwBDAGwMAAADAEoAbQwAAAMANwDqDAAABABMAG4MAAADAEIACwAICXwbSxsAAAIIaAwAAAQAPABpDAAAAwBQAGsMAAADAFIAagwAAAMAQwBsDAAAAwBKAG0MAAADADcA6gwAAAQATABuDAAAAwBCAAAA.Baruk:BAABLgAECn8cAAINAAgJ8BP2KgCIAQhoDAAABQAyAGkMAAAEADsAawwAAAQAQwBqDAAAAwBLAGwMAAAFADwAbQwAAAEAAgDqDAAABABFAG4MAAACABYADQAICfAT9ioAiAEIaAwAAAUAMgBpDAAABAA7AGsMAAAEAEMAagwAAAMASwBsDAAABQA8AG0MAAABAAIA6gwAAAQARQBuDAAAAgAWAAAA.',
Be='Beauzericka:BAAALgADCgEJAQAAAA==.Beeswax:BAAALgADCgkJCQAAAA==.',
Bi='Bigçhungi:BAABLgAECn8YAAMOAAgJAx/sBgALAghoDAAAAwBGAGkMAAAEAFAAawwAAAQAUgBqDAAABABdAGwMAAAEAFkAbQwAAAEAQgDqDAAAAwBUAG4MAAABAFEADgAHCdId7AYACwIHaAwAAAEAJwBpDAAAAQBQAGsMAAABAFIAagwAAAEAXQBsDAAAAQBZAOoMAAABAFQAbgwAAAEAUQAPAAcJlRcVHACWAQdoDAAAAgBGAGkMAAADAC8AawwAAAMARwBqDAAAAwA6AGwMAAADAD0AbQwAAAEAQgDqDAAAAgAsAAEuAAUUBQkUAAkA4iEA.',
Bl='Blitzen:BAABLgAECn8lAAMQAAkJ3Bq8AQBxAgloDAAABQBBAGkMAAAFAEQAawwAAAYASQBqDAAABABjAGwMAAAEAFIAbQwAAAMARgDqDAAABAA2AG4MAAAEAEAAbwwAAAIARgAQAAkJ3Bq8AQBxAgloDAAABQBBAGkMAAAFAEQAawwAAAUASQBqDAAABABjAGwMAAAEAFIAbQwAAAMARgDqDAAABAA2AG4MAAAEAEAAbwwAAAIARgARAAEJswRPSwArAAFrDAAAAQAMAAAA.',
Bo='Borealiss:BAAALgAECgYJBwABLgAECgkJJQAQANwaAA==.',
Br='Brewjigsaw:BAAALgADCgcJCgAAAA==.',
Bu='Buffsubordie:BAAALgAFFAEJAQAAAA==.',
Bw='Bwonsamdi:BAABLgAECn9EAAIDAAgJhCATDwC2AghoDAAACgBeAGkMAAAKAFcAawwAAAoAWABqDAAACgBSAGwMAAAIAGAAbQwAAAQAQgDqDAAADABaAG4MAAAEADsAAwAICYQgEw8AtgIIaAwAAAoAXgBpDAAACgBXAGsMAAAKAFgAagwAAAoAUgBsDAAACABgAG0MAAAEAEIA6gwAAAwAWgBuDAAABAA7AAAA.',
['Bâ']='Bârks:BAABLgAECn8bAAISAAcJix5ECwBHAgdoDAAABgBbAGkMAAAFAFUAawwAAAUAUwBqDAAAAwBaAGwMAAACAEgA6gwAAAUARgBuDAAAAQA1ABIABwmLHkQLAEcCB2gMAAAGAFsAaQwAAAUAVQBrDAAABQBTAGoMAAADAFoAbAwAAAIASADqDAAABQBGAG4MAAABADUAAAA=.',
Ca='Callia:BAAALgAECgcJBwAAAA==.Camazotz:BAAALgADCgUJBQAAAA==.Cardkun:BAAALgADCgIJAgAAAA==.Carp:BAABLgAECn8aAAITAAYJKgqEHQCgAAZoDAAABQANAGkMAAAFABkAawwAAAUAHABqDAAABAAmAGwMAAACACcA6gwAAAUAGAATAAYJKgqEHQCgAAZoDAAABQANAGkMAAAFABkAawwAAAUAHABqDAAABAAmAGwMAAACACcA6gwAAAUAGAAAAA==.',
Ch='Chargerkun:BAAALgAECgMJCwAAAA==.Chayda:BAAALgADCgEJAQAAAA==.Choleena:BAABLgAECn8bAAINAAcJ5BU9IgC+AQdoDAAABgBJAGkMAAAFAEAAawwAAAUALQBqDAAAAwBQAGwMAAACAD4A6gwAAAUANABuDAAAAQAMAA0ABwnkFT0iAL4BB2gMAAAGAEkAaQwAAAUAQABrDAAABQAtAGoMAAADAFAAbAwAAAIAPgDqDAAABQA0AG4MAAABAAwAAAA=.',
Ci='Cindress:BAAALgADCgEJAQAAAA==.',
Co='Combat:BAAALgAECgYJDwAAAA==.Coojotwo:BAAALgAECgUJDAAAAA==.',
Cr='Crewd:BAAALgADCgEJAQAAAA==.Crimzon:BAAALgAECgEJAQAAAA==.',
Da='Dangerfloof:BAAALgADCgQJCAAAAA==.Dangerwithin:BAACLgAFFH8jAAMUAAgJpCMlAACqAghoDAAABgBjAGkMAAAGAGMAawwAAAYAXwBqDAAABABjAGwMAAADAE0AbQwAAAIAQgDqDAAABwBkAG4MAAABAGMAFAAHCYUkJQAAqgIHaAwAAAYAYwBpDAAABgBjAGsMAAAGAF8AagwAAAQAYwBtDAAAAgBCAOoMAAAHAGQAbgwAAAEAYwAIAAEJrh34JwBYAAFsDAAAAwBLAC4ABAp/JgACFAAJCcomMwAA+wMAFAAJCcomMwAA+wMAAS4ABRQDCQkABABWIAA=.Danklazercat:BAAALgADCgcJDgABLgAFFAUJFAAJAOIhAA==.Darius:BAABLgAFFH8FAAIVAAMJ6gyIFgC3AANoDAAAAQAbAGkMAAACACYA6gwAAAIAIAAVAAMJ6gyIFgC3AANoDAAAAQAbAGkMAAACACYA6gwAAAIAIAAAAA==.Dastraz:BAAALgAECgYJDgAAAA==.',
De='Decay:BAAALgAECgMJAwAAAA==.Deebz:BAABLgAECn8aAAMHAAcJqRgTLwCmAQdoDAAABQBOAGkMAAAFAEoAawwAAAUAQQBqDAAAAwBAAGwMAAACAEcA6gwAAAUARABuDAAAAQAUAAcABwn8FhMvAKYBB2gMAAABAE4AaQwAAAEASgBrDAAAAQBBAGoMAAACADkAbAwAAAEALgDqDAAAAQBEAG4MAAABABQAFgAGCUMYyQoAVAEGaAwAAAQAOABpDAAABABFAGsMAAAEAC8AagwAAAEAQABsDAAAAQBHAOoMAAAEAEEAAAA=.Devkra:BAAALgADCggJDgAAAA==.',
Dm='Dmgabsorb:BAAALgADCgIJAgAAAA==.',
Do='Doge:BAAALgADCgkJCQAAAA==.',
Dr='Dragoneux:BAAALgAFFAIJAwAAAQ==.',
Du='Dudemachine:BAAALgADCgUJBQABLgADCgkJEwAXAAAAAA==.',
['Dè']='Dèèbz:BAAALgADCgQJBgAAAA==.',
['Dö']='Dörf:BAAALgADCgMJAwAAAA==.',
Ed='Eddison:BAAALgADCgkJCQAAAA==.',
En='Enchanted:BAABLgAECn8XAAMVAAcJgBibGQAUAQdoDAAABQA4AGkMAAAEADgAawwAAAQAPABqDAAAAwA5AGwMAAADAEQA6gwAAAMASABuDAAAAQA+ABUABgnqFJsZABQBBmgMAAADAB4AaQwAAAMANwBrDAAAAwA8AGoMAAADADkAbAwAAAIARADqDAAAAgA0AAkABgkkFnuMAN8ABmgMAAACADgAaQwAAAEAOABrDAAAAQAxAGwMAAABACoA6gwAAAEASABuDAAAAQA+AAAA.Enid:BAACLgAFFH8mAAIVAAcJPCYKAAAFAwdoDAAABgBkAGkMAAAGAGMAawwAAAYAYwBqDAAABwBjAGwMAAAFAGEAbQwAAAEAWgDqDAAABwBjABUABwk8JgoAAAUDB2gMAAAGAGQAaQwAAAYAYwBrDAAABgBjAGoMAAAHAGMAbAwAAAUAYQBtDAAAAQBaAOoMAAAHAGMALgAECn8ZAAIVAAgJqSZZAQB+AwAVAAgJqSZZAQB+AwAAAA==.',
Es='Eskanor:BAAALgADCgQJBgAAAA==.',
Et='Eternalwrath:BAAALgAECgcJDQAAAA==.',
Eu='Eublar:BAAALgAECgEJAQAAAA==.',
Fa='Falzemphx:BAAALgAECgMJBgAAAA==.Farbringer:BAAALgAECgUJBgABLgAECgYJDgAXAAAAAA==.Fayanna:BAAALgADCgEJAQAAAA==.',
Fe='Felicitee:BAAALgAECgMJAwAAAA==.',
Fo='Foxxylady:BAABLgAECn8dAAIHAAcJZx6YJgDNAQdoDAAABgBcAGkMAAAFAF8AawwAAAYAUABqDAAAAwBfAGwMAAABAEsA6gwAAAcAPQBuDAAAAQA9AAcABwlnHpgmAM0BB2gMAAAGAFwAaQwAAAUAXwBrDAAABgBQAGoMAAADAF8AbAwAAAEASwDqDAAABwA9AG4MAAABAD0AAAA=.',
Fu='Furbees:BAAALgAECgUJEAAAAA==.',
Ge='Geenon:BAAALgAECgMJBgAAAA==.Gephen:BAAALgADCgUJBQAAAA==.',
Gr='Grakdeez:BAAALgAECgUJBwABLgAECgkJEAAXAAAAAA==.Grakfist:BAAALgAECgkJEAAAAA==.Graubard:BAAALgAECgEJAQAAAA==.Gravec:BAAALgADCgEJAQAAAA==.Grimswhisper:BAAALgAECgYJDQAAAA==.Gritchen:BAABLgAECn8YAAMSAAYJYR16EgDiAQZoDAAAAwBLAGkMAAAFAFEAawwAAAQAPQBqDAAAAwBdAGwMAAADAEIA6gwAAAYASQASAAYJYR16EgDiAQZoDAAAAwBLAGkMAAAFAFEAawwAAAMAPQBqDAAAAgBdAGwMAAACAEIA6gwAAAYASQAYAAMJNAIcWwAzAANrDAAAAQAIAGoMAAABAA0AbAwAAAEAAgAAAA==.Growler:BAAALgAECgYJEAAAAA==.Grynsel:BAABLgAECn8bAAIHAAcJ6A0wRQBSAQdoDAAABgAmAGkMAAAFAC0AawwAAAUAHwBqDAAAAwBBAGwMAAACADoA6gwAAAUAIgBuDAAAAQAFAAcABwnoDTBFAFIBB2gMAAAGACYAaQwAAAUALQBrDAAABQAfAGoMAAADAEEAbAwAAAIAOgDqDAAABQAiAG4MAAABAAUAAAA=.',
Ha='Harlynne:BAAALgADCgkJCQAAAA==.',
Ho='Holios:BAAALgADCgYJBgABLgAECgcJGwAYAL0KAA==.',
Hu='Huntwix:BAAALgADCgYJBgAAAA==.',
Id='Idontknow:BAABLgAECn8bAAIYAAcJvQoJJAA4AQdoDAAABQAxAGkMAAAGACQAawwAAAYAIABqDAAABAAZAGwMAAADABMA6gwAAAIAEwBuDAAAAQAIABgABwm9CgkkADgBB2gMAAAFADEAaQwAAAYAJABrDAAABgAgAGoMAAAEABkAbAwAAAMAEwDqDAAAAgATAG4MAAABAAgAAAA=.',
Ii='Iilia:BAAALgAECgQJBAAAAA==.',
In='Inwe:BAABLgAECn8WAAMMAAYJCwqqGwCnAAZoDAAABQAdAGkMAAAFABcAawwAAAUAFABqDAAAAwAVAGwMAAABABwA6gwAAAMAGwAMAAUJ5QmqGwCnAAVoDAAAAwAdAGkMAAADABcAawwAAAMAFABqDAAAAgAVAGwMAAABABwACwAFCR4CEXgAbgAFaAwAAAIABABpDAAAAgAIAGsMAAACAAcAagwAAAEAAwDqDAAAAwADAAAA.',
Je='Jeemana:BAAALgADCgYJBgAAAA==.',
Jo='Johnnydodge:BAABLgAECn8eAAIPAAgJKAyeHwB9AQhoDAAABgAnAGkMAAAFABoAawwAAAUAIQBqDAAABAAnAGwMAAAEACMAbQwAAAIACwDqDAAAAwAqAG4MAAABABwADwAICSgMnh8AfQEIaAwAAAYAJwBpDAAABQAaAGsMAAAFACEAagwAAAQAJwBsDAAABAAjAG0MAAACAAsA6gwAAAMAKgBuDAAAAQAcAAAA.Joyride:BAABLgAECn8bAAMZAAcJlhqaCQDAAQdoDAAABgBTAGkMAAAFAFAAawwAAAUANABqDAAAAwA6AGwMAAACAEsA6gwAAAUAOwBuDAAAAQA4ABkABwmWGpoJAMABB2gMAAAFAFMAaQwAAAUAUABrDAAABQA0AGoMAAADADoAbAwAAAIASwDqDAAABQA7AG4MAAABADgAGgABCeQOJEQBMgABaAwAAAEAJgAAAA==.',
Ju='Jujuwing:BAAALgAECgcJEAAAAA==.',
['Jù']='Jùde:BAAALgAECgQJCQAAAA==.',
Ka='Kaidastraza:BAAALgADCgcJCgAAAA==.Kaliel:BAAALgADCgUJBQAAAA==.Kalthas:BAAALgAECgEJAQAAAA==.Kanrethad:BAAALgAECgkJEwAAAA==.',
Ke='Kerrygan:BAABLgAECn8XAAIbAAYJdQ5KHQAJAQZoDAAABAAxAGkMAAAEACIAawwAAAQAIQBqDAAABAAnAGwMAAADACMA6gwAAAQAIAAbAAYJdQ5KHQAJAQZoDAAABAAxAGkMAAAEACIAawwAAAQAIQBqDAAABAAnAGwMAAADACMA6gwAAAQAIAAAAA==.',
Kh='Khaed:BAABLgAECn8ZAAIcAAkJHhHpEQCYAQloDAAABAAvAGkMAAAEADcAawwAAAIAJQBqDAAAAwAgAGwMAAABABQAbQwAAAEAJADqDAAABQBPAG4MAAAEADYAbwwAAAEAEwAcAAkJHhHpEQCYAQloDAAABAAvAGkMAAAEADcAawwAAAIAJQBqDAAAAwAgAGwMAAABABQAbQwAAAEAJADqDAAABQBPAG4MAAAEADYAbwwAAAEAEwAAAA==.',
Ki='Kicat:BAAALgADCgYJCgAAAA==.Kilmister:BAAALgADCgkJFwABLgAECgEJAQAXAAAAAA==.Kinara:BAAALgAECgIJAgAAAA==.',
Ko='Korthank:BAABLgAECn8XAAMcAAkJXyApCgAvAgloDAAAAwBfAGkMAAADAFQAawwAAAMAVwBqDAAAAgBfAGwMAAACADEAbQwAAAEAPwDqDAAABQBbAG4MAAADAFwAbwwAAAEAYgAcAAkJXyApCgAvAgloDAAAAgBfAGkMAAADAFQAawwAAAMAVwBqDAAAAgBfAGwMAAACADEAbQwAAAEAPwDqDAAABQBbAG4MAAADAFwAbwwAAAEAYgANAAEJXRCPpAArAAFoDAAAAQApAAAA.Koruka:BAAALgADCgEJAQAAAA==.Kozatri:BAAALgADCgcJEwAAAA==.',
Kr='Krentead:BAAALgADCgYJBgAAAA==.',
Kw='Kwissy:BAABLgAECn8UAAIHAAYJyQQwbgDgAAZoDAAABAARAGkMAAAEAA4AawwAAAMACQBqDAAAAwAWAGwMAAADAAoA6gwAAAMACAAHAAYJyQQwbgDgAAZoDAAABAARAGkMAAAEAA4AawwAAAMACQBqDAAAAwAWAGwMAAADAAoA6gwAAAMACAAAAA==.',
La='Labellanotte:BAABLgAECn8aAAMLAAcJcwVfXQC+AAdoDAAABQAIAGkMAAAFABcAawwAAAUADQBqDAAAAwAWAGwMAAACAAwA6gwAAAUACgBuDAAAAQAGAAsABwlzBV9dAL4AB2gMAAADAAgAaQwAAAMAFwBrDAAABAANAGoMAAACABYAbAwAAAIADADqDAAABQAKAG4MAAABAAYADAAECakGVR8AggAEaAwAAAIAFgBpDAAAAgAQAGsMAAABAAwAagwAAAEAFQAAAA==.Lamastrasz:BAAALgAECgEJAQAAAA==.Landao:BAAALgAECgQJBAAAAA==.Lateron:BAAALgADCgYJBgAAAA==.Laturalus:BAAALgADCgUJBQAAAA==.Layssa:BAABLgAECn8WAAMdAAcJ1BW/HQBdAQdoDAAAAgAhAGkMAAADACgAawwAAAMAOgBqDAAAAwAfAGwMAAADAEQA6gwAAAQARwBuDAAABAA+AB0ABwnUFb8dAF0BB2gMAAABACEAaQwAAAIAKABrDAAAAgA6AGoMAAACAB8AbAwAAAIARADqDAAABABHAG4MAAAEAD4ACwAFCd4IUIMA0QAFaAwAAAEAFgBpDAAAAQAWAGsMAAABAAwAagwAAAEAGgBsDAAAAQAdAAAA.',
Li='Lightarrow:BAAALgAECgcJBwAAAA==.Liliania:BAABLgAECn8XAAMeAAgJUgezDQAGAQhoDAAAAgAEAGkMAAACAA4AawwAAAMACwBqDAAAAwAOAGwMAAAFAB0AbQwAAAIADQDqDAAABAAdAG4MAAACABwAHgAICVIHsw0ABgEIaAwAAAIABABpDAAAAgAOAGsMAAACAAsAagwAAAIADgBsDAAABQAdAG0MAAACAA0A6gwAAAQAHQBuDAAAAgAcAAUAAgmSAREzARoAAmsMAAABAAQAagwAAAEAAgAAAA==.Limper:BAAALgADCgMJAwAAAA==.Lizuket:BAAALgADCgYJCwAAAA==.',
Lo='Loveles:BAAALgADCgUJBQAAAA==.',
Lu='Lucry:BAAALgADCgkJDgAAAA==.Lucyford:BAABLgAECn8YAAMaAAYJjxjdXABMAQZoDAAABQA+AGkMAAAEADwAawwAAAQAPgBqDAAAAwBKAGwMAAADAEMA6gwAAAUAPQAaAAYJjxjdXABMAQZoDAAAAwA+AGkMAAADADwAawwAAAMAPgBqDAAAAgBKAGwMAAACAEMA6gwAAAQAPQAEAAYJUBmyMAAmAQZoDAAAAgBJAGkMAAABADgAawwAAAEARQBqDAAAAQBIAGwMAAABAFoA6gwAAAEAGQAAAA==.Lunafloof:BAAALgAECgcJDQAAAA==.Lunaiya:BAAALgAECgUJDQAAAA==.Lunarfang:BAAALgAECgEJAQAAAA==.Lunarosa:BAAALgADCgkJCQABLgAECgEJAQAXAAAAAA==.',
Ly='Lyraali:BAABLgAECn8XAAIHAAcJzBfILQCrAQdoDAAABgBGAGkMAAAEAEEAawwAAAQAQwBqDAAAAgAmAGwMAAABAC4A6gwAAAUAOABuDAAAAQA7AAcABwnMF8gtAKsBB2gMAAAGAEYAaQwAAAQAQQBrDAAABABDAGoMAAACACYAbAwAAAEALgDqDAAABQA4AG4MAAABADsAAAA=.',
Ma='Magemode:BAABLgAECn8YAAIfAAYJyCHjTgBKAgZoDAAABABLAGkMAAAEAF4AawwAAAQAVQBqDAAABABJAGwMAAAEAFcA6gwAAAQAWgAfAAYJyCHjTgBKAgZoDAAABABLAGkMAAAEAF4AawwAAAQAVQBqDAAABABJAGwMAAAEAFcA6gwAAAQAWgAAAA==.Maomaow:BAAALgADCggJCAAAAA==.Mara:BAAALgADCgYJEQAAAA==.Mavramaria:BAAALgADCgYJCgAAAA==.',
Me='Melzemphx:BAAALgAECgYJEQAAAA==.',
Mi='Mikeberetta:BAAALgADCgMJAwAAAA==.Miniz:BAAALgADCgcJBwAAAA==.Minlea:BAAALgADCggJCAAAAA==.Misirlou:BAAALgADCgMJAwABLgAECgkJJQAQANwaAA==.Mizchivf:BAAALgADCgQJBgAAAA==.',
Mo='Mogal:BAAALgADCgEJAQAAAA==.Moktezuma:BAAALgAECgQJBAAAAA==.Moosifer:BAAALgADCgYJBgAAAA==.Morodos:BAAALgADCgkJFAAAAA==.',
Mu='Murtaugh:BAAALgADCgcJCgAAAA==.Mutekii:BAAALgAECgYJBgAAAA==.',
Na='Natrel:BAABLgAECn8YAAMNAAYJIR7WGAAEAgZoDAAABQBjAGkMAAAFAFYAawwAAAQAVwBqDAAAAwAxAGwMAAADADcA6gwAAAQAVAANAAYJIR7WGAAEAgZoDAAABABjAGkMAAAEAFYAawwAAAMAVwBqDAAAAgAxAGwMAAACADcA6gwAAAMAVAADAAYJ/QYuOgDYAAZoDAAAAQANAGkMAAABABEAawwAAAEAEABqDAAAAQASAGwMAAABABEA6gwAAAEAGAAAAA==.',
Ne='Neema:BAAALgAECgEJAwAAAA==.Nemmael:BAAALgADCgcJDwAAAA==.',
No='Noctogero:BAAALgADCgcJBwAAAA==.Nosibm:BAAALgADCgkJEgAAAA==.Notabutt:BAAALgADCgYJBgAAAA==.',
Ny='Nyxes:BAAALgADCgMJAwAAAA==.',
['Nê']='Nêo:BAAALgADCgcJBwAAAA==.',
Oc='Octane:BAAALgAECgEJAQAAAA==.Octozm:BAABLgAFFH8GAAIfAAIJJyMTMwDRAAJoDAAAAwBaAOoMAAADAFkAHwACCScjEzMA0QACaAwAAAMAWgDqDAAAAwBZAAAA.',
Or='Oreofrosting:BAAALgADCgkJEwAAAA==.',
Pa='Palmstrike:BAAALgAECgEJAQAAAA==.Pañdø:BAAALgADCgMJAwAAAA==.',
Pe='Penderrin:BAAALgADCggJDgAAAA==.',
Pi='Pidia:BAAALgADCgUJCAAAAA==.',
Po='Popes:BAACLgAFFH8JAAMHAAQJeA6mJAAXAQRoDAAAAwBCAGkMAAACAC8AawwAAAEACQDqDAAAAwAZAAcABAkYCKYkABcBBGgMAAACAAoAaQwAAAIALwBrDAAAAQAJAOoMAAACAA8AFgACCeYRAx0AogACaAwAAAEAQgDqDAAAAQAZAC4ABAp/GAADFgAJCV0beR8AKgIAFgAICRkdeR8AKgIABwACCcYTFY8AjgAAAAA=.Popper:BAAALgADCgIJAgAAAA==.',
Pr='Preservation:BAAALgAFFAMJAwAAAA==.Prey:BAAALgADCgMJAwAAAA==.Pruina:BAAALgADCgEJAQAAAA==.',
Pu='Pub:BAAALgAECgYJDQAAAA==.',
Py='Pyrø:BAAALgAECgEJAQAAAA==.',
Ra='Radhika:BAAALgAECgIJAwAAAA==.Raelos:BAAALgAECgcJEQAAAA==.Ragebait:BAABLgAECn8bAAIaAAcJ7RjUNQC8AQdoDAAABgBKAGkMAAAFAD4AawwAAAUARgBqDAAAAwBQAGwMAAACADUA6gwAAAUAPgBuDAAAAQA8ABoABwntGNQ1ALwBB2gMAAAGAEoAaQwAAAUAPgBrDAAABQBGAGoMAAADAFAAbAwAAAIANQDqDAAABQA+AG4MAAABADwAAAA=.Raiha:BAAALgADCgUJBQAAAA==.Ranikina:BAAALgAECgYJEgAAAA==.Raynor:BAAALgADCgIJAgAAAA==.',
Re='Regasus:BAAALgAECgYJCQAAAA==.Revolt:BAABLgAECn8nAAIYAAgJrhvFDAASAghoDAAABwBJAGkMAAAGAEUAawwAAAYAVQBqDAAABQA+AGwMAAAEAFMAbQwAAAMAJADqDAAABgBPAG4MAAACAEQAGAAICa4bxQwAEgIIaAwAAAcASQBpDAAABgBFAGsMAAAGAFUAagwAAAUAPgBsDAAABABTAG0MAAADACQA6gwAAAYATwBuDAAAAgBEAAAA.Reïna:BAABLgAECn8UAAIeAAYJaA2vDgD3AAZoDAAABgAbAGkMAAAEACgAawwAAAQAJABqDAAAAwAjAGwMAAABACIA6gwAAAIAHwAeAAYJaA2vDgD3AAZoDAAABgAbAGkMAAAEACgAawwAAAQAJABqDAAAAwAjAGwMAAABACIA6gwAAAIAHwAAAA==.',
Rh='Rheía:BAAALgADCgYJBgABLgAFFAMJCQAEAFYgAA==.',
Ro='Roükai:BAAALgAECgQJBQAAAA==.',
Ry='Ryuruko:BAAALgAECgYJBgAAAA==.',
Sa='Sahariel:BAABLgAECn8mAAMSAAgJJx+PDgAUAghoDAAABQBNAGkMAAAFAGAAawwAAAUAUgBqDAAABQBUAGwMAAAGAE0AbQwAAAIANQDqDAAABwBaAG4MAAADAEsAEgAICScfjw4AFAIIaAwAAAQATQBpDAAABABgAGsMAAAEAFIAagwAAAQAVABsDAAABQBNAG0MAAACADUA6gwAAAYAWgBuDAAAAgBLABgABwnBEx0bAHkBB2gMAAABACkAaQwAAAEABABrDAAAAQBAAGoMAAABAC0AbAwAAAEASQDqDAAAAQBAAG4MAAABADcAAAA=.',
Sc='Schwartpheil:BAAALgAECgYJEAAAAA==.Schwartzbann:BAAALgADCgcJCgABLgAECgYJEAAXAAAAAA==.Scilla:BAAALgADCgEJAQABLgAECgEJAQAXAAAAAA==.',
Sh='Shadowballz:BAAALgAECggJEQAAAA==.Shadowwing:BAAALgAECgMJBwAAAA==.Shamnorris:BAAALgADCgQJBAAAAA==.Shardemma:BAAALgADCgkJGQAAAA==.Shelfy:BAAALgAECgQJDwAAAA==.Shreddedbeef:BAAALgADCgcJBwAAAA==.Shytningbolt:BAAALgADCgMJAgAAAA==.Shælyn:BAAALgAECgMJBgAAAA==.',
Sk='Skitzo:BAAALgADCgkJFgAAAA==.',
Sp='Spinetaker:BAABLgAECn8mAAIUAAgJGSITBADDAghoDAAABQBeAGkMAAAFAF8AawwAAAYAXQBqDAAABABLAGwMAAAFAF0A6gwAAAcAWgBuDAAABABUAG8MAAACADoAFAAICRkiEwQAwwIIaAwAAAUAXgBpDAAABQBfAGsMAAAGAF0AagwAAAQASwBsDAAABQBdAOoMAAAHAFoAbgwAAAQAVABvDAAAAgA6AAEuAAUUBQkUAAkA4iEA.Spyder:BAAALgADCgQJBAAAAA==.',
St='Stolensouls:BAABLgAECn8XAAMeAAYJzA9oDQALAQZoDAAABgAkAGkMAAAFADkAawwAAAUALABqDAAAAwAWAGwMAAABACMA6gwAAAMAHAAeAAYJzA9oDQALAQZoDAAABQAkAGkMAAAFADkAawwAAAUALABqDAAAAwAWAGwMAAABACMA6gwAAAMAHAAFAAEJegESMwEaAAFoDAAAAQADAAAA.Strawkun:BAAALgAECgIJAwAAAA==.',
Su='Sunaris:BAAALgADCgUJBQAAAA==.Suneater:BAAALgAECgQJBAAAAA==.',
['Sç']='Sçruffy:BAACLgAFFH8UAAMJAAUJ4iGsIABrAQVoDAAABQBaAGkMAAAFAE8AawwAAAMAVQBqDAAAAwBgAOoMAAAEAFsACQAECeIhrCAAawEEaAwAAAUAWgBpDAAABQBPAGsMAAADAFUA6gwAAAQAWwAVAAEJAAB4EwBXAAFqDAAAAwBgAC4ABAp/OwACCQAJCXsmCwUAgwMACQAJCXsmCwUAgwMAAAA=.',
Ta='Tahtiania:BAAALgADCgYJCwAAAA==.Talas:BAAALgADCgEJAQAAAA==.Taliesin:BAAALgADCgUJBQAAAA==.',
Te='Teldryn:BAACLgAFFH8MAAIPAAQJ9BEnFQAbAQRoDAAABABMAGkMAAADADYAawwAAAIABQDqDAAAAwAwAA8ABAn0EScVABsBBGgMAAAEAEwAaQwAAAMANgBrDAAAAgAFAOoMAAADADAALgAECn8kAAMPAAgJWyRMBwAzAwAPAAgJWyRMBwAzAwAOAAEJ3hjXOQBJAAAAAA==.Telios:BAAALgAECgQJBQAAAA==.',
Th='Thaer:BAAALgADCgYJCgAAAA==.Thorendire:BAABLgAECn8kAAIbAAgJ4g5eEgB6AQhoDAAABgAwAGkMAAAGACQAawwAAAYALgBqDAAABQAmAGwMAAAEACsAbQwAAAIAGADqDAAABQArAG4MAAACABcAGwAICeIOXhIAegEIaAwAAAYAMABpDAAABgAkAGsMAAAGAC4AagwAAAUAJgBsDAAABAArAG0MAAACABgA6gwAAAUAKwBuDAAAAgAXAAAA.',
Ti='Tirnz:BAABLgAECn8mAAIKAAgJugrRBwBMAQhoDAAABwAlAGkMAAAGABMAawwAAAUAGQBqDAAABAAgAGwMAAAEACMAbQwAAAMAHQDqDAAABgAbAG4MAAADABIACgAICboK0QcATAEIaAwAAAcAJQBpDAAABgATAGsMAAAFABkAagwAAAQAIABsDAAABAAjAG0MAAADAB0A6gwAAAYAGwBuDAAAAwASAAAA.',
To='Tohotstotrot:BAAALgADCgQJBAAAAA==.Torlana:BAAALgADCgYJBgAAAA==.',
Tr='Trafaros:BAAALgADCgMJAwAAAA==.Trilldh:BAAALgAECgcJBQAAAA==.Trixielou:BAAALgAECggJEAAAAA==.',
Tt='Ttattoo:BAEBLgAECn8YAAMgAAYJ5QfTNADUAAZoDAAABQAdAGkMAAAEABcAawwAAAUAEABqDAAAAwATAGwMAAACABUA6gwAAAUACQAgAAYJ5QfTNADUAAZoDAAABQAdAGkMAAAEABcAawwAAAUAEABqDAAAAwATAGwMAAABABUA6gwAAAUACQAUAAEJqALkeQAbAAFsDAAAAQAGAAAA.Ttattooz:BAEALgADCgMJAwABLgAECgYJGAAgAOUHAA==.',
Ty='Tyramonde:BAAALgAECgYJBgAAAA==.',
Ub='Ubonrebu:BAAALgAFFAEJAQAAAA==.',
Va='Vaelestrix:BAACLgAFFH8XAAQBAAcJzRruAwCuAQdoDAAABgBhAGkMAAAGAGIAawwAAAcAWgBqDAAAAQBOAGwMAAABABIA6gwAAAEAMwBuDAAAAQA4AAEABgmyHu4DAK4BBmgMAAAFAGEAaQwAAAUAYgBrDAAABgBaAGoMAAABAE4A6gwAAAEAMwBuDAAAAQA4ACEAAwkMHI4DABYBA2gMAAABAFUAaQwAAAEAPQBrDAAAAQBEACIAAQlRBywGAF0AAWwMAAABABIALgAECn88AAMBAAkJ5iVuAADlAwABAAkJ5iVuAADlAwAiAAEJPyWFGABsAAAAAA==.Valholla:BAAALgADCgMJAwAAAA==.Vashtanerada:BAAALgADCgYJCgAAAA==.',
Ve='Veilish:BAAALgADCgYJCQAAAA==.',
Vo='Voiddøøde:BAAALgADCgcJBwAAAA==.Voidsocket:BAAALgAECgcJAQAAAA==.Voidtoes:BAAALgADCgYJBgAAAA==.',
Vu='Vulpvs:BAAALgADCgcJCwAAAA==.',
Vv='Vvlpvs:BAAALgADCgQJBAAAAA==.',
Wa='Warherald:BAABLgAECn8ZAAMjAAYJ2g8bGgD1AAZoDAAABgArAGkMAAAFACIAawwAAAQAMgBqDAAAAwAzAGwMAAADACUA6gwAAAQAJAAjAAYJ2g8bGgD1AAZoDAAABQArAGkMAAAEACIAawwAAAQAMgBqDAAAAwAzAGwMAAADACUA6gwAAAMAJAAPAAMJAwVIWQBrAANoDAAAAQAMAGkMAAABABgA6gwAAAEAAQAAAA==.Wasntme:BAAALgADCgYJBgABLgAECgcJGwAYAL0KAA==.',
We='Wednesday:BAACLgAFFH8aAAIVAAcJ/xSiBQCPAQdoDAAABQA9AGkMAAAFAFMAawwAAAUAUgBqDAAAAgBLAG0MAAABABUA6gwAAAcARgBuDAAAAQACABUABwn/FKIFAI8BB2gMAAAFAD0AaQwAAAUAUwBrDAAABQBSAGoMAAACAEsAbQwAAAEAFQDqDAAABwBGAG4MAAABAAIALgAECn8lAAIVAAgJLyR3BACMAgAVAAgJLyR3BACMAgAAAA==.',
Wh='Whoops:BAAALgADCgcJBwAAAA==.',
Xa='Xalaria:BAAALgAECgYJDAAAAA==.',
Xi='Xirek:BAABLgAECn8bAAIjAAcJFw53FgAZAQdoDAAABgAZAGkMAAAFACkAawwAAAUAIgBqDAAAAwAXAGwMAAACADgA6gwAAAUALABuDAAAAQANACMABwkXDncWABkBB2gMAAAGABkAaQwAAAUAKQBrDAAABQAiAGoMAAADABcAbAwAAAIAOADqDAAABQAsAG4MAAABAA0AAAA=.',
Yr='Yreasak:BAABLgAECn8bAAMFAAcJdAfNagAGAQdoDAAABQATAGkMAAAFABkAawwAAAUAIABqDAAABAAUAGwMAAADAA0A6gwAAAQAEQBuDAAAAQAFAAUABwkzBs1qAAYBB2gMAAAEAA4AaQwAAAQAGQBrDAAABAASAGoMAAAEABQAbAwAAAMADQDqDAAABAARAG4MAAABAAUAJAADCRcI/BoAngADaAwAAAEAEwBpDAAAAQAJAGsMAAABACAAAAA=.Yrisan:BAAALgADCgUJBQABLgAECgcJGwAFAHQHAA==.',
Ys='Yseulde:BAAALgADCgkJEQABLgAECgcJGwAFAHQHAA==.',
Zo='Zonako:BAAALgAECgcJEgAAAA==.Zoogranby:BAAALgADCgYJBgAAAA==.',
Zu='Zurâ:BAABLgAECn8XAAIVAAYJkQXNJgCnAAZoDAAABAAMAGkMAAAEABMAawwAAAQACgBqDAAABAAWAGwMAAADABEA6gwAAAQACwAVAAYJkQXNJgCnAAZoDAAABAAMAGkMAAAEABMAawwAAAQACgBqDAAABAAWAGwMAAADABEA6gwAAAQACwAAAA==.',
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
