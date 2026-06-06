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
local provider = {region='US',realm='Dethecus',name='US',type='daily',zone=46,date='2026-06-06',data={Aa='Aashley:BAAALgAECgcJBwAAAA==.',
Al='Alistis:BAAALgADCgEJAQAAAA==.',
Am='Amutio:BAAALgAECgMJCwAAAA==.',
An='Andromedus:BAAALgAFFAEJAgABLgAFFAgJJgABAOsbAA==.',
Ar='Arasis:BAACLgAFFH8FAAICAAMJeRr5FQARAQNoDAAAAgBfAGkMAAABABMA6gwAAAIAWAACAAMJeRr5FQARAQNoDAAAAgBfAGkMAAABABMA6gwAAAIAWAAuAAQKfzUAAgIACQl5JcUBADgDAAIACQl5JcUBADgDAAAA.Arìel:BAAALgADCgkJFQAAAA==.',
As='Ashhleyy:BAAALgAECgcJBgAAAA==.Ashhlleyy:BAAALgAECgcJAQAAAA==.Ashleyy:BAAALgAECgcJBgAAAA==.',
Ba='Balancing:BAABLgAFFH8HAAIDAAIJShukGwCeAAJoDAAABAA4AOoMAAADAFIAAwACCUobpBsAngACaAwAAAQAOADqDAAAAwBSAAAA.Bamag:BAABLgAECn8eAAIBAAgJgSLxBgA5AwhoDAAABQBfAGkMAAAFAGAAawwAAAUAYgBqDAAABABeAGwMAAAEAFwAbQwAAAIAXADqDAAABABcAG4MAAABADEAAQAICYEi8QYAOQMIaAwAAAUAXwBpDAAABQBgAGsMAAAFAGIAagwAAAQAXgBsDAAABABcAG0MAAACAFwA6gwAAAQAXABuDAAAAQAxAAAA.',
Bi='Bigmak:BAAALgAECggJCwAAAA==.',
Br='Braellyn:BAAALgAECgUJCQAAAA==.',
Bu='Burnyou:BAAALgADCgkJGwAAAA==.',
Ce='Celestine:BAAALgAECgEJAQAAAA==.Cenobité:BAABLgAECn8rAAMEAAgJqCTYCACtAghoDAAABwBgAGkMAAAIAGEAawwAAAYAXwBqDAAABQBYAGwMAAAFAGEAbQwAAAMAYADqDAAABgBeAG4MAAADAE4ABAAICagk2AgArQIIaAwAAAcAYABpDAAACABhAGsMAAAGAF8AagwAAAQAWABsDAAABABhAG0MAAADAGAA6gwAAAYAXgBuDAAAAwBOAAUAAgk/G+9wAH8AAmoMAAABAC0AbAwAAAEARQAAAA==.Ceridemon:BAABLgAECn8iAAIGAAkJ4g9pGwCSAQloDAAABQAlAGkMAAAFAEIAawwAAAUAIgBqDAAABAAjAGwMAAAEADoAbQwAAAMAIADqDAAABQAzAG4MAAACABEAbwwAAAEAGgAGAAkJ4g9pGwCSAQloDAAABQAlAGkMAAAFAEIAawwAAAUAIgBqDAAABAAjAGwMAAAEADoAbQwAAAMAIADqDAAABQAzAG4MAAACABEAbwwAAAEAGgAAAA==.',
Ch='Chingee:BAACLgAFFH8GAAMHAAYJ+QECGgDWAAZoDAAAAQACAGkMAAABAAIAawwAAAEAAwBqDAAAAQAGAGwMAAABAAsA6gwAAAEABAAHAAQJQgICGgDWAARpDAAAAQACAGsMAAABAAMAagwAAAEABgBsDAAAAQALAAgAAglmARZAAFgAAmgMAAABAAIA6gwAAAEABAAuAAQKf0wAAwgACQnHGqIJAKECAAgACQnsGaIJAKECAAcACAmLDkAmALoBAAAA.',
Co='Cobel:BAAALgAECgMJAwAAAA==.Consarios:BAABLgAFFH8HAAIJAAYJHRlVFQCgAQZoDAAAAQBPAGkMAAABAFMAawwAAAEATwBqDAAAAQAuAGwMAAABABMA6gwAAAIAOgAJAAYJHRlVFQCgAQZoDAAAAQBPAGkMAAABAFMAawwAAAEATwBqDAAAAQAuAGwMAAABABMA6gwAAAIAOgAAAA==.',
Cr='Croakadin:BAAALgADCgcJEAAAAA==.Crushers:BAAALgADCggJCAAAAA==.',
Cy='Cyraanden:BAACLgAFFH8RAAMEAAQJ3A3uIwC8AARoDAAABQAlAGkMAAAGACEAawwAAAEAJgDqDAAABQAgAAUAAwltCtg2AL8AA2gMAAABABoAaQwAAAEADwBrDAAAAQAmAAQAAwmBDe4jALwAA2gMAAAEACUAaQwAAAUAIQDqDAAABQAgAC4ABAp/NQADBAAJCbsagBAAOQIABAAJCU4agBAAOQIABQAECR4U3ksAyAAAAAA=.Cyvus:BAABLgAECn8kAAMHAAgJawVZQwArAQhoDAAABgAIAGkMAAAGAAUAawwAAAUAEwBqDAAABQAZAGwMAAAFABAAbQwAAAIAEQDqDAAABgAPAG4MAAABAAAABwAICWsFWUMAKwEIaAwAAAIACABpDAAAAgAFAGsMAAADABMAagwAAAIAGQBsDAAAAgAQAG0MAAACABEA6gwAAAMADwBuDAAAAQAAAAoABgn7CfhHAOUABmgMAAAEACYAaQwAAAQAFQBrDAAAAgAcAGoMAAADABIAbAwAAAMAFADqDAAAAwASAAAA.',
Da='Dab:BAABLgAECn9BAAILAAkJhSXlAwBfAwloDAAACQBgAGkMAAAJAGMAawwAAAkAYQBqDAAABwBhAGwMAAAIAGAAbQwAAAYAYwDqDAAACgBfAG4MAAAFAFQAbwwAAAIAYwALAAkJhSXlAwBfAwloDAAACQBgAGkMAAAJAGMAawwAAAkAYQBqDAAABwBhAGwMAAAIAGAAbQwAAAYAYwDqDAAACgBfAG4MAAAFAFQAbwwAAAIAYwAAAA==.Daedara:BAAALgAECgMJBAAAAA==.Daggz:BAABLgAECn8yAAMMAAkJER8LEgCnAgloDAAABwBXAGkMAAAHAFEAawwAAAcAXQBqDAAABgBVAGwMAAAFAE0AbQwAAAUAQADqDAAABwBOAG4MAAAEAFcAbwwAAAIAQgAMAAgJtx8LEgCnAghoDAAABQBXAGkMAAAFAFEAawwAAAUAXQBqDAAABAA/AGwMAAADAE0AbQwAAAMAPgDqDAAABQBOAG4MAAADAFcAAgAJCfUYMQsAaQIJaAwAAAIAVgBpDAAAAgBQAGsMAAACAEwAagwAAAIAVQBsDAAAAgAtAG0MAAACAEAA6gwAAAIAPABuDAAAAQAfAG8MAAACAEIAAAA=.Dansgrundle:BAAALgAECgMJAwABLgAECgkJHgANABQaAA==.Darkhorse:BAABLgAECn8mAAIOAAgJwh6FCwBgAghoDAAACABTAGkMAAAIAF0AawwAAAUAVgBqDAAABABeAGwMAAAEAFcAbQwAAAEADADqDAAABgBcAG4MAAACAF4ADgAICcIehQsAYAIIaAwAAAgAUwBpDAAACABdAGsMAAAFAFYAagwAAAQAXgBsDAAABABXAG0MAAABAAwA6gwAAAYAXABuDAAAAgBeAAAA.Darkmer:BAABLgAECn8xAAILAAcJ3wjSogAeAQdoDAAACgAWAGkMAAAKABkAawwAAAkAFABqDAAABgAQAGwMAAAFACMA6gwAAAgAFgBuDAAAAQAKAAsABwnfCNKiAB4BB2gMAAAKABYAaQwAAAoAGQBrDAAACQAUAGoMAAAGABAAbAwAAAUAIwDqDAAACAAWAG4MAAABAAoAAAA=.',
De='Deathsnight:BAAALgAECgUJBwAAAA==.Derpy:BAAALgADCgYJCQAAAA==.Deynestta:BAAALgAECgIJBAAAAA==.',
Di='Dixiereaper:BAABLgAECn8WAAIPAAkJahBrGgB+AQloDAAAAwBMAGkMAAADADwAawwAAAMALABqDAAAAgAvAGwMAAADACUAbQwAAAIAHgDqDAAAAwAcAG4MAAACAC0AbwwAAAEADQAPAAkJahBrGgB+AQloDAAAAwBMAGkMAAADADwAawwAAAMALABqDAAAAgAvAGwMAAADACUAbQwAAAIAHgDqDAAAAwAcAG4MAAACAC0AbwwAAAEADQAAAA==.',
Dr='Droopin:BAAALgADCgYJBwAAAA==.',
Ds='Ds:BAAALgAECgcJCwAAAA==.Dsntdrptotem:BAABLgAECn8wAAMQAAkJVBXiIQDHAQloDAAABgA8AGkMAAAFADUAawwAAAYANQBqDAAABQAuAGwMAAAGADcAbQwAAAQAGgDqDAAABgA3AG4MAAAFAFgAbwwAAAUAKwAQAAkJZRLiIQDHAQloDAAAAgAnAGkMAAABADEAawwAAAIAHwBqDAAAAgAuAGwMAAADADcAbQwAAAMAGgDqDAAAAwAqAG4MAAAFAFgAbwwAAAUAKwARAAcJ2BGDEwCBAQdoDAAABAA8AGkMAAAEADUAawwAAAQANQBqDAAAAwAWAGwMAAADADAAbQwAAAEAAgDqDAAAAwA3AAAA.',
Dt='Dtothep:BAAALgAECgEJAQAAAA==.',
El='Elfangar:BAAALgADCgcJBwAAAA==.',
Ep='Epicamerican:BAAALgAECgUJBQAAAA==.',
Ff='Ffecanti:BAAALgAECgYJCQAAAA==.',
Fl='Floury:BAAALgAECgMJAwAAAA==.',
Ga='Gailen:BAAALgADCgkJDgAAAA==.',
Gi='Gideonn:BAAALgADCgMJAwAAAA==.',
Go='Gorber:BAABLgAECn8WAAISAAgJDRaMIADMAQhoDAAAAwA9AGkMAAADAEMAawwAAAMAQQBqDAAAAwBLAGwMAAADAEwAbQwAAAIAIADqDAAAAwA4AG4MAAACACMAEgAICQ0WjCAAzAEIaAwAAAMAPQBpDAAAAwBDAGsMAAADAEEAagwAAAMASwBsDAAAAwBMAG0MAAACACAA6gwAAAMAOABuDAAAAgAjAAEuAAUUCAkoAAwAwBoA.Gorberfn:BAAALgAECgMJAwABLgAFFAgJKAAMAMAaAA==.',
Gr='Grimorn:BAACLgAFFH8iAAILAAgJfyDxAABGAghoDAAABgBjAGkMAAAGAGMAawwAAAUAWwBqDAAABABaAGwMAAADAGEAbQwAAAEAIQDqDAAACABfAG4MAAABAEEACwAICX8g8QAARgIIaAwAAAYAYwBpDAAABgBjAGsMAAAFAFsAagwAAAQAWgBsDAAAAwBhAG0MAAABACEA6gwAAAgAXwBuDAAAAQBBAC4ABAp/KQACCwAJCcAhwAMAmQMACwAJCcAhwAMAmQMAAAA=.Grogvald:BAABLgAECn8rAAINAAgJYSVTAwBlAwhoDAAABgBfAGkMAAAHAGIAawwAAAcAYwBqDAAABgBjAGwMAAAEAGMAbQwAAAQAYQDqDAAABwBiAG4MAAACAE0ADQAICWElUwMAZQMIaAwAAAYAXwBpDAAABwBiAGsMAAAHAGMAagwAAAYAYwBsDAAABABjAG0MAAAEAGEA6gwAAAcAYgBuDAAAAgBNAAAA.',
['Gø']='Gøober:BAACLgAFFH8oAAQMAAgJwBqKBwAVAghoDAAABwBdAGkMAAAHAGMAawwAAAYAUgBqDAAABQA4AGwMAAAEAEUAbQwAAAEABgDqDAAACQBYAG4MAAABACgADAAHCbQaigcAFQIHaAwAAAEAXQBpDAAAAwBjAGsMAAACAFIAagwAAAMALgBtDAAAAQAGAOoMAAAGAFgAbgwAAAEAKAATAAYJ4RucAwAPAgZoDAAABABUAGkMAAADAEYAawwAAAMAQgBqDAAAAgA4AGwMAAAEAEUA6gwAAAMAQQACAAMJICFAFQAWAQNoDAAAAgBbAGkMAAABAFUAawwAAAEATQAuAAQKf0IABBMACQlCJoMDAG0DABMACQkUIYMDAG0DAAIACQnlIDsFANACAAwABwmqJF4bAHUCAAAA.',
Ha='Hadrick:BAAALgAECgUJBQAAAA==.',
He='Herax:BAABLgAECn8hAAIQAAgJ4xqhGwD3AQhoDAAABQBYAGkMAAAEAEUAawwAAAUAQgBqDAAABAA/AGwMAAADAFgAbQwAAAIAIgDqDAAABwBfAG4MAAADACcAEAAICeMaoRsA9wEIaAwAAAUAWABpDAAABABFAGsMAAAFAEIAagwAAAQAPwBsDAAAAwBYAG0MAAACACIA6gwAAAcAXwBuDAAAAwAnAAAA.',
Hi='Hidrógeno:BAACLgAFFH8FAAIJAAMJLgwebQDEAANoDAAAAgA1AGkMAAABABMA6gwAAAIAFAAJAAMJLgwebQDEAANoDAAAAgA1AGkMAAABABMA6gwAAAIAFAAuAAQKfxcAAgkACAkrHssxAFsCAAkACAkrHssxAFsCAAAA.Hinigy:BAAALgAECgUJBgABLgAECggJKAAUALoWAA==.',
Ho='Hoofartted:BAACLgAFFH8GAAIRAAMJUhjCCwDrAANoDAAAAgBQAGkMAAABAC4A6gwAAAMAPAARAAMJUhjCCwDrAANoDAAAAgBQAGkMAAABAC4A6gwAAAMAPAAuAAQKfzkAAhEACAnOI/cDALECABEACAnOI/cDALECAAAA.Horchata:BAAALgAECgMJCAAAAA==.Horndawg:BAAALgADCgkJHAAAAA==.',
Il='Illidara:BAAALgAECgMJAwABLgAFFAMJCQAOADkWAA==.',
Is='Istarìa:BAAALgADCgkJIgAAAA==.',
Jo='Jollyrancher:BAAALgADCgYJBgAAAA==.',
Ju='Judgejobrown:BAABLgAECn8gAAIVAAkJLhZVPAAiAgloDAAABQA8AGkMAAAFAEgAawwAAAQAQQBqDAAABABUAGwMAAAEADcAbQwAAAEAEADqDAAABQBIAG4MAAADAD0AbwwAAAEAMwAVAAkJLhZVPAAiAgloDAAABQA8AGkMAAAFAEgAawwAAAQAQQBqDAAABABUAGwMAAAEADcAbQwAAAEAEADqDAAABQBIAG4MAAADAD0AbwwAAAEAMwAAAA==.',
Ka='Katarina:BAAALgAECgEJAQAAAA==.',
Kh='Khajiit:BAABLgAECn8YAAIWAAcJ4x3KJQCRAQdoDAAABQBQAGkMAAADAFAAawwAAAQAQABqDAAAAwBXAGwMAAABAEYA6gwAAAUAUABuDAAAAwBSABYABwnjHcolAJEBB2gMAAAFAFAAaQwAAAMAUABrDAAABABAAGoMAAADAFcAbAwAAAEARgDqDAAABQBQAG4MAAADAFIAAAA=.',
Ki='Kijana:BAABLgAFFH8IAAIMAAQJ6iTVFwCQAQRoDAAAAgBiAGkMAAACAF8AawwAAAEAVgDqDAAAAwBhAAwABAnqJNUXAJABBGgMAAACAGIAaQwAAAIAXwBrDAAAAQBWAOoMAAADAGEAAS4ABRQICR4ADACdHAA=.Kindraa:BAAALgADCgkJKAAAAA==.',
La='Lardpile:BAAALgADCgYJBgAAAA==.Lazaria:BAAALgAECgcJDQAAAA==.',
Le='Leveltwo:BAABLgAECn9DAAQCAAkJER79BQC+AgloDAAACQBXAGkMAAAJAFgAawwAAAkANABqDAAACABSAGwMAAAHAFIAbQwAAAUAUgDqDAAACgBEAG4MAAAHAE8AbwwAAAMASQACAAkJER79BQC+AgloDAAACQBXAGkMAAAJAFgAawwAAAcANABqDAAACABSAGwMAAAHAFIAbQwAAAUAUgDqDAAACgBEAG4MAAAHAE8AbwwAAAMASQATAAEJFhH+NwA1AAFrDAAAAQArAAwAAQlWBKE0ASkAAWsMAAABAAsAAAA=.',
Li='Litguine:BAAALgAECgQJBgAAAA==.Littlestar:BAABLgAECn9BAAIIAAkJ4BPQFQAeAgloDAAACQA7AGkMAAAIADgAawwAAAkAPwBqDAAACAA1AGwMAAAJAD8AbQwAAAMAGADqDAAACwAqAG4MAAAHACYAbwwAAAEAOAAIAAkJ4BPQFQAeAgloDAAACQA7AGkMAAAIADgAawwAAAkAPwBqDAAACAA1AGwMAAAJAD8AbQwAAAMAGADqDAAACwAqAG4MAAAHACYAbwwAAAEAOAAAAA==.',
Lo='Lockdnloadd:BAAALgADCgUJCAAAAA==.',
Lu='Lucyfurr:BAAALgAECgUJBgABLgAECgkJLAAXALQgAA==.Lunea:BAAALgAECgYJCgAAAA==.',
Ly='Lyraa:BAAALgADCgYJEAAAAA==.',
Ma='Marvel:BAAALgADCgkJEwAAAA==.Mattystaff:BAAALgADCgUJBQABLgAECgMJAwAYAAAAAA==.',
Me='Melanreu:BAAALgAECgEJAQAAAA==.Melvang:BAAALgAECgIJAgAAAA==.',
My='Myrddraal:BAAALgAECgUJBQAAAA==.Mythicc:BAAALgAECgYJBwAAAA==.',
Na='Naenae:BAAALgAECgMJBAAAAA==.Nastybob:BAABLgAECn8zAAILAAkJtyQJBwA4AwloDAAABgBjAGkMAAAGAGEAawwAAAYAXwBqDAAABgBTAGwMAAAGAFkAbQwAAAYAXwDqDAAABgBbAG4MAAAFAFcAbwwAAAQAYAALAAkJtyQJBwA4AwloDAAABgBjAGkMAAAGAGEAawwAAAYAXwBqDAAABgBTAGwMAAAGAFkAbQwAAAYAXwDqDAAABgBbAG4MAAAFAFcAbwwAAAQAYAAAAA==.',
Ni='Nicobulus:BAABLgAECn8hAAIQAAkJHBBzKQCWAQloDAAABQAoAGkMAAAFADMAawwAAAQAKQBqDAAABAASAGwMAAADABgAbQwAAAEAIQDqDAAABgA6AG4MAAAEACEAbwwAAAEALwAQAAkJHBBzKQCWAQloDAAABQAoAGkMAAAFADMAawwAAAQAKQBqDAAABAASAGwMAAADABgAbQwAAAEAIQDqDAAABgA6AG4MAAAEACEAbwwAAAEALwAAAA==.Nightspell:BAAALgAECgUJBwAAAA==.',
No='Nor:BAABLgAECn8XAAMNAAcJ7B3DHAAvAgdoDAAABABQAGkMAAAEAFQAawwAAAQAVgBqDAAAAwBMAGwMAAADAFsAbQwAAAEAIwDqDAAABABSAA0ABgmZIMMcAC8CBmgMAAADAFAAaQwAAAMAVABrDAAAAwBWAGoMAAACAEwAbAwAAAIAWwDqDAAABABSAAkABgmOFQKdADABBmgMAAABAD4AaQwAAAEAPwBrDAAAAQBOAGoMAAABADMAbAwAAAEAHwBtDAAAAQAoAAAA.',
['Nä']='Näota:BAAALgAECgEJAQAAAA==.',
Pa='Papanoellego:BAACLgAFFH8nAAIVAAgJ8xc7AwBHAghoDAAABwBfAGkMAAAHAGMAawwAAAYAXwBqDAAABQBQAGwMAAAEADEAbQwAAAEABQDqDAAACABQAG4MAAABAAMAFQAICfMXOwMARwIIaAwAAAcAXwBpDAAABwBjAGsMAAAGAF8AagwAAAUAUABsDAAABAAxAG0MAAABAAUA6gwAAAgAUABuDAAAAQADAC4ABAp/KQACFQAJCQEkOQMAywMAFQAJCQEkOQMAywMAAAA=.',
Ph='Phcicoknight:BAAALgADCgYJBgAAAA==.Pheal:BAABLgAECn8hAAMLAAgJ2hX3VAC+AQhoDAAABQA7AGkMAAAEADkAawwAAAUALABqDAAABAAvAGwMAAADAC8AbQwAAAIAJgDqDAAABwBIAG4MAAADAEcACwAICdoV91QAvgEIaAwAAAUAOwBpDAAABAA5AGsMAAAFACwAagwAAAQALwBsDAAAAwAvAG0MAAACACYA6gwAAAYASABuDAAAAwBHABkAAQkDE/4zADgAAeoMAAABADAAAAA=.Phiend:BAAALgAECgQJDgAAAA==.Phlak:BAABLgAECn8UAAIXAAYJVAvXcAD5AAZoDAAABQApAGkMAAADABAAawwAAAMAFABqDAAAAgAcAGwMAAABAB4A6gwAAAYAJQAXAAYJVAvXcAD5AAZoDAAABQApAGkMAAADABAAawwAAAMAFABqDAAAAgAcAGwMAAABAB4A6gwAAAYAJQAAAA==.',
Pl='Pluvl:BAABLgAECn8eAAIOAAkJkQMzKQA+AQloDAAAAwADAGkMAAADAAUAawwAAAMABABqDAAAAwACAGwMAAAFAAkAbQwAAAMACgDqDAAABwAJAG4MAAACAAoAbwwAAAEAEgAOAAkJkQMzKQA+AQloDAAAAwADAGkMAAADAAUAawwAAAMABABqDAAAAwACAGwMAAAFAAkAbQwAAAMACgDqDAAABwAJAG4MAAACAAoAbwwAAAEAEgAAAA==.',
['Pö']='Pöstal:BAAALgAECgEJAQAAAA==.',
Qu='Quimby:BAAALgAECgcJDgAAAA==.',
Ra='Raign:BAAALgAECgUJBQAAAA==.',
Re='Reyla:BAAALgADCgIJAgABLgAFFAcJHQAOAD4ZAA==.',
Rh='Rhyze:BAAALgAECgcJDgAAAA==.',
Ri='Rivent:BAAALgAECgYJCAAAAA==.Rivia:BAABLgAECn8cAAIJAAgJrBz2QQAfAghoDAAABABSAGkMAAAGAFsAawwAAAMALABqDAAAAwBBAGwMAAACAD4AbQwAAAIANwDqDAAABQBgAG4MAAADAFAACQAICawc9kEAHwIIaAwAAAQAUgBpDAAABgBbAGsMAAADACwAagwAAAMAQQBsDAAAAgA+AG0MAAACADcA6gwAAAUAYABuDAAAAwBQAAAA.',
Ro='Royalmace:BAAALgAECgQJBAAAAA==.',
Sa='Saannthh:BAAALgAECgcJBwAAAA==.Safaridan:BAABLgAECn8eAAQNAAkJFBpWGQBIAgloDAAABQA5AGkMAAAEAEEAawwAAAQAPgBqDAAABABHAGwMAAAEAFMAbQwAAAEALQDqDAAABABYAG4MAAADAD8AbwwAAAEAPwANAAkJFBpWGQBIAgloDAAABAA5AGkMAAADAEEAawwAAAMAPgBqDAAAAgBHAGwMAAADAFMAbQwAAAEALQDqDAAAAwBYAG4MAAACAD8AbwwAAAEAPwAaAAUJXgyGMACXAAVoDAAAAQAbAGkMAAABACQAawwAAAEANgBqDAAAAgAuAGwMAAABAAgACQACCXoH8ZUBKwAC6gwAAAEADwBuDAAAAQAWAAAA.Saimie:BAAALgAECgkJAQAAAA==.Sapphirre:BAAALgADCgkJGgAAAA==.Savsham:BAAALgADCgEJAQAAAA==.',
Sc='Scamp:BAAALgAECgEJAgAAAA==.Scrump:BAAALgAECgQJBQAAAA==.',
Sh='Shtick:BAAALgADCggJDQAAAA==.',
Si='Sienen:BAAALgAECgUJCwAAAA==.',
Sj='Sjk:BAABLgAECn8WAAIGAAgJXyCjBgD8AghoDAAAAwBYAGkMAAAEAFcAawwAAAQAWQBqDAAAAwBTAGwMAAADAEgAbQwAAAIAUADqDAAAAgBcAG4MAAABAEQABgAICV8gowYA/AIIaAwAAAMAWABpDAAABABXAGsMAAAEAFkAagwAAAMAUwBsDAAAAwBIAG0MAAACAFAA6gwAAAIAXABuDAAAAQBEAAAA.',
Sk='Skass:BAAALgAECgIJAgAAAA==.',
Sl='Slabia:BAABLgAECn8VAAIJAAcJsCC4MQBcAgdoDAAABQBjAGkMAAAFAFgAawwAAAQAWABqDAAAAgBSAGwMAAACAD4A6gwAAAIAPgBuDAAAAQBjAAkABwmwILgxAFwCB2gMAAAFAGMAaQwAAAUAWABrDAAABABYAGoMAAACAFIAbAwAAAIAPgDqDAAAAgA+AG4MAAABAGMAAAA=.Slade:BAAALgAECgEJAQAAAA==.Slashly:BAAALgAECgEJBQAAAA==.Sloan:BAABLgAECn8ZAAIIAAYJigNzSQDOAAZoDAAABwAMAGkMAAAGAAkAawwAAAUACQBqDAAABAAJAGwMAAACAAkA6gwAAAEAAwAIAAYJigNzSQDOAAZoDAAABwAMAGkMAAAGAAkAawwAAAUACQBqDAAABAAJAGwMAAACAAkA6gwAAAEAAwAAAA==.',
Sp='Spektrum:BAAALgADCgEJAQAAAA==.Spicychicken:BAAALgAFFAEJAgABLgAFFAgJJAAbAIIZAA==.',
Sq='Squirrelydan:BAAALgADCgUJBQAAAA==.',
St='Stacey:BAAALgAECgQJBAABLgAFFAkJLwAKAJgfAA==.Stepmom:BAAALgAFFAIJAgAAAA==.Stepsis:BAAALgAFFAIJBAAAAA==.Sticky:BAAALgAECgIJAgABLgAFFAQJCQASAGUPAA==.Stiick:BAAALgADCgUJBQAAAA==.',
Sv='Svinehundt:BAABLgAECn8oAAIUAAgJuhbRPADiAQhoDAAACAA1AGkMAAAHAEUAawwAAAcANwBqDAAABABAAGwMAAAEAEgAbQwAAAIAPQDqDAAABwBNAG4MAAABABAAFAAICboW0TwA4gEIaAwAAAgANQBpDAAABwBFAGsMAAAHADcAagwAAAQAQABsDAAABABIAG0MAAACAD0A6gwAAAcATQBuDAAAAQAQAAAA.',
Ta='Tabtok:BAAALgADCgcJDgAAAA==.Tanalin:BAAALgADCgcJCgABLgAECggJKAAUALoWAA==.Tanglebones:BAABLgAECn8qAAIcAAYJBw3zEAALAQZoDAAACAAxAGkMAAAIACIAawwAAAgAIwBqDAAABgAnAGwMAAAEABEA6gwAAAgAHQAcAAYJBw3zEAALAQZoDAAACAAxAGkMAAAIACIAawwAAAgAIwBqDAAABgAnAGwMAAAEABEA6gwAAAgAHQAAAA==.Tasty:BAAALgAECgEJAQABLgAFFAQJFgAXAOMbAA==.Taukra:BAAALgADCgYJBgAAAA==.',
To='Tore:BAAALgAECgYJDAAAAA==.',
Tr='Trazie:BAAALgAECgYJCQAAAA==.Trenn:BAAALgADCgkJCQABLgAECggJEgAYAAAAAA==.',
Un='Unsocial:BAAALgAECgIJAwAAAA==.',
Ve='Vecna:BAAALgAECgEJAQABLgAECgYJCAAYAAAAAA==.Vermi:BAAALgAECgMJCAAAAA==.',
Wa='Warcloud:BAABLgAECn8aAAINAAkJEQRkRAAkAQloDAAAAwAWAGkMAAADAAgAawwAAAMACgBqDAAAAwADAGwMAAAEABIAbQwAAAIABADqDAAABQAMAG4MAAACAAQAbwwAAAEACAANAAkJEQRkRAAkAQloDAAAAwAWAGkMAAADAAgAawwAAAMACgBqDAAAAwADAGwMAAAEABIAbQwAAAIABADqDAAABQAMAG4MAAACAAQAbwwAAAEACAAAAA==.Wartortle:BAABLgAECn8wAAMdAAgJMhu3DwDgAQhoDAAACgBKAGkMAAAIAFUAawwAAAgAUQBqDAAACAA0AGwMAAAIAEsAbQwAAAIAKADqDAAAAwBXAG4MAAABACoAHQAICTIbtw8A4AEIaAwAAAkASgBpDAAACABVAGsMAAAIAFEAagwAAAgANABsDAAACABLAG0MAAACACgA6gwAAAMAVwBuDAAAAQAqAB4AAQmdCcV0ACwAAWgMAAABABgAAAA=.',
Wh='Whack:BAAALgAECgYJBgAAAA==.Whiskeytf:BAAALgAECgYJDwAAAA==.',
Ws='Wsedfgghj:BAAALgAECgcJDAAAAA==.',
Wu='Wu:BAAALgAECgMJBAAAAA==.Wulfgaz:BAAALgAECgcJEAAAAA==.',
Wy='Wyldhart:BAAALgAECgEJAQAAAA==.Wylf:BAAALgADCgcJBwABLgAECgcJEAAYAAAAAA==.',
Xt='Xtheleon:BAAALgADCgYJCgAAAA==.',
Ze='Zenn:BAAALgAECggJEgAAAA==.Zeroomega:BAAALgADCgMJAwAAAA==.Zerø:BAAALgAECgMJAwAAAA==.',
Zi='Zinthous:BAAALgAECgEJAQAAAA==.',
['Äl']='Ältäir:BAABLgAECn8jAAIXAAgJhhjEMgDaAQhoDAAABgBTAGkMAAAFAEcAawwAAAUARQBqDAAABAAxAGwMAAADAEEAbQwAAAIANADqDAAABwBGAG4MAAADACcAFwAICYYYxDIA2gEIaAwAAAYAUwBpDAAABQBHAGsMAAAFAEUAagwAAAQAMQBsDAAAAwBBAG0MAAACADQA6gwAAAcARgBuDAAAAwAnAAAA.',
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
