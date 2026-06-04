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

local lookup = {'DemonHunter-Devourer','DeathKnight-Unholy','DemonHunter-Havoc','DemonHunter-Vengeance','Monk-Windwalker','Monk-Mistweaver','Unknown-Unknown','Monk-Brewmaster','Mage-Frost','Druid-Restoration','Priest-Holy','DeathKnight-Frost','Paladin-Retribution','Druid-Feral','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Evoker-Augmentation','Evoker-Devastation','Hunter-Marksmanship','Hunter-BeastMastery','Rogue-Assassination','Evoker-Preservation','DeathKnight-Blood','Paladin-Protection','Warrior-Fury','Warrior-Protection',}
local provider = {region='US',realm='WyrmrestAccord',name='US',type='subscribers',zone=46,date='2026-06-03',data={Ag='Aggrodari:BAECLgAFFH8SAAIBAAQJOSQuGwCuAQRoDAAABgBjAGkMAAAFAGMAawwAAAMATADqDAAABABfAAEABAk5JC4bAK4BBGgMAAAGAGMAaQwAAAUAYwBrDAAAAwBMAOoMAAAEAF8ALgAECn9GAAIBAAgJliZLBwAPAwABAAgJliZLBwAPAwAAAA==.Aggrorunner:BAEALgADCgMJBQABLgAFFAQJEgABADkkAA==.',
An='Anuhkin:BAEALgADCgUJBQABLgAFFAUJEAACALwhAA==.',
Ar='Archoknot:BAEALgAECgQJCwAAAA==.Arcis:BAECLgAFFH8HAAIDAAMJWBhfEgD0AANoDAAAAwBFAGkMAAACAFIA6gwAAAIAIgADAAMJWBhfEgD0AANoDAAAAwBFAGkMAAACAFIA6gwAAAIAIgAuAAQKfxcABAMACAnfHQ0PAB4CAAMABgnqHg0PAB4CAAEABgm3D9WJAPoAAAQABAlqFX0UAPgAAAAA.',
Bj='Bjørnulf:BAEALgAECgYJCwAAAA==.',
Bo='Bowbafletch:BAEALgAFFAEJAQABLgAFFAUJEAACALwhAA==.',
Br='Breadroll:BAECLgAFFH8GAAIFAAIJviFzJACxAAJoDAAAAgBWAOoMAAAEAFYABQACCb4hcyQAsQACaAwAAAIAVgDqDAAABABWAC4ABAp/HgADBQAJCdwh7wIAaAMABQAJCdwh7wIAaAMABgAECWUd0T8ASgEAAAA=.Brendemøn:BAEALgAECgYJCwAAAA==.Brêndêath:BAEALgAECgYJCgABLgAECgYJCwAHAAAAAA==.',
Ca='Caedues:BAECLgAFFH8QAAICAAUJvCFJTABCAQVoDAAABABfAGkMAAAEAFsAawwAAAMAVQBqDAAAAQBGAOoMAAAEAEgAAgAFCbwhSUwAQgEFaAwAAAQAXwBpDAAABABbAGsMAAADAFUAagwAAAEARgDqDAAABABIAC4ABAp/IQACAgAJCdAhfBMABgMAAgAJCdAhfBMABgMAAAA=.',
Ch='Chaosity:BAEALgAECgcJEgABLgAECgkJIQAIAEUdAA==.Cheeseburber:BAEALgADCgMJAwABLgAECgQJEAAHAAAAAA==.',
Dr='Drommekage:BAEBLgAECn8bAAIJAAcJuQZzwgD8AAdoDAAABQANAGkMAAAFABQAawwAAAUAIwBqDAAABAATAGwMAAADAA8AbQwAAAEABgDqDAAABAAMAAkABwm5BnPCAPwAB2gMAAAFAA0AaQwAAAUAFABrDAAABQAjAGoMAAAEABMAbAwAAAMADwBtDAAAAQAGAOoMAAAEAAwAAAA=.',
El='Elvarg:BAEALgAECgEJAQABLgAECgcJFQAKAEIbAA==.',
En='Enneth:BAEALgADCgQJBAAAAA==.',
Ev='Eviecera:BAEALgADCgUJBQABLgAFFAYJBQALAEofAA==.',
Ex='Exesa:BAEBLgAECn8WAAMCAAgJABUfYACcAQhoDAAAAwBAAGkMAAADADQAawwAAAIAKgBqDAAAAwBiAGwMAAADAEMAbQwAAAIAKwDqDAAAAgAyAG4MAAAEADYAAgAICa8RH2AAnAEIaAwAAAIAQABpDAAAAgArAGsMAAABABIAagwAAAMAYgBsDAAAAwBDAG0MAAACACsA6gwAAAEAIABuDAAAAwAtAAwABQmGE6cSADYBBWgMAAABADEAaQwAAAEANABrDAAAAQAqAOoMAAABADIAbgwAAAEANgAAAA==.',
Fe='Fedja:BAEALgAECggJEQABLgAECgcJJQANAKEYAA==.',
He='Henbolt:BAEALgAFFAEJAwABLgADCgEJAQAHAAAAAA==.Henpaw:BAEALgAFFAEJAwABLgADCgEJAQAHAAAAAA==.Henscale:BAEALgAECgEJAQABLgADCgEJAQAHAAAAAQ==.Henseng:BAEALgADCgEJAQAAAA==.Hensurge:BAEALgAFFAEJAgABLgADCgEJAQAHAAAAAA==.',
Hi='Hirenar:BAEALgAECgEJAgABLgAFFAUJEAACALwhAA==.',
['Hâ']='Hâstery:BAEALgAECggJBwABLgAFFAUJCgAOADkcAA==.',
Il='Illothe:BAECLgAFFH8iAAQPAAcJVhaYIgCTAQdoDAAABgBZAGkMAAAFAFkAawwAAAYAQgBqDAAABQBCAGwMAAADACoAbQwAAAIAAwDqDAAABwAzAA8ABgmOGpgiAJMBBmgMAAAGAFkAaQwAAAMAWQBrDAAABgBCAGoMAAAFAEIAbAwAAAMAKgDqDAAABwAzABAAAgnLAOsiAEgAAmkMAAABAAAAbQwAAAIAAwARAAEJoAnqIgBHAAFpDAAAAQAYAC4ABAp/KgADDwAJCV8hBRIA6wIADwAICfoiBRIA6wIAEAADCRMV0jcA1gAAAAA=.Illothedh:BAEALgADCgMJAwABLgAFFAcJIgAPAFYWAA==.',
In='Insouciantly:BAEALgAECgIJAgABLgAECgcJGAALAIgjAA==.',
Ir='Irreverently:BAEBLgAECn8YAAILAAcJiCMrEgBPAgdoDAAABABNAGkMAAAEAFkAawwAAAQAWgBqDAAAAgBhAGwMAAADAFoAbQwAAAEAYADqDAAABgBgAAsABwmIIysSAE8CB2gMAAAEAE0AaQwAAAQAWQBrDAAABABaAGoMAAACAGEAbAwAAAMAWgBtDAAAAQBgAOoMAAAGAGAAAAA=.',
Jl='Jlucks:BAECLgAFFH8lAAISAAcJWSO5BgBlAgdoDAAABwBiAGkMAAAGAFgAawwAAAYAWwBqDAAABgBaAGwMAAACAFsA6gwAAAkAYABuDAAAAQBNABIABwlZI7kGAGUCB2gMAAAHAGIAaQwAAAYAWABrDAAABgBbAGoMAAAGAFoAbAwAAAIAWwDqDAAACQBgAG4MAAABAE0ALgAECn9PAAMSAAkJgia+AACEAwASAAkJgia+AACEAwATAAEJjR1CHQBYAAAAAA==.Jlucksdh:BAECLgAFFH8hAAIBAAUJqiSsHQCeAQVoDAAACwBgAGkMAAAJAF8AawwAAAQAVQBqDAAAAgA7AOoMAAAHAGIAAQAFCaokrB0AngEFaAwAAAsAYABpDAAACQBfAGsMAAAEAFUAagwAAAIAOwDqDAAABwBiAC4ABAp/TwACAQAJCSglFQQAPgMAAQAJCSglFQQAPgMAAS4ABRQHCSUAEgBZIwA=.Jluckshnt:BAEBLgAFFH8GAAIUAAMJJxtbFQD4AANoDAAAAgA+AGkMAAACAFEA6gwAAAIAQAAUAAMJJxtbFQD4AANoDAAAAgA+AGkMAAACAFEA6gwAAAIAQAABLgAFFAcJJQASAFkjAA==.Jlucksmk:BAEBLgAECn9KAAMGAAcJpyW5CQDnAgdoDAAADQBhAGkMAAAMAGIAawwAAAwAYgBqDAAADABjAGwMAAAKAGIAbQwAAAIAUwDqDAAADQBjAAYABwmnJbkJAOcCB2gMAAANAGEAaQwAAAwAYgBrDAAADABiAGoMAAAKAGMAbAwAAAoAYgBtDAAAAgBTAOoMAAAKAGMACAACCYAHiZsAIAACagwAAAIAGgDqDAAAAwATAAEuAAUUBwklABIAWSMA.',
Kr='Kred:BAEALgADCgYJBgABLgAECgkJSAAVAI4iAA==.Kredrothi:BAEBLgAECn9IAAIVAAkJjiL0DADdAgloDAAACgBfAGkMAAAJAGEAawwAAAkAWABqDAAACABgAGwMAAAIAEwAbQwAAAcATADqDAAACgBXAG4MAAAHAF0AbwwAAAQAWwAVAAkJjiL0DADdAgloDAAACgBfAGkMAAAJAGEAawwAAAkAWABqDAAACABgAGwMAAAIAEwAbQwAAAcATADqDAAACgBXAG4MAAAHAF0AbwwAAAQAWwAAAA==.',
Ku='Kunha:BAEALgADCgkJCQABLgAFFAIJAwAHAAAAAA==.',
La='Laghar:BAEALgAECgEJAQAAAA==.',
Ma='Magicracoon:BAEALgAECgQJEAAAAA==.Malzbier:BAEALgAECggJDAABLgAFFAUJEAACALwhAA==.Marosia:BAEALgAECgYJCQABLgAECggJIwAWAJQhAA==.Marroc:BAEBLgAECn8jAAIWAAgJlCHzAgCFAghoDAAABgBhAGkMAAAFAF4AawwAAAUAWQBqDAAABQBLAGwMAAADAEUAbQwAAAIAXgDqDAAABgBjAG4MAAADADoAFgAICZQh8wIAhQIIaAwAAAYAYQBpDAAABQBeAGsMAAAFAFkAagwAAAUASwBsDAAAAwBFAG0MAAACAF4A6gwAAAYAYwBuDAAAAwA6AAAA.',
Ne='Nekun:BAEALgAECgMJBgABLgAECgMJBgAHAAAAAA==.',
Ni='Nitedragon:BAEBLgAECn8UAAIXAAcJUCCGBwByAgdoDAAAAwBcAGkMAAADAFUAawwAAAMASABqDAAAAwBSAGwMAAADAFcA6gwAAAQAWABuDAAAAQBEABcABwlQIIYHAHICB2gMAAADAFwAaQwAAAMAVQBrDAAAAwBIAGoMAAADAFIAbAwAAAMAVwDqDAAABABYAG4MAAABAEQAAAA=.',
['Nì']='Nìte:BAEALgAECgcJCAABLgAECgcJFAAXAFAgAA==.',
Or='Oracs:BAEBLgAECn8VAAQSAAcJ6h9WGAAPAgdoDAAAAwBNAGkMAAADAFgAawwAAAMAXABqDAAABABZAGwMAAADAFIA6gwAAAQAWgBuDAAAAQA6ABIABglgH1YYAA8CBmgMAAABAEoAaQwAAAEAUwBrDAAAAQBcAGwMAAADAFIA6gwAAAIAWgBuDAAAAQA6ABMABQkkHRgXAIQBBWgMAAABAE0AaQwAAAEAWABrDAAAAQBNAGoMAAAEAFkA6gwAAAEANgAXAAQJdAQLOQCiAARoDAAAAQAGAGkMAAABABIAawwAAAEAAwDqDAAAAQAQAAEuAAUUBQkQAAIAvCEA.',
Pa='Pai:BAEALgAFFAIJAwABLgAFFAIJBgAFAL4hAA==.',
Pi='Pickups:BAECLgAFFH8HAAIBAAMJtBd4UwDcAANoDAAAAgA5AGkMAAABADYA6gwAAAQARQABAAMJtBd4UwDcAANoDAAAAgA5AGkMAAABADYA6gwAAAQARQAuAAQKfyIAAwQACAmzG0IHABQCAAQABwm/GUIHABQCAAEABwn/FIZ0ACgBAAEuAAUUCAkfAAkAYxwA.',
Qa='Qahz:BAECLgAFFH8OAAIPAAQJlxUyOQBGAQRoDAAABABRAGkMAAAEAFoAawwAAAMAHQDqDAAAAwATAA8ABAmXFTI5AEYBBGgMAAAEAFEAaQwAAAQAWgBrDAAAAwAdAOoMAAADABMALgAECn8rAAIPAAcJ4CFXJgB5AgAPAAcJ4CFXJgB5AgABLgAFFAQJEgABADkkAA==.',
Ru='Ruehnar:BAEALgAECgYJDwABLgAECgcJJQANAKEYAA==.',
Ry='Ryenth:BAEALgAECgEJAgABLgAECgkJIQAIAEUdAA==.',
Si='Sixul:BAEBLgAFFH8JAAIWAAQJ7RHaBAAtAQRoDAAABAA9AGkMAAADAEEAawwAAAEAFADqDAAAAQAkABYABAntEdoEAC0BBGgMAAAEAD0AaQwAAAMAQQBrDAAAAQAUAOoMAAABACQAAAA=.',
St='Startut:BAEALgAECgIJBAAAAA==.Stiffbow:BAEALgADCgQJBAABLgAECggJKgAVAIcWAA==.',
Ta='Taylorquick:BAEALgAECgcJDQAAAA==.Tazukey:BAEBLgAECn8VAAIKAAcJQht5OgC8AQdoDAAABQBgAGkMAAAEAFMAawwAAAQAUgBqDAAAAgBMAGwMAAABADsA6gwAAAQARgBuDAAAAQATAAoABwlCG3k6ALwBB2gMAAAFAGAAaQwAAAQAUwBrDAAABABSAGoMAAACAEwAbAwAAAEAOwDqDAAABABGAG4MAAABABMAAAA=.',
Te='Tenisia:BAEALgAECgcJDgAAAA==.',
Th='Theò:BAEALgADCgMJBAAAAA==.',
Ti='Titanbp:BAEALgADCgYJCQABLgAFFAgJJgAYAJ8eAA==.Titandb:BAECLgAFFH8mAAIYAAgJnx4XAgCBAghoDAAACABgAGkMAAAHAGIAawwAAAYAYQBqDAAABQBVAGwMAAABAE4AbQwAAAEAHgDqDAAACQBeAG4MAAABADQAGAAICZ8eFwIAgQIIaAwAAAgAYABpDAAABwBiAGsMAAAGAGEAagwAAAUAVQBsDAAAAQBOAG0MAAABAB4A6gwAAAkAXgBuDAAAAQA0AC4ABAp/LQACGAAJCSwjRwQA5gIAGAAJCSwjRwQA5gIAAAA=.Titanpp:BAEALgADCgQJCAABLgAFFAgJJgAYAJ8eAA==.',
Va='Valynithira:BAECLgAFFH8fAAIJAAgJYxyZCgBxAghoDAAABQBiAGkMAAAFAGAAawwAAAYATQBqDAAABABcAGwMAAADAE4AbQwAAAEAGgDqDAAABgBdAG4MAAABACUACQAICWMcmQoAcQIIaAwAAAUAYgBpDAAABQBgAGsMAAAGAE0AagwAAAQAXABsDAAAAwBOAG0MAAABABoA6gwAAAYAXQBuDAAAAQAlAC4ABAp/LgACCQAICeYlpQ8ASwMACQAICeYlpQ8ASwMAAAA=.',
Ve='Velanyr:BAEBLgAECn8dAAIPAAkJoh38LgAUAgloDAAABQBOAGkMAAAEADgAawwAAAQARQBqDAAAAwBRAGwMAAADAFEAbQwAAAIAXwDqDAAABQBQAG4MAAACAEsAbwwAAAEARgAPAAkJoh38LgAUAgloDAAABQBOAGkMAAAEADgAawwAAAQARQBqDAAAAwBRAGwMAAADAFEAbQwAAAIAXwDqDAAABQBQAG4MAAACAEsAbwwAAAEARgAAAA==.',
Vi='Viridessia:BAEBLgAECn81AAQSAAkJqRnoHgDVAQloDAAACQBEAGkMAAAIADgAawwAAAgARQBqDAAABgA+AGwMAAAGAEQAbQwAAAIAGwDqDAAACQBYAG4MAAAEAEQAbwwAAAEATgASAAgJrxboHgDVAQhoDAAAAwAtAGkMAAADACcAawwAAAMARQBqDAAAAQAEAGwMAAACABAA6gwAAAUAWABuDAAABABEAG8MAAABAE4AEwAHCTUWqAkAfQEHaAwAAAYARABpDAAABQA4AGsMAAAFAEIAagwAAAQAPgBsDAAABABEAG0MAAACABsA6gwAAAQANQAXAAEJ1QerOwAoAAFqDAAAAQAUAAEuAAQKCQkhAAgARR0A.',
Vl='Vladja:BAEBLgAECn8lAAMNAAcJoRjlbwCAAQdoDAAABgBIAGkMAAAGADMAawwAAAYARwBqDAAABQBQAGwMAAAFAEUAbQwAAAEAHQDqDAAACABTAA0ABgk/G+VvAIABBmgMAAAGAEgAaQwAAAYAMwBrDAAABgBHAGoMAAAFAFAAbAwAAAUARQDqDAAACABTABkAAQmKCyVLAC8AAW0MAAABAB0AAAA=.',
Yi='Yiangchen:BAEBLgAECn8hAAIIAAkJRR3qCACZAgloDAAABABWAGkMAAAEAFsAawwAAAQAOABqDAAABQBWAGwMAAAFAFIAbQwAAAIANwDqDAAABABCAG4MAAAEAEQAbwwAAAEAXAAIAAkJRR3qCACZAgloDAAABABWAGkMAAAEAFsAawwAAAQAOABqDAAABQBWAGwMAAAFAFIAbQwAAAIANwDqDAAABABCAG4MAAAEAEQAbwwAAAEAXAAAAA==.',
Zi='Zirkondrake:BAEBLgAECn9AAAMaAAgJSiPgBwDXAghoDAAACgBbAGkMAAALAGIAawwAAAkAVwBqDAAACQBiAGwMAAAHAGEAbQwAAAMAUQDqDAAACgBdAG4MAAAFAFIAGgAICUoj4AcA1wIIaAwAAAkAWwBpDAAACQBiAGsMAAAIAFcAagwAAAcAYgBsDAAABgBhAG0MAAACAFEA6gwAAAgAXQBuDAAABABSABsACAmmG2sLACYCCGgMAAABAEUAaQwAAAIAVgBrDAAAAQBNAGoMAAACAFoAbAwAAAEAOwBtDAAAAQAlAOoMAAACAFoAbgwAAAEATAAAAA==.',
Zy='Zylphian:BAEBLgAECn8qAAIVAAgJhxYwLgD5AQhoDAAABwBHAGkMAAAFADUAawwAAAQAKQBqDAAABQA8AGwMAAAFAC4AbQwAAAQAIQDqDAAABwBUAG4MAAAFAEcAFQAICYcWMC4A+QEIaAwAAAcARwBpDAAABQA1AGsMAAAEACkAagwAAAUAPABsDAAABQAuAG0MAAAEACEA6gwAAAcAVABuDAAABQBHAAAA.',
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
