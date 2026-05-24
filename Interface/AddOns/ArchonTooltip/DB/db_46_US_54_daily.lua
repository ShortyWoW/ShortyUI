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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Shaman-Elemental','Mage-Frost','Warrior-Fury','Hunter-BeastMastery','Paladin-Holy','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Paladin-Protection','Warlock-Demonology','Paladin-Retribution','DeathKnight-Unholy','DeathKnight-Frost','Druid-Feral','Hunter-Survival','Rogue-Assassination','DemonHunter-Devourer','Monk-Windwalker','Warlock-Affliction','Warlock-Destruction','DemonHunter-Havoc','Priest-Holy','Priest-Shadow','Priest-Discipline','DeathKnight-Blood','Druid-Guardian','Mage-Fire','Warrior-Arms','Shaman-Enhancement','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Outlaw','Druid-Restoration','Druid-Balance','Warrior-Protection','Monk-Brewmaster',}
local provider = {region='US',realm='Coilfang',name='US',type='daily',zone=46,date='2026-05-24',data={Ae='Aendean:BAAALgAECgQJBAAAAA==.',
Am='Amethyne:BAAALgADCgMJAwAAAA==.',
An='Anabell:BAAALgAECgIJAwABLgAECgYJCAABAAAAAA==.',
Ar='Arckane:BAAALgAECgEJAQAAAA==.Arcueid:BAABLgAECn80AAMCAAkJqCAeFwBdAgloDAAABwBQAGkMAAAGAFMAawwAAAkAWABqDAAABwBVAGwMAAAGAEkAbQwAAAMAOwDqDAAACgBZAG4MAAADAFwAbwwAAAEAYwACAAgJ4x8eFwBdAghoDAAABwBQAGkMAAAGAFMAawwAAAkAWABqDAAABwBVAGwMAAAGAEkAbQwAAAMAOwDqDAAACgBZAG4MAAACAFwAAwACCRAZ+F8AlgACbgwAAAEAUwBvDAAAAQAtAAAA.',
As='Asmadeus:BAAALgAECgYJBwAAAA==.',
Ay='Ayda:BAABLgAECn9FAAIEAAkJXyU9BABbAwloDAAACQBhAGkMAAAJAGAAawwAAAkAYQBqDAAACABOAGwMAAAIAGMAbQwAAAcAWgDqDAAACQBfAG4MAAAGAF4AbwwAAAQAXgAEAAkJXyU9BABbAwloDAAACQBhAGkMAAAJAGAAawwAAAkAYQBqDAAACABOAGwMAAAIAGMAbQwAAAcAWgDqDAAACQBfAG4MAAAGAF4AbwwAAAQAXgAAAA==.',
Ba='Bajabeachboy:BAAALgAFFAIJBAABLgAFFAMJDgAFAEofAA==.Bartholdson:BAABLgAECn8aAAIGAAgJ2hjlLwD0AQhoDAAABQBAAGkMAAAEAFIAawwAAAQATABqDAAABAA9AGwMAAADADIAbQwAAAEALADqDAAABAA2AG4MAAABAEgABgAICdoY5S8A9AEIaAwAAAUAQABpDAAABABSAGsMAAAEAEwAagwAAAQAPQBsDAAAAwAyAG0MAAABACwA6gwAAAQANgBuDAAAAQBIAAAA.',
Be='Bearlydidit:BAAALgADCgQJBAAAAA==.Beloc:BAAALgAECgcJAgAAAA==.Berzerkirz:BAAALgADCgYJBgAAAA==.',
Bl='Blacksnow:BAAALgADCgEJAQAAAA==.Blcksnowcrow:BAABLgAECn8kAAIHAAkJfxxZCQDRAgloDAAABgBbAGkMAAAFAFkAawwAAAYAXABqDAAABABEAGwMAAADAFAAbQwAAAMAQwDqDAAABwBOAG4MAAABACkAbwwAAAEALwAHAAkJfxxZCQDRAgloDAAABgBbAGkMAAAFAFkAawwAAAYAXABqDAAABABEAGwMAAADAFAAbQwAAAMAQwDqDAAABwBOAG4MAAABACkAbwwAAAEALwAAAA==.',
Bo='Bonfire:BAACLgAFFH8HAAIIAAUJvRyGFQBiAQVoDAAAAQA+AGkMAAACAF8AawwAAAEAMABqDAAAAQBaAOoMAAACAFgACAAFCb0chhUAYgEFaAwAAAEAPgBpDAAAAgBfAGsMAAABADAAagwAAAEAWgDqDAAAAgBYAC4ABAp/JgAECAAJCW8j9AkAnwIACAAJCe0i9AkAnwIACQAGCW4heQ4ACAEACgACCUoChkQASwAAAS4ABRQFCQkABAAZHAA=.Boochili:BAABLgAECn9BAAILAAkJ7yYHAACWAwloDAAACABjAGkMAAAIAGMAawwAAAgAYwBqDAAACABjAGwMAAAIAGMAbQwAAAcAYwDqDAAACABjAG4MAAAGAGMAbwwAAAQAYwALAAkJ7yYHAACWAwloDAAACABjAGkMAAAIAGMAawwAAAgAYwBqDAAACABjAGwMAAAIAGMAbQwAAAcAYwDqDAAACABjAG4MAAAGAGMAbwwAAAQAYwAAAA==.',
Br='Bravebeard:BAAALgAFFAMJAwAAAA==.Braveling:BAABLgAECn8fAAIMAAkJ9A72OgDYAQloDAAABQAZAGkMAAAFACwAawwAAAUAGwBqDAAAAwAvAGwMAAADAC0AbQwAAAEAIADqDAAABQAjAG4MAAADAEgAbwwAAAEAFgAMAAkJ9A72OgDYAQloDAAABQAZAGkMAAAFACwAawwAAAUAGwBqDAAAAwAvAGwMAAADAC0AbQwAAAEAIADqDAAABQAjAG4MAAADAEgAbwwAAAEAFgAAAA==.',
Bu='Bubblës:BAAALgAECgQJCAABLgAECgkJMAAEAJgiAA==.',
Ca='Carezarsh:BAAALgADCgMJAQAAAA==.',
Ch='Charlie:BAACLgAFFH8XAAMNAAYJ3CLpBwDrAQZoDAAABgBdAGkMAAAFAFoAawwAAAUAXwBqDAAAAQBGAGwMAAABAE8A6gwAAAUAVgANAAYJ3CLpBwDrAQZoDAAABgBdAGkMAAAFAFoAawwAAAQAXwBqDAAAAQBGAGwMAAABAE8A6gwAAAUAVgALAAEJQCOWDgBhAAFrDAAAAQBaAC4ABAp/OAADDQAJCc4lHwgAUwMADQAJCc4lHwgAUwMACwAFCc4Zax8A7AAAAAA=.Chicken:BAAALgAFFAMJBAAAAA==.',
Cr='Cruel:BAAALgADCgEJAQAAAA==.',
['Cä']='Cätîáñdrïà:BAACLgAFFH8JAAICAAQJuhekIAAxAQRoDAAAAgBPAGkMAAAEAEUAawwAAAEAHwDqDAAAAgA+AAIABAm6F6QgADEBBGgMAAACAE8AaQwAAAQARQBrDAAAAQAfAOoMAAACAD4ALgAECn9dAAMCAAkJuyC6BQAzAwACAAkJuyC6BQAzAwADAAYJdw62SADkAAAAAA==.',
Da='Dagron:BAAALgAFFAIJAgAAAA==.Daniedk:BAABLgAECn8uAAIOAAgJvhOhWwCUAQhoDAAABwBDAGkMAAAHAC4AawwAAAYAHQBqDAAABwBAAGwMAAAFACsAbQwAAAMAIgDqDAAABgBDAG4MAAAFAEEADgAICb4ToVsAlAEIaAwAAAcAQwBpDAAABwAuAGsMAAAGAB0AagwAAAcAQABsDAAABQArAG0MAAADACIA6gwAAAYAQwBuDAAABQBBAAAA.Daphanim:BAAALgADCgYJCgAAAA==.Darctotem:BAAALgAECgYJEQAAAA==.',
De='Deathtouch:BAACLgAFFH8HAAMOAAMJPhxrfQDcAANoDAAAAgBTAGkMAAADADcA6gwAAAIATQAOAAMJPhxrfQDcAANoDAAAAQBTAGkMAAACADcA6gwAAAIATQAPAAIJSRDAEwCLAAJoDAAAAQAnAGkMAAABACsALgAECn8bAAMOAAgJSSPRKgA1AgAOAAgJyiLRKgA1AgAPAAEJEh2AKABBAAAAAA==.Devona:BAABLgAECn8kAAMHAAkJZR3yHQDvAQloDAAABwBBAGkMAAAGAFAAawwAAAYATQBqDAAAAwBNAGwMAAADAF8AbQwAAAEAHQDqDAAABgBYAG4MAAADAF4AbwwAAAEARAAHAAcJtBzyHQDvAQdoDAAABQBBAGkMAAAFAFAAawwAAAUATQBqDAAAAgBNAGwMAAACAF8AbQwAAAEAHQDqDAAABQBYAA0ACAnTD8JcAJsBCGgMAAACACQAaQwAAAEALgBrDAAAAQAYAGoMAAABABsAbAwAAAEAKADqDAAAAQAaAG4MAAADAE8AbwwAAAEAHQAAAA==.',
Di='Didit:BAAALgADCgcJBwAAAA==.Dingledangle:BAABLgAECn8iAAIQAAgJlBQuDQCyAQhoDAAABgBOAGkMAAAGADwAawwAAAYAPgBqDAAABQA5AGwMAAACAAkAbQwAAAIALwDqDAAABQA+AG4MAAACADAAEAAICZQULg0AsgEIaAwAAAYATgBpDAAABgA8AGsMAAAGAD4AagwAAAUAOQBsDAAAAgAJAG0MAAACAC8A6gwAAAUAPgBuDAAAAgAwAAAA.',
Dj='Djindor:BAAALgADCgUJBQAAAA==.',
Dr='Draconix:BAAALgAECgQJBAABLgAECgYJBgABAAAAAA==.Dragonzordd:BAAALgADCgQJBQABLgAECgYJFQARAAwiAA==.Dragooncrush:BAAALgADCgcJCwAAAA==.Dragoonnick:BAACLgAFFH8LAAISAAQJcxK/AwBJAQRoDAAABQBDAGkMAAADAFEAawwAAAEAIgDqDAAAAgAEABIABAlzEr8DAEkBBGgMAAAFAEMAaQwAAAMAUQBrDAAAAQAiAOoMAAACAAQALgAECn89AAISAAkJ0hsWBAB0AgASAAkJ0hsWBAB0AgAAAA==.Drazzy:BAAALgAECgIJAgAAAA==.',
Eg='Egg:BAAALgAFFAEJAQABLgAFFAYJFwATAKcTAA==.',
Es='Esh:BAAALgAECgcJDgAAAA==.',
Eu='Euphal:BAABLgAECn8oAAIMAAkJLBLNPgDLAQloDAAABAA1AGkMAAAGAC0AawwAAAUAIQBqDAAAAwA1AGwMAAAHAEAAbQwAAAIAFwDqDAAABwBDAG4MAAAFADUAbwwAAAEAHgAMAAkJLBLNPgDLAQloDAAABAA1AGkMAAAGAC0AawwAAAUAIQBqDAAAAwA1AGwMAAAHAEAAbQwAAAIAFwDqDAAABwBDAG4MAAAFADUAbwwAAAEAHgAAAA==.',
Ey='Eyekicku:BAABLgAECn8iAAIUAAkJrx+GBgDEAgloDAAABwBcAGkMAAAGAFoAawwAAAYAWQBqDAAAAwBaAGwMAAADAE4AbQwAAAEAQADqDAAABQBZAG4MAAACAFoAbwwAAAEANQAUAAkJrx+GBgDEAgloDAAABwBcAGkMAAAGAFoAawwAAAYAWQBqDAAAAwBaAGwMAAADAE4AbQwAAAEAQADqDAAABQBZAG4MAAACAFoAbwwAAAEANQAAAA==.',
Fe='Feldana:BAAALgAECgQJBAAAAA==.Fenicon:BAAALgAECgQJBQAAAA==.',
Fi='Fitz:BAAALgAECgQJBAAAAA==.Fitzwell:BAAALgAECgUJCAAAAA==.',
Fu='Fuyu:BAAALgAECgQJBAAAAA==.Fuyuhex:BAAALgAFFAIJAwAAAA==.',
Gh='Ghost:BAAALgAECgMJBQAAAA==.',
Gi='Gibbousbogg:BAAALgADCgEJAQAAAA==.',
Gr='Graycieden:BAAALgAECgYJCQAAAA==.',
Gu='Guldangit:BAACLgAFFH8iAAMMAAgJWxy2AQAmAghoDAAABwBcAGkMAAAFAFsAawwAAAYAVQBqDAAABABLAGwMAAADADkAbQwAAAEAIwDqDAAABwBIAG4MAAABAEgADAAICTQctgEAJgIIaAwAAAYAXABpDAAABABbAGsMAAAFAFIAagwAAAMARABsDAAAAwA5AG0MAAABACMA6gwAAAYASABuDAAAAQBIABUABQnVHMwBAGcBBWgMAAABADwAaQwAAAEAUgBrDAAAAQBVAGoMAAABAEsA6gwAAAEAQwAuAAQKfzIABBUACQn/JUcAAE8DABUACQkSJUcAAE8DAAwACQkBI2oIAD4DABYABAmOIi4aAHsBAAAA.',
Ha='Hanora:BAAALgAECgUJBgAAAA==.',
He='Hellspawn:BAABLgAECn9FAAIXAAkJyg9EFgCjAQloDAAACQA+AGkMAAAJADMAawwAAAkALABqDAAACAAbAGwMAAAIACUAbQwAAAcAGADqDAAACQApAG4MAAAGACQAbwwAAAQAGQAXAAkJyg9EFgCjAQloDAAACQA+AGkMAAAJADMAawwAAAkALABqDAAACAAbAGwMAAAIACUAbQwAAAcAGADqDAAACQApAG4MAAAGACQAbwwAAAQAGQAAAA==.',
Hh='Hhounow:BAAALgADCgcJDAAAAA==.',
Ho='Hojai:BAAALgADCgMJAwAAAA==.Holybeef:BAAALgAECgcJDQAAAA==.Holygrim:BAACLgAFFH8kAAIYAAgJGSQQAABIAwhoDAAABwBkAGkMAAAHAGMAawwAAAYAYgBqDAAABQBhAGwMAAACAFEAbQwAAAEAVwDqDAAABwBiAG4MAAABAE0AGAAICRkkEAAASAMIaAwAAAcAZABpDAAABwBjAGsMAAAGAGIAagwAAAUAYQBsDAAAAgBRAG0MAAABAFcA6gwAAAcAYgBuDAAAAQBNAC4ABAp/HQADGAAICWMm4AEAVwMAGAAICWMm4AEAVwMAGQABCT4JKXUALgAAAAA=.Holyloa:BAAALgAECgMJAwAAAA==.Holypablo:BAABLgAECn9FAAQaAAkJPx9pBQASAwloDAAACQBJAGkMAAAJAFoAawwAAAkAXgBqDAAACABfAGwMAAAIAGEAbQwAAAcAVADqDAAACQA6AG4MAAAGAEIAbwwAAAQAOwAaAAkJPx9pBQASAwloDAAABABJAGkMAAAEAFoAawwAAAQAXgBqDAAABgBfAGwMAAAHAGEAbQwAAAcAVADqDAAABQA6AG4MAAAEAEIAbwwAAAQAOwAZAAcJ0RnhGgDKAQdoDAAABAA2AGkMAAAEAEcAawwAAAQARwBqDAAAAgA6AGwMAAABAEAA6gwAAAMAKABuDAAAAgBeABgABAmtC5VdALwABGgMAAABAA4AaQwAAAEAGABrDAAAAQAxAOoMAAABAB8AAAA=.Howii:BAABLgAECn9HAAIbAAkJnSX3AABPAwloDAAACgBbAGkMAAAJAGIAawwAAAkAYABqDAAACABfAGwMAAAIAGEAbQwAAAcAYADqDAAACgBgAG4MAAAGAGAAbwwAAAQAXwAbAAkJnSX3AABPAwloDAAACgBbAGkMAAAJAGIAawwAAAkAYABqDAAACABfAGwMAAAIAGEAbQwAAAcAYADqDAAACgBgAG4MAAAGAGAAbwwAAAQAXwAAAA==.',
Im='Imperator:BAAALgAECgQJBAAAAA==.',
In='Inchworm:BAAALgAECgYJBgAAAA==.',
Is='Isabellaah:BAABLgAECn8hAAIGAAkJZBWvJgAbAgloDAAABwA7AGkMAAAGAEYAawwAAAYAPwBqDAAAAwAgAGwMAAADADwAbQwAAAEACQDqDAAABQAsAG4MAAABAFAAbwwAAAEAMQAGAAkJZBWvJgAbAgloDAAABwA7AGkMAAAGAEYAawwAAAYAPwBqDAAAAwAgAGwMAAADADwAbQwAAAEACQDqDAAABQAsAG4MAAABAFAAbwwAAAEAMQAAAA==.',
Je='Jeraziah:BAAALgAECgUJEQABLgAECgkJNAACAKggAA==.',
Jo='Johnnyjr:BAABLgAECn8kAAIFAAkJASH4BAD3AgloDAAABABLAGkMAAAEAGAAawwAAAQAVwBqDAAABAAyAGwMAAAEAFcAbQwAAAQAPwDqDAAABABRAG4MAAAEAF4AbwwAAAQAWQAFAAkJASH4BAD3AgloDAAABABLAGkMAAAEAGAAawwAAAQAVwBqDAAABAAyAGwMAAAEAFcAbQwAAAQAPwDqDAAABABRAG4MAAAEAF4AbwwAAAQAWQAAAA==.',
Ke='Kelliz:BAAALgADCgcJCAAAAA==.',
Kh='Khaladin:BAAALgAECgYJEgAAAA==.',
La='Laggers:BAABLgAECn8jAAIcAAgJdxYiFwBdAQhoDAAABgA3AGkMAAAGAE4AawwAAAYARgBqDAAABQAwAGwMAAADADMAbQwAAAEAGgDqDAAABwBKAG4MAAABAC0AHAAICXcWIhcAXQEIaAwAAAYANwBpDAAABgBOAGsMAAAGAEYAagwAAAUAMABsDAAAAwAzAG0MAAABABoA6gwAAAcASgBuDAAAAQAtAAAA.',
Le='Lean:BAAALgAECgYJBgABLgAFFAUJCQAEABkcAA==.',
Li='Litbit:BAABLgAECn8fAAIEAAgJ1wOErQANAQhoDAAABQALAGkMAAAFABAAawwAAAUABgBqDAAABQAQAGwMAAAEAA4AbQwAAAIABwDqDAAABAAFAG4MAAABAAYABAAICdcDhK0ADQEIaAwAAAUACwBpDAAABQAQAGsMAAAFAAYAagwAAAUAEABsDAAABAAOAG0MAAACAAcA6gwAAAQABQBuDAAAAQAGAAAA.Litbitonme:BAAALgAECgQJCgAAAA==.Litllit:BAAALgAECgMJAwAAAA==.Litt:BAAALgADCgkJCwAAAA==.Lizardwizard:BAAALgAECgEJAQAAAA==.',
Lo='Lockmantwo:BAAALgAECgcJAwAAAA==.Lostmoo:BAAALgAECgEJAQAAAA==.Lostunholy:BAABLgAECn8fAAIOAAgJax//JgBGAghoDAAACABhAGkMAAAFAFIAawwAAAQAVwBqDAAAAwBaAGwMAAADAFMAbQwAAAIASQDqDAAABQBaAG4MAAABAC4ADgAICWsf/yYARgIIaAwAAAgAYQBpDAAABQBSAGsMAAAEAFcAagwAAAMAWgBsDAAAAwBTAG0MAAACAEkA6gwAAAUAWgBuDAAAAQAuAAAA.Lovebug:BAAALgADCgcJBwAAAA==.',
Lu='Lunaardris:BAAALgAECgQJBQAAAA==.',
Ly='Lynxe:BAAALgAECgYJBgAAAA==.',
Ma='Maggikal:BAABLgAECn8gAAMEAAgJIxAoXwCoAQhoDAAABgA3AGkMAAAFAEUAawwAAAUALQBqDAAAAwAXAGwMAAACAAoA6gwAAAgAKABuDAAAAgAqAG8MAAABABcABAAICSMQKF8AqAEIaAwAAAYANwBpDAAABQBFAGsMAAAFAC0AagwAAAMAFwBsDAAAAgAKAOoMAAAHACgAbgwAAAIAKgBvDAAAAQAXAB0AAQkIDIMPADMAAeoMAAABAB4AAAA=.',
Me='Megahottie:BAAALgAECgEJAQAAAA==.',
Mi='Mirant:BAAALgAECgUJDwAAAA==.',
Mo='Moretisha:BAAALgADCgYJBgAAAA==.',
['Mâ']='Mâchine:BAAALgAFFAIJAgABLgAFFAUJFQAOAMgWAA==.',
Na='Nakwoo:BAAALgADCgMJAwAAAA==.',
Of='Of:BAAALgAECgEJAgAAAA==.',
On='One:BAAALgAECgEJAQAAAA==.',
Op='Opallea:BAABLgAECn8dAAMXAAkJWxugEQBRAgloDAAABQBPAGkMAAAGAE4AawwAAAYASwBqDAAAAwBOAGwMAAACAEgAbQwAAAEARADqDAAABABKAG4MAAABAC4AbwwAAAEAQAAXAAkJWxugEQBRAgloDAAABABPAGkMAAAFAE4AawwAAAUASwBqDAAAAgBOAGwMAAACAEgAbQwAAAEARADqDAAABABKAG4MAAABAC4AbwwAAAEAQAATAAQJ6gSUzABjAARoDAAAAQAKAGkMAAABABIAawwAAAEACQBqDAAAAQAeAAAA.',
Pa='Pallyplay:BAAALgAECgEJAQAAAA==.',
Pb='Pballs:BAAALgADCgEJAQABLgAECgkJRQAaAD8fAA==.',
Pe='Periodic:BAACLgAFFH8OAAICAAQJKCP9EQCQAQRoDAAABQBaAGkMAAADAGAAawwAAAIAUQDqDAAABABbAAIABAkoI/0RAJABBGgMAAAFAFoAaQwAAAMAYABrDAAAAgBRAOoMAAAEAFsALgAECn8vAAICAAkJ5CP0AACZAwACAAkJ5CP0AACZAwAAAA==.',
Pl='Platen:BAABLgAECn8jAAIGAAkJQRJbMADyAQloDAAABwA3AGkMAAAGADIAawwAAAYAKABqDAAAAwAwAGwMAAADAEwAbQwAAAEABQDqDAAABQBNAG4MAAADACsAbwwAAAEAFgAGAAkJQRJbMADyAQloDAAABwA3AGkMAAAGADIAawwAAAYAKABqDAAAAwAwAGwMAAADAEwAbQwAAAEABQDqDAAABQBNAG4MAAADACsAbwwAAAEAFgAAAA==.',
Po='Potter:BAABLgAECn9FAAIEAAkJbB+FFQC/AgloDAAACQBUAGkMAAAJAEwAawwAAAkAUgBqDAAACABBAGwMAAAIAF8AbQwAAAcASgDqDAAACQBQAG4MAAAGAEwAbwwAAAQASAAEAAkJbB+FFQC/AgloDAAACQBUAGkMAAAJAEwAawwAAAkAUgBqDAAACABBAGwMAAAIAF8AbQwAAAcASgDqDAAACQBQAG4MAAAGAEwAbwwAAAQASAAAAA==.',
Ra='Raffa:BAABLgAECn8jAAIUAAcJiB54FADxAQdoDAAABQBWAGkMAAAEAE4AawwAAAUAJwBqDAAABQBUAGwMAAADAFgAbQwAAAIAUADqDAAACwBfABQABwmIHngUAPEBB2gMAAAFAFYAaQwAAAQATgBrDAAABQAnAGoMAAAFAFQAbAwAAAMAWABtDAAAAgBQAOoMAAALAF8AAAA=.Rakandei:BAAALgADCgMJAwAAAA==.Ramaylis:BAAALgADCgEJAQAAAA==.Raptor:BAABLgAFFH8JAAIEAAUJGRy0MgBiAQVoDAAAAgBTAGkMAAACADsAawwAAAIAMABqDAAAAQADAOoMAAACAF8ABAAFCRkctDIAYgEFaAwAAAIAUwBpDAAAAgA7AGsMAAACADAAagwAAAEAAwDqDAAAAgBfAAAA.Rapunzel:BAAALgAECgkJBgAAAA==.Rataiga:BAAALgAECgYJEgAAAA==.',
Rh='Rheynah:BAABLgAECn8gAAMeAAkJ4QSvOAC1AAloDAAABgAIAGkMAAAFABIAawwAAAUADQBqDAAAAwAVAGwMAAADAA0AbQwAAAEACADqDAAABQAHAG4MAAADAAsAbwwAAAEAEQAFAAgJ/wMWUQDeAAhoDAAABQAIAGkMAAAEAA8AawwAAAQADQBqDAAAAgADAGwMAAACAAcA6gwAAAQABwBuDAAAAQABAG8MAAABABEAHgAICasDrzgAtQAIaAwAAAEABABpDAAAAQASAGsMAAABAAQAagwAAAEAFQBsDAAAAQANAG0MAAABAAgA6gwAAAEAAwBuDAAAAgALAAAA.',
Ri='Rimuna:BAAALgADCgUJBQAAAA==.Rinni:BAACLgAFFH8aAAIQAAYJkyDGAADpAQZoDAAABgBeAGkMAAAFAF0AawwAAAQAUgBqDAAAAwBJAGwMAAABADYA6gwAAAcAXQAQAAYJkyDGAADpAQZoDAAABgBeAGkMAAAFAF0AawwAAAQAUgBqDAAAAwBJAGwMAAABADYA6gwAAAcAXQAuAAQKfy0AAhAACQkQJQoBADgDABAACQkQJQoBADgDAAAA.',
Ro='Rovintis:BAABLgAECn82AAIeAAgJpBrRCgAXAghoDAAACQBTAGkMAAAJAEsAawwAAAgATABqDAAABwBWAGwMAAAGAEQAbQwAAAQANgDqDAAACABUAG4MAAADACMAHgAICaQa0QoAFwIIaAwAAAkAUwBpDAAACQBLAGsMAAAIAEwAagwAAAcAVgBsDAAABgBEAG0MAAAEADYA6gwAAAgAVABuDAAAAwAjAAAA.',
Ry='Rynne:BAABLgAECn8VAAQCAAgJCxSNQQB5AQhoDAAAAwA5AGkMAAAEACcAawwAAAMASQBqDAAAAwA7AGwMAAADADcAbQwAAAEABwBuDAAAAwAaAG8MAAABAFoAAgAHCdYRjUEAeQEHaAwAAAEAOQBpDAAAAQAnAGsMAAABAEkAagwAAAEAOwBsDAAAAQA3AG0MAAABAAcAbgwAAAEAGgAfAAcJ8AcBHAAKAQdoDAAAAgAYAGkMAAADABYAawwAAAIAGwBqDAAAAgAZAGwMAAACABAAbgwAAAEAEQBvDAAAAQAMAAMAAQlnAy+fAB0AAW4MAAABAAgAAAA=.',
Sa='Sansundertal:BAABLgAECn8wAAIKAAkJsSJ+AgBJAwloDAAABwBcAGkMAAAGAFEAawwAAAYAYQBqDAAABgBjAGwMAAAGAGAAbQwAAAQAWwDqDAAABwBjAG4MAAAEAFkAbwwAAAIAMgAKAAkJsSJ+AgBJAwloDAAABwBcAGkMAAAGAFEAawwAAAYAYQBqDAAABgBjAGwMAAAGAGAAbQwAAAQAWwDqDAAABwBjAG4MAAAEAFkAbwwAAAIAMgAAAA==.Sargeràs:BAAALgADCgcJDAABLgAECgMJAwABAAAAAA==.',
Se='Selissaroth:BAAALgAECgEJAQAAAA==.Sentinal:BAABLgAECn8sAAIbAAgJchZ3FACgAQhoDAAABwBXAGkMAAAHAD0AawwAAAYAOwBqDAAABgBUAGwMAAAFAEMAbQwAAAMAHQDqDAAABwA5AG4MAAADACcAGwAICXIWdxQAoAEIaAwAAAcAVwBpDAAABwA9AGsMAAAGADsAagwAAAYAVABsDAAABQBDAG0MAAADAB0A6gwAAAcAOQBuDAAAAwAnAAAA.Sentinäl:BAAALgAECgIJAgAAAA==.Sephiro:BAAALgAECgQJBgAAAA==.',
Sh='Shamu:BAACLgAFFH8IAAICAAMJ9BDHOADOAANoDAAABAAWAGkMAAABABIA6gwAAAMAWAACAAMJ9BDHOADOAANoDAAABAAWAGkMAAABABIA6gwAAAMAWAAuAAQKfxoAAgIACQkNFdI5AJoBAAIACQkNFdI5AJoBAAAA.Shawner:BAAALgADCgMJAwAAAA==.Shy:BAAALgAECgUJBgAAAA==.',
Si='Silvertiger:BAABLgAECn9EAAMRAAkJ3h+gBADKAgloDAAACABYAGkMAAAJAFoAawwAAAkAUgBqDAAACABGAGwMAAAIAFQAbQwAAAcAUwDqDAAACQBEAG4MAAAGAFQAbwwAAAQARgARAAkJ3h+gBADKAgloDAAABwBYAGkMAAAHAFoAawwAAAcAUgBqDAAABwBGAGwMAAAHAFQAbQwAAAYAUwDqDAAABwBEAG4MAAAGAFQAbwwAAAQARgAgAAcJgg+dPABsAQdoDAAAAQAtAGkMAAACADMAawwAAAIAJABqDAAAAQASAGwMAAABACwAbQwAAAEAIADqDAAAAgAdAAAA.',
Sl='Slabbydabby:BAAALgAECgYJCgAAAA==.Sleeperbater:BAAALgADCgIJAgAAAA==.Sleeperdk:BAAALgAECgYJCwAAAA==.',
Sn='Snackyfraps:BAAALgAECgEJAQABLgAECgkJRQAaAD8fAA==.Sneaki:BAABLgAECn9DAAQhAAkJdyXfAwDqAgloDAAACQBjAGkMAAAJAF8AawwAAAkAXABqDAAACABcAGwMAAAIAF0AbQwAAAYAYADqDAAACQBdAG4MAAAFAGMAbwwAAAQAYAAhAAkJ+SPfAwDqAgloDAAACABjAGkMAAAIAF8AawwAAAgAXABqDAAABwBcAGwMAAACAD8AbQwAAAUAYADqDAAACABdAG4MAAAEAGMAbwwAAAQAYAAiAAgJ/RzKAwA0AghoDAAAAQBXAGkMAAABACsAawwAAAEARwBqDAAAAQBLAGwMAAABAF0AbQwAAAEAQQDqDAAAAQBPAG4MAAABAE4AEgABCbEjbRoAaQABbAwAAAUAWwAAAA==.Sniperanger:BAAALgADCgMJAwAAAA==.Snstr:BAABLgAECn8aAAQYAAYJbRfiLACTAQZoDAAABgBOAGkMAAAFAEgAawwAAAQATABqDAAAAwAaAGwMAAADACgA6gwAAAUAQAAYAAYJbRfiLACTAQZoDAAABQBOAGkMAAAEAEgAawwAAAMATABqDAAAAgAaAGwMAAACACgA6gwAAAQAQAAZAAQJ5gMhTQChAARpDAAAAQAGAGsMAAABAA4AagwAAAEADgBsDAAAAQAJABoAAgmRCFlNAF0AAmgMAAABAA4A6gwAAAEAHAAAAA==.',
So='Sorynia:BAABLgAECn8YAAIGAAgJnwY8cgAwAQhoDAAABAASAGkMAAAEABkAawwAAAQAGABqDAAABAAbAGwMAAABAAgAbQwAAAEABQDqDAAABAALAG4MAAACABgABgAICZ8GPHIAMAEIaAwAAAQAEgBpDAAABAAZAGsMAAAEABgAagwAAAQAGwBsDAAAAQAIAG0MAAABAAUA6gwAAAQACwBuDAAAAgAYAAAA.Soul:BAAALgAECgEJAQAAAA==.Soulkid:BAAALgAECgQJBQAAAA==.',
St='Starta:BAACLgAFFH8LAAITAAMJ5xnyRQDqAANoDAAABAA7AGkMAAADADwA6gwAAAQATgATAAMJ5xnyRQDqAANoDAAABAA7AGkMAAADADwA6gwAAAQATgAuAAQKfxsAAhMACAmNIRsmABgCABMACAmNIRsmABgCAAAA.Startawar:BAACLgAFFH8FAAINAAIJxhLhawCbAAJpDAAAAQAiAOoMAAAEAD0ADQACCcYS4WsAmwACaQwAAAEAIgDqDAAABAA9AC4ABAp/JAACDQAICccjLBYA5AIADQAICccjLBYA5AIAAAA=.Stormbeard:BAAALgAECgUJBQABLgAFFAYJFwANANwiAA==.',
Su='Sukii:BAAALgAECgUJBgAAAA==.Sulfuricvein:BAAALgAFFAEJAQAAAA==.',
['Sø']='Sømebody:BAAALgAECgMJAwAAAA==.',
Ti='Tiana:BAAALgAECgkJBAAAAA==.',
To='Totemdaddy:BAAALgAECgEJAQAAAA==.Totemicdidit:BAAALgADCgMJAwAAAA==.Totemstorm:BAAALgAECgcJBwAAAA==.',
Tr='Traumatic:BAABLgAECn8UAAIFAAcJjRj6LwDvAQdoDAAAAwBIAGkMAAAEAEUAawwAAAMAPwBqDAAAAwAfAGwMAAACADwA6gwAAAQASQBuDAAAAQAlAAUABwmNGPovAO8BB2gMAAADAEgAaQwAAAQARQBrDAAAAwA/AGoMAAADAB8AbAwAAAIAPADqDAAABABJAG4MAAABACUAAAA=.',
Tu='Tunny:BAAALgAECgYJCAAAAA==.Turnleft:BAABLgAECn8wAAMjAAkJZiMnAgCeAwloDAAABwBjAGkMAAAHAGEAawwAAAYAYwBqDAAABgBiAGwMAAAGAGMAbQwAAAQAXQDqDAAABwBiAG4MAAAEAE8AbwwAAAEAMAAjAAkJZiMnAgCeAwloDAAABwBjAGkMAAAHAGEAawwAAAYAYwBqDAAABgBiAGwMAAAGAGMAbQwAAAQAXQDqDAAABgBiAG4MAAAEAE8AbwwAAAEAMAAkAAEJgh5iZgBXAAHqDAAAAQBOAAAA.',
Va='Valerïan:BAAALgADCgEJAQABLgAECgcJEwABAAAAAA==.Vauntmonk:BAAALgADCgMJAwABLgAFFAQJEQAlAFYhAA==.',
Ve='Vercyv:BAAALgADCgkJEQAAAA==.Vevio:BAAALgAECgQJBAAAAA==.',
Vi='Video:BAAALgAECgEJAQAAAA==.Violet:BAACLgAFFH8GAAIOAAMJABlNawD3AANoDAAAAwBFAGkMAAACAEsA6gwAAAEALgAOAAMJABlNawD3AANoDAAAAwBFAGkMAAACAEsA6gwAAAEALgAuAAQKfy0AAg4ACQk8HrERAMMCAA4ACQk8HrERAMMCAAAA.Vishlock:BAABLgAECn8xAAMVAAkJhBlOBQAGAgloDAAABgBQAGkMAAAGADsAawwAAAYANwBqDAAABQA1AGwMAAAFAEsAbQwAAAQAGwDqDAAABwBMAG4MAAAGAFkAbwwAAAQAOQAVAAkJhBlOBQAGAgloDAAABQBQAGkMAAAGADsAawwAAAUANwBqDAAAAwA1AGwMAAAEAEsAbQwAAAIAGwDqDAAABQBMAG4MAAADAFkAbwwAAAMAOQAMAAgJ8w4OlAAwAQhoDAAAAQARAGsMAAABACAAagwAAAIACgBsDAAAAQBBAG0MAAACABEA6gwAAAIAQQBuDAAAAwAXAG8MAAABAC4AAAA=.',
Vo='Voddie:BAABLgAECn8gAAIDAAkJPgxKKwBwAQloDAAABgAdAGkMAAAGABoAawwAAAYAHgBqDAAAAwALAGwMAAADABUAbQwAAAEACQDqDAAABAAeAG4MAAACAFQAbwwAAAEAEgADAAkJPgxKKwBwAQloDAAABgAdAGkMAAAGABoAawwAAAYAHgBqDAAAAwALAGwMAAADABUAbQwAAAEACQDqDAAABAAeAG4MAAACAFQAbwwAAAEAEgAAAA==.Votarick:BAAALgAECgEJAQAAAA==.',
Wa='Waban:BAAALgAECgcJEwAAAA==.Walmarthas:BAAALgAECgcJDQABLgAECgkJHQAIAEkUAA==.Wapta:BAAALgAFFAEJAQABLgAFFAUJCQAEABkcAA==.',
Wi='Wizwiztheliz:BAAALgAECgYJDwAAAA==.',
Wo='Wolf:BAABLgAECn8cAAImAAgJOxBmJABsAQhoDAAABgAwAGkMAAAFACcAawwAAAUAIABqDAAAAwAbAGwMAAACADEAbQwAAAEABwDqDAAABAA2AG4MAAACADoAJgAICTsQZiQAbAEIaAwAAAYAMABpDAAABQAnAGsMAAAFACAAagwAAAMAGwBsDAAAAgAxAG0MAAABAAcA6gwAAAQANgBuDAAAAgA6AAEuAAUUAwkEAAEAAAAA.Woof:BAAALgAECgIJAgAAAA==.',
Xy='Xynelle:BAAALgADCgcJCwAAAA==.',
Ya='Yahtzee:BAAALgAECgQJBwAAAA==.',
Yo='Youdidwhat:BAAALgADCgkJCQAAAA==.',
Za='Zaia:BAAALgAECgcJEwAAAA==.',
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
