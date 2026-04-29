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

local lookup = {'DeathKnight-Unholy','Hunter-BeastMastery','Hunter-Survival','Hunter-Marksmanship','Monk-Brewmaster','Paladin-Holy','Paladin-Retribution','Unknown-Unknown','Mage-Frost','Druid-Balance','Shaman-Elemental','Druid-Restoration','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Priest-Shadow','Priest-Holy','Priest-Discipline','Monk-Mistweaver','Monk-Windwalker','DemonHunter-Devourer','DeathKnight-Frost','DemonHunter-Havoc','Warrior-Fury','DeathKnight-Blood','Druid-Guardian','Shaman-Enhancement','Paladin-Protection',}
local provider = {region='US',realm='Proudmoore',name='US',type='subscribers',zone=46,date='2026-04-28',data={Ad='Adriano:BAEALgAECgYJEwABLgAECgkJGQABAKQfAA==.',
Al='Alaskannatif:BAEBLgAECn8iAAQCAAkJZBNsJgAgAgloDAAABQA/AGkMAAAEAD4AawwAAAQANgBqDAAABABQAGwMAAADACgAbQwAAAQAOQDqDAAABQBHAG4MAAADABsAbwwAAAIAEwACAAgJdRRsJgAgAghoDAAAAwA3AGkMAAADAD4AawwAAAIANgBqDAAAAwBQAGwMAAADACgAbQwAAAMAOQDqDAAABABEAG4MAAACABsAAwAICQoQkxEA/wAIaAwAAAIAPwBpDAAAAQArAGsMAAABADQAagwAAAEACABtDAAAAQAkAOoMAAABAEcAbgwAAAEAAABvDAAAAgATAAQAAQnRAWyaABgAAWsMAAABAAQAAAA=.Allthatjazz:BAECLgAFFH8SAAIFAAUJVRH6BwBSAQVoDAAABQA4AGkMAAAEAEQAawwAAAMAFQBqDAAAAgAEAOoMAAAEAB8ABQAFCVUR+gcAUgEFaAwAAAUAOABpDAAABABEAGsMAAADABUAagwAAAIABADqDAAABAAfAC4ABAp/JwACBQAICTMdUhAAmAIABQAICTMdUhAAmAIAAAA=.',
An='Anakinxd:BAECLgAFFH8KAAMGAAQJAhDKCwAjAQRoDAAABAA+AGkMAAACABAAawwAAAEAIADqDAAAAwAzAAYABAkCEMoLACMBBGgMAAADAD4AaQwAAAIAEABrDAAAAQAgAOoMAAADADMABwABCekAGj0AOAABaAwAAAEAAgAuAAQKfxkAAwYACAkzIUIKANACAAYACAkzIUIKANACAAcAAQlhBu+1AC4AAAEuAAQKBgkOAAgAAAAA.Anakín:BAEALgAECgYJDgAAAA==.',
Ap='Apsmage:BAECLgAFFH8QAAIJAAUJIh7PCADaAQVoDAAABQBQAGkMAAACAE4AawwAAAMAUgBqDAAAAwBRAOoMAAADAEIACQAFCSIezwgA2gEFaAwAAAUAUABpDAAAAgBOAGsMAAADAFIAagwAAAMAUQDqDAAAAwBCAC4ABAp/IQACCQAICSkmuAwAXwMACQAICSkmuAwAXwMAAAA=.',
As='Ashla:BAEBLgAECn8gAAIKAAgJnRbJCgCmAQhoDAAABgA9AGkMAAAFAEAAawwAAAUAQwBqDAAAAwAxAGwMAAAEAFEAbQwAAAIAHQDqDAAABQBJAG4MAAACABsACgAICZ0WyQoApgEIaAwAAAYAPQBpDAAABQBAAGsMAAAFAEMAagwAAAMAMQBsDAAABABRAG0MAAACAB0A6gwAAAUASQBuDAAAAgAbAAAA.',
Ba='Balto:BAEBLgAECn8pAAILAAgJ6h8oAwB4AghoDAAABgBhAGkMAAAGAGEAawwAAAYAWgBqDAAABQBZAGwMAAAFAFcAbQwAAAQAQwDqDAAABgBXAG4MAAADACwACwAICeofKAMAeAIIaAwAAAYAYQBpDAAABgBhAGsMAAAGAFoAagwAAAUAWQBsDAAABQBXAG0MAAAEAEMA6gwAAAYAVwBuDAAAAwAsAAAA.Bananahammoc:BAEALgAECgYJDwAAAA==.Baselard:BAEALgAECgYJCgABLgAFFAYJDAAMAMsXAA==.',
Be='Bearrypotter:BAEALgAECgUJDgABLgAFFAMJBgABAK8WAA==.',
Bi='Bigdorfnrg:BAEALgAECgUJBAABLgAFFAQJBgAJAEwFAA==.',
Bl='Blacksesame:BAEBLgAECn8aAAQEAAgJ0hvcEwCTAghoDAAABwBXAGkMAAADAFoAawwAAAIAOwBqDAAAAgBAAGwMAAACADcAbQwAAAIAKgDqDAAABQBYAG4MAAADAEoABAAICdIb3BMAkwIIaAwAAAUAVwBpDAAAAgBaAGsMAAACADsAagwAAAEAQABsDAAAAQA3AG0MAAABACoA6gwAAAQAWABuDAAAAgBKAAIABQnnEZo0ABQBBWgMAAABABoAaQwAAAEANQBqDAAAAQArAGwMAAABAC8A6gwAAAEANwADAAMJHxQwFQDPAANoDAAAAQAxAG0MAAABACcAbgwAAAEAQQABLgAECgkJIwAJABQjAA==.Blisskiller:BAEALgAECgYJEAAAAA==.',
Bu='Bussybolt:BAECLgAFFH8TAAQNAAYJNBG3AQAOAQZoDAAABAAxAGkMAAADACsAawwAAAQALgBqDAAAAwAZAGwMAAABABkA6gwAAAQANwANAAMJGA+3AQAOAQNpDAAAAQArAGsMAAAEAC4AbAwAAAEAGQAOAAMJPxMLIwD4AANoDAAABAAxAGkMAAACACsA6gwAAAQANwAPAAEJAAArBgBTAAFqDAAAAwAZAC4ABAp/NAAEDgAJCR0jhwMAvwIADgAICdYihwMAvwIADQAGCSAisQgANgIADwABCQAAky0AQwAAAAA=.',
Ca='Caamm:BAECLgAFFH8PAAIQAAYJRyKlAQAHAgZoDAAAAwBgAGkMAAADAFkAawwAAAMAVABqDAAAAwBAAGwMAAABAEQA6gwAAAIAYwAQAAYJRyKlAQAHAgZoDAAAAwBgAGkMAAADAFkAawwAAAMAVABqDAAAAwBAAGwMAAABAEQA6gwAAAIAYwAuAAQKfxsAAhAACAlOJHoDAGYDABAACAlOJHoDAGYDAAAA.Carynna:BAEALgAECgUJCQABLgAECgkJIQARAI8jAA==.Caëlin:BAEALgAECgMJBgAAAA==.',
Ch='Chalse:BAEALgAECgYJBgAAAA==.Charbie:BAEALgADCggJCQABLgAECgYJBgAIAAAAAA==.Charlîe:BAEALgADCgUJBQABLgAECgYJBgAIAAAAAA==.',
Cl='Cloudsire:BAEALgAECgYJBgABLgAFFAEJAQAIAAAAAA==.',
Co='Coralirodeth:BAECLgAFFH8MAAMQAAQJ9BmkBQBwAQRoDAAABABJAGkMAAADAD4AawwAAAIAXQDqDAAAAwAkABAABAn0GaQFAHABBGgMAAAEAEkAaQwAAAMAPgBrDAAAAQBdAOoMAAACACQAEgACCY4KzBEAngACawwAAAEAIgDqDAAAAQATAC4ABAp/IwADEgAICUkecQ0AYgIAEgAHCZAgcQ0AYgIAEAAICWcaKRMAXAIAAAA=.',
Da='Dacotaco:BAEALgAECgcJBgABLgAFFAQJBgAJAEwFAA==.Darthmául:BAECLgAFFH8KAAITAAUJWw3yBQBvAQVoDAAAAgA0AGkMAAACABkAawwAAAIANwBqDAAAAgAKAOoMAAACABoAEwAFCVsN8gUAbwEFaAwAAAIANABpDAAAAgAZAGsMAAACADcAagwAAAIACgDqDAAAAgAaAC4ABAp/FwADEwAICaQa0hcAAgIAEwAICaQa0hcAAgIAFAADCY0NF18AkwAAAS4ABAoGCQ4ACAAAAAA=.',
Dd='Ddawz:BAEBLgAECn8VAAIHAAgJPiEKJgCOAghoDAAABQBYAGkMAAADAGIAawwAAAMAXQBqDAAAAgBDAGwMAAACAFUAbQwAAAIAQQDqDAAAAwBVAG4MAAABAE8ABwAICT4hCiYAjgIIaAwAAAUAWABpDAAAAwBiAGsMAAADAF0AagwAAAIAQwBsDAAAAgBVAG0MAAACAEEA6gwAAAMAVQBuDAAAAQBPAAAA.',
De='Decobolt:BAEALgADCgkJCQABLgAECgYJEwAIAAAAAA==.Decototem:BAEALgAECgYJEwAAAA==.Deprecated:BAEALgAECgYJEAABLgAFFAcJEwAOAD8TAA==.',
Di='Distressful:BAEALgADCgMJAwABLgAECgUJCgAIAAAAAA==.',
Dr='Drogy:BAEALgADCgcJCwAAAA==.',
['Dæ']='Dæy:BAEBLgAECn8aAAIFAAgJNR+dAwBbAghoDAAABQBRAGkMAAAFAFcAawwAAAUAWgBqDAAAAwBaAGwMAAADAFUAbQwAAAEAPwDqDAAAAwBMAG4MAAABAEkABQAICTUfnQMAWwIIaAwAAAUAUQBpDAAABQBXAGsMAAAFAFoAagwAAAMAWgBsDAAAAwBVAG0MAAABAD8A6gwAAAMATABuDAAAAQBJAAAA.',
Ec='Ecksreaper:BAECLgAFFH8bAAIVAAgJBCRZAADxAghoDAAABABgAGkMAAAFAGEAawwAAAUAYgBqDAAABABgAGwMAAADAGAAbQwAAAEAUADqDAAABABhAG4MAAABAE0AFQAICQQkWQAA8QIIaAwAAAQAYABpDAAABQBhAGsMAAAFAGIAagwAAAQAYABsDAAAAwBgAG0MAAABAFAA6gwAAAQAYQBuDAAAAQBNAC4ABAp/GAACFQAJCVEmGAMAnQMAFQAJCVEmGAMAnQMAAAA=.Ecksripper:BAEALgAECgUJCAABLgAFFAgJGwAVAAQkAA==.',
Ef='Effe:BAEALgAFFAEJAQAAAA==.',
Et='Ethaldra:BAEALgAECgMJAwAAAA==.',
Fe='Fenrisyr:BAEBLgAECn8jAAIOAAcJMSAbLwBQAgdoDAAABQBeAGkMAAAFAFoAawwAAAUAXQBqDAAABQA/AGwMAAAFAFIAbQwAAAMALgDqDAAABwBXAA4ABwkxIBsvAFACB2gMAAAFAF4AaQwAAAUAWgBrDAAABQBdAGoMAAAFAD8AbAwAAAUAUgBtDAAAAwAuAOoMAAAHAFcAAS4ABAoJCSQAAQDJJAA=.',
Fh='Fhaust:BAEBLgAECn8kAAIBAAgJySSGBgB+AghoDAAABwBjAGkMAAAFAGEAawwAAAUAYwBqDAAABQBgAGwMAAAFAFgAbQwAAAMAWADqDAAABQBgAG4MAAABAFkAAQAICckkhgYAfgIIaAwAAAcAYwBpDAAABQBhAGsMAAAFAGMAagwAAAUAYABsDAAABQBYAG0MAAADAFgA6gwAAAUAYABuDAAAAQBZAAAA.',
['Fê']='Fênris:BAEALgAECgIJAgABLgAECgkJJAABAMkkAA==.',
Ga='Gadlyn:BAEBLgAECn8ZAAICAAgJGg1YIQBsAQhoDAAABQAnAGkMAAAFADYAawwAAAQAJwBqDAAAAgAfAGwMAAACABYAbQwAAAEAFwDqDAAABQAnAG4MAAABABEAAgAICRoNWCEAbAEIaAwAAAUAJwBpDAAABQA2AGsMAAAEACcAagwAAAIAHwBsDAAAAgAWAG0MAAABABcA6gwAAAUAJwBuDAAAAQARAAAA.Gaurth:BAEALgADCgUJBAAAAA==.',
Gh='Gharcyndr:BAEALgAECgIJAgAAAA==.Gharreth:BAEALgAECgIJAgABLgAECgIJAgAIAAAAAA==.',
Gi='Gigagirthy:BAEBLgAECn8VAAMWAAgJvRd0AgCqAQhoDAAAAwBIAGkMAAADAE8AawwAAAMAUwBqDAAAAwBVAGwMAAADAEMAbQwAAAIAEgDqDAAAAwA+AG4MAAABACkAAQAICT8WhlMA9wEIaAwAAAIANQBpDAAAAgBPAGsMAAACAFMAagwAAAMAVQBsDAAAAgBDAG0MAAABAAoA6gwAAAIAPgBuDAAAAQApABYABgkaFXQCAKoBBmgMAAABAEgAaQwAAAEANABrDAAAAQBDAGwMAAABAD4AbQwAAAEAEgDqDAAAAQAyAAAA.Girthcat:BAEALgAECgYJDgABLgAECggJFQAWAL0XAA==.',
Gl='Glaivejazzy:BAEALgAECgYJDgABLgAFFAUJEgAFAFURAA==.',
Go='Goodbearry:BAEALgAECgQJCgABLgAFFAMJBgABAK8WAA==.',
Gr='Grizzlygerm:BAEALgAECgUJBQAAAA==.',
Gu='Gunnther:BAEALgAECgIJAgABLgAECgIJAgAIAAAAAA==.',
He='Heimdaller:BAEALgAECgYJCwAAAA==.Heimerdonker:BAEALgADCgcJBwABLgAFFAQJBgAJAEwFAA==.Heimermagic:BAECLgAFFH8GAAIJAAQJTAVKJAAJAQRoDAAAAgAKAGkMAAACAAAAawwAAAEACgDqDAAAAQAgAAkABAlMBUokAAkBBGgMAAACAAoAaQwAAAIAAABrDAAAAQAKAOoMAAABACAALgAECn8rAAIJAAgJIBquIAC3AQAJAAgJIBquIAC3AQAAAA==.Hewikan:BAEALgAECgQJBQAAAA==.',
Hu='Huddie:BAEALgAECgYJEgAAAA==.',
Ic='Icesniper:BAEALgAECgYJEwAAAA==.',
Im='Immunize:BAEALgADCgEJAQABLgADCgYJCwAIAAAAAA==.',
Ja='Jadeiana:BAEALgAECgUJBwAAAA==.Jagö:BAEALgAECgQJBwAAAA==.Jazzytwo:BAEALgAECgYJDAABLgAFFAUJEgAFAFURAA==.',
Ju='Justhunt:BAECLgAFFH8JAAICAAQJRRCJCABIAQRoDAAAAwAkAGkMAAABAD8AawwAAAIAOADqDAAAAwALAAIABAlFEIkIAEgBBGgMAAADACQAaQwAAAEAPwBrDAAAAgA4AOoMAAADAAsALgAECn8kAAMCAAgJ2x38DQDNAgACAAgJ2x38DQDNAgAEAAEJQAb6kAApAAAAAA==.',
Ka='Kahrhen:BAEALgADCgYJBgABLgAECggJIAAKAJ0WAA==.Kalazar:BAECLgAFFH8YAAMEAAgJ7RvNAgAqAghoDAAABQBRAGkMAAADAF0AawwAAAMAWgBqDAAABAA4AGwMAAADADgAbQwAAAEAKwDqDAAABABAAG4MAAABAEcABAAICaAazQIAKgIIaAwAAAUAUQBpDAAAAQBGAGsMAAADAFoAagwAAAQAOABsDAAAAwA4AG0MAAABACsA6gwAAAIAQABuDAAAAQBHAAIAAgloFT8VALAAAmkMAAACAF0A6gwAAAIAEAAuAAQKfyUAAwIACQm0JXUAANIDAAIACQl1JHUAANIDAAQACAleJT0FAEkDAAAA.',
Kh='Khuuthun:BAEALgAECgUJCAABLgAFFAcJFgAOAC4hAA==.',
Ko='Konstabeam:BAEBLgAECn8gAAMVAAgJuxNPGACrAQhoDAAABQBKAGkMAAAFAEIAawwAAAQAMwBqDAAABQBPAGwMAAAFADcAbQwAAAIADwDqDAAABQBFAG4MAAABABUAFQAICbsTTxgAqwEIaAwAAAUASgBpDAAABABCAGsMAAAEADMAagwAAAUATwBsDAAABQA3AG0MAAACAA8A6gwAAAUARQBuDAAAAQAVABcAAQnaFChqAD0AAWkMAAABADUAAAA=.Korvast:BAEBLgAECn87AAIYAAgJeiKxAQC3AghoDAAADQBhAGkMAAALAGEAawwAAAoAWABqDAAABgBVAGwMAAAGAF4AbQwAAAMASgDqDAAABwBKAG4MAAADAFsAGAAICXoisQEAtwIIaAwAAA0AYQBpDAAACwBhAGsMAAAKAFgAagwAAAYAVQBsDAAABgBeAG0MAAADAEoA6gwAAAcASgBuDAAAAwBbAAAA.',
La='Landinoo:BAEALgADCggJCwABLgAECggJFQAHAD4hAA==.',
Le='Lenorlée:BAEBLgAECn8ZAAIJAAgJkh0kDABTAghoDAAABQBdAGkMAAAEAFUAawwAAAQAWgBqDAAAAwBdAGwMAAADAF4AbQwAAAEABwDqDAAABABhAG4MAAABAD0ACQAICZIdJAwAUwIIaAwAAAUAXQBpDAAABABVAGsMAAAEAFoAagwAAAMAXQBsDAAAAwBeAG0MAAABAAcA6gwAAAQAYQBuDAAAAQA9AAAA.',
Ly='Lynkalla:BAEALgADCgMJAwABLgAECgYJEwAIAAAAAA==.Lynmakara:BAEALgAECgYJEwAAAA==.',
Me='Meddah:BAEBLgAECn8nAAIMAAgJIxfsCwASAghoDAAABgBDAGkMAAAFAEUAawwAAAYARgBqDAAABQAlAGwMAAAFADMAbQwAAAQAMgDqDAAABgA5AG4MAAACAEQADAAICSMX7AsAEgIIaAwAAAYAQwBpDAAABQBFAGsMAAAGAEYAagwAAAUAJQBsDAAABQAzAG0MAAAEADIA6gwAAAYAOQBuDAAAAgBEAAAA.',
Mo='Moltremix:BAEBLgAECn8UAAIWAAcJrB5AAwBgAgdoDAAAAwBTAGkMAAADAEoAawwAAAMAUwBqDAAAAgBHAGwMAAACAFQAbQwAAAIAOQDqDAAABQBWABYABwmsHkADAGACB2gMAAADAFMAaQwAAAMASgBrDAAAAwBTAGoMAAACAEcAbAwAAAIAVABtDAAAAgA5AOoMAAAFAFYAAS4ABRQFCQ8AFgDjGQA=.Moltøn:BAECLgAFFH8PAAQWAAUJ4xlzAABlAQVoDAAABABNAGkMAAAEAEwAawwAAAIAEwBqDAAAAQA0AOoMAAAEAFsAFgAECTIYcwAAZQEEaAwAAAMAPABpDAAAAwBMAGsMAAABABMA6gwAAAMAWwABAAQJbRVLEgBAAQRoDAAAAQBNAGkMAAABACYAawwAAAEAEgDqDAAAAQBUABkAAQkAAD8ZAAAAAWoMAAABADQALgAECn8lAAMWAAkJgCS3AAA3AwAWAAgJsyW3AAA3AwABAAIJJx6rXwCwAAAAAA==.Moodk:BAEALgAECgUJBQABLgAFFAQJDQAFAP4gAA==.Moosshu:BAECLgAFFH8NAAIFAAQJ/iBfBAB1AQRoDAAABABgAGkMAAAEAFUAawwAAAIAUgDqDAAAAwBJAAUABAn+IF8EAHUBBGgMAAAEAGAAaQwAAAQAVQBrDAAAAgBSAOoMAAADAEkALgAECn8kAAIFAAgJ4iODBgAfAwAFAAgJ4iODBgAfAwAAAA==.Morsaudet:BAEBLgAECn8ZAAIBAAgJpB+UIgC1AghoDAAABQBaAGkMAAAEAGIAawwAAAMAXABqDAAAAwBWAGwMAAADAF0AbQwAAAMAHwDqDAAAAwBeAG4MAAABAEIAAQAICaQflCIAtQIIaAwAAAUAWgBpDAAABABiAGsMAAADAFwAagwAAAMAVgBsDAAAAwBdAG0MAAADAB8A6gwAAAMAXgBuDAAAAQBCAAAA.',
My='Mysterice:BAEALgAECgUJBQABLgAECgYJEwAIAAAAAA==.',
Na='Navelty:BAEALgADCgkJCQAAAA==.',
No='Nofatherpls:BAEALgAECgMJAwABLgAECgkJEQAIAAAAAA==.Nolazax:BAECLgAFFH8OAAMMAAUJxhNrBQCEAQVoDAAABQA7AGkMAAADABsAawwAAAIAOgBqDAAAAQAlAOoMAAADAEYADAAFCcYTawUAhAEFaAwAAAQAOwBpDAAAAwAbAGsMAAACADoAagwAAAEAJQDqDAAAAwBGABoAAQkvEP8GADgAAWgMAAABACkALgAECn8dAAIMAAgJyiIrCAAKAwAMAAgJyiIrCAAKAwABLgAFFAIJBwATAL8fAA==.',
Ny='Nyrae:BAEBLgAECn8YAAMQAAcJuxknHQDyAQdoDAAABQBLAGkMAAAEAE0AawwAAAQATwBqDAAAAwBSAGwMAAACADUAbQwAAAEALQDqDAAABQBAABAABglXGycdAPIBBmgMAAADAEsAaQwAAAMATQBrDAAAAwBPAGoMAAADAFIAbAwAAAIANQDqDAAAAgBAABIABQmxI3AhAIgBBWgMAAACAGEAaQwAAAEAXgBrDAAAAQBQAG0MAAABAFkA6gwAAAMAXQAAAA==.',
Om='Omgdagron:BAEALgADCgIJAgABLgAECggJFwAbAPMRAA==.Omghammer:BAEALgAECggJDwABLgAECggJFwAbAPMRAA==.Omgtotem:BAEBLgAECn8XAAIbAAgJ8xGLBQCSAQhoDAAABQA6AGkMAAAFAD8AawwAAAUAMgBqDAAAAgALAGwMAAACACwAbQwAAAEAHgDqDAAAAgAtAG4MAAABABwAGwAICfMRiwUAkgEIaAwAAAUAOgBpDAAABQA/AGsMAAAFADIAagwAAAIACwBsDAAAAgAsAG0MAAABAB4A6gwAAAIALQBuDAAAAQAcAAAA.',
['Oî']='Oî:BAEALgAECgYJEwAAAA==.',
Po='Poazfk:BAEALgAECgYJCgABLgAECgkJEQAIAAAAAA==.',
Pr='Praeset:BAEALgADCgYJCwAAAA==.Priest:BAEBLgAECn8bAAQRAAgJgRr/EwA/AghoDAAABQBWAGkMAAAFAFUAawwAAAQAWABqDAAABABZAGwMAAADAFoAbQwAAAEACQDqDAAABABMAG4MAAABABAAEQAHCVgd/xMAPwIHaAwAAAEAVgBpDAAAAgBVAGsMAAACAFgAagwAAAMAWQBsDAAAAwBaAG0MAAABAAkA6gwAAAMATAASAAUJiQ2tHgCfAAVoDAAABAAgAGkMAAADAC4AawwAAAIAGgBqDAAAAQAbAOoMAAABACgAEAABCUsIyDgAMwABbgwAAAEAFQAAAA==.',
Ps='Psyká:BAEALgAECgYJEgAAAA==.',
Ra='Razska:BAEBLgAECn8mAAMQAAgJ3xgZCwCkAQhoDAAABgBQAGkMAAAFAEUAawwAAAYAUgBqDAAABgBJAGwMAAAFAD4AbQwAAAMAMQDqDAAABgBOAG4MAAABABYAEAAICd8YGQsApAEIaAwAAAUAUABpDAAABQBFAGsMAAAGAFIAagwAAAUASQBsDAAABQA+AG0MAAACADEA6gwAAAYATgBuDAAAAQAWABEAAwkpCwxnAJEAA2gMAAABAA4AagwAAAEALABtDAAAAQAaAAAA.',
Se='Senapim:BAECLgAFFH8PAAIJAAQJ4CE9CgCAAQRoDAAABABfAGkMAAAEAFQAawwAAAMASwDqDAAABABbAAkABAngIT0KAIABBGgMAAAEAF8AaQwAAAQAVABrDAAAAwBLAOoMAAAEAFsALgAECn8oAAIJAAgJpCSqDwBKAwAJAAgJpCSqDwBKAwAAAA==.Senapimonk:BAEALgAFFAIJAgABLgAFFAQJDwAJAOAhAA==.',
Sh='Shelannigans:BAEBLgAECn8hAAIRAAkJjyO6AACYAwloDAAABQBUAGkMAAAFAGEAawwAAAQAXwBqDAAABABhAGwMAAADAGMAbQwAAAMAYADqDAAABQBgAG4MAAACAFwAbwwAAAIAPAARAAkJjyO6AACYAwloDAAABQBUAGkMAAAFAGEAawwAAAQAXwBqDAAABABhAGwMAAADAGMAbQwAAAMAYADqDAAABQBgAG4MAAACAFwAbwwAAAIAPAAAAA==.Shuvi:BAEALgAECgcJCwABLgAFFAYJEQATAIwXAA==.',
Sk='Skywardwings:BAEALgAECgQJBQABLgAECgUJCgAIAAAAAA==.',
St='Stebmage:BAEALgAECgUJBQABLgAFFAUJEwALAHEaAA==.Stebpaladin:BAEALgAECgEJAQABLgAFFAUJEwALAHEaAA==.Stebrogue:BAEALgADCgMJAwABLgAFFAUJEwALAHEaAA==.Stebshaman:BAECLgAFFH8TAAILAAUJcRpTBAChAQVoDAAABQBKAGkMAAAEAD0AawwAAAQASABqDAAAAwA6AOoMAAADAD4ACwAFCXEaUwQAoQEFaAwAAAUASgBpDAAABAA9AGsMAAAEAEgAagwAAAMAOgDqDAAAAwA+AC4ABAp/IgACCwAJCSkfVwYALgMACwAJCSkfVwYALgMAAAA=.',
Su='Sullet:BAEALgAECgYJBwAAAA==.',
Sy='Sylyphe:BAECLgAFFH8RAAITAAYJjBdeBACfAQZoDAAABABFAGkMAAACAEYAawwAAAMARABqDAAAAwApAGwMAAABAEkA6gwAAAQAJgATAAYJjBdeBACfAQZoDAAABABFAGkMAAACAEYAawwAAAMARABqDAAAAwApAGwMAAABAEkA6gwAAAQAJgAuAAQKfxQAAhMACAnFG94NAHgCABMACAnFG94NAHgCAAAA.',
Te='Tengen:BAEALgADCgEJAQAAAA==.',
Ti='Tierán:BAEBLgAECn8gAAQCAAgJsiUVAwC5AghoDAAABQBiAGkMAAAFAGIAawwAAAQAYwBqDAAABABRAGwMAAADAFYAbQwAAAMAYwDqDAAABQBhAG4MAAADAF8AAgAICbIlFQMAuQIIaAwAAAIAYgBpDAAAAgBiAGsMAAACAGMAagwAAAMAUQBsDAAAAQBWAG0MAAADAGMA6gwAAAIAYQBuDAAAAwBfAAQABgk0GhAwALIBBmgMAAACAFsAaQwAAAIAWQBrDAAAAQAHAGoMAAABABoAbAwAAAIAQQDqDAAAAwBQAAMAAwnBHDMdAAUBA2gMAAABAD0AaQwAAAEASgBrDAAAAQBVAAAA.',
To='Tobis:BAEALgAECgkJEQAAAA==.Toonces:BAEALgAECgEJAQABLgAECggJJgAQAN8YAA==.',
Tr='Trem:BAEALgAECggJEwABLgAFFAcJFgAOAC4hAA==.Tremens:BAECLgAFFH8WAAQOAAcJLiF3AAB0AgdoDAAABABjAGkMAAAEAFgAawwAAAMAZABqDAAAAgBXAGwMAAADAEYAbQwAAAEARgDqDAAABQBPAA4ABglMIncAAHQCBmgMAAAEAGMAaQwAAAQAWABrDAAAAgBkAGoMAAABAFcAbAwAAAMARgDqDAAABQBPAA0AAgmyEjIKALcAAmsMAAABABkAbQwAAAEARgAPAAEJAACTBwA+AAFqDAAAAQADAC4ABAp/HwACDgAJCT8mIwAAhwMADgAJCT8mIwAAhwMAAAA=.',
Tw='Twelvedread:BAEALgAECgQJBAABLgAECggJHQAHAFETAA==.Twlvepeers:BAEBLgAECn8dAAMHAAgJURNTLQBZAQhoDAAABQA/AGkMAAAEAEYAawwAAAQAMgBqDAAABAAnAGwMAAADAEQAbQwAAAIAGADqDAAABQA0AG4MAAACAA8ABwAHCRkSUy0AWQEHaAwAAAUAPwBpDAAABABGAGsMAAAEADIAagwAAAQAJwBtDAAAAgAYAOoMAAAFADQAbgwAAAIADwAcAAEJoRr/HABOAAFsDAAAAwBEAAAA.',
Ty='Typhoidbeary:BAECLgAFFH8GAAMBAAMJrxbaOACqAANoDAAAAwBbAGkMAAACADIA6gwAAAEAHwABAAIJ0xvaOACqAAJoDAAAAwBbAGkMAAACADIAFgABCWcMUQYAUAAB6gwAAAEAHwAuAAQKfx0AAgEACQlAId8SAAoDAAEACQlAId8SAAoDAAAA.',
['Tè']='Tèren:BAEALgADCgcJEAAAAA==.',
Un='Unobservant:BAEALgADCgMJAwABLgAECgUJCgAIAAAAAA==.',
Ve='Ventres:BAEALgADCgMJAwABLgAECggJIAAKAJ0WAA==.',
Vi='Virtuel:BAEALgAECgMJAwAAAA==.',
Xa='Xalitoes:BAEBLgAECn8YAAIFAAgJhCP1CgDcAghoDAAAAwBgAGkMAAAEAFwAawwAAAQAVABqDAAAAgBVAGwMAAACAFYAbQwAAAIAXQDqDAAABQBbAG4MAAACAFsABQAICYQj9QoA3AIIaAwAAAMAYABpDAAABABcAGsMAAAEAFQAagwAAAIAVQBsDAAAAgBWAG0MAAACAF0A6gwAAAUAWwBuDAAAAgBbAAAA.',
Xe='Xelaym:BAEALgAECgIJAgAAAA==.',
Xp='Xplosives:BAEALgAECgUJCgAAAA==.',
Za='Zannarossa:BAEALgAFFAEJAQABLgAECgkJGQABAKQfAA==.Zayvointh:BAEALgAECgYJDwABLgAFFAQJDAAQAPQZAA==.',
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
