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

local lookup = {'Warrior-Fury','DemonHunter-Havoc','DemonHunter-Devourer','Druid-Restoration','Paladin-Holy','Hunter-BeastMastery','Paladin-Retribution','DeathKnight-Unholy','Unknown-Unknown','Priest-Discipline','Priest-Shadow','DeathKnight-Blood','DeathKnight-Frost','Warlock-Demonology','Shaman-Restoration','Shaman-Elemental','Rogue-Subtlety','Evoker-Preservation','Mage-Frost','Warrior-Protection','Monk-Windwalker','Monk-Mistweaver','Druid-Balance','Monk-Brewmaster','Paladin-Protection','Evoker-Augmentation','Evoker-Devastation','Druid-Feral','Shaman-Enhancement','Priest-Holy','Mage-Arcane',}
local provider = {region='US',realm='Winterhoof',name='US',type='daily',zone=46,date='2026-05-12',data={Ae='Aeterna:BAAALgAECgQJBQAAAA==.',
Al='Albus:BAAALgADCgEJAQAAAA==.Allsmite:BAAALgADCgkJDwABLgAECgkJHgABAOYTAA==.Allure:BAABLgAECn8WAAMCAAYJGR7FDQC9AQZoDAAABABUAGkMAAAEAFEAawwAAAQATQBqDAAABABbAGwMAAACAF0A6gwAAAQAMAACAAYJGR7FDQC9AQZoDAAAAwBUAGkMAAADAFEAawwAAAMATQBqDAAABABbAGwMAAACAF0A6gwAAAIAMAADAAQJ4QucpwDCAARoDAAAAQAiAGkMAAABABEAawwAAAEAKwDqDAAAAgAaAAAA.Almasy:BAABLgAECn8WAAIEAAgJyhovEwBIAghoDAAAAwBAAGkMAAADAEoAawwAAAMAWgBqDAAAAwA+AGwMAAADAD4AbQwAAAEAQwDqDAAABABLAG4MAAACADIABAAICcoaLxMASAIIaAwAAAMAQABpDAAAAwBKAGsMAAADAFoAagwAAAMAPgBsDAAAAwA+AG0MAAABAEMA6gwAAAQASwBuDAAAAgAyAAAA.Alyce:BAAALgADCgMJAwAAAA==.',
Am='Amadin:BAABLgAECn8xAAIFAAgJSBFpHgCoAQhoDAAABwBIAGkMAAAHAD4AawwAAAcARQBqDAAABwAqAGwMAAAHABkAbQwAAAQADQDqDAAABgAXAG4MAAAEACwABQAICUgRaR4AqAEIaAwAAAcASABpDAAABwA+AGsMAAAHAEUAagwAAAcAKgBsDAAABwAZAG0MAAAEAA0A6gwAAAYAFwBuDAAABAAsAAAA.Amoralibash:BAAALgAECgYJCwAAAA==.',
An='Anguskhan:BAAALgADCgUJCAAAAA==.Anhafel:BAABLgAECn8hAAIDAAYJtRQSUQAaAQZoDAAABwBZAGkMAAAGADEAawwAAAcAMgBqDAAABAAsAGwMAAADAB0A6gwAAAYALgADAAYJtRQSUQAaAQZoDAAABwBZAGkMAAAGADEAawwAAAcAMgBqDAAABAAsAGwMAAADAB0A6gwAAAYALgAAAA==.Anári:BAAALgADCgUJBQAAAA==.',
Ap='Apocalipze:BAAALgADCgYJCgAAAA==.',
Ar='Aragosa:BAAALgADCgcJDQAAAA==.Arcsisu:BAAALgAECggJCAAAAA==.Ardinn:BAAALgAECgQJBgAAAA==.Ares:BAAALgAECgEJAQABLgAFFAQJCwAGALkXAA==.Arileous:BAAALgAECgUJCAAAAA==.Arkeios:BAAALgADCgcJEAAAAA==.Arthan:BAAALgADCgUJBQAAAA==.',
As='Asmoodeus:BAAALgAECgEJAgABLgAECgkJIgAHAJsPAA==.Aspp:BAABLgAECn8UAAIIAAgJDg1FPwCVAQhoDAAABAAkAGkMAAADACcAawwAAAMAJwBqDAAAAQACAGwMAAACACwAbQwAAAEAFgDqDAAABQAdAG4MAAABABUACAAICQ4NRT8AlQEIaAwAAAQAJABpDAAAAwAnAGsMAAADACcAagwAAAEAAgBsDAAAAgAsAG0MAAABABYA6gwAAAUAHQBuDAAAAQAVAAAA.',
Au='Augpress:BAAALgAECgcJDgAAAA==.Aureliandawn:BAAALgADCgkJCQAAAA==.',
Ba='Bald:BAAALgAECgYJBgAAAA==.Balek:BAAALgADCgcJCwAAAA==.Bambiná:BAAALgADCgMJAwAAAA==.',
Bi='Bijou:BAAALgAECgEJAQAAAA==.',
Bl='Blind:BAAALgADCgEJAQAAAA==.Blucifer:BAAALgAECgUJDQAAAA==.Bluedelts:BAAALgAECgYJBwAAAA==.Blutopic:BAAALgADCgUJBwAAAA==.',
Br='Briar:BAAALgAECgMJBAAAAA==.Britnysteers:BAAALgADCgUJBQAAAA==.',
Bs='Bstook:BAAALgADCgQJAgAAAA==.',
Bu='Bubblybear:BAAALgAECgUJCwAAAA==.Bucksdk:BAAALgAFFAEJAQAAAA==.Buckshotheal:BAAALgADCgYJBwABLgAFFAEJAQAJAAAAAA==.Bullshatt:BAAALgADCgYJBgAAAA==.',
['Bé']='Béifong:BAAALgAECgcJCQAAAA==.',
Ca='Cantmilkthis:BAAALgADCgIJAQAAAA==.Castiél:BAAALgADCgIJAgAAAA==.',
Ce='Celaida:BAAALgAECgYJDQABLgAECggJJQAKAO4bAA==.Cerius:BAAALgADCgEJAQAAAA==.',
Ch='Cheever:BAAALgADCgIJAgAAAA==.',
Ci='Cirednev:BAAALgADCgkJCQAAAA==.',
Cl='Clippy:BAAALgADCgEJAQAAAA==.',
Co='Colinferrell:BAAALgAECgYJCgAAAA==.',
Cr='Crawlercarl:BAAALgAECgMJAwAAAA==.',
Cu='Custard:BAAALgADCggJCgAAAA==.',
Cy='Cyrandalorr:BAABLgAECn8lAAMKAAgJ7hu3BgCeAghoDAAABgBIAGkMAAAGAFYAawwAAAUAVQBqDAAABgBCAGwMAAADAEMAbQwAAAIAKgDqDAAABgBeAG4MAAADADgACgAICe4btwYAngIIaAwAAAUASABpDAAABABWAGsMAAADAFUAagwAAAUAQgBsDAAAAwBDAG0MAAACACoA6gwAAAUAXgBuDAAAAwA4AAsABQkRBrpDAN4ABWgMAAABABEAaQwAAAIADgBrDAAAAgAOAGoMAAABABAA6gwAAAEADwAAAA==.',
Da='Danne:BAAALgADCgYJBgABLgAECgQJCAAJAAAAAA==.Dardianil:BAAALgADCgkJEgABLgAECgYJCwAJAAAAAA==.Darkmedicine:BAAALgADCgEJAQAAAA==.Darknmagic:BAAALgAECgUJBgAAAA==.Dave:BAAALgAECggJEwABLgABCgIJAgAJAAAAAA==.',
De='Deathzdemize:BAACLgAFFH8iAAMIAAgJdyD7AACTAghoDAAABgBhAGkMAAAGAGMAawwAAAYAYgBqDAAABQBbAGwMAAACAGQAbQwAAAEAFgDqDAAABwBjAG4MAAABAD8ACAAHCXcg+wAAkwIHaAwAAAYAYQBpDAAABgBjAGsMAAAGAGIAbAwAAAIAZABtDAAAAQAWAOoMAAAHAGMAbgwAAAEAPwAMAAEJAAC/KQAAAAFqDAAABQBbAC4ABAp/NQAECAAJCYUl5wAA3QMACAAJCYUl5wAA3QMADAAFCdokqBAAAAIADQAECYMVWA0A2AAAAAA=.Decay:BAABLgAECn8sAAIOAAkJQx5pCwCpAgloDAAABwBfAGkMAAAGAFoAawwAAAcAXABqDAAABQBVAGwMAAAFAE4AbQwAAAQASADqDAAACABZAG4MAAABADkAbwwAAAEAKgAOAAkJQx5pCwCpAgloDAAABwBfAGkMAAAGAFoAawwAAAcAXABqDAAABQBVAGwMAAAFAE4AbQwAAAQASADqDAAACABZAG4MAAABADkAbwwAAAEAKgABLgAECgYJIQAHAPIlAA==.Demonbane:BAABLgAECn8jAAMCAAkJZRs8BQB+AgloDAAABgBJAGkMAAAFAEkAawwAAAUAPwBqDAAABAA0AGwMAAAEAFMAbQwAAAIAKgDqDAAABQBMAG4MAAADAD8AbwwAAAEAVAACAAkJZRs8BQB+AgloDAAAAwBJAGkMAAACAEkAawwAAAQAPwBqDAAAAwA0AGwMAAADAFMAbQwAAAEAKgDqDAAABABMAG4MAAADAD8AbwwAAAEAVAADAAcJWgp0WAAGAQdoDAAAAwAJAGkMAAADABMAawwAAAEAGABqDAAAAQAYAGwMAAABAC8AbQwAAAEAEgDqDAAAAQAlAAAA.',
Di='Diancie:BAAALgADCgEJAQAAAA==.Dirtpear:BAAALgAECggJEgAAAA==.',
Dr='Dragonaddon:BAAALgAECgYJBgAAAA==.Draig:BAAALgAECgUJBQAAAA==.Drakythor:BAAALgAECgUJDgAAAA==.Drold:BAAALgADCgUJBAAAAA==.Druisy:BAAALgAECgUJCAAAAA==.',
Du='Duró:BAAALgAECgYJDwABLgAECgcJDgAJAAAAAA==.',
['Dé']='Dév:BAAALgAECgEJAQAAAA==.',
El='Eleonna:BAAALgADCgUJBQAAAA==.',
En='Endymion:BAABLgAECn8YAAIFAAgJlhPSFwDgAQhoDAAABABbAGkMAAADADAAawwAAAMARQBqDAAAAwAlAGwMAAADAEAAbQwAAAEAJwDqDAAABQAmAG4MAAACAAoABQAICZYT0hcA4AEIaAwAAAQAWwBpDAAAAwAwAGsMAAADAEUAagwAAAMAJQBsDAAAAwBAAG0MAAABACcA6gwAAAUAJgBuDAAAAgAKAAAA.',
Et='Eternity:BAACLgAFFH8LAAIGAAQJuRfwFgBKAQRoDAAAAgBFAGkMAAAEAFMAawwAAAIALgDqDAAAAwAsAAYABAm5F/AWAEoBBGgMAAACAEUAaQwAAAQAUwBrDAAAAgAuAOoMAAADACwALgAECn8oAAIGAAkJFCIrDADgAgAGAAkJFCIrDADgAgAAAA==.',
Ev='Evigs:BAAALgADCgMJAwAAAA==.Evilgouda:BAAALgAECgYJCgAAAA==.',
Ex='Exorcizim:BAAALgAECggJCwAAAA==.',
Fa='Facetheclaw:BAAALgAECgUJBQABLgAECgkJFAAPAFISAA==.Facetheflame:BAAALgAECgEJAQABLgAECgkJFAAPAFISAA==.Facethegem:BAABLgAECn8UAAMPAAkJUhK0MgBeAQloDAAAAgBLAGkMAAACADUAawwAAAIAEQBqDAAAAgAiAGwMAAACABAAbQwAAAIAMADqDAAABAAkAG4MAAADAD8AbwwAAAEASwAPAAYJ6xG0MgBeAQZqDAAAAQAiAGwMAAABABAAbQwAAAIAMADqDAAAAwAkAG4MAAADAD8AbwwAAAEASwAQAAYJGRIpJwA2AQZoDAAAAgA7AGkMAAACAEkAawwAAAIARwBqDAAAAQAnAGwMAAABAAcA6gwAAAEAEgAAAA==.Facethespoon:BAAALgAECgYJBwABLgAECgkJFAAPAFISAA==.Facethezoom:BAAALgADCgcJBwABLgAECgkJFAAPAFISAA==.Father:BAAALgAECgEJAQABLgAECgQJBQAJAAAAAA==.',
Fe='Felbourne:BAACLgAFFH8FAAIDAAIJvRAMTgCVAAJoDAAAAgAkAOoMAAADADEAAwACCb0QDE4AlQACaAwAAAIAJADqDAAAAwAxAC4ABAp/FwADAwAJCdgY3BQAKwIAAwAHCTkg3BQAKwIAAgAJCZcDQyoAcwEAAS4ABRQGCRMAEQD+GgA=.Feldnor:BAAALgADCgIJAgAAAA==.Felmoon:BAAALgAECgYJCAAAAA==.Felreaper:BAAALgADCggJCwAAAA==.',
Fi='Fizbar:BAABLgAECn8iAAISAAkJMAl5DgBwAQloDAAABgAnAGkMAAAFACgAawwAAAUAEABqDAAABAAZAGwMAAAEABMAbQwAAAIAFwDqDAAABAAYAG4MAAADAA8AbwwAAAEABAASAAkJMAl5DgBwAQloDAAABgAnAGkMAAAFACgAawwAAAUAEABqDAAABAAZAGwMAAAEABMAbQwAAAIAFwDqDAAABAAYAG4MAAADAA8AbwwAAAEABAAAAA==.',
Fo='Fonzo:BAAALgADCgMJAwAAAA==.',
Fr='Frozarath:BAAALgADCgcJBwAAAA==.Frozntempest:BAABLgAECn8WAAITAAgJvAaQbABKAQhoDAAABAAOAGkMAAADAAcAawwAAAMAFABqDAAAAwAHAGwMAAADACQAbQwAAAIADQDqDAAAAgAKAG4MAAACABEAEwAICbwGkGwASgEIaAwAAAQADgBpDAAAAwAHAGsMAAADABQAagwAAAMABwBsDAAAAwAkAG0MAAACAA0A6gwAAAIACgBuDAAAAgARAAAA.Frozone:BAAALgADCgYJBgAAAA==.',
Fu='Furiousa:BAABLgAECn8bAAMBAAkJqxVuEQD4AQloDAAABABIAGkMAAADADoAawwAAAMAQQBqDAAAAwBFAGwMAAADAE0AbQwAAAIAFwDqDAAABQA4AG4MAAADADUAbwwAAAEAJAABAAkJSBVuEQD4AQloDAAABABIAGkMAAADADoAawwAAAMAQQBqDAAAAwBFAGwMAAADAE0AbQwAAAEADwDqDAAABQA4AG4MAAADADUAbwwAAAEAJAAUAAEJSQm/PQAlAAFtDAAAAQAXAAAA.',
Ga='Galairn:BAAALgAECgUJBQAAAA==.Garlakrond:BAAALgADCgcJBwAAAA==.Garlatha:BAABLgAECn8eAAIBAAkJ5hOuEAAAAgloDAAABQA6AGkMAAAEACwAawwAAAQAKQBqDAAAAwBPAGwMAAADAD0AbQwAAAIAKADqDAAABQA6AG4MAAADAD8AbwwAAAEAJgABAAkJ5hOuEAAAAgloDAAABQA6AGkMAAAEACwAawwAAAQAKQBqDAAAAwBPAGwMAAADAD0AbQwAAAIAKADqDAAABQA6AG4MAAADAD8AbwwAAAEAJgAAAA==.Gasaiyuno:BAABLgAECn8VAAMVAAcJMQY4MQDSAAdoDAAABAALAGkMAAAEABYAawwAAAQAFgBqDAAAAwAbAGwMAAADABAAbQwAAAEAEADqDAAAAgAGABUABwkxBjgxANIAB2gMAAADAAsAaQwAAAQAFgBrDAAABAAWAGoMAAADABsAbAwAAAMAEABtDAAAAQAQAOoMAAABAAYAFgACCYkEz1wAOwACaAwAAAEABQDqDAAAAQARAAAA.',
Ge='Geves:BAAALgAECgYJEAAAAA==.',
Gu='Gullabull:BAAALgAECgIJAgAAAA==.',
Ha='Hanki:BAAALgAECgQJBwAAAA==.Harrinarr:BAAALgAECgEJAQABLgAFFAMJBgAWAHcDAA==.',
He='Hedgehog:BAAALgAECgQJBwAAAA==.Hegony:BAAALgAECgYJBgAAAA==.Hellgar:BAABLgAECn8VAAIHAAgJVxB8SwB5AQhoDAAAAgAxAGkMAAAFAEIAawwAAAUAMQBqDAAAAQAiAGwMAAABACsAbQwAAAEAEQDqDAAABQAyAG4MAAABABEABwAICVcQfEsAeQEIaAwAAAIAMQBpDAAABQBCAGsMAAAFADEAagwAAAEAIgBsDAAAAQArAG0MAAABABEA6gwAAAUAMgBuDAAAAQARAAAA.Hexmaster:BAAALgAECgUJDQAAAA==.',
Ho='Holycoww:BAAALgAECgYJDgAAAA==.Holysquid:BAAALgADCgYJBgAAAA==.Holyyoshi:BAABLgAECn8WAAIHAAgJCRGiVgDeAQhoDAAABAA3AGkMAAADADIAawwAAAQANwBqDAAAAwA7AGwMAAACAB8AbQwAAAIAEgDqDAAAAwBIAG4MAAABABQABwAICQkRolYA3gEIaAwAAAQANwBpDAAAAwAyAGsMAAAEADcAagwAAAMAOwBsDAAAAgAfAG0MAAACABIA6gwAAAMASABuDAAAAQAUAAAA.',
Ic='Iceagentdave:BAAALgAECgMJAwAAAA==.',
Ij='Ijakee:BAAALgAECgEJAQABLgAECggJFgAEAMoaAA==.',
Il='Illbegood:BAAALgAECgEJAQAAAA==.',
Im='Impearsmoke:BAAALgADCgUJBQABLgAECggJEgAJAAAAAA==.',
Io='Io:BAAALgADCgQJBAABLgAECgEJAQAJAAAAAA==.',
Is='Isakura:BAAALgAECgcJDQAAAA==.',
It='Ithlaris:BAAALgADCgkJEAAAAA==.',
Iz='Izakura:BAAALgAECggJCgAAAA==.',
Ja='Jab:BAACLgAFFH8HAAIMAAQJRQJ8GgCHAARoDAAAAQADAGkMAAABAAIAagwAAAMADgDqDAAAAgAKAAwABAlFAnwaAIcABGgMAAABAAMAaQwAAAEAAgBqDAAAAwAOAOoMAAACAAoALgAECn8fAAIMAAcJPBDmHQDrAAAMAAcJPBDmHQDrAAAAAA==.Jamama:BAAALgAECgYJDQAAAA==.Jasperr:BAABLgAECn8fAAMMAAkJ2hV4HABoAQloDAAABQA6AGkMAAAEADoAawwAAAQAQABqDAAAAwAZAGwMAAADAC4AbQwAAAIADADqDAAABgBCAG4MAAADAEkAbwwAAAEAQQAMAAgJPxh4HABoAQhoDAAABAA6AGkMAAADADoAawwAAAMAQABqDAAAAgAZAGwMAAACAC4A6gwAAAUAQgBuDAAAAwBJAG8MAAABAEEACAAHCZII8GQALgEHaAwAAAEAEABpDAAAAQAeAGsMAAABABcAagwAAAEADwBsDAAAAQAYAG0MAAACAAwA6gwAAAEAFwAAAA==.Jaspper:BAAALgAECgUJBQABLgAECgkJHwAMANoVAA==.',
Ji='Jigsaw:BAAALgAECgYJCQAAAA==.Jinsha:BAABLgAECn8kAAIXAAgJYiLGBAC7AghoDAAABQBhAGkMAAAFAFQAawwAAAYAXwBqDAAABQBPAGwMAAAFAFEAbQwAAAEAUADqDAAABgBfAG4MAAADAFEAFwAICWIixgQAuwIIaAwAAAUAYQBpDAAABQBUAGsMAAAGAF8AagwAAAUATwBsDAAABQBRAG0MAAABAFAA6gwAAAYAXwBuDAAAAwBRAAAA.Jinu:BAABLgAECn8VAAIDAAgJWR4ZMwAuAghoDAAAAwBOAGkMAAADAFoAawwAAAIAWgBqDAAAAgBaAGwMAAACAEkAbQwAAAIAQwDqDAAABgBcAG4MAAABADIAAwAICVkeGTMALgIIaAwAAAMATgBpDAAAAwBaAGsMAAACAFoAagwAAAIAWgBsDAAAAgBJAG0MAAACAEMA6gwAAAYAXABuDAAAAQAyAAAA.Jiéqu:BAABLgAECn8aAAIYAAcJbx5fDAAPAgdoDAAABgBUAGkMAAAGAE4AawwAAAUASwBqDAAAAgBHAGwMAAABAFEAbQwAAAEAQgDqDAAABQBRABgABwlvHl8MAA8CB2gMAAAGAFQAaQwAAAYATgBrDAAABQBLAGoMAAACAEcAbAwAAAEAUQBtDAAAAQBCAOoMAAAFAFEAAAA=.',
Jo='Joker:BAABLgAECn8XAAIGAAcJAQfNYAAEAQdoDAAABAAgAGkMAAAEABUAawwAAAQAEABqDAAAAwAQAGwMAAADAA4AbQwAAAIAEgDqDAAAAwAEAAYABwkBB81gAAQBB2gMAAAEACAAaQwAAAQAFQBrDAAABAAQAGoMAAADABAAbAwAAAMADgBtDAAAAgASAOoMAAADAAQAAAA=.Jomama:BAAALgAECggJEAAAAA==.Jork:BAABLgAECn8lAAIBAAkJNR+VBQCtAgloDAAABgBYAGkMAAAGAEcAawwAAAUAYABqDAAABQBgAGwMAAAFAEYAbQwAAAIAVQDqDAAABgBYAG4MAAABAE0AbwwAAAEAPAABAAkJNR+VBQCtAgloDAAABgBYAGkMAAAGAEcAawwAAAUAYABqDAAABQBgAGwMAAAFAEYAbQwAAAIAVQDqDAAABgBYAG4MAAABAE0AbwwAAAEAPAAAAA==.',
Ju='Justmeat:BAAALgAECgEJAQAAAA==.',
Ka='Kaesong:BAAALgADCgYJBgAAAA==.Karasendreth:BAAALgADCgUJBQAAAA==.Kazera:BAAALgADCgYJBgAAAA==.',
Ke='Kelleina:BAAALgADCgEJAQAAAA==.Kematian:BAAALgADCgcJCQABLgAECgcJGgAYAG8eAA==.Kes:BAAALgAECgUJCgAAAA==.',
Ko='Korolev:BAAALgAECgUJCgABLgAFFAIJAgAJAAAAAA==.',
Kr='Kristiani:BAAALgADCgIJAgAAAA==.',
La='Lad:BAAALgAECgQJBgAAAA==.Lakmir:BAAALgAECgQJBwAAAA==.Lawbreaker:BAAALgADCgcJDAAAAA==.',
Le='Leaffy:BAAALgAECgEJAgABLgAECggJGwAPAPQZAA==.Leafygaga:BAAALgAECgYJCgAAAA==.Lehaba:BAAALgADCgcJBwAAAA==.Leora:BAAALgAECgMJBQAAAA==.',
Li='Lilthiccy:BAAALgADCgUJBQABLgAECggJEAAJAAAAAA==.',
Lo='Locii:BAAALgADCgkJEgAAAA==.Loki:BAAALgAECgIJAgAAAA==.',
Lu='Lunura:BAAALgAECgQJCAAAAA==.',
Ma='Magicmoosle:BAAALgAFFAIJAwAAAA==.Manerick:BAAALgAECgEJAQAAAA==.Marche:BAAALgAECgYJDQAAAA==.Marvin:BAAALgAECgMJBwAAAA==.',
Me='Meliôdas:BAAALgAECgEJBQAAAA==.Meseel:BAAALgADCgIJAgAAAA==.',
Mi='Mirelai:BAAALgADCgEJAQAAAA==.',
Mo='Mojin:BAAALgAECgcJBwAAAA==.Mommy:BAAALgAECgMJAwABLgAECgcJBwAJAAAAAA==.Moonspinner:BAAALgAECgMJAwAAAA==.Mooädib:BAAALgAECgIJAgAAAA==.Mossflower:BAAALgADCgQJBQAAAA==.Mourningstar:BAAALgADCgUJBQAAAA==.',
Mu='Munashe:BAAALgADCgUJBQAAAA==.',
My='Mysteer:BAAALgAECgcJDwAAAA==.Mysteia:BAABLgAECn8fAAIWAAgJWxx7CwBMAghoDAAABQBTAGkMAAAEAE4AawwAAAQANABqDAAABQBEAGwMAAAFAFcAbQwAAAIATADqDAAABQBPAG4MAAABADUAFgAICVscewsATAIIaAwAAAUAUwBpDAAABABOAGsMAAAEADQAagwAAAUARABsDAAABQBXAG0MAAACAEwA6gwAAAUATwBuDAAAAQA1AAAA.',
['Mà']='Màkina:BAAALgAECgYJEwAAAA==.',
['Mú']='Mústang:BAAALgADCgcJBwAAAA==.',
Na='Nathanyal:BAAALgADCgIJAgAAAA==.Navy:BAAALgAECgYJDgABLgAFFAQJCwAGALkXAA==.',
Ne='Nelyssa:BAAALgADCggJFAAAAA==.Neodragoon:BAABLgAECn8VAAMHAAYJRxWyngBBAQZoDAAABAAqAGkMAAAEAE4AawwAAAQASQBqDAAAAwAuAGwMAAADADIA6gwAAAMAGwAHAAYJMhSyngBBAQZoDAAABAAqAGkMAAAEAE4AawwAAAMASQBqDAAAAQAHAGwMAAABACQA6gwAAAIAGwAZAAQJ0wcOMgCFAARrDAAAAQAHAGoMAAACAC4AbAwAAAIAMgDqDAAAAQACAAEuAAUUAwkFABoA3AMA.Neodragoonz:BAAALgADCgYJBwABLgAFFAMJBQAaANwDAA==.',
Ni='Nihilist:BAABLgAECn8bAAIMAAkJgx3cBgBCAgloDAAABQBhAGkMAAAEAFkAawwAAAQATgBqDAAAAwA8AGwMAAADAEAAbQwAAAEAGwDqDAAAAwBLAG4MAAADAFEAbwwAAAEAWwAMAAkJgx3cBgBCAgloDAAABQBhAGkMAAAEAFkAawwAAAQATgBqDAAAAwA8AGwMAAADAEAAbQwAAAEAGwDqDAAAAwBLAG4MAAADAFEAbwwAAAEAWwAAAA==.Nimbuss:BAAALgAECgcJDAAAAA==.Nitequilz:BAABLgAECn8mAAIPAAgJnx5NCgCeAghoDAAABwBaAGkMAAAGAFYAawwAAAYAVABqDAAABQBLAGwMAAAEADoAbQwAAAEAQQDqDAAABgBVAG4MAAADAFAADwAICZ8eTQoAngIIaAwAAAcAWgBpDAAABgBWAGsMAAAGAFQAagwAAAUASwBsDAAABAA6AG0MAAABAEEA6gwAAAYAVQBuDAAAAwBQAAAA.',
Nu='Nuos:BAAALgADCggJCQAAAA==.',
Ob='Obamanationn:BAAALgADCgIJAgAAAA==.Obeejoowan:BAAALgADCgkJGwAAAA==.Obijuan:BAAALgAECgYJDAAAAA==.',
On='Onani:BAAALgAECgYJCQAAAA==.',
Os='Oswarin:BAAALgADCggJCAAAAA==.',
Ou='Ouch:BAAALgAECgYJEgAAAA==.Outcast:BAAALgAECgYJCQAAAA==.Outcastbrew:BAABLgAECn8UAAIYAAgJ+SFuBwAOAwhoDAAAAwBUAGkMAAADAGIAawwAAAMAYABqDAAAAwBYAGwMAAADAF8AbQwAAAEAVADqDAAAAwBeAG4MAAABADUAGAAICfkhbgcADgMIaAwAAAMAVABpDAAAAwBiAGsMAAADAGAAagwAAAMAWABsDAAAAwBfAG0MAAABAFQA6gwAAAMAXgBuDAAAAQA1AAAA.',
Oz='Ozonekiller:BAAALgADCgIJAgAAAA==.',
Pi='Pine:BAABLgAECn8WAAIFAAcJEA1cKABcAQdoDAAABAAhAGkMAAADAB0AawwAAAMAIABqDAAAAwAmAGwMAAADAB0AbQwAAAEABwDqDAAABQA/AAUABwkQDVwoAFwBB2gMAAAEACEAaQwAAAMAHQBrDAAAAwAgAGoMAAADACYAbAwAAAMAHQBtDAAAAQAHAOoMAAAFAD8AAAA=.',
Pl='Plateguy:BAAALgADCgQJAwAAAA==.',
Po='Poxx:BAAALgAFFAIJAgABLgAFFAYJEwARAP4aAA==.',
Qu='Quigonjin:BAAALgAECgQJBgAAAA==.',
Ra='Raelynixii:BAAALgAECgQJBwAAAA==.Raksi:BAAALgADCgIJAgAAAA==.Ranker:BAAALgAECgQJBAAAAA==.Rashakas:BAAALgADCgcJCAAAAA==.',
Rh='Rhayvival:BAABLgAFFH8GAAMWAAMJdwN/HwCdAANoDAAAAgAJAGkMAAADAAgA6gwAAAEACAAWAAMJdwN/HwCdAANoDAAAAQAJAGkMAAABAAgA6gwAAAEACAAYAAIJAQgDOQBsAAJoDAAAAQAHAGkMAAACACEAAAA=.Rhayvoke:BAABLgAECn8XAAQaAAcJyxc8HQDdAQdoDAAABABMAGkMAAAEAEAAawwAAAQANwBqDAAAAwBIAGwMAAADADkA6gwAAAQAPABuDAAAAQAzABoABwmTFzwdAN0BB2gMAAAEAEwAaQwAAAMAPABrDAAABAA3AGoMAAACAEgAbAwAAAEAOQDqDAAAAwA8AG4MAAABADMAEgADCdoLdToAlgADagwAAAEAHQBsDAAAAgA2AOoMAAABAAcAGwABCRkZbToARwABaQwAAAEAQAABLgAFFAMJBgAWAHcDAA==.',
Ri='Rills:BAAALgAECgQJBAAAAA==.Risho:BAAALgAECgMJAwAAAA==.',
Ro='Rollepolle:BAAALgAFFAIJBAABLgAFFAgJIgAIAHcgAA==.Rossini:BAAALgADCgUJBQAAAA==.',
Ru='Rush:BAAALgAECgEJAQABLgAECgQJBQAJAAAAAA==.Rushs:BAAALgADCgEJAQABLgAECgUJBwAJAAAAAA==.',
Ry='Rygaeyl:BAAALgADCgQJBAAAAA==.Ryleigh:BAABLgAECn8kAAILAAgJTRkZDwD0AQhoDAAABgBKAGkMAAAGAEgAawwAAAYANwBqDAAABQA0AGwMAAAFAEMAbQwAAAEAKgDqDAAABQBCAG4MAAACAEoACwAICU0ZGQ8A9AEIaAwAAAYASgBpDAAABgBIAGsMAAAGADcAagwAAAUANABsDAAABQBDAG0MAAABACoA6gwAAAUAQgBuDAAAAgBKAAAA.Rynron:BAAALgAECgQJCQAAAA==.',
Sa='Sabeatris:BAAALgAECgYJDgAAAA==.Sabereth:BAAALgADCgMJBAAAAA==.Samraj:BAAALgAECgcJEQAAAA==.Sapheerion:BAAALgADCgcJBwABLgAECgcJDwAJAAAAAA==.',
Se='Sempiternal:BAACLgAFFH8LAAIFAAQJ/A6OFgAOAQRoDAAABAA1AGkMAAADACEAawwAAAIAHQDqDAAAAgAlAAUABAn8Do4WAA4BBGgMAAAEADUAaQwAAAMAIQBrDAAAAgAdAOoMAAACACUALgAECn8vAAIFAAkJThFSLQDPAQAFAAkJThFSLQDPAQAAAA==.',
Sh='Shadowsmite:BAABLgAECn8UAAIHAAkJzhzEEgB5AgloDAAABAA9AGkMAAADAFwAawwAAAIATABqDAAAAgBOAGwMAAACADoAbQwAAAEAUwDqDAAABABDAG4MAAABAFQAbwwAAAEAQQAHAAkJzhzEEgB5AgloDAAABAA9AGkMAAADAFwAawwAAAIATABqDAAAAgBOAGwMAAACADoAbQwAAAEAUwDqDAAABABDAG4MAAABAFQAbwwAAAEAQQAAAA==.Shaunanigans:BAAALgAECggJCgAAAA==.Shaunsdh:BAAALgAECgEJAQABLgAECggJCgAJAAAAAA==.Shaunwick:BAAALgAECgQJBAABLgAECggJCgAJAAAAAA==.Shego:BAABLgAECn8ZAAQIAAgJHCK4MQBxAghoDAAABABdAGkMAAAFAGEAawwAAAMAXwBqDAAAAwBZAGwMAAADAGAA6gwAAAQAWwBuDAAAAgArAG8MAAABAFwACAAHCToguDEAcQIHaAwAAAMAXQBpDAAABABdAGsMAAACAF8AagwAAAIATABsDAAAAQBNAOoMAAAEAFsAbgwAAAIAKwANAAUJRCXcEwBsAAVpDAAAAQBhAGsMAAABAF4AagwAAAEAWQBsDAAAAQBgAG8MAAABAFwADAACCR0igDAAaAACaAwAAAEAUQBsDAAAAQBdAAAA.Sheltered:BAABLgAECn8hAAIHAAYJ8iU4IAAdAgZoDAAABgBfAGkMAAAGAGMAawwAAAYAYgBqDAAAAgBfAOoMAAAIAF8AbgwAAAUAYAAHAAYJ8iU4IAAdAgZoDAAABgBfAGkMAAAGAGMAawwAAAYAYgBqDAAAAgBfAOoMAAAIAF8AbgwAAAUAYAAAAA==.',
Si='Sinadora:BAAALgAECgUJAgAAAA==.Sinakra:BAABLgAECn8iAAIHAAkJmw+XLgDZAQloDAAABgAqAGkMAAAFADEAawwAAAUAPwBqDAAABAAnAGwMAAAEACsAbQwAAAIAFwDqDAAABAAVAG4MAAADAC4AbwwAAAEAHQAHAAkJmw+XLgDZAQloDAAABgAqAGkMAAAFADEAawwAAAUAPwBqDAAABAAnAGwMAAAEACsAbQwAAAIAFwDqDAAABAAVAG4MAAADAC4AbwwAAAEAHQAAAA==.',
Sl='Slapdaddy:BAAALgAECgEJAQAAAA==.Slaphappy:BAAALgADCgIJAgAAAA==.Slaphapypapy:BAACLgAFFH8TAAIRAAYJ/ho5AwDJAQZoDAAABQBYAGkMAAAFAFsAawwAAAQAUwBqDAAAAQAmAG0MAAABABMA6gwAAAMAPwARAAYJ/ho5AwDJAQZoDAAABQBYAGkMAAAFAFsAawwAAAQAUwBqDAAAAQAmAG0MAAABABMA6gwAAAMAPwAuAAQKfx8AAhEACQmVJAACAJcDABEACQmVJAACAJcDAAAA.',
Sp='Spritz:BAAALgAECgYJCwAAAA==.',
St='Stampede:BAAALgADCggJHQAAAA==.Starbursts:BAAALgADCgIJAgAAAA==.Starshots:BAAALgAECgUJBQAAAA==.Stepdruid:BAAALgAECgQJBAAAAA==.Stookums:BAAALgADCgMJAwAAAA==.Stormyred:BAAALgADCgUJBQAAAA==.Straya:BAABLgAECn8aAAIPAAgJeBIEIADNAQhoDAAABABYAGkMAAADABYAawwAAAMAOQBqDAAAAwArAGwMAAADADkAbQwAAAEAGADqDAAABwAjAG4MAAACADAADwAICXgSBCAAzQEIaAwAAAQAWABpDAAAAwAWAGsMAAADADkAagwAAAMAKwBsDAAAAwA5AG0MAAABABgA6gwAAAcAIwBuDAAAAgAwAAAA.',
Su='Subito:BAAALgADCgUJBQAAAA==.',
Ta='Tahirrah:BAABLgAECn8YAAIGAAgJXhWfKgC5AQhoDAAABAA7AGkMAAADAEkAawwAAAMAKQBqDAAAAwAvAGwMAAADAEAAbQwAAAEAEQDqDAAABQBHAG4MAAACADYABgAICV4VnyoAuQEIaAwAAAQAOwBpDAAAAwBJAGsMAAADACkAagwAAAMALwBsDAAAAwBAAG0MAAABABEA6gwAAAUARwBuDAAAAgA2AAAA.Talindra:BAABLgAECn8VAAIMAAgJaQZgHQDwAAhoDAAAAwARAGkMAAACABMAawwAAAMAIwBqDAAAAwAOAGwMAAADAAcAbQwAAAEADADqDAAABAAMAG4MAAACAAoADAAICWkGYB0A8AAIaAwAAAMAEQBpDAAAAgATAGsMAAADACMAagwAAAMADgBsDAAAAwAHAG0MAAABAAwA6gwAAAQADABuDAAAAgAKAAAA.Tanis:BAAALgAECgQJBQAAAA==.',
Te='Temperånce:BAABLgAECn8wAAMEAAkJ7AxMNABgAQloDAAABwA8AGkMAAAHADcAawwAAAcAHQBqDAAABgAZAGwMAAAGADsAbQwAAAQAEQDqDAAABgAiAG4MAAAEAAcAbwwAAAEACAAEAAkJ7AxMNABgAQloDAAABgA8AGkMAAAGADcAawwAAAYAHQBqDAAABQAZAGwMAAAFADsAbQwAAAMAEQDqDAAABQAiAG4MAAADAAcAbwwAAAEACAAcAAgJKglyDQBaAQhoDAAAAQAHAGkMAAABAB0AawwAAAEALABqDAAAAQAiAGwMAAABABYAbQwAAAEAFgDqDAAAAQAQAG4MAAABABQAAAA=.Terrarium:BAAALgAECgQJCAAAAA==.',
Th='Thekingelvis:BAAALgAECgUJBwAAAA==.Thinnblood:BAAALgAECgMJAwAAAA==.Thratos:BAAALgADCgEJAgAAAA==.Thumpers:BAAALgADCgYJEQAAAA==.',
Ti='Tino:BAABLgAECn8oAAMFAAgJfh78EwBzAghoDAAABwBcAGkMAAAGAE0AawwAAAYAWgBqDAAABgBFAGwMAAAEAFIAbQwAAAIAMQDqDAAABwBgAG4MAAACAEIABQAICX4e/BMAcwIIaAwAAAYAXABpDAAABQBNAGsMAAAFAFoAagwAAAUARQBsDAAABABSAG0MAAACADEA6gwAAAYAYABuDAAAAgBCAAcABQkOC/mWANkABWgMAAABACEAaQwAAAEAJQBrDAAAAQAXAGoMAAABABcA6gwAAAEAEwAAAA==.',
Tm='Tmnt:BAAALgAECgcJEAAAAA==.',
To='Toastergeist:BAAALgADCgcJBwAAAA==.Toothgrinder:BAABLgAECn8XAAQQAAgJug+YKQApAQhoDAAABAAmAGkMAAAEAD0AawwAAAQAMgBqDAAAAwApAGwMAAABACwAbQwAAAEADgDqDAAABQAhAG4MAAABACgAEAAHCb0PmCkAKQEHaAwAAAIAJgBpDAAAAwA9AGsMAAADADIAagwAAAIAKQBsDAAAAQAsAG0MAAABAA4A6gwAAAQAIQAPAAMJvxrMTQDoAANoDAAAAQA1AGkMAAABAD8A6gwAAAEAVwAdAAQJgQr3GwBrAARoDAAAAQAYAGsMAAABAA8AagwAAAEADgBuDAAAAQAoAAAA.',
Tr='Trickortreat:BAAALgADCgEJAQAAAA==.Trundle:BAAALgAECgcJEAAAAA==.',
Ts='Tsilihin:BAAALgAECgEJAQAAAA==.Tsuquisitor:BAAALgAECgQJCAABLgAFFAIJBgAWAA0eAA==.Tsurenity:BAACLgAFFH8GAAIWAAIJDR6uDgCyAAJoDAAABABPAGkMAAACAEkAFgACCQ0erg4AsgACaAwAAAQATwBpDAAAAgBJAC4ABAp/GQACFgAICb4iMQQALAMAFgAICb4iMQQALAMAAAA=.',
Ty='Tylenis:BAAALgADCgQJBAAAAA==.',
['Tõ']='Tõrúkmåktö:BAAALgADCgIJAgAAAA==.',
['Tø']='Tøwmater:BAAALgAECgkJCAABLgAECggJIAAWAFILAA==.',
Va='Valerus:BAAALgAECgQJCAAAAA==.Vareesa:BAAALgADCgcJBwABLgAFFAgJHAAWAMAYAA==.Varr:BAAALgAECgMJAwAAAA==.Vayeda:BAABLgAECn8kAAITAAkJ7SKCBQArAwloDAAABgBbAGkMAAAFAFAAawwAAAUAWgBqDAAABABSAGwMAAAEAGEAbQwAAAIAWgDqDAAABgBdAG4MAAADAFgAbwwAAAEAUQATAAkJ7SKCBQArAwloDAAABgBbAGkMAAAFAFAAawwAAAUAWgBqDAAABABSAGwMAAAEAGEAbQwAAAIAWgDqDAAABgBdAG4MAAADAFgAbwwAAAEAUQAAAA==.',
Vi='Vicky:BAAALgAECgQJBAABLgAFFAMJBQAaANwDAA==.',
We='Weeddragon:BAAALgAFFAIJAgAAAA==.',
Wh='Whatnow:BAAALgAECgkJAQAAAA==.',
Wi='Widow:BAAALgAECgEJAQAAAA==.',
Xe='Xetz:BAAALgAECgcJDQAAAA==.Xezar:BAACLgAFFH8MAAQLAAUJRwjHDADeAAVoDAAAAgATAGkMAAAEACUAawwAAAIAEwBqDAAAAgBRAOoMAAACAAgACwAECUcIxwwA3gAEaAwAAAIAEwBpDAAAAwAlAGsMAAACABMA6gwAAAEACAAeAAEJkRcBHwBUAAFqDAAAAgA8AAoAAgnYBQ8qAFAAAmkMAAABAAUA6gwAAAEAGAAuAAQKfyMABAsACQkLGzEPAJECAAsACQkLGzEPAJECAB4ABwnrHJoWACcCAAoAAwmXH8oyAAwBAAAA.',
Xs='Xsoul:BAAALgADCgUJBQAAAA==.',
Ya='Yanray:BAABLgAECn8lAAMTAAgJDg0dVQCAAQhoDAAABQAkAGkMAAAEAC8AawwAAAUAIQBqDAAABAAfAGwMAAAGADMAbQwAAAQABwDqDAAABgAmAG4MAAADABIAEwAICQ4NHVUAgAEIaAwAAAQAJABpDAAAAwAvAGsMAAAEACEAagwAAAQAHwBsDAAABgAzAG0MAAAEAAcA6gwAAAUAJgBuDAAAAwASAB8ABAmnA2gVAHEABGgMAAABAAUAaQwAAAEAHABrDAAAAQABAOoMAAABAAEAAAA=.',
Yo='Yoursalad:BAAALgADCgQJAgAAAA==.',
Yu='Yuuka:BAABLgAECn8dAAIKAAgJGxOnFgCeAQhoDAAABQBJAGkMAAAFADgAawwAAAUAKABqDAAAAgAdAGwMAAADADUAbQwAAAIABgDqDAAABABLAG4MAAADADkACgAICRsTpxYAngEIaAwAAAUASQBpDAAABQA4AGsMAAAFACgAagwAAAIAHQBsDAAAAwA1AG0MAAACAAYA6gwAAAQASwBuDAAAAwA5AAAA.',
Za='Zarigar:BAAALgADCgUJBQAAAA==.Zawn:BAAALgAECgYJCAAAAA==.',
Ze='Zeroh:BAAALgAECgYJDQAAAA==.',
Zi='Zigzagger:BAAALgAECgQJBgAAAA==.',
Zn='Zna:BAAALgAECgUJCAAAAA==.',
['Øø']='Øø:BAAALgAECgYJEAAAAA==.',
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
