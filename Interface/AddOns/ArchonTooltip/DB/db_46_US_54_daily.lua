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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Shaman-Elemental','Mage-Frost','Warrior-Fury','Hunter-BeastMastery','Paladin-Holy','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Paladin-Protection','Warlock-Demonology','Paladin-Retribution','DeathKnight-Unholy','DeathKnight-Frost','Druid-Feral','Hunter-Survival','Rogue-Assassination','Monk-Windwalker','Warlock-Affliction','Warlock-Destruction','DemonHunter-Havoc','Priest-Holy','Priest-Shadow','Priest-Discipline','DeathKnight-Blood','Druid-Guardian','DemonHunter-Devourer','Warrior-Arms','Shaman-Enhancement','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Outlaw','Druid-Restoration','Druid-Balance','Warrior-Protection','Monk-Brewmaster',}
local provider = {region='US',realm='Coilfang',name='US',type='daily',zone=46,date='2026-05-20',data={Ae='Aendean:BAAALgAECgEJAQAAAA==.',
Am='Amethyne:BAAALgADCgMJAwAAAA==.',
An='Anabell:BAAALgAECgIJAwABLgAECgYJCAABAAAAAA==.',
Ar='Arckane:BAAALgAECgEJAQAAAA==.Arcueid:BAABLgAECn8zAAMCAAkJqSAeFwBdAgloDAAABgBQAGkMAAAGAFMAawwAAAkAWABqDAAABwBVAGwMAAAGAEkAbQwAAAMAOwDqDAAACgBZAG4MAAADAFwAbwwAAAEAYwACAAgJ5B8eFwBdAghoDAAABgBQAGkMAAAGAFMAawwAAAkAWABqDAAABwBVAGwMAAAGAEkAbQwAAAMAOwDqDAAACgBZAG4MAAACAFwAAwACCRAZDFoAmAACbgwAAAEAUwBvDAAAAQAtAAAA.',
As='Asmadeus:BAAALgAECgYJBwAAAA==.',
Ay='Ayda:BAABLgAECn9FAAIEAAkJXCVtAwBgAwloDAAACQBhAGkMAAAJAGAAawwAAAkAYQBqDAAACABOAGwMAAAIAGMAbQwAAAcAWQDqDAAACQBfAG4MAAAGAF4AbwwAAAQAXgAEAAkJXCVtAwBgAwloDAAACQBhAGkMAAAJAGAAawwAAAkAYQBqDAAACABOAGwMAAAIAGMAbQwAAAcAWQDqDAAACQBfAG4MAAAGAF4AbwwAAAQAXgAAAA==.',
Ba='Bajabeachboy:BAAALgAFFAIJBAABLgAFFAMJDgAFAEofAA==.Bartholdson:BAABLgAECn8aAAIGAAgJ2hi6KgD8AQhoDAAABQBAAGkMAAAEAFIAawwAAAQATABqDAAABAA9AGwMAAADADIAbQwAAAEALADqDAAABAA2AG4MAAABAEgABgAICdoYuioA/AEIaAwAAAUAQABpDAAABABSAGsMAAAEAEwAagwAAAQAPQBsDAAAAwAyAG0MAAABACwA6gwAAAQANgBuDAAAAQBIAAAA.',
Be='Bearlydidit:BAAALgADCgQJBAAAAA==.Beloc:BAAALgAECgcJAgAAAA==.Berzerkirz:BAAALgADCgYJBgAAAA==.',
Bl='Blacksnow:BAAALgADCgEJAQAAAA==.Blcksnowcrow:BAABLgAECn8kAAIHAAkJfxxMCADWAgloDAAABgBbAGkMAAAFAFkAawwAAAYAXABqDAAABABEAGwMAAADAFAAbQwAAAMAQwDqDAAABwBOAG4MAAABACkAbwwAAAEALwAHAAkJfxxMCADWAgloDAAABgBbAGkMAAAFAFkAawwAAAYAXABqDAAABABEAGwMAAADAFAAbQwAAAMAQwDqDAAABwBOAG4MAAABACkAbwwAAAEALwAAAA==.',
Bo='Bonfire:BAACLgAFFH8HAAIIAAUJvRyjEgBtAQVoDAAAAQA+AGkMAAACAF8AawwAAAEAMABqDAAAAQBaAOoMAAACAFgACAAFCb0coxIAbQEFaAwAAAEAPgBpDAAAAgBfAGsMAAABADAAagwAAAEAWgDqDAAAAgBYAC4ABAp/JgAECAAJCW8j3QgAowIACAAJCe0i3QgAowIACQAGCW4hlQ0ADAEACgACCUoChkQASwAAAS4ABRQFCQkABAAZHAA=.Boochili:BAABLgAECn9BAAILAAkJ7iYEAACVAwloDAAACABjAGkMAAAIAGMAawwAAAgAYwBqDAAACABjAGwMAAAIAGMAbQwAAAcAYwDqDAAACABjAG4MAAAGAGMAbwwAAAQAYwALAAkJ7iYEAACVAwloDAAACABjAGkMAAAIAGMAawwAAAgAYwBqDAAACABjAGwMAAAIAGMAbQwAAAcAYwDqDAAACABjAG4MAAAGAGMAbwwAAAQAYwAAAA==.',
Br='Bravebeard:BAAALgAECgUJCQAAAA==.Braveling:BAABLgAECn8ZAAIMAAgJOQzqWwBrAQhoDAAABAAZAGkMAAAEACwAawwAAAQAGQBqDAAAAwAvAGwMAAADAC0AbQwAAAEAIADqDAAABAAaAG4MAAACABMADAAICTkM6lsAawEIaAwAAAQAGQBpDAAABAAsAGsMAAAEABkAagwAAAMALwBsDAAAAwAtAG0MAAABACAA6gwAAAQAGgBuDAAAAgATAAAA.',
Bu='Bubblës:BAAALgAECgQJCAABLgAECggJKQAEAAgiAA==.',
Ca='Carezarsh:BAAALgADCgMJAQAAAA==.',
Ch='Charlie:BAACLgAFFH8WAAMNAAUJxyPnDgCTAQVoDAAABgBdAGkMAAAFAFoAawwAAAUAXwBqDAAAAQBGAOoMAAAFAFYADQAFCccj5w4AkwEFaAwAAAYAXQBpDAAABQBaAGsMAAAEAF8AagwAAAEARgDqDAAABQBWAAsAAQlAIxUNAGMAAWsMAAABAFoALgAECn83AAMNAAkJziUfCABTAwANAAkJziUfCABTAwALAAUJjxSqLACBAAAAAA==.Chicken:BAAALgAFFAMJBAAAAA==.',
Cr='Cruel:BAAALgADCgEJAQAAAA==.',
['Cä']='Cätîáñdrïà:BAACLgAFFH8GAAICAAQJuBNpIgAWAQRoDAAAAQAmAGkMAAADAEUAawwAAAEAHwDqDAAAAQA+AAIABAm4E2kiABYBBGgMAAABACYAaQwAAAMARQBrDAAAAQAfAOoMAAABAD4ALgAECn9dAAMCAAkJuyC8BAA4AwACAAkJuyC8BAA4AwADAAYJdw7lQwDmAAAAAA==.',
Da='Dagron:BAAALgAFFAIJAgAAAA==.Daniedk:BAABLgAECn8sAAIOAAgJvxM2UwCgAQhoDAAABgBDAGkMAAAHAC4AawwAAAYAHQBqDAAABwBAAGwMAAAFACsAbQwAAAMAIgDqDAAABgBDAG4MAAAEAEEADgAICb8TNlMAoAEIaAwAAAYAQwBpDAAABwAuAGsMAAAGAB0AagwAAAcAQABsDAAABQArAG0MAAADACIA6gwAAAYAQwBuDAAABABBAAAA.Daphanim:BAAALgADCgYJCgAAAA==.Darctotem:BAAALgAECgYJEQAAAA==.',
De='Deathtouch:BAACLgAFFH8HAAMOAAMJPhxOcADoAANoDAAAAgBTAGkMAAADADcA6gwAAAIATQAOAAMJPhxOcADoAANoDAAAAQBTAGkMAAACADcA6gwAAAIATQAPAAIJSRAWEACNAAJoDAAAAQAnAGkMAAABACsALgAECn8bAAMOAAgJRyMvJgBAAgAOAAgJxyIvJgBAAgAPAAEJEh2SJABCAAAAAA==.Devona:BAABLgAECn8eAAMHAAgJuh1jIwC3AQhoDAAABgBBAGkMAAAFAFAAawwAAAUATQBqDAAAAwBNAGwMAAADAF8AbQwAAAEAHQDqDAAABQBYAG4MAAACAF4ABwAHCbQcYyMAtwEHaAwAAAQAQQBpDAAABABQAGsMAAAEAE0AagwAAAIATQBsDAAAAgBfAG0MAAABAB0A6gwAAAQAWAANAAcJjBDBcABjAQdoDAAAAgAkAGkMAAABAC4AawwAAAEAGABqDAAAAQAbAGwMAAABACgA6gwAAAEAGgBuDAAAAgBPAAAA.',
Di='Didit:BAAALgADCgcJBwAAAA==.Dingledangle:BAABLgAECn8hAAIQAAgJlRQfDACzAQhoDAAABgBOAGkMAAAGADwAawwAAAYAPgBqDAAABQA5AGwMAAACAAkAbQwAAAIALwDqDAAABQA+AG4MAAABADAAEAAICZUUHwwAswEIaAwAAAYATgBpDAAABgA8AGsMAAAGAD4AagwAAAUAOQBsDAAAAgAJAG0MAAACAC8A6gwAAAUAPgBuDAAAAQAwAAAA.',
Dj='Djindor:BAAALgADCgUJBQAAAA==.',
Dr='Draconix:BAAALgAECgQJBAABLgAECgYJBgABAAAAAA==.Dragonzordd:BAAALgADCgQJBQABLgAECgYJFAARAAwiAA==.Dragooncrush:BAAALgADCgcJCwAAAA==.Dragoonnick:BAACLgAFFH8KAAISAAMJExRbBQD8AANoDAAABQBDAGkMAAADAFEA6gwAAAIABAASAAMJExRbBQD8AANoDAAABQBDAGkMAAADAFEA6gwAAAIABAAuAAQKfz0AAhIACQnSGxYEAHQCABIACQnSGxYEAHQCAAAA.Drazzy:BAAALgAECgIJAgAAAA==.',
Eg='Egg:BAAALgAFFAEJAQAAAA==.',
Es='Esh:BAAALgAECgcJDgAAAA==.',
Eu='Euphal:BAABLgAECn8oAAIMAAkJKxLVOQDQAQloDAAABAA1AGkMAAAGAC0AawwAAAUAIQBqDAAAAwA1AGwMAAAHAEAAbQwAAAIAFwDqDAAABwBDAG4MAAAFADUAbwwAAAEAHgAMAAkJKxLVOQDQAQloDAAABAA1AGkMAAAGAC0AawwAAAUAIQBqDAAAAwA1AGwMAAAHAEAAbQwAAAIAFwDqDAAABwBDAG4MAAAFADUAbwwAAAEAHgAAAA==.',
Ey='Eyekicku:BAABLgAECn8cAAITAAgJdSAkCwBhAghoDAAABgBcAGkMAAAFAFoAawwAAAUAWQBqDAAAAwBaAGwMAAADAE4AbQwAAAEAQADqDAAABABUAG4MAAABAFEAEwAICXUgJAsAYQIIaAwAAAYAXABpDAAABQBaAGsMAAAFAFkAagwAAAMAWgBsDAAAAwBOAG0MAAABAEAA6gwAAAQAVABuDAAAAQBRAAAA.',
Fe='Feldana:BAAALgAECgQJBAAAAA==.Fenicon:BAAALgAECgQJBQAAAA==.',
Fi='Fitz:BAAALgAECgQJBAAAAA==.Fitzwell:BAAALgAECgQJBAAAAA==.',
Fu='Fuyu:BAAALgAECgQJBAAAAA==.Fuyuhex:BAAALgAFFAIJAwAAAA==.',
Gh='Ghost:BAAALgAECgMJBQAAAA==.',
Gi='Gibbousbogg:BAAALgADCgEJAQAAAA==.',
Gr='Graycieden:BAAALgAECgYJBwAAAA==.',
Gu='Guldangit:BAACLgAFFH8iAAMMAAgJSxyEAgBmAghoDAAABwBcAGkMAAAFAFsAawwAAAYAVQBqDAAABABLAGwMAAADADkAbQwAAAEAIgDqDAAABwBIAG4MAAABAEgADAAICSQchAIAZgIIaAwAAAYAXABpDAAABABbAGsMAAAFAFIAagwAAAMARABsDAAAAwA5AG0MAAABACIA6gwAAAYASABuDAAAAQBIABQABQnVHEQBAG0BBWgMAAABADwAaQwAAAEAUgBrDAAAAQBVAGoMAAABAEsA6gwAAAEAQwAuAAQKfzIABBQACQn/JTgAAFcDABQACQkTJTgAAFcDAAwACQkBI2oIAD4DABUABAmOIi4aAHsBAAAA.',
Ha='Hanora:BAAALgAECgUJBgAAAA==.',
He='Hellspawn:BAABLgAECn9FAAIWAAkJyg/aEwCyAQloDAAACQA+AGkMAAAJADMAawwAAAkALABqDAAACAAbAGwMAAAIACUAbQwAAAcAGADqDAAACQApAG4MAAAGACQAbwwAAAQAGQAWAAkJyg/aEwCyAQloDAAACQA+AGkMAAAJADMAawwAAAkALABqDAAACAAbAGwMAAAIACUAbQwAAAcAGADqDAAACQApAG4MAAAGACQAbwwAAAQAGQAAAA==.',
Hh='Hhounow:BAAALgADCgcJDAAAAA==.',
Ho='Hojai:BAAALgADCgMJAwAAAA==.Holybeef:BAAALgAECgcJDQAAAA==.Holygrim:BAACLgAFFH8eAAIXAAcJOyQaAABvAgdoDAAABgBkAGkMAAAGAGMAawwAAAUAYgBqDAAABABhAGwMAAACAFEAbQwAAAEAVgDqDAAABgBVABcABwk7JBoAAG8CB2gMAAAGAGQAaQwAAAYAYwBrDAAABQBiAGoMAAAEAGEAbAwAAAIAUQBtDAAAAQBWAOoMAAAGAFUALgAECn8dAAMXAAgJYybgAQBXAwAXAAgJYybgAQBXAwAYAAEJPgmlbgAuAAAAAA==.Holyloa:BAAALgAECgMJAwAAAA==.Holypablo:BAABLgAECn9FAAQZAAkJPx/GBAAXAwloDAAACQBJAGkMAAAJAFoAawwAAAkAXgBqDAAACABfAGwMAAAIAGEAbQwAAAcAVADqDAAACQA6AG4MAAAGAEIAbwwAAAQAOwAZAAkJPx/GBAAXAwloDAAABABJAGkMAAAEAFoAawwAAAQAXgBqDAAABgBfAGwMAAAHAGEAbQwAAAcAVADqDAAABQA6AG4MAAAEAEIAbwwAAAQAOwAYAAcJ0RmlGADPAQdoDAAABAA2AGkMAAAEAEcAawwAAAQARwBqDAAAAgA6AGwMAAABAEAA6gwAAAMAKABuDAAAAgBeABcABAmtC5VdALwABGgMAAABAA4AaQwAAAEAGABrDAAAAQAxAOoMAAABAB8AAAA=.Howii:BAABLgAECn9HAAIaAAkJoCXHAABVAwloDAAACgBbAGkMAAAJAGIAawwAAAkAYABqDAAACABfAGwMAAAIAGEAbQwAAAcAYADqDAAACgBgAG4MAAAGAGAAbwwAAAQAXwAaAAkJoCXHAABVAwloDAAACgBbAGkMAAAJAGIAawwAAAkAYABqDAAACABfAGwMAAAIAGEAbQwAAAcAYADqDAAACgBgAG4MAAAGAGAAbwwAAAQAXwAAAA==.',
Im='Imperator:BAAALgAECgQJBAAAAA==.',
In='Inchworm:BAAALgAECgYJBgAAAA==.',
Is='Isabellaah:BAABLgAECn8bAAIGAAcJ9xJZXABWAQdoDAAABgA6AGkMAAAFAEYAawwAAAUAMABqDAAAAwAgAGwMAAADADwAbQwAAAEACQDqDAAABAAsAAYABwn3EllcAFYBB2gMAAAGADoAaQwAAAUARgBrDAAABQAwAGoMAAADACAAbAwAAAMAPABtDAAAAQAJAOoMAAAEACwAAAA=.',
Je='Jeraziah:BAAALgAECgUJEQABLgAECgkJMwACAKkgAA==.',
Jo='Johnnyjr:BAABLgAECn8kAAIFAAkJAiENBAADAwloDAAABABLAGkMAAAEAGAAawwAAAQAVwBqDAAABAAyAGwMAAAEAFcAbQwAAAQAPwDqDAAABABRAG4MAAAEAF4AbwwAAAQAWQAFAAkJAiENBAADAwloDAAABABLAGkMAAAEAGAAawwAAAQAVwBqDAAABAAyAGwMAAAEAFcAbQwAAAQAPwDqDAAABABRAG4MAAAEAF4AbwwAAAQAWQAAAA==.',
Ke='Kelliz:BAAALgADCgcJCAAAAA==.',
Kh='Khaladin:BAAALgAECgYJEgAAAA==.',
La='Laggers:BAABLgAECn8jAAIbAAgJdxZtFABiAQhoDAAABgA3AGkMAAAGAE4AawwAAAYARgBqDAAABQAwAGwMAAADADMAbQwAAAEAGgDqDAAABwBKAG4MAAABAC0AGwAICXcWbRQAYgEIaAwAAAYANwBpDAAABgBOAGsMAAAGAEYAagwAAAUAMABsDAAAAwAzAG0MAAABABoA6gwAAAcASgBuDAAAAQAtAAAA.',
Li='Litbit:BAABLgAECn8eAAIEAAcJCASjuQDtAAdoDAAABQALAGkMAAAFABAAawwAAAUABgBqDAAABQAQAGwMAAAEAA4AbQwAAAIABwDqDAAABAAFAAQABwkIBKO5AO0AB2gMAAAFAAsAaQwAAAUAEABrDAAABQAGAGoMAAAFABAAbAwAAAQADgBtDAAAAgAHAOoMAAAEAAUAAAA=.Litbitonme:BAAALgAECgMJBgAAAA==.Litllit:BAAALgAECgMJAwAAAA==.Litt:BAAALgADCgkJCwAAAA==.Lizardwizard:BAAALgAECgEJAQAAAA==.',
Lo='Lockmantwo:BAAALgAECgcJAwAAAA==.Lostmoo:BAAALgAECgEJAQAAAA==.Lostunholy:BAABLgAECn8fAAIOAAgJah8RIwBPAghoDAAACABhAGkMAAAFAFIAawwAAAQAVwBqDAAAAwBaAGwMAAADAFMAbQwAAAIASQDqDAAABQBaAG4MAAABAC4ADgAICWofESMATwIIaAwAAAgAYQBpDAAABQBSAGsMAAAEAFcAagwAAAMAWgBsDAAAAwBTAG0MAAACAEkA6gwAAAUAWgBuDAAAAQAuAAAA.Lovebug:BAAALgADCgcJBwAAAA==.',
Lu='Lunaardris:BAAALgAECgQJBQAAAA==.',
Ly='Lynxe:BAAALgAECgYJBgAAAA==.',
Ma='Maggikal:BAABLgAECn8YAAIEAAcJYw2xjwAzAQdoDAAABQA3AGkMAAAEABgAawwAAAQAIwBqDAAAAgAWAGwMAAACAAoA6gwAAAYAJABuDAAAAQAqAAQABwljDbGPADMBB2gMAAAFADcAaQwAAAQAGABrDAAABAAjAGoMAAACABYAbAwAAAIACgDqDAAABgAkAG4MAAABACoAAAA=.',
Me='Megahottie:BAAALgADCgYJBgAAAA==.',
Mi='Mirant:BAAALgAECgUJDwAAAA==.',
Mo='Moretisha:BAAALgADCgYJBgAAAA==.',
['Mâ']='Mâchine:BAAALgADCgIJAgABLgAECggJFAAcAKIcAA==.',
Na='Nakwoo:BAAALgADCgMJAwAAAA==.',
Of='Of:BAAALgAECgEJAgAAAA==.',
On='One:BAAALgAECgEJAQAAAA==.',
Op='Opallea:BAABLgAECn8aAAMWAAkJWxugEQBRAgloDAAABABPAGkMAAAFAE4AawwAAAUASwBqDAAAAwBOAGwMAAACAEgAbQwAAAEARADqDAAABABKAG4MAAABAC4AbwwAAAEAQAAWAAkJWxugEQBRAgloDAAAAwBPAGkMAAAEAE4AawwAAAQASwBqDAAAAgBOAGwMAAACAEgAbQwAAAEARADqDAAABABKAG4MAAABAC4AbwwAAAEAQAAcAAQJ6gQ4wQBoAARoDAAAAQAKAGkMAAABABIAawwAAAEACQBqDAAAAQAeAAAA.',
Pa='Pallyplay:BAAALgAECgEJAQAAAA==.',
Pb='Pballs:BAAALgADCgEJAQABLgAECgkJRQAZAD8fAA==.',
Pe='Periodic:BAACLgAFFH8OAAICAAQJKCPcDgCWAQRoDAAABQBaAGkMAAADAGAAawwAAAIAUQDqDAAABABbAAIABAkoI9wOAJYBBGgMAAAFAFoAaQwAAAMAYABrDAAAAgBRAOoMAAAEAFsALgAECn8vAAICAAkJ5SP0AACZAwACAAkJ5SP0AACZAwAAAA==.',
Pl='Platen:BAABLgAECn8dAAIGAAgJzBAMTgB8AQhoDAAABgAvAGkMAAAFACYAawwAAAUAKABqDAAAAwAwAGwMAAADAEwAbQwAAAEABQDqDAAABAAwAG4MAAACACsABgAICcwQDE4AfAEIaAwAAAYALwBpDAAABQAmAGsMAAAFACgAagwAAAMAMABsDAAAAwBMAG0MAAABAAUA6gwAAAQAMABuDAAAAgArAAAA.',
Po='Potter:BAABLgAECn9FAAIEAAkJbB+yEgDHAgloDAAACQBUAGkMAAAJAEwAawwAAAkAUgBqDAAACABBAGwMAAAIAF8AbQwAAAcASgDqDAAACQBQAG4MAAAGAEwAbwwAAAQASAAEAAkJbB+yEgDHAgloDAAACQBUAGkMAAAJAEwAawwAAAkAUgBqDAAACABBAGwMAAAIAF8AbQwAAAcASgDqDAAACQBQAG4MAAAGAEwAbwwAAAQASAAAAA==.',
Ra='Raffa:BAABLgAECn8jAAITAAcJhx7NEgD3AQdoDAAABQBWAGkMAAAEAE4AawwAAAUAJwBqDAAABQBUAGwMAAADAFgAbQwAAAIAUADqDAAACwBfABMABwmHHs0SAPcBB2gMAAAFAFYAaQwAAAQATgBrDAAABQAnAGoMAAAFAFQAbAwAAAMAWABtDAAAAgBQAOoMAAALAF8AAAA=.Rakandei:BAAALgADCgMJAwAAAA==.Raptor:BAABLgAFFH8JAAIEAAUJGRyBKgBtAQVoDAAAAgBTAGkMAAACADsAawwAAAIAMABqDAAAAQADAOoMAAACAF8ABAAFCRkcgSoAbQEFaAwAAAIAUwBpDAAAAgA7AGsMAAACADAAagwAAAEAAwDqDAAAAgBfAAAA.Rapunzel:BAAALgAECgkJBgAAAA==.Rataiga:BAAALgAECgYJEgAAAA==.',
Rh='Rheynah:BAABLgAECn8aAAMdAAgJ8AMONAC2AAhoDAAABQAHAGkMAAAEABIAawwAAAQABABqDAAAAwAVAGwMAAADAA0AbQwAAAEACADqDAAABAAFAG4MAAACAAsAHQAICasDDjQAtgAIaAwAAAEABABpDAAAAQASAGsMAAABAAQAagwAAAEAFQBsDAAAAQANAG0MAAABAAgA6gwAAAEAAwBuDAAAAgALAAUABgkHA0tjAIwABmgMAAAEAAcAaQwAAAMADwBrDAAAAwADAGoMAAACAAMAbAwAAAIABwDqDAAAAwAFAAAA.',
Ri='Rimuna:BAAALgADCgUJBQAAAA==.Rinni:BAACLgAFFH8VAAIQAAYJAR9KAADyAQZoDAAABQBeAGkMAAAEAEkAawwAAAMAUgBqDAAAAgAgAGwMAAABADYA6gwAAAYAXQAQAAYJAR9KAADyAQZoDAAABQBeAGkMAAAEAEkAawwAAAMAUgBqDAAAAgAgAGwMAAABADYA6gwAAAYAXQAuAAQKfy0AAhAACQkQJdwAADwDABAACQkQJdwAADwDAAAA.',
Ro='Rovintis:BAABLgAECn81AAIdAAgJvhkyCgASAghoDAAACQBTAGkMAAAJAEsAawwAAAgATABqDAAABwBWAGwMAAAGAEQAbQwAAAQANgDqDAAACABUAG4MAAACABMAHQAICb4ZMgoAEgIIaAwAAAkAUwBpDAAACQBLAGsMAAAIAEwAagwAAAcAVgBsDAAABgBEAG0MAAAEADYA6gwAAAgAVABuDAAAAgATAAAA.',
Ry='Rynne:BAABLgAECn8UAAQCAAcJ1hGyPAB7AQdoDAAAAwA5AGkMAAAEACcAawwAAAMASQBqDAAAAwA7AGwMAAADADcAbQwAAAEABwBuDAAAAwAaAAIABwnWEbI8AHsBB2gMAAABADkAaQwAAAEAJwBrDAAAAQBJAGoMAAABADsAbAwAAAEANwBtDAAAAQAHAG4MAAABABoAHgAGCYsIARwACgEGaAwAAAIAGABpDAAAAwAWAGsMAAACABsAagwAAAIAGQBsDAAAAgAQAG4MAAABABEAAwABCWcDMZUAHgABbgwAAAEACAAAAA==.',
Sa='Sansundertal:BAABLgAECn8wAAIKAAkJsSJ+AgBJAwloDAAABwBcAGkMAAAGAFEAawwAAAYAYQBqDAAABgBjAGwMAAAGAGAAbQwAAAQAWwDqDAAABwBjAG4MAAAEAFkAbwwAAAIAMgAKAAkJsSJ+AgBJAwloDAAABwBcAGkMAAAGAFEAawwAAAYAYQBqDAAABgBjAGwMAAAGAGAAbQwAAAQAWwDqDAAABwBjAG4MAAAEAFkAbwwAAAIAMgAAAA==.Sargeràs:BAAALgADCgcJDAABLgAECgMJAwABAAAAAA==.',
Se='Selissaroth:BAAALgAECgEJAQAAAA==.Sentinal:BAABLgAECn8sAAIaAAgJchZhEgCrAQhoDAAABwBXAGkMAAAHAD0AawwAAAYAOwBqDAAABgBUAGwMAAAFAEMAbQwAAAMAHQDqDAAABwA5AG4MAAADACcAGgAICXIWYRIAqwEIaAwAAAcAVwBpDAAABwA9AGsMAAAGADsAagwAAAYAVABsDAAABQBDAG0MAAADAB0A6gwAAAcAOQBuDAAAAwAnAAAA.Sentinäl:BAAALgADCgIJAgAAAA==.Sephiro:BAAALgAECgQJBgAAAA==.',
Sh='Shamu:BAACLgAFFH8IAAICAAMJ9BAaMgDTAANoDAAABAAWAGkMAAABABIA6gwAAAMAWAACAAMJ9BAaMgDTAANoDAAABAAWAGkMAAABABIA6gwAAAMAWAAuAAQKfxoAAgIACQkNFTg1AJ4BAAIACQkNFTg1AJ4BAAAA.Shawner:BAAALgADCgMJAwAAAA==.Shy:BAAALgAECgUJBgAAAA==.',
Si='Silvertiger:BAABLgAECn9EAAMRAAkJ3h/NAwDYAgloDAAACABYAGkMAAAJAFoAawwAAAkAUgBqDAAACABGAGwMAAAIAFQAbQwAAAcAUwDqDAAACQBEAG4MAAAGAFQAbwwAAAQARgARAAkJ3h/NAwDYAgloDAAABwBYAGkMAAAHAFoAawwAAAcAUgBqDAAABwBGAGwMAAAHAFQAbQwAAAYAUwDqDAAABwBEAG4MAAAGAFQAbwwAAAQARgAfAAcJgg+dPABsAQdoDAAAAQAtAGkMAAACADMAawwAAAIAJABqDAAAAQASAGwMAAABACwAbQwAAAEAIADqDAAAAgAdAAAA.',
Sl='Slabbydabby:BAAALgAECgYJCAAAAA==.Sleeperbater:BAAALgADCgIJAgAAAA==.Sleeperdk:BAAALgAECgYJCwAAAA==.',
Sn='Snackyfraps:BAAALgADCgUJCAABLgAECgkJRQAZAD8fAA==.Sneaki:BAABLgAECn9DAAQgAAkJdyVIAwDzAgloDAAACQBjAGkMAAAJAF8AawwAAAkAXABqDAAACABcAGwMAAAIAF0AbQwAAAYAYADqDAAACQBdAG4MAAAFAGMAbwwAAAQAYAAgAAkJ+SNIAwDzAgloDAAACABjAGkMAAAIAF8AawwAAAgAXABqDAAABwBcAGwMAAACAD8AbQwAAAUAYADqDAAACABdAG4MAAAEAGMAbwwAAAQAYAAhAAgJ+xxlAwA5AghoDAAAAQBXAGkMAAABACsAawwAAAEARwBqDAAAAQBLAGwMAAABAF0AbQwAAAEAQQDqDAAAAQBPAG4MAAABAE4AEgABCbEjHhkAagABbAwAAAUAWwAAAA==.Sniperanger:BAAALgADCgMJAwAAAA==.Snstr:BAABLgAECn8aAAQXAAYJbRfiLACTAQZoDAAABgBOAGkMAAAFAEgAawwAAAQATABqDAAAAwAaAGwMAAADACgA6gwAAAUAQAAXAAYJbRfiLACTAQZoDAAABQBOAGkMAAAEAEgAawwAAAMATABqDAAAAgAaAGwMAAACACgA6gwAAAQAQAAYAAQJ5gMhTQChAARpDAAAAQAGAGsMAAABAA4AagwAAAEADgBsDAAAAQAJABkAAgmRCFlNAF0AAmgMAAABAA4A6gwAAAEAHAAAAA==.',
So='Sorynia:BAABLgAECn8XAAIGAAgJnwaHaAA2AQhoDAAABAASAGkMAAAEABkAawwAAAQAGABqDAAABAAbAGwMAAABAAgAbQwAAAEABQDqDAAABAALAG4MAAABABgABgAICZ8Gh2gANgEIaAwAAAQAEgBpDAAABAAZAGsMAAAEABgAagwAAAQAGwBsDAAAAQAIAG0MAAABAAUA6gwAAAQACwBuDAAAAQAYAAAA.Soul:BAAALgAECgEJAQAAAA==.Soulkid:BAAALgAECgQJBQAAAA==.',
St='Starta:BAACLgAFFH8LAAIcAAMJ5xmXPwDwAANoDAAABAA7AGkMAAADADwA6gwAAAQATgAcAAMJ5xmXPwDwAANoDAAABAA7AGkMAAADADwA6gwAAAQATgAuAAQKfxsAAhwACAmNITIjABsCABwACAmNITIjABsCAAAA.Startawar:BAACLgAFFH8FAAINAAIJxhLCYgCbAAJpDAAAAQAiAOoMAAAEAD0ADQACCcYSwmIAmwACaQwAAAEAIgDqDAAABAA9AC4ABAp/JAACDQAICccjLBYA5AIADQAICccjLBYA5AIAAAA=.',
Su='Sukii:BAAALgAECgUJBgAAAA==.Sulfuricvein:BAAALgAFFAEJAQAAAA==.',
['Sø']='Sømebody:BAAALgAECgMJAwAAAA==.',
Ti='Tiana:BAAALgAECgkJBAAAAA==.',
To='Totemdaddy:BAAALgAECgEJAQAAAA==.Totemicdidit:BAAALgADCgMJAwAAAA==.Totemstorm:BAAALgAECgcJBwAAAA==.',
Tr='Traumatic:BAABLgAECn8UAAIFAAcJjRj6LwDvAQdoDAAAAwBIAGkMAAAEAEUAawwAAAMAPwBqDAAAAwAfAGwMAAACADwA6gwAAAQASQBuDAAAAQAlAAUABwmNGPovAO8BB2gMAAADAEgAaQwAAAQARQBrDAAAAwA/AGoMAAADAB8AbAwAAAIAPADqDAAABABJAG4MAAABACUAAAA=.',
Tu='Tunny:BAAALgAECgYJCAAAAA==.Turnleft:BAABLgAECn8uAAMiAAkJYyMCAgCbAwloDAAABwBjAGkMAAAHAGEAawwAAAYAYwBqDAAABgBiAGwMAAAGAGMAbQwAAAMAXQDqDAAABwBiAG4MAAADAE8AbwwAAAEAMAAiAAkJYyMCAgCbAwloDAAABwBjAGkMAAAHAGEAawwAAAYAYwBqDAAABgBiAGwMAAAGAGMAbQwAAAMAXQDqDAAABgBiAG4MAAADAE8AbwwAAAEAMAAjAAEJgh4AAAAAAAHqDAAAAQBOAAAA.',
Va='Valerïan:BAAALgADCgEJAQABLgAECgYJBQABAAAAAA==.Vauntmonk:BAAALgADCgMJAwABLgAFFAQJEQAkAFYhAA==.',
Ve='Vercyv:BAAALgADCgkJEQAAAA==.Vevio:BAAALgAECgQJBAAAAA==.',
Vi='Video:BAAALgAECgEJAQAAAA==.Violet:BAABLgAECn8tAAIOAAkJOh5xDwDJAgloDAAACABfAGkMAAAHAF8AawwAAAYAXABqDAAABQBZAGwMAAAEAFkAbQwAAAMASwDqDAAABwBbAG4MAAADAC4AbwwAAAIAIAAOAAkJOh5xDwDJAgloDAAACABfAGkMAAAHAF8AawwAAAYAXABqDAAABQBZAGwMAAAEAFkAbQwAAAMASwDqDAAABwBbAG4MAAADAC4AbwwAAAIAIAAAAA==.Vishlock:BAABLgAECn8xAAMUAAkJgxl5BAAPAgloDAAABgBQAGkMAAAGADsAawwAAAYANwBqDAAABQA1AGwMAAAFAEsAbQwAAAQAGwDqDAAABwBMAG4MAAAGAFkAbwwAAAQAOQAUAAkJgxl5BAAPAgloDAAABQBQAGkMAAAGADsAawwAAAUANwBqDAAAAwA1AGwMAAAEAEsAbQwAAAIAGwDqDAAABQBMAG4MAAADAFkAbwwAAAMAOQAMAAgJ8w4OlAAwAQhoDAAAAQARAGsMAAABACAAagwAAAIACgBsDAAAAQBBAG0MAAACABEA6gwAAAIAQQBuDAAAAwAXAG8MAAABAC4AAAA=.',
Vo='Voddie:BAABLgAECn8aAAIDAAgJpAz/MgAyAQhoDAAABQAdAGkMAAAFABQAawwAAAUAHgBqDAAAAwALAGwMAAADABUAbQwAAAEACQDqDAAAAwAeAG4MAAABAFQAAwAICaQM/zIAMgEIaAwAAAUAHQBpDAAABQAUAGsMAAAFAB4AagwAAAMACwBsDAAAAwAVAG0MAAABAAkA6gwAAAMAHgBuDAAAAQBUAAAA.Votarick:BAAALgAECgEJAQAAAA==.',
Wa='Waban:BAAALgAECgcJEwAAAA==.Walmarthas:BAAALgAECgcJDQABLgAECggJGwAIAEwVAA==.Wapta:BAAALgAFFAEJAQABLgAFFAUJCQAEABkcAA==.',
Wi='Wizwiztheliz:BAAALgAECgYJDwAAAA==.',
Wo='Wolf:BAABLgAECn8cAAIlAAgJOhBxIgBvAQhoDAAABgAwAGkMAAAFACcAawwAAAUAIABqDAAAAwAbAGwMAAACADEAbQwAAAEABwDqDAAABAA2AG4MAAACADoAJQAICToQcSIAbwEIaAwAAAYAMABpDAAABQAnAGsMAAAFACAAagwAAAMAGwBsDAAAAgAxAG0MAAABAAcA6gwAAAQANgBuDAAAAgA6AAEuAAUUAwkEAAEAAAAA.Woof:BAAALgAECgIJAgAAAA==.',
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
