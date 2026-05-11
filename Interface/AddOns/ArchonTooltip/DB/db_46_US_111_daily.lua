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

local lookup = {'Monk-Mistweaver','Warrior-Arms','Warrior-Fury','Warrior-Protection','Mage-Frost','Warlock-Demonology','Hunter-BeastMastery','Unknown-Unknown','Paladin-Retribution','Hunter-Survival','Druid-Restoration','DemonHunter-Devourer','Evoker-Preservation','Evoker-Devastation','Paladin-Holy','DeathKnight-Unholy','Warlock-Affliction','Monk-Windwalker','Monk-Brewmaster','DeathKnight-Blood','DemonHunter-Havoc','Priest-Shadow','Priest-Holy','Rogue-Subtlety','Priest-Discipline','Shaman-Elemental','Shaman-Enhancement','Rogue-Assassination','Druid-Guardian','Druid-Feral','Druid-Balance','Evoker-Augmentation',}
local provider = {region='US',realm='Gorgonnash',name='US',type='daily',zone=46,date='2026-05-10',data={Aa='Aakira:BAAALgAECgcJDQAAAA==.Aangie:BAABLgAECn8YAAIBAAcJngbANgDBAAdoDAAABAAdAGkMAAAEAAsAawwAAAQACwBqDAAAAwAJAGwMAAADABoA6gwAAAQAFQBuDAAAAgAIAAEABwmeBsA2AMEAB2gMAAAEAB0AaQwAAAQACwBrDAAABAALAGoMAAADAAkAbAwAAAMAGgDqDAAABAAVAG4MAAACAAgAAAA=.Aanjie:BAABLgAECn8aAAIBAAYJQwk9MADlAAZoDAAABQAmAGkMAAAFABMAawwAAAUAGABqDAAABAAWAGwMAAADABMA6gwAAAQAEwABAAYJQwk9MADlAAZoDAAABQAmAGkMAAAFABMAawwAAAUAGABqDAAABAAWAGwMAAADABMA6gwAAAQAEwAAAA==.',
Ab='Abban:BAAALgAECgMJAwAAAA==.Abrastal:BAAALgAECgQJCAAAAA==.',
Ad='Adrestia:BAAALgADCgcJBwAAAA==.',
Ak='Akbar:BAAALgAECgUJBQAAAA==.',
Al='Alline:BAAALgAECgYJDAAAAA==.Alswaron:BAAALgAECgUJDQAAAA==.',
Am='Amador:BAACLgAFFH8GAAQCAAMJrAxuFgB4AANoDAAAAwA1AGkMAAABAAIA6gwAAAIAKQACAAIJ8gpuFgB4AAJoDAAAAgA1AGkMAAABAAIAAwABCdQPFSEAUwABaAwAAAEAKAAEAAEJIBCcDwBHAAHqDAAAAgApAC4ABAp/JwAEAgAICQUhLQQAVgIAAgAHCQUhLQQAVgIAAwAECd0a6GkADgEABAACCZwQjDoAdwAAAAA=.Amorlan:BAAALgAECgEJAQAAAA==.Amyra:BAAALgAECgEJAQAAAA==.',
An='Annox:BAAALgAECgQJBwAAAA==.',
Ap='Apsallar:BAAALgAECgcJDgAAAA==.',
Ar='Arcanism:BAABLgAECn8cAAIFAAcJsBNucQA1AQdoDAAABgBMAGkMAAAGADcAawwAAAYANQBqDAAAAwBBAGwMAAABAC0AbQwAAAEAGgDqDAAABQAtAAUABwmwE25xADUBB2gMAAAGAEwAaQwAAAYANwBrDAAABgA1AGoMAAADAEEAbAwAAAEALQBtDAAAAQAaAOoMAAAFAC0AAAA=.Arlas:BAAALgAECgIJAwAAAA==.Arthone:BAAALgADCgUJBQAAAA==.',
As='Asstalor:BAABLgAECn8XAAIGAAgJXQ8wNQCVAQhoDAAABAAlAGkMAAAEACoAawwAAAQAHwBqDAAABAAxAGwMAAACAD0AbQwAAAEAIgDqDAAAAwAnAG4MAAABABsABgAICV0PMDUAlQEIaAwAAAQAJQBpDAAABAAqAGsMAAAEAB8AagwAAAQAMQBsDAAAAgA9AG0MAAABACIA6gwAAAMAJwBuDAAAAQAbAAAA.',
Au='Auggy:BAAALgADCgEJAQAAAA==.Auryon:BAABLgAECn8nAAIHAAgJJyEDDgBvAghoDAAACABdAGkMAAAGAFEAawwAAAcAVwBqDAAABAA1AGwMAAAGAEwAbQwAAAEAUADqDAAABgBTAG4MAAABAFoABwAICSchAw4AbwIIaAwAAAgAXQBpDAAABgBRAGsMAAAHAFcAagwAAAQANQBsDAAABgBMAG0MAAABAFAA6gwAAAYAUwBuDAAAAQBaAAAA.',
Av='Avelna:BAAALgADCgYJBgABLgADCgcJDQAIAAAAAA==.',
Az='Azmodea:BAAALgADCgEJAgAAAA==.',
Ba='Baccstab:BAAALgAECgYJDAAAAA==.Bagains:BAAALgADCgcJDwAAAA==.Baraka:BAAALgAECgYJCgAAAA==.Baulder:BAAALgAECgUJBgAAAA==.',
Bi='Bigb:BAAALgAECggJDwABLgAFFAgJHQAFAI8jAA==.Bigolcrittie:BAAALgADCgIJAgAAAA==.',
Bl='Bloodfurry:BAAALgAECgEJAQAAAA==.Bluè:BAAALgAECgcJEQAAAA==.',
Bo='Bobdaunicorn:BAAALgAECgEJAQAAAA==.Boltz:BAAALgAECgMJAwAAAA==.Bombalaharis:BAAALgAECgcJDQAAAA==.',
Br='Brekke:BAABLgAECn8oAAIJAAkJdRb8JwDqAQloDAAABgBBAGkMAAAFAFEAawwAAAUASgBqDAAABQArAGwMAAAFAEAAbQwAAAMAFgDqDAAABgA7AG4MAAADAD8AbwwAAAIAGwAJAAkJdRb8JwDqAQloDAAABgBBAGkMAAAFAFEAawwAAAUASgBqDAAABQArAGwMAAAFAEAAbQwAAAMAFgDqDAAABgA7AG4MAAADAD8AbwwAAAIAGwAAAA==.Brokenbow:BAABLgAECn8XAAMKAAkJphNtEQCsAQloDAAAAwA2AGkMAAADAEMAawwAAAMAQQBqDAAAAgAfAGwMAAADAEgAbQwAAAMALQDqDAAAAwBJAG4MAAACAAUAbwwAAAEAEQAKAAkJVg5tEQCsAQloDAAAAgAdAGkMAAADAEMAawwAAAMAQQBqDAAAAgAfAGwMAAABAB0AbQwAAAIAIwDqDAAAAgAqAG4MAAACAAUAbwwAAAEAEQAHAAQJCBjBfQDuAARoDAAAAQA2AGwMAAACAEgAbQwAAAEALQDqDAAAAQBJAAAA.',
Bu='Bullshaft:BAAALgAECgEJAQAAAA==.Buntz:BAABLgAECn8cAAIJAAkJGSI/BAAXAwloDAAABABjAGkMAAAEAFEAawwAAAQAWABqDAAAAwBQAGwMAAACAFoAbQwAAAIAUQDqDAAAAwBWAG4MAAADAFkAbwwAAAMAUAAJAAkJGSI/BAAXAwloDAAABABjAGkMAAAEAFEAawwAAAQAWABqDAAAAwBQAGwMAAACAFoAbQwAAAIAUQDqDAAAAwBWAG4MAAADAFkAbwwAAAMAUAAAAA==.Bushmethsin:BAACLgAFFH8SAAILAAUJHCP6BAD9AQVoDAAABgBdAGkMAAAEAF8AawwAAAMAXQBqDAAAAQBJAOoMAAAEAF0ACwAFCRwj+gQA/QEFaAwAAAYAXQBpDAAABABfAGsMAAADAF0AagwAAAEASQDqDAAABABdAC4ABAp/FAACCwAICVUiDB4ATgIACwAICVUiDB4ATgIAAAA=.Buttery:BAAALgAECgUJDwAAAA==.',
Ca='Cabb:BAAALgAECgQJBAAAAA==.',
Ce='Ceedubble:BAAALgAECggJDAAAAA==.Celestine:BAAALgADCgYJBgABLgAECggJIAAMAGANAA==.',
Ch='Charmanderz:BAABLgAECn8jAAMNAAgJfw0IDwBcAQhoDAAABgA4AGkMAAAGAB8AawwAAAYAJQBqDAAABAAQAGwMAAAEADgAbQwAAAIABwDqDAAABgBCAG4MAAABAAUADQAICX8NCA8AXAEIaAwAAAYAOABpDAAABgAfAGsMAAAGACUAagwAAAQAEABsDAAAAwA4AG0MAAACAAcA6gwAAAYAQgBuDAAAAQAFAA4AAQkiFaM7AD8AAWwMAAABADYAAAA=.Cherchlglsia:BAAALgADCgQJCAAAAA==.Chewsdee:BAAALgAECgQJBAAAAA==.Christlovesu:BAAALgAECgIJAgAAAA==.Chuckrules:BAAALgADCgcJDgAAAA==.',
Cl='Clackshi:BAAALgAECgYJCgAAAA==.',
Cr='Critable:BAABLgAECn8mAAMPAAkJAhHvFgDhAQloDAAABgAoAGkMAAAFACcAawwAAAUAMwBqDAAABQBAAGwMAAAFADIAbQwAAAMAFgDqDAAABQAsAG4MAAADADUAbwwAAAEAGQAPAAkJAhHvFgDhAQloDAAABQAoAGkMAAAEACcAawwAAAQAMwBqDAAABABAAGwMAAAEADIAbQwAAAIAFgDqDAAABAAsAG4MAAACADUAbwwAAAEAGQAJAAgJNggYggB2AQhoDAAAAQAbAGkMAAABABAAawwAAAEAHwBqDAAAAQAGAGwMAAABABQAbQwAAAEADgDqDAAAAQAYAG4MAAABAAwAAAA=.',
Cu='Curst:BAAALgAECggJEwAAAA==.',
Da='Dagares:BAAALgADCggJDQAAAA==.Dahnte:BAAALgAECgEJAQAAAA==.',
De='Dechala:BAABLgAECn8gAAIMAAgJYA0CPQBNAQhoDAAABQAoAGkMAAAEACYAawwAAAQAKABqDAAABQAgAGwMAAAEAC0AbQwAAAIAFQDqDAAABQAjAG4MAAADABAADAAICWANAj0ATQEIaAwAAAUAKABpDAAABAAmAGsMAAAEACgAagwAAAUAIABsDAAABAAtAG0MAAACABUA6gwAAAUAIwBuDAAAAwAQAAAA.Deezknights:BAACLgAFFH8PAAIQAAUJ4yGCHQBrAQVoDAAABABcAGkMAAADAGAAawwAAAIAQABqDAAAAgBNAOoMAAAEAF4AEAAFCeMhgh0AawEFaAwAAAQAXABpDAAAAwBgAGsMAAACAEAAagwAAAIATQDqDAAABABeAC4ABAp/HwACEAAJCQYlTAkAUgMAEAAJCQYlTAkAUgMAAAA=.Deezpuffs:BAAALgAFFAMJAwABLgAFFAUJDwAQAOMhAA==.Deezrage:BAAALgADCgYJBgAAAA==.Derailed:BAAALgADCgEJAgAAAA==.Dergon:BAABLgAECn8iAAIGAAgJ1RrOGwAPAghoDAAABABKAGkMAAADAEQAawwAAAMAMABqDAAABQA8AGwMAAAFAFEAbQwAAAQAPADqDAAABwBiAG4MAAADADEABgAICdUazhsADwIIaAwAAAQASgBpDAAAAwBEAGsMAAADADAAagwAAAUAPABsDAAABQBRAG0MAAAEADwA6gwAAAcAYgBuDAAAAwAxAAAA.Destiria:BAABLgAECn8kAAMGAAgJtBnQGwAPAghoDAAABgBHAGkMAAAGACkAawwAAAUAOABqDAAABAAgAGwMAAAFAFcAbQwAAAMAWADqDAAABQAwAG4MAAACAEMABgAICbQZ0BsADwIIaAwAAAUARwBpDAAABQApAGsMAAAFADgAagwAAAQAIABsDAAABQBXAG0MAAADAFgA6gwAAAQAMABuDAAAAgBDABEAAwl5B3knAFQAA2gMAAABAAgAaQwAAAEABgDqDAAAAQAqAAAA.Devistatorxx:BAAALgAECgUJBQAAAA==.',
Do='Doggyystyle:BAAALgAECgEJAQAAAA==.Donaldpump:BAAALgAECgYJBwAAAA==.Doomedturtle:BAAALgADCgYJCQAAAA==.Doublekill:BAAALgAECgUJCQAAAA==.',
Du='Duergan:BAABLgAECn8mAAQSAAgJEBSrFQCKAQhoDAAABwA2AGkMAAAHADsAawwAAAQAJwBqDAAAAwAgAGwMAAAEACgAbQwAAAQAMADqDAAABgBKAG4MAAADACoAEgAICRAUqxUAigEIaAwAAAYANgBpDAAABgA7AGsMAAADACcAagwAAAIAIABsDAAAAwAoAG0MAAADADAA6gwAAAUASgBuDAAAAwAqABMABglvBcE2AMUABmgMAAABAAsAaQwAAAEAEABrDAAAAQAQAGoMAAABAAgAbAwAAAEAEwBtDAAAAQAEAAEAAQlFAwRyACEAAeoMAAABAAgAAAA=.',
Ea='Eatz:BAAALgADCgYJBgAAAA==.',
Fa='Faelyn:BAAALgADCgEJBAAAAA==.Fansy:BAAALgAECgEJAQAAAA==.',
Fi='Fillycheese:BAAALgAECgEJAQAAAA==.',
Fl='Fleurelle:BAAALgAECgIJAgAAAA==.',
Fr='Frollo:BAAALgAECgEJAQAAAA==.Frosstitute:BAAALgAECgMJAwAAAA==.',
Fu='Furfiend:BAABLgAECn8XAAIQAAYJjRyZWQA+AQZoDAAABgBUAGkMAAAGAFEAawwAAAQAKgBqDAAAAQAWAOoMAAACAEUAbgwAAAQAVwAQAAYJjRyZWQA+AQZoDAAABgBUAGkMAAAGAFEAawwAAAQAKgBqDAAAAQAWAOoMAAACAEUAbgwAAAQAVwAAAA==.',
Gi='Giantdog:BAAALgAECgUJBQAAAA==.Gilraen:BAABLgAECn8rAAMCAAgJxhS+CQC8AQhoDAAABwAqAGkMAAAHACcAawwAAAUAJwBqDAAABQA/AGwMAAAFADMAbQwAAAQAKADqDAAABwBgAG4MAAADAD4AAgAICQYSvgkAvAEIaAwAAAEAHQBpDAAAAQAZAGsMAAABAB0AagwAAAIAPwBsDAAAAgAnAG0MAAACACgA6gwAAAIAYABuDAAAAgA+AAMACAl1DmpNAHEBCGgMAAAGACoAaQwAAAYAJwBrDAAABAAnAGoMAAADABgAbAwAAAMAMwBtDAAAAgAYAOoMAAAFAB0AbgwAAAEAHwAAAA==.Gingerjen:BAAALgAECgYJBgAAAA==.',
Go='Gorgrand:BAAALgAECgcJBwAAAA==.Gothbiotch:BAAALgAECgMJAwAAAA==.',
Gr='Greggnog:BAAALgAECgcJDAAAAA==.Greggy:BAAALgAECgUJCQABLgAECgcJDAAIAAAAAA==.Grenache:BAAALgAECgMJBAAAAA==.',
Ha='Halfworld:BAAALgADCgYJBgAAAA==.Happydaze:BAABLgAECn8fAAMUAAgJ7RmUCwDIAQhoDAAABQBIAGkMAAADAEQAawwAAAQANABqDAAABgBRAGwMAAAEAD0AbQwAAAIARwDqDAAABgBLAG4MAAABAD4AFAAICZQZlAsAyAEIaAwAAAUASABpDAAAAwBEAGsMAAAEADQAagwAAAUAPwBsDAAAAgA2AG0MAAACAEcA6gwAAAYASwBuDAAAAQA+ABAAAgnZF37uAKEAAmoMAAABAFEAbAwAAAIAPQAAAA==.Haxthedruid:BAAALgAECgEJAQAAAA==.Haxthemonk:BAAALgAECgEJAQAAAA==.',
He='Hemotoxin:BAAALgAECgMJAwAAAA==.Hendel:BAAALgAECgQJBgAAAA==.Herkaferk:BAAALgAECgYJEwAAAA==.',
Ho='Hojx:BAAALgAECgEJAQAAAA==.',
Hr='Hrolf:BAAALgAECgUJDwABLgAECggJJgASABAUAA==.',
Il='Illiannà:BAAALgAECgYJCQABLgAECggJIwANAH8NAA==.Illidont:BAAALgAECgYJCgAAAA==.Illijr:BAABLgAECn8WAAIVAAgJ+g6sEQB6AQhoDAAABAA2AGkMAAADAB0AawwAAAMAIQBqDAAAAwAnAGwMAAACACgAbQwAAAEAKgDqDAAABQAnAG4MAAABAB0AFQAICfoOrBEAegEIaAwAAAQANgBpDAAAAwAdAGsMAAADACEAagwAAAMAJwBsDAAAAgAoAG0MAAABACoA6gwAAAUAJwBuDAAAAQAdAAAA.',
It='Ithil:BAAALgADCgkJDwAAAA==.',
Ja='Jaemison:BAAALgADCgQJAwAAAA==.',
Ji='Jicks:BAAALgAECgYJEwAAAA==.',
Jk='Jkass:BAAALgAECgYJEwAAAA==.',
Ju='Judgementdày:BAAALgAECgQJCgAAAA==.',
['Jà']='Jàk:BAAALgADCgUJBQAAAA==.',
Ka='Kamaeria:BAABLgAECn8jAAIWAAgJKQ+UFgCXAQhoDAAABQAQAGkMAAAFABkAawwAAAUAEwBqDAAABQAnAGwMAAAEAC0AbQwAAAMAIgDqDAAABgBbAG4MAAACACYAFgAICSkPlBYAlwEIaAwAAAUAEABpDAAABQAZAGsMAAAFABMAagwAAAUAJwBsDAAABAAtAG0MAAADACIA6gwAAAYAWwBuDAAAAgAmAAEuAAQKCAkpAAcA5A8A.Kaíros:BAAALgADCgMJAwAAAA==.',
Kh='Khaotica:BAAALgADCgkJCQAAAA==.',
Ki='Kiandara:BAACLgAFFH8RAAMDAAUJvxP/DAA3AQVoDAAABABUAGkMAAAFAEEAawwAAAQAHABqDAAAAgBFAOoMAAACABcAAwAFCdcO/wwANwEFaAwAAAQAVABpDAAABAAgAGsMAAADABkAagwAAAIARQDqDAAAAQAJAAIAAwliD6MOANYAA2kMAAABAEEAawwAAAEAHADqDAAAAQAXAC4ABAp/IQADAwAJCfEb8gwA7gIAAwAJCcUb8gwA7gIABAAFCRwb3R0AVwEAAAA=.Kikkoman:BAAALgAFFAEJAQAAAA==.Kilmas:BAAALgAECgIJAgAAAA==.Kirant:BAAALgADCggJDQAAAA==.Kirara:BAAALgADCgYJBgAAAA==.',
Ko='Kooz:BAAALgADCgUJBQAAAA==.Kooze:BAAALgADCgUJCAAAAA==.Koozo:BAAALgADCgMJAwAAAA==.',
Kt='Kt:BAABLgAECn8aAAIFAAcJNhNBUwB5AQdoDAAABQAzAGkMAAAFAEcAawwAAAUAHgBqDAAAAgA3AGwMAAADADoA6gwAAAQAOgBuDAAAAgAYAAUABwk2E0FTAHkBB2gMAAAFADMAaQwAAAUARwBrDAAABQAeAGoMAAACADcAbAwAAAMAOgDqDAAABAA6AG4MAAACABgAAAA=.',
Ky='Kynrath:BAAALgAECgIJAwAAAA==.',
La='Laurie:BAAALgADCgMJBgAAAA==.Lava:BAAALgADCgUJBQABLgAECggJDwAIAAAAAA==.Lavablast:BAAALgADCgYJCwAAAA==.',
Le='Lelanie:BAAALgADCggJDgAAAA==.',
Li='Lichnfamous:BAAALgAECgcJEQAAAA==.Lightfrost:BAAALgADCgIJAgAAAA==.Lightning:BAAALgAECgUJCAAAAA==.Likkan:BAAALgAECgEJAQAAAA==.Lilithdawn:BAABLgAECn8hAAIXAAkJvhu3BgCTAgloDAAABgBYAGkMAAAGAE8AawwAAAUAUABqDAAABABdAGwMAAAEAFYAbQwAAAEAOgDqDAAABQApAG4MAAABAEkAbwwAAAEAJgAXAAkJvhu3BgCTAgloDAAABgBYAGkMAAAGAE8AawwAAAUAUABqDAAABABdAGwMAAAEAFYAbQwAAAEAOgDqDAAABQApAG4MAAABAEkAbwwAAAEAJgAAAA==.',
Lo='Lockwar:BAAALgAECgYJEAAAAA==.Louvre:BAABLgAECn8hAAIYAAkJAxgfBQB2AgloDAAABABTAGkMAAAFAF8AawwAAAYATwBqDAAABABEAGwMAAAEADIAbQwAAAEAEQDqDAAABQA+AG4MAAADADgAbwwAAAEALwAYAAkJAxgfBQB2AgloDAAABABTAGkMAAAFAF8AawwAAAYATwBqDAAABABEAGwMAAAEADIAbQwAAAEAEQDqDAAABQA+AG4MAAADADgAbwwAAAEALwAAAA==.',
Lu='Lukarian:BAAALgAECgQJBQAAAA==.',
Ma='Makthra:BAAALgAECgUJDgAAAA==.Marek:BAAALgADCgUJCAAAAA==.Marionette:BAAALgADCggJGQAAAA==.Mawseeker:BAAALgADCgEJAQAAAA==.',
Me='Megabettegaa:BAABLgAECn9RAAIQAAkJLhfbGwAuAgloDAAACwBMAGkMAAAMAD4AawwAAA0ANQBqDAAACwBCAGwMAAAKADsAbQwAAAcAMgDqDAAACQBLAG4MAAAGAEMAbwwAAAIAHgAQAAkJLhfbGwAuAgloDAAACwBMAGkMAAAMAD4AawwAAA0ANQBqDAAACwBCAGwMAAAKADsAbQwAAAcAMgDqDAAACQBLAG4MAAAGAEMAbwwAAAIAHgAAAA==.Mennathil:BAAALgADCgEJAQAAAA==.Meric:BAAALgADCgcJDgAAAA==.',
Mi='Midnight:BAAALgAECgcJCQAAAA==.Milo:BAAALgAECgQJCwAAAA==.Miniangel:BAACLgAFFH8HAAIXAAMJNQ/cEQDNAANoDAAABAAUAGkMAAACACMA6gwAAAEAPAAXAAMJNQ/cEQDNAANoDAAABAAUAGkMAAACACMA6gwAAAEAPAAuAAQKfx4AAxcACQl9FYgJAFoCABcACQl9FYgJAFoCABYACAk+EO4oAJMBAAAA.Mixednuts:BAAALgAECgIJAgAAAA==.',
Mo='Molasses:BAACLgAFFH8IAAIFAAMJVwsCUADyAANoDAAABAAfAGkMAAADACAA6gwAAAEAFwAFAAMJVwsCUADyAANoDAAABAAfAGkMAAADACAA6gwAAAEAFwAuAAQKfzAAAgUACQl4GSQUAIECAAUACQl4GSQUAIECAAAA.Moof:BAAALgAECgEJAQAAAA==.',
Na='Najitar:BAAALgAECgEJAQAAAA==.Nazaibrew:BAAALgADCgYJBgABLgAECgkJKQAZABQeAA==.',
Ne='Necromalus:BAAALgADCgEJAwAAAA==.Neerx:BAAALgADCgUJBQAAAA==.',
Nu='Nubkselk:BAABLgAECn8lAAIMAAgJqx4dDQBsAghoDAAABwBXAGkMAAAGAEwAawwAAAYAVQBqDAAABQA3AGwMAAAEAE4AbQwAAAEARADqDAAABQA+AG4MAAADAFoADAAICaseHQ0AbAIIaAwAAAcAVwBpDAAABgBMAGsMAAAGAFUAagwAAAUANwBsDAAABABOAG0MAAABAEQA6gwAAAUAPgBuDAAAAwBaAAAA.Nurishment:BAACLgAFFH8ZAAILAAYJPhRGCAC9AQZoDAAABgAwAGkMAAAFADIAawwAAAQASABqDAAABAAoAGwMAAABAEEA6gwAAAUAIQALAAYJPhRGCAC9AQZoDAAABgAwAGkMAAAFADIAawwAAAQASABqDAAABAAoAGwMAAABAEEA6gwAAAUAIQAuAAQKfyMAAgsACQn7HWwSAKICAAsACQn7HWwSAKICAAAA.',
Ny='Nyrr:BAAALgADCgEJAgAAAA==.',
Og='Ogmurka:BAAALgAECgEJAQAAAA==.',
On='Oni:BAAALgADCgUJBQAAAA==.Onitachi:BAABLgAECn8rAAMaAAgJzxHQIgBHAQhoDAAABwBLAGkMAAAHADYAawwAAAgANABqDAAABAA1AGwMAAAEAB0AbQwAAAIACgDqDAAABwAxAG4MAAAEADAAGgAICc8R0CIARwEIaAwAAAcASwBpDAAABwA2AGsMAAAHADQAagwAAAIANQBsDAAAAwAdAG0MAAACAAoA6gwAAAYAMQBuDAAABAAwABsABAlwCYQXAJ4ABGsMAAABABkAagwAAAIAFABsDAAAAQAVAOoMAAABABkAAAA=.',
Op='Optistriker:BAABLgAECn8oAAILAAgJUhVSHADtAQhoDAAABwAmAGkMAAAGAEAAawwAAAYAPwBqDAAABQA9AGwMAAAFADAAbQwAAAMAJgDqDAAABgBCAG4MAAACADYACwAICVIVUhwA7QEIaAwAAAcAJgBpDAAABgBAAGsMAAAGAD8AagwAAAUAPQBsDAAABQAwAG0MAAADACYA6gwAAAYAQgBuDAAAAgA2AAAA.',
Oy='Oythsar:BAAALgADCgQJBAAAAA==.',
Pa='Painfree:BAAALgADCgQJBAAAAA==.Papabear:BAAALgAECgEJAQAAAA==.',
Pi='Pig:BAABLgAECn8cAAIDAAgJKhjZKwAGAghoDAAABgBBAGkMAAAFAEsAawwAAAUAVABqDAAAAwA4AGwMAAADAEEAbQwAAAEAFgDqDAAABAA8AG4MAAABADoAAwAICSoY2SsABgIIaAwAAAYAQQBpDAAABQBLAGsMAAAFAFQAagwAAAMAOABsDAAAAwBBAG0MAAABABYA6gwAAAQAPABuDAAAAQA6AAEuAAQKCQkcAAkAGSIA.Pinks:BAAALgADCgkJCQAAAA==.',
Po='Poplockndrop:BAAALgAECgUJBgAAAA==.Portion:BAABLgAECn8oAAIFAAcJaBwCWgArAgdoDAAACABUAGkMAAAIAE4AawwAAAgAXABqDAAABQBKAGwMAAAEAFEAbQwAAAEAIgDqDAAABgBBAAUABwloHAJaACsCB2gMAAAIAFQAaQwAAAgATgBrDAAACABcAGoMAAAFAEoAbAwAAAQAUQBtDAAAAQAiAOoMAAAGAEEAAAA=.',
Pr='Pretentious:BAABLgAECn8YAAIJAAgJoh8nJgCOAghoDAAABABcAGkMAAADAF0AawwAAAMAVgBqDAAAAwAsAGwMAAAEAFsAbQwAAAIAOwDqDAAABABFAG4MAAABAEoACQAICaIfJyYAjgIIaAwAAAQAXABpDAAAAwBdAGsMAAADAFYAagwAAAMALABsDAAABABbAG0MAAACADsA6gwAAAQARQBuDAAAAQBKAAAA.Prettyfun:BAAALgADCgUJBQAAAA==.Prettysavage:BAAALgAECgIJAgAAAA==.Primo:BAAALgADCgYJEQAAAA==.',
Ra='Radicalism:BAAALgAECgQJBQAAAA==.Ranigard:BAAALgAECgUJCAAAAA==.Rantioc:BAAALgAECgIJAgAAAA==.Raugan:BAAALgAECgEJAQAAAA==.',
Re='Reparations:BAAALgAECgkJBgAAAA==.Repentofsin:BAAALgAECgQJBAAAAA==.Rexbriefs:BAAALgAECgcJCAAAAA==.',
Ri='Riptong:BAAALgADCgEJAQAAAA==.',
Ro='Rovinj:BAAALgAECgkJBQAAAA==.',
Ru='Rumi:BAABLgAECn8bAAIMAAgJNhKhLACOAQhoDAAABgBSAGkMAAAFADEAawwAAAQAIQBqDAAAAwAyAGwMAAACADQAbQwAAAEAIgDqDAAABQAqAG4MAAABAB8ADAAICTYSoSwAjgEIaAwAAAYAUgBpDAAABQAxAGsMAAAEACEAagwAAAMAMgBsDAAAAgA0AG0MAAABACIA6gwAAAUAKgBuDAAAAQAfAAAA.',
Ry='Rydle:BAAALgAECgYJBgAAAA==.',
Sa='Sanlesh:BAAALgADCgUJBgAAAA==.Sapodillà:BAAALgAECgcJBwAAAA==.Sarijevo:BAAALgAECgkJBQAAAA==.Saurax:BAAALgADCgMJAwAAAA==.',
Sc='Scatz:BAAALgADCgIJAgAAAA==.Scott:BAAALgAECgcJBwAAAA==.Scylla:BAAALgAECgYJDwAAAA==.',
Se='Sevrin:BAACLgAFFH8GAAIYAAIJ1ht7EQC9AAJoDAAABABCAGkMAAACAEsAGAACCdYbexEAvQACaAwAAAQAQgBpDAAAAgBLAC4ABAp/JAACGAAICVUjOwMAsAIAGAAICVUjOwMAsAIAAAA=.',
Sh='Shadowfuryy:BAAALgAECgUJBQAAAA==.Shalati:BAAALgADCgYJBgAAAA==.Shestrouble:BAAALgAFFAIJAgAAAA==.Shirerat:BAAALgADCgMJBAAAAA==.Shtzson:BAAALgAECgYJBgABLgAECgcJEwAIAAAAAA==.Shyjinx:BAAALgAECgYJBgAAAA==.Shîft:BAABLgAECn8jAAMYAAgJxyCFFAB1AQhoDAAABgBeAGkMAAAGAFMAawwAAAUAVwBqDAAABABYAGwMAAAEAFUAbQwAAAIAQADqDAAABgBgAG4MAAACAEoAGAAGCQ4ihRQAdQEGaAwAAAYAXgBpDAAAAQBSAGsMAAAFAFcAagwAAAQAWADqDAAABgBgAG4MAAACAEoAHAADCX8eWwwAAgEDaQwAAAUAUwBsDAAABABVAG0MAAACAEAAAAA=.',
Si='Siiwwy:BAAALgAECgMJAwAAAA==.',
Sl='Slice:BAAALgAECgUJDAAAAA==.',
So='Solicide:BAABLgAECn8jAAUdAAgJKxs0BwDcAQhoDAAABgBWAGkMAAAGAFAAawwAAAUAUwBqDAAABQBEAGwMAAAEAD8AbQwAAAIANwDqDAAABQBLAG4MAAACACoAHQAICTcXNAcA3AEIaAwAAAIAJwBpDAAAAwBCAGsMAAADAEkAagwAAAMAOABsDAAAAgA/AG0MAAABADcA6gwAAAMASwBuDAAAAgAqAB4ABgmoGyEPAL0BBmgMAAAEAFYAaQwAAAMAUABrDAAAAgBTAGoMAAACAEQAbQwAAAEAHQDqDAAAAgBKAAsAAQlEExzIADoAAWwMAAABADEAHwABCc8MSX4ANAABbAwAAAEAIAAAAA==.Sonarra:BAAALgAECgYJBgAAAA==.',
Sp='Sparkle:BAACLgAFFH8VAAIgAAUJaRSwFwAvAQVoDAAABQBLAGkMAAAGADAAawwAAAMAOgBqDAAAAgAPAOoMAAAFABkAIAAFCWkUsBcALwEFaAwAAAUASwBpDAAABgAwAGsMAAADADoAagwAAAIADwDqDAAABQAZAC4ABAp/VAACIAAJCRkgGQMA8gIAIAAJCRkgGQMA8gIAAAA=.Splatacular:BAAALgADCgEJAQAAAA==.',
St='Stolenhearth:BAABLgAECn8bAAIDAAYJewsINQD6AAZoDAAABQAgAGkMAAAFACAAawwAAAUAJABqDAAABAAVAGwMAAAEABMA6gwAAAQAGgADAAYJewsINQD6AAZoDAAABQAgAGkMAAAFACAAawwAAAUAJABqDAAABAAVAGwMAAAEABMA6gwAAAQAGgAAAA==.',
Sv='Svets:BAABLgAECn8pAAMZAAkJFB4IBADqAgloDAAABwBNAGkMAAAHAF0AawwAAAYAUABqDAAABQBGAGwMAAAFAEIAbQwAAAIATwDqDAAABgBbAG4MAAACAEgAbwwAAAEAPAAZAAkJFB4IBADqAgloDAAABgBNAGkMAAAHAF0AawwAAAYAUABqDAAABQBGAGwMAAAFAEIAbQwAAAIATwDqDAAABgBbAG4MAAACAEgAbwwAAAEAPAAXAAEJ3AnKhQArAAFoDAAAAQAZAAAA.',
Sw='Swavey:BAAALgADCgQJBAAAAA==.',
Sy='Syrana:BAAALgADCgEJAQAAAA==.',
Te='Teeanna:BAAALgAECgIJAgABLgAECgIJAwAIAAAAAA==.Temaile:BAAALgADCgEJBAAAAA==.Tenin:BAAALgADCgEJAQAAAA==.',
Th='Thinmint:BAAALgADCgEJAQAAAA==.',
Ti='Tinnman:BAAALgADCgYJBgAAAA==.Tippsie:BAEBLgAECn8VAAIYAAYJ4SMgCgAFAgZoDAAABABcAGkMAAAEAFwAawwAAAQAXgBqDAAAAwBhAGwMAAADAFIA6gwAAAMAYQAYAAYJ4SMgCgAFAgZoDAAABABcAGkMAAAEAFwAawwAAAQAXgBqDAAAAwBhAGwMAAADAFIA6gwAAAMAYQAAAA==.',
To='Toughguytony:BAAALgADCgUJBgAAAA==.',
Tr='Treydk:BAABLgAFFH8FAAIQAAMJ3AmxWgDjAANoDAAAAgAoAGkMAAACABAA6gwAAAEAEgAQAAMJ3AmxWgDjAANoDAAAAgAoAGkMAAACABAA6gwAAAEAEgAAAA==.Trreyy:BAABLgAECn8fAAIJAAgJqh5TKACEAghoDAAABQBcAGkMAAAFAFoAawwAAAQAWwBqDAAABQA/AGwMAAAEAE8AbQwAAAIANwDqDAAABQBcAG4MAAABADAACQAICaoeUygAhAIIaAwAAAUAXABpDAAABQBaAGsMAAAEAFsAagwAAAUAPwBsDAAABABPAG0MAAACADcA6gwAAAUAXABuDAAAAQAwAAAA.',
Ts='Tsimfuqis:BAAALgAFFAMJAwAAAA==.',
Tw='Twizzy:BAABLgAECn8pAAIHAAgJ5A+DLgCXAQhoDAAABgBKAGkMAAAGADYAawwAAAUALgBqDAAABQAZAGwMAAAGACQAbQwAAAMAFgDqDAAABwAkAG4MAAADAA0ABwAICeQPgy4AlwEIaAwAAAYASgBpDAAABgA2AGsMAAAFAC4AagwAAAUAGQBsDAAABgAkAG0MAAADABYA6gwAAAcAJABuDAAAAwANAAAA.',
Ty='Tyranhikar:BAAALgADCgEJAQAAAA==.',
Tz='Tzechan:BAABLgAECn8VAAMPAAgJWBsTLgDLAQhoDAAABABHAGkMAAAEADYAawwAAAIAUABqDAAAAwBRAGwMAAACAFAAbQwAAAEANADqDAAABABbAG4MAAABAC8ADwAHCZgcEy4AywEHaAwAAAQARwBpDAAABAA2AGsMAAACAFAAagwAAAMAUQBsDAAAAgBQAG0MAAABADQA6gwAAAQAWwAJAAEJUREP+gA/AAFuDAAAAQAsAAAA.',
Ug='Uggalee:BAAALgAECgYJCAAAAA==.',
Va='Valtirya:BAAALgAECgQJBgAAAA==.Vayzen:BAABLgAECn8YAAIgAAcJDB4rEwBNAgdoDAAABABXAGkMAAADAFIAawwAAAQASwBqDAAABABXAGwMAAAEAFQAbQwAAAIAMQDqDAAAAwBSACAABwkMHisTAE0CB2gMAAAEAFcAaQwAAAMAUgBrDAAABABLAGoMAAAEAFcAbAwAAAQAVABtDAAAAgAxAOoMAAADAFIAAAA=.',
Vi='Virexus:BAAALgADCgIJAgAAAA==.',
Vo='Voidfree:BAABLgAECn8ZAAIMAAYJSwmkZwDWAAZoDAAABQAlAGkMAAAFAB0AawwAAAUAFABqDAAAAwAgAGwMAAACAA8A6gwAAAUADwAMAAYJSwmkZwDWAAZoDAAABQAlAGkMAAAFAB0AawwAAAUAFABqDAAAAwAgAGwMAAACAA8A6gwAAAUADwAAAA==.',
Vy='Vynarc:BAABLgAECn8oAAIJAAgJiRE7QQCMAQhoDAAABgA3AGkMAAAFAC0AawwAAAUAQQBqDAAABgAyAGwMAAAFADIAbQwAAAMAIADqDAAABgArAG4MAAAEABUACQAICYkRO0EAjAEIaAwAAAYANwBpDAAABQAtAGsMAAAFAEEAagwAAAYAMgBsDAAABQAyAG0MAAADACAA6gwAAAYAKwBuDAAABAAVAAAA.',
Wa='Warcrimes:BAAALgAECgEJAQAAAA==.Watervendor:BAABLgAECn8jAAIFAAgJXhqDIwAhAghoDAAABgBSAGkMAAAGAD8AawwAAAUASQBqDAAABAA6AGwMAAAEAFIAbQwAAAIAOADqDAAABgBUAG4MAAACAB4ABQAICV4agyMAIQIIaAwAAAYAUgBpDAAABgA/AGsMAAAFAEkAagwAAAQAOgBsDAAABABSAG0MAAACADgA6gwAAAYAVABuDAAAAgAeAAAA.',
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

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end
