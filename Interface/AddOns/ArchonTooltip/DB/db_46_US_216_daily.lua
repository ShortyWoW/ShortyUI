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

local lookup = {'Warrior-Arms','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Paladin-Protection','Paladin-Retribution','Monk-Mistweaver','Monk-Brewmaster','Warlock-Affliction','Warlock-Demonology','Mage-Frost','Hunter-Survival','Unknown-Unknown','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Unholy','Paladin-Holy','Druid-Restoration','Shaman-Restoration','DemonHunter-Devourer','Priest-Discipline','Priest-Holy','Priest-Shadow','Warlock-Destruction','Warrior-Fury','Warrior-Protection','Rogue-Subtlety','DeathKnight-Blood','Shaman-Enhancement','DeathKnight-Frost','DemonHunter-Vengeance',}
local provider = {region='US',realm='TheUnderbog',name='US',type='daily',zone=46,date='2026-05-16',data={Ac='Acinovanth:BAAALgAECgEJAQAAAA==.Acousticjeff:BAAALgAECgYJBgAAAA==.',
Ad='Adwill:BAABLgAECn8mAAIBAAgJ3B/tBQBYAghoDAAABwBYAGkMAAAGAFUAawwAAAYAVQBqDAAABgBVAGwMAAAEAFQAbQwAAAMARwDqDAAABQBSAG4MAAABAEgAAQAICdwf7QUAWAIIaAwAAAcAWABpDAAABgBVAGsMAAAGAFUAagwAAAYAVQBsDAAABABUAG0MAAADAEcA6gwAAAUAUgBuDAAAAQBIAAAA.',
Ae='Aelvoker:BAACLgAFFH8XAAQCAAYJvR0UDACdAQZoDAAABQBSAGkMAAAFAEAAawwAAAMAOQBqDAAAAwAzAGwMAAABAFEA6gwAAAYAXwACAAYJshcUDACdAQZoDAAAAwBSAGkMAAADAEAAawwAAAEAGwBqDAAAAgAzAGwMAAABAFEA6gwAAAEALwADAAQJPhUNBAAJAQRoDAAAAQA/AGkMAAABAAEAawwAAAIAOQDqDAAABABfAAQABAnuBoETAJAABGgMAAABACwAaQwAAAEADABqDAAAAQALAOoMAAABAAMALgAECn8XAAQDAAkJRR9RBwB3AgADAAYJJCNRBwB3AgAEAAcJnRGJGgC3AQACAAIJ3RrRSgCpAAAAAA==.',
Ai='Aindra:BAAALgAECggJEAAAAA==.Airen:BAAALgAECgQJBQAAAA==.',
An='Antidead:BAABLgAECn8gAAMFAAgJOR50BQCfAghoDAAABQBOAGkMAAAFAE8AawwAAAUARABqDAAABAA4AGwMAAAEAFIAbQwAAAIAUgDqDAAABQBSAG4MAAACAEMABQAICTkedAUAnwIIaAwAAAQATgBpDAAABABPAGsMAAAEAEQAagwAAAMAOABsDAAAAwBSAG0MAAABAFIA6gwAAAQAUgBuDAAAAQBDAAYACAnXE+JMAJkBCGgMAAABADoAaQwAAAEAKQBrDAAAAQA3AGoMAAABACoAbAwAAAEAMwBtDAAAAQAyAOoMAAABAC4AbgwAAAEANAAAAA==.',
Ap='Apachaler:BAABLgAECn8iAAMHAAcJAx6qEQAqAgdoDAAACABSAGkMAAAGAF0AawwAAAUAUgBqDAAABABPAGwMAAAEAEQAbQwAAAEANgDqDAAABgBMAAcABwkDHqoRACoCB2gMAAAHAFIAaQwAAAYAXQBrDAAABQBSAGoMAAAEAE8AbAwAAAQARABtDAAAAQA2AOoMAAAGAEwACAABCTYZnWoARAABaAwAAAEAQAAAAA==.',
Ar='Arathael:BAAALgADCgIJAgAAAA==.Ardyce:BAAALgADCgIJAgAAAA==.Arrae:BAAALgAECgUJAwAAAA==.Arreuws:BAAALgAECgQJBAAAAA==.',
As='Asiansmoliv:BAACLgAFFH8OAAMJAAMJwyCHAgAeAQNoDAAABgBWAGkMAAACAFIA6gwAAAYAUgAJAAMJwyCHAgAeAQNoDAAAAgBWAGkMAAACAFIA6gwAAAEAUgAKAAIJ9htlMgCuAAJoDAAABABVAOoMAAAFADkALgAECn8wAAMJAAkJ/CQcAABrAwAJAAkJ/CQcAABrAwAKAAUJuh9HOQC3AQAAAA==.',
Ba='Babymager:BAABLgAECn8dAAILAAYJSQ2fnwADAQZoDAAABwApAGkMAAAGACcAawwAAAUAIABqDAAAAwAqAGwMAAADABcA6gwAAAUAIQALAAYJSQ2fnwADAQZoDAAABwApAGkMAAAGACcAawwAAAUAIABqDAAAAwAqAGwMAAADABcA6gwAAAUAIQAAAA==.Babyshamz:BAAALgAECgYJBgAAAA==.',
Be='Beartwige:BAAALgADCgYJBgAAAA==.Belladonnà:BAAALgADCgQJBAAAAA==.Betsy:BAAALgAECgQJBAAAAA==.',
Bi='Bigpopapump:BAACLgAFFH8RAAIMAAQJThkhCABgAQRoDAAABwBhAGkMAAAFADoAawwAAAEAMgDqDAAABAA0AAwABAlOGSEIAGABBGgMAAAHAGEAaQwAAAUAOgBrDAAAAQAyAOoMAAAEADQALgAECn87AAIMAAgJtSacAQAXAwAMAAgJtSacAQAXAwAAAA==.Bishop:BAAALgADCgMJAwAAAA==.',
Bl='Blackgarden:BAAALgAECgUJBwAAAA==.Bloodydak:BAEALgAECgcJBwABLgAECgcJEAANAAAAAA==.',
Bo='Bombasharna:BAAALgADCgMJBQAAAA==.Bonkzx:BAAALgADCgMJAwAAAA==.Booze:BAAALgAECgkJDwAAAA==.',
Br='Brigne:BAAALgADCgYJCwAAAA==.',
Bu='Buddeez:BAACLgAFFH8YAAILAAUJBB5HEwB/AQVoDAAABwBjAGkMAAADAFEAawwAAAUAKgBqDAAAAwA5AOoMAAAGAFMACwAFCQQeRxMAfwEFaAwAAAcAYwBpDAAAAwBRAGsMAAAFACoAagwAAAMAOQDqDAAABgBTAC4ABAp/KwACCwAJCT8lTQoAcQMACwAJCT8lTQoAcQMAAAA=.Built:BAABLgAECn8eAAQMAAkJ9CBYDAAJAgloDAAABQBfAGkMAAAFAF8AawwAAAUAWgBqDAAAAwA4AGwMAAADAFsAbQwAAAEATQDqDAAABQBZAG4MAAACADEAbwwAAAEAVAAMAAgJASFYDAAJAghoDAAABABfAGkMAAAEAF8AawwAAAUAWgBqDAAAAwA4AGwMAAADAFsA6gwAAAQAUwBuDAAAAgAxAG8MAAABAFQADgADCUwYvn8A6AADaAwAAAEAEwBtDAAAAQBNAOoMAAABAFkADwABCdoYaIEAQQABaQwAAAEAPwAAAA==.',
Ca='Cabbage:BAAALgADCgEJAQAAAA==.Carrot:BAAALgAECgIJAgAAAA==.',
Ce='Cenwen:BAACLgAFFH8IAAILAAMJ4wygWgDvAANoDAAABAAsAGkMAAADACAA6gwAAAEAFgALAAMJ4wygWgDvAANoDAAABAAsAGkMAAADACAA6gwAAAEAFgAuAAQKfyUAAgsACAmVHMxfABwCAAsACAmVHMxfABwCAAAA.',
Ch='Chaos:BAABLgAECn8wAAIMAAkJ9yGDAgDxAgloDAAABgBgAGkMAAAHAFUAawwAAAYAWwBqDAAABQBXAGwMAAAGAFgAbQwAAAQAVQDqDAAABgBaAG4MAAAFAEcAbwwAAAMAVwAMAAkJ9yGDAgDxAgloDAAABgBgAGkMAAAHAFUAawwAAAYAWwBqDAAABQBXAGwMAAAGAFgAbQwAAAQAVQDqDAAABgBaAG4MAAAFAEcAbwwAAAMAVwAAAA==.Chonk:BAAALgADCgYJCQAAAA==.Chugginjizz:BAAALgAECgEJAQABLgAFFAcJHwAQAFEVAA==.',
Cl='Clawreece:BAAALgAECgQJBgAAAA==.',
Co='Conta:BAAALgAECgUJCAAAAA==.',
Cr='Cryingtears:BAABLgAECn8jAAMRAAgJgw0NOwAMAQhoDAAABwA7AGkMAAAGAEAAawwAAAYAOwBqDAAABAARAGwMAAADAAgAbQwAAAEABADqDAAABQA2AG4MAAADAAgAEQAICYMNDTsADAEIaAwAAAUAOwBpDAAABABAAGsMAAAEADsAagwAAAEAEQBsDAAAAQAIAG0MAAABAAQA6gwAAAMANgBuDAAAAgAIAAYABwmpBl6gAOwAB2gMAAACABwAaQwAAAIAFABrDAAAAgARAGoMAAADABEAbAwAAAIADwDqDAAAAgAMAG4MAAABAAgAAAA=.',
Cu='Cuchicu:BAABLgAECn87AAISAAkJ1hsECgDfAgloDAAACgBcAGkMAAAKAFsAawwAAAkAVgBqDAAABwBMAGwMAAAHAFIAbQwAAAMAJQDqDAAACQBXAG4MAAACACgAbwwAAAIALQASAAkJ1hsECgDfAgloDAAACgBcAGkMAAAKAFsAawwAAAkAVgBqDAAABwBMAGwMAAAHAFIAbQwAAAMAJQDqDAAACQBXAG4MAAACACgAbwwAAAIALQAAAA==.',
Da='Dakkonix:BAEALgAECgcJEAAAAA==.Dakkonixx:BAEALgAECgUJBQABLgAECgcJEAANAAAAAA==.Damagexx:BAAALgAECgEJAQAAAA==.Darkaged:BAAALgADCgYJBgAAAA==.Darklords:BAAALgADCgEJAQAAAA==.',
De='Demigodd:BAAALgADCgIJAgAAAA==.Demonasa:BAAALgADCgIJAgAAAA==.Desim:BAABLgAECn8WAAIQAAcJsx6EMwBoAgdoDAAABABcAGkMAAAEAFgAawwAAAQAVQBqDAAAAgBbAGwMAAACAEUA6gwAAAUAUwBuDAAAAQA0ABAABwmzHoQzAGgCB2gMAAAEAFwAaQwAAAQAWABrDAAABABVAGoMAAACAFsAbAwAAAIARQDqDAAABQBTAG4MAAABADQAAAA=.Dextt:BAABLgAECn8dAAITAAcJLCIrDgCpAgdoDAAABQBcAGkMAAAFAGMAawwAAAUAYgBqDAAABQBbAGwMAAADAFsAbQwAAAIAKgDqDAAABABhABMABwksIisOAKkCB2gMAAAFAFwAaQwAAAUAYwBrDAAABQBiAGoMAAAFAFsAbAwAAAMAWwBtDAAAAgAqAOoMAAAEAGEAAAA=.Dez:BAABLgAECn8dAAIRAAgJDhQlHQDPAQhoDAAABABKAGkMAAAEADMAawwAAAQAKgBqDAAABQBEAGwMAAAFAEUAbQwAAAIAEQDqDAAAAwAsAG4MAAACACsAEQAICQ4UJR0AzwEIaAwAAAQASgBpDAAABAAzAGsMAAAEACoAagwAAAUARABsDAAABQBFAG0MAAACABEA6gwAAAMALABuDAAAAgArAAAA.',
Dk='Dkamp:BAAALgADCgQJDAAAAA==.',
Dm='Dmoney:BAAALgAECgYJBgAAAA==.',
Do='Dondiablo:BAAALgAECgYJDQAAAA==.Doylock:BAAALgAECgUJBQAAAA==.',
Dr='Dragnaballs:BAAALgAECgcJEgABLgAFFAgJJAALANAWAA==.Drehd:BAACLgAFFH8KAAITAAMJvCSgGAA1AQNoDAAABQBfAGkMAAADAF8A6gwAAAIAWgATAAMJvCSgGAA1AQNoDAAABQBfAGkMAAADAF8A6gwAAAIAWgAuAAQKfy0AAhMACAnWJEEEAC4DABMACAnWJEEEAC4DAAAA.Drewcifer:BAABLgAECn8kAAIUAAkJfR+BFgDPAgloDAAABQBbAGkMAAAFAFcAawwAAAUAXQBqDAAABABeAGwMAAADAFIAbQwAAAMAQADqDAAABQBPAG4MAAAEAEoAbwwAAAIARgAUAAkJfR+BFgDPAgloDAAABQBbAGkMAAAFAFcAawwAAAUAXQBqDAAABABeAGwMAAADAFIAbQwAAAMAQADqDAAABQBPAG4MAAAEAEoAbwwAAAIARgABLgAECgkJJAAUAH0fAA==.Drewwar:BAAALgAECgEJAQABLgAECgkJJAAUAH0fAA==.Dripps:BAAALgAECgYJBgAAAA==.',
Du='Dumper:BAAALgADCgEJAQAAAA==.Dumps:BAAALgAECgMJAwAAAA==.',
['Dó']='Dóom:BAAALgAECgUJCQABLgAFFAMJAwANAAAAAA==.',
['Dü']='Düsk:BAAALgADCgUJBQABLgAECgEJBAANAAAAAA==.',
Eg='Egoon:BAAALgAECgQJBgAAAA==.',
El='Elmerfud:BAAALgAECgYJBwAAAA==.',
En='Enrèk:BAAALgADCgYJBgAAAA==.',
Fa='Falafel:BAACLgAFFH8SAAIQAAUJkx8TKgAHAQVoDAAABABVAGkMAAAEAFMAawwAAAQAPwBqDAAAAgA/AOoMAAAEAFoAEAAFCZMfEyoABwEFaAwAAAQAVQBpDAAABABTAGsMAAAEAD8AagwAAAIAPwDqDAAABABaAC4ABAp/KAACEAAJCU0i7BIACgMAEAAJCU0i7BIACgMAAAA=.',
Fi='Fidely:BAAALgADCgEJAQAAAA==.',
Fo='Fomo:BAAALgADCgYJBgAAAA==.Fornax:BAAALgAECgQJBwABLgAECgcJFwALAA8MAA==.Fotmtrash:BAACLgAFFH8NAAMVAAQJVhoCFQA9AQRoDAAABQBBAGkMAAADAFUAawwAAAIAPgDqDAAAAwA4ABUABAmTFgIVAD0BBGgMAAABADIAaQwAAAEAPgBrDAAAAgA+AOoMAAACADgAFgADCbwUtBQAyAADaAwAAAQAQQBpDAAAAgBVAOoMAAABAAgALgAECn8uAAQWAAgJ1yPvBwDMAgAVAAgJNSABBgDcAgAWAAgJGiLvBwDMAgAXAAIJJwlhWgBOAAAAAA==.Foxxydots:BAABLgAECn8mAAIKAAgJSRY1SgDrAQhoDAAABgBNAGkMAAAGADoAawwAAAYAPgBqDAAABQA8AGwMAAAFAEcAbQwAAAMAKwDqDAAABgBBAG4MAAABABQACgAICUkWNUoA6wEIaAwAAAYATQBpDAAABgA6AGsMAAAGAD4AagwAAAUAPABsDAAABQBHAG0MAAADACsA6gwAAAYAQQBuDAAAAQAUAAAA.',
Fr='Frostitoot:BAABLgAECn8XAAILAAcJDwzMhQAyAQdoDAAABAAnAGkMAAAEABwAawwAAAQAMABqDAAAAwAcAGwMAAADAB0A6gwAAAQAJABuDAAAAQADAAsABwkPDMyFADIBB2gMAAAEACcAaQwAAAQAHABrDAAABAAwAGoMAAADABwAbAwAAAMAHQDqDAAABAAkAG4MAAABAAMAAAA=.',
Ga='Galbsadi:BAABLgAECn8iAAMYAAgJthLZDAAkAQhoDAAABgA6AGkMAAAGADwAawwAAAYAMwBqDAAABQArAGwMAAAEACgAbQwAAAEAGgDqDAAABQA+AG4MAAABACQAGAAHCbUP2QwAJAEHaQwAAAEAGgBrDAAAAQAyAGoMAAADACsAbAwAAAEAKABtDAAAAQAaAOoMAAABAD4AbgwAAAEAJAAKAAYJDRDwfwD+AAZoDAAABgA6AGkMAAAFADwAawwAAAUAMwBqDAAAAgAXAGwMAAADABAA6gwAAAQAEgAAAA==.Garrius:BAAALgADCgQJBAAAAA==.',
Ge='Gelfdar:BAAALgAECgEJAQAAAA==.Gethendriel:BAAALgAECgQJCQAAAA==.',
Gl='Glaia:BAAALgADCgYJDQAAAA==.',
Go='Goel:BAAALgAECgEJAgAAAA==.',
Gr='Graf:BAABLgAECn8jAAQZAAkJRCDcHABnAgloDAAABgBZAGkMAAAFAFcAawwAAAYATwBqDAAABABVAGwMAAAFAF8AbQwAAAEAUADqDAAABQBTAG4MAAACAE4AbwwAAAEAQwAZAAcJlyDcHABnAgdoDAAABABZAGkMAAADAFcAawwAAAQATwBqDAAAAwBTAGwMAAADAFIA6gwAAAQAUwBuDAAAAQBOAAEABgk9GAUbABkBBmgMAAABAE0AaQwAAAEANABrDAAAAQAQAOoMAAABAFEAbgwAAAEATQBvDAAAAQBDABoABgmyGnQkAMQABmgMAAABADIAaQwAAAEAKgBrDAAAAQBJAGoMAAABAFUAbAwAAAIAXwBtDAAAAQBQAAAA.Graflock:BAAALgAECgEJAQAAAA==.Grimzorath:BAAALgAECgYJBgAAAA==.Grox:BAABLgAECn8UAAIZAAYJmg+qTgBsAQZoDAAABAA+AGkMAAAEAC4AawwAAAQAKgBqDAAAAwAlAGwMAAACABMA6gwAAAMAHAAZAAYJmg+qTgBsAQZoDAAABAA+AGkMAAAEAC4AawwAAAQAKgBqDAAAAwAlAGwMAAACABMA6gwAAAMAHAAAAA==.Grudge:BAAALgADCgMJBQAAAA==.',
Ha='Hackensack:BAAALgAECggJEAAAAA==.Hamtaro:BAAALgAECgEJAQAAAA==.Hawthorne:BAABLgAECn8aAAIHAAcJ7x3cFAAgAgdoDAAABQBQAGkMAAAFAFsAawwAAAQAUQBqDAAAAwBWAGwMAAAEAFkAbQwAAAEAJgDqDAAABABDAAcABwnvHdwUACACB2gMAAAFAFAAaQwAAAUAWwBrDAAABABRAGoMAAADAFYAbAwAAAQAWQBtDAAAAQAmAOoMAAAEAEMAAAA=.',
Hi='Hiyabusa:BAABLgAECn8UAAIbAAcJ4BBDLQCWAQdoDAAABABLAGkMAAAEADgAawwAAAMAIQBqDAAAAwAiAGwMAAADAEQA6gwAAAIAEgBuDAAAAQAGABsABwngEEMtAJYBB2gMAAAEAEsAaQwAAAQAOABrDAAAAwAhAGoMAAADACIAbAwAAAMARADqDAAAAgASAG4MAAABAAYAAAA=.',
Ho='Hollowboi:BAABLgAECn8xAAIIAAgJhR+OCQBkAghoDAAACABZAGkMAAAIAFUAawwAAAgATwBqDAAABgBIAGwMAAAGAFAAbQwAAAMATgDqDAAABwBRAG4MAAADAEQACAAICYUfjgkAZAIIaAwAAAgAWQBpDAAACABVAGsMAAAIAE8AagwAAAYASABsDAAABgBQAG0MAAADAE4A6gwAAAcAUQBuDAAAAwBEAAAA.Holygraf:BAAALgAECgcJDgAAAA==.',
Ia='Iamyama:BAAALgAECgUJCQAAAA==.',
Il='Illgaz:BAAALgADCgEJAQAAAA==.',
Io='Ionna:BAAALgADCgcJBwAAAA==.',
Jd='Jdvance:BAAALgAECgYJBgAAAA==.',
Jh='Jhouska:BAAALgAECgcJEAAAAA==.',
Jo='Jormunngandr:BAACLgAFFH8fAAMQAAcJURWmBwCsAQdoDAAABQBTAGkMAAAGAE4AawwAAAUAQwBqDAAABAA7AG0MAAACABMA6gwAAAgANgBuDAAAAQAXABAABglRFaYHAKwBBmgMAAAFAFMAaQwAAAYATgBrDAAABQBDAG0MAAACABMA6gwAAAgANgBuDAAAAQAXABwAAQkAADgVAEYAAWoMAAAEADsALgAECn8fAAIQAAkJvSCtEQASAwAQAAkJvSCtEQASAwAAAA==.',
Ju='Judgynomnom:BAACLgAFFH8GAAIRAAQJ8xZyFQAsAQRoDAAAAgBhAGkMAAACAFMAawwAAAEAGQDqDAAAAQAcABEABAnzFnIVACwBBGgMAAACAGEAaQwAAAIAUwBrDAAAAQAZAOoMAAABABwALgAECn8cAAIRAAgJaCbcCQDUAgARAAgJaCbcCQDUAgAAAA==.',
Jy='Jyggles:BAAALgAECgYJCgAAAA==.',
Ke='Keyaesh:BAAALgADCgYJBwAAAA==.',
Ki='Kirax:BAAALgADCgEJAQAAAA==.',
Ko='Konataizumi:BAAALgADCgcJCwAAAA==.',
Kr='Kruhks:BAAALgAECgYJCAABLgAFFAMJCgATALwkAA==.',
Ks='Kshot:BAABLgAECn81AAIMAAkJmR8/BAC4AgloDAAACABZAGkMAAAHAF4AawwAAAcATwBqDAAABwBQAGwMAAAHAFYAbQwAAAQASADqDAAABwBcAG4MAAAEAE8AbwwAAAIANAAMAAkJmR8/BAC4AgloDAAACABZAGkMAAAHAF4AawwAAAcATwBqDAAABwBQAGwMAAAHAFYAbQwAAAQASADqDAAABwBcAG4MAAAEAE8AbwwAAAIANAAAAA==.',
La='Lagdalen:BAABLgAECn8XAAIWAAYJhBtYFgDWAQZoDAAABABfAGkMAAAFAEAAawwAAAUAXABqDAAAAQAZAOoMAAAHAEkAbgwAAAEARwAWAAYJhBtYFgDWAQZoDAAABABfAGkMAAAFAEAAawwAAAUAXABqDAAAAQAZAOoMAAAHAEkAbgwAAAEARwAAAA==.Lanachan:BAABLgAECn8oAAIZAAgJOhFLIwCMAQhoDAAABwAqAGkMAAAGAD8AawwAAAYANABqDAAABgBQAGwMAAAFADMAbQwAAAIAIgDqDAAABwAoAG4MAAABABcAGQAICToRSyMAjAEIaAwAAAcAKgBpDAAABgA/AGsMAAAGADQAagwAAAYAUABsDAAABQAzAG0MAAACACIA6gwAAAcAKABuDAAAAQAXAAAA.',
Ld='Ldn:BAABLgAECn8wAAILAAkJzA/RPwDdAQloDAAACABDAGkMAAAHADAAawwAAAcAJABqDAAABwAvAGwMAAAGAC8AbQwAAAMAGQDqDAAABwA1AG4MAAACACAAbwwAAAEADAALAAkJzA/RPwDdAQloDAAACABDAGkMAAAHADAAawwAAAcAJABqDAAABwAvAGwMAAAGAC8AbQwAAAMAGQDqDAAABwA1AG4MAAACACAAbwwAAAEADAAAAA==.',
Le='Lep:BAAALgAECgUJBQAAAA==.',
Li='Likai:BAAALgADCgUJBQAAAA==.Lisa:BAAALgADCgcJAQAAAA==.Liz:BAABLgAECn8mAAIOAAgJqAkeTQBiAQhoDAAABgAUAGkMAAAGADAAawwAAAYAHABqDAAABgAWAGwMAAAGABcAbQwAAAMAFwDqDAAAAwASAG4MAAACAAkADgAICagJHk0AYgEIaAwAAAYAFABpDAAABgAwAGsMAAAGABwAagwAAAYAFgBsDAAABgAXAG0MAAADABcA6gwAAAMAEgBuDAAAAgAJAAAA.',
Ly='Lylieth:BAABLgAECn8yAAIKAAkJlhJgLQDnAQloDAAABwBJAGkMAAAGAC0AawwAAAcAMgBqDAAABgBAAGwMAAAGADsAbQwAAAQAJwDqDAAABwA1AG4MAAAFACwAbwwAAAIADwAKAAkJlhJgLQDnAQloDAAABwBJAGkMAAAGAC0AawwAAAcAMgBqDAAABgBAAGwMAAAGADsAbQwAAAQAJwDqDAAABwA1AG4MAAAFACwAbwwAAAIADwAAAA==.Lyndyn:BAAALgADCgIJAgAAAA==.',
Ma='Mather:BAAALgAECgEJAgAAAA==.Mayzel:BAAALgAECgMJBAAAAA==.',
Mi='Microsqueeze:BAAALgADCgkJCQAAAA==.',
Mo='Mock:BAAALgAECgcJDgABLgAECgcJEAANAAAAAA==.Mogera:BAAALgADCgMJBQAAAA==.',
Ni='Ninluv:BAAALgAECgQJDgAAAA==.',
Ny='Nyancat:BAAALgADCgkJCwAAAA==.',
Ol='Olaho:BAAALgADCgYJBgAAAA==.',
Om='Omenz:BAAALgADCgIJAgAAAA==.',
Oo='Oojni:BAAALgADCgYJBgAAAA==.',
Pa='Pazzman:BAAALgADCgYJBwAAAA==.',
Pe='Perc:BAAALgAECgQJBAAAAA==.',
Ph='Pharhar:BAABLgAECn8qAAMRAAgJTCCKEwArAghoDAAABwBcAGkMAAAHAGMAawwAAAcAYQBqDAAABQBQAGwMAAAFAEAAbQwAAAMANQDqDAAABQBRAG4MAAADAFsAEQAICUwgihMAKwIIaAwAAAMAXABpDAAABQBjAGsMAAAHAGEAagwAAAUAUABsDAAABQBAAG0MAAADADUA6gwAAAUAUQBuDAAAAgBbAAYAAwmKFEu+ALwAA2gMAAAEAEAAaQwAAAIAQABuDAAAAQAcAAAA.',
Po='Poppachàdson:BAABLgAECn8dAAIdAAcJ+CDTCABPAgdoDAAABABbAGkMAAAFAFwAawwAAAUAVwBqDAAABQBFAGwMAAACAEQA6gwAAAYAYQBuDAAAAgBFAB0ABwn4INMIAE8CB2gMAAAEAFsAaQwAAAUAXABrDAAABQBXAGoMAAAFAEUAbAwAAAIARADqDAAABgBhAG4MAAACAEUAAS4ABRQDCQYAHQAaFQA=.Poppadadson:BAACLgAFFH8GAAIdAAMJGhW+BgDoAANoDAAAAwAsAGkMAAABACUA6gwAAAIAUAAdAAMJGhW+BgDoAANoDAAAAwAsAGkMAAABACUA6gwAAAIAUAAuAAQKfxwAAh0ABwmBH4kGAI0CAB0ABwmBH4kGAI0CAAAA.Poppadotson:BAAALgAECgMJAwABLgAFFAMJBgAdABoVAA==.',
Pu='Puscifer:BAAALgAECgkJCAAAAA==.',
Qu='Quarrior:BAAALgADCgEJAQABLgAECgEJBAANAAAAAA==.Quellazaire:BAAALgADCgcJDAAAAA==.Quincar:BAAALgADCgEJAQABLgAECgEJBAANAAAAAA==.',
Ra='Ravister:BAAALgAECgUJBQABLgAFFAUJFAAXAGgjAA==.',
Re='Relic:BAACLgAFFH8WAAMeAAUJRxavBAA5AQVoDAAABgBIAGkMAAAEAEwAawwAAAQAJgBqDAAAAwAmAOoMAAAFACkAHgAECUcWrwQAOQEEaAwAAAYASABpDAAABABMAGsMAAAEACYA6gwAAAQAKQAcAAIJxQtzJwA3AAJqDAAAAwAmAOoMAAABAB4ALgAECn8fAAIeAAkJhB2TAgCMAgAeAAkJhB2TAgCMAgAAAA==.Renk:BAABLgAECn8oAAIQAAgJ1iQkDgDAAghoDAAACABhAGkMAAAIAGMAawwAAAcAYABqDAAABQBjAGwMAAAEAF0AbQwAAAEAYADqDAAABgBhAG4MAAABAE8AEAAICdYkJA4AwAIIaAwAAAgAYQBpDAAACABjAGsMAAAHAGAAagwAAAUAYwBsDAAABABdAG0MAAABAGAA6gwAAAYAYQBuDAAAAQBPAAAA.Renka:BAAALgAECgQJBAAAAA==.',
Ro='Ronald:BAABLgAECn8UAAIGAAYJZRrhlgBPAQZoDAAAAgBIAGkMAAACAEsAawwAAAIATgBqDAAAAQAPAOoMAAAHAEMAbgwAAAYAKwAGAAYJZRrhlgBPAQZoDAAAAgBIAGkMAAACAEsAawwAAAIATgBqDAAAAQAPAOoMAAAHAEMAbgwAAAYAKwAAAA==.Roykevious:BAAALgAECgEJAwAAAA==.',
Sa='Saeyl:BAAALgAECgYJDAABLgAECgkJFwAVAJsJAA==.Sammie:BAEALgAECgUJBgABLgAECgcJEAANAAAAAA==.Savant:BAAALgAECgMJAwAAAA==.Sayl:BAABLgAECn8XAAMVAAkJmwlCLgAsAQloDAAAAwAjAGkMAAACABIAawwAAAIAGQBqDAAAAgAqAGwMAAADABEAbQwAAAIAJQDqDAAABQAQAG4MAAADAA0AbwwAAAEADQAVAAYJNQpCLgAsAQZoDAAAAwAjAGkMAAACABIAawwAAAIAGQBqDAAAAgAqAGwMAAACABEA6gwAAAQAEAAXAAUJMwg/QQC0AAVsDAAAAQATAG0MAAACABEA6gwAAAEAFQBuDAAAAwAeAG8MAAABAA8AAAA=.',
Sc='Scallywinkle:BAAALgAECgcJEAAAAA==.Scrap:BAABLgAECn8aAAMKAAkJ4hqLPgATAgloDAAABABSAGkMAAADAFUAawwAAAMARABqDAAAAwBBAGwMAAADAEIAbQwAAAIAQQDqDAAABABFAG4MAAADAEUAbwwAAAEAKwAKAAgJcBqLPgATAghoDAAABABSAGkMAAADAFUAawwAAAEAPQBsDAAAAQA/AG0MAAABAEEA6gwAAAQARQBuDAAAAwBFAG8MAAABACsAGAAECXkU4CsAEAEEawwAAAIARABqDAAAAwBBAGwMAAACAEIAbQwAAAEAFgAAAA==.',
Se='Senova:BAAALgAECgIJAgAAAA==.',
Sh='Shadowghoul:BAAALgAECggJEAAAAA==.Shadowydern:BAABLgAECn8mAAMXAAkJZB92BQDIAgloDAAABgBhAGkMAAAGAFUAawwAAAUAVABqDAAABABgAGwMAAAEAF4AbQwAAAIAWADqDAAABgBTAG4MAAAEAEcAbwwAAAEAJQAXAAkJZB92BQDIAgloDAAABgBhAGkMAAAGAFUAawwAAAQAVABqDAAABABgAGwMAAAEAF4AbQwAAAIAWADqDAAABgBTAG4MAAAEAEcAbwwAAAEAJQAWAAEJ/RBpfwAzAAFrDAAAAQArAAAA.Shamewow:BAACLgAFFH8WAAITAAUJfBkmBwBTAQVoDAAABgBLAGkMAAAFAEAAawwAAAIAPwBqDAAAAwA4AOoMAAAGAEIAEwAFCXwZJgcAUwEFaAwAAAYASwBpDAAABQBAAGsMAAACAD8AagwAAAMAOADqDAAABgBCAC4ABAp/KwACEwAJCWEaShkATAIAEwAJCWEaShkATAIAAAA=.Shrimpboat:BAAALgAECgYJBQAAAA==.',
Si='Sicknnasty:BAACLgAFFH8UAAIcAAUJJxS6EAAIAQVoDAAABgBFAGkMAAAFAEEAawwAAAMAHwBqDAAAAgBLAOoMAAAEACcAHAAFCScUuhAACAEFaAwAAAYARQBpDAAABQBBAGsMAAADAB8AagwAAAIASwDqDAAABAAnAC4ABAp/QQADHAAICXwiTggACQIAHAAICXwiTggACQIAEAAICcgU0EUAqwEAAAA=.',
Sl='Slayerz:BAAALgAECgYJBgAAAA==.',
Sn='Snattch:BAAALgADCgEJAQAAAA==.Snookismalls:BAAALgAECgcJEAAAAA==.',
So='Solarian:BAAALgADCgMJAwAAAA==.Solitary:BAAALgAECgcJEwAAAA==.',
Sp='Speed:BAAALgAECgYJCwAAAA==.Spinach:BAAALgAECgMJAQABLgAECgYJBQANAAAAAA==.',
St='Starshopping:BAABLgAECn8UAAIUAAgJmiFlFQDWAghoDAAAAgBhAGkMAAADAFgAawwAAAMAWABqDAAAAwBaAGwMAAADAFoAbQwAAAIAUwDqDAAAAgBPAG4MAAACAEoAFAAICZohZRUA1gIIaAwAAAIAYQBpDAAAAwBYAGsMAAADAFgAagwAAAMAWgBsDAAAAwBaAG0MAAACAFMA6gwAAAIATwBuDAAAAgBKAAEuAAQKCQkwAAwA9yEA.',
Su='Sunari:BAAALgADCgQJBAAAAA==.',
Ta='Taewryn:BAAALgAFFAQJBAABLgAFFAgJKAAIABYiAA==.Talrip:BAABLgAECn8eAAIfAAkJVR3YBgAgAgloDAAABQA4AGkMAAAFAFsAawwAAAUAUgBqDAAAAwAyAGwMAAADAFEAbQwAAAEAWgDqDAAABQA8AG4MAAACAFIAbwwAAAEANwAfAAkJVR3YBgAgAgloDAAABQA4AGkMAAAFAFsAawwAAAUAUgBqDAAAAwAyAGwMAAADAFEAbQwAAAEAWgDqDAAABQA8AG4MAAACAFIAbwwAAAEANwAAAA==.',
Th='Thicctrix:BAAALgADCgcJDAAAAA==.Thundon:BAAALgADCgcJCQAAAA==.',
To='Toatem:BAAALgAECgUJBQAAAA==.Toro:BAACLgAFFH8bAAIZAAUJByImCAB4AQVoDAAABwBhAGkMAAAGAGAAawwAAAUANwBqDAAAAwAsAOoMAAAGAGIAGQAFCQciJggAeAEFaAwAAAcAYQBpDAAABgBgAGsMAAAFADcAagwAAAMALADqDAAABgBiAC4ABAp/KwACGQAJCXckZQUAUAMAGQAJCXckZQUAUAMAAAA=.',
Tr='Traitor:BAAALgADCgEJAQAAAA==.Trappynomnom:BAAALgAFFAIJAgAAAA==.Tree:BAACLgAFFH8PAAISAAQJBiREDACtAQRoDAAABQBiAGkMAAADAGMAawwAAAEASQDqDAAABgBiABIABAkGJEQMAK0BBGgMAAAFAGIAaQwAAAMAYwBrDAAAAQBJAOoMAAAGAGIALgAECn8WAAISAAYJmSNYHgBMAgASAAYJmSNYHgBMAgAAAA==.Treegrundler:BAAALgAECgYJEwAAAA==.Treeus:BAAALgAECgYJCQAAAA==.Trixulous:BAAALgADCgkJJQAAAA==.',
Tw='Twiigee:BAABLgAECn8XAAIIAAYJWSANIAABAgZoDAAABQBfAGkMAAAFAFMAawwAAAQAVABqDAAAAgAxAGwMAAACAEMA6gwAAAUAUwAIAAYJWSANIAABAgZoDAAABQBfAGkMAAAFAFMAawwAAAQAVABqDAAAAgAxAGwMAAACAEMA6gwAAAUAUwAAAA==.',
Tz='Tzungxie:BAABLgAECn8pAAIbAAkJWB2pBwBmAgloDAAABwBRAGkMAAAHAEEAawwAAAYASgBqDAAAAwA/AGwMAAAFAEkAbQwAAAIAUwDqDAAABwBTAG4MAAACAFoAbwwAAAIAMQAbAAkJWB2pBwBmAgloDAAABwBRAGkMAAAHAEEAawwAAAYASgBqDAAAAwA/AGwMAAAFAEkAbQwAAAIAUwDqDAAABwBTAG4MAAACAFoAbwwAAAIAMQAAAA==.',
Un='Unholylord:BAACLgAFFH8UAAIXAAUJaCPtBwCBAQVoDAAABwBTAGkMAAAFAGMAawwAAAMAWQBqDAAAAQAeAOoMAAAEAFkAFwAFCWgj7QcAgQEFaAwAAAcAUwBpDAAABQBjAGsMAAADAFkAagwAAAEAHgDqDAAABABZAC4ABAp/IgACFwAJCaojygQARwMAFwAJCaojygQARwMAAAA=.',
Va='Vae:BAAALgAECgMJAwAAAA==.Vagbadge:BAAALgAECgkJCQABLgAFFAUJFAAXAGgjAA==.Varroww:BAAALgAECgYJEQAAAA==.',
Vo='Vosxo:BAAALgAECgEJAQAAAA==.',
['Ví']='Vígo:BAABLgAECn8gAAIBAAcJpQizJQDeAAdoDAAABwANAGkMAAAGACYAawwAAAYAGABqDAAABAAaAGwMAAADAAkAbQwAAAEAEgDqDAAABQAbAAEABwmlCLMlAN4AB2gMAAAHAA0AaQwAAAYAJgBrDAAABgAYAGoMAAAEABoAbAwAAAMACQBtDAAAAQASAOoMAAAFABsAAAA=.',
Wa='Wado:BAAALgAECgEJAQAAAA==.',
We='Wellíngton:BAAALgAECgEJAQAAAA==.',
Wh='Whack:BAAALgADCgYJBgAAAA==.',
Wi='Wicke:BAAALgADCgQJBAABLgAECgEJAQANAAAAAA==.',
Wo='Wolfthetree:BAAALgAECgUJCAAAAA==.',
Wy='Wystarr:BAAALgADCgIJAgAAAA==.',
Xa='Xamael:BAAALgADCgMJAwAAAA==.',
Xe='Xerkz:BAAALgAECgEJAQAAAA==.',
Ys='Ystarian:BAABLgAECn89AAQDAAkJrRujAgBRAgloDAAACgBVAGkMAAAIAFUAawwAAAgASQBqDAAABwBdAGwMAAAIAFQAbQwAAAQAPgDqDAAACwBNAG4MAAAEAD0AbwwAAAEAIwADAAkJrRujAgBRAgloDAAABwBVAGkMAAAFAFUAawwAAAQASQBqDAAABQBdAGwMAAAHAFQAbQwAAAIAPgDqDAAABwBNAG4MAAACAD0AbwwAAAEAIwACAAgJBhQcHQDeAQhoDAAAAwAwAGkMAAADADgAawwAAAQANABqDAAAAgAyAGwMAAABADUAbQwAAAIAMgDqDAAAAwBIAG4MAAACABgABAABCRsB804AIAAB6gwAAAEAAgAAAA==.',
Za='Zaptik:BAAALgAECgEJAQAAAA==.',
['Ël']='Ëlëmëntary:BAAALgAECgcJBgAAAA==.',
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
