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

local lookup = {'Monk-Windwalker','Monk-Brewmaster','DeathKnight-Frost','DeathKnight-Unholy','DeathKnight-Blood','Druid-Restoration','Druid-Guardian','Hunter-Survival','Paladin-Retribution','Priest-Discipline','Shaman-Restoration','Paladin-Holy','DemonHunter-Devourer','Mage-Frost','Monk-Mistweaver','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Warrior-Fury','Warrior-Arms','Rogue-Subtlety','Priest-Holy','Priest-Shadow','Hunter-Marksmanship','Druid-Balance','Druid-Feral','Paladin-Protection','Shaman-Elemental','Mage-Arcane','Evoker-Preservation','Evoker-Augmentation','Unknown-Unknown','Hunter-BeastMastery',}
local provider = {region='US',realm='Balnazzar',name='US',type='daily',zone=46,date='2026-06-17',data={Ad='Adrianmonk:BAAALgAECgYJDgAAAA==.',
Ak='Aktuu:BAAALgAECggJEAAAAA==.',
An='Andeys:BAAALgAECggJDwAAAA==.Angelius:BAABLgAFFH8FAAIBAAMJrA1eJwC0AANoDAAAAgAQAGkMAAACAC8AawwAAAEAKAABAAMJrA1eJwC0AANoDAAAAgAQAGkMAAACAC8AawwAAAEAKAAAAA==.',
Ar='Arasaka:BAAALgAECgIJAgABLgAECgkJHgACAJkTAA==.',
Ba='Badgirl:BAAALgAECgQJBAAAAA==.Baggigy:BAACLgAFFH8JAAMDAAMJehFfFgDWAANoDAAAAgAuAGkMAAABACkA6gwAAAYALgADAAMJehFfFgDWAANoDAAAAQAuAGkMAAABACkA6gwAAAQALgAEAAIJUwYg+QBzAAJoDAAAAQAXAOoMAAACAAgALgAECn8hAAQDAAgJhB+eFgAjAQAEAAYJ1BydmwA0AQADAAMJVCGeFgAjAQAFAAQJQARUSgBlAAAAAA==.Balance:BAABLgAFFH8IAAMGAAMJcA9xQwCkAANoDAAAAwAyAGkMAAABACEA6gwAAAQAIgAGAAMJcA9xQwCkAANoDAAAAgAyAGkMAAABACEA6gwAAAQAIgAHAAEJjgckQQApAAFoDAAAAQATAAAA.Bandwagon:BAAALgAECgYJBgAAAA==.',
Be='Bentpanda:BAABLgAECn8YAAIIAAkJaBbjEwAGAgloDAAABABdAGkMAAAEAEwAawwAAAQAOgBqDAAAAgA5AGwMAAACAB0AbQwAAAIATwDqDAAAAwAkAG4MAAACAC8AbwwAAAEAJQAIAAkJaBbjEwAGAgloDAAABABdAGkMAAAEAEwAawwAAAQAOgBqDAAAAgA5AGwMAAACAB0AbQwAAAIATwDqDAAAAwAkAG4MAAACAC8AbwwAAAEAJQAAAA==.',
Bh='Bhain:BAABLgAFFH8QAAIJAAUJfB4nLQBaAQVoDAAABQBEAGkMAAAEAE0AawwAAAIAWQBqDAAAAQBNAOoMAAAEAE0ACQAFCXweJy0AWgEFaAwAAAUARABpDAAABABNAGsMAAACAFkAagwAAAEATQDqDAAABABNAAAA.',
Bi='Bigcocko:BAACLgAFFH8hAAIGAAgJ3h0UBADeAghoDAAABwBVAGkMAAAGAFMAawwAAAQAWgBqDAAABABhAGwMAAACADkAbQwAAAEANgDqDAAACABcAG4MAAABADIABgAICd4dFAQA3gIIaAwAAAcAVQBpDAAABgBTAGsMAAAEAFoAagwAAAQAYQBsDAAAAgA5AG0MAAABADYA6gwAAAgAXABuDAAAAQAyAC4ABAp/LgACBgAJCYYliQIAcgMABgAJCYYliQIAcgMAAAA=.Bigwheels:BAAALgAECgMJAwAAAA==.Birchwood:BAAALgAECgYJBgAAAA==.',
Bl='Blarrg:BAAALgAFFAEJAQABLgAFFAMJCQADAHoRAA==.Blocks:BAAALgADCgEJAgAAAA==.',
Bo='Boneriffik:BAAALgAECgUJDQAAAA==.Bossfury:BAAALgAECgYJCQAAAA==.',
Br='Brogh:BAABLgAECn8eAAIKAAkJcRR9EQBcAgloDAAABgBQAGkMAAAGAEcAawwAAAcAOgBqDAAAAQBCAGwMAAABABEAbQwAAAEAGQDqDAAABgBAAG4MAAABAEYAbwwAAAEAEAAKAAkJcRR9EQBcAgloDAAABgBQAGkMAAAGAEcAawwAAAcAOgBqDAAAAQBCAGwMAAABABEAbQwAAAEAGQDqDAAABgBAAG4MAAABAEYAbwwAAAEAEAAAAA==.',
Bu='Buffallo:BAABLgAECn8WAAILAAkJ/AwuOQCdAQloDAAABAAnAGkMAAAEADMAawwAAAQAMwBqDAAAAgAaAGwMAAACABwAbQwAAAEACADqDAAAAwAsAG4MAAABABYAbwwAAAEAGQALAAkJ/AwuOQCdAQloDAAABAAnAGkMAAAEADMAawwAAAQAMwBqDAAAAgAaAGwMAAACABwAbQwAAAEACADqDAAAAwAsAG4MAAABABYAbwwAAAEAGQAAAA==.',
Ca='Camouflage:BAABLgAECn9AAAIIAAkJBCW+AgAYAwloDAAACQBiAGkMAAAJAGEAawwAAAgAYgBqDAAACABeAGwMAAAHAGEAbQwAAAUAWgDqDAAACABiAG4MAAAGAFgAbwwAAAQAWAAIAAkJBCW+AgAYAwloDAAACQBiAGkMAAAJAGEAawwAAAgAYgBqDAAACABeAGwMAAAHAGEAbQwAAAUAWgDqDAAACABiAG4MAAAGAFgAbwwAAAQAWAAAAA==.Caneangel:BAAALgAFFAIJAgAAAA==.',
Ch='Charvhug:BAAALgAFFAEJAQABLgAFFAIJBQAJAAcVAA==.Chilyn:BAABLgAECn8VAAIMAAUJ4RygLgCiAQVoDAAABABcAGkMAAAFAFAAawwAAAUAUQBqDAAAAgA0AOoMAAAFAD4ADAAFCeEcoC4AogEFaAwAAAQAXABpDAAABQBQAGsMAAAFAFEAagwAAAIANADqDAAABQA+AAAA.',
Co='Coldnbloodÿ:BAABLgAECn8cAAINAAYJEw6WoQDgAAZoDAAABgAcAGkMAAAGACMAawwAAAQAKABqDAAABAAnAGwMAAAFAC0A6gwAAAMAHwANAAYJEw6WoQDgAAZoDAAABgAcAGkMAAAGACMAawwAAAQAKABqDAAABAAnAGwMAAAFAC0A6gwAAAMAHwAAAA==.Corrupthell:BAABLgAECn8WAAIEAAcJHhDciABTAQdoDAAABAA6AGkMAAAEACgAawwAAAMAJgBqDAAAAgA7AGwMAAACACAA6gwAAAYAJABuDAAAAQAoAAQABwkeENyIAFMBB2gMAAAEADoAaQwAAAQAKABrDAAAAwAmAGoMAAACADsAbAwAAAIAIADqDAAABgAkAG4MAAABACgAAAA=.Cowi:BAABLgAECn8WAAILAAYJ+g6QYwAwAQZoDAAABQA6AGkMAAAEADoAawwAAAMALQBqDAAAAwASAGwMAAADAAwA6gwAAAQAJQALAAYJ+g6QYwAwAQZoDAAABQA6AGkMAAAEADoAawwAAAMALQBqDAAAAwASAGwMAAADAAwA6gwAAAQAJQABLgAFFAIJBgAOAF4OAA==.',
Cr='Crispaw:BAAALgAECgYJCwAAAA==.Crispo:BAAALgAECgYJDQAAAA==.',
Da='Dadbod:BAAALgAECgcJEQAAAA==.Dadsmemory:BAAALgAECgEJAQAAAA==.Darylbaryl:BAACLgAFFH8FAAIOAAMJXgmjkQCzAANoDAAAAgAbAGkMAAACAAMA6gwAAAEAKQAOAAMJXgmjkQCzAANoDAAAAgAbAGkMAAACAAMA6gwAAAEAKQAuAAQKfxgAAg4ACAlKGilcACUCAA4ACAlKGilcACUCAAAA.Daswassap:BAAALgAECgYJCgAAAA==.',
De='Def:BAAALgAECgIJBgAAAA==.Del:BAAALgAECgQJBgAAAA==.',
Dk='Dkdogg:BAAALgAECgEJAQAAAA==.',
Dr='Dragonfist:BAABLgAECn8eAAQCAAkJmRMYMACVAQloDAAABwBCAGkMAAAFAFAAawwAAAUATABqDAAAAwAeAGwMAAADAC4AbQwAAAEACQDqDAAAAwA8AG4MAAACAAsAbwwAAAEAMgACAAcJexMYMACVAQdoDAAABAA8AGkMAAAEAEAAawwAAAQAOQBqDAAAAwAeAGwMAAADAC4AbQwAAAEACQDqDAAAAwA8AAEABQk6Fvo7ACwBBWgMAAACAEIAaQwAAAEAUABrDAAAAQBMAG4MAAABAAsAbwwAAAEAMgAPAAIJrBy/nABeAAJoDAAAAQA9AG4MAAABAFUAAAA=.Driver:BAACLgAFFH8PAAMQAAUJtgsISQA1AQVoDAAABQAhAGkMAAADAB4AawwAAAEAAgBsDAAAAQApAOoMAAAFACkAEAAFCbYLCEkANQEFaAwAAAQAIQBpDAAAAgAeAGsMAAABAAIAbAwAAAEAKQDqDAAABQApABEAAgndBmYRAIMAAmgMAAABABYAaQwAAAEADQAuAAQKfzUAAxAACAniHvMZALkCABAACAniHvMZALkCABIABgniGNEUAKQBAAAA.',
['Dä']='Däenerys:BAABLgAECn8VAAIEAAkJyA7KTgDXAQloDAAAAwA8AGkMAAADAEEAawwAAAMAMgBqDAAAAwAnAGwMAAACABYAbQwAAAEAEgDqDAAAAwAjAG4MAAACAB0AbwwAAAEAFAAEAAkJyA7KTgDXAQloDAAAAwA8AGkMAAADAEEAawwAAAMAMgBqDAAAAwAnAGwMAAACABYAbQwAAAEAEgDqDAAAAwAjAG4MAAACAB0AbwwAAAEAFAAAAA==.',
Es='Esuna:BAAALgAECgMJBAAAAA==.',
Ew='Ewwf:BAAALgAECgMJBQABLgAFFAgJEwANABEfAA==.',
Ex='Exemplio:BAABLgAECn8lAAICAAkJmCTlAwAPAwloDAAABwBgAGkMAAAGAGEAawwAAAYAYwBqDAAAAwBaAGwMAAADAGAAbQwAAAIAUwDqDAAABgBcAG4MAAADAGEAbwwAAAEAVgACAAkJmCTlAwAPAwloDAAABwBgAGkMAAAGAGEAawwAAAYAYwBqDAAAAwBaAGwMAAADAGAAbQwAAAIAUwDqDAAABgBcAG4MAAADAGEAbwwAAAEAVgAAAA==.',
Fa='Fairyboy:BAAALgADCgYJDAAAAA==.',
Fe='Feel:BAAALgADCgQJBAAAAA==.Felbeast:BAAALgAECgEJAQABLgAECgkJHgACAJkTAA==.Felfirehell:BAAALgADCgMJBgAAAA==.',
Fi='Fininho:BAAALgADCgEJAQAAAA==.',
Fl='Flame:BAAALgAECgUJBQAAAA==.',
Fr='Frahmunda:BAAALgAECgIJBAAAAA==.Frosty:BAABLgAECn8UAAIOAAcJzw3UqACIAQdoDAAABAArAGkMAAADACsAawwAAAMAMQBqDAAAAwAgAGwMAAADABoAbQwAAAEABADqDAAAAwAqAA4ABwnPDdSoAIgBB2gMAAAEACsAaQwAAAMAKwBrDAAAAwAxAGoMAAADACAAbAwAAAMAGgBtDAAAAQAEAOoMAAADACoAAAA=.Frybeam:BAAALgAECgIJAwAAAA==.',
Gi='Gilfoyle:BAAALgAECgIJBwAAAA==.Giovahni:BAACLgAFFH8TAAINAAcJ1BLkIACyAQdoDAAABABJAGkMAAAEADIAawwAAAIAEwBqDAAAAgAbAGwMAAACACMAbQwAAAEANADqDAAABAA5AA0ABwnUEuQgALIBB2gMAAAEAEkAaQwAAAQAMgBrDAAAAgATAGoMAAACABsAbAwAAAIAIwBtDAAAAQA0AOoMAAAEADkALgAECn8xAAINAAgJ1x+vHwBXAgANAAgJ1x+vHwBXAgAAAA==.',
Gl='Glaivemstake:BAAALgADCgYJDwAAAA==.',
Go='Goat:BAAALgADCgUJCAABLgAECgkJHgACAJkTAA==.',
Gr='Gristlecharm:BAABLgAECn8UAAIOAAcJsAVXyABYAQdoDAAABAASAGkMAAAEABMAawwAAAQAEABqDAAAAgAUAGwMAAACABAAbQwAAAEABQDqDAAAAwAKAA4ABwmwBVfIAFgBB2gMAAAEABIAaQwAAAQAEwBrDAAABAAQAGoMAAACABQAbAwAAAIAEABtDAAAAQAFAOoMAAADAAoAAAA=.',
Gw='Gwevon:BAAALgAECgMJAwAAAA==.',
Ha='Hateeho:BAABLgAECn8cAAITAAgJ3hPoOwBWAQhoDAAABQAwAGkMAAAEAD8AawwAAAQAQQBqDAAABAAUAGwMAAADADMAbQwAAAEAFwDqDAAABQAxAG4MAAACADYAEwAICd4T6DsAVgEIaAwAAAUAMABpDAAABAA/AGsMAAAEAEEAagwAAAQAFABsDAAAAwAzAG0MAAABABcA6gwAAAUAMQBuDAAAAgA2AAAA.Haxxen:BAAALgAECgQJBAAAAA==.',
Ho='Holylight:BAAALgAECgMJBQAAAA==.',
Ja='Jahblestraza:BAAALgAECgEJAwAAAA==.Janaria:BAABLgAFFH8KAAIUAAMJER4GHgAAAQNoDAAABABKAGkMAAACAFEA6gwAAAQASgAUAAMJER4GHgAAAQNoDAAABABKAGkMAAACAFEA6gwAAAQASgAAAA==.Jandlion:BAAALgADCgYJBgAAAA==.Jaysix:BAAALgAECgUJBQAAAA==.',
Je='Jedah:BAAALgAECgEJBAAAAA==.Jessiescool:BAABLgAECn8aAAIJAAYJNQ7SlwBOAQZoDAAABQAsAGkMAAAEACkAawwAAAQAHgBqDAAABAA5AGwMAAAEABYA6gwAAAUAKQAJAAYJNQ7SlwBOAQZoDAAABQAsAGkMAAAEACkAawwAAAQAHgBqDAAABAA5AGwMAAAEABYA6gwAAAUAKQAAAA==.',
Ji='Jinxnyx:BAABLgAECn8YAAIHAAkJMw4wEAB1AQloDAAABAA7AGkMAAAEADgAawwAAAQALgBqDAAAAwAiAGwMAAADAC0AbQwAAAEAFQDqDAAAAwArAG4MAAABAAwAbwwAAAEABAAHAAkJMw4wEAB1AQloDAAABAA7AGkMAAAEADgAawwAAAQALgBqDAAAAwAiAGwMAAADAC0AbQwAAAEAFQDqDAAAAwArAG4MAAABAAwAbwwAAAEABAAAAA==.',
Jo='Johnnydeman:BAAALgADCgUJBQAAAA==.Jordanpoole:BAAALgAECgQJCgAAAA==.Joyluka:BAACLgAFFH8PAAIJAAMJjxxwVQAEAQNoDAAABgBcAGkMAAAFAFMA6gwAAAQAKgAJAAMJjxxwVQAEAQNoDAAABgBcAGkMAAAFAFMA6gwAAAQAKgAuAAQKfxsAAgkABwmLJE0nAGYCAAkABwmLJE0nAGYCAAAA.',
Ka='Kalvin:BAABLgAECn8dAAIVAAgJiA6FJQBpAQhoDAAABAAlAGkMAAADADMAawwAAAMAGABqDAAAAgACAGwMAAACACgAbQwAAAIABgDqDAAACwAoAG4MAAACADoAFQAICYgOhSUAaQEIaAwAAAQAJQBpDAAAAwAzAGsMAAADABgAagwAAAIAAgBsDAAAAgAoAG0MAAACAAYA6gwAAAsAKABuDAAAAgA6AAAA.Kanari:BAABLgAECn8mAAQWAAkJPhDxMwA2AQloDAAABAAzAGkMAAAEACgAawwAAAQAMwBqDAAAAwA7AGwMAAAHADEAbQwAAAQAFgDqDAAABwA+AG4MAAAEACMAbwwAAAEAAQAWAAcJlRPxMwA2AQdoDAAABAAzAGkMAAACACgAawwAAAMAMwBqDAAAAgA7AGwMAAADADEA6gwAAAIAPgBuDAAAAQAjAAoABQnGCcRIAOIABWkMAAABAA0AbAwAAAMAGgBtDAAAAwAWAOoMAAADACsAbgwAAAEAEwAXAAgJNQaMAABsAAhpDAAAAQABAGsMAAABAAIAagwAAAEAAwBsDAAAAQAVAG0MAAABAB0A6gwAAAIAIABuDAAAAgAWAG8MAAABAAEAAAA=.',
Ke='Kelak:BAAALgADCgEJAgAAAA==.',
Ki='Killerkid:BAAALgADCgUJBwAAAA==.Kitaravana:BAAALgAECgIJBgAAAA==.',
La='Lagoles:BAACLgAFFH8HAAIIAAMJIxGeAABRAANqDAAAAQAhAGwMAAABAAwA6gwAAAUASwAIAAMJIxGeAABRAANqDAAAAQAhAGwMAAABAAwA6gwAAAUASwAuAAQKfzoAAwgACQkuI1oDAAIDAAgACQmcIloDAAIDABgACAl9H5oTAJgCAAEuAAUUAwkIAA4AvRYA.Lance:BAAALgAECgUJBQAAAA==.Landis:BAAALgAECgUJEAAAAA==.',
Le='Leaf:BAAALgAECgIJAwABLgAECgkJQAAIAAQlAA==.Leoben:BAAALgAECgEJBAAAAA==.',
Li='Liltracey:BAAALgAFFAIJAwABLgAFFAMJCAAGAHAPAA==.Listeriah:BAAALgADCgUJBgAAAA==.',
Lo='Lockbounty:BAAALgAECgEJAQAAAA==.',
Ma='Mambrú:BAAALgAECgMJAwABLgAECgkJGAAHADMOAA==.',
Mi='Miggles:BAACLgAFFH8QAAIGAAMJRRJAPgC3AANoDAAABQApAGkMAAAEABcA6gwAAAcASwAGAAMJRRJAPgC3AANoDAAABQApAGkMAAAEABcA6gwAAAcASwAuAAQKfzEAAwYACQk5IPUKAA4DAAYACQk5IPUKAA4DABkAAglmDk1sAG8AAAAA.Milo:BAABLgAFFH8KAAIaAAMJbhlsDADuAANoDAAABABFAGkMAAABAC0A6gwAAAUAUAAaAAMJbhlsDADuAANoDAAABABFAGkMAAABAC0A6gwAAAUAUAAAAA==.',
Mk='Mk:BAEBLgAECn9NAAQBAAkJiiIHAAAmAgloDAAADQBjAGkMAAAMAGMAawwAAAwAYwBqDAAACwBiAGwMAAAJAGAAbQwAAAUAVgDqDAAACABiAG4MAAAGAGIAbwwAAAEAHAABAAgJ3SUHAAAmAghoDAAADABjAGkMAAALAGMAawwAAAsAYwBqDAAACgBiAGwMAAAIAGAAbQwAAAUAVgDqDAAACABiAG4MAAAGAGIAAgAFCaYJCVgAqAAFaAwAAAEAFQBpDAAAAQAcAGsMAAABAB4AagwAAAEADABsDAAAAQARAA8AAQmIB9/FACUAAW8MAAABABMAAAA=.',
Mo='Monzo:BAABLgAECn8kAAMEAAgJ2iEEGQDmAghoDAAABwBbAGkMAAAHAF4AawwAAAYAXwBqDAAAAwBbAGwMAAADAE0AbQwAAAIAQADqDAAABgBhAG4MAAACAFQABAAICdohBBkA5gIIaAwAAAYAWwBpDAAABgBeAGsMAAAGAF8AagwAAAMAWwBsDAAAAwBNAG0MAAACAEAA6gwAAAYAYQBuDAAAAgBUAAUAAgnUD5I9AFwAAmgMAAABACoAaQwAAAEAJgABLgAFFAMJCAAGAHAPAA==.Morgane:BAAALgAECgcJCAAAAA==.Morvayne:BAACLgAFFH8IAAIOAAMJvRbZfQDbAANoDAAAAwAyAGkMAAACADMA6gwAAAMASAAOAAMJvRbZfQDbAANoDAAAAwAyAGkMAAACADMA6gwAAAMASAAuAAQKfz4AAg4ACQmqIEwRAPMCAA4ACQmqIEwRAPMCAAAA.',
My='Myneemo:BAABLgAECn8bAAIOAAkJfBmQLABnAgloDAAAAwA9AGkMAAAEAEcAawwAAAIARQBqDAAAAwA1AGwMAAAEAEIAbQwAAAMANgDqDAAABABIAG4MAAADAD4AbwwAAAEAPwAOAAkJfBmQLABnAgloDAAAAwA9AGkMAAAEAEcAawwAAAIARQBqDAAAAwA1AGwMAAAEAEIAbQwAAAMANgDqDAAABABIAG4MAAADAD4AbwwAAAEAPwAAAA==.Myro:BAABLgAECn8iAAIJAAgJ3QqolwBFAQhoDAAAAwAYAGkMAAAFACQAawwAAAcAKQBqDAAABAAvAGwMAAAEABkAbQwAAAMADwDqDAAABQAcAG4MAAADABcACQAICd0KqJcARQEIaAwAAAMAGABpDAAABQAkAGsMAAAHACkAagwAAAQALwBsDAAABAAZAG0MAAADAA8A6gwAAAUAHABuDAAAAwAXAAAA.',
No='Nomoneydown:BAAALgAECgIJBgAAAA==.Nosam:BAABLgAECn8hAAIQAAcJwhMGaQBqAQdoDAAACgBBAGkMAAAHAC4AawwAAAUAJABqDAAAAwBAAGwMAAADACoAbQwAAAIAJQDqDAAAAwBLABAABwnCEwZpAGoBB2gMAAAKAEEAaQwAAAcALgBrDAAABQAkAGoMAAADAEAAbAwAAAMAKgBtDAAAAgAlAOoMAAADAEsAAAA=.',
Nt='Nthegreat:BAAALgAECggJDAAAAA==.',
Nw='Nwf:BAABLgAECn8aAAITAAgJHRmcJwC9AQhoDAAABABTAGkMAAAEAEQAawwAAAQATwBqDAAABAA+AGwMAAAEACMAbQwAAAEATgDqDAAABABIAG4MAAABACAAEwAICR0ZnCcAvQEIaAwAAAQAUwBpDAAABABEAGsMAAAEAE8AagwAAAQAPgBsDAAABAAjAG0MAAABAE4A6gwAAAQASABuDAAAAQAgAAAA.',
['Nè']='Nèbula:BAABLgAECn8qAAQMAAgJZBkRFwBSAghoDAAABwA/AGkMAAAHAEsAawwAAAcAPQBqDAAABAAjAGwMAAAFADYAbQwAAAMAQgDqDAAABQBbAG4MAAAEAEgADAAICWQZERcAUgIIaAwAAAIAPwBpDAAAAgBLAGsMAAADAD0AagwAAAIAIwBsDAAAAQA2AG0MAAADAEIA6gwAAAEAWwBuDAAABABIABsABgmTE08AAJQABmgMAAAFADIAaQwAAAUARABrDAAABAA8AGoMAAACADEAbAwAAAMAKgDqDAAABAAdAAkAAQl0B466ASYAAWwMAAABABMAAAA=.',
Or='Ornatas:BAACLgAFFH8NAAIcAAUJMiFfGgBHAQVoDAAABQBaAGkMAAADAFYAawwAAAEATgBqDAAAAQBeAOoMAAADAFQAHAAFCTIhXxoARwEFaAwAAAUAWgBpDAAAAwBWAGsMAAABAE4AagwAAAEAXgDqDAAAAwBUAC4ABAp/GAACHAAICbQclhUAbwIAHAAICbQclhUAbwIAAAA=.',
Pa='Pandamonium:BAABLgAECn8dAAQPAAgJPxT8KwBWAQhoDAAABgAvAGkMAAAFADgAawwAAAYAOgBqDAAAAwBRAGwMAAABACIAbQwAAAEALQDqDAAABgA9AG4MAAABABwADwAICT8U/CsAVgEIaAwAAAUALwBpDAAABAA4AGsMAAAEADoAagwAAAIAUQBsDAAAAQAiAG0MAAABAC0A6gwAAAQAPQBuDAAAAQAcAAIABAn4A7JuAGcABGgMAAABAAQAaQwAAAEADABrDAAAAgAOAGoMAAABAA0AAQABCTgJALMAJAAB6gwAAAIAFwAAAA==.',
Pe='Perdyblues:BAACLgAFFH8GAAIQAAMJgwJmlQCXAANoDAAAAwAKAGkMAAABAAQA6gwAAAIABAAQAAMJgwJmlQCXAANoDAAAAwAKAGkMAAABAAQA6gwAAAIABAAuAAQKfx8AAhAACAmzCvx2AEsBABAACAmzCvx2AEsBAAAA.',
Po='Pom:BAAALgAECgEJAwAAAA==.',
Ps='Psymie:BAAALgAECgYJEQAAAA==.',
Qi='Qiana:BAABLgAECn8dAAIMAAcJvxNrLgCjAQdoDAAABQBQAGkMAAAFAEkAawwAAAUAQQBqDAAAAwArAGwMAAAEACEA6gwAAAUAKwBuDAAAAgANAAwABwm/E2suAKMBB2gMAAAFAFAAaQwAAAUASQBrDAAABQBBAGoMAAADACsAbAwAAAQAIQDqDAAABQArAG4MAAACAA0AAS4ABAoJCSIAFgC+GwA=.',
Qu='Quickstabbin:BAABLgAECn8bAAIBAAgJCQzsRwDgAAhoDAAABgA8AGkMAAAFAC4AawwAAAIAEgBqDAAABAAhAGwMAAADACUAbQwAAAEABwDqDAAABQAZAG4MAAABABMAAQAICQkM7EcA4AAIaAwAAAYAPABpDAAABQAuAGsMAAACABIAagwAAAQAIQBsDAAAAwAlAG0MAAABAAcA6gwAAAUAGQBuDAAAAQATAAAA.Quinoaffle:BAAALgAECgEJAQABLgAFFAMJBQAQAEkPAA==.',
Ra='Rainootra:BAAALgAECgcJDwAAAA==.Ralan:BAAALgAECgYJBgABLgAFFAIJBgAOAF4OAA==.',
Re='Rebirthn:BAAALgAECgcJCQAAAA==.Redronz:BAAALgADCgUJCAABLgAECgkJHgACAJkTAA==.',
Ri='Riffroot:BAAALgADCgEJAQAAAA==.Ritheran:BAAALgAECgMJAwABLgAECgkJHgACAJkTAA==.',
Ro='Rocny:BAAALgAECgEJAQAAAA==.',
Sa='Saerus:BAABLgAECn8eAAMOAAkJKhAfXADKAQloDAAAAgBEAGkMAAADACgAawwAAAQAOQBqDAAABgBQAGwMAAAEAEQAbQwAAAIAGgDqDAAABgAwAG4MAAABAAEAbwwAAAIAFAAOAAkJ4w8fXADKAQloDAAAAQBEAGkMAAACACgAawwAAAMAOQBqDAAABAA8AGwMAAACAEQAbQwAAAEAGgDqDAAAAwAqAG4MAAABAAEAbwwAAAIAFAAdAAcJGQldDgCTAAdoDAAAAQAMAGkMAAABAAYAawwAAAEAAwBqDAAAAgBQAGwMAAACAEAAbQwAAAEABADqDAAAAwAwAAAA.',
Sc='Scylla:BAACLgAFFH8SAAIeAAcJvx0uAQBCAgdoDAAAAQA2AGkMAAAEAGEAawwAAAMAWgBqDAAAAgBEAGwMAAABAFoAbQwAAAEANwDqDAAABgBMAB4ABwm/HS4BAEICB2gMAAABADYAaQwAAAQAYQBrDAAAAwBaAGoMAAACAEQAbAwAAAEAWgBtDAAAAQA3AOoMAAAGAEwALgAECn8sAAMeAAkJACYfAADlAwAeAAkJACYfAADlAwAfAAEJpQ5FXgBCAAABLgAECgYJDwAgAAAAAA==.',
Se='Sephiroth:BAABLgAECn8VAAIJAAkJDhSIQgAdAgloDAAAAwBLAGkMAAADADcAawwAAAMAQQBqDAAAAwBFAGwMAAADAE4AbQwAAAEAEwDqDAAAAwA0AG4MAAABAA0AbwwAAAEAMQAJAAkJDhSIQgAdAgloDAAAAwBLAGkMAAADADcAawwAAAMAQQBqDAAAAwBFAGwMAAADAE4AbQwAAAEAEwDqDAAAAwA0AG4MAAABAA0AbwwAAAEAMQAAAA==.Serephant:BAAALgADCgEJAgAAAA==.',
Si='Siegeshock:BAAALgADCgUJBgAAAA==.Silentbobb:BAAALgADCgcJBwAAAA==.',
Sn='Snow:BAAALgAFFAEJAQABLgAECgkJQAAIAAQlAA==.',
So='Soothe:BAABLgAECn8XAAIWAAYJgxkrJQCbAQZoDAAABABAAGkMAAAFAE0AawwAAAUANwBqDAAAAQA6AGwMAAACADkA6gwAAAYATgAWAAYJgxkrJQCbAQZoDAAABABAAGkMAAAFAE0AawwAAAUANwBqDAAAAQA6AGwMAAACADkA6gwAAAYATgAAAA==.',
St='Stormride:BAAALgAECgIJAwAAAA==.',
Sw='Swaggasaurus:BAABLgAECn8nAAMJAAkJ+B43JQBvAgloDAAABQBjAGkMAAAFAFEAawwAAAUASwBqDAAAAwBVAGwMAAAGAFIAbQwAAAMAWQDqDAAABwBeAG4MAAAEAFEAbwwAAAEAHAAJAAkJ+B43JQBvAgloDAAABQBjAGkMAAAFAFEAawwAAAUASwBqDAAAAwBVAGwMAAAGAFIAbQwAAAIAWQDqDAAABwBeAG4MAAAEAFEAbwwAAAEAHAAMAAEJlwPYkQAsAAFtDAAAAQAJAAAA.',
Sy='Sylarien:BAAALgAECgYJCgAAAA==.Syriena:BAAALgADCggJAwAAAA==.',
Ta='Tadok:BAAALgADCgUJBQAAAA==.Talset:BAACLgAFFH8VAAITAAQJlhzKFABlAQRoDAAABgBIAGkMAAAEAFUAawwAAAMAMwDqDAAACABTABMABAmWHMoUAGUBBGgMAAAGAEgAaQwAAAQAVQBrDAAAAwAzAOoMAAAIAFMALgAECn8fAAITAAgJRB8JFABRAgATAAgJRB8JFABRAgAAAA==.',
Te='Tengoo:BAAALgAECgUJBQAAAA==.',
Th='Thewaitress:BAABLgAFFH8FAAIJAAIJBxUImACHAAJoDAAAAwA3AOoMAAACADQACQACCQcVCJgAhwACaAwAAAMANwDqDAAAAgA0AAAA.Thylight:BAAALgAECgUJBgAAAA==.',
To='Tooperdy:BAAALgADCgIJAgAAAA==.',
Tr='Trappe:BAAALgADCgcJBwAAAA==.',
Tu='Tusker:BAAALgAECgcJDQAAAA==.',
Tw='Twostunz:BAAALgADCgcJDAAAAA==.',
Ty='Tysotcan:BAAALgAECgIJAgAAAA==.',
Ur='Ursalvation:BAAALgADCgUJBQAAAA==.',
Va='Vad:BAAALgAECgIJBwAAAA==.',
Ve='Veew:BAABLgAECn8XAAMTAAgJ8RGROgC8AQhoDAAABAA8AGkMAAAEAEUAawwAAAQAOgBqDAAAAwAwAGwMAAADADcAbQwAAAEAEADqDAAAAwAsAG8MAAABABAAEwAICToRkToAvAEIaAwAAAMAPABpDAAAAwBFAGsMAAADADoAagwAAAEAMABsDAAAAgAqAG0MAAABABAA6gwAAAMALABvDAAAAQAQABQABQmyEQobABkBBWgMAAABADkAaQwAAAEAPgBrDAAAAQAGAGoMAAACACQAbAwAAAEANwAAAA==.',
Vu='Vutraat:BAAALgADCgEJAQAAAA==.',
Vy='Vynaca:BAAALgAECgIJBwAAAA==.',
Wa='Warpedshadow:BAAALgAECggJCwAAAA==.',
Wh='Whitegoddess:BAABLgAECn8pAAIhAAgJTQygawBqAQhoDAAABwAjAGkMAAAGADMAawwAAAYAJwBqDAAABgApAGwMAAAFABQAbQwAAAMAFwDqDAAABAAiAG4MAAAEABAAIQAICU0MoGsAagEIaAwAAAcAIwBpDAAABgAzAGsMAAAGACcAagwAAAYAKQBsDAAABQAUAG0MAAADABcA6gwAAAQAIgBuDAAABAAQAAAA.',
Wo='Wontan:BAAALgAECgcJCAAAAA==.',
Wu='Wukong:BAAALgAECgQJBAAAAA==.',
Xa='Xania:BAAALgAECgIJBwAAAA==.',
Yu='Yungmage:BAABLgAECn8dAAIOAAcJYBuQggDMAQdoDAAABgBUAGkMAAAGAF0AawwAAAUAVwBqDAAABgBSAGwMAAABAEIAbQwAAAEAEQDqDAAABABGAA4ABwlgG5CCAMwBB2gMAAAGAFQAaQwAAAYAXQBrDAAABQBXAGoMAAAGAFIAbAwAAAEAQgBtDAAAAQARAOoMAAAEAEYAAAA=.',
Za='Zaifu:BAAALgAECgIJBwAAAA==.',
Zi='Ziggy:BAABLgAECn8ZAAIOAAkJABhSRQBoAgloDAAABABaAGkMAAAEAFEAawwAAAQASABqDAAAAwBLAGwMAAADAEQAbQwAAAEAQgDqDAAABABIAG4MAAABAAoAbwwAAAEAHQAOAAkJABhSRQBoAgloDAAABABaAGkMAAAEAFEAawwAAAQASABqDAAAAwBLAGwMAAADAEQAbQwAAAEAQgDqDAAABABIAG4MAAABAAoAbwwAAAEAHQAAAA==.',
['Èl']='Èlfman:BAABLgAECn8VAAIGAAcJJhjdNADIAQdoDAAAAgAWAGkMAAAFAD0AawwAAAQAOgBqDAAABABKAGwMAAAEAEkAbQwAAAEAVgBuDAAAAQA3AAYABwkmGN00AMgBB2gMAAACABYAaQwAAAUAPQBrDAAABAA6AGoMAAAEAEoAbAwAAAQASQBtDAAAAQBWAG4MAAABADcAAAA=.',
['Øm']='Ømega:BAAALgAECgEJAQAAAA==.',
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
