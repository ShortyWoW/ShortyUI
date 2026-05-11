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

local lookup = {'Unknown-Unknown','Priest-Shadow','Priest-Discipline','Paladin-Retribution','Druid-Restoration','Druid-Balance','Mage-Frost','DeathKnight-Unholy','DemonHunter-Devourer','Warlock-Affliction','Warrior-Fury','Priest-Holy','Hunter-Marksmanship','Mage-Arcane','Paladin-Protection','Monk-Mistweaver','Evoker-Preservation','Evoker-Augmentation','Monk-Windwalker','Monk-Brewmaster','Druid-Guardian',}
local provider = {region='US',realm='BlackwingLair',name='US',type='daily',zone=46,date='2026-05-10',data={Am='Amar:BAAALgADCgUJCQAAAA==.',
Ar='Aranii:BAAALgAECgEJAQAAAA==.',
As='Assaultdeez:BAAALgAECgYJDwABLgAECgcJBwABAAAAAA==.',
Ba='Baku:BAAALgAECgYJCgAAAA==.Balial:BAAALgAFFAIJAwAAAA==.Battlerez:BAABLgAECn8ZAAMCAAYJ6R1iEgDBAQZoDAAABQBQAGkMAAAFAEwAawwAAAUAVABqDAAAAgBKAGwMAAABADgA6gwAAAcAVQACAAYJ6R1iEgDBAQZoDAAABQBQAGkMAAAFAEwAawwAAAUAVABqDAAAAgBKAGwMAAABADgA6gwAAAUAVQADAAEJeQkDWAAyAAHqDAAAAgAYAAAA.',
Be='Bearfiend:BAAALgADCgcJBwAAAA==.',
Bj='Bj:BAAALgAECgEJAQABLgAFFAIJAgABAAAAAA==.',
Bl='Blackthorne:BAAALgADCgcJCgAAAA==.Blightbark:BAAALgADCgUJBQAAAA==.Blopi:BAAALgAECgEJAQAAAA==.',
Bu='Bubblegyatt:BAABLgAECn8ZAAIEAAYJlRx3cACbAQZoDAAABQBBAGkMAAAGAE0AawwAAAQAUABqDAAABAAyAGwMAAAEAFMA6gwAAAIAOgAEAAYJlRx3cACbAQZoDAAABQBBAGkMAAAGAE0AawwAAAQAUABqDAAABAAyAGwMAAAEAFMA6gwAAAIAOgABLgAECggJHgAEAAYeAA==.',
Ca='Calcio:BAAALgAECgYJEAAAAA==.',
Co='Conversed:BAAALgAECgYJCgAAAA==.Convy:BAABLgAECn8UAAMFAAkJChFqPACyAQloDAAAAwAzAGkMAAADACYAawwAAAMAGgBqDAAAAgAWAGwMAAADAD0AbQwAAAEAJwDqDAAAAwA9AG4MAAABACUAbwwAAAEANAAFAAkJChFqPACyAQloDAAAAwAzAGkMAAACACYAawwAAAMAGgBqDAAAAgAWAGwMAAADAD0AbQwAAAEAJwDqDAAAAwA9AG4MAAABACUAbwwAAAEANAAGAAEJFwQNiQAmAAFpDAAAAQAKAAAA.Coreander:BAABLgAECn8UAAIHAAgJ3gjhVwBtAQhoDAAABAAYAGkMAAAEAB4AawwAAAUAIwBqDAAAAgAbAGwMAAACABsAbQwAAAEADADqDAAAAQAQAG4MAAABAAwABwAICd4I4VcAbQEIaAwAAAQAGABpDAAABAAeAGsMAAAFACMAagwAAAIAGwBsDAAAAgAbAG0MAAABAAwA6gwAAAEAEABuDAAAAQAMAAAA.',
Cr='Crunchboi:BAAALgAECgQJCgAAAA==.',
Da='Dab:BAABLgAECn8fAAIDAAgJuRHzEgC8AQhoDAAABQA3AGkMAAAFADsAawwAAAUAMwBqDAAABQAsAGwMAAADADUAbQwAAAEAGwDqDAAABgA8AG4MAAABAAoAAwAICbkR8xIAvAEIaAwAAAUANwBpDAAABQA7AGsMAAAFADMAagwAAAUALABsDAAAAwA1AG0MAAABABsA6gwAAAYAPABuDAAAAQAKAAAA.Daberina:BAAALgADCgIJAgAAAA==.Darklider:BAAALgAECgMJAwAAAA==.',
Dc='Dcmaster:BAAALgAECgEJAgAAAA==.',
De='Deabbzy:BAABLgAECn8XAAIIAAcJJxAwTABiAQdoDAAABAA3AGkMAAAEADAAawwAAAQAOABqDAAABAA6AGwMAAADABoAbQwAAAEAEQDqDAAAAwAsAAgABwknEDBMAGIBB2gMAAAEADcAaQwAAAQAMABrDAAABAA4AGoMAAAEADoAbAwAAAMAGgBtDAAAAQARAOoMAAADACwAAAA=.Dedal:BAAALgAECgYJDwAAAA==.',
Du='Dumbchicken:BAAALgADCgcJBwABLgAECgkJEwAJAMMcAA==.Durto:BAAALgADCgcJBwABLgAECgQJBwABAAAAAA==.',
Dz='Dzk:BAAALgAECgEJAQAAAA==.',
El='Eldthweone:BAABLgAECn8pAAIKAAgJgx3HAQBEAghoDAAABwBVAGkMAAAGAFAAawwAAAYAWwBqDAAABwBgAGwMAAAFAEcAbQwAAAMAMQDqDAAABgBJAG4MAAABAEsACgAICYMdxwEARAIIaAwAAAcAVQBpDAAABgBQAGsMAAAGAFsAagwAAAcAYABsDAAABQBHAG0MAAADADEA6gwAAAYASQBuDAAAAQBLAAAA.',
Eu='Eurykrates:BAAALgADCgYJBgAAAA==.',
Fl='Flämmå:BAAALgADCgIJAgAAAA==.',
Gi='Gingergnar:BAABLgAECn8XAAILAAcJbxwyEgDlAQdoDAAABABRAGkMAAAEAFsAawwAAAQARwBqDAAABABPAGwMAAADAEIAbQwAAAEAPQDqDAAAAwBAAAsABwlvHDISAOUBB2gMAAAEAFEAaQwAAAQAWwBrDAAABABHAGoMAAAEAE8AbAwAAAMAQgBtDAAAAQA9AOoMAAADAEAAAS4AAwoGCQYAAQAAAAA=.',
Gr='Greyguard:BAAALgAECgQJBAAAAA==.',
Gs='Gsnairb:BAAALgAECgUJCAAAAA==.',
Gu='Guillemønk:BAAALgADCgYJCQAAAA==.',
He='Healobot:BAABLgAECn8VAAIMAAcJOB0UDAAtAgdoDAAABABKAGkMAAAEAFMAawwAAAQATABqDAAAAgBSAGwMAAABADQAbQwAAAEASgDqDAAABQBPAAwABwk4HRQMAC0CB2gMAAAEAEoAaQwAAAQAUwBrDAAABABMAGoMAAACAFIAbAwAAAEANABtDAAAAQBKAOoMAAAFAE8AAAA=.',
Hu='Huldra:BAAALgADCgEJAQAAAA==.',
Hy='Hylax:BAACLgAFFH8JAAINAAMJRSWgCAA/AQNoDAAABABhAGkMAAADAGMA6gwAAAIAWQANAAMJRSWgCAA/AQNoDAAABABhAGkMAAADAGMA6gwAAAIAWQAuAAQKfywAAg0ACAkmJtoAAPgCAA0ACAkmJtoAAPgCAAAA.Hypnotroll:BAAALgAECgIJBQAAAA==.',
Ih='Ihuntwabbits:BAAALgADCgEJAQABLgAECgcJBwABAAAAAA==.',
In='Inesita:BAAALgAECgIJBAAAAA==.Innelli:BAABLgAECn8YAAMOAAYJkg2RBQAiAQZoDAAABQAqAGkMAAAFACMAawwAAAUAGQBqDAAAAwAyAGwMAAACABYA6gwAAAQAMAAOAAYJPQ2RBQAiAQZoDAAAAwAqAGkMAAADACIAawwAAAMAGQBqDAAAAQAKAGwMAAABABIA6gwAAAIAMAAHAAYJUwtXfgAcAQZoDAAAAgAjAGkMAAACACMAawwAAAIAFABqDAAAAgAyAGwMAAABABYA6gwAAAIAHwAAAA==.',
Ir='Irworeeyore:BAAALgADCgUJBQAAAA==.Irworeloch:BAAALgADCgcJBwAAAA==.',
Ja='Jasaris:BAABLgAECn8XAAIPAAcJtyXJAgCLAgdoDAAABABgAGkMAAAEAGMAawwAAAQAYwBqDAAABABgAGwMAAADAF4AbQwAAAEAXQDqDAAAAwBgAA8ABwm3JckCAIsCB2gMAAAEAGAAaQwAAAQAYwBrDAAABABjAGoMAAAEAGAAbAwAAAMAXgBtDAAAAQBdAOoMAAADAGAAAAA=.',
Jo='Jonnathan:BAABLgAECn8hAAILAAkJCA9YNADZAQloDAAABwA/AGkMAAAHADAAawwAAAUAMgBqDAAAAgARAGwMAAADACgAbQwAAAEACQDqDAAABgAwAG4MAAABABcAbwwAAAEAGAALAAkJCA9YNADZAQloDAAABwA/AGkMAAAHADAAawwAAAUAMgBqDAAAAgARAGwMAAADACgAbQwAAAEACQDqDAAABgAwAG4MAAABABcAbwwAAAEAGAAAAA==.',
Ju='Juzumaki:BAAALgADCgQJBAAAAA==.',
Ka='Kaltralak:BAAALgAECgMJCAABLgAECggJFwAHAMgVAA==.',
Kh='Khalorn:BAAALgAECggJCAAAAA==.',
Ki='Killidén:BAAALgAECgQJBQAAAA==.Kiralas:BAAALgAECgMJAwABLgAECgkJGgACAIYUAA==.',
Kr='Krahzkal:BAAALgADCgYJBgAAAA==.',
Li='Lilithiia:BAAALgAECgcJDAAAAA==.Lirakas:BAABLgAECn8aAAMCAAkJhhRlHQBdAQloDAAABABQAGkMAAAEAC0AawwAAAQAPABqDAAABABLAGwMAAAEADsAbQwAAAEAJADqDAAAAwA9AG4MAAABACAAbwwAAAEAKgACAAkJhhRlHQBdAQloDAAABABQAGkMAAADAC0AawwAAAQAPABqDAAAAQBLAGwMAAADADsAbQwAAAEAJADqDAAAAwA9AG4MAAABACAAbwwAAAEAKgADAAMJkhSTPgC5AANpDAAAAQAhAGoMAAADADMAbAwAAAEASAAAAA==.',
Lo='Lonoa:BAAALgADCgEJAQAAAA==.',
Ma='Mackks:BAAALgAECggJCgAAAA==.Maell:BAAALgAECgQJBAAAAA==.Mariah:BAAALgAECgUJCAAAAA==.Maysie:BAAALgADCgIJAwAAAA==.',
Mc='Mcnugget:BAAALgAECgIJBAABLgAECggJIgAQAAIhAA==.',
Me='Mercury:BAAALgAECgUJEAAAAA==.',
Mi='Milch:BAABLgAECn8WAAIHAAYJCwxGfwAaAQZoDAAABAAlAGkMAAAFAB0AawwAAAQAIQBqDAAAAwAUAGwMAAADACIA6gwAAAMAEwAHAAYJCwxGfwAaAQZoDAAABAAlAGkMAAAFAB0AawwAAAQAIQBqDAAAAwAUAGwMAAADACIA6gwAAAMAEwAAAA==.Minipriest:BAAALgAFFAQJBAABLgAFFAYJEwARAJQPAQ==.Minivoker:BAACLgAFFH8TAAIRAAYJlA8OCAClAQZoDAAABAA0AGkMAAAEAEgAawwAAAMACQBqDAAAAwAVAGwMAAABABsA6gwAAAQANwARAAYJlA8OCAClAQZoDAAABAA0AGkMAAAEAEgAawwAAAMACQBqDAAAAwAVAGwMAAABABsA6gwAAAQANwAuAAQKfzgAAxEACQlwIMcCAMUCABEACAmOIMcCAMUCABIABQnXGtoWAJYBAAAA.',
Mo='Moop:BAAALgAECgYJAQAAAA==.',
Ni='Nilsine:BAAALgADCgcJBwAAAA==.',
On='Onyx:BAAALgAECgcJEAAAAA==.',
Op='Oppa:BAAALgAECgEJAQABLgAFFAIJAwABAAAAAA==.',
Pa='Pailiah:BAAALgAECgQJCgABLgAECgYJCgABAAAAAA==.',
Pi='Pinkchicken:BAAALgADCgkJCwABLgAECgkJEwAJAMMcAA==.',
Po='Potadpole:BAAALgAECgYJBgABLgAFFAMJBwASAJMVAA==.',
Pu='Purplenerple:BAAALgAECgcJBwAAAA==.',
Qa='Qamar:BAAALgAFFAEJAQAAAA==.',
Re='Reloth:BAAALgAECgUJCAAAAA==.',
Ro='Rosealee:BAAALgAECgEJAQAAAA==.',
Ru='Rune:BAAALgAECggJDwAAAA==.',
Sa='Sauriel:BAAALgAECgEJAQABLgAFFAIJAwABAAAAAA==.',
Se='Sellz:BAAALgAECgEJAQAAAA==.Serf:BAABLgAECn8lAAIGAAkJvRu1DgCzAgloDAAABwBZAGkMAAAGAFIAawwAAAYATwBqDAAABABUAGwMAAAEAFgAbQwAAAEAQADqDAAABQBcAG4MAAADADwAbwwAAAEACgAGAAkJvRu1DgCzAgloDAAABwBZAGkMAAAGAFIAawwAAAYATwBqDAAABABUAGwMAAAEAFgAbQwAAAEAQADqDAAABQBcAG4MAAADADwAbwwAAAEACgAAAA==.Setra:BAAALgAECgYJDQAAAA==.Settio:BAAALgAECgcJEgAAAA==.',
Sh='Shaboom:BAAALgADCgIJAgABLgAECggJHgAEAAYeAA==.Shruggon:BAAALgADCgEJAQAAAA==.',
Sl='Slev:BAABLgAECn8iAAQQAAYJAiF1FAAlAgZoDAAAAwBFAGkMAAAGAFsAawwAAAIAQQBqDAAACQBaAGwMAAAFAGMA6gwAAAkAWwAQAAYJAiF1FAAlAgZoDAAAAwBFAGkMAAAFAFsAawwAAAIAQQBqDAAACABaAGwMAAAEAGMA6gwAAAkAWwATAAIJ1QkpYgAyAAJpDAAAAQAaAGwMAAABABcAFAABCQAAfH8AAAABagwAAAEAOQAAAA==.Slevatelli:BAAALgAECgIJAgABLgAECggJIgAQAAIhAA==.',
Sm='Smecky:BAAALgAECgEJAQAAAA==.',
So='Songoku:BAAALgAECgYJDgAAAA==.',
St='Sterey:BAAALgADCgcJCQAAAA==.Styles:BAAALgAECgcJDQABLgAECggJHgAEAAYeAA==.',
Sw='Switchout:BAAALgADCgYJBgAAAA==.',
Te='Tehkromlech:BAAALgAECgcJDQAAAA==.Tetankeo:BAABLgAECn8WAAIVAAgJkxxMBwDaAQhoDAAABQBTAGkMAAAEAFAAawwAAAMAQgBqDAAAAgBHAGwMAAACAE4AbQwAAAEAOADqDAAABABXAG4MAAABADoAFQAICZMcTAcA2gEIaAwAAAUAUwBpDAAABABQAGsMAAADAEIAagwAAAIARwBsDAAAAgBOAG0MAAABADgA6gwAAAQAVwBuDAAAAQA6AAAA.',
Tk='Tk:BAAALgADCgcJBQAAAA==.Tkdragon:BAAALgAFFAEJAQAAAA==.',
To='Tobolaeh:BAAALgAECgYJEwABLgAECgcJFQAMADgdAA==.',
Tu='Turbomoose:BAAALgADCgYJBgAAAA==.',
Ul='Ulthrax:BAAALgAECgEJAQAAAA==.',
Va='Vaedalth:BAAALgADCgQJBAABLgAECgkJGgAEANsVAA==.',
Ve='Veil:BAAALgAECgQJBAABLgAECgYJCgABAAAAAA==.',
Wa='Warfrenzy:BAAALgADCgQJBAAAAA==.',
Xa='Xaletara:BAAALgADCgcJBwAAAA==.',
Xb='Xbite:BAAALgAECgMJAwAAAA==.',
Xe='Xennion:BAAALgADCgIJAgAAAA==.',
Xf='Xfallenhealz:BAAALgAECgIJAgAAAA==.Xfallenlight:BAAALgADCgcJCwAAAA==.',
Yi='Yiirn:BAAALgAECgUJDgAAAA==.',
Ze='Zel:BAAALgAECggJEwAAAA==.',
['Ðr']='Ðred:BAAALgADCggJCAAAAA==.',
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
