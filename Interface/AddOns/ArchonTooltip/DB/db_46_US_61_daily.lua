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
local provider = {region='US',realm='Darrowmere',name='US',type='daily',zone=46,date='2026-05-10',data={Ab='Abaddonmoon:BAABLgAECn8XAAIBAAYJOwcyDADyAAZoDAAABQAUAGkMAAAEABYAawwAAAQAGgBqDAAAAwARAGwMAAADAAgA6gwAAAQADgABAAYJOwcyDADyAAZoDAAABQAUAGkMAAAEABYAawwAAAQAGgBqDAAAAwARAGwMAAADAAgA6gwAAAQADgAAAA==.',
Ad='Addvar:BAAALgADCgEJAQAAAA==.Adelost:BAAALgAECgQJBQAAAA==.',
Ah='Ahalina:BAAALgAECgEJAQAAAA==.Ahnari:BAACLgAFFH8FAAICAAMJdgJ6DwDMAANoDAAAAgAIAGkMAAACAAMAawwAAAEABgACAAMJdgJ6DwDMAANoDAAAAgAIAGkMAAACAAMAawwAAAEABgAuAAQKfxUAAwIACAlAEVQ9ALkBAAIACAlAEVQ9ALkBAAMABAm8AoQmAIsAAAAA.',
Ai='Ailinaa:BAACLgAFFH8YAAMEAAYJoBh4BQCbAQZoDAAAAwBDAGkMAAAFAEUAawwAAAQAPQBqDAAABQAjAGwMAAACABwA6gwAAAUAWAAEAAUJBRx4BQCbAQVoDAAAAwBDAGkMAAACAEUAawwAAAQAPQBqDAAAAwANAOoMAAAFAFgABQADCeQM5xIAnwADaQwAAAMAJQBqDAAAAgAjAGwMAAACABwALgAECn8gAAMEAAkJJB/KFQCfAgAEAAgJKR/KFQCfAgAFAAQJ4xdtEwAvAQAAAA==.',
Ak='Akalifato:BAAALgAFFAMJAwABLgAFFAUJFQAGAB4eAA==.Akroma:BAAALgAECgIJAwAAAA==.',
Al='Alariya:BAAALgAECgUJBQAAAA==.Alerat:BAAALgADCgMJAwABLgAECggJGgAHANAIAA==.Alistin:BAAALgAECgcJCAAAAA==.Alone:BAAALgADCgQJAwAAAA==.Alstir:BAAALgAECgEJAQAAAA==.',
Am='Amaryllis:BAAALgAECgEJAQAAAA==.Ambivalent:BAAALgAECgQJBgAAAA==.',
Ar='Aradin:BAAALgADCgcJCAAAAA==.Archanfel:BAABLgAECn8gAAIDAAYJ5wxPHQAjAQZoDAAABgAiAGkMAAAGAB4AawwAAAYALwBqDAAABQANAGwMAAAEAAwA6gwAAAUAKAADAAYJ5wxPHQAjAQZoDAAABgAiAGkMAAAGAB4AawwAAAYALwBqDAAABQANAGwMAAAEAAwA6gwAAAUAKAAAAA==.Argasha:BAAALgADCgUJBQAAAA==.',
As='Asriel:BAAALgAECgYJBgAAAA==.',
Aw='Awsomweorc:BAAALgADCgEJAQAAAA==.',
Ay='Ayonna:BAAALgAECgUJDAAAAA==.',
Az='Azar:BAAALgADCgUJBQAAAA==.',
Ba='Bandie:BAAALgAECgUJDAAAAA==.Barksalot:BAAALgADCgEJAQAAAA==.Barrakum:BAAALgAECgUJCwAAAA==.Bayn:BAAALgADCgQJCQAAAA==.',
Be='Beeftruck:BAACLgAFFH8HAAMFAAMJZRMFFgB/AANoDAAAAwAxAGkMAAACAD4A6gwAAAIAJAAEAAIJ+BWdJACcAAJoDAAAAgAxAGkMAAACAD4ABQACCbcIBRYAfwACaAwAAAEACADqDAAAAgAkAC4ABAp/IQADBQAHCfohkQYABwIABQAHCfIdkQYABwIABAAFCacgHSsALAEAAAA=.Belletrixx:BAAALgAECgYJEgAAAA==.Berried:BAABLgAECn8uAAIIAAkJRx5AAwAMAwloDAAACABeAGkMAAAHAFcAawwAAAgAUgBqDAAABQBOAGwMAAAEAFAAbQwAAAMARgDqDAAABwBYAG4MAAADADYAbwwAAAEAPAAIAAkJRx5AAwAMAwloDAAACABeAGkMAAAHAFcAawwAAAgAUgBqDAAABQBOAGwMAAAEAFAAbQwAAAMARgDqDAAABwBYAG4MAAADADYAbwwAAAEAPAAAAA==.',
Bi='Biigmâc:BAAALgAECgcJEAAAAA==.Biminem:BAABLgAECn8YAAIJAAcJShVlCQCSAQdoDAAABgBPAGkMAAADAD8AawwAAAMAOABqDAAAAwA3AGwMAAAEAEIAbQwAAAEAGADqDAAABAAkAAkABwlKFWUJAJIBB2gMAAAGAE8AaQwAAAMAPwBrDAAAAwA4AGoMAAADADcAbAwAAAQAQgBtDAAAAQAYAOoMAAAEACQAAAA=.',
Bl='Black:BAAALgAECgYJDAAAAA==.Blackwidow:BAAALgAECgMJAwAAAA==.Bloodshöt:BAAALgAECgYJEQABLgAECggJHgAEAEsVAA==.',
Bo='Bodak:BAABLgAECn8bAAIKAAYJ5hnONwCjAQZoDAAABQA7AGkMAAAFADgAawwAAAUAVwBqDAAABABOAGwMAAAEACYA6gwAAAQATQAKAAYJ5hnONwCjAQZoDAAABQA7AGkMAAAFADgAawwAAAUAVwBqDAAABABOAGwMAAAEACYA6gwAAAQATQAAAA==.Boricua:BAAALgAECgEJAgAAAA==.',
Br='Brakun:BAAALgADCgIJAgAAAA==.Broris:BAAALgAECgMJAwAAAA==.',
Ca='Calamari:BAAALgADCgQJBAAAAA==.Calistarius:BAABLgAECn8UAAILAAgJlBDTEABcAQhoDAAAAwA4AGkMAAADADgAawwAAAMAKABqDAAAAwBOAGwMAAADABoAbQwAAAEAKADqDAAAAwArAG4MAAABAB8ACwAICZQQ0xAAXAEIaAwAAAMAOABpDAAAAwA4AGsMAAADACgAagwAAAMATgBsDAAAAwAaAG0MAAABACgA6gwAAAMAKwBuDAAAAQAfAAAA.Caliste:BAAALgADCgIJAgABLgAFFAQJDgAJAFgeAA==.Calityy:BAAALgADCgYJBgABLgAFFAYJEwADAIofAA==.Camine:BAABLgAECn8mAAIMAAgJshlyKADoAQhoDAAABwBfAGkMAAAGAD8AawwAAAYAOwBqDAAABQBOAGwMAAAFAFUAbQwAAAEALgDqDAAABQAwAG4MAAADADwADAAICbIZcigA6AEIaAwAAAcAXwBpDAAABgA/AGsMAAAGADsAagwAAAUATgBsDAAABQBVAG0MAAABAC4A6gwAAAUAMABuDAAAAwA8AAAA.Carise:BAAALgAECgQJBAAAAA==.Castalasaras:BAAALgAECgMJAwAAAA==.Castorsilver:BAAALgAECgEJAQAAAA==.',
Ce='Certified:BAAALgAECgUJBQAAAA==.',
Ch='Chickeny:BAAALgADCgEJAQAAAA==.Choppstik:BAAALgAECgYJDAAAAA==.',
Co='Coldslayerck:BAAALgADCgkJCQAAAA==.Constäntine:BAAALgAECgQJBAAAAA==.Coriolis:BAABLgAECn8kAAMNAAYJ3hlcGwBuAQZoDAAABgBQAGkMAAAHAEEAawwAAAYAQwBqDAAABQAxAGwMAAAFADgA6gwAAAcAPQANAAYJ3hlcGwBuAQZoDAAABQBQAGkMAAAFAEEAawwAAAYAQwBqDAAABQAxAGwMAAAFADgA6gwAAAUAPQAOAAMJggrxMACPAANoDAAAAQAgAGkMAAACABEA6gwAAAIAHQAAAA==.',
Cr='Crowléy:BAAALgAECgUJDAAAAA==.',
Cu='Cuddlyowl:BAABLgAECn8XAAIPAAcJwQ4EqwCFAQdoDAAAAwA4AGkMAAAEAC4AawwAAAMAMQBqDAAABAAnAGwMAAACABgAbQwAAAIACwDqDAAABQAkAA8ABwnBDgSrAIUBB2gMAAADADgAaQwAAAQALgBrDAAAAwAxAGoMAAAEACcAbAwAAAIAGABtDAAAAgALAOoMAAAFACQAAAA=.',
Da='Dagnamagus:BAAALgAECgQJBQAAAA==.Daliann:BAAALgAECgYJCQAAAA==.Damnation:BAAALgAECgYJBwAAAA==.Dangerduck:BAAALgAECgUJDAAAAA==.Darktruth:BAAALgADCgMJAwAAAA==.Dartes:BAAALgAECgYJCwAAAA==.Dashe:BAAALgAECgcJAQAAAA==.',
De='Deathcokie:BAAALgAECgYJDgAAAA==.Deatho:BAABLgAECn8kAAMLAAYJ9ybxBQBAAgZoDAAABgBjAGkMAAAHAGMAawwAAAYAYwBqDAAABQBjAGwMAAAFAGMA6gwAAAcAYwALAAYJ9ybxBQBAAgZoDAAABgBjAGkMAAAHAGMAawwAAAYAYwBqDAAABQBjAGwMAAAFAGMA6gwAAAYAYwAEAAEJCSNvnQBKAAHqDAAAAQBZAAAA.Deathstoned:BAAALgADCgQJBQAAAA==.Deimos:BAAALgADCgQJBAAAAA==.',
Di='Diamondshard:BAAALgAECgIJAwAAAA==.',
Dr='Draegov:BAAALgADCgYJBgAAAA==.Draeth:BAAALgADCgcJDQAAAA==.Dreadful:BAAALgAECgYJDQAAAA==.Dreylan:BAAALgADCgcJBwAAAA==.Dreyra:BAAALgADCgcJBwABLgAECgkJLQADAL8eAA==.Drosof:BAAALgADCgYJCwAAAA==.Drow:BAAALgADCgcJBwAAAA==.',
Du='Dukalioth:BAABLgAECn8XAAIQAAYJdA0BHAAJAQZoDAAABQAmAGkMAAAEADEAawwAAAUAHgBqDAAAAwASAGwMAAADABMA6gwAAAMAIgAQAAYJdA0BHAAJAQZoDAAABQAmAGkMAAAEADEAawwAAAUAHgBqDAAAAwASAGwMAAADABMA6gwAAAMAIgAAAA==.',
['Dê']='Dêcay:BAACLgAFFH8PAAIMAAUJCyI4FwB+AQVoDAAABQBWAGkMAAAEAF4AawwAAAIAXQBqDAAAAQAtAOoMAAADAEkADAAFCQsiOBcAfgEFaAwAAAUAVgBpDAAABABeAGsMAAACAF0AagwAAAEALQDqDAAAAwBJAC4ABAp/IwADDAAJCTYgERgA6wIADAAICf0hERgA6wIAAQADCfQYAAsA8gAAAAA=.',
['Dö']='Döctorfate:BAAALgAECgYJBgAAAA==.',
Ef='Effinsoldier:BAAALgAECgUJDQAAAA==.',
Ek='Ekko:BAAALgADCgIJAgAAAA==.',
El='Ellyy:BAAALgADCgIJAgAAAA==.Elvira:BAAALgAECgQJBQAAAA==.',
En='Endlessagony:BAABLgAECn8eAAIMAAkJBx4sIADBAgloDAAABQBYAGkMAAADAF4AawwAAAMAVQBqDAAAAwBjAGwMAAAEAE8AbQwAAAIAJQDqDAAABABKAG4MAAAEAEsAbwwAAAIATgAMAAkJBx4sIADBAgloDAAABQBYAGkMAAADAF4AawwAAAMAVQBqDAAAAwBjAGwMAAAEAE8AbQwAAAIAJQDqDAAABABKAG4MAAAEAEsAbwwAAAIATgAAAA==.Endlessice:BAAALgAECgQJBAAAAA==.Enyo:BAABLgAECn8fAAQRAAYJ3R8NKQDIAQZoDAAABQBdAGkMAAAGAEsAawwAAAYAUABqDAAABABMAGwMAAAFAE4A6gwAAAUAUAARAAYJ3R8NKQDIAQZoDAAABQBdAGkMAAAFAEsAawwAAAUAUABqDAAAAQA5AGwMAAAFAE4A6gwAAAUAUAASAAEJAAA1JwBVAAFqDAAAAwBMABMAAgl4BnpeAFMAAmkMAAABABAAawwAAAEAEAAAAA==.',
Er='Erathas:BAABLgAECn8ZAAIUAAkJsRHEYQC/AQloDAAAAwAWAGkMAAADACAAawwAAAMAKQBqDAAAAgASAGwMAAAEAEAAbQwAAAIAJwDqDAAABQA9AG4MAAACADoAbwwAAAEAKgAUAAkJsRHEYQC/AQloDAAAAwAWAGkMAAADACAAawwAAAMAKQBqDAAAAgASAGwMAAAEAEAAbQwAAAIAJwDqDAAABQA9AG4MAAACADoAbwwAAAEAKgAAAA==.',
Fa='Falandril:BAAALgAECggJDwAAAA==.Fasriel:BAAALgAECgIJAgAAAA==.',
Fe='Feata:BAAALgAECgEJAQABLgAECgMJAwAVAAAAAA==.Felston:BAAALgADCgUJBQAAAA==.',
Fi='Fiyero:BAABLgAECn8mAAMEAAkJMQ40FwC1AQloDAAABwAmAGkMAAAHACEAawwAAAYAIgBqDAAABAAgAGwMAAADADYAbQwAAAEAEADqDAAABgAfAG4MAAADADUAbwwAAAEAHQAEAAkJMQ40FwC1AQloDAAABQAmAGkMAAAGACEAawwAAAUAIgBqDAAAAwAgAGwMAAACADYAbQwAAAEAEADqDAAABQAfAG4MAAACADUAbwwAAAEAHQAFAAcJwgQrJQDEAAdoDAAAAgAYAGkMAAABAAUAawwAAAEABgBqDAAAAQAQAGwMAAABABMA6gwAAAEACQBuDAAAAQAHAAAA.',
Fl='Flagcrazed:BAAALgADCgUJBQAAAA==.Fleabath:BAAALgAECgUJCQABLgAECggJGgACANkIAA==.Fluffypyro:BAAALgADCgYJBgAAAA==.',
Fo='Forëplây:BAAALgAECgMJBAAAAA==.Foughum:BAAALgADCgUJBQABLgAECgMJAwAVAAAAAA==.',
Fr='Friedcheekin:BAAALgADCgUJBQAAAA==.',
Fu='Fury:BAAALgADCgEJAQAAAA==.',
Ga='Galdames:BAAALgADCgQJBAAAAA==.',
Ge='Gedien:BAAALgAECgYJCQAAAA==.',
Gi='Gilforty:BAABLgAECn8YAAITAAcJ0BbSBQCkAQdoDAAABABDAGkMAAAEAEwAawwAAAQANwBqDAAABAAhAGwMAAADAD4AbQwAAAEAFQDqDAAABABDABMABwnQFtIFAKQBB2gMAAAEAEMAaQwAAAQATABrDAAABAA3AGoMAAAEACEAbAwAAAMAPgBtDAAAAQAVAOoMAAAEAEMAAAA=.',
Gl='Glep:BAAALgAECgIJAgABLgAECgkJJgAWAEQdAA==.Gloriosa:BAABLgAECn8vAAIXAAkJBQ7uFQC0AQloDAAABwAnAGkMAAAHADMAawwAAAcALgBqDAAABgAoAGwMAAAGABMAbQwAAAMAFQDqDAAABwA6AG4MAAADABYAbwwAAAEAFwAXAAkJBQ7uFQC0AQloDAAABwAnAGkMAAAHADMAawwAAAcALgBqDAAABgAoAGwMAAAGABMAbQwAAAMAFQDqDAAABwA6AG4MAAADABYAbwwAAAEAFwAAAA==.',
Gv='Gvendalyn:BAABLgAECn8cAAICAAcJaSY9CgCZAgdoDAAABQBjAGkMAAAEAGMAawwAAAUAYgBqDAAAAwBiAGwMAAAEAF8A6gwAAAYAYwBuDAAAAQBiAAIABwlpJj0KAJkCB2gMAAAFAGMAaQwAAAQAYwBrDAAABQBiAGoMAAADAGIAbAwAAAQAXwDqDAAABgBjAG4MAAABAGIAAAA=.',
Gw='Gweyn:BAAALgADCgQJBQAAAA==.',
Gy='Gyatsò:BAABLgAECn8ZAAIYAAgJsxhjDQDtAQhoDAAABQBLAGkMAAAEAEIAawwAAAQAQABqDAAAAwBLAGwMAAADAD0AbQwAAAIAMADqDAAAAwBAAG4MAAABAD0AGAAICbMYYw0A7QEIaAwAAAUASwBpDAAABABCAGsMAAAEAEAAagwAAAMASwBsDAAAAwA9AG0MAAACADAA6gwAAAMAQABuDAAAAQA9AAAA.',
['Gø']='Gød:BAAALgADCgUJBQAAAA==.',
Ha='Harshdh:BAAALgAECgYJBgABLgAECggJFwAMAMgWAA==.Harshdk:BAABLgAECn8XAAIMAAgJyBZhKgDfAQhoDAAAAwBIAGkMAAADAD8AawwAAAMANQBqDAAAAwA4AGwMAAADADMAbQwAAAMARQDqDAAAAwAtAG4MAAACADQADAAICcgWYSoA3wEIaAwAAAMASABpDAAAAwA/AGsMAAADADUAagwAAAMAOABsDAAAAwAzAG0MAAADAEUA6gwAAAMALQBuDAAAAgA0AAAA.',
He='Helel:BAABLgAECn8qAAMMAAYJmxeVWABBAQZoDAAACAA5AGkMAAAIADsAawwAAAcAQQBqDAAABgA7AGwMAAAGADgA6gwAAAcAPgAMAAYJaheVWABBAQZoDAAABwA5AGkMAAAHADkAawwAAAYAQQBqDAAABQA2AGwMAAAFADgA6gwAAAYAPgAZAAYJ5REaGQANAQZoDAAAAQATAGkMAAABADsAawwAAAEAQQBqDAAAAQA7AGwMAAABACwA6gwAAAEAJwAAAA==.',
Ho='Hops:BAAALgAECgIJAgAAAA==.',
Il='Illibanger:BAAALgAECgcJBwABLgAFFAMJBwAFAGUTAA==.',
Im='Impetuous:BAAALgADCgYJDwABLgAECggJGgACANkIAA==.',
Ip='Ipokeu:BAAALgADCgQJBAAAAA==.',
Ja='Jabmöney:BAAALgAFFAEJAQAAAA==.Jaffy:BAAALgADCgYJDgAAAA==.Jamninja:BAABLgAECn8fAAIPAAcJCB6sLAD2AQdoDAAABQBTAGkMAAAFAEoAawwAAAUATwBqDAAABQBRAGwMAAAEAEkAbQwAAAIATADqDAAABQBIAA8ABwkIHqwsAPYBB2gMAAAFAFMAaQwAAAUASgBrDAAABQBPAGoMAAAFAFEAbAwAAAQASQBtDAAAAgBMAOoMAAAFAEgAAAA=.Jardalanin:BAAALgADCgEJAQAAAA==.Jaroshe:BAAALgADCgUJBQAAAA==.',
Je='Jellyfish:BAABLgAECn8VAAMaAAgJOA7GGQCIAQhoDAAAAgASAGkMAAACABAAawwAAAIAGQBqDAAAAgAUAGwMAAACACcAbQwAAAIAGwDqDAAABABGAG4MAAAFAEgAGgAICUYMxhkAiAEIaAwAAAEADgBpDAAAAQAIAGsMAAABABkAagwAAAEAFABsDAAAAQAMAG0MAAABABsA6gwAAAIARgBuDAAAAgBIAAgACAnOB38aAGoBCGgMAAABABIAaQwAAAEAEABrDAAAAQADAGoMAAABAAYAbAwAAAEAJwBtDAAAAQAIAOoMAAACADkAbgwAAAMACQAAAA==.Jessamyn:BAAALgAECgMJAwAAAA==.',
Jh='Jhoira:BAAALgAECgYJCgAAAA==.',
Jo='Jokko:BAAALgADCgEJAgAAAA==.Jordyy:BAABLgAECn8gAAQRAAkJ3h+EEQBfAgloDAAABQBfAGkMAAAFAE4AawwAAAQAVgBqDAAABABhAGwMAAADAFcAbQwAAAIAYADqDAAABQBcAG4MAAADAFAAbwwAAAEAIgARAAgJ3h+EEQBfAghoDAAABQBfAGkMAAAEAE4AawwAAAMAVgBsDAAAAgBXAG0MAAACAGAA6gwAAAUAXABuDAAAAwBQAG8MAAABACIAEgACCfMhwRcAvgACagwAAAQAYQBsDAAAAQBWABMAAgkRE0hUAHEAAmkMAAABADsAawwAAAEAJgAAAA==.',
Ka='Kaifren:BAACLgAFFH8HAAIPAAIJ8xK3YgCrAAJoDAAABAA/AOoMAAADACEADwACCfMSt2IAqwACaAwAAAQAPwDqDAAAAwAhAC4ABAp/FQACDwAJCSEM730AHQEADwAJCSEM730AHQEAAAA=.Kalifa:BAACLgAFFH8VAAIGAAUJHh5QCQBqAQVoDAAAAwBQAGkMAAAEAEQAawwAAAQAXwBqDAAAAwBDAOoMAAAHAD8ABgAFCR4eUAkAagEFaAwAAAMAUABpDAAABABEAGsMAAAEAF8AagwAAAMAQwDqDAAABwA/AC4ABAp/LgACBgAICfUjEwQAxAIABgAICfUjEwQAxAIAAAA=.Kalinethe:BAAALgAECgEJAQAAAA==.Karatay:BAAALgADCgQJBQAAAA==.Karrod:BAAALgAECgYJCQAAAA==.Katyce:BAAALgADCgcJDQAAAA==.',
Ke='Keilani:BAAALgAECgQJBQAAAA==.',
Ki='Killeerrkap:BAAALgAECgQJBQAAAA==.Killrmiller:BAAALgADCgMJAwAAAA==.Kirajdh:BAABLgAECn8mAAIWAAkJRB3SBwCyAgloDAAABgBXAGkMAAAEAFsAawwAAAUAVQBqDAAABgBXAGwMAAAFAE8AbQwAAAIARgDqDAAABQBPAG4MAAAEAD0AbwwAAAEALQAWAAkJRB3SBwCyAgloDAAABgBXAGkMAAAEAFsAawwAAAUAVQBqDAAABgBXAGwMAAAFAE8AbQwAAAIARgDqDAAABQBPAG4MAAAEAD0AbwwAAAEALQAAAA==.Kittenmitten:BAAALgADCgQJBAAAAA==.Kiwaj:BAAALgAECgUJBQABLgAECgkJJgAWAEQdAA==.',
Ko='Komayetu:BAAALgAECgQJBAAAAA==.',
Kr='Kraas:BAAALgAECgEJAQAAAA==.Krateis:BAABLgAECn8dAAIbAAYJjwS2EAACAQZoDAAABwAJAGkMAAAGAAsAawwAAAYAEgBqDAAAAgAKAGwMAAACAAsA6gwAAAYABQAbAAYJjwS2EAACAQZoDAAABwAJAGkMAAAGAAsAawwAAAYAEgBqDAAAAgAKAGwMAAACAAsA6gwAAAYABQAAAA==.Kraéthlas:BAAALgADCgYJCgAAAA==.',
Kw='Kwonhee:BAAALgADCgMJAwAAAA==.',
La='Lanadelrey:BAAALgAECgYJAQAAAA==.Laurenth:BAAALgADCgcJEQAAAA==.Lazyace:BAAALgAECgIJBAAAAA==.',
Le='Lebenspender:BAABLgAECn8iAAIKAAYJWiIMEQBCAgZoDAAABwBTAGkMAAAGAFEAawwAAAYAWQBqDAAABQBUAGwMAAAFAF0A6gwAAAUAXwAKAAYJWiIMEQBCAgZoDAAABwBTAGkMAAAGAFEAawwAAAYAWQBqDAAABQBUAGwMAAAFAF0A6gwAAAUAXwAAAA==.Lextalonis:BAAALgAECgYJCAAAAA==.',
Li='Linkstery:BAABLgAECn8kAAMRAAgJGRpLUwDNAQhoDAAABgBXAGkMAAAGAEQAawwAAAUAVQBqDAAAAwBHAGwMAAAFAEsAbQwAAAQAIgDqDAAABQA+AG4MAAACADQAEQAHCUoYS1MAzQEHaAwAAAYAVwBpDAAABgBEAGsMAAAFAFUAbAwAAAQARQBtDAAAAQAIAOoMAAAFAD4AbgwAAAIANAATAAMJfRWxNADkAANqDAAAAwBHAGwMAAABAEsAbQwAAAMAIgAAAA==.',
Lo='Losvanknight:BAAALgAECgcJCAAAAA==.',
Lt='Lt:BAAALgADCgEJAQAAAA==.',
Ly='Lyathon:BAAALgADCgMJAwAAAA==.',
Ma='Macfluffy:BAAALgADCgkJDgAAAA==.Mactacolover:BAAALgAECgMJAwAAAA==.Madbomber:BAAALgAECgYJDgAAAA==.Maeze:BAABLgAECn8aAAICAAgJ2QiQPgBXAQhoDAAABAAYAGkMAAAEABcAawwAAAQAGwBqDAAABAAbAGwMAAAEACMAbQwAAAEACQDqDAAABAASAG4MAAABABMAAgAICdkIkD4AVwEIaAwAAAQAGABpDAAABAAXAGsMAAAEABsAagwAAAQAGwBsDAAABAAjAG0MAAABAAkA6gwAAAQAEgBuDAAAAQATAAAA.Magepawk:BAAALgAECgMJAwAAAA==.Magew:BAAALgADCgQJBAAAAA==.Malandru:BAACLgAFFH8GAAIcAAQJwhQQEABCAQRoDAAAAgBTAGkMAAACAE4AbAwAAAEAAwDqDAAAAQAvABwABAnCFBAQAEIBBGgMAAACAFMAaQwAAAIATgBsDAAAAQADAOoMAAABAC8ALgAECn8iAAMUAAgJOh9vGgA0AgAUAAgJOh9vGgA0AgAcAAgJIgpkOgCQAQAAAA==.Mawwowow:BAABLgAECn8cAAIWAAYJOht2NQBpAQZoDAAABQA4AGkMAAAFAFEAawwAAAUASABqDAAABABDAGwMAAAEAFIA6gwAAAUANwAWAAYJOht2NQBpAQZoDAAABQA4AGkMAAAFAFEAawwAAAUASABqDAAABABDAGwMAAAEAFIA6gwAAAUANwAAAA==.Maximillius:BAAALgAECgQJBQABLgAECgcJGQAMALAeAA==.Mayjoraid:BAAALgAECgEJAQAAAA==.',
Me='Meekah:BAABLgAECn8yAAIIAAgJox8nBADlAghoDAAABwBHAGkMAAAHAFgAawwAAAcAUwBqDAAABgBRAGwMAAAGAFoAbQwAAAUAVgDqDAAACABWAG4MAAAEADwACAAICaMfJwQA5QIIaAwAAAcARwBpDAAABwBYAGsMAAAHAFMAagwAAAYAUQBsDAAABgBaAG0MAAAFAFYA6gwAAAgAVgBuDAAABAA8AAAA.Melbrosha:BAAALgAECgUJCwAAAA==.Melodine:BAAALgADCgEJAQAAAA==.Melyndia:BAAALgAECgUJBQABLgAECggJIQAdAAEgAA==.Meriks:BAAALgAECgQJDAABLgAECgUJDQAVAAAAAA==.',
Mi='Mickspooky:BAACLgAFFH8UAAIMAAQJtxTuMQBCAQRoDAAAAwA/AGkMAAAHAEoAawwAAAQAFwDqDAAABgAyAAwABAm3FO4xAEIBBGgMAAADAD8AaQwAAAcASgBrDAAABAAXAOoMAAAGADIALgAECn8nAAMMAAgJmR9HKQCVAgAMAAgJmR9HKQCVAgAZAAMJjxMzJQCpAAABLgAECgMJAwAVAAAAAA==.Mickstormy:BAAALgAECgMJAwAAAA==.Mierin:BAAALgAECgQJBgAAAA==.Milfy:BAAALgADCgQJBAABLgADCgUJBQAVAAAAAA==.Mintie:BAABLgAECn8eAAIeAAYJlBNnEQALAQZoDAAABgApAGkMAAAGAC8AawwAAAYANgBqDAAABAA3AGwMAAADAC8A6gwAAAUAPAAeAAYJlBNnEQALAQZoDAAABgApAGkMAAAGAC8AawwAAAYANgBqDAAABAA3AGwMAAADAC8A6gwAAAUAPAAAAA==.',
Mo='Moozylla:BAAALgAECggJCQAAAA==.Morrïgan:BAAALgAECgEJAQAAAA==.Mossiah:BAAALgAECgEJAQAAAA==.',
Mu='Muriggy:BAAALgADCgIJAgAAAA==.',
My='Mylarna:BAABLgAECn8aAAIHAAgJ0AgeJwAuAQhoDAAABgAiAGkMAAAFAC8AawwAAAQADQBqDAAAAgAUAGwMAAABAAcAbQwAAAIAEgDqDAAABQAdAG4MAAABAAcABwAICdAIHicALgEIaAwAAAYAIgBpDAAABQAvAGsMAAAEAA0AagwAAAIAFABsDAAAAQAHAG0MAAACABIA6gwAAAUAHQBuDAAAAQAHAAAA.Mynx:BAAALgAECgcJEQAAAA==.',
['Må']='Mårsh:BAAALgAECgEJAQAAAA==.',
Na='Nadira:BAAALgADCgYJBgABLgAECgYJFgAZAKMVAA==.Nahkti:BAAALgADCgcJBwAAAA==.Nazarick:BAAALgAECgYJCAAAAA==.',
Ne='Neona:BAAALgAECgQJBAAAAA==.Neriv:BAAALgAECgYJDAAAAA==.Nexaladin:BAAALgAECgEJAQAAAA==.',
Ni='Nimbus:BAAALgAECgMJBAABLgAFFAcJEwANACUUAA==.Nixii:BAABLgAECn8dAAIGAAYJGwzpKwD1AAZoDAAABgAoAGkMAAAFACQAawwAAAUAJgBqDAAABAAeAGwMAAAEAAkA6gwAAAUAHgAGAAYJGwzpKwD1AAZoDAAABgAoAGkMAAAFACQAawwAAAUAJgBqDAAABAAeAGwMAAAEAAkA6gwAAAUAHgAAAA==.',
No='Nocticula:BAABLgAECn8qAAIaAAgJ9AmrHwBUAQhoDAAABwA2AGkMAAAGABkAawwAAAcAGABqDAAABgASAGwMAAAFAAgAbQwAAAIACgDqDAAABgA5AG4MAAADAAMAGgAICfQJqx8AVAEIaAwAAAcANgBpDAAABgAZAGsMAAAHABgAagwAAAYAEgBsDAAABQAIAG0MAAACAAoA6gwAAAYAOQBuDAAAAwADAAAA.',
Ny='Nyet:BAACLgAFFH8PAAMEAAUJOBCYEQAuAQVoDAAABABIAGkMAAAEABEAawwAAAIALQBqDAAAAQATAOoMAAAEAB4ABAAFCTgQmBEALgEFaAwAAAQASABpDAAAAwARAGsMAAACAC0AagwAAAEAEwDqDAAABAAeAAUAAQliBqEcAEcAAWkMAAABABAALgAECn8cAAIEAAkJvxtbHABqAgAEAAkJvxtbHABqAgAAAA==.Nythraxia:BAAALgAECgMJAwAAAA==.Nyxiria:BAAALgADCgcJGgAAAA==.',
['Nò']='Nòir:BAAALgAECgMJAwAAAA==.',
Oh='Ohnarr:BAAALgAECgMJAwAAAA==.',
Ok='Oktoberfist:BAAALgAECgcJBwABLgAECggJAwAVAAAAAA==.',
Or='Orine:BAAALgAECggJDwAAAA==.Orioz:BAACLgAFFH8OAAIJAAQJWB5uAgBfAQRoDAAABQBeAGkMAAAEAEAAawwAAAMARwDqDAAAAgBPAAkABAlYHm4CAF8BBGgMAAAFAF4AaQwAAAQAQABrDAAAAwBHAOoMAAACAE8ALgAECn8kAAIJAAgJNCLxAwDoAgAJAAgJNCLxAwDoAgAAAA==.',
Os='Osiras:BAAALgAECgUJBQABLgAECgYJCAAVAAAAAA==.',
Ow='Owun:BAAALgADCgEJAQAAAA==.',
Oz='Oz:BAAALgADCgkJCgAAAA==.',
Pa='Pandapal:BAAALgAECgEJAgAAAA==.Pathbrin:BAAALgADCgEJAQAAAA==.Pauliee:BAAALgADCgMJAwAAAA==.Pawkah:BAAALgAECgEJAgAAAA==.Paytowintaxi:BAAALgADCgEJAQAAAA==.',
Pe='Peyton:BAAALgADCggJEQAAAA==.',
Pr='Protection:BAAALgADCgUJBgAAAA==.',
Ps='Psychoman:BAAALgADCgMJAwABLgAFFAUJDAAGANAbAA==.Psychomurda:BAABLgAECn8cAAMUAAYJpAtXdgALAQZoDAAABQAoAGkMAAAGACQAawwAAAUAHABqDAAAAwAcAGwMAAACABMA6gwAAAcAFwAUAAYJpAtXdgALAQZoDAAABAAoAGkMAAAFACQAawwAAAQAHABqDAAAAwAcAGwMAAACABMA6gwAAAcAFwAfAAMJ/geyJgBuAANoDAAAAQASAGkMAAABABIAawwAAAEAGAABLgAECggJMgAIAKMfAA==.',
Ra='Raign:BAAALgAECgEJAgAAAA==.Ratpack:BAAALgAECggJAwAAAA==.',
Re='Renfri:BAAALgADCgYJDgAAAA==.',
Ro='Robel:BAAALgAECgUJBgAAAA==.Ronaldbruce:BAAALgAECgQJBQAAAA==.Roupert:BAAALgADCgEJAQAAAA==.',
Sa='Sao:BAAALgAECgIJAgAAAA==.Sardrian:BAAALgAECgUJCwAAAA==.',
Se='Seimie:BAABLgAECn8ZAAITAAcJ6gqEDAAVAQdoDAAABQAzAGkMAAAEABcAawwAAAMAGABqDAAAAwAZAGwMAAADABEAbQwAAAEACwDqDAAABgAmABMABwnqCoQMABUBB2gMAAAFADMAaQwAAAQAFwBrDAAAAwAYAGoMAAADABkAbAwAAAMAEQBtDAAAAQALAOoMAAAGACYAAAA=.Selithvia:BAAALgAECgYJDQAAAA==.Senethotsare:BAAALgAECgQJBQAAAA==.Sethen:BAAALgADCgEJAQAAAA==.',
Sh='Shaboudi:BAAALgADCgEJAQABLgAECgQJBQAVAAAAAA==.Shamalicious:BAAALgADCgEJAQAAAA==.Shammwow:BAAALgAECgEJAQAAAA==.Shaofikx:BAABLgAECn8kAAIgAAgJlgpZHwBBAQhoDAAABwAYAGkMAAAFACsAawwAAAYAFgBqDAAABAARAGwMAAAFACcAbQwAAAIAFADqDAAABQAQAG4MAAACABcAIAAICZYKWR8AQQEIaAwAAAcAGABpDAAABQArAGsMAAAGABYAagwAAAQAEQBsDAAABQAnAG0MAAACABQA6gwAAAUAEABuDAAAAgAXAAAA.Shenknarok:BAABLgAECn8rAAIhAAYJ1xsECgCRAQZoDAAACQBPAGkMAAAHAFEAawwAAAcAUQBqDAAABwBFAGwMAAAGADcA6gwAAAcAOgAhAAYJ1xsECgCRAQZoDAAACQBPAGkMAAAHAFEAawwAAAcAUQBqDAAABwBFAGwMAAAGADcA6gwAAAcAOgAAAA==.Sherryl:BAABLgAECn8hAAIdAAYJlQ5oQQAZAQZoDAAABgAyAGkMAAAGACAAawwAAAYAMQBqDAAABQAYAGwMAAAFAB0A6gwAAAUAJAAdAAYJlQ5oQQAZAQZoDAAABgAyAGkMAAAGACAAawwAAAYAMQBqDAAABQAYAGwMAAAFAB0A6gwAAAUAJAAAAA==.Shmooples:BAAALgAECgEJAQAAAA==.Shunei:BAAALgADCgQJBAAAAA==.',
Si='Siema:BAAALgAECgMJAwAAAA==.Sigurd:BAAALgADCggJBwAAAA==.',
Sk='Skdragon:BAAALgADCgEJAQAAAA==.Skyari:BAABLgAECn8ZAAIEAAYJ8yTnDgAKAgZoDAAABABfAGkMAAAFAF8AawwAAAUAYQBqDAAABABbAGwMAAAEAFgA6gwAAAMAXwAEAAYJ8yTnDgAKAgZoDAAABABfAGkMAAAFAF8AawwAAAUAYQBqDAAABABbAGwMAAAEAFgA6gwAAAMAXwAAAA==.Skyarii:BAAALgAECgQJBwABLgAECgYJGQAEAPMkAA==.',
So='Songweaver:BAAALgAECgEJAgAAAA==.Soulminion:BAABLgAECn8aAAIMAAYJXQINpgCkAAZoDAAABwAEAGkMAAAGAAoAawwAAAYABwBqDAAAAQACAGwMAAABAAQA6gwAAAUAAwAMAAYJXQINpgCkAAZoDAAABwAEAGkMAAAGAAoAawwAAAYABwBqDAAAAQACAGwMAAABAAQA6gwAAAUAAwAAAA==.',
Sp='Spiritshard:BAAALgADCgcJEgAAAA==.Splashmountn:BAEALgAECgYJCgAAAA==.',
St='Sthane:BAAALgADCgEJAQAAAA==.Sthise:BAAALgAECgMJAwAAAA==.',
Su='Subtlety:BAAALgAECgkJEQAAAA==.Sulfurya:BAAALgAECgQJBQAAAA==.',
Sy='Sykoman:BAACLgAFFH8MAAMGAAUJ0BvcCgBdAQVoDAAAAwBTAGkMAAABADgAawwAAAIAVABqDAAAAQAYAOoMAAAFAD0ABgAFCdAb3AoAXQEFaAwAAAMAUwBpDAAAAQA4AGsMAAACAFQAagwAAAEAGADqDAAABAA9AB0AAQnlAMBMAC8AAeoMAAABAAIALgAECn8hAAIGAAgJEyJ6CwDfAgAGAAgJEyJ6CwDfAgAAAA==.',
['Sì']='Sìleñtclãw:BAAALgAECgcJDQAAAA==.',
Ta='Talarina:BAAALgADCgYJBgAAAA==.Taylen:BAAALgADCgcJBwAAAA==.',
Te='Terumi:BAAALgAECgIJAgAAAA==.Teverion:BAAALgADCgcJCwAAAA==.',
Th='Therkage:BAAALgADCgcJEAAAAA==.Thesios:BAAALgADCgcJBwAAAA==.Thickthighs:BAAALgAECgEJAQAAAA==.Thizz:BAABLgAECn8cAAIEAAYJPiD8KQASAgZoDAAACQBaAGkMAAAIAF4AawwAAAMAUQBqDAAAAQBDAGwMAAACAE0A6gwAAAUARAAEAAYJPiD8KQASAgZoDAAACQBaAGkMAAAIAF4AawwAAAMAUQBqDAAAAQBDAGwMAAACAE0A6gwAAAUARAABLgAFFAEJAQAVAAAAAA==.',
Ti='Tinksy:BAAALgADCgEJAQABLgADCgUJBQAVAAAAAA==.',
To='Toeto:BAAALgADCgYJBgAAAA==.Toetoeto:BAAALgADCggJCwAAAA==.Toetoetoete:BAAALgADCgYJBgAAAA==.Tooe:BAAALgAECgMJAwAAAA==.Torquei:BAAALgAECgYJBgAAAA==.Toxious:BAAALgAECgQJBAAAAA==.',
Tp='Tpaman:BAAALgAECgYJBgAAAA==.Tpdruid:BAAALgAECgMJAwAAAA==.',
Ts='Tsjuda:BAAALgADCgEJAQAAAA==.Tsjudii:BAAALgADCgYJBgAAAA==.Tsjudilla:BAAALgADCgEJAQAAAA==.',
Tu='Tujefe:BAAALgAECgYJCgAAAA==.',
Ug='Ugzlug:BAAALgADCgEJAQAAAA==.',
Un='Unholydk:BAAALgAECgUJBwABLgAECgkJLQAGANwhAA==.',
Va='Vacuus:BAABLgAECn8XAAISAAgJRwjnBgBWAQhoDAAAAwARAGkMAAADAB4AawwAAAMAKQBqDAAAAwATAGwMAAAEABEAbQwAAAIACwDqDAAAAwAOAG4MAAACAA4AEgAICUcI5wYAVgEIaAwAAAMAEQBpDAAAAwAeAGsMAAADACkAagwAAAMAEwBsDAAABAARAG0MAAACAAsA6gwAAAMADgBuDAAAAgAOAAAA.Vahldire:BAAALgAECgUJCQAAAA==.Valeri:BAAALgADCggJCwAAAA==.Varkon:BAAALgADCgMJAwAAAA==.Varn:BAAALgADCggJCAAAAA==.Varthion:BAAALgAECgYJBgAAAA==.',
Ve='Velastrasza:BAAALgADCgcJBwAAAA==.Velkethria:BAAALgAECgYJEwAAAA==.Velnyxia:BAAALgAECgQJBQAAAA==.Velovañ:BAAALgADCgEJAQAAAA==.Velthyria:BAAALgADCgkJCQAAAA==.Vestara:BAAALgAECggJCAAAAA==.Veylara:BAABLgAECn8hAAIRAAYJxwYPdgDjAAZoDAAABgAQAGkMAAAGABcAawwAAAYAEgBqDAAABQAXAGwMAAAFAAsA6gwAAAUAEAARAAYJxwYPdgDjAAZoDAAABgAQAGkMAAAGABcAawwAAAYAEgBqDAAABQAXAGwMAAAFAAsA6gwAAAUAEAAAAA==.',
Vi='Viryda:BAAALgADCggJFgABLgAECggJJgAeAJgJAA==.',
Vo='Voidgram:BAAALgADCgQJBAAAAA==.',
Wa='Wartimebeast:BAAALgAECgUJEAAAAA==.',
We='Welp:BAAALgAECgEJAQAAAA==.',
Wi='Windwalker:BAAALgAECgcJCAAAAA==.Wisteria:BAABLgAECn8uAAMTAAgJ2BNiCwALAghoDAAABgBFAGkMAAAIAD8AawwAAAgAPQBqDAAABgAkAGwMAAAFABsAbQwAAAMAEgDqDAAABwBcAG4MAAADABYAEwAICdgTYgsACwIIaAwAAAYARQBpDAAACAA/AGsMAAAIAD0AagwAAAYAJABsDAAABAAbAG0MAAADABIA6gwAAAcAXABuDAAAAwAWABIAAQnDATM4ABoAAWwMAAABAAQAAS4AAwoECQQAFQAAAAA=.',
Wo='Womplock:BAAALgAECgQJBgAAAA==.',
Wr='Wrâth:BAABLgAECn8oAAIPAAgJmROhOQDEAQhoDAAACAA7AGkMAAAEACoAawwAAAQANgBqDAAABgA4AGwMAAAFADEAbQwAAAUAMwDqDAAABgAoAG4MAAACADQADwAICZkToTkAxAEIaAwAAAgAOwBpDAAABAAqAGsMAAAEADYAagwAAAYAOABsDAAABQAxAG0MAAAFADMA6gwAAAYAKABuDAAAAgA0AAAA.',
Wy='Wydwen:BAAALgAECgEJAQAAAA==.',
Xe='Xenro:BAAALgADCgcJBgAAAA==.',
Xi='Xirus:BAAALgADCgQJAQAAAA==.',
Xu='Xulfred:BAAALgADCgIJAgAAAA==.',
Ya='Yavana:BAAALgADCgEJAQAAAA==.',
Zi='Zigzogg:BAAALgADCgEJAQAAAA==.Zilida:BAAALgADCgEJAQAAAA==.Ziwee:BAABLgAECn8aAAIgAAgJvBqAFQBeAghoDAAABQBaAGkMAAAFAFkAawwAAAQATQBqDAAAAwBLAGwMAAADAEIAbQwAAAEALADqDAAABABNAG4MAAABACEAIAAICbwagBUAXgIIaAwAAAUAWgBpDAAABQBZAGsMAAAEAE0AagwAAAMASwBsDAAAAwBCAG0MAAABACwA6gwAAAQATQBuDAAAAQAhAAEuAAQKCAkaACAAvBoA.',
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
