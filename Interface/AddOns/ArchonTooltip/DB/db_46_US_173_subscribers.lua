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

local lookup = {'DeathKnight-Unholy','Hunter-BeastMastery','Hunter-Survival','Hunter-Marksmanship','Monk-Brewmaster','Paladin-Holy','Paladin-Retribution','Unknown-Unknown','Mage-Frost','Druid-Balance','Shaman-Elemental','Druid-Restoration','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Priest-Shadow','Priest-Holy','Priest-Discipline','Monk-Mistweaver','Monk-Windwalker','DemonHunter-Devourer','DeathKnight-Frost','DemonHunter-Havoc','Warrior-Fury','Evoker-Preservation','DeathKnight-Blood','Druid-Guardian','Shaman-Enhancement','Evoker-Augmentation','Paladin-Protection','Mage-Arcane','Evoker-Devastation',}
local provider = {region='US',realm='Proudmoore',name='US',type='subscribers',zone=46,date='2026-05-01',data={Ad='Adriano:BAEALgAECgYJEwABLgAECgkJGQABAKQfAA==.',
Al='Alaskannatif:BAEBLgAECn8pAAQCAAkJnBZuJgAgAgloDAAABgBHAGkMAAAEAD4AawwAAAQANgBqDAAABQBQAGwMAAAEAEEAbQwAAAUAOQDqDAAABgBHAG4MAAAEABsAbwwAAAMAMwACAAgJdRRuJgAgAghoDAAAAwA3AGkMAAADAD4AawwAAAIANgBqDAAAAwBQAGwMAAADACgAbQwAAAMAOQDqDAAABABEAG4MAAACABsAAwAJCfMU9AkAwgEJaAwAAAMARwBpDAAAAQArAGsMAAABADQAagwAAAIAJQBsDAAAAQBBAG0MAAACADEA6gwAAAIARwBuDAAAAgAXAG8MAAADADMABAABCdEBc5oAGAABawwAAAEABAAAAA==.Allthatjazz:BAECLgAFFH8YAAIFAAYJ7hOwBACJAQZoDAAABgBAAGkMAAAFAFMAawwAAAQAFQBqDAAAAwAQAGwMAAABAB0A6gwAAAUANwAFAAYJ7hOwBACJAQZoDAAABgBAAGkMAAAFAFMAawwAAAQAFQBqDAAAAwAQAGwMAAABAB0A6gwAAAUANwAuAAQKfycAAgUACAkzHVYQAJgCAAUACAkzHVYQAJgCAAAA.',
An='Anakinxd:BAECLgAFFH8KAAMGAAQJAhDUCwAjAQRoDAAABAA+AGkMAAACABAAawwAAAEAIADqDAAAAwAzAAYABAkCENQLACMBBGgMAAADAD4AaQwAAAIAEABrDAAAAQAgAOoMAAADADMABwABCekA3UsANgABaAwAAAEAAgAuAAQKfxkAAwYACAkzIUIKANACAAYACAkzIUIKANACAAcAAQlhBpvaAC4AAAEuAAQKBgkOAAgAAAAA.Anakín:BAEALgAECgYJDgAAAA==.',
Ap='Apsmage:BAECLgAFFH8QAAIJAAUJIh7VCADaAQVoDAAABQBQAGkMAAACAE4AawwAAAMAUgBqDAAAAwBRAOoMAAADAEIACQAFCSIe1QgA2gEFaAwAAAUAUABpDAAAAgBOAGsMAAADAFIAagwAAAMAUQDqDAAAAwBCAC4ABAp/IQACCQAICSkmvgwAXwMACQAICSkmvgwAXwMAAAA=.',
As='Ashla:BAEBLgAECn8hAAIKAAgJHBfVDAC/AQhoDAAABgA9AGkMAAAFAEAAawwAAAUAQwBqDAAAAwAxAGwMAAAEAFEAbQwAAAIAHQDqDAAABgBSAG4MAAACABsACgAICRwX1QwAvwEIaAwAAAYAPQBpDAAABQBAAGsMAAAFAEMAagwAAAMAMQBsDAAABABRAG0MAAACAB0A6gwAAAYAUgBuDAAAAgAbAAAA.',
Ba='Balto:BAEBLgAECn8qAAILAAgJTCBmBAB7AghoDAAABgBhAGkMAAAGAGEAawwAAAYAWgBqDAAABQBZAGwMAAAFAFcAbQwAAAQAQwDqDAAABwBeAG4MAAADACwACwAICUwgZgQAewIIaAwAAAYAYQBpDAAABgBhAGsMAAAGAFoAagwAAAUAWQBsDAAABQBXAG0MAAAEAEMA6gwAAAcAXgBuDAAAAwAsAAAA.Bananahammoc:BAEALgAECgYJDwAAAA==.Baselard:BAEALgAECgYJCgABLgAFFAcJDgAMABQVAA==.',
Be='Bearrypotter:BAEALgAECgUJDgABLgAFFAQJCQABADwhAA==.',
Bi='Bigdorfnrg:BAEALgAECgUJBAABLgAFFAQJBgAJAEwFAA==.',
Bl='Blacksesame:BAEBLgAECn8aAAQEAAgJ0hvkEwCTAghoDAAABwBXAGkMAAADAFoAawwAAAIAOwBqDAAAAgBAAGwMAAACADcAbQwAAAIAKgDqDAAABQBYAG4MAAADAEoABAAICdIb5BMAkwIIaAwAAAUAVwBpDAAAAgBaAGsMAAACADsAagwAAAEAQABsDAAAAQA3AG0MAAABACoA6gwAAAQAWABuDAAAAgBKAAIABQnnEf1DAAgBBWgMAAABABoAaQwAAAEANQBqDAAAAQArAGwMAAABAC8A6gwAAAEANwADAAMJHxQzHADKAANoDAAAAQAxAG0MAAABACcAbgwAAAEAQQABLgAECgkJIwAJABQjAA==.Blisskiller:BAEBLgAECn8XAAIHAAcJ2ROMLwCDAQdoDAAABQAkAGkMAAAEAEgAawwAAAQAQABqDAAAAwA2AGwMAAADADEAbQwAAAEAKgDqDAAAAwAnAAcABwnZE4wvAIMBB2gMAAAFACQAaQwAAAQASABrDAAABABAAGoMAAADADYAbAwAAAMAMQBtDAAAAQAqAOoMAAADACcAAAA=.',
Bu='Bussybolt:BAECLgAFFH8TAAQNAAYJNBGfAgAIAQZoDAAABAAxAGkMAAADACsAawwAAAQALgBqDAAAAwAZAGwMAAABABkA6gwAAAQANwANAAMJGA+fAgAIAQNpDAAAAQArAGsMAAAEAC4AbAwAAAEAGQAOAAMJPxMRIwD4AANoDAAABAAxAGkMAAACACsA6gwAAAQANwAPAAEJAAAtBgBTAAFqDAAAAwAZAC4ABAp/NAAEDgAJCR0jrAUAuAIADgAICdYirAUAuAIADQAGCSAitAgANgIADwABCQAAli0AQwAAAAA=.',
Ca='Caamm:BAECLgAFFH8PAAIQAAYJRyKmAQAHAgZoDAAAAwBgAGkMAAADAFkAawwAAAMAVABqDAAAAwBAAGwMAAABAEQA6gwAAAIAYwAQAAYJRyKmAQAHAgZoDAAAAwBgAGkMAAADAFkAawwAAAMAVABqDAAAAwBAAGwMAAABAEQA6gwAAAIAYwAuAAQKfxsAAhAACAlOJH0DAGYDABAACAlOJH0DAGYDAAAA.Carynna:BAEALgAECgUJCQABLgAECgkJIQARAI8jAA==.Caëlin:BAEALgAECgMJBgAAAA==.',
Ch='Chalse:BAEALgAECgYJBgAAAA==.Charbie:BAEALgADCggJCQABLgAECgYJBgAIAAAAAA==.Charlîe:BAEALgADCgUJBQABLgAECgYJBgAIAAAAAA==.',
Cl='Cloudsire:BAEALgAECgYJBgABLgAFFAEJAQAIAAAAAA==.',
Co='Coralirodeth:BAECLgAFFH8QAAMQAAQJ9BmoBQBwAQRoDAAABQBJAGkMAAAEAD4AawwAAAMAXQDqDAAABAAkABAABAn0GagFAHABBGgMAAAFAEkAaQwAAAMAPgBrDAAAAgBdAOoMAAACACQAEgADCfoI5BIA3wADaQwAAAEABABrDAAAAQAiAOoMAAACAB0ALgAECn8qAAMSAAgJoB5zDQBiAgASAAcJ9CBzDQBiAgAQAAgJxBsrEwBcAgAAAA==.',
Da='Dacotaco:BAEALgAECgcJCwABLgAFFAQJBgAJAEwFAA==.Darthmául:BAECLgAFFH8QAAITAAYJ+Q4+BQCnAQZoDAAAAwA0AGkMAAADACYAawwAAAMANwBqDAAAAwAKAGwMAAABAAQA6gwAAAMAQwATAAYJ+Q4+BQCnAQZoDAAAAwA0AGkMAAADACYAawwAAAMANwBqDAAAAwAKAGwMAAABAAQA6gwAAAMAQwAuAAQKfxcAAxMACAmkGgwYAP8BABMACAmkGgwYAP8BABQAAwmNDR1fAJMAAAEuAAQKBgkOAAgAAAAA.',
Dd='Ddawz:BAEBLgAECn8cAAIHAAgJXiIFCACaAghoDAAABgBYAGkMAAAEAGIAawwAAAQAXQBqDAAAAwBVAGwMAAADAFUAbQwAAAMAVQDqDAAABABVAG4MAAABAE8ABwAICV4iBQgAmgIIaAwAAAYAWABpDAAABABiAGsMAAAEAF0AagwAAAMAVQBsDAAAAwBVAG0MAAADAFUA6gwAAAQAVQBuDAAAAQBPAAAA.',
De='Decobolt:BAEALgADCgkJCQABLgAECgYJEwAIAAAAAA==.Decototem:BAEALgAECgYJEwAAAA==.Deprecated:BAEALgAECgYJEAABLgAFFAgJGQAOAOASAA==.',
Di='Distressful:BAEALgADCgMJAwABLgAECgUJCgAIAAAAAA==.',
Dr='Drogy:BAEALgADCgcJCwAAAA==.',
['Dæ']='Dæy:BAEBLgAECn8hAAIFAAgJjiBnAwCSAghoDAAABgBYAGkMAAAGAFcAawwAAAYAWgBqDAAABABcAGwMAAAEAF4AbQwAAAIASADqDAAABABMAG4MAAABAEkABQAICY4gZwMAkgIIaAwAAAYAWABpDAAABgBXAGsMAAAGAFoAagwAAAQAXABsDAAABABeAG0MAAACAEgA6gwAAAQATABuDAAAAQBJAAAA.',
Ec='Ecksreaper:BAECLgAFFH8WAAIVAAgJ7SNaAADxAghoDAAAAwBgAGkMAAAEAGEAawwAAAQAYQBqDAAAAwBWAGwMAAADAGAAbQwAAAEAUADqDAAAAwBhAG4MAAABAE0AFQAICe0jWgAA8QIIaAwAAAMAYABpDAAABABhAGsMAAAEAGEAagwAAAMAVgBsDAAAAwBgAG0MAAABAFAA6gwAAAMAYQBuDAAAAQBNAC4ABAp/GAACFQAJCVEmGwMAnQMAFQAJCVEmGwMAnQMAAAA=.Ecksripper:BAEALgAECgUJCAABLgAFFAgJFgAVAO0jAA==.',
Ef='Effe:BAEALgAFFAEJAQAAAA==.',
Et='Ethaldra:BAEALgAECgMJAwABLgAECgkJIgAGAB0aAA==.',
Fe='Fenrisyr:BAEBLgAECn8jAAIOAAcJMSAmLwBQAgdoDAAABQBeAGkMAAAFAFoAawwAAAUAXQBqDAAABQA/AGwMAAAFAFIAbQwAAAMALgDqDAAABwBXAA4ABwkxICYvAFACB2gMAAAFAF4AaQwAAAUAWgBrDAAABQBdAGoMAAAFAD8AbAwAAAUAUgBtDAAAAwAuAOoMAAAHAFcAAS4ABAoJCSQAAQDJJAA=.',
Fh='Fhaust:BAEBLgAECn8kAAIBAAgJySRCDgBQAghoDAAABwBjAGkMAAAFAGEAawwAAAUAYwBqDAAABQBgAGwMAAAFAFgAbQwAAAMAWADqDAAABQBgAG4MAAABAFkAAQAICckkQg4AUAIIaAwAAAcAYwBpDAAABQBhAGsMAAAFAGMAagwAAAUAYABsDAAABQBYAG0MAAADAFgA6gwAAAUAYABuDAAAAQBZAAAA.',
['Fê']='Fênris:BAEALgAECgIJAgABLgAECgkJJAABAMkkAA==.',
Ga='Gadlyn:BAEBLgAECn8fAAICAAgJ9g2aHgCoAQhoDAAABgAuAGkMAAAGADYAawwAAAUAJwBqDAAAAwAzAGwMAAADABoAbQwAAAEAFwDqDAAABgArAG4MAAABABEAAgAICfYNmh4AqAEIaAwAAAYALgBpDAAABgA2AGsMAAAFACcAagwAAAMAMwBsDAAAAwAaAG0MAAABABcA6gwAAAYAKwBuDAAAAQARAAAA.Gaurth:BAEALgADCgUJBAAAAA==.',
Gh='Gharcyndr:BAEALgAECgIJAwABLgAECgIJBAAIAAAAAA==.Gharreth:BAEALgAECgIJBAAAAA==.',
Gi='Gigagirthy:BAEBLgAECn8aAAMBAAkJXB8EHgDTAQloDAAAAwBIAGkMAAADAE8AawwAAAMAUwBqDAAAAwBVAGwMAAAEAFAAbQwAAAMAWgDqDAAABABQAG4MAAACAFIAbwwAAAEARwABAAkJaR4EHgDTAQloDAAAAgA1AGkMAAACAE8AawwAAAIAUwBqDAAAAwBVAGwMAAADAFAAbQwAAAIAWgDqDAAAAwBQAG4MAAACAFIAbwwAAAEARwAWAAYJGhUuAwCkAQZoDAAAAQBIAGkMAAABADQAawwAAAEAQwBsDAAAAQA+AG0MAAABABIA6gwAAAEAMgAAAA==.Girthcat:BAEALgAECgYJDgABLgAECgkJGgABAFwfAA==.',
Gl='Glaivejazzy:BAEALgAECgYJDgABLgAFFAYJGAAFAO4TAA==.',
Go='Goodbearry:BAEALgAECgUJDAABLgAFFAQJCQABADwhAA==.',
Gr='Grizzlygerm:BAEALgAECgUJBQAAAA==.',
Gu='Gunnther:BAEALgAECgIJBAABLgAECgIJBAAIAAAAAA==.',
He='Heimdaller:BAEALgAECgYJCwAAAA==.Heimerdonker:BAEALgADCgcJBwABLgAFFAQJBgAJAEwFAA==.Heimermagic:BAECLgAFFH8GAAIJAAQJTAWOMQAGAQRoDAAAAgAKAGkMAAACAAAAawwAAAEACgDqDAAAAQAgAAkABAlMBY4xAAYBBGgMAAACAAoAaQwAAAIAAABrDAAAAQAKAOoMAAABACAALgAECn8uAAIJAAgJuxe3UABFAgAJAAgJuxe3UABFAgAAAA==.Hewikan:BAEALgAECgUJCQAAAA==.',
Hu='Huddie:BAEALgAECgYJEgAAAA==.',
Ic='Icesniper:BAEALgAECgYJEwAAAA==.',
Im='Immunize:BAEALgADCgEJAQABLgADCgYJCwAIAAAAAA==.',
Ja='Jadeiana:BAEALgAECgYJDQAAAA==.Jagö:BAEALgAECgQJBwAAAA==.Jazzytwo:BAEALgAECgYJDAABLgAFFAYJGAAFAO4TAA==.',
Ju='Justhunt:BAECLgAFFH8NAAICAAQJ4xRoCwBWAQRoDAAABABLAGkMAAACAEEAawwAAAMAOADqDAAABAAQAAIABAnjFGgLAFYBBGgMAAAEAEsAaQwAAAIAQQBrDAAAAwA4AOoMAAAEABAALgAECn8kAAMCAAgJ2x3/DQDNAgACAAgJ2x3/DQDNAgAEAAEJQAYCkQApAAAAAA==.',
Ka='Kahrhen:BAEALgADCgYJBgABLgAECggJIQAKABwXAA==.Kalazar:BAECLgAFFH8YAAMEAAgJ7RvPAgAqAghoDAAABQBRAGkMAAADAF0AawwAAAMAWgBqDAAABAA4AGwMAAADADgAbQwAAAEAKwDqDAAABABAAG4MAAABAEcABAAICaAazwIAKgIIaAwAAAUAUQBpDAAAAQBGAGsMAAADAFoAagwAAAQAOABsDAAAAwA4AG0MAAABACsA6gwAAAIAQABuDAAAAQBHAAIAAgloFT4VALAAAmkMAAACAF0A6gwAAAIAEAAuAAQKfyUAAwIACQm0JXYAANIDAAIACQl1JHYAANIDAAQACAleJUAFAEkDAAAA.',
Kh='Khuuthun:BAEALgAECgUJCAABLgAFFAcJFgAOAC4hAA==.',
Ko='Koakuma:BAEALgAFFAEJAQABLgAFFAMJCwASAJ4WAA==.Konstabeam:BAEBLgAECn8jAAMVAAgJ8RWZJQBTAQhoDAAABQA5AGkMAAAFAEIAawwAAAQAMwBqDAAABgBPAGwMAAAGADcAbQwAAAMAOADqDAAABQA2AG4MAAABADIAFQAHCUwWmSUAUwEHaAwAAAUAOQBpDAAABABCAGsMAAAEADMAagwAAAUATwBsDAAABgA3AG0MAAADADgA6gwAAAUANgAXAAMJUxTRLQA/AANpDAAAAQA1AGoMAAABADEAbgwAAAEAMgAAAA==.Korvast:BAEBLgAECn9CAAIYAAgJ5CPQAQDcAghoDAAADgBiAGkMAAAMAGEAawwAAAsAXQBqDAAABwBVAGwMAAAHAF4AbQwAAAQAVQDqDAAACABTAG4MAAADAFsAGAAICeQj0AEA3AIIaAwAAA4AYgBpDAAADABhAGsMAAALAF0AagwAAAcAVQBsDAAABwBeAG0MAAAEAFUA6gwAAAgAUwBuDAAAAwBbAAAA.',
La='Landinoo:BAEALgADCggJCwABLgAECggJHAAHAF4iAA==.',
Le='Lenorlée:BAEBLgAECn8ZAAIJAAgJkh2gEwA9AghoDAAABQBdAGkMAAAEAFUAawwAAAQAWgBqDAAAAwBdAGwMAAADAF4AbQwAAAEABwDqDAAABABhAG4MAAABAD0ACQAICZIdoBMAPQIIaAwAAAUAXQBpDAAABABVAGsMAAAEAFoAagwAAAMAXQBsDAAAAwBeAG0MAAABAAcA6gwAAAQAYQBuDAAAAQA9AAAA.',
Lu='Lucielsiais:BAEALgADCgMJAwABLgAECgkJKQACAJwWAA==.',
Ly='Lynkalla:BAEALgADCgMJAwABLgAECgYJGQAZAJ0SAA==.Lynmakara:BAEBLgAECn8ZAAIZAAYJnRIOCwBgAQZoDAAABQAgAGkMAAAFAEQAawwAAAUAIQBqDAAABAAmAGwMAAADACoA6gwAAAMARQAZAAYJnRIOCwBgAQZoDAAABQAgAGkMAAAFAEQAawwAAAUAIQBqDAAABAAmAGwMAAADACoA6gwAAAMARQAAAA==.',
Me='Meddah:BAEBLgAECn8vAAIMAAgJUho6CwBVAghoDAAABwBDAGkMAAAGAEUAawwAAAcASQBqDAAABgAtAGwMAAAGAEgAbQwAAAUARgDqDAAABwBHAG4MAAADAEQADAAICVIaOgsAVQIIaAwAAAcAQwBpDAAABgBFAGsMAAAHAEkAagwAAAYALQBsDAAABgBIAG0MAAAFAEYA6gwAAAcARwBuDAAAAwBEAAAA.',
Mo='Moltremix:BAEBLgAECn8UAAIWAAcJrB5CAwBgAgdoDAAAAwBTAGkMAAADAEoAawwAAAMAUwBqDAAAAgBHAGwMAAACAFQAbQwAAAIAOQDqDAAABQBWABYABwmsHkIDAGACB2gMAAADAFMAaQwAAAMASgBrDAAAAwBTAGoMAAACAEcAbAwAAAIAVABtDAAAAgA5AOoMAAAFAFYAAS4ABRQFCRQAFgAoGgA=.Moltøn:BAECLgAFFH8UAAQWAAUJKBp0AABlAQVoDAAABQBNAGkMAAAFAEwAawwAAAMAEwBqDAAAAgA0AOoMAAAFAF4AFgAECTIYdAAAZQEEaAwAAAMAPABpDAAAAwBMAGsMAAABABMA6gwAAAMAWwABAAQJbxaOGQBPAQRoDAAAAgBNAGkMAAACACYAawwAAAIAEgDqDAAAAgBeABoAAQkAAOgfAAAAAWoMAAACADQALgAECn8lAAMWAAkJgCS3AAA3AwAWAAgJsyW3AAA3AwABAAIJJx7IeQCpAAAAAA==.Moodk:BAEALgAECgUJBQABLgAFFAUJEgAFAI8hAA==.Moosshu:BAECLgAFFH8SAAIFAAUJjyFQBQB9AQVoDAAABQBgAGkMAAAFAFUAawwAAAMAUgBqDAAAAQBLAOoMAAAEAE8ABQAFCY8hUAUAfQEFaAwAAAUAYABpDAAABQBVAGsMAAADAFIAagwAAAEASwDqDAAABABPAC4ABAp/JQACBQAICeIjhgYAHwMABQAICeIjhgYAHwMAAAA=.Morsaudet:BAEBLgAECn8ZAAIBAAgJpB+dIgC1AghoDAAABQBaAGkMAAAEAGIAawwAAAMAXABqDAAAAwBWAGwMAAADAF0AbQwAAAMAHwDqDAAAAwBeAG4MAAABAEIAAQAICaQfnSIAtQIIaAwAAAUAWgBpDAAABABiAGsMAAADAFwAagwAAAMAVgBsDAAAAwBdAG0MAAADAB8A6gwAAAMAXgBuDAAAAQBCAAAA.',
My='Mysterice:BAEALgAECgUJBQABLgAECgYJEwAIAAAAAA==.',
Na='Navelty:BAEALgADCgkJCQAAAA==.',
No='Nofatherpls:BAEALgAECgMJAwABLgAECgkJEQAIAAAAAA==.Nolazax:BAECLgAFFH8UAAQMAAYJzBJsBQCEAQZoDAAABgA7AGkMAAAEABsAawwAAAMAOgBqDAAAAgAlAGwMAAABACMA6gwAAAQARgAMAAYJzBJsBQCEAQZoDAAABAA7AGkMAAADABsAawwAAAIAOgBqDAAAAQAlAGwMAAABACMA6gwAAAMARgAKAAUJww9KCwA7AQVoDAAAAQBMAGkMAAABACEAawwAAAEAFgBqDAAAAQAPAOoMAAABAB0AGwABCS8Q/gYAOAABaAwAAAEAKQAuAAQKfx0AAgwACAnKIiwIAAoDAAwACAnKIiwIAAoDAAEuAAUUAgkHABMAvx8A.',
Ny='Nyrae:BAEBLgAECn8YAAMQAAcJuxksHQDyAQdoDAAABQBLAGkMAAAEAE0AawwAAAQATwBqDAAAAwBSAGwMAAACADUAbQwAAAEALQDqDAAABQBAABAABglXGywdAPIBBmgMAAADAEsAaQwAAAMATQBrDAAAAwBPAGoMAAADAFIAbAwAAAIANQDqDAAAAgBAABIABQmxI3EhAIgBBWgMAAACAGEAaQwAAAEAXgBrDAAAAQBQAG0MAAABAFkA6gwAAAMAXQAAAA==.',
Om='Omgdagron:BAEALgADCgIJAgABLgAECgkJIAAcAEEWAA==.Omghammer:BAEALgAECggJDwABLgAECgkJIAAcAEEWAA==.Omgtotem:BAEBLgAECn8gAAIcAAkJQRY5AgBVAgloDAAABgBOAGkMAAAGAD8AawwAAAYASgBqDAAAAwBGAGwMAAADAD0AbQwAAAIANADqDAAAAwA6AG4MAAACAB8AbwwAAAEAIgAcAAkJQRY5AgBVAgloDAAABgBOAGkMAAAGAD8AawwAAAYASgBqDAAAAwBGAGwMAAADAD0AbQwAAAIANADqDAAAAwA6AG4MAAACAB8AbwwAAAEAIgAAAA==.',
['Oî']='Oî:BAEBLgAECn8YAAMdAAYJcgjxIwDmAAZoDAAABQAeAGkMAAAFABMAawwAAAUAHABqDAAABAAcAGwMAAACAA0A6gwAAAMADwAdAAYJcgjxIwDmAAZoDAAAAwAeAGkMAAADABMAawwAAAMAHABqDAAAAwAcAGwMAAABAA0A6gwAAAMADwAZAAUJ/gmrEgDQAAVoDAAAAgALAGkMAAACABYAawwAAAIAGABqDAAAAQAlAGwMAAABACAAAAA=.',
Pa='Patycakes:BAECLgAFFH8IAAIeAAMJVRCmAwDGAANoDAAABABLAGkMAAADAA0A6gwAAAEAJAAeAAMJVRCmAwDGAANoDAAABABLAGkMAAADAA0A6gwAAAEAJAAuAAQKfy0AAh4ACAlpHL4KACECAB4ACAlpHL4KACECAAAA.Patygrr:BAEALgAECgkJCQABLgAFFAMJCAAeAFUQAA==.',
Po='Poazfk:BAEALgAECgYJCgABLgAECgkJEQAIAAAAAA==.',
Pr='Praeset:BAEALgADCgYJCwAAAA==.Priest:BAEBLgAECn8jAAQRAAgJmRsHFAA/AghoDAAABgBWAGkMAAAGAFUAawwAAAUAWABqDAAABQBZAGwMAAAEAFoAbQwAAAIAJADqDAAABQBMAG4MAAACAAwAEQAHCdseBxQAPwIHaAwAAAEAVgBpDAAAAgBVAGsMAAACAFgAagwAAAMAWQBsDAAAAwBaAG0MAAACACQA6gwAAAMATAASAAcJAQyvFwAvAQdoDAAABAAgAGkMAAADAC4AawwAAAIAGgBqDAAAAQAbAGwMAAABABoA6gwAAAIAKwBuDAAAAQAMABAABQn/CMYkANUABWgMAAABABIAaQwAAAEAGwBrDAAAAQAZAGoMAAABADAAbgwAAAEAFQAAAA==.',
Ps='Psyká:BAEBLgAECn8YAAIfAAYJCiOJAwAyAgZoDAAABQBfAGkMAAAFAGAAawwAAAQAWwBqDAAAAwBaAGwMAAADAFEA6gwAAAQAUwAfAAYJCiOJAwAyAgZoDAAABQBfAGkMAAAFAGAAawwAAAQAWwBqDAAAAwBaAGwMAAADAFEA6gwAAAQAUwAAAA==.',
Ra='Razska:BAEBLgAECn8uAAMQAAgJdhmYBwANAghoDAAABwBQAGkMAAAGAEUAawwAAAcAUgBqDAAABwBLAGwMAAAGAEgAbQwAAAQAMQDqDAAABwBPAG4MAAACABYAEAAICXYZmAcADQIIaAwAAAYAUABpDAAABgBFAGsMAAAHAFIAagwAAAYASwBsDAAABgBIAG0MAAACADEA6gwAAAcATwBuDAAAAgAWABEAAwlXCxBnAJEAA2gMAAABAA4AagwAAAEALABtDAAAAgAbAAAA.',
Ri='Rivén:BAEALgAECggJCAAAAA==.',
Se='Senapim:BAECLgAFFH8PAAIJAAQJ4CE/EgB2AQRoDAAABABfAGkMAAAEAFQAawwAAAMASwDqDAAABABbAAkABAngIT8SAHYBBGgMAAAEAF8AaQwAAAQAVABrDAAAAwBLAOoMAAAEAFsALgAECn8oAAIJAAgJpCSyDwBKAwAJAAgJpCSyDwBKAwAAAA==.Senapimonk:BAEALgAFFAIJAgABLgAFFAQJDwAJAOAhAA==.',
Sh='Shelannigans:BAEBLgAECn8hAAIRAAkJjyO6AACYAwloDAAABQBUAGkMAAAFAGEAawwAAAQAXwBqDAAABABhAGwMAAADAGMAbQwAAAMAYADqDAAABQBgAG4MAAACAFwAbwwAAAIAPAARAAkJjyO6AACYAwloDAAABQBUAGkMAAAFAGEAawwAAAQAXwBqDAAABABhAGwMAAADAGMAbQwAAAMAYADqDAAABQBgAG4MAAACAFwAbwwAAAIAPAAAAA==.Shuvi:BAEALgAECgcJCwABLgAFFAYJEgATABwZAA==.',
Sk='Skywardwings:BAEALgAECgUJBwABLgAECgUJCgAIAAAAAA==.',
Sm='Smallbuff:BAECLgAFFH8QAAIdAAUJBh4YCAB0AQVoDAAABQBYAGkMAAADADwAawwAAAMAQwBqDAAAAQBXAOoMAAAEAFoAHQAFCQYeGAgAdAEFaAwAAAUAWABpDAAAAwA8AGsMAAADAEMAagwAAAEAVwDqDAAABABaAC4ABAp/HQADHQAHCawi/xwA3wEAHQAHCZ4i/xwA3wEAIAAECSQNyCwAtQAAAAA=.Smallsha:BAEALgAFFAEJAQABLgAFFAUJEAAdAAYeAA==.',
So='Solipriest:BAECLgAFFH8LAAISAAMJnhYIEAAJAQNoDAAABQBUAGkMAAAEADkA6gwAAAIAHgASAAMJnhYIEAAJAQNoDAAABQBUAGkMAAAEADkA6gwAAAIAHgAuAAQKfygAAxIACQm4IUYBADkDABIACQm4IUYBADkDABEAAQk+DzSCAC8AAAAA.',
Sp='Spankies:BAEALgADCgcJBwABLgAECgkJKQACAJwWAA==.',
St='Stebmage:BAEALgAECgUJBQABLgAFFAcJGQALAM8ZAA==.Stebpaladin:BAEALgAECgEJAQABLgAFFAcJGQALAM8ZAA==.Stebrogue:BAEALgADCgMJAwABLgAFFAcJGQALAM8ZAA==.Stebshaman:BAECLgAFFH8ZAAILAAcJzxmuAAApAgdoDAAABgBYAGkMAAAFAF0AawwAAAQASABqDAAABABdAGwMAAABAA8AbQwAAAEANQDqDAAABABIAAsABwnPGa4AACkCB2gMAAAGAFgAaQwAAAUAXQBrDAAABABIAGoMAAAEAF0AbAwAAAEADwBtDAAAAQA1AOoMAAAEAEgALgAECn8iAAILAAkJKR9cBgAuAwALAAkJKR9cBgAuAwAAAA==.',
Su='Sullet:BAEALgAECgYJBwAAAA==.',
Sy='Sylyphe:BAECLgAFFH8SAAITAAYJHBlhBACfAQZoDAAABABFAGkMAAACAEYAawwAAAMARABqDAAAAwApAGwMAAABAEkA6gwAAAUAPgATAAYJHBlhBACfAQZoDAAABABFAGkMAAACAEYAawwAAAMARABqDAAAAwApAGwMAAABAEkA6gwAAAUAPgAuAAQKfxQAAhMACAnFG+YNAHcCABMACAnFG+YNAHcCAAAA.',
Te='Tengen:BAEALgADCgEJAQAAAA==.',
Ti='Tierán:BAEBLgAECn8nAAQCAAkJnyVjAQAfAwloDAAABgBiAGkMAAAGAGIAawwAAAUAYwBqDAAABQBRAGwMAAADAFYAbQwAAAMAYwDqDAAABgBhAG4MAAAEAF8AbwwAAAEAXwACAAkJnyVjAQAfAwloDAAAAgBiAGkMAAACAGIAawwAAAIAYwBqDAAAAwBRAGwMAAABAFYAbQwAAAMAYwDqDAAAAgBhAG4MAAADAF8AbwwAAAEAXwADAAYJEyIABwD7AQZoDAAAAgBTAGkMAAACAFYAawwAAAIAYABqDAAAAQBCAOoMAAABAF4AbgwAAAEASgAEAAYJNBoWMACyAQZoDAAAAgBbAGkMAAACAFkAawwAAAEABwBqDAAAAQAaAGwMAAACAEEA6gwAAAMAUAAAAA==.',
To='Tobis:BAEALgAECgkJEQAAAA==.Toonces:BAEALgAECgEJAQABLgAECggJLgAQAHYZAA==.',
Tr='Trem:BAEALgAECggJEwABLgAFFAcJFgAOAC4hAA==.Tremens:BAECLgAFFH8WAAQOAAcJLiF4AAB0AgdoDAAABABjAGkMAAAEAFgAawwAAAMAZABqDAAAAgBXAGwMAAADAEYAbQwAAAEARgDqDAAABQBPAA4ABglMIngAAHQCBmgMAAAEAGMAaQwAAAQAWABrDAAAAgBkAGoMAAABAFcAbAwAAAMARgDqDAAABQBPAA0AAgmyEjMKALcAAmsMAAABABkAbQwAAAEARgAPAAEJAACVBwA+AAFqDAAAAQADAC4ABAp/HwACDgAJCT8mOwAAhwMADgAJCT8mOwAAhwMAAAA=.',
Tw='Twelvedread:BAEALgAECgQJBAABLgAECggJJAAHAN4UAA==.Twlvepeers:BAEBLgAECn8kAAMHAAgJ3hT3MQB6AQhoDAAABgA/AGkMAAAFAEYAawwAAAUAQQBqDAAABQAnAGwMAAAEAFEAbQwAAAIAGADqDAAABgA0AG4MAAADAA8ABwAHCQwT9zEAegEHaAwAAAYAPwBpDAAABQBGAGsMAAAFAEEAagwAAAUAJwBtDAAAAgAYAOoMAAAGADQAbgwAAAMADwAeAAEJyx+LIABbAAFsDAAABABRAAAA.',
Ty='Typhoidbeary:BAECLgAFFH8JAAMBAAQJPCEvEQBqAQRoDAAAAwBbAGkMAAADAF4AawwAAAEAQADqDAAAAgBZAAEABAk8IS8RAGoBBGgMAAADAFsAaQwAAAMAXgBrDAAAAQBAAOoMAAABAFkAFgABCWcM5wYAUAAB6gwAAAEAHwAuAAQKfyIAAgEACQlvJOASAAoDAAEACQlvJOASAAoDAAAA.',
['Tè']='Tèren:BAEALgADCgcJEAAAAA==.',
Un='Unobservant:BAEALgADCgMJAwABLgAECgUJCgAIAAAAAA==.',
Ve='Ventres:BAEALgADCgMJAwABLgAECggJIQAKABwXAA==.',
Vi='Virtuel:BAEALgAECgUJCAAAAA==.',
Xa='Xalitoes:BAEBLgAECn8YAAIFAAgJhCP2CgDcAghoDAAAAwBgAGkMAAAEAFwAawwAAAQAVABqDAAAAgBVAGwMAAACAFYAbQwAAAIAXQDqDAAABQBbAG4MAAACAFsABQAICYQj9goA3AIIaAwAAAMAYABpDAAABABcAGsMAAAEAFQAagwAAAIAVQBsDAAAAgBWAG0MAAACAF0A6gwAAAUAWwBuDAAAAgBbAAAA.',
Xe='Xelaym:BAEALgAECgMJBAAAAA==.',
Xp='Xplosives:BAEALgAECgUJCgAAAA==.',
Za='Zannarossa:BAEBLgAECn8aAAMMAAgJ2x6OBQDGAghoDAAABABFAGkMAAAEAEYAawwAAAQAUgBqDAAABABbAGwMAAADAFcAbQwAAAIARADqDAAABABNAG4MAAABAFQADAAICdsejgUAxgIIaAwAAAMARQBpDAAAAwBGAGsMAAADAFIAagwAAAMAWwBsDAAAAgBXAG0MAAABAEQA6gwAAAIATQBuDAAAAQBUAAoABwkmBR8iAO4AB2gMAAABAAgAaQwAAAEACABrDAAAAQAOAGoMAAABABQAbAwAAAEADgBtDAAAAQAJAOoMAAACABcAAS4ABAoJCRkAAQCkHwA=.Zayvointh:BAEALgAECgYJDwABLgAFFAQJEAAQAPQZAA==.',
['ßr']='ßrøna:BAEALgADCgEJBgAAAA==.',
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
