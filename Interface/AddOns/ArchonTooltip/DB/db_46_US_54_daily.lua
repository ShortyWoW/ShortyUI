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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Shaman-Elemental','Mage-Frost','Warrior-Fury','Hunter-BeastMastery','Paladin-Holy','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Paladin-Protection','Warlock-Demonology','Paladin-Retribution','Druid-Guardian','Druid-Feral','DeathKnight-Unholy','DeathKnight-Frost','Hunter-Survival','Rogue-Assassination','DemonHunter-Devourer','Monk-Windwalker','Warlock-Affliction','Warlock-Destruction','DemonHunter-Havoc','Priest-Holy','Priest-Shadow','Priest-Discipline','DeathKnight-Blood','Mage-Fire','Warrior-Arms','Shaman-Enhancement','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Outlaw','Druid-Restoration','Druid-Balance','Warrior-Protection','Monk-Brewmaster',}
local provider = {region='US',realm='Coilfang',name='US',type='daily',zone=46,date='2026-05-27',data={Ae='Aendean:BAAALgAECgQJBAAAAA==.',
Am='Amethyne:BAAALgADCgMJAwAAAA==.',
An='Anabell:BAAALgAECgIJAwABLgAECgYJCAABAAAAAA==.',
Ar='Arckane:BAAALgAECgEJAQAAAA==.Arcueid:BAABLgAECn80AAMCAAkJqCAeFwBdAgloDAAABwBQAGkMAAAGAFMAawwAAAkAWABqDAAABwBVAGwMAAAGAEkAbQwAAAMAOwDqDAAACgBZAG4MAAADAFwAbwwAAAEAYwACAAgJ4x8eFwBdAghoDAAABwBQAGkMAAAGAFMAawwAAAkAWABqDAAABwBVAGwMAAAGAEkAbQwAAAMAOwDqDAAACgBZAG4MAAACAFwAAwACCRAZIWMAlgACbgwAAAEAUwBvDAAAAQAtAAAA.',
As='Asmadeus:BAAALgAECgYJBwAAAA==.',
Ay='Ayda:BAABLgAECn9KAAIEAAkJXyWhBABQAwloDAAACgBhAGkMAAAKAGAAawwAAAkAYQBqDAAACQBYAGwMAAAIAGMAbQwAAAcAWgDqDAAACgBfAG4MAAAHAF4AbwwAAAQAXgAEAAkJXyWhBABQAwloDAAACgBhAGkMAAAKAGAAawwAAAkAYQBqDAAACQBYAGwMAAAIAGMAbQwAAAcAWgDqDAAACgBfAG4MAAAHAF4AbwwAAAQAXgAAAA==.',
Ba='Bajabeachboy:BAAALgAFFAIJBAABLgAFFAMJDgAFAEofAA==.Bartholdson:BAABLgAECn8fAAIGAAgJ2hixMQD3AQhoDAAABQBAAGkMAAAEAFIAawwAAAQATABqDAAABQBBAGwMAAAEADIAbQwAAAIALADqDAAABQA2AG4MAAACAEgABgAICdoYsTEA9wEIaAwAAAUAQABpDAAABABSAGsMAAAEAEwAagwAAAUAQQBsDAAABAAyAG0MAAACACwA6gwAAAUANgBuDAAAAgBIAAAA.',
Be='Bearlydidit:BAAALgADCgQJBAAAAA==.Beloc:BAAALgAECgcJAgAAAA==.Berzerkirz:BAAALgADCgYJBgAAAA==.',
Bl='Blacksnow:BAAALgADCgEJAQAAAA==.Blcksnowcrow:BAABLgAECn8kAAIHAAkJfxz7CQDPAgloDAAABgBbAGkMAAAFAFkAawwAAAYAXABqDAAABABEAGwMAAADAFAAbQwAAAMAQwDqDAAABwBOAG4MAAABACkAbwwAAAEALwAHAAkJfxz7CQDPAgloDAAABgBbAGkMAAAFAFkAawwAAAYAXABqDAAABABEAGwMAAADAFAAbQwAAAMAQwDqDAAABwBOAG4MAAABACkAbwwAAAEALwAAAA==.',
Bo='Bonfire:BAACLgAFFH8HAAIIAAUJvRy5FwBaAQVoDAAAAQA+AGkMAAACAF8AawwAAAEAMABqDAAAAQBaAOoMAAACAFgACAAFCb0cuRcAWgEFaAwAAAEAPgBpDAAAAgBfAGsMAAABADAAagwAAAEAWgDqDAAAAgBYAC4ABAp/JgAECAAJCW8jNgoAmQIACAAJCe0iNgoAmQIACQAGCW4h7g4ABwEACgACCUoChkQASwAAAS4ABRQFCQkABAAZHAA=.Boochili:BAABLgAECn9GAAILAAkJ7yYIAACVAwloDAAACQBjAGkMAAAJAGMAawwAAAgAYwBqDAAACQBjAGwMAAAIAGMAbQwAAAcAYwDqDAAACQBjAG4MAAAHAGMAbwwAAAQAYwALAAkJ7yYIAACVAwloDAAACQBjAGkMAAAJAGMAawwAAAgAYwBqDAAACQBjAGwMAAAIAGMAbQwAAAcAYwDqDAAACQBjAG4MAAAHAGMAbwwAAAQAYwAAAA==.',
Br='Bravebeard:BAABLgAFFH8GAAIFAAMJ7BFpKADmAANoDAAAAgBBAGkMAAACADMA6gwAAAIAFAAFAAMJ7BFpKADmAANoDAAAAgBBAGkMAAACADMA6gwAAAIAFAAAAA==.Braveling:BAABLgAECn8fAAIMAAkJ9A4tPQDVAQloDAAABQAZAGkMAAAFACwAawwAAAUAGwBqDAAAAwAvAGwMAAADAC0AbQwAAAEAIADqDAAABQAjAG4MAAADAEgAbwwAAAEAFgAMAAkJ9A4tPQDVAQloDAAABQAZAGkMAAAFACwAawwAAAUAGwBqDAAAAwAvAGwMAAADAC0AbQwAAAEAIADqDAAABQAjAG4MAAADAEgAbwwAAAEAFgAAAA==.',
Bu='Bubblës:BAAALgAECgQJCAABLgAECgkJMAAEAJgiAA==.',
Ca='Carezarsh:BAAALgADCgMJAQAAAA==.',
Ch='Charlie:BAACLgAFFH8XAAMNAAYJ3CJACQDkAQZoDAAABgBdAGkMAAAFAFoAawwAAAUAXwBqDAAAAQBGAGwMAAABAE8A6gwAAAUAVgANAAYJ3CJACQDkAQZoDAAABgBdAGkMAAAFAFoAawwAAAQAXwBqDAAAAQBGAGwMAAABAE8A6gwAAAUAVgALAAEJQCN/DwBhAAFrDAAAAQBaAC4ABAp/OAADDQAJCc4lHwgAUwMADQAJCc4lHwgAUwMACwAFCc4ZgSAA7AAAAAA=.Chicken:BAABLgAFFH8FAAMOAAMJjArUFwCVAANoDAAAAQASAGkMAAABAAsA6gwAAAMAMwAOAAMJjArUFwCVAANoDAAAAQASAGkMAAABAAsA6gwAAAIAMwAPAAEJMwOCFgA+AAHqDAAAAQAIAAAA.',
Cr='Cruel:BAAALgADCgEJAQAAAA==.',
['Cä']='Cätîáñdrïà:BAACLgAFFH8KAAICAAQJuhf+IgAwAQRoDAAAAgBPAGkMAAAEAEUAawwAAAIAHwDqDAAAAgA+AAIABAm6F/4iADABBGgMAAACAE8AaQwAAAQARQBrDAAAAgAfAOoMAAACAD4ALgAECn9iAAMCAAkJ+CC5BQA6AwACAAkJ+CC5BQA6AwADAAYJdw7qSgDkAAAAAA==.',
Da='Dagron:BAAALgAFFAIJAgAAAA==.Daniedk:BAABLgAECn8xAAIQAAgJvhMNXQCXAQhoDAAABwBDAGkMAAAHAC4AawwAAAYAHQBqDAAABwBAAGwMAAAFACsAbQwAAAMAIgDqDAAABwBDAG4MAAAHAEEAEAAICb4TDV0AlwEIaAwAAAcAQwBpDAAABwAuAGsMAAAGAB0AagwAAAcAQABsDAAABQArAG0MAAADACIA6gwAAAcAQwBuDAAABwBBAAAA.Daphanim:BAAALgADCgYJCgAAAA==.Darctotem:BAAALgAECgcJEwAAAA==.Darksabbath:BAAALgADCgUJBQAAAA==.',
De='Deathtouch:BAACLgAFFH8HAAMQAAMJPhzXgwDWAANoDAAAAgBTAGkMAAADADcA6gwAAAIATQAQAAMJPhzXgwDWAANoDAAAAQBTAGkMAAACADcA6gwAAAIATQARAAIJSRBnFQCJAAJoDAAAAQAnAGkMAAABACsALgAECn8bAAMQAAgJSSOmLAA0AgAQAAgJyiKmLAA0AgARAAEJEh2CKwA8AAAAAA==.Devona:BAABLgAECn8kAAMHAAkJZR0PHwDtAQloDAAABwBBAGkMAAAGAFAAawwAAAYATQBqDAAAAwBNAGwMAAADAF8AbQwAAAEAHQDqDAAABgBYAG4MAAADAF4AbwwAAAEARAAHAAcJtBwPHwDtAQdoDAAABQBBAGkMAAAFAFAAawwAAAUATQBqDAAAAgBNAGwMAAACAF8AbQwAAAEAHQDqDAAABQBYAA0ACAnTD+NkAIoBCGgMAAACACQAaQwAAAEALgBrDAAAAQAYAGoMAAABABsAbAwAAAEAKADqDAAAAQAaAG4MAAADAE8AbwwAAAEAHQAAAA==.',
Di='Didit:BAAALgADCgcJBwAAAA==.Dingdangler:BAAALgAECgMJAwAAAA==.Dingledangle:BAABLgAECn8kAAIPAAgJchUsDADNAQhoDAAABgBOAGkMAAAGADwAawwAAAYAPgBqDAAABQA5AGwMAAACAAkAbQwAAAIALwDqDAAABgBOAG4MAAADADAADwAICXIVLAwAzQEIaAwAAAYATgBpDAAABgA8AGsMAAAGAD4AagwAAAUAOQBsDAAAAgAJAG0MAAACAC8A6gwAAAYATgBuDAAAAwAwAAAA.',
Dj='Djindor:BAAALgADCgUJBQAAAA==.',
Dr='Draconix:BAAALgAECgQJBAABLgAECgYJBgABAAAAAA==.Dragonzordd:BAAALgADCgQJBQABLgAECgYJGgASAAwiAA==.Dragooncrush:BAAALgADCgcJCwAAAA==.Dragoonnick:BAACLgAFFH8NAAITAAQJOBU1AwBbAQRoDAAABgBYAGkMAAADAFEAawwAAAEAIgDqDAAAAwAMABMABAk4FTUDAFsBBGgMAAAGAFgAaQwAAAMAUQBrDAAAAQAiAOoMAAADAAwALgAECn9AAAITAAkJ/BvVBAAeAgATAAkJ/BvVBAAeAgAAAA==.Drazzy:BAAALgAECgIJAgAAAA==.',
Eg='Egg:BAAALgAFFAEJAgABLgAFFAYJFwAUAKcTAA==.',
Es='Esh:BAAALgAECgcJDgAAAA==.',
Eu='Euphal:BAABLgAECn8oAAIMAAkJLBJSQQDHAQloDAAABAA1AGkMAAAGAC0AawwAAAUAIQBqDAAAAwA1AGwMAAAHAEAAbQwAAAIAFwDqDAAABwBDAG4MAAAFADUAbwwAAAEAHgAMAAkJLBJSQQDHAQloDAAABAA1AGkMAAAGAC0AawwAAAUAIQBqDAAAAwA1AGwMAAAHAEAAbQwAAAIAFwDqDAAABwBDAG4MAAAFADUAbwwAAAEAHgAAAA==.',
Ey='Eyekicku:BAABLgAECn8iAAIVAAkJrx8ABwDCAgloDAAABwBcAGkMAAAGAFoAawwAAAYAWQBqDAAAAwBaAGwMAAADAE4AbQwAAAEAQADqDAAABQBZAG4MAAACAFoAbwwAAAEANQAVAAkJrx8ABwDCAgloDAAABwBcAGkMAAAGAFoAawwAAAYAWQBqDAAAAwBaAGwMAAADAE4AbQwAAAEAQADqDAAABQBZAG4MAAACAFoAbwwAAAEANQAAAA==.',
Fe='Feldana:BAAALgAECgQJBAAAAA==.Fenicon:BAAALgAECgQJBQAAAA==.',
Fi='Fitz:BAAALgAECgQJBAAAAA==.Fitzwell:BAAALgAECgUJCQAAAA==.',
Fl='Flow:BAAALgAECgQJBAABLgAFFAMJBQAOAIwKAA==.',
Fu='Fuyu:BAAALgAECgQJBAAAAA==.Fuyuhex:BAABLgAFFH8FAAICAAMJ0RFgSgCeAANoDAAAAgAzAGwMAAABAAAA6gwAAAIAVAACAAMJ0RFgSgCeAANoDAAAAgAzAGwMAAABAAAA6gwAAAIAVAAAAA==.',
Gh='Ghost:BAAALgAECgMJBQAAAA==.',
Gi='Gibbousbogg:BAAALgADCgEJAQAAAA==.',
Gr='Graycieden:BAAALgAECgYJCQAAAA==.',
Gu='Guldangit:BAACLgAFFH8jAAMMAAgJcR22AQAmAghoDAAABwBcAGkMAAAFAFsAawwAAAYAVQBqDAAABABLAGwMAAADADkAbQwAAAEAIwDqDAAACABcAG4MAAABAEgADAAICTQctgEAJgIIaAwAAAYAXABpDAAABABbAGsMAAAFAFIAagwAAAMARABsDAAAAwA5AG0MAAABACMA6gwAAAYASABuDAAAAQBIABYABQlJH6IBAHsBBWgMAAABADwAaQwAAAEAUgBrDAAAAQBVAGoMAAABAEsA6gwAAAIAXAAuAAQKfzIABBYACQn/JU8AAE0DABYACQkSJU8AAE0DAAwACQkBI2oIAD4DABcABAmOIi4aAHsBAAAA.',
Ha='Hanora:BAAALgAECgUJBgAAAA==.',
He='Hellspawn:BAABLgAECn9KAAIYAAkJeBCMFgCpAQloDAAACgA+AGkMAAAKADMAawwAAAkALABqDAAACQAqAGwMAAAIACUAbQwAAAcAGADqDAAACgAtAG4MAAAHAC0AbwwAAAQAGQAYAAkJeBCMFgCpAQloDAAACgA+AGkMAAAKADMAawwAAAkALABqDAAACQAqAGwMAAAIACUAbQwAAAcAGADqDAAACgAtAG4MAAAHAC0AbwwAAAQAGQAAAA==.',
Hh='Hhounow:BAAALgADCgcJDAAAAA==.',
Ho='Hojai:BAAALgADCgMJAwAAAA==.Holybeef:BAAALgAECggJDgAAAA==.Holygrim:BAACLgAFFH8kAAIZAAgJGSQeAABAAwhoDAAABwBkAGkMAAAHAGMAawwAAAYAYgBqDAAABQBhAGwMAAACAFEAbQwAAAEAVwDqDAAABwBiAG4MAAABAE0AGQAICRkkHgAAQAMIaAwAAAcAZABpDAAABwBjAGsMAAAGAGIAagwAAAUAYQBsDAAAAgBRAG0MAAABAFcA6gwAAAcAYgBuDAAAAQBNAC4ABAp/HQADGQAICWMm4AEAVwMAGQAICWMm4AEAVwMAGgABCT4JUHgALgAAAAA=.Holyloa:BAAALgAECgMJAwAAAA==.Holypablo:BAABLgAECn9KAAQbAAkJPx+4BQAKAwloDAAACgBJAGkMAAAKAFoAawwAAAkAXgBqDAAACQBfAGwMAAAIAGEAbQwAAAcAVADqDAAACgA6AG4MAAAHAEIAbwwAAAQAOwAbAAkJPx+4BQAKAwloDAAABABJAGkMAAAFAFoAawwAAAQAXgBqDAAABwBfAGwMAAAHAGEAbQwAAAcAVADqDAAABQA6AG4MAAAEAEIAbwwAAAQAOwAaAAcJZBsNGQDaAQdoDAAABQA2AGkMAAAEAEcAawwAAAQARwBqDAAAAgA6AGwMAAABAEAA6gwAAAQAPQBuDAAAAwBhABkABAmtC5VdALwABGgMAAABAA4AaQwAAAEAGABrDAAAAQAxAOoMAAABAB8AAAA=.Howii:BAABLgAECn9MAAIcAAkJryXtAABUAwloDAAACwBbAGkMAAAKAGIAawwAAAkAYABqDAAACQBfAGwMAAAIAGEAbQwAAAcAYADqDAAACwBgAG4MAAAHAGEAbwwAAAQAXwAcAAkJryXtAABUAwloDAAACwBbAGkMAAAKAGIAawwAAAkAYABqDAAACQBfAGwMAAAIAGEAbQwAAAcAYADqDAAACwBgAG4MAAAHAGEAbwwAAAQAXwAAAA==.',
Im='Imperator:BAAALgAECgQJBAAAAA==.',
In='Inchworm:BAAALgAECgYJBgAAAA==.',
Is='Isabellaah:BAABLgAECn8hAAIGAAkJZBXPKAAcAgloDAAABwA7AGkMAAAGAEYAawwAAAYAPwBqDAAAAwAgAGwMAAADADwAbQwAAAEACQDqDAAABQAsAG4MAAABAFAAbwwAAAEAMQAGAAkJZBXPKAAcAgloDAAABwA7AGkMAAAGAEYAawwAAAYAPwBqDAAAAwAgAGwMAAADADwAbQwAAAEACQDqDAAABQAsAG4MAAABAFAAbwwAAAEAMQAAAA==.',
Je='Jeraziah:BAAALgAECgUJEQABLgAECgkJNAACAKggAA==.',
Jo='Johnnyjr:BAABLgAECn8pAAIFAAkJESFCBQD3AgloDAAABQBLAGkMAAAFAGAAawwAAAQAVwBqDAAABQBAAGwMAAAEAFcAbQwAAAQAPwDqDAAABQBRAG4MAAAFAGAAbwwAAAQAWQAFAAkJESFCBQD3AgloDAAABQBLAGkMAAAFAGAAawwAAAQAVwBqDAAABQBAAGwMAAAEAFcAbQwAAAQAPwDqDAAABQBRAG4MAAAFAGAAbwwAAAQAWQAAAA==.',
Ke='Kelliz:BAAALgADCgcJCAAAAA==.',
Kh='Khaladin:BAAALgAECgYJEgAAAA==.',
La='Laggers:BAABLgAECn8jAAIOAAgJdxZmGABcAQhoDAAABgA3AGkMAAAGAE4AawwAAAYARgBqDAAABQAwAGwMAAADADMAbQwAAAEAGgDqDAAABwBKAG4MAAABAC0ADgAICXcWZhgAXAEIaAwAAAYANwBpDAAABgBOAGsMAAAGAEYAagwAAAUAMABsDAAAAwAzAG0MAAABABoA6gwAAAcASgBuDAAAAQAtAAAA.',
Le='Lean:BAAALgAFFAIJAgABLgAFFAUJCQAEABkcAA==.',
Li='Litbit:BAABLgAECn8jAAIEAAgJXQTGsQD+AAhoDAAABgAQAGkMAAAGABMAawwAAAYABwBqDAAABgAQAGwMAAAEAA4AbQwAAAIABwDqDAAABAAFAG4MAAABAAYABAAICV0ExrEA/gAIaAwAAAYAEABpDAAABgATAGsMAAAGAAcAagwAAAYAEABsDAAABAAOAG0MAAACAAcA6gwAAAQABQBuDAAAAQAGAAAA.Litbitonme:BAAALgAECgQJCgAAAA==.Litllit:BAAALgAECgMJAwAAAA==.Litt:BAAALgADCgkJCwAAAA==.Liuye:BAAALgADCgUJBQAAAA==.Lizardwizard:BAAALgAECgEJAQAAAA==.',
Lo='Lockmantwo:BAAALgAECgcJAwAAAA==.Lostmoo:BAAALgAECgEJAQAAAA==.Lostunholy:BAABLgAECn8gAAIQAAgJBSKmHwBzAghoDAAACABhAGkMAAAFAFIAawwAAAQAVwBqDAAAAwBaAGwMAAADAFMAbQwAAAIASQDqDAAABQBaAG4MAAACAF0AEAAICQUiph8AcwIIaAwAAAgAYQBpDAAABQBSAGsMAAAEAFcAagwAAAMAWgBsDAAAAwBTAG0MAAACAEkA6gwAAAUAWgBuDAAAAgBdAAAA.Lovebug:BAAALgADCgcJBwAAAA==.',
Lu='Lunaardris:BAAALgAECgQJBQAAAA==.',
Ly='Lynxe:BAAALgAECgYJBgAAAA==.',
Ma='Maggikal:BAABLgAECn8gAAMEAAgJIxBRYgCcAQhoDAAABgA3AGkMAAAFAEUAawwAAAUALQBqDAAAAwAXAGwMAAACAAoA6gwAAAgAKABuDAAAAgAqAG8MAAABABcABAAICSMQUWIAnAEIaAwAAAYANwBpDAAABQBFAGsMAAAFAC0AagwAAAMAFwBsDAAAAgAKAOoMAAAHACgAbgwAAAIAKgBvDAAAAQAXAB0AAQkIDCEQADMAAeoMAAABAB4AAAA=.',
Me='Megahottie:BAAALgAECgEJAQAAAA==.',
Mi='Mirant:BAAALgAECgUJDwAAAA==.',
Mo='Moretisha:BAAALgADCgYJBgAAAA==.',
['Mâ']='Mâchine:BAAALgAFFAIJAgABLgAFFAUJFQAQAMgWAA==.',
Na='Nakwoo:BAAALgADCgMJAwAAAA==.',
Of='Of:BAAALgAECgEJAwAAAA==.',
On='One:BAAALgAECgEJAQAAAA==.',
Op='Opallea:BAABLgAECn8dAAMYAAkJWxugEQBRAgloDAAABQBPAGkMAAAGAE4AawwAAAYASwBqDAAAAwBOAGwMAAACAEgAbQwAAAEARADqDAAABABKAG4MAAABAC4AbwwAAAEAQAAYAAkJWxugEQBRAgloDAAABABPAGkMAAAFAE4AawwAAAUASwBqDAAAAgBOAGwMAAACAEgAbQwAAAEARADqDAAABABKAG4MAAABAC4AbwwAAAEAQAAUAAQJ6gSo1gBZAARoDAAAAQAKAGkMAAABABIAawwAAAEACQBqDAAAAQAeAAAA.',
Pa='Pallyplay:BAAALgAECgEJAQAAAA==.',
Pb='Pballs:BAAALgADCgEJAQABLgAECgkJSgAbAD8fAA==.',
Pe='Periodic:BAACLgAFFH8RAAICAAQJKCPgEwCPAQRoDAAABgBaAGkMAAAEAGAAawwAAAIAUQDqDAAABQBbAAIABAkoI+ATAI8BBGgMAAAGAFoAaQwAAAQAYABrDAAAAgBRAOoMAAAFAFsALgAECn8vAAICAAkJ5CP0AACZAwACAAkJ5CP0AACZAwAAAA==.',
Pl='Platen:BAABLgAECn8jAAIGAAkJQRLyMgDyAQloDAAABwA3AGkMAAAGADIAawwAAAYAKABqDAAAAwAwAGwMAAADAEwAbQwAAAEABQDqDAAABQBNAG4MAAADACsAbwwAAAEAFgAGAAkJQRLyMgDyAQloDAAABwA3AGkMAAAGADIAawwAAAYAKABqDAAAAwAwAGwMAAADAEwAbQwAAAEABQDqDAAABQBNAG4MAAADACsAbwwAAAEAFgAAAA==.',
Po='Potter:BAABLgAECn9FAAIEAAkJbB/IFgC2AgloDAAACQBUAGkMAAAJAEwAawwAAAkAUgBqDAAACABBAGwMAAAIAF8AbQwAAAcASgDqDAAACQBQAG4MAAAGAEwAbwwAAAQASAAEAAkJbB/IFgC2AgloDAAACQBUAGkMAAAJAEwAawwAAAkAUgBqDAAACABBAGwMAAAIAF8AbQwAAAcASgDqDAAACQBQAG4MAAAGAEwAbwwAAAQASAAAAA==.',
Ra='Raffa:BAABLgAECn8jAAIVAAcJiB5HFQDwAQdoDAAABQBWAGkMAAAEAE4AawwAAAUAJwBqDAAABQBUAGwMAAADAFgAbQwAAAIAUADqDAAACwBfABUABwmIHkcVAPABB2gMAAAFAFYAaQwAAAQATgBrDAAABQAnAGoMAAAFAFQAbAwAAAMAWABtDAAAAgBQAOoMAAALAF8AAAA=.Rakandei:BAAALgADCgMJAwAAAA==.Ramaylis:BAAALgADCgEJAQAAAA==.Raptor:BAABLgAFFH8JAAIEAAUJGRxwNgBgAQVoDAAAAgBTAGkMAAACADsAawwAAAIAMABqDAAAAQADAOoMAAACAF8ABAAFCRkccDYAYAEFaAwAAAIAUwBpDAAAAgA7AGsMAAACADAAagwAAAEAAwDqDAAAAgBfAAAA.Rapunzel:BAAALgAECgkJBgAAAA==.Rataiga:BAAALgAECgYJEgAAAA==.',
Rh='Rheynah:BAABLgAECn8gAAMFAAkJ4QSFUwDeAAloDAAABgAIAGkMAAAFABIAawwAAAUADQBqDAAAAwAVAGwMAAADAA0AbQwAAAEACADqDAAABQAHAG4MAAADAAsAbwwAAAEAEQAFAAgJ/wOFUwDeAAhoDAAABQAIAGkMAAAEAA8AawwAAAQADQBqDAAAAgADAGwMAAACAAcA6gwAAAQABwBuDAAAAQABAG8MAAABABEAHgAICasDfzwArgAIaAwAAAEABABpDAAAAQASAGsMAAABAAQAagwAAAEAFQBsDAAAAQANAG0MAAABAAgA6gwAAAEAAwBuDAAAAgALAAAA.',
Ri='Rimuna:BAAALgADCgUJBQAAAA==.Rinni:BAACLgAFFH8dAAIPAAYJryGzAAAHAgZoDAAABwBeAGkMAAAFAF0AawwAAAUAYABqDAAABABJAGwMAAABADYA6gwAAAcAXQAPAAYJryGzAAAHAgZoDAAABwBeAGkMAAAFAF0AawwAAAUAYABqDAAABABJAGwMAAABADYA6gwAAAcAXQAuAAQKfy0AAg8ACQkQJR0BADUDAA8ACQkQJR0BADUDAAAA.',
Ro='Rovintis:BAABLgAECn89AAIeAAgJTxvtCQArAghoDAAACgBTAGkMAAAKAFUAawwAAAkATABqDAAACABWAGwMAAAHAEQAbQwAAAUAOADqDAAACQBUAG4MAAADACMAHgAICU8b7QkAKwIIaAwAAAoAUwBpDAAACgBVAGsMAAAJAEwAagwAAAgAVgBsDAAABwBEAG0MAAAFADgA6gwAAAkAVABuDAAAAwAjAAAA.',
Ry='Rynne:BAABLgAECn8cAAQCAAkJYhfaKQDyAQloDAAABAA5AGkMAAAFACsAawwAAAQASQBqDAAABAA7AGwMAAAEAFUAbQwAAAIAOADqDAAAAQAsAG4MAAADABoAbwwAAAEAWgACAAgJ3xXaKQDyAQhoDAAAAgA5AGkMAAACACsAawwAAAIASQBqDAAAAgA7AGwMAAACAFUAbQwAAAIAOADqDAAAAQAsAG4MAAABABoAHwAHCfAHARwACgEHaAwAAAIAGABpDAAAAwAWAGsMAAACABsAagwAAAIAGQBsDAAAAgAQAG4MAAABABEAbwwAAAEADAADAAEJZwMCpQAdAAFuDAAAAQAIAAAA.',
Sa='Sansundertal:BAABLgAECn8wAAIKAAkJsSJ+AgBJAwloDAAABwBcAGkMAAAGAFEAawwAAAYAYQBqDAAABgBjAGwMAAAGAGAAbQwAAAQAWwDqDAAABwBjAG4MAAAEAFkAbwwAAAIAMgAKAAkJsSJ+AgBJAwloDAAABwBcAGkMAAAGAFEAawwAAAYAYQBqDAAABgBjAGwMAAAGAGAAbQwAAAQAWwDqDAAABwBjAG4MAAAEAFkAbwwAAAIAMgAAAA==.Sargeràs:BAAALgADCgcJDAABLgAECgQJBAABAAAAAA==.',
Se='Selissaroth:BAAALgAECgEJAQAAAA==.Sentinal:BAABLgAECn8tAAIcAAgJdxdjEwC3AQhoDAAABwBXAGkMAAAHAD0AawwAAAYAOwBqDAAABgBUAGwMAAAFAEMAbQwAAAMAHQDqDAAABwA5AG4MAAAEADkAHAAICXcXYxMAtwEIaAwAAAcAVwBpDAAABwA9AGsMAAAGADsAagwAAAYAVABsDAAABQBDAG0MAAADAB0A6gwAAAcAOQBuDAAABAA5AAAA.Sentinäl:BAAALgAECgIJAgAAAA==.Sephiro:BAAALgAECgQJBgAAAA==.',
Sh='Shamu:BAACLgAFFH8IAAICAAMJ9BD6OwDOAANoDAAABAAWAGkMAAABABIA6gwAAAMAWAACAAMJ9BD6OwDOAANoDAAABAAWAGkMAAABABIA6gwAAAMAWAAuAAQKfxoAAgIACQkNFQ08AJkBAAIACQkNFQ08AJkBAAAA.Shawner:BAAALgADCgMJAwAAAA==.Shy:BAAALgAECgUJCgAAAA==.',
Si='Silvertiger:BAABLgAECn9JAAMSAAkJ3h/ABADOAgloDAAACQBYAGkMAAAKAFoAawwAAAkAUgBqDAAACQBGAGwMAAAIAFQAbQwAAAcAUwDqDAAACgBEAG4MAAAHAFQAbwwAAAQARgASAAkJ3h/ABADOAgloDAAACABYAGkMAAAIAFoAawwAAAcAUgBqDAAACABGAGwMAAAHAFQAbQwAAAYAUwDqDAAACABEAG4MAAAHAFQAbwwAAAQARgAgAAcJgg+dPABsAQdoDAAAAQAtAGkMAAACADMAawwAAAIAJABqDAAAAQASAGwMAAABACwAbQwAAAEAIADqDAAAAgAdAAAA.',
Sl='Slabbydabby:BAAALgAECgYJCgAAAA==.Sleeperbater:BAAALgADCgIJAgAAAA==.Sleeperdk:BAAALgAECgYJCwAAAA==.',
Sn='Snackyfraps:BAAALgAECgUJBwABLgAECgkJSgAbAD8fAA==.Sneaki:BAABLgAECn9IAAQhAAkJdyUXBADoAgloDAAACgBjAGkMAAAKAF8AawwAAAkAXABqDAAACQBcAGwMAAAIAF0AbQwAAAYAYADqDAAACgBdAG4MAAAGAGMAbwwAAAQAYAAhAAkJ+SMXBADoAgloDAAACQBjAGkMAAAJAF8AawwAAAgAXABqDAAACABcAGwMAAACAD8AbQwAAAUAYADqDAAACQBdAG4MAAAFAGMAbwwAAAQAYAAiAAgJ/RzvAwAzAghoDAAAAQBXAGkMAAABACsAawwAAAEARwBqDAAAAQBLAGwMAAABAF0AbQwAAAEAQQDqDAAAAQBPAG4MAAABAE4AEwABCbEjQRsAaQABbAwAAAUAWwAAAA==.Sniperanger:BAAALgADCgMJAwAAAA==.Snstr:BAABLgAECn8aAAQZAAYJbRfiLACTAQZoDAAABgBOAGkMAAAFAEgAawwAAAQATABqDAAAAwAaAGwMAAADACgA6gwAAAUAQAAZAAYJbRfiLACTAQZoDAAABQBOAGkMAAAEAEgAawwAAAMATABqDAAAAgAaAGwMAAACACgA6gwAAAQAQAAaAAQJ5gMhTQChAARpDAAAAQAGAGsMAAABAA4AagwAAAEADgBsDAAAAQAJABsAAgmRCFlNAF0AAmgMAAABAA4A6gwAAAEAHAAAAA==.',
So='Sorynia:BAABLgAECn8aAAIGAAgJkAdDcQA8AQhoDAAABAASAGkMAAAEABkAawwAAAQAGABqDAAABAAbAGwMAAABAAgAbQwAAAEABQDqDAAABQAcAG4MAAADABgABgAICZAHQ3EAPAEIaAwAAAQAEgBpDAAABAAZAGsMAAAEABgAagwAAAQAGwBsDAAAAQAIAG0MAAABAAUA6gwAAAUAHABuDAAAAwAYAAAA.Soul:BAAALgAECgEJAQAAAA==.Soulkid:BAAALgAECgQJBQAAAA==.',
St='Starta:BAACLgAFFH8LAAIUAAMJ5xmKSQDnAANoDAAABAA7AGkMAAADADwA6gwAAAQATgAUAAMJ5xmKSQDnAANoDAAABAA7AGkMAAADADwA6gwAAAQATgAuAAQKfxsAAhQACAmNIaUnABQCABQACAmNIaUnABQCAAAA.Startawar:BAACLgAFFH8FAAINAAIJxhJMbwCWAAJpDAAAAQAiAOoMAAAEAD0ADQACCcYSTG8AlgACaQwAAAEAIgDqDAAABAA9AC4ABAp/JAACDQAICccjLBYA5AIADQAICccjLBYA5AIAAAA=.Stormbeard:BAAALgAECgUJBQABLgAFFAYJFwANANwiAA==.',
Su='Sukii:BAAALgAECgUJBgAAAA==.Sulfuricvein:BAAALgAFFAEJAQAAAA==.',
['Sø']='Sømebody:BAAALgAECgQJBAAAAA==.',
Th='Thelandrius:BAAALgADCgIJAgAAAA==.',
Ti='Tiana:BAAALgAECgkJBAAAAA==.',
To='Totemdaddy:BAAALgAECgEJAQAAAA==.Totemicdidit:BAAALgADCgMJAwAAAA==.Totemstorm:BAAALgAECgcJBwAAAA==.',
Tr='Traumatic:BAABLgAECn8UAAIFAAcJjRj6LwDvAQdoDAAAAwBIAGkMAAAEAEUAawwAAAMAPwBqDAAAAwAfAGwMAAACADwA6gwAAAQASQBuDAAAAQAlAAUABwmNGPovAO8BB2gMAAADAEgAaQwAAAQARQBrDAAAAwA/AGoMAAADAB8AbAwAAAIAPADqDAAABABJAG4MAAABACUAAAA=.',
Tu='Tunny:BAAALgAECgYJCAAAAA==.Turnleft:BAACLgAFFH8FAAIjAAMJPBwXKwD4AANoDAAAAgA9AGkMAAABAFAA6gwAAAIASgAjAAMJPBwXKwD4AANoDAAAAgA9AGkMAAABAFAA6gwAAAIASgAuAAQKfzAAAyMACQlmI0sCAJ4DACMACQlmI0sCAJ4DACQAAQmCHrBpAFcAAAAA.',
Va='Valerïan:BAAALgADCgEJAQABLgAECgYJBQABAAAAAA==.Vauntmonk:BAAALgADCgMJAwABLgAFFAUJEgAlAFYhAA==.',
Ve='Vendetta:BAAALgAECgEJAQABLgAFFAMJBQAOAIwKAA==.Vercyv:BAAALgADCgkJEQAAAA==.Vevio:BAAALgAECgQJBAAAAA==.',
Vi='Video:BAAALgAECgEJAQAAAA==.Violet:BAACLgAFFH8GAAIQAAMJABlXcgDwAANoDAAAAwBFAGkMAAACAEsA6gwAAAEALgAQAAMJABlXcgDwAANoDAAAAwBFAGkMAAACAEsA6gwAAAEALgAuAAQKfzAAAhAACQkzH6EMAPECABAACQkzH6EMAPECAAAA.Vishlock:BAABLgAECn8xAAMWAAkJhBmvBQABAgloDAAABgBQAGkMAAAGADsAawwAAAYANwBqDAAABQA1AGwMAAAFAEsAbQwAAAQAGwDqDAAABwBMAG4MAAAGAFkAbwwAAAQAOQAWAAkJhBmvBQABAgloDAAABQBQAGkMAAAGADsAawwAAAUANwBqDAAAAwA1AGwMAAAEAEsAbQwAAAIAGwDqDAAABQBMAG4MAAADAFkAbwwAAAMAOQAMAAgJ8w4OlAAwAQhoDAAAAQARAGsMAAABACAAagwAAAIACgBsDAAAAQBBAG0MAAACABEA6gwAAAIAQQBuDAAAAwAXAG8MAAABAC4AAAA=.',
Vo='Voddie:BAABLgAECn8gAAIDAAkJPgzULABvAQloDAAABgAdAGkMAAAGABoAawwAAAYAHgBqDAAAAwALAGwMAAADABUAbQwAAAEACQDqDAAABAAeAG4MAAACAFQAbwwAAAEAEgADAAkJPgzULABvAQloDAAABgAdAGkMAAAGABoAawwAAAYAHgBqDAAAAwALAGwMAAADABUAbQwAAAEACQDqDAAABAAeAG4MAAACAFQAbwwAAAEAEgAAAA==.Votarick:BAAALgAECgEJAQAAAA==.',
Wa='Waban:BAAALgAECgcJEwAAAA==.Walmarthas:BAAALgAECgcJDQABLgAECgkJHQAIAEkUAA==.Wapta:BAAALgAFFAEJAQABLgAFFAUJCQAEABkcAA==.',
Wi='Wizwiztheliz:BAAALgAECgYJDwAAAA==.',
Wo='Wolf:BAABLgAECn8cAAImAAgJOxCVJQBpAQhoDAAABgAwAGkMAAAFACcAawwAAAUAIABqDAAAAwAbAGwMAAACADEAbQwAAAEABwDqDAAABAA2AG4MAAACADoAJgAICTsQlSUAaQEIaAwAAAYAMABpDAAABQAnAGsMAAAFACAAagwAAAMAGwBsDAAAAgAxAG0MAAABAAcA6gwAAAQANgBuDAAAAgA6AAEuAAUUAwkFAA4AjAoA.Woof:BAAALgAECgIJAgAAAA==.',
Xy='Xynelle:BAAALgADCgcJCwAAAA==.',
Ya='Yahtzee:BAAALgAECgQJBwAAAA==.',
Yo='Youdidwhat:BAAALgADCgkJCQAAAA==.',
Za='Zaia:BAAALgAECgcJEwAAAA==.',
Ze='Zenithmage:BAAALgAECgcJDQAAAA==.',
['Ár']='Ártémes:BAAALgADCggJAgAAAA==.',
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
