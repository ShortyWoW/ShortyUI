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

local lookup = {'Monk-Mistweaver','Warrior-Arms','Warrior-Fury','Warrior-Protection','Mage-Frost','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Unknown-Unknown','Paladin-Retribution','Hunter-Survival','Druid-Restoration','DemonHunter-Devourer','Evoker-Preservation','Evoker-Devastation','Paladin-Holy','DeathKnight-Unholy','DeathKnight-Blood','Evoker-Augmentation','Warlock-Affliction','Monk-Windwalker','Monk-Brewmaster','DemonHunter-Havoc','Priest-Discipline','Priest-Shadow','Priest-Holy','Rogue-Subtlety','Shaman-Elemental','Shaman-Enhancement','Rogue-Assassination','Druid-Guardian','Druid-Feral','Druid-Balance',}
local provider = {region='US',realm='Gorgonnash',name='US',type='daily',zone=46,date='2026-05-14',data={Aa='Aakira:BAAALgAECgcJDQAAAA==.Aangie:BAABLgAECn8YAAIBAAcJngZMPAD0AAdoDAAABAAdAGkMAAAEAAsAawwAAAQACwBqDAAAAwAJAGwMAAADABoA6gwAAAQAFQBuDAAAAgAIAAEABwmeBkw8APQAB2gMAAAEAB0AaQwAAAQACwBrDAAABAALAGoMAAADAAkAbAwAAAMAGgDqDAAABAAVAG4MAAACAAgAAAA=.Aanjie:BAABLgAECn8aAAIBAAYJQwlDOQDXAAZoDAAABQAmAGkMAAAFABMAawwAAAUAGABqDAAABAAWAGwMAAADABMA6gwAAAQAEwABAAYJQwlDOQDXAAZoDAAABQAmAGkMAAAFABMAawwAAAUAGABqDAAABAAWAGwMAAADABMA6gwAAAQAEwAAAA==.',
Ab='Abban:BAAALgAECgMJAwAAAA==.Abom:BAAALgAECgIJAgAAAA==.Abrastal:BAAALgAECgQJCAAAAA==.',
Ad='Adrestia:BAAALgAECgEJAQAAAA==.',
Ak='Akbar:BAAALgAECgUJBQAAAA==.',
Al='Alline:BAAALgAECgYJEAAAAA==.Alswaron:BAAALgAECgUJEgAAAA==.',
Am='Amador:BAACLgAFFH8IAAQCAAMJYBFrEQDPAANoDAAABABZAGkMAAABAAIA6gwAAAMAKQACAAMJFRBrEQDPAANoDAAAAwBZAGkMAAABAAIA6gwAAAEAHwADAAEJ1A8XIQBTAAFoDAAAAQAoAAQAAQkgEJ0PAEcAAeoMAAACACkALgAECn8nAAQCAAgJBSGdBACiAgACAAcJBSGdBACiAgADAAQJ3RrpaQAOAQAEAAIJnBCNOgB3AAAAAA==.Amorlan:BAAALgAECgEJAQAAAA==.Amyra:BAAALgAECgEJAQAAAA==.',
An='Annox:BAAALgAECgQJBwAAAA==.',
Ap='Apsallar:BAAALgAECgcJEAAAAA==.',
Ar='Arcanism:BAABLgAECn8cAAIFAAcJsBOjngCZAQdoDAAABgBMAGkMAAAGADcAawwAAAYANQBqDAAAAwBBAGwMAAABAC0AbQwAAAEAGgDqDAAABQAtAAUABwmwE6OeAJkBB2gMAAAGAEwAaQwAAAYANwBrDAAABgA1AGoMAAADAEEAbAwAAAEALQBtDAAAAQAaAOoMAAAFAC0AAAA=.Arlas:BAAALgAECgIJAwAAAA==.Arthone:BAAALgADCgUJBQAAAA==.',
As='Asstalor:BAABLgAECn8dAAMGAAgJmxC9PQCOAQhoDAAABQAmAGkMAAAFAC8AawwAAAQAHwBqDAAABQAxAGwMAAADAD0AbQwAAAIAIgDqDAAABAA3AG4MAAABABsABgAICVoQvT0AjgEIaAwAAAUAJgBpDAAABAAqAGsMAAAEAB8AagwAAAUAMQBsDAAAAwA9AG0MAAACACIA6gwAAAQANwBuDAAAAQAbAAcAAQmPEt0rADcAAWkMAAABAC8AAAA=.',
Au='Auggy:BAAALgADCgIJAgAAAA==.Auryon:BAABLgAECn8nAAIIAAgJJyGoFABUAghoDAAACABdAGkMAAAGAFEAawwAAAcAVwBqDAAABAA1AGwMAAAGAEwAbQwAAAEAUADqDAAABgBTAG4MAAABAFoACAAICSchqBQAVAIIaAwAAAgAXQBpDAAABgBRAGsMAAAHAFcAagwAAAQANQBsDAAABgBMAG0MAAABAFAA6gwAAAYAUwBuDAAAAQBaAAAA.',
Av='Avelna:BAAALgADCgYJBgABLgADCgcJDQAJAAAAAA==.',
Az='Azmodea:BAAALgADCgEJAgAAAA==.',
Ba='Baccstab:BAAALgAECgYJDAAAAA==.Bagains:BAAALgADCgcJEwAAAA==.Baraka:BAAALgAECgYJCgAAAA==.Baulder:BAAALgAECgYJDQAAAA==.',
Bi='Bigb:BAAALgAECggJDwABLgAFFAgJHQAFAI8jAA==.Bigolcrittie:BAAALgADCgIJAgAAAA==.',
Bl='Bloodfurry:BAAALgAECgMJAQAAAA==.Bluè:BAAALgAECgcJEQAAAA==.',
Bo='Bobdaunicorn:BAAALgAECgEJAQAAAA==.Boltz:BAAALgAECgMJAwAAAA==.Bombalaharis:BAAALgAECgcJDQAAAA==.',
Br='Brekke:BAABLgAECn8pAAIKAAkJdRZYMgDaAQloDAAABgBBAGkMAAAFAFEAawwAAAUASgBqDAAABQArAGwMAAAFAEAAbQwAAAMAFgDqDAAABwA7AG4MAAADAD8AbwwAAAIAGwAKAAkJdRZYMgDaAQloDAAABgBBAGkMAAAFAFEAawwAAAUASgBqDAAABQArAGwMAAAFAEAAbQwAAAMAFgDqDAAABwA7AG4MAAADAD8AbwwAAAIAGwAAAA==.Brokenbow:BAABLgAECn8XAAMLAAkJphMkEQCxAQloDAAAAwA2AGkMAAADAEMAawwAAAMAQQBqDAAAAgAfAGwMAAADAEgAbQwAAAMALQDqDAAAAwBJAG4MAAACAAUAbwwAAAEAEQALAAkJVg4kEQCxAQloDAAAAgAdAGkMAAADAEMAawwAAAMAQQBqDAAAAgAfAGwMAAABAB0AbQwAAAIAIwDqDAAAAgAqAG4MAAACAAUAbwwAAAEAEQAIAAQJCBjFfQDuAARoDAAAAQA2AGwMAAACAEgAbQwAAAEALQDqDAAAAQBJAAAA.',
Bu='Bullshaft:BAAALgAECgEJAQAAAA==.Buntz:BAABLgAECn8gAAIKAAkJgCPiAwAuAwloDAAABQBjAGkMAAAFAF4AawwAAAUAXgBqDAAAAwBQAGwMAAACAFoAbQwAAAIAUQDqDAAABABfAG4MAAADAFkAbwwAAAMAUAAKAAkJgCPiAwAuAwloDAAABQBjAGkMAAAFAF4AawwAAAUAXgBqDAAAAwBQAGwMAAACAFoAbQwAAAIAUQDqDAAABABfAG4MAAADAFkAbwwAAAMAUAAAAA==.Bushmethsin:BAACLgAFFH8XAAIMAAUJHCSjBQAKAgVoDAAABwBdAGkMAAAFAF8AawwAAAQAXQBqDAAAAgBWAOoMAAAFAF0ADAAFCRwkowUACgIFaAwAAAcAXQBpDAAABQBfAGsMAAAEAF0AagwAAAIAVgDqDAAABQBdAC4ABAp/FAACDAAICVUiDR4ATgIADAAICVUiDR4ATgIAAAA=.Buttery:BAAALgAECgUJDwAAAA==.',
Ca='Cabb:BAAALgAECgQJBAAAAA==.',
Ce='Ceedubble:BAAALgAECggJDAAAAA==.Celestine:BAAALgADCgYJBgABLgAECggJIgANAGIOAA==.',
Ch='Charmanderz:BAABLgAECn8kAAMOAAgJfw33EABZAQhoDAAABgA4AGkMAAAGAB8AawwAAAYAJQBqDAAABAAQAGwMAAAEADgAbQwAAAIABwDqDAAABwBCAG4MAAABAAUADgAICX8N9xAAWQEIaAwAAAYAOABpDAAABgAfAGsMAAAGACUAagwAAAQAEABsDAAAAwA4AG0MAAACAAcA6gwAAAcAQgBuDAAAAQAFAA8AAQkiFaM7AD8AAWwMAAABADYAAAA=.Cherchlglsia:BAAALgADCgQJCAAAAA==.Chewsdee:BAAALgAECgQJBAAAAA==.Christlovesu:BAAALgAECgIJAgAAAA==.Chuckrules:BAAALgADCgcJDgAAAA==.',
Cl='Clackshi:BAAALgAECgYJCgAAAA==.',
Cr='Critable:BAABLgAECn8mAAMQAAkJAhEaGwDQAQloDAAABgAoAGkMAAAFACcAawwAAAUAMwBqDAAABQBAAGwMAAAFADIAbQwAAAMAFgDqDAAABQAsAG4MAAADADUAbwwAAAEAGQAQAAkJAhEaGwDQAQloDAAABQAoAGkMAAAEACcAawwAAAQAMwBqDAAABABAAGwMAAAEADIAbQwAAAIAFgDqDAAABAAsAG4MAAACADUAbwwAAAEAGQAKAAgJNggXggB2AQhoDAAAAQAbAGkMAAABABAAawwAAAEAHwBqDAAAAQAGAGwMAAABABQAbQwAAAEADgDqDAAAAQAYAG4MAAABAAwAAAA=.',
Cu='Curst:BAAALgAECggJEwAAAA==.',
Da='Dagares:BAAALgADCggJDQAAAA==.Dahnte:BAAALgAECgEJAQAAAA==.',
De='Dechala:BAABLgAECn8iAAINAAgJYg7VRQBQAQhoDAAABQAoAGkMAAAEACYAawwAAAQAKABqDAAABQAgAGwMAAAEAC0AbQwAAAIAFQDqDAAABgAjAG4MAAAEACIADQAICWIO1UUAUAEIaAwAAAUAKABpDAAABAAmAGsMAAAEACgAagwAAAUAIABsDAAABAAtAG0MAAACABUA6gwAAAYAIwBuDAAABAAiAAAA.Deezknights:BAACLgAFFH8QAAMRAAUJ4yFeIwBmAQVoDAAABABcAGkMAAADAGAAawwAAAIAQABqDAAAAwBNAOoMAAAEAF4AEQAFCeMhXiMAZgEFaAwAAAQAXABpDAAAAwBgAGsMAAACAEAAagwAAAIATQDqDAAABABeABIAAQkAAJMyAAAAAWoMAAABADQALgAECn8nAAIRAAkJBiVBCAD2AgARAAkJBiVBCAD2AgAAAA==.Deezpuffs:BAABLgAFFH8HAAITAAQJOxW5FQA7AQRoDAAAAQBLAGkMAAACACQAawwAAAIAJgDqDAAAAgBCABMABAk7FbkVADsBBGgMAAABAEsAaQwAAAIAJABrDAAAAgAmAOoMAAACAEIAAS4ABRQFCRAAEQDjIQA=.Deezrage:BAAALgADCgYJBgAAAA==.Derailed:BAAALgADCgEJAgAAAA==.Dergon:BAABLgAECn8iAAIGAAgJ1RpQJAD7AQhoDAAABABKAGkMAAADAEQAawwAAAMAMABqDAAABQA8AGwMAAAFAFEAbQwAAAQAPADqDAAABwBiAG4MAAADADEABgAICdUaUCQA+wEIaAwAAAQASgBpDAAAAwBEAGsMAAADADAAagwAAAUAPABsDAAABQBRAG0MAAAEADwA6gwAAAcAYgBuDAAAAwAxAAAA.Destiria:BAABLgAECn8kAAMGAAgJtBn/IwD8AQhoDAAABgBHAGkMAAAGACkAawwAAAUAOABqDAAABAAgAGwMAAAFAFcAbQwAAAMAWADqDAAABQAwAG4MAAACAEMABgAICbQZ/yMA/AEIaAwAAAUARwBpDAAABQApAGsMAAAFADgAagwAAAQAIABsDAAABQBXAG0MAAADAFgA6gwAAAQAMABuDAAAAgBDABQAAwl5B3knAFQAA2gMAAABAAgAaQwAAAEABgDqDAAAAQAqAAAA.Devistatorxx:BAAALgAECgUJBQAAAA==.',
Do='Doggyystyle:BAAALgAECgEJAQAAAA==.Donaldpump:BAAALgAECgYJBwAAAA==.Doomedturtle:BAAALgADCgYJCQAAAA==.Doublekill:BAAALgAECgUJDAAAAA==.',
Du='Duergan:BAABLgAECn8mAAQVAAgJEBTQGQB+AQhoDAAABwA2AGkMAAAHADsAawwAAAQAJwBqDAAAAwAgAGwMAAAEACgAbQwAAAQAMADqDAAABgBKAG4MAAADACoAFQAICRAU0BkAfgEIaAwAAAYANgBpDAAABgA7AGsMAAADACcAagwAAAIAIABsDAAAAwAoAG0MAAADADAA6gwAAAUASgBuDAAAAwAqABYABglvBck8AL8ABmgMAAABAAsAaQwAAAEAEABrDAAAAQAQAGoMAAABAAgAbAwAAAEAEwBtDAAAAQAEAAEAAQlFAwRyACEAAeoMAAABAAgAAAA=.',
Ea='Eatz:BAAALgADCgYJBgAAAA==.',
Fa='Faelyn:BAAALgADCgEJBAAAAA==.Fansy:BAAALgAECgEJAQAAAA==.',
Fi='Fillycheese:BAAALgAECgEJAQAAAA==.',
Fl='Fleurelle:BAAALgAECgIJAgAAAA==.',
Fr='Frollo:BAAALgAECgEJAQAAAA==.Frosstitute:BAAALgAECgMJAwAAAA==.',
Fu='Furfiend:BAABLgAECn8fAAMRAAcJqh9SUgBpAQdoDAAACABUAGkMAAAIAFEAawwAAAYATwBqDAAAAgBJAGwMAAABAFQA6gwAAAIARQBuDAAABABXABEABglqH1JSAGkBBmgMAAAHAFQAaQwAAAcAUQBrDAAABQBPAGoMAAABABYA6gwAAAIARQBuDAAABABXABIABQk4G8UYADMBBWgMAAABAEoAaQwAAAEAQQBrDAAAAQA2AGoMAAABAEkAbAwAAAEAVAAAAA==.',
Gi='Giantdog:BAAALgAECgUJBQAAAA==.Gilraen:BAABLgAECn8wAAMCAAgJHhd4CgDSAQhoDAAACAA0AGkMAAAIADYAawwAAAYAOABqDAAABgBDAGwMAAAGADMAbQwAAAQAKADqDAAABwBgAG4MAAADAD4AAgAICX4WeAoA0gEIaAwAAAIANABpDAAAAgA2AGsMAAACADgAagwAAAMAQwBsDAAAAwAnAG0MAAACACgA6gwAAAIAYABuDAAAAgA+AAMACAl1DmtNAHEBCGgMAAAGACoAaQwAAAYAJwBrDAAABAAnAGoMAAADABgAbAwAAAMAMwBtDAAAAgAYAOoMAAAFAB0AbgwAAAEAHwAAAA==.Gingerjen:BAAALgAECggJDgAAAA==.',
Go='Gorgrand:BAAALgAECgcJBwAAAA==.Gothbiotch:BAAALgAECgMJAwAAAA==.',
Gr='Greggnog:BAAALgAECgcJDAAAAA==.Greggy:BAAALgAECgUJCQABLgAECgcJDAAJAAAAAA==.Grenache:BAAALgAECgMJBAAAAA==.',
Ha='Halfworld:BAAALgADCgYJBgAAAA==.Happydaze:BAABLgAECn8gAAMSAAgJ+RlDDgC+AQhoDAAABQBIAGkMAAADAEQAawwAAAQANABqDAAABgBRAGwMAAAEAD0AbQwAAAIARwDqDAAABwBMAG4MAAABAD4AEgAICaAZQw4AvgEIaAwAAAUASABpDAAAAwBEAGsMAAAEADQAagwAAAUAPwBsDAAAAgA2AG0MAAACAEcA6gwAAAcATABuDAAAAQA+ABEAAgnZF4HuAKEAAmoMAAABAFEAbAwAAAIAPQAAAA==.Haxthedruid:BAAALgAECgEJAQAAAA==.Haxthemonk:BAAALgAECgEJAQAAAA==.',
He='Hemotoxin:BAAALgAECgMJAwAAAA==.Hendel:BAAALgAECgQJBgAAAA==.Herkaferk:BAAALgAECgYJEwAAAA==.',
Ho='Hojx:BAAALgAECgEJAQAAAA==.',
Hr='Hrolf:BAAALgAECgUJDwABLgAECggJJgAVABAUAA==.',
Il='Illiannà:BAAALgAECgYJCQABLgAECggJJAAOAH8NAA==.Illidont:BAAALgAECgcJDAAAAA==.Illijr:BAABLgAECn8WAAIXAAgJ+g5GFQBlAQhoDAAABAA2AGkMAAADAB0AawwAAAMAIQBqDAAAAwAnAGwMAAACACgAbQwAAAEAKgDqDAAABQAnAG4MAAABAB0AFwAICfoORhUAZQEIaAwAAAQANgBpDAAAAwAdAGsMAAADACEAagwAAAMAJwBsDAAAAgAoAG0MAAABACoA6gwAAAUAJwBuDAAAAQAdAAAA.',
It='Ithil:BAAALgADCgkJDwAAAA==.',
Ja='Jaemison:BAAALgADCgQJAwAAAA==.',
Ji='Jicks:BAABLgAECn8UAAIYAAYJ8wSMMQDZAAZoDAAABAATAGkMAAAEABAAawwAAAMACABqDAAAAgAJAGwMAAABAAMA6gwAAAYAEwAYAAYJ8wSMMQDZAAZoDAAABAATAGkMAAAEABAAawwAAAMACABqDAAAAgAJAGwMAAABAAMA6gwAAAYAEwAAAA==.',
Jk='Jkass:BAAALgAECgYJEwAAAA==.',
Ju='Judgementdày:BAAALgAECgQJCgAAAA==.',
['Jà']='Jàk:BAAALgADCgUJBQAAAA==.',
Ka='Kamaeria:BAABLgAECn8jAAIZAAgJKQ8aGwCKAQhoDAAABQAQAGkMAAAFABkAawwAAAUAEwBqDAAABQAnAGwMAAAEAC0AbQwAAAMAIgDqDAAABgBbAG4MAAACACYAGQAICSkPGhsAigEIaAwAAAUAEABpDAAABQAZAGsMAAAFABMAagwAAAUAJwBsDAAABAAtAG0MAAADACIA6gwAAAYAWwBuDAAAAgAmAAEuAAQKCAkwAAgAthIA.Kaíros:BAAALgADCgMJAwAAAA==.',
Kh='Khaotica:BAAALgADCgkJCQAAAA==.',
Ki='Kiandara:BAACLgAFFH8VAAMDAAUJyxYBDQA3AQVoDAAABQBgAGkMAAAGAFAAawwAAAUAIABqDAAAAwBOAOoMAAACABcAAwAFCXsVAQ0ANwEFaAwAAAUAYABpDAAABQBQAGsMAAAEACAAagwAAAMATgDqDAAAAQAJAAIAAwliDxwRANIAA2kMAAABAEEAawwAAAEAHADqDAAAAQAXAC4ABAp/IQADAwAJCfEb8gwA7gIAAwAJCcUb8gwA7gIABAAFCRwb3h0AVwEAAAA=.Kikkoman:BAAALgAFFAEJAQAAAA==.Kilmas:BAAALgAECgIJAgAAAA==.Kirant:BAAALgADCggJDQAAAA==.Kirara:BAAALgADCgYJBgAAAA==.',
Ko='Kooz:BAAALgADCgUJBQAAAA==.Kooze:BAAALgADCgUJCAAAAA==.Koozo:BAAALgADCgMJAwAAAA==.',
Kt='Kt:BAABLgAECn8aAAIFAAcJNhOSYQBqAQdoDAAABQAzAGkMAAAFAEcAawwAAAUAHgBqDAAAAgA3AGwMAAADADoA6gwAAAQAOgBuDAAAAgAYAAUABwk2E5JhAGoBB2gMAAAFADMAaQwAAAUARwBrDAAABQAeAGoMAAACADcAbAwAAAMAOgDqDAAABAA6AG4MAAACABgAAAA=.',
Ky='Kynrath:BAAALgAECgIJAwAAAA==.',
La='Laurie:BAAALgADCgMJBgAAAA==.Lava:BAAALgADCgUJBQABLgAECggJDwAJAAAAAA==.Lavablast:BAAALgADCgYJCwAAAA==.',
Le='Lelanie:BAAALgADCggJDgAAAA==.',
Li='Lichnfamous:BAABLgAECn8YAAIRAAgJnxDNPgCoAQhoDAAAAwAWAGkMAAAEACoAawwAAAQAQABqDAAABAAlAGwMAAADACcAbQwAAAEADwDqDAAABAA+AG4MAAABADQAEQAICZ8QzT4AqAEIaAwAAAMAFgBpDAAABAAqAGsMAAAEAEAAagwAAAQAJQBsDAAAAwAnAG0MAAABAA8A6gwAAAQAPgBuDAAAAQA0AAAA.Lightfrost:BAAALgADCgIJAgAAAA==.Lightning:BAAALgAECgUJCAAAAA==.Likkan:BAAALgAECgEJAQAAAA==.Lilithdawn:BAABLgAECn8hAAIaAAkJvhuRCACJAgloDAAABgBYAGkMAAAGAE8AawwAAAUAUABqDAAABABdAGwMAAAEAFYAbQwAAAEAOgDqDAAABQApAG4MAAABAEkAbwwAAAEAJgAaAAkJvhuRCACJAgloDAAABgBYAGkMAAAGAE8AawwAAAUAUABqDAAABABdAGwMAAAEAFYAbQwAAAEAOgDqDAAABQApAG4MAAABAEkAbwwAAAEAJgAAAA==.',
Lo='Lockwar:BAAALgAECgYJEAAAAA==.Louvre:BAABLgAECn8hAAIbAAkJAxhhCABIAgloDAAABABTAGkMAAAFAF8AawwAAAYATwBqDAAABABEAGwMAAAEADIAbQwAAAEAEQDqDAAABQA+AG4MAAADADgAbwwAAAEALwAbAAkJAxhhCABIAgloDAAABABTAGkMAAAFAF8AawwAAAYATwBqDAAABABEAGwMAAAEADIAbQwAAAEAEQDqDAAABQA+AG4MAAADADgAbwwAAAEALwAAAA==.',
Lu='Lukarian:BAAALgAECgQJBQAAAA==.',
Ma='Makthra:BAAALgAECgUJEQAAAA==.Marek:BAAALgADCgUJCAAAAA==.Marionette:BAAALgADCggJGQAAAA==.Mawseeker:BAAALgADCgEJAQAAAA==.',
Me='Megabettegaa:BAABLgAECn9aAAIRAAkJLhf4JAAXAgloDAAADABMAGkMAAAOAD4AawwAAA8ANQBqDAAADQBCAGwMAAAMADsAbQwAAAcAMgDqDAAACQBLAG4MAAAGAEMAbwwAAAIAHgARAAkJLhf4JAAXAgloDAAADABMAGkMAAAOAD4AawwAAA8ANQBqDAAADQBCAGwMAAAMADsAbQwAAAcAMgDqDAAACQBLAG4MAAAGAEMAbwwAAAIAHgAAAA==.Mennathil:BAAALgADCgEJAQAAAA==.Meric:BAAALgADCgcJDgAAAA==.',
Mi='Midnight:BAAALgAECgcJCQAAAA==.Milo:BAAALgAECgQJCwAAAA==.Miniangel:BAACLgAFFH8IAAIaAAMJSg/mEwDLAANoDAAABAAUAGkMAAACACMA6gwAAAIAPQAaAAMJSg/mEwDLAANoDAAABAAUAGkMAAACACMA6gwAAAIAPQAuAAQKfx4AAxoACQl9FZwLAFICABoACQl9FZwLAFICABkACAk+EPAoAJMBAAAA.Mixednuts:BAAALgAECgIJAgAAAA==.',
Mo='Molasses:BAACLgAFFH8LAAIFAAMJVwtrWADtAANoDAAABQAfAGkMAAAEACAA6gwAAAIAFwAFAAMJVwtrWADtAANoDAAABQAfAGkMAAAEACAA6gwAAAIAFwAuAAQKfzAAAgUACQl4GT8cAGcCAAUACQl4GT8cAGcCAAAA.Moof:BAAALgAECgEJAQAAAA==.',
Na='Najitar:BAAALgAECgEJAQAAAA==.Nazaibrew:BAAALgADCgYJBgABLgAECgkJKQAYABQeAA==.',
Ne='Necromalus:BAAALgADCgEJBAAAAA==.Neerx:BAAALgADCgUJBQAAAA==.',
Nu='Nubkselk:BAABLgAECn8nAAINAAgJRh/7EABpAghoDAAABwBXAGkMAAAGAEwAawwAAAYAVQBqDAAABQA3AGwMAAAEAE4AbQwAAAEARADqDAAABgBJAG4MAAAEAFoADQAICUYf+xAAaQIIaAwAAAcAVwBpDAAABgBMAGsMAAAGAFUAagwAAAUANwBsDAAABABOAG0MAAABAEQA6gwAAAYASQBuDAAABABaAAAA.Nurishment:BAACLgAFFH8ZAAIMAAYJPhTgCQC+AQZoDAAABgAwAGkMAAAFADIAawwAAAQASABqDAAABAAoAGwMAAABAEEA6gwAAAUAIQAMAAYJPhTgCQC+AQZoDAAABgAwAGkMAAAFADIAawwAAAQASABqDAAABAAoAGwMAAABAEEA6gwAAAUAIQAuAAQKfyMAAgwACQn7HWwSAKICAAwACQn7HWwSAKICAAAA.',
Ny='Nyrr:BAAALgADCgEJAgAAAA==.',
Og='Ogmurka:BAAALgAECgEJAQAAAA==.',
On='Oni:BAAALgADCgUJBQAAAA==.Onitachi:BAABLgAECn8rAAMcAAgJzxG4KQA1AQhoDAAABwBLAGkMAAAHADYAawwAAAgANABqDAAABAA1AGwMAAAEAB0AbQwAAAIACgDqDAAABwAxAG4MAAAEADAAHAAICc8RuCkANQEIaAwAAAcASwBpDAAABwA2AGsMAAAHADQAagwAAAIANQBsDAAAAwAdAG0MAAACAAoA6gwAAAYAMQBuDAAABAAwAB0ABAlwCfoaAJAABGsMAAABABkAagwAAAIAFABsDAAAAQAVAOoMAAABABkAAAA=.',
Op='Optistriker:BAABLgAECn8wAAIMAAgJxhWAHgD4AQhoDAAACAAvAGkMAAAHAEAAawwAAAcAPwBqDAAABgA9AGwMAAAGADAAbQwAAAQAJgDqDAAABwBCAG4MAAADADYADAAICcYVgB4A+AEIaAwAAAgALwBpDAAABwBAAGsMAAAHAD8AagwAAAYAPQBsDAAABgAwAG0MAAAEACYA6gwAAAcAQgBuDAAAAwA2AAAA.',
Oy='Oythsar:BAAALgADCgQJBAAAAA==.',
Pa='Painfree:BAAALgADCgQJBAAAAA==.Papabear:BAAALgAECgEJAQAAAA==.',
Pi='Pig:BAABLgAECn8cAAIDAAgJKhjaKwAGAghoDAAABgBBAGkMAAAFAEsAawwAAAUAVABqDAAAAwA4AGwMAAADAEEAbQwAAAEAFgDqDAAABAA8AG4MAAABADoAAwAICSoY2isABgIIaAwAAAYAQQBpDAAABQBLAGsMAAAFAFQAagwAAAMAOABsDAAAAwBBAG0MAAABABYA6gwAAAQAPABuDAAAAQA6AAEuAAQKCQkgAAoAgCMA.Pinks:BAAALgADCgkJCQAAAA==.',
Po='Poplockndrop:BAAALgAECgUJBgAAAA==.Portion:BAABLgAECn8oAAIFAAcJaBwDWgArAgdoDAAACABUAGkMAAAIAE4AawwAAAgAXABqDAAABQBKAGwMAAAEAFEAbQwAAAEAIgDqDAAABgBBAAUABwloHANaACsCB2gMAAAIAFQAaQwAAAgATgBrDAAACABcAGoMAAAFAEoAbAwAAAQAUQBtDAAAAQAiAOoMAAAGAEEAAAA=.',
Pr='Pretentious:BAABLgAECn8YAAIKAAgJoh8rJgCOAghoDAAABABcAGkMAAADAF0AawwAAAMAVgBqDAAAAwAsAGwMAAAEAFsAbQwAAAIAOwDqDAAABABFAG4MAAABAEoACgAICaIfKyYAjgIIaAwAAAQAXABpDAAAAwBdAGsMAAADAFYAagwAAAMALABsDAAABABbAG0MAAACADsA6gwAAAQARQBuDAAAAQBKAAAA.Prettyfun:BAAALgADCgUJBQAAAA==.Prettysavage:BAAALgAECgIJAgAAAA==.Primo:BAAALgADCgYJEQAAAA==.',
['Pè']='Pèrsephônè:BAAALgADCgIJAgAAAA==.',
Ra='Radicalism:BAAALgAECgQJBQAAAA==.Ranigard:BAAALgAECgUJCAAAAA==.Rantioc:BAAALgAECgIJAgAAAA==.Raugan:BAAALgAECgEJAQAAAA==.',
Re='Reparations:BAAALgAECgkJBgAAAA==.Repentofsin:BAAALgAECgQJBAAAAA==.Rexbriefs:BAAALgAECgcJCAAAAA==.',
Ri='Riptong:BAAALgADCgEJAQAAAA==.',
Ro='Rovinj:BAAALgAECgkJBwAAAA==.',
Ru='Rumi:BAABLgAECn8bAAINAAgJNhJdNwCEAQhoDAAABgBSAGkMAAAFADEAawwAAAQAIQBqDAAAAwAyAGwMAAACADQAbQwAAAEAIgDqDAAABQAqAG4MAAABAB8ADQAICTYSXTcAhAEIaAwAAAYAUgBpDAAABQAxAGsMAAAEACEAagwAAAMAMgBsDAAAAgA0AG0MAAABACIA6gwAAAUAKgBuDAAAAQAfAAAA.',
Ry='Rydle:BAAALgAECgYJBgAAAA==.',
Sa='Sanlesh:BAAALgADCgUJBgAAAA==.Sapodillà:BAAALgAECgcJBwAAAA==.Sarijevo:BAAALgAECgkJBQAAAA==.Saurax:BAAALgADCgMJBAAAAA==.',
Sc='Scatz:BAAALgADCgIJAgAAAA==.Scott:BAAALgAECgcJBwAAAA==.Scylla:BAAALgAECgYJDwAAAA==.',
Se='Sevrin:BAACLgAFFH8GAAIbAAIJ1ht+EQC9AAJoDAAABABCAGkMAAACAEsAGwACCdYbfhEAvQACaAwAAAQAQgBpDAAAAgBLAC4ABAp/JAACGwAICVUj6QUAfwIAGwAICVUj6QUAfwIAAAA=.',
Sh='Shadowfuryy:BAAALgAECgUJBQAAAA==.Shalati:BAAALgADCgYJBgAAAA==.Shestrouble:BAAALgAFFAIJBAAAAA==.Shirerat:BAAALgADCgMJBAAAAA==.Shtzson:BAAALgAECgYJBgABLgAECgcJEwAJAAAAAA==.Shyjinx:BAAALgAECgYJBgAAAA==.Shîft:BAABLgAECn8nAAMbAAgJWiF0FwBwAQhoDAAABgBeAGkMAAAGAFMAawwAAAUAVwBqDAAABQBYAGwMAAAFAFUAbQwAAAIAQADqDAAABwBgAG4MAAADAFQAGwAGCdwidBcAcAEGaAwAAAYAXgBpDAAAAQBSAGsMAAAFAFcAagwAAAUAWADqDAAABwBgAG4MAAADAFQAHgADCX8eDw4A+AADaQwAAAUAUwBsDAAABQBVAG0MAAACAEAAAAA=.',
Si='Siiwwy:BAAALgAECgMJAwAAAA==.',
Sl='Slice:BAAALgAECgUJDAAAAA==.',
So='Solicide:BAABLgAECn8lAAUfAAgJKxsfCQDZAQhoDAAABgBWAGkMAAAGAFAAawwAAAUAUwBqDAAABQBEAGwMAAAEAD8AbQwAAAIANwDqDAAABgBLAG4MAAADACoAHwAICTcXHwkA2QEIaAwAAAIAJwBpDAAAAwBCAGsMAAADAEkAagwAAAMAOABsDAAAAgA/AG0MAAABADcA6gwAAAQASwBuDAAAAwAqACAABgmoGyEPAL0BBmgMAAAEAFYAaQwAAAMAUABrDAAAAgBTAGoMAAACAEQAbQwAAAEAHQDqDAAAAgBKAAwAAQlEExvIADoAAWwMAAABADEAIQABCc8MS34ANAABbAwAAAEAIAAAAA==.Solthicc:BAAALgAECgUJBQAAAA==.Sonarra:BAAALgAECgYJBgAAAA==.',
Sp='Sparkle:BAACLgAFFH8aAAITAAUJaRQhFwAzAQVoDAAABgBLAGkMAAAHADAAawwAAAQAOgBqDAAAAwAPAOoMAAAGABkAEwAFCWkUIRcAMwEFaAwAAAYASwBpDAAABwAwAGsMAAAEADoAagwAAAMADwDqDAAABgAZAC4ABAp/VAACEwAJCRkgvAQA1wIAEwAJCRkgvAQA1wIAAAA=.Splatacular:BAAALgADCgEJAQAAAA==.',
St='Stolenhearth:BAABLgAECn8jAAIDAAYJRgxTOwD0AAZoDAAABwAgAGkMAAAHACoAawwAAAcAJABqDAAABQAVAGwMAAAEABMA6gwAAAUAGgADAAYJRgxTOwD0AAZoDAAABwAgAGkMAAAHACoAawwAAAcAJABqDAAABQAVAGwMAAAEABMA6gwAAAUAGgAAAA==.',
Sv='Svets:BAABLgAECn8pAAMYAAkJFB5ZBQDcAgloDAAABwBNAGkMAAAHAF0AawwAAAYAUABqDAAABQBGAGwMAAAFAEIAbQwAAAIATwDqDAAABgBbAG4MAAACAEgAbwwAAAEAPAAYAAkJFB5ZBQDcAgloDAAABgBNAGkMAAAHAF0AawwAAAYAUABqDAAABQBGAGwMAAAFAEIAbQwAAAIATwDqDAAABgBbAG4MAAACAEgAbwwAAAEAPAAaAAEJ3AnKhQArAAFoDAAAAQAZAAAA.',
Sw='Swavey:BAAALgADCgQJBAAAAA==.',
Sy='Syrana:BAAALgADCgEJAQAAAA==.',
Te='Teeanna:BAAALgAECgIJAgABLgAECgIJAwAJAAAAAA==.Temaile:BAAALgADCgEJBAAAAA==.Tenin:BAAALgADCgEJAQAAAA==.',
Th='Thinmint:BAAALgADCgEJAQAAAA==.',
Ti='Tinnman:BAAALgADCgYJBgAAAA==.Tippsie:BAEBLgAECn8YAAIbAAYJpiQaCwATAgZoDAAABQBiAGkMAAAFAF4AawwAAAUAYABqDAAAAwBhAGwMAAADAFIA6gwAAAMAYQAbAAYJpiQaCwATAgZoDAAABQBiAGkMAAAFAF4AawwAAAUAYABqDAAAAwBhAGwMAAADAFIA6gwAAAMAYQAAAA==.',
To='Toughguytony:BAAALgADCgUJBgAAAA==.',
Tr='Treydk:BAABLgAFFH8FAAIRAAMJ3AlgZQDfAANoDAAAAgAoAGkMAAACABAA6gwAAAEAEgARAAMJ3AlgZQDfAANoDAAAAgAoAGkMAAACABAA6gwAAAEAEgAAAA==.Trreyy:BAABLgAECn8fAAIKAAgJqh5YKACEAghoDAAABQBcAGkMAAAFAFoAawwAAAQAWwBqDAAABQA/AGwMAAAEAE8AbQwAAAIANwDqDAAABQBcAG4MAAABADAACgAICaoeWCgAhAIIaAwAAAUAXABpDAAABQBaAGsMAAAEAFsAagwAAAUAPwBsDAAABABPAG0MAAACADcA6gwAAAUAXABuDAAAAQAwAAAA.',
Ts='Tsimfuqis:BAAALgAFFAMJBAAAAA==.',
Tw='Twizzy:BAABLgAECn8wAAIIAAgJthJvLADFAQhoDAAABwBOAGkMAAAHAEYAawwAAAYAQwBqDAAABgA+AGwMAAAHAC4AbQwAAAMAFgDqDAAACAAlAG4MAAAEAA0ACAAICbYSbywAxQEIaAwAAAcATgBpDAAABwBGAGsMAAAGAEMAagwAAAYAPgBsDAAABwAuAG0MAAADABYA6gwAAAgAJQBuDAAABAANAAAA.',
Ty='Tyranhikar:BAAALgADCgEJAQAAAA==.',
Tz='Tzechan:BAABLgAECn8aAAMQAAgJWBsSLgDLAQhoDAAABQBHAGkMAAAFADYAawwAAAMAUABqDAAABABRAGwMAAADAFAAbQwAAAEANADqDAAABABbAG4MAAABAC8AEAAHCZgcEi4AywEHaAwAAAUARwBpDAAABQA2AGsMAAADAFAAagwAAAQAUQBsDAAAAwBQAG0MAAABADQA6gwAAAQAWwAKAAEJURE5HQE3AAFuDAAAAQAsAAAA.',
Ug='Uggalee:BAAALgAECgYJCAAAAA==.',
Va='Valtirya:BAAALgAECgQJBgAAAA==.Vayzen:BAABLgAECn8YAAITAAcJDB4uEwBNAgdoDAAABABXAGkMAAADAFIAawwAAAQASwBqDAAABABXAGwMAAAEAFQAbQwAAAIAMQDqDAAAAwBSABMABwkMHi4TAE0CB2gMAAAEAFcAaQwAAAMAUgBrDAAABABLAGoMAAAEAFcAbAwAAAQAVABtDAAAAgAxAOoMAAADAFIAAAA=.',
Vi='Virexus:BAAALgADCgIJAgAAAA==.',
Vo='Voidfree:BAABLgAECn8ZAAINAAYJSwkPdgDRAAZoDAAABQAlAGkMAAAFAB0AawwAAAUAFABqDAAAAwAgAGwMAAACAA8A6gwAAAUADwANAAYJSwkPdgDRAAZoDAAABQAlAGkMAAAFAB0AawwAAAUAFABqDAAAAwAgAGwMAAACAA8A6gwAAAUADwAAAA==.',
Vy='Vynarc:BAABLgAECn8qAAIKAAgJiREmUAB5AQhoDAAABgA3AGkMAAAFAC0AawwAAAUAQQBqDAAABgAyAGwMAAAFADIAbQwAAAMAIADqDAAABwArAG4MAAAFABUACgAICYkRJlAAeQEIaAwAAAYANwBpDAAABQAtAGsMAAAFAEEAagwAAAYAMgBsDAAABQAyAG0MAAADACAA6gwAAAcAKwBuDAAABQAVAAAA.',
Wa='Warcrimes:BAAALgAECgEJAQAAAA==.Watervendor:BAABLgAECn8lAAIFAAgJOBzlKAAjAghoDAAABgBSAGkMAAAGAD8AawwAAAUASQBqDAAABAA6AGwMAAAEAFIAbQwAAAIAOADqDAAABwBUAG4MAAADAD8ABQAICTgc5SgAIwIIaAwAAAYAUgBpDAAABgA/AGsMAAAFAEkAagwAAAQAOgBsDAAABABSAG0MAAACADgA6gwAAAcAVABuDAAAAwA/AAAA.',
We='Wearegroot:BAAALgAECgEJAQAAAA==.Webedeadiy:BAAALgADCgEJAQAAAA==.',
Wi='Wiggimbottom:BAAALgAECgYJEgAAAA==.Wihtè:BAAALgADCgUJCQAAAA==.Willscarlet:BAAALgADCgMJAwAAAA==.',
Wo='Wolffoxfangs:BAAALgAECgYJDQAAAA==.',
Xe='Xeados:BAAALgAECgIJAgAAAA==.',
Yi='Yin:BAAALgADCgcJDQAAAA==.',
Za='Zaquel:BAAALgAECgUJBQAAAA==.Zarcissa:BAAALgAECgMJBgAAAA==.Zavira:BAAALgADCgcJBwAAAA==.',
Zy='Zyrin:BAAALgAECgYJDwAAAA==.',
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
