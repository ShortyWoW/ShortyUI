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
local provider = {region='US',realm='Winterhoof',name='US',type='daily',zone=46,date='2026-05-11',data={Ae='Aeterna:BAAALgAECgQJBQAAAA==.',
Al='Albus:BAAALgADCgEJAQAAAA==.Allsmite:BAAALgADCgkJDwABLgAECgkJHgABAOYTAA==.Allure:BAABLgAECn8WAAMCAAYJGR5oDQC+AQZoDAAABABUAGkMAAAEAFEAawwAAAQATQBqDAAABABbAGwMAAACAF0A6gwAAAQAMAACAAYJGR5oDQC+AQZoDAAAAwBUAGkMAAADAFEAawwAAAMATQBqDAAABABbAGwMAAACAF0A6gwAAAIAMAADAAQJ4QuZpwDCAARoDAAAAQAiAGkMAAABABEAawwAAAEAKwDqDAAAAgAaAAAA.Almasy:BAABLgAECn8WAAIEAAgJyhrIEgBIAghoDAAAAwBAAGkMAAADAEoAawwAAAMAWgBqDAAAAwA+AGwMAAADAD4AbQwAAAEAQwDqDAAABABLAG4MAAACADIABAAICcoayBIASAIIaAwAAAMAQABpDAAAAwBKAGsMAAADAFoAagwAAAMAPgBsDAAAAwA+AG0MAAABAEMA6gwAAAQASwBuDAAAAgAyAAAA.Alyce:BAAALgADCgMJAwAAAA==.',
Am='Amadin:BAABLgAECn8xAAIFAAgJSBHPHQCpAQhoDAAABwBIAGkMAAAHAD4AawwAAAcARQBqDAAABwAqAGwMAAAHABkAbQwAAAQADQDqDAAABgAXAG4MAAAEACwABQAICUgRzx0AqQEIaAwAAAcASABpDAAABwA+AGsMAAAHAEUAagwAAAcAKgBsDAAABwAZAG0MAAAEAA0A6gwAAAYAFwBuDAAABAAsAAAA.Amoralibash:BAAALgAECgYJCwAAAA==.',
An='Anguskhan:BAAALgADCgUJCAAAAA==.Anhafel:BAABLgAECn8hAAIDAAYJtRTGTwAaAQZoDAAABwBZAGkMAAAGADEAawwAAAcAMgBqDAAABAAsAGwMAAADAB0A6gwAAAYALgADAAYJtRTGTwAaAQZoDAAABwBZAGkMAAAGADEAawwAAAcAMgBqDAAABAAsAGwMAAADAB0A6gwAAAYALgAAAA==.Anári:BAAALgADCgUJBQAAAA==.',
Ap='Apocalipze:BAAALgADCgYJCgAAAA==.',
Ar='Aragosa:BAAALgADCgcJDQAAAA==.Arcsisu:BAAALgAECggJCAAAAA==.Ardinn:BAAALgAECgQJBgAAAA==.Ares:BAAALgAECgEJAQABLgAFFAQJCwAGALkXAA==.Arileous:BAAALgAECgUJCAAAAA==.Arkeios:BAAALgADCgcJEAAAAA==.Arthan:BAAALgADCgUJBQAAAA==.',
As='Asmoodeus:BAAALgAECgEJAgABLgAECgkJIgAHAJsPAA==.Aspp:BAABLgAECn8UAAIIAAgJDg0RPgCVAQhoDAAABAAkAGkMAAADACcAawwAAAMAJwBqDAAAAQACAGwMAAACACwAbQwAAAEAFgDqDAAABQAdAG4MAAABABUACAAICQ4NET4AlQEIaAwAAAQAJABpDAAAAwAnAGsMAAADACcAagwAAAEAAgBsDAAAAgAsAG0MAAABABYA6gwAAAUAHQBuDAAAAQAVAAAA.',
Au='Augpress:BAAALgAECgcJDgAAAA==.Aureliandawn:BAAALgADCgkJCQAAAA==.',
Ba='Bald:BAAALgAECgYJBgAAAA==.Balek:BAAALgADCgcJCwAAAA==.Bambiná:BAAALgADCgMJAwAAAA==.',
Bi='Bijou:BAAALgAECgEJAQAAAA==.',
Bl='Blucifer:BAAALgAECgUJDQAAAA==.Bluedelts:BAAALgAECgYJBwAAAA==.Blutopic:BAAALgADCgUJBwAAAA==.',
Br='Briar:BAAALgAECgMJBAAAAA==.Britnysteers:BAAALgADCgUJBQAAAA==.',
Bs='Bstook:BAAALgADCgQJAgAAAA==.',
Bu='Bubblybear:BAAALgAECgUJCwAAAA==.Bucksdk:BAAALgAFFAEJAQAAAA==.Buckshotheal:BAAALgADCgYJBwABLgAFFAEJAQAJAAAAAA==.Bullshatt:BAAALgADCgYJBgAAAA==.',
['Bé']='Béifong:BAAALgAECgcJCQAAAA==.',
Ca='Cantmilkthis:BAAALgADCgIJAQAAAA==.Castiél:BAAALgADCgIJAgAAAA==.',
Ce='Celaida:BAAALgAECgYJDQABLgAECggJJQAKAPEbAA==.Cerius:BAAALgADCgEJAQAAAA==.',
Ch='Cheever:BAAALgADCgIJAgAAAA==.',
Ci='Cirednev:BAAALgADCgkJCQAAAA==.',
Cl='Clippy:BAAALgADCgEJAQAAAA==.',
Co='Colinferrell:BAAALgAECgYJCgAAAA==.',
Cr='Crawlercarl:BAAALgAECgMJAwAAAA==.',
Cu='Custard:BAAALgADCggJCgAAAA==.',
Cy='Cyrandalorr:BAABLgAECn8lAAMKAAgJ8RtIBwCKAghoDAAABgBIAGkMAAAGAFYAawwAAAUAVQBqDAAABgBCAGwMAAADAEMAbQwAAAIAKgDqDAAABgBeAG4MAAADADkACgAICfEbSAcAigIIaAwAAAUASABpDAAABABWAGsMAAADAFUAagwAAAUAQgBsDAAAAwBDAG0MAAACACoA6gwAAAUAXgBuDAAAAwA5AAsABQkRBrdDAN4ABWgMAAABABEAaQwAAAIADgBrDAAAAgAOAGoMAAABABAA6gwAAAEADwAAAA==.',
Da='Danne:BAAALgADCgYJBgABLgAECgQJCAAJAAAAAA==.Dardianil:BAAALgADCgkJEgABLgAECgYJCwAJAAAAAA==.Darkmedicine:BAAALgADCgEJAQAAAA==.Darknmagic:BAAALgAECgUJBgAAAA==.Dave:BAAALgAECggJEwABLgABCgIJAgAJAAAAAA==.',
De='Deathzdemize:BAACLgAFFH8iAAMIAAgJdyDMAACUAghoDAAABgBhAGkMAAAGAGMAawwAAAYAYgBqDAAABQBbAGwMAAACAGQAbQwAAAEAFgDqDAAABwBjAG4MAAABAD8ACAAHCXcgzAAAlAIHaAwAAAYAYQBpDAAABgBjAGsMAAAGAGIAbAwAAAIAZABtDAAAAQAWAOoMAAAHAGMAbgwAAAEAPwAMAAEJAABuFABPAAFqDAAABQBbAC4ABAp/MgAECAAJCYMl5wAA3QMACAAJCYMl5wAA3QMADAAFCdokqBAAAAIADQAECYMVWA0A2AAAAAA=.Decay:BAABLgAECn8sAAIOAAkJQx4BCwCpAgloDAAABwBfAGkMAAAGAFoAawwAAAcAXABqDAAABQBVAGwMAAAFAE4AbQwAAAQASADqDAAACABZAG4MAAABADkAbwwAAAEAKgAOAAkJQx4BCwCpAgloDAAABwBfAGkMAAAGAFoAawwAAAcAXABqDAAABQBVAGwMAAAFAE4AbQwAAAQASADqDAAACABZAG4MAAABADkAbwwAAAEAKgABLgAECgYJIQAHAPIlAA==.Demonbane:BAABLgAECn8jAAMCAAkJZRsQBQB/AgloDAAABgBJAGkMAAAFAEkAawwAAAUAPwBqDAAABAA0AGwMAAAEAFMAbQwAAAIAKgDqDAAABQBMAG4MAAADAD8AbwwAAAEAVAACAAkJZRsQBQB/AgloDAAAAwBJAGkMAAACAEkAawwAAAQAPwBqDAAAAwA0AGwMAAADAFMAbQwAAAEAKgDqDAAABABMAG4MAAADAD8AbwwAAAEAVAADAAcJWgr+VgAGAQdoDAAAAwAJAGkMAAADABMAawwAAAEAGABqDAAAAQAYAGwMAAABAC8AbQwAAAEAEgDqDAAAAQAlAAAA.',
Di='Diancie:BAAALgADCgEJAQAAAA==.Dirtpear:BAAALgAECggJEgAAAA==.',
Dr='Dragonaddon:BAAALgAECgYJBgAAAA==.Draig:BAAALgAECgUJBQAAAA==.Drakythor:BAAALgAECgUJDgAAAA==.Drold:BAAALgADCgUJBAAAAA==.Druisy:BAAALgAECgUJCAAAAA==.',
Du='Duró:BAAALgAECgYJDwABLgAECgcJDgAJAAAAAA==.',
['Dé']='Dév:BAAALgAECgEJAQAAAA==.',
El='Eleonna:BAAALgADCgUJBQAAAA==.',
En='Endymion:BAABLgAECn8YAAIFAAgJlhM9FwDhAQhoDAAABABbAGkMAAADADAAawwAAAMARQBqDAAAAwAlAGwMAAADAEAAbQwAAAEAJwDqDAAABQAmAG4MAAACAAoABQAICZYTPRcA4QEIaAwAAAQAWwBpDAAAAwAwAGsMAAADAEUAagwAAAMAJQBsDAAAAwBAAG0MAAABACcA6gwAAAUAJgBuDAAAAgAKAAAA.',
Et='Eternity:BAACLgAFFH8LAAIGAAQJuRfNFQBNAQRoDAAAAgBFAGkMAAAEAFMAawwAAAIALgDqDAAAAwAsAAYABAm5F80VAE0BBGgMAAACAEUAaQwAAAQAUwBrDAAAAgAuAOoMAAADACwALgAECn8oAAIGAAkJFCIpDADgAgAGAAkJFCIpDADgAgAAAA==.',
Ev='Evigs:BAAALgADCgMJAwAAAA==.Evilgouda:BAAALgAECgYJCgAAAA==.',
Ex='Exorcizim:BAAALgAECggJCwAAAA==.',
Fa='Facetheclaw:BAAALgAECgUJBQABLgAECgkJFAAPAFISAA==.Facetheflame:BAAALgAECgEJAQABLgAECgkJFAAPAFISAA==.Facethegem:BAABLgAECn8UAAMPAAkJUhKxMQBeAQloDAAAAgBLAGkMAAACADUAawwAAAIAEQBqDAAAAgAiAGwMAAACABAAbQwAAAIAMADqDAAABAAkAG4MAAADAD8AbwwAAAEASwAPAAYJ6xGxMQBeAQZqDAAAAQAiAGwMAAABABAAbQwAAAIAMADqDAAAAwAkAG4MAAADAD8AbwwAAAEASwAQAAYJGRJqJgA2AQZoDAAAAgA7AGkMAAACAEkAawwAAAIARwBqDAAAAQAnAGwMAAABAAcA6gwAAAEAEgAAAA==.Facethespoon:BAAALgAECgYJBwABLgAECgkJFAAPAFISAA==.Facethezoom:BAAALgADCgcJBwABLgAECgkJFAAPAFISAA==.Father:BAAALgAECgEJAQABLgAECgQJBQAJAAAAAA==.',
Fe='Felbourne:BAACLgAFFH8FAAIDAAIJvRBvTACVAAJoDAAAAgAkAOoMAAADADEAAwACCb0Qb0wAlQACaAwAAAIAJADqDAAAAwAxAC4ABAp/FwADAwAJCdgYTxQAKwIAAwAHCTkgTxQAKwIAAgAJCZcDQyoAcwEAAS4ABRQGCRMAEQD+GgA=.Feldnor:BAAALgADCgIJAgAAAA==.Felmoon:BAAALgAECgYJCAAAAA==.Felreaper:BAAALgADCggJCwAAAA==.',
Fi='Fizbar:BAABLgAECn8iAAISAAkJMAlBDgBwAQloDAAABgAnAGkMAAAFACgAawwAAAUAEABqDAAABAAZAGwMAAAEABMAbQwAAAIAFwDqDAAABAAYAG4MAAADAA8AbwwAAAEABAASAAkJMAlBDgBwAQloDAAABgAnAGkMAAAFACgAawwAAAUAEABqDAAABAAZAGwMAAAEABMAbQwAAAIAFwDqDAAABAAYAG4MAAADAA8AbwwAAAEABAAAAA==.',
Fo='Fonzo:BAAALgADCgMJAwAAAA==.',
Fr='Frozarath:BAAALgADCgcJBwAAAA==.Frozntempest:BAABLgAECn8WAAITAAgJvAbvagBKAQhoDAAABAAOAGkMAAADAAcAawwAAAMAFABqDAAAAwAHAGwMAAADACQAbQwAAAIADQDqDAAAAgAKAG4MAAACABEAEwAICbwG72oASgEIaAwAAAQADgBpDAAAAwAHAGsMAAADABQAagwAAAMABwBsDAAAAwAkAG0MAAACAA0A6gwAAAIACgBuDAAAAgARAAAA.Frozone:BAAALgADCgYJBgAAAA==.',
Fu='Furiousa:BAABLgAECn8bAAMBAAkJqxXTEAD6AQloDAAABABIAGkMAAADADoAawwAAAMAQQBqDAAAAwBFAGwMAAADAE0AbQwAAAIAFwDqDAAABQA4AG4MAAADADUAbwwAAAEAJAABAAkJSBXTEAD6AQloDAAABABIAGkMAAADADoAawwAAAMAQQBqDAAAAwBFAGwMAAADAE0AbQwAAAEADwDqDAAABQA4AG4MAAADADUAbwwAAAEAJAAUAAEJSQkwPQAlAAFtDAAAAQAXAAAA.',
Ga='Galairn:BAAALgAECgUJBQAAAA==.Garlakrond:BAAALgADCgcJBwAAAA==.Garlatha:BAABLgAECn8eAAIBAAkJ5hMLEAACAgloDAAABQA6AGkMAAAEACwAawwAAAQAKQBqDAAAAwBPAGwMAAADAD0AbQwAAAIAKADqDAAABQA6AG4MAAADAD8AbwwAAAEAJgABAAkJ5hMLEAACAgloDAAABQA6AGkMAAAEACwAawwAAAQAKQBqDAAAAwBPAGwMAAADAD0AbQwAAAIAKADqDAAABQA6AG4MAAADAD8AbwwAAAEAJgAAAA==.Gasaiyuno:BAABLgAECn8VAAMVAAcJMQZUMADSAAdoDAAABAALAGkMAAAEABYAawwAAAQAFgBqDAAAAwAbAGwMAAADABAAbQwAAAEAEADqDAAAAgAGABUABwkxBlQwANIAB2gMAAADAAsAaQwAAAQAFgBrDAAABAAWAGoMAAADABsAbAwAAAMAEABtDAAAAQAQAOoMAAABAAYAFgACCYkEWloAOwACaAwAAAEABQDqDAAAAQARAAAA.',
Ge='Geves:BAAALgAECgYJEAAAAA==.',
Gu='Gullabull:BAAALgAECgIJAgAAAA==.',
Ha='Hanki:BAAALgAECgQJBwAAAA==.Harrinarr:BAAALgAECgEJAQABLgAFFAMJBgAWAHcDAA==.',
He='Hedgehog:BAAALgAECgQJBwAAAA==.Hegony:BAAALgAECgYJBgAAAA==.Hellgar:BAABLgAECn8VAAIHAAgJVxDpSQB6AQhoDAAAAgAxAGkMAAAFAEIAawwAAAUAMQBqDAAAAQAiAGwMAAABACsAbQwAAAEAEQDqDAAABQAyAG4MAAABABEABwAICVcQ6UkAegEIaAwAAAIAMQBpDAAABQBCAGsMAAAFADEAagwAAAEAIgBsDAAAAQArAG0MAAABABEA6gwAAAUAMgBuDAAAAQARAAAA.Hexmaster:BAAALgAECgUJDQAAAA==.',
Ho='Holycoww:BAAALgAECgYJDgAAAA==.Holysquid:BAAALgADCgYJBgAAAA==.Holyyoshi:BAABLgAECn8WAAIHAAgJCRGiVgDeAQhoDAAABAA3AGkMAAADADIAawwAAAQANwBqDAAAAwA7AGwMAAACAB8AbQwAAAIAEgDqDAAAAwBIAG4MAAABABQABwAICQkRolYA3gEIaAwAAAQANwBpDAAAAwAyAGsMAAAEADcAagwAAAMAOwBsDAAAAgAfAG0MAAACABIA6gwAAAMASABuDAAAAQAUAAAA.',
Ic='Iceagentdave:BAAALgAECgMJAwAAAA==.',
Ij='Ijakee:BAAALgAECgEJAQABLgAECggJFgAEAMoaAA==.',
Il='Illbegood:BAAALgAECgEJAQAAAA==.',
Im='Impearsmoke:BAAALgADCgUJBQABLgAECggJEgAJAAAAAA==.',
Io='Io:BAAALgADCgQJBAABLgAECgEJAQAJAAAAAA==.',
Is='Isakura:BAAALgAECgcJDQAAAA==.',
It='Ithlaris:BAAALgADCgkJEAAAAA==.',
Iz='Izakura:BAAALgAECggJCgAAAA==.',
Ja='Jab:BAABLgAECn8fAAIMAAcJPBB4HQDrAAdoDAAABQBUAGkMAAAFACwAawwAAAUALQBqDAAABQA5AGwMAAAEACwAbQwAAAMAAwDqDAAABAAbAAwABwk8EHgdAOsAB2gMAAAFAFQAaQwAAAUALABrDAAABQAtAGoMAAAFADkAbAwAAAQALABtDAAAAwADAOoMAAAEABsAAAA=.Jamama:BAAALgAECgYJDQAAAA==.Jasperr:BAABLgAECn8fAAMMAAkJ2hV2HABoAQloDAAABQA6AGkMAAAEADoAawwAAAQAQABqDAAAAwAZAGwMAAADAC4AbQwAAAIADADqDAAABgBCAG4MAAADAEkAbwwAAAEAQQAMAAgJPxh2HABoAQhoDAAABAA6AGkMAAADADoAawwAAAMAQABqDAAAAgAZAGwMAAACAC4A6gwAAAUAQgBuDAAAAwBJAG8MAAABAEEACAAHCZIIJ2MALgEHaAwAAAEAEABpDAAAAQAeAGsMAAABABcAagwAAAEADwBsDAAAAQAYAG0MAAACAAwA6gwAAAEAFwAAAA==.Jaspper:BAAALgAECgUJBQABLgAECgkJHwAMANoVAA==.',
Ji='Jigsaw:BAAALgAECgYJCQAAAA==.Jinsha:BAABLgAECn8jAAIXAAcJ5iI9CABeAgdoDAAABQBhAGkMAAAFAFQAawwAAAYAXwBqDAAABQBPAGwMAAAFAFEA6gwAAAYAXwBuDAAAAwBRABcABwnmIj0IAF4CB2gMAAAFAGEAaQwAAAUAVABrDAAABgBfAGoMAAAFAE8AbAwAAAUAUQDqDAAABgBfAG4MAAADAFEAAAA=.Jinu:BAABLgAECn8UAAIDAAgJWR4WMwAuAghoDAAAAwBOAGkMAAADAFoAawwAAAIAWgBqDAAAAQBaAGwMAAACAEkAbQwAAAIAQwDqDAAABgBcAG4MAAABADIAAwAICVkeFjMALgIIaAwAAAMATgBpDAAAAwBaAGsMAAACAFoAagwAAAEAWgBsDAAAAgBJAG0MAAACAEMA6gwAAAYAXABuDAAAAQAyAAAA.Jiéqu:BAABLgAECn8aAAIYAAcJbh4bDAAPAgdoDAAABgBUAGkMAAAGAE4AawwAAAUASwBqDAAAAgBHAGwMAAABAFEAbQwAAAEAQgDqDAAABQBRABgABwluHhsMAA8CB2gMAAAGAFQAaQwAAAYATgBrDAAABQBLAGoMAAACAEcAbAwAAAEAUQBtDAAAAQBCAOoMAAAFAFEAAAA=.',
Jo='Joker:BAABLgAECn8XAAIGAAcJAQcXXwAFAQdoDAAABAAgAGkMAAAEABUAawwAAAQAEABqDAAAAwAQAGwMAAADAA4AbQwAAAIAEgDqDAAAAwAEAAYABwkBBxdfAAUBB2gMAAAEACAAaQwAAAQAFQBrDAAABAAQAGoMAAADABAAbAwAAAMADgBtDAAAAgASAOoMAAADAAQAAAA=.Jomama:BAAALgAECggJEAAAAA==.Jork:BAABLgAECn8lAAIBAAkJNR9LBQCvAgloDAAABgBYAGkMAAAGAEcAawwAAAUAYABqDAAABQBgAGwMAAAFAEYAbQwAAAIAVQDqDAAABgBYAG4MAAABAE0AbwwAAAEAPAABAAkJNR9LBQCvAgloDAAABgBYAGkMAAAGAEcAawwAAAUAYABqDAAABQBgAGwMAAAFAEYAbQwAAAIAVQDqDAAABgBYAG4MAAABAE0AbwwAAAEAPAAAAA==.',
Ju='Justmeat:BAAALgAECgEJAQAAAA==.',
Ka='Kaesong:BAAALgADCgYJBgAAAA==.Karasendreth:BAAALgADCgUJBQAAAA==.Kazera:BAAALgADCgYJBgAAAA==.',
Ke='Kelleina:BAAALgADCgEJAQAAAA==.Kematian:BAAALgADCgcJCQABLgAECgcJGgAYAG4eAA==.Kes:BAAALgAECgUJCgAAAA==.',
Ko='Korolev:BAAALgAECgUJCgABLgAFFAIJAgAJAAAAAA==.',
Kr='Kristiani:BAAALgADCgIJAgAAAA==.',
La='Lad:BAAALgAECgQJBAAAAA==.Lakmir:BAAALgAECgQJBwAAAA==.Lawbreaker:BAAALgADCgcJDAAAAA==.',
Le='Leaffy:BAAALgAECgEJAgABLgAECggJGwAPAPQZAA==.Leafygaga:BAAALgAECgYJCgAAAA==.Lehaba:BAAALgADCgcJBwAAAA==.Leora:BAAALgAECgMJBQAAAA==.',
Li='Lilthiccy:BAAALgADCgUJBQABLgAECggJEAAJAAAAAA==.',
Lo='Locii:BAAALgADCgkJEgAAAA==.Loki:BAAALgAECgIJAgAAAA==.',
Lu='Lunura:BAAALgAECgQJCAAAAA==.',
Ma='Magicmoosle:BAAALgAFFAIJAwAAAA==.Manerick:BAAALgAECgEJAQAAAA==.Marche:BAAALgAECgYJDQAAAA==.Marvin:BAAALgAECgMJBwAAAA==.',
Me='Meliôdas:BAAALgAECgEJBQAAAA==.Meseel:BAAALgADCgIJAgAAAA==.',
Mi='Mirelai:BAAALgADCgEJAQAAAA==.',
Mo='Mojin:BAAALgAECgcJBwAAAA==.Mommy:BAAALgAECgMJAwABLgAECgcJBwAJAAAAAA==.Moonspinner:BAAALgAECgMJAwAAAA==.Mooädib:BAAALgAECgIJAgAAAA==.Mossflower:BAAALgADCgQJBQAAAA==.Mourningstar:BAAALgADCgUJBQAAAA==.',
Mu='Munashe:BAAALgADCgUJBQAAAA==.',
My='Mysteer:BAAALgAECgcJDwAAAA==.Mysteia:BAABLgAECn8fAAIWAAgJWxwdCwBMAghoDAAABQBTAGkMAAAEAE4AawwAAAQANABqDAAABQBEAGwMAAAFAFcAbQwAAAIATADqDAAABQBPAG4MAAABADUAFgAICVscHQsATAIIaAwAAAUAUwBpDAAABABOAGsMAAAEADQAagwAAAUARABsDAAABQBXAG0MAAACAEwA6gwAAAUATwBuDAAAAQA1AAAA.',
['Mà']='Màkina:BAAALgAECgYJEwAAAA==.',
['Mú']='Mústang:BAAALgADCgcJBwAAAA==.',
Na='Nathanyal:BAAALgADCgIJAgAAAA==.Navy:BAAALgAECgYJDgABLgAFFAQJCwAGALkXAA==.',
Ne='Nelyssa:BAAALgADCggJFAAAAA==.Neodragoon:BAABLgAECn8VAAMHAAYJRxWxngBBAQZoDAAABAAqAGkMAAAEAE4AawwAAAQASQBqDAAAAwAuAGwMAAADADIA6gwAAAMAGwAHAAYJMhSxngBBAQZoDAAABAAqAGkMAAAEAE4AawwAAAMASQBqDAAAAQAHAGwMAAABACQA6gwAAAIAGwAZAAQJ0wcOMgCFAARrDAAAAQAHAGoMAAACAC4AbAwAAAIAMgDqDAAAAQACAAEuAAUUAwkEAAkAAAAA.Neodragoonz:BAAALgADCgYJBwABLgAFFAMJBAAJAAAAAA==.',
Ni='Nihilist:BAABLgAECn8bAAIMAAkJgx2nBgBDAgloDAAABQBhAGkMAAAEAFkAawwAAAQATgBqDAAAAwA8AGwMAAADAEAAbQwAAAEAGwDqDAAAAwBLAG4MAAADAFEAbwwAAAEAWwAMAAkJgx2nBgBDAgloDAAABQBhAGkMAAAEAFkAawwAAAQATgBqDAAAAwA8AGwMAAADAEAAbQwAAAEAGwDqDAAAAwBLAG4MAAADAFEAbwwAAAEAWwAAAA==.Nimbuss:BAAALgAECgcJDAAAAA==.Nitequilz:BAABLgAECn8mAAIPAAgJnx71CQCeAghoDAAABwBaAGkMAAAGAFYAawwAAAYAVABqDAAABQBLAGwMAAAEADoAbQwAAAEAQQDqDAAABgBVAG4MAAADAFAADwAICZ8e9QkAngIIaAwAAAcAWgBpDAAABgBWAGsMAAAGAFQAagwAAAUASwBsDAAABAA6AG0MAAABAEEA6gwAAAYAVQBuDAAAAwBQAAAA.',
Nu='Nuos:BAAALgADCggJCQAAAA==.',
Ob='Obamanationn:BAAALgADCgIJAgAAAA==.Obeejoowan:BAAALgADCgkJGwAAAA==.Obijuan:BAAALgAECgYJDAAAAA==.',
On='Onani:BAAALgAECgYJCQAAAA==.',
Os='Oswarin:BAAALgADCggJCAAAAA==.',
Ou='Ouch:BAAALgAECgYJEgAAAA==.Outcast:BAAALgAECgQJBAAAAA==.Outcastbrew:BAABLgAECn8UAAIYAAgJ+SFuBwAOAwhoDAAAAwBUAGkMAAADAGIAawwAAAMAYABqDAAAAwBYAGwMAAADAF8AbQwAAAEAVADqDAAAAwBeAG4MAAABADUAGAAICfkhbgcADgMIaAwAAAMAVABpDAAAAwBiAGsMAAADAGAAagwAAAMAWABsDAAAAwBfAG0MAAABAFQA6gwAAAMAXgBuDAAAAQA1AAAA.',
Oz='Ozonekiller:BAAALgADCgIJAgAAAA==.',
Pi='Pine:BAABLgAECn8WAAIFAAcJEA2iJwBcAQdoDAAABAAhAGkMAAADAB0AawwAAAMAIABqDAAAAwAmAGwMAAADAB0AbQwAAAEABwDqDAAABQA/AAUABwkQDaInAFwBB2gMAAAEACEAaQwAAAMAHQBrDAAAAwAgAGoMAAADACYAbAwAAAMAHQBtDAAAAQAHAOoMAAAFAD8AAAA=.',
Pl='Plateguy:BAAALgADCgQJAwAAAA==.',
Po='Poxx:BAAALgAECgQJBAABLgAFFAYJEwARAP4aAA==.',
Qu='Quigonjin:BAAALgAECgQJBgAAAA==.',
Ra='Raelynixii:BAAALgAECgQJBwAAAA==.Raksi:BAAALgADCgIJAgAAAA==.Ranker:BAAALgAECgEJAQAAAA==.Rashakas:BAAALgADCgcJCAAAAA==.',
Rh='Rhayvival:BAABLgAFFH8GAAMWAAMJdwOOHgCdAANoDAAAAgAJAGkMAAADAAgA6gwAAAEACAAWAAMJdwOOHgCdAANoDAAAAQAJAGkMAAABAAgA6gwAAAEACAAYAAIJAQj4NwBsAAJoDAAAAQAHAGkMAAACACEAAAA=.Rhayvoke:BAABLgAECn8XAAQaAAcJyxc3HQDdAQdoDAAABABMAGkMAAAEAEAAawwAAAQANwBqDAAAAwBIAGwMAAADADkA6gwAAAQAPABuDAAAAQAzABoABwmTFzcdAN0BB2gMAAAEAEwAaQwAAAMAPABrDAAABAA3AGoMAAACAEgAbAwAAAEAOQDqDAAAAwA8AG4MAAABADMAEgADCdoLcToAlgADagwAAAEAHQBsDAAAAgA2AOoMAAABAAcAGwABCRkZbDoARwABaQwAAAEAQAABLgAFFAMJBgAWAHcDAA==.',
Ri='Rills:BAAALgAECgQJBAAAAA==.Risho:BAAALgAECgMJAwAAAA==.',
Ro='Rollepolle:BAAALgAFFAIJBAABLgAFFAgJIgAIAHcgAA==.Rossini:BAAALgADCgUJBQAAAA==.',
Ru='Rush:BAAALgAECgEJAQABLgAECgQJBQAJAAAAAA==.Rushs:BAAALgADCgEJAQABLgAECgUJBwAJAAAAAA==.',
Ry='Rygaeyl:BAAALgADCgQJBAAAAA==.Ryleigh:BAABLgAECn8kAAILAAgJTRm/DgD1AQhoDAAABgBKAGkMAAAGAEgAawwAAAYANwBqDAAABQA0AGwMAAAFAEMAbQwAAAEAKgDqDAAABQBCAG4MAAACAEoACwAICU0Zvw4A9QEIaAwAAAYASgBpDAAABgBIAGsMAAAGADcAagwAAAUANABsDAAABQBDAG0MAAABACoA6gwAAAUAQgBuDAAAAgBKAAAA.Rynron:BAAALgAECgQJCQAAAA==.',
Sa='Sabeatris:BAAALgAECgYJDgAAAA==.Sabereth:BAAALgADCgMJBAAAAA==.Samraj:BAAALgAECgcJEQAAAA==.Sapheerion:BAAALgADCgcJBwABLgAECgcJDwAJAAAAAA==.',
Se='Sempiternal:BAACLgAFFH8LAAIFAAQJ/A6eFQAVAQRoDAAABAA1AGkMAAADACEAawwAAAIAHQDqDAAAAgAlAAUABAn8Dp4VABUBBGgMAAAEADUAaQwAAAMAIQBrDAAAAgAdAOoMAAACACUALgAECn8vAAIFAAkJThFSLQDPAQAFAAkJThFSLQDPAQAAAA==.',
Sh='Shadowsmite:BAABLgAECn8UAAIHAAkJzhwbEgB6AgloDAAABAA9AGkMAAADAFwAawwAAAIATABqDAAAAgBOAGwMAAACADoAbQwAAAEAUwDqDAAABABDAG4MAAABAFQAbwwAAAEAQQAHAAkJzhwbEgB6AgloDAAABAA9AGkMAAADAFwAawwAAAIATABqDAAAAgBOAGwMAAACADoAbQwAAAEAUwDqDAAABABDAG4MAAABAFQAbwwAAAEAQQAAAA==.Shaunanigans:BAAALgAECggJCgAAAA==.Shaunsdh:BAAALgAECgEJAQABLgAECggJCgAJAAAAAA==.Shaunwick:BAAALgAECgQJBAABLgAECggJCgAJAAAAAA==.Shego:BAABLgAECn8VAAQIAAgJrSG0MQBxAghoDAAABABdAGkMAAAEAF0AawwAAAIAXwBqDAAAAgBMAGwMAAACAF0A6gwAAAQAWwBuDAAAAgArAG8MAAABAFwACAAHCTogtDEAcQIHaAwAAAMAXQBpDAAABABdAGsMAAACAF8AagwAAAIATABsDAAAAQBNAOoMAAAEAFsAbgwAAAIAKwANAAEJLSQdEwBtAAFvDAAAAQBcAAwAAgkdItIvAGgAAmgMAAABAFEAbAwAAAEAXQAAAA==.Sheltered:BAABLgAECn8hAAIHAAYJ8iVTHwAdAgZoDAAABgBfAGkMAAAGAGMAawwAAAYAYgBqDAAAAgBfAOoMAAAIAF8AbgwAAAUAYAAHAAYJ8iVTHwAdAgZoDAAABgBfAGkMAAAGAGMAawwAAAYAYgBqDAAAAgBfAOoMAAAIAF8AbgwAAAUAYAAAAA==.',
Si='Sinadora:BAAALgAECgUJAgAAAA==.Sinakra:BAABLgAECn8iAAIHAAkJmw+CLQDZAQloDAAABgAqAGkMAAAFADEAawwAAAUAPwBqDAAABAAnAGwMAAAEACsAbQwAAAIAFwDqDAAABAAVAG4MAAADAC4AbwwAAAEAHQAHAAkJmw+CLQDZAQloDAAABgAqAGkMAAAFADEAawwAAAUAPwBqDAAABAAnAGwMAAAEACsAbQwAAAIAFwDqDAAABAAVAG4MAAADAC4AbwwAAAEAHQAAAA==.',
Sl='Slapdaddy:BAAALgAECgEJAQAAAA==.Slaphappy:BAAALgADCgIJAgAAAA==.Slaphapypapy:BAACLgAFFH8TAAIRAAYJ/ho3AwDJAQZoDAAABQBYAGkMAAAFAFsAawwAAAQAUwBqDAAAAQAmAG0MAAABABMA6gwAAAMAPwARAAYJ/ho3AwDJAQZoDAAABQBYAGkMAAAFAFsAawwAAAQAUwBqDAAAAQAmAG0MAAABABMA6gwAAAMAPwAuAAQKfx8AAhEACQmVJAECAJcDABEACQmVJAECAJcDAAAA.',
Sp='Spritz:BAAALgAECgYJCwAAAA==.',
St='Stampede:BAAALgADCggJGgAAAA==.Starbursts:BAAALgADCgIJAgAAAA==.Starshots:BAAALgAECgUJBQAAAA==.Stepdruid:BAAALgAECgQJBAAAAA==.Stookums:BAAALgADCgMJAwAAAA==.Stormyred:BAAALgADCgUJBQAAAA==.Straya:BAABLgAECn8aAAIPAAgJeBJeHwDNAQhoDAAABABYAGkMAAADABYAawwAAAMAOQBqDAAAAwArAGwMAAADADkAbQwAAAEAGADqDAAABwAjAG4MAAACADAADwAICXgSXh8AzQEIaAwAAAQAWABpDAAAAwAWAGsMAAADADkAagwAAAMAKwBsDAAAAwA5AG0MAAABABgA6gwAAAcAIwBuDAAAAgAwAAAA.',
Su='Subito:BAAALgADCgUJBQAAAA==.',
Ta='Tahirrah:BAABLgAECn8YAAIGAAgJXhWJKQC6AQhoDAAABAA7AGkMAAADAEkAawwAAAMAKQBqDAAAAwAvAGwMAAADAEAAbQwAAAEAEQDqDAAABQBHAG4MAAACADYABgAICV4ViSkAugEIaAwAAAQAOwBpDAAAAwBJAGsMAAADACkAagwAAAMALwBsDAAAAwBAAG0MAAABABEA6gwAAAUARwBuDAAAAgA2AAAA.Talindra:BAABLgAECn8VAAIMAAgJaQb3HADwAAhoDAAAAwARAGkMAAACABMAawwAAAMAIwBqDAAAAwAOAGwMAAADAAcAbQwAAAEADADqDAAABAAMAG4MAAACAAoADAAICWkG9xwA8AAIaAwAAAMAEQBpDAAAAgATAGsMAAADACMAagwAAAMADgBsDAAAAwAHAG0MAAABAAwA6gwAAAQADABuDAAAAgAKAAAA.Tanis:BAAALgAECgQJBQAAAA==.',
Te='Temperånce:BAABLgAECn8wAAMEAAkJ7Ax7MwBgAQloDAAABwA8AGkMAAAHADcAawwAAAcAHQBqDAAABgAZAGwMAAAGADsAbQwAAAQAEQDqDAAABgAiAG4MAAAEAAcAbwwAAAEACAAEAAkJ7Ax7MwBgAQloDAAABgA8AGkMAAAGADcAawwAAAYAHQBqDAAABQAZAGwMAAAFADsAbQwAAAMAEQDqDAAABQAiAG4MAAADAAcAbwwAAAEACAAcAAgJKgkpDQBaAQhoDAAAAQAHAGkMAAABAB0AawwAAAEALABqDAAAAQAiAGwMAAABABYAbQwAAAEAFgDqDAAAAQAQAG4MAAABABQAAAA=.Terrarium:BAAALgAECgQJCAAAAA==.',
Th='Thekingelvis:BAAALgAECgUJBwAAAA==.Thinnblood:BAAALgAECgMJAwAAAA==.Thratos:BAAALgADCgEJAgAAAA==.Thumpers:BAAALgADCgYJEQAAAA==.',
Ti='Tino:BAABLgAECn8oAAMFAAgJfh78EwBzAghoDAAABwBcAGkMAAAGAE0AawwAAAYAWgBqDAAABgBFAGwMAAAEAFIAbQwAAAIAMQDqDAAABwBgAG4MAAACAEIABQAICX4e/BMAcwIIaAwAAAYAXABpDAAABQBNAGsMAAAFAFoAagwAAAUARQBsDAAABABSAG0MAAACADEA6gwAAAYAYABuDAAAAgBCAAcABQkOC2eUANkABWgMAAABACEAaQwAAAEAJQBrDAAAAQAXAGoMAAABABcA6gwAAAEAEwAAAA==.',
Tm='Tmnt:BAAALgAECgcJEAAAAA==.',
To='Toastergeist:BAAALgADCgcJBwAAAA==.Toothgrinder:BAABLgAECn8XAAQQAAgJug/aKAApAQhoDAAABAAmAGkMAAAEAD0AawwAAAQAMgBqDAAAAwApAGwMAAABACwAbQwAAAEADgDqDAAABQAhAG4MAAABACgAEAAHCb0P2igAKQEHaAwAAAIAJgBpDAAAAwA9AGsMAAADADIAagwAAAIAKQBsDAAAAQAsAG0MAAABAA4A6gwAAAQAIQAPAAMJvxpCTADoAANoDAAAAQA1AGkMAAABAD8A6gwAAAEAVwAdAAQJgQpmGwBrAARoDAAAAQAYAGsMAAABAA8AagwAAAEADgBuDAAAAQAoAAAA.',
Tr='Trickortreat:BAAALgADCgEJAQAAAA==.Trundle:BAAALgAECgcJEAAAAA==.',
Ts='Tsilihin:BAAALgAECgEJAQAAAA==.Tsuquisitor:BAAALgAECgQJCAABLgAFFAIJBgAWAA0eAA==.Tsurenity:BAACLgAFFH8GAAIWAAIJDR6sDgCyAAJoDAAABABPAGkMAAACAEkAFgACCQ0erA4AsgACaAwAAAQATwBpDAAAAgBJAC4ABAp/GQACFgAICb4iMQQALAMAFgAICb4iMQQALAMAAAA=.',
Ty='Tylenis:BAAALgADCgQJBAAAAA==.',
['Tõ']='Tõrúkmåktö:BAAALgADCgIJAgAAAA==.',
['Tø']='Tøwmater:BAAALgAECgkJBwABLgAECggJIAAWAFILAA==.',
Va='Valerus:BAAALgAECgQJCAAAAA==.Vareesa:BAAALgADCgcJBwABLgAFFAgJHAAWAMAYAA==.Varr:BAAALgAECgMJAwAAAA==.Vayeda:BAABLgAECn8kAAITAAkJ7SJKBQAsAwloDAAABgBbAGkMAAAFAFAAawwAAAUAWgBqDAAABABSAGwMAAAEAGEAbQwAAAIAWgDqDAAABgBdAG4MAAADAFgAbwwAAAEAUQATAAkJ7SJKBQAsAwloDAAABgBbAGkMAAAFAFAAawwAAAUAWgBqDAAABABSAGwMAAAEAGEAbQwAAAIAWgDqDAAABgBdAG4MAAADAFgAbwwAAAEAUQAAAA==.',
Vi='Vicky:BAAALgAECgQJBAABLgAFFAMJBAAJAAAAAA==.',
We='Weeddragon:BAAALgAFFAIJAgAAAA==.',
Wh='Whatnow:BAAALgAECgkJAQAAAA==.',
Wi='Widow:BAAALgAECgEJAQAAAA==.',
Xe='Xetz:BAAALgAECgcJDQAAAA==.Xezar:BAACLgAFFH8MAAQLAAUJRwjEDADeAAVoDAAAAgATAGkMAAAEACUAawwAAAIAEwBqDAAAAgBRAOoMAAACAAgACwAECUcIxAwA3gAEaAwAAAIAEwBpDAAAAwAlAGsMAAACABMA6gwAAAEACAAeAAEJkRdhHgBUAAFqDAAAAgA8AAoAAgnYBTQpAFAAAmkMAAABAAUA6gwAAAEAGAAuAAQKfyEABAsACQkLGy8PAJECAAsACQkLGy8PAJECAB4ABwnrHJkWACcCAAoAAwmXH8kyAAwBAAAA.',
Xs='Xsoul:BAAALgADCgUJBQAAAA==.',
Ya='Yanray:BAABLgAECn8lAAMTAAgJDg23UwCAAQhoDAAABQAkAGkMAAAEAC8AawwAAAUAIQBqDAAABAAfAGwMAAAGADMAbQwAAAQABwDqDAAABgAmAG4MAAADABIAEwAICQ4Nt1MAgAEIaAwAAAQAJABpDAAAAwAvAGsMAAAEACEAagwAAAQAHwBsDAAABgAzAG0MAAAEAAcA6gwAAAUAJgBuDAAAAwASAB8ABAmnA2gVAHEABGgMAAABAAUAaQwAAAEAHABrDAAAAQABAOoMAAABAAEAAAA=.',
Yo='Yoursalad:BAAALgADCgQJAgAAAA==.',
Yu='Yuuka:BAABLgAECn8dAAIKAAgJGxMzFgCeAQhoDAAABQBJAGkMAAAFADgAawwAAAUAKABqDAAAAgAdAGwMAAADADUAbQwAAAIABgDqDAAABABLAG4MAAADADkACgAICRsTMxYAngEIaAwAAAUASQBpDAAABQA4AGsMAAAFACgAagwAAAIAHQBsDAAAAwA1AG0MAAACAAYA6gwAAAQASwBuDAAAAwA5AAAA.',
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
