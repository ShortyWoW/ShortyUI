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

local lookup = {'Paladin-Holy','Evoker-Preservation','Unknown-Unknown','Evoker-Augmentation','Evoker-Devastation','Monk-Brewmaster','DemonHunter-Havoc','DemonHunter-Devourer','DemonHunter-Vengeance','Warrior-Protection','Rogue-Subtlety','Mage-Frost','Warlock-Demonology','Rogue-Assassination','Warrior-Fury','Rogue-Outlaw','DeathKnight-Blood','Druid-Guardian','Monk-Windwalker','Shaman-Elemental','Shaman-Restoration','Priest-Shadow','Warlock-Destruction','Warlock-Affliction','Paladin-Retribution','Priest-Holy','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Unholy','Priest-Discipline','Mage-Fire','Mage-Arcane','Druid-Balance',}
local provider = {region='US',realm='BleedingHollow',name='US',type='subscribers',zone=46,date='2026-04-28',data={Ad='Addex:BAEBLgAFFH8LAAIBAAYJyRDLAQDjAQZoDAAAAgA0AGkMAAACAD0AawwAAAIADQBqDAAAAgAiAGwMAAABACsA6gwAAAIANAABAAYJyRDLAQDjAQZoDAAAAgA0AGkMAAACAD0AawwAAAIADQBqDAAAAgAiAGwMAAABACsA6gwAAAIANAABLgAFFAgJHAACAJ4aAA==.',
Ae='Aeveracy:BAEALgADCgMJAwABLgAECgIJAgADAAAAAA==.',
Am='Ambient:BAECLgAFFH8cAAMCAAgJnhrNAABkAghoDAAABQBEAGkMAAAFAEAAawwAAAUAQABqDAAABABLAGwMAAADAFQAbQwAAAEAJwDqDAAABABLAG4MAAABAEkAAgAICZ4azQAAZAIIaAwAAAMARABpDAAABQBAAGsMAAAFAEAAagwAAAQASwBsDAAAAwBUAG0MAAABACcA6gwAAAQASwBuDAAAAQBJAAQAAQk/F24gAFAAAWgMAAACADsALgAECn8dAAMCAAkJcyO/BAADAwACAAgJKyO/BAADAwAFAAEJiBPGOgBEAAAAAA==.',
Br='Briéè:BAEALgAECgMJBAAAAA==.Bruwon:BAECLgAFFH8XAAIGAAcJTiCJAAAEAgdoDAAABABIAGkMAAAEAFcAawwAAAQAVwBqDAAAAwA8AGwMAAACAFQAbQwAAAEATwDqDAAABQBUAAYABwlOIIkAAAQCB2gMAAAEAEgAaQwAAAQAVwBrDAAABABXAGoMAAADADwAbAwAAAIAVABtDAAAAQBPAOoMAAAFAFQALgAECn8hAAIGAAkJPyHFBAA+AwAGAAkJPyHFBAA+AwAAAA==.',
Ca='Captinsaneo:BAEALgAECggJCAAAAA==.',
Ch='Charzie:BAEALgAECgEJAQABLgAFFAcJFwAGAE4gAA==.',
Ci='Ciprox:BAEALgAECggJDgABLgAFFAUJDgAHAAYeAA==.',
Cy='Cyprexdh:BAECLgAFFH8OAAMHAAUJBh7sAQB7AQVoDAAABQBjAGkMAAADADMAawwAAAMAQQBqDAAAAgAmAOoMAAABAFoABwAECX8Z7AEAewEEaAwAAAMAYwBpDAAAAQAFAGsMAAABAEEA6gwAAAEAWgAIAAQJahNWFAAwAQRoDAAAAgAxAGkMAAACADMAawwAAAIALwBqDAAAAgAmAC4ABAp/HQAEBwAJCXckMwMAUgMABwAICVslMwMAUgMACAAECS0hajEAJgEACQABCQAAuC0AKQAAAAA=.',
Da='Danilynn:BAEALgADCggJFAABLgAECgYJEAADAAAAAA==.Danitsia:BAEALgAECgYJEAAAAA==.',
De='Delabrand:BAEALgAECgYJCQABLgAFFAYJEwAKAAomAA==.Delarage:BAECLgAFFH8TAAIKAAYJCiYvAAA8AgZoDAAABQBjAGkMAAADAGMAawwAAAMAWgBqDAAAAwBhAGwMAAABAGQA6gwAAAQAYQAKAAYJCiYvAAA8AgZoDAAABQBjAGkMAAADAGMAawwAAAMAWgBqDAAAAwBhAGwMAAABAGQA6gwAAAQAYQAuAAQKfx0AAgoACAn5Jv8AAJADAAoACAn5Jv8AAJADAAAA.Deleerious:BAECLgAFFH8JAAILAAMJHSRKCAAsAQNoDAAABABiAGkMAAADAGAA6gwAAAIAUgALAAMJHSRKCAAsAQNoDAAABABiAGkMAAADAGAA6gwAAAIAUgAuAAQKfx0AAgsACAn6IJ4FADgDAAsACAn6IJ4FADgDAAAA.',
Do='Doriel:BAEALgAECgMJBAABLgAFFAMJBwAMAOQQAA==.',
Du='Dubsstree:BAEALgADCgYJBgABLgAFFAYJEgANALIdAA==.',
Dw='Dwarfwarloc:BAEALgAECgYJEQAAAA==.',
Eg='Egirlarmpits:BAEALgAFFAEJAQABLgAFFAQJBQABAOoDAA==.',
Em='Emellious:BAECLgAFFH8MAAILAAUJThiRBwBrAQVoDAAABABPAGkMAAAEAFsAawwAAAEADABqDAAAAQA6AOoMAAACAEEACwAFCU4YkQcAawEFaAwAAAQATwBpDAAABABbAGsMAAABAAwAagwAAAEAOgDqDAAAAgBBAC4ABAp/HAADCwAICQMhmAwAzwIACwAICQMhmAwAzwIADgABCZALfh8ANQAAAAA=.',
Fu='Funkaroused:BAEBLgAECn8lAAIPAAcJYxqUEACHAQdoDAAABgBbAGkMAAAGAEcAawwAAAYAQABqDAAABQBFAGwMAAAGAEsA6gwAAAYANABuDAAAAgAyAA8ABwljGpQQAIcBB2gMAAAGAFsAaQwAAAYARwBrDAAABgBAAGoMAAAFAEUAbAwAAAYASwDqDAAABgA0AG4MAAACADIAAAA=.',
Gi='Giantmagic:BAEBLgAECn8VAAIMAAcJthl5XQAiAgdoDAAAAwBOAGkMAAADAEoAawwAAAMAWwBqDAAABABOAGwMAAACAD4AbQwAAAEAEwDqDAAABQBEAAwABwm2GXldACICB2gMAAADAE4AaQwAAAMASgBrDAAAAwBbAGoMAAAEAE4AbAwAAAIAPgBtDAAAAQATAOoMAAAFAEQAAAA=.',
Gj='Gjlo:BAEBLgAECn8zAAMPAAkJNBbyBAA8AgloDAAABwBQAGkMAAAJAEwAawwAAAYATQBqDAAABgBGAGwMAAAGAEEAbQwAAAQAEgDqDAAABgBGAG4MAAAFADcAbwwAAAIACQAPAAkJNBbyBAA8AgloDAAABgBQAGkMAAAIAEwAawwAAAUATQBqDAAABABGAGwMAAADAEEAbQwAAAIAEgDqDAAABABGAG4MAAAFADcAbwwAAAIACQAKAAcJhg32FAC6AAdoDAAAAQBCAGkMAAABADcAawwAAAEAGgBqDAAAAgAdAGwMAAADACAAbQwAAAIACADqDAAAAgARAAAA.',
Gl='Gluzzaie:BAEALgAECggJEwAAAA==.',
Gr='Gronknose:BAEBLgAECn8WAAIQAAcJ0iHgAQCcAgdoDAAAAwBVAGkMAAAEAFwAawwAAAQATABqDAAAAwBeAGwMAAACAFcAbQwAAAEAUgDqDAAABQBfABAABwnSIeABAJwCB2gMAAADAFUAaQwAAAQAXABrDAAABABMAGoMAAADAF4AbAwAAAIAVwBtDAAAAQBSAOoMAAAFAF8AAS4ABAoICR4ABgC1IgA=.',
Ha='Hakdh:BAEALgAECgYJBgABLgAFFAUJCQARAG8QAA==.Hakdk:BAEBLgAFFH8JAAIRAAUJbxDzBQA7AQVoDAAAAQAiAGkMAAABACMAawwAAAEAJwBqDAAAAwAaAOoMAAADADoAEQAFCW8Q8wUAOwEFaAwAAAEAIgBpDAAAAQAjAGsMAAABACcAagwAAAMAGgDqDAAAAwA6AAAA.Hakgek:BAEBLgAFFH8HAAISAAQJAA6+AQAxAQRoDAAAAgAlAGkMAAACACgAawwAAAIAJgBsDAAAAQAbABIABAkADr4BADEBBGgMAAACACUAaQwAAAIAKABrDAAAAgAmAGwMAAABABsAAS4ABRQFCQkAEQBvEAA=.Hakmonk:BAEBLgAFFH8GAAIGAAQJSxHFDQAWAQRoDAAAAgAmAGkMAAACAEsAawwAAAEAEQDqDAAAAQAuAAYABAlLEcUNABYBBGgMAAACACYAaQwAAAIASwBrDAAAAQARAOoMAAABAC4AAS4ABRQFCQkAEQBvEAA=.Haksham:BAEALgAECgcJBAABLgAFFAUJCQARAG8QAA==.Hakwar:BAEALgAECgUJBQABLgAFFAUJCQARAG8QAA==.Halosbrew:BAECLgAFFH8JAAIGAAQJrBnfDwADAQRoDAAAAgBLAGkMAAADAFYAawwAAAEAGgDqDAAAAwBKAAYABAmsGd8PAAMBBGgMAAACAEsAaQwAAAMAVgBrDAAAAQAaAOoMAAADAEoALgAECn8UAAMGAAgJRx4PFQBjAgAGAAcJzSEPFQBjAgATAAUJaROvPAAoAQAAAA==.Halosdk:BAEALgAFFAIJBAABLgAFFAQJCQAGAKwZAA==.',
He='Heavensfeel:BAEBLgAECn8hAAQCAAgJ8h4HCAC7AghoDAAABgBVAGkMAAAFAD0AawwAAAUASwBqDAAABABbAGwMAAAEAFYAbQwAAAIAUADqDAAABQBVAG4MAAACAEMAAgAICfIeBwgAuwIIaAwAAAUAVQBpDAAABAA9AGsMAAAEAEsAagwAAAMAWwBsDAAAAwBWAG0MAAACAFAA6gwAAAQAVQBuDAAAAgBDAAQABAmfDWQmAKQABGkMAAABAAcAawwAAAEAMQBqDAAAAQA6AGwMAAABAC8ABQACCUMLLQsAeAACaAwAAAEAGgDqDAAAAQAeAAEuAAUUBAkJAAYArBkA.',
In='Initiative:BAEALgAECgYJEgAAAA==.',
It='Itsgrippy:BAEALgAECgYJDgAAAA==.',
Ke='Keeflan:BAEBLgAECn8ZAAMUAAgJIB+2KwC6AQhoDAAABABiAGkMAAAEAFUAawwAAAQASQBqDAAAAwA4AGwMAAADADwAbQwAAAEARgDqDAAABQBaAG4MAAABAE8AFAAGCeAftisAugEGaAwAAAMAYgBpDAAAAgBVAGsMAAACAEkAagwAAAIAOABsDAAAAwA8AOoMAAADAFoAFQAHCUYNq0AAfgEHaAwAAAEAOwBpDAAAAgASAGsMAAACACIAagwAAAEABQBtDAAAAQAEAOoMAAACAFoAbgwAAAEAGAABLgAFFAQJBQABAOoDAA==.',
Le='Lewinskibidi:BAEALgAFFAIJAgABLgAFFAYJEgAWAPggAA==.',
Ma='Madtheaug:BAEBLgAECn8WAAMFAAgJkyArEgC+AQhoDAAAAgBPAGkMAAACAEkAawwAAAIAVwBqDAAABABWAGwMAAADAFwAbQwAAAMAUADqDAAABABbAG4MAAACAE4ABQAHCbMYKxIAvgEHaAwAAAIATwBpDAAAAgBJAGsMAAACAFcAagwAAAIAOwBsDAAAAgARAG0MAAACAC8A6gwAAAIASQAEAAUJgSFhIAC9AQVqDAAAAgBWAGwMAAABAFwAbQwAAAEAUADqDAAAAgBbAG4MAAACAE4AAS4ABRQICRgAFwDRJQA=.Madthehunt:BAEALgAFFAEJAQABLgAFFAgJGAAXANElAA==.Madthelock:BAECLgAFFH8YAAMXAAgJ0SU3AACWAghoDAAAAwBfAGkMAAADAGEAawwAAAQAZABqDAAABABYAGwMAAADAGEAbQwAAAEAYgDqDAAABQBhAG4MAAABAFoAFwAGCScmNwAAlgIGaQwAAAIAYQBrDAAABABkAGoMAAADAFgAbAwAAAIAYQBtDAAAAQBiAOoMAAACAF4ADQAGCSkh3gAAUQIGaAwAAAMAXwBpDAAAAQBeAGoMAAABAEcAbAwAAAEALgDqDAAAAwBhAG4MAAABAFoALgAECn8ZAAQNAAkJhyRZDAAYAwANAAkJkyFZDAAYAwAXAAYJHCZbCgAZAgAYAAMJASRlDgBLAQAAAA==.Magølli:BAECLgAFFH8HAAIMAAMJ5BApPQCxAANoDAAAAwAtAGkMAAADADgAawwAAAEAGgAMAAMJ5BApPQCxAANoDAAAAwAtAGkMAAADADgAawwAAAEAGgAuAAQKfx8AAgwACAk1H0YmANkCAAwACAk1H0YmANkCAAAA.',
Mi='Minbä:BAEALgAECgYJEgABLgAFFAYJEgANALIdAA==.Minigun:BAEALgAECgcJCgAAAQ==.Minipala:BAECLgAFFH8GAAIBAAMJvhiZDQDrAANoDAAAAwBPAGkMAAACADMA6gwAAAEAOwABAAMJvhiZDQDrAANoDAAAAwBPAGkMAAACADMA6gwAAAEAOwAuAAQKfx0AAwEACAk4IoQGAAMDAAEACAk4IoQGAAMDABkABQnnDy+zAB4BAAEuAAUUBgkSAA0Ash0A.Miniss:BAECLgAFFH8SAAMNAAYJsh1qAQDjAQZoDAAABQBeAGkMAAAEAE8AawwAAAIAUQBqDAAAAwBXAGwMAAABABoA6gwAAAMAYQANAAYJsh1qAQDjAQZoDAAABQBeAGkMAAACAE8AawwAAAEAUQBqDAAAAwBXAGwMAAABABoA6gwAAAMAYQAXAAIJgA0/DQCjAAJpDAAAAgAeAGsMAAABACYALgAECn8vAAQNAAkJzSX6AAA0AwANAAkJyiX6AAA0AwAXAAIJESA9QQCwAAAYAAEJECcDMgA6AAAAAA==.',
Mo='Moosclemommy:BAECLgAFFH8LAAIGAAQJFx6dAwCFAQRoDAAABABFAGkMAAACAD0AawwAAAIAWQDqDAAAAwBXAAYABAkXHp0DAIUBBGgMAAAEAEUAaQwAAAIAPQBrDAAAAgBZAOoMAAADAFcALgAECn8gAAIGAAgJICW+BQAsAwAGAAgJICW+BQAsAwABLgAFFAYJCgACAKEIAA==.',
My='Mythicalhobo:BAEALgADCgUJCAAAAA==.Mythmaker:BAEALgAECgUJCQABLgAECgcJFQAMALYZAA==.',
Na='Nargrodamus:BAEALgAECggJEQAAAA==.',
Ni='Nimueh:BAECLgAFFH8GAAIaAAUJugV2AwBUAQVoDAAAAQAEAGkMAAABABwAawwAAAEABwBqDAAAAQATAGwMAAACAA0AGgAFCboFdgMAVAEFaAwAAAEABABpDAAAAQAcAGsMAAABAAcAagwAAAEAEwBsDAAAAgANAC4ABAp/IQACGgAJCS8S4RQANgIAGgAJCS8S4RQANgIAAAA=.Nindë:BAEALgAFFAMJAwABLgAFFAUJDwAbAD0OAA==.Niniane:BAECLgAFFH8PAAMbAAUJPQ6jCgA2AQVoDAAABAAhAGkMAAADAAkAawwAAAMAKwBqDAAAAgARAOoMAAADADoAGwAECT0OowoANgEEaAwAAAMAIQBpDAAAAwAJAGsMAAABACsA6gwAAAMAOgAcAAMJ5wMHGQDDAANoDAAAAQAKAGsMAAACAAkAagwAAAIAEQAuAAQKfx8AAxsACAl0H2oQALYCABsABwnmImoQALYCABwABglSCo9WAO4AAAAA.',
No='Nordsense:BAEALgAECgEJAQAAAA==.Novebear:BAEALgAFFAIJAwABLgAFFAMJCAAKABglAA==.Novelus:BAECLgAFFH8IAAIKAAMJGCXxAwBHAQNoDAAAAwBhAGkMAAABAF0A6gwAAAQAXQAKAAMJGCXxAwBHAQNoDAAAAwBhAGkMAAABAF0A6gwAAAQAXQAuAAQKfyIAAgoACAntJJgCAD8DAAoACAntJJgCAD8DAAAA.',
Ol='Oldbronze:BAECLgAFFH8FAAIKAAMJWxVJBwDqAANoDAAAAgBHAGkMAAACADwA6gwAAAEAHwAKAAMJWxVJBwDqAANoDAAAAgBHAGkMAAACADwA6gwAAAEAHwAuAAQKfygAAgoACAluIC0IAKICAAoACAluIC0IAKICAAAA.',
On='Onenjen:BAEALgAECgYJEgAAAA==.',
['Oñ']='Oññayu:BAEALgAECgIJAgAAAA==.',
Pa='Parkercannon:BAECLgAFFH8SAAIWAAYJ+CADAQA6AgZoDAAABABeAGkMAAAEAFwAawwAAAMAUABqDAAAAwBJAGwMAAACAF4A6gwAAAIAPAAWAAYJ+CADAQA6AgZoDAAABABeAGkMAAAEAFwAawwAAAMAUABqDAAAAwBJAGwMAAACAF4A6gwAAAIAPAAuAAQKfyYAAhYACQnyI+oAANADABYACQnyI+oAANADAAAA.Patrennessy:BAEBLgAECn8eAAIGAAgJtSJaBABCAghoDAAABQBiAGkMAAAFAGAAawwAAAUAXQBqDAAABABdAGwMAAADAEUAbQwAAAIAUADqDAAABABbAG4MAAACAFwABgAICbUiWgQAQgIIaAwAAAUAYgBpDAAABQBgAGsMAAAFAF0AagwAAAQAXQBsDAAAAwBFAG0MAAACAFAA6gwAAAQAWwBuDAAAAgBcAAAA.',
Ra='Ramsama:BAEALgAECgkJBwAAAA==.Ramsdh:BAEALgAECggJCAABLgAFFAYJEQALAGceAA==.Ramsx:BAECLgAFFH8RAAMLAAYJZx67AQCVAQZoDAAABQBaAGkMAAAEAFYAawwAAAMAUQBqDAAAAQAYAGwMAAABACsA6gwAAAMAVgALAAUJtiG7AQCVAQVoDAAABQBaAGkMAAACAFYAawwAAAIAUQBqDAAAAQAYAOoMAAACAFYADgAECX8SZgIAFgEEaQwAAAIAOgBrDAAAAQA6AGwMAAABACsA6gwAAAEAHAAuAAQKfxUAAwsABglEJtkUAGsCAAsABglEJtkUAGsCAA4AAQk4JHoNAGEAAAAA.Rarelinelk:BAEALgAECgIJAgABLgAFFAUJDwAdANwjAA==.',
Re='Recursively:BAECLgAFFH8TAAQNAAcJPxOkAwDnAQdoDAAAAwBPAGkMAAADAD8AawwAAAQAQgBqDAAAAgAlAGwMAAABABUAbQwAAAEACADqDAAABQA2AA0ABgkJE6QDAOcBBmgMAAADAE8AaQwAAAIAPwBrDAAAAgAXAGoMAAABAA4AbAwAAAEAFQDqDAAAAwA2ABcABAm+D9ADAFoBBGkMAAABACwAawwAAAIAQgBtDAAAAQAIAOoMAAACACkAGAABCQAAbgUAVwABagwAAAEAJQAuAAQKfyUABA0ACQleI+8MABIDAA0ACQkvI+8MABIDABcABgkKIoAIADoCABgAAQkAANQiAGYAAAAA.Redxr:BAEALgAECgYJCgABLgAFFAUJCAAeAE4WAA==.',
Sh='Sharrq:BAECLgAFFH8HAAIfAAMJ2xZvAAALAQNoDAAAAwBJAGkMAAADAB4A6gwAAAEASAAfAAMJ2xZvAAALAQNoDAAAAwBJAGkMAAADAB4A6gwAAAEASAAuAAQKfyAAAx8ACAnCIEoAAIUCAB8ACAnCIEoAAIUCACAAAQkrCVYeADQAAAAA.',
Si='Sivvychuckle:BAEALgAECgIJAwABLgAECgcJCwADAAAAAA==.Sivvygrows:BAEALgAECgcJBwABLgAECgcJCwADAAAAAA==.Sivvyrawr:BAEALgAECgcJCwAAAA==.',
Sl='Slammybreath:BAEBLgAECn8dAAMEAAgJZxQZMQA+AQhoDAAABAAjAGkMAAAEADIAawwAAAQAQABqDAAABAArAGwMAAAEAE4AbQwAAAIAHwDqDAAABgA6AG4MAAABAC4ABAAGCcwSGTEAPgEGaAwAAAIAIwBpDAAAAgAxAGsMAAACADUAagwAAAIAKwBsDAAAAgArAOoMAAADADoABQAICdoT7CwAtAAIaAwAAAIAHwBpDAAAAgAyAGsMAAACAEAAagwAAAIAIgBsDAAAAgBOAG0MAAACAB8A6gwAAAMANQBuDAAAAQAuAAEuAAUUBgkKAAIAoQgA.',
Sp='Spicyhotwing:BAECLgAFFH8KAAICAAYJoQiBAwDOAQZoDAAAAQAKAGkMAAABAAsAawwAAAEAGwBqDAAAAgAhAGwMAAABAAUA6gwAAAQAKgACAAYJoQiBAwDOAQZoDAAAAQAKAGkMAAABAAsAawwAAAEAGwBqDAAAAgAhAGwMAAABAAUA6gwAAAQAKgAuAAQKfxQAAwIACAnrEjMUAAICAAIACAnrEjMUAAICAAUAAQl9HnA4AFUAAAAA.',
Ta='Tauntinitis:BAEALgADCgMJAwABLgAECgkJMwAPADQWAA==.',
Te='Tendeyaloran:BAEALgAECgIJAgAAAA==.',
Th='Thanala:BAECLgAFFH8OAAIBAAUJDCJqAgDGAQVoDAAABABSAGkMAAAEAGEAawwAAAIAWABqDAAAAQBLAOoMAAADAFsAAQAFCQwiagIAxgEFaAwAAAQAUgBpDAAABABhAGsMAAACAFgAagwAAAEASwDqDAAAAwBbAC4ABAp/HAACAQAICWIefBQAbgIAAQAICWIefBQAbgIAAAA=.',
Tr='Trintu:BAEALgAECggJAgABLgAFFAUJCQARAG8QAA==.',
Yo='Yoktuah:BAEBLgAFFH8FAAMBAAQJ6gO6DQD9AARoDAAAAgAAAGkMAAABABwAawwAAAEACgDqDAAAAQAAAAEABAnqA7oNAP0ABGgMAAABAAAAaQwAAAEAHABrDAAAAQAKAOoMAAABAAAAGQABCRgRlzEAUgABaAwAAAEAKwAAAA==.',
Yu='Yungdh:BAEALgAECgYJDQABLgAFFAYJFQAhAGslAA==.Yungdrood:BAECLgAFFH8VAAIhAAYJayX8AAA1AgZoDAAABQBjAGkMAAAFAGMAawwAAAQAYwBqDAAAAwBhAGwMAAABAF4A6gwAAAMAVQAhAAYJayX8AAA1AgZoDAAABQBjAGkMAAAFAGMAawwAAAQAYwBqDAAAAwBhAGwMAAABAF4A6gwAAAMAVQAuAAQKfywAAiEACAnQJkACAJ8DACEACAnQJkACAJ8DAAAA.Yungmonk:BAEALgAECgQJBAABLgAFFAYJFQAhAGslAA==.Yungwizard:BAEBLgAECn8WAAIMAAYJ2iXVOQCOAgZoDAAABABfAGkMAAAEAGIAawwAAAQAXwBqDAAAAwBhAGwMAAAEAGEA6gwAAAMAYQAMAAYJ2iXVOQCOAgZoDAAABABfAGkMAAAEAGIAawwAAAQAXwBqDAAAAwBhAGwMAAAEAGEA6gwAAAMAYQABLgAFFAYJFQAhAGslAA==.',
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
