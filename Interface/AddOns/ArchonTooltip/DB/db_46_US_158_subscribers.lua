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

local lookup = {'Unknown-Unknown','Evoker-Augmentation','Mage-Frost','Priest-Shadow','Evoker-Preservation','Evoker-Devastation','Monk-Mistweaver','Warlock-Demonology','Warlock-Destruction','Monk-Brewmaster','Shaman-Restoration','Shaman-Elemental','Monk-Windwalker','Priest-Holy','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','DemonHunter-Vengeance','DemonHunter-Devourer','Rogue-Subtlety','Rogue-Assassination','Paladin-Retribution','Paladin-Holy','Paladin-Protection','Druid-Balance','Warrior-Fury','Warrior-Protection','Warrior-Arms','Druid-Restoration','Priest-Discipline',}
local provider = {region='US',realm='MoonGuard',name='US',type='subscribers',zone=46,date='2026-05-14',data={Ad='Advvy:BAEALgAECgUJDQAAAA==.',
Ag='Ageregressor:BAEALgAECgcJBwAAAA==.',
Ai='Aihime:BAEALgADCgYJBgABLgAECgEJAQABAAAAAA==.',
Al='Alcean:BAEBLgAECn8wAAICAAkJMCAHBADrAgloDAAACABdAGkMAAAHAFgAawwAAAcAWwBqDAAABQA4AGwMAAAFAFUAbQwAAAQATQDqDAAACABVAG4MAAADAFIAbwwAAAEANgACAAkJMCAHBADrAgloDAAACABdAGkMAAAHAFgAawwAAAcAWwBqDAAABQA4AGwMAAAFAFUAbQwAAAQATQDqDAAACABVAG4MAAADAFIAbwwAAAEANgAAAA==.Algebra:BAECLgAFFH8SAAIDAAUJRiRUEwC2AQVoDAAABQBbAGkMAAAEAFsAawwAAAQAYwBqDAAAAQAPAOoMAAAEAFkAAwAFCUYkVBMAtgEFaAwAAAUAWwBpDAAABABbAGsMAAAEAGMAagwAAAEADwDqDAAABABZAC4ABAp/GwACAwAJCQkkfgQAPgMAAwAJCQkkfgQAPgMAAAA=.Aléyna:BAEALgAECgEJAgAAAA==.',
Ar='Araakki:BAEALgAECgUJDQAAAA==.Arteron:BAEALgAFFAIJAwABLgAFFAcJHQAEACwdAA==.',
Ay='Ayoade:BAECLgAFFH8QAAIFAAQJ3BPwCgA8AQRoDAAABAArAGkMAAAEAD0AawwAAAQANADqDAAABAAtAAUABAncE/AKADwBBGgMAAAEACsAaQwAAAQAPQBrDAAABAA0AOoMAAAEAC0ALgAECn8YAAMFAAgJaRydCgCMAgAFAAgJaRydCgCMAgAGAAIJERXjMQCHAAABLgAFFAYJCwAHAFIgAA==.',
Az='Azzurel:BAEBLgAECn8XAAMIAAgJLxHCUABSAQhoDAAABAAxAGkMAAAEACkAawwAAAMAOABqDAAAAwAwAGwMAAADADwAbQwAAAIAEADqDAAAAwAwAG4MAAABACMACAAICS8RwlAAUgEIaAwAAAQAMQBpDAAABAApAGsMAAADADgAagwAAAIAMABsDAAAAwA8AG0MAAACABAA6gwAAAMAMABuDAAAAQAjAAkAAQkAAD5yADMAAWoMAAABABQAAAA=.',
Bo='Bobbysan:BAECLgAFFH8dAAIKAAcJpBicAwDWAQdoDAAABgBQAGkMAAAFAEwAawwAAAQASQBqDAAABABAAGwMAAACACgAbQwAAAEAGwDqDAAABwBQAAoABwmkGJwDANYBB2gMAAAGAFAAaQwAAAUATABrDAAABABJAGoMAAAEAEAAbAwAAAIAKABtDAAAAQAbAOoMAAAHAFAALgAECn8pAAIKAAkJWiDCBwB1AgAKAAkJWiDCBwB1AgAAAA==.',
Br='Brigbala:BAEALgAECgMJBgAAAA==.',
Cr='Crustome:BAEALgAECgYJEgAAAA==.',
De='Deathhunterz:BAEALgAECgQJBAAAAA==.Demagogué:BAECLgAFFH8FAAMLAAIJchuDRgBVAAJsDAAAAgAyAOoMAAADAFkACwABCckTg0YAVQABbAwAAAIAMgAMAAEJnxCGMQBOAAHqDAAAAwAqAC4ABAp/HQADDAAHCZYkTgkAcQIADAAHCZYkTgkAcQIACwAHCdoZyicAsQEAAS4ABRQGCQ4ABQCfEAA=.Demonipryde:BAEALgAECgMJAwAAAA==.',
Dr='Drunkenqrow:BAEALgAECgYJDQABLgAECggJEAABAAAAAA==.',
Du='Dubsii:BAECLgAFFH8LAAIHAAYJUiDuAgBSAgZoDAAAAgBTAGkMAAACAGAAawwAAAMAXABqDAAAAQBUAGwMAAACAC4A6gwAAAEAXQAHAAYJUiDuAgBSAgZoDAAAAgBTAGkMAAACAGAAawwAAAMAXABqDAAAAQBUAGwMAAACAC4A6gwAAAEAXQAuAAQKfxcAAwcACAmLIZwGAPMCAAcACAmLIZwGAPMCAA0AAQl/JgBNAG8AAAAA.',
Eh='Ehanee:BAEALgAECgkJDwAAAA==.',
Er='Ereshin:BAEALgAECgYJBwABLgAECgcJFQAOAOUeAA==.',
Ev='Evielyssa:BAEALgAECgYJDwABLgAFFAMJBQAOAEofAA==.Evierari:BAEBLgAFFH8FAAMOAAIJSh/EFwCnAAJoDAAAAwBQAGkMAAACAE8ADgACCUofxBcApwACaAwAAAIAUABpDAAAAgBPAAQAAQkgAb8XADwAAWgMAAABAAIAAAA=.',
Fa='Fappimeal:BAECLgAFFH8WAAIPAAUJkiTPCgB8AQVoDAAABgBiAGkMAAAGAGEAawwAAAQATgBqDAAAAQA3AOoMAAAFAGMADwAFCZIkzwoAfAEFaAwAAAYAYgBpDAAABgBhAGsMAAAEAE4AagwAAAEANwDqDAAABQBjAC4ABAp/OAADDwAJCSEmdwIAtAMADwAJCSEmdwIAtAMAEAABCUUg3RgAXAAAAAA=.',
Fo='Fofer:BAEBLgAECn8cAAIKAAYJ8SVSDgADAgZoDAAABgBhAGkMAAAGAF4AawwAAAYAYwBqDAAAAwBhAGwMAAADAGEA6gwAAAQAYAAKAAYJ8SVSDgADAgZoDAAABgBhAGkMAAAGAF4AawwAAAYAYwBqDAAAAwBhAGwMAAADAGEA6gwAAAQAYAABLgAFFAcJGwARACkhAA==.',
Fr='Froshin:BAEALgADCgUJCgABLgAECgcJFQAOAOUeAA==.',
Fu='Funkey:BAECLgAFFH8PAAMSAAQJIBWeAgCjAARoDAAABQBDAGkMAAAFAFoAawwAAAEAFADqDAAABAAmABMABAmZDh8vABABBGgMAAADACEAaQwAAAQAOABrDAAAAQAUAOoMAAAEACYAEgACCbYengIAowACaAwAAAIAQwBpDAAAAQBaAC4ABAp/JwADEgAJCZ8gxAEA/AIAEgAICbMixAEA/AIAEwAGCX4Wjy8ApgEAAAA=.',
Gr='Greathades:BAEALgAECgkJAgAAAA==.Greatmonkey:BAEALgAECgcJBgABLgAECgkJAgABAAAAAA==.Greatra:BAEALgADCgEJAQABLgAECgkJAgABAAAAAA==.Grummel:BAECLgAFFH8HAAIUAAMJux9DEADOAANoDAAABQBbAGkMAAABAEQA6gwAAAEAUwAUAAMJux9DEADOAANoDAAABQBbAGkMAAABAEQA6gwAAAEAUwAuAAQKfyEAAxQACQmDH38JAPkCABQACQmDH38JAPkCABUAAQlwFGwdAEAAAAAA.',
Hb='Hbcarter:BAEALgAFFAIJBAABLgAFFAYJCwAHAFIgAA==.',
Ia='Iambuns:BAEALgADCgcJBwABLgAFFAUJFgAPAJIkAA==.',
Il='Illiyania:BAEALgAECgEJAQAAAA==.',
Im='Imquitelarge:BAEALgAECgkJEwAAAA==.',
Iz='Izapotato:BAECLgAFFH8TAAITAAUJMxgjCQCXAQVoDAAABABUAGkMAAAEACoAawwAAAQANABqDAAAAwBDAOoMAAAEAEQAEwAFCTMYIwkAlwEFaAwAAAQAVABpDAAABAAqAGsMAAAEADQAagwAAAMAQwDqDAAABABEAC4ABAp/GwACEwAHCX4lpBgAwQIAEwAHCX4lpBgAwQIAAS4ABRQGCQ4ABQCfEAA=.',
Ke='Kelandrea:BAEBLgAECn8cAAQWAAkJoRrYIgCeAgloDAAABABTAGkMAAAEAFYAawwAAAMAUABqDAAABABiAGwMAAAEAFIAbQwAAAMALQDqDAAAAgBcAG4MAAADAEYAbwwAAAEABQAWAAkJoRrYIgCeAgloDAAAAwBTAGkMAAADAFYAawwAAAMAUABqDAAAAwBiAGwMAAADAFIAbQwAAAMALQDqDAAAAgBcAG4MAAADAEYAbwwAAAEABQAXAAIJ0hD3gQBwAAJoDAAAAQASAGkMAAABAEMAGAACCTMXQzMARAACagwAAAEAUgBsDAAAAQA7AAAA.',
Ki='Kirkh:BAEALgAECgcJCwABLgAECgkJJgAEAEobAA==.Kirkpriest:BAEBLgAECn8mAAIEAAkJSht8BwAQAwloDAAABQBbAGkMAAAFAFkAawwAAAUAXABqDAAABQBPAGwMAAAFAFcAbQwAAAQAMADqDAAABQBaAG4MAAADADEAbwwAAAEACQAEAAkJSht8BwAQAwloDAAABQBbAGkMAAAFAFkAawwAAAUAXABqDAAABQBPAGwMAAAFAFcAbQwAAAQAMADqDAAABQBaAG4MAAADADEAbwwAAAEACQAAAA==.Kitowatt:BAEALgAECgYJCgABLgAECgcJFAAZAJUcAA==.',
Kr='Kregazi:BAEBLgAECn8sAAIRAAkJtSGXAgDpAgloDAAABwBXAGkMAAAGAFoAawwAAAYAXgBqDAAABgBZAGwMAAAFAGEAbQwAAAMATADqDAAABgBSAG4MAAAEAGEAbwwAAAEAPwARAAkJtSGXAgDpAgloDAAABwBXAGkMAAAGAFoAawwAAAYAXgBqDAAABgBZAGwMAAAFAGEAbQwAAAMATADqDAAABgBSAG4MAAAEAGEAbwwAAAEAPwAAAA==.',
Ky='Kyriste:BAEALgAECgYJDgABLgAFFAQJEgAUABQgAA==.',
La='Larissaqt:BAECLgAFFH8XAAIEAAYJPQ1cBgCQAQZoDAAABQAvAGkMAAAEACwAawwAAAUAHQBqDAAABAAgAGwMAAABABMA6gwAAAQAGwAEAAYJPQ1cBgCQAQZoDAAABQAvAGkMAAAEACwAawwAAAUAHQBqDAAABAAgAGwMAAABABMA6gwAAAQAGwAuAAQKfyAAAgQACAnUIPcNABcCAAQACAnUIPcNABcCAAAA.',
Li='Lilylock:BAEALgAECgEJAQABLgAECggJFgAaAHAeAA==.Lilyweave:BAEBLgAECn8WAAQaAAgJcB6jDgAtAghoDAAAAwBLAGkMAAADAFcAawwAAAMAVwBqDAAABABcAGwMAAADAFEAbQwAAAIAPADqDAAAAgBaAG4MAAACAD4AGgAICXAeow4ALQIIaAwAAAIASwBpDAAAAgBXAGsMAAADAFcAagwAAAQAXABsDAAAAgBRAG0MAAACADwA6gwAAAIAWgBuDAAAAgA+ABsAAgkNDzw9AGMAAmgMAAABABgAaQwAAAEANAAcAAEJNwzCQgAzAAFsDAAAAQAfAAAA.Lioshi:BAEALgAECgYJCQABLgAFFAQJEAADAJ4aAA==.',
Ma='Maildaddy:BAECLgAFFH8OAAIFAAYJnxCZCQCYAQZoDAAAAwAwAGkMAAADAEMAawwAAAMALQBqDAAAAQAiAGwMAAABAAoA6gwAAAMAMQAFAAYJnxCZCQCYAQZoDAAAAwAwAGkMAAADAEMAawwAAAMALQBqDAAAAQAiAGwMAAABAAoA6gwAAAMAMQAuAAQKfyAABAUACAmJHAsJAPsBAAUABwklIAsJAPsBAAIABQkoESo3ABsBAAYAAwkcHN8nAOIAAAAA.Maxxy:BAEBLgAECn8cAAIdAAkJtR2gFgCBAgloDAAABQBdAGkMAAAEAFwAawwAAAQAXwBqDAAAAwA6AGwMAAADAEoAbQwAAAEARQDqDAAABQBUAG4MAAACAE8AbwwAAAEAJAAdAAkJtR2gFgCBAgloDAAABQBdAGkMAAAEAFwAawwAAAQAXwBqDAAAAwA6AGwMAAADAEoAbQwAAAEARQDqDAAABQBUAG4MAAACAE8AbwwAAAEAJAAAAA==.',
Mc='Mckellen:BAECLgAFFH8HAAMOAAQJ+A0lDwADAQRoDAAAAgAwAGkMAAACADYAawwAAAEAEwDqDAAAAgAUAA4ABAldDSUPAAMBBGgMAAACADAAaQwAAAEANgBrDAAAAQATAOoMAAABAA0AHgACCREJAhQAlgACaQwAAAEAGgDqDAAAAQAUAC4ABAp/HQADHgAICc4ZmQwAbgIAHgAICc4ZmQwAbgIADgAECSYMg1wAwQAAAS4ABRQGCQsABwBSIAA=.',
Me='Merarite:BAEALgADCgEJAQABLgAECgkJNAAKAK4PAA==.',
Mi='Minidruid:BAECLgAFFH8IAAIZAAQJsRXxEAA6AQRoDAAAAgAwAGkMAAACAEMAawwAAAIAMQDqDAAAAgA4ABkABAmxFfEQADoBBGgMAAACADAAaQwAAAIAQwBrDAAAAgAxAOoMAAACADgALgAECn8YAAIZAAcJbyJ8CwA7AgAZAAcJbyJ8CwA7AgABLgAFFAMJBwADALYTAA==.',
Mo='Mordraius:BAEALgAECggJEQABLgAFFAQJEAADAJ4aAA==.',
My='Myceliums:BAEALgAECgQJCgAAAA==.',
Na='Nadasa:BAECLgAFFH8LAAIWAAQJywrmKQAkAQRoDAAABAAhAGkMAAADABgAawwAAAEAFADqDAAAAwAfABYABAnLCuYpACQBBGgMAAAEACEAaQwAAAMAGABrDAAAAQAUAOoMAAADAB8ALgAECn81AAIWAAkJ4x47FQB2AgAWAAkJ4x47FQB2AgAAAA==.Naramonria:BAEALgADCgcJCAAAAA==.',
Ni='Nixaanu:BAEALgAECgEJAQABLgAECggJFAAMAH8aAA==.Nixei:BAEBLgAECn8UAAIMAAgJfxpEGABTAghoDAAAAgAyAGkMAAACAEIAawwAAAIATwBqDAAAAgA3AGwMAAAEAFAAbQwAAAMARwDqDAAAAgA3AG4MAAADAEYADAAICX8aRBgAUwIIaAwAAAIAMgBpDAAAAgBCAGsMAAACAE8AagwAAAIANwBsDAAABABQAG0MAAADAEcA6gwAAAIANwBuDAAAAwBGAAAA.',
Ny='Nyriaa:BAEBLgAECn8eAAIOAAkJviO3AQBcAwloDAAABQBjAGkMAAAFAGIAawwAAAUAWwBqDAAAAwBfAGwMAAADAF4AbQwAAAEAUQDqDAAABQBjAG4MAAACAFMAbwwAAAEATwAOAAkJviO3AQBcAwloDAAABQBjAGkMAAAFAGIAawwAAAUAWwBqDAAAAwBfAGwMAAADAF4AbQwAAAEAUQDqDAAABQBjAG4MAAACAFMAbwwAAAEATwAAAA==.',
['Ní']='Nítedragon:BAEALgADCggJAwABLgAECgcJEwABAAAAAA==.',
Pa='Palashin:BAEALgAECgQJBAABLgAECgcJFQAOAOUeAA==.',
Pe='Peepofloor:BAEALgADCgcJCwABLgAFFAEJAQABAAAAAA==.Personnelkid:BAEALgAECgEJAQABLgAECggJIwAOAGERAA==.',
Ph='Pheiro:BAEBLgAECn8cAAIDAAgJcQ1wiADBAQhoDAAABQBSAGkMAAAFAC0AawwAAAQAJQBqDAAAAgAXAGwMAAACABAAbQwAAAQADwDqDAAABQAmAG4MAAABAAUAAwAICXENcIgAwQEIaAwAAAUAUgBpDAAABQAtAGsMAAAEACUAagwAAAIAFwBsDAAAAgAQAG0MAAAEAA8A6gwAAAUAJgBuDAAAAQAFAAAA.',
Pu='Punchweagle:BAEBLgAECn80AAMKAAkJrg+yFQCsAQloDAAACAAzAGkMAAAHAEAAawwAAAgAOgBqDAAABgAoAGwMAAAGADkAbQwAAAUAEQDqDAAABgAwAG4MAAAEAAsAbwwAAAIACwAKAAkJaA6yFQCsAQloDAAABAAzAGkMAAAEADQAawwAAAQAMwBqDAAABAAZAGwMAAAEADkAbQwAAAUAEQDqDAAABAAqAG4MAAAEAAsAbwwAAAIACwANAAYJUxRGMgBbAQZoDAAABAAyAGkMAAADAEAAawwAAAQAOgBqDAAAAgAoAGwMAAACACUA6gwAAAIAMAAAAA==.',
Qr='Qrowdrake:BAEALgAECgIJAgABLgAECggJEAABAAAAAA==.Qrowfather:BAEALgAECggJEAAAAA==.Qrowsunny:BAEALgAECgQJBQABLgAECggJEAABAAAAAA==.',
Ra='Raveglaive:BAEALgAECgQJAQAAAA==.',
Re='Redvine:BAEALgADCgUJBQABLgAFFAQJDwASACAVAA==.Rexpanda:BAEALgAECgQJBQABLgAECgUJBQABAAAAAA==.Rextank:BAEALgAECgEJAQABLgAECgUJBQABAAAAAA==.',
Ro='Roogies:BAECLgAFFH8SAAIUAAQJFCCzBgCIAQRoDAAABwBcAGkMAAAHAFUAawwAAAIANwDqDAAAAgBeABQABAkUILMGAIgBBGgMAAAHAFwAaQwAAAcAVQBrDAAAAgA3AOoMAAACAF4ALgAECn87AAMUAAkJiSXqAQAMAwAUAAkJWiXqAQAMAwAVAAIJnRghFQCoAAAAAA==.',
Ru='Rumpy:BAEALgAFFAIJBAABLgAFFAMJBwAUALsfAA==.',
['Ræ']='Ræx:BAEALgAECgUJBQAAAA==.',
['Rë']='Rëi:BAECLgAFFH8HAAIDAAMJthNrLQABAQNoDAAAAwA/AGkMAAACACMA6gwAAAIANAADAAMJthNrLQABAQNoDAAAAwA/AGkMAAACACMA6gwAAAIANAAuAAQKfxkAAgMACAkUHK5DAG0CAAMACAkUHK5DAG0CAAAA.',
Sh='Shiins:BAEALgAECgIJAwABLgAECgcJFQAOAOUeAA==.Shinthyr:BAEBLgAECn8VAAIOAAcJ5R4eFQA0AgdoDAAABABTAGkMAAADAFUAawwAAAMAXQBqDAAAAwBHAGwMAAACAFUA6gwAAAQASwBuDAAAAgA6AA4ABwnlHh4VADQCB2gMAAAEAFMAaQwAAAMAVQBrDAAAAwBdAGoMAAADAEcAbAwAAAIAVQDqDAAABABLAG4MAAACADoAAAA=.',
Si='Sizzlefox:BAEALgAECgEJAQABLgAECgUJDQABAAAAAA==.',
St='Stygianfox:BAEALgAECgEJAQABLgAECgUJDQABAAAAAA==.',
Ta='Tahune:BAEBLgAECn8yAAMdAAkJpSOzAQCUAwloDAAACABdAGkMAAAHAGIAawwAAAcAXwBqDAAABwBcAGwMAAAGAGEAbQwAAAQAXADqDAAABwBhAG4MAAADAFoAbwwAAAEAPgAdAAkJpSOzAQCUAwloDAAABgBdAGkMAAAHAGIAawwAAAUAXwBqDAAABwBcAGwMAAAGAGEAbQwAAAQAXADqDAAABwBhAG4MAAADAFoAbwwAAAEAPgAZAAIJhiHkQAChAAJoDAAAAgBWAGsMAAACAFUAAAA=.Taso:BAEBLgAECn8YAAIKAAgJ9BAjHwBcAQhoDAAABQA/AGkMAAAEAEMAawwAAAQASgBqDAAABABPAGwMAAABAAAAbQwAAAEAAADqDAAABAA6AG4MAAABACYACgAICfQQIx8AXAEIaAwAAAUAPwBpDAAABABDAGsMAAAEAEoAagwAAAQATwBsDAAAAQAAAG0MAAABAAAA6gwAAAQAOgBuDAAAAQAmAAEuAAUUBAkMABEAiyAA.',
Th='Therapygap:BAEBLgAECn8jAAQOAAgJYRG+JgA1AQhoDAAABgBMAGkMAAAHACUAawwAAAMANwBqDAAABAAdAGwMAAAHADQAbQwAAAEAIwDqDAAABgA8AG4MAAABAAgADgAHCV0TviYANQEHaAwAAAMATABpDAAAAwAlAGsMAAACADcAagwAAAMAHQBsDAAABQA0AG0MAAABACMA6gwAAAUAPAAEAAYJKwrkPQCxAAZoDAAAAwAnAGkMAAAEABUAawwAAAEAEgBqDAAAAQAHAGwMAAACACkA6gwAAAEACAAeAAEJfANQWwAjAAFuDAAAAQAIAAAA.',
Tr='Triboon:BAEALgADCgMJAwABLgAFFAYJEgAHAIIcAA==.Trèantdaddy:BAEALgAFFAEJAgABLgAFFAYJDgAFAJ8QAA==.',
Uh='Uhohfren:BAEALgAFFAEJAQAAAA==.',
Us='Usurah:BAECLgAFFH8XAAIWAAYJyRijCACqAQZoDAAABgBOAGkMAAAGAFYAawwAAAMAQQBqDAAAAwA8AGwMAAABABgA6gwAAAQAPgAWAAYJyRijCACqAQZoDAAABgBOAGkMAAAGAFYAawwAAAMAQQBqDAAAAwA8AGwMAAABABgA6gwAAAQAPgAuAAQKfysAAxYACQmAIsQJAEMDABYACQmAIsQJAEMDABgABQlYHHERAEcBAAAA.',
Vi='Vindh:BAECLgAFFH8OAAMTAAQJugfENQD3AARoDAAABQAXAGkMAAADABUAawwAAAIACADqDAAABAAYABMABAm6B8Q1APcABGgMAAAFABcAaQwAAAMAFQBrDAAAAgAIAOoMAAADABgAEgABCQ4GMAsAKwAB6gwAAAEADwAuAAQKfyQAAxMACQm3FV09AP8BABMACQm3FV09AP8BABIAAQlRA4AmACUAAAAA.',
Vy='Vyndraennis:BAEBLgAECn8cAAITAAgJ0BK8MwCUAQhoDAAABQAhAGkMAAAFAEUAawwAAAUAOQBqDAAAAwAyAGwMAAADABwAbQwAAAEALQDqDAAABQA1AG4MAAABADEAEwAICdASvDMAlAEIaAwAAAUAIQBpDAAABQBFAGsMAAAFADkAagwAAAMAMgBsDAAAAwAcAG0MAAABAC0A6gwAAAUANQBuDAAAAQAxAAAA.',
Ya='Yaav:BAEBLgAECn8VAAIPAAgJqhE7RgCPAQhoDAAABAA2AGkMAAAEADoAawwAAAMAJgBqDAAAAwBLAGwMAAADACMAbQwAAAEAKADqDAAAAgA0AG4MAAABACQADwAICaoRO0YAjwEIaAwAAAQANgBpDAAABAA6AGsMAAADACYAagwAAAMASwBsDAAAAwAjAG0MAAABACgA6gwAAAIANABuDAAAAQAkAAAA.',
Yu='Yufia:BAEBLgAECn8ZAAIIAAkJXR5GCgAsAwloDAAABABQAGkMAAAEAF8AawwAAAQAWABqDAAAAwBdAGwMAAACAFgAbQwAAAEAQgDqDAAABQBjAG4MAAABABEAbwwAAAEAVgAIAAkJXR5GCgAsAwloDAAABABQAGkMAAAEAF8AawwAAAQAWABqDAAAAwBdAGwMAAACAFgAbQwAAAEAQgDqDAAABQBjAG4MAAABABEAbwwAAAEAVgAAAA==.',
Za='Zatum:BAEBLgAECn8UAAIZAAcJlRweFADKAQdoDAAABABKAGkMAAAEAFYAawwAAAMATwBqDAAAAgA7AGwMAAACAEcA6gwAAAQAVABuDAAAAQAqABkABwmVHB4UAMoBB2gMAAAEAEoAaQwAAAQAVgBrDAAAAwBPAGoMAAACADsAbAwAAAIARwDqDAAABABUAG4MAAABACoAAAA=.',
Zh='Zhuröng:BAECLgAFFH8QAAIDAAQJnhoqLgBYAQRoDAAABQBJAGkMAAAFAE4AawwAAAMAKgDqDAAAAwBPAAMABAmeGiouAFgBBGgMAAAFAEkAaQwAAAUATgBrDAAAAwAqAOoMAAADAE8ALgAECn8mAAIDAAkJlx8tLgAMAgADAAkJlx8tLgAMAgAAAA==.',
Zo='Zomb:BAECLgAFFH8MAAIRAAQJiyCjBwBwAQRoDAAABQBYAGkMAAAEAEQAawwAAAEAXQDqDAAAAgBSABEABAmLIKMHAHABBGgMAAAFAFgAaQwAAAQARABrDAAAAQBdAOoMAAACAFIALgAECn8kAAIRAAgJjiFpBAAFAwARAAgJjiFpBAAFAwAAAA==.',
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
