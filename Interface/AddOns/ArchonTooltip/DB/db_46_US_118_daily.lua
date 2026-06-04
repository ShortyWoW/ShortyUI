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

local lookup = {'Warrior-Fury','DemonHunter-Devourer','DeathKnight-Unholy','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','Unknown-Unknown','Druid-Feral','Warlock-Destruction','Warrior-Protection','Paladin-Retribution','Hunter-Survival','Warrior-Arms','Evoker-Preservation','Mage-Frost','Evoker-Augmentation','Druid-Restoration','Druid-Balance','Priest-Discipline','Priest-Holy','Priest-Shadow','DeathKnight-Blood','Hunter-BeastMastery','Evoker-Devastation','Paladin-Holy','Paladin-Protection','Druid-Guardian','DemonHunter-Havoc','Warlock-Demonology','Warlock-Affliction','DemonHunter-Vengeance','Shaman-Elemental','Rogue-Assassination',}
local provider = {region='US',realm='Haomarush',name='US',type='daily',zone=46,date='2026-06-03',data={Ad='Adderall:BAAALgAECggJDgAAAA==.',
Ae='Aethrion:BAAALgAECgMJBwAAAA==.',
Al='Alexya:BAAALgADCgIJAgAAAA==.All:BAAALgADCgEJAQAAAA==.Alphahawk:BAACLgAFFH8OAAIBAAQJwgi+JAAOAQRoDAAABAAQAGkMAAAEABgAawwAAAIAEgDqDAAABAAdAAEABAnCCL4kAA4BBGgMAAAEABAAaQwAAAQAGABrDAAAAgASAOoMAAAEAB0ALgAECn9CAAIBAAkJBBuqFQA2AgABAAkJBBuqFQA2AgAAAA==.',
Ap='Apocalipsis:BAAALgAECgMJAwAAAA==.',
Aq='Aquilis:BAABLgAECn8TAAICAAkJAhigVgCeAQloDAAAAwBMAGkMAAADAFQAawwAAAMATABqDAAAAQArAGwMAAADADcAbQwAAAIANwDqDAAAAQAvAG4MAAACAEEAbwwAAAEAHwACAAkJAhigVgCeAQloDAAAAwBMAGkMAAADAFQAawwAAAMATABqDAAAAQArAGwMAAADADcAbQwAAAIANwDqDAAAAQAvAG4MAAACAEEAbwwAAAEAHwAAAA==.',
Ar='Aralaria:BAAALgAECgUJBQABLgAFFAMJCAADAKYbAA==.Aramis:BAAALgAECggJEwABLgAFFAMJCAADAKYbAA==.Aranumi:BAAALgAECgQJBAABLgAFFAMJCAADAKYbAA==.Arathrok:BAACLgAFFH8IAAIDAAMJphtCeAD6AANoDAAABABMAGkMAAADAFgA6gwAAAEALwADAAMJphtCeAD6AANoDAAABABMAGkMAAADAFgA6gwAAAEALwAuAAQKfx4AAgMACQmLIABNANABAAMACQmLIABNANABAAAA.',
As='Asha:BAACLgAFFH8YAAQEAAUJ/xZrEAAqAQVoDAAABQBHAGkMAAAFADEAawwAAAUATgBqDAAABAA7AOoMAAAFACQABAAFCf8WaxAAKgEFaAwAAAMARwBpDAAAAwAxAGsMAAADAE4AagwAAAIAOwDqDAAAAwAkAAUABQkADQ0hACYBBWgMAAABAEkAaQwAAAEAKABrDAAAAQALAGoMAAABABsA6gwAAAEADAAGAAUJ7QVILgDfAAVoDAAAAQAWAGkMAAABAA0AawwAAAEADwBqDAAAAQAUAOoMAAABAAgALgAECn8cAAQEAAgJyyBeGwDDAQAEAAgJyyBeGwDDAQAFAAQJ0BwkQQBEAQAGAAUJxhl6NQAdAQAAAA==.Asmoday:BAABLgAECn8pAAIDAAkJziKjDgDrAgloDAAABgBUAGkMAAAGAF8AawwAAAYAWgBqDAAAAwBUAGwMAAAFAFoAbQwAAAMAXgDqDAAABwBYAG4MAAAEAFMAbwwAAAEAVgADAAkJziKjDgDrAgloDAAABgBUAGkMAAAGAF8AawwAAAYAWgBqDAAAAwBUAGwMAAAFAFoAbQwAAAMAXgDqDAAABwBYAG4MAAAEAFMAbwwAAAEAVgAAAA==.Astra:BAAALgAECgEJAQABLgAFFAEJAQAHAAAAAA==.Asunawa:BAAALgADCgUJBQAAAA==.',
Au='Aundarr:BAAALgAECgQJBAABLgAECgkJKQADAM4iAA==.Autoshift:BAABLgAECn8WAAIIAAgJ7wp7GQApAQhoDAAABAAeAGkMAAAEACUAawwAAAQAKwBqDAAAAwAlAGwMAAACACAAbQwAAAEAFgDqDAAAAgAQAG4MAAACAAwACAAICe8KexkAKQEIaAwAAAQAHgBpDAAABAAlAGsMAAAEACsAagwAAAMAJQBsDAAAAgAgAG0MAAABABYA6gwAAAIAEABuDAAAAgAMAAAA.Auun:BAAALgAECgYJBwABLgAECgkJKQADAM4iAA==.',
Ba='Bartre:BAAALgAECgQJBwABLgAFFAQJFAAJAGgjAA==.Bat:BAABLgAECn8eAAIIAAkJZCWGAgDxAgloDAAABQBjAGkMAAAFAF4AawwAAAMAYgBqDAAABABiAGwMAAAEAF4AbQwAAAMAYQDqDAAAAwBeAG4MAAACAFgAbwwAAAEAYwAIAAkJZCWGAgDxAgloDAAABQBjAGkMAAAFAF4AawwAAAMAYgBqDAAABABiAGwMAAAEAF4AbQwAAAMAYQDqDAAAAwBeAG4MAAACAFgAbwwAAAEAYwAAAA==.',
Be='Benedictine:BAAALgAECgEJBQAAAA==.',
Bi='Bigcleavage:BAABLgAECn8hAAIKAAkJAxtYDQAGAgloDAAABwA+AGkMAAAFAEsAawwAAAUAWQBqDAAABABRAGwMAAAEAFEAbQwAAAIAKADqDAAAAwA4AG4MAAACAEkAbwwAAAEASgAKAAkJAxtYDQAGAgloDAAABwA+AGkMAAAFAEsAawwAAAUAWQBqDAAABABRAGwMAAAEAFEAbQwAAAIAKADqDAAAAwA4AG4MAAACAEkAbwwAAAEASgAAAA==.Bilbert:BAAALgAECgMJAwABLgAFFAMJCAALAGAgAA==.',
Bl='Blue:BAAALgAECgYJBgABLgAFFAcJFwAMAEESAA==.Blueberrypie:BAAALgAFFAEJAQABLgAFFAMJBQANAGATAA==.',
Bo='Boomster:BAABLgAFFH8KAAIOAAYJ5h9QBgAwAgZoDAAAAgA+AGkMAAACAEoAawwAAAEASwBqDAAAAQBRAGwMAAABAGEA6gwAAAMAYgAOAAYJ5h9QBgAwAgZoDAAAAgA+AGkMAAACAEoAawwAAAEASwBqDAAAAQBRAGwMAAABAGEA6gwAAAMAYgABLgAFFAkJCwAFAOIdAA==.',
Br='Bridgetpower:BAAALgADCgIJAgAAAA==.',
Ca='Calixta:BAACLgAFFH8IAAILAAMJYCCoRgAQAQNoDAAABABSAGkMAAADAEYA6gwAAAEAXwALAAMJYCCoRgAQAQNoDAAABABSAGkMAAADAEYA6gwAAAEAXwAuAAQKfyIAAgsACQnBI2oUALwCAAsACQnBI2oUALwCAAAA.Carbshock:BAAALgADCgYJCgAAAA==.',
Ce='Ceroah:BAAALgAECgYJCwAAAA==.',
Ch='Cherrypie:BAAALgAFFAEJAQABLgAFFAMJBQANAGATAA==.',
Co='Coodown:BAAALgAECgYJCAAAAA==.',
Cr='Cranberrypie:BAAALgAECgQJBQABLgAFFAMJBQANAGATAA==.Criscomaster:BAAALgADCgYJEQAAAA==.',
Cy='Cylla:BAACLgAFFH8TAAIPAAQJlAyhXgAbAQRoDAAABgAuAGkMAAAGABIAawwAAAIADQDqDAAABQAxAA8ABAmUDKFeABsBBGgMAAAGAC4AaQwAAAYAEgBrDAAAAgANAOoMAAAFADEALgAECn86AAIPAAkJfBxJLgBWAgAPAAkJfBxJLgBWAgAAAA==.',
De='Delacour:BAAALgAECgQJBAABLgAECgkJKQADAM4iAA==.',
Di='Dilfdormu:BAABLgAECn8aAAMOAAYJHxD1GgAeAQZoDAAABAA4AGkMAAAFAEcAawwAAAUAJABqDAAABQASAGwMAAACAB0A6gwAAAUAIgAOAAYJHxD1GgAeAQZoDAAABAA4AGkMAAAEAEcAawwAAAQAJABqDAAABQASAGwMAAACAB0A6gwAAAUAIgAQAAIJ1QKKhwA2AAJpDAAAAQAGAGsMAAABAAcAAAA=.',
Dk='Dkvaluemenu:BAAALgAECgQJBAAAAA==.',
Do='Donkey:BAAALgADCgIJAgAAAA==.Doson:BAACLgAFFH8NAAIRAAQJWRKZKAAQAQRoDAAABgA7AGkMAAAEACEAawwAAAEAGADqDAAAAgBFABEABAlZEpkoABABBGgMAAAGADsAaQwAAAQAIQBrDAAAAQAYAOoMAAACAEUALgAECn85AAMRAAkJPh+pCAAjAwARAAkJPh+pCAAjAwASAAEJ2iShZwBqAAAAAA==.',
Dr='Dragonmabals:BAAALgAECgQJBAAAAA==.Dratak:BAACLgAFFH88AAIKAAgJ0SOVAADcAghoDAAACgBjAGkMAAAJAGEAawwAAAkAXgBqDAAABwBfAGwMAAAGAGEAbQwAAAUASADqDAAACwBhAG4MAAADAFMACgAICdEjlQAA3AIIaAwAAAoAYwBpDAAACQBhAGsMAAAJAF4AagwAAAcAXwBsDAAABgBhAG0MAAAFAEgA6gwAAAsAYQBuDAAAAwBTAC4ABAp/cQACCgAJCcomFgAAlgMACgAJCcomFgAAlgMAAAA=.Dread:BAABLgAECn8bAAIEAAgJjBrAEAB2AghoDAAABQBVAGkMAAAEAFwAawwAAAQAWQBqDAAABABGAGwMAAADAFQAbQwAAAIAFgDqDAAABABEAG4MAAABAB8ABAAICYwawBAAdgIIaAwAAAUAVQBpDAAABABcAGsMAAAEAFkAagwAAAQARgBsDAAAAwBUAG0MAAACABYA6gwAAAQARABuDAAAAQAfAAAA.Dreadfang:BAAALgADCgcJDQAAAA==.Dred:BAAALgAECgMJBwAAAA==.Drizbul:BAAALgAECgEJBAABLgAFFAgJPAAKANEjAA==.',
Ea='Earthswrath:BAAALgAECgUJDgAAAA==.',
El='Elitzai:BAAALgAECgIJAwAAAA==.Elusivemonk:BAAALgAECgEJAQAAAA==.',
Em='Emeralda:BAAALgADCgcJDQAAAA==.',
Ev='Evalueate:BAAALgAECgQJBAAAAA==.',
Fl='Fluf:BAAALgADCgcJDAAAAA==.',
Fr='Frocknor:BAABLgAECn8gAAMKAAcJjxWlHwAjAQdoDAAABgAjAGkMAAAGADMAawwAAAUALQBqDAAAAwBHAGwMAAAEAFEA6gwAAAcAOgBuDAAAAQA5AAEABglLFIg9AEEBBmgMAAAEACMAaQwAAAQALgBrDAAAAwAlAGoMAAACAEcAbAwAAAEAUQDqDAAABgA6AAoABwleEKUfACMBB2gMAAACABUAaQwAAAIAMwBrDAAAAgAtAGoMAAABAEMAbAwAAAMAIwDqDAAAAQAnAG4MAAABADkAAAA=.',
Fu='Fuki:BAAALgAECgQJDAAAAA==.Furrymythh:BAAALgAECgQJBAABLgAFFAQJFAAKAIUlAA==.',
Fy='Fyrstureinn:BAAALgADCgIJAgAAAA==.',
Ga='Galumian:BAACLgAFFH8rAAITAAgJYiLSAAByAghoDAAACABfAGkMAAAHAF4AawwAAAUAYQBqDAAABgBcAGwMAAAFAGAAbQwAAAIAMgDqDAAACQBZAG4MAAABAFcAEwAICWIi0gAAcgIIaAwAAAgAXwBpDAAABwBeAGsMAAAFAGEAagwAAAYAXABsDAAABQBgAG0MAAACADIA6gwAAAkAWQBuDAAAAQBXAC4ABAp/QQAEEwAJCaUl7wAA0AMAEwAJCaUl7wAA0AMAFAAHCRIRQC8AhgEAFQACCdwhukYAyQAAAAA=.',
Ge='Geron:BAAALgAECgUJBQABLgAFFAMJCAALAGAgAA==.Geronimô:BAAALgAECgYJDAAAAA==.Gerønimo:BAAALgAECgEJAQAAAA==.',
Go='Goo:BAAALgAECgcJDAABLgAFFAYJFgAWACIWAA==.',
Gu='Gummies:BAAALgAECgEJAQAAAA==.Guy:BAAALgADCgcJBwAAAA==.',
Ha='Hamhock:BAAALgAECgQJDgAAAA==.Haradali:BAAALgAFFAQJBAAAAA==.Hawa:BAAALgADCgEJAQAAAA==.',
Hi='Highpantsman:BAAALgAECgcJCAAAAA==.',
Ho='Holydiah:BAABLgAECn8cAAILAAYJcQu6xwDuAAZoDAAABgAhAGkMAAAGABYAawwAAAYAFwBqDAAABQAzAGwMAAAEACkA6gwAAAEAGAALAAYJcQu6xwDuAAZoDAAABgAhAGkMAAAGABYAawwAAAYAFwBqDAAABQAzAGwMAAAEACkA6gwAAAEAGAAAAA==.Holypriest:BAAALgAECgcJCgAAAA==.Hordehound:BAAALgADCgIJAgAAAA==.',
Hu='Huugg:BAAALgADCgMJAwAAAA==.',
Ja='Jakimozo:BAAALgAECgcJDAAAAA==.Jasminetea:BAACLgAFFH8JAAMUAAMJXhaOHQC0AANoDAAABAAyAGkMAAADADYA6gwAAAIAQwAUAAMJBxKOHQC0AANoDAAABAAyAGkMAAACADYA6gwAAAEAIQATAAIJ7hHNMwCSAAJpDAAAAQAYAOoMAAABAEMALgAECn8vAAQTAAkJYhywEgAdAgATAAgJxR6wEgAdAgAVAAcJ/wyAMwA9AQAUAAQJjglMTgCRAAAAAA==.',
Ju='Judgecutie:BAAALgAECgkJCQAAAA==.',
Ka='Kadesh:BAAALgADCgYJBgABLgAECgkJKQADAM4iAA==.Kayla:BAAALgAECgEJAwAAAA==.',
Ko='Kode:BAAALgAECgIJAgABLgAECgkJKQADAM4iAA==.',
Kr='Krizara:BAAALgAECgEJAQABLgAECgcJIAAKAI8VAA==.Kroth:BAABLgAECn9KAAIRAAkJpxMQKQD9AQloDAAACgA7AGkMAAAJACgAawwAAAkAPgBqDAAACQAvAGwMAAAJADgAbQwAAAcAHADqDAAACQBDAG4MAAAHADQAbwwAAAUAJgARAAkJpxMQKQD9AQloDAAACgA7AGkMAAAJACgAawwAAAkAPgBqDAAACQAvAGwMAAAJADgAbQwAAAcAHADqDAAACQBDAG4MAAAHADQAbwwAAAUAJgAAAA==.',
Ku='Kubfury:BAAALgAECgcJDgAAAA==.Kudi:BAAALgAECgYJDAAAAA==.',
['Kí']='Kíllian:BAABLgAECn8lAAIXAAkJ/yH0EAC7AgloDAAABQBVAGkMAAAFAFMAawwAAAUAXABqDAAAAgArAGwMAAAFAFkAbQwAAAQAXwDqDAAABgBeAG4MAAADAD0AbwwAAAIAXAAXAAkJ/yH0EAC7AgloDAAABQBVAGkMAAAFAFMAawwAAAUAXABqDAAAAgArAGwMAAAFAFkAbQwAAAQAXwDqDAAABgBeAG4MAAADAD0AbwwAAAIAXAAAAA==.Kíran:BAAALgAECgEJAwAAAA==.',
La='Labatblue:BAAALgADCgEJAQAAAA==.Lacey:BAAALgAECgYJBgAAAA==.Lavitz:BAAALgAECgYJCgAAAA==.',
Li='Lily:BAAALgAECgMJAwAAAA==.',
Lo='Loris:BAAALgAECgcJBgABLgAFFAkJCwAFAOIdAA==.',
Lu='Lunaci:BAABLgAECn8qAAMQAAkJDxxVDACKAgloDAAABgBAAGkMAAAFADgAawwAAAUAUABqDAAABABJAGwMAAAGAE4AbQwAAAQARQDqDAAABgBZAG4MAAAEAE4AbwwAAAIAOgAQAAkJDxxVDACKAgloDAAABABAAGkMAAADADgAawwAAAMAUABqDAAAAgBJAGwMAAAEAE4AbQwAAAQARQDqDAAAAwBZAG4MAAAEAE4AbwwAAAIAOgAYAAYJmQ6NEADzAAZoDAAAAgAjAGkMAAACACUAawwAAAIANQBqDAAAAgAeAGwMAAACABMA6gwAAAMAKQAAAA==.Lunylu:BAAALgADCgUJBQAAAA==.',
Ma='Magicmagicin:BAAALgAECgMJAgAAAA==.Magnusson:BAABLgAECn8uAAIKAAkJWR3vBgCIAgloDAAABwBaAGkMAAAGAFAAawwAAAYAUwBqDAAABABLAGwMAAAGAFkAbQwAAAQALwDqDAAABwBPAG4MAAAEACgAbwwAAAIAWAAKAAkJWR3vBgCIAgloDAAABwBaAGkMAAAGAFAAawwAAAYAUwBqDAAABABLAGwMAAAGAFkAbQwAAAQALwDqDAAABwBPAG4MAAAEACgAbwwAAAIAWAAAAA==.Mandrah:BAAALgAECgYJCQAAAA==.Masutado:BAABLgAECn8uAAIPAAkJvBzBGwCqAgloDAAABwBSAGkMAAAGAEgAawwAAAYAUABqDAAABABUAGwMAAAGAF4AbQwAAAQAUADqDAAABwBSAG4MAAAEAEQAbwwAAAIAGwAPAAkJvBzBGwCqAgloDAAABwBSAGkMAAAGAEgAawwAAAYAUABqDAAABABUAGwMAAAGAF4AbQwAAAQAUADqDAAABwBSAG4MAAAEAEQAbwwAAAIAGwAAAA==.Maven:BAAALgAECgQJBAAAAA==.Mayelle:BAAALgADCgkJEAAAAA==.Mayernnaise:BAAALgAECgUJBgAAAA==.Maypah:BAAALgADCgIJAgAAAA==.Mayvoker:BAAALgADCgEJAQAAAA==.',
Me='Metier:BAAALgAECgUJCgABLgAFFAQJFAAKAIUlAA==.',
Mi='Miao:BAAALgAECgYJBgAAAA==.Mirror:BAAALgAFFAQJAQABLgAFFAkJCwAFAOIdAA==.Misfortune:BAAALgAECggJDgABLgAFFAMJCAALAGAgAA==.Mitsy:BAABLgAECn8mAAIVAAgJ+RSAHgDEAQhoDAAABgA9AGkMAAAFADMAawwAAAUANgBqDAAABQA+AGwMAAAFAD0AbQwAAAIAHQDqDAAABgBEAG4MAAAEAC8AFQAICfkUgB4AxAEIaAwAAAYAPQBpDAAABQAzAGsMAAAFADYAagwAAAUAPgBsDAAABQA9AG0MAAACAB0A6gwAAAYARABuDAAABAAvAAAA.',
Mo='Money:BAABLgAECn8jAAMLAAgJGCGfIACpAghoDAAABwBgAGkMAAAGAGIAawwAAAcAWQBqDAAABABiAGwMAAAEAFIAbQwAAAIAKwDqDAAABABfAG4MAAABAFQACwAHCRYhnyAAqQIHaAwAAAcAYABpDAAABgBiAGsMAAAHAFkAagwAAAQAYgBsDAAABABSAG0MAAABACsA6gwAAAQAXwAZAAIJcAfjcgBbAAJtDAAAAQAUAG4MAAABABEAAAA=.Montipython:BAABLgAECn8WAAMaAAkJ7RRiGQA8AQloDAAABABcAGkMAAAEAEsAawwAAAQAPwBqDAAAAwBGAGwMAAACAC8AbQwAAAEAGADqDAAAAgBBAG4MAAABACQAbwwAAAEAFwAaAAUJBh1iGQA8AQVoDAAABABcAGkMAAAEAEsAawwAAAQAPwBqDAAAAQBGAOoMAAABAEEACwAGCWcNsr0A/AAGagwAAAIAQgBsDAAAAgAvAG0MAAABABgA6gwAAAEAKABuDAAAAQAkAG8MAAABABcAAAA=.Moons:BAACLgAFFH8XAAMMAAcJQRKmAgDsAQdoDAAABQBVAGkMAAAGADIAawwAAAQANQBqDAAAAgAgAGwMAAABACAAbQwAAAEAEQDqDAAABAAoAAwABwlBEqYCAOwBB2gMAAAFAFUAaQwAAAYAMgBrDAAABAA1AGoMAAACACAAbAwAAAEAIABtDAAAAQARAOoMAAADACgAFwABCfEB7JcAOwAB6gwAAAEABAAuAAQKf1MAAgwACQmPI3QCABgDAAwACQmPI3QCABgDAAAA.Mothman:BAAALgADCgUJBAAAAA==.Moussebreath:BAACLgAFFH8IAAITAAYJwQYsIwANAQZoDAAAAQAoAGkMAAABAAkAawwAAAEABQBsDAAAAgARAG0MAAABAAgA6gwAAAIAFgATAAYJwQYsIwANAQZoDAAAAQAoAGkMAAABAAkAawwAAAEABQBsDAAAAgARAG0MAAABAAgA6gwAAAIAFgAuAAQKfxgAAhMABwmrH1UOAFUCABMABwmrH1UOAFUCAAAA.',
Mu='Mudpie:BAABLgAECn8aAAIbAAkJAx/FCgAhAgloDAAABABgAGkMAAAFAFQAawwAAAUAXQBqDAAAAgBGAGwMAAADAEsAbQwAAAEATADqDAAAAwBHAG4MAAABAEEAbwwAAAIARgAbAAkJAx/FCgAhAgloDAAABABgAGkMAAAFAFQAawwAAAUAXQBqDAAAAgBGAGwMAAADAEsAbQwAAAEATADqDAAAAwBHAG4MAAABAEEAbwwAAAIARgABLgAFFAMJBQANAGATAA==.Munco:BAACLgAFFH8FAAIcAAQJVhsBDAAvAQRoDAAAAQBBAGkMAAABAEQAawwAAAEAUwDqDAAAAgA+ABwABAlWGwEMAC8BBGgMAAABAEEAaQwAAAEARABrDAAAAQBTAOoMAAACAD4ALgAECn89AAMcAAkJ4yPIAgAkAwAcAAkJ4yPIAgAkAwACAAEJTBg+8gBHAAAAAA==.Muncola:BAAALgAECgMJAwABLgAFFAQJBQAcAFYbAA==.Muncoli:BAAALgAECgMJBAABLgAFFAQJBQAcAFYbAA==.Muncolito:BAAALgADCgEJAQABLgAFFAQJBQAcAFYbAA==.Mungus:BAAALgAECgQJCQAAAA==.Mutakor:BAAALgAECgEJAQABLgAFFAgJPAAKANEjAA==.',
My='Mythhleremix:BAAALgADCgUJBgABLgAFFAQJFAAKAIUlAA==.',
Ne='Nedd:BAAALgADCggJCAABLgAECgkJKQADAM4iAA==.Nellie:BAABLgAECn8gAAMSAAkJJg4OJACXAQloDAAABQAfAGkMAAAFABcAawwAAAUAKABqDAAAAwApAGwMAAAEADAAbQwAAAIAJQDqDAAABQA0AG4MAAACAA8AbwwAAAEAKAASAAkJJg4OJACXAQloDAAAAwAfAGkMAAADABcAawwAAAMAKABqDAAAAwApAGwMAAAEADAAbQwAAAIAJQDqDAAABAA0AG4MAAACAA8AbwwAAAEAKAARAAQJlQHMsABkAARoDAAAAgADAGkMAAACAAQAawwAAAIABADqDAAAAQADAAAA.Newtree:BAAALgAFFAcJBAABLgAFFAkJCwAFAOIdAA==.',
No='Notker:BAABLgAECn8uAAIUAAkJ7COJAgBtAwloDAAABwBiAGkMAAAGAF0AawwAAAYAYQBqDAAABABeAGwMAAAGAGAAbQwAAAQAWADqDAAABwBhAG4MAAAEAFEAbwwAAAIATwAUAAkJ7COJAgBtAwloDAAABwBiAGkMAAAGAF0AawwAAAYAYQBqDAAABABeAGwMAAAGAGAAbQwAAAQAWADqDAAABwBhAG4MAAAEAFEAbwwAAAIATwAAAA==.',
Ny='Nynaa:BAAALgAECgEJAQABLgAECgkJKQADAM4iAA==.',
Or='Orcwarr:BAABLgAECn8uAAQKAAkJ1RyGBwB5AgloDAAACABXAGkMAAAHAFoAawwAAAcAVgBqDAAABgBPAGwMAAAGAEIAbQwAAAIAQgDqDAAABgBFAG4MAAADADMAbwwAAAEARwAKAAkJ1RyGBwB5AgloDAAABgBXAGkMAAAGAFoAawwAAAYAVgBqDAAABgBPAGwMAAAGAEIAbQwAAAIAQgDqDAAABQBFAG4MAAADADMAbwwAAAEARwABAAMJlAl4jwCAAANoDAAAAgAbAGkMAAABAAEAawwAAAEAKwANAAEJPQsKQwAzAAHqDAAAAQAcAAAA.',
Pa='Panders:BAABLgAFFH8KAAILAAQJ+AW1UQD3AARoDAAAAwANAGkMAAADAB8AawwAAAEACQDqDAAAAwAGAAsABAn4BbVRAPcABGgMAAADAA0AaQwAAAMAHwBrDAAAAQAJAOoMAAADAAYAAAA=.Patadita:BAAALgAECgYJDgAAAA==.',
Pe='Pecanpie:BAABLgAFFH8FAAQNAAMJYBNyKQCZAANoDAAAAgAsAGkMAAACADYA6gwAAAEAMgANAAIJQBNyKQCZAAJoDAAAAQAsAGkMAAABADYAAQACCSAN/TwAkQACaAwAAAEAKgBpDAAAAQAYAAoAAQmhEw8oADsAAeoMAAABADIAAAA=.Penne:BAAALgADCgcJDAAAAA==.',
Pi='Pinkpony:BAAALgAFFAUJBAABLgAFFAkJCwAFAOIdAA==.Pipsi:BAAALgAECgEJAQABLgAFFAQJBQAcAFYbAA==.',
Pk='Pk:BAAALgAECgUJBQABLgAFFAQJCAADAJUZAA==.',
Pr='Pryor:BAAALgAECgUJBQABLgAECgkJKQADAM4iAA==.',
Qu='Quiverinpalm:BAABLgAECn8VAAIGAAgJfA8IKABlAQhoDAAABQA9AGkMAAAEAB4AawwAAAMAIwBqDAAAAgAcAGwMAAACACYAbQwAAAEAEwDqDAAAAwArAG4MAAABADAABgAICXwPCCgAZQEIaAwAAAUAPQBpDAAABAAeAGsMAAADACMAagwAAAIAHABsDAAAAgAmAG0MAAABABMA6gwAAAMAKwBuDAAAAQAwAAAA.',
Ra='Rageoverrun:BAAALgADCgYJCgAAAA==.',
Re='Remiwog:BAAALgADCggJCgAAAA==.Rennik:BAACLgAFFH8UAAQJAAQJaCNeCAD6AARoDAAABwBdAGkMAAAGAFwAawwAAAIAWADqDAAABQBYAAkAAwlrHF4IAPoAA2gMAAACAEkAaQwAAAIAOABrDAAAAgBYAB0AAgmQI8FuAM8AAmgMAAAFAF0A6gwAAAUAWAAeAAEJ8CMAFgBYAAFpDAAABABcAC4ABAp/OgAEHQAJCQUkzSQAQwIAHQAHCaMezSQAQwIACQAFCUojWQ4A4wEAHgADCV0kXx4AsgAAAAA=.Rentiak:BAAALgAECgYJEwAAAA==.',
Ru='Rue:BAAALgAECgYJCwAAAA==.',
Sa='Saffy:BAAALgADCgYJBwAAAA==.',
Sc='Scorevival:BAAALgAECgEJAQAAAA==.Scorewin:BAEBLgAECn8hAAIfAAkJCiTeAQD1AgloDAAABQBeAGkMAAAEAFsAawwAAAQAYQBqDAAABABUAGwMAAADAGAAbQwAAAIASgDqDAAABgBhAG4MAAAEAF4AbwwAAAEAWwAfAAkJCiTeAQD1AgloDAAABQBeAGkMAAAEAFsAawwAAAQAYQBqDAAABABUAGwMAAADAGAAbQwAAAIASgDqDAAABgBhAG4MAAAEAF4AbwwAAAEAWwAAAA==.',
Se='Serenity:BAAALgAECgEJAwABLgAFFAUJCgACAGMaAA==.Serraku:BAAALgAECgEJAQAAAA==.',
Sh='Shadowfern:BAEALgAECgMJBgAAAA==.Shalniar:BAAALgADCgYJBgABLgAFFAYJGAAgAMMfAA==.Shioh:BAAALgADCgUJBQAAAA==.Shocky:BAAALgAECgEJAQAAAA==.',
Si='Sienda:BAAALgAECgUJBQAAAA==.Sinappi:BAAALgAECgEJAwAAAA==.Siñ:BAABLgAECn8jAAIhAAkJTQhhCgCBAQloDAAABQAbAGkMAAAFABwAawwAAAUAFgBqDAAABAARAGwMAAAFABAAbQwAAAMADwDqDAAAAgAXAG4MAAAEABIAbwwAAAIAEAAhAAkJTQhhCgCBAQloDAAABQAbAGkMAAAFABwAawwAAAUAFgBqDAAABAARAGwMAAAFABAAbQwAAAMADwDqDAAAAgAXAG4MAAAEABIAbwwAAAIAEAAAAA==.',
Sk='Skaya:BAAALgADCgIJAgAAAA==.Skeetshootah:BAABLgAECn8tAAIXAAkJ2hfyKgAiAgloDAAABwBKAGkMAAAGAE0AawwAAAYATwBqDAAABAAvAGwMAAAFADkAbQwAAAQAOADqDAAABwAyAG4MAAAEAC0AbwwAAAIALgAXAAkJ2hfyKgAiAgloDAAABwBKAGkMAAAGAE0AawwAAAYATwBqDAAABAAvAGwMAAAFADkAbQwAAAQAOADqDAAABwAyAG4MAAAEAC0AbwwAAAIALgAAAA==.Skùnkstomper:BAAALgADCgEJAQAAAA==.Skúnkstomper:BAAALgAECgEJAQABLgAECgEJAgAHAAAAAA==.Skûnkstomper:BAAALgADCgMJAQABLgAECgEJAgAHAAAAAA==.',
Sl='Slowbadon:BAABLgAECn8YAAIZAAkJixP8MQB/AQloDAAABAA/AGkMAAAEAEcAawwAAAQATABqDAAAAgAdAGwMAAACACkAbQwAAAIANgDqDAAAAwAyAG4MAAACAC4AbwwAAAEAEAAZAAkJixP8MQB/AQloDAAABAA/AGkMAAAEAEcAawwAAAQATABqDAAAAgAdAGwMAAACACkAbQwAAAIANgDqDAAAAwAyAG4MAAACAC4AbwwAAAEAEAAAAA==.',
Sp='Spáceballs:BAAALgAECgEJAgAAAA==.',
St='Stabpokestab:BAAALgADCgcJDQAAAA==.Stay:BAAALgAECgcJBgABLgAFFAkJCwAFAOIdAA==.Streetlight:BAABLgAECn8VAAIMAAkJYQ+UEwADAgloDAAAAwAiAGkMAAABACYAawwAAAEALwBqDAAAAQAwAGwMAAAEAEYAbQwAAAMANgDqDAAABAAgAG4MAAADABMAbwwAAAEAEAAMAAkJYQ+UEwADAgloDAAAAwAiAGkMAAABACYAawwAAAEALwBqDAAAAQAwAGwMAAAEAEYAbQwAAAMANgDqDAAABAAgAG4MAAADABMAbwwAAAEAEAABLgABCgEJAQAHAAAAAA==.Streetlights:BAAALgAECgYJDgABLgABCgEJAQAHAAAAAA==.Streets:BAAALgAECggJEQABLgABCgEJAQAHAAAAAA==.',
Ta='Tank:BAACLgAFFH8UAAIKAAQJhSX9BgCqAQRoDAAABwBiAGkMAAAGAFwAawwAAAIAXwDqDAAABQBhAAoABAmFJf0GAKoBBGgMAAAHAGIAaQwAAAYAXABrDAAAAgBfAOoMAAAFAGEALgAECn8yAAIKAAkJwyWvAgA8AwAKAAkJwyWvAgA8AwAAAA==.',
Te='Teafayd:BAABLgAECn8YAAMeAAYJhQsrHADEAAZoDAAABAAcAGkMAAAGACQAawwAAAUAJABqDAAAAwAcAGwMAAACABMA6gwAAAQAGwAeAAYJCAsrHADEAAZoDAAAAgAVAGkMAAAGACQAawwAAAQAJABqDAAAAwAcAGwMAAACABMA6gwAAAQAGwAJAAIJMArEMABPAAJoDAAAAgAcAGsMAAABABgAAAA=.',
Th='Thisboss:BAAALgAECgYJCAAAAA==.Thunderdot:BAABLgAECn8yAAIVAAkJbh6VCwCKAgloDAAABwBeAGkMAAAHAFoAawwAAAgAXQBqDAAABgBDAGwMAAAFAFUAbQwAAAIAKADqDAAACgBVAG4MAAAEADkAbwwAAAEASQAVAAkJbh6VCwCKAgloDAAABwBeAGkMAAAHAFoAawwAAAgAXQBqDAAABgBDAGwMAAAFAFUAbQwAAAIAKADqDAAACgBVAG4MAAAEADkAbwwAAAEASQAAAA==.Thunderlok:BAAALgADCgEJAgAAAA==.',
Ti='Tilvayne:BAACLgAFFH8WAAIDAAUJZBe6TgA+AQVoDAAABgBPAGkMAAAFAEEAawwAAAQAMgBqDAAAAwAqAOoMAAAEACwAAwAFCWQXuk4APgEFaAwAAAYATwBpDAAABQBBAGsMAAAEADIAagwAAAMAKgDqDAAABAAsAC4ABAp/TQACAwAJCc4imA0A9AIAAwAJCc4imA0A9AIAAAA=.',
To='Tomayter:BAABLgAECn8tAAIUAAkJzh9QBwDrAgloDAAABgBdAGkMAAAGAF4AawwAAAYAWABqDAAABAA2AGwMAAAGAE4AbQwAAAQAWwDqDAAABwBfAG4MAAAEAFcAbwwAAAIAMgAUAAkJzh9QBwDrAgloDAAABgBdAGkMAAAGAF4AawwAAAYAWABqDAAABAA2AGwMAAAGAE4AbQwAAAQAWwDqDAAABwBfAG4MAAAEAFcAbwwAAAIAMgAAAA==.',
Tr='Trap:BAAALgAFFAEJAgABLgAFFAUJCgACAGMaAA==.Trinitee:BAAALgADCgYJEAAAAA==.Trisriane:BAAALgAECgMJBgABLgAECgkJHQALAG4aAA==.Trist:BAABLgAECn8dAAILAAkJbhpzPgArAgloDAAABQBYAGkMAAAEAFsAawwAAAQASQBqDAAABABMAGwMAAADAFUAbQwAAAEAFADqDAAABQBQAG4MAAACAB0AbwwAAAEARwALAAkJbhpzPgArAgloDAAABQBYAGkMAAAEAFsAawwAAAQASQBqDAAABABMAGwMAAADAFUAbQwAAAEAFADqDAAABQBQAG4MAAACAB0AbwwAAAEARwAAAA==.',
Tu='Turbogoat:BAABLgAECn8lAAIDAAgJuh4GLQCFAghoDAAABgBeAGkMAAAHAFwAawwAAAYAWwBqDAAABABaAGwMAAAEAFQAbQwAAAMAPQDqDAAABgBTAG4MAAABACoAAwAICboeBi0AhQIIaAwAAAYAXgBpDAAABwBcAGsMAAAGAFsAagwAAAQAWgBsDAAABABUAG0MAAADAD0A6gwAAAYAUwBuDAAAAQAqAAAA.Turok:BAAALgAECgEJAgABLgAFFAMJBQAMAFMYAA==.',
Tw='Twaave:BAABLgAECn8yAAIPAAkJjSL9DAAJAwloDAAABwBgAGkMAAAGAGAAawwAAAkAYQBqDAAABgBeAGwMAAAFAFsAbQwAAAMAQgDqDAAACQBfAG4MAAAEAEcAbwwAAAEAWgAPAAkJjSL9DAAJAwloDAAABwBgAGkMAAAGAGAAawwAAAkAYQBqDAAABgBeAGwMAAAFAFsAbQwAAAMAQgDqDAAACQBfAG4MAAAEAEcAbwwAAAEAWgAAAA==.',
['Tÿ']='Tÿ:BAAALgAECgQJBQAAAA==.',
Va='Vaz:BAAALgAECgYJCwAAAA==.Vazp:BAAALgAECgUJBQABLgAECgYJCwAHAAAAAA==.',
Ve='Vendmachin:BAAALgADCgEJAQAAAA==.Verdessa:BAAALgAECgQJCAAAAA==.',
Vn='Vnav:BAAALgAECgcJCAAAAA==.',
Wa='Waltz:BAAALgADCgEJAQAAAA==.',
Xe='Xevic:BAAALgAECgIJAgABLgAECgkJKQADAM4iAA==.',
Xi='Xins:BAAALgAECgQJBAAAAA==.',
Yi='Yikezvelobtw:BAAALgAECgIJAwAAAA==.',
Za='Zapa:BAAALgAECgEJAQAAAA==.',
Ze='Zennah:BAAALgADCgQJBAAAAA==.Zerene:BAABLgAECn8uAAMJAAkJfhpTAwBTAgloDAAABwBAAGkMAAAGAEgAawwAAAYAUABqDAAABAA6AGwMAAAGAEUAbQwAAAQAOADqDAAABwA7AG4MAAAEAEQAbwwAAAIARwAJAAkJfhpTAwBTAgloDAAABABAAGkMAAAFAEgAawwAAAUAUABqDAAABAA6AGwMAAAFAEUAbQwAAAMAOADqDAAABQA7AG4MAAADAEQAbwwAAAIARwAdAAcJAAbGkwAOAQdoDAAAAwAUAGkMAAABAAYAawwAAAEAGgBsDAAAAQAKAG0MAAABABUA6gwAAAIADgBuDAAAAQAGAAAA.',
['Æs']='Æsc:BAABLgAECn8uAAIWAAkJUBdOFAC9AQloDAAABwAxAGkMAAAGAFQAawwAAAYASwBqDAAABABBAGwMAAAGAEsAbQwAAAQALgDqDAAABwA+AG4MAAAEACgAbwwAAAIALAAWAAkJUBdOFAC9AQloDAAABwAxAGkMAAAGAFQAawwAAAYASwBqDAAABABBAGwMAAAGAEsAbQwAAAQALgDqDAAABwA+AG4MAAAEACgAbwwAAAIALAAAAA==.',
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
