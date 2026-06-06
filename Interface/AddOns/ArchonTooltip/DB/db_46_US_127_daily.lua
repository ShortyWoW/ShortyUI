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
local provider = {region='US',realm='Kalecgos',name='US',type='daily',zone=46,date='2026-06-05',data={Aa='Aamon:BAAALgADCgUJBQAAAA==.Aarius:BAAALgAECgQJBAAAAA==.',
Ae='Aerius:BAAALgADCgYJBAAAAA==.',
Am='Amen:BAAALgADCgEJAQAAAA==.',
Ao='Ao:BAAALgAECgQJCwAAAA==.',
Au='Augmentation:BAAALgAECgIJAwAAAA==.Aurumursi:BAAALgADCgcJBwAAAA==.',
Av='Aviandraka:BAAALgADCgEJAQAAAA==.',
Ba='Baeroch:BAAALgADCgEJAQAAAA==.Barlartwo:BAAALgAECggJDAAAAA==.Bazthrax:BAAALgAECgQJBQAAAA==.Baztinel:BAAALgADCgkJCQAAAA==.Bazty:BAAALgAECgYJDgAAAA==.',
Be='Belthazaar:BAABLgAECn8XAAIBAAYJVAFLNgBBAAZoDAAABgADAGkMAAAEAAIAawwAAAQABABqDAAAAgACAGwMAAACAAMA6gwAAAUAAwABAAYJVAFLNgBBAAZoDAAABgADAGkMAAAEAAIAawwAAAQABABqDAAAAgACAGwMAAACAAMA6gwAAAUAAwAAAA==.',
Bi='Biller:BAAALgADCgYJDAAAAA==.',
Bl='Blade:BAACLgAFFH8KAAICAAMJzh1ALADuAANoDAAABQBXAGkMAAADAE4A6gwAAAIAPgACAAMJzh1ALADuAANoDAAABQBXAGkMAAADAE4A6gwAAAIAPgAuAAQKfx0AAgIACAnWIiUZABwCAAIACAnWIiUZABwCAAAA.Blarneystone:BAAALgAECgYJDwAAAA==.Bluemoon:BAAALgADCgYJDAAAAA==.',
Bo='Bootybleaps:BAAALgAFFAIJAgAAAA==.Bootybsneaks:BAACLgAFFH8iAAIDAAYJziJcCADyAQZoDAAACABaAGkMAAAIAGAAawwAAAYAUABqDAAABABFAGwMAAABAFAA6gwAAAcAYQADAAYJziJcCADyAQZoDAAACABaAGkMAAAIAGAAawwAAAYAUABqDAAABABFAGwMAAABAFAA6gwAAAcAYQAuAAQKfzUAAwMACQkiI2IEAOwCAAMACQkiI2IEAOwCAAQAAQl8Fi0kADoAAAAA.',
Br='Bramble:BAAALgADCgIJAgAAAA==.Brynhild:BAABLgAECn8ZAAIFAAYJ5AuRIwDWAAZoDAAABQApAGkMAAAFABgAawwAAAQAFgBqDAAABAAdAGwMAAAEAB8A6gwAAAMAIAAFAAYJ5AuRIwDWAAZoDAAABQApAGkMAAAFABgAawwAAAQAFgBqDAAABAAdAGwMAAAEAB8A6gwAAAMAIAAAAA==.',
Bu='Bullfist:BAABLgAECn8VAAMGAAYJUBpJKQDGAQZoDAAAAwAsAGkMAAADADcAawwAAAMARQBqDAAABQBDAGwMAAADAEYA6gwAAAQAYAAGAAYJUBpJKQDGAQZoDAAAAgAsAGkMAAACADcAawwAAAIARQBqDAAABABDAGwMAAADAEYA6gwAAAQAYAAHAAQJMRa2SwDHAARoDAAAAQBBAGkMAAABADgAawwAAAEAMABqDAAAAQAuAAEuAAQKCAkkAAgAGhwA.Bullievit:BAACLgAFFH8NAAIJAAQJMxSOHQAXAQRoDAAABAA8AGkMAAACACkAawwAAAMAIQDqDAAABABHAAkABAkzFI4dABcBBGgMAAAEADwAaQwAAAIAKQBrDAAAAwAhAOoMAAAEAEcALgAECn8kAAMJAAkJXh30GQDuAQAJAAkJXh30GQDuAQAKAAQJLQU8ngCOAAAAAA==.',
Ca='Calssara:BAAALgADCgEJAQAAAA==.',
Ce='Cerealkìller:BAABLgAECn9GAAMLAAkJRBGxCQDTAQloDAAACQArAGkMAAAJACYAawwAAAgAKgBqDAAACQAtAGwMAAAIADQAbQwAAAcAIADqDAAACQAkAG4MAAAHAFgAbwwAAAQAEwALAAkJRBGxCQDTAQloDAAACAArAGkMAAAIACYAawwAAAcAKgBqDAAACAAtAGwMAAAIADQAbQwAAAcAIADqDAAACAAkAG4MAAAHAFgAbwwAAAQAEwAMAAUJ7QBNVAA7AAVoDAAAAQADAGkMAAABAAAAawwAAAEAAQBqDAAAAQAJAOoMAAABAAMAAAA=.',
Ch='Chaostheory:BAAALgAECgEJAgABLgAFFAMJCgACAM4dAA==.Chaozz:BAABLgAECn8YAAINAAYJXyIQPwD4AQZoDAAABABjAGkMAAAEAFUAawwAAAQAWABqDAAABABIAGwMAAAEAEoA6gwAAAQAWwANAAYJXyIQPwD4AQZoDAAABABjAGkMAAAEAFUAawwAAAQAWABqDAAABABIAGwMAAAEAEoA6gwAAAQAWwAAAA==.Chichi:BAAALgAECgIJAgAAAA==.Chistery:BAAALgAECgUJCQAAAA==.Chunly:BAABLgAECn8cAAQOAAkJmhMWFwDvAQloDAAAAwA7AGkMAAAFAD0AawwAAAUAMQBqDAAAAwAwAGwMAAABACkAbQwAAAEAGwDqDAAABQBBAG4MAAAEADcAbwwAAAEAKQAOAAkJmhMWFwDvAQloDAAAAwA7AGkMAAADAD0AawwAAAMAMQBqDAAAAgAwAGwMAAABACkAbQwAAAEAGwDqDAAABQBBAG4MAAAEADcAbwwAAAEAKQAHAAMJIg5DagBoAANpDAAAAQAcAGsMAAABACsAagwAAAEAGQAGAAIJmwQmZABAAAJpDAAAAQALAGsMAAABAAsAAAA=.',
Cl='Clovicta:BAAALgADCgQJBAAAAA==.',
Cm='Cmoobones:BAABLgAECn8XAAIPAAgJOhGsFwB4AQhoDAAAAwA9AGkMAAADAB0AawwAAAMAJwBqDAAAAwA9AGwMAAADADAAbQwAAAEAGQDqDAAABQA1AG4MAAACADIADwAICToRrBcAeAEIaAwAAAMAPQBpDAAAAwAdAGsMAAADACcAagwAAAMAPQBsDAAAAwAwAG0MAAABABkA6gwAAAUANQBuDAAAAgAyAAAA.',
Co='Colokush:BAAALgADCgcJBwAAAA==.Constantine:BAAALgADCgEJAQABLgAECgcJHQAOAD4kAA==.',
Cr='Crisgard:BAAALgAECgQJDgAAAA==.Cronos:BAABLgAECn8rAAMQAAkJcBOMHgDaAQloDAAABwA2AGkMAAAFADkAawwAAAYANwBqDAAABgA2AGwMAAAGADUAbQwAAAMAIQDqDAAABwBEAG4MAAACABgAbwwAAAEAMgAQAAkJkBGMHgDaAQloDAAABQA2AGkMAAAFADkAawwAAAYANwBqDAAABQA2AGwMAAAFADMAbQwAAAIAGwDqDAAABgAmAG4MAAABABgAbwwAAAEAMgARAAYJcBB0DgAYAQZoDAAAAgAuAGoMAAABACAAbAwAAAEANQBtDAAAAQAhAOoMAAABAEQAbgwAAAEABwAAAA==.Cropop:BAAALgAECgYJCAAAAA==.Crow:BAAALgAECgkJBAAAAA==.Crysalus:BAAALgAECgEJAQAAAA==.',
Da='Dacian:BAAALgAECggJDwAAAA==.Darallyn:BAABLgAECn8UAAISAAcJ0hj2XQC+AQdoDAAABABOAGkMAAAEAEYAawwAAAQALgBqDAAAAwBUAGwMAAABADsA6gwAAAMASgBuDAAAAQA0ABIABwnSGPZdAL4BB2gMAAAEAE4AaQwAAAQARgBrDAAABAAuAGoMAAADAFQAbAwAAAEAOwDqDAAAAwBKAG4MAAABADQAAAA=.Davik:BAABLgAECn8YAAITAAYJ/gwAQgD9AAZoDAAABgAkAGkMAAAGABEAawwAAAUAHQBqDAAAAQAiAGwMAAABACYA6gwAAAUAKwATAAYJ/gwAQgD9AAZoDAAABgAkAGkMAAAGABEAawwAAAUAHQBqDAAAAQAiAGwMAAABACYA6gwAAAUAKwAAAA==.Davinah:BAAALgADCgUJCQAAAA==.',
De='Deathcharger:BAAALgAECgMJAwAAAA==.Demonicaxe:BAAALgADCgkJCQAAAA==.Devïl:BAAALgAECgQJCAAAAA==.',
Di='Dingbat:BAAALgADCgEJAQAAAA==.',
Do='Dog:BAAALgAECggJBgAAAA==.Dollfie:BAAALgAECgIJAgAAAA==.Doser:BAABLgAECn8YAAIUAAgJJw2fiwBNAQhoDAAABABEAGkMAAAFACAAawwAAAQAHQBqDAAAAwA2AGwMAAADAB0AbQwAAAEAGgDqDAAAAgAUAG4MAAACAB0AFAAICScNn4sATQEIaAwAAAQARABpDAAABQAgAGsMAAAEAB0AagwAAAMANgBsDAAAAwAdAG0MAAABABoA6gwAAAIAFABuDAAAAgAdAAAA.',
Dr='Dracarsynimz:BAAALgAFFAIJAgABLgAFFAUJFAAQAEILAQ==.Dracene:BAABLgAECn8VAAIVAAgJVAc+IwDqAAhoDAAABAAmAGkMAAAEABIAawwAAAQACABqDAAAAQAUAGwMAAACAB0AbQwAAAEACQDqDAAABAAMAG4MAAABAA4AFQAICVQHPiMA6gAIaAwAAAQAJgBpDAAABAASAGsMAAAEAAgAagwAAAEAFABsDAAAAgAdAG0MAAABAAkA6gwAAAQADABuDAAAAQAOAAAA.Dragosa:BAAALgADCgMJAwABLgAFFAIJAwAWAAAAAA==.',
Du='Duf:BAAALgAECgEJBAAAAA==.',
Dy='Dynasty:BAAALgAECgQJBAAAAA==.',
Eb='Eblazed:BAAALgADCgMJAwAAAA==.',
Fe='Feraldruid:BAAALgAECgMJAwAAAA==.',
Fi='Fisten:BAAALgAECgYJBgAAAA==.',
Fl='Flixs:BAAALgAECgUJBgABLgAECgUJDAAWAAAAAA==.',
Fo='Foxcraft:BAABLgAECn8aAAMGAAkJvB4OBQAUAwloDAAAAwBfAGkMAAADAFwAawwAAAMAXgBqDAAABQBZAGwMAAADAEgAbQwAAAEAPQDqDAAABQBTAG4MAAACADUAbwwAAAEAQQAGAAkJvB4OBQAUAwloDAAAAwBfAGkMAAADAFwAawwAAAMAXgBqDAAABQBZAGwMAAADAEgAbQwAAAEAPQDqDAAABQBTAG4MAAABADUAbwwAAAEAQQAHAAEJZQrEhQA7AAFuDAAAAQAaAAAA.',
Fr='Friëren:BAAALgAECgQJBQAAAA==.Frostfire:BAAALgAECgEJAQAAAA==.',
Ga='Gamera:BAAALgAECgUJCgAAAA==.Gangstabarny:BAAALgAECgEJAQAAAA==.Gankadin:BAABLgAECn8WAAMXAAgJkxRwHQALAghoDAAAAwBKAGkMAAADAFIAawwAAAMANwBqDAAAAwAfAGwMAAADAEwAbQwAAAEAJADqDAAABQAwAG4MAAABAA4AFwAICZMUcB0ACwIIaAwAAAIASgBpDAAAAwBSAGsMAAADADcAagwAAAMAHwBsDAAAAwBMAG0MAAABACQA6gwAAAUAMABuDAAAAQAOABQAAQnxBGuhASYAAWgMAAABAAwAAAA=.',
Gb='Gb:BAACLgAFFH8NAAMTAAQJ8hpLHwDeAARoDAAABQBZAGkMAAAEAC0AawwAAAIATgDqDAAAAgA+ABMAAwmwGUsfAN4AA2gMAAAEAFkAaQwAAAIALQDqDAAAAgA+ABgAAwnJD/UrAMwAA2gMAAABACQAaQwAAAIAKQBrDAAAAgArAC4ABAp/KAAEGAAJCUodgQcA9gIAGAAJCUodgQcA9gIAEwAICeUcAw4AowIAGQACCTkIMnEAYgAAAAA=.',
Gi='Giffca:BAAALgAECgYJDgAAAA==.',
Gr='Groobel:BAAALgAECgEJAwAAAA==.Groobs:BAAALgAECgEJBwAAAA==.',
Gu='Gunhyrr:BAAALgAFFAEJAQAAAA==.',
Ho='Holycow:BAAALgAECgUJBQABLgAECgkJMQAOAIQWAA==.',
Hu='Humanmatt:BAAALgAECgQJBgAAAA==.',
Hy='Hydra:BAAALgAECgkJBAAAAA==.',
Ic='Icewolff:BAAALgAECgUJBwAAAA==.',
Ik='Ikinokoru:BAACLgAFFH8MAAIaAAQJZyB7HwBtAQRoDAAABABfAGkMAAADAFwAawwAAAEAMwDqDAAABABbABoABAlnIHsfAG0BBGgMAAAEAF8AaQwAAAMAXABrDAAAAQAzAOoMAAAEAFsALgAECn9BAAIaAAgJ+CU8CgD7AgAaAAgJ+CU8CgD7AgAAAA==.',
In='Inyànga:BAAALgAECgMJAwAAAA==.',
Je='Jeffren:BAAALgAECgUJDAAAAA==.',
Ji='Jinsho:BAAALgAECggJCAAAAA==.',
Jy='Jyve:BAAALgADCgcJBwABLgAECgkJIwAaAHwbAA==.',
Ka='Kalal:BAAALgADCgYJBwAAAA==.',
Ke='Keg:BAABLgAECn8dAAIOAAcJPiQcEAB+AgdoDAAABQBgAGkMAAAFAGEAawwAAAUAYgBqDAAABABfAGwMAAAEAFgAbQwAAAEAVwDqDAAABQBYAA4ABwk+JBwQAH4CB2gMAAAFAGAAaQwAAAUAYQBrDAAABQBiAGoMAAAEAF8AbAwAAAQAWABtDAAAAQBXAOoMAAAFAFgAAAA=.Keygunmonk:BAAALgADCgcJBwAAAA==.',
Ko='Kovowolf:BAACLgAFFH8RAAIKAAUJaBAJIQBCAQVoDAAABQA/AGkMAAAFADwAawwAAAIAFgBqDAAAAQAEAOoMAAAEADsACgAFCWgQCSEAQgEFaAwAAAUAPwBpDAAABQA8AGsMAAACABYAagwAAAEABADqDAAABAA7AC4ABAp/LwACCgAJCbMhMwUAXAMACgAJCbMhMwUAXAMAAAA=.',
Kr='Krazedwolf:BAACLgAFFH8IAAIUAAUJzBErPAAkAQVoDAAAAgBUAGkMAAACACMAawwAAAEAGgBqDAAAAQAkAOoMAAACACIAFAAFCcwRKzwAJAEFaAwAAAIAVABpDAAAAgAjAGsMAAABABoAagwAAAEAJADqDAAAAgAiAC4ABAp/KAACFAAJCUYhMRUAugIAFAAJCUYhMRUAugIAAAA=.',
Kv='Kvn:BAAALgAECgUJBgAAAA==.',
Le='Leatherpapi:BAAALgAECgUJBQAAAA==.Lehran:BAAALgAECgUJCAAAAA==.Lemonator:BAAALgAECgQJBQAAAA==.Lemynaid:BAAALgAECgYJDgAAAA==.',
Li='Linsay:BAACLgAFFH8gAAITAAgJJx1fAQCgAghoDAAABgBjAGkMAAAFAGIAawwAAAUAXABqDAAABQBjAGwMAAACAFcAbQwAAAEAGADqDAAABwBkAG4MAAABABMAEwAICScdXwEAoAIIaAwAAAYAYwBpDAAABQBiAGsMAAAFAFwAagwAAAUAYwBsDAAAAgBXAG0MAAABABgA6gwAAAcAZABuDAAAAQATAC4ABAp/NwACEwAJCSUmQAEAwAMAEwAJCSUmQAEAwAMAAAA=.',
Lo='Lokagdai:BAAALgAECgEJAgAAAA==.Lotieos:BAABLgAECn8bAAIbAAYJMQ4GsQAIAQZoDAAABwAkAGkMAAAHAC4AawwAAAUAIABqDAAAAQAOAGwMAAABAAwA6gwAAAYANgAbAAYJMQ4GsQAIAQZoDAAABwAkAGkMAAAHAC4AawwAAAUAIABqDAAAAQAOAGwMAAABAAwA6gwAAAYANgAAAA==.Lovelypwr:BAABLgAECn8+AAMTAAkJdRMmGgDsAQloDAAACgA9AGkMAAAHADwAawwAAAYAJgBqDAAABQAiAGwMAAAHADsAbQwAAAYAKQDqDAAADQBEAG4MAAAFABgAbwwAAAMAKwATAAkJdRMmGgDsAQloDAAACgA9AGkMAAAHADwAawwAAAYAJgBqDAAABQAiAGwMAAAHADsAbQwAAAYAKQDqDAAADABEAG4MAAAFABgAbwwAAAMAKwAYAAEJSwytcwAvAAHqDAAAAQAfAAAA.',
Ma='Mannera:BAABLgAFFH8GAAIYAAMJihabKgDXAANoDAAAAgA3AGkMAAACADUA6gwAAAIAQAAYAAMJihabKgDXAANoDAAAAgA3AGkMAAACADUA6gwAAAIAQAAAAA==.Manzio:BAAALgADCgQJBAAAAA==.Marcus:BAAALgAFFAIJAwAAAA==.Matheris:BAABLgAECn8YAAIPAAkJZiJiBQC3AgloDAAABQBfAGkMAAADAF4AawwAAAMAXgBqDAAAAgBRAGwMAAACAFsAbQwAAAIAQQDqDAAABABhAG4MAAACAFIAbwwAAAEAUgAPAAkJZiJiBQC3AgloDAAABQBfAGkMAAADAF4AawwAAAMAXgBqDAAAAgBRAGwMAAACAFsAbQwAAAIAQQDqDAAABABhAG4MAAACAFIAbwwAAAEAUgAAAA==.Mawiyah:BAAALgAECgcJBwAAAA==.Max:BAABLgAECn8aAAIPAAkJHx4YBQC/AgloDAAABABaAGkMAAAEAFwAawwAAAQAXABqDAAABABRAGwMAAAEAEoAbQwAAAEAOQDqDAAAAwBPAG4MAAABAFkAbwwAAAEAKAAPAAkJHx4YBQC/AgloDAAABABaAGkMAAAEAFwAawwAAAQAXABqDAAABABRAGwMAAAEAEoAbQwAAAEAOQDqDAAAAwBPAG4MAAABAFkAbwwAAAEAKAABLgAFFAQJDAAMAMAaAA==.',
Me='Melarac:BAABLgAECn8WAAQKAAcJyAvJcQDUAAdoDAAABAAJAGkMAAAEACAAawwAAAQADABqDAAAAwAjAGwMAAABAFgA6gwAAAUADABvDAAAAQATAAoABgn7B8lxANQABmgMAAABAAkAaQwAAAEAIABrDAAAAQAMAGoMAAABACMA6gwAAAEADABvDAAAAQATAAkABgmNCalLAM0ABmgMAAABABsAaQwAAAEAGwBrDAAAAQASAGoMAAABACgAbAwAAAEAFgDqDAAAAgAZAAgABQnUBlZOAF4ABWgMAAACABMAaQwAAAIAEQBrDAAAAgAPAGoMAAABAA0A6gwAAAIAEAAAAA==.',
Mi='Minibow:BAAALgAECgEJAQAAAA==.Minimagic:BAACLgAFFH8WAAMSAAUJNRxbSQBFAQVoDAAABgBOAGkMAAAFAEwAawwAAAMATQBqDAAAAQBWAOoMAAAHADgAEgAFCTUcW0kARQEFaAwAAAUATgBpDAAABQBMAGsMAAADAE0AagwAAAEAVgDqDAAABwA4ABwAAQkECMoFAEAAAWgMAAABABQALgAECn88AAISAAkJSCRuCQAqAwASAAkJSCRuCQAqAwAAAA==.',
Mo='Mogh:BAAALgAECgQJBQAAAA==.Monker:BAABLgAECn8hAAQGAAgJzh5hGQA3AghoDAAABgBjAGkMAAAFAGIAawwAAAYAYABqDAAAAwAWAGwMAAAEAF0AbQwAAAIALQDqDAAABgBfAG4MAAABAFEABgAHCa4eYRkANwIHaAwAAAMAYwBpDAAAAwBiAGsMAAAEAGAAagwAAAEAFgBsDAAAAwBdAG0MAAACAC0A6gwAAAMAXwAHAAUJ7htBLwA+AQVoDAAAAgA7AGkMAAABAEQAawwAAAEAQwBqDAAAAQBDAOoMAAADAFoADgAGCYAVED4AIwEGaAwAAAEAPgBpDAAAAQBEAGsMAAABAD8AagwAAAEAQwBsDAAAAQAdAG4MAAABADMAAAA=.',
Mu='Muth:BAAALgAECgQJBgAAAA==.Muthra:BAAALgAECgEJAQABLgAECgQJBgAWAAAAAA==.Muthroc:BAAALgAECgEJAQABLgAECgQJBgAWAAAAAA==.',
My='Mysteria:BAAALgADCgIJAgAAAA==.',
Na='Nasara:BAACLgAFFH8IAAISAAIJ8xv0jACkAAJoDAAABABIAOoMAAAEAEYAEgACCfMb9IwApAACaAwAAAQASADqDAAABABGAC4ABAp/OAACEgAICV8j+yAA8AIAEgAICV8j+yAA8AIAAAA=.Nastylad:BAAALgADCgMJAwAAAA==.Nastyzoo:BAAALgAECgUJCAAAAA==.Natassia:BAAALgAECgIJAgAAAA==.',
Ne='Neceob:BAAALgADCgYJCAAAAA==.Nehemia:BAAALgAECgcJBwAAAA==.Nezukokamado:BAAALgAECgYJDgAAAA==.',
Ni='Nikallnight:BAAALgADCgYJBgAAAA==.Nimbus:BAABLgAECn8ZAAIQAAkJACNiAwA2AwloDAAAAwBYAGkMAAADAF4AawwAAAMAWwBqDAAAAwBTAGwMAAADAFgAbQwAAAMAXwDqDAAAAwBZAG4MAAADAGEAbwwAAAEARwAQAAkJACNiAwA2AwloDAAAAwBYAGkMAAADAF4AawwAAAMAWwBqDAAAAwBTAGwMAAADAFgAbQwAAAMAXwDqDAAAAwBZAG4MAAADAGEAbwwAAAEARwABLgAFFAgJHgAQAPIbAA==.',
No='Noodles:BAAALgADCgcJBwABLgAECgcJDQAWAAAAAA==.Northstríder:BAAALgADCgMJAwAAAA==.Notloc:BAAALgAECgMJAwABLgAECgcJHQAOAD4kAA==.',
Ob='Oblivionpwr:BAAALgAECgEJAwABLgAECgkJPgATAHUTAA==.',
On='Onomisar:BAAALgAECgUJCQAAAA==.',
Or='Oriah:BAAALgAECgMJAwAAAA==.',
Pa='Padtroll:BAAALgADCgQJBAAAAA==.Paliatarii:BAABLgAECn8dAAIbAAgJnxQGWwCtAQhoDAAABgBKAGkMAAAGADgAawwAAAUAMgBqDAAAAgA0AGwMAAADADUA6gwAAAUALwBuDAAAAQAzAG8MAAABACQAGwAICZ8UBlsArQEIaAwAAAYASgBpDAAABgA4AGsMAAAFADIAagwAAAIANABsDAAAAwA1AOoMAAAFAC8AbgwAAAEAMwBvDAAAAQAkAAAA.Pallyfever:BAAALgADCgkJEAAAAA==.',
Pu='Purple:BAAALgADCgMJAwABLgAECgcJHQAOAD4kAA==.',
Ra='Raging:BAAALgAECgMJBAAAAA==.',
Re='Remyxo:BAABLgAECn8VAAMdAAgJfRo0CwAnAghoDAAABABcAGkMAAAEAFcAawwAAAQAMABqDAAAAQBeAGwMAAACAEkAbQwAAAEAHQDqDAAABABaAG4MAAABADUAHQAICX0aNAsAJwIIaAwAAAQAXABpDAAAAwBXAGsMAAAEADAAagwAAAEAXgBsDAAAAgBJAG0MAAABAB0A6gwAAAQAWgBuDAAAAQA1AAIAAQntGWWQAEAAAWkMAAABAEIAAAA=.Repentia:BAAALgAFFAEJAQAAAA==.Revaneth:BAAALgADCgcJEwAAAA==.Revanoc:BAAALgAECgMJBAAAAA==.',
Ro='Rockaden:BAAALgADCgUJBQABLgAECgQJBgAWAAAAAA==.Roidsnmolly:BAAALgAECgcJAgAAAA==.',
Ru='Runa:BAAALgAECgYJEwABLgAFFAUJEQAKAGgQAA==.',
Sa='Sadie:BAAALgAECgMJAgAAAA==.Sahlberg:BAABLgAECn8UAAICAAcJUhRMLQCUAQdoDAAABQBEAGkMAAAFAD0AawwAAAIARABqDAAAAgBEAGwMAAABABkAbQwAAAEAEgDqDAAABABFAAIABwlSFEwtAJQBB2gMAAAFAEQAaQwAAAUAPQBrDAAAAgBEAGoMAAACAEQAbAwAAAEAGQBtDAAAAQASAOoMAAAEAEUAAAA=.Saphyra:BAAALgADCgUJBQABLgAECgYJGQAFAOQLAA==.',
Sc='Schiel:BAAALgAECgEJAwAAAA==.',
Se='Senkestsu:BAAALgAECggJDAAAAA==.Seraphin:BAAALgAFFAIJAwAAAA==.Sezen:BAAALgAECgcJDgAAAA==.',
Sh='Shammtastiç:BAABLgAECn86AAIeAAkJThcFGwD7AQloDAAACgBPAGkMAAAKAFIAawwAAAoATQBqDAAABgBCAGwMAAAFAC8AbQwAAAEACwDqDAAACgBRAG4MAAAFAEwAbwwAAAEAFQAeAAkJThcFGwD7AQloDAAACgBPAGkMAAAKAFIAawwAAAoATQBqDAAABgBCAGwMAAAFAC8AbQwAAAEACwDqDAAACgBRAG4MAAAFAEwAbwwAAAEAFQAAAA==.Shandizard:BAAALgADCgkJDQAAAA==.Shivra:BAAALgAECgIJAwAAAA==.Shohei:BAAALgADCgcJBwAAAA==.Shulrukol:BAAALgAECgYJEAABLgAFFAgJIAATACcdAA==.Shytownx:BAAALgAECgEJAQAAAA==.',
Si='Sinley:BAABLgAECn8lAAMbAAgJog2vcQB3AQhoDAAABgAvAGkMAAAGAB4AawwAAAYAEwBqDAAABQAoAGwMAAAFADEAbQwAAAEAHwDqDAAABgAgAG4MAAACACEAGwAICaINr3EAdwEIaAwAAAYALwBpDAAABQAeAGsMAAAGABMAagwAAAQAKABsDAAABQAxAG0MAAABAB8A6gwAAAUAIABuDAAAAgAhAAsAAwknBYc5ACgAA2kMAAABABIAagwAAAEABQDqDAAAAQAIAAAA.',
Sn='Sncak:BAACLgAFFH8iAAMDAAcJoxmsBwAEAgdoDAAACABfAGkMAAAIAGEAawwAAAcASQBqDAAAAwAgAG0MAAABAAUA6gwAAAYAWwBuDAAAAQAfAAMABwmjGawHAAQCB2gMAAAIAF8AaQwAAAcAYQBrDAAABwBJAGoMAAADACAAbQwAAAEABQDqDAAABgBbAG4MAAABAB8ABAABCTkNPAYAXAABaQwAAAEAIQAuAAQKfyoAAwMACQkPJCgCAJADAAMACQkPJCgCAJADAAQABAm/G6QPABYBAAAA.',
So='Solvatod:BAAALgADCgIJAgAAAA==.Soyboiz:BAAALgAECgUJBwAAAA==.',
Sp='Spellslanger:BAAALgADCgYJBgAAAA==.Spiritwolf:BAACLgAFFH8IAAIFAAQJ2g/8DADSAARoDAAAAwA6AGkMAAACACIAagwAAAEANwDqDAAAAgAdAAUABAnaD/wMANIABGgMAAADADoAaQwAAAIAIgBqDAAAAQA3AOoMAAACAB0ALgAECn8bAAIFAAkJ9iE7BADdAgAFAAkJ9iE7BADdAgAAAA==.',
St='Stanalli:BAAALgADCgIJAgAAAA==.',
Sw='Swagsauce:BAAALgAECgcJBwAAAA==.',
Sy='Sylvara:BAAALgAECgUJBQAAAA==.Symphony:BAAALgAECgUJDQAAAA==.Syrax:BAABLgAECn8lAAMRAAcJvRZ+CQCEAQdoDAAABwBMAGkMAAAIAEEAawwAAAcAJwBqDAAABQBHAGwMAAAEAE0A6gwAAAUATABuDAAAAQAOABEABgkfGn4JAIQBBmgMAAAHAEwAaQwAAAMAQQBrDAAABAAmAGoMAAAFAEcAbAwAAAQATQDqDAAABABMABAABAlrDFpeALAABGkMAAAFACQAawwAAAMAJwDqDAAAAQAlAG4MAAABAA4AAS4ABRQECQwADADAGgA=.Syrieal:BAACLgAFFH8MAAIMAAQJwBolEwA8AQRoDAAABABOAGkMAAADAEkAawwAAAEASgDqDAAABAAvAAwABAnAGiUTADwBBGgMAAAEAE4AaQwAAAMASQBrDAAAAQBKAOoMAAAEAC8ALgAECn9BAAMMAAkJ1B8YBgC5AgAMAAkJwB4YBgC5AgALAAcJDhkcCgDIAQAAAA==.',
Ta='Taiyla:BAACLgAFFH8HAAISAAQJ9wW/aQAEAQRoDAAAAgAcAGkMAAACAA0AawwAAAEABgDqDAAAAgANABIABAn3Bb9pAAQBBGgMAAACABwAaQwAAAIADQBrDAAAAQAGAOoMAAACAA0ALgAECn8+AAISAAkJphZ9LgBYAgASAAkJphZ9LgBYAgAAAA==.Talithiala:BAAALgAECgYJDwAAAA==.Tallai:BAAALgAECgEJAwAAAA==.Tash:BAABLgAECn8rAAMGAAgJExkqEwAzAghoDAAABwBMAGkMAAAFAEIAawwAAAUARQBqDAAABgBcAGwMAAAHAE0AbQwAAAMAHwDqDAAACABFAG4MAAACAB0ABgAICRMZKhMAMwIIaAwAAAUATABpDAAABABCAGsMAAAEAEUAagwAAAUAXABsDAAABQBNAG0MAAACAB8A6gwAAAYARQBuDAAAAgAdAA4ABwmKCg9YAKIAB2gMAAACAB0AaQwAAAEAEgBrDAAAAQAGAGoMAAABACoAbAwAAAIATABtDAAAAQALAOoMAAACABMAAAA=.Taurelin:BAAALgAECgEJAQAAAA==.',
Te='Tejano:BAAALgAECggJEQAAAA==.',
Th='Therionwolf:BAAALgAECgYJDgAAAA==.Thoradin:BAAALgAECgEJAQAAAA==.Thyra:BAAALgAECgUJBQABLgAFFAUJEQAKAGgQAA==.',
Tr='Trip:BAABLgAECn8kAAMfAAkJSgvvVgArAQloDAAABQAlAGkMAAAFAA4AawwAAAUAHABqDAAABAAjAGwMAAAEAB4AbQwAAAIAIwDqDAAABQApAG4MAAAEAA4AbwwAAAIAGAAfAAkJSgvvVgArAQloDAAABAAlAGkMAAAEAA4AawwAAAQAHABqDAAAAwAjAGwMAAACAB4AbQwAAAIAIwDqDAAAAgApAG4MAAACAA4AbwwAAAIAGAAgAAcJBw1JGQAoAQdoDAAAAQAYAGkMAAABABcAawwAAAEAHwBqDAAAAQAXAGwMAAACACYA6gwAAAMAJQBuDAAAAgAtAAAA.',
Ts='Tsty:BAAALgADCgQJBAAAAA==.',
Tu='Tubbybuddy:BAABLgAECn8WAAIgAAYJORn/EwBoAQZoDAAABQBYAGkMAAAEAFAAawwAAAQARQBqDAAAAwANAGwMAAACAAYA6gwAAAQATgAgAAYJORn/EwBoAQZoDAAABQBYAGkMAAAEAFAAawwAAAQARQBqDAAAAwANAGwMAAACAAYA6gwAAAQATgAAAA==.Tunafish:BAAALgADCgMJAwAAAA==.',
['Tö']='Töhru:BAAALgADCgEJAQAAAA==.',
Un='Uniboom:BAAALgADCgYJBgABLgAFFAcJIwAZABwcAA==.Unilock:BAACLgAFFH8HAAIhAAQJthNtQwAxAQRoDAAAAgAsAGkMAAACAFIAawwAAAEALwDqDAAAAgAbACEABAm2E21DADEBBGgMAAACACwAaQwAAAIAUgBrDAAAAQAvAOoMAAACABsALgAECn8gAAIhAAkJshkTJgBAAgAhAAkJshkTJgBAAgABLgAFFAcJIwAZABwcAA==.Unipray:BAACLgAFFH8jAAMZAAcJHBzyAwAUAgdoDAAABwBAAGkMAAAHAF8AawwAAAYAOgBqDAAABABXAGwMAAABACsAbQwAAAEANgDqDAAACQBjABkABwkcHPIDABQCB2gMAAAEAEAAaQwAAAUAXwBrDAAABAA6AGoMAAADAFcAbAwAAAEAKwBtDAAAAQA2AOoMAAAHAGMAEwAFCYAXpRQAKwEFaAwAAAMASQBpDAAAAgA6AGsMAAACACsAagwAAAEAHgDqDAAAAgBBAC4ABAp/JwADGQAJCbAiUAEAbwMAGQAJCbAiUAEAbwMAEwAHCese0hQARwIAAAA=.',
Va='Vamperella:BAABLgAECn8ZAAIcAAYJcgGxEQBNAAZoDAAABgABAGkMAAAFAAUAawwAAAUABABqDAAAAQACAGwMAAABAAMA6gwAAAcAAwAcAAYJcgGxEQBNAAZoDAAABgABAGkMAAAFAAUAawwAAAUABABqDAAAAQACAGwMAAABAAMA6gwAAAcAAwAAAA==.',
Ve='Velkor:BAAALgAECgQJCAAAAA==.',
Vi='Vikings:BAAALgADCgIJAgAAAA==.',
Wa='Wanye:BAAALgADCgcJBwAAAA==.',
We='Wenzr:BAAALgAECgUJCgAAAA==.',
Wi='Willer:BAAALgADCgYJBgAAAA==.',
Wo='Wolffbane:BAAALgAECgYJBgAAAA==.',
Wu='Wumbo:BAAALgAECgYJCAABLgAFFAcJKwAbAEklAA==.',
Ye='Yefercas:BAAALgAECgYJCwABLgAECgkJAQAWAAAAAA==.',
Yi='Yiumi:BAABLgAECn84AAIiAAkJGRZXAgAmAgloDAAACAA4AGkMAAAIAE0AawwAAAgASgBqDAAABgAcAGwMAAAGADsAbQwAAAYAKADqDAAACABKAG4MAAAFACgAbwwAAAEAHQAiAAkJGRZXAgAmAgloDAAACAA4AGkMAAAIAE0AawwAAAgASgBqDAAABgAcAGwMAAAGADsAbQwAAAYAKADqDAAACABKAG4MAAAFACgAbwwAAAEAHQAAAA==.',
Yl='Ylvis:BAABLgAECn8uAAIaAAgJvQugXACDAQhoDAAABgBEAGkMAAAHABgAawwAAAkAFABqDAAABAAeAGwMAAAFABwAbQwAAAQADADqDAAABQAeAG4MAAAGABkAGgAICb0LoFwAgwEIaAwAAAYARABpDAAABwAYAGsMAAAJABQAagwAAAQAHgBsDAAABQAcAG0MAAAEAAwA6gwAAAUAHgBuDAAABgAZAAAA.',
Yo='You:BAABLgAECn8kAAIMAAkJsxdVFADBAQloDAAABQArAGkMAAAFAFAAawwAAAUATABqDAAABABZAGwMAAAEADkAbQwAAAIAGgDqDAAABQA8AG4MAAAEAEMAbwwAAAIASAAMAAkJsxdVFADBAQloDAAABQArAGkMAAAFAFAAawwAAAUATABqDAAABABZAGwMAAAEADkAbQwAAAIAGgDqDAAABQA8AG4MAAAEAEMAbwwAAAIASAAAAA==.',
Yu='Yulogee:BAABLgAFFH8GAAMMAAMJXh0wHADuAANoDAAAAgAzAGkMAAABAFAA6gwAAAMAXQAMAAMJXh0wHADuAANoDAAAAgAzAGkMAAABAFAA6gwAAAIAXQAbAAEJ4wLQBgE2AAHqDAAAAQAHAAAA.Yurdead:BAAALgADCgYJBgABLgAECgEJAQAWAAAAAA==.',
Za='Zabrozo:BAAALgAECgYJBgAAAA==.',
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
