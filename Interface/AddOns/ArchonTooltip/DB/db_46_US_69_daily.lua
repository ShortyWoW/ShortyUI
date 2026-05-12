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

local lookup = {'DemonHunter-Devourer','DemonHunter-Havoc','Druid-Restoration','Druid-Balance','Druid-Guardian','Hunter-BeastMastery','Evoker-Preservation','Evoker-Augmentation','Paladin-Retribution','Priest-Holy','Priest-Shadow','Rogue-Subtlety','Warlock-Demonology','Shaman-Elemental','DeathKnight-Unholy','Shaman-Restoration','Paladin-Holy','Warlock-Destruction','Monk-Brewmaster','Hunter-Marksmanship','Druid-Feral','Hunter-Survival','Mage-Frost','Evoker-Devastation','Unknown-Unknown','DeathKnight-Frost','Warrior-Protection',}
local provider = {region='US',realm='Detheroc',name='US',type='daily',zone=46,date='2026-05-11',data={Ab='Abominus:BAAALgADCgMJAwAAAA==.Abrak:BAAALgAECgcJDAAAAA==.',
Ae='Aelflaed:BAAALgAECgcJDwAAAA==.Aerirea:BAAALgAECgIJAgAAAA==.Aethèr:BAAALgADCggJCQAAAA==.',
Al='Aladiirn:BAACLgAFFH8SAAIBAAUJ/xWhHwA4AQVoDAAABQBNAGkMAAAFADMAawwAAAMADQBqDAAAAQAfAOoMAAAEAFIAAQAFCf8VoR8AOAEFaAwAAAUATQBpDAAABQAzAGsMAAADAA0AagwAAAEAHwDqDAAABABSAC4ABAp/MAADAQAICW4k2wsAggIAAQAICW4k2wsAggIAAgABCT4bDmUAUAAAAAA=.Alphapacer:BAAALgADCgcJCQAAAA==.',
As='Asha:BAABLgAECn8YAAQDAAcJuhgmUABlAQdoDAAABABDAGkMAAAEADAAawwAAAQAPgBqDAAABABcAGwMAAAEAFcAbQwAAAEAAwDqDAAAAwBRAAMABgmXHCZQAGUBBmgMAAADAEMAaQwAAAMAMABrDAAAAwA+AGoMAAACAFwAbAwAAAIAVwDqDAAAAgBRAAQABwlJEVAfAEsBB2gMAAABAEYAaQwAAAEASQBrDAAAAQBHAGoMAAABAEMAbAwAAAEAKwBtDAAAAQABAOoMAAABAAQABQACCZUKejYAIgACagwAAAEAGQBsDAAAAQAbAAAA.Ashleeann:BAABLgAECn8YAAIGAAkJkQ0IOgDGAQloDAAABAAWAGkMAAADAC0AawwAAAMAQgBqDAAAAwAcAGwMAAAEABYAbQwAAAEAFwDqDAAAAwAhAG4MAAACACoAbwwAAAEAEwAGAAkJkQ0IOgDGAQloDAAABAAWAGkMAAADAC0AawwAAAMAQgBqDAAAAwAcAGwMAAAEABYAbQwAAAEAFwDqDAAAAwAhAG4MAAACACoAbwwAAAEAEwAAAA==.',
At='Ather:BAAALgAECgcJCwAAAA==.',
Au='Aurix:BAAALgADCgMJAwAAAA==.',
Aw='Awenyddion:BAAALgAECgUJCgAAAA==.',
Ba='Bayle:BAABLgAECn8VAAMHAAYJlQqZKQAmAQZoDAAABQAYAGkMAAAEAB0AawwAAAQAEgBqDAAAAwAbAGwMAAADAB0A6gwAAAIAIAAHAAYJlQqZKQAmAQZoDAAAAwAYAGkMAAADAB0AawwAAAMAEgBqDAAAAwAbAGwMAAADAB0A6gwAAAEAIAAIAAQJ0QkFSgCtAARoDAAAAgApAGkMAAABAAwAawwAAAEAHwDqDAAAAQAOAAAA.',
Bb='Bbygrl:BAAALgAECgMJAwAAAA==.',
Bo='Boabjr:BAAALgADCgUJBQAAAA==.Booner:BAAALgAECgEJAwAAAA==.Botadin:BAABLgAECn8aAAIJAAcJKhzXMQDHAQdoDAAABQBbAGkMAAAFAEQAawwAAAUASABqDAAAAwBCAGwMAAACADUA6gwAAAUAQwBuDAAAAQBOAAkABwkqHNcxAMcBB2gMAAAFAFsAaQwAAAUARABrDAAABQBIAGoMAAADAEIAbAwAAAIANQDqDAAABQBDAG4MAAABAE4AAAA=.',
Br='Brandrood:BAAALgAECgYJBgAAAA==.',
Bu='Bubblemeinfy:BAAALgAECgEJAQAAAA==.',
['Bô']='Bôw:BAABLgAECn8eAAIGAAkJ0AqdQACtAQloDAAABQAYAGkMAAAFACAAawwAAAUANQBqDAAABAAmAGwMAAAEACAAbQwAAAEAGADqDAAAAwARAG4MAAACABEAbwwAAAEAEwAGAAkJ0AqdQACtAQloDAAABQAYAGkMAAAFACAAawwAAAUANQBqDAAABAAmAGwMAAAEACAAbQwAAAEAGADqDAAAAwARAG4MAAACABEAbwwAAAEAEwAAAA==.',
Ch='Chaotic:BAAALgADCgkJDwAAAA==.',
Co='Corca:BAACLgAFFH8JAAIKAAMJNxIHEgDPAANoDAAABAAkAGkMAAADACsA6gwAAAIAPAAKAAMJNxIHEgDPAANoDAAABAAkAGkMAAADACsA6gwAAAIAPAAuAAQKfy0AAwoACAnJFM4cAHQBAAoACAnJFM4cAHQBAAsABgneCNRHAMIAAAAA.',
Da='Dallinar:BAAALgADCgIJAgAAAA==.Darklocke:BAAALgAECgIJBAAAAA==.Dazbraz:BAAALgADCgkJCQABLgAECggJHQAMABgaAA==.',
De='Death:BAAALgADCgYJBgABLgAFFAMJDQANAGQlAA==.Deaçon:BAAALgAECgUJDQAAAA==.Derffenator:BAAALgADCgEJAQAAAA==.',
Di='Diazz:BAAALgAECgEJAgAAAA==.Dirty:BAAALgADCgMJAwABLgAECggJHgAOAOQTAA==.',
Do='Dooma:BAABLgAECn8cAAIPAAgJDhyHMAB2AghoDAAABABcAGkMAAAEAFQAawwAAAQATwBqDAAAAwBYAGwMAAADAFoAbQwAAAIAKgDqDAAABgBHAG4MAAACACoADwAICQ4chzAAdgIIaAwAAAQAXABpDAAABABUAGsMAAAEAE8AagwAAAMAWABsDAAAAwBaAG0MAAACACoA6gwAAAYARwBuDAAAAgAqAAAA.',
Dp='Dps:BAAALgAECgMJAwAAAA==.',
Dr='Drakko:BAAALgAECggJDwAAAA==.Drax:BAAALgAECgkJCAAAAA==.',
Du='Dunspore:BAABLgAECn8fAAIQAAkJrSA+BwAAAwloDAAABQBhAGkMAAAFAF0AawwAAAUAXQBqDAAABABNAGwMAAAEAFsAbQwAAAEAUQDqDAAABABeAG4MAAACAEMAbwwAAAEANgAQAAkJrSA+BwAAAwloDAAABQBhAGkMAAAFAF0AawwAAAUAXQBqDAAABABNAGwMAAAEAFsAbQwAAAEAUQDqDAAABABeAG4MAAACAEMAbwwAAAEANgAAAA==.',
Ea='Earendel:BAAALgADCgkJCQAAAA==.',
Er='Ermahn:BAAALgAECgYJDAAAAA==.',
Fi='Finalgoddk:BAAALgADCgEJAQABLgAFFAMJCQAJAJglAA==.Finalgodfury:BAACLgAFFH8JAAIJAAMJmCX0GQBPAQNoDAAABABhAGkMAAADAGAA6gwAAAIAXwAJAAMJmCX0GQBPAQNoDAAABABhAGkMAAADAGAA6gwAAAIAXwAuAAQKfycAAgkACAkBJiQJAEkDAAkACAkBJiQJAEkDAAAA.',
Fo='Foxydots:BAAALgAECgYJCAAAAA==.',
Fr='Frostscythe:BAAALgAECgMJAwAAAA==.',
Fu='Furmidable:BAAALgADCgcJBwAAAA==.',
Gi='Girrzz:BAAALgAECgQJCAAAAA==.Girthspell:BAAALgAECgEJAQAAAA==.',
Gr='Grand:BAACLgAFFH8JAAIRAAMJ/SMgFAAiAQNoDAAABABcAGkMAAADAFUA6gwAAAIAYQARAAMJ/SMgFAAiAQNoDAAABABcAGkMAAADAFUA6gwAAAIAYQAuAAQKfzEAAhEACAnWI7cEAO8CABEACAnWI7cEAO8CAAAA.Grock:BAABLgAECn8eAAMQAAcJVQ1hOAA8AQdoDAAABQAvAGkMAAAFAA8AawwAAAUAIgBqDAAABQAuAGwMAAAEABsAbQwAAAIAFQDqDAAABAAtABAABwlVDWE4ADwBB2gMAAAEAC8AaQwAAAQADwBrDAAABAAiAGoMAAAEAC4AbAwAAAMAGwBtDAAAAgAVAOoMAAADAC0ADgAGCZoEZT8AvgAGaAwAAAEAEgBpDAAAAQAPAGsMAAABAAsAagwAAAEACABsDAAAAQADAOoMAAABAAkAAAA=.Grundlegut:BAAALgAECgEJAQAAAA==.Grundletap:BAAALgADCgEJAgAAAA==.',
Gx='Gxxse:BAABLgAECn8dAAIMAAgJGBpHGABFAghoDAAABQBIAGkMAAAEAEwAawwAAAQASABqDAAABAAxAGwMAAACAEAAbQwAAAIAHgDqDAAABgA3AG4MAAACAF8ADAAICRgaRxgARQIIaAwAAAUASABpDAAABABMAGsMAAAEAEgAagwAAAQAMQBsDAAAAgBAAG0MAAACAB4A6gwAAAYANwBuDAAAAgBfAAAA.',
He='Hewman:BAAALgAECgQJBgAAAA==.Hezzding:BAAALgADCgIJAgAAAA==.',
Hu='Hugehippo:BAAALgAECgQJBAAAAA==.Hunanchicken:BAAALgAECgEJAQAAAA==.',
Ic='Icebox:BAAALgAECgYJBgAAAA==.Icejesterr:BAAALgAECgUJDAAAAA==.',
Ig='Ignorepain:BAAALgAECgYJDQAAAA==.',
Il='Illigiggle:BAAALgADCgYJCQAAAA==.Illioogg:BAAALgADCgMJAwAAAA==.',
Im='Imptastic:BAAALgAECgUJBwAAAA==.',
In='Industdoom:BAAALgAECgEJAQAAAA==.',
Ir='Ironstock:BAAALgADCgEJAQAAAA==.',
Je='Jesterpal:BAAALgAECgYJDgAAAA==.',
Jo='Joj:BAAALgAECgYJBwAAAA==.Jollyolly:BAABLgAECn8kAAMNAAkJHBgYLgC4AQloDAAABgBZAGkMAAAGAEsAawwAAAcARgBqDAAABABDAGwMAAAEADEAbQwAAAEAJwDqDAAABQA/AG4MAAACACMAbwwAAAEARQANAAgJ6RQYLgC4AQhoDAAAAgAyAGkMAAADAEsAawwAAAIAOgBsDAAAAgAxAG0MAAABACcA6gwAAAUAPwBuDAAAAQAVAG8MAAABAEUAEgAGCZIWth0AYQEGaAwAAAQAWQBpDAAAAwA2AGsMAAAFAEYAagwAAAQAQwBsDAAAAgAnAG4MAAABACMAAAA=.',
Ju='Juvens:BAAALgAECgEJAQAAAA==.Jux:BAAALgADCgMJAwAAAA==.',
Ka='Kalleo:BAAALgADCgIJAgAAAA==.Karma:BAAALgADCgQJBAAAAA==.',
Ko='Korath:BAAALgAECgYJBgABLgAFFAMJBwATAJ8ZAA==.',
Kr='Krimzin:BAAALgAECgEJAgABLgAFFAQJDAAGAHIbAA==.',
Ky='Kynrina:BAAALgADCgEJAQAAAA==.',
La='Ladrill:BAAALgADCgcJBwAAAA==.Lainarning:BAAALgAECgMJBAAAAA==.',
Le='Lewiz:BAAALgAECgYJDgAAAA==.',
Lu='Lucetia:BAAALgAECgEJAQAAAA==.',
Ma='Machooze:BAAALgAECgEJAQAAAA==.Magifrey:BAAALgAECgEJAgAAAA==.Masha:BAAALgADCgYJBgAAAA==.Mazikene:BAAALgAECgEJAQAAAA==.',
Mi='Mirabeaux:BAAALgAECgEJAQAAAA==.',
Mo='Moomtir:BAAALgADCgEJAQAAAA==.Morelia:BAAALgADCgcJFAAAAA==.Morph:BAAALgADCgEJAQAAAA==.Morrist:BAAALgAECgMJAwAAAA==.',
Ms='Mskeisha:BAAALgAECgMJAwAAAA==.',
Mu='Mugsfaru:BAABLgAECn8YAAMGAAcJ2yD2KgC0AQdoDAAABQBfAGkMAAAEAFYAawwAAAQAUwBqDAAAAwBhAGwMAAADAFwAbQwAAAEAOgDqDAAABABZAAYABwnbIPYqALQBB2gMAAAEAF8AaQwAAAQAVgBrDAAABABTAGoMAAADAGEAbAwAAAIAXABtDAAAAQA6AOoMAAABAFkAFAADCccOJ2wAjgADaAwAAAEALwBsDAAAAQARAOoMAAADADAAAAA=.',
Na='Nabecovid:BAACLgAFFH8GAAIVAAIJyQvCCACgAAJoDAAABAAyAOoMAAACAAoAFQACCckLwggAoAACaAwAAAQAMgDqDAAAAgAKAC4ABAp/MAADFQAICQ0cGgQARgIAFQAICQ0cGgQARgIABQABCQgQ+DMAKgAAAAA=.Nasha:BAABLgAECn8vAAIJAAkJ8h96CADbAgloDAAABgBWAGkMAAAGAGEAawwAAAYAWwBqDAAABgBBAGwMAAAGAFwAbQwAAAQAUADqDAAABgBQAG4MAAAEADQAbwwAAAMASQAJAAkJ8h96CADbAgloDAAABgBWAGkMAAAGAGEAawwAAAYAWwBqDAAABgBBAGwMAAAGAFwAbQwAAAQAUADqDAAABgBQAG4MAAAEADQAbwwAAAMASQAAAA==.Natek:BAABLgAECn8bAAMOAAgJ8h+FDgAHAghoDAAAAwBIAGkMAAADAEYAawwAAAMAWQBqDAAAAwBUAGwMAAAEAFQAbQwAAAMAVQDqDAAABABQAG4MAAAEAFgADgAICfIfhQ4ABwIIaAwAAAMASABpDAAAAgBGAGsMAAADAFkAagwAAAMAVABsDAAABABUAG0MAAADAFUA6gwAAAMAUABuDAAAAgBYABAAAwngFnFXAL0AA2kMAAABAD4A6gwAAAEAPwBuDAAAAgAxAAAA.',
Ni='Nightprowlr:BAAALgAECggJEwAAAA==.',
Oo='Oogglytotems:BAAALgADCgQJBAAAAA==.Ooggmonk:BAAALgADCgUJBQAAAA==.',
Or='Orb:BAAALgADCgEJAQAAAA==.',
Pa='Pablofanques:BAAALgAECgQJBAAAAA==.Pantojak:BAACLgAFFH8HAAITAAMJnxnyHgD1AANoDAAAAwAyAGkMAAADAFYA6gwAAAEAOwATAAMJnxnyHgD1AANoDAAAAwAyAGkMAAADAFYA6gwAAAEAOwAuAAQKfxkAAhMABwl/IcwlANUBABMABwl/IcwlANUBAAAA.Parksnar:BAAALgAECgcJEAAAAA==.',
Pe='Pepe:BAAALgAECgUJCgAAAA==.',
Ph='Phouchg:BAABLgAECn8eAAQWAAgJdh08CAAyAghoDAAAAgARAGkMAAAFAE4AawwAAAUAXQBqDAAABABNAGwMAAAEAGMAbQwAAAMAUQDqDAAABABPAG4MAAADAEwAFgAHCXkdPAgAMgIHaQwAAAIATgBrDAAAAgBdAGoMAAABAAsAbAwAAAEAYwBtDAAAAQBRAOoMAAACAE8AbgwAAAEAEwAUAAcJSRYzCACLAQdoDAAAAQARAGkMAAACAEUAawwAAAIAQQBqDAAAAgBNAGwMAAACADcAbQwAAAEAOQBuDAAAAQBMAAYACAnuDyA8AG4BCGgMAAABAAQAaQwAAAEALwBrDAAAAQAiAGoMAAABACoAbAwAAAEAQQBtDAAAAQAlAOoMAAACADEAbgwAAAEALgAAAA==.',
Pi='Pirotessa:BAABLgAECn8lAAIXAAkJuB2mGgBbAgloDAAABQBWAGkMAAAHAFEAawwAAAcAWQBqDAAABQBWAGwMAAADAFAAbQwAAAEARADqDAAABgBfAG4MAAACAB0AbwwAAAEATQAXAAkJuB2mGgBbAgloDAAABQBWAGkMAAAHAFEAawwAAAcAWQBqDAAABQBWAGwMAAADAFAAbQwAAAEARADqDAAABgBfAG4MAAACAB0AbwwAAAEATQAAAA==.',
Ra='Ranore:BAAALgADCgcJHgABLgAECgkJJgACABkdAA==.Rathimus:BAAALgAECgIJAgAAAA==.Rayven:BAAALgAECgEJAQAAAA==.',
Re='Reimdh:BAAALgAECgEJAQABLgAFFAUJEgABAP8VAA==.Reptar:BAAALgAECgUJDQABLgAFFAYJGwATAEoWAA==.',
Ri='Rianor:BAAALgAECgEJAQAAAA==.Richardtwist:BAAALgAECgEJAwAAAA==.',
Ro='Robinhoof:BAAALgADCgYJBwAAAA==.Rocko:BAAALgAECgcJEwAAAA==.Roxbox:BAAALgAECgMJAwAAAA==.',
Ry='Ryukyu:BAABLgAECn8lAAMIAAgJoRp0EADeAQhoDAAABwBKAGkMAAAGAEkAawwAAAcAUwBqDAAABABFAGwMAAAEAEcAbQwAAAEAPwDqDAAABwA2AG4MAAABADkACAAHCVsbdBAA3gEHaAwAAAcASgBpDAAABQBJAGsMAAAGAFMAagwAAAMARQBsDAAAAgBHAG0MAAABAD8A6gwAAAcANgAYAAUJfxVRJQD6AAVpDAAAAQA7AGsMAAABAC0AagwAAAEAKwBsDAAAAgA5AG4MAAABADkAAAA=.',
Sa='Savz:BAAALgADCgQJBAABLgAECgYJBgAZAAAAAA==.',
Sc='Schro:BAAALgAECgQJBAAAAA==.Schrolock:BAABLgAECn8VAAMNAAgJ7w/jbQCFAQhoDAAAAwAnAGkMAAADAC0AawwAAAMAQgBqDAAABAAgAGwMAAAEADQA6gwAAAIAHwBuDAAAAQAVAG8MAAABAB0ADQAICe8P420AhQEIaAwAAAMAJwBpDAAAAwAtAGsMAAADAEIAagwAAAEAIABsDAAABAA0AOoMAAACAB8AbgwAAAEAFQBvDAAAAQAdABIAAQkAACRzADIAAWoMAAADABkAAAA=.',
Sh='Shortbread:BAAALgADCgkJAwAAAA==.',
Sp='Sprung:BAAALgAECgQJCwAAAA==.Spyla:BAAALgAECgQJDQAAAA==.',
St='Steven:BAAALgADCgEJAQAAAA==.',
Su='Supermouse:BAABLgAECn8cAAIaAAcJXh1PBAAfAgdoDAAABQBPAGkMAAAEAEYAawwAAAUAUwBqDAAABQBTAGwMAAAEAEQAbQwAAAEARgDqDAAABABPABoABwleHU8EAB8CB2gMAAAFAE8AaQwAAAQARgBrDAAABQBTAGoMAAAFAFMAbAwAAAQARABtDAAAAQBGAOoMAAAEAE8AAAA=.',
To='Tophat:BAAALgAECgYJDQAAAA==.',
Tw='Twoinchfury:BAABLgAECn8vAAIbAAgJeBqbBwAVAghoDAAABwBOAGkMAAAHAEkAawwAAAcARQBqDAAABQBKAGwMAAAGADoAbQwAAAMAFgDqDAAACABKAG4MAAAEAGEAGwAICXgamwcAFQIIaAwAAAcATgBpDAAABwBJAGsMAAAHAEUAagwAAAUASgBsDAAABgA6AG0MAAADABYA6gwAAAgASgBuDAAABABhAAAA.',
Va='Vaihlor:BAAALgAECgEJAQAAAA==.',
Ve='Velaris:BAAALgADCgEJAQABLgAECgkJIAAKAOkaAA==.Veledin:BAAALgAECgcJDAABLgAECggJDwAZAAAAAA==.Vergil:BAABLgAECn8UAAMCAAgJ6xObDwCdAQhoDAAAAwA5AGkMAAADAAQAawwAAAIARgBqDAAABABCAGwMAAAEAFYAbQwAAAIAOwDqDAAAAQADAG4MAAABAEkAAgAICesTmw8AnQEIaAwAAAIAOQBpDAAAAgAEAGsMAAACAEYAagwAAAQAQgBsDAAABABWAG0MAAACADsA6gwAAAEAAwBuDAAAAQBJAAEAAgmwA+/GAC8AAmgMAAABAA4AaQwAAAEABAAAAA==.Veroq:BAAALgADCgcJCAAAAA==.',
Wa='Wachabe:BAABLgAECn8ZAAIFAAYJYw52FwDOAAZoDAAABQAcAGkMAAAFAB4AawwAAAQAKQBqDAAABAAeAGwMAAADADEA6gwAAAQAIQAFAAYJYw52FwDOAAZoDAAABQAcAGkMAAAFAB4AawwAAAQAKQBqDAAABAAeAGwMAAADADEA6gwAAAQAIQAAAA==.',
We='Weiden:BAACLgAFFH8HAAIEAAIJyATjJgB8AAJoDAAABAASAGkMAAADAAYABAACCcgE4yYAfAACaAwAAAQAEgBpDAAAAwAGAC4ABAp/MAACBAAICdoWJRMAvgEABAAICdoWJRMAvgEAAAA=.',
Yo='Yourpal:BAAALgADCgMJAwAAAA==.',
Yu='Yulwei:BAAALgAECggJEAAAAA==.',
Za='Zahard:BAAALgAECgYJBgAAAA==.',
Ze='Zeldah:BAAALgAECgQJBQABLgAECggJJQAIAKEaAA==.',
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
