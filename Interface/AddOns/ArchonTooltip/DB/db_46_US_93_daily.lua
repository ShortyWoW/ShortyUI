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

local lookup = {'Priest-Holy','Priest-Shadow','Mage-Frost','Warrior-Fury','Paladin-Holy','Hunter-BeastMastery','Paladin-Retribution','Warrior-Arms','Unknown-Unknown','Druid-Balance','Shaman-Enhancement','Hunter-Survival','Warlock-Destruction','DeathKnight-Unholy','DeathKnight-Blood','Druid-Guardian','DemonHunter-Devourer','Monk-Brewmaster','DemonHunter-Vengeance','Monk-Windwalker','Hunter-Marksmanship','Warlock-Affliction','Rogue-Subtlety','Rogue-Assassination','Druid-Restoration','Warrior-Protection','Shaman-Elemental','DemonHunter-Havoc','Paladin-Protection','Priest-Discipline','Warlock-Demonology','Evoker-Preservation','DeathKnight-Frost',}
local provider = {region='US',realm='Farstriders',name='US',type='daily',zone=46,date='2026-05-10',data={Ab='Absolon:BAAALgAECgYJDQAAAA==.',
Ae='Aelar:BAAALgADCgEJAQAAAA==.Aellynn:BAABLgAECn8jAAMBAAgJ/Am2IQBDAQhoDAAABwAYAGkMAAAGACgAawwAAAYAHgBqDAAABQAQAGwMAAAEACQAbQwAAAEAGADqDAAABQAaAG4MAAABAAQAAQAICfwJtiEAQwEIaAwAAAYAGABpDAAABgAoAGsMAAAGAB4AagwAAAUAEABsDAAABAAkAG0MAAABABgA6gwAAAUAGgBuDAAAAQAEAAIAAQleACdsABcAAWgMAAABAAAAAAA=.Aerir:BAACLgAFFH8MAAIDAAQJYQqPPQAqAQRoDAAABQAlAGkMAAAEADUAawwAAAEABgDqDAAAAgAIAAMABAlhCo89ACoBBGgMAAAFACUAaQwAAAQANQBrDAAAAQAGAOoMAAACAAgALgAECn8oAAIDAAgJ9BvdWwAmAgADAAgJ9BvdWwAmAgAAAA==.Aerithar:BAAALgADCgEJAQAAAA==.Aesirr:BAAALgAECgUJCgAAAA==.',
Al='Alandris:BAABLgAECn8WAAIEAAcJEwSZPQDUAAdoDAAABAALAGkMAAADAAgAawwAAAMADgBqDAAAAwAKAGwMAAAEAAoA6gwAAAMACABuDAAAAgAIAAQABwkTBJk9ANQAB2gMAAAEAAsAaQwAAAMACABrDAAAAwAOAGoMAAADAAoAbAwAAAQACgDqDAAAAwAIAG4MAAACAAgAAAA=.Alerya:BAAALgAECgEJAQAAAA==.Alinie:BAABLgAECn8WAAIFAAgJCiVZBwD3AghoDAAAAgBfAGkMAAAEAGEAawwAAAQAYwBqDAAAAgBhAGwMAAACAGEAbQwAAAIAYwDqDAAABQBcAG4MAAABAE8ABQAICQolWQcA9wIIaAwAAAIAXwBpDAAABABhAGsMAAAEAGMAagwAAAIAYQBsDAAAAgBhAG0MAAACAGMA6gwAAAUAXABuDAAAAQBPAAAA.Alleriya:BAABLgAECn8bAAIGAAcJyApfSgAvAQdoDAAABQAWAGkMAAAFABsAawwAAAQAFABqDAAABABGAGwMAAADACYAbQwAAAEAFQDqDAAABQAiAAYABwnICl9KAC8BB2gMAAAFABYAaQwAAAUAGwBrDAAABAAUAGoMAAAEAEYAbAwAAAMAJgBtDAAAAQAVAOoMAAAFACIAAAA=.Allison:BAAALgADCgMJAwAAAA==.Alltheheals:BAAALgAECggJDAAAAA==.Altruis:BAAALgADCgIJAgABLgAFFAQJCgAHAB0gAA==.',
Am='Amarawyn:BAAALgAECgYJDQAAAA==.Ambulance:BAAALgADCgEJAQAAAA==.Amoragan:BAABLgAECn8bAAMIAAgJexlDCwCeAQhoDAAABAA+AGkMAAAEAE0AawwAAAQAMwBqDAAAAwBNAGwMAAAEAEsAbQwAAAEAMgDqDAAABgBJAG4MAAABAEIABAAHCa4X2TgAwwEHaAwAAAIANABpDAAAAgBNAGsMAAACADMAagwAAAEARwBsDAAAAgBLAG0MAAABADIA6gwAAAQAOAAIAAcJnxZDCwCeAQdoDAAAAgA+AGkMAAACADMAawwAAAIAIABqDAAAAgBNAGwMAAACADwA6gwAAAIASQBuDAAAAQBCAAAA.',
An='Andriela:BAAALgAECgYJDQAAAA==.',
Ap='Apexy:BAAALgAECgUJDgAAAA==.',
Ar='Arashikaze:BAAALgAECgcJDgAAAA==.',
Au='Augidget:BAABLgAECn8cAAICAAgJDhVPEADZAQhoDAAABAA1AGkMAAAEADYAawwAAAQAPABqDAAAAwBSAGwMAAAEAEYAbQwAAAIAEgDqDAAABgBQAG4MAAABACcAAgAICQ4VTxAA2QEIaAwAAAQANQBpDAAABAA2AGsMAAAEADwAagwAAAMAUgBsDAAABABGAG0MAAACABIA6gwAAAYAUABuDAAAAQAnAAAA.',
Av='Avgo:BAAALgAECgMJAwABLgAECgYJDgAJAAAAAA==.Avilen:BAABLgAECn8VAAIGAAgJJQgjQwBGAQhoDAAAAwAkAGkMAAADABsAawwAAAMAIABqDAAAAwAaAGwMAAADAAUAbQwAAAIABwDqDAAAAwATAG4MAAABABEABgAICSUII0MARgEIaAwAAAMAJABpDAAAAwAbAGsMAAADACAAagwAAAMAGgBsDAAAAwAFAG0MAAACAAcA6gwAAAMAEwBuDAAAAQARAAAA.Aviris:BAAALgAECgYJBgABLgAECggJCgAJAAAAAA==.',
Ay='Ayuzi:BAAALgADCgEJAQAAAA==.',
Ba='Badsilk:BAAALgAECgYJEwAAAA==.Balinteen:BAAALgAECgYJDQAAAA==.Barktwain:BAAALgAECgQJBAAAAA==.Bastael:BAABLgAECn8cAAIFAAgJBCQWAwAfAwhoDAAABABaAGkMAAAEAGEAawwAAAQAXABqDAAAAwBKAGwMAAAEAF4AbQwAAAIAXADqDAAABgBiAG4MAAABAF8ABQAICQQkFgMAHwMIaAwAAAQAWgBpDAAABABhAGsMAAAEAFwAagwAAAMASgBsDAAABABeAG0MAAACAFwA6gwAAAYAYgBuDAAAAQBfAAAA.Bayus:BAAALgADCgIJAgAAAA==.',
Be='Bendyy:BAABLgAECn8bAAIDAAgJfB2lIAAwAghoDAAABABMAGkMAAAEAFIAawwAAAMATABqDAAAAwBdAGwMAAAEAFEAbQwAAAIAOQDqDAAABgBaAG4MAAABAD4AAwAICXwdpSAAMAIIaAwAAAQATABpDAAABABSAGsMAAADAEwAagwAAAMAXQBsDAAABABRAG0MAAACADkA6gwAAAYAWgBuDAAAAQA+AAAA.',
Bh='Bharani:BAAALgADCgcJBwAAAA==.',
Bi='Biopaindr:BAABLgAECn8ZAAIKAAcJ/RJyGgBxAQdoDAAABQBFAGkMAAAFADQAawwAAAQAMwBqDAAAAwAkAGwMAAADADEAbQwAAAEAEwDqDAAABAAxAAoABwn9EnIaAHEBB2gMAAAFAEUAaQwAAAUANABrDAAABAAzAGoMAAADACQAbAwAAAMAMQBtDAAAAQATAOoMAAAEADEAAAA=.Bitxi:BAAALgAECgUJDgAAAA==.',
Bo='Boldbane:BAAALgAECgQJBgAAAA==.Boozo:BAAALgAECgIJBAAAAA==.',
Br='Brocklee:BAABLgAECn8XAAILAAYJjxBYDgAqAQZoDAAABQAxAGkMAAAFAC8AawwAAAUANwBqDAAAAwAvAGwMAAABABsA6gwAAAQAHwALAAYJjxBYDgAqAQZoDAAABQAxAGkMAAAFAC8AawwAAAUANwBqDAAAAwAvAGwMAAABABsA6gwAAAQAHwAAAA==.',
Bu='Bubbaman:BAAALgAECgUJDQAAAA==.Burda:BAABLgAECn8aAAIMAAkJcxWwBwA2AgloDAAABQBBAGkMAAAEADcAawwAAAQAQQBqDAAAAwA5AGwMAAADADcAbQwAAAEAKQDqDAAAAwA6AG4MAAABACoAbwwAAAIANgAMAAkJcxWwBwA2AgloDAAABQBBAGkMAAAEADcAawwAAAQAQQBqDAAAAwA5AGwMAAADADcAbQwAAAEAKQDqDAAAAwA6AG4MAAABACoAbwwAAAIANgAAAA==.',
Ca='Caenae:BAAALgAECgMJBwAAAA==.Cattlerage:BAAALgADCgUJBQABLgAFFAQJCgAHAB0gAA==.',
Ce='Celestial:BAAALgAECgEJAgAAAA==.',
Ch='Chandris:BAAALgADCgIJAgAAAA==.Chrissy:BAAALgAECgYJBgAAAA==.',
Ci='Ciannie:BAAALgADCgIJAgAAAA==.',
Cl='Clamor:BAAALgAECgQJCgAAAA==.',
Co='Coletrain:BAAALgAECgUJCgAAAA==.Corri:BAAALgAECgMJBwAAAA==.Corriandis:BAAALgAECgMJAwAAAA==.',
Cr='Credon:BAAALgAECgUJDgAAAA==.Crixxe:BAAALgAECgQJBwAAAA==.',
Dh='Dhellia:BAAALgAECgYJCgAAAA==.',
Di='Dierlyn:BAAALgAECgYJDQAAAA==.Dirtytaters:BAAALgAECgUJDgAAAA==.Divastating:BAAALgAECgEJAQABLgAECgIJBQAJAAAAAA==.',
Do='Doró:BAAALgADCgQJBgAAAA==.',
Dt='Dtothed:BAAALgADCgQJCwAAAA==.',
Dw='Dwarfred:BAAALgAECgYJCgAAAA==.Dwimor:BAABLgAECn8ZAAIGAAYJBBCWVwAKAQZoDAAABgAlAGkMAAAFADcAawwAAAUAMgBqDAAAAgAaAGwMAAACACEA6gwAAAUAHAAGAAYJBBCWVwAKAQZoDAAABgAlAGkMAAAFADcAawwAAAUAMgBqDAAAAgAaAGwMAAACACEA6gwAAAUAHAAAAA==.',
['Dô']='Dôro:BAAALgADCggJDQABLgAECgkJGwANAMYdAA==.',
Ea='Earadin:BAAALgAECgMJAwAAAA==.',
Ec='Ecthelorn:BAAALgADCgMJBAAAAA==.',
El='Elasong:BAAALgAECgQJCQAAAA==.Elmö:BAAALgAECgUJBQAAAA==.Elrarebriel:BAAALgADCggJDAAAAA==.',
Em='Emberstorm:BAAALgADCgQJBAAAAA==.',
Fa='Fairamir:BAAALgADCgIJAgAAAA==.Fayona:BAAALgADCgUJBwAAAA==.',
Fe='Felystra:BAAALgAECgIJBQAAAA==.',
Fi='Fizzlyn:BAACLgAFFH8MAAMOAAQJFRmkJQBZAQRoDAAABQBaAGkMAAAEADgAawwAAAEAHQDqDAAAAgBQAA4ABAndGKQlAFkBBGgMAAAEAFgAaQwAAAQAOABrDAAAAQAdAOoMAAACAFAADwABCWEjeRwAZQABaAwAAAEAWgAuAAQKfykAAg4ACAnuIqsuAH0CAA4ACAnuIqsuAH0CAAAA.',
Fl='Fluffsmcgee:BAAALgADCgkJDgAAAA==.',
Fr='Fredrick:BAAALgADCgcJCAAAAA==.Frieza:BAAALgAECgEJAQAAAA==.',
Fu='Furr:BAAALgAECgEJAQABLgAFFAUJFQADAH8ZAA==.',
Ga='Galdora:BAAALgADCgcJEQAAAA==.Galedriel:BAAALgAECgMJBAAAAA==.',
Gh='Ghosthunter:BAAALgADCgkJDwAAAA==.',
Gi='Giizmo:BAAALgAECgEJAQAAAA==.',
Gr='Gragdal:BAAALgADCgQJBAAAAA==.Grandpa:BAAALgADCgkJGQABLgAECgQJEAAJAAAAAA==.Grewsöm:BAABLgAECn8XAAMOAAgJxCOhEACEAghoDAAABQBgAGkMAAAEAGIAawwAAAMAYABqDAAAAwBaAGwMAAACAFIAbQwAAAEAUADqDAAAAwBbAG4MAAACAF4ADgAICcQjoRAAhAIIaAwAAAIAYABpDAAAAgBiAGsMAAACAGAAagwAAAIAWgBsDAAAAgBSAG0MAAABAFAA6gwAAAIAWwBuDAAAAgBeAA8ABQmqHjcSAFwBBWgMAAADAFYAaQwAAAIARgBrDAAAAQBRAGoMAAABAFQA6gwAAAEATAABLgAFFAQJCgAHAB0gAA==.Grotusque:BAABLgAECn8kAAIQAAgJrxO9CgCDAQhoDAAABwBCAGkMAAAGAD4AawwAAAYAMwBqDAAABQAuAGwMAAAFACQAbQwAAAEALgDqDAAABQA8AG4MAAABABwAEAAICa8TvQoAgwEIaAwAAAcAQgBpDAAABgA+AGsMAAAGADMAagwAAAUALgBsDAAABQAkAG0MAAABAC4A6gwAAAUAPABuDAAAAQAcAAAA.',
Gu='Gullugren:BAAALgAECgkJCAAAAA==.Gutterdoxy:BAAALgADCgMJAwAAAA==.',
Ha='Hadiirn:BAABLgAECn8dAAIRAAYJ9RD9TwASAQZoDAAABQAoAGkMAAAFACkAawwAAAYAIgBqDAAABQBIAGwMAAADACgA6gwAAAUAOgARAAYJ9RD9TwASAQZoDAAABQAoAGkMAAAFACkAawwAAAYAIgBqDAAABQBIAGwMAAADACgA6gwAAAUAOgAAAA==.Haiiro:BAABLgAECn8cAAISAAgJeRXBEQC+AQhoDAAABAA4AGkMAAAEAEoAawwAAAQAPABqDAAAAwBGAGwMAAAEADcAbQwAAAIAHwDqDAAABgA2AG4MAAABADIAEgAICXkVwREAvgEIaAwAAAQAOABpDAAABABKAGsMAAAEADwAagwAAAMARgBsDAAABAA3AG0MAAACAB8A6gwAAAYANgBuDAAAAQAyAAAA.Hardim:BAAALgAECgYJDAAAAA==.Hardwood:BAAALgADCgMJAwAAAA==.Hargen:BAAALgAECgIJAgAAAA==.Harknesse:BAAALgAECgUJDgAAAA==.Hatermage:BAAALgAECgYJDwAAAA==.Hazzrel:BAAALgAECgYJDQAAAA==.',
He='Heftychi:BAAALgAECgIJAgAAAA==.Heftydh:BAABLgAECn8aAAITAAcJCR4ZBQDVAQdoDAAABQBWAGkMAAAFAFEAawwAAAQAUQBqDAAABABVAGwMAAADAE4AbQwAAAEAKgDqDAAABABbABMABwkJHhkFANUBB2gMAAAFAFYAaQwAAAUAUQBrDAAABABRAGoMAAAEAFUAbAwAAAMATgBtDAAAAQAqAOoMAAAEAFsAAAA=.Hewhospins:BAABLgAECn8kAAMSAAgJQxLyFACbAQhoDAAABgBXAGkMAAAGAEUAawwAAAYALwBqDAAABAAkAGwMAAAEABsAbQwAAAMAIgDqDAAABgAtAG4MAAABAA4AEgAICUMS8hQAmwEIaAwAAAYAVwBpDAAABgBFAGsMAAAGAC8AagwAAAQAJABsDAAABAAbAG0MAAACACIA6gwAAAYALQBuDAAAAQAOABQAAQloCh9kADAAAW0MAAABABoAAAA=.',
Hy='Hydraulicman:BAAALgAECgEJAQAAAA==.Hyzer:BAAALgAECgYJBgABLgAECggJDAAJAAAAAA==.',
Id='Idget:BAAALgADCgEJAQAAAA==.',
Ig='Igknight:BAAALgAECgEJAQAAAA==.',
Ja='Jacksmite:BAAALgADCgEJAQAAAA==.Jasmirana:BAAALgAECgYJDAAAAA==.',
Je='Jemano:BAAALgADCgEJAQAAAA==.',
Ji='Jirenr:BAABLgAECn8VAAIUAAYJYwYCMADQAAZoDAAABAAOAGkMAAAEABEAawwAAAQAEwBqDAAABAATAGwMAAACABUA6gwAAAMACQAUAAYJYwYCMADQAAZoDAAABAAOAGkMAAAEABEAawwAAAQAEwBqDAAABAATAGwMAAACABUA6gwAAAMACQAAAA==.',
Jo='Jolage:BAABLgAECn8UAAIDAAYJOg+6bwA4AQZoDAAABAAhAGkMAAADACkAawwAAAMAIABqDAAAAgATAGwMAAAFABkA6gwAAAMAPQADAAYJOg+6bwA4AQZoDAAABAAhAGkMAAADACkAawwAAAMAIABqDAAAAgATAGwMAAAFABkA6gwAAAMAPQAAAA==.Jolreal:BAABLgAECn8yAAMVAAgJXCBDFACSAghoDAAABwBbAGkMAAAHAFsAawwAAAcAXgBqDAAABwBWAGwMAAAHAEoAbQwAAAQAWADqDAAACABWAG4MAAADADQAFQAHCVAiQxQAkgIHaAwAAAUAWwBpDAAABQBbAGsMAAAFAF4AagwAAAUAVgBsDAAABQBKAG0MAAACAFgA6gwAAAYAVgAMAAgJUBhnCQAXAghoDAAAAgBOAGkMAAACAEgAawwAAAIASwBqDAAAAgBMAGwMAAACADAAbQwAAAIAMADqDAAAAgA7AG4MAAADADQAAAA=.',
Ju='Julez:BAAALgAECgYJDwAAAA==.Julezara:BAAALgAECgMJBAAAAA==.Julezdruid:BAAALgADCgIJAgAAAA==.Junkai:BAACLgAFFH8IAAIHAAMJQBSWNAD0AANoDAAABAA/AGkMAAADADMAawwAAAEAKAAHAAMJQBSWNAD0AANoDAAABAA/AGkMAAADADMAawwAAAEAKAAuAAQKfykAAgcACAn+IysbAMYCAAcACAn+IysbAMYCAAAA.',
Ka='Kathanial:BAAALgADCgUJBgAAAA==.Katiagrimm:BAAALgADCgIJAgAAAA==.Kawi:BAAALgADCgcJBwABLgAECgYJFwALAI8QAA==.',
Ke='Keco:BAAALgAECgIJBQAAAA==.Kelenar:BAAALgAECgMJAwAAAA==.Kennie:BAABLgAECn8dAAMNAAgJaAqiCgAzAQhoDAAABQArAGkMAAAFACAAawwAAAUAGABqDAAAAwAKAGwMAAADABwAbQwAAAIADADqDAAABQAiAG4MAAABAAsADQAICWgKogoAMwEIaAwAAAQAKwBpDAAABAAgAGsMAAAEABgAagwAAAMACgBsDAAAAwAcAG0MAAACAAwA6gwAAAUAIgBuDAAAAQALABYAAwkgBrUcAI0AA2gMAAABAAwAaQwAAAEAFABrDAAAAQAOAAAA.',
Kl='Kladivo:BAAALgADCgYJBgABLgAECgEJAQAJAAAAAA==.',
Kn='Knorr:BAAALgAECgUJBQAAAA==.',
Ko='Korthaz:BAAALgADCgIJAgAAAA==.',
Kw='Kwansu:BAAALgAECgEJAQAAAA==.',
La='Lahlania:BAAALgAECgYJDQAAAA==.Laura:BAAALgADCgQJBQAAAA==.',
Li='Lilyda:BAAALgADCggJBgAAAA==.',
Lo='Lolann:BAAALgADCgUJCAAAAA==.',
Ly='Lyia:BAAALgADCgEJAQAAAA==.',
Ma='Machette:BAAALgAECgUJDQAAAA==.Mailaria:BAABLgAECn8cAAITAAgJDQ76CQA+AQhoDAAABAAwAGkMAAAEADIAawwAAAQAHQBqDAAAAwAyAGwMAAAEACsAbQwAAAIAGwDqDAAABgArAG4MAAABAAkAEwAICQ0O+gkAPgEIaAwAAAQAMABpDAAABAAyAGsMAAAEAB0AagwAAAMAMgBsDAAABAArAG0MAAACABsA6gwAAAYAKwBuDAAAAQAJAAAA.Majesti:BAAALgADCggJBwAAAA==.Malakar:BAABLgAECn8jAAMXAAcJuRsnEwCGAQdoDAAABQBaAGkMAAAGADkAawwAAAYAUABqDAAABQAkAGwMAAAFAC8AbQwAAAIATQDqDAAABgBHABcABwlpFycTAIYBB2gMAAADADkAaQwAAAMAOQBrDAAAAwA4AGoMAAADACQAbAwAAAMALwBtDAAAAgBNAOoMAAADAD4AGAAGCYcZ0AsAagEGaAwAAAIAWgBpDAAAAwAoAGsMAAADAFAAagwAAAIAEgBsDAAAAgArAOoMAAADAEcAAAA=.Malvolio:BAAALgADCgMJAwAAAA==.Mantoecore:BAAALgADCgcJCAAAAA==.Marellaa:BAAALgAECgMJBAAAAA==.Markers:BAAALgADCgIJAgAAAA==.',
Mc='Mcsplatapus:BAAALgAECgUJBAAAAA==.',
Me='Meingsolin:BAAALgAECgYJDwAAAA==.Meseeker:BAAALgADCgEJAQAAAA==.Mezagog:BAAALgADCgcJEAAAAA==.',
Mi='Midknight:BAAALgAECgUJBgAAAA==.Minizoomies:BAAALgAECgEJAQAAAA==.',
Mo='Momo:BAAALgADCgkJFgAAAA==.',
My='Mygourdness:BAABLgAECn8VAAIZAAYJ+ATSXgCwAAZoDAAABAAOAGkMAAAEABgAawwAAAQACQBqDAAAAgAGAGwMAAACAA0A6gwAAAUACAAZAAYJ+ATSXgCwAAZoDAAABAAOAGkMAAAEABgAawwAAAQACQBqDAAAAgAGAGwMAAACAA0A6gwAAAUACAAAAA==.Myuk:BAABLgAECn8YAAIMAAgJOB1GCAArAghoDAAAAwBPAGkMAAADAE8AawwAAAMAQABqDAAAAwBaAGwMAAAEAEQAbQwAAAEATQDqDAAABgBYAG4MAAABAEEADAAICTgdRggAKwIIaAwAAAMATwBpDAAAAwBPAGsMAAADAEAAagwAAAMAWgBsDAAABABEAG0MAAABAE0A6gwAAAYAWABuDAAAAQBBAAAA.',
Na='Naminay:BAAALgAECgYJDgAAAA==.Narbash:BAAALgAECgQJBAAAAA==.Nasrullah:BAAALgADCgkJDAAAAA==.Natalie:BAAALgAECgEJAQAAAA==.',
Ne='Nekia:BAAALgADCgcJBwAAAA==.Neroz:BAABLgAECn8pAAIRAAgJMRifGgDzAQhoDAAABwBPAGkMAAAHAEkAawwAAAcAOABqDAAABQAwAGwMAAAFADcAbQwAAAMAPwDqDAAABgA9AG4MAAABACkAEQAICTEYnxoA8wEIaAwAAAcATwBpDAAABwBJAGsMAAAHADgAagwAAAUAMABsDAAABQA3AG0MAAADAD8A6gwAAAYAPQBuDAAAAQApAAAA.Nerppie:BAABLgAECn8kAAIFAAgJUB+UCQCCAghoDAAABgBQAGkMAAAGAE8AawwAAAYAWQBqDAAABABXAGwMAAAEAGEAbQwAAAMANQDqDAAABgBUAG4MAAABAEQABQAICVAflAkAggIIaAwAAAYAUABpDAAABgBPAGsMAAAGAFkAagwAAAQAVwBsDAAABABhAG0MAAADADUA6gwAAAYAVABuDAAAAQBEAAAA.Nevershark:BAAALgAECgUJBQAAAA==.',
Ni='Nightfallz:BAAALgADCgUJBQAAAA==.Nina:BAABLgAECn8YAAIHAAcJdRpRTwD0AQdoDAAABABEAGkMAAAEAFAAawwAAAQAVABqDAAAAQAyAGwMAAABACcA6gwAAAYATwBuDAAABAA2AAcABwl1GlFPAPQBB2gMAAAEAEQAaQwAAAQAUABrDAAABABUAGoMAAABADIAbAwAAAEAJwDqDAAABgBPAG4MAAAEADYAAAA=.Nixah:BAAALgAECgUJDQAAAA==.',
Nk='Nkript:BAABLgAECn8aAAMGAAcJehWtLgCWAQdoDAAABQA+AGkMAAAEAEkAawwAAAQAQABqDAAABAA7AGwMAAAEADkA6gwAAAQAKQBuDAAAAQAeAAYABwl6Fa0uAJYBB2gMAAACAD4AaQwAAAMASQBrDAAAAwBAAGoMAAADADsAbAwAAAMAOQDqDAAAAwApAG4MAAABAB4AFQAGCaYIhk8AEQEGaAwAAAMAHABpDAAAAQAFAGsMAAABAB0AagwAAAEAFwBsDAAAAQATAOoMAAABABsAAAA=.',
No='Nortel:BAAALgAECgYJDgAAAA==.',
Oh='Ohgourdness:BAAALgADCgcJBwABLgAECgYJFQAZAPgEAA==.',
On='Onari:BAABLgAECn8bAAIBAAgJ5Rw5CgBNAghoDAAABABGAGkMAAAEAFAAawwAAAQAUQBqDAAAAwBOAGwMAAAEAEEAbQwAAAEAOgDqDAAABgBbAG4MAAABAEIAAQAICeUcOQoATQIIaAwAAAQARgBpDAAABABQAGsMAAAEAFEAagwAAAMATgBsDAAABABBAG0MAAABADoA6gwAAAYAWwBuDAAAAQBCAAAA.',
Or='Orious:BAAALgADCgYJBgAAAA==.',
Pa='Pandagang:BAAALgADCgQJBQAAAA==.',
Pe='Peezee:BAAALgAECgUJCQAAAA==.Perce:BAABLgAECn8eAAIFAAgJ9iA7BAD5AghoDAAABgBHAGkMAAAEAE4AawwAAAQAUQBqDAAABABeAGwMAAAEAFoAbQwAAAIAVQDqDAAABQBbAG4MAAABAFEABQAICfYgOwQA+QIIaAwAAAYARwBpDAAABABOAGsMAAAEAFEAagwAAAQAXgBsDAAABABaAG0MAAACAFUA6gwAAAUAWwBuDAAAAQBRAAAA.Peyotte:BAABLgAECn8VAAIaAAgJfR9QBQBVAghoDAAABABVAGkMAAAEAFgAawwAAAMAUwBqDAAAAgBUAGwMAAACAFoAbQwAAAEAOADqDAAABABIAG4MAAABAFYAGgAICX0fUAUAVQIIaAwAAAQAVQBpDAAABABYAGsMAAADAFMAagwAAAIAVABsDAAAAgBaAG0MAAABADgA6gwAAAQASABuDAAAAQBWAAEuAAQKCAkeABsAqiIA.',
Pf='Pfemme:BAABLgAECn8dAAIGAAgJaRW+IQDWAQhoDAAABABTAGkMAAAEAC4AawwAAAQANQBqDAAABAAsAGwMAAAFAE4AbQwAAAIAFADqDAAAAwA1AG4MAAADADAABgAICWkVviEA1gEIaAwAAAQAUwBpDAAABAAuAGsMAAAEADUAagwAAAQALABsDAAABQBOAG0MAAACABQA6gwAAAMANQBuDAAAAwAwAAAA.',
Ps='Psych:BAAALgADCgYJBgAAAA==.',
Pu='Purian:BAAALgADCgUJCAAAAA==.',
Ra='Rami:BAAALgADCgYJBgAAAA==.',
Re='Repello:BAAALgAECgYJBwAAAA==.Reyaieleron:BAAALgAECgQJCQAAAA==.',
Ri='Ricky:BAAALgADCgEJAQAAAA==.Rivenaer:BAABLgAECn8sAAIcAAgJgA+uEQB6AQhoDAAABwA1AGkMAAAHACsAawwAAAcAOABqDAAABgA0AGwMAAAFABgAbQwAAAMAGQDqDAAABgAzAG4MAAADABYAHAAICYAPrhEAegEIaAwAAAcANQBpDAAABwArAGsMAAAHADgAagwAAAYANABsDAAABQAYAG0MAAADABkA6gwAAAYAMwBuDAAAAwAWAAAA.',
Ru='Ruindsoul:BAAALgADCgcJCwAAAA==.Ruka:BAAALgADCgEJAQAAAA==.Runearne:BAAALgAECgIJAgAAAA==.Rustymark:BAAALgAFFAEJAQAAAA==.',
Sc='Scaletal:BAAALgAECgUJBQAAAA==.Schmetzy:BAAALgAECgYJBwAAAA==.Schmezzy:BAABLgAECn8aAAIOAAgJtx0vGwAyAghoDAAABABTAGkMAAADAF4AawwAAAQAPQBqDAAAAwBQAGwMAAAEAEAAbQwAAAIAVgDqDAAABQBIAG4MAAABAEUADgAICbcdLxsAMgIIaAwAAAQAUwBpDAAAAwBeAGsMAAAEAD0AagwAAAMAUABsDAAABABAAG0MAAACAFYA6gwAAAUASABuDAAAAQBFAAAA.',
Se='Sealalicious:BAABLgAECn8pAAIdAAgJ1Bf9CgCbAQhoDAAABwBOAGkMAAAHAEEAawwAAAcATgBqDAAABQAyAGwMAAAFAEMAbQwAAAMAJwDqDAAABgBCAG4MAAABAB0AHQAICdQX/QoAmwEIaAwAAAcATgBpDAAABwBBAGsMAAAHAE4AagwAAAUAMgBsDAAABQBDAG0MAAADACcA6gwAAAYAQgBuDAAAAQAdAAAA.Seenaa:BAAALgADCgcJEAAAAA==.',
Sh='Shallot:BAAALgADCgIJAgAAAA==.Shammywow:BAAALgAECgUJDQAAAA==.Sharkzilla:BAAALgAECgkJEAAAAA==.Shauray:BAAALgADCgUJCAAAAA==.Shine:BAAALgAECgQJEAAAAA==.Shrub:BAAALgADCgcJBwABLgAFFAgJGQAeAKghAA==.',
Sm='Smoo:BAAALgADCgkJHQAAAA==.',
Sn='Snø:BAAALgAECgYJDQAAAA==.',
So='Sobol:BAAALgAFFAEJAQAAAA==.Soggyaugi:BAAALgAECgUJBQAAAA==.Solbinder:BAAALgADCgIJAgAAAA==.Soraa:BAEALgAECgUJDwABLgAECgcJEQAJAAAAAA==.',
St='Starlethia:BAAALgAECgYJCgAAAA==.',
Su='Sunshine:BAAALgADCgcJDAAAAA==.Sunwälker:BAAALgADCgQJBAAAAA==.',
Sy='Sybelin:BAAALgADCgMJAwAAAA==.',
Ta='Tallchief:BAAALgAECgMJBwAAAA==.Tankufrdying:BAAALgADCgQJBgAAAA==.Tavarien:BAAALgADCgEJAQAAAA==.',
Te='Tenjo:BAAALgADCgMJAwAAAA==.Terrier:BAAALgAECgEJAQAAAA==.',
Th='Thaerdran:BAABLgAECn8bAAIPAAcJ4RWNEgBYAQdoDAAABQAyAGkMAAAEAEUAawwAAAQARwBqDAAABAAnAGwMAAAFADAA6gwAAAMAQwBuDAAAAgAdAA8ABwnhFY0SAFgBB2gMAAAFADIAaQwAAAQARQBrDAAABABHAGoMAAAEACcAbAwAAAUAMADqDAAAAwBDAG4MAAACAB0AAAA=.',
Ti='Tirriel:BAAALgADCgMJAwAAAA==.',
To='Toess:BAAALgAECgEJAQAAAA==.Tonjuren:BAAALgAECgMJBwABLgAECgYJDwAJAAAAAA==.',
Tr='Trublood:BAAALgAECgUJDgAAAA==.',
Tw='Twister:BAAALgAECgQJDwAAAA==.',
Ty='Tyrra:BAAALgADCgMJAwAAAA==.',
Uk='Ukeenonme:BAAALgADCgQJBgAAAA==.',
Us='Usorloups:BAABLgAECn8eAAIbAAgJqiKqBgCDAghoDAAABABUAGkMAAAEAFIAawwAAAMAWwBqDAAABABKAGwMAAADAFcAbQwAAAMAYgDqDAAABgBVAG4MAAADAFsAGwAICaoiqgYAgwIIaAwAAAQAVABpDAAABABSAGsMAAADAFsAagwAAAQASgBsDAAAAwBXAG0MAAADAGIA6gwAAAYAVQBuDAAAAwBbAAAA.',
Ve='Velonys:BAABLgAECn8oAAQNAAkJvB/XBACPAgloDAAABwBgAGkMAAAGAFwAawwAAAUAVwBqDAAABQBOAGwMAAAFAFsAbQwAAAMARwDqDAAABQBQAG4MAAACAFAAbwwAAAIAMQANAAgJiCHXBACPAghoDAAAAgBgAGkMAAADAFwAawwAAAQAVwBqDAAABQBOAGwMAAAEAFsAbQwAAAMARwDqDAAAAgBQAG4MAAABAFAAFgAECSwgjAYAYAEEaAwAAAEAXABpDAAAAQBTAGsMAAABAE4A6gwAAAEASgAfAAYJSRWIRgBaAQZoDAAABABBAGkMAAACAEoAbAwAAAEAOADqDAAAAgA3AG4MAAABABoAbwwAAAIAMQAAAA==.Velus:BAAALgAECgQJBAAAAA==.',
Vi='Victory:BAAALgAECgEJAQAAAA==.Vintar:BAAALgADCgMJAwAAAA==.',
Vy='Vyu:BAAALgAECgkJAwAAAA==.',
Wa='Wanayu:BAABLgAECn8bAAINAAgJUhhSAwD+AQhoDAAABAA/AGkMAAAEAEYAawwAAAQAOQBqDAAAAwAmAGwMAAAEAEQAbQwAAAEAFgDqDAAABgBQAG4MAAABAEgADQAICVIYUgMA/gEIaAwAAAQAPwBpDAAABABGAGsMAAAEADkAagwAAAMAJgBsDAAABABEAG0MAAABABYA6gwAAAYAUABuDAAAAQBIAAAA.Wanweasley:BAAALgAECgUJCgAAAA==.',
We='Weeab:BAAALgADCgEJAQAAAA==.Weezlee:BAAALgAECgQJBAAAAA==.Weh:BAABLgAECn8YAAIDAAkJryLJCwDLAgloDAAABABfAGkMAAAEAGMAawwAAAMAYwBqDAAAAwBiAGwMAAACAGMAbQwAAAIATADqDAAABABjAG4MAAABAEkAbwwAAAEAQwADAAkJryLJCwDLAgloDAAABABfAGkMAAAEAGMAawwAAAMAYwBqDAAAAwBiAGwMAAACAGMAbQwAAAIATADqDAAABABjAG4MAAABAEkAbwwAAAEAQwAAAA==.',
Wi='Wickedsham:BAAALgADCgIJAgAAAA==.Wintermourne:BAAALgAECgcJDgAAAA==.Wizagon:BAAALgAECggJEgAAAA==.',
Wo='Woodsy:BAABLgAECn8bAAIgAAgJLBmdBwADAghoDAAABAAzAGkMAAAEAE0AawwAAAQAPwBqDAAAAwBAAGwMAAAEADwAbQwAAAIAMADqDAAABQBTAG4MAAABAEEAIAAICSwZnQcAAwIIaAwAAAQAMwBpDAAABABNAGsMAAAEAD8AagwAAAMAQABsDAAABAA8AG0MAAACADAA6gwAAAUAUwBuDAAAAQBBAAAA.Wounded:BAAALgAECgEJAQAAAA==.Woundliquor:BAAALgAECgcJCAAAAA==.',
Wu='Wuinn:BAACLgAFFH8KAAIZAAQJ5hHOCgAvAQRoDAAABAA+AGkMAAACACUAawwAAAIAGADqDAAAAgA6ABkABAnmEc4KAC8BBGgMAAAEAD4AaQwAAAIAJQBrDAAAAgAYAOoMAAACADoALgAECn8xAAMZAAkJCyDeDwC5AgAZAAkJCyDeDwC5AgAQAAcJUhjZCACrAQAAAA==.',
Xe='Xemnas:BAABLgAECn8jAAQOAAcJpQz4UwBNAQdoDAAABwAqAGkMAAAHAB8AawwAAAcAEwBqDAAABgAbAGwMAAAEACYAbQwAAAEAHADqDAAAAwAiAA4ABwmlDPhTAE0BB2gMAAAHACoAaQwAAAYAHwBrDAAABgATAGoMAAAGABsAbAwAAAQAJgBtDAAAAQAcAOoMAAADACIAIQABCbQLyRgAMgABaQwAAAEAHQAPAAEJqgFVQQAcAAFrDAAAAQAEAAAA.',
Ya='Yawnday:BAAALgADCgUJCAAAAA==.',
Za='Zaryala:BAAALgADCgkJKAAAAA==.',
Ze='Zenshift:BAAALgAECgMJBQAAAA==.',
Zy='Zynthia:BAABLgAECn8nAAIOAAgJYiSQBwDsAghoDAAABwBcAGkMAAAHAGIAawwAAAcAYQBqDAAABABjAGwMAAAEAF0AbQwAAAMAXwDqDAAABgBgAG4MAAABAE4ADgAICWIkkAcA7AIIaAwAAAcAXABpDAAABwBiAGsMAAAHAGEAagwAAAQAYwBsDAAABABdAG0MAAADAF8A6gwAAAYAYABuDAAAAQBOAAAA.',
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
