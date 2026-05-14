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
local provider = {region='US',realm='Auchindoun',name='US',type='daily',zone=46,date='2026-05-13',data={Ad='Adnerb:BAABLgAECn8VAAQBAAgJNxIdEQDwAAhoDAAABwBNAGkMAAADADAAawwAAAMAMQBqDAAAAgAzAGwMAAABACQAbQwAAAEAGADqDAAAAwBIAG4MAAABABAAAQAGCQITHREA8AAGaAwAAAcATQBpDAAAAgAqAGsMAAABACUAbAwAAAEAJABtDAAAAQAYAOoMAAADAEgAAgAECeoOaIMAsgAEaQwAAAEAMABrDAAAAQAxAGoMAAABADMAbgwAAAEAEAADAAIJkQdqRAA7AAJrDAAAAQATAGoMAAABABMAAS4ABRQFCQcABAAlEQA=.',
Ah='Ahriman:BAABLgAECn8XAAIFAAYJLw58ZgDpAAZoDAAABgA1AGkMAAAFACYAawwAAAQAJQBqDAAAAwAvAGwMAAACACIA6gwAAAMAEQAFAAYJLw58ZgDpAAZoDAAABgA1AGkMAAAFACYAawwAAAQAJQBqDAAAAwAvAGwMAAACACIA6gwAAAMAEQAAAA==.',
Al='Alystra:BAABLgAECn8YAAIGAAcJGwebLAAGAQdoDAAABQAQAGkMAAAEABYAawwAAAQAEgBqDAAAAwAeAGwMAAADABgAbQwAAAEADADqDAAABAANAAYABwkbB5ssAAYBB2gMAAAFABAAaQwAAAQAFgBrDAAABAASAGoMAAADAB4AbAwAAAMAGABtDAAAAQAMAOoMAAAEAA0AAAA=.',
An='Anjedin:BAAALgAECgYJCwAAAA==.',
Ao='Aoki:BAABLgAECn8hAAICAAgJByHLFABFAghoDAAABgBgAGkMAAAGAF8AawwAAAUAUABqDAAABgBgAGwMAAAEAF4AbQwAAAEANgDqDAAAAgBVAG4MAAADAFUAAgAICQchyxQARQIIaAwAAAYAYABpDAAABgBfAGsMAAAFAFAAagwAAAYAYABsDAAABABeAG0MAAABADYA6gwAAAIAVQBuDAAAAwBVAAAA.',
Ar='Archdemon:BAABLgAECn8iAAIHAAkJOhh2BwAjAgloDAAABgA7AGkMAAAFAEkAawwAAAUASgBqDAAAAwAxAGwMAAAEACwAbQwAAAIAMQDqDAAABgBCAG4MAAACAEMAbwwAAAEAPQAHAAkJOhh2BwAjAgloDAAABgA7AGkMAAAFAEkAawwAAAUASgBqDAAAAwAxAGwMAAAEACwAbQwAAAIAMQDqDAAABgBCAG4MAAACAEMAbwwAAAEAPQAAAA==.Argonos:BAAALgAECgcJDQAAAA==.Arielias:BAAALgAECgkJDQABLgAFFAUJBwAEACURAA==.Arkanoas:BAACLgAFFH8MAAIIAAQJNAvAPgA1AQRoDAAABAA3AGkMAAADAB8AawwAAAMAFgDqDAAAAgAEAAgABAk0C8A+ADUBBGgMAAAEADcAaQwAAAMAHwBrDAAAAwAWAOoMAAACAAQALgAECn8rAAIIAAkJthYMOACUAgAIAAkJthYMOACUAgAAAA==.',
As='Ashatal:BAAALgADCgEJAQAAAA==.Ashphantom:BAAALgAECgIJAgAAAA==.',
Ba='Bagelbite:BAAALgADCgUJBQAAAA==.Banshee:BAAALgAECgYJDAABLgAFFAUJBwAEACURAA==.Battahelin:BAAALgAECgQJBgAAAA==.Bazoo:BAAALgAECgEJAQAAAA==.',
Be='Bearmanowl:BAAALgAECgYJBwAAAA==.Bellator:BAAALgAECgMJBAAAAA==.',
Bi='Bigchungus:BAABLgAECn8dAAIJAAYJ/AgMNQDFAAZoDAAABgAgAGkMAAAGABEAawwAAAYAFgBqDAAABAASAGwMAAADABEA6gwAAAQAGQAJAAYJ/AgMNQDFAAZoDAAABgAgAGkMAAAGABEAawwAAAYAFgBqDAAABAASAGwMAAADABEA6gwAAAQAGQAAAA==.',
Bl='Blart:BAAALgAECgUJBwAAAA==.Bloody:BAAALgAECgUJBQAAAA==.',
Br='Breathplay:BAABLgAECn8XAAIKAAgJhhuWPQBBAghoDAAABABQAGkMAAAEAEoAawwAAAQAOwBqDAAAAgA6AGwMAAACAEYAbQwAAAIAQQDqDAAAAwBLAG4MAAACAEQACgAICYYblj0AQQIIaAwAAAQAUABpDAAABABKAGsMAAAEADsAagwAAAIAOgBsDAAAAgBGAG0MAAACAEEA6gwAAAMASwBuDAAAAgBEAAAA.',
['Bà']='Bàyne:BAABLgAECn8yAAILAAkJUBO6HgDtAQloDAAABwAuAGkMAAAHAEcAawwAAAcAPgBqDAAABgAxAGwMAAAGAEMAbQwAAAQAIwDqDAAABwBEAG4MAAAEABwAbwwAAAIADgALAAkJUBO6HgDtAQloDAAABwAuAGkMAAAHAEcAawwAAAcAPgBqDAAABgAxAGwMAAAGAEMAbQwAAAQAIwDqDAAABwBEAG4MAAAEABwAbwwAAAIADgAAAA==.',
Ca='Caroquintero:BAABLgAECn8eAAIIAAYJcgM8tQDEAAZoDAAABgADAGkMAAAGABAAawwAAAYACABqDAAABAALAGwMAAAEAAkA6gwAAAQABgAIAAYJcgM8tQDEAAZoDAAABgADAGkMAAAGABAAawwAAAYACABqDAAABAALAGwMAAAEAAkA6gwAAAQABgAAAA==.',
Ch='Charliemen:BAAALgAECgQJBAAAAA==.Chilli:BAAALgADCgEJAQAAAA==.Chubtart:BAABLgAECn8yAAIMAAkJ0CM9CAASAwloDAAABQBgAGkMAAAFAFUAawwAAAYAXQBqDAAABQBXAGwMAAAHAF8AbQwAAAYAXQDqDAAACABfAG4MAAAFAFcAbwwAAAMAVgAMAAkJ0CM9CAASAwloDAAABQBgAGkMAAAFAFUAawwAAAYAXQBqDAAABQBXAGwMAAAHAF8AbQwAAAYAXQDqDAAACABfAG4MAAAFAFcAbwwAAAMAVgAAAA==.Churrasco:BAAALgAECgQJCAAAAA==.',
Cl='Clayton:BAAALgADCgcJBAAAAA==.',
Co='Cojeculos:BAAALgAECgIJAgAAAA==.',
Cu='Cunumi:BAAALgAECgMJBAAAAA==.',
Da='Daddy:BAABLgAECn8wAAMNAAkJYxUGDgAbAgloDAAABwBKAGkMAAAGADEAawwAAAYAMgBqDAAABwAmAGwMAAAGAC0AbQwAAAMAPADqDAAACAA3AG4MAAAEAFMAbwwAAAEAEwANAAkJYxUGDgAbAgloDAAABQBKAGkMAAAEADEAawwAAAQAMgBqDAAABQAmAGwMAAAEAC0AbQwAAAMAPADqDAAABAA3AG4MAAAEAFMAbwwAAAEAEwAOAAYJsQpMWQAjAQZoDAAAAgAmAGkMAAACABcAawwAAAIAEABqDAAAAgAUAGwMAAACADEA6gwAAAQADwAAAA==.Danehar:BAAALgAECgEJAQAAAA==.',
Dc='Dcone:BAAALgADCgYJBgAAAA==.',
De='Deadkey:BAAALgADCgEJAQAAAA==.Deathborne:BAAALgAECgUJCQAAAA==.Deathshreik:BAAALgADCgMJAwAAAA==.Deathslam:BAABLgAECn8gAAIKAAgJqBkhIQAgAghoDAAABABUAGkMAAAFAFYAawwAAAQALABqDAAABAANAGwMAAAFAFsAbQwAAAMAJwDqDAAABABBAG4MAAADADAACgAICagZISEAIAIIaAwAAAQAVABpDAAABQBWAGsMAAAEACwAagwAAAQADQBsDAAABQBbAG0MAAADACcA6gwAAAQAQQBuDAAAAwAwAAAA.',
Dr='Droston:BAAALgADCgQJBAAAAA==.',
Du='Dutchess:BAABLgAECn8eAAIPAAgJShkuKQDyAQhoDAAABQBFAGkMAAAFAFIAawwAAAQASABqDAAABAA6AGwMAAAFAFQAbQwAAAIARADqDAAABAA7AG4MAAABABEADwAICUoZLikA8gEIaAwAAAUARQBpDAAABQBSAGsMAAAEAEgAagwAAAQAOgBsDAAABQBUAG0MAAACAEQA6gwAAAQAOwBuDAAAAQARAAAA.',
Dy='Dylan:BAACLgAFFH8QAAIIAAQJ9hvoHgB5AQRoDAAABAA1AGkMAAAFAFsAawwAAAMAOADqDAAABABVAAgABAn2G+geAHkBBGgMAAAEADUAaQwAAAUAWwBrDAAAAwA4AOoMAAAEAFUALgAECn8nAAIIAAkJ7CSVAgBjAwAIAAkJ7CSVAgBjAwAAAA==.Dylanj:BAAALgAECgQJBAABLgAFFAQJEAAIAPYbAQ==.',
Ec='Echevalier:BAAALgAECgQJBQAAAA==.',
Eg='Egonspengler:BAAALgADCgQJBAAAAA==.',
El='Elowen:BAAALgAFFAEJAQAAAQ==.',
En='Enhae:BAAALgAECgEJAQAAAA==.',
Er='Eresiine:BAAALgAECgcJCgAAAA==.Eríngo:BAAALgAECgcJCwAAAA==.',
Es='Esna:BAAALgADCgUJBwAAAA==.',
Fi='Filomena:BAAALgADCgUJBgAAAA==.Firnin:BAAALgAECgYJEAAAAA==.',
Fl='Floise:BAACLgAFFH8OAAMQAAQJ0hV5EwA8AQRoDAAABQAuAGkMAAAEADsAawwAAAMASgDqDAAAAgApABAABAlRFHkTADwBBGgMAAACAC4AaQwAAAMALABrDAAAAwBKAOoMAAACACkAEQACCVQTWQ0AkwACaAwAAAMAJwBpDAAAAQA7AC4ABAp/HgAEEQAJCfsZdwwAjAIAEQAJCUAZdwwAjAIAEAAHCREVvjMAvAAABgABCVwShlYAPgAAAAA=.Flounder:BAAALgAECgEJAwAAAA==.',
Fo='Foamtotem:BAAALgADCgEJAQAAAA==.Forumsoldier:BAABLgAECn8jAAIIAAgJlhfUPQDFAQhoDAAABQBHAGkMAAAFAD8AawwAAAUAPQBqDAAABQAyAGwMAAAFAEoAbQwAAAMAJgDqDAAABQBKAG4MAAACACcACAAICZYX1D0AxQEIaAwAAAUARwBpDAAABQA/AGsMAAAFAD0AagwAAAUAMgBsDAAABQBKAG0MAAADACYA6gwAAAUASgBuDAAAAgAnAAAA.',
Fr='Frozenscorch:BAAALgAECggJEQAAAA==.',
['Fä']='Fälkor:BAABLgAECn8nAAMSAAgJrQYWLQALAQhoDAAABgAdAGkMAAAFABgAawwAAAQAEwBqDAAABQAZAGwMAAAGABMAbQwAAAQACgDqDAAABgAIAG4MAAADAAcAEgAICa0GFi0ACwEIaAwAAAUAHQBpDAAABAAYAGsMAAAEABMAagwAAAQAFgBsDAAABQATAG0MAAAEAAoA6gwAAAYACABuDAAAAgAHABMABQk0BLoQAJQABWgMAAABAAkAaQwAAAEACgBqDAAAAQAZAGwMAAABAA8AbgwAAAEABwAAAA==.',
['Fö']='Föx:BAAALgAECgEJAQABLgAECgYJEQAUAAAAAA==.',
Gi='Gigamoo:BAAALgAECgQJBgAAAA==.',
Gl='Glorfindel:BAAALgAFFAEJAQABLgAFFAQJCQAMAGYWAA==.Glys:BAAALgAECgUJCgAAAA==.',
Go='Gogocow:BAAALgAECgEJAQAAAA==.Gooba:BAAALgAECgEJAQAAAA==.Goommar:BAAALgAECgYJDAAAAA==.Gorim:BAAALgAECgIJAgAAAA==.',
Gr='Grandgoose:BAAALgADCgIJAgAAAA==.Granuju:BAAALgADCgUJBgAAAA==.',
Gu='Gunnhildr:BAAALgADCgkJCQAAAA==.',
Ha='Hanasanai:BAAALgADCgMJBAAAAA==.Handil:BAABLgAECn8aAAIVAAYJRiHQFgDvAQZoDAAABQBZAGkMAAAFAFoAawwAAAUAXgBqDAAABQBcAGwMAAABADwA6gwAAAUAUwAVAAYJRiHQFgDvAQZoDAAABQBZAGkMAAAFAFoAawwAAAUAXgBqDAAABQBcAGwMAAABADwA6gwAAAUAUwAAAA==.',
He='Helpingyou:BAAALgAECggJEgAAAA==.',
Ho='Holybell:BAAALgAECgIJAgAAAA==.Hoptyj:BAAALgADCgIJAgAAAA==.',
['Hë']='Hënnessy:BAAALgADCgMJAwAAAA==.Hënnëssy:BAABLgAECn8YAAIVAAYJgRUwJQB4AQZoDAAABABYAGkMAAAEAB0AawwAAAQALgBqDAAABAA3AGwMAAADAC0A6gwAAAUAQAAVAAYJgRUwJQB4AQZoDAAABABYAGkMAAAEAB0AawwAAAQALgBqDAAABAA3AGwMAAADAC0A6gwAAAUAQAAAAA==.',
Im='Impaladin:BAAALgADCgYJCgAAAA==.',
Io='Iolanthe:BAAALgADCgQJBAAAAA==.',
Iz='Izeroeasily:BAAALgAECgMJAwAAAA==.Izerohealz:BAAALgADCgQJBAAAAA==.Izzi:BAAALgAECgYJEQAAAA==.Izzia:BAABLgAECn8YAAILAAcJzRpFFgAxAgdoDAAABQBSAGkMAAAEAFQAawwAAAUAPgBqDAAAAgBGAGwMAAACAEgAbQwAAAEAGwDqDAAABQBRAAsABwnNGkUWADECB2gMAAAFAFIAaQwAAAQAVABrDAAABQA+AGoMAAACAEYAbAwAAAIASABtDAAAAQAbAOoMAAAFAFEAAAA=.',
Ja='Jabbathabutt:BAAALgAECgYJBgAAAA==.Jasia:BAAALgADCgYJCAAAAA==.',
Jo='Joyboy:BAAALgAECgEJAQAAAA==.',
Ju='Justfn:BAAALgADCgUJBwAAAA==.',
Ka='Kamitos:BAABLgAECn8jAAMQAAcJIhEAIABJAQdoDAAABwAlAGkMAAAHADUAawwAAAMAOABqDAAABQAnAGwMAAAFABwA6gwAAAUAOQBuDAAAAwAhABAABwkiEQAgAEkBB2gMAAAFACUAaQwAAAYANQBrDAAAAgA4AGoMAAADACcAbAwAAAMAHADqDAAABQA5AG4MAAADACEABgAFCcgIZkQA2QAFaAwAAAIAIgBpDAAAAQAWAGsMAAABABsAagwAAAIAGwBsDAAAAgAEAAAA.Kayewyn:BAABLgAECn8cAAILAAgJ4A9gMAB7AQhoDAAABgBWAGkMAAAGAD0AawwAAAYAIQBqDAAAAwAUAGwMAAACACQAbQwAAAEADwDqDAAAAwApAG4MAAABAB0ACwAICeAPYDAAewEIaAwAAAYAVgBpDAAABgA9AGsMAAAGACEAagwAAAMAFABsDAAAAgAkAG0MAAABAA8A6gwAAAMAKQBuDAAAAQAdAAAA.',
Kb='Kbdh:BAAALgAECgYJCQABLgAFFAIJAwAUAAAAAA==.Kbdruid:BAAALgAFFAEJAQABLgAFFAIJAwAUAAAAAA==.Kbhunter:BAAALgAECgUJCAABLgAFFAIJAwAUAAAAAA==.Kbmage:BAAALgADCgQJBAABLgAFFAIJAwAUAAAAAA==.Kbmonk:BAAALgAFFAIJAwAAAA==.Kbpaladin:BAAALgAECgYJBgABLgAFFAIJAwAUAAAAAA==.',
Ke='Keiji:BAAALgAECgYJDgAAAA==.',
Kl='Klipnor:BAAALgAECgQJCAAAAA==.',
Kr='Krocketeer:BAAALgAECgYJCQAAAA==.',
Ky='Kyndel:BAAALgAECgYJCgABLgAFFAQJDQALAJoZAA==.Kynn:BAACLgAFFH8NAAILAAQJmhmQEwBQAQRoDAAABQBSAGkMAAAEAFEAawwAAAMAOwDqDAAAAQAmAAsABAmaGZATAFABBGgMAAAFAFIAaQwAAAQAUQBrDAAAAwA7AOoMAAABACYALgAECn8zAAILAAkJlCLzAQCBAwALAAkJlCLzAQCBAwAAAA==.',
['Kè']='Kèlemvore:BAABLgAECn8mAAIPAAgJNBEUTAB4AQhoDAAABgA4AGkMAAAGADwAawwAAAYAPgBqDAAABQA2AGwMAAAGACEAbQwAAAEADwDqDAAABgA6AG4MAAACABUADwAICTQRFEwAeAEIaAwAAAYAOABpDAAABgA8AGsMAAAGAD4AagwAAAUANgBsDAAABgAhAG0MAAABAA8A6gwAAAYAOgBuDAAAAgAVAAAA.',
Le='Leafittome:BAAALgADCgEJAQAAAA==.',
Ly='Lykos:BAAALgAECgYJDgAAAA==.',
Ma='Mammal:BAAALgAECgQJBAAAAA==.',
Me='Medxchaos:BAAALgAECgQJBwABLgAFFAQJDgAQANIVAA==.Meowy:BAAALgAECgEJAQAAAA==.Mepha:BAABLgAECn8rAAMWAAkJliDmAgCnAgloDAAABwBYAGkMAAAHAFsAawwAAAcAWwBqDAAABQBMAGwMAAAEAEkAbQwAAAMAPQDqDAAABgBhAG4MAAADAEkAbwwAAAEAWgAWAAkJXR3mAgCnAgloDAAAAwBIAGkMAAADAFIAawwAAAMAUABqDAAAAwAXAGwMAAACAEkAbQwAAAIAPQDqDAAAAwBEAG4MAAADAEkAbwwAAAEAWgAXAAcJ+B/yGACDAgdoDAAABABYAGkMAAAEAFsAawwAAAQAWwBqDAAAAgBMAGwMAAACAEUAbQwAAAEAMwDqDAAAAwBhAAAA.',
Mi='Mightymost:BAAALgADCgEJAQAAAA==.',
Mu='Muddless:BAABLgAECn8eAAMWAAgJkh/dAwB7AghoDAAABQBJAGkMAAAFAFcAawwAAAMAUgBqDAAAAwA7AGwMAAAEAFwAbQwAAAEASgDqDAAABgBbAG4MAAADAEAAFgAICZIf3QMAewIIaAwAAAUASQBpDAAABQBXAGsMAAADAFIAagwAAAMAOwBsDAAABABcAG0MAAABAEoA6gwAAAQAWwBuDAAAAwBAABcAAQnqC82lADkAAeoMAAACAB4AAAA=.Mudds:BAABLgAECn8cAAIJAAgJoSB7EAB5AghoDAAABgBVAGkMAAAFAFoAawwAAAUAWABqDAAAAgBMAGwMAAACAFQAbQwAAAIAUgDqDAAABQBXAG4MAAABAEEACQAICaEgexAAeQIIaAwAAAYAVQBpDAAABQBaAGsMAAAFAFgAagwAAAIATABsDAAAAgBUAG0MAAACAFIA6gwAAAUAVwBuDAAAAQBBAAAA.',
Na='Naelia:BAAALgAECgYJCgABLgAFFAQJDAAKABgLAA==.Nakira:BAAALgAECgMJAwAAAA==.Nami:BAAALgAECgUJBQAAAA==.',
Ni='Nicodemus:BAAALgADCgIJAgAAAA==.Nightrush:BAABLgAECn8oAAMCAAgJISWhDQCJAghoDAAABwBjAGkMAAAHAGIAawwAAAYAYQBqDAAABQBdAGwMAAADAFEAbQwAAAMAXQDqDAAABgBiAG4MAAADAGAAAgAGCQMmoQ0AiQIGaAwAAAEAYwBpDAAAAQBiAGsMAAACAGEAbQwAAAMAXQDqDAAAAQBiAG4MAAADAGAAAQAGCbQh/QYAtwEGaAwAAAYAWwBpDAAABgBXAGsMAAAEAFQAagwAAAUAXQBsDAAAAwBRAOoMAAAFAFYAAAA=.',
No='Noodles:BAABLgAECn8XAAIFAAYJehbVYgDyAAZoDAAABQBGAGkMAAAFADkAawwAAAUAMwBqDAAABABMAGwMAAACACwA6gwAAAIAPwAFAAYJehbVYgDyAAZoDAAABQBGAGkMAAAFADkAawwAAAUAMwBqDAAABABMAGwMAAACACwA6gwAAAIAPwAAAA==.Norbit:BAAALgAECgEJAQAAAA==.',
Oe='Oesteroth:BAABLgAECn8UAAILAAYJbgV/XQDDAAZoDAAABAAYAGkMAAAEAAkAawwAAAQACQBqDAAAAwAUAGwMAAABAAgA6gwAAAQACgALAAYJbgV/XQDDAAZoDAAABAAYAGkMAAAEAAkAawwAAAQACQBqDAAAAwAUAGwMAAABAAgA6gwAAAQACgAAAA==.',
Ok='Okomo:BAAALgAECgEJAQABLgAECgMJAwAUAAAAAA==.',
Pa='Palaben:BAABLgAECn8bAAMVAAgJdRF4KgBTAQhoDAAABAAyAGkMAAAEAFsAawwAAAQANQBqDAAABAAiAGwMAAADACYAbQwAAAIAFgDqDAAAAwA9AG4MAAADAAMAFQAHCawSeCoAUwEHaAwAAAQAMgBpDAAABABbAGsMAAAEADUAagwAAAMAIgBsDAAAAgAmAOoMAAADAD0AbgwAAAEAAwAPAAQJWgxoxwCMAARqDAAAAQAGAGwMAAABABkAbQwAAAIAGgBuDAAAAgAqAAAA.Pantsu:BAABLgAECn85AAMKAAgJfiUtCADwAghoDAAACQBiAGkMAAAJAGMAawwAAAgAYgBqDAAABwBdAGwMAAAGAF8AbQwAAAUAWQDqDAAACABeAG4MAAAFAGAACgAICX4lLQgA8AIIaAwAAAgAYgBpDAAACABjAGsMAAAHAGIAagwAAAYAXQBsDAAABQBfAG0MAAAEAFkA6gwAAAcAXgBuDAAABABgABgACAn9H7cBAIMCCGgMAAABAFQAaQwAAAEAXABrDAAAAQBbAGoMAAABAD8AbAwAAAEAWgBtDAAAAQBFAOoMAAABAEgAbgwAAAEARwAAAA==.Pateaviejas:BAAALgAECgMJAwAAAA==.Pawnchy:BAAALgAECgUJCQAAAA==.',
Pe='Peepaw:BAAALgAECgYJEQAAAA==.',
Pi='Pitchwhite:BAABLgAECn8XAAIRAAYJHBGzKwAJAQZoDAAABQA7AGkMAAAEACMAawwAAAQAOwBqDAAABAAzAGwMAAABABIA6gwAAAUAJgARAAYJHBGzKwAJAQZoDAAABQA7AGkMAAAEACMAawwAAAQAOwBqDAAABAAzAGwMAAABABIA6gwAAAUAJgAAAA==.Pixel:BAAALgADCgkJDQAAAA==.',
Pr='Proselyte:BAACLgAFFH8HAAIJAAMJ6xGOEgDkAANoDAAAAwAmAGkMAAADADMA6gwAAAEALwAJAAMJ6xGOEgDkAANoDAAAAwAmAGkMAAADADMA6gwAAAEALwAuAAQKfyIAAgkACQmxHeAFAJECAAkACQmxHeAFAJECAAAA.',
Pu='Punchbear:BAAALgADCgQJBAAAAA==.Punchize:BAABLgAECn8dAAMZAAgJwByYCgAwAghoDAAABQBiAGkMAAAGAFQAawwAAAYARwBqDAAAAwBgAGwMAAACADwAbQwAAAEAVQDqDAAABQBWAG4MAAABAB0AGQAICcAcmAoAMAIIaAwAAAUAYgBpDAAABQBUAGsMAAAFAEcAagwAAAMAYABsDAAAAgA8AG0MAAABAFUA6gwAAAUAVgBuDAAAAQAdABoAAgn0CndZAEoAAmkMAAABACAAawwAAAEAFwAAAA==.Punchlocks:BAAALgAECgEJAQAAAA==.',
Qu='Quirkchungus:BAAALgAECgQJBAAAAA==.',
Ra='Rakrak:BAAALgADCgEJAQAAAA==.Rani:BAAALgADCgUJBQAAAA==.Rathon:BAAALgAECgkJDAAAAA==.',
Re='Remote:BAAALgAECgMJAwAAAA==.',
Ri='Rianis:BAAALgADCgcJEAAAAA==.Rilea:BAAALgAECgYJEAAAAA==.',
['Rä']='Räiyu:BAAALgADCgMJAwAAAA==.',
Sa='Sadgasm:BAABLgAECn8eAAIbAAkJmx4aAgCxAgloDAAABQBfAGkMAAAFAGEAawwAAAUATABqDAAAAwBOAGwMAAADAEIAbQwAAAEAJgDqDAAABgBVAG4MAAABAFUAbwwAAAEAUgAbAAkJmx4aAgCxAgloDAAABQBfAGkMAAAFAGEAawwAAAUATABqDAAAAwBOAGwMAAADAEIAbQwAAAEAJgDqDAAABgBVAG4MAAABAFUAbwwAAAEAUgAAAA==.Safeword:BAAALgAECgkJCwAAAA==.Sauron:BAAALgAECgMJBQAAAA==.',
Se='Sebrine:BAAALgAECgUJCwAAAA==.Seishan:BAACLgAFFH8HAAMEAAUJJRFtGADsAAVoDAAAAgA/AGkMAAABAEIAawwAAAEAEABqDAAAAQArAOoMAAACABwABAAFCSURbRgA7AAFaAwAAAIAPwBpDAAAAQBCAGsMAAABABAAagwAAAEAKwDqDAAAAQAcABwAAQmvCZcLAFMAAeoMAAABABgALgAECn8fAAQcAAcJkxsqBwD0AQAcAAYJ1R4qBwD0AQAEAAUJxhfPKQDGAAAdAAEJ+xfgEwBJAAAAAA==.Seneca:BAAALgAECgEJBAAAAA==.',
Sh='Shadowtalon:BAAALgADCgEJAQAAAA==.Shamandrea:BAAALgAECgYJBgABLgAECggJHwARADgYAA==.Shzam:BAAALgADCgYJDgAAAA==.',
Sl='Slam:BAAALgADCgMJBQAAAA==.Sleipner:BAABLgAECn8fAAIeAAkJAQ66DwBWAQloDAAABABTAGkMAAAEADQAawwAAAQAJgBqDAAABAAdAGwMAAAEABsAbQwAAAMAEgDqDAAABQAhAG4MAAACABMAbwwAAAEADAAeAAkJAQ66DwBWAQloDAAABABTAGkMAAAEADQAawwAAAQAJgBqDAAABAAdAGwMAAAEABsAbQwAAAMAEgDqDAAABQAhAG4MAAACABMAbwwAAAEADAAAAA==.',
Sm='Smiley:BAAALgADCgYJBgAAAA==.',
Sn='Sneeze:BAAALgADCgIJAgAAAA==.Snugglehex:BAAALgADCgEJAQAAAA==.',
So='Socktrout:BAABLgAECn8qAAQfAAkJnReAIQD+AQloDAAABgAzAGkMAAAFAEkAawwAAAQAQwBqDAAAAwAbAGwMAAAGACkAbQwAAAUAPwDqDAAABgBBAG4MAAAEAEsAbwwAAAMAKwAfAAgJexaAIQD+AQhoDAAABgAzAGkMAAAFAEkAawwAAAQAQwBsDAAAAgApAG0MAAACAD8A6gwAAAYAQQBuDAAABABLAG8MAAACABQAIAADCekKEkMAqQADagwAAAIAGwBsDAAABAAgAG0MAAADABYAIQACCS0RfRkATgACagwAAAEABgBvDAAAAQArAAAA.Softgrizzly:BAAALgADCgMJAwAAAA==.Solidgold:BAACLgAFFH8UAAMXAAcJLhm3AQDUAQdoDAAABABbAGkMAAADAFMAawwAAAMALgBqDAAAAwBaAGwMAAACADAAbQwAAAEAFQDqDAAABABfABcABwkuGbcBANQBB2gMAAAEAFsAaQwAAAMAUwBrDAAAAwAuAGoMAAADAFoAbAwAAAEAMABtDAAAAQAVAOoMAAAEAF8AFgABCaAGugsAUwABbAwAAAEAEAAuAAQKfycAAxcACAmIJMoTALACABcACAlhI8oTALACABYABQmoIPwcAAgBAAAA.Solvane:BAAALgAECgMJAwABLgAFFAUJBwAEACURAA==.',
Sp='Spongeybob:BAAALgADCgEJAgAAAA==.',
Ss='Sscrubbucket:BAAALgAECgYJBgAAAA==.',
Su='Sunrise:BAAALgADCgkJEAAAAA==.',
Sy='Syllassa:BAAALgAECgkJAQAAAA==.Sylv:BAAALgADCgQJBgAAAA==.',
Ta='Taelia:BAACLgAFFH8MAAIKAAQJGAtgQgAnAQRoDAAABAA+AGkMAAADABUAawwAAAIACQDqDAAAAwATAAoABAkYC2BCACcBBGgMAAAEAD4AaQwAAAMAFQBrDAAAAgAJAOoMAAADABMALgAECn85AAIKAAkJ5iDGBwD2AgAKAAkJ5iDGBwD2AgAAAA==.Tahine:BAAALgAECgYJDQAAAA==.Tans:BAAALgADCgkJCwAAAA==.',
Ti='Tiktoks:BAAALgAECgEJAQAAAA==.Timetwoflame:BAABLgAECn8bAAIiAAgJ5RHPCQDYAQhoDAAABgA/AGkMAAAGAEUAawwAAAUAQgBqDAAAAQATAGwMAAABABwAbQwAAAEAIgDqDAAABAAyAG4MAAADACEAIgAICeURzwkA2AEIaAwAAAYAPwBpDAAABgBFAGsMAAAFAEIAagwAAAEAEwBsDAAAAQAcAG0MAAABACIA6gwAAAQAMgBuDAAAAwAhAAAA.',
Tn='Tnarg:BAAALgADCgIJAgAAAA==.',
To='Tokki:BAAALgAECgYJBwAAAA==.',
Tr='Trekvis:BAAALgADCgcJDgAAAA==.',
Tu='Tugboat:BAAALgADCgIJAgAAAA==.',
['Tû']='Tûâny:BAAALgAECgUJBQAAAA==.',
Up='Upphoria:BAABLgAECn8XAAMRAAYJ1Ar+LgDzAAZoDAAABQArAGkMAAAGADAAawwAAAQABABqDAAAAwAOAGwMAAACAAwA6gwAAAMAKQARAAYJ1Ar+LgDzAAZoDAAABAArAGkMAAAFADAAawwAAAQABABqDAAAAwAOAGwMAAACAAwA6gwAAAMAKQAGAAIJPgN+ZAAmAAJoDAAAAQAEAGkMAAABAAwAAAA=.',
Ur='Urkel:BAAALgAECgEJAQAAAA==.',
Ut='Uthomage:BAAALgAECgMJAwAAAA==.',
Va='Vashi:BAAALgADCgcJBwAAAA==.',
Vi='Viccan:BAABLgAECn8iAAIgAAkJ/AYYDAAiAQloDAAABgAeAGkMAAAFABMAawwAAAUAEABqDAAAAwAIAGwMAAAEAAkAbQwAAAIABADqDAAABgAbAG4MAAACAA8AbwwAAAEAEgAgAAkJ/AYYDAAiAQloDAAABgAeAGkMAAAFABMAawwAAAUAEABqDAAAAwAIAGwMAAAEAAkAbQwAAAIABADqDAAABgAbAG4MAAACAA8AbwwAAAEAEgAAAA==.',
Wa='Walkingtanko:BAAALgADCgIJAgAAAA==.Wavés:BAAALgADCgIJAgAAAA==.',
We='Wef:BAAALgADCgcJBwAAAA==.',
Wi='Willowleaf:BAAALgAECgEJAQABLgAECggJHwARADgYAA==.',
Wo='Wolffie:BAAALgAECggJEQAAAA==.',
Wu='Wushuu:BAAALgAECgUJCgABLgAFFAQJDAAIADQLAA==.',
Xa='Xampu:BAAALgADCgYJBgAAAA==.',
Xe='Xernaeus:BAAALgADCgQJBAAAAA==.',
Ya='Yahwëh:BAAALgAECgMJBAAAAA==.',
Yo='Yodason:BAAALgADCgQJBQAAAA==.',
Yu='Yuukï:BAABLgAECn8iAAMJAAkJIB1NCQBHAgloDAAABgBbAGkMAAAFAFUAawwAAAYAUQBqDAAAAwA5AGwMAAAEADgAbQwAAAIAJwDqDAAABQBbAG4MAAACAFEAbwwAAAEARAAJAAgJdB1NCQBHAghoDAAABgBbAGkMAAAFAFUAawwAAAUAUQBqDAAAAwA5AGwMAAADADgAbQwAAAEAJwDqDAAABQBbAG4MAAACAFEAGgAECQgHIEgAhwAEawwAAAEABwBsDAAAAQANAG0MAAABABAAbwwAAAEAIgAAAA==.',
Za='Zaelyse:BAAALgADCgMJAwAAAA==.Zaton:BAABLgAECn8XAAIIAAgJNhBiSwCbAQhoDAAABAAsAGkMAAAEAEEAawwAAAQAMQBqDAAABABMAGwMAAACAA8AbQwAAAEANQDqDAAAAwAxAG4MAAABAAoACAAICTYQYksAmwEIaAwAAAQALABpDAAABABBAGsMAAAEADEAagwAAAQATABsDAAAAgAPAG0MAAABADUA6gwAAAMAMQBuDAAAAQAKAAAA.',
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
