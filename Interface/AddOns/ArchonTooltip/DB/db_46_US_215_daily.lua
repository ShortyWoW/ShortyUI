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
local provider = {region='US',realm='TheScryers',name='US',type='daily',zone=46,date='2026-05-10',data={Ae='Aelin:BAAALgAECgYJBwAAAA==.',
Ai='Airo:BAABLgAECn8wAAIBAAkJQxdwBwA7AgloDAAACABXAGkMAAAGAD4AawwAAAYAPgBqDAAABAA/AGwMAAAHAC4AbQwAAAQAVgDqDAAACQA6AG4MAAADACsAbwwAAAEAHQABAAkJQxdwBwA7AgloDAAACABXAGkMAAAGAD4AawwAAAYAPgBqDAAABAA/AGwMAAAHAC4AbQwAAAQAVgDqDAAACQA6AG4MAAADACsAbwwAAAEAHQAAAA==.',
Ak='Akaris:BAABLgAECn8WAAICAAYJXwWVOQDEAAZoDAAABQAJAGkMAAAEAA4AawwAAAQAFgBqDAAAAwALAGwMAAACAAwA6gwAAAQACQACAAYJXwWVOQDEAAZoDAAABQAJAGkMAAAEAA4AawwAAAQAFgBqDAAAAwALAGwMAAACAAwA6gwAAAQACQAAAA==.',
Al='Alainea:BAABLgAECn8UAAIDAAgJTgW6LAAPAQhoDAAABAAOAGkMAAADAA8AawwAAAMABgBqDAAAAgAMAGwMAAACABcAbQwAAAIACQDqDAAAAgAQAG4MAAACAAgAAwAICU4FuiwADwEIaAwAAAQADgBpDAAAAwAPAGsMAAADAAYAagwAAAIADABsDAAAAgAXAG0MAAACAAkA6gwAAAIAEABuDAAAAgAIAAAA.Alispia:BAAALgADCgUJBQAAAA==.',
Am='Amaterasu:BAABLgAFFH8JAAIEAAMJViB1FQATAQNoDAAAAwBWAGkMAAADAFsA6gwAAAMARwAEAAMJViB1FQATAQNoDAAAAwBWAGkMAAADAFsA6gwAAAMARwABLgAFFAMJCQAEAFYgAA==.Ambre:BAAALgAECgcJDQAAAA==.Amerdro:BAAALgAECgQJCQAAAA==.Amoreesa:BAAALgAECgQJBAAAAA==.',
An='Andross:BAAALgADCgcJEgABLgAECgcJGwAFAHQHAA==.Angrytestie:BAAALgAECgUJBQAAAA==.Anomaly:BAABLgAECn8sAAMGAAgJJSKRBACEAghoDAAABwBbAGkMAAAGAGAAawwAAAYAVgBqDAAABwBiAGwMAAAGAE8AbQwAAAIASADqDAAACABYAG4MAAACAGAABgAICSUikQQAhAIIaAwAAAcAWwBpDAAABQBgAGsMAAAGAFYAagwAAAcAYgBsDAAABgBPAG0MAAACAEgA6gwAAAcAWABuDAAAAgBgAAcAAgl2Dja5AFAAAmkMAAABAAMA6gwAAAEARgAAAA==.Anthousai:BAAALgADCgQJBAAAAA==.',
Ar='Ara:BAABLgAFFH8MAAIIAAYJARp+AwC7AQZoDAAAAgA8AGkMAAACAEsAawwAAAIAUgBqDAAAAQA+AGwMAAABACUA6gwAAAQAUgAIAAYJARp+AwC7AQZoDAAAAgA8AGkMAAACAEsAawwAAAIAUgBqDAAAAQA+AGwMAAABACUA6gwAAAQAUgAAAA==.',
As='Asylum:BAAALgADCgcJDQAAAA==.',
Au='Aura:BAAALgAECgMJAwAAAA==.',
Ax='Axl:BAABLgAECn8WAAMJAAYJ7gb1gQDqAAZoDAAABQAMAGkMAAAEABcAawwAAAQAEgBqDAAAAwAOAGwMAAACABEA6gwAAAQAEAAJAAYJ7gb1gQDqAAZoDAAABAAMAGkMAAAEABcAawwAAAQAEgBqDAAAAwAOAGwMAAACABEA6gwAAAQAEAAKAAEJ8QF1GgAhAAFoDAAAAQAEAAAA.',
Ay='Aylíth:BAAALgAFFAEJAQABLgAFFAMJCQAEAFYgAA==.',
Ba='Bacon:BAAALgADCgkJCQAAAA==.Bahdeeps:BAAALgAECgEJAQAAAA==.Bahheals:BAABLgAECn8UAAMLAAcJzgQdXQC1AAdoDAAAAwAZAGkMAAADAA0AawwAAAMABABqDAAAAgAEAGwMAAADAAYAbQwAAAEABADqDAAABQAaAAsABwnOBB1dALUAB2gMAAACABkAaQwAAAIADQBrDAAAAgAEAGoMAAACAAQAbAwAAAIABgBtDAAAAQAEAOoMAAAEABoADAAFCYUBbh4AdwAFaAwAAAEABABpDAAAAQAIAGsMAAABAAAAbAwAAAEAAADqDAAAAQAFAAAA.Banjoo:BAABLgAECn8aAAILAAgJfBsjGgD/AQhoDAAABAA8AGkMAAADAFAAawwAAAMAUgBqDAAAAwBDAGwMAAADAEoAbQwAAAMANwDqDAAABABMAG4MAAADAEIACwAICXwbIxoA/wEIaAwAAAQAPABpDAAAAwBQAGsMAAADAFIAagwAAAMAQwBsDAAAAwBKAG0MAAADADcA6gwAAAQATABuDAAAAwBCAAAA.Baruk:BAABLgAECn8cAAINAAgJ8BM0KQCIAQhoDAAABQAyAGkMAAAEADsAawwAAAQAQwBqDAAAAwBLAGwMAAAFADwAbQwAAAEAAgDqDAAABABFAG4MAAACABYADQAICfATNCkAiAEIaAwAAAUAMgBpDAAABAA7AGsMAAAEAEMAagwAAAMASwBsDAAABQA8AG0MAAABAAIA6gwAAAQARQBuDAAAAgAWAAAA.',
Be='Beauzericka:BAAALgADCgEJAQAAAA==.Beeswax:BAAALgADCgkJCQAAAA==.',
Bi='Bigçhungi:BAABLgAECn8YAAMOAAgJAx9hBgANAghoDAAAAwBGAGkMAAAEAFAAawwAAAQAUgBqDAAABABdAGwMAAAEAFkAbQwAAAEAQgDqDAAAAwBUAG4MAAABAFEADgAHCdIdYQYADQIHaAwAAAEAJwBpDAAAAQBQAGsMAAABAFIAagwAAAEAXQBsDAAAAQBZAOoMAAABAFQAbgwAAAEAUQAPAAcJlRdPGgCaAQdoDAAAAgBGAGkMAAADAC8AawwAAAMARwBqDAAAAwA6AGwMAAADAD0AbQwAAAEAQgDqDAAAAgAsAAEuAAUUBQkUAAkA4iEA.',
Bl='Blitzen:BAABLgAECn8lAAMQAAkJ3BqdAQBxAgloDAAABQBBAGkMAAAFAEQAawwAAAYASQBqDAAABABjAGwMAAAEAFIAbQwAAAMARgDqDAAABAA2AG4MAAAEAEAAbwwAAAIARgAQAAkJ3BqdAQBxAgloDAAABQBBAGkMAAAFAEQAawwAAAUASQBqDAAABABjAGwMAAAEAFIAbQwAAAMARgDqDAAABAA2AG4MAAAEAEAAbwwAAAIARgARAAEJswRNSwArAAFrDAAAAQAMAAAA.',
Bo='Borealiss:BAAALgAECgYJBwABLgAECgkJJQAQANwaAA==.',
Br='Brewjigsaw:BAAALgADCgcJCgAAAA==.',
Bu='Buffsubordie:BAAALgAFFAEJAQAAAA==.',
Bw='Bwonsamdi:BAABLgAECn9EAAIDAAgJhCARDwC2AghoDAAACgBeAGkMAAAKAFcAawwAAAoAWABqDAAACgBSAGwMAAAIAGAAbQwAAAQAQgDqDAAADABaAG4MAAAEADsAAwAICYQgEQ8AtgIIaAwAAAoAXgBpDAAACgBXAGsMAAAKAFgAagwAAAoAUgBsDAAACABgAG0MAAAEAEIA6gwAAAwAWgBuDAAABAA7AAAA.',
['Bâ']='Bârks:BAABLgAECn8aAAISAAYJKCBUDgALAgZoDAAABgBbAGkMAAAFAFUAawwAAAUAUwBqDAAAAwBaAGwMAAACAEgA6gwAAAUARgASAAYJKCBUDgALAgZoDAAABgBbAGkMAAAFAFUAawwAAAUAUwBqDAAAAwBaAGwMAAACAEgA6gwAAAUARgAAAA==.',
Ca='Callia:BAAALgAECgQJBAAAAA==.Camazotz:BAAALgADCgUJBQAAAA==.Cardkun:BAAALgADCgIJAgAAAA==.Carp:BAABLgAECn8aAAITAAYJKgq6GgChAAZoDAAABQANAGkMAAAFABkAawwAAAUAHABqDAAABAAmAGwMAAACACcA6gwAAAUAGAATAAYJKgq6GgChAAZoDAAABQANAGkMAAAFABkAawwAAAUAHABqDAAABAAmAGwMAAACACcA6gwAAAUAGAAAAA==.',
Ch='Chargerkun:BAAALgAECgMJCwAAAA==.Chayda:BAAALgADCgEJAQAAAA==.Choleena:BAABLgAECn8aAAINAAYJvxgGJQChAQZoDAAABgBJAGkMAAAFAEAAawwAAAUALQBqDAAAAwBQAGwMAAACAD4A6gwAAAUANAANAAYJvxgGJQChAQZoDAAABgBJAGkMAAAFAEAAawwAAAUALQBqDAAAAwBQAGwMAAACAD4A6gwAAAUANAAAAA==.',
Ci='Cindress:BAAALgADCgEJAQAAAA==.',
Co='Combat:BAAALgAECgYJDwAAAA==.Coojotwo:BAAALgAECgUJDAAAAA==.',
Cr='Crewd:BAAALgADCgEJAQAAAA==.Crimzon:BAAALgAECgEJAQAAAA==.',
Da='Dangerfloof:BAAALgADCgQJCAAAAA==.Dangerwithin:BAACLgAFFH8jAAMUAAgJpCMZAACrAghoDAAABgBjAGkMAAAGAGMAawwAAAYAXwBqDAAABABjAGwMAAADAE0AbQwAAAIAQgDqDAAABwBkAG4MAAABAGMAFAAHCYUkGQAAqwIHaAwAAAYAYwBpDAAABgBjAGsMAAAGAF8AagwAAAQAYwBtDAAAAgBCAOoMAAAHAGQAbgwAAAEAYwAIAAEJrh0+JQBZAAFsDAAAAwBLAC4ABAp/JgACFAAJCcomMwAA+wMAFAAJCcomMwAA+wMAAS4ABRQDCQkABABWIAA=.Danklazercat:BAAALgADCgcJDgABLgAFFAUJFAAJAOIhAA==.Darius:BAABLgAFFH8FAAIVAAMJ6gxUFQC3AANoDAAAAQAbAGkMAAACACYA6gwAAAIAIAAVAAMJ6gxUFQC3AANoDAAAAQAbAGkMAAACACYA6gwAAAIAIAAAAA==.Dastraz:BAAALgAECgYJDgAAAA==.',
De='Decay:BAAALgAECgMJAwAAAA==.Deebz:BAABLgAECn8ZAAMWAAYJARxvCgBWAQZoDAAABQBOAGkMAAAFAEoAawwAAAUAQQBqDAAAAwBAAGwMAAACAEcA6gwAAAUARAAHAAYJ/hnTNwBwAQZoDAAAAQBOAGkMAAABAEoAawwAAAEAQQBqDAAAAgA5AGwMAAABAC4A6gwAAAEARAAWAAYJQxhvCgBWAQZoDAAABAA4AGkMAAAEAEUAawwAAAQALwBqDAAAAQBAAGwMAAABAEcA6gwAAAQAQQAAAA==.Devkra:BAAALgADCggJDgAAAA==.',
Dm='Dmgabsorb:BAAALgADCgIJAgAAAA==.',
Do='Doge:BAAALgADCgkJCQAAAA==.',
Dr='Dragoneux:BAAALgAFFAIJAwAAAQ==.',
Du='Dudemachine:BAAALgADCgUJBQABLgADCgkJEwAXAAAAAA==.',
['Dè']='Dèèbz:BAAALgADCgQJBAAAAA==.',
['Dö']='Dörf:BAAALgADCgMJAwAAAA==.',
Ed='Eddison:BAAALgADCgkJCQAAAA==.',
En='Enchanted:BAABLgAECn8XAAMVAAcJgBiLGAAUAQdoDAAABQA4AGkMAAAEADgAawwAAAQAPABqDAAAAwA5AGwMAAADAEQA6gwAAAMASABuDAAAAQA+ABUABgnqFIsYABQBBmgMAAADAB4AaQwAAAMANwBrDAAAAwA8AGoMAAADADkAbAwAAAIARADqDAAAAgA0AAkABgkkFiarAJoABmgMAAACADgAaQwAAAEAOABrDAAAAQAxAGwMAAABACoA6gwAAAEASABuDAAAAQA+AAAA.Enid:BAACLgAFFH8mAAIVAAcJPCYKAAAFAwdoDAAABgBkAGkMAAAGAGMAawwAAAYAYwBqDAAABwBjAGwMAAAFAGEAbQwAAAEAWgDqDAAABwBjABUABwk8JgoAAAUDB2gMAAAGAGQAaQwAAAYAYwBrDAAABgBjAGoMAAAHAGMAbAwAAAUAYQBtDAAAAQBaAOoMAAAHAGMALgAECn8ZAAIVAAgJqSZaAQB+AwAVAAgJqSZaAQB+AwAAAA==.',
Es='Eskanor:BAAALgADCgQJBgAAAA==.',
Et='Eternalwrath:BAAALgAECgYJDAAAAA==.',
Eu='Eublar:BAAALgAECgEJAQAAAA==.',
Fa='Falzemphx:BAAALgAECgMJBgAAAA==.Farbringer:BAAALgAECgUJBgABLgAECgYJDgAXAAAAAA==.Fayanna:BAAALgADCgEJAQAAAA==.',
Fe='Felicitee:BAAALgAECgMJAwAAAA==.',
Fo='Foxxylady:BAABLgAECn8dAAIHAAcJZx7HIwDKAQdoDAAABgBcAGkMAAAFAF8AawwAAAYAUABqDAAAAwBfAGwMAAABAEsA6gwAAAcAPQBuDAAAAQA9AAcABwlnHscjAMoBB2gMAAAGAFwAaQwAAAUAXwBrDAAABgBQAGoMAAADAF8AbAwAAAEASwDqDAAABwA9AG4MAAABAD0AAAA=.',
Fu='Furbees:BAAALgAECgUJEAAAAA==.',
Ge='Geenon:BAAALgAECgMJBgAAAA==.Gephen:BAAALgADCgUJBQAAAA==.',
Gr='Grakdeez:BAAALgAECgUJBwABLgAECgkJEAAXAAAAAA==.Grakfist:BAAALgAECgkJEAAAAA==.Graubard:BAAALgAECgEJAQAAAA==.Gravec:BAAALgADCgEJAQAAAA==.Grimswhisper:BAAALgAECgYJDQAAAA==.Gritchen:BAABLgAECn8YAAMSAAYJYR1yEQDiAQZoDAAAAwBLAGkMAAAFAFEAawwAAAQAPQBqDAAAAwBdAGwMAAADAEIA6gwAAAYASQASAAYJYR1yEQDiAQZoDAAAAwBLAGkMAAAFAFEAawwAAAMAPQBqDAAAAgBdAGwMAAACAEIA6gwAAAYASQAYAAMJNAKgVwAzAANrDAAAAQAIAGoMAAABAA0AbAwAAAEAAgAAAA==.Growler:BAAALgAECgYJEAAAAA==.Grynsel:BAABLgAECn8aAAIHAAYJOxAGTwAiAQZoDAAABgAmAGkMAAAFAC0AawwAAAUAHwBqDAAAAwBBAGwMAAACADoA6gwAAAUAIgAHAAYJOxAGTwAiAQZoDAAABgAmAGkMAAAFAC0AawwAAAUAHwBqDAAAAwBBAGwMAAACADoA6gwAAAUAIgAAAA==.',
Ha='Harlynne:BAAALgADCgkJCQAAAA==.',
Ho='Holios:BAAALgADCgYJBgABLgAECgcJGwAYAL0KAA==.',
Hu='Huntwix:BAAALgADCgYJBgAAAA==.',
Id='Idontknow:BAABLgAECn8bAAIYAAcJvQqPIgA4AQdoDAAABQAxAGkMAAAGACQAawwAAAYAIABqDAAABAAZAGwMAAADABMA6gwAAAIAEwBuDAAAAQAIABgABwm9Co8iADgBB2gMAAAFADEAaQwAAAYAJABrDAAABgAgAGoMAAAEABkAbAwAAAMAEwDqDAAAAgATAG4MAAABAAgAAAA=.',
Ii='Iilia:BAAALgAECgQJBAAAAA==.',
In='Inwe:BAABLgAECn8WAAMMAAYJCwo8GgCnAAZoDAAABQAdAGkMAAAFABcAawwAAAUAFABqDAAAAwAVAGwMAAABABwA6gwAAAMAGwAMAAUJ5Qk8GgCnAAVoDAAAAwAdAGkMAAADABcAawwAAAMAFABqDAAAAgAVAGwMAAABABwACwAFCR4COnQAbgAFaAwAAAIABABpDAAAAgAIAGsMAAACAAcAagwAAAEAAwDqDAAAAwADAAAA.',
Je='Jeemana:BAAALgADCgYJBgAAAA==.',
Jo='Johnnydodge:BAABLgAECn8eAAIPAAgJKAz9HQB/AQhoDAAABgAnAGkMAAAFABoAawwAAAUAIQBqDAAABAAnAGwMAAAEACMAbQwAAAIACwDqDAAAAwAqAG4MAAABABwADwAICSgM/R0AfwEIaAwAAAYAJwBpDAAABQAaAGsMAAAFACEAagwAAAQAJwBsDAAABAAjAG0MAAACAAsA6gwAAAMAKgBuDAAAAQAcAAAA.Joyride:BAABLgAECn8aAAMZAAYJdxucDAB+AQZoDAAABgBTAGkMAAAFAFAAawwAAAUANABqDAAAAwA6AGwMAAACAEsA6gwAAAUAOwAZAAYJdxucDAB+AQZoDAAABQBTAGkMAAAFAFAAawwAAAUANABqDAAAAwA6AGwMAAACAEsA6gwAAAUAOwAaAAEJ5A4hRAEyAAFoDAAAAQAmAAAA.',
Ju='Jujuwing:BAAALgAECgQJBgAAAA==.',
['Jù']='Jùde:BAAALgAECgQJBQAAAA==.',
Ka='Kaidastraza:BAAALgADCgcJCgAAAA==.Kaliel:BAAALgADCgUJBQAAAA==.Kalthas:BAAALgAECgEJAQAAAA==.Kanrethad:BAAALgAECgkJEwAAAA==.',
Ke='Kerrygan:BAABLgAECn8XAAIbAAYJdQ76GwAJAQZoDAAABAAxAGkMAAAEACIAawwAAAQAIQBqDAAABAAnAGwMAAADACMA6gwAAAQAIAAbAAYJdQ76GwAJAQZoDAAABAAxAGkMAAAEACIAawwAAAQAIQBqDAAABAAnAGwMAAADACMA6gwAAAQAIAAAAA==.',
Kh='Khaed:BAABLgAECn8ZAAIcAAkJHhHpEQCYAQloDAAABAAvAGkMAAAEADcAawwAAAIAJQBqDAAAAwAgAGwMAAABABQAbQwAAAEAJADqDAAABQBPAG4MAAAEADYAbwwAAAEAEwAcAAkJHhHpEQCYAQloDAAABAAvAGkMAAAEADcAawwAAAIAJQBqDAAAAwAgAGwMAAABABQAbQwAAAEAJADqDAAABQBPAG4MAAAEADYAbwwAAAEAEwAAAA==.',
Ki='Kicat:BAAALgADCgYJCgAAAA==.Kilmister:BAAALgADCgkJFwABLgAECgEJAQAXAAAAAA==.Kinara:BAAALgAECgIJAgAAAA==.',
Ko='Korthank:BAABLgAECn8WAAMcAAgJeh8oCgAvAghoDAAAAwBfAGkMAAADAFQAawwAAAMAVwBqDAAAAgBfAGwMAAACADEAbQwAAAEAPwDqDAAABQBbAG4MAAADAFwAHAAICXofKAoALwIIaAwAAAIAXwBpDAAAAwBUAGsMAAADAFcAagwAAAIAXwBsDAAAAgAxAG0MAAABAD8A6gwAAAUAWwBuDAAAAwBcAA0AAQldEI+kACsAAWgMAAABACkAAAA=.Koruka:BAAALgADCgEJAQAAAA==.Kozatri:BAAALgADCgcJEwAAAA==.',
Kr='Krentead:BAAALgADCgYJBgAAAA==.',
Kw='Kwissy:BAABLgAECn8UAAIHAAYJyQS+agDWAAZoDAAABAARAGkMAAAEAA4AawwAAAMACQBqDAAAAwAWAGwMAAADAAoA6gwAAAMACAAHAAYJyQS+agDWAAZoDAAABAARAGkMAAAEAA4AawwAAAMACQBqDAAAAwAWAGwMAAADAAoA6gwAAAMACAAAAA==.',
La='Labellanotte:BAABLgAECn8ZAAMLAAYJ8AVIYQCoAAZoDAAABQAIAGkMAAAFABcAawwAAAUADQBqDAAAAwAWAGwMAAACAAwA6gwAAAUACgALAAYJ8AVIYQCoAAZoDAAAAwAIAGkMAAADABcAawwAAAQADQBqDAAAAgAWAGwMAAACAAwA6gwAAAUACgAMAAQJqQaiHQCCAARoDAAAAgAWAGkMAAACABAAawwAAAEADABqDAAAAQAVAAAA.Lamastrasz:BAAALgAECgEJAQAAAA==.Landao:BAAALgAECgQJBAAAAA==.Laturalus:BAAALgADCgUJBQAAAA==.Layssa:BAABLgAECn8WAAMdAAcJ1BWFHABeAQdoDAAAAgAhAGkMAAADACgAawwAAAMAOgBqDAAAAwAfAGwMAAADAEQA6gwAAAQARwBuDAAABAA+AB0ABwnUFYUcAF4BB2gMAAABACEAaQwAAAIAKABrDAAAAgA6AGoMAAACAB8AbAwAAAIARADqDAAABABHAG4MAAAEAD4ACwAFCd4ITYMA0QAFaAwAAAEAFgBpDAAAAQAWAGsMAAABAAwAagwAAAEAGgBsDAAAAQAdAAAA.',
Li='Liliania:BAABLgAECn8XAAMeAAgJUgecDAATAQhoDAAAAgAEAGkMAAACAA4AawwAAAMACwBqDAAAAwAOAGwMAAAFAB0AbQwAAAIADQDqDAAABAAdAG4MAAACABwAHgAICVIHnAwAEwEIaAwAAAIABABpDAAAAgAOAGsMAAACAAsAagwAAAIADgBsDAAABQAdAG0MAAACAA0A6gwAAAQAHQBuDAAAAgAcAAUAAgmSARAzARoAAmsMAAABAAQAagwAAAEAAgAAAA==.Limper:BAAALgADCgMJAwAAAA==.Lizuket:BAAALgADCgYJBgAAAA==.',
Lo='Loveles:BAAALgADCgUJBQAAAA==.',
Lu='Lucry:BAAALgADCgkJDgAAAA==.Lucyford:BAABLgAECn8YAAMaAAYJjxgSWgBHAQZoDAAABQA+AGkMAAAEADwAawwAAAQAPgBqDAAAAwBKAGwMAAADAEMA6gwAAAUAPQAaAAYJjxgSWgBHAQZoDAAAAwA+AGkMAAADADwAawwAAAMAPgBqDAAAAgBKAGwMAAACAEMA6gwAAAQAPQAEAAYJUBkiLwAoAQZoDAAAAgBJAGkMAAABADgAawwAAAEARQBqDAAAAQBIAGwMAAABAFoA6gwAAAEAGQAAAA==.Lunafloof:BAAALgAECgYJDAAAAA==.Lunaiya:BAAALgAECgUJDQAAAA==.Lunarfang:BAAALgAECgEJAQAAAA==.Lunarosa:BAAALgADCgkJCQABLgAECgEJAQAXAAAAAA==.',
Ly='Lyraali:BAABLgAECn8WAAIHAAYJ8hehOwBiAQZoDAAABgBGAGkMAAAEAEEAawwAAAQAQwBqDAAAAgAmAGwMAAABAC4A6gwAAAUAOAAHAAYJ8hehOwBiAQZoDAAABgBGAGkMAAAEAEEAawwAAAQAQwBqDAAAAgAmAGwMAAABAC4A6gwAAAUAOAAAAA==.',
Ma='Magemode:BAABLgAECn8YAAIfAAYJyCHhTgBKAgZoDAAABABLAGkMAAAEAF4AawwAAAQAVQBqDAAABABJAGwMAAAEAFcA6gwAAAQAWgAfAAYJyCHhTgBKAgZoDAAABABLAGkMAAAEAF4AawwAAAQAVQBqDAAABABJAGwMAAAEAFcA6gwAAAQAWgAAAA==.Maomaow:BAAALgADCggJCAAAAA==.Mara:BAAALgADCgYJDwAAAA==.Mavramaria:BAAALgADCgYJCgAAAA==.',
Me='Melzemphx:BAAALgAECgYJEQAAAA==.',
Mi='Mikeberetta:BAAALgADCgMJAwAAAA==.Miniz:BAAALgADCgcJBwAAAA==.Minlea:BAAALgADCggJCAAAAA==.Misirlou:BAAALgADCgMJAwABLgAECgkJJQAQANwaAA==.Mizchivf:BAAALgADCgQJBgAAAA==.',
Mo='Mogal:BAAALgADCgEJAQAAAA==.Moktezuma:BAAALgAECgQJBAAAAA==.Moosifer:BAAALgADCgYJBgAAAA==.Morodos:BAAALgADCgkJFAAAAA==.',
Mu='Murtaugh:BAAALgADCgUJBQAAAA==.Mutekii:BAAALgAECgQJBAAAAA==.',
Na='Natrel:BAAALgAECgYJEgAAAA==.',
Ne='Neema:BAAALgAECgEJAwAAAA==.Nemmael:BAAALgADCgcJDwAAAA==.',
No='Noctogero:BAAALgADCgcJBwAAAA==.Nosibm:BAAALgADCgkJEgAAAA==.',
Ny='Nyxes:BAAALgADCgMJAwAAAA==.',
['Nê']='Nêo:BAAALgADCgcJBwAAAA==.',
Oc='Octane:BAAALgAECgEJAQAAAA==.Octozm:BAAALgAFFAIJBAAAAA==.',
Or='Oreofrosting:BAAALgADCgkJEwAAAA==.',
Pa='Palmstrike:BAAALgADCgEJAQAAAA==.Pañdø:BAAALgADCgMJAwAAAA==.',
Pe='Penderrin:BAAALgADCggJDgAAAA==.',
Pi='Pidia:BAAALgADCgUJCAAAAA==.',
Po='Popes:BAACLgAFFH8JAAMHAAQJeA6MIQAeAQRoDAAAAwBCAGkMAAACAC8AawwAAAEACQDqDAAAAwAZAAcABAkYCIwhAB4BBGgMAAACAAoAaQwAAAIALwBrDAAAAQAJAOoMAAACAA8AFgACCeYR/RwAogACaAwAAAEAQgDqDAAAAQAZAC4ABAp/GAADFgAJCV0bdh8AKgIAFgAICRkddh8AKgIABwACCcYTwIkAigAAAAA=.Popper:BAAALgADCgIJAgAAAA==.',
Pr='Preservation:BAAALgAFFAMJAwAAAA==.Prey:BAAALgADCgMJAwAAAA==.Pruina:BAAALgADCgEJAQAAAA==.',
Pu='Pub:BAAALgAECgYJDQAAAA==.',
Py='Pyrø:BAAALgAECgEJAQAAAA==.',
Ra='Radhika:BAAALgAECgIJAwAAAA==.Raelos:BAAALgAECgcJEQAAAA==.Ragebait:BAABLgAECn8aAAIaAAYJNRkMSQB0AQZoDAAABgBKAGkMAAAFAD4AawwAAAUARgBqDAAAAwBQAGwMAAACADUA6gwAAAUAPgAaAAYJNRkMSQB0AQZoDAAABgBKAGkMAAAFAD4AawwAAAUARgBqDAAAAwBQAGwMAAACADUA6gwAAAUAPgAAAA==.Raiha:BAAALgADCgUJBQAAAA==.Ranikina:BAAALgAECgYJEgAAAA==.Raynor:BAAALgADCgIJAgAAAA==.',
Re='Regasus:BAAALgAECgYJCQAAAA==.Revolt:BAABLgAECn8nAAIYAAgJrhv1CwATAghoDAAABwBJAGkMAAAGAEUAawwAAAYAVQBqDAAABQA+AGwMAAAEAFMAbQwAAAMAJADqDAAABgBPAG4MAAACAEQAGAAICa4b9QsAEwIIaAwAAAcASQBpDAAABgBFAGsMAAAGAFUAagwAAAUAPgBsDAAABABTAG0MAAADACQA6gwAAAYATwBuDAAAAgBEAAAA.Reïna:BAABLgAECn8UAAIeAAYJaA0gDgD7AAZoDAAABgAbAGkMAAAEACgAawwAAAQAJABqDAAAAwAjAGwMAAABACIA6gwAAAIAHwAeAAYJaA0gDgD7AAZoDAAABgAbAGkMAAAEACgAawwAAAQAJABqDAAAAwAjAGwMAAABACIA6gwAAAIAHwAAAA==.',
Rh='Rheía:BAAALgADCgYJBgABLgAFFAMJCQAEAFYgAA==.',
Ro='Roükai:BAAALgAECgQJBQAAAA==.',
Ry='Ryuruko:BAAALgAECgUJBQAAAA==.',
Sa='Sahariel:BAABLgAECn8mAAMSAAgJJx+sDQAVAghoDAAABQBNAGkMAAAFAGAAawwAAAUAUgBqDAAABQBUAGwMAAAGAE0AbQwAAAIANQDqDAAABwBaAG4MAAADAEsAEgAICScfrA0AFQIIaAwAAAQATQBpDAAABABgAGsMAAAEAFIAagwAAAQAVABsDAAABQBNAG0MAAACADUA6gwAAAYAWgBuDAAAAgBLABgABwnBE90ZAHoBB2gMAAABACkAaQwAAAEABABrDAAAAQBAAGoMAAABAC0AbAwAAAEASQDqDAAAAQBAAG4MAAABADcAAAA=.',
Sc='Schwartpheil:BAAALgAECgYJEAAAAA==.Schwartzbann:BAAALgADCgcJCgABLgAECgYJEAAXAAAAAA==.Scilla:BAAALgADCgEJAQABLgAECgEJAQAXAAAAAA==.',
Sh='Shadowballz:BAAALgAECggJEQAAAA==.Shadowwing:BAAALgAECgMJBwAAAA==.Shamnorris:BAAALgADCgQJBAAAAA==.Shardemma:BAAALgADCgkJGQAAAA==.Shelfy:BAAALgAECgQJDwAAAA==.Shreddedbeef:BAAALgADCgcJBwAAAA==.Shytningbolt:BAAALgADCgMJAgAAAA==.Shælyn:BAAALgAECgMJBgAAAA==.',
Sk='Skitzo:BAAALgADCgkJFgAAAA==.',
Sp='Spinetaker:BAABLgAECn8mAAIUAAgJGSK0AwDEAghoDAAABQBeAGkMAAAFAF8AawwAAAYAXQBqDAAABABLAGwMAAAFAF0A6gwAAAcAWgBuDAAABABUAG8MAAACADoAFAAICRkitAMAxAIIaAwAAAUAXgBpDAAABQBfAGsMAAAGAF0AagwAAAQASwBsDAAABQBdAOoMAAAHAFoAbgwAAAQAVABvDAAAAgA6AAEuAAUUBQkUAAkA4iEA.Spyder:BAAALgADCgQJBAAAAA==.',
St='Stolensouls:BAABLgAECn8XAAMeAAYJzA/rDAANAQZoDAAABgAkAGkMAAAFADkAawwAAAUALABqDAAAAwAWAGwMAAABACMA6gwAAAMAHAAeAAYJzA/rDAANAQZoDAAABQAkAGkMAAAFADkAawwAAAUALABqDAAAAwAWAGwMAAABACMA6gwAAAMAHAAFAAEJegERMwEaAAFoDAAAAQADAAAA.Strawkun:BAAALgAECgIJAwAAAA==.',
Su='Sunaris:BAAALgADCgUJBQAAAA==.Suneater:BAAALgAECgQJBAAAAA==.',
['Sç']='Sçruffy:BAACLgAFFH8UAAMJAAUJ4iGDHgBpAQVoDAAABQBaAGkMAAAFAE8AawwAAAMAVQBqDAAAAwBgAOoMAAAEAFsACQAECeIhgx4AaQEEaAwAAAUAWgBpDAAABQBPAGsMAAADAFUA6gwAAAQAWwAVAAEJAABzEwBXAAFqDAAAAwBgAC4ABAp/OwACCQAJCXsmDAUAgwMACQAJCXsmDAUAgwMAAAA=.',
Ta='Tahtiania:BAAALgADCgYJCwAAAA==.Talas:BAAALgADCgEJAQAAAA==.Taliesin:BAAALgADCgUJBQAAAA==.',
Te='Teldryn:BAACLgAFFH8MAAIPAAQJ9BF/EwAiAQRoDAAABABMAGkMAAADADYAawwAAAIABQDqDAAAAwAwAA8ABAn0EX8TACIBBGgMAAAEAEwAaQwAAAMANgBrDAAAAgAFAOoMAAADADAALgAECn8iAAMPAAgJWyRLBwAzAwAPAAgJWyRLBwAzAwAOAAEJ3hjXOQBJAAAAAA==.Telios:BAAALgAECgQJBQAAAA==.',
Th='Thaer:BAAALgADCgYJCgAAAA==.Thorendire:BAABLgAECn8kAAIbAAgJ4g6CEQB7AQhoDAAABgAwAGkMAAAGACQAawwAAAYALgBqDAAABQAmAGwMAAAEACsAbQwAAAIAGADqDAAABQArAG4MAAACABcAGwAICeIOghEAewEIaAwAAAYAMABpDAAABgAkAGsMAAAGAC4AagwAAAUAJgBsDAAABAArAG0MAAACABgA6gwAAAUAKwBuDAAAAgAXAAAA.',
Ti='Tirnz:BAABLgAECn8mAAIKAAgJugo8BwBMAQhoDAAABwAlAGkMAAAGABMAawwAAAUAGQBqDAAABAAgAGwMAAAEACMAbQwAAAMAHQDqDAAABgAbAG4MAAADABIACgAICboKPAcATAEIaAwAAAcAJQBpDAAABgATAGsMAAAFABkAagwAAAQAIABsDAAABAAjAG0MAAADAB0A6gwAAAYAGwBuDAAAAwASAAAA.',
To='Tohotstotrot:BAAALgADCgQJBAAAAA==.Torlana:BAAALgADCgYJBgAAAA==.',
Tr='Trafaros:BAAALgADCgMJAwAAAA==.Trilldh:BAAALgAECgcJBQAAAA==.Trixielou:BAAALgAECggJEAAAAA==.',
Tt='Ttattoo:BAEBLgAECn8YAAMgAAYJ5Qc6MwDUAAZoDAAABQAdAGkMAAAEABcAawwAAAUAEABqDAAAAwATAGwMAAACABUA6gwAAAUACQAgAAYJ5Qc6MwDUAAZoDAAABQAdAGkMAAAEABcAawwAAAUAEABqDAAAAwATAGwMAAABABUA6gwAAAUACQAUAAEJqAItdQAbAAFsDAAAAQAGAAAA.Ttattooz:BAEALgADCgMJAwABLgAECgYJGAAgAOUHAA==.',
Ty='Tyramonde:BAAALgAECgYJBgAAAA==.',
Ub='Ubonrebu:BAAALgAFFAEJAQAAAA==.',
Va='Vaelestrix:BAACLgAFFH8XAAQBAAcJzRodAwC1AQdoDAAABgBhAGkMAAAGAGIAawwAAAcAWgBqDAAAAQBOAGwMAAABABIA6gwAAAEAMwBuDAAAAQA4AAEABgmyHh0DALUBBmgMAAAFAGEAaQwAAAUAYgBrDAAABgBaAGoMAAABAE4A6gwAAAEAMwBuDAAAAQA4ACEAAwkMHEADABYBA2gMAAABAFUAaQwAAAEAPQBrDAAAAQBEACIAAQlRBysGAF0AAWwMAAABABIALgAECn86AAMBAAkJ5iVuAADlAwABAAkJ5iVuAADlAwAiAAEJPyWEGABsAAAAAA==.Valholla:BAAALgADCgMJAwAAAA==.Vashtanerada:BAAALgADCgYJCgAAAA==.',
Ve='Veilish:BAAALgADCgYJCQAAAA==.',
Vo='Voiddøøde:BAAALgADCgcJBwAAAA==.Voidsocket:BAAALgAECgcJAQAAAA==.Voidtoes:BAAALgADCgYJBgAAAA==.',
Vu='Vulpvs:BAAALgADCgcJCwAAAA==.',
Vv='Vvlpvs:BAAALgADCgQJBAAAAA==.',
Wa='Warherald:BAABLgAECn8XAAMjAAYJRA+PGQD1AAZoDAAABgArAGkMAAAFACIAawwAAAQAMgBqDAAAAgAwAGwMAAACAB4A6gwAAAQAJAAjAAYJRA+PGQD1AAZoDAAABQArAGkMAAAEACIAawwAAAQAMgBqDAAAAgAwAGwMAAACAB4A6gwAAAMAJAAPAAMJAwWNVQBtAANoDAAAAQAMAGkMAAABABgA6gwAAAEAAQAAAA==.Wasntme:BAAALgADCgYJBgABLgAECgcJGwAYAL0KAA==.',
We='Wednesday:BAACLgAFFH8WAAIVAAcJwxHrAgCZAQdoDAAABAA3AGkMAAAEAEMAawwAAAQATwBqDAAAAgBLAG0MAAABABUA6gwAAAYALgBuDAAAAQACABUABwnDEesCAJkBB2gMAAAEADcAaQwAAAQAQwBrDAAABABPAGoMAAACAEsAbQwAAAEAFQDqDAAABgAuAG4MAAABAAIALgAECn8lAAIVAAgJLyQhBACNAgAVAAgJLyQhBACNAgAAAA==.',
Wh='Whoops:BAAALgADCgcJBwAAAA==.',
Xa='Xalaria:BAAALgAECgYJDAAAAA==.',
Xi='Xirek:BAABLgAECn8aAAIjAAYJ4Q96GQD2AAZoDAAABgAZAGkMAAAFACkAawwAAAUAIgBqDAAAAwAXAGwMAAACADgA6gwAAAUALAAjAAYJ4Q96GQD2AAZoDAAABgAZAGkMAAAFACkAawwAAAUAIgBqDAAAAwAXAGwMAAACADgA6gwAAAUALAAAAA==.',
Yr='Yreasak:BAABLgAECn8bAAMFAAcJdAc2ZwAFAQdoDAAABQATAGkMAAAFABkAawwAAAUAIABqDAAABAAUAGwMAAADAA0A6gwAAAQAEQBuDAAAAQAFAAUABwkzBjZnAAUBB2gMAAAEAA4AaQwAAAQAGQBrDAAABAASAGoMAAAEABQAbAwAAAMADQDqDAAABAARAG4MAAABAAUAJAADCRcI/BoAngADaAwAAAEAEwBpDAAAAQAJAGsMAAABACAAAAA=.Yrisan:BAAALgADCgUJBQABLgAECgcJGwAFAHQHAA==.',
Ys='Yseulde:BAAALgADCgkJEQABLgAECgcJGwAFAHQHAA==.',
Zo='Zonako:BAAALgAECgcJEgAAAA==.Zoogranby:BAAALgADCgYJBgAAAA==.',
Zu='Zurâ:BAABLgAECn8XAAIVAAYJkQWAJQCnAAZoDAAABAAMAGkMAAAEABMAawwAAAQACgBqDAAABAAWAGwMAAADABEA6gwAAAQACwAVAAYJkQWAJQCnAAZoDAAABAAMAGkMAAAEABMAawwAAAQACgBqDAAABAAWAGwMAAADABEA6gwAAAQACwAAAA==.',
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
