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

local lookup = {'Warrior-Fury','Hunter-Survival','Druid-Feral','Druid-Guardian','Monk-Mistweaver','Monk-Windwalker','Monk-Brewmaster','DemonHunter-Havoc','Priest-Holy','Priest-Discipline','Warlock-Demonology','Paladin-Retribution','Priest-Shadow','DeathKnight-Unholy','Hunter-BeastMastery','Paladin-Holy','Rogue-Subtlety','DeathKnight-Blood','Shaman-Elemental','Shaman-Enhancement','Evoker-Augmentation','Hunter-Marksmanship','Mage-Frost','Druid-Balance','Shaman-Restoration','Unknown-Unknown','DeathKnight-Frost','Paladin-Protection','DemonHunter-Devourer','Rogue-Assassination','Warrior-Protection','Warrior-Arms',}
local provider = {region='US',realm='Dethecus',name='US',type='daily',zone=46,date='2026-06-18',data={Aa='Aashley:BAAALgAECgcJBwAAAA==.',
Al='Alistis:BAAALgADCgEJAQAAAA==.',
Am='Amutio:BAAALgAECgMJDgAAAA==.',
An='Andromedus:BAAALgAFFAEJAgABLgAFFAgJKwABAHocAA==.',
Ar='Arasis:BAACLgAFFH8FAAICAAMJeRr7GAAKAQNoDAAAAgBfAGkMAAABABMA6gwAAAIAWAACAAMJeRr7GAAKAQNoDAAAAgBfAGkMAAABABMA6gwAAAIAWAAuAAQKfzUAAgIACQl5JR8CADEDAAIACQl5JR8CADEDAAAA.Arìel:BAAALgAECgEJAQAAAA==.',
As='Asexpected:BAAALgAECggJCQABLgAECgkJGAADADEYAA==.Ashhleyy:BAAALgAECgcJBgAAAA==.Ashhlleyy:BAAALgAECgcJAQAAAA==.Ashleyy:BAAALgAECgcJBgAAAA==.',
Ba='Balancing:BAABLgAFFH8HAAIEAAIJShv1IACZAAJoDAAABAA4AOoMAAADAFIABAACCUob9SAAmQACaAwAAAQAOADqDAAAAwBSAAAA.Bamag:BAABLgAECn8eAAIBAAgJgSLxBgA5AwhoDAAABQBfAGkMAAAFAGAAawwAAAUAYgBqDAAABABeAGwMAAAEAFwAbQwAAAIAXADqDAAABABcAG4MAAABADEAAQAICYEi8QYAOQMIaAwAAAUAXwBpDAAABQBgAGsMAAAFAGIAagwAAAQAXgBsDAAABABcAG0MAAACAFwA6gwAAAQAXABuDAAAAQAxAAAA.',
Bi='Bigmak:BAAALgAECgkJDAAAAA==.',
Bo='Boom:BAAALgAFFAcJBAABLgAFFAkJCwAFAOIdAA==.',
Br='Braellyn:BAAALgAECgUJCQAAAA==.',
Bu='Burnyou:BAAALgADCgkJHQAAAA==.',
Ce='Celestine:BAAALgAECgEJAQAAAA==.Cenobité:BAABLgAECn8rAAMGAAgJqCSzCQCpAghoDAAABwBgAGkMAAAIAGEAawwAAAYAXwBqDAAABQBYAGwMAAAFAGEAbQwAAAMAYADqDAAABgBeAG4MAAADAE4ABgAICagkswkAqQIIaAwAAAcAYABpDAAACABhAGsMAAAGAF8AagwAAAQAWABsDAAABABhAG0MAAADAGAA6gwAAAYAXgBuDAAAAwBOAAcAAgk/G+9wAH8AAmoMAAABAC0AbAwAAAEARQAAAA==.Ceridemon:BAABLgAECn8kAAIIAAkJFBDYHQCNAQloDAAABQAlAGkMAAAFAEIAawwAAAUAIgBqDAAABAAjAGwMAAAEADoAbQwAAAMAIADqDAAABQAzAG4MAAADABUAbwwAAAIAGgAIAAkJFBDYHQCNAQloDAAABQAlAGkMAAAFAEIAawwAAAUAIgBqDAAABAAjAGwMAAAEADoAbQwAAAMAIADqDAAABQAzAG4MAAADABUAbwwAAAIAGgAAAA==.',
Ch='Chingee:BAACLgAFFH8GAAMJAAYJ+QEtHQDPAAZoDAAAAQACAGkMAAABAAIAawwAAAEAAwBqDAAAAQAGAGwMAAABAAsA6gwAAAEABAAJAAQJQgItHQDPAARpDAAAAQACAGsMAAABAAMAagwAAAEABgBsDAAAAQALAAoAAglmAfZGAFcAAmgMAAABAAIA6gwAAAEABAAuAAQKf0wAAwoACQnHGqIJAKECAAoACQnsGaIJAKECAAkACAmLDkAmALoBAAAA.',
Co='Cobalt:BAAALgAECgUJBQABLgAFFAMJBwALAN8aAA==.Cobel:BAAALgAECgMJAwAAAA==.Consarios:BAABLgAFFH8HAAIMAAYJHRnEHQCRAQZoDAAAAQBPAGkMAAABAFMAawwAAAEATwBqDAAAAQAuAGwMAAABABMA6gwAAAIAOgAMAAYJHRnEHQCRAQZoDAAAAQBPAGkMAAABAFMAawwAAAEATwBqDAAAAQAuAGwMAAABABMA6gwAAAIAOgAAAA==.',
Cr='Croakadin:BAAALgADCgcJEAAAAA==.Crushers:BAAALgADCggJCAAAAA==.',
Cy='Cyraanden:BAACLgAFFH8UAAMGAAQJIBOXIgDLAARoDAAABgBBAGkMAAAHADsAawwAAAEAJgDqDAAABgAgAAYAAwmFFJciAMsAA2gMAAAFAEEAaQwAAAYAOwDqDAAABgAgAAcAAwltCss6ALsAA2gMAAABABoAaQwAAAEADwBrDAAAAQAmAC4ABAp/NQADBgAJCbsatxEANQIABgAJCU4atxEANQIABwAECR4ULk4AxwAAAAA=.Cyvus:BAABLgAECn8kAAMJAAgJawVZQwArAQhoDAAABgAIAGkMAAAGAAUAawwAAAUAEwBqDAAABQAZAGwMAAAFABAAbQwAAAIAEQDqDAAABgAPAG4MAAABAAAACQAICWsFWUMAKwEIaAwAAAIACABpDAAAAgAFAGsMAAADABMAagwAAAIAGQBsDAAAAgAQAG0MAAACABEA6gwAAAMADwBuDAAAAQAAAA0ABgn7CSVNANsABmgMAAAEACYAaQwAAAQAFQBrDAAAAgAcAGoMAAADABIAbAwAAAMAFADqDAAAAwASAAAA.',
Da='Dab:BAABLgAECn9BAAIOAAkJhSWgBABZAwloDAAACQBgAGkMAAAJAGMAawwAAAkAYQBqDAAABwBhAGwMAAAIAGAAbQwAAAYAYwDqDAAACgBfAG4MAAAFAFQAbwwAAAIAYwAOAAkJhSWgBABZAwloDAAACQBgAGkMAAAJAGMAawwAAAkAYQBqDAAABwBhAGwMAAAIAGAAbQwAAAYAYwDqDAAACgBfAG4MAAAFAFQAbwwAAAIAYwAAAA==.Daedara:BAAALgAECgMJBAAAAA==.Daggz:BAABLgAECn8yAAMPAAkJER8LEgCnAgloDAAABwBXAGkMAAAHAFEAawwAAAcAXQBqDAAABgBVAGwMAAAFAE0AbQwAAAUAQADqDAAABwBOAG4MAAAEAFcAbwwAAAIAQgAPAAgJtx8LEgCnAghoDAAABQBXAGkMAAAFAFEAawwAAAUAXQBqDAAABAA/AGwMAAADAE0AbQwAAAMAPgDqDAAABQBOAG4MAAADAFcAAgAJCfUYAgwAYgIJaAwAAAIAVgBpDAAAAgBQAGsMAAACAEwAagwAAAIAVQBsDAAAAgAtAG0MAAACAEAA6gwAAAIAPABuDAAAAQAfAG8MAAACAEIAAAA=.Dansgrundle:BAAALgAECgMJAwABLgAECgkJHgAQABQaAA==.Darkhorse:BAABLgAECn8mAAIRAAgJwh6PDABdAghoDAAACABTAGkMAAAIAF0AawwAAAUAVgBqDAAABABeAGwMAAAEAFcAbQwAAAEADADqDAAABgBcAG4MAAACAF4AEQAICcIejwwAXQIIaAwAAAgAUwBpDAAACABdAGsMAAAFAFYAagwAAAQAXgBsDAAABABXAG0MAAABAAwA6gwAAAYAXABuDAAAAgBeAAAA.Darkmer:BAABLgAECn86AAIOAAgJUApqiABTAQhoDAAACwAcAGkMAAALABkAawwAAAoAFABqDAAABwAYAGwMAAAGACMAbQwAAAIAEgDqDAAACQAnAG4MAAACABEADgAICVAKaogAUwEIaAwAAAsAHABpDAAACwAZAGsMAAAKABQAagwAAAcAGABsDAAABgAjAG0MAAACABIA6gwAAAkAJwBuDAAAAgARAAAA.',
De='Deathsnight:BAAALgAECgUJBwAAAA==.Derpy:BAAALgADCgYJCQAAAA==.Deynestta:BAAALgAECgIJBAAAAA==.',
Di='Dixiereaper:BAABLgAECn8WAAISAAkJahBrGgB+AQloDAAAAwBMAGkMAAADADwAawwAAAMALABqDAAAAgAvAGwMAAADACUAbQwAAAIAHgDqDAAAAwAcAG4MAAACAC0AbwwAAAEADQASAAkJahBrGgB+AQloDAAAAwBMAGkMAAADADwAawwAAAMALABqDAAAAgAvAGwMAAADACUAbQwAAAIAHgDqDAAAAwAcAG4MAAACAC0AbwwAAAEADQAAAA==.',
Dr='Droopin:BAAALgADCgYJBwAAAA==.',
Ds='Ds:BAAALgAECgcJCwAAAA==.Dsntdrptotem:BAABLgAECn8xAAMTAAkJVBUgJADGAQloDAAABgA8AGkMAAAFADUAawwAAAYANQBqDAAABQAuAGwMAAAGADcAbQwAAAQAGgDqDAAABwA3AG4MAAAFAFgAbwwAAAUAKwATAAkJ2xIgJADGAQloDAAAAgAnAGkMAAABADEAawwAAAIAHwBqDAAAAgAuAGwMAAADADcAbQwAAAMAGgDqDAAABAAzAG4MAAAFAFgAbwwAAAUAKwAUAAcJ2BGDEwCBAQdoDAAABAA8AGkMAAAEADUAawwAAAQANQBqDAAAAwAWAGwMAAADADAAbQwAAAEAAgDqDAAAAwA3AAAA.',
Dt='Dtothep:BAAALgAECgEJAQAAAA==.',
El='Elfangar:BAAALgAECgEJAQAAAA==.',
Ep='Epicamerican:BAAALgAECgUJBQAAAA==.',
Ff='Ffecanti:BAAALgAECgYJCQAAAA==.',
Fl='Floury:BAAALgAECgMJAwAAAA==.',
Ga='Gailen:BAAALgADCgkJDgAAAA==.',
Gi='Gideonn:BAAALgADCgMJAwAAAA==.',
Go='Gorber:BAABLgAECn8WAAIVAAgJDRZoIgDHAQhoDAAAAwA9AGkMAAADAEMAawwAAAMAQQBqDAAAAwBLAGwMAAADAEwAbQwAAAIAIADqDAAAAwA4AG4MAAACACMAFQAICQ0WaCIAxwEIaAwAAAMAPQBpDAAAAwBDAGsMAAADAEEAagwAAAMASwBsDAAAAwBMAG0MAAACACAA6gwAAAMAOABuDAAAAgAjAAEuAAUUCAkoAA8AwBoA.Gorberfn:BAAALgAECgMJAwABLgAFFAgJKAAPAMAaAA==.',
Gr='Grimorn:BAACLgAFFH8iAAIOAAgJfyDxAABGAghoDAAABgBjAGkMAAAGAGMAawwAAAUAWwBqDAAABABaAGwMAAADAGEAbQwAAAEAIQDqDAAACABfAG4MAAABAEEADgAICX8g8QAARgIIaAwAAAYAYwBpDAAABgBjAGsMAAAFAFsAagwAAAQAWgBsDAAAAwBhAG0MAAABACEA6gwAAAgAXwBuDAAAAQBBAC4ABAp/KQACDgAJCcAhwAMAmQMADgAJCcAhwAMAmQMAAAA=.Grogvald:BAABLgAECn8tAAIQAAgJ+iX5AgB0AwhoDAAABgBfAGkMAAAHAGIAawwAAAcAYwBqDAAABgBjAGwMAAAEAGMAbQwAAAQAYQDqDAAABwBiAG4MAAAEAFoAEAAICfol+QIAdAMIaAwAAAYAXwBpDAAABwBiAGsMAAAHAGMAagwAAAYAYwBsDAAABABjAG0MAAAEAGEA6gwAAAcAYgBuDAAABABaAAAA.',
['Gø']='Gøober:BAACLgAFFH8oAAQPAAgJwBrGDAADAghoDAAABwBdAGkMAAAHAGMAawwAAAYAUgBqDAAABQA4AGwMAAAEAEUAbQwAAAEABgDqDAAACQBYAG4MAAABACgAFgAGCeEbnAMADwIGaAwAAAQAVABpDAAAAwBGAGsMAAADAEIAagwAAAIAOABsDAAABABFAOoMAAADAEEADwAHCbQaxgwAAwIHaAwAAAEAXQBpDAAAAwBjAGsMAAACAFIAagwAAAMALgBtDAAAAQAGAOoMAAAGAFgAbgwAAAEAKAACAAMJICHjFwATAQNoDAAAAgBbAGkMAAABAFUAawwAAAEATQAuAAQKf0IABBYACQlCJoMDAG0DABYACQkUIYMDAG0DAAIACQnlIMMFAMkCAA8ABwmqJP0dAHICAAAA.',
Ha='Hadrick:BAAALgAFFAEJAQAAAA==.',
He='Herax:BAABLgAECn8hAAITAAgJ4xqgHQD0AQhoDAAABQBYAGkMAAAEAEUAawwAAAUAQgBqDAAABAA/AGwMAAADAFgAbQwAAAIAIgDqDAAABwBfAG4MAAADACcAEwAICeMaoB0A9AEIaAwAAAUAWABpDAAABABFAGsMAAAFAEIAagwAAAQAPwBsDAAAAwBYAG0MAAACACIA6gwAAAcAXwBuDAAAAwAnAAAA.',
Hi='Hidrógeno:BAACLgAFFH8FAAIMAAMJLgxnegDBAANoDAAAAgA1AGkMAAABABMA6gwAAAIAFAAMAAMJLgxnegDBAANoDAAAAgA1AGkMAAABABMA6gwAAAIAFAAuAAQKfxcAAgwACAkrHssxAFsCAAwACAkrHssxAFsCAAAA.Hinigy:BAAALgAECgUJBgABLgAECggJKAALALoWAA==.',
Ho='Hoofartted:BAACLgAFFH8GAAIUAAMJUhjrDQDgAANoDAAAAgBQAGkMAAABAC4A6gwAAAMAPAAUAAMJUhjrDQDgAANoDAAAAgBQAGkMAAABAC4A6gwAAAMAPAAuAAQKfzkAAhQACAnOI2kEAKsCABQACAnOI2kEAKsCAAAA.Horchata:BAAALgAECgMJCAAAAA==.Horndawg:BAAALgADCgkJHAAAAA==.',
Il='Illidara:BAAALgAECgMJAwABLgAFFAMJCwARAPgZAA==.',
Is='Istarìa:BAAALgAECgEJAQAAAA==.',
Ja='Jachen:BAAALgADCgMJAwAAAA==.',
Jo='Jollyrancher:BAAALgADCgYJBgAAAA==.',
Ju='Judgejobrown:BAABLgAECn8gAAIXAAkJLhbBPwAdAgloDAAABQA8AGkMAAAFAEgAawwAAAQAQQBqDAAABABUAGwMAAAEADcAbQwAAAEAEADqDAAABQBIAG4MAAADAD0AbwwAAAEAMwAXAAkJLhbBPwAdAgloDAAABQA8AGkMAAAFAEgAawwAAAQAQQBqDAAABABUAGwMAAAEADcAbQwAAAEAEADqDAAABQBIAG4MAAADAD0AbwwAAAEAMwAAAA==.',
Ka='Katarina:BAAALgAECgEJAQAAAA==.',
Kh='Khajiit:BAABLgAECn8YAAIYAAcJ4x0VKACQAQdoDAAABQBQAGkMAAADAFAAawwAAAQAQABqDAAAAwBXAGwMAAABAEYA6gwAAAUAUABuDAAAAwBSABgABwnjHRUoAJABB2gMAAAFAFAAaQwAAAMAUABrDAAABABAAGoMAAADAFcAbAwAAAEARgDqDAAABQBQAG4MAAADAFIAAAA=.',
Ki='Kijana:BAABLgAFFH8IAAIPAAQJ6iSxIACCAQRoDAAAAgBiAGkMAAACAF8AawwAAAEAVgDqDAAAAwBhAA8ABAnqJLEgAIIBBGgMAAACAGIAaQwAAAIAXwBrDAAAAQBWAOoMAAADAGEAAS4ABRQICR4ADwCdHAA=.Kindraa:BAAALgADCgkJKgAAAA==.',
La='Laherrmosa:BAAALgAECgQJBAAAAA==.Lardpile:BAAALgADCgYJBgAAAA==.Lazaria:BAAALgAECgcJDQAAAA==.',
Le='Leveltwo:BAABLgAECn9HAAQCAAkJMx6SBgC3AgloDAAACgBXAGkMAAAKAFgAawwAAAoANABqDAAACABSAGwMAAAHAFIAbQwAAAUAUgDqDAAACwBHAG4MAAAHAE8AbwwAAAMASQACAAkJMx6SBgC3AgloDAAACgBXAGkMAAAKAFgAawwAAAgANABqDAAACABSAGwMAAAHAFIAbQwAAAUAUgDqDAAACwBHAG4MAAAHAE8AbwwAAAMASQAWAAEJFhESOwA1AAFrDAAAAQArAA8AAQlWBCtJASkAAWsMAAABAAsAAAA=.',
Li='Litguine:BAAALgAECgQJBgAAAA==.Littlestar:BAABLgAECn9LAAIKAAkJFRU3FQAxAgloDAAACgA7AGkMAAAJADgAawwAAAoAPwBqDAAACQA1AGwMAAAKAD8AbQwAAAQAIADqDAAADAAzAG4MAAAIAC4AbwwAAAMAOwAKAAkJFRU3FQAxAgloDAAACgA7AGkMAAAJADgAawwAAAoAPwBqDAAACQA1AGwMAAAKAD8AbQwAAAQAIADqDAAADAAzAG4MAAAIAC4AbwwAAAMAOwAAAA==.',
Lo='Lockdnloadd:BAAALgADCgUJCAAAAA==.',
Lu='Lucyfurr:BAAALgAECgUJBgABLgAECgkJLAAZALQgAA==.Lunea:BAAALgAECgYJCgAAAA==.',
Ly='Lyraa:BAAALgADCgYJEAAAAA==.',
Ma='Marvel:BAAALgADCgkJEwAAAA==.Mattystaff:BAAALgADCgUJBQABLgAECgMJAwAaAAAAAA==.',
Me='Melanreu:BAAALgAECgEJAQAAAA==.Melvang:BAAALgAECgUJBgAAAA==.',
My='Myrddraal:BAAALgAECgcJBwAAAA==.Mythicc:BAAALgAECgYJBwAAAA==.',
Na='Naenae:BAAALgAECgMJBQAAAA==.Nastybob:BAABLgAECn8zAAIOAAkJtyQ+CAAxAwloDAAABgBjAGkMAAAGAGEAawwAAAYAXwBqDAAABgBTAGwMAAAGAFkAbQwAAAYAXwDqDAAABgBbAG4MAAAFAFcAbwwAAAQAYAAOAAkJtyQ+CAAxAwloDAAABgBjAGkMAAAGAGEAawwAAAYAXwBqDAAABgBTAGwMAAAGAFkAbQwAAAYAXwDqDAAABgBbAG4MAAAFAFcAbwwAAAQAYAAAAA==.',
Ni='Nicobulus:BAABLgAECn8hAAITAAkJHBA9LACUAQloDAAABQAoAGkMAAAFADMAawwAAAQAKQBqDAAABAASAGwMAAADABgAbQwAAAEAIQDqDAAABgA6AG4MAAAEACEAbwwAAAEALwATAAkJHBA9LACUAQloDAAABQAoAGkMAAAFADMAawwAAAQAKQBqDAAABAASAGwMAAADABgAbQwAAAEAIQDqDAAABgA6AG4MAAAEACEAbwwAAAEALwAAAA==.Nightsblack:BAAALgADCggJCAAAAA==.Nightspell:BAAALgAECgUJCgAAAA==.',
No='Nor:BAABLgAECn8XAAMQAAcJ7B3DHAAvAgdoDAAABABQAGkMAAAEAFQAawwAAAQAVgBqDAAAAwBMAGwMAAADAFsAbQwAAAEAIwDqDAAABABSABAABgmZIMMcAC8CBmgMAAADAFAAaQwAAAMAVABrDAAAAwBWAGoMAAACAEwAbAwAAAIAWwDqDAAABABSAAwABgmOFfqmAC0BBmgMAAABAD4AaQwAAAEAPwBrDAAAAQBOAGoMAAABADMAbAwAAAEAHwBtDAAAAQAoAAAA.',
['Nä']='Näota:BAAALgAECgUJBQAAAA==.',
Pa='Papanoellego:BAACLgAFFH8nAAIXAAgJ8xc7AwBHAghoDAAABwBfAGkMAAAHAGMAawwAAAYAXwBqDAAABQBQAGwMAAAEADEAbQwAAAEABQDqDAAACABQAG4MAAABAAMAFwAICfMXOwMARwIIaAwAAAcAXwBpDAAABwBjAGsMAAAGAF8AagwAAAUAUABsDAAABAAxAG0MAAABAAUA6gwAAAgAUABuDAAAAQADAC4ABAp/KQACFwAJCQEkOQMAywMAFwAJCQEkOQMAywMAAAA=.',
Ph='Phcicoknight:BAAALgADCgYJBgAAAA==.Pheal:BAABLgAECn8hAAMOAAgJ2hWVWwC0AQhoDAAABQA7AGkMAAAEADkAawwAAAUALABqDAAABAAvAGwMAAADAC8AbQwAAAIAJgDqDAAABwBIAG4MAAADAEcADgAICdoVlVsAtAEIaAwAAAUAOwBpDAAABAA5AGsMAAAFACwAagwAAAQALwBsDAAAAwAvAG0MAAACACYA6gwAAAYASABuDAAAAwBHABsAAQkDEyw5ADgAAeoMAAABADAAAAA=.Phiend:BAAALgAECgQJEQAAAA==.Phlak:BAABLgAECn8UAAIZAAYJVAvqdgD5AAZoDAAABQApAGkMAAADABAAawwAAAMAFABqDAAAAgAcAGwMAAABAB4A6gwAAAYAJQAZAAYJVAvqdgD5AAZoDAAABQApAGkMAAADABAAawwAAAMAFABqDAAAAgAcAGwMAAABAB4A6gwAAAYAJQAAAA==.',
Pl='Pluvl:BAABLgAECn8eAAIRAAkJkQObKwA8AQloDAAAAwADAGkMAAADAAUAawwAAAMABABqDAAAAwACAGwMAAAFAAkAbQwAAAMACgDqDAAABwAJAG4MAAACAAoAbwwAAAEAEgARAAkJkQObKwA8AQloDAAAAwADAGkMAAADAAUAawwAAAMABABqDAAAAwACAGwMAAAFAAkAbQwAAAMACgDqDAAABwAJAG4MAAACAAoAbwwAAAEAEgAAAA==.',
['Pö']='Pöstal:BAAALgAECgEJAQAAAA==.',
Qu='Quimby:BAAALgAECgcJDgAAAA==.',
Ra='Raign:BAAALgAECgcJEgAAAA==.',
Re='Reyla:BAAALgADCgIJAgABLgAFFAcJHQARAD4ZAA==.',
Rh='Rhyze:BAAALgAECgcJDgAAAA==.',
Ri='Rivent:BAAALgAECgYJCAAAAA==.Rivia:BAABLgAECn8cAAIMAAgJrBz2QQAfAghoDAAABABSAGkMAAAGAFsAawwAAAMALABqDAAAAwBBAGwMAAACAD4AbQwAAAIANwDqDAAABQBgAG4MAAADAFAADAAICawc9kEAHwIIaAwAAAQAUgBpDAAABgBbAGsMAAADACwAagwAAAMAQQBsDAAAAgA+AG0MAAACADcA6gwAAAUAYABuDAAAAwBQAAAA.',
Ro='Royalmace:BAAALgAECgQJBAAAAA==.',
Sa='Saannthh:BAAALgAECgcJBwAAAA==.Safaridan:BAABLgAECn8eAAQQAAkJFBpWGQBIAgloDAAABQA5AGkMAAAEAEEAawwAAAQAPgBqDAAABABHAGwMAAAEAFMAbQwAAAEALQDqDAAABABYAG4MAAADAD8AbwwAAAEAPwAQAAkJFBpWGQBIAgloDAAABAA5AGkMAAADAEEAawwAAAMAPgBqDAAAAgBHAGwMAAADAFMAbQwAAAEALQDqDAAAAwBYAG4MAAACAD8AbwwAAAEAPwAcAAUJXgwEMwCXAAVoDAAAAQAbAGkMAAABACQAawwAAAEANgBqDAAAAgAuAGwMAAABAAgADAACCXoH47EBKQAC6gwAAAEADwBuDAAAAQAWAAAA.Saimie:BAAALgAECgkJBQAAAA==.Sapphirre:BAAALgAECgEJAQAAAA==.Savsham:BAAALgADCgEJAQAAAA==.',
Sc='Scamp:BAAALgAECgEJAgAAAA==.Scrump:BAAALgAECgQJBQAAAA==.',
Sh='Shtick:BAAALgADCggJDQAAAA==.',
Si='Sienen:BAAALgAECgUJCwAAAA==.',
Sj='Sjk:BAABLgAECn8WAAIIAAgJXyCjBgD8AghoDAAAAwBYAGkMAAAEAFcAawwAAAQAWQBqDAAAAwBTAGwMAAADAEgAbQwAAAIAUADqDAAAAgBcAG4MAAABAEQACAAICV8gowYA/AIIaAwAAAMAWABpDAAABABXAGsMAAAEAFkAagwAAAMAUwBsDAAAAwBIAG0MAAACAFAA6gwAAAIAXABuDAAAAQBEAAAA.',
Sk='Skass:BAAALgAECgIJAgAAAA==.',
Sl='Slabia:BAABLgAECn8VAAIMAAcJsCC4MQBcAgdoDAAABQBjAGkMAAAFAFgAawwAAAQAWABqDAAAAgBSAGwMAAACAD4A6gwAAAIAPgBuDAAAAQBjAAwABwmwILgxAFwCB2gMAAAFAGMAaQwAAAUAWABrDAAABABYAGoMAAACAFIAbAwAAAIAPgDqDAAAAgA+AG4MAAABAGMAAAA=.Slade:BAAALgAECgEJAQAAAA==.Slashly:BAAALgAECgEJBQAAAA==.Sloan:BAABLgAECn8dAAIKAAYJFwTATQDMAAZoDAAACAAMAGkMAAAHAAkAawwAAAYACQBqDAAABQARAGwMAAACAAkA6gwAAAEAAwAKAAYJFwTATQDMAAZoDAAACAAMAGkMAAAHAAkAawwAAAYACQBqDAAABQARAGwMAAACAAkA6gwAAAEAAwAAAA==.',
Sp='Spektrum:BAAALgADCgEJAQAAAA==.Spicychicken:BAAALgAFFAEJAgABLgAFFAgJJAAdAIIZAA==.',
Sq='Squirrelydan:BAAALgAECgEJAQAAAA==.',
St='Stacey:BAAALgAECgQJBAABLgAFFAkJLwANAJgfAA==.Stepmom:BAAALgAFFAIJAgAAAA==.Stepsis:BAAALgAFFAIJBAAAAA==.Sticky:BAAALgAECgIJAwABLgAFFAQJCwAVAN8RAA==.Stiick:BAAALgADCgUJBQAAAA==.',
Sv='Svinehundt:BAABLgAECn8oAAILAAgJuhanQADbAQhoDAAACAA1AGkMAAAHAEUAawwAAAcANwBqDAAABABAAGwMAAAEAEgAbQwAAAIAPQDqDAAABwBNAG4MAAABABAACwAICboWp0AA2wEIaAwAAAgANQBpDAAABwBFAGsMAAAHADcAagwAAAQAQABsDAAABABIAG0MAAACAD0A6gwAAAcATQBuDAAAAQAQAAAA.',
Ta='Tabtok:BAAALgADCgcJDgAAAA==.Tanalin:BAAALgADCgcJCgABLgAECggJKAALALoWAA==.Tanglebones:BAABLgAECn82AAMeAAYJBw3EEQAJAQZoDAAACgAxAGkMAAAKACIAawwAAAoAIwBqDAAACAAnAGwMAAAGABEA6gwAAAoAHQAeAAYJBw3EEQAJAQZoDAAACAAxAGkMAAAIACIAawwAAAgAIwBqDAAABgAnAGwMAAAEABEA6gwAAAgAHQARAAYJPQd0OADvAAZoDAAAAgAWAGkMAAACABkAawwAAAIADwBqDAAAAgABAGwMAAACAAsA6gwAAAIAEQAAAA==.Tasty:BAAALgAECgEJAQABLgAFFAQJGQAZAOsbAA==.Taukra:BAAALgADCgYJBgAAAA==.',
To='Tore:BAAALgAECgYJDAAAAA==.',
Tr='Trazie:BAAALgAECgYJCQAAAA==.Trenn:BAAALgADCgkJCQABLgAECggJEgAaAAAAAA==.',
Un='Unsocial:BAAALgAECgIJAwAAAA==.',
Ve='Vecna:BAAALgAECgEJAQABLgAECgYJCAAaAAAAAA==.Vermi:BAAALgAECgMJCAAAAA==.',
Wa='Warcloud:BAABLgAECn8aAAIQAAkJEQRKRwAiAQloDAAAAwAWAGkMAAADAAgAawwAAAMACgBqDAAAAwADAGwMAAAEABIAbQwAAAIABADqDAAABQAMAG4MAAACAAQAbwwAAAEACAAQAAkJEQRKRwAiAQloDAAAAwAWAGkMAAADAAgAawwAAAMACgBqDAAAAwADAGwMAAAEABIAbQwAAAIABADqDAAABQAMAG4MAAACAAQAbwwAAAEACAAAAA==.Wartortle:BAABLgAECn8wAAMfAAgJMhvpEADbAQhoDAAACgBKAGkMAAAIAFUAawwAAAgAUQBqDAAACAA0AGwMAAAIAEsAbQwAAAIAKADqDAAAAwBXAG4MAAABACoAHwAICTIb6RAA2wEIaAwAAAkASgBpDAAACABVAGsMAAAIAFEAagwAAAgANABsDAAACABLAG0MAAACACgA6gwAAAMAVwBuDAAAAQAqACAAAQmdCeyAACkAAWgMAAABABgAAAA=.',
Wh='Whack:BAAALgAECgYJBgAAAA==.Whiskeytf:BAAALgAECgYJDwAAAA==.',
Ws='Wsedfgghj:BAAALgAECgcJDAAAAA==.',
Wu='Wu:BAAALgAECgQJBwAAAA==.Wulfgaz:BAAALgAECgcJEAAAAA==.',
Wy='Wyldhart:BAAALgAECgEJAQAAAA==.Wylf:BAAALgADCgcJBwABLgAECgcJEAAaAAAAAA==.',
Xt='Xtheleon:BAAALgADCgYJCgAAAA==.',
Ze='Zenn:BAAALgAECggJEgAAAA==.Zeroomega:BAAALgADCgMJAwAAAA==.Zerø:BAAALgAECgMJBAAAAA==.',
Zi='Zinthous:BAAALgAECgEJAQAAAA==.',
['Äl']='Ältäir:BAABLgAECn8jAAIZAAgJhhjJNQDZAQhoDAAABgBTAGkMAAAFAEcAawwAAAUARQBqDAAABAAxAGwMAAADAEEAbQwAAAIANADqDAAABwBGAG4MAAADACcAGQAICYYYyTUA2QEIaAwAAAYAUwBpDAAABQBHAGsMAAAFAEUAagwAAAQAMQBsDAAAAwBBAG0MAAACADQA6gwAAAcARgBuDAAAAwAnAAAA.',
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
