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

local lookup = {'Hunter-Marksmanship','Hunter-BeastMastery','Hunter-Survival','Rogue-Subtlety','DemonHunter-Devourer','Priest-Shadow','Warrior-Protection','DeathKnight-Frost','DeathKnight-Blood','Mage-Frost','Monk-Windwalker','DeathKnight-Unholy','Druid-Restoration','Druid-Balance','Shaman-Elemental','Shaman-Restoration','Warrior-Fury','Paladin-Retribution','Priest-Discipline','Priest-Holy','Evoker-Devastation','Evoker-Augmentation','Paladin-Holy','Unknown-Unknown','Warrior-Arms','Warlock-Demonology','Monk-Mistweaver','Monk-Brewmaster','Shaman-Enhancement','Rogue-Assassination','Rogue-Outlaw','Paladin-Protection','Warlock-Destruction','Warlock-Affliction','Evoker-Preservation',}
local provider = {region='US',realm='Auchindoun',name='US',type='daily',zone=46,date='2026-05-26',data={Ad='Adnerb:BAABLgAECn8VAAQBAAgJORIvGADVAAhoDAAABwBNAGkMAAADADAAawwAAAMAMQBqDAAAAgAzAGwMAAABACQAbQwAAAEAGADqDAAAAwBIAG4MAAABABAAAQAGCQMTLxgA1QAGaAwAAAcATQBpDAAAAgAqAGsMAAABACUAbAwAAAEAJABtDAAAAQAYAOoMAAADAEgAAgAECeoOL7cApQAEaQwAAAEAMABrDAAAAQAxAGoMAAABADMAbgwAAAEAEAADAAIJkQeDWQA1AAJrDAAAAQATAGoMAAABABMAAS4ABRQFCQcABAAlEQA=.',
Ah='Ahriman:BAABLgAECn8XAAIFAAYJLw64kgDYAAZoDAAABgA1AGkMAAAFACYAawwAAAQAJQBqDAAAAwAvAGwMAAACACIA6gwAAAMAEQAFAAYJLw64kgDYAAZoDAAABgA1AGkMAAAFACYAawwAAAQAJQBqDAAAAwAvAGwMAAACACIA6gwAAAMAEQAAAA==.',
Al='Alystra:BAABLgAECn8ZAAIGAAgJRQYMPAABAQhoDAAABQAQAGkMAAAEABYAawwAAAQAEgBqDAAAAwAeAGwMAAADABgAbQwAAAEADADqDAAABAANAG4MAAABAAMABgAICUUGDDwAAQEIaAwAAAUAEABpDAAABAAWAGsMAAAEABIAagwAAAMAHgBsDAAAAwAYAG0MAAABAAwA6gwAAAQADQBuDAAAAQADAAAA.',
An='Anjedin:BAAALgAECgYJEAAAAA==.',
Ao='Aoki:BAABLgAECn8kAAICAAgJJSEJGQBtAghoDAAABgBfAGkMAAAGAF4AawwAAAUATwBqDAAABgBgAGwMAAAEAF0AbQwAAAEANgDqDAAAAwBVAG4MAAAFAFoAAgAICSUhCRkAbQIIaAwAAAYAXwBpDAAABgBeAGsMAAAFAE8AagwAAAYAYABsDAAABABdAG0MAAABADYA6gwAAAMAVQBuDAAABQBaAAAA.',
Ar='Archdemon:BAABLgAECn8oAAIHAAkJtBimCwAWAgloDAAABwA7AGkMAAAFAEkAawwAAAUASgBqDAAAAwAxAGwMAAAFADYAbQwAAAMAMQDqDAAABwBCAG4MAAADAEMAbwwAAAIAPQAHAAkJtBimCwAWAgloDAAABwA7AGkMAAAFAEkAawwAAAUASgBqDAAAAwAxAGwMAAAFADYAbQwAAAMAMQDqDAAABwBCAG4MAAADAEMAbwwAAAIAPQAAAA==.Argonos:BAAALgAECgcJDQAAAA==.Arielias:BAABLgAECn8WAAMIAAkJAhlRBgANAgloDAAABABZAGkMAAAFAE8AawwAAAUAQgBqDAAAAQAkAGwMAAACAD0AbQwAAAEANADqDAAAAgBUAG4MAAABAEAAbwwAAAEADQAIAAcJ9RpRBgANAgdoDAAAAwBZAGkMAAAEAE8AawwAAAQAPwBsDAAAAQAxAG0MAAABADQA6gwAAAIAVABuDAAAAQBAAAkABgnME74gACcBBmgMAAABADYAaQwAAAEAOABrDAAAAQBCAGoMAAABACQAbAwAAAEAPQBvDAAAAQANAAEuAAUUBQkHAAQAJREA.Arkanoas:BAACLgAFFH8OAAIKAAUJcgsyVwAhAQVoDAAABAA3AGkMAAADAB8AawwAAAMAFgBqDAAAAQAFAOoMAAADAAcACgAFCXILMlcAIQEFaAwAAAQANwBpDAAAAwAfAGsMAAADABYAagwAAAEABQDqDAAAAwAHAC4ABAp/KwACCgAJCbYWDDgAlAIACgAJCbYWDDgAlAIAAAA=.',
As='Ashatal:BAAALgADCgEJAQAAAA==.Ashphantom:BAAALgAECgIJAgAAAA==.',
Ba='Bagelbite:BAAALgADCgUJBQAAAA==.Banshee:BAAALgAECgYJDAABLgAFFAUJBwAEACURAA==.Battahelin:BAAALgAECgQJBgAAAA==.Bazoo:BAAALgAECgEJAQAAAA==.',
Be='Bearmanowl:BAAALgAECgYJBwAAAA==.Bellator:BAAALgAECgMJBAAAAA==.',
Bi='Bigchungus:BAABLgAECn8dAAILAAYJ/AjISwCyAAZoDAAABgAgAGkMAAAGABEAawwAAAYAFgBqDAAABAASAGwMAAADABEA6gwAAAQAGQALAAYJ/AjISwCyAAZoDAAABgAgAGkMAAAGABEAawwAAAYAFgBqDAAABAASAGwMAAADABEA6gwAAAQAGQAAAA==.',
Bl='Blart:BAAALgAECgUJBwAAAA==.Blended:BAAALgAECgEJAQAAAA==.Bloody:BAAALgAFFAEJAQAAAA==.',
Br='Breathplay:BAABLgAECn8YAAIMAAkJbRqWPQBBAgloDAAABABQAGkMAAAEAEoAawwAAAQAOwBqDAAAAgA6AGwMAAACAEYAbQwAAAIAQQDqDAAAAwBLAG4MAAACAEQAbwwAAAEALwAMAAkJbRqWPQBBAgloDAAABABQAGkMAAAEAEoAawwAAAQAOwBqDAAAAgA6AGwMAAACAEYAbQwAAAIAQQDqDAAAAwBLAG4MAAACAEQAbwwAAAEALwAAAA==.',
['Bà']='Bàyne:BAABLgAECn8yAAINAAkJUBM2KwDjAQloDAAABwAuAGkMAAAHAEcAawwAAAcAPgBqDAAABgAxAGwMAAAGAEMAbQwAAAQAIwDqDAAABwBEAG4MAAAEABwAbwwAAAIADgANAAkJUBM2KwDjAQloDAAABwAuAGkMAAAHAEcAawwAAAcAPgBqDAAABgAxAGwMAAAGAEMAbQwAAAQAIwDqDAAABwBEAG4MAAAEABwAbwwAAAIADgAAAA==.',
Ca='Caroquintero:BAABLgAECn8fAAIKAAYJcgM65wC0AAZoDAAABgADAGkMAAAHABAAawwAAAYACABqDAAABAALAGwMAAAEAAkA6gwAAAQABgAKAAYJcgM65wC0AAZoDAAABgADAGkMAAAHABAAawwAAAYACABqDAAABAALAGwMAAAEAAkA6gwAAAQABgAAAA==.',
Ch='Charliemen:BAAALgAECgQJBAAAAA==.Chilli:BAAALgADCgEJAQAAAA==.Chubtart:BAACLgAFFH8IAAIOAAMJKxyRIAD/AANoDAAABABRAGkMAAADADIA6gwAAAEAVAAOAAMJKxyRIAD/AANoDAAABABRAGkMAAADADIA6gwAAAEAVAAuAAQKfzQAAg4ACQnRIz0IABIDAA4ACQnRIz0IABIDAAAA.Churrasco:BAAALgAECgQJCAAAAA==.',
Cl='Clayton:BAAALgADCgcJBAAAAA==.',
Co='Cojeculos:BAAALgAECgQJBwAAAA==.',
Cu='Cunumi:BAAALgAECgMJBAAAAA==.',
Da='Daddy:BAABLgAECn81AAMPAAkJZBViGwDjAQloDAAACABKAGkMAAAHADEAawwAAAcAMgBqDAAACAAmAGwMAAAGAC0AbQwAAAMAOwDqDAAACQA3AG4MAAAEAFMAbwwAAAEAEwAPAAkJZBViGwDjAQloDAAABQBKAGkMAAAEADEAawwAAAQAMgBqDAAABQAmAGwMAAAEAC0AbQwAAAMAOwDqDAAABAA3AG4MAAAEAFMAbwwAAAEAEwAQAAYJKw0tZQD/AAZoDAAAAwAmAGkMAAADABcAawwAAAMAGwBqDAAAAwAUAGwMAAACADEA6gwAAAUAKgAAAA==.Daizenat:BAAALgADCgIJAgAAAA==.Danehar:BAAALgAECgEJAQAAAA==.Darthforum:BAAALgADCgMJAwAAAA==.',
Dc='Dcone:BAAALgADCgYJBgAAAA==.',
De='Deadkey:BAAALgADCgEJAQAAAA==.Deathborne:BAAALgAECgUJCQAAAA==.Deathshreik:BAAALgADCgMJAwAAAA==.Deathslam:BAACLgAFFH8JAAIMAAQJRQc2ZQAHAQRoDAAAAwAdAGkMAAACABAAawwAAAIAEADqDAAAAgALAAwABAlFBzZlAAcBBGgMAAADAB0AaQwAAAIAEABrDAAAAgAQAOoMAAACAAsALgAECn8kAAIMAAkJbRmLJgBOAgAMAAkJbRmLJgBOAgAAAA==.',
Dr='Droston:BAAALgADCgQJBAAAAA==.',
Du='Durötan:BAABLgAECn8ZAAQCAAkJUhAbNQDlAQloDAAAAwAuAGkMAAAEAEIAawwAAAQAOABqDAAAAwAfAGwMAAACADQAbQwAAAIAFwDqDAAABQArAG4MAAABABIAbwwAAAEAGQACAAkJUhAbNQDlAQloDAAAAgAuAGkMAAADAEIAawwAAAIAOABqDAAAAwAfAGwMAAABADQAbQwAAAEAFwDqDAAABAArAG4MAAABABIAbwwAAAEAGQABAAUJRAoAVgDxAAVoDAAAAQAeAGsMAAACACgAbAwAAAEAEgBtDAAAAQAJAOoMAAABACAAAwABCb8KmFYAOgABaQwAAAEAGwABLgAFFAgJHAARAIwdAA==.Dutchess:BAABLgAECn8eAAISAAgJQBmBSgDQAQhoDAAABQBFAGkMAAAFAFIAawwAAAQASABqDAAABAA6AGwMAAAFAFQAbQwAAAIAQwDqDAAABAA7AG4MAAABABEAEgAICUAZgUoA0AEIaAwAAAUARQBpDAAABQBSAGsMAAAEAEgAagwAAAQAOgBsDAAABQBUAG0MAAACAEMA6gwAAAQAOwBuDAAAAQARAAAA.',
Dy='Dylan:BAACLgAFFH8ZAAIKAAUJayMHJQCaAQVoDAAABgBfAGkMAAAHAGEAawwAAAUAVABqDAAAAgBWAOoMAAAFAFUACgAFCWsjByUAmgEFaAwAAAYAXwBpDAAABwBhAGsMAAAFAFQAagwAAAIAVgDqDAAABQBVAC4ABAp/LwACCgAJCWolBAQAYAMACgAJCWolBAQAYAMAAAA=.Dylanj:BAAALgAECgQJBAABLgAFFAUJGQAKAGsjAQ==.',
Ec='Echevalier:BAAALgAECgQJBQAAAA==.Echoes:BAAALgADCgQJBAAAAA==.',
Eg='Egonspengler:BAAALgADCgQJBAAAAA==.',
El='Elayia:BAAALgADCgEJAQAAAA==.Elowen:BAAALgAFFAIJBAAAAQ==.',
En='Enhae:BAAALgAECgEJAQAAAA==.',
Er='Eresiine:BAAALgAECgcJDgAAAA==.Eríngo:BAAALgAFFAEJAQAAAA==.',
Es='Esna:BAAALgADCgUJCQAAAA==.',
Fi='Filomena:BAAALgADCgUJBgAAAA==.Firnin:BAAALgAECgYJEAAAAA==.',
Fl='Floise:BAACLgAFFH8RAAMTAAUJ6hQmFQCDAQVoDAAABQAuAGkMAAAEADsAawwAAAMASgBqDAAAAQAsAOoMAAAEACkAEwAFCbYTJhUAgwEFaAwAAAIALgBpDAAAAwAsAGsMAAADAEoAagwAAAEALADqDAAABAApABQAAglUE1kNAJMAAmgMAAADACcAaQwAAAEAOwAuAAQKfx4ABBQACQn7GXcMAIwCABQACQlAGXcMAIwCABMABwkQFRA4AAYBAAYAAQlcEpVtADsAAAAA.Flounder:BAAALgAECgEJAwAAAA==.',
Fo='Foamtotem:BAAALgADCgEJAQAAAA==.Forumsoldier:BAACLgAFFH8GAAIKAAQJagfNWQAaAQRoDAAAAgAdAGkMAAACABUAawwAAAEACADqDAAAAQAQAAoABAlqB81ZABoBBGgMAAACAB0AaQwAAAIAFQBrDAAAAQAIAOoMAAABABAALgAECn8jAAIKAAgJlhcoVAA8AgAKAAgJlhcoVAA8AgAAAA==.',
Fr='Frozenscorch:BAAALgAECggJEgAAAA==.',
Ft='Fteve:BAAALgAECgUJCQAAAA==.',
['Fä']='Fälkor:BAABLgAECn8rAAMVAAgJrQZ7EgDIAAhoDAAABwAdAGkMAAAGABgAawwAAAUAEwBqDAAABgAZAGwMAAAGABMAbQwAAAQACgDqDAAABgAIAG4MAAADAAcAFgAICa0GMkIAAgEIaAwAAAUAHQBpDAAABAAYAGsMAAAEABMAagwAAAUAFwBsDAAABQATAG0MAAAEAAoA6gwAAAYACABuDAAAAgAHABUABgkkBnsSAMgABmgMAAACABMAaQwAAAIAFABrDAAAAQAPAGoMAAABABkAbAwAAAEADwBuDAAAAQAHAAAA.',
['Fö']='Föx:BAAALgAECgcJDQAAAA==.',
Gi='Gigamoo:BAAALgAECgQJBgAAAA==.',
Gl='Glorfindel:BAAALgAFFAEJAgABLgAFFAIJBgAMACgKAA==.Glys:BAAALgAECgUJCgAAAA==.',
Go='Gogocow:BAAALgAECgEJAQAAAA==.Gooba:BAAALgAECgEJAQAAAA==.Goommar:BAABLgAECn8UAAIRAAcJMALxawCGAAdoDAAAAwAEAGkMAAADAAYAawwAAAMABwBqDAAABAAIAGwMAAACAAgA6gwAAAQAAwBuDAAAAQACABEABwkwAvFrAIYAB2gMAAADAAQAaQwAAAMABgBrDAAAAwAHAGoMAAAEAAgAbAwAAAIACADqDAAABAADAG4MAAABAAIAAAA=.Gorim:BAAALgAECgIJAgAAAA==.',
Gr='Grandgoose:BAAALgADCgIJAgAAAA==.Grandpa:BAAALgAECgcJCAAAAA==.Granuju:BAAALgADCgUJBgAAAA==.',
Gu='Gunnhildr:BAAALgADCgkJCQAAAA==.',
Ha='Hanasanai:BAAALgADCgMJBAAAAA==.Handil:BAABLgAECn8cAAIXAAYJTCMPFQBGAgZoDAAABQBZAGkMAAAFAFoAawwAAAUAXgBqDAAABQBcAGwMAAACAFEA6gwAAAYAXQAXAAYJTCMPFQBGAgZoDAAABQBZAGkMAAAFAFoAawwAAAUAXgBqDAAABQBcAGwMAAACAFEA6gwAAAYAXQAAAA==.',
He='Helpingyou:BAABLgAECn8bAAIGAAkJ/wiwJQB9AQloDAAAAwAcAGkMAAADABcAawwAAAIAFwBqDAAAAwAbAGwMAAAEABoAbQwAAAQAEwDqDAAAAwAdAG4MAAAEAA8AbwwAAAEAEQAGAAkJ/wiwJQB9AQloDAAAAwAcAGkMAAADABcAawwAAAIAFwBqDAAAAwAbAGwMAAAEABoAbQwAAAQAEwDqDAAAAwAdAG4MAAAEAA8AbwwAAAEAEQAAAA==.',
Ho='Holybell:BAAALgAECgIJAgAAAA==.Hoptyj:BAAALgADCgIJAgAAAA==.',
['Hë']='Hënnessy:BAAALgADCgMJAwAAAA==.Hënnëssy:BAABLgAECn8dAAIXAAcJsRKvLQCJAQdoDAAABABYAGkMAAAEAB0AawwAAAQALgBqDAAABQA3AGwMAAAEAC0AbQwAAAIABADqDAAABgBAABcABwmxEq8tAIkBB2gMAAAEAFgAaQwAAAQAHQBrDAAABAAuAGoMAAAFADcAbAwAAAQALQBtDAAAAgAEAOoMAAAGAEAAAAA=.',
Im='Impaladin:BAAALgAECgMJAwAAAA==.',
Io='Iolanthe:BAAALgADCgQJBAAAAA==.',
Iz='Izeroeasily:BAAALgAECgMJAwABLgAECgUJBgAYAAAAAA==.Izerohealz:BAAALgADCgQJBAAAAA==.Izzi:BAAALgAECgYJEQAAAA==.Izzia:BAABLgAECn8hAAINAAgJQxlbGwBOAghoDAAABgBSAGkMAAAEAFQAawwAAAYAPwBqDAAAAgBGAGwMAAADAEgAbQwAAAMAIwDqDAAABwBRAG4MAAACABwADQAICUMZWxsATgIIaAwAAAYAUgBpDAAABABUAGsMAAAGAD8AagwAAAIARgBsDAAAAwBIAG0MAAADACMA6gwAAAcAUQBuDAAAAgAcAAAA.',
Ja='Jabbathabutt:BAAALgAECgYJCQAAAA==.Jaceret:BAAALgAECgEJAQAAAA==.Jasia:BAAALgADCgYJCAAAAA==.',
Jo='Joyboy:BAAALgAECgEJAQAAAA==.',
Ju='Justfn:BAAALgADCgUJBwAAAA==.',
Ka='Kamitos:BAABLgAECn8sAAMTAAkJpA8lGgDYAQloDAAACAAlAGkMAAAIADUAawwAAAQAOABqDAAABgAnAGwMAAAGACgAbQwAAAEAEgDqDAAABgA5AG4MAAAEACEAbwwAAAEAFgATAAkJpA8lGgDYAQloDAAABgAlAGkMAAAHADUAawwAAAMAOABqDAAABAAnAGwMAAAEACgAbQwAAAEAEgDqDAAABgA5AG4MAAAEACEAbwwAAAEAFgAGAAUJyAhmRADZAAVoDAAAAgAiAGkMAAABABYAawwAAAEAGwBqDAAAAgAbAGwMAAACAAQAAAA=.Kaye:BAAALgAECgEJAQAAAA==.Kayewyn:BAABLgAECn8pAAINAAgJGhb/JQACAghoDAAACABWAGkMAAAIAD0AawwAAAgAUgBqDAAABQAwAGwMAAAEADwAbQwAAAEADwDqDAAABABDAG4MAAADAB0ADQAICRoW/yUAAgIIaAwAAAgAVgBpDAAACAA9AGsMAAAIAFIAagwAAAUAMABsDAAABAA8AG0MAAABAA8A6gwAAAQAQwBuDAAAAwAdAAAA.',
Kb='Kbdh:BAAALgAECgYJCwABLgAFFAIJAwAYAAAAAA==.Kbdruid:BAAALgAFFAEJAQABLgAFFAIJAwAYAAAAAA==.Kbhunter:BAAALgAECgUJCAABLgAFFAIJAwAYAAAAAA==.Kbmage:BAAALgADCgQJBAABLgAFFAIJAwAYAAAAAA==.Kbmonk:BAAALgAFFAIJAwAAAA==.Kbpaladin:BAAALgAECgYJBgABLgAFFAIJAwAYAAAAAA==.',
Ke='Keiji:BAAALgAECgYJDgAAAA==.Kelemvor:BAAALgAECgUJBQAAAA==.',
Kl='Klipnor:BAAALgAECgQJCAAAAA==.',
Kr='Krocketeer:BAAALgAECgYJCQAAAA==.',
Ky='Kyndel:BAAALgAECgYJCgABLgAFFAUJFwANAHUbAA==.Kynn:BAACLgAFFH8XAAINAAUJdRvzEACwAQVoDAAABwBSAGkMAAAGAFEAawwAAAUAUABqDAAAAgAxAOoMAAADADgADQAFCXUb8xAAsAEFaAwAAAcAUgBpDAAABgBRAGsMAAAFAFAAagwAAAIAMQDqDAAAAwA4AC4ABAp/NwACDQAJCZQi8wEAgQMADQAJCZQi8wEAgQMAAAA=.',
['Kè']='Kèlemvore:BAABLgAECn8uAAISAAgJkRLEXgCcAQhoDAAABwBBAGkMAAAHAEUAawwAAAcAPgBqDAAABgA2AGwMAAAHACEAbQwAAAIADwDqDAAABwA6AG4MAAADABsAEgAICZESxF4AnAEIaAwAAAcAQQBpDAAABwBFAGsMAAAHAD4AagwAAAYANgBsDAAABwAhAG0MAAACAA8A6gwAAAcAOgBuDAAAAwAbAAAA.',
Le='Leafittome:BAAALgADCgEJAQAAAA==.',
Ly='Lykos:BAAALgAECgYJDgAAAA==.',
Ma='Mammal:BAAALgAECgQJBAABLgAECggJGgAPAHQcAA==.',
Me='Medxchaos:BAAALgAECgQJBwABLgAFFAUJEQATAOoUAA==.Meowy:BAAALgAECgEJAQAAAA==.Mepha:BAABLgAECn8rAAMZAAkJlyCUBwBeAgloDAAABwBYAGkMAAAHAFsAawwAAAcAWwBqDAAABQBMAGwMAAAEAEkAbQwAAAMAPQDqDAAABgBhAG4MAAADAEkAbwwAAAEAWgARAAcJ+B/yGACDAgdoDAAABABYAGkMAAAEAFsAawwAAAQAWwBqDAAAAgBMAGwMAAACAEUAbQwAAAEAMwDqDAAAAwBhABkACQleHZQHAF4CCWgMAAADAEgAaQwAAAMAUgBrDAAAAwBQAGoMAAADABcAbAwAAAIASQBtDAAAAgA9AOoMAAADAEQAbgwAAAMASQBvDAAAAQBaAAAA.',
Mi='Mightymost:BAAALgAECgYJCwAAAA==.',
Mu='Mudd:BAABLgAECn8jAAMZAAgJkh/TCABBAghoDAAABQBJAGkMAAAFAFcAawwAAAMAUgBqDAAAAwA7AGwMAAAEAFwAbQwAAAIASgDqDAAACABbAG4MAAAFAEAAGQAICZIf0wgAQQIIaAwAAAUASQBpDAAABQBXAGsMAAADAFIAagwAAAMAOwBsDAAABABcAG0MAAACAEoA6gwAAAUAWwBuDAAABQBAABEAAQlwEPGKADYAAeoMAAADACoAAAA=.Mudds:BAABLgAECn8cAAILAAgJoSB7EAB5AghoDAAABgBVAGkMAAAFAFoAawwAAAUAWABqDAAAAgBMAGwMAAACAFQAbQwAAAIAUgDqDAAABQBXAG4MAAABAEEACwAICaEgexAAeQIIaAwAAAYAVQBpDAAABQBaAGsMAAAFAFgAagwAAAIATABsDAAAAgBUAG0MAAACAFIA6gwAAAUAVwBuDAAAAQBBAAEuAAQKCAkjABkAkh8A.',
Na='Naelia:BAABLgAECn8XAAIaAAcJVQ/9aABbAQdoDAAABAAtAGkMAAAEACQAawwAAAMAIQBqDAAAAwAYAGwMAAAEACUAbQwAAAEAGgDqDAAABAA4ABoABwlVD/1oAFsBB2gMAAAEAC0AaQwAAAQAJABrDAAAAwAhAGoMAAADABgAbAwAAAQAJQBtDAAAAQAaAOoMAAAEADgAAS4ABRQFCRYADABBFQA=.Nakira:BAAALgAECgMJAwAAAA==.Nami:BAAALgAECgUJBQAAAA==.',
Ne='Nenekirimaru:BAAALgADCgIJAgAAAA==.',
Ni='Nicodemus:BAAALgADCgIJAgAAAA==.Nightrush:BAABLgAECn8oAAMCAAgJIiXiGwBcAghoDAAABwBjAGkMAAAHAGIAawwAAAYAYQBqDAAABQBdAGwMAAADAFEAbQwAAAMAXQDqDAAABgBiAG4MAAADAGAAAgAGCQQm4hsAXAIGaAwAAAEAYwBpDAAAAQBiAGsMAAACAGEAbQwAAAMAXQDqDAAAAQBiAG4MAAADAGAAAQAGCbQhMAwAgQEGaAwAAAYAWwBpDAAABgBXAGsMAAAEAFQAagwAAAUAXQBsDAAAAwBRAOoMAAAFAFYAAAA=.',
No='Noodles:BAABLgAECn8dAAIFAAcJvhY4bAAsAQdoDAAABgBGAGkMAAAGADkAawwAAAYANABqDAAABQBMAGwMAAADACwA6gwAAAIAPwBuDAAAAQA8AAUABwm+FjhsACwBB2gMAAAGAEYAaQwAAAYAOQBrDAAABgA0AGoMAAAFAEwAbAwAAAMALADqDAAAAgA/AG4MAAABADwAAAA=.Norbit:BAAALgAECgEJAQAAAA==.',
Oe='Oesteroth:BAABLgAECn8UAAINAAYJbgVpeAC0AAZoDAAABAAYAGkMAAAEAAkAawwAAAQACQBqDAAAAwAUAGwMAAABAAgA6gwAAAQACgANAAYJbgVpeAC0AAZoDAAABAAYAGkMAAAEAAkAawwAAAQACQBqDAAAAwAUAGwMAAABAAgA6gwAAAQACgAAAA==.',
Ok='Okomo:BAAALgAECgUJBgAAAA==.',
Pa='Palaben:BAABLgAECn8bAAMXAAgJdRFlOgA/AQhoDAAABAAyAGkMAAAEAFsAawwAAAQANQBqDAAABAAiAGwMAAADACYAbQwAAAIAFgDqDAAAAwA9AG4MAAADAAMAFwAHCawSZToAPwEHaAwAAAQAMgBpDAAABABbAGsMAAAEADUAagwAAAMAIgBsDAAAAgAmAOoMAAADAD0AbgwAAAEAAwASAAQJXQxwAgGRAARqDAAAAQAGAGwMAAABABkAbQwAAAIAGgBuDAAAAgAqAAAA.Pantsu:BAABLgAECn9BAAQMAAgJuCXcEgC/AghoDAAACgBiAGkMAAAKAGMAawwAAAkAYgBqDAAACABdAGwMAAAHAF8AbQwAAAYAXQDqDAAACQBeAG4MAAAGAGAADAAICYEl3BIAvwIIaAwAAAgAYgBpDAAACABjAGsMAAAHAGIAagwAAAYAXQBsDAAABQBfAG0MAAAEAFkA6gwAAAcAXgBuDAAABABgAAkACAnYIC8HAIwCCGgMAAABAEsAaQwAAAEAVABrDAAAAQBLAGoMAAABAFoAbAwAAAEAUwBtDAAAAQBdAOoMAAABAFgAbgwAAAEAVwAIAAgJ/x9gBQAtAghoDAAAAQBUAGkMAAABAFwAawwAAAEAWwBqDAAAAQA/AGwMAAABAFoAbQwAAAEARQDqDAAAAQBIAG4MAAABAEcAAAA=.Pateaviejas:BAAALgAECgMJAwAAAA==.Pawnchy:BAAALgAECgUJCQAAAA==.',
Pe='Peepaw:BAABLgAECn8ZAAIbAAYJTgV1YgCjAAZoDAAABQAOAGkMAAAGABMAawwAAAYAEABqDAAAAwATAGwMAAABAAUA6gwAAAQABgAbAAYJTgV1YgCjAAZoDAAABQAOAGkMAAAGABMAawwAAAYAEABqDAAAAwATAGwMAAABAAUA6gwAAAQABgAAAA==.Pennyz:BAAALgADCgYJBgAAAA==.',
Pi='Pitchwhite:BAABLgAECn8XAAIUAAYJHBFpRAAnAQZoDAAABQA7AGkMAAAEACMAawwAAAQAOwBqDAAABAAzAGwMAAABABIA6gwAAAUAJgAUAAYJHBFpRAAnAQZoDAAABQA7AGkMAAAEACMAawwAAAQAOwBqDAAABAAzAGwMAAABABIA6gwAAAUAJgAAAA==.Pixel:BAAALgADCgkJDQAAAA==.',
Pr='Proselyte:BAACLgAFFH8PAAILAAQJixgjDQA5AQRoDAAABQA7AGkMAAAFAEgAawwAAAIAMgDqDAAAAwBEAAsABAmLGCMNADkBBGgMAAAFADsAaQwAAAUASABrDAAAAgAyAOoMAAADAEQALgAECn8pAAILAAkJ3h/aBgDCAgALAAkJ3h/aBgDCAgAAAA==.',
Pu='Punchbear:BAAALgADCgYJBgAAAA==.Punchize:BAABLgAECn8rAAMcAAgJMCMZBgDDAghoDAAABwBiAGkMAAAIAFQAawwAAAgAVQBqDAAABQBgAGwMAAAEAFoAbQwAAAEAVQDqDAAABwBbAG4MAAADAF8AHAAICTAjGQYAwwIIaAwAAAcAYgBpDAAABwBUAGsMAAAHAFUAagwAAAUAYABsDAAABABaAG0MAAABAFUA6gwAAAcAWwBuDAAAAwBfABsAAgn0Ch2DAEkAAmkMAAABACAAawwAAAEAFwAAAA==.Punchlocks:BAAALgAECgEJAQAAAA==.',
Qu='Quirkchungus:BAAALgAECgYJDwAAAA==.',
Ra='Rakrak:BAAALgADCgEJAQAAAA==.Rani:BAAALgADCgUJBQAAAA==.Rathon:BAAALgAECgkJDQAAAA==.',
Re='Remote:BAAALgAECgQJBwAAAA==.',
Ri='Rianis:BAAALgADCgcJEAAAAA==.Rilea:BAAALgAECgYJEQAAAA==.Risenspirits:BAAALgAECgYJBgAAAA==.',
['Rä']='Räiyu:BAAALgADCgMJAwAAAA==.',
Sa='Sadgasm:BAABLgAECn8sAAIdAAkJGyDSAgDHAgloDAAABwBfAGkMAAAGAGEAawwAAAYATABqDAAABABbAGwMAAAFAEIAbQwAAAMARADqDAAACABVAG4MAAADAFUAbwwAAAIAUgAdAAkJGyDSAgDHAgloDAAABwBfAGkMAAAGAGEAawwAAAYATABqDAAABABbAGwMAAAFAEIAbQwAAAMARADqDAAACABVAG4MAAADAFUAbwwAAAIAUgAAAA==.Safeword:BAAALgAECgkJCwAAAA==.Sauron:BAAALgAECgUJCgAAAA==.',
Sc='Scrubuckett:BAAALgADCgYJBgAAAA==.',
Se='Sebrine:BAAALgAECgUJCwAAAA==.Seishan:BAACLgAFFH8HAAMEAAUJJRHoEQC6AAVoDAAAAgA/AGkMAAABAEIAawwAAAEAEABqDAAAAQArAOoMAAACABwABAAFCSUR6BEAugAFaAwAAAIAPwBpDAAAAQBCAGsMAAABABAAagwAAAEAKwDqDAAAAQAcAB4AAQmvCVAPAEkAAeoMAAABABgALgAECn8fAAQeAAcJkxsqBwD0AQAeAAYJ1R4qBwD0AQAEAAUJxhdMPQAyAQAfAAEJ+xcxHABDAAAAAA==.Seneca:BAAALgAECgEJBAAAAA==.',
Sh='Shadowslam:BAAALgAECgYJCAAAAA==.Shadowtalon:BAAALgADCgEJAQAAAA==.Shamandrea:BAAALgAFFAMJAwAAAA==.Shzam:BAAALgADCgYJDgAAAA==.',
Sl='Slam:BAAALgADCgMJBQAAAA==.Sleipner:BAABLgAECn8fAAIgAAkJAA6lFgBHAQloDAAABABTAGkMAAAEADQAawwAAAQAJgBqDAAABAAdAGwMAAAEABsAbQwAAAMAEgDqDAAABQAhAG4MAAACABMAbwwAAAEADAAgAAkJAA6lFgBHAQloDAAABABTAGkMAAAEADQAawwAAAQAJgBqDAAABAAdAGwMAAAEABsAbQwAAAMAEgDqDAAABQAhAG4MAAACABMAbwwAAAEADAAAAA==.',
Sm='Smiley:BAAALgADCgYJBgAAAA==.',
Sn='Sneeze:BAAALgADCgIJAgAAAA==.Snugglehex:BAAALgADCgEJAQAAAA==.',
So='Socktrout:BAABLgAECn8qAAQaAAkJnxcOPADZAQloDAAABgAzAGkMAAAFAEkAawwAAAQAQwBqDAAAAwAbAGwMAAAGACkAbQwAAAUAPwDqDAAABgBBAG4MAAAEAEsAbwwAAAMAKwAaAAgJfRYOPADZAQhoDAAABgAzAGkMAAAFAEkAawwAAAQAQwBsDAAAAgApAG0MAAACAD8A6gwAAAYAQQBuDAAABABLAG8MAAACABQAIQADCesKEkMAqQADagwAAAIAGwBsDAAABAAgAG0MAAADABYAIgACCS0RMy0ARQACagwAAAEABgBvDAAAAQArAAAA.Softgrizzly:BAAALgADCgMJAwAAAA==.Solidgold:BAACLgAFFH8cAAMRAAgJjB2AAAChAghoDAAABgBeAGkMAAAFAFMAawwAAAQAWgBqDAAABABaAGwMAAACADAAbQwAAAEAFQDqDAAABQBfAG4MAAABAF8AEQAICYwdgAAAoQIIaAwAAAYAXgBpDAAABQBTAGsMAAAEAFoAagwAAAQAWgBsDAAAAQAwAG0MAAABABUA6gwAAAUAXwBuDAAAAQBfABkAAQmgBroLAFMAAWwMAAABABAALgAECn8yAAMRAAgJfSXPBAD/AgARAAgJfSXPBAD/AgAZAAUJqCD8HAAIAQAAAA==.Solvane:BAAALgAECgMJAwABLgAFFAUJBwAEACURAA==.',
Sp='Spongeybob:BAAALgADCgEJAgAAAA==.',
Ss='Sscrubbucket:BAAALgAECgYJBgAAAA==.',
Su='Sunrise:BAAALgADCgkJEAAAAA==.',
Sy='Syllassa:BAAALgAECgkJAQAAAA==.Sylv:BAAALgAECgQJBAAAAA==.',
Ta='Taelia:BAACLgAFFH8WAAIMAAUJQRUlSQA0AQVoDAAABgBIAGkMAAAFADUAawwAAAQAJgBqDAAAAgAyAOoMAAAFADUADAAFCUEVJUkANAEFaAwAAAYASABpDAAABQA1AGsMAAAEACYAagwAAAIAMgDqDAAABQA1AC4ABAp/RAACDAAJCWQjDgkAEwMADAAJCWQjDgkAEwMAAAA=.Tahine:BAAALgAECgcJEwAAAA==.Tans:BAAALgADCgkJCwAAAA==.',
Ti='Tiktoks:BAAALgAECgEJAQABLgAFFAQJCgAUAOgHAA==.Timetwoflame:BAABLgAECn8fAAMjAAgJ5RFvDgDKAQhoDAAABwA/AGkMAAAHAEUAawwAAAYAQgBqDAAAAgATAGwMAAABABwAbQwAAAEAIgDqDAAABAAyAG4MAAADACEAIwAICeURbw4AygEIaAwAAAYAPwBpDAAABgBFAGsMAAAFAEIAagwAAAEAEwBsDAAAAQAcAG0MAAABACIA6gwAAAQAMgBuDAAAAwAhABUABAm6B10XAIAABGgMAAABAA0AaQwAAAEAEABrDAAAAQAdAGoMAAABAAUAAAA=.',
Tn='Tnarg:BAAALgADCgIJAgAAAA==.',
To='Tokki:BAAALgAECgYJCwAAAA==.',
Tr='Trekvis:BAAALgADCgcJDgAAAA==.',
Tu='Tugboat:BAAALgADCgIJAgAAAA==.',
Tw='Twoæ:BAAALgAECgEJAQAAAA==.',
['Tû']='Tûâny:BAAALgAECgUJBQAAAA==.',
Up='Upphoria:BAABLgAECn8bAAMUAAgJ6AqTLgA8AQhoDAAABQArAGkMAAAGADAAawwAAAQABABqDAAAAwAOAGwMAAACAAwAbQwAAAEAJgDqDAAABQApAG4MAAABABIAFAAICegKky4APAEIaAwAAAQAKwBpDAAABQAwAGsMAAAEAAQAagwAAAMADgBsDAAAAgAMAG0MAAABACYA6gwAAAUAKQBuDAAAAQASAAYAAgk+A0SAACMAAmgMAAABAAQAaQwAAAEADAAAAA==.',
Ur='Urkel:BAAALgAECgEJAQAAAA==.',
Ut='Uthomage:BAAALgAECgMJAwAAAA==.',
Va='Vashi:BAAALgADCgcJBwAAAA==.',
Vi='Viccan:BAABLgAECn8lAAMhAAkJHAd2EQALAQloDAAABgAeAGkMAAAFABMAawwAAAUAEABqDAAAAwAIAGwMAAAFAAkAbQwAAAMABwDqDAAABgAbAG4MAAADAA8AbwwAAAEAEgAhAAkJ/AZ2EQALAQloDAAABgAeAGkMAAAFABMAawwAAAUAEABqDAAAAwAIAGwMAAAEAAkAbQwAAAIABADqDAAABgAbAG4MAAACAA8AbwwAAAEAEgAaAAMJKgLbCAFDAANsDAAAAQAGAG0MAAABAAcAbgwAAAEAAwAAAA==.',
Wa='Walkingtanko:BAAALgADCgIJAgAAAA==.Wavés:BAAALgADCgIJAgAAAA==.',
We='Wef:BAAALgADCgcJBwAAAA==.',
Wi='Wildwood:BAAALgADCgMJAwAAAA==.Willowleaf:BAAALgAECgEJAQABLgAFFAMJAwAYAAAAAA==.',
Wo='Wolffie:BAAALgAECggJEQAAAA==.',
Wu='Wushuu:BAAALgAECgUJCgABLgAFFAUJDgAKAHILAA==.',
Xa='Xampu:BAAALgADCgYJBgAAAA==.',
Xe='Xernaeus:BAAALgADCgQJBAAAAA==.',
Ya='Yahwëh:BAAALgAECgMJBAAAAA==.',
Yo='Yodason:BAAALgADCgQJBQAAAA==.',
Yu='Yuukï:BAABLgAECn8wAAMLAAkJGR2KCACfAgloDAAACABbAGkMAAAGAFUAawwAAAcAUQBqDAAABABGAGwMAAAGAEoAbQwAAAQAPgDqDAAABwBbAG4MAAAEAFEAbwwAAAIAGwALAAkJGR2KCACfAgloDAAACABbAGkMAAAGAFUAawwAAAYAUQBqDAAABABGAGwMAAAFAEoAbQwAAAMAPgDqDAAABwBbAG4MAAAEAFEAbwwAAAEAGwAbAAQJCAeubgB8AARrDAAAAQAHAGwMAAABAA0AbQwAAAEAEABvDAAAAQAiAAAA.',
Za='Zaelyse:BAAALgAECgYJBgAAAA==.Zaton:BAABLgAECn8ZAAIKAAgJLxECbACNAQhoDAAABAAsAGkMAAAEAEEAawwAAAQAMQBqDAAABABMAGwMAAACAA8AbQwAAAEANQDqDAAABAAxAG4MAAACABwACgAICS8RAmwAjQEIaAwAAAQALABpDAAABABBAGsMAAAEADEAagwAAAQATABsDAAAAgAPAG0MAAABADUA6gwAAAQAMQBuDAAAAgAcAAAA.',
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
