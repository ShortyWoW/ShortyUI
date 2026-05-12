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

local lookup = {'Warlock-Destruction','Warlock-Demonology','DeathKnight-Unholy','Druid-Feral','Druid-Guardian','Druid-Balance','Unknown-Unknown','Hunter-Survival','DeathKnight-Blood','Paladin-Retribution','DemonHunter-Devourer','Hunter-BeastMastery','Mage-Frost','DeathKnight-Frost','Warrior-Fury','Warrior-Arms','Monk-Windwalker','Monk-Brewmaster','Shaman-Restoration','Shaman-Elemental','Shaman-Enhancement','Druid-Restoration','Mage-Fire','Mage-Arcane','Monk-Mistweaver','Paladin-Protection','Warrior-Protection','Priest-Shadow',}
local provider = {region='US',realm='TolBarad',name='US',type='daily',zone=46,date='2026-05-12',data={Ae='Aelarion:BAAALgADCgIJAgAAAA==.',
Ai='Airfryer:BAABLgAECn8gAAMBAAgJYhBeBwB9AQhoDAAABgA+AGkMAAAGAEoAawwAAAYAQwBqDAAABQAqAGwMAAACABoAbQwAAAEAAADqDAAABQAqAG4MAAABABMAAQAICWIQXgcAfQEIaAwAAAUAPgBpDAAABQBKAGsMAAAFAEMAagwAAAUAKgBsDAAAAgAaAG0MAAABAAAA6gwAAAUAKgBuDAAAAQATAAIAAwkKDXCYAKYAA2gMAAABACMAaQwAAAEAIgBrDAAAAQAeAAEuAAQKCAklAAMAXBsA.',
Aj='Ajorc:BAABLgAECn8aAAIEAAcJKhuaCgAdAgdoDAAAAwA9AGkMAAAEAEsAawwAAAQATgBqDAAABAA6AGwMAAADADkA6gwAAAQASgBuDAAABABFAAQABwkqG5oKAB0CB2gMAAADAD0AaQwAAAQASwBrDAAABABOAGoMAAAEADoAbAwAAAMAOQDqDAAABABKAG4MAAAEAEUAAAA=.Ajudando:BAACLgAFFH8LAAMFAAMJrhXhBwDJAANoDAAABAAlAGkMAAADAFMA6gwAAAQALQAEAAMJkxDbBQABAQNoDAAAAQAOAGkMAAABAFMA6gwAAAEAHAAFAAMJMRPhBwDJAANoDAAAAwAlAGkMAAACAEAA6gwAAAMALQAuAAQKfzIABAQACAkfIJYJADkCAAQACAm/H5YJADkCAAUACAk+FngOAJkBAAYAAgm0Cs5vAGAAAAAA.',
Ar='Arc:BAAALgAECgEJAwAAAA==.Arkanjjo:BAAALgAECgEJAQAAAA==.Arkhin:BAAALgADCgYJBgABLgAECgQJBAAHAAAAAA==.Artesuda:BAAALgAECgIJAwAAAA==.',
Au='Aurelya:BAAALgAECgEJAQAAAA==.',
Aw='Awrelius:BAAALgADCgUJDAAAAA==.',
Az='Aznat:BAAALgAECgYJCgABLgAECggJJQAIAG0aAA==.',
Ba='Bachir:BAAALgAECgQJBAAAAA==.Balduco:BAAALgAECgQJCwABLgAECgYJDgAHAAAAAA==.Banguelä:BAAALgAECgYJDAAAAA==.Barkernth:BAABLgAECn8hAAIJAAgJwRVvEwBXAQhoDAAABQBFAGkMAAAFAEUAawwAAAUARgBqDAAABQA3AGwMAAAFADUAbQwAAAEADwDqDAAABgBVAG8MAAABABoACQAICcEVbxMAVwEIaAwAAAUARQBpDAAABQBFAGsMAAAFAEYAagwAAAUANwBsDAAABQA1AG0MAAABAA8A6gwAAAYAVQBvDAAAAQAaAAAA.Batatadoci:BAABLgAECn8VAAIKAAgJqgjRZQA4AQhoDAAAAwASAGkMAAADACsAawwAAAMAGwBqDAAAAwATAGwMAAADABIAbQwAAAEACADqDAAAAwAPAG4MAAACABcACgAICaoI0WUAOAEIaAwAAAMAEgBpDAAAAwArAGsMAAADABsAagwAAAMAEwBsDAAAAwASAG0MAAABAAgA6gwAAAMADwBuDAAAAgAXAAAA.',
Be='Bellatryx:BAAALgAECgEJAQAAAA==.',
Bi='Bianca:BAAALgAECgcJCAAAAA==.Bispopelado:BAAALgADCgcJBwAAAA==.',
Br='Brutaal:BAAALgADCgUJBQAAAA==.Brutállus:BAAALgADCgcJBwAAAA==.',
Ca='Calangosauro:BAAALgAFFAEJAQAAAA==.',
Ch='Chinchanchen:BAAALgAECgEJAQAAAA==.',
Co='Coqueiro:BAAALgADCgYJBgAAAA==.',
Cr='Cremador:BAAALgAECgYJDgAAAA==.',
Da='Dabura:BAAALgADCgEJAQAAAA==.Dam:BAAALgADCgYJBgAAAA==.',
De='Deabu:BAAALgADCgQJBQAAAA==.Demethryus:BAAALgADCgYJBgAAAA==.Dennath:BAAALgAECgQJBAAAAA==.Ders:BAAALgADCgEJAQAAAA==.Devilton:BAABLgAECn8kAAILAAcJPw6hTwAeAQdoDAAABwAgAGkMAAAGACsAawwAAAYAMABqDAAABQAqAGwMAAAEACYAbQwAAAEACQDqDAAABwAuAAsABwk/DqFPAB4BB2gMAAAHACAAaQwAAAYAKwBrDAAABgAwAGoMAAAFACoAbAwAAAQAJgBtDAAAAQAJAOoMAAAHAC4AAAA=.',
Di='Diericshaman:BAAALgADCgUJBQAAAA==.',
Do='Domri:BAABLgAECn8bAAIMAAgJaCABEwBOAghoDAAABQBeAGkMAAAEAF8AawwAAAQAWwBqDAAABABaAGwMAAAEAFYAbQwAAAEAIADqDAAABABVAG4MAAABAF4ADAAICWggARMATgIIaAwAAAUAXgBpDAAABABfAGsMAAAEAFsAagwAAAQAWgBsDAAABABWAG0MAAABACAA6gwAAAQAVQBuDAAAAQBeAAAA.Donnus:BAABLgAECn8wAAINAAkJWyAlDADSAgloDAAABwBeAGkMAAAHAFkAawwAAAcAUABqDAAABgBQAGwMAAAFAFMAbQwAAAQASwDqDAAABgBYAG4MAAAEAEgAbwwAAAIATgANAAkJWyAlDADSAgloDAAABwBeAGkMAAAHAFkAawwAAAcAUABqDAAABgBQAGwMAAAFAFMAbQwAAAQASwDqDAAABgBYAG4MAAAEAEgAbwwAAAIATgAAAA==.Doomhand:BAAALgAECgQJBAAAAA==.Dormin:BAAALgADCgUJBQAAAA==.Dorotty:BAAALgAECgQJBQAAAA==.',
Dr='Dragolancer:BAAALgAECgMJAwAAAA==.Drakonvolk:BAABLgAECn8rAAMOAAgJQR7RAwA9AghoDAAACABUAGkMAAAHAGAAawwAAAYAVgBqDAAABQBXAGwMAAAEAEQAbQwAAAEAHQDqDAAABwBRAG4MAAAFAF8ADgAHCS8g0QMAPQIHaAwAAAEAVABpDAAAAQBOAGsMAAABAFYAagwAAAIAVwBsDAAAAQBEAOoMAAADAFEAbgwAAAMAXwADAAgJ6Bw/OwCjAQhoDAAABwBOAGkMAAAGAGAAawwAAAUATwBqDAAAAwBEAGwMAAADAD8AbQwAAAEAHQDqDAAABABPAG4MAAACAFsAAAA=.Drevanir:BAAALgADCggJCAAAAA==.Druidzuda:BAAALgADCgEJAQAAAA==.',
['Dé']='Dégell:BAAALgAECgUJCQAAAA==.',
Ed='Edy:BAAALgAECgEJAgABLgAECggJEQAHAAAAAA==.',
Ei='Einheriar:BAAALgADCgUJBQAAAA==.',
El='Elanya:BAAALgADCgUJAgAAAA==.Elidaryel:BAABLgAECn80AAILAAkJBCD0BAD0AgloDAAABwBeAGkMAAAHAFkAawwAAAcAWgBqDAAABgBVAGwMAAAFAFIAbQwAAAUASgDqDAAACABeAG4MAAAFAFMAbwwAAAIALQALAAkJBCD0BAD0AgloDAAABwBeAGkMAAAHAFkAawwAAAcAWgBqDAAABgBVAGwMAAAFAFIAbQwAAAUASgDqDAAACABeAG4MAAAFAFMAbwwAAAIALQAAAA==.',
Fa='Faephine:BAAALgADCgkJEgAAAA==.',
Fe='Felithia:BAAALgADCgQJBAABLgAFFAQJDQAOANYQAA==.',
Fr='Fred:BAAALgAECgUJBgAAAA==.Frozenrune:BAABLgAECn8lAAMOAAgJ1B/zBAD8AQhoDAAABgBhAGkMAAAFAFwAawwAAAUAXwBqDAAABQBbAGwMAAAFAF4AbQwAAAMAMgDqDAAABQBcAG4MAAADAC8ADgAGCeEk8wQA/AEGaAwAAAMAYQBpDAAAAgBcAGsMAAACAF8AagwAAAIAWwBsDAAAAgBeAOoMAAACAFwACQAICWAWUQ4ApgEIaAwAAAMAKQBpDAAAAwBEAGsMAAADAEsAagwAAAMAQQBsDAAAAwAxAG0MAAADADIA6gwAAAMARABuDAAAAwAvAAAA.',
Fu='Fuleco:BAABLgAECn8oAAMPAAgJiyMQCwBKAghoDAAABwBjAGkMAAAHAGIAawwAAAYAUwBqDAAABQBjAGwMAAAEAFgAbQwAAAEAXwDqDAAABwBhAG4MAAADAEoADwAICXMhEAsASgIIaAwAAAcAYwBpDAAABwBiAGsMAAABAFAAagwAAAUAYwBsDAAAAQA5AG0MAAABAF8A6gwAAAcAYQBuDAAAAgBHABAAAwkxIDoXABcBA2sMAAAFAFMAbAwAAAMAWABuDAAAAQBKAAAA.',
Ga='Gablle:BAABLgAECn8wAAMRAAkJ3g3uEwCmAQloDAAABwAUAGkMAAAHACkAawwAAAcALQBqDAAABgAfAGwMAAAFACgAbQwAAAQAHwDqDAAABgAvAG4MAAAEACMAbwwAAAIAFQARAAkJ3g3uEwCmAQloDAAABgAUAGkMAAAGACkAawwAAAYALQBqDAAABQAfAGwMAAAEACgAbQwAAAMAHwDqDAAABgAvAG4MAAADACMAbwwAAAEAFQASAAgJowM8KgAJAQhoDAAAAQAEAGkMAAABAAgAawwAAAEABgBqDAAAAQAEAGwMAAABABcAbQwAAAEACgBuDAAAAQAHAG8MAAABAAQAAAA=.Gabrielstone:BAAALgAECgQJBgAAAA==.Gabriwel:BAAALgAECgQJBwAAAA==.',
Gl='Glimmuln:BAABLgAECn8fAAMTAAYJOgkGTwDjAAZoDAAABgATAGkMAAAGACMAawwAAAYAFwBqDAAABAAMAGwMAAAEAAkA6gwAAAUAKgATAAYJOgkGTwDjAAZoDAAABQATAGkMAAAGACMAawwAAAYAFwBqDAAABAAMAGwMAAAEAAkA6gwAAAUAKgAUAAEJpwfajwAoAAFoDAAAAQATAAAA.Glimwr:BAAALgAECgQJCgAAAA==.',
Go='Gordorc:BAAALgAECgEJAQAAAA==.Gorvok:BAAALgADCgMJAwAAAA==.',
Gr='Grongos:BAAALgAECgEJAgABLgAECgYJDgAHAAAAAA==.Grumps:BAAALgADCgcJBwAAAA==.',
Gu='Gueber:BAAALgAECgYJCwAAAA==.Gueberlin:BAAALgADCgQJBAAAAA==.Guebernir:BAAALgADCgYJDAAAAA==.',
Ha='Hakoda:BAAALgAECgEJAQAAAA==.Harggoth:BAAALgAECgMJAwAAAA==.',
He='Hergor:BAABLgAECn8gAAQUAAgJ/xISGQCcAQhoDAAABABAAGkMAAAEADwAawwAAAUAKQBqDAAABQBAAGwMAAAEACsAbQwAAAMAIQDqDAAABgA7AG4MAAABACQAFAAICf8SEhkAnAEIaAwAAAMAQABpDAAABAA8AGsMAAAFACkAagwAAAMAQABsDAAAAwArAG0MAAACACEA6gwAAAIAOwBuDAAAAQAkABMABAn1Cn9yAMUABGgMAAABAAgAagwAAAEACABtDAAAAQAzAOoMAAAEACwAFQACCb0IHywANQACagwAAAEAAABsDAAAAQAWAAAA.Hexdrinker:BAAALgADCgkJCQAAAA==.',
Ir='Irmasuelen:BAAALgAECgYJCgAAAA==.',
Je='Jeh:BAAALgADCgkJEwAAAA==.Jeje:BAAALgAECgQJBwAAAA==.',
Jo='Jorgebenjorg:BAAALgAECgEJAQAAAA==.',
Ka='Kalanguin:BAAALgADCgEJAQAAAA==.Kate:BAABLgAECn8jAAIWAAkJZxTfHgDkAQloDAAABQBHAGkMAAAFAD4AawwAAAUATgBqDAAABAAxAGwMAAADACwAbQwAAAIAGgDqDAAABgA9AG4MAAADADgAbwwAAAIAEgAWAAkJZxTfHgDkAQloDAAABQBHAGkMAAAFAD4AawwAAAUATgBqDAAABAAxAGwMAAADACwAbQwAAAIAGgDqDAAABgA9AG4MAAADADgAbwwAAAIAEgAAAA==.',
Kh='Khylin:BAAALgAECgUJCAAAAA==.',
Kl='Klimorin:BAAALgADCgMJBAAAAA==.',
Kr='Krzero:BAAALgADCgIJAgABLgAECggJKwAOAEEeAA==.',
Lc='Lcabronehboy:BAAALgAECgMJCgAAAA==.',
Le='Lexan:BAABLgAECn8fAAMUAAcJHRAiJgA8AQdoDAAABgAkAGkMAAAFAC4AawwAAAUAKQBqDAAABAAsAGwMAAAEACsAbQwAAAEAGADqDAAABgA3ABQABwkdECImADwBB2gMAAAFACQAaQwAAAQALgBrDAAABAApAGoMAAADACwAbAwAAAMAKwBtDAAAAQAYAOoMAAAGADcAFQAFCTwIuxUAxgAFaAwAAAEAFABpDAAAAQAYAGsMAAABABkAagwAAAEACABsDAAAAQANAAAA.',
Li='Linlygan:BAAALgADCgQJBAAAAA==.Lissão:BAABLgAECn8dAAMJAAgJ9RtMCAAbAghoDAAABQBHAGkMAAAFAFAAawwAAAUARgBqDAAAAwBIAGwMAAADADoAbQwAAAIASQDqDAAABQBBAG4MAAABAFAACQAICfUbTAgAGwIIaAwAAAUARwBpDAAABQBQAGsMAAAFAEYAagwAAAMASABsDAAAAwA6AG0MAAACAEkA6gwAAAQAQQBuDAAAAQBQAAMAAQnxAJM8ARkAAeoMAAABAAIAAAA=.',
Lu='Lucoa:BAAALgADCgUJBQABLgAECggJHwACAIEaAA==.Luhanar:BAAALgAECgMJBAABLgAECggJKwAOAEEeAA==.',
Ly='Lylithe:BAAALgAECgEJAQAAAA==.',
Ma='Madow:BAABLgAECn8fAAICAAgJgRpuHgAJAghoDAAABQA9AGkMAAAFAFAAawwAAAUARwBqDAAAAwBZAGwMAAADAD0AbQwAAAIALgDqDAAABwBRAG4MAAABAEgAAgAICYEabh4ACQIIaAwAAAUAPQBpDAAABQBQAGsMAAAFAEcAagwAAAMAWQBsDAAAAwA9AG0MAAACAC4A6gwAAAcAUQBuDAAAAQBIAAAA.Magmafire:BAABLgAECn80AAMXAAkJuSBZAQCiAgloDAAABABjAGkMAAADAFgAawwAAAIAVQBqDAAACQBfAGwMAAAIAEwAbQwAAAgAWADqDAAABwBbAG4MAAAHAFEAbwwAAAQAOgAXAAgJYR9ZAQCiAghpDAAAAQBYAGsMAAABAFAAagwAAAcAXwBsDAAABQBJAG0MAAAGAFgA6gwAAAUAWwBuDAAABwBRAG8MAAAEADoAGAAHCfMf1wIAWAIHaAwAAAQAYwBpDAAAAgBXAGsMAAABAFUAagwAAAIAGwBsDAAAAwBMAG0MAAACADQA6gwAAAIAWAAAAA==.Magronego:BAAALgAECgMJBQAAAA==.Malakain:BAAALgAECgEJAQAAAA==.Mazakita:BAAALgADCgMJAwAAAA==.',
Mi='Mitsy:BAABLgAECn8YAAMZAAYJrxxZGQCfAQZoDAAABABSAGkMAAAFAFYAawwAAAUAOgBqDAAAAwBNAGwMAAADAEMA6gwAAAQAQwAZAAYJrxxZGQCfAQZoDAAAAwBSAGkMAAADAFYAawwAAAMAOgBqDAAAAQBNAGwMAAABAEMA6gwAAAIAQwARAAYJDAt6PwAcAQZoDAAAAQANAGkMAAACACkAawwAAAIAJABqDAAAAgAlAGwMAAACABgA6gwAAAIAGgAAAA==.',
Mo='Morevil:BAAALgADCgQJBAAAAA==.Morterubra:BAABLgAECn8lAAMDAAgJXBuuJAAGAghoDAAACwBbAGkMAAAFAEYAawwAAAYAQQBqDAAAAwANAGwMAAACACMAbQwAAAEANwDqDAAABgBQAG4MAAADAFsAAwAICVwbriQABgIIaAwAAAkAWwBpDAAAAwBGAGsMAAAEAEEAagwAAAEADQBsDAAAAQAjAG0MAAABADcA6gwAAAYAUABuDAAAAwBbAAkABQmgC7UmAKcABWgMAAACADIAaQwAAAIAHgBrDAAAAgAUAGoMAAACAAwAbAwAAAEAEAAAAA==.Mosa:BAAALgAECgQJBwAAAA==.',
Mu='Mulkzagoon:BAAALgADCgQJBgAAAA==.Murodan:BAAALgAECgQJBAAAAA==.Musphelheim:BAAALgADCgcJBwAAAA==.',
['Mö']='Mörrigan:BAAALgAECgQJBAAAAA==.',
Na='Nadruk:BAABLgAECn8jAAITAAcJuh7wHQAsAgdoDAAABQBaAGkMAAAFAEEAawwAAAUAVABqDAAABgBQAGwMAAAFAE4AbQwAAAIAOgDqDAAABwBbABMABwm6HvAdACwCB2gMAAAFAFoAaQwAAAUAQQBrDAAABQBUAGoMAAAGAFAAbAwAAAUATgBtDAAAAgA6AOoMAAAHAFsAAAA=.Natalia:BAAALgAECggJCQAAAA==.',
Ne='Neskau:BAAALgAECgEJAQAAAA==.Nevinha:BAAALgADCgEJAQAAAA==.Neymardacaça:BAAALgADCgIJAgAAAA==.',
Ni='Nidaime:BAABLgAECn8aAAINAAgJRhPtngDrAAhoDAAABAApAGkMAAAEAEQAawwAAAUAQABqDAAABABFAGwMAAABACkAbQwAAAEAFQDqDAAABQA4AG4MAAACADMADQAICUYT7Z4A6wAIaAwAAAQAKQBpDAAABABEAGsMAAAFAEAAagwAAAQARQBsDAAAAQApAG0MAAABABUA6gwAAAUAOABuDAAAAgAzAAAA.',
No='Noach:BAAALgADCgMJAwABLgAECgYJDgAHAAAAAA==.Nocro:BAAALgADCgEJAQAAAA==.',
Oa='Oathkeeper:BAAALgADCgYJBQAAAA==.',
Od='Odahviing:BAAALgADCgkJCgABLgAECggJJQADAFwbAA==.',
Oi='Oicasada:BAAALgADCgMJBAAAAA==.',
Op='Optix:BAAALgAECgMJAwAAAA==.',
Ox='Oxylus:BAABLgAECn8cAAIWAAgJqxFxJgCvAQhoDAAABQBDAGkMAAAFAEIAawwAAAUAOwBqDAAABAAkAGwMAAAEACYAbQwAAAEAHADqDAAAAwAtAG4MAAABABMAFgAICasRcSYArwEIaAwAAAUAQwBpDAAABQBCAGsMAAAFADsAagwAAAQAJABsDAAABAAmAG0MAAABABwA6gwAAAMALQBuDAAAAQATAAAA.',
Pa='Padremario:BAAALgADCgEJAgAAAA==.Palahorda:BAAALgADCgUJBQAAAA==.Panchorf:BAABLgAECn8kAAIaAAcJNwZZHQC9AAdoDAAABwAWAGkMAAAGABoAawwAAAYADQBqDAAABQAGAGwMAAAEAAoAbQwAAAEABADqDAAABwASABoABwk3BlkdAL0AB2gMAAAHABYAaQwAAAYAGgBrDAAABgANAGoMAAAFAAYAbAwAAAQACgBtDAAAAQAEAOoMAAAHABIAAAA=.',
Pe='Pescador:BAAALgAECgcJEAAAAA==.Pevê:BAAALgAECgMJAgAAAA==.',
Pr='Prihunter:BAABLgAECn8kAAIMAAcJxwuOSwA+AQdoDAAABwAcAGkMAAAGACIAawwAAAYAJwBqDAAABQAYAGwMAAAEABcAbQwAAAEAEQDqDAAABwAkAAwABwnHC45LAD4BB2gMAAAHABwAaQwAAAYAIgBrDAAABgAnAGoMAAAFABgAbAwAAAQAFwBtDAAAAQARAOoMAAAHACQAAAA=.Primanocte:BAAALgADCgYJBgAAAA==.',
Ra='Rafikii:BAACLgAFFH8FAAIFAAMJRwJBDwBiAANoDAAAAwAGAGkMAAABAAAA6gwAAAEACQAFAAMJRwJBDwBiAANoDAAAAwAGAGkMAAABAAAA6gwAAAEACQAuAAQKfx0AAgUACAndApAgAJoAAAUACAndApAgAJoAAAAA.Randel:BAAALgADCgQJBAAAAA==.Raswell:BAAALgADCgEJAQAAAA==.',
Rh='Rhadamants:BAAALgAECgEJAQAAAA==.',
Ri='Richard:BAAALgADCggJBQAAAA==.Ritaa:BAABLgAECn8cAAIKAAcJSxuaRwAMAgdoDAAABABFAGkMAAAEAEAAawwAAAYAQgBqDAAABAAzAGwMAAAEAD4A6gwAAAMASQBuDAAAAwBSAAoABwlLG5pHAAwCB2gMAAAEAEUAaQwAAAQAQABrDAAABgBCAGoMAAAEADMAbAwAAAQAPgDqDAAAAwBJAG4MAAADAFIAAAA=.Rizúl:BAAALgAECgQJBAAAAA==.',
Rl='Rldsbvb:BAABLgAECn8lAAIIAAgJbRpOCAA1AghoDAAABgBEAGkMAAAHAFcAawwAAAYAQwBqDAAABAA2AGwMAAAEAFIAbQwAAAIATQDqDAAABwA7AG4MAAABAB8ACAAICW0aTggANQIIaAwAAAYARABpDAAABwBXAGsMAAAGAEMAagwAAAQANgBsDAAABABSAG0MAAACAE0A6gwAAAcAOwBuDAAAAQAfAAAA.',
Ro='Rotgaz:BAAALgAECgEJAQAAAA==.',
Sa='Sabedetudo:BAAALgAECgEJAQAAAA==.Sadomie:BAABLgAECn8fAAIMAAgJVhdYJADZAQhoDAAABgBHAGkMAAAGADcAawwAAAQAOQBqDAAABAA/AGwMAAADAEkAbQwAAAIAIADqDAAABQBIAG4MAAABADYADAAICVYXWCQA2QEIaAwAAAYARwBpDAAABgA3AGsMAAAEADkAagwAAAQAPwBsDAAAAwBJAG0MAAACACAA6gwAAAUASABuDAAAAQA2AAAA.',
Sh='Shindi:BAAALgADCgQJBQAAAA==.Shreka:BAAALgADCgMJAwAAAA==.',
Si='Silaleas:BAAALgAECgIJAwAAAA==.',
Sk='Skiff:BAAALgAECgEJAgAAAA==.',
So='Solana:BAAALgADCgYJBgAAAA==.',
Sw='Sweej:BAAALgAECgIJAgABLgAECgkJLgAUAOAVAA==.',
Ta='Tacalypau:BAAALgADCgYJBgAAAA==.Tahir:BAAALgAECgYJCAAAAA==.Taima:BAAALgADCgkJCwAAAA==.',
Th='Thebrunovest:BAABLgAECn8ZAAIDAAYJEhAzbQAdAQZoDAAABAAyAGkMAAAEAD0AawwAAAQAIABqDAAABAAtAGwMAAADACoA6gwAAAYAEwADAAYJEhAzbQAdAQZoDAAABAAyAGkMAAAEAD0AawwAAAQAIABqDAAABAAtAGwMAAADACoA6gwAAAYAEwAAAA==.Thortrevan:BAABLgAECn8sAAIMAAgJ0h2ZEAC1AghoDAAACQBgAGkMAAAIAFYAawwAAAoAWABqDAAABAAxAGwMAAAEAEkAbQwAAAEAQgDqDAAABgBPAG4MAAACACsADAAICdIdmRAAtQIIaAwAAAkAYABpDAAACABWAGsMAAAKAFgAagwAAAQAMQBsDAAABABJAG0MAAABAEIA6gwAAAYATwBuDAAAAgArAAAA.Thrain:BAABLgAECn8fAAIbAAcJeRmQDgCGAQdoDAAABgBOAGkMAAAFAFIAawwAAAUAPgBqDAAABAAmAGwMAAAEACoAbQwAAAEAOgDqDAAABgBCABsABwl5GZAOAIYBB2gMAAAGAE4AaQwAAAUAUgBrDAAABQA+AGoMAAAEACYAbAwAAAQAKgBtDAAAAQA6AOoMAAAGAEIAAAA=.',
Ti='Tiffah:BAABLgAECn8cAAINAAgJoR2mNACgAghoDAAABABcAGkMAAAEAFUAawwAAAQASQBqDAAAAwBfAGwMAAAEAEMAbQwAAAEANgDqDAAABQBJAG4MAAADAFMADQAICaEdpjQAoAIIaAwAAAQAXABpDAAABABVAGsMAAAEAEkAagwAAAMAXwBsDAAABABDAG0MAAABADYA6gwAAAUASQBuDAAAAwBTAAAA.Tinth:BAAALgADCgEJAQAAAA==.Tixi:BAAALgAECgUJBQAAAA==.',
To='Toranaar:BAAALgAECgUJCAABLgAECggJEQAHAAAAAA==.Totahealer:BAAALgAECgMJBQABLgAECgYJDgAHAAAAAA==.',
Tr='Traix:BAAALgAECgYJEgAAAA==.Trememoita:BAAALgADCgQJBAAAAA==.',
Va='Vanthyn:BAAALgAECgEJAQAAAA==.',
Ve='Veccia:BAAALgADCgIJAgAAAA==.',
Vh='Vherk:BAAALgADCgQJBAAAAA==.',
We='Wenasnoches:BAAALgADCggJDAAAAA==.',
Wh='Whitetusk:BAAALgADCgcJBwAAAA==.',
Wu='Wurdulak:BAAALgADCgEJAQAAAA==.',
Xa='Xamelo:BAABLgAECn8kAAITAAcJsSMmBwDUAgdoDAAABwBhAGkMAAAGAGAAawwAAAYAYQBqDAAABQBcAGwMAAAEAGAAbQwAAAEAQgDqDAAABwBcABMABwmxIyYHANQCB2gMAAAHAGEAaQwAAAYAYABrDAAABgBhAGoMAAAFAFwAbAwAAAQAYABtDAAAAQBCAOoMAAAHAFwAAAA=.',
Xi='Xicobruxo:BAAALgAECgIJAgAAAA==.',
Yo='Yona:BAAALgAECgUJEAABLgAECgYJEAAHAAAAAA==.',
Za='Zadockn:BAAALgAECgQJBQAAAA==.',
Zu='Zughy:BAAALgAECgYJCQABLgAFFAgJGwAcALUeAA==.',
['Zé']='Zédaplanta:BAABLgAECn8cAAIWAAYJ5hJBNgBVAQZoDAAABwBIAGkMAAAGAD8AawwAAAYAMwBqDAAABAAiAGwMAAABAA0A6gwAAAQANgAWAAYJ5hJBNgBVAQZoDAAABwBIAGkMAAAGAD8AawwAAAYAMwBqDAAABAAiAGwMAAABAA0A6gwAAAQANgAAAA==.',
['Är']='Ärkin:BAAALgADCgQJBAABLgAECggJJQADAFwbAA==.',
['Ðe']='Ðeath:BAAALgAECgYJCAABLgAECggJKAAPAIsjAA==.',
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
