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

local lookup = {'Monk-Windwalker','Monk-Mistweaver','DemonHunter-Vengeance','Warrior-Fury','Paladin-Retribution','Hunter-Survival','Evoker-Preservation','Druid-Restoration','Priest-Shadow','Priest-Holy','Mage-Frost','Paladin-Holy','Warlock-Destruction','Evoker-Augmentation','Warlock-Demonology','Warlock-Affliction','DeathKnight-Blood','Warrior-Protection','Unknown-Unknown','Hunter-BeastMastery','DemonHunter-Devourer','DemonHunter-Havoc','Shaman-Restoration','Hunter-Marksmanship','Druid-Feral','Evoker-Devastation','Shaman-Elemental','Warrior-Arms','Paladin-Protection','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','Shaman-Enhancement','Mage-Arcane','Druid-Balance',}
local provider = {region='US',realm='SistersofElune',name='US',type='daily',zone=46,date='2026-05-10',data={Al='Althenara:BAAALgAECgEJAQAAAA==.',
Am='Amaurine:BAAALgADCgEJAQAAAA==.',
An='Anoramang:BAAALgADCgYJBgAAAA==.',
Aq='Aquarius:BAAALgAECgUJDgAAAA==.Aquessaria:BAAALgADCgEJAQAAAA==.Aquå:BAAALgAECgMJCgAAAA==.',
Ar='Aratfu:BAABLgAECn8iAAMBAAcJYhfxIgC/AQdoDAAACABVAGkMAAAGAEAAawwAAAQAMgBqDAAABQBHAGwMAAADADkA6gwAAAcAPABuDAAAAQAqAAEABwliF/EiAL8BB2gMAAAHAFUAaQwAAAYAQABrDAAAAwAyAGoMAAADAEcAbAwAAAEAOQDqDAAABQA8AG4MAAABACoAAgAFCTASNDIA2QAFaAwAAAEAFgBrDAAAAQARAGoMAAACADYAbAwAAAIAOgDqDAAAAgBPAAAA.Araycadia:BAAALgADCgYJCQAAAA==.Arcanita:BAAALgADCgcJCQAAAA==.Arcee:BAAALgAECgcJDQAAAA==.Archivus:BAAALgADCgEJAQAAAA==.Argelmach:BAAALgAECgEJAQAAAA==.Arui:BAAALgAECgYJEgAAAA==.',
At='Athania:BAABLgAECn8VAAIDAAYJRRiZCABiAQZoDAAABQBKAGkMAAAFAEIAawwAAAMAFQBqDAAAAgAxAGwMAAACAEMA6gwAAAQAUAADAAYJRRiZCABiAQZoDAAABQBKAGkMAAAFAEIAawwAAAMAFQBqDAAAAgAxAGwMAAACAEMA6gwAAAQAUAAAAA==.Athornia:BAAALgADCgQJBgAAAA==.',
Az='Azai:BAAALgADCgcJBwAAAA==.Azrannoth:BAABLgAECn8UAAIEAAgJYhfzEADyAQhoDAAABQA9AGkMAAAEADYAawwAAAQANQBqDAAAAgA+AGwMAAABACcAbQwAAAEASQDqDAAAAgA7AG4MAAABAE0ABAAICWIX8xAA8gEIaAwAAAUAPQBpDAAABAA2AGsMAAAEADUAagwAAAIAPgBsDAAAAQAnAG0MAAABAEkA6gwAAAIAOwBuDAAAAQBNAAAA.Azurite:BAAALgAECgYJEwAAAA==.',
Ba='Baelthos:BAAALgAECgYJEwAAAA==.Balthamøs:BAABLgAECn8pAAIFAAkJ6BBULQDSAQloDAAABgA6AGkMAAAGADIAawwAAAYAMQBqDAAABgAZAGwMAAAFADUAbQwAAAIAIQDqDAAABgAvAG4MAAADABEAbwwAAAEAJAAFAAkJ6BBULQDSAQloDAAABgA6AGkMAAAGADIAawwAAAYAMQBqDAAABgAZAGwMAAAFADUAbQwAAAIAIQDqDAAABgAvAG4MAAADABEAbwwAAAEAJAAAAA==.Baz:BAABLgAECn8WAAIGAAcJwR6vCABbAgdoDAAABABjAGkMAAAEAFoAawwAAAQAWQBqDAAAAwBjAGwMAAACADoAbQwAAAEAJgDqDAAABABgAAYABwnBHq8IAFsCB2gMAAAEAGMAaQwAAAQAWgBrDAAABABZAGoMAAADAGMAbAwAAAIAOgBtDAAAAQAmAOoMAAAEAGAAAAA=.',
Be='Beautiful:BAAALgAECgQJBQABLgAFFAQJCgAHAFcaAA==.Belathel:BAAALgAECgEJAQAAAA==.Bermon:BAABLgAECn8WAAIIAAgJhwq9NQBOAQhoDAAAAwAqAGkMAAADAC4AawwAAAMAIABqDAAAAwAVAGwMAAADACYAbQwAAAMADwDqDAAAAwAIAG4MAAABAAgACAAICYcKvTUATgEIaAwAAAMAKgBpDAAAAwAuAGsMAAADACAAagwAAAMAFQBsDAAAAwAmAG0MAAADAA8A6gwAAAMACABuDAAAAQAIAAAA.',
Bl='Bloodmojo:BAAALgADCgYJCAAAAA==.Bloodtotems:BAAALgAECgcJEQAAAA==.Bloomumz:BAAALgAECgUJDgAAAA==.Bluebyyou:BAABLgAECn8VAAMJAAYJ1AapLwDkAAZoDAAABAAUAGkMAAAEABIAawwAAAQAEwBqDAAAAwAQAGwMAAACAAcA6gwAAAQAFQAJAAYJ1AapLwDkAAZoDAAAAwAUAGkMAAADABIAawwAAAMAEwBqDAAAAQAQAGwMAAABAAcA6gwAAAMAFQAKAAYJBQY+MADYAAZoDAAAAQAEAGkMAAABABIAawwAAAEACABqDAAAAgAdAGwMAAABABEA6gwAAAEADQAAAA==.Blur:BAAALgAECgEJAQAAAA==.',
Bo='Borgor:BAAALgADCggJCAAAAA==.Bowlicious:BAAALgADCgYJCgAAAA==.',
Br='Bryman:BAAALgADCgQJBwAAAA==.Brystle:BAABLgAECn8dAAILAAYJ+gf0jAABAQZoDAAABQAfAGkMAAAFABsAawwAAAUADABqDAAABQANAGwMAAAFAA8A6gwAAAQADwALAAYJ+gf0jAABAQZoDAAABQAfAGkMAAAFABsAawwAAAUADABqDAAABQANAGwMAAAFAA8A6gwAAAQADwAAAA==.',
Ca='Caelion:BAABLgAECn8tAAIMAAkJjyIxAQB8AwloDAAACABjAGkMAAAJAGMAawwAAAcAYABqDAAABQBeAGwMAAAGAF8AbQwAAAEAWgDqDAAABwBiAG4MAAABAEAAbwwAAAEAOQAMAAkJjyIxAQB8AwloDAAACABjAGkMAAAJAGMAawwAAAcAYABqDAAABQBeAGwMAAAGAF8AbQwAAAEAWgDqDAAABwBiAG4MAAABAEAAbwwAAAEAOQAAAA==.Callaf:BAABLgAECn8bAAINAAgJzA/mBgCGAQhoDAAABQBJAGkMAAAFAEUAawwAAAUALwBqDAAABAAgAGwMAAACABMAbQwAAAEABwDqDAAABAAsAG4MAAABABQADQAICcwP5gYAhgEIaAwAAAUASQBpDAAABQBFAGsMAAAFAC8AagwAAAQAIABsDAAAAgATAG0MAAABAAcA6gwAAAQALABuDAAAAQAUAAAA.Cannex:BAAALgAECgYJEwAAAA==.',
Ce='Celas:BAAALgAECgQJBQAAAA==.Cemmos:BAAALgAECgEJAQABLgAECggJFgAIAIcKAA==.',
Ch='Chromex:BAAALgADCgEJAQAAAA==.',
Ci='Cindro:BAABLgAECn8sAAMHAAkJuQ3BCQDJAQloDAAABwA7AGkMAAAHACYAawwAAAcAHQBqDAAABgAcAGwMAAAFADkAbQwAAAMAEgDqDAAABQAgAG4MAAADABAAbwwAAAEAIgAHAAkJuQ3BCQDJAQloDAAABgA7AGkMAAAGACYAawwAAAYAHQBqDAAABQAcAGwMAAAFADkAbQwAAAMAEgDqDAAABQAgAG4MAAADABAAbwwAAAEAIgAOAAQJPgObTgBmAARoDAAAAQAHAGkMAAABAAkAawwAAAEABwBqDAAAAQAZAAAA.',
Cl='Clam:BAAALgAECgIJAgAAAA==.',
Co='Coheed:BAAALgADCgUJBQAAAA==.Command:BAAALgADCgEJAQAAAA==.Cottonwood:BAAALgADCgYJCwAAAA==.',
Cr='Crystaleyes:BAAALgADCgYJBgAAAA==.',
De='Deathmage:BAAALgADCgMJAwAAAA==.Deekon:BAABLgAECn8VAAMPAAYJOxoKRABiAQZoDAAABQBOAGkMAAAFAEgAawwAAAMAQABqDAAAAgBRAGwMAAACADwA6gwAAAQAPAAPAAYJOxoKRABiAQZoDAAABQBOAGkMAAAFAEgAawwAAAMAQABqDAAAAQAoAGwMAAACADwA6gwAAAQAPAAQAAEJAACyHgAAAAFqDAAAAQBRAAAA.Deni:BAAALgAECgEJAgAAAA==.Devourer:BAAALgADCgEJAQAAAA==.Deyvian:BAAALgAECgIJAgAAAA==.',
Do='Dovathresh:BAAALgAECgcJDAABLgAFFAcJFwARALMWAA==.',
Ec='Ectorius:BAAALgAECgEJAQAAAA==.',
Eg='Egud:BAABLgAECn8cAAISAAgJ5xefCQDgAQhoDAAABQArAGkMAAAFAFIAawwAAAUAPgBqDAAAAwBRAGwMAAADAEYAbQwAAAIAPQDqDAAABAAtAG4MAAABAD4AEgAICecXnwkA4AEIaAwAAAUAKwBpDAAABQBSAGsMAAAFAD4AagwAAAMAUQBsDAAAAwBGAG0MAAACAD0A6gwAAAQALQBuDAAAAQA+AAAA.',
El='Elegean:BAAALgADCgIJAgAAAA==.Eliri:BAACLgAFFH8OAAICAAQJKRzYDQBNAQRoDAAABgBPAGkMAAAEAEwAawwAAAEAQADqDAAAAwBDAAIABAkpHNgNAE0BBGgMAAAGAE8AaQwAAAQATABrDAAAAQBAAOoMAAADAEMALgAECn8YAAICAAgJYhucIACuAQACAAgJYhucIACuAQAAAA==.Ellenad:BAAALgAECgUJCgAAAA==.Elsadormu:BAAALgAECgIJAgABLgAECgQJCwATAAAAAA==.Elsà:BAAALgAECgYJBgABLgAECgYJOAAUAPUiAA==.',
Ev='Evayn:BAAALgAECgYJEQAAAA==.Everhunt:BAAALgAECgQJBAAAAA==.Evo:BAAALgAECgYJEAAAAA==.Evolves:BAAALgADCgEJAQAAAA==.',
Ey='Ey:BAAALgAECgQJBAAAAA==.',
Fa='Fanguloo:BAAALgADCgYJBgAAAA==.Fantasmo:BAAALgAECgEJAQAAAA==.Fantoria:BAAALgADCgcJBAAAAA==.Farisu:BAAALgAECggJEwAAAA==.',
Fe='Feasting:BAAALgADCgEJAQABLgAECgUJCAATAAAAAA==.Feval:BAAALgADCgMJAwAAAA==.',
Fl='Flavortown:BAABLgAECn8WAAIVAAYJwRVaPgBIAQZoDAAABAA3AGkMAAAEADcAawwAAAQAOgBqDAAAAwBVAGwMAAADACsA6gwAAAQAQQAVAAYJwRVaPgBIAQZoDAAABAA3AGkMAAAEADcAawwAAAQAOgBqDAAAAwBVAGwMAAADACsA6gwAAAQAQQAAAA==.Fletch:BAAALgADCgMJAwAAAA==.Flick:BAAALgAECgUJEAAAAA==.Fluffyfury:BAAALgAECgQJCQAAAA==.',
Fo='Foggy:BAAALgADCgEJAQAAAA==.',
Fr='Frontallover:BAAALgADCgUJBQABLgAFFAQJDgACACkcAA==.',
Ga='Gaba:BAABLgAFFH8IAAICAAQJNxMuEgAVAQRoDAAAAwA8AGkMAAACADIAawwAAAEAHwDqDAAAAgA2AAIABAk3Ey4SABUBBGgMAAADADwAaQwAAAIAMgBrDAAAAQAfAOoMAAACADYAAAA=.Galndrel:BAAALgADCgEJAQAAAA==.',
Ge='Georish:BAABLgAECn8eAAIWAAgJgw+aHwDBAQhoDAAABQBKAGkMAAAFACoAawwAAAUAEwBqDAAAAwAgAGwMAAADADkAbQwAAAEACQDqDAAABQA0AG4MAAADABUAFgAICYMPmh8AwQEIaAwAAAUASgBpDAAABQAqAGsMAAAFABMAagwAAAMAIABsDAAAAwA5AG0MAAABAAkA6gwAAAUANABuDAAAAwAVAAAA.',
Gi='Ginseng:BAABLgAECn8UAAIXAAYJdh/OFQATAgZoDAAABQBVAGkMAAAFAFoAawwAAAMAWQBqDAAAAgBLAGwMAAACADYA6gwAAAMAVwAXAAYJdh/OFQATAgZoDAAABQBVAGkMAAAFAFoAawwAAAMAWQBqDAAAAgBLAGwMAAACADYA6gwAAAMAVwAAAA==.',
Go='Gorg:BAABLgAECn8VAAMNAAYJ8gi7EADZAAZoDAAABQAeAGkMAAAFACIAawwAAAMAFABqDAAAAgAOAGwMAAACAAwA6gwAAAQADwANAAYJ8gi7EADZAAZoDAAAAwAeAGkMAAADACIAawwAAAMAFABqDAAAAgAOAGwMAAACAAwA6gwAAAQADwAQAAIJrQanIgBnAAJoDAAAAgAIAGkMAAACABkAAAA=.',
Gr='Grease:BAAALgAECgEJAQAAAA==.',
Gu='Gunkshot:BAABLgAECn8VAAIYAAcJ7yVOCQANAwdoDAAABQBhAGkMAAADAGMAawwAAAMAYQBqDAAAAgBiAGwMAAACAGEA6gwAAAQAYwBuDAAAAgBaABgABwnvJU4JAA0DB2gMAAAFAGEAaQwAAAMAYwBrDAAAAwBhAGoMAAACAGIAbAwAAAIAYQDqDAAABABjAG4MAAACAFoAAAA=.',
['Gé']='Gémini:BAAALgAECgEJAQAAAA==.',
Ha='Haavoc:BAABLgAECn8jAAIZAAkJ3AaSDQBNAQloDAAABQAqAGkMAAAFAAcAawwAAAUAFwBqDAAABQAVAGwMAAAFAA8AbQwAAAEACgDqDAAABgANAG4MAAACAAUAbwwAAAEAFQAZAAkJ3AaSDQBNAQloDAAABQAqAGkMAAAFAAcAawwAAAUAFwBqDAAABQAVAGwMAAAFAA8AbQwAAAEACgDqDAAABgANAG4MAAACAAUAbwwAAAEAFQAAAA==.Hagul:BAAALgADCgQJAwAAAA==.Handsomeman:BAAALgAECgEJAQAAAA==.Haniki:BAAALgADCgMJAwAAAA==.',
He='Hexadecimal:BAAALgAECgIJAwAAAA==.',
Hi='Hiasinth:BAABLgAECn8WAAMCAAgJZxALIgCjAQhoDAAABAAuAGkMAAAEAEMAawwAAAQAMQBqDAAAAwAwAGwMAAACADcAbQwAAAEACwDqDAAAAwAyAG4MAAABAAYAAgAICWcQCyIAowEIaAwAAAMALgBpDAAAAwBDAGsMAAADADEAagwAAAMAMABsDAAAAgA3AG0MAAABAAsA6gwAAAMAMgBuDAAAAQAGAAEAAwnFFmlTAMQAA2gMAAABAFkAaQwAAAEALwBrDAAAAQAlAAAA.',
Ho='Holytroller:BAAALgADCgUJBQAAAA==.Hornhub:BAAALgAECgYJCgAAAA==.',
Ik='Ikhdea:BAAALgADCgUJBQAAAA==.Ikhdin:BAAALgAECgQJBAAAAA==.Ikhlock:BAAALgADCgMJAwAAAA==.Ikthalon:BAAALgADCggJCAAAAA==.',
Im='Imnotafurry:BAAALgAECgYJBwABLgAFFAQJDgACACkcAA==.',
In='Invictorian:BAAALgADCgUJBQAAAA==.',
Ir='Irine:BAAALgAECgQJAwAAAA==.Irore:BAAALgAECgQJBAAAAA==.',
Is='Isoldé:BAAALgADCgcJBwAAAA==.',
Ja='Jagen:BAAALgADCgYJBgAAAA==.Jamarie:BAAALgADCgYJBgAAAA==.Jarrah:BAAALgAECgYJEQAAAA==.Jaxr:BAACLgAFFH8GAAIUAAMJiwU2MQDeAANoDAAAAwATAGkMAAACAAsA6gwAAAEACwAUAAMJiwU2MQDeAANoDAAAAwATAGkMAAACAAsA6gwAAAEACwAuAAQKfyYAAhQACQlCE/cgANsBABQACQlCE/cgANsBAAAA.',
Je='Jetahnna:BAAALgAECgYJDwAAAA==.',
Jh='Jhata:BAABLgAECn8VAAQHAAYJlAxvFAAEAQZoDAAAAwAcAGkMAAAEACUAawwAAAUAHwBqDAAAAwAkAGwMAAACAB4A6gwAAAQAHQAHAAYJlAxvFAAEAQZoDAAAAgAcAGkMAAADACUAawwAAAMAHwBqDAAAAgAkAGwMAAABAB4A6gwAAAIAHQAOAAYJZRGqLwDyAAZoDAAAAQA1AGkMAAABACwAawwAAAIAOABqDAAAAQBDAGwMAAABABQA6gwAAAEALwAaAAEJTgsuPgA2AAHqDAAAAQAcAAAA.',
Jo='Johnnysins:BAAALgAECgUJBwABLgAFFAcJCwALAHoTAA==.Jontarr:BAAALgAECgIJBAAAAA==.',
Ka='Kaelanna:BAAALgAECgcJEAAAAA==.Kajadin:BAAALgAECgYJEwAAAA==.Karatedonkey:BAAALgAECgYJEQAAAA==.Kardai:BAEALgAECgYJEwAAAA==.Katamai:BAABLgAECn8VAAILAAYJ0AQ3oQDaAAZoDAAABQALAGkMAAAFAA8AawwAAAMABwBqDAAAAgAPAGwMAAACAA8A6gwAAAQACwALAAYJ0AQ3oQDaAAZoDAAABQALAGkMAAAFAA8AawwAAAMABwBqDAAAAgAPAGwMAAACAA8A6gwAAAQACwAAAA==.Kazimas:BAAALgAECgUJCgAAAA==.',
Ke='Kelisande:BAAALgADCgEJAQAAAA==.',
Kh='Khalcite:BAAALgAECgYJEwAAAA==.',
Ki='Kik:BAAALgADCgEJAQAAAA==.Kittyshaman:BAABLgAECn8sAAMbAAkJiRGFFgCpAQloDAAABwA4AGkMAAAHAEsAawwAAAcAKABqDAAABgBCAGwMAAAFADYAbQwAAAIADgDqDAAABgBAAG4MAAADABAAbwwAAAEAJAAbAAgJCBKFFgCpAQhoDAAABwA4AGkMAAAHAEsAawwAAAcAKABqDAAABQBCAGwMAAAFADYAbQwAAAIADgDqDAAABgBAAG4MAAADABAAFwACCQUFCogALAACagwAAAEACQBvDAAAAQAQAAAA.',
Ko='Kode:BAAALgAECgMJAwAAAA==.',
Ku='Kuross:BAAALgAECgQJBQAAAA==.',
Ky='Kyraltas:BAAALgAECgYJEAAAAA==.Kyrexis:BAAALgADCgIJAgAAAA==.',
La='Laermeluion:BAAALgAFFAEJAQABLgAFFAcJFwARALMWAA==.Larra:BAABLgAECn84AAIUAAYJ9SJmHQDwAQZoDAAACwBVAGkMAAAKAFgAawwAAAoAWQBqDAAACQBhAGwMAAAIAFYA6gwAAAgAYQAUAAYJ9SJmHQDwAQZoDAAACwBVAGkMAAAKAFgAawwAAAoAWQBqDAAACQBhAGwMAAAIAFYA6gwAAAgAYQAAAA==.',
Le='Lefthian:BAAALgAECgQJEAAAAA==.Lemixa:BAAALgADCgEJAQAAAA==.',
Li='Listwhorior:BAABLgAECn8sAAISAAgJZyE7AwCdAghoDAAABwBNAGkMAAAGAGIAawwAAAcAYQBqDAAABgBUAGwMAAAFAFkAbQwAAAQAVADqDAAABgBRAG4MAAADAEQAEgAICWchOwMAnQIIaAwAAAcATQBpDAAABgBiAGsMAAAHAGEAagwAAAYAVABsDAAABQBZAG0MAAAEAFQA6gwAAAYAUQBuDAAAAwBEAAAA.',
Lo='Logen:BAAALgADCgcJCAAAAA==.Lokita:BAAALgADCgUJBQAAAA==.Loshing:BAAALgAECgIJAgAAAA==.',
Lu='Lunakae:BAAALgAECgUJCwAAAA==.',
Ly='Lysandrra:BAAALgAECgMJBAAAAA==.',
Ma='Madeline:BAAALgAECgMJAwAAAA==.Malafar:BAAALgAFFAIJBAAAAA==.Malfuriion:BAAALgAECgMJBQAAAA==.Maranwae:BAABLgAECn8dAAIXAAcJtSF1CgCSAgdoDAAABQBdAGkMAAAFAFwAawwAAAUARABqDAAABABRAGwMAAADAFwA6gwAAAUAXwBuDAAAAgBQABcABwm1IXUKAJICB2gMAAAFAF0AaQwAAAUAXABrDAAABQBEAGoMAAAEAFEAbAwAAAMAXADqDAAABQBfAG4MAAACAFAAAAA=.Maybemo:BAAALgADCgkJEAAAAA==.',
Me='Mebumsir:BAAALgADCgUJBgAAAA==.Melokoi:BAABLgAECn8ZAAMSAAgJVCD1AwCEAghoDAAABABQAGkMAAAEAE8AawwAAAQAWQBqDAAABABFAGwMAAADAE4AbQwAAAEAUgDqDAAABABYAG4MAAABAFAAEgAICVQg9QMAhAIIaAwAAAMAUABpDAAAAwBPAGsMAAADAFkAagwAAAMARQBsDAAAAwBOAG0MAAABAFIA6gwAAAMAWABuDAAAAQBQABwABQniBJIrAJgABWgMAAABAAkAaQwAAAEAAgBrDAAAAQAUAGoMAAABAAoA6gwAAAEAEQAAAA==.Merlose:BAABLgAECn8fAAIdAAgJLhb8CADEAQhoDAAABgBHAGkMAAAGAEAAawwAAAUAMwBqDAAABAA7AGwMAAADAEQAbQwAAAEAMwDqDAAABQAZAG4MAAABAEAAHQAICS4W/AgAxAEIaAwAAAYARwBpDAAABgBAAGsMAAAFADMAagwAAAQAOwBsDAAAAwBEAG0MAAABADMA6gwAAAUAGQBuDAAAAQBAAAAA.',
Mi='Minidrake:BAAALgAECgUJDgAAAA==.',
Mo='Mogrun:BAABLgAECn8WAAMNAAcJShlpFwCOAQdoDAAABABMAGkMAAAEAEEAawwAAAQARgBqDAAAAwA0AGwMAAADACkA6gwAAAMARABuDAAAAQBBAA8ABgklGo1YAL4BBmgMAAACAEoAaQwAAAEANwBrDAAAAgBGAGoMAAABACgA6gwAAAIARABuDAAAAQBBAA0ABgmVFWkXAI4BBmgMAAACAEwAaQwAAAMAQQBrDAAAAgAzAGoMAAACADQAbAwAAAMAKQDqDAAAAQApAAAA.Monahci:BAAALgADCgcJEwAAAA==.Monocho:BAAALgADCgMJAwAAAA==.Monrroe:BAAALgAECgYJDAAAAA==.Mooasaurus:BAAALgAFFAIJAgAAAA==.Moonfaith:BAAALgADCgYJBgABLgAFFAMJBwAIAJkRAA==.Moonveil:BAAALgAECggJDQABLgAFFAMJBwAIAJkRAA==.Moshamie:BAAALgAECgcJEgAAAA==.',
Na='Naeryns:BAAALgAECgUJCQAAAA==.Narzwaz:BAABLgAECn8WAAIBAAYJbB39EwCcAQZoDAAABQBbAGkMAAAEAFUAawwAAAQATgBqDAAAAwBVAGwMAAABADIA6gwAAAUARwABAAYJbB39EwCcAQZoDAAABQBbAGkMAAAEAFUAawwAAAQATgBqDAAAAwBVAGwMAAABADIA6gwAAAUARwAAAA==.Natallia:BAAALgADCgUJBQABLgAECgYJOAAUAPUiAA==.',
Ne='Nehemiia:BAAALgADCgMJAwAAAA==.Neytri:BAABLgAECn8ZAAIUAAgJbgupNwBxAQhoDAAABAAfAGkMAAAEACgAawwAAAQAKABqDAAAAwAVAGwMAAADAA4AbQwAAAIAEADqDAAABAAPAG4MAAABAC4AFAAICW4LqTcAcQEIaAwAAAQAHwBpDAAABAAoAGsMAAAEACgAagwAAAMAFQBsDAAAAwAOAG0MAAACABAA6gwAAAQADwBuDAAAAQAuAAAA.',
Ni='Nivale:BAABLgAECn8WAAILAAYJWhvgSQCRAQZoDAAABABOAGkMAAAEAE0AawwAAAQAOwBqDAAAAwBSAGwMAAADAEQA6gwAAAQAQgALAAYJWhvgSQCRAQZoDAAABABOAGkMAAAEAE0AawwAAAQAOwBqDAAAAwBSAGwMAAADAEQA6gwAAAQAQgAAAA==.',
No='Noel:BAABLgAECn8gAAILAAgJshmONwDLAQhoDAAABQBQAGkMAAAFAEYAawwAAAUAUQBqDAAABABTAGwMAAAEAE0AbQwAAAMAPgDqDAAABQBNAG4MAAABAAkACwAICbIZjjcAywEIaAwAAAUAUABpDAAABQBGAGsMAAAFAFEAagwAAAQAUwBsDAAABABNAG0MAAADAD4A6gwAAAUATQBuDAAAAQAJAAAA.Nosotras:BAAALgAECgYJEwAAAA==.Noxicous:BAAALgAECgYJEQAAAA==.',
Ol='Olitas:BAAALgAECgQJBgAAAA==.',
Pa='Patches:BAABLgAECn8VAAMeAAcJKhAXFAB6AQdoDAAABAAxAGkMAAAEACwAawwAAAQAOgBqDAAAAgAiAGwMAAACABMA6gwAAAQAMwBuDAAAAQAXAB4ABwkqEBcUAHoBB2gMAAAEADEAaQwAAAQALABrDAAABAA6AGoMAAACACIAbAwAAAEAEwDqDAAABAAzAG4MAAABABcAHwABCRIENh4AKAABbAwAAAEACgAAAA==.',
Pe='Perse:BAAALgAECgQJBQAAAA==.',
Ph='Phau:BAAALgAECgYJEwAAAA==.',
Pi='Pinklemonade:BAAALgADCgIJAgAAAA==.',
Pl='Playmate:BAACLgAFFH8HAAIIAAMJmRFEJADNAANoDAAAAwA7AGkMAAADADcA6gwAAAEAEwAIAAMJmRFEJADNAANoDAAAAwA7AGkMAAADADcA6gwAAAEAEwAuAAQKfyMAAggACAlXH6oOAHICAAgACAlXH6oOAHICAAAA.',
Po='Potatoe:BAAALgADCgQJBAAAAA==.',
Pr='Prozac:BAAALgADCgMJAwAAAA==.Prïnçess:BAAALgAECgUJDAAAAA==.',
Py='Pymilocs:BAAALgAECgYJEwAAAA==.',
Qu='Qualison:BAAALgAECgYJEgAAAA==.',
Ra='Rabare:BAAALgAECgcJDgAAAA==.Rabore:BAAALgAECgQJBAAAAA==.Rahumn:BAABLgAECn8aAAIEAAcJjxMvHQCGAQdoDAAABAA1AGkMAAAEACwAawwAAAUANQBqDAAAAwA9AGwMAAADADUA6gwAAAYAOQBuDAAAAQAmAAQABwmPEy8dAIYBB2gMAAAEADUAaQwAAAQALABrDAAABQA1AGoMAAADAD0AbAwAAAMANQDqDAAABgA5AG4MAAABACYAAAA=.Ralee:BAAALgAECgUJCwABLgAECgYJFQAbAH8GAA==.Ranebowz:BAABLgAECn8aAAIFAAgJ/BzVFgBOAghoDAAABABSAGkMAAAEAEkAawwAAAQARQBqDAAABABEAGwMAAADAEwAbQwAAAIAPgDqDAAABABOAG4MAAABAEwABQAICfwc1RYATgIIaAwAAAQAUgBpDAAABABJAGsMAAAEAEUAagwAAAQARABsDAAAAwBMAG0MAAACAD4A6gwAAAQATgBuDAAAAQBMAAAA.Ravenmohr:BAAALgADCgUJBQAAAA==.',
Re='Rennai:BAAALgADCggJCAAAAA==.',
Rh='Rhebeqa:BAAALgADCgkJEAABLgAECgQJDAATAAAAAA==.',
Ri='Richter:BAAALgADCgkJIAAAAA==.Rin:BAEBLgAECn8eAAICAAgJhB+PBgChAghoDAAABQBSAGkMAAAFAFAAawwAAAUAUABqDAAABABUAGwMAAADAE4AbQwAAAEARADqDAAABABgAG4MAAADAEkAAgAICYQfjwYAoQIIaAwAAAUAUgBpDAAABQBQAGsMAAAFAFAAagwAAAQAVABsDAAAAwBOAG0MAAABAEQA6gwAAAQAYABuDAAAAwBJAAAA.Rist:BAABLgAECn8gAAISAAkJARAuDACpAQloDAAABQArAGkMAAAFAD0AawwAAAUAMwBqDAAABAAgAGwMAAAEADgAbQwAAAEAJgDqDAAABQAcAG4MAAACAB4AbwwAAAEAEAASAAkJARAuDACpAQloDAAABQArAGkMAAAFAD0AawwAAAUAMwBqDAAABAAgAGwMAAAEADgAbQwAAAEAJgDqDAAABQAcAG4MAAACAB4AbwwAAAEAEAAAAA==.',
Ro='Rogelink:BAAALgAECggJDgAAAA==.Rosan:BAAALgAECgQJBAAAAA==.Royakan:BAAALgAECgEJBAAAAA==.',
Sa='Samoset:BAAALgAECgYJEwAAAA==.',
Se='Setsuna:BAABLgAECn8eAAMaAAkJESP6BwBoAgloDAAABABgAGkMAAAEAF4AawwAAAQAWgBqDAAAAwBQAGwMAAAEAGEAbQwAAAIASgDqDAAABQBeAG4MAAACAFUAbwwAAAIAVAAaAAYJBCX6BwBoAgZoDAAABABgAGkMAAAEAF4AawwAAAQAWgBqDAAAAwBQAGwMAAADAGEA6gwAAAQAXgAOAAUJZx59FQClAQVsDAAAAQBXAG0MAAACAEoA6gwAAAEAOQBuDAAAAgBVAG8MAAACAFQAAS4ABAoDCQMAEwAAAAA=.',
Sh='Shava:BAAALgAECgYJBgAAAA==.Sheepstealer:BAABLgAECn8bAAIaAAcJThQCBgB9AQdoDAAABQA4AGkMAAAFADsAawwAAAUANABqDAAAAwBQAGwMAAADAEMA6gwAAAUAMABuDAAAAQAaABoABwlOFAIGAH0BB2gMAAAFADgAaQwAAAUAOwBrDAAABQA0AGoMAAADAFAAbAwAAAMAQwDqDAAABQAwAG4MAAABABoAAAA=.Shippo:BAAALgAECgIJAgAAAA==.Shockisha:BAAALgADCgYJBgAAAA==.Showgirl:BAAALgADCgcJBwABLgAFFAQJCgAHAFcaAA==.',
Si='Silvanthos:BAAALgAECgQJBAAAAA==.Silvers:BAAALgAECgUJCwAAAA==.',
Sl='Sliccie:BAABLgAECn8mAAIPAAgJwhGiMQCiAQhoDAAABQA2AGkMAAAGADMAawwAAAYALwBqDAAABQAyAGwMAAAEAC8AbQwAAAIAIwDqDAAABwAvAG4MAAADACEADwAICcIRojEAogEIaAwAAAUANgBpDAAABgAzAGsMAAAGAC8AagwAAAUAMgBsDAAABAAvAG0MAAACACMA6gwAAAcALwBuDAAAAwAhAAAA.',
Sm='Smitegoat:BAABLgAECn8mAAMKAAkJ8RqeFAA5AgloDAAABgBNAGkMAAAGAEQAawwAAAYATgBqDAAABAA8AGwMAAADAFAAbQwAAAIAPADqDAAABwBSAG4MAAADAB8AbwwAAAEATwAKAAgJ8xmeFAA5AghoDAAABgBNAGkMAAAGAEQAawwAAAYATgBqDAAABAA8AGwMAAADAFAAbQwAAAIAPADqDAAABQBIAG4MAAADAB8AIAACCagfaDAAvAAC6gwAAAIAUgBvDAAAAQBPAAAA.',
Sn='Sney:BAABLgAECn8VAAIbAAYJfwa4OQDRAAZoDAAABgATAGkMAAAGABYAawwAAAUADABqDAAAAQAJAGwMAAABAAgA6gwAAAIAEgAbAAYJfwa4OQDRAAZoDAAABgATAGkMAAAGABYAawwAAAUADABqDAAAAQAJAGwMAAABAAgA6gwAAAIAEgAAAA==.',
So='Sorlzul:BAAALgAECgMJBwAAAA==.',
Sp='Specialbarz:BAAALgADCgEJAQAAAA==.',
St='Stellaluna:BAAALgAECgQJBAAAAA==.',
Sv='Svanalock:BAAALgADCgcJDwAAAA==.',
Ta='Tad:BAABLgAECn8bAAIUAAcJWA7zPQBZAQdoDAAABQAwAGkMAAAFADEAawwAAAUAPwBqDAAAAwAYAGwMAAADAA8A6gwAAAUAFgBuDAAAAQAUABQABwlYDvM9AFkBB2gMAAAFADAAaQwAAAUAMQBrDAAABQA/AGoMAAADABgAbAwAAAMADwDqDAAABQAWAG4MAAABABQAAAA=.Taini:BAAALgADCgYJBgABLgAFFAcJFwARALMWAA==.Taiurag:BAAALgAECgUJEAAAAA==.Taken:BAAALgAECgYJEwAAAA==.Tazra:BAABLgAECn8kAAIFAAkJax2MFQBYAgloDAAABgBaAGkMAAAFAFcAawwAAAQASwBqDAAABABRAGwMAAAFAFEAbQwAAAIASQDqDAAABQBTAG4MAAAEADQAbwwAAAEAOgAFAAkJax2MFQBYAgloDAAABgBaAGkMAAAFAFcAawwAAAQASwBqDAAABABRAGwMAAAFAFEAbQwAAAIASQDqDAAABQBTAG4MAAAEADQAbwwAAAEAOgAAAA==.Tazzy:BAAALgADCgkJDwAAAA==.Tazzyy:BAAALgAECgQJBAAAAA==.',
Te='Terrylabonte:BAAALgAECgcJEgAAAA==.',
Th='Thomaz:BAABLgAECn8fAAIEAAkJhBDCEQDqAQloDAAABAAiAGkMAAAEACsAawwAAAQAMwBqDAAABAArAGwMAAADAC4AbQwAAAMAGwDqDAAABQAvAG4MAAADACAAbwwAAAEANgAEAAkJhBDCEQDqAQloDAAABAAiAGkMAAAEACsAawwAAAQAMwBqDAAABAArAGwMAAADAC4AbQwAAAMAGwDqDAAABQAvAG4MAAADACAAbwwAAAEANgAAAA==.Thorninii:BAAALgADCgQJBAAAAA==.Thundergoose:BAAALgAECgMJAwAAAA==.',
Ti='Tirel:BAAALgADCgUJBQAAAA==.',
To='Tonkatruck:BAAALgAECgYJEwAAAA==.',
Tt='Ttvnazboo:BAAALgADCgMJBAAAAA==.',
Tu='Tulany:BAABLgAECn8VAAMKAAgJYwjiIwAzAQhoDAAABAAcAGkMAAADAA8AawwAAAQAGQBqDAAAAwAXAGwMAAACABIAbQwAAAEAGwDqDAAAAwAOAG4MAAABABMACgAICQoH4iMAMwEIaAwAAAEAHABpDAAAAQAMAGsMAAABABAAagwAAAEADABsDAAAAQAMAG0MAAABABsA6gwAAAEADgBuDAAAAQATACAABgljBwkxABgBBmgMAAADABMAaQwAAAIADwBrDAAAAwAZAGoMAAACABcAbAwAAAEAEgDqDAAAAgALAAAA.Tuyenlotus:BAABLgAECn8hAAIhAAkJAhyiBAAiAgloDAAABQBIAGkMAAAFAFAAawwAAAQAUwBqDAAAAwBGAGwMAAAEADwAbQwAAAIAJgDqDAAABgBOAG4MAAACAFkAbwwAAAIARgAhAAkJAhyiBAAiAgloDAAABQBIAGkMAAAFAFAAawwAAAQAUwBqDAAAAwBGAGwMAAAEADwAbQwAAAIAJgDqDAAABgBOAG4MAAACAFkAbwwAAAIARgAAAA==.',
Un='Unholypriest:BAAALgAECgUJCgAAAA==.',
Ut='Utloc:BAAALgAECgYJEwAAAA==.',
Va='Vahnya:BAAALgAECgYJDwAAAA==.Vardren:BAAALgADCgQJBAAAAA==.',
Ve='Venekor:BAABLgAECn8WAAIOAAYJLgX7PgDuAAZoDAAABQANAGkMAAAEAA4AawwAAAQADQBqDAAAAwAPAGwMAAACAA4A6gwAAAQACQAOAAYJLgX7PgDuAAZoDAAABQANAGkMAAAEAA4AawwAAAQADQBqDAAAAwAPAGwMAAACAA4A6gwAAAQACQAAAA==.Vesia:BAABLgAECn8YAAMKAAYJZRg1HQBpAQZoDAAABABDAGkMAAAEAEcAawwAAAUAQABqDAAAAwAxAGwMAAADADoA6gwAAAUAQAAKAAYJZRg1HQBpAQZoDAAAAwBDAGkMAAADAEcAawwAAAQAQABqDAAAAgAxAGwMAAADADoA6gwAAAUAQAAJAAQJYBPYPwD4AARoDAAAAQAwAGkMAAABAC8AawwAAAEANABqDAAAAQAWAAAA.',
Vi='Viainfinita:BAAALgADCgYJBgAAAA==.Viannaironcl:BAAALgADCgIJAgAAAA==.',
Vo='Voidrat:BAAALgAECgEJAwABLgAECgcJIgABAGIXAA==.Voidweaver:BAAALgADCgYJBgAAAA==.',
['Ví']='Ví:BAAALgAECgYJEwAAAA==.',
Wa='Warfare:BAAALgADCgUJBQABLgAECgkJIwAZANwGAA==.',
Wh='Whistler:BAAALgADCgEJAQAAAA==.',
Wi='Wildpally:BAAALgAECgUJEgAAAA==.',
['Wí']='Wíldhide:BAAALgADCgMJAwAAAA==.',
Xo='Xonon:BAAALgAECgYJEAAAAA==.',
Xw='Xweithel:BAAALgAECgQJBwAAAA==.',
Yo='Yourmageisty:BAABLgAECn8nAAMLAAkJQRUIJQAZAgloDAAABwBPAGkMAAAGAEUAawwAAAUAIABqDAAABAAqAGwMAAAFAEQAbQwAAAMAOADqDAAABgA+AG4MAAACACUAbwwAAAEAHAALAAkJThIIJQAZAgloDAAABgA5AGkMAAAEACAAawwAAAQAHwBqDAAABAAqAGwMAAAFAEQAbQwAAAMAOADqDAAABQA+AG4MAAACACUAbwwAAAEAHAAiAAQJmheVCwAcAQRoDAAAAQBPAGkMAAACAEUAawwAAAEAIADqDAAAAQA7AAAA.',
Yu='Yulíana:BAAALgAECgUJCQAAAA==.',
Za='Zanot:BAAALgADCgYJBgAAAA==.Zariara:BAAALgADCgUJBQAAAA==.',
Zc='Zcart:BAABLgAECn8VAAMUAAYJ9g0rVgAOAQZoDAAABQAqAGkMAAAFACQAawwAAAMAFgBqDAAAAgA7AGwMAAACACwA6gwAAAQAIQAUAAYJ9g0rVgAOAQZoDAAABQAqAGkMAAAFACQAawwAAAIAFgBqDAAAAgA7AGwMAAACACwA6gwAAAQAIQAYAAEJ4QFMmgAZAAFrDAAAAQAEAAAA.',
Ze='Zelara:BAAALgAFFAIJAgAAAA==.Zertloc:BAABLgAECn8eAAIbAAYJCRvlGQCLAQZoDAAABgBAAGkMAAAGAEgAawwAAAYAQgBqDAAABQBRAGwMAAADAE0A6gwAAAQAQAAbAAYJCRvlGQCLAQZoDAAABgBAAGkMAAAGAEgAawwAAAYAQgBqDAAABQBRAGwMAAADAE0A6gwAAAQAQAAAAA==.',
Zh='Zhaan:BAAALgAECgEJAQAAAA==.',
Zi='Zieda:BAABLgAECn8gAAIjAAcJBw9bIgAxAQdoDAAABgA4AGkMAAAFADAAawwAAAUAJABqDAAABAAbAGwMAAAFABkAbQwAAAIAGwDqDAAABQAkACMABwkHD1siADEBB2gMAAAGADgAaQwAAAUAMABrDAAABQAkAGoMAAAEABsAbAwAAAUAGQBtDAAAAgAbAOoMAAAFACQAAAA=.Ziti:BAAALgADCgIJAgAAAA==.',
Zo='Zombini:BAAALgAECgQJBAAAAA==.',
Zu='Zubiria:BAAALgADCgcJCwAAAA==.Zulaaj:BAAALgAECgMJAwAAAA==.',
['Év']='Évania:BAAALgADCgYJBgAAAA==.Éver:BAAALgADCgUJBQAAAA==.',
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
