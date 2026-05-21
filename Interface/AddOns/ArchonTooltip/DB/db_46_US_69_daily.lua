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

local lookup = {'DemonHunter-Devourer','DemonHunter-Havoc','DemonHunter-Vengeance','Druid-Restoration','Druid-Balance','Druid-Guardian','Hunter-BeastMastery','Unknown-Unknown','Evoker-Preservation','Evoker-Augmentation','Paladin-Protection','DeathKnight-Unholy','Paladin-Retribution','Priest-Holy','Priest-Shadow','Rogue-Subtlety','Warlock-Demonology','Shaman-Elemental','DeathKnight-Frost','Shaman-Restoration','Paladin-Holy','Monk-Brewmaster','Warlock-Destruction','Hunter-Marksmanship','Druid-Feral','Hunter-Survival','Mage-Frost','Evoker-Devastation','Warrior-Protection',}
local provider = {region='US',realm='Detheroc',name='US',type='daily',zone=46,date='2026-05-20',data={Ab='Abominus:BAAALgADCgMJAwAAAA==.Abrak:BAAALgAECgcJDAAAAA==.',
Ae='Aelflaed:BAAALgAECgcJDwAAAA==.Aerirea:BAAALgAECgIJAgAAAA==.Aethèr:BAAALgADCggJCQAAAA==.',
Al='Aladiirn:BAACLgAFFH8TAAIBAAUJ/xXMEgA7AQVoDAAABQBNAGkMAAAFADMAawwAAAMADQBqDAAAAQAfAOoMAAAFAFIAAQAFCf8VzBIAOwEFaAwAAAUATQBpDAAABQAzAGsMAAADAA0AagwAAAEAHwDqDAAABQBSAC4ABAp/NwAEAQAICW4kqRMAfwIAAQAICW4kqRMAfwIAAgABCT4bEWUAUAAAAwABCeADICwAJwAAAAA=.Alphapacer:BAAALgADCgcJCQAAAA==.',
As='Asha:BAABLgAECn8YAAQEAAcJuhgpUABlAQdoDAAABABDAGkMAAAEADAAawwAAAQAPgBqDAAABABcAGwMAAAEAFcAbQwAAAEAAwDqDAAAAwBRAAQABgmXHClQAGUBBmgMAAADAEMAaQwAAAMAMABrDAAAAwA+AGoMAAACAFwAbAwAAAIAVwDqDAAAAgBRAAUABwlJEdctADABB2gMAAABAEYAaQwAAAEASQBrDAAAAQBHAGoMAAABAEMAbAwAAAEAKwBtDAAAAQABAOoMAAABAAQABgACCZUKmFMAIgACagwAAAEAGQBsDAAAAQAbAAAA.Ashleeann:BAABLgAECn8YAAIHAAkJkQ0JOgDGAQloDAAABAAWAGkMAAADAC0AawwAAAMAQgBqDAAAAwAcAGwMAAAEABYAbQwAAAEAFwDqDAAAAwAhAG4MAAACACoAbwwAAAEAEwAHAAkJkQ0JOgDGAQloDAAABAAWAGkMAAADAC0AawwAAAMAQgBqDAAAAwAcAGwMAAAEABYAbQwAAAEAFwDqDAAAAwAhAG4MAAACACoAbwwAAAEAEwAAAA==.',
At='Ather:BAAALgAECgcJDwAAAA==.',
Au='Aurix:BAAALgADCgMJAwAAAA==.',
Aw='Awenyddion:BAAALgAECgUJCgABLgAECgcJDwAIAAAAAA==.',
Ba='Bayle:BAABLgAECn8VAAMJAAYJlQqbKQAmAQZoDAAABQAYAGkMAAAEAB0AawwAAAQAEgBqDAAAAwAbAGwMAAADAB0A6gwAAAIAIAAJAAYJlQqbKQAmAQZoDAAAAwAYAGkMAAADAB0AawwAAAMAEgBqDAAAAwAbAGwMAAADAB0A6gwAAAEAIAAKAAQJ0QkJSgCtAARoDAAAAgApAGkMAAABAAwAawwAAAEAHwDqDAAAAQAOAAEuAAQKCQkgAAsAiAsA.',
Bb='Bbygrl:BAAALgAFFAEJAQABLgAFFAMJBQAMAOoJAA==.',
Bo='Boabjr:BAAALgADCgUJBQAAAA==.Booner:BAAALgAECgEJAwAAAA==.Botadin:BAABLgAECn8dAAINAAcJAB1vSQDBAQdoDAAABQBbAGkMAAAFAEQAawwAAAUASABqDAAAAwBCAGwMAAADAEIA6gwAAAYAQwBuDAAAAgBOAA0ABwkAHW9JAMEBB2gMAAAFAFsAaQwAAAUARABrDAAABQBIAGoMAAADAEIAbAwAAAMAQgDqDAAABgBDAG4MAAACAE4AAAA=.',
Br='Brandrood:BAAALgAECgYJBgAAAA==.Bronst:BAAALgAECgIJAgABLgAECgYJBgAIAAAAAA==.',
Bu='Bubblemeinfy:BAAALgAECgEJAQAAAA==.',
['Bô']='Bôw:BAABLgAECn8fAAIHAAkJ0AqfQACtAQloDAAABQAYAGkMAAAFACAAawwAAAUANQBqDAAABAAmAGwMAAAEACAAbQwAAAIAGADqDAAAAwARAG4MAAACABEAbwwAAAEAEwAHAAkJ0AqfQACtAQloDAAABQAYAGkMAAAFACAAawwAAAUANQBqDAAABAAmAGwMAAAEACAAbQwAAAIAGADqDAAAAwARAG4MAAACABEAbwwAAAEAEwAAAA==.',
Ca='Calvin:BAAALgAECgEJAgAAAA==.',
Ch='Chaotic:BAAALgADCgkJDwAAAA==.',
Co='Corca:BAACLgAFFH8PAAIOAAMJNxI4FwDGAANoDAAABgAkAGkMAAAFACsA6gwAAAQAPAAOAAMJNxI4FwDGAANoDAAABgAkAGkMAAAFACsA6gwAAAQAPAAuAAQKfzQAAw4ACQnCEq4hAIcBAA4ACQnCEq4hAIcBAA8ABgneCNdHAMIAAAAA.',
Da='Dallinar:BAAALgADCgIJAgAAAA==.Darklocke:BAAALgAECgIJBQAAAA==.Dazbraz:BAAALgADCgkJCQABLgAECggJHwAQAMIaAA==.',
De='Death:BAAALgADCgYJBgABLgAFFAMJEAARAGQlAA==.Deaçon:BAAALgAECgUJDQAAAA==.Derffenator:BAAALgADCgEJAQAAAA==.',
Di='Diazz:BAAALgAECgEJAgAAAA==.Dirty:BAAALgADCgMJAwABLgAECggJHgASAOQTAA==.',
Do='Dooma:BAACLgAFFH8FAAMMAAMJ6glyewDSAANoDAAAAgAnAGkMAAABAAsA6gwAAAIAGQAMAAMJHAZyewDSAANoDAAAAQAJAGkMAAABAAsA6gwAAAIAGQATAAEJRw+YEwBPAAFoDAAAAQAnAC4ABAp/IQADDAAICUwdizAAdgIADAAICUwdizAAdgIAEwAECd8ZPxMA8QAAAAA=.',
Dp='Dps:BAAALgAECgUJCAAAAA==.',
Dr='Drakko:BAAALgAECggJDwABLgAECggJEgAIAAAAAA==.Drax:BAAALgAECgkJDAAAAA==.',
Du='Dunspore:BAABLgAECn8gAAIUAAkJrSA9BwAAAwloDAAABQBhAGkMAAAFAF0AawwAAAUAXQBqDAAABABNAGwMAAAEAFsAbQwAAAIAUQDqDAAABABeAG4MAAACAEMAbwwAAAEANgAUAAkJrSA9BwAAAwloDAAABQBhAGkMAAAFAF0AawwAAAUAXQBqDAAABABNAGwMAAAEAFsAbQwAAAIAUQDqDAAABABeAG4MAAACAEMAbwwAAAEANgAAAA==.',
Ea='Earendel:BAAALgADCgkJCQAAAA==.',
Er='Ermahn:BAAALgAECgYJDwAAAA==.',
Fi='Finalgoddk:BAAALgADCgEJAQABLgAFFAMJDAANAJglAA==.Finalgodfury:BAACLgAFFH8MAAINAAMJmCWBIwBAAQNoDAAABQBhAGkMAAAEAGAA6gwAAAMAXwANAAMJmCWBIwBAAQNoDAAABQBhAGkMAAAEAGAA6gwAAAMAXwAuAAQKfygAAg0ACAkBJiUJAEkDAA0ACAkBJiUJAEkDAAAA.',
Fo='Foxydots:BAAALgAECgYJCAAAAA==.',
Fr='Frostscythe:BAAALgAECgMJAwAAAA==.',
Fu='Furmidable:BAAALgADCgcJBwAAAA==.',
Gi='Girrzz:BAAALgAECgUJCwAAAA==.Girthspell:BAAALgAECgEJAQAAAA==.',
Gr='Grand:BAACLgAFFH8PAAIVAAMJ/SPWFwAsAQNoDAAABgBcAGkMAAAFAFUA6gwAAAQAYQAVAAMJ/SPWFwAsAQNoDAAABgBcAGkMAAAFAFUA6gwAAAQAYQAuAAQKfzgAAhUACQl9It4EAB4DABUACQl9It4EAB4DAAAA.Grock:BAABLgAECn8oAAMUAAkJfxSsGwAzAgloDAAABgBMAGkMAAAGAEgAawwAAAYAUQBqDAAABgA/AGwMAAAFACwAbQwAAAMAHADqDAAABQAtAG4MAAACACEAbwwAAAEAGgAUAAkJfxSsGwAzAgloDAAABQBMAGkMAAAFAEgAawwAAAUAUQBqDAAABQA/AGwMAAAEACwAbQwAAAMAHADqDAAABAAtAG4MAAABACEAbwwAAAEAGgASAAcJtgQjTADHAAdoDAAAAQASAGkMAAABAA8AawwAAAEACwBqDAAAAQAIAGwMAAABAAMA6gwAAAEACQBuDAAAAQANAAAA.Grundlegut:BAAALgAECgEJAQAAAA==.Grundletap:BAAALgADCgEJAgAAAA==.',
Gx='Gxxse:BAABLgAECn8fAAIQAAgJwhpGGABFAghoDAAABQBIAGkMAAAEAEwAawwAAAQASABqDAAABAAxAGwMAAACAEAAbQwAAAIAHgDqDAAABwBDAG4MAAADAF8AEAAICcIaRhgARQIIaAwAAAUASABpDAAABABMAGsMAAAEAEgAagwAAAQAMQBsDAAAAgBAAG0MAAACAB4A6gwAAAcAQwBuDAAAAwBfAAAA.',
He='Hewman:BAAALgAECgQJBwAAAA==.Hezzding:BAAALgADCgIJAgAAAA==.',
Ho='Hogar:BAAALgAECgYJBgABLgAFFAUJDAAWACwXAA==.',
Hu='Hugehippo:BAAALgAECgQJBAAAAA==.Hunanchicken:BAAALgAECgEJAQAAAA==.',
Ic='Icebox:BAAALgAECgYJBgAAAA==.Icejesterr:BAAALgAECgUJDAAAAA==.',
Ig='Ignorepain:BAAALgAECgYJDQAAAA==.',
Il='Illigiggle:BAAALgADCgYJCQAAAA==.Illioogg:BAAALgADCgMJAwAAAA==.',
Im='Imptastic:BAAALgAECgUJBwAAAA==.',
In='Industdoom:BAAALgAECgEJAQAAAA==.',
Ir='Ironstock:BAAALgADCgEJAQAAAA==.',
Je='Jesterpal:BAAALgAECgYJDgAAAA==.',
Jo='Joj:BAAALgAECgYJBwAAAA==.Jollyolly:BAABLgAECn8nAAMXAAkJXRmEDQAvAQloDAAABgBZAGkMAAAGAEsAawwAAAcARgBqDAAABABDAGwMAAAEADEAbQwAAAIAJwDqDAAABwBZAG4MAAACACMAbwwAAAEARQARAAgJ6RQgTACVAQhoDAAAAgAyAGkMAAADAEsAawwAAAIAOgBsDAAAAgAxAG0MAAABACcA6gwAAAUAPwBuDAAAAQAVAG8MAAABAEUAFwAICb0WhA0ALwEIaAwAAAQAWQBpDAAAAwA2AGsMAAAFAEYAagwAAAQAQwBsDAAAAgAnAG0MAAABAB0A6gwAAAIAWQBuDAAAAQAjAAAA.',
Ju='Juvens:BAAALgAECgEJAQAAAA==.Jux:BAAALgADCgMJAwAAAA==.',
Ka='Kalleo:BAAALgADCgIJAgAAAA==.Karma:BAAALgADCgQJBAAAAA==.',
Ko='Korath:BAAALgAECgYJBgABLgAFFAUJDAAWACwXAA==.',
Kr='Krimzin:BAAALgAECgEJAgABLgAFFAUJEQAHAAwdAA==.',
Ky='Kynrina:BAAALgADCgEJAQAAAA==.',
La='Ladrill:BAAALgADCgcJBwAAAA==.Lainarning:BAAALgAECgMJBAAAAA==.',
Le='Lewiz:BAAALgAECgYJDgAAAA==.',
Li='Lightsnack:BAAALgAECgEJAgAAAA==.',
Lu='Lucetia:BAAALgAECgEJAgAAAA==.',
Ma='Machooze:BAAALgAECgIJAgAAAA==.Magifrey:BAAALgAECgEJAgAAAA==.Masha:BAAALgADCgYJBgAAAA==.Mazikene:BAAALgAECgEJAQAAAA==.',
Mi='Mirabeaux:BAAALgAECgYJCAAAAA==.',
Mo='Moomtir:BAAALgADCgEJAQAAAA==.Morelia:BAAALgADCgcJFAAAAA==.Morph:BAAALgADCgEJAQAAAA==.Morrist:BAAALgAECgMJAwAAAA==.',
Ms='Mskeisha:BAAALgAECgMJAwAAAA==.',
Mu='Mugsfaru:BAABLgAECn8dAAMHAAcJSSJKLwDoAQdoDAAABgBiAGkMAAAFAF0AawwAAAUAWQBqDAAABABhAGwMAAAEAGEAbQwAAAEAOgDqDAAABABZAAcABwlJIkovAOgBB2gMAAAFAGIAaQwAAAUAXQBrDAAABQBZAGoMAAAEAGEAbAwAAAMAYQBtDAAAAQA6AOoMAAABAFkAGAADCccOKmwAjgADaAwAAAEALwBsDAAAAQARAOoMAAADADAAAAA=.',
Na='Nabecovid:BAACLgAFFH8MAAIZAAMJMxPYBwD0AANoDAAABgA/AGkMAAACAC4A6gwAAAQAJQAZAAMJMxPYBwD0AANoDAAABgA/AGkMAAACAC4A6gwAAAQAJQAuAAQKfzcAAxkACQkZHloDAKsCABkACQkZHloDAKsCAAYAAQkIENNRACYAAAAA.Nasha:BAACLgAFFH8KAAINAAQJQBZtJAA+AQRoDAAAAwA/AGkMAAADAD8AawwAAAEANADqDAAAAwAwAA0ABAlAFm0kAD4BBGgMAAADAD8AaQwAAAMAPwBrDAAAAQA0AOoMAAADADAALgAECn8vAAINAAkJ8h+cEwCqAgANAAkJ8h+cEwCqAgAAAA==.Natek:BAABLgAECn8fAAMSAAgJZSC8DwBCAghoDAAABABIAGkMAAAEAE4AawwAAAMAWQBqDAAAAwBUAGwMAAAFAFQAbQwAAAQAVQDqDAAABABQAG4MAAAEAFgAEgAICWUgvA8AQgIIaAwAAAQASABpDAAAAwBOAGsMAAADAFkAagwAAAMAVABsDAAABQBUAG0MAAAEAFUA6gwAAAMAUABuDAAAAgBYABQAAwngFkhzALcAA2kMAAABAD4A6gwAAAEAPwBuDAAAAgAxAAAA.',
Ni='Nightprowlr:BAAALgAECggJEwAAAA==.',
Oo='Oogglytotems:BAAALgADCgQJBAAAAA==.Ooggmonk:BAAALgADCgUJBQAAAA==.',
Or='Orb:BAAALgADCgEJAQAAAA==.',
Ow='Owlbundy:BAAALgAECgcJBAAAAA==.',
Pa='Pablofanques:BAAALgAECgQJBQAAAA==.Pantojak:BAACLgAFFH8MAAIWAAUJLBdnFgA0AQVoDAAABABCAGkMAAAEAFYAawwAAAEAGABqDAAAAQAvAOoMAAACADsAFgAFCSwXZxYANAEFaAwAAAQAQgBpDAAABABWAGsMAAABABgAagwAAAEALwDqDAAAAgA7AC4ABAp/GQACFgAHCX8hziUA1QEAFgAHCX8hziUA1QEAAAA=.Parksnar:BAAALgAECgcJEAAAAA==.',
Pe='Pepe:BAAALgAECgUJCgAAAA==.',
Ph='Phouchg:BAACLgAFFH8JAAMaAAMJoyTHDABGAQNoDAAABABcAGkMAAADAF4A6gwAAAIAXgAaAAMJoyTHDABGAQNoDAAAAwBcAGkMAAADAF4A6gwAAAIAXgAHAAEJvR+9aQBQAAFoDAAAAQBRAC4ABAp/KgAEGgAJCYYhcQIAAwMAGgAJCYYhcQIAAwMAGAAHCUkW2wwAXwEABwAICe4PO1oAWwEAAAA=.',
Pi='Pirotessa:BAABLgAECn8lAAIbAAkJuB2RNAChAgloDAAABQBWAGkMAAAHAFEAawwAAAcAWQBqDAAABQBWAGwMAAADAFAAbQwAAAEARADqDAAABgBfAG4MAAACAB0AbwwAAAEATQAbAAkJuB2RNAChAgloDAAABQBWAGkMAAAHAFEAawwAAAcAWQBqDAAABQBWAGwMAAADAFAAbQwAAAEARADqDAAABgBfAG4MAAACAB0AbwwAAAEATQAAAA==.',
Ra='Ranore:BAAALgADCggJJQABLgAECgkJLQACAPAdAA==.Rathimus:BAAALgAECgIJAgAAAA==.Rayven:BAAALgAECgEJAQAAAA==.',
Re='Reimdh:BAAALgAECgEJAQABLgAFFAUJEwABAP8VAA==.Reptar:BAABLgAFFH8HAAIGAAUJhyUNAgC9AQVoDAAAAgBeAGkMAAABAGAAawwAAAEAYQBqDAAAAQBWAOoMAAACAGAABgAFCYclDQIAvQEFaAwAAAIAXgBpDAAAAQBgAGsMAAABAGEAagwAAAEAVgDqDAAAAgBgAAEuAAUUBwkdABYAfBQA.',
Ri='Rianor:BAAALgAECgEJAQAAAA==.Richardtwist:BAAALgAECgEJAwAAAA==.',
Ro='Robinhoof:BAAALgADCgYJBwAAAA==.Rocko:BAAALgAECgcJEwAAAA==.Roxbox:BAAALgAECgUJBwAAAA==.',
Ry='Ryukyu:BAABLgAECn8tAAMKAAkJ5hkPFAAQAgloDAAACABRAGkMAAAHAEkAawwAAAgAUwBqDAAABQBFAGwMAAAFAEcAbQwAAAEAPwDqDAAACAA2AG4MAAABADkAbwwAAAIALgAKAAgJaxoPFAAQAghoDAAACABRAGkMAAAGAEkAawwAAAcAUwBqDAAABABFAGwMAAADAEcAbQwAAAEAPwDqDAAABwA2AG8MAAACAC4AHAAGCQkVUSUA+gAGaQwAAAEAOwBrDAAAAQAtAGoMAAABACsAbAwAAAIAOQDqDAAAAQAxAG4MAAABADkAAAA=.',
Sa='Savz:BAAALgADCgQJBAABLgAECgYJBgAIAAAAAA==.',
Sc='Schro:BAAALgAECgYJBgAAAA==.Schrolock:BAABLgAECn8VAAMRAAgJ7w/mbQCFAQhoDAAAAwAnAGkMAAADAC0AawwAAAMAQgBqDAAABAAgAGwMAAAEADQA6gwAAAIAHwBuDAAAAQAVAG8MAAABAB0AEQAICe8P5m0AhQEIaAwAAAMAJwBpDAAAAwAtAGsMAAADAEIAagwAAAEAIABsDAAABAA0AOoMAAACAB8AbgwAAAEAFQBvDAAAAQAdABcAAQkAACZzADIAAWoMAAADABkAAAA=.',
Sh='Shortbread:BAAALgADCgkJAwAAAA==.',
Sp='Sprung:BAAALgAECgQJCwAAAA==.Spyla:BAAALgAECgQJDQAAAA==.',
St='Steven:BAAALgAECgMJBAABLgAECgkJLQAKAOYZAA==.',
Su='Supermouse:BAABLgAECn8mAAITAAgJ/RxgBQAUAghoDAAABgBPAGkMAAAFAEYAawwAAAYAUwBqDAAABgBWAGwMAAAGAEQAbQwAAAIASQDqDAAABgBPAG4MAAABAEEAEwAICf0cYAUAFAIIaAwAAAYATwBpDAAABQBGAGsMAAAGAFMAagwAAAYAVgBsDAAABgBEAG0MAAACAEkA6gwAAAYATwBuDAAAAQBBAAAA.',
To='Tophat:BAABLgAECn8VAAIbAAYJLQivvADoAAZoDAAABAAZAGkMAAAFAB0AawwAAAUAFgBqDAAAAwAhAGwMAAABAA4A6gwAAAMADAAbAAYJLQivvADoAAZoDAAABAAZAGkMAAAFAB0AawwAAAUAFgBqDAAAAwAhAGwMAAABAA4A6gwAAAMADAAAAA==.',
Tw='Twoinchfury:BAACLgAFFH8GAAIdAAMJ9hR/EwDQAANoDAAAAgAcAGkMAAACAEYA6gwAAAIAPQAdAAMJ9hR/EwDQAANoDAAAAgAcAGkMAAACAEYA6gwAAAIAPQAuAAQKfzIAAh0ACQnwFzUJADUCAB0ACQnwFzUJADUCAAAA.',
Va='Vaihlor:BAAALgAECgEJAQAAAA==.',
Ve='Velaris:BAAALgADCgEJAQAAAA==.Veledin:BAAALgAECggJEgAAAA==.Vergil:BAACLgAFFH8GAAICAAMJhg33DwDaAANoDAAAAwAgAGkMAAACACcA6gwAAAEAIAACAAMJhg33DwDaAANoDAAAAwAgAGkMAAACACcA6gwAAAEAIAAuAAQKfx8AAwIACQnAGZMJAFcCAAIACQmQGZMJAFcCAAEAAwluA5nWAEcAAAAA.Veroq:BAAALgADCgcJCAAAAA==.',
Wa='Wachabe:BAABLgAECn8fAAIGAAgJphJ+EwBsAQhoDAAABQAcAGkMAAAFAB4AawwAAAQAKQBqDAAABAAeAGwMAAADADEAbQwAAAEAGQDqDAAABgBRAG4MAAADAE0ABgAICaYSfhMAbAEIaAwAAAUAHABpDAAABQAeAGsMAAAEACkAagwAAAQAHgBsDAAAAwAxAG0MAAABABkA6gwAAAYAUQBuDAAAAwBNAAAA.',
We='Weiden:BAACLgAFFH8MAAIFAAMJiAvIIwDHAANoDAAABgAXAGkMAAAEACsA6gwAAAIAFQAFAAMJiAvIIwDHAANoDAAABgAXAGkMAAAEACsA6gwAAAIAFQAuAAQKfzcAAgUACQnVGEYRAB4CAAUACQnVGEYRAB4CAAAA.',
Yo='Yourpal:BAAALgADCgMJBAAAAA==.',
Yu='Yulwei:BAAALgAECggJEAAAAA==.',
['Yô']='Yôu:BAAALgADCgkJCwAAAA==.',
Za='Zahard:BAAALgAECgYJBgAAAA==.',
Ze='Zeldah:BAAALgAECgcJCQABLgAECgkJLQAKAOYZAA==.',
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
