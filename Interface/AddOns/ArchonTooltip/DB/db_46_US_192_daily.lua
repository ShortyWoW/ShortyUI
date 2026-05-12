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

local lookup = {'Paladin-Holy','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Monk-Brewmaster','Mage-Frost','DeathKnight-Unholy','Unknown-Unknown','Mage-Arcane','Druid-Balance','Druid-Guardian','DemonHunter-Devourer','DeathKnight-Blood','Druid-Restoration','Paladin-Retribution','DemonHunter-Vengeance','Monk-Mistweaver','Hunter-Marksmanship','Hunter-BeastMastery','Warrior-Arms','DeathKnight-Frost','Shaman-Elemental','Evoker-Augmentation','Priest-Holy','DemonHunter-Havoc','Mage-Fire','Monk-Windwalker','Priest-Discipline','Priest-Shadow','Paladin-Protection',}
local provider = {region='US',realm='ShatteredHalls',name='US',type='daily',zone=46,date='2026-05-11',data={Al='Alannaria:BAAALgADCgQJBwAAAA==.Alaris:BAAALgAECgQJBAABLgAFFAUJEwABALYjAA==.Alex:BAAALgAECggJEAABLgAECggJIQACAHwfAA==.Allmight:BAAALgADCgIJAgAAAA==.Alx:BAABLgAECn8hAAQCAAcJfB9UOgCIAQdoDAAABgBXAGkMAAAGAFcAawwAAAUAUQBqDAAABQBAAGwMAAADAEsA6gwAAAYAWABuDAAAAgA+AAIABwkUHFQ6AIgBB2gMAAADADUAaQwAAAIAVwBrDAAAAgBRAGoMAAABACcAbAwAAAEASwDqDAAABQBGAG4MAAACAD4AAwAECSAZvSUAMAEEaQwAAAIARQBrDAAAAQBOAGoMAAAEAEAAbAwAAAIALQAEAAQJXyFIEAApAQRoDAAAAwBXAGkMAAACAFQAawwAAAIAUADqDAAAAQBYAAAA.',
Au='Audrey:BAAALgAECggJEgAAAA==.',
Av='Avoe:BAAALgADCgYJBgAAAA==.',
Ba='Banakafalata:BAABLgAECn8VAAIFAAYJsAppMgDbAAZoDAAABQA/AGkMAAAFABQAawwAAAQAEQBqDAAAAgArAGwMAAABAAoA6gwAAAQAGgAFAAYJsAppMgDbAAZoDAAABQA/AGkMAAAFABQAawwAAAQAEQBqDAAAAgArAGwMAAABAAoA6gwAAAQAGgABLgAECgkJJAAGAMIUAA==.Bat:BAAALgAECgUJCAAAAA==.',
Be='Beautieful:BAAALgADCgcJEQAAAA==.Bevo:BAAALgAECgYJBgAAAA==.',
Bi='Bigsha:BAAALgADCgYJCwAAAA==.',
Bl='Blux:BAAALgADCgUJBQAAAA==.',
Bo='Bondagestyle:BAAALgADCgIJAgAAAA==.Borgor:BAABLgAECn8pAAIHAAgJKiIVGwDbAghoDAAACABhAGkMAAAHAGEAawwAAAYASwBqDAAABABZAGwMAAAEAFoAbQwAAAMAVwDqDAAABwBZAG4MAAACAEoABwAICSoiFRsA2wIIaAwAAAgAYQBpDAAABwBhAGsMAAAGAEsAagwAAAQAWQBsDAAABABaAG0MAAADAFcA6gwAAAcAWQBuDAAAAgBKAAEuAAUUAQkCAAgAAAAA.',
Bt='Btterbean:BAAALgAECgMJBQAAAA==.',
Bu='Burdên:BAABLgAECn8cAAIJAAgJ9weCBABUAQhoDAAABAAQAGkMAAAEACAAawwAAAUAGwBqDAAABAAzAGwMAAAEABkAbQwAAAEADgDqDAAABQARAG4MAAABAAoACQAICfcHggQAVAEIaAwAAAQAEABpDAAABAAgAGsMAAAFABsAagwAAAQAMwBsDAAABAAZAG0MAAABAA4A6gwAAAUAEQBuDAAAAQAKAAAA.',
Ch='Chamber:BAAALgAECgQJBAAAAA==.Chambr:BAAALgAECgEJAQAAAA==.Chamchi:BAAALgAECgQJBAAAAA==.Cheri:BAACLgAFFH8JAAIKAAUJtQVnGQDwAAVoDAAAAwASAGkMAAACABAAawwAAAEABABqDAAAAQALAOoMAAACABIACgAFCbUFZxkA8AAFaAwAAAMAEgBpDAAAAgAQAGsMAAABAAQAagwAAAEACwDqDAAAAgASAC4ABAp/IQACCgAICeQapBsAJQIACgAICeQapBsAJQIAAAA=.',
Co='Codh:BAAALgAECgEJAgABLgAECgUJCgAIAAAAAA==.Codum:BAAALgAECgUJCgAAAA==.',
Da='Dackosaur:BAABLgAECn8cAAILAAgJdyFpAgCkAghoDAAABABdAGkMAAAEAF4AawwAAAUAXwBqDAAABABcAGwMAAAEAFEAbQwAAAEAUQDqDAAABQBbAG4MAAABAD4ACwAICXchaQIApAIIaAwAAAQAXQBpDAAABABeAGsMAAAFAF8AagwAAAQAXABsDAAABABRAG0MAAABAFEA6gwAAAUAWwBuDAAAAQA+AAAA.Dageek:BAAALgAECgEJAQAAAA==.Daneikus:BAAALgAECgMJAwAAAA==.Danekriste:BAABLgAECn8SAAIMAAYJyQWYgQClAAZoDAAAAwAWAGkMAAADAAcAawwAAAMADwBqDAAAAwAQAGwMAAAEABIA6gwAAAIACAAMAAYJyQWYgQClAAZoDAAAAwAWAGkMAAADAAcAawwAAAMADwBqDAAAAwAQAGwMAAAEABIA6gwAAAIACAAAAA==.Darkenedone:BAACLgAFFH8SAAINAAUJVhyWCgA2AQVoDAAABgBAAGkMAAAFAEUAawwAAAIAQQBqDAAAAQBDAOoMAAAEAFoADQAFCVYclgoANgEFaAwAAAYAQABpDAAABQBFAGsMAAACAEEAagwAAAEAQwDqDAAABABaAC4ABAp/GQADDQAJCbYbNhAACAIADQAJCbYbNhAACAIABwACCQ8SxxQBSwAAAAA=.',
Db='Dblackfalcon:BAAALgAECgEJAQAAAA==.',
De='Deathaura:BAAALgADCgMJAwAAAA==.Deathbyarrow:BAAALgADCgUJBQAAAA==.Demonex:BAAALgADCgMJAwABLgAECgQJBAAIAAAAAA==.Demono:BAABLgAECn8WAAIMAAYJExdGXgCGAQZoDAAABAAkAGkMAAAEAD4AawwAAAQAOABqDAAAAwAzAGwMAAADAD0A6gwAAAQATgAMAAYJExdGXgCGAQZoDAAABAAkAGkMAAAEAD4AawwAAAQAOABqDAAAAwAzAGwMAAADAD0A6gwAAAQATgABLgAFFAUJFAAOAHckAA==.Denton:BAAALgAECgQJBAAAAA==.',
Do='Doggx:BAAALgADCggJCwAAAA==.',
Dr='Drfrangelico:BAABLgAECn8ZAAMBAAgJqBGkGADVAQhoDAAABAA2AGkMAAAEAEYAawwAAAQAMgBqDAAAAwAdAGwMAAADACYAbQwAAAIAIwDqDAAAAwAlAG4MAAACAC0AAQAICagRpBgA1QEIaAwAAAMANgBpDAAAAwBGAGsMAAADADIAagwAAAIAHQBsDAAAAgAmAG0MAAABACMA6gwAAAIAJQBuDAAAAQAtAA8ACAnoBnpiADsBCGgMAAABABUAaQwAAAEAFABrDAAAAQANAGoMAAABABgAbAwAAAEACQBtDAAAAQAkAOoMAAABAAkAbgwAAAEADAAAAA==.Druido:BAACLgAFFH8UAAIOAAUJdyRKAQARAgVoDAAABABdAGkMAAAEAF0AawwAAAQAXABqDAAAAgBaAOoMAAAGAGAADgAFCXckSgEAEQIFaAwAAAQAXQBpDAAABABdAGsMAAAEAFwAagwAAAIAWgDqDAAABgBgAC4ABAp/LwADDgAJCdglLgAA7wMADgAJCdglLgAA7wMACgAECeghaxwAZAEAAAA=.Drunkmonk:BAAALgAECggJEAAAAA==.',
Ds='Ds:BAACLgAFFH8LAAIQAAQJ/B9YAQBRAQRoDAAABABbAGkMAAADAFAAawwAAAEAQQDqDAAAAwBaABAABAn8H1gBAFEBBGgMAAAEAFsAaQwAAAMAUABrDAAAAQBBAOoMAAADAFoALgAECn8kAAIQAAkJUSMoAQAnAwAQAAkJUSMoAQAnAwAAAA==.',
Du='Dumdum:BAAALgAECgQJBgAAAA==.',
En='Enjoyby:BAABLgAECn8YAAIRAAYJ1yLvCgBPAgZoDAAAAwBbAGkMAAAEAF0AawwAAAUAWQBqDAAABQBdAGwMAAAEAFsA6gwAAAMASgARAAYJ1yLvCgBPAgZoDAAAAwBbAGkMAAAEAF0AawwAAAUAWQBqDAAABQBdAGwMAAAEAFsA6gwAAAMASgAAAA==.',
Er='Erzascarlet:BAAALgADCgIJAgAAAA==.',
Ex='Exayah:BAAALgAECgQJBAAAAA==.',
Fi='Fistwarior:BAAALgAECgYJDAABLgAFFAYJHgACAO8jAA==.',
Fr='Frankßuck:BAABLgAECn8dAAMSAAYJ5wLHGwB2AAZoDAAABgAGAGkMAAAGAAkAawwAAAYACABqDAAABAAKAGwMAAAEAAYA6gwAAAMABQATAAYJ2AKOfQC1AAZoDAAABQAFAGkMAAAFAAkAawwAAAUACABqDAAAAwAKAGwMAAADAAYA6gwAAAIABQASAAYJDQLHGwB2AAZoDAAAAQAGAGkMAAABAAgAawwAAAEABABqDAAAAQAAAGwMAAABAAQA6gwAAAEAAQAAAA==.Friarstrange:BAAALgAECgYJDwAAAA==.Frosticle:BAAALgADCgEJAQAAAA==.',
Ga='Gaebora:BAABLgAECn8eAAIOAAYJHyEAKgAKAgZoDAAABgBZAGkMAAAGAFIAawwAAAYAVABqDAAABABYAGwMAAACAE0A6gwAAAYAVQAOAAYJHyEAKgAKAgZoDAAABgBZAGkMAAAGAFIAawwAAAYAVABqDAAABABYAGwMAAACAE0A6gwAAAYAVQAAAA==.',
Gn='Gnomekabobs:BAAALgADCgEJAQABLgAECggJJwAUAGYhAA==.',
Gy='Gyllene:BAAALgADCgMJAwAAAA==.',
Ha='Hadory:BAABLgAECn8WAAIPAAgJfhDlUgDoAQhoDAAABAAsAGkMAAAEADYAawwAAAMAQABqDAAAAwA8AGwMAAADAC0AbQwAAAEAEwDqDAAAAwAzAG4MAAABABAADwAICX4Q5VIA6AEIaAwAAAQALABpDAAABAA2AGsMAAADAEAAagwAAAMAPABsDAAAAwAtAG0MAAABABMA6gwAAAMAMwBuDAAAAQAQAAAA.Harakki:BAABLgAECn8cAAIVAAgJ/hJCBQCdAQhoDAAABABRAGkMAAAEAEMAawwAAAUAJABqDAAABAA5AGwMAAAEADEAbQwAAAEAHADqDAAABQAwAG4MAAABABsAFQAICf4SQgUAnQEIaAwAAAQAUQBpDAAABABDAGsMAAAFACQAagwAAAQAOQBsDAAABAAxAG0MAAABABwA6gwAAAUAMABuDAAAAQAbAAAA.Hardscope:BAAALgAECgYJEAAAAA==.Havilove:BAAALgADCgIJAgAAAA==.',
He='Herbie:BAAALgADCgIJAgABLgAECgUJCgAIAAAAAA==.',
Ho='Holyroran:BAABLgAECn8dAAIBAAYJkiJrDgBDAgZoDAAABQBTAGkMAAAGAFAAawwAAAUAXwBqDAAABgBYAGwMAAAEAFcA6gwAAAMAYAABAAYJkiJrDgBDAgZoDAAABQBTAGkMAAAGAFAAawwAAAUAXwBqDAAABgBYAGwMAAAEAFcA6gwAAAMAYAAAAA==.Hopseng:BAAALgADCgQJBAAAAA==.Hotsrock:BAAALgAECgEJAQAAAA==.',
Ia='Iamundeadian:BAAALgAECgMJAwABLgAECgkJAgAIAAAAAA==.',
Ic='Icdeadpeeple:BAAALgAECgYJEwAAAA==.Icytouch:BAAALgAECgQJCwAAAA==.',
Il='Illijim:BAAALgAECgMJAwABLgAECggJIQAFAC4eAA==.',
Im='Immortal:BAAALgAECgkJCQAAAA==.',
Ip='Ipwnprince:BAAALgAECgEJAQAAAA==.',
Is='Isityummy:BAAALgAECgIJAQAAAA==.',
Ja='Jarakk:BAAALgADCgUJCAAAAA==.',
Je='Jedrek:BAAALgAECgEJAQAAAA==.Jellybeanrez:BAABLgAECn8aAAIPAAYJTgeBiwDpAAZoDAAABgAiAGkMAAAFABMAawwAAAYAEgBqDAAAAgAXAGwMAAACAAkA6gwAAAUACwAPAAYJTgeBiwDpAAZoDAAABgAiAGkMAAAFABMAawwAAAYAEgBqDAAAAgAXAGwMAAACAAkA6gwAAAUACwAAAA==.',
Jo='Jojolion:BAAALgAECgQJCAAAAA==.Jorrdan:BAAALgAECggJDwAAAA==.',
Ka='Kaidapixi:BAAALgADCgYJBgAAAA==.Kalacia:BAABLgAECn8ZAAIGAAgJNB1SKgAIAghoDAAAAgBGAGkMAAAEAFcAawwAAAQASwBqDAAAAgAyAGwMAAADAFkAbQwAAAEAUADqDAAABgBGAG4MAAADADEABgAICTQdUioACAIIaAwAAAIARgBpDAAABABXAGsMAAAEAEsAagwAAAIAMgBsDAAAAwBZAG0MAAABAFAA6gwAAAYARgBuDAAAAwAxAAAA.',
Ke='Keysbricked:BAAALgAECgQJBgABLgAECgkJGAAWAFUUAA==.',
Ki='Kickflip:BAAALgAECgYJBgABLgAFFAYJEQAXAFwYAA==.Kikthebucket:BAAALgADCgEJAQAAAA==.',
Kr='Kraytoes:BAAALgADCgEJAQAAAA==.Kritz:BAAALgAECgUJBwAAAA==.',
La='Laine:BAABLgAECn8cAAIYAAYJMhyJHwDlAQZoDAAABQBcAGkMAAAHAFAAawwAAAYATgBqDAAAAgBJAOoMAAAGAFYAbgwAAAIAFgAYAAYJMhyJHwDlAQZoDAAABQBcAGkMAAAHAFAAawwAAAYATgBqDAAAAgBJAOoMAAAGAFYAbgwAAAIAFgAAAA==.Lastexile:BAAALgAECgEJAQAAAA==.',
Li='Linglinda:BAAALgAFFAEJAgAAAA==.',
Lo='Lockstar:BAAALgAECgkJAgAAAA==.Lockwarior:BAACLgAFFH8eAAQCAAYJ7yM/BAD4AQZoDAAABwBgAGkMAAAGAGAAawwAAAUATwBqDAAABQA5AGwMAAACAFwA6gwAAAUAXwACAAYJ7yM/BAD4AQZoDAAABwBgAGkMAAAGAGAAawwAAAQATwBqDAAAAwA5AGwMAAACAFwA6gwAAAUAXwAEAAEJAABjBABbAAFqDAAAAgA2AAMAAQmdDZkVAFMAAWsMAAABACIALgAECn8kAAMCAAkJtyLNBABuAwACAAkJtyLNBABuAwADAAEJAADLgAANAAAAAA==.Loricarvonri:BAAALgAECgUJCAAAAA==.Lottiedottie:BAAALgAECgQJBAAAAA==.Love:BAAALgAECgQJBAAAAA==.',
Lu='Luciena:BAABLgAECn8ZAAIZAAgJEA49EwBsAQhoDAAAAwAwAGkMAAADACUAawwAAAMALQBqDAAABAAZAGwMAAAEACcAbQwAAAIACADqDAAABAAsAG4MAAACABsAGQAICRAOPRMAbAEIaAwAAAMAMABpDAAAAwAlAGsMAAADAC0AagwAAAQAGQBsDAAABAAnAG0MAAACAAgA6gwAAAQALABuDAAAAgAbAAAA.Lunarheals:BAABLgAECn8dAAIYAAYJmBrGFQC4AQZoDAAABQBIAGkMAAAGAEIAawwAAAUARABqDAAABQBGAGwMAAAFADgA6gwAAAMASQAYAAYJmBrGFQC4AQZoDAAABQBIAGkMAAAGAEIAawwAAAUARABqDAAABQBGAGwMAAAFADgA6gwAAAMASQAAAA==.Lunasong:BAABLgAECn8VAAITAAcJggV8XQAJAQdoDAAAAwAOAGkMAAADABMAawwAAAQAEgBqDAAAAwAlAGwMAAADAAcAbQwAAAEABwDqDAAABAARABMABwmCBXxdAAkBB2gMAAADAA4AaQwAAAMAEwBrDAAABAASAGoMAAADACUAbAwAAAMABwBtDAAAAQAHAOoMAAAEABEAAAA=.Luxury:BAAALgAECgMJBgAAAA==.',
Ma='Marcagi:BAAALgADCgEJAQAAAA==.Martyulon:BAABLgAECn8UAAIRAAYJHxiAGwCFAQZoDAAAAwBJAGkMAAADAEcAawwAAAQAOgBqDAAAAwA2AGwMAAADAC0A6gwAAAQAQgARAAYJHxiAGwCFAQZoDAAAAwBJAGkMAAADAEcAawwAAAQAOgBqDAAAAwA2AGwMAAADAC0A6gwAAAQAQgAAAA==.Maxlink:BAAALgADCgcJBgAAAA==.',
Me='Melikefire:BAABLgAECn8fAAIaAAkJzxqkAACSAgloDAAABABOAGkMAAADAEAAawwAAAMAPQBqDAAAAwA5AGwMAAAEAF8AbQwAAAMAOADqDAAABwBJAG4MAAADAEIAbwwAAAEAMwAaAAkJzxqkAACSAgloDAAABABOAGkMAAADAEAAawwAAAMAPQBqDAAAAwA5AGwMAAAEAF8AbQwAAAMAOADqDAAABwBJAG4MAAADAEIAbwwAAAEAMwAAAA==.Melikesword:BAAALgAECgQJBAAAAA==.',
Mo='Molda:BAAALgAECgcJEwAAAA==.Monkjimothy:BAABLgAECn8hAAQFAAgJLh6KCQA7AghoDAAABgBXAGkMAAAFAFMAawwAAAUASABqDAAABABbAGwMAAAEAEkAbQwAAAEAKADqDAAABgBaAG4MAAACAF0ABQAICe8bigkAOwIIaAwAAAQAVwBpDAAABABTAGsMAAAEAEgAagwAAAMAWwBsDAAAAwBJAG0MAAABACgA6gwAAAQATgBuDAAAAQBBABsABQncHuU1AEgBBWgMAAACAEoAaQwAAAEARABrDAAAAQBEAOoMAAACAFoAbgwAAAEAXQARAAIJdAonXgBVAAJqDAAAAQAeAGwMAAABABcAAAA=.Monko:BAAALgAECgEJAQABLgAFFAUJFAAOAHckAA==.Moomie:BAAALgADCgMJAwAAAA==.Moonstrike:BAAALgAECggJEAAAAA==.Mortius:BAAALgADCgcJCAAAAA==.',
['Mí']='Míku:BAAALgAECgMJAwAAAA==.',
Na='Navier:BAAALgADCgMJAwAAAA==.',
No='Noice:BAAALgAECgIJAgABLgAFFAYJEQAXAFwYAA==.',
Od='Odinsknight:BAAALgAECggJEwAAAA==.',
Pa='Pandáam:BAAALgAECgEJAQAAAA==.Parkeidand:BAAALgAECggJEQAAAA==.',
Ph='Phreek:BAABLgAECn8XAAIGAAkJdxI3eQDfAQloDAAABAA3AGkMAAADADgAawwAAAMAMQBqDAAAAgAxAGwMAAACAEgAbQwAAAEAFADqDAAABgA5AG4MAAABACYAbwwAAAEAGwAGAAkJdxI3eQDfAQloDAAABAA3AGkMAAADADgAawwAAAMAMQBqDAAAAgAxAGwMAAACAEgAbQwAAAEAFADqDAAABgA5AG4MAAABACYAbwwAAAEAGwAAAA==.',
Po='Pookie:BAAALgAECgEJAQAAAA==.Portius:BAAALgADCggJDAAAAA==.Pouyan:BAABLgAECn8mAAIOAAgJzRWJJwCjAQhoDAAABwBWAGkMAAAGAEoAawwAAAYAQABqDAAABQA4AGwMAAAFAD4AbQwAAAIAFADqDAAABQBBAG4MAAACABAADgAICc0ViScAowEIaAwAAAcAVgBpDAAABgBKAGsMAAAGAEAAagwAAAUAOABsDAAABQA+AG0MAAACABQA6gwAAAUAQQBuDAAAAgAQAAAA.',
Pr='Prfctpullout:BAAALgADCgIJAgAAAA==.',
Ra='Ra:BAABLgAECn8xAAMQAAkJ4Q/EBgCdAQloDAAACgA3AGkMAAAGACYAawwAAAYAJwBqDAAABQA0AGwMAAAGAD4AbQwAAAMAEQDqDAAABwAsAG4MAAAEADEAbwwAAAIAEgAQAAkJsg/EBgCdAQloDAAACAA3AGkMAAAFACYAawwAAAUAIwBqDAAABAA0AGwMAAAGAD4AbQwAAAMAEQDqDAAABwAsAG4MAAAEADEAbwwAAAIAEgAZAAQJZAxDKwCeAARoDAAAAgAZAGkMAAABAB4AawwAAAEAJwBqDAAAAQATAAAA.Racinette:BAACLgAFFH8TAAIBAAUJtiO0BADtAQVoDAAABgBPAGkMAAAGAF0AawwAAAIAYwBqDAAAAQBfAOoMAAAEAFkAAQAFCbYjtAQA7QEFaAwAAAYATwBpDAAABgBdAGsMAAACAGMAagwAAAEAXwDqDAAABABZAC4ABAp/GgACAQAJCfskvgUAEAMAAQAJCfskvgUAEAMAAAA=.',
Re='Rebexha:BAAALgAECgQJDAAAAA==.Redia:BAAALgAECgEJAQAAAA==.Relvanas:BAAALgAECgYJEwAAAA==.',
Ri='Riverside:BAAALgAECgYJBgAAAA==.',
Sa='Saelesth:BAAALgAECggJEAAAAA==.Sambie:BAABLgAECn8bAAITAAcJiAImcgDRAAdoDAAABAAFAGkMAAAEAAcAawwAAAUABwBqDAAABAAMAGwMAAAEAAkA6gwAAAUABABuDAAAAQAEABMABwmIAiZyANEAB2gMAAAEAAUAaQwAAAQABwBrDAAABQAHAGoMAAAEAAwAbAwAAAQACQDqDAAABQAEAG4MAAABAAQAAAA=.',
Sc='Scantron:BAAALgAECgYJCAAAAA==.Scrappycocco:BAAALgAECgUJDAAAAA==.Scuffedbones:BAAALgAFFAEJAQABLgAFFAUJBQAKAFMDAA==.Scuffedbop:BAAALgADCgcJDQABLgAFFAUJBQAKAFMDAA==.Scuffedfaith:BAABLgAECn8YAAMcAAgJsBm3DwDsAQhoDAAAAwA1AGkMAAAEAF8AawwAAAQAYABqDAAAAwBfAGwMAAADADgAbQwAAAIAUgDqDAAAAwAZAG4MAAACABQAHAAHCTwctw8A7AEHaAwAAAMANQBpDAAAAwBfAGsMAAADAGAAagwAAAIAXwBsDAAAAwA4AG0MAAACAFIA6gwAAAIAGQAdAAUJ4QRqSQC4AAVpDAAAAQAMAGsMAAABAA0AagwAAAEAAgDqDAAAAQAOAG4MAAACAAkAAS4ABRQFCQUACgBTAwA=.',
Se='Sefyra:BAAALgAECgYJEwAAAA==.Setelai:BAAALgADCgUJBQAAAA==.',
Sh='Shankz:BAAALgADCgEJAQAAAA==.Shishi:BAAALgADCgcJCAAAAA==.',
Si='Sinful:BAAALgAECgIJAgAAAA==.',
Sn='Sneakycress:BAAALgAECgQJBwAAAA==.Snolo:BAAALgAECgYJEwAAAA==.Snowyrose:BAAALgAECgMJAwABLgAFFAEJAgAIAAAAAA==.',
So='Sorakaa:BAAALgADCgUJBQAAAA==.Soulstoned:BAAALgADCgYJCQAAAA==.',
Sp='Spiritwarior:BAAALgAFFAIJAwABLgAFFAYJHgACAO8jAA==.Splux:BAAALgAECgUJBQAAAA==.',
St='Starsky:BAAALgADCgQJBAAAAA==.Strangedraco:BAAALgADCgYJBgAAAA==.Strangewood:BAABLgAECn8zAAMKAAkJXArcFgCWAQloDAAACAAXAGkMAAAJAB8AawwAAAkAHABqDAAABQASAGwMAAAFACAAbQwAAAMADADqDAAACAArAG4MAAADABYAbwwAAAEAEAAKAAkJXArcFgCWAQloDAAAAwAXAGkMAAAEAB8AawwAAAQAHABqDAAAAwASAGwMAAAEACAAbQwAAAMADADqDAAABQArAG4MAAACABYAbwwAAAEAEAAOAAcJGxRRRgCIAQdoDAAABQBYAGkMAAAFAEwAawwAAAUARABqDAAAAgAxAGwMAAABAA4A6gwAAAMALgBuDAAAAQAPAAAA.',
Su='Sugarhzopurp:BAAALgAECgcJCAAAAA==.Summerss:BAAALgADCggJCAAAAA==.',
Sw='Swiftlee:BAAALgAECgYJBwAAAA==.',
Th='Thunderfnk:BAABLgAECn8YAAIWAAgJVRRUGgCOAQhoDAAABABIAGkMAAAEAEEAawwAAAQAMQBqDAAAAwAlAGwMAAADAFEAbQwAAAEAEwDqDAAABAA5AG4MAAABABEAFgAICVUUVBoAjgEIaAwAAAQASABpDAAABABBAGsMAAAEADEAagwAAAMAJQBsDAAAAwBRAG0MAAABABMA6gwAAAQAOQBuDAAAAQARAAAA.',
Tr='Trickydice:BAAALgAECgQJBAAAAA==.',
Ty='Tysreaper:BAABLgAECn8YAAMCAAgJLBKBXACzAQhoDAAABAAnAGkMAAAEAD4AawwAAAQAPgBqDAAAAwAwAGwMAAADAD4AbQwAAAEAFADqDAAABAA1AG4MAAABABkAAgAICVYRgVwAswEIaAwAAAMAJwBpDAAAAgAvAGsMAAADAD4AagwAAAMAMABsDAAAAwA+AG0MAAABABQA6gwAAAQANQBuDAAAAQAZAAQAAwlxD/kYALMAA2gMAAABAAoAaQwAAAIAPgBrDAAAAQAtAAAA.',
Ur='Urickea:BAAALgAECgEJAQAAAA==.',
Va='Valdyr:BAABLgAECn8cAAIPAAgJDR/lEwBsAghoDAAABABWAGkMAAAEAFcAawwAAAUATgBqDAAABABTAGwMAAAEAGAAbQwAAAEAPQDqDAAABQBXAG4MAAABADoADwAICQ0f5RMAbAIIaAwAAAQAVgBpDAAABABXAGsMAAAFAE4AagwAAAQAUwBsDAAABABgAG0MAAABAD0A6gwAAAUAVwBuDAAAAQA6AAAA.Vannishstrik:BAAALgAECgQJBAAAAA==.Varri:BAAALgADCgMJAwAAAA==.',
Vo='Vodouism:BAAALgAECgUJBQABLgAECgYJFQAOACAjAA==.Vonbane:BAAALgADCgYJCAAAAA==.',
Vu='Vu:BAAALgAECgYJBgAAAA==.',
Wa='Warcawk:BAAALgAECgYJEgAAAA==.Wardsky:BAAALgAECgYJCgAAAA==.',
We='Webbington:BAAALgAECgEJAQAAAA==.',
Wr='Wreckthar:BAABLgAECn8zAAMPAAgJDSO7CQDMAghoDAAACQBbAGkMAAAJAF0AawwAAAkAYgBqDAAABwBhAGwMAAAFAE0AbQwAAAIAUgDqDAAABwBXAG4MAAADAGAADwAICQ0juwkAzAIIaAwAAAgAWwBpDAAACQBdAGsMAAAJAGIAagwAAAcAYQBsDAAABQBNAG0MAAACAFIA6gwAAAYAVwBuDAAAAwBgAB4AAgk/GVUjAIwAAmgMAAABAC0A6gwAAAEAUwAAAA==.',
Wu='Wu:BAABLgAECn8WAAIbAAgJPBBOGABzAQhoDAAABAAuAGkMAAAFADMAawwAAAQAKgBqDAAAAgApAGwMAAACAC8AbQwAAAEAIADqDAAAAwArAG4MAAABABsAGwAICTwQThgAcwEIaAwAAAQALgBpDAAABQAzAGsMAAAEACoAagwAAAIAKQBsDAAAAgAvAG0MAAABACAA6gwAAAMAKwBuDAAAAQAbAAEuAAQKCAkhAAIAfB8A.',
Xe='Xelagos:BAAALgAECgcJBwABLgAECggJIQACAHwfAA==.',
Xy='Xyla:BAAALgADCgEJAQAAAA==.',
Ze='Zenetrawr:BAABLgAECn8uAAIXAAgJYxSyEQDPAQhoDAAACgBIAGkMAAAJAD4AawwAAAcALABqDAAAAwA2AGwMAAAEACkAbQwAAAIAGQDqDAAABwA7AG4MAAAEADsAFwAICWMUshEAzwEIaAwAAAoASABpDAAACQA+AGsMAAAHACwAagwAAAMANgBsDAAABAApAG0MAAACABkA6gwAAAcAOwBuDAAABAA7AAAA.',
Zi='Zingispingus:BAABLgAECn8dAAIKAAcJ5Ae0KgABAQdoDAAABgAXAGkMAAAFABEAawwAAAUAGQBqDAAABAAQAGwMAAAEABkAbQwAAAIACgDqDAAAAwATAAoABwnkB7QqAAEBB2gMAAAGABcAaQwAAAUAEQBrDAAABQAZAGoMAAAEABAAbAwAAAQAGQBtDAAAAgAKAOoMAAADABMAAAA=.',
['Ær']='Ærìs:BAAALgADCgcJBwAAAA==.',
['Ða']='Ðaora:BAAALgADCgkJCgABLgAECgQJDAAIAAAAAA==.',
['ßa']='ßandamonium:BAAALgAECgUJBQAAAA==.',
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
