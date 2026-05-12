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

local lookup = {'Warrior-Arms','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Paladin-Protection','Paladin-Retribution','Monk-Mistweaver','Monk-Brewmaster','Warlock-Affliction','Warlock-Demonology','Mage-Frost','Hunter-Survival','Unknown-Unknown','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Unholy','Paladin-Holy','Druid-Restoration','Shaman-Restoration','DemonHunter-Devourer','Priest-Holy','Priest-Discipline','Priest-Shadow','Warlock-Destruction','Warrior-Fury','Warrior-Protection','DeathKnight-Blood','Shaman-Enhancement','DeathKnight-Frost','DemonHunter-Vengeance','Rogue-Subtlety',}
local provider = {region='US',realm='TheUnderbog',name='US',type='daily',zone=46,date='2026-05-12',data={Ac='Acinovanth:BAAALgAECgEJAQAAAA==.Acousticjeff:BAAALgAECgYJBgAAAA==.',
Ad='Adwill:BAABLgAECn8eAAIBAAcJIiC0BQAtAgdoDAAABgBYAGkMAAAFAFUAawwAAAUAVQBqDAAABQBUAGwMAAADAFQAbQwAAAIARwDqDAAABABNAAEABwkiILQFAC0CB2gMAAAGAFgAaQwAAAUAVQBrDAAABQBVAGoMAAAFAFQAbAwAAAMAVABtDAAAAgBHAOoMAAAEAE0AAAA=.',
Ae='Aelvoker:BAACLgAFFH8SAAQCAAUJ9BkNBAAJAQVoDAAABAA/AGkMAAAEADEAawwAAAMAOQBqDAAAAgAlAOoMAAAFAF8AAgAECT4VDQQACQEEaAwAAAEAPwBpDAAAAQABAGsMAAACADkA6gwAAAQAXwADAAQJERJVJADgAARoDAAAAgA9AGkMAAACADEAawwAAAEAGwBqDAAAAQAlAAQABAnuBoETAJAABGgMAAABACwAaQwAAAEADABqDAAAAQALAOoMAAABAAMALgAECn8XAAQCAAkJRR9RBwB3AgACAAYJJCNRBwB3AgAEAAcJnRGJGgC3AQADAAIJ3RrRSgCpAAAAAA==.',
Ai='Aindra:BAAALgAECggJEAAAAA==.Airen:BAAALgAECgQJBQAAAA==.',
An='Antidead:BAABLgAECn8gAAMFAAgJOR50BQCfAghoDAAABQBOAGkMAAAFAE8AawwAAAUARABqDAAABAA4AGwMAAAEAFIAbQwAAAIAUgDqDAAABQBSAG4MAAACAEMABQAICTkedAUAnwIIaAwAAAQATgBpDAAABABPAGsMAAAEAEQAagwAAAMAOABsDAAAAwBSAG0MAAABAFIA6gwAAAQAUgBuDAAAAQBDAAYACAnXEyU2ALsBCGgMAAABADoAaQwAAAEAKQBrDAAAAQA3AGoMAAABACoAbAwAAAEAMwBtDAAAAQAyAOoMAAABAC4AbgwAAAEANAAAAA==.',
Ap='Apachaler:BAABLgAECn8cAAMHAAcJ3x2GDwAOAgdoDAAABwBSAGkMAAAFAF0AawwAAAQAUgBqDAAAAwBPAGwMAAADAEEAbQwAAAEANgDqDAAABQBMAAcABwnfHYYPAA4CB2gMAAAGAFIAaQwAAAUAXQBrDAAABABSAGoMAAADAE8AbAwAAAMAQQBtDAAAAQA2AOoMAAAFAEwACAABCTYZm18ASQABaAwAAAEAQAAAAA==.',
Ar='Arathael:BAAALgADCgIJAgAAAA==.Ardyce:BAAALgADCgIJAgAAAA==.Arrae:BAAALgAECgUJAwAAAA==.Arreuws:BAAALgAECgQJBAAAAA==.',
As='Asiansmoliv:BAACLgAFFH8LAAMJAAMJ4BriAwC2AANoDAAABQBVAGkMAAABAD8A6gwAAAUAOQAJAAIJ9BniAwC2AAJoDAAAAQBFAGkMAAABAD8ACgACCfYbZTIArgACaAwAAAQAVQDqDAAABQA5AC4ABAp/JwADCQAJCYkjugEAxgIACQAICaIjugEAxgIACgAFCbofaykA0AEAAAA=.',
Ba='Babymager:BAABLgAECn8dAAILAAYJSQ2rhgAYAQZoDAAABwApAGkMAAAGACcAawwAAAUAIABqDAAAAwAqAGwMAAADABcA6gwAAAUAIQALAAYJSQ2rhgAYAQZoDAAABwApAGkMAAAGACcAawwAAAUAIABqDAAAAwAqAGwMAAADABcA6gwAAAUAIQAAAA==.Babyshamz:BAAALgADCggJCAAAAA==.',
Be='Beartwige:BAAALgADCgYJBgAAAA==.Belladonnà:BAAALgADCgQJBAAAAA==.Betsy:BAAALgAECgQJBAAAAA==.',
Bi='Bigpopapump:BAACLgAFFH8OAAIMAAQJ8BhJBgBoAQRoDAAABgBhAGkMAAAEADoAawwAAAEAMgDqDAAAAwAwAAwABAnwGEkGAGgBBGgMAAAGAGEAaQwAAAQAOgBrDAAAAQAyAOoMAAADADAALgAECn8zAAIMAAgJRCbYAQD6AgAMAAgJRCbYAQD6AgAAAA==.Bishop:BAAALgADCgMJAwAAAA==.',
Bl='Blackgarden:BAAALgAECgUJBwAAAA==.Bloodydak:BAEALgAECgcJBwABLgAECgYJDwANAAAAAA==.',
Bo='Bombasharna:BAAALgADCgMJBQAAAA==.Bonkzx:BAAALgADCgMJAwAAAA==.Booze:BAAALgAECggJDgAAAA==.',
Br='Brigne:BAAALgADCgYJCwAAAA==.',
Bu='Buddeez:BAACLgAFFH8UAAILAAUJ8B3nGgCFAQVoDAAABgBjAGkMAAADAFEAawwAAAQAKQBqDAAAAgAuAOoMAAAFAFMACwAFCfAd5xoAhQEFaAwAAAYAYwBpDAAAAwBRAGsMAAAEACkAagwAAAIALgDqDAAABQBTAC4ABAp/KwACCwAJCT8lTQoAcQMACwAJCT8lTQoAcQMAAAA=.Built:BAABLgAECn8dAAQMAAgJ8CBYDAAJAghoDAAABQBfAGkMAAAFAF8AawwAAAUAWgBqDAAAAwA4AGwMAAADAFsAbQwAAAEATQDqDAAABQBZAG4MAAACADEADAAHCf8gWAwACQIHaAwAAAQAXwBpDAAABABfAGsMAAAFAFoAagwAAAMAOABsDAAAAwBbAOoMAAAEAFMAbgwAAAIAMQAOAAMJTBi+fwDoAANoDAAAAQATAG0MAAABAE0A6gwAAAEAWQAPAAEJ2hhogQBBAAFpDAAAAQA/AAAA.',
Ca='Cabbage:BAAALgADCgEJAQAAAA==.',
Ce='Cenwen:BAACLgAFFH8HAAILAAMJjQvUVADuAANoDAAAAwAiAGkMAAADACAA6gwAAAEAFgALAAMJjQvUVADuAANoDAAAAwAiAGkMAAADACAA6gwAAAEAFgAuAAQKfx8AAgsABwlzHMxfABwCAAsABwlzHMxfABwCAAAA.',
Ch='Chaos:BAABLgAECn8nAAIMAAkJAiBnAgDbAgloDAAABQBOAGkMAAAGAFEAawwAAAUAUQBqDAAABABRAGwMAAAFAFgAbQwAAAMAVQDqDAAABQBaAG4MAAAEAEMAbwwAAAIAUwAMAAkJAiBnAgDbAgloDAAABQBOAGkMAAAGAFEAawwAAAUAUQBqDAAABABRAGwMAAAFAFgAbQwAAAMAVQDqDAAABQBaAG4MAAAEAEMAbwwAAAIAUwAAAA==.Chonk:BAAALgADCgYJCQAAAA==.Chugginjizz:BAAALgAECgEJAQABLgAFFAYJGAAQALAVAA==.',
Cl='Clawreece:BAAALgAECgQJBgAAAA==.',
Co='Conta:BAAALgAECgMJAwAAAA==.',
Cr='Cryingtears:BAABLgAECn8jAAMRAAgJgw1wMwAVAQhoDAAABwA7AGkMAAAGAEAAawwAAAYAOwBqDAAABAARAGwMAAADAAgAbQwAAAEABADqDAAABQA2AG4MAAADAAgAEQAICYMNcDMAFQEIaAwAAAUAOwBpDAAABABAAGsMAAAEADsAagwAAAEAEQBsDAAAAQAIAG0MAAABAAQA6gwAAAMANgBuDAAAAgAIAAYABwmpBmODAP0AB2gMAAACABwAaQwAAAIAFABrDAAAAgARAGoMAAADABEAbAwAAAIADwDqDAAAAgAMAG4MAAABAAgAAAA=.',
Cu='Cuchicu:BAABLgAECn8vAAISAAkJPBpzDQCNAgloDAAACABcAGkMAAAIAFYAawwAAAcAVgBqDAAABQBAAGwMAAAFAEkAbQwAAAMAJQDqDAAABwBMAG4MAAACACgAbwwAAAIALQASAAkJPBpzDQCNAgloDAAACABcAGkMAAAIAFYAawwAAAcAVgBqDAAABQBAAGwMAAAFAEkAbQwAAAMAJQDqDAAABwBMAG4MAAACACgAbwwAAAIALQAAAA==.',
Da='Dakkonix:BAEALgAECgYJDwAAAA==.Dakkonixx:BAEALgAECgUJBQABLgAECgYJDwANAAAAAA==.Damagexx:BAAALgAECgEJAQAAAA==.Darkaged:BAAALgADCgYJBgAAAA==.Darklords:BAAALgADCgEJAQAAAA==.',
De='Demonasa:BAAALgADCgIJAgAAAA==.Desim:BAABLgAECn8WAAIQAAcJsx6EMwBoAgdoDAAABABcAGkMAAAEAFgAawwAAAQAVQBqDAAAAgBbAGwMAAACAEUA6gwAAAUAUwBuDAAAAQA0ABAABwmzHoQzAGgCB2gMAAAEAFwAaQwAAAQAWABrDAAABABVAGoMAAACAFsAbAwAAAIARQDqDAAABQBTAG4MAAABADQAAAA=.Dextt:BAABLgAECn8dAAITAAcJLCIrDgCpAgdoDAAABQBcAGkMAAAFAGMAawwAAAUAYgBqDAAABQBbAGwMAAADAFsAbQwAAAIAKgDqDAAABABhABMABwksIisOAKkCB2gMAAAFAFwAaQwAAAUAYwBrDAAABQBiAGoMAAAFAFsAbAwAAAMAWwBtDAAAAgAqAOoMAAAEAGEAAAA=.Dez:BAABLgAECn8XAAIRAAgJfRATIQCSAQhoDAAAAwArAGkMAAADACwAawwAAAMAHABqDAAABABEAGwMAAAEAC4AbQwAAAIAEQDqDAAAAwAsAG4MAAABACsAEQAICX0QEyEAkgEIaAwAAAMAKwBpDAAAAwAsAGsMAAADABwAagwAAAQARABsDAAABAAuAG0MAAACABEA6gwAAAMALABuDAAAAQArAAAA.',
Dk='Dkamp:BAAALgADCgQJDAAAAA==.',
Dm='Dmoney:BAAALgAECgYJBgAAAA==.',
Do='Dondiablo:BAAALgAECgYJDQAAAA==.Doylock:BAAALgAECgUJBQAAAA==.',
Dr='Dragnaballs:BAAALgAECgcJEgABLgAFFAgJIQALAGMWAA==.Drehd:BAACLgAFFH8KAAITAAMJvCTmFAA4AQNoDAAABQBfAGkMAAADAF8A6gwAAAIAWgATAAMJvCTmFAA4AQNoDAAABQBfAGkMAAADAF8A6gwAAAIAWgAuAAQKfy0AAhMACAnWJOkCADoDABMACAnWJOkCADoDAAAA.Drewcifer:BAABLgAECn8iAAIUAAkJhR6BFgDPAgloDAAABQBbAGkMAAAFAFcAawwAAAUAXQBqDAAABABeAGwMAAADAFIAbQwAAAMAQADqDAAABQBPAG4MAAADAEoAbwwAAAEAMwAUAAkJhR6BFgDPAgloDAAABQBbAGkMAAAFAFcAawwAAAUAXQBqDAAABABeAGwMAAADAFIAbQwAAAMAQADqDAAABQBPAG4MAAADAEoAbwwAAAEAMwABLgAECgkJIgAUAIUeAA==.Drewwar:BAAALgAECgEJAQABLgAECgkJIgAUAIUeAA==.Dripps:BAAALgAECgYJBgAAAA==.',
Du='Dumper:BAAALgADCgEJAQAAAA==.Dumps:BAAALgAECgMJAwAAAA==.',
['Dó']='Dóom:BAAALgAECgUJCQABLgAFFAEJAQANAAAAAA==.',
['Dü']='Düsk:BAAALgADCgUJBQABLgAECgEJAwANAAAAAA==.',
Eg='Egoon:BAAALgAECgQJBQAAAA==.',
El='Elmerfud:BAAALgAECgYJBwAAAA==.',
En='Enrèk:BAAALgADCgYJBgAAAA==.',
Fa='Falafel:BAACLgAFFH8NAAIQAAUJBR/qHwBtAQVoDAAAAwBVAGkMAAADAE0AawwAAAMAPwBqDAAAAQA2AOoMAAADAFoAEAAFCQUf6h8AbQEFaAwAAAMAVQBpDAAAAwBNAGsMAAADAD8AagwAAAEANgDqDAAAAwBaAC4ABAp/JQACEAAJCZwh7BIACgMAEAAJCZwh7BIACgMAAAA=.',
Fi='Fidely:BAAALgADCgEJAQAAAA==.',
Fo='Fomo:BAAALgADCgYJBgAAAA==.Fornax:BAAALgAECgQJBwABLgAECgcJFwALAA8MAA==.Fotmtrash:BAACLgAFFH8KAAMVAAQJfhhPEgDRAARoDAAABABBAGkMAAACAFUAawwAAAIAPgDqDAAAAgAlABUAAwm8FE8SANEAA2gMAAAEAEEAaQwAAAIAVQDqDAAAAQAIABYAAgl4EyogAK0AAmsMAAACAD4A6gwAAAEAJQAuAAQKfyYABBUACAlUIu8HAMwCABUACAkaIu8HAMwCABYABQmIHm8TAMEBABcAAgknCWFaAE4AAAAA.Foxxydots:BAABLgAECn8mAAIKAAgJSRYJMgCqAQhoDAAABgBNAGkMAAAGADoAawwAAAYAPgBqDAAABQA8AGwMAAAFAEcAbQwAAAMAKwDqDAAABgBBAG4MAAABABQACgAICUkWCTIAqgEIaAwAAAYATQBpDAAABgA6AGsMAAAGAD4AagwAAAUAPABsDAAABQBHAG0MAAADACsA6gwAAAYAQQBuDAAAAQAUAAAA.',
Fr='Frostitoot:BAABLgAECn8XAAILAAcJDwzrbABJAQdoDAAABAAnAGkMAAAEABwAawwAAAQAMABqDAAAAwAcAGwMAAADAB0A6gwAAAQAJABuDAAAAQADAAsABwkPDOtsAEkBB2gMAAAEACcAaQwAAAQAHABrDAAABAAwAGoMAAADABwAbAwAAAMAHQDqDAAABAAkAG4MAAABAAMAAAA=.',
Ga='Galbsadi:BAABLgAECn8cAAMYAAgJthJdCgA+AQhoDAAABQA6AGkMAAAFADwAawwAAAUAMwBqDAAABAArAGwMAAADACgAbQwAAAEAGgDqDAAABAA+AG4MAAABACQAGAAHCbUPXQoAPgEHaQwAAAEAGgBrDAAAAQAyAGoMAAADACsAbAwAAAEAKABtDAAAAQAaAOoMAAABAD4AbgwAAAEAJAAKAAYJDRDXZgAPAQZoDAAABQA6AGkMAAAEADwAawwAAAQAMwBqDAAAAQAXAGwMAAACABAA6gwAAAMAEgAAAA==.Garrius:BAAALgADCgQJBAAAAA==.',
Ge='Gelfdar:BAAALgAECgEJAQAAAA==.Gethendriel:BAAALgAECgQJCQAAAA==.',
Gl='Glaia:BAAALgADCgYJDQAAAA==.',
Go='Goel:BAAALgAECgEJAgAAAA==.',
Gr='Graf:BAABLgAECn8dAAQZAAgJ6h7cHABnAghoDAAABQBZAGkMAAAEAE4AawwAAAUASQBqDAAAAwBTAGwMAAAEAFIA6gwAAAUAUwBuDAAAAgBOAG8MAAABAEMAGQAHCZEf3BwAZwIHaAwAAAMAWQBpDAAAAgBOAGsMAAADAEgAagwAAAMAUwBsDAAAAwBSAOoMAAAEAFMAbgwAAAEATgABAAYJPRgFGwAZAQZoDAAAAQBNAGkMAAABADQAawwAAAEAEADqDAAAAQBRAG4MAAABAE0AbwwAAAEAQwAaAAQJQRM6LwDJAARoDAAAAQAyAGkMAAABACoAawwAAAEASQBsDAAAAQAeAAAA.Grimzorath:BAAALgAECgYJBgAAAA==.Grox:BAABLgAECn8UAAIZAAYJmg+qTgBsAQZoDAAABAA+AGkMAAAEAC4AawwAAAQAKgBqDAAAAwAlAGwMAAACABMA6gwAAAMAHAAZAAYJmg+qTgBsAQZoDAAABAA+AGkMAAAEAC4AawwAAAQAKgBqDAAAAwAlAGwMAAACABMA6gwAAAMAHAAAAA==.Grudge:BAAALgADCgMJBQAAAA==.',
Ha='Hackensack:BAAALgAECgcJDwAAAA==.Hamtaro:BAAALgAECgEJAQAAAA==.Hawthorne:BAABLgAECn8aAAIHAAcJ7x3cFAAgAgdoDAAABQBQAGkMAAAFAFsAawwAAAQAUQBqDAAAAwBWAGwMAAAEAFkAbQwAAAEAJgDqDAAABABDAAcABwnvHdwUACACB2gMAAAFAFAAaQwAAAUAWwBrDAAABABRAGoMAAADAFYAbAwAAAQAWQBtDAAAAQAmAOoMAAAEAEMAAAA=.',
Hi='Hiyabusa:BAAALgAECgYJEgAAAA==.',
Ho='Hollowboi:BAABLgAECn8pAAIIAAgJ2x58BwBrAghoDAAABwBZAGkMAAAHAFMAawwAAAcATgBqDAAABQBIAGwMAAAFAEgAbQwAAAIATgDqDAAABgBRAG4MAAACAEQACAAICdsefAcAawIIaAwAAAcAWQBpDAAABwBTAGsMAAAHAE4AagwAAAUASABsDAAABQBIAG0MAAACAE4A6gwAAAYAUQBuDAAAAgBEAAAA.Holygraf:BAAALgAECgcJDgAAAA==.',
Ia='Iamyama:BAAALgAECgUJCQAAAA==.',
Io='Ionna:BAAALgADCgcJBwAAAA==.',
Jd='Jdvance:BAAALgAECgYJBgAAAA==.',
Jh='Jhouska:BAAALgAECgcJEAAAAA==.',
Jo='Jormunngandr:BAACLgAFFH8YAAMQAAYJsBUeEgCdAQZoDAAABABTAGkMAAAFAEEAawwAAAQAQwBqDAAAAwA7AG0MAAABAAYA6gwAAAcANgAQAAUJsBUeEgCdAQVoDAAABABTAGkMAAAFAEEAawwAAAQAQwBtDAAAAQAGAOoMAAAHADYAGwABCQAAOBUARgABagwAAAMAOwAuAAQKfx8AAhAACQm9IK0RABIDABAACQm9IK0RABIDAAAA.',
Ju='Judgynomnom:BAACLgAFFH8GAAIRAAQJ8xYYEgAyAQRoDAAAAgBhAGkMAAACAFMAawwAAAEAGQDqDAAAAQAcABEABAnzFhgSADIBBGgMAAACAGEAaQwAAAIAUwBrDAAAAQAZAOoMAAABABwALgAECn8cAAIRAAgJaCbcCQDUAgARAAgJaCbcCQDUAgAAAA==.',
Jy='Jyggles:BAAALgAECgYJCgAAAA==.',
Ki='Kirax:BAAALgADCgEJAQAAAA==.',
Ko='Konataizumi:BAAALgADCgcJCwAAAA==.',
Kr='Kruhks:BAAALgAECgYJCAABLgAFFAMJCgATALwkAA==.',
Ks='Kshot:BAABLgAECn8vAAIMAAkJ8x6aAwCrAgloDAAABwBSAGkMAAAGAF4AawwAAAYATwBqDAAABgBQAGwMAAAGAFAAbQwAAAQASADqDAAABgBcAG4MAAAEAE8AbwwAAAIANAAMAAkJ8x6aAwCrAgloDAAABwBSAGkMAAAGAF4AawwAAAYATwBqDAAABgBQAGwMAAAGAFAAbQwAAAQASADqDAAABgBcAG4MAAAEAE8AbwwAAAIANAAAAA==.',
La='Lagdalen:BAABLgAECn8XAAIVAAYJjRudEwDVAQZoDAAABABfAGkMAAAFAEAAawwAAAUAXABqDAAAAQAZAOoMAAAHAEkAbgwAAAEARwAVAAYJjRudEwDVAQZoDAAABABfAGkMAAAFAEAAawwAAAUAXABqDAAAAQAZAOoMAAAHAEkAbgwAAAEARwAAAA==.Lanachan:BAABLgAECn8oAAIZAAgJOhHmGACxAQhoDAAABwAqAGkMAAAGAD8AawwAAAYANABqDAAABgBQAGwMAAAFADMAbQwAAAIAIgDqDAAABwAoAG4MAAABABcAGQAICToR5hgAsQEIaAwAAAcAKgBpDAAABgA/AGsMAAAGADQAagwAAAYAUABsDAAABQAzAG0MAAACACIA6gwAAAcAKABuDAAAAQAXAAAA.',
Ld='Ldn:BAABLgAECn8nAAILAAgJMRCLRgCnAQhoDAAABwA+AGkMAAAGADAAawwAAAYAJABqDAAABgAvAGwMAAAFAC8AbQwAAAIAGQDqDAAABgA1AG4MAAABABAACwAICTEQi0YApwEIaAwAAAcAPgBpDAAABgAwAGsMAAAGACQAagwAAAYALwBsDAAABQAvAG0MAAACABkA6gwAAAYANQBuDAAAAQAQAAAA.',
Le='Lep:BAAALgAECgUJBQAAAA==.',
Li='Likai:BAAALgADCgUJBQAAAA==.Lisa:BAAALgADCgcJAQAAAA==.Liz:BAABLgAECn8fAAIOAAgJUwaJTAA7AQhoDAAABQAQAGkMAAAFABcAawwAAAUADwBqDAAABQAWAGwMAAAFAA8AbQwAAAIAEwDqDAAAAwASAG4MAAABAAQADgAICVMGiUwAOwEIaAwAAAUAEABpDAAABQAXAGsMAAAFAA8AagwAAAUAFgBsDAAABQAPAG0MAAACABMA6gwAAAMAEgBuDAAAAQAEAAAA.',
Ly='Lylieth:BAABLgAECn8rAAIKAAkJ0BHjIAD7AQloDAAABgBJAGkMAAAFAC0AawwAAAYAMgBqDAAABQAmAGwMAAAFAC8AbQwAAAMAJwDqDAAABwA1AG4MAAAEACgAbwwAAAIADwAKAAkJ0BHjIAD7AQloDAAABgBJAGkMAAAFAC0AawwAAAYAMgBqDAAABQAmAGwMAAAFAC8AbQwAAAMAJwDqDAAABwA1AG4MAAAEACgAbwwAAAIADwAAAA==.Lyndyn:BAAALgADCgIJAgAAAA==.',
Ma='Mather:BAAALgAECgEJAgAAAA==.Mayzel:BAAALgAECgMJBAAAAA==.',
Mi='Microsqueeze:BAAALgADCgkJCQAAAA==.',
Mo='Mock:BAAALgAECgcJCAABLgAECgcJEAANAAAAAA==.Mogera:BAAALgADCgMJBQAAAA==.',
Ni='Ninluv:BAAALgAECgQJDgAAAA==.',
Ny='Nyancat:BAAALgADCgkJCwAAAA==.',
Ol='Olaho:BAAALgADCgYJBgAAAA==.',
Om='Omenz:BAAALgADCgIJAgAAAA==.',
Oo='Oojni:BAAALgADCgYJBgAAAA==.',
Pa='Pazzman:BAAALgADCgYJBwAAAA==.',
Pe='Perc:BAAALgAECgQJBAAAAA==.',
Ph='Pharhar:BAABLgAECn8iAAMRAAgJdhuVHAAxAghoDAAABgBcAGkMAAAGAGMAawwAAAYAYQBqDAAABABQAGwMAAAEAEAAbQwAAAIAJwDqDAAABABRAG4MAAACAAgAEQAICXYblRwAMQIIaAwAAAMAXABpDAAABQBjAGsMAAAGAGEAagwAAAQAUABsDAAABABAAG0MAAACACcA6gwAAAQAUQBuDAAAAQAIAAYAAwl9EQGkAMMAA2gMAAADAEAAaQwAAAEAKQBuDAAAAQAcAAAA.',
Po='Poppachàdson:BAABLgAECn8dAAIcAAcJ+CDTCABPAgdoDAAABABbAGkMAAAFAFwAawwAAAUAVwBqDAAABQBFAGwMAAACAEQA6gwAAAYAYQBuDAAAAgBFABwABwn4INMIAE8CB2gMAAAEAFsAaQwAAAUAXABrDAAABQBXAGoMAAAFAEUAbAwAAAIARADqDAAABgBhAG4MAAACAEUAAS4ABRQDCQYAHAAaFQA=.Poppadadson:BAACLgAFFH8GAAIcAAMJGhWPBQD8AANoDAAAAwAsAGkMAAABACUA6gwAAAIAUAAcAAMJGhWPBQD8AANoDAAAAwAsAGkMAAABACUA6gwAAAIAUAAuAAQKfxwAAhwABwmBH4kGAI0CABwABwmBH4kGAI0CAAAA.Poppadotson:BAAALgAECgMJAwABLgAFFAMJBgAcABoVAA==.',
Pu='Puscifer:BAAALgAECgkJBAAAAA==.',
Qu='Quarrior:BAAALgADCgEJAQABLgAECgEJAwANAAAAAA==.Quellazaire:BAAALgADCgcJDAAAAA==.Quincar:BAAALgADCgEJAQABLgAECgEJAwANAAAAAA==.',
Ra='Ravister:BAAALgAECgUJBQABLgAFFAUJFAAXAGgjAA==.',
Re='Relic:BAACLgAFFH8SAAMdAAUJyRUPAwBEAQVoDAAABQBHAGkMAAAEAEwAawwAAAMAIgBqDAAAAgAaAOoMAAAEACkAHQAECckVDwMARAEEaAwAAAUARwBpDAAABABMAGsMAAADACIA6gwAAAMAKQAbAAIJxQuXIwA4AAJqDAAAAgAaAOoMAAABAB4ALgAECn8dAAIdAAkJ4xyTAgCMAgAdAAkJ4xyTAgCMAgAAAA==.Renk:BAABLgAECn8iAAIQAAcJ1SUHEQCNAgdoDAAABwBhAGkMAAAHAGMAawwAAAYAYABqDAAABABjAGwMAAAEAF0AbQwAAAEAYADqDAAABQBhABAABwnVJQcRAI0CB2gMAAAHAGEAaQwAAAcAYwBrDAAABgBgAGoMAAAEAGMAbAwAAAQAXQBtDAAAAQBgAOoMAAAFAGEAAAA=.Renka:BAAALgADCggJCgAAAA==.',
Ro='Ronald:BAABLgAECn8UAAIGAAYJZRrhlgBPAQZoDAAAAgBIAGkMAAACAEsAawwAAAIATgBqDAAAAQAPAOoMAAAHAEMAbgwAAAYAKwAGAAYJZRrhlgBPAQZoDAAAAgBIAGkMAAACAEsAawwAAAIATgBqDAAAAQAPAOoMAAAHAEMAbgwAAAYAKwAAAA==.Roykevious:BAAALgAECgEJAwAAAA==.',
Sa='Saeyl:BAAALgAECgYJDAABLgAECgkJFwAWAJsJAA==.Sammie:BAEALgAECgUJBgABLgAECgYJDwANAAAAAA==.Savant:BAAALgADCgEJAQAAAA==.Sayl:BAABLgAECn8XAAMWAAkJmwlCLgAsAQloDAAAAwAjAGkMAAACABIAawwAAAIAGQBqDAAAAgAqAGwMAAADABEAbQwAAAIAJQDqDAAABQAQAG4MAAADAA0AbwwAAAEADQAWAAYJNQpCLgAsAQZoDAAAAwAjAGkMAAACABIAawwAAAIAGQBqDAAAAgAqAGwMAAACABEA6gwAAAQAEAAXAAUJMwjCNQDOAAVsDAAAAQATAG0MAAACABEA6gwAAAEAFQBuDAAAAwAeAG8MAAABAA8AAAA=.',
Sc='Scallywinkle:BAAALgAECgcJEAAAAA==.Scrap:BAABLgAECn8aAAMKAAkJ4hqLPgATAgloDAAABABSAGkMAAADAFUAawwAAAMARABqDAAAAwBBAGwMAAADAEIAbQwAAAIAQQDqDAAABABFAG4MAAADAEUAbwwAAAEAKwAKAAgJcBqLPgATAghoDAAABABSAGkMAAADAFUAawwAAAEAPQBsDAAAAQA/AG0MAAABAEEA6gwAAAQARQBuDAAAAwBFAG8MAAABACsAGAAECXkU4CsAEAEEawwAAAIARABqDAAAAwBBAGwMAAACAEIAbQwAAAEAFgAAAA==.',
Se='Senova:BAAALgAECgIJAgAAAA==.',
Sh='Shadowghoul:BAAALgAECgcJCAAAAA==.Shadowydern:BAABLgAECn8jAAMXAAgJySH8BACpAghoDAAABgBhAGkMAAAGAFUAawwAAAUAVABqDAAABABgAGwMAAAEAF4AbQwAAAIAWADqDAAABQBTAG4MAAADAEcAFwAICckh/AQAqQIIaAwAAAYAYQBpDAAABgBVAGsMAAAEAFQAagwAAAQAYABsDAAABABeAG0MAAACAFgA6gwAAAUAUwBuDAAAAwBHABUAAQn9EGl/ADMAAWsMAAABACsAAAA=.Shamewow:BAACLgAFFH8SAAITAAUJExkGDgBwAQVoDAAABQBLAGkMAAAEAEAAawwAAAIAPwBqDAAAAgAyAOoMAAAFAEIAEwAFCRMZBg4AcAEFaAwAAAUASwBpDAAABABAAGsMAAACAD8AagwAAAIAMgDqDAAABQBCAC4ABAp/KwACEwAJCWEaShkATAIAEwAJCWEaShkATAIAAAA=.',
Si='Sicknnasty:BAACLgAFFH8PAAIbAAUJjRLRBwARAQVoDAAABQBFAGkMAAAEADEAawwAAAIAHwBqDAAAAQBLAOoMAAADACcAGwAFCY0S0QcAEQEFaAwAAAUARQBpDAAABAAxAGsMAAACAB8AagwAAAEASwDqDAAAAwAnAC4ABAp/PgADGwAICXwicgUAbAIAGwAICXwicgUAbAIAEAAICcgU7i4A1QEAAAA=.',
Sl='Slayerz:BAAALgAECgYJBgAAAA==.',
Sn='Snattch:BAAALgADCgEJAQAAAA==.Snookismalls:BAAALgAECgcJEAAAAA==.',
So='Solarian:BAAALgADCgMJAwAAAA==.Solitary:BAAALgAECgcJEgAAAA==.',
Sp='Speed:BAAALgAECgYJCwAAAA==.Spinach:BAAALgAECgMJAQAAAA==.',
St='Starshopping:BAABLgAECn8UAAIUAAgJmiFlFQDWAghoDAAAAgBhAGkMAAADAFgAawwAAAMAWABqDAAAAwBaAGwMAAADAFoAbQwAAAIAUwDqDAAAAgBPAG4MAAACAEoAFAAICZohZRUA1gIIaAwAAAIAYQBpDAAAAwBYAGsMAAADAFgAagwAAAMAWgBsDAAAAwBaAG0MAAACAFMA6gwAAAIATwBuDAAAAgBKAAEuAAQKCQknAAwAAiAA.',
Su='Sunari:BAAALgADCgQJBAAAAA==.',
Ta='Taewryn:BAAALgAFFAQJBAABLgAFFAcJIAAIAOchAA==.Talrip:BAABLgAECn8dAAIeAAgJcx7YBgAgAghoDAAABQA4AGkMAAAFAFsAawwAAAUAUgBqDAAAAwAyAGwMAAADAFEAbQwAAAEAWgDqDAAABQA8AG4MAAACAFIAHgAICXMe2AYAIAIIaAwAAAUAOABpDAAABQBbAGsMAAAFAFIAagwAAAMAMgBsDAAAAwBRAG0MAAABAFoA6gwAAAUAPABuDAAAAgBSAAAA.',
Th='Thicctrix:BAAALgADCgcJDAAAAA==.Thundon:BAAALgADCgcJCQAAAA==.',
To='Toatem:BAAALgAECgUJBQAAAA==.Toro:BAACLgAFFH8WAAIZAAUJByJIBQCHAQVoDAAABgBhAGkMAAAFAGAAawwAAAQANwBqDAAAAgAsAOoMAAAFAGIAGQAFCQciSAUAhwEFaAwAAAYAYQBpDAAABQBgAGsMAAAEADcAagwAAAIALADqDAAABQBiAC4ABAp/KwACGQAJCXckZQUAUAMAGQAJCXckZQUAUAMAAAA=.',
Tr='Traitor:BAAALgADCgEJAQAAAA==.Trappynomnom:BAAALgAFFAIJAgAAAA==.Tree:BAACLgAFFH8MAAISAAQJAiRICgCuAQRoDAAABABiAGkMAAACAGMAawwAAAEASQDqDAAABQBiABIABAkCJEgKAK4BBGgMAAAEAGIAaQwAAAIAYwBrDAAAAQBJAOoMAAAFAGIALgAECn8VAAISAAYJmSNYHgBMAgASAAYJmSNYHgBMAgAAAA==.Treegrundler:BAAALgAECgYJEwAAAA==.Treeus:BAAALgAECgYJCQAAAA==.Trixulous:BAAALgADCgkJJQAAAA==.',
Tw='Twiigee:BAABLgAECn8XAAIIAAYJWSANIAABAgZoDAAABQBfAGkMAAAFAFMAawwAAAQAVABqDAAAAgAxAGwMAAACAEMA6gwAAAUAUwAIAAYJWSANIAABAgZoDAAABQBfAGkMAAAFAFMAawwAAAQAVABqDAAAAgAxAGwMAAACAEMA6gwAAAUAUwAAAA==.',
Tz='Tzungxie:BAABLgAECn8nAAIfAAkJWB2xAwCoAgloDAAABwBRAGkMAAAHAEEAawwAAAYASgBqDAAAAwA/AGwMAAAEAEkAbQwAAAIAUwDqDAAABgBTAG4MAAACAFoAbwwAAAIAMQAfAAkJWB2xAwCoAgloDAAABwBRAGkMAAAHAEEAawwAAAYASgBqDAAAAwA/AGwMAAAEAEkAbQwAAAIAUwDqDAAABgBTAG4MAAACAFoAbwwAAAIAMQAAAA==.',
Un='Unholylord:BAACLgAFFH8UAAIXAAUJaCNCBgCLAQVoDAAABwBTAGkMAAAFAGMAawwAAAMAWQBqDAAAAQAeAOoMAAAEAFkAFwAFCWgjQgYAiwEFaAwAAAcAUwBpDAAABQBjAGsMAAADAFkAagwAAAEAHgDqDAAABABZAC4ABAp/IAACFwAJCTYjygQARwMAFwAJCTYjygQARwMAAAA=.',
Va='Vae:BAAALgAECgMJAwAAAA==.Vagbadge:BAAALgAECgkJCQABLgAFFAUJFAAXAGgjAA==.Varroww:BAAALgAECgYJEQAAAA==.',
Vo='Vosxo:BAAALgAECgEJAQAAAA==.',
['Ví']='Vígo:BAABLgAECn8ZAAIBAAYJ7Qh0IADTAAZoDAAABgANAGkMAAAFACYAawwAAAUAGABqDAAAAwAaAGwMAAACAAkA6gwAAAQAGwABAAYJ7Qh0IADTAAZoDAAABgANAGkMAAAFACYAawwAAAUAGABqDAAAAwAaAGwMAAACAAkA6gwAAAQAGwAAAA==.',
Wa='Wado:BAAALgAECgEJAQAAAA==.',
We='Wellíngton:BAAALgAECgEJAQAAAA==.',
Wh='Whack:BAAALgADCgYJBgAAAA==.',
Wi='Wicke:BAAALgADCgQJBAABLgAECgEJAQANAAAAAA==.',
Wo='Wolfthetree:BAAALgAECgUJCAAAAA==.',
Wy='Wystarr:BAAALgADCgIJAgAAAA==.',
Xa='Xamael:BAAALgADCgMJAwAAAA==.',
Xe='Xerkz:BAAALgAECgEJAQAAAA==.',
Ys='Ystarian:BAABLgAECn88AAQCAAkJrRvCAQBuAgloDAAACgBVAGkMAAAIAFUAawwAAAgASQBqDAAABwBdAGwMAAAIAFQAbQwAAAQAPgDqDAAACgBNAG4MAAAEAD0AbwwAAAEAIwACAAkJrRvCAQBuAgloDAAABwBVAGkMAAAFAFUAawwAAAQASQBqDAAABQBdAGwMAAAHAFQAbQwAAAIAPgDqDAAABgBNAG4MAAACAD0AbwwAAAEAIwADAAgJBhQcHQDeAQhoDAAAAwAwAGkMAAADADgAawwAAAQANABqDAAAAgAyAGwMAAABADUAbQwAAAIAMgDqDAAAAwBIAG4MAAACABgABAABCRsB804AIAAB6gwAAAEAAgAAAA==.',
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
