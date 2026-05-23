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

local lookup = {'Hunter-Marksmanship','Hunter-BeastMastery','Hunter-Survival','Rogue-Subtlety','DemonHunter-Devourer','Priest-Shadow','Warrior-Protection','Mage-Frost','Monk-Windwalker','DeathKnight-Unholy','Druid-Restoration','Druid-Balance','Shaman-Elemental','Shaman-Restoration','Warrior-Fury','Paladin-Retribution','Priest-Discipline','Priest-Holy','Evoker-Devastation','Evoker-Augmentation','Paladin-Holy','Unknown-Unknown','Warrior-Arms','DeathKnight-Blood','DeathKnight-Frost','Monk-Mistweaver','Monk-Brewmaster','Shaman-Enhancement','Rogue-Assassination','Rogue-Outlaw','Paladin-Protection','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Evoker-Preservation',}
local provider = {region='US',realm='Auchindoun',name='US',type='daily',zone=46,date='2026-05-23',data={Ad='Adnerb:BAABLgAECn8VAAQBAAgJORJ+FwDVAAhoDAAABwBNAGkMAAADADAAawwAAAMAMQBqDAAAAgAzAGwMAAABACQAbQwAAAEAGADqDAAAAwBIAG4MAAABABAAAQAGCQMTfhcA1QAGaAwAAAcATQBpDAAAAgAqAGsMAAABACUAbAwAAAEAJABtDAAAAQAYAOoMAAADAEgAAgAECeoOE68AqAAEaQwAAAEAMABrDAAAAQAxAGoMAAABADMAbgwAAAEAEAADAAIJkQerVQA3AAJrDAAAAQATAGoMAAABABMAAS4ABRQFCQcABAAlEQA=.',
Ah='Ahriman:BAABLgAECn8XAAIFAAYJLw50jgDZAAZoDAAABgA1AGkMAAAFACYAawwAAAQAJQBqDAAAAwAvAGwMAAACACIA6gwAAAMAEQAFAAYJLw50jgDZAAZoDAAABgA1AGkMAAAFACYAawwAAAQAJQBqDAAAAwAvAGwMAAACACIA6gwAAAMAEQAAAA==.',
Al='Alystra:BAABLgAECn8ZAAIGAAgJRQbKOQADAQhoDAAABQAQAGkMAAAEABYAawwAAAQAEgBqDAAAAwAeAGwMAAADABgAbQwAAAEADADqDAAABAANAG4MAAABAAMABgAICUUGyjkAAwEIaAwAAAUAEABpDAAABAAWAGsMAAAEABIAagwAAAMAHgBsDAAAAwAYAG0MAAABAAwA6gwAAAQADQBuDAAAAQADAAAA.',
An='Anjedin:BAAALgAECgYJEAAAAA==.',
Ao='Aoki:BAABLgAECn8jAAICAAgJ6CCIGABqAghoDAAABgBfAGkMAAAGAF4AawwAAAUATwBqDAAABgBgAGwMAAAEAF0AbQwAAAEANgDqDAAAAwBVAG4MAAAEAFYAAgAICeggiBgAagIIaAwAAAYAXwBpDAAABgBeAGsMAAAFAE8AagwAAAYAYABsDAAABABdAG0MAAABADYA6gwAAAMAVQBuDAAABABWAAAA.',
Ar='Archdemon:BAABLgAECn8iAAIHAAkJOxgWDQDyAQloDAAABgA7AGkMAAAFAEkAawwAAAUASgBqDAAAAwAxAGwMAAAEACwAbQwAAAIAMQDqDAAABgBCAG4MAAACAEMAbwwAAAEAPQAHAAkJOxgWDQDyAQloDAAABgA7AGkMAAAFAEkAawwAAAUASgBqDAAAAwAxAGwMAAAEACwAbQwAAAIAMQDqDAAABgBCAG4MAAACAEMAbwwAAAEAPQAAAA==.Argonos:BAAALgAECgcJDQAAAA==.Arielias:BAAALgAFFAIJAgABLgAFFAUJBwAEACURAA==.Arkanoas:BAACLgAFFH8OAAIIAAUJcgsPUwAhAQVoDAAABAA3AGkMAAADAB8AawwAAAMAFgBqDAAAAQAFAOoMAAADAAcACAAFCXILD1MAIQEFaAwAAAQANwBpDAAAAwAfAGsMAAADABYAagwAAAEABQDqDAAAAwAHAC4ABAp/KwACCAAJCbYWDDgAlAIACAAJCbYWDDgAlAIAAAA=.',
As='Ashatal:BAAALgADCgEJAQAAAA==.Ashphantom:BAAALgAECgIJAgAAAA==.',
Ba='Bagelbite:BAAALgADCgUJBQAAAA==.Banshee:BAAALgAECgYJDAABLgAFFAUJBwAEACURAA==.Battahelin:BAAALgAECgQJBgAAAA==.Bazoo:BAAALgAECgEJAQAAAA==.',
Be='Bearmanowl:BAAALgAECgYJBwAAAA==.Bellator:BAAALgAECgMJBAAAAA==.',
Bi='Bigchungus:BAABLgAECn8dAAIJAAYJ/Aj5SACyAAZoDAAABgAgAGkMAAAGABEAawwAAAYAFgBqDAAABAASAGwMAAADABEA6gwAAAQAGQAJAAYJ/Aj5SACyAAZoDAAABgAgAGkMAAAGABEAawwAAAYAFgBqDAAABAASAGwMAAADABEA6gwAAAQAGQAAAA==.',
Bl='Blart:BAAALgAECgUJBwAAAA==.Blended:BAAALgAECgEJAQAAAA==.Bloody:BAAALgAFFAEJAQAAAA==.',
Br='Breathplay:BAABLgAECn8YAAIKAAkJbRqWPQBBAgloDAAABABQAGkMAAAEAEoAawwAAAQAOwBqDAAAAgA6AGwMAAACAEYAbQwAAAIAQQDqDAAAAwBLAG4MAAACAEQAbwwAAAEALwAKAAkJbRqWPQBBAgloDAAABABQAGkMAAAEAEoAawwAAAQAOwBqDAAAAgA6AGwMAAACAEYAbQwAAAIAQQDqDAAAAwBLAG4MAAACAEQAbwwAAAEALwAAAA==.',
['Bà']='Bàyne:BAABLgAECn8yAAILAAkJUBPCKQDkAQloDAAABwAuAGkMAAAHAEcAawwAAAcAPgBqDAAABgAxAGwMAAAGAEMAbQwAAAQAIwDqDAAABwBEAG4MAAAEABwAbwwAAAIADgALAAkJUBPCKQDkAQloDAAABwAuAGkMAAAHAEcAawwAAAcAPgBqDAAABgAxAGwMAAAGAEMAbQwAAAQAIwDqDAAABwBEAG4MAAAEABwAbwwAAAIADgAAAA==.',
Ca='Caroquintero:BAABLgAECn8fAAIIAAYJcgN04QC0AAZoDAAABgADAGkMAAAHABAAawwAAAYACABqDAAABAALAGwMAAAEAAkA6gwAAAQABgAIAAYJcgN04QC0AAZoDAAABgADAGkMAAAHABAAawwAAAYACABqDAAABAALAGwMAAAEAAkA6gwAAAQABgAAAA==.',
Ch='Charliemen:BAAALgAECgQJBAAAAA==.Chilli:BAAALgADCgEJAQAAAA==.Chubtart:BAACLgAFFH8IAAIMAAMJKxzHHgABAQNoDAAABABRAGkMAAADADIA6gwAAAEAVAAMAAMJKxzHHgABAQNoDAAABABRAGkMAAADADIA6gwAAAEAVAAuAAQKfzQAAgwACQnRIz0IABIDAAwACQnRIz0IABIDAAAA.Churrasco:BAAALgAECgQJCAAAAA==.',
Cl='Clayton:BAAALgADCgcJBAAAAA==.',
Co='Cojeculos:BAAALgAECgQJBwAAAA==.',
Cu='Cunumi:BAAALgAECgMJBAAAAA==.',
Da='Daddy:BAABLgAECn81AAMNAAkJZBVFGgDjAQloDAAACABKAGkMAAAHADEAawwAAAcAMgBqDAAACAAmAGwMAAAGAC0AbQwAAAMAOwDqDAAACQA3AG4MAAAEAFMAbwwAAAEAEwANAAkJZBVFGgDjAQloDAAABQBKAGkMAAAEADEAawwAAAQAMgBqDAAABQAmAGwMAAAEAC0AbQwAAAMAOwDqDAAABAA3AG4MAAAEAFMAbwwAAAEAEwAOAAYJKw1xYQD/AAZoDAAAAwAmAGkMAAADABcAawwAAAMAGwBqDAAAAwAUAGwMAAACADEA6gwAAAUAKgAAAA==.Daizenat:BAAALgADCgIJAgAAAA==.Danehar:BAAALgAECgEJAQAAAA==.',
Dc='Dcone:BAAALgADCgYJBgAAAA==.',
De='Deadkey:BAAALgADCgEJAQAAAA==.Deathborne:BAAALgAECgUJCQAAAA==.Deathshreik:BAAALgADCgMJAwAAAA==.Deathslam:BAACLgAFFH8JAAIKAAQJRQdkXgARAQRoDAAAAwAdAGkMAAACABAAawwAAAIAEADqDAAAAgALAAoABAlFB2ReABEBBGgMAAADAB0AaQwAAAIAEABrDAAAAgAQAOoMAAACAAsALgAECn8kAAIKAAkJbRnhJABOAgAKAAkJbRnhJABOAgAAAA==.',
Dr='Droston:BAAALgADCgQJBAAAAA==.',
Du='Durötan:BAABLgAECn8YAAQCAAkJUhByMgDpAQloDAAAAwAuAGkMAAAEAEIAawwAAAQAOABqDAAAAwAfAGwMAAACADQAbQwAAAIAFwDqDAAABAArAG4MAAABABIAbwwAAAEAGQACAAkJUhByMgDpAQloDAAAAgAuAGkMAAADAEIAawwAAAIAOABqDAAAAwAfAGwMAAABADQAbQwAAAEAFwDqDAAAAwArAG4MAAABABIAbwwAAAEAGQABAAUJRAoAVgDxAAVoDAAAAQAeAGsMAAACACgAbAwAAAEAEgBtDAAAAQAJAOoMAAABACAAAwABCb8KxlMAOgABaQwAAAEAGwABLgAFFAgJHAAPAJUdAA==.Dutchess:BAABLgAECn8eAAIQAAgJQBn9RgDSAQhoDAAABQBFAGkMAAAFAFIAawwAAAQASABqDAAABAA6AGwMAAAFAFQAbQwAAAIAQwDqDAAABAA7AG4MAAABABEAEAAICUAZ/UYA0gEIaAwAAAUARQBpDAAABQBSAGsMAAAEAEgAagwAAAQAOgBsDAAABQBUAG0MAAACAEMA6gwAAAQAOwBuDAAAAQARAAAA.',
Dy='Dylan:BAACLgAFFH8VAAIIAAUJXCK4KACBAQVoDAAABQBaAGkMAAAGAFsAawwAAAQAVABqDAAAAQBWAOoMAAAFAFUACAAFCVwiuCgAgQEFaAwAAAUAWgBpDAAABgBbAGsMAAAEAFQAagwAAAEAVgDqDAAABQBVAC4ABAp/LgACCAAJCVYlogQAVAMACAAJCVYlogQAVAMAAAA=.Dylanj:BAAALgAECgQJBAABLgAFFAUJFQAIAFwiAQ==.',
Ec='Echevalier:BAAALgAECgQJBQAAAA==.Echoes:BAAALgADCgQJBAAAAA==.',
Eg='Egonspengler:BAAALgADCgQJBAAAAA==.',
El='Elayia:BAAALgADCgEJAQAAAA==.Elowen:BAAALgAFFAIJBAAAAQ==.',
En='Enhae:BAAALgAECgEJAQAAAA==.',
Er='Eresiine:BAAALgAECgcJDgAAAA==.Eríngo:BAAALgAFFAEJAQAAAA==.',
Es='Esna:BAAALgADCgUJCQAAAA==.',
Fi='Filomena:BAAALgADCgUJBgAAAA==.Firnin:BAAALgAECgYJEAAAAA==.',
Fl='Floise:BAACLgAFFH8RAAMRAAUJ6hSDEwCIAQVoDAAABQAuAGkMAAAEADsAawwAAAMASgBqDAAAAQAsAOoMAAAEACkAEQAFCbYTgxMAiAEFaAwAAAIALgBpDAAAAwAsAGsMAAADAEoAagwAAAEALADqDAAABAApABIAAglUE1kNAJMAAmgMAAADACcAaQwAAAEAOwAuAAQKfx4ABBIACQn7GXcMAIwCABIACQlAGXcMAIwCABEABwkQFaw2AAgBAAYAAQlcEsppADsAAAAA.Flounder:BAAALgAECgEJAwAAAA==.',
Fo='Foamtotem:BAAALgADCgEJAQAAAA==.Forumsoldier:BAACLgAFFH8GAAIIAAQJageiVQAaAQRoDAAAAgAdAGkMAAACABUAawwAAAEACADqDAAAAQAQAAgABAlqB6JVABoBBGgMAAACAB0AaQwAAAIAFQBrDAAAAQAIAOoMAAABABAALgAECn8jAAIIAAgJlhcoVAA8AgAIAAgJlhcoVAA8AgAAAA==.',
Fr='Frozenscorch:BAAALgAECggJEgAAAA==.',
Ft='Fteve:BAAALgAECgUJCQAAAA==.',
['Fä']='Fälkor:BAABLgAECn8rAAMTAAgJrQbpEQDIAAhoDAAABwAdAGkMAAAGABgAawwAAAUAEwBqDAAABgAZAGwMAAAGABMAbQwAAAQACgDqDAAABgAIAG4MAAADAAcAFAAICa0GCkAAAgEIaAwAAAUAHQBpDAAABAAYAGsMAAAEABMAagwAAAUAFwBsDAAABQATAG0MAAAEAAoA6gwAAAYACABuDAAAAgAHABMABgkkBukRAMgABmgMAAACABMAaQwAAAIAFABrDAAAAQAPAGoMAAABABkAbAwAAAEADwBuDAAAAQAHAAAA.',
['Fö']='Föx:BAAALgAECgcJCQAAAA==.',
Gi='Gigamoo:BAAALgAECgQJBgAAAA==.',
Gl='Glorfindel:BAAALgAFFAEJAgABLgAFFAUJDAAMAPMWAA==.Glys:BAAALgAECgUJCgAAAA==.',
Go='Gogocow:BAAALgAECgEJAQAAAA==.Gooba:BAAALgAECgEJAQAAAA==.Goommar:BAABLgAECn8UAAIPAAcJMAJUaACGAAdoDAAAAwAEAGkMAAADAAYAawwAAAMABwBqDAAABAAIAGwMAAACAAgA6gwAAAQAAwBuDAAAAQACAA8ABwkwAlRoAIYAB2gMAAADAAQAaQwAAAMABgBrDAAAAwAHAGoMAAAEAAgAbAwAAAIACADqDAAABAADAG4MAAABAAIAAAA=.Gorim:BAAALgAECgIJAgAAAA==.',
Gr='Grandgoose:BAAALgADCgIJAgAAAA==.Grandpa:BAAALgAECgYJCAAAAA==.Granuju:BAAALgADCgUJBgAAAA==.',
Gu='Gunnhildr:BAAALgADCgkJCQAAAA==.',
Ha='Hanasanai:BAAALgADCgMJBAAAAA==.Handil:BAABLgAECn8cAAIVAAYJTCM2FABHAgZoDAAABQBZAGkMAAAFAFoAawwAAAUAXgBqDAAABQBcAGwMAAACAFEA6gwAAAYAXQAVAAYJTCM2FABHAgZoDAAABQBZAGkMAAAFAFoAawwAAAUAXgBqDAAABQBcAGwMAAACAFEA6gwAAAYAXQAAAA==.',
He='Helpingyou:BAABLgAECn8bAAIGAAkJ/wgmJACAAQloDAAAAwAcAGkMAAADABcAawwAAAIAFwBqDAAAAwAbAGwMAAAEABoAbQwAAAQAEwDqDAAAAwAdAG4MAAAEAA8AbwwAAAEAEQAGAAkJ/wgmJACAAQloDAAAAwAcAGkMAAADABcAawwAAAIAFwBqDAAAAwAbAGwMAAAEABoAbQwAAAQAEwDqDAAAAwAdAG4MAAAEAA8AbwwAAAEAEQAAAA==.',
Ho='Holybell:BAAALgAECgIJAgAAAA==.Hoptyj:BAAALgADCgIJAgAAAA==.',
['Hë']='Hënnessy:BAAALgADCgMJAwAAAA==.Hënnëssy:BAABLgAECn8dAAIVAAcJsRIoLACJAQdoDAAABABYAGkMAAAEAB0AawwAAAQALgBqDAAABQA3AGwMAAAEAC0AbQwAAAIABADqDAAABgBAABUABwmxEigsAIkBB2gMAAAEAFgAaQwAAAQAHQBrDAAABAAuAGoMAAAFADcAbAwAAAQALQBtDAAAAgAEAOoMAAAGAEAAAAA=.',
Im='Impaladin:BAAALgAECgMJAwAAAA==.',
Io='Iolanthe:BAAALgADCgQJBAAAAA==.',
Iz='Izeroeasily:BAAALgAECgMJAwABLgAECgUJBgAWAAAAAA==.Izerohealz:BAAALgADCgQJBAAAAA==.Izzi:BAAALgAECgYJEQAAAA==.Izzia:BAABLgAECn8dAAILAAgJ0BjEGgBMAghoDAAABgBSAGkMAAAEAFQAawwAAAYAPwBqDAAAAgBGAGwMAAACAEgAbQwAAAIAGgDqDAAABgBRAG4MAAABABsACwAICdAYxBoATAIIaAwAAAYAUgBpDAAABABUAGsMAAAGAD8AagwAAAIARgBsDAAAAgBIAG0MAAACABoA6gwAAAYAUQBuDAAAAQAbAAAA.',
Ja='Jabbathabutt:BAAALgAECgYJCQAAAA==.Jaceret:BAAALgAECgEJAQAAAA==.Jasia:BAAALgADCgYJCAAAAA==.',
Jo='Joyboy:BAAALgAECgEJAQAAAA==.',
Ju='Justfn:BAAALgADCgUJBwAAAA==.',
Ka='Kamitos:BAABLgAECn8sAAMRAAkJpA+pGADgAQloDAAACAAlAGkMAAAIADUAawwAAAQAOABqDAAABgAnAGwMAAAGACgAbQwAAAEAEgDqDAAABgA5AG4MAAAEACEAbwwAAAEAFgARAAkJpA+pGADgAQloDAAABgAlAGkMAAAHADUAawwAAAMAOABqDAAABAAnAGwMAAAEACgAbQwAAAEAEgDqDAAABgA5AG4MAAAEACEAbwwAAAEAFgAGAAUJyAhmRADZAAVoDAAAAgAiAGkMAAABABYAawwAAAEAGwBqDAAAAgAbAGwMAAACAAQAAAA=.Kaye:BAAALgADCgMJAgAAAA==.Kayewyn:BAABLgAECn8kAAILAAgJaBFfNQCiAQhoDAAABwBWAGkMAAAHAD0AawwAAAcAJgBqDAAABAAUAGwMAAADACQAbQwAAAEADwDqDAAABABDAG4MAAADAB0ACwAICWgRXzUAogEIaAwAAAcAVgBpDAAABwA9AGsMAAAHACYAagwAAAQAFABsDAAAAwAkAG0MAAABAA8A6gwAAAQAQwBuDAAAAwAdAAAA.',
Kb='Kbdh:BAAALgAECgYJCwABLgAFFAIJAwAWAAAAAA==.Kbdruid:BAAALgAFFAEJAQABLgAFFAIJAwAWAAAAAA==.Kbhunter:BAAALgAECgUJCAABLgAFFAIJAwAWAAAAAA==.Kbmage:BAAALgADCgQJBAABLgAFFAIJAwAWAAAAAA==.Kbmonk:BAAALgAFFAIJAwAAAA==.Kbpaladin:BAAALgAECgYJBgABLgAFFAIJAwAWAAAAAA==.',
Ke='Keiji:BAAALgAECgYJDgAAAA==.',
Kl='Klipnor:BAAALgAECgQJCAAAAA==.',
Kr='Krocketeer:BAAALgAECgYJCQAAAA==.',
Ky='Kyndel:BAAALgAECgYJCgABLgAFFAUJFwALAHUbAA==.Kynn:BAACLgAFFH8XAAILAAUJdRtsDwCwAQVoDAAABwBSAGkMAAAGAFEAawwAAAUAUABqDAAAAgAxAOoMAAADADgACwAFCXUbbA8AsAEFaAwAAAcAUgBpDAAABgBRAGsMAAAFAFAAagwAAAIAMQDqDAAAAwA4AC4ABAp/NwACCwAJCZQi8wEAgQMACwAJCZQi8wEAgQMAAAA=.',
['Kè']='Kèlemvore:BAABLgAECn8uAAIQAAgJkRJuWgCeAQhoDAAABwBBAGkMAAAHAEUAawwAAAcAPgBqDAAABgA2AGwMAAAHACEAbQwAAAIADwDqDAAABwA6AG4MAAADABsAEAAICZESbloAngEIaAwAAAcAQQBpDAAABwBFAGsMAAAHAD4AagwAAAYANgBsDAAABwAhAG0MAAACAA8A6gwAAAcAOgBuDAAAAwAbAAAA.',
Le='Leafittome:BAAALgADCgEJAQAAAA==.',
Ly='Lykos:BAAALgAECgYJDgAAAA==.',
Ma='Mammal:BAAALgAECgQJBAABLgAECggJGgANAHQcAA==.',
Me='Medxchaos:BAAALgAECgQJBwABLgAFFAUJEQARAOoUAA==.Meowy:BAAALgAECgEJAQAAAA==.Mepha:BAABLgAECn8rAAMXAAkJlyAtBwBhAgloDAAABwBYAGkMAAAHAFsAawwAAAcAWwBqDAAABQBMAGwMAAAEAEkAbQwAAAMAPQDqDAAABgBhAG4MAAADAEkAbwwAAAEAWgAPAAcJ+B/yGACDAgdoDAAABABYAGkMAAAEAFsAawwAAAQAWwBqDAAAAgBMAGwMAAACAEUAbQwAAAEAMwDqDAAAAwBhABcACQleHS0HAGECCWgMAAADAEgAaQwAAAMAUgBrDAAAAwBQAGoMAAADABcAbAwAAAIASQBtDAAAAgA9AOoMAAADAEQAbgwAAAMASQBvDAAAAQBaAAAA.',
Mi='Mightymost:BAAALgAECgYJCwAAAA==.',
Mu='Mudd:BAABLgAECn8jAAMXAAgJkh9eCABEAghoDAAABQBJAGkMAAAFAFcAawwAAAMAUgBqDAAAAwA7AGwMAAAEAFwAbQwAAAIASgDqDAAACABbAG4MAAAFAEAAFwAICZIfXggARAIIaAwAAAUASQBpDAAABQBXAGsMAAADAFIAagwAAAMAOwBsDAAABABcAG0MAAACAEoA6gwAAAUAWwBuDAAABQBAAA8AAQlwEAaGADYAAeoMAAADACoAAAA=.Mudds:BAABLgAECn8cAAIJAAgJoSB7EAB5AghoDAAABgBVAGkMAAAFAFoAawwAAAUAWABqDAAAAgBMAGwMAAACAFQAbQwAAAIAUgDqDAAABQBXAG4MAAABAEEACQAICaEgexAAeQIIaAwAAAYAVQBpDAAABQBaAGsMAAAFAFgAagwAAAIATABsDAAAAgBUAG0MAAACAFIA6gwAAAUAVwBuDAAAAQBBAAEuAAQKCAkjABcAkh8A.',
Na='Naelia:BAAALgAECgYJEAABLgAFFAUJFgAKAEEVAA==.Nakira:BAAALgAECgMJAwAAAA==.Nami:BAAALgAECgUJBQAAAA==.',
Ne='Nenekirimaru:BAAALgADCgIJAgAAAA==.',
Ni='Nicodemus:BAAALgADCgIJAgAAAA==.Nightrush:BAABLgAECn8oAAMCAAgJIiVMGgBfAghoDAAABwBjAGkMAAAHAGIAawwAAAYAYQBqDAAABQBdAGwMAAADAFEAbQwAAAMAXQDqDAAABgBiAG4MAAADAGAAAgAGCQQmTBoAXwIGaAwAAAEAYwBpDAAAAQBiAGsMAAACAGEAbQwAAAMAXQDqDAAAAQBiAG4MAAADAGAAAQAGCbQh1QsAggEGaAwAAAYAWwBpDAAABgBXAGsMAAAEAFQAagwAAAUAXQBsDAAAAwBRAOoMAAAFAFYAAAA=.',
No='Noodles:BAABLgAECn8dAAIFAAcJvhYUaQAtAQdoDAAABgBGAGkMAAAGADkAawwAAAYANABqDAAABQBMAGwMAAADACwA6gwAAAIAPwBuDAAAAQA8AAUABwm+FhRpAC0BB2gMAAAGAEYAaQwAAAYAOQBrDAAABgA0AGoMAAAFAEwAbAwAAAMALADqDAAAAgA/AG4MAAABADwAAAA=.Norbit:BAAALgAECgEJAQAAAA==.',
Oe='Oesteroth:BAABLgAECn8UAAILAAYJbgWmdQC0AAZoDAAABAAYAGkMAAAEAAkAawwAAAQACQBqDAAAAwAUAGwMAAABAAgA6gwAAAQACgALAAYJbgWmdQC0AAZoDAAABAAYAGkMAAAEAAkAawwAAAQACQBqDAAAAwAUAGwMAAABAAgA6gwAAAQACgAAAA==.',
Ok='Okomo:BAAALgAECgUJBgAAAA==.',
Pa='Palaben:BAABLgAECn8bAAMVAAgJdRGqOABAAQhoDAAABAAyAGkMAAAEAFsAawwAAAQANQBqDAAABAAiAGwMAAADACYAbQwAAAIAFgDqDAAAAwA9AG4MAAADAAMAFQAHCawSqjgAQAEHaAwAAAQAMgBpDAAABABbAGsMAAAEADUAagwAAAMAIgBsDAAAAgAmAOoMAAADAD0AbgwAAAEAAwAQAAQJXQw6+gCRAARqDAAAAQAGAGwMAAABABkAbQwAAAIAGgBuDAAAAgAqAAAA.Pantsu:BAABLgAECn9BAAQKAAgJuCWsEQDBAghoDAAACgBiAGkMAAAKAGMAawwAAAkAYgBqDAAACABdAGwMAAAHAF8AbQwAAAYAXQDqDAAACQBeAG4MAAAGAGAACgAICYElrBEAwQIIaAwAAAgAYgBpDAAACABjAGsMAAAHAGIAagwAAAYAXQBsDAAABQBfAG0MAAAEAFkA6gwAAAcAXgBuDAAABABgABgACAnYINEGAI4CCGgMAAABAEsAaQwAAAEAVABrDAAAAQBLAGoMAAABAFoAbAwAAAEAUwBtDAAAAQBdAOoMAAABAFgAbgwAAAEAVwAZAAgJ/x8MBQAtAghoDAAAAQBUAGkMAAABAFwAawwAAAEAWwBqDAAAAQA/AGwMAAABAFoAbQwAAAEARQDqDAAAAQBIAG4MAAABAEcAAAA=.Pateaviejas:BAAALgAECgMJAwAAAA==.Pawnchy:BAAALgAECgUJCQAAAA==.',
Pe='Peepaw:BAABLgAECn8ZAAIaAAYJTgV+XACkAAZoDAAABQAOAGkMAAAGABMAawwAAAYAEABqDAAAAwATAGwMAAABAAUA6gwAAAQABgAaAAYJTgV+XACkAAZoDAAABQAOAGkMAAAGABMAawwAAAYAEABqDAAAAwATAGwMAAABAAUA6gwAAAQABgAAAA==.',
Pi='Pitchwhite:BAABLgAECn8XAAISAAYJHBFpRAAnAQZoDAAABQA7AGkMAAAEACMAawwAAAQAOwBqDAAABAAzAGwMAAABABIA6gwAAAUAJgASAAYJHBFpRAAnAQZoDAAABQA7AGkMAAAEACMAawwAAAQAOwBqDAAABAAzAGwMAAABABIA6gwAAAUAJgAAAA==.Pixel:BAAALgADCgkJDQAAAA==.',
Pr='Proselyte:BAACLgAFFH8PAAIJAAQJixgVDAA7AQRoDAAABQA7AGkMAAAFAEgAawwAAAIAMgDqDAAAAwBEAAkABAmLGBUMADsBBGgMAAAFADsAaQwAAAUASABrDAAAAgAyAOoMAAADAEQALgAECn8pAAIJAAkJ3h9+BgDEAgAJAAkJ3h9+BgDEAgAAAA==.',
Pu='Punchbear:BAAALgADCgYJBgAAAA==.Punchize:BAABLgAECn8lAAMbAAgJAiFQCACSAghoDAAABgBiAGkMAAAHAFQAawwAAAcAUQBqDAAABABgAGwMAAADADwAbQwAAAEAVQDqDAAABgBWAG4MAAADAF8AGwAICQIhUAgAkgIIaAwAAAYAYgBpDAAABgBUAGsMAAAGAFEAagwAAAQAYABsDAAAAwA8AG0MAAABAFUA6gwAAAYAVgBuDAAAAwBfABoAAgn0ClR7AEgAAmkMAAABACAAawwAAAEAFwAAAA==.Punchlocks:BAAALgAECgEJAQAAAA==.',
Qu='Quirkchungus:BAAALgAECgYJDwAAAA==.',
Ra='Rakrak:BAAALgADCgEJAQAAAA==.Rani:BAAALgADCgUJBQAAAA==.Rathon:BAAALgAECgkJDQAAAA==.',
Re='Remote:BAAALgAECgQJBwAAAA==.',
Ri='Rianis:BAAALgADCgcJEAAAAA==.Rilea:BAAALgAECgYJEQAAAA==.',
['Rä']='Räiyu:BAAALgADCgMJAwAAAA==.',
Sa='Sadgasm:BAABLgAECn8mAAIcAAkJGiBfAwCrAgloDAAABgBfAGkMAAAGAGEAawwAAAYATABqDAAABABbAGwMAAAEAEIAbQwAAAIARADqDAAABwBVAG4MAAACAFUAbwwAAAEAUgAcAAkJGiBfAwCrAgloDAAABgBfAGkMAAAGAGEAawwAAAYATABqDAAABABbAGwMAAAEAEIAbQwAAAIARADqDAAABwBVAG4MAAACAFUAbwwAAAEAUgAAAA==.Safeword:BAAALgAECgkJCwAAAA==.Sauron:BAAALgAECgUJCgAAAA==.',
Sc='Scrubuckett:BAAALgADCgYJBgAAAA==.',
Se='Sebrine:BAAALgAECgUJCwAAAA==.Seishan:BAACLgAFFH8HAAMEAAUJJRHoEQC6AAVoDAAAAgA/AGkMAAABAEIAawwAAAEAEABqDAAAAQArAOoMAAACABwABAAFCSUR6BEAugAFaAwAAAIAPwBpDAAAAQBCAGsMAAABABAAagwAAAEAKwDqDAAAAQAcAB0AAQmvCbEOAEkAAeoMAAABABgALgAECn8fAAQdAAcJkxsqBwD0AQAdAAYJ1R4qBwD0AQAEAAUJxhdMPQAyAQAeAAEJ+xcMGwBDAAAAAA==.Seneca:BAAALgAECgEJBAAAAA==.',
Sh='Shadowslam:BAAALgAECgYJCAAAAA==.Shadowtalon:BAAALgADCgEJAQAAAA==.Shamandrea:BAAALgAECgYJCgABLgAFFAMJBwASAPUSAA==.Shzam:BAAALgADCgYJDgAAAA==.',
Sl='Slam:BAAALgADCgMJBQAAAA==.Sleipner:BAABLgAECn8fAAIfAAkJAA7VFQBIAQloDAAABABTAGkMAAAEADQAawwAAAQAJgBqDAAABAAdAGwMAAAEABsAbQwAAAMAEgDqDAAABQAhAG4MAAACABMAbwwAAAEADAAfAAkJAA7VFQBIAQloDAAABABTAGkMAAAEADQAawwAAAQAJgBqDAAABAAdAGwMAAAEABsAbQwAAAMAEgDqDAAABQAhAG4MAAACABMAbwwAAAEADAAAAA==.',
Sm='Smiley:BAAALgADCgYJBgAAAA==.',
Sn='Sneeze:BAAALgADCgIJAgAAAA==.Snugglehex:BAAALgADCgEJAQAAAA==.',
So='Socktrout:BAABLgAECn8qAAQgAAkJnxcKOgDZAQloDAAABgAzAGkMAAAFAEkAawwAAAQAQwBqDAAAAwAbAGwMAAAGACkAbQwAAAUAPwDqDAAABgBBAG4MAAAEAEsAbwwAAAMAKwAgAAgJfRYKOgDZAQhoDAAABgAzAGkMAAAFAEkAawwAAAQAQwBsDAAAAgApAG0MAAACAD8A6gwAAAYAQQBuDAAABABLAG8MAAACABQAIQADCesKEkMAqQADagwAAAIAGwBsDAAABAAgAG0MAAADABYAIgACCS0RWysARQACagwAAAEABgBvDAAAAQArAAAA.Softgrizzly:BAAALgADCgMJAwAAAA==.Solidgold:BAACLgAFFH8cAAMPAAgJlR1iAACnAghoDAAABgBeAGkMAAAFAFMAawwAAAQAWwBqDAAABABaAGwMAAACADAAbQwAAAEAFQDqDAAABQBfAG4MAAABAF8ADwAICZUdYgAApwIIaAwAAAYAXgBpDAAABQBTAGsMAAAEAFsAagwAAAQAWgBsDAAAAQAwAG0MAAABABUA6gwAAAUAXwBuDAAAAQBfABcAAQmgBroLAFMAAWwMAAABABAALgAECn8vAAMPAAgJfSXHBAD7AgAPAAgJfSXHBAD7AgAXAAUJqCD8HAAIAQAAAA==.Solvane:BAAALgAECgMJAwABLgAFFAUJBwAEACURAA==.',
Sp='Spongeybob:BAAALgADCgEJAgAAAA==.',
Ss='Sscrubbucket:BAAALgAECgYJBgAAAA==.',
Su='Sunrise:BAAALgADCgkJEAAAAA==.',
Sy='Syllassa:BAAALgAECgkJAQAAAA==.Sylv:BAAALgAECgQJBAAAAA==.',
Ta='Taelia:BAACLgAFFH8WAAIKAAUJQRUzQgBBAQVoDAAABgBIAGkMAAAFADUAawwAAAQAJgBqDAAAAgAyAOoMAAAFADUACgAFCUEVM0IAQQEFaAwAAAYASABpDAAABQA1AGsMAAAEACYAagwAAAIAMgDqDAAABQA1AC4ABAp/QwACCgAJCWQjTAgAFQMACgAJCWQjTAgAFQMAAAA=.Tahine:BAAALgAECgcJEAAAAA==.Tans:BAAALgADCgkJCwAAAA==.',
Ti='Tiktoks:BAAALgAECgEJAQABLgAFFAQJCgASAOgHAA==.Timetwoflame:BAABLgAECn8fAAMjAAgJ5RH+DQDKAQhoDAAABwA/AGkMAAAHAEUAawwAAAYAQgBqDAAAAgATAGwMAAABABwAbQwAAAEAIgDqDAAABAAyAG4MAAADACEAIwAICeUR/g0AygEIaAwAAAYAPwBpDAAABgBFAGsMAAAFAEIAagwAAAEAEwBsDAAAAQAcAG0MAAABACIA6gwAAAQAMgBuDAAAAwAhABMABAm6B54WAIEABGgMAAABAA0AaQwAAAEAEABrDAAAAQAdAGoMAAABAAUAAAA=.',
Tn='Tnarg:BAAALgADCgIJAgAAAA==.',
To='Tokki:BAAALgAECgYJCwAAAA==.',
Tr='Trekvis:BAAALgADCgcJDgAAAA==.',
Tu='Tugboat:BAAALgADCgIJAgAAAA==.',
Tw='Twoæ:BAAALgAECgEJAQAAAA==.',
['Tû']='Tûâny:BAAALgAECgUJBQAAAA==.',
Up='Upphoria:BAABLgAECn8bAAMSAAgJ6AosLQA+AQhoDAAABQArAGkMAAAGADAAawwAAAQABABqDAAAAwAOAGwMAAACAAwAbQwAAAEAJgDqDAAABQApAG4MAAABABIAEgAICegKLC0APgEIaAwAAAQAKwBpDAAABQAwAGsMAAAEAAQAagwAAAMADgBsDAAAAgAMAG0MAAABACYA6gwAAAUAKQBuDAAAAQASAAYAAgk+A1h7ACMAAmgMAAABAAQAaQwAAAEADAAAAA==.',
Ur='Urkel:BAAALgAECgEJAQAAAA==.',
Ut='Uthomage:BAAALgAECgMJAwAAAA==.',
Va='Vashi:BAAALgADCgcJBwAAAA==.',
Vi='Viccan:BAABLgAECn8lAAMhAAkJHAeXEAANAQloDAAABgAeAGkMAAAFABMAawwAAAUAEABqDAAAAwAIAGwMAAAFAAkAbQwAAAMABwDqDAAABgAbAG4MAAADAA8AbwwAAAEAEgAhAAkJ/AaXEAANAQloDAAABgAeAGkMAAAFABMAawwAAAUAEABqDAAAAwAIAGwMAAAEAAkAbQwAAAIABADqDAAABgAbAG4MAAACAA8AbwwAAAEAEgAgAAMJKgLqAQFDAANsDAAAAQAGAG0MAAABAAcAbgwAAAEAAwAAAA==.',
Wa='Walkingtanko:BAAALgADCgIJAgAAAA==.Wavés:BAAALgADCgIJAgAAAA==.',
We='Wef:BAAALgADCgcJBwAAAA==.',
Wi='Wildwood:BAAALgADCgMJAwAAAA==.Willowleaf:BAAALgAECgEJAQABLgAFFAMJBwASAPUSAA==.',
Wo='Wolffie:BAAALgAECggJEQAAAA==.',
Wu='Wushuu:BAAALgAECgUJCgABLgAFFAUJDgAIAHILAA==.',
Xa='Xampu:BAAALgADCgYJBgAAAA==.',
Xe='Xernaeus:BAAALgADCgQJBAAAAA==.',
Ya='Yahwëh:BAAALgAECgMJBAAAAA==.',
Yo='Yodason:BAAALgADCgQJBQAAAA==.',
Yu='Yuukï:BAABLgAECn8qAAMJAAkJdB5qDABXAgloDAAABwBbAGkMAAAGAFUAawwAAAcAUQBqDAAABABGAGwMAAAFADwAbQwAAAMAPgDqDAAABgBbAG4MAAADAFEAbwwAAAEARAAJAAgJ+B5qDABXAghoDAAABwBbAGkMAAAGAFUAawwAAAYAUQBqDAAABABGAGwMAAAEADwAbQwAAAIAPgDqDAAABgBbAG4MAAADAFEAGgAECQgH1mcAfQAEawwAAAEABwBsDAAAAQANAG0MAAABABAAbwwAAAEAIgAAAA==.',
Za='Zaelyse:BAAALgAECgYJBgAAAA==.Zaton:BAABLgAECn8ZAAIIAAgJLxGTaACOAQhoDAAABAAsAGkMAAAEAEEAawwAAAQAMQBqDAAABABMAGwMAAACAA8AbQwAAAEANQDqDAAABAAxAG4MAAACABwACAAICS8Rk2gAjgEIaAwAAAQALABpDAAABABBAGsMAAAEADEAagwAAAQATABsDAAAAgAPAG0MAAABADUA6gwAAAQAMQBuDAAAAgAcAAAA.',
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
