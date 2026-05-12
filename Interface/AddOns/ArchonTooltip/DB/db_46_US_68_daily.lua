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

local lookup = {'Hunter-Survival','Warrior-Fury','Monk-Windwalker','Monk-Brewmaster','DemonHunter-Havoc','Priest-Discipline','Priest-Holy','Priest-Shadow','DeathKnight-Unholy','Hunter-BeastMastery','Paladin-Holy','Rogue-Subtlety','DeathKnight-Blood','Shaman-Elemental','Shaman-Enhancement','Hunter-Marksmanship','Paladin-Retribution','Unknown-Unknown','Druid-Balance','Shaman-Restoration','Mage-Frost','Paladin-Protection','Warlock-Demonology','Rogue-Assassination','Warrior-Protection','Warrior-Arms',}
local provider = {region='US',realm='Dethecus',name='US',type='daily',zone=46,date='2026-05-12',data={Aa='Aashley:BAAALgAECgcJBwAAAA==.',
Al='Alistis:BAAALgADCgEJAQAAAA==.',
Am='Amutio:BAAALgAECgMJCwAAAA==.',
Ar='Arasis:BAABLgAECn8qAAIBAAkJHSUxAQBbAwloDAAABQBgAGkMAAAGAGIAawwAAAYAYgBqDAAABABcAGwMAAAEAF4AbQwAAAMAWwDqDAAACABgAG4MAAAFAFsAbwwAAAEAWgABAAkJHSUxAQBbAwloDAAABQBgAGkMAAAGAGIAawwAAAYAYgBqDAAABABcAGwMAAAEAF4AbQwAAAMAWwDqDAAACABgAG4MAAAFAFsAbwwAAAEAWgAAAA==.Arìel:BAAALgADCgYJBgAAAA==.',
As='Ashhlleyy:BAAALgAECgcJAQAAAA==.',
Ba='Balancing:BAAALgAECgIJAgAAAA==.Bamag:BAABLgAECn8eAAICAAgJgSLxBgA5AwhoDAAABQBfAGkMAAAFAGAAawwAAAUAYgBqDAAABABeAGwMAAAEAFwAbQwAAAIAXADqDAAABABcAG4MAAABADEAAgAICYEi8QYAOQMIaAwAAAUAXwBpDAAABQBgAGsMAAAFAGIAagwAAAQAXgBsDAAABABcAG0MAAACAFwA6gwAAAQAXABuDAAAAQAxAAAA.',
Bi='Bigmak:BAAALgAECgEJAQAAAA==.',
Br='Braellyn:BAAALgAECgUJCQAAAA==.',
Bu='Burnyou:BAAALgADCgYJCwAAAA==.',
Ce='Cenobité:BAABLgAECn8rAAMDAAgJpyQxAwDhAghoDAAABwBgAGkMAAAIAGEAawwAAAYAXwBqDAAABQBYAGwMAAAFAGEAbQwAAAMAYADqDAAABgBeAG4MAAADAE4AAwAICackMQMA4QIIaAwAAAcAYABpDAAACABhAGsMAAAGAF8AagwAAAQAWABsDAAABABhAG0MAAADAGAA6gwAAAYAXgBuDAAAAwBOAAQAAgk/G+9wAH8AAmoMAAABAC0AbAwAAAEARQAAAA==.Ceridemon:BAABLgAECn8ZAAIFAAgJaxApEgB+AQhoDAAABAAhAGkMAAAEAEIAawwAAAQAIgBqDAAAAwAjAGwMAAADADoAbQwAAAIAIADqDAAABAAzAG4MAAABABEABQAICWsQKRIAfgEIaAwAAAQAIQBpDAAABABCAGsMAAAEACIAagwAAAMAIwBsDAAAAwA6AG0MAAACACAA6gwAAAQAMwBuDAAAAQARAAAA.',
Ch='Chingee:BAABLgAECn9EAAMGAAkJ/RmiCQChAgloDAAACQBcAGkMAAAJAEoAawwAAAkATQBqDAAACQA4AGwMAAAJADsAbQwAAAYAMwDqDAAACgBSAG4MAAAFAFAAbwwAAAIAFgAGAAkJ3BiiCQChAgloDAAABwBQAGkMAAAHAEoAawwAAAcATQBqDAAABwA4AGwMAAAHADsAbQwAAAUAJgDqDAAACABSAG4MAAAEAFAAbwwAAAIAFgAHAAgJiw5AJgC6AQhoDAAAAgBcAGkMAAACAD8AawwAAAIAIwBqDAAAAgAMAGwMAAACAAcAbQwAAAEAMwDqDAAAAgAOAG4MAAABABMAAAA=.',
Co='Consarios:BAAALgAECgUJCAAAAA==.',
Cr='Croakadin:BAAALgADCgcJEAAAAA==.Crushers:BAAALgADCggJCAAAAA==.',
Cy='Cyraanden:BAACLgAFFH8IAAIDAAMJ8Az+EwDTAANoDAAAAwAlAGkMAAADACEA6gwAAAIAHAADAAMJ8Az+EwDTAANoDAAAAwAlAGkMAAADACEA6gwAAAIAHAAuAAQKfy4AAwMACAmKGo8LABUCAAMACAmKGo8LABUCAAQAAgmrCKF6AFoAAAAA.Cyvus:BAABLgAECn8dAAMHAAgJSANZQwArAQhoDAAABQAIAGkMAAAFAAUAawwAAAQADQBqDAAABAAMAGwMAAAEAAQAbQwAAAEABADqDAAABQAPAG4MAAABAAAABwAICUgDWUMAKwEIaAwAAAIACABpDAAAAgAFAGsMAAACAA0AagwAAAEADABsDAAAAQAEAG0MAAABAAQA6gwAAAMADwBuDAAAAQAAAAgABgnFCTovAPMABmgMAAADACMAaQwAAAMAFQBrDAAAAgAcAGoMAAADABIAbAwAAAMAFADqDAAAAgASAAAA.',
Da='Dab:BAABLgAECn8vAAIJAAgJFCS2CgDMAghoDAAABwBcAGkMAAAHAF0AawwAAAcAXQBqDAAABQBgAGwMAAAGAGAAbQwAAAQAYwDqDAAACABfAG4MAAADAEsACQAICRQktgoAzAIIaAwAAAcAXABpDAAABwBdAGsMAAAHAF0AagwAAAUAYABsDAAABgBgAG0MAAAEAGMA6gwAAAgAXwBuDAAAAwBLAAAA.Daedara:BAAALgAECgEJAQAAAA==.Daggz:BAABLgAECn8qAAMBAAkJjR3GBQBsAgloDAAABgBXAGkMAAAGAFEAawwAAAYAXQBqDAAABQBVAGwMAAAEAE0AbQwAAAQAPgDqDAAABgBOAG4MAAAEAFcAbwwAAAEAJAAKAAgJth8LEgCnAghoDAAABQBXAGkMAAAFAFEAawwAAAUAXQBqDAAABAA/AGwMAAADAE0AbQwAAAMAPgDqDAAABQBOAG4MAAADAFcAAQAJCccVxgUAbAIJaAwAAAEATQBpDAAAAQBQAGsMAAABAEsAagwAAAEAVQBsDAAAAQArAG0MAAABACcA6gwAAAEAPABuDAAAAQAfAG8MAAABACQAAAA=.Dansgrundle:BAAALgAECgMJAwABLgAECgkJHgALABQaAA==.Darkhorse:BAABLgAECn8bAAIMAAgJ+hqVGgAtAghoDAAABgBJAGkMAAAGAFoAawwAAAMASABqDAAAAwBEAGwMAAADAE4AbQwAAAEADADqDAAABABCAG4MAAABAFkADAAICfoalRoALQIIaAwAAAYASQBpDAAABgBaAGsMAAADAEgAagwAAAMARABsDAAAAwBOAG0MAAABAAwA6gwAAAQAQgBuDAAAAQBZAAAA.Darkmer:BAABLgAECn8eAAIJAAYJvAUfhQDtAAZoDAAABwAPAGkMAAAHABMAawwAAAYADQBqDAAAAwAQAGwMAAACAA4A6gwAAAUACQAJAAYJvAUfhQDtAAZoDAAABwAPAGkMAAAHABMAawwAAAYADQBqDAAAAwAQAGwMAAACAA4A6gwAAAUACQAAAA==.',
De='Deathsnight:BAAALgAECgUJBwAAAA==.Derpy:BAAALgADCgYJCQAAAA==.Deynestta:BAAALgAECgIJBAAAAA==.',
Di='Dixiereaper:BAABLgAECn8VAAINAAkJahBrGgB+AQloDAAAAwBMAGkMAAADADwAawwAAAMALABqDAAAAgAvAGwMAAADACUAbQwAAAEAHgDqDAAAAwAcAG4MAAACAC0AbwwAAAEADQANAAkJahBrGgB+AQloDAAAAwBMAGkMAAADADwAawwAAAMALABqDAAAAgAvAGwMAAADACUAbQwAAAEAHgDqDAAAAwAcAG4MAAACAC0AbwwAAAEADQAAAA==.',
Dr='Droopin:BAAALgADCgYJBwAAAA==.',
Ds='Ds:BAAALgAECgYJCgAAAA==.Dsntdrptotem:BAABLgAECn8cAAMOAAkJkBASMQACAQloDAAABAA8AGkMAAAEADUAawwAAAUANQBqDAAABAAuAGwMAAAEADcAbQwAAAIAGgDqDAAAAwA3AG4MAAABABAAbwwAAAEAEQAPAAcJ2BEXDwAqAQdoDAAABAA8AGkMAAAEADUAawwAAAQANQBqDAAAAwAWAGwMAAADADAAbQwAAAEAAgDqDAAAAwA3AA4ABglwCxIxAAIBBmsMAAABAB4AagwAAAEALgBsDAAAAQA3AG0MAAABABoAbgwAAAEAEABvDAAAAQARAAAA.',
Dt='Dtothep:BAAALgAECgEJAQAAAA==.',
El='Elfangar:BAAALgADCgcJBwAAAA==.',
Ep='Epicamerican:BAAALgAECgEJAQAAAA==.',
Ff='Ffecanti:BAAALgAECgEJAwAAAA==.',
Fl='Floury:BAAALgAECgMJAwAAAA==.',
Ga='Gailen:BAAALgADCgkJDgAAAA==.',
Gi='Gideonn:BAAALgADCgMJAwAAAA==.',
Go='Gorber:BAAALgAFFAMJAwABLgAFFAcJGgAKAJoaAA==.Gorberfn:BAAALgAECgMJAwABLgAFFAcJGgAKAJoaAA==.',
Gr='Grimorn:BAACLgAFFH8aAAIJAAcJrCDxAABGAgdoDAAABQBcAGkMAAAFAGEAawwAAAQAWwBqDAAAAwBaAGwMAAACAFsAbQwAAAEAIQDqDAAABgBfAAkABwmsIPEAAEYCB2gMAAAFAFwAaQwAAAUAYQBrDAAABABbAGoMAAADAFoAbAwAAAIAWwBtDAAAAQAhAOoMAAAGAF8ALgAECn8pAAIJAAkJvyHAAwCZAwAJAAkJvyHAAwCZAwAAAA==.Grogvald:BAABLgAECn8UAAILAAcJfSJTCgB/AgdoDAAAAwBXAGkMAAAEAGAAawwAAAQAWQBqDAAAAwBUAGwMAAABAFMAbQwAAAEAVQDqDAAABABaAAsABwl9IlMKAH8CB2gMAAADAFcAaQwAAAQAYABrDAAABABZAGoMAAADAFQAbAwAAAEAUwBtDAAAAQBVAOoMAAAEAFoAAAA=.',
['Gø']='Gøober:BAACLgAFFH8aAAMKAAcJmhp+AwC2AQdoDAAABQBdAGkMAAAFAFsAawwAAAQAUgBqDAAAAwA4AGwMAAACAEUAbQwAAAEABgDqDAAABgBBABAABgnhG5wDAA8CBmgMAAAEAFQAaQwAAAMARgBrDAAAAwBCAGoMAAACADgAbAwAAAIARQDqDAAAAwBBAAoABgkGGn4DALYBBmgMAAABAF0AaQwAAAIAWwBrDAAAAQBSAGoMAAABAC4AbQwAAAEABgDqDAAAAwA7AC4ABAp/OAAEAQAJCVwjaAEAEwMAEAAJCRQhgwMAbQMAAQAJCS4gaAEAEwMACgABCYcd0q4AUgAAAAA=.',
Ha='Hadrick:BAAALgADCgYJBgAAAA==.',
He='Herax:BAABLgAECn8fAAIOAAgJ4xrbCwAxAghoDAAABQBYAGkMAAAEAEUAawwAAAUAQgBqDAAABAA/AGwMAAADAFgAbQwAAAIAIgDqDAAABgBfAG4MAAACACcADgAICeMa2wsAMQIIaAwAAAUAWABpDAAABABFAGsMAAAFAEIAagwAAAQAPwBsDAAAAwBYAG0MAAACACIA6gwAAAYAXwBuDAAAAgAnAAAA.',
Hi='Hidrógeno:BAACLgAFFH8FAAIRAAMJLgyBOgDtAANoDAAAAgA1AGkMAAABABMA6gwAAAIAFAARAAMJLgyBOgDtAANoDAAAAgA1AGkMAAABABMA6gwAAAIAFAAuAAQKfxcAAhEACAkrHssxAFsCABEACAkrHssxAFsCAAAA.',
Ho='Hoofartted:BAABLgAECn8xAAIPAAgJaCL7AQCwAghoDAAACQBfAGkMAAAIAFQAawwAAAgAYQBqDAAABgBhAGwMAAAFAE4AbQwAAAMASADqDAAABwBfAG4MAAADAFwADwAICWgi+wEAsAIIaAwAAAkAXwBpDAAACABUAGsMAAAIAGEAagwAAAYAYQBsDAAABQBOAG0MAAADAEgA6gwAAAcAXwBuDAAAAwBcAAAA.Horchata:BAAALgAECgMJCAAAAA==.Horndawg:BAAALgADCgkJHAAAAA==.',
Il='Illidara:BAAALgAECgMJAwABLgAFFAIJAgASAAAAAA==.',
Is='Istarìa:BAAALgADCgkJEAAAAA==.',
Jo='Jollyrancher:BAAALgADCgYJBgAAAA==.',
Ju='Judgejobrown:BAAALgAECgcJEwAAAA==.',
Kh='Khajiit:BAABLgAECn8XAAITAAcJ4x0HFAC4AQdoDAAABQBQAGkMAAADAFAAawwAAAQAQABqDAAAAwBXAGwMAAABAEYA6gwAAAQAUABuDAAAAwBSABMABwnjHQcUALgBB2gMAAAFAFAAaQwAAAMAUABrDAAABABAAGoMAAADAFcAbAwAAAEARgDqDAAABABQAG4MAAADAFIAAAA=.',
Ki='Kijana:BAABLgAFFH8EAAIKAAQJIx4PFABTAQRoDAAAAQA+AGkMAAABAEsAawwAAAEAVgDqDAAAAQBTAAoABAkjHg8UAFMBBGgMAAABAD4AaQwAAAEASwBrDAAAAQBWAOoMAAABAFMAAAA=.Kindraa:BAAALgADCgkJEQAAAA==.',
La='Lardpile:BAAALgADCgYJBgAAAA==.Lazaria:BAAALgAECgcJDQAAAA==.',
Le='Leveltwo:BAABLgAECn8lAAIBAAgJLhgOCQAoAghoDAAABgBMAGkMAAAFAEQAawwAAAUANABqDAAABQA+AGwMAAAEAEUAbQwAAAMAUQDqDAAABgAxAG4MAAADACIAAQAICS4YDgkAKAIIaAwAAAYATABpDAAABQBEAGsMAAAFADQAagwAAAUAPgBsDAAABABFAG0MAAADAFEA6gwAAAYAMQBuDAAAAwAiAAAA.',
Li='Litguine:BAAALgAECgQJBgAAAA==.Littlestar:BAABLgAECn8cAAIGAAcJLxJgFQCrAQdoDAAABQA7AGkMAAAFADgAawwAAAUAPwBqDAAABAA1AGwMAAADAC4AbQwAAAEAEADqDAAABQAeAAYABwkvEmAVAKsBB2gMAAAFADsAaQwAAAUAOABrDAAABQA/AGoMAAAEADUAbAwAAAMALgBtDAAAAQAQAOoMAAAFAB4AAAA=.',
Lo='Lockdnloadd:BAAALgADCgUJCAAAAA==.',
Lu='Lucyfurr:BAAALgAECgEJAQABLgAECggJJwAUACUiAA==.Lunea:BAAALgAECgYJCgAAAA==.',
Ly='Lyraa:BAAALgADCgYJEAAAAA==.',
Ma='Marvel:BAAALgADCgkJEwAAAA==.Mattystaff:BAAALgADCgUJBQAAAA==.',
Me='Melanreu:BAAALgAECgEJAQAAAA==.Melvang:BAAALgAECgEJAQAAAA==.',
My='Myrddraal:BAAALgADCgcJCgAAAA==.Mythicc:BAAALgAECgYJBwAAAA==.',
Na='Naenae:BAAALgAECgEJAQAAAA==.Nastybob:BAABLgAECn8hAAIJAAkJxB+hCADmAgloDAAABABZAGkMAAAEAGEAawwAAAQAXwBqDAAABABTAGwMAAAEAE4AbQwAAAQAQADqDAAABABRAG4MAAADAEoAbwwAAAIARAAJAAkJxB+hCADmAgloDAAABABZAGkMAAAEAGEAawwAAAQAXwBqDAAABABTAGwMAAAEAE4AbQwAAAQAQADqDAAABABRAG4MAAADAEoAbwwAAAIARAAAAA==.',
Ni='Nicobulus:BAAALgAECggJEgAAAA==.Nightspell:BAAALgADCgIJAgAAAA==.',
No='Nor:BAABLgAECn8XAAMLAAcJ6x3DHAAvAgdoDAAABABQAGkMAAAEAFQAawwAAAQAVgBqDAAAAwBMAGwMAAADAFsAbQwAAAEAIwDqDAAABABSAAsABgmZIMMcAC8CBmgMAAADAFAAaQwAAAMAVABrDAAAAwBWAGoMAAACAEwAbAwAAAIAWwDqDAAABABSABEABgmOFUNZAFUBBmgMAAABAD4AaQwAAAEAPwBrDAAAAQBOAGoMAAABADMAbAwAAAEAHwBtDAAAAQAoAAAA.',
['Nä']='Näota:BAAALgADCgEJAQAAAA==.',
Pa='Papanoellego:BAACLgAFFH8aAAIVAAcJLRo7AwBHAgdoDAAABQBfAGkMAAAFAFoAawwAAAQAUABqDAAAAwBGAGwMAAACADEAbQwAAAEABQDqDAAABgBQABUABwktGjsDAEcCB2gMAAAFAF8AaQwAAAUAWgBrDAAABABQAGoMAAADAEYAbAwAAAIAMQBtDAAAAQAFAOoMAAAGAFAALgAECn8iAAIVAAkJrCM5AwDLAwAVAAkJrCM5AwDLAwAAAA==.',
Ph='Phcicoknight:BAAALgADCgYJBgAAAA==.Pheal:BAABLgAECn8fAAIJAAgJsBOsLwDSAQhoDAAABQA7AGkMAAAEADkAawwAAAUALABqDAAABAAvAGwMAAADAC8AbQwAAAIAJgDqDAAABgBIAG4MAAACACAACQAICbATrC8A0gEIaAwAAAUAOwBpDAAABAA5AGsMAAAFACwAagwAAAQALwBsDAAAAwAvAG0MAAACACYA6gwAAAYASABuDAAAAgAgAAAA.Phiend:BAAALgAECgQJCQAAAA==.Phlak:BAAALgAECgIJAwAAAA==.',
Pl='Pluvl:BAABLgAECn8WAAIMAAcJPwIwJgDcAAdoDAAAAwADAGkMAAADAAUAawwAAAMABABqDAAAAwACAGwMAAAEAAQAbQwAAAIACADqDAAABAAHAAwABwk/AjAmANwAB2gMAAADAAMAaQwAAAMABQBrDAAAAwAEAGoMAAADAAIAbAwAAAQABABtDAAAAgAIAOoMAAAEAAcAAAA=.',
Qu='Quimby:BAAALgADCgcJDQAAAA==.',
Ra='Raign:BAAALgADCggJCwAAAA==.',
Re='Reyla:BAAALgADCgIJAgABLgAFFAUJFwAMANUiAA==.',
Rh='Rhyze:BAAALgAECgcJCQAAAA==.',
Ri='Rivent:BAAALgAECgUJBwAAAA==.Rivia:BAABLgAECn8UAAIRAAgJuxf2QQAfAghoDAAAAwBHAGkMAAAEAE0AawwAAAMALABqDAAAAwBBAGwMAAACAD4AbQwAAAEANwDqDAAAAwA/AG4MAAABADEAEQAICbsX9kEAHwIIaAwAAAMARwBpDAAABABNAGsMAAADACwAagwAAAMAQQBsDAAAAgA+AG0MAAABADcA6gwAAAMAPwBuDAAAAQAxAAAA.',
Ro='Royalmace:BAAALgAECgQJBAAAAA==.',
Sa='Safaridan:BAABLgAECn8eAAQLAAkJFBpWGQBIAgloDAAABQA5AGkMAAAEAEEAawwAAAQAPgBqDAAABABHAGwMAAAEAFMAbQwAAAEALQDqDAAABABYAG4MAAADAD8AbwwAAAEAPwALAAkJFBpWGQBIAgloDAAABAA5AGkMAAADAEEAawwAAAMAPgBqDAAAAgBHAGwMAAADAFMAbQwAAAEALQDqDAAAAwBYAG4MAAACAD8AbwwAAAEAPwAWAAUJXgwAIACoAAVoDAAAAQAbAGkMAAABACQAawwAAAEANgBqDAAAAgAuAGwMAAABAAgAEQACCXoHZRcBNwAC6gwAAAEADwBuDAAAAQAWAAAA.Sapphirre:BAAALgADCgcJDgAAAA==.Savsham:BAAALgADCgEJAQAAAA==.',
Sc='Scamp:BAAALgADCgQJBAAAAA==.Scrump:BAAALgAECgQJBQAAAA==.',
Sh='Shtick:BAAALgADCggJDQAAAA==.',
Si='Sienen:BAAALgAECgQJBAAAAA==.',
Sj='Sjk:BAABLgAECn8WAAIFAAgJXyCjBgD8AghoDAAAAwBYAGkMAAAEAFcAawwAAAQAWQBqDAAAAwBTAGwMAAADAEgAbQwAAAIAUADqDAAAAgBcAG4MAAABAEQABQAICV8gowYA/AIIaAwAAAMAWABpDAAABABXAGsMAAAEAFkAagwAAAMAUwBsDAAAAwBIAG0MAAACAFAA6gwAAAIAXABuDAAAAQBEAAAA.',
Sl='Slabia:BAABLgAECn8VAAIRAAcJsCC4MQBcAgdoDAAABQBjAGkMAAAFAFgAawwAAAQAWABqDAAAAgBSAGwMAAACAD4A6gwAAAIAPgBuDAAAAQBjABEABwmwILgxAFwCB2gMAAAFAGMAaQwAAAUAWABrDAAABABYAGoMAAACAFIAbAwAAAIAPgDqDAAAAgA+AG4MAAABAGMAAAA=.Slashly:BAAALgAECgEJAwAAAA==.Sloan:BAAALgAECgUJCwAAAA==.',
Sp='Spektrum:BAAALgADCgEJAQAAAA==.',
St='Stacey:BAAALgAECgQJBAABLgAFFAgJJgAIAOMdAA==.Stepmom:BAAALgAFFAIJAgAAAA==.Stepsis:BAAALgAFFAIJBAAAAA==.Stiick:BAAALgADCgUJBQAAAA==.',
Sv='Svinehundt:BAABLgAECn8cAAIXAAgJExQtKwDIAQhoDAAABgA1AGkMAAAFAD4AawwAAAUANwBqDAAAAgAnAGwMAAACADAAbQwAAAEALgDqDAAABgBNAG4MAAABABAAFwAICRMULSsAyAEIaAwAAAYANQBpDAAABQA+AGsMAAAFADcAagwAAAIAJwBsDAAAAgAwAG0MAAABAC4A6gwAAAYATQBuDAAAAQAQAAAA.',
Ta='Tabtok:BAAALgADCgcJDgAAAA==.Tanalin:BAAALgADCgMJAwABLgAECggJHAAXABMUAA==.Tanglebones:BAABLgAECn8UAAIYAAYJwgtBCwAiAQZoDAAABAAxAGkMAAAEAB4AawwAAAQAIwBqDAAAAgAdAGwMAAACAA4A6gwAAAQAFAAYAAYJwgtBCwAiAQZoDAAABAAxAGkMAAAEAB4AawwAAAQAIwBqDAAAAgAdAGwMAAACAA4A6gwAAAQAFAAAAA==.Tasty:BAAALgAECgEJAQABLgAFFAMJCQAUALgcAA==.Taukra:BAAALgADCgYJBgAAAA==.',
To='Tore:BAAALgAECgYJDAAAAA==.',
Tr='Trazie:BAAALgAECgYJCQAAAA==.Trenn:BAAALgADCgkJCQABLgAECggJEgASAAAAAA==.',
Un='Unsocial:BAAALgADCgkJEAAAAA==.',
Ve='Vecna:BAAALgAECgEJAQABLgAECgYJEAASAAAAAA==.Vermi:BAAALgAECgIJAgAAAA==.',
Wa='Warcloud:BAABLgAECn8VAAILAAcJSAQmNwAAAQdoDAAAAwAWAGkMAAADAAgAawwAAAMACgBqDAAAAwADAGwMAAAEABIAbQwAAAIABADqDAAAAwAIAAsABwlIBCY3AAABB2gMAAADABYAaQwAAAMACABrDAAAAwAKAGoMAAADAAMAbAwAAAQAEgBtDAAAAgAEAOoMAAADAAgAAAA=.Wartortle:BAABLgAECn8pAAMZAAYJMxuHFADEAQZoDAAACQBBAGkMAAAHAFUAawwAAAcAUQBqDAAACAA0AGwMAAAIAEsAbQwAAAIAKAAZAAYJMxuHFADEAQZoDAAACABBAGkMAAAHAFUAawwAAAcAUQBqDAAACAA0AGwMAAAIAEsAbQwAAAIAKAAaAAEJnQkxRgAyAAFoDAAAAQAYAAAA.',
Wh='Whack:BAAALgAECgYJBgAAAA==.',
Ws='Wsedfgghj:BAAALgAECgYJCgAAAA==.',
Wu='Wu:BAAALgAECgIJAgAAAA==.Wulfgaz:BAAALgAECgYJCgAAAA==.',
Wy='Wyldhart:BAAALgAECgEJAQAAAA==.Wylf:BAAALgADCgcJBwABLgAECgYJCgASAAAAAA==.',
Xt='Xtheleon:BAAALgADCgUJBQAAAA==.',
Ze='Zenn:BAAALgAECggJEgAAAA==.Zeroomega:BAAALgADCgMJAwAAAA==.Zerø:BAAALgADCgYJBgAAAA==.',
Zi='Zinthous:BAAALgAECgEJAQAAAA==.',
['Äl']='Ältäir:BAABLgAECn8fAAIUAAgJhxh2GwDvAQhoDAAABQBTAGkMAAAEAEcAawwAAAUARQBqDAAABAAxAGwMAAADAEEAbQwAAAIANADqDAAABgBGAG4MAAACACcAFAAICYcYdhsA7wEIaAwAAAUAUwBpDAAABABHAGsMAAAFAEUAagwAAAQAMQBsDAAAAwBBAG0MAAACADQA6gwAAAYARgBuDAAAAgAnAAAA.',
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
