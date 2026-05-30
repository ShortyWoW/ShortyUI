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

local lookup = {'Warrior-Fury','Hunter-Survival','Druid-Guardian','Monk-Windwalker','Monk-Brewmaster','DemonHunter-Havoc','Priest-Holy','Priest-Discipline','Paladin-Retribution','Priest-Shadow','DeathKnight-Unholy','Hunter-BeastMastery','Paladin-Holy','Rogue-Subtlety','DeathKnight-Blood','Shaman-Elemental','Shaman-Enhancement','Evoker-Augmentation','Hunter-Marksmanship','Warlock-Demonology','Mage-Frost','Druid-Balance','Shaman-Restoration','Unknown-Unknown','DeathKnight-Frost','Paladin-Protection','DemonHunter-Devourer','Rogue-Assassination','Warrior-Protection','Warrior-Arms',}
local provider = {region='US',realm='Dethecus',name='US',type='daily',zone=46,date='2026-05-29',data={Aa='Aashley:BAAALgAECgcJBwAAAA==.',
Al='Alistis:BAAALgADCgEJAQAAAA==.',
Am='Amutio:BAAALgAECgMJCwAAAA==.',
An='Andromedus:BAAALgAFFAEJAgABLgAFFAgJIwABABsbAA==.',
Ar='Arasis:BAABLgAECn81AAICAAkJeSVqAQA/AwloDAAABwBgAGkMAAAIAGIAawwAAAgAYgBqDAAABgBdAGwMAAAFAGEAbQwAAAMAWwDqDAAACABgAG4MAAAHAF8AbwwAAAEAWgACAAkJeSVqAQA/AwloDAAABwBgAGkMAAAIAGIAawwAAAgAYgBqDAAABgBdAGwMAAAFAGEAbQwAAAMAWwDqDAAACABgAG4MAAAHAF8AbwwAAAEAWgAAAA==.Arìel:BAAALgADCgkJFQAAAA==.',
As='Ashhleyy:BAAALgAECgcJBgAAAA==.Ashhlleyy:BAAALgAECgcJAQAAAA==.Ashleyy:BAAALgAECgcJBgAAAA==.',
Ba='Balancing:BAABLgAFFH8FAAIDAAIJUBZ7GwCJAAJoDAAAAwAnAOoMAAACAEsAAwACCVAWexsAiQACaAwAAAMAJwDqDAAAAgBLAAAA.Bamag:BAABLgAECn8eAAIBAAgJgSLxBgA5AwhoDAAABQBfAGkMAAAFAGAAawwAAAUAYgBqDAAABABeAGwMAAAEAFwAbQwAAAIAXADqDAAABABcAG4MAAABADEAAQAICYEi8QYAOQMIaAwAAAUAXwBpDAAABQBgAGsMAAAFAGIAagwAAAQAXgBsDAAABABcAG0MAAACAFwA6gwAAAQAXABuDAAAAQAxAAAA.',
Bi='Bigmak:BAAALgAECgEJAQAAAA==.',
Br='Braellyn:BAAALgAECgUJCQAAAA==.',
Bu='Burnyou:BAAALgADCggJGgAAAA==.',
Ce='Cenobité:BAABLgAECn8rAAMEAAgJqCQECACzAghoDAAABwBgAGkMAAAIAGEAawwAAAYAXwBqDAAABQBYAGwMAAAFAGEAbQwAAAMAYADqDAAABgBeAG4MAAADAE4ABAAICagkBAgAswIIaAwAAAcAYABpDAAACABhAGsMAAAGAF8AagwAAAQAWABsDAAABABhAG0MAAADAGAA6gwAAAYAXgBuDAAAAwBOAAUAAgk/G+9wAH8AAmoMAAABAC0AbAwAAAEARQAAAA==.Ceridemon:BAABLgAECn8iAAIGAAkJ4g/bGACXAQloDAAABQAlAGkMAAAFAEIAawwAAAUAIgBqDAAABAAjAGwMAAAEADoAbQwAAAMAIADqDAAABQAzAG4MAAACABEAbwwAAAEAGgAGAAkJ4g/bGACXAQloDAAABQAlAGkMAAAFAEIAawwAAAUAIgBqDAAABAAjAGwMAAAEADoAbQwAAAMAIADqDAAABQAzAG4MAAACABEAbwwAAAEAGgAAAA==.',
Ch='Chingee:BAACLgAFFH8GAAMHAAYJ+QGEFwDcAAZoDAAAAQACAGkMAAABAAIAawwAAAEAAwBqDAAAAQAGAGwMAAABAAsA6gwAAAEABAAHAAQJQgKEFwDcAARpDAAAAQACAGsMAAABAAMAagwAAAEABgBsDAAAAQALAAgAAglmAVE5AF0AAmgMAAABAAIA6gwAAAEABAAuAAQKf0wAAwgACQnHGqIJAKECAAgACQnsGaIJAKECAAcACAmLDkAmALoBAAAA.',
Co='Cobel:BAAALgAECgEJAQAAAA==.Consarios:BAABLgAFFH8HAAIJAAYJHRldDgCyAQZoDAAAAQBPAGkMAAABAFMAawwAAAEATwBqDAAAAQAuAGwMAAABABMA6gwAAAIAOgAJAAYJHRldDgCyAQZoDAAAAQBPAGkMAAABAFMAawwAAAEATwBqDAAAAQAuAGwMAAABABMA6gwAAAIAOgAAAA==.',
Cr='Croakadin:BAAALgADCgcJEAAAAA==.Crushers:BAAALgADCggJCAAAAA==.',
Cy='Cyraanden:BAACLgAFFH8RAAMEAAQJ3A2zHwDBAARoDAAABQAlAGkMAAAGACEAawwAAAEAJgDqDAAABQAgAAQAAwmBDbMfAMEAA2gMAAAEACUAaQwAAAUAIQDqDAAABQAgAAUAAwltCjk0AL8AA2gMAAABABoAaQwAAAEADwBrDAAAAQAmAC4ABAp/NQADBAAJCbsaKA8APgIABAAJCU4aKA8APgIABQAECR4UzUgAyAAAAAA=.Cyvus:BAABLgAECn8kAAMHAAgJawVZQwArAQhoDAAABgAIAGkMAAAGAAUAawwAAAUAEwBqDAAABQAZAGwMAAAFABAAbQwAAAIAEQDqDAAABgAPAG4MAAABAAAABwAICWsFWUMAKwEIaAwAAAIACABpDAAAAgAFAGsMAAADABMAagwAAAIAGQBsDAAAAgAQAG0MAAACABEA6gwAAAMADwBuDAAAAQAAAAoABgn7CYNDANkABmgMAAAEACYAaQwAAAQAFQBrDAAAAgAcAGoMAAADABIAbAwAAAMAFADqDAAAAwASAAAA.',
Da='Dab:BAABLgAECn9BAAILAAkJhSUuAwBjAwloDAAACQBgAGkMAAAJAGMAawwAAAkAYQBqDAAABwBhAGwMAAAIAGAAbQwAAAYAYwDqDAAACgBfAG4MAAAFAFQAbwwAAAIAYwALAAkJhSUuAwBjAwloDAAACQBgAGkMAAAJAGMAawwAAAkAYQBqDAAABwBhAGwMAAAIAGAAbQwAAAYAYwDqDAAACgBfAG4MAAAFAFQAbwwAAAIAYwAAAA==.Daedara:BAAALgAECgMJBAAAAA==.Daggz:BAABLgAECn8yAAMMAAkJER8LEgCnAgloDAAABwBXAGkMAAAHAFEAawwAAAcAXQBqDAAABgBVAGwMAAAFAE0AbQwAAAUAQADqDAAABwBOAG4MAAAEAFcAbwwAAAIAQgAMAAgJtx8LEgCnAghoDAAABQBXAGkMAAAFAFEAawwAAAUAXQBqDAAABAA/AGwMAAADAE0AbQwAAAMAPgDqDAAABQBOAG4MAAADAFcAAgAJCfUYLQoAbgIJaAwAAAIAVgBpDAAAAgBQAGsMAAACAEwAagwAAAIAVQBsDAAAAgAtAG0MAAACAEAA6gwAAAIAPABuDAAAAQAfAG8MAAACAEIAAAA=.Dansgrundle:BAAALgAECgMJAwABLgAECgkJHgANABQaAA==.Darkhorse:BAABLgAECn8mAAIOAAgJwh6FCgBkAghoDAAACABTAGkMAAAIAF0AawwAAAUAVgBqDAAABABeAGwMAAAEAFcAbQwAAAEADADqDAAABgBcAG4MAAACAF4ADgAICcIehQoAZAIIaAwAAAgAUwBpDAAACABdAGsMAAAFAFYAagwAAAQAXgBsDAAABABXAG0MAAABAAwA6gwAAAYAXABuDAAAAgBeAAAA.Darkmer:BAABLgAECn8rAAILAAcJqwV6sQD6AAdoDAAACQAPAGkMAAAJABMAawwAAAgADQBqDAAABQAQAGwMAAAEAA4A6gwAAAcADABuDAAAAQAKAAsABwmrBXqxAPoAB2gMAAAJAA8AaQwAAAkAEwBrDAAACAANAGoMAAAFABAAbAwAAAQADgDqDAAABwAMAG4MAAABAAoAAAA=.',
De='Deathsnight:BAAALgAECgUJBwAAAA==.Derpy:BAAALgADCgYJCQAAAA==.Deynestta:BAAALgAECgIJBAAAAA==.',
Di='Dixiereaper:BAABLgAECn8WAAIPAAkJahBrGgB+AQloDAAAAwBMAGkMAAADADwAawwAAAMALABqDAAAAgAvAGwMAAADACUAbQwAAAIAHgDqDAAAAwAcAG4MAAACAC0AbwwAAAEADQAPAAkJahBrGgB+AQloDAAAAwBMAGkMAAADADwAawwAAAMALABqDAAAAgAvAGwMAAADACUAbQwAAAIAHgDqDAAAAwAcAG4MAAACAC0AbwwAAAEADQAAAA==.',
Dr='Droopin:BAAALgADCgYJBwAAAA==.',
Ds='Ds:BAAALgAECgYJCgAAAA==.Dsntdrptotem:BAABLgAECn8uAAMQAAkJzBT7HwDIAQloDAAABgA8AGkMAAAFADUAawwAAAYANQBqDAAABQAuAGwMAAAGADcAbQwAAAQAGgDqDAAABgA3AG4MAAAEAFgAbwwAAAQAIAAQAAkJ3RH7HwDIAQloDAAAAgAnAGkMAAABADEAawwAAAIAHwBqDAAAAgAuAGwMAAADADcAbQwAAAMAGgDqDAAAAwAqAG4MAAAEAFgAbwwAAAQAIAARAAcJ2BGDEwCBAQdoDAAABAA8AGkMAAAEADUAawwAAAQANQBqDAAAAwAWAGwMAAADADAAbQwAAAEAAgDqDAAAAwA3AAAA.',
Dt='Dtothep:BAAALgAECgEJAQAAAA==.',
El='Elfangar:BAAALgADCgcJBwAAAA==.',
Ep='Epicamerican:BAAALgAECgEJAQAAAA==.',
Ff='Ffecanti:BAAALgAECgYJCQAAAA==.',
Fl='Floury:BAAALgAECgMJAwAAAA==.',
Ga='Gailen:BAAALgADCgkJDgAAAA==.',
Gi='Gideonn:BAAALgADCgMJAwAAAA==.',
Go='Gorber:BAABLgAECn8WAAISAAgJDRZoHgDIAQhoDAAAAwA9AGkMAAADAEMAawwAAAMAQQBqDAAAAwBLAGwMAAADAEwAbQwAAAIAIADqDAAAAwA4AG4MAAACACMAEgAICQ0WaB4AyAEIaAwAAAMAPQBpDAAAAwBDAGsMAAADAEEAagwAAAMASwBsDAAAAwBMAG0MAAACACAA6gwAAAMAOABuDAAAAgAjAAEuAAUUCAkoAAwAwBoA.Gorberfn:BAAALgAECgMJAwABLgAFFAgJKAAMAMAaAA==.',
Gr='Grimorn:BAACLgAFFH8iAAILAAgJfyDxAABGAghoDAAABgBjAGkMAAAGAGMAawwAAAUAWwBqDAAABABaAGwMAAADAGEAbQwAAAEAIQDqDAAACABfAG4MAAABAEEACwAICX8g8QAARgIIaAwAAAYAYwBpDAAABgBjAGsMAAAFAFsAagwAAAQAWgBsDAAAAwBhAG0MAAABACEA6gwAAAgAXwBuDAAAAQBBAC4ABAp/KQACCwAJCcAhwAMAmQMACwAJCcAhwAMAmQMAAAA=.Grogvald:BAABLgAECn8kAAINAAgJ0CMuBgAZAwhoDAAABQBXAGkMAAAGAGAAawwAAAYAXwBqDAAABQBaAGwMAAADAF8AbQwAAAMAYQDqDAAABgBcAG4MAAACAE0ADQAICdAjLgYAGQMIaAwAAAUAVwBpDAAABgBgAGsMAAAGAF8AagwAAAUAWgBsDAAAAwBfAG0MAAADAGEA6gwAAAYAXABuDAAAAgBNAAAA.',
['Gø']='Gøober:BAACLgAFFH8oAAQMAAgJwBpxBAAeAghoDAAABwBdAGkMAAAHAGMAawwAAAYAUgBqDAAABQA4AGwMAAAEAEUAbQwAAAEABgDqDAAACQBYAG4MAAABACgADAAHCbQacQQAHgIHaAwAAAEAXQBpDAAAAwBjAGsMAAACAFIAagwAAAMALgBtDAAAAQAGAOoMAAAGAFgAbgwAAAEAKAATAAYJ4RucAwAPAgZoDAAABABUAGkMAAADAEYAawwAAAMAQgBqDAAAAgA4AGwMAAAEAEUA6gwAAAMAQQACAAMJICH6EwAdAQNoDAAAAgBbAGkMAAABAFUAawwAAAEATQAuAAQKf0IABBMACQlCJoMDAG0DABMACQkUIYMDAG0DAAIACQnlIJEEANcCAAwABwmqJOEYAHkCAAAA.',
Ha='Hadrick:BAAALgADCgYJBgAAAA==.',
He='Herax:BAABLgAECn8hAAIQAAgJ4xpfGQD+AQhoDAAABQBYAGkMAAAEAEUAawwAAAUAQgBqDAAABAA/AGwMAAADAFgAbQwAAAIAIgDqDAAABwBfAG4MAAADACcAEAAICeMaXxkA/gEIaAwAAAUAWABpDAAABABFAGsMAAAFAEIAagwAAAQAPwBsDAAAAwBYAG0MAAACACIA6gwAAAcAXwBuDAAAAwAnAAAA.',
Hi='Hidrógeno:BAACLgAFFH8FAAIJAAMJLgxEXwDMAANoDAAAAgA1AGkMAAABABMA6gwAAAIAFAAJAAMJLgxEXwDMAANoDAAAAgA1AGkMAAABABMA6gwAAAIAFAAuAAQKfxcAAgkACAkrHssxAFsCAAkACAkrHssxAFsCAAAA.Hinigy:BAAALgAECgUJBgABLgAECggJKAAUALoWAA==.',
Ho='Hoofartted:BAACLgAFFH8GAAIRAAMJUhiUCQD1AANoDAAAAgBQAGkMAAABAC4A6gwAAAMAPAARAAMJUhiUCQD1AANoDAAAAgBQAGkMAAABAC4A6gwAAAMAPAAuAAQKfzkAAhEACAnOI4QDALQCABEACAnOI4QDALQCAAAA.Horchata:BAAALgAECgMJCAAAAA==.Horndawg:BAAALgADCgkJHAAAAA==.',
Il='Illidara:BAAALgAECgMJAwABLgAFFAMJBgAOADkWAA==.',
Is='Istarìa:BAAALgADCgkJHAAAAA==.',
Jo='Jollyrancher:BAAALgADCgYJBgAAAA==.',
Ju='Judgejobrown:BAABLgAECn8gAAIVAAkJLhZ6NwAiAgloDAAABQA8AGkMAAAFAEgAawwAAAQAQQBqDAAABABUAGwMAAAEADcAbQwAAAEAEADqDAAABQBIAG4MAAADAD0AbwwAAAEAMwAVAAkJLhZ6NwAiAgloDAAABQA8AGkMAAAFAEgAawwAAAQAQQBqDAAABABUAGwMAAAEADcAbQwAAAEAEADqDAAABQBIAG4MAAADAD0AbwwAAAEAMwAAAA==.',
Ka='Katarina:BAAALgAECgEJAQAAAA==.',
Kh='Khajiit:BAABLgAECn8YAAIWAAcJ4x2jIwCSAQdoDAAABQBQAGkMAAADAFAAawwAAAQAQABqDAAAAwBXAGwMAAABAEYA6gwAAAUAUABuDAAAAwBSABYABwnjHaMjAJIBB2gMAAAFAFAAaQwAAAMAUABrDAAABABAAGoMAAADAFcAbAwAAAEARgDqDAAABQBQAG4MAAADAFIAAAA=.',
Ki='Kijana:BAABLgAFFH8IAAIMAAQJ6iS5EACYAQRoDAAAAgBiAGkMAAACAF8AawwAAAEAVgDqDAAAAwBhAAwABAnqJLkQAJgBBGgMAAACAGIAaQwAAAIAXwBrDAAAAQBWAOoMAAADAGEAAS4ABRQFCRYADADIJgA=.Kindraa:BAAALgADCgkJIQAAAA==.',
La='Lardpile:BAAALgADCgYJBgAAAA==.Lazaria:BAAALgAECgcJDQAAAA==.',
Le='Leveltwo:BAABLgAECn8+AAMCAAkJER5QBQDFAgloDAAACABXAGkMAAAIAFgAawwAAAgANABqDAAACABSAGwMAAAHAFIAbQwAAAUAUgDqDAAACQBEAG4MAAAGAE8AbwwAAAMASQACAAkJER5QBQDFAgloDAAACABXAGkMAAAIAFgAawwAAAcANABqDAAACABSAGwMAAAHAFIAbQwAAAUAUgDqDAAACQBEAG4MAAAGAE8AbwwAAAMASQATAAEJFhEqNQA1AAFrDAAAAQArAAAA.',
Li='Litguine:BAAALgAECgQJBgAAAA==.Littlestar:BAABLgAECn85AAIIAAgJkxPmGgDVAQhoDAAACAA7AGkMAAAIADgAawwAAAgAPwBqDAAABwA1AGwMAAAIAD8AbQwAAAMAGADqDAAACgAqAG4MAAAFACYACAAICZMT5hoA1QEIaAwAAAgAOwBpDAAACAA4AGsMAAAIAD8AagwAAAcANQBsDAAACAA/AG0MAAADABgA6gwAAAoAKgBuDAAABQAmAAAA.',
Lo='Lockdnloadd:BAAALgADCgUJCAAAAA==.',
Lu='Lucyfurr:BAAALgAECgUJBgABLgAECgkJLAAXALQgAA==.Lunea:BAAALgAECgYJCgAAAA==.',
Ly='Lyraa:BAAALgADCgYJEAAAAA==.',
Ma='Marvel:BAAALgADCgkJEwAAAA==.Mattystaff:BAAALgADCgUJBQABLgAECgEJAQAYAAAAAA==.',
Me='Melanreu:BAAALgAECgEJAQAAAA==.Melvang:BAAALgAECgIJAgAAAA==.',
My='Myrddraal:BAAALgADCgcJCgAAAA==.Mythicc:BAAALgAECgYJBwAAAA==.',
Na='Naenae:BAAALgAECgEJAgAAAA==.Nastybob:BAABLgAECn8zAAILAAkJtyT2BQA8AwloDAAABgBjAGkMAAAGAGEAawwAAAYAXwBqDAAABgBTAGwMAAAGAFkAbQwAAAYAXwDqDAAABgBbAG4MAAAFAFcAbwwAAAQAYAALAAkJtyT2BQA8AwloDAAABgBjAGkMAAAGAGEAawwAAAYAXwBqDAAABgBTAGwMAAAGAFkAbQwAAAYAXwDqDAAABgBbAG4MAAAFAFcAbwwAAAQAYAAAAA==.',
Ni='Nicobulus:BAABLgAECn8eAAIQAAgJ4w3INQBFAQhoDAAABQAoAGkMAAAFADMAawwAAAQAKQBqDAAABAASAGwMAAADABgAbQwAAAEAIQDqDAAABQAjAG4MAAADABYAEAAICeMNyDUARQEIaAwAAAUAKABpDAAABQAzAGsMAAAEACkAagwAAAQAEgBsDAAAAwAYAG0MAAABACEA6gwAAAUAIwBuDAAAAwAWAAAA.Nightspell:BAAALgAECgUJBgAAAA==.',
No='Nor:BAABLgAECn8XAAMNAAcJ7B3DHAAvAgdoDAAABABQAGkMAAAEAFQAawwAAAQAVgBqDAAAAwBMAGwMAAADAFsAbQwAAAEAIwDqDAAABABSAA0ABgmZIMMcAC8CBmgMAAADAFAAaQwAAAMAVABrDAAAAwBWAGoMAAACAEwAbAwAAAIAWwDqDAAABABSAAkABgmOFVSTAC8BBmgMAAABAD4AaQwAAAEAPwBrDAAAAQBOAGoMAAABADMAbAwAAAEAHwBtDAAAAQAoAAAA.',
['Nä']='Näota:BAAALgAECgEJAQAAAA==.',
Pa='Papanoellego:BAACLgAFFH8nAAIVAAgJ8xc7AwBHAghoDAAABwBfAGkMAAAHAGMAawwAAAYAXwBqDAAABQBQAGwMAAAEADEAbQwAAAEABQDqDAAACABQAG4MAAABAAMAFQAICfMXOwMARwIIaAwAAAcAXwBpDAAABwBjAGsMAAAGAF8AagwAAAUAUABsDAAABAAxAG0MAAABAAUA6gwAAAgAUABuDAAAAQADAC4ABAp/KQACFQAJCQEkOQMAywMAFQAJCQEkOQMAywMAAAA=.',
Ph='Phcicoknight:BAAALgADCgYJBgAAAA==.Pheal:BAABLgAECn8hAAMLAAgJ2hXJTwDAAQhoDAAABQA7AGkMAAAEADkAawwAAAUALABqDAAABAAvAGwMAAADAC8AbQwAAAIAJgDqDAAABwBIAG4MAAADAEcACwAICdoVyU8AwAEIaAwAAAUAOwBpDAAABAA5AGsMAAAFACwAagwAAAQALwBsDAAAAwAvAG0MAAACACYA6gwAAAYASABuDAAAAwBHABkAAQkDE28tADkAAeoMAAABADAAAAA=.Phiend:BAAALgAECgQJDgAAAA==.Phlak:BAAALgAECgYJDwAAAA==.',
Pl='Pluvl:BAABLgAECn8cAAIOAAgJ7QKYMAD9AAhoDAAAAwADAGkMAAADAAUAawwAAAMABABqDAAAAwACAGwMAAAFAAkAbQwAAAMACgDqDAAABgAHAG4MAAACAAoADgAICe0CmDAA/QAIaAwAAAMAAwBpDAAAAwAFAGsMAAADAAQAagwAAAMAAgBsDAAABQAJAG0MAAADAAoA6gwAAAYABwBuDAAAAgAKAAAA.',
Qu='Quimby:BAAALgAECgcJDQAAAA==.',
Ra='Raign:BAAALgADCgkJIAAAAA==.',
Re='Reyla:BAAALgADCgIJAgABLgAFFAcJHQAOAD4ZAA==.',
Rh='Rhyze:BAAALgAECgcJDgAAAA==.',
Ri='Rivent:BAAALgAECgYJCAAAAA==.Rivia:BAABLgAECn8cAAIJAAgJrBz2QQAfAghoDAAABABSAGkMAAAGAFsAawwAAAMALABqDAAAAwBBAGwMAAACAD4AbQwAAAIANwDqDAAABQBgAG4MAAADAFAACQAICawc9kEAHwIIaAwAAAQAUgBpDAAABgBbAGsMAAADACwAagwAAAMAQQBsDAAAAgA+AG0MAAACADcA6gwAAAUAYABuDAAAAwBQAAAA.',
Ro='Royalmace:BAAALgAECgQJBAAAAA==.',
Sa='Safaridan:BAABLgAECn8eAAQNAAkJFBpWGQBIAgloDAAABQA5AGkMAAAEAEEAawwAAAQAPgBqDAAABABHAGwMAAAEAFMAbQwAAAEALQDqDAAABABYAG4MAAADAD8AbwwAAAEAPwANAAkJFBpWGQBIAgloDAAABAA5AGkMAAADAEEAawwAAAMAPgBqDAAAAgBHAGwMAAADAFMAbQwAAAEALQDqDAAAAwBYAG4MAAACAD8AbwwAAAEAPwAaAAUJXgy/LQCXAAVoDAAAAQAbAGkMAAABACQAawwAAAEANgBqDAAAAgAuAGwMAAABAAgACQACCXoHjYIBKwAC6gwAAAEADwBuDAAAAQAWAAAA.Sapphirre:BAAALgADCgcJFwAAAA==.Savsham:BAAALgADCgEJAQAAAA==.',
Sc='Scamp:BAAALgAECgEJAgAAAA==.Scrump:BAAALgAECgQJBQAAAA==.',
Sh='Shtick:BAAALgADCggJDQAAAA==.',
Si='Sienen:BAAALgAECgUJCAAAAA==.',
Sj='Sjk:BAABLgAECn8WAAIGAAgJXyCjBgD8AghoDAAAAwBYAGkMAAAEAFcAawwAAAQAWQBqDAAAAwBTAGwMAAADAEgAbQwAAAIAUADqDAAAAgBcAG4MAAABAEQABgAICV8gowYA/AIIaAwAAAMAWABpDAAABABXAGsMAAAEAFkAagwAAAMAUwBsDAAAAwBIAG0MAAACAFAA6gwAAAIAXABuDAAAAQBEAAAA.',
Sl='Slabia:BAABLgAECn8VAAIJAAcJsCC4MQBcAgdoDAAABQBjAGkMAAAFAFgAawwAAAQAWABqDAAAAgBSAGwMAAACAD4A6gwAAAIAPgBuDAAAAQBjAAkABwmwILgxAFwCB2gMAAAFAGMAaQwAAAUAWABrDAAABABYAGoMAAACAFIAbAwAAAIAPgDqDAAAAgA+AG4MAAABAGMAAAA=.Slade:BAAALgAECgEJAQAAAA==.Slashly:BAAALgAECgEJBQAAAA==.Sloan:BAABLgAECn8ZAAIIAAYJigO9RgC7AAZoDAAABwAMAGkMAAAGAAkAawwAAAUACQBqDAAABAAJAGwMAAACAAkA6gwAAAEAAwAIAAYJigO9RgC7AAZoDAAABwAMAGkMAAAGAAkAawwAAAUACQBqDAAABAAJAGwMAAACAAkA6gwAAAEAAwAAAA==.',
Sp='Spektrum:BAAALgADCgEJAQAAAA==.Spicychicken:BAAALgAFFAEJAQABLgAFFAgJJAAbAIIZAA==.',
Sq='Squirrelydan:BAAALgADCgUJBQAAAA==.',
St='Stacey:BAAALgAECgQJBAABLgAFFAkJLgAKAJgfAA==.Stepmom:BAAALgAFFAIJAgAAAA==.Stepsis:BAAALgAFFAIJBAAAAA==.Sticky:BAAALgAECgIJAgABLgAFFAMJBQASAJIMAA==.Stiick:BAAALgADCgUJBQAAAA==.',
Sv='Svinehundt:BAABLgAECn8oAAIUAAgJuhbWOADoAQhoDAAACAA1AGkMAAAHAEUAawwAAAcANwBqDAAABABAAGwMAAAEAEgAbQwAAAIAPQDqDAAABwBNAG4MAAABABAAFAAICboW1jgA6AEIaAwAAAgANQBpDAAABwBFAGsMAAAHADcAagwAAAQAQABsDAAABABIAG0MAAACAD0A6gwAAAcATQBuDAAAAQAQAAAA.',
Ta='Tabtok:BAAALgADCgcJDgAAAA==.Tanalin:BAAALgADCgcJCgABLgAECggJKAAUALoWAA==.Tanglebones:BAABLgAECn8eAAIcAAYJmwxDEAAMAQZoDAAABgAxAGkMAAAGACAAawwAAAYAIwBqDAAABAAnAGwMAAACAA4A6gwAAAYAHQAcAAYJmwxDEAAMAQZoDAAABgAxAGkMAAAGACAAawwAAAYAIwBqDAAABAAnAGwMAAACAA4A6gwAAAYAHQAAAA==.Tasty:BAAALgAECgEJAQABLgAFFAQJEgAXAP0YAA==.Taukra:BAAALgADCgYJBgAAAA==.',
To='Tore:BAAALgAECgYJDAAAAA==.',
Tr='Trazie:BAAALgAECgYJCQAAAA==.Trenn:BAAALgADCgkJCQABLgAECggJEgAYAAAAAA==.',
Un='Unsocial:BAAALgADCgkJIQAAAA==.',
Ve='Vecna:BAAALgAECgEJAQABLgAECgYJCAAYAAAAAA==.Vermi:BAAALgAECgMJCAAAAA==.',
Wa='Warcloud:BAABLgAECn8YAAINAAgJ+AM1RwAHAQhoDAAAAwAWAGkMAAADAAgAawwAAAMACgBqDAAAAwADAGwMAAAEABIAbQwAAAIABADqDAAABAAIAG4MAAACAAQADQAICfgDNUcABwEIaAwAAAMAFgBpDAAAAwAIAGsMAAADAAoAagwAAAMAAwBsDAAABAASAG0MAAACAAQA6gwAAAQACABuDAAAAgAEAAAA.Wartortle:BAABLgAECn8vAAMdAAgJpBpKDwDaAQhoDAAACgBKAGkMAAAIAFUAawwAAAgAUQBqDAAACAA0AGwMAAAIAEsAbQwAAAIAKADqDAAAAgBNAG4MAAABACoAHQAICaQaSg8A2gEIaAwAAAkASgBpDAAACABVAGsMAAAIAFEAagwAAAgANABsDAAACABLAG0MAAACACgA6gwAAAIATQBuDAAAAQAqAB4AAQmdCclsACwAAWgMAAABABgAAAA=.',
Wh='Whack:BAAALgAECgYJBgAAAA==.Whiskeytf:BAAALgAECgYJDwAAAA==.',
Ws='Wsedfgghj:BAAALgAECgcJDAAAAA==.',
Wu='Wu:BAAALgAECgIJAgAAAA==.Wulfgaz:BAAALgAECgYJDwAAAA==.',
Wy='Wyldhart:BAAALgAECgEJAQAAAA==.Wylf:BAAALgADCgcJBwABLgAECgYJDwAYAAAAAA==.',
Xt='Xtheleon:BAAALgADCgYJCgAAAA==.',
Ze='Zenn:BAAALgAECggJEgAAAA==.Zeroomega:BAAALgADCgMJAwAAAA==.Zerø:BAAALgAECgEJAQAAAA==.',
Zi='Zinthous:BAAALgAECgEJAQAAAA==.',
['Äl']='Ältäir:BAABLgAECn8jAAIXAAgJhhgxLwDbAQhoDAAABgBTAGkMAAAFAEcAawwAAAUARQBqDAAABAAxAGwMAAADAEEAbQwAAAIANADqDAAABwBGAG4MAAADACcAFwAICYYYMS8A2wEIaAwAAAYAUwBpDAAABQBHAGsMAAAFAEUAagwAAAQAMQBsDAAAAwBBAG0MAAACADQA6gwAAAcARgBuDAAAAwAnAAAA.',
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
