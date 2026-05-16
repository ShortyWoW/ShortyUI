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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Shaman-Elemental','Mage-Frost','Paladin-Holy','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Paladin-Protection','Warlock-Demonology','Paladin-Retribution','DeathKnight-Unholy','DeathKnight-Frost','Druid-Feral','Hunter-Survival','Rogue-Assassination','Monk-Windwalker','Warlock-Affliction','Warlock-Destruction','DemonHunter-Havoc','Priest-Holy','Priest-Shadow','Priest-Discipline','DeathKnight-Blood','Hunter-BeastMastery','Warrior-Fury','Druid-Guardian','DemonHunter-Devourer','Warrior-Arms','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Outlaw','Druid-Restoration','Warrior-Protection','Monk-Brewmaster',}
local provider = {region='US',realm='Coilfang',name='US',type='daily',zone=46,date='2026-05-14',data={Ae='Aendean:BAAALgAECgEJAQAAAA==.',
Am='Amethyne:BAAALgADCgMJAwAAAA==.',
An='Anabell:BAAALgAECgEJAQABLgAECgYJCAABAAAAAA==.',
Ar='Arckane:BAAALgAECgEJAQAAAA==.Arcueid:BAABLgAECn8uAAMCAAkJqSB6FQA4AgloDAAABQBQAGkMAAAFAFMAawwAAAgAWABqDAAABgBVAGwMAAAGAEkAbQwAAAMAOwDqDAAACQBZAG4MAAADAFwAbwwAAAEAYwACAAgJ5B96FQA4AghoDAAABQBQAGkMAAAFAFMAawwAAAgAWABqDAAABgBVAGwMAAAGAEkAbQwAAAMAOwDqDAAACQBZAG4MAAACAFwAAwACCRAZgkkApwACbgwAAAEAUwBvDAAAAQAtAAAA.',
As='Asmadeus:BAAALgAECgEJAQAAAA==.',
Ay='Ayda:BAABLgAECn88AAIEAAkJVyWEAgBiAwloDAAACABhAGkMAAAIAF8AawwAAAgAYQBqDAAABwBOAGwMAAAHAGMAbQwAAAYAWQDqDAAACABfAG4MAAAFAF4AbwwAAAMAXgAEAAkJVyWEAgBiAwloDAAACABhAGkMAAAIAF8AawwAAAgAYQBqDAAABwBOAGwMAAAHAGMAbQwAAAYAWQDqDAAACABfAG4MAAAFAF4AbwwAAAMAXgAAAA==.',
Ba='Bartholdson:BAAALgAECgYJEgAAAA==.',
Be='Bearlydidit:BAAALgADCgQJBAAAAA==.Beloc:BAAALgAECgcJAgAAAA==.Berzerkirz:BAAALgADCgYJBgAAAA==.',
Bl='Blacksnow:BAAALgADCgEJAQAAAA==.Blcksnowcrow:BAABLgAECn8dAAIFAAkJ8BmWDQBgAgloDAAABQBNAGkMAAAEAFkAawwAAAQAXABqDAAAAgAgAGwMAAADAFAAbQwAAAMAQwDqDAAABgBGAG4MAAABACkAbwwAAAEALwAFAAkJ8BmWDQBgAgloDAAABQBNAGkMAAAEAFkAawwAAAQAXABqDAAAAgAgAGwMAAADAFAAbQwAAAMAQwDqDAAABgBGAG4MAAABACkAbwwAAAEALwAAAA==.',
Bo='Bonfire:BAABLgAECn8kAAQGAAgJASMyCgBZAghoDAAABgBfAGkMAAAGAF8AawwAAAYAXQBqDAAABQBjAGwMAAAEAFUAbQwAAAIAUgDqDAAABgBdAG4MAAABAFEABgAICQEjMgoAWQIIaAwAAAQAXwBpDAAABABfAGsMAAAFAF0AagwAAAQAYwBsDAAAAwBVAG0MAAACAFIA6gwAAAUAXQBuDAAAAQBRAAcABQncIEoQAKsABWgMAAACAF0AaQwAAAEATABqDAAAAQBfAGwMAAABAEoA6gwAAAEAWwAIAAIJSgKGRABLAAJpDAAAAQAHAGsMAAABAAQAAS4ABRQECQgABAAZHAA=.Boochili:BAABLgAECn84AAIJAAkJuCYGAACLAwloDAAABwBjAGkMAAAHAGMAawwAAAcAYwBqDAAABwBjAGwMAAAHAGMAbQwAAAYAYwDqDAAABwBjAG4MAAAFAGMAbwwAAAMAXwAJAAkJuCYGAACLAwloDAAABwBjAGkMAAAHAGMAawwAAAcAYwBqDAAABwBjAGwMAAAHAGMAbQwAAAYAYwDqDAAABwBjAG4MAAAFAGMAbwwAAAMAXwAAAA==.',
Br='Bravebeard:BAAALgAECgUJBQAAAA==.Braveling:BAABLgAECn8YAAIKAAgJOQz+SQBnAQhoDAAABAAZAGkMAAAEACwAawwAAAQAGQBqDAAAAwAvAGwMAAADAC0AbQwAAAEAIADqDAAABAAaAG4MAAABABMACgAICTkM/kkAZwEIaAwAAAQAGQBpDAAABAAsAGsMAAAEABkAagwAAAMALwBsDAAAAwAtAG0MAAABACAA6gwAAAQAGgBuDAAAAQATAAAA.',
Bu='Bubblës:BAAALgAECgQJCAABLgAECggJIQAEAAgiAA==.',
Ca='Carezarsh:BAAALgADCgMJAQAAAA==.',
Ch='Charlie:BAACLgAFFH8SAAMLAAQJxyOTDQCGAQRoDAAABQBdAGkMAAAEAFoAawwAAAQAXwDqDAAABQBWAAsABAnHI5MNAIYBBGgMAAAFAF0AaQwAAAQAWgBrDAAAAwBfAOoMAAAFAFYACQABCUAjSAsAZAABawwAAAEAWgAuAAQKfzMAAwsACQnKJZYGAAIDAAsACQnKJZYGAAIDAAkAAwlgGLYtAFsAAAAA.Chicken:BAAALgAFFAEJAQAAAA==.',
Cr='Cruel:BAAALgADCgEJAQAAAA==.',
['Cä']='Cätîáñdrïà:BAABLgAECn9UAAMCAAkJlSBJAwA9AwloDAAACwBOAGkMAAAKAFcAawwAAAoAWgBqDAAACwBQAGwMAAAKAGMAbQwAAAgAUgDqDAAADQBaAG4MAAAHADoAbwwAAAQAUwACAAkJlSBJAwA9AwloDAAACgBOAGkMAAAIAFcAawwAAAgAWgBqDAAACQBQAGwMAAAJAGMAbQwAAAgAUgDqDAAADQBaAG4MAAAGADoAbwwAAAQAUwADAAYJdw5xNgDzAAZoDAAAAQAyAGkMAAACAB4AawwAAAIALwBqDAAAAgAzAGwMAAABABMAbgwAAAEAJQAAAA==.',
Da='Daniedk:BAABLgAECn8rAAIMAAgJvxMLPwCoAQhoDAAABgBDAGkMAAAHAC4AawwAAAYAHQBqDAAABwBAAGwMAAAFACsAbQwAAAMAIgDqDAAABQBDAG4MAAAEAEEADAAICb8TCz8AqAEIaAwAAAYAQwBpDAAABwAuAGsMAAAGAB0AagwAAAcAQABsDAAABQArAG0MAAADACIA6gwAAAUAQwBuDAAABABBAAAA.Daphanim:BAAALgADCgYJCgAAAA==.Darctotem:BAAALgAECgUJEAAAAA==.',
De='Deathtouch:BAACLgAFFH8HAAMMAAMJPhxgXgDtAANoDAAAAgBTAGkMAAADADcA6gwAAAIATQAMAAMJPhxgXgDtAANoDAAAAQBTAGkMAAACADcA6gwAAAIATQANAAIJSRAKCwCWAAJoDAAAAQAnAGkMAAABACsALgAECn8bAAMMAAgJRyMUGQBfAgAMAAgJxyIUGQBfAgANAAEJEh06GwBJAAAAAA==.Devona:BAABLgAECn8dAAMFAAgJ5RuHHADEAQhoDAAABgBBAGkMAAAFAFAAawwAAAUATQBqDAAAAwBNAGwMAAADAF8AbQwAAAEAHQDqDAAABQBYAG4MAAABADgABQAHCbQchxwAxAEHaAwAAAQAQQBpDAAABABQAGsMAAAEAE0AagwAAAIATQBsDAAAAgBfAG0MAAABAB0A6gwAAAQAWAALAAcJmwzAaQA6AQdoDAAAAgAkAGkMAAABAC4AawwAAAEAGABqDAAAAQAbAGwMAAABACgA6gwAAAEAGgBuDAAAAQATAAAA.',
Di='Didit:BAAALgADCgcJBwAAAA==.Dingledangle:BAABLgAECn8dAAIOAAgJxxI6CwCWAQhoDAAABQA4AGkMAAAFADwAawwAAAUANABqDAAABQA5AGwMAAACAAkAbQwAAAIALwDqDAAABAA+AG4MAAABADAADgAICccSOgsAlgEIaAwAAAUAOABpDAAABQA8AGsMAAAFADQAagwAAAUAOQBsDAAAAgAJAG0MAAACAC8A6gwAAAQAPgBuDAAAAQAwAAAA.',
Dj='Djindor:BAAALgADCgUJBQAAAA==.',
Dr='Draconix:BAAALgAECgQJBAABLgAECgYJBgABAAAAAA==.Dragonzordd:BAAALgADCgQJBQABLgAECgYJFAAPAAwiAA==.Dragooncrush:BAAALgADCgQJBAAAAA==.Dragoonnick:BAACLgAFFH8HAAIQAAMJSg4fBQDzAANoDAAABAAXAGkMAAACAFEA6gwAAAEABAAQAAMJSg4fBQDzAANoDAAABAAXAGkMAAACAFEA6gwAAAEABAAuAAQKfzwAAhAACQnSGwMDADkCABAACQnSGwMDADkCAAAA.Drazzy:BAAALgAECgIJAgAAAA==.',
Eg='Egg:BAAALgAECgYJBgABLgAECggJHQAGAMgPAA==.',
Es='Esh:BAAALgAECgcJDgAAAA==.',
Eu='Euphal:BAABLgAECn8nAAIKAAgJDBNhPQCPAQhoDAAABAA1AGkMAAAGAC0AawwAAAUAIQBqDAAAAwA1AGwMAAAHAEAAbQwAAAIAFwDqDAAABwBDAG4MAAAFADUACgAICQwTYT0AjwEIaAwAAAQANQBpDAAABgAtAGsMAAAFACEAagwAAAMANQBsDAAABwBAAG0MAAACABcA6gwAAAcAQwBuDAAABQA1AAAA.',
Ey='Eyekicku:BAABLgAECn8cAAIRAAgJdSCbBwB5AghoDAAABgBcAGkMAAAFAFoAawwAAAUAWQBqDAAAAwBaAGwMAAADAE4AbQwAAAEAQADqDAAABABUAG4MAAABAFEAEQAICXUgmwcAeQIIaAwAAAYAXABpDAAABQBaAGsMAAAFAFkAagwAAAMAWgBsDAAAAwBOAG0MAAABAEAA6gwAAAQAVABuDAAAAQBRAAAA.',
Fe='Feldana:BAAALgAECgQJBAAAAA==.Fenicon:BAAALgAECgQJBQAAAA==.',
Fi='Fitz:BAAALgAECgQJBAAAAA==.Fitzwell:BAAALgAECgQJBAAAAA==.',
Fu='Fuyu:BAAALgAECgQJBAAAAA==.Fuyuhex:BAAALgAFFAIJAwAAAA==.',
Gh='Ghost:BAAALgAECgMJBQAAAA==.',
Gr='Graycieden:BAAALgAECgYJBwAAAA==.',
Gu='Guldangit:BAACLgAFFH8hAAMKAAcJRxy2AQAmAgdoDAAABwBcAGkMAAAFAFsAawwAAAYAVQBqDAAABABLAGwMAAADADkAbQwAAAEAIgDqDAAABwBIAAoABwkaHLYBACYCB2gMAAAGAFwAaQwAAAQAWwBrDAAABQBSAGoMAAADAEQAbAwAAAMAOQBtDAAAAQAiAOoMAAAGAEgAEgAFCdUcvQAAfgEFaAwAAAEAPABpDAAAAQBSAGsMAAABAFUAagwAAAEASwDqDAAAAQBDAC4ABAp/MgAEEgAJCf8lGgAAdgMAEgAJCRMlGgAAdgMACgAJCQEjaggAPgMAEwAECY4iLhoAewEAAAA=.',
Ha='Hanora:BAAALgAECgUJBgAAAA==.',
He='Hellspawn:BAABLgAECn88AAIUAAkJyg9LDwC2AQloDAAACAA+AGkMAAAIADMAawwAAAgALABqDAAABwAbAGwMAAAHACUAbQwAAAYAGADqDAAACAApAG4MAAAFACQAbwwAAAMAGQAUAAkJyg9LDwC2AQloDAAACAA+AGkMAAAIADMAawwAAAgALABqDAAABwAbAGwMAAAHACUAbQwAAAYAGADqDAAACAApAG4MAAAFACQAbwwAAAMAGQAAAA==.',
Hh='Hhounow:BAAALgADCgYJBgAAAA==.',
Ho='Hojai:BAAALgADCgMJAwAAAA==.Holybeef:BAAALgAECgcJDQAAAA==.Holygrim:BAACLgAFFH8eAAIVAAcJOyQmAADeAgdoDAAABgBkAGkMAAAGAGMAawwAAAUAYgBqDAAABABhAGwMAAACAFEAbQwAAAEAVgDqDAAABgBVABUABwk7JCYAAN4CB2gMAAAGAGQAaQwAAAYAYwBrDAAABQBiAGoMAAAEAGEAbAwAAAIAUQBtDAAAAQBWAOoMAAAGAFUALgAECn8dAAMVAAgJYybgAQBXAwAVAAgJYybgAQBXAwAWAAEJPgneXgAzAAAAAA==.Holyloa:BAAALgAECgMJAwAAAA==.Holypablo:BAABLgAECn88AAQXAAkJPx8ZAwAqAwloDAAACABJAGkMAAAIAFoAawwAAAgAXgBqDAAABwBfAGwMAAAHAGEAbQwAAAYAVADqDAAACAA6AG4MAAAFAEIAbwwAAAMAOwAXAAkJPx8ZAwAqAwloDAAABABJAGkMAAAEAFoAawwAAAQAXgBqDAAABgBfAGwMAAAGAGEAbQwAAAYAVADqDAAABQA6AG4MAAAEAEIAbwwAAAMAOwAWAAcJehb2GQCTAQdoDAAAAwA1AGkMAAADAEIAawwAAAMARwBqDAAAAQA5AGwMAAABAEAA6gwAAAIAHwBuDAAAAQA6ABUABAmtC5VdALwABGgMAAABAA4AaQwAAAEAGABrDAAAAQAxAOoMAAABAB8AAAA=.Howii:BAABLgAECn8+AAIYAAkJlSWWAABcAwloDAAACQBbAGkMAAAIAGIAawwAAAgAYABqDAAABwBfAGwMAAAHAGEAbQwAAAYAYADqDAAACQBgAG4MAAAFAGAAbwwAAAMAXwAYAAkJlSWWAABcAwloDAAACQBbAGkMAAAIAGIAawwAAAgAYABqDAAABwBfAGwMAAAHAGEAbQwAAAYAYADqDAAACQBgAG4MAAAFAGAAbwwAAAMAXwAAAA==.',
Im='Imperator:BAAALgAECgQJBAAAAA==.',
In='Inchworm:BAAALgAECgYJBgAAAA==.',
Is='Isabellaah:BAABLgAECn8bAAIZAAcJ9xIZRgBfAQdoDAAABgA6AGkMAAAFAEYAawwAAAUAMABqDAAAAwAgAGwMAAADADwAbQwAAAEACQDqDAAABAAsABkABwn3EhlGAF8BB2gMAAAGADoAaQwAAAUARgBrDAAABQAwAGoMAAADACAAbAwAAAMAPABtDAAAAQAJAOoMAAAEACwAAAA=.',
Je='Jellyfïsh:BAAALgAECgUJCgAAAA==.Jeraziah:BAAALgAECgUJEQABLgAECgkJLgACAKkgAA==.',
Jo='Johnnyjr:BAABLgAECn8bAAIaAAkJex6SBQDAAgloDAAAAwBAAGkMAAADAGAAawwAAAMAUgBqDAAAAwAyAGwMAAADAFcAbQwAAAMAPwDqDAAAAwA7AG4MAAADAFsAbwwAAAMATwAaAAkJex6SBQDAAgloDAAAAwBAAGkMAAADAGAAawwAAAMAUgBqDAAAAwAyAGwMAAADAFcAbQwAAAMAPwDqDAAAAwA7AG4MAAADAFsAbwwAAAMATwAAAA==.',
Ke='Kelliz:BAAALgADCgcJCAAAAA==.',
Kh='Khaladin:BAAALgAECgYJEgAAAA==.',
La='Laggers:BAABLgAECn8jAAIbAAgJdxbCDgBrAQhoDAAABgA3AGkMAAAGAE4AawwAAAYARgBqDAAABQAwAGwMAAADADMAbQwAAAEAGgDqDAAABwBKAG4MAAABAC0AGwAICXcWwg4AawEIaAwAAAYANwBpDAAABgBOAGsMAAAGAEYAagwAAAUAMABsDAAAAwAzAG0MAAABABoA6gwAAAcASgBuDAAAAQAtAAAA.',
Li='Litbit:BAABLgAECn8XAAIEAAcJ5wNhogDrAAdoDAAABAALAGkMAAAEABAAawwAAAQABgBqDAAABAAGAGwMAAADAA4AbQwAAAEABgDqDAAAAwAEAAQABwnnA2GiAOsAB2gMAAAEAAsAaQwAAAQAEABrDAAABAAGAGoMAAAEAAYAbAwAAAMADgBtDAAAAQAGAOoMAAADAAQAAAA=.Litbitonme:BAAALgAECgMJBgAAAA==.Litt:BAAALgADCgkJCwAAAA==.Lizardwizard:BAAALgAECgEJAQAAAA==.',
Lo='Lockmantwo:BAAALgAECgcJAwAAAA==.Lostmoo:BAAALgAECgEJAQAAAA==.Lostunholy:BAABLgAECn8XAAIMAAcJhCDcMADgAQdoDAAABwBhAGkMAAAEAFIAawwAAAMAVwBqDAAAAgBaAGwMAAACAFMAbQwAAAEAOQDqDAAABABaAAwABwmEINwwAOABB2gMAAAHAGEAaQwAAAQAUgBrDAAAAwBXAGoMAAACAFoAbAwAAAIAUwBtDAAAAQA5AOoMAAAEAFoAAAA=.Lovebug:BAAALgADCgcJBwAAAA==.',
Lu='Lunaardris:BAAALgAECgQJBQAAAA==.',
Ly='Lynxe:BAAALgAECgYJBgAAAA==.',
Ma='Maggikal:BAABLgAECn8XAAIEAAYJtQyulgAAAQZoDAAABQA3AGkMAAAEABgAawwAAAQAIwBqDAAAAgAWAGwMAAACAAoA6gwAAAYAJAAEAAYJtQyulgAAAQZoDAAABQA3AGkMAAAEABgAawwAAAQAIwBqDAAAAgAWAGwMAAACAAoA6gwAAAYAJAAAAA==.',
Me='Megahottie:BAAALgADCgYJBgAAAA==.',
Mi='Mirant:BAAALgAECgUJDQAAAA==.',
Mo='Moretisha:BAAALgADCgYJBgAAAA==.',
Na='Nakwoo:BAAALgADCgMJAwAAAA==.',
Of='Of:BAAALgAECgEJAQAAAA==.',
On='One:BAAALgAECgEJAQAAAA==.',
Op='Opallea:BAABLgAECn8aAAMUAAkJWxugEQBRAgloDAAABABPAGkMAAAFAE4AawwAAAUASwBqDAAAAwBOAGwMAAACAEgAbQwAAAEARADqDAAABABKAG4MAAABAC4AbwwAAAEAQAAUAAkJWxugEQBRAgloDAAAAwBPAGkMAAAEAE4AawwAAAQASwBqDAAAAgBOAGwMAAACAEgAbQwAAAEARADqDAAABABKAG4MAAABAC4AbwwAAAEAQAAcAAQJ6gQCpwBpAARoDAAAAQAKAGkMAAABABIAawwAAAEACQBqDAAAAQAeAAAA.',
Pa='Pallyplay:BAAALgAECgEJAQAAAA==.',
Pb='Pballs:BAAALgADCgEJAQABLgAECgkJPAAXAD8fAA==.',
Pe='Periodic:BAACLgAFFH8OAAICAAQJKCNuCgCbAQRoDAAABQBaAGkMAAADAGAAawwAAAIAUQDqDAAABABbAAIABAkoI24KAJsBBGgMAAAFAFoAaQwAAAMAYABrDAAAAgBRAOoMAAAEAFsALgAECn8vAAICAAkJ5SP0AACZAwACAAkJ5SP0AACZAwAAAA==.',
Pl='Platen:BAABLgAECn8cAAIZAAgJlQ5FRQBiAQhoDAAABgAvAGkMAAAFACYAawwAAAUAKABqDAAAAwAwAGwMAAADAEwAbQwAAAEABQDqDAAABAAwAG4MAAABAAQAGQAICZUORUUAYgEIaAwAAAYALwBpDAAABQAmAGsMAAAFACgAagwAAAMAMABsDAAAAwBMAG0MAAABAAUA6gwAAAQAMABuDAAAAQAEAAAA.',
Po='Potter:BAABLgAECn88AAIEAAkJHh82EQCxAgloDAAACABUAGkMAAAIAEwAawwAAAgAUQBqDAAABwBBAGwMAAAHAF8AbQwAAAYASgDqDAAACABQAG4MAAAFAEcAbwwAAAMASAAEAAkJHh82EQCxAgloDAAACABUAGkMAAAIAEwAawwAAAgAUQBqDAAABwBBAGwMAAAHAF8AbQwAAAYASgDqDAAACABQAG4MAAAFAEcAbwwAAAMASAAAAA==.',
Ra='Raffa:BAABLgAECn8fAAIRAAcJFxxSIgDDAQdoDAAABABRAGkMAAADAC4AawwAAAQAJwBqDAAABQBUAGwMAAADAFgAbQwAAAIAUADqDAAACgBfABEABwkXHFIiAMMBB2gMAAAEAFEAaQwAAAMALgBrDAAABAAnAGoMAAAFAFQAbAwAAAMAWABtDAAAAgBQAOoMAAAKAF8AAAA=.Rakandei:BAAALgADCgMJAwAAAA==.Raptor:BAABLgAFFH8IAAIEAAQJGRy7HgB+AQRoDAAAAgBTAGkMAAACADsAawwAAAIAMADqDAAAAgBfAAQABAkZHLseAH4BBGgMAAACAFMAaQwAAAIAOwBrDAAAAgAwAOoMAAACAF8AAAA=.Rapunzel:BAAALgAECgkJBgAAAA==.Rataiga:BAAALgAECgYJEgAAAA==.',
Rh='Rheynah:BAABLgAECn8ZAAMdAAgJjQMzKgCsAAhoDAAABQAHAGkMAAAEABIAawwAAAQABABqDAAAAwAVAGwMAAADAA0AbQwAAAEACADqDAAABAAFAG4MAAABAAQAHQAICUkDMyoArAAIaAwAAAEABABpDAAAAQASAGsMAAABAAQAagwAAAEAFQBsDAAAAQANAG0MAAABAAgA6gwAAAEAAwBuDAAAAQAEABoABgkHA9hTAJEABmgMAAAEAAcAaQwAAAMADwBrDAAAAwADAGoMAAACAAMAbAwAAAIABwDqDAAAAwAFAAAA.',
Ri='Rimuna:BAAALgADCgUJBQAAAA==.Rinni:BAACLgAFFH8VAAIOAAYJAR+SAADMAQZoDAAABQBeAGkMAAAEAEkAawwAAAMAUgBqDAAAAgAgAGwMAAABADYA6gwAAAYAXQAOAAYJAR+SAADMAQZoDAAABQBeAGkMAAAEAEkAawwAAAMAUgBqDAAAAgAgAGwMAAABADYA6gwAAAYAXQAuAAQKfyYAAg4ACQkQJdwBAEUDAA4ACQkQJdwBAEUDAAAA.',
Ro='Rovintis:BAABLgAECn8uAAIdAAgJ0hiNCAD6AQhoDAAACABOAGkMAAAIAEAAawwAAAcATABqDAAABgBWAGwMAAAFAEMAbQwAAAMANgDqDAAABwBUAG4MAAACABMAHQAICdIYjQgA+gEIaAwAAAgATgBpDAAACABAAGsMAAAHAEwAagwAAAYAVgBsDAAABQBDAG0MAAADADYA6gwAAAcAVABuDAAAAgATAAAA.',
Ry='Rynne:BAAALgAECgcJEgAAAA==.',
Sa='Sansundertal:BAABLgAECn8wAAIIAAkJsSJ+AgBJAwloDAAABwBcAGkMAAAGAFEAawwAAAYAYQBqDAAABgBjAGwMAAAGAGAAbQwAAAQAWwDqDAAABwBjAG4MAAAEAFkAbwwAAAIAMgAIAAkJsSJ+AgBJAwloDAAABwBcAGkMAAAGAFEAawwAAAYAYQBqDAAABgBjAGwMAAAGAGAAbQwAAAQAWwDqDAAABwBjAG4MAAAEAFkAbwwAAAIAMgAAAA==.Sargeràs:BAAALgADCgYJBgABLgAECgMJAwABAAAAAA==.',
Se='Selissaroth:BAAALgAECgEJAQAAAA==.Sentinal:BAABLgAECn8kAAIYAAgJVRVqDwCtAQhoDAAABgBXAGkMAAAGAD0AawwAAAUAOwBqDAAABQBUAGwMAAAEAEMAbQwAAAIAEQDqDAAABgAyAG4MAAACACcAGAAICVUVag8ArQEIaAwAAAYAVwBpDAAABgA9AGsMAAAFADsAagwAAAUAVABsDAAABABDAG0MAAACABEA6gwAAAYAMgBuDAAAAgAnAAAA.Sentinäl:BAAALgADCgIJAgAAAA==.Sephiro:BAAALgAECgQJBgAAAA==.',
Sh='Shamu:BAACLgAFFH8GAAICAAIJvBV+NwCVAAJoDAAAAwAWAOoMAAADAFgAAgACCbwVfjcAlQACaAwAAAMAFgDqDAAAAwBYAC4ABAp/GAACAgAICb8VxDMAbgEAAgAICb8VxDMAbgEAAAA=.Shawner:BAAALgADCgMJAwAAAA==.Shy:BAAALgAECgUJBgAAAA==.',
Si='Silvertiger:BAABLgAECn87AAMPAAkJBh8/AwDLAgloDAAABwBYAGkMAAAIAFoAawwAAAgAUgBqDAAABwBGAGwMAAAHAFQAbQwAAAYAUADqDAAACAA1AG4MAAAFAFQAbwwAAAMARgAPAAkJBh8/AwDLAgloDAAABgBYAGkMAAAGAFoAawwAAAYAUgBqDAAABgBGAGwMAAAGAFQAbQwAAAUAUADqDAAABgA1AG4MAAAFAFQAbwwAAAMARgAeAAcJgg+dPABsAQdoDAAAAQAtAGkMAAACADMAawwAAAIAJABqDAAAAQASAGwMAAABACwAbQwAAAEAIADqDAAAAgAdAAAA.',
Sl='Slabbydabby:BAAALgAECgYJCAAAAA==.Sleeperbater:BAAALgADCgIJAgAAAA==.Sleeperdk:BAAALgAECgYJCwAAAA==.',
Sn='Snackyfraps:BAAALgADCgUJCAABLgAECgkJPAAXAD8fAA==.Sneaki:BAABLgAECn86AAQfAAkJKCRiAwDLAgloDAAACABjAGkMAAAIAF8AawwAAAgAXABqDAAABwBcAGwMAAAHAF0AbQwAAAUASADqDAAACABdAG4MAAAEAGEAbwwAAAMAYAAfAAkJqiJiAwDLAgloDAAABwBjAGkMAAAHAF8AawwAAAcAXABqDAAABgBcAGwMAAACAD8AbQwAAAQASADqDAAABwBdAG4MAAADAGEAbwwAAAMAYAAgAAgJ+xw7AgBPAghoDAAAAQBXAGkMAAABACsAawwAAAEARwBqDAAAAQBLAGwMAAABAF0AbQwAAAEAQQDqDAAAAQBPAG4MAAABAE4AEAABCecd6hgAVgABbAwAAAQATAAAAA==.Sniperanger:BAAALgADCgMJAwAAAA==.Snstr:BAABLgAECn8aAAQVAAYJbRfiLACTAQZoDAAABgBOAGkMAAAFAEgAawwAAAQATABqDAAAAwAaAGwMAAADACgA6gwAAAUAQAAVAAYJbRfiLACTAQZoDAAABQBOAGkMAAAEAEgAawwAAAMATABqDAAAAgAaAGwMAAACACgA6gwAAAQAQAAWAAQJ5gMhTQChAARpDAAAAQAGAGsMAAABAA4AagwAAAEADgBsDAAAAQAJABcAAgmRCFlNAF0AAmgMAAABAA4A6gwAAAEAHAAAAA==.',
So='Sorynia:BAABLgAECn8WAAIZAAgJnwaGUQA7AQhoDAAABAASAGkMAAAEABkAawwAAAQAGABqDAAABAAbAGwMAAABAAgAbQwAAAEABQDqDAAAAwALAG4MAAABABgAGQAICZ8GhlEAOwEIaAwAAAQAEgBpDAAABAAZAGsMAAAEABgAagwAAAQAGwBsDAAAAQAIAG0MAAABAAUA6gwAAAMACwBuDAAAAQAYAAAA.Soul:BAAALgAECgEJAQAAAA==.Soulkid:BAAALgAECgQJBQAAAA==.',
St='Starta:BAACLgAFFH8LAAIcAAMJ5xkgNgD2AANoDAAABAA7AGkMAAADADwA6gwAAAQATgAcAAMJ5xkgNgD2AANoDAAABAA7AGkMAAADADwA6gwAAAQATgAuAAQKfxsAAhwACAmNIZoZACQCABwACAmNIZoZACQCAAAA.Startawar:BAACLgAFFH8FAAILAAIJxhLAUAClAAJpDAAAAQAiAOoMAAAEAD0ACwACCcYSwFAApQACaQwAAAEAIgDqDAAABAA9AC4ABAp/JAACCwAICccjTxAAnQIACwAICccjTxAAnQIAAAA=.',
Su='Sukii:BAAALgAECgUJBgAAAA==.Sulfuricvein:BAAALgAECgcJCwAAAA==.',
['Sø']='Sømebody:BAAALgAECgMJAwAAAA==.',
Ti='Tiana:BAAALgAECgkJBAAAAA==.',
To='Totemdaddy:BAAALgAECgEJAQAAAA==.Totemicdidit:BAAALgADCgMJAwAAAA==.Totemstorm:BAAALgAECgcJBwAAAA==.',
Tr='Traumatic:BAABLgAECn8UAAIaAAcJjRj6LwDvAQdoDAAAAwBIAGkMAAAEAEUAawwAAAMAPwBqDAAAAwAfAGwMAAACADwA6gwAAAQASQBuDAAAAQAlABoABwmNGPovAO8BB2gMAAADAEgAaQwAAAQARQBrDAAAAwA/AGoMAAADAB8AbAwAAAIAPADqDAAABABJAG4MAAABACUAAAA=.',
Tu='Tunny:BAAALgAECgYJCAAAAA==.Turnleft:BAABLgAECn8sAAIhAAgJcSUAAwBfAwhoDAAABwBjAGkMAAAHAGEAawwAAAYAYwBqDAAABgBiAGwMAAAGAGMAbQwAAAMAXQDqDAAABgBiAG4MAAADAE8AIQAICXElAAMAXwMIaAwAAAcAYwBpDAAABwBhAGsMAAAGAGMAagwAAAYAYgBsDAAABgBjAG0MAAADAF0A6gwAAAYAYgBuDAAAAwBPAAAA.',
Va='Valerïan:BAAALgADCgEJAQABLgAECgcJDgABAAAAAA==.Vauntmonk:BAAALgADCgMJAwABLgAFFAQJDgAiAFIhAA==.',
Ve='Vercyv:BAAALgADCgkJEQAAAA==.Vevio:BAAALgAECgQJBAAAAA==.',
Vi='Video:BAAALgAECgEJAQAAAA==.Violet:BAABLgAECn8oAAIMAAkJWx2MEACeAgloDAAABgBZAGkMAAAGAFgAawwAAAUAVwBqDAAABABZAGwMAAAEAFkAbQwAAAMASwDqDAAABwBbAG4MAAADAC4AbwwAAAIAIAAMAAkJWx2MEACeAgloDAAABgBZAGkMAAAGAFgAawwAAAUAVwBqDAAABABZAGwMAAAEAFkAbQwAAAMASwDqDAAABwBbAG4MAAADAC4AbwwAAAIAIAAAAA==.Vishlock:BAABLgAECn8vAAMSAAkJgxnGAgAqAgloDAAABgBQAGkMAAAGADsAawwAAAYANwBqDAAABQA1AGwMAAAFAEsAbQwAAAQAGwDqDAAABwBMAG4MAAAFAFkAbwwAAAMAOQASAAkJgxnGAgAqAgloDAAABQBQAGkMAAAGADsAawwAAAUANwBqDAAAAwA1AGwMAAAEAEsAbQwAAAIAGwDqDAAABQBMAG4MAAACAFkAbwwAAAMAOQAKAAcJcA4OlAAwAQdoDAAAAQARAGsMAAABACAAagwAAAIACgBsDAAAAQBBAG0MAAACABEA6gwAAAIAQQBuDAAAAwAXAAAA.',
Vo='Voddie:BAABLgAECn8ZAAIDAAcJOAmmOwDcAAdoDAAABQAdAGkMAAAFABQAawwAAAUAHgBqDAAAAwALAGwMAAADABUAbQwAAAEACQDqDAAAAwAeAAMABwk4CaY7ANwAB2gMAAAFAB0AaQwAAAUAFABrDAAABQAeAGoMAAADAAsAbAwAAAMAFQBtDAAAAQAJAOoMAAADAB4AAAA=.Votarick:BAAALgAECgEJAQAAAA==.',
Wa='Waban:BAAALgAECgcJEwAAAA==.Walmarthas:BAAALgAECgcJDAABLgAECggJGgAGAEwVAA==.Wapta:BAAALgAFFAEJAQABLgAFFAQJCAAEABkcAA==.',
Wi='Wizwiztheliz:BAAALgAECgYJDwAAAA==.',
Wo='Wolf:BAABLgAECn8bAAIjAAgJXQ6jHQBoAQhoDAAABgAwAGkMAAAFACcAawwAAAUAIABqDAAAAwAbAGwMAAACADEAbQwAAAEABwDqDAAABAA2AG4MAAABABkAIwAICV0Oox0AaAEIaAwAAAYAMABpDAAABQAnAGsMAAAFACAAagwAAAMAGwBsDAAAAgAxAG0MAAABAAcA6gwAAAQANgBuDAAAAQAZAAEuAAUUAQkBAAEAAAAA.Woof:BAAALgAECgIJAgAAAA==.',
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
