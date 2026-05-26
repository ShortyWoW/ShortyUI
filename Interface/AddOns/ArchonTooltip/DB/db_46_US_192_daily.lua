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

local lookup = {'Paladin-Holy','DeathKnight-Unholy','DeathKnight-Blood','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Hunter-BeastMastery','Hunter-Survival','Hunter-Marksmanship','Unknown-Unknown','Monk-Brewmaster','Mage-Frost','Monk-Windwalker','Mage-Arcane','Druid-Balance','Druid-Guardian','DemonHunter-Devourer','Druid-Restoration','Paladin-Retribution','DemonHunter-Vengeance','Monk-Mistweaver','Druid-Feral','Warrior-Arms','DeathKnight-Frost','Paladin-Protection','Shaman-Elemental','Evoker-Augmentation','Priest-Holy','DemonHunter-Havoc','Mage-Fire','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','Priest-Shadow',}
local provider = {region='US',realm='ShatteredHalls',name='US',type='daily',zone=46,date='2026-05-26',data={Ak='Ako:BAAALgAECgUJBQAAAA==.',
Al='Alannaria:BAAALgADCgQJBwAAAA==.Alaris:BAAALgAECggJDAABLgAFFAUJHQABAN8kAA==.Alex:BAABLgAECn8ZAAMCAAkJgBd7XQCUAQloDAAAAwBDAGkMAAAEAEMAawwAAAMAQwBqDAAAAgA1AGwMAAACAEAAbQwAAAEAJwDqDAAABgBMAG4MAAADAEsAbwwAAAEAFgACAAgJKBR7XQCUAQhoDAAAAwBDAGkMAAAEAEMAawwAAAMAQwBqDAAAAQA1AGwMAAABABMA6gwAAAUATABuDAAAAgAoAG8MAAABABYAAwAFCe8XOyMAFAEFagwAAAEAMABsDAAAAQBAAG0MAAABACcA6gwAAAEAQQBuDAAAAQBLAAEuAAUUAwkFAAQALgoA.Allmight:BAAALgADCgIJAgAAAA==.Alx:BAACLgAFFH8FAAMEAAMJLgqAbwC+AANoDAAAAgAXAGkMAAABABUA6gwAAAIAIAAEAAMJkQeAbwC+AANoDAAAAQADAGkMAAABABUA6gwAAAIAIAAFAAEJKQk3GgBNAAFoDAAAAQAXAC4ABAp/NAAEBAAICZAhahQAmwIABAAICZAhahQAmwIABgAECSAZvSUAMAEABQAECV8hRxAAKQEAAAA=.',
Ar='Archom:BAAALgADCgYJBgAAAA==.',
Au='Audrey:BAABLgAECn8kAAQHAAkJ2CMCCgDqAgloDAAABgBeAGkMAAAEAFgAawwAAAQAYQBqDAAABABYAGwMAAAEAFAAbQwAAAQAYADqDAAABABaAG4MAAAEAFsAbwwAAAIAXwAHAAcJeiQCCgDqAgdoDAAAAgBeAGkMAAABAFgAawwAAAEAYQBtDAAAAQBgAOoMAAABAFoAbgwAAAEAWwBvDAAAAgBfAAgACAlnFC8VAOYBCGgMAAACAEIAaQwAAAEABgBrDAAAAQBaAGoMAAACAEUAbAwAAAEAUABtDAAAAQAbAOoMAAABAAQAbgwAAAEAWgAJAAgJDxljCgCnAQhoDAAAAgBLAGkMAAACACoAawwAAAIAPwBqDAAAAgBYAGwMAAADAE8AbQwAAAIATgDqDAAAAgA8AG4MAAACADEAAS4ABRQCCQIACgAAAAA=.',
Av='Avoe:BAAALgADCgYJBgAAAA==.',
Ba='Banakafalata:BAABLgAECn8aAAILAAYJrgsyRQDPAAZoDAAABgA/AGkMAAAGABQAawwAAAQAEQBqDAAAAgArAGwMAAADABcA6gwAAAUAGgALAAYJrgsyRQDPAAZoDAAABgA/AGkMAAAGABQAawwAAAQAEQBqDAAAAgArAGwMAAADABcA6gwAAAUAGgABLgAFFAMJBwAMANMJAA==.Bat:BAAALgAECgUJDAAAAA==.',
Be='Beautieful:BAAALgADCgcJEQAAAA==.Bevo:BAAALgAECgYJBgAAAA==.',
Bi='Bigsha:BAAALgADCgYJCwAAAA==.',
Bl='Blux:BAAALgADCgUJBQAAAA==.',
Bo='Bondagestyle:BAAALgADCgIJAgAAAA==.Borgor:BAABLgAECn8pAAICAAgJKiIZGwDbAghoDAAACABhAGkMAAAHAGEAawwAAAYASwBqDAAABABZAGwMAAAEAFoAbQwAAAMAVwDqDAAABwBZAG4MAAACAEoAAgAICSoiGRsA2wIIaAwAAAgAYQBpDAAABwBhAGsMAAAGAEsAagwAAAQAWQBsDAAABABaAG0MAAADAFcA6gwAAAcAWQBuDAAAAgBKAAEuAAUUAwkHAA0A6xwA.',
Br='Braindead:BAAALgAECgUJBQAAAA==.',
Bt='Btterbean:BAAALgAECgMJBQAAAA==.',
Bu='Burdên:BAABLgAECn8qAAIOAAgJ0w3DBAB7AQhoDAAABgAdAGkMAAAGADMAawwAAAcALABqDAAABgAzAGwMAAAGACEAbQwAAAIADgDqDAAABwAbAG4MAAACAC4ADgAICdMNwwQAewEIaAwAAAYAHQBpDAAABgAzAGsMAAAHACwAagwAAAYAMwBsDAAABgAhAG0MAAACAA4A6gwAAAcAGwBuDAAAAgAuAAAA.',
By='Byng:BAAALgAECgEJAQAAAA==.',
Ch='Chamber:BAAALgAECgQJBAAAAA==.Chambr:BAAALgAECgEJAQAAAA==.Chamchi:BAAALgAECgQJBAAAAA==.Cheri:BAACLgAFFH8LAAIPAAUJtQXaJADcAAVoDAAAAwASAGkMAAACABAAawwAAAEABABqDAAAAQALAOoMAAAEABIADwAFCbUF2iQA3AAFaAwAAAMAEgBpDAAAAgAQAGsMAAABAAQAagwAAAEACwDqDAAABAASAC4ABAp/IwACDwAJCUwZphsAJQIADwAJCUwZphsAJQIAAAA=.',
Co='Codh:BAAALgAECgEJAgABLgAECgUJCwAKAAAAAA==.Codum:BAAALgAECgUJCwAAAA==.',
Cu='Cubenzi:BAAALgADCgkJBAAAAA==.',
Da='Dackosaur:BAABLgAECn8qAAIQAAgJUCPcAwDAAghoDAAABgBdAGkMAAAGAF4AawwAAAcAXwBqDAAABgBcAGwMAAAGAFwAbQwAAAIAWgDqDAAABwBbAG4MAAACAEsAEAAICVAj3AMAwAIIaAwAAAYAXQBpDAAABgBeAGsMAAAHAF8AagwAAAYAXABsDAAABgBcAG0MAAACAFoA6gwAAAcAWwBuDAAAAgBLAAAA.Dageek:BAAALgAECgEJAQAAAA==.Daneikus:BAAALgAECgYJCAAAAA==.Danekriste:BAABLgAECn8SAAIRAAYJyQVOtACYAAZoDAAAAwAWAGkMAAADAAcAawwAAAMADwBqDAAAAwAQAGwMAAAEABIA6gwAAAIACAARAAYJyQVOtACYAAZoDAAAAwAWAGkMAAADAAcAawwAAAMADwBqDAAAAwAQAGwMAAAEABIA6gwAAAIACAAAAA==.Darkenedone:BAACLgAFFH8cAAIDAAUJJiH1CwBuAQVoDAAACABLAGkMAAAHAFoAawwAAAQAUgBqDAAAAwBDAOoMAAAGAFoAAwAFCSYh9QsAbgEFaAwAAAgASwBpDAAABwBaAGsMAAAEAFIAagwAAAMAQwDqDAAABgBaAC4ABAp/IQADAwAJCUIiuQMA6QIAAwAJCUIiuQMA6QIAAgACCQ8SyhQBSwAAAAA=.',
Db='Dblackfalcon:BAAALgAECggJCQAAAA==.',
De='Deathaura:BAAALgAECgIJAgAAAA==.Deathbyarrow:BAAALgADCgUJBQAAAA==.Demonex:BAAALgADCgMJAwABLgAECgQJBAAKAAAAAA==.Demono:BAABLgAECn8WAAIRAAYJExdHXgCGAQZoDAAABAAkAGkMAAAEAD4AawwAAAQAOABqDAAAAwAzAGwMAAADAD0A6gwAAAQATgARAAYJExdHXgCGAQZoDAAABAAkAGkMAAAEAD4AawwAAAQAOABqDAAAAwAzAGwMAAADAD0A6gwAAAQATgABLgAFFAcJHAASAAkjAA==.Denton:BAAALgAECgQJBQAAAA==.',
Do='Doggx:BAAALgAECgcJCAAAAA==.',
Dr='Drfrangelico:BAABLgAECn8aAAMBAAgJqBEDKACtAQhoDAAABAA2AGkMAAAEAEYAawwAAAQAMgBqDAAAAwAdAGwMAAADACYAbQwAAAIAIwDqDAAAAwAlAG4MAAADAC0AAQAICagRAygArQEIaAwAAAMANgBpDAAAAwBGAGsMAAADADIAagwAAAIAHQBsDAAAAgAmAG0MAAABACMA6gwAAAIAJQBuDAAAAQAtABMACAnpBnWYACsBCGgMAAABABUAaQwAAAEAFABrDAAAAQANAGoMAAABABgAbAwAAAEACQBtDAAAAQAkAOoMAAABAAkAbgwAAAIADAAAAA==.Druido:BAACLgAFFH8cAAISAAcJCSNoAgDNAgdoDAAABQBdAGkMAAAFAF0AawwAAAUAXgBqDAAAAwBaAGwMAAABAE4AbQwAAAEAUADqDAAACABgABIABwkJI2gCAM0CB2gMAAAFAF0AaQwAAAUAXQBrDAAABQBeAGoMAAADAFoAbAwAAAEATgBtDAAAAQBQAOoMAAAIAGAALgAECn8yAAMSAAkJ2CUtAADvAwASAAkJ2CUtAADvAwAPAAQJ6CGYLQBGAQAAAA==.Drunkmonk:BAAALgAECggJEAAAAA==.',
Ds='Ds:BAACLgAFFH8TAAIUAAQJACKOAQB+AQRoDAAABgBbAGkMAAAFAFQAawwAAAMAUQDqDAAABQBaABQABAkAIo4BAH4BBGgMAAAGAFsAaQwAAAUAVABrDAAAAwBRAOoMAAAFAFoALgAECn8rAAIUAAkJdyMoAQAnAwAUAAkJdyMoAQAnAwAAAA==.',
Du='Dumdum:BAAALgAECgQJBgAAAA==.',
En='Enjoyby:BAABLgAECn8dAAIVAAgJZiH3CADhAghoDAAABABbAGkMAAAFAF0AawwAAAYAWQBqDAAABQBdAGwMAAAEAFsAbQwAAAEAUQDqDAAAAwBKAG4MAAABAEIAFQAICWYh9wgA4QIIaAwAAAQAWwBpDAAABQBdAGsMAAAGAFkAagwAAAUAXQBsDAAABABbAG0MAAABAFEA6gwAAAMASgBuDAAAAQBCAAAA.',
Eo='Eocháid:BAAALgAECgEJAQABLgAFFAIJAgAKAAAAAA==.',
Er='Erzascarlet:BAAALgADCgIJAgAAAA==.',
Ex='Exayah:BAAALgAECgQJBAAAAA==.',
Fi='Fistwarior:BAAALgAECgYJDAABLgAFFAcJIAAEAFweAA==.',
Fr='Frankßuck:BAABLgAECn8kAAMHAAcJOQUSjQD9AAdoDAAABwAKAGkMAAAHAAkAawwAAAcADQBqDAAABQAKAGwMAAAFABoAbQwAAAEABwDqDAAABAAMAAcABwk5BRKNAP0AB2gMAAAGAAoAaQwAAAYACQBrDAAABgANAGoMAAAEAAoAbAwAAAQAGgBtDAAAAQAHAOoMAAADAAwACQAGCQ0CwCUAagAGaAwAAAEABgBpDAAAAQAIAGsMAAABAAQAagwAAAEAAABsDAAAAQAEAOoMAAABAAEAAAA=.Friarstrange:BAABLgAECn8UAAIVAAYJqAwlSgD6AAZoDAAABAAdAGkMAAAEACkAawwAAAQAKgBqDAAAAgAZAGwMAAACABUA6gwAAAQAIQAVAAYJqAwlSgD6AAZoDAAABAAdAGkMAAAEACkAawwAAAQAKgBqDAAAAgAZAGwMAAACABUA6gwAAAQAIQAAAA==.Frosticle:BAAALgADCgEJAQAAAA==.',
Ga='Gaebora:BAABLgAECn8gAAMSAAgJdx4AKgAKAghoDAAABgBZAGkMAAAGAFIAawwAAAYAVABqDAAABABYAGwMAAACAE0AbQwAAAEAMgDqDAAABgBVAG4MAAABAEAAEgAGCR8hACoACgIGaAwAAAYAWQBpDAAABgBSAGsMAAAGAFQAagwAAAQAWABsDAAAAgBNAOoMAAAGAFUAFgACCboQei4AcwACbQwAAAEANQBuDAAAAQAgAAAA.',
Gn='Gnomekabobs:BAAALgADCgEJAQABLgAECgkJNwAXAFokAA==.',
Gy='Gyllene:BAAALgADCgMJAwAAAA==.',
Ha='Hadory:BAABLgAECn8WAAITAAgJfhDmUgDoAQhoDAAABAAsAGkMAAAEADYAawwAAAMAQABqDAAAAwA8AGwMAAADAC0AbQwAAAEAEwDqDAAAAwAzAG4MAAABABAAEwAICX4Q5lIA6AEIaAwAAAQALABpDAAABAA2AGsMAAADAEAAagwAAAMAPABsDAAAAwAtAG0MAAABABMA6gwAAAMAMwBuDAAAAQAQAAAA.Harakki:BAABLgAECn8qAAIYAAgJWhSTCgCdAQhoDAAABgBRAGkMAAAGAEMAawwAAAcALwBqDAAABgA5AGwMAAAGADIAbQwAAAIAHADqDAAABwAyAG4MAAACACUAGAAICVoUkwoAnQEIaAwAAAYAUQBpDAAABgBDAGsMAAAHAC8AagwAAAYAOQBsDAAABgAyAG0MAAACABwA6gwAAAcAMgBuDAAAAgAlAAAA.Hardscope:BAAALgAECgYJEAAAAA==.Havilove:BAAALgADCgIJAgAAAA==.',
He='Herbie:BAAALgADCgMJBAABLgAECgUJCwAKAAAAAA==.',
Ho='Holyroran:BAABLgAECn8eAAIBAAcJ/yG+DwCAAgdoDAAABQBTAGkMAAAGAFAAawwAAAUAXwBqDAAABgBYAGwMAAAEAFcAbQwAAAEATgDqDAAAAwBgAAEABwn/Ib4PAIACB2gMAAAFAFMAaQwAAAYAUABrDAAABQBfAGoMAAAGAFgAbAwAAAQAVwBtDAAAAQBOAOoMAAADAGAAAAA=.Hopseng:BAAALgADCgQJBAAAAA==.Hotsrock:BAAALgAECgEJAQAAAA==.',
['Hé']='Hécâté:BAAALgAFFAEJAQAAAA==.',
Ia='Iamundeadian:BAEALgAECgYJAwABLgAECgkJAgAKAAAAAA==.',
Ic='Icdeadpeeple:BAABLgAECn8ZAAMTAAYJSRObpQAVAQZoDAAABQA2AGkMAAAFADUAawwAAAUAOQBqDAAAAgBFAGwMAAADAC4A6gwAAAUAIgATAAYJsRCbpQAVAQZoDAAABQA2AGkMAAAFADUAawwAAAQAFwBqDAAAAQAvAGwMAAADAC4A6gwAAAUAIgAZAAIJRhYBQQA+AAJrDAAAAQA5AGoMAAABAEUAAAA=.Icytouch:BAAALgAECgYJEgAAAA==.',
Il='Illijim:BAAALgAECgMJAwABLgAECggJLwALAKMhAA==.',
Im='Immortal:BAAALgAECgkJCgAAAA==.',
Ip='Ipwnprince:BAAALgAECgEJAQAAAA==.',
Is='Isityummy:BAAALgAECgIJAQAAAA==.',
Ja='Jarakk:BAAALgADCgUJCAAAAA==.',
Je='Jedrek:BAAALgAECgEJAQAAAA==.Jellybeanrez:BAABLgAECn8iAAITAAgJ4wedlwAsAQhoDAAABwAiAGkMAAAGABMAawwAAAcAEgBqDAAAAwAXAGwMAAADAAkAbQwAAAEAJgDqDAAABgAPAG4MAAABAAQAEwAICeMHnZcALAEIaAwAAAcAIgBpDAAABgATAGsMAAAHABIAagwAAAMAFwBsDAAAAwAJAG0MAAABACYA6gwAAAYADwBuDAAAAQAEAAAA.',
Jo='Jojolion:BAAALgAECgQJCAAAAA==.Jorrdan:BAAALgAECgkJEwAAAA==.',
Ka='Kaidapixi:BAAALgADCgYJBgAAAA==.Kalacia:BAABLgAECn8nAAIMAAkJjB4dFwC5AgloDAAAAwBGAGkMAAAGAFcAawwAAAYAUABqDAAABABXAGwMAAAFAF0AbQwAAAIAUADqDAAABwBIAG4MAAAFADoAbwwAAAEAUAAMAAkJjB4dFwC5AgloDAAAAwBGAGkMAAAGAFcAawwAAAYAUABqDAAABABXAGwMAAAFAF0AbQwAAAIAUADqDAAABwBIAG4MAAAFADoAbwwAAAEAUAAAAA==.',
Ke='Keysbricked:BAAALgAECgQJBgABLgAECgkJGAAaAFUUAA==.',
Ki='Kickflip:BAAALgAECgYJBgABLgAFFAYJFQAbAFwbAA==.Kikthebucket:BAAALgADCgEJAQAAAA==.',
Kr='Kraytoes:BAAALgADCgEJAQAAAA==.Kritz:BAAALgAECggJDwAAAA==.',
La='Laine:BAABLgAECn8cAAIcAAYJMhyKHwDlAQZoDAAABQBcAGkMAAAHAFAAawwAAAYATgBqDAAAAgBJAOoMAAAGAFYAbgwAAAIAFgAcAAYJMhyKHwDlAQZoDAAABQBcAGkMAAAHAFAAawwAAAYATgBqDAAAAgBJAOoMAAAGAFYAbgwAAAIAFgAAAA==.Lastexile:BAAALgAECgEJAQAAAA==.',
Li='Linglinda:BAACLgAFFH8HAAINAAMJ6xyHFAADAQNoDAAABABFAGkMAAACAE4A6gwAAAEASQANAAMJ6xyHFAADAQNoDAAABABFAGkMAAACAE4A6gwAAAEASQAuAAQKfxoAAg0ACQnxIEgFAOMCAA0ACQnxIEgFAOMCAAAA.',
Lo='Lockstar:BAEALgAECgkJAgAAAA==.Lockwarior:BAACLgAFFH8gAAQEAAcJXB6LEQDNAQdoDAAABwBgAGkMAAAGAGAAawwAAAUATwBqDAAABQA5AGwMAAACAFwAbQwAAAEABgDqDAAABgBfAAQABgnvI4sRAM0BBmgMAAAHAGAAaQwAAAYAYABrDAAABABPAGoMAAADADkAbAwAAAIAXADqDAAABgBfAAUAAQkAAGQEAFsAAWoMAAACADYABgACCQ4InBUAUwACawwAAAEAIgBtDAAAAQAGAC4ABAp/JAADBAAJCbcizQQAbgMABAAJCbcizQQAbgMABgABCQAAzoAADQAAAAA=.Loricarvonri:BAAALgAECgUJCAAAAA==.Lottiedottie:BAAALgAECgQJBAAAAA==.Love:BAAALgAECgQJBAAAAA==.',
Lu='Luciena:BAABLgAECn8eAAIdAAgJuw/sGwBtAQhoDAAABABAAGkMAAAEACcAawwAAAQALQBqDAAABQAbAGwMAAAEACcAbQwAAAIACADqDAAABQA4AG4MAAACABsAHQAICbsP7BsAbQEIaAwAAAQAQABpDAAABAAnAGsMAAAEAC0AagwAAAUAGwBsDAAABAAnAG0MAAACAAgA6gwAAAUAOABuDAAAAgAbAAAA.Lunarheals:BAABLgAECn8iAAIcAAgJ7RhXEwAhAghoDAAABgBIAGkMAAAHAEIAawwAAAYARABqDAAABQBGAGwMAAAFADgAbQwAAAEAGADqDAAAAwBJAG4MAAABAE0AHAAICe0YVxMAIQIIaAwAAAYASABpDAAABwBCAGsMAAAGAEQAagwAAAUARgBsDAAABQA4AG0MAAABABgA6gwAAAMASQBuDAAAAQBNAAAA.Lunasong:BAABLgAECn8XAAIHAAgJAAZcdwAsAQhoDAAAAwAOAGkMAAADABMAawwAAAQAEgBqDAAAAwAlAGwMAAADAAcAbQwAAAEABwDqDAAABQAaAG4MAAABAA4ABwAICQAGXHcALAEIaAwAAAMADgBpDAAAAwATAGsMAAAEABIAagwAAAMAJQBsDAAAAwAHAG0MAAABAAcA6gwAAAUAGgBuDAAAAQAOAAAA.Luxury:BAAALgAECgMJBgAAAA==.',
Ma='Marcagi:BAAALgADCgEJAQAAAA==.Martyguard:BAAALgAECgUJBQABLgAECggJIgAVAEEUAA==.Martyulon:BAABLgAECn8iAAMVAAgJQRT1JADAAQhoDAAABQBJAGkMAAAFAEcAawwAAAYAOgBqDAAABQA2AGwMAAAFAC0AbQwAAAEACQDqDAAABgBCAG4MAAABACIAFQAICUEU9SQAwAEIaAwAAAQASQBpDAAABABHAGsMAAAFADoAagwAAAQANgBsDAAABAAtAG0MAAABAAkA6gwAAAYAQgBuDAAAAQAiAA0ABQkdCXZPAKcABWgMAAABAB4AaQwAAAEAGABrDAAAAQASAGoMAAABABYAbAwAAAEAEwAAAA==.Maxlink:BAAALgAECgMJAwAAAA==.',
Me='Melikefire:BAACLgAFFH8HAAIeAAMJyRPFAQDiAANoDAAABAA6AGkMAAACAC4A6gwAAAEALwAeAAMJyRPFAQDiAANoDAAABAA6AGkMAAACAC4A6gwAAAEALwAuAAQKfyoAAh4ACQnkHAcBAKgCAB4ACQnkHAcBAKgCAAAA.Melikesword:BAAALgAECgQJBAAAAA==.',
Mo='Molda:BAAALgAECgcJEwAAAA==.Monkjimothy:BAABLgAECn8vAAQLAAgJoyH8BwCcAghoDAAACABfAGkMAAAHAFQAawwAAAcAVQBqDAAABgBbAGwMAAAGAFEAbQwAAAIAQQDqDAAACABgAG4MAAADAF0ACwAICe0g/AcAnAIIaAwAAAYAXwBpDAAABgBUAGsMAAAGAFUAagwAAAUAWwBsDAAABQBRAG0MAAACAEEA6gwAAAYAYABuDAAAAgBQAA0ABQncHuo1AEgBBWgMAAACAEoAaQwAAAEARABrDAAAAQBEAOoMAAACAFoAbgwAAAEAXQAVAAIJdAonXgBVAAJqDAAAAQAeAGwMAAABABcAAAA=.Monko:BAAALgAECgEJAQABLgAFFAcJHAASAAkjAA==.Moomie:BAAALgADCgMJAwAAAA==.Moonstrike:BAAALgAECggJEAAAAA==.Mortius:BAAALgADCgcJDAAAAA==.',
['Mí']='Míku:BAAALgAECgMJAwAAAA==.',
Na='Navier:BAAALgADCgMJAwAAAA==.',
Ne='Nero:BAAALgADCgEJAQAAAA==.',
No='Noice:BAAALgAECgIJAgABLgAFFAYJFQAbAFwbAA==.',
Od='Odinsknight:BAABLgAECn8fAAQYAAgJohLqCgCVAQhoDAAABgAuAGkMAAAFADAAawwAAAQANABqDAAABAAqAGwMAAADACwAbQwAAAIAGADqDAAABQA4AG4MAAACADwAGAAICfMR6goAlQEIaAwAAAUALgBpDAAABAAwAGsMAAADACcAagwAAAQAKgBsDAAAAwAsAG0MAAACABgA6gwAAAQAOABuDAAAAgA8AAIAAwmwATsOAVgAA2gMAAABAAQAaQwAAAEABADqDAAAAQAEAAMAAQlSFGNPADQAAWsMAAABADQAAAA=.',
Pa='Pandáam:BAAALgAECgEJAQAAAA==.Parkeidand:BAAALgAECggJEQAAAA==.Patodeez:BAAALgAECgEJAQAAAA==.',
Ph='Phreek:BAABLgAECn8dAAIMAAkJdxI6eQDfAQloDAAABgA3AGkMAAAEADgAawwAAAQAMQBqDAAAAgAxAGwMAAACAEgAbQwAAAEAFADqDAAACAA5AG4MAAABACYAbwwAAAEAGwAMAAkJdxI6eQDfAQloDAAABgA3AGkMAAAEADgAawwAAAQAMQBqDAAAAgAxAGwMAAACAEgAbQwAAAEAFADqDAAACAA5AG4MAAABACYAbwwAAAEAGwAAAA==.',
Po='Pookie:BAAALgAECgEJAQAAAA==.Portius:BAAALgADCggJDQAAAA==.Pouyan:BAABLgAECn8uAAISAAkJhhScJwD4AQloDAAACABWAGkMAAAHAEoAawwAAAcAQABqDAAABgA4AGwMAAAGAD4AbQwAAAMAGwDqDAAABgBBAG4MAAACABAAbwwAAAEAEgASAAkJhhScJwD4AQloDAAACABWAGkMAAAHAEoAawwAAAcAQABqDAAABgA4AGwMAAAGAD4AbQwAAAMAGwDqDAAABgBBAG4MAAACABAAbwwAAAEAEgAAAA==.',
Pr='Prfctpullout:BAAALgADCgIJAgAAAA==.',
Ra='Ra:BAABLgAECn9DAAQUAAkJcBNiCADMAQloDAAADAA3AGkMAAAJACkAawwAAAkAOQBqDAAABwA0AGwMAAAHAFMAbQwAAAQAIgDqDAAACwA4AG4MAAAFADEAbwwAAAMAEgAUAAkJ2BJiCADMAQloDAAACQA3AGkMAAAGACkAawwAAAYAOQBqDAAABQA0AGwMAAAHAFMAbQwAAAQAIgDqDAAACAAsAG4MAAAFADEAbwwAAAMAEgAdAAUJ7hH8LQDiAAVoDAAAAwAsAGkMAAACACIAawwAAAIALwBqDAAAAgAoAOoMAAADADgAEQACCSkHfd4ATgACaQwAAAEAEABrDAAAAQATAAAA.Racinette:BAACLgAFFH8dAAIBAAUJ3yS0CAD4AQVoDAAACABcAGkMAAAIAF0AawwAAAQAYwBqDAAAAwBhAOoMAAAGAFkAAQAFCd8ktAgA+AEFaAwAAAgAXABpDAAACABdAGsMAAAEAGMAagwAAAMAYQDqDAAABgBZAC4ABAp/GgACAQAJCfskvwUAEAMAAQAJCfskvwUAEAMAAAA=.',
Re='Rebexha:BAAALgAECgUJDQAAAA==.Redia:BAAALgAECgEJAgAAAA==.Relvanas:BAABLgAECn8iAAMfAAgJ/gZnJQBDAQhoDAAABwAPAGkMAAAGABwAawwAAAUAEABqDAAABQAxAGwMAAAEAB4AbQwAAAIABwDqDAAABAASAG4MAAABAAgAHwAICf4GZyUAQwEIaAwAAAYADwBpDAAABgAcAGsMAAAFABAAagwAAAUAMQBsDAAAAwAeAG0MAAACAAcA6gwAAAMAEgBuDAAAAQAIACAAAwkpA3IgAEAAA2gMAAABAAUAbAwAAAEADgDqDAAAAQADAAAA.',
Ri='Riverside:BAAALgAECgYJDgAAAA==.',
Sa='Saelesth:BAAALgAECggJEAAAAA==.Sambie:BAABLgAECn8jAAIHAAcJLwPBmwDfAAdoDAAABQAKAGkMAAAFAAkAawwAAAYACABqDAAABQAPAGwMAAAFAAkA6gwAAAcABgBuDAAAAgAEAAcABwkvA8GbAN8AB2gMAAAFAAoAaQwAAAUACQBrDAAABgAIAGoMAAAFAA8AbAwAAAUACQDqDAAABwAGAG4MAAACAAQAAAA=.',
Sc='Scannedtron:BAAALgAECgcJBwAAAA==.Scantron:BAAALgAECgcJDAAAAA==.Scrappycocco:BAAALgAECgUJDAAAAA==.Scuffedbones:BAABLgAFFH8GAAICAAUJCgR8cADvAAVoDAAAAQASAGkMAAACAAkAawwAAAEACABqDAAAAQAJAOoMAAABAAQAAgAFCQoEfHAA7wAFaAwAAAEAEgBpDAAAAgAJAGsMAAABAAgAagwAAAEACQDqDAAAAQAEAAAA.Scuffedbop:BAAALgADCgcJDQABLgAFFAUJBgACAAoEAA==.Scuffedfaith:BAABLgAECn8bAAMhAAgJ0BpPEgAtAghoDAAABABMAGkMAAAFAF8AawwAAAUAYABqDAAAAwBfAGwMAAADADgAbQwAAAIAUgDqDAAAAwAZAG4MAAACABQAIQAHCYUdTxIALQIHaAwAAAQATABpDAAABABfAGsMAAAEAGAAagwAAAIAXwBsDAAAAwA4AG0MAAACAFIA6gwAAAIAGQAiAAUJ4QRsSQC4AAVpDAAAAQAMAGsMAAABAA0AagwAAAEAAgDqDAAAAQAOAG4MAAACAAkAAS4ABRQFCQYAAgAKBAA=.',
Se='Sefyra:BAABLgAECn8ZAAIHAAYJJRWtbQBBAQZoDAAABQAzAGkMAAAFACsAawwAAAUAPABqDAAAAgAtAGwMAAADAEkA6gwAAAUAKgAHAAYJJRWtbQBBAQZoDAAABQAzAGkMAAAFACsAawwAAAUAPABqDAAAAgAtAGwMAAADAEkA6gwAAAUAKgAAAA==.Setelai:BAAALgADCgUJBQAAAA==.',
Sh='Shamroran:BAAALgADCgEJAQAAAA==.Shankz:BAAALgADCgEJAQAAAA==.Shishi:BAAALgADCgkJCgAAAA==.',
Si='Sinful:BAAALgAECgIJAgAAAA==.',
Sn='Sneakycress:BAAALgAECgUJCQAAAA==.Snolo:BAABLgAECn8gAAIbAAgJWBBOKwB1AQhoDAAABgA3AGkMAAAGACoAawwAAAYAKwBqDAAABQA6AGwMAAAEACsAbQwAAAEAIQDqDAAAAwA0AG4MAAABABUAGwAICVgQTisAdQEIaAwAAAYANwBpDAAABgAqAGsMAAAGACsAagwAAAUAOgBsDAAABAArAG0MAAABACEA6gwAAAMANABuDAAAAQAVAAAA.Snowyrose:BAAALgAECgMJAwABLgAFFAMJBwANAOscAA==.',
So='Sorakaa:BAAALgADCgUJBQAAAA==.Soulstoned:BAAALgADCgYJCQAAAA==.',
Sp='Spiritwarior:BAAALgAFFAIJAwABLgAFFAcJIAAEAFweAA==.Splux:BAAALgAECgUJBQAAAA==.',
St='Starsky:BAAALgADCgUJBgAAAA==.Strangedraco:BAAALgADCgYJBgAAAA==.Strangewood:BAACLgAFFH8HAAIPAAMJtwQxLACpAANoDAAABAAJAGkMAAACABAA6gwAAAEACQAPAAMJtwQxLACpAANoDAAABAAJAGkMAAACABAA6gwAAAEACQAuAAQKfzoAAw8ACQlSDGMjAIoBAA8ACQlSDGMjAIoBABIABwkaF1JGAIgBAAAA.',
Su='Sugarhzopurp:BAAALgAECgcJCAAAAA==.Summerss:BAAALgADCggJCAAAAA==.',
Sw='Swiftlee:BAAALgAECgYJBwAAAA==.',
Th='Thunderfnk:BAABLgAECn8YAAIaAAgJVRQJLgBmAQhoDAAABABIAGkMAAAEAEEAawwAAAQAMQBqDAAAAwAlAGwMAAADAFEAbQwAAAEAEwDqDAAABAA5AG4MAAABABEAGgAICVUUCS4AZgEIaAwAAAQASABpDAAABABBAGsMAAAEADEAagwAAAMAJQBsDAAAAwBRAG0MAAABABMA6gwAAAQAOQBuDAAAAQARAAAA.',
Tr='Trickydice:BAAALgAECgUJBgAAAA==.',
Tw='Twentyfour:BAAALgAECgEJAQAAAA==.',
Ty='Tysreaper:BAABLgAECn8YAAMEAAgJLBKFXACzAQhoDAAABAAnAGkMAAAEAD4AawwAAAQAPgBqDAAAAwAwAGwMAAADAD4AbQwAAAEAFADqDAAABAA1AG4MAAABABkABAAICVYRhVwAswEIaAwAAAMAJwBpDAAAAgAvAGsMAAADAD4AagwAAAMAMABsDAAAAwA+AG0MAAABABQA6gwAAAQANQBuDAAAAQAZAAUAAwlxD/kYALMAA2gMAAABAAoAaQwAAAIAPgBrDAAAAQAtAAAA.',
Ur='Urickea:BAAALgAECgEJAQAAAA==.',
Va='Valdyr:BAABLgAECn8qAAITAAgJYSBrHQB9AghoDAAABgBbAGkMAAAGAFcAawwAAAcATgBqDAAABgBbAGwMAAAGAGAAbQwAAAIAPQDqDAAABwBcAG4MAAACAEgAEwAICWEgax0AfQIIaAwAAAYAWwBpDAAABgBXAGsMAAAHAE4AagwAAAYAWwBsDAAABgBgAG0MAAACAD0A6gwAAAcAXABuDAAAAgBIAAAA.Vannishstrik:BAAALgAECgQJBAAAAA==.Varri:BAAALgADCgMJAwAAAA==.',
Vo='Vodouism:BAAALgAECgUJBQABLgAECgYJFQASACAjAA==.Vonbane:BAAALgADCgYJCAAAAA==.',
Vu='Vu:BAAALgAECgYJBgAAAA==.',
Wa='Warcawk:BAAALgAECgYJEgAAAA==.Wardsky:BAAALgAECgYJCgAAAA==.',
We='Webbington:BAAALgAECgEJAQAAAA==.',
Wr='Wreckthar:BAABLgAECn9FAAMTAAkJESPRBgAmAwloDAAACwBeAGkMAAALAF0AawwAAAsAYgBqDAAACQBhAGwMAAAHAFMAbQwAAAQAUgDqDAAACQBZAG4MAAAFAGEAbwwAAAIATwATAAkJESPRBgAmAwloDAAACgBeAGkMAAALAF0AawwAAAsAYgBqDAAACQBhAGwMAAAHAFMAbQwAAAQAUgDqDAAACABZAG4MAAAFAGEAbwwAAAIATwAZAAIJPxn0LwCDAAJoDAAAAQAtAOoMAAABAFMAAAA=.',
Wu='Wu:BAABLgAECn8WAAINAAgJPBCsKABPAQhoDAAABAAuAGkMAAAFADMAawwAAAQAKgBqDAAAAgApAGwMAAACAC8AbQwAAAEAIADqDAAAAwArAG4MAAABABsADQAICTwQrCgATwEIaAwAAAQALgBpDAAABQAzAGsMAAAEACoAagwAAAIAKQBsDAAAAgAvAG0MAAABACAA6gwAAAMAKwBuDAAAAQAbAAEuAAUUAwkFAAQALgoA.',
Xe='Xelagos:BAAALgAECgcJBwABLgAFFAMJBQAEAC4KAA==.',
Xy='Xyla:BAAALgADCgEJAQAAAA==.',
Ze='Zenetrawr:BAACLgAFFH8IAAIbAAMJ2g7tNADGAANoDAAAAwAqAGkMAAADACQA6gwAAAIAIgAbAAMJ2g7tNADGAANoDAAAAwAqAGkMAAADACQA6gwAAAIAIgAuAAQKfzEAAhsACAm9F7YcANgBABsACAm9F7YcANgBAAAA.',
Zi='Zingispingus:BAABLgAECn8fAAIPAAgJjQfqNgASAQhoDAAABgAXAGkMAAAFABEAawwAAAUAGQBqDAAABAAQAGwMAAAEABkAbQwAAAIACgDqDAAABAATAG8MAAABAA4ADwAICY0H6jYAEgEIaAwAAAYAFwBpDAAABQARAGsMAAAFABkAagwAAAQAEABsDAAABAAZAG0MAAACAAoA6gwAAAQAEwBvDAAAAQAOAAAA.',
['Ær']='Ærìs:BAAALgADCgcJBwAAAA==.',
['Ða']='Ðaora:BAAALgADCgkJCgABLgAECgUJDgAKAAAAAA==.',
['ßa']='ßandamonium:BAAALgAECgYJCQAAAA==.',
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
