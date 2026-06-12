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

local lookup = {'Monk-Windwalker','Monk-Brewmaster','DeathKnight-Frost','DeathKnight-Unholy','DeathKnight-Blood','Druid-Restoration','Druid-Guardian','Hunter-Survival','Paladin-Retribution','Priest-Discipline','Shaman-Restoration','DemonHunter-Devourer','Mage-Frost','Monk-Mistweaver','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Warrior-Fury','Warrior-Arms','Rogue-Subtlety','Priest-Holy','Priest-Shadow','Hunter-Marksmanship','Druid-Balance','Druid-Feral','Paladin-Holy','Paladin-Protection','Shaman-Elemental','Mage-Arcane','Evoker-Preservation','Evoker-Augmentation','Unknown-Unknown','Hunter-BeastMastery',}
local provider = {region='US',realm='Balnazzar',name='US',type='daily',zone=46,date='2026-06-11',data={Ad='Adrianmonk:BAAALgAECgYJDgAAAA==.',
Ak='Aktuu:BAAALgAECgcJDAAAAA==.',
An='Andeys:BAAALgAECggJDwAAAA==.Angelius:BAABLgAFFH8FAAIBAAMJrA1tJQC3AANoDAAAAgAQAGkMAAACAC8AawwAAAEAKAABAAMJrA1tJQC3AANoDAAAAgAQAGkMAAACAC8AawwAAAEAKAAAAA==.',
Ar='Arasaka:BAAALgAECgIJAgABLgAECgkJHgACAJkTAA==.',
Ba='Badgirl:BAAALgAECgQJBAAAAA==.Baggigy:BAACLgAFFH8JAAMDAAMJehF7FADWAANoDAAAAgAuAGkMAAABACkA6gwAAAYALgADAAMJehF7FADWAANoDAAAAQAuAGkMAAABACkA6gwAAAQALgAEAAIJUwaX7QB2AAJoDAAAAQAXAOoMAAACAAgALgAECn8fAAQDAAgJGx7KGAAHAQAEAAYJ1ByamAA0AQADAAMJCx7KGAAHAQAFAAQJQAQcSABnAAAAAA==.Balance:BAABLgAFFH8IAAMGAAMJcA+jQQClAANoDAAAAwAyAGkMAAABACEA6gwAAAQAIgAGAAMJcA+jQQClAANoDAAAAgAyAGkMAAABACEA6gwAAAQAIgAHAAEJjgcoPgApAAFoDAAAAQATAAAA.Bandwagon:BAAALgAECgUJBQAAAA==.',
Be='Bentpanda:BAABLgAECn8YAAIIAAkJaBYbEwAOAgloDAAABABdAGkMAAAEAEwAawwAAAQAOgBqDAAAAgA5AGwMAAACAB0AbQwAAAIATwDqDAAAAwAkAG4MAAACAC8AbwwAAAEAJQAIAAkJaBYbEwAOAgloDAAABABdAGkMAAAEAEwAawwAAAQAOgBqDAAAAgA5AGwMAAACAB0AbQwAAAIATwDqDAAAAwAkAG4MAAACAC8AbwwAAAEAJQAAAA==.',
Bh='Bhain:BAABLgAFFH8QAAIJAAUJfB5iKABeAQVoDAAABQBEAGkMAAAEAE0AawwAAAIAWQBqDAAAAQBNAOoMAAAEAE0ACQAFCXweYigAXgEFaAwAAAUARABpDAAABABNAGsMAAACAFkAagwAAAEATQDqDAAABABNAAAA.',
Bi='Bigcocko:BAACLgAFFH8hAAIGAAgJ3h1sAwDpAghoDAAABwBVAGkMAAAGAFMAawwAAAQAWgBqDAAABABhAGwMAAACADkAbQwAAAEANgDqDAAACABcAG4MAAABADIABgAICd4dbAMA6QIIaAwAAAcAVQBpDAAABgBTAGsMAAAEAFoAagwAAAQAYQBsDAAAAgA5AG0MAAABADYA6gwAAAgAXABuDAAAAQAyAC4ABAp/LgACBgAJCYYliQIAcgMABgAJCYYliQIAcgMAAAA=.Bigwheels:BAAALgAECgMJAwAAAA==.Birchwood:BAAALgAECgYJBgAAAA==.',
Bl='Blarrg:BAAALgAFFAEJAQABLgAFFAMJCQADAHoRAA==.Blocks:BAAALgADCgEJAgAAAA==.',
Bo='Boneriffik:BAAALgAECgUJDQAAAA==.Bossfury:BAAALgAECgYJCQAAAA==.',
Br='Brogh:BAABLgAECn8eAAIKAAkJcRTGEABhAgloDAAABgBQAGkMAAAGAEcAawwAAAcAOgBqDAAAAQBCAGwMAAABABEAbQwAAAEAGQDqDAAABgBAAG4MAAABAEYAbwwAAAEAEAAKAAkJcRTGEABhAgloDAAABgBQAGkMAAAGAEcAawwAAAcAOgBqDAAAAQBCAGwMAAABABEAbQwAAAEAGQDqDAAABgBAAG4MAAABAEYAbwwAAAEAEAAAAA==.',
Bu='Buffallo:BAABLgAECn8WAAILAAkJ/AwuOQCdAQloDAAABAAnAGkMAAAEADMAawwAAAQAMwBqDAAAAgAaAGwMAAACABwAbQwAAAEACADqDAAAAwAsAG4MAAABABYAbwwAAAEAGQALAAkJ/AwuOQCdAQloDAAABAAnAGkMAAAEADMAawwAAAQAMwBqDAAAAgAaAGwMAAACABwAbQwAAAEACADqDAAAAwAsAG4MAAABABYAbwwAAAEAGQAAAA==.',
Ca='Camouflage:BAABLgAECn9AAAIIAAkJBCWOAgAcAwloDAAACQBiAGkMAAAJAGEAawwAAAgAYgBqDAAACABeAGwMAAAHAGEAbQwAAAUAWgDqDAAACABiAG4MAAAGAFgAbwwAAAQAWAAIAAkJBCWOAgAcAwloDAAACQBiAGkMAAAJAGEAawwAAAgAYgBqDAAACABeAGwMAAAHAGEAbQwAAAUAWgDqDAAACABiAG4MAAAGAFgAbwwAAAQAWAAAAA==.Caneangel:BAAALgAFFAIJAgAAAA==.',
Ch='Charvhug:BAAALgAFFAEJAQABLgAFFAIJBQAJAAcVAA==.Chilyn:BAAALgAECgUJEQAAAA==.',
Co='Coldnbloodÿ:BAABLgAECn8cAAIMAAYJEw7VnQDgAAZoDAAABgAcAGkMAAAGACMAawwAAAQAKABqDAAABAAnAGwMAAAFAC0A6gwAAAMAHwAMAAYJEw7VnQDgAAZoDAAABgAcAGkMAAAGACMAawwAAAQAKABqDAAABAAnAGwMAAAFAC0A6gwAAAMAHwAAAA==.Corrupthell:BAABLgAECn8WAAIEAAcJHhCyhABWAQdoDAAABAA6AGkMAAAEACgAawwAAAMAJgBqDAAAAgA7AGwMAAACACAA6gwAAAYAJABuDAAAAQAoAAQABwkeELKEAFYBB2gMAAAEADoAaQwAAAQAKABrDAAAAwAmAGoMAAACADsAbAwAAAIAIADqDAAABgAkAG4MAAABACgAAAA=.Cowi:BAAALgAECgYJEgABLgAFFAIJBQANAF4OAA==.',
Cr='Crispaw:BAAALgAECgYJCwAAAA==.Crispo:BAAALgAECgYJDQAAAA==.',
Da='Dadbod:BAAALgAECgcJEQAAAA==.Dadsmemory:BAAALgAECgEJAQAAAA==.Darylbaryl:BAACLgAFFH8FAAINAAMJXgl9jAC9AANoDAAAAgAbAGkMAAACAAMA6gwAAAEAKQANAAMJXgl9jAC9AANoDAAAAgAbAGkMAAACAAMA6gwAAAEAKQAuAAQKfxgAAg0ACAlKGilcACUCAA0ACAlKGilcACUCAAAA.Daswassap:BAAALgAECgYJCgAAAA==.',
De='Def:BAAALgAECgIJBgAAAA==.Del:BAAALgAECgQJBgAAAA==.',
Dk='Dkdogg:BAAALgAECgEJAQAAAA==.',
Dr='Dragonfist:BAABLgAECn8eAAQCAAkJmRMYMACVAQloDAAABwBCAGkMAAAFAFAAawwAAAUATABqDAAAAwAeAGwMAAADAC4AbQwAAAEACQDqDAAAAwA8AG4MAAACAAsAbwwAAAEAMgACAAcJexMYMACVAQdoDAAABAA8AGkMAAAEAEAAawwAAAQAOQBqDAAAAwAeAGwMAAADAC4AbQwAAAEACQDqDAAAAwA8AAEABQk6Fvo7ACwBBWgMAAACAEIAaQwAAAEAUABrDAAAAQBMAG4MAAABAAsAbwwAAAEAMgAOAAIJrBw4lQBfAAJoDAAAAQA9AG4MAAABAFUAAAA=.Driver:BAACLgAFFH8PAAMPAAUJtgtURQA2AQVoDAAABQAhAGkMAAADAB4AawwAAAEAAgBsDAAAAQApAOoMAAAFACkADwAFCbYLVEUANgEFaAwAAAQAIQBpDAAAAgAeAGsMAAABAAIAbAwAAAEAKQDqDAAABQApABAAAgndBlsQAIQAAmgMAAABABYAaQwAAAEADQAuAAQKfzUAAw8ACAniHvMZALkCAA8ACAniHvMZALkCABEABgniGNEUAKQBAAAA.',
['Dä']='Däenerys:BAAALgAECgkJEQAAAA==.',
Es='Esuna:BAAALgAECgMJBAAAAA==.',
Ew='Ewwf:BAAALgAECgMJBQABLgAFFAgJEwAMABEfAA==.',
Ex='Exemplio:BAABLgAECn8lAAICAAkJmCS5AwAQAwloDAAABwBgAGkMAAAGAGEAawwAAAYAYwBqDAAAAwBaAGwMAAADAGAAbQwAAAIAUwDqDAAABgBcAG4MAAADAGEAbwwAAAEAVgACAAkJmCS5AwAQAwloDAAABwBgAGkMAAAGAGEAawwAAAYAYwBqDAAAAwBaAGwMAAADAGAAbQwAAAIAUwDqDAAABgBcAG4MAAADAGEAbwwAAAEAVgAAAA==.',
Fa='Fairyboy:BAAALgADCgYJDAAAAA==.',
Fe='Feel:BAAALgADCgQJBAAAAA==.Felbeast:BAAALgAECgEJAQABLgAECgkJHgACAJkTAA==.Felfirehell:BAAALgADCgMJBgAAAA==.',
Fi='Fininho:BAAALgADCgEJAQAAAA==.',
Fl='Flame:BAAALgAECgUJBQAAAA==.',
Fr='Frahmunda:BAAALgAECgIJBAAAAA==.Frosty:BAABLgAECn8UAAINAAcJzw3UqACIAQdoDAAABAArAGkMAAADACsAawwAAAMAMQBqDAAAAwAgAGwMAAADABoAbQwAAAEABADqDAAAAwAqAA0ABwnPDdSoAIgBB2gMAAAEACsAaQwAAAMAKwBrDAAAAwAxAGoMAAADACAAbAwAAAMAGgBtDAAAAQAEAOoMAAADACoAAAA=.Frybeam:BAAALgAECgIJAwAAAA==.',
Gi='Gilfoyle:BAAALgAECgIJBwAAAA==.Giovahni:BAACLgAFFH8RAAIMAAYJhxJ1LQBmAQZoDAAABABJAGkMAAAEADIAawwAAAIAEwBqDAAAAgAbAGwMAAACACMA6gwAAAMAOQAMAAYJhxJ1LQBmAQZoDAAABABJAGkMAAAEADIAawwAAAIAEwBqDAAAAgAbAGwMAAACACMA6gwAAAMAOQAuAAQKfzEAAgwACAnXH80eAFcCAAwACAnXH80eAFcCAAAA.',
Gl='Glaivemstake:BAAALgADCgYJDwAAAA==.',
Go='Goat:BAAALgADCgUJCAABLgAECgkJHgACAJkTAA==.',
Gr='Gristlecharm:BAABLgAECn8UAAINAAcJsAVXyABYAQdoDAAABAASAGkMAAAEABMAawwAAAQAEABqDAAAAgAUAGwMAAACABAAbQwAAAEABQDqDAAAAwAKAA0ABwmwBVfIAFgBB2gMAAAEABIAaQwAAAQAEwBrDAAABAAQAGoMAAACABQAbAwAAAIAEABtDAAAAQAFAOoMAAADAAoAAAA=.',
Gw='Gwevon:BAAALgAECgMJAwAAAA==.',
Ha='Hateeho:BAABLgAECn8cAAISAAgJ3hM1OgBaAQhoDAAABQAwAGkMAAAEAD8AawwAAAQAQQBqDAAABAAUAGwMAAADADMAbQwAAAEAFwDqDAAABQAxAG4MAAACADYAEgAICd4TNToAWgEIaAwAAAUAMABpDAAABAA/AGsMAAAEAEEAagwAAAQAFABsDAAAAwAzAG0MAAABABcA6gwAAAUAMQBuDAAAAgA2AAAA.Haxxen:BAAALgAECgQJBAAAAA==.',
Ho='Holylight:BAAALgAECgMJBQAAAA==.',
Ja='Jahblestraza:BAAALgAECgEJAwAAAA==.Janaria:BAABLgAFFH8KAAITAAMJER5pGwAFAQNoDAAABABKAGkMAAACAFEA6gwAAAQASgATAAMJER5pGwAFAQNoDAAABABKAGkMAAACAFEA6gwAAAQASgAAAA==.Jandlion:BAAALgADCgYJBgAAAA==.Jaysix:BAAALgAECgUJBQAAAA==.',
Je='Jedah:BAAALgAECgEJBAAAAA==.Jessiescool:BAABLgAECn8aAAIJAAYJNQ7SlwBOAQZoDAAABQAsAGkMAAAEACkAawwAAAQAHgBqDAAABAA5AGwMAAAEABYA6gwAAAUAKQAJAAYJNQ7SlwBOAQZoDAAABQAsAGkMAAAEACkAawwAAAQAHgBqDAAABAA5AGwMAAAEABYA6gwAAAUAKQAAAA==.',
Ji='Jinxnyx:BAABLgAECn8YAAIHAAkJMw4wEAB1AQloDAAABAA7AGkMAAAEADgAawwAAAQALgBqDAAAAwAiAGwMAAADAC0AbQwAAAEAFQDqDAAAAwArAG4MAAABAAwAbwwAAAEABAAHAAkJMw4wEAB1AQloDAAABAA7AGkMAAAEADgAawwAAAQALgBqDAAAAwAiAGwMAAADAC0AbQwAAAEAFQDqDAAAAwArAG4MAAABAAwAbwwAAAEABAAAAA==.',
Jo='Johnnydeman:BAAALgADCgUJBQAAAA==.Jordanpoole:BAAALgAECgQJCgAAAA==.Joyluka:BAACLgAFFH8PAAIJAAMJjxxOTwAHAQNoDAAABgBcAGkMAAAFAFMA6gwAAAQAKgAJAAMJjxxOTwAHAQNoDAAABgBcAGkMAAAFAFMA6gwAAAQAKgAuAAQKfxsAAgkABwmLJNslAGkCAAkABwmLJNslAGkCAAAA.',
Ka='Kalvin:BAABLgAECn8dAAIUAAgJiA6vJABqAQhoDAAABAAlAGkMAAADADMAawwAAAMAGABqDAAAAgACAGwMAAACACgAbQwAAAIABgDqDAAACwAoAG4MAAACADoAFAAICYgOryQAagEIaAwAAAQAJQBpDAAAAwAzAGsMAAADABgAagwAAAIAAgBsDAAAAgAoAG0MAAACAAYA6gwAAAsAKABuDAAAAgA6AAAA.Kanari:BAABLgAECn8jAAQVAAgJNhK1MgA3AQhoDAAABAAzAGkMAAAEACgAawwAAAQAMwBqDAAAAwA7AGwMAAAHADEAbQwAAAQAFgDqDAAABgA+AG4MAAADACMAFQAHCZUTtTIANwEHaAwAAAQAMwBpDAAAAgAoAGsMAAADADMAagwAAAIAOwBsDAAAAwAxAOoMAAACAD4AbgwAAAEAIwAKAAUJxglaRgDpAAVpDAAAAQANAGwMAAADABoAbQwAAAMAFgDqDAAAAwArAG4MAAABABMAFgAHCSkHH1UAtwAHaQwAAAEAAQBrDAAAAQACAGoMAAABAAMAbAwAAAEAFQBtDAAAAQAdAOoMAAABACAAbgwAAAEAFgAAAA==.',
Ke='Kelak:BAAALgADCgEJAgAAAA==.',
Ki='Killerkid:BAAALgADCgUJBwAAAA==.Kitaravana:BAAALgAECgIJBgAAAA==.',
La='Lagoles:BAACLgAFFH8GAAIIAAMJIxEpJgCYAANqDAAAAQAhAGwMAAABAAwA6gwAAAQASwAIAAMJIxEpJgCYAANqDAAAAQAhAGwMAAABAAwA6gwAAAQASwAuAAQKfzoAAwgACQkuIyoDAAYDAAgACQmcIioDAAYDABcACAl9H5oTAJgCAAEuAAUUAwkIAA0AyBYA.Lance:BAAALgAECgUJBQAAAA==.Landis:BAAALgAECgUJEAAAAA==.',
Le='Leaf:BAAALgAECgIJAwABLgAECgkJQAAIAAQlAA==.Leoben:BAAALgAECgEJBAAAAA==.',
Li='Liltracey:BAAALgAFFAIJAwABLgAFFAMJCAAGAHAPAA==.Listeriah:BAAALgADCgUJBgAAAA==.',
Lo='Lockbounty:BAAALgAECgEJAQAAAA==.',
Ma='Mambrú:BAAALgAECgMJAwABLgAECgkJGAAHADMOAA==.',
Mi='Miggles:BAACLgAFFH8QAAIGAAMJRRIhPAC6AANoDAAABQApAGkMAAAEABcA6gwAAAcASwAGAAMJRRIhPAC6AANoDAAABQApAGkMAAAEABcA6gwAAAcASwAuAAQKfzEAAwYACQk5IKEKAA4DAAYACQk5IKEKAA4DABgAAglmDk1sAG8AAAAA.Milo:BAABLgAFFH8IAAIZAAMJbhl+CwDxAANoDAAAAwBFAGkMAAABAC0A6gwAAAQAUAAZAAMJbhl+CwDxAANoDAAAAwBFAGkMAAABAC0A6gwAAAQAUAAAAA==.',
Mk='Mk:BAEBLgAECn9BAAQBAAkJgCAfBgAfAwloDAAACwBjAGkMAAAKAGMAawwAAAoAYwBqDAAACQBhAGwMAAAHAFwAbQwAAAMAMADqDAAACABiAG4MAAAGAGIAbwwAAAEAHAABAAgJiCMfBgAfAwhoDAAACgBjAGkMAAAJAGMAawwAAAkAYwBqDAAACABhAGwMAAAGAFwAbQwAAAMAMADqDAAACABiAG4MAAAGAGIAAgAFCaYJwVYAqAAFaAwAAAEAFQBpDAAAAQAcAGsMAAABAB4AagwAAAEADABsDAAAAQARAA4AAQmIBzG8ACUAAW8MAAABABMAAAA=.',
Mo='Monzo:BAABLgAECn8kAAMEAAgJ2iEEGQDmAghoDAAABwBbAGkMAAAHAF4AawwAAAYAXwBqDAAAAwBbAGwMAAADAE0AbQwAAAIAQADqDAAABgBhAG4MAAACAFQABAAICdohBBkA5gIIaAwAAAYAWwBpDAAABgBeAGsMAAAGAF8AagwAAAMAWwBsDAAAAwBNAG0MAAACAEAA6gwAAAYAYQBuDAAAAgBUAAUAAgnUD5I9AFwAAmgMAAABACoAaQwAAAEAJgABLgAFFAMJCAAGAHAPAA==.Morgane:BAAALgAECgcJCAAAAA==.Morvayne:BAACLgAFFH8IAAINAAMJyBbMeADoAANoDAAAAwAyAGkMAAACADMA6gwAAAMASAANAAMJyBbMeADoAANoDAAAAwAyAGkMAAACADMA6gwAAAMASAAuAAQKfz4AAg0ACQmqIJoQAPUCAA0ACQmqIJoQAPUCAAAA.',
My='Myneemo:BAABLgAECn8VAAINAAgJZRfiSwD1AQhoDAAAAwA9AGkMAAADADgAawwAAAEALQBqDAAAAgAlAGwMAAADAEIAbQwAAAMANgDqDAAABABIAG4MAAACAD4ADQAICWUX4ksA9QEIaAwAAAMAPQBpDAAAAwA4AGsMAAABAC0AagwAAAIAJQBsDAAAAwBCAG0MAAADADYA6gwAAAQASABuDAAAAgA+AAAA.Myro:BAABLgAECn8iAAIJAAgJ3Qr8kgBIAQhoDAAAAwAYAGkMAAAFACQAawwAAAcAKQBqDAAABAAvAGwMAAAEABkAbQwAAAMADwDqDAAABQAcAG4MAAADABcACQAICd0K/JIASAEIaAwAAAMAGABpDAAABQAkAGsMAAAHACkAagwAAAQALwBsDAAABAAZAG0MAAADAA8A6gwAAAUAHABuDAAAAwAXAAAA.',
No='Nomoneydown:BAAALgAECgIJBgAAAA==.Nosam:BAABLgAECn8hAAIPAAcJwhM4ZgBvAQdoDAAACgBBAGkMAAAHAC4AawwAAAUAJABqDAAAAwBAAGwMAAADACoAbQwAAAIAJQDqDAAAAwBLAA8ABwnCEzhmAG8BB2gMAAAKAEEAaQwAAAcALgBrDAAABQAkAGoMAAADAEAAbAwAAAMAKgBtDAAAAgAlAOoMAAADAEsAAAA=.',
Nt='Nthegreat:BAAALgAECggJDAAAAA==.',
Nw='Nwf:BAABLgAECn8aAAISAAgJHRmNJgDBAQhoDAAABABTAGkMAAAEAEQAawwAAAQATwBqDAAABAA+AGwMAAAEACMAbQwAAAEATgDqDAAABABIAG4MAAABACAAEgAICR0ZjSYAwQEIaAwAAAQAUwBpDAAABABEAGsMAAAEAE8AagwAAAQAPgBsDAAABAAjAG0MAAABAE4A6gwAAAQASABuDAAAAQAgAAAA.',
['Nè']='Nèbula:BAABLgAECn8gAAQaAAgJwBULIgDvAQhoDAAABgA/AGkMAAAFAEsAawwAAAUAPQBqDAAAAwAGAGwMAAAEACsAbQwAAAIAHwDqDAAABABbAG4MAAADAEgAGgAHCXQWCyIA7wEHaAwAAAIAPwBpDAAAAgBLAGsMAAACAD0AagwAAAEABgBtDAAAAgAfAOoMAAABAFsAbgwAAAMASAAbAAYJ7Q6iJQDiAAZoDAAABAAyAGkMAAADACMAawwAAAMAIQBqDAAAAgAxAGwMAAADACoA6gwAAAMAHQAJAAEJdAfrpwEoAAFsDAAAAQATAAAA.',
Or='Ornatas:BAACLgAFFH8NAAIcAAUJMiHyFwBOAQVoDAAABQBaAGkMAAADAFYAawwAAAEATgBqDAAAAQBeAOoMAAADAFQAHAAFCTIh8hcATgEFaAwAAAUAWgBpDAAAAwBWAGsMAAABAE4AagwAAAEAXgDqDAAAAwBUAC4ABAp/GAACHAAICbQclhUAbwIAHAAICbQclhUAbwIAAAA=.',
Pa='Pandamonium:BAABLgAECn8dAAQOAAgJPxT8KwBWAQhoDAAABgAvAGkMAAAFADgAawwAAAYAOgBqDAAAAwBRAGwMAAABACIAbQwAAAEALQDqDAAABgA9AG4MAAABABwADgAICT8U/CsAVgEIaAwAAAUALwBpDAAABAA4AGsMAAAEADoAagwAAAIAUQBsDAAAAQAiAG0MAAABAC0A6gwAAAQAPQBuDAAAAQAcAAIABAn4AwZtAGcABGgMAAABAAQAaQwAAAEADABrDAAAAgAOAGoMAAABAA0AAQABCTgJmIEALwAB6gwAAAIAFwAAAA==.',
Pe='Perdyblues:BAABLgAECn8XAAIPAAgJ0wYVjQAeAQhoDAAAAwAbAGkMAAAEAB0AawwAAAUAEQBqDAAAAgAIAGwMAAADAA4AbQwAAAEADgDqDAAABAAOAG4MAAABAAQADwAICdMGFY0AHgEIaAwAAAMAGwBpDAAABAAdAGsMAAAFABEAagwAAAIACABsDAAAAwAOAG0MAAABAA4A6gwAAAQADgBuDAAAAQAEAAAA.',
Po='Pom:BAAALgAECgEJAwAAAA==.',
Ps='Psymie:BAAALgAECgUJDQAAAA==.',
Qi='Qiana:BAABLgAECn8XAAIaAAcJwxK8LgCdAQdoDAAABABQAGkMAAAEAEkAawwAAAQAQQBqDAAAAgAZAGwMAAADACEA6gwAAAQAKwBuDAAAAgANABoABwnDErwuAJ0BB2gMAAAEAFAAaQwAAAQASQBrDAAABABBAGoMAAACABkAbAwAAAMAIQDqDAAABAArAG4MAAACAA0AAS4ABAoJCSEAFQC+GwA=.',
Qu='Quickstabbin:BAABLgAECn8bAAIBAAgJCQxVRQDkAAhoDAAABgA8AGkMAAAFAC4AawwAAAIAEgBqDAAABAAhAGwMAAADACUAbQwAAAEABwDqDAAABQAZAG4MAAABABMAAQAICQkMVUUA5AAIaAwAAAYAPABpDAAABQAuAGsMAAACABIAagwAAAQAIQBsDAAAAwAlAG0MAAABAAcA6gwAAAUAGQBuDAAAAQATAAAA.Quinoaffle:BAAALgAECgEJAQABLgAFFAMJBQAPAFIPAA==.',
Ra='Rainootra:BAAALgAECgcJCgAAAA==.',
Re='Rebirthn:BAAALgAECgcJCQAAAA==.Redronz:BAAALgADCgUJCAABLgAECgkJHgACAJkTAA==.',
Ri='Riffroot:BAAALgADCgEJAQAAAA==.Ritheran:BAAALgAECgMJAwABLgAECgkJHgACAJkTAA==.',
Ro='Rocny:BAAALgAECgEJAQAAAA==.',
Sa='Saerus:BAABLgAECn8eAAMNAAkJKhDJWADQAQloDAAAAgBEAGkMAAADACgAawwAAAQAOQBqDAAABgBQAGwMAAAEAEQAbQwAAAIAGgDqDAAABgAwAG4MAAABAAEAbwwAAAIAFAANAAkJ4w/JWADQAQloDAAAAQBEAGkMAAACACgAawwAAAMAOQBqDAAABAA8AGwMAAACAEQAbQwAAAEAGgDqDAAAAwAqAG4MAAABAAEAbwwAAAIAFAAdAAcJGQm1DQCTAAdoDAAAAQAMAGkMAAABAAYAawwAAAEAAwBqDAAAAgBQAGwMAAACAEAAbQwAAAEABADqDAAAAwAwAAAA.',
Sc='Scylla:BAACLgAFFH8SAAIeAAcJvx0uAQBCAgdoDAAAAQA2AGkMAAAEAGEAawwAAAMAWgBqDAAAAgBEAGwMAAABAFoAbQwAAAEANwDqDAAABgBMAB4ABwm/HS4BAEICB2gMAAABADYAaQwAAAQAYQBrDAAAAwBaAGoMAAACAEQAbAwAAAEAWgBtDAAAAQA3AOoMAAAGAEwALgAECn8sAAMeAAkJACYfAADlAwAeAAkJACYfAADlAwAfAAEJpQ5FXgBCAAABLgAECgYJDwAgAAAAAA==.',
Se='Sephiroth:BAABLgAECn8VAAIJAAkJDhSIQgAdAgloDAAAAwBLAGkMAAADADcAawwAAAMAQQBqDAAAAwBFAGwMAAADAE4AbQwAAAEAEwDqDAAAAwA0AG4MAAABAA0AbwwAAAEAMQAJAAkJDhSIQgAdAgloDAAAAwBLAGkMAAADADcAawwAAAMAQQBqDAAAAwBFAGwMAAADAE4AbQwAAAEAEwDqDAAAAwA0AG4MAAABAA0AbwwAAAEAMQAAAA==.Serephant:BAAALgADCgEJAgAAAA==.',
Si='Siegeshock:BAAALgADCgUJBQABLgAECgQJDQAgAAAAAA==.Silentbobb:BAAALgADCgcJBwAAAA==.',
Sn='Snow:BAAALgAFFAEJAQABLgAECgkJQAAIAAQlAA==.',
So='Soothe:BAABLgAECn8XAAIVAAYJgxk5JACcAQZoDAAABABAAGkMAAAFAE0AawwAAAUANwBqDAAAAQA6AGwMAAACADkA6gwAAAYATgAVAAYJgxk5JACcAQZoDAAABABAAGkMAAAFAE0AawwAAAUANwBqDAAAAQA6AGwMAAACADkA6gwAAAYATgAAAA==.',
St='Stormride:BAAALgAECgIJAwAAAA==.',
Sw='Swaggasaurus:BAABLgAECn8lAAMJAAgJxiHXIwByAghoDAAABQBjAGkMAAAFAFEAawwAAAUASwBqDAAAAwBVAGwMAAAGAFIAbQwAAAMAWQDqDAAABwBeAG4MAAADAFEACQAICcYh1yMAcgIIaAwAAAUAYwBpDAAABQBRAGsMAAAFAEsAagwAAAMAVQBsDAAABgBSAG0MAAACAFkA6gwAAAcAXgBuDAAAAwBRABoAAQmXAxuPACwAAW0MAAABAAkAAAA=.',
Sy='Sylarien:BAAALgAECgYJCgAAAA==.Syriena:BAAALgADCggJAwAAAA==.',
Ta='Tadok:BAAALgADCgUJBQAAAA==.Talset:BAACLgAFFH8RAAISAAQJURkeFQBaAQRoDAAABQBIAGkMAAADAFUAawwAAAIAEgDqDAAABwBTABIABAlRGR4VAFoBBGgMAAAFAEgAaQwAAAMAVQBrDAAAAgASAOoMAAAHAFMALgAECn8fAAISAAgJRB9LEwBUAgASAAgJRB9LEwBUAgAAAA==.',
Te='Tengoo:BAAALgAECgUJBQAAAA==.',
Th='Thewaitress:BAABLgAFFH8FAAIJAAIJBxVokACHAAJoDAAAAwA3AOoMAAACADQACQACCQcVaJAAhwACaAwAAAMANwDqDAAAAgA0AAAA.Thylight:BAAALgAECgUJBgAAAA==.',
To='Tooperdy:BAAALgADCgIJAgAAAA==.',
Tr='Trappe:BAAALgADCgcJBwAAAA==.',
Tu='Tusker:BAAALgAECgcJDQAAAA==.',
Tw='Twostunz:BAAALgADCgcJDAAAAA==.',
Ty='Tysotcan:BAAALgAECgEJAQAAAA==.',
Ur='Ursalvation:BAAALgADCgUJBQAAAA==.',
Va='Vad:BAAALgAECgIJBwAAAA==.',
Ve='Veew:BAABLgAECn8XAAMSAAgJ8RGROgC8AQhoDAAABAA8AGkMAAAEAEUAawwAAAQAOgBqDAAAAwAwAGwMAAADADcAbQwAAAEAEADqDAAAAwAsAG8MAAABABAAEgAICToRkToAvAEIaAwAAAMAPABpDAAAAwBFAGsMAAADADoAagwAAAEAMABsDAAAAgAqAG0MAAABABAA6gwAAAMALABvDAAAAQAQABMABQmyEQobABkBBWgMAAABADkAaQwAAAEAPgBrDAAAAQAGAGoMAAACACQAbAwAAAEANwAAAA==.',
Vy='Vynaca:BAAALgAECgIJBwAAAA==.',
Wa='Warpedshadow:BAAALgAECggJCwAAAA==.',
Wh='Whitegoddess:BAABLgAECn8pAAIhAAgJTQzZZwBuAQhoDAAABwAjAGkMAAAGADMAawwAAAYAJwBqDAAABgApAGwMAAAFABQAbQwAAAMAFwDqDAAABAAiAG4MAAAEABAAIQAICU0M2WcAbgEIaAwAAAcAIwBpDAAABgAzAGsMAAAGACcAagwAAAYAKQBsDAAABQAUAG0MAAADABcA6gwAAAQAIgBuDAAABAAQAAAA.',
Wo='Wontan:BAAALgAECgcJCAAAAA==.',
Wu='Wukong:BAAALgAECgQJBAAAAA==.',
Xa='Xania:BAAALgAECgIJBwAAAA==.',
Yu='Yungmage:BAABLgAECn8dAAINAAcJYBuQggDMAQdoDAAABgBUAGkMAAAGAF0AawwAAAUAVwBqDAAABgBSAGwMAAABAEIAbQwAAAEAEQDqDAAABABGAA0ABwlgG5CCAMwBB2gMAAAGAFQAaQwAAAYAXQBrDAAABQBXAGoMAAAGAFIAbAwAAAEAQgBtDAAAAQARAOoMAAAEAEYAAAA=.',
Za='Zaifu:BAAALgAECgIJBwAAAA==.',
Zi='Ziggy:BAABLgAECn8ZAAINAAkJABhSRQBoAgloDAAABABaAGkMAAAEAFEAawwAAAQASABqDAAAAwBLAGwMAAADAEQAbQwAAAEAQgDqDAAABABIAG4MAAABAAoAbwwAAAEAHQANAAkJABhSRQBoAgloDAAABABaAGkMAAAEAFEAawwAAAQASABqDAAAAwBLAGwMAAADAEQAbQwAAAEAQgDqDAAABABIAG4MAAABAAoAbwwAAAEAHQAAAA==.',
['Èl']='Èlfman:BAABLgAECn8VAAIGAAcJJhgWNADIAQdoDAAAAgAWAGkMAAAFAD0AawwAAAQAOgBqDAAABABKAGwMAAAEAEkAbQwAAAEAVgBuDAAAAQA3AAYABwkmGBY0AMgBB2gMAAACABYAaQwAAAUAPQBrDAAABAA6AGoMAAAEAEoAbAwAAAQASQBtDAAAAQBWAG4MAAABADcAAAA=.',
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
