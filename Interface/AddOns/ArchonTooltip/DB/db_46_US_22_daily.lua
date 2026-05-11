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
local provider = {region='US',realm='Auchindoun',name='US',type='daily',zone=46,date='2026-05-10',data={Ad='Adnerb:BAABLgAECn8VAAQBAAgJNxJaEADxAAhoDAAABwBNAGkMAAADADAAawwAAAMAMQBqDAAAAgAzAGwMAAABACQAbQwAAAEAGADqDAAAAwBIAG4MAAABABAAAQAGCQITWhAA8QAGaAwAAAcATQBpDAAAAgAqAGsMAAABACUAbAwAAAEAJABtDAAAAQAYAOoMAAADAEgAAgAECeoOI3kAswAEaQwAAAEAMABrDAAAAQAxAGoMAAABADMAbgwAAAEAEAADAAIJkQcRQAA8AAJrDAAAAQATAGoMAAABABMAAS4ABRQFCQYABACnDwA=.',
Ah='Ahriman:BAABLgAECn8XAAIFAAYJLw7uYADmAAZoDAAABgA1AGkMAAAFACYAawwAAAQAJQBqDAAAAwAvAGwMAAACACIA6gwAAAMAEQAFAAYJLw7uYADmAAZoDAAABgA1AGkMAAAFACYAawwAAAQAJQBqDAAAAwAvAGwMAAACACIA6gwAAAMAEQAAAA==.',
Al='Alystra:BAABLgAECn8YAAIGAAcJGweFKQALAQdoDAAABQAQAGkMAAAEABYAawwAAAQAEgBqDAAAAwAeAGwMAAADABgAbQwAAAEADADqDAAABAANAAYABwkbB4UpAAsBB2gMAAAFABAAaQwAAAQAFgBrDAAABAASAGoMAAADAB4AbAwAAAMAGABtDAAAAQAMAOoMAAAEAA0AAAA=.',
An='Anjedin:BAAALgAECgYJCwAAAA==.',
Ao='Aoki:BAABLgAECn8cAAICAAgJdR6THAD2AQhoDAAABQBbAGkMAAAFAEoAawwAAAQARwBqDAAABQBgAGwMAAADAFMAbQwAAAEANgDqDAAAAgBVAG4MAAADAFUAAgAICXUekxwA9gEIaAwAAAUAWwBpDAAABQBKAGsMAAAEAEcAagwAAAUAYABsDAAAAwBTAG0MAAABADYA6gwAAAIAVQBuDAAAAwBVAAAA.',
Ar='Archdemon:BAABLgAECn8iAAIHAAkJOhiXBgAtAgloDAAABgA7AGkMAAAFAEkAawwAAAUASgBqDAAAAwAxAGwMAAAEACwAbQwAAAIAMQDqDAAABgBCAG4MAAACAEMAbwwAAAEAPQAHAAkJOhiXBgAtAgloDAAABgA7AGkMAAAFAEkAawwAAAUASgBqDAAAAwAxAGwMAAAEACwAbQwAAAIAMQDqDAAABgBCAG4MAAACAEMAbwwAAAEAPQAAAA==.Argonos:BAAALgAECgcJDQAAAA==.Arielias:BAAALgAECgYJCQABLgAFFAUJBgAEAKcPAA==.Arkanoas:BAACLgAFFH8MAAIIAAQJNAu0OQA4AQRoDAAABAA3AGkMAAADAB8AawwAAAMAFgDqDAAAAgAEAAgABAk0C7Q5ADgBBGgMAAAEADcAaQwAAAMAHwBrDAAAAwAWAOoMAAACAAQALgAECn8pAAIIAAkJthYKOACUAgAIAAkJthYKOACUAgAAAA==.',
As='Ashatal:BAAALgADCgEJAQAAAA==.Ashphantom:BAAALgAECgIJAgAAAA==.',
Ba='Bagelbite:BAAALgADCgUJBQAAAA==.Banshee:BAAALgAECgYJDAABLgAFFAUJBgAEAKcPAA==.Battahelin:BAAALgAECgQJBgAAAA==.Bazoo:BAAALgAECgEJAQAAAA==.',
Be='Bearmanowl:BAAALgAECgYJBwAAAA==.Bellator:BAAALgAECgMJBAAAAA==.',
Bi='Bigchungus:BAABLgAECn8dAAIJAAYJ/AjMMADMAAZoDAAABgAgAGkMAAAGABEAawwAAAYAFgBqDAAABAASAGwMAAADABEA6gwAAAQAGQAJAAYJ/AjMMADMAAZoDAAABgAgAGkMAAAGABEAawwAAAYAFgBqDAAABAASAGwMAAADABEA6gwAAAQAGQAAAA==.',
Bl='Blart:BAAALgAECgUJBwAAAA==.Bloody:BAAALgADCgEJAQAAAA==.',
Br='Breathplay:BAABLgAECn8XAAIKAAgJhhuUPQBBAghoDAAABABQAGkMAAAEAEoAawwAAAQAOwBqDAAAAgA6AGwMAAACAEYAbQwAAAIAQQDqDAAAAwBLAG4MAAACAEQACgAICYYblD0AQQIIaAwAAAQAUABpDAAABABKAGsMAAAEADsAagwAAAIAOgBsDAAAAgBGAG0MAAACAEEA6gwAAAMASwBuDAAAAgBEAAAA.',
['Bà']='Bàyne:BAABLgAECn8yAAILAAkJUBN8HADsAQloDAAABwAuAGkMAAAHAEcAawwAAAcAPgBqDAAABgAxAGwMAAAGAEMAbQwAAAQAIwDqDAAABwBEAG4MAAAEABwAbwwAAAIADgALAAkJUBN8HADsAQloDAAABwAuAGkMAAAHAEcAawwAAAcAPgBqDAAABgAxAGwMAAAGAEMAbQwAAAQAIwDqDAAABwBEAG4MAAAEABwAbwwAAAIADgAAAA==.',
Ca='Caroquintero:BAABLgAECn8eAAIIAAYJcgN6rADGAAZoDAAABgADAGkMAAAGABAAawwAAAYACABqDAAABAALAGwMAAAEAAkA6gwAAAQABgAIAAYJcgN6rADGAAZoDAAABgADAGkMAAAGABAAawwAAAYACABqDAAABAALAGwMAAAEAAkA6gwAAAQABgAAAA==.',
Ch='Charliemen:BAAALgAECgQJBAAAAA==.Chilli:BAAALgADCgEJAQAAAA==.Chubtart:BAABLgAECn8yAAIMAAkJ0CM8CAASAwloDAAABQBgAGkMAAAFAFUAawwAAAYAXQBqDAAABQBXAGwMAAAHAF8AbQwAAAYAXQDqDAAACABfAG4MAAAFAFcAbwwAAAMAVgAMAAkJ0CM8CAASAwloDAAABQBgAGkMAAAFAFUAawwAAAYAXQBqDAAABQBXAGwMAAAHAF8AbQwAAAYAXQDqDAAACABfAG4MAAAFAFcAbwwAAAMAVgAAAA==.Churrasco:BAAALgAECgQJCAAAAA==.',
Cl='Clayton:BAAALgADCgcJBAAAAA==.',
Cu='Cunumi:BAAALgAECgMJBAAAAA==.',
Da='Daddy:BAABLgAECn8tAAMNAAgJLBZrEgDTAQhoDAAABwBKAGkMAAAGADEAawwAAAYAMgBqDAAABwAmAGwMAAAGAC0AbQwAAAIAJwDqDAAACAA3AG4MAAADAFMADQAICSwWaxIA0wEIaAwAAAUASgBpDAAABAAxAGsMAAAEADIAagwAAAUAJgBsDAAABAAtAG0MAAACACcA6gwAAAQANwBuDAAAAwBTAA4ABgmxCk1ZACMBBmgMAAACACYAaQwAAAIAFwBrDAAAAgAQAGoMAAACABQAbAwAAAIAMQDqDAAABAAPAAAA.Danehar:BAAALgAECgEJAQAAAA==.',
Dc='Dcone:BAAALgADCgYJBgAAAA==.',
De='Deadkey:BAAALgADCgEJAQAAAA==.Deathborne:BAAALgAECgUJCQAAAA==.Deathshreik:BAAALgADCgMJAwAAAA==.Deathslam:BAABLgAECn8gAAIKAAgJqBlHHQAlAghoDAAABABUAGkMAAAFAFYAawwAAAQALABqDAAABAANAGwMAAAFAFsAbQwAAAMAJwDqDAAABABBAG4MAAADADAACgAICagZRx0AJQIIaAwAAAQAVABpDAAABQBWAGsMAAAEACwAagwAAAQADQBsDAAABQBbAG0MAAADACcA6gwAAAQAQQBuDAAAAwAwAAAA.',
Dr='Droston:BAAALgADCgQJBAAAAA==.',
Du='Dutchess:BAABLgAECn8cAAIPAAgJPBh+KADoAQhoDAAABQBFAGkMAAAFAFIAawwAAAQASABqDAAABAA6AGwMAAAEAEoAbQwAAAEAOwDqDAAABAA7AG4MAAABABEADwAICTwYfigA6AEIaAwAAAUARQBpDAAABQBSAGsMAAAEAEgAagwAAAQAOgBsDAAABABKAG0MAAABADsA6gwAAAQAOwBuDAAAAQARAAAA.',
Dy='Dylan:BAACLgAFFH8QAAIIAAQJBByhGgB9AQRoDAAABAA1AGkMAAAFAFsAawwAAAMAOADqDAAABABWAAgABAkEHKEaAH0BBGgMAAAEADUAaQwAAAUAWwBrDAAAAwA4AOoMAAAEAFYALgAECn8iAAIIAAkJoiSxAwBGAwAIAAkJoiSxAwBGAwAAAA==.Dylanj:BAAALgAECgQJBAAAAQ==.',
Ec='Echevalier:BAAALgAECgQJBQAAAA==.',
Eg='Egonspengler:BAAALgADCgQJBAAAAA==.',
El='Elowen:BAAALgAFFAEJAQAAAQ==.',
En='Enhae:BAAALgAECgEJAQAAAA==.',
Er='Eresiine:BAAALgAECgcJCgAAAA==.Eríngo:BAAALgAECgcJCwAAAA==.',
Es='Esna:BAAALgADCgUJBgAAAA==.',
Fi='Filomena:BAAALgADCgUJBgAAAA==.Firnin:BAAALgAECgYJEAAAAA==.',
Fl='Floise:BAACLgAFFH8OAAMQAAQJ0hXrEQBCAQRoDAAABQAuAGkMAAAEADsAawwAAAMASgDqDAAAAgApABAABAlRFOsRAEIBBGgMAAACAC4AaQwAAAMALABrDAAAAwBKAOoMAAACACkAEQACCVQTWA0AkwACaAwAAAMAJwBpDAAAAQA7AC4ABAp/HQADEQAJCfsZeAwAjAIAEQAJCUAZeAwAjAIAEAAHCREVZzAAvAAAAAA=.Flounder:BAAALgAECgEJAwAAAA==.',
Fo='Foamtotem:BAAALgADCgEJAQAAAA==.Forumsoldier:BAABLgAECn8jAAIIAAgJlhdoOQDFAQhoDAAABQBHAGkMAAAFAD8AawwAAAUAPQBqDAAABQAyAGwMAAAFAEoAbQwAAAMAJgDqDAAABQBKAG4MAAACACcACAAICZYXaDkAxQEIaAwAAAUARwBpDAAABQA/AGsMAAAFAD0AagwAAAUAMgBsDAAABQBKAG0MAAADACYA6gwAAAUASgBuDAAAAgAnAAAA.',
Fr='Frozenscorch:BAAALgAECggJDwAAAA==.',
['Fä']='Fälkor:BAABLgAECn8jAAMSAAgJigYgKwAKAQhoDAAABgAdAGkMAAAFABgAawwAAAQAEwBqDAAABQAZAGwMAAAFABMAbQwAAAMACQDqDAAABQAHAG4MAAACAAcAEgAICV8GICsACgEIaAwAAAUAHQBpDAAABAAYAGsMAAAEABMAagwAAAQAFgBsDAAABAATAG0MAAADAAkA6gwAAAUABwBuDAAAAQAEABMABQk0BN8PAJQABWgMAAABAAkAaQwAAAEACgBqDAAAAQAZAGwMAAABAA8AbgwAAAEABwAAAA==.',
['Fö']='Föx:BAAALgADCgEJAQABLgAECgQJCQAUAAAAAA==.',
Gi='Gigamoo:BAAALgAECgQJBgAAAA==.',
Gl='Glys:BAAALgAECgUJCgAAAA==.',
Go='Gogocow:BAAALgAECgEJAQAAAA==.Gooba:BAAALgAECgEJAQAAAA==.Goommar:BAAALgAECgUJCwAAAA==.Gorim:BAAALgAECgIJAgAAAA==.',
Gr='Grandgoose:BAAALgADCgIJAgAAAA==.Granuju:BAAALgADCgUJBgAAAA==.',
Gu='Gunnhildr:BAAALgADCgkJCQAAAA==.',
Ha='Hanasanai:BAAALgADCgMJBAAAAA==.Handil:BAABLgAECn8aAAIVAAYJRiHQFAD1AQZoDAAABQBZAGkMAAAFAFoAawwAAAUAXgBqDAAABQBcAGwMAAABADwA6gwAAAUAUwAVAAYJRiHQFAD1AQZoDAAABQBZAGkMAAAFAFoAawwAAAUAXgBqDAAABQBcAGwMAAABADwA6gwAAAUAUwAAAA==.',
He='Helpingyou:BAAALgAECggJDgAAAA==.',
Ho='Holybell:BAAALgAECgIJAgAAAA==.Hoptyj:BAAALgADCgIJAgAAAA==.',
['Hë']='Hënnessy:BAAALgADCgMJAwAAAA==.Hënnëssy:BAABLgAECn8VAAIVAAYJNhROJAByAQZoDAAABABYAGkMAAAEAB0AawwAAAQALgBqDAAAAwA3AGwMAAACABkA6gwAAAQAQAAVAAYJNhROJAByAQZoDAAABABYAGkMAAAEAB0AawwAAAQALgBqDAAAAwA3AGwMAAACABkA6gwAAAQAQAAAAA==.',
Im='Impaladin:BAAALgADCgYJCgAAAA==.',
Io='Iolanthe:BAAALgADCgQJBAAAAA==.',
Iz='Izeroeasily:BAAALgAECgMJAwAAAA==.Izerohealz:BAAALgADCgQJBAAAAA==.Izzi:BAAALgAECgYJEQAAAA==.Izzia:BAABLgAECn8WAAILAAcJzRplFAAxAgdoDAAABQBSAGkMAAAEAFQAawwAAAUAPgBqDAAAAgBGAGwMAAABAEgAbQwAAAEAGwDqDAAABABRAAsABwnNGmUUADECB2gMAAAFAFIAaQwAAAQAVABrDAAABQA+AGoMAAACAEYAbAwAAAEASABtDAAAAQAbAOoMAAAEAFEAAAA=.',
Ja='Jabbathabutt:BAAALgAECgYJBgAAAA==.Jasia:BAAALgADCgYJCAAAAA==.',
Jo='Joyboy:BAAALgAECgEJAQAAAA==.',
Ju='Justfn:BAAALgADCgUJBwAAAA==.',
Ka='Kamitos:BAABLgAECn8jAAMQAAcJIhGwHQBNAQdoDAAABwAlAGkMAAAHADUAawwAAAMAOABqDAAABQAnAGwMAAAFABwA6gwAAAUAOQBuDAAAAwAhABAABwkiEbAdAE0BB2gMAAAFACUAaQwAAAYANQBrDAAAAgA4AGoMAAADACcAbAwAAAMAHADqDAAABQA5AG4MAAADACEABgAFCcgIZEQA2QAFaAwAAAIAIgBpDAAAAQAWAGsMAAABABsAagwAAAIAGwBsDAAAAgAEAAAA.Kayewyn:BAABLgAECn8YAAILAAgJ4A9xLQB7AQhoDAAABQBWAGkMAAAFAD0AawwAAAUAIQBqDAAAAgAUAGwMAAACACQAbQwAAAEADwDqDAAAAwApAG4MAAABAB0ACwAICeAPcS0AewEIaAwAAAUAVgBpDAAABQA9AGsMAAAFACEAagwAAAIAFABsDAAAAgAkAG0MAAABAA8A6gwAAAMAKQBuDAAAAQAdAAAA.',
Kb='Kbdh:BAAALgAECgYJBwABLgAFFAIJAwAUAAAAAA==.Kbdruid:BAAALgAFFAEJAQABLgAFFAIJAwAUAAAAAA==.Kbhunter:BAAALgAECgUJCAABLgAFFAIJAwAUAAAAAA==.Kbmage:BAAALgADCgQJBAABLgAFFAIJAwAUAAAAAA==.Kbmonk:BAAALgAFFAIJAwAAAA==.Kbpaladin:BAAALgAECgYJBgABLgAFFAIJAwAUAAAAAA==.',
Ke='Keiji:BAAALgAECgUJBgAAAA==.',
Kl='Klipnor:BAAALgAECgQJCAAAAA==.',
Kr='Krocketeer:BAAALgAECgYJCQAAAA==.',
Ky='Kyndel:BAAALgAECgYJCgABLgAFFAQJDQALAJoZAA==.Kynn:BAACLgAFFH8NAAILAAQJmhnAEQBPAQRoDAAABQBSAGkMAAAEAFEAawwAAAMAOwDqDAAAAQAmAAsABAmaGcARAE8BBGgMAAAFAFIAaQwAAAQAUQBrDAAAAwA7AOoMAAABACYALgAECn8xAAILAAkJlCL0AQCBAwALAAkJlCL0AQCBAwAAAA==.',
['Kè']='Kèlemvore:BAABLgAECn8iAAIPAAcJeBLLTwBhAQdoDAAABgA4AGkMAAAGADwAawwAAAYAPgBqDAAABQA2AGwMAAAFAB0A6gwAAAUAOgBuDAAAAQAQAA8ABwl4EstPAGEBB2gMAAAGADgAaQwAAAYAPABrDAAABgA+AGoMAAAFADYAbAwAAAUAHQDqDAAABQA6AG4MAAABABAAAAA=.',
Le='Leafittome:BAAALgADCgEJAQAAAA==.',
Ly='Lykos:BAAALgAECgYJCAAAAA==.',
Ma='Mammal:BAAALgAECgQJBAABLgAECggJFwANACIZAA==.',
Me='Medxchaos:BAAALgAECgQJBwABLgAFFAQJDgAQANIVAA==.Meowy:BAAALgAECgEJAQAAAA==.Mepha:BAABLgAECn8rAAMWAAkJliBUAgCxAgloDAAABwBYAGkMAAAHAFsAawwAAAcAWwBqDAAABQBMAGwMAAAEAEkAbQwAAAMAPQDqDAAABgBhAG4MAAADAEkAbwwAAAEAWgAWAAkJXR1UAgCxAgloDAAAAwBIAGkMAAADAFIAawwAAAMAUABqDAAAAwAXAGwMAAACAEkAbQwAAAIAPQDqDAAAAwBEAG4MAAADAEkAbwwAAAEAWgAXAAcJ+B/xGACDAgdoDAAABABYAGkMAAAEAFsAawwAAAQAWwBqDAAAAgBMAGwMAAACAEUAbQwAAAEAMwDqDAAAAwBhAAAA.',
Mu='Muddless:BAABLgAECn8eAAMWAAgJkh8wAwCEAghoDAAABQBJAGkMAAAFAFcAawwAAAMAUgBqDAAAAwA7AGwMAAAEAFwAbQwAAAEASgDqDAAABgBbAG4MAAADAEAAFgAICZIfMAMAhAIIaAwAAAUASQBpDAAABQBXAGsMAAADAFIAagwAAAMAOwBsDAAABABcAG0MAAABAEoA6gwAAAQAWwBuDAAAAwBAABcAAQnqC8ulADkAAeoMAAACAB4AAAA=.Mudds:BAABLgAECn8cAAIJAAgJoSB3EAB5AghoDAAABgBVAGkMAAAFAFoAawwAAAUAWABqDAAAAgBMAGwMAAACAFQAbQwAAAIAUgDqDAAABQBXAG4MAAABAEEACQAICaEgdxAAeQIIaAwAAAYAVQBpDAAABQBaAGsMAAAFAFgAagwAAAIATABsDAAAAgBUAG0MAAACAFIA6gwAAAUAVwBuDAAAAQBBAAAA.',
Na='Naelia:BAAALgAECgQJBQAAAA==.Nakira:BAAALgAECgMJAwAAAA==.Nami:BAAALgAECgUJBQAAAA==.',
Ni='Nicodemus:BAAALgADCgEJAQAAAA==.Nightrush:BAABLgAECn8oAAMCAAgJISVvCwCLAghoDAAABwBjAGkMAAAHAGIAawwAAAYAYQBqDAAABQBdAGwMAAADAFEAbQwAAAMAXQDqDAAABgBiAG4MAAADAGAAAgAGCQMmbwsAiwIGaAwAAAEAYwBpDAAAAQBiAGsMAAACAGEAbQwAAAMAXQDqDAAAAQBiAG4MAAADAGAAAQAGCbQhOgYAvgEGaAwAAAYAWwBpDAAABgBXAGsMAAAEAFQAagwAAAUAXQBsDAAAAwBRAOoMAAAFAFYAAAA=.',
No='Noodles:BAABLgAECn8XAAIFAAYJehYbWwD1AAZoDAAABQBGAGkMAAAFADkAawwAAAUAMwBqDAAABABMAGwMAAACACwA6gwAAAIAPwAFAAYJehYbWwD1AAZoDAAABQBGAGkMAAAFADkAawwAAAUAMwBqDAAABABMAGwMAAACACwA6gwAAAIAPwAAAA==.Norbit:BAAALgAECgEJAQAAAA==.',
Oe='Oesteroth:BAABLgAECn8UAAILAAYJbgXFWADDAAZoDAAABAAYAGkMAAAEAAkAawwAAAQACQBqDAAAAwAUAGwMAAABAAgA6gwAAAQACgALAAYJbgXFWADDAAZoDAAABAAYAGkMAAAEAAkAawwAAAQACQBqDAAAAwAUAGwMAAABAAgA6gwAAAQACgAAAA==.',
Ok='Okomo:BAAALgAECgEJAQABLgAECgMJAwAUAAAAAA==.',
Pa='Palaben:BAABLgAECn8bAAMVAAgJdRHfJwBYAQhoDAAABAAyAGkMAAAEAFsAawwAAAQANQBqDAAABAAiAGwMAAADACYAbQwAAAIAFgDqDAAAAwA9AG4MAAADAAMAFQAHCawS3ycAWAEHaAwAAAQAMgBpDAAABABbAGsMAAAEADUAagwAAAMAIgBsDAAAAgAmAOoMAAADAD0AbgwAAAEAAwAPAAQJWgyLtgCYAARqDAAAAQAGAGwMAAABABkAbQwAAAIAGgBuDAAAAgAqAAAA.Pantsu:BAABLgAECn8xAAMKAAgJfiWHCADfAghoDAAACABiAGkMAAAIAGMAawwAAAcAYgBqDAAABgBdAGwMAAAFAF8AbQwAAAQAWQDqDAAABwBeAG4MAAAEAGAACgAICX4lhwgA3wIIaAwAAAcAYgBpDAAABwBjAGsMAAAGAGIAagwAAAUAXQBsDAAABABfAG0MAAADAFkA6gwAAAcAXgBuDAAABABgABgABgmGIYsDAOkBBmgMAAABAFQAaQwAAAEAXABrDAAAAQBbAGoMAAABAD8AbAwAAAEAWgBtDAAAAQBFAAAA.Pateaviejas:BAAALgAECgMJAwAAAA==.Pawnchy:BAAALgAECgUJCQAAAA==.',
Pe='Peepaw:BAAALgAECgYJEQAAAA==.',
Pi='Pitchwhite:BAABLgAECn8XAAIRAAYJHBE9KQAKAQZoDAAABQA7AGkMAAAEACMAawwAAAQAOwBqDAAABAAzAGwMAAABABIA6gwAAAUAJgARAAYJHBE9KQAKAQZoDAAABQA7AGkMAAAEACMAawwAAAQAOwBqDAAABAAzAGwMAAABABIA6gwAAAUAJgAAAA==.Pixel:BAAALgADCgkJDQAAAA==.',
Pr='Proselyte:BAACLgAFFH8HAAIJAAMJ6xH6EADkAANoDAAAAwAmAGkMAAADADMA6gwAAAEALwAJAAMJ6xH6EADkAANoDAAAAwAmAGkMAAADADMA6gwAAAEALwAuAAQKfyIAAgkACQmxHRAFAJgCAAkACQmxHRAFAJgCAAAA.',
Pu='Punchbear:BAAALgADCgQJBAAAAA==.Punchize:BAABLgAECn8YAAMZAAgJwBynCQAyAghoDAAABABiAGkMAAAFAFQAawwAAAUARwBqDAAAAgBgAGwMAAACADwAbQwAAAEAVQDqDAAABABWAG4MAAABAB0AGQAICcAcpwkAMgIIaAwAAAQAYgBpDAAABABUAGsMAAAEAEcAagwAAAIAYABsDAAAAgA8AG0MAAABAFUA6gwAAAQAVgBuDAAAAQAdABoAAgn0CqdSAEoAAmkMAAABACAAawwAAAEAFwAAAA==.Punchlocks:BAAALgAECgEJAQAAAA==.',
Qu='Quirkchungus:BAAALgAECgQJBAAAAA==.',
Ra='Rakrak:BAAALgADCgEJAQAAAA==.Rani:BAAALgADCgUJBQAAAA==.Rathon:BAAALgAECgcJCgABLgAECggJGgAFAJYXAA==.',
Re='Remote:BAAALgAECgMJAwAAAA==.',
Ri='Rianis:BAAALgADCgcJEAAAAA==.Rilea:BAAALgAECgYJEAAAAA==.',
['Rä']='Räiyu:BAAALgADCgMJAwAAAA==.',
Sa='Sadgasm:BAABLgAECn8eAAIbAAkJnx61AQC5AgloDAAABQBfAGkMAAAFAGEAawwAAAUATABqDAAAAwBOAGwMAAADAEIAbQwAAAEAJgDqDAAABgBVAG4MAAABAFUAbwwAAAEAUwAbAAkJnx61AQC5AgloDAAABQBfAGkMAAAFAGEAawwAAAUATABqDAAAAwBOAGwMAAADAEIAbQwAAAEAJgDqDAAABgBVAG4MAAABAFUAbwwAAAEAUwAAAA==.Safeword:BAAALgAECgkJCwAAAA==.Sauron:BAAALgAECgMJBQAAAA==.',
Se='Sebrine:BAAALgAECgUJCwAAAA==.Seishan:BAACLgAFFH8GAAMEAAUJpw/lEQC6AAVoDAAAAQAwAGkMAAABAEIAawwAAAEAEABqDAAAAQArAOoMAAACABwABAAFCacP5REAugAFaAwAAAEAMABpDAAAAQBCAGsMAAABABAAagwAAAEAKwDqDAAAAQAcABwAAQmvCdUKAFMAAeoMAAABABgALgAECn8fAAQcAAcJkxsqBwD0AQAcAAYJ1R4qBwD0AQAEAAUJxhfaJgDNAAAdAAEJ+xcSEgBJAAAAAA==.Seneca:BAAALgAECgEJBAAAAA==.',
Sh='Shadowtalon:BAAALgADCgEJAQAAAA==.Shamandrea:BAAALgAECgYJBgABLgAECggJHwARADgYAA==.Shzam:BAAALgADCgYJDgAAAA==.',
Sl='Slam:BAAALgADCgMJBQAAAA==.Sleipner:BAABLgAECn8fAAIeAAkJAQ61DgBYAQloDAAABABTAGkMAAAEADQAawwAAAQAJgBqDAAABAAdAGwMAAAEABsAbQwAAAMAEgDqDAAABQAhAG4MAAACABMAbwwAAAEADAAeAAkJAQ61DgBYAQloDAAABABTAGkMAAAEADQAawwAAAQAJgBqDAAABAAdAGwMAAAEABsAbQwAAAMAEgDqDAAABQAhAG4MAAACABMAbwwAAAEADAAAAA==.',
Sm='Smiley:BAAALgADCgYJBgAAAA==.',
Sn='Snugglehex:BAAALgADCgEJAQAAAA==.',
So='Socktrout:BAABLgAECn8qAAQfAAkJnReBHgAAAgloDAAABgAzAGkMAAAFAEkAawwAAAQAQwBqDAAAAwAbAGwMAAAGACkAbQwAAAUAPwDqDAAABgBBAG4MAAAEAEsAbwwAAAMAKwAfAAgJexaBHgAAAghoDAAABgAzAGkMAAAFAEkAawwAAAQAQwBsDAAAAgApAG0MAAACAD8A6gwAAAYAQQBuDAAABABLAG8MAAACABQAIAADCekKFEMAqQADagwAAAIAGwBsDAAABAAgAG0MAAADABYAIQACCS0RZxYATgACagwAAAEABgBvDAAAAQArAAAA.Softgrizzly:BAAALgADCgMJAwAAAA==.Solidgold:BAACLgAFFH8RAAMXAAcJaBXNBACoAQdoDAAAAwBbAGkMAAACABwAawwAAAMALgBqDAAAAwBaAGwMAAACADAAbQwAAAEAFQDqDAAAAwBcABcABwloFc0EAKgBB2gMAAADAFsAaQwAAAIAHABrDAAAAwAuAGoMAAADAFoAbAwAAAEAMABtDAAAAQAVAOoMAAADAFwAFgABCaAGuAsAUwABbAwAAAEAEAAuAAQKfyYAAxcACAmIJMkTALACABcACAlhI8kTALACABYABQmoIPwcAAgBAAAA.Solvane:BAAALgAECgMJAwABLgAFFAUJBgAEAKcPAA==.',
Sp='Spongeybob:BAAALgADCgEJAgAAAA==.',
Ss='Sscrubbucket:BAAALgAECgYJBgAAAA==.',
Su='Sunrise:BAAALgADCgkJEAAAAA==.',
Sy='Syllassa:BAAALgAECgkJAQAAAA==.Sylv:BAAALgADCgQJBgAAAA==.',
Ta='Taelia:BAACLgAFFH8MAAIKAAQJFAtkPQAnAQRoDAAABAA+AGkMAAADABUAawwAAAIACQDqDAAAAwATAAoABAkUC2Q9ACcBBGgMAAAEAD4AaQwAAAMAFQBrDAAAAgAJAOoMAAADABMALgAECn81AAIKAAkJCSCRCADeAgAKAAkJCSCRCADeAgAAAA==.Tahine:BAAALgAECgYJDQAAAA==.Tans:BAAALgADCgkJCwAAAA==.',
Ti='Tiktoks:BAAALgAECgEJAQABLgAECggJKQARAO8ZAA==.Timetwoflame:BAABLgAECn8ZAAIiAAgJ5REXCQDZAQhoDAAABgA/AGkMAAAGAEUAawwAAAUAQgBqDAAAAQATAGwMAAABABwAbQwAAAEAIgDqDAAAAwAyAG4MAAACACEAIgAICeURFwkA2QEIaAwAAAYAPwBpDAAABgBFAGsMAAAFAEIAagwAAAEAEwBsDAAAAQAcAG0MAAABACIA6gwAAAMAMgBuDAAAAgAhAAAA.',
Tn='Tnarg:BAAALgADCgIJAgAAAA==.',
To='Tokki:BAAALgAECgYJBwAAAA==.',
Tr='Trekvis:BAAALgADCgcJDgAAAA==.',
Tu='Tugboat:BAAALgADCgIJAgAAAA==.',
['Tû']='Tûâny:BAAALgAECgUJBQAAAA==.',
Up='Upphoria:BAABLgAECn8XAAMRAAYJ1AqELADzAAZoDAAABQArAGkMAAAGADAAawwAAAQABABqDAAAAwAOAGwMAAACAAwA6gwAAAMAKQARAAYJ1AqELADzAAZoDAAABAArAGkMAAAFADAAawwAAAQABABqDAAAAwAOAGwMAAACAAwA6gwAAAMAKQAGAAIJPgOtXgAmAAJoDAAAAQAEAGkMAAABAAwAAAA=.',
Ur='Urkel:BAAALgADCgIJAgAAAA==.',
Ut='Uthomage:BAAALgAECgMJAwAAAA==.',
Va='Vashi:BAAALgADCgcJBwAAAA==.',
Vi='Viccan:BAABLgAECn8iAAIgAAkJ/AaQCgA0AQloDAAABgAeAGkMAAAFABMAawwAAAUAEABqDAAAAwAIAGwMAAAEAAkAbQwAAAIABADqDAAABgAbAG4MAAACAA8AbwwAAAEAEgAgAAkJ/AaQCgA0AQloDAAABgAeAGkMAAAFABMAawwAAAUAEABqDAAAAwAIAGwMAAAEAAkAbQwAAAIABADqDAAABgAbAG4MAAACAA8AbwwAAAEAEgAAAA==.',
Wa='Walkingtanko:BAAALgADCgIJAgAAAA==.Wavés:BAAALgADCgIJAgAAAA==.',
We='Wef:BAAALgADCgUJBQAAAA==.',
Wi='Willowleaf:BAAALgAECgEJAQABLgAECggJHwARADgYAA==.',
Wo='Wolffie:BAAALgAECggJEAAAAA==.',
Wu='Wushuu:BAAALgAECgUJCgABLgAFFAQJDAAIADQLAA==.',
Xe='Xernaeus:BAAALgADCgQJBAAAAA==.',
Ya='Yahwëh:BAAALgAECgMJBAAAAA==.',
Yo='Yodason:BAAALgADCgQJBQAAAA==.',
Yu='Yuukï:BAABLgAECn8iAAMJAAkJIh0PCABOAgloDAAABgBbAGkMAAAFAFUAawwAAAYAUQBqDAAAAwA5AGwMAAAEADgAbQwAAAIAJwDqDAAABQBbAG4MAAACAFEAbwwAAAEARAAJAAgJdx0PCABOAghoDAAABgBbAGkMAAAFAFUAawwAAAUAUQBqDAAAAwA5AGwMAAADADgAbQwAAAEAJwDqDAAABQBbAG4MAAACAFEAGgAECQgHrEEAigAEawwAAAEABwBsDAAAAQANAG0MAAABABAAbwwAAAEAIgAAAA==.',
Za='Zaelyse:BAAALgADCgMJAwAAAA==.Zaton:BAABLgAECn8WAAIIAAcJNxKEVgBxAQdoDAAABAAsAGkMAAAEAEEAawwAAAQAMQBqDAAABABMAGwMAAACAA8AbQwAAAEANQDqDAAAAwAxAAgABwk3EoRWAHEBB2gMAAAEACwAaQwAAAQAQQBrDAAABAAxAGoMAAAEAEwAbAwAAAIADwBtDAAAAQA1AOoMAAADADEAAAA=.',
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
