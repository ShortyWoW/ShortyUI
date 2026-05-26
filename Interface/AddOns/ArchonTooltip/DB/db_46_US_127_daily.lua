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

local lookup = {'Warrior-Fury','Rogue-Subtlety','Rogue-Assassination','Druid-Feral','Druid-Guardian','Druid-Balance','Druid-Restoration','DeathKnight-Frost','DemonHunter-Devourer','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','Warrior-Protection','Evoker-Augmentation','Evoker-Devastation','Priest-Shadow','Paladin-Retribution','Unknown-Unknown','Paladin-Holy','Priest-Discipline','Priest-Holy','Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Blood','Mage-Frost','Shaman-Elemental','Shaman-Restoration','Shaman-Enhancement','Warlock-Demonology','Mage-Arcane','Mage-Fire',}
local provider = {region='US',realm='Kalecgos',name='US',type='daily',zone=46,date='2026-05-26',data={Aa='Aamon:BAAALgADCgUJBQAAAA==.Aarius:BAAALgAECgQJBAAAAA==.',
Ae='Aerius:BAAALgADCgYJBAAAAA==.',
Am='Amen:BAAALgADCgEJAQAAAA==.',
Ao='Ao:BAAALgAECgQJCwAAAA==.',
Au='Augmentation:BAAALgAECgIJAwAAAA==.Aurumursi:BAAALgADCgcJBwAAAA==.',
Av='Aviandraka:BAAALgADCgEJAQAAAA==.',
Ba='Baeroch:BAAALgADCgEJAQAAAA==.Barlartwo:BAAALgAECgUJBQAAAA==.Bazthrax:BAAALgAECgMJAgAAAA==.Baztinel:BAAALgADCgkJCQAAAA==.Bazty:BAAALgAECgYJDgAAAA==.',
Be='Belthazaar:BAAALgAECgYJDgAAAA==.',
Bl='Blade:BAACLgAFFH8KAAIBAAMJzh06JQDyAANoDAAABQBXAGkMAAADAE4A6gwAAAIAPgABAAMJzh06JQDyAANoDAAABQBXAGkMAAADAE4A6gwAAAIAPgAuAAQKfx0AAgEACAnWIoMVACYCAAEACAnWIoMVACYCAAAA.Blarneystone:BAAALgAECgUJDgAAAA==.Bluemoon:BAAALgADCgYJBgAAAA==.',
Bo='Bootybsneaks:BAACLgAFFH8bAAICAAUJCiPKCgCTAQVoDAAABwBaAGkMAAAHAGAAawwAAAUASgBqDAAAAwBFAOoMAAAFAGEAAgAFCQojygoAkwEFaAwAAAcAWgBpDAAABwBgAGsMAAAFAEoAagwAAAMARQDqDAAABQBhAC4ABAp/NQADAgAJCSIjjAMA9gIAAgAJCSIjjAMA9gIAAwABCXwWYiEAOwAAAAA=.',
Br='Bramble:BAAALgADCgIJAgAAAA==.Brynhild:BAABLgAECn8ZAAIEAAYJ5AurHgDiAAZoDAAABQApAGkMAAAFABgAawwAAAQAFgBqDAAABAAdAGwMAAAEAB8A6gwAAAMAIAAEAAYJ5AurHgDiAAZoDAAABQApAGkMAAAFABgAawwAAAQAFgBqDAAABAAdAGwMAAAEAB8A6gwAAAMAIAAAAA==.',
Bu='Bullfist:BAAALgAECgYJDQABLgAECggJJAAFABocAA==.Bullievit:BAACLgAFFH8FAAIGAAMJFxC2KADFAANoDAAAAgA8AGsMAAABAAYA6gwAAAIAOAAGAAMJFxC2KADFAANoDAAAAgA8AGsMAAABAAYA6gwAAAIAOAAuAAQKfyQAAwYACQleHfYWAPUBAAYACQleHfYWAPUBAAcABAktBTyeAI4AAAAA.',
Ca='Calssara:BAAALgADCgEJAQAAAA==.',
Ce='Cerealkìller:BAABLgAECn80AAIIAAkJpRCqCADGAQloDAAABwArAGkMAAAHACYAawwAAAYAKgBqDAAABwAtAGwMAAAGACcAbQwAAAUAIADqDAAABwAkAG4MAAAFAFgAbwwAAAIAEwAIAAkJpRCqCADGAQloDAAABwArAGkMAAAHACYAawwAAAYAKgBqDAAABwAtAGwMAAAGACcAbQwAAAUAIADqDAAABwAkAG4MAAAFAFgAbwwAAAIAEwAAAA==.',
Ch='Chaostheory:BAAALgAECgEJAgABLgAFFAMJCgABAM4dAA==.Chaozz:BAABLgAECn8YAAIJAAYJXyIQPwD4AQZoDAAABABjAGkMAAAEAFUAawwAAAQAWABqDAAABABIAGwMAAAEAEoA6gwAAAQAWwAJAAYJXyIQPwD4AQZoDAAABABjAGkMAAAEAFUAawwAAAQAWABqDAAABABIAGwMAAAEAEoA6gwAAAQAWwAAAA==.Chichi:BAAALgAECgIJAgAAAA==.Chistery:BAAALgAECgUJBgAAAA==.Chunly:BAABLgAECn8YAAQKAAcJTxUpIACNAQdoDAAAAwA7AGkMAAAFAD0AawwAAAUAMQBqDAAAAwAwAOoMAAAEAEEAbgwAAAMAMgBvDAAAAQApAAoABwlPFSkgAI0BB2gMAAADADsAaQwAAAMAPQBrDAAAAwAxAGoMAAACADAA6gwAAAQAQQBuDAAAAwAyAG8MAAABACkACwADCSIOn2MAagADaQwAAAEAHABrDAAAAQArAGoMAAABABkADAACCZsEJmQAQAACaQwAAAEACwBrDAAAAQALAAAA.',
Cl='Clovicta:BAAALgADCgQJBAAAAA==.',
Cm='Cmoobones:BAABLgAECn8VAAINAAgJRw/BFwBjAQhoDAAAAwA9AGkMAAADAB0AawwAAAMAJwBqDAAAAwA9AGwMAAADADAAbQwAAAEAGQDqDAAABAAoAG4MAAABABwADQAICUcPwRcAYwEIaAwAAAMAPQBpDAAAAwAdAGsMAAADACcAagwAAAMAPQBsDAAAAwAwAG0MAAABABkA6gwAAAQAKABuDAAAAQAcAAAA.',
Co='Colokush:BAAALgADCgcJBwAAAA==.Constantine:BAAALgADCgEJAQABLgAECgcJHQAKAD4kAA==.',
Cr='Crisgard:BAAALgAECgQJDgAAAA==.Cronos:BAABLgAECn8mAAMOAAgJYhOnKACGAQhoDAAABgA2AGkMAAAFADkAawwAAAYANwBqDAAABQA2AGwMAAAFADUAbQwAAAIAIQDqDAAABwBEAG4MAAACABgADgAICUsQpygAhgEIaAwAAAQANgBpDAAABQA5AGsMAAAGADcAagwAAAQANgBsDAAABAAoAG0MAAABABUA6gwAAAYAJgBuDAAAAQAYAA8ABglwEHQNAB8BBmgMAAACAC4AagwAAAEAIABsDAAAAQA1AG0MAAABACEA6gwAAAEARABuDAAAAQAHAAAA.Crow:BAAALgAECgkJBAAAAA==.Crysalus:BAAALgAECgEJAQAAAA==.',
Da='Dacian:BAAALgAECggJDwAAAA==.Darallyn:BAAALgAECgYJEwAAAA==.Davik:BAABLgAECn8YAAIQAAYJ/gy0OwADAQZoDAAABgAkAGkMAAAGABEAawwAAAUAHQBqDAAAAQAiAGwMAAABACYA6gwAAAUAKwAQAAYJ/gy0OwADAQZoDAAABgAkAGkMAAAGABEAawwAAAUAHQBqDAAAAQAiAGwMAAABACYA6gwAAAUAKwAAAA==.Davinah:BAAALgADCgUJCQAAAA==.',
De='Deathcharger:BAAALgAECgMJAwAAAA==.Demonicaxe:BAAALgADCgkJCQAAAA==.Devïl:BAAALgAECgQJBwAAAA==.',
Di='Dingbat:BAAALgADCgEJAQAAAA==.',
Do='Dog:BAAALgAECggJBgAAAA==.Dollfie:BAAALgAECgIJAgAAAA==.Doser:BAABLgAECn8XAAIRAAgJgwzyfQBZAQhoDAAABABEAGkMAAAFACAAawwAAAQAHQBqDAAAAwA2AGwMAAADAB0AbQwAAAEAGgDqDAAAAgAUAG4MAAABABIAEQAICYMM8n0AWQEIaAwAAAQARABpDAAABQAgAGsMAAAEAB0AagwAAAMANgBsDAAAAwAdAG0MAAABABoA6gwAAAIAFABuDAAAAQASAAAA.',
Dr='Dracarsynimz:BAAALgAFFAIJAgABLgAFFAUJFAAOAEILAQ==.Dracene:BAAALgAECgUJDgAAAA==.Dragosa:BAAALgADCgMJAwABLgAECgMJBAASAAAAAA==.',
Du='Duf:BAAALgAECgEJAwAAAA==.',
Dy='Dynasty:BAAALgAECgQJBAAAAA==.',
Eb='Eblazed:BAAALgADCgMJAwAAAA==.',
Fe='Feraldruid:BAAALgAECgMJAwAAAA==.',
Fi='Fisten:BAAALgAECgYJBgAAAA==.',
Fl='Flixs:BAAALgAECgEJAQABLgAECgQJCwASAAAAAA==.',
Fo='Foxcraft:BAABLgAECn8aAAMMAAkJvB4OBQAUAwloDAAAAwBfAGkMAAADAFwAawwAAAMAXgBqDAAABQBZAGwMAAADAEgAbQwAAAEAPQDqDAAABQBTAG4MAAACADUAbwwAAAEAQQAMAAkJvB4OBQAUAwloDAAAAwBfAGkMAAADAFwAawwAAAMAXgBqDAAABQBZAGwMAAADAEgAbQwAAAEAPQDqDAAABQBTAG4MAAABADUAbwwAAAEAQQALAAEJZQrEhQA7AAFuDAAAAQAaAAAA.',
Fr='Friëren:BAAALgAECgQJBQAAAA==.Frostfire:BAAALgAECgEJAQAAAA==.',
Ga='Gamera:BAAALgAECgUJCgAAAA==.Gangstabarny:BAAALgAECgEJAQAAAA==.Gankadin:BAABLgAECn8WAAMTAAgJkxSRGgAQAghoDAAAAwBKAGkMAAADAFIAawwAAAMANwBqDAAAAwAfAGwMAAADAEwAbQwAAAEAJADqDAAABQAwAG4MAAABAA4AEwAICZMUkRoAEAIIaAwAAAIASgBpDAAAAwBSAGsMAAADADcAagwAAAMAHwBsDAAAAwBMAG0MAAABACQA6gwAAAUAMABuDAAAAQAOABEAAQnxBHqDASkAAWgMAAABAAwAAAA=.',
Gb='Gb:BAACLgAFFH8NAAMQAAQJ8hr1GgDxAARoDAAABQBZAGkMAAAEAC0AawwAAAIATgDqDAAAAgA+ABAAAwmwGfUaAPEAA2gMAAAEAFkAaQwAAAIALQDqDAAAAgA+ABQAAwnJDzomANgAA2gMAAABACQAaQwAAAIAKQBrDAAAAgArAC4ABAp/KAAEFAAJCUodWAYA/AIAFAAJCUodWAYA/AIAEAAICeUcAw4AowIAFQACCTkIMnEAYgAAAAA=.',
Gi='Giffca:BAAALgAECgYJDgAAAA==.',
Gr='Groobel:BAAALgAECgEJAwAAAA==.Groobs:BAAALgAECgEJBwAAAA==.',
Gu='Gunhyrr:BAAALgAFFAEJAQAAAA==.',
Ho='Holycow:BAAALgAECgUJBQABLgAECggJKAAKABQXAA==.',
Hu='Humanmatt:BAAALgAECgQJBgAAAA==.',
Hy='Hydra:BAAALgAECgkJBAAAAA==.',
Ic='Icewolff:BAAALgAECgUJBwAAAA==.',
Ik='Ikinokoru:BAACLgAFFH8FAAIWAAMJ3yPoNwAUAQNoDAAAAgBfAGkMAAABAFgA6gwAAAIAWwAWAAMJ3yPoNwAUAQNoDAAAAgBfAGkMAAABAFgA6gwAAAIAWwAuAAQKfz8AAhYACAn4JQcIAP8CABYACAn4JQcIAP8CAAAA.',
In='Inyànga:BAAALgAECgMJAwAAAA==.',
Je='Jeffren:BAAALgAECgQJCwAAAA==.',
Ji='Jinsho:BAAALgAECggJCAAAAA==.',
Jy='Jyve:BAAALgADCgcJBwABLgAECgkJIgAWAHwbAA==.',
Ka='Kalal:BAAALgADCgYJBwAAAA==.',
Ke='Keg:BAABLgAECn8dAAIKAAcJPiQcEAB+AgdoDAAABQBgAGkMAAAFAGEAawwAAAUAYgBqDAAABABfAGwMAAAEAFgAbQwAAAEAVwDqDAAABQBYAAoABwk+JBwQAH4CB2gMAAAFAGAAaQwAAAUAYQBrDAAABQBiAGoMAAAEAF8AbAwAAAQAWABtDAAAAQBXAOoMAAAFAFgAAAA=.Keygunmonk:BAAALgADCgcJBwAAAA==.',
Ko='Kovowolf:BAACLgAFFH8OAAIHAAQJwBD7JAATAQRoDAAABQA/AGkMAAAFADwAawwAAAIAFgDqDAAAAgAZAAcABAnAEPskABMBBGgMAAAFAD8AaQwAAAUAPABrDAAAAgAWAOoMAAACABkALgAECn8vAAIHAAkJsyGRBABeAwAHAAkJsyGRBABeAwAAAA==.',
Kr='Krazedwolf:BAACLgAFFH8FAAIRAAMJPBNvTADrAANoDAAAAgBUAGkMAAACACMAawwAAAEAGgARAAMJPBNvTADrAANoDAAAAgBUAGkMAAACACMAawwAAAEAGgAuAAQKfygAAhEACQlGIYcRAMcCABEACQlGIYcRAMcCAAAA.',
Kv='Kvn:BAAALgAECgUJBgAAAA==.',
Le='Leatherpapi:BAAALgADCgIJAgAAAA==.Lehran:BAAALgAECgUJBwAAAA==.Lemonator:BAAALgAECgQJBQAAAA==.Lemynaid:BAAALgAECgYJDgAAAA==.',
Li='Linsay:BAACLgAFFH8gAAIQAAgJJx2gAAC6AghoDAAABgBjAGkMAAAFAGIAawwAAAUAXABqDAAABQBjAGwMAAACAFcAbQwAAAEAGADqDAAABwBkAG4MAAABABMAEAAICScdoAAAugIIaAwAAAYAYwBpDAAABQBiAGsMAAAFAFwAagwAAAUAYwBsDAAAAgBXAG0MAAABABgA6gwAAAcAZABuDAAAAQATAC4ABAp/NwACEAAJCSUmQAEAwAMAEAAJCSUmQAEAwAMAAAA=.',
Lo='Lokagdai:BAAALgAECgEJAgAAAA==.Lotieos:BAABLgAECn8bAAIXAAYJMQ6wogAJAQZoDAAABwAkAGkMAAAHAC4AawwAAAUAIABqDAAAAQAOAGwMAAABAAwA6gwAAAYANgAXAAYJMQ6wogAJAQZoDAAABwAkAGkMAAAHAC4AawwAAAUAIABqDAAAAQAOAGwMAAABAAwA6gwAAAYANgAAAA==.Lovelypwr:BAABLgAECn87AAMQAAkJdRNbFwDxAQloDAAACgA9AGkMAAAHADwAawwAAAYAJgBqDAAABQAiAGwMAAAHADsAbQwAAAUAKQDqDAAACwBEAG4MAAAFABgAbwwAAAMAKwAQAAkJdRNbFwDxAQloDAAACgA9AGkMAAAHADwAawwAAAYAJgBqDAAABQAiAGwMAAAHADsAbQwAAAUAKQDqDAAACgBEAG4MAAAFABgAbwwAAAMAKwAUAAEJSwygaAAwAAHqDAAAAQAfAAAA.',
Ma='Mannera:BAAALgAFFAMJAwAAAA==.Manzio:BAAALgADCgQJBAAAAA==.Marcus:BAAALgAECgMJBAAAAA==.Matheris:BAABLgAECn8YAAINAAkJZiJGBADLAgloDAAABQBfAGkMAAADAF4AawwAAAMAXgBqDAAAAgBRAGwMAAACAFsAbQwAAAIAQQDqDAAABABhAG4MAAACAFIAbwwAAAEAUgANAAkJZiJGBADLAgloDAAABQBfAGkMAAADAF4AawwAAAMAXgBqDAAAAgBRAGwMAAACAFsAbQwAAAIAQQDqDAAABABhAG4MAAACAFIAbwwAAAEAUgAAAA==.Mawiyah:BAAALgAECgcJBwAAAA==.Max:BAAALgAECgYJEQABLgAFFAMJBQAYAI8OAA==.',
Me='Melarac:BAABLgAECn8VAAQGAAYJjQmkRQDNAAZoDAAABAAbAGkMAAAEABsAawwAAAQAEgBqDAAAAwAoAGwMAAABABYA6gwAAAUAGQAGAAYJjQmkRQDNAAZoDAAAAQAbAGkMAAABABsAawwAAAEAEgBqDAAAAQAoAGwMAAABABYA6gwAAAIAGQAHAAUJCAj+fACpAAVoDAAAAQAJAGkMAAABACAAawwAAAEADABqDAAAAQAjAOoMAAABAAwABQAFCdQGoEIAYQAFaAwAAAIAEwBpDAAAAgARAGsMAAACAA8AagwAAAEADQDqDAAAAgAQAAAA.',
Mi='Minibow:BAAALgAECgEJAQAAAA==.Minimagic:BAACLgAFFH8QAAIZAAQJNRzQPABRAQRoDAAABQBOAGkMAAAEAEwAawwAAAIATQDqDAAABQA4ABkABAk1HNA8AFEBBGgMAAAFAE4AaQwAAAQATABrDAAAAgBNAOoMAAAFADgALgAECn86AAIZAAkJBiRTCQAgAwAZAAkJBiRTCQAgAwAAAA==.',
Mo='Mogh:BAAALgAECgQJBQAAAA==.Monker:BAABLgAECn8hAAQMAAgJzh7PFQA7AghoDAAABgBjAGkMAAAFAGIAawwAAAYAYABqDAAAAwAWAGwMAAAEAF0AbQwAAAIALQDqDAAABgBfAG4MAAABAFEADAAHCa4ezxUAOwIHaAwAAAMAYwBpDAAAAwBiAGsMAAAEAGAAagwAAAEAFgBsDAAAAwBdAG0MAAACAC0A6gwAAAMAXwALAAUJ7hvcKwBBAQVoDAAAAgA7AGkMAAABAEQAawwAAAEAQwBqDAAAAQBDAOoMAAADAFoACgAGCYAVED4AIwEGaAwAAAEAPgBpDAAAAQBEAGsMAAABAD8AagwAAAEAQwBsDAAAAQAdAG4MAAABADMAAAA=.',
Mu='Muth:BAAALgAECgQJBgAAAA==.Muthra:BAAALgAECgEJAQABLgAECgQJBgASAAAAAA==.Muthroc:BAAALgAECgEJAQABLgAECgQJBgASAAAAAA==.',
My='Mysteria:BAAALgADCgIJAgAAAA==.',
Na='Nasara:BAABLgAECn82AAIZAAgJXyP7IADwAghoDAAACQBfAGkMAAAJAGEAawwAAAoAXQBqDAAACgBiAGwMAAAGAF0AbQwAAAEARQDqDAAABgBiAG4MAAADAFUAGQAICV8j+yAA8AIIaAwAAAkAXwBpDAAACQBhAGsMAAAKAF0AagwAAAoAYgBsDAAABgBdAG0MAAABAEUA6gwAAAYAYgBuDAAAAwBVAAAA.Nastylad:BAAALgADCgMJAwAAAA==.Nastyzoo:BAAALgAECgUJCAAAAA==.Natassia:BAAALgAECgIJAgAAAA==.',
Ne='Neceob:BAAALgADCgYJCAAAAA==.Nehemia:BAAALgADCgEJAQAAAA==.Nezukokamado:BAAALgADCgEJAQAAAA==.',
Ni='Nikallnight:BAAALgADCgYJBgAAAA==.Nimbus:BAAALgAECggJEAABLgAFFAgJGAAOAIUWAA==.',
No='Noodles:BAAALgADCgcJBwABLgAECgcJDQASAAAAAA==.Northstríder:BAAALgADCgMJAwAAAA==.Notloc:BAAALgAECgMJAwABLgAECgcJHQAKAD4kAA==.',
Ob='Oblivionpwr:BAAALgAECgEJAgABLgAECgkJOwAQAHUTAA==.',
On='Onomisar:BAAALgAECgUJCQAAAA==.',
Or='Oriah:BAAALgADCgMJAwAAAA==.',
Pa='Padtroll:BAAALgADCgQJBAAAAA==.Paliatarii:BAABLgAECn8bAAIXAAYJERa5kQAlAQZoDAAABgBKAGkMAAAGADgAawwAAAUAMgBqDAAAAgA0AGwMAAADADUA6gwAAAUALwAXAAYJERa5kQAlAQZoDAAABgBKAGkMAAAGADgAawwAAAUAMgBqDAAAAgA0AGwMAAADADUA6gwAAAUALwAAAA==.Pallyfever:BAAALgADCgkJEAAAAA==.',
Pu='Purple:BAAALgADCgMJAwABLgAECgcJHQAKAD4kAA==.',
Ra='Raging:BAAALgAECgMJBAAAAA==.',
Re='Remyxo:BAAALgAECgUJDgAAAA==.Repentia:BAAALgAFFAEJAQAAAA==.Revaneth:BAAALgADCgcJEwAAAA==.Revanoc:BAAALgAECgEJAQAAAA==.Revanon:BAAALgADCgYJBgAAAA==.',
Ro='Roidsnmolly:BAAALgAECgcJAgAAAA==.',
Ru='Runa:BAAALgAECgYJEwABLgAFFAQJDgAHAMAQAA==.',
Sa='Sadie:BAAALgAECgMJAgAAAA==.Sahlberg:BAAALgAECgcJDwAAAA==.Saphyra:BAAALgADCgUJBQABLgAECgYJGQAEAOQLAA==.',
Sc='Schiel:BAAALgAECgEJAwAAAA==.',
Se='Senkestsu:BAAALgAECgcJCwAAAA==.Seraphin:BAAALgAFFAIJAwAAAA==.Sezen:BAAALgAECgcJDgAAAA==.',
Sh='Shammtastiç:BAABLgAECn81AAIaAAkJIRe2GgDpAQloDAAACQBMAGkMAAAJAFIAawwAAAkATQBqDAAABQBBAGwMAAAEAC8AbQwAAAEACwDqDAAACgBRAG4MAAAFAEwAbwwAAAEAFQAaAAkJIRe2GgDpAQloDAAACQBMAGkMAAAJAFIAawwAAAkATQBqDAAABQBBAGwMAAAEAC8AbQwAAAEACwDqDAAACgBRAG4MAAAFAEwAbwwAAAEAFQAAAA==.Shandizard:BAAALgADCgkJDQAAAA==.Shivra:BAAALgAECgIJAwAAAA==.Shohei:BAAALgADCgcJBwAAAA==.Shulrukol:BAAALgAECgYJEAABLgAFFAgJIAAQACcdAA==.Shytownx:BAAALgAECgEJAQAAAA==.',
Si='Sinley:BAABLgAECn8lAAMXAAgJog0laAB6AQhoDAAABgAvAGkMAAAGAB4AawwAAAYAEwBqDAAABQAoAGwMAAAFADEAbQwAAAEAHwDqDAAABgAgAG4MAAACACEAFwAICaINJWgAegEIaAwAAAYALwBpDAAABQAeAGsMAAAGABMAagwAAAQAKABsDAAABQAxAG0MAAABAB8A6gwAAAUAIABuDAAAAgAhAAgAAwknBUoxACgAA2kMAAABABIAagwAAAEABQDqDAAAAQAIAAAA.',
Sn='Sncak:BAACLgAFFH8ZAAMCAAYJVhxlCAC2AQZoDAAABwBfAGkMAAAGAGEAawwAAAUASQBqDAAAAQAaAG0MAAABAAUA6gwAAAUAWwACAAYJVhxlCAC2AQZoDAAABwBfAGkMAAAFAGEAawwAAAUASQBqDAAAAQAaAG0MAAABAAUA6gwAAAUAWwADAAEJOQ08BgBcAAFpDAAAAQAhAC4ABAp/KgADAgAJCQ8kKAIAkAMAAgAJCQ8kKAIAkAMAAwAECb8bpA8AFgEAAAA=.',
So='Solvatod:BAAALgADCgIJAgAAAA==.Soyboiz:BAAALgAECgUJBwAAAA==.',
Sp='Spellslanger:BAAALgADCgYJBgAAAA==.Spiritwolf:BAACLgAFFH8GAAIEAAMJnQ/tCQDrAANoDAAAAwA6AGkMAAACACIA6gwAAAEAGwAEAAMJnQ/tCQDrAANoDAAAAwA6AGkMAAACACIA6gwAAAEAGwAuAAQKfxsAAgQACQn2ITsEAN0CAAQACQn2ITsEAN0CAAAA.',
St='Stanalli:BAAALgADCgIJAgAAAA==.',
Sw='Swagsauce:BAAALgADCgcJBwAAAA==.',
Sy='Sylvara:BAAALgAECgUJBQAAAA==.Symphony:BAAALgAECgQJCQAAAA==.Syrax:BAABLgAECn8fAAMPAAcJqhYcCQB/AQdoDAAABgBMAGkMAAAHAEEAawwAAAYAJwBqDAAABAA5AGwMAAADAEwA6gwAAAQATABuDAAAAQAOAA8ABgkIGhwJAH8BBmgMAAAGAEwAaQwAAAMAQQBrDAAAAwAmAGoMAAAEADkAbAwAAAMATADqDAAAAwBMAA4ABAlrDItWALYABGkMAAAEACQAawwAAAMAJwDqDAAAAQAlAG4MAAABAA4AAS4ABRQDCQUAGACPDgA=.Syrieal:BAACLgAFFH8FAAIYAAMJjw5KIACyAANoDAAAAgAoAGkMAAABABcA6gwAAAIALwAYAAMJjw5KIACyAANoDAAAAgAoAGkMAAABABcA6gwAAAIALwAuAAQKfzAAAxgACQlSGxkMACQCABgACQn3GhkMACQCAAgAAglCDoYoAEsAAAAA.',
Ta='Taiyla:BAABLgAECn81AAIZAAkJmxFsQwD8AQloDAAACAA9AGkMAAAHACcAawwAAAcAHABqDAAABwAyAGwMAAAGADwAbQwAAAQAKQDqDAAABwAzAG4MAAAFADkAbwwAAAIAEwAZAAkJmxFsQwD8AQloDAAACAA9AGkMAAAHACcAawwAAAcAHABqDAAABwAyAGwMAAAGADwAbQwAAAQAKQDqDAAABwAzAG4MAAAFADkAbwwAAAIAEwAAAA==.Talithiala:BAAALgAECgYJCQAAAA==.Tallai:BAAALgAECgEJAwAAAA==.Tash:BAABLgAECn8rAAMMAAgJExkqEwAzAghoDAAABwBMAGkMAAAFAEIAawwAAAUARQBqDAAABgBcAGwMAAAHAE0AbQwAAAMAHwDqDAAACABFAG4MAAACAB0ADAAICRMZKhMAMwIIaAwAAAUATABpDAAABABCAGsMAAAEAEUAagwAAAUAXABsDAAABQBNAG0MAAACAB8A6gwAAAYARQBuDAAAAgAdAAoABwmKCmRPAKcAB2gMAAACAB0AaQwAAAEAEgBrDAAAAQAGAGoMAAABACoAbAwAAAIATABtDAAAAQALAOoMAAACABMAAAA=.Taurelin:BAAALgAECgEJAQAAAA==.',
Te='Tejano:BAAALgAECggJEQAAAA==.',
Th='Thyra:BAAALgAECgUJBQABLgAFFAQJDgAHAMAQAA==.',
Tr='Trip:BAABLgAECn8kAAMbAAkJSgvvVgArAQloDAAABQAlAGkMAAAFAA4AawwAAAUAHABqDAAABAAjAGwMAAAEAB4AbQwAAAIAIwDqDAAABQApAG4MAAAEAA4AbwwAAAIAGAAbAAkJSgvvVgArAQloDAAABAAlAGkMAAAEAA4AawwAAAQAHABqDAAAAwAjAGwMAAACAB4AbQwAAAIAIwDqDAAAAgApAG4MAAACAA4AbwwAAAIAGAAcAAcJBw1CFgApAQdoDAAAAQAYAGkMAAABABcAawwAAAEAHwBqDAAAAQAXAGwMAAACACYA6gwAAAMAJQBuDAAAAgAtAAAA.',
Tu='Tubbybuddy:BAABLgAECn8WAAIcAAYJORmDEQBsAQZoDAAABQBYAGkMAAAEAFAAawwAAAQARQBqDAAAAwANAGwMAAACAAYA6gwAAAQATgAcAAYJORmDEQBsAQZoDAAABQBYAGkMAAAEAFAAawwAAAQARQBqDAAAAwANAGwMAAACAAYA6gwAAAQATgAAAA==.Tunafish:BAAALgADCgMJAwAAAA==.',
['Tö']='Töhru:BAAALgADCgEJAQAAAA==.',
Un='Uniboom:BAAALgADCgYJBgABLgAFFAcJHQAVABwcAA==.Unilock:BAABLgAECn8gAAIdAAkJshk0IgBHAgloDAAABQBdAGkMAAAFAF8AawwAAAQAUQBqDAAAAwBeAGwMAAAFAFsAbQwAAAEAAQDqDAAABQBXAG4MAAADAEkAbwwAAAEAAQAdAAkJshk0IgBHAgloDAAABQBdAGkMAAAFAF8AawwAAAQAUQBqDAAAAwBeAGwMAAAFAFsAbQwAAAEAAQDqDAAABQBXAG4MAAADAEkAbwwAAAEAAQABLgAFFAcJHQAVABwcAA==.Unipray:BAACLgAFFH8dAAMVAAcJHBxNAgAuAgdoDAAABgBAAGkMAAAGAF8AawwAAAUAOgBqDAAAAwBXAGwMAAABACsAbQwAAAEANgDqDAAABwBjABUABwkcHE0CAC4CB2gMAAAEAEAAaQwAAAUAXwBrDAAABAA6AGoMAAACAFcAbAwAAAEAKwBtDAAAAQA2AOoMAAAGAGMAEAAFCV4V7RIANQEFaAwAAAIAOgBpDAAAAQA0AGsMAAABACsAagwAAAEAHgDqDAAAAQBBAC4ABAp/JwADFQAJCbAiUAEAbwMAFQAJCbAiUAEAbwMAEAAHCeseiRkA3AEAAAA=.',
Va='Vamperella:BAABLgAECn8YAAIeAAYJcgFgDwBSAAZoDAAABgABAGkMAAAFAAUAawwAAAUABABqDAAAAQACAGwMAAABAAMA6gwAAAYAAwAeAAYJcgFgDwBSAAZoDAAABgABAGkMAAAFAAUAawwAAAUABABqDAAAAQACAGwMAAABAAMA6gwAAAYAAwAAAA==.',
Ve='Velkor:BAAALgAECgQJCAAAAA==.',
Vi='Vikings:BAAALgADCgIJAgAAAA==.',
Wa='Wanye:BAAALgADCgcJBwAAAA==.',
We='Wenzr:BAAALgAECgQJBgAAAA==.',
Wi='Willer:BAAALgADCgYJBgAAAA==.',
Wu='Wumbo:BAAALgAECgIJAgABLgAFFAcJIQAXALgkAA==.',
Ye='Yefercas:BAAALgAECgUJCgAAAA==.',
Yi='Yiumi:BAABLgAECn84AAIfAAkJGRa6AQBMAgloDAAACAA4AGkMAAAIAE0AawwAAAgASgBqDAAABgAcAGwMAAAGADsAbQwAAAYAKADqDAAACABKAG4MAAAFACgAbwwAAAEAHQAfAAkJGRa6AQBMAgloDAAACAA4AGkMAAAIAE0AawwAAAgASgBqDAAABgAcAGwMAAAGADsAbQwAAAYAKADqDAAACABKAG4MAAAFACgAbwwAAAEAHQAAAA==.',
Yl='Ylvis:BAABLgAECn8oAAIWAAgJogcOZQBVAQhoDAAABQASAGkMAAAGABgAawwAAAgAEwBqDAAABAAeAGwMAAAFABwAbQwAAAQADADqDAAABAAPAG4MAAAEABIAFgAICaIHDmUAVQEIaAwAAAUAEgBpDAAABgAYAGsMAAAIABMAagwAAAQAHgBsDAAABQAcAG0MAAAEAAwA6gwAAAQADwBuDAAABAASAAAA.',
Yo='You:BAABLgAECn8kAAIYAAkJsxeFEQDMAQloDAAABQArAGkMAAAFAFAAawwAAAUATABqDAAABABZAGwMAAAEADkAbQwAAAIAGgDqDAAABQA8AG4MAAAEAEMAbwwAAAIASAAYAAkJsxeFEQDMAQloDAAABQArAGkMAAAFAFAAawwAAAUATABqDAAABABZAGwMAAAEADkAbQwAAAIAGgDqDAAABQA8AG4MAAAEAEMAbwwAAAIASAAAAA==.',
Yu='Yulogee:BAABLgAFFH8FAAMYAAMJ/hs2GQDqAANoDAAAAgAzAGkMAAABAFAA6gwAAAIAUgAYAAMJ/hs2GQDqAANoDAAAAgAzAGkMAAABAFAA6gwAAAEAUgAXAAEJ4wLD5QA8AAHqDAAAAQAHAAAA.Yurdead:BAAALgADCgYJBgABLgAECgEJAQASAAAAAA==.',
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
