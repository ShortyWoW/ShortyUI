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

local lookup = {'Warrior-Arms','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Paladin-Protection','Paladin-Retribution','Monk-Mistweaver','Warlock-Affliction','Warlock-Demonology','Mage-Frost','Hunter-Survival','Unknown-Unknown','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Unholy','Paladin-Holy','Druid-Restoration','Shaman-Restoration','DemonHunter-Devourer','Priest-Holy','Priest-Discipline','Priest-Shadow','Warlock-Destruction','Warrior-Fury','Warrior-Protection','Monk-Brewmaster','DeathKnight-Blood','Shaman-Enhancement','DeathKnight-Frost','DemonHunter-Vengeance','Rogue-Subtlety',}
local provider = {region='US',realm='TheUnderbog',name='US',type='daily',zone=46,date='2026-05-10',data={Ac='Acinovanth:BAAALgAECgEJAQAAAA==.Acousticjeff:BAAALgAECgYJBgAAAA==.',
Ad='Adwill:BAABLgAECn8eAAIBAAcJLyDvBgBVAgdoDAAABgBZAGkMAAAFAFUAawwAAAUAVQBqDAAABQBUAGwMAAADAFQAbQwAAAIARwDqDAAABABNAAEABwkvIO8GAFUCB2gMAAAGAFkAaQwAAAUAVQBrDAAABQBVAGoMAAAFAFQAbAwAAAMAVABtDAAAAgBHAOoMAAAEAE0AAAA=.',
Ae='Aelvoker:BAACLgAFFH8SAAQCAAUJ9BkMBAAJAQVoDAAABAA/AGkMAAAEADEAawwAAAMAOQBqDAAAAgAlAOoMAAAFAF8AAgAECT4VDAQACQEEaAwAAAEAPwBpDAAAAQABAGsMAAACADkA6gwAAAQAXwADAAQJERKjIwDkAARoDAAAAgA9AGkMAAACADEAawwAAAEAGwBqDAAAAQAlAAQABAnuBn0TAJAABGgMAAABACwAaQwAAAEADABqDAAAAQALAOoMAAABAAMALgAECn8XAAQCAAkJRR9SBwB3AgACAAYJJCNSBwB3AgAEAAcJnRGHGgC3AQADAAIJ3RrNSgCpAAAAAA==.',
Ai='Aindra:BAAALgAECggJEAAAAA==.Airen:BAAALgAECgQJBQAAAA==.',
An='Antidead:BAABLgAECn8gAAMFAAgJOR5zBQCfAghoDAAABQBOAGkMAAAFAE8AawwAAAUARABqDAAABAA4AGwMAAAEAFIAbQwAAAIAUgDqDAAABQBSAG4MAAACAEMABQAICTkecwUAnwIIaAwAAAQATgBpDAAABABPAGsMAAAEAEQAagwAAAMAOABsDAAAAwBSAG0MAAABAFIA6gwAAAQAUgBuDAAAAQBDAAYACAnXE8szALgBCGgMAAABADoAaQwAAAEAKQBrDAAAAQA3AGoMAAABACoAbAwAAAEAMwBtDAAAAQAyAOoMAAABAC4AbgwAAAEANAAAAA==.',
Ap='Apachaler:BAABLgAECn8bAAIHAAcJ3x2NDgAPAgdoDAAABgBSAGkMAAAFAF0AawwAAAQAUgBqDAAAAwBPAGwMAAADAEEAbQwAAAEANgDqDAAABQBMAAcABwnfHY0OAA8CB2gMAAAGAFIAaQwAAAUAXQBrDAAABABSAGoMAAADAE8AbAwAAAMAQQBtDAAAAQA2AOoMAAAFAEwAAAA=.',
Ar='Arathael:BAAALgADCgIJAgAAAA==.Ardyce:BAAALgADCgIJAgAAAA==.Arrae:BAAALgAECgUJAwAAAA==.Arreuws:BAAALgAECgQJBAAAAA==.',
As='Asiansmoliv:BAACLgAFFH8LAAMIAAMJ4BpWAwC3AANoDAAABQBVAGkMAAABAD8A6gwAAAUAOQAIAAIJ9BlWAwC3AAJoDAAAAQBFAGkMAAABAD8ACQACCfYbYDIArgACaAwAAAQAVQDqDAAABQA5AC4ABAp/JwADCAAJCYkjugEAxgIACAAICaIjugEAxgIACQAFCbofTScA0QEAAAA=.',
Ba='Babymager:BAABLgAECn8dAAIKAAYJSQ2MgwASAQZoDAAABwApAGkMAAAGACcAawwAAAUAIABqDAAAAwAqAGwMAAADABcA6gwAAAUAIQAKAAYJSQ2MgwASAQZoDAAABwApAGkMAAAGACcAawwAAAUAIABqDAAAAwAqAGwMAAADABcA6gwAAAUAIQAAAA==.Babyshamz:BAAALgADCggJCAAAAA==.',
Be='Beartwige:BAAALgADCgYJBgAAAA==.Belladonnà:BAAALgADCgQJBAAAAA==.Betsy:BAAALgAECgQJBAAAAA==.',
Bi='Bigpopapump:BAACLgAFFH8MAAILAAMJnhodAwDLAANoDAAABgBhAGkMAAAEADoA6gwAAAIAMAALAAMJnhodAwDLAANoDAAABgBhAGkMAAAEADoA6gwAAAIAMAAuAAQKfzMAAgsACAlEJpsBAPsCAAsACAlEJpsBAPsCAAAA.Bishop:BAAALgADCgMJAwAAAA==.',
Bl='Blackgarden:BAAALgAECgUJBwAAAA==.Bloodydak:BAEALgAECgcJBwABLgAECgYJDwAMAAAAAA==.',
Bo='Bombasharna:BAAALgADCgMJBQAAAA==.Bonkzx:BAAALgADCgMJAwAAAA==.Booze:BAAALgAECggJDgAAAA==.',
Br='Brigne:BAAALgADCgYJCwAAAA==.',
Bu='Buddeez:BAACLgAFFH8TAAIKAAUJ8B1wGACGAQVoDAAABgBjAGkMAAADAFEAawwAAAQAKQBqDAAAAQAuAOoMAAAFAFMACgAFCfAdcBgAhgEFaAwAAAYAYwBpDAAAAwBRAGsMAAAEACkAagwAAAEALgDqDAAABQBTAC4ABAp/KwACCgAJCT8lUAoAcQMACgAJCT8lUAoAcQMAAAA=.Built:BAABLgAECn8dAAQLAAgJ8CA/DAAJAghoDAAABQBfAGkMAAAFAF8AawwAAAUAWgBqDAAAAwA4AGwMAAADAFsAbQwAAAEATQDqDAAABQBZAG4MAAACADEACwAHCf8gPwwACQIHaAwAAAQAXwBpDAAABABfAGsMAAAFAFoAagwAAAMAOABsDAAAAwBbAOoMAAAEAFMAbgwAAAIAMQANAAMJTBi6fwDoAANoDAAAAQATAG0MAAABAE0A6gwAAAEAWQAOAAEJ2hhogQBBAAFpDAAAAQA/AAAA.',
Ca='Cabbage:BAAALgADCgEJAQAAAA==.',
Ce='Cenwen:BAACLgAFFH8HAAIKAAMJjQt8UADxAANoDAAAAwAiAGkMAAADACAA6gwAAAEAFgAKAAMJjQt8UADxAANoDAAAAwAiAGkMAAADACAA6gwAAAEAFgAuAAQKfx8AAgoABwlzHMpfABwCAAoABwlzHMpfABwCAAAA.',
Ch='Chaos:BAABLgAECn8nAAILAAkJAiAnAgDdAgloDAAABQBOAGkMAAAGAFEAawwAAAUAUQBqDAAABABRAGwMAAAFAFgAbQwAAAMAVQDqDAAABQBaAG4MAAAEAEMAbwwAAAIAUwALAAkJAiAnAgDdAgloDAAABQBOAGkMAAAGAFEAawwAAAUAUQBqDAAABABRAGwMAAAFAFgAbQwAAAMAVQDqDAAABQBaAG4MAAAEAEMAbwwAAAIAUwAAAA==.Chonk:BAAALgADCgYJCQAAAA==.Chugginjizz:BAAALgAECgEJAQABLgAFFAYJGAAPALAVAA==.',
Cl='Clawreece:BAAALgAECgQJBQAAAA==.',
Co='Conta:BAAALgAECgMJAwAAAA==.',
Cr='Cryingtears:BAABLgAECn8jAAMQAAgJgw2xMQAYAQhoDAAABwA7AGkMAAAGAEAAawwAAAYAOwBqDAAABAARAGwMAAADAAgAbQwAAAEABADqDAAABQA2AG4MAAADAAgAEAAICYMNsTEAGAEIaAwAAAUAOwBpDAAABABAAGsMAAAEADsAagwAAAEAEQBsDAAAAQAIAG0MAAABAAQA6gwAAAMANgBuDAAAAgAIAAYABwmpBrF+APoAB2gMAAACABwAaQwAAAIAFABrDAAAAgARAGoMAAADABEAbAwAAAIADwDqDAAAAgAMAG4MAAABAAgAAAA=.',
Cu='Cuchicu:BAABLgAECn8vAAIRAAkJPBqpDACMAgloDAAACABcAGkMAAAIAFYAawwAAAcAVgBqDAAABQBAAGwMAAAFAEkAbQwAAAMAJQDqDAAABwBMAG4MAAACACgAbwwAAAIALQARAAkJPBqpDACMAgloDAAACABcAGkMAAAIAFYAawwAAAcAVgBqDAAABQBAAGwMAAAFAEkAbQwAAAMAJQDqDAAABwBMAG4MAAACACgAbwwAAAIALQAAAA==.',
Da='Dakkonix:BAEALgAECgYJDwAAAA==.Dakkonixx:BAEALgAECgUJBQABLgAECgYJDwAMAAAAAA==.Damagexx:BAAALgAECgEJAQAAAA==.Darkaged:BAAALgADCgYJBgAAAA==.Darklords:BAAALgADCgEJAQAAAA==.',
De='Demonasa:BAAALgADCgIJAgAAAA==.Desim:BAABLgAECn8WAAIPAAcJsx6BMwBpAgdoDAAABABcAGkMAAAEAFgAawwAAAQAVQBqDAAAAgBbAGwMAAACAEUA6gwAAAUAUwBuDAAAAQA0AA8ABwmzHoEzAGkCB2gMAAAEAFwAaQwAAAQAWABrDAAABABVAGoMAAACAFsAbAwAAAIARQDqDAAABQBTAG4MAAABADQAAAA=.Dextt:BAABLgAECn8dAAISAAcJLCIsDgCpAgdoDAAABQBcAGkMAAAFAGMAawwAAAUAYgBqDAAABQBbAGwMAAADAFsAbQwAAAIAKgDqDAAABABhABIABwksIiwOAKkCB2gMAAAFAFwAaQwAAAUAYwBrDAAABQBiAGoMAAAFAFsAbAwAAAMAWwBtDAAAAgAqAOoMAAAEAGEAAAA=.Dez:BAABLgAECn8XAAIQAAgJfRCSHwCWAQhoDAAAAwArAGkMAAADACwAawwAAAMAHABqDAAABABEAGwMAAAEAC4AbQwAAAIAEQDqDAAAAwAsAG4MAAABACsAEAAICX0Qkh8AlgEIaAwAAAMAKwBpDAAAAwAsAGsMAAADABwAagwAAAQARABsDAAABAAuAG0MAAACABEA6gwAAAMALABuDAAAAQArAAAA.',
Dk='Dkamp:BAAALgADCgQJDAAAAA==.',
Dm='Dmoney:BAAALgAECgYJBgAAAA==.',
Do='Dondiablo:BAAALgAECgYJDQAAAA==.Doylock:BAAALgAECgUJBQAAAA==.',
Dr='Dragnaballs:BAAALgAECgcJEgABLgAFFAgJIQAKAGMWAA==.Drehd:BAACLgAFFH8KAAISAAMJvCQOEwA5AQNoDAAABQBfAGkMAAADAF8A6gwAAAIAWgASAAMJvCQOEwA5AQNoDAAABQBfAGkMAAADAF8A6gwAAAIAWgAuAAQKfy0AAhIACAnWJKACADwDABIACAnWJKACADwDAAAA.Drewcifer:BAABLgAECn8iAAITAAkJhR6BFgDQAgloDAAABQBbAGkMAAAFAFcAawwAAAUAXQBqDAAABABeAGwMAAADAFIAbQwAAAMAQADqDAAABQBPAG4MAAADAEoAbwwAAAEAMwATAAkJhR6BFgDQAgloDAAABQBbAGkMAAAFAFcAawwAAAUAXQBqDAAABABeAGwMAAADAFIAbQwAAAMAQADqDAAABQBPAG4MAAADAEoAbwwAAAEAMwABLgAECgkJIgATAIUeAA==.Drewwar:BAAALgAECgEJAQABLgAECgkJIgATAIUeAA==.Dripps:BAAALgAECgYJBgAAAA==.',
Du='Dumper:BAAALgADCgEJAQAAAA==.Dumps:BAAALgAECgMJAwAAAA==.',
['Dó']='Dóom:BAAALgAECgUJCQAAAA==.',
['Dü']='Düsk:BAAALgADCgUJBQABLgAECgEJAwAMAAAAAA==.',
Eg='Egoon:BAAALgAECgQJBQAAAA==.',
El='Elmerfud:BAAALgAECgYJBwAAAA==.',
En='Enrèk:BAAALgADCgYJBgAAAA==.',
Fa='Falafel:BAACLgAFFH8NAAIPAAUJBR+3HQBrAQVoDAAAAwBVAGkMAAADAE0AawwAAAMAPwBqDAAAAQA2AOoMAAADAFoADwAFCQUftx0AawEFaAwAAAMAVQBpDAAAAwBNAGsMAAADAD8AagwAAAEANgDqDAAAAwBaAC4ABAp/JQACDwAJCZwh7BIACgMADwAJCZwh7BIACgMAAAA=.',
Fi='Fidely:BAAALgADCgEJAQAAAA==.',
Fo='Fomo:BAAALgADCgYJBgAAAA==.Fornax:BAAALgAECgQJBwABLgAECgcJFwAKAA8MAA==.Fotmtrash:BAACLgAFFH8IAAMUAAQJbRJQEQDTAARoDAAABABBAGkMAAACAFUAawwAAAEAHQDqDAAAAQAIABQAAwm8FFARANMAA2gMAAAEAEEAaQwAAAIAVQDqDAAAAQAIABUAAQl/C1MoAE8AAWsMAAABAB0ALgAECn8mAAQUAAgJVCLvBwDMAgAUAAgJGiLvBwDMAgAVAAUJiB53EgDBAQAWAAIJJwleWgBOAAAAAA==.Foxxydots:BAABLgAECn8mAAIJAAgJSRa1LwCqAQhoDAAABgBNAGkMAAAGADoAawwAAAYAPgBqDAAABQA8AGwMAAAFAEcAbQwAAAMAKwDqDAAABgBBAG4MAAABABQACQAICUkWtS8AqgEIaAwAAAYATQBpDAAABgA6AGsMAAAGAD4AagwAAAUAPABsDAAABQBHAG0MAAADACsA6gwAAAYAQQBuDAAAAQAUAAAA.',
Fr='Frostitoot:BAABLgAECn8XAAIKAAcJDwwfagBEAQdoDAAABAAnAGkMAAAEABwAawwAAAQAMABqDAAAAwAcAGwMAAADAB0A6gwAAAQAJABuDAAAAQADAAoABwkPDB9qAEQBB2gMAAAEACcAaQwAAAQAHABrDAAABAAwAGoMAAADABwAbAwAAAMAHQDqDAAABAAkAG4MAAABAAMAAAA=.',
Ga='Galbsadi:BAABLgAECn8cAAMXAAgJthJPCQBLAQhoDAAABQA6AGkMAAAFADwAawwAAAUAMwBqDAAABAArAGwMAAADACgAbQwAAAEAGgDqDAAABAA+AG4MAAABACQAFwAHCbUPTwkASwEHaQwAAAEAGgBrDAAAAQAyAGoMAAADACsAbAwAAAEAKABtDAAAAQAaAOoMAAABAD4AbgwAAAEAJAAJAAYJDRBKYwAOAQZoDAAABQA6AGkMAAAEADwAawwAAAQAMwBqDAAAAQAXAGwMAAACABAA6gwAAAMAEgAAAA==.Garrius:BAAALgADCgQJBAAAAA==.',
Ge='Gelfdar:BAAALgAECgEJAQAAAA==.Gethendriel:BAAALgAECgQJCQAAAA==.',
Gl='Glaia:BAAALgADCgYJDQAAAA==.',
Go='Goel:BAAALgAECgEJAgAAAA==.',
Gr='Graf:BAABLgAECn8dAAQYAAgJ6h7cHABnAghoDAAABQBZAGkMAAAEAE4AawwAAAUASQBqDAAAAwBTAGwMAAAEAFIA6gwAAAUAUwBuDAAAAgBOAG8MAAABAEMAGAAHCZEf3BwAZwIHaAwAAAMAWQBpDAAAAgBOAGsMAAADAEgAagwAAAMAUwBsDAAAAwBSAOoMAAAEAFMAbgwAAAEATgABAAYJPRgFGwAZAQZoDAAAAQBNAGkMAAABADQAawwAAAEAEADqDAAAAQBRAG4MAAABAE0AbwwAAAEAQwAZAAQJQRM6LwDJAARoDAAAAQAyAGkMAAABACoAawwAAAEASQBsDAAAAQAeAAAA.Grimzorath:BAAALgAECgYJBgAAAA==.Grox:BAABLgAECn8UAAIYAAYJmg+qTgBsAQZoDAAABAA+AGkMAAAEAC4AawwAAAQAKgBqDAAAAwAlAGwMAAACABMA6gwAAAMAHAAYAAYJmg+qTgBsAQZoDAAABAA+AGkMAAAEAC4AawwAAAQAKgBqDAAAAwAlAGwMAAACABMA6gwAAAMAHAAAAA==.Grudge:BAAALgADCgMJBQAAAA==.',
Ha='Hackensack:BAAALgAECgcJDwAAAA==.Hamtaro:BAAALgAECgEJAQAAAA==.Hawthorne:BAABLgAECn8aAAIHAAcJ7x3bFAAgAgdoDAAABQBQAGkMAAAFAFsAawwAAAQAUQBqDAAAAwBWAGwMAAAEAFkAbQwAAAEAJgDqDAAABABDAAcABwnvHdsUACACB2gMAAAFAFAAaQwAAAUAWwBrDAAABABRAGoMAAADAFYAbAwAAAQAWQBtDAAAAQAmAOoMAAAEAEMAAAA=.',
Hi='Hiyabusa:BAAALgAECgYJEgAAAA==.',
Ho='Hollowboi:BAABLgAECn8pAAIaAAgJ2x4OBwBrAghoDAAABwBZAGkMAAAHAFMAawwAAAcATgBqDAAABQBIAGwMAAAFAEgAbQwAAAIATgDqDAAABgBRAG4MAAACAEQAGgAICdseDgcAawIIaAwAAAcAWQBpDAAABwBTAGsMAAAHAE4AagwAAAUASABsDAAABQBIAG0MAAACAE4A6gwAAAYAUQBuDAAAAgBEAAAA.Holygraf:BAAALgAECgcJDgAAAA==.',
Ia='Iamyama:BAAALgAECgUJCQAAAA==.',
Io='Ionna:BAAALgADCgcJBwAAAA==.',
Jd='Jdvance:BAAALgAECgYJBgAAAA==.',
Jh='Jhouska:BAAALgAECgcJEAAAAA==.',
Jo='Jormunngandr:BAACLgAFFH8YAAMPAAYJsBULEACcAQZoDAAABABTAGkMAAAFAEEAawwAAAQAQwBqDAAAAwA7AG0MAAABAAYA6gwAAAcANgAPAAUJsBULEACcAQVoDAAABABTAGkMAAAFAEEAawwAAAQAQwBtDAAAAQAGAOoMAAAHADYAGwABCQAAMxUARgABagwAAAMAOwAuAAQKfx8AAg8ACQm9IKkRABIDAA8ACQm9IKkRABIDAAAA.',
Ju='Judgynomnom:BAACLgAFFH8GAAIQAAQJ8xYgEQA3AQRoDAAAAgBhAGkMAAACAFMAawwAAAEAGQDqDAAAAQAcABAABAnzFiARADcBBGgMAAACAGEAaQwAAAIAUwBrDAAAAQAZAOoMAAABABwALgAECn8cAAIQAAgJaCbcCQDUAgAQAAgJaCbcCQDUAgAAAA==.',
Jy='Jyggles:BAAALgAECgYJCgAAAA==.',
Ki='Kirax:BAAALgADCgEJAQAAAA==.',
Ko='Konataizumi:BAAALgADCgcJCwAAAA==.',
Kr='Kruhks:BAAALgAECgYJCAABLgAFFAMJCgASALwkAA==.',
Ks='Kshot:BAABLgAECn8vAAILAAkJ8x5EAwCtAgloDAAABwBSAGkMAAAGAF4AawwAAAYATwBqDAAABgBQAGwMAAAGAFAAbQwAAAQASADqDAAABgBcAG4MAAAEAE8AbwwAAAIANAALAAkJ8x5EAwCtAgloDAAABwBSAGkMAAAGAF4AawwAAAYATwBqDAAABgBQAGwMAAAGAFAAbQwAAAQASADqDAAABgBcAG4MAAAEAE8AbwwAAAIANAAAAA==.',
La='Lagdalen:BAABLgAECn8VAAIUAAYJQRuVEgDVAQZoDAAABABfAGkMAAAFAEAAawwAAAUAXABqDAAAAQAZAOoMAAAFAEUAbgwAAAEARwAUAAYJQRuVEgDVAQZoDAAABABfAGkMAAAFAEAAawwAAAUAXABqDAAAAQAZAOoMAAAFAEUAbgwAAAEARwAAAA==.Lanachan:BAABLgAECn8iAAIYAAgJTw3OJQBKAQhoDAAABgAqAGkMAAAFACgAawwAAAUAFQBqDAAABQAuAGwMAAAEACMAbQwAAAEAIgDqDAAABwAoAG4MAAABABcAGAAICU8NziUASgEIaAwAAAYAKgBpDAAABQAoAGsMAAAFABUAagwAAAUALgBsDAAABAAjAG0MAAABACIA6gwAAAcAKABuDAAAAQAXAAAA.',
Ld='Ldn:BAABLgAECn8nAAIKAAgJMRCFRAChAQhoDAAABwA+AGkMAAAGADAAawwAAAYAJABqDAAABgAvAGwMAAAFAC8AbQwAAAIAGQDqDAAABgA1AG4MAAABABAACgAICTEQhUQAoQEIaAwAAAcAPgBpDAAABgAwAGsMAAAGACQAagwAAAYALwBsDAAABQAvAG0MAAACABkA6gwAAAYANQBuDAAAAQAQAAAA.',
Le='Lep:BAAALgADCgcJDQAAAA==.',
Li='Likai:BAAALgADCgUJBQAAAA==.Lisa:BAAALgADCgcJAQAAAA==.Liz:BAABLgAECn8fAAINAAgJUwb0SQAwAQhoDAAABQAQAGkMAAAFABcAawwAAAUADwBqDAAABQAWAGwMAAAFAA8AbQwAAAIAEwDqDAAAAwASAG4MAAABAAQADQAICVMG9EkAMAEIaAwAAAUAEABpDAAABQAXAGsMAAAFAA8AagwAAAUAFgBsDAAABQAPAG0MAAACABMA6gwAAAMAEgBuDAAAAQAEAAAA.',
Ly='Lylieth:BAABLgAECn8rAAIJAAkJ0BEtHwD8AQloDAAABgBJAGkMAAAFAC0AawwAAAYAMgBqDAAABQAmAGwMAAAFAC8AbQwAAAMAJwDqDAAABwA1AG4MAAAEACgAbwwAAAIADwAJAAkJ0BEtHwD8AQloDAAABgBJAGkMAAAFAC0AawwAAAYAMgBqDAAABQAmAGwMAAAFAC8AbQwAAAMAJwDqDAAABwA1AG4MAAAEACgAbwwAAAIADwAAAA==.Lyndyn:BAAALgADCgIJAgAAAA==.',
Ma='Mather:BAAALgAECgEJAgAAAA==.Mayzel:BAAALgAECgMJBAAAAA==.',
Mi='Microsqueeze:BAAALgADCgkJCQAAAA==.',
Mo='Mock:BAAALgAECgYJBwABLgAECgcJEAAMAAAAAA==.Mogera:BAAALgADCgMJBQAAAA==.',
Ni='Ninluv:BAAALgAECgQJDgAAAA==.',
Ny='Nyancat:BAAALgADCgkJCgAAAA==.',
Ol='Olaho:BAAALgADCgYJBgAAAA==.',
Om='Omenz:BAAALgADCgIJAgAAAA==.',
Oo='Oojni:BAAALgADCgYJBgAAAA==.',
Pa='Pazzman:BAAALgADCgYJBwAAAA==.',
Pe='Perc:BAAALgAECgQJBAAAAA==.',
Ph='Pharhar:BAABLgAECn8iAAMQAAgJdhuTHAAxAghoDAAABgBcAGkMAAAGAGMAawwAAAYAYQBqDAAABABQAGwMAAAEAEAAbQwAAAIAJwDqDAAABABRAG4MAAACAAgAEAAICXYbkxwAMQIIaAwAAAMAXABpDAAABQBjAGsMAAAGAGEAagwAAAQAUABsDAAABABAAG0MAAACACcA6gwAAAQAUQBuDAAAAQAIAAYAAwl9EZicAMMAA2gMAAADAEAAaQwAAAEAKQBuDAAAAQAcAAAA.',
Po='Poppachàdson:BAABLgAECn8dAAIcAAcJ+CDSCABPAgdoDAAABABbAGkMAAAFAFwAawwAAAUAVwBqDAAABQBFAGwMAAACAEQA6gwAAAYAYQBuDAAAAgBFABwABwn4INIIAE8CB2gMAAAEAFsAaQwAAAUAXABrDAAABQBXAGoMAAAFAEUAbAwAAAIARADqDAAABgBhAG4MAAACAEUAAS4ABRQDCQYAHAAaFQA=.Poppadadson:BAACLgAFFH8GAAIcAAMJGhUpBQD8AANoDAAAAwAsAGkMAAABACUA6gwAAAIAUAAcAAMJGhUpBQD8AANoDAAAAwAsAGkMAAABACUA6gwAAAIAUAAuAAQKfxwAAhwABwmBH4kGAI0CABwABwmBH4kGAI0CAAAA.Poppadotson:BAAALgAECgMJAwABLgAFFAMJBgAcABoVAA==.',
Pu='Puscifer:BAAALgAECgkJBAAAAA==.',
Qu='Quarrior:BAAALgADCgEJAQABLgAECgEJAwAMAAAAAA==.Quellazaire:BAAALgADCgcJDAAAAA==.Quincar:BAAALgADCgEJAQABLgAECgEJAwAMAAAAAA==.',
Ra='Ravister:BAAALgAECgUJBQABLgAFFAUJFAAWAGgjAA==.',
Re='Relic:BAACLgAFFH8SAAMdAAUJyRWEAgBEAQVoDAAABQBHAGkMAAAEAEwAawwAAAMAIgBqDAAAAgAaAOoMAAAEACkAHQAECckVhAIARAEEaAwAAAUARwBpDAAABABMAGsMAAADACIA6gwAAAMAKQAbAAIJxQvNIQA4AAJqDAAAAgAaAOoMAAABAB4ALgAECn8dAAIdAAkJ4xyTAgCMAgAdAAkJ4xyTAgCMAgAAAA==.Renk:BAABLgAECn8iAAIPAAcJ1SW8DwCNAgdoDAAABwBhAGkMAAAHAGMAawwAAAYAYABqDAAABABjAGwMAAAEAF0AbQwAAAEAYADqDAAABQBhAA8ABwnVJbwPAI0CB2gMAAAHAGEAaQwAAAcAYwBrDAAABgBgAGoMAAAEAGMAbAwAAAQAXQBtDAAAAQBgAOoMAAAFAGEAAAA=.Renka:BAAALgADCggJCAAAAA==.',
Ro='Ronald:BAABLgAECn8UAAIGAAYJZRrflgBPAQZoDAAAAgBIAGkMAAACAEsAawwAAAIATgBqDAAAAQAPAOoMAAAHAEMAbgwAAAYAKwAGAAYJZRrflgBPAQZoDAAAAgBIAGkMAAACAEsAawwAAAIATgBqDAAAAQAPAOoMAAAHAEMAbgwAAAYAKwAAAA==.Roykevious:BAAALgAECgEJAwAAAA==.',
Sa='Saeyl:BAAALgAECgYJDAABLgAECgkJFwAVAJsJAA==.Sammie:BAEALgAECgUJBgABLgAECgYJDwAMAAAAAA==.Savant:BAAALgADCgEJAQAAAA==.Sayl:BAABLgAECn8XAAMVAAkJmwlCLgAsAQloDAAAAwAjAGkMAAACABIAawwAAAIAGQBqDAAAAgAqAGwMAAADABEAbQwAAAIAJQDqDAAABQAQAG4MAAADAA0AbwwAAAEADQAVAAYJNQpCLgAsAQZoDAAAAwAjAGkMAAACABIAawwAAAIAGQBqDAAAAgAqAGwMAAACABEA6gwAAAQAEAAWAAUJMwgcMwDQAAVsDAAAAQATAG0MAAACABEA6gwAAAEAFQBuDAAAAwAeAG8MAAABAA8AAAA=.',
Sc='Scallywinkle:BAAALgAECgcJEAAAAA==.Scrap:BAABLgAECn8aAAMJAAkJ4hqIPgATAgloDAAABABSAGkMAAADAFUAawwAAAMARABqDAAAAwBBAGwMAAADAEIAbQwAAAIAQQDqDAAABABFAG4MAAADAEUAbwwAAAEAKwAJAAgJcBqIPgATAghoDAAABABSAGkMAAADAFUAawwAAAEAPQBsDAAAAQA/AG0MAAABAEEA6gwAAAQARQBuDAAAAwBFAG8MAAABACsAFwAECXkU4SsAEAEEawwAAAIARABqDAAAAwBBAGwMAAACAEIAbQwAAAEAFgAAAA==.',
Se='Senova:BAAALgAECgIJAgAAAA==.',
Sh='Shadowghoul:BAAALgAECgcJCAAAAA==.Shadowydern:BAABLgAECn8jAAMWAAgJySGNBACqAghoDAAABgBhAGkMAAAGAFUAawwAAAUAVABqDAAABABgAGwMAAAEAF4AbQwAAAIAWADqDAAABQBTAG4MAAADAEcAFgAICckhjQQAqgIIaAwAAAYAYQBpDAAABgBVAGsMAAAEAFQAagwAAAQAYABsDAAABABeAG0MAAACAFgA6gwAAAUAUwBuDAAAAwBHABQAAQn9EGl/ADMAAWsMAAABACsAAAA=.Shamewow:BAACLgAFFH8RAAISAAUJghjjDABvAQVoDAAABQBLAGkMAAAEAEAAawwAAAIAPwBqDAAAAQArAOoMAAAFAEIAEgAFCYIY4wwAbwEFaAwAAAUASwBpDAAABABAAGsMAAACAD8AagwAAAEAKwDqDAAABQBCAC4ABAp/KwACEgAJCWEaSxkATAIAEgAJCWEaSxkATAIAAAA=.',
Si='Sicknnasty:BAACLgAFFH8PAAIbAAUJjRLOBwARAQVoDAAABQBFAGkMAAAEADEAawwAAAIAHwBqDAAAAQBLAOoMAAADACcAGwAFCY0SzgcAEQEFaAwAAAUARQBpDAAABAAxAGsMAAACAB8AagwAAAEASwDqDAAAAwAnAC4ABAp/NgADGwAICSUgFQkA+wEAGwAHCYMiFQkA+wEADwAICcgUXywA1QEAAAA=.',
Sl='Slayerz:BAAALgAECgYJBgAAAA==.',
Sn='Snattch:BAAALgADCgEJAQAAAA==.Snookismalls:BAAALgAECgcJEAAAAA==.',
So='Solarian:BAAALgADCgMJAwAAAA==.Solitary:BAAALgAECgcJEgAAAA==.',
Sp='Speed:BAAALgAECgYJCwAAAA==.Spinach:BAAALgAECgMJAQAAAA==.',
St='Starshopping:BAABLgAECn8UAAITAAgJmiFlFQDWAghoDAAAAgBhAGkMAAADAFgAawwAAAMAWABqDAAAAwBaAGwMAAADAFoAbQwAAAIAUwDqDAAAAgBPAG4MAAACAEoAEwAICZohZRUA1gIIaAwAAAIAYQBpDAAAAwBYAGsMAAADAFgAagwAAAMAWgBsDAAAAwBaAG0MAAACAFMA6gwAAAIATwBuDAAAAgBKAAEuAAQKCQknAAsAAiAA.',
Su='Sunari:BAAALgADCgQJBAAAAA==.',
Ta='Taewryn:BAAALgAFFAQJBAABLgAFFAcJIAAaAOchAA==.Talrip:BAABLgAECn8dAAIeAAgJcx7YBgAgAghoDAAABQA4AGkMAAAFAFsAawwAAAUAUgBqDAAAAwAyAGwMAAADAFEAbQwAAAEAWgDqDAAABQA8AG4MAAACAFIAHgAICXMe2AYAIAIIaAwAAAUAOABpDAAABQBbAGsMAAAFAFIAagwAAAMAMgBsDAAAAwBRAG0MAAABAFoA6gwAAAUAPABuDAAAAgBSAAAA.',
Th='Thicctrix:BAAALgADCgcJDAAAAA==.Thundon:BAAALgADCgcJCQAAAA==.',
To='Toatem:BAAALgAECgUJBQAAAA==.Toro:BAACLgAFFH8VAAIYAAUJByItBACQAQVoDAAABgBhAGkMAAAFAGAAawwAAAQANwBqDAAAAQAOAOoMAAAFAGIAGAAFCQciLQQAkAEFaAwAAAYAYQBpDAAABQBgAGsMAAAEADcAagwAAAEADgDqDAAABQBiAC4ABAp/KwACGAAJCXckZAUAUAMAGAAJCXckZAUAUAMAAAA=.',
Tr='Traitor:BAAALgADCgEJAQAAAA==.Trappynomnom:BAAALgADCggJDQAAAA==.Tree:BAABLgAFFH8MAAIRAAQJAiR4CQCtAQRoDAAABABiAGkMAAACAGMAawwAAAEASQDqDAAABQBiABEABAkCJHgJAK0BBGgMAAAEAGIAaQwAAAIAYwBrDAAAAQBJAOoMAAAFAGIAAAA=.Treegrundler:BAAALgAECgYJEwAAAA==.Treeus:BAAALgAECgYJCQAAAA==.Trixulous:BAAALgADCgkJJQAAAA==.',
Tw='Twiigee:BAABLgAECn8XAAIaAAYJWSAOIAABAgZoDAAABQBfAGkMAAAFAFMAawwAAAQAVABqDAAAAgAxAGwMAAACAEMA6gwAAAUAUwAaAAYJWSAOIAABAgZoDAAABQBfAGkMAAAFAFMAawwAAAQAVABqDAAAAgAxAGwMAAACAEMA6gwAAAUAUwAAAA==.',
Tz='Tzungxie:BAABLgAECn8nAAIfAAkJWB1FAwCuAgloDAAABwBRAGkMAAAHAEEAawwAAAYASgBqDAAAAwA/AGwMAAAEAEkAbQwAAAIAUwDqDAAABgBTAG4MAAACAFoAbwwAAAIAMQAfAAkJWB1FAwCuAgloDAAABwBRAGkMAAAHAEEAawwAAAYASgBqDAAAAwA/AGwMAAAEAEkAbQwAAAIAUwDqDAAABgBTAG4MAAACAFoAbwwAAAIAMQAAAA==.',
Un='Unholylord:BAACLgAFFH8UAAIWAAUJaCOiBQCMAQVoDAAABwBTAGkMAAAFAGMAawwAAAMAWQBqDAAAAQAeAOoMAAAEAFkAFgAFCWgjogUAjAEFaAwAAAcAUwBpDAAABQBjAGsMAAADAFkAagwAAAEAHgDqDAAABABZAC4ABAp/IAACFgAJCTYjygQARwMAFgAJCTYjygQARwMAAAA=.',
Va='Vae:BAAALgAECgMJAwAAAA==.Vagbadge:BAAALgAECgkJCQABLgAFFAUJFAAWAGgjAA==.Varroww:BAAALgAECgYJEQAAAA==.',
Vo='Vosxo:BAAALgAECgEJAQAAAA==.',
['Ví']='Vígo:BAABLgAECn8ZAAIBAAYJ7QiRHgDTAAZoDAAABgANAGkMAAAFACYAawwAAAUAGABqDAAAAwAaAGwMAAACAAkA6gwAAAQAGwABAAYJ7QiRHgDTAAZoDAAABgANAGkMAAAFACYAawwAAAUAGABqDAAAAwAaAGwMAAACAAkA6gwAAAQAGwAAAA==.',
Wa='Wado:BAAALgAECgEJAQAAAA==.',
We='Wellíngton:BAAALgAECgEJAQAAAA==.',
Wh='Whack:BAAALgADCgYJBgAAAA==.',
Wi='Wicke:BAAALgADCgQJBAABLgAECgEJAQAMAAAAAA==.',
Wo='Wolfthetree:BAAALgAECgUJCAAAAA==.',
Wy='Wystarr:BAAALgADCgIJAgAAAA==.',
Xa='Xamael:BAAALgADCgMJAwAAAA==.',
Xe='Xerkz:BAAALgAECgEJAQAAAA==.',
Ys='Ystarian:BAABLgAECn88AAQCAAkJrRujAQBuAgloDAAACgBVAGkMAAAIAFUAawwAAAgASQBqDAAABwBdAGwMAAAIAFQAbQwAAAQAPgDqDAAACgBNAG4MAAAEAD0AbwwAAAEAIwACAAkJrRujAQBuAgloDAAABwBVAGkMAAAFAFUAawwAAAQASQBqDAAABQBdAGwMAAAHAFQAbQwAAAIAPgDqDAAABgBNAG4MAAACAD0AbwwAAAEAIwADAAgJBhQXHQDeAQhoDAAAAwAwAGkMAAADADgAawwAAAQANABqDAAAAgAyAGwMAAABADUAbQwAAAIAMgDqDAAAAwBIAG4MAAACABgABAABCRsB8E4AIAAB6gwAAAEAAgAAAA==.',
Za='Zaptik:BAAALgAECgEJAQAAAA==.',
['Ël']='Ëlëmëntary:BAAALgAECgcJBgAAAA==.',
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
