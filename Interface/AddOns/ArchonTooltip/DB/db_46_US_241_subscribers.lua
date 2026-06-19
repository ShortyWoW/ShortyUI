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

local lookup = {'DemonHunter-Devourer','DeathKnight-Unholy','DemonHunter-Havoc','DemonHunter-Vengeance','Monk-Windwalker','Monk-Mistweaver','Unknown-Unknown','DeathKnight-Blood','Evoker-Augmentation','Mage-Frost','Druid-Restoration','Priest-Holy','DeathKnight-Frost','Paladin-Retribution','Druid-Feral','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Evoker-Devastation','Hunter-Marksmanship','Monk-Brewmaster','Hunter-BeastMastery','Rogue-Assassination','Evoker-Preservation','Mage-Arcane','Warrior-Arms','Paladin-Protection','Warrior-Fury','Warrior-Protection',}
local provider = {region='US',realm='WyrmrestAccord',name='US',type='subscribers',zone=46,date='2026-06-18',data={Ag='Aggrodari:BAECLgAFFH8TAAIBAAUJOSSwIwChAQVoDAAABgBjAGkMAAAFAGMAawwAAAMATABqDAAAAQARAOoMAAAEAF8AAQAFCTkksCMAoQEFaAwAAAYAYwBpDAAABQBjAGsMAAADAEwAagwAAAEAEQDqDAAABABfAC4ABAp/SAACAQAJCVklagIAYgMAAQAJCVklagIAYgMAAAA=.Aggrorunner:BAEALgADCgMJBQABLgAFFAUJEwABADkkAA==.',
An='Anuhkin:BAEALgADCgUJBQABLgAFFAYJEgACAEYfAA==.',
Ar='Archoknot:BAEALgAFFAEJAQAAAA==.Arcis:BAECLgAFFH8MAAIDAAMJahyRFQD4AANoDAAABQBLAGkMAAADAFIA6gwAAAQAPAADAAMJahyRFQD4AANoDAAABQBLAGkMAAADAFIA6gwAAAQAPAAuAAQKfx0ABAMACAk2H/0OADYCAAMABgl6IP0OADYCAAEABgm3D5OSAPsAAAQABAlqFTsWAPcAAAAA.',
Bj='Bjørnulf:BAEALgAECgYJCwAAAA==.',
Bo='Bowbafletch:BAEALgAFFAEJAgABLgAFFAYJEgACAEYfAA==.',
Br='Breadroll:BAECLgAFFH8GAAIFAAIJviHeKQCpAAJoDAAAAgBWAOoMAAAEAFYABQACCb4h3ikAqQACaAwAAAIAVgDqDAAABABWAC4ABAp/HgADBQAJCdwh7wIAaAMABQAJCdwh7wIAaAMABgAECWUddUgASgEAAAA=.Brendemøn:BAEALgAECgYJCwAAAA==.Brêndêath:BAEALgAECgYJCgABLgAECgYJCwAHAAAAAA==.',
Ca='Caedues:BAECLgAFFH8SAAMCAAYJRh9VTwBTAQZoDAAABABfAGkMAAAEAFsAawwAAAMAVQBqDAAAAQBGAGwMAAABACoA6gwAAAUAVQACAAUJ+SJVTwBTAQVoDAAABABfAGkMAAAEAFsAawwAAAMAVQBqDAAAAQBGAOoMAAAFAFUACAABCXoQdDsASAABbAwAAAEAKgAuAAQKfyEAAgIACQnQIXwTAAYDAAIACQnQIXwTAAYDAAAA.',
Ch='Chaosity:BAEALgAECgcJEgABLgAECgkJNQAJAKkZAA==.Cheeseburber:BAEALgADCgMJAwABLgAECgQJEAAHAAAAAA==.',
Dr='Drommekage:BAEBLgAECn8bAAIKAAcJuQbPzgDzAAdoDAAABQANAGkMAAAFABQAawwAAAUAIwBqDAAABAATAGwMAAADAA8AbQwAAAEABgDqDAAABAAMAAoABwm5Bs/OAPMAB2gMAAAFAA0AaQwAAAUAFABrDAAABQAjAGoMAAAEABMAbAwAAAMADwBtDAAAAQAGAOoMAAAEAAwAAAA=.',
El='Elvarg:BAEALgAECgEJAQABLgAECgcJFQALAEIbAA==.',
En='Enneth:BAEALgADCgQJBAAAAA==.',
Ev='Eviecera:BAEALgADCgUJBQABLgAFFAYJBQAMAEofAA==.',
Ex='Exesa:BAECLgAFFH8FAAICAAQJTBX8XwA1AQRoDAAAAQA4AGkMAAABAEEAawwAAAEAGADqDAAAAgBHAAIABAlMFfxfADUBBGgMAAABADgAaQwAAAEAQQBrDAAAAQAYAOoMAAACAEcALgAECn8gAAMCAAkJwB1kFwC6AgACAAkJWx1kFwC6AgANAAUJhhMhFQAxAQAAAA==.',
Fe='Fedja:BAEBLgAECn8cAAQIAAkJXxUUFADTAQloDAAAAwAzAGkMAAADACoAawwAAAMANwBqDAAAAwBGAGwMAAADADwAbQwAAAMAQwDqDAAABQA3AG4MAAADADEAbwwAAAIANwAIAAkJ2hMUFADTAQloDAAAAgAqAGkMAAACABUAawwAAAIANwBqDAAAAgBGAGwMAAACADwAbQwAAAEAQwDqDAAAAgA2AG4MAAACADEAbwwAAAIANwANAAcJthJGEQBjAQdoDAAAAQAzAGkMAAABACoAagwAAAEAJABsDAAAAQAzAG0MAAACADEA6gwAAAMANwBuDAAAAQAkAAIAAQnfB8x3ATAAAWsMAAABABQAAS4ABAoICSsADgCdGQA=.',
Hi='Hirenar:BAEALgAECgEJAgABLgAFFAYJEgACAEYfAA==.',
['Hâ']='Hâstery:BAEALgAECggJBwABLgAFFAYJDAAPAA0eAA==.',
Il='Illothe:BAECLgAFFH8xAAQQAAcJVhZeEABeAQdoDAAACQBZAGkMAAAIAFkAawwAAAkAQgBqDAAACABVAGwMAAAEACoAbQwAAAIAAwDqDAAACQAzABAABgmOGl4QAF4BBmgMAAAJAFkAaQwAAAYAWQBrDAAACQBCAGoMAAAIAFUAbAwAAAQAKgDqDAAACQAzABEAAQmgCeUoAEUAAWkMAAABABgAEgACCcsAGCgARAACaQwAAAEAAABtDAAAAgADAC4ABAp/KgADEAAJCV8hBRIA6wIAEAAICfoiBRIA6wIAEgADCRMV0jcA1gAAAAA=.Illothedh:BAEALgADCgMJAwABLgAFFAcJMQAQAFYWAA==.',
In='Insouciantly:BAEALgAECgIJAgABLgAECgcJGAAMAIgjAA==.',
Ir='Irreverently:BAEBLgAECn8YAAIMAAcJiCMrEgBPAgdoDAAABABNAGkMAAAEAFkAawwAAAQAWgBqDAAAAgBhAGwMAAADAFoAbQwAAAEAYADqDAAABgBgAAwABwmIIysSAE8CB2gMAAAEAE0AaQwAAAQAWQBrDAAABABaAGoMAAACAGEAbAwAAAMAWgBtDAAAAQBgAOoMAAAGAGAAAAA=.',
Jl='Jlucks:BAECLgAFFH8zAAIJAAgJiiIIBQC6AghoDAAACQBiAGkMAAAIAFoAawwAAAgAWwBqDAAACABaAGwMAAACAFsAbQwAAAIASQDqDAAADQBgAG4MAAABAE0ACQAICYoiCAUAugIIaAwAAAkAYgBpDAAACABaAGsMAAAIAFsAagwAAAgAWgBsDAAAAgBbAG0MAAACAEkA6gwAAA0AYABuDAAAAQBNAC4ABAp/TwADCQAJCYIm5gAAgAMACQAJCYIm5gAAgAMAEwABCY0dNB8AWAAAAAA=.Jlucksdh:BAECLgAFFH8hAAIBAAUJqiReJwCOAQVoDAAACwBgAGkMAAAJAF8AawwAAAQAVQBqDAAAAgA7AOoMAAAHAGIAAQAFCaokXicAjgEFaAwAAAsAYABpDAAACQBfAGsMAAAEAFUAagwAAAIAOwDqDAAABwBiAC4ABAp/TwACAQAJCSgl6AQAOQMAAQAJCSgl6AQAOQMAAS4ABRQICTMACQCKIgA=.Jluckshnt:BAEBLgAFFH8GAAIUAAMJJxt+GQDpAANoDAAAAgA+AGkMAAACAFEA6gwAAAIAQAAUAAMJJxt+GQDpAANoDAAAAgA+AGkMAAACAFEA6gwAAAIAQAABLgAFFAgJMwAJAIoiAA==.Jlucksmk:BAEBLgAECn9WAAMGAAcJpyUwCwDmAgdoDAAADwBhAGkMAAAOAGIAawwAAA4AYgBqDAAADgBjAGwMAAAMAGIAbQwAAAIAUwDqDAAADwBjAAYABwmnJTALAOYCB2gMAAANAGEAaQwAAAwAYgBrDAAADABiAGoMAAAKAGMAbAwAAAoAYgBtDAAAAgBTAOoMAAAKAGMAFQAGCasS0jUAJgEGaAwAAAIARgBpDAAAAgAwAGsMAAACACcAagwAAAQALABsDAAAAgAeAOoMAAAFADEAAS4ABRQICTMACQCKIgA=.',
Ki='Kippee:BAECLgAFFH8YAAIKAAYJIxpKMwCcAQZoDAAABgBUAGkMAAAFAEYAawwAAAUASQBqDAAAAgBDAGwMAAABAEgA6gwAAAUAIgAKAAYJIxpKMwCcAQZoDAAABgBUAGkMAAAFAEYAawwAAAUASQBqDAAAAgBDAGwMAAABAEgA6gwAAAUAIgAuAAQKfycAAgoACQlMIs8gAPACAAoACQlMIs8gAPACAAAA.Kipplock:BAEALgAECgYJDwABLgAFFAYJGAAKACMaAA==.',
Kr='Kred:BAEALgADCgYJBgABLgAECgkJWwAWAOYiAA==.Kredrothi:BAEBLgAECn9bAAIWAAkJ5iIqAACMAgloDAAADABfAGkMAAALAGEAawwAAAwAWABqDAAACwBgAGwMAAALAFMAbQwAAAgATADqDAAADABXAG4MAAAJAF0AbwwAAAUAWwAWAAkJ5iIqAACMAgloDAAADABfAGkMAAALAGEAawwAAAwAWABqDAAACwBgAGwMAAALAFMAbQwAAAgATADqDAAADABXAG4MAAAJAF0AbwwAAAUAWwAAAA==.',
Ku='Kunha:BAEALgADCgkJCQABLgAFFAIJAwAHAAAAAA==.',
La='Laghar:BAEALgAECgEJAQAAAA==.',
Ma='Magicracoon:BAEALgAECgQJEAAAAA==.Malzbier:BAEALgAECggJDAABLgAFFAYJEgACAEYfAA==.Marosia:BAEALgAECgcJEwABLgAFFAIJBQAXAHgdAA==.Marroc:BAECLgAFFH8FAAIXAAIJeB3lCADCAAJoDAAAAQA0AOoMAAAEAGIAFwACCXgd5QgAwgACaAwAAAEANADqDAAABABiAC4ABAp/LQACFwAJCSQitAEA4wIAFwAJCSQitAEA4wIAAAA=.',
Ne='Nekun:BAEALgAECgMJBgABLgAECgMJBgAHAAAAAA==.',
Ni='Nitedragon:BAEBLgAECn8XAAMYAAcJUCAaCABvAgdoDAAABABcAGkMAAAEAFUAawwAAAQASABqDAAAAwBSAGwMAAADAFcA6gwAAAQAWABuDAAAAQBEABgABwlQIBoIAG8CB2gMAAADAFwAaQwAAAMAVQBrDAAAAwBIAGoMAAADAFIAbAwAAAMAVwDqDAAABABYAG4MAAABAEQAEwADCcgDTSAAUQADaAwAAAEABQBpDAAAAQAMAGsMAAABAAsAAAA=.',
No='Nottoasty:BAEALgAFFAIJAgABLgAFFAQJBAAHAAAAAA==.',
['Nì']='Nìte:BAEALgAECgcJDgABLgAECgcJFwAYAFAgAA==.',
Or='Oracs:BAEBLgAECn8VAAQJAAcJ6h9WGAAPAgdoDAAAAwBNAGkMAAADAFgAawwAAAMAXABqDAAABABZAGwMAAADAFIA6gwAAAQAWgBuDAAAAQA6AAkABglgH1YYAA8CBmgMAAABAEoAaQwAAAEAUwBrDAAAAQBcAGwMAAADAFIA6gwAAAIAWgBuDAAAAQA6ABMABQkkHRgXAIQBBWgMAAABAE0AaQwAAAEAWABrDAAAAQBNAGoMAAAEAFkA6gwAAAEANgAYAAQJdAQLOQCiAARoDAAAAQAGAGkMAAABABIAawwAAAEAAwDqDAAAAQAQAAEuAAUUBgkSAAIARh8A.',
Pa='Pai:BAEALgAFFAIJAwABLgAFFAIJBgAFAL4hAA==.',
Pi='Pickups:BAECLgAFFH8HAAIBAAMJtBenXwDRAANoDAAAAgA5AGkMAAABADYA6gwAAAQARQABAAMJtBenXwDRAANoDAAAAgA5AGkMAAABADYA6gwAAAQARQAuAAQKfyIAAwQACAmzG0IHABQCAAQABwm/GUIHABQCAAEABwn/FJN8ACcBAAEuAAUUCAkfAAoAYxwA.',
Qa='Qahz:BAECLgAFFH8PAAIQAAUJlxU5RgA8AQVoDAAABABRAGkMAAAEAFoAawwAAAMAHQBqDAAAAQAlAOoMAAADABMAEAAFCZcVOUYAPAEFaAwAAAQAUQBpDAAABABaAGsMAAADAB0AagwAAAEAJQDqDAAAAwATAC4ABAp/LQACEAAJCRsi9g4A1AIAEAAJCRsi9g4A1AIAAS4ABRQFCRMAAQA5JAA=.',
Ru='Ruehnar:BAEALgAECgYJDwABLgAECggJKwAOAJ0ZAA==.',
Si='Sixul:BAEBLgAFFH8JAAIXAAQJ7RGsBQAiAQRoDAAABAA9AGkMAAADAEEAawwAAAEAFADqDAAAAQAkABcABAntEawFACIBBGgMAAAEAD0AaQwAAAMAQQBrDAAAAQAUAOoMAAABACQAAAA=.',
St='Startut:BAEALgAECgIJBAAAAA==.',
Sy='Syth:BAEALgAECggJDwABLgAECgkJLQAZAKIkAA==.',
Ta='Taylorquick:BAEALgAECggJDgAAAA==.Tazukey:BAEBLgAECn8VAAILAAcJQht5OgC8AQdoDAAABQBgAGkMAAAEAFMAawwAAAQAUgBqDAAAAgBMAGwMAAABADsA6gwAAAQARgBuDAAAAQATAAsABwlCG3k6ALwBB2gMAAAFAGAAaQwAAAQAUwBrDAAABABSAGoMAAACAEwAbAwAAAEAOwDqDAAABABGAG4MAAABABMAAAA=.',
Te='Tenisia:BAEALgAECgcJDgAAAA==.Teyr:BAEBLgAECn84AAIaAAkJkSFXAwD9AgloDAAACABgAGkMAAAIAF4AawwAAAgAXABqDAAABwBiAGwMAAAHAFMAbQwAAAUAYADqDAAABwBhAG4MAAAEADQAbwwAAAIASQAaAAkJkSFXAwD9AgloDAAACABgAGkMAAAIAF4AawwAAAgAXABqDAAABwBiAGwMAAAHAFMAbQwAAAUAYADqDAAABwBhAG4MAAAEADQAbwwAAAIASQAAAA==.',
Th='Theò:BAEALgAECgQJBAAAAA==.',
Ti='Titanbp:BAEALgADCgYJCQABLgAFFAgJKQAIAJ8eAA==.Titandb:BAECLgAFFH8pAAIIAAgJnx79AwBqAghoDAAACQBgAGkMAAAIAGIAawwAAAcAYQBqDAAABQBVAGwMAAABAE4AbQwAAAEAHgDqDAAACQBeAG4MAAABADQACAAICZ8e/QMAagIIaAwAAAkAYABpDAAACABiAGsMAAAHAGEAagwAAAUAVQBsDAAAAQBOAG0MAAABAB4A6gwAAAkAXgBuDAAAAQA0AC4ABAp/LQACCAAJCSwjEgUA2wIACAAJCSwjEgUA2wIAAAA=.Titanpp:BAEALgADCgQJCAABLgAFFAgJKQAIAJ8eAA==.',
Va='Valynithira:BAECLgAFFH8fAAIKAAgJYxxoEwBTAghoDAAABQBiAGkMAAAFAGAAawwAAAYATQBqDAAABABcAGwMAAADAE4AbQwAAAEAGgDqDAAABgBdAG4MAAABACUACgAICWMcaBMAUwIIaAwAAAUAYgBpDAAABQBgAGsMAAAGAE0AagwAAAQAXABsDAAAAwBOAG0MAAABABoA6gwAAAYAXQBuDAAAAQAlAC4ABAp/LgACCgAICeYlpQ8ASwMACgAICeYlpQ8ASwMAAAA=.',
Ve='Velanyr:BAEBLgAECn8dAAIQAAkJoh2BMwALAgloDAAABQBOAGkMAAAEADgAawwAAAQARQBqDAAAAwBRAGwMAAADAFEAbQwAAAIAXwDqDAAABQBQAG4MAAACAEsAbwwAAAEARgAQAAkJoh2BMwALAgloDAAABQBOAGkMAAAEADgAawwAAAQARQBqDAAAAwBRAGwMAAADAFEAbQwAAAIAXwDqDAAABQBQAG4MAAACAEsAbwwAAAEARgAAAA==.',
Vi='Viridessia:BAEBLgAECn81AAQJAAkJqRnIIADTAQloDAAACQBEAGkMAAAIADgAawwAAAgARQBqDAAABgA+AGwMAAAGAEQAbQwAAAIAGwDqDAAACQBYAG4MAAAEAEQAbwwAAAEATgAJAAgJrxbIIADTAQhoDAAAAwAtAGkMAAADACcAawwAAAMARQBqDAAAAQAEAGwMAAACABAA6gwAAAUAWABuDAAABABEAG8MAAABAE4AEwAHCTUWYAoAeQEHaAwAAAYARABpDAAABQA4AGsMAAAFAEIAagwAAAQAPgBsDAAABABEAG0MAAACABsA6gwAAAQANQAYAAEJ1QcfPwAoAAFqDAAAAQAUAAAA.',
Vl='Vladja:BAEBLgAECn8rAAMOAAgJnRlpTQDfAQhoDAAABwBIAGkMAAAHADMAawwAAAcARwBqDAAABgBSAGwMAAAGAFAAbQwAAAEAHQDqDAAACABTAG4MAAABAEYADgAHCfUbaU0A3wEHaAwAAAcASABpDAAABwAzAGsMAAAHAEcAagwAAAYAUgBsDAAABgBQAOoMAAAIAFMAbgwAAAEARgAbAAEJigvgUAAvAAFtDAAAAQAdAAAA.',
Wr='Wrexilion:BAEALgAECgUJBQAAAA==.',
Yi='Yiangchen:BAEBLgAECn8hAAIVAAkJRR3nCQCUAgloDAAABABWAGkMAAAEAFsAawwAAAQAOABqDAAABQBWAGwMAAAFAFIAbQwAAAIANwDqDAAABABCAG4MAAAEAEQAbwwAAAEAXAAVAAkJRR3nCQCUAgloDAAABABWAGkMAAAEAFsAawwAAAQAOABqDAAABQBWAGwMAAAFAFIAbQwAAAIANwDqDAAABABCAG4MAAAEAEQAbwwAAAEAXAABLgAECgkJNQAJAKkZAA==.',
Zi='Zirkondrake:BAEBLgAECn9BAAMcAAgJGSTPBwDiAghoDAAACgBbAGkMAAALAGIAawwAAAkAVwBqDAAACQBiAGwMAAAHAGEAbQwAAAMAUQDqDAAACgBdAG4MAAAGAGEAHAAICRkkzwcA4gIIaAwAAAkAWwBpDAAACQBiAGsMAAAIAFcAagwAAAcAYgBsDAAABgBhAG0MAAACAFEA6gwAAAgAXQBuDAAABQBhAB0ACAmmG+IMABwCCGgMAAABAEUAaQwAAAIAVgBrDAAAAQBNAGoMAAACAFoAbAwAAAEAOwBtDAAAAQAlAOoMAAACAFoAbgwAAAEATAAAAA==.',
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
