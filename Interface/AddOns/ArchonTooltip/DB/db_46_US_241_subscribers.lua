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

local lookup = {'DemonHunter-Devourer','DeathKnight-Unholy','DemonHunter-Havoc','DemonHunter-Vengeance','Monk-Windwalker','Monk-Mistweaver','Unknown-Unknown','Evoker-Devastation','Mage-Frost','Druid-Restoration','Priest-Holy','Paladin-Retribution','Druid-Feral','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Evoker-Augmentation','Monk-Brewmaster','Hunter-BeastMastery','Rogue-Assassination','Evoker-Preservation','DeathKnight-Blood','Warrior-Fury','Warrior-Protection',}
local provider = {region='US',realm='WyrmrestAccord',name='US',type='subscribers',zone=46,date='2026-05-29',data={Ag='Aggrodari:BAECLgAFFH8PAAIBAAQJBCTYGQCiAQRoDAAABQBjAGkMAAAEAGMAawwAAAIASQDqDAAABABfAAEABAkEJNgZAKIBBGgMAAAFAGMAaQwAAAQAYwBrDAAAAgBJAOoMAAAEAF8ALgAECn8+AAIBAAgJjiaXBwAEAwABAAgJjiaXBwAEAwAAAA==.Aggrorunner:BAEALgADCgMJBQABLgAFFAQJDwABAAQkAA==.',
An='Anuhkin:BAEALgADCgUJBQABLgAFFAUJEAACALwhAA==.',
Ar='Archoknot:BAEALgAECgQJCwAAAA==.Arcis:BAEBLgAECn8VAAQDAAgJ6xsEHAB4AQhoDAAABAA4AGkMAAADADcAawwAAAMAPABqDAAAAQA7AGwMAAACAFoAbQwAAAEASgDqDAAABgBPAG4MAAABAFQAAwAECQsgBBwAeAEEbAwAAAEAWgBtDAAAAQBKAOoMAAACAE8AbgwAAAEAVAAEAAQJahWtEwD4AARoDAAAAQA4AGkMAAABADcAawwAAAEAPADqDAAAAQAvAAEABgm3D5+EAPcABmgMAAADAC0AaQwAAAIAIQBrDAAAAgAaAGoMAAABADsAbAwAAAEAMADqDAAAAwAvAAAA.',
Bj='Bjørnulf:BAEALgAECgYJCwAAAA==.',
Bo='Bowbafletch:BAEALgAFFAEJAQABLgAFFAUJEAACALwhAA==.',
Br='Breadroll:BAECLgAFFH8GAAIFAAIJviHPIQCzAAJoDAAAAgBWAOoMAAAEAFYABQACCb4hzyEAswACaAwAAAIAVgDqDAAABABWAC4ABAp/HgADBQAJCdwh7wIAaAMABQAJCdwh7wIAaAMABgAECWUdujsASgEAAAA=.Brendemøn:BAEALgAECgYJCwAAAA==.Brêndêath:BAEALgAECgYJCgABLgAECgYJCwAHAAAAAA==.',
Ca='Caedues:BAECLgAFFH8QAAICAAUJvCGKRABFAQVoDAAABABfAGkMAAAEAFsAawwAAAMAVQBqDAAAAQBGAOoMAAAEAEgAAgAFCbwhikQARQEFaAwAAAQAXwBpDAAABABbAGsMAAADAFUAagwAAAEARgDqDAAABABIAC4ABAp/IQACAgAJCdAhfBMABgMAAgAJCdAhfBMABgMAAAA=.',
Ch='Chaosity:BAEALgAECgcJEgABLgAECgkJNAAIAEEYAA==.Cheeseburber:BAEALgADCgMJAwABLgAECgQJEAAHAAAAAA==.',
Dr='Drommekage:BAEBLgAECn8bAAIJAAcJuQbnwQDnAAdoDAAABQANAGkMAAAFABQAawwAAAUAIwBqDAAABAATAGwMAAADAA8AbQwAAAEABgDqDAAABAAMAAkABwm5BufBAOcAB2gMAAAFAA0AaQwAAAUAFABrDAAABQAjAGoMAAAEABMAbAwAAAMADwBtDAAAAQAGAOoMAAAEAAwAAAA=.',
El='Eliraina:BAEALgAECgkJEwAAAA==.Elvarg:BAEALgAECgEJAQABLgAECgcJFQAKAEIbAA==.',
En='Enneth:BAEALgADCgQJBAAAAA==.',
Ev='Eviecera:BAEALgADCgUJBQABLgAFFAYJBQALAEofAA==.',
Ex='Exesa:BAEALgAECggJEAAAAA==.',
Fe='Fedja:BAEALgAECggJEQABLgAECgYJJAAMAD8bAA==.',
He='Henbolt:BAEALgAFFAEJAgABLgADCgEJAQAHAAAAAA==.Henpaw:BAEALgAFFAEJAwABLgADCgEJAQAHAAAAAA==.Henscale:BAEALgAECgEJAQABLgADCgEJAQAHAAAAAQ==.Henseng:BAEALgADCgEJAQAAAA==.Hensurge:BAEALgAFFAEJAgABLgADCgEJAQAHAAAAAA==.',
Hi='Hirenar:BAEALgAECgEJAgABLgAFFAUJEAACALwhAA==.',
['Hâ']='Hâstery:BAEALgAECggJBwABLgAFFAUJCgANADkcAA==.',
Il='Illothe:BAECLgAFFH8iAAQOAAcJVhZTHACgAQdoDAAABgBZAGkMAAAFAFkAawwAAAYAQgBqDAAABQBCAGwMAAADACoAbQwAAAIAAwDqDAAABwAzAA4ABgmOGlMcAKABBmgMAAAGAFkAaQwAAAMAWQBrDAAABgBCAGoMAAAFAEIAbAwAAAMAKgDqDAAABwAzAA8AAQmgCXAfAEkAAWkMAAABABgAEAACCcsAViEASAACaQwAAAEAAABtDAAAAgADAC4ABAp/KgADDgAJCV8hBRIA6wIADgAICfoiBRIA6wIAEAADCRMV0jcA1gAAAAA=.Illothedh:BAEALgADCgMJAwABLgAFFAcJIgAOAFYWAA==.',
In='Insouciantly:BAEALgAECgIJAgABLgAECgcJGAALAIgjAA==.',
Ir='Irreverently:BAEBLgAECn8YAAILAAcJiCMrEgBPAgdoDAAABABNAGkMAAAEAFkAawwAAAQAWgBqDAAAAgBhAGwMAAADAFoAbQwAAAEAYADqDAAABgBgAAsABwmIIysSAE8CB2gMAAAEAE0AaQwAAAQAWQBrDAAABABaAGoMAAACAGEAbAwAAAMAWgBtDAAAAQBgAOoMAAAGAGAAAAA=.',
Jl='Jlucks:BAECLgAFFH8jAAIRAAcJWSNrBQBwAgdoDAAABwBiAGkMAAAGAFgAawwAAAYAWwBqDAAABgBaAGwMAAACAFsA6gwAAAcAYABuDAAAAQBNABEABwlZI2sFAHACB2gMAAAHAGIAaQwAAAYAWABrDAAABgBbAGoMAAAGAFoAbAwAAAIAWwDqDAAABwBgAG4MAAABAE0ALgAECn9NAAIRAAkJgiagAAB7AwARAAkJgiagAAB7AwAAAA==.Jlucksdh:BAECLgAFFH8hAAIBAAUJqiSpGQCjAQVoDAAACwBgAGkMAAAJAF8AawwAAAQAVQBqDAAAAgA7AOoMAAAHAGIAAQAFCaokqRkAowEFaAwAAAsAYABpDAAACQBfAGsMAAAEAFUAagwAAAIAOwDqDAAABwBiAC4ABAp/TwACAQAJCSglygMAOwMAAQAJCSglygMAOwMAAS4ABRQHCSMAEQBZIwA=.Jlucksmk:BAEBLgAECn9KAAMGAAcJpyUMCQDnAgdoDAAADQBhAGkMAAAMAGIAawwAAAwAYgBqDAAADABjAGwMAAAKAGIAbQwAAAIAUwDqDAAADQBjAAYABwmnJQwJAOcCB2gMAAANAGEAaQwAAAwAYgBrDAAADABiAGoMAAAKAGMAbAwAAAoAYgBtDAAAAgBTAOoMAAAKAGMAEgACCYAHgJcAIAACagwAAAIAGgDqDAAAAwATAAEuAAUUBwkjABEAWSMA.',
Kr='Kred:BAEALgADCgYJBgABLgAECgkJRAATAI4iAA==.Kredrothi:BAEBLgAECn9EAAITAAkJjiJADADcAgloDAAACQBfAGkMAAAJAGEAawwAAAkAWABqDAAACABgAGwMAAAIAEwAbQwAAAcATADqDAAACQBXAG4MAAAGAF0AbwwAAAMAWwATAAkJjiJADADcAgloDAAACQBfAGkMAAAJAGEAawwAAAkAWABqDAAACABgAGwMAAAIAEwAbQwAAAcATADqDAAACQBXAG4MAAAGAF0AbwwAAAMAWwAAAA==.',
Ku='Kunha:BAEALgADCgkJCQABLgAFFAIJAwAHAAAAAA==.',
La='Laghar:BAEALgAECgEJAQAAAA==.',
Ma='Magicracoon:BAEALgAECgQJEAAAAA==.Malzbier:BAEALgAECggJDAABLgAFFAUJEAACALwhAA==.Marosia:BAEALgAECgYJCQABLgAECggJIwAUAJQhAA==.Marroc:BAEBLgAECn8jAAIUAAgJlCHBAgCIAghoDAAABgBhAGkMAAAFAF4AawwAAAUAWQBqDAAABQBLAGwMAAADAEUAbQwAAAIAXgDqDAAABgBjAG4MAAADADoAFAAICZQhwQIAiAIIaAwAAAYAYQBpDAAABQBeAGsMAAAFAFkAagwAAAUASwBsDAAAAwBFAG0MAAACAF4A6gwAAAYAYwBuDAAAAwA6AAAA.',
Ne='Nekun:BAEALgAECgMJBgABLgAECgMJBgAHAAAAAA==.',
Ni='Nitedragon:BAEBLgAECn8UAAIVAAcJUCA5BwByAgdoDAAAAwBcAGkMAAADAFUAawwAAAMASABqDAAAAwBSAGwMAAADAFcA6gwAAAQAWABuDAAAAQBEABUABwlQIDkHAHICB2gMAAADAFwAaQwAAAMAVQBrDAAAAwBIAGoMAAADAFIAbAwAAAMAVwDqDAAABABYAG4MAAABAEQAAAA=.',
No='Noellia:BAEALgAECgcJDgABLgAECgkJEwAHAAAAAA==.',
['Nì']='Nìte:BAEALgAECgcJBwABLgAECgcJFAAVAFAgAA==.',
Or='Oracs:BAEBLgAECn8VAAQRAAcJ6h9WGAAPAgdoDAAAAwBNAGkMAAADAFgAawwAAAMAXABqDAAABABZAGwMAAADAFIA6gwAAAQAWgBuDAAAAQA6ABEABglgH1YYAA8CBmgMAAABAEoAaQwAAAEAUwBrDAAAAQBcAGwMAAADAFIA6gwAAAIAWgBuDAAAAQA6AAgABQkkHRgXAIQBBWgMAAABAE0AaQwAAAEAWABrDAAAAQBNAGoMAAAEAFkA6gwAAAEANgAVAAQJdAQLOQCiAARoDAAAAQAGAGkMAAABABIAawwAAAEAAwDqDAAAAQAQAAEuAAUUBQkQAAIAvCEA.',
Pa='Pai:BAEALgAFFAIJAwABLgAFFAIJBgAFAL4hAA==.',
Pi='Pickups:BAECLgAFFH8HAAIBAAMJtBckTgDdAANoDAAAAgA5AGkMAAABADYA6gwAAAQARQABAAMJtBckTgDdAANoDAAAAgA5AGkMAAABADYA6gwAAAQARQAuAAQKfyIAAwQACAmzG0IHABQCAAQABwm/GUIHABQCAAEABwn/FBhvACgBAAEuAAUUCAkfAAkAYxwA.',
Qa='Qahz:BAECLgAFFH8LAAIOAAQJLRMyPAA5AQRoDAAAAwA4AGkMAAADAFoAawwAAAIAHQDqDAAAAwATAA4ABAktEzI8ADkBBGgMAAADADgAaQwAAAMAWgBrDAAAAgAdAOoMAAADABMALgAECn8pAAIOAAcJ4CFXJgB5AgAOAAcJ4CFXJgB5AgABLgAFFAQJDwABAAQkAA==.',
Ru='Ruehnar:BAEALgAECgYJDwABLgAECgYJJAAMAD8bAA==.',
Ry='Ryenth:BAEALgAECgEJAQABLgAECgkJNAAIAEEYAA==.',
Si='Simantha:BAEALgAECgYJDwABLgAECgkJEwAHAAAAAA==.Sixul:BAEBLgAFFH8JAAIUAAQJ7RF/BAAwAQRoDAAABAA9AGkMAAADAEEAawwAAAEAFADqDAAAAQAkABQABAntEX8EADABBGgMAAAEAD0AaQwAAAMAQQBrDAAAAQAUAOoMAAABACQAAAA=.',
St='Startut:BAEALgAECgIJBAAAAA==.Stiffbow:BAEALgADCgQJBAABLgAECggJKAATAK4UAA==.',
Ta='Taylorquick:BAEALgAECgcJDQAAAA==.Tazukey:BAEBLgAECn8VAAIKAAcJQht5OgC8AQdoDAAABQBgAGkMAAAEAFMAawwAAAQAUgBqDAAAAgBMAGwMAAABADsA6gwAAAQARgBuDAAAAQATAAoABwlCG3k6ALwBB2gMAAAFAGAAaQwAAAQAUwBrDAAABABSAGoMAAACAEwAbAwAAAEAOwDqDAAABABGAG4MAAABABMAAAA=.',
Te='Tenisia:BAEALgAECgcJDgAAAA==.',
Th='Theò:BAEALgADCgMJBAAAAA==.',
Ti='Titanbp:BAEALgADCgYJCQABLgAFFAgJJgAWAJ8eAA==.Titandb:BAECLgAFFH8mAAIWAAgJnx6tAQCEAghoDAAACABgAGkMAAAHAGIAawwAAAYAYQBqDAAABQBVAGwMAAABAE4AbQwAAAEAHgDqDAAACQBeAG4MAAABADQAFgAICZ8erQEAhAIIaAwAAAgAYABpDAAABwBiAGsMAAAGAGEAagwAAAUAVQBsDAAAAQBOAG0MAAABAB4A6gwAAAkAXgBuDAAAAQA0AC4ABAp/LQACFgAJCSwj6QMA6QIAFgAJCSwj6QMA6QIAAAA=.Titanpp:BAEALgADCgQJCAABLgAFFAgJJgAWAJ8eAA==.',
Va='Valynithira:BAECLgAFFH8fAAIJAAgJYxywBwB7AghoDAAABQBiAGkMAAAFAGAAawwAAAYATQBqDAAABABcAGwMAAADAE4AbQwAAAEAGgDqDAAABgBdAG4MAAABACUACQAICWMcsAcAewIIaAwAAAUAYgBpDAAABQBgAGsMAAAGAE0AagwAAAQAXABsDAAAAwBOAG0MAAABABoA6gwAAAYAXQBuDAAAAQAlAC4ABAp/LgACCQAICeYlpQ8ASwMACQAICeYlpQ8ASwMAAAA=.',
Ve='Velanyr:BAEBLgAECn8dAAIOAAkJoh2wLAAYAgloDAAABQBOAGkMAAAEADgAawwAAAQARQBqDAAAAwBRAGwMAAADAFEAbQwAAAIAXwDqDAAABQBQAG4MAAACAEsAbwwAAAEARgAOAAkJoh2wLAAYAgloDAAABQBOAGkMAAAEADgAawwAAAQARQBqDAAAAwBRAGwMAAADAFEAbQwAAAIAXwDqDAAABQBQAG4MAAACAEsAbwwAAAEARgAAAA==.',
Vi='Viridessia:BAEBLgAECn80AAQIAAkJQRhOCQB/AQloDAAACQBEAGkMAAAIADgAawwAAAgARQBqDAAABgA+AGwMAAAGAEQAbQwAAAIAGwDqDAAACAA7AG4MAAAEAEQAbwwAAAEATgARAAgJFRUWIgCsAQhoDAAAAwAtAGkMAAADACcAawwAAAMARQBqDAAAAQAEAGwMAAACABAA6gwAAAQAOwBuDAAABABEAG8MAAABAE4ACAAHCTUWTgkAfwEHaAwAAAYARABpDAAABQA4AGsMAAAFAEIAagwAAAQAPgBsDAAABABEAG0MAAACABsA6gwAAAQANQAVAAEJ1QeEOQApAAFqDAAAAQAUAAAA.',
Vl='Vladja:BAEBLgAECn8kAAIMAAYJPxvuaQB/AQZoDAAABgBIAGkMAAAGADMAawwAAAYARwBqDAAABQBQAGwMAAAFAEUA6gwAAAgAUwAMAAYJPxvuaQB/AQZoDAAABgBIAGkMAAAGADMAawwAAAYARwBqDAAABQBQAGwMAAAFAEUA6gwAAAgAUwAAAA==.',
Yi='Yiangchen:BAEBLgAECn8hAAISAAkJRR1eCACbAgloDAAABABWAGkMAAAEAFsAawwAAAQAOABqDAAABQBWAGwMAAAFAFIAbQwAAAIANwDqDAAABABCAG4MAAAEAEQAbwwAAAEAXAASAAkJRR1eCACbAgloDAAABABWAGkMAAAEAFsAawwAAAQAOABqDAAABQBWAGwMAAAFAFIAbQwAAAIANwDqDAAABABCAG4MAAAEAEQAbwwAAAEAXAABLgAECgkJNAAIAEEYAA==.',
Zi='Zirkondrake:BAEBLgAECn84AAMXAAgJUx/aEABdAghoDAAACQBTAGkMAAAKAFwAawwAAAgAUABqDAAACABiAGwMAAAGAFoAbQwAAAIAJwDqDAAACQBdAG4MAAAEAFIAFwAICVMf2hAAXQIIaAwAAAgAUwBpDAAACABcAGsMAAAHAFAAagwAAAYAYgBsDAAABQBaAG0MAAABACcA6gwAAAcAXQBuDAAAAwBSABgACAmmG9cKACsCCGgMAAABAEUAaQwAAAIAVgBrDAAAAQBNAGoMAAACAFoAbAwAAAEAOwBtDAAAAQAlAOoMAAACAFoAbgwAAAEATAAAAA==.',
Zy='Zylphian:BAEBLgAECn8oAAITAAgJrhQwLgD5AQhoDAAABwBHAGkMAAAFADUAawwAAAQAKQBqDAAABQA8AGwMAAAFAC4AbQwAAAQAIQDqDAAABwBUAG4MAAADACYAEwAICa4UMC4A+QEIaAwAAAcARwBpDAAABQA1AGsMAAAEACkAagwAAAUAPABsDAAABQAuAG0MAAAEACEA6gwAAAcAVABuDAAAAwAmAAAA.',
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
