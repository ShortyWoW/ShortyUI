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

local lookup = {'Warlock-Destruction','Warrior-Fury','Rogue-Subtlety','Rogue-Assassination','Druid-Feral','Druid-Guardian','Druid-Balance','Druid-Restoration','DeathKnight-Frost','DemonHunter-Devourer','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','Warrior-Protection','Evoker-Augmentation','Evoker-Devastation','Priest-Shadow','Paladin-Retribution','Paladin-Protection','Unknown-Unknown','Paladin-Holy','Priest-Discipline','Priest-Holy','Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Blood','Mage-Frost','Mage-Arcane','Warrior-Arms','Shaman-Elemental','Shaman-Restoration','Shaman-Enhancement','Warlock-Demonology','Mage-Fire',}
local provider = {region='US',realm='Kalecgos',name='US',type='daily',zone=46,date='2026-05-31',data={Aa='Aamon:BAAALgADCgUJBQAAAA==.Aarius:BAAALgAECgQJBAAAAA==.',
Ae='Aerius:BAAALgADCgYJBAAAAA==.',
Am='Amen:BAAALgADCgEJAQAAAA==.',
Ao='Ao:BAAALgAECgQJCwAAAA==.',
Au='Augmentation:BAAALgAECgIJAwAAAA==.Aurumursi:BAAALgADCgcJBwAAAA==.',
Av='Aviandraka:BAAALgADCgEJAQAAAA==.',
Ba='Baeroch:BAAALgADCgEJAQAAAA==.Barlartwo:BAAALgAECggJDAAAAA==.Bazthrax:BAAALgAECgQJBQAAAA==.Baztinel:BAAALgADCgkJCQAAAA==.Bazty:BAAALgAECgYJDgAAAA==.',
Be='Belthazaar:BAABLgAECn8UAAIBAAYJTQFnNABBAAZoDAAABQADAGkMAAADAAIAawwAAAMABABqDAAAAgACAGwMAAACAAMA6gwAAAUAAwABAAYJTQFnNABBAAZoDAAABQADAGkMAAADAAIAawwAAAMABABqDAAAAgACAGwMAAACAAMA6gwAAAUAAwAAAA==.',
Bi='Biller:BAAALgADCgYJBgAAAA==.',
Bl='Blade:BAACLgAFFH8KAAICAAMJzh3+KADvAANoDAAABQBXAGkMAAADAE4A6gwAAAIAPgACAAMJzh3+KADvAANoDAAABQBXAGkMAAADAE4A6gwAAAIAPgAuAAQKfx0AAgIACAnWIsEXAB4CAAIACAnWIsEXAB4CAAAA.Blarneystone:BAAALgAECgYJDwAAAA==.Bluemoon:BAAALgADCgYJDAAAAA==.',
Bo='Bootybleaps:BAAALgAFFAIJAgAAAA==.Bootybsneaks:BAACLgAFFH8hAAIDAAYJziL9BgDyAQZoDAAACABaAGkMAAAIAGAAawwAAAYAUABqDAAABABFAGwMAAABAFAA6gwAAAYAYQADAAYJziL9BgDyAQZoDAAACABaAGkMAAAIAGAAawwAAAYAUABqDAAABABFAGwMAAABAFAA6gwAAAYAYQAuAAQKfzUAAwMACQkiIwgEAPACAAMACQkiIwgEAPACAAQAAQl8Fv0iADoAAAAA.',
Br='Bramble:BAAALgADCgIJAgAAAA==.Brynhild:BAABLgAECn8ZAAIFAAYJ5AvAIQDWAAZoDAAABQApAGkMAAAFABgAawwAAAQAFgBqDAAABAAdAGwMAAAEAB8A6gwAAAMAIAAFAAYJ5AvAIQDWAAZoDAAABQApAGkMAAAFABgAawwAAAQAFgBqDAAABAAdAGwMAAAEAB8A6gwAAAMAIAAAAA==.',
Bu='Bullfist:BAAALgAECgYJEAABLgAECggJJAAGABocAA==.Bullievit:BAACLgAFFH8JAAIHAAQJyBNXGwAYAQRoDAAAAwA8AGkMAAABACkAawwAAAIAHQDqDAAAAwBHAAcABAnIE1cbABgBBGgMAAADADwAaQwAAAEAKQBrDAAAAgAdAOoMAAADAEcALgAECn8kAAMHAAkJXh3LGADvAQAHAAkJXh3LGADvAQAIAAQJLQU8ngCOAAAAAA==.',
Ca='Calssara:BAAALgADCgEJAQAAAA==.',
Ce='Cerealkìller:BAABLgAECn89AAIJAAkJRBH6CADNAQloDAAACAArAGkMAAAIACYAawwAAAcAKgBqDAAACAAtAGwMAAAHADQAbQwAAAYAIADqDAAACAAkAG4MAAAGAFgAbwwAAAMAEwAJAAkJRBH6CADNAQloDAAACAArAGkMAAAIACYAawwAAAcAKgBqDAAACAAtAGwMAAAHADQAbQwAAAYAIADqDAAACAAkAG4MAAAGAFgAbwwAAAMAEwAAAA==.',
Ch='Chaostheory:BAAALgAECgEJAgABLgAFFAMJCgACAM4dAA==.Chaozz:BAABLgAECn8YAAIKAAYJXyIQPwD4AQZoDAAABABjAGkMAAAEAFUAawwAAAQAWABqDAAABABIAGwMAAAEAEoA6gwAAAQAWwAKAAYJXyIQPwD4AQZoDAAABABjAGkMAAAEAFUAawwAAAQAWABqDAAABABIAGwMAAAEAEoA6gwAAAQAWwAAAA==.Chichi:BAAALgAECgIJAgAAAA==.Chistery:BAAALgAECgUJCQAAAA==.Chunly:BAABLgAECn8cAAQLAAkJmhPfFQDzAQloDAAAAwA7AGkMAAAFAD0AawwAAAUAMQBqDAAAAwAwAGwMAAABACkAbQwAAAEAGwDqDAAABQBBAG4MAAAEADcAbwwAAAEAKQALAAkJmhPfFQDzAQloDAAAAwA7AGkMAAADAD0AawwAAAMAMQBqDAAAAgAwAGwMAAABACkAbQwAAAEAGwDqDAAABQBBAG4MAAAEADcAbwwAAAEAKQAMAAMJIg65ZwBoAANpDAAAAQAcAGsMAAABACsAagwAAAEAGQANAAIJmwQmZABAAAJpDAAAAQALAGsMAAABAAsAAAA=.',
Cl='Clovicta:BAAALgADCgQJBAAAAA==.',
Cm='Cmoobones:BAABLgAECn8VAAIOAAgJRw+kGQBYAQhoDAAAAwA9AGkMAAADAB0AawwAAAMAJwBqDAAAAwA9AGwMAAADADAAbQwAAAEAGQDqDAAABAAoAG4MAAABABwADgAICUcPpBkAWAEIaAwAAAMAPQBpDAAAAwAdAGsMAAADACcAagwAAAMAPQBsDAAAAwAwAG0MAAABABkA6gwAAAQAKABuDAAAAQAcAAAA.',
Co='Colokush:BAAALgADCgcJBwAAAA==.Constantine:BAAALgADCgEJAQABLgAECgcJHQALAD4kAA==.',
Cr='Crisgard:BAAALgAECgQJDgAAAA==.Cronos:BAABLgAECn8rAAMPAAkJcBMfHQDWAQloDAAABwA2AGkMAAAFADkAawwAAAYANwBqDAAABgA2AGwMAAAGADUAbQwAAAMAIQDqDAAABwBEAG4MAAACABgAbwwAAAEAMgAPAAkJkBEfHQDWAQloDAAABQA2AGkMAAAFADkAawwAAAYANwBqDAAABQA2AGwMAAAFADMAbQwAAAIAGwDqDAAABgAmAG4MAAABABgAbwwAAAEAMgAQAAYJcBAdDgAZAQZoDAAAAgAuAGoMAAABACAAbAwAAAEANQBtDAAAAQAhAOoMAAABAEQAbgwAAAEABwAAAA==.Cropop:BAAALgAECgIJAgAAAA==.Crow:BAAALgAECgkJBAAAAA==.Crysalus:BAAALgAECgEJAQAAAA==.',
Da='Dacian:BAAALgAECggJDwAAAA==.Darallyn:BAAALgAECgYJEwAAAA==.Davik:BAABLgAECn8YAAIRAAYJ/gymPwDvAAZoDAAABgAkAGkMAAAGABEAawwAAAUAHQBqDAAAAQAiAGwMAAABACYA6gwAAAUAKwARAAYJ/gymPwDvAAZoDAAABgAkAGkMAAAGABEAawwAAAUAHQBqDAAAAQAiAGwMAAABACYA6gwAAAUAKwAAAA==.Davinah:BAAALgADCgUJCQAAAA==.',
De='Deathcharger:BAAALgAECgMJAwAAAA==.Demonicaxe:BAAALgADCgkJCQAAAA==.Devïl:BAAALgAECgQJBwAAAA==.',
Di='Dingbat:BAAALgADCgEJAQAAAA==.',
Do='Dog:BAAALgAECggJBgAAAA==.Dollfie:BAAALgAECgIJAgAAAA==.Doser:BAABLgAECn8XAAISAAgJgwxuiABFAQhoDAAABABEAGkMAAAFACAAawwAAAQAHQBqDAAAAwA2AGwMAAADAB0AbQwAAAEAGgDqDAAAAgAUAG4MAAABABIAEgAICYMMbogARQEIaAwAAAQARABpDAAABQAgAGsMAAAEAB0AagwAAAMANgBsDAAAAwAdAG0MAAABABoA6gwAAAIAFABuDAAAAQASAAAA.',
Dr='Dracarsynimz:BAAALgAFFAIJAgABLgAFFAUJFAAPAEILAQ==.Dracene:BAABLgAECn8VAAITAAgJVAe1IQDtAAhoDAAABAAmAGkMAAAEABIAawwAAAQACABqDAAAAQAUAGwMAAACAB0AbQwAAAEACQDqDAAABAAMAG4MAAABAA4AEwAICVQHtSEA7QAIaAwAAAQAJgBpDAAABAASAGsMAAAEAAgAagwAAAEAFABsDAAAAgAdAG0MAAABAAkA6gwAAAQADABuDAAAAQAOAAAA.Dragosa:BAAALgADCgMJAwABLgAFFAEJAQAUAAAAAA==.',
Du='Duf:BAAALgAECgEJBAAAAA==.',
Dy='Dynasty:BAAALgAECgQJBAAAAA==.',
Eb='Eblazed:BAAALgADCgMJAwAAAA==.',
Fe='Feraldruid:BAAALgAECgMJAwAAAA==.',
Fi='Fisten:BAAALgAECgYJBgAAAA==.',
Fl='Flixs:BAAALgAECgEJAQABLgAECgUJDAAUAAAAAA==.',
Fo='Foxcraft:BAABLgAECn8aAAMNAAkJvB4OBQAUAwloDAAAAwBfAGkMAAADAFwAawwAAAMAXgBqDAAABQBZAGwMAAADAEgAbQwAAAEAPQDqDAAABQBTAG4MAAACADUAbwwAAAEAQQANAAkJvB4OBQAUAwloDAAAAwBfAGkMAAADAFwAawwAAAMAXgBqDAAABQBZAGwMAAADAEgAbQwAAAEAPQDqDAAABQBTAG4MAAABADUAbwwAAAEAQQAMAAEJZQrEhQA7AAFuDAAAAQAaAAAA.',
Fr='Friëren:BAAALgAECgQJBQAAAA==.Frostfire:BAAALgAECgEJAQAAAA==.',
Ga='Gamera:BAAALgAECgUJCgAAAA==.Gangstabarny:BAAALgAECgEJAQAAAA==.Gankadin:BAABLgAECn8WAAMVAAgJkxRHHAANAghoDAAAAwBKAGkMAAADAFIAawwAAAMANwBqDAAAAwAfAGwMAAADAEwAbQwAAAEAJADqDAAABQAwAG4MAAABAA4AFQAICZMURxwADQIIaAwAAAIASgBpDAAAAwBSAGsMAAADADcAagwAAAMAHwBsDAAAAwBMAG0MAAABACQA6gwAAAUAMABuDAAAAQAOABIAAQnxBLqhARwAAWgMAAABAAwAAAA=.',
Gb='Gb:BAACLgAFFH8NAAMRAAQJ8hplHQDkAARoDAAABQBZAGkMAAAEAC0AawwAAAIATgDqDAAAAgA+ABEAAwmwGWUdAOQAA2gMAAAEAFkAaQwAAAIALQDqDAAAAgA+ABYAAwnJDzMoANUAA2gMAAABACQAaQwAAAIAKQBrDAAAAgArAC4ABAp/KAAEFgAJCUodDQcA8gIAFgAJCUodDQcA8gIAEQAICeUcAw4AowIAFwACCTkIMnEAYgAAAAA=.',
Gi='Giffca:BAAALgAECgYJDgAAAA==.',
Gr='Groobel:BAAALgAECgEJAwAAAA==.Groobs:BAAALgAECgEJBwAAAA==.',
Gu='Gunhyrr:BAAALgAFFAEJAQAAAA==.',
Ho='Holycow:BAAALgAECgUJBQABLgAECggJMAALABQXAA==.',
Hu='Humanmatt:BAAALgAECgQJBgAAAA==.',
Hy='Hydra:BAAALgAECgkJBAAAAA==.',
Ic='Icewolff:BAAALgAECgUJBwAAAA==.',
Ik='Ikinokoru:BAACLgAFFH8IAAIYAAMJcST9NwAjAQNoDAAAAwBfAGkMAAACAFwA6gwAAAMAWwAYAAMJcST9NwAjAQNoDAAAAwBfAGkMAAACAFwA6gwAAAMAWwAuAAQKf0EAAhgACAn4JUUJAP0CABgACAn4JUUJAP0CAAAA.',
In='Inyànga:BAAALgAECgMJAwAAAA==.',
Je='Jeffren:BAAALgAECgUJDAAAAA==.',
Ji='Jinsho:BAAALgAECggJCAAAAA==.',
Jy='Jyve:BAAALgADCgcJBwABLgAECgkJIgAYAHwbAA==.',
Ka='Kalal:BAAALgADCgYJBwAAAA==.',
Ke='Keg:BAABLgAECn8dAAILAAcJPiQcEAB+AgdoDAAABQBgAGkMAAAFAGEAawwAAAUAYgBqDAAABABfAGwMAAAEAFgAbQwAAAEAVwDqDAAABQBYAAsABwk+JBwQAH4CB2gMAAAFAGAAaQwAAAUAYQBrDAAABQBiAGoMAAAEAF8AbAwAAAQAWABtDAAAAQBXAOoMAAAFAFgAAAA=.Keygunmonk:BAAALgADCgcJBwAAAA==.',
Ko='Kovowolf:BAACLgAFFH8QAAIIAAUJaw/5HwA/AQVoDAAABQA/AGkMAAAFADwAawwAAAIAFgBqDAAAAQAEAOoMAAADAC8ACAAFCWsP+R8APwEFaAwAAAUAPwBpDAAABQA8AGsMAAACABYAagwAAAEABADqDAAAAwAvAC4ABAp/LwACCAAJCbMh8wQAXgMACAAJCbMh8wQAXgMAAAA=.',
Kr='Krazedwolf:BAACLgAFFH8HAAISAAUJzBHZNAAsAQVoDAAAAgBUAGkMAAACACMAawwAAAEAGgBqDAAAAQAkAOoMAAABACIAEgAFCcwR2TQALAEFaAwAAAIAVABpDAAAAgAjAGsMAAABABoAagwAAAEAJADqDAAAAQAiAC4ABAp/KAACEgAJCUYhgxMAugIAEgAJCUYhgxMAugIAAAA=.',
Kv='Kvn:BAAALgAECgUJBgAAAA==.',
Le='Leatherpapi:BAAALgAECgUJBQAAAA==.Lehran:BAAALgAECgUJCAAAAA==.Lemonator:BAAALgAECgQJBQAAAA==.Lemynaid:BAAALgAECgYJDgAAAA==.',
Li='Linsay:BAACLgAFFH8gAAIRAAgJJx33AACmAghoDAAABgBjAGkMAAAFAGIAawwAAAUAXABqDAAABQBjAGwMAAACAFcAbQwAAAEAGADqDAAABwBkAG4MAAABABMAEQAICScd9wAApgIIaAwAAAYAYwBpDAAABQBiAGsMAAAFAFwAagwAAAUAYwBsDAAAAgBXAG0MAAABABgA6gwAAAcAZABuDAAAAQATAC4ABAp/NwACEQAJCSUmQAEAwAMAEQAJCSUmQAEAwAMAAAA=.',
Lo='Lokagdai:BAAALgAECgEJAgAAAA==.Lotieos:BAABLgAECn8bAAIZAAYJMQ63qgAIAQZoDAAABwAkAGkMAAAHAC4AawwAAAUAIABqDAAAAQAOAGwMAAABAAwA6gwAAAYANgAZAAYJMQ63qgAIAQZoDAAABwAkAGkMAAAHAC4AawwAAAUAIABqDAAAAQAOAGwMAAABAAwA6gwAAAYANgAAAA==.Lovelypwr:BAABLgAECn89AAMRAAkJdRPEGADmAQloDAAACgA9AGkMAAAHADwAawwAAAYAJgBqDAAABQAiAGwMAAAHADsAbQwAAAYAKQDqDAAADABEAG4MAAAFABgAbwwAAAMAKwARAAkJdRPEGADmAQloDAAACgA9AGkMAAAHADwAawwAAAYAJgBqDAAABQAiAGwMAAAHADsAbQwAAAYAKQDqDAAACwBEAG4MAAAFABgAbwwAAAMAKwAWAAEJSwznbQAwAAHqDAAAAQAfAAAA.',
Ma='Mannera:BAABLgAFFH8GAAIWAAMJihZWJwDeAANoDAAAAgA3AGkMAAACADUA6gwAAAIAQAAWAAMJihZWJwDeAANoDAAAAgA3AGkMAAACADUA6gwAAAIAQAAAAA==.Manzio:BAAALgADCgQJBAAAAA==.Marcus:BAAALgAFFAEJAQAAAA==.Matheris:BAABLgAECn8YAAIOAAkJZiLoBAC/AgloDAAABQBfAGkMAAADAF4AawwAAAMAXgBqDAAAAgBRAGwMAAACAFsAbQwAAAIAQQDqDAAABABhAG4MAAACAFIAbwwAAAEAUgAOAAkJZiLoBAC/AgloDAAABQBfAGkMAAADAF4AawwAAAMAXgBqDAAAAgBRAGwMAAACAFsAbQwAAAIAQQDqDAAABABhAG4MAAACAFIAbwwAAAEAUgAAAA==.Mawiyah:BAAALgAECgcJBwAAAA==.Max:BAABLgAECn8aAAIOAAkJHx6ZBADHAgloDAAABABaAGkMAAAEAFwAawwAAAQAXABqDAAABABRAGwMAAAEAEoAbQwAAAEAOQDqDAAAAwBPAG4MAAABAFkAbwwAAAEAKAAOAAkJHx6ZBADHAgloDAAABABaAGkMAAAEAFwAawwAAAQAXABqDAAABABRAGwMAAAEAEoAbQwAAAEAOQDqDAAAAwBPAG4MAAABAFkAbwwAAAEAKAABLgAFFAMJCAAaAGESAA==.',
Me='Melarac:BAABLgAECn8VAAQHAAYJjQkISQDNAAZoDAAABAAbAGkMAAAEABsAawwAAAQAEgBqDAAAAwAoAGwMAAABABYA6gwAAAUAGQAHAAYJjQkISQDNAAZoDAAAAQAbAGkMAAABABsAawwAAAEAEgBqDAAAAQAoAGwMAAABABYA6gwAAAIAGQAIAAUJCAixgACpAAVoDAAAAQAJAGkMAAABACAAawwAAAEADABqDAAAAQAjAOoMAAABAAwABgAFCdQGu0gAYQAFaAwAAAIAEwBpDAAAAgARAGsMAAACAA8AagwAAAEADQDqDAAAAgAQAAAA.',
Mi='Minibow:BAAALgAECgEJAQAAAA==.Minimagic:BAACLgAFFH8UAAMbAAQJNRwNRABFAQRoDAAABgBOAGkMAAAFAEwAawwAAAMATQDqDAAABgA4ABsABAk1HA1EAEUBBGgMAAAFAE4AaQwAAAUATABrDAAAAwBNAOoMAAAGADgAHAABCQQICQUAQAABaAwAAAEAFAAuAAQKfzwAAhsACQlIJIcIACUDABsACQlIJIcIACUDAAAA.',
Mo='Mogh:BAAALgAECgQJBQAAAA==.Monker:BAABLgAECn8hAAQNAAgJzh7PFwA3AghoDAAABgBjAGkMAAAFAGIAawwAAAYAYABqDAAAAwAWAGwMAAAEAF0AbQwAAAIALQDqDAAABgBfAG4MAAABAFEADQAHCa4ezxcANwIHaAwAAAMAYwBpDAAAAwBiAGsMAAAEAGAAagwAAAEAFgBsDAAAAwBdAG0MAAACAC0A6gwAAAMAXwAMAAUJ7hu8LQA/AQVoDAAAAgA7AGkMAAABAEQAawwAAAEAQwBqDAAAAQBDAOoMAAADAFoACwAGCYAVED4AIwEGaAwAAAEAPgBpDAAAAQBEAGsMAAABAD8AagwAAAEAQwBsDAAAAQAdAG4MAAABADMAAAA=.',
Mu='Muth:BAAALgAECgQJBgAAAA==.Muthra:BAAALgAECgEJAQABLgAECgQJBgAUAAAAAA==.Muthroc:BAAALgAECgEJAQABLgAECgQJBgAUAAAAAA==.',
My='Mysteria:BAAALgADCgIJAgAAAA==.',
Na='Nasara:BAACLgAFFH8GAAIbAAIJTBs2hgCkAAJoDAAAAwBEAOoMAAADAEYAGwACCUwbNoYApAACaAwAAAMARADqDAAAAwBGAC4ABAp/OAACGwAICV8j+yAA8AIAGwAICV8j+yAA8AIAAAA=.Nastylad:BAAALgADCgMJAwAAAA==.Nastyzoo:BAAALgAECgUJCAAAAA==.Natassia:BAAALgAECgIJAgAAAA==.',
Ne='Neceob:BAAALgADCgYJCAAAAA==.Nehemia:BAAALgAECgcJBwAAAA==.Nezukokamado:BAAALgAECgYJBwAAAA==.',
Ni='Nikallnight:BAAALgADCgYJBgAAAA==.Nimbus:BAAALgAFFAQJBAABLgAFFAgJHgAPAPIbAA==.',
No='Noodles:BAAALgADCgcJBwABLgAECgcJDQAUAAAAAA==.Northstríder:BAAALgADCgMJAwAAAA==.Notloc:BAAALgAECgMJAwABLgAECgcJHQALAD4kAA==.',
Ob='Oblivionpwr:BAAALgAECgEJAwABLgAECgkJPQARAHUTAA==.',
On='Onomisar:BAAALgAECgUJCQAAAA==.',
Or='Oriah:BAAALgADCgUJBQAAAA==.',
Pa='Padtroll:BAAALgADCgQJBAAAAA==.Paliatarii:BAABLgAECn8dAAIZAAgJnxSNVwCtAQhoDAAABgBKAGkMAAAGADgAawwAAAUAMgBqDAAAAgA0AGwMAAADADUA6gwAAAUALwBuDAAAAQAzAG8MAAABACQAGQAICZ8UjVcArQEIaAwAAAYASgBpDAAABgA4AGsMAAAFADIAagwAAAIANABsDAAAAwA1AOoMAAAFAC8AbgwAAAEAMwBvDAAAAQAkAAAA.Pallyfever:BAAALgADCgkJEAAAAA==.',
Pu='Purple:BAAALgADCgMJAwABLgAECgcJHQALAD4kAA==.',
Ra='Raging:BAAALgAECgMJBAAAAA==.',
Re='Remyxo:BAABLgAECn8VAAMdAAgJfRqOCgApAghoDAAABABcAGkMAAAEAFcAawwAAAQAMABqDAAAAQBeAGwMAAACAEkAbQwAAAEAHQDqDAAABABaAG4MAAABADUAHQAICX0ajgoAKQIIaAwAAAQAXABpDAAAAwBXAGsMAAAEADAAagwAAAEAXgBsDAAAAgBJAG0MAAABAB0A6gwAAAQAWgBuDAAAAQA1AAIAAQntGVuLAEAAAWkMAAABAEIAAAA=.Repentia:BAAALgAFFAEJAQAAAA==.Revaneth:BAAALgADCgcJEwAAAA==.Revanoc:BAAALgAECgMJBAAAAA==.Revanon:BAAALgADCgYJBgAAAA==.',
Ro='Rockaden:BAAALgADCgUJBQABLgAECgQJBgAUAAAAAA==.Roidsnmolly:BAAALgAECgcJAgAAAA==.',
Ru='Runa:BAAALgAECgYJEwABLgAFFAUJEAAIAGsPAA==.',
Sa='Sadie:BAAALgAECgMJAgAAAA==.Sahlberg:BAAALgAECgcJDwAAAA==.Saphyra:BAAALgADCgUJBQABLgAECgYJGQAFAOQLAA==.',
Sc='Schiel:BAAALgAECgEJAwAAAA==.',
Se='Senkestsu:BAAALgAECggJDAAAAA==.Seraphin:BAAALgAFFAIJAwAAAA==.Sezen:BAAALgAECgcJDgAAAA==.',
Sh='Shammtastiç:BAABLgAECn86AAIeAAkJThdXGQACAgloDAAACgBPAGkMAAAKAFIAawwAAAoATQBqDAAABgBCAGwMAAAFAC8AbQwAAAEACwDqDAAACgBRAG4MAAAFAEwAbwwAAAEAFQAeAAkJThdXGQACAgloDAAACgBPAGkMAAAKAFIAawwAAAoATQBqDAAABgBCAGwMAAAFAC8AbQwAAAEACwDqDAAACgBRAG4MAAAFAEwAbwwAAAEAFQAAAA==.Shandizard:BAAALgADCgkJDQAAAA==.Shivra:BAAALgAECgIJAwAAAA==.Shohei:BAAALgADCgcJBwAAAA==.Shulrukol:BAAALgAECgYJEAABLgAFFAgJIAARACcdAA==.Shytownx:BAAALgAECgEJAQAAAA==.',
Si='Sinley:BAABLgAECn8lAAMZAAgJog3jbQB3AQhoDAAABgAvAGkMAAAGAB4AawwAAAYAEwBqDAAABQAoAGwMAAAFADEAbQwAAAEAHwDqDAAABgAgAG4MAAACACEAGQAICaIN420AdwEIaAwAAAYALwBpDAAABQAeAGsMAAAGABMAagwAAAQAKABsDAAABQAxAG0MAAABAB8A6gwAAAUAIABuDAAAAgAhAAkAAwknBT81ACgAA2kMAAABABIAagwAAAEABQDqDAAAAQAIAAAA.',
Sn='Sncak:BAACLgAFFH8eAAMDAAYJVhx4CgCqAQZoDAAACABfAGkMAAAHAGEAawwAAAYASQBqDAAAAgAgAG0MAAABAAUA6gwAAAYAWwADAAYJVhx4CgCqAQZoDAAACABfAGkMAAAGAGEAawwAAAYASQBqDAAAAgAgAG0MAAABAAUA6gwAAAYAWwAEAAEJOQ08BgBcAAFpDAAAAQAhAC4ABAp/KgADAwAJCQ8kKAIAkAMAAwAJCQ8kKAIAkAMABAAECb8bpA8AFgEAAAA=.',
So='Solvatod:BAAALgADCgIJAgAAAA==.Soyboiz:BAAALgAECgUJBwAAAA==.',
Sp='Spellslanger:BAAALgADCgYJBgAAAA==.Spiritwolf:BAACLgAFFH8IAAIFAAQJ2g+PCwDWAARoDAAAAwA6AGkMAAACACIAagwAAAEANwDqDAAAAgAdAAUABAnaD48LANYABGgMAAADADoAaQwAAAIAIgBqDAAAAQA3AOoMAAACAB0ALgAECn8bAAIFAAkJ9iE7BADdAgAFAAkJ9iE7BADdAgAAAA==.',
St='Stanalli:BAAALgADCgIJAgAAAA==.',
Sw='Swagsauce:BAAALgAECgcJBwAAAA==.',
Sy='Sylvara:BAAALgAECgUJBQAAAA==.Symphony:BAAALgAECgUJDQAAAA==.Syrax:BAABLgAECn8fAAMQAAcJqhZ7CQB8AQdoDAAABgBMAGkMAAAHAEEAawwAAAYAJwBqDAAABAA5AGwMAAADAEwA6gwAAAQATABuDAAAAQAOABAABgkIGnsJAHwBBmgMAAAGAEwAaQwAAAMAQQBrDAAAAwAmAGoMAAAEADkAbAwAAAMATADqDAAAAwBMAA8ABAlrDC9XALIABGkMAAAEACQAawwAAAMAJwDqDAAAAQAlAG4MAAABAA4AAS4ABRQDCQgAGgBhEgA=.Syrieal:BAACLgAFFH8IAAIaAAMJYRLiIQC1AANoDAAAAwAoAGkMAAACADUA6gwAAAMALwAaAAMJYRLiIQC1AANoDAAAAwAoAGkMAAACADUA6gwAAAMALwAuAAQKfzcAAxoACQmfHDgNAB4CABoACQn3GjgNAB4CAAkABwnHGL4JALsBAAAA.',
Ta='Taiyla:BAABLgAECn81AAIbAAkJmxGBRgDyAQloDAAACAA9AGkMAAAHACcAawwAAAcAHABqDAAABwAyAGwMAAAGADwAbQwAAAQAKQDqDAAABwAzAG4MAAAFADkAbwwAAAIAEwAbAAkJmxGBRgDyAQloDAAACAA9AGkMAAAHACcAawwAAAcAHABqDAAABwAyAGwMAAAGADwAbQwAAAQAKQDqDAAABwAzAG4MAAAFADkAbwwAAAIAEwAAAA==.Talithiala:BAAALgAECgYJCQAAAA==.Tallai:BAAALgAECgEJAwAAAA==.Tash:BAABLgAECn8rAAMNAAgJExkqEwAzAghoDAAABwBMAGkMAAAFAEIAawwAAAUARQBqDAAABgBcAGwMAAAHAE0AbQwAAAMAHwDqDAAACABFAG4MAAACAB0ADQAICRMZKhMAMwIIaAwAAAUATABpDAAABABCAGsMAAAEAEUAagwAAAUAXABsDAAABQBNAG0MAAACAB8A6gwAAAYARQBuDAAAAgAdAAsABwmKCgNUAKYAB2gMAAACAB0AaQwAAAEAEgBrDAAAAQAGAGoMAAABACoAbAwAAAIATABtDAAAAQALAOoMAAACABMAAAA=.Taurelin:BAAALgAECgEJAQAAAA==.',
Te='Tejano:BAAALgAECggJEQAAAA==.',
Th='Therionwolf:BAAALgAECgEJAgAAAA==.Thyra:BAAALgAECgUJBQABLgAFFAUJEAAIAGsPAA==.',
Tr='Trip:BAABLgAECn8kAAMfAAkJSgvvVgArAQloDAAABQAlAGkMAAAFAA4AawwAAAUAHABqDAAABAAjAGwMAAAEAB4AbQwAAAIAIwDqDAAABQApAG4MAAAEAA4AbwwAAAIAGAAfAAkJSgvvVgArAQloDAAABAAlAGkMAAAEAA4AawwAAAQAHABqDAAAAwAjAGwMAAACAB4AbQwAAAIAIwDqDAAAAgApAG4MAAACAA4AbwwAAAIAGAAgAAcJBw3/FwApAQdoDAAAAQAYAGkMAAABABcAawwAAAEAHwBqDAAAAQAXAGwMAAACACYA6gwAAAMAJQBuDAAAAgAtAAAA.',
Ts='Tsty:BAAALgADCgQJBAAAAA==.',
Tu='Tubbybuddy:BAABLgAECn8WAAIgAAYJORn+EgBpAQZoDAAABQBYAGkMAAAEAFAAawwAAAQARQBqDAAAAwANAGwMAAACAAYA6gwAAAQATgAgAAYJORn+EgBpAQZoDAAABQBYAGkMAAAEAFAAawwAAAQARQBqDAAAAwANAGwMAAACAAYA6gwAAAQATgAAAA==.Tunafish:BAAALgADCgMJAwAAAA==.',
['Tö']='Töhru:BAAALgADCgEJAQAAAA==.',
Un='Uniboom:BAAALgADCgYJBgABLgAFFAcJIgAXABwcAA==.Unilock:BAACLgAFFH8HAAIhAAQJthNoPQA1AQRoDAAAAgAsAGkMAAACAFIAawwAAAEALwDqDAAAAgAbACEABAm2E2g9ADUBBGgMAAACACwAaQwAAAIAUgBrDAAAAQAvAOoMAAACABsALgAECn8gAAIhAAkJshlLJABCAgAhAAkJshlLJABCAgABLgAFFAcJIgAXABwcAA==.Unipray:BAACLgAFFH8iAAMXAAcJHBz9AgAhAgdoDAAABwBAAGkMAAAHAF8AawwAAAYAOgBqDAAABABXAGwMAAABACsAbQwAAAEANgDqDAAACABjABcABwkcHP0CACECB2gMAAAEAEAAaQwAAAUAXwBrDAAABAA6AGoMAAADAFcAbAwAAAEAKwBtDAAAAQA2AOoMAAAHAGMAEQAFCYAX/xIAMAEFaAwAAAMASQBpDAAAAgA6AGsMAAACACsAagwAAAEAHgDqDAAAAQBBAC4ABAp/JwADFwAJCbAiUAEAbwMAFwAJCbAiUAEAbwMAEQAHCese0hQARwIAAAA=.',
Va='Vamperella:BAABLgAECn8ZAAIcAAYJcgGREABPAAZoDAAABgABAGkMAAAFAAUAawwAAAUABABqDAAAAQACAGwMAAABAAMA6gwAAAcAAwAcAAYJcgGREABPAAZoDAAABgABAGkMAAAFAAUAawwAAAUABABqDAAAAQACAGwMAAABAAMA6gwAAAcAAwAAAA==.',
Ve='Velkor:BAAALgAECgQJCAAAAA==.',
Vi='Vikings:BAAALgADCgIJAgAAAA==.',
Wa='Wanye:BAAALgADCgcJBwAAAA==.',
We='Wenzr:BAAALgAECgUJCgAAAA==.',
Wi='Willer:BAAALgADCgYJBgAAAA==.',
Wu='Wumbo:BAAALgAECgYJCAABLgAFFAcJJgAZAOYkAA==.',
Ye='Yefercas:BAAALgAECgYJCwABLgAECgkJAQAUAAAAAA==.',
Yi='Yiumi:BAABLgAECn84AAIiAAkJGRYUAgA0AgloDAAACAA4AGkMAAAIAE0AawwAAAgASgBqDAAABgAcAGwMAAAGADsAbQwAAAYAKADqDAAACABKAG4MAAAFACgAbwwAAAEAHQAiAAkJGRYUAgA0AgloDAAACAA4AGkMAAAIAE0AawwAAAgASgBqDAAABgAcAGwMAAAGADsAbQwAAAYAKADqDAAACABKAG4MAAAFACgAbwwAAAEAHQAAAA==.',
Yl='Ylvis:BAABLgAECn8tAAIYAAgJvQuKWACEAQhoDAAABgBEAGkMAAAHABgAawwAAAkAFABqDAAABAAeAGwMAAAFABwAbQwAAAQADADqDAAABQAeAG4MAAAFABkAGAAICb0LilgAhAEIaAwAAAYARABpDAAABwAYAGsMAAAJABQAagwAAAQAHgBsDAAABQAcAG0MAAAEAAwA6gwAAAUAHgBuDAAABQAZAAAA.',
Yo='You:BAABLgAECn8kAAIaAAkJsxcMEwDFAQloDAAABQArAGkMAAAFAFAAawwAAAUATABqDAAABABZAGwMAAAEADkAbQwAAAIAGgDqDAAABQA8AG4MAAAEAEMAbwwAAAIASAAaAAkJsxcMEwDFAQloDAAABQArAGkMAAAFAFAAawwAAAUATABqDAAABABZAGwMAAAEADkAbQwAAAIAGgDqDAAABQA8AG4MAAAEAEMAbwwAAAIASAAAAA==.',
Yu='Yulogee:BAABLgAFFH8GAAMaAAMJXh2hGQDyAANoDAAAAgAzAGkMAAABAFAA6gwAAAMAXQAaAAMJXh2hGQDyAANoDAAAAgAzAGkMAAABAFAA6gwAAAIAXQAZAAEJ4wID+AA3AAHqDAAAAQAHAAAA.Yurdead:BAAALgADCgYJBgABLgAECgEJAQAUAAAAAA==.',
Ze='Zemzelett:BAAALgAECggJEgAAAA==.Zeuz:BAAALgADCgEJAQAAAA==.',
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
