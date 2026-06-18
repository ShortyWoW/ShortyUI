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

local lookup = {'Warlock-Affliction','DemonHunter-Devourer','DemonHunter-Havoc','Unknown-Unknown','DeathKnight-Blood','Rogue-Assassination','Warrior-Protection','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','DemonHunter-Vengeance','Paladin-Holy','Warlock-Demonology','Paladin-Retribution','Druid-Restoration','Priest-Discipline','Evoker-Augmentation','Hunter-Survival','Paladin-Protection','Rogue-Subtlety','Mage-Frost','Mage-Arcane','Warlock-Destruction','Priest-Shadow','Druid-Balance','Rogue-Outlaw','Hunter-BeastMastery','Hunter-Marksmanship','Priest-Holy',}
local provider = {region='US',realm='EmeraldDream',name='US',type='subscribers',zone=46,date='2026-06-17',data={Al='Alleryia:BAEALgAECgcJEgABLgAFFAUJFQABAHIZAA==.',
Bl='Blacephalon:BAEBLgAECn8RAAMCAAgJAx2VMAA5AghoDAAAAwBGAGkMAAACAFgAawwAAAMAVwBqDAAAAQAlAGwMAAACAEQAbQwAAAIAOgDqDAAAAwBXAG4MAAABADwAAgAICQMdlTAAOQIIaAwAAAMARgBpDAAAAgBYAGsMAAABAFcAagwAAAEAJQBsDAAAAgBEAG0MAAACADoA6gwAAAMAVwBuDAAAAQA8AAMAAQmNB4J3AC0AAWsMAAACABMAAS4ABAoJCRAABAAAAAA=.',
Bu='Bungulator:BAEALgADCgkJCQABLgAFFAQJEQAFAH8TAA==.',
Ca='Calsbigdk:BAEALgAECgEJAQABLgAFFAgJJQAGABUdAA==.',
Ch='Chûd:BAEALgAECgUJBQAAAA==.',
Cj='Cjk:BAECLgAFFH8SAAIHAAQJ3RisBQASAQRoDAAABABAAGkMAAAFAD0AawwAAAQAPgDqDAAABQBCAAcABAndGKwFABIBBGgMAAAEAEAAaQwAAAUAPQBrDAAABAA+AOoMAAAFAEIALgAECn8xAAIHAAgJgCT4BQCxAgAHAAgJgCT4BQCxAgAAAA==.',
Co='Colombian:BAECLgAFFH8XAAIIAAQJUSBlCwBsAQRoDAAACABbAGkMAAAHAFsAawwAAAMAVADqDAAABQA+AAgABAlRIGULAGwBBGgMAAAIAFsAaQwAAAcAWwBrDAAAAwBUAOoMAAAFAD4ALgAECn8gAAMIAAgJdxpoGgDdAQAIAAgJdxpoGgDdAQAJAAEJ3xqEggBFAAAAAA==.',
Da='Daddio:BAEALgAECgQJCwABLgADCgcJBwAEAAAAAA==.Damio:BAEALgAFFAQJBAABLgAFFAgJHwAKAD0XAA==.',
De='Dechu:BAECLgAFFH8fAAMLAAYJuiC4AgB9AQZoDAAACQBfAGkMAAAIAFoAawwAAAUAYQBqDAAAAwBGAGwMAAABADUA6gwAAAUAUQACAAYJOB1nIwCjAQZoDAAACABfAGkMAAAHAFEAawwAAAQAQgBqDAAAAgAZAGwMAAABADUA6gwAAAQASwALAAUJziG4AgB9AQVoDAAAAQBMAGkMAAABAFoAawwAAAEAYQBqDAAAAQBGAOoMAAABAFEALgAECn8+AAMLAAkJUSWbAABQAwALAAkJUSWbAABQAwACAAgJRx5aJwAuAgABLgAFFAgJJQAGABUdAA==.Deddio:BAEALgADCgcJBwAAAA==.',
Dr='Drampa:BAEALgADCgUJCgABLgAECgkJEAAEAAAAAA==.',
El='Elysius:BAEALgAECgQJCQAAAA==.',
En='Energizer:BAEALgAECgIJAgABLgAFFAQJDAAMABsgAA==.',
Et='Etheryia:BAECLgAFFH8VAAMBAAUJchn/BwD6AAVoDAAABgBKAGkMAAAFAEwAawwAAAMAHwBqDAAAAgAdAOoMAAAFAE0ADQAFCdUVQk0ALAEFaAwAAAUASABpDAAAAwAqAGsMAAADAB8AagwAAAEAHQDqDAAABABNAAEABAm2G/8HAPoABGgMAAABAEoAaQwAAAIATABqDAAAAQAHAOoMAAABAD0ALgAECn8qAAINAAkJUiE1EgC6AgANAAkJUiE1EgC6AgAAAA==.',
Fa='Fartslinger:BAEALgADCgQJBAABLgAFFAcJIQAOAOYcAA==.',
Fe='Felenmonk:BAEBLgAFFH8QAAMKAAUJ/A+1JwAvAQVoDAAABABIAGkMAAAEAB0AawwAAAMALQBqDAAAAQARAOoMAAAEACcACgAFCfwPtScALwEFaAwAAAIASABpDAAAAgAdAGsMAAACAC0AagwAAAEAEQDqDAAABAAnAAkAAwkdAj1GAIYAA2gMAAACAAYAaQwAAAIACABrDAAAAQAAAAEuAAUUCQkxAA8A3B8A.',
Fl='Floydfu:BAEALgAECgEJAgABLgAECgcJDAAEAAAAAA==.',
Gu='Guzzlord:BAEALgAECgkJEAAAAA==.',
Il='Illililili:BAEALgAECgYJDwABLgAECgkJJQAQABkRAA==.',
Jo='Joedragon:BAEBLgAECn8UAAIRAAYJJgprWQDOAAZoDAAABAAcAGkMAAAEAC0AawwAAAUAGQBqDAAAAwASAGwMAAACABIA6gwAAAIACwARAAYJJgprWQDOAAZoDAAABAAcAGkMAAAEAC0AawwAAAUAGQBqDAAAAwASAGwMAAACABIA6gwAAAIACwABLgAECgkJSAASAJ4fAA==.',
Ka='Kabigon:BAEALgADCgcJCgABLgAECgkJEAAEAAAAAA==.',
Ki='Kifka:BAEBLgAECn8tAAMOAAgJGyPQFwC0AghoDAAACQBiAGkMAAAIAFYAawwAAAgAUgBqDAAABQBgAGwMAAAFAFgA6gwAAAcAXABuDAAAAgBhAG8MAAABAFIADgAICf4h0BcAtAIIaAwAAAEAVwBpDAAAAQBWAGsMAAABAEsAagwAAAIATwBsDAAAAgBYAOoMAAABAFoAbgwAAAEAYQBvDAAAAQBSABMABwmVH8sLAAkCB2gMAAAIAGIAaQwAAAcATgBrDAAABwBSAGoMAAADAGAAbAwAAAMAUQDqDAAABgBcAG4MAAABADQAAS4ABRQECRYAFADpHwA=.',
Li='Liothen:BAEALgAECgkJCAAAAA==.',
Ma='Maniacul:BAECLgAFFH8WAAIUAAQJ6R85FQBhAQRoDAAACABbAGkMAAAFAFYAawwAAAMAPwDqDAAABgBVABQABAnpHzkVAGEBBGgMAAAIAFsAaQwAAAUAVgBrDAAAAwA/AOoMAAAGAFUALgAECn92AAIUAAkJGiY8AQBqAwAUAAkJGiY8AQBqAwAAAA==.',
Mh='Mhyre:BAEALgAECgYJEQAAAA==.',
Mo='Monkio:BAECLgAFFH8fAAIKAAgJPReQBgClAghoDAAABQBgAGkMAAAGAGMAawwAAAYAYQBqDAAAAwAUAGwMAAACAC4AbQwAAAEAJQDqDAAABwA4AG8MAAABABYACgAICT0XkAYApQIIaAwAAAUAYABpDAAABgBjAGsMAAAGAGEAagwAAAMAFABsDAAAAgAuAG0MAAABACUA6gwAAAcAOABvDAAAAQAWAC4ABAp/JQADCgAJCf0fHQcALgMACgAJCf0fHQcALgMACAACCVAdFGUAjQAAAAA=.',
Od='Odbabymage:BAECLgAFFH85AAIVAAkJrSW5AABhAwloDAAACQBjAGkMAAAFAGEAawwAAAkAYwBqDAAACQBjAGwMAAAGAGQAbQwAAAUAYwDqDAAACQBhAG4MAAADAGAAbwwAAAIAUAAVAAkJrSW5AABhAwloDAAACQBjAGkMAAAFAGEAawwAAAkAYwBqDAAACQBjAGwMAAAGAGQAbQwAAAUAYwDqDAAACQBhAG4MAAADAGAAbwwAAAIAUAAuAAQKfyIAAxUACQnUJgQEAMADABUACQnUJgQEAMADABYAAQlRJCAaAEcAAAAA.',
Og='Og:BAEBLgAECn82AAQNAAkJQR11GwB/AgloDAAACgBhAGkMAAAJAE4AawwAAAkAWQBqDAAABgBeAGwMAAAFAEwAbQwAAAMANADqDAAACQBcAG4MAAACAE4AbwwAAAEAIgANAAkJvht1GwB/AgloDAAACABYAGkMAAAGAEYAawwAAAcAVwBqDAAABABYAGwMAAAEAEEAbQwAAAMANADqDAAABwBcAG4MAAACAE4AbwwAAAEAIgABAAYJoSGtBwDzAQZoDAAAAgBhAGkMAAADAE4AawwAAAIAWQBqDAAAAQBeAGwMAAABAEwA6gwAAAIAWAAXAAEJAACZVAAAAAFqDAAAAQAmAAAA.',
Oh='Ohb:BAEBLgAECn8lAAMQAAkJGRENFAAMAgloDAAABAAWAGkMAAAEACUAawwAAAQAPgBqDAAABAA7AGwMAAAEADwAbQwAAAYAJgDqDAAABAApAG4MAAAFAB0AbwwAAAIAKQAQAAkJGRENFAAMAgloDAAAAgAWAGkMAAACACUAawwAAAIAPgBqDAAAAgA7AGwMAAADADwAbQwAAAUAJgDqDAAAAgApAG4MAAAFAB0AbwwAAAIAKQAYAAcJ0QrgUADNAAdoDAAAAgAjAGkMAAACAD0AawwAAAIALABqDAAAAgAcAGwMAAABAAIAbQwAAAEAAwDqDAAAAgASAAAA.',
Pa='Pandodruid:BAECLgAFFH8jAAMPAAkJgSGRAACbAwloDAAABABjAGkMAAAEAGEAawwAAAMAYQBqDAAABABbAGwMAAADAFYAbQwAAAQAPwDqDAAABwBjAG4MAAAEAE4AbwwAAAIAOgAPAAkJgSGRAACbAwloDAAABABjAGkMAAAEAGEAawwAAAIAYQBqDAAABABbAGwMAAADAFYAbQwAAAQAPwDqDAAABgBjAG4MAAAEAE4AbwwAAAIAOgAZAAIJBRNSOgCPAAJrDAAAAQAMAOoMAAABAFQALgAECn8VAAMPAAgJ8SFyDwC9AgAPAAgJ8SFyDwC9AgAZAAEJNCXVbwBoAAAAAA==.',
Ph='Pharyngitis:BAECLgAFFH8eAAIFAAYJ3RFvGAAjAQZoDAAACQBKAGkMAAAIAEkAawwAAAUAJwBqDAAAAwAcAGwMAAABAA0A6gwAAAQAGwAFAAYJ3RFvGAAjAQZoDAAACQBKAGkMAAAIAEkAawwAAAUAJwBqDAAAAwAcAGwMAAABAA0A6gwAAAQAGwAuAAQKfx8AAgUABwnqGEsRAPYBAAUABwnqGEsRAPYBAAAA.',
Ra='Rayocchi:BAECLgAFFH8KAAIKAAUJ5x2xGgCeAQVoDAAAAgBTAGkMAAACAFcAawwAAAIAWABqDAAAAgA7AOoMAAACAD8ACgAFCecdsRoAngEFaAwAAAIAUwBpDAAAAgBXAGsMAAACAFgAagwAAAIAOwDqDAAAAgA/AC4ABAp/FQADCgAHCQMe2U4AMgEACgAGCXQd2U4AMgEACAAECZsa0EoA1gAAAS4ABRQECQwADAAbIAA=.Rayocell:BAECLgAFFH8MAAIMAAQJGyBsGQBWAQRoDAAABABYAGkMAAAEAF4AawwAAAEAOQDqDAAAAwBYAAwABAkbIGwZAFYBBGgMAAAEAFgAaQwAAAQAXgBrDAAAAQA5AOoMAAADAFgALgAECn8mAAMMAAkJryR2BQAUAwAMAAkJryR2BQAUAwAOAAUJ/xknewCEAQAAAA==.Rayogizer:BAEALgAFFAMJBAABLgAFFAQJDAAMABsgAA==.',
Re='Rejuvenate:BAECLgAFFH8ZAAIPAAYJQhfrFAC/AQZoDAAACABSAGkMAAAHAEkAawwAAAIAOwBqDAAAAgAYAGwMAAABADcA6gwAAAUAPQAPAAYJQhfrFAC/AQZoDAAACABSAGkMAAAHAEkAawwAAAIAOwBqDAAAAgAYAGwMAAABADcA6gwAAAUAPQAuAAQKfyEAAw8ACAm/IS8TAJwCAA8ACAm/IS8TAJwCABkAAQl5DE6OADEAAAAA.',
Ro='Ronakada:BAEALgAECgQJCAABLgAECgQJCQAEAAAAAA==.',
Ru='Ruyari:BAEALgADCgUJBQAAAA==.',
Sa='Sahurian:BAEALgAECgcJDAAAAA==.',
Se='Seppä:BAECLgAFFH8IAAIKAAMJyQVkSwB3AANoDAAAAwATAGkMAAABAAUA6gwAAAQAEwAKAAMJyQVkSwB3AANoDAAAAwATAGkMAAABAAUA6gwAAAQAEwAuAAQKfxkAAwoACAmoEbBCAGIBAAoACAmoEbBCAGIBAAgAAglXIHxTALwAAAAA.',
Sn='Snigmorder:BAECLgAFFH8lAAQGAAgJFR0/AgCXAQhoDAAACABXAGkMAAAHAFwAawwAAAYAWgBqDAAABQBjAGwMAAABAD8AbQwAAAEASgDqDAAACABVAG4MAAABABsAFAAFCecdIAsA5wEFaAwAAAcAVwBpDAAABQBcAGsMAAAEAFoA6gwAAAUAVQBuDAAAAQAbAAYABwnJHD8CAJcBB2gMAAABAEIAaQwAAAIAVgBrDAAAAQBNAGoMAAADAGMAbAwAAAEAPwBtDAAAAQBKAOoMAAADAEgAGgACCa0C3wEAWgACawwAAAEABgBqDAAAAgBSAC4ABAp/QgAEBgAJCQglmQIAqgIABgAICU8jmQIAqgIAFAAICYwl/QcApwIAGgAGCcYekgkAjwEAAAA=.',
Sp='Splashofray:BAEALgAECgEJAQABLgAFFAQJDAAMABsgAA==.',
To='Tofer:BAECLgAFFH8eAAMSAAYJeCB2BADOAQZoDAAACQBiAGkMAAAIAFwAawwAAAQATABqDAAAAQA7AGwMAAABAGEA6gwAAAcAMwASAAYJgR92BADOAQZoDAAACQBiAGkMAAAHAFwAawwAAAQATABqDAAAAQA7AGwMAAABAGEA6gwAAAUAJgAbAAIJDgyJKABRAAJpDAAAAQAKAOoMAAACADMALgAECn9FAAQSAAkJriUsAQBbAwASAAkJqiUsAQBbAwAbAAgJ2SAyFgCGAgAcAAEJMwmDjgAsAAAAAA==.Toffuu:BAEBLgAECn8VAAIKAAgJsCS+BQBLAwhoDAAAAwBhAGkMAAADAGMAawwAAAMAYgBqDAAAAwBfAGwMAAADAGMAbQwAAAEATADqDAAAAwBhAG4MAAACAFcACgAICbAkvgUASwMIaAwAAAMAYQBpDAAAAwBjAGsMAAADAGIAagwAAAMAXwBsDAAAAwBjAG0MAAABAEwA6gwAAAMAYQBuDAAAAgBXAAEuAAUUBgkeABIAeCAA.',
Vh='Vhader:BAECLgAFFH8RAAIFAAQJfxP0IQDaAARoDAAABwA0AGkMAAAFADwAawwAAAEAGwDqDAAABAA7AAUABAl/E/QhANoABGgMAAAHADQAaQwAAAUAPABrDAAAAQAbAOoMAAAEADsALgAECn8tAAIFAAkJcB6WBwCxAgAFAAkJcB6WBwCxAgAAAA==.',
['Wú']='Wú:BAEBLgAECn8lAAMIAAgJvxDOKgBnAQhoDAAABgAzAGkMAAAGADEAawwAAAUAIgBqDAAABQAnAGwMAAAGACsAbQwAAAIAGQDqDAAABgArAG8MAAABADQACAAICb8QzioAZwEIaAwAAAUAMwBpDAAABQAxAGsMAAAEACIAagwAAAQAJwBsDAAABQArAG0MAAACABkA6gwAAAUAKwBvDAAAAQA0AAkABgkMBIhZAKQABmgMAAABAAUAaQwAAAEABwBrDAAAAQAQAGoMAAABAAsAbAwAAAEAEgDqDAAAAQADAAAA.',
Xu='Xurkitree:BAEALgAECgEJAgABLgAECgkJEAAEAAAAAA==.',
Zo='Zogado:BAEALgAECgUJBgABLgAECgkJJwAdAAUhAA==.',
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
