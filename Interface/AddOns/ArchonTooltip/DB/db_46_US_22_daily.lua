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

local lookup = {'Hunter-Marksmanship','Hunter-BeastMastery','Hunter-Survival','Rogue-Subtlety','DemonHunter-Devourer','Priest-Shadow','Warrior-Protection','DeathKnight-Frost','DeathKnight-Blood','Mage-Frost','Monk-Windwalker','DeathKnight-Unholy','Druid-Restoration','Druid-Balance','Shaman-Restoration','Shaman-Elemental','Warrior-Fury','Paladin-Retribution','Priest-Discipline','Priest-Holy','Evoker-Devastation','Evoker-Augmentation','Paladin-Holy','Unknown-Unknown','Warrior-Arms','Warlock-Demonology','Monk-Mistweaver','Monk-Brewmaster','Druid-Feral','Shaman-Enhancement','Rogue-Assassination','Rogue-Outlaw','Paladin-Protection','Warlock-Destruction','Warlock-Affliction','Evoker-Preservation',}
local provider = {region='US',realm='Auchindoun',name='US',type='daily',zone=46,date='2026-05-30',data={Ad='Adnerb:BAABLgAECn8VAAQBAAgJORIRGQDUAAhoDAAABwBNAGkMAAADADAAawwAAAMAMQBqDAAAAgAzAGwMAAABACQAbQwAAAEAGADqDAAAAwBIAG4MAAABABAAAQAGCQMTERkA1AAGaAwAAAcATQBpDAAAAgAqAGsMAAABACUAbAwAAAEAJABtDAAAAQAYAOoMAAADAEgAAgAECeoOmr4ApAAEaQwAAAEAMABrDAAAAQAxAGoMAAABADMAbgwAAAEAEAADAAIJkQdMXQA0AAJrDAAAAQATAGoMAAABABMAAS4ABRQFCQcABAAlEQA=.',
Ah='Ahriman:BAABLgAECn8XAAIFAAYJLw6+fgAtAQZoDAAABgA1AGkMAAAFACYAawwAAAQAJQBqDAAAAwAvAGwMAAACACIA6gwAAAMAEQAFAAYJLw6+fgAtAQZoDAAABgA1AGkMAAAFACYAawwAAAQAJQBqDAAAAwAvAGwMAAACACIA6gwAAAMAEQAAAA==.',
Al='Alystra:BAABLgAECn8aAAIGAAgJ1wZOPAD9AAhoDAAABQAQAGkMAAAEABYAawwAAAQAEgBqDAAAAwAeAGwMAAADABgAbQwAAAEADADqDAAABAANAG4MAAACAA0ABgAICdcGTjwA/QAIaAwAAAUAEABpDAAABAAWAGsMAAAEABIAagwAAAMAHgBsDAAAAwAYAG0MAAABAAwA6gwAAAQADQBuDAAAAgANAAAA.',
An='Anjedin:BAAALgAECgYJEAAAAA==.',
Ao='Aoki:BAABLgAECn8lAAICAAgJHyLcFwCAAghoDAAABgBfAGkMAAAGAF4AawwAAAUATwBqDAAABgBgAGwMAAAEAF0AbQwAAAIASADqDAAAAwBVAG4MAAAFAFoAAgAICR8i3BcAgAIIaAwAAAYAXwBpDAAABgBeAGsMAAAFAE8AagwAAAYAYABsDAAABABdAG0MAAACAEgA6gwAAAMAVQBuDAAABQBaAAAA.',
Ar='Archdemon:BAABLgAECn8oAAIHAAkJtBitDAAKAgloDAAABwA7AGkMAAAFAEkAawwAAAUASgBqDAAAAwAxAGwMAAAFADYAbQwAAAMAMQDqDAAABwBCAG4MAAADAEMAbwwAAAIAPQAHAAkJtBitDAAKAgloDAAABwA7AGkMAAAFAEkAawwAAAUASgBqDAAAAwAxAGwMAAAFADYAbQwAAAMAMQDqDAAABwBCAG4MAAADAEMAbwwAAAIAPQAAAA==.Argonos:BAAALgAECgcJDQAAAA==.Arielias:BAABLgAECn8WAAMIAAkJAhkDBwADAgloDAAABABZAGkMAAAFAE8AawwAAAUAQgBqDAAAAQAkAGwMAAACAD0AbQwAAAEANADqDAAAAgBUAG4MAAABAEAAbwwAAAEADQAIAAcJ9RoDBwADAgdoDAAAAwBZAGkMAAAEAE8AawwAAAQAPwBsDAAAAQAxAG0MAAABADQA6gwAAAIAVABuDAAAAQBAAAkABgnLE34iACQBBmgMAAABADYAaQwAAAEAOABrDAAAAQBCAGoMAAABACQAbAwAAAEAPQBvDAAAAQANAAEuAAUUBQkHAAQAJREA.Arkanoas:BAACLgAFFH8OAAIKAAUJcgvsXAAYAQVoDAAABAA3AGkMAAADAB8AawwAAAMAFgBqDAAAAQAFAOoMAAADAAcACgAFCXIL7FwAGAEFaAwAAAQANwBpDAAAAwAfAGsMAAADABYAagwAAAEABQDqDAAAAwAHAC4ABAp/KwACCgAJCbYWDDgAlAIACgAJCbYWDDgAlAIAAAA=.',
As='Ashatal:BAAALgADCgEJAQAAAA==.Ashphantom:BAAALgAECgIJAgAAAA==.',
Ba='Bagelbite:BAAALgADCgUJBQAAAA==.Banshee:BAAALgAECgYJDAABLgAFFAUJBwAEACURAA==.Battahelin:BAAALgAECgQJBgAAAA==.Bazoo:BAAALgAECgEJAQAAAA==.',
Be='Bearmanowl:BAAALgAECgYJBwAAAA==.Bellator:BAAALgAECgMJBAAAAA==.',
Bi='Bigchungus:BAABLgAECn8dAAILAAYJ/AiUTwCxAAZoDAAABgAgAGkMAAAGABEAawwAAAYAFgBqDAAABAASAGwMAAADABEA6gwAAAQAGQALAAYJ/AiUTwCxAAZoDAAABgAgAGkMAAAGABEAawwAAAYAFgBqDAAABAASAGwMAAADABEA6gwAAAQAGQAAAA==.',
Bl='Blart:BAAALgAECgUJBwAAAA==.Blended:BAAALgAECgEJAQAAAA==.Bloody:BAAALgAFFAEJAQAAAA==.',
Br='Breathplay:BAABLgAECn8YAAIMAAkJbRqWPQBBAgloDAAABABQAGkMAAAEAEoAawwAAAQAOwBqDAAAAgA6AGwMAAACAEYAbQwAAAIAQQDqDAAAAwBLAG4MAAACAEQAbwwAAAEALwAMAAkJbRqWPQBBAgloDAAABABQAGkMAAAEAEoAawwAAAQAOwBqDAAAAgA6AGwMAAACAEYAbQwAAAIAQQDqDAAAAwBLAG4MAAACAEQAbwwAAAEALwAAAA==.',
['Bà']='Bàyne:BAABLgAECn8yAAINAAkJUBOkLADjAQloDAAABwAuAGkMAAAHAEcAawwAAAcAPgBqDAAABgAxAGwMAAAGAEMAbQwAAAQAIwDqDAAABwBEAG4MAAAEABwAbwwAAAIADgANAAkJUBOkLADjAQloDAAABwAuAGkMAAAHAEcAawwAAAcAPgBqDAAABgAxAGwMAAAGAEMAbQwAAAQAIwDqDAAABwBEAG4MAAAEABwAbwwAAAIADgAAAA==.',
Ca='Caroquintero:BAABLgAECn8fAAIKAAYJcgOS7wChAAZoDAAABgADAGkMAAAHABAAawwAAAYACABqDAAABAALAGwMAAAEAAkA6gwAAAQABgAKAAYJcgOS7wChAAZoDAAABgADAGkMAAAHABAAawwAAAYACABqDAAABAALAGwMAAAEAAkA6gwAAAQABgAAAA==.',
Ch='Charliemen:BAAALgAECgQJCAAAAA==.Chilli:BAAALgADCgEJAQAAAA==.Chubtart:BAACLgAFFH8MAAIOAAQJ9BpuEwBSAQRoDAAABQBWAGkMAAAEAEEAawwAAAEAJgDqDAAAAgBUAA4ABAn0Gm4TAFIBBGgMAAAFAFYAaQwAAAQAQQBrDAAAAQAmAOoMAAACAFQALgAECn80AAIOAAkJ0SM9CAASAwAOAAkJ0SM9CAASAwAAAA==.Churrasco:BAAALgAECgQJCAAAAA==.',
Ci='Ciborg:BAAALgADCgUJBQAAAA==.',
Cl='Clayton:BAAALgADCgcJBAAAAA==.',
Co='Cojeculos:BAAALgAECgQJCwAAAA==.',
Cu='Cunumi:BAAALgAECgMJBAAAAA==.',
Da='Daddy:BAACLgAFFH8FAAMPAAMJhA3aQQDCAANoDAAAAwBJAGkMAAABABkA6gwAAAEABAAPAAMJhA3aQQDCAANoDAAAAgBJAGkMAAABABkA6gwAAAEABAAQAAEJ1QjpSAA8AAFoDAAAAQAWAC4ABAp/NQADEAAJCWQV9BwA4QEAEAAJCWQV9BwA4QEADwAGCSsNxGkA/gAAAAA=.Daizenat:BAAALgADCgIJAgAAAA==.Danehar:BAAALgAECgEJAQAAAA==.Darthforum:BAAALgADCgMJAwAAAA==.',
Dc='Dcone:BAAALgADCgYJBgAAAA==.',
De='Deadkey:BAAALgADCgEJAQAAAA==.Deathborne:BAAALgAECgUJCQAAAA==.Deathshreik:BAAALgADCgMJAwAAAA==.Deathslam:BAACLgAFFH8NAAIMAAQJ/AhWaAAPAQRoDAAABAAsAGkMAAADABMAawwAAAMAEADqDAAAAwALAAwABAn8CFZoAA8BBGgMAAAEACwAaQwAAAMAEwBrDAAAAwAQAOoMAAADAAsALgAECn8kAAIMAAkJbRnbKABKAgAMAAkJbRnbKABKAgAAAA==.',
Dr='Droston:BAAALgADCgQJBAAAAA==.',
Du='Durötan:BAABLgAECn8ZAAQCAAkJUhCgNwDoAQloDAAAAwAuAGkMAAAEAEIAawwAAAQAOABqDAAAAwAfAGwMAAACADQAbQwAAAIAFwDqDAAABQArAG4MAAABABIAbwwAAAEAGQACAAkJUhCgNwDoAQloDAAAAgAuAGkMAAADAEIAawwAAAIAOABqDAAAAwAfAGwMAAABADQAbQwAAAEAFwDqDAAABAArAG4MAAABABIAbwwAAAEAGQABAAUJRAoAVgDxAAVoDAAAAQAeAGsMAAACACgAbAwAAAEAEgBtDAAAAQAJAOoMAAABACAAAwABCb8KmlkAOgABaQwAAAEAGwABLgAFFAgJHAARAIwdAA==.Dutchess:BAABLgAECn8iAAISAAkJUhuZKwA6AgloDAAABgBFAGkMAAAFAFIAawwAAAQASABqDAAABAA6AGwMAAAFAFQAbQwAAAIAQwDqDAAABQA7AG4MAAACADAAbwwAAAEASwASAAkJUhuZKwA6AgloDAAABgBFAGkMAAAFAFIAawwAAAQASABqDAAABAA6AGwMAAAFAFQAbQwAAAIAQwDqDAAABQA7AG4MAAACADAAbwwAAAEASwAAAA==.',
Dy='Dylan:BAACLgAFFH8ZAAIKAAUJayOcKgCQAQVoDAAABgBfAGkMAAAHAGEAawwAAAUAVABqDAAAAgBWAOoMAAAFAFUACgAFCWsjnCoAkAEFaAwAAAYAXwBpDAAABwBhAGsMAAAFAFQAagwAAAIAVgDqDAAABQBVAC4ABAp/LwACCgAJCWklhwQAVAMACgAJCWklhwQAVAMAAAA=.Dylanj:BAAALgAECgQJBAABLgAFFAUJGQAKAGsjAQ==.',
Ec='Echevalier:BAAALgAECgQJBQAAAA==.Echoes:BAAALgADCgQJBAAAAA==.',
Eg='Egonspengler:BAAALgADCgQJBAAAAA==.',
El='Elayia:BAAALgADCgEJAQAAAA==.Elowen:BAAALgAFFAIJBAAAAQ==.',
En='Enhae:BAAALgAECgEJAQAAAA==.',
Er='Eresiine:BAAALgAECggJDwAAAA==.Eríngo:BAAALgAFFAEJAQAAAA==.',
Es='Esna:BAAALgADCgUJCQAAAA==.',
Fi='Filomena:BAAALgADCgUJBgAAAA==.Firnin:BAAALgAECgYJEAAAAA==.',
Fl='Floise:BAACLgAFFH8SAAMTAAUJ6hTVFwBuAQVoDAAABQAuAGkMAAAEADsAawwAAAMASgBqDAAAAQAsAOoMAAAFACkAEwAFCbYT1RcAbgEFaAwAAAIALgBpDAAAAwAsAGsMAAADAEoAagwAAAEALADqDAAABQApABQAAglUE1kNAJMAAmgMAAADACcAaQwAAAEAOwAuAAQKfx4ABBQACQn7GXcMAIwCABQACQlAGXcMAIwCABMABwkQFRc5AAYBAAYAAQlcEn9xADoAAAAA.Flounder:BAAALgAECgEJAwAAAA==.',
Fo='Foamtotem:BAAALgAECgUJBQAAAA==.Forumshaman:BAAALgADCgcJBwAAAA==.Forumsoldier:BAACLgAFFH8GAAIKAAQJagfVXwAQAQRoDAAAAgAdAGkMAAACABUAawwAAAEACADqDAAAAQAQAAoABAlqB9VfABABBGgMAAACAB0AaQwAAAIAFQBrDAAAAQAIAOoMAAABABAALgAECn8kAAIKAAkJxBVZTADfAQAKAAkJxBVZTADfAQAAAA==.',
Fr='Frozenscorch:BAAALgAECgkJEwAAAA==.',
Ft='Fteve:BAAALgAECgUJCgAAAA==.',
['Fä']='Fälkor:BAABLgAECn8rAAMVAAgJrQYvEwDFAAhoDAAABwAdAGkMAAAGABgAawwAAAUAEwBqDAAABgAZAGwMAAAGABMAbQwAAAQACgDqDAAABgAIAG4MAAADAAcAFgAICa0GTUkA4gAIaAwAAAUAHQBpDAAABAAYAGsMAAAEABMAagwAAAUAFwBsDAAABQATAG0MAAAEAAoA6gwAAAYACABuDAAAAgAHABUABgkkBi8TAMUABmgMAAACABMAaQwAAAIAFABrDAAAAQAPAGoMAAABABkAbAwAAAEADwBuDAAAAQAHAAAA.',
['Fö']='Föx:BAAALgAFFAQJBAAAAA==.',
Gi='Gigamoo:BAAALgAECgQJBgAAAA==.',
Gl='Glorfindel:BAAALgAFFAEJAgABLgAFFAIJBwAMAEwSAA==.Glys:BAAALgAECgUJCgAAAA==.',
Go='Gogocow:BAAALgAECgEJAQAAAA==.Gooba:BAAALgAECgEJAQAAAA==.Goommar:BAABLgAECn8ZAAIRAAcJQQIYbgCLAAdoDAAABAAEAGkMAAADAAYAawwAAAQACABqDAAABgAJAGwMAAADAAgA6gwAAAQAAwBuDAAAAQACABEABwlBAhhuAIsAB2gMAAAEAAQAaQwAAAMABgBrDAAABAAIAGoMAAAGAAkAbAwAAAMACADqDAAABAADAG4MAAABAAIAAAA=.Gorim:BAAALgAECgIJAgAAAA==.',
Gr='Grandgoose:BAAALgADCgIJAgAAAA==.Grandpa:BAAALgAECgcJDAAAAA==.Granuju:BAAALgADCgUJBgAAAA==.',
Gu='Gunnhildr:BAAALgADCgkJCQAAAA==.',
Ha='Hanasanai:BAAALgADCgMJBAAAAA==.Handil:BAABLgAECn8cAAIXAAYJTCMcFgBDAgZoDAAABQBZAGkMAAAFAFoAawwAAAUAXgBqDAAABQBcAGwMAAACAFEA6gwAAAYAXQAXAAYJTCMcFgBDAgZoDAAABQBZAGkMAAAFAFoAawwAAAUAXgBqDAAABQBcAGwMAAACAFEA6gwAAAYAXQAAAA==.Hathus:BAAALgAECgIJAgAAAA==.',
He='Helpingyou:BAABLgAECn8gAAIGAAkJSwyAIwCNAQloDAAAAwAcAGkMAAADABcAawwAAAIAFwBqDAAAAwAbAGwMAAAFADEAbQwAAAUALgDqDAAABAAdAG4MAAAFABMAbwwAAAIAHgAGAAkJSwyAIwCNAQloDAAAAwAcAGkMAAADABcAawwAAAIAFwBqDAAAAwAbAGwMAAAFADEAbQwAAAUALgDqDAAABAAdAG4MAAAFABMAbwwAAAIAHgAAAA==.',
Ho='Holybell:BAAALgAECgIJAgAAAA==.Hoptyj:BAAALgADCgIJAgAAAA==.',
['Hë']='Hënnessy:BAAALgADCgMJAwAAAA==.Hënnëssy:BAABLgAECn8gAAIXAAgJHxLIJwC2AQhoDAAABABYAGkMAAAEAB0AawwAAAQALgBqDAAABgA3AGwMAAAEAC0AbQwAAAIABADqDAAABwBAAG4MAAABACQAFwAICR8SyCcAtgEIaAwAAAQAWABpDAAABAAdAGsMAAAEAC4AagwAAAYANwBsDAAABAAtAG0MAAACAAQA6gwAAAcAQABuDAAAAQAkAAAA.',
Im='Impaladin:BAAALgAECgMJAwAAAA==.',
Io='Iolanthe:BAAALgADCgQJBAAAAA==.',
Iz='Izeroeasily:BAAALgAECgMJAwABLgAECgUJBgAYAAAAAA==.Izerohealz:BAAALgADCgQJBAAAAA==.Izzi:BAAALgAECgYJEgAAAA==.Izzia:BAABLgAECn8hAAINAAgJQxmLHABOAghoDAAABgBSAGkMAAAEAFQAawwAAAYAPwBqDAAAAgBGAGwMAAADAEgAbQwAAAMAIwDqDAAABwBRAG4MAAACABwADQAICUMZixwATgIIaAwAAAYAUgBpDAAABABUAGsMAAAGAD8AagwAAAIARgBsDAAAAwBIAG0MAAADACMA6gwAAAcAUQBuDAAAAgAcAAAA.',
Ja='Jabbathabutt:BAAALgAECgYJCQAAAA==.Jaceret:BAAALgAECgEJAQAAAA==.Jasia:BAAALgADCgYJCAAAAA==.',
Jo='Joyboy:BAAALgAECgEJAQAAAA==.',
Ju='Justfn:BAAALgADCgUJBwAAAA==.',
Ka='Kamitos:BAABLgAECn8sAAMTAAkJpA8QHADMAQloDAAACAAlAGkMAAAIADUAawwAAAQAOABqDAAABgAnAGwMAAAGACgAbQwAAAEAEgDqDAAABgA5AG4MAAAEACEAbwwAAAEAFgATAAkJpA8QHADMAQloDAAABgAlAGkMAAAHADUAawwAAAMAOABqDAAABAAnAGwMAAAEACgAbQwAAAEAEgDqDAAABgA5AG4MAAAEACEAbwwAAAEAFgAGAAUJyAhmRADZAAVoDAAAAgAiAGkMAAABABYAawwAAAEAGwBqDAAAAgAbAGwMAAACAAQAAAA=.Kaye:BAAALgAECgEJAQAAAA==.Kayewyn:BAABLgAECn8qAAINAAgJGhZRJwACAghoDAAACABWAGkMAAAIAD0AawwAAAgAUgBqDAAABQAwAGwMAAAEADwAbQwAAAEADwDqDAAABABDAG4MAAAEAB0ADQAICRoWUScAAgIIaAwAAAgAVgBpDAAACAA9AGsMAAAIAFIAagwAAAUAMABsDAAABAA8AG0MAAABAA8A6gwAAAQAQwBuDAAABAAdAAAA.',
Kb='Kbdh:BAAALgAECgYJDQABLgAFFAIJAwAYAAAAAA==.Kbdruid:BAAALgAFFAEJAQABLgAFFAIJAwAYAAAAAA==.Kbhunter:BAAALgAECgUJCAABLgAFFAIJAwAYAAAAAA==.Kbmage:BAAALgADCgQJBAABLgAFFAIJAwAYAAAAAA==.Kbmonk:BAAALgAFFAIJAwAAAA==.Kbpaladin:BAAALgAECgYJBgABLgAFFAIJAwAYAAAAAA==.',
Ke='Keiji:BAAALgAECgYJDgAAAA==.Kelemvor:BAAALgAECgUJBQAAAA==.Kelôx:BAAALgAECgQJBAAAAA==.',
Kl='Klipnor:BAAALgAECgQJCAAAAA==.',
Kr='Krocketeer:BAAALgAECgYJCQAAAA==.',
Ky='Kyndel:BAAALgAECgYJCgABLgAFFAUJHAANAO8dAA==.Kynn:BAACLgAFFH8cAAINAAUJ7x3IEADBAQVoDAAACABSAGkMAAAHAFEAawwAAAYAWgBqDAAAAwA9AOoMAAAEAEMADQAFCe8dyBAAwQEFaAwAAAgAUgBpDAAABwBRAGsMAAAGAFoAagwAAAMAPQDqDAAABABDAC4ABAp/OAADDQAJCZQi8wEAgQMADQAJCZQi8wEAgQMADgABCXcRxnkAPAAAAAA=.',
['Kè']='Kèlemvore:BAABLgAECn8uAAISAAgJkRK4YwCPAQhoDAAABwBBAGkMAAAHAEUAawwAAAcAPgBqDAAABgA2AGwMAAAHACEAbQwAAAIADwDqDAAABwA6AG4MAAADABsAEgAICZESuGMAjwEIaAwAAAcAQQBpDAAABwBFAGsMAAAHAD4AagwAAAYANgBsDAAABwAhAG0MAAACAA8A6gwAAAcAOgBuDAAAAwAbAAAA.',
Le='Leafittome:BAAALgADCgEJAQAAAA==.',
Ly='Lykos:BAAALgAECgYJDgAAAA==.',
Ma='Mammal:BAAALgAECgQJBAABLgAECggJGgAQAHQcAA==.',
Me='Medxchaos:BAAALgAECgQJBwABLgAFFAUJEgATAOoUAA==.Meowy:BAAALgAECgEJAQAAAA==.Mepha:BAABLgAECn8rAAMZAAkJlyAyCABYAgloDAAABwBYAGkMAAAHAFsAawwAAAcAWwBqDAAABQBMAGwMAAAEAEkAbQwAAAMAPQDqDAAABgBhAG4MAAADAEkAbwwAAAEAWgARAAcJ+B/yGACDAgdoDAAABABYAGkMAAAEAFsAawwAAAQAWwBqDAAAAgBMAGwMAAACAEUAbQwAAAEAMwDqDAAAAwBhABkACQleHTIIAFgCCWgMAAADAEgAaQwAAAMAUgBrDAAAAwBQAGoMAAADABcAbAwAAAIASQBtDAAAAgA9AOoMAAADAEQAbgwAAAMASQBvDAAAAQBaAAAA.',
Mi='Mightymost:BAAALgAECgYJDwAAAA==.',
Mu='Mudd:BAABLgAECn8kAAMZAAgJkh90CQA8AghoDAAABQBJAGkMAAAFAFcAawwAAAMAUgBqDAAAAwA7AGwMAAAEAFwAbQwAAAIASgDqDAAACQBbAG4MAAAFAEAAGQAICZIfdAkAPAIIaAwAAAUASQBpDAAABQBXAGsMAAADAFIAagwAAAMAOwBsDAAABABcAG0MAAACAEoA6gwAAAYAWwBuDAAABQBAABEAAQlwEF2QADYAAeoMAAADACoAAS4ABAoJCR0ACwAfIAA=.Mudds:BAABLgAECn8dAAILAAkJHyB7EAB5AgloDAAABgBVAGkMAAAFAFoAawwAAAUAWABqDAAAAgBMAGwMAAACAFQAbQwAAAIAUgDqDAAABQBXAG4MAAABAEEAbwwAAAEASQALAAkJHyB7EAB5AgloDAAABgBVAGkMAAAFAFoAawwAAAUAWABqDAAAAgBMAGwMAAACAFQAbQwAAAIAUgDqDAAABQBXAG4MAAABAEEAbwwAAAEASQAAAA==.',
Na='Naelia:BAABLgAECn8dAAIaAAcJRBY7TwCiAQdoDAAABQAtAGkMAAAFADgAawwAAAQALwBqDAAABAAYAGwMAAAFAFMAbQwAAAIANADqDAAABAA4ABoABwlEFjtPAKIBB2gMAAAFAC0AaQwAAAUAOABrDAAABAAvAGoMAAAEABgAbAwAAAUAUwBtDAAAAgA0AOoMAAAEADgAAS4ABRQFCRoADABBFQA=.Nakira:BAAALgAECgMJAwAAAA==.Nami:BAAALgAECgUJBQAAAA==.',
Ne='Nenekirimaru:BAAALgADCgIJAgAAAA==.',
Ni='Nicodemus:BAAALgADCgIJAgAAAA==.Nightrush:BAABLgAECn8oAAMCAAgJIiW2HgBYAghoDAAABwBjAGkMAAAHAGIAawwAAAYAYQBqDAAABQBdAGwMAAADAFEAbQwAAAMAXQDqDAAABgBiAG4MAAADAGAAAgAGCQQmth4AWAIGaAwAAAEAYwBpDAAAAQBiAGsMAAACAGEAbQwAAAMAXQDqDAAAAQBiAG4MAAADAGAAAQAGCbQh1AwAfgEGaAwAAAYAWwBpDAAABgBXAGsMAAAEAFQAagwAAAUAXQBsDAAAAwBRAOoMAAAFAFYAAAA=.',
No='Noodles:BAABLgAECn8dAAIFAAcJvhaUbwAoAQdoDAAABgBGAGkMAAAGADkAawwAAAYANABqDAAABQBMAGwMAAADACwA6gwAAAIAPwBuDAAAAQA8AAUABwm+FpRvACgBB2gMAAAGAEYAaQwAAAYAOQBrDAAABgA0AGoMAAAFAEwAbAwAAAMALADqDAAAAgA/AG4MAAABADwAAAA=.Norbit:BAAALgAECgEJAQAAAA==.',
Oe='Oesteroth:BAABLgAECn8UAAINAAYJbgVDewC0AAZoDAAABAAYAGkMAAAEAAkAawwAAAQACQBqDAAAAwAUAGwMAAABAAgA6gwAAAQACgANAAYJbgVDewC0AAZoDAAABAAYAGkMAAAEAAkAawwAAAQACQBqDAAAAwAUAGwMAAABAAgA6gwAAAQACgAAAA==.',
Ok='Okomo:BAAALgAECgUJBgAAAA==.',
Pa='Palaben:BAABLgAECn8bAAMXAAgJdRGHPAA+AQhoDAAABAAyAGkMAAAEAFsAawwAAAQANQBqDAAABAAiAGwMAAADACYAbQwAAAIAFgDqDAAAAwA9AG4MAAADAAMAFwAHCawShzwAPgEHaAwAAAQAMgBpDAAABABbAGsMAAAEADUAagwAAAMAIgBsDAAAAgAmAOoMAAADAD0AbgwAAAEAAwASAAQJXQzlCQGKAARqDAAAAQAGAGwMAAABABkAbQwAAAIAGgBuDAAAAgAqAAAA.Pantsu:BAABLgAECn9DAAQMAAkJuSV1BgA2AwloDAAACgBiAGkMAAAKAGMAawwAAAkAYgBqDAAACABdAGwMAAAHAF8AbQwAAAYAXQDqDAAACQBeAG4MAAAHAGAAbwwAAAEAYAAMAAkJiCV1BgA2AwloDAAACABiAGkMAAAIAGMAawwAAAcAYgBqDAAABgBdAGwMAAAFAF8AbQwAAAQAWQDqDAAABwBeAG4MAAAFAGAAbwwAAAEAYAAJAAgJ2CDiBwCHAghoDAAAAQBLAGkMAAABAFQAawwAAAEASwBqDAAAAQBaAGwMAAABAFMAbQwAAAEAXQDqDAAAAQBYAG4MAAABAFcACAAICf8f9AUAIwIIaAwAAAEAVABpDAAAAQBcAGsMAAABAFsAagwAAAEAPwBsDAAAAQBaAG0MAAABAEUA6gwAAAEASABuDAAAAQBHAAAA.Pateaviejas:BAAALgAECgMJAwAAAA==.Pawnchy:BAAALgAECgUJCQAAAA==.',
Pe='Peepaw:BAABLgAECn8ZAAIbAAYJTgXpagCdAAZoDAAABQAOAGkMAAAGABMAawwAAAYAEABqDAAAAwATAGwMAAABAAUA6gwAAAQABgAbAAYJTgXpagCdAAZoDAAABQAOAGkMAAAGABMAawwAAAYAEABqDAAAAwATAGwMAAABAAUA6gwAAAQABgAAAA==.Pennyz:BAAALgADCgYJBgAAAA==.',
Pi='Pitchwhite:BAABLgAECn8XAAIUAAYJHBFpRAAnAQZoDAAABQA7AGkMAAAEACMAawwAAAQAOwBqDAAABAAzAGwMAAABABIA6gwAAAUAJgAUAAYJHBFpRAAnAQZoDAAABQA7AGkMAAAEACMAawwAAAQAOwBqDAAABAAzAGwMAAABABIA6gwAAAUAJgAAAA==.Pixel:BAAALgADCgkJDQAAAA==.',
Pr='Proselyte:BAACLgAFFH8RAAILAAUJixj2DgAxAQVoDAAABQA7AGkMAAAFAEgAawwAAAIAMgBqDAAAAQAdAOoMAAAEAEQACwAFCYsY9g4AMQEFaAwAAAUAOwBpDAAABQBIAGsMAAACADIAagwAAAEAHQDqDAAABABEAC4ABAp/KQACCwAJCd4ffgcAvgIACwAJCd4ffgcAvgIAAAA=.',
Pu='Punchbear:BAAALgADCgYJBgAAAA==.Punchize:BAABLgAECn8tAAMcAAgJMCOSBgDAAghoDAAABwBiAGkMAAAIAFQAawwAAAgAVQBqDAAABQBgAGwMAAAEAFoAbQwAAAEAVQDqDAAACABbAG4MAAAEAF8AHAAICTAjkgYAwAIIaAwAAAcAYgBpDAAABwBUAGsMAAAHAFUAagwAAAUAYABsDAAABABaAG0MAAABAFUA6gwAAAgAWwBuDAAABABfABsAAgn0ChuOAEYAAmkMAAABACAAawwAAAEAFwAAAA==.Punchlocks:BAAALgAECgEJAQAAAA==.',
Qu='Quirkchungus:BAAALgAECgYJDwAAAA==.',
Ra='Rakrak:BAAALgADCgEJAQAAAA==.Rani:BAAALgADCgUJBQAAAA==.Rathon:BAAALgAECgkJDQABLgAFFAQJBgAdAGsXAA==.',
Re='Remote:BAAALgAECgQJBwAAAA==.',
Ri='Rianis:BAAALgADCgcJEAAAAA==.Rilea:BAAALgAECgYJEQAAAA==.Risenspirits:BAAALgAECgYJBgAAAA==.',
['Rä']='Räiyu:BAAALgADCgMJAwAAAA==.',
Sa='Sadgasm:BAABLgAECn8sAAIeAAkJGyAoAwDDAgloDAAABwBfAGkMAAAGAGEAawwAAAYATABqDAAABABbAGwMAAAFAEIAbQwAAAMARADqDAAACABVAG4MAAADAFUAbwwAAAIAUgAeAAkJGyAoAwDDAgloDAAABwBfAGkMAAAGAGEAawwAAAYATABqDAAABABbAGwMAAAFAEIAbQwAAAMARADqDAAACABVAG4MAAADAFUAbwwAAAIAUgAAAA==.Safeword:BAAALgAECgkJCwAAAA==.Sauron:BAAALgAECgUJCgAAAA==.',
Sc='Scrubuckett:BAAALgADCgYJBgAAAA==.',
Se='Sebrine:BAAALgAECgUJDAAAAA==.Seishan:BAACLgAFFH8HAAMEAAUJJRHoEQC6AAVoDAAAAgA/AGkMAAABAEIAawwAAAEAEABqDAAAAQArAOoMAAACABwABAAFCSUR6BEAugAFaAwAAAIAPwBpDAAAAQBCAGsMAAABABAAagwAAAEAKwDqDAAAAQAcAB8AAQmvCaEQAEEAAeoMAAABABgALgAECn8fAAQfAAcJkxsqBwD0AQAfAAYJ1R4qBwD0AQAEAAUJxhdMPQAyAQAgAAEJ+xeaHQBDAAAAAA==.Seneca:BAAALgAECgEJBAAAAA==.',
Sh='Shadowslam:BAAALgAECgYJCAAAAA==.Shadowtalon:BAAALgADCgEJAQAAAA==.Shamandrea:BAAALgAFFAMJAwAAAA==.Shzam:BAAALgAECgEJAQAAAA==.',
Sl='Slam:BAAALgADCgMJBQAAAA==.Sleipner:BAABLgAECn8fAAIhAAkJAA7CFwBGAQloDAAABABTAGkMAAAEADQAawwAAAQAJgBqDAAABAAdAGwMAAAEABsAbQwAAAMAEgDqDAAABQAhAG4MAAACABMAbwwAAAEADAAhAAkJAA7CFwBGAQloDAAABABTAGkMAAAEADQAawwAAAQAJgBqDAAABAAdAGwMAAAEABsAbQwAAAMAEgDqDAAABQAhAG4MAAACABMAbwwAAAEADAAAAA==.',
Sm='Smiley:BAAALgADCgYJBgAAAA==.',
Sn='Sneeze:BAAALgADCgIJAgAAAA==.Snugglehex:BAAALgADCgEJAQAAAA==.',
So='Socktrout:BAABLgAECn8qAAQaAAkJnxdcPwDSAQloDAAABgAzAGkMAAAFAEkAawwAAAQAQwBqDAAAAwAbAGwMAAAGACkAbQwAAAUAPwDqDAAABgBBAG4MAAAEAEsAbwwAAAMAKwAaAAgJfRZcPwDSAQhoDAAABgAzAGkMAAAFAEkAawwAAAQAQwBsDAAAAgApAG0MAAACAD8A6gwAAAYAQQBuDAAABABLAG8MAAACABQAIgADCesKEkMAqQADagwAAAIAGwBsDAAABAAgAG0MAAADABYAIwACCS0RJjAARQACagwAAAEABgBvDAAAAQArAAAA.Softgrizzly:BAAALgADCgMJAwAAAA==.Solidgold:BAACLgAFFH8cAAMRAAgJjB2+AACTAghoDAAABgBeAGkMAAAFAFMAawwAAAQAWgBqDAAABABaAGwMAAACADAAbQwAAAEAFQDqDAAABQBfAG4MAAABAF8AEQAICYwdvgAAkwIIaAwAAAYAXgBpDAAABQBTAGsMAAAEAFoAagwAAAQAWgBsDAAAAQAwAG0MAAABABUA6gwAAAUAXwBuDAAAAQBfABkAAQmgBroLAFMAAWwMAAABABAALgAECn8yAAMRAAgJfSVPBQD7AgARAAgJfSVPBQD7AgAZAAUJqCD8HAAIAQAAAA==.Solvane:BAAALgAECgMJAwABLgAFFAUJBwAEACURAA==.',
Sp='Spongeybob:BAAALgADCgEJAgAAAA==.',
Ss='Sscrubbucket:BAAALgAECgYJBgAAAA==.',
Su='Sunrise:BAAALgADCgkJEAAAAA==.',
Sy='Syllassa:BAAALgAECgkJAQAAAA==.Sylv:BAAALgAECgQJBAAAAA==.',
Ta='Taelia:BAACLgAFFH8aAAIMAAUJQRWdUQAxAQVoDAAABwBIAGkMAAAGADUAawwAAAUAJgBqDAAAAgAyAOoMAAAGADUADAAFCUEVnVEAMQEFaAwAAAcASABpDAAABgA1AGsMAAAFACYAagwAAAIAMgDqDAAABgA1AC4ABAp/RAACDAAJCWQjHgoADgMADAAJCWQjHgoADgMAAAA=.Tahine:BAABLgAECn8UAAIdAAcJABHrFgA3AQdoDAAABABAAGkMAAAEACwAawwAAAQAKABqDAAAAQA3AGwMAAABABwA6gwAAAQAQABuDAAAAgASAB0ABwkAEesWADcBB2gMAAAEAEAAaQwAAAQALABrDAAABAAoAGoMAAABADcAbAwAAAEAHADqDAAABABAAG4MAAACABIAAAA=.Tans:BAAALgADCgkJCwAAAA==.',
Ti='Tiktoks:BAAALgAECgEJAQABLgAFFAQJDgAUAL4QAA==.Timetwoflame:BAABLgAECn8fAAMkAAgJ5RH2DgDKAQhoDAAABwA/AGkMAAAHAEUAawwAAAYAQgBqDAAAAgATAGwMAAABABwAbQwAAAEAIgDqDAAABAAyAG4MAAADACEAJAAICeUR9g4AygEIaAwAAAYAPwBpDAAABgBFAGsMAAAFAEIAagwAAAEAEwBsDAAAAQAcAG0MAAABACIA6gwAAAQAMgBuDAAAAwAhABUABAm6BzYYAH4ABGgMAAABAA0AaQwAAAEAEABrDAAAAQAdAGoMAAABAAUAAAA=.',
Tn='Tnarg:BAAALgADCgIJAgAAAA==.',
To='Tokki:BAAALgAECgYJCwAAAA==.',
Tr='Trekvis:BAAALgADCgcJDgAAAA==.',
Tu='Tugboat:BAAALgADCgIJAgAAAA==.',
Tw='Twoæ:BAAALgAECgEJAQAAAA==.',
['Tû']='Tûâny:BAAALgAECgUJBQAAAA==.',
Up='Upphoria:BAABLgAECn8cAAMUAAgJ6AooMAA3AQhoDAAABQArAGkMAAAGADAAawwAAAQABABqDAAAAwAOAGwMAAACAAwAbQwAAAEAJgDqDAAABgApAG4MAAABABIAFAAICegKKDAANwEIaAwAAAQAKwBpDAAABQAwAGsMAAAEAAQAagwAAAMADgBsDAAAAgAMAG0MAAABACYA6gwAAAYAKQBuDAAAAQASAAYAAgk+AzGFACIAAmgMAAABAAQAaQwAAAEADAAAAA==.',
Ur='Urkel:BAAALgAECgEJAQAAAA==.',
Ut='Uthomage:BAAALgAECgMJAwAAAA==.',
Va='Vashi:BAAALgADCgcJBwAAAA==.',
Vi='Viccan:BAABLgAECn8lAAMiAAkJHAeWEgAGAQloDAAABgAeAGkMAAAFABMAawwAAAUAEABqDAAAAwAIAGwMAAAFAAkAbQwAAAMABwDqDAAABgAbAG4MAAADAA8AbwwAAAEAEgAiAAkJ/AaWEgAGAQloDAAABgAeAGkMAAAFABMAawwAAAUAEABqDAAAAwAIAGwMAAAEAAkAbQwAAAIABADqDAAABgAbAG4MAAACAA8AbwwAAAEAEgAaAAMJKgKBEAFDAANsDAAAAQAGAG0MAAABAAcAbgwAAAEAAwAAAA==.',
Wa='Walkingtanko:BAAALgADCgIJAgAAAA==.Wavés:BAAALgADCgIJAgAAAA==.',
We='Wef:BAAALgADCgcJBwAAAA==.',
Wi='Wildwood:BAAALgADCgMJAwAAAA==.Willowleaf:BAAALgAECgEJAQABLgAFFAMJAwAYAAAAAA==.',
Wo='Wolffie:BAAALgAECggJEQAAAA==.',
Wu='Wushuu:BAAALgAECgUJCgABLgAFFAUJDgAKAHILAA==.',
Xa='Xampu:BAAALgADCgYJBwAAAA==.',
Xe='Xernaeus:BAAALgADCgQJBAAAAA==.',
Ya='Yahwëh:BAAALgAECgMJBAAAAA==.',
Yo='Yodason:BAAALgADCgQJBQAAAA==.',
Yu='Yuukï:BAABLgAECn8wAAMLAAkJGR1MCQCbAgloDAAACABbAGkMAAAGAFUAawwAAAcAUQBqDAAABABGAGwMAAAGAEoAbQwAAAQAPgDqDAAABwBbAG4MAAAEAFEAbwwAAAIAGwALAAkJGR1MCQCbAgloDAAACABbAGkMAAAGAFUAawwAAAYAUQBqDAAABABGAGwMAAAFAEoAbQwAAAMAPgDqDAAABwBbAG4MAAAEAFEAbwwAAAEAGwAbAAQJCAccdgB8AARrDAAAAQAHAGwMAAABAA0AbQwAAAEAEABvDAAAAQAiAAAA.',
Za='Zaelyse:BAAALgAFFAMJAwAAAA==.Zaton:BAABLgAECn8ZAAIKAAgJLxHucwB3AQhoDAAABAAsAGkMAAAEAEEAawwAAAQAMQBqDAAABABMAGwMAAACAA8AbQwAAAEANQDqDAAABAAxAG4MAAACABwACgAICS8R7nMAdwEIaAwAAAQALABpDAAABABBAGsMAAAEADEAagwAAAQATABsDAAAAgAPAG0MAAABADUA6gwAAAQAMQBuDAAAAgAcAAAA.',
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
