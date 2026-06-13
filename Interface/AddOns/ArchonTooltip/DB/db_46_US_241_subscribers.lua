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

local lookup = {'DemonHunter-Devourer','DeathKnight-Unholy','DemonHunter-Havoc','DemonHunter-Vengeance','Monk-Windwalker','Monk-Mistweaver','Unknown-Unknown','DeathKnight-Blood','Evoker-Augmentation','Mage-Frost','Druid-Restoration','Priest-Holy','DeathKnight-Frost','Paladin-Retribution','Druid-Feral','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Evoker-Devastation','Hunter-Marksmanship','Monk-Brewmaster','Hunter-BeastMastery','Rogue-Assassination','Evoker-Preservation','Warrior-Arms','Paladin-Protection','Warrior-Fury','Warrior-Protection',}
local provider = {region='US',realm='WyrmrestAccord',name='US',type='subscribers',zone=46,date='2026-06-12',data={Ag='Aggrodari:BAECLgAFFH8TAAIBAAUJOSQRIQCkAQVoDAAABgBjAGkMAAAFAGMAawwAAAMATABqDAAAAQARAOoMAAAEAF8AAQAFCTkkESEApAEFaAwAAAYAYwBpDAAABQBjAGsMAAADAEwAagwAAAEAEQDqDAAABABfAC4ABAp/SAACAQAJCVklSgIAYgMAAQAJCVklSgIAYgMAAAA=.Aggrorunner:BAEALgADCgMJBQABLgAFFAUJEwABADkkAA==.',
An='Anuhkin:BAEALgADCgUJBQABLgAFFAYJEgACAEYfAA==.',
Ar='Archoknot:BAEALgAFFAEJAQAAAA==.Arcis:BAECLgAFFH8JAAIDAAMJahx4FAD6AANoDAAABABLAGkMAAACAFIA6gwAAAMAPAADAAMJahx4FAD6AANoDAAABABLAGkMAAACAFIA6gwAAAMAPAAuAAQKfxwABAMACAk2H5EOADgCAAMABgl6IJEOADgCAAEABgm3DwmQAPsAAAQABAlqFcoVAPcAAAAA.',
Bj='Bjørnulf:BAEALgAECgYJCwAAAA==.',
Bo='Bowbafletch:BAEALgAFFAEJAQABLgAFFAYJEgACAEYfAA==.',
Br='Breadroll:BAECLgAFFH8GAAIFAAIJviHuJwCqAAJoDAAAAgBWAOoMAAAEAFYABQACCb4h7icAqgACaAwAAAIAVgDqDAAABABWAC4ABAp/HgADBQAJCdwh7wIAaAMABQAJCdwh7wIAaAMABgAECWUdBkYASgEAAAA=.Brendemøn:BAEALgAECgYJCwAAAA==.Brêndêath:BAEALgAECgYJCgABLgAECgYJCwAHAAAAAA==.',
Ca='Caedues:BAECLgAFFH8SAAMCAAYJRh+mSgBWAQZoDAAABABfAGkMAAAEAFsAawwAAAMAVQBqDAAAAQBGAGwMAAABACoA6gwAAAUAVQACAAUJ+SKmSgBWAQVoDAAABABfAGkMAAAEAFsAawwAAAMAVQBqDAAAAQBGAOoMAAAFAFUACAABCXoQKDkASgABbAwAAAEAKgAuAAQKfyEAAgIACQnQIXwTAAYDAAIACQnQIXwTAAYDAAAA.',
Ch='Chaosity:BAEALgAECgcJEgABLgAECgkJNQAJAKkZAA==.Cheeseburber:BAEALgADCgMJAwABLgAECgQJEAAHAAAAAA==.',
Dr='Drommekage:BAEBLgAECn8bAAIKAAcJuQbqygD4AAdoDAAABQANAGkMAAAFABQAawwAAAUAIwBqDAAABAATAGwMAAADAA8AbQwAAAEABgDqDAAABAAMAAoABwm5BurKAPgAB2gMAAAFAA0AaQwAAAUAFABrDAAABQAjAGoMAAAEABMAbAwAAAMADwBtDAAAAQAGAOoMAAAEAAwAAAA=.',
El='Elvarg:BAEALgAECgEJAQABLgAECgcJFQALAEIbAA==.',
En='Enneth:BAEALgADCgQJBAAAAA==.',
Ev='Eviecera:BAEALgADCgUJBQABLgAFFAYJBQAMAEofAA==.',
Ex='Exesa:BAECLgAFFH8FAAICAAQJTBVQWgA5AQRoDAAAAQA4AGkMAAABAEEAawwAAAEAGADqDAAAAgBHAAIABAlMFVBaADkBBGgMAAABADgAaQwAAAEAQQBrDAAAAQAYAOoMAAACAEcALgAECn8gAAMCAAkJwB2xFgC7AgACAAkJWx2xFgC7AgANAAUJhhN5FAA0AQAAAA==.',
Fe='Fedja:BAEALgAECgkJEgABLgAECggJKwAOAJ0ZAA==.',
Hi='Hirenar:BAEALgAECgEJAgABLgAFFAYJEgACAEYfAA==.',
['Hâ']='Hâstery:BAEALgAECggJBwABLgAFFAYJDAAPAA0eAA==.',
Il='Illothe:BAECLgAFFH8tAAQQAAcJVhZeEABeAQdoDAAACABZAGkMAAAHAFkAawwAAAgAQgBqDAAABwBVAGwMAAAEACoAbQwAAAIAAwDqDAAACQAzABAABgmOGl4QAF4BBmgMAAAIAFkAaQwAAAUAWQBrDAAACABCAGoMAAAHAFUAbAwAAAQAKgDqDAAACQAzABEAAQmgCUUnAEcAAWkMAAABABgAEgACCcsAdScARQACaQwAAAEAAABtDAAAAgADAC4ABAp/KgADEAAJCV8hBRIA6wIAEAAICfoiBRIA6wIAEgADCRMV0jcA1gAAAAA=.Illothedh:BAEALgADCgMJAwABLgAFFAcJLQAQAFYWAA==.',
In='Insouciantly:BAEALgAECgIJAgABLgAECgcJGAAMAIgjAA==.',
Ir='Irreverently:BAEBLgAECn8YAAIMAAcJiCMrEgBPAgdoDAAABABNAGkMAAAEAFkAawwAAAQAWgBqDAAAAgBhAGwMAAADAFoAbQwAAAEAYADqDAAABgBgAAwABwmIIysSAE8CB2gMAAAEAE0AaQwAAAQAWQBrDAAABABaAGoMAAACAGEAbAwAAAMAWgBtDAAAAQBgAOoMAAAGAGAAAAA=.',
Jl='Jlucks:BAECLgAFFH8pAAIJAAgJaCI9BQCnAghoDAAABwBiAGkMAAAGAFgAawwAAAYAWwBqDAAABgBaAGwMAAACAFsAbQwAAAIASQDqDAAACwBgAG4MAAABAE0ACQAICWgiPQUApwIIaAwAAAcAYgBpDAAABgBYAGsMAAAGAFsAagwAAAYAWgBsDAAAAgBbAG0MAAACAEkA6gwAAAsAYABuDAAAAQBNAC4ABAp/TwADCQAJCYIm4QAAgQMACQAJCYIm4QAAgQMAEwABCY0dlB4AWAAAAAA=.Jlucksdh:BAECLgAFFH8hAAIBAAUJqiRkJACSAQVoDAAACwBgAGkMAAAJAF8AawwAAAQAVQBqDAAAAgA7AOoMAAAHAGIAAQAFCaokZCQAkgEFaAwAAAsAYABpDAAACQBfAGsMAAAEAFUAagwAAAIAOwDqDAAABwBiAC4ABAp/TwACAQAJCSglnAQAOgMAAQAJCSglnAQAOgMAAS4ABRQICSkACQBoIgA=.Jluckshnt:BAEBLgAFFH8GAAIUAAMJJxthGADxAANoDAAAAgA+AGkMAAACAFEA6gwAAAIAQAAUAAMJJxthGADxAANoDAAAAgA+AGkMAAACAFEA6gwAAAIAQAABLgAFFAgJKQAJAGgiAA==.Jlucksmk:BAEBLgAECn9WAAMGAAcJpyXLCgDmAgdoDAAADwBhAGkMAAAOAGIAawwAAA4AYgBqDAAADgBjAGwMAAAMAGIAbQwAAAIAUwDqDAAADwBjAAYABwmnJcsKAOYCB2gMAAANAGEAaQwAAAwAYgBrDAAADABiAGoMAAAKAGMAbAwAAAoAYgBtDAAAAgBTAOoMAAAKAGMAFQAGCasSIzUAJgEGaAwAAAIARgBpDAAAAgAwAGsMAAACACcAagwAAAQALABsDAAAAgAeAOoMAAAFADEAAS4ABRQICSkACQBoIgA=.',
Kr='Kred:BAEALgADCgYJBgABLgAECgkJUgAWAI4iAA==.Kredrothi:BAEBLgAECn9SAAIWAAkJjiIJDwDUAgloDAAACwBfAGkMAAAKAGEAawwAAAsAWABqDAAACgBgAGwMAAAKAEwAbQwAAAcATADqDAAACwBXAG4MAAAIAF0AbwwAAAQAWwAWAAkJjiIJDwDUAgloDAAACwBfAGkMAAAKAGEAawwAAAsAWABqDAAACgBgAGwMAAAKAEwAbQwAAAcATADqDAAACwBXAG4MAAAIAF0AbwwAAAQAWwAAAA==.',
Ku='Kunha:BAEALgADCgkJCQABLgAFFAIJAwAHAAAAAA==.',
La='Laghar:BAEALgAECgEJAQAAAA==.',
Ma='Magicracoon:BAEALgAECgQJEAAAAA==.Malzbier:BAEALgAECggJDAABLgAFFAYJEgACAEYfAA==.Marosia:BAEALgAECgYJDAABLgAECgkJKwAXADMhAA==.Marroc:BAEBLgAECn8rAAIXAAkJMyGnAQDjAgloDAAABwBhAGkMAAAGAF4AawwAAAYAWQBqDAAABgBRAGwMAAADAEUAbQwAAAIAXgDqDAAABwBjAG4MAAAFAEIAbwwAAAEARQAXAAkJMyGnAQDjAgloDAAABwBhAGkMAAAGAF4AawwAAAYAWQBqDAAABgBRAGwMAAADAEUAbQwAAAIAXgDqDAAABwBjAG4MAAAFAEIAbwwAAAEARQAAAA==.',
Ne='Nekun:BAEALgAECgMJBgABLgAECgMJBgAHAAAAAA==.',
Ni='Nitedragon:BAEBLgAECn8UAAIYAAcJUCDmBwBvAgdoDAAAAwBcAGkMAAADAFUAawwAAAMASABqDAAAAwBSAGwMAAADAFcA6gwAAAQAWABuDAAAAQBEABgABwlQIOYHAG8CB2gMAAADAFwAaQwAAAMAVQBrDAAAAwBIAGoMAAADAFIAbAwAAAMAVwDqDAAABABYAG4MAAABAEQAAAA=.',
['Nì']='Nìte:BAEALgAECgcJCAABLgAECgcJFAAYAFAgAA==.',
Or='Oracs:BAEBLgAECn8VAAQJAAcJ6h9WGAAPAgdoDAAAAwBNAGkMAAADAFgAawwAAAMAXABqDAAABABZAGwMAAADAFIA6gwAAAQAWgBuDAAAAQA6AAkABglgH1YYAA8CBmgMAAABAEoAaQwAAAEAUwBrDAAAAQBcAGwMAAADAFIA6gwAAAIAWgBuDAAAAQA6ABMABQkkHRgXAIQBBWgMAAABAE0AaQwAAAEAWABrDAAAAQBNAGoMAAAEAFkA6gwAAAEANgAYAAQJdAQLOQCiAARoDAAAAQAGAGkMAAABABIAawwAAAEAAwDqDAAAAQAQAAEuAAUUBgkSAAIARh8A.',
Pa='Pai:BAEALgAFFAIJAwABLgAFFAIJBgAFAL4hAA==.',
Pi='Pickups:BAECLgAFFH8HAAIBAAMJtBdlXADRAANoDAAAAgA5AGkMAAABADYA6gwAAAQARQABAAMJtBdlXADRAANoDAAAAgA5AGkMAAABADYA6gwAAAQARQAuAAQKfyIAAwQACAmzG0IHABQCAAQABwm/GUIHABQCAAEABwn/FG16ACYBAAEuAAUUCAkfAAoAYxwA.',
Qa='Qahz:BAECLgAFFH8PAAIQAAUJlxXRQgA/AQVoDAAABABRAGkMAAAEAFoAawwAAAMAHQBqDAAAAQAlAOoMAAADABMAEAAFCZcV0UIAPwEFaAwAAAQAUQBpDAAABABaAGsMAAADAB0AagwAAAEAJQDqDAAAAwATAC4ABAp/LQACEAAJCRsiWQ4A1gIAEAAJCRsiWQ4A1gIAAS4ABRQFCRMAAQA5JAA=.',
Ru='Ruehnar:BAEALgAECgYJDwABLgAECggJKwAOAJ0ZAA==.',
Si='Sixul:BAEBLgAFFH8JAAIXAAQJ7RF0BQAoAQRoDAAABAA9AGkMAAADAEEAawwAAAEAFADqDAAAAQAkABcABAntEXQFACgBBGgMAAAEAD0AaQwAAAMAQQBrDAAAAQAUAOoMAAABACQAAAA=.',
St='Startut:BAEALgAECgIJBAAAAA==.Stiffbow:BAEALgADCgQJBAABLgAECgkJOgAWAOIbAA==.',
Ta='Taylorquick:BAEALgAECggJDgAAAA==.Tazukey:BAEBLgAECn8VAAILAAcJQht5OgC8AQdoDAAABQBgAGkMAAAEAFMAawwAAAQAUgBqDAAAAgBMAGwMAAABADsA6gwAAAQARgBuDAAAAQATAAsABwlCG3k6ALwBB2gMAAAFAGAAaQwAAAQAUwBrDAAABABSAGoMAAACAEwAbAwAAAEAOwDqDAAABABGAG4MAAABABMAAAA=.',
Te='Tenisia:BAEALgAECgcJDgAAAA==.Teyr:BAEBLgAECn84AAIZAAkJkSEyAwD+AgloDAAACABgAGkMAAAIAF4AawwAAAgAXABqDAAABwBiAGwMAAAHAFMAbQwAAAUAYADqDAAABwBhAG4MAAAEADQAbwwAAAIASQAZAAkJkSEyAwD+AgloDAAACABgAGkMAAAIAF4AawwAAAgAXABqDAAABwBiAGwMAAAHAFMAbQwAAAUAYADqDAAABwBhAG4MAAAEADQAbwwAAAIASQAAAA==.',
Th='Theò:BAEALgADCgMJBAAAAA==.',
Ti='Titanbp:BAEALgADCgYJCQABLgAFFAgJJgAIAJ8eAA==.Titandb:BAECLgAFFH8mAAIIAAgJnx6FAwBvAghoDAAACABgAGkMAAAHAGIAawwAAAYAYQBqDAAABQBVAGwMAAABAE4AbQwAAAEAHgDqDAAACQBeAG4MAAABADQACAAICZ8ehQMAbwIIaAwAAAgAYABpDAAABwBiAGsMAAAGAGEAagwAAAUAVQBsDAAAAQBOAG0MAAABAB4A6gwAAAkAXgBuDAAAAQA0AC4ABAp/LQACCAAJCSwj4AQA3wIACAAJCSwj4AQA3wIAAAA=.Titanpp:BAEALgADCgQJCAABLgAFFAgJJgAIAJ8eAA==.',
Va='Valynithira:BAECLgAFFH8fAAIKAAgJYxzTEABfAghoDAAABQBiAGkMAAAFAGAAawwAAAYATQBqDAAABABcAGwMAAADAE4AbQwAAAEAGgDqDAAABgBdAG4MAAABACUACgAICWMc0xAAXwIIaAwAAAUAYgBpDAAABQBgAGsMAAAGAE0AagwAAAQAXABsDAAAAwBOAG0MAAABABoA6gwAAAYAXQBuDAAAAQAlAC4ABAp/LgACCgAICeYlpQ8ASwMACgAICeYlpQ8ASwMAAAA=.',
Ve='Velanyr:BAEBLgAECn8dAAIQAAkJoh2UMQAQAgloDAAABQBOAGkMAAAEADgAawwAAAQARQBqDAAAAwBRAGwMAAADAFEAbQwAAAIAXwDqDAAABQBQAG4MAAACAEsAbwwAAAEARgAQAAkJoh2UMQAQAgloDAAABQBOAGkMAAAEADgAawwAAAQARQBqDAAAAwBRAGwMAAADAFEAbQwAAAIAXwDqDAAABQBQAG4MAAACAEsAbwwAAAEARgAAAA==.',
Vi='Viridessia:BAEBLgAECn81AAQJAAkJqRlZIADUAQloDAAACQBEAGkMAAAIADgAawwAAAgARQBqDAAABgA+AGwMAAAGAEQAbQwAAAIAGwDqDAAACQBYAG4MAAAEAEQAbwwAAAEATgAJAAgJrxZZIADUAQhoDAAAAwAtAGkMAAADACcAawwAAAMARQBqDAAAAQAEAGwMAAACABAA6gwAAAUAWABuDAAABABEAG8MAAABAE4AEwAHCTUWOgoAeQEHaAwAAAYARABpDAAABQA4AGsMAAAFAEIAagwAAAQAPgBsDAAABABEAG0MAAACABsA6gwAAAQANQAYAAEJ1QcLPgAoAAFqDAAAAQAUAAAA.',
Vl='Vladja:BAEBLgAECn8rAAMOAAgJnRmvSwDgAQhoDAAABwBIAGkMAAAHADMAawwAAAcARwBqDAAABgBSAGwMAAAGAFAAbQwAAAEAHQDqDAAACABTAG4MAAABAEYADgAHCfUbr0sA4AEHaAwAAAcASABpDAAABwAzAGsMAAAHAEcAagwAAAYAUgBsDAAABgBQAOoMAAAIAFMAbgwAAAEARgAaAAEJigtETwAvAAFtDAAAAQAdAAAA.',
Wr='Wrexilion:BAEALgAECgUJBQAAAA==.',
Yi='Yiangchen:BAEBLgAECn8hAAIVAAkJRR2mCQCVAgloDAAABABWAGkMAAAEAFsAawwAAAQAOABqDAAABQBWAGwMAAAFAFIAbQwAAAIANwDqDAAABABCAG4MAAAEAEQAbwwAAAEAXAAVAAkJRR2mCQCVAgloDAAABABWAGkMAAAEAFsAawwAAAQAOABqDAAABQBWAGwMAAAFAFIAbQwAAAIANwDqDAAABABCAG4MAAAEAEQAbwwAAAEAXAABLgAECgkJNQAJAKkZAA==.',
Zi='Zirkondrake:BAEBLgAECn9AAAMbAAgJSiPSCADSAghoDAAACgBbAGkMAAALAGIAawwAAAkAVwBqDAAACQBiAGwMAAAHAGEAbQwAAAMAUQDqDAAACgBdAG4MAAAFAFIAGwAICUoj0ggA0gIIaAwAAAkAWwBpDAAACQBiAGsMAAAIAFcAagwAAAcAYgBsDAAABgBhAG0MAAACAFEA6gwAAAgAXQBuDAAABABSABwACAmmG3wMAB4CCGgMAAABAEUAaQwAAAIAVgBrDAAAAQBNAGoMAAACAFoAbAwAAAEAOwBtDAAAAQAlAOoMAAACAFoAbgwAAAEATAAAAA==.',
Zy='Zylphian:BAEBLgAECn86AAIWAAkJ4hv8FgCZAgloDAAACQBSAGkMAAAHAFIAawwAAAYAQABqDAAABwBAAGwMAAAHAEYAbQwAAAUAMwDqDAAACQBUAG4MAAAGAEcAbwwAAAIAPgAWAAkJ4hv8FgCZAgloDAAACQBSAGkMAAAHAFIAawwAAAYAQABqDAAABwBAAGwMAAAHAEYAbQwAAAUAMwDqDAAACQBUAG4MAAAGAEcAbwwAAAIAPgAAAA==.',
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
