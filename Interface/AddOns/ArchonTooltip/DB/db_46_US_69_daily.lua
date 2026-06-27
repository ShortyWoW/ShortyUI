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

local lookup = {'Monk-Brewmaster','DemonHunter-Devourer','DemonHunter-Havoc','DemonHunter-Vengeance','Druid-Restoration','Druid-Balance','Druid-Guardian','Hunter-BeastMastery','Unknown-Unknown','Evoker-Preservation','Evoker-Augmentation','Mage-Frost','DeathKnight-Unholy','Paladin-Retribution','Shaman-Elemental','Hunter-Survival','Priest-Holy','Priest-Shadow','Rogue-Subtlety','Warlock-Demonology','DeathKnight-Frost','Paladin-Holy','Shaman-Restoration','DeathKnight-Blood','Warlock-Destruction','Evoker-Devastation','Hunter-Marksmanship','Druid-Feral','Shaman-Enhancement','Warrior-Protection',}
local provider = {region='US',realm='Detheroc',name='US',type='daily',zone=46,date='2026-06-26',data={Ab='Abominus:BAAALgADCgMJAwAAAA==.Abrak:BAAALgAECgcJDQAAAA==.',
Ae='Aelflaed:BAAALgAECgcJDwAAAA==.Aeolia:BAAALgAECgEJAQABLgAFFAYJFgABADUbAA==.Aerirea:BAAALgAECgcJCwAAAA==.Aethèr:BAAALgADCggJCQAAAA==.',
Al='Aladiirn:BAACLgAFFH8iAAICAAcJPBOvIACzAQdoDAAACABNAGkMAAAIAEQAawwAAAUAHABqDAAAAgAfAG0MAAABABAA6gwAAAkAUgBuDAAAAQAWAAIABwk8E68gALMBB2gMAAAIAE0AaQwAAAgARABrDAAABQAcAGoMAAACAB8AbQwAAAEAEADqDAAACQBSAG4MAAABABYALgAECn89AAQCAAgJbiTQGgBzAgACAAgJbiTQGgBzAgADAAEJPhsRZQBQAAAEAAMJ9gObMABBAAAAAA==.Alphapacer:BAAALgADCgcJCQAAAA==.',
An='Anthria:BAAALgAECgMJAwABLgAFFAYJFgABADUbAA==.',
As='Asha:BAABLgAECn8YAAQFAAcJuRgpUABlAQdoDAAABABDAGkMAAAEADAAawwAAAQAPgBqDAAABABcAGwMAAAEAFcAbQwAAAEAAwDqDAAAAwBRAAUABgmXHClQAGUBBmgMAAADAEMAaQwAAAMAMABrDAAAAwA+AGoMAAACAFwAbAwAAAIAVwDqDAAAAgBRAAYABwlJEZA5ACwBB2gMAAABAEYAaQwAAAEASQBrDAAAAQBHAGoMAAABAEMAbAwAAAEAKwBtDAAAAQABAOoMAAABAAQABwACCZUKAYEAIAACagwAAAEAGQBsDAAAAQAbAAAA.Ashaii:BAAALgADCgEJAQAAAA==.Ashleeann:BAABLgAECn8YAAIIAAkJkQ0JOgDGAQloDAAABAAWAGkMAAADAC0AawwAAAMAQgBqDAAAAwAcAGwMAAAEABYAbQwAAAEAFwDqDAAAAwAhAG4MAAACACoAbwwAAAEAEwAIAAkJkQ0JOgDGAQloDAAABAAWAGkMAAADAC0AawwAAAMAQgBqDAAAAwAcAGwMAAAEABYAbQwAAAEAFwDqDAAAAwAhAG4MAAACACoAbwwAAAEAEwAAAA==.',
At='Ather:BAAALgAECgcJDwAAAA==.',
Au='Aulton:BAAALgADCgIJAgAAAA==.Aurix:BAAALgADCgMJAwAAAA==.',
Aw='Awenyddion:BAAALgAECgUJCgABLgAECgcJDwAJAAAAAA==.',
Ba='Bayle:BAABLgAECn8bAAMKAAkJoAubKQAmAQloDAAABgAYAGkMAAAEAB0AawwAAAQAEgBqDAAAAwAbAGwMAAADAB0AbQwAAAEAVQDqDAAAAgAgAG4MAAACAAwAbwwAAAIABwAKAAgJ7AibKQAmAQhoDAAAAwAYAGkMAAADAB0AawwAAAMAEgBqDAAAAwAbAGwMAAADAB0A6gwAAAEAIABuDAAAAQAMAG8MAAABAAcACwAHCYAKFFgA0gAHaAwAAAMALABpDAAAAQAMAGsMAAABAB8AbQwAAAEAIQDqDAAAAQAOAG4MAAABAB8AbwwAAAEAEwAAAA==.',
Bb='Bbygrl:BAABLgAFFH8FAAIMAAIJ/wjFsgBvAAJpDAAAAQACAOoMAAAEACsADAACCf8IxbIAbwACaQwAAAEAAgDqDAAABAArAAEuAAUUAwkHAA0Abg8A.',
Bo='Boabjr:BAAALgADCgUJBQAAAA==.Boldin:BAAALgAECgMJAwAAAA==.Booner:BAAALgAECgEJAwAAAA==.Botadin:BAABLgAECn82AAIOAAkJkiDAAQBZAgloDAAACABgAGkMAAAIAGEAawwAAAgAVQBqDAAABgBOAGwMAAAGAEYAbQwAAAIATwDqDAAACABbAG4MAAAHAE4AbwwAAAEAQwAOAAkJkiDAAQBZAgloDAAACABgAGkMAAAIAGEAawwAAAgAVQBqDAAABgBOAGwMAAAGAEYAbQwAAAIATwDqDAAACABbAG4MAAAHAE4AbwwAAAEAQwAAAA==.',
Br='Brandrood:BAAALgAECgYJBgAAAA==.Bronst:BAAALgAECgIJAgABLgAECgkJMQAPAOYYAA==.',
Bu='Bubblemeinfy:BAAALgAECgEJAQAAAA==.',
['Bô']='Bôw:BAABLgAECn8fAAIIAAkJ0AqfQACtAQloDAAABQAYAGkMAAAFACAAawwAAAUANQBqDAAABAAmAGwMAAAEACAAbQwAAAIAGADqDAAAAwARAG4MAAACABEAbwwAAAEAEwAIAAkJ0AqfQACtAQloDAAABQAYAGkMAAAFACAAawwAAAUANQBqDAAABAAmAGwMAAAEACAAbQwAAAIAGADqDAAAAwARAG4MAAACABEAbwwAAAEAEwAAAA==.',
Ce='Cerinis:BAABLgAFFH8GAAIQAAIJKBDaDQBQAAJoDAAAAgAYAOoMAAAEADoAEAACCSgQ2g0AUAACaAwAAAIAGADqDAAABAA6AAAA.',
Ch='Chairmanmao:BAAALgAECgMJAwAAAA==.Chaotic:BAAALgADCgkJDwAAAA==.',
Co='Corca:BAACLgAFFH8XAAIRAAQJHw6jHQDMAARoDAAACAAkAGkMAAAHACsAawwAAAIABADqDAAABgA8ABEABAkfDqMdAMwABGgMAAAIACQAaQwAAAcAKwBrDAAAAgAEAOoMAAAGADwALgAECn83AAMRAAkJwhIRKgB3AQARAAkJwhIRKgB3AQASAAYJ3gjXRwDCAAAAAA==.',
Da='Dallinar:BAAALgADCgIJAgAAAA==.Darklocke:BAAALgAECgUJCwAAAA==.Dazbraz:BAAALgADCgkJCQABLgAFFAcJEwATAEgMAA==.',
De='Death:BAAALgADCgYJBgABLgAFFAYJFQAUAEweAA==.Deaçon:BAAALgAECgUJDQAAAA==.Derffenator:BAAALgADCgEJAQAAAA==.',
Di='Diazz:BAAALgAECgEJAgAAAA==.Dirty:BAAALgADCgMJAwABLgAECggJHgAPAOQTAA==.',
Do='Dooma:BAACLgAFFH8HAAMNAAMJbg/msQDAAANoDAAAAgAnAGkMAAABAAsA6gwAAAQAQwANAAMJoAvmsQDAAANoDAAAAQAJAGkMAAABAAsA6gwAAAMAQwAVAAIJlw44IACGAAJoDAAAAQAnAOoMAAABACMALgAECn8jAAMNAAkJeh4IMwAyAgANAAkJeh4IMwAyAgAVAAUJDxiWFgAkAQAAAA==.',
Dp='Dps:BAAALgAECgUJCAAAAA==.',
Dr='Drakjob:BAAALgADCgkJCgABLgAFFAQJFwAWABojAA==.Drakko:BAAALgAECggJDwABLgAFFAIJBgAQACgQAA==.Drax:BAAALgAECgkJDAAAAA==.Droplock:BAAALgAECgEJAgAAAA==.',
Du='Dunspore:BAABLgAECn8gAAIXAAkJrSA9BwAAAwloDAAABQBhAGkMAAAFAF0AawwAAAUAXQBqDAAABABNAGwMAAAEAFsAbQwAAAIAUQDqDAAABABeAG4MAAACAEMAbwwAAAEANgAXAAkJrSA9BwAAAwloDAAABQBhAGkMAAAFAF0AawwAAAUAXQBqDAAABABNAGwMAAAEAFsAbQwAAAIAUQDqDAAABABeAG4MAAACAEMAbwwAAAEANgAAAA==.',
Ea='Earendel:BAAALgADCgkJCQAAAA==.',
Er='Ermahn:BAAALgAECgYJEwAAAA==.',
Fi='Finalgoddk:BAAALgADCgkJCgABLgAFFAQJDQAOANMiAA==.Finalgodfury:BAACLgAFFH8NAAIOAAQJ0yJyKABpAQRoDAAABQBhAGkMAAAEAGAAawwAAAEAQwDqDAAAAwBfAA4ABAnTInIoAGkBBGgMAAAFAGEAaQwAAAQAYABrDAAAAQBDAOoMAAADAF8ALgAECn8oAAIOAAgJAiYlCQBJAwAOAAgJAiYlCQBJAwAAAA==.Fingbang:BAAALgADCgYJBgABLgAFFAMJAwAJAAAAAA==.',
Fo='Fooshg:BAAALgAECgEJAQABLgAFFAQJEQAQADslAA==.Foxinhood:BAAALgAFFAMJAwAAAA==.Foxydots:BAAALgAECgYJCAAAAA==.',
Fr='Frigidfire:BAAALgAECgEJBAAAAA==.Frostscythe:BAAALgAECgMJAwAAAA==.',
Fu='Furmidable:BAAALgADCggJCQAAAA==.',
Gi='Girrzz:BAAALgAECgcJEQAAAA==.Girthspell:BAAALgAECgEJAQAAAA==.Girthtrude:BAAALgAECgEJAQAAAA==.',
Gr='Grand:BAACLgAFFH8XAAIWAAQJGiNvFgB0AQRoDAAACABcAGkMAAAHAFUAawwAAAIAUwDqDAAABgBhABYABAkaI28WAHQBBGgMAAAIAFwAaQwAAAcAVQBrDAAAAgBTAOoMAAAGAGEALgAECn87AAIWAAkJfSLCBwAQAwAWAAkJfSLCBwAQAwAAAA==.Grock:BAABLgAECn83AAMXAAkJFh31AQD2AQloDAAACABPAGkMAAAIAFwAawwAAAgAWABqDAAABwBOAGwMAAAGAFwAbQwAAAMAHADqDAAACQBQAG4MAAAEAFUAbwwAAAIALAAXAAkJFh31AQD2AQloDAAABwBPAGkMAAAHAFwAawwAAAcAWABqDAAABgBOAGwMAAAFAFwAbQwAAAMAHADqDAAACABQAG4MAAADAFUAbwwAAAIALAAPAAcJtgQXYQDCAAdoDAAAAQASAGkMAAABAA8AawwAAAEACwBqDAAAAQAIAGwMAAABAAMA6gwAAAEACQBuDAAAAQANAAAA.Grundlegut:BAAALgAECgEJAQAAAA==.Grundletap:BAAALgADCgEJAgAAAA==.',
Gx='Gxxse:BAACLgAFFH8TAAITAAcJSAyjEgB4AQdoDAAABgA8AGkMAAAGADYAawwAAAIACwBqDAAAAQAZAGwMAAABAAgAbQwAAAEADgDqDAAAAgAnABMABwlIDKMSAHgBB2gMAAAGADwAaQwAAAYANgBrDAAAAgALAGoMAAABABkAbAwAAAEACABtDAAAAQAOAOoMAAACACcALgAECn8hAAITAAkJChtGGABFAgATAAkJChtGGABFAgAAAA==.',
He='Hewman:BAAALgAECgQJCwAAAA==.Hezzding:BAAALgADCgIJAgAAAA==.',
Ho='Hogar:BAABLgAFFH8IAAIYAAQJGw+vKwCdAARoDAAAAgAnAGkMAAACACYAagwAAAIAJgDqDAAAAgAmABgABAkbD68rAJ0ABGgMAAACACcAaQwAAAIAJgBqDAAAAgAmAOoMAAACACYAAS4ABRQGCRYAAQA1GwA=.',
Hu='Hugehippo:BAAALgAECgQJBAAAAA==.Hunanchicken:BAAALgAECgEJAQAAAA==.',
Ic='Icebox:BAAALgAECgYJBgAAAA==.Icejesterr:BAAALgAECgUJDAAAAA==.',
Ig='Ignorepain:BAAALgAECgYJDQAAAA==.',
Il='Illigiggle:BAAALgADCgYJCQAAAA==.Illioogg:BAAALgADCgMJAwAAAA==.',
Im='Imptastic:BAAALgAECggJCgAAAA==.',
In='Industdoom:BAAALgAECgEJAQAAAA==.',
Ir='Ironstock:BAAALgADCgEJAQAAAA==.',
Je='Jesterpal:BAAALgAECgYJDgAAAA==.',
Jo='Joj:BAAALgAECgYJBwAAAA==.Jollyolly:BAABLgAECn8rAAMZAAkJmRnDEQAsAQloDAAABgBZAGkMAAAHAEsAawwAAAgARgBqDAAABQBDAGwMAAAEADEAbQwAAAIAJwDqDAAACABeAG4MAAACACMAbwwAAAEARQAUAAgJ6RRoXACJAQhoDAAAAgAyAGkMAAAEAEsAawwAAAMAOgBsDAAAAgAxAG0MAAABACcA6gwAAAUAPwBuDAAAAQAVAG8MAAABAEUAGQAICQIXwxEALAEIaAwAAAQAWQBpDAAAAwA2AGsMAAAFAEYAagwAAAUAQwBsDAAAAgAnAG0MAAABAB0A6gwAAAMAXgBuDAAAAQAjAAAA.',
Ju='Juvens:BAAALgAECgEJAQAAAA==.Jux:BAAALgADCgMJAwAAAA==.',
Ka='Kahkahaka:BAAALgADCgEJAQAAAA==.Kalleo:BAAALgADCgIJAgAAAA==.Karma:BAAALgADCgQJBAAAAA==.',
Ko='Korath:BAAALgAECgYJBgABLgAFFAYJFgABADUbAA==.',
Kr='Krimzin:BAAALgAFFAIJAgABLgAFFAUJGgAIADAhAA==.',
Ky='Kynrina:BAAALgADCgEJAQAAAA==.',
La='Ladrill:BAAALgADCgcJBwAAAA==.Lainarning:BAAALgAECgMJBQAAAA==.',
Le='Lewiz:BAABLgAFFH8GAAIMAAMJRgNcLQB4AANoDAAAAwAKAGkMAAABAAkA6gwAAAIABQAMAAMJRgNcLQB4AANoDAAAAwAKAGkMAAABAAkA6gwAAAIABQAAAA==.',
Li='Lightsnack:BAAALgAECgEJAgAAAA==.',
Lu='Lucetia:BAAALgAECgEJAwAAAA==.',
Ma='Machooze:BAAALgAFFAEJAQAAAA==.Magifrey:BAAALgAECgEJAgAAAA==.Makyae:BAAALgAECgUJBwAAAA==.Masha:BAAALgADCgYJBgAAAA==.Mazikene:BAAALgAECgEJAQAAAA==.',
Mi='Minniemee:BAAALgAECgQJAQAAAA==.Mirabeaux:BAAALgAECgYJCQAAAA==.',
Mo='Moji:BAABLgAFFH8GAAMLAAYJsRlaIABeAQZoDAAAAQBVAGkMAAABAE4AawwAAAEAXwBqDAAAAQBfAGwMAAABADYAbQwAAAEADwALAAQJxhdaIABeAQRpDAAAAQBOAGsMAAABAF8AbAwAAAEANgBtDAAAAQAPABoAAgleIbcLAGAAAmgMAAABAFUAagwAAAEAXwAAAA==.Moomtir:BAAALgADCgEJAQAAAA==.Morelia:BAAALgADCgcJFAAAAA==.Morph:BAAALgADCgEJAQAAAA==.Morrist:BAAALgAECgMJAwAAAA==.',
Ms='Mskeisha:BAAALgAECgMJAwAAAA==.',
Mu='Mugsfaru:BAACLgAFFH8FAAIIAAIJhCDCcwC2AAJoDAAAAgBGAOoMAAADAF8ACAACCYQgwnMAtgACaAwAAAIARgDqDAAAAwBfAC4ABAp/HgADCAAHCUoiSSgAPgIACAAHCUoiSSgAPgIAGwADCccOKmwAjgAAAAA=.',
Na='Nabecovid:BAACLgAFFH8UAAIcAAQJCBcjCQAaAQRoDAAACABRAGkMAAAEAE4AawwAAAIACgDqDAAABgBBABwABAkIFyMJABoBBGgMAAAIAFEAaQwAAAQATgBrDAAAAgAKAOoMAAAGAEEALgAECn86AAMcAAkJGh6IBQCYAgAcAAkJGh6IBQCYAgAHAAEJCBD2fwAiAAAAAA==.Nasha:BAACLgAFFH8ZAAIOAAUJNBh1PQAwAQVoDAAABgBAAGkMAAAGAEAAawwAAAQARgBqDAAAAwA+AOoMAAAGADAADgAFCTQYdT0AMAEFaAwAAAYAQABpDAAABgBAAGsMAAAEAEYAagwAAAMAPgDqDAAABgAwAC4ABAp/LwACDgAJCfMfdh8AiwIADgAJCfMfdh8AiwIAAAA=.Natek:BAACLgAFFH8HAAMdAAMJaxaqDQDkAANoDAAAAgBFAGkMAAACACUA6gwAAAMAQAAdAAMJKRaqDQDkAANoDAAAAQBFAGkMAAABACMA6gwAAAEAQAAPAAMJuhHfNQC2AANoDAAAAQApAGkMAAABACUA6gwAAAIAOAAuAAQKfyEABA8ACQl4IHkWADICAA8ACAlvIHkWADICABcAAwngFp2SALIAAB0AAgn5HBMpAK8AAAAA.',
Ni='Nightprowlr:BAAALgAFFAIJAwABLgAFFAMJAwAJAAAAAA==.',
Oo='Oogglytotems:BAAALgADCgQJBAAAAA==.Ooggmonk:BAAALgADCgUJBQAAAA==.',
Or='Orb:BAAALgADCgEJAQAAAA==.Orcangel:BAAALgAECgEJAQAAAA==.',
Ow='Owlbundy:BAAALgAECgcJBAAAAA==.',
Oz='Ozzën:BAAALgAECgEJBAABLgAFFAcJEwATAEgMAA==.',
Pa='Pablofanques:BAAALgAECgQJBQAAAA==.Pantojak:BAACLgAFFH8WAAIBAAYJNRtBEQCbAQZoDAAABgBRAGkMAAAGAFgAawwAAAMAMABqDAAAAgA1AGwMAAABADcA6gwAAAQASQABAAYJNRtBEQCbAQZoDAAABgBRAGkMAAAGAFgAawwAAAMAMABqDAAAAgA1AGwMAAABADcA6gwAAAQASQAuAAQKfxoAAgEACAkpIrQlAIABAAEACAkpIrQlAIABAAAA.Parksnar:BAAALgAECgcJEwAAAA==.',
Pe='Peekabull:BAAALgAECgMJBgAAAA==.Pepe:BAAALgAECgUJCgAAAA==.',
Ph='Phouchg:BAACLgAFFH8RAAMQAAQJOyXGBgChAQRoDAAABgBcAGkMAAAFAF4AawwAAAIAYwDqDAAABABeABAABAk7JcYGAKEBBGgMAAAFAFwAaQwAAAUAXgBrDAAAAgBjAOoMAAAEAF4ACAABCb0fk6cARgABaAwAAAEAUQAuAAQKfy4ABBAACQm5IQkEAPECABAACQm5IQkEAPECAAgACAnuDwB4AFABABsABwlJFsYQAE4BAAAA.',
Pi='Pirotessa:BAABLgAECn8lAAIMAAkJuB2RNAChAgloDAAABQBWAGkMAAAHAFEAawwAAAcAWQBqDAAABQBWAGwMAAADAFAAbQwAAAEARADqDAAABgBfAG4MAAACAB0AbwwAAAEATQAMAAkJuB2RNAChAgloDAAABQBWAGkMAAAHAFEAawwAAAcAWQBqDAAABQBWAGwMAAADAFAAbQwAAAEARADqDAAABgBfAG4MAAACAB0AbwwAAAEATQAAAA==.',
Pl='Plumpuddin:BAAALgAECgYJDQAAAA==.',
Qk='Qkz:BAAALgAECgYJBwABLgAFFAQJFwAWABojAA==.',
Ra='Ranore:BAAALgADCggJJQABLgAECgkJPwADAL4eAA==.Rathimus:BAAALgAECgIJAgAAAA==.Rayven:BAAALgAECgEJAQAAAA==.',
Re='Reimdh:BAAALgAECgEJAQABLgAFFAcJIgACADwTAA==.Reptar:BAABLgAFFH8SAAIHAAYJOyWXAgAYAgZoDAAABQBiAGkMAAADAGAAawwAAAMAYQBqDAAAAQBWAOoMAAAFAGIAbgwAAAEAVgAHAAYJOyWXAgAYAgZoDAAABQBiAGkMAAADAGAAawwAAAMAYQBqDAAAAQBWAOoMAAAFAGIAbgwAAAEAVgABLgAFFAcJHQABAH4UAA==.',
Ri='Rianor:BAAALgAECgEJAQAAAA==.Richardtwist:BAAALgAECgEJAwAAAA==.',
Ro='Roaar:BAABLgAFFH8MAAMQAAQJag1+BgC+AARoDAAABABAAGkMAAADABAAawwAAAEACADqDAAABAAwAAgABAlqDdNUAP4ABGgMAAACAEAAaQwAAAEAEABrDAAAAQAIAOoMAAADADAAEAADCXsFfgYAvgADaAwAAAIAFQBpDAAAAgAEAOoMAAABAA8AAAA=.Robinhoof:BAAALgADCgYJBwAAAA==.Rocko:BAAALgAECgcJEwAAAA==.Rourke:BAABLgAFFH8FAAIIAAMJIhRhWwDuAANoDAAAAgBQAGkMAAABADgA6gwAAAIAEgAIAAMJIhRhWwDuAANoDAAAAgBQAGkMAAABADgA6gwAAAIAEgAAAA==.Roxbox:BAAALgAFFAMJAwAAAA==.',
Ry='Ryukyu:BAACLgAFFH8JAAMaAAMJGBWZDQBIAANoDAAABAA7AGkMAAADADYA6gwAAAIAMAALAAIJFhabUQCEAAJoDAAABAA7AGkMAAADADYAGgABCRwTmQ0ASAAB6gwAAAIAMAAuAAQKfy8AAwsACQkiGw4SAFICAAsACQmyGg4SAFICABoABgkJFVElAPoAAAAA.',
Sa='Savz:BAAALgADCgQJBAABLgAECgYJBgAJAAAAAA==.',
Sc='Schro:BAAALgAECgYJBwAAAA==.Schrolock:BAABLgAECn8VAAMUAAgJ7w/mbQCFAQhoDAAAAwAnAGkMAAADAC0AawwAAAMAQgBqDAAABAAgAGwMAAAEADQA6gwAAAIAHwBuDAAAAQAVAG8MAAABAB0AFAAICe8P5m0AhQEIaAwAAAMAJwBpDAAAAwAtAGsMAAADAEIAagwAAAEAIABsDAAABAA0AOoMAAACAB8AbgwAAAEAFQBvDAAAAQAdABkAAQkAACZzADIAAWoMAAADABkAAAA=.',
Sh='Shortbread:BAAALgADCgkJAwAAAA==.',
Sp='Sprung:BAAALgAECgQJCwAAAA==.Spyla:BAAALgAECgQJDQAAAA==.',
St='Steven:BAAALgAECgMJBQABLgAFFAMJCQAaABgVAA==.',
Su='Supermouse:BAABLgAECn8mAAIVAAgJ/By5CAAAAghoDAAABgBPAGkMAAAFAEYAawwAAAYAUwBqDAAABgBWAGwMAAAGAEQAbQwAAAIASQDqDAAABgBPAG4MAAABAEEAFQAICfwcuQgAAAIIaAwAAAYATwBpDAAABQBGAGsMAAAGAFMAagwAAAYAVgBsDAAABgBEAG0MAAACAEkA6gwAAAYATwBuDAAAAQBBAAAA.',
Ta='Tabtarget:BAAALgAECgEJAwABLgAFFAQJFwAWABojAA==.Talmage:BAAALgADCgIJAgAAAA==.',
To='Tophat:BAACLgAFFH8IAAIMAAgJdgDDmwCTAAhoDAAAAQADAGkMAAABAAAAawwAAAEAAABqDAAAAQAGAGwMAAABAAIAbQwAAAEAAADqDAAAAQAAAG4MAAABAAAADAAICXYAw5sAkwAIaAwAAAEAAwBpDAAAAQAAAGsMAAABAAAAagwAAAEABgBsDAAAAQACAG0MAAABAAAA6gwAAAEAAABuDAAAAQAAAC4ABAp/GQACDAAICWoHWKgALgEADAAICWoHWKgALgEAAAA=.',
Tw='Twoinchfury:BAACLgAFFH8VAAIeAAUJFxQNFwDkAAVoDAAABgAvAGkMAAAGAEYAawwAAAIAGQBqDAAAAQA5AOoMAAAGAD0AHgAFCRcUDRcA5AAFaAwAAAYALwBpDAAABgBGAGsMAAACABkAagwAAAEAOQDqDAAABgA9AC4ABAp/MgACHgAJCfAXrw0AEAIAHgAJCfAXrw0AEAIAAAA=.',
Va='Vaihlor:BAAALgAECgEJAQAAAA==.',
Ve='Velaris:BAAALgADCgEJAQABLgAECgkJJAARAL8cAA==.Veledin:BAABLgAECn8UAAMCAAgJ/hUCQADJAQhoDAAAAgAsAGkMAAADADYAawwAAAMARQBqDAAABgBXAGwMAAABACIAbQwAAAEANQDqDAAAAwA9AG8MAAABAEsAAgAICf4VAkAAyQEIaAwAAAIALABpDAAAAwA2AGsMAAADAEUAagwAAAUAVwBsDAAAAQAiAG0MAAABADUA6gwAAAMAPQBvDAAAAQBLAAQAAQkAALBCAAAAAWoMAAABACkAAS4ABRQCCQYAEAAoEAA=.Vergil:BAACLgAFFH8NAAIDAAQJDRFwEQAYAQRoDAAABQBGAGkMAAAEAC4AawwAAAIAEwDqDAAAAgAlAAMABAkNEXARABgBBGgMAAAFAEYAaQwAAAQALgBrDAAAAgATAOoMAAACACUALgAECn8lAAMDAAkJAxsIDABmAgADAAkJ0xoIDABmAgACAAMJbgMTBwFDAAAAAA==.Veroq:BAAALgADCgcJCAAAAA==.',
Wa='Wachabe:BAABLgAECn8pAAIHAAkJzRYsDgAAAgloDAAABgA8AGkMAAAFAB4AawwAAAQAKQBqDAAABAAeAGwMAAAFADgAbQwAAAIAOwDqDAAABwBRAG4MAAAFAE0AbwwAAAMAOwAHAAkJzRYsDgAAAgloDAAABgA8AGkMAAAFAB4AawwAAAQAKQBqDAAABAAeAGwMAAAFADgAbQwAAAIAOwDqDAAABwBRAG4MAAAFAE0AbwwAAAMAOwAAAA==.',
We='Weiden:BAACLgAFFH8UAAIGAAQJWw0qKADyAARoDAAACAAyAGkMAAAGACsAawwAAAIAEADqDAAABAAYAAYABAlbDSooAPIABGgMAAAIADIAaQwAAAYAKwBrDAAAAgAQAOoMAAAEABgALgAECn85AAIGAAkJ1RhUFwASAgAGAAkJ1RhUFwASAgAAAA==.',
Yo='Yourpal:BAAALgAECgQJBAAAAA==.',
Yr='Yrene:BAAALgAECgQJAwAAAA==.',
Yu='Yulwei:BAAALgAECggJEAAAAA==.',
['Yô']='Yôu:BAAALgAECgIJBQAAAA==.',
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
