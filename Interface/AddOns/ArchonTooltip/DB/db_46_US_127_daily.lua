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

local lookup = {'Warlock-Destruction','Warrior-Fury','Rogue-Subtlety','Rogue-Assassination','Druid-Feral','Monk-Mistweaver','Monk-Brewmaster','Druid-Guardian','Druid-Balance','Druid-Restoration','DeathKnight-Frost','DeathKnight-Blood','DemonHunter-Devourer','Monk-Windwalker','Warrior-Protection','Evoker-Augmentation','Evoker-Devastation','Mage-Frost','Priest-Shadow','Paladin-Retribution','Paladin-Protection','Unknown-Unknown','Paladin-Holy','Priest-Discipline','Priest-Holy','Hunter-BeastMastery','DeathKnight-Unholy','Mage-Arcane','Warrior-Arms','Shaman-Elemental','Shaman-Restoration','Shaman-Enhancement','Warlock-Demonology','Mage-Fire',}
local provider = {region='US',realm='Kalecgos',name='US',type='daily',zone=46,date='2026-06-07',data={Aa='Aamon:BAAALgADCgUJBQAAAA==.Aarius:BAAALgAECgQJBAAAAA==.',
Ae='Aerius:BAAALgADCgYJBAAAAA==.',
Am='Amen:BAAALgADCgEJAQAAAA==.',
Ao='Ao:BAAALgAECgQJCwAAAA==.',
Au='Augmentation:BAAALgAECgIJAwAAAA==.Aurumursi:BAAALgADCgcJBwAAAA==.',
Av='Aviandraka:BAAALgADCgEJAQAAAA==.',
Ba='Baeroch:BAAALgADCgEJAQAAAA==.Barlartwo:BAAALgAECggJEgAAAA==.Bazthrax:BAAALgAECgUJCQAAAA==.Baztinel:BAAALgADCgkJCQAAAA==.Bazty:BAAALgAECgYJDgAAAA==.',
Be='Belthazaar:BAABLgAECn8XAAIBAAYJVAE+NwBAAAZoDAAABgADAGkMAAAEAAIAawwAAAQABABqDAAAAgACAGwMAAACAAMA6gwAAAUAAwABAAYJVAE+NwBAAAZoDAAABgADAGkMAAAEAAIAawwAAAQABABqDAAAAgACAGwMAAACAAMA6gwAAAUAAwAAAA==.',
Bi='Biller:BAAALgADCgYJDAAAAA==.',
Bl='Blade:BAACLgAFFH8KAAICAAMJzh13LQDnAANoDAAABQBXAGkMAAADAE4A6gwAAAIAPgACAAMJzh13LQDnAANoDAAABQBXAGkMAAADAE4A6gwAAAIAPgAuAAQKfx0AAgIACAnWIp8ZABsCAAIACAnWIp8ZABsCAAAA.Blarneystone:BAAALgAECgcJEwAAAA==.Bluemoon:BAAALgADCgYJDAAAAA==.',
Bo='Bootybleaps:BAAALgAFFAMJAwAAAA==.Bootybsneaks:BAACLgAFFH8iAAIDAAYJziLKCADwAQZoDAAACABaAGkMAAAIAGAAawwAAAYAUABqDAAABABFAGwMAAABAFAA6gwAAAcAYQADAAYJziLKCADwAQZoDAAACABaAGkMAAAIAGAAawwAAAYAUABqDAAABABFAGwMAAABAFAA6gwAAAcAYQAuAAQKfzUAAwMACQkiI38EAOsCAAMACQkiI38EAOsCAAQAAQl8FqckADoAAAAA.',
Br='Bramble:BAAALgADCgIJAgAAAA==.Brynhild:BAABLgAECn8ZAAIFAAYJ5AtVJADVAAZoDAAABQApAGkMAAAFABgAawwAAAQAFgBqDAAABAAdAGwMAAAEAB8A6gwAAAMAIAAFAAYJ5AtVJADVAAZoDAAABQApAGkMAAAFABgAawwAAAQAFgBqDAAABAAdAGwMAAAEAB8A6gwAAAMAIAAAAA==.',
Bu='Bullfist:BAABLgAECn8ZAAMGAAYJUBokKgDHAQZoDAAABAAsAGkMAAAEADcAawwAAAQARQBqDAAABgBDAGwMAAADAEYA6gwAAAQAYAAGAAYJUBokKgDHAQZoDAAAAgAsAGkMAAACADcAawwAAAIARQBqDAAABABDAGwMAAADAEYA6gwAAAQAYAAHAAQJORZBTADHAARoDAAAAgBBAGkMAAACADgAawwAAAIAMABqDAAAAgAuAAEuAAQKCAkkAAgAGhwA.Bullievit:BAACLgAFFH8NAAIJAAQJMxRQHgAXAQRoDAAABAA8AGkMAAACACkAawwAAAMAIQDqDAAABABHAAkABAkzFFAeABcBBGgMAAAEADwAaQwAAAIAKQBrDAAAAwAhAOoMAAAEAEcALgAECn8kAAMJAAkJXh1LGgDuAQAJAAkJXh1LGgDuAQAKAAQJLQU8ngCOAAAAAA==.',
Ca='Calssara:BAAALgADCgEJAQAAAA==.',
Ce='Cerealkìller:BAABLgAECn9GAAMLAAkJRBH7CQDSAQloDAAACQArAGkMAAAJACYAawwAAAgAKgBqDAAACQAtAGwMAAAIADQAbQwAAAcAIADqDAAACQAkAG4MAAAHAFgAbwwAAAQAEwALAAkJRBH7CQDSAQloDAAACAArAGkMAAAIACYAawwAAAcAKgBqDAAACAAtAGwMAAAIADQAbQwAAAcAIADqDAAACAAkAG4MAAAHAFgAbwwAAAQAEwAMAAUJ7QB2VQA7AAVoDAAAAQADAGkMAAABAAAAawwAAAEAAQBqDAAAAQAJAOoMAAABAAMAAAA=.',
Ch='Chaostheory:BAAALgAECgEJAgABLgAFFAMJCgACAM4dAA==.Chaozz:BAABLgAECn8YAAINAAYJXyIQPwD4AQZoDAAABABjAGkMAAAEAFUAawwAAAQAWABqDAAABABIAGwMAAAEAEoA6gwAAAQAWwANAAYJXyIQPwD4AQZoDAAABABjAGkMAAAEAFUAawwAAAQAWABqDAAABABIAGwMAAAEAEoA6gwAAAQAWwAAAA==.Chichi:BAAALgAECgIJAgAAAA==.Chistery:BAAALgAECgYJDQAAAA==.Chunly:BAABLgAECn8dAAQOAAkJMBUrFAARAgloDAAAAwA7AGkMAAAFAD0AawwAAAUAMQBqDAAAAwAwAGwMAAABACkAbQwAAAEAGwDqDAAABQBBAG4MAAAFAFgAbwwAAAEAKQAOAAkJMBUrFAARAgloDAAAAwA7AGkMAAADAD0AawwAAAMAMQBqDAAAAgAwAGwMAAABACkAbQwAAAEAGwDqDAAABQBBAG4MAAAFAFgAbwwAAAEAKQAHAAMJIg4ZawBoAANpDAAAAQAcAGsMAAABACsAagwAAAEAGQAGAAIJmwQmZABAAAJpDAAAAQALAGsMAAABAAsAAAA=.',
Cl='Clovicta:BAAALgADCgQJBAAAAA==.',
Cm='Cmoobones:BAABLgAECn8XAAIPAAgJOhErGAB0AQhoDAAAAwA9AGkMAAADAB0AawwAAAMAJwBqDAAAAwA9AGwMAAADADAAbQwAAAEAGQDqDAAABQA1AG4MAAACADIADwAICToRKxgAdAEIaAwAAAMAPQBpDAAAAwAdAGsMAAADACcAagwAAAMAPQBsDAAAAwAwAG0MAAABABkA6gwAAAUANQBuDAAAAgAyAAAA.',
Co='Colokush:BAAALgADCgcJBwAAAA==.Constantine:BAAALgADCgEJAQABLgAECgcJHQAOAD4kAA==.',
Cr='Crisgard:BAAALgAECgQJDgAAAA==.Cronos:BAABLgAECn8rAAMQAAkJcBPQHgDZAQloDAAABwA2AGkMAAAFADkAawwAAAYANwBqDAAABgA2AGwMAAAGADUAbQwAAAMAIQDqDAAABwBEAG4MAAACABgAbwwAAAEAMgAQAAkJkBHQHgDZAQloDAAABQA2AGkMAAAFADkAawwAAAYANwBqDAAABQA2AGwMAAAFADMAbQwAAAIAGwDqDAAABgAmAG4MAAABABgAbwwAAAEAMgARAAYJcBC2DgAWAQZoDAAAAgAuAGoMAAABACAAbAwAAAEANQBtDAAAAQAhAOoMAAABAEQAbgwAAAEABwAAAA==.Cropop:BAAALgAECgYJCAAAAA==.Crow:BAAALgAECgkJBAAAAA==.Crysalus:BAAALgAECgEJAQAAAA==.',
Da='Dacian:BAAALgAECggJDwAAAA==.Darallyn:BAABLgAECn8UAAISAAcJ0hjRXgC+AQdoDAAABABOAGkMAAAEAEYAawwAAAQALgBqDAAAAwBUAGwMAAABADsA6gwAAAMASgBuDAAAAQA0ABIABwnSGNFeAL4BB2gMAAAEAE4AaQwAAAQARgBrDAAABAAuAGoMAAADAFQAbAwAAAEAOwDqDAAAAwBKAG4MAAABADQAAAA=.Davik:BAABLgAECn8YAAITAAYJ/gzDQgD9AAZoDAAABgAkAGkMAAAGABEAawwAAAUAHQBqDAAAAQAiAGwMAAABACYA6gwAAAUAKwATAAYJ/gzDQgD9AAZoDAAABgAkAGkMAAAGABEAawwAAAUAHQBqDAAAAQAiAGwMAAABACYA6gwAAAUAKwAAAA==.Davinah:BAAALgADCgUJCQAAAA==.',
De='Deathcharger:BAAALgAECgMJAwAAAA==.Demonicaxe:BAAALgADCgkJCQAAAA==.Devïl:BAAALgAECgQJCAAAAA==.',
Di='Dingbat:BAAALgADCgEJAQAAAA==.',
Do='Dog:BAAALgAECggJBgAAAA==.Dollfie:BAAALgAECgIJAgAAAA==.Doser:BAABLgAECn8YAAIUAAgJJw1jjgBKAQhoDAAABABEAGkMAAAFACAAawwAAAQAHQBqDAAAAwA2AGwMAAADAB0AbQwAAAEAGgDqDAAAAgAUAG4MAAACAB0AFAAICScNY44ASgEIaAwAAAQARABpDAAABQAgAGsMAAAEAB0AagwAAAMANgBsDAAAAwAdAG0MAAABABoA6gwAAAIAFABuDAAAAgAdAAAA.',
Dr='Dracarsynimz:BAAALgAFFAIJAgABLgAFFAUJFAAQAEILAQ==.Dracene:BAABLgAECn8bAAIVAAgJBQjqIgDxAAhoDAAABAAmAGkMAAAFABwAawwAAAUACQBqDAAAAgAUAGwMAAADAB0AbQwAAAIACQDqDAAABQAOAG4MAAABAA4AFQAICQUI6iIA8QAIaAwAAAQAJgBpDAAABQAcAGsMAAAFAAkAagwAAAIAFABsDAAAAwAdAG0MAAACAAkA6gwAAAUADgBuDAAAAQAOAAAA.Dragosa:BAAALgADCgMJAwABLgAFFAIJAwAWAAAAAA==.',
Du='Duf:BAAALgAECgEJBAAAAA==.',
Dy='Dynasty:BAAALgAECgQJBAAAAA==.',
Eb='Eblazed:BAAALgADCgMJAwAAAA==.',
Fe='Feraldruid:BAAALgAECgMJAwAAAA==.',
Fi='Fisten:BAAALgAECgYJBgAAAA==.',
Fl='Flixs:BAAALgAECgUJBgABLgAECgUJDAAWAAAAAA==.',
Fo='Foxcraft:BAABLgAECn8aAAMGAAkJvB4OBQAUAwloDAAAAwBfAGkMAAADAFwAawwAAAMAXgBqDAAABQBZAGwMAAADAEgAbQwAAAEAPQDqDAAABQBTAG4MAAACADUAbwwAAAEAQQAGAAkJvB4OBQAUAwloDAAAAwBfAGkMAAADAFwAawwAAAMAXgBqDAAABQBZAGwMAAADAEgAbQwAAAEAPQDqDAAABQBTAG4MAAABADUAbwwAAAEAQQAHAAEJZQrEhQA7AAFuDAAAAQAaAAAA.',
Fr='Friëren:BAAALgAECgQJBQAAAA==.Frostfire:BAAALgAECgEJAQAAAA==.',
Ga='Gamera:BAAALgAECgcJEAAAAA==.Gangstabarny:BAAALgAECgEJAQAAAA==.Gankadin:BAABLgAECn8WAAMXAAgJkxTVHQALAghoDAAAAwBKAGkMAAADAFIAawwAAAMANwBqDAAAAwAfAGwMAAADAEwAbQwAAAEAJADqDAAABQAwAG4MAAABAA4AFwAICZMU1R0ACwIIaAwAAAIASgBpDAAAAwBSAGsMAAADADcAagwAAAMAHwBsDAAAAwBMAG0MAAABACQA6gwAAAUAMABuDAAAAQAOABQAAQnxBH2oASUAAWgMAAABAAwAAAA=.',
Gb='Gb:BAACLgAFFH8NAAMTAAQJ8hoKIADeAARoDAAABQBZAGkMAAAEAC0AawwAAAIATgDqDAAAAgA+ABMAAwmwGQogAN4AA2gMAAAEAFkAaQwAAAIALQDqDAAAAgA+ABgAAwnJD9AsAMwAA2gMAAABACQAaQwAAAIAKQBrDAAAAgArAC4ABAp/KAAEGAAJCUodtwcA8wIAGAAJCUodtwcA8wIAEwAICeUcAw4AowIAGQACCTkIMnEAYgAAAAA=.',
Gi='Giffca:BAAALgAECgYJDgAAAA==.',
Gr='Groobel:BAAALgAECgEJAwAAAA==.Groobs:BAAALgAECgEJBwAAAA==.',
Gu='Gunhyrr:BAAALgAFFAEJAQAAAA==.',
Ho='Holycow:BAAALgAECgUJBQABLgAECgkJMQAOAIQWAA==.',
Hu='Humanmatt:BAAALgAECgQJBgAAAA==.',
Hy='Hydra:BAAALgAECgkJBAAAAA==.',
Ic='Icewolff:BAAALgAECgUJBwAAAA==.',
Ik='Ikinokoru:BAACLgAFFH8MAAIaAAQJZyCdIQBpAQRoDAAABABfAGkMAAADAFwAawwAAAEAMwDqDAAABABbABoABAlnIJ0hAGkBBGgMAAAEAF8AaQwAAAMAXABrDAAAAQAzAOoMAAAEAFsALgAECn9JAAIaAAkJiCXwAQBwAwAaAAkJiCXwAQBwAwAAAA==.',
In='Inyànga:BAAALgAECgMJAwAAAA==.',
Is='Isla:BAAALgAECgEJAQAAAA==.',
Je='Jeffren:BAAALgAECgUJDAAAAA==.',
Ji='Jinsho:BAAALgAECggJCAAAAA==.',
Jy='Jyve:BAAALgADCgcJBwABLgAECgkJIwAaAHwbAA==.',
Ka='Kalal:BAAALgADCgYJBwAAAA==.',
Ke='Keg:BAABLgAECn8dAAIOAAcJPiQcEAB+AgdoDAAABQBgAGkMAAAFAGEAawwAAAUAYgBqDAAABABfAGwMAAAEAFgAbQwAAAEAVwDqDAAABQBYAA4ABwk+JBwQAH4CB2gMAAAFAGAAaQwAAAUAYQBrDAAABQBiAGoMAAAEAF8AbAwAAAQAWABtDAAAAQBXAOoMAAAFAFgAAAA=.Keygunmonk:BAAALgADCgcJBwAAAA==.',
Ko='Kovowolf:BAACLgAFFH8RAAIKAAUJaBAOIgA+AQVoDAAABQA/AGkMAAAFADwAawwAAAIAFgBqDAAAAQAEAOoMAAAEADsACgAFCWgQDiIAPgEFaAwAAAUAPwBpDAAABQA8AGsMAAACABYAagwAAAEABADqDAAABAA7AC4ABAp/LwACCgAJCbMhUQUAXAMACgAJCbMhUQUAXAMAAAA=.',
Kr='Krazedwolf:BAACLgAFFH8IAAIUAAUJzBGnPgAhAQVoDAAAAgBUAGkMAAACACMAawwAAAEAGgBqDAAAAQAkAOoMAAACACIAFAAFCcwRpz4AIQEFaAwAAAIAVABpDAAAAgAjAGsMAAABABoAagwAAAEAJADqDAAAAgAiAC4ABAp/KAACFAAJCUYhohUAuAIAFAAJCUYhohUAuAIAAAA=.',
Kv='Kvn:BAAALgAECgUJBgAAAA==.',
Le='Leatherpapi:BAAALgAECgUJBQAAAA==.Lehran:BAAALgAECgUJCAAAAA==.Lemonator:BAAALgAECgQJBQAAAA==.Lemynaid:BAAALgAECgYJDgAAAA==.',
Li='Linsay:BAACLgAFFH8gAAITAAgJJx15AQCeAghoDAAABgBjAGkMAAAFAGIAawwAAAUAXABqDAAABQBjAGwMAAACAFcAbQwAAAEAGADqDAAABwBkAG4MAAABABMAEwAICScdeQEAngIIaAwAAAYAYwBpDAAABQBiAGsMAAAFAFwAagwAAAUAYwBsDAAAAgBXAG0MAAABABgA6gwAAAcAZABuDAAAAQATAC4ABAp/NwACEwAJCSUmQAEAwAMAEwAJCSUmQAEAwAMAAAA=.',
Lo='Lokagdai:BAAALgAECgEJAgAAAA==.Lotieos:BAABLgAECn8cAAIbAAYJMQ4+swAIAQZoDAAACAAkAGkMAAAHAC4AawwAAAUAIABqDAAAAQAOAGwMAAABAAwA6gwAAAYANgAbAAYJMQ4+swAIAQZoDAAACAAkAGkMAAAHAC4AawwAAAUAIABqDAAAAQAOAGwMAAABAAwA6gwAAAYANgAAAA==.Lovelypwr:BAABLgAECn8+AAMTAAkJdROnGgDpAQloDAAACgA9AGkMAAAHADwAawwAAAYAJgBqDAAABQAiAGwMAAAHADsAbQwAAAYAKQDqDAAADQBEAG4MAAAFABgAbwwAAAMAKwATAAkJdROnGgDpAQloDAAACgA9AGkMAAAHADwAawwAAAYAJgBqDAAABQAiAGwMAAAHADsAbQwAAAYAKQDqDAAADABEAG4MAAAFABgAbwwAAAMAKwAYAAEJSwxkdQAvAAHqDAAAAQAfAAAA.',
Ma='Mannera:BAABLgAFFH8GAAIYAAMJihaQKwDWAANoDAAAAgA3AGkMAAACADUA6gwAAAIAQAAYAAMJihaQKwDWAANoDAAAAgA3AGkMAAACADUA6gwAAAIAQAAAAA==.Manzio:BAAALgADCgQJBAAAAA==.Marcus:BAAALgAFFAIJAwAAAA==.Matheris:BAABLgAECn8YAAIPAAkJZiKOBQC0AgloDAAABQBfAGkMAAADAF4AawwAAAMAXgBqDAAAAgBRAGwMAAACAFsAbQwAAAIAQQDqDAAABABhAG4MAAACAFIAbwwAAAEAUgAPAAkJZiKOBQC0AgloDAAABQBfAGkMAAADAF4AawwAAAMAXgBqDAAAAgBRAGwMAAACAFsAbQwAAAIAQQDqDAAABABhAG4MAAACAFIAbwwAAAEAUgAAAA==.Mawiyah:BAAALgAECgcJBwAAAA==.Max:BAABLgAECn8aAAIPAAkJHx49BQC8AgloDAAABABaAGkMAAAEAFwAawwAAAQAXABqDAAABABRAGwMAAAEAEoAbQwAAAEAOQDqDAAAAwBPAG4MAAABAFkAbwwAAAEAKAAPAAkJHx49BQC8AgloDAAABABaAGkMAAAEAFwAawwAAAQAXABqDAAABABRAGwMAAAEAEoAbQwAAAEAOQDqDAAAAwBPAG4MAAABAFkAbwwAAAEAKAABLgAFFAQJDAAMAMAaAA==.',
Me='Melarac:BAABLgAECn8WAAQKAAcJyAu1cgDUAAdoDAAABAAJAGkMAAAEACAAawwAAAQADABqDAAAAwAjAGwMAAABAFgA6gwAAAUADABvDAAAAQATAAoABgn7B7VyANQABmgMAAABAAkAaQwAAAEAIABrDAAAAQAMAGoMAAABACMA6gwAAAEADABvDAAAAQATAAkABgmNCZhMAM0ABmgMAAABABsAaQwAAAEAGwBrDAAAAQASAGoMAAABACgAbAwAAAEAFgDqDAAAAgAZAAgABQnUBhlQAF4ABWgMAAACABMAaQwAAAIAEQBrDAAAAgAPAGoMAAABAA0A6gwAAAIAEAAAAA==.',
Mi='Minibow:BAAALgAECgIJAwAAAA==.Minimagic:BAACLgAFFH8WAAMSAAUJNRw/SwBFAQVoDAAABgBOAGkMAAAFAEwAawwAAAMATQBqDAAAAQBWAOoMAAAHADgAEgAFCTUcP0sARQEFaAwAAAUATgBpDAAABQBMAGsMAAADAE0AagwAAAEAVgDqDAAABwA4ABwAAQkECAkGAEAAAWgMAAABABQALgAECn88AAISAAkJSCSjCQApAwASAAkJSCSjCQApAwAAAA==.',
Mo='Mogh:BAAALgAECgQJBQAAAA==.Monker:BAABLgAECn8hAAQGAAgJzh7pGQA3AghoDAAABgBjAGkMAAAFAGIAawwAAAYAYABqDAAAAwAWAGwMAAAEAF0AbQwAAAIALQDqDAAABgBfAG4MAAABAFEABgAHCa4e6RkANwIHaAwAAAMAYwBpDAAAAwBiAGsMAAAEAGAAagwAAAEAFgBsDAAAAwBdAG0MAAACAC0A6gwAAAMAXwAHAAUJ7huuLwA+AQVoDAAAAgA7AGkMAAABAEQAawwAAAEAQwBqDAAAAQBDAOoMAAADAFoADgAGCYAVED4AIwEGaAwAAAEAPgBpDAAAAQBEAGsMAAABAD8AagwAAAEAQwBsDAAAAQAdAG4MAAABADMAAAA=.',
Mu='Muth:BAAALgAECgQJBgAAAA==.Muthra:BAAALgAECgEJAQABLgAECgQJBgAWAAAAAA==.Muthroc:BAAALgAECgEJAQABLgAECgQJBgAWAAAAAA==.',
My='Mysteria:BAAALgADCgIJAgAAAA==.',
Na='Nasara:BAACLgAFFH8IAAISAAIJ8xsVjwCkAAJoDAAABABIAOoMAAAEAEYAEgACCfMbFY8ApAACaAwAAAQASADqDAAABABGAC4ABAp/OAACEgAICV8j+yAA8AIAEgAICV8j+yAA8AIAAAA=.Nastylad:BAAALgADCgMJAwAAAA==.Nastyzoo:BAAALgAECgUJCAAAAA==.Natassia:BAAALgAECgIJAgAAAA==.',
Ne='Neceob:BAAALgADCgYJCAAAAA==.Nehemia:BAAALgAECgcJBwAAAA==.Nezukokamado:BAAALgAECgYJDgAAAA==.',
Ni='Nikallnight:BAAALgADCgYJBgAAAA==.Nimbus:BAACLgAFFH8GAAIQAAQJpBTlJQAjAQRoDAAAAgBWAGkMAAABAC0AawwAAAEAFwDqDAAAAgA5ABAABAmkFOUlACMBBGgMAAACAFYAaQwAAAEALQBrDAAAAQAXAOoMAAACADkALgAECn8ZAAIQAAkJACN8AwA1AwAQAAkJACN8AwA1AwABLgAFFAgJIgAQAPIbAA==.',
No='Noodles:BAAALgADCgcJBwABLgAECgcJDQAWAAAAAA==.Northstríder:BAAALgADCgMJAwAAAA==.Notloc:BAAALgAECgMJAwABLgAECgcJHQAOAD4kAA==.',
Ob='Oblivionpwr:BAAALgAECgEJAwABLgAECgkJPgATAHUTAA==.',
On='Onomisar:BAAALgAECgUJCQAAAA==.',
Or='Oriah:BAAALgAECgMJAwAAAA==.',
Pa='Padtroll:BAAALgADCgQJBAAAAA==.Paliatarii:BAABLgAECn8dAAIbAAgJnxQNXACtAQhoDAAABgBKAGkMAAAGADgAawwAAAUAMgBqDAAAAgA0AGwMAAADADUA6gwAAAUALwBuDAAAAQAzAG8MAAABACQAGwAICZ8UDVwArQEIaAwAAAYASgBpDAAABgA4AGsMAAAFADIAagwAAAIANABsDAAAAwA1AOoMAAAFAC8AbgwAAAEAMwBvDAAAAQAkAAAA.Pallyfever:BAAALgADCgkJEAAAAA==.',
Pu='Purple:BAAALgADCgMJAwABLgAECgcJHQAOAD4kAA==.',
Ra='Raging:BAAALgAECgMJBAAAAA==.',
Re='Remyxo:BAABLgAECn8bAAMdAAgJ2R5YBwB6AghoDAAABABcAGkMAAAFAF0AawwAAAUARwBqDAAAAgBeAGwMAAADAEkAbQwAAAIATgDqDAAABQBaAG4MAAABADUAHQAICdkeWAcAegIIaAwAAAQAXABpDAAABABdAGsMAAAFAEcAagwAAAIAXgBsDAAAAwBJAG0MAAACAE4A6gwAAAUAWgBuDAAAAQA1AAIAAQntGWuSAEAAAWkMAAABAEIAAAA=.Repentia:BAAALgAFFAEJAQAAAA==.Revaneth:BAAALgADCgcJEwAAAA==.Revanoc:BAAALgAECgMJBAAAAA==.',
Ro='Rockaden:BAAALgADCgUJBQABLgAECgQJBgAWAAAAAA==.Roidsnmolly:BAAALgAECgcJAgAAAA==.',
Ru='Runa:BAAALgAECgYJEwABLgAFFAUJEQAKAGgQAA==.',
Sa='Sadie:BAAALgAECgMJAgAAAA==.Sahlberg:BAABLgAECn8UAAICAAcJUhThLQCTAQdoDAAABQBEAGkMAAAFAD0AawwAAAIARABqDAAAAgBEAGwMAAABABkAbQwAAAEAEgDqDAAABABFAAIABwlSFOEtAJMBB2gMAAAFAEQAaQwAAAUAPQBrDAAAAgBEAGoMAAACAEQAbAwAAAEAGQBtDAAAAQASAOoMAAAEAEUAAAA=.Saphyra:BAAALgADCgUJBQABLgAECgYJGQAFAOQLAA==.',
Sc='Schiel:BAAALgAECgEJAwAAAA==.',
Se='Senkestsu:BAAALgAECggJDAAAAA==.Seraphin:BAAALgAFFAIJAwAAAA==.Sezen:BAAALgAECgcJDgAAAA==.',
Sh='Shammtastiç:BAABLgAECn86AAIeAAkJTheIGwD5AQloDAAACgBPAGkMAAAKAFIAawwAAAoATQBqDAAABgBCAGwMAAAFAC8AbQwAAAEACwDqDAAACgBRAG4MAAAFAEwAbwwAAAEAFQAeAAkJTheIGwD5AQloDAAACgBPAGkMAAAKAFIAawwAAAoATQBqDAAABgBCAGwMAAAFAC8AbQwAAAEACwDqDAAACgBRAG4MAAAFAEwAbwwAAAEAFQAAAA==.Shandizard:BAAALgADCgkJDQAAAA==.Shivra:BAAALgAECgIJAwAAAA==.Shohei:BAAALgADCgcJBwAAAA==.Shulrukol:BAAALgAECgYJEAABLgAFFAgJIAATACcdAA==.Shytownx:BAAALgAECgEJAQAAAA==.',
Si='Sinley:BAABLgAECn8pAAMbAAgJsg2OcQB6AQhoDAAABgAvAGkMAAAHAB8AawwAAAcAEwBqDAAABgAoAGwMAAAGADEAbQwAAAEAHwDqDAAABgAgAG4MAAACACEAGwAICbINjnEAegEIaAwAAAYALwBpDAAABgAfAGsMAAAHABMAagwAAAQAKABsDAAABQAxAG0MAAABAB8A6gwAAAUAIABuDAAAAgAhAAsABAn8BY0uAFMABGkMAAABABIAagwAAAIACQBsDAAAAQATAOoMAAABAAgAAAA=.',
Sn='Sncak:BAACLgAFFH8iAAMDAAcJoxk1CAD+AQdoDAAACABfAGkMAAAIAGEAawwAAAcASQBqDAAAAwAgAG0MAAABAAUA6gwAAAYAWwBuDAAAAQAfAAMABwmjGTUIAP4BB2gMAAAIAF8AaQwAAAcAYQBrDAAABwBJAGoMAAADACAAbQwAAAEABQDqDAAABgBbAG4MAAABAB8ABAABCTkNPAYAXAABaQwAAAEAIQAuAAQKfyoAAwMACQkPJCgCAJADAAMACQkPJCgCAJADAAQABAm/G6QPABYBAAAA.',
So='Solvatod:BAAALgADCgIJAgAAAA==.Soyboiz:BAAALgAECgUJBwAAAA==.',
Sp='Spellslanger:BAAALgADCgYJBgAAAA==.Spiritwolf:BAACLgAFFH8IAAIFAAQJ2g9aDQDSAARoDAAAAwA6AGkMAAACACIAagwAAAEANwDqDAAAAgAdAAUABAnaD1oNANIABGgMAAADADoAaQwAAAIAIgBqDAAAAQA3AOoMAAACAB0ALgAECn8bAAIFAAkJ9iE7BADdAgAFAAkJ9iE7BADdAgAAAA==.',
St='Stanalli:BAAALgADCgIJAgAAAA==.',
Sw='Swagsauce:BAAALgAECgcJBwAAAA==.',
Sy='Sylvara:BAAALgAECgUJBQAAAA==.Symphony:BAAALgAECgUJDQAAAA==.Syrax:BAABLgAECn8lAAMRAAcJvRaeCQCDAQdoDAAABwBMAGkMAAAIAEEAawwAAAcAJwBqDAAABQBHAGwMAAAEAE0A6gwAAAUATABuDAAAAQAOABEABgkfGp4JAIMBBmgMAAAHAEwAaQwAAAMAQQBrDAAABAAmAGoMAAAFAEcAbAwAAAQATQDqDAAABABMABAABAlrDOxfAK0ABGkMAAAFACQAawwAAAMAJwDqDAAAAQAlAG4MAAABAA4AAS4ABRQECQwADADAGgA=.Syrieal:BAACLgAFFH8MAAIMAAQJwBodFAA5AQRoDAAABABOAGkMAAADAEkAawwAAAEASgDqDAAABAAvAAwABAnAGh0UADkBBGgMAAAEAE4AaQwAAAMASQBrDAAAAQBKAOoMAAAEAC8ALgAECn9BAAMMAAkJ1B8yBgC3AgAMAAkJwB4yBgC3AgALAAcJDhlqCgDIAQAAAA==.',
Ta='Taiyla:BAACLgAFFH8HAAISAAQJ9wXzawAEAQRoDAAAAgAcAGkMAAACAA0AawwAAAEABgDqDAAAAgANABIABAn3BfNrAAQBBGgMAAACABwAaQwAAAIADQBrDAAAAQAGAOoMAAACAA0ALgAECn8+AAISAAkJphZBLwBWAgASAAkJphZBLwBWAgAAAA==.Talithiala:BAAALgAECgYJDwAAAA==.Tallai:BAAALgAECgEJAwAAAA==.Tash:BAABLgAECn8rAAMGAAgJExkqEwAzAghoDAAABwBMAGkMAAAFAEIAawwAAAUARQBqDAAABgBcAGwMAAAHAE0AbQwAAAMAHwDqDAAACABFAG4MAAACAB0ABgAICRMZKhMAMwIIaAwAAAUATABpDAAABABCAGsMAAAEAEUAagwAAAUAXABsDAAABQBNAG0MAAACAB8A6gwAAAYARQBuDAAAAgAdAA4ABwmKCspZAJ8AB2gMAAACAB0AaQwAAAEAEgBrDAAAAQAGAGoMAAABACoAbAwAAAIATABtDAAAAQALAOoMAAACABMAAAA=.Taurelin:BAAALgAECgEJAQAAAA==.',
Te='Tejano:BAAALgAECggJEQAAAA==.',
Th='Therionwolf:BAAALgAECgcJDwAAAA==.Thoradin:BAAALgAECgEJAQAAAA==.Thyra:BAAALgAECgUJBQABLgAFFAUJEQAKAGgQAA==.',
Tr='Trip:BAABLgAECn8kAAMfAAkJSgvvVgArAQloDAAABQAlAGkMAAAFAA4AawwAAAUAHABqDAAABAAjAGwMAAAEAB4AbQwAAAIAIwDqDAAABQApAG4MAAAEAA4AbwwAAAIAGAAfAAkJSgvvVgArAQloDAAABAAlAGkMAAAEAA4AawwAAAQAHABqDAAAAwAjAGwMAAACAB4AbQwAAAIAIwDqDAAAAgApAG4MAAACAA4AbwwAAAIAGAAgAAcJBw3AGQAoAQdoDAAAAQAYAGkMAAABABcAawwAAAEAHwBqDAAAAQAXAGwMAAACACYA6gwAAAMAJQBuDAAAAgAtAAAA.',
Ts='Tsty:BAAALgADCgQJBAAAAA==.',
Tu='Tubbybuddy:BAABLgAECn8WAAIgAAYJORloFABnAQZoDAAABQBYAGkMAAAEAFAAawwAAAQARQBqDAAAAwANAGwMAAACAAYA6gwAAAQATgAgAAYJORloFABnAQZoDAAABQBYAGkMAAAEAFAAawwAAAQARQBqDAAAAwANAGwMAAACAAYA6gwAAAQATgAAAA==.Tunafish:BAAALgADCgMJAwAAAA==.',
['Tö']='Töhru:BAAALgADCgEJAQAAAA==.',
Un='Uniboom:BAAALgADCgYJBgABLgAFFAcJIwAZABwcAA==.Unilock:BAACLgAFFH8HAAIhAAQJthNcRQAwAQRoDAAAAgAsAGkMAAACAFIAawwAAAEALwDqDAAAAgAbACEABAm2E1xFADABBGgMAAACACwAaQwAAAIAUgBrDAAAAQAvAOoMAAACABsALgAECn8gAAIhAAkJshlzJgA9AgAhAAkJshlzJgA9AgABLgAFFAcJIwAZABwcAA==.Unipray:BAACLgAFFH8jAAMZAAcJHBwoBAATAgdoDAAABwBAAGkMAAAHAF8AawwAAAYAOgBqDAAABABXAGwMAAABACsAbQwAAAEANgDqDAAACQBjABkABwkcHCgEABMCB2gMAAAEAEAAaQwAAAUAXwBrDAAABAA6AGoMAAADAFcAbAwAAAEAKwBtDAAAAQA2AOoMAAAHAGMAEwAFCYAXOxUAKgEFaAwAAAMASQBpDAAAAgA6AGsMAAACACsAagwAAAEAHgDqDAAAAgBBAC4ABAp/JwADGQAJCbAiUAEAbwMAGQAJCbAiUAEAbwMAEwAHCese0hQARwIAAAA=.',
Va='Vamperella:BAABLgAECn8ZAAIcAAYJcgEtEgBMAAZoDAAABgABAGkMAAAFAAUAawwAAAUABABqDAAAAQACAGwMAAABAAMA6gwAAAcAAwAcAAYJcgEtEgBMAAZoDAAABgABAGkMAAAFAAUAawwAAAUABABqDAAAAQACAGwMAAABAAMA6gwAAAcAAwAAAA==.',
Ve='Velkor:BAAALgAECgQJCAAAAA==.',
Vi='Vikings:BAAALgADCgIJAgAAAA==.',
Wa='Wanye:BAAALgADCgcJBwAAAA==.',
We='Wenzr:BAAALgAECgUJCgAAAA==.',
Wi='Willer:BAAALgADCgYJBgAAAA==.',
Wo='Wolffbane:BAAALgAECgYJBgAAAA==.',
Wu='Wumbo:BAAALgAECgYJCAABLgAFFAcJKwAbAEklAA==.',
Ye='Yefercas:BAAALgAECgYJCwABLgAECgkJAQAWAAAAAA==.',
Yi='Yiumi:BAABLgAECn84AAIiAAkJGRZpAgAiAgloDAAACAA4AGkMAAAIAE0AawwAAAgASgBqDAAABgAcAGwMAAAGADsAbQwAAAYAKADqDAAACABKAG4MAAAFACgAbwwAAAEAHQAiAAkJGRZpAgAiAgloDAAACAA4AGkMAAAIAE0AawwAAAgASgBqDAAABgAcAGwMAAAGADsAbQwAAAYAKADqDAAACABKAG4MAAAFACgAbwwAAAEAHQAAAA==.',
Yl='Ylvis:BAABLgAECn8zAAIaAAgJARD5TQCtAQhoDAAABwBEAGkMAAAIADAAawwAAAoAIwBqDAAABQAeAGwMAAAGAEEAbQwAAAQADADqDAAABQAeAG4MAAAGABkAGgAICQEQ+U0ArQEIaAwAAAcARABpDAAACAAwAGsMAAAKACMAagwAAAUAHgBsDAAABgBBAG0MAAAEAAwA6gwAAAUAHgBuDAAABgAZAAAA.',
Yo='You:BAABLgAECn8kAAIMAAkJsxeqFADAAQloDAAABQArAGkMAAAFAFAAawwAAAUATABqDAAABABZAGwMAAAEADkAbQwAAAIAGgDqDAAABQA8AG4MAAAEAEMAbwwAAAIASAAMAAkJsxeqFADAAQloDAAABQArAGkMAAAFAFAAawwAAAUATABqDAAABABZAGwMAAAEADkAbQwAAAIAGgDqDAAABQA8AG4MAAAEAEMAbwwAAAIASAAAAA==.',
Yu='Yulogee:BAABLgAFFH8GAAMMAAMJXh1VHQDrAANoDAAAAgAzAGkMAAABAFAA6gwAAAMAXQAMAAMJXh1VHQDrAANoDAAAAgAzAGkMAAABAFAA6gwAAAIAXQAbAAEJ4wIaDAE2AAHqDAAAAQAHAAAA.Yurdead:BAAALgADCgYJBgABLgAECgEJAQAWAAAAAA==.',
Za='Zabrozo:BAAALgAECgYJBgAAAA==.',
Ze='Zemzelett:BAABLgAECn8YAAIeAAgJlxUzIwDAAQhoDAAAAwAtAGkMAAAFADwAawwAAAUASQBqDAAAAgBQAGwMAAADAEMAbQwAAAIAMgDqDAAAAwAzAG4MAAABACQAHgAICZcVMyMAwAEIaAwAAAMALQBpDAAABQA8AGsMAAAFAEkAagwAAAIAUABsDAAAAwBDAG0MAAACADIA6gwAAAMAMwBuDAAAAQAkAAAA.Zeuz:BAAALgADCgEJAQAAAA==.',
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
