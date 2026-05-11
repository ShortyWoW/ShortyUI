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

local lookup = {'Hunter-BeastMastery','Unknown-Unknown','Warrior-Fury','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Paladin-Retribution','Paladin-Protection','Hunter-Marksmanship','Paladin-Holy','Mage-Frost','Warrior-Protection','Evoker-Augmentation','Monk-Brewmaster','Priest-Discipline','Priest-Shadow','Monk-Mistweaver','Hunter-Survival','DeathKnight-Unholy','Evoker-Devastation','Evoker-Preservation','Warrior-Arms','Druid-Feral','Monk-Windwalker','Shaman-Elemental','DemonHunter-Devourer','DemonHunter-Havoc','Shaman-Enhancement','Druid-Restoration','Shaman-Restoration','Rogue-Subtlety','DemonHunter-Vengeance','DeathKnight-Blood','Mage-Arcane','Mage-Fire','DeathKnight-Frost',}
local provider = {region='US',realm='Rivendare',name='US',type='daily',zone=46,date='2026-05-10',data={Ai='Aisling:BAAALgADCgYJBgAAAA==.',
Al='Alanispally:BAAALgADCgIJAQAAAA==.Algryn:BAAALgADCgUJBQAAAA==.Alkanz:BAAALgAECgkJDgAAAA==.Allinaa:BAABLgAECn8UAAIBAAgJuw72QACsAQhoDAAAAwAkAGkMAAADADIAawwAAAMANgBqDAAAAwBFAGwMAAACACgAbQwAAAEACwDqDAAAAwAtAG4MAAACABkAAQAICbsO9kAArAEIaAwAAAMAJABpDAAAAwAyAGsMAAADADYAagwAAAMARQBsDAAAAgAoAG0MAAABAAsA6gwAAAMALQBuDAAAAgAZAAAA.',
Am='Amorvea:BAAALgADCgUJBQABLgAECgIJAgACAAAAAA==.',
An='Angron:BAAALgADCgIJBQAAAA==.Anika:BAABLgAECn8qAAIDAAkJdAmxGQCfAQloDAAABgAhAGkMAAAGABMAawwAAAYAGQBqDAAABQAJAGwMAAAFABoAbQwAAAMAEQDqDAAABgAxAG4MAAAEAAsAbwwAAAEACQADAAkJdAmxGQCfAQloDAAABgAhAGkMAAAGABMAawwAAAYAGQBqDAAABQAJAGwMAAAFABoAbQwAAAMAEQDqDAAABgAxAG4MAAAEAAsAbwwAAAEACQAAAA==.',
Ar='Arlyx:BAACLgAFFH8HAAMEAAMJ4A8cSADTAANoDAAAAwAwAGkMAAADADwA6gwAAAEADQAEAAMJ4A8cSADTAANoDAAAAwAwAGkMAAACADwA6gwAAAEADQAFAAEJmw5fFQBUAAFpDAAAAQAlAC4ABAp/HwAEBAAICf4b9jAApQEABAAFCQIe9jAApQEABQADCfMWh0cAmAAABgACCegHNB8AdwAAAAA=.Arnwaz:BAAALgAECgUJCwAAAA==.Arthuria:BAAALgAECggJDAAAAA==.',
As='Aslan:BAAALgADCgQJBwAAAA==.',
At='Atelwen:BAAALgAECgcJBwAAAA==.',
Av='Avelyn:BAAALgAECgMJAwAAAA==.',
Ba='Babyruthie:BAAALgAECgMJBAAAAA==.Baf:BAACLgAFFH8HAAIHAAQJaxfZFwBSAQRoDAAAAgBBAGkMAAACADIAawwAAAEARgDqDAAAAgA1AAcABAlrF9kXAFIBBGgMAAACAEEAaQwAAAIAMgBrDAAAAQBGAOoMAAACADUALgAECn8aAAIHAAcJdx2FPgArAgAHAAcJdx2FPgArAgAAAA==.Bayside:BAAALgAECgYJEQAAAA==.',
Be='Bearfomat:BAAALgAFFAIJAgAAAA==.Beefis:BAAALgAECgUJCwAAAA==.Beenjuicin:BAAALgAFFAEJAQAAAA==.Berfomat:BAABLgAECn8nAAIIAAkJ1CHfAAD4AgloDAAABgBhAGkMAAAGAF8AawwAAAYAUQBqDAAABQBcAGwMAAAEAGEAbQwAAAMAYQDqDAAABQBdAG4MAAADAEkAbwwAAAEAOAAIAAkJ1CHfAAD4AgloDAAABgBhAGkMAAAGAF8AawwAAAYAUQBqDAAABQBcAGwMAAAEAGEAbQwAAAMAYQDqDAAABQBdAG4MAAADAEkAbwwAAAEAOAAAAA==.',
Bi='Bingchilling:BAACLgAFFH8SAAIJAAUJyRLkCgBrAQVoDAAABQA4AGkMAAAEAEwAawwAAAQADgBqDAAAAQAIAOoMAAAEAC0ACQAFCckS5AoAawEFaAwAAAUAOABpDAAABABMAGsMAAAEAA4AagwAAAEACADqDAAABAAtAC4ABAp/IwACCQAJCVAbBgwA6gIACQAJCVAbBgwA6gIAAAA=.',
Bj='Bjorn:BAAALgAFFAEJAQAAAA==.',
Bl='Bloomyvfd:BAABLgAECn8YAAIKAAYJVB4PFAD9AQZoDAAABQBQAGkMAAAFAEsAawwAAAQARABqDAAAAwBSAGwMAAAEAEsA6gwAAAMAUQAKAAYJVB4PFAD9AQZoDAAABQBQAGkMAAAFAEsAawwAAAQARABqDAAAAwBSAGwMAAAEAEsA6gwAAAMAUQAAAA==.',
Bo='Bonniebadass:BAAALgAECgYJEwAAAA==.Bottle:BAAALgAECgcJDAAAAA==.Boxxylove:BAAALgAECgQJBAAAAA==.',
Br='Bravas:BAAALgAECgcJBQAAAA==.Brimscythe:BAAALgADCgQJBAAAAA==.Broxar:BAAALgADCgcJCwAAAA==.',
['Bî']='Bîa:BAABLgAECn8VAAIHAAcJjiBaGQA8AgdoDAAABABeAGkMAAAEAFEAawwAAAMAOgBqDAAAAwBiAGwMAAACAFEA6gwAAAQAXwBuDAAAAQBXAAcABwmOIFoZADwCB2gMAAAEAF4AaQwAAAQAUQBrDAAAAwA6AGoMAAADAGIAbAwAAAIAUQDqDAAABABfAG4MAAABAFcAAAA=.',
Ca='Cablemstache:BAAALgADCgcJBwAAAA==.Calisti:BAABLgAECn8lAAILAAcJtxrTZgAJAgdoDAAACABRAGkMAAAHAEoAawwAAAcAUQBqDAAABQA1AGwMAAAEAEEAbQwAAAIAGADqDAAABABRAAsABwm3GtNmAAkCB2gMAAAIAFEAaQwAAAcASgBrDAAABwBRAGoMAAAFADUAbAwAAAQAQQBtDAAAAgAYAOoMAAAEAFEAAAA=.Cavalis:BAABLgAECn8qAAQEAAkJ6hilIwDjAQloDAAABgBLAGkMAAAGAEgAawwAAAYAUQBqDAAABQBGAGwMAAAFAFEAbQwAAAMAMgDqDAAABgAuAG4MAAAEADIAbwwAAAEANQAEAAgJRhelIwDjAQhoDAAAAwBDAGkMAAAFAEMAagwAAAIAQwBsDAAABQBRAG0MAAADADIA6gwAAAUALgBuDAAABAAyAG8MAAABADUABgAECU0YshIAAQEEaAwAAAMASwBpDAAAAQBIAGoMAAABAB0A6gwAAAEAJwAFAAIJqx9YRwCZAAJrDAAABgBRAGoMAAACAEYAAAA=.',
Ce='Ceedh:BAAALgAFFAMJBAAAAA==.Ceejr:BAACLgAFFH8YAAMDAAcJtyKkAQDoAQdoDAAABgBaAGkMAAAEAFsAawwAAAMAYABqDAAAAwA3AGwMAAACAFcAbQwAAAEAWADqDAAABQBPAAMABQnmIqQBAOgBBWgMAAAFAFoAaQwAAAQAWwBrDAAAAwBgAGoMAAADADcA6gwAAAQATwAMAAQJkiCnBAB2AQRoDAAAAQBXAGwMAAACAFcAbQwAAAEAWADqDAAAAQBGAC4ABAp/IAACAwAJCWklIwEAxAMAAwAJCWklIwEAxAMAAAA=.Cerovallen:BAAALgAECgYJCQAAAA==.',
Ch='Chailee:BAAALgADCgEJAQAAAA==.Cherish:BAAALgADCgMJAwABLgAECgUJCgACAAAAAA==.Chillum:BAAALgAECgIJAgABLgAFFAQJBwANAKsNAA==.Chimneybeans:BAAALgADCgcJBwAAAA==.',
Co='Corny:BAAALgAECgUJCwAAAA==.',
Cr='Creativez:BAABLgAFFH8GAAIOAAIJNRmyGACoAAJoDAAAAgBQAOoMAAAEADAADgACCTUZshgAqAACaAwAAAIAUADqDAAABAAwAAAA.',
Da='Damnskippy:BAAALgAECgMJBQAAAA==.Dannÿ:BAABLgAECn8cAAMPAAcJnhW2FwCHAQdoDAAABQA8AGkMAAAFADgAawwAAAUALQBqDAAABABKAGwMAAADADcAbQwAAAEAIgDqDAAABQA7AA8ABgn6FrYXAIcBBmgMAAAFADwAaQwAAAUAOABrDAAABQAtAGoMAAAEAEoAbAwAAAMANwDqDAAABQA7ABAAAQlMCkZaAC8AAW0MAAABABoAAAA=.Dantè:BAAALgAECgIJAgAAAA==.Daris:BAAALgADCgMJAwAAAA==.Darkire:BAABLgAECn8hAAIBAAgJYBnKNQB5AQhoDAAABQBfAGkMAAAGAFAAawwAAAYARwBqDAAABAA6AGwMAAADADsAbQwAAAEACQDqDAAABwBKAG4MAAABAEAAAQAICWAZyjUAeQEIaAwAAAUAXwBpDAAABgBQAGsMAAAGAEcAagwAAAQAOgBsDAAAAwA7AG0MAAABAAkA6gwAAAcASgBuDAAAAQBAAAAA.Darkstar:BAAALgADCgUJBQAAAA==.Darkwarriorx:BAAALgADCgQJAgAAAA==.',
De='Deathlegion:BAAALgAECgQJBAAAAA==.Deathroll:BAABLgAECn8mAAIRAAkJrRVYDAAwAgloDAAABwBKAGkMAAAGAEoAawwAAAYAQABqDAAABQA/AGwMAAAFADUAbQwAAAMAJwDqDAAABABGAG4MAAABABEAbwwAAAEAKwARAAkJrRVYDAAwAgloDAAABwBKAGkMAAAGAEoAawwAAAYAQABqDAAABQA/AGwMAAAFADUAbQwAAAMAJwDqDAAABABGAG4MAAABABEAbwwAAAEAKwAAAA==.Delarus:BAAALgAECgEJAQAAAA==.Demonarmor:BAAALgAECgMJCAABLgAECgcJCAACAAAAAA==.',
Di='Diddley:BAAALgADCgMJAwAAAA==.',
Do='Dogmatik:BAAALgAECgEJAQABLgAECgMJAwACAAAAAA==.Dontah:BAAALgADCgcJBwABLgAECgkJIgASAI0gAA==.Doomward:BAABLgAECn8VAAITAAYJUBSmWQA+AQZoDAAABQA+AGkMAAAFADQAawwAAAQAPgBqDAAAAgBUAGwMAAACABwA6gwAAAMANgATAAYJUBSmWQA+AQZoDAAABQA+AGkMAAAFADQAawwAAAQAPgBqDAAAAgBUAGwMAAACABwA6gwAAAMANgAAAA==.Dorien:BAABLgAECn8iAAMSAAkJjSCWAQD8AgloDAAABgBhAGkMAAAFAGAAawwAAAUAVABqDAAAAwBcAGwMAAADAEcAbQwAAAIAVgDqDAAABgBdAG4MAAADAEgAbwwAAAEAPwASAAkJjSCWAQD8AgloDAAABgBhAGkMAAAFAGAAawwAAAUAVABqDAAAAwBcAGwMAAADAEcAbQwAAAIAVgDqDAAABgBdAG4MAAACAEgAbwwAAAEAPwABAAEJlgdWvAA1AAFuDAAAAQATAAAA.',
Dr='Drachilly:BAACLgAFFH8HAAINAAQJqw3qGAApAQRoDAAAAgAyAGkMAAACAAwAawwAAAEAIwDqDAAAAgAqAA0ABAmrDeoYACkBBGgMAAACADIAaQwAAAIADABrDAAAAQAjAOoMAAACACoALgAECn8cAAQNAAgJKB6WEQDMAQAUAAYJ9x0+EADYAQANAAgJkh2WEQDMAQAVAAEJDwJ5MAAbAAAAAA==.Dragnar:BAABLgAECn8jAAIBAAkJlwzrPQC3AQloDAAABQArAGkMAAAFADQAawwAAAUALgBqDAAABAAWAGwMAAAEADQAbQwAAAIABQDqDAAABgAZAG4MAAADABAAbwwAAAEADgABAAkJlwzrPQC3AQloDAAABQArAGkMAAAFADQAawwAAAUALgBqDAAABAAWAGwMAAAEADQAbQwAAAIABQDqDAAABgAZAG4MAAADABAAbwwAAAEADgAAAA==.Drhealzgood:BAAALgADCgYJBgAAAA==.Droggo:BAAALgADCgIJAgAAAA==.',
Ev='Evilvdduck:BAAALgAECgEJAQAAAA==.',
Fa='Faewryn:BAAALgAECgkJCgAAAA==.Faeya:BAAALgADCgEJAQABLgADCgUJCAACAAAAAA==.Falekia:BAAALgAECgEJAQAAAA==.Fay:BAACLgAFFH8HAAIOAAQJIRZuEgAuAQRoDAAAAgA7AGkMAAACAD8AawwAAAEAMQDqDAAAAgA2AA4ABAkhFm4SAC4BBGgMAAACADsAaQwAAAIAPwBrDAAAAQAxAOoMAAACADYALgAECn8cAAIOAAgJySFJDwDdAQAOAAgJySFJDwDdAQAAAA==.',
Fe='Felltown:BAAALgADCgMJAwAAAA==.',
Fi='Firstblood:BAAALgAECgYJCQAAAA==.Fishnchimps:BAAALgAFFAMJAwAAAA==.',
Fu='Furrburger:BAAALgADCgIJAgAAAA==.',
Ga='Gaiserik:BAABLgAECn8fAAIWAAcJvh+DBQAnAgdoDAAABQBbAGkMAAAGAFcAawwAAAYAUwBqDAAABgBeAGwMAAADAEYAbQwAAAEASgDqDAAABABQABYABwm+H4MFACcCB2gMAAAFAFsAaQwAAAYAVwBrDAAABgBTAGoMAAAGAF4AbAwAAAMARgBtDAAAAQBKAOoMAAAEAFAAAAA=.Galenda:BAAALgADCgQJBQAAAA==.Gandolph:BAAALgADCgEJAQAAAA==.Garduhm:BAAALgADCgYJCQABLgAECgIJAgACAAAAAA==.Garlictoast:BAAALgAECgQJBwAAAA==.',
Ge='Gearsofhate:BAAALgAECgEJAgAAAA==.Gehenna:BAAALgADCgYJCgAAAA==.',
Go='Goldenorder:BAAALgAECgEJAgAAAA==.Gome:BAAALgADCgcJGwABLgAFFAMJAwACAAAAAA==.',
Gr='Gracile:BAAALgADCgEJAQAAAA==.Gragolf:BAABLgAECn8cAAIBAAgJzhTdKQCsAQhoDAAABQA/AGkMAAAFAEUAawwAAAQAQgBqDAAABABOAGwMAAADAEcAbQwAAAEAFQDqDAAABQA8AG4MAAABABMAAQAICc4U3SkArAEIaAwAAAUAPwBpDAAABQBFAGsMAAAEAEIAagwAAAQATgBsDAAAAwBHAG0MAAABABUA6gwAAAUAPABuDAAAAQATAAAA.Greggor:BAAALgAECgYJDQAAAA==.Gronkus:BAAALgAECgYJBwAAAA==.',
Gu='Gustabo:BAABLgAECn8bAAIXAAYJGyLzBQD7AQZoDAAABQBUAGkMAAAGAFYAawwAAAQAXABqDAAABABNAGwMAAADAFUA6gwAAAUAVgAXAAYJGyLzBQD7AQZoDAAABQBUAGkMAAAGAFYAawwAAAQAXABqDAAABABNAGwMAAADAFUA6gwAAAUAVgAAAA==.',
Ha='Havibonespur:BAABLgAECn8XAAMOAAYJXQsvLgDrAAZoDAAABAAlAGkMAAAEABEAawwAAAQAGwBqDAAABAA7AGwMAAADAB0A6gwAAAQAIAAOAAYJXQsvLgDrAAZoDAAABAAlAGkMAAAEABEAawwAAAQAGwBqDAAABAA7AGwMAAACAB0A6gwAAAQAIAAYAAEJyQQicgAjAAFsDAAAAQAMAAAA.',
He='Healir:BAAALgAECggJEwAAAA==.Healmepls:BAAALgADCgYJCgABLgAFFAUJDAAZAHcPAA==.Hellsong:BAAALgAECgEJAQAAAA==.Helor:BAABLgAECn8XAAMaAAkJcRZiHADnAQloDAAABABSAGkMAAADAE4AawwAAAIAVABqDAAAAgBTAGwMAAADAE8AbQwAAAMAHQDqDAAABABRAG4MAAABAAUAbwwAAAEAEQAaAAkJcRZiHADnAQloDAAAAwBSAGkMAAACAE4AawwAAAEAVABqDAAAAQBTAGwMAAADAE8AbQwAAAMAHQDqDAAAAwBRAG4MAAABAAUAbwwAAAEAEQAbAAUJ3RXALgBXAQVoDAAAAQA/AGkMAAABAEAAawwAAAEAIgBqDAAAAQBLAOoMAAABADwAAAA=.',
Ho='Holydeath:BAAALgAECgYJCwAAAA==.Hotpocketz:BAAALgADCgcJCQABLgAECggJFwADACoXAA==.',
Hu='Hunterish:BAAALgADCgEJAQAAAA==.',
Ia='Iadrithe:BAAALgADCgYJBgAAAA==.',
In='Inspectadeck:BAAALgAECgMJBAAAAA==.Invisus:BAAALgAECgYJCAAAAA==.',
Is='Ispayderj:BAAALgAECgMJBAAAAA==.',
Ja='Jahy:BAAALgADCgIJAgAAAA==.Jake:BAABLgAECn8fAAIHAAkJyiXrAwAeAwloDAAABABeAGkMAAAEAGMAawwAAAQAXQBqDAAABABhAGwMAAAEAGIAbQwAAAMAYwDqDAAABABjAG4MAAADAF8AbwwAAAEAXgAHAAkJyiXrAwAeAwloDAAABABeAGkMAAAEAGMAawwAAAQAXQBqDAAABABhAGwMAAAEAGIAbQwAAAMAYwDqDAAABABjAG4MAAADAF8AbwwAAAEAXgAAAA==.Jarlan:BAACLgAFFH8LAAIWAAQJjB82BAB0AQRoDAAABABcAGkMAAAEAGAAawwAAAEAJQDqDAAAAgBgABYABAmMHzYEAHQBBGgMAAAEAFwAaQwAAAQAYABrDAAAAQAlAOoMAAACAGAALgAECn8hAAIWAAgJDCK7AQAjAwAWAAgJDCK7AQAjAwAAAA==.Jarlhun:BAABLgAECn8XAAIJAAYJFhwHCACLAQZoDAAABQBQAGkMAAAFAFAAawwAAAQASgBqDAAAAwBeAGwMAAACAC8A6gwAAAQATAAJAAYJFhwHCACLAQZoDAAABQBQAGkMAAAFAFAAawwAAAQASgBqDAAAAwBeAGwMAAACAC8A6gwAAAQATAABLgAFFAQJCwAWAIwfAA==.',
Je='Jellous:BAACLgAFFH8GAAMaAAIJpQbLVQB2AAJoDAAABAAdAGkMAAACAAQAGgACCQYFy1UAdgACaAwAAAMAFABpDAAAAgAEABsAAQlnC/sNAE4AAWgMAAABAB0ALgAECn8qAAMbAAkJgheREwA4AgAbAAgJeRiREwA4AgAaAAkJZBTbMwAqAgAAAA==.Jethereal:BAAALgADCgcJBwABLgAFFAIJBgAaAKUGAA==.',
Ju='Jurista:BAAALgADCgYJBgAAAA==.Justin:BAAALgAECgYJBgAAAA==.',
Ke='Ketharion:BAABLgAECn8iAAIKAAgJOxbyEgAIAghoDAAABgBaAGkMAAAFADIAawwAAAUAVABqDAAABAAyAGwMAAAEAD0AbQwAAAIAFQDqDAAABQBRAG4MAAADAA4ACgAICTsW8hIACAIIaAwAAAYAWgBpDAAABQAyAGsMAAAFAFQAagwAAAQAMgBsDAAABAA9AG0MAAACABUA6gwAAAUAUQBuDAAAAwAOAAAA.Kevamin:BAAALgAECgUJDgAAAA==.',
Kh='Khaela:BAAALgAECgIJAgAAAA==.Khato:BAAALgAECggJDAAAAA==.',
Ki='Killya:BAAALgADCgEJAQAAAA==.Kirasha:BAAALgADCgcJBwAAAA==.',
Ku='Kulfa:BAAALgADCgcJCgAAAA==.Kurailos:BAAALgADCggJCAAAAA==.Kurisu:BAAALgAECgQJCAAAAA==.',
La='Lailyne:BAAALgAECgkJEAAAAA==.',
Le='Learned:BAAALgAECggJEwAAAA==.Leo:BAABLgAECn8ZAAIMAAgJRByTBQBLAghoDAAABABJAGkMAAAEAFsAawwAAAQAWgBqDAAABABTAGwMAAADAFgAbQwAAAEAPwDqDAAABABSAG4MAAABABAADAAICUQckwUASwIIaAwAAAQASQBpDAAABABbAGsMAAAEAFoAagwAAAQAUwBsDAAAAwBYAG0MAAABAD8A6gwAAAQAUgBuDAAAAQAQAAAA.Leone:BAAALgAECgYJBwAAAA==.',
Li='Lilany:BAAALgAFFAIJAgAAAA==.Lillymeii:BAAALgAECgEJAQAAAA==.Linova:BAAALgADCgUJBQAAAA==.Lithrak:BAABLgAECn8wAAIcAAkJ0B9UAQDUAgloDAAABwBWAGkMAAAHAFkAawwAAAcAVABqDAAABgBcAGwMAAAGAF8AbQwAAAMAUgDqDAAABgBOAG4MAAAFAE0AbwwAAAEAOQAcAAkJ0B9UAQDUAgloDAAABwBWAGkMAAAHAFkAawwAAAcAVABqDAAABgBcAGwMAAAGAF8AbQwAAAMAUgDqDAAABgBOAG4MAAAFAE0AbwwAAAEAOQAAAA==.',
Lo='Logical:BAAALgAECgEJAQAAAA==.Lorakine:BAAALgADCgUJBQAAAA==.',
Lu='Luciferr:BAAALgADCgEJAQAAAA==.Lucit:BAAALgADCgEJAQABLgAFFAMJBwAEAOAPAA==.Lute:BAAALgAECgQJCAAAAA==.',
Ly='Lyric:BAAALgADCgcJDAABLgAFFAQJBwAOACEWAA==.',
['Lá']='Lárien:BAABLgAECn8XAAIdAAcJsxSaKgCLAQdoDAAABABDAGkMAAAEAEwAawwAAAQANgBqDAAAAwA0AGwMAAADACgAbQwAAAEABQDqDAAABABJAB0ABwmzFJoqAIsBB2gMAAAEAEMAaQwAAAQATABrDAAABAA2AGoMAAADADQAbAwAAAMAKABtDAAAAQAFAOoMAAAEAEkAAAA=.',
Ma='Mable:BAAALgADCggJCAAAAA==.Magicmicah:BAAALgADCgcJBwAAAA==.Manon:BAACLgAFFH8HAAIeAAQJrRJIGAAYAQRoDAAAAgAxAGkMAAACAC0AawwAAAEAGwDqDAAAAgBFAB4ABAmtEkgYABgBBGgMAAACADEAaQwAAAIALQBrDAAAAQAbAOoMAAACAEUALgAECn8aAAIeAAcJJhkPLQDWAQAeAAcJJhkPLQDWAQAAAA==.',
Mc='Mcchungus:BAAALgAECgcJDQAAAA==.',
Me='Meliodas:BAAALgAECgQJBgAAAA==.Menghao:BAAALgAECgYJDwAAAA==.Meowmixx:BAAALgAECgcJAwAAAA==.',
Mi='Mikayybrew:BAAALgADCgUJBQAAAA==.Mischief:BAABLgAECn8uAAIGAAkJxBk+AQBvAgloDAAABgBPAGkMAAAFAFgAawwAAAUAWgBqDAAABgA3AGwMAAAGAEAAbQwAAAUAIADqDAAABwBNAG4MAAAEADwAbwwAAAIAIQAGAAkJxBk+AQBvAgloDAAABgBPAGkMAAAFAFgAawwAAAUAWgBqDAAABgA3AGwMAAAGAEAAbQwAAAUAIADqDAAABwBNAG4MAAAEADwAbwwAAAIAIQAAAA==.',
Mk='Mk:BAEALgAECgQJCQABLgAECggJMAAYAA4jAA==.',
Mo='Moneyfupa:BAAALgAECgUJBQAAAA==.Mooage:BAACLgAFFH8GAAILAAIJYiC9MwDLAAJoDAAAAwBaAOoMAAADAEsACwACCWIgvTMAywACaAwAAAMAWgDqDAAAAwBLAC4ABAp/MwACCwAJCZwkIgQAPQMACwAJCZwkIgQAPQMAAAA=.Morewyn:BAABLgAECn8eAAIBAAgJVRFlLQCcAQhoDAAABABAAGkMAAAFADcAawwAAAUAJwBqDAAABAAcAGwMAAADADwAbQwAAAMAEwDqDAAAAwAvAG4MAAADABcAAQAICVURZS0AnAEIaAwAAAQAQABpDAAABQA3AGsMAAAFACcAagwAAAQAHABsDAAAAwA8AG0MAAADABMA6gwAAAMALwBuDAAAAwAXAAAA.Mozoh:BAAALgADCgMJAwABLgAECgIJAgACAAAAAA==.',
Ne='Nerrgall:BAAALgADCgcJBwAAAA==.',
Ni='Nickignomaj:BAAALgAECggJEgABLgAFFAIJBQAWANcQAA==.Nidhogg:BAAALgADCgcJBwABLgAECgkJIQAeANcaAA==.Nisara:BAAALgAECgYJCgAAAA==.',
No='Noellie:BAAALgAFFAEJAQAAAA==.Noobdestroya:BAAALgAECgQJDwAAAA==.Nosfuratu:BAAALgADCgkJCQAAAA==.',
Ny='Nymi:BAAALgADCgYJBgAAAA==.',
Of='Offline:BAAALgADCgcJCwAAAA==.',
Ol='Oldbutcool:BAAALgADCgEJAgAAAA==.',
Om='Omantul:BAABLgAECn8hAAMeAAkJ1xqGIgAQAgloDAAABQBfAGkMAAAFAF8AawwAAAUAXABqDAAAAwAxAGwMAAADAFcAbQwAAAEAKgDqDAAABwBUAG4MAAADACEAbwwAAAEAJAAeAAgJDRqGIgAQAghoDAAAAQBfAGkMAAABAF8AawwAAAIAXABqDAAAAQAxAGwMAAADAFcAbQwAAAEAKgBuDAAAAQAhAG8MAAABACQAGQAGCVAZRSwAEgEGaAwAAAQAQQBpDAAABABEAGsMAAADADkAagwAAAIAKwDqDAAABwA4AG4MAAACAEwAAAA=.',
Or='Orangez:BAAALgAECgMJBAAAAA==.',
Ou='Ouija:BAAALgAECgEJAQAAAA==.',
Ow='Owocoxl:BAAALgADCgYJCwABLgAFFAQJDQAfAOAPAA==.',
Pa='Painfull:BAABLgAECn8cAAIaAAgJAB0+KwBTAghoDAAABABUAGkMAAAFAFIAawwAAAQAMABqDAAAAwA7AGwMAAADAFEAbQwAAAIAOwDqDAAABABZAG4MAAADAEoAGgAICQAdPisAUwIIaAwAAAQAVABpDAAABQBSAGsMAAAEADAAagwAAAMAOwBsDAAAAwBRAG0MAAACADsA6gwAAAQAWQBuDAAAAwBKAAAA.Pants:BAAALgAECgEJAQAAAA==.Paz:BAAALgADCgcJBwABLgAECgIJAgACAAAAAA==.',
Ph='Phakes:BAAALgAECgUJCAAAAA==.Phengzera:BAAALgAECgcJEQAAAA==.Phizz:BAAALgAFFAQJBAAAAA==.',
Po='Po:BAAALgADCgcJDQABLgAFFAUJCwAaAIoQAA==.Pontius:BAAALgADCgMJAwABLgAECgkJDgACAAAAAA==.',
Pr='Prowlborn:BAAALgADCgEJAQAAAA==.',
Pu='Puke:BAABLgAECn8dAAIgAAkJlyGPAAABAwloDAAABABgAGkMAAAEAF8AawwAAAMAXwBqDAAABABMAGwMAAADAFEAbQwAAAMAUgDqDAAABABXAG4MAAADAEUAbwwAAAEATgAgAAkJlyGPAAABAwloDAAABABgAGkMAAAEAF8AawwAAAMAXwBqDAAABABMAGwMAAADAFEAbQwAAAMAUgDqDAAABABXAG4MAAADAEUAbwwAAAEATgAAAA==.Pumpkinspice:BAAALgADCgUJBgAAAA==.Purplepower:BAAALgAECgMJBAAAAA==.',
Ra='Rarim:BAAALgAECgkJDgAAAA==.',
Re='Reaperfive:BAAALgADCgcJBwAAAA==.Redbonespur:BAAALgADCgcJBwABLgAECgYJFwAOAF0LAA==.',
Ri='Rimtardo:BAAALgAECgQJBwAAAA==.Rio:BAAALgAECgMJAwABLgAECggJHAAEALkRAA==.',
Ro='Rotdaddy:BAABLgAECn8aAAIfAAgJ4BFdFwBUAQhoDAAABQA2AGkMAAADADkAawwAAAQAPQBqDAAAAwAnAGwMAAACAC4A6gwAAAUANQBuDAAAAwAlAG8MAAABAAkAHwAICeARXRcAVAEIaAwAAAUANgBpDAAAAwA5AGsMAAAEAD0AagwAAAMAJwBsDAAAAgAuAOoMAAAFADUAbgwAAAMAJQBvDAAAAQAJAAAA.Roxxev:BAAALgADCgcJBwAAAA==.',
Ry='Ryø:BAAALgAECgkJDgAAAA==.',
Sa='Saintrandy:BAAALgADCgMJAwAAAA==.',
Sc='Scorch:BAAALgADCgcJCgAAAA==.',
Se='Seraphym:BAAALgADCgYJCAAAAA==.',
Sh='Shinra:BAAALgADCgEJAQAAAA==.Shore:BAAALgAECgkJDgAAAA==.Shrekw:BAAALgAECgYJDAAAAA==.Shuralya:BAACLgAFFH8LAAMHAAMJXxPpMQD8AANoDAAABAA5AGkMAAADABsA6gwAAAQAPwAHAAMJXxPpMQD8AANoDAAAAgA5AGkMAAACABsA6gwAAAIAPwAKAAMJURLIGgDdAANoDAAAAgA3AGkMAAABACIA6gwAAAIAMwAuAAQKfzYAAwcACQkoG90NAJkCAAcACQkoG90NAJkCAAoACQk7GH0gABcCAAAA.',
Si='Silverhorn:BAAALgADCgQJBAAAAA==.Siouxsie:BAAALgADCgcJCgAAAA==.',
Sm='Smoldnrg:BAAALgAECgUJBQAAAA==.',
So='Sofka:BAABLgAECn8fAAMhAAkJBw5sGgB+AQloDAAABAApAGkMAAAEADQAawwAAAUAKwBqDAAABABCAGwMAAAEADwAbQwAAAIAJgDqDAAABAAiAG4MAAADAAkAbwwAAAEABgAhAAkJBw5sGgB+AQloDAAABAApAGkMAAAEADQAawwAAAUAKwBqDAAABABCAGwMAAAEADwAbQwAAAIAJgDqDAAAAwAiAG4MAAADAAkAbwwAAAEABgATAAEJMgHwOwEbAAHqDAAAAQADAAAA.Sourpatch:BAAALgAECgIJAgAAAA==.',
St='Stilts:BAAALgAECgUJDQAAAA==.Stradynia:BAAALgAECggJDQAAAA==.Stuart:BAAALgADCgMJAwABLgAECgIJAgACAAAAAA==.Stócky:BAAALgAECgYJDAAAAA==.',
Su='Sui:BAAALgADCgUJCAAAAA==.Survas:BAABLgAECn8dAAIfAAgJqhn5HAAXAghoDAAABQBIAGkMAAAFAEkAawwAAAUAPwBqDAAAAwA7AGwMAAACAFcAbQwAAAIAGwDqDAAABgBKAG4MAAABADwAHwAICaoZ+RwAFwIIaAwAAAUASABpDAAABQBJAGsMAAAFAD8AagwAAAMAOwBsDAAAAgBXAG0MAAACABsA6gwAAAYASgBuDAAAAQA8AAAA.',
Sw='Swobu:BAAALgAECgEJAQAAAA==.',
Sy='Sylwynn:BAAALgADCgUJCAAAAA==.',
['Sá']='Sárkány:BAAALgADCgcJCQAAAA==.',
Ta='Talanaz:BAAALgAECgYJDAAAAA==.Taleah:BAAALgAECgEJAgAAAA==.Taleb:BAAALgAECgYJCgAAAA==.Tardor:BAAALgADCgMJAwAAAA==.Tavgoesboom:BAAALgAFFAIJAgABLgAFFAMJAwACAAAAAA==.Tawna:BAAALgAECgQJBQAAAA==.',
Te='Tealan:BAABLgAECn8UAAQNAAcJSxVAKAB7AQdoDAAAAwA4AGkMAAAEAE4AawwAAAMANABqDAAAAwAKAGwMAAACAC4A6gwAAAMAQwBuDAAAAgAYAA0ABwlLFUAoAHsBB2gMAAABADgAaQwAAAEATgBrDAAAAQA0AGoMAAABAAoAbAwAAAEALgDqDAAAAgBDAG4MAAACABgAFQAFCawU1CcANQEFaAwAAAIAJwBpDAAAAwA8AGsMAAACADIAagwAAAIAPQDqDAAAAQA1ABQAAQk5CMpAAC8AAWwMAAABABUAAAA=.Tenyi:BAAALgAECgMJAwAAAA==.Terrin:BAAALgAECgQJBQABLgAECgYJCgACAAAAAA==.',
To='Toospooky:BAAALgAECgUJCAAAAA==.Tovlacar:BAAALgAECgEJAQABLgAECgkJMAAPAOwPAA==.Toyboy:BAAALgADCgEJAQAAAA==.',
Tr='Triage:BAABLgAECn8UAAQiAAcJbx9sBAAFAgdoDAAABABgAGkMAAAEAFwAawwAAAMAWABqDAAAAgBRAGwMAAADAF8AbQwAAAEAFQDqDAAAAwBYACIABQkJJGwEAAUCBWgMAAAEAGAAaQwAAAEAXABrDAAAAQBYAGwMAAACAF8A6gwAAAMAWAALAAQJihib7gAcAQRpDAAAAwBQAGsMAAACAFYAagwAAAIAUQBtDAAAAQAVACMAAQlNFmsKAEQAAWwMAAABADkAAAA=.Trolladin:BAAALgAECgEJAQAAAA==.Tronarn:BAAALgADCgkJCQABLgAECgYJCgACAAAAAA==.',
Ty='Tyrias:BAAALgAECggJAwAAAA==.',
Ug='Ugin:BAABLgAECn8qAAMkAAkJPhdQAgA3AgloDAAABgBDAGkMAAAGAEMAawwAAAYARwBqDAAABQBEAGwMAAAFAC4AbQwAAAMALgDqDAAABgBQAG4MAAAEAEgAbwwAAAEAFwAkAAkJFxZQAgA3AgloDAAAAQBDAGkMAAABAEMAawwAAAEARwBqDAAAAQBEAGwMAAABABYAbQwAAAEALgDqDAAAAQBQAG4MAAACAEgAbwwAAAEAFwATAAgJ6RDiQACFAQhoDAAABQAzAGkMAAAFAC4AawwAAAUAMQBqDAAABAAkAGwMAAAEAC4AbQwAAAIAHQDqDAAABQA9AG4MAAACABMAAAA=.',
Um='Umaydie:BAAALgAECgIJAwAAAA==.Umbrasyl:BAAALgAECgUJBgAAAA==.',
Un='Unclecharlie:BAAALgAECgUJCQABLgAECggJJAATALchAA==.Unholylukers:BAAALgAECgIJAwAAAA==.Unit:BAAALgADCgcJCwAAAA==.',
Va='Valkrit:BAAALgADCgIJAgAAAA==.Vasrin:BAABLgAECn8qAAIcAAkJBiHfAAD/AgloDAAABgBjAGkMAAAGAFYAawwAAAYAXABqDAAABQBhAGwMAAAFAFsAbQwAAAMAVQDqDAAABgBjAG4MAAAEADEAbwwAAAEASAAcAAkJBiHfAAD/AgloDAAABgBjAGkMAAAGAFYAawwAAAYAXABqDAAABQBhAGwMAAAFAFsAbQwAAAMAVQDqDAAABgBjAG4MAAAEADEAbwwAAAEASAAAAA==.',
Ve='Velaria:BAAALgADCgYJEAABLgAECgYJDAACAAAAAA==.Veon:BAAALgADCgYJBgAAAA==.Verlehn:BAAALgADCgcJBgAAAA==.',
Vo='Voidomo:BAAALgAECgkJEgAAAA==.',
Wa='Walden:BAAALgAECgcJEAAAAA==.Waterlance:BAAALgAECgEJAgAAAA==.',
Wi='Wisecraic:BAAALgADCgcJDQAAAA==.Wispi:BAAALgAECgQJBAAAAA==.',
Wo='Wocoxl:BAACLgAFFH8NAAIfAAQJ4A/nDQAOAQRoDAAABQBDAGkMAAACAB4AbQwAAAEABgDqDAAABQA6AB8ABAngD+cNAA4BBGgMAAAFAEMAaQwAAAIAHgBtDAAAAQAGAOoMAAAFADoALgAECn8iAAIfAAkJSB20BgAkAwAfAAkJSB20BgAkAwAAAA==.',
Xe='Xerah:BAAALgADCggJDgAAAA==.',
Ya='Yaracklea:BAAALgAECggJDwAAAA==.',
Yi='Yingu:BAAALgADCgEJAQAAAA==.',
['Yü']='Yüki:BAAALgAECgEJAQAAAA==.',
Za='Zabaniya:BAAALgADCgEJAQAAAA==.Zac:BAAALgADCgYJDAAAAA==.Zacceptable:BAABLgAECn8VAAIiAAcJUhRDBABdAQdoDAAABQBHAGkMAAAEADUAawwAAAQAMQBqDAAAAgApAGwMAAABABwAbQwAAAIAKgDqDAAAAwBDACIABwlSFEMEAF0BB2gMAAAFAEcAaQwAAAQANQBrDAAABAAxAGoMAAACACkAbAwAAAEAHABtDAAAAgAqAOoMAAADAEMAAAA=.Zaida:BAAALgADCgUJBQABLgAECgIJAgACAAAAAA==.',
Ze='Zeale:BAABLgAECn8cAAIEAAgJuRH6OgCBAQhoDAAABABFAGkMAAAGADgAawwAAAQAGgBqDAAAAwAkAGwMAAAEADsAbQwAAAEAJgDqDAAABQAxAG4MAAABABIABAAICbkR+joAgQEIaAwAAAQARQBpDAAABgA4AGsMAAAEABoAagwAAAMAJABsDAAABAA7AG0MAAABACYA6gwAAAUAMQBuDAAAAQASAAAA.Zenedict:BAAALgAECgYJDwAAAA==.',
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
