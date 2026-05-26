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
local provider = {region='US',realm='Coilfang',name='US',type='daily',zone=46,date='2026-05-26',data={Ae='Aendean:BAAALgAECgQJBAAAAA==.',
Am='Amethyne:BAAALgADCgMJAwAAAA==.',
An='Anabell:BAAALgAECgIJAwABLgAECgYJCAABAAAAAA==.',
Ar='Arckane:BAAALgAECgEJAQAAAA==.Arcueid:BAABLgAECn80AAMCAAkJqCAeFwBdAgloDAAABwBQAGkMAAAGAFMAawwAAAkAWABqDAAABwBVAGwMAAAGAEkAbQwAAAMAOwDqDAAACgBZAG4MAAADAFwAbwwAAAEAYwACAAgJ4x8eFwBdAghoDAAABwBQAGkMAAAGAFMAawwAAAkAWABqDAAABwBVAGwMAAAGAEkAbQwAAAMAOwDqDAAACgBZAG4MAAACAFwAAwACCRAZ/mEAlgACbgwAAAEAUwBvDAAAAQAtAAAA.',
As='Asmadeus:BAAALgAECgYJBwAAAA==.',
Ay='Ayda:BAABLgAECn9FAAIEAAkJXyWDBABZAwloDAAACQBhAGkMAAAJAGAAawwAAAkAYQBqDAAACABOAGwMAAAIAGMAbQwAAAcAWgDqDAAACQBfAG4MAAAGAF4AbwwAAAQAXgAEAAkJXyWDBABZAwloDAAACQBhAGkMAAAJAGAAawwAAAkAYQBqDAAACABOAGwMAAAIAGMAbQwAAAcAWgDqDAAACQBfAG4MAAAGAF4AbwwAAAQAXgAAAA==.',
Ba='Bajabeachboy:BAAALgAFFAIJBAABLgAFFAMJDgAFAEofAA==.Bartholdson:BAABLgAECn8fAAIGAAgJ2hhxMQDzAQhoDAAABQBAAGkMAAAEAFIAawwAAAQATABqDAAABQBBAGwMAAAEADIAbQwAAAIALADqDAAABQA2AG4MAAACAEgABgAICdoYcTEA8wEIaAwAAAUAQABpDAAABABSAGsMAAAEAEwAagwAAAUAQQBsDAAABAAyAG0MAAACACwA6gwAAAUANgBuDAAAAgBIAAAA.',
Be='Bearlydidit:BAAALgADCgQJBAAAAA==.Beloc:BAAALgAECgcJAgAAAA==.Berzerkirz:BAAALgADCgYJBgAAAA==.',
Bl='Blacksnow:BAAALgADCgEJAQAAAA==.Blcksnowcrow:BAABLgAECn8kAAIHAAkJfxzFCQDQAgloDAAABgBbAGkMAAAFAFkAawwAAAYAXABqDAAABABEAGwMAAADAFAAbQwAAAMAQwDqDAAABwBOAG4MAAABACkAbwwAAAEALwAHAAkJfxzFCQDQAgloDAAABgBbAGkMAAAFAFkAawwAAAYAXABqDAAABABEAGwMAAADAFAAbQwAAAMAQwDqDAAABwBOAG4MAAABACkAbwwAAAEALwAAAA==.',
Bo='Bonfire:BAACLgAFFH8HAAIIAAUJvRwoFwBbAQVoDAAAAQA+AGkMAAACAF8AawwAAAEAMABqDAAAAQBaAOoMAAACAFgACAAFCb0cKBcAWwEFaAwAAAEAPgBpDAAAAgBfAGsMAAABADAAagwAAAEAWgDqDAAAAgBYAC4ABAp/JgAECAAJCW8jKQoAoAIACAAJCe0iKQoAoAIACQAGCW4hxg4ABwEACgACCUoChkQASwAAAS4ABRQFCQkABAAZHAA=.Boochili:BAABLgAECn9BAAILAAkJ7yYHAACWAwloDAAACABjAGkMAAAIAGMAawwAAAgAYwBqDAAACABjAGwMAAAIAGMAbQwAAAcAYwDqDAAACABjAG4MAAAGAGMAbwwAAAQAYwALAAkJ7yYHAACWAwloDAAACABjAGkMAAAIAGMAawwAAAgAYwBqDAAACABjAGwMAAAIAGMAbQwAAAcAYwDqDAAACABjAG4MAAAGAGMAbwwAAAQAYwAAAA==.',
Br='Bravebeard:BAAALgAFFAMJAwAAAA==.Braveling:BAABLgAECn8fAAIMAAkJ9A4/PADYAQloDAAABQAZAGkMAAAFACwAawwAAAUAGwBqDAAAAwAvAGwMAAADAC0AbQwAAAEAIADqDAAABQAjAG4MAAADAEgAbwwAAAEAFgAMAAkJ9A4/PADYAQloDAAABQAZAGkMAAAFACwAawwAAAUAGwBqDAAAAwAvAGwMAAADAC0AbQwAAAEAIADqDAAABQAjAG4MAAADAEgAbwwAAAEAFgAAAA==.',
Bu='Bubblës:BAAALgAECgQJCAABLgAECgkJMAAEAJgiAA==.',
Ca='Carezarsh:BAAALgADCgMJAQAAAA==.',
Ch='Charlie:BAACLgAFFH8XAAMNAAYJ3CLSCADmAQZoDAAABgBdAGkMAAAFAFoAawwAAAUAXwBqDAAAAQBGAGwMAAABAE8A6gwAAAUAVgANAAYJ3CLSCADmAQZoDAAABgBdAGkMAAAFAFoAawwAAAQAXwBqDAAAAQBGAGwMAAABAE8A6gwAAAUAVgALAAEJQCM3DwBhAAFrDAAAAQBaAC4ABAp/OAADDQAJCc4lHwgAUwMADQAJCc4lHwgAUwMACwAFCc4ZJyAA7AAAAAA=.Chicken:BAAALgAFFAMJBAAAAA==.',
Cr='Cruel:BAAALgADCgEJAQAAAA==.',
['Cä']='Cätîáñdrïà:BAACLgAFFH8JAAICAAQJuhdOIgAxAQRoDAAAAgBPAGkMAAAEAEUAawwAAAEAHwDqDAAAAgA+AAIABAm6F04iADEBBGgMAAACAE8AaQwAAAQARQBrDAAAAQAfAOoMAAACAD4ALgAECn9dAAMCAAkJuyAaBgAyAwACAAkJuyAaBgAyAwADAAYJdw4PSgDkAAAAAA==.',
Da='Dagron:BAAALgAFFAIJAgAAAA==.Daniedk:BAABLgAECn8vAAIOAAgJvhN9XQCUAQhoDAAABwBDAGkMAAAHAC4AawwAAAYAHQBqDAAABwBAAGwMAAAFACsAbQwAAAMAIgDqDAAABgBDAG4MAAAGAEEADgAICb4TfV0AlAEIaAwAAAcAQwBpDAAABwAuAGsMAAAGAB0AagwAAAcAQABsDAAABQArAG0MAAADACIA6gwAAAYAQwBuDAAABgBBAAAA.Daphanim:BAAALgADCgYJCgAAAA==.Darctotem:BAAALgAECgYJEQAAAA==.',
De='Deathtouch:BAACLgAFFH8HAAMOAAMJPhxtgQDXAANoDAAAAgBTAGkMAAADADcA6gwAAAIATQAOAAMJPhxtgQDXAANoDAAAAQBTAGkMAAACADcA6gwAAAIATQAPAAIJSRDgFACLAAJoDAAAAQAnAGkMAAABACsALgAECn8bAAMOAAgJSSP7KwA1AgAOAAgJyiL7KwA1AgAPAAEJEh01KgBBAAAAAA==.Devona:BAABLgAECn8kAAMHAAkJZR24HgDuAQloDAAABwBBAGkMAAAGAFAAawwAAAYATQBqDAAAAwBNAGwMAAADAF8AbQwAAAEAHQDqDAAABgBYAG4MAAADAF4AbwwAAAEARAAHAAcJtBy4HgDuAQdoDAAABQBBAGkMAAAFAFAAawwAAAUATQBqDAAAAgBNAGwMAAACAF8AbQwAAAEAHQDqDAAABQBYAA0ACAnTDytfAJsBCGgMAAACACQAaQwAAAEALgBrDAAAAQAYAGoMAAABABsAbAwAAAEAKADqDAAAAQAaAG4MAAADAE8AbwwAAAEAHQAAAA==.',
Di='Didit:BAAALgADCgcJBwAAAA==.Dingdangler:BAAALgAECgMJAwAAAA==.Dingledangle:BAABLgAECn8iAAIQAAgJlBRyDQCzAQhoDAAABgBOAGkMAAAGADwAawwAAAYAPgBqDAAABQA5AGwMAAACAAkAbQwAAAIALwDqDAAABQA+AG4MAAACADAAEAAICZQUcg0AswEIaAwAAAYATgBpDAAABgA8AGsMAAAGAD4AagwAAAUAOQBsDAAAAgAJAG0MAAACAC8A6gwAAAUAPgBuDAAAAgAwAAAA.',
Dj='Djindor:BAAALgADCgUJBQAAAA==.',
Dr='Draconix:BAAALgAECgQJBAABLgAECgYJBgABAAAAAA==.Dragonzordd:BAAALgADCgQJBQABLgAECgYJGgARAAwiAA==.Dragooncrush:BAAALgADCgcJCwAAAA==.Dragoonnick:BAACLgAFFH8LAAISAAQJcxLrAwBIAQRoDAAABQBDAGkMAAADAFEAawwAAAEAIgDqDAAAAgAEABIABAlzEusDAEgBBGgMAAAFAEMAaQwAAAMAUQBrDAAAAQAiAOoMAAACAAQALgAECn9AAAISAAkJ/BvABAAfAgASAAkJ/BvABAAfAgAAAA==.Drazzy:BAAALgAECgIJAgAAAA==.',
Eg='Egg:BAAALgAFFAEJAQABLgAFFAYJFwATAKcTAA==.',
Es='Esh:BAAALgAECgcJDgAAAA==.',
Eu='Euphal:BAABLgAECn8oAAIMAAkJLBIzQADLAQloDAAABAA1AGkMAAAGAC0AawwAAAUAIQBqDAAAAwA1AGwMAAAHAEAAbQwAAAIAFwDqDAAABwBDAG4MAAAFADUAbwwAAAEAHgAMAAkJLBIzQADLAQloDAAABAA1AGkMAAAGAC0AawwAAAUAIQBqDAAAAwA1AGwMAAAHAEAAbQwAAAIAFwDqDAAABwBDAG4MAAAFADUAbwwAAAEAHgAAAA==.',
Ey='Eyekicku:BAABLgAECn8iAAIUAAkJrx/KBgDDAgloDAAABwBcAGkMAAAGAFoAawwAAAYAWQBqDAAAAwBaAGwMAAADAE4AbQwAAAEAQADqDAAABQBZAG4MAAACAFoAbwwAAAEANQAUAAkJrx/KBgDDAgloDAAABwBcAGkMAAAGAFoAawwAAAYAWQBqDAAAAwBaAGwMAAADAE4AbQwAAAEAQADqDAAABQBZAG4MAAACAFoAbwwAAAEANQAAAA==.',
Fe='Feldana:BAAALgAECgQJBAAAAA==.Fenicon:BAAALgAECgQJBQAAAA==.',
Fi='Fitz:BAAALgAECgQJBAAAAA==.Fitzwell:BAAALgAECgUJCQAAAA==.',
Fu='Fuyu:BAAALgAECgQJBAAAAA==.Fuyuhex:BAABLgAFFH8FAAICAAMJ0REVSQCeAANoDAAAAgAzAGwMAAABAAAA6gwAAAIAVAACAAMJ0REVSQCeAANoDAAAAgAzAGwMAAABAAAA6gwAAAIAVAAAAA==.',
Gh='Ghost:BAAALgAECgMJBQAAAA==.',
Gi='Gibbousbogg:BAAALgADCgEJAQAAAA==.',
Gr='Graycieden:BAAALgAECgYJCQAAAA==.',
Gu='Guldangit:BAACLgAFFH8jAAMMAAgJcR22AQAmAghoDAAABwBcAGkMAAAFAFsAawwAAAYAVQBqDAAABABLAGwMAAADADkAbQwAAAEAIwDqDAAACABcAG4MAAABAEgADAAICTQctgEAJgIIaAwAAAYAXABpDAAABABbAGsMAAAFAFIAagwAAAMARABsDAAAAwA5AG0MAAABACMA6gwAAAYASABuDAAAAQBIABUABQlJH4EBAH0BBWgMAAABADwAaQwAAAEAUgBrDAAAAQBVAGoMAAABAEsA6gwAAAIAXAAuAAQKfzIABBUACQn/JUsAAE4DABUACQkSJUsAAE4DAAwACQkBI2oIAD4DABYABAmOIi4aAHsBAAAA.',
Ha='Hanora:BAAALgAECgUJBgAAAA==.',
He='Hellspawn:BAABLgAECn9FAAIXAAkJyg/jFgCjAQloDAAACQA+AGkMAAAJADMAawwAAAkALABqDAAACAAbAGwMAAAIACUAbQwAAAcAGADqDAAACQApAG4MAAAGACQAbwwAAAQAGQAXAAkJyg/jFgCjAQloDAAACQA+AGkMAAAJADMAawwAAAkALABqDAAACAAbAGwMAAAIACUAbQwAAAcAGADqDAAACQApAG4MAAAGACQAbwwAAAQAGQAAAA==.',
Hh='Hhounow:BAAALgADCgcJDAAAAA==.',
Ho='Hojai:BAAALgADCgMJAwAAAA==.Holybeef:BAAALgAECgcJDQAAAA==.Holygrim:BAACLgAFFH8kAAIYAAgJGSQWAABHAwhoDAAABwBkAGkMAAAHAGMAawwAAAYAYgBqDAAABQBhAGwMAAACAFEAbQwAAAEAVwDqDAAABwBiAG4MAAABAE0AGAAICRkkFgAARwMIaAwAAAcAZABpDAAABwBjAGsMAAAGAGIAagwAAAUAYQBsDAAAAgBRAG0MAAABAFcA6gwAAAcAYgBuDAAAAQBNAC4ABAp/HQADGAAICWMm4AEAVwMAGAAICWMm4AEAVwMAGQABCT4JH3gALgAAAAA=.Holyloa:BAAALgAECgMJAwAAAA==.Holypablo:BAABLgAECn9FAAQaAAkJPx+cBQAQAwloDAAACQBJAGkMAAAJAFoAawwAAAkAXgBqDAAACABfAGwMAAAIAGEAbQwAAAcAVADqDAAACQA6AG4MAAAGAEIAbwwAAAQAOwAaAAkJPx+cBQAQAwloDAAABABJAGkMAAAEAFoAawwAAAQAXgBqDAAABgBfAGwMAAAHAGEAbQwAAAcAVADqDAAABQA6AG4MAAAEAEIAbwwAAAQAOwAZAAcJ0RmaGwDKAQdoDAAABAA2AGkMAAAEAEcAawwAAAQARwBqDAAAAgA6AGwMAAABAEAA6gwAAAMAKABuDAAAAgBeABgABAmtC5VdALwABGgMAAABAA4AaQwAAAEAGABrDAAAAQAxAOoMAAABAB8AAAA=.Howii:BAABLgAECn9HAAIbAAkJnSUQAQBOAwloDAAACgBbAGkMAAAJAGIAawwAAAkAYABqDAAACABfAGwMAAAIAGEAbQwAAAcAYADqDAAACgBgAG4MAAAGAGAAbwwAAAQAXwAbAAkJnSUQAQBOAwloDAAACgBbAGkMAAAJAGIAawwAAAkAYABqDAAACABfAGwMAAAIAGEAbQwAAAcAYADqDAAACgBgAG4MAAAGAGAAbwwAAAQAXwAAAA==.',
Im='Imperator:BAAALgAECgQJBAAAAA==.',
In='Inchworm:BAAALgAECgYJBgAAAA==.',
Is='Isabellaah:BAABLgAECn8hAAIGAAkJZBUjKAAaAgloDAAABwA7AGkMAAAGAEYAawwAAAYAPwBqDAAAAwAgAGwMAAADADwAbQwAAAEACQDqDAAABQAsAG4MAAABAFAAbwwAAAEAMQAGAAkJZBUjKAAaAgloDAAABwA7AGkMAAAGAEYAawwAAAYAPwBqDAAAAwAgAGwMAAADADwAbQwAAAEACQDqDAAABQAsAG4MAAABAFAAbwwAAAEAMQAAAA==.',
Je='Jeraziah:BAAALgAECgUJEQABLgAECgkJNAACAKggAA==.',
Jo='Johnnyjr:BAABLgAECn8kAAIFAAkJASE9BQD2AgloDAAABABLAGkMAAAEAGAAawwAAAQAVwBqDAAABAAyAGwMAAAEAFcAbQwAAAQAPwDqDAAABABRAG4MAAAEAF4AbwwAAAQAWQAFAAkJASE9BQD2AgloDAAABABLAGkMAAAEAGAAawwAAAQAVwBqDAAABAAyAGwMAAAEAFcAbQwAAAQAPwDqDAAABABRAG4MAAAEAF4AbwwAAAQAWQAAAA==.',
Ke='Kelliz:BAAALgADCgcJCAAAAA==.',
Kh='Khaladin:BAAALgAECgYJEgAAAA==.',
La='Laggers:BAABLgAECn8jAAIcAAgJdxb0FwBdAQhoDAAABgA3AGkMAAAGAE4AawwAAAYARgBqDAAABQAwAGwMAAADADMAbQwAAAEAGgDqDAAABwBKAG4MAAABAC0AHAAICXcW9BcAXQEIaAwAAAYANwBpDAAABgBOAGsMAAAGAEYAagwAAAUAMABsDAAAAwAzAG0MAAABABoA6gwAAAcASgBuDAAAAQAtAAAA.',
Le='Lean:BAAALgAFFAIJAgABLgAFFAUJCQAEABkcAA==.',
Li='Litbit:BAABLgAECn8jAAIEAAgJXQSXqAAZAQhoDAAABgAQAGkMAAAGABMAawwAAAYABwBqDAAABgAQAGwMAAAEAA4AbQwAAAIABwDqDAAABAAFAG4MAAABAAYABAAICV0El6gAGQEIaAwAAAYAEABpDAAABgATAGsMAAAGAAcAagwAAAYAEABsDAAABAAOAG0MAAACAAcA6gwAAAQABQBuDAAAAQAGAAAA.Litbitonme:BAAALgAECgQJCgAAAA==.Litllit:BAAALgAECgMJAwAAAA==.Litt:BAAALgADCgkJCwAAAA==.Lizardwizard:BAAALgAECgEJAQAAAA==.',
Lo='Lockmantwo:BAAALgAECgcJAwAAAA==.Lostmoo:BAAALgAECgEJAQAAAA==.Lostunholy:BAABLgAECn8gAAIOAAgJBSIjHwBzAghoDAAACABhAGkMAAAFAFIAawwAAAQAVwBqDAAAAwBaAGwMAAADAFMAbQwAAAIASQDqDAAABQBaAG4MAAACAF0ADgAICQUiIx8AcwIIaAwAAAgAYQBpDAAABQBSAGsMAAAEAFcAagwAAAMAWgBsDAAAAwBTAG0MAAACAEkA6gwAAAUAWgBuDAAAAgBdAAAA.Lovebug:BAAALgADCgcJBwAAAA==.',
Lu='Lunaardris:BAAALgAECgQJBQAAAA==.',
Ly='Lynxe:BAAALgAECgYJBgAAAA==.',
Ma='Maggikal:BAABLgAECn8gAAMEAAgJIxAnYQCnAQhoDAAABgA3AGkMAAAFAEUAawwAAAUALQBqDAAAAwAXAGwMAAACAAoA6gwAAAgAKABuDAAAAgAqAG8MAAABABcABAAICSMQJ2EApwEIaAwAAAYANwBpDAAABQBFAGsMAAAFAC0AagwAAAMAFwBsDAAAAgAKAOoMAAAHACgAbgwAAAIAKgBvDAAAAQAXAB0AAQkIDP8PADMAAeoMAAABAB4AAAA=.',
Me='Megahottie:BAAALgAECgEJAQAAAA==.',
Mi='Mirant:BAAALgAECgUJDwAAAA==.',
Mo='Moretisha:BAAALgADCgYJBgAAAA==.',
['Mâ']='Mâchine:BAAALgAFFAIJAgABLgAFFAUJFQAOAMgWAA==.',
Na='Nakwoo:BAAALgADCgMJAwAAAA==.',
Of='Of:BAAALgAECgEJAgAAAA==.',
On='One:BAAALgAECgEJAQAAAA==.',
Op='Opallea:BAABLgAECn8dAAMXAAkJWxugEQBRAgloDAAABQBPAGkMAAAGAE4AawwAAAYASwBqDAAAAwBOAGwMAAACAEgAbQwAAAEARADqDAAABABKAG4MAAABAC4AbwwAAAEAQAAXAAkJWxugEQBRAgloDAAABABPAGkMAAAFAE4AawwAAAUASwBqDAAAAgBOAGwMAAACAEgAbQwAAAEARADqDAAABABKAG4MAAABAC4AbwwAAAEAQAATAAQJ6gRA0ABjAARoDAAAAQAKAGkMAAABABIAawwAAAEACQBqDAAAAQAeAAAA.',
Pa='Pallyplay:BAAALgAECgEJAQAAAA==.',
Pb='Pballs:BAAALgADCgEJAQABLgAECgkJRQAaAD8fAA==.',
Pe='Periodic:BAACLgAFFH8OAAICAAQJKCNGEwCQAQRoDAAABQBaAGkMAAADAGAAawwAAAIAUQDqDAAABABbAAIABAkoI0YTAJABBGgMAAAFAFoAaQwAAAMAYABrDAAAAgBRAOoMAAAEAFsALgAECn8vAAICAAkJ5CP0AACZAwACAAkJ5CP0AACZAwAAAA==.',
Pl='Platen:BAABLgAECn8jAAIGAAkJQRIbMgDxAQloDAAABwA3AGkMAAAGADIAawwAAAYAKABqDAAAAwAwAGwMAAADAEwAbQwAAAEABQDqDAAABQBNAG4MAAADACsAbwwAAAEAFgAGAAkJQRIbMgDxAQloDAAABwA3AGkMAAAGADIAawwAAAYAKABqDAAAAwAwAGwMAAADAEwAbQwAAAEABQDqDAAABQBNAG4MAAADACsAbwwAAAEAFgAAAA==.',
Po='Potter:BAABLgAECn9FAAIEAAkJbB9hFgC+AgloDAAACQBUAGkMAAAJAEwAawwAAAkAUgBqDAAACABBAGwMAAAIAF8AbQwAAAcASgDqDAAACQBQAG4MAAAGAEwAbwwAAAQASAAEAAkJbB9hFgC+AgloDAAACQBUAGkMAAAJAEwAawwAAAkAUgBqDAAACABBAGwMAAAIAF8AbQwAAAcASgDqDAAACQBQAG4MAAAGAEwAbwwAAAQASAAAAA==.',
Ra='Raffa:BAABLgAECn8jAAIUAAcJiB7vFADwAQdoDAAABQBWAGkMAAAEAE4AawwAAAUAJwBqDAAABQBUAGwMAAADAFgAbQwAAAIAUADqDAAACwBfABQABwmIHu8UAPABB2gMAAAFAFYAaQwAAAQATgBrDAAABQAnAGoMAAAFAFQAbAwAAAMAWABtDAAAAgBQAOoMAAALAF8AAAA=.Rakandei:BAAALgADCgMJAwAAAA==.Ramaylis:BAAALgADCgEJAQAAAA==.Raptor:BAABLgAFFH8JAAIEAAUJGRxlNQBhAQVoDAAAAgBTAGkMAAACADsAawwAAAIAMABqDAAAAQADAOoMAAACAF8ABAAFCRkcZTUAYQEFaAwAAAIAUwBpDAAAAgA7AGsMAAACADAAagwAAAEAAwDqDAAAAgBfAAAA.Rapunzel:BAAALgAECgkJBgAAAA==.Rataiga:BAAALgAECgYJEgAAAA==.',
Rh='Rheynah:BAABLgAECn8gAAMeAAkJ4QRsOwCvAAloDAAABgAIAGkMAAAFABIAawwAAAUADQBqDAAAAwAVAGwMAAADAA0AbQwAAAEACADqDAAABQAHAG4MAAADAAsAbwwAAAEAEQAFAAgJ/wO0UgDeAAhoDAAABQAIAGkMAAAEAA8AawwAAAQADQBqDAAAAgADAGwMAAACAAcA6gwAAAQABwBuDAAAAQABAG8MAAABABEAHgAICasDbDsArwAIaAwAAAEABABpDAAAAQASAGsMAAABAAQAagwAAAEAFQBsDAAAAQANAG0MAAABAAgA6gwAAAEAAwBuDAAAAgALAAAA.',
Ri='Rimuna:BAAALgADCgUJBQAAAA==.Rinni:BAACLgAFFH8aAAIQAAYJkyDcAADoAQZoDAAABgBeAGkMAAAFAF0AawwAAAQAUgBqDAAAAwBJAGwMAAABADYA6gwAAAcAXQAQAAYJkyDcAADoAQZoDAAABgBeAGkMAAAFAF0AawwAAAQAUgBqDAAAAwBJAGwMAAABADYA6gwAAAcAXQAuAAQKfy0AAhAACQkQJRUBADcDABAACQkQJRUBADcDAAAA.',
Ro='Rovintis:BAABLgAECn82AAIeAAgJpBpsCwAQAghoDAAACQBTAGkMAAAJAEsAawwAAAgATABqDAAABwBWAGwMAAAGAEQAbQwAAAQANgDqDAAACABUAG4MAAADACMAHgAICaQabAsAEAIIaAwAAAkAUwBpDAAACQBLAGsMAAAIAEwAagwAAAcAVgBsDAAABgBEAG0MAAAEADYA6gwAAAgAVABuDAAAAwAjAAAA.',
Ry='Rynne:BAABLgAECn8VAAQCAAgJCxQYQwB5AQhoDAAAAwA5AGkMAAAEACcAawwAAAMASQBqDAAAAwA7AGwMAAADADcAbQwAAAEABwBuDAAAAwAaAG8MAAABAFoAAgAHCdYRGEMAeQEHaAwAAAEAOQBpDAAAAQAnAGsMAAABAEkAagwAAAEAOwBsDAAAAQA3AG0MAAABAAcAbgwAAAEAGgAfAAcJ8AcBHAAKAQdoDAAAAgAYAGkMAAADABYAawwAAAIAGwBqDAAAAgAZAGwMAAACABAAbgwAAAEAEQBvDAAAAQAMAAMAAQlnAwyjAB0AAW4MAAABAAgAAAA=.',
Sa='Sansundertal:BAABLgAECn8wAAIKAAkJsSJ+AgBJAwloDAAABwBcAGkMAAAGAFEAawwAAAYAYQBqDAAABgBjAGwMAAAGAGAAbQwAAAQAWwDqDAAABwBjAG4MAAAEAFkAbwwAAAIAMgAKAAkJsSJ+AgBJAwloDAAABwBcAGkMAAAGAFEAawwAAAYAYQBqDAAABgBjAGwMAAAGAGAAbQwAAAQAWwDqDAAABwBjAG4MAAAEAFkAbwwAAAIAMgAAAA==.Sargeràs:BAAALgADCgcJDAABLgAECgQJBAABAAAAAA==.',
Se='Selissaroth:BAAALgAECgEJAQAAAA==.Sentinal:BAABLgAECn8tAAIbAAgJdxcZEwC4AQhoDAAABwBXAGkMAAAHAD0AawwAAAYAOwBqDAAABgBUAGwMAAAFAEMAbQwAAAMAHQDqDAAABwA5AG4MAAAEADkAGwAICXcXGRMAuAEIaAwAAAcAVwBpDAAABwA9AGsMAAAGADsAagwAAAYAVABsDAAABQBDAG0MAAADAB0A6gwAAAcAOQBuDAAABAA5AAAA.Sentinäl:BAAALgAECgIJAgAAAA==.Sephiro:BAAALgAECgQJBgAAAA==.',
Sh='Shamu:BAACLgAFFH8IAAICAAMJ9BDqOgDOAANoDAAABAAWAGkMAAABABIA6gwAAAMAWAACAAMJ9BDqOgDOAANoDAAABAAWAGkMAAABABIA6gwAAAMAWAAuAAQKfxoAAgIACQkNFTE7AJoBAAIACQkNFTE7AJoBAAAA.Shawner:BAAALgADCgMJAwAAAA==.Shy:BAAALgAECgUJCAAAAA==.',
Si='Silvertiger:BAABLgAECn9EAAMRAAkJ3h/bBADJAgloDAAACABYAGkMAAAJAFoAawwAAAkAUgBqDAAACABGAGwMAAAIAFQAbQwAAAcAUwDqDAAACQBEAG4MAAAGAFQAbwwAAAQARgARAAkJ3h/bBADJAgloDAAABwBYAGkMAAAHAFoAawwAAAcAUgBqDAAABwBGAGwMAAAHAFQAbQwAAAYAUwDqDAAABwBEAG4MAAAGAFQAbwwAAAQARgAgAAcJgg+dPABsAQdoDAAAAQAtAGkMAAACADMAawwAAAIAJABqDAAAAQASAGwMAAABACwAbQwAAAEAIADqDAAAAgAdAAAA.',
Sl='Slabbydabby:BAAALgAECgYJCgAAAA==.Sleeperbater:BAAALgADCgIJAgAAAA==.Sleeperdk:BAAALgAECgYJCwAAAA==.',
Sn='Snackyfraps:BAAALgAECgIJAgABLgAECgkJRQAaAD8fAA==.Sneaki:BAABLgAECn9DAAQhAAkJdyUGBADoAgloDAAACQBjAGkMAAAJAF8AawwAAAkAXABqDAAACABcAGwMAAAIAF0AbQwAAAYAYADqDAAACQBdAG4MAAAFAGMAbwwAAAQAYAAhAAkJ+SMGBADoAgloDAAACABjAGkMAAAIAF8AawwAAAgAXABqDAAABwBcAGwMAAACAD8AbQwAAAUAYADqDAAACABdAG4MAAAEAGMAbwwAAAQAYAAiAAgJ/RzeAwA0AghoDAAAAQBXAGkMAAABACsAawwAAAEARwBqDAAAAQBLAGwMAAABAF0AbQwAAAEAQQDqDAAAAQBPAG4MAAABAE4AEgABCbEj8RoAaQABbAwAAAUAWwAAAA==.Sniperanger:BAAALgADCgMJAwAAAA==.Snstr:BAABLgAECn8aAAQYAAYJbRfiLACTAQZoDAAABgBOAGkMAAAFAEgAawwAAAQATABqDAAAAwAaAGwMAAADACgA6gwAAAUAQAAYAAYJbRfiLACTAQZoDAAABQBOAGkMAAAEAEgAawwAAAMATABqDAAAAgAaAGwMAAACACgA6gwAAAQAQAAZAAQJ5gMhTQChAARpDAAAAQAGAGsMAAABAA4AagwAAAEADgBsDAAAAQAJABoAAgmRCFlNAF0AAmgMAAABAA4A6gwAAAEAHAAAAA==.',
So='Sorynia:BAABLgAECn8YAAIGAAgJnwYqdQAwAQhoDAAABAASAGkMAAAEABkAawwAAAQAGABqDAAABAAbAGwMAAABAAgAbQwAAAEABQDqDAAABAALAG4MAAACABgABgAICZ8GKnUAMAEIaAwAAAQAEgBpDAAABAAZAGsMAAAEABgAagwAAAQAGwBsDAAAAQAIAG0MAAABAAUA6gwAAAQACwBuDAAAAgAYAAAA.Soul:BAAALgAECgEJAQAAAA==.Soulkid:BAAALgAECgQJBQAAAA==.',
St='Starta:BAACLgAFFH8LAAITAAMJ5xkySADqAANoDAAABAA7AGkMAAADADwA6gwAAAQATgATAAMJ5xkySADqAANoDAAABAA7AGkMAAADADwA6gwAAAQATgAuAAQKfxsAAhMACAmNIf8mABgCABMACAmNIf8mABgCAAAA.Startawar:BAACLgAFFH8FAAINAAIJxhLJbACYAAJpDAAAAQAiAOoMAAAEAD0ADQACCcYSyWwAmAACaQwAAAEAIgDqDAAABAA9AC4ABAp/JAACDQAICccjLBYA5AIADQAICccjLBYA5AIAAAA=.Stormbeard:BAAALgAECgUJBQABLgAFFAYJFwANANwiAA==.',
Su='Sukii:BAAALgAECgUJBgAAAA==.Sulfuricvein:BAAALgAFFAEJAQAAAA==.',
['Sø']='Sømebody:BAAALgAECgQJBAAAAA==.',
Th='Thelandrius:BAAALgADCgIJAgAAAA==.',
Ti='Tiana:BAAALgAECgkJBAAAAA==.',
To='Totemdaddy:BAAALgAECgEJAQAAAA==.Totemicdidit:BAAALgADCgMJAwAAAA==.Totemstorm:BAAALgAECgcJBwAAAA==.',
Tr='Traumatic:BAABLgAECn8UAAIFAAcJjRj6LwDvAQdoDAAAAwBIAGkMAAAEAEUAawwAAAMAPwBqDAAAAwAfAGwMAAACADwA6gwAAAQASQBuDAAAAQAlAAUABwmNGPovAO8BB2gMAAADAEgAaQwAAAQARQBrDAAAAwA/AGoMAAADAB8AbAwAAAIAPADqDAAABABJAG4MAAABACUAAAA=.',
Tu='Tunny:BAAALgAECgYJCAAAAA==.Turnleft:BAACLgAFFH8FAAIjAAMJPByJKgD5AANoDAAAAgA9AGkMAAABAFAA6gwAAAIASgAjAAMJPByJKgD5AANoDAAAAgA9AGkMAAABAFAA6gwAAAIASgAuAAQKfzAAAyMACQlmIz8CAJ4DACMACQlmIz8CAJ4DACQAAQmCHnxoAFcAAAAA.',
Va='Valerïan:BAAALgADCgEJAQABLgAECgcJEwABAAAAAA==.Vauntmonk:BAAALgADCgMJAwABLgAFFAQJEQAlAFYhAA==.',
Ve='Vercyv:BAAALgADCgkJEQAAAA==.Vevio:BAAALgAECgQJBAAAAA==.',
Vi='Video:BAAALgAECgEJAQAAAA==.Violet:BAACLgAFFH8GAAIOAAMJABm4bgDzAANoDAAAAwBFAGkMAAACAEsA6gwAAAEALgAOAAMJABm4bgDzAANoDAAAAwBFAGkMAAACAEsA6gwAAAEALgAuAAQKfzAAAg4ACQkzH1gMAPICAA4ACQkzH1gMAPICAAAA.Vishlock:BAABLgAECn8xAAMVAAkJhBmGBQADAgloDAAABgBQAGkMAAAGADsAawwAAAYANwBqDAAABQA1AGwMAAAFAEsAbQwAAAQAGwDqDAAABwBMAG4MAAAGAFkAbwwAAAQAOQAVAAkJhBmGBQADAgloDAAABQBQAGkMAAAGADsAawwAAAUANwBqDAAAAwA1AGwMAAAEAEsAbQwAAAIAGwDqDAAABQBMAG4MAAADAFkAbwwAAAMAOQAMAAgJ8w4OlAAwAQhoDAAAAQARAGsMAAABACAAagwAAAIACgBsDAAAAQBBAG0MAAACABEA6gwAAAIAQQBuDAAAAwAXAG8MAAABAC4AAAA=.',
Vo='Voddie:BAABLgAECn8gAAIDAAkJPgw9LABwAQloDAAABgAdAGkMAAAGABoAawwAAAYAHgBqDAAAAwALAGwMAAADABUAbQwAAAEACQDqDAAABAAeAG4MAAACAFQAbwwAAAEAEgADAAkJPgw9LABwAQloDAAABgAdAGkMAAAGABoAawwAAAYAHgBqDAAAAwALAGwMAAADABUAbQwAAAEACQDqDAAABAAeAG4MAAACAFQAbwwAAAEAEgAAAA==.Votarick:BAAALgAECgEJAQAAAA==.',
Wa='Waban:BAAALgAECgcJEwAAAA==.Walmarthas:BAAALgAECgcJDQABLgAECgkJHQAIAEkUAA==.Wapta:BAAALgAFFAEJAQABLgAFFAUJCQAEABkcAA==.',
Wi='Wizwiztheliz:BAAALgAECgYJDwAAAA==.',
Wo='Wolf:BAABLgAECn8cAAImAAgJOxAOJQBrAQhoDAAABgAwAGkMAAAFACcAawwAAAUAIABqDAAAAwAbAGwMAAACADEAbQwAAAEABwDqDAAABAA2AG4MAAACADoAJgAICTsQDiUAawEIaAwAAAYAMABpDAAABQAnAGsMAAAFACAAagwAAAMAGwBsDAAAAgAxAG0MAAABAAcA6gwAAAQANgBuDAAAAgA6AAEuAAUUAwkEAAEAAAAA.Woof:BAAALgAECgIJAgAAAA==.',
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
