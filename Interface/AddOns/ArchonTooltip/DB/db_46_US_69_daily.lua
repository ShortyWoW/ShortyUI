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

local lookup = {'Monk-Brewmaster','DemonHunter-Devourer','DemonHunter-Havoc','DemonHunter-Vengeance','Druid-Restoration','Druid-Balance','Druid-Guardian','Hunter-BeastMastery','Unknown-Unknown','Evoker-Preservation','Evoker-Augmentation','Mage-Frost','DeathKnight-Unholy','Paladin-Retribution','Shaman-Elemental','Paladin-Holy','Priest-Holy','Priest-Shadow','Rogue-Subtlety','Warlock-Demonology','DeathKnight-Frost','Shaman-Restoration','Hunter-Survival','DeathKnight-Blood','Warlock-Destruction','Evoker-Devastation','Hunter-Marksmanship','Druid-Feral','Shaman-Enhancement','Warrior-Protection',}
local provider = {region='US',realm='Detheroc',name='US',type='daily',zone=46,date='2026-06-17',data={Ab='Abominus:BAAALgADCgMJAwAAAA==.Abrak:BAAALgAECgcJDQAAAA==.',
Ae='Aelflaed:BAAALgAECgcJDwAAAA==.Aeolia:BAAALgAECgEJAQABLgAFFAYJFgABADUbAA==.Aerirea:BAAALgAECgcJCwAAAA==.Aethèr:BAAALgADCggJCQAAAA==.',
Al='Aladiirn:BAACLgAFFH8fAAICAAcJPBObIACzAQdoDAAABwBNAGkMAAAHAEQAawwAAAUAHABqDAAAAgAfAG0MAAABABAA6gwAAAgAUgBuDAAAAQAWAAIABwk8E5sgALMBB2gMAAAHAE0AaQwAAAcARABrDAAABQAcAGoMAAACAB8AbQwAAAEAEADqDAAACABSAG4MAAABABYALgAECn89AAQCAAgJbiTQGgBzAgACAAgJbiTQGgBzAgADAAEJPhsRZQBQAAAEAAMJ9gOOMABBAAAAAA==.Alphapacer:BAAALgADCgcJCQAAAA==.',
An='Anthria:BAAALgAECgIJAgABLgAFFAYJFgABADUbAA==.',
As='Asha:BAABLgAECn8YAAQFAAcJuRgpUABlAQdoDAAABABDAGkMAAAEADAAawwAAAQAPgBqDAAABABcAGwMAAAEAFcAbQwAAAEAAwDqDAAAAwBRAAUABgmXHClQAGUBBmgMAAADAEMAaQwAAAMAMABrDAAAAwA+AGoMAAACAFwAbAwAAAIAVwDqDAAAAgBRAAYABwlJEX45ACwBB2gMAAABAEYAaQwAAAEASQBrDAAAAQBHAGoMAAABAEMAbAwAAAEAKwBtDAAAAQABAOoMAAABAAQABwACCZUKzIAAIAACagwAAAEAGQBsDAAAAQAbAAAA.Ashaii:BAAALgADCgEJAQAAAA==.Ashleeann:BAABLgAECn8YAAIIAAkJkQ0JOgDGAQloDAAABAAWAGkMAAADAC0AawwAAAMAQgBqDAAAAwAcAGwMAAAEABYAbQwAAAEAFwDqDAAAAwAhAG4MAAACACoAbwwAAAEAEwAIAAkJkQ0JOgDGAQloDAAABAAWAGkMAAADAC0AawwAAAMAQgBqDAAAAwAcAGwMAAAEABYAbQwAAAEAFwDqDAAAAwAhAG4MAAACACoAbwwAAAEAEwAAAA==.',
At='Ather:BAAALgAECgcJDwAAAA==.',
Au='Aulton:BAAALgADCgIJAgAAAA==.Aurix:BAAALgADCgMJAwAAAA==.',
Aw='Awenyddion:BAAALgAECgUJCgABLgAECgcJDwAJAAAAAA==.',
Ba='Bayle:BAABLgAECn8ZAAMKAAkJdBCbKQAmAQloDAAABgAYAGkMAAAEAB0AawwAAAQAEgBqDAAAAwAbAGwMAAADAB0AbQwAAAEAVQDqDAAAAgAgAG4MAAABAD8AbwwAAAEARAAKAAYJlQqbKQAmAQZoDAAAAwAYAGkMAAADAB0AawwAAAMAEgBqDAAAAwAbAGwMAAADAB0A6gwAAAEAIAALAAcJgAoDWADSAAdoDAAAAwAsAGkMAAABAAwAawwAAAEAHwBtDAAAAQAhAOoMAAABAA4AbgwAAAEAHwBvDAAAAQATAAAA.',
Bb='Bbygrl:BAABLgAFFH8FAAIMAAIJ/wiHsgBvAAJpDAAAAQACAOoMAAAEACsADAACCf8Ih7IAbwACaQwAAAEAAgDqDAAABAArAAEuAAUUAwkHAA0Abg8A.',
Bo='Boabjr:BAAALgADCgUJBQAAAA==.Boldin:BAAALgAECgMJAwAAAA==.Booner:BAAALgAECgEJAwAAAA==.Botadin:BAABLgAECn8tAAIOAAgJSyGcHACZAghoDAAABwBgAGkMAAAHAGEAawwAAAcAVQBqDAAABQBCAGwMAAAFAEMAbQwAAAEATwDqDAAABwBbAG4MAAAGAE4ADgAICUshnBwAmQIIaAwAAAcAYABpDAAABwBhAGsMAAAHAFUAagwAAAUAQgBsDAAABQBDAG0MAAABAE8A6gwAAAcAWwBuDAAABgBOAAAA.',
Br='Brandrood:BAAALgAECgYJBgAAAA==.Bronst:BAAALgAECgIJAgABLgAECgkJMQAPAOYYAA==.',
Bu='Bubblemeinfy:BAAALgAECgEJAQAAAA==.',
['Bô']='Bôw:BAABLgAECn8fAAIIAAkJ0AqfQACtAQloDAAABQAYAGkMAAAFACAAawwAAAUANQBqDAAABAAmAGwMAAAEACAAbQwAAAIAGADqDAAAAwARAG4MAAACABEAbwwAAAEAEwAIAAkJ0AqfQACtAQloDAAABQAYAGkMAAAFACAAawwAAAUANQBqDAAABAAmAGwMAAAEACAAbQwAAAIAGADqDAAAAwARAG4MAAACABEAbwwAAAEAEwAAAA==.',
Ca='Calvin:BAAALgAECgEJAgABLgAFFAQJFwAQABojAA==.',
Ce='Cerinis:BAAALgAFFAIJBAAAAA==.',
Ch='Chairmanmao:BAAALgAECgMJAwAAAA==.Chaotic:BAAALgADCgkJDwAAAA==.',
Co='Corca:BAACLgAFFH8XAAIRAAQJHw6bHQDMAARoDAAACAAkAGkMAAAHACsAawwAAAIABADqDAAABgA8ABEABAkfDpsdAMwABGgMAAAIACQAaQwAAAcAKwBrDAAAAgAEAOoMAAAGADwALgAECn83AAMRAAkJwhIHKgB3AQARAAkJwhIHKgB3AQASAAYJ3gjXRwDCAAAAAA==.',
Da='Dallinar:BAAALgADCgIJAgAAAA==.Darklocke:BAAALgAECgUJCwAAAA==.Dazbraz:BAAALgADCgkJCQABLgAFFAYJEgATAJsNAA==.',
De='Death:BAAALgADCgYJBgABLgAFFAUJFAAUAOUfAA==.Deaçon:BAAALgAECgUJDQAAAA==.Derffenator:BAAALgADCgEJAQAAAA==.',
Di='Diazz:BAAALgAECgEJAgAAAA==.Dirty:BAAALgADCgMJAwABLgAECggJHgAPAOQTAA==.',
Do='Dooma:BAACLgAFFH8HAAMNAAMJbg98sQDBAANoDAAAAgAnAGkMAAABAAsA6gwAAAQAQwANAAMJoAt8sQDBAANoDAAAAQAJAGkMAAABAAsA6gwAAAMAQwAVAAIJlw4RIACGAAJoDAAAAQAnAOoMAAABACMALgAECn8jAAMNAAkJeh6sMgA0AgANAAkJeh6sMgA0AgAVAAUJDxiNFgAkAQAAAA==.',
Dp='Dps:BAAALgAECgUJCAAAAA==.',
Dr='Drakjob:BAAALgADCgkJCgABLgAFFAQJFwAQABojAA==.Drakko:BAAALgAECggJDwABLgAFFAIJBAAJAAAAAA==.Drax:BAAALgAECgkJDAAAAA==.Droplock:BAAALgAECgEJAgAAAA==.',
Du='Dunspore:BAABLgAECn8gAAIWAAkJrSA9BwAAAwloDAAABQBhAGkMAAAFAF0AawwAAAUAXQBqDAAABABNAGwMAAAEAFsAbQwAAAIAUQDqDAAABABeAG4MAAACAEMAbwwAAAEANgAWAAkJrSA9BwAAAwloDAAABQBhAGkMAAAFAF0AawwAAAUAXQBqDAAABABNAGwMAAAEAFsAbQwAAAIAUQDqDAAABABeAG4MAAACAEMAbwwAAAEANgAAAA==.',
Ea='Earendel:BAAALgADCgkJCQAAAA==.',
Er='Ermahn:BAAALgAECgYJEwAAAA==.',
Fi='Finalgoddk:BAAALgADCgkJCgABLgAFFAQJDQAOANMiAA==.Finalgodfury:BAACLgAFFH8NAAIOAAQJ0yJOKABpAQRoDAAABQBhAGkMAAAEAGAAawwAAAEAQwDqDAAAAwBfAA4ABAnTIk4oAGkBBGgMAAAFAGEAaQwAAAQAYABrDAAAAQBDAOoMAAADAF8ALgAECn8oAAIOAAgJAiYlCQBJAwAOAAgJAiYlCQBJAwAAAA==.Fingbang:BAAALgADCgYJBgABLgAFFAMJAwAJAAAAAA==.',
Fo='Fooshg:BAAALgAECgEJAQABLgAFFAQJEQAXADslAA==.Foxinhood:BAAALgAFFAMJAwAAAA==.Foxydots:BAAALgAECgYJCAAAAA==.',
Fr='Frigidfire:BAAALgAECgEJAgAAAA==.Frostscythe:BAAALgAECgMJAwAAAA==.',
Fu='Furmidable:BAAALgADCggJCQAAAA==.',
Gi='Girrzz:BAAALgAECgYJDwAAAA==.Girthspell:BAAALgAECgEJAQAAAA==.Girthtrude:BAAALgAECgEJAQAAAA==.',
Gr='Grand:BAACLgAFFH8XAAIQAAQJGiNlFgB0AQRoDAAACABcAGkMAAAHAFUAawwAAAIAUwDqDAAABgBhABAABAkaI2UWAHQBBGgMAAAIAFwAaQwAAAcAVQBrDAAAAgBTAOoMAAAGAGEALgAECn87AAIQAAkJfSLABwAQAwAQAAkJfSLABwAQAwAAAA==.Grock:BAABLgAECn8xAAMWAAkJexn8EwCsAgloDAAABwBNAGkMAAAHAEkAawwAAAcAWABqDAAABgA/AGwMAAAFACwAbQwAAAMAHADqDAAACABQAG4MAAAEAFUAbwwAAAIALAAWAAkJexn8EwCsAgloDAAABgBNAGkMAAAGAEkAawwAAAYAWABqDAAABQA/AGwMAAAEACwAbQwAAAMAHADqDAAABwBQAG4MAAADAFUAbwwAAAIALAAPAAcJtgT8YADCAAdoDAAAAQASAGkMAAABAA8AawwAAAEACwBqDAAAAQAIAGwMAAABAAMA6gwAAAEACQBuDAAAAQANAAAA.Grundlegut:BAAALgAECgEJAQAAAA==.Grundletap:BAAALgADCgEJAgAAAA==.',
Gx='Gxxse:BAACLgAFFH8SAAITAAYJmw2WEgB4AQZoDAAABgA8AGkMAAAGADYAawwAAAIACwBqDAAAAQAZAGwMAAABAAgA6gwAAAIAJwATAAYJmw2WEgB4AQZoDAAABgA8AGkMAAAGADYAawwAAAIACwBqDAAAAQAZAGwMAAABAAgA6gwAAAIAJwAuAAQKfyEAAhMACQkKG0YYAEUCABMACQkKG0YYAEUCAAAA.',
He='Hewman:BAAALgAECgQJCwAAAA==.Hezzding:BAAALgADCgIJAgAAAA==.',
Ho='Hogar:BAABLgAFFH8IAAIYAAQJGw+ZKwCdAARoDAAAAgAnAGkMAAACACYAagwAAAIAJgDqDAAAAgAmABgABAkbD5krAJ0ABGgMAAACACcAaQwAAAIAJgBqDAAAAgAmAOoMAAACACYAAS4ABRQGCRYAAQA1GwA=.',
Hu='Hugehippo:BAAALgAECgQJBAAAAA==.Hunanchicken:BAAALgAECgEJAQAAAA==.',
Ic='Icebox:BAAALgAECgYJBgAAAA==.Icejesterr:BAAALgAECgUJDAAAAA==.',
Ig='Ignorepain:BAAALgAECgYJDQAAAA==.',
Il='Illigiggle:BAAALgADCgYJCQAAAA==.Illioogg:BAAALgADCgMJAwAAAA==.',
Im='Imptastic:BAAALgAECgYJCAAAAA==.',
In='Industdoom:BAAALgAECgEJAQAAAA==.',
Ir='Ironstock:BAAALgADCgEJAQAAAA==.',
Je='Jesterpal:BAAALgAECgYJDgAAAA==.',
Jo='Joj:BAAALgAECgYJBwAAAA==.Jollyolly:BAABLgAECn8rAAMZAAkJmRnBEQAsAQloDAAABgBZAGkMAAAHAEsAawwAAAgARgBqDAAABQBDAGwMAAAEADEAbQwAAAIAJwDqDAAACABeAG4MAAACACMAbwwAAAEARQAUAAgJ6RRXXACJAQhoDAAAAgAyAGkMAAAEAEsAawwAAAMAOgBsDAAAAgAxAG0MAAABACcA6gwAAAUAPwBuDAAAAQAVAG8MAAABAEUAGQAICQIXwREALAEIaAwAAAQAWQBpDAAAAwA2AGsMAAAFAEYAagwAAAUAQwBsDAAAAgAnAG0MAAABAB0A6gwAAAMAXgBuDAAAAQAjAAAA.',
Ju='Juvens:BAAALgAECgEJAQAAAA==.Jux:BAAALgADCgMJAwAAAA==.',
Ka='Kalleo:BAAALgADCgIJAgAAAA==.Karma:BAAALgADCgQJBAAAAA==.',
Ko='Korath:BAAALgAECgYJBgABLgAFFAYJFgABADUbAA==.',
Kr='Krimzin:BAAALgAFFAIJAgABLgAFFAUJGgAIADAhAA==.',
Ky='Kynrina:BAAALgADCgEJAQAAAA==.',
La='Ladrill:BAAALgADCgcJBwAAAA==.Lainarning:BAAALgAECgMJBQAAAA==.',
Le='Lewiz:BAAALgAFFAIJBAAAAA==.',
Li='Lightsnack:BAAALgAECgEJAgAAAA==.',
Lu='Lucetia:BAAALgAECgEJAwAAAA==.',
Ma='Machooze:BAAALgAFFAEJAQAAAA==.Magifrey:BAAALgAECgEJAgAAAA==.Makyae:BAAALgAECgUJBwAAAA==.Masha:BAAALgADCgYJBgAAAA==.Mazikene:BAAALgAECgEJAQAAAA==.',
Mi='Minniemee:BAAALgAECgQJAQAAAA==.Mirabeaux:BAAALgAECgYJCQAAAA==.',
Mo='Moji:BAABLgAFFH8GAAMLAAYJsRloIABcAQZoDAAAAQBVAGkMAAABAE4AawwAAAEAXwBqDAAAAQBfAGwMAAABADYAbQwAAAEADwALAAQJxhdoIABcAQRpDAAAAQBOAGsMAAABAF8AbAwAAAEANgBtDAAAAQAPABoAAgleIa4LAGAAAmgMAAABAFUAagwAAAEAXwAAAA==.Moomtir:BAAALgADCgEJAQAAAA==.Morelia:BAAALgADCgcJFAAAAA==.Morph:BAAALgADCgEJAQAAAA==.Morrist:BAAALgAECgMJAwAAAA==.',
Ms='Mskeisha:BAAALgAECgMJAwAAAA==.',
Mu='Mugsfaru:BAACLgAFFH8FAAIIAAIJhCBacwC2AAJoDAAAAgBGAOoMAAADAF8ACAACCYQgWnMAtgACaAwAAAIARgDqDAAAAwBfAC4ABAp/HgADCAAHCUoiRygAPgIACAAHCUoiRygAPgIAGwADCccOKmwAjgAAAAA=.',
Na='Nabecovid:BAACLgAFFH8UAAIcAAQJCBcbCQAaAQRoDAAACABRAGkMAAAEAE4AawwAAAIACgDqDAAABgBBABwABAkIFxsJABoBBGgMAAAIAFEAaQwAAAQATgBrDAAAAgAKAOoMAAAGAEEALgAECn86AAMcAAkJGh6JBQCYAgAcAAkJGh6JBQCYAgAHAAEJCBDFfwAiAAAAAA==.Nasha:BAACLgAFFH8ZAAIOAAUJNBhOPQAwAQVoDAAABgBAAGkMAAAGAEAAawwAAAQARgBqDAAAAwA+AOoMAAAGADAADgAFCTQYTj0AMAEFaAwAAAYAQABpDAAABgBAAGsMAAAEAEYAagwAAAMAPgDqDAAABgAwAC4ABAp/LwACDgAJCfMfbB8AiwIADgAJCfMfbB8AiwIAAAA=.Natek:BAACLgAFFH8HAAMdAAMJaxabDQDkAANoDAAAAgBFAGkMAAACACUA6gwAAAMAQAAdAAMJKRabDQDkAANoDAAAAQBFAGkMAAABACMA6gwAAAEAQAAPAAMJuhHFNQC2AANoDAAAAQApAGkMAAABACUA6gwAAAIAOAAuAAQKfyEABA8ACQl4IHQWADICAA8ACAlvIHQWADICABYAAwngFnWSALIAAB0AAgn5HPsoAK8AAAAA.',
Ni='Nightprowlr:BAAALgAFFAIJAgABLgAFFAMJAwAJAAAAAA==.',
Oo='Oogglytotems:BAAALgADCgQJBAAAAA==.Ooggmonk:BAAALgADCgUJBQAAAA==.',
Or='Orb:BAAALgADCgEJAQAAAA==.Orcangel:BAAALgAECgEJAQAAAA==.',
Ow='Owlbundy:BAAALgAECgcJBAAAAA==.',
Oz='Ozzën:BAAALgAECgEJAgABLgAFFAYJEgATAJsNAA==.',
Pa='Pablofanques:BAAALgAECgQJBQAAAA==.Pantojak:BAACLgAFFH8WAAIBAAYJNRs3EQCbAQZoDAAABgBRAGkMAAAGAFgAawwAAAMAMABqDAAAAgA1AGwMAAABADcA6gwAAAQASQABAAYJNRs3EQCbAQZoDAAABgBRAGkMAAAGAFgAawwAAAMAMABqDAAAAgA1AGwMAAABADcA6gwAAAQASQAuAAQKfxoAAgEACAkpIqslAIABAAEACAkpIqslAIABAAAA.Parksnar:BAAALgAECgcJEwAAAA==.',
Pe='Peekabull:BAAALgAECgMJBgAAAA==.Pepe:BAAALgAECgUJCgAAAA==.',
Ph='Phouchg:BAACLgAFFH8RAAMXAAQJOyW6BgChAQRoDAAABgBcAGkMAAAFAF4AawwAAAIAYwDqDAAABABeABcABAk7JboGAKEBBGgMAAAFAFwAaQwAAAUAXgBrDAAAAgBjAOoMAAAEAF4ACAABCb0fBKcARgABaAwAAAEAUQAuAAQKfy4ABBcACQm5IQcEAPECABcACQm5IQcEAPECAAgACAnuD+R3AFABABsABwlJFsIQAE4BAAAA.',
Pi='Pirotessa:BAABLgAECn8lAAIMAAkJuB2RNAChAgloDAAABQBWAGkMAAAHAFEAawwAAAcAWQBqDAAABQBWAGwMAAADAFAAbQwAAAEARADqDAAABgBfAG4MAAACAB0AbwwAAAEATQAMAAkJuB2RNAChAgloDAAABQBWAGkMAAAHAFEAawwAAAcAWQBqDAAABQBWAGwMAAADAFAAbQwAAAEARADqDAAABgBfAG4MAAACAB0AbwwAAAEATQAAAA==.',
Pl='Plumpuddin:BAAALgAECgUJBQAAAA==.',
Qk='Qkz:BAAALgAECgYJBwABLgAFFAQJFwAQABojAA==.',
Ra='Ranore:BAAALgADCggJJQABLgAECgkJPwADAL4eAA==.Rathimus:BAAALgAECgIJAgAAAA==.Rayven:BAAALgAECgEJAQAAAA==.',
Re='Reimdh:BAAALgAECgEJAQABLgAFFAcJHwACADwTAA==.Reptar:BAABLgAFFH8MAAIHAAYJOyWUAgAYAgZoDAAAAwBiAGkMAAACAGAAawwAAAIAYQBqDAAAAQBWAOoMAAADAGIAbgwAAAEAVgAHAAYJOyWUAgAYAgZoDAAAAwBiAGkMAAACAGAAawwAAAIAYQBqDAAAAQBWAOoMAAADAGIAbgwAAAEAVgABLgAFFAcJHQABAH4UAA==.',
Ri='Rianor:BAAALgAECgEJAQAAAA==.Richardtwist:BAAALgAECgEJAwAAAA==.',
Ro='Roaar:BAABLgAFFH8GAAIIAAQJ0weDVAD+AARoDAAAAQAHAGkMAAABABAAawwAAAEACADqDAAAAwAwAAgABAnTB4NUAP4ABGgMAAABAAcAaQwAAAEAEABrDAAAAQAIAOoMAAADADAAAAA=.Robinhoof:BAAALgADCgYJBwAAAA==.Rocko:BAAALgAECgcJEwAAAA==.Rourke:BAABLgAFFH8FAAIIAAMJIhT/WgDuAANoDAAAAgBQAGkMAAABADgA6gwAAAIAEgAIAAMJIhT/WgDuAANoDAAAAgBQAGkMAAABADgA6gwAAAIAEgAAAA==.Roxbox:BAAALgAFFAMJAwAAAA==.',
Ry='Ryukyu:BAACLgAFFH8JAAMaAAMJGBWQDQBIAANoDAAABAA7AGkMAAADADYA6gwAAAIAMAALAAIJFhZyUQCEAAJoDAAABAA7AGkMAAADADYAGgABCRwTkA0ASAAB6gwAAAIAMAAuAAQKfy8AAwsACQkiGw4SAFICAAsACQmyGg4SAFICABoABgkJFVElAPoAAAAA.',
Sa='Savz:BAAALgADCgQJBAABLgAECgYJBgAJAAAAAA==.',
Sc='Schro:BAAALgAECgYJBwAAAA==.Schrolock:BAABLgAECn8VAAMUAAgJ7w/mbQCFAQhoDAAAAwAnAGkMAAADAC0AawwAAAMAQgBqDAAABAAgAGwMAAAEADQA6gwAAAIAHwBuDAAAAQAVAG8MAAABAB0AFAAICe8P5m0AhQEIaAwAAAMAJwBpDAAAAwAtAGsMAAADAEIAagwAAAEAIABsDAAABAA0AOoMAAACAB8AbgwAAAEAFQBvDAAAAQAdABkAAQkAACZzADIAAWoMAAADABkAAAA=.',
Sh='Shortbread:BAAALgADCgkJAwAAAA==.',
Sp='Sprung:BAAALgAECgQJCwAAAA==.Spyla:BAAALgAECgQJDQAAAA==.',
St='Steven:BAAALgAECgMJBQABLgAFFAMJCQAaABgVAA==.',
Su='Supermouse:BAABLgAECn8mAAIVAAgJ/By3CAAAAghoDAAABgBPAGkMAAAFAEYAawwAAAYAUwBqDAAABgBWAGwMAAAGAEQAbQwAAAIASQDqDAAABgBPAG4MAAABAEEAFQAICfwctwgAAAIIaAwAAAYATwBpDAAABQBGAGsMAAAGAFMAagwAAAYAVgBsDAAABgBEAG0MAAACAEkA6gwAAAYATwBuDAAAAQBBAAAA.',
To='Tophat:BAACLgAFFH8IAAIMAAgJdgCWmwCTAAhoDAAAAQADAGkMAAABAAAAawwAAAEAAABqDAAAAQAGAGwMAAABAAIAbQwAAAEAAADqDAAAAQAAAG4MAAABAAAADAAICXYAlpsAkwAIaAwAAAEAAwBpDAAAAQAAAGsMAAABAAAAagwAAAEABgBsDAAAAQACAG0MAAABAAAA6gwAAAEAAABuDAAAAQAAAC4ABAp/GQACDAAICWoHOKgALgEADAAICWoHOKgALgEAAAA=.',
Tw='Twoinchfury:BAACLgAFFH8TAAIeAAQJFxT9FgDkAARoDAAABgAvAGkMAAAGAEYAawwAAAIAGQDqDAAABQA9AB4ABAkXFP0WAOQABGgMAAAGAC8AaQwAAAYARgBrDAAAAgAZAOoMAAAFAD0ALgAECn8yAAIeAAkJ8BeuDQAQAgAeAAkJ8BeuDQAQAgAAAA==.',
Va='Vaihlor:BAAALgAECgEJAQAAAA==.',
Ve='Velaris:BAAALgADCgEJAQABLgAECgkJJAARAL8cAA==.Veledin:BAABLgAECn8UAAMCAAgJ/hX5PwDJAQhoDAAAAgAsAGkMAAADADYAawwAAAMARQBqDAAABgBXAGwMAAABACIAbQwAAAEANQDqDAAAAwA9AG8MAAABAEsAAgAICf4V+T8AyQEIaAwAAAIALABpDAAAAwA2AGsMAAADAEUAagwAAAUAVwBsDAAAAQAiAG0MAAABADUA6gwAAAMAPQBvDAAAAQBLAAQAAQkAAJlCAAAAAWoMAAABACkAAS4ABRQCCQQACQAAAAA=.Vergil:BAACLgAFFH8NAAIDAAQJDRFaEQAYAQRoDAAABQBGAGkMAAAEAC4AawwAAAIAEwDqDAAAAgAlAAMABAkNEVoRABgBBGgMAAAFAEYAaQwAAAQALgBrDAAAAgATAOoMAAACACUALgAECn8lAAMDAAkJAxsHDABmAgADAAkJ0xoHDABmAgACAAMJbgPIBgFDAAAAAA==.Veroq:BAAALgADCgcJCAAAAA==.',
Wa='Wachabe:BAABLgAECn8pAAIHAAkJzRYsDgAAAgloDAAABgA8AGkMAAAFAB4AawwAAAQAKQBqDAAABAAeAGwMAAAFADgAbQwAAAIAOwDqDAAABwBRAG4MAAAFAE0AbwwAAAMAOwAHAAkJzRYsDgAAAgloDAAABgA8AGkMAAAFAB4AawwAAAQAKQBqDAAABAAeAGwMAAAFADgAbQwAAAIAOwDqDAAABwBRAG4MAAAFAE0AbwwAAAMAOwAAAA==.',
We='Weiden:BAACLgAFFH8UAAIGAAQJWw0jKADyAARoDAAACAAyAGkMAAAGACsAawwAAAIAEADqDAAABAAYAAYABAlbDSMoAPIABGgMAAAIADIAaQwAAAYAKwBrDAAAAgAQAOoMAAAEABgALgAECn85AAIGAAkJ1RhTFwASAgAGAAkJ1RhTFwASAgAAAA==.',
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
