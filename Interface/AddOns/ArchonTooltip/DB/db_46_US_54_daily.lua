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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Shaman-Elemental','Mage-Frost','Paladin-Holy','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Paladin-Protection','Warlock-Demonology','Paladin-Retribution','DeathKnight-Unholy','DeathKnight-Frost','Druid-Feral','Hunter-Survival','Rogue-Assassination','Monk-Windwalker','Warlock-Affliction','Warlock-Destruction','DemonHunter-Havoc','Priest-Holy','Priest-Shadow','Priest-Discipline','DeathKnight-Blood','Hunter-BeastMastery','Druid-Guardian','DemonHunter-Devourer','Warrior-Arms','Warrior-Fury','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Outlaw','Druid-Restoration','Warrior-Protection','Monk-Brewmaster',}
local provider = {region='US',realm='Coilfang',name='US',type='daily',zone=46,date='2026-05-11',data={Ae='Aendean:BAAALgAECgEJAQAAAA==.',
Am='Amethyne:BAAALgADCgMJAwAAAA==.',
An='Anabell:BAAALgADCgcJDwABLgAECgYJBwABAAAAAA==.',
Ar='Arckane:BAAALgAECgEJAQAAAA==.Arcueid:BAABLgAECn8oAAMCAAkJqSBmEwAwAgloDAAABQBQAGkMAAAFAFMAawwAAAcAWABqDAAABQBVAGwMAAAFAEkAbQwAAAIAOwDqDAAACABZAG4MAAACAFwAbwwAAAEAYwACAAgJ5B9mEwAwAghoDAAABQBQAGkMAAAFAFMAawwAAAcAWABqDAAABQBVAGwMAAAFAEkAbQwAAAIAOwDqDAAACABZAG4MAAACAFwAAwABCZ4RKWEARwABbwwAAAEALQAAAA==.',
As='Asmadeus:BAAALgAECgEJAQAAAA==.',
Ay='Ayda:BAABLgAECn8zAAIEAAkJDyOTBQAmAwloDAAABwBhAGkMAAAHAFwAawwAAAcAYQBqDAAABgBOAGwMAAAGAF8AbQwAAAUAWQDqDAAABwBfAG4MAAAEAE0AbwwAAAIASAAEAAkJDyOTBQAmAwloDAAABwBhAGkMAAAHAFwAawwAAAcAYQBqDAAABgBOAGwMAAAGAF8AbQwAAAUAWQDqDAAABwBfAG4MAAAEAE0AbwwAAAIASAAAAA==.',
Ba='Bartholdson:BAAALgAECgYJDAAAAA==.',
Be='Bearlydidit:BAAALgADCgQJBAAAAA==.Beloc:BAAALgAECggJAgAAAA==.Berzerkirz:BAAALgADCgYJBgAAAA==.',
Bl='Blacksnow:BAAALgADCgEJAQAAAA==.Blcksnowcrow:BAABLgAECn8dAAIFAAkJ8BkjCwBvAgloDAAABQBNAGkMAAAEAFkAawwAAAQAXABqDAAAAgAgAGwMAAADAFAAbQwAAAMAQwDqDAAABgBGAG4MAAABACkAbwwAAAEALwAFAAkJ8BkjCwBvAgloDAAABQBNAGkMAAAEAFkAawwAAAQAXABqDAAAAgAgAGwMAAADAFAAbQwAAAMAQwDqDAAABgBGAG4MAAABACkAbwwAAAEALwAAAA==.',
Bo='Bonfire:BAABLgAECn8kAAQGAAgJASMjBwB0AghoDAAABgBfAGkMAAAGAF8AawwAAAYAXQBqDAAABQBjAGwMAAAEAFUAbQwAAAIAUgDqDAAABgBdAG4MAAABAFEABgAICQEjIwcAdAIIaAwAAAQAXwBpDAAABABfAGsMAAAFAF0AagwAAAQAYwBsDAAAAwBVAG0MAAACAFIA6gwAAAUAXQBuDAAAAQBRAAcABQncILgOALAABWgMAAACAF0AaQwAAAEATABqDAAAAQBfAGwMAAABAEoA6gwAAAEAWwAIAAIJSgKBRABLAAJpDAAAAQAHAGsMAAABAAQAAS4ABRQECQQAAQAAAAA=.Boochili:BAABLgAECn8vAAIJAAkJiiYQAACIAwloDAAABgBjAGkMAAAGAGMAawwAAAYAYwBqDAAABgBjAGwMAAAGAGMAbQwAAAUAYwDqDAAABgBiAG4MAAAEAGMAbwwAAAIAXAAJAAkJiiYQAACIAwloDAAABgBjAGkMAAAGAGMAawwAAAYAYwBqDAAABgBjAGwMAAAGAGMAbQwAAAUAYwDqDAAABgBiAG4MAAAEAGMAbwwAAAIAXAAAAA==.',
Br='Braveling:BAABLgAECn8YAAIKAAgJOQxvPgB7AQhoDAAABAAZAGkMAAAEACwAawwAAAQAGQBqDAAAAwAvAGwMAAADAC0AbQwAAAEAIADqDAAABAAaAG4MAAABABMACgAICTkMbz4AewEIaAwAAAQAGQBpDAAABAAsAGsMAAAEABkAagwAAAMALwBsDAAAAwAtAG0MAAABACAA6gwAAAQAGgBuDAAAAQATAAAA.',
Bu='Bubblës:BAAALgAECgQJBgABLgAECggJHwAEAAgiAA==.',
Ca='Carezarsh:BAAALgADCgMJAQAAAA==.',
Ch='Charlie:BAACLgAFFH8SAAMLAAQJxyPzCgCNAQRoDAAABQBdAGkMAAAEAFoAawwAAAQAXwDqDAAABQBWAAsABAnHI/MKAI0BBGgMAAAFAF0AaQwAAAQAWgBrDAAAAwBfAOoMAAAFAFYACQABCUAjRQoAZgABawwAAAEAWgAuAAQKfzAAAwsACQm5JfkFAP4CAAsACQm5JfkFAP4CAAkAAwlgGPkqAFwAAAAA.Chicken:BAAALgAFFAEJAQAAAA==.',
Cr='Cruel:BAAALgADCgEJAQAAAA==.',
['Cä']='Cätîáñdrïà:BAABLgAECn9LAAMCAAkJzR2LCQCkAgloDAAACgBCAGkMAAAJAEsAawwAAAkAWgBqDAAACgA/AGwMAAAJAEoAbQwAAAcAUgDqDAAADABaAG4MAAAGADoAbwwAAAMAUwACAAkJzR2LCQCkAgloDAAACQBCAGkMAAAHAEsAawwAAAcAWgBqDAAACAA/AGwMAAAIAEoAbQwAAAcAUgDqDAAADABaAG4MAAAGADoAbwwAAAMAUwADAAUJaA5hOQDXAAVoDAAAAQAyAGkMAAACAB4AawwAAAIALwBqDAAAAgAzAGwMAAABABMAAAA=.',
Da='Daniedk:BAABLgAECn8jAAIMAAgJDhM3PgCUAQhoDAAABQBDAGkMAAAGAC4AawwAAAUAHQBqDAAABgBAAGwMAAAEACsAbQwAAAIAFQDqDAAABABDAG4MAAADAEEADAAICQ4TNz4AlAEIaAwAAAUAQwBpDAAABgAuAGsMAAAFAB0AagwAAAYAQABsDAAABAArAG0MAAACABUA6gwAAAQAQwBuDAAAAwBBAAAA.Daphanim:BAAALgADCgYJCgAAAA==.Darctotem:BAAALgAECgUJCwAAAA==.',
De='Deathtouch:BAACLgAFFH8HAAMMAAMJPhzoVgDyAANoDAAAAgBTAGkMAAADADcA6gwAAAIATQAMAAMJPhzoVgDyAANoDAAAAQBTAGkMAAACADcA6gwAAAIATQANAAIJSRBxCACfAAJoDAAAAQAnAGkMAAABACsALgAECn8bAAMMAAgJRyOsEgB5AgAMAAgJxyKsEgB5AgANAAEJEh0eFgBQAAAAAA==.Devona:BAABLgAECn8dAAMFAAgJ5RuVGADVAQhoDAAABgBBAGkMAAAFAFAAawwAAAUATQBqDAAAAwBNAGwMAAADAF8AbQwAAAEAHQDqDAAABQBYAG4MAAABADgABQAHCbQclRgA1QEHaAwAAAQAQQBpDAAABABQAGsMAAAEAE0AagwAAAIATQBsDAAAAgBfAG0MAAABAB0A6gwAAAQAWAALAAcJmwxfWgBOAQdoDAAAAgAkAGkMAAABAC4AawwAAAEAGABqDAAAAQAbAGwMAAABACgA6gwAAAEAGgBuDAAAAQATAAAA.',
Di='Didit:BAAALgADCgcJBwAAAA==.Dingledangle:BAABLgAECn8VAAIOAAcJBBJJDQBYAQdoDAAABAA4AGkMAAAEADwAawwAAAQANABqDAAABAA5AGwMAAABAAkAbQwAAAEAIwDqDAAAAwA+AA4ABwkEEkkNAFgBB2gMAAAEADgAaQwAAAQAPABrDAAABAA0AGoMAAAEADkAbAwAAAEACQBtDAAAAQAjAOoMAAADAD4AAAA=.',
Dj='Djindor:BAAALgADCgUJBQAAAA==.',
Dr='Draconix:BAAALgAECgQJBAABLgAECgYJBgABAAAAAA==.Dragonzordd:BAAALgADCgQJBQABLgAECgYJFAAPAAwiAA==.Dragooncrush:BAAALgADCgIJAgAAAA==.Dragoonnick:BAABLgAECn81AAIQAAkJwhsWBAB0AgloDAAACABaAGkMAAAJAE0AawwAAAkAVABqDAAABgBBAGwMAAAGAEgAbQwAAAIAKQDqDAAACQBIAG4MAAADAFIAbwwAAAEALgAQAAkJwhsWBAB0AgloDAAACABaAGkMAAAJAE0AawwAAAkAVABqDAAABgBBAGwMAAAGAEgAbQwAAAIAKQDqDAAACQBIAG4MAAADAFIAbwwAAAEALgAAAA==.Drazzy:BAAALgAECgIJAgAAAA==.',
Es='Esh:BAAALgAECgcJDgAAAA==.',
Eu='Euphal:BAABLgAECn8mAAIKAAgJ2xLdMwCgAQhoDAAABAA1AGkMAAAGAC0AawwAAAUAIQBqDAAAAwA1AGwMAAAHAEAAbQwAAAIAFwDqDAAABwBDAG4MAAAEADIACgAICdsS3TMAoAEIaAwAAAQANQBpDAAABgAtAGsMAAAFACEAagwAAAMANQBsDAAABwBAAG0MAAACABcA6gwAAAcAQwBuDAAABAAyAAAA.',
Ey='Eyekicku:BAABLgAECn8cAAIRAAgJdSDMBQCLAghoDAAABgBcAGkMAAAFAFoAawwAAAUAWQBqDAAAAwBaAGwMAAADAE4AbQwAAAEAQADqDAAABABUAG4MAAABAFEAEQAICXUgzAUAiwIIaAwAAAYAXABpDAAABQBaAGsMAAAFAFkAagwAAAMAWgBsDAAAAwBOAG0MAAABAEAA6gwAAAQAVABuDAAAAQBRAAAA.',
Fe='Feldana:BAAALgAECgQJBAAAAA==.Fenicon:BAAALgAECgQJBQAAAA==.',
Fi='Fitz:BAAALgAECgQJBAAAAA==.Fitzwell:BAAALgAECgQJBAAAAA==.',
Fu='Fuyu:BAAALgAECgQJBAAAAA==.Fuyuhex:BAAALgAFFAIJAQAAAA==.',
Gh='Ghost:BAAALgAECgMJBQAAAA==.',
Gr='Graycieden:BAAALgAECgYJBwAAAA==.',
Gu='Guldangit:BAACLgAFFH8dAAMKAAcJGhyZAgAXAgdoDAAABgBcAGkMAAAEAFsAawwAAAUAUgBqDAAABABLAGwMAAADADkAbQwAAAEAIgDqDAAABgBIAAoABwkaHJkCABcCB2gMAAAGAFwAaQwAAAQAWwBrDAAABQBSAGoMAAADAEQAbAwAAAMAOQBtDAAAAQAiAOoMAAAGAEgAEgABCQAAPwMAYAABagwAAAEASwAuAAQKfykAAwoACQnCI2oIAD4DAAoACQkBI2oIAD4DABMABAmOIi4aAHsBAAAA.',
Ha='Hanora:BAAALgAECgEJAQAAAA==.',
He='Hellspawn:BAABLgAECn8zAAIUAAkJxg4fDQDCAQloDAAABwA+AGkMAAAHADMAawwAAAcALABqDAAABgAbAGwMAAAGACIAbQwAAAUAGADqDAAABwAfAG4MAAAEABwAbwwAAAIAGQAUAAkJxg4fDQDCAQloDAAABwA+AGkMAAAHADMAawwAAAcALABqDAAABgAbAGwMAAAGACIAbQwAAAUAGADqDAAABwAfAG4MAAAEABwAbwwAAAIAGQAAAA==.',
Hh='Hhounow:BAAALgADCgYJBgAAAA==.',
Ho='Hojai:BAAALgADCgMJAwAAAA==.Holybeef:BAAALgAECgcJDQAAAA==.Holygrim:BAACLgAFFH8aAAIVAAcJ5yMaAABvAgdoDAAABQBkAGkMAAAFAGEAawwAAAQAYgBqDAAAAwBeAGwMAAACAFEAbQwAAAEAVgDqDAAABgBVABUABwnnIxoAAG8CB2gMAAAFAGQAaQwAAAUAYQBrDAAABABiAGoMAAADAF4AbAwAAAIAUQBtDAAAAQBWAOoMAAAGAFUALgAECn8dAAMVAAgJYybgAQBXAwAVAAgJYybgAQBXAwAWAAEJPgl2WQAzAAAAAA==.Holyloa:BAAALgAECgMJAwAAAA==.Holypablo:BAABLgAECn8zAAQXAAkJER+JAgAvAwloDAAABwBJAGkMAAAHAFoAawwAAAcAXgBqDAAABgBfAGwMAAAGAGEAbQwAAAUAUADqDAAABwA6AG4MAAAEAEIAbwwAAAIAOwAXAAkJER+JAgAvAwloDAAABABJAGkMAAAEAFoAawwAAAQAXgBqDAAABgBfAGwMAAAGAGEAbQwAAAUAUADqDAAABQA6AG4MAAAEAEIAbwwAAAIAOwAWAAQJaRR6MwDVAARoDAAAAgA1AGkMAAACAEIAawwAAAIAPQDqDAAAAQAbABUABAmtC5ZdALwABGgMAAABAA4AaQwAAAEAGABrDAAAAQAxAOoMAAABAB8AAAA=.Howii:BAABLgAECn81AAIYAAkJvSSpAABNAwloDAAACABbAGkMAAAHAGIAawwAAAcAYABqDAAABgBfAGwMAAAGAGEAbQwAAAUAWgDqDAAACABfAG4MAAAEAFcAbwwAAAIAXwAYAAkJvSSpAABNAwloDAAACABbAGkMAAAHAGIAawwAAAcAYABqDAAABgBfAGwMAAAGAGEAbQwAAAUAWgDqDAAACABfAG4MAAAEAFcAbwwAAAIAXwAAAA==.',
Im='Imperator:BAAALgAECgQJBAAAAA==.',
In='Inchworm:BAAALgAECgYJBgAAAA==.',
Is='Isabellaah:BAABLgAECn8bAAIZAAcJ9xKcOwBwAQdoDAAABgA6AGkMAAAFAEYAawwAAAUAMABqDAAAAwAgAGwMAAADADwAbQwAAAEACQDqDAAABAAsABkABwn3Epw7AHABB2gMAAAGADoAaQwAAAUARgBrDAAABQAwAGoMAAADACAAbAwAAAMAPABtDAAAAQAJAOoMAAAEACwAAAA=.',
Je='Jellyfïsh:BAAALgAECgUJCgAAAA==.Jeraziah:BAAALgAECgUJEQABLgAECgkJKAACAKkgAA==.',
Jo='Johnnyjr:BAAALgAECgkJEgAAAA==.',
Ke='Kelliz:BAAALgADCgcJCAAAAA==.',
Kh='Khaladin:BAAALgAECgYJEgAAAA==.',
La='Laggers:BAABLgAECn8jAAIaAAgJdxbsCwB0AQhoDAAABgA3AGkMAAAGAE4AawwAAAYARgBqDAAABQAwAGwMAAADADMAbQwAAAEAGgDqDAAABwBKAG4MAAABAC0AGgAICXcW7AsAdAEIaAwAAAYANwBpDAAABgBOAGsMAAAGAEYAagwAAAUAMABsDAAAAwAzAG0MAAABABoA6gwAAAcASgBuDAAAAQAtAAAA.',
Li='Litbit:BAABLgAECn8XAAIEAAcJ5wMGlgD4AAdoDAAABAALAGkMAAAEABAAawwAAAQABgBqDAAABAAGAGwMAAADAA4AbQwAAAEABgDqDAAAAwAEAAQABwnnAwaWAPgAB2gMAAAEAAsAaQwAAAQAEABrDAAABAAGAGoMAAAEAAYAbAwAAAMADgBtDAAAAQAGAOoMAAADAAQAAAA=.Litbitonme:BAAALgAECgMJAwAAAA==.Litt:BAAALgADCgkJCwAAAA==.Lizardwizard:BAAALgAECgEJAQAAAA==.',
Lo='Lockmantwo:BAAALgAECgcJAwAAAA==.Lostmoo:BAAALgAECgEJAQAAAA==.Lostunholy:BAABLgAECn8XAAIMAAcJhCApJgD6AQdoDAAABwBhAGkMAAAEAFIAawwAAAMAVwBqDAAAAgBaAGwMAAACAFMAbQwAAAEAOQDqDAAABABaAAwABwmEICkmAPoBB2gMAAAHAGEAaQwAAAQAUgBrDAAAAwBXAGoMAAACAFoAbAwAAAIAUwBtDAAAAQA5AOoMAAAEAFoAAAA=.Lovebug:BAAALgADCgcJBwAAAA==.',
Lu='Lunaardris:BAAALgAECgQJBQAAAA==.',
Ly='Lynxe:BAAALgAECgYJBgAAAA==.',
Ma='Maggikal:BAABLgAECn8XAAIEAAYJtQzGhwASAQZoDAAABQA3AGkMAAAEABgAawwAAAQAIwBqDAAAAgAWAGwMAAACAAoA6gwAAAYAJAAEAAYJtQzGhwASAQZoDAAABQA3AGkMAAAEABgAawwAAAQAIwBqDAAAAgAWAGwMAAACAAoA6gwAAAYAJAAAAA==.',
Me='Megahottie:BAAALgADCgYJBgAAAA==.',
Mi='Mirant:BAAALgAECgUJDQAAAA==.',
Mo='Moretisha:BAAALgADCgYJBgAAAA==.',
Na='Nakwoo:BAAALgADCgMJAwAAAA==.',
On='One:BAAALgAECgEJAQAAAA==.',
Op='Opallea:BAABLgAECn8YAAMUAAgJphueEQBRAghoDAAABABPAGkMAAAFAE4AawwAAAUASwBqDAAAAwBOAGwMAAACAEgAbQwAAAEARADqDAAAAwBKAG4MAAABAC4AFAAICaYbnhEAUQIIaAwAAAMATwBpDAAABABOAGsMAAAEAEsAagwAAAIATgBsDAAAAgBIAG0MAAABAEQA6gwAAAMASgBuDAAAAQAuABsABAnqBNaaAGsABGgMAAABAAoAaQwAAAEAEgBrDAAAAQAJAGoMAAABAB4AAAA=.',
Pa='Pallyplay:BAAALgAECgEJAQAAAA==.',
Pb='Pballs:BAAALgADCgEJAQABLgAECgkJMwAXABEfAA==.',
Pe='Periodic:BAACLgAFFH8JAAICAAQJtCHlCgCJAQRoDAAABABbAGkMAAACAGAAawwAAAEAQgDqDAAAAgBbAAIABAm0IeUKAIkBBGgMAAAEAFsAaQwAAAIAYABrDAAAAQBCAOoMAAACAFsALgAECn8vAAICAAkJ5SP0AACZAwACAAkJ5SP0AACZAwAAAA==.',
Pl='Platen:BAABLgAECn8cAAIZAAgJlQ6oOgBzAQhoDAAABgAvAGkMAAAFACYAawwAAAUAKABqDAAAAwAwAGwMAAADAEwAbQwAAAEABQDqDAAABAAwAG4MAAABAAQAGQAICZUOqDoAcwEIaAwAAAYALwBpDAAABQAmAGsMAAAFACgAagwAAAMAMABsDAAAAwBMAG0MAAABAAUA6gwAAAQAMABuDAAAAQAEAAAA.',
Po='Potter:BAABLgAECn8zAAIEAAkJwxwNFQCCAgloDAAABwBUAGkMAAAHAEwAawwAAAcAUQBqDAAABgBBAGwMAAAGAFwAbQwAAAUALwDqDAAABwBQAG4MAAAEAEUAbwwAAAIAOQAEAAkJwxwNFQCCAgloDAAABwBUAGkMAAAHAEwAawwAAAcAUQBqDAAABgBBAGwMAAAGAFwAbQwAAAUALwDqDAAABwBQAG4MAAAEAEUAbwwAAAIAOQAAAA==.',
Ra='Raffa:BAABLgAECn8cAAIRAAcJhhdOIgDDAQdoDAAABABRAGkMAAADAC4AawwAAAQAJwBqDAAABQBUAGwMAAACACoAbQwAAAEAOADqDAAACQBfABEABwmGF04iAMMBB2gMAAAEAFEAaQwAAAMALgBrDAAABAAnAGoMAAAFAFQAbAwAAAIAKgBtDAAAAQA4AOoMAAAJAF8AAAA=.Rakandei:BAAALgADCgMJAwAAAA==.Raptor:BAAALgAFFAQJBAAAAA==.Rapunzel:BAAALgAECgkJAwAAAA==.Rataiga:BAAALgAECgYJEgAAAA==.',
Rh='Rheynah:BAABLgAECn8ZAAMcAAgJjQPYJAC1AAhoDAAABQAHAGkMAAAEABIAawwAAAQABABqDAAAAwAVAGwMAAADAA0AbQwAAAEACADqDAAABAAFAG4MAAABAAQAHAAICUkD2CQAtQAIaAwAAAEABABpDAAAAQASAGsMAAABAAQAagwAAAEAFQBsDAAAAQANAG0MAAABAAgA6gwAAAEAAwBuDAAAAQAEAB0ABgkHA4BMAJoABmgMAAAEAAcAaQwAAAMADwBrDAAAAwADAGoMAAACAAMAbAwAAAIABwDqDAAAAwAFAAAA.',
Ri='Rimuna:BAAALgADCgUJBQAAAA==.Rinni:BAACLgAFFH8TAAIOAAYJAR9pAADOAQZoDAAABABeAGkMAAAEAEkAawwAAAMAUgBqDAAAAgAgAGwMAAABADYA6gwAAAUAXQAOAAYJAR9pAADOAQZoDAAABABeAGkMAAAEAEkAawwAAAMAUgBqDAAAAgAgAGwMAAABADYA6gwAAAUAXQAuAAQKfyYAAg4ACQkQJdwBAEUDAA4ACQkQJdwBAEUDAAAA.',
Ro='Rovintis:BAABLgAECn8mAAIcAAgJFBgXBwAAAghoDAAABwBOAGkMAAAHAEAAawwAAAYAQQBqDAAABQBHAGwMAAAEAEMAbQwAAAIANgDqDAAABgBUAG4MAAABABAAHAAICRQYFwcAAAIIaAwAAAcATgBpDAAABwBAAGsMAAAGAEEAagwAAAUARwBsDAAABABDAG0MAAACADYA6gwAAAYAVABuDAAAAQAQAAAA.',
Ry='Rynne:BAAALgAECgcJEgAAAA==.',
Sa='Sansundertal:BAABLgAECn8wAAIIAAkJsSJ/AgBJAwloDAAABwBcAGkMAAAGAFEAawwAAAYAYQBqDAAABgBjAGwMAAAGAGAAbQwAAAQAWwDqDAAABwBjAG4MAAAEAFkAbwwAAAIAMgAIAAkJsSJ/AgBJAwloDAAABwBcAGkMAAAGAFEAawwAAAYAYQBqDAAABgBjAGwMAAAGAGAAbQwAAAQAWwDqDAAABwBjAG4MAAAEAFkAbwwAAAIAMgAAAA==.Sargeràs:BAAALgADCgYJBgABLgAECgMJAwABAAAAAA==.',
Se='Selissaroth:BAAALgAECgEJAQAAAA==.Sentinal:BAABLgAECn8jAAIYAAgJVRW4DAC8AQhoDAAABgBXAGkMAAAGAD0AawwAAAUAOwBqDAAABQBUAGwMAAAEAEMAbQwAAAIAEQDqDAAABgAyAG4MAAABACcAGAAICVUVuAwAvAEIaAwAAAYAVwBpDAAABgA9AGsMAAAFADsAagwAAAUAVABsDAAABABDAG0MAAACABEA6gwAAAYAMgBuDAAAAQAnAAAA.Sentinäl:BAAALgADCgIJAgAAAA==.Sephiro:BAAALgAECgQJBgAAAA==.',
Sh='Shamu:BAACLgAFFH8FAAICAAIJvBW3MgCWAAJoDAAAAwAWAOoMAAACAFgAAgACCbwVtzIAlgACaAwAAAMAFgDqDAAAAgBYAC4ABAp/GAACAgAICb8Vxy0AcwEAAgAICb8Vxy0AcwEAAAA=.Shawner:BAAALgADCgMJAwAAAA==.Shy:BAAALgAECgIJAgAAAA==.',
Si='Silvertiger:BAABLgAECn8yAAMPAAkJ0xwuAwC0AgloDAAABgBYAGkMAAAHAFoAawwAAAcATwBqDAAABgBGAGwMAAAGAE4AbQwAAAUAPwDqDAAABwA1AG4MAAAEAEsAbwwAAAIAPQAPAAkJ0xwuAwC0AgloDAAABQBYAGkMAAAFAFoAawwAAAUATwBqDAAABQBGAGwMAAAFAE4AbQwAAAQAPwDqDAAABQA1AG4MAAAEAEsAbwwAAAIAPQAeAAcJgg+ZPABsAQdoDAAAAQAtAGkMAAACADMAawwAAAIAJABqDAAAAQASAGwMAAABACwAbQwAAAEAIADqDAAAAgAdAAAA.',
Sl='Slabbydabby:BAAALgAECgIJAwAAAA==.Sleeperbater:BAAALgADCgIJAgAAAA==.Sleeperdk:BAAALgAECgYJCwAAAA==.',
Sn='Snackyfraps:BAAALgADCgUJCAABLgAECgkJMwAXABEfAA==.Sneaki:BAABLgAECn8xAAQfAAkJaSKYBACKAgloDAAABwBjAGkMAAAHAFMAawwAAAcAVwBqDAAABgBLAGwMAAAGAF0AbQwAAAQASADqDAAABwBPAG4MAAADAGEAbwwAAAIAWwAfAAkJuCCYBACKAgloDAAABgBjAGkMAAAGAFMAawwAAAYAVwBqDAAABQBCAGwMAAACAD8AbQwAAAMASADqDAAABgBLAG4MAAACAGEAbwwAAAIAWwAgAAgJ+xykAQBkAghoDAAAAQBXAGkMAAABACsAawwAAAEARwBqDAAAAQBLAGwMAAABAF0AbQwAAAEAQQDqDAAAAQBPAG4MAAABAE4AEAABCcEcjRcAVAABbAwAAAMASQAAAA==.Sniperanger:BAAALgADCgMJAwAAAA==.Snstr:BAABLgAECn8aAAQVAAYJbRfiLACTAQZoDAAABgBOAGkMAAAFAEgAawwAAAQATABqDAAAAwAaAGwMAAADACgA6gwAAAUAQAAVAAYJbRfiLACTAQZoDAAABQBOAGkMAAAEAEgAawwAAAMATABqDAAAAgAaAGwMAAACACgA6gwAAAQAQAAWAAQJ5gMfTQChAARpDAAAAQAGAGsMAAABAA4AagwAAAEADgBsDAAAAQAJABcAAgmRCFdNAF0AAmgMAAABAA4A6gwAAAEAHAAAAA==.',
So='Sorynia:BAAALgAECgUJDgAAAA==.Soul:BAAALgAECgEJAQAAAA==.Soulkid:BAAALgAECgQJBQAAAA==.',
St='Starta:BAACLgAFFH8KAAIbAAMJ5xmnMQD7AANoDAAABAA7AGkMAAADADwA6gwAAAMATgAbAAMJ5xmnMQD7AANoDAAABAA7AGkMAAADADwA6gwAAAMATgAuAAQKfxUAAhsACAmNIZgUACkCABsACAmNIZgUACkCAAAA.Startawar:BAABLgAECn8kAAILAAgJxyN4DACtAghoDAAABgBjAGkMAAAGAGEAawwAAAYAYQBqDAAABABcAGwMAAAEAGAAbQwAAAIANwDqDAAABQBiAG4MAAADAF8ACwAICccjeAwArQIIaAwAAAYAYwBpDAAABgBhAGsMAAAGAGEAagwAAAQAXABsDAAABABgAG0MAAACADcA6gwAAAUAYgBuDAAAAwBfAAAA.',
Su='Sukii:BAAALgAECgUJBgAAAA==.Sulfuricvein:BAAALgAECgMJBQAAAA==.',
['Sø']='Sømebody:BAAALgAECgMJAwAAAA==.',
Ti='Tiana:BAAALgAECgkJBAAAAA==.',
To='Totemdaddy:BAAALgAECgEJAQAAAA==.Totemicdidit:BAAALgADCgMJAwAAAA==.Totemstorm:BAAALgAECgcJBwAAAA==.',
Tr='Traumatic:BAABLgAECn8UAAIdAAcJjRj5LwDvAQdoDAAAAwBIAGkMAAAEAEUAawwAAAMAPwBqDAAAAwAfAGwMAAACADwA6gwAAAQASQBuDAAAAQAlAB0ABwmNGPkvAO8BB2gMAAADAEgAaQwAAAQARQBrDAAAAwA/AGoMAAADAB8AbAwAAAIAPADqDAAABABJAG4MAAABACUAAAA=.',
Tu='Tunny:BAAALgAECgYJCAAAAA==.Turnleft:BAABLgAECn8sAAIhAAgJcSV0AgBnAwhoDAAABwBjAGkMAAAHAGEAawwAAAYAYwBqDAAABgBiAGwMAAAGAGMAbQwAAAMAXQDqDAAABgBiAG4MAAADAE8AIQAICXEldAIAZwMIaAwAAAcAYwBpDAAABwBhAGsMAAAGAGMAagwAAAYAYgBsDAAABgBjAG0MAAADAF0A6gwAAAYAYgBuDAAAAwBPAAAA.',
Va='Vauntmonk:BAAALgADCgMJAwABLgAFFAQJCgAiAN4fAA==.',
Ve='Vercyv:BAAALgADCgkJEQAAAA==.Vevio:BAAALgAECgQJBAAAAA==.',
Vi='Video:BAAALgAECgEJAQAAAA==.Violet:BAABLgAECn8nAAIMAAkJWx2BDQCoAgloDAAABgBZAGkMAAAGAFgAawwAAAUAVwBqDAAABABZAGwMAAAEAFkAbQwAAAMASwDqDAAABgBbAG4MAAADAC4AbwwAAAIAIAAMAAkJWx2BDQCoAgloDAAABgBZAGkMAAAGAFgAawwAAAUAVwBqDAAABABZAGwMAAAEAFkAbQwAAAMASwDqDAAABgBbAG4MAAADAC4AbwwAAAIAIAAAAA==.Vishlock:BAABLgAECn8tAAMSAAkJ9xadAgAQAgloDAAABgBQAGkMAAAGADsAawwAAAYANwBqDAAABQA1AGwMAAAFAEsAbQwAAAQAGwDqDAAABwBMAG4MAAAEADQAbwwAAAIAKgASAAkJ9xadAgAQAgloDAAABQBQAGkMAAAGADsAawwAAAUANwBqDAAAAwA1AGwMAAAEAEsAbQwAAAIAGwDqDAAABQBMAG4MAAABADQAbwwAAAIAKgAKAAcJcA4LlAAwAQdoDAAAAQARAGsMAAABACAAagwAAAIACgBsDAAAAQBBAG0MAAACABEA6gwAAAIAQQBuDAAAAwAXAAAA.',
Vo='Voddie:BAABLgAECn8ZAAIDAAcJOAkONQDrAAdoDAAABQAdAGkMAAAFABQAawwAAAUAHgBqDAAAAwALAGwMAAADABUAbQwAAAEACQDqDAAAAwAeAAMABwk4CQ41AOsAB2gMAAAFAB0AaQwAAAUAFABrDAAABQAeAGoMAAADAAsAbAwAAAMAFQBtDAAAAQAJAOoMAAADAB4AAAA=.Votarick:BAAALgAECgEJAQAAAA==.',
Wa='Waban:BAAALgAECgcJEwAAAA==.Walmarthas:BAAALgAECgcJCwABLgAECggJGgAGAEwVAA==.Wapta:BAAALgAFFAEJAQABLgAFFAQJBAABAAAAAA==.',
Wi='Wizwiztheliz:BAAALgAECgYJDwAAAA==.',
Wo='Wolf:BAABLgAECn8bAAIjAAgJXQ6gGQB1AQhoDAAABgAwAGkMAAAFACcAawwAAAUAIABqDAAAAwAbAGwMAAACADEAbQwAAAEABwDqDAAABAA2AG4MAAABABkAIwAICV0OoBkAdQEIaAwAAAYAMABpDAAABQAnAGsMAAAFACAAagwAAAMAGwBsDAAAAgAxAG0MAAABAAcA6gwAAAQANgBuDAAAAQAZAAEuAAUUAQkBAAEAAAAA.Woof:BAAALgAECgIJAgAAAA==.',
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
