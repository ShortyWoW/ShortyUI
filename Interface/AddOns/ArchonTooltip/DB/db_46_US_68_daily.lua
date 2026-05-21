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

local lookup = {'Warrior-Fury','Hunter-Survival','Monk-Windwalker','Monk-Brewmaster','DemonHunter-Havoc','Priest-Discipline','Priest-Holy','Priest-Shadow','DeathKnight-Unholy','Hunter-BeastMastery','Paladin-Holy','Rogue-Subtlety','DeathKnight-Blood','Shaman-Elemental','Shaman-Enhancement','Evoker-Augmentation','Hunter-Marksmanship','Paladin-Retribution','Warlock-Demonology','Unknown-Unknown','Mage-Frost','Druid-Balance','Shaman-Restoration','Paladin-Protection','Rogue-Assassination','Warrior-Protection','Warrior-Arms',}
local provider = {region='US',realm='Dethecus',name='US',type='daily',zone=46,date='2026-05-20',data={Aa='Aashley:BAAALgAECgcJBwAAAA==.',
Al='Alistis:BAAALgADCgEJAQAAAA==.',
Am='Amutio:BAAALgAECgMJCwAAAA==.',
An='Andromedus:BAAALgAFFAEJAgABLgAFFAcJHgABACgcAA==.',
Ar='Arasis:BAABLgAECn81AAICAAkJeSX/AABOAwloDAAABwBgAGkMAAAIAGIAawwAAAgAYgBqDAAABgBdAGwMAAAFAGEAbQwAAAMAWwDqDAAACABgAG4MAAAHAF8AbwwAAAEAWgACAAkJeSX/AABOAwloDAAABwBgAGkMAAAIAGIAawwAAAgAYgBqDAAABgBdAGwMAAAFAGEAbQwAAAMAWwDqDAAACABgAG4MAAAHAF8AbwwAAAEAWgAAAA==.Arìel:BAAALgADCgYJCgAAAA==.',
As='Ashhleyy:BAAALgAECgcJBgAAAA==.Ashhlleyy:BAAALgAECgcJAQAAAA==.Ashleyy:BAAALgAECgcJBgAAAA==.',
Ba='Balancing:BAAALgAFFAIJAgAAAA==.Bamag:BAABLgAECn8eAAIBAAgJgSLxBgA5AwhoDAAABQBfAGkMAAAFAGAAawwAAAUAYgBqDAAABABeAGwMAAAEAFwAbQwAAAIAXADqDAAABABcAG4MAAABADEAAQAICYEi8QYAOQMIaAwAAAUAXwBpDAAABQBgAGsMAAAFAGIAagwAAAQAXgBsDAAABABcAG0MAAACAFwA6gwAAAQAXABuDAAAAQAxAAAA.',
Bi='Bigmak:BAAALgAECgEJAQAAAA==.',
Br='Braellyn:BAAALgAECgUJCQAAAA==.',
Bu='Burnyou:BAAALgADCggJEwAAAA==.',
Ce='Cenobité:BAABLgAECn8rAAMDAAgJpyQ3BgC/AghoDAAABwBgAGkMAAAIAGEAawwAAAYAXwBqDAAABQBYAGwMAAAFAGEAbQwAAAMAYADqDAAABgBeAG4MAAADAE4AAwAICackNwYAvwIIaAwAAAcAYABpDAAACABhAGsMAAAGAF8AagwAAAQAWABsDAAABABhAG0MAAADAGAA6gwAAAYAXgBuDAAAAwBOAAQAAgk/G+9wAH8AAmoMAAABAC0AbAwAAAEARQAAAA==.Ceridemon:BAABLgAECn8hAAIFAAgJpRCPGQBxAQhoDAAABQAlAGkMAAAFAEIAawwAAAUAIgBqDAAABAAjAGwMAAAEADoAbQwAAAMAIADqDAAABQAzAG4MAAACABEABQAICaUQjxkAcQEIaAwAAAUAJQBpDAAABQBCAGsMAAAFACIAagwAAAQAIwBsDAAABAA6AG0MAAADACAA6gwAAAUAMwBuDAAAAgARAAAA.',
Ch='Chingee:BAABLgAECn9MAAMGAAkJxxoiCgCWAgloDAAACgBcAGkMAAAKAEoAawwAAAoATQBqDAAACgA4AGwMAAAKAE4AbQwAAAcAMwDqDAAACwBSAG4MAAAGAFAAbwwAAAIAFgAGAAkJ7BkiCgCWAgloDAAACABQAGkMAAAIAEoAawwAAAgATQBqDAAACAA4AGwMAAAIAE4AbQwAAAYAKwDqDAAACQBSAG4MAAAFAFAAbwwAAAIAFgAHAAgJiw5AJgC6AQhoDAAAAgBcAGkMAAACAD8AawwAAAIAIwBqDAAAAgAMAGwMAAACAAcAbQwAAAEAMwDqDAAAAgAOAG4MAAABABMAAAA=.',
Co='Consarios:BAAALgAECgUJCAAAAA==.',
Cr='Croakadin:BAAALgADCgcJEAAAAA==.Crushers:BAAALgADCggJCAAAAA==.',
Cy='Cyraanden:BAACLgAFFH8NAAIDAAMJgQ1FGQDLAANoDAAABAAlAGkMAAAFACEA6gwAAAQAIAADAAMJgQ1FGQDLAANoDAAABAAlAGkMAAAFACEA6gwAAAQAIAAuAAQKfzUAAwMACQm6Gj8MAE4CAAMACQlOGj8MAE4CAAQABAkdFNZCAMoAAAAA.Cyvus:BAABLgAECn8kAAMHAAgJagVZQwArAQhoDAAABgAIAGkMAAAGAAUAawwAAAUAEwBqDAAABQAZAGwMAAAFABAAbQwAAAIAEQDqDAAABgAPAG4MAAABAAAABwAICWoFWUMAKwEIaAwAAAIACABpDAAAAgAFAGsMAAADABMAagwAAAIAGQBsDAAAAgAQAG0MAAACABEA6gwAAAMADwBuDAAAAQAAAAgABgn7CWQ7AO4ABmgMAAAEACYAaQwAAAQAFQBrDAAAAgAcAGoMAAADABIAbAwAAAMAFADqDAAAAwASAAAA.',
Da='Dab:BAABLgAECn84AAIJAAkJFSXQAgBeAwloDAAACABgAGkMAAAIAGMAawwAAAgAYQBqDAAABgBhAGwMAAAHAGAAbQwAAAUAYwDqDAAACQBfAG4MAAAEAEsAbwwAAAEAYwAJAAkJFSXQAgBeAwloDAAACABgAGkMAAAIAGMAawwAAAgAYQBqDAAABgBhAGwMAAAHAGAAbQwAAAUAYwDqDAAACQBfAG4MAAAEAEsAbwwAAAEAYwAAAA==.Daedara:BAAALgAECgMJBAAAAA==.Daggz:BAABLgAECn8yAAMKAAkJEB8LEgCnAgloDAAABwBXAGkMAAAHAFEAawwAAAcAXQBqDAAABgBVAGwMAAAFAE0AbQwAAAUAQADqDAAABwBOAG4MAAAEAFcAbwwAAAIAQgAKAAgJth8LEgCnAghoDAAABQBXAGkMAAAFAFEAawwAAAUAXQBqDAAABAA/AGwMAAADAE0AbQwAAAMAPgDqDAAABQBOAG4MAAADAFcAAgAJCfUY6gcAfQIJaAwAAAIAVgBpDAAAAgBQAGsMAAACAEwAagwAAAIAVQBsDAAAAgAtAG0MAAACAEAA6gwAAAIAPABuDAAAAQAfAG8MAAACAEIAAAA=.Dansgrundle:BAAALgAECgMJAwABLgAECgkJHgALABQaAA==.Darkhorse:BAABLgAECn8iAAIMAAgJIB48CQBjAghoDAAABwBTAGkMAAAHAF0AawwAAAQAVgBqDAAABABeAGwMAAAEAFcAbQwAAAEADADqDAAABQBRAG4MAAACAF4ADAAICSAePAkAYwIIaAwAAAcAUwBpDAAABwBdAGsMAAAEAFYAagwAAAQAXgBsDAAABABXAG0MAAABAAwA6gwAAAUAUQBuDAAAAgBeAAAA.Darkmer:BAABLgAECn8kAAIJAAYJ3AWjuADYAAZoDAAACAAPAGkMAAAIABMAawwAAAcADQBqDAAABAAQAGwMAAADAA4A6gwAAAYACwAJAAYJ3AWjuADYAAZoDAAACAAPAGkMAAAIABMAawwAAAcADQBqDAAABAAQAGwMAAADAA4A6gwAAAYACwAAAA==.',
De='Deathsnight:BAAALgAECgUJBwAAAA==.Derpy:BAAALgADCgYJCQAAAA==.Deynestta:BAAALgAECgIJBAAAAA==.',
Di='Dixiereaper:BAABLgAECn8WAAINAAkJahBrGgB+AQloDAAAAwBMAGkMAAADADwAawwAAAMALABqDAAAAgAvAGwMAAADACUAbQwAAAIAHgDqDAAAAwAcAG4MAAACAC0AbwwAAAEADQANAAkJahBrGgB+AQloDAAAAwBMAGkMAAADADwAawwAAAMALABqDAAAAgAvAGwMAAADACUAbQwAAAIAHgDqDAAAAwAcAG4MAAACAC0AbwwAAAEADQAAAA==.',
Dr='Droopin:BAAALgADCgYJBwAAAA==.',
Ds='Ds:BAAALgAECgYJCgAAAA==.Dsntdrptotem:BAABLgAECn8rAAMOAAkJiRSBGwDLAQloDAAABgA8AGkMAAAFADUAawwAAAYANQBqDAAABQAuAGwMAAAGADcAbQwAAAQAGgDqDAAABQA3AG4MAAADAFgAbwwAAAMAGwAOAAkJmhGBGwDLAQloDAAAAgAnAGkMAAABADEAawwAAAIAHwBqDAAAAgAuAGwMAAADADcAbQwAAAMAGgDqDAAAAgAqAG4MAAADAFgAbwwAAAMAGwAPAAcJ2BGDEwCBAQdoDAAABAA8AGkMAAAEADUAawwAAAQANQBqDAAAAwAWAGwMAAADADAAbQwAAAEAAgDqDAAAAwA3AAAA.',
Dt='Dtothep:BAAALgAECgEJAQAAAA==.',
El='Elfangar:BAAALgADCgcJBwAAAA==.',
Ep='Epicamerican:BAAALgAECgEJAQAAAA==.',
Ff='Ffecanti:BAAALgAECgYJCQAAAA==.',
Fl='Floury:BAAALgAECgMJAwAAAA==.',
Ga='Gailen:BAAALgADCgkJDgAAAA==.',
Gi='Gideonn:BAAALgADCgMJAwAAAA==.',
Go='Gorber:BAABLgAECn8WAAIQAAgJDBaZGgDUAQhoDAAAAwA9AGkMAAADAEMAawwAAAMAQQBqDAAAAwBLAGwMAAADAEwAbQwAAAIAIADqDAAAAwA4AG4MAAACACMAEAAICQwWmRoA1AEIaAwAAAMAPQBpDAAAAwBDAGsMAAADAEEAagwAAAMASwBsDAAAAwBMAG0MAAACACAA6gwAAAMAOABuDAAAAgAjAAEuAAUUCAkhAAoAFRkA.Gorberfn:BAAALgAECgMJAwABLgAFFAgJIQAKABUZAA==.',
Gr='Grimorn:BAACLgAFFH8hAAIJAAgJfiBMAQDNAghoDAAABgBjAGkMAAAGAGMAawwAAAUAWwBqDAAABABaAGwMAAADAGEAbQwAAAEAIQDqDAAABwBfAG4MAAABAEEACQAICX4gTAEAzQIIaAwAAAYAYwBpDAAABgBjAGsMAAAFAFsAagwAAAQAWgBsDAAAAwBhAG0MAAABACEA6gwAAAcAXwBuDAAAAQBBAC4ABAp/KQACCQAJCb8hwAMAmQMACQAJCb8hwAMAmQMAAAA=.Grogvald:BAABLgAECn8cAAILAAgJOSLzBwDcAghoDAAABABXAGkMAAAFAGAAawwAAAUAXgBqDAAABABUAGwMAAACAFMAbQwAAAIAVQDqDAAABQBaAG4MAAABAE0ACwAICTki8wcA3AIIaAwAAAQAVwBpDAAABQBgAGsMAAAFAF4AagwAAAQAVABsDAAAAgBTAG0MAAACAFUA6gwAAAUAWgBuDAAAAQBNAAAA.',
['Gø']='Gøober:BAACLgAFFH8hAAQKAAgJFRlgAwD7AQhoDAAABgBdAGkMAAAGAFsAawwAAAUAUgBqDAAABAA4AGwMAAADAEUAbQwAAAEABgDqDAAABwBBAG4MAAABACgAEQAGCeEbnAMADwIGaAwAAAQAVABpDAAAAwBGAGsMAAADAEIAagwAAAIAOABsDAAAAwBFAOoMAAADAEEACgAHCVoYYAMA+wEHaAwAAAEAXQBpDAAAAgBbAGsMAAACAFIAagwAAAIALgBtDAAAAQAGAOoMAAAEADsAbgwAAAEAKAACAAIJOyHlGQC9AAJoDAAAAQBUAGkMAAABAFUALgAECn9CAAQRAAkJQiaDAwBtAwARAAkJFCGDAwBtAwACAAkJ5SA2AwDrAgAKAAcJqiSJEwCBAgAAAA==.',
Ha='Hadrick:BAAALgADCgYJBgAAAA==.',
He='Herax:BAABLgAECn8fAAIOAAgJ4xopFQAGAghoDAAABQBYAGkMAAAEAEUAawwAAAUAQgBqDAAABAA/AGwMAAADAFgAbQwAAAIAIgDqDAAABgBfAG4MAAACACcADgAICeMaKRUABgIIaAwAAAUAWABpDAAABABFAGsMAAAFAEIAagwAAAQAPwBsDAAAAwBYAG0MAAACACIA6gwAAAYAXwBuDAAAAgAnAAAA.',
Hi='Hidrógeno:BAACLgAFFH8FAAISAAMJLgzKSwDeAANoDAAAAgA1AGkMAAABABMA6gwAAAIAFAASAAMJLgzKSwDeAANoDAAAAgA1AGkMAAABABMA6gwAAAIAFAAuAAQKfxcAAhIACAkrHssxAFsCABIACAkrHssxAFsCAAAA.Hinigy:BAAALgAECgUJBQABLgAECggJHAATABMUAA==.',
Ho='Hoofartted:BAABLgAECn85AAIPAAgJzSObAgDBAghoDAAACgBfAGkMAAAJAFcAawwAAAkAYQBqDAAABwBhAGwMAAAGAFoAbQwAAAQAUgDqDAAACABfAG4MAAAEAFwADwAICc0jmwIAwQIIaAwAAAoAXwBpDAAACQBXAGsMAAAJAGEAagwAAAcAYQBsDAAABgBaAG0MAAAEAFIA6gwAAAgAXwBuDAAABABcAAAA.Horchata:BAAALgAECgMJCAAAAA==.Horndawg:BAAALgADCgkJHAAAAA==.',
Il='Illidara:BAAALgAECgMJAwABLgAFFAIJBAAUAAAAAA==.',
Is='Istarìa:BAAALgADCgkJGAAAAA==.',
Jo='Jollyrancher:BAAALgADCgYJBgAAAA==.',
Ju='Judgejobrown:BAABLgAECn8fAAIVAAgJgBZrRgDhAQhoDAAABQA8AGkMAAAFAEgAawwAAAQAQQBqDAAABABUAGwMAAAEADcAbQwAAAEAEADqDAAABQBIAG4MAAADAD0AFQAICYAWa0YA4QEIaAwAAAUAPABpDAAABQBIAGsMAAAEAEEAagwAAAQAVABsDAAABAA3AG0MAAABABAA6gwAAAUASABuDAAAAwA9AAAA.',
Kh='Khajiit:BAABLgAECn8YAAIWAAcJ4x3THgCYAQdoDAAABQBQAGkMAAADAFAAawwAAAQAQABqDAAAAwBXAGwMAAABAEYA6gwAAAUAUABuDAAAAwBSABYABwnjHdMeAJgBB2gMAAAFAFAAaQwAAAMAUABrDAAABABAAGoMAAADAFcAbAwAAAEARgDqDAAABQBQAG4MAAADAFIAAAA=.',
Ki='Kijana:BAABLgAFFH8IAAIKAAQJ6iTsCACkAQRoDAAAAgBiAGkMAAACAF8AawwAAAEAVgDqDAAAAwBhAAoABAnqJOwIAKQBBGgMAAACAGIAaQwAAAIAXwBrDAAAAQBWAOoMAAADAGEAAS4ABRQFCREACgB6JQA=.Kindraa:BAAALgADCgkJGQAAAA==.',
La='Lardpile:BAAALgADCgYJBgAAAA==.Lazaria:BAAALgAECgcJDQAAAA==.',
Le='Leveltwo:BAABLgAECn8zAAICAAkJyxkiCAB6AgloDAAABwBMAGkMAAAHAEQAawwAAAcANABqDAAABwBKAGwMAAAFAEUAbQwAAAQAUQDqDAAACABBAG4MAAAFAE8AbwwAAAEAIQACAAkJyxkiCAB6AgloDAAABwBMAGkMAAAHAEQAawwAAAcANABqDAAABwBKAGwMAAAFAEUAbQwAAAQAUQDqDAAACABBAG4MAAAFAE8AbwwAAAEAIQAAAA==.',
Li='Litguine:BAAALgAECgQJBgAAAA==.Littlestar:BAABLgAECn8pAAIGAAgJShFcGgDBAQhoDAAABgA7AGkMAAAGADgAawwAAAYAPwBqDAAABQA1AGwMAAAGAC4AbQwAAAIAEADqDAAACAAoAG4MAAACABIABgAICUoRXBoAwQEIaAwAAAYAOwBpDAAABgA4AGsMAAAGAD8AagwAAAUANQBsDAAABgAuAG0MAAACABAA6gwAAAgAKABuDAAAAgASAAAA.',
Lo='Lockdnloadd:BAAALgADCgUJCAAAAA==.',
Lu='Lucyfurr:BAAALgAECgUJBgABLgAECggJKwAXACUiAA==.Lunea:BAAALgAECgYJCgAAAA==.',
Ly='Lyraa:BAAALgADCgYJEAAAAA==.',
Ma='Marvel:BAAALgADCgkJEwAAAA==.Mattystaff:BAAALgADCgUJBQAAAA==.',
Me='Melanreu:BAAALgAECgEJAQAAAA==.Melvang:BAAALgAECgIJAgAAAA==.',
My='Myrddraal:BAAALgADCgcJCgAAAA==.Mythicc:BAAALgAECgYJBwAAAA==.',
Na='Naenae:BAAALgAECgEJAQAAAA==.Nastybob:BAABLgAECn8qAAIJAAkJXyQ5BQA3AwloDAAABQBjAGkMAAAFAGEAawwAAAUAXwBqDAAABQBTAGwMAAAFAFkAbQwAAAUAWADqDAAABQBbAG4MAAAEAFcAbwwAAAMAYAAJAAkJXyQ5BQA3AwloDAAABQBjAGkMAAAFAGEAawwAAAUAXwBqDAAABQBTAGwMAAAFAFkAbQwAAAUAWADqDAAABQBbAG4MAAAEAFcAbwwAAAMAYAAAAA==.',
Ni='Nicobulus:BAABLgAECn8XAAIOAAgJigq/OAAXAQhoDAAABAAoAGkMAAAEABMAawwAAAMAHABqDAAAAwASAGwMAAACABgAbQwAAAEAIQDqDAAABAAfAG4MAAACAAsADgAICYoKvzgAFwEIaAwAAAQAKABpDAAABAATAGsMAAADABwAagwAAAMAEgBsDAAAAgAYAG0MAAABACEA6gwAAAQAHwBuDAAAAgALAAAA.Nightspell:BAAALgAECgIJAgAAAA==.',
No='Nor:BAABLgAECn8XAAMLAAcJ6x3DHAAvAgdoDAAABABQAGkMAAAEAFQAawwAAAQAVgBqDAAAAwBMAGwMAAADAFsAbQwAAAEAIwDqDAAABABSAAsABgmZIMMcAC8CBmgMAAADAFAAaQwAAAMAVABrDAAAAwBWAGoMAAACAEwAbAwAAAIAWwDqDAAABABSABIABgmOFRuBAEIBBmgMAAABAD4AaQwAAAEAPwBrDAAAAQBOAGoMAAABADMAbAwAAAEAHwBtDAAAAQAoAAAA.',
['Nä']='Näota:BAAALgAECgEJAQAAAA==.',
Pa='Papanoellego:BAACLgAFFH8hAAIVAAgJYBcsBACDAghoDAAABgBfAGkMAAAGAGMAawwAAAUAVQBqDAAABABQAGwMAAADADEAbQwAAAEABQDqDAAABwBQAG4MAAABAAMAFQAICWAXLAQAgwIIaAwAAAYAXwBpDAAABgBjAGsMAAAFAFUAagwAAAQAUABsDAAAAwAxAG0MAAABAAUA6gwAAAcAUABuDAAAAQADAC4ABAp/KQACFQAJCQEkOQMAywMAFQAJCQEkOQMAywMAAAA=.',
Ph='Phcicoknight:BAAALgADCgYJBgAAAA==.Pheal:BAABLgAECn8fAAIJAAgJsBPOTACzAQhoDAAABQA7AGkMAAAEADkAawwAAAUALABqDAAABAAvAGwMAAADAC8AbQwAAAIAJgDqDAAABgBIAG4MAAACACAACQAICbATzkwAswEIaAwAAAUAOwBpDAAABAA5AGsMAAAFACwAagwAAAQALwBsDAAAAwAvAG0MAAACACYA6gwAAAYASABuDAAAAgAgAAAA.Phiend:BAAALgAECgQJDQAAAA==.Phlak:BAAALgAECgYJCgAAAA==.',
Pl='Pluvl:BAABLgAECn8YAAIMAAgJLAKXLgDtAAhoDAAAAwADAGkMAAADAAUAawwAAAMABABqDAAAAwACAGwMAAAEAAQAbQwAAAIACADqDAAABQAHAG4MAAABAAQADAAICSwCly4A7QAIaAwAAAMAAwBpDAAAAwAFAGsMAAADAAQAagwAAAMAAgBsDAAABAAEAG0MAAACAAgA6gwAAAUABwBuDAAAAQAEAAAA.',
Qu='Quimby:BAAALgAECgYJBgAAAA==.',
Ra='Raign:BAAALgADCgkJGwAAAA==.',
Re='Reyla:BAAALgADCgIJAgABLgAFFAcJHQAMADkZAA==.',
Rh='Rhyze:BAAALgAECgcJDgAAAA==.',
Ri='Rivent:BAAALgAECgYJCAAAAA==.Rivia:BAABLgAECn8aAAISAAgJRBv2QQAfAghoDAAAAwBHAGkMAAAFAE0AawwAAAMALABqDAAAAwBBAGwMAAACAD4AbQwAAAIANwDqDAAABQBgAG4MAAADAFAAEgAICUQb9kEAHwIIaAwAAAMARwBpDAAABQBNAGsMAAADACwAagwAAAMAQQBsDAAAAgA+AG0MAAACADcA6gwAAAUAYABuDAAAAwBQAAAA.',
Ro='Royalmace:BAAALgAECgQJBAAAAA==.',
Sa='Safaridan:BAABLgAECn8eAAQLAAkJFBpWGQBIAgloDAAABQA5AGkMAAAEAEEAawwAAAQAPgBqDAAABABHAGwMAAAEAFMAbQwAAAEALQDqDAAABABYAG4MAAADAD8AbwwAAAEAPwALAAkJFBpWGQBIAgloDAAABAA5AGkMAAADAEEAawwAAAMAPgBqDAAAAgBHAGwMAAADAFMAbQwAAAEALQDqDAAAAwBYAG4MAAACAD8AbwwAAAEAPwAYAAUJXgy1KACZAAVoDAAAAQAbAGkMAAABACQAawwAAAEANgBqDAAAAgAuAGwMAAABAAgAEgACCXoHBlcBMQAC6gwAAAEADwBuDAAAAQAWAAAA.Sapphirre:BAAALgADCgcJEQAAAA==.Savsham:BAAALgADCgEJAQAAAA==.',
Sc='Scamp:BAAALgAECgEJAQAAAA==.Scrump:BAAALgAECgQJBQAAAA==.',
Sh='Shtick:BAAALgADCggJDQAAAA==.',
Si='Sienen:BAAALgAECgQJBAAAAA==.',
Sj='Sjk:BAABLgAECn8WAAIFAAgJXyCjBgD8AghoDAAAAwBYAGkMAAAEAFcAawwAAAQAWQBqDAAAAwBTAGwMAAADAEgAbQwAAAIAUADqDAAAAgBcAG4MAAABAEQABQAICV8gowYA/AIIaAwAAAMAWABpDAAABABXAGsMAAAEAFkAagwAAAMAUwBsDAAAAwBIAG0MAAACAFAA6gwAAAIAXABuDAAAAQBEAAAA.',
Sl='Slabia:BAABLgAECn8VAAISAAcJsCC4MQBcAgdoDAAABQBjAGkMAAAFAFgAawwAAAQAWABqDAAAAgBSAGwMAAACAD4A6gwAAAIAPgBuDAAAAQBjABIABwmwILgxAFwCB2gMAAAFAGMAaQwAAAUAWABrDAAABABYAGoMAAACAFIAbAwAAAIAPgDqDAAAAgA+AG4MAAABAGMAAAA=.Slade:BAAALgAECgEJAQAAAA==.Slashly:BAAALgAECgEJBAAAAA==.Sloan:BAAALgAECgYJEAAAAA==.',
Sp='Spektrum:BAAALgADCgEJAQAAAA==.',
St='Stacey:BAAALgAECgQJBAABLgAFFAkJLQAIACceAA==.Stepmom:BAAALgAFFAIJAgAAAA==.Stepsis:BAAALgAFFAIJBAAAAA==.Stiick:BAAALgADCgUJBQAAAA==.',
Sv='Svinehundt:BAABLgAECn8cAAITAAgJExTvQwCuAQhoDAAABgA1AGkMAAAFAD4AawwAAAUANwBqDAAAAgAnAGwMAAACADAAbQwAAAEALgDqDAAABgBNAG4MAAABABAAEwAICRMU70MArgEIaAwAAAYANQBpDAAABQA+AGsMAAAFADcAagwAAAIAJwBsDAAAAgAwAG0MAAABAC4A6gwAAAYATQBuDAAAAQAQAAAA.',
Ta='Tabtok:BAAALgADCgcJDgAAAA==.Tanalin:BAAALgADCgMJAwABLgAECggJHAATABMUAA==.Tanglebones:BAABLgAECn8UAAIZAAYJwgsJDwAIAQZoDAAABAAxAGkMAAAEAB4AawwAAAQAIwBqDAAAAgAdAGwMAAACAA4A6gwAAAQAFAAZAAYJwgsJDwAIAQZoDAAABAAxAGkMAAAEAB4AawwAAAQAIwBqDAAAAgAdAGwMAAACAA4A6gwAAAQAFAAAAA==.Tasty:BAAALgAECgEJAQAAAA==.Taukra:BAAALgADCgYJBgAAAA==.',
To='Tore:BAAALgAECgYJDAAAAA==.',
Tr='Trazie:BAAALgAECgYJCQAAAA==.Trenn:BAAALgADCgkJCQABLgAECggJEgAUAAAAAA==.',
Un='Unsocial:BAAALgADCgkJGAAAAA==.',
Ve='Vecna:BAAALgAECgEJAQABLgAECgYJCAAUAAAAAA==.Vermi:BAAALgAECgMJBQAAAA==.',
Wa='Warcloud:BAABLgAECn8XAAILAAgJ+ANEQQAHAQhoDAAAAwAWAGkMAAADAAgAawwAAAMACgBqDAAAAwADAGwMAAAEABIAbQwAAAIABADqDAAABAAIAG4MAAABAAQACwAICfgDREEABwEIaAwAAAMAFgBpDAAAAwAIAGsMAAADAAoAagwAAAMAAwBsDAAABAASAG0MAAACAAQA6gwAAAQACABuDAAAAQAEAAAA.Wartortle:BAABLgAECn8tAAMaAAcJSBwHEAC0AQdoDAAACgBKAGkMAAAIAFUAawwAAAgAUQBqDAAACAA0AGwMAAAIAEsAbQwAAAIAKADqDAAAAQBNABoABwlIHAcQALQBB2gMAAAJAEoAaQwAAAgAVQBrDAAACABRAGoMAAAIADQAbAwAAAgASwBtDAAAAgAoAOoMAAABAE0AGwABCZ0JEl0ALgABaAwAAAEAGAAAAA==.',
Wh='Whack:BAAALgAECgYJBgAAAA==.Whiskeytf:BAAALgAECgYJDAAAAA==.',
Ws='Wsedfgghj:BAAALgAECgcJDAAAAA==.',
Wu='Wu:BAAALgAECgIJAgAAAA==.Wulfgaz:BAAALgAECgYJCgAAAA==.',
Wy='Wyldhart:BAAALgAECgEJAQAAAA==.Wylf:BAAALgADCgcJBwABLgAECgYJCgAUAAAAAA==.',
Xt='Xtheleon:BAAALgADCgYJBwAAAA==.',
Ze='Zenn:BAAALgAECggJEgAAAA==.Zeroomega:BAAALgADCgMJAwAAAA==.Zerø:BAAALgADCgYJBgAAAA==.',
Zi='Zinthous:BAAALgAECgEJAQAAAA==.',
['Äl']='Ältäir:BAABLgAECn8hAAIXAAgJhxgRKADiAQhoDAAABgBTAGkMAAAFAEcAawwAAAUARQBqDAAABAAxAGwMAAADAEEAbQwAAAIANADqDAAABgBGAG4MAAACACcAFwAICYcYESgA4gEIaAwAAAYAUwBpDAAABQBHAGsMAAAFAEUAagwAAAQAMQBsDAAAAwBBAG0MAAACADQA6gwAAAYARgBuDAAAAgAnAAAA.',
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
