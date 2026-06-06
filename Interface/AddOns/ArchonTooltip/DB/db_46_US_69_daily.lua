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

local lookup = {'Monk-Brewmaster','DemonHunter-Devourer','DemonHunter-Havoc','DemonHunter-Vengeance','Druid-Restoration','Druid-Balance','Druid-Guardian','Hunter-BeastMastery','Unknown-Unknown','Evoker-Preservation','Evoker-Augmentation','Paladin-Protection','Mage-Frost','DeathKnight-Unholy','Paladin-Retribution','Shaman-Elemental','Priest-Holy','Priest-Shadow','Rogue-Subtlety','Warlock-Demonology','DeathKnight-Frost','Shaman-Restoration','Hunter-Survival','Paladin-Holy','Warlock-Destruction','Evoker-Devastation','Hunter-Marksmanship','Druid-Feral','Warrior-Protection',}
local provider = {region='US',realm='Detheroc',name='US',type='daily',zone=46,date='2026-06-06',data={Ab='Abominus:BAAALgADCgMJAwAAAA==.Abrak:BAAALgAECgcJDQAAAA==.',
Ae='Aelflaed:BAAALgAECgcJDwAAAA==.Aeolia:BAAALgAECgEJAQABLgAFFAYJFgABADUbAA==.Aerirea:BAAALgAECgMJBwAAAA==.Aethèr:BAAALgADCggJCQAAAA==.',
Al='Aladiirn:BAACLgAFFH8bAAICAAcJPBJaGgC8AQdoDAAABgBNAGkMAAAGAEQAawwAAAQADQBqDAAAAgAfAG0MAAABABAA6gwAAAcAUgBuDAAAAQAWAAIABwk8EloaALwBB2gMAAAGAE0AaQwAAAYARABrDAAABAANAGoMAAACAB8AbQwAAAEAEADqDAAABwBSAG4MAAABABYALgAECn89AAQCAAgJbiQ0GQB0AgACAAgJbiQ0GQB0AgADAAEJPhsRZQBQAAAEAAMJ9gOXLQBBAAAAAA==.Alphapacer:BAAALgADCgcJCQAAAA==.',
As='Asha:BAABLgAECn8YAAQFAAcJuRgpUABlAQdoDAAABABDAGkMAAAEADAAawwAAAQAPgBqDAAABABcAGwMAAAEAFcAbQwAAAEAAwDqDAAAAwBRAAUABgmXHClQAGUBBmgMAAADAEMAaQwAAAMAMABrDAAAAwA+AGoMAAACAFwAbAwAAAIAVwDqDAAAAgBRAAYABwlJEaQ2ACwBB2gMAAABAEYAaQwAAAEASQBrDAAAAQBHAGoMAAABAEMAbAwAAAEAKwBtDAAAAQABAOoMAAABAAQABwACCZUKzHMAIQACagwAAAEAGQBsDAAAAQAbAAAA.Ashleeann:BAABLgAECn8YAAIIAAkJkQ0JOgDGAQloDAAABAAWAGkMAAADAC0AawwAAAMAQgBqDAAAAwAcAGwMAAAEABYAbQwAAAEAFwDqDAAAAwAhAG4MAAACACoAbwwAAAEAEwAIAAkJkQ0JOgDGAQloDAAABAAWAGkMAAADAC0AawwAAAMAQgBqDAAAAwAcAGwMAAAEABYAbQwAAAEAFwDqDAAAAwAhAG4MAAACACoAbwwAAAEAEwAAAA==.',
At='Ather:BAAALgAECgcJDwAAAA==.',
Au='Aulton:BAAALgADCgIJAgAAAA==.Aurix:BAAALgADCgMJAwAAAA==.',
Aw='Awenyddion:BAAALgAECgUJCgABLgAECgcJDwAJAAAAAA==.',
Ba='Bayle:BAABLgAECn8WAAMKAAYJlQqbKQAmAQZoDAAABgAYAGkMAAAEAB0AawwAAAQAEgBqDAAAAwAbAGwMAAADAB0A6gwAAAIAIAAKAAYJlQqbKQAmAQZoDAAAAwAYAGkMAAADAB0AawwAAAMAEgBqDAAAAwAbAGwMAAADAB0A6gwAAAEAIAALAAQJFQoJSgCtAARoDAAAAwAsAGkMAAABAAwAawwAAAEAHwDqDAAAAQAOAAEuAAQKCQkgAAwAiAsA.',
Bb='Bbygrl:BAABLgAFFH8FAAINAAIJ/wi+qAByAAJpDAAAAQACAOoMAAAEACsADQACCf8IvqgAcgACaQwAAAEAAgDqDAAABAArAAEuAAUUAwkHAA4Abg8A.',
Bo='Boabjr:BAAALgADCgUJBQAAAA==.Boldin:BAAALgAECgMJAwAAAA==.Booner:BAAALgAECgEJAwAAAA==.Botadin:BAABLgAECn8tAAIPAAgJSyEDGgCeAghoDAAABwBgAGkMAAAHAGEAawwAAAcAVQBqDAAABQBCAGwMAAAFAEMAbQwAAAEATwDqDAAABwBbAG4MAAAGAE4ADwAICUshAxoAngIIaAwAAAcAYABpDAAABwBhAGsMAAAHAFUAagwAAAUAQgBsDAAABQBDAG0MAAABAE8A6gwAAAcAWwBuDAAABgBOAAAA.',
Br='Brandrood:BAAALgAECgYJBgAAAA==.Bronst:BAAALgAECgIJAgABLgAECggJKQAQADAYAA==.',
Bu='Bubblemeinfy:BAAALgAECgEJAQAAAA==.',
['Bô']='Bôw:BAABLgAECn8fAAIIAAkJ0AqfQACtAQloDAAABQAYAGkMAAAFACAAawwAAAUANQBqDAAABAAmAGwMAAAEACAAbQwAAAIAGADqDAAAAwARAG4MAAACABEAbwwAAAEAEwAIAAkJ0AqfQACtAQloDAAABQAYAGkMAAAFACAAawwAAAUANQBqDAAABAAmAGwMAAAEACAAbQwAAAIAGADqDAAAAwARAG4MAAACABEAbwwAAAEAEwAAAA==.',
Ca='Calvin:BAAALgAECgEJAgAAAA==.',
Ce='Cerinis:BAAALgAFFAEJAQAAAA==.',
Ch='Chairmanmao:BAAALgAECgMJAwAAAA==.Chaotic:BAAALgADCgkJDwAAAA==.',
Co='Corca:BAACLgAFFH8UAAIRAAQJHw57GgDSAARoDAAABwAkAGkMAAAGACsAawwAAAIABADqDAAABQA8ABEABAkfDnsaANIABGgMAAAHACQAaQwAAAYAKwBrDAAAAgAEAOoMAAAFADwALgAECn83AAMRAAkJwhL5JwB5AQARAAkJwhL5JwB5AQASAAYJ3gjXRwDCAAAAAA==.',
Da='Dallinar:BAAALgADCgIJAgAAAA==.Darklocke:BAAALgAECgUJCwAAAA==.Dazbraz:BAAALgADCgkJCQABLgAFFAUJDwATAOsPAA==.',
De='Death:BAAALgADCgYJBgABLgAFFAMJEAAUAGQlAA==.Deaçon:BAAALgAECgUJDQAAAA==.Derffenator:BAAALgADCgEJAQAAAA==.',
Di='Diazz:BAAALgAECgEJAgAAAA==.Dirty:BAAALgADCgMJAwABLgAECggJHgAQAOQTAA==.',
Do='Dooma:BAACLgAFFH8HAAMOAAMJbg+loADHAANoDAAAAgAnAGkMAAABAAsA6gwAAAQAQwAOAAMJoAuloADHAANoDAAAAQAJAGkMAAABAAsA6gwAAAMAQwAVAAIJlw7oGgCGAAJoDAAAAQAnAOoMAAABACMALgAECn8jAAMOAAkJeh7QLgA7AgAOAAkJeh7QLgA7AgAVAAUJDxjjFAAlAQAAAA==.',
Dp='Dps:BAAALgAECgUJCAAAAA==.',
Dr='Drakjob:BAAALgADCgkJCgAAAA==.Drakko:BAAALgAECggJDwABLgAFFAEJAQAJAAAAAA==.Drax:BAAALgAECgkJDAAAAA==.',
Du='Dunspore:BAABLgAECn8gAAIWAAkJrSA9BwAAAwloDAAABQBhAGkMAAAFAF0AawwAAAUAXQBqDAAABABNAGwMAAAEAFsAbQwAAAIAUQDqDAAABABeAG4MAAACAEMAbwwAAAEANgAWAAkJrSA9BwAAAwloDAAABQBhAGkMAAAFAF0AawwAAAUAXQBqDAAABABNAGwMAAAEAFsAbQwAAAIAUQDqDAAABABeAG4MAAACAEMAbwwAAAEANgAAAA==.',
Ea='Earendel:BAAALgADCgkJCQAAAA==.',
Er='Ermahn:BAAALgAECgYJEAAAAA==.',
Fi='Finalgoddk:BAAALgADCgkJCgABLgAFFAQJDQAPANMiAA==.Finalgodfury:BAACLgAFFH8NAAIPAAQJ0yLLHwByAQRoDAAABQBhAGkMAAAEAGAAawwAAAEAQwDqDAAAAwBfAA8ABAnTIssfAHIBBGgMAAAFAGEAaQwAAAQAYABrDAAAAQBDAOoMAAADAF8ALgAECn8oAAIPAAgJAiYlCQBJAwAPAAgJAiYlCQBJAwAAAA==.Fingbang:BAAALgADCgYJBgABLgAFFAMJAwAJAAAAAA==.',
Fo='Fooshg:BAAALgAECgEJAQABLgAFFAQJDgAXADslAA==.Foxinhood:BAAALgAFFAMJAwAAAA==.Foxydots:BAAALgAECgYJCAAAAA==.',
Fr='Frostscythe:BAAALgAECgMJAwAAAA==.',
Fu='Furmidable:BAAALgADCgcJBwAAAA==.',
Gi='Girrzz:BAAALgAECgYJDwAAAA==.Girthspell:BAAALgAECgEJAQAAAA==.Girthtrude:BAAALgAECgEJAQAAAA==.',
Gr='Grand:BAACLgAFFH8UAAIYAAQJGiM7FAB8AQRoDAAABwBcAGkMAAAGAFUAawwAAAIAUwDqDAAABQBhABgABAkaIzsUAHwBBGgMAAAHAFwAaQwAAAYAVQBrDAAAAgBTAOoMAAAFAGEALgAECn87AAIYAAkJfSIDBwATAwAYAAkJfSIDBwATAwAAAA==.Grock:BAABLgAECn8wAAMWAAkJexmIEgCtAgloDAAABwBNAGkMAAAHAEkAawwAAAcAWABqDAAABgA/AGwMAAAFACwAbQwAAAMAHADqDAAABwBQAG4MAAAEAFUAbwwAAAIALAAWAAkJexmIEgCtAgloDAAABgBNAGkMAAAGAEkAawwAAAYAWABqDAAABQA/AGwMAAAEACwAbQwAAAMAHADqDAAABgBQAG4MAAADAFUAbwwAAAIALAAQAAcJtgQ9WwDDAAdoDAAAAQASAGkMAAABAA8AawwAAAEACwBqDAAAAQAIAGwMAAABAAMA6gwAAAEACQBuDAAAAQANAAAA.Grundlegut:BAAALgAECgEJAQAAAA==.Grundletap:BAAALgADCgEJAgAAAA==.',
Gx='Gxxse:BAACLgAFFH8PAAITAAUJ6w/LGgA1AQVoDAAABQA5AGkMAAAFADYAawwAAAIACwBqDAAAAQAZAOoMAAACACcAEwAFCesPyxoANQEFaAwAAAUAOQBpDAAABQA2AGsMAAACAAsAagwAAAEAGQDqDAAAAgAnAC4ABAp/IQACEwAJCQobRhgARQIAEwAJCQobRhgARQIAAAA=.',
He='Hewman:BAAALgAECgQJCwAAAA==.Hezzding:BAAALgADCgIJAgAAAA==.',
Ho='Hogar:BAAALgAFFAQJBAABLgAFFAYJFgABADUbAA==.',
Hu='Hugehippo:BAAALgAECgQJBAAAAA==.Hunanchicken:BAAALgAECgEJAQAAAA==.',
Ic='Icebox:BAAALgAECgYJBgAAAA==.Icejesterr:BAAALgAECgUJDAAAAA==.',
Ig='Ignorepain:BAAALgAECgYJDQAAAA==.',
Il='Illigiggle:BAAALgADCgYJCQAAAA==.Illioogg:BAAALgADCgMJAwAAAA==.',
Im='Imptastic:BAAALgAECgYJCAAAAA==.',
In='Industdoom:BAAALgAECgEJAQAAAA==.',
Ir='Ironstock:BAAALgADCgEJAQAAAA==.',
Je='Jesterpal:BAAALgAECgYJDgAAAA==.',
Jo='Joj:BAAALgAECgYJBwAAAA==.Jollyolly:BAABLgAECn8rAAMZAAkJmRloEAAuAQloDAAABgBZAGkMAAAHAEsAawwAAAgARgBqDAAABQBDAGwMAAAEADEAbQwAAAIAJwDqDAAACABeAG4MAAACACMAbwwAAAEARQAUAAgJ6RSzWACOAQhoDAAAAgAyAGkMAAAEAEsAawwAAAMAOgBsDAAAAgAxAG0MAAABACcA6gwAAAUAPwBuDAAAAQAVAG8MAAABAEUAGQAICQIXaBAALgEIaAwAAAQAWQBpDAAAAwA2AGsMAAAFAEYAagwAAAUAQwBsDAAAAgAnAG0MAAABAB0A6gwAAAMAXgBuDAAAAQAjAAAA.',
Ju='Juvens:BAAALgAECgEJAQAAAA==.Jux:BAAALgADCgMJAwAAAA==.',
Ka='Kalleo:BAAALgADCgIJAgAAAA==.Karma:BAAALgADCgQJBAAAAA==.',
Ko='Korath:BAAALgAECgYJBgABLgAFFAYJFgABADUbAA==.',
Kr='Krimzin:BAAALgAFFAEJAQABLgAFFAUJGgAIADAhAA==.',
Ky='Kynrina:BAAALgADCgEJAQAAAA==.',
La='Ladrill:BAAALgADCgcJBwAAAA==.Lainarning:BAAALgAECgMJBQAAAA==.',
Le='Lewiz:BAAALgAFFAIJAwAAAA==.',
Li='Lightsnack:BAAALgAECgEJAgAAAA==.',
Lu='Lucetia:BAAALgAECgEJAwAAAA==.',
Ma='Machooze:BAAALgAFFAEJAQAAAA==.Magifrey:BAAALgAECgEJAgAAAA==.Makyae:BAAALgAECgEJAgAAAA==.Masha:BAAALgADCgYJBgAAAA==.Mazikene:BAAALgAECgEJAQAAAA==.',
Mi='Minniemee:BAAALgAECgQJAQAAAA==.Mirabeaux:BAAALgAECgYJCQAAAA==.',
Mo='Moji:BAABLgAFFH8GAAMLAAYJsRnBGwBjAQZoDAAAAQBVAGkMAAABAE4AawwAAAEAXwBqDAAAAQBfAGwMAAABADYAbQwAAAEADwALAAQJxhfBGwBjAQRpDAAAAQBOAGsMAAABAF8AbAwAAAEANgBtDAAAAQAPABoAAgleIYQKAGMAAmgMAAABAFUAagwAAAEAXwAAAA==.Moomtir:BAAALgADCgEJAQAAAA==.Morelia:BAAALgADCgcJFAAAAA==.Morph:BAAALgADCgEJAQAAAA==.Morrist:BAAALgAECgMJAwAAAA==.',
Ms='Mskeisha:BAAALgAECgMJAwAAAA==.',
Mu='Mugsfaru:BAACLgAFFH8FAAIIAAIJhCCpZAC+AAJoDAAAAgBGAOoMAAADAF8ACAACCYQgqWQAvgACaAwAAAIARgDqDAAAAwBfAC4ABAp/HgADCAAHCUoisCQARAIACAAHCUoisCQARAIAGwADCccOKmwAjgAAAAA=.',
Na='Nabecovid:BAACLgAFFH8RAAIcAAQJxhFrCgD5AARoDAAABwBQAGkMAAADAC4AawwAAAIACgDqDAAABQAsABwABAnGEWsKAPkABGgMAAAHAFAAaQwAAAMALgBrDAAAAgAKAOoMAAAFACwALgAECn86AAMcAAkJGh7/BACaAgAcAAkJGh7/BACaAgAHAAEJCBA3cwAiAAAAAA==.Nasha:BAACLgAFFH8UAAIPAAUJfBY3OQApAQVoDAAABQBAAGkMAAAFAD8AawwAAAMANgBqDAAAAgA1AOoMAAAFADAADwAFCXwWNzkAKQEFaAwAAAUAQABpDAAABQA/AGsMAAADADYAagwAAAIANQDqDAAABQAwAC4ABAp/LwACDwAJCfMflRwAjwIADwAJCfMflRwAjwIAAAA=.Natek:BAABLgAECn8fAAMQAAgJbyDZFAA0AghoDAAABABIAGkMAAAEAE4AawwAAAMAWQBqDAAAAwBUAGwMAAAFAFQAbQwAAAQAVgDqDAAABABQAG4MAAAEAFgAEAAICW8g2RQANAIIaAwAAAQASABpDAAAAwBOAGsMAAADAFkAagwAAAMAVABsDAAABQBUAG0MAAAEAFYA6gwAAAMAUABuDAAAAgBYABYAAwngFhCLALIAA2kMAAABAD4A6gwAAAEAPwBuDAAAAgAxAAAA.',
Ni='Nightprowlr:BAAALgAFFAIJAgABLgAFFAMJAwAJAAAAAA==.',
Oo='Oogglytotems:BAAALgADCgQJBAAAAA==.Ooggmonk:BAAALgADCgUJBQAAAA==.',
Or='Orb:BAAALgADCgEJAQAAAA==.Orcangel:BAAALgAECgEJAQAAAA==.',
Ow='Owlbundy:BAAALgAECgcJBAAAAA==.',
Pa='Pablofanques:BAAALgAECgQJBQAAAA==.Pantojak:BAACLgAFFH8WAAIBAAYJNRv5DQCiAQZoDAAABgBRAGkMAAAGAFgAawwAAAMAMABqDAAAAgA1AGwMAAABADcA6gwAAAQASQABAAYJNRv5DQCiAQZoDAAABgBRAGkMAAAGAFgAawwAAAMAMABqDAAAAgA1AGwMAAABADcA6gwAAAQASQAuAAQKfxoAAgEACAkpIj0kAIEBAAEACAkpIj0kAIEBAAAA.Parksnar:BAAALgAECgcJEwAAAA==.',
Pe='Peekabull:BAAALgAECgMJBgAAAA==.Pepe:BAAALgAECgUJCgAAAA==.',
Ph='Phouchg:BAACLgAFFH8OAAMXAAQJOyU2BQClAQRoDAAABQBcAGkMAAAEAF4AawwAAAIAYwDqDAAAAwBeABcABAk7JTYFAKUBBGgMAAAEAFwAaQwAAAQAXgBrDAAAAgBjAOoMAAADAF4ACAABCb0fipEASwABaAwAAAEAUQAuAAQKfy4ABBcACQm5IZ0DAPgCABcACQm5IZ0DAPgCAAgACAnuD9FvAFUBABsABwlJFrkPAFEBAAAA.',
Pi='Pirotessa:BAABLgAECn8lAAINAAkJuB2RNAChAgloDAAABQBWAGkMAAAHAFEAawwAAAcAWQBqDAAABQBWAGwMAAADAFAAbQwAAAEARADqDAAABgBfAG4MAAACAB0AbwwAAAEATQANAAkJuB2RNAChAgloDAAABQBWAGkMAAAHAFEAawwAAAcAWQBqDAAABQBWAGwMAAADAFAAbQwAAAEARADqDAAABgBfAG4MAAACAB0AbwwAAAEATQAAAA==.',
Ra='Ranore:BAAALgADCggJJQABLgAECgkJPwADAL4eAA==.Rathimus:BAAALgAECgIJAgAAAA==.Rayven:BAAALgAECgEJAQAAAA==.',
Re='Reimdh:BAAALgAECgEJAQABLgAFFAcJGwACADwSAA==.Reptar:BAABLgAFFH8MAAIHAAYJOyXlAQAhAgZoDAAAAwBiAGkMAAACAGAAawwAAAIAYQBqDAAAAQBWAOoMAAADAGIAbgwAAAEAVgAHAAYJOyXlAQAhAgZoDAAAAwBiAGkMAAACAGAAawwAAAIAYQBqDAAAAQBWAOoMAAADAGIAbgwAAAEAVgABLgAFFAcJHQABAH4UAA==.',
Ri='Rianor:BAAALgAECgEJAQAAAA==.Richardtwist:BAAALgAECgEJAwAAAA==.',
Ro='Roaar:BAAALgAECgMJAwAAAA==.Robinhoof:BAAALgADCgYJBwAAAA==.Rocko:BAAALgAECgcJEwAAAA==.Rourke:BAABLgAFFH8FAAIIAAMJIhT0TwDzAANoDAAAAgBQAGkMAAABADgA6gwAAAIAEgAIAAMJIhT0TwDzAANoDAAAAgBQAGkMAAABADgA6gwAAAIAEgAAAA==.Roxbox:BAAALgAFFAMJAwAAAA==.',
Ry='Ryukyu:BAACLgAFFH8JAAMaAAMJGBXuCwBNAANoDAAABAA7AGkMAAADADYA6gwAAAIAMAALAAIJFhZ1SgCKAAJoDAAABAA7AGkMAAADADYAGgABCRwT7gsATQAB6gwAAAIAMAAuAAQKfy8AAwsACQkiG2QRAFICAAsACQmyGmQRAFICABoABgkJFVElAPoAAAAA.',
Sa='Savz:BAAALgADCgQJBAABLgAECgYJBgAJAAAAAA==.',
Sc='Schro:BAAALgAECgYJBwAAAA==.Schrolock:BAABLgAECn8VAAMUAAgJ7w/mbQCFAQhoDAAAAwAnAGkMAAADAC0AawwAAAMAQgBqDAAABAAgAGwMAAAEADQA6gwAAAIAHwBuDAAAAQAVAG8MAAABAB0AFAAICe8P5m0AhQEIaAwAAAMAJwBpDAAAAwAtAGsMAAADAEIAagwAAAEAIABsDAAABAA0AOoMAAACAB8AbgwAAAEAFQBvDAAAAQAdABkAAQkAACZzADIAAWoMAAADABkAAAA=.',
Sh='Shortbread:BAAALgADCgkJAwAAAA==.',
Sp='Sprung:BAAALgAECgQJCwAAAA==.Spyla:BAAALgAECgQJDQAAAA==.',
St='Steven:BAAALgAECgMJBQABLgAFFAMJCQAaABgVAA==.',
Su='Supermouse:BAABLgAECn8mAAIVAAgJ/BzmBwADAghoDAAABgBPAGkMAAAFAEYAawwAAAYAUwBqDAAABgBWAGwMAAAGAEQAbQwAAAIASQDqDAAABgBPAG4MAAABAEEAFQAICfwc5gcAAwIIaAwAAAYATwBpDAAABQBGAGsMAAAGAFMAagwAAAYAVgBsDAAABgBEAG0MAAACAEkA6gwAAAYATwBuDAAAAQBBAAAA.',
To='Tophat:BAACLgAFFH8IAAINAAgJdgDtkACcAAhoDAAAAQADAGkMAAABAAAAawwAAAEAAABqDAAAAQAGAGwMAAABAAIAbQwAAAEAAADqDAAAAQAAAG4MAAABAAAADQAICXYA7ZAAnAAIaAwAAAEAAwBpDAAAAQAAAGsMAAABAAAAagwAAAEABgBsDAAAAQACAG0MAAABAAAA6gwAAAEAAABuDAAAAQAAAC4ABAp/GQACDQAICWoH1J8ANgEADQAICWoH1J8ANgEAAAA=.',
Tw='Twoinchfury:BAACLgAFFH8PAAIdAAQJFxTSEwDzAARoDAAABQAvAGkMAAAFAEYAawwAAAEAGQDqDAAABAA9AB0ABAkXFNITAPMABGgMAAAFAC8AaQwAAAUARgBrDAAAAQAZAOoMAAAEAD0ALgAECn8yAAIdAAkJ8BepDAAVAgAdAAkJ8BepDAAVAgAAAA==.',
Va='Vaihlor:BAAALgAECgEJAQAAAA==.',
Ve='Velaris:BAAALgADCgEJAQABLgAECgkJJAARAL8cAA==.Veledin:BAABLgAECn8UAAMCAAgJ/hUoPQDHAQhoDAAAAgAsAGkMAAADADYAawwAAAMARQBqDAAABgBXAGwMAAABACIAbQwAAAEANQDqDAAAAwA9AG8MAAABAEsAAgAICf4VKD0AxwEIaAwAAAIALABpDAAAAwA2AGsMAAADAEUAagwAAAUAVwBsDAAAAQAiAG0MAAABADUA6gwAAAMAPQBvDAAAAQBLAAQAAQkAAFQ+AAAAAWoMAAABACkAAS4ABRQBCQEACQAAAAA=.Vergil:BAACLgAFFH8KAAIDAAQJnA7bEAAJAQRoDAAABAA0AGkMAAADAC0AawwAAAIAEwDqDAAAAQAgAAMABAmcDtsQAAkBBGgMAAAEADQAaQwAAAMALQBrDAAAAgATAOoMAAABACAALgAECn8lAAMDAAkJAxvgCgBpAgADAAkJ0xrgCgBpAgACAAMJbgP4+ABDAAAAAA==.Veroq:BAAALgADCgcJCAAAAA==.',
Wa='Wachabe:BAABLgAECn8pAAIHAAkJzRb7DAAAAgloDAAABgA8AGkMAAAFAB4AawwAAAQAKQBqDAAABAAeAGwMAAAFADgAbQwAAAIAOwDqDAAABwBRAG4MAAAFAE0AbwwAAAMAOwAHAAkJzRb7DAAAAgloDAAABgA8AGkMAAAFAB4AawwAAAQAKQBqDAAABAAeAGwMAAAFADgAbQwAAAIAOwDqDAAABwBRAG4MAAAFAE0AbwwAAAMAOwAAAA==.',
We='Weiden:BAACLgAFFH8RAAIGAAQJvAwVJQDwAARoDAAABwAvAGkMAAAFACsAawwAAAIAEADqDAAAAwAVAAYABAm8DBUlAPAABGgMAAAHAC8AaQwAAAUAKwBrDAAAAgAQAOoMAAADABUALgAECn85AAIGAAkJ1RgUFgATAgAGAAkJ1RgUFgATAgAAAA==.',
Yo='Yourpal:BAAALgAECgQJBAAAAA==.',
Yr='Yrene:BAAALgAECgEJAgAAAA==.',
Yu='Yulwei:BAAALgAECggJEAAAAA==.',
['Yô']='Yôu:BAAALgAECgEJAgAAAA==.',
Za='Zahard:BAAALgAECgYJBgAAAA==.',
Ze='Zeldah:BAAALgAFFAEJAQABLgAFFAMJCQAaABgVAA==.Zenroj:BAAALgADCgYJBgAAAA==.',
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
