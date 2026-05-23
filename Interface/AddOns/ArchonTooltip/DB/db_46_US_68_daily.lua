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

local lookup = {'Warrior-Fury','Hunter-Survival','Monk-Windwalker','Monk-Brewmaster','DemonHunter-Havoc','Priest-Discipline','Priest-Holy','Priest-Shadow','DeathKnight-Unholy','Hunter-BeastMastery','Paladin-Holy','Rogue-Subtlety','DeathKnight-Blood','Shaman-Elemental','Shaman-Enhancement','Evoker-Augmentation','Hunter-Marksmanship','Paladin-Retribution','Warlock-Demonology','Unknown-Unknown','Mage-Frost','Druid-Balance','Shaman-Restoration','DeathKnight-Frost','Paladin-Protection','DemonHunter-Devourer','Rogue-Assassination','Warrior-Protection','Warrior-Arms',}
local provider = {region='US',realm='Dethecus',name='US',type='daily',zone=46,date='2026-05-22',data={Aa='Aashley:BAAALgAECgcJBwAAAA==.',
Al='Alistis:BAAALgADCgEJAQAAAA==.',
Am='Amutio:BAAALgAECgMJCwAAAA==.',
An='Andromedus:BAAALgAFFAEJAgABLgAFFAcJHgABADAcAA==.',
Ar='Arasis:BAABLgAECn81AAICAAkJeSUeAQBIAwloDAAABwBgAGkMAAAIAGIAawwAAAgAYgBqDAAABgBdAGwMAAAFAGEAbQwAAAMAWwDqDAAACABgAG4MAAAHAF8AbwwAAAEAWgACAAkJeSUeAQBIAwloDAAABwBgAGkMAAAIAGIAawwAAAgAYgBqDAAABgBdAGwMAAAFAGEAbQwAAAMAWwDqDAAACABgAG4MAAAHAF8AbwwAAAEAWgAAAA==.Arìel:BAAALgADCgkJDwAAAA==.',
As='Ashhleyy:BAAALgAECgcJBgAAAA==.Ashhlleyy:BAAALgAECgcJAQAAAA==.Ashleyy:BAAALgAECgcJBgAAAA==.',
Ba='Balancing:BAAALgAFFAIJBAAAAA==.Bamag:BAABLgAECn8eAAIBAAgJgSLxBgA5AwhoDAAABQBfAGkMAAAFAGAAawwAAAUAYgBqDAAABABeAGwMAAAEAFwAbQwAAAIAXADqDAAABABcAG4MAAABADEAAQAICYEi8QYAOQMIaAwAAAUAXwBpDAAABQBgAGsMAAAFAGIAagwAAAQAXgBsDAAABABcAG0MAAACAFwA6gwAAAQAXABuDAAAAQAxAAAA.',
Bi='Bigmak:BAAALgAECgEJAQAAAA==.',
Br='Braellyn:BAAALgAECgUJCQAAAA==.',
Bu='Burnyou:BAAALgADCggJEwAAAA==.',
Ce='Cenobité:BAABLgAECn8rAAMDAAgJqCTXBgC5AghoDAAABwBgAGkMAAAIAGEAawwAAAYAXwBqDAAABQBYAGwMAAAFAGEAbQwAAAMAYADqDAAABgBeAG4MAAADAE4AAwAICagk1wYAuQIIaAwAAAcAYABpDAAACABhAGsMAAAGAF8AagwAAAQAWABsDAAABABhAG0MAAADAGAA6gwAAAYAXgBuDAAAAwBOAAQAAgk/G+9wAH8AAmoMAAABAC0AbAwAAAEARQAAAA==.Ceridemon:BAABLgAECn8iAAIFAAkJ4g/YFQCjAQloDAAABQAlAGkMAAAFAEIAawwAAAUAIgBqDAAABAAjAGwMAAAEADoAbQwAAAMAIADqDAAABQAzAG4MAAACABEAbwwAAAEAGgAFAAkJ4g/YFQCjAQloDAAABQAlAGkMAAAFAEIAawwAAAUAIgBqDAAABAAjAGwMAAAEADoAbQwAAAMAIADqDAAABQAzAG4MAAACABEAbwwAAAEAGgAAAA==.',
Ch='Chingee:BAABLgAECn9MAAMGAAkJxxrtCgCTAgloDAAACgBcAGkMAAAKAEoAawwAAAoATQBqDAAACgA4AGwMAAAKAE4AbQwAAAcAMwDqDAAACwBSAG4MAAAGAFAAbwwAAAIAFgAGAAkJ7BntCgCTAgloDAAACABQAGkMAAAIAEoAawwAAAgATQBqDAAACAA4AGwMAAAIAE4AbQwAAAYAKwDqDAAACQBSAG4MAAAFAFAAbwwAAAIAFgAHAAgJiw5AJgC6AQhoDAAAAgBcAGkMAAACAD8AawwAAAIAIwBqDAAAAgAMAGwMAAACAAcAbQwAAAEAMwDqDAAAAgAOAG4MAAABABMAAAA=.',
Co='Consarios:BAAALgAFFAEJAQAAAA==.',
Cr='Croakadin:BAAALgADCgcJEAAAAA==.Crushers:BAAALgADCggJCAAAAA==.',
Cy='Cyraanden:BAACLgAFFH8NAAIDAAMJgQ0EGwDHAANoDAAABAAlAGkMAAAFACEA6gwAAAQAIAADAAMJgQ0EGwDHAANoDAAABAAlAGkMAAAFACEA6gwAAAQAIAAuAAQKfzUAAwMACQm7GlsNAEQCAAMACQlOGlsNAEQCAAQABAkeFKxEAMkAAAAA.Cyvus:BAABLgAECn8kAAMHAAgJawVZQwArAQhoDAAABgAIAGkMAAAGAAUAawwAAAUAEwBqDAAABQAZAGwMAAAFABAAbQwAAAIAEQDqDAAABgAPAG4MAAABAAAABwAICWsFWUMAKwEIaAwAAAIACABpDAAAAgAFAGsMAAADABMAagwAAAIAGQBsDAAAAgAQAG0MAAACABEA6gwAAAMADwBuDAAAAQAAAAgABgn7CY49AO0ABmgMAAAEACYAaQwAAAQAFQBrDAAAAgAcAGoMAAADABIAbAwAAAMAFADqDAAAAwASAAAA.',
Da='Dab:BAABLgAECn9BAAIJAAkJhSVoAgBpAwloDAAACQBgAGkMAAAJAGMAawwAAAkAYQBqDAAABwBhAGwMAAAIAGAAbQwAAAYAYwDqDAAACgBfAG4MAAAFAFQAbwwAAAIAYwAJAAkJhSVoAgBpAwloDAAACQBgAGkMAAAJAGMAawwAAAkAYQBqDAAABwBhAGwMAAAIAGAAbQwAAAYAYwDqDAAACgBfAG4MAAAFAFQAbwwAAAIAYwAAAA==.Daedara:BAAALgAECgMJBAAAAA==.Daggz:BAABLgAECn8yAAMKAAkJER8LEgCnAgloDAAABwBXAGkMAAAHAFEAawwAAAcAXQBqDAAABgBVAGwMAAAFAE0AbQwAAAUAQADqDAAABwBOAG4MAAAEAFcAbwwAAAIAQgAKAAgJtx8LEgCnAghoDAAABQBXAGkMAAAFAFEAawwAAAUAXQBqDAAABAA/AGwMAAADAE0AbQwAAAMAPgDqDAAABQBOAG4MAAADAFcAAgAJCfUYuAgAdwIJaAwAAAIAVgBpDAAAAgBQAGsMAAACAEwAagwAAAIAVQBsDAAAAgAtAG0MAAACAEAA6gwAAAIAPABuDAAAAQAfAG8MAAACAEIAAAA=.Dansgrundle:BAAALgAECgMJAwABLgAECgkJHgALABQaAA==.Darkhorse:BAABLgAECn8iAAIMAAgJIB4VCgBcAghoDAAABwBTAGkMAAAHAF0AawwAAAQAVgBqDAAABABeAGwMAAAEAFcAbQwAAAEADADqDAAABQBRAG4MAAACAF4ADAAICSAeFQoAXAIIaAwAAAcAUwBpDAAABwBdAGsMAAAEAFYAagwAAAQAXgBsDAAABABXAG0MAAABAAwA6gwAAAUAUQBuDAAAAgBeAAAA.Darkmer:BAABLgAECn8kAAIJAAYJ3AWivwDSAAZoDAAACAAPAGkMAAAIABMAawwAAAcADQBqDAAABAAQAGwMAAADAA4A6gwAAAYACwAJAAYJ3AWivwDSAAZoDAAACAAPAGkMAAAIABMAawwAAAcADQBqDAAABAAQAGwMAAADAA4A6gwAAAYACwAAAA==.',
De='Deathsnight:BAAALgAECgUJBwAAAA==.Derpy:BAAALgADCgYJCQAAAA==.Deynestta:BAAALgAECgIJBAAAAA==.',
Di='Dixiereaper:BAABLgAECn8WAAINAAkJahBrGgB+AQloDAAAAwBMAGkMAAADADwAawwAAAMALABqDAAAAgAvAGwMAAADACUAbQwAAAIAHgDqDAAAAwAcAG4MAAACAC0AbwwAAAEADQANAAkJahBrGgB+AQloDAAAAwBMAGkMAAADADwAawwAAAMALABqDAAAAgAvAGwMAAADACUAbQwAAAIAHgDqDAAAAwAcAG4MAAACAC0AbwwAAAEADQAAAA==.',
Dr='Droopin:BAAALgADCgYJBwAAAA==.',
Ds='Ds:BAAALgAECgYJCgAAAA==.Dsntdrptotem:BAABLgAECn8rAAMOAAkJihQcHQDIAQloDAAABgA8AGkMAAAFADUAawwAAAYANQBqDAAABQAuAGwMAAAGADcAbQwAAAQAGgDqDAAABQA3AG4MAAADAFgAbwwAAAMAGwAOAAkJmxEcHQDIAQloDAAAAgAnAGkMAAABADEAawwAAAIAHwBqDAAAAgAuAGwMAAADADcAbQwAAAMAGgDqDAAAAgAqAG4MAAADAFgAbwwAAAMAGwAPAAcJ2BGDEwCBAQdoDAAABAA8AGkMAAAEADUAawwAAAQANQBqDAAAAwAWAGwMAAADADAAbQwAAAEAAgDqDAAAAwA3AAAA.',
Dt='Dtothep:BAAALgAECgEJAQAAAA==.',
El='Elfangar:BAAALgADCgcJBwAAAA==.',
Ep='Epicamerican:BAAALgAECgEJAQAAAA==.',
Ff='Ffecanti:BAAALgAECgYJCQAAAA==.',
Fl='Floury:BAAALgAECgMJAwAAAA==.',
Ga='Gailen:BAAALgADCgkJDgAAAA==.',
Gi='Gideonn:BAAALgADCgMJAwAAAA==.',
Go='Gorber:BAABLgAECn8WAAIQAAgJDRYiHADRAQhoDAAAAwA9AGkMAAADAEMAawwAAAMAQQBqDAAAAwBLAGwMAAADAEwAbQwAAAIAIADqDAAAAwA4AG4MAAACACMAEAAICQ0WIhwA0QEIaAwAAAMAPQBpDAAAAwBDAGsMAAADAEEAagwAAAMASwBsDAAAAwBMAG0MAAACACAA6gwAAAMAOABuDAAAAgAjAAEuAAUUCAkiAAoAVxoA.Gorberfn:BAAALgAECgMJAwABLgAFFAgJIgAKAFcaAA==.',
Gr='Grimorn:BAACLgAFFH8iAAIJAAgJfyDKAQDCAghoDAAABgBjAGkMAAAGAGMAawwAAAUAWwBqDAAABABaAGwMAAADAGEAbQwAAAEAIQDqDAAACABfAG4MAAABAEEACQAICX8gygEAwgIIaAwAAAYAYwBpDAAABgBjAGsMAAAFAFsAagwAAAQAWgBsDAAAAwBhAG0MAAABACEA6gwAAAgAXwBuDAAAAQBBAC4ABAp/KQACCQAJCcAhwAMAmQMACQAJCcAhwAMAmQMAAAA=.Grogvald:BAABLgAECn8cAAILAAgJOSK8CADXAghoDAAABABXAGkMAAAFAGAAawwAAAUAXgBqDAAABABUAGwMAAACAFMAbQwAAAIAVQDqDAAABQBaAG4MAAABAE0ACwAICTkivAgA1wIIaAwAAAQAVwBpDAAABQBgAGsMAAAFAF4AagwAAAQAVABsDAAAAgBTAG0MAAACAFUA6gwAAAUAWgBuDAAAAQBNAAAA.',
['Gø']='Gøober:BAACLgAFFH8iAAQKAAgJVxpjAwAKAghoDAAABgBdAGkMAAAGAFsAawwAAAUAUgBqDAAABAA4AGwMAAADAEUAbQwAAAEABgDqDAAACABYAG4MAAABACgAEQAGCeEbnAMADwIGaAwAAAQAVABpDAAAAwBGAGsMAAADAEIAagwAAAIAOABsDAAAAwBFAOoMAAADAEEACgAHCTkaYwMACgIHaAwAAAEAXQBpDAAAAgBbAGsMAAACAFIAagwAAAIALgBtDAAAAQAGAOoMAAAFAFgAbgwAAAEAKAACAAIJOyGJGwC4AAJoDAAAAQBUAGkMAAABAFUALgAECn9CAAQRAAkJQiaDAwBtAwARAAkJFCGDAwBtAwACAAkJ5SCZAwDjAgAKAAcJqiQOFQB9AgAAAA==.',
Ha='Hadrick:BAAALgADCgYJBgAAAA==.',
He='Herax:BAABLgAECn8hAAIOAAgJ4xqfFgABAghoDAAABQBYAGkMAAAEAEUAawwAAAUAQgBqDAAABAA/AGwMAAADAFgAbQwAAAIAIgDqDAAABwBfAG4MAAADACcADgAICeManxYAAQIIaAwAAAUAVwBpDAAABABFAGsMAAAFAEIAagwAAAQAPwBsDAAAAwBYAG0MAAACACIA6gwAAAcAXwBuDAAAAwAnAAAA.',
Hi='Hidrógeno:BAACLgAFFH8FAAISAAMJLgz1UADbAANoDAAAAgA1AGkMAAABABMA6gwAAAIAFAASAAMJLgz1UADbAANoDAAAAgA1AGkMAAABABMA6gwAAAIAFAAuAAQKfxcAAhIACAkrHssxAFsCABIACAkrHssxAFsCAAAA.Hinigy:BAAALgAECgUJBQABLgAECggJHAATABQUAA==.',
Ho='Hoofartted:BAACLgAFFH8FAAIPAAMJUhiFBwD+AANoDAAAAgBQAGkMAAABAC4A6gwAAAIAPAAPAAMJUhiFBwD+AANoDAAAAgBQAGkMAAABAC4A6gwAAAIAPAAuAAQKfzkAAg8ACAnOI/ICALoCAA8ACAnOI/ICALoCAAAA.Horchata:BAAALgAECgMJCAAAAA==.Horndawg:BAAALgADCgkJHAAAAA==.',
Il='Illidara:BAAALgAECgMJAwABLgAFFAIJBAAUAAAAAA==.',
Is='Istarìa:BAAALgADCgkJGgAAAA==.',
Jo='Jollyrancher:BAAALgADCgYJBgAAAA==.',
Ju='Judgejobrown:BAABLgAECn8gAAIVAAkJLhbeMgAtAgloDAAABQA8AGkMAAAFAEgAawwAAAQAQQBqDAAABABUAGwMAAAEADcAbQwAAAEAEADqDAAABQBIAG4MAAADAD0AbwwAAAEAMwAVAAkJLhbeMgAtAgloDAAABQA8AGkMAAAFAEgAawwAAAQAQQBqDAAABABUAGwMAAAEADcAbQwAAAEAEADqDAAABQBIAG4MAAADAD0AbwwAAAEAMwAAAA==.',
Ka='Katarina:BAAALgAECgEJAQAAAA==.',
Kh='Khajiit:BAABLgAECn8YAAIWAAcJ4x15IACUAQdoDAAABQBQAGkMAAADAFAAawwAAAQAQABqDAAAAwBXAGwMAAABAEYA6gwAAAUAUABuDAAAAwBSABYABwnjHXkgAJQBB2gMAAAFAFAAaQwAAAMAUABrDAAABABAAGoMAAADAFcAbAwAAAEARgDqDAAABQBQAG4MAAADAFIAAAA=.',
Ki='Kijana:BAABLgAFFH8IAAIKAAQJ6iSjCgCfAQRoDAAAAgBiAGkMAAACAF8AawwAAAEAVgDqDAAAAwBhAAoABAnqJKMKAJ8BBGgMAAACAGIAaQwAAAIAXwBrDAAAAQBWAOoMAAADAGEAAS4ABRQFCREACgB6JQA=.Kindraa:BAAALgADCgkJGQAAAA==.',
La='Lardpile:BAAALgADCgYJBgAAAA==.Lazaria:BAAALgAECgcJDQAAAA==.',
Le='Leveltwo:BAABLgAECn80AAICAAkJzBnyCABzAgloDAAABwBMAGkMAAAHAEQAawwAAAcANABqDAAABwBKAGwMAAAFAEUAbQwAAAQAUgDqDAAACABBAG4MAAAFAE8AbwwAAAIAIQACAAkJzBnyCABzAgloDAAABwBMAGkMAAAHAEQAawwAAAcANABqDAAABwBKAGwMAAAFAEUAbQwAAAQAUgDqDAAACABBAG4MAAAFAE8AbwwAAAIAIQAAAA==.',
Li='Litguine:BAAALgAECgQJBgAAAA==.Littlestar:BAABLgAECn8xAAIGAAgJnRJJGgDNAQhoDAAABwA7AGkMAAAHADgAawwAAAcAPwBqDAAABgA1AGwMAAAHAC4AbQwAAAMAGADqDAAACQAoAG4MAAADACYABgAICZ0SSRoAzQEIaAwAAAcAOwBpDAAABwA4AGsMAAAHAD8AagwAAAYANQBsDAAABwAuAG0MAAADABgA6gwAAAkAKABuDAAAAwAmAAAA.',
Lo='Lockdnloadd:BAAALgADCgUJCAAAAA==.',
Lu='Lucyfurr:BAAALgAECgUJBgABLgAECgkJLAAXALQgAA==.Lunea:BAAALgAECgYJCgAAAA==.',
Ly='Lyraa:BAAALgADCgYJEAAAAA==.',
Ma='Marvel:BAAALgADCgkJEwAAAA==.Mattystaff:BAAALgADCgUJBQAAAA==.',
Me='Melanreu:BAAALgAECgEJAQAAAA==.Melvang:BAAALgAECgIJAgAAAA==.',
My='Myrddraal:BAAALgADCgcJCgAAAA==.Mythicc:BAAALgAECgYJBwAAAA==.',
Na='Naenae:BAAALgAECgEJAQAAAA==.Nastybob:BAABLgAECn8zAAIJAAkJtyStBABEAwloDAAABgBjAGkMAAAGAGEAawwAAAYAXwBqDAAABgBTAGwMAAAGAFkAbQwAAAYAXwDqDAAABgBbAG4MAAAFAFcAbwwAAAQAYAAJAAkJtyStBABEAwloDAAABgBjAGkMAAAGAGEAawwAAAYAXwBqDAAABgBTAGwMAAAGAFkAbQwAAAYAXwDqDAAABgBbAG4MAAAFAFcAbwwAAAQAYAAAAA==.',
Ni='Nicobulus:BAABLgAECn8XAAIOAAgJiwoEOwAWAQhoDAAABAAoAGkMAAAEABMAawwAAAMAHABqDAAAAwASAGwMAAACABgAbQwAAAEAIQDqDAAABAAfAG4MAAACAAsADgAICYsKBDsAFgEIaAwAAAQAKABpDAAABAATAGsMAAADABwAagwAAAMAEgBsDAAAAgAYAG0MAAABACEA6gwAAAQAHwBuDAAAAgALAAAA.Nightspell:BAAALgAECgUJBQAAAA==.',
No='Nor:BAABLgAECn8XAAMLAAcJ7B3DHAAvAgdoDAAABABQAGkMAAAEAFQAawwAAAQAVgBqDAAAAwBMAGwMAAADAFsAbQwAAAEAIwDqDAAABABSAAsABgmZIMMcAC8CBmgMAAADAFAAaQwAAAMAVABrDAAAAwBWAGoMAAACAEwAbAwAAAIAWwDqDAAABABSABIABgmOFWKJADkBBmgMAAABAD4AaQwAAAEAPwBrDAAAAQBOAGoMAAABADMAbAwAAAEAHwBtDAAAAQAoAAAA.',
['Nä']='Näota:BAAALgAECgEJAQAAAA==.',
Pa='Papanoellego:BAACLgAFFH8hAAIVAAgJYBeEBQB7AghoDAAABgBfAGkMAAAGAGMAawwAAAUAVQBqDAAABABQAGwMAAADADEAbQwAAAEABQDqDAAABwBQAG4MAAABAAMAFQAICWAXhAUAewIIaAwAAAYAXwBpDAAABgBjAGsMAAAFAFUAagwAAAQAUABsDAAAAwAxAG0MAAABAAUA6gwAAAcAUABuDAAAAQADAC4ABAp/KQACFQAJCQEkOQMAywMAFQAJCQEkOQMAywMAAAA=.',
Ph='Phcicoknight:BAAALgADCgYJBgAAAA==.Pheal:BAABLgAECn8hAAMJAAgJ2hXBRwDHAQhoDAAABQA7AGkMAAAEADkAawwAAAUALABqDAAABAAvAGwMAAADAC8AbQwAAAIAJgDqDAAABwBIAG4MAAADAEcACQAICdoVwUcAxwEIaAwAAAUAOwBpDAAABAA5AGsMAAAFACwAagwAAAQALwBsDAAAAwAvAG0MAAACACYA6gwAAAYASABuDAAAAwBHABgAAQkDEwsoADkAAeoMAAABADAAAAA=.Phiend:BAAALgAECgQJDQAAAA==.Phlak:BAAALgAECgYJDwAAAA==.',
Pl='Pluvl:BAABLgAECn8YAAIMAAgJLAI3MADqAAhoDAAAAwADAGkMAAADAAUAawwAAAMABABqDAAAAwACAGwMAAAEAAQAbQwAAAIACADqDAAABQAHAG4MAAABAAQADAAICSwCNzAA6gAIaAwAAAMAAwBpDAAAAwAFAGsMAAADAAQAagwAAAMAAgBsDAAABAAEAG0MAAACAAgA6gwAAAUABwBuDAAAAQAEAAAA.',
Qu='Quimby:BAAALgAECgYJBgAAAA==.',
Ra='Raign:BAAALgADCgkJGwAAAA==.',
Re='Reyla:BAAALgADCgIJAgABLgAFFAcJHQAMAD4ZAA==.',
Rh='Rhyze:BAAALgAECgcJDgAAAA==.',
Ri='Rivent:BAAALgAECgYJCAAAAA==.Rivia:BAABLgAECn8cAAISAAgJrByxRwDNAQhoDAAABABSAGkMAAAGAFsAawwAAAMALABqDAAAAwBBAGwMAAACAD4AbQwAAAIANwDqDAAABQBgAG4MAAADAFAAEgAICawcsUcAzQEIaAwAAAQAUgBpDAAABgBbAGsMAAADACwAagwAAAMAQQBsDAAAAgA+AG0MAAACADcA6gwAAAUAYABuDAAAAwBQAAAA.',
Ro='Royalmace:BAAALgAECgQJBAAAAA==.',
Sa='Safaridan:BAABLgAECn8eAAQLAAkJFBpWGQBIAgloDAAABQA5AGkMAAAEAEEAawwAAAQAPgBqDAAABABHAGwMAAAEAFMAbQwAAAEALQDqDAAABABYAG4MAAADAD8AbwwAAAEAPwALAAkJFBpWGQBIAgloDAAABAA5AGkMAAADAEEAawwAAAMAPgBqDAAAAgBHAGwMAAADAFMAbQwAAAEALQDqDAAAAwBYAG4MAAACAD8AbwwAAAEAPwAZAAUJXgw8KgCYAAVoDAAAAQAbAGkMAAABACQAawwAAAEANgBqDAAAAgAuAGwMAAABAAgAEgACCXoHG2EBMAAC6gwAAAEADwBuDAAAAQAWAAAA.Sapphirre:BAAALgADCgcJEQAAAA==.Savsham:BAAALgADCgEJAQAAAA==.',
Sc='Scamp:BAAALgAECgEJAQAAAA==.Scrump:BAAALgAECgQJBQAAAA==.',
Sh='Shtick:BAAALgADCggJDQAAAA==.',
Si='Sienen:BAAALgAECgQJBAAAAA==.',
Sj='Sjk:BAABLgAECn8WAAIFAAgJXyCjBgD8AghoDAAAAwBYAGkMAAAEAFcAawwAAAQAWQBqDAAAAwBTAGwMAAADAEgAbQwAAAIAUADqDAAAAgBcAG4MAAABAEQABQAICV8gowYA/AIIaAwAAAMAWABpDAAABABXAGsMAAAEAFkAagwAAAMAUwBsDAAAAwBIAG0MAAACAFAA6gwAAAIAXABuDAAAAQBEAAAA.',
Sl='Slabia:BAABLgAECn8VAAISAAcJsCC4MQBcAgdoDAAABQBjAGkMAAAFAFgAawwAAAQAWABqDAAAAgBSAGwMAAACAD4A6gwAAAIAPgBuDAAAAQBjABIABwmwILgxAFwCB2gMAAAFAGMAaQwAAAUAWABrDAAABABYAGoMAAACAFIAbAwAAAIAPgDqDAAAAgA+AG4MAAABAGMAAAA=.Slade:BAAALgAECgEJAQAAAA==.Slashly:BAAALgAECgEJBAAAAA==.Sloan:BAABLgAECn8UAAIGAAYJOwO1PwDNAAZoDAAABgAMAGkMAAAFAAkAawwAAAQACQBqDAAAAwAJAGwMAAABAAQA6gwAAAEAAwAGAAYJOwO1PwDNAAZoDAAABgAMAGkMAAAFAAkAawwAAAQACQBqDAAAAwAJAGwMAAABAAQA6gwAAAEAAwAAAA==.',
Sp='Spektrum:BAAALgADCgEJAQAAAA==.Spicychicken:BAAALgAFFAEJAQABLgAFFAgJHQAaAGwZAA==.',
St='Stacey:BAAALgAECgQJBAABLgAFFAkJLgAIAJgfAA==.Stepmom:BAAALgAFFAIJAgAAAA==.Stepsis:BAAALgAFFAIJBAAAAA==.Stiick:BAAALgADCgUJBQAAAA==.',
Sv='Svinehundt:BAABLgAECn8cAAITAAgJFBTWRgCtAQhoDAAABgA1AGkMAAAFAD4AawwAAAUANwBqDAAAAgAnAGwMAAACADAAbQwAAAEALgDqDAAABgBNAG4MAAABABAAEwAICRQU1kYArQEIaAwAAAYANQBpDAAABQA+AGsMAAAFADcAagwAAAIAJwBsDAAAAgAwAG0MAAABAC4A6gwAAAYATQBuDAAAAQAQAAAA.',
Ta='Tabtok:BAAALgADCgcJDgAAAA==.Tanalin:BAAALgADCgMJAwABLgAECggJHAATABQUAA==.Tanglebones:BAABLgAECn8UAAIbAAYJwguXDwAIAQZoDAAABAAxAGkMAAAEAB4AawwAAAQAIwBqDAAAAgAdAGwMAAACAA4A6gwAAAQAFAAbAAYJwguXDwAIAQZoDAAABAAxAGkMAAAEAB4AawwAAAQAIwBqDAAAAgAdAGwMAAACAA4A6gwAAAQAFAAAAA==.Tasty:BAAALgAECgEJAQABLgAFFAQJDgAXACEYAA==.Taukra:BAAALgADCgYJBgAAAA==.',
To='Tore:BAAALgAECgYJDAAAAA==.',
Tr='Trazie:BAAALgAECgYJCQAAAA==.Trenn:BAAALgADCgkJCQABLgAECggJEgAUAAAAAA==.',
Un='Unsocial:BAAALgADCgkJGAAAAA==.',
Ve='Vecna:BAAALgAECgEJAQABLgAECgYJCAAUAAAAAA==.Vermi:BAAALgAECgMJBQAAAA==.',
Wa='Warcloud:BAABLgAECn8XAAILAAgJ+AMJQwAHAQhoDAAAAwAWAGkMAAADAAgAawwAAAMACgBqDAAAAwADAGwMAAAEABIAbQwAAAIABADqDAAABAAIAG4MAAABAAQACwAICfgDCUMABwEIaAwAAAMAFgBpDAAAAwAIAGsMAAADAAoAagwAAAMAAwBsDAAABAASAG0MAAACAAQA6gwAAAQACABuDAAAAQAEAAAA.Wartortle:BAABLgAECn8tAAMcAAcJSRz8EACtAQdoDAAACgBKAGkMAAAIAFUAawwAAAgAUQBqDAAACAA0AGwMAAAIAEsAbQwAAAIAKADqDAAAAQBNABwABwlJHPwQAK0BB2gMAAAJAEoAaQwAAAgAVQBrDAAACABRAGoMAAAIADQAbAwAAAgASwBtDAAAAgAoAOoMAAABAE0AHQABCZ0JIWIALAABaAwAAAEAGAAAAA==.',
Wh='Whack:BAAALgAECgYJBgAAAA==.Whiskeytf:BAAALgAECgYJDAAAAA==.',
Ws='Wsedfgghj:BAAALgAECgcJDAAAAA==.',
Wu='Wu:BAAALgAECgIJAgAAAA==.Wulfgaz:BAAALgAECgYJCgAAAA==.',
Wy='Wyldhart:BAAALgAECgEJAQAAAA==.Wylf:BAAALgADCgcJBwABLgAECgYJCgAUAAAAAA==.',
Xt='Xtheleon:BAAALgADCgYJBwAAAA==.',
Ze='Zenn:BAAALgAECggJEgAAAA==.Zeroomega:BAAALgADCgMJAwAAAA==.Zerø:BAAALgADCgYJBgAAAA==.',
Zi='Zinthous:BAAALgAECgEJAQAAAA==.',
['Äl']='Ältäir:BAABLgAECn8jAAIXAAgJhhiMKgDeAQhoDAAABgBTAGkMAAAFAEcAawwAAAUARQBqDAAABAAxAGwMAAADAEEAbQwAAAIANADqDAAABwBGAG4MAAADACcAFwAICYYYjCoA3gEIaAwAAAYAUwBpDAAABQBHAGsMAAAFAEUAagwAAAQAMQBsDAAAAwBBAG0MAAACADQA6gwAAAcARgBuDAAAAwAnAAAA.',
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
