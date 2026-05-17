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

local lookup = {'Priest-Holy','Priest-Shadow','Mage-Frost','Warrior-Fury','Paladin-Holy','Paladin-Retribution','Hunter-BeastMastery','Warrior-Arms','Unknown-Unknown','Shaman-Elemental','Druid-Balance','Shaman-Enhancement','Hunter-Survival','Warlock-Destruction','Monk-Brewmaster','DeathKnight-Unholy','DeathKnight-Blood','Druid-Guardian','DemonHunter-Devourer','DemonHunter-Vengeance','Monk-Windwalker','Hunter-Marksmanship','Warlock-Affliction','Rogue-Subtlety','Rogue-Assassination','Druid-Restoration','Warrior-Protection','DemonHunter-Havoc','Paladin-Protection','Priest-Discipline','Warlock-Demonology','Evoker-Devastation','Evoker-Preservation','DeathKnight-Frost',}
local provider = {region='US',realm='Farstriders',name='US',type='daily',zone=46,date='2026-05-16',data={Ab='Absolon:BAAALgAECgYJEQAAAA==.',
Ae='Aelar:BAAALgADCgEJAQAAAA==.Aellynn:BAABLgAECn8kAAMBAAgJ/AlTKAA6AQhoDAAABwAYAGkMAAAGACgAawwAAAYAHgBqDAAABQAQAGwMAAAEACQAbQwAAAIAGADqDAAABQAaAG4MAAABAAQAAQAICfwJUygAOgEIaAwAAAYAGABpDAAABgAoAGsMAAAGAB4AagwAAAUAEABsDAAABAAkAG0MAAACABgA6gwAAAUAGgBuDAAAAQAEAAIAAQleACpsABcAAWgMAAABAAAAAAA=.Aerir:BAACLgAFFH8MAAIDAAQJYQovSQAgAQRoDAAABQAlAGkMAAAEADUAawwAAAEABgDqDAAAAgAIAAMABAlhCi9JACABBGgMAAAFACUAaQwAAAQANQBrDAAAAQAGAOoMAAACAAgALgAECn8pAAIDAAgJ9BvcWwAmAgADAAgJ9BvcWwAmAgAAAA==.Aerithar:BAAALgADCgEJAQAAAA==.Aesirr:BAAALgAECgcJEQAAAA==.',
Ah='Ahmari:BAAALgADCgMJAwAAAA==.',
Al='Alandris:BAABLgAECn8YAAIEAAcJ2ARXRwDVAAdoDAAABAALAGkMAAADAAgAawwAAAMADgBqDAAAAwAKAGwMAAAEAAoA6gwAAAQADgBuDAAAAwAPAAQABwnYBFdHANUAB2gMAAAEAAsAaQwAAAMACABrDAAAAwAOAGoMAAADAAoAbAwAAAQACgDqDAAABAAOAG4MAAADAA8AAAA=.Alerya:BAAALgAECgEJAQAAAA==.Alinie:BAACLgAFFH8GAAMFAAMJGCFJFwAdAQNoDAAAAgBgAGkMAAACAF8A6gwAAAIAPQAFAAMJGCFJFwAdAQNoDAAAAQBgAGkMAAABAF8A6gwAAAEAPQAGAAMJrBx4MgAQAQNoDAAAAQBAAGkMAAABAFMA6gwAAAEASAAuAAQKfxYAAgUACAkKJVgHAPcCAAUACAkKJVgHAPcCAAAA.Alleriya:BAABLgAECn8dAAIHAAgJLwqMTQBfAQhoDAAABQAWAGkMAAAFABsAawwAAAQAFABqDAAABABGAGwMAAADACYAbQwAAAEAFQDqDAAABgAiAG4MAAABABAABwAICS8KjE0AXwEIaAwAAAUAFgBpDAAABQAbAGsMAAAEABQAagwAAAQARgBsDAAAAwAmAG0MAAABABUA6gwAAAYAIgBuDAAAAQAQAAAA.Allison:BAAALgADCgMJAwAAAA==.Alltheheals:BAAALgAECggJDAAAAA==.Altruis:BAAALgADCgIJAgABLgAFFAQJDAAGAB0gAA==.',
Am='Amarawyn:BAAALgAECgYJEwAAAA==.Ambulance:BAAALgADCgEJAQAAAA==.Amoragan:BAABLgAECn8eAAMIAAkJGhpWEgB6AQloDAAABAA+AGkMAAAEAE0AawwAAAQAMwBqDAAAAwBNAGwMAAAEAEsAbQwAAAEAMgDqDAAABgBJAG4MAAACAEIAbwwAAAIATQAEAAkJ8hfaOADDAQloDAAAAgA0AGkMAAACAE0AawwAAAIAMwBqDAAAAQBHAGwMAAACAEsAbQwAAAEAMgDqDAAABAA4AG4MAAABADAAbwwAAAIATQAIAAcJnxZWEgB6AQdoDAAAAgA+AGkMAAACADMAawwAAAIAIABqDAAAAgBNAGwMAAACADwA6gwAAAIASQBuDAAAAQBCAAAA.',
An='Andriela:BAAALgAECggJEgAAAA==.',
Ap='Apexy:BAAALgAECgYJDgAAAA==.',
Ar='Arashikaze:BAAALgAECgcJDgAAAA==.',
Au='Augidget:BAABLgAECn8lAAICAAkJGhVXDwAVAgloDAAABQA2AGkMAAAFAEkAawwAAAUASgBqDAAABABSAGwMAAAFAEYAbQwAAAIAEgDqDAAABwBQAG4MAAACACcAbwwAAAIAFQACAAkJGhVXDwAVAgloDAAABQA2AGkMAAAFAEkAawwAAAUASgBqDAAABABSAGwMAAAFAEYAbQwAAAIAEgDqDAAABwBQAG4MAAACACcAbwwAAAIAFQAAAA==.',
Av='Avgo:BAAALgAECgMJAwABLgAECgYJDgAJAAAAAA==.Avilen:BAABLgAECn8VAAIHAAgJJQhBVwBCAQhoDAAAAwAkAGkMAAADABsAawwAAAMAIABqDAAAAwAaAGwMAAADAAUAbQwAAAIABwDqDAAAAwATAG4MAAABABEABwAICSUIQVcAQgEIaAwAAAMAJABpDAAAAwAbAGsMAAADACAAagwAAAMAGgBsDAAAAwAFAG0MAAACAAcA6gwAAAMAEwBuDAAAAQARAAAA.Aviris:BAAALgAECgYJBgABLgAECggJDQAJAAAAAA==.',
Ay='Ayuzi:BAAALgADCgEJAQAAAA==.',
Ba='Badsilk:BAAALgAECgYJEwAAAA==.Balinteen:BAAALgAECgYJEQAAAA==.Barktwain:BAAALgAECgQJBAAAAA==.Bastael:BAABLgAECn8fAAIFAAkJtyPzAQBnAwloDAAABABaAGkMAAAEAGEAawwAAAQAXABqDAAAAwBKAGwMAAAEAF4AbQwAAAIAXADqDAAABgBiAG4MAAACAF8AbwwAAAIAVQAFAAkJtyPzAQBnAwloDAAABABaAGkMAAAEAGEAawwAAAQAXABqDAAAAwBKAGwMAAAEAF4AbQwAAAIAXADqDAAABgBiAG4MAAACAF8AbwwAAAIAVQAAAA==.Bayus:BAAALgADCgIJAgAAAA==.',
Be='Benchie:BAAALgAECgEJAQABLgAECggJJwAKAJcZAA==.Bendyy:BAABLgAECn8hAAIDAAkJcRzaHwBjAgloDAAABQBMAGkMAAAFAFIAawwAAAMATABqDAAAAwBdAGwMAAAEAFEAbQwAAAIAOQDqDAAABwBaAG4MAAACAEMAbwwAAAIAMQADAAkJcRzaHwBjAgloDAAABQBMAGkMAAAFAFIAawwAAAMATABqDAAAAwBdAGwMAAAEAFEAbQwAAAIAOQDqDAAABwBaAG4MAAACAEMAbwwAAAIAMQAAAA==.',
Bh='Bharani:BAAALgADCgcJBwAAAA==.',
Bi='Biopaindr:BAABLgAECn8bAAILAAgJAhLZHQB+AQhoDAAABQBFAGkMAAAFADQAawwAAAQAMwBqDAAAAwAkAGwMAAADADEAbQwAAAEAEwDqDAAABQA0AG4MAAABABwACwAICQIS2R0AfgEIaAwAAAUARQBpDAAABQA0AGsMAAAEADMAagwAAAMAJABsDAAAAwAxAG0MAAABABMA6gwAAAUANABuDAAAAQAcAAAA.Bitxi:BAAALgAECgYJDgAAAA==.',
Bo='Boldbane:BAAALgAECgQJBgAAAA==.Boozo:BAAALgAECgIJBAAAAA==.',
Br='Brocklee:BAABLgAECn8ZAAIMAAcJSQ8UEAA6AQdoDAAABQAxAGkMAAAFAC8AawwAAAUANwBqDAAAAwAvAGwMAAABABsA6gwAAAUAHwBuDAAAAQAWAAwABwlJDxQQADoBB2gMAAAFADEAaQwAAAUALwBrDAAABQA3AGoMAAADAC8AbAwAAAEAGwDqDAAABQAfAG4MAAABABYAAAA=.',
Bu='Bubbaman:BAAALgAECgYJDQAAAA==.Burda:BAABLgAECn8aAAINAAkJcxUTDQASAgloDAAABQBBAGkMAAAEADcAawwAAAQAQQBqDAAAAwA5AGwMAAADADcAbQwAAAEAKQDqDAAAAwA6AG4MAAABACoAbwwAAAIANgANAAkJcxUTDQASAgloDAAABQBBAGkMAAAEADcAawwAAAQAQQBqDAAAAwA5AGwMAAADADcAbQwAAAEAKQDqDAAAAwA6AG4MAAABACoAbwwAAAIANgAAAA==.',
Ca='Caenae:BAAALgAECgMJBwAAAA==.Cattlerage:BAAALgADCgUJBQABLgAFFAQJDAAGAB0gAA==.',
Ce='Celestial:BAAALgAECgEJAgAAAA==.',
Ch='Chandris:BAAALgADCgIJAgAAAA==.Chrissy:BAAALgAECgYJBgAAAA==.',
Ci='Ciannie:BAAALgADCgIJAgAAAA==.',
Cl='Clamor:BAAALgAECgQJDgAAAA==.',
Co='Coletrain:BAAALgAECgUJCwAAAA==.Corri:BAAALgAECgQJCwAAAA==.Corriandis:BAAALgAECgQJBAAAAA==.',
Cr='Credon:BAAALgAECgYJDgAAAA==.Crixxe:BAAALgAECgQJBwAAAA==.',
Da='Davin:BAAALgAECgUJBQAAAA==.',
Dh='Dhellia:BAAALgAECgYJCgAAAA==.',
Di='Dierlyn:BAAALgAECgYJEwAAAA==.Dirtytaters:BAAALgAECgYJDgAAAA==.Divastating:BAAALgAECgEJAQABLgAECgQJCQAJAAAAAA==.',
Do='Doró:BAAALgAECgYJCQABLgAECgkJIgAOACUfAA==.',
Dt='Dtothed:BAAALgADCgQJCwAAAA==.',
Dw='Dwarfred:BAAALgAECgYJEAAAAA==.Dwimor:BAABLgAECn8ZAAIHAAYJBBA/XwBKAQZoDAAABgAlAGkMAAAFADcAawwAAAUAMgBqDAAAAgAaAGwMAAACACEA6gwAAAUAHAAHAAYJBBA/XwBKAQZoDAAABgAlAGkMAAAFADcAawwAAAUAMgBqDAAAAgAaAGwMAAACACEA6gwAAAUAHAAAAA==.',
['Dô']='Dôro:BAAALgAECgEJAQABLgAECgkJIgAOACUfAA==.',
Ea='Earadin:BAAALgAECgMJAwAAAA==.',
Ec='Ecthelorn:BAAALgADCgMJBAAAAA==.',
El='Elasong:BAAALgAECgQJCQAAAA==.Elletal:BAAALgADCgEJAQABLgAECggJJAAPAEMSAA==.Elmö:BAAALgAECgUJCAAAAA==.Elrarebriel:BAAALgADCggJDAAAAA==.',
Em='Emberstorm:BAAALgADCgQJBAAAAA==.',
Fa='Fairamir:BAAALgADCgIJAgAAAA==.Fayona:BAAALgADCgUJBwAAAA==.',
Fe='Felystra:BAAALgAECgIJBQAAAA==.',
Fi='Fizzlyn:BAACLgAFFH8MAAMQAAQJFRlvMwBMAQRoDAAABQBaAGkMAAAEADgAawwAAAEAHQDqDAAAAgBQABAABAndGG8zAEwBBGgMAAAEAFgAaQwAAAQAOABrDAAAAQAdAOoMAAACAFAAEQABCWEjwiEAYgABaAwAAAEAWgAuAAQKfykAAhAACAnuIq4uAH0CABAACAnuIq4uAH0CAAAA.',
Fl='Fluffsmcgee:BAAALgADCgkJDgAAAA==.',
Fr='Fredrick:BAAALgADCgcJCAAAAA==.Frieza:BAAALgAECgQJBQAAAA==.',
Fu='Furr:BAAALgAFFAEJAQABLgAFFAYJFwADAI0VAA==.',
Ga='Galdora:BAAALgADCgcJEQAAAA==.Galedriel:BAAALgAECgMJBAAAAA==.',
Gh='Ghosthunter:BAAALgADCgkJDwAAAA==.',
Gi='Giizmo:BAAALgAECgEJAQAAAA==.',
Gr='Gragdal:BAAALgADCgQJBAAAAA==.Grandpa:BAAALgADCgkJGQABLgAECgYJGwAHAModAA==.Grewsöm:BAABLgAECn8cAAMQAAgJxCMBHwBKAghoDAAABgBgAGkMAAAFAGIAawwAAAQAYABqDAAABABaAGwMAAADAFIAbQwAAAEAUADqDAAAAwBbAG4MAAACAF4AEAAICcQjAR8ASgIIaAwAAAIAYABpDAAAAgBiAGsMAAACAGAAagwAAAIAWgBsDAAAAgBSAG0MAAABAFAA6gwAAAIAWwBuDAAAAgBeABEABgmKHaYRAJwBBmgMAAAEAFYAaQwAAAMAWgBrDAAAAgBaAGoMAAACAFQAbAwAAAEAIQDqDAAAAQBMAAEuAAUUBAkMAAYAHSAA.Grotusque:BAABLgAECn8sAAISAAgJBRc1CwDFAQhoDAAACABCAGkMAAAHAD4AawwAAAcAMwBqDAAABgA7AGwMAAAGAEgAbQwAAAIAOgDqDAAABgBIAG4MAAACABwAEgAICQUXNQsAxQEIaAwAAAgAQgBpDAAABwA+AGsMAAAHADMAagwAAAYAOwBsDAAABgBIAG0MAAACADoA6gwAAAYASABuDAAAAgAcAAAA.',
Gu='Gullugren:BAAALgAECgkJCAAAAA==.Gutterdoxy:BAAALgADCgMJAwAAAA==.',
Ha='Hadiirn:BAABLgAECn8dAAITAAYJ9RCbaAABAQZoDAAABQAoAGkMAAAFACkAawwAAAYAIgBqDAAABQBIAGwMAAADACgA6gwAAAUAOgATAAYJ9RCbaAABAQZoDAAABQAoAGkMAAAFACkAawwAAAYAIgBqDAAABQBIAGwMAAADACgA6gwAAAUAOgAAAA==.Haiiro:BAABLgAECn8iAAIPAAkJOBfiDgAOAgloDAAABQA4AGkMAAAFAE4AawwAAAQAPABqDAAAAwBGAGwMAAAEADcAbQwAAAIAHwDqDAAABwA2AG4MAAACAD4AbwwAAAIASgAPAAkJOBfiDgAOAgloDAAABQA4AGkMAAAFAE4AawwAAAQAPABqDAAAAwBGAGwMAAAEADcAbQwAAAIAHwDqDAAABwA2AG4MAAACAD4AbwwAAAIASgAAAA==.Hardim:BAAALgAECgYJEgAAAA==.Hardwood:BAAALgADCgMJAwAAAA==.Hargen:BAAALgAECgIJAgAAAA==.Harknesse:BAAALgAECgYJDgAAAA==.Hatermage:BAAALgAECgYJDwAAAA==.Hazzrel:BAAALgAECgYJDQAAAA==.',
He='Heftychi:BAAALgAECgIJAgAAAA==.Heftydh:BAABLgAECn8cAAIUAAgJ9xzqBAAQAghoDAAABQBWAGkMAAAFAFEAawwAAAQAUQBqDAAABABVAGwMAAADAE4AbQwAAAEAKgDqDAAABQBbAG4MAAABADkAFAAICfcc6gQAEAIIaAwAAAUAVgBpDAAABQBRAGsMAAAEAFEAagwAAAQAVQBsDAAAAwBOAG0MAAABACoA6gwAAAUAWwBuDAAAAQA5AAAA.Hewhospins:BAABLgAECn8kAAMPAAgJQxKCHACEAQhoDAAABgBXAGkMAAAGAEUAawwAAAYALwBqDAAABAAkAGwMAAAEABsAbQwAAAMAIgDqDAAABgAtAG4MAAABAA4ADwAICUMSghwAhAEIaAwAAAYAVwBpDAAABgBFAGsMAAAGAC8AagwAAAQAJABsDAAABAAbAG0MAAACACIA6gwAAAYALQBuDAAAAQAOABUAAQloCgeEACEAAW0MAAABABoAAAA=.',
Hy='Hydraulicman:BAAALgAECgEJAQAAAA==.Hyzer:BAAALgAECgYJBgABLgAECggJEAAJAAAAAA==.',
Id='Idget:BAAALgADCgEJAQAAAA==.',
Ig='Igknight:BAAALgAECgEJAQAAAA==.',
Ja='Jacksmite:BAAALgADCgEJAQAAAA==.Jasmirana:BAAALgAECgYJDAAAAA==.',
Je='Jemano:BAAALgADCgEJAQAAAA==.',
Ji='Jirenr:BAABLgAECn8XAAIVAAcJxwVoNgDYAAdoDAAABAAOAGkMAAAEABEAawwAAAQAEwBqDAAABAATAGwMAAACABUA6gwAAAQACQBuDAAAAQAHABUABwnHBWg2ANgAB2gMAAAEAA4AaQwAAAQAEQBrDAAABAATAGoMAAAEABMAbAwAAAIAFQDqDAAABAAJAG4MAAABAAcAAAA=.',
Jo='Jolage:BAABLgAECn8UAAIDAAYJOg+KigAnAQZoDAAABAAhAGkMAAADACkAawwAAAMAIABqDAAAAgATAGwMAAAFABkA6gwAAAMAPQADAAYJOg+KigAnAQZoDAAABAAhAGkMAAADACkAawwAAAMAIABqDAAAAgATAGwMAAAFABkA6gwAAAMAPQAAAA==.Jolreal:BAACLgAFFH8FAAINAAMJaxdwEQAEAQNoDAAAAgAvAGkMAAACAEIA6gwAAAEAQgANAAMJaxdwEQAEAQNoDAAAAgAvAGkMAAACAEIA6gwAAAEAQgAuAAQKfzoAAxYACAmiIEUUAJICABYABwlQIkUUAJICAA0ACAnIGrILACYCAAAA.',
Ju='Julez:BAABLgAECn8VAAIHAAYJZQ/BYwAhAQZoDAAABQA0AGkMAAAFACcAawwAAAQAHgBqDAAAAgAWAGwMAAACAC4A6gwAAAMAHQAHAAYJZQ/BYwAhAQZoDAAABQA0AGkMAAAFACcAawwAAAQAHgBqDAAAAgAWAGwMAAACAC4A6gwAAAMAHQAAAA==.Julezara:BAAALgAECgMJBAAAAA==.Julezdruid:BAAALgADCgMJBQAAAA==.Junkai:BAACLgAFFH8IAAIGAAMJQBRyQADrAANoDAAABAA/AGkMAAADADMAawwAAAEAKAAGAAMJQBRyQADrAANoDAAABAA/AGkMAAADADMAawwAAAEAKAAuAAQKfysAAgYACAn+Iy0bAMYCAAYACAn+Iy0bAMYCAAAA.',
Ka='Kathanial:BAAALgADCgUJBgAAAA==.Katiagrimm:BAAALgADCgIJAgAAAA==.Kawi:BAAALgADCgcJBwABLgAECgcJGQAMAEkPAA==.',
Ke='Keco:BAAALgAECgQJCQAAAA==.Kelenar:BAAALgAECgMJAwAAAA==.Kennie:BAABLgAECn8dAAMOAAgJaAo0DgAPAQhoDAAABQArAGkMAAAFACAAawwAAAUAGABqDAAAAwAKAGwMAAADABwAbQwAAAIADADqDAAABQAiAG4MAAABAAsADgAICWgKNA4ADwEIaAwAAAQAKwBpDAAABAAgAGsMAAAEABgAagwAAAMACgBsDAAAAwAcAG0MAAACAAwA6gwAAAUAIgBuDAAAAQALABcAAwkgBrUcAI0AA2gMAAABAAwAaQwAAAEAFABrDAAAAQAOAAAA.',
Kl='Kladivo:BAAALgADCgYJBgABLgAECgQJBAAJAAAAAA==.',
Kn='Knorr:BAAALgAECgUJBQAAAA==.',
Ko='Korthaz:BAAALgADCgIJAgAAAA==.',
Kw='Kwansu:BAAALgAECgQJBAAAAA==.',
La='Lahlania:BAAALgAECgYJEwAAAA==.Laura:BAAALgAECgIJAgAAAA==.',
Li='Lilyda:BAAALgADCggJBgAAAA==.',
Lo='Lolann:BAAALgADCgUJCAAAAA==.',
Ly='Lyia:BAAALgADCgEJAQAAAA==.',
Ma='Machette:BAAALgAECgUJEQAAAA==.Mailaria:BAABLgAECn8lAAIUAAkJRQ+WCACTAQloDAAABQAwAGkMAAAFADIAawwAAAUAHQBqDAAABAAyAGwMAAAFAEAAbQwAAAIAGwDqDAAABwArAG4MAAACAAkAbwwAAAIAJwAUAAkJRQ+WCACTAQloDAAABQAwAGkMAAAFADIAawwAAAUAHQBqDAAABAAyAGwMAAAFAEAAbQwAAAIAGwDqDAAABwArAG4MAAACAAkAbwwAAAIAJwAAAA==.Majesti:BAAALgADCggJBwAAAA==.Malakar:BAABLgAECn8jAAMYAAcJuRsUIgDoAQdoDAAABQBaAGkMAAAGADkAawwAAAYAUABqDAAABQAkAGwMAAAFAC8AbQwAAAIATQDqDAAABgBHABgABwlpFxQiAOgBB2gMAAADADkAaQwAAAMAOQBrDAAAAwA4AGoMAAADACQAbAwAAAMALwBtDAAAAgBNAOoMAAADAD4AGQAGCYcZ0AsAagEGaAwAAAIAWgBpDAAAAwAoAGsMAAADAFAAagwAAAIAEgBsDAAAAgArAOoMAAADAEcAAAA=.Malvolio:BAAALgADCgMJAwAAAA==.Mantoecore:BAAALgADCgcJCAAAAA==.Marellaa:BAAALgAECgMJBAAAAA==.Markers:BAAALgADCgIJAgAAAA==.',
Mc='Mcsplatapus:BAAALgAECgUJBAAAAA==.',
Me='Meingsolin:BAABLgAECn8VAAIVAAYJjhJCKQAdAQZoDAAABQA/AGkMAAAFADAAawwAAAQAIABqDAAAAgA+AGwMAAACADAA6gwAAAMALQAVAAYJjhJCKQAdAQZoDAAABQA/AGkMAAAFADAAawwAAAQAIABqDAAAAgA+AGwMAAACADAA6gwAAAMALQAAAA==.Meseeker:BAAALgADCgEJAQAAAA==.Mezagog:BAAALgADCgcJEAAAAA==.',
Mi='Midknight:BAAALgAECgUJBgAAAA==.Miggylosoh:BAAALgAECgMJBAAAAA==.Minizoomies:BAAALgAECgEJAQAAAA==.',
Mo='Momo:BAAALgADCgkJFgAAAA==.',
My='Mygourdness:BAABLgAECn8VAAIaAAYJ+ASVcACgAAZoDAAABAAOAGkMAAAEABgAawwAAAQACQBqDAAAAgAGAGwMAAACAA0A6gwAAAUACAAaAAYJ+ASVcACgAAZoDAAABAAOAGkMAAAEABgAawwAAAQACQBqDAAAAgAGAGwMAAACAA0A6gwAAAUACAAAAA==.Myuk:BAABLgAECn8hAAINAAkJAx3PBwBoAgloDAAABABPAGkMAAAEAE8AawwAAAQAQABqDAAABABaAGwMAAAFAEQAbQwAAAEATQDqDAAABwBYAG4MAAACAEEAbwwAAAIARgANAAkJAx3PBwBoAgloDAAABABPAGkMAAAEAE8AawwAAAQAQABqDAAABABaAGwMAAAFAEQAbQwAAAEATQDqDAAABwBYAG4MAAACAEEAbwwAAAIARgAAAA==.',
Na='Naminay:BAAALgAECgYJDgAAAA==.Narbash:BAAALgAECgQJBAAAAA==.Nasrullah:BAAALgADCgkJDAAAAA==.Natalie:BAAALgAECgEJAQAAAA==.',
Ne='Nekia:BAAALgADCgcJBwAAAA==.Neroz:BAABLgAECn8pAAITAAgJMRjcKgDVAQhoDAAABwBPAGkMAAAHAEkAawwAAAcAOABqDAAABQAwAGwMAAAFADcAbQwAAAMAPwDqDAAABgA9AG4MAAABACkAEwAICTEY3CoA1QEIaAwAAAcATwBpDAAABwBJAGsMAAAHADgAagwAAAUAMABsDAAABQA3AG0MAAADAD8A6gwAAAYAPQBuDAAAAQApAAAA.Nerppie:BAABLgAECn8kAAIFAAgJUB8FDwBdAghoDAAABgBQAGkMAAAGAE8AawwAAAYAWQBqDAAABABXAGwMAAAEAGEAbQwAAAMANQDqDAAABgBUAG4MAAABAEQABQAICVAfBQ8AXQIIaAwAAAYAUABpDAAABgBPAGsMAAAGAFkAagwAAAQAVwBsDAAABABhAG0MAAADADUA6gwAAAYAVABuDAAAAQBEAAAA.Nevershark:BAAALgAECgUJBQAAAA==.',
Ni='Nightfallz:BAAALgADCgUJBQAAAA==.Nina:BAABLgAECn8ZAAIGAAcJdRpRTwD0AQdoDAAABQBEAGkMAAAEAFAAawwAAAQAVABqDAAAAQAyAGwMAAABACcA6gwAAAYATwBuDAAABAA2AAYABwl1GlFPAPQBB2gMAAAFAEQAaQwAAAQAUABrDAAABABUAGoMAAABADIAbAwAAAEAJwDqDAAABgBPAG4MAAAEADYAAAA=.Nixah:BAAALgAECgUJDQAAAA==.',
Nk='Nkript:BAABLgAECn8hAAMHAAgJ3BRZLQDWAQhoDAAABgA+AGkMAAAFAEkAawwAAAUAQABqDAAABQA7AGwMAAAFAE4AbQwAAAEAFwDqDAAABQApAG4MAAABAB4ABwAICdwUWS0A1gEIaAwAAAMAPgBpDAAABABJAGsMAAAEAEAAagwAAAQAOwBsDAAABABOAG0MAAABABcA6gwAAAQAKQBuDAAAAQAeABYABgmmCIlPABEBBmgMAAADABwAaQwAAAEABQBrDAAAAQAdAGoMAAABABcAbAwAAAEAEwDqDAAAAQAbAAAA.',
No='Nortel:BAAALgAECgYJDgAAAA==.',
Oh='Ohgourdness:BAAALgADCgcJBwABLgAECgYJFQAaAPgEAA==.',
On='Onari:BAABLgAECn8kAAIBAAkJvRxoBwC0AgloDAAABQBGAGkMAAAFAFQAawwAAAUAUQBqDAAABABSAGwMAAAFAEEAbQwAAAEAOgDqDAAABwBjAG4MAAACAEIAbwwAAAIANgABAAkJvRxoBwC0AgloDAAABQBGAGkMAAAFAFQAawwAAAUAUQBqDAAABABSAGwMAAAFAEEAbQwAAAEAOgDqDAAABwBjAG4MAAACAEIAbwwAAAIANgAAAA==.',
Or='Orious:BAAALgADCgYJBgAAAA==.',
Pa='Pandagang:BAAALgADCgQJBQAAAA==.',
Pe='Peezee:BAAALgAECgUJCQAAAA==.Perce:BAABLgAECn8eAAIFAAgJ9iAPBwDaAghoDAAABgBHAGkMAAAEAE4AawwAAAQAUQBqDAAABABeAGwMAAAEAFoAbQwAAAIAVQDqDAAABQBbAG4MAAABAFEABQAICfYgDwcA2gIIaAwAAAYARwBpDAAABABOAGsMAAAEAFEAagwAAAQAXgBsDAAABABaAG0MAAACAFUA6gwAAAUAWwBuDAAAAQBRAAAA.Peyotte:BAABLgAECn8VAAIbAAgJfR8wCAAyAghoDAAABABVAGkMAAAEAFgAawwAAAMAUwBqDAAAAgBUAGwMAAACAFoAbQwAAAEAOADqDAAABABIAG4MAAABAFYAGwAICX0fMAgAMgIIaAwAAAQAVQBpDAAABABYAGsMAAADAFMAagwAAAIAVABsDAAAAgBaAG0MAAABADgA6gwAAAQASABuDAAAAQBWAAEuAAQKCQkgAAoAwR8A.',
Pf='Pfemme:BAABLgAECn8mAAIHAAkJ+BskEACIAgloDAAABQBTAGkMAAAFAD0AawwAAAUASQBqDAAABQAsAGwMAAAGAE4AbQwAAAMAKQDqDAAABABXAG4MAAAEAFMAbwwAAAEAPwAHAAkJ+BskEACIAgloDAAABQBTAGkMAAAFAD0AawwAAAUASQBqDAAABQAsAGwMAAAGAE4AbQwAAAMAKQDqDAAABABXAG4MAAAEAFMAbwwAAAEAPwAAAA==.',
Ps='Psych:BAAALgADCgYJBgAAAA==.',
Pu='Purian:BAAALgADCgUJCAAAAA==.',
Ra='Rami:BAAALgADCgYJBgAAAA==.',
Re='Repello:BAAALgAECgYJBwAAAA==.Reyaieleron:BAAALgAECgQJCQAAAA==.',
Ri='Ricky:BAAALgADCgEJAQAAAA==.Rivenaer:BAABLgAECn8vAAIcAAkJBQ+lEgCeAQloDAAABwA1AGkMAAAHACsAawwAAAcAOABqDAAABgA0AGwMAAAFABgAbQwAAAQAGQDqDAAABgAzAG4MAAAEABYAbwwAAAEAHQAcAAkJBQ+lEgCeAQloDAAABwA1AGkMAAAHACsAawwAAAcAOABqDAAABgA0AGwMAAAFABgAbQwAAAQAGQDqDAAABgAzAG4MAAAEABYAbwwAAAEAHQAAAA==.',
Ru='Ruindsoul:BAAALgADCgcJCwAAAA==.Ruka:BAAALgADCgEJAQAAAA==.Runearne:BAAALgAECgIJAgAAAA==.Rustymark:BAABLgAECn8WAAIHAAkJ0Qu1PgCQAQloDAAABQAdAGkMAAAFACIAawwAAAQAJQBqDAAAAgANAGwMAAACADIAbQwAAAEAJADqDAAAAQAPAG4MAAABABYAbwwAAAEAEQAHAAkJ0Qu1PgCQAQloDAAABQAdAGkMAAAFACIAawwAAAQAJQBqDAAAAgANAGwMAAACADIAbQwAAAEAJADqDAAAAQAPAG4MAAABABYAbwwAAAEAEQAAAA==.',
Sc='Scaletal:BAAALgAECgUJBQAAAA==.Schmetzy:BAAALgAECgYJBwAAAA==.Schmezzy:BAABLgAECn8aAAIQAAgJtx2sLgD9AQhoDAAABABTAGkMAAADAF4AawwAAAQAPQBqDAAAAwBQAGwMAAAEAEAAbQwAAAIAVgDqDAAABQBIAG4MAAABAEUAEAAICbcdrC4A/QEIaAwAAAQAUwBpDAAAAwBeAGsMAAAEAD0AagwAAAMAUABsDAAABABAAG0MAAACAFYA6gwAAAUASABuDAAAAQBFAAAA.',
Se='Sealalicious:BAABLgAECn8pAAIdAAgJ1BdGDgCGAQhoDAAABwBOAGkMAAAHAEEAawwAAAcATgBqDAAABQAyAGwMAAAFAEMAbQwAAAMAJwDqDAAABgBCAG4MAAABAB0AHQAICdQXRg4AhgEIaAwAAAcATgBpDAAABwBBAGsMAAAHAE4AagwAAAUAMgBsDAAABQBDAG0MAAADACcA6gwAAAYAQgBuDAAAAQAdAAAA.Seenaa:BAAALgADCgcJEAAAAA==.',
Sh='Shallot:BAAALgADCgMJBQAAAA==.Shammywow:BAAALgAECgUJDQAAAA==.Sharkzilla:BAAALgAECgkJEgAAAA==.Shauray:BAAALgADCgUJCAAAAA==.Shine:BAABLgAECn8bAAMHAAYJyh3/NgCuAQZoDAAABwBjAGkMAAAFAFMAawwAAAMAJABqDAAAAgBXAGwMAAACAEUA6gwAAAgAXQAHAAYJ+xz/NgCuAQZoDAAABgBjAGkMAAAEAFMAawwAAAIAGQBqDAAAAgBXAGwMAAACAEUA6gwAAAcAXQANAAQJRRD4KQD7AARoDAAAAQA4AGkMAAABADQAawwAAAEAJADqDAAAAQAVAAAA.Shrub:BAAALgADCgcJBwABLgAFFAgJGQAeAKghAA==.',
Sl='Sloppy:BAAALgADCgMJAwAAAA==.',
Sm='Smoo:BAAALgADCgkJJAAAAA==.',
Sn='Snø:BAAALgAECgYJDQAAAA==.',
So='Sobol:BAAALgAFFAEJAgAAAA==.Soggyaugi:BAAALgAECgUJBQAAAA==.Solbinder:BAAALgADCgIJAgAAAA==.Soraa:BAEALgAECgUJDwABLgAECggJFgADAHIfAA==.',
St='Starlethia:BAAALgAECggJEwAAAA==.',
Su='Sumpnclaws:BAAALgAECgYJBgAAAA==.Sunshine:BAAALgADCgcJDAAAAA==.Sunwälker:BAAALgADCgQJBAAAAA==.',
Sy='Sybelin:BAAALgADCgMJAwAAAA==.',
Ta='Tallchief:BAAALgAECgMJBwAAAA==.Tankufrdying:BAAALgADCgQJBgAAAA==.Tavarien:BAAALgADCgEJAQAAAA==.Tayllana:BAAALgAECgEJAQAAAA==.',
Te='Tenjo:BAAALgADCgMJAwAAAA==.Terrier:BAAALgAECgEJAQAAAA==.',
Th='Thaerdran:BAABLgAECn8dAAIRAAcJoBcfFgBhAQdoDAAABQAyAGkMAAAEAEUAawwAAAQARwBqDAAABAAnAGwMAAAFADAA6gwAAAQAQwBuDAAAAwA3ABEABwmgFx8WAGEBB2gMAAAFADIAaQwAAAQARQBrDAAABABHAGoMAAAEACcAbAwAAAUAMADqDAAABABDAG4MAAADADcAAAA=.',
Ti='Tirriel:BAAALgADCgMJAwAAAA==.',
To='Toess:BAAALgAECgEJAQAAAA==.Tonjuren:BAAALgAECgMJBwABLgAECgYJFQAVAI4SAA==.',
Tr='Trublood:BAAALgAECgYJDgAAAA==.',
Tw='Twister:BAAALgAECgQJDwAAAA==.',
Ty='Tyrra:BAAALgADCgMJAwAAAA==.',
Uk='Ukeenonme:BAAALgADCgQJBgAAAA==.',
Us='Usorloups:BAABLgAECn8gAAIKAAkJwR96CACRAgloDAAABABUAGkMAAAEAFIAawwAAAMAWwBqDAAABABKAGwMAAADAFcAbQwAAAMAYgDqDAAABgBVAG4MAAAEAFsAbwwAAAEAHQAKAAkJwR96CACRAgloDAAABABUAGkMAAAEAFIAawwAAAMAWwBqDAAABABKAGwMAAADAFcAbQwAAAMAYgDqDAAABgBVAG4MAAAEAFsAbwwAAAEAHQAAAA==.',
Va='Valstad:BAAALgAECgYJBgAAAA==.',
Ve='Velonys:BAABLgAECn8oAAQOAAkJvB/XBACPAgloDAAABwBgAGkMAAAGAFwAawwAAAUAVwBqDAAABQBOAGwMAAAFAFsAbQwAAAMARwDqDAAABQBQAG4MAAACAFAAbwwAAAIAMQAOAAgJiCHXBACPAghoDAAAAgBgAGkMAAADAFwAawwAAAQAVwBqDAAABQBOAGwMAAAEAFsAbQwAAAMARwDqDAAAAgBQAG4MAAABAFAAHwAGCUkVLl0ASQEGaAwAAAQAQQBpDAAAAgBKAGwMAAABADgA6gwAAAIANwBuDAAAAQAaAG8MAAACADEAFwAECSwglAwAJAEEaAwAAAEAXABpDAAAAQBTAGsMAAABAE4A6gwAAAEASgAAAA==.Velus:BAAALgAECgQJBAAAAA==.',
Vi='Victory:BAAALgAECgEJAQAAAA==.Vintar:BAAALgADCgMJAwAAAA==.',
Vy='Vyu:BAAALgAECgkJAwAAAA==.',
Wa='Wanayu:BAABLgAECn8iAAIOAAkJNhigAgA8AgloDAAABQBOAGkMAAAFAEYAawwAAAUAOQBqDAAABAA5AGwMAAAFAEsAbQwAAAEAFgDqDAAABwBTAG4MAAABAEgAbwwAAAEAIwAOAAkJNhigAgA8AgloDAAABQBOAGkMAAAFAEYAawwAAAUAOQBqDAAABAA5AGwMAAAFAEsAbQwAAAEAFgDqDAAABwBTAG4MAAABAEgAbwwAAAEAIwAAAA==.Wanweasley:BAAALgAECgcJDAAAAA==.',
We='Weeab:BAAALgADCgEJAQAAAA==.Weezlee:BAAALgAECgQJBAAAAA==.Weh:BAABLgAECn8YAAIDAAkJryK1FQCfAgloDAAABABfAGkMAAAEAGMAawwAAAMAYwBqDAAAAwBiAGwMAAACAGMAbQwAAAIATADqDAAABABjAG4MAAABAEkAbwwAAAEAQwADAAkJryK1FQCfAgloDAAABABfAGkMAAAEAGMAawwAAAMAYwBqDAAAAwBiAGwMAAACAGMAbQwAAAIATADqDAAABABjAG4MAAABAEkAbwwAAAEAQwAAAA==.',
Wi='Wickedsham:BAAALgADCgIJAgAAAA==.Wintermourne:BAAALgAECgcJDgAAAA==.Wizagon:BAABLgAECn8VAAIgAAkJYxkeAwAyAgloDAAAAgBPAGkMAAACAFYAawwAAAIAQABqDAAAAgBgAGwMAAADADgAbQwAAAIAKQDqDAAABABOAG4MAAACACcAbwwAAAIASAAgAAkJYxkeAwAyAgloDAAAAgBPAGkMAAACAFYAawwAAAIAQABqDAAAAgBgAGwMAAADADgAbQwAAAIAKQDqDAAABABOAG4MAAACACcAbwwAAAIASAAAAA==.',
Wo='Woodsy:BAABLgAECn8iAAIhAAkJmRroAwC4AgloDAAABQBQAGkMAAAFAFQAawwAAAUAPwBqDAAABABAAGwMAAAFADwAbQwAAAIAMADqDAAABgBhAG4MAAABAEEAbwwAAAEALwAhAAkJmRroAwC4AgloDAAABQBQAGkMAAAFAFQAawwAAAUAPwBqDAAABABAAGwMAAAFADwAbQwAAAIAMADqDAAABgBhAG4MAAABAEEAbwwAAAEALwAAAA==.Wounded:BAAALgAECgEJAQAAAA==.Woundliquor:BAAALgAECgcJCAAAAA==.',
Wu='Wuinn:BAACLgAFFH8NAAMaAAQJ5hHQCgAvAQRoDAAABQA+AGkMAAADACUAawwAAAMAGADqDAAAAgA6ABoABAnmEdAKAC8BBGgMAAAEAD4AaQwAAAIAJQBrDAAAAgAYAOoMAAACADoACwADCaUDWCgAiQADaAwAAAEAEwBpDAAAAQADAGsMAAABAAQALgAECn8xAAMaAAkJCyDeDwC5AgAaAAkJCyDeDwC5AgASAAcJUhj4DACmAQAAAA==.',
Xe='Xemnas:BAABLgAECn8qAAQQAAcJjA3DcwAzAQdoDAAACQAqAGkMAAAJACQAawwAAAgAFgBqDAAABwAzAGwMAAAEACYAbQwAAAEAHADqDAAABAAnABAABwn/DMNzADMBB2gMAAAIACoAaQwAAAcAHwBrDAAABgATAGoMAAAGABsAbAwAAAQAJgBtDAAAAQAcAOoMAAAEACcAIgAECecKWhcAjgAEaAwAAAEAGABpDAAAAgAkAGsMAAABABYAagwAAAEAMwARAAEJqgHVSwAaAAFrDAAAAQAEAAAA.',
Ya='Yawnday:BAAALgADCgUJCAAAAA==.',
Za='Zaryala:BAAALgADCgkJKAAAAA==.',
Ze='Zenshift:BAAALgAECgMJBgAAAA==.',
Zy='Zynthia:BAABLgAECn8nAAIQAAgJYiQHDgDBAghoDAAABwBcAGkMAAAHAGIAawwAAAcAYQBqDAAABABjAGwMAAAEAF0AbQwAAAMAXwDqDAAABgBgAG4MAAABAE4AEAAICWIkBw4AwQIIaAwAAAcAXABpDAAABwBiAGsMAAAHAGEAagwAAAQAYwBsDAAABABdAG0MAAADAF8A6gwAAAYAYABuDAAAAQBOAAAA.',
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
