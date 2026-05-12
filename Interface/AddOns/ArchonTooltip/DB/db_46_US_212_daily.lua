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

local lookup = {'Paladin-Retribution','Unknown-Unknown','Druid-Balance','Mage-Frost','Priest-Discipline','Priest-Holy','Priest-Shadow','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Paladin-Holy','Druid-Restoration','Druid-Guardian','Warrior-Protection','DemonHunter-Devourer','DemonHunter-Havoc','Hunter-BeastMastery','Evoker-Preservation','Hunter-Marksmanship','Warlock-Destruction','Warrior-Arms','Paladin-Protection','Monk-Mistweaver','Monk-Windwalker','Monk-Brewmaster','Rogue-Subtlety','Shaman-Restoration',}
local provider = {region='US',realm='Terokkar',name='US',type='daily',zone=46,date='2026-05-11',data={Ab='Abuna:BAABLgAECn8dAAIBAAgJAhPCRACJAQhoDAAABQAoAGkMAAAFADkAawwAAAUAMQBqDAAABABFAGwMAAADAD0AbQwAAAEAIgDqDAAABQA+AG4MAAABACMAAQAICQITwkQAiQEIaAwAAAUAKABpDAAABQA5AGsMAAAFADEAagwAAAQARQBsDAAAAwA9AG0MAAABACIA6gwAAAUAPgBuDAAAAQAjAAAA.',
Ad='Adreni:BAAALgADCgUJBQAAAA==.',
Ae='Aelzia:BAAALgAECgEJAgAAAA==.Aennivan:BAAALgADCgcJBwABLgAECgMJBwACAAAAAA==.Aestia:BAAALgAECgMJAwAAAA==.',
Al='Alfarin:BAAALgAECgEJAQAAAA==.Aljern:BAAALgADCgEJAgAAAA==.Alpha:BAAALgAECgYJBwAAAA==.Alysra:BAAALgADCgUJBQABLgAFFAYJFwADAF0hAA==.',
Am='Ammogal:BAAALgAECgQJBAAAAA==.',
An='Andyson:BAAALgAECgMJBQAAAA==.Antandra:BAAALgAECgYJEwAAAA==.Anwen:BAABLgAECn8ZAAIEAAgJMRVbNADfAQhoDAAAAwAxAGkMAAADAE0AawwAAAMALgBqDAAABAAzAGwMAAADAD4AbQwAAAIAJADqDAAABQA/AG4MAAACACsABAAICTEVWzQA3wEIaAwAAAMAMQBpDAAAAwBNAGsMAAADAC4AagwAAAQAMwBsDAAAAwA+AG0MAAACACQA6gwAAAUAPwBuDAAAAgArAAAA.',
Ar='Arawen:BAAALgAECgQJBgABLgAECggJGQAEADEVAA==.',
Av='Avadrea:BAAALgADCgEJAQAAAA==.Aválánche:BAAALgADCgEJAQAAAA==.',
Ay='Ayanea:BAABLgAECn8hAAQFAAgJJCPcBgCVAghoDAAABQBcAGkMAAAFAF4AawwAAAUAXQBqDAAABABeAGwMAAAEAFwAbQwAAAIAWgDqDAAABQBQAG4MAAADAFIABQAICech3AYAlQIIaAwAAAQAXABpDAAAAwBOAGsMAAADAFQAagwAAAMAXgBsDAAABABcAG0MAAACAFoA6gwAAAUAUABuDAAAAwBSAAYAAgm8JHNbAMYAAmkMAAABAF4AawwAAAEAXQAHAAQJTw9DOQC3AARoDAAAAQAdAGkMAAABADoAawwAAAEAHQBqDAAAAQAtAAAA.Aysá:BAAALgADCgMJBQAAAA==.',
Ba='Baberaham:BAABLgAECn8ZAAQIAAcJ8QKxjQDYAAdoDAAABgAJAGkMAAAHAAwAawwAAAQABgBqDAAAAgAOAGwMAAABAAYAbQwAAAEABQDqDAAABAAEAAgABwnxArGNANgAB2gMAAAFAAkAaQwAAAQADABrDAAABAAGAGoMAAACAA4AbAwAAAEABgBtDAAAAQAFAOoMAAADAAQACQADCXEBVhYAOAADaAwAAAEAAgBpDAAAAgADAOoMAAABAAQACgABCYQE3D4AKAABaQwAAAEACwAAAA==.Baiford:BAABLgAECn8ZAAMLAAgJXg/1SgBMAQhoDAAABQA5AGkMAAAEACIAawwAAAQAFgBqDAAAAwAxAGwMAAABABsAbQwAAAIAHQDqDAAABQBHAG4MAAABABQACwAICV4P9UoATAEIaAwAAAMAOQBpDAAAAwAiAGsMAAADABYAagwAAAMAMQBsDAAAAQAbAG0MAAACAB0A6gwAAAUARwBuDAAAAQAUAAEAAwnyC161AKIAA2gMAAACACsAaQwAAAEAHgBrDAAAAQAQAAAA.Baldie:BAAALgADCgEJAQAAAA==.Batteries:BAAALgAECgMJBAAAAA==.',
Be='Bearitto:BAABLgAECn8uAAIMAAgJsiBiCgC0AghoDAAACABgAGkMAAAHAFAAawwAAAgAWgBqDAAABwBXAGwMAAAGAFgAbQwAAAIAYQDqDAAABgBUAG4MAAACAC0ADAAICbIgYgoAtAIIaAwAAAgAYABpDAAABwBQAGsMAAAIAFoAagwAAAcAVwBsDAAABgBYAG0MAAACAGEA6gwAAAYAVABuDAAAAgAtAAAA.',
Bi='Bigpony:BAAALgADCgYJCAAAAA==.',
Bl='Bloodrain:BAAALgADCgYJBgAAAA==.',
Bo='Bobsan:BAAALgAECgQJBAAAAA==.',
Br='Breyvarian:BAAALgADCgUJBQAAAA==.Broland:BAAALgAECgYJEgAAAA==.',
Bu='Burningvoker:BAAALgADCgYJBgAAAA==.',
Ca='Caitycat:BAABLgAECn8XAAIMAAgJdxUqHAD1AQhoDAAABABMAGkMAAAEAEEAawwAAAQAOABqDAAAAwA/AGwMAAACACoAbQwAAAEALQDqDAAABABIAG4MAAABABEADAAICXcVKhwA9QEIaAwAAAQATABpDAAABABBAGsMAAAEADgAagwAAAMAPwBsDAAAAgAqAG0MAAABAC0A6gwAAAQASABuDAAAAQARAAAA.Calliopê:BAAALgAECgYJEQAAAA==.Candycane:BAAALgADCgQJBAAAAA==.Carabina:BAAALgADCgIJAgAAAA==.Casseopea:BAAALgADCgYJCQABLgAECgMJCQACAAAAAA==.Catherinn:BAAALgAECgUJBQAAAA==.Cattlock:BAAALgAECgQJCwAAAA==.',
Ch='Chaltin:BAAALgAECgMJAwAAAA==.Chillhunt:BAAALgADCgIJAgAAAA==.',
Co='Coldhand:BAAALgAECgkJBgAAAA==.Colë:BAABLgAECn8aAAINAAgJFxRuCgCSAQhoDAAABAAoAGkMAAAEADsAawwAAAQAQgBqDAAABAA7AGwMAAADADkAbQwAAAEAIgDqDAAABQA9AG4MAAABACYADQAICRcUbgoAkgEIaAwAAAQAKABpDAAABAA7AGsMAAAEAEIAagwAAAQAOwBsDAAAAwA5AG0MAAABACIA6gwAAAUAPQBuDAAAAQAmAAAA.',
['Cæ']='Cærus:BAAALgAECgYJBgABLgAFFAYJDwAHAD4VAA==.',
Da='Daedrina:BAAALgADCgMJAwAAAA==.Dalkrim:BAABLgAECn8dAAIKAAgJJhxCCgDpAQhoDAAABQBfAGkMAAAFAFIAawwAAAUATQBqDAAABABHAGwMAAADAEkAbQwAAAEAJQDqDAAABQBWAG4MAAABADMACgAICSYcQgoA6QEIaAwAAAUAXwBpDAAABQBSAGsMAAAFAE0AagwAAAQARwBsDAAAAwBJAG0MAAABACUA6gwAAAUAVgBuDAAAAQAzAAAA.',
De='Deadblanchy:BAAALgADCgIJAgAAAA==.Debboi:BAAALgADCgUJBQAAAA==.Denzel:BAAALgAECgYJBQAAAA==.Derrick:BAAALgAECgYJEQAAAA==.Desol:BAAALgADCgEJAQAAAA==.Destrya:BAABLgAECn8hAAIOAAgJMSBtBAB4AghoDAAABQBYAGkMAAAFAFUAawwAAAUAUABqDAAABAA3AGwMAAAEAFQAbQwAAAIARwDqDAAABQBdAG4MAAADAEkADgAICTEgbQQAeAIIaAwAAAUAWABpDAAABQBVAGsMAAAFAFAAagwAAAQANwBsDAAABABUAG0MAAACAEcA6gwAAAUAXQBuDAAAAwBJAAAA.',
Di='Diamondhoof:BAAALgADCgYJBgAAAA==.Dibbsette:BAABLgAECn8eAAMFAAgJvxwDGADdAQhoDAAABQBQAGkMAAAFAFAAawwAAAUARABqDAAABABHAGwMAAADAEIAbQwAAAEATADqDAAABgBMAG4MAAABAEQABQAICb8cAxgA3QEIaAwAAAQAUABpDAAABABQAGsMAAAEAEQAagwAAAMARwBsDAAAAgBCAG0MAAABAEwA6gwAAAUATABuDAAAAQBEAAcABglBDZMkADEBBmgMAAABABoAaQwAAAEAKABrDAAAAQAhAGoMAAABADsAbAwAAAEAEwDqDAAAAQAyAAAA.',
Do='Douber:BAAALgADCgYJCAAAAA==.',
Dr='Drosera:BAAALgADCgYJBgAAAA==.',
Ds='Dshiznit:BAAALgAECgEJAQABLgAECgYJEQACAAAAAA==.',
Dw='Dwamli:BAAALgAECgQJDAAAAA==.',
Dy='Dynamitedave:BAAALgAECgUJDAABLgAECgYJEQACAAAAAA==.',
['Dø']='Dømino:BAAALgAECgQJEAAAAA==.',
Eb='Ebolabeef:BAABLgAECn8gAAIIAAgJPCWKCQDXAghoDAAABQBcAGkMAAAFAGEAawwAAAUAXgBqDAAAAwBZAGwMAAAEAGAAbQwAAAIAWgDqDAAABQBhAG4MAAADAGMACAAICTwligkA1wIIaAwAAAUAXABpDAAABQBhAGsMAAAFAF4AagwAAAMAWQBsDAAABABgAG0MAAACAFoA6gwAAAUAYQBuDAAAAwBjAAAA.',
Ei='Eirlys:BAAALgAECgYJEAAAAA==.',
El='Elky:BAAALgADCgkJHAABLgAECgMJBgACAAAAAA==.Elìyon:BAABLgAECn8oAAMPAAgJZQ3rOwBXAQhoDAAABgAkAGkMAAAGACUAawwAAAYAMABqDAAABQA0AGwMAAAFACkAbQwAAAMAFgDqDAAABgAaAG4MAAADABwADwAICWUN6zsAVwEIaAwAAAYAJABpDAAABgAlAGsMAAAGADAAagwAAAUANABsDAAABQApAG0MAAADABYA6gwAAAUAGgBuDAAAAwAcABAAAQmhAS99ACIAAeoMAAABAAQAAAA=.',
Es='Espyvon:BAAALgADCgQJBAAAAA==.',
Et='Eternalay:BAAALgAECgYJBwAAAA==.Eternshot:BAAALgADCgEJAQAAAA==.Eternsword:BAAALgADCgYJBgAAAA==.',
Ev='Evelanara:BAAALgADCgUJBQAAAA==.Evelinnia:BAAALgADCgMJAwAAAA==.Evilmurkii:BAAALgAECgEJBgABLgAECgYJEAACAAAAAA==.Evilssoul:BAAALgAECgQJBAAAAA==.',
Fe='Feltsmer:BAAALgADCgYJCQAAAA==.Fenira:BAAALgADCgUJBQAAAA==.Ferguz:BAABLgAECn8YAAIRAAcJ2hu5JwDDAQdoDAAABABRAGkMAAAEAFAAawwAAAQAWQBqDAAABABKAGwMAAADADwAbQwAAAEAMQDqDAAABABCABEABwnaG7knAMMBB2gMAAAEAFEAaQwAAAQAUABrDAAABABZAGoMAAAEAEoAbAwAAAMAPABtDAAAAQAxAOoMAAAEAEIAAAA=.',
Fo='Foscora:BAAALgAECgEJAQAAAA==.',
Fr='Frushy:BAAALgADCgcJBwAAAA==.',
Fu='Fugu:BAAALgADCggJEQAAAA==.',
Ga='Gannicûs:BAAALgAECgEJAQAAAA==.Garlando:BAAALgAECgEJAQAAAA==.',
Go='Goatmommy:BAAALgAECgQJDgAAAA==.Goph:BAAALgADCgMJBQAAAA==.Goremnar:BAAALgADCgYJBgAAAA==.',
Gr='Grimmfury:BAAALgAECgMJCQAAAA==.Grimmtide:BAAALgADCgYJBgAAAA==.Grolgor:BAAALgADCgQJBAAAAA==.Grïffïth:BAACLgAFFH8cAAMBAAcJPxpgAwC/AQdoDAAABgBcAGkMAAAEAFkAawwAAAUALgBqDAAABABCAGwMAAADAGAAbQwAAAEADQDqDAAABQBBAAEABgn3F2ADAL8BBmgMAAAGAFwAaQwAAAQAWQBrDAAABQAuAGoMAAAEAEIAbQwAAAEADQDqDAAABQBBAAsAAQnYAL8cAEYAAWwMAAADAAIALgAECn8rAAMBAAkJjSEZDwAVAwABAAkJjSEZDwAVAwALAAYJSw9pRwBaAQAAAA==.',
Gu='Gunjir:BAAALgAECgMJCQAAAA==.',
Gw='Gwyneira:BAAALgAECgYJCgABLgAECgYJEAACAAAAAA==.',
Ha='Haranbush:BAAALgADCgYJBgAAAA==.',
Hi='Hipidipi:BAAALgADCgUJBQAAAA==.',
Ho='Honeysuckles:BAAALgAECgEJAQAAAA==.',
Hu='Hucklebeary:BAAALgAECgQJBgAAAA==.Hugcubs:BAAALgADCgUJBQAAAA==.',
['Hí']='Hítgirl:BAAALgAECgQJCAAAAA==.',
Ic='Icylilith:BAAALgADCgYJCQAAAA==.',
Im='Imugi:BAABLgAECn8dAAISAAgJcgcEEgAuAQhoDAAABQAlAGkMAAAFAAoAawwAAAUADgBqDAAABAAiAGwMAAADABIAbQwAAAEADgDqDAAABQASAG4MAAABAAQAEgAICXIHBBIALgEIaAwAAAUAJQBpDAAABQAKAGsMAAAFAA4AagwAAAQAIgBsDAAAAwASAG0MAAABAA4A6gwAAAUAEgBuDAAAAQAEAAAA.',
Ir='Irithia:BAAALgADCgEJAQAAAA==.',
Is='Ishamael:BAAALgADCgcJBwABLgAECgYJEQACAAAAAA==.Issavanos:BAAALgAECgYJEAAAAA==.',
Ja='Jazmane:BAAALgADCgYJBgAAAA==.',
Je='Jenhoney:BAAALgAECgMJCQAAAA==.Jes:BAAALgADCgEJAQAAAA==.Jessdarklord:BAAALgAECgQJAwAAAA==.',
Jo='Josh:BAAALgAECgYJCQABLgAFFAYJDAATAOcTAA==.',
Ka='Kaliya:BAAALgAECgQJCQAAAA==.Kashar:BAAALgADCgMJAwAAAA==.',
Ke='Kevdog:BAABLgAECn8dAAIUAAgJMRAPBwCGAQhoDAAABQAnAGkMAAAFADIAawwAAAUAQABqDAAABAAqAGwMAAADACoAbQwAAAEAEADqDAAABQA1AG4MAAABABcAFAAICTEQDwcAhgEIaAwAAAUAJwBpDAAABQAyAGsMAAAFAEAAagwAAAQAKgBsDAAAAwAqAG0MAAABABAA6gwAAAUANQBuDAAAAQAXAAAA.',
Kh='Khelemarth:BAAALgAECgEJBAAAAA==.',
Ki='Kire:BAABLgAECn8aAAMOAAkJaR9CAgDPAgloDAAAAwA1AGkMAAADAF4AawwAAAMAUQBqDAAABABVAGwMAAAEAF8AbQwAAAIAQgDqDAAABABbAG4MAAACAFYAbwwAAAEASAAOAAkJaR9CAgDPAgloDAAAAwA1AGkMAAADAF4AawwAAAMAUQBqDAAABABVAGwMAAAEAF8AbQwAAAIAQgDqDAAAAwBbAG4MAAACAFYAbwwAAAEASAAVAAEJ0Q7NQAA3AAHqDAAAAQAlAAAA.Kirohan:BAAALgADCgcJCgAAAA==.',
Ko='Kobellr:BAAALgADCgUJBQAAAA==.Koldov:BAAALgAECgEJAQAAAA==.Kosmik:BAAALgADCgcJCwAAAA==.',
Kr='Krimzin:BAAALgAECgEJAgABLgAFFAQJDAARAHIbAA==.',
Ku='Kuiu:BAAALgADCgEJAQAAAA==.Kulnurayne:BAAALgADCgcJDAAAAA==.Kuna:BAAALgAECgQJCAAAAA==.Kushta:BAABLgAECn8YAAIBAAgJix0MGQDTAghoDAAABgBVAGkMAAAEAGEAawwAAAQATQBqDAAAAwBeAGwMAAADAFYAbQwAAAEADwDqDAAAAQBKAG4MAAACAFsAAQAICYsdDBkA0wIIaAwAAAYAVQBpDAAABABhAGsMAAAEAE0AagwAAAMAXgBsDAAAAwBWAG0MAAABAA8A6gwAAAEASgBuDAAAAgBbAAAA.',
La='Lackjaw:BAABLgAECn8aAAIUAAgJUA73EQC8AQhoDAAAAwAiAGkMAAAEACwAawwAAAUAJABqDAAABAAiAGwMAAAEADAAbQwAAAIAFQDqDAAAAgAmAG4MAAACACAAFAAICVAO9xEAvAEIaAwAAAMAIgBpDAAABAAsAGsMAAAFACQAagwAAAQAIgBsDAAABAAwAG0MAAACABUA6gwAAAIAJgBuDAAAAgAgAAAA.Landrick:BAACLgAFFH8IAAIKAAMJ+gqmFgCwAANoDAAABAAVAGkMAAADADAA6gwAAAEADgAKAAMJ+gqmFgCwAANoDAAABAAVAGkMAAADADAA6gwAAAEADgAuAAQKfzEAAgoACQlIGkkGAE0CAAoACQlIGkkGAE0CAAAA.Lanejack:BAAALgADCgQJBwAAAA==.Larissah:BAEALgADCgUJAgABLgAECgkJHgAWAFYZAA==.Lava:BAAALgAECggJDwAAAA==.',
Lg='Lgang:BAABLgAECn8VAAIQAAYJ5gqGPAANAQZoDAAABgAsAGkMAAAGAB4AawwAAAUAHQBqDAAAAQAFAGwMAAABABMA6gwAAAIADwAQAAYJ5gqGPAANAQZoDAAABgAsAGkMAAAGAB4AawwAAAUAHQBqDAAAAQAFAGwMAAABABMA6gwAAAIADwAAAA==.',
Li='Lifeblõõm:BAABLgAECn8UAAMMAAcJUSEwDgB/AgdoDAAAAwBfAGkMAAADAFwAawwAAAMAWwBqDAAABABZAGwMAAADAEkA6gwAAAMAWABuDAAAAQBDAAwABwlRITAOAH8CB2gMAAADAF8AaQwAAAMAXABrDAAAAwBbAGoMAAADAFkAbAwAAAIASQDqDAAAAwBYAG4MAAABAEMAAwACCYwOa10AMwACagwAAAEANwBsDAAAAQAlAAAA.Lilium:BAAALgAECgYJBgAAAA==.',
Ll='Llau:BAABLgAECn8eAAIXAAgJrxqpCQBnAghoDAAABABAAGkMAAAEAFEAawwAAAQATABqDAAAAwA5AGwMAAAFAE8AbQwAAAIAJwDqDAAABQBTAG4MAAADAD8AFwAICa8aqQkAZwIIaAwAAAQAQABpDAAABABRAGsMAAAEAEwAagwAAAMAOQBsDAAABQBPAG0MAAACACcA6gwAAAUAUwBuDAAAAwA/AAAA.',
Lo='Losia:BAAALgAECgMJCQAAAA==.Loveinvain:BAAALgAECgMJAgAAAA==.',
Lu='Lunabun:BAAALgADCgcJEwAAAA==.',
['Lû']='Lûffy:BAAALgAECgkJCQAAAA==.',
Ma='Malorn:BAABLgAECn8gAAQYAAgJlBVREADIAQhoDAAABQAvAGkMAAAEAD4AawwAAAUAOgBqDAAABAA4AGwMAAADADcAbQwAAAIANgDqDAAABwA7AG4MAAACADEAGAAICZQVURAAyAEIaAwAAAEALwBpDAAAAQA+AGsMAAABADoAagwAAAEAEgBsDAAAAQA3AG0MAAABADYA6gwAAAIAOwBuDAAAAgAxABkABgntDthDADMBBmgMAAAEABgAaQwAAAMANgBrDAAABAAuAGoMAAADADgAbAwAAAIAEADqDAAABAAxABcAAgloDIhOAFsAAm0MAAABACQA6gwAAAEAGwAAAA==.Manaaddict:BAAALgAECgYJBgAAAA==.',
Mi='Midníght:BAAALgAECgEJAQABLgAECgMJBgACAAAAAA==.',
Mo='Moltencarl:BAAALgAECgEJAgAAAA==.',
My='Myrna:BAAALgAECgMJAwAAAA==.',
Ni='Niege:BAAALgAECgYJCgAAAA==.Niiso:BAAALgAECgMJAwAAAA==.Nivina:BAAALgADCgcJBwAAAA==.',
Nk='Nkagnyto:BAABLgAECn8VAAMZAAUJCBBtNADTAAVoDAAABgA5AGkMAAAFADcAawwAAAUAFgBqDAAAAgAuAOoMAAADAB0AGQAFCQgQbTQA0wAFaAwAAAUAOQBpDAAABAA3AGsMAAAEABYAagwAAAEAGwDqDAAAAwAdABgABAnHDBg9AJsABGgMAAABAB4AaQwAAAEAMgBrDAAAAQARAGoMAAABAC4AAAA=.Nkanue:BAAALgADCgIJAgABLgAECgUJFQAZAAgQAA==.',
No='Noonstalker:BAAALgAECgUJCwAAAA==.',
Or='Oric:BAAALgADCgMJAwABLgAECgYJEwACAAAAAA==.Orintaar:BAAALgADCgMJAwAAAA==.Ormac:BAAALgAECgYJEwAAAA==.Ororoe:BAABLgAECn8kAAMZAAgJ9xprFABrAghoDAAABgBYAGkMAAAGAFIAawwAAAYAOgBqDAAABABJAGwMAAAEAEQAbQwAAAIASwDqDAAABgA1AG4MAAACADcAGQAICc0aaxQAawIIaAwAAAMAWABpDAAAAwBSAGsMAAADADoAagwAAAEASQBsDAAAAgBEAG0MAAABAEsA6gwAAAMAMwBuDAAAAgA3ABgABwn1EGAcAE8BB2gMAAADADYAaQwAAAMAKgBrDAAAAwArAGoMAAADACIAbAwAAAIAJwBtDAAAAQAZAOoMAAADADUAAAA=.Orphancalf:BAAALgAECgIJAgAAAA==.',
Pa='Palapo:BAAALgAECgMJBwAAAA==.Panrocktar:BAAALgADCgEJAQAAAA==.Paudrig:BAAALgAECgYJDQAAAA==.',
Pe='Perfect:BAAALgAECgQJBgAAAA==.',
Ph='Phagetouched:BAAALgAECgUJAwAAAA==.Phaydre:BAAALgAECgYJEgABLgAFFAUJCgASANgPAA==.',
Pi='Picklenick:BAABLgAECn8cAAIaAAgJbBBhEQCiAQhoDAAABQAmAGkMAAAFADoAawwAAAUANgBqDAAAAwAfAGwMAAADACcAbQwAAAEADwDqDAAABQAmAG4MAAABADAAGgAICWwQYREAogEIaAwAAAUAJgBpDAAABQA6AGsMAAAFADYAagwAAAMAHwBsDAAAAwAnAG0MAAABAA8A6gwAAAUAJgBuDAAAAQAwAAAA.',
Po='Ponytree:BAAALgAECggJEQAAAA==.Porani:BAAALgAECgEJAQAAAA==.',
Pr='Prismo:BAAALgAECgcJDgAAAA==.',
Pw='Pwnbuggy:BAABLgAECn8dAAIIAAgJpBeOJwD0AQhoDAAABQAoAGkMAAAEAFUAawwAAAQAOwBqDAAAAwA5AGwMAAACACoAbQwAAAIALwDqDAAABwBOAG4MAAACAEYACAAICaQXjicA9AEIaAwAAAUAKABpDAAABABVAGsMAAAEADsAagwAAAMAOQBsDAAAAgAqAG0MAAACAC8A6gwAAAcATgBuDAAAAgBGAAAA.',
Qa='Qartoga:BAAALgADCgEJAQABLgAECgQJCAACAAAAAA==.',
Ql='Qlue:BAAALgADCgcJBwAAAA==.',
Ra='Rabellious:BAAALgAECgEJAQAAAA==.Rabin:BAAALgADCgIJAgAAAA==.Racistgreen:BAAALgAECgIJAgAAAA==.Raethys:BAAALgADCgUJBQAAAA==.Rafikibull:BAAALgAECgIJBQAAAA==.Raindrop:BAABLgAECn8dAAIMAAgJHRelIwC9AQhoDAAABQBYAGkMAAAFAD4AawwAAAUARwBqDAAABAAvAGwMAAADADsAbQwAAAIAHgDqDAAABABEAG4MAAABAC0ADAAICR0XpSMAvQEIaAwAAAUAWABpDAAABQA+AGsMAAAFAEcAagwAAAQALwBsDAAAAwA7AG0MAAACAB4A6gwAAAQARABuDAAAAQAtAAAA.Ramah:BAAALgAECgMJCQAAAA==.Ramen:BAAALgADCgEJAQAAAA==.',
Re='Reignstorm:BAABLgAECn8dAAIJAAgJzAsFCQAmAQhoDAAABQAjAGkMAAAFACcAawwAAAUAIwBqDAAABAAUAGwMAAADABsAbQwAAAEAEgDqDAAABQAiAG4MAAABABQACQAICcwLBQkAJgEIaAwAAAUAIwBpDAAABQAnAGsMAAAFACMAagwAAAQAFABsDAAAAwAbAG0MAAABABIA6gwAAAUAIgBuDAAAAQAUAAAA.Reivax:BAABLgAECn8pAAIRAAgJzRNMJgDKAQhoDAAABwBGAGkMAAAGAD8AawwAAAYALwBqDAAABQBBAGwMAAAFADIAbQwAAAMAEQDqDAAABgBIAG4MAAADAB8AEQAICc0TTCYAygEIaAwAAAcARgBpDAAABgA/AGsMAAAGAC8AagwAAAUAQQBsDAAABQAyAG0MAAADABEA6gwAAAYASABuDAAAAwAfAAAA.Rethelm:BAAALgAECgYJEwAAAA==.Retreats:BAAALgADCgUJBQAAAA==.Retsella:BAAALgADCgkJIgAAAA==.Reveum:BAABLgAECn8vAAMVAAgJPgqVGgD3AAhoDAAACgAeAGkMAAAIAB0AawwAAAgAIQBqDAAABgAcAGwMAAAFACEAbQwAAAIAEQDqDAAABgAdAG4MAAACAAkADgAICW0JjRcADgEIaAwAAAQAGQBpDAAABAAbAGsMAAAEABkAagwAAAQADQBsDAAAAwAhAG0MAAACABEA6gwAAAMAHQBuDAAAAgAJABUABglfC5UaAPcABmgMAAAGAB4AaQwAAAQAHQBrDAAABAAhAGoMAAACABwAbAwAAAIAGgDqDAAAAwAZAAAA.Revân:BAAALgADCgMJAwAAAA==.',
Rh='Rhaegár:BAAALgAECgQJCQAAAA==.',
Ro='Robyerto:BAAALgADCgMJAwAAAA==.Rogl:BAACLgAFFH8MAAIMAAUJRCEMBgDuAQVoDAAAAwBRAGkMAAADAFwAawwAAAIAYABqDAAAAQA6AOoMAAADAGEADAAFCUQhDAYA7gEFaAwAAAMAUQBpDAAAAwBcAGsMAAACAGAAagwAAAEAOgDqDAAAAwBhAC4ABAp/HQACDAAHCRsgUBwAWgIADAAHCRsgUBwAWgIAAAA=.Rosgard:BAAALgADCggJCAAAAA==.',
Ru='Ruhll:BAAALgADCgcJCQAAAA==.Ruminate:BAAALgADCgYJCgABLgAECgMJBgACAAAAAA==.Rustychi:BAAALgAECgYJDwAAAA==.',
['Rá']='Rámpapi:BAAALgAECgQJDgAAAA==.',
Sa='Sammaile:BAAALgAECgYJEQAAAA==.Sarahsmith:BAAALgAECgYJEwAAAA==.Saucypeach:BAAALgAECgYJDQAAAA==.',
Sc='Scamander:BAABLgAECn8WAAIRAAkJDxYSJgAiAgloDAAAAgA4AGkMAAADADQAawwAAAMATgBqDAAAAgAzAGwMAAACAEkAbQwAAAEANgDqDAAABQA0AG4MAAADADEAbwwAAAEAIQARAAkJDxYSJgAiAgloDAAAAgA4AGkMAAADADQAawwAAAMATgBqDAAAAgAzAGwMAAACAEkAbQwAAAEANgDqDAAABQA0AG4MAAADADEAbwwAAAEAIQAAAA==.Scarmouse:BAAALgAECgEJAQAAAA==.',
Se='Seifer:BAAALgADCgkJJQAAAA==.Semnickmonk:BAAALgAECgMJBAAAAA==.Senjosaku:BAAALgAFFAEJAQABLgAFFAMJCQAEAEEbAA==.Serigo:BAAALgAECgUJDgAAAA==.Serral:BAAALgAFFAEJAQAAAA==.',
Sh='Shaxx:BAAALgADCgEJAQABLgAECgUJDgACAAAAAA==.',
Sk='Skayley:BAAALgADCgUJBQAAAA==.',
Sm='Smoochy:BAAALgAECgEJAQAAAA==.',
So='Solysz:BAAALgAECgYJEwAAAA==.Sophietheone:BAAALgADCgIJAgAAAA==.Soten:BAAALgADCgcJBwABLgAECgMJCQACAAAAAA==.Soß:BAACLgAFFH8KAAIEAAQJBBrbJAAhAQRoDAAAAwBWAGkMAAACAFoAbAwAAAEAAgDqDAAABABWAAQABAkEGtskACEBBGgMAAADAFYAaQwAAAIAWgBsDAAAAQACAOoMAAAEAFYALgAECn8fAAIEAAcJzyGZUgBAAgAEAAcJzyGZUgBAAgAAAA==.',
Sp='Spongébob:BAAALgAECgIJAgAAAA==.Spork:BAAALgAECgMJBgAAAA==.',
St='Stimcheck:BAAALgADCgcJBwABLgADCggJCAACAAAAAA==.Stmary:BAAALgADCgQJBAAAAA==.Størmzmisery:BAAALgADCgUJBQAAAA==.',
Su='Subzéro:BAABLgAECn8ZAAIEAAYJWAvZgAAfAQZoDAAABgAgAGkMAAAGAB8AawwAAAUAHQBqDAAAAgAaAGwMAAACACcA6gwAAAQADAAEAAYJWAvZgAAfAQZoDAAABgAgAGkMAAAGAB8AawwAAAUAHQBqDAAAAgAaAGwMAAACACcA6gwAAAQADAAAAA==.',
Sw='Sweetwhisper:BAAALgAECgYJEQAAAA==.',
Sy='Sylitae:BAAALgADCgcJHAAAAA==.',
['Så']='Såbëtha:BAAALgADCgMJBQAAAA==.',
Ta='Tazzen:BAAALgAECgQJBQAAAA==.',
Te='Teletern:BAAALgADCgMJBQAAAA==.Tempeststørm:BAAALgAECgUJBwAAAA==.',
Th='Thaunelian:BAAALgAECgQJBAABLgAECggJIAAYAJQVAA==.Thoristain:BAAALgAECgYJEwAAAA==.Thorshman:BAAALgADCgcJBwABLgAECgYJEwACAAAAAA==.Thrain:BAABLgAECn8dAAIBAAgJvwuNTAByAQhoDAAABQAiAGkMAAAEACsAawwAAAUAIABqDAAABAA4AGwMAAADAC0AbQwAAAEAEwDqDAAABgATAG4MAAABAA8AAQAICb8LjUwAcgEIaAwAAAUAIgBpDAAABAArAGsMAAAFACAAagwAAAQAOABsDAAAAwAtAG0MAAABABMA6gwAAAYAEwBuDAAAAQAPAAAA.Threefive:BAAALgAECgQJBQAAAA==.',
To='Torvar:BAAALgADCgEJAgAAAA==.Totemíc:BAAALgAECgQJBQAAAA==.',
Tp='Tpops:BAAALgADCgQJBAAAAA==.',
Ty='Tyrdrea:BAAALgADCgkJCQAAAA==.',
Un='Unholypwnage:BAAALgADCgEJAQAAAA==.',
Va='Vallak:BAAALgAECgQJBAAAAA==.',
Ve='Velarion:BAAALgAECgEJAQAAAA==.Veryundead:BAABLgAECn8oAAIUAAgJExH7BgCIAQhoDAAABwBCAGkMAAAHAEIAawwAAAcAKwBqDAAABgAtAGwMAAAEABcAbQwAAAIAFADqDAAABgA0AG4MAAABACEAFAAICRMR+wYAiAEIaAwAAAcAQgBpDAAABwBCAGsMAAAHACsAagwAAAYALQBsDAAABAAXAG0MAAACABQA6gwAAAYANABuDAAAAQAhAAAA.',
Vo='Void:BAABLgAECn8VAAIQAAYJwBe+FABYAQZoDAAABQBBAGkMAAAFAD0AawwAAAUAOABqDAAAAgBTAGwMAAACAEUA6gwAAAIAMgAQAAYJwBe+FABYAQZoDAAABQBBAGkMAAAFAD0AawwAAAUAOABqDAAAAgBTAGwMAAACAEUA6gwAAAIAMgAAAA==.Voidmara:BAAALgAECgEJAgAAAA==.Voíd:BAAALgAECgEJAQAAAA==.',
Vr='Vrylykos:BAAALgAECgYJCgAAAA==.',
Wa='Waddlez:BAAALgAECgEJAQAAAA==.Wardawg:BAAALgADCgEJAQABLgAECggJIQAFACQjAA==.Wargrylls:BAAALgADCgcJBwAAAA==.',
We='Wendrin:BAAALgAECgYJBgAAAA==.',
Wh='White:BAAALgAECgQJBQAAAA==.',
Wo='Wolvynlyfe:BAAALgADCgIJAgAAAA==.',
Xa='Xanarine:BAABLgAECn8VAAMLAAYJhRQwRABnAQZoDAAABgBCAGkMAAAGAEcAawwAAAUANABqDAAAAQASAGwMAAABACAA6gwAAAIASQALAAYJhRQwRABnAQZoDAAABQBCAGkMAAAFAEcAawwAAAUANABqDAAAAQASAGwMAAABACAA6gwAAAIASQABAAIJtQdGIQFbAAJoDAAAAQAbAGkMAAABAAsAAAA=.Xavíous:BAAALgADCgYJBgAAAA==.',
Xe='Xeeva:BAABLgAECn8VAAIbAAUJXxc1MwBWAQVoDAAABgAyAGkMAAAFAFUAawwAAAUAOgBqDAAAAgBGAOoMAAADACEAGwAFCV8XNTMAVgEFaAwAAAYAMgBpDAAABQBVAGsMAAAFADoAagwAAAIARgDqDAAAAwAhAAAA.',
Xu='Xuralxia:BAAALgAECgEJBgAAAA==.',
Zi='Zink:BAAALgAECgEJAQAAAA==.Ziyad:BAABLgAECn8WAAQDAAcJexM/HQBdAQdoDAAABAAyAGkMAAAEADcAawwAAAQANABqDAAAAwAvAGwMAAACACYAbQwAAAEAJQDqDAAABABAAAMABwkEET8dAF0BB2gMAAADAC0AaQwAAAMAFgBrDAAAAwA0AGoMAAADAC8AbAwAAAIAJgBtDAAAAQAlAOoMAAADAEAADQADCcMTCiEAlgADaAwAAAEAMgBpDAAAAQA3AGsMAAABAC0ADAABCYgBJeoAGgAB6gwAAAEAAwAAAA==.',
Zy='Zyn:BAAALgAECgMJAwAAAA==.',
['Zè']='Zèró:BAABLgAECn8VAAMWAAYJnBzbDQBtAQZoDAAABABhAGkMAAAFAEAAawwAAAUAPgBqDAAAAgBGAGwMAAACAEIA6gwAAAMASgAWAAYJnBzbDQBtAQZoDAAABABhAGkMAAAEAEAAawwAAAQAPgBqDAAAAgBGAGwMAAACAEIA6gwAAAMASgABAAIJPxBNyACAAAJpDAAAAQAvAGsMAAABACQAAAA=.',
['Ðü']='Ðüß:BAAALgADCgIJAgABLgAECgMJAwACAAAAAA==.',
['Ön']='Öna:BAABLgAECn8oAAIRAAgJ8BQkLgCmAQhoDAAABwBQAGkMAAAHAEUAawwAAAcARQBqDAAABgBPAGwMAAAEADQAbQwAAAEAHwDqDAAABwA3AG4MAAABAA8AEQAICfAUJC4ApgEIaAwAAAcAUABpDAAABwBFAGsMAAAHAEUAagwAAAYATwBsDAAABAA0AG0MAAABAB8A6gwAAAcANwBuDAAAAQAPAAAA.',
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
