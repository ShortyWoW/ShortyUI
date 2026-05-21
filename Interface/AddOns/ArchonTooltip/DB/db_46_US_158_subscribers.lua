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

local lookup = {'Unknown-Unknown','Evoker-Augmentation','Mage-Frost','Priest-Shadow','Evoker-Preservation','Evoker-Devastation','Shaman-Restoration','Warlock-Demonology','Warlock-Destruction','DemonHunter-Vengeance','Monk-Brewmaster','Shaman-Elemental','Monk-Mistweaver','Monk-Windwalker','Priest-Holy','DeathKnight-Unholy','DeathKnight-Frost','Druid-Restoration','DemonHunter-Devourer','Rogue-Subtlety','Rogue-Assassination','Warrior-Arms','Paladin-Retribution','Paladin-Holy','Paladin-Protection','Druid-Balance','DeathKnight-Blood','Warrior-Fury','Warrior-Protection','Priest-Discipline','DemonHunter-Havoc',}
local provider = {region='US',realm='MoonGuard',name='US',type='subscribers',zone=46,date='2026-05-20',data={Ad='Advvy:BAEALgAECgUJDgAAAA==.',
Ag='Ageregressor:BAEALgAECgcJBwAAAA==.',
Ai='Aihime:BAEALgADCgYJBgABLgAECgEJAQABAAAAAA==.',
Al='Alcean:BAEBLgAECn8xAAICAAkJAyH4BQDcAgloDAAACABdAGkMAAAHAFgAawwAAAcAWwBqDAAABQA4AGwMAAAFAFUAbQwAAAQATQDqDAAACABVAG4MAAADAFIAbwwAAAIARwACAAkJAyH4BQDcAgloDAAACABdAGkMAAAHAFgAawwAAAcAWwBqDAAABQA4AGwMAAAFAFUAbQwAAAQATQDqDAAACABVAG4MAAADAFIAbwwAAAIARwAAAA==.Algebra:BAECLgAFFH8TAAIDAAUJRiQ2HACoAQVoDAAABQBbAGkMAAAEAFsAawwAAAQAYwBqDAAAAgBaAOoMAAAEAFkAAwAFCUYkNhwAqAEFaAwAAAUAWwBpDAAABABbAGsMAAAEAGMAagwAAAIAWgDqDAAABABZAC4ABAp/HQACAwAJCZ8kSAYANwMAAwAJCZ8kSAYANwMAAAA=.Aléyna:BAEALgAECgEJAgAAAA==.',
Ar='Araakki:BAEALgAECgYJDgAAAA==.Arteron:BAEALgAFFAIJAwABLgAFFAcJHQAEACwdAA==.',
Ay='Ayoade:BAECLgAFFH8UAAIFAAQJohTwCgA8AQRoDAAABQAzAGkMAAAFAD0AawwAAAUANADqDAAABQAtAAUABAmiFPAKADwBBGgMAAAFADMAaQwAAAUAPQBrDAAABQA0AOoMAAAFAC0ALgAECn8YAAMFAAgJaRydCgCMAgAFAAgJaRydCgCMAgAGAAIJERXjMQCHAAABLgAFFAgJKgAHAHwgAA==.',
Az='Azzurel:BAEBLgAECn8XAAMIAAgJLxExZQBTAQhoDAAABAAxAGkMAAAEACkAawwAAAMAOABqDAAAAwAwAGwMAAADADwAbQwAAAIAEADqDAAAAwAwAG4MAAABACMACAAICS8RMWUAUwEIaAwAAAQAMQBpDAAABAApAGsMAAADADgAagwAAAIAMABsDAAAAwA8AG0MAAACABAA6gwAAAMAMABuDAAAAQAjAAkAAQkAAD5yADMAAWoMAAABABQAAAA=.',
Ba='Bareskin:BAEALgAFFAQJBAABLgAFFAUJEQAKACAVAA==.',
Bo='Bobbysan:BAECLgAFFH8eAAILAAgJQxiBAgAmAghoDAAABgBQAGkMAAAFAEwAawwAAAQASQBqDAAABABAAGwMAAACACgAbQwAAAEAGwDqDAAABwBQAG4MAAABADgACwAICUMYgQIAJgIIaAwAAAYAUABpDAAABQBMAGsMAAAEAEkAagwAAAQAQABsDAAAAgAoAG0MAAABABsA6gwAAAcAUABuDAAAAQA4AC4ABAp/LAACCwAJCWIgPwoAagIACwAJCWIgPwoAagIAAAA=.',
Br='Brigbala:BAEALgAECgMJBgAAAA==.',
Cr='Crustome:BAEALgAECgYJEgAAAA==.Crustorc:BAEALgAECgYJBgABLgAECgYJEgABAAAAAA==.',
De='Deathhunterz:BAEALgAECgQJBwAAAA==.Demagogué:BAECLgAFFH8KAAMMAAYJgRPFIgDZAAZoDAAAAQA9AGsMAAABAAkAagwAAAEAJQBsDAAAAgBgAG0MAAABACcA6gwAAAQAKgAMAAQJ6gvFIgDZAARrDAAAAQAJAGoMAAABACUAbQwAAAEAJwDqDAAABAAqAAcAAglvDytEAIwAAmgMAAABABwAbAwAAAIAMgAuAAQKfx4AAwwACAnvI5sHALgCAAwACAnvI5sHALgCAAcABwnaGVMyAKwBAAEuAAUUBwkQAAUAsw4A.Demonipryde:BAEALgAECgMJAwAAAA==.',
Dr='Drunkenqrow:BAEALgAECgYJDQABLgAECggJEAABAAAAAA==.',
Du='Dubsii:BAECLgAFFH8LAAINAAYJUiDqBABFAgZoDAAAAgBTAGkMAAACAGAAawwAAAMAXABqDAAAAQBUAGwMAAACAC4A6gwAAAEAXQANAAYJUiDqBABFAgZoDAAAAgBTAGkMAAACAGAAawwAAAMAXABqDAAAAQBUAGwMAAACAC4A6gwAAAEAXQAuAAQKfxcAAw0ACAmLIZwGAPMCAA0ACAmLIZwGAPMCAA4AAQl/JrxaAG4AAAEuAAUUCAkqAAcAfCAA.Dubsy:BAECLgAFFH8qAAIHAAgJfCDsAACjAghoDAAACQBQAGkMAAAJAF8AawwAAAYAWwBqDAAABwBjAGwMAAABAEMAbQwAAAEALADqDAAACABWAG4MAAABAGQABwAICXwg7AAAowIIaAwAAAkAUABpDAAACQBfAGsMAAAGAFsAagwAAAcAYwBsDAAAAQBDAG0MAAABACwA6gwAAAgAVgBuDAAAAQBkAC4ABAp/MgADBwAJCdAllgAAtAMABwAJCdAllgAAtAMADAADCfQivDcAGwEAAAA=.',
Eh='Ehanee:BAEALgAFFAEJAQAAAA==.',
Er='Ereshin:BAEALgAECggJDwAAAA==.',
Ev='Evielyssa:BAEALgAECgYJDwABLgAFFAMJBQAPAEofAA==.Evierari:BAEBLgAFFH8FAAMPAAIJSh90GwCjAAJoDAAAAwBQAGkMAAACAE8ADwACCUofdBsAowACaAwAAAIAUABpDAAAAgBPAAQAAQkgAb8XADwAAWgMAAABAAIAAAA=.',
Fa='Fappimeal:BAECLgAFFH8bAAMQAAUJkiTPCgB8AQVoDAAABwBiAGkMAAAHAGEAawwAAAUATgBqDAAAAgA3AOoMAAAGAGMAEAAFCZIkzwoAfAEFaAwAAAYAYgBpDAAABgBhAGsMAAAEAE4AagwAAAEANwDqDAAABQBjABEABQndD+EGACoBBWgMAAABACoAaQwAAAEAOgBrDAAAAQArAGoMAAABACQA6gwAAAEAEQAuAAQKfzkAAxAACQkhJncCALQDABAACQkhJncCALQDABEAAgnNFRYcAIsAAAAA.',
Fo='Fofer:BAEBLgAECn8iAAILAAcJkiV5CACIAgdoDAAABwBhAGkMAAAHAF4AawwAAAcAYwBqDAAABABhAGwMAAAEAGIAbQwAAAEAWQDqDAAABABgAAsABwmSJXkIAIgCB2gMAAAHAGEAaQwAAAcAXgBrDAAABwBjAGoMAAAEAGEAbAwAAAQAYgBtDAAAAQBZAOoMAAAEAGAAAAA=.Foil:BAEALgADCgkJCQABLgAECgkJOwASAOgkAA==.',
Fr='Froshin:BAEALgADCgUJCgABLgAECggJDwABAAAAAA==.',
Fu='Funkey:BAECLgAFFH8RAAMKAAUJIBWeAgCjAAVoDAAABQBDAGkMAAAFAFoAawwAAAIAFABqDAAAAQAWAOoMAAAEACYAEwAFCZkOmDcADAEFaAwAAAMAIQBpDAAABAA4AGsMAAACABQAagwAAAEAFgDqDAAABAAmAAoAAgm2Hp4CAKMAAmgMAAACAEMAaQwAAAEAWgAuAAQKfycAAwoACQmfIMQBAPwCAAoACAmzIsQBAPwCABMABgl+FmJCAJUBAAAA.',
Gr='Greathades:BAEALgAECgkJAgABLgAECgkJBAABAAAAAA==.Greatmonkey:BAEALgAECgcJBgABLgAECgkJBAABAAAAAA==.Greatodin:BAEALgAECgkJBAAAAA==.Greatra:BAEALgADCgEJAQABLgAECgkJBAABAAAAAA==.Grummel:BAECLgAFFH8IAAIUAAMJoiBDEADOAANoDAAABQBbAGkMAAABAEQA6gwAAAIAWgAUAAMJoiBDEADOAANoDAAABQBbAGkMAAABAEQA6gwAAAIAWgAuAAQKfycAAxQACQk9IH8JAPkCABQACQk9IH8JAPkCABUAAQlwFGwdAEAAAAAA.',
Hb='Hbcarter:BAEBLgAFFH8HAAISAAMJSxScKADqAANoDAAAAwBVAGkMAAABAB8A6gwAAAMAJgASAAMJSxScKADqAANoDAAAAwBVAGkMAAABAB8A6gwAAAMAJgABLgAFFAgJKgAHAHwgAA==.',
Ia='Iambuns:BAEALgADCgcJBwABLgAFFAUJGwAQAJIkAA==.',
Il='Illiyania:BAEALgAECgEJAQAAAA==.',
Im='Imquitelarge:BAEBLgAECn8VAAIWAAkJWxbWCQAYAgloDAAAAgAuAGkMAAACADIAawwAAAIAJwBqDAAAAgA8AGwMAAACACIAbQwAAAIAIwDqDAAAAwBVAG4MAAAEAFEAbwwAAAIAVQAWAAkJWxbWCQAYAgloDAAAAgAuAGkMAAACADIAawwAAAIAJwBqDAAAAgA8AGwMAAACACIAbQwAAAIAIwDqDAAAAwBVAG4MAAAEAFEAbwwAAAIAVQAAAA==.',
Iz='Izapotato:BAECLgAFFH8TAAITAAUJMxgjCQCXAQVoDAAABABUAGkMAAAEACoAawwAAAQANABqDAAAAwBDAOoMAAAEAEQAEwAFCTMYIwkAlwEFaAwAAAQAVABpDAAABAAqAGsMAAAEADQAagwAAAMAQwDqDAAABABEAC4ABAp/IgACEwAHCaAlVBgAXQIAEwAHCaAlVBgAXQIAAS4ABRQHCRAABQCzDgA=.',
Ke='Kelandrea:BAECLgAFFH8GAAIXAAIJwAuQZgCWAAJoDAAAAwAWAOoMAAADACUAFwACCcALkGYAlgACaAwAAAMAFgDqDAAAAwAlAC4ABAp/HAAEFwAJCaEa2CIAngIAFwAJCaEa2CIAngIAGAACCdIQ94EAcAAAGQACCTMXCzsAQQAAAAA=.',
Ki='Kirkh:BAEALgAECgcJCwABLgAECgkJJgAEAEobAA==.Kirkpriest:BAEBLgAECn8mAAIEAAkJSht8BwAQAwloDAAABQBbAGkMAAAFAFkAawwAAAUAXABqDAAABQBPAGwMAAAFAFcAbQwAAAQAMADqDAAABQBaAG4MAAADADEAbwwAAAEACQAEAAkJSht8BwAQAwloDAAABQBbAGkMAAAFAFkAawwAAAUAXABqDAAABQBPAGwMAAAFAFcAbQwAAAQAMADqDAAABQBaAG4MAAADADEAbwwAAAEACQAAAA==.Kitowatt:BAEALgAECgYJCgABLgAECgcJFgAaAKocAA==.',
Kr='Kregazi:BAECLgAFFH8IAAIbAAMJaBQoGgDGAANoDAAAAwA7AGkMAAADAEMA6gwAAAIAHQAbAAMJaBQoGgDGAANoDAAAAwA7AGkMAAADAEMA6gwAAAIAHQAuAAQKfy4AAhsACQmNIpEDAN0CABsACQmNIpEDAN0CAAAA.',
Ky='Kyriste:BAEBLgAECn8XAAIPAAcJZiGQCgCMAgdoDAAABQBbAGkMAAAFAFoAawwAAAQAWABqDAAAAgBVAGwMAAACAEAA6gwAAAMAWwBuDAAAAgBXAA8ABwlmIZAKAIwCB2gMAAAFAFsAaQwAAAUAWgBrDAAABABYAGoMAAACAFUAbAwAAAIAQADqDAAAAwBbAG4MAAACAFcAAS4ABRQECRMAFABgIQA=.',
La='Larissaqt:BAECLgAFFH8XAAIEAAYJPQ0ECQCBAQZoDAAABQAvAGkMAAAEACwAawwAAAUAHQBqDAAABAAgAGwMAAABABMA6gwAAAQAGwAEAAYJPQ0ECQCBAQZoDAAABQAvAGkMAAAEACwAawwAAAUAHQBqDAAABAAgAGwMAAABABMA6gwAAAQAGwAuAAQKfyAAAgQACAnUIAQTAAcCAAQACAnUIAQTAAcCAAAA.',
Li='Lilylock:BAEALgAECgEJAQABLgAECggJFgAcAHAeAA==.Lilyweave:BAEBLgAECn8WAAQcAAgJcB6sFQCgAghoDAAAAwBLAGkMAAADAFcAawwAAAMAVwBqDAAABABcAGwMAAADAFEAbQwAAAIAPADqDAAAAgBaAG4MAAACAD4AHAAICXAerBUAoAIIaAwAAAIASwBpDAAAAgBXAGsMAAADAFcAagwAAAQAXABsDAAAAgBRAG0MAAACADwA6gwAAAIAWgBuDAAAAgA+AB0AAgkNDzw9AGMAAmgMAAABABgAaQwAAAEANAAWAAEJNwzCQgAzAAFsDAAAAQAfAAAA.Lioshi:BAEALgAECgYJCQABLgAFFAQJEAADAJ4aAA==.',
Ma='Maildaddy:BAECLgAFFH8QAAIFAAcJsw7cBwDeAQdoDAAAAwAwAGkMAAADAEMAawwAAAMALQBqDAAAAQAiAGwMAAABAAoAbQwAAAEACADqDAAABAAxAAUABwmzDtwHAN4BB2gMAAADADAAaQwAAAMAQwBrDAAAAwAtAGoMAAABACIAbAwAAAEACgBtDAAAAQAIAOoMAAAEADEALgAECn8kAAQFAAgJiRzjBwBIAgAFAAcJJSDjBwBIAgACAAUJKBEqNwAbAQAGAAMJHBzfJwDiAAAAAA==.Maxxy:BAEBLgAECn8cAAISAAkJtR2gFgCBAgloDAAABQBdAGkMAAAEAFwAawwAAAQAXwBqDAAAAwA6AGwMAAADAEoAbQwAAAEARQDqDAAABQBUAG4MAAACAE8AbwwAAAEAJAASAAkJtR2gFgCBAgloDAAABQBdAGkMAAAEAFwAawwAAAQAXwBqDAAAAwA6AGwMAAADAEoAbQwAAAEARQDqDAAABQBUAG4MAAACAE8AbwwAAAEAJAAAAA==.',
Mc='Mckellen:BAECLgAFFH8HAAMPAAQJ+A1GEgD8AARoDAAAAgAwAGkMAAACADYAawwAAAEAEwDqDAAAAgAUAA8ABAldDUYSAPwABGgMAAACADAAaQwAAAEANgBrDAAAAQATAOoMAAABAA0AHgACCREJAhQAlgACaQwAAAEAGgDqDAAAAQAUAC4ABAp/HQADHgAICc4ZmQwAbgIAHgAICc4ZmQwAbgIADwAECSYMg1wAwQAAAS4ABRQICSoABwB8IAA=.',
Me='Medranden:BAEALgADCgcJBwABLgAECgQJBwABAAAAAA==.Merarite:BAEALgAECgcJBwABLgAECgkJNgALADYQAA==.',
Mi='Militee:BAEALgADCgMJBAAAAA==.Minidruid:BAECLgAFFH8NAAIaAAUJcRhwEwA4AQVoDAAAAwBDAGkMAAADAEMAawwAAAMAMwBqDAAAAQAsAOoMAAADAD4AGgAFCXEYcBMAOAEFaAwAAAMAQwBpDAAAAwBDAGsMAAADADMAagwAAAEALADqDAAAAwA+AC4ABAp/HgACGgAHCY4iYg0ATwIAGgAHCY4iYg0ATwIAAS4ABRQDCQcAAwC2EwA=.',
Mo='Mordraius:BAEALgAECggJEQABLgAFFAQJEAADAJ4aAA==.',
My='Myceliums:BAEALgAECgUJDgAAAA==.',
Na='Nadasa:BAECLgAFFH8RAAIXAAUJ6BP0JQA7AQVoDAAABQAzAGkMAAAEAD4AawwAAAMAOgBqDAAAAQAxAOoMAAAEAB8AFwAFCegT9CUAOwEFaAwAAAUAMwBpDAAABAA+AGsMAAADADoAagwAAAEAMQDqDAAABAAfAC4ABAp/OgACFwAJCe0g5xAAvgIAFwAJCe0g5xAAvgIAAAA=.Naramonria:BAEALgADCgcJCAAAAA==.',
Ni='Nixaanu:BAEALgAECgEJAQABLgAECggJFAAMAH8aAA==.Nixei:BAEBLgAECn8UAAIMAAgJfxpEGABTAghoDAAAAgAyAGkMAAACAEIAawwAAAIATwBqDAAAAgA3AGwMAAAEAFAAbQwAAAMARwDqDAAAAgA3AG4MAAADAEYADAAICX8aRBgAUwIIaAwAAAIAMgBpDAAAAgBCAGsMAAACAE8AagwAAAIANwBsDAAABABQAG0MAAADAEcA6gwAAAIANwBuDAAAAwBGAAAA.',
Ny='Nyriaa:BAEBLgAECn8eAAIPAAkJviPcAgBKAwloDAAABQBjAGkMAAAFAGIAawwAAAUAWwBqDAAAAwBfAGwMAAADAF4AbQwAAAEAUQDqDAAABQBjAG4MAAACAFMAbwwAAAEATwAPAAkJviPcAgBKAwloDAAABQBjAGkMAAAFAGIAawwAAAUAWwBqDAAAAwBfAGwMAAADAF4AbQwAAAEAUQDqDAAABQBjAG4MAAACAFMAbwwAAAEATwAAAA==.',
['Ní']='Nítedragon:BAEALgADCggJAwABLgAECgcJEwABAAAAAA==.',
Pa='Palashin:BAEALgAECgUJCAABLgAECggJDwABAAAAAA==.',
Pe='Personnelkid:BAEALgAECgYJBwABLgAECgkJOAAPAIMZAA==.',
Ph='Pheiro:BAEBLgAECn8cAAIDAAgJcQ1wiADBAQhoDAAABQBSAGkMAAAFAC0AawwAAAQAJQBqDAAAAgAXAGwMAAACABAAbQwAAAQADwDqDAAABQAmAG4MAAABAAUAAwAICXENcIgAwQEIaAwAAAUAUgBpDAAABQAtAGsMAAAEACUAagwAAAIAFwBsDAAAAgAQAG0MAAAEAA8A6gwAAAUAJgBuDAAAAQAFAAAA.',
Pl='Platedaddy:BAEALgAECgYJBgABLgAFFAcJEAAFALMOAA==.',
Pu='Punchweagle:BAEBLgAECn82AAMLAAkJNhARGwCmAQloDAAACAAzAGkMAAAHAEAAawwAAAgAOgBqDAAABgAoAGwMAAAGADkAbQwAAAUAEQDqDAAABgAwAG4MAAAFAA0AbwwAAAMAEwALAAkJ8Q4RGwCmAQloDAAABAAzAGkMAAAEADQAawwAAAQAMwBqDAAABAAZAGwMAAAEADkAbQwAAAUAEQDqDAAABAAqAG4MAAAFAA0AbwwAAAMAEwAOAAYJUxRGMgBbAQZoDAAABAAyAGkMAAADAEAAawwAAAQAOgBqDAAAAgAoAGwMAAACACUA6gwAAAIAMAAAAA==.',
Qr='Qrowdrake:BAEALgAECgQJBAABLgAECggJEAABAAAAAA==.Qrowfather:BAEALgAECggJEAAAAA==.Qrowsunny:BAEALgAECgQJBQABLgAECggJEAABAAAAAA==.',
Ra='Raveglaive:BAEALgAECgUJAwAAAA==.',
Re='Redvine:BAEALgADCgUJBQABLgAFFAUJEQAKACAVAA==.Rexpanda:BAEALgAECgQJBgABLgAECgUJBQABAAAAAA==.Rextank:BAEALgAECgEJAQABLgAECgUJBQABAAAAAA==.',
Ro='Roogies:BAECLgAFFH8TAAIUAAQJYCHXCQB+AQRoDAAABwBcAGkMAAAHAFUAawwAAAMARADqDAAAAgBeABQABAlgIdcJAH4BBGgMAAAHAFwAaQwAAAcAVQBrDAAAAwBEAOoMAAACAF4ALgAECn87AAMUAAkJiSU2AwD1AgAUAAkJWiU2AwD1AgAVAAIJnRghFQCoAAAAAA==.',
Ru='Rumpy:BAEALgAFFAIJBAABLgAFFAMJCAAUAKIgAA==.',
['Ræ']='Ræx:BAEALgAECgUJBQAAAA==.',
['Rë']='Rëi:BAECLgAFFH8HAAIDAAMJthNrLQABAQNoDAAAAwA/AGkMAAACACMA6gwAAAIANAADAAMJthNrLQABAQNoDAAAAwA/AGkMAAACACMA6gwAAAIANAAuAAQKfxkAAgMACAkUHK5DAG0CAAMACAkUHK5DAG0CAAAA.',
Sh='Shiins:BAEALgAECgIJAwABLgAECggJDwABAAAAAA==.Shinthyr:BAEBLgAECn8VAAIPAAcJ5R4eFQA0AgdoDAAABABTAGkMAAADAFUAawwAAAMAXQBqDAAAAwBHAGwMAAACAFUA6gwAAAQASwBuDAAAAgA6AA8ABwnlHh4VADQCB2gMAAAEAFMAaQwAAAMAVQBrDAAAAwBdAGoMAAADAEcAbAwAAAIAVQDqDAAABABLAG4MAAACADoAAS4ABAoICQ8AAQAAAAA=.',
Si='Sizzlefox:BAEALgAECgEJAQABLgAECgYJDgABAAAAAA==.',
St='Stygianfox:BAEALgAECgEJAQABLgAECgYJDgABAAAAAA==.',
Ta='Tahune:BAEBLgAECn87AAMSAAkJ6CRAAQC6AwloDAAACQBdAGkMAAAIAGIAawwAAAgAXwBqDAAACABfAGwMAAAHAGEAbQwAAAUAXADqDAAACABhAG4MAAAEAFoAbwwAAAIAWAASAAkJ6CRAAQC6AwloDAAABwBdAGkMAAAIAGIAawwAAAYAXwBqDAAACABfAGwMAAAHAGEAbQwAAAUAXADqDAAACABhAG4MAAAEAFoAbwwAAAIAWAAaAAIJhiH5TQCZAAJoDAAAAgBWAGsMAAACAFUAAAA=.Taso:BAEBLgAECn8dAAILAAgJVhHgJQBYAQhoDAAABgA/AGkMAAAFAEMAawwAAAUASgBqDAAABQBPAGwMAAABAAAAbQwAAAEAAADqDAAABQBBAG4MAAABACYACwAICVYR4CUAWAEIaAwAAAYAPwBpDAAABQBDAGsMAAAFAEoAagwAAAUATwBsDAAAAQAAAG0MAAABAAAA6gwAAAUAQQBuDAAAAQAmAAEuAAUUBAkQABsAiyAA.',
Th='Therapygap:BAEBLgAECn8nAAQPAAgJgBL4IACNAQhoDAAABwBMAGkMAAAIADwAawwAAAQANwBqDAAABAAdAGwMAAAIADQAbQwAAAEAIwDqDAAABgA8AG4MAAABAAgADwAHCaYU+CAAjQEHaAwAAAQATABpDAAABAA8AGsMAAADADcAagwAAAMAHQBsDAAABgA0AG0MAAABACMA6gwAAAUAPAAEAAYJKwonSQCtAAZoDAAAAwAnAGkMAAAEABUAawwAAAEAEgBqDAAAAQAHAGwMAAACACkA6gwAAAEACAAeAAEJfAPVaAAiAAFuDAAAAQAIAAEuAAQKCQk4AA8AgxkA.',
Tr='Triboon:BAEALgADCgMJAwABLgAFFAcJEwANAHcbAA==.Trèantdaddy:BAEALgAFFAEJAgABLgAFFAcJEAAFALMOAA==.',
Us='Usurah:BAECLgAFFH8YAAIXAAYJDBlSDgCWAQZoDAAABgBOAGkMAAAGAFYAawwAAAMAQQBqDAAAAwA8AGwMAAACABsA6gwAAAQAPgAXAAYJDBlSDgCWAQZoDAAABgBOAGkMAAAGAFYAawwAAAMAQQBqDAAAAwA8AGwMAAACABsA6gwAAAQAPgAuAAQKfysAAxcACQmAIsQJAEMDABcACQmAIsQJAEMDABkABQlYHGMVAD4BAAAA.',
Vi='Vindh:BAECLgAFFH8OAAMTAAQJugeKPgD0AARoDAAABQAXAGkMAAADABUAawwAAAIACADqDAAABAAYABMABAm6B4o+APQABGgMAAAFABcAaQwAAAMAFQBrDAAAAgAIAOoMAAADABgACgABCQ4GEQ0AKwAB6gwAAAEADwAuAAQKfygABBMACQm3FV09AP8BABMACQm3FV09AP8BAAoAAgk6A6wmAD0AAB8AAQkAADFlAAAAAAAA.',
Ya='Yaav:BAEBLgAECn8XAAIQAAkJxhBcQwDPAQloDAAABAA2AGkMAAAEADoAawwAAAMAJgBqDAAAAwBLAGwMAAADACMAbQwAAAEAKADqDAAAAgA0AG4MAAACACQAbwwAAAEAGwAQAAkJxhBcQwDPAQloDAAABAA2AGkMAAAEADoAawwAAAMAJgBqDAAAAwBLAGwMAAADACMAbQwAAAEAKADqDAAAAgA0AG4MAAACACQAbwwAAAEAGwAAAA==.',
Yu='Yufia:BAEBLgAECn8ZAAIIAAkJXR5GCgAsAwloDAAABABQAGkMAAAEAF8AawwAAAQAWABqDAAAAwBdAGwMAAACAFgAbQwAAAEAQgDqDAAABQBjAG4MAAABABEAbwwAAAEAVgAIAAkJXR5GCgAsAwloDAAABABQAGkMAAAEAF8AawwAAAQAWABqDAAAAwBdAGwMAAACAFgAbQwAAAEAQgDqDAAABQBjAG4MAAABABEAbwwAAAEAVgAAAA==.',
Za='Zatum:BAEBLgAECn8WAAIaAAcJqhx+GgC8AQdoDAAABABKAGkMAAAEAFYAawwAAAMATwBqDAAAAgA7AGwMAAAEAEgA6gwAAAQAVABuDAAAAQAqABoABwmqHH4aALwBB2gMAAAEAEoAaQwAAAQAVgBrDAAAAwBPAGoMAAACADsAbAwAAAQASADqDAAABABUAG4MAAABACoAAAA=.',
Zh='Zhuröng:BAECLgAFFH8QAAIDAAQJnhrLOQBNAQRoDAAABQBJAGkMAAAFAE4AawwAAAMAKgDqDAAAAwBPAAMABAmeGss5AE0BBGgMAAAFAEkAaQwAAAUATgBrDAAAAwAqAOoMAAADAE8ALgAECn8mAAIDAAkJlx8OQAD1AQADAAkJlx8OQAD1AQAAAA==.',
Zo='Zomb:BAECLgAFFH8QAAIbAAQJiyCCCgBiAQRoDAAABgBYAGkMAAAFAEQAawwAAAIAXQDqDAAAAwBSABsABAmLIIIKAGIBBGgMAAAGAFgAaQwAAAUARABrDAAAAgBdAOoMAAADAFIALgAECn8lAAIbAAgJjiFpBAAFAwAbAAgJjiFpBAAFAwAAAA==.',
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
