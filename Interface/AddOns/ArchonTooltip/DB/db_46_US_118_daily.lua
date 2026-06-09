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
local provider = {region='US',realm='Haomarush',name='US',type='daily',zone=46,date='2026-06-08',data={Ad='Adderall:BAAALgAECggJDgAAAA==.',
Ae='Aethrion:BAAALgAECgMJBwAAAA==.',
Al='Alexya:BAAALgADCgIJAgAAAA==.All:BAAALgADCgEJAQAAAA==.Alphahawk:BAACLgAFFH8OAAIBAAQJwgiXJwAIAQRoDAAABAAQAGkMAAAEABgAawwAAAIAEgDqDAAABAAdAAEABAnCCJcnAAgBBGgMAAAEABAAaQwAAAQAGABrDAAAAgASAOoMAAAEAB0ALgAECn9CAAIBAAkJBBvVFgA0AgABAAkJBBvVFgA0AgAAAA==.',
Ap='Apocalipsis:BAAALgAECgMJAwAAAA==.',
Aq='Aquilis:BAABLgAECn8TAAICAAkJAhigVgCeAQloDAAAAwBMAGkMAAADAFQAawwAAAMATABqDAAAAQArAGwMAAADADcAbQwAAAIANwDqDAAAAQAvAG4MAAACAEEAbwwAAAEAHwACAAkJAhigVgCeAQloDAAAAwBMAGkMAAADAFQAawwAAAMATABqDAAAAQArAGwMAAADADcAbQwAAAIANwDqDAAAAQAvAG4MAAACAEEAbwwAAAEAHwAAAA==.',
Ar='Aralaria:BAAALgAECgUJBQABLgAFFAMJCQADAIcdAA==.Aramis:BAAALgAECggJEwABLgAFFAMJCQADAIcdAA==.Aranumi:BAAALgAECgQJBAABLgAFFAMJCQADAIcdAA==.Arathrok:BAACLgAFFH8JAAIDAAMJhx1RgAD5AANoDAAABABMAGkMAAADAFgA6gwAAAIAPQADAAMJhx1RgAD5AANoDAAABABMAGkMAAADAFgA6gwAAAIAPQAuAAQKfx4AAgMACQmLIDxQAM4BAAMACQmLIDxQAM4BAAAA.',
As='Asha:BAACLgAFFH8YAAQEAAUJ/xYvEgAmAQVoDAAABQBHAGkMAAAFADEAawwAAAUATgBqDAAABAA7AOoMAAAFACQABAAFCf8WLxIAJgEFaAwAAAMARwBpDAAAAwAxAGsMAAADAE4AagwAAAIAOwDqDAAAAwAkAAUABQkADdAkACMBBWgMAAABAEkAaQwAAAEAKABrDAAAAQALAGoMAAABABsA6gwAAAEADAAGAAUJ7QU+MADfAAVoDAAAAQAWAGkMAAABAA0AawwAAAEADwBqDAAAAQAUAOoMAAABAAgALgAECn8cAAQEAAgJyyBcHADCAQAEAAgJyyBcHADCAQAFAAQJ0BwPRQBEAQAGAAUJxhnuNgAcAQAAAA==.Asmoday:BAABLgAECn8pAAIDAAkJziLSDwDoAgloDAAABgBUAGkMAAAGAF8AawwAAAYAWgBqDAAAAwBUAGwMAAAFAFoAbQwAAAMAXgDqDAAABwBYAG4MAAAEAFMAbwwAAAEAVgADAAkJziLSDwDoAgloDAAABgBUAGkMAAAGAF8AawwAAAYAWgBqDAAAAwBUAGwMAAAFAFoAbQwAAAMAXgDqDAAABwBYAG4MAAAEAFMAbwwAAAEAVgAAAA==.Astra:BAAALgAECgEJAQABLgAECgYJCwAHAAAAAA==.Asunawa:BAAALgADCgUJBQAAAA==.',
Au='Aundarr:BAAALgAECgQJBAABLgAECgkJKQADAM4iAA==.Autoshift:BAABLgAECn8WAAIIAAgJ7wrUGgAoAQhoDAAABAAeAGkMAAAEACUAawwAAAQAKwBqDAAAAwAlAGwMAAACACAAbQwAAAEAFgDqDAAAAgAQAG4MAAACAAwACAAICe8K1BoAKAEIaAwAAAQAHgBpDAAABAAlAGsMAAAEACsAagwAAAMAJQBsDAAAAgAgAG0MAAABABYA6gwAAAIAEABuDAAAAgAMAAAA.Auun:BAAALgAECgYJBwABLgAECgkJKQADAM4iAA==.',
Ba='Bartre:BAAALgAECgQJCAABLgAFFAQJFwAJAGgjAA==.Bat:BAABLgAECn8eAAIIAAkJZCW9AgDvAgloDAAABQBjAGkMAAAFAF4AawwAAAMAYgBqDAAABABiAGwMAAAEAF4AbQwAAAMAYQDqDAAAAwBeAG4MAAACAFgAbwwAAAEAYwAIAAkJZCW9AgDvAgloDAAABQBjAGkMAAAFAF4AawwAAAMAYgBqDAAABABiAGwMAAAEAF4AbQwAAAMAYQDqDAAAAwBeAG4MAAACAFgAbwwAAAEAYwAAAA==.',
Be='Benedictine:BAAALgAECgEJBQAAAA==.',
Bi='Bigcleavage:BAABLgAECn8hAAIKAAkJAxshDgAAAgloDAAABwA+AGkMAAAFAEsAawwAAAUAWQBqDAAABABRAGwMAAAEAFEAbQwAAAIAKADqDAAAAwA4AG4MAAACAEkAbwwAAAEASgAKAAkJAxshDgAAAgloDAAABwA+AGkMAAAFAEsAawwAAAUAWQBqDAAABABRAGwMAAAEAFEAbQwAAAIAKADqDAAAAwA4AG4MAAACAEkAbwwAAAEASgAAAA==.Bilbert:BAAALgAECgMJAwABLgAFFAMJCQALAKQgAA==.',
Bl='Blue:BAAALgAECgYJBgABLgAFFAcJFwAMAEESAA==.Blueberrypie:BAAALgAFFAEJAQABLgAFFAMJBQANAGATAA==.',
Bo='Boomster:BAABLgAFFH8KAAIOAAYJ5h87BwAqAgZoDAAAAgA+AGkMAAACAEoAawwAAAEASwBqDAAAAQBRAGwMAAABAGEA6gwAAAMAYgAOAAYJ5h87BwAqAgZoDAAAAgA+AGkMAAACAEoAawwAAAEASwBqDAAAAQBRAGwMAAABAGEA6gwAAAMAYgABLgAFFAkJCwAFAOIdAA==.',
Br='Bridgetpower:BAAALgADCgIJAgAAAA==.',
Ca='Calixta:BAACLgAFFH8JAAILAAMJpCDxSAARAQNoDAAABABSAGkMAAADAEYA6gwAAAIAYQALAAMJpCDxSAARAQNoDAAABABSAGkMAAADAEYA6gwAAAIAYQAuAAQKfyIAAgsACQnBI94VALgCAAsACQnBI94VALgCAAAA.Carbshock:BAAALgADCgYJCgAAAA==.',
Ce='Ceroah:BAAALgAECgYJCwAAAA==.',
Ch='Cherrypie:BAAALgAFFAEJAQABLgAFFAMJBQANAGATAA==.',
Co='Coodown:BAAALgAECgYJCAAAAA==.',
Cr='Cranberrypie:BAAALgAECgQJBQABLgAFFAMJBQANAGATAA==.Criscomaster:BAAALgAECgMJAwAAAA==.',
Cy='Cylla:BAACLgAFFH8WAAIPAAQJ7QzWYQAgAQRoDAAABwAuAGkMAAAHABYAawwAAAIADQDqDAAABgAxAA8ABAntDNZhACABBGgMAAAHAC4AaQwAAAcAFgBrDAAAAgANAOoMAAAGADEALgAECn86AAIPAAkJfBxgMABTAgAPAAkJfBxgMABTAgAAAA==.',
De='Delacour:BAAALgAECgQJBAABLgAECgkJKQADAM4iAA==.',
Di='Dilfdormu:BAABLgAECn8gAAMOAAYJwBB5GABDAQZoDAAABgA7AGkMAAAHAEcAawwAAAcAKwBqDAAABQASAGwMAAACAB0A6gwAAAUAIgAOAAYJwBB5GABDAQZoDAAABgA7AGkMAAAGAEcAawwAAAYAKwBqDAAABQASAGwMAAACAB0A6gwAAAUAIgAQAAIJ1QKxjAA0AAJpDAAAAQAGAGsMAAABAAcAAAA=.',
Dk='Dkvaluemenu:BAAALgAECgQJBAAAAA==.',
Do='Donkey:BAAALgADCgIJAgAAAA==.Doson:BAACLgAFFH8NAAIRAAQJWRKrKwAFAQRoDAAABgA7AGkMAAAEACEAawwAAAEAGADqDAAAAgBFABEABAlZEqsrAAUBBGgMAAAGADsAaQwAAAQAIQBrDAAAAQAYAOoMAAACAEUALgAECn85AAMRAAkJPh8bCQAiAwARAAkJPh8bCQAiAwASAAEJ2iTeagBqAAAAAA==.',
Dr='Dragonmabals:BAAALgAECgQJBAAAAA==.Dratak:BAACLgAFFH9AAAIKAAgJ0SPWAADJAghoDAAACwBjAGkMAAAKAGEAawwAAAoAXgBqDAAACABfAGwMAAAGAGEAbQwAAAUASADqDAAACwBhAG4MAAADAFMACgAICdEj1gAAyQIIaAwAAAsAYwBpDAAACgBhAGsMAAAKAF4AagwAAAgAXwBsDAAABgBhAG0MAAAFAEgA6gwAAAsAYQBuDAAAAwBTAC4ABAp/cQACCgAJCcomHgAAkwMACgAJCcomHgAAkwMAAAA=.Dread:BAABLgAECn8bAAIEAAgJjBrAEAB2AghoDAAABQBVAGkMAAAEAFwAawwAAAQAWQBqDAAABABGAGwMAAADAFQAbQwAAAIAFgDqDAAABABEAG4MAAABAB8ABAAICYwawBAAdgIIaAwAAAUAVQBpDAAABABcAGsMAAAEAFkAagwAAAQARgBsDAAAAwBUAG0MAAACABYA6gwAAAQARABuDAAAAQAfAAAA.Dreadfang:BAAALgADCgcJDQAAAA==.Dred:BAAALgAECgMJBwAAAA==.Drizbul:BAAALgAECgEJBAABLgAFFAgJQAAKANEjAA==.',
Ea='Earthswrath:BAAALgAECgUJDgAAAA==.',
El='Elitzai:BAAALgAECgIJAwAAAA==.Elusivemonk:BAAALgAECgEJAQAAAA==.',
Em='Emeralda:BAAALgADCgcJDQAAAA==.',
Ev='Evalueate:BAAALgAECgQJBAAAAA==.',
Fl='Fluf:BAAALgADCgcJDAAAAA==.',
Fr='Frocknor:BAABLgAECn8lAAMKAAcJjxXQIAAgAQdoDAAABwAjAGkMAAAHADMAawwAAAYALQBqDAAABABOAGwMAAAFAFEA6gwAAAcAOgBuDAAAAQA5AAEABglLFNY+AEUBBmgMAAAFACMAaQwAAAUALgBrDAAABAAlAGoMAAADAE4AbAwAAAIAUQDqDAAABgA6AAoABwleENAgACABB2gMAAACABUAaQwAAAIAMwBrDAAAAgAtAGoMAAABAEMAbAwAAAMAIwDqDAAAAQAnAG4MAAABADkAAAA=.',
Fu='Fuki:BAAALgAECgQJDAAAAA==.Furrymythh:BAAALgAECgQJBAABLgAFFAQJFwAKAKYlAA==.',
Fy='Fyrstureinn:BAAALgADCgIJAgAAAA==.',
Ga='Galumian:BAACLgAFFH8vAAITAAgJxSLSAAByAghoDAAACQBjAGkMAAAIAGIAawwAAAYAYQBqDAAABgBcAGwMAAAFAGAAbQwAAAIAMgDqDAAACgBZAG4MAAABAFcAEwAICcUi0gAAcgIIaAwAAAkAYwBpDAAACABiAGsMAAAGAGEAagwAAAYAXABsDAAABQBgAG0MAAACADIA6gwAAAoAWQBuDAAAAQBXAC4ABAp/QQAEEwAJCaUl/wAAzgMAEwAJCaUl/wAAzgMAFAAHCRIRQC8AhgEAFQACCdwhukYAyQAAAAA=.',
Ge='Geron:BAAALgAECgUJBQABLgAFFAMJCQALAKQgAA==.Geronimó:BAAALgAECgEJAQABLgAECgcJBwAHAAAAAA==.Geronimô:BAAALgAECgYJDAAAAA==.Gerønimo:BAAALgAECgEJAQAAAA==.',
Go='Goo:BAAALgAECgcJDAABLgAFFAcJFwAWAC0VAA==.',
Gu='Gummies:BAAALgAECgEJAQAAAA==.Guy:BAAALgADCgcJBwAAAA==.',
Ha='Hamhock:BAAALgAECgQJDgAAAA==.Haradali:BAAALgAFFAQJBAAAAA==.Hawa:BAAALgADCgEJAQAAAA==.',
Hi='Highpantsman:BAAALgAECgcJCAAAAA==.',
Ho='Holydiah:BAABLgAECn8iAAILAAcJtQ7qkgBEAQdoDAAABwAhAGkMAAAHABwAawwAAAcAHQBqDAAABgAzAGwMAAAFACkAbQwAAAEARADqDAAAAQAYAAsABwm1DuqSAEQBB2gMAAAHACEAaQwAAAcAHABrDAAABwAdAGoMAAAGADMAbAwAAAUAKQBtDAAAAQBEAOoMAAABABgAAAA=.Holypriest:BAAALgAECgcJCgAAAA==.Hoofwinkled:BAAALgAECgcJBwAAAA==.Hordehound:BAAALgADCgIJAgAAAA==.',
Hu='Huugg:BAAALgADCgMJAwAAAA==.',
Ja='Jakimozo:BAAALgAECgcJDAAAAA==.Jasminetea:BAACLgAFFH8JAAMUAAMJXhYvIACpAANoDAAABAAyAGkMAAADADYA6gwAAAIAQwAUAAMJBxIvIACpAANoDAAABAAyAGkMAAACADYA6gwAAAEAIQATAAIJ7hFNNwCNAAJpDAAAAQAYAOoMAAABAEMALgAECn8vAAQTAAkJYhywEgAdAgATAAgJxR6wEgAdAgAVAAcJ/wz2NQA4AQAUAAQJjgncUACOAAAAAA==.',
Ju='Judgecutie:BAAALgAECgkJCQAAAA==.',
Ka='Kadesh:BAAALgADCgYJBgABLgAECgkJKQADAM4iAA==.Kayla:BAAALgAECgEJAwAAAA==.',
Ko='Kode:BAAALgAECgIJAgABLgAECgkJKQADAM4iAA==.',
Kr='Krizara:BAAALgAECgEJAQABLgAECgcJJQAKAI8VAA==.Kroth:BAABLgAECn9KAAIRAAkJpxMnKgD9AQloDAAACgA7AGkMAAAJACgAawwAAAkAPgBqDAAACQAvAGwMAAAJADgAbQwAAAcAHADqDAAACQBDAG4MAAAHADQAbwwAAAUAJgARAAkJpxMnKgD9AQloDAAACgA7AGkMAAAJACgAawwAAAkAPgBqDAAACQAvAGwMAAAJADgAbQwAAAcAHADqDAAACQBDAG4MAAAHADQAbwwAAAUAJgAAAA==.',
Ku='Kubfury:BAAALgAECgcJDgAAAA==.Kudi:BAAALgAECgYJDAAAAA==.',
['Kí']='Kíllian:BAABLgAECn8lAAIXAAkJ/yFpEgC2AgloDAAABQBVAGkMAAAFAFMAawwAAAUAXABqDAAAAgArAGwMAAAFAFkAbQwAAAQAXwDqDAAABgBeAG4MAAADAD0AbwwAAAIAXAAXAAkJ/yFpEgC2AgloDAAABQBVAGkMAAAFAFMAawwAAAUAXABqDAAAAgArAGwMAAAFAFkAbQwAAAQAXwDqDAAABgBeAG4MAAADAD0AbwwAAAIAXAAAAA==.Kíran:BAAALgAECgEJAwAAAA==.',
La='Labatblue:BAAALgADCgEJAQAAAA==.Lacey:BAAALgAECgYJBgAAAA==.Lavitz:BAAALgAECgYJCgAAAA==.',
Li='Lily:BAAALgAECgcJCwAAAA==.Limparrow:BAAALgADCgYJBgAAAA==.',
Lo='Loris:BAAALgAECgcJBgABLgAFFAkJCwAFAOIdAA==.',
Lu='Lunaci:BAABLgAECn8qAAMQAAkJDxzcDACJAgloDAAABgBAAGkMAAAFADgAawwAAAUAUABqDAAABABJAGwMAAAGAE4AbQwAAAQARQDqDAAABgBZAG4MAAAEAE4AbwwAAAIAOgAQAAkJDxzcDACJAgloDAAABABAAGkMAAADADgAawwAAAMAUABqDAAAAgBJAGwMAAAEAE4AbQwAAAQARQDqDAAAAwBZAG4MAAAEAE4AbwwAAAIAOgAYAAYJmQ4sEQDvAAZoDAAAAgAjAGkMAAACACUAawwAAAIANQBqDAAAAgAeAGwMAAACABMA6gwAAAMAKQAAAA==.Lunylu:BAAALgADCgUJBQAAAA==.',
Ma='Magicmagicin:BAAALgAECgMJAgAAAA==.Magnusson:BAABLgAECn8uAAIKAAkJWR1zBwCCAgloDAAABwBaAGkMAAAGAFAAawwAAAYAUwBqDAAABABLAGwMAAAGAFkAbQwAAAQALwDqDAAABwBPAG4MAAAEACgAbwwAAAIAWAAKAAkJWR1zBwCCAgloDAAABwBaAGkMAAAGAFAAawwAAAYAUwBqDAAABABLAGwMAAAGAFkAbQwAAAQALwDqDAAABwBPAG4MAAAEACgAbwwAAAIAWAAAAA==.Mandrah:BAAALgAECgYJCQAAAA==.Masutado:BAABLgAECn8uAAIPAAkJvBxMHQCnAgloDAAABwBSAGkMAAAGAEgAawwAAAYAUABqDAAABABUAGwMAAAGAF4AbQwAAAQAUADqDAAABwBSAG4MAAAEAEQAbwwAAAIAGwAPAAkJvBxMHQCnAgloDAAABwBSAGkMAAAGAEgAawwAAAYAUABqDAAABABUAGwMAAAGAF4AbQwAAAQAUADqDAAABwBSAG4MAAAEAEQAbwwAAAIAGwAAAA==.Maven:BAAALgAECgQJBAAAAA==.Mayelle:BAAALgADCgkJEAAAAA==.Mayernnaise:BAAALgAECgUJBgAAAA==.Maypah:BAAALgADCgIJAgAAAA==.Mayvoker:BAAALgADCgEJAQAAAA==.',
Me='Metier:BAAALgAECgUJCgABLgAFFAQJFwAKAKYlAA==.',
Mi='Miao:BAAALgAECgYJBgAAAA==.Mirror:BAABLgAFFH8GAAIOAAUJbCW+BwAfAgVoDAAAAgBdAGkMAAABAF8AawwAAAEAYQBqDAAAAQBfAOoMAAABAGEADgAFCWwlvgcAHwIFaAwAAAIAXQBpDAAAAQBfAGsMAAABAGEAagwAAAEAXwDqDAAAAQBhAAEuAAUUCQkLAAUA4h0A.Misfortune:BAAALgAECggJDgABLgAFFAMJCQALAKQgAA==.Mitsy:BAABLgAECn8uAAIVAAgJIRbkHQDQAQhoDAAABwA9AGkMAAAGADUAawwAAAYAOQBqDAAABgA+AGwMAAAGAD0AbQwAAAMALQDqDAAABwBEAG4MAAAFAC8AFQAICSEW5B0A0AEIaAwAAAcAPQBpDAAABgA1AGsMAAAGADkAagwAAAYAPgBsDAAABgA9AG0MAAADAC0A6gwAAAcARABuDAAABQAvAAAA.',
Mo='Money:BAABLgAECn8jAAMLAAgJGCGfIACpAghoDAAABwBgAGkMAAAGAGIAawwAAAcAWQBqDAAABABiAGwMAAAEAFIAbQwAAAIAKwDqDAAABABfAG4MAAABAFQACwAHCRYhnyAAqQIHaAwAAAcAYABpDAAABgBiAGsMAAAHAFkAagwAAAQAYgBsDAAABABSAG0MAAABACsA6gwAAAQAXwAZAAIJcAeNdQBbAAJtDAAAAQAUAG4MAAABABEAAAA=.Montipython:BAABLgAECn8WAAMaAAkJ7RRwGgA7AQloDAAABABcAGkMAAAEAEsAawwAAAQAPwBqDAAAAwBGAGwMAAACAC8AbQwAAAEAGADqDAAAAgBBAG4MAAABACQAbwwAAAEAFwAaAAUJBh1wGgA7AQVoDAAABABcAGkMAAAEAEsAawwAAAQAPwBqDAAAAQBGAOoMAAABAEEACwAGCWcNgcMA+gAGagwAAAIAQgBsDAAAAgAvAG0MAAABABgA6gwAAAEAKABuDAAAAQAkAG8MAAABABcAAAA=.Moons:BAACLgAFFH8XAAMMAAcJQRJNAwDcAQdoDAAABQBVAGkMAAAGADIAawwAAAQANQBqDAAAAgAgAGwMAAABACAAbQwAAAEAEQDqDAAABAAoAAwABwlBEk0DANwBB2gMAAAFAFUAaQwAAAYAMgBrDAAABAA1AGoMAAACACAAbAwAAAEAIABtDAAAAQARAOoMAAADACgAFwABCfEBFKEAOwAB6gwAAAEABAAuAAQKf1QAAgwACQmXI0ACACYDAAwACQmXI0ACACYDAAAA.Mothman:BAAALgADCgUJBAAAAA==.Moussebreath:BAACLgAFFH8JAAITAAYJVggEJAASAQZoDAAAAQAoAGkMAAABAAkAawwAAAEABQBsDAAAAgARAG0MAAABAAgA6gwAAAMALgATAAYJVggEJAASAQZoDAAAAQAoAGkMAAABAAkAawwAAAEABQBsDAAAAgARAG0MAAABAAgA6gwAAAMALgAuAAQKfxgAAhMABwmrH1UOAFUCABMABwmrH1UOAFUCAAAA.',
Mu='Mudpie:BAABLgAECn8aAAIbAAkJAx9ICwAgAgloDAAABABgAGkMAAAFAFQAawwAAAUAXQBqDAAAAgBGAGwMAAADAEsAbQwAAAEATADqDAAAAwBHAG4MAAABAEEAbwwAAAIARgAbAAkJAx9ICwAgAgloDAAABABgAGkMAAAFAFQAawwAAAUAXQBqDAAAAgBGAGwMAAADAEsAbQwAAAEATADqDAAAAwBHAG4MAAABAEEAbwwAAAIARgABLgAFFAMJBQANAGATAA==.Munco:BAACLgAFFH8FAAIcAAQJVhvBDQApAQRoDAAAAQBBAGkMAAABAEQAawwAAAEAUwDqDAAAAgA+ABwABAlWG8ENACkBBGgMAAABAEEAaQwAAAEARABrDAAAAQBTAOoMAAACAD4ALgAECn89AAMcAAkJ4yMsAwAfAwAcAAkJ4yMsAwAfAwACAAEJTBgk+QBHAAAAAA==.Muncola:BAAALgAECgMJAwABLgAFFAQJBQAcAFYbAA==.Muncoli:BAAALgAECgMJBAABLgAFFAQJBQAcAFYbAA==.Muncolito:BAAALgADCgEJAQABLgAFFAQJBQAcAFYbAA==.Mungus:BAAALgAECgQJCQAAAA==.Mutakor:BAAALgAECgEJAQABLgAFFAgJQAAKANEjAA==.',
My='Mylf:BAAALgAECgEJAQAAAA==.Mythhleremix:BAAALgADCgUJBgABLgAFFAQJFwAKAKYlAA==.',
Ne='Nedd:BAAALgADCggJCAABLgAECgkJKQADAM4iAA==.Nellie:BAABLgAECn8gAAMSAAkJJg6CJQCWAQloDAAABQAfAGkMAAAFABcAawwAAAUAKABqDAAAAwApAGwMAAAEADAAbQwAAAIAJQDqDAAABQA0AG4MAAACAA8AbwwAAAEAKAASAAkJJg6CJQCWAQloDAAAAwAfAGkMAAADABcAawwAAAMAKABqDAAAAwApAGwMAAAEADAAbQwAAAIAJQDqDAAABAA0AG4MAAACAA8AbwwAAAEAKAARAAQJlQHMsABkAARoDAAAAgADAGkMAAACAAQAawwAAAIABADqDAAAAQADAAAA.Newtree:BAAALgAFFAcJBAABLgAFFAkJCwAFAOIdAA==.',
No='Notker:BAABLgAECn8uAAIUAAkJ7CO/AgBqAwloDAAABwBiAGkMAAAGAF0AawwAAAYAYQBqDAAABABeAGwMAAAGAGAAbQwAAAQAWADqDAAABwBhAG4MAAAEAFEAbwwAAAIATwAUAAkJ7CO/AgBqAwloDAAABwBiAGkMAAAGAF0AawwAAAYAYQBqDAAABABeAGwMAAAGAGAAbQwAAAQAWADqDAAABwBhAG4MAAAEAFEAbwwAAAIATwAAAA==.',
Ny='Nynaa:BAAALgAECgEJAQABLgAECgkJKQADAM4iAA==.',
On='Onieroxmysox:BAAALgADCgEJAQAAAA==.',
Or='Orcwarr:BAABLgAECn8uAAQKAAkJ1RwbCAByAgloDAAACABXAGkMAAAHAFoAawwAAAcAVgBqDAAABgBPAGwMAAAGAEIAbQwAAAIAQgDqDAAABgBFAG4MAAADADMAbwwAAAEARwAKAAkJ1RwbCAByAgloDAAABgBXAGkMAAAGAFoAawwAAAYAVgBqDAAABgBPAGwMAAAGAEIAbQwAAAIAQgDqDAAABQBFAG4MAAADADMAbwwAAAEARwABAAMJlAl4jwCAAANoDAAAAgAbAGkMAAABAAEAawwAAAEAKwANAAEJPQsKQwAzAAHqDAAAAQAcAAAA.',
Pa='Panders:BAABLgAFFH8KAAILAAQJ+AW1WADvAARoDAAAAwANAGkMAAADAB8AawwAAAEACQDqDAAAAwAGAAsABAn4BbVYAO8ABGgMAAADAA0AaQwAAAMAHwBrDAAAAQAJAOoMAAADAAYAAAA=.Patadita:BAAALgAECgYJDgAAAA==.',
Pe='Pecanpie:BAABLgAFFH8FAAQNAAMJYBNLLQCVAANoDAAAAgAsAGkMAAACADYA6gwAAAEAMgANAAIJQBNLLQCVAAJoDAAAAQAsAGkMAAABADYAAQACCSANLEAAjwACaAwAAAEAKgBpDAAAAQAYAAoAAQmhE4UqADYAAeoMAAABADIAAAA=.Penne:BAAALgADCgcJDAAAAA==.',
Pi='Pinkpony:BAAALgAFFAUJBAABLgAFFAkJCwAFAOIdAA==.Pipsi:BAAALgAECgEJAQABLgAFFAQJBQAcAFYbAA==.',
Pk='Pk:BAAALgAECgUJBQABLgAFFAQJCAADAJUZAA==.',
Pr='Pryor:BAAALgAECgUJBQABLgAECgkJKQADAM4iAA==.',
Qu='Quiverinpalm:BAABLgAECn8VAAIGAAgJfA8uKQBkAQhoDAAABQA9AGkMAAAEAB4AawwAAAMAIwBqDAAAAgAcAGwMAAACACYAbQwAAAEAEwDqDAAAAwArAG4MAAABADAABgAICXwPLikAZAEIaAwAAAUAPQBpDAAABAAeAGsMAAADACMAagwAAAIAHABsDAAAAgAmAG0MAAABABMA6gwAAAMAKwBuDAAAAQAwAAAA.',
Ra='Rageoverrun:BAAALgADCgYJCgAAAA==.',
Re='Remiwog:BAAALgADCggJCgAAAA==.Rennik:BAACLgAFFH8XAAQJAAQJaCNZCQD3AARoDAAACABdAGkMAAAHAFwAawwAAAIAWADqDAAABgBYAAkAAwlrHFkJAPcAA2gMAAACAEkAaQwAAAIAOABrDAAAAgBYAB0AAgmQI1R2AMsAAmgMAAAGAF0A6gwAAAYAWAAeAAEJ8COfGABYAAFpDAAABQBcAC4ABAp/OgAEHQAJCQUklCYAPgIAHQAHCaMelCYAPgIACQAFCUojWQ4A4wEAHgADCV0k8B8AsgAAAAA=.Rentiak:BAAALgAECgYJEwAAAA==.',
Ru='Rue:BAAALgAECgYJCwAAAA==.',
Sa='Saffy:BAAALgADCgYJBwAAAA==.',
Sc='Scorevival:BAAALgAECgEJAQAAAA==.Scorewin:BAEBLgAECn8hAAIfAAkJCiTeAQD1AgloDAAABQBeAGkMAAAEAFsAawwAAAQAYQBqDAAABABUAGwMAAADAGAAbQwAAAIASgDqDAAABgBhAG4MAAAEAF4AbwwAAAEAWwAfAAkJCiTeAQD1AgloDAAABQBeAGkMAAAEAFsAawwAAAQAYQBqDAAABABUAGwMAAADAGAAbQwAAAIASgDqDAAABgBhAG4MAAAEAF4AbwwAAAEAWwAAAA==.',
Se='Sennaria:BAAALgAECgEJAQAAAA==.Serenity:BAAALgAECgEJAwABLgAFFAUJCgACAGMaAA==.Serraku:BAAALgAECgEJAQAAAA==.',
Sh='Shadowfern:BAEALgAECgMJBgAAAA==.Shalniar:BAAALgADCgYJBgABLgAFFAYJGgAgAMMfAA==.Shioh:BAAALgADCgUJBQAAAA==.Shocky:BAAALgAECgEJAQAAAA==.',
Si='Sienda:BAAALgAECgYJCwAAAA==.Sinappi:BAAALgAECgEJAwAAAA==.Siñ:BAABLgAECn8jAAIhAAkJTQjBCgCAAQloDAAABQAbAGkMAAAFABwAawwAAAUAFgBqDAAABAARAGwMAAAFABAAbQwAAAMADwDqDAAAAgAXAG4MAAAEABIAbwwAAAIAEAAhAAkJTQjBCgCAAQloDAAABQAbAGkMAAAFABwAawwAAAUAFgBqDAAABAARAGwMAAAFABAAbQwAAAMADwDqDAAAAgAXAG4MAAAEABIAbwwAAAIAEAAAAA==.',
Sk='Skaya:BAAALgADCgIJAgAAAA==.Skeetshootah:BAABLgAECn8tAAIXAAkJ2hf3LQAcAgloDAAABwBKAGkMAAAGAE0AawwAAAYATwBqDAAABAAvAGwMAAAFADkAbQwAAAQAOADqDAAABwAyAG4MAAAEAC0AbwwAAAIALgAXAAkJ2hf3LQAcAgloDAAABwBKAGkMAAAGAE0AawwAAAYATwBqDAAABAAvAGwMAAAFADkAbQwAAAQAOADqDAAABwAyAG4MAAAEAC0AbwwAAAIALgAAAA==.Skunkstomper:BAAALgAECgEJAQABLgAECgcJBwAHAAAAAA==.Skùnkstomper:BAAALgAECgQJBAAAAA==.Skúnkstomper:BAAALgAECgEJAQABLgAECgcJBwAHAAAAAA==.Skûnkstomper:BAAALgAECgEJAQABLgAECgcJBwAHAAAAAA==.',
Sl='Slowbadon:BAABLgAECn8YAAIZAAkJixOcMwB9AQloDAAABAA/AGkMAAAEAEcAawwAAAQATABqDAAAAgAdAGwMAAACACkAbQwAAAIANgDqDAAAAwAyAG4MAAACAC4AbwwAAAEAEAAZAAkJixOcMwB9AQloDAAABAA/AGkMAAAEAEcAawwAAAQATABqDAAAAgAdAGwMAAACACkAbQwAAAIANgDqDAAAAwAyAG4MAAACAC4AbwwAAAEAEAAAAA==.',
Sp='Spáceballs:BAAALgAECgYJCAABLgAECgcJBwAHAAAAAA==.',
St='Stabpokestab:BAAALgADCgcJDQAAAA==.Stay:BAAALgAECgcJBgABLgAFFAkJCwAFAOIdAA==.Streetlight:BAABLgAECn8VAAIMAAkJYQ9iFAAAAgloDAAAAwAiAGkMAAABACYAawwAAAEALwBqDAAAAQAwAGwMAAAEAEYAbQwAAAMANgDqDAAABAAgAG4MAAADABMAbwwAAAEAEAAMAAkJYQ9iFAAAAgloDAAAAwAiAGkMAAABACYAawwAAAEALwBqDAAAAQAwAGwMAAAEAEYAbQwAAAMANgDqDAAABAAgAG4MAAADABMAbwwAAAEAEAABLgABCgEJAQAHAAAAAA==.Streetlights:BAAALgAECgYJDgABLgABCgEJAQAHAAAAAA==.Streets:BAAALgAECggJEQABLgABCgEJAQAHAAAAAA==.',
Ta='Tank:BAACLgAFFH8XAAIKAAQJpiWSBwCrAQRoDAAACABiAGkMAAAHAF4AawwAAAIAXwDqDAAABgBhAAoABAmmJZIHAKsBBGgMAAAIAGIAaQwAAAcAXgBrDAAAAgBfAOoMAAAGAGEALgAECn8yAAIKAAkJwyWvAgA8AwAKAAkJwyWvAgA8AwAAAA==.',
Te='Teafayd:BAABLgAECn8bAAQeAAYJBw1SHQDHAAZoDAAABQAcAGkMAAAHACQAawwAAAUAJABqDAAAAwAcAGwMAAACABMA6gwAAAUALgAeAAYJCAtSHQDHAAZoDAAAAgAVAGkMAAAHACQAawwAAAQAJABqDAAAAwAcAGwMAAACABMA6gwAAAQAGwAJAAMJ4AwuJACFAANoDAAAAgAcAGsMAAABABgA6gwAAAEALgAdAAEJyAJoUwEjAAFoDAAAAQAHAAAA.',
Th='Thisboss:BAAALgAECgYJCAAAAA==.Thunderdot:BAABLgAECn8yAAIVAAkJbh5KDACIAgloDAAABwBeAGkMAAAHAFoAawwAAAgAXQBqDAAABgBDAGwMAAAFAFUAbQwAAAIAKADqDAAACgBVAG4MAAAEADkAbwwAAAEASQAVAAkJbh5KDACIAgloDAAABwBeAGkMAAAHAFoAawwAAAgAXQBqDAAABgBDAGwMAAAFAFUAbQwAAAIAKADqDAAACgBVAG4MAAAEADkAbwwAAAEASQAAAA==.Thunderlok:BAAALgADCgEJAgAAAA==.',
Ti='Tilvayne:BAACLgAFFH8WAAIDAAUJZBehVwA6AQVoDAAABgBPAGkMAAAFAEEAawwAAAQAMgBqDAAAAwAqAOoMAAAEACwAAwAFCWQXoVcAOgEFaAwAAAYATwBpDAAABQBBAGsMAAAEADIAagwAAAMAKgDqDAAABAAsAC4ABAp/TQACAwAJCc4irg4A8QIAAwAJCc4irg4A8QIAAAA=.',
To='Tomayter:BAABLgAECn8tAAIUAAkJzh+5BwDpAgloDAAABgBdAGkMAAAGAF4AawwAAAYAWABqDAAABAA2AGwMAAAGAE4AbQwAAAQAWwDqDAAABwBfAG4MAAAEAFcAbwwAAAIAMgAUAAkJzh+5BwDpAgloDAAABgBdAGkMAAAGAF4AawwAAAYAWABqDAAABAA2AGwMAAAGAE4AbQwAAAQAWwDqDAAABwBfAG4MAAAEAFcAbwwAAAIAMgAAAA==.',
Tr='Trap:BAAALgAFFAEJAgABLgAFFAUJCgACAGMaAA==.Tree:BAABLgAFFH8HAAIRAAcJYx4SBgCSAgdoDAAAAQBXAGkMAAABABwAawwAAAEAVgBqDAAAAQBVAGwMAAABAE4AbQwAAAEAWADqDAAAAQBYABEABwljHhIGAJICB2gMAAABAFcAaQwAAAEAHABrDAAAAQBWAGoMAAABAFUAbAwAAAEATgBtDAAAAQBYAOoMAAABAFgAAS4ABRQJCQsABQDiHQA=.Trinitee:BAAALgADCggJEgAAAA==.Trisriane:BAAALgAECgMJBgABLgAECgkJHQALAG4aAA==.Trist:BAABLgAECn8dAAILAAkJbhpzPgArAgloDAAABQBYAGkMAAAEAFsAawwAAAQASQBqDAAABABMAGwMAAADAFUAbQwAAAEAFADqDAAABQBQAG4MAAACAB0AbwwAAAEARwALAAkJbhpzPgArAgloDAAABQBYAGkMAAAEAFsAawwAAAQASQBqDAAABABMAGwMAAADAFUAbQwAAAEAFADqDAAABQBQAG4MAAACAB0AbwwAAAEARwAAAA==.',
Tu='Turbogoat:BAABLgAECn8lAAIDAAgJuh4GLQCFAghoDAAABgBeAGkMAAAHAFwAawwAAAYAWwBqDAAABABaAGwMAAAEAFQAbQwAAAMAPQDqDAAABgBTAG4MAAABACoAAwAICboeBi0AhQIIaAwAAAYAXgBpDAAABwBcAGsMAAAGAFsAagwAAAQAWgBsDAAABABUAG0MAAADAD0A6gwAAAYAUwBuDAAAAQAqAAAA.Turok:BAAALgAECgEJAgABLgAFFAMJBQAMAFMYAA==.',
Tw='Twaave:BAABLgAECn8yAAIPAAkJjSLiDQAHAwloDAAABwBgAGkMAAAGAGAAawwAAAkAYQBqDAAABgBeAGwMAAAFAFsAbQwAAAMAQgDqDAAACQBfAG4MAAAEAEcAbwwAAAEAWgAPAAkJjSLiDQAHAwloDAAABwBgAGkMAAAGAGAAawwAAAkAYQBqDAAABgBeAGwMAAAFAFsAbQwAAAMAQgDqDAAACQBfAG4MAAAEAEcAbwwAAAEAWgAAAA==.',
['Tÿ']='Tÿ:BAAALgAECgQJBQAAAA==.',
Va='Vaz:BAAALgAECgYJCwAAAA==.Vazp:BAAALgAECgUJBQABLgAECgYJCwAHAAAAAA==.',
Ve='Vendmachin:BAAALgADCgEJAQAAAA==.Verdessa:BAAALgAECgQJCAAAAA==.',
Vn='Vnav:BAAALgAECgcJDgAAAA==.',
Wa='Waltz:BAAALgADCgEJAQAAAA==.',
Xe='Xevic:BAAALgAECgIJAgABLgAECgkJKQADAM4iAA==.',
Xi='Xins:BAAALgAECgQJBAAAAA==.',
Yi='Yikezvelobtw:BAAALgAECgIJAwAAAA==.',
Za='Zapa:BAAALgAECgEJAQAAAA==.',
Ze='Zennah:BAAALgADCgQJBAAAAA==.Zerene:BAABLgAECn8uAAMJAAkJfhqSAwBRAgloDAAABwBAAGkMAAAGAEgAawwAAAYAUABqDAAABAA6AGwMAAAGAEUAbQwAAAQAOADqDAAABwA7AG4MAAAEAEQAbwwAAAIARwAJAAkJfhqSAwBRAgloDAAABABAAGkMAAAFAEgAawwAAAUAUABqDAAABAA6AGwMAAAFAEUAbQwAAAMAOADqDAAABQA7AG4MAAADAEQAbwwAAAIARwAdAAcJAAZ8mAAJAQdoDAAAAwAUAGkMAAABAAYAawwAAAEAGgBsDAAAAQAKAG0MAAABABUA6gwAAAIADgBuDAAAAQAGAAAA.',
['Æs']='Æsc:BAABLgAECn8uAAIWAAkJUBdpFQC5AQloDAAABwAxAGkMAAAGAFQAawwAAAYASwBqDAAABABBAGwMAAAGAEsAbQwAAAQALgDqDAAABwA+AG4MAAAEACgAbwwAAAIALAAWAAkJUBdpFQC5AQloDAAABwAxAGkMAAAGAFQAawwAAAYASwBqDAAABABBAGwMAAAGAEsAbQwAAAQALgDqDAAABwA+AG4MAAAEACgAbwwAAAIALAAAAA==.',
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
