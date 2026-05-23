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

local lookup = {'Warrior-Fury','Rogue-Subtlety','Rogue-Assassination','Druid-Feral','Druid-Guardian','Druid-Balance','Druid-Restoration','DeathKnight-Frost','DemonHunter-Devourer','Warrior-Protection','Monk-Windwalker','Evoker-Augmentation','Evoker-Devastation','Paladin-Retribution','Unknown-Unknown','Monk-Mistweaver','Monk-Brewmaster','Paladin-Holy','Priest-Shadow','Priest-Discipline','Priest-Holy','Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Blood','Mage-Frost','Shaman-Elemental','Shaman-Restoration','Shaman-Enhancement','Warlock-Demonology','Mage-Arcane','Mage-Fire',}
local provider = {region='US',realm='Kalecgos',name='US',type='daily',zone=46,date='2026-05-22',data={Aa='Aamon:BAAALgADCgUJBQAAAA==.Aarius:BAAALgAECgQJBAAAAA==.',
Ae='Aerius:BAAALgADCgYJBAAAAA==.',
Am='Amen:BAAALgADCgEJAQAAAA==.',
Ao='Ao:BAAALgAECgQJCwAAAA==.',
Au='Augmentation:BAAALgAECgIJAwAAAA==.Aurumursi:BAAALgADCgcJBwAAAA==.',
Av='Aviandraka:BAAALgADCgEJAQAAAA==.',
Ba='Baeroch:BAAALgADCgEJAQAAAA==.Barlartwo:BAAALgAECgUJBQAAAA==.Bazthrax:BAAALgAECgIJAgAAAA==.Baztinel:BAAALgADCgkJCQAAAA==.Bazty:BAAALgAECgYJDgAAAA==.',
Be='Belthazaar:BAAALgAECgUJCAAAAA==.',
Bl='Blade:BAACLgAFFH8KAAIBAAMJzh1pIgD0AANoDAAABQBXAGkMAAADAE4A6gwAAAIAPgABAAMJzh1pIgD0AANoDAAABQBXAGkMAAADAE4A6gwAAAIAPgAuAAQKfx0AAgEACAnWIhMUACkCAAEACAnWIhMUACkCAAAA.Blarneystone:BAAALgAECgUJDgAAAA==.Bluemoon:BAAALgADCgYJBgAAAA==.',
Bo='Bootybsneaks:BAACLgAFFH8bAAICAAUJCiPmCACYAQVoDAAABwBaAGkMAAAHAGAAawwAAAUASgBqDAAAAwBFAOoMAAAFAGEAAgAFCQoj5ggAmAEFaAwAAAcAWgBpDAAABwBgAGsMAAAFAEoAagwAAAMARQDqDAAABQBhAC4ABAp/NQADAgAJCSIjKAMA/QIAAgAJCSIjKAMA/QIAAwABCXwWLyAAOwAAAAA=.',
Br='Bramble:BAAALgADCgIJAgAAAA==.Brynhild:BAABLgAECn8ZAAIEAAYJ5AvtHADiAAZoDAAABQApAGkMAAAFABgAawwAAAQAFgBqDAAABAAdAGwMAAAEAB8A6gwAAAMAIAAEAAYJ5AvtHADiAAZoDAAABQApAGkMAAAFABgAawwAAAQAFgBqDAAABAAdAGwMAAAEAB8A6gwAAAMAIAAAAA==.',
Bu='Bullfist:BAAALgAECgYJCgABLgAECggJJAAFABocAA==.Bullievit:BAACLgAFFH8FAAIGAAMJFxDsJQDFAANoDAAAAgA8AGsMAAABAAYA6gwAAAIAOAAGAAMJFxDsJQDFAANoDAAAAgA8AGsMAAABAAYA6gwAAAIAOAAuAAQKfyQAAwYACQleHdEVAPUBAAYACQleHdEVAPUBAAcABAktBTyeAI4AAAAA.',
Ca='Calssara:BAAALgADCgEJAQAAAA==.',
Ce='Cerealkìller:BAABLgAECn80AAIIAAkJpRDsBwDHAQloDAAABwArAGkMAAAHACYAawwAAAYAKgBqDAAABwAtAGwMAAAGACcAbQwAAAUAIADqDAAABwAkAG4MAAAFAFgAbwwAAAIAEwAIAAkJpRDsBwDHAQloDAAABwArAGkMAAAHACYAawwAAAYAKgBqDAAABwAtAGwMAAAGACcAbQwAAAUAIADqDAAABwAkAG4MAAAFAFgAbwwAAAIAEwAAAA==.',
Ch='Chaostheory:BAAALgAECgEJAgABLgAFFAMJCgABAM4dAA==.Chaozz:BAABLgAECn8YAAIJAAYJXyIQPwD4AQZoDAAABABjAGkMAAAEAFUAawwAAAQAWABqDAAABABIAGwMAAAEAEoA6gwAAAQAWwAJAAYJXyIQPwD4AQZoDAAABABjAGkMAAAEAFUAawwAAAQAWABqDAAABABIAGwMAAAEAEoA6gwAAAQAWwAAAA==.Chichi:BAAALgAECgIJAgAAAA==.Chistery:BAAALgAECgUJBgAAAA==.Chunly:BAAALgAECgYJEQAAAA==.',
Cl='Clovicta:BAAALgADCgQJBAAAAA==.',
Cm='Cmoobones:BAABLgAECn8VAAIKAAgJRw+XFgBlAQhoDAAAAwA9AGkMAAADAB0AawwAAAMAJwBqDAAAAwA9AGwMAAADADAAbQwAAAEAGQDqDAAABAAoAG4MAAABABwACgAICUcPlxYAZQEIaAwAAAMAPQBpDAAAAwAdAGsMAAADACcAagwAAAMAPQBsDAAAAwAwAG0MAAABABkA6gwAAAQAKABuDAAAAQAcAAAA.',
Co='Colokush:BAAALgADCgcJBwAAAA==.Constantine:BAAALgADCgEJAQABLgAECgcJHQALAD4kAA==.',
Cr='Crisgard:BAAALgAECgQJDgAAAA==.Cronos:BAABLgAECn8mAAMMAAgJYhMIJwCFAQhoDAAABgA2AGkMAAAFADkAawwAAAYANwBqDAAABQA2AGwMAAAFADUAbQwAAAIAIQDqDAAABwBEAG4MAAACABgADAAICUsQCCcAhQEIaAwAAAQANgBpDAAABQA5AGsMAAAGADcAagwAAAQANgBsDAAABAAoAG0MAAABABUA6gwAAAYAJgBuDAAAAQAYAA0ABglwEOMMAB8BBmgMAAACAC4AagwAAAEAIABsDAAAAQA1AG0MAAABACEA6gwAAAEARABuDAAAAQAHAAAA.Crow:BAAALgAECgkJBAAAAA==.Crysalus:BAAALgAECgEJAQAAAA==.',
Da='Dacian:BAAALgAECggJDwAAAA==.Darallyn:BAAALgAECgYJEwAAAA==.Davik:BAAALgAECgQJEwAAAA==.',
De='Deathcharger:BAAALgADCgYJDwAAAA==.Demonicaxe:BAAALgADCgkJCQAAAA==.Devïl:BAAALgAECgMJAgAAAA==.',
Di='Dingbat:BAAALgADCgEJAQAAAA==.',
Do='Dog:BAAALgAECggJBgAAAA==.Dollfie:BAAALgAECgIJAgAAAA==.Doser:BAABLgAECn8UAAIOAAgJ1gtmfABSAQhoDAAAAwBEAGkMAAAEACAAawwAAAMAEQBqDAAAAwA2AGwMAAADAB0AbQwAAAEAGgDqDAAAAgAUAG4MAAABABIADgAICdYLZnwAUgEIaAwAAAMARABpDAAABAAgAGsMAAADABEAagwAAAMANgBsDAAAAwAdAG0MAAABABoA6gwAAAIAFABuDAAAAQASAAAA.',
Dr='Dracarsynimz:BAAALgAECgkJMQABLgAFFAQJEwAMAEILAQ==.Dracene:BAAALgAECgUJDgAAAA==.Dragosa:BAAALgADCgMJAwABLgAECgMJBAAPAAAAAA==.',
Du='Duf:BAAALgAECgEJAwAAAA==.',
Dy='Dynasty:BAAALgAECgQJBAAAAA==.',
Eb='Eblazed:BAAALgADCgMJAwAAAA==.',
Fe='Feraldruid:BAAALgAECgMJAwAAAA==.',
Fi='Fisten:BAAALgAECgYJBgAAAA==.',
Fl='Flixs:BAAALgAECgEJAQABLgAECgQJCwAPAAAAAA==.',
Fo='Foxcraft:BAABLgAECn8aAAMQAAkJvB4OBQAUAwloDAAAAwBfAGkMAAADAFwAawwAAAMAXgBqDAAABQBZAGwMAAADAEgAbQwAAAEAPQDqDAAABQBTAG4MAAACADUAbwwAAAEAQQAQAAkJvB4OBQAUAwloDAAAAwBfAGkMAAADAFwAawwAAAMAXgBqDAAABQBZAGwMAAADAEgAbQwAAAEAPQDqDAAABQBTAG4MAAABADUAbwwAAAEAQQARAAEJZQrEhQA7AAFuDAAAAQAaAAAA.',
Fr='Friëren:BAAALgAECgQJBQAAAA==.',
Ga='Gamera:BAAALgAECgUJCgAAAA==.Gangstabarny:BAAALgAECgEJAQAAAA==.Gankadin:BAABLgAECn8WAAMSAAgJkxQoGQASAghoDAAAAwBKAGkMAAADAFIAawwAAAMANwBqDAAAAwAfAGwMAAADAEwAbQwAAAEAJADqDAAABQAwAG4MAAABAA4AEgAICZMUKBkAEgIIaAwAAAIASgBpDAAAAwBSAGsMAAADADcAagwAAAMAHwBsDAAAAwBMAG0MAAABACQA6gwAAAUAMABuDAAAAQAOAA4AAQnxBK5xASkAAWgMAAABAAwAAAA=.',
Gb='Gb:BAACLgAFFH8NAAMTAAQJ8hrfGAD4AARoDAAABQBZAGkMAAAEAC0AawwAAAIATgDqDAAAAgA+ABMAAwmwGd8YAPgAA2gMAAAEAFkAaQwAAAIALQDqDAAAAgA+ABQAAwnJD7cjANoAA2gMAAABACQAaQwAAAIAKQBrDAAAAgArAC4ABAp/KAAEFAAJCUod7wUA/wIAFAAJCUod7wUA/wIAEwAICeUcAw4AowIAFQACCTkIMnEAYgAAAAA=.',
Gi='Giffca:BAAALgAECgYJDgAAAA==.',
Gr='Groobel:BAAALgAECgEJAwAAAA==.Groobs:BAAALgAECgEJBwAAAA==.',
Gu='Gunhyrr:BAAALgAFFAEJAQAAAA==.',
Ho='Holycow:BAAALgAECgUJBQABLgAECggJKAALABQXAA==.',
Hu='Humanmatt:BAAALgAECgQJBgAAAA==.',
Hy='Hydra:BAAALgAECgkJBAAAAA==.',
Ic='Icewolff:BAAALgAECgUJBgAAAA==.',
Ik='Ikinokoru:BAACLgAFFH8FAAIWAAMJ3yO+LwAdAQNoDAAAAgBfAGkMAAABAFgA6gwAAAIAWwAWAAMJ3yO+LwAdAQNoDAAAAgBfAGkMAAABAFgA6gwAAAIAWwAuAAQKfzoAAhYACAmRJf8IAO0CABYACAmRJf8IAO0CAAAA.',
In='Inyànga:BAAALgAECgMJAwAAAA==.',
Je='Jeffren:BAAALgAECgQJCwAAAA==.',
Ji='Jinsho:BAAALgAECggJCAAAAA==.',
Jy='Jyve:BAAALgADCgcJBwABLgAECgkJIgAWAHwbAA==.',
Ka='Kalal:BAAALgADCgYJBwAAAA==.',
Ke='Keg:BAABLgAECn8dAAILAAcJPiQcEAB+AgdoDAAABQBgAGkMAAAFAGEAawwAAAUAYgBqDAAABABfAGwMAAAEAFgAbQwAAAEAVwDqDAAABQBYAAsABwk+JBwQAH4CB2gMAAAFAGAAaQwAAAUAYQBrDAAABQBiAGoMAAAEAF8AbAwAAAQAWABtDAAAAQBXAOoMAAAFAFgAAAA=.Keygunmonk:BAAALgADCgcJBwAAAA==.',
Ko='Kovowolf:BAACLgAFFH8OAAIHAAQJwBAzIgAUAQRoDAAABQA/AGkMAAAFADwAawwAAAIAFgDqDAAAAgAZAAcABAnAEDMiABQBBGgMAAAFAD8AaQwAAAUAPABrDAAAAgAWAOoMAAACABkALgAECn8qAAIHAAkJDx8LCwDtAgAHAAkJDx8LCwDtAgAAAA==.',
Kr='Krazedwolf:BAACLgAFFH8FAAIOAAMJPBP5RwDuAANoDAAAAgBUAGkMAAACACMAawwAAAEAGgAOAAMJPBP5RwDuAANoDAAAAgBUAGkMAAACACMAawwAAAEAGgAuAAQKfygAAg4ACQlGId4PAM0CAA4ACQlGId4PAM0CAAAA.',
Kv='Kvn:BAAALgAECgUJBgAAAA==.',
Le='Lehran:BAAALgAECgIJAwAAAA==.Lemonator:BAAALgAECgQJBQAAAA==.Lemynaid:BAAALgAECgYJDgAAAA==.',
Li='Linsay:BAACLgAFFH8gAAITAAgJJx10AADAAghoDAAABgBjAGkMAAAFAGIAawwAAAUAXABqDAAABQBjAGwMAAACAFcAbQwAAAEAGADqDAAABwBkAG4MAAABABMAEwAICScddAAAwAIIaAwAAAYAYwBpDAAABQBiAGsMAAAFAFwAagwAAAUAYwBsDAAAAgBXAG0MAAABABgA6gwAAAcAZABuDAAAAQATAC4ABAp/NwACEwAJCSUmQAEAwAMAEwAJCSUmQAEAwAMAAAA=.',
Lo='Lokagdai:BAAALgAECgEJAgAAAA==.Lotieos:BAABLgAECn8bAAIXAAYJMQ6jmgANAQZoDAAABwAkAGkMAAAHAC4AawwAAAUAIABqDAAAAQAOAGwMAAABAAwA6gwAAAYANgAXAAYJMQ6jmgANAQZoDAAABwAkAGkMAAAHAC4AawwAAAUAIABqDAAAAQAOAGwMAAABAAwA6gwAAAYANgAAAA==.Lovelypwr:BAABLgAECn86AAITAAkJdRPjFQD0AQloDAAACgA9AGkMAAAHADwAawwAAAYAJgBqDAAABQAiAGwMAAAHADsAbQwAAAUAKQDqDAAACgBEAG4MAAAFABgAbwwAAAMAKwATAAkJdRPjFQD0AQloDAAACgA9AGkMAAAHADwAawwAAAYAJgBqDAAABQAiAGwMAAAHADsAbQwAAAUAKQDqDAAACgBEAG4MAAAFABgAbwwAAAMAKwAAAA==.',
Ma='Mannera:BAAALgAFFAMJAwAAAA==.Manzio:BAAALgADCgQJBAAAAA==.Marcus:BAAALgAECgMJBAAAAA==.Matheris:BAABLgAECn8YAAIKAAkJZiLgAwDQAgloDAAABQBfAGkMAAADAF4AawwAAAMAXgBqDAAAAgBRAGwMAAACAFsAbQwAAAIAQQDqDAAABABhAG4MAAACAFIAbwwAAAEAUgAKAAkJZiLgAwDQAgloDAAABQBfAGkMAAADAF4AawwAAAMAXgBqDAAAAgBRAGwMAAACAFsAbQwAAAIAQQDqDAAABABhAG4MAAACAFIAbwwAAAEAUgAAAA==.Mawiyah:BAAALgAECgcJBwAAAA==.Max:BAAALgAECgYJEQABLgAFFAMJBQAYAI8OAA==.',
Me='Melarac:BAABLgAECn8VAAQGAAYJjQljQgDNAAZoDAAABAAbAGkMAAAEABsAawwAAAQAEgBqDAAAAwAoAGwMAAABABYA6gwAAAUAGQAGAAYJjQljQgDNAAZoDAAAAQAbAGkMAAABABsAawwAAAEAEgBqDAAAAQAoAGwMAAABABYA6gwAAAIAGQAHAAUJCAhHeQCpAAVoDAAAAQAJAGkMAAABACAAawwAAAEADABqDAAAAQAjAOoMAAABAAwABQAFCdQGyDwAYwAFaAwAAAIAEwBpDAAAAgARAGsMAAACAA8AagwAAAEADQDqDAAAAgAQAAAA.',
Mi='Minibow:BAAALgAECgEJAQAAAA==.Minimagic:BAACLgAFFH8QAAIZAAQJNRwRNwBTAQRoDAAABQBOAGkMAAAEAEwAawwAAAIATQDqDAAABQA4ABkABAk1HBE3AFMBBGgMAAAFAE4AaQwAAAQATABrDAAAAgBNAOoMAAAFADgALgAECn86AAIZAAkJBiRrCAAkAwAZAAkJBiRrCAAkAwAAAA==.',
Mo='Mogh:BAAALgAECgMJAwAAAA==.Monker:BAABLgAECn8eAAQQAAgJzh4/FAA7AghoDAAABQBjAGkMAAAEAGIAawwAAAUAYABqDAAAAwAWAGwMAAAEAF0AbQwAAAIALQDqDAAABgBfAG4MAAABAFEAEAAHCa4ePxQAOwIHaAwAAAMAYwBpDAAAAwBiAGsMAAAEAGAAagwAAAEAFgBsDAAAAwBdAG0MAAACAC0A6gwAAAMAXwALAAYJgBUQPgAjAQZoDAAAAQA+AGkMAAABAEQAawwAAAEAPwBqDAAAAQBDAGwMAAABAB0AbgwAAAEAMwARAAMJvByXUgCaAANoDAAAAQA5AGoMAAABAEMA6gwAAAMAWgAAAA==.',
Mu='Muth:BAAALgAECgQJBgAAAA==.Muthra:BAAALgAECgEJAQABLgAECgQJBgAPAAAAAA==.Muthroc:BAAALgAECgEJAQABLgAECgQJBgAPAAAAAA==.',
Na='Nasara:BAABLgAECn82AAIZAAgJXyP7IADwAghoDAAACQBfAGkMAAAJAGEAawwAAAoAXQBqDAAACgBiAGwMAAAGAF0AbQwAAAEARQDqDAAABgBiAG4MAAADAFUAGQAICV8j+yAA8AIIaAwAAAkAXwBpDAAACQBhAGsMAAAKAF0AagwAAAoAYgBsDAAABgBdAG0MAAABAEUA6gwAAAYAYgBuDAAAAwBVAAAA.Nastylad:BAAALgADCgMJAwAAAA==.Nastyzoo:BAAALgAECgUJCAAAAA==.Natassia:BAAALgAECgIJAgAAAA==.',
Ne='Neceob:BAAALgADCgYJCAAAAA==.Nehemia:BAAALgADCgEJAQAAAA==.',
Ni='Nikallnight:BAAALgADCgYJBgAAAA==.',
No='Noodles:BAAALgADCgcJBwABLgAECgcJHQAJAL4WAA==.Northstríder:BAAALgADCgMJAwAAAA==.Notloc:BAAALgAECgMJAwABLgAECgcJHQALAD4kAA==.',
Ob='Oblivionpwr:BAAALgAECgEJAgABLgAECgkJOgATAHUTAA==.',
On='Onomisar:BAAALgAECgUJCQAAAA==.',
Or='Oriah:BAAALgADCgMJAwAAAA==.',
Pa='Padtroll:BAAALgADCgQJBAAAAA==.Paliatarii:BAABLgAECn8bAAIXAAYJERa0iwAnAQZoDAAABgBKAGkMAAAGADgAawwAAAUAMgBqDAAAAgA0AGwMAAADADUA6gwAAAUALwAXAAYJERa0iwAnAQZoDAAABgBKAGkMAAAGADgAawwAAAUAMgBqDAAAAgA0AGwMAAADADUA6gwAAAUALwAAAA==.Pallyfever:BAAALgADCgkJEAAAAA==.',
Pu='Purple:BAAALgADCgMJAwABLgAECgcJHQALAD4kAA==.',
Ra='Raging:BAAALgAECgMJBAAAAA==.',
Re='Remyxo:BAAALgAECgUJDgAAAA==.Repentia:BAAALgAFFAEJAQAAAA==.Revaneth:BAAALgADCgcJDwAAAA==.Revanoc:BAAALgADCgcJBwAAAA==.Revanon:BAAALgADCgYJBgAAAA==.',
Ro='Roidsnmolly:BAAALgAECgYJAQAAAA==.',
Ru='Runa:BAAALgAECgYJEwABLgAFFAQJDgAHAMAQAA==.',
Sa='Sadie:BAAALgAECgMJAgAAAA==.Sahlberg:BAAALgAECgcJDwAAAA==.Saphyra:BAAALgADCgUJBQABLgAECgYJGQAEAOQLAA==.',
Sc='Schiel:BAAALgAECgEJAwAAAA==.',
Se='Senkestsu:BAAALgAECgcJCwAAAA==.Seraphin:BAAALgAFFAIJAwAAAA==.Sezen:BAAALgAECgcJDgAAAA==.',
Sh='Shammtastiç:BAABLgAECn8zAAIaAAkJIRcsGQDpAQloDAAACQBMAGkMAAAIAFIAawwAAAgATQBqDAAABQBBAGwMAAAEAC8AbQwAAAEACwDqDAAACgBRAG4MAAAFAEwAbwwAAAEAFQAaAAkJIRcsGQDpAQloDAAACQBMAGkMAAAIAFIAawwAAAgATQBqDAAABQBBAGwMAAAEAC8AbQwAAAEACwDqDAAACgBRAG4MAAAFAEwAbwwAAAEAFQAAAA==.Shandizard:BAAALgADCgkJDQAAAA==.Shivra:BAAALgAECgIJAwAAAA==.Shohei:BAAALgADCgcJBwAAAA==.Shulrukol:BAAALgAECgYJEAABLgAFFAgJIAATACcdAA==.Shytownx:BAAALgAECgEJAQAAAA==.',
Si='Sinley:BAABLgAECn8eAAMXAAcJVw1DfgBAAQdoDAAABQAoAGkMAAAFAB4AawwAAAUAEwBqDAAABAAoAGwMAAAEADEA6gwAAAUAIABuDAAAAgAhABcABwlXDUN+AEABB2gMAAAFACgAaQwAAAQAHgBrDAAABQATAGoMAAADACgAbAwAAAQAMQDqDAAABAAgAG4MAAACACEACAADCScFAi0AKAADaQwAAAEAEgBqDAAAAQAFAOoMAAABAAgAAAA=.',
Sn='Sncak:BAACLgAFFH8ZAAMCAAYJVhx8BgC9AQZoDAAABwBfAGkMAAAGAGEAawwAAAUASQBqDAAAAQAaAG0MAAABAAUA6gwAAAUAWwACAAYJVhx8BgC9AQZoDAAABwBfAGkMAAAFAGEAawwAAAUASQBqDAAAAQAaAG0MAAABAAUA6gwAAAUAWwADAAEJOQ08BgBcAAFpDAAAAQAhAC4ABAp/KgADAgAJCQ8kKAIAkAMAAgAJCQ8kKAIAkAMAAwAECb8bpA8AFgEAAAA=.',
So='Solvatod:BAAALgADCgIJAgAAAA==.Soyboiz:BAAALgAECgUJBwAAAA==.',
Sp='Spellslanger:BAAALgADCgYJBgAAAA==.Spiritwolf:BAACLgAFFH8GAAIEAAMJnQ/9CADtAANoDAAAAwA6AGkMAAACACIA6gwAAAEAGwAEAAMJnQ/9CADtAANoDAAAAwA6AGkMAAACACIA6gwAAAEAGwAuAAQKfxsAAgQACQn2ITsEAN0CAAQACQn2ITsEAN0CAAAA.',
St='Stanalli:BAAALgADCgIJAgAAAA==.',
Sy='Sylvara:BAAALgAECgUJBQAAAA==.Symphony:BAAALgAECgQJBgAAAA==.Syrax:BAABLgAECn8fAAMNAAcJqhaPCACAAQdoDAAABgBMAGkMAAAHAEEAawwAAAYAJwBqDAAABAA5AGwMAAADAEwA6gwAAAQATABuDAAAAQAOAA0ABgkIGo8IAIABBmgMAAAGAEwAaQwAAAMAQQBrDAAAAwAmAGoMAAAEADkAbAwAAAMATADqDAAAAwBMAAwABAlrDMVSALYABGkMAAAEACQAawwAAAMAJwDqDAAAAQAlAG4MAAABAA4AAS4ABRQDCQUAGACPDgA=.Syrieal:BAACLgAFFH8FAAIYAAMJjw6dHQC1AANoDAAAAgAoAGkMAAABABcA6gwAAAIALwAYAAMJjw6dHQC1AANoDAAAAgAoAGkMAAABABcA6gwAAAIALwAuAAQKfzAAAxgACQlSG00LACgCABgACQn3Gk0LACgCAAgAAglCDhwlAEoAAAAA.',
Ta='Taiyla:BAABLgAECn81AAIZAAkJmxHEPwAAAgloDAAACAA9AGkMAAAHACcAawwAAAcAHABqDAAABwAyAGwMAAAGADwAbQwAAAQAKQDqDAAABwAzAG4MAAAFADkAbwwAAAIAEwAZAAkJmxHEPwAAAgloDAAACAA9AGkMAAAHACcAawwAAAcAHABqDAAABwAyAGwMAAAGADwAbQwAAAQAKQDqDAAABwAzAG4MAAAFADkAbwwAAAIAEwAAAA==.Talithiala:BAAALgAECgYJCQAAAA==.Tallai:BAAALgAECgEJAwAAAA==.Tash:BAABLgAECn8rAAMQAAgJExkqEwAzAghoDAAABwBMAGkMAAAFAEIAawwAAAUARQBqDAAABgBcAGwMAAAHAE0AbQwAAAMAHwDqDAAACABFAG4MAAACAB0AEAAICRMZKhMAMwIIaAwAAAUATABpDAAABABCAGsMAAAEAEUAagwAAAUAXABsDAAABQBNAG0MAAACAB8A6gwAAAYARQBuDAAAAgAdAAsABwmKCltLAKcAB2gMAAACAB0AaQwAAAEAEgBrDAAAAQAGAGoMAAABACoAbAwAAAIATABtDAAAAQALAOoMAAACABMAAAA=.Taurelin:BAAALgAECgEJAQAAAA==.',
Te='Tejano:BAAALgAECggJEQAAAA==.',
Th='Thyra:BAAALgAECgUJBQABLgAFFAQJDgAHAMAQAA==.',
Tr='Trip:BAABLgAECn8kAAMbAAkJSgvvVgArAQloDAAABQAlAGkMAAAFAA4AawwAAAUAHABqDAAABAAjAGwMAAAEAB4AbQwAAAIAIwDqDAAABQApAG4MAAAEAA4AbwwAAAIAGAAbAAkJSgvvVgArAQloDAAABAAlAGkMAAAEAA4AawwAAAQAHABqDAAAAwAjAGwMAAACAB4AbQwAAAIAIwDqDAAAAgApAG4MAAACAA4AbwwAAAIAGAAcAAcJBw2uFAApAQdoDAAAAQAYAGkMAAABABcAawwAAAEAHwBqDAAAAQAXAGwMAAACACYA6gwAAAMAJQBuDAAAAgAtAAAA.',
Tu='Tubbybuddy:BAAALgAECgYJEQAAAA==.Tunafish:BAAALgADCgMJAwAAAA==.',
['Tö']='Töhru:BAAALgADCgEJAQAAAA==.',
Un='Uniboom:BAAALgADCgYJBgABLgAFFAcJHQAVABwcAA==.Unilock:BAABLgAECn8fAAIdAAkJORlbIwA3AgloDAAABQBdAGkMAAAFAF8AawwAAAQAUQBqDAAAAwBeAGwMAAAFAFsAbQwAAAEAAQDqDAAABQBXAG4MAAACAD8AbwwAAAEAAQAdAAkJORlbIwA3AgloDAAABQBdAGkMAAAFAF8AawwAAAQAUQBqDAAAAwBeAGwMAAAFAFsAbQwAAAEAAQDqDAAABQBXAG4MAAACAD8AbwwAAAEAAQABLgAFFAcJHQAVABwcAA==.Unipray:BAACLgAFFH8dAAMVAAcJHBzdAQAwAgdoDAAABgBAAGkMAAAGAF8AawwAAAUAOgBqDAAAAwBXAGwMAAABACsAbQwAAAEANgDqDAAABwBjABUABwkcHN0BADACB2gMAAAEAEAAaQwAAAUAXwBrDAAABAA6AGoMAAACAFcAbAwAAAEAKwBtDAAAAQA2AOoMAAAGAGMAEwAFCV4VPBEAPQEFaAwAAAIAOgBpDAAAAQA0AGsMAAABACsAagwAAAEAHgDqDAAAAQBBAC4ABAp/JwADFQAJCbAiUAEAbwMAFQAJCbAiUAEAbwMAEwAHCeseJhgA3gEAAAA=.',
Va='Valaran:BAAALgADCgEJAQAAAA==.Vamperella:BAABLgAECn8XAAIeAAUJcgGmDgBTAAVoDAAABgABAGkMAAAFAAUAawwAAAUABABsDAAAAQADAOoMAAAGAAMAHgAFCXIBpg4AUwAFaAwAAAYAAQBpDAAABQAFAGsMAAAFAAQAbAwAAAEAAwDqDAAABgADAAAA.',
Ve='Velkor:BAAALgAECgQJBQAAAA==.',
Vi='Vikings:BAAALgADCgIJAgAAAA==.',
Wa='Wanye:BAAALgADCgcJBwAAAA==.',
We='Wenzr:BAAALgAECgQJBgAAAA==.',
Wi='Willer:BAAALgADCgYJBgAAAA==.',
Wu='Wumbo:BAAALgAECgIJAgABLgAFFAcJIQAXALgkAA==.',
Ye='Yefercas:BAAALgAECgUJCgAAAA==.',
Yi='Yiumi:BAABLgAECn84AAIfAAkJGRaYAQBOAgloDAAACAA4AGkMAAAIAE0AawwAAAgASgBqDAAABgAcAGwMAAAGADsAbQwAAAYAKADqDAAACABKAG4MAAAFACgAbwwAAAEAHQAfAAkJGRaYAQBOAgloDAAACAA4AGkMAAAIAE0AawwAAAgASgBqDAAABgAcAGwMAAAGADsAbQwAAAYAKADqDAAACABKAG4MAAAFACgAbwwAAAEAHQAAAA==.',
Yl='Ylvis:BAABLgAECn8oAAIWAAgJogeZXgBZAQhoDAAABQASAGkMAAAGABgAawwAAAgAEwBqDAAABAAeAGwMAAAFABwAbQwAAAQADADqDAAABAAPAG4MAAAEABIAFgAICaIHmV4AWQEIaAwAAAUAEgBpDAAABgAYAGsMAAAIABMAagwAAAQAHgBsDAAABQAcAG0MAAAEAAwA6gwAAAQADwBuDAAABAASAAAA.',
Yo='You:BAABLgAECn8kAAIYAAkJsxdcEADRAQloDAAABQArAGkMAAAFAFAAawwAAAUATABqDAAABABZAGwMAAAEADkAbQwAAAIAGgDqDAAABQA8AG4MAAAEAEMAbwwAAAIASAAYAAkJsxdcEADRAQloDAAABQArAGkMAAAFAFAAawwAAAUATABqDAAABABZAGwMAAAEADkAbQwAAAIAGgDqDAAABQA8AG4MAAAEAEMAbwwAAAIASAAAAA==.',
Yu='Yulogee:BAAALgAFFAMJBAAAAA==.Yurdead:BAAALgADCgYJBgABLgAECgEJAQAPAAAAAA==.',
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
