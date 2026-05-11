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

local lookup = {'Unknown-Unknown','Evoker-Augmentation','Mage-Frost','Priest-Shadow','Evoker-Preservation','Evoker-Devastation','Warlock-Demonology','Warlock-Destruction','Monk-Brewmaster','Shaman-Elemental','Shaman-Restoration','Monk-Mistweaver','Monk-Windwalker','DeathKnight-Unholy','DeathKnight-Blood','Priest-Holy','DemonHunter-Vengeance','DemonHunter-Devourer','Rogue-Subtlety','Rogue-Assassination','Paladin-Retribution','Paladin-Holy','Warrior-Fury','Warrior-Protection','Warrior-Arms','Druid-Restoration','Priest-Discipline','Druid-Balance',}
local provider = {region='US',realm='MoonGuard',name='US',type='subscribers',zone=46,date='2026-05-10',data={Ad='Advvy:BAEALgAECgUJDAAAAA==.',
Ag='Ageregressor:BAEALgAECgcJBwAAAA==.',
Ai='Aihime:BAEALgADCgYJBgABLgAECgEJAQABAAAAAA==.',
Al='Alcean:BAEBLgAECn8oAAICAAkJkh9yAwDlAgloDAAABwBZAGkMAAAGAFgAawwAAAYAWwBqDAAABAA4AGwMAAAEAFUAbQwAAAMATQDqDAAABwBVAG4MAAACAEkAbwwAAAEANgACAAkJkh9yAwDlAgloDAAABwBZAGkMAAAGAFgAawwAAAYAWwBqDAAABAA4AGwMAAAEAFUAbQwAAAMATQDqDAAABwBVAG4MAAACAEkAbwwAAAEANgAAAA==.Algebra:BAECLgAFFH8OAAIDAAUJax7uHAB2AQVoDAAABABVAGkMAAADAD0AawwAAAMASwBqDAAAAQAPAOoMAAADAFkAAwAFCWse7hwAdgEFaAwAAAQAVQBpDAAAAwA9AGsMAAADAEsAagwAAAEADwDqDAAAAwBZAC4ABAp/GAACAwAJCVgj/AQALAMAAwAJCVgj/AQALAMAAAA=.Aléyna:BAEALgAECgEJAgAAAA==.',
Ar='Araakki:BAEALgAECgUJDAAAAA==.Arteron:BAEALgAFFAIJAwABLgAFFAcJHQAEACwdAA==.',
Ay='Ayoade:BAECLgAFFH8QAAIFAAQJ3BPsCgA8AQRoDAAABAArAGkMAAAEAD0AawwAAAQANADqDAAABAAtAAUABAncE+wKADwBBGgMAAAEACsAaQwAAAQAPQBrDAAABAA0AOoMAAAEAC0ALgAECn8YAAMFAAgJaRycCgCMAgAFAAgJaRycCgCMAgAGAAIJERXjMQCHAAAAAA==.',
Az='Azzurel:BAEBLgAECn8XAAMHAAgJLxFmQwBkAQhoDAAABAAxAGkMAAAEACkAawwAAAMAOABqDAAAAwAwAGwMAAADADwAbQwAAAIAEADqDAAAAwAwAG4MAAABACMABwAICS8RZkMAZAEIaAwAAAQAMQBpDAAABAApAGsMAAADADgAagwAAAIAMABsDAAAAwA8AG0MAAACABAA6gwAAAMAMABuDAAAAQAjAAgAAQkAADxyADMAAWoMAAABABQAAAA=.',
Bo='Bobbysan:BAECLgAFFH8bAAIJAAYJvRrWBgCTAQZoDAAABgBQAGkMAAAFAEwAawwAAAQASQBqDAAABABAAGwMAAACACgA6gwAAAYASAAJAAYJvRrWBgCTAQZoDAAABgBQAGkMAAAFAEwAawwAAAQASQBqDAAABABAAGwMAAACACgA6gwAAAYASAAuAAQKfykAAgkACQlaIC0GAIACAAkACQlaIC0GAIACAAAA.',
Br='Brigbala:BAEALgAECgMJBgAAAA==.',
Cr='Crustome:BAEALgAECgYJEgAAAA==.',
De='Deathhunterz:BAEALgAECgQJBAAAAA==.Demagogué:BAEBLgAECn8WAAMKAAcJmCT1DAAXAgdoDAAABgBgAGkMAAAEAFoAawwAAAQAXABqDAAAAgBiAGwMAAACAF4AbQwAAAEAXgDqDAAAAwBdAAoABwmYJPUMABcCB2gMAAAEAGAAaQwAAAMAWgBrDAAAAwBcAGoMAAACAGIAbAwAAAIAXgBtDAAAAQBeAOoMAAABAF0ACwAECSAi/1cAKAEEaAwAAAIAVgBpDAAAAQBUAGsMAAABAFoA6gwAAAIAWAABLgAFFAYJDgAFAJ8QAA==.Demonipryde:BAEALgAECgMJAwAAAA==.',
Dr='Drunkenqrow:BAEALgAECgYJDQABLgAECggJDgABAAAAAA==.',
Du='Dubsii:BAECLgAFFH8GAAIMAAQJxhgBDgC/AARoDAAAAQBNAGkMAAABAFkAawwAAAIAKABsDAAAAgAuAAwABAnGGAEOAL8ABGgMAAABAE0AaQwAAAEAWQBrDAAAAgAoAGwMAAACAC4ALgAECn8XAAMMAAgJiyGcBgDzAgAMAAgJiyGcBgDzAgANAAEJfyZ+RQBvAAABLgAFFAQJEAAFANwTAA==.',
Eh='Ehanee:BAEALgAECgkJDwAAAA==.',
Ev='Evielyssa:BAEALgAECgYJDwABLgAFFAMJAwABAAAAAA==.Evierari:BAEALgAFFAMJAwAAAA==.',
Fa='Fappimeal:BAECLgAFFH8WAAIOAAUJkiS2EQCUAQVoDAAABgBiAGkMAAAGAGEAawwAAAQATgBqDAAAAQA3AOoMAAAFAGMADgAFCZIkthEAlAEFaAwAAAYAYgBpDAAABgBhAGsMAAAEAE4AagwAAAEANwDqDAAABQBjAC4ABAp/MAACDgAJCfgleAIAtAMADgAJCfgleAIAtAMAAAA=.',
Fo='Fofer:BAEBLgAECn8cAAIJAAYJ8SXuCwAMAgZoDAAABgBhAGkMAAAGAF4AawwAAAYAYwBqDAAAAwBhAGwMAAADAGEA6gwAAAQAYAAJAAYJ8SXuCwAMAgZoDAAABgBhAGkMAAAGAF4AawwAAAYAYwBqDAAAAwBhAGwMAAADAGEA6gwAAAQAYAABLgAFFAYJGQAPAIoeAA==.',
Fr='Froshin:BAEALgADCgUJCgABLgAECgcJFQAQAOUeAA==.',
Fu='Funkey:BAECLgAFFH8MAAMRAAQJIBWeAgCjAARoDAAABABDAGkMAAAEAFoAawwAAAEAFADqDAAAAwAmABIABAmZDi4rAA8BBGgMAAACACEAaQwAAAMAOABrDAAAAQAUAOoMAAADACYAEQACCbYengIAowACaAwAAAIAQwBpDAAAAQBaAC4ABAp/JwADEQAJCZ8gxAEA/AIAEQAICbMixAEA/AIAEgAGCX4WtiUAsQEAAAA=.',
Gr='Greathades:BAEALgAECgkJAgAAAA==.Greatmonkey:BAEALgAECgcJBgABLgAECgkJAgABAAAAAA==.Greatra:BAEALgADCgEJAQABLgAECgkJAgABAAAAAA==.Grummel:BAECLgAFFH8GAAITAAIJSR9AEADOAAJoDAAABQBbAGkMAAABAEQAEwACCUkfQBAAzgACaAwAAAUAWwBpDAAAAQBEAC4ABAp/HwADEwAICf8hfgkA+QIAEwAICf8hfgkA+QIAFAABCXAUah0AQAAAAAA=.',
Hb='Hbcarter:BAEALgAFFAIJAgABLgAFFAQJEAAFANwTAA==.',
Ia='Iambuns:BAEALgADCgcJBwABLgAFFAUJFgAOAJIkAA==.',
Il='Illiyania:BAEALgAECgEJAQAAAA==.',
Im='Imquitelarge:BAEALgAECgkJEwAAAA==.',
Iz='Izapotato:BAECLgAFFH8TAAISAAUJMxghCQCXAQVoDAAABABUAGkMAAAEACoAawwAAAQANABqDAAAAwBDAOoMAAAEAEQAEgAFCTMYIQkAlwEFaAwAAAQAVABpDAAABAAqAGsMAAAEADQAagwAAAMAQwDqDAAABABEAC4ABAp/GwACEgAHCX4lpBgAwQIAEgAHCX4lpBgAwQIAAS4ABRQGCQ4ABQCfEAA=.',
Ke='Kelandrea:BAEBLgAECn8aAAMVAAkJoRrVIgCeAgloDAAABABTAGkMAAAEAFYAawwAAAMAUABqDAAAAwBiAGwMAAADAFIAbQwAAAMALQDqDAAAAgBcAG4MAAADAEYAbwwAAAEABQAVAAkJoRrVIgCeAgloDAAAAwBTAGkMAAADAFYAawwAAAMAUABqDAAAAwBiAGwMAAADAFIAbQwAAAMALQDqDAAAAgBcAG4MAAADAEYAbwwAAAEABQAWAAIJ0hD3gQBwAAJoDAAAAQASAGkMAAABAEMAAAA=.',
Ki='Kirkh:BAEALgAECgcJCwABLgAECgkJJgAEAEobAA==.Kirkpriest:BAEBLgAECn8mAAIEAAkJSht8BwAQAwloDAAABQBbAGkMAAAFAFkAawwAAAUAXABqDAAABQBPAGwMAAAFAFcAbQwAAAQAMADqDAAABQBaAG4MAAADADEAbwwAAAEACQAEAAkJSht8BwAQAwloDAAABQBbAGkMAAAFAFkAawwAAAUAXABqDAAABQBPAGwMAAAFAFcAbQwAAAQAMADqDAAABQBaAG4MAAADADEAbwwAAAEACQAAAA==.Kitowatt:BAEALgAECgYJCgABLgAECgcJDgABAAAAAA==.',
Kr='Kregazi:BAEBLgAECn8pAAIPAAgJmSB4BACAAghoDAAABwBXAGkMAAAGAFoAawwAAAYAXgBqDAAABgBZAGwMAAAFAGEAbQwAAAMATADqDAAABQBSAG4MAAADADYADwAICZkgeAQAgAIIaAwAAAcAVwBpDAAABgBaAGsMAAAGAF4AagwAAAYAWQBsDAAABQBhAG0MAAADAEwA6gwAAAUAUgBuDAAAAwA2AAAA.',
La='Larissaqt:BAECLgAFFH8SAAIEAAYJQQuhBQCMAQZoDAAABAAoAGkMAAADACwAawwAAAQAEQBqDAAAAwAfAGwMAAABABMA6gwAAAMAFQAEAAYJQQuhBQCMAQZoDAAABAAoAGkMAAADACwAawwAAAQAEQBqDAAAAwAfAGwMAAABABMA6gwAAAMAFQAuAAQKfxoAAgQACAkTHeYRAGwCAAQACAkTHeYRAGwCAAAA.',
Li='Lilylock:BAEALgAECgEJAQABLgAECggJFgAXAHAeAA==.Lilyweave:BAEBLgAECn8WAAQXAAgJcB4nCgBNAghoDAAAAwBLAGkMAAADAFcAawwAAAMAVwBqDAAABABcAGwMAAADAFEAbQwAAAIAPADqDAAAAgBaAG4MAAACAD4AFwAICXAeJwoATQIIaAwAAAIASwBpDAAAAgBXAGsMAAADAFcAagwAAAQAXABsDAAAAgBRAG0MAAACADwA6gwAAAIAWgBuDAAAAgA+ABgAAgkNDzs9AGMAAmgMAAABABgAaQwAAAEANAAZAAEJNwzBQgAzAAFsDAAAAQAfAAAA.Lioshi:BAEALgAECgYJCQABLgAFFAQJDAADAJ4aAA==.',
Ma='Maildaddy:BAECLgAFFH8OAAIFAAYJnxDJBwCrAQZoDAAAAwAwAGkMAAADAEMAawwAAAMALQBqDAAAAQAiAGwMAAABAAoA6gwAAAMAMQAFAAYJnxDJBwCrAQZoDAAAAwAwAGkMAAADAEMAawwAAAMALQBqDAAAAQAiAGwMAAABAAoA6gwAAAMAMQAuAAQKfxsABAUACAnnF3YOAFACAAUABwnZGnYOAFACAAIABQkoESU3ABsBAAYAAwkcHN8nAOIAAAAA.Maxxy:BAEBLgAECn8cAAIaAAkJtR2fFgCBAgloDAAABQBdAGkMAAAEAFwAawwAAAQAXwBqDAAAAwA6AGwMAAADAEoAbQwAAAEARQDqDAAABQBUAG4MAAACAE8AbwwAAAEAJAAaAAkJtR2fFgCBAgloDAAABQBdAGkMAAAEAFwAawwAAAQAXwBqDAAAAwA6AGwMAAADAEoAbQwAAAEARQDqDAAABQBUAG4MAAACAE8AbwwAAAEAJAAAAA==.',
Mc='Mckellen:BAECLgAFFH8HAAMQAAQJ+A09DQAJAQRoDAAAAgAwAGkMAAACADYAawwAAAEAEwDqDAAAAgAUABAABAldDT0NAAkBBGgMAAACADAAaQwAAAEANgBrDAAAAQATAOoMAAABAA0AGwACCREJABQAlgACaQwAAAEAGgDqDAAAAQAUAC4ABAp/HQADGwAICc4ZmAwAbgIAGwAICc4ZmAwAbgIAEAAECSYMg1wAwQAAAS4ABRQECRAABQDcEwA=.',
Me='Merarite:BAEALgADCgEJAQABLgAECgkJMQAJAMUOAA==.',
Mi='Minidruid:BAEBLgAECn8VAAIcAAcJByA+CgAzAgdoDAAABABQAGkMAAAEAFwAawwAAAQAVgBqDAAABABNAGwMAAACAE0AbQwAAAIAVgDqDAAAAQBEABwABwkHID4KADMCB2gMAAAEAFAAaQwAAAQAXABrDAAABABWAGoMAAAEAE0AbAwAAAIATQBtDAAAAgBWAOoMAAABAEQAAS4ABRQDCQcAAwC2EwA=.',
Mo='Mordraius:BAEALgAECggJEQABLgAFFAQJDAADAJ4aAA==.',
My='Myceliums:BAEALgAECgQJBwAAAA==.',
Na='Nadasa:BAECLgAFFH8IAAIVAAQJnQmAJgAgAQRoDAAAAwAhAGkMAAACAAwAawwAAAEAFADqDAAAAgAfABUABAmdCYAmACABBGgMAAADACEAaQwAAAIADABrDAAAAQAUAOoMAAACAB8ALgAECn81AAIVAAkJ4x5IDwCMAgAVAAkJ4x5IDwCMAgAAAA==.Naramonria:BAEALgADCgcJCAAAAA==.',
Ni='Nixaanu:BAEALgAECgEJAQABLgAECggJFAAKAH8aAA==.Nixei:BAEBLgAECn8UAAIKAAgJfxpBGABTAghoDAAAAgAyAGkMAAACAEIAawwAAAIATwBqDAAAAgA3AGwMAAAEAFAAbQwAAAMARwDqDAAAAgA3AG4MAAADAEYACgAICX8aQRgAUwIIaAwAAAIAMgBpDAAAAgBCAGsMAAACAE8AagwAAAIANwBsDAAABABQAG0MAAADAEcA6gwAAAIANwBuDAAAAwBGAAAA.',
Ny='Nyriaa:BAEBLgAECn8eAAIQAAkJviM4AQBoAwloDAAABQBjAGkMAAAFAGIAawwAAAUAWwBqDAAAAwBfAGwMAAADAF4AbQwAAAEAUQDqDAAABQBjAG4MAAACAFMAbwwAAAEATwAQAAkJviM4AQBoAwloDAAABQBjAGkMAAAFAGIAawwAAAUAWwBqDAAAAwBfAGwMAAADAF4AbQwAAAEAUQDqDAAABQBjAG4MAAACAFMAbwwAAAEATwAAAA==.',
['Ní']='Nítedragon:BAEALgADCggJAwABLgAECgcJEwABAAAAAA==.',
Pe='Peepofloor:BAEALgADCgcJCwABLgAFFAEJAQABAAAAAA==.Personnelkid:BAEALgAECgEJAQABLgAECggJIgAQAGERAA==.',
Ph='Pheiro:BAEBLgAECn8cAAIDAAgJcQ1wiADBAQhoDAAABQBSAGkMAAAFAC0AawwAAAQAJQBqDAAAAgAXAGwMAAACABAAbQwAAAQADwDqDAAABQAmAG4MAAABAAUAAwAICXENcIgAwQEIaAwAAAUAUgBpDAAABQAtAGsMAAAEACUAagwAAAIAFwBsDAAAAgAQAG0MAAAEAA8A6gwAAAUAJgBuDAAAAQAFAAAA.',
Pu='Punchweagle:BAEBLgAECn8xAAMJAAkJxQ58EwCqAQloDAAACAAzAGkMAAAHAEAAawwAAAgAOgBqDAAABQAoAGwMAAAFACcAbQwAAAQAEQDqDAAABgAwAG4MAAAEAAsAbwwAAAIACwAJAAkJfw18EwCqAQloDAAABAAzAGkMAAAEADQAawwAAAQAMwBqDAAAAwAOAGwMAAADACcAbQwAAAQAEQDqDAAABAAqAG4MAAAEAAsAbwwAAAIACwANAAYJUxRBMgBbAQZoDAAABAAyAGkMAAADAEAAawwAAAQAOgBqDAAAAgAoAGwMAAACACUA6gwAAAIAMAAAAA==.',
Qr='Qrowfather:BAEALgAECggJDgAAAA==.Qrowsunny:BAEALgAECgQJBQABLgAECggJDgABAAAAAA==.',
Ra='Raveglaive:BAEALgAECgQJAQAAAA==.',
Re='Redvine:BAEALgADCgUJBQABLgAFFAQJDAARACAVAA==.Rexpanda:BAEALgAECgQJBQABLgAECgUJBQABAAAAAA==.Rextank:BAEALgAECgEJAQABLgAECgUJBQABAAAAAA==.',
Ru='Rumpy:BAEALgAFFAIJAgABLgAFFAIJBgATAEkfAA==.',
['Ræ']='Ræx:BAEALgAECgUJBQAAAA==.',
['Rë']='Rëi:BAECLgAFFH8HAAIDAAMJthNnLQABAQNoDAAAAwA/AGkMAAACACMA6gwAAAIANAADAAMJthNnLQABAQNoDAAAAwA/AGkMAAACACMA6gwAAAIANAAuAAQKfxkAAgMACAkUHK1DAG0CAAMACAkUHK1DAG0CAAAA.',
Sh='Shiins:BAEALgAECgIJAwABLgAECgcJFQAQAOUeAA==.Shinthyr:BAEBLgAECn8VAAIQAAcJ5R4eFQA0AgdoDAAABABTAGkMAAADAFUAawwAAAMAXQBqDAAAAwBHAGwMAAACAFUA6gwAAAQASwBuDAAAAgA6ABAABwnlHh4VADQCB2gMAAAEAFMAaQwAAAMAVQBrDAAAAwBdAGoMAAADAEcAbAwAAAIAVQDqDAAABABLAG4MAAACADoAAAA=.',
Si='Sizzlefox:BAEALgAECgEJAQABLgAECgUJDAABAAAAAA==.',
St='Stygianfox:BAEALgAECgEJAQABLgAECgUJDAABAAAAAA==.',
Ta='Tahune:BAEBLgAECn8yAAMaAAkJpSNeAQCaAwloDAAACABdAGkMAAAHAGIAawwAAAcAXwBqDAAABwBcAGwMAAAGAGEAbQwAAAQAXADqDAAABwBhAG4MAAADAFoAbwwAAAEAPgAaAAkJpSNeAQCaAwloDAAABgBdAGkMAAAHAGIAawwAAAUAXwBqDAAABwBcAGwMAAAGAGEAbQwAAAQAXADqDAAABwBhAG4MAAADAFoAbwwAAAEAPgAcAAIJhiEvOwCoAAJoDAAAAgBWAGsMAAACAFUAAAA=.Taso:BAEALgAECgcJEgABLgAFFAQJDAAPAIsgAA==.',
Th='Therapygap:BAEBLgAECn8iAAQQAAgJYRFoIgA+AQhoDAAABgBMAGkMAAAHACUAawwAAAMANwBqDAAABAAdAGwMAAAGADQAbQwAAAEAIwDqDAAABgA8AG4MAAABAAgAEAAHCV0TaCIAPgEHaAwAAAMATABpDAAAAwAlAGsMAAACADcAagwAAAMAHQBsDAAABQA0AG0MAAABACMA6gwAAAUAPAAEAAYJqAn1NgC9AAZoDAAAAwAnAGkMAAAEABUAawwAAAEAEgBqDAAAAQAHAGwMAAABACIA6gwAAAEACAAbAAEJfAMzUwAjAAFuDAAAAQAIAAAA.',
Tr='Triboon:BAEALgADCgMJAwABLgAFFAYJEgAMAIIcAA==.Trèantdaddy:BAEALgAFFAEJAgABLgAFFAYJDgAFAJ8QAA==.',
Uh='Uhohfren:BAEALgAFFAEJAQAAAA==.',
Us='Usurah:BAECLgAFFH8UAAIVAAUJmhwSCgBcAQVoDAAABQBOAGkMAAAFAFYAawwAAAMAQQBqDAAAAwA8AOoMAAAEAD4AFQAFCZocEgoAXAEFaAwAAAUATgBpDAAABQBWAGsMAAADAEEAagwAAAMAPADqDAAABAA+AC4ABAp/JgACFQAJCYAiwgkAQwMAFQAJCYAiwgkAQwMAAAA=.',
Vi='Vindh:BAECLgAFFH8KAAMSAAQJgQfOMAD5AARoDAAABAAXAGkMAAACABUAawwAAAEABgDqDAAAAwAYABIABAmBB84wAPkABGgMAAAEABcAaQwAAAIAFQBrDAAAAQAGAOoMAAACABgAEQABCQ4GGwoAKwAB6gwAAAEADwAuAAQKfyQAAxIACQm3FVo9AP8BABIACQm3FVo9AP8BABEAAQlRA+kiACUAAAAA.',
Vy='Vyndraennis:BAEBLgAECn8cAAISAAgJ0BI1KQCfAQhoDAAABQAhAGkMAAAFAEUAawwAAAUAOQBqDAAAAwAyAGwMAAADABwAbQwAAAEALQDqDAAABQA1AG4MAAABADEAEgAICdASNSkAnwEIaAwAAAUAIQBpDAAABQBFAGsMAAAFADkAagwAAAMAMgBsDAAAAwAcAG0MAAABAC0A6gwAAAUANQBuDAAAAQAxAAAA.',
Ya='Yaav:BAEBLgAECn8VAAIOAAgJqhE3OAClAQhoDAAABAA2AGkMAAAEADoAawwAAAMAJgBqDAAAAwBLAGwMAAADACMAbQwAAAEAKADqDAAAAgA0AG4MAAABACQADgAICaoRNzgApQEIaAwAAAQANgBpDAAABAA6AGsMAAADACYAagwAAAMASwBsDAAAAwAjAG0MAAABACgA6gwAAAIANABuDAAAAQAkAAAA.',
Yu='Yufia:BAEBLgAECn8ZAAIHAAkJXR5HCgAsAwloDAAABABQAGkMAAAEAF8AawwAAAQAWABqDAAAAwBdAGwMAAACAFgAbQwAAAEAQgDqDAAABQBjAG4MAAABABEAbwwAAAEAVgAHAAkJXR5HCgAsAwloDAAABABQAGkMAAAEAF8AawwAAAQAWABqDAAAAwBdAGwMAAACAFgAbQwAAAEAQgDqDAAABQBjAG4MAAABABEAbwwAAAEAVgAAAA==.',
Za='Zatum:BAEALgAECgcJDgAAAA==.',
Zh='Zhuröng:BAECLgAFFH8MAAIDAAQJnhoQJwBfAQRoDAAABABJAGkMAAAEAE4AawwAAAIAKgDqDAAAAgBPAAMABAmeGhAnAF8BBGgMAAAEAEkAaQwAAAQATgBrDAAAAgAqAOoMAAACAE8ALgAECn8fAAIDAAgJRyDJTQBNAgADAAgJRyDJTQBNAgAAAA==.',
Zo='Zomb:BAECLgAFFH8MAAIPAAQJiyDqBQB6AQRoDAAABQBYAGkMAAAEAEQAawwAAAEAXQDqDAAAAgBSAA8ABAmLIOoFAHoBBGgMAAAFAFgAaQwAAAQARABrDAAAAQBdAOoMAAACAFIALgAECn8kAAIPAAgJjiFpBAAFAwAPAAgJjiFpBAAFAwAAAA==.',
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
