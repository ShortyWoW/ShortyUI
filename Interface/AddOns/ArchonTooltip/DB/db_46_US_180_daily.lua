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

local lookup = {'Hunter-BeastMastery','Unknown-Unknown','Warrior-Fury','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Paladin-Retribution','Paladin-Protection','Hunter-Marksmanship','Paladin-Holy','Mage-Frost','Warrior-Protection','Evoker-Augmentation','Monk-Brewmaster','Priest-Discipline','Priest-Shadow','Monk-Mistweaver','Hunter-Survival','DeathKnight-Unholy','Evoker-Devastation','Evoker-Preservation','Warrior-Arms','Druid-Feral','Monk-Windwalker','Shaman-Elemental','DemonHunter-Devourer','DemonHunter-Havoc','Shaman-Enhancement','Druid-Restoration','Shaman-Restoration','Mage-Arcane','Rogue-Subtlety','DemonHunter-Vengeance','DeathKnight-Blood','Mage-Fire','DeathKnight-Frost',}
local provider = {region='US',realm='Rivendare',name='US',type='daily',zone=46,date='2026-05-13',data={Ai='Aisling:BAAALgADCgYJBgAAAA==.',
Al='Alanispally:BAAALgADCgIJAQAAAA==.Algryn:BAAALgADCgUJBQAAAA==.Alkanz:BAAALgAECgkJDgAAAA==.Allinaa:BAABLgAECn8cAAIBAAkJwA56JwDQAQloDAAABAAkAGkMAAAEADIAawwAAAQANgBqDAAABABFAGwMAAADADAAbQwAAAIAEQDqDAAABAAtAG4MAAACABkAbwwAAAEAGAABAAkJwA56JwDQAQloDAAABAAkAGkMAAAEADIAawwAAAQANgBqDAAABABFAGwMAAADADAAbQwAAAIAEQDqDAAABAAtAG4MAAACABkAbwwAAAEAGAAAAA==.',
Am='Amorvea:BAAALgADCgUJBQABLgAECgIJAgACAAAAAA==.',
An='Angron:BAAALgADCgIJBQAAAA==.Anika:BAABLgAECn8qAAIDAAkJdAmjHACXAQloDAAABgAhAGkMAAAGABMAawwAAAYAGQBqDAAABQAJAGwMAAAFABoAbQwAAAMAEQDqDAAABgAxAG4MAAAEAAsAbwwAAAEACQADAAkJdAmjHACXAQloDAAABgAhAGkMAAAGABMAawwAAAYAGQBqDAAABQAJAGwMAAAFABoAbQwAAAMAEQDqDAAABgAxAG4MAAAEAAsAbwwAAAEACQAAAA==.',
Ar='Arcade:BAAALgAECgEJAgAAAA==.Arlyx:BAACLgAFFH8LAAMEAAQJwhBhSgDaAARoDAAABAAwAGkMAAAEADwAawwAAAEAKgDqDAAAAgATAAQAAwnIEGFKANoAA2gMAAAEADAAaQwAAAMAPADqDAAAAgATAAUAAgmnD5kUAFIAAmkMAAABACUAawwAAAEAKgAuAAQKfx8ABAQACAn+G2c1AKIBAAQABQkCHmc1AKIBAAUAAwnzFohHAJgAAAYAAgnoBzQfAHcAAAAA.Arnwaz:BAAALgAECgUJCwAAAA==.Arthuria:BAAALgAECggJDAAAAA==.',
As='Aslan:BAAALgADCgQJBwAAAA==.',
At='Atelwen:BAAALgAECgcJBwAAAA==.',
Av='Avelyn:BAAALgAECgMJAwAAAA==.',
Ba='Babyruthie:BAAALgAECgMJBAAAAA==.Baf:BAACLgAFFH8IAAIHAAQJaxdHGwBNAQRoDAAAAgBBAGkMAAACADIAawwAAAEARgDqDAAAAwA1AAcABAlrF0cbAE0BBGgMAAACAEEAaQwAAAIAMgBrDAAAAQBGAOoMAAADADUALgAECn8aAAIHAAcJdx2GPgArAgAHAAcJdx2GPgArAgAAAA==.Bayside:BAAALgAECgYJEQAAAA==.',
Be='Bearfomat:BAAALgAFFAIJAgAAAA==.Beefis:BAAALgAECgUJCwAAAA==.Beenjuicin:BAAALgAFFAEJAgABLgAFFAIJAgACAAAAAA==.Berfomat:BAABLgAECn8nAAIIAAkJ1CEqAQDxAgloDAAABgBhAGkMAAAGAF8AawwAAAYAUQBqDAAABQBcAGwMAAAEAGEAbQwAAAMAYQDqDAAABQBdAG4MAAADAEkAbwwAAAEAOAAIAAkJ1CEqAQDxAgloDAAABgBhAGkMAAAGAF8AawwAAAYAUQBqDAAABQBcAGwMAAAEAGEAbQwAAAMAYQDqDAAABQBdAG4MAAADAEkAbwwAAAEAOAAAAA==.',
Bi='Bingchilling:BAACLgAFFH8SAAIJAAUJyRLpCgBrAQVoDAAABQA4AGkMAAAEAEwAawwAAAQADgBqDAAAAQAIAOoMAAAEAC0ACQAFCckS6QoAawEFaAwAAAUAOABpDAAABABMAGsMAAAEAA4AagwAAAEACADqDAAABAAtAC4ABAp/IwACCQAJCVAbCAwA6gIACQAJCVAbCAwA6gIAAAA=.',
Bj='Bjorn:BAAALgAFFAEJAQAAAA==.',
Bl='Bloomyvfd:BAABLgAECn8YAAIKAAYJVB4uFgD1AQZoDAAABQBQAGkMAAAFAEsAawwAAAQARABqDAAAAwBSAGwMAAAEAEsA6gwAAAMAUQAKAAYJVB4uFgD1AQZoDAAABQBQAGkMAAAFAEsAawwAAAQARABqDAAAAwBSAGwMAAAEAEsA6gwAAAMAUQAAAA==.',
Bo='Bombuur:BAAALgAECgQJBAAAAA==.Bonniebadass:BAAALgAECgYJEwAAAA==.Bottle:BAAALgAECgcJDAAAAA==.Boxxylove:BAAALgAECgQJBAAAAA==.',
Br='Bravas:BAAALgAECgcJBQAAAA==.Brimscythe:BAAALgADCgQJBAAAAA==.Broxar:BAAALgADCgcJCwAAAA==.',
['Bî']='Bîa:BAABLgAECn8VAAIHAAcJjiDXHAA0AgdoDAAABABeAGkMAAAEAFEAawwAAAMAOgBqDAAAAwBiAGwMAAACAFEA6gwAAAQAXwBuDAAAAQBXAAcABwmOINccADQCB2gMAAAEAF4AaQwAAAQAUQBrDAAAAwA6AGoMAAADAGIAbAwAAAIAUQDqDAAABABfAG4MAAABAFcAAAA=.',
Ca='Cablemstache:BAAALgADCgcJBwAAAA==.Calisti:BAABLgAECn8lAAILAAcJtxrVZgAJAgdoDAAACABRAGkMAAAHAEoAawwAAAcAUQBqDAAABQA1AGwMAAAEAEEAbQwAAAIAGADqDAAABABRAAsABwm3GtVmAAkCB2gMAAAIAFEAaQwAAAcASgBrDAAABwBRAGoMAAAFADUAbAwAAAQAQQBtDAAAAgAYAOoMAAAEAFEAAAA=.Cavalis:BAABLgAECn8qAAQEAAkJ6hiDJgDjAQloDAAABgBLAGkMAAAGAEgAawwAAAYAUQBqDAAABQBGAGwMAAAFAFEAbQwAAAMAMgDqDAAABgAuAG4MAAAEADIAbwwAAAEANQAEAAgJRheDJgDjAQhoDAAAAwBDAGkMAAAFAEMAagwAAAIAQwBsDAAABQBRAG0MAAADADIA6gwAAAUALgBuDAAABAAyAG8MAAABADUABgAECU0YsRIAAQEEaAwAAAMASwBpDAAAAQBIAGoMAAABAB0A6gwAAAEAJwAFAAIJqx9ZRwCZAAJrDAAABgBRAGoMAAACAEYAAAA=.',
Ce='Ceedh:BAAALgAFFAMJBAAAAA==.Ceejr:BAACLgAFFH8YAAMDAAcJtyKlAQDoAQdoDAAABgBaAGkMAAAEAFsAawwAAAMAYABqDAAAAwA3AGwMAAACAFcAbQwAAAEAWADqDAAABQBPAAMABQnmIqUBAOgBBWgMAAAFAFoAaQwAAAQAWwBrDAAAAwBgAGoMAAADADcA6gwAAAQATwAMAAQJkiDIBQBpAQRoDAAAAQBXAGwMAAACAFcAbQwAAAEAWADqDAAAAQBGAC4ABAp/IAACAwAJCWklJAEAxAMAAwAJCWklJAEAxAMAAAA=.Cerovallen:BAAALgAECgYJCQAAAA==.',
Ch='Chailee:BAAALgADCgEJAQAAAA==.Cherish:BAAALgADCgMJAwABLgAECgUJCgACAAAAAA==.Chillum:BAAALgAECgIJAgABLgAFFAQJCQANAOIPAA==.Chimneybeans:BAAALgADCgcJBwAAAA==.',
Co='Corny:BAAALgAECgUJCwAAAA==.',
Cr='Creativez:BAABLgAFFH8HAAIOAAIJNRmzGACoAAJoDAAAAgBQAOoMAAAFADAADgACCTUZsxgAqAACaAwAAAIAUADqDAAABQAwAAAA.Creativezd:BAAALgAFFAIJAgABLgAFFAIJBwAOADUZAA==.',
Da='Damnskippy:BAAALgAECgQJBgAAAA==.Dannÿ:BAABLgAECn8cAAMPAAcJnhWuGQCEAQdoDAAABQA8AGkMAAAFADgAawwAAAUALQBqDAAABABKAGwMAAADADcAbQwAAAEAIgDqDAAABQA7AA8ABgn6Fq4ZAIQBBmgMAAAFADwAaQwAAAUAOABrDAAABQAtAGoMAAAEAEoAbAwAAAMANwDqDAAABQA7ABAAAQlMCq5fAC8AAW0MAAABABoAAAA=.Dantè:BAAALgAECgIJAgAAAA==.Daris:BAAALgADCgMJAwAAAA==.Darkire:BAACLgAFFH8GAAIBAAMJpAtdMgDpAANoDAAAAgAfAGkMAAACABYA6gwAAAIAIwABAAMJpAtdMgDpAANoDAAAAgAfAGkMAAACABYA6gwAAAIAIwAuAAQKfyEAAgEACAlgGYM4AMwBAAEACAlgGYM4AMwBAAAA.Darkstar:BAAALgADCgUJBQAAAA==.Darkwarriorx:BAAALgADCgQJAgAAAA==.',
De='Deathlegion:BAAALgAECgQJBAAAAA==.Deathroll:BAABLgAECn8mAAIRAAkJrRUtDgApAgloDAAABwBKAGkMAAAGAEoAawwAAAYAQABqDAAABQA/AGwMAAAFADUAbQwAAAMAJwDqDAAABABGAG4MAAABABEAbwwAAAEAKwARAAkJrRUtDgApAgloDAAABwBKAGkMAAAGAEoAawwAAAYAQABqDAAABQA/AGwMAAAFADUAbQwAAAMAJwDqDAAABABGAG4MAAABABEAbwwAAAEAKwAAAA==.Delarus:BAAALgAECgEJAQAAAA==.Demonarmor:BAAALgAECgMJCAABLgAECgcJCAACAAAAAA==.',
Di='Diddley:BAAALgADCgMJAwAAAA==.',
Do='Dogmatik:BAAALgAECgEJAQABLgAECgMJAwACAAAAAA==.Dontah:BAAALgADCgcJBwABLgAECgkJIgASAI0gAA==.Doomward:BAABLgAECn8bAAITAAYJfBSYXABFAQZoDAAABgA+AGkMAAAGADQAawwAAAUAPgBqDAAAAwBUAGwMAAADAB4A6gwAAAQANgATAAYJfBSYXABFAQZoDAAABgA+AGkMAAAGADQAawwAAAUAPgBqDAAAAwBUAGwMAAADAB4A6gwAAAQANgAAAA==.Dorien:BAABLgAECn8iAAMSAAkJjSAYAgD1AgloDAAABgBhAGkMAAAFAGAAawwAAAUAVABqDAAAAwBcAGwMAAADAEcAbQwAAAIAVgDqDAAABgBdAG4MAAADAEgAbwwAAAEAPwASAAkJjSAYAgD1AgloDAAABgBhAGkMAAAFAGAAawwAAAUAVABqDAAAAwBcAGwMAAADAEcAbQwAAAIAVgDqDAAABgBdAG4MAAACAEgAbwwAAAEAPwABAAEJlgeB0wA1AAFuDAAAAQATAAAA.',
Dr='Drachilly:BAACLgAFFH8JAAINAAQJ4g/mGAAoAQRoDAAAAwAyAGkMAAADACIAawwAAAEAIwDqDAAAAgAqAA0ABAniD+YYACgBBGgMAAADADIAaQwAAAMAIgBrDAAAAQAjAOoMAAACACoALgAECn8cAAQNAAgJKB46EwDJAQAUAAYJ9x09EADYAQANAAgJkh06EwDJAQAVAAEJDwLiMgAbAAAAAA==.Dragnar:BAABLgAECn8jAAIBAAkJlwzuPQC3AQloDAAABQArAGkMAAAFADQAawwAAAUALgBqDAAABAAWAGwMAAAEADQAbQwAAAIABQDqDAAABgAZAG4MAAADABAAbwwAAAEADgABAAkJlwzuPQC3AQloDAAABQArAGkMAAAFADQAawwAAAUALgBqDAAABAAWAGwMAAAEADQAbQwAAAIABQDqDAAABgAZAG4MAAADABAAbwwAAAEADgAAAA==.Drhealzgood:BAAALgADCgYJBgAAAA==.Droggo:BAAALgADCgIJAgAAAA==.',
Ev='Evilvdduck:BAAALgAECgEJAQAAAA==.',
Fa='Faewryn:BAAALgAECgkJCgAAAA==.Faeya:BAAALgADCgEJAQABLgADCgUJCAACAAAAAA==.Falekia:BAAALgAECgEJAQAAAA==.Fay:BAACLgAFFH8KAAIOAAQJIRbSEwAwAQRoDAAAAwA7AGkMAAADAD8AawwAAAEAMQDqDAAAAwA2AA4ABAkhFtITADABBGgMAAADADsAaQwAAAMAPwBrDAAAAQAxAOoMAAADADYALgAECn8cAAIOAAgJySHsEgB6AgAOAAgJySHsEgB6AgAAAA==.',
Fe='Felltown:BAAALgADCgMJAwAAAA==.',
Fi='Firstblood:BAAALgAECgYJCQAAAA==.Fishnchimps:BAABLgAFFH8FAAIRAAMJDRTEGADiAANoDAAAAgAkAGkMAAABABkA6gwAAAIAXAARAAMJDRTEGADiAANoDAAAAgAkAGkMAAABABkA6gwAAAIAXAAAAA==.',
Fu='Furrburger:BAAALgADCgIJAgAAAA==.',
Ga='Gaiserik:BAABLgAECn8fAAIWAAcJvh9yBgAhAgdoDAAABQBbAGkMAAAGAFcAawwAAAYAUwBqDAAABgBeAGwMAAADAEYAbQwAAAEASgDqDAAABABQABYABwm+H3IGACECB2gMAAAFAFsAaQwAAAYAVwBrDAAABgBTAGoMAAAGAF4AbAwAAAMARgBtDAAAAQBKAOoMAAAEAFAAAAA=.Galenda:BAAALgADCgQJBQAAAA==.Gandolph:BAAALgADCgEJAQAAAA==.Garduhm:BAAALgADCgYJCQABLgAECgIJAgACAAAAAA==.Garlictoast:BAAALgAECgQJBwAAAA==.',
Ge='Gearsofhate:BAAALgAECgEJAgAAAA==.Gehenna:BAAALgADCgYJCgAAAA==.',
Go='Goldenorder:BAAALgAECgEJAgAAAA==.Gome:BAAALgADCgcJGwABLgAFFAMJBQARAA0UAA==.',
Gr='Gracile:BAAALgADCgEJAQAAAA==.Gragolf:BAABLgAECn8cAAIBAAgJzhT4LgCtAQhoDAAABQA/AGkMAAAFAEUAawwAAAQAQgBqDAAABABOAGwMAAADAEcAbQwAAAEAFQDqDAAABQA8AG4MAAABABMAAQAICc4U+C4ArQEIaAwAAAUAPwBpDAAABQBFAGsMAAAEAEIAagwAAAQATgBsDAAAAwBHAG0MAAABABUA6gwAAAUAPABuDAAAAQATAAAA.Greggor:BAAALgAECgYJDQAAAA==.Gronkus:BAAALgAECgYJBwAAAA==.',
Gu='Gustabo:BAABLgAECn8bAAIXAAYJGyKeBgD4AQZoDAAABQBUAGkMAAAGAFYAawwAAAQAXABqDAAABABNAGwMAAADAFUA6gwAAAUAVgAXAAYJGyKeBgD4AQZoDAAABQBUAGkMAAAGAFYAawwAAAQAXABqDAAABABNAGwMAAADAFUA6gwAAAUAVgAAAA==.',
Ha='Haslin:BAAALgADCgEJAQAAAA==.Havibonespur:BAABLgAECn8XAAMOAAYJXQsTMQDpAAZoDAAABAAlAGkMAAAEABEAawwAAAQAGwBqDAAABAA7AGwMAAADAB0A6gwAAAQAIAAOAAYJXQsTMQDpAAZoDAAABAAlAGkMAAAEABEAawwAAAQAGwBqDAAABAA7AGwMAAACAB0A6gwAAAQAIAAYAAEJyQS5egAgAAFsDAAAAQAMAAAA.',
He='Healir:BAAALgAECggJEwAAAA==.Healmepls:BAAALgADCgYJCgABLgAFFAUJDAAZAHcPAA==.Hellsong:BAAALgAECgEJAQAAAA==.Helor:BAABLgAECn8XAAMaAAkJcRaEHwDnAQloDAAABABSAGkMAAADAE4AawwAAAIAVABqDAAAAgBTAGwMAAADAE8AbQwAAAMAHQDqDAAABABRAG4MAAABAAUAbwwAAAEAEQAaAAkJcRaEHwDnAQloDAAAAwBSAGkMAAACAE4AawwAAAEAVABqDAAAAQBTAGwMAAADAE8AbQwAAAMAHQDqDAAAAwBRAG4MAAABAAUAbwwAAAEAEQAbAAUJ3RXDLgBXAQVoDAAAAQA/AGkMAAABAEAAawwAAAEAIgBqDAAAAQBLAOoMAAABADwAAAA=.',
Ho='Holydeath:BAAALgAECgYJEQAAAA==.Hotpocketz:BAAALgADCgcJCQABLgAECggJFwADACoXAA==.',
Hu='Hunterish:BAAALgADCgEJAQAAAA==.',
Ia='Iadrithe:BAAALgADCgYJBgAAAA==.',
In='Inspectadeck:BAAALgAECgMJBAAAAA==.Invisus:BAAALgAFFAEJAQAAAA==.',
Is='Ispayderj:BAAALgAECgMJBAAAAA==.',
Ja='Jahy:BAAALgADCgIJAgAAAA==.Jake:BAABLgAECn8fAAIHAAkJyiXHBAAZAwloDAAABABeAGkMAAAEAGMAawwAAAQAXQBqDAAABABhAGwMAAAEAGIAbQwAAAMAYwDqDAAABABjAG4MAAADAF8AbwwAAAEAXgAHAAkJyiXHBAAZAwloDAAABABeAGkMAAAEAGMAawwAAAQAXQBqDAAABABhAGwMAAAEAGIAbQwAAAMAYwDqDAAABABjAG4MAAADAF8AbwwAAAEAXgAAAA==.Jarlan:BAACLgAFFH8PAAIWAAQJjB9zBAB6AQRoDAAABQBcAGkMAAAFAGAAawwAAAIAJQDqDAAAAwBgABYABAmMH3MEAHoBBGgMAAAFAFwAaQwAAAUAYABrDAAAAgAlAOoMAAADAGAALgAECn8hAAIWAAgJDCK7AQAjAwAWAAgJDCK7AQAjAwAAAA==.Jarlhun:BAABLgAECn8XAAIJAAYJFhzGCACGAQZoDAAABQBQAGkMAAAFAFAAawwAAAQASgBqDAAAAwBeAGwMAAACAC8A6gwAAAQATAAJAAYJFhzGCACGAQZoDAAABQBQAGkMAAAFAFAAawwAAAQASgBqDAAAAwBeAGwMAAACAC8A6gwAAAQATAABLgAFFAQJDwAWAIwfAA==.',
Je='Jellous:BAACLgAFFH8GAAMaAAIJpQb7WwB2AAJoDAAABAAdAGkMAAACAAQAGgACCQYF+1sAdgACaAwAAAMAFABpDAAAAgAEABsAAQlnC/sNAE4AAWgMAAABAB0ALgAECn8qAAMbAAkJgheTEwA4AgAbAAgJeRiTEwA4AgAaAAkJZBTeMwAqAgAAAA==.Jethereal:BAAALgADCgcJBwABLgAFFAIJBgAaAKUGAA==.',
Ju='Jurista:BAAALgADCgYJBgAAAA==.Justin:BAAALgAECgYJBgAAAA==.',
Ke='Ketharion:BAABLgAECn8rAAMKAAkJ5RWbDgBJAgloDAAABwBaAGkMAAAGADIAawwAAAYAVABqDAAABQAyAGwMAAAFAD0AbQwAAAMAJADqDAAABgBRAG4MAAAEAA4AbwwAAAEAIQAKAAkJ5RWbDgBJAgloDAAABwBaAGkMAAAGADIAawwAAAYAVABqDAAABQAyAGwMAAAFAD0AbQwAAAMAJADqDAAABgBRAG4MAAADAA4AbwwAAAEAIQAHAAEJigs8JQEyAAFuDAAAAQAdAAAA.Kevamin:BAAALgAECgYJEwAAAA==.',
Kh='Khaela:BAAALgAECgIJAgAAAA==.Khato:BAAALgAECggJDAAAAA==.',
Ki='Killya:BAAALgADCgEJAQAAAA==.Kirasha:BAAALgADCgcJBwAAAA==.',
Ku='Kulfa:BAAALgADCgcJCgAAAA==.Kurailos:BAAALgADCggJCAAAAA==.Kurisu:BAAALgAECgQJCAAAAA==.',
La='Lailyne:BAAALgAECgkJEAAAAA==.',
Le='Learned:BAAALgAECggJEwAAAA==.Leo:BAABLgAECn8ZAAIMAAgJRBx1BgA/AghoDAAABABJAGkMAAAEAFsAawwAAAQAWgBqDAAABABTAGwMAAADAFgAbQwAAAEAPwDqDAAABABSAG4MAAABABAADAAICUQcdQYAPwIIaAwAAAQASQBpDAAABABbAGsMAAAEAFoAagwAAAQAUwBsDAAAAwBYAG0MAAABAD8A6gwAAAQAUgBuDAAAAQAQAAAA.Leone:BAAALgAECgYJBwAAAA==.',
Li='Lilany:BAAALgAFFAIJAgAAAA==.Lillymeii:BAAALgAECgEJAQAAAA==.Linova:BAAALgADCgUJBQAAAA==.Lithrak:BAABLgAECn8wAAIcAAkJ0B+8AQDHAgloDAAABwBWAGkMAAAHAFkAawwAAAcAVABqDAAABgBcAGwMAAAGAF8AbQwAAAMAUgDqDAAABgBOAG4MAAAFAE0AbwwAAAEAOQAcAAkJ0B+8AQDHAgloDAAABwBWAGkMAAAHAFkAawwAAAcAVABqDAAABgBcAGwMAAAGAF8AbQwAAAMAUgDqDAAABgBOAG4MAAAFAE0AbwwAAAEAOQAAAA==.',
Lo='Logical:BAAALgAECgEJAQAAAA==.Lorakine:BAAALgADCgUJBQAAAA==.',
Lu='Luciferr:BAAALgADCgEJAQAAAA==.Lucit:BAAALgADCgEJAQABLgAFFAQJCwAEAMIQAA==.Lute:BAAALgAECgQJCAAAAA==.',
Ly='Lyric:BAAALgADCgcJDAABLgAFFAQJCgAOACEWAA==.',
['Lá']='Lárien:BAABLgAECn8XAAIdAAcJsxRsLQCMAQdoDAAABABDAGkMAAAEAEwAawwAAAQANgBqDAAAAwA0AGwMAAADACgAbQwAAAEABQDqDAAABABJAB0ABwmzFGwtAIwBB2gMAAAEAEMAaQwAAAQATABrDAAABAA2AGoMAAADADQAbAwAAAMAKABtDAAAAQAFAOoMAAAEAEkAAAA=.',
Ma='Mable:BAAALgADCggJCAAAAA==.Magicmicah:BAAALgADCgcJBwAAAA==.Manon:BAACLgAFFH8KAAIeAAQJ/Rb/EgBKAQRoDAAAAwBaAGkMAAADAC0AawwAAAEAGwDqDAAAAwBIAB4ABAn9Fv8SAEoBBGgMAAADAFoAaQwAAAMALQBrDAAAAQAbAOoMAAADAEgALgAECn8aAAIeAAcJJhkRLQDWAQAeAAcJJhkRLQDWAQAAAA==.',
Mc='Mcchungus:BAAALgAECgcJDQAAAA==.',
Me='Meliodas:BAAALgAECgQJBgAAAA==.Menghao:BAABLgAECn8UAAMLAAcJQAXiiQASAQdoDAAABQAKAGkMAAADAA4AawwAAAMADQBqDAAAAgARAGwMAAABAAoA6gwAAAUAEwBuDAAAAQAMAAsABwlABeKJABIBB2gMAAADAAoAaQwAAAMADgBrDAAAAwANAGoMAAACABEAbAwAAAEACgDqDAAABAATAG4MAAABAAwAHwACCdwBahoARAACaAwAAAIABADqDAAAAQAEAAAA.Meowmixx:BAAALgAECgcJAwAAAA==.',
Mi='Mikayybrew:BAAALgADCgUJBQAAAA==.Mischief:BAACLgAFFH8FAAIGAAMJZAPCAwDBAANoDAAAAgAGAGkMAAABAAYA6gwAAAIADQAGAAMJZAPCAwDBAANoDAAAAgAGAGkMAAABAAYA6gwAAAIADQAuAAQKfzUAAgYACQlNHesAAKoCAAYACQlNHesAAKoCAAAA.',
Mk='Mk:BAAALgAECgQJCQABLgAECggJNwAYAGsjAA==.',
Mo='Moneyfupa:BAAALgAECgUJBQAAAA==.Mooage:BAACLgAFFH8GAAILAAIJYiDBMwDLAAJoDAAAAwBaAOoMAAADAEsACwACCWIgwTMAywACaAwAAAMAWgDqDAAAAwBLAC4ABAp/MwACCwAJCZwkzgQAOQMACwAJCZwkzgQAOQMAAAA=.Morewyn:BAABLgAECn8eAAIBAAgJVREpMQCkAQhoDAAABABAAGkMAAAFADcAawwAAAUAJwBqDAAABAAcAGwMAAADADwAbQwAAAMAEwDqDAAAAwAvAG4MAAADABcAAQAICVURKTEApAEIaAwAAAQAQABpDAAABQA3AGsMAAAFACcAagwAAAQAHABsDAAAAwA8AG0MAAADABMA6gwAAAMALwBuDAAAAwAXAAAA.Mozoh:BAAALgADCgMJAwABLgAECgIJAgACAAAAAA==.',
Ne='Nerrgall:BAAALgADCgcJBwAAAA==.',
Ni='Nickignomaj:BAAALgAECggJEgABLgAFFAIJBQAWANcQAA==.Nidhogg:BAAALgADCgcJBwABLgAECgkJIQAeANcaAA==.Nisara:BAAALgAECgYJCgAAAA==.',
No='Noellie:BAAALgAFFAEJAgAAAA==.Noobdestroya:BAAALgAECgQJDwAAAA==.Nosfuratu:BAAALgADCgkJCQAAAA==.',
Ny='Nymi:BAAALgADCgYJBgAAAA==.',
Of='Offline:BAAALgADCgcJCwAAAA==.',
Ol='Oldbutcool:BAAALgADCgEJAgAAAA==.',
Om='Omantul:BAABLgAECn8hAAMeAAkJ1xqGIgAQAgloDAAABQBfAGkMAAAFAF8AawwAAAUAXABqDAAAAwAxAGwMAAADAFcAbQwAAAEAKgDqDAAABwBUAG4MAAADACEAbwwAAAEAJAAeAAgJDRqGIgAQAghoDAAAAQBfAGkMAAABAF8AawwAAAIAXABqDAAAAQAxAGwMAAADAFcAbQwAAAEAKgBuDAAAAQAhAG8MAAABACQAGQAGCVAZji8ADgEGaAwAAAQAQQBpDAAABABEAGsMAAADADkAagwAAAIAKwDqDAAABwA4AG4MAAACAEwAAAA=.',
Or='Orangez:BAAALgAECgMJBAAAAA==.',
Ou='Ouija:BAAALgAECgEJAQAAAA==.',
Ow='Owocoxl:BAAALgADCgYJCwABLgAFFAQJDwAgAOAPAA==.',
Pa='Painfull:BAABLgAECn8cAAIaAAgJAB1AKwBTAghoDAAABABUAGkMAAAFAFIAawwAAAQAMABqDAAAAwA7AGwMAAADAFEAbQwAAAIAOwDqDAAABABZAG4MAAADAEoAGgAICQAdQCsAUwIIaAwAAAQAVABpDAAABQBSAGsMAAAEADAAagwAAAMAOwBsDAAAAwBRAG0MAAACADsA6gwAAAQAWQBuDAAAAwBKAAAA.Pants:BAAALgAECgEJAQAAAA==.Paz:BAAALgADCgcJBwABLgAECgIJAgACAAAAAA==.',
Ph='Phakes:BAAALgAECgUJCAAAAA==.Phengzera:BAAALgAECgcJEQAAAA==.Phizz:BAAALgAFFAQJBAAAAA==.',
Po='Po:BAAALgADCgcJDQABLgAFFAUJCwAaAIoQAA==.Pontius:BAAALgADCgMJAwABLgAECgkJDgACAAAAAA==.',
Pr='Prowlborn:BAAALgADCgEJAQAAAA==.',
Pu='Puke:BAABLgAECn8dAAIhAAkJlyG9AAD+AgloDAAABABgAGkMAAAEAF8AawwAAAMAXwBqDAAABABMAGwMAAADAFEAbQwAAAMAUgDqDAAABABXAG4MAAADAEUAbwwAAAEATgAhAAkJlyG9AAD+AgloDAAABABgAGkMAAAEAF8AawwAAAMAXwBqDAAABABMAGwMAAADAFEAbQwAAAMAUgDqDAAABABXAG4MAAADAEUAbwwAAAEATgAAAA==.Pumpkinspice:BAAALgADCgUJBgAAAA==.Purplepower:BAAALgAECgMJBAAAAA==.',
Ra='Rarim:BAAALgAECgkJDgAAAA==.',
Re='Reaperfive:BAAALgADCgcJBwAAAA==.Redbonespur:BAAALgADCgcJBwABLgAECgYJFwAOAF0LAA==.',
Ri='Rimtardo:BAAALgAECgQJBwAAAA==.Rio:BAAALgAECgMJAwABLgAECggJIgAEAOsSAA==.',
Ro='Rotdaddy:BAABLgAECn8aAAIgAAgJ4BGGGQBNAQhoDAAABQA2AGkMAAADADkAawwAAAQAPQBqDAAAAwAnAGwMAAACAC4A6gwAAAUANQBuDAAAAwAlAG8MAAABAAkAIAAICeARhhkATQEIaAwAAAUANgBpDAAAAwA5AGsMAAAEAD0AagwAAAMAJwBsDAAAAgAuAOoMAAAFADUAbgwAAAMAJQBvDAAAAQAJAAAA.Roxxev:BAAALgADCgcJBwAAAA==.',
Ry='Ryø:BAAALgAECgkJDgAAAA==.',
Sa='Saintrandy:BAAALgADCgMJAwAAAA==.',
Sc='Scorch:BAAALgADCgcJCgAAAA==.',
Se='Seraphym:BAAALgADCgYJCAAAAA==.',
Sh='Shaviji:BAAALgAECgcJBwAAAA==.Shinra:BAAALgADCgEJAQAAAA==.Shore:BAAALgAECgkJDgAAAA==.Shrekw:BAAALgAECgYJDwAAAA==.Shuralya:BAACLgAFFH8MAAMHAAMJXxPxNgD4AANoDAAABAA5AGkMAAADABsA6gwAAAUAPwAHAAMJXxPxNgD4AANoDAAAAgA5AGkMAAACABsA6gwAAAIAPwAKAAMJURK5HQDQAANoDAAAAgA3AGkMAAABACIA6gwAAAMAMwAuAAQKfzgAAwcACQnrGwYOAKYCAAcACQnrGwYOAKYCAAoACQk9GH0gABcCAAAA.',
Si='Silverhorn:BAAALgADCgQJBAAAAA==.Siouxsie:BAAALgADCgcJCgAAAA==.',
Sm='Smoldnrg:BAAALgAECgUJBQAAAA==.',
So='Sofka:BAABLgAECn8fAAMiAAkJBw5uGgB+AQloDAAABAApAGkMAAAEADQAawwAAAUAKwBqDAAABABCAGwMAAAEADwAbQwAAAIAJgDqDAAABAAiAG4MAAADAAkAbwwAAAEABgAiAAkJBw5uGgB+AQloDAAABAApAGkMAAAEADQAawwAAAUAKwBqDAAABABCAGwMAAAEADwAbQwAAAIAJgDqDAAAAwAiAG4MAAADAAkAbwwAAAEABgATAAEJMgHwOwEbAAHqDAAAAQADAAAA.Sourpatch:BAAALgAECgIJAgAAAA==.',
St='Stilts:BAAALgAECgUJDQAAAA==.Stradynia:BAAALgAECggJDQAAAA==.Stuart:BAAALgADCgMJAwABLgAECgIJAgACAAAAAA==.Stócky:BAAALgAECgYJDAAAAA==.',
Su='Sui:BAAALgADCgUJCAAAAA==.Survas:BAACLgAFFH8GAAIgAAMJfg4qGADvAANoDAAAAgAxAGkMAAACABwA6gwAAAIAIQAgAAMJfg4qGADvAANoDAAAAgAxAGkMAAACABwA6gwAAAIAIQAuAAQKfx0AAiAACAmqGfocABcCACAACAmqGfocABcCAAAA.',
Sw='Swobu:BAAALgAECgEJAQAAAA==.',
Sy='Sylwynn:BAAALgADCgUJCAAAAA==.',
['Sá']='Sárkány:BAAALgADCgcJCQAAAA==.',
Ta='Talanaz:BAAALgAECgYJDAAAAA==.Taleah:BAAALgAECgEJAgAAAA==.Taleb:BAAALgAECgYJCgAAAA==.Tardor:BAAALgADCgMJAwAAAA==.Tavgoesboom:BAAALgAFFAIJAgABLgAFFAMJBQARAA0UAA==.Tawna:BAAALgAECgQJBQAAAA==.',
Te='Tealan:BAABLgAECn8VAAQNAAgJuRZGKAB7AQhoDAAAAwA4AGkMAAAEAE4AawwAAAMANABqDAAAAwAKAGwMAAACAC4A6gwAAAMAQwBuDAAAAgAYAG8MAAABAFAADQAHCUsVRigAewEHaAwAAAEAOABpDAAAAQBOAGsMAAABADQAagwAAAEACgBsDAAAAQAuAOoMAAACAEMAbgwAAAIAGAAVAAYJmhTVJwA1AQZoDAAAAgAnAGkMAAADADwAawwAAAIAMgBqDAAAAgA9AOoMAAABADUAbwwAAAEAMwAUAAEJOQjJQAAvAAFsDAAAAQAVAAAA.Tenyi:BAAALgAECgMJAwAAAA==.Terrin:BAAALgAECgQJBQABLgAECgYJCgACAAAAAA==.',
To='Toospooky:BAAALgAECgUJCAAAAA==.Tovlacar:BAAALgAECgEJAQABLgAECgkJMAAPAOwPAA==.Toyboy:BAAALgADCgEJAQAAAA==.',
Tr='Triage:BAABLgAECn8UAAQfAAcJbx9sBAAFAgdoDAAABABgAGkMAAAEAFwAawwAAAMAWABqDAAAAgBRAGwMAAADAF8AbQwAAAEAFQDqDAAAAwBYAB8ABQkJJGwEAAUCBWgMAAAEAGAAaQwAAAEAXABrDAAAAQBYAGwMAAACAF8A6gwAAAMAWAALAAQJihie7gAcAQRpDAAAAwBQAGsMAAACAFYAagwAAAIAUQBtDAAAAQAVACMAAQlNFvkKAEQAAWwMAAABADkAAAA=.Trolladin:BAAALgAECgEJAQAAAA==.Tronarn:BAAALgADCgkJEgABLgAECgYJCgACAAAAAA==.',
Ty='Tyrias:BAAALgAECggJAwAAAA==.',
Ug='Ugin:BAABLgAECn8qAAMkAAkJPhf8AgAlAgloDAAABgBDAGkMAAAGAEMAawwAAAYARwBqDAAABQBEAGwMAAAFAC4AbQwAAAMALgDqDAAABgBQAG4MAAAEAEgAbwwAAAEAFwAkAAkJFxb8AgAlAgloDAAAAQBDAGkMAAABAEMAawwAAAEARwBqDAAAAQBEAGwMAAABABYAbQwAAAEALgDqDAAAAQBQAG4MAAACAEgAbwwAAAEAFwATAAgJ6RDuRgCBAQhoDAAABQAzAGkMAAAFAC4AawwAAAUAMQBqDAAABAAkAGwMAAAEAC4AbQwAAAIAHQDqDAAABQA9AG4MAAACABMAAAA=.',
Um='Umaydie:BAAALgAECgIJAwAAAA==.Umbrasyl:BAAALgAECgUJBgAAAA==.',
Un='Unclecharlie:BAAALgAECgUJCQABLgAECggJJAATALchAA==.Unholylukers:BAAALgAECgIJAwAAAA==.Unit:BAAALgADCgcJCwAAAA==.',
Va='Valkrit:BAAALgADCgIJAgAAAA==.Vasrin:BAABLgAECn8qAAIcAAkJBiEtAQD0AgloDAAABgBjAGkMAAAGAFYAawwAAAYAXABqDAAABQBhAGwMAAAFAFsAbQwAAAMAVQDqDAAABgBjAG4MAAAEADEAbwwAAAEASAAcAAkJBiEtAQD0AgloDAAABgBjAGkMAAAGAFYAawwAAAYAXABqDAAABQBhAGwMAAAFAFsAbQwAAAMAVQDqDAAABgBjAG4MAAAEADEAbwwAAAEASAAAAA==.',
Ve='Velaria:BAAALgADCgYJEAABLgAECgYJDAACAAAAAA==.Veon:BAAALgADCgYJBgAAAA==.Verlehn:BAAALgADCgcJBgAAAA==.',
Vo='Voidomo:BAAALgAECgkJEgAAAA==.',
Wa='Walden:BAAALgAECgcJEAAAAA==.Waterlance:BAAALgAECgEJAgAAAA==.',
Wi='Wisecraic:BAAALgADCgcJDQAAAA==.Wispi:BAAALgAECgQJBAAAAA==.',
Wo='Wocoxl:BAACLgAFFH8PAAIgAAQJ4A/qDQAOAQRoDAAABgBDAGkMAAACAB4AbQwAAAEABgDqDAAABgA6ACAABAngD+oNAA4BBGgMAAAGAEMAaQwAAAIAHgBtDAAAAQAGAOoMAAAGADoALgAECn8iAAIgAAkJSB21BgAkAwAgAAkJSB21BgAkAwAAAA==.',
Xe='Xerah:BAAALgADCggJDgAAAA==.',
Ya='Yaracklea:BAAALgAECggJDwAAAA==.',
Yi='Yingu:BAAALgADCgEJAQAAAA==.',
['Yü']='Yüki:BAAALgAECgEJAQAAAA==.',
Za='Zabaniya:BAAALgADCgEJAQAAAA==.Zac:BAAALgADCgYJDAAAAA==.Zacceptable:BAABLgAECn8VAAIfAAcJUhSYBABbAQdoDAAABQBHAGkMAAAEADUAawwAAAQAMQBqDAAAAgApAGwMAAABABwAbQwAAAIAKgDqDAAAAwBDAB8ABwlSFJgEAFsBB2gMAAAFAEcAaQwAAAQANQBrDAAABAAxAGoMAAACACkAbAwAAAEAHABtDAAAAgAqAOoMAAADAEMAAAA=.Zaida:BAAALgADCgUJBQABLgAECgIJAgACAAAAAA==.',
Ze='Zeale:BAABLgAECn8iAAIEAAgJ6xLbLgC9AQhoDAAABQBFAGkMAAAHADgAawwAAAUAKwBqDAAABAA1AGwMAAAFADsAbQwAAAEAJgDqDAAABgA0AG4MAAABABIABAAICesS2y4AvQEIaAwAAAUARQBpDAAABwA4AGsMAAAFACsAagwAAAQANQBsDAAABQA7AG0MAAABACYA6gwAAAYANABuDAAAAQASAAAA.Zenedict:BAAALgAFFAEJAQAAAA==.',
Zh='Zharsha:BAAALgADCgkJCQAAAA==.',
['Áç']='Áçe:BAAALgADCgMJAwAAAA==.',
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
