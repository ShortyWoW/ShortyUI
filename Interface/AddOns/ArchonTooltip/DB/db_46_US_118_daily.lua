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
local provider = {region='US',realm='Haomarush',name='US',type='daily',zone=46,date='2026-06-05',data={Ad='Adderall:BAAALgAECggJDgAAAA==.',
Ae='Aethrion:BAAALgAECgMJBwAAAA==.',
Al='Alexya:BAAALgADCgIJAgAAAA==.All:BAAALgADCgEJAQAAAA==.Alphahawk:BAACLgAFFH8OAAIBAAQJwgggJgAOAQRoDAAABAAQAGkMAAAEABgAawwAAAIAEgDqDAAABAAdAAEABAnCCCAmAA4BBGgMAAAEABAAaQwAAAQAGABrDAAAAgASAOoMAAAEAB0ALgAECn9CAAIBAAkJBBtCFgA1AgABAAkJBBtCFgA1AgAAAA==.',
Ap='Apocalipsis:BAAALgAECgMJAwAAAA==.',
Aq='Aquilis:BAABLgAECn8TAAICAAkJAhigVgCeAQloDAAAAwBMAGkMAAADAFQAawwAAAMATABqDAAAAQArAGwMAAADADcAbQwAAAIANwDqDAAAAQAvAG4MAAACAEEAbwwAAAEAHwACAAkJAhigVgCeAQloDAAAAwBMAGkMAAADAFQAawwAAAMATABqDAAAAQArAGwMAAADADcAbQwAAAIANwDqDAAAAQAvAG4MAAACAEEAbwwAAAEAHwAAAA==.',
Ar='Aralaria:BAAALgAECgUJBQABLgAFFAMJCAADAKYbAA==.Aramis:BAAALgAECggJEwABLgAFFAMJCAADAKYbAA==.Aranumi:BAAALgAECgQJBAABLgAFFAMJCAADAKYbAA==.Arathrok:BAACLgAFFH8IAAIDAAMJphvCfQD2AANoDAAABABMAGkMAAADAFgA6gwAAAEALwADAAMJphvCfQD2AANoDAAABABMAGkMAAADAFgA6gwAAAEALwAuAAQKfx4AAgMACQmLILtOAM4BAAMACQmLILtOAM4BAAAA.',
As='Asha:BAACLgAFFH8YAAQEAAUJ/xZaEQAmAQVoDAAABQBHAGkMAAAFADEAawwAAAUATgBqDAAABAA7AOoMAAAFACQABAAFCf8WWhEAJgEFaAwAAAMARwBpDAAAAwAxAGsMAAADAE4AagwAAAIAOwDqDAAAAwAkAAUABQkADbAiACQBBWgMAAABAEkAaQwAAAEAKABrDAAAAQALAGoMAAABABsA6gwAAAEADAAGAAUJ7QUmLwDfAAVoDAAAAQAWAGkMAAABAA0AawwAAAEADwBqDAAAAQAUAOoMAAABAAgALgAECn8cAAQEAAgJyyDLGwDDAQAEAAgJyyDLGwDDAQAFAAQJ0BzeQgBEAQAGAAUJxhk1NgAcAQAAAA==.Asmoday:BAABLgAECn8pAAIDAAkJziI3DwDpAgloDAAABgBUAGkMAAAGAF8AawwAAAYAWgBqDAAAAwBUAGwMAAAFAFoAbQwAAAMAXgDqDAAABwBYAG4MAAAEAFMAbwwAAAEAVgADAAkJziI3DwDpAgloDAAABgBUAGkMAAAGAF8AawwAAAYAWgBqDAAAAwBUAGwMAAAFAFoAbQwAAAMAXgDqDAAABwBYAG4MAAAEAFMAbwwAAAEAVgAAAA==.Astra:BAAALgAECgEJAQABLgAFFAEJAQAHAAAAAA==.Asunawa:BAAALgADCgUJBQAAAA==.',
Au='Aundarr:BAAALgAECgQJBAABLgAECgkJKQADAM4iAA==.Autoshift:BAABLgAECn8WAAIIAAgJ7woNGgAoAQhoDAAABAAeAGkMAAAEACUAawwAAAQAKwBqDAAAAwAlAGwMAAACACAAbQwAAAEAFgDqDAAAAgAQAG4MAAACAAwACAAICe8KDRoAKAEIaAwAAAQAHgBpDAAABAAlAGsMAAAEACsAagwAAAMAJQBsDAAAAgAgAG0MAAABABYA6gwAAAIAEABuDAAAAgAMAAAA.Auun:BAAALgAECgYJBwABLgAECgkJKQADAM4iAA==.',
Ba='Bartre:BAAALgAECgQJCAABLgAFFAQJFAAJAGgjAA==.Bat:BAABLgAECn8eAAIIAAkJZCWhAgDvAgloDAAABQBjAGkMAAAFAF4AawwAAAMAYgBqDAAABABiAGwMAAAEAF4AbQwAAAMAYQDqDAAAAwBeAG4MAAACAFgAbwwAAAEAYwAIAAkJZCWhAgDvAgloDAAABQBjAGkMAAAFAF4AawwAAAMAYgBqDAAABABiAGwMAAAEAF4AbQwAAAMAYQDqDAAAAwBeAG4MAAACAFgAbwwAAAEAYwAAAA==.',
Be='Benedictine:BAAALgAECgEJBQAAAA==.',
Bi='Bigcleavage:BAABLgAECn8hAAIKAAkJAxu8DQADAgloDAAABwA+AGkMAAAFAEsAawwAAAUAWQBqDAAABABRAGwMAAAEAFEAbQwAAAIAKADqDAAAAwA4AG4MAAACAEkAbwwAAAEASgAKAAkJAxu8DQADAgloDAAABwA+AGkMAAAFAEsAawwAAAUAWQBqDAAABABRAGwMAAAEAFEAbQwAAAIAKADqDAAAAwA4AG4MAAACAEkAbwwAAAEASgAAAA==.Bilbert:BAAALgAECgMJAwABLgAFFAMJCAALAGAgAA==.',
Bl='Blue:BAAALgAECgYJBgABLgAFFAcJFwAMAEESAA==.Blueberrypie:BAAALgAFFAEJAQABLgAFFAMJBQANAGATAA==.',
Bo='Boomster:BAABLgAFFH8KAAIOAAYJ5h+pBgAtAgZoDAAAAgA+AGkMAAACAEoAawwAAAEASwBqDAAAAQBRAGwMAAABAGEA6gwAAAMAYgAOAAYJ5h+pBgAtAgZoDAAAAgA+AGkMAAACAEoAawwAAAEASwBqDAAAAQBRAGwMAAABAGEA6gwAAAMAYgABLgAFFAkJCwAFAOIdAA==.',
Br='Bridgetpower:BAAALgADCgIJAgAAAA==.',
Ca='Calixta:BAACLgAFFH8IAAILAAMJYCB2SgAJAQNoDAAABABSAGkMAAADAEYA6gwAAAEAXwALAAMJYCB2SgAJAQNoDAAABABSAGkMAAADAEYA6gwAAAEAXwAuAAQKfyIAAgsACQnBIyYVALoCAAsACQnBIyYVALoCAAAA.Carbshock:BAAALgADCgYJCgAAAA==.',
Ce='Ceroah:BAAALgAECgYJCwAAAA==.',
Ch='Cherrypie:BAAALgAFFAEJAQABLgAFFAMJBQANAGATAA==.',
Co='Coodown:BAAALgAECgYJCAAAAA==.',
Cr='Cranberrypie:BAAALgAECgQJBQABLgAFFAMJBQANAGATAA==.Criscomaster:BAAALgADCgYJEQAAAA==.',
Cy='Cylla:BAACLgAFFH8TAAIPAAQJlAxGYQAbAQRoDAAABgAuAGkMAAAGABIAawwAAAIADQDqDAAABQAxAA8ABAmUDEZhABsBBGgMAAAGAC4AaQwAAAYAEgBrDAAAAgANAOoMAAAFADEALgAECn86AAIPAAkJfBxALwBUAgAPAAkJfBxALwBUAgAAAA==.',
De='Delacour:BAAALgAECgQJBAABLgAECgkJKQADAM4iAA==.',
Di='Dilfdormu:BAABLgAECn8gAAMOAAYJwBAlGABFAQZoDAAABgA7AGkMAAAHAEcAawwAAAcAKwBqDAAABQASAGwMAAACAB0A6gwAAAUAIgAOAAYJwBAlGABFAQZoDAAABgA7AGkMAAAGAEcAawwAAAYAKwBqDAAABQASAGwMAAACAB0A6gwAAAUAIgAQAAIJ1QIsiQA2AAJpDAAAAQAGAGsMAAABAAcAAAA=.',
Dk='Dkvaluemenu:BAAALgAECgQJBAAAAA==.',
Do='Donkey:BAAALgADCgIJAgAAAA==.Doson:BAACLgAFFH8NAAIRAAQJWRI4KgAIAQRoDAAABgA7AGkMAAAEACEAawwAAAEAGADqDAAAAgBFABEABAlZEjgqAAgBBGgMAAAGADsAaQwAAAQAIQBrDAAAAQAYAOoMAAACAEUALgAECn85AAMRAAkJPh/iCAAiAwARAAkJPh/iCAAiAwASAAEJ2iTyaABqAAAAAA==.',
Dr='Dragonmabals:BAAALgAECgQJBAAAAA==.Dratak:BAACLgAFFH9AAAIKAAgJ0SO2AADRAghoDAAACwBjAGkMAAAKAGEAawwAAAoAXgBqDAAACABfAGwMAAAGAGEAbQwAAAUASADqDAAACwBhAG4MAAADAFMACgAICdEjtgAA0QIIaAwAAAsAYwBpDAAACgBhAGsMAAAKAF4AagwAAAgAXwBsDAAABgBhAG0MAAAFAEgA6gwAAAsAYQBuDAAAAwBTAC4ABAp/cQACCgAJCcomFwAAlQMACgAJCcomFwAAlQMAAAA=.Dread:BAABLgAECn8bAAIEAAgJjBrAEAB2AghoDAAABQBVAGkMAAAEAFwAawwAAAQAWQBqDAAABABGAGwMAAADAFQAbQwAAAIAFgDqDAAABABEAG4MAAABAB8ABAAICYwawBAAdgIIaAwAAAUAVQBpDAAABABcAGsMAAAEAFkAagwAAAQARgBsDAAAAwBUAG0MAAACABYA6gwAAAQARABuDAAAAQAfAAAA.Dreadfang:BAAALgADCgcJDQAAAA==.Dred:BAAALgAECgMJBwAAAA==.Drizbul:BAAALgAECgEJBAABLgAFFAgJQAAKANEjAA==.',
Ea='Earthswrath:BAAALgAECgUJDgAAAA==.',
El='Elitzai:BAAALgAECgIJAwAAAA==.Elusivemonk:BAAALgAECgEJAQAAAA==.',
Em='Emeralda:BAAALgADCgcJDQAAAA==.',
Ev='Evalueate:BAAALgAECgQJBAAAAA==.',
Fl='Fluf:BAAALgADCgcJDAAAAA==.',
Fr='Frocknor:BAABLgAECn8gAAMKAAcJjxU6IAAiAQdoDAAABgAjAGkMAAAGADMAawwAAAUALQBqDAAAAwBHAGwMAAAEAFEA6gwAAAcAOgBuDAAAAQA5AAEABglLFI8+AEEBBmgMAAAEACMAaQwAAAQALgBrDAAAAwAlAGoMAAACAEcAbAwAAAEAUQDqDAAABgA6AAoABwleEDogACIBB2gMAAACABUAaQwAAAIAMwBrDAAAAgAtAGoMAAABAEMAbAwAAAMAIwDqDAAAAQAnAG4MAAABADkAAAA=.',
Fu='Fuki:BAAALgAECgQJDAAAAA==.Furrymythh:BAAALgAECgQJBAABLgAFFAQJFAAKAIUlAA==.',
Fy='Fyrstureinn:BAAALgADCgIJAgAAAA==.',
Ga='Galumian:BAACLgAFFH8vAAITAAgJxSLSAAByAghoDAAACQBjAGkMAAAIAGIAawwAAAYAYQBqDAAABgBcAGwMAAAFAGAAbQwAAAIAMgDqDAAACgBZAG4MAAABAFcAEwAICcUi0gAAcgIIaAwAAAkAYwBpDAAACABiAGsMAAAGAGEAagwAAAYAXABsDAAABQBgAG0MAAACADIA6gwAAAoAWQBuDAAAAQBXAC4ABAp/QQAEEwAJCaUl9QAAzwMAEwAJCaUl9QAAzwMAFAAHCRIRQC8AhgEAFQACCdwhukYAyQAAAAA=.',
Ge='Geron:BAAALgAECgUJBQABLgAFFAMJCAALAGAgAA==.Geronimô:BAAALgAECgYJDAAAAA==.Gerønimo:BAAALgAECgEJAQAAAA==.',
Go='Goo:BAAALgAECgcJDAABLgAFFAYJFgAWACIWAA==.',
Gu='Gummies:BAAALgAECgEJAQAAAA==.Guy:BAAALgADCgcJBwAAAA==.',
Ha='Hamhock:BAAALgAECgQJDgAAAA==.Haradali:BAAALgAFFAQJBAAAAA==.Hawa:BAAALgADCgEJAQAAAA==.',
Hi='Highpantsman:BAAALgAECgcJCAAAAA==.',
Ho='Holydiah:BAABLgAECn8hAAILAAYJVQyBwwD2AAZoDAAABwAhAGkMAAAHABwAawwAAAcAHQBqDAAABgAzAGwMAAAFACkA6gwAAAEAGAALAAYJVQyBwwD2AAZoDAAABwAhAGkMAAAHABwAawwAAAcAHQBqDAAABgAzAGwMAAAFACkA6gwAAAEAGAAAAA==.Holypriest:BAAALgAECgcJCgAAAA==.Hoofwinkled:BAAALgAECgcJBwAAAA==.Hordehound:BAAALgADCgIJAgAAAA==.',
Hu='Huugg:BAAALgADCgMJAwAAAA==.',
Ja='Jakimozo:BAAALgAECgcJDAAAAA==.Jasminetea:BAACLgAFFH8JAAMUAAMJXhYIHwCpAANoDAAABAAyAGkMAAADADYA6gwAAAIAQwAUAAMJBxIIHwCpAANoDAAABAAyAGkMAAACADYA6gwAAAEAIQATAAIJ7hFtNQCOAAJpDAAAAQAYAOoMAAABAEMALgAECn8vAAQTAAkJYhywEgAdAgATAAgJxR6wEgAdAgAVAAcJ/wx1NAA8AQAUAAQJjglTTwCQAAAAAA==.',
Ju='Judgecutie:BAAALgAECgkJCQAAAA==.',
Ka='Kadesh:BAAALgADCgYJBgABLgAECgkJKQADAM4iAA==.Kayla:BAAALgAECgEJAwAAAA==.',
Ko='Kode:BAAALgAECgIJAgABLgAECgkJKQADAM4iAA==.',
Kr='Krizara:BAAALgAECgEJAQABLgAECgcJIAAKAI8VAA==.Kroth:BAABLgAECn9KAAIRAAkJpxOXKQD9AQloDAAACgA7AGkMAAAJACgAawwAAAkAPgBqDAAACQAvAGwMAAAJADgAbQwAAAcAHADqDAAACQBDAG4MAAAHADQAbwwAAAUAJgARAAkJpxOXKQD9AQloDAAACgA7AGkMAAAJACgAawwAAAkAPgBqDAAACQAvAGwMAAAJADgAbQwAAAcAHADqDAAACQBDAG4MAAAHADQAbwwAAAUAJgAAAA==.',
Ku='Kubfury:BAAALgAECgcJDgAAAA==.Kudi:BAAALgAECgYJDAAAAA==.',
['Kí']='Kíllian:BAABLgAECn8lAAIXAAkJ/yG9EQC4AgloDAAABQBVAGkMAAAFAFMAawwAAAUAXABqDAAAAgArAGwMAAAFAFkAbQwAAAQAXwDqDAAABgBeAG4MAAADAD0AbwwAAAIAXAAXAAkJ/yG9EQC4AgloDAAABQBVAGkMAAAFAFMAawwAAAUAXABqDAAAAgArAGwMAAAFAFkAbQwAAAQAXwDqDAAABgBeAG4MAAADAD0AbwwAAAIAXAAAAA==.Kíran:BAAALgAECgEJAwAAAA==.',
La='Labatblue:BAAALgADCgEJAQAAAA==.Lacey:BAAALgAECgYJBgAAAA==.Lavitz:BAAALgAECgYJCgAAAA==.',
Li='Lily:BAAALgAECgcJCgAAAA==.',
Lo='Loris:BAAALgAECgcJBgABLgAFFAkJCwAFAOIdAA==.',
Lu='Lunaci:BAABLgAECn8qAAMQAAkJDxyYDACJAgloDAAABgBAAGkMAAAFADgAawwAAAUAUABqDAAABABJAGwMAAAGAE4AbQwAAAQARQDqDAAABgBZAG4MAAAEAE4AbwwAAAIAOgAQAAkJDxyYDACJAgloDAAABABAAGkMAAADADgAawwAAAMAUABqDAAAAgBJAGwMAAAEAE4AbQwAAAQARQDqDAAAAwBZAG4MAAAEAE4AbwwAAAIAOgAYAAYJmQ7aEADwAAZoDAAAAgAjAGkMAAACACUAawwAAAIANQBqDAAAAgAeAGwMAAACABMA6gwAAAMAKQAAAA==.Lunylu:BAAALgADCgUJBQAAAA==.',
Ma='Magicmagicin:BAAALgAECgMJAgAAAA==.Magnusson:BAABLgAECn8uAAIKAAkJWR01BwCFAgloDAAABwBaAGkMAAAGAFAAawwAAAYAUwBqDAAABABLAGwMAAAGAFkAbQwAAAQALwDqDAAABwBPAG4MAAAEACgAbwwAAAIAWAAKAAkJWR01BwCFAgloDAAABwBaAGkMAAAGAFAAawwAAAYAUwBqDAAABABLAGwMAAAGAFkAbQwAAAQALwDqDAAABwBPAG4MAAAEACgAbwwAAAIAWAAAAA==.Mandrah:BAAALgAECgYJCQAAAA==.Masutado:BAABLgAECn8uAAIPAAkJvBxyHACpAgloDAAABwBSAGkMAAAGAEgAawwAAAYAUABqDAAABABUAGwMAAAGAF4AbQwAAAQAUADqDAAABwBSAG4MAAAEAEQAbwwAAAIAGwAPAAkJvBxyHACpAgloDAAABwBSAGkMAAAGAEgAawwAAAYAUABqDAAABABUAGwMAAAGAF4AbQwAAAQAUADqDAAABwBSAG4MAAAEAEQAbwwAAAIAGwAAAA==.Maven:BAAALgAECgQJBAAAAA==.Mayelle:BAAALgADCgkJEAAAAA==.Mayernnaise:BAAALgAECgUJBgAAAA==.Maypah:BAAALgADCgIJAgAAAA==.Mayvoker:BAAALgADCgEJAQAAAA==.',
Me='Metier:BAAALgAECgUJCgABLgAFFAQJFAAKAIUlAA==.',
Mi='Miao:BAAALgAECgYJBgAAAA==.Mirror:BAABLgAFFH8GAAIOAAUJbCUwBwAhAgVoDAAAAgBdAGkMAAABAF8AawwAAAEAYQBqDAAAAQBfAOoMAAABAGEADgAFCWwlMAcAIQIFaAwAAAIAXQBpDAAAAQBfAGsMAAABAGEAagwAAAEAXwDqDAAAAQBhAAEuAAUUCQkLAAUA4h0A.Misfortune:BAAALgAECggJDgABLgAFFAMJCAALAGAgAA==.Mitsy:BAABLgAECn8uAAIVAAgJIRZdHQDRAQhoDAAABwA9AGkMAAAGADUAawwAAAYAOQBqDAAABgA+AGwMAAAGAD0AbQwAAAMALQDqDAAABwBEAG4MAAAFAC8AFQAICSEWXR0A0QEIaAwAAAcAPQBpDAAABgA1AGsMAAAGADkAagwAAAYAPgBsDAAABgA9AG0MAAADAC0A6gwAAAcARABuDAAABQAvAAAA.',
Mo='Money:BAABLgAECn8jAAMLAAgJGCGfIACpAghoDAAABwBgAGkMAAAGAGIAawwAAAcAWQBqDAAABABiAGwMAAAEAFIAbQwAAAIAKwDqDAAABABfAG4MAAABAFQACwAHCRYhnyAAqQIHaAwAAAcAYABpDAAABgBiAGsMAAAHAFkAagwAAAQAYgBsDAAABABSAG0MAAABACsA6gwAAAQAXwAZAAIJcAf+cwBbAAJtDAAAAQAUAG4MAAABABEAAAA=.Montipython:BAABLgAECn8WAAMaAAkJ7RToGQA7AQloDAAABABcAGkMAAAEAEsAawwAAAQAPwBqDAAAAwBGAGwMAAACAC8AbQwAAAEAGADqDAAAAgBBAG4MAAABACQAbwwAAAEAFwAaAAUJBh3oGQA7AQVoDAAABABcAGkMAAAEAEsAawwAAAQAPwBqDAAAAQBGAOoMAAABAEEACwAGCWcNKr8A/AAGagwAAAIAQgBsDAAAAgAvAG0MAAABABgA6gwAAAEAKABuDAAAAQAkAG8MAAABABcAAAA=.Moons:BAACLgAFFH8XAAMMAAcJQRIjAwDcAQdoDAAABQBVAGkMAAAGADIAawwAAAQANQBqDAAAAgAgAGwMAAABACAAbQwAAAEAEQDqDAAABAAoAAwABwlBEiMDANwBB2gMAAAFAFUAaQwAAAYAMgBrDAAABAA1AGoMAAACACAAbAwAAAEAIABtDAAAAQARAOoMAAADACgAFwABCfEBgZwAOwAB6gwAAAEABAAuAAQKf1QAAgwACQmXIycCACgDAAwACQmXIycCACgDAAAA.Mothman:BAAALgADCgUJBAAAAA==.Moussebreath:BAACLgAFFH8JAAITAAYJVgiQIgAUAQZoDAAAAQAoAGkMAAABAAkAawwAAAEABQBsDAAAAgARAG0MAAABAAgA6gwAAAMALgATAAYJVgiQIgAUAQZoDAAAAQAoAGkMAAABAAkAawwAAAEABQBsDAAAAgARAG0MAAABAAgA6gwAAAMALgAuAAQKfxgAAhMABwmrH1UOAFUCABMABwmrH1UOAFUCAAAA.',
Mu='Mudpie:BAABLgAECn8aAAIbAAkJAx8CCwAfAgloDAAABABgAGkMAAAFAFQAawwAAAUAXQBqDAAAAgBGAGwMAAADAEsAbQwAAAEATADqDAAAAwBHAG4MAAABAEEAbwwAAAIARgAbAAkJAx8CCwAfAgloDAAABABgAGkMAAAFAFQAawwAAAUAXQBqDAAAAgBGAGwMAAADAEsAbQwAAAEATADqDAAAAwBHAG4MAAABAEEAbwwAAAIARgABLgAFFAMJBQANAGATAA==.Munco:BAACLgAFFH8FAAIcAAQJVhvdDAAqAQRoDAAAAQBBAGkMAAABAEQAawwAAAEAUwDqDAAAAgA+ABwABAlWG90MACoBBGgMAAABAEEAaQwAAAEARABrDAAAAQBTAOoMAAACAD4ALgAECn89AAMcAAkJ4yPwAgAhAwAcAAkJ4yPwAgAhAwACAAEJTBjn9ABHAAAAAA==.Muncola:BAAALgAECgMJAwABLgAFFAQJBQAcAFYbAA==.Muncoli:BAAALgAECgMJBAABLgAFFAQJBQAcAFYbAA==.Muncolito:BAAALgADCgEJAQABLgAFFAQJBQAcAFYbAA==.Mungus:BAAALgAECgQJCQAAAA==.Mutakor:BAAALgAECgEJAQABLgAFFAgJQAAKANEjAA==.',
My='Mylf:BAAALgAECgEJAQAAAA==.Mythhleremix:BAAALgADCgUJBgABLgAFFAQJFAAKAIUlAA==.',
Ne='Nedd:BAAALgADCggJCAABLgAECgkJKQADAM4iAA==.Nellie:BAABLgAECn8gAAMSAAkJJg7QJACWAQloDAAABQAfAGkMAAAFABcAawwAAAUAKABqDAAAAwApAGwMAAAEADAAbQwAAAIAJQDqDAAABQA0AG4MAAACAA8AbwwAAAEAKAASAAkJJg7QJACWAQloDAAAAwAfAGkMAAADABcAawwAAAMAKABqDAAAAwApAGwMAAAEADAAbQwAAAIAJQDqDAAABAA0AG4MAAACAA8AbwwAAAEAKAARAAQJlQHMsABkAARoDAAAAgADAGkMAAACAAQAawwAAAIABADqDAAAAQADAAAA.Newtree:BAAALgAFFAcJBAABLgAFFAkJCwAFAOIdAA==.',
No='Notker:BAABLgAECn8uAAIUAAkJ7COfAgBsAwloDAAABwBiAGkMAAAGAF0AawwAAAYAYQBqDAAABABeAGwMAAAGAGAAbQwAAAQAWADqDAAABwBhAG4MAAAEAFEAbwwAAAIATwAUAAkJ7COfAgBsAwloDAAABwBiAGkMAAAGAF0AawwAAAYAYQBqDAAABABeAGwMAAAGAGAAbQwAAAQAWADqDAAABwBhAG4MAAAEAFEAbwwAAAIATwAAAA==.',
Ny='Nynaa:BAAALgAECgEJAQABLgAECgkJKQADAM4iAA==.',
On='Onieroxmysox:BAAALgADCgEJAQAAAA==.',
Or='Orcwarr:BAABLgAECn8uAAQKAAkJ1RzOBwB1AgloDAAACABXAGkMAAAHAFoAawwAAAcAVgBqDAAABgBPAGwMAAAGAEIAbQwAAAIAQgDqDAAABgBFAG4MAAADADMAbwwAAAEARwAKAAkJ1RzOBwB1AgloDAAABgBXAGkMAAAGAFoAawwAAAYAVgBqDAAABgBPAGwMAAAGAEIAbQwAAAIAQgDqDAAABQBFAG4MAAADADMAbwwAAAEARwABAAMJlAl4jwCAAANoDAAAAgAbAGkMAAABAAEAawwAAAEAKwANAAEJPQsKQwAzAAHqDAAAAQAcAAAA.',
Pa='Panders:BAABLgAFFH8KAAILAAQJ+AUnVQDxAARoDAAAAwANAGkMAAADAB8AawwAAAEACQDqDAAAAwAGAAsABAn4BSdVAPEABGgMAAADAA0AaQwAAAMAHwBrDAAAAQAJAOoMAAADAAYAAAA=.Patadita:BAAALgAECgYJDgAAAA==.',
Pe='Pecanpie:BAABLgAFFH8FAAQNAAMJYBNNKwCVAANoDAAAAgAsAGkMAAACADYA6gwAAAEAMgANAAIJQBNNKwCVAAJoDAAAAQAsAGkMAAABADYAAQACCSAN3T4AkQACaAwAAAEAKgBpDAAAAQAYAAoAAQmhE4wpADcAAeoMAAABADIAAAA=.Penne:BAAALgADCgcJDAAAAA==.',
Pi='Pinkpony:BAAALgAFFAUJBAABLgAFFAkJCwAFAOIdAA==.Pipsi:BAAALgAECgEJAQABLgAFFAQJBQAcAFYbAA==.',
Pk='Pk:BAAALgAECgUJBQABLgAFFAQJCAADAJUZAA==.',
Pr='Pryor:BAAALgAECgUJBQABLgAECgkJKQADAM4iAA==.',
Qu='Quiverinpalm:BAABLgAECn8VAAIGAAgJfA+UKABkAQhoDAAABQA9AGkMAAAEAB4AawwAAAMAIwBqDAAAAgAcAGwMAAACACYAbQwAAAEAEwDqDAAAAwArAG4MAAABADAABgAICXwPlCgAZAEIaAwAAAUAPQBpDAAABAAeAGsMAAADACMAagwAAAIAHABsDAAAAgAmAG0MAAABABMA6gwAAAMAKwBuDAAAAQAwAAAA.',
Ra='Rageoverrun:BAAALgADCgYJCgAAAA==.',
Re='Remiwog:BAAALgADCggJCgAAAA==.Rennik:BAACLgAFFH8UAAQJAAQJaCOuCAD5AARoDAAABwBdAGkMAAAGAFwAawwAAAIAWADqDAAABQBYAAkAAwlrHK4IAPkAA2gMAAACAEkAaQwAAAIAOABrDAAAAgBYAB0AAgmQIzRyAM0AAmgMAAAFAF0A6gwAAAUAWAAeAAEJ8CNIFwBYAAFpDAAABABcAC4ABAp/OgAEHQAJCQUkjSUAQgIAHQAHCaMejSUAQgIACQAFCUojWQ4A4wEAHgADCV0kGR8AsgAAAAA=.Rentiak:BAAALgAECgYJEwAAAA==.',
Ru='Rue:BAAALgAECgYJCwAAAA==.',
Sa='Saffy:BAAALgADCgYJBwAAAA==.',
Sc='Scorevival:BAAALgAECgEJAQAAAA==.Scorewin:BAEBLgAECn8hAAIfAAkJCiTeAQD1AgloDAAABQBeAGkMAAAEAFsAawwAAAQAYQBqDAAABABUAGwMAAADAGAAbQwAAAIASgDqDAAABgBhAG4MAAAEAF4AbwwAAAEAWwAfAAkJCiTeAQD1AgloDAAABQBeAGkMAAAEAFsAawwAAAQAYQBqDAAABABUAGwMAAADAGAAbQwAAAIASgDqDAAABgBhAG4MAAAEAF4AbwwAAAEAWwAAAA==.',
Se='Serenity:BAAALgAECgEJAwABLgAFFAUJCgACAGMaAA==.Serraku:BAAALgAECgEJAQAAAA==.',
Sh='Shadowfern:BAEALgAECgMJBgAAAA==.Shalniar:BAAALgADCgYJBgABLgAFFAYJGAAgAMMfAA==.Shioh:BAAALgADCgUJBQAAAA==.Shocky:BAAALgAECgEJAQAAAA==.',
Si='Sienda:BAAALgAECgUJBQAAAA==.Sinappi:BAAALgAECgEJAwAAAA==.Siñ:BAABLgAECn8jAAIhAAkJTQiTCgCBAQloDAAABQAbAGkMAAAFABwAawwAAAUAFgBqDAAABAARAGwMAAAFABAAbQwAAAMADwDqDAAAAgAXAG4MAAAEABIAbwwAAAIAEAAhAAkJTQiTCgCBAQloDAAABQAbAGkMAAAFABwAawwAAAUAFgBqDAAABAARAGwMAAAFABAAbQwAAAMADwDqDAAAAgAXAG4MAAAEABIAbwwAAAIAEAAAAA==.',
Sk='Skaya:BAAALgADCgIJAgAAAA==.Skeetshootah:BAABLgAECn8tAAIXAAkJ2hc9LAAhAgloDAAABwBKAGkMAAAGAE0AawwAAAYATwBqDAAABAAvAGwMAAAFADkAbQwAAAQAOADqDAAABwAyAG4MAAAEAC0AbwwAAAIALgAXAAkJ2hc9LAAhAgloDAAABwBKAGkMAAAGAE0AawwAAAYATwBqDAAABAAvAGwMAAAFADkAbQwAAAQAOADqDAAABwAyAG4MAAAEAC0AbwwAAAIALgAAAA==.Skùnkstomper:BAAALgADCgEJAQAAAA==.Skúnkstomper:BAAALgAECgEJAQABLgAECgcJBwAHAAAAAA==.Skûnkstomper:BAAALgAECgEJAQABLgAECgcJBwAHAAAAAA==.',
Sl='Slowbadon:BAABLgAECn8YAAIZAAkJixPkMgB9AQloDAAABAA/AGkMAAAEAEcAawwAAAQATABqDAAAAgAdAGwMAAACACkAbQwAAAIANgDqDAAAAwAyAG4MAAACAC4AbwwAAAEAEAAZAAkJixPkMgB9AQloDAAABAA/AGkMAAAEAEcAawwAAAQATABqDAAAAgAdAGwMAAACACkAbQwAAAIANgDqDAAAAwAyAG4MAAACAC4AbwwAAAEAEAAAAA==.',
Sp='Spáceballs:BAAALgAECgEJAgABLgAECgcJBwAHAAAAAA==.',
St='Stabpokestab:BAAALgADCgcJDQAAAA==.Stay:BAAALgAECgcJBgABLgAFFAkJCwAFAOIdAA==.Streetlight:BAABLgAECn8VAAIMAAkJYQ/jEwACAgloDAAAAwAiAGkMAAABACYAawwAAAEALwBqDAAAAQAwAGwMAAAEAEYAbQwAAAMANgDqDAAABAAgAG4MAAADABMAbwwAAAEAEAAMAAkJYQ/jEwACAgloDAAAAwAiAGkMAAABACYAawwAAAEALwBqDAAAAQAwAGwMAAAEAEYAbQwAAAMANgDqDAAABAAgAG4MAAADABMAbwwAAAEAEAABLgABCgEJAQAHAAAAAA==.Streetlights:BAAALgAECgYJDgABLgABCgEJAQAHAAAAAA==.Streets:BAAALgAECggJEQABLgABCgEJAQAHAAAAAA==.',
Ta='Tank:BAACLgAFFH8UAAIKAAQJhSVtBwCjAQRoDAAABwBiAGkMAAAGAFwAawwAAAIAXwDqDAAABQBhAAoABAmFJW0HAKMBBGgMAAAHAGIAaQwAAAYAXABrDAAAAgBfAOoMAAAFAGEALgAECn8yAAIKAAkJwyWvAgA8AwAKAAkJwyWvAgA8AwAAAA==.',
Te='Teafayd:BAABLgAECn8YAAMeAAYJhQvWHADEAAZoDAAABAAcAGkMAAAGACQAawwAAAUAJABqDAAAAwAcAGwMAAACABMA6gwAAAQAGwAeAAYJCAvWHADEAAZoDAAAAgAVAGkMAAAGACQAawwAAAQAJABqDAAAAwAcAGwMAAACABMA6gwAAAQAGwAJAAIJMApsMQBPAAJoDAAAAgAcAGsMAAABABgAAAA=.',
Th='Thisboss:BAAALgAECgYJCAAAAA==.Thunderdot:BAABLgAECn8yAAIVAAkJbh71CwCJAgloDAAABwBeAGkMAAAHAFoAawwAAAgAXQBqDAAABgBDAGwMAAAFAFUAbQwAAAIAKADqDAAACgBVAG4MAAAEADkAbwwAAAEASQAVAAkJbh71CwCJAgloDAAABwBeAGkMAAAHAFoAawwAAAgAXQBqDAAABgBDAGwMAAAFAFUAbQwAAAIAKADqDAAACgBVAG4MAAAEADkAbwwAAAEASQAAAA==.Thunderlok:BAAALgADCgEJAgAAAA==.',
Ti='Tilvayne:BAACLgAFFH8WAAIDAAUJZBchUwA7AQVoDAAABgBPAGkMAAAFAEEAawwAAAQAMgBqDAAAAwAqAOoMAAAEACwAAwAFCWQXIVMAOwEFaAwAAAYATwBpDAAABQBBAGsMAAAEADIAagwAAAMAKgDqDAAABAAsAC4ABAp/TQACAwAJCc4iGw4A8gIAAwAJCc4iGw4A8gIAAAA=.',
To='Tomayter:BAABLgAECn8tAAIUAAkJzh+EBwDqAgloDAAABgBdAGkMAAAGAF4AawwAAAYAWABqDAAABAA2AGwMAAAGAE4AbQwAAAQAWwDqDAAABwBfAG4MAAAEAFcAbwwAAAIAMgAUAAkJzh+EBwDqAgloDAAABgBdAGkMAAAGAF4AawwAAAYAWABqDAAABAA2AGwMAAAGAE4AbQwAAAQAWwDqDAAABwBfAG4MAAAEAFcAbwwAAAIAMgAAAA==.',
Tr='Trap:BAAALgAFFAEJAgABLgAFFAUJCgACAGMaAA==.Trinitee:BAAALgADCgYJEAAAAA==.Trisriane:BAAALgAECgMJBgABLgAECgkJHQALAG4aAA==.Trist:BAABLgAECn8dAAILAAkJbhpzPgArAgloDAAABQBYAGkMAAAEAFsAawwAAAQASQBqDAAABABMAGwMAAADAFUAbQwAAAEAFADqDAAABQBQAG4MAAACAB0AbwwAAAEARwALAAkJbhpzPgArAgloDAAABQBYAGkMAAAEAFsAawwAAAQASQBqDAAABABMAGwMAAADAFUAbQwAAAEAFADqDAAABQBQAG4MAAACAB0AbwwAAAEARwAAAA==.',
Tu='Turbogoat:BAABLgAECn8lAAIDAAgJuh4GLQCFAghoDAAABgBeAGkMAAAHAFwAawwAAAYAWwBqDAAABABaAGwMAAAEAFQAbQwAAAMAPQDqDAAABgBTAG4MAAABACoAAwAICboeBi0AhQIIaAwAAAYAXgBpDAAABwBcAGsMAAAGAFsAagwAAAQAWgBsDAAABABUAG0MAAADAD0A6gwAAAYAUwBuDAAAAQAqAAAA.Turok:BAAALgAECgEJAgABLgAFFAMJBQAMAFMYAA==.',
Tw='Twaave:BAABLgAECn8yAAIPAAkJjSJvDQAIAwloDAAABwBgAGkMAAAGAGAAawwAAAkAYQBqDAAABgBeAGwMAAAFAFsAbQwAAAMAQgDqDAAACQBfAG4MAAAEAEcAbwwAAAEAWgAPAAkJjSJvDQAIAwloDAAABwBgAGkMAAAGAGAAawwAAAkAYQBqDAAABgBeAGwMAAAFAFsAbQwAAAMAQgDqDAAACQBfAG4MAAAEAEcAbwwAAAEAWgAAAA==.',
['Tÿ']='Tÿ:BAAALgAECgQJBQAAAA==.',
Va='Vaz:BAAALgAECgYJCwAAAA==.Vazp:BAAALgAECgUJBQABLgAECgYJCwAHAAAAAA==.',
Ve='Vendmachin:BAAALgADCgEJAQAAAA==.Verdessa:BAAALgAECgQJCAAAAA==.',
Vn='Vnav:BAAALgAECgcJCwAAAA==.',
Wa='Waltz:BAAALgADCgEJAQAAAA==.',
Xe='Xevic:BAAALgAECgIJAgABLgAECgkJKQADAM4iAA==.',
Xi='Xins:BAAALgAECgQJBAAAAA==.',
Yi='Yikezvelobtw:BAAALgAECgIJAwAAAA==.',
Za='Zapa:BAAALgAECgEJAQAAAA==.',
Ze='Zennah:BAAALgADCgQJBAAAAA==.Zerene:BAABLgAECn8uAAMJAAkJfhp3AwBRAgloDAAABwBAAGkMAAAGAEgAawwAAAYAUABqDAAABAA6AGwMAAAGAEUAbQwAAAQAOADqDAAABwA7AG4MAAAEAEQAbwwAAAIARwAJAAkJfhp3AwBRAgloDAAABABAAGkMAAAFAEgAawwAAAUAUABqDAAABAA6AGwMAAAFAEUAbQwAAAMAOADqDAAABQA7AG4MAAADAEQAbwwAAAIARwAdAAcJAAZXlQAOAQdoDAAAAwAUAGkMAAABAAYAawwAAAEAGgBsDAAAAQAKAG0MAAABABUA6gwAAAIADgBuDAAAAQAGAAAA.',
['Æs']='Æsc:BAABLgAECn8uAAIWAAkJUBfIFAC8AQloDAAABwAxAGkMAAAGAFQAawwAAAYASwBqDAAABABBAGwMAAAGAEsAbQwAAAQALgDqDAAABwA+AG4MAAAEACgAbwwAAAIALAAWAAkJUBfIFAC8AQloDAAABwAxAGkMAAAGAFQAawwAAAYASwBqDAAABABBAGwMAAAGAEsAbQwAAAQALgDqDAAABwA+AG4MAAAEACgAbwwAAAIALAAAAA==.',
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
