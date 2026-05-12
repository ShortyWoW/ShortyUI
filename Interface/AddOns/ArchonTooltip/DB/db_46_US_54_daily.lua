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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Shaman-Elemental','Mage-Frost','Paladin-Holy','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Paladin-Protection','Warlock-Demonology','Paladin-Retribution','DeathKnight-Unholy','DeathKnight-Frost','Druid-Feral','Hunter-Survival','Rogue-Assassination','Monk-Windwalker','Warlock-Affliction','Warlock-Destruction','DemonHunter-Havoc','Priest-Holy','Priest-Shadow','Priest-Discipline','DeathKnight-Blood','Hunter-BeastMastery','Druid-Guardian','DemonHunter-Devourer','Warrior-Arms','Warrior-Fury','Hunter-Marksmanship','Rogue-Outlaw','Rogue-Subtlety','Druid-Restoration','Warrior-Protection','Monk-Brewmaster',}
local provider = {region='US',realm='Coilfang',name='US',type='daily',zone=46,date='2026-05-12',data={Ae='Aendean:BAAALgAECgEJAQAAAA==.',
Am='Amethyne:BAAALgADCgMJAwAAAA==.',
An='Anabell:BAAALgAECgEJAQABLgAECgYJCAABAAAAAA==.',
Ar='Arckane:BAAALgAECgEJAQAAAA==.Arcueid:BAABLgAECn8oAAMCAAkJqSDhEwAwAgloDAAABQBQAGkMAAAFAFMAawwAAAcAWABqDAAABQBVAGwMAAAFAEkAbQwAAAIAOwDqDAAACABZAG4MAAACAFwAbwwAAAEAYwACAAgJ5B/hEwAwAghoDAAABQBQAGkMAAAFAFMAawwAAAcAWABqDAAABQBVAGwMAAAFAEkAbQwAAAIAOwDqDAAACABZAG4MAAACAFwAAwABCZ4RymIARwABbwwAAAEALQAAAA==.',
As='Asmadeus:BAAALgAECgEJAQAAAA==.',
Ay='Ayda:BAABLgAECn8zAAIEAAkJDyPMBQAmAwloDAAABwBhAGkMAAAHAFwAawwAAAcAYQBqDAAABgBOAGwMAAAGAF8AbQwAAAUAWQDqDAAABwBfAG4MAAAEAE0AbwwAAAIASAAEAAkJDyPMBQAmAwloDAAABwBhAGkMAAAHAFwAawwAAAcAYQBqDAAABgBOAGwMAAAGAF8AbQwAAAUAWQDqDAAABwBfAG4MAAAEAE0AbwwAAAIASAAAAA==.',
Ba='Bartholdson:BAAALgAECgYJEgAAAA==.',
Be='Bearlydidit:BAAALgADCgQJBAAAAA==.Beloc:BAAALgAECggJAgAAAA==.Berzerkirz:BAAALgADCgYJBgAAAA==.',
Bl='Blacksnow:BAAALgADCgEJAQAAAA==.Blcksnowcrow:BAABLgAECn8dAAIFAAkJ8BmMCwBuAgloDAAABQBNAGkMAAAEAFkAawwAAAQAXABqDAAAAgAgAGwMAAADAFAAbQwAAAMAQwDqDAAABgBGAG4MAAABACkAbwwAAAEALwAFAAkJ8BmMCwBuAgloDAAABQBNAGkMAAAEAFkAawwAAAQAXABqDAAAAgAgAGwMAAADAFAAbQwAAAMAQwDqDAAABgBGAG4MAAABACkAbwwAAAEALwAAAA==.',
Bo='Bonfire:BAABLgAECn8kAAQGAAgJASNLBwB1AghoDAAABgBfAGkMAAAGAF8AawwAAAYAXQBqDAAABQBjAGwMAAAEAFUAbQwAAAIAUgDqDAAABgBdAG4MAAABAFEABgAICQEjSwcAdQIIaAwAAAQAXwBpDAAABABfAGsMAAAFAF0AagwAAAQAYwBsDAAAAwBVAG0MAAACAFIA6gwAAAUAXQBuDAAAAQBRAAcABQncIPEOALAABWgMAAACAF0AaQwAAAEATABqDAAAAQBfAGwMAAABAEoA6gwAAAEAWwAIAAIJSgKGRABLAAJpDAAAAQAHAGsMAAABAAQAAS4ABRQECQQAAQAAAAA=.Boochili:BAABLgAECn8vAAIJAAkJiiYQAACIAwloDAAABgBjAGkMAAAGAGMAawwAAAYAYwBqDAAABgBjAGwMAAAGAGMAbQwAAAUAYwDqDAAABgBiAG4MAAAEAGMAbwwAAAIAXAAJAAkJiiYQAACIAwloDAAABgBjAGkMAAAGAGMAawwAAAYAYwBqDAAABgBjAGwMAAAGAGMAbQwAAAUAYwDqDAAABgBiAG4MAAAEAGMAbwwAAAIAXAAAAA==.',
Br='Braveling:BAABLgAECn8YAAIKAAgJOQycPwB6AQhoDAAABAAZAGkMAAAEACwAawwAAAQAGQBqDAAAAwAvAGwMAAADAC0AbQwAAAEAIADqDAAABAAaAG4MAAABABMACgAICTkMnD8AegEIaAwAAAQAGQBpDAAABAAsAGsMAAAEABkAagwAAAMALwBsDAAAAwAtAG0MAAABACAA6gwAAAQAGgBuDAAAAQATAAAA.',
Bu='Bubblës:BAAALgAECgQJCAABLgAECggJHwAEAAgiAA==.',
Ca='Carezarsh:BAAALgADCgMJAQAAAA==.',
Ch='Charlie:BAACLgAFFH8SAAMLAAQJxyOZCwCNAQRoDAAABQBdAGkMAAAEAFoAawwAAAQAXwDqDAAABQBWAAsABAnHI5kLAI0BBGgMAAAFAF0AaQwAAAQAWgBrDAAAAwBfAOoMAAAFAFYACQABCUAjjAoAZgABawwAAAEAWgAuAAQKfzAAAwsACQm5JUAGAP4CAAsACQm5JUAGAP4CAAkAAwlgGKcrAFwAAAAA.Chicken:BAAALgAFFAEJAQAAAA==.',
Cr='Cruel:BAAALgADCgEJAQAAAA==.',
['Cä']='Cätîáñdrïà:BAABLgAECn9LAAMCAAkJzR3jCQCkAgloDAAACgBCAGkMAAAJAEsAawwAAAkAWgBqDAAACgA/AGwMAAAJAEoAbQwAAAcAUgDqDAAADABaAG4MAAAGADoAbwwAAAMAUwACAAkJzR3jCQCkAgloDAAACQBCAGkMAAAHAEsAawwAAAcAWgBqDAAACAA/AGwMAAAIAEoAbQwAAAcAUgDqDAAADABaAG4MAAAGADoAbwwAAAMAUwADAAUJaA47OgDXAAVoDAAAAQAyAGkMAAACAB4AawwAAAIALwBqDAAAAgAzAGwMAAABABMAAAA=.',
Da='Daniedk:BAABLgAECn8jAAIMAAgJDhNmPwCUAQhoDAAABQBDAGkMAAAGAC4AawwAAAUAHQBqDAAABgBAAGwMAAAEACsAbQwAAAIAFQDqDAAABABDAG4MAAADAEEADAAICQ4TZj8AlAEIaAwAAAUAQwBpDAAABgAuAGsMAAAFAB0AagwAAAYAQABsDAAABAArAG0MAAACABUA6gwAAAQAQwBuDAAAAwBBAAAA.Daphanim:BAAALgADCgYJCgAAAA==.Darctotem:BAAALgAECgUJCwAAAA==.',
De='Deathtouch:BAACLgAFFH8HAAMMAAMJPhxUWQDvAANoDAAAAgBTAGkMAAADADcA6gwAAAIATQAMAAMJPhxUWQDvAANoDAAAAQBTAGkMAAACADcA6gwAAAIATQANAAIJSRDzCACfAAJoDAAAAQAnAGkMAAABACsALgAECn8bAAMMAAgJRyNVEwB5AgAMAAgJxyJVEwB5AgANAAEJEh35FgBQAAAAAA==.Devona:BAABLgAECn8dAAMFAAgJ5Rs1GQDUAQhoDAAABgBBAGkMAAAFAFAAawwAAAUATQBqDAAAAwBNAGwMAAADAF8AbQwAAAEAHQDqDAAABQBYAG4MAAABADgABQAHCbQcNRkA1AEHaAwAAAQAQQBpDAAABABQAGsMAAAEAE0AagwAAAIATQBsDAAAAgBfAG0MAAABAB0A6gwAAAQAWAALAAcJmwxBXABNAQdoDAAAAgAkAGkMAAABAC4AawwAAAEAGABqDAAAAQAbAGwMAAABACgA6gwAAAEAGgBuDAAAAQATAAAA.',
Di='Didit:BAAALgADCgcJBwAAAA==.Dingledangle:BAABLgAECn8VAAIOAAcJBBKUDQBYAQdoDAAABAA4AGkMAAAEADwAawwAAAQANABqDAAABAA5AGwMAAABAAkAbQwAAAEAIwDqDAAAAwA+AA4ABwkEEpQNAFgBB2gMAAAEADgAaQwAAAQAPABrDAAABAA0AGoMAAAEADkAbAwAAAEACQBtDAAAAQAjAOoMAAADAD4AAAA=.',
Dj='Djindor:BAAALgADCgUJBQAAAA==.',
Dr='Draconix:BAAALgAECgQJBAABLgAECgYJBgABAAAAAA==.Dragonzordd:BAAALgADCgQJBQABLgAECgYJFAAPAAwiAA==.Dragooncrush:BAAALgADCgQJBAAAAA==.Dragoonnick:BAABLgAECn81AAIQAAkJwhsWBAB0AgloDAAACABaAGkMAAAJAE0AawwAAAkAVABqDAAABgBBAGwMAAAGAEgAbQwAAAIAKQDqDAAACQBIAG4MAAADAFIAbwwAAAEALgAQAAkJwhsWBAB0AgloDAAACABaAGkMAAAJAE0AawwAAAkAVABqDAAABgBBAGwMAAAGAEgAbQwAAAIAKQDqDAAACQBIAG4MAAADAFIAbwwAAAEALgAAAA==.Drazzy:BAAALgAECgIJAgAAAA==.',
Es='Esh:BAAALgAECgcJDgAAAA==.',
Eu='Euphal:BAABLgAECn8mAAIKAAgJ2xLkNACfAQhoDAAABAA1AGkMAAAGAC0AawwAAAUAIQBqDAAAAwA1AGwMAAAHAEAAbQwAAAIAFwDqDAAABwBDAG4MAAAEADIACgAICdsS5DQAnwEIaAwAAAQANQBpDAAABgAtAGsMAAAFACEAagwAAAMANQBsDAAABwBAAG0MAAACABcA6gwAAAcAQwBuDAAABAAyAAAA.',
Ey='Eyekicku:BAABLgAECn8cAAIRAAgJdSAABgCKAghoDAAABgBcAGkMAAAFAFoAawwAAAUAWQBqDAAAAwBaAGwMAAADAE4AbQwAAAEAQADqDAAABABUAG4MAAABAFEAEQAICXUgAAYAigIIaAwAAAYAXABpDAAABQBaAGsMAAAFAFkAagwAAAMAWgBsDAAAAwBOAG0MAAABAEAA6gwAAAQAVABuDAAAAQBRAAAA.',
Fe='Feldana:BAAALgAECgQJBAAAAA==.Fenicon:BAAALgAECgQJBQAAAA==.',
Fi='Fitz:BAAALgAECgQJBAAAAA==.Fitzwell:BAAALgAECgQJBAAAAA==.',
Fu='Fuyu:BAAALgAECgQJBAAAAA==.Fuyuhex:BAAALgAFFAIJAQAAAA==.',
Gh='Ghost:BAAALgAECgMJBQAAAA==.',
Gr='Graycieden:BAAALgAECgYJBwAAAA==.',
Gu='Guldangit:BAACLgAFFH8dAAMKAAcJGhy2AQAmAgdoDAAABgBcAGkMAAAEAFsAawwAAAUAUgBqDAAABABLAGwMAAADADkAbQwAAAEAIgDqDAAABgBIAAoABwkaHLYBACYCB2gMAAAGAFwAaQwAAAQAWwBrDAAABQBSAGoMAAADAEQAbAwAAAMAOQBtDAAAAQAiAOoMAAAGAEgAEgABCQAAPwMAYAABagwAAAEASwAuAAQKfykAAwoACQnCI2oIAD4DAAoACQkBI2oIAD4DABMABAmOIi4aAHsBAAAA.',
Ha='Hanora:BAAALgAECgEJAQAAAA==.',
He='Hellspawn:BAABLgAECn8zAAIUAAkJxg6oDQC+AQloDAAABwA+AGkMAAAHADMAawwAAAcALABqDAAABgAbAGwMAAAGACIAbQwAAAUAGADqDAAABwAfAG4MAAAEABwAbwwAAAIAGQAUAAkJxg6oDQC+AQloDAAABwA+AGkMAAAHADMAawwAAAcALABqDAAABgAbAGwMAAAGACIAbQwAAAUAGADqDAAABwAfAG4MAAAEABwAbwwAAAIAGQAAAA==.',
Hh='Hhounow:BAAALgADCgYJBgAAAA==.',
Ho='Hojai:BAAALgADCgMJAwAAAA==.Holybeef:BAAALgAECgcJDQAAAA==.Holygrim:BAACLgAFFH8aAAIVAAcJ5yMaAABvAgdoDAAABQBkAGkMAAAFAGEAawwAAAQAYgBqDAAAAwBeAGwMAAACAFEAbQwAAAEAVgDqDAAABgBVABUABwnnIxoAAG8CB2gMAAAFAGQAaQwAAAUAYQBrDAAABABiAGoMAAADAF4AbAwAAAIAUQBtDAAAAQBWAOoMAAAGAFUALgAECn8dAAMVAAgJYybgAQBXAwAVAAgJYybgAQBXAwAWAAEJPgnqWgAzAAAAAA==.Holyloa:BAAALgAECgMJAwAAAA==.Holypablo:BAABLgAECn8zAAQXAAkJER+pAgAvAwloDAAABwBJAGkMAAAHAFoAawwAAAcAXgBqDAAABgBfAGwMAAAGAGEAbQwAAAUAUADqDAAABwA6AG4MAAAEAEIAbwwAAAIAOwAXAAkJER+pAgAvAwloDAAABABJAGkMAAAEAFoAawwAAAQAXgBqDAAABgBfAGwMAAAGAGEAbQwAAAUAUADqDAAABQA6AG4MAAAEAEIAbwwAAAIAOwAWAAQJaRRhNADVAARoDAAAAgA1AGkMAAACAEIAawwAAAIAPQDqDAAAAQAbABUABAmtC5VdALwABGgMAAABAA4AaQwAAAEAGABrDAAAAQAxAOoMAAABAB8AAAA=.Howii:BAABLgAECn81AAIYAAkJvSSvAABMAwloDAAACABbAGkMAAAHAGIAawwAAAcAYABqDAAABgBfAGwMAAAGAGEAbQwAAAUAWgDqDAAACABfAG4MAAAEAFcAbwwAAAIAXwAYAAkJvSSvAABMAwloDAAACABbAGkMAAAHAGIAawwAAAcAYABqDAAABgBfAGwMAAAGAGEAbQwAAAUAWgDqDAAACABfAG4MAAAEAFcAbwwAAAIAXwAAAA==.',
Im='Imperator:BAAALgAECgQJBAAAAA==.',
In='Inchworm:BAAALgAECgYJBgAAAA==.',
Is='Isabellaah:BAABLgAECn8bAAIZAAcJ9xJdPQBuAQdoDAAABgA6AGkMAAAFAEYAawwAAAUAMABqDAAAAwAgAGwMAAADADwAbQwAAAEACQDqDAAABAAsABkABwn3El09AG4BB2gMAAAGADoAaQwAAAUARgBrDAAABQAwAGoMAAADACAAbAwAAAMAPABtDAAAAQAJAOoMAAAEACwAAAA=.',
Je='Jellyfïsh:BAAALgAECgUJCgAAAA==.Jeraziah:BAAALgAECgUJEQABLgAECgkJKAACAKkgAA==.',
Jo='Johnnyjr:BAAALgAECgkJEgAAAA==.',
Ke='Kelliz:BAAALgADCgcJCAAAAA==.',
Kh='Khaladin:BAAALgAECgYJEgAAAA==.',
La='Laggers:BAABLgAECn8jAAIaAAgJdxZFDAB1AQhoDAAABgA3AGkMAAAGAE4AawwAAAYARgBqDAAABQAwAGwMAAADADMAbQwAAAEAGgDqDAAABwBKAG4MAAABAC0AGgAICXcWRQwAdQEIaAwAAAYANwBpDAAABgBOAGsMAAAGAEYAagwAAAUAMABsDAAAAwAzAG0MAAABABoA6gwAAAcASgBuDAAAAQAtAAAA.',
Li='Litbit:BAABLgAECn8XAAIEAAcJ5wMCmAD4AAdoDAAABAALAGkMAAAEABAAawwAAAQABgBqDAAABAAGAGwMAAADAA4AbQwAAAEABgDqDAAAAwAEAAQABwnnAwKYAPgAB2gMAAAEAAsAaQwAAAQAEABrDAAABAAGAGoMAAAEAAYAbAwAAAMADgBtDAAAAQAGAOoMAAADAAQAAAA=.Litbitonme:BAAALgAECgMJAwAAAA==.Litt:BAAALgADCgkJCwAAAA==.Lizardwizard:BAAALgAECgEJAQAAAA==.',
Lo='Lockmantwo:BAAALgAECgcJAwAAAA==.Lostmoo:BAAALgAECgEJAQAAAA==.Lostunholy:BAABLgAECn8XAAIMAAcJhCAeJwD5AQdoDAAABwBhAGkMAAAEAFIAawwAAAMAVwBqDAAAAgBaAGwMAAACAFMAbQwAAAEAOQDqDAAABABaAAwABwmEIB4nAPkBB2gMAAAHAGEAaQwAAAQAUgBrDAAAAwBXAGoMAAACAFoAbAwAAAIAUwBtDAAAAQA5AOoMAAAEAFoAAAA=.Lovebug:BAAALgADCgcJBwAAAA==.',
Lu='Lunaardris:BAAALgAECgQJBQAAAA==.',
Ly='Lynxe:BAAALgAECgYJBgAAAA==.',
Ma='Maggikal:BAABLgAECn8XAAIEAAYJtQyriQASAQZoDAAABQA3AGkMAAAEABgAawwAAAQAIwBqDAAAAgAWAGwMAAACAAoA6gwAAAYAJAAEAAYJtQyriQASAQZoDAAABQA3AGkMAAAEABgAawwAAAQAIwBqDAAAAgAWAGwMAAACAAoA6gwAAAYAJAAAAA==.',
Me='Megahottie:BAAALgADCgYJBgAAAA==.',
Mi='Mirant:BAAALgAECgUJDQAAAA==.',
Mo='Moretisha:BAAALgADCgYJBgAAAA==.',
Na='Nakwoo:BAAALgADCgMJAwAAAA==.',
On='One:BAAALgAECgEJAQAAAA==.',
Op='Opallea:BAABLgAECn8YAAMUAAgJphugEQBRAghoDAAABABPAGkMAAAFAE4AawwAAAUASwBqDAAAAwBOAGwMAAACAEgAbQwAAAEARADqDAAAAwBKAG4MAAABAC4AFAAICaYboBEAUQIIaAwAAAMATwBpDAAABABOAGsMAAAEAEsAagwAAAIATgBsDAAAAgBIAG0MAAABAEQA6gwAAAMASgBuDAAAAQAuABsABAnqBGidAGsABGgMAAABAAoAaQwAAAEAEgBrDAAAAQAJAGoMAAABAB4AAAA=.',
Pa='Pallyplay:BAAALgAECgEJAQAAAA==.',
Pb='Pballs:BAAALgADCgEJAQABLgAECgkJMwAXABEfAA==.',
Pe='Periodic:BAACLgAFFH8KAAICAAQJriHuCgCOAQRoDAAABABaAGkMAAACAGAAawwAAAEAQgDqDAAAAwBbAAIABAmuIe4KAI4BBGgMAAAEAFoAaQwAAAIAYABrDAAAAQBCAOoMAAADAFsALgAECn8vAAICAAkJ5SP0AACZAwACAAkJ5SP0AACZAwAAAA==.',
Pl='Platen:BAABLgAECn8cAAIZAAgJlQ4/PAByAQhoDAAABgAvAGkMAAAFACYAawwAAAUAKABqDAAAAwAwAGwMAAADAEwAbQwAAAEABQDqDAAABAAwAG4MAAABAAQAGQAICZUOPzwAcgEIaAwAAAYALwBpDAAABQAmAGsMAAAFACgAagwAAAMAMABsDAAAAwBMAG0MAAABAAUA6gwAAAQAMABuDAAAAQAEAAAA.',
Po='Potter:BAABLgAECn8zAAIEAAkJwxy6FQCBAgloDAAABwBUAGkMAAAHAEwAawwAAAcAUQBqDAAABgBBAGwMAAAGAFwAbQwAAAUALwDqDAAABwBQAG4MAAAEAEUAbwwAAAIAOQAEAAkJwxy6FQCBAgloDAAABwBUAGkMAAAHAEwAawwAAAcAUQBqDAAABgBBAGwMAAAGAFwAbQwAAAUALwDqDAAABwBQAG4MAAAEAEUAbwwAAAIAOQAAAA==.',
Ra='Raffa:BAABLgAECn8cAAIRAAcJhhdSIgDDAQdoDAAABABRAGkMAAADAC4AawwAAAQAJwBqDAAABQBUAGwMAAACACoAbQwAAAEAOADqDAAACQBfABEABwmGF1IiAMMBB2gMAAAEAFEAaQwAAAMALgBrDAAABAAnAGoMAAAFAFQAbAwAAAIAKgBtDAAAAQA4AOoMAAAJAF8AAAA=.Rakandei:BAAALgADCgMJAwAAAA==.Raptor:BAAALgAFFAQJBAAAAA==.Rapunzel:BAAALgAECgkJAwAAAA==.Rataiga:BAAALgAECgYJEgAAAA==.',
Rh='Rheynah:BAABLgAECn8ZAAMcAAgJjQPUJQC1AAhoDAAABQAHAGkMAAAEABIAawwAAAQABABqDAAAAwAVAGwMAAADAA0AbQwAAAEACADqDAAABAAFAG4MAAABAAQAHAAICUkD1CUAtQAIaAwAAAEABABpDAAAAQASAGsMAAABAAQAagwAAAEAFQBsDAAAAQANAG0MAAABAAgA6gwAAAEAAwBuDAAAAQAEAB0ABgkHA/FNAJkABmgMAAAEAAcAaQwAAAMADwBrDAAAAwADAGoMAAACAAMAbAwAAAIABwDqDAAAAwAFAAAA.',
Ri='Rimuna:BAAALgADCgUJBQAAAA==.Rinni:BAACLgAFFH8UAAIOAAYJAR9vAADOAQZoDAAABQBeAGkMAAAEAEkAawwAAAMAUgBqDAAAAgAgAGwMAAABADYA6gwAAAUAXQAOAAYJAR9vAADOAQZoDAAABQBeAGkMAAAEAEkAawwAAAMAUgBqDAAAAgAgAGwMAAABADYA6gwAAAUAXQAuAAQKfyYAAg4ACQkQJdwBAEUDAA4ACQkQJdwBAEUDAAAA.',
Ro='Rovintis:BAABLgAECn8mAAIcAAgJFBhaBwD/AQhoDAAABwBOAGkMAAAHAEAAawwAAAYAQQBqDAAABQBHAGwMAAAEAEMAbQwAAAIANgDqDAAABgBUAG4MAAABABAAHAAICRQYWgcA/wEIaAwAAAcATgBpDAAABwBAAGsMAAAGAEEAagwAAAUARwBsDAAABABDAG0MAAACADYA6gwAAAYAVABuDAAAAQAQAAAA.',
Ry='Rynne:BAAALgAECgcJEgAAAA==.',
Sa='Sansundertal:BAABLgAECn8wAAIIAAkJsSJ+AgBJAwloDAAABwBcAGkMAAAGAFEAawwAAAYAYQBqDAAABgBjAGwMAAAGAGAAbQwAAAQAWwDqDAAABwBjAG4MAAAEAFkAbwwAAAIAMgAIAAkJsSJ+AgBJAwloDAAABwBcAGkMAAAGAFEAawwAAAYAYQBqDAAABgBjAGwMAAAGAGAAbQwAAAQAWwDqDAAABwBjAG4MAAAEAFkAbwwAAAIAMgAAAA==.Sargeràs:BAAALgADCgYJBgABLgAECgMJAwABAAAAAA==.',
Se='Selissaroth:BAAALgAECgEJAQAAAA==.Sentinal:BAABLgAECn8kAAIYAAgJVRUEDQC8AQhoDAAABgBXAGkMAAAGAD0AawwAAAUAOwBqDAAABQBUAGwMAAAEAEMAbQwAAAIAEQDqDAAABgAyAG4MAAACACcAGAAICVUVBA0AvAEIaAwAAAYAVwBpDAAABgA9AGsMAAAFADsAagwAAAUAVABsDAAABABDAG0MAAACABEA6gwAAAYAMgBuDAAAAgAnAAAA.Sentinäl:BAAALgADCgIJAgAAAA==.Sephiro:BAAALgAECgQJBgAAAA==.',
Sh='Shamu:BAACLgAFFH8FAAICAAIJvBVHNACWAAJoDAAAAwAWAOoMAAACAFgAAgACCbwVRzQAlgACaAwAAAMAFgDqDAAAAgBYAC4ABAp/GAACAgAICb8VtS4AcwEAAgAICb8VtS4AcwEAAAA=.Shawner:BAAALgADCgMJAwAAAA==.Shy:BAAALgAECgIJAgAAAA==.',
Si='Silvertiger:BAABLgAECn8yAAMPAAkJ0xxbAwCzAgloDAAABgBYAGkMAAAHAFoAawwAAAcATwBqDAAABgBGAGwMAAAGAE4AbQwAAAUAPwDqDAAABwA1AG4MAAAEAEsAbwwAAAIAPQAPAAkJ0xxbAwCzAgloDAAABQBYAGkMAAAFAFoAawwAAAUATwBqDAAABQBGAGwMAAAFAE4AbQwAAAQAPwDqDAAABQA1AG4MAAAEAEsAbwwAAAIAPQAeAAcJgg+dPABsAQdoDAAAAQAtAGkMAAACADMAawwAAAIAJABqDAAAAQASAGwMAAABACwAbQwAAAEAIADqDAAAAgAdAAAA.',
Sl='Slabbydabby:BAAALgAECgIJAwAAAA==.Sleeperbater:BAAALgADCgIJAgAAAA==.Sleeperdk:BAAALgAECgYJCwAAAA==.',
Sn='Snackyfraps:BAAALgADCgUJCAABLgAECgkJMwAXABEfAA==.Sneaki:BAABLgAECn8xAAQfAAkJaSKqAQBlAgloDAAABwBjAGkMAAAHAFMAawwAAAcAVwBqDAAABgBLAGwMAAAGAF0AbQwAAAQASADqDAAABwBPAG4MAAADAGEAbwwAAAIAWwAgAAkJuCDQBACIAgloDAAABgBjAGkMAAAGAFMAawwAAAYAVwBqDAAABQBCAGwMAAACAD8AbQwAAAMASADqDAAABgBLAG4MAAACAGEAbwwAAAIAWwAfAAgJ+xyqAQBlAghoDAAAAQBXAGkMAAABACsAawwAAAEARwBqDAAAAQBLAGwMAAABAF0AbQwAAAEAQQDqDAAAAQBPAG4MAAABAE4AEAABCcEc+RcAUwABbAwAAAMASQAAAA==.Sniperanger:BAAALgADCgMJAwAAAA==.Snstr:BAABLgAECn8aAAQVAAYJbRfiLACTAQZoDAAABgBOAGkMAAAFAEgAawwAAAQATABqDAAAAwAaAGwMAAADACgA6gwAAAUAQAAVAAYJbRfiLACTAQZoDAAABQBOAGkMAAAEAEgAawwAAAMATABqDAAAAgAaAGwMAAACACgA6gwAAAQAQAAWAAQJ5gMhTQChAARpDAAAAQAGAGsMAAABAA4AagwAAAEADgBsDAAAAQAJABcAAgmRCFlNAF0AAmgMAAABAA4A6gwAAAEAHAAAAA==.',
So='Sorynia:BAAALgAECgUJDgAAAA==.Soul:BAAALgAECgEJAQAAAA==.Soulkid:BAAALgAECgQJBQAAAA==.',
St='Starta:BAACLgAFFH8KAAIbAAMJ5xnXMgD7AANoDAAABAA7AGkMAAADADwA6gwAAAMATgAbAAMJ5xnXMgD7AANoDAAABAA7AGkMAAADADwA6gwAAAMATgAuAAQKfxUAAhsACAmNISMVACkCABsACAmNISMVACkCAAAA.Startawar:BAABLgAECn8kAAILAAgJxyP/DACtAghoDAAABgBjAGkMAAAGAGEAawwAAAYAYQBqDAAABABcAGwMAAAEAGAAbQwAAAIANwDqDAAABQBiAG4MAAADAF8ACwAICccj/wwArQIIaAwAAAYAYwBpDAAABgBhAGsMAAAGAGEAagwAAAQAXABsDAAABABgAG0MAAACADcA6gwAAAUAYgBuDAAAAwBfAAAA.',
Su='Sukii:BAAALgAECgUJBgAAAA==.Sulfuricvein:BAAALgAECgMJBQAAAA==.',
['Sø']='Sømebody:BAAALgAECgMJAwAAAA==.',
Ti='Tiana:BAAALgAECgkJBAAAAA==.',
To='Totemdaddy:BAAALgAECgEJAQAAAA==.Totemicdidit:BAAALgADCgMJAwAAAA==.Totemstorm:BAAALgAECgcJBwAAAA==.',
Tr='Traumatic:BAABLgAECn8UAAIdAAcJjRj6LwDvAQdoDAAAAwBIAGkMAAAEAEUAawwAAAMAPwBqDAAAAwAfAGwMAAACADwA6gwAAAQASQBuDAAAAQAlAB0ABwmNGPovAO8BB2gMAAADAEgAaQwAAAQARQBrDAAAAwA/AGoMAAADAB8AbAwAAAIAPADqDAAABABJAG4MAAABACUAAAA=.',
Tu='Tunny:BAAALgAECgYJCAAAAA==.Turnleft:BAABLgAECn8sAAIhAAgJcSWKAgBnAwhoDAAABwBjAGkMAAAHAGEAawwAAAYAYwBqDAAABgBiAGwMAAAGAGMAbQwAAAMAXQDqDAAABgBiAG4MAAADAE8AIQAICXEligIAZwMIaAwAAAcAYwBpDAAABwBhAGsMAAAGAGMAagwAAAYAYgBsDAAABgBjAG0MAAADAF0A6gwAAAYAYgBuDAAAAwBPAAAA.',
Va='Vauntmonk:BAAALgADCgMJAwABLgAFFAQJCgAiAN4fAA==.',
Ve='Vercyv:BAAALgADCgkJEQAAAA==.Vevio:BAAALgAECgQJBAAAAA==.',
Vi='Video:BAAALgAECgEJAQAAAA==.Violet:BAABLgAECn8nAAIMAAkJWx0CDgCoAgloDAAABgBZAGkMAAAGAFgAawwAAAUAVwBqDAAABABZAGwMAAAEAFkAbQwAAAMASwDqDAAABgBbAG4MAAADAC4AbwwAAAIAIAAMAAkJWx0CDgCoAgloDAAABgBZAGkMAAAGAFgAawwAAAUAVwBqDAAABABZAGwMAAAEAFkAbQwAAAMASwDqDAAABgBbAG4MAAADAC4AbwwAAAIAIAAAAA==.Vishlock:BAABLgAECn8tAAMSAAkJ9xbaAgAJAgloDAAABgBQAGkMAAAGADsAawwAAAYANwBqDAAABQA1AGwMAAAFAEsAbQwAAAQAGwDqDAAABwBMAG4MAAAEADQAbwwAAAIAKgASAAkJ9xbaAgAJAgloDAAABQBQAGkMAAAGADsAawwAAAUANwBqDAAAAwA1AGwMAAAEAEsAbQwAAAIAGwDqDAAABQBMAG4MAAABADQAbwwAAAIAKgAKAAcJcA4OlAAwAQdoDAAAAQARAGsMAAABACAAagwAAAIACgBsDAAAAQBBAG0MAAACABEA6gwAAAIAQQBuDAAAAwAXAAAA.',
Vo='Voddie:BAABLgAECn8ZAAIDAAcJOAnZNQDrAAdoDAAABQAdAGkMAAAFABQAawwAAAUAHgBqDAAAAwALAGwMAAADABUAbQwAAAEACQDqDAAAAwAeAAMABwk4Cdk1AOsAB2gMAAAFAB0AaQwAAAUAFABrDAAABQAeAGoMAAADAAsAbAwAAAMAFQBtDAAAAQAJAOoMAAADAB4AAAA=.Votarick:BAAALgAECgEJAQAAAA==.',
Wa='Waban:BAAALgAECgcJEwAAAA==.Walmarthas:BAAALgAECgcJCwABLgAECggJGgAGAEwVAA==.Wapta:BAAALgAFFAEJAQABLgAFFAQJBAABAAAAAA==.',
Wi='Wizwiztheliz:BAAALgAECgYJDwAAAA==.',
Wo='Wolf:BAABLgAECn8bAAIjAAgJXQ7+GQB1AQhoDAAABgAwAGkMAAAFACcAawwAAAUAIABqDAAAAwAbAGwMAAACADEAbQwAAAEABwDqDAAABAA2AG4MAAABABkAIwAICV0O/hkAdQEIaAwAAAYAMABpDAAABQAnAGsMAAAFACAAagwAAAMAGwBsDAAAAgAxAG0MAAABAAcA6gwAAAQANgBuDAAAAQAZAAEuAAUUAQkBAAEAAAAA.Woof:BAAALgAECgIJAgAAAA==.',
Xy='Xynelle:BAAALgADCgcJCwAAAA==.',
Ya='Yahtzee:BAAALgAECgQJBwAAAA==.',
Yo='Youdidwhat:BAAALgADCgkJCQAAAA==.',
Za='Zaia:BAAALgAECgYJDAAAAA==.',
Ze='Zenithmage:BAAALgAECgcJDQAAAA==.',
['Ár']='Ártémes:BAAALgADCggJAgAAAA==.',
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
