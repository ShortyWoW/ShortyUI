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

local lookup = {'Priest-Holy','Priest-Shadow','Mage-Frost','Warrior-Fury','Paladin-Holy','Paladin-Retribution','Hunter-BeastMastery','Warrior-Arms','Unknown-Unknown','Druid-Balance','Shaman-Enhancement','Hunter-Survival','Warlock-Destruction','DeathKnight-Unholy','DeathKnight-Blood','Druid-Guardian','DemonHunter-Devourer','Monk-Brewmaster','DemonHunter-Vengeance','Monk-Windwalker','Hunter-Marksmanship','Warlock-Affliction','Rogue-Subtlety','Rogue-Assassination','Druid-Restoration','Warrior-Protection','Shaman-Elemental','DemonHunter-Havoc','Paladin-Protection','Priest-Discipline','Warlock-Demonology','Evoker-Preservation','DeathKnight-Frost',}
local provider = {region='US',realm='Farstriders',name='US',type='daily',zone=46,date='2026-05-13',data={Ab='Absolon:BAAALgAECgYJDQAAAA==.',
Ae='Aelar:BAAALgADCgEJAQAAAA==.Aellynn:BAABLgAECn8kAAMBAAgJ/AmuIwBDAQhoDAAABwAYAGkMAAAGACgAawwAAAYAHgBqDAAABQAQAGwMAAAEACQAbQwAAAIAGADqDAAABQAaAG4MAAABAAQAAQAICfwJriMAQwEIaAwAAAYAGABpDAAABgAoAGsMAAAGAB4AagwAAAUAEABsDAAABAAkAG0MAAACABgA6gwAAAUAGgBuDAAAAQAEAAIAAQleACpsABcAAWgMAAABAAAAAAA=.Aerir:BAACLgAFFH8MAAIDAAQJYQrVQgAmAQRoDAAABQAlAGkMAAAEADUAawwAAAEABgDqDAAAAgAIAAMABAlhCtVCACYBBGgMAAAFACUAaQwAAAQANQBrDAAAAQAGAOoMAAACAAgALgAECn8oAAIDAAgJ9BvcWwAmAgADAAgJ9BvcWwAmAgAAAA==.Aerithar:BAAALgADCgEJAQAAAA==.Aesirr:BAAALgAECgUJCgAAAA==.',
Ah='Ahmari:BAAALgADCgMJAwAAAA==.',
Al='Alandris:BAABLgAECn8YAAIEAAcJ2AQCPQDkAAdoDAAABAALAGkMAAADAAgAawwAAAMADgBqDAAAAwAKAGwMAAAEAAoA6gwAAAQADgBuDAAAAwAPAAQABwnYBAI9AOQAB2gMAAAEAAsAaQwAAAMACABrDAAAAwAOAGoMAAADAAoAbAwAAAQACgDqDAAABAAOAG4MAAADAA8AAAA=.Alerya:BAAALgAECgEJAQAAAA==.Alinie:BAACLgAFFH8GAAMFAAMJGCHiFAAfAQNoDAAAAgBgAGkMAAACAF8A6gwAAAIAPQAFAAMJGCHiFAAfAQNoDAAAAQBgAGkMAAABAF8A6gwAAAEAPQAGAAMJrBzzLAAUAQNoDAAAAQBAAGkMAAABAFMA6gwAAAEASAAuAAQKfxYAAgUACAkKJVgHAPcCAAUACAkKJVgHAPcCAAAA.Alleriya:BAABLgAECn8bAAIHAAcJyAqmTgA6AQdoDAAABQAWAGkMAAAFABsAawwAAAQAFABqDAAABABGAGwMAAADACYAbQwAAAEAFQDqDAAABQAiAAcABwnICqZOADoBB2gMAAAFABYAaQwAAAUAGwBrDAAABAAUAGoMAAAEAEYAbAwAAAMAJgBtDAAAAQAVAOoMAAAFACIAAAA=.Allison:BAAALgADCgMJAwAAAA==.Alltheheals:BAAALgAECggJDAAAAA==.Altruis:BAAALgADCgIJAgABLgAFFAQJCgAGAB0gAA==.',
Am='Amarawyn:BAAALgAECgYJEwAAAA==.Ambulance:BAAALgADCgEJAQAAAA==.Amoragan:BAABLgAECn8bAAMIAAgJexmvDACaAQhoDAAABAA+AGkMAAAEAE0AawwAAAQAMwBqDAAAAwBNAGwMAAAEAEsAbQwAAAEAMgDqDAAABgBJAG4MAAABAEIABAAHCa4X2jgAwwEHaAwAAAIANABpDAAAAgBNAGsMAAACADMAagwAAAEARwBsDAAAAgBLAG0MAAABADIA6gwAAAQAOAAIAAcJnxavDACaAQdoDAAAAgA+AGkMAAACADMAawwAAAIAIABqDAAAAgBNAGwMAAACADwA6gwAAAIASQBuDAAAAQBCAAAA.',
An='Andriela:BAAALgAECgYJDQAAAA==.',
Ap='Apexy:BAAALgAECgYJDgAAAA==.',
Ar='Arashikaze:BAAALgAECgcJDgAAAA==.',
Au='Augidget:BAABLgAECn8iAAICAAgJ7RbTDgD+AQhoDAAABQA2AGkMAAAFAEkAawwAAAUASgBqDAAABABSAGwMAAAFAEYAbQwAAAIAEgDqDAAABwBQAG4MAAABACcAAgAICe0W0w4A/gEIaAwAAAUANgBpDAAABQBJAGsMAAAFAEoAagwAAAQAUgBsDAAABQBGAG0MAAACABIA6gwAAAcAUABuDAAAAQAnAAAA.',
Av='Avgo:BAAALgAECgMJAwABLgAECgYJDgAJAAAAAA==.Avilen:BAABLgAECn8VAAIHAAgJJQhqRwBRAQhoDAAAAwAkAGkMAAADABsAawwAAAMAIABqDAAAAwAaAGwMAAADAAUAbQwAAAIABwDqDAAAAwATAG4MAAABABEABwAICSUIakcAUQEIaAwAAAMAJABpDAAAAwAbAGsMAAADACAAagwAAAMAGgBsDAAAAwAFAG0MAAACAAcA6gwAAAMAEwBuDAAAAQARAAAA.Aviris:BAAALgAECgYJBgABLgAECggJCgAJAAAAAA==.',
Ay='Ayuzi:BAAALgADCgEJAQAAAA==.',
Ba='Badsilk:BAAALgAECgYJEwAAAA==.Balinteen:BAAALgAECgYJDQAAAA==.Barktwain:BAAALgAECgQJBAAAAA==.Bastael:BAABLgAECn8cAAIFAAgJBCTAAwAXAwhoDAAABABaAGkMAAAEAGEAawwAAAQAXABqDAAAAwBKAGwMAAAEAF4AbQwAAAIAXADqDAAABgBiAG4MAAABAF8ABQAICQQkwAMAFwMIaAwAAAQAWgBpDAAABABhAGsMAAAEAFwAagwAAAMASgBsDAAABABeAG0MAAACAFwA6gwAAAYAYgBuDAAAAQBfAAAA.Bayus:BAAALgADCgIJAgAAAA==.',
Be='Bendyy:BAABLgAECn8eAAIDAAgJfB29JAArAghoDAAABQBMAGkMAAAFAFIAawwAAAMATABqDAAAAwBdAGwMAAAEAFEAbQwAAAIAOQDqDAAABwBaAG4MAAABAD4AAwAICXwdvSQAKwIIaAwAAAUATABpDAAABQBSAGsMAAADAEwAagwAAAMAXQBsDAAABABRAG0MAAACADkA6gwAAAcAWgBuDAAAAQA+AAAA.',
Bh='Bharani:BAAALgADCgcJBwAAAA==.',
Bi='Biopaindr:BAABLgAECn8ZAAIKAAcJ/RKTHABtAQdoDAAABQBFAGkMAAAFADQAawwAAAQAMwBqDAAAAwAkAGwMAAADADEAbQwAAAEAEwDqDAAABAAxAAoABwn9EpMcAG0BB2gMAAAFAEUAaQwAAAUANABrDAAABAAzAGoMAAADACQAbAwAAAMAMQBtDAAAAQATAOoMAAAEADEAAAA=.Bitxi:BAAALgAECgYJDgAAAA==.',
Bo='Boldbane:BAAALgAECgQJBgAAAA==.Boozo:BAAALgAECgIJBAAAAA==.',
Br='Brocklee:BAABLgAECn8XAAILAAYJjxDNDwAjAQZoDAAABQAxAGkMAAAFAC8AawwAAAUANwBqDAAAAwAvAGwMAAABABsA6gwAAAQAHwALAAYJjxDNDwAjAQZoDAAABQAxAGkMAAAFAC8AawwAAAUANwBqDAAAAwAvAGwMAAABABsA6gwAAAQAHwAAAA==.',
Bu='Bubbaman:BAAALgAECgYJDQAAAA==.Burda:BAABLgAECn8aAAIMAAkJcxW6CAAzAgloDAAABQBBAGkMAAAEADcAawwAAAQAQQBqDAAAAwA5AGwMAAADADcAbQwAAAEAKQDqDAAAAwA6AG4MAAABACoAbwwAAAIANgAMAAkJcxW6CAAzAgloDAAABQBBAGkMAAAEADcAawwAAAQAQQBqDAAAAwA5AGwMAAADADcAbQwAAAEAKQDqDAAAAwA6AG4MAAABACoAbwwAAAIANgAAAA==.',
Ca='Caenae:BAAALgAECgMJBwAAAA==.Cattlerage:BAAALgADCgUJBQABLgAFFAQJCgAGAB0gAA==.',
Ce='Celestial:BAAALgAECgEJAgAAAA==.',
Ch='Chandris:BAAALgADCgIJAgAAAA==.Chrissy:BAAALgAECgYJBgAAAA==.',
Ci='Ciannie:BAAALgADCgIJAgAAAA==.',
Cl='Clamor:BAAALgAECgQJDgAAAA==.',
Co='Coletrain:BAAALgAECgUJCwAAAA==.Corri:BAAALgAECgMJCgAAAA==.Corriandis:BAAALgAECgQJBAAAAA==.',
Cr='Credon:BAAALgAECgYJDgAAAA==.Crixxe:BAAALgAECgQJBwAAAA==.',
Dh='Dhellia:BAAALgAECgYJCgAAAA==.',
Di='Dierlyn:BAAALgAECgYJEwAAAA==.Dirtytaters:BAAALgAECgYJDgAAAA==.Divastating:BAAALgAECgEJAQABLgAECgQJCQAJAAAAAA==.',
Do='Doró:BAAALgAECgYJCQABLgAECgkJGwANAMYdAA==.',
Dt='Dtothed:BAAALgADCgQJCwAAAA==.',
Dw='Dwarfred:BAAALgAECgYJEAAAAA==.Dwimor:BAABLgAECn8ZAAIHAAYJBBDKXAAVAQZoDAAABgAlAGkMAAAFADcAawwAAAUAMgBqDAAAAgAaAGwMAAACACEA6gwAAAUAHAAHAAYJBBDKXAAVAQZoDAAABgAlAGkMAAAFADcAawwAAAUAMgBqDAAAAgAaAGwMAAACACEA6gwAAAUAHAAAAA==.',
['Dô']='Dôro:BAAALgAECgEJAQABLgAECgkJGwANAMYdAA==.',
Ea='Earadin:BAAALgAECgMJAwAAAA==.',
Ec='Ecthelorn:BAAALgADCgMJBAAAAA==.',
El='Elasong:BAAALgAECgQJCQAAAA==.Elmö:BAAALgAECgUJBQAAAA==.Elrarebriel:BAAALgADCggJDAAAAA==.',
Em='Emberstorm:BAAALgADCgQJBAAAAA==.',
Fa='Fairamir:BAAALgADCgIJAgAAAA==.Fayona:BAAALgADCgUJBwAAAA==.',
Fe='Felystra:BAAALgAECgIJBQAAAA==.',
Fi='Fizzlyn:BAACLgAFFH8MAAMOAAQJFRmiKgBWAQRoDAAABQBaAGkMAAAEADgAawwAAAEAHQDqDAAAAgBQAA4ABAndGKIqAFYBBGgMAAAEAFgAaQwAAAQAOABrDAAAAQAdAOoMAAACAFAADwABCWEj4R4AZAABaAwAAAEAWgAuAAQKfykAAg4ACAnuIq4uAH0CAA4ACAnuIq4uAH0CAAAA.',
Fl='Fluffsmcgee:BAAALgADCgkJDgAAAA==.',
Fr='Fredrick:BAAALgADCgcJCAAAAA==.Frieza:BAAALgAECgQJBQAAAA==.',
Fu='Furr:BAAALgAFFAEJAQABLgAFFAYJFwADAI0VAA==.',
Ga='Galdora:BAAALgADCgcJEQAAAA==.Galedriel:BAAALgAECgMJBAAAAA==.',
Gh='Ghosthunter:BAAALgADCgkJDwAAAA==.',
Gi='Giizmo:BAAALgAECgEJAQAAAA==.',
Gr='Gragdal:BAAALgADCgQJBAAAAA==.Grandpa:BAAALgADCgkJGQABLgAECgUJEwAJAAAAAA==.Grewsöm:BAABLgAECn8XAAMOAAgJxCN5EwB+AghoDAAABQBgAGkMAAAEAGIAawwAAAMAYABqDAAAAwBaAGwMAAACAFIAbQwAAAEAUADqDAAAAwBbAG4MAAACAF4ADgAICcQjeRMAfgIIaAwAAAIAYABpDAAAAgBiAGsMAAACAGAAagwAAAIAWgBsDAAAAgBSAG0MAAABAFAA6gwAAAIAWwBuDAAAAgBeAA8ABQmqHtoTAFkBBWgMAAADAFYAaQwAAAIARgBrDAAAAQBRAGoMAAABAFQA6gwAAAEATAABLgAFFAQJCgAGAB0gAA==.Grotusque:BAABLgAECn8kAAIQAAgJrxMNDACEAQhoDAAABwBCAGkMAAAGAD4AawwAAAYAMwBqDAAABQAuAGwMAAAFACQAbQwAAAEALgDqDAAABQA8AG4MAAABABwAEAAICa8TDQwAhAEIaAwAAAcAQgBpDAAABgA+AGsMAAAGADMAagwAAAUALgBsDAAABQAkAG0MAAABAC4A6gwAAAUAPABuDAAAAQAcAAAA.',
Gu='Gullugren:BAAALgAECgkJCAAAAA==.Gutterdoxy:BAAALgADCgMJAwAAAA==.',
Ha='Hadiirn:BAABLgAECn8dAAIRAAYJ9RA/VgARAQZoDAAABQAoAGkMAAAFACkAawwAAAYAIgBqDAAABQBIAGwMAAADACgA6gwAAAUAOgARAAYJ9RA/VgARAQZoDAAABQAoAGkMAAAFACkAawwAAAYAIgBqDAAABQBIAGwMAAADACgA6gwAAAUAOgAAAA==.Haiiro:BAABLgAECn8fAAISAAgJtRWLEgDCAQhoDAAABQA4AGkMAAAFAE4AawwAAAQAPABqDAAAAwBGAGwMAAAEADcAbQwAAAIAHwDqDAAABwA2AG4MAAABADIAEgAICbUVixIAwgEIaAwAAAUAOABpDAAABQBOAGsMAAAEADwAagwAAAMARgBsDAAABAA3AG0MAAACAB8A6gwAAAcANgBuDAAAAQAyAAAA.Hardim:BAAALgAECgYJEgAAAA==.Hardwood:BAAALgADCgMJAwAAAA==.Hargen:BAAALgAECgIJAgAAAA==.Harknesse:BAAALgAECgYJDgAAAA==.Hatermage:BAAALgAECgYJDwAAAA==.Hazzrel:BAAALgAECgYJDQAAAA==.',
He='Heftychi:BAAALgAECgIJAgAAAA==.Heftydh:BAABLgAECn8aAAITAAcJCR6dBQDSAQdoDAAABQBWAGkMAAAFAFEAawwAAAQAUQBqDAAABABVAGwMAAADAE4AbQwAAAEAKgDqDAAABABbABMABwkJHp0FANIBB2gMAAAFAFYAaQwAAAUAUQBrDAAABABRAGoMAAAEAFUAbAwAAAMATgBtDAAAAQAqAOoMAAAEAFsAAAA=.Hewhospins:BAABLgAECn8kAAMSAAgJQxKTFgCZAQhoDAAABgBXAGkMAAAGAEUAawwAAAYALwBqDAAABAAkAGwMAAAEABsAbQwAAAMAIgDqDAAABgAtAG4MAAABAA4AEgAICUMSkxYAmQEIaAwAAAYAVwBpDAAABgBFAGsMAAAGAC8AagwAAAQAJABsDAAABAAbAG0MAAACACIA6gwAAAYALQBuDAAAAQAOABQAAQloChJqADAAAW0MAAABABoAAAA=.',
Hy='Hydraulicman:BAAALgAECgEJAQAAAA==.Hyzer:BAAALgAECgYJBgABLgAECggJDwAJAAAAAA==.',
Id='Idget:BAAALgADCgEJAQAAAA==.',
Ig='Igknight:BAAALgAECgEJAQAAAA==.',
Ja='Jacksmite:BAAALgADCgEJAQAAAA==.Jasmirana:BAAALgAECgYJDAAAAA==.',
Je='Jemano:BAAALgADCgEJAQAAAA==.',
Ji='Jirenr:BAABLgAECn8VAAIUAAYJYwZnNADHAAZoDAAABAAOAGkMAAAEABEAawwAAAQAEwBqDAAABAATAGwMAAACABUA6gwAAAMACQAUAAYJYwZnNADHAAZoDAAABAAOAGkMAAAEABEAawwAAAQAEwBqDAAABAATAGwMAAACABUA6gwAAAMACQAAAA==.',
Jo='Jolage:BAABLgAECn8UAAIDAAYJOg/HeAAyAQZoDAAABAAhAGkMAAADACkAawwAAAMAIABqDAAAAgATAGwMAAAFABkA6gwAAAMAPQADAAYJOg/HeAAyAQZoDAAABAAhAGkMAAADACkAawwAAAMAIABqDAAAAgATAGwMAAAFABkA6gwAAAMAPQAAAA==.Jolreal:BAABLgAECn8yAAMVAAgJXCBFFACSAghoDAAABwBbAGkMAAAHAFsAawwAAAcAXgBqDAAABwBWAGwMAAAHAEoAbQwAAAQAWADqDAAACABWAG4MAAADADQAFQAHCVAiRRQAkgIHaAwAAAUAWwBpDAAABQBbAGsMAAAFAF4AagwAAAUAVgBsDAAABQBKAG0MAAACAFgA6gwAAAYAVgAMAAgJUBjDCgASAghoDAAAAgBOAGkMAAACAEgAawwAAAIASwBqDAAAAgBMAGwMAAACADAAbQwAAAIAMADqDAAAAgA7AG4MAAADADQAAAA=.',
Ju='Julez:BAAALgAECgYJDwAAAA==.Julezara:BAAALgAECgMJBAAAAA==.Julezdruid:BAAALgADCgMJBQAAAA==.Junkai:BAACLgAFFH8IAAIGAAMJQBS7OQDxAANoDAAABAA/AGkMAAADADMAawwAAAEAKAAGAAMJQBS7OQDxAANoDAAABAA/AGkMAAADADMAawwAAAEAKAAuAAQKfysAAgYACAn+Iy0bAMYCAAYACAn+Iy0bAMYCAAAA.',
Ka='Kathanial:BAAALgADCgUJBgAAAA==.Katiagrimm:BAAALgADCgIJAgAAAA==.Kawi:BAAALgADCgcJBwABLgAECgYJFwALAI8QAA==.',
Ke='Keco:BAAALgAECgQJCQAAAA==.Kelenar:BAAALgAECgMJAwAAAA==.Kennie:BAABLgAECn8dAAMNAAgJaAo1DAAfAQhoDAAABQArAGkMAAAFACAAawwAAAUAGABqDAAAAwAKAGwMAAADABwAbQwAAAIADADqDAAABQAiAG4MAAABAAsADQAICWgKNQwAHwEIaAwAAAQAKwBpDAAABAAgAGsMAAAEABgAagwAAAMACgBsDAAAAwAcAG0MAAACAAwA6gwAAAUAIgBuDAAAAQALABYAAwkgBrUcAI0AA2gMAAABAAwAaQwAAAEAFABrDAAAAQAOAAAA.',
Kl='Kladivo:BAAALgADCgYJBgABLgAECgQJBAAJAAAAAA==.',
Kn='Knorr:BAAALgAECgUJBQAAAA==.',
Ko='Korthaz:BAAALgADCgIJAgAAAA==.',
Kw='Kwansu:BAAALgAECgQJBAAAAA==.',
La='Lahlania:BAAALgAECgYJDQAAAA==.Laura:BAAALgADCgQJBQAAAA==.',
Li='Lilyda:BAAALgADCggJBgAAAA==.',
Lo='Lolann:BAAALgADCgUJCAAAAA==.',
Ly='Lyia:BAAALgADCgEJAQAAAA==.',
Ma='Machette:BAAALgAECgUJEQAAAA==.Mailaria:BAABLgAECn8iAAITAAgJOA+RCQBZAQhoDAAABQAwAGkMAAAFADIAawwAAAUAHQBqDAAABAAyAGwMAAAFAEAAbQwAAAIAGwDqDAAABwArAG4MAAABAAkAEwAICTgPkQkAWQEIaAwAAAUAMABpDAAABQAyAGsMAAAFAB0AagwAAAQAMgBsDAAABQBAAG0MAAACABsA6gwAAAcAKwBuDAAAAQAJAAAA.Majesti:BAAALgADCggJBwAAAA==.Malakar:BAABLgAECn8jAAMXAAcJuRvkFACAAQdoDAAABQBaAGkMAAAGADkAawwAAAYAUABqDAAABQAkAGwMAAAFAC8AbQwAAAIATQDqDAAABgBHABcABwlpF+QUAIABB2gMAAADADkAaQwAAAMAOQBrDAAAAwA4AGoMAAADACQAbAwAAAMALwBtDAAAAgBNAOoMAAADAD4AGAAGCYcZ0AsAagEGaAwAAAIAWgBpDAAAAwAoAGsMAAADAFAAagwAAAIAEgBsDAAAAgArAOoMAAADAEcAAAA=.Malvolio:BAAALgADCgMJAwAAAA==.Mantoecore:BAAALgADCgcJCAAAAA==.Marellaa:BAAALgAECgMJBAAAAA==.Markers:BAAALgADCgIJAgAAAA==.',
Mc='Mcsplatapus:BAAALgAECgUJBAAAAA==.',
Me='Meingsolin:BAAALgAECgYJDwAAAA==.Meseeker:BAAALgADCgEJAQAAAA==.Mezagog:BAAALgADCgcJEAAAAA==.',
Mi='Midknight:BAAALgAECgUJBgAAAA==.Miggylosoh:BAAALgAECgMJBAAAAA==.Minizoomies:BAAALgAECgEJAQAAAA==.',
Mo='Momo:BAAALgADCgkJFgAAAA==.',
My='Mygourdness:BAABLgAECn8VAAIZAAYJ+ATWYwCwAAZoDAAABAAOAGkMAAAEABgAawwAAAQACQBqDAAAAgAGAGwMAAACAA0A6gwAAAUACAAZAAYJ+ATWYwCwAAZoDAAABAAOAGkMAAAEABgAawwAAAQACQBqDAAAAgAGAGwMAAACAA0A6gwAAAUACAAAAA==.Myuk:BAABLgAECn8eAAIMAAgJOB1TCAA8AghoDAAABABPAGkMAAAEAE8AawwAAAQAQABqDAAABABaAGwMAAAFAEQAbQwAAAEATQDqDAAABwBYAG4MAAABAEEADAAICTgdUwgAPAIIaAwAAAQATwBpDAAABABPAGsMAAAEAEAAagwAAAQAWgBsDAAABQBEAG0MAAABAE0A6gwAAAcAWABuDAAAAQBBAAAA.',
Na='Naminay:BAAALgAECgYJDgAAAA==.Narbash:BAAALgAECgQJBAAAAA==.Nasrullah:BAAALgADCgkJDAAAAA==.Natalie:BAAALgAECgEJAQAAAA==.',
Ne='Nekia:BAAALgADCgcJBwAAAA==.Neroz:BAABLgAECn8pAAIRAAgJMRiGHQD0AQhoDAAABwBPAGkMAAAHAEkAawwAAAcAOABqDAAABQAwAGwMAAAFADcAbQwAAAMAPwDqDAAABgA9AG4MAAABACkAEQAICTEYhh0A9AEIaAwAAAcATwBpDAAABwBJAGsMAAAHADgAagwAAAUAMABsDAAABQA3AG0MAAADAD8A6gwAAAYAPQBuDAAAAQApAAAA.Nerppie:BAABLgAECn8kAAIFAAgJUB9BCwB3AghoDAAABgBQAGkMAAAGAE8AawwAAAYAWQBqDAAABABXAGwMAAAEAGEAbQwAAAMANQDqDAAABgBUAG4MAAABAEQABQAICVAfQQsAdwIIaAwAAAYAUABpDAAABgBPAGsMAAAGAFkAagwAAAQAVwBsDAAABABhAG0MAAADADUA6gwAAAYAVABuDAAAAQBEAAAA.Nevershark:BAAALgAECgUJBQAAAA==.',
Ni='Nightfallz:BAAALgADCgUJBQAAAA==.Nina:BAABLgAECn8YAAIGAAcJdRpRTwD0AQdoDAAABABEAGkMAAAEAFAAawwAAAQAVABqDAAAAQAyAGwMAAABACcA6gwAAAYATwBuDAAABAA2AAYABwl1GlFPAPQBB2gMAAAEAEQAaQwAAAQAUABrDAAABABUAGoMAAABADIAbAwAAAEAJwDqDAAABgBPAG4MAAAEADYAAAA=.Nixah:BAAALgAECgUJDQAAAA==.',
Nk='Nkript:BAABLgAECn8aAAMHAAcJehXfMgCdAQdoDAAABQA+AGkMAAAEAEkAawwAAAQAQABqDAAABAA7AGwMAAAEADkA6gwAAAQAKQBuDAAAAQAeAAcABwl6Fd8yAJ0BB2gMAAACAD4AaQwAAAMASQBrDAAAAwBAAGoMAAADADsAbAwAAAMAOQDqDAAAAwApAG4MAAABAB4AFQAGCaYIiU8AEQEGaAwAAAMAHABpDAAAAQAFAGsMAAABAB0AagwAAAEAFwBsDAAAAQATAOoMAAABABsAAAA=.',
No='Nortel:BAAALgAECgYJDgAAAA==.',
Oh='Ohgourdness:BAAALgADCgcJBwABLgAECgYJFQAZAPgEAA==.',
On='Onari:BAABLgAECn8hAAIBAAgJsR0kCACFAghoDAAABQBGAGkMAAAFAFQAawwAAAUAUQBqDAAABABSAGwMAAAFAEEAbQwAAAEAOgDqDAAABwBjAG4MAAABAEIAAQAICbEdJAgAhQIIaAwAAAUARgBpDAAABQBUAGsMAAAFAFEAagwAAAQAUgBsDAAABQBBAG0MAAABADoA6gwAAAcAYwBuDAAAAQBCAAAA.',
Or='Orious:BAAALgADCgYJBgAAAA==.',
Pa='Pandagang:BAAALgADCgQJBQAAAA==.',
Pe='Peezee:BAAALgAECgUJCQAAAA==.Perce:BAABLgAECn8eAAIFAAgJ9iAXBQDvAghoDAAABgBHAGkMAAAEAE4AawwAAAQAUQBqDAAABABeAGwMAAAEAFoAbQwAAAIAVQDqDAAABQBbAG4MAAABAFEABQAICfYgFwUA7wIIaAwAAAYARwBpDAAABABOAGsMAAAEAFEAagwAAAQAXgBsDAAABABaAG0MAAACAFUA6gwAAAUAWwBuDAAAAQBRAAAA.Peyotte:BAABLgAECn8VAAIaAAgJfR8aBgBMAghoDAAABABVAGkMAAAEAFgAawwAAAMAUwBqDAAAAgBUAGwMAAACAFoAbQwAAAEAOADqDAAABABIAG4MAAABAFYAGgAICX0fGgYATAIIaAwAAAQAVQBpDAAABABYAGsMAAADAFMAagwAAAIAVABsDAAAAgBaAG0MAAABADgA6gwAAAQASABuDAAAAQBWAAEuAAQKCQkgABsAwR8A.',
Pf='Pfemme:BAABLgAECn8dAAIHAAgJaRVVJgDWAQhoDAAABABTAGkMAAAEAC4AawwAAAQANQBqDAAABAAsAGwMAAAFAE4AbQwAAAIAFADqDAAAAwA1AG4MAAADADAABwAICWkVVSYA1gEIaAwAAAQAUwBpDAAABAAuAGsMAAAEADUAagwAAAQALABsDAAABQBOAG0MAAACABQA6gwAAAMANQBuDAAAAwAwAAAA.',
Ps='Psych:BAAALgADCgYJBgAAAA==.',
Pu='Purian:BAAALgADCgUJCAAAAA==.',
Ra='Rami:BAAALgADCgYJBgAAAA==.',
Re='Repello:BAAALgAECgYJBwAAAA==.Reyaieleron:BAAALgAECgQJCQAAAA==.',
Ri='Ricky:BAAALgADCgEJAQAAAA==.Rivenaer:BAABLgAECn8vAAIcAAkJBQ+LDgC2AQloDAAABwA1AGkMAAAHACsAawwAAAcAOABqDAAABgA0AGwMAAAFABgAbQwAAAQAGQDqDAAABgAzAG4MAAAEABYAbwwAAAEAHQAcAAkJBQ+LDgC2AQloDAAABwA1AGkMAAAHACsAawwAAAcAOABqDAAABgA0AGwMAAAFABgAbQwAAAQAGQDqDAAABgAzAG4MAAAEABYAbwwAAAEAHQAAAA==.',
Ru='Ruindsoul:BAAALgADCgcJCwAAAA==.Ruka:BAAALgADCgEJAQAAAA==.Runearne:BAAALgAECgIJAgAAAA==.Rustymark:BAAALgAFFAEJAQAAAA==.',
Sc='Scaletal:BAAALgAECgUJBQAAAA==.Schmetzy:BAAALgAECgYJBwAAAA==.Schmezzy:BAABLgAECn8aAAIOAAgJtx0aHwAsAghoDAAABABTAGkMAAADAF4AawwAAAQAPQBqDAAAAwBQAGwMAAAEAEAAbQwAAAIAVgDqDAAABQBIAG4MAAABAEUADgAICbcdGh8ALAIIaAwAAAQAUwBpDAAAAwBeAGsMAAAEAD0AagwAAAMAUABsDAAABABAAG0MAAACAFYA6gwAAAUASABuDAAAAQBFAAAA.',
Se='Sealalicious:BAABLgAECn8pAAIdAAgJ1BfqCwCXAQhoDAAABwBOAGkMAAAHAEEAawwAAAcATgBqDAAABQAyAGwMAAAFAEMAbQwAAAMAJwDqDAAABgBCAG4MAAABAB0AHQAICdQX6gsAlwEIaAwAAAcATgBpDAAABwBBAGsMAAAHAE4AagwAAAUAMgBsDAAABQBDAG0MAAADACcA6gwAAAYAQgBuDAAAAQAdAAAA.Seenaa:BAAALgADCgcJEAAAAA==.',
Sh='Shallot:BAAALgADCgMJBQAAAA==.Shammywow:BAAALgAECgUJDQAAAA==.Sharkzilla:BAAALgAECgkJEgAAAA==.Shauray:BAAALgADCgUJCAAAAA==.Shine:BAAALgAECgUJEwAAAA==.Shrub:BAAALgADCgcJBwABLgAFFAgJGQAeAKghAA==.',
Sl='Sloppy:BAAALgADCgMJAwAAAA==.',
Sm='Smoo:BAAALgADCgkJJAAAAA==.',
Sn='Snø:BAAALgAECgYJDQAAAA==.',
So='Sobol:BAAALgAFFAEJAgAAAA==.Soggyaugi:BAAALgAECgUJBQAAAA==.Solbinder:BAAALgADCgIJAgAAAA==.Soraa:BAEALgAECgUJDwABLgAECgcJEQAJAAAAAA==.',
St='Starlethia:BAAALgAECggJDAAAAA==.',
Su='Sunshine:BAAALgADCgcJDAAAAA==.Sunwälker:BAAALgADCgQJBAAAAA==.',
Sy='Sybelin:BAAALgADCgMJAwAAAA==.',
Ta='Tallchief:BAAALgAECgMJBwAAAA==.Tankufrdying:BAAALgADCgQJBgAAAA==.Tavarien:BAAALgADCgEJAQAAAA==.',
Te='Tenjo:BAAALgADCgMJAwAAAA==.Terrier:BAAALgAECgEJAQAAAA==.',
Th='Thaerdran:BAABLgAECn8dAAIPAAcJoBeHEQB7AQdoDAAABQAyAGkMAAAEAEUAawwAAAQARwBqDAAABAAnAGwMAAAFADAA6gwAAAQAQwBuDAAAAwA3AA8ABwmgF4cRAHsBB2gMAAAFADIAaQwAAAQARQBrDAAABABHAGoMAAAEACcAbAwAAAUAMADqDAAABABDAG4MAAADADcAAAA=.',
Ti='Tirriel:BAAALgADCgMJAwAAAA==.',
To='Toess:BAAALgAECgEJAQAAAA==.Tonjuren:BAAALgAECgMJBwABLgAECgYJDwAJAAAAAA==.',
Tr='Trublood:BAAALgAECgYJDgAAAA==.',
Tw='Twister:BAAALgAECgQJDwAAAA==.',
Ty='Tyrra:BAAALgADCgMJAwAAAA==.',
Uk='Ukeenonme:BAAALgADCgQJBgAAAA==.',
Us='Usorloups:BAABLgAECn8gAAIbAAkJwR/4BADAAgloDAAABABUAGkMAAAEAFIAawwAAAMAWwBqDAAABABKAGwMAAADAFcAbQwAAAMAYgDqDAAABgBVAG4MAAAEAFsAbwwAAAEAHQAbAAkJwR/4BADAAgloDAAABABUAGkMAAAEAFIAawwAAAMAWwBqDAAABABKAGwMAAADAFcAbQwAAAMAYgDqDAAABgBVAG4MAAAEAFsAbwwAAAEAHQAAAA==.',
Va='Valstad:BAAALgAECgYJBgAAAA==.',
Ve='Velonys:BAABLgAECn8oAAQNAAkJvB/XBACPAgloDAAABwBgAGkMAAAGAFwAawwAAAUAVwBqDAAABQBOAGwMAAAFAFsAbQwAAAMARwDqDAAABQBQAG4MAAACAFAAbwwAAAIAMQANAAgJiCHXBACPAghoDAAAAgBgAGkMAAADAFwAawwAAAQAVwBqDAAABQBOAGwMAAAEAFsAbQwAAAMARwDqDAAAAgBQAG4MAAABAFAAHwAGCUkVzEsAWAEGaAwAAAQAQQBpDAAAAgBKAGwMAAABADgA6gwAAAIANwBuDAAAAQAaAG8MAAACADEAFgAECSwgGwgATwEEaAwAAAEAXABpDAAAAQBTAGsMAAABAE4A6gwAAAEASgAAAA==.Velus:BAAALgAECgQJBAAAAA==.',
Vi='Victory:BAAALgAECgEJAQAAAA==.Vintar:BAAALgADCgMJAwAAAA==.',
Vy='Vyu:BAAALgAECgkJAwAAAA==.',
Wa='Wanayu:BAABLgAECn8hAAINAAgJrRkAAwAcAghoDAAABQBOAGkMAAAFAEYAawwAAAUAOQBqDAAABAA5AGwMAAAFAEsAbQwAAAEAFgDqDAAABwBTAG4MAAABAEgADQAICa0ZAAMAHAIIaAwAAAUATgBpDAAABQBGAGsMAAAFADkAagwAAAQAOQBsDAAABQBLAG0MAAABABYA6gwAAAcAUwBuDAAAAQBIAAAA.Wanweasley:BAAALgAECgUJCgAAAA==.',
We='Weeab:BAAALgADCgEJAQAAAA==.Weezlee:BAAALgAECgQJBAAAAA==.Weh:BAABLgAECn8YAAIDAAkJryLnDQDGAgloDAAABABfAGkMAAAEAGMAawwAAAMAYwBqDAAAAwBiAGwMAAACAGMAbQwAAAIATADqDAAABABjAG4MAAABAEkAbwwAAAEAQwADAAkJryLnDQDGAgloDAAABABfAGkMAAAEAGMAawwAAAMAYwBqDAAAAwBiAGwMAAACAGMAbQwAAAIATADqDAAABABjAG4MAAABAEkAbwwAAAEAQwAAAA==.',
Wi='Wickedsham:BAAALgADCgIJAgAAAA==.Wintermourne:BAAALgAECgcJDgAAAA==.Wizagon:BAAALgAECggJEgAAAA==.',
Wo='Woodsy:BAABLgAECn8hAAIgAAgJmht7BACBAghoDAAABQBQAGkMAAAFAFQAawwAAAUAPwBqDAAABABAAGwMAAAFADwAbQwAAAIAMADqDAAABgBhAG4MAAABAEEAIAAICZobewQAgQIIaAwAAAUAUABpDAAABQBUAGsMAAAFAD8AagwAAAQAQABsDAAABQA8AG0MAAACADAA6gwAAAYAYQBuDAAAAQBBAAAA.Wounded:BAAALgAECgEJAQAAAA==.Woundliquor:BAAALgAECgcJCAAAAA==.',
Wu='Wuinn:BAACLgAFFH8KAAIZAAQJ5hHQCgAvAQRoDAAABAA+AGkMAAACACUAawwAAAIAGADqDAAAAgA6ABkABAnmEdAKAC8BBGgMAAAEAD4AaQwAAAIAJQBrDAAAAgAYAOoMAAACADoALgAECn8xAAMZAAkJCyDeDwC5AgAZAAkJCyDeDwC5AgAQAAcJUhjxCQCvAQAAAA==.',
Xe='Xemnas:BAABLgAECn8mAAQOAAcJ/wxTWABQAQdoDAAACAAqAGkMAAAIAB8AawwAAAcAEwBqDAAABgAbAGwMAAAEACYAbQwAAAEAHADqDAAABAAnAA4ABwn/DFNYAFABB2gMAAAIACoAaQwAAAcAHwBrDAAABgATAGoMAAAGABsAbAwAAAQAJgBtDAAAAQAcAOoMAAAEACcAIQABCbQLWxwAMgABaQwAAAEAHQAPAAEJqgFKRQAcAAFrDAAAAQAEAAAA.',
Ya='Yawnday:BAAALgADCgUJCAAAAA==.',
Za='Zaryala:BAAALgADCgkJKAAAAA==.',
Ze='Zenshift:BAAALgAECgMJBgAAAA==.',
Zy='Zynthia:BAABLgAECn8nAAIOAAgJYiQACQDnAghoDAAABwBcAGkMAAAHAGIAawwAAAcAYQBqDAAABABjAGwMAAAEAF0AbQwAAAMAXwDqDAAABgBgAG4MAAABAE4ADgAICWIkAAkA5wIIaAwAAAcAXABpDAAABwBiAGsMAAAHAGEAagwAAAQAYwBsDAAABABdAG0MAAADAF8A6gwAAAYAYABuDAAAAQBOAAAA.',
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
