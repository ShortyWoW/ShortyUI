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

local lookup = {'DeathKnight-Frost','Hunter-BeastMastery','Hunter-Survival','Warrior-Fury','Warrior-Arms','Druid-Balance','Shaman-Elemental','Priest-Discipline','Shaman-Enhancement','Shaman-Restoration','Warrior-Protection','DeathKnight-Unholy','Evoker-Augmentation','Evoker-Devastation','Mage-Frost','DemonHunter-Havoc','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Paladin-Retribution','Unknown-Unknown','DemonHunter-Devourer','Monk-Mistweaver','Monk-Windwalker','DeathKnight-Blood','Priest-Holy','Rogue-Assassination','Paladin-Holy','Druid-Restoration','Druid-Guardian','Paladin-Protection','Monk-Brewmaster','Druid-Feral',}
local provider = {region='US',realm='Darrowmere',name='US',type='daily',zone=46,date='2026-05-12',data={Ab='Abaddonmoon:BAABLgAECn8XAAIBAAYJOwcyDADyAAZoDAAABQAUAGkMAAAEABYAawwAAAQAGgBqDAAAAwARAGwMAAADAAgA6gwAAAQADgABAAYJOwcyDADyAAZoDAAABQAUAGkMAAAEABYAawwAAAQAGgBqDAAAAwARAGwMAAADAAgA6gwAAAQADgAAAA==.',
Ad='Addvar:BAAALgADCgEJAQAAAA==.Adelost:BAAALgAECgQJBQAAAA==.',
Ah='Ahalina:BAAALgAECgEJAQAAAA==.Ahnari:BAACLgAFFH8FAAICAAMJdgJ5DwDMAANoDAAAAgAIAGkMAAACAAMAawwAAAEABgACAAMJdgJ5DwDMAANoDAAAAgAIAGkMAAACAAMAawwAAAEABgAuAAQKfxUAAwIACAlAEVg9ALkBAAIACAlAEVg9ALkBAAMABAm8AoQmAIsAAAAA.',
Ai='Ailinaa:BAACLgAFFH8YAAMEAAYJoBh6BQCbAQZoDAAAAwBDAGkMAAAFAEUAawwAAAQAPQBqDAAABQAjAGwMAAACABwA6gwAAAUAWAAEAAUJBRx6BQCbAQVoDAAAAwBDAGkMAAACAEUAawwAAAQAPQBqDAAAAwANAOoMAAAFAFgABQADCeQMBRQAnwADaQwAAAMAJQBqDAAAAgAjAGwMAAACABwALgAECn8gAAMEAAkJJB/JFQCfAgAEAAgJKR/JFQCfAgAFAAQJ4xfmFAAtAQAAAA==.',
Ak='Akalifato:BAAALgAFFAMJAwABLgAFFAUJFQAGAB4eAA==.Akroma:BAAALgAECgIJBAAAAA==.',
Al='Alariya:BAAALgAECgUJBQAAAA==.Alerat:BAAALgADCgMJAwABLgAECggJGgAHANAIAA==.Alistin:BAAALgAECgcJCAAAAA==.Alone:BAAALgADCgQJAwAAAA==.Alstir:BAAALgAECgEJAQAAAA==.',
Am='Amaryllis:BAAALgAECgEJAQAAAA==.Ambivalent:BAAALgAECgQJBgAAAA==.',
Ar='Aradin:BAAALgADCgcJCAAAAA==.Archanfel:BAABLgAECn8gAAIDAAYJ5wyYHgAjAQZoDAAABgAiAGkMAAAGAB4AawwAAAYALwBqDAAABQANAGwMAAAEAAwA6gwAAAUAKAADAAYJ5wyYHgAjAQZoDAAABgAiAGkMAAAGAB4AawwAAAYALwBqDAAABQANAGwMAAAEAAwA6gwAAAUAKAAAAA==.Argasha:BAAALgADCgUJBQAAAA==.',
As='Asriel:BAAALgAECgcJCAAAAA==.',
Aw='Awsomweorc:BAAALgADCgEJAQAAAA==.',
Ay='Ayonna:BAAALgAECgUJDAAAAA==.',
Az='Azar:BAAALgADCgUJBQAAAA==.',
Ba='Bandie:BAAALgAECgUJDAAAAA==.Barksalot:BAAALgADCgEJAQAAAA==.Barrakum:BAAALgAECgUJDgAAAA==.Bayn:BAAALgADCgQJCQAAAA==.',
Be='Beeftruck:BAACLgAFFH8HAAMFAAMJZRMSGAB5AANoDAAAAwAxAGkMAAACAD4A6gwAAAIAJAAEAAIJ+BX+JgCaAAJoDAAAAgAxAGkMAAACAD4ABQACCbcIEhgAeQACaAwAAAEACADqDAAAAgAkAC4ABAp/IwADBQAICcshIgQAZQIABQAICVceIgQAZQIABAAGCfQeBiEAcwEAAAA=.Belletrixx:BAAALgAECgYJEgAAAA==.Berried:BAABLgAECn8wAAIIAAkJRx6AAwALAwloDAAACABeAGkMAAAHAFcAawwAAAgAUgBqDAAABwBOAGwMAAAEAFAAbQwAAAMARgDqDAAABwBYAG4MAAADADYAbwwAAAEAPAAIAAkJRx6AAwALAwloDAAACABeAGkMAAAHAFcAawwAAAgAUgBqDAAABwBOAGwMAAAEAFAAbQwAAAMARgDqDAAABwBYAG4MAAADADYAbwwAAAEAPAAAAA==.',
Bi='Biigmâc:BAAALgAECgcJEAAAAA==.Biminem:BAABLgAECn8ZAAIJAAgJdBSLBwDOAQhoDAAABgBPAGkMAAADAD8AawwAAAMAOABqDAAAAwA3AGwMAAAEAEIAbQwAAAEAGADqDAAABAAkAG4MAAABACcACQAICXQUiwcAzgEIaAwAAAYATwBpDAAAAwA/AGsMAAADADgAagwAAAMANwBsDAAABABCAG0MAAABABgA6gwAAAQAJABuDAAAAQAnAAAA.',
Bl='Black:BAAALgAECgYJDAAAAA==.Blackwidow:BAAALgAECgMJAwAAAA==.Bloodshöt:BAAALgAECgYJEQABLgAECggJHwAEANMVAA==.',
Bo='Bodak:BAABLgAECn8bAAIKAAYJ5hnRNwCjAQZoDAAABQA7AGkMAAAFADgAawwAAAUAVwBqDAAABABOAGwMAAAEACYA6gwAAAQATQAKAAYJ5hnRNwCjAQZoDAAABQA7AGkMAAAFADgAawwAAAUAVwBqDAAABABOAGwMAAAEACYA6gwAAAQATQAAAA==.Boricua:BAAALgAECgEJAgAAAA==.',
Br='Brakun:BAAALgADCgIJAgAAAA==.Broris:BAAALgAECgMJAwAAAA==.',
Ca='Calamari:BAAALgADCgQJBAAAAA==.Calistarius:BAABLgAECn8UAAILAAgJlBDnEQBSAQhoDAAAAwA4AGkMAAADADgAawwAAAMAKABqDAAAAwBOAGwMAAADABoAbQwAAAEAKADqDAAAAwArAG4MAAABAB8ACwAICZQQ5xEAUgEIaAwAAAMAOABpDAAAAwA4AGsMAAADACgAagwAAAMATgBsDAAAAwAaAG0MAAABACgA6gwAAAMAKwBuDAAAAQAfAAAA.Caliste:BAAALgADCgIJAgABLgAFFAQJDgAJAFgeAA==.Calityy:BAAALgADCgYJBgABLgAFFAYJEwADAH8fAA==.Camine:BAABLgAECn8mAAIMAAgJshm2KgDoAQhoDAAABwBfAGkMAAAGAD8AawwAAAYAOwBqDAAABQBOAGwMAAAFAFUAbQwAAAEALgDqDAAABQAwAG4MAAADADwADAAICbIZtioA6AEIaAwAAAcAXwBpDAAABgA/AGsMAAAGADsAagwAAAUATgBsDAAABQBVAG0MAAABAC4A6gwAAAUAMABuDAAAAwA8AAAA.Carise:BAAALgAECgQJBAAAAA==.Castalasaras:BAAALgAECgMJAwAAAA==.Castorsilver:BAAALgAECgEJAQAAAA==.',
Ce='Certified:BAAALgAECgUJBQAAAA==.',
Ch='Chickeny:BAAALgADCgEJAQAAAA==.Choppstik:BAAALgAECgYJDAAAAA==.',
Co='Coldslayerck:BAAALgADCgkJCQAAAA==.Constäntine:BAAALgAECgQJBAAAAA==.Coriolis:BAABLgAECn8kAAMNAAYJ3hlrHABwAQZoDAAABgBQAGkMAAAHAEEAawwAAAYAQwBqDAAABQAxAGwMAAAFADgA6gwAAAcAPQANAAYJ3hlrHABwAQZoDAAABQBQAGkMAAAFAEEAawwAAAYAQwBqDAAABQAxAGwMAAAFADgA6gwAAAUAPQAOAAMJggrxMACPAANoDAAAAQAgAGkMAAACABEA6gwAAAIAHQAAAA==.',
Cr='Crowléy:BAAALgAECgUJDAAAAA==.',
Cu='Cuddlyowl:BAABLgAECn8XAAIPAAcJwQ4DqwCFAQdoDAAAAwA4AGkMAAAEAC4AawwAAAMAMQBqDAAABAAnAGwMAAACABgAbQwAAAIACwDqDAAABQAkAA8ABwnBDgOrAIUBB2gMAAADADgAaQwAAAQALgBrDAAAAwAxAGoMAAAEACcAbAwAAAIAGABtDAAAAgALAOoMAAAFACQAAAA=.',
Da='Dagnamagus:BAAALgAECgQJBQAAAA==.Daliann:BAAALgAECgYJCQAAAA==.Damnation:BAAALgAECgYJBwAAAA==.Dangerduck:BAAALgAECgYJEgAAAA==.Darktruth:BAAALgADCgMJAwAAAA==.Dartes:BAAALgAECgYJCwAAAA==.Dashe:BAAALgAECgcJAQAAAA==.',
De='Deathcokie:BAAALgAECgYJDgAAAA==.Deatho:BAABLgAECn8kAAMLAAYJ9yZBBgA+AgZoDAAABgBjAGkMAAAHAGMAawwAAAYAYwBqDAAABQBjAGwMAAAFAGMA6gwAAAcAYwALAAYJ9yZBBgA+AgZoDAAABgBjAGkMAAAHAGMAawwAAAYAYwBqDAAABQBjAGwMAAAFAGMA6gwAAAYAYwAEAAEJCSNznQBKAAHqDAAAAQBZAAAA.Deathstoned:BAAALgADCgQJBQAAAA==.Deimos:BAAALgADCgQJBAAAAA==.',
Di='Diamondshard:BAAALgAECgIJAwAAAA==.',
Dr='Draegov:BAAALgADCgYJBgAAAA==.Draeth:BAAALgADCgcJDQAAAA==.Dreadful:BAAALgAECgYJDQAAAA==.Dreylan:BAAALgADCgcJBwAAAA==.Dreyra:BAAALgADCgcJBwABLgAECgkJLQADAL8eAA==.Drosof:BAAALgADCgYJCwAAAA==.Drow:BAAALgADCgcJBwAAAA==.',
Du='Dukalioth:BAABLgAECn8XAAIQAAYJdA1RHQAIAQZoDAAABQAmAGkMAAAEADEAawwAAAUAHgBqDAAAAwASAGwMAAADABMA6gwAAAMAIgAQAAYJdA1RHQAIAQZoDAAABQAmAGkMAAAEADEAawwAAAUAHgBqDAAAAwASAGwMAAADABMA6gwAAAMAIgAAAA==.',
['Dê']='Dêcay:BAACLgAFFH8PAAIMAAUJCyL/GQB9AQVoDAAABQBWAGkMAAAEAF4AawwAAAIAXQBqDAAAAQAtAOoMAAADAEkADAAFCQsi/xkAfQEFaAwAAAUAVgBpDAAABABeAGsMAAACAF0AagwAAAEALQDqDAAAAwBJAC4ABAp/KAADDAAJCTYgExgA6wIADAAICf0hExgA6wIAAQAFCbgdXQQAzAEAAAA=.',
['Dö']='Döctorfate:BAAALgAECgYJBgAAAA==.',
Ef='Effinsoldier:BAAALgAECgUJDQAAAA==.',
Ek='Ekko:BAAALgADCgIJAgAAAA==.',
El='Ellyy:BAAALgADCgIJAgAAAA==.Elvira:BAAALgAECgQJBQAAAA==.',
En='Endlessagony:BAABLgAECn8eAAIMAAkJBx4wIADBAgloDAAABQBYAGkMAAADAF4AawwAAAMAVQBqDAAAAwBjAGwMAAAEAE8AbQwAAAIAJQDqDAAABABKAG4MAAAEAEsAbwwAAAIATgAMAAkJBx4wIADBAgloDAAABQBYAGkMAAADAF4AawwAAAMAVQBqDAAAAwBjAGwMAAAEAE8AbQwAAAIAJQDqDAAABABKAG4MAAAEAEsAbwwAAAIATgAAAA==.Endlessice:BAAALgAECgUJBQAAAA==.Enyo:BAABLgAECn8fAAQRAAYJ3R8+KwDIAQZoDAAABQBdAGkMAAAGAEsAawwAAAYAUABqDAAABABMAGwMAAAFAE4A6gwAAAUAUAARAAYJ3R8+KwDIAQZoDAAABQBdAGkMAAAFAEsAawwAAAUAUABqDAAAAQA5AGwMAAAFAE4A6gwAAAUAUAASAAEJAAA1JwBVAAFqDAAAAwBMABMAAgl4Bn1eAFMAAmkMAAABABAAawwAAAEAEAAAAA==.',
Er='Erathas:BAABLgAECn8ZAAIUAAkJsRHBYQC/AQloDAAAAwAWAGkMAAADACAAawwAAAMAKQBqDAAAAgASAGwMAAAEAEAAbQwAAAIAJwDqDAAABQA9AG4MAAACADoAbwwAAAEAKgAUAAkJsRHBYQC/AQloDAAAAwAWAGkMAAADACAAawwAAAMAKQBqDAAAAgASAGwMAAAEAEAAbQwAAAIAJwDqDAAABQA9AG4MAAACADoAbwwAAAEAKgAAAA==.',
Fa='Falandril:BAAALgAECggJDwAAAA==.Fasriel:BAAALgAECgIJAgAAAA==.',
Fe='Feata:BAAALgAECgEJAQABLgAECgMJAwAVAAAAAA==.Felston:BAAALgADCgUJBQAAAA==.',
Fi='Fiyero:BAABLgAECn8gAAMEAAkJMQ4cGQCvAQloDAAABgAmAGkMAAAGACEAawwAAAUAIgBqDAAAAwAgAGwMAAACADYAbQwAAAEAEADqDAAABQAfAG4MAAADADUAbwwAAAEAHQAEAAkJMQ4cGQCvAQloDAAABAAmAGkMAAAFACEAawwAAAQAIgBqDAAAAgAgAGwMAAABADYAbQwAAAEAEADqDAAABAAfAG4MAAACADUAbwwAAAEAHQAFAAcJwgQqJQDEAAdoDAAAAgAYAGkMAAABAAUAawwAAAEABgBqDAAAAQAQAGwMAAABABMA6gwAAAEACQBuDAAAAQAHAAAA.',
Fl='Flagcrazed:BAAALgADCgUJBQAAAA==.Fleabath:BAAALgAECgUJCQABLgAECggJGgACANkIAA==.Fluffypyro:BAAALgADCgYJBgAAAA==.',
Fo='Forëplây:BAAALgAECgMJBAAAAA==.Foughum:BAAALgADCgUJBQABLgAECgMJAwAVAAAAAA==.',
Fr='Friedcheekin:BAAALgADCgUJBQAAAA==.',
Fu='Fury:BAAALgADCgEJAQAAAA==.',
Ga='Galdames:BAAALgADCgQJBAAAAA==.',
Ge='Gedien:BAAALgAECgYJCQAAAA==.',
Gi='Gilforty:BAABLgAECn8YAAITAAcJ0BYJBgCiAQdoDAAABABDAGkMAAAEAEwAawwAAAQANwBqDAAABAAhAGwMAAADAD4AbQwAAAEAFQDqDAAABABDABMABwnQFgkGAKIBB2gMAAAEAEMAaQwAAAQATABrDAAABAA3AGoMAAAEACEAbAwAAAMAPgBtDAAAAQAVAOoMAAAEAEMAAAA=.',
Gl='Glep:BAAALgAECgIJAgABLgAECgkJJgAWAEQdAA==.Gloriosa:BAABLgAECn8vAAIXAAkJBQ4yFwC0AQloDAAABwAnAGkMAAAHADMAawwAAAcALgBqDAAABgAoAGwMAAAGABMAbQwAAAMAFQDqDAAABwA6AG4MAAADABYAbwwAAAEAFwAXAAkJBQ4yFwC0AQloDAAABwAnAGkMAAAHADMAawwAAAcALgBqDAAABgAoAGwMAAAGABMAbQwAAAMAFQDqDAAABwA6AG4MAAADABYAbwwAAAEAFwAAAA==.',
Go='Gorl:BAAALgAECgEJAQAAAA==.',
Gv='Gvendalyn:BAABLgAECn8cAAICAAcJaSZfCwCbAgdoDAAABQBjAGkMAAAEAGMAawwAAAUAYgBqDAAAAwBiAGwMAAAEAF8A6gwAAAYAYwBuDAAAAQBiAAIABwlpJl8LAJsCB2gMAAAFAGMAaQwAAAQAYwBrDAAABQBiAGoMAAADAGIAbAwAAAQAXwDqDAAABgBjAG4MAAABAGIAAAA=.',
Gw='Gweyn:BAAALgADCgQJBQAAAA==.',
Gy='Gyatsò:BAABLgAECn8aAAIYAAgJsxgwDgDsAQhoDAAABQBLAGkMAAAEAEIAawwAAAQAQABqDAAAAwBLAGwMAAADAD0AbQwAAAIAMADqDAAABABAAG4MAAABAD0AGAAICbMYMA4A7AEIaAwAAAUASwBpDAAABABCAGsMAAAEAEAAagwAAAMASwBsDAAAAwA9AG0MAAACADAA6gwAAAQAQABuDAAAAQA9AAAA.',
['Gø']='Gød:BAAALgADCgUJBQAAAA==.',
Ha='Harshdh:BAAALgAECgYJBgABLgAECggJFwAMAMgWAA==.Harshdk:BAABLgAECn8XAAIMAAgJyBbBLADfAQhoDAAAAwBIAGkMAAADAD8AawwAAAMANQBqDAAAAwA4AGwMAAADADMAbQwAAAMARQDqDAAAAwAtAG4MAAACADQADAAICcgWwSwA3wEIaAwAAAMASABpDAAAAwA/AGsMAAADADUAagwAAAMAOABsDAAAAwAzAG0MAAADAEUA6gwAAAMALQBuDAAAAgA0AAAA.',
He='Helel:BAABLgAECn8rAAMMAAYJsRdCXABBAQZoDAAACAA5AGkMAAAIADsAawwAAAcAQQBqDAAABgA7AGwMAAAHADkA6gwAAAcAPgAMAAYJgBdCXABBAQZoDAAABwA5AGkMAAAHADkAawwAAAYAQQBqDAAABQA2AGwMAAAGADkA6gwAAAYAPgAZAAYJ5RElGgANAQZoDAAAAQATAGkMAAABADsAawwAAAEAQQBqDAAAAQA7AGwMAAABACwA6gwAAAEAJwAAAA==.',
Ho='Hops:BAAALgAECgIJAgAAAA==.',
Il='Illibanger:BAAALgAECgcJBwABLgAFFAMJBwAFAGUTAA==.',
Im='Impetuous:BAAALgADCgYJDwABLgAECggJGgACANkIAA==.',
Ip='Ipokeu:BAAALgADCgQJBAAAAA==.',
Ja='Jabmöney:BAAALgAFFAEJAQAAAA==.Jaffy:BAAALgADCgYJDgAAAA==.Jamninja:BAABLgAECn8gAAIPAAgJ+h1sHQBQAghoDAAABQBTAGkMAAAFAEoAawwAAAUATwBqDAAABQBRAGwMAAAEAEkAbQwAAAIATADqDAAABQBIAG4MAAABAEsADwAICfodbB0AUAIIaAwAAAUAUwBpDAAABQBKAGsMAAAFAE8AagwAAAUAUQBsDAAABABJAG0MAAACAEwA6gwAAAUASABuDAAAAQBLAAAA.Jardalanin:BAAALgADCgEJAQAAAA==.Jaroshe:BAAALgADCgUJBQAAAA==.',
Je='Jellyfish:BAABLgAECn8VAAMaAAgJOA4fGwCIAQhoDAAAAgASAGkMAAACABAAawwAAAIAGQBqDAAAAgAUAGwMAAACACcAbQwAAAIAGwDqDAAABABGAG4MAAAFAEgAGgAICUYMHxsAiAEIaAwAAAEADgBpDAAAAQAIAGsMAAABABkAagwAAAEAFABsDAAAAQAMAG0MAAABABsA6gwAAAIARgBuDAAAAgBIAAgACAnOB8kbAGoBCGgMAAABABIAaQwAAAEAEABrDAAAAQADAGoMAAABAAYAbAwAAAEAJwBtDAAAAQAIAOoMAAACADkAbgwAAAMACQAAAA==.Jessamyn:BAAALgAECgMJAwAAAA==.',
Jh='Jhoira:BAAALgAECgYJCgAAAA==.',
Jo='Jokko:BAAALgADCgEJAgAAAA==.Jordyy:BAABLgAECn8gAAQRAAkJ3h+1EgBfAgloDAAABQBfAGkMAAAFAE4AawwAAAQAVgBqDAAABABhAGwMAAADAFcAbQwAAAIAYADqDAAABQBcAG4MAAADAFAAbwwAAAEAIgARAAgJ3h+1EgBfAghoDAAABQBfAGkMAAAEAE4AawwAAAMAVgBsDAAAAgBXAG0MAAACAGAA6gwAAAUAXABuDAAAAwBQAG8MAAABACIAEgACCfMhwRcAvgACagwAAAQAYQBsDAAAAQBWABMAAgkRE0pUAHEAAmkMAAABADsAawwAAAEAJgAAAA==.',
Ka='Kaifren:BAACLgAFFH8HAAIPAAIJ8xKaZwCoAAJoDAAABAA/AOoMAAADACEADwACCfMSmmcAqAACaAwAAAQAPwDqDAAAAwAhAC4ABAp/GAACDwAJCaIPvE0AkgEADwAJCaIPvE0AkgEAAAA=.Kalifa:BAACLgAFFH8VAAIGAAUJHh5aCgBqAQVoDAAAAwBQAGkMAAAEAEQAawwAAAQAXwBqDAAAAwBDAOoMAAAHAD8ABgAFCR4eWgoAagEFaAwAAAMAUABpDAAABABEAGsMAAAEAF8AagwAAAMAQwDqDAAABwA/AC4ABAp/LgACBgAICfUjhAQAwgIABgAICfUjhAQAwgIAAAA=.Kalinethe:BAAALgAECgEJAQAAAA==.Karatay:BAAALgADCgQJBQAAAA==.Karrod:BAAALgAECgYJCgAAAA==.Katyce:BAAALgADCgcJDQAAAA==.',
Ke='Keilani:BAAALgAECgQJBQAAAA==.',
Ki='Killeerrkap:BAAALgAECgQJBQAAAA==.Killrmiller:BAAALgADCgMJAwAAAA==.Kirajdh:BAABLgAECn8mAAIWAAkJRB1sCAC0AgloDAAABgBXAGkMAAAEAFsAawwAAAUAVQBqDAAABgBXAGwMAAAFAE8AbQwAAAIARgDqDAAABQBPAG4MAAAEAD0AbwwAAAEALQAWAAkJRB1sCAC0AgloDAAABgBXAGkMAAAEAFsAawwAAAUAVQBqDAAABgBXAGwMAAAFAE8AbQwAAAIARgDqDAAABQBPAG4MAAAEAD0AbwwAAAEALQAAAA==.Kittenmitten:BAAALgADCgQJBAAAAA==.Kiwaj:BAAALgAECgUJBQABLgAECgkJJgAWAEQdAA==.',
Ko='Komayetu:BAAALgAECgQJBAAAAA==.',
Kr='Kraas:BAAALgAECgEJAQAAAA==.Krateis:BAABLgAECn8dAAIbAAYJjwS2EAACAQZoDAAABwAJAGkMAAAGAAsAawwAAAYAEgBqDAAAAgAKAGwMAAACAAsA6gwAAAYABQAbAAYJjwS2EAACAQZoDAAABwAJAGkMAAAGAAsAawwAAAYAEgBqDAAAAgAKAGwMAAACAAsA6gwAAAYABQAAAA==.Kraéthlas:BAAALgADCgYJCgAAAA==.',
Kw='Kwonhee:BAAALgADCgMJAwAAAA==.',
La='Lanadelrey:BAAALgAECgYJAQAAAA==.Laurenth:BAAALgADCgkJFQAAAA==.Lazyace:BAAALgAECgIJBAAAAA==.',
Le='Lebenspender:BAABLgAECn8iAAIKAAYJWiI7EgBBAgZoDAAABwBTAGkMAAAGAFEAawwAAAYAWQBqDAAABQBUAGwMAAAFAF0A6gwAAAUAXwAKAAYJWiI7EgBBAgZoDAAABwBTAGkMAAAGAFEAawwAAAYAWQBqDAAABQBUAGwMAAAFAF0A6gwAAAUAXwAAAA==.Lextalonis:BAAALgAECgYJCAAAAA==.',
Li='Linkstery:BAABLgAECn8kAAMRAAgJGRpQUwDNAQhoDAAABgBXAGkMAAAGAEQAawwAAAUAVQBqDAAAAwBHAGwMAAAFAEsAbQwAAAQAIgDqDAAABQA+AG4MAAACADQAEQAHCUoYUFMAzQEHaAwAAAYAVwBpDAAABgBEAGsMAAAFAFUAbAwAAAQARQBtDAAAAQAIAOoMAAAFAD4AbgwAAAIANAATAAMJfRWwNADkAANqDAAAAwBHAGwMAAABAEsAbQwAAAMAIgAAAA==.',
Lo='Losvanknight:BAAALgAECgcJCAAAAA==.',
Lt='Lt:BAAALgADCgEJAQAAAA==.',
Ly='Lyathon:BAAALgADCgMJAwAAAA==.',
Ma='Macfluffy:BAAALgAECgQJBAAAAA==.Mactacolover:BAAALgAECgMJAwAAAA==.Madbomber:BAAALgAECgYJDgAAAA==.Maeze:BAABLgAECn8aAAICAAgJ2QiJQABjAQhoDAAABAAYAGkMAAAEABcAawwAAAQAGwBqDAAABAAbAGwMAAAEACMAbQwAAAEACQDqDAAABAASAG4MAAABABMAAgAICdkIiUAAYwEIaAwAAAQAGABpDAAABAAXAGsMAAAEABsAagwAAAQAGwBsDAAABAAjAG0MAAABAAkA6gwAAAQAEgBuDAAAAQATAAAA.Magepawk:BAAALgAECgMJAwAAAA==.Magew:BAAALgADCgQJBAAAAA==.Malandru:BAACLgAFFH8GAAIcAAQJwhQsEQA9AQRoDAAAAgBTAGkMAAACAE4AbAwAAAEAAwDqDAAAAQAvABwABAnCFCwRAD0BBGgMAAACAFMAaQwAAAIATgBsDAAAAQADAOoMAAABAC8ALgAECn8iAAMUAAgJOh91HAAzAgAUAAgJOh91HAAzAgAcAAgJIgpkOgCQAQAAAA==.Mawwowow:BAABLgAECn8cAAIWAAYJOhu2NwBsAQZoDAAABQA4AGkMAAAFAFEAawwAAAUASABqDAAABABDAGwMAAAEAFIA6gwAAAUANwAWAAYJOhu2NwBsAQZoDAAABQA4AGkMAAAFAFEAawwAAAUASABqDAAABABDAGwMAAAEAFIA6gwAAAUANwAAAA==.Maximillius:BAAALgAECgQJBQABLgAECgcJGQAMALAeAA==.Mayjoraid:BAAALgAECgEJAgAAAA==.',
Me='Meekah:BAABLgAECn8zAAIIAAgJox9pBADkAghoDAAABwBHAGkMAAAHAFgAawwAAAcAUwBqDAAABgBRAGwMAAAGAFoAbQwAAAUAVgDqDAAACABWAG4MAAAFADwACAAICaMfaQQA5AIIaAwAAAcARwBpDAAABwBYAGsMAAAHAFMAagwAAAYAUQBsDAAABgBaAG0MAAAFAFYA6gwAAAgAVgBuDAAABQA8AAAA.Melbrosha:BAAALgAECgUJCwAAAA==.Melodine:BAAALgADCgEJAQAAAA==.Melyndia:BAAALgAECgUJBQABLgAECggJIQAdAAEgAA==.Meriks:BAAALgAECgQJDAABLgAECgUJDQAVAAAAAA==.',
Mi='Mickspooky:BAACLgAFFH8UAAIMAAQJtxSBNQBCAQRoDAAAAwA/AGkMAAAHAEoAawwAAAQAFwDqDAAABgAyAAwABAm3FIE1AEIBBGgMAAADAD8AaQwAAAcASgBrDAAABAAXAOoMAAAGADIALgAECn8nAAMMAAgJmR9KKQCVAgAMAAgJmR9KKQCVAgAZAAMJjxOIJgCoAAABLgAECgMJAwAVAAAAAA==.Mickstormy:BAAALgAECgMJAwAAAA==.Mierin:BAAALgAECgQJBwAAAA==.Milfy:BAAALgADCgQJBAABLgADCgUJBQAVAAAAAA==.Mintie:BAABLgAECn8eAAIeAAYJlBMJEwALAQZoDAAABgApAGkMAAAGAC8AawwAAAYANgBqDAAABAA3AGwMAAADAC8A6gwAAAUAPAAeAAYJlBMJEwALAQZoDAAABgApAGkMAAAGAC8AawwAAAYANgBqDAAABAA3AGwMAAADAC8A6gwAAAUAPAAAAA==.',
Mo='Moozylla:BAAALgAECggJCQAAAA==.Morrïgan:BAAALgAECgIJAgAAAA==.Mossiah:BAAALgAECgEJAQAAAA==.',
Mu='Muriggy:BAAALgADCgIJAgAAAA==.',
My='Mylarna:BAABLgAECn8aAAIHAAgJ0Ai/KAAuAQhoDAAABgAiAGkMAAAFAC8AawwAAAQADQBqDAAAAgAUAGwMAAABAAcAbQwAAAIAEgDqDAAABQAdAG4MAAABAAcABwAICdAIvygALgEIaAwAAAYAIgBpDAAABQAvAGsMAAAEAA0AagwAAAIAFABsDAAAAQAHAG0MAAACABIA6gwAAAUAHQBuDAAAAQAHAAAA.Mynx:BAAALgAECgcJEQAAAA==.',
['Må']='Mårsh:BAAALgAECgEJAQAAAA==.',
Na='Nadira:BAAALgADCgYJBgABLgAECgYJFgAZAKMVAA==.Nahkti:BAAALgADCgcJBwAAAA==.Nazarick:BAAALgAECgYJCAAAAA==.',
Ne='Neona:BAAALgAECgQJBAAAAA==.Neriv:BAAALgAECgYJDAAAAA==.Nexaladin:BAAALgAECgEJAQAAAA==.',
Ni='Nimbus:BAAALgAECgMJBAABLgAFFAcJEwANACUUAA==.Nixii:BAABLgAECn8dAAIGAAYJGwzQLQDzAAZoDAAABgAoAGkMAAAFACQAawwAAAUAJgBqDAAABAAeAGwMAAAEAAkA6gwAAAUAHgAGAAYJGwzQLQDzAAZoDAAABgAoAGkMAAAFACQAawwAAAUAJgBqDAAABAAeAGwMAAAEAAkA6gwAAAUAHgAAAA==.',
No='Nocticula:BAABLgAECn8qAAIaAAgJ9AkyIQBUAQhoDAAABwA2AGkMAAAGABkAawwAAAcAGABqDAAABgASAGwMAAAFAAgAbQwAAAIACgDqDAAABgA5AG4MAAADAAMAGgAICfQJMiEAVAEIaAwAAAcANgBpDAAABgAZAGsMAAAHABgAagwAAAYAEgBsDAAABQAIAG0MAAACAAoA6gwAAAYAOQBuDAAAAwADAAAA.',
Ny='Nyet:BAACLgAFFH8PAAMEAAUJOBBpEwAmAQVoDAAABABIAGkMAAAEABEAawwAAAIALQBqDAAAAQATAOoMAAAEAB4ABAAFCTgQaRMAJgEFaAwAAAQASABpDAAAAwARAGsMAAACAC0AagwAAAEAEwDqDAAABAAeAAUAAQliBoMeAEcAAWkMAAABABAALgAECn8cAAIEAAkJvxtcHABqAgAEAAkJvxtcHABqAgAAAA==.Nythraxia:BAAALgAECgMJAwAAAA==.Nyxiria:BAAALgADCgcJGgAAAA==.',
['Nò']='Nòir:BAAALgAECgMJAwAAAA==.',
Oh='Ohnarr:BAAALgAECgMJAwAAAA==.',
Ok='Oktoberfist:BAAALgAECgcJBwABLgAECggJAwAVAAAAAA==.',
Or='Orine:BAAALgAECggJDwAAAA==.Orioz:BAACLgAFFH8OAAIJAAQJWB62AgBdAQRoDAAABQBeAGkMAAAEAEAAawwAAAMARwDqDAAAAgBPAAkABAlYHrYCAF0BBGgMAAAFAF4AaQwAAAQAQABrDAAAAwBHAOoMAAACAE8ALgAECn8kAAIJAAgJNCLxAwDoAgAJAAgJNCLxAwDoAgAAAA==.',
Os='Osiras:BAAALgAECgUJBQABLgAECgYJCAAVAAAAAA==.',
Ow='Owun:BAAALgADCgEJAQAAAA==.',
Oz='Oz:BAAALgADCgkJCgAAAA==.',
Pa='Pandapal:BAAALgAECgEJAgAAAA==.Pathbrin:BAAALgADCgEJAQAAAA==.Pauliee:BAAALgADCgMJAwAAAA==.Pawkah:BAAALgAECgEJAgAAAA==.Paytowintaxi:BAAALgADCgEJAQAAAA==.',
Pe='Peyton:BAAALgADCggJEQAAAA==.',
Pr='Protection:BAAALgADCgUJBgAAAA==.',
Ps='Psychoman:BAAALgADCgMJAwABLgAFFAUJDgAGANAbAA==.Psychomurda:BAABLgAECn8cAAMUAAYJpAtYegAPAQZoDAAABQAoAGkMAAAGACQAawwAAAUAHABqDAAAAwAcAGwMAAACABMA6gwAAAcAFwAUAAYJpAtYegAPAQZoDAAABAAoAGkMAAAFACQAawwAAAQAHABqDAAAAwAcAGwMAAACABMA6gwAAAcAFwAfAAMJ/gcmKABuAANoDAAAAQASAGkMAAABABIAawwAAAEAGAABLgAECggJMwAIAKMfAA==.',
Ra='Raign:BAAALgAECgEJAgAAAA==.Ratpack:BAAALgAECggJAwAAAA==.',
Re='Renfri:BAAALgADCgYJDgAAAA==.',
Ro='Robel:BAAALgAECgUJBgAAAA==.Ronaldbruce:BAAALgAECgQJBQAAAA==.Roupert:BAAALgAECgEJAQAAAA==.',
Sa='Sao:BAAALgAECgIJAgAAAA==.Sardrian:BAAALgAECgUJCwAAAA==.',
Se='Seimie:BAABLgAECn8aAAITAAgJoQnJCwAlAQhoDAAABQAzAGkMAAAEABcAawwAAAMAGABqDAAAAwAZAGwMAAADABEAbQwAAAEACwDqDAAABgAmAG4MAAABAAQAEwAICaEJyQsAJQEIaAwAAAUAMwBpDAAABAAXAGsMAAADABgAagwAAAMAGQBsDAAAAwARAG0MAAABAAsA6gwAAAYAJgBuDAAAAQAEAAAA.Selithvia:BAAALgAECgYJDQAAAA==.Senethotsare:BAAALgAECgQJBQAAAA==.Sethen:BAAALgADCgEJAQAAAA==.',
Sh='Shaboudi:BAAALgADCgEJAQABLgAECgQJBQAVAAAAAA==.Shamalicious:BAAALgADCgEJAQAAAA==.Shammwow:BAAALgAECgEJAQAAAA==.Shaofikx:BAABLgAECn8kAAIgAAgJlgqMIABBAQhoDAAABwAYAGkMAAAFACsAawwAAAYAFgBqDAAABAARAGwMAAAFACcAbQwAAAIAFADqDAAABQAQAG4MAAACABcAIAAICZYKjCAAQQEIaAwAAAcAGABpDAAABQArAGsMAAAGABYAagwAAAQAEQBsDAAABQAnAG0MAAACABQA6gwAAAUAEABuDAAAAgAXAAAA.Shenknarok:BAABLgAECn8rAAIhAAYJ1xuVCgCUAQZoDAAACQBPAGkMAAAHAFEAawwAAAcAUQBqDAAABwBFAGwMAAAGADcA6gwAAAcAOgAhAAYJ1xuVCgCUAQZoDAAACQBPAGkMAAAHAFEAawwAAAcAUQBqDAAABwBFAGwMAAAGADcA6gwAAAcAOgAAAA==.Sherryl:BAABLgAECn8hAAIdAAYJlQ6vQwAaAQZoDAAABgAyAGkMAAAGACAAawwAAAYAMQBqDAAABQAYAGwMAAAFAB0A6gwAAAUAJAAdAAYJlQ6vQwAaAQZoDAAABgAyAGkMAAAGACAAawwAAAYAMQBqDAAABQAYAGwMAAAFAB0A6gwAAAUAJAAAAA==.Shmooples:BAAALgAECgEJAQAAAA==.Shunei:BAAALgADCgQJBAAAAA==.',
Si='Siema:BAAALgAECgMJAwAAAA==.Sigurd:BAAALgADCggJBwAAAA==.',
Sk='Skdragon:BAAALgADCgEJAQAAAA==.Skyari:BAABLgAECn8ZAAIEAAYJ8yQqEAAHAgZoDAAABABfAGkMAAAFAF8AawwAAAUAYQBqDAAABABbAGwMAAAEAFgA6gwAAAMAXwAEAAYJ8yQqEAAHAgZoDAAABABfAGkMAAAFAF8AawwAAAUAYQBqDAAABABbAGwMAAAEAFgA6gwAAAMAXwAAAA==.Skyarii:BAAALgAECgQJBwABLgAECgYJGQAEAPMkAA==.',
So='Songweaver:BAAALgAECgEJAgAAAA==.Soulminion:BAABLgAECn8aAAIMAAYJXQIwrACkAAZoDAAABwAEAGkMAAAGAAoAawwAAAYABwBqDAAAAQACAGwMAAABAAQA6gwAAAUAAwAMAAYJXQIwrACkAAZoDAAABwAEAGkMAAAGAAoAawwAAAYABwBqDAAAAQACAGwMAAABAAQA6gwAAAUAAwAAAA==.',
Sp='Spiritshard:BAAALgADCgcJEgAAAA==.Splashmountn:BAEALgAECgYJCgAAAA==.',
St='Sthane:BAAALgADCgEJAQAAAA==.Sthise:BAAALgAECgMJAwAAAA==.',
Su='Subtlety:BAAALgAECgkJEQAAAA==.Sulfurya:BAAALgAECgQJBQAAAA==.',
Sy='Sykoman:BAACLgAFFH8OAAMGAAUJ0BsFDABcAQVoDAAABABTAGkMAAACADgAawwAAAIAVABqDAAAAQAYAOoMAAAFAD0ABgAFCdAbBQwAXAEFaAwAAAQAUwBpDAAAAgA4AGsMAAACAFQAagwAAAEAGADqDAAABAA9AB0AAQnlAD1QAC8AAeoMAAABAAIALgAECn8hAAIGAAgJEyJ9CwDfAgAGAAgJEyJ9CwDfAgAAAA==.',
['Sì']='Sìleñtclãw:BAAALgAECgcJDQAAAA==.',
Ta='Talarina:BAAALgADCgYJBgAAAA==.Taylen:BAAALgADCgcJBwAAAA==.',
Te='Terumi:BAAALgAECgIJAgAAAA==.Teverion:BAAALgADCgcJCwAAAA==.',
Th='Therkage:BAAALgADCgcJEAAAAA==.Thesios:BAAALgADCgcJBwAAAA==.Thickthighs:BAAALgAECgEJAQAAAA==.Thizz:BAABLgAECn8cAAIEAAYJPiD/KQASAgZoDAAACQBaAGkMAAAIAF4AawwAAAMAUQBqDAAAAQBDAGwMAAACAE0A6gwAAAUARAAEAAYJPiD/KQASAgZoDAAACQBaAGkMAAAIAF4AawwAAAMAUQBqDAAAAQBDAGwMAAACAE0A6gwAAAUARAABLgAFFAEJAQAVAAAAAA==.',
Ti='Tinksy:BAAALgADCgEJAQABLgADCgUJBQAVAAAAAA==.',
To='Toeto:BAAALgADCgYJBgAAAA==.Toetoeto:BAAALgADCggJCwAAAA==.Toetoetoete:BAAALgADCgYJBgAAAA==.Tooe:BAAALgAECgMJAwAAAA==.Torquei:BAAALgAECgYJBgAAAA==.Toxious:BAAALgAECgQJBAAAAA==.',
Tp='Tpaman:BAAALgAECgYJBgAAAA==.Tpdruid:BAAALgAECgMJAwAAAA==.',
Ts='Tsjuda:BAAALgADCgEJAQAAAA==.Tsjudii:BAAALgADCgYJBgAAAA==.Tsjudilla:BAAALgADCgEJAQAAAA==.',
Tu='Tujefe:BAAALgAECgYJCgAAAA==.',
Ug='Ugzlug:BAAALgADCgEJAQAAAA==.',
Un='Unholydk:BAAALgAECgUJBwABLgAECgYJCwAVAAAAAA==.',
Va='Vacuus:BAABLgAECn8XAAISAAgJRwibBwBQAQhoDAAAAwARAGkMAAADAB4AawwAAAMAKQBqDAAAAwATAGwMAAAEABEAbQwAAAIACwDqDAAAAwAOAG4MAAACAA4AEgAICUcImwcAUAEIaAwAAAMAEQBpDAAAAwAeAGsMAAADACkAagwAAAMAEwBsDAAABAARAG0MAAACAAsA6gwAAAMADgBuDAAAAgAOAAAA.Vahldire:BAAALgAECgUJCQAAAA==.Valeri:BAAALgADCggJCwAAAA==.Varkon:BAAALgADCgMJAwAAAA==.Varn:BAAALgADCggJCAAAAA==.Varthion:BAAALgAECgYJBgAAAA==.',
Ve='Velastrasza:BAAALgADCgcJBwAAAA==.Velkethria:BAAALgAECgYJEwAAAA==.Velnyxia:BAAALgAECgQJBQAAAA==.Velovañ:BAAALgADCgEJAQAAAA==.Velthyria:BAAALgADCgkJCQAAAA==.Vestara:BAAALgAECggJCAAAAA==.Veylara:BAABLgAECn8hAAIRAAYJxwYIegDkAAZoDAAABgAQAGkMAAAGABcAawwAAAYAEgBqDAAABQAXAGwMAAAFAAsA6gwAAAUAEAARAAYJxwYIegDkAAZoDAAABgAQAGkMAAAGABcAawwAAAYAEgBqDAAABQAXAGwMAAAFAAsA6gwAAAUAEAAAAA==.',
Vi='Viryda:BAAALgADCggJFgABLgAECggJJgAeAJgJAA==.',
Vo='Voidgram:BAAALgADCgQJBAAAAA==.',
Wa='Wartimebeast:BAAALgAECgUJEAAAAA==.',
We='Welp:BAAALgAECgEJAQAAAA==.',
Wi='Windwalker:BAAALgAECgcJCAAAAA==.Wisteria:BAABLgAECn8zAAMTAAgJiRZiCwALAghoDAAABwBXAGkMAAAJAD8AawwAAAkAPQBqDAAABwAmAGwMAAAGADkAbQwAAAMAEgDqDAAABwBcAG4MAAADABYAEwAICYkWYgsACwIIaAwAAAcAVwBpDAAACQA/AGsMAAAJAD0AagwAAAcAJgBsDAAABQA5AG0MAAADABIA6gwAAAcAXABuDAAAAwAWABIAAQnDATM4ABoAAWwMAAABAAQAAS4AAwoECQQAFQAAAAA=.',
Wo='Womplock:BAAALgAECgQJBgAAAA==.',
Wr='Wrâth:BAABLgAECn8oAAIPAAgJmRNfOwDKAQhoDAAACAA7AGkMAAAEACoAawwAAAQANgBqDAAABgA4AGwMAAAFADEAbQwAAAUAMwDqDAAABgAoAG4MAAACADQADwAICZkTXzsAygEIaAwAAAgAOwBpDAAABAAqAGsMAAAEADYAagwAAAYAOABsDAAABQAxAG0MAAAFADMA6gwAAAYAKABuDAAAAgA0AAAA.',
Wy='Wydwen:BAAALgAECgEJAQAAAA==.',
Xe='Xenro:BAAALgADCgcJBgAAAA==.',
Xi='Xirus:BAAALgADCgQJAQAAAA==.',
Xu='Xulfred:BAAALgADCgIJAgAAAA==.',
Ya='Yavana:BAAALgADCgEJAQAAAA==.',
Zi='Zigzogg:BAAALgADCgEJAQAAAA==.Zilida:BAAALgADCgEJAQAAAA==.Ziwee:BAABLgAECn8aAAIgAAgJvBqBFQBeAghoDAAABQBaAGkMAAAFAFkAawwAAAQATQBqDAAAAwBLAGwMAAADAEIAbQwAAAEALADqDAAABABNAG4MAAABACEAIAAICbwagRUAXgIIaAwAAAUAWgBpDAAABQBZAGsMAAAEAE0AagwAAAMASwBsDAAAAwBCAG0MAAABACwA6gwAAAQATQBuDAAAAQAhAAEuAAQKCAkaACAAvBoA.',
Zo='Zorana:BAAALgADCgEJAQAAAA==.',
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
