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

local lookup = {'Paladin-Holy','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Hunter-Marksmanship','Hunter-Survival','Hunter-BeastMastery','Monk-Brewmaster','Mage-Frost','DeathKnight-Unholy','Monk-Windwalker','Mage-Arcane','Druid-Balance','Unknown-Unknown','Druid-Guardian','DemonHunter-Devourer','DeathKnight-Blood','Druid-Restoration','Paladin-Retribution','DemonHunter-Vengeance','Monk-Mistweaver','Warrior-Arms','DeathKnight-Frost','Paladin-Protection','Shaman-Elemental','Evoker-Augmentation','Priest-Holy','DemonHunter-Havoc','Mage-Fire','Priest-Discipline','Priest-Shadow',}
local provider = {region='US',realm='ShatteredHalls',name='US',type='daily',zone=46,date='2026-05-14',data={Al='Alannaria:BAAALgADCgQJBwAAAA==.Alaris:BAAALgAECggJDAABLgAFFAUJFwABALYjAA==.Alex:BAAALgAECggJEAABLgAECggJIQACAHwfAA==.Allmight:BAAALgADCgIJAgAAAA==.Alx:BAABLgAECn8hAAQCAAcJfB/zQwB6AQdoDAAABgBXAGkMAAAGAFcAawwAAAUAUQBqDAAABQBAAGwMAAADAEsA6gwAAAYAWABuDAAAAgA+AAIABwkUHPNDAHoBB2gMAAADADUAaQwAAAIAVwBrDAAAAgBRAGoMAAABACcAbAwAAAEASwDqDAAABQBGAG4MAAACAD4AAwAECSAZvSUAMAEEaQwAAAIARQBrDAAAAQBOAGoMAAAEAEAAbAwAAAIALQAEAAQJXyFHEAApAQRoDAAAAwBXAGkMAAACAFQAawwAAAIAUADqDAAAAQBYAAAA.',
Ar='Archom:BAAALgADCgUJBQAAAA==.',
Au='Audrey:BAABLgAECn8bAAQFAAkJax12BgDOAQloDAAABQBLAGkMAAADACoAawwAAAMAWgBqDAAAAwBYAGwMAAADAE8AbQwAAAMATgDqDAAAAwA8AG4MAAADAFsAbwwAAAEAVAAFAAgJDxl2BgDOAQhoDAAAAgBLAGkMAAACACoAawwAAAIAPwBqDAAAAgBYAGwMAAADAE8AbQwAAAIATgDqDAAAAgA8AG4MAAACADEABgAGCTcPgR8AMgEGaAwAAAIAQgBpDAAAAQAGAGsMAAABAFoAagwAAAEARQBtDAAAAQAbAOoMAAABAAQABwADCe0dj3sAzwADaAwAAAEANQBuDAAAAQBbAG8MAAABAFQAAAA=.',
Av='Avoe:BAAALgADCgYJBgAAAA==.',
Ba='Banakafalata:BAABLgAECn8ZAAIIAAYJrgsxNgDZAAZoDAAABgA/AGkMAAAGABQAawwAAAQAEQBqDAAAAgArAGwMAAACABcA6gwAAAUAGgAIAAYJrgsxNgDZAAZoDAAABgA/AGkMAAAGABQAawwAAAQAEQBqDAAAAgArAGwMAAACABcA6gwAAAUAGgABLgAECgkJKAAJAH8WAA==.Bat:BAAALgAECgUJDAAAAA==.',
Be='Beautieful:BAAALgADCgcJEQAAAA==.Bevo:BAAALgAECgYJBgAAAA==.',
Bi='Bigsha:BAAALgADCgYJCwAAAA==.',
Bl='Blux:BAAALgADCgUJBQAAAA==.',
Bo='Bondagestyle:BAAALgADCgIJAgAAAA==.Borgor:BAABLgAECn8pAAIKAAgJKiIZGwDbAghoDAAACABhAGkMAAAHAGEAawwAAAYASwBqDAAABABZAGwMAAAEAFoAbQwAAAMAVwDqDAAABwBZAG4MAAACAEoACgAICSoiGRsA2wIIaAwAAAgAYQBpDAAABwBhAGsMAAAGAEsAagwAAAQAWQBsDAAABABaAG0MAAADAFcA6gwAAAcAWQBuDAAAAgBKAAEuAAQKCQkXAAsAMyAA.',
Bt='Btterbean:BAAALgAECgMJBQAAAA==.',
Bu='Burdên:BAABLgAECn8dAAIMAAgJWwgDBQBLAQhoDAAABAAQAGkMAAAEACAAawwAAAUAGwBqDAAABAAzAGwMAAAEABkAbQwAAAEADgDqDAAABgAYAG4MAAABAAoADAAICVsIAwUASwEIaAwAAAQAEABpDAAABAAgAGsMAAAFABsAagwAAAQAMwBsDAAABAAZAG0MAAABAA4A6gwAAAYAGABuDAAAAQAKAAAA.',
Ch='Chamber:BAAALgAECgQJBAAAAA==.Chambr:BAAALgAECgEJAQAAAA==.Chamchi:BAAALgAECgQJBAAAAA==.Cheri:BAACLgAFFH8KAAINAAUJtQWJGwDoAAVoDAAAAwASAGkMAAACABAAawwAAAEABABqDAAAAQALAOoMAAADABIADQAFCbUFiRsA6AAFaAwAAAMAEgBpDAAAAgAQAGsMAAABAAQAagwAAAEACwDqDAAAAwASAC4ABAp/IQACDQAICeQaphsAJQIADQAICeQaphsAJQIAAAA=.',
Co='Codh:BAAALgAECgEJAgABLgAECgUJCgAOAAAAAA==.Codum:BAAALgAECgUJCgAAAA==.',
Da='Dackosaur:BAABLgAECn8dAAIPAAgJeiH6AgChAghoDAAABABdAGkMAAAEAF4AawwAAAUAXwBqDAAABABcAGwMAAAEAFEAbQwAAAEAUQDqDAAABgBbAG4MAAABAD4ADwAICXoh+gIAoQIIaAwAAAQAXQBpDAAABABeAGsMAAAFAF8AagwAAAQAXABsDAAABABRAG0MAAABAFEA6gwAAAYAWwBuDAAAAQA+AAAA.Dageek:BAAALgAECgEJAQAAAA==.Daneikus:BAAALgAECgMJAwAAAA==.Danekriste:BAABLgAECn8SAAIQAAYJyQVmjwCdAAZoDAAAAwAWAGkMAAADAAcAawwAAAMADwBqDAAAAwAQAGwMAAAEABIA6gwAAAIACAAQAAYJyQVmjwCdAAZoDAAAAwAWAGkMAAADAAcAawwAAAMADwBqDAAAAwAQAGwMAAAEABIA6gwAAAIACAAAAA==.Darkenedone:BAACLgAFFH8WAAIRAAUJVhzsCwAyAQVoDAAABwBAAGkMAAAGAEUAawwAAAMAQQBqDAAAAQBDAOoMAAAFAFoAEQAFCVYc7AsAMgEFaAwAAAcAQABpDAAABgBFAGsMAAADAEEAagwAAAEAQwDqDAAABQBaAC4ABAp/IQADEQAJCUIiuwEAFAMAEQAJCUIiuwEAFAMACgACCQ8SyhQBSwAAAAA=.',
Db='Dblackfalcon:BAAALgAECgEJAQAAAA==.',
De='Deathaura:BAAALgADCgMJAwAAAA==.Deathbyarrow:BAAALgADCgUJBQAAAA==.Demonex:BAAALgADCgMJAwABLgAECgQJBAAOAAAAAA==.Demono:BAABLgAECn8WAAIQAAYJExdHXgCGAQZoDAAABAAkAGkMAAAEAD4AawwAAAQAOABqDAAAAwAzAGwMAAADAD0A6gwAAAQATgAQAAYJExdHXgCGAQZoDAAABAAkAGkMAAAEAD4AawwAAAQAOABqDAAAAwAzAGwMAAADAD0A6gwAAAQATgABLgAFFAUJFAASAHckAA==.Denton:BAAALgAECgQJBAAAAA==.',
Do='Doggx:BAAALgADCgkJDQAAAA==.',
Dr='Drfrangelico:BAABLgAECn8ZAAMBAAgJqBGcHADEAQhoDAAABAA2AGkMAAAEAEYAawwAAAQAMgBqDAAAAwAdAGwMAAADACYAbQwAAAIAIwDqDAAAAwAlAG4MAAACAC0AAQAICagRnBwAxAEIaAwAAAMANgBpDAAAAwBGAGsMAAADADIAagwAAAIAHQBsDAAAAgAmAG0MAAABACMA6gwAAAIAJQBuDAAAAQAtABMACAnoBidxACsBCGgMAAABABUAaQwAAAEAFABrDAAAAQANAGoMAAABABgAbAwAAAEACQBtDAAAAQAkAOoMAAABAAkAbgwAAAEADAAAAA==.Druido:BAACLgAFFH8UAAISAAUJdyRKAQARAgVoDAAABABdAGkMAAAEAF0AawwAAAQAXABqDAAAAgBaAOoMAAAGAGAAEgAFCXckSgEAEQIFaAwAAAQAXQBpDAAABABdAGsMAAAEAFwAagwAAAIAWgDqDAAABgBgAC4ABAp/LwADEgAJCdglLQAA7wMAEgAJCdglLQAA7wMADQAECeghGSAAVwEAAAA=.Drunkmonk:BAAALgAECggJEAAAAA==.',
Ds='Ds:BAACLgAFFH8PAAIUAAQJmyCDAQBUAQRoDAAABQBbAGkMAAAEAFAAawwAAAIARwDqDAAABABaABQABAmbIIMBAFQBBGgMAAAFAFsAaQwAAAQAUABrDAAAAgBHAOoMAAAEAFoALgAECn8mAAIUAAkJWiMoAQAnAwAUAAkJWiMoAQAnAwAAAA==.',
Du='Dumdum:BAAALgAECgQJBgAAAA==.',
En='Enjoyby:BAABLgAECn8YAAIVAAYJ1yKiDQBCAgZoDAAAAwBbAGkMAAAEAF0AawwAAAUAWQBqDAAABQBdAGwMAAAEAFsA6gwAAAMASgAVAAYJ1yKiDQBCAgZoDAAAAwBbAGkMAAAEAF0AawwAAAUAWQBqDAAABQBdAGwMAAAEAFsA6gwAAAMASgAAAA==.',
Er='Erzascarlet:BAAALgADCgIJAgAAAA==.',
Ex='Exayah:BAAALgAECgQJBAAAAA==.',
Fi='Fistwarior:BAAALgAECgYJDAABLgAFFAcJIAACAFoeAA==.',
Fr='Frankßuck:BAABLgAECn8dAAMFAAYJ5wK7HgBsAAZoDAAABgAGAGkMAAAGAAkAawwAAAYACABqDAAABAAKAGwMAAAEAAYA6gwAAAMABQAHAAYJ2AIrigCsAAZoDAAABQAFAGkMAAAFAAkAawwAAAUACABqDAAAAwAKAGwMAAADAAYA6gwAAAIABQAFAAYJDQK7HgBsAAZoDAAAAQAGAGkMAAABAAgAawwAAAEABABqDAAAAQAAAGwMAAABAAQA6gwAAAEAAQAAAA==.Friarstrange:BAABLgAECn8UAAIVAAYJqAx2MwD3AAZoDAAABAAdAGkMAAAEACkAawwAAAQAKgBqDAAAAgAZAGwMAAACABUA6gwAAAQAIQAVAAYJqAx2MwD3AAZoDAAABAAdAGkMAAAEACkAawwAAAQAKgBqDAAAAgAZAGwMAAACABUA6gwAAAQAIQAAAA==.Frosticle:BAAALgADCgEJAQAAAA==.',
Ga='Gaebora:BAABLgAECn8eAAISAAYJHyEAKgAKAgZoDAAABgBZAGkMAAAGAFIAawwAAAYAVABqDAAABABYAGwMAAACAE0A6gwAAAYAVQASAAYJHyEAKgAKAgZoDAAABgBZAGkMAAAGAFIAawwAAAYAVABqDAAABABYAGwMAAACAE0A6gwAAAYAVQAAAA==.',
Gn='Gnomekabobs:BAAALgADCgEJAQABLgAECggJLQAWAL0hAA==.',
Gy='Gyllene:BAAALgADCgMJAwAAAA==.',
Ha='Hadory:BAABLgAECn8WAAITAAgJfhDmUgDoAQhoDAAABAAsAGkMAAAEADYAawwAAAMAQABqDAAAAwA8AGwMAAADAC0AbQwAAAEAEwDqDAAAAwAzAG4MAAABABAAEwAICX4Q5lIA6AEIaAwAAAQALABpDAAABAA2AGsMAAADAEAAagwAAAMAPABsDAAAAwAtAG0MAAABABMA6gwAAAMAMwBuDAAAAQAQAAAA.Harakki:BAABLgAECn8dAAIXAAgJHRMaBwCIAQhoDAAABABRAGkMAAAEAEMAawwAAAUAJABqDAAABAA5AGwMAAAEADEAbQwAAAEAHADqDAAABgAyAG4MAAABABsAFwAICR0TGgcAiAEIaAwAAAQAUQBpDAAABABDAGsMAAAFACQAagwAAAQAOQBsDAAABAAxAG0MAAABABwA6gwAAAYAMgBuDAAAAQAbAAAA.Hardscope:BAAALgAECgYJEAAAAA==.Havilove:BAAALgADCgIJAgAAAA==.',
He='Herbie:BAAALgADCgMJBAABLgAECgUJCgAOAAAAAA==.',
Ho='Holyroran:BAABLgAECn8dAAIBAAYJkiK9EAA6AgZoDAAABQBTAGkMAAAGAFAAawwAAAUAXwBqDAAABgBYAGwMAAAEAFcA6gwAAAMAYAABAAYJkiK9EAA6AgZoDAAABQBTAGkMAAAGAFAAawwAAAUAXwBqDAAABgBYAGwMAAAEAFcA6gwAAAMAYAAAAA==.Hopseng:BAAALgADCgQJBAAAAA==.Hotsrock:BAAALgAECgEJAQAAAA==.',
Ia='Iamundeadian:BAEALgAECgYJAwABLgAECgkJAgAOAAAAAA==.',
Ic='Icdeadpeeple:BAABLgAECn8YAAMTAAYJUBGIfAAVAQZoDAAABQA2AGkMAAAFADUAawwAAAUAOQBqDAAAAgBFAGwMAAACABUA6gwAAAUAIgATAAYJuA6IfAAVAQZoDAAABQA2AGkMAAAFADUAawwAAAQAFwBqDAAAAQAvAGwMAAACABUA6gwAAAUAIgAYAAIJRhaJMwBDAAJrDAAAAQA5AGoMAAABAEUAAAA=.Icytouch:BAAALgAECgQJCwAAAA==.',
Il='Illijim:BAAALgAECgMJAwABLgAECggJIgAIAC4eAA==.',
Im='Immortal:BAAALgAECgkJCgAAAA==.',
Ip='Ipwnprince:BAAALgAECgEJAQAAAA==.',
Is='Isityummy:BAAALgAECgIJAQAAAA==.',
Ja='Jarakk:BAAALgADCgUJCAAAAA==.',
Je='Jedrek:BAAALgAECgEJAQAAAA==.Jellybeanrez:BAABLgAECn8aAAITAAYJTgd3mgDfAAZoDAAABgAiAGkMAAAFABMAawwAAAYAEgBqDAAAAgAXAGwMAAACAAkA6gwAAAUACwATAAYJTgd3mgDfAAZoDAAABgAiAGkMAAAFABMAawwAAAYAEgBqDAAAAgAXAGwMAAACAAkA6gwAAAUACwAAAA==.',
Jo='Jojolion:BAAALgAECgQJCAAAAA==.Jorrdan:BAAALgAECggJEAAAAA==.',
Ka='Kaidapixi:BAAALgADCgYJBgAAAA==.Kalacia:BAABLgAECn8ZAAIJAAgJNB3JMgD5AQhoDAAAAgBGAGkMAAAEAFcAawwAAAQASwBqDAAAAgAyAGwMAAADAFkAbQwAAAEAUADqDAAABgBGAG4MAAADADEACQAICTQdyTIA+QEIaAwAAAIARgBpDAAABABXAGsMAAAEAEsAagwAAAIAMgBsDAAAAwBZAG0MAAABAFAA6gwAAAYARgBuDAAAAwAxAAAA.',
Ke='Keysbricked:BAAALgAECgQJBgABLgAECgkJGAAZAFUUAA==.',
Ki='Kickflip:BAAALgAECgYJBgABLgAFFAYJFQAaAFwbAA==.Kikthebucket:BAAALgADCgEJAQAAAA==.',
Kr='Kraytoes:BAAALgADCgEJAQAAAA==.Kritz:BAAALgAECgUJCgAAAA==.',
La='Laine:BAABLgAECn8cAAIbAAYJMhyKHwDlAQZoDAAABQBcAGkMAAAHAFAAawwAAAYATgBqDAAAAgBJAOoMAAAGAFYAbgwAAAIAFgAbAAYJMhyKHwDlAQZoDAAABQBcAGkMAAAHAFAAawwAAAYATgBqDAAAAgBJAOoMAAAGAFYAbgwAAAIAFgAAAA==.Lastexile:BAAALgAECgEJAQAAAA==.',
Li='Linglinda:BAABLgAECn8XAAILAAkJMyBJAwDwAgloDAAAAwBaAGkMAAADAFkAawwAAAMAUQBqDAAAAgBaAGwMAAACAFAAbQwAAAEAOQDqDAAABQBcAG4MAAACAF8AbwwAAAIARgALAAkJMyBJAwDwAgloDAAAAwBaAGkMAAADAFkAawwAAAMAUQBqDAAAAgBaAGwMAAACAFAAbQwAAAEAOQDqDAAABQBcAG4MAAACAF8AbwwAAAIARgAAAA==.',
Lo='Lockstar:BAEALgAECgkJAgAAAA==.Lockwarior:BAACLgAFFH8gAAQCAAcJWh7fBQDxAQdoDAAABwBgAGkMAAAGAGAAawwAAAUATwBqDAAABQA5AGwMAAACAFwAbQwAAAEABgDqDAAABgBfAAIABgnvI98FAPEBBmgMAAAHAGAAaQwAAAYAYABrDAAABABPAGoMAAADADkAbAwAAAIAXADqDAAABgBfAAQAAQkAAGQEAFsAAWoMAAACADYAAwACCQgISBYAUQACawwAAAEAIgBtDAAAAQAGAC4ABAp/JAADAgAJCbcizQQAbgMAAgAJCbcizQQAbgMAAwABCQAAzoAADQAAAAA=.Loricarvonri:BAAALgAECgUJCAAAAA==.Lottiedottie:BAAALgAECgQJBAAAAA==.Love:BAAALgAECgQJBAAAAA==.',
Lu='Luciena:BAABLgAECn8ZAAIcAAgJEA6QFgBXAQhoDAAAAwAwAGkMAAADACUAawwAAAMALQBqDAAABAAZAGwMAAAEACcAbQwAAAIACADqDAAABAAsAG4MAAACABsAHAAICRAOkBYAVwEIaAwAAAMAMABpDAAAAwAlAGsMAAADAC0AagwAAAQAGQBsDAAABAAnAG0MAAACAAgA6gwAAAQALABuDAAAAgAbAAAA.Lunarheals:BAABLgAECn8dAAIbAAYJmBp/GACuAQZoDAAABQBIAGkMAAAGAEIAawwAAAUARABqDAAABQBGAGwMAAAFADgA6gwAAAMASQAbAAYJmBp/GACuAQZoDAAABQBIAGkMAAAGAEIAawwAAAUARABqDAAABQBGAGwMAAAFADgA6gwAAAMASQAAAA==.Lunasong:BAABLgAECn8WAAIHAAcJFgZRZgAEAQdoDAAAAwAOAGkMAAADABMAawwAAAQAEgBqDAAAAwAlAGwMAAADAAcAbQwAAAEABwDqDAAABQAaAAcABwkWBlFmAAQBB2gMAAADAA4AaQwAAAMAEwBrDAAABAASAGoMAAADACUAbAwAAAMABwBtDAAAAQAHAOoMAAAFABoAAAA=.Luxury:BAAALgAECgMJBgAAAA==.',
Ma='Marcagi:BAAALgADCgEJAQAAAA==.Martyulon:BAABLgAECn8VAAIVAAYJHxhIIAB7AQZoDAAAAwBJAGkMAAADAEcAawwAAAQAOgBqDAAAAwA2AGwMAAADAC0A6gwAAAUAQgAVAAYJHxhIIAB7AQZoDAAAAwBJAGkMAAADAEcAawwAAAQAOgBqDAAAAwA2AGwMAAADAC0A6gwAAAUAQgAAAA==.Maxlink:BAAALgADCgcJBgAAAA==.',
Me='Melikefire:BAABLgAECn8nAAIdAAkJ4ByRAAC+AgloDAAABQBeAGkMAAAEAFcAawwAAAQAPQBqDAAABAA5AGwMAAAEAF8AbQwAAAMAOADqDAAACQBJAG4MAAAEAEQAbwwAAAIANQAdAAkJ4ByRAAC+AgloDAAABQBeAGkMAAAEAFcAawwAAAQAPQBqDAAABAA5AGwMAAAEAF8AbQwAAAMAOADqDAAACQBJAG4MAAAEAEQAbwwAAAIANQAAAA==.Melikesword:BAAALgAECgQJBAAAAA==.',
Mo='Molda:BAAALgAECgcJEwAAAA==.Monkjimothy:BAABLgAECn8iAAQIAAgJLh5lCwAuAghoDAAABgBXAGkMAAAFAFMAawwAAAUASABqDAAABABbAGwMAAAEAEkAbQwAAAEAKADqDAAABwBaAG4MAAACAF0ACAAICe8bZQsALgIIaAwAAAQAVwBpDAAABABTAGsMAAAEAEgAagwAAAMAWwBsDAAAAwBJAG0MAAABACgA6gwAAAUATgBuDAAAAQBBAAsABQncHuo1AEgBBWgMAAACAEoAaQwAAAEARABrDAAAAQBEAOoMAAACAFoAbgwAAAEAXQAVAAIJdAonXgBVAAJqDAAAAQAeAGwMAAABABcAAAA=.Monko:BAAALgAECgEJAQABLgAFFAUJFAASAHckAA==.Moomie:BAAALgADCgMJAwAAAA==.Moonstrike:BAAALgAECggJEAAAAA==.Mortius:BAAALgADCgcJDAAAAA==.',
['Mí']='Míku:BAAALgAECgMJAwAAAA==.',
Na='Navier:BAAALgADCgMJAwAAAA==.',
No='Noice:BAAALgAECgIJAgABLgAFFAYJFQAaAFwbAA==.',
Od='Odinsknight:BAAALgAECggJEwAAAA==.',
Pa='Pandáam:BAAALgAECgEJAQAAAA==.Parkeidand:BAAALgAECggJEQAAAA==.',
Ph='Phreek:BAABLgAECn8XAAIJAAkJdxI6eQDfAQloDAAABAA3AGkMAAADADgAawwAAAMAMQBqDAAAAgAxAGwMAAACAEgAbQwAAAEAFADqDAAABgA5AG4MAAABACYAbwwAAAEAGwAJAAkJdxI6eQDfAQloDAAABAA3AGkMAAADADgAawwAAAMAMQBqDAAAAgAxAGwMAAACAEgAbQwAAAEAFADqDAAABgA5AG4MAAABACYAbwwAAAEAGwAAAA==.',
Po='Pookie:BAAALgAECgEJAQAAAA==.Portius:BAAALgADCggJDAAAAA==.Pouyan:BAABLgAECn8oAAISAAkJMRQKIgDeAQloDAAABwBWAGkMAAAGAEoAawwAAAYAQABqDAAABQA4AGwMAAAFAD4AbQwAAAIAFADqDAAABgBBAG4MAAACABAAbwwAAAEAEgASAAkJMRQKIgDeAQloDAAABwBWAGkMAAAGAEoAawwAAAYAQABqDAAABQA4AGwMAAAFAD4AbQwAAAIAFADqDAAABgBBAG4MAAACABAAbwwAAAEAEgAAAA==.',
Pr='Prfctpullout:BAAALgADCgIJAgAAAA==.',
Ra='Ra:BAABLgAECn88AAQUAAkJ2RKwBQDgAQloDAAACwA3AGkMAAAIACkAawwAAAgAOQBqDAAABgA0AGwMAAAHAFMAbQwAAAQAIgDqDAAACAAsAG4MAAAFADEAbwwAAAMAEgAUAAkJ2RKwBQDgAQloDAAACQA3AGkMAAAGACkAawwAAAYAOQBqDAAABQA0AGwMAAAHAFMAbQwAAAQAIgDqDAAACAAsAG4MAAAFADEAbwwAAAMAEgAcAAQJZAydLwCTAARoDAAAAgAZAGkMAAABAB4AawwAAAEAJwBqDAAAAQATABAAAgkpB6i2AFEAAmkMAAABABAAawwAAAEAEwAAAA==.Racinette:BAACLgAFFH8XAAIBAAUJtiOyBQDoAQVoDAAABwBPAGkMAAAHAF0AawwAAAMAYwBqDAAAAQBfAOoMAAAFAFkAAQAFCbYjsgUA6AEFaAwAAAcATwBpDAAABwBdAGsMAAADAGMAagwAAAEAXwDqDAAABQBZAC4ABAp/GgACAQAJCfskvwUAEAMAAQAJCfskvwUAEAMAAAA=.',
Re='Rebexha:BAAALgAECgQJDAAAAA==.Redia:BAAALgAECgEJAQAAAA==.Relvanas:BAAALgAECgYJEwAAAA==.',
Ri='Riverside:BAAALgAECgYJBgAAAA==.',
Sa='Saelesth:BAAALgAECggJEAAAAA==.Sambie:BAABLgAECn8cAAIHAAcJigL/fADLAAdoDAAABAAFAGkMAAAEAAcAawwAAAUABwBqDAAABAAMAGwMAAAEAAkA6gwAAAYABQBuDAAAAQAEAAcABwmKAv98AMsAB2gMAAAEAAUAaQwAAAQABwBrDAAABQAHAGoMAAAEAAwAbAwAAAQACQDqDAAABgAFAG4MAAABAAQAAAA=.',
Sc='Scantron:BAAALgAECgYJCAAAAA==.Scrappycocco:BAAALgAECgUJDAAAAA==.Scuffedbones:BAAALgAFFAEJAQABLgAFFAUJBQANAFMDAA==.Scuffedbop:BAAALgADCgcJDQABLgAFFAUJBQANAFMDAA==.Scuffedfaith:BAABLgAECn8bAAMeAAgJ0BpFDAA9AghoDAAABABMAGkMAAAFAF8AawwAAAUAYABqDAAAAwBfAGwMAAADADgAbQwAAAIAUgDqDAAAAwAZAG4MAAACABQAHgAHCYUdRQwAPQIHaAwAAAQATABpDAAABABfAGsMAAAEAGAAagwAAAIAXwBsDAAAAwA4AG0MAAACAFIA6gwAAAIAGQAfAAUJ4QRsSQC4AAVpDAAAAQAMAGsMAAABAA0AagwAAAEAAgDqDAAAAQAOAG4MAAACAAkAAS4ABRQFCQUADQBTAwA=.',
Se='Sefyra:BAABLgAECn8YAAIHAAYJihOeUwA1AQZoDAAABQAzAGkMAAAFACsAawwAAAUAPABqDAAAAgAtAGwMAAACADQA6gwAAAUAKgAHAAYJihOeUwA1AQZoDAAABQAzAGkMAAAFACsAawwAAAUAPABqDAAAAgAtAGwMAAACADQA6gwAAAUAKgAAAA==.Setelai:BAAALgADCgUJBQAAAA==.',
Sh='Shankz:BAAALgADCgEJAQAAAA==.Shishi:BAAALgADCgcJCAAAAA==.',
Si='Sinful:BAAALgAECgIJAgAAAA==.',
Sn='Sneakycress:BAAALgAECgQJBwAAAA==.Snolo:BAAALgAECgYJEwAAAA==.Snowyrose:BAAALgAECgMJAwABLgAECgkJFwALADMgAA==.',
So='Sorakaa:BAAALgADCgUJBQAAAA==.Soulstoned:BAAALgADCgYJCQAAAA==.',
Sp='Spiritwarior:BAAALgAFFAIJAwABLgAFFAcJIAACAFoeAA==.Splux:BAAALgAECgUJBQAAAA==.',
St='Starsky:BAAALgADCgUJBgAAAA==.Strangedraco:BAAALgADCgYJBgAAAA==.Strangewood:BAABLgAECn82AAMNAAkJTwxJGQCSAQloDAAACAAXAGkMAAAJAB8AawwAAAkAHABqDAAABQASAGwMAAAFACAAbQwAAAMADADqDAAACQAuAG4MAAAEADgAbwwAAAIAEwANAAkJTwxJGQCSAQloDAAAAwAXAGkMAAAEAB8AawwAAAQAHABqDAAAAwASAGwMAAAEACAAbQwAAAMADADqDAAABgAuAG4MAAADADgAbwwAAAIAEwASAAcJGxRSRgCIAQdoDAAABQBYAGkMAAAFAEwAawwAAAUARABqDAAAAgAxAGwMAAABAA4A6gwAAAMALgBuDAAAAQAPAAAA.',
Su='Sugarhzopurp:BAAALgAECgcJCAAAAA==.Summerss:BAAALgADCggJCAAAAA==.',
Sw='Swiftlee:BAAALgAECgYJBwAAAA==.',
Th='Thunderfnk:BAABLgAECn8YAAIZAAgJVRSVHwB6AQhoDAAABABIAGkMAAAEAEEAawwAAAQAMQBqDAAAAwAlAGwMAAADAFEAbQwAAAEAEwDqDAAABAA5AG4MAAABABEAGQAICVUUlR8AegEIaAwAAAQASABpDAAABABBAGsMAAAEADEAagwAAAMAJQBsDAAAAwBRAG0MAAABABMA6gwAAAQAOQBuDAAAAQARAAAA.',
Tr='Trickydice:BAAALgAECgQJBAAAAA==.',
Ty='Tysreaper:BAABLgAECn8YAAMCAAgJLBKFXACzAQhoDAAABAAnAGkMAAAEAD4AawwAAAQAPgBqDAAAAwAwAGwMAAADAD4AbQwAAAEAFADqDAAABAA1AG4MAAABABkAAgAICVYRhVwAswEIaAwAAAMAJwBpDAAAAgAvAGsMAAADAD4AagwAAAMAMABsDAAAAwA+AG0MAAABABQA6gwAAAQANQBuDAAAAQAZAAQAAwlxD/kYALMAA2gMAAABAAoAaQwAAAIAPgBrDAAAAQAtAAAA.',
Ur='Urickea:BAAALgAECgEJAQAAAA==.',
Va='Valdyr:BAABLgAECn8dAAITAAgJVh9EGABiAghoDAAABABWAGkMAAAEAFcAawwAAAUATgBqDAAABABTAGwMAAAEAGAAbQwAAAEAPQDqDAAABgBcAG4MAAABADoAEwAICVYfRBgAYgIIaAwAAAQAVgBpDAAABABXAGsMAAAFAE4AagwAAAQAUwBsDAAABABgAG0MAAABAD0A6gwAAAYAXABuDAAAAQA6AAAA.Vannishstrik:BAAALgAECgQJBAAAAA==.Varri:BAAALgADCgMJAwAAAA==.',
Vo='Vodouism:BAAALgAECgUJBQABLgAECgYJFQASACAjAA==.Vonbane:BAAALgADCgYJCAAAAA==.',
Vu='Vu:BAAALgAECgYJBgAAAA==.',
Wa='Warcawk:BAAALgAECgYJEgAAAA==.Wardsky:BAAALgAECgYJCgAAAA==.',
We='Webbington:BAAALgAECgEJAQAAAA==.',
Wr='Wreckthar:BAABLgAECn88AAMTAAkJNiKUBAAhAwloDAAACgBeAGkMAAAKAF0AawwAAAoAYgBqDAAACABhAGwMAAAGAFAAbQwAAAMAUgDqDAAACABZAG4MAAAEAGAAbwwAAAEAQQATAAkJNiKUBAAhAwloDAAACQBeAGkMAAAKAF0AawwAAAoAYgBqDAAACABhAGwMAAAGAFAAbQwAAAMAUgDqDAAABwBZAG4MAAAEAGAAbwwAAAEAQQAYAAIJPxmVJQCKAAJoDAAAAQAtAOoMAAABAFMAAAA=.',
Wu='Wu:BAABLgAECn8WAAILAAgJPBAkHABnAQhoDAAABAAuAGkMAAAFADMAawwAAAQAKgBqDAAAAgApAGwMAAACAC8AbQwAAAEAIADqDAAAAwArAG4MAAABABsACwAICTwQJBwAZwEIaAwAAAQALgBpDAAABQAzAGsMAAAEACoAagwAAAIAKQBsDAAAAgAvAG0MAAABACAA6gwAAAMAKwBuDAAAAQAbAAEuAAQKCAkhAAIAfB8A.',
Xe='Xelagos:BAAALgAECgcJBwABLgAECggJIQACAHwfAA==.',
Xy='Xyla:BAAALgADCgEJAQAAAA==.',
Ze='Zenetrawr:BAACLgAFFH8FAAIaAAMJwQsJKQDUAANoDAAAAgAqAGkMAAACABcA6gwAAAEAFwAaAAMJwQsJKQDUAANoDAAAAgAqAGkMAAACABcA6gwAAAEAFwAuAAQKfzAAAhoACAmRFwYTAN8BABoACAmRFwYTAN8BAAAA.',
Zi='Zingispingus:BAABLgAECn8fAAINAAgJjQezKQAVAQhoDAAABgAXAGkMAAAFABEAawwAAAUAGQBqDAAABAAQAGwMAAAEABkAbQwAAAIACgDqDAAABAATAG8MAAABAA4ADQAICY0HsykAFQEIaAwAAAYAFwBpDAAABQARAGsMAAAFABkAagwAAAQAEABsDAAABAAZAG0MAAACAAoA6gwAAAQAEwBvDAAAAQAOAAAA.',
['Ær']='Ærìs:BAAALgADCgcJBwAAAA==.',
['Ða']='Ðaora:BAAALgADCgkJCgABLgAECgQJDAAOAAAAAA==.',
['ßa']='ßandamonium:BAAALgAECgYJBgAAAA==.',
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
