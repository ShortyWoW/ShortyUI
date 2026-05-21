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

local lookup = {'Warrior-Fury','Rogue-Subtlety','Rogue-Assassination','Druid-Feral','Druid-Guardian','Druid-Balance','Druid-Restoration','DeathKnight-Frost','DemonHunter-Devourer','Monk-Windwalker','Evoker-Devastation','Evoker-Augmentation','Unknown-Unknown','Monk-Mistweaver','Monk-Brewmaster','Priest-Shadow','Priest-Discipline','Priest-Holy','Hunter-BeastMastery','Paladin-Retribution','DeathKnight-Unholy','Warrior-Protection','DeathKnight-Blood','Mage-Frost','Shaman-Elemental','Shaman-Enhancement','Shaman-Restoration','Warlock-Demonology','Mage-Arcane','Mage-Fire',}
local provider = {region='US',realm='Kalecgos',name='US',type='daily',zone=46,date='2026-05-20',data={Aa='Aamon:BAAALgADCgUJBQAAAA==.Aarius:BAAALgAECgQJBAAAAA==.',
Ae='Aerius:BAAALgADCgYJBAAAAA==.',
Am='Amen:BAAALgADCgEJAQAAAA==.',
Ao='Ao:BAAALgAECgQJCwAAAA==.',
Au='Augmentation:BAAALgAECgIJAwAAAA==.Aurumursi:BAAALgADCgcJBwAAAA==.',
Av='Aviandraka:BAAALgADCgEJAQAAAA==.',
Ba='Baeroch:BAAALgADCgEJAQAAAA==.Barlartwo:BAAALgAECgUJBQAAAA==.Bazthrax:BAAALgAECgIJAgAAAA==.Baztinel:BAAALgADCgkJCQAAAA==.Bazty:BAAALgAECgYJDgAAAA==.',
Be='Belthazaar:BAAALgAECgUJCAAAAA==.',
Bl='Blade:BAACLgAFFH8KAAIBAAMJzh2rHwD9AANoDAAABQBXAGkMAAADAE4A6gwAAAIAPgABAAMJzh2rHwD9AANoDAAABQBXAGkMAAADAE4A6gwAAAIAPgAuAAQKfx0AAgEACAnWIpISADACAAEACAnWIpISADACAAAA.Blarneystone:BAAALgAECgUJDgAAAA==.',
Bo='Bootybsneaks:BAACLgAFFH8bAAICAAUJCiNEBwCgAQVoDAAABwBaAGkMAAAHAGAAawwAAAUASgBqDAAAAwBFAOoMAAAFAGEAAgAFCQojRAcAoAEFaAwAAAcAWgBpDAAABwBgAGsMAAAFAEoAagwAAAMARQDqDAAABQBhAC4ABAp/NQADAgAJCSEjwwIAAwMAAgAJCSEjwwIAAwMAAwABCXwWOB8AOwAAAAA=.',
Br='Bramble:BAAALgADCgIJAgAAAA==.Brynhild:BAABLgAECn8ZAAIEAAYJ5AvRGwDiAAZoDAAABQApAGkMAAAFABgAawwAAAQAFgBqDAAABAAdAGwMAAAEAB8A6gwAAAMAIAAEAAYJ5AvRGwDiAAZoDAAABQApAGkMAAAFABgAawwAAAQAFgBqDAAABAAdAGwMAAAEAB8A6gwAAAMAIAAAAA==.',
Bu='Bullfist:BAAALgAECgYJBgABLgAECggJJAAFABscAA==.Bullievit:BAACLgAFFH8FAAIGAAMJFxAFJADFAANoDAAAAgA8AGsMAAABAAYA6gwAAAIAOAAGAAMJFxAFJADFAANoDAAAAgA8AGsMAAABAAYA6gwAAAIAOAAuAAQKfyQAAwYACQlXHa4UAPgBAAYACQlXHa4UAPgBAAcABAktBTyeAI4AAAAA.',
Ca='Calssara:BAAALgADCgEJAQAAAA==.',
Ce='Cerealkìller:BAABLgAECn8rAAIIAAkJURAZCAC7AQloDAAABgArAGkMAAAGACUAawwAAAUAKgBqDAAABgAtAGwMAAAFACcAbQwAAAQAIADqDAAABgAgAG4MAAAEAFgAbwwAAAEAEgAIAAkJURAZCAC7AQloDAAABgArAGkMAAAGACUAawwAAAUAKgBqDAAABgAtAGwMAAAFACcAbQwAAAQAIADqDAAABgAgAG4MAAAEAFgAbwwAAAEAEgAAAA==.',
Ch='Chaostheory:BAAALgAECgEJAgABLgAFFAMJCgABAM4dAA==.Chaozz:BAABLgAECn8YAAIJAAYJXyIQPwD4AQZoDAAABABjAGkMAAAEAFUAawwAAAQAWABqDAAABABIAGwMAAAEAEoA6gwAAAQAWwAJAAYJXyIQPwD4AQZoDAAABABjAGkMAAAEAFUAawwAAAQAWABqDAAABABIAGwMAAAEAEoA6gwAAAQAWwAAAA==.Chichi:BAAALgAECgIJAgAAAA==.Chistery:BAAALgAECgUJBgAAAA==.Chunly:BAAALgAECgYJEQAAAA==.',
Cl='Clovicta:BAAALgADCgQJBAAAAA==.',
Cm='Cmoobones:BAAALgAECggJDwAAAA==.',
Co='Colokush:BAAALgADCgcJBwAAAA==.Constantine:BAAALgADCgEJAQABLgAECgcJHQAKAD4kAA==.',
Cr='Crisgard:BAAALgAECgQJDgAAAA==.Cronos:BAABLgAECn8lAAMLAAgJaRI5DAAmAQhoDAAABgA2AGkMAAAFADkAawwAAAYANwBqDAAABQA2AGwMAAAFADUAbQwAAAIAIgDqDAAABwBEAG4MAAABAAcADAAHCWQR1ywAVQEHaAwAAAQANgBpDAAABQA5AGsMAAAGADcAagwAAAQANgBsDAAABAAoAG0MAAABABUA6gwAAAYAJgALAAYJcRA5DAAmAQZoDAAAAgAuAGoMAAABACAAbAwAAAEANQBtDAAAAQAiAOoMAAABAEQAbgwAAAEABwAAAA==.Crysalus:BAAALgAECgEJAQAAAA==.',
Da='Dacian:BAAALgAECggJDwAAAA==.Darallyn:BAAALgAECgYJDgAAAA==.Davik:BAAALgAECgQJEwAAAA==.',
De='Deathcharger:BAAALgADCgYJDwAAAA==.Demonicaxe:BAAALgADCgkJCQAAAA==.Devïl:BAAALgAECgMJAgAAAA==.',
Di='Dingbat:BAAALgADCgEJAQAAAA==.',
Do='Dog:BAAALgAECggJBgAAAA==.Dollfie:BAAALgAECgIJAgAAAA==.Doser:BAAALgAECgYJEgAAAA==.',
Dr='Dracarsynimz:BAAALgAECgkJMQABLgAFFAQJEwAMAEILAQ==.Dracene:BAAALgAECgUJDgAAAA==.Dragosa:BAAALgADCgMJAwABLgAECgMJBAANAAAAAA==.',
Du='Duf:BAAALgAECgEJAwAAAA==.',
Dy='Dynasty:BAAALgAECgQJBAAAAA==.',
Eb='Eblazed:BAAALgADCgMJAwAAAA==.',
Fe='Feraldruid:BAAALgAECgMJAwAAAA==.',
Fi='Fisten:BAAALgAECgYJBgAAAA==.',
Fl='Flixs:BAAALgAECgEJAQABLgAECgQJCgANAAAAAA==.',
Fo='Foxcraft:BAABLgAECn8aAAMOAAkJvB4OBQAUAwloDAAAAwBfAGkMAAADAFwAawwAAAMAXgBqDAAABQBZAGwMAAADAEgAbQwAAAEAPQDqDAAABQBTAG4MAAACADUAbwwAAAEAQQAOAAkJvB4OBQAUAwloDAAAAwBfAGkMAAADAFwAawwAAAMAXgBqDAAABQBZAGwMAAADAEgAbQwAAAEAPQDqDAAABQBTAG4MAAABADUAbwwAAAEAQQAPAAEJZQrEhQA7AAFuDAAAAQAaAAAA.',
Fr='Friëren:BAAALgAECgQJBQAAAA==.',
Ga='Gamera:BAAALgAECgUJCgAAAA==.Gangstabarny:BAAALgAECgEJAQAAAA==.Gankadin:BAAALgAFFAEJAQAAAA==.',
Gb='Gb:BAACLgAFFH8NAAMQAAQJ8hoiFwD+AARoDAAABQBZAGkMAAAEAC0AawwAAAIATgDqDAAAAgA+ABAAAwmwGSIXAP4AA2gMAAAEAFkAaQwAAAIALQDqDAAAAgA+ABEAAwnJD8YhANoAA2gMAAABACQAaQwAAAIAKQBrDAAAAgArAC4ABAp/JQAEEAAICeUcAw4AowIAEAAICeUcAw4AowIAEQAICdsbDAsAhQIAEgACCTkIMnEAYgAAAAA=.',
Gi='Giffca:BAAALgAECgYJDgAAAA==.',
Gr='Groobel:BAAALgAECgEJAwAAAA==.Groobs:BAAALgAECgEJBwAAAA==.',
Ho='Holycow:BAAALgAECgUJBQAAAA==.',
Hu='Humanmatt:BAAALgAECgQJBgAAAA==.',
Hy='Hydra:BAAALgAECgkJBAAAAA==.',
Ic='Icewolff:BAAALgAECgUJBgAAAA==.',
Ik='Ikinokoru:BAACLgAFFH8FAAITAAMJ3yOmKgAoAQNoDAAAAgBfAGkMAAABAFgA6gwAAAIAWwATAAMJ3yOmKgAoAQNoDAAAAgBfAGkMAAABAFgA6gwAAAIAWwAuAAQKfzoAAhMACAmRJRMIAPECABMACAmRJRMIAPECAAAA.',
In='Inyànga:BAAALgAECgMJAwAAAA==.',
Je='Jeffren:BAAALgAECgQJCgAAAA==.',
Ji='Jinsho:BAAALgAECggJCAAAAA==.',
Jy='Jyve:BAAALgADCgcJBwABLgAECgkJIgATAHwbAA==.',
Ka='Kalal:BAAALgADCgYJBwAAAA==.',
Ke='Keg:BAABLgAECn8dAAIKAAcJPiQcEAB+AgdoDAAABQBgAGkMAAAFAGEAawwAAAUAYgBqDAAABABfAGwMAAAEAFgAbQwAAAEAVwDqDAAABQBYAAoABwk+JBwQAH4CB2gMAAAFAGAAaQwAAAUAYQBrDAAABQBiAGoMAAAEAF8AbAwAAAQAWABtDAAAAQBXAOoMAAAFAFgAAAA=.Keygunmonk:BAAALgADCgcJBwAAAA==.',
Ko='Kovowolf:BAACLgAFFH8NAAIHAAQJwBAOIAAZAQRoDAAABQA/AGkMAAAFADwAawwAAAIAFgDqDAAAAQAZAAcABAnAEA4gABkBBGgMAAAFAD8AaQwAAAUAPABrDAAAAgAWAOoMAAABABkALgAECn8qAAIHAAkJDx9fCgDuAgAHAAkJDx9fCgDuAgAAAA==.',
Kr='Krazedwolf:BAACLgAFFH8FAAIUAAMJPBPMQgDxAANoDAAAAgBUAGkMAAACACMAawwAAAEAGgAUAAMJPBPMQgDxAANoDAAAAgBUAGkMAAACACMAawwAAAEAGgAuAAQKfygAAhQACQlHITEOANQCABQACQlHITEOANQCAAAA.',
Kv='Kvn:BAAALgAECgUJBgAAAA==.',
Le='Lehran:BAAALgAECgIJAwAAAA==.Lemonator:BAAALgAECgQJBQAAAA==.Lemynaid:BAAALgAECgYJDgAAAA==.',
Li='Linsay:BAACLgAFFH8fAAIQAAcJuyAPAQBvAgdoDAAABgBjAGkMAAAFAGIAawwAAAUAXABqDAAABQBjAGwMAAACAFcAbQwAAAEAGADqDAAABwBkABAABwm7IA8BAG8CB2gMAAAGAGMAaQwAAAUAYgBrDAAABQBcAGoMAAAFAGMAbAwAAAIAVwBtDAAAAQAYAOoMAAAHAGQALgAECn83AAIQAAkJJCZAAQDAAwAQAAkJJCZAAQDAAwAAAA==.',
Lo='Lokagdai:BAAALgAECgEJAgAAAA==.Lotieos:BAABLgAECn8ZAAIVAAYJMQ6UkwAUAQZoDAAABgAkAGkMAAAGAC4AawwAAAUAIABqDAAAAQAOAGwMAAABAAwA6gwAAAYANgAVAAYJMQ6UkwAUAQZoDAAABgAkAGkMAAAGAC4AawwAAAUAIABqDAAAAQAOAGwMAAABAAwA6gwAAAYANgAAAA==.Lovelypwr:BAABLgAECn86AAIQAAkJdhN5FAD3AQloDAAACgA9AGkMAAAHADwAawwAAAYAJgBqDAAABQAiAGwMAAAHADsAbQwAAAUAKQDqDAAACgBEAG4MAAAFABgAbwwAAAMAKwAQAAkJdhN5FAD3AQloDAAACgA9AGkMAAAHADwAawwAAAYAJgBqDAAABQAiAGwMAAAHADsAbQwAAAUAKQDqDAAACgBEAG4MAAAFABgAbwwAAAMAKwAAAA==.',
Ma='Mannera:BAAALgAFFAIJAgAAAA==.Manzio:BAAALgADCgQJBAAAAA==.Marcus:BAAALgAECgMJBAAAAA==.Matheris:BAABLgAECn8YAAIWAAkJYCJ6AwDYAgloDAAABQBfAGkMAAADAF4AawwAAAMAXgBqDAAAAgBRAGwMAAACAFsAbQwAAAIAQADqDAAABABhAG4MAAACAFIAbwwAAAEAUgAWAAkJYCJ6AwDYAgloDAAABQBfAGkMAAADAF4AawwAAAMAXgBqDAAAAgBRAGwMAAACAFsAbQwAAAIAQADqDAAABABhAG4MAAACAFIAbwwAAAEAUgAAAA==.Mawiyah:BAAALgAECgcJBwAAAA==.Max:BAAALgAECgYJDAABLgAECgkJLAAXAEwaAA==.',
Me='Melarac:BAAALgAECgYJEAAAAA==.',
Mi='Minibow:BAAALgAECgEJAQAAAA==.Minimagic:BAACLgAFFH8QAAIYAAQJNRx4MABeAQRoDAAABQBOAGkMAAAEAEwAawwAAAIATQDqDAAABQA4ABgABAk1HHgwAF4BBGgMAAAFAE4AaQwAAAQATABrDAAAAgBNAOoMAAAFADgALgAECn86AAIYAAkJBSR6BwAoAwAYAAkJBSR6BwAoAwAAAA==.',
Mo='Monker:BAABLgAECn8eAAQOAAgJzh7aEgA8AghoDAAABQBjAGkMAAAEAGIAawwAAAUAYABqDAAAAwAWAGwMAAAEAF0AbQwAAAIALQDqDAAABgBfAG4MAAABAFEADgAHCa4e2hIAPAIHaAwAAAMAYwBpDAAAAwBiAGsMAAAEAGAAagwAAAEAFgBsDAAAAwBdAG0MAAACAC0A6gwAAAMAXwAKAAYJgBUQPgAjAQZoDAAAAQA+AGkMAAABAEQAawwAAAEAPwBqDAAAAQBDAGwMAAABAB0AbgwAAAEAMwAPAAMJvBysUACaAANoDAAAAQA5AGoMAAABAEMA6gwAAAMAWgAAAA==.',
Mu='Muth:BAAALgAECgQJBgAAAA==.Muthra:BAAALgAECgEJAQABLgAECgQJBgANAAAAAA==.Muthroc:BAAALgAECgEJAQABLgAECgQJBgANAAAAAA==.',
Na='Nasara:BAABLgAECn80AAIYAAgJXyP7IADwAghoDAAACQBfAGkMAAAJAGEAawwAAAoAXQBqDAAACgBiAGwMAAAGAF0AbQwAAAEARQDqDAAABQBiAG4MAAACAFUAGAAICV8j+yAA8AIIaAwAAAkAXwBpDAAACQBhAGsMAAAKAF0AagwAAAoAYgBsDAAABgBdAG0MAAABAEUA6gwAAAUAYgBuDAAAAgBVAAAA.Nastylad:BAAALgADCgMJAwAAAA==.Nastyzoo:BAAALgAECgUJCAAAAA==.Natassia:BAAALgAECgIJAgAAAA==.',
Ne='Neceob:BAAALgADCgYJCAAAAA==.Nehemia:BAAALgADCgEJAQAAAA==.',
Ni='Nikallnight:BAAALgADCgYJBgAAAA==.',
No='Noodles:BAAALgADCgcJBwABLgAECgcJHQAJAL4WAA==.Northstríder:BAAALgADCgMJAwAAAA==.Notloc:BAAALgAECgMJAwABLgAECgcJHQAKAD4kAA==.',
Ob='Oblivionpwr:BAAALgAECgEJAgABLgAECgkJOgAQAHYTAA==.',
On='Onomisar:BAAALgAECgQJCAAAAA==.',
Or='Oriah:BAAALgADCgMJAwAAAA==.',
Pa='Padtroll:BAAALgADCgQJBAAAAA==.Paliatarii:BAABLgAECn8aAAIVAAYJERa3hAAvAQZoDAAABgBKAGkMAAAGADgAawwAAAUAMgBqDAAAAgA0AGwMAAACADUA6gwAAAUALwAVAAYJERa3hAAvAQZoDAAABgBKAGkMAAAGADgAawwAAAUAMgBqDAAAAgA0AGwMAAACADUA6gwAAAUALwAAAA==.Pallyfever:BAAALgADCgkJEAAAAA==.',
Pu='Purple:BAAALgADCgMJAwABLgAECgcJHQAKAD4kAA==.',
Ra='Raging:BAAALgAECgMJBAAAAA==.',
Re='Remyxo:BAAALgAECgUJDgAAAA==.Repentia:BAAALgAECgYJEQAAAA==.Revaneth:BAAALgADCgcJDwAAAA==.Revanoc:BAAALgADCgYJBgAAAA==.Revanon:BAAALgADCgYJBgAAAA==.',
Ro='Roidsnmolly:BAAALgAECgYJAQAAAA==.',
Ru='Runa:BAAALgAECgYJEwABLgAFFAQJDQAHAMAQAA==.',
Sa='Sadie:BAAALgAECgMJAgAAAA==.Sahlberg:BAAALgAECgcJDwAAAA==.Saphyra:BAAALgADCgUJBQABLgAECgYJGQAEAOQLAA==.',
Sc='Schiel:BAAALgAECgEJAQAAAA==.',
Se='Senkestsu:BAAALgAECgcJCwAAAA==.Seraphin:BAAALgAFFAIJAwAAAA==.Sezen:BAAALgAECgcJCAAAAA==.',
Sh='Shammtastiç:BAABLgAECn8zAAIZAAkJIReeFwDtAQloDAAACQBMAGkMAAAIAFIAawwAAAgATQBqDAAABQBBAGwMAAAEAC8AbQwAAAEACwDqDAAACgBRAG4MAAAFAEwAbwwAAAEAFQAZAAkJIReeFwDtAQloDAAACQBMAGkMAAAIAFIAawwAAAgATQBqDAAABQBBAGwMAAAEAC8AbQwAAAEACwDqDAAACgBRAG4MAAAFAEwAbwwAAAEAFQAAAA==.Shandizard:BAAALgADCgkJDQAAAA==.Shivra:BAAALgAECgIJAwAAAA==.Shohei:BAAALgADCgcJBwAAAA==.Shulrukol:BAAALgAECgYJEAABLgAFFAcJHwAQALsgAA==.Shytownx:BAAALgAECgEJAQAAAA==.',
Si='Sinley:BAABLgAECn8eAAMVAAcJVw3BeABGAQdoDAAABQAoAGkMAAAFAB4AawwAAAUAEwBqDAAABAAoAGwMAAAEADEA6gwAAAUAIABuDAAAAgAhABUABwlXDcF4AEYBB2gMAAAFACgAaQwAAAQAHgBrDAAABQATAGoMAAADACgAbAwAAAQAMQDqDAAABAAgAG4MAAACACEACAADCScFaCoAKQADaQwAAAEAEgBqDAAAAQAFAOoMAAABAAgAAAA=.',
Sn='Sncak:BAACLgAFFH8YAAMCAAUJ4SKDCQCBAQVoDAAABwBfAGkMAAAGAGEAawwAAAUASQBqDAAAAQAaAOoMAAAFAFsAAgAFCeEigwkAgQEFaAwAAAcAXwBpDAAABQBhAGsMAAAFAEkAagwAAAEAGgDqDAAABQBbAAMAAQk5DTwGAFwAAWkMAAABACEALgAECn8qAAMCAAkJDyQoAgCQAwACAAkJDyQoAgCQAwADAAQJvxukDwAWAQAAAA==.',
So='Solvatod:BAAALgADCgIJAgAAAA==.Soyboiz:BAAALgAECgUJBwAAAA==.',
Sp='Spellslanger:BAAALgADCgYJBgAAAA==.Spiritwolf:BAACLgAFFH8GAAIEAAMJnQ8+CADtAANoDAAAAwA6AGkMAAACACIA6gwAAAEAGwAEAAMJnQ8+CADtAANoDAAAAwA6AGkMAAACACIA6gwAAAEAGwAuAAQKfxoAAgQACQnzITsEAN0CAAQACQnzITsEAN0CAAAA.',
St='Stanalli:BAAALgADCgIJAgAAAA==.',
Sy='Sylvara:BAAALgAECgUJBQAAAA==.Symphony:BAAALgAECgQJBgAAAA==.Syrax:BAABLgAECn8fAAMLAAcJqhYsCACEAQdoDAAABgBMAGkMAAAHAEEAawwAAAYAJwBqDAAABAA5AGwMAAADAEwA6gwAAAQATABuDAAAAQAOAAsABgkIGiwIAIQBBmgMAAAGAEwAaQwAAAMAQQBrDAAAAwAmAGoMAAAEADkAbAwAAAMATADqDAAAAwBMAAwABAlrDC5QALYABGkMAAAEACQAawwAAAMAJwDqDAAAAQAlAG4MAAABAA4AAS4ABAoJCSwAFwBMGgA=.Syrieal:BAABLgAECn8sAAMXAAkJTBrMCwATAgloDAAABgBBAGkMAAAFAD8AawwAAAUARgBqDAAABQBFAGwMAAAEADoAbQwAAAYALQDqDAAABgBIAG4MAAAFAGAAbwwAAAIAQwAXAAkJMhrMCwATAgloDAAABgBBAGkMAAAFAD8AawwAAAUARgBqDAAABQBFAGwMAAAEADoAbQwAAAUAKwDqDAAABQBIAG4MAAAFAGAAbwwAAAIAQwAIAAIJywpLJgA5AAJtDAAAAQAtAOoMAAABAAkAAAA=.',
Ta='Taiyla:BAABLgAECn8sAAIYAAkJ8g9OSADbAQloDAAABwAxAGkMAAAGACcAawwAAAYAHABqDAAABgAtAGwMAAAFADcAbQwAAAMAGQDqDAAABgAzAG4MAAAEADkAbwwAAAEAEwAYAAkJ8g9OSADbAQloDAAABwAxAGkMAAAGACcAawwAAAYAHABqDAAABgAtAGwMAAAFADcAbQwAAAMAGQDqDAAABgAzAG4MAAAEADkAbwwAAAEAEwAAAA==.Talithiala:BAAALgAECgYJBgAAAA==.Tallai:BAAALgAECgEJAwAAAA==.Tash:BAABLgAECn8rAAMOAAgJFBkqEwAzAghoDAAABwBMAGkMAAAFAEIAawwAAAUARQBqDAAABgBcAGwMAAAHAE0AbQwAAAMAHwDqDAAACABFAG4MAAACAB0ADgAICRQZKhMAMwIIaAwAAAUATABpDAAABABCAGsMAAAEAEUAagwAAAUAXABsDAAABQBNAG0MAAACAB8A6gwAAAYARQBuDAAAAgAdAAoABwmKCgBIALAAB2gMAAACAB0AaQwAAAEAEgBrDAAAAQAGAGoMAAABACoAbAwAAAIATABtDAAAAQALAOoMAAACABMAAAA=.Taurelin:BAAALgAECgEJAQAAAA==.',
Te='Tejano:BAAALgAECggJEQAAAA==.',
Th='Thyra:BAAALgAECgUJBQABLgAFFAQJDQAHAMAQAA==.',
Tr='Trip:BAABLgAECn8kAAMaAAkJBw93EwAtAQloDAAABQAYAGkMAAAFABcAawwAAAUAHwBqDAAABAAXAGwMAAAEACYAbQwAAAIAPwDqDAAABQAlAG4MAAAEAC0AbwwAAAIALAAaAAcJBw13EwAtAQdoDAAAAQAYAGkMAAABABcAawwAAAEAHwBqDAAAAQAXAGwMAAACACYA6gwAAAMAJQBuDAAAAgAtABsACQlNC+9WACsBCWgMAAAEACUAaQwAAAQADgBrDAAABAAcAGoMAAADACMAbAwAAAIAHgBtDAAAAgAjAOoMAAACACkAbgwAAAIADgBvDAAAAgAYAAAA.',
Tu='Tubbybuddy:BAAALgAECgYJEQAAAA==.Tunafish:BAAALgADCgMJAwAAAA==.',
['Tö']='Töhru:BAAALgADCgEJAQAAAA==.',
Un='Uniboom:BAAALgADCgYJBgABLgAFFAYJGwASAEUdAA==.Unilock:BAABLgAECn8fAAIcAAkJORk7IQA6AgloDAAABQBdAGkMAAAFAF8AawwAAAQAUQBqDAAAAwBeAGwMAAAFAFsAbQwAAAEAAQDqDAAABQBXAG4MAAACAD8AbwwAAAEAAQAcAAkJORk7IQA6AgloDAAABQBdAGkMAAAFAF8AawwAAAQAUQBqDAAAAwBeAGwMAAAFAFsAbQwAAAEAAQDqDAAABQBXAG4MAAACAD8AbwwAAAEAAQABLgAFFAYJGwASAEUdAA==.Unipray:BAACLgAFFH8bAAMSAAYJRR2NAwDfAQZoDAAABgBAAGkMAAAGAF8AawwAAAUAOgBqDAAAAwBXAGwMAAABACsA6gwAAAYAYwASAAYJRR2NAwDfAQZoDAAABABAAGkMAAAFAF8AawwAAAQAOgBqDAAAAgBXAGwMAAABACsA6gwAAAYAYwAQAAQJ/ROzGQDoAARoDAAAAgA6AGkMAAABADQAawwAAAEAKwBqDAAAAQAeAC4ABAp/JwADEgAJCbAiUAEAbwMAEgAJCbAiUAEAbwMAEAAHCesesRYA4gEAAAA=.',
Va='Valaran:BAAALgADCgEJAQAAAA==.Vamperella:BAABLgAECn8WAAIdAAUJYwHMDgBLAAVoDAAABgABAGkMAAAFAAUAawwAAAQAAwBsDAAAAQADAOoMAAAGAAMAHQAFCWMBzA4ASwAFaAwAAAYAAQBpDAAABQAFAGsMAAAEAAMAbAwAAAEAAwDqDAAABgADAAAA.',
Ve='Velkor:BAAALgAECgQJBQAAAA==.',
Vi='Vikings:BAAALgADCgIJAgAAAA==.',
Wa='Wanye:BAAALgADCgcJBwAAAA==.',
We='Wenzr:BAAALgAECgQJBgAAAA==.',
Wu='Wumbo:BAAALgAECgIJAgABLgAFFAcJHQAVAF0kAA==.',
Ye='Yefercas:BAAALgAECgUJCgAAAA==.',
Yi='Yiumi:BAABLgAECn8xAAIeAAkJoxTaAQAnAgloDAAABwA4AGkMAAAHAE0AawwAAAcAMQBqDAAABQAcAGwMAAAFADsAbQwAAAUAJwDqDAAABwBGAG4MAAAFACgAbwwAAAEAHQAeAAkJoxTaAQAnAgloDAAABwA4AGkMAAAHAE0AawwAAAcAMQBqDAAABQAcAGwMAAAFADsAbQwAAAUAJwDqDAAABwBGAG4MAAAFACgAbwwAAAEAHQAAAA==.',
Yl='Ylvis:BAABLgAECn8gAAITAAgJBAefYABKAQhoDAAABAARAGkMAAAFABgAawwAAAYAEwBqDAAABAAeAGwMAAAEABwAbQwAAAMADADqDAAAAwAOAG4MAAADAAkAEwAICQQHn2AASgEIaAwAAAQAEQBpDAAABQAYAGsMAAAGABMAagwAAAQAHgBsDAAABAAcAG0MAAADAAwA6gwAAAMADgBuDAAAAwAJAAAA.',
Yo='You:BAABLgAECn8kAAIXAAkJsRdQDwDXAQloDAAABQArAGkMAAAFAFAAawwAAAUATABqDAAABABZAGwMAAAEADkAbQwAAAIAGQDqDAAABQA8AG4MAAAEAEMAbwwAAAIASAAXAAkJsRdQDwDXAQloDAAABQArAGkMAAAFAFAAawwAAAUATABqDAAABABZAGwMAAAEADkAbQwAAAIAGQDqDAAABQA8AG4MAAAEAEMAbwwAAAIASAAAAA==.',
Yu='Yulogee:BAAALgAFFAMJBAAAAA==.Yurdead:BAAALgADCgYJBgABLgAECgEJAQANAAAAAA==.',
Ze='Zemzelett:BAAALgAECgUJCwAAAA==.Zeuz:BAAALgADCgEJAQAAAA==.',
Zu='Zumadin:BAAALgADCgkJBwAAAA==.Zummev:BAAALgADCgYJBAAAAA==.',
['Æs']='Æsham:BAAALgADCgQJBAAAAA==.',
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
