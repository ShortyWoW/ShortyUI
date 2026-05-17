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

local lookup = {'Unknown-Unknown','Evoker-Augmentation','Mage-Frost','Priest-Shadow','Evoker-Preservation','Evoker-Devastation','Monk-Mistweaver','Warlock-Demonology','Warlock-Destruction','Monk-Brewmaster','Shaman-Elemental','Shaman-Restoration','Monk-Windwalker','Priest-Holy','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','DemonHunter-Vengeance','DemonHunter-Devourer','Rogue-Subtlety','Rogue-Assassination','Paladin-Retribution','Paladin-Holy','Paladin-Protection','Druid-Balance','Warrior-Fury','Warrior-Protection','Warrior-Arms','Druid-Restoration','Priest-Discipline','DemonHunter-Havoc',}
local provider = {region='US',realm='MoonGuard',name='US',type='subscribers',zone=46,date='2026-05-16',data={Ad='Advvy:BAEALgAECgUJDQAAAA==.',
Ag='Ageregressor:BAEALgAECgcJBwAAAA==.',
Ai='Aihime:BAEALgADCgYJBgABLgAECgEJAQABAAAAAA==.',
Al='Alcean:BAEBLgAECn8xAAICAAkJAyEWBQDdAgloDAAACABdAGkMAAAHAFgAawwAAAcAWwBqDAAABQA4AGwMAAAFAFUAbQwAAAQATQDqDAAACABVAG4MAAADAFIAbwwAAAIARwACAAkJAyEWBQDdAgloDAAACABdAGkMAAAHAFgAawwAAAcAWwBqDAAABQA4AGwMAAAFAFUAbQwAAAQATQDqDAAACABVAG4MAAADAFIAbwwAAAIARwAAAA==.Algebra:BAECLgAFFH8SAAIDAAUJRiTcFQCwAQVoDAAABQBbAGkMAAAEAFsAawwAAAQAYwBqDAAAAQAPAOoMAAAEAFkAAwAFCUYk3BUAsAEFaAwAAAUAWwBpDAAABABbAGsMAAAEAGMAagwAAAEADwDqDAAABABZAC4ABAp/GwACAwAJCQkk+gUALwMAAwAJCQkk+gUALwMAAAA=.Aléyna:BAEALgAECgEJAgAAAA==.',
Ar='Araakki:BAEALgAECgUJDQAAAA==.Arteron:BAEALgAFFAIJAwABLgAFFAcJHQAEACwdAA==.',
Ay='Ayoade:BAECLgAFFH8QAAIFAAQJ3BPwCgA8AQRoDAAABAArAGkMAAAEAD0AawwAAAQANADqDAAABAAtAAUABAncE/AKADwBBGgMAAAEACsAaQwAAAQAPQBrDAAABAA0AOoMAAAEAC0ALgAECn8YAAMFAAgJaRydCgCMAgAFAAgJaRydCgCMAgAGAAIJERXjMQCHAAABLgAFFAYJCwAHAFIgAA==.',
Az='Azzurel:BAEBLgAECn8XAAMIAAgJLxEZXABMAQhoDAAABAAxAGkMAAAEACkAawwAAAMAOABqDAAAAwAwAGwMAAADADwAbQwAAAIAEADqDAAAAwAwAG4MAAABACMACAAICS8RGVwATAEIaAwAAAQAMQBpDAAABAApAGsMAAADADgAagwAAAIAMABsDAAAAwA8AG0MAAACABAA6gwAAAMAMABuDAAAAQAjAAkAAQkAAD5yADMAAWoMAAABABQAAAA=.',
Bo='Bobbysan:BAECLgAFFH8dAAIKAAcJpBhNBADQAQdoDAAABgBQAGkMAAAFAEwAawwAAAQASQBqDAAABABAAGwMAAACACgAbQwAAAEAGwDqDAAABwBQAAoABwmkGE0EANABB2gMAAAGAFAAaQwAAAUATABrDAAABABJAGoMAAAEAEAAbAwAAAIAKABtDAAAAQAbAOoMAAAHAFAALgAECn8sAAIKAAkJYiDrCABuAgAKAAkJYiDrCABuAgAAAA==.',
Br='Brigbala:BAEALgAECgMJBgAAAA==.',
Cr='Crustome:BAEALgAECgYJEgAAAA==.',
De='Deathhunterz:BAEALgAECgQJBAAAAA==.Demagogué:BAECLgAFFH8GAAMLAAMJPhdVJgCiAANsDAAAAgBgAG0MAAABACcA6gwAAAMAKgALAAIJBRBVJgCiAAJtDAAAAQAnAOoMAAADACoADAABCckTrkkAVQABbAwAAAIAMgAuAAQKfx4AAwsACAnvIyUGAL8CAAsACAnvIyUGAL8CAAwABwnaGUEsAK4BAAEuAAUUBwkQAAUAtA4A.Demonipryde:BAEALgAECgMJAwAAAA==.',
Dr='Drunkenqrow:BAEALgAECgYJDQABLgAECggJEAABAAAAAA==.',
Du='Dubsii:BAECLgAFFH8LAAIHAAYJUiCrAwBMAgZoDAAAAgBTAGkMAAACAGAAawwAAAMAXABqDAAAAQBUAGwMAAACAC4A6gwAAAEAXQAHAAYJUiCrAwBMAgZoDAAAAgBTAGkMAAACAGAAawwAAAMAXABqDAAAAQBUAGwMAAACAC4A6gwAAAEAXQAuAAQKfxcAAwcACAmLIZwGAPMCAAcACAmLIZwGAPMCAA0AAQl/JqlRAG4AAAAA.',
Eh='Ehanee:BAEALgAECgkJDwAAAA==.',
Er='Ereshin:BAEALgAECgcJCQABLgAECgcJFQAOAOUeAA==.',
Ev='Evielyssa:BAEALgAECgYJDwABLgAFFAMJBQAOAEofAA==.Evierari:BAEBLgAFFH8FAAMOAAIJSh+wGAClAAJoDAAAAwBQAGkMAAACAE8ADgACCUofsBgApQACaAwAAAIAUABpDAAAAgBPAAQAAQkgAb8XADwAAWgMAAABAAIAAAA=.',
Fa='Fappimeal:BAECLgAFFH8WAAIPAAUJkiTPCgB8AQVoDAAABgBiAGkMAAAGAGEAawwAAAQATgBqDAAAAQA3AOoMAAAFAGMADwAFCZIkzwoAfAEFaAwAAAYAYgBpDAAABgBhAGsMAAAEAE4AagwAAAEANwDqDAAABQBjAC4ABAp/OAADDwAJCSEmdwIAtAMADwAJCSEmdwIAtAMAEAABCUUgKBwAWQAAAAA=.',
Fo='Fofer:BAEBLgAECn8iAAIKAAcJnCWEBwCJAgdoDAAABwBhAGkMAAAHAF4AawwAAAcAYwBqDAAABABhAGwMAAAEAGMAbQwAAAEAWgDqDAAABABgAAoABwmcJYQHAIkCB2gMAAAHAGEAaQwAAAcAXgBrDAAABwBjAGoMAAAEAGEAbAwAAAQAYwBtDAAAAQBaAOoMAAAEAGAAAS4ABRQHCRsAEQApIQA=.',
Fr='Froshin:BAEALgADCgUJCgABLgAECgcJFQAOAOUeAA==.',
Fu='Funkey:BAECLgAFFH8RAAMSAAUJIBWeAgCjAAVoDAAABQBDAGkMAAAFAFoAawwAAAIAFABqDAAAAQAWAOoMAAAEACYAEwAFCZkO2zEAEAEFaAwAAAMAIQBpDAAABAA4AGsMAAACABQAagwAAAEAFgDqDAAABAAmABIAAgm2Hp4CAKMAAmgMAAACAEMAaQwAAAEAWgAuAAQKfycAAxIACQmfIMQBAPwCABIACAmzIsQBAPwCABMABgl+Fso4AJcBAAAA.',
Gr='Greathades:BAEALgAECgkJAgABLgAECgkJBAABAAAAAA==.Greatmonkey:BAEALgAECgcJBgABLgAECgkJBAABAAAAAA==.Greatodin:BAEALgAECgkJBAAAAA==.Greatra:BAEALgADCgEJAQABLgAECgkJBAABAAAAAA==.Grummel:BAECLgAFFH8IAAIUAAMJoiBDEADOAANoDAAABQBbAGkMAAABAEQA6gwAAAIAWgAUAAMJoiBDEADOAANoDAAABQBbAGkMAAABAEQA6gwAAAIAWgAuAAQKfycAAxQACQk9IH8JAPkCABQACQk9IH8JAPkCABUAAQlwFGwdAEAAAAAA.',
Hb='Hbcarter:BAEALgAFFAIJBAABLgAFFAYJCwAHAFIgAA==.',
Ia='Iambuns:BAEALgADCgcJBwABLgAFFAUJFgAPAJIkAA==.',
Il='Illiyania:BAEALgAECgEJAQAAAA==.',
Im='Imquitelarge:BAEALgAECgkJEwAAAA==.',
Iz='Izapotato:BAECLgAFFH8TAAITAAUJMxgjCQCXAQVoDAAABABUAGkMAAAEACoAawwAAAQANABqDAAAAwBDAOoMAAAEAEQAEwAFCTMYIwkAlwEFaAwAAAQAVABpDAAABAAqAGsMAAAEADQAagwAAAMAQwDqDAAABABEAC4ABAp/GwACEwAHCX4lpBgAwQIAEwAHCX4lpBgAwQIAAS4ABRQHCRAABQC0DgA=.',
Ke='Kelandrea:BAEBLgAECn8cAAQWAAkJoRrYIgCeAgloDAAABABTAGkMAAAEAFYAawwAAAMAUABqDAAABABiAGwMAAAEAFIAbQwAAAMALQDqDAAAAgBcAG4MAAADAEYAbwwAAAEABQAWAAkJoRrYIgCeAgloDAAAAwBTAGkMAAADAFYAawwAAAMAUABqDAAAAwBiAGwMAAADAFIAbQwAAAMALQDqDAAAAgBcAG4MAAADAEYAbwwAAAEABQAXAAIJ0hD3gQBwAAJoDAAAAQASAGkMAAABAEMAGAACCTMXtzUAQgACagwAAAEAUgBsDAAAAQA7AAAA.',
Ki='Kirkh:BAEALgAECgcJCwABLgAECgkJJgAEAEobAA==.Kirkpriest:BAEBLgAECn8mAAIEAAkJSht8BwAQAwloDAAABQBbAGkMAAAFAFkAawwAAAUAXABqDAAABQBPAGwMAAAFAFcAbQwAAAQAMADqDAAABQBaAG4MAAADADEAbwwAAAEACQAEAAkJSht8BwAQAwloDAAABQBbAGkMAAAFAFkAawwAAAUAXABqDAAABQBPAGwMAAAFAFcAbQwAAAQAMADqDAAABQBaAG4MAAADADEAbwwAAAEACQAAAA==.Kitowatt:BAEALgAECgYJCgABLgAECgcJFAAZAJUcAA==.',
Kr='Kregazi:BAECLgAFFH8FAAIRAAMJvRK9FwDEAANoDAAAAgA7AGkMAAACADYA6gwAAAEAHQARAAMJvRK9FwDEAANoDAAAAgA7AGkMAAACADYA6gwAAAEAHQAuAAQKfywAAhEACQm1IVoDANUCABEACQm1IVoDANUCAAAA.',
Ky='Kyriste:BAEBLgAECn8UAAIOAAcJ8x30FADjAQdoDAAABQBbAGkMAAAFAFoAawwAAAQAWABqDAAAAQAvAGwMAAABACgA6gwAAAIAWwBuDAAAAgBXAA4ABwnzHfQUAOMBB2gMAAAFAFsAaQwAAAUAWgBrDAAABABYAGoMAAABAC8AbAwAAAEAKADqDAAAAgBbAG4MAAACAFcAAS4ABRQECRMAFABgIQA=.',
La='Larissaqt:BAECLgAFFH8XAAIEAAYJPQ1YBwCKAQZoDAAABQAvAGkMAAAEACwAawwAAAUAHQBqDAAABAAgAGwMAAABABMA6gwAAAQAGwAEAAYJPQ1YBwCKAQZoDAAABQAvAGkMAAAEACwAawwAAAUAHQBqDAAABAAgAGwMAAABABMA6gwAAAQAGwAuAAQKfyAAAgQACAnUIBoQAAwCAAQACAnUIBoQAAwCAAAA.',
Li='Lilylock:BAEALgAECgEJAQABLgAECggJFgAaAHAeAA==.Lilyweave:BAEBLgAECn8WAAQaAAgJcB6sFQCgAghoDAAAAwBLAGkMAAADAFcAawwAAAMAVwBqDAAABABcAGwMAAADAFEAbQwAAAIAPADqDAAAAgBaAG4MAAACAD4AGgAICXAerBUAoAIIaAwAAAIASwBpDAAAAgBXAGsMAAADAFcAagwAAAQAXABsDAAAAgBRAG0MAAACADwA6gwAAAIAWgBuDAAAAgA+ABsAAgkNDzw9AGMAAmgMAAABABgAaQwAAAEANAAcAAEJNwzCQgAzAAFsDAAAAQAfAAAA.Lioshi:BAEALgAECgYJCQABLgAFFAQJEAADAJ4aAA==.',
Ma='Maildaddy:BAECLgAFFH8QAAIFAAcJtA5XCgCUAQdoDAAAAwAwAGkMAAADAEMAawwAAAMALQBqDAAAAQAiAGwMAAABAAoAbQwAAAEACADqDAAABAAxAAUABwm0DlcKAJQBB2gMAAADADAAaQwAAAMAQwBrDAAAAwAtAGoMAAABACIAbAwAAAEACgBtDAAAAQAIAOoMAAAEADEALgAECn8kAAQFAAgJiRz0BgBLAgAFAAcJJSD0BgBLAgACAAUJKBEqNwAbAQAGAAMJHBzfJwDiAAAAAA==.Maxxy:BAEBLgAECn8cAAIdAAkJtR2gFgCBAgloDAAABQBdAGkMAAAEAFwAawwAAAQAXwBqDAAAAwA6AGwMAAADAEoAbQwAAAEARQDqDAAABQBUAG4MAAACAE8AbwwAAAEAJAAdAAkJtR2gFgCBAgloDAAABQBdAGkMAAAEAFwAawwAAAQAXwBqDAAAAwA6AGwMAAADAEoAbQwAAAEARQDqDAAABQBUAG4MAAACAE8AbwwAAAEAJAAAAA==.',
Mc='Mckellen:BAECLgAFFH8HAAMOAAQJ+A01EAD8AARoDAAAAgAwAGkMAAACADYAawwAAAEAEwDqDAAAAgAUAA4ABAldDTUQAPwABGgMAAACADAAaQwAAAEANgBrDAAAAQATAOoMAAABAA0AHgACCREJAhQAlgACaQwAAAEAGgDqDAAAAQAUAC4ABAp/HQADHgAICc4ZmQwAbgIAHgAICc4ZmQwAbgIADgAECSYMg1wAwQAAAS4ABRQGCQsABwBSIAA=.',
Me='Merarite:BAEALgAECgcJBwABLgAECgkJNgAKADYQAA==.',
Mi='Minidruid:BAECLgAFFH8IAAIZAAQJsRW2EgAyAQRoDAAAAgAwAGkMAAACAEMAawwAAAIAMQDqDAAAAgA4ABkABAmxFbYSADIBBGgMAAACADAAaQwAAAIAQwBrDAAAAgAxAOoMAAACADgALgAECn8dAAIZAAcJjiJVCwBSAgAZAAcJjiJVCwBSAgABLgAFFAMJBwADALYTAA==.',
Mo='Mordraius:BAEALgAECggJEQABLgAFFAQJEAADAJ4aAA==.',
My='Myceliums:BAEALgAECgQJCgAAAA==.',
Na='Nadasa:BAECLgAFFH8NAAIWAAUJywqMLQAgAQVoDAAABAAhAGkMAAADABgAawwAAAIAFABqDAAAAQAxAOoMAAADAB8AFgAFCcsKjC0AIAEFaAwAAAQAIQBpDAAAAwAYAGsMAAACABQAagwAAAEAMQDqDAAAAwAfAC4ABAp/OAACFgAJCeMeABcAegIAFgAJCeMeABcAegIAAAA=.Naramonria:BAEALgADCgcJCAAAAA==.',
Ni='Nixaanu:BAEALgAECgEJAQABLgAECggJFAALAH8aAA==.Nixei:BAEBLgAECn8UAAILAAgJfxpEGABTAghoDAAAAgAyAGkMAAACAEIAawwAAAIATwBqDAAAAgA3AGwMAAAEAFAAbQwAAAMARwDqDAAAAgA3AG4MAAADAEYACwAICX8aRBgAUwIIaAwAAAIAMgBpDAAAAgBCAGsMAAACAE8AagwAAAIANwBsDAAABABQAG0MAAADAEcA6gwAAAIANwBuDAAAAwBGAAAA.',
Ny='Nyriaa:BAEBLgAECn8eAAIOAAkJviMvAgBSAwloDAAABQBjAGkMAAAFAGIAawwAAAUAWwBqDAAAAwBfAGwMAAADAF4AbQwAAAEAUQDqDAAABQBjAG4MAAACAFMAbwwAAAEATwAOAAkJviMvAgBSAwloDAAABQBjAGkMAAAFAGIAawwAAAUAWwBqDAAAAwBfAGwMAAADAF4AbQwAAAEAUQDqDAAABQBjAG4MAAACAFMAbwwAAAEATwAAAA==.',
['Ní']='Nítedragon:BAEALgADCggJAwABLgAECgcJEwABAAAAAA==.',
Pa='Palashin:BAEALgAECgQJBAABLgAECgcJFQAOAOUeAA==.',
Pe='Personnelkid:BAEALgAECgEJAQABLgAECgkJOAAOAIUZAA==.',
Ph='Pheiro:BAEBLgAECn8cAAIDAAgJcQ1wiADBAQhoDAAABQBSAGkMAAAFAC0AawwAAAQAJQBqDAAAAgAXAGwMAAACABAAbQwAAAQADwDqDAAABQAmAG4MAAABAAUAAwAICXENcIgAwQEIaAwAAAUAUgBpDAAABQAtAGsMAAAEACUAagwAAAIAFwBsDAAAAgAQAG0MAAAEAA8A6gwAAAUAJgBuDAAAAQAFAAAA.',
Pu='Punchweagle:BAEBLgAECn82AAMKAAkJNhBmGACmAQloDAAACAAzAGkMAAAHAEAAawwAAAgAOgBqDAAABgAoAGwMAAAGADkAbQwAAAUAEQDqDAAABgAwAG4MAAAFAA0AbwwAAAMAEwAKAAkJ8Q5mGACmAQloDAAABAAzAGkMAAAEADQAawwAAAQAMwBqDAAABAAZAGwMAAAEADkAbQwAAAUAEQDqDAAABAAqAG4MAAAFAA0AbwwAAAMAEwANAAYJUxRGMgBbAQZoDAAABAAyAGkMAAADAEAAawwAAAQAOgBqDAAAAgAoAGwMAAACACUA6gwAAAIAMAAAAA==.',
Qr='Qrowdrake:BAEALgAECgIJAgABLgAECggJEAABAAAAAA==.Qrowfather:BAEALgAECggJEAAAAA==.Qrowsunny:BAEALgAECgQJBQABLgAECggJEAABAAAAAA==.',
Ra='Raveglaive:BAEALgAECgUJAwAAAA==.',
Re='Redvine:BAEALgADCgUJBQABLgAFFAUJEQASACAVAA==.Rexpanda:BAEALgAECgQJBQABLgAECgUJBQABAAAAAA==.Rextank:BAEALgAECgEJAQABLgAECgUJBQABAAAAAA==.',
Ro='Roogies:BAECLgAFFH8TAAIUAAQJYCGABwCHAQRoDAAABwBcAGkMAAAHAFUAawwAAAMARADqDAAAAgBeABQABAlgIYAHAIcBBGgMAAAHAFwAaQwAAAcAVQBrDAAAAwBEAOoMAAACAF4ALgAECn87AAMUAAkJiSVmAgD5AgAUAAkJWiVmAgD5AgAVAAIJnRghFQCoAAAAAA==.',
Ru='Rumpy:BAEALgAFFAIJBAABLgAFFAMJCAAUAKIgAA==.',
['Ræ']='Ræx:BAEALgAECgUJBQAAAA==.',
['Rë']='Rëi:BAECLgAFFH8HAAIDAAMJthNrLQABAQNoDAAAAwA/AGkMAAACACMA6gwAAAIANAADAAMJthNrLQABAQNoDAAAAwA/AGkMAAACACMA6gwAAAIANAAuAAQKfxkAAgMACAkUHK5DAG0CAAMACAkUHK5DAG0CAAAA.',
Sh='Shiins:BAEALgAECgIJAwABLgAECgcJFQAOAOUeAA==.Shinthyr:BAEBLgAECn8VAAIOAAcJ5R4eFQA0AgdoDAAABABTAGkMAAADAFUAawwAAAMAXQBqDAAAAwBHAGwMAAACAFUA6gwAAAQASwBuDAAAAgA6AA4ABwnlHh4VADQCB2gMAAAEAFMAaQwAAAMAVQBrDAAAAwBdAGoMAAADAEcAbAwAAAIAVQDqDAAABABLAG4MAAACADoAAAA=.',
Si='Sizzlefox:BAEALgAECgEJAQABLgAECgUJDQABAAAAAA==.',
St='Stygianfox:BAEALgAECgEJAQABLgAECgUJDQABAAAAAA==.',
Ta='Tahune:BAEBLgAECn86AAMdAAkJzSObAQCiAwloDAAACQBdAGkMAAAIAGIAawwAAAgAXwBqDAAACABfAGwMAAAHAGEAbQwAAAUAXADqDAAACABhAG4MAAAEAFoAbwwAAAEAPgAdAAkJzSObAQCiAwloDAAABwBdAGkMAAAIAGIAawwAAAYAXwBqDAAACABfAGwMAAAHAGEAbQwAAAUAXADqDAAACABhAG4MAAAEAFoAbwwAAAEAPgAZAAIJhiFSRgCcAAJoDAAAAgBWAGsMAAACAFUAAAA=.Taso:BAEBLgAECn8YAAIKAAgJ9BAMIwBTAQhoDAAABQA/AGkMAAAEAEMAawwAAAQASgBqDAAABABPAGwMAAABAAAAbQwAAAEAAADqDAAABAA6AG4MAAABACYACgAICfQQDCMAUwEIaAwAAAUAPwBpDAAABABDAGsMAAAEAEoAagwAAAQATwBsDAAAAQAAAG0MAAABAAAA6gwAAAQAOgBuDAAAAQAmAAEuAAUUBAkQABEAiyAA.',
Th='Therapygap:BAEBLgAECn8jAAQOAAgJYRFHOQBWAQhoDAAABgBMAGkMAAAHACUAawwAAAMANwBqDAAABAAdAGwMAAAHADQAbQwAAAEAIwDqDAAABgA8AG4MAAABAAgADgAHCV0TRzkAVgEHaAwAAAMATABpDAAAAwAlAGsMAAACADcAagwAAAMAHQBsDAAABQA0AG0MAAABACMA6gwAAAUAPAAEAAYJKwooQgCtAAZoDAAAAwAnAGkMAAAEABUAawwAAAEAEgBqDAAAAQAHAGwMAAACACkA6gwAAAEACAAeAAEJfAOSXwAjAAFuDAAAAQAIAAEuAAQKCQk4AA4AhRkA.',
Tr='Triboon:BAEALgADCgMJAwABLgAFFAYJEgAHAIIcAA==.Trèantdaddy:BAEALgAFFAEJAgABLgAFFAcJEAAFALQOAA==.',
Us='Usurah:BAECLgAFFH8XAAIWAAYJyRhfCgCjAQZoDAAABgBOAGkMAAAGAFYAawwAAAMAQQBqDAAAAwA8AGwMAAABABgA6gwAAAQAPgAWAAYJyRhfCgCjAQZoDAAABgBOAGkMAAAGAFYAawwAAAMAQQBqDAAAAwA8AGwMAAABABgA6gwAAAQAPgAuAAQKfysAAxYACQmAIsQJAEMDABYACQmAIsQJAEMDABgABQlYHOISAEIBAAAA.',
Vi='Vindh:BAECLgAFFH8OAAMTAAQJugd2OAD3AARoDAAABQAXAGkMAAADABUAawwAAAIACADqDAAABAAYABMABAm6B3Y4APcABGgMAAAFABcAaQwAAAMAFQBrDAAAAgAIAOoMAAADABgAEgABCQ4GuwsAKwAB6gwAAAEADwAuAAQKfygABBMACQm3FV09AP8BABMACQm3FV09AP8BABIAAgk6AxAjAD0AAB8AAQkAAMlbAAAAAAAA.',
Ya='Yaav:BAEBLgAECn8VAAIPAAgJqhGlUwCBAQhoDAAABAA2AGkMAAAEADoAawwAAAMAJgBqDAAAAwBLAGwMAAADACMAbQwAAAEAKADqDAAAAgA0AG4MAAABACQADwAICaoRpVMAgQEIaAwAAAQANgBpDAAABAA6AGsMAAADACYAagwAAAMASwBsDAAAAwAjAG0MAAABACgA6gwAAAIANABuDAAAAQAkAAAA.',
Yu='Yufia:BAEBLgAECn8ZAAIIAAkJXR5GCgAsAwloDAAABABQAGkMAAAEAF8AawwAAAQAWABqDAAAAwBdAGwMAAACAFgAbQwAAAEAQgDqDAAABQBjAG4MAAABABEAbwwAAAEAVgAIAAkJXR5GCgAsAwloDAAABABQAGkMAAAEAF8AawwAAAQAWABqDAAAAwBdAGwMAAACAFgAbQwAAAEAQgDqDAAABQBjAG4MAAABABEAbwwAAAEAVgAAAA==.',
Za='Zatum:BAEBLgAECn8UAAIZAAcJlRxmFwC6AQdoDAAABABKAGkMAAAEAFYAawwAAAMATwBqDAAAAgA7AGwMAAACAEcA6gwAAAQAVABuDAAAAQAqABkABwmVHGYXALoBB2gMAAAEAEoAaQwAAAQAVgBrDAAAAwBPAGoMAAACADsAbAwAAAIARwDqDAAABABUAG4MAAABACoAAAA=.',
Zh='Zhuröng:BAECLgAFFH8QAAIDAAQJnhpgMgBSAQRoDAAABQBJAGkMAAAFAE4AawwAAAMAKgDqDAAAAwBPAAMABAmeGmAyAFIBBGgMAAAFAEkAaQwAAAUATgBrDAAAAwAqAOoMAAADAE8ALgAECn8mAAIDAAkJlx8CNgD/AQADAAkJlx8CNgD/AQAAAA==.',
Zo='Zomb:BAECLgAFFH8QAAIRAAQJiyC3CABmAQRoDAAABgBYAGkMAAAFAEQAawwAAAIAXQDqDAAAAwBSABEABAmLILcIAGYBBGgMAAAGAFgAaQwAAAUARABrDAAAAgBdAOoMAAADAFIALgAECn8kAAIRAAgJjiFpBAAFAwARAAgJjiFpBAAFAwAAAA==.',
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
