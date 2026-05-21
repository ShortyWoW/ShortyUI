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

local lookup = {'Paladin-Holy','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Hunter-Marksmanship','Hunter-Survival','Hunter-BeastMastery','Monk-Brewmaster','Mage-Frost','DeathKnight-Unholy','Monk-Windwalker','Mage-Arcane','Druid-Balance','Unknown-Unknown','Druid-Guardian','DemonHunter-Devourer','DeathKnight-Blood','Druid-Restoration','Paladin-Retribution','DemonHunter-Vengeance','Monk-Mistweaver','Warrior-Arms','DeathKnight-Frost','Paladin-Protection','Shaman-Elemental','Evoker-Augmentation','Priest-Holy','DemonHunter-Havoc','Mage-Fire','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','Priest-Shadow',}
local provider = {region='US',realm='ShatteredHalls',name='US',type='daily',zone=46,date='2026-05-20',data={Al='Alannaria:BAAALgADCgQJBwAAAA==.Alaris:BAAALgAECggJDAABLgAFFAUJHQABAN8kAA==.Alex:BAAALgAECggJEAABLgAECggJNAACAJ0hAA==.Allmight:BAAALgADCgIJAgAAAA==.Alx:BAABLgAECn80AAQCAAgJnSG8FwBzAghoDAAACABYAGkMAAAJAFcAawwAAAgAVABqDAAABwBAAGwMAAAGAEsAbQwAAAMAWADqDAAACABfAG4MAAADAFIAAgAICZ0hvBcAcwIIaAwAAAUAWABpDAAABQBXAGsMAAAFAFQAagwAAAMAJwBsDAAABABLAG0MAAADAFgA6gwAAAcAXwBuDAAAAwBSAAMABAkgGb0lADABBGkMAAACAEUAawwAAAEATgBqDAAABABAAGwMAAACAC0ABAAECV8hRxAAKQEEaAwAAAMAVwBpDAAAAgBUAGsMAAACAFAA6gwAAAEAWAAAAA==.',
Ar='Archom:BAAALgADCgYJBgAAAA==.',
Au='Audrey:BAABLgAECn8bAAQFAAkJax1qCQCrAQloDAAABQBLAGkMAAADACoAawwAAAMAWgBqDAAAAwBYAGwMAAADAE8AbQwAAAMATgDqDAAAAwA8AG4MAAADAFsAbwwAAAEAVAAFAAgJDxlqCQCrAQhoDAAAAgBLAGkMAAACACoAawwAAAIAPwBqDAAAAgBYAGwMAAADAE8AbQwAAAIATgDqDAAAAgA8AG4MAAACADEABgAGCTcPPSkAKAEGaAwAAAIAQgBpDAAAAQAGAGsMAAABAFoAagwAAAEARQBtDAAAAQAbAOoMAAABAAQABwADCe0dpZkAxwADaAwAAAEANQBuDAAAAQBbAG8MAAABAFQAAAA=.',
Av='Avoe:BAAALgADCgYJBgAAAA==.',
Ba='Banakafalata:BAABLgAECn8ZAAIIAAYJrgtFQQDQAAZoDAAABgA/AGkMAAAGABQAawwAAAQAEQBqDAAAAgArAGwMAAACABcA6gwAAAUAGgAIAAYJrgtFQQDQAAZoDAAABgA/AGkMAAAGABQAawwAAAQAEQBqDAAAAgArAGwMAAACABcA6gwAAAUAGgABLgAFFAMJBgAJANMJAA==.Bat:BAAALgAECgUJDAAAAA==.',
Be='Beautieful:BAAALgADCgcJEQAAAA==.Bevo:BAAALgAECgYJBgAAAA==.',
Bi='Bigsha:BAAALgADCgYJCwAAAA==.',
Bl='Blux:BAAALgADCgUJBQAAAA==.',
Bo='Bondagestyle:BAAALgADCgIJAgAAAA==.Borgor:BAABLgAECn8pAAIKAAgJKiIZGwDbAghoDAAACABhAGkMAAAHAGEAawwAAAYASwBqDAAABABZAGwMAAAEAFoAbQwAAAMAVwDqDAAABwBZAG4MAAACAEoACgAICSoiGRsA2wIIaAwAAAgAYQBpDAAABwBhAGsMAAAGAEsAagwAAAQAWQBsDAAABABaAG0MAAADAFcA6gwAAAcAWQBuDAAAAgBKAAEuAAUUAwkGAAsApBwA.',
Br='Braindead:BAAALgAECgUJBQAAAA==.',
Bt='Btterbean:BAAALgAECgMJBQAAAA==.',
Bu='Burdên:BAABLgAECn8pAAIMAAgJ0AvkBABoAQhoDAAABgAdAGkMAAAGADMAawwAAAcALABqDAAABgAzAGwMAAAGACEAbQwAAAIADgDqDAAABwAbAG4MAAABAAoADAAICdAL5AQAaAEIaAwAAAYAHQBpDAAABgAzAGsMAAAHACwAagwAAAYAMwBsDAAABgAhAG0MAAACAA4A6gwAAAcAGwBuDAAAAQAKAAAA.',
Ch='Chamber:BAAALgAECgQJBAAAAA==.Chambr:BAAALgAECgEJAQAAAA==.Chamchi:BAAALgAECgQJBAAAAA==.Cheri:BAACLgAFFH8LAAINAAUJtQWQIADdAAVoDAAAAwASAGkMAAACABAAawwAAAEABABqDAAAAQALAOoMAAAEABIADQAFCbUFkCAA3QAFaAwAAAMAEgBpDAAAAgAQAGsMAAABAAQAagwAAAEACwDqDAAABAASAC4ABAp/IQACDQAICeQaphsAJQIADQAICeQaphsAJQIAAAA=.',
Co='Codh:BAAALgAECgEJAgABLgAECgUJCwAOAAAAAA==.Codum:BAAALgAECgUJCwAAAA==.',
Da='Dackosaur:BAABLgAECn8pAAIPAAgJnCKQAwC2AghoDAAABgBdAGkMAAAGAF4AawwAAAcAXwBqDAAABgBcAGwMAAAGAFwAbQwAAAIAWgDqDAAABwBbAG4MAAABAD4ADwAICZwikAMAtgIIaAwAAAYAXQBpDAAABgBeAGsMAAAHAF8AagwAAAYAXABsDAAABgBcAG0MAAACAFoA6gwAAAcAWwBuDAAAAQA+AAAA.Dageek:BAAALgAECgEJAQAAAA==.Daneikus:BAAALgAECgQJBgAAAA==.Danekriste:BAABLgAECn8SAAIQAAYJyQVbqACcAAZoDAAAAwAWAGkMAAADAAcAawwAAAMADwBqDAAAAwAQAGwMAAAEABIA6gwAAAIACAAQAAYJyQVbqACcAAZoDAAAAwAWAGkMAAADAAcAawwAAAMADwBqDAAAAwAQAGwMAAAEABIA6gwAAAIACAAAAA==.Darkenedone:BAACLgAFFH8cAAIRAAUJJiGyCACAAQVoDAAACABLAGkMAAAHAFoAawwAAAQAUgBqDAAAAwBDAOoMAAAGAFoAEQAFCSYhsggAgAEFaAwAAAgASwBpDAAABwBaAGsMAAAEAFIAagwAAAMAQwDqDAAABgBaAC4ABAp/IQADEQAJCUIi+AIA8wIAEQAJCUIi+AIA8wIACgACCQ8SyhQBSwAAAAA=.',
Db='Dblackfalcon:BAAALgAECggJCQAAAA==.',
De='Deathaura:BAAALgADCgMJAwAAAA==.Deathbyarrow:BAAALgADCgUJBQAAAA==.Demonex:BAAALgADCgMJAwABLgAECgQJBAAOAAAAAA==.Demono:BAABLgAECn8WAAIQAAYJExdHXgCGAQZoDAAABAAkAGkMAAAEAD4AawwAAAQAOABqDAAAAwAzAGwMAAADAD0A6gwAAAQATgAQAAYJExdHXgCGAQZoDAAABAAkAGkMAAAEAD4AawwAAAQAOABqDAAAAwAzAGwMAAADAD0A6gwAAAQATgABLgAFFAYJFgASAKAjAA==.Denton:BAAALgAECgQJBQAAAA==.',
Do='Doggx:BAAALgAECgEJAgAAAA==.',
Dr='Drfrangelico:BAABLgAECn8ZAAMBAAgJqBGjJACvAQhoDAAABAA2AGkMAAAEAEYAawwAAAQAMgBqDAAAAwAdAGwMAAADACYAbQwAAAIAIwDqDAAAAwAlAG4MAAACAC0AAQAICagRoyQArwEIaAwAAAMANgBpDAAAAwBGAGsMAAADADIAagwAAAIAHQBsDAAAAgAmAG0MAAABACMA6gwAAAIAJQBuDAAAAQAtABMACAnoBl6JADMBCGgMAAABABUAaQwAAAEAFABrDAAAAQANAGoMAAABABgAbAwAAAEACQBtDAAAAQAkAOoMAAABAAkAbgwAAAEADAAAAA==.Druido:BAACLgAFFH8WAAISAAYJoCNKAQARAgZoDAAABABdAGkMAAAEAF0AawwAAAQAXABqDAAAAgBaAG0MAAABAFAA6gwAAAcAYAASAAYJoCNKAQARAgZoDAAABABdAGkMAAAEAF0AawwAAAQAXABqDAAAAgBaAG0MAAABAFAA6gwAAAcAYAAuAAQKfy8AAxIACQnYJS0AAO8DABIACQnYJS0AAO8DAA0ABAnoIacpAEkBAAAA.Drunkmonk:BAAALgAECggJEAAAAA==.',
Ds='Ds:BAACLgAFFH8TAAIUAAQJACIuAQCEAQRoDAAABgBbAGkMAAAFAFQAawwAAAMAUQDqDAAABQBaABQABAkAIi4BAIQBBGgMAAAGAFsAaQwAAAUAVABrDAAAAwBRAOoMAAAFAFoALgAECn8rAAIUAAkJdyMoAQAnAwAUAAkJdyMoAQAnAwAAAA==.',
Du='Dumdum:BAAALgAECgQJBgAAAA==.',
En='Enjoyby:BAABLgAECn8bAAIVAAYJ1yIUEwA5AgZoDAAABABbAGkMAAAFAF0AawwAAAYAWQBqDAAABQBdAGwMAAAEAFsA6gwAAAMASgAVAAYJ1yIUEwA5AgZoDAAABABbAGkMAAAFAF0AawwAAAYAWQBqDAAABQBdAGwMAAAEAFsA6gwAAAMASgAAAA==.',
Eo='Eocháid:BAAALgAECgEJAQABLgAFFAIJAgAOAAAAAA==.',
Er='Erzascarlet:BAAALgADCgIJAgAAAA==.',
Ex='Exayah:BAAALgAECgQJBAAAAA==.',
Fi='Fistwarior:BAAALgAECgYJDAABLgAFFAcJIAACAFoeAA==.',
Fr='Frankßuck:BAABLgAECn8jAAMFAAYJrQWGIwBqAAZoDAAABwAKAGkMAAAHAAkAawwAAAcADQBqDAAABQAKAGwMAAAFABoA6gwAAAQADAAHAAYJrQWAoQC1AAZoDAAABgAKAGkMAAAGAAkAawwAAAYADQBqDAAABAAKAGwMAAAEABoA6gwAAAMADAAFAAYJDQKGIwBqAAZoDAAAAQAGAGkMAAABAAgAawwAAAEABABqDAAAAQAAAGwMAAABAAQA6gwAAAEAAQAAAA==.Friarstrange:BAABLgAECn8UAAIVAAYJqAwEQQD4AAZoDAAABAAdAGkMAAAEACkAawwAAAQAKgBqDAAAAgAZAGwMAAACABUA6gwAAAQAIQAVAAYJqAwEQQD4AAZoDAAABAAdAGkMAAAEACkAawwAAAQAKgBqDAAAAgAZAGwMAAACABUA6gwAAAQAIQAAAA==.Frosticle:BAAALgADCgEJAQAAAA==.',
Ga='Gaebora:BAABLgAECn8eAAISAAYJHyEAKgAKAgZoDAAABgBZAGkMAAAGAFIAawwAAAYAVABqDAAABABYAGwMAAACAE0A6gwAAAYAVQASAAYJHyEAKgAKAgZoDAAABgBZAGkMAAAGAFIAawwAAAYAVABqDAAABABYAGwMAAACAE0A6gwAAAYAVQAAAA==.',
Gn='Gnomekabobs:BAAALgADCgEJAQABLgAECgkJLgAWAN4hAA==.',
Gy='Gyllene:BAAALgADCgMJAwAAAA==.',
Ha='Hadory:BAABLgAECn8WAAITAAgJfhDmUgDoAQhoDAAABAAsAGkMAAAEADYAawwAAAMAQABqDAAAAwA8AGwMAAADAC0AbQwAAAEAEwDqDAAAAwAzAG4MAAABABAAEwAICX4Q5lIA6AEIaAwAAAQALABpDAAABAA2AGsMAAADAEAAagwAAAMAPABsDAAAAwAtAG0MAAABABMA6gwAAAMAMwBuDAAAAQAQAAAA.Harakki:BAABLgAECn8pAAIXAAgJyhMPCQCjAQhoDAAABgBRAGkMAAAGAEMAawwAAAcALwBqDAAABgA5AGwMAAAGADIAbQwAAAIAHADqDAAABwAyAG4MAAABABsAFwAICcoTDwkAowEIaAwAAAYAUQBpDAAABgBDAGsMAAAHAC8AagwAAAYAOQBsDAAABgAyAG0MAAACABwA6gwAAAcAMgBuDAAAAQAbAAAA.Hardscope:BAAALgAECgYJEAAAAA==.Havilove:BAAALgADCgIJAgAAAA==.',
He='Herbie:BAAALgADCgMJBAABLgAECgUJCwAOAAAAAA==.',
Ho='Holyroran:BAABLgAECn8dAAIBAAYJkiJwFQAsAgZoDAAABQBTAGkMAAAGAFAAawwAAAUAXwBqDAAABgBYAGwMAAAEAFcA6gwAAAMAYAABAAYJkiJwFQAsAgZoDAAABQBTAGkMAAAGAFAAawwAAAUAXwBqDAAABgBYAGwMAAAEAFcA6gwAAAMAYAAAAA==.Hopseng:BAAALgADCgQJBAAAAA==.Hotsrock:BAAALgAECgEJAQAAAA==.',
['Hé']='Hécâté:BAAALgAECgQJBAAAAA==.',
Ia='Iamundeadian:BAEALgAECgYJAwABLgAECgkJAgAOAAAAAA==.',
Ic='Icdeadpeeple:BAABLgAECn8YAAMTAAYJUBGunwANAQZoDAAABQA2AGkMAAAFADUAawwAAAUAOQBqDAAAAgBFAGwMAAACABUA6gwAAAUAIgATAAYJuA6unwANAQZoDAAABQA2AGkMAAAFADUAawwAAAQAFwBqDAAAAQAvAGwMAAACABUA6gwAAAUAIgAYAAIJRhadOwA/AAJrDAAAAQA5AGoMAAABAEUAAAA=.Icytouch:BAAALgAECgQJDAAAAA==.',
Il='Illijim:BAAALgAECgMJAwABLgAECggJLgAIAKMhAA==.',
Im='Immortal:BAAALgAECgkJCgAAAA==.',
Ip='Ipwnprince:BAAALgAECgEJAQAAAA==.',
Is='Isityummy:BAAALgAECgIJAQAAAA==.',
Ja='Jarakk:BAAALgADCgUJCAAAAA==.',
Je='Jedrek:BAAALgAECgEJAQAAAA==.Jellybeanrez:BAABLgAECn8dAAITAAgJ4weWiAA1AQhoDAAABgAiAGkMAAAFABMAawwAAAYAEgBqDAAAAgAXAGwMAAACAAkAbQwAAAEAJgDqDAAABgAPAG4MAAABAAQAEwAICeMHlogANQEIaAwAAAYAIgBpDAAABQATAGsMAAAGABIAagwAAAIAFwBsDAAAAgAJAG0MAAABACYA6gwAAAYADwBuDAAAAQAEAAAA.',
Jo='Jojolion:BAAALgAECgQJCAAAAA==.Jorrdan:BAAALgAECgkJEwAAAA==.',
Ka='Kaidapixi:BAAALgADCgYJBgAAAA==.Kalacia:BAABLgAECn8hAAIJAAkJ/x3jFwCmAgloDAAAAwBGAGkMAAAFAFcAawwAAAUASwBqDAAAAwBWAGwMAAAEAFkAbQwAAAIAUADqDAAABgBGAG4MAAAEADoAbwwAAAEAUAAJAAkJ/x3jFwCmAgloDAAAAwBGAGkMAAAFAFcAawwAAAUASwBqDAAAAwBWAGwMAAAEAFkAbQwAAAIAUADqDAAABgBGAG4MAAAEADoAbwwAAAEAUAAAAA==.',
Ke='Keysbricked:BAAALgAECgQJBgABLgAECgkJGAAZAFUUAA==.',
Ki='Kickflip:BAAALgAECgYJBgABLgAFFAYJFQAaAFwbAA==.Kikthebucket:BAAALgADCgEJAQAAAA==.',
Kr='Kraytoes:BAAALgADCgEJAQAAAA==.Kritz:BAAALgAECgUJCgAAAA==.',
La='Laine:BAABLgAECn8cAAIbAAYJMhyKHwDlAQZoDAAABQBcAGkMAAAHAFAAawwAAAYATgBqDAAAAgBJAOoMAAAGAFYAbgwAAAIAFgAbAAYJMhyKHwDlAQZoDAAABQBcAGkMAAAHAFAAawwAAAYATgBqDAAAAgBJAOoMAAAGAFYAbgwAAAIAFgAAAA==.Lastexile:BAAALgAECgEJAQAAAA==.',
Li='Linglinda:BAACLgAFFH8GAAILAAMJpBwIEgAAAQNoDAAABABFAGkMAAABAEwA6gwAAAEASQALAAMJpBwIEgAAAQNoDAAABABFAGkMAAABAEwA6gwAAAEASQAuAAQKfxkAAgsACQkzIB4FANgCAAsACQkzIB4FANgCAAAA.',
Lo='Lockstar:BAEALgAECgkJAgAAAA==.Lockwarior:BAACLgAFFH8gAAQCAAcJWh4qCwDdAQdoDAAABwBgAGkMAAAGAGAAawwAAAUATwBqDAAABQA5AGwMAAACAFwAbQwAAAEABgDqDAAABgBfAAIABgnvIyoLAN0BBmgMAAAHAGAAaQwAAAYAYABrDAAABABPAGoMAAADADkAbAwAAAIAXADqDAAABgBfAAQAAQkAAGQEAFsAAWoMAAACADYAAwACCQgIlBgAUQACawwAAAEAIgBtDAAAAQAGAC4ABAp/JAADAgAJCbcizQQAbgMAAgAJCbcizQQAbgMAAwABCQAAzoAADQAAAAA=.Loricarvonri:BAAALgAECgUJCAAAAA==.Lottiedottie:BAAALgAECgQJBAAAAA==.Love:BAAALgAECgQJBAAAAA==.',
Lu='Luciena:BAABLgAECn8ZAAIcAAgJEA5UHABUAQhoDAAAAwAwAGkMAAADACUAawwAAAMALQBqDAAABAAZAGwMAAAEACcAbQwAAAIACADqDAAABAAsAG4MAAACABsAHAAICRAOVBwAVAEIaAwAAAMAMABpDAAAAwAlAGsMAAADAC0AagwAAAQAGQBsDAAABAAnAG0MAAACAAgA6gwAAAQALABuDAAAAgAbAAAA.Lunarheals:BAABLgAECn8gAAIbAAYJmBpTHgChAQZoDAAABgBIAGkMAAAHAEIAawwAAAYARABqDAAABQBGAGwMAAAFADgA6gwAAAMASQAbAAYJmBpTHgChAQZoDAAABgBIAGkMAAAHAEIAawwAAAYARABqDAAABQBGAGwMAAAFADgA6gwAAAMASQAAAA==.Lunasong:BAABLgAECn8WAAIHAAcJFgZTgAD/AAdoDAAAAwAOAGkMAAADABMAawwAAAQAEgBqDAAAAwAlAGwMAAADAAcAbQwAAAEABwDqDAAABQAaAAcABwkWBlOAAP8AB2gMAAADAA4AaQwAAAMAEwBrDAAABAASAGoMAAADACUAbAwAAAMABwBtDAAAAQAHAOoMAAAFABoAAAA=.Luxury:BAAALgAECgMJBgAAAA==.',
Ma='Marcagi:BAAALgADCgEJAQAAAA==.Martyguard:BAAALgAECgUJBQABLgAECgcJIQAVADsVAA==.Martyulon:BAABLgAECn8hAAMVAAcJOxUJJgCVAQdoDAAABQBJAGkMAAAFAEcAawwAAAYAOgBqDAAABQA2AGwMAAAFAC0AbQwAAAEACQDqDAAABgBCABUABwk7FQkmAJUBB2gMAAAEAEkAaQwAAAQARwBrDAAABQA6AGoMAAAEADYAbAwAAAQALQBtDAAAAQAJAOoMAAAGAEIACwAFCR0JCUgAsAAFaAwAAAEAHgBpDAAAAQAYAGsMAAABABIAagwAAAEAFgBsDAAAAQATAAAA.Maxlink:BAAALgAECgMJAwAAAA==.',
Me='Melikefire:BAACLgAFFH8GAAIdAAMJHBGDAQDvAANoDAAABAA6AGkMAAABABoA6gwAAAEALwAdAAMJHBGDAQDvAANoDAAABAA6AGkMAAABABoA6gwAAAEALwAuAAQKfyoAAh0ACQngHNIAAK4CAB0ACQngHNIAAK4CAAAA.Melikesword:BAAALgAECgQJBAAAAA==.',
Mo='Molda:BAAALgAECgcJEwAAAA==.Monkjimothy:BAABLgAECn8uAAQIAAgJoyEqCACNAghoDAAACABfAGkMAAAHAFQAawwAAAcAVQBqDAAABgBbAGwMAAAGAFEAbQwAAAIAQQDqDAAACABgAG4MAAACAF0ACAAICRMgKggAjQIIaAwAAAYAXwBpDAAABgBUAGsMAAAGAFUAagwAAAUAWwBsDAAABQBRAG0MAAACAEEA6gwAAAYAYABuDAAAAQBBAAsABQncHuo1AEgBBWgMAAACAEoAaQwAAAEARABrDAAAAQBEAOoMAAACAFoAbgwAAAEAXQAVAAIJdAonXgBVAAJqDAAAAQAeAGwMAAABABcAAAA=.Monko:BAAALgAECgEJAQABLgAFFAYJFgASAKAjAA==.Moomie:BAAALgADCgMJAwAAAA==.Moonstrike:BAAALgAECggJEAAAAA==.Mortius:BAAALgADCgcJDAAAAA==.',
['Mí']='Míku:BAAALgAECgMJAwAAAA==.',
Na='Navier:BAAALgADCgMJAwAAAA==.',
No='Noice:BAAALgAECgIJAgABLgAFFAYJFQAaAFwbAA==.',
Od='Odinsknight:BAABLgAECn8dAAQXAAgJSBFwCgCEAQhoDAAABgAuAGkMAAAFADAAawwAAAQANABqDAAABAAqAGwMAAADACwAbQwAAAIAGADqDAAABAA0AG4MAAABACkAFwAICZkQcAoAhAEIaAwAAAUALgBpDAAABAAwAGsMAAADACcAagwAAAQAKgBsDAAAAwAsAG0MAAACABgA6gwAAAMANABuDAAAAQApAAoAAwmwATsOAVgAA2gMAAABAAQAaQwAAAEABADqDAAAAQAEABEAAQlSFClJADQAAWsMAAABADQAAAA=.',
Pa='Pandáam:BAAALgAECgEJAQAAAA==.Parkeidand:BAAALgAECggJEQAAAA==.',
Ph='Phreek:BAABLgAECn8bAAIJAAkJdxI6eQDfAQloDAAABQA3AGkMAAAEADgAawwAAAQAMQBqDAAAAgAxAGwMAAACAEgAbQwAAAEAFADqDAAABwA5AG4MAAABACYAbwwAAAEAGwAJAAkJdxI6eQDfAQloDAAABQA3AGkMAAAEADgAawwAAAQAMQBqDAAAAgAxAGwMAAACAEgAbQwAAAEAFADqDAAABwA5AG4MAAABACYAbwwAAAEAGwAAAA==.',
Po='Pookie:BAAALgAECgEJAQAAAA==.Portius:BAAALgADCggJDQAAAA==.Pouyan:BAABLgAECn8uAAISAAkJhhR0JAD7AQloDAAACABWAGkMAAAHAEoAawwAAAcAQABqDAAABgA4AGwMAAAGAD4AbQwAAAMAGwDqDAAABgBBAG4MAAACABAAbwwAAAEAEgASAAkJhhR0JAD7AQloDAAACABWAGkMAAAHAEoAawwAAAcAQABqDAAABgA4AGwMAAAGAD4AbQwAAAMAGwDqDAAABgBBAG4MAAACABAAbwwAAAEAEgAAAA==.',
Pr='Prfctpullout:BAAALgADCgIJAgAAAA==.',
Ra='Ra:BAABLgAECn88AAQUAAkJ2RJsBwDTAQloDAAACwA3AGkMAAAIACkAawwAAAgAOQBqDAAABgA0AGwMAAAHAFMAbQwAAAQAIgDqDAAACAAsAG4MAAAFADEAbwwAAAMAEgAUAAkJ2RJsBwDTAQloDAAACQA3AGkMAAAGACkAawwAAAYAOQBqDAAABQA0AGwMAAAHAFMAbQwAAAQAIgDqDAAACAAsAG4MAAAFADEAbwwAAAMAEgAcAAQJZAxeOQCPAARoDAAAAgAZAGkMAAABAB4AawwAAAEAJwBqDAAAAQATABAAAgkpB3DQAFAAAmkMAAABABAAawwAAAEAEwAAAA==.Racinette:BAACLgAFFH8dAAIBAAUJ3ySaBgADAgVoDAAACABcAGkMAAAIAF0AawwAAAQAYwBqDAAAAwBhAOoMAAAGAFkAAQAFCd8kmgYAAwIFaAwAAAgAXABpDAAACABdAGsMAAAEAGMAagwAAAMAYQDqDAAABgBZAC4ABAp/GgACAQAJCfskvwUAEAMAAQAJCfskvwUAEAMAAAA=.',
Re='Rebexha:BAAALgAECgUJDQAAAA==.Redia:BAAALgAECgEJAQAAAA==.Relvanas:BAABLgAECn8bAAMeAAgJ3AZUIgBJAQhoDAAABgAPAGkMAAAFABwAawwAAAQAEABqDAAABAAxAGwMAAADAB4AbQwAAAEABQDqDAAAAwASAG4MAAABAAgAHgAICdwGVCIASQEIaAwAAAUADwBpDAAABQAcAGsMAAAEABAAagwAAAQAMQBsDAAAAgAeAG0MAAABAAUA6gwAAAIAEgBuDAAAAQAIAB8AAwkpAxAeAEIAA2gMAAABAAUAbAwAAAEADgDqDAAAAQADAAAA.',
Ri='Riverside:BAAALgAECgYJDgAAAA==.',
Sa='Saelesth:BAAALgAECggJEAAAAA==.Sambie:BAABLgAECn8iAAIHAAcJLwOnjQDiAAdoDAAABQAKAGkMAAAFAAkAawwAAAYACABqDAAABQAPAGwMAAAFAAkA6gwAAAcABgBuDAAAAQAEAAcABwkvA6eNAOIAB2gMAAAFAAoAaQwAAAUACQBrDAAABgAIAGoMAAAFAA8AbAwAAAUACQDqDAAABwAGAG4MAAABAAQAAAA=.',
Sc='Scantron:BAAALgAECgcJCgAAAA==.Scrappycocco:BAAALgAECgUJDAAAAA==.Scuffedbones:BAAALgAFFAEJAQABLgAFFAUJBgANAFMDAA==.Scuffedbop:BAAALgADCgcJDQABLgAFFAUJBgANAFMDAA==.Scuffedfaith:BAABLgAECn8bAAMgAAgJ0BpKEAAzAghoDAAABABMAGkMAAAFAF8AawwAAAUAYABqDAAAAwBfAGwMAAADADgAbQwAAAIAUgDqDAAAAwAZAG4MAAACABQAIAAHCYUdShAAMwIHaAwAAAQATABpDAAABABfAGsMAAAEAGAAagwAAAIAXwBsDAAAAwA4AG0MAAACAFIA6gwAAAIAGQAhAAUJ4QRsSQC4AAVpDAAAAQAMAGsMAAABAA0AagwAAAEAAgDqDAAAAQAOAG4MAAACAAkAAS4ABRQFCQYADQBTAwA=.',
Se='Sefyra:BAABLgAECn8YAAIHAAYJihOfbAAtAQZoDAAABQAzAGkMAAAFACsAawwAAAUAPABqDAAAAgAtAGwMAAACADQA6gwAAAUAKgAHAAYJihOfbAAtAQZoDAAABQAzAGkMAAAFACsAawwAAAUAPABqDAAAAgAtAGwMAAACADQA6gwAAAUAKgAAAA==.Setelai:BAAALgADCgUJBQAAAA==.',
Sh='Shankz:BAAALgADCgEJAQAAAA==.Shishi:BAAALgADCgkJCgAAAA==.',
Si='Sinful:BAAALgAECgIJAgAAAA==.',
Sn='Sneakycress:BAAALgAECgUJCQAAAA==.Snolo:BAABLgAECn8YAAIaAAYJkRI0OwAKAQZoDAAABQA3AGkMAAAFACoAawwAAAUAKwBqDAAABAA6AGwMAAADACsA6gwAAAIANAAaAAYJkRI0OwAKAQZoDAAABQA3AGkMAAAFACoAawwAAAUAKwBqDAAABAA6AGwMAAADACsA6gwAAAIANAAAAA==.Snowyrose:BAAALgAECgMJAwABLgAFFAMJBgALAKQcAA==.',
So='Sorakaa:BAAALgADCgUJBQAAAA==.Soulstoned:BAAALgADCgYJCQAAAA==.',
Sp='Spiritwarior:BAAALgAFFAIJAwABLgAFFAcJIAACAFoeAA==.Splux:BAAALgAECgUJBQAAAA==.',
St='Starsky:BAAALgADCgUJBgAAAA==.Strangedraco:BAAALgADCgYJBgAAAA==.Strangewood:BAACLgAFFH8GAAINAAMJSgRwJwCoAANoDAAABAAJAGkMAAABAA0A6gwAAAEACQANAAMJSgRwJwCoAANoDAAABAAJAGkMAAABAA0A6gwAAAEACQAuAAQKfzkAAw0ACQlPDLUfAJEBAA0ACQlPDLUfAJEBABIABwnPFFJGAIgBAAAA.',
Su='Sugarhzopurp:BAAALgAECgcJCAAAAA==.Summerss:BAAALgADCggJCAAAAA==.',
Sw='Swiftlee:BAAALgAECgYJBwAAAA==.',
Th='Thunderfnk:BAABLgAECn8YAAIZAAgJVRSzKQBpAQhoDAAABABIAGkMAAAEAEEAawwAAAQAMQBqDAAAAwAlAGwMAAADAFEAbQwAAAEAEwDqDAAABAA5AG4MAAABABEAGQAICVUUsykAaQEIaAwAAAQASABpDAAABABBAGsMAAAEADEAagwAAAMAJQBsDAAAAwBRAG0MAAABABMA6gwAAAQAOQBuDAAAAQARAAAA.',
Tr='Trickydice:BAAALgAECgUJBgAAAA==.',
Ty='Tysreaper:BAABLgAECn8YAAMCAAgJLBKFXACzAQhoDAAABAAnAGkMAAAEAD4AawwAAAQAPgBqDAAAAwAwAGwMAAADAD4AbQwAAAEAFADqDAAABAA1AG4MAAABABkAAgAICVYRhVwAswEIaAwAAAMAJwBpDAAAAgAvAGsMAAADAD4AagwAAAMAMABsDAAAAwA+AG0MAAABABQA6gwAAAQANQBuDAAAAQAZAAQAAwlxD/kYALMAA2gMAAABAAoAaQwAAAIAPgBrDAAAAQAtAAAA.',
Ur='Urickea:BAAALgAECgEJAQAAAA==.',
Va='Valdyr:BAABLgAECn8pAAITAAgJmx/yHABxAghoDAAABgBbAGkMAAAGAFcAawwAAAcATgBqDAAABgBbAGwMAAAGAGAAbQwAAAIAPQDqDAAABwBcAG4MAAABADoAEwAICZsf8hwAcQIIaAwAAAYAWwBpDAAABgBXAGsMAAAHAE4AagwAAAYAWwBsDAAABgBgAG0MAAACAD0A6gwAAAcAXABuDAAAAQA6AAAA.Vannishstrik:BAAALgAECgQJBAAAAA==.Varri:BAAALgADCgMJAwAAAA==.',
Vo='Vodouism:BAAALgAECgUJBQABLgAECgYJFQASACAjAA==.Vonbane:BAAALgADCgYJCAAAAA==.',
Vu='Vu:BAAALgAECgYJBgAAAA==.',
Wa='Warcawk:BAAALgAECgYJEgAAAA==.Wardsky:BAAALgAECgYJCgAAAA==.',
We='Webbington:BAAALgAECgEJAQAAAA==.',
Wr='Wreckthar:BAABLgAECn88AAMTAAkJNiLkBwANAwloDAAACgBeAGkMAAAKAF0AawwAAAoAYgBqDAAACABhAGwMAAAGAFAAbQwAAAMAUgDqDAAACABZAG4MAAAEAGAAbwwAAAEAQQATAAkJNiLkBwANAwloDAAACQBeAGkMAAAKAF0AawwAAAoAYgBqDAAACABhAGwMAAAGAFAAbQwAAAMAUgDqDAAABwBZAG4MAAAEAGAAbwwAAAEAQQAYAAIJPxkULACEAAJoDAAAAQAtAOoMAAABAFMAAAA=.',
Wu='Wu:BAABLgAECn8WAAILAAgJPBAWJABcAQhoDAAABAAuAGkMAAAFADMAawwAAAQAKgBqDAAAAgApAGwMAAACAC8AbQwAAAEAIADqDAAAAwArAG4MAAABABsACwAICTwQFiQAXAEIaAwAAAQALgBpDAAABQAzAGsMAAAEACoAagwAAAIAKQBsDAAAAgAvAG0MAAABACAA6gwAAAMAKwBuDAAAAQAbAAEuAAQKCAk0AAIAnSEA.',
Xe='Xelagos:BAAALgAECgcJBwABLgAECggJNAACAJ0hAA==.',
Xy='Xyla:BAAALgADCgEJAQAAAA==.',
Ze='Zenetrawr:BAACLgAFFH8IAAIaAAMJ2g5VLgDUAANoDAAAAwAqAGkMAAADACQA6gwAAAIAIgAaAAMJ2g5VLgDUAANoDAAAAwAqAGkMAAADACQA6gwAAAIAIgAuAAQKfzEAAhoACAm9F/0ZANkBABoACAm9F/0ZANkBAAAA.',
Zi='Zingispingus:BAABLgAECn8fAAINAAgJjQciMgAXAQhoDAAABgAXAGkMAAAFABEAawwAAAUAGQBqDAAABAAQAGwMAAAEABkAbQwAAAIACgDqDAAABAATAG8MAAABAA4ADQAICY0HIjIAFwEIaAwAAAYAFwBpDAAABQARAGsMAAAFABkAagwAAAQAEABsDAAABAAZAG0MAAACAAoA6gwAAAQAEwBvDAAAAQAOAAAA.',
['Ær']='Ærìs:BAAALgADCgcJBwAAAA==.',
['Ða']='Ðaora:BAAALgADCgkJCgABLgAECgUJDgAOAAAAAA==.',
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
