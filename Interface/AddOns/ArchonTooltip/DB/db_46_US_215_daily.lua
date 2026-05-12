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
local provider = {region='US',realm='TheScryers',name='US',type='daily',zone=46,date='2026-05-11',data={Ae='Aelin:BAAALgAECgYJBwAAAA==.',
Ai='Airo:BAABLgAECn8wAAIBAAkJQxffBwA2AgloDAAACABXAGkMAAAGAD4AawwAAAYAPgBqDAAABAA/AGwMAAAHAC4AbQwAAAQAVgDqDAAACQA6AG4MAAADACsAbwwAAAEAHQABAAkJQxffBwA2AgloDAAACABXAGkMAAAGAD4AawwAAAYAPgBqDAAABAA/AGwMAAAHAC4AbQwAAAQAVgDqDAAACQA6AG4MAAADACsAbwwAAAEAHQAAAA==.',
Ak='Akaris:BAABLgAECn8WAAICAAYJXwXZOgDEAAZoDAAABQAJAGkMAAAEAA4AawwAAAQAFgBqDAAAAwALAGwMAAACAAwA6gwAAAQACQACAAYJXwXZOgDEAAZoDAAABQAJAGkMAAAEAA4AawwAAAQAFgBqDAAAAwALAGwMAAACAAwA6gwAAAQACQAAAA==.',
Al='Alainea:BAABLgAECn8UAAIDAAgJTgWpLQAPAQhoDAAABAAOAGkMAAADAA8AawwAAAMABgBqDAAAAgAMAGwMAAACABcAbQwAAAIACQDqDAAAAgAQAG4MAAACAAgAAwAICU4FqS0ADwEIaAwAAAQADgBpDAAAAwAPAGsMAAADAAYAagwAAAIADABsDAAAAgAXAG0MAAACAAkA6gwAAAIAEABuDAAAAgAIAAAA.Alispia:BAAALgADCgUJBQAAAA==.',
Am='Amaterasu:BAABLgAFFH8JAAIEAAMJViATFgASAQNoDAAAAwBWAGkMAAADAFsA6gwAAAMARwAEAAMJViATFgASAQNoDAAAAwBWAGkMAAADAFsA6gwAAAMARwABLgAFFAMJCQAEAFYgAA==.Ambre:BAAALgAECgcJDQAAAA==.Amerdro:BAAALgAECgQJCQAAAA==.Amoreesa:BAAALgAECgQJBAAAAA==.',
An='Andross:BAAALgADCgcJEgABLgAECgcJGwAFAHQHAA==.Angrytestie:BAAALgAECgUJBQAAAA==.Anomaly:BAABLgAECn8sAAMGAAgJJSLFBACDAghoDAAABwBbAGkMAAAGAGAAawwAAAYAVgBqDAAABwBiAGwMAAAGAE8AbQwAAAIASADqDAAACABYAG4MAAACAGAABgAICSUixQQAgwIIaAwAAAcAWwBpDAAABQBgAGsMAAAGAFYAagwAAAcAYgBsDAAABgBPAG0MAAACAEgA6gwAAAcAWABuDAAAAgBgAAcAAgl2Dje5AFAAAmkMAAABAAMA6gwAAAEARgAAAA==.Anthousai:BAAALgADCgQJBAAAAA==.',
Ar='Ara:BAABLgAFFH8MAAIIAAYJARp+AwC7AQZoDAAAAgA8AGkMAAACAEsAawwAAAIAUgBqDAAAAQA+AGwMAAABACUA6gwAAAQAUgAIAAYJARp+AwC7AQZoDAAAAgA8AGkMAAACAEsAawwAAAIAUgBqDAAAAQA+AGwMAAABACUA6gwAAAQAUgAAAA==.',
As='Asylum:BAAALgADCgcJDQAAAA==.',
Au='Aura:BAAALgAECgMJAwAAAA==.',
Ax='Axl:BAABLgAECn8WAAMJAAYJ7gbRhADqAAZoDAAABQAMAGkMAAAEABcAawwAAAQAEgBqDAAAAwAOAGwMAAACABEA6gwAAAQAEAAJAAYJ7gbRhADqAAZoDAAABAAMAGkMAAAEABcAawwAAAQAEgBqDAAAAwAOAGwMAAACABEA6gwAAAQAEAAKAAEJ8QF2GgAhAAFoDAAAAQAEAAAA.',
Ay='Aylíth:BAAALgAFFAEJAQABLgAFFAMJCQAEAFYgAA==.',
Ba='Bacon:BAAALgADCgkJCQAAAA==.Bahdeeps:BAAALgAECgEJAQAAAA==.Bahheals:BAABLgAECn8UAAMLAAcJzgTsXgC1AAdoDAAAAwAZAGkMAAADAA0AawwAAAMABABqDAAAAgAEAGwMAAADAAYAbQwAAAEABADqDAAABQAaAAsABwnOBOxeALUAB2gMAAACABkAaQwAAAIADQBrDAAAAgAEAGoMAAACAAQAbAwAAAIABgBtDAAAAQAEAOoMAAAEABoADAAFCYUBZR8AeAAFaAwAAAEABABpDAAAAQAIAGsMAAABAAAAbAwAAAEAAADqDAAAAQAFAAAA.Banjoo:BAABLgAECn8aAAILAAgJfBvLGgAAAghoDAAABAA8AGkMAAADAFAAawwAAAMAUgBqDAAAAwBDAGwMAAADAEoAbQwAAAMANwDqDAAABABMAG4MAAADAEIACwAICXwbyxoAAAIIaAwAAAQAPABpDAAAAwBQAGsMAAADAFIAagwAAAMAQwBsDAAAAwBKAG0MAAADADcA6gwAAAQATABuDAAAAwBCAAAA.Baruk:BAABLgAECn8cAAINAAgJ8BMnKgCIAQhoDAAABQAyAGkMAAAEADsAawwAAAQAQwBqDAAAAwBLAGwMAAAFADwAbQwAAAEAAgDqDAAABABFAG4MAAACABYADQAICfATJyoAiAEIaAwAAAUAMgBpDAAABAA7AGsMAAAEAEMAagwAAAMASwBsDAAABQA8AG0MAAABAAIA6gwAAAQARQBuDAAAAgAWAAAA.',
Be='Beauzericka:BAAALgADCgEJAQAAAA==.Beeswax:BAAALgADCgkJCQAAAA==.',
Bi='Bigçhungi:BAABLgAECn8YAAMOAAgJAx+rBgAMAghoDAAAAwBGAGkMAAAEAFAAawwAAAQAUgBqDAAABABdAGwMAAAEAFkAbQwAAAEAQgDqDAAAAwBUAG4MAAABAFEADgAHCdIdqwYADAIHaAwAAAEAJwBpDAAAAQBQAGsMAAABAFIAagwAAAEAXQBsDAAAAQBZAOoMAAABAFQAbgwAAAEAUQAPAAcJlRdDGwCZAQdoDAAAAgBGAGkMAAADAC8AawwAAAMARwBqDAAAAwA6AGwMAAADAD0AbQwAAAEAQgDqDAAAAgAsAAEuAAUUBQkUAAkA4iEA.',
Bl='Blitzen:BAABLgAECn8lAAMQAAkJ3BqvAQBwAgloDAAABQBBAGkMAAAFAEQAawwAAAYASQBqDAAABABjAGwMAAAEAFIAbQwAAAMARgDqDAAABAA2AG4MAAAEAEAAbwwAAAIARgAQAAkJ3BqvAQBwAgloDAAABQBBAGkMAAAFAEQAawwAAAUASQBqDAAABABjAGwMAAAEAFIAbQwAAAMARgDqDAAABAA2AG4MAAAEAEAAbwwAAAIARgARAAEJswRKSwArAAFrDAAAAQAMAAAA.',
Bo='Borealiss:BAAALgAECgYJBwABLgAECgkJJQAQANwaAA==.',
Br='Brewjigsaw:BAAALgADCgcJCgAAAA==.',
Bu='Buffsubordie:BAAALgAFFAEJAQAAAA==.',
Bw='Bwonsamdi:BAABLgAECn9EAAIDAAgJhCAQDwC2AghoDAAACgBeAGkMAAAKAFcAawwAAAoAWABqDAAACgBSAGwMAAAIAGAAbQwAAAQAQgDqDAAADABaAG4MAAAEADsAAwAICYQgEA8AtgIIaAwAAAoAXgBpDAAACgBXAGsMAAAKAFgAagwAAAoAUgBsDAAACABgAG0MAAAEAEIA6gwAAAwAWgBuDAAABAA7AAAA.',
['Bâ']='Bârks:BAABLgAECn8aAAISAAYJKCDSDgAMAgZoDAAABgBbAGkMAAAFAFUAawwAAAUAUwBqDAAAAwBaAGwMAAACAEgA6gwAAAUARgASAAYJKCDSDgAMAgZoDAAABgBbAGkMAAAFAFUAawwAAAUAUwBqDAAAAwBaAGwMAAACAEgA6gwAAAUARgAAAA==.',
Ca='Callia:BAAALgAECgYJBgAAAA==.Camazotz:BAAALgADCgUJBQAAAA==.Cardkun:BAAALgADCgIJAgAAAA==.Carp:BAABLgAECn8aAAITAAYJKgpIHACgAAZoDAAABQANAGkMAAAFABkAawwAAAUAHABqDAAABAAmAGwMAAACACcA6gwAAAUAGAATAAYJKgpIHACgAAZoDAAABQANAGkMAAAFABkAawwAAAUAHABqDAAABAAmAGwMAAACACcA6gwAAAUAGAAAAA==.',
Ch='Chargerkun:BAAALgAECgMJCwAAAA==.Chayda:BAAALgADCgEJAQAAAA==.Choleena:BAABLgAECn8aAAINAAYJvxj1JQCgAQZoDAAABgBJAGkMAAAFAEAAawwAAAUALQBqDAAAAwBQAGwMAAACAD4A6gwAAAUANAANAAYJvxj1JQCgAQZoDAAABgBJAGkMAAAFAEAAawwAAAUALQBqDAAAAwBQAGwMAAACAD4A6gwAAAUANAAAAA==.',
Ci='Cindress:BAAALgADCgEJAQAAAA==.',
Co='Combat:BAAALgAECgYJDwAAAA==.Coojotwo:BAAALgAECgUJDAAAAA==.',
Cr='Crewd:BAAALgADCgEJAQAAAA==.Crimzon:BAAALgAECgEJAQAAAA==.',
Da='Dangerfloof:BAAALgADCgQJCAAAAA==.Dangerwithin:BAACLgAFFH8jAAMUAAgJpCMeAACrAghoDAAABgBjAGkMAAAGAGMAawwAAAYAXwBqDAAABABjAGwMAAADAE0AbQwAAAIAQgDqDAAABwBkAG4MAAABAGMAFAAHCYUkHgAAqwIHaAwAAAYAYwBpDAAABgBjAGsMAAAGAF8AagwAAAQAYwBtDAAAAgBCAOoMAAAHAGQAbgwAAAEAYwAIAAEJrh2jJgBYAAFsDAAAAwBLAC4ABAp/JgACFAAJCcomMwAA+wMAFAAJCcomMwAA+wMAAS4ABRQDCQkABABWIAA=.Danklazercat:BAAALgADCgcJDgABLgAFFAUJFAAJAOIhAA==.Darius:BAABLgAFFH8FAAIVAAMJ6gwAFgC3AANoDAAAAQAbAGkMAAACACYA6gwAAAIAIAAVAAMJ6gwAFgC3AANoDAAAAQAbAGkMAAACACYA6gwAAAIAIAAAAA==.Dastraz:BAAALgAECgYJDgAAAA==.',
De='Decay:BAAALgAECgMJAwAAAA==.Deebz:BAABLgAECn8ZAAMWAAYJARywCgBVAQZoDAAABQBOAGkMAAAFAEoAawwAAAUAQQBqDAAAAwBAAGwMAAACAEcA6gwAAAUARAAHAAYJ/hk0OwBxAQZoDAAAAQBOAGkMAAABAEoAawwAAAEAQQBqDAAAAgA5AGwMAAABAC4A6gwAAAEARAAWAAYJQxiwCgBVAQZoDAAABAA4AGkMAAAEAEUAawwAAAQALwBqDAAAAQBAAGwMAAABAEcA6gwAAAQAQQAAAA==.Devkra:BAAALgADCggJDgAAAA==.',
Dm='Dmgabsorb:BAAALgADCgIJAgAAAA==.',
Do='Doge:BAAALgADCgkJCQAAAA==.',
Dr='Dragoneux:BAAALgAFFAIJAwAAAQ==.',
Du='Dudemachine:BAAALgADCgUJBQABLgADCgkJEwAXAAAAAA==.',
['Dè']='Dèèbz:BAAALgADCgQJBAAAAA==.',
['Dö']='Dörf:BAAALgADCgMJAwAAAA==.',
Ed='Eddison:BAAALgADCgkJCQAAAA==.',
En='Enchanted:BAABLgAECn8XAAMVAAcJgBhAGQAUAQdoDAAABQA4AGkMAAAEADgAawwAAAQAPABqDAAAAwA5AGwMAAADAEQA6gwAAAMASABuDAAAAQA+ABUABgnqFEAZABQBBmgMAAADAB4AaQwAAAMANwBrDAAAAwA8AGoMAAADADkAbAwAAAIARADqDAAAAgA0AAkABgkkFiqKAN8ABmgMAAACADgAaQwAAAEAOABrDAAAAQAxAGwMAAABACoA6gwAAAEASABuDAAAAQA+AAAA.Enid:BAACLgAFFH8mAAIVAAcJPCYKAAAFAwdoDAAABgBkAGkMAAAGAGMAawwAAAYAYwBqDAAABwBjAGwMAAAFAGEAbQwAAAEAWgDqDAAABwBjABUABwk8JgoAAAUDB2gMAAAGAGQAaQwAAAYAYwBrDAAABgBjAGoMAAAHAGMAbAwAAAUAYQBtDAAAAQBaAOoMAAAHAGMALgAECn8ZAAIVAAgJqSZaAQB+AwAVAAgJqSZaAQB+AwAAAA==.',
Es='Eskanor:BAAALgADCgQJBgAAAA==.',
Et='Eternalwrath:BAAALgAECgYJDAAAAA==.',
Eu='Eublar:BAAALgAECgEJAQAAAA==.',
Fa='Falzemphx:BAAALgAECgMJBgAAAA==.Farbringer:BAAALgAECgUJBgABLgAECgYJDgAXAAAAAA==.Fayanna:BAAALgADCgEJAQAAAA==.',
Fe='Felicitee:BAAALgAECgMJAwAAAA==.',
Fo='Foxxylady:BAABLgAECn8dAAIHAAcJZx5AJQDPAQdoDAAABgBcAGkMAAAFAF8AawwAAAYAUABqDAAAAwBfAGwMAAABAEsA6gwAAAcAPQBuDAAAAQA9AAcABwlnHkAlAM8BB2gMAAAGAFwAaQwAAAUAXwBrDAAABgBQAGoMAAADAF8AbAwAAAEASwDqDAAABwA9AG4MAAABAD0AAAA=.',
Fu='Furbees:BAAALgAECgUJEAAAAA==.',
Ge='Geenon:BAAALgAECgMJBgAAAA==.Gephen:BAAALgADCgUJBQAAAA==.',
Gr='Grakdeez:BAAALgAECgUJBwABLgAECgkJEAAXAAAAAA==.Grakfist:BAAALgAECgkJEAAAAA==.Graubard:BAAALgAECgEJAQAAAA==.Gravec:BAAALgADCgEJAQAAAA==.Grimswhisper:BAAALgAECgYJDQAAAA==.Gritchen:BAABLgAECn8YAAMSAAYJYR0JEgDjAQZoDAAAAwBLAGkMAAAFAFEAawwAAAQAPQBqDAAAAwBdAGwMAAADAEIA6gwAAAYASQASAAYJYR0JEgDjAQZoDAAAAwBLAGkMAAAFAFEAawwAAAMAPQBqDAAAAgBdAGwMAAACAEIA6gwAAAYASQAYAAMJNAKoWQAzAANrDAAAAQAIAGoMAAABAA0AbAwAAAEAAgAAAA==.Growler:BAAALgAECgYJEAAAAA==.Grynsel:BAABLgAECn8aAAIHAAYJOxA5TwAwAQZoDAAABgAmAGkMAAAFAC0AawwAAAUAHwBqDAAAAwBBAGwMAAACADoA6gwAAAUAIgAHAAYJOxA5TwAwAQZoDAAABgAmAGkMAAAFAC0AawwAAAUAHwBqDAAAAwBBAGwMAAACADoA6gwAAAUAIgAAAA==.',
Ha='Harlynne:BAAALgADCgkJCQAAAA==.',
Ho='Holios:BAAALgADCgYJBgABLgAECgcJGwAYAL0KAA==.',
Hu='Huntwix:BAAALgADCgYJBgAAAA==.',
Id='Idontknow:BAABLgAECn8bAAIYAAcJvQprIwA4AQdoDAAABQAxAGkMAAAGACQAawwAAAYAIABqDAAABAAZAGwMAAADABMA6gwAAAIAEwBuDAAAAQAIABgABwm9CmsjADgBB2gMAAAFADEAaQwAAAYAJABrDAAABgAgAGoMAAAEABkAbAwAAAMAEwDqDAAAAgATAG4MAAABAAgAAAA=.',
Ii='Iilia:BAAALgAECgQJBAAAAA==.',
In='Inwe:BAABLgAECn8WAAMMAAYJCwoYGwCnAAZoDAAABQAdAGkMAAAFABcAawwAAAUAFABqDAAAAwAVAGwMAAABABwA6gwAAAMAGwAMAAUJ5QkYGwCnAAVoDAAAAwAdAGkMAAADABcAawwAAAMAFABqDAAAAgAVAGwMAAABABwACwAFCR4Cb3YAbgAFaAwAAAIABABpDAAAAgAIAGsMAAACAAcAagwAAAEAAwDqDAAAAwADAAAA.',
Je='Jeemana:BAAALgADCgYJBgAAAA==.',
Jo='Johnnydodge:BAABLgAECn8eAAIPAAgJKAzgHgB/AQhoDAAABgAnAGkMAAAFABoAawwAAAUAIQBqDAAABAAnAGwMAAAEACMAbQwAAAIACwDqDAAAAwAqAG4MAAABABwADwAICSgM4B4AfwEIaAwAAAYAJwBpDAAABQAaAGsMAAAFACEAagwAAAQAJwBsDAAABAAjAG0MAAACAAsA6gwAAAMAKgBuDAAAAQAcAAAA.Joyride:BAABLgAECn8aAAMZAAYJdxv0DAB9AQZoDAAABgBTAGkMAAAFAFAAawwAAAUANABqDAAAAwA6AGwMAAACAEsA6gwAAAUAOwAZAAYJdxv0DAB9AQZoDAAABQBTAGkMAAAFAFAAawwAAAUANABqDAAAAwA6AGwMAAACAEsA6gwAAAUAOwAaAAEJ5A4hRAEyAAFoDAAAAQAmAAAA.',
Ju='Jujuwing:BAAALgAECgYJCgAAAA==.',
['Jù']='Jùde:BAAALgAECgQJCQAAAA==.',
Ka='Kaidastraza:BAAALgADCgcJCgAAAA==.Kaliel:BAAALgADCgUJBQAAAA==.Kalthas:BAAALgAECgEJAQAAAA==.Kanrethad:BAAALgAECgkJEwAAAA==.',
Ke='Kerrygan:BAABLgAECn8XAAIbAAYJdQ60HAAJAQZoDAAABAAxAGkMAAAEACIAawwAAAQAIQBqDAAABAAnAGwMAAADACMA6gwAAAQAIAAbAAYJdQ60HAAJAQZoDAAABAAxAGkMAAAEACIAawwAAAQAIQBqDAAABAAnAGwMAAADACMA6gwAAAQAIAAAAA==.',
Kh='Khaed:BAABLgAECn8ZAAIcAAkJHhHpEQCYAQloDAAABAAvAGkMAAAEADcAawwAAAIAJQBqDAAAAwAgAGwMAAABABQAbQwAAAEAJADqDAAABQBPAG4MAAAEADYAbwwAAAEAEwAcAAkJHhHpEQCYAQloDAAABAAvAGkMAAAEADcAawwAAAIAJQBqDAAAAwAgAGwMAAABABQAbQwAAAEAJADqDAAABQBPAG4MAAAEADYAbwwAAAEAEwAAAA==.',
Ki='Kicat:BAAALgADCgYJCgAAAA==.Kilmister:BAAALgADCgkJFwABLgAECgEJAQAXAAAAAA==.Kinara:BAAALgAECgIJAgAAAA==.',
Ko='Korthank:BAABLgAECn8WAAMcAAgJeh8oCgAvAghoDAAAAwBfAGkMAAADAFQAawwAAAMAVwBqDAAAAgBfAGwMAAACADEAbQwAAAEAPwDqDAAABQBbAG4MAAADAFwAHAAICXofKAoALwIIaAwAAAIAXwBpDAAAAwBUAGsMAAADAFcAagwAAAIAXwBsDAAAAgAxAG0MAAABAD8A6gwAAAUAWwBuDAAAAwBcAA0AAQldEI+kACsAAWgMAAABACkAAAA=.Koruka:BAAALgADCgEJAQAAAA==.Kozatri:BAAALgADCgcJEwAAAA==.',
Kr='Krentead:BAAALgADCgYJBgAAAA==.',
Kw='Kwissy:BAABLgAECn8UAAIHAAYJyQQdbADhAAZoDAAABAARAGkMAAAEAA4AawwAAAMACQBqDAAAAwAWAGwMAAADAAoA6gwAAAMACAAHAAYJyQQdbADhAAZoDAAABAARAGkMAAAEAA4AawwAAAMACQBqDAAAAwAWAGwMAAADAAoA6gwAAAMACAAAAA==.',
La='Labellanotte:BAABLgAECn8ZAAMLAAYJ8AUcYwCoAAZoDAAABQAIAGkMAAAFABcAawwAAAUADQBqDAAAAwAWAGwMAAACAAwA6gwAAAUACgALAAYJ8AUcYwCoAAZoDAAAAwAIAGkMAAADABcAawwAAAQADQBqDAAAAgAWAGwMAAACAAwA6gwAAAUACgAMAAQJqQaYHgCCAARoDAAAAgAWAGkMAAACABAAawwAAAEADABqDAAAAQAVAAAA.Lamastrasz:BAAALgAECgEJAQAAAA==.Landao:BAAALgAECgQJBAAAAA==.Lateron:BAAALgADCgYJBgAAAA==.Laturalus:BAAALgADCgUJBQAAAA==.Layssa:BAABLgAECn8WAAMdAAcJ1BUtHQBdAQdoDAAAAgAhAGkMAAADACgAawwAAAMAOgBqDAAAAwAfAGwMAAADAEQA6gwAAAQARwBuDAAABAA+AB0ABwnUFS0dAF0BB2gMAAABACEAaQwAAAIAKABrDAAAAgA6AGoMAAACAB8AbAwAAAIARADqDAAABABHAG4MAAAEAD4ACwAFCd4ITIMA0QAFaAwAAAEAFgBpDAAAAQAWAGsMAAABAAwAagwAAAEAGgBsDAAAAQAdAAAA.',
Li='Lightarrow:BAAALgAECgcJBwAAAA==.Liliania:BAABLgAECn8XAAMeAAgJUgcADQASAQhoDAAAAgAEAGkMAAACAA4AawwAAAMACwBqDAAAAwAOAGwMAAAFAB0AbQwAAAIADQDqDAAABAAdAG4MAAACABwAHgAICVIHAA0AEgEIaAwAAAIABABpDAAAAgAOAGsMAAACAAsAagwAAAIADgBsDAAABQAdAG0MAAACAA0A6gwAAAQAHQBuDAAAAgAcAAUAAgmSAQ8zARoAAmsMAAABAAQAagwAAAEAAgAAAA==.Limper:BAAALgADCgMJAwAAAA==.Lizuket:BAAALgADCgYJCwAAAA==.',
Lo='Loveles:BAAALgADCgUJBQAAAA==.',
Lu='Lucry:BAAALgADCgkJDgAAAA==.Lucyford:BAABLgAECn8YAAMaAAYJjxj7WgBMAQZoDAAABQA+AGkMAAAEADwAawwAAAQAPgBqDAAAAwBKAGwMAAADAEMA6gwAAAUAPQAaAAYJjxj7WgBMAQZoDAAAAwA+AGkMAAADADwAawwAAAMAPgBqDAAAAgBKAGwMAAACAEMA6gwAAAQAPQAEAAYJUBnKLwAnAQZoDAAAAgBJAGkMAAABADgAawwAAAEARQBqDAAAAQBIAGwMAAABAFoA6gwAAAEAGQAAAA==.Lunafloof:BAAALgAECgYJDAAAAA==.Lunaiya:BAAALgAECgUJDQAAAA==.Lunarfang:BAAALgAECgEJAQAAAA==.Lunarosa:BAAALgADCgkJCQABLgAECgEJAQAXAAAAAA==.',
Ly='Lyraali:BAABLgAECn8WAAIHAAYJ8hcUPgBnAQZoDAAABgBGAGkMAAAEAEEAawwAAAQAQwBqDAAAAgAmAGwMAAABAC4A6gwAAAUAOAAHAAYJ8hcUPgBnAQZoDAAABgBGAGkMAAAEAEEAawwAAAQAQwBqDAAAAgAmAGwMAAABAC4A6gwAAAUAOAAAAA==.',
Ma='Magemode:BAABLgAECn8YAAIfAAYJyCHgTgBKAgZoDAAABABLAGkMAAAEAF4AawwAAAQAVQBqDAAABABJAGwMAAAEAFcA6gwAAAQAWgAfAAYJyCHgTgBKAgZoDAAABABLAGkMAAAEAF4AawwAAAQAVQBqDAAABABJAGwMAAAEAFcA6gwAAAQAWgAAAA==.Maomaow:BAAALgADCggJCAAAAA==.Mara:BAAALgADCgYJDwAAAA==.Mavramaria:BAAALgADCgYJCgAAAA==.',
Me='Melzemphx:BAAALgAECgYJEQAAAA==.',
Mi='Mikeberetta:BAAALgADCgMJAwAAAA==.Miniz:BAAALgADCgcJBwAAAA==.Minlea:BAAALgADCggJCAAAAA==.Misirlou:BAAALgADCgMJAwABLgAECgkJJQAQANwaAA==.Mizchivf:BAAALgADCgQJBgAAAA==.',
Mo='Mogal:BAAALgADCgEJAQAAAA==.Moktezuma:BAAALgAECgQJBAAAAA==.Moosifer:BAAALgADCgYJBgAAAA==.Morodos:BAAALgADCgkJFAAAAA==.',
Mu='Murtaugh:BAAALgADCgcJCgAAAA==.Mutekii:BAAALgAECgQJBAAAAA==.',
Na='Natrel:BAABLgAECn8YAAMNAAYJIR5RGAAEAgZoDAAABQBjAGkMAAAFAFYAawwAAAQAVwBqDAAAAwAxAGwMAAADADcA6gwAAAQAVAANAAYJIR5RGAAEAgZoDAAABABjAGkMAAAEAFYAawwAAAMAVwBqDAAAAgAxAGwMAAACADcA6gwAAAMAVAADAAYJ/QZbOQDYAAZoDAAAAQANAGkMAAABABEAawwAAAEAEABqDAAAAQASAGwMAAABABEA6gwAAAEAGAAAAA==.',
Ne='Neema:BAAALgAECgEJAwAAAA==.Nemmael:BAAALgADCgcJDwAAAA==.',
No='Noctogero:BAAALgADCgcJBwAAAA==.Nosibm:BAAALgADCgkJEgAAAA==.Notabutt:BAAALgADCgYJBgAAAA==.',
Ny='Nyxes:BAAALgADCgMJAwAAAA==.',
['Nê']='Nêo:BAAALgADCgcJBwAAAA==.',
Oc='Octane:BAAALgAECgEJAQAAAA==.Octozm:BAAALgAFFAIJBAAAAA==.',
Or='Oreofrosting:BAAALgADCgkJEwAAAA==.',
Pa='Palmstrike:BAAALgAECgEJAQAAAA==.Pañdø:BAAALgADCgMJAwAAAA==.',
Pe='Penderrin:BAAALgADCggJDgAAAA==.',
Pi='Pidia:BAAALgADCgUJCAAAAA==.',
Po='Popes:BAACLgAFFH8JAAMHAAQJeA47IwAZAQRoDAAAAwBCAGkMAAACAC8AawwAAAEACQDqDAAAAwAZAAcABAkYCDsjABkBBGgMAAACAAoAaQwAAAIALwBrDAAAAQAJAOoMAAACAA8AFgACCeYR/RwAogACaAwAAAEAQgDqDAAAAQAZAC4ABAp/GAADFgAJCV0bdh8AKgIAFgAICRkddh8AKgIABwACCcYTV4wAkAAAAAA=.Popper:BAAALgADCgIJAgAAAA==.',
Pr='Preservation:BAAALgAFFAMJAwAAAA==.Prey:BAAALgADCgMJAwAAAA==.Pruina:BAAALgADCgEJAQAAAA==.',
Pu='Pub:BAAALgAECgYJDQAAAA==.',
Py='Pyrø:BAAALgAECgEJAQAAAA==.',
Ra='Radhika:BAAALgAECgIJAwAAAA==.Raelos:BAAALgAECgcJEQAAAA==.Ragebait:BAABLgAECn8aAAIaAAYJNRmFSwB1AQZoDAAABgBKAGkMAAAFAD4AawwAAAUARgBqDAAAAwBQAGwMAAACADUA6gwAAAUAPgAaAAYJNRmFSwB1AQZoDAAABgBKAGkMAAAFAD4AawwAAAUARgBqDAAAAwBQAGwMAAACADUA6gwAAAUAPgAAAA==.Raiha:BAAALgADCgUJBQAAAA==.Ranikina:BAAALgAECgYJEgAAAA==.Raynor:BAAALgADCgIJAgAAAA==.',
Re='Regasus:BAAALgAECgYJCQAAAA==.Revolt:BAABLgAECn8nAAIYAAgJrhtxDAASAghoDAAABwBJAGkMAAAGAEUAawwAAAYAVQBqDAAABQA+AGwMAAAEAFMAbQwAAAMAJADqDAAABgBPAG4MAAACAEQAGAAICa4bcQwAEgIIaAwAAAcASQBpDAAABgBFAGsMAAAGAFUAagwAAAUAPgBsDAAABABTAG0MAAADACQA6gwAAAYATwBuDAAAAgBEAAAA.Reïna:BAABLgAECn8UAAIeAAYJaA1zDgD7AAZoDAAABgAbAGkMAAAEACgAawwAAAQAJABqDAAAAwAjAGwMAAABACIA6gwAAAIAHwAeAAYJaA1zDgD7AAZoDAAABgAbAGkMAAAEACgAawwAAAQAJABqDAAAAwAjAGwMAAABACIA6gwAAAIAHwAAAA==.',
Rh='Rheía:BAAALgADCgYJBgABLgAFFAMJCQAEAFYgAA==.',
Ro='Roükai:BAAALgAECgQJBQAAAA==.',
Ry='Ryuruko:BAAALgAECgYJBgAAAA==.',
Sa='Sahariel:BAABLgAECn8mAAMSAAgJJx8tDgAVAghoDAAABQBNAGkMAAAFAGAAawwAAAUAUgBqDAAABQBUAGwMAAAGAE0AbQwAAAIANQDqDAAABwBaAG4MAAADAEsAEgAICScfLQ4AFQIIaAwAAAQATQBpDAAABABgAGsMAAAEAFIAagwAAAQAVABsDAAABQBNAG0MAAACADUA6gwAAAYAWgBuDAAAAgBLABgABwnBE5MaAHoBB2gMAAABACkAaQwAAAEABABrDAAAAQBAAGoMAAABAC0AbAwAAAEASQDqDAAAAQBAAG4MAAABADcAAAA=.',
Sc='Schwartpheil:BAAALgAECgYJEAAAAA==.Schwartzbann:BAAALgADCgcJCgABLgAECgYJEAAXAAAAAA==.Scilla:BAAALgADCgEJAQABLgAECgEJAQAXAAAAAA==.',
Sh='Shadowballz:BAAALgAECggJEQAAAA==.Shadowwing:BAAALgAECgMJBwAAAA==.Shamnorris:BAAALgADCgQJBAAAAA==.Shardemma:BAAALgADCgkJGQAAAA==.Shelfy:BAAALgAECgQJDwAAAA==.Shreddedbeef:BAAALgADCgcJBwAAAA==.Shytningbolt:BAAALgADCgMJAgAAAA==.Shælyn:BAAALgAECgMJBgAAAA==.',
Sk='Skitzo:BAAALgADCgkJFgAAAA==.',
Sp='Spinetaker:BAABLgAECn8mAAIUAAgJGSLkAwDDAghoDAAABQBeAGkMAAAFAF8AawwAAAYAXQBqDAAABABLAGwMAAAFAF0A6gwAAAcAWgBuDAAABABUAG8MAAACADoAFAAICRki5AMAwwIIaAwAAAUAXgBpDAAABQBfAGsMAAAGAF0AagwAAAQASwBsDAAABQBdAOoMAAAHAFoAbgwAAAQAVABvDAAAAgA6AAEuAAUUBQkUAAkA4iEA.Spyder:BAAALgADCgQJBAAAAA==.',
St='Stolensouls:BAABLgAECn8XAAMeAAYJzA9CDQANAQZoDAAABgAkAGkMAAAFADkAawwAAAUALABqDAAAAwAWAGwMAAABACMA6gwAAAMAHAAeAAYJzA9CDQANAQZoDAAABQAkAGkMAAAFADkAawwAAAUALABqDAAAAwAWAGwMAAABACMA6gwAAAMAHAAFAAEJegEQMwEaAAFoDAAAAQADAAAA.Strawkun:BAAALgAECgIJAwAAAA==.',
Su='Sunaris:BAAALgADCgUJBQAAAA==.Suneater:BAAALgAECgQJBAAAAA==.',
['Sç']='Sçruffy:BAACLgAFFH8UAAMJAAUJ4iEUIABoAQVoDAAABQBaAGkMAAAFAE8AawwAAAMAVQBqDAAAAwBgAOoMAAAEAFsACQAECeIhFCAAaAEEaAwAAAUAWgBpDAAABQBPAGsMAAADAFUA6gwAAAQAWwAVAAEJAABzEwBXAAFqDAAAAwBgAC4ABAp/OwACCQAJCXsmDAUAgwMACQAJCXsmDAUAgwMAAAA=.',
Ta='Tahtiania:BAAALgADCgYJCwAAAA==.Talas:BAAALgADCgEJAQAAAA==.Taliesin:BAAALgADCgUJBQAAAA==.',
Te='Teldryn:BAACLgAFFH8MAAIPAAQJ9BFWFAAiAQRoDAAABABMAGkMAAADADYAawwAAAIABQDqDAAAAwAwAA8ABAn0EVYUACIBBGgMAAAEAEwAaQwAAAMANgBrDAAAAgAFAOoMAAADADAALgAECn8kAAMPAAgJWyRMBwAzAwAPAAgJWyRMBwAzAwAOAAEJ3hjYOQBJAAAAAA==.Telios:BAAALgAECgQJBQAAAA==.',
Th='Thaer:BAAALgADCgYJCgAAAA==.Thorendire:BAABLgAECn8kAAIbAAgJ4g72EQB7AQhoDAAABgAwAGkMAAAGACQAawwAAAYALgBqDAAABQAmAGwMAAAEACsAbQwAAAIAGADqDAAABQArAG4MAAACABcAGwAICeIO9hEAewEIaAwAAAYAMABpDAAABgAkAGsMAAAGAC4AagwAAAUAJgBsDAAABAArAG0MAAACABgA6gwAAAUAKwBuDAAAAgAXAAAA.',
Ti='Tirnz:BAABLgAECn8mAAIKAAgJugqIBwBMAQhoDAAABwAlAGkMAAAGABMAawwAAAUAGQBqDAAABAAgAGwMAAAEACMAbQwAAAMAHQDqDAAABgAbAG4MAAADABIACgAICboKiAcATAEIaAwAAAcAJQBpDAAABgATAGsMAAAFABkAagwAAAQAIABsDAAABAAjAG0MAAADAB0A6gwAAAYAGwBuDAAAAwASAAAA.',
To='Tohotstotrot:BAAALgADCgQJBAAAAA==.Torlana:BAAALgADCgYJBgAAAA==.',
Tr='Trafaros:BAAALgADCgMJAwAAAA==.Trilldh:BAAALgAECgcJBQAAAA==.Trixielou:BAAALgAECggJEAAAAA==.',
Tt='Ttattoo:BAEBLgAECn8YAAMgAAYJ5Qc6NADUAAZoDAAABQAdAGkMAAAEABcAawwAAAUAEABqDAAAAwATAGwMAAACABUA6gwAAAUACQAgAAYJ5Qc6NADUAAZoDAAABQAdAGkMAAAEABcAawwAAAUAEABqDAAAAwATAGwMAAABABUA6gwAAAUACQAUAAEJqAKwdwAbAAFsDAAAAQAGAAAA.Ttattooz:BAEALgADCgMJAwABLgAECgYJGAAgAOUHAA==.',
Ty='Tyramonde:BAAALgAECgYJBgAAAA==.',
Ub='Ubonrebu:BAAALgAFFAEJAQAAAA==.',
Va='Vaelestrix:BAACLgAFFH8XAAQBAAcJzRpuAwCyAQdoDAAABgBhAGkMAAAGAGIAawwAAAcAWgBqDAAAAQBOAGwMAAABABIA6gwAAAEAMwBuDAAAAQA4AAEABgmyHm4DALIBBmgMAAAFAGEAaQwAAAUAYgBrDAAABgBaAGoMAAABAE4A6gwAAAEAMwBuDAAAAQA4ACEAAwkMHGcDABYBA2gMAAABAFUAaQwAAAEAPQBrDAAAAQBEACIAAQlRBysGAF0AAWwMAAABABIALgAECn88AAMBAAkJ5iVuAADlAwABAAkJ5iVuAADlAwAiAAEJPyWEGABsAAAAAA==.Valholla:BAAALgADCgMJAwAAAA==.Vashtanerada:BAAALgADCgYJCgAAAA==.',
Ve='Veilish:BAAALgADCgYJCQAAAA==.',
Vo='Voiddøøde:BAAALgADCgcJBwAAAA==.Voidsocket:BAAALgAECgcJAQAAAA==.Voidtoes:BAAALgADCgYJBgAAAA==.',
Vu='Vulpvs:BAAALgADCgcJCwAAAA==.',
Vv='Vvlpvs:BAAALgADCgQJBAAAAA==.',
Wa='Warherald:BAABLgAECn8XAAMjAAYJRA9AGgD0AAZoDAAABgArAGkMAAAFACIAawwAAAQAMgBqDAAAAgAwAGwMAAACAB4A6gwAAAQAJAAjAAYJRA9AGgD0AAZoDAAABQArAGkMAAAEACIAawwAAAQAMgBqDAAAAgAwAGwMAAACAB4A6gwAAAMAJAAPAAMJAwV6VwBsAANoDAAAAQAMAGkMAAABABgA6gwAAAEAAQAAAA==.Wasntme:BAAALgADCgYJBgABLgAECgcJGwAYAL0KAA==.',
We='Wednesday:BAACLgAFFH8WAAIVAAcJwxHrAgCZAQdoDAAABAA3AGkMAAAEAEMAawwAAAQATwBqDAAAAgBLAG0MAAABABUA6gwAAAYALgBuDAAAAQACABUABwnDEesCAJkBB2gMAAAEADcAaQwAAAQAQwBrDAAABABPAGoMAAACAEsAbQwAAAEAFQDqDAAABgAuAG4MAAABAAIALgAECn8lAAIVAAgJLyRQBACNAgAVAAgJLyRQBACNAgAAAA==.',
Wh='Whoops:BAAALgADCgcJBwAAAA==.',
Xa='Xalaria:BAAALgAECgYJDAAAAA==.',
Xi='Xirek:BAABLgAECn8aAAIjAAYJ4Q8gGgD1AAZoDAAABgAZAGkMAAAFACkAawwAAAUAIgBqDAAAAwAXAGwMAAACADgA6gwAAAUALAAjAAYJ4Q8gGgD1AAZoDAAABgAZAGkMAAAFACkAawwAAAUAIgBqDAAAAwAXAGwMAAACADgA6gwAAAUALAAAAA==.',
Yr='Yreasak:BAABLgAECn8bAAMFAAcJdAf0aAAHAQdoDAAABQATAGkMAAAFABkAawwAAAUAIABqDAAABAAUAGwMAAADAA0A6gwAAAQAEQBuDAAAAQAFAAUABwkzBvRoAAcBB2gMAAAEAA4AaQwAAAQAGQBrDAAABAASAGoMAAAEABQAbAwAAAMADQDqDAAABAARAG4MAAABAAUAJAADCRcI/BoAngADaAwAAAEAEwBpDAAAAQAJAGsMAAABACAAAAA=.Yrisan:BAAALgADCgUJBQABLgAECgcJGwAFAHQHAA==.',
Ys='Yseulde:BAAALgADCgkJEQABLgAECgcJGwAFAHQHAA==.',
Zo='Zonako:BAAALgAECgcJEgAAAA==.Zoogranby:BAAALgADCgYJBgAAAA==.',
Zu='Zurâ:BAABLgAECn8XAAIVAAYJkQVGJgCnAAZoDAAABAAMAGkMAAAEABMAawwAAAQACgBqDAAABAAWAGwMAAADABEA6gwAAAQACwAVAAYJkQVGJgCnAAZoDAAABAAMAGkMAAAEABMAawwAAAQACgBqDAAABAAWAGwMAAADABEA6gwAAAQACwAAAA==.',
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
