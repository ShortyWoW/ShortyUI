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

local lookup = {'Rogue-Subtlety','Evoker-Augmentation','Shaman-Elemental','Paladin-Holy','Warlock-Demonology','Hunter-Survival','Hunter-BeastMastery','Monk-Mistweaver','DeathKnight-Unholy','DeathKnight-Frost','Druid-Restoration','Druid-Feral','Shaman-Restoration','Warrior-Arms','Warrior-Fury','Warrior-Protection','Evoker-Devastation','Evoker-Preservation','Priest-Holy','Druid-Guardian','Monk-Windwalker','DeathKnight-Blood','Hunter-Marksmanship','Unknown-Unknown','Priest-Shadow','Paladin-Protection','Paladin-Retribution','Warlock-Affliction','DemonHunter-Havoc','Shaman-Enhancement','Druid-Balance','Warlock-Destruction','Mage-Frost','Monk-Brewmaster','Rogue-Outlaw','Rogue-Assassination',}
local provider = {region='US',realm='TheScryers',name='US',type='daily',zone=46,date='2026-05-16',data={Ae='Aelin:BAAALgAECgYJBwAAAA==.',
Ai='Airo:BAABLgAECn8wAAIBAAkJQxeKDQD/AQloDAAACABXAGkMAAAGAD4AawwAAAYAPgBqDAAABAA/AGwMAAAHAC4AbQwAAAQAVgDqDAAACQA6AG4MAAADACsAbwwAAAEAHQABAAkJQxeKDQD/AQloDAAACABXAGkMAAAGAD4AawwAAAYAPgBqDAAABAA/AGwMAAAHAC4AbQwAAAQAVgDqDAAACQA6AG4MAAADACsAbwwAAAEAHQAAAA==.',
Ak='Akaris:BAABLgAECn8ZAAICAAYJXwXuSQCwAAZoDAAABQAJAGkMAAAEAA4AawwAAAQAFgBqDAAAAwALAGwMAAAEAAwA6gwAAAUACQACAAYJXwXuSQCwAAZoDAAABQAJAGkMAAAEAA4AawwAAAQAFgBqDAAAAwALAGwMAAAEAAwA6gwAAAUACQAAAA==.',
Al='Alainea:BAABLgAECn8VAAIDAAgJbgWmOQD4AAhoDAAABAAOAGkMAAADAA8AawwAAAMABgBqDAAAAgAMAGwMAAACABcAbQwAAAIACQDqDAAAAgAQAG4MAAADAAsAAwAICW4FpjkA+AAIaAwAAAQADgBpDAAAAwAPAGsMAAADAAYAagwAAAIADABsDAAAAgAXAG0MAAACAAkA6gwAAAIAEABuDAAAAwALAAAA.Alispia:BAAALgADCgUJBQAAAA==.',
Am='Amaterasu:BAABLgAFFH8MAAIEAAMJViDXGQAKAQNoDAAABABWAGkMAAAEAFsA6gwAAAQARwAEAAMJViDXGQAKAQNoDAAABABWAGkMAAAEAFsA6gwAAAQARwABLgAFFAMJDAAEAFYgAA==.Ambre:BAAALgAECgcJDQAAAA==.Amerdro:BAAALgAECgQJCQAAAA==.Amoreesa:BAAALgAECgQJBAAAAA==.',
An='Andross:BAAALgADCgcJEgABLgAECgcJGwAFAHQHAA==.Angrytestie:BAAALgAECgUJBQAAAA==.Anomaly:BAACLgAFFH8FAAIGAAIJLiUCFwDKAAJoDAAABABdAGkMAAABAGAABgACCS4lAhcAygACaAwAAAQAXQBpDAAAAQBgAC4ABAp/LAADBgAICSUiRwkATgIABgAICSUiRwkATgIABwACCXYONrkAUAAAAAA=.Anthousai:BAAALgADCgQJBAAAAA==.',
Ar='Ara:BAABLgAFFH8MAAIIAAYJARqAAwC7AQZoDAAAAgA8AGkMAAACAEsAawwAAAIAUgBqDAAAAQA+AGwMAAABACUA6gwAAAQAUgAIAAYJARqAAwC7AQZoDAAAAgA8AGkMAAACAEsAawwAAAIAUgBqDAAAAQA+AGwMAAABACUA6gwAAAQAUgAAAA==.',
As='Asylum:BAAALgADCgcJDQAAAA==.',
Au='Aura:BAAALgAECgMJAwAAAA==.',
Ax='Axl:BAABLgAECn8ZAAMJAAYJKAd4pADaAAZoDAAABQAMAGkMAAAEABcAawwAAAQAEgBqDAAAAwAOAGwMAAAEABQA6gwAAAUAEAAJAAYJKAd4pADaAAZoDAAABAAMAGkMAAAEABcAawwAAAQAEgBqDAAAAwAOAGwMAAAEABQA6gwAAAUAEAAKAAEJ8QF2GgAhAAFoDAAAAQAEAAAA.',
Ay='Aylíth:BAAALgAFFAEJAQABLgAFFAMJDAAEAFYgAA==.',
Ba='Bacon:BAAALgADCgkJCQAAAA==.Bahdeeps:BAAALgAECgQJBQAAAA==.Bahheals:BAABLgAECn8VAAMLAAcJXAX4aQC0AAdoDAAAAwAZAGkMAAADAA0AawwAAAQADgBqDAAAAgAEAGwMAAADAAYAbQwAAAEABADqDAAABQAaAAsABwlcBfhpALQAB2gMAAACABkAaQwAAAIADQBrDAAAAwAOAGoMAAACAAQAbAwAAAIABgBtDAAAAQAEAOoMAAAEABoADAAFCYUB0SUAbgAFaAwAAAEABABpDAAAAQAIAGsMAAABAAAAbAwAAAEAAADqDAAAAQAFAAAA.Banjoo:BAABLgAECn8bAAILAAgJfBsSIgDzAQhoDAAABAA8AGkMAAADAFAAawwAAAMAUgBqDAAAAwBDAGwMAAADAEoAbQwAAAMANwDqDAAABQBMAG4MAAADAEIACwAICXwbEiIA8wEIaAwAAAQAPABpDAAAAwBQAGsMAAADAFIAagwAAAMAQwBsDAAAAwBKAG0MAAADADcA6gwAAAUATABuDAAAAwBCAAAA.Baruk:BAABLgAECn8lAAINAAgJ6RTlMADDAQhoDAAABgAyAGkMAAAFADsAawwAAAUAQwBqDAAABQBLAGwMAAAGADwAbQwAAAIABwDqDAAABQBFAG4MAAADACYADQAICekU5TAAwwEIaAwAAAYAMgBpDAAABQA7AGsMAAAFAEMAagwAAAUASwBsDAAABgA8AG0MAAACAAcA6gwAAAUARQBuDAAAAwAmAAAA.',
Be='Beauzericka:BAAALgADCgEJAQAAAA==.Beeswax:BAAALgADCgkJCQAAAA==.',
Bi='Bigçhungi:BAABLgAECn8hAAQOAAkJoBulCgDsAQloDAAABABGAGkMAAAFAFAAawwAAAUAUgBqDAAABQBdAGwMAAAFAFkAbQwAAAIAQgDqDAAABABUAG4MAAACAFEAbwwAAAEACgAOAAkJ5xalCgDsAQloDAAAAgAnAGkMAAACAFAAawwAAAIAUgBqDAAAAgBdAGwMAAACAFkAbQwAAAEAAQDqDAAAAQBUAG4MAAABAFEAbwwAAAEACgAPAAcJlRfOJwBvAQdoDAAAAgBGAGkMAAADAC8AawwAAAMARwBqDAAAAwA6AGwMAAADAD0AbQwAAAEAQgDqDAAAAgAsABAAAgkBAGRLAAEAAuoMAAABAAAAbgwAAAEAAAABLgAFFAYJFgAJAIYhAA==.',
Bl='Blitzen:BAABLgAECn8lAAMRAAkJ3BqxAgBMAgloDAAABQBBAGkMAAAFAEQAawwAAAYASQBqDAAABABjAGwMAAAEAFIAbQwAAAMARgDqDAAABAA2AG4MAAAEAEAAbwwAAAIARgARAAkJ3BqxAgBMAgloDAAABQBBAGkMAAAFAEQAawwAAAUASQBqDAAABABjAGwMAAAEAFIAbQwAAAMARgDqDAAABAA2AG4MAAAEAEAAbwwAAAIARgASAAEJswRPSwArAAFrDAAAAQAMAAAA.',
Bo='Borealiss:BAAALgAECgYJBwABLgAECgkJJQARANwaAA==.',
Br='Brewjigsaw:BAAALgADCgcJCgAAAA==.',
Bu='Buffsubordie:BAAALgAFFAEJAQAAAA==.',
Bw='Bwonsamdi:BAABLgAECn9EAAIDAAgJhCATDwC2AghoDAAACgBeAGkMAAAKAFcAawwAAAoAWABqDAAACgBSAGwMAAAIAGAAbQwAAAQAQgDqDAAADABaAG4MAAAEADsAAwAICYQgEw8AtgIIaAwAAAoAXgBpDAAACgBXAGsMAAAKAFgAagwAAAoAUgBsDAAACABgAG0MAAAEAEIA6gwAAAwAWgBuDAAABAA7AAAA.',
['Bâ']='Bârks:BAABLgAECn8gAAITAAcJlB+dDABSAgdoDAAABwBbAGkMAAAGAFUAawwAAAYAUwBqDAAABABaAGwMAAADAFoA6gwAAAUARgBuDAAAAQA1ABMABwmUH50MAFICB2gMAAAHAFsAaQwAAAYAVQBrDAAABgBTAGoMAAAEAFoAbAwAAAMAWgDqDAAABQBGAG4MAAABADUAAAA=.',
Ca='Callia:BAAALgAECgcJDAAAAA==.Camazotz:BAAALgADCgUJBQAAAA==.Cardkun:BAAALgADCgIJAgAAAA==.Carp:BAABLgAECn8gAAIUAAYJ4goOJgChAAZoDAAABgANAGkMAAAGABkAawwAAAYAIwBqDAAABQAtAGwMAAADACcA6gwAAAYAGwAUAAYJ4goOJgChAAZoDAAABgANAGkMAAAGABkAawwAAAYAIwBqDAAABQAtAGwMAAADACcA6gwAAAYAGwAAAA==.',
Ch='Chargerkun:BAAALgAECgMJCwAAAA==.Chayda:BAAALgADCgEJAQAAAA==.Choleena:BAABLgAECn8gAAINAAcJERbOKgC4AQdoDAAABwBJAGkMAAAGAEAAawwAAAYALQBqDAAABABQAGwMAAADAEIA6gwAAAUANABuDAAAAQAMAA0ABwkRFs4qALgBB2gMAAAHAEkAaQwAAAYAQABrDAAABgAtAGoMAAAEAFAAbAwAAAMAQgDqDAAABQA0AG4MAAABAAwAAAA=.',
Ci='Cindress:BAAALgADCgEJAQAAAA==.',
Co='Combat:BAAALgAECgYJDwAAAA==.Coojotwo:BAAALgAECgUJDAAAAA==.',
Cr='Crewd:BAAALgADCgEJAQAAAA==.Crimzon:BAAALgAECgEJAQAAAA==.',
Da='Dangerfloof:BAAALgADCgQJCAAAAA==.Dangerwithin:BAACLgAFFH8kAAMVAAgJpCM7AACjAghoDAAABgBjAGkMAAAGAGMAawwAAAYAXwBqDAAABABjAGwMAAADAE0AbQwAAAIAQgDqDAAACABkAG4MAAABAGMAFQAHCYUkOwAAowIHaAwAAAYAYwBpDAAABgBjAGsMAAAGAF8AagwAAAQAYwBtDAAAAgBCAOoMAAAIAGQAbgwAAAEAYwAIAAEJrh3HLQBVAAFsDAAAAwBLAC4ABAp/JgACFQAJCcomMwAA+wMAFQAJCcomMwAA+wMAAS4ABRQDCQwABABWIAA=.Danklazercat:BAAALgADCgcJDgABLgAFFAYJFgAJAIYhAA==.Darius:BAABLgAFFH8HAAIWAAMJkA/kGAC6AANoDAAAAgAdAGkMAAACACYA6gwAAAMAMwAWAAMJkA/kGAC6AANoDAAAAgAdAGkMAAACACYA6gwAAAMAMwAAAA==.Dastraz:BAAALgAECgcJEAAAAA==.',
De='Decay:BAAALgAECgkJDQAAAA==.Deebz:BAABLgAECn8fAAQHAAcJqRhAQwCCAQdoDAAABgBOAGkMAAAGAEoAawwAAAYAQQBqDAAABABAAGwMAAADAEcA6gwAAAUARABuDAAAAQAUAAcABwn8FkBDAIIBB2gMAAABAE4AaQwAAAEASgBrDAAAAQBBAGoMAAACADkAbAwAAAEALgDqDAAAAQBEAG4MAAABABQAFwAGCUMYoA8A7QAGaAwAAAQAOABpDAAABABFAGsMAAAEAC8AagwAAAEAQABsDAAAAQBHAOoMAAAEAEEABgAFCYIJ9y4A2AAFaAwAAAEAHQBpDAAAAQAkAGsMAAABABoAagwAAAEAJgBsDAAAAQAEAAAA.Devkra:BAAALgADCggJDgAAAA==.',
Dm='Dmgabsorb:BAAALgADCgIJAgAAAA==.',
Do='Doge:BAAALgADCgkJCQAAAA==.',
Dr='Dragoneux:BAAALgAFFAMJBQAAAQ==.',
Du='Dudemachine:BAAALgADCgUJBQABLgADCgkJEwAYAAAAAA==.',
['Dè']='Dèèbz:BAAALgADCgQJBgAAAA==.',
['Dö']='Dörf:BAAALgADCgMJAwAAAA==.',
Ed='Eddison:BAAALgADCgkJCQAAAA==.',
En='Enchanted:BAABLgAECn8XAAMWAAcJgBgcHgD9AAdoDAAABQA4AGkMAAAEADgAawwAAAQAPABqDAAAAwA5AGwMAAADAEQA6gwAAAMASABuDAAAAQA+ABYABgnqFBweAP0ABmgMAAADAB4AaQwAAAMANwBrDAAAAwA8AGoMAAADADkAbAwAAAIARADqDAAAAgA0AAkABgkkFiSqANAABmgMAAACADgAaQwAAAEAOABrDAAAAQAxAGwMAAABACoA6gwAAAEASABuDAAAAQA+AAAA.Enid:BAACLgAFFH8nAAIWAAcJPCYKAAAFAwdoDAAABwBkAGkMAAAGAGMAawwAAAYAYwBqDAAABwBjAGwMAAAFAGEAbQwAAAEAWgDqDAAABwBjABYABwk8JgoAAAUDB2gMAAAHAGQAaQwAAAYAYwBrDAAABgBjAGoMAAAHAGMAbAwAAAUAYQBtDAAAAQBaAOoMAAAHAGMALgAECn8cAAIWAAgJsSZZAQB+AwAWAAgJsSZZAQB+AwAAAA==.',
Es='Eskanor:BAAALgADCgQJBgAAAA==.',
Et='Eternalwrath:BAAALgAECgcJEgAAAA==.',
Eu='Eublar:BAAALgAECgEJAQAAAA==.',
Fa='Falzemphx:BAAALgAECgQJCAAAAA==.Farbringer:BAAALgAECgUJBgABLgAECgcJEAAYAAAAAA==.Fayanna:BAAALgADCgEJAQAAAA==.',
Fe='Felicitee:BAAALgAECgMJAwAAAA==.',
Fo='Foxxylady:BAABLgAECn8dAAIHAAcJZx7iOACoAQdoDAAABgBcAGkMAAAFAF8AawwAAAYAUABqDAAAAwBfAGwMAAABAEsA6gwAAAcAPQBuDAAAAQA9AAcABwlnHuI4AKgBB2gMAAAGAFwAaQwAAAUAXwBrDAAABgBQAGoMAAADAF8AbAwAAAEASwDqDAAABwA9AG4MAAABAD0AAAA=.',
Fu='Furbees:BAAALgAECgUJEAAAAA==.',
Ge='Geenon:BAAALgAECgQJCgAAAA==.Gephen:BAAALgADCgUJBQAAAA==.',
Gr='Grakdeez:BAAALgAECgcJDAABLgAECgkJEAAYAAAAAA==.Grakfist:BAAALgAECgkJEAAAAA==.Graubard:BAAALgAECgEJAQAAAA==.Gravec:BAAALgADCgEJAQAAAA==.Grimswhisper:BAAALgAECgYJDQAAAA==.Gritchen:BAABLgAECn8aAAMTAAcJPxqxEwDzAQdoDAAAAwBLAGkMAAAFAFEAawwAAAQAPQBqDAAAAwBdAGwMAAADAEIA6gwAAAcASQBuDAAAAQATABMABwk/GrETAPMBB2gMAAADAEsAaQwAAAUAUQBrDAAAAwA9AGoMAAACAF0AbAwAAAIAQgDqDAAABwBJAG4MAAABABMAGQADCTQC6WYALQADawwAAAEACABqDAAAAQANAGwMAAABAAIAAAA=.Growler:BAAALgAECgYJEAAAAA==.Grynsel:BAABLgAECn8gAAIHAAcJ6A2/VwBDAQdoDAAABwAmAGkMAAAGAC0AawwAAAYAHwBqDAAABABBAGwMAAADADoA6gwAAAUAIgBuDAAAAQAFAAcABwnoDb9XAEMBB2gMAAAHACYAaQwAAAYALQBrDAAABgAfAGoMAAAEAEEAbAwAAAMAOgDqDAAABQAiAG4MAAABAAUAAAA=.',
Ha='Harlynne:BAAALgADCgkJCQAAAA==.Harukav:BAAALgADCgIJAgAAAA==.',
Ho='Holios:BAAALgADCgYJBgABLgAECgcJGwAZAL0KAA==.',
Hu='Huntwix:BAAALgADCgYJBgAAAA==.',
Id='Idontknow:BAABLgAECn8bAAIZAAcJvQq1LAAeAQdoDAAABQAxAGkMAAAGACQAawwAAAYAIABqDAAABAAZAGwMAAADABMA6gwAAAIAEwBuDAAAAQAIABkABwm9CrUsAB4BB2gMAAAFADEAaQwAAAYAJABrDAAABgAgAGoMAAAEABkAbAwAAAMAEwDqDAAAAgATAG4MAAABAAgAAAA=.',
Ii='Iilia:BAAALgAECgQJBAAAAA==.',
In='Inwe:BAABLgAECn8WAAMMAAYJCwqRIQCUAAZoDAAABQAdAGkMAAAFABcAawwAAAUAFABqDAAAAwAVAGwMAAABABwA6gwAAAMAGwAMAAUJ5QmRIQCUAAVoDAAAAwAdAGkMAAADABcAawwAAAMAFABqDAAAAgAVAGwMAAABABwACwAFCR4CIYgAZAAFaAwAAAIABABpDAAAAgAIAGsMAAACAAcAagwAAAEAAwDqDAAAAwADAAAA.',
Je='Jeemana:BAAALgADCgYJBgAAAA==.',
Jo='Johnnydodge:BAABLgAECn8eAAIPAAgJKAyHKgBgAQhoDAAABgAnAGkMAAAFABoAawwAAAUAIQBqDAAABAAnAGwMAAAEACMAbQwAAAIACwDqDAAAAwAqAG4MAAABABwADwAICSgMhyoAYAEIaAwAAAYAJwBpDAAABQAaAGsMAAAFACEAagwAAAQAJwBsDAAABAAjAG0MAAACAAsA6gwAAAMAKgBuDAAAAQAcAAAA.Joyride:BAABLgAECn8gAAMaAAcJ4hrPCwC0AQdoDAAABwBTAGkMAAAGAFAAawwAAAYAOABqDAAABAA6AGwMAAADAEsA6gwAAAUAOwBuDAAAAQA4ABoABwniGs8LALQBB2gMAAAGAFMAaQwAAAYAUABrDAAABgA4AGoMAAAEADoAbAwAAAMASwDqDAAABQA7AG4MAAABADgAGwABCeQOJEQBMgABaAwAAAEAJgAAAA==.',
Ju='Jujuwing:BAAALgAECgcJEgAAAA==.',
['Jù']='Jùde:BAAALgAECgQJCQAAAA==.',
Ka='Kaidastraza:BAAALgADCgcJCgAAAA==.Kaliel:BAAALgADCgUJBQAAAA==.Kalthas:BAAALgAECgEJAQAAAA==.Kanrethad:BAABLgAECn8UAAMFAAkJWSOEBQAPAwloDAAAAgBdAGkMAAACAFsAawwAAAIAUgBqDAAAAgBgAGwMAAACAGMAbQwAAAIAUQDqDAAAAgBgAG4MAAAEAFMAbwwAAAIAXwAFAAkJWSOEBQAPAwloDAAAAgBdAGkMAAACAFsAawwAAAIAUgBqDAAAAQBgAGwMAAACAGMAbQwAAAIAUQDqDAAAAgBgAG4MAAAEAFMAbwwAAAIAXwAcAAEJAAD8KwAAAAFqDAAAAQBYAAAA.',
Ke='Kerrygan:BAABLgAECn8XAAIdAAYJdQ7gIwD0AAZoDAAABAAxAGkMAAAEACIAawwAAAQAIQBqDAAABAAnAGwMAAADACMA6gwAAAQAIAAdAAYJdQ7gIwD0AAZoDAAABAAxAGkMAAAEACIAawwAAAQAIQBqDAAABAAnAGwMAAADACMA6gwAAAQAIAAAAA==.',
Kh='Khaed:BAABLgAECn8ZAAIeAAkJHhHpEQCYAQloDAAABAAvAGkMAAAEADcAawwAAAIAJQBqDAAAAwAgAGwMAAABABQAbQwAAAEAJADqDAAABQBPAG4MAAAEADYAbwwAAAEAEwAeAAkJHhHpEQCYAQloDAAABAAvAGkMAAAEADcAawwAAAIAJQBqDAAAAwAgAGwMAAABABQAbQwAAAEAJADqDAAABQBPAG4MAAAEADYAbwwAAAEAEwAAAA==.',
Ki='Kicat:BAAALgADCgYJCgAAAA==.Kilmister:BAAALgADCgkJFwABLgAECgEJAQAYAAAAAA==.Kinara:BAAALgAECgIJAgAAAA==.',
Ko='Korthank:BAACLgAFFH8FAAIeAAMJOxvCBQAFAQNoDAAAAwBVAGkMAAABAEEA6gwAAAEAOQAeAAMJOxvCBQAFAQNoDAAAAwBVAGkMAAABAEEA6gwAAAEAOQAuAAQKfxcAAx4ACQlfICkKAC8CAB4ACQlfICkKAC8CAA0AAQldEI+kACsAAAAA.Koruka:BAAALgADCgEJAQAAAA==.Kozatri:BAAALgADCgcJEwAAAA==.',
Kr='Krentead:BAAALgADCgYJBgAAAA==.',
Kw='Kwissy:BAABLgAECn8aAAIHAAYJ0wX4fwDfAAZoDAAABQASAGkMAAAFAA4AawwAAAQACQBqDAAABAAWAGwMAAAEAAoA6gwAAAQAFQAHAAYJ0wX4fwDfAAZoDAAABQASAGkMAAAFAA4AawwAAAQACQBqDAAABAAWAGwMAAAEAAoA6gwAAAQAFQAAAA==.',
La='Labellanotte:BAABLgAECn8fAAMLAAcJcwXHaQC0AAdoDAAABgAIAGkMAAAGABcAawwAAAYADQBqDAAABAAWAGwMAAADAAwA6gwAAAUACgBuDAAAAQAGAAsABwlzBcdpALQAB2gMAAADAAgAaQwAAAMAFwBrDAAABAANAGoMAAACABYAbAwAAAIADADqDAAABQAKAG4MAAABAAYADAAFCawG3iEAkgAFaAwAAAMAFgBpDAAAAwASAGsMAAACAAwAagwAAAIAFQBsDAAAAQAOAAAA.Lamastrasz:BAAALgAECgEJAQAAAA==.Landao:BAAALgAECgQJBAAAAA==.Lateron:BAAALgADCgYJBgAAAA==.Laturalus:BAAALgADCgUJBQAAAA==.Layssa:BAABLgAECn8YAAMfAAcJShbfJQBEAQdoDAAAAgAhAGkMAAADACgAawwAAAMAOgBqDAAABAArAGwMAAAEAEsA6gwAAAQARwBuDAAABAA+AB8ABwlKFt8lAEQBB2gMAAABACEAaQwAAAIAKABrDAAAAgA6AGoMAAADACsAbAwAAAMASwDqDAAABABHAG4MAAAEAD4ACwAFCd4IUIMA0QAFaAwAAAEAFgBpDAAAAQAWAGsMAAABAAwAagwAAAEAGgBsDAAAAQAdAAAA.',
Li='Lightarrow:BAAALgAECgcJBwAAAA==.Liliania:BAABLgAECn8XAAMgAAgJUgdiEADwAAhoDAAAAgAEAGkMAAACAA4AawwAAAMACwBqDAAAAwAOAGwMAAAFAB0AbQwAAAIADQDqDAAABAAdAG4MAAACABwAIAAICVIHYhAA8AAIaAwAAAIABABpDAAAAgAOAGsMAAACAAsAagwAAAIADgBsDAAABQAdAG0MAAACAA0A6gwAAAQAHQBuDAAAAgAcAAUAAgmSAREzARoAAmsMAAABAAQAagwAAAEAAgAAAA==.Limper:BAAALgADCgMJAwAAAA==.Lizuket:BAAALgADCgYJCwAAAA==.',
Lo='Loveles:BAAALgADCgUJBQAAAA==.',
Lu='Lucry:BAAALgADCgkJDgAAAA==.Lucyford:BAABLgAECn8eAAMEAAYJziFhEQBCAgZoDAAABgBcAGkMAAAFAFkAawwAAAUAUgBqDAAABABXAGwMAAAEAFoA6gwAAAYASwAEAAYJziFhEQBCAgZoDAAAAwBcAGkMAAACAFkAawwAAAIAUgBqDAAAAgBXAGwMAAACAFoA6gwAAAIASwAbAAYJjxiHdgA3AQZoDAAAAwA+AGkMAAADADwAawwAAAMAPgBqDAAAAgBKAGwMAAACAEMA6gwAAAQAPQAAAA==.Lunafloof:BAAALgAECgcJEgAAAA==.Lunaiya:BAAALgAECgUJDQAAAA==.Lunarfang:BAAALgAECgEJAQAAAA==.Lunarosa:BAAALgADCgkJCQABLgAECgEJAQAYAAAAAA==.',
Ly='Lyraali:BAABLgAECn8XAAIHAAcJzBcYQQCKAQdoDAAABgBGAGkMAAAEAEEAawwAAAQAQwBqDAAAAgAmAGwMAAABAC4A6gwAAAUAOABuDAAAAQA7AAcABwnMFxhBAIoBB2gMAAAGAEYAaQwAAAQAQQBrDAAABABDAGoMAAACACYAbAwAAAEALgDqDAAABQA4AG4MAAABADsAAAA=.',
Ma='Magemode:BAABLgAECn8YAAIhAAYJyCHjTgBKAgZoDAAABABLAGkMAAAEAF4AawwAAAQAVQBqDAAABABJAGwMAAAEAFcA6gwAAAQAWgAhAAYJyCHjTgBKAgZoDAAABABLAGkMAAAEAF4AawwAAAQAVQBqDAAABABJAGwMAAAEAFcA6gwAAAQAWgAAAA==.Maomaow:BAAALgADCggJCAAAAA==.Mara:BAAALgADCgYJEQAAAA==.Mavramaria:BAAALgADCgYJCgAAAA==.',
Me='Melzemphx:BAABLgAECn8XAAMVAAYJQQfEOQDMAAZoDAAABQARAGkMAAAEABQAawwAAAQAFwBqDAAAAwAUAGwMAAACAA8A6gwAAAUAEAAVAAYJQQfEOQDMAAZoDAAAAwARAGkMAAADABQAawwAAAMAFwBqDAAAAgAUAGwMAAACAA8A6gwAAAMAEAAIAAUJrANqUwCBAAVoDAAAAgAJAGkMAAABAAgAawwAAAEABwBqDAAAAQAJAOoMAAACAAsAAAA=.',
Mi='Mikeberetta:BAAALgADCgMJAwAAAA==.Miniz:BAAALgADCgcJBwAAAA==.Minlea:BAAALgADCggJCAAAAA==.Misirlou:BAAALgAECgYJBgABLgAECgkJJQARANwaAA==.Mizchivf:BAAALgADCgQJBgAAAA==.',
Mo='Mogal:BAAALgADCgEJAQAAAA==.Moktezuma:BAAALgAECgQJBAAAAA==.Moosifer:BAAALgADCgYJBgAAAA==.Morodos:BAAALgADCgkJFAAAAA==.',
Mu='Murtaugh:BAAALgADCgcJCgAAAA==.Mutekii:BAAALgAECgcJDQAAAA==.',
Na='Natrel:BAABLgAECn8YAAMNAAYJIR7oHwD7AQZoDAAABQBjAGkMAAAFAFYAawwAAAQAVwBqDAAAAwAxAGwMAAADADcA6gwAAAQAVAANAAYJIR7oHwD7AQZoDAAABABjAGkMAAAEAFYAawwAAAMAVwBqDAAAAgAxAGwMAAACADcA6gwAAAMAVAADAAYJ/QZrRwC/AAZoDAAAAQANAGkMAAABABEAawwAAAEAEABqDAAAAQASAGwMAAABABEA6gwAAAEAGAAAAA==.',
Ne='Neema:BAAALgAECgEJAwAAAA==.Nemmael:BAAALgADCgcJDwAAAA==.',
No='Noctogero:BAAALgADCgcJBwAAAA==.Nosibm:BAAALgADCgkJEgAAAA==.Notabutt:BAAALgADCgYJBgAAAA==.',
Ny='Nyxes:BAAALgADCgMJAwAAAA==.',
['Nê']='Nêo:BAAALgADCgcJBwAAAA==.',
Oc='Octane:BAAALgAECgEJAQABLgAECgQJBAAYAAAAAA==.Octozm:BAABLgAFFH8HAAIhAAIJoyQTMwDRAAJoDAAAAwBaAOoMAAAEAGEAIQACCaMkEzMA0QACaAwAAAMAWgDqDAAABABhAAAA.',
Or='Oreofrosting:BAAALgADCgkJEwAAAA==.',
Pa='Palmstrike:BAAALgAECgEJAQAAAA==.Pañdø:BAAALgADCgMJAwAAAA==.',
Pe='Penderrin:BAAALgADCggJDgAAAA==.',
Pi='Pidia:BAAALgADCgUJCAAAAA==.',
Po='Popes:BAACLgAFFH8JAAMHAAQJeA57LAALAQRoDAAAAwBCAGkMAAACAC8AawwAAAEACQDqDAAAAwAZAAcABAkYCHssAAsBBGgMAAACAAoAaQwAAAIALwBrDAAAAQAJAOoMAAACAA8AFwACCeYRAx0AogACaAwAAAEAQgDqDAAAAQAZAC4ABAp/GAADFwAJCV0beR8AKgIAFwAICRkdeR8AKgIABwACCcYTiqQAiAAAAAA=.Popper:BAAALgADCgIJAgAAAA==.',
Pr='Preservation:BAAALgAFFAMJAwAAAA==.Prey:BAAALgADCgMJAwAAAA==.Pruina:BAAALgADCgEJAQAAAA==.',
Pu='Pub:BAAALgAECgYJDQAAAA==.',
Py='Pyrø:BAAALgAECgEJAQAAAA==.',
Ra='Radhika:BAAALgAECgIJAwAAAA==.Raelos:BAAALgAECggJEwAAAA==.Ragebait:BAABLgAECn8gAAIbAAcJDxmXSQCjAQdoDAAABwBKAGkMAAAGAD4AawwAAAYASABqDAAABABQAGwMAAADADUA6gwAAAUAPgBuDAAAAQA8ABsABwkPGZdJAKMBB2gMAAAHAEoAaQwAAAYAPgBrDAAABgBIAGoMAAAEAFAAbAwAAAMANQDqDAAABQA+AG4MAAABADwAAAA=.Raiha:BAAALgADCgUJBQAAAA==.Ranikina:BAAALgAECgYJEgAAAA==.Raynor:BAAALgADCgIJAgAAAA==.',
Re='Regasus:BAAALgAECgYJCQAAAA==.Revolt:BAACLgAFFH8HAAIZAAMJugn2GADYAANoDAAAAwAvAGkMAAACAAcA6gwAAAIAEwAZAAMJugn2GADYAANoDAAAAwAvAGkMAAACAAcA6gwAAAIAEwAuAAQKfy8AAhkACQkCH/UFALsCABkACQkCH/UFALsCAAAA.Reïna:BAABLgAECn8UAAIgAAYJaA1DEQDlAAZoDAAABgAbAGkMAAAEACgAawwAAAQAJABqDAAAAwAjAGwMAAABACIA6gwAAAIAHwAgAAYJaA1DEQDlAAZoDAAABgAbAGkMAAAEACgAawwAAAQAJABqDAAAAwAjAGwMAAABACIA6gwAAAIAHwAAAA==.',
Rh='Rheía:BAAALgADCgYJBgABLgAFFAMJDAAEAFYgAA==.',
Ro='Roükai:BAAALgAECgQJBQAAAA==.',
Ry='Ryuruko:BAAALgAECgYJBgAAAA==.',
Sa='Sahariel:BAABLgAECn8sAAMTAAkJwh8gBgDVAgloDAAABgBNAGkMAAAGAGAAawwAAAYAVgBqDAAABQBUAGwMAAAGAE0AbQwAAAIANQDqDAAACABaAG4MAAAEAE0AbwwAAAEAVgATAAkJwh8gBgDVAgloDAAABQBNAGkMAAAFAGAAawwAAAUAVgBqDAAABABUAGwMAAAFAE0AbQwAAAIANQDqDAAABwBaAG4MAAADAE0AbwwAAAEAVgAZAAcJwRO7IgBdAQdoDAAAAQApAGkMAAABAAQAawwAAAEAQABqDAAAAQAtAGwMAAABAEkA6gwAAAEAQABuDAAAAQA3AAAA.',
Sc='Schwartpheil:BAAALgAECgYJEAAAAA==.Schwartzbann:BAAALgADCgcJCgABLgAECgYJEAAYAAAAAA==.Scilla:BAAALgADCgEJAQABLgAECgEJAQAYAAAAAA==.',
Sh='Shadowballz:BAAALgAECggJEQAAAA==.Shadowwing:BAAALgAECgMJBwAAAA==.Shamnorris:BAAALgADCgQJBAAAAA==.Shardemma:BAAALgADCgkJGQAAAA==.Shelfy:BAAALgAECgQJDwAAAA==.Shimmerly:BAAALgAECgQJBAAAAA==.Shreddedbeef:BAAALgADCgcJBwAAAA==.Shytningbolt:BAAALgADCgMJAgAAAA==.Shælyn:BAAALgAECgMJBgAAAA==.',
Sk='Skitzo:BAAALgADCgkJFgAAAA==.',
Sp='Spinetaker:BAABLgAECn8tAAIVAAgJGSJLBgCnAghoDAAABgBeAGkMAAAGAF8AawwAAAcAXQBqDAAABQBLAGwMAAAGAF0A6gwAAAgAWgBuDAAABQBUAG8MAAACADoAFQAICRkiSwYApwIIaAwAAAYAXgBpDAAABgBfAGsMAAAHAF0AagwAAAUASwBsDAAABgBdAOoMAAAIAFoAbgwAAAUAVABvDAAAAgA6AAEuAAUUBgkWAAkAhiEA.Spyder:BAAALgADCgQJBAAAAA==.',
St='Stolensouls:BAABLgAECn8XAAMgAAYJzA/kDwD3AAZoDAAABgAkAGkMAAAFADkAawwAAAUALABqDAAAAwAWAGwMAAABACMA6gwAAAMAHAAgAAYJzA/kDwD3AAZoDAAABQAkAGkMAAAFADkAawwAAAUALABqDAAAAwAWAGwMAAABACMA6gwAAAMAHAAFAAEJegESMwEaAAFoDAAAAQADAAAA.Strawkun:BAAALgAECgIJAwAAAA==.',
Su='Sunaris:BAAALgADCgUJBQAAAA==.Suneater:BAAALgAECgUJCQAAAA==.',
['Sç']='Sçruffy:BAACLgAFFH8WAAMJAAYJhiHPDwBgAQZoDAAABQBaAGkMAAAFAE8AawwAAAMAVQBqDAAAAwBgAG0MAAABAFIA6gwAAAUAWwAJAAUJhiHPDwBgAQVoDAAABQBaAGkMAAAFAE8AawwAAAMAVQBtDAAAAQBSAOoMAAAFAFsAFgABCQAAeBMAVwABagwAAAMAYAAuAAQKfz4AAgkACQl7JgsFAIMDAAkACQl7JgsFAIMDAAAA.',
Ta='Tahtiania:BAAALgADCgYJCwAAAA==.Talas:BAAALgADCgEJAQAAAA==.Taliesin:BAAALgADCgUJBQAAAA==.',
Te='Teldryn:BAACLgAFFH8QAAIPAAQJPRhKEQA7AQRoDAAABQBMAGkMAAAEADgAawwAAAMAOwDqDAAABAA4AA8ABAk9GEoRADsBBGgMAAAFAEwAaQwAAAQAOABrDAAAAwA7AOoMAAAEADgALgAECn8kAAMPAAgJWyRMBwAzAwAPAAgJWyRMBwAzAwAOAAEJ3hjXOQBJAAAAAA==.Telios:BAAALgAECgQJBQAAAA==.',
Th='Thaer:BAAALgADCgYJCgAAAA==.Thorendire:BAABLgAECn8oAAIdAAgJvA9YFgBwAQhoDAAABwAwAGkMAAAHACQAawwAAAYALgBqDAAABgAnAGwMAAAEACsAbQwAAAIAGADqDAAABgA7AG4MAAACABcAHQAICbwPWBYAcAEIaAwAAAcAMABpDAAABwAkAGsMAAAGAC4AagwAAAYAJwBsDAAABAArAG0MAAACABgA6gwAAAYAOwBuDAAAAgAXAAAA.',
Ti='Tirnz:BAABLgAECn8mAAIKAAgJugr1CwA7AQhoDAAABwAlAGkMAAAGABMAawwAAAUAGQBqDAAABAAgAGwMAAAEACMAbQwAAAMAHQDqDAAABgAbAG4MAAADABIACgAICboK9QsAOwEIaAwAAAcAJQBpDAAABgATAGsMAAAFABkAagwAAAQAIABsDAAABAAjAG0MAAADAB0A6gwAAAYAGwBuDAAAAwASAAAA.',
To='Tohotstotrot:BAAALgADCgQJBAAAAA==.Torlana:BAAALgADCgYJBgAAAA==.',
Tr='Trafaros:BAAALgADCgMJAwAAAA==.Trilldh:BAAALgAECgcJBQAAAA==.Trixielou:BAAALgAECggJEQAAAA==.',
Tt='Ttattoo:BAEBLgAECn8YAAMiAAYJ5QcBPwDFAAZoDAAABQAdAGkMAAAEABcAawwAAAUAEABqDAAAAwATAGwMAAACABUA6gwAAAUACQAiAAYJ5QcBPwDFAAZoDAAABQAdAGkMAAAEABcAawwAAAUAEABqDAAAAwATAGwMAAABABUA6gwAAAUACQAVAAEJqAImiAAZAAFsDAAAAQAGAAAA.Ttattooz:BAEALgAECgYJBgABLgAECgYJGAAiAOUHAA==.',
Ty='Tyramonde:BAAALgAECgYJBgAAAA==.',
Ub='Ubonrebu:BAAALgAFFAEJAQAAAA==.',
Va='Vaelestrix:BAACLgAFFH8XAAQBAAcJzRoCBgCeAQdoDAAABgBhAGkMAAAGAGIAawwAAAcAWgBqDAAAAQBOAGwMAAABABIA6gwAAAEAMwBuDAAAAQA4AAEABgmyHgIGAJ4BBmgMAAAFAGEAaQwAAAUAYgBrDAAABgBaAGoMAAABAE4A6gwAAAEAMwBuDAAAAQA4ACMAAwkMHHAEAAwBA2gMAAABAFUAaQwAAAEAPQBrDAAAAQBEACQAAQlRBywGAF0AAWwMAAABABIALgAECn9EAAMBAAkJ9yVuAADlAwABAAkJ9yVuAADlAwAkAAEJ7iUdFwBtAAAAAA==.Valholla:BAAALgADCgMJAwAAAA==.Vashtanerada:BAAALgADCgYJCgAAAA==.',
Ve='Veilish:BAAALgADCgYJCQAAAA==.',
Vo='Voiddøøde:BAAALgADCgcJBwAAAA==.Voidsocket:BAAALgAECgcJAQAAAA==.Voidtoes:BAAALgADCgYJBgAAAA==.',
Vu='Vulpvs:BAAALgADCgcJCwAAAA==.',
Vv='Vvlpvs:BAAALgADCgQJBAAAAA==.',
Wa='Warherald:BAABLgAECn8eAAQQAAYJ2g+IHwDpAAZoDAAABwArAGkMAAAGACIAawwAAAUAMgBqDAAABAAzAGwMAAADACUA6gwAAAUAJAAQAAYJ2g+IHwDpAAZoDAAABQArAGkMAAAEACIAawwAAAQAMgBqDAAAAwAzAGwMAAADACUA6gwAAAMAJAAOAAUJzwfGNACQAAVoDAAAAQARAGkMAAABAAUAawwAAAEAHgBqDAAAAQANAOoMAAABABoADwADCQMFiGQAZgADaAwAAAEADABpDAAAAQAYAOoMAAABAAEAAAA=.Wasntme:BAAALgADCgYJBgABLgAECgcJGwAZAL0KAA==.',
We='Wednesday:BAACLgAFFH8aAAIWAAcJ/xTsAgCZAQdoDAAABQA9AGkMAAAFAFMAawwAAAUAUgBqDAAAAgBLAG0MAAABABUA6gwAAAcARgBuDAAAAQACABYABwn/FOwCAJkBB2gMAAAFAD0AaQwAAAUAUwBrDAAABQBSAGoMAAACAEsAbQwAAAEAFQDqDAAABwBGAG4MAAABAAIALgAECn8sAAIWAAgJ+yS1AwB1AgAWAAgJ+yS1AwB1AgAAAA==.',
Wh='Whoops:BAAALgADCgcJBwAAAA==.',
Xa='Xalaria:BAAALgAECgYJDAAAAA==.',
Xi='Xirek:BAABLgAECn8gAAIQAAcJUA6gGgAVAQdoDAAABwAZAGkMAAAGACwAawwAAAYAIgBqDAAABAAbAGwMAAADADgA6gwAAAUALABuDAAAAQANABAABwlQDqAaABUBB2gMAAAHABkAaQwAAAYALABrDAAABgAiAGoMAAAEABsAbAwAAAMAOADqDAAABQAsAG4MAAABAA0AAAA=.',
Yr='Yreasak:BAABLgAECn8bAAMFAAcJdAe6gwD2AAdoDAAABQATAGkMAAAFABkAawwAAAUAIABqDAAABAAUAGwMAAADAA0A6gwAAAQAEQBuDAAAAQAFAAUABwkzBrqDAPYAB2gMAAAEAA4AaQwAAAQAGQBrDAAABAASAGoMAAAEABQAbAwAAAMADQDqDAAABAARAG4MAAABAAUAHAADCRcI/BoAngADaAwAAAEAEwBpDAAAAQAJAGsMAAABACAAAAA=.Yrisan:BAAALgADCgUJBQABLgAECgcJGwAFAHQHAA==.',
Ys='Yseulde:BAAALgADCgkJEQABLgAECgcJGwAFAHQHAA==.',
Zo='Zonako:BAAALgAECgcJEgAAAA==.Zoogranby:BAAALgADCgYJBgAAAA==.',
Zu='Zurâ:BAABLgAECn8XAAIWAAYJkQX3KwCcAAZoDAAABAAMAGkMAAAEABMAawwAAAQACgBqDAAABAAWAGwMAAADABEA6gwAAAQACwAWAAYJkQX3KwCcAAZoDAAABAAMAGkMAAAEABMAawwAAAQACgBqDAAABAAWAGwMAAADABEA6gwAAAQACwAAAA==.',
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
