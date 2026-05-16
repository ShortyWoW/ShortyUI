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

local lookup = {'Hunter-Marksmanship','Hunter-BeastMastery','Hunter-Survival','Rogue-Subtlety','DemonHunter-Devourer','Priest-Shadow','Warrior-Protection','Mage-Frost','Monk-Windwalker','DeathKnight-Unholy','Druid-Restoration','Druid-Balance','Shaman-Elemental','Shaman-Restoration','Paladin-Retribution','Priest-Discipline','Priest-Holy','Evoker-Augmentation','Evoker-Devastation','Unknown-Unknown','Paladin-Holy','Warrior-Arms','Warrior-Fury','DeathKnight-Frost','Monk-Brewmaster','Monk-Mistweaver','Shaman-Enhancement','Rogue-Assassination','Rogue-Outlaw','Paladin-Protection','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Evoker-Preservation',}
local provider = {region='US',realm='Auchindoun',name='US',type='daily',zone=46,date='2026-05-14',data={Ad='Adnerb:BAABLgAECn8VAAQBAAgJNxLnEgDaAAhoDAAABwBNAGkMAAADADAAawwAAAMAMQBqDAAAAgAzAGwMAAABACQAbQwAAAEAGADqDAAAAwBIAG4MAAABABAAAQAGCQIT5xIA2gAGaAwAAAcATQBpDAAAAgAqAGsMAAABACUAbAwAAAEAJABtDAAAAQAYAOoMAAADAEgAAgAECeoOvYoAqgAEaQwAAAEAMABrDAAAAQAxAGoMAAABADMAbgwAAAEAEAADAAIJkQcASAA4AAJrDAAAAQATAGoMAAABABMAAS4ABRQFCQcABAAlEQA=.',
Ah='Ahriman:BAABLgAECn8XAAIFAAYJLw7vbgDgAAZoDAAABgA1AGkMAAAFACYAawwAAAQAJQBqDAAAAwAvAGwMAAACACIA6gwAAAMAEQAFAAYJLw7vbgDgAAZoDAAABgA1AGkMAAAFACYAawwAAAQAJQBqDAAAAwAvAGwMAAACACIA6gwAAAMAEQAAAA==.',
Al='Alystra:BAABLgAECn8YAAIGAAcJGwdJLwD/AAdoDAAABQAQAGkMAAAEABYAawwAAAQAEgBqDAAAAwAeAGwMAAADABgAbQwAAAEADADqDAAABAANAAYABwkbB0kvAP8AB2gMAAAFABAAaQwAAAQAFgBrDAAABAASAGoMAAADAB4AbAwAAAMAGABtDAAAAQAMAOoMAAAEAA0AAAA=.',
An='Anjedin:BAAALgAECgYJCwAAAA==.',
Ao='Aoki:BAABLgAECn8hAAICAAgJ1iAjGAA4AghoDAAABgBfAGkMAAAGAF4AawwAAAUATwBqDAAABgBgAGwMAAAEAF0AbQwAAAEANgDqDAAAAgBVAG4MAAADAFUAAgAICdYgIxgAOAIIaAwAAAYAXwBpDAAABgBeAGsMAAAFAE8AagwAAAYAYABsDAAABABdAG0MAAABADYA6gwAAAIAVQBuDAAAAwBVAAAA.',
Ar='Archdemon:BAABLgAECn8iAAIHAAkJOhiCCAAYAgloDAAABgA7AGkMAAAFAEkAawwAAAUASgBqDAAAAwAxAGwMAAAEACwAbQwAAAIAMQDqDAAABgBCAG4MAAACAEMAbwwAAAEAPQAHAAkJOhiCCAAYAgloDAAABgA7AGkMAAAFAEkAawwAAAUASgBqDAAAAwAxAGwMAAAEACwAbQwAAAIAMQDqDAAABgBCAG4MAAACAEMAbwwAAAEAPQAAAA==.Argonos:BAAALgAECgcJDQAAAA==.Arielias:BAAALgAECgkJDQABLgAFFAUJBwAEACURAA==.Arkanoas:BAACLgAFFH8MAAIIAAQJNAvoQAAzAQRoDAAABAA3AGkMAAADAB8AawwAAAMAFgDqDAAAAgAEAAgABAk0C+hAADMBBGgMAAAEADcAaQwAAAMAHwBrDAAAAwAWAOoMAAACAAQALgAECn8rAAIIAAkJthYMOACUAgAIAAkJthYMOACUAgAAAA==.',
As='Ashatal:BAAALgADCgEJAQAAAA==.Ashphantom:BAAALgAECgIJAgAAAA==.',
Ba='Bagelbite:BAAALgADCgUJBQAAAA==.Banshee:BAAALgAECgYJDAABLgAFFAUJBwAEACURAA==.Battahelin:BAAALgAECgQJBgAAAA==.Bazoo:BAAALgAECgEJAQAAAA==.',
Be='Bearmanowl:BAAALgAECgYJBwAAAA==.Bellator:BAAALgAECgMJBAAAAA==.',
Bi='Bigchungus:BAABLgAECn8dAAIJAAYJ/Aj1NwDDAAZoDAAABgAgAGkMAAAGABEAawwAAAYAFgBqDAAABAASAGwMAAADABEA6gwAAAQAGQAJAAYJ/Aj1NwDDAAZoDAAABgAgAGkMAAAGABEAawwAAAYAFgBqDAAABAASAGwMAAADABEA6gwAAAQAGQAAAA==.',
Bl='Blart:BAAALgAECgUJBwAAAA==.Bloody:BAAALgAECgUJBQAAAA==.',
Br='Breathplay:BAABLgAECn8YAAIKAAkJbRqWPQBBAgloDAAABABQAGkMAAAEAEoAawwAAAQAOwBqDAAAAgA6AGwMAAACAEYAbQwAAAIAQQDqDAAAAwBLAG4MAAACAEQAbwwAAAEALwAKAAkJbRqWPQBBAgloDAAABABQAGkMAAAEAEoAawwAAAQAOwBqDAAAAgA6AGwMAAACAEYAbQwAAAIAQQDqDAAAAwBLAG4MAAACAEQAbwwAAAEALwAAAA==.',
['Bà']='Bàyne:BAABLgAECn8yAAILAAkJUBMIIQDmAQloDAAABwAuAGkMAAAHAEcAawwAAAcAPgBqDAAABgAxAGwMAAAGAEMAbQwAAAQAIwDqDAAABwBEAG4MAAAEABwAbwwAAAIADgALAAkJUBMIIQDmAQloDAAABwAuAGkMAAAHAEcAawwAAAcAPgBqDAAABgAxAGwMAAAGAEMAbQwAAAQAIwDqDAAABwBEAG4MAAAEABwAbwwAAAIADgAAAA==.',
Ca='Caroquintero:BAABLgAECn8eAAIIAAYJcgOXvAC9AAZoDAAABgADAGkMAAAGABAAawwAAAYACABqDAAABAALAGwMAAAEAAkA6gwAAAQABgAIAAYJcgOXvAC9AAZoDAAABgADAGkMAAAGABAAawwAAAYACABqDAAABAALAGwMAAAEAAkA6gwAAAQABgAAAA==.',
Ch='Charliemen:BAAALgAECgQJBAAAAA==.Chilli:BAAALgADCgEJAQAAAA==.Chubtart:BAACLgAFFH8GAAIMAAMJ6RtXFwASAQNoDAAAAwBRAGkMAAACADAA6gwAAAEAVAAMAAMJ6RtXFwASAQNoDAAAAwBRAGkMAAACADAA6gwAAAEAVAAuAAQKfzIAAgwACQnQIz0IABIDAAwACQnQIz0IABIDAAAA.Churrasco:BAAALgAECgQJCAAAAA==.',
Cl='Clayton:BAAALgADCgcJBAAAAA==.',
Co='Cojeculos:BAAALgAECgIJAgAAAA==.',
Cu='Cunumi:BAAALgAECgMJBAAAAA==.',
Da='Daddy:BAABLgAECn8wAAMNAAkJZBXVEAAHAgloDAAABwBKAGkMAAAGADEAawwAAAYAMgBqDAAABwAmAGwMAAAGAC0AbQwAAAMAOwDqDAAACAA3AG4MAAAEAFMAbwwAAAEAEwANAAkJZBXVEAAHAgloDAAABQBKAGkMAAAEADEAawwAAAQAMgBqDAAABQAmAGwMAAAEAC0AbQwAAAMAOwDqDAAABAA3AG4MAAAEAFMAbwwAAAEAEwAOAAYJsQpMWQAjAQZoDAAAAgAmAGkMAAACABcAawwAAAIAEABqDAAAAgAUAGwMAAACADEA6gwAAAQADwAAAA==.Danehar:BAAALgAECgEJAQAAAA==.',
Dc='Dcone:BAAALgADCgYJBgAAAA==.',
De='Deadkey:BAAALgADCgEJAQAAAA==.Deathborne:BAAALgAECgUJCQAAAA==.Deathshreik:BAAALgADCgMJAwAAAA==.Deathslam:BAACLgAFFH8FAAIKAAQJngVsSgAVAQRoDAAAAgAdAGkMAAABAAcAawwAAAEACQDqDAAAAQALAAoABAmeBWxKABUBBGgMAAACAB0AaQwAAAEABwBrDAAAAQAJAOoMAAABAAsALgAECn8gAAIKAAgJqBlpJwALAgAKAAgJqBlpJwALAgAAAA==.',
Dr='Droston:BAAALgADCgQJBAAAAA==.',
Du='Dutchess:BAABLgAECn8eAAIPAAgJPxkfLwDnAQhoDAAABQBFAGkMAAAFAFIAawwAAAQASABqDAAABAA6AGwMAAAFAFQAbQwAAAIAQwDqDAAABAA7AG4MAAABABEADwAICT8ZHy8A5wEIaAwAAAUARQBpDAAABQBSAGsMAAAEAEgAagwAAAQAOgBsDAAABQBUAG0MAAACAEMA6gwAAAQAOwBuDAAAAQARAAAA.',
Dy='Dylan:BAACLgAFFH8QAAIIAAQJ9hvBIAB3AQRoDAAABAA1AGkMAAAFAFsAawwAAAMAOADqDAAABABVAAgABAn2G8EgAHcBBGgMAAAEADUAaQwAAAUAWwBrDAAAAwA4AOoMAAAEAFUALgAECn8nAAIIAAkJ4CQNAwBXAwAIAAkJ4CQNAwBXAwAAAA==.Dylanj:BAAALgAECgQJBAABLgAFFAQJEAAIAPYbAQ==.',
Ec='Echevalier:BAAALgAECgQJBQAAAA==.',
Eg='Egonspengler:BAAALgADCgQJBAAAAA==.',
El='Elowen:BAAALgAFFAEJAQAAAQ==.',
En='Enhae:BAAALgAECgEJAQAAAA==.',
Er='Eresiine:BAAALgAECgcJCgAAAA==.Eríngo:BAAALgAECgcJCwAAAA==.',
Es='Esna:BAAALgADCgUJBwAAAA==.',
Fi='Filomena:BAAALgADCgUJBgAAAA==.Firnin:BAAALgAECgYJEAAAAA==.',
Fl='Floise:BAACLgAFFH8OAAMQAAQJ0hUoFAA7AQRoDAAABQAuAGkMAAAEADsAawwAAAMASgDqDAAAAgApABAABAlRFCgUADsBBGgMAAACAC4AaQwAAAMALABrDAAAAwBKAOoMAAACACkAEQACCVQTWQ0AkwACaAwAAAMAJwBpDAAAAQA7AC4ABAp/HgAEEQAJCfsZdwwAjAIAEQAJCUAZdwwAjAIAEAAHCREVcTYAuQAABgABCVwS7lgAPQAAAAA=.Flounder:BAAALgAECgEJAwAAAA==.',
Fo='Foamtotem:BAAALgADCgEJAQAAAA==.Forumsoldier:BAABLgAECn8jAAIIAAgJlhcoVAA8AghoDAAABQBHAGkMAAAFAD8AawwAAAUAPQBqDAAABQAyAGwMAAAFAEoAbQwAAAMAJgDqDAAABQBKAG4MAAACACcACAAICZYXKFQAPAIIaAwAAAUARwBpDAAABQA/AGsMAAAFAD0AagwAAAUAMgBsDAAABQBKAG0MAAADACYA6gwAAAUASgBuDAAAAgAnAAAA.',
Fr='Frozenscorch:BAAALgAECggJEQAAAA==.',
['Fä']='Fälkor:BAABLgAECn8rAAMSAAgJrAabMQAAAQhoDAAABwAdAGkMAAAGABgAawwAAAUAEwBqDAAABgAZAGwMAAAGABMAbQwAAAQACgDqDAAABgAIAG4MAAADAAcAEgAICawGmzEAAAEIaAwAAAUAHQBpDAAABAAYAGsMAAAEABMAagwAAAUAFwBsDAAABQATAG0MAAAEAAoA6gwAAAYACABuDAAAAgAHABMABgkkBjwOAM8ABmgMAAACABMAaQwAAAIAFABrDAAAAQAPAGoMAAABABkAbAwAAAEADwBuDAAAAQAHAAAA.',
['Fö']='Föx:BAAALgAECgEJAgABLgAECgYJEQAUAAAAAA==.',
Gi='Gigamoo:BAAALgAECgQJBgAAAA==.',
Gl='Glorfindel:BAAALgAFFAEJAQABLgAFFAQJCQAMAGYWAA==.Glys:BAAALgAECgUJCgAAAA==.',
Go='Gogocow:BAAALgAECgEJAQAAAA==.Gooba:BAAALgAECgEJAQAAAA==.Goommar:BAAALgAECgYJDAAAAA==.Gorim:BAAALgAECgIJAgAAAA==.',
Gr='Grandgoose:BAAALgADCgIJAgAAAA==.Granuju:BAAALgADCgUJBgAAAA==.',
Gu='Gunnhildr:BAAALgADCgkJCQAAAA==.',
Ha='Hanasanai:BAAALgADCgMJBAAAAA==.Handil:BAABLgAECn8aAAIVAAYJRiEjGADqAQZoDAAABQBZAGkMAAAFAFoAawwAAAUAXgBqDAAABQBcAGwMAAABADwA6gwAAAUAUwAVAAYJRiEjGADqAQZoDAAABQBZAGkMAAAFAFoAawwAAAUAXgBqDAAABQBcAGwMAAABADwA6gwAAAUAUwAAAA==.',
He='Helpingyou:BAAALgAECggJEgAAAA==.',
Ho='Holybell:BAAALgAECgIJAgAAAA==.Hoptyj:BAAALgADCgIJAgAAAA==.',
['Hë']='Hënnessy:BAAALgADCgMJAwAAAA==.Hënnëssy:BAABLgAECn8ZAAIVAAcJsRIlIgCYAQdoDAAABABYAGkMAAAEAB0AawwAAAQALgBqDAAABAA3AGwMAAADAC0AbQwAAAEABADqDAAABQBAABUABwmxEiUiAJgBB2gMAAAEAFgAaQwAAAQAHQBrDAAABAAuAGoMAAAEADcAbAwAAAMALQBtDAAAAQAEAOoMAAAFAEAAAAA=.',
Im='Impaladin:BAAALgADCgYJCgAAAA==.',
Io='Iolanthe:BAAALgADCgQJBAAAAA==.',
Iz='Izeroeasily:BAAALgAECgMJAwAAAA==.Izerohealz:BAAALgADCgQJBAAAAA==.Izzi:BAAALgAECgYJEQAAAA==.Izzia:BAABLgAECn8YAAILAAcJzRohGAAqAgdoDAAABQBSAGkMAAAEAFQAawwAAAUAPgBqDAAAAgBGAGwMAAACAEgAbQwAAAEAGwDqDAAABQBRAAsABwnNGiEYACoCB2gMAAAFAFIAaQwAAAQAVABrDAAABQA+AGoMAAACAEYAbAwAAAIASABtDAAAAQAbAOoMAAAFAFEAAAA=.',
Ja='Jabbathabutt:BAAALgAECgYJCAAAAA==.Jasia:BAAALgADCgYJCAAAAA==.',
Jo='Joyboy:BAAALgAECgEJAQAAAA==.',
Ju='Justfn:BAAALgADCgUJBwAAAA==.',
Ka='Kamitos:BAABLgAECn8rAAMQAAgJfBDzFgCxAQhoDAAACAAlAGkMAAAIADUAawwAAAQAOABqDAAABgAnAGwMAAAGACgAbQwAAAEAEgDqDAAABgA5AG4MAAAEACEAEAAICXwQ8xYAsQEIaAwAAAYAJQBpDAAABwA1AGsMAAADADgAagwAAAQAJwBsDAAABAAoAG0MAAABABIA6gwAAAYAOQBuDAAABAAhAAYABQnICGZEANkABWgMAAACACIAaQwAAAEAFgBrDAAAAQAbAGoMAAACABsAbAwAAAIABAAAAA==.Kayewyn:BAABLgAECn8cAAILAAgJ4A/9MgB1AQhoDAAABgBWAGkMAAAGAD0AawwAAAYAIQBqDAAAAwAUAGwMAAACACQAbQwAAAEADwDqDAAAAwApAG4MAAABAB0ACwAICeAP/TIAdQEIaAwAAAYAVgBpDAAABgA9AGsMAAAGACEAagwAAAMAFABsDAAAAgAkAG0MAAABAA8A6gwAAAMAKQBuDAAAAQAdAAAA.',
Kb='Kbdh:BAAALgAECgYJCQABLgAFFAIJAwAUAAAAAA==.Kbdruid:BAAALgAFFAEJAQABLgAFFAIJAwAUAAAAAA==.Kbhunter:BAAALgAECgUJCAABLgAFFAIJAwAUAAAAAA==.Kbmage:BAAALgADCgQJBAABLgAFFAIJAwAUAAAAAA==.Kbmonk:BAAALgAFFAIJAwAAAA==.Kbpaladin:BAAALgAECgYJBgABLgAFFAIJAwAUAAAAAA==.',
Ke='Keiji:BAAALgAECgYJDgAAAA==.',
Kl='Klipnor:BAAALgAECgQJCAAAAA==.',
Kr='Krocketeer:BAAALgAECgYJCQAAAA==.',
Ky='Kyndel:BAAALgAECgYJCgABLgAFFAQJEQALAD8bAA==.Kynn:BAACLgAFFH8RAAILAAQJPxu+EwBUAQRoDAAABgBSAGkMAAAFAFEAawwAAAQAPQDqDAAAAgA0AAsABAk/G74TAFQBBGgMAAAGAFIAaQwAAAUAUQBrDAAABAA9AOoMAAACADQALgAECn80AAILAAkJlCLzAQCBAwALAAkJlCLzAQCBAwAAAA==.',
['Kè']='Kèlemvore:BAABLgAECn8mAAIPAAgJNBFZUgBzAQhoDAAABgA4AGkMAAAGADwAawwAAAYAPgBqDAAABQA2AGwMAAAGACEAbQwAAAEADwDqDAAABgA6AG4MAAACABUADwAICTQRWVIAcwEIaAwAAAYAOABpDAAABgA8AGsMAAAGAD4AagwAAAUANgBsDAAABgAhAG0MAAABAA8A6gwAAAYAOgBuDAAAAgAVAAAA.',
Le='Leafittome:BAAALgADCgEJAQAAAA==.',
Ly='Lykos:BAAALgAECgYJDgAAAA==.',
Ma='Mammal:BAAALgAECgQJBAABLgAECggJGAANAKYZAA==.',
Me='Medxchaos:BAAALgAECgQJBwABLgAFFAQJDgAQANIVAA==.Meowy:BAAALgAECgEJAQAAAA==.Mepha:BAABLgAECn8rAAMWAAkJliC4AwCSAgloDAAABwBYAGkMAAAHAFsAawwAAAcAWwBqDAAABQBMAGwMAAAEAEkAbQwAAAMAPQDqDAAABgBhAG4MAAADAEkAbwwAAAEAWgAWAAkJXR24AwCSAgloDAAAAwBIAGkMAAADAFIAawwAAAMAUABqDAAAAwAXAGwMAAACAEkAbQwAAAIAPQDqDAAAAwBEAG4MAAADAEkAbwwAAAEAWgAXAAcJ+B/yGACDAgdoDAAABABYAGkMAAAEAFsAawwAAAQAWwBqDAAAAgBMAGwMAAACAEUAbQwAAAEAMwDqDAAAAwBhAAAA.',
Mi='Mightymost:BAAALgADCgMJAwAAAA==.',
Mu='Muddless:BAABLgAECn8eAAMWAAgJkh/mBABnAghoDAAABQBJAGkMAAAFAFcAawwAAAMAUgBqDAAAAwA7AGwMAAAEAFwAbQwAAAEASgDqDAAABgBbAG4MAAADAEAAFgAICZIf5gQAZwIIaAwAAAUASQBpDAAABQBXAGsMAAADAFIAagwAAAMAOwBsDAAABABcAG0MAAABAEoA6gwAAAQAWwBuDAAAAwBAABcAAQnqC82lADkAAeoMAAACAB4AAAA=.Mudds:BAABLgAECn8cAAIJAAgJoSB7EAB5AghoDAAABgBVAGkMAAAFAFoAawwAAAUAWABqDAAAAgBMAGwMAAACAFQAbQwAAAIAUgDqDAAABQBXAG4MAAABAEEACQAICaEgexAAeQIIaAwAAAYAVQBpDAAABQBaAGsMAAAFAFgAagwAAAIATABsDAAAAgBUAG0MAAACAFIA6gwAAAUAVwBuDAAAAQBBAAAA.',
Na='Naelia:BAAALgAECgYJEAABLgAFFAQJEAAKAI8QAA==.Nakira:BAAALgAECgMJAwAAAA==.Nami:BAAALgAECgUJBQAAAA==.',
Ni='Nicodemus:BAAALgADCgIJAgAAAA==.Nightrush:BAABLgAECn8oAAMCAAgJISXxDwB8AghoDAAABwBjAGkMAAAHAGIAawwAAAYAYQBqDAAABQBdAGwMAAADAFEAbQwAAAMAXQDqDAAABgBiAG4MAAADAGAAAgAGCQMm8Q8AfAIGaAwAAAEAYwBpDAAAAQBiAGsMAAACAGEAbQwAAAMAXQDqDAAAAQBiAG4MAAADAGAAAQAGCbQhwwcApgEGaAwAAAYAWwBpDAAABgBXAGsMAAAEAFQAagwAAAUAXQBsDAAAAwBRAOoMAAAFAFYAAAA=.',
No='Noodles:BAABLgAECn8XAAIFAAYJehZpawBgAQZoDAAABQBGAGkMAAAFADkAawwAAAUAMwBqDAAABABMAGwMAAACACwA6gwAAAIAPwAFAAYJehZpawBgAQZoDAAABQBGAGkMAAAFADkAawwAAAUAMwBqDAAABABMAGwMAAACACwA6gwAAAIAPwAAAA==.Norbit:BAAALgAECgEJAQAAAA==.',
Oe='Oesteroth:BAABLgAECn8UAAILAAYJbgUaYwC2AAZoDAAABAAYAGkMAAAEAAkAawwAAAQACQBqDAAAAwAUAGwMAAABAAgA6gwAAAQACgALAAYJbgUaYwC2AAZoDAAABAAYAGkMAAAEAAkAawwAAAQACQBqDAAAAwAUAGwMAAABAAgA6gwAAAQACgAAAA==.',
Ok='Okomo:BAAALgAECgEJAQABLgAECgMJAwAUAAAAAA==.',
Pa='Palaben:BAABLgAECn8bAAMVAAgJdRGYLABOAQhoDAAABAAyAGkMAAAEAFsAawwAAAQANQBqDAAABAAiAGwMAAADACYAbQwAAAIAFgDqDAAAAwA9AG4MAAADAAMAFQAHCawSmCwATgEHaAwAAAQAMgBpDAAABABbAGsMAAAEADUAagwAAAMAIgBsDAAAAgAmAOoMAAADAD0AbgwAAAEAAwAPAAQJWgxYzgCMAARqDAAAAQAGAGwMAAABABkAbQwAAAIAGgBuDAAAAgAqAAAA.Pantsu:BAABLgAECn85AAMKAAgJfiUfCgDfAghoDAAACQBiAGkMAAAJAGMAawwAAAgAYgBqDAAABwBdAGwMAAAGAF8AbQwAAAUAWQDqDAAACABeAG4MAAAFAGAACgAICX4lHwoA3wIIaAwAAAgAYgBpDAAACABjAGsMAAAHAGIAagwAAAYAXQBsDAAABQBfAG0MAAAEAFkA6gwAAAcAXgBuDAAABABgABgACAn9H1YCAGYCCGgMAAABAFQAaQwAAAEAXABrDAAAAQBbAGoMAAABAD8AbAwAAAEAWgBtDAAAAQBFAOoMAAABAEgAbgwAAAEARwAAAA==.Pateaviejas:BAAALgAECgMJAwAAAA==.Pawnchy:BAAALgAECgUJCQAAAA==.',
Pe='Peepaw:BAAALgAECgYJEQAAAA==.',
Pi='Pitchwhite:BAABLgAECn8XAAIRAAYJHBEdLQAHAQZoDAAABQA7AGkMAAAEACMAawwAAAQAOwBqDAAABAAzAGwMAAABABIA6gwAAAUAJgARAAYJHBEdLQAHAQZoDAAABQA7AGkMAAAEACMAawwAAAQAOwBqDAAABAAzAGwMAAABABIA6gwAAAUAJgAAAA==.Pixel:BAAALgADCgkJDQAAAA==.',
Pr='Proselyte:BAACLgAFFH8IAAIJAAMJrBRUEgDsAANoDAAAAwAmAGkMAAADADMA6gwAAAIARAAJAAMJrBRUEgDsAANoDAAAAwAmAGkMAAADADMA6gwAAAIARAAuAAQKfyIAAgkACQmxHRMHAIQCAAkACQmxHRMHAIQCAAAA.',
Pu='Punchbear:BAAALgADCgQJBAAAAA==.Punchize:BAABLgAECn8dAAMZAAgJwBzBCwAoAghoDAAABQBiAGkMAAAGAFQAawwAAAYARwBqDAAAAwBgAGwMAAACADwAbQwAAAEAVQDqDAAABQBWAG4MAAABAB0AGQAICcAcwQsAKAIIaAwAAAUAYgBpDAAABQBUAGsMAAAFAEcAagwAAAMAYABsDAAAAgA8AG0MAAABAFUA6gwAAAUAVgBuDAAAAQAdABoAAgn0CjJdAEkAAmkMAAABACAAawwAAAEAFwAAAA==.Punchlocks:BAAALgAECgEJAQAAAA==.',
Qu='Quirkchungus:BAAALgAECgUJCAAAAA==.',
Ra='Rakrak:BAAALgADCgEJAQAAAA==.Rani:BAAALgADCgUJBQAAAA==.Rathon:BAAALgAECgkJDAAAAA==.',
Re='Remote:BAAALgAECgMJAwAAAA==.',
Ri='Rianis:BAAALgADCgcJEAAAAA==.Rilea:BAAALgAECgYJEAAAAA==.',
['Rä']='Räiyu:BAAALgADCgMJAwAAAA==.',
Sa='Sadgasm:BAABLgAECn8eAAIbAAkJmx6sAgCaAgloDAAABQBfAGkMAAAFAGEAawwAAAUATABqDAAAAwBOAGwMAAADAEIAbQwAAAEAJgDqDAAABgBVAG4MAAABAFUAbwwAAAEAUgAbAAkJmx6sAgCaAgloDAAABQBfAGkMAAAFAGEAawwAAAUATABqDAAAAwBOAGwMAAADAEIAbQwAAAEAJgDqDAAABgBVAG4MAAABAFUAbwwAAAEAUgAAAA==.Safeword:BAAALgAECgkJCwAAAA==.Sauron:BAAALgAECgMJBQAAAA==.',
Se='Sebrine:BAAALgAECgUJCwAAAA==.Seishan:BAACLgAFFH8HAAMEAAUJJRH+GADpAAVoDAAAAgA/AGkMAAABAEIAawwAAAEAEABqDAAAAQArAOoMAAACABwABAAFCSUR/hgA6QAFaAwAAAIAPwBpDAAAAQBCAGsMAAABABAAagwAAAEAKwDqDAAAAQAcABwAAQmvCfILAFAAAeoMAAABABgALgAECn8fAAQcAAcJkxsqBwD0AQAcAAYJ1R4qBwD0AQAEAAUJxhddLAC+AAAdAAEJ+xcKFQBGAAAAAA==.Seneca:BAAALgAECgEJBAAAAA==.',
Sh='Shadowtalon:BAAALgADCgEJAQAAAA==.Shamandrea:BAAALgAECgYJBgABLgAECggJHwARADgYAA==.Shzam:BAAALgADCgYJDgAAAA==.',
Sl='Slam:BAAALgADCgMJBQAAAA==.Sleipner:BAABLgAECn8fAAIeAAkJAQ7ZEABPAQloDAAABABTAGkMAAAEADQAawwAAAQAJgBqDAAABAAdAGwMAAAEABsAbQwAAAMAEgDqDAAABQAhAG4MAAACABMAbwwAAAEADAAeAAkJAQ7ZEABPAQloDAAABABTAGkMAAAEADQAawwAAAQAJgBqDAAABAAdAGwMAAAEABsAbQwAAAMAEgDqDAAABQAhAG4MAAACABMAbwwAAAEADAAAAA==.',
Sm='Smiley:BAAALgADCgYJBgAAAA==.',
Sn='Sneeze:BAAALgADCgIJAgAAAA==.Snugglehex:BAAALgADCgEJAQAAAA==.',
So='Socktrout:BAABLgAECn8qAAQfAAkJnReOJgDwAQloDAAABgAzAGkMAAAFAEkAawwAAAQAQwBqDAAAAwAbAGwMAAAGACkAbQwAAAUAPwDqDAAABgBBAG4MAAAEAEsAbwwAAAMAKwAfAAgJexaOJgDwAQhoDAAABgAzAGkMAAAFAEkAawwAAAQAQwBsDAAAAgApAG0MAAACAD8A6gwAAAYAQQBuDAAABABLAG8MAAACABQAIAADCekKEkMAqQADagwAAAIAGwBsDAAABAAgAG0MAAADABYAIQACCS0RYhwATQACagwAAAEABgBvDAAAAQArAAAA.Softgrizzly:BAAALgADCgMJAwAAAA==.Solidgold:BAACLgAFFH8UAAMXAAcJLhkyAgDIAQdoDAAABABbAGkMAAADAFMAawwAAAMALgBqDAAAAwBaAGwMAAACADAAbQwAAAEAFQDqDAAABABfABcABwkuGTICAMgBB2gMAAAEAFsAaQwAAAMAUwBrDAAAAwAuAGoMAAADAFoAbAwAAAEAMABtDAAAAQAVAOoMAAAEAF8AFgABCaAGugsAUwABbAwAAAEAEAAuAAQKfyoAAxcACAm+JMoTALACABcACAmWI8oTALACABYABQmoIPwcAAgBAAAA.Solvane:BAAALgAECgMJAwABLgAFFAUJBwAEACURAA==.',
Sp='Spongeybob:BAAALgADCgEJAgAAAA==.',
Ss='Sscrubbucket:BAAALgAECgYJBgAAAA==.',
Su='Sunrise:BAAALgADCgkJEAAAAA==.',
Sy='Syllassa:BAAALgAECgkJAQAAAA==.Sylv:BAAALgADCgQJBgAAAA==.',
Ta='Taelia:BAACLgAFFH8QAAIKAAQJjxBLRQAjAQRoDAAABQA+AGkMAAAEABcAawwAAAMAHgDqDAAABAA1AAoABAmPEEtFACMBBGgMAAAFAD4AaQwAAAQAFwBrDAAAAwAeAOoMAAAEADUALgAECn88AAIKAAkJHSMZCAD4AgAKAAkJHSMZCAD4AgAAAA==.Tahine:BAAALgAECgYJDQAAAA==.Tans:BAAALgADCgkJCwAAAA==.',
Ti='Tiktoks:BAAALgAECgEJAQABLgAFFAQJBgARANcEAA==.Timetwoflame:BAABLgAECn8bAAIiAAgJ5RGmCgDTAQhoDAAABgA/AGkMAAAGAEUAawwAAAUAQgBqDAAAAQATAGwMAAABABwAbQwAAAEAIgDqDAAABAAyAG4MAAADACEAIgAICeURpgoA0wEIaAwAAAYAPwBpDAAABgBFAGsMAAAFAEIAagwAAAEAEwBsDAAAAQAcAG0MAAABACIA6gwAAAQAMgBuDAAAAwAhAAAA.',
Tn='Tnarg:BAAALgADCgIJAgAAAA==.',
To='Tokki:BAAALgAECgYJBwAAAA==.',
Tr='Trekvis:BAAALgADCgcJDgAAAA==.',
Tu='Tugboat:BAAALgADCgIJAgAAAA==.',
['Tû']='Tûâny:BAAALgAECgUJBQAAAA==.',
Up='Upphoria:BAABLgAECn8XAAMRAAYJ1ArTMADvAAZoDAAABQArAGkMAAAGADAAawwAAAQABABqDAAAAwAOAGwMAAACAAwA6gwAAAMAKQARAAYJ1ArTMADvAAZoDAAABAArAGkMAAAFADAAawwAAAQABABqDAAAAwAOAGwMAAACAAwA6gwAAAMAKQAGAAIJPgMOaAAkAAJoDAAAAQAEAGkMAAABAAwAAAA=.',
Ur='Urkel:BAAALgAECgEJAQAAAA==.',
Ut='Uthomage:BAAALgAECgMJAwAAAA==.',
Va='Vashi:BAAALgADCgcJBwAAAA==.',
Vi='Viccan:BAABLgAECn8iAAIgAAkJ/AbUDAAdAQloDAAABgAeAGkMAAAFABMAawwAAAUAEABqDAAAAwAIAGwMAAAEAAkAbQwAAAIABADqDAAABgAbAG4MAAACAA8AbwwAAAEAEgAgAAkJ/AbUDAAdAQloDAAABgAeAGkMAAAFABMAawwAAAUAEABqDAAAAwAIAGwMAAAEAAkAbQwAAAIABADqDAAABgAbAG4MAAACAA8AbwwAAAEAEgAAAA==.',
Wa='Walkingtanko:BAAALgADCgIJAgAAAA==.Wavés:BAAALgADCgIJAgAAAA==.',
We='Wef:BAAALgADCgcJBwAAAA==.',
Wi='Willowleaf:BAAALgAECgEJAQABLgAECggJHwARADgYAA==.',
Wo='Wolffie:BAAALgAECggJEQAAAA==.',
Wu='Wushuu:BAAALgAECgUJCgABLgAFFAQJDAAIADQLAA==.',
Xa='Xampu:BAAALgADCgYJBgAAAA==.',
Xe='Xernaeus:BAAALgADCgQJBAAAAA==.',
Ya='Yahwëh:BAAALgAECgMJBAAAAA==.',
Yo='Yodason:BAAALgADCgQJBQAAAA==.',
Yu='Yuukï:BAABLgAECn8iAAMJAAkJIB3OCgA9AgloDAAABgBbAGkMAAAFAFUAawwAAAYAUQBqDAAAAwA5AGwMAAAEADgAbQwAAAIAJwDqDAAABQBbAG4MAAACAFEAbwwAAAEARAAJAAgJdB3OCgA9AghoDAAABgBbAGkMAAAFAFUAawwAAAUAUQBqDAAAAwA5AGwMAAADADgAbQwAAAEAJwDqDAAABQBbAG4MAAACAFEAGgAECQgHN0wAggAEawwAAAEABwBsDAAAAQANAG0MAAABABAAbwwAAAEAIgAAAA==.',
Za='Zaelyse:BAAALgADCgMJAwAAAA==.Zaton:BAABLgAECn8XAAIIAAgJNxASUwCPAQhoDAAABAAsAGkMAAAEAEEAawwAAAQAMQBqDAAABABMAGwMAAACAA8AbQwAAAEANQDqDAAAAwAxAG4MAAABAAoACAAICTcQElMAjwEIaAwAAAQALABpDAAABABBAGsMAAAEADEAagwAAAQATABsDAAAAgAPAG0MAAABADUA6gwAAAMAMQBuDAAAAQAKAAAA.',
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
