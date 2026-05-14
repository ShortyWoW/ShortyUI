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

local lookup = {'Paladin-Retribution','Unknown-Unknown','Druid-Balance','Mage-Frost','Priest-Discipline','Priest-Holy','Priest-Shadow','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Paladin-Holy','Druid-Restoration','Druid-Guardian','Warrior-Protection','DemonHunter-Devourer','DemonHunter-Havoc','Hunter-BeastMastery','Evoker-Preservation','Hunter-Marksmanship','Warlock-Destruction','Warrior-Arms','Monk-Mistweaver','Monk-Windwalker','Monk-Brewmaster','Rogue-Subtlety','Shaman-Restoration','Paladin-Protection',}
local provider = {region='US',realm='Terokkar',name='US',type='daily',zone=46,date='2026-05-13',data={Ab='Abuna:BAABLgAECn8eAAIBAAgJAhPySQB+AQhoDAAABQAoAGkMAAAFADkAawwAAAUAMQBqDAAABABFAGwMAAADAD0AbQwAAAEAIgDqDAAABQA+AG4MAAACACMAAQAICQIT8kkAfgEIaAwAAAUAKABpDAAABQA5AGsMAAAFADEAagwAAAQARQBsDAAAAwA9AG0MAAABACIA6gwAAAUAPgBuDAAAAgAjAAAA.',
Ad='Adreni:BAAALgADCgUJBQAAAA==.',
Ae='Aelzia:BAAALgAECgEJAwAAAA==.Aennivan:BAAALgADCgcJBwABLgAECgMJBwACAAAAAA==.Aestia:BAAALgAECgMJAwAAAA==.',
Al='Alfarin:BAAALgAECgEJAQAAAA==.Aljern:BAAALgADCgEJAgAAAA==.Alpha:BAAALgAECgYJBwAAAA==.Alysra:BAAALgADCgUJBQABLgAFFAYJGwADAKghAA==.',
Am='Ammogal:BAAALgAECgQJBAAAAA==.',
An='Andyson:BAAALgAECgMJBwAAAA==.Antandra:BAAALgAECgYJEwAAAA==.Anwen:BAABLgAECn8ZAAIEAAgJMRVAOADYAQhoDAAAAwAxAGkMAAADAE0AawwAAAMALgBqDAAABAAzAGwMAAADAD4AbQwAAAIAJADqDAAABQA/AG4MAAACACsABAAICTEVQDgA2AEIaAwAAAMAMQBpDAAAAwBNAGsMAAADAC4AagwAAAQAMwBsDAAAAwA+AG0MAAACACQA6gwAAAUAPwBuDAAAAgArAAAA.',
Ar='Arawen:BAAALgAECgQJBgABLgAECggJGQAEADEVAA==.Artinash:BAAALgAECgUJBQAAAA==.',
Av='Avadrea:BAAALgADCgEJAQAAAA==.Aválánche:BAAALgADCgEJAQAAAA==.',
Ay='Ayanea:BAABLgAECn8hAAQFAAgJJCOOBwCQAghoDAAABQBcAGkMAAAFAF4AawwAAAUAXQBqDAAABABeAGwMAAAEAFwAbQwAAAIAWgDqDAAABQBQAG4MAAADAFIABQAICechjgcAkAIIaAwAAAQAXABpDAAAAwBOAGsMAAADAFQAagwAAAMAXgBsDAAABABcAG0MAAACAFoA6gwAAAUAUABuDAAAAwBSAAYAAgm8JHNbAMYAAmkMAAABAF4AawwAAAEAXQAHAAQJTw8ePACxAARoDAAAAQAdAGkMAAABADoAawwAAAEAHQBqDAAAAQAtAAAA.Aysá:BAAALgADCgMJBQAAAA==.',
Ba='Baberaham:BAABLgAECn8ZAAQIAAcJ8QLSkwDWAAdoDAAABgAJAGkMAAAHAAwAawwAAAQABgBqDAAAAgAOAGwMAAABAAYAbQwAAAEABQDqDAAABAAEAAgABwnxAtKTANYAB2gMAAAFAAkAaQwAAAQADABrDAAABAAGAGoMAAACAA4AbAwAAAEABgBtDAAAAQAFAOoMAAADAAQACQADCXEBVhYAOAADaAwAAAEAAgBpDAAAAgADAOoMAAABAAQACgABCYQEQkEAKAABaQwAAAEACwAAAA==.Baiford:BAABLgAECn8ZAAMLAAgJXg/2SgBMAQhoDAAABQA5AGkMAAAEACIAawwAAAQAFgBqDAAAAwAxAGwMAAABABsAbQwAAAIAHQDqDAAABQBHAG4MAAABABQACwAICV4P9koATAEIaAwAAAMAOQBpDAAAAwAiAGsMAAADABYAagwAAAMAMQBsDAAAAQAbAG0MAAACAB0A6gwAAAUARwBuDAAAAQAUAAEAAwnyC1y8AJ8AA2gMAAACACsAaQwAAAEAHgBrDAAAAQAQAAAA.Baldie:BAAALgADCgEJAQAAAA==.Batteries:BAAALgAECgMJBAAAAA==.',
Be='Bearitto:BAABLgAECn8uAAIMAAgJsiApCwC0AghoDAAACABgAGkMAAAHAFAAawwAAAgAWgBqDAAABwBXAGwMAAAGAFgAbQwAAAIAYQDqDAAABgBUAG4MAAACAC0ADAAICbIgKQsAtAIIaAwAAAgAYABpDAAABwBQAGsMAAAIAFoAagwAAAcAVwBsDAAABgBYAG0MAAACAGEA6gwAAAYAVABuDAAAAgAtAAAA.',
Bi='Bigpony:BAAALgADCgYJCAAAAA==.',
Bl='Bloodrain:BAAALgADCgYJBgAAAA==.',
Bo='Bobsan:BAAALgAECgQJBAAAAA==.',
Br='Breyvarian:BAAALgADCgUJBQAAAA==.Broland:BAAALgAECgYJEgAAAA==.',
Bu='Burningvoker:BAAALgADCgYJBgAAAA==.',
Ca='Caitycat:BAABLgAECn8YAAIMAAgJdxWxHQD1AQhoDAAABABMAGkMAAAEAEEAawwAAAQAOABqDAAAAwA/AGwMAAACACoAbQwAAAEALQDqDAAABABIAG4MAAACABEADAAICXcVsR0A9QEIaAwAAAQATABpDAAABABBAGsMAAAEADgAagwAAAMAPwBsDAAAAgAqAG0MAAABAC0A6gwAAAQASABuDAAAAgARAAAA.Calliopê:BAAALgAECgYJEQAAAA==.Candycane:BAAALgADCgQJBAAAAA==.Carabina:BAAALgADCgMJAgAAAA==.Casseopea:BAAALgADCgYJCQABLgAECgMJCQACAAAAAA==.Catherinn:BAAALgAECgUJBQAAAA==.Cattlock:BAAALgAECgQJCwAAAA==.',
Ch='Chaltin:BAAALgAECgMJAwAAAA==.Chillhunt:BAAALgADCgIJAgAAAA==.',
Co='Coldhand:BAAALgAECgkJBgAAAA==.Colë:BAABLgAECn8bAAINAAgJFxQ8CwCTAQhoDAAABAAoAGkMAAAEADsAawwAAAQAQgBqDAAABAA7AGwMAAADADkAbQwAAAEAIgDqDAAABQA9AG4MAAACACYADQAICRcUPAsAkwEIaAwAAAQAKABpDAAABAA7AGsMAAAEAEIAagwAAAQAOwBsDAAAAwA5AG0MAAABACIA6gwAAAUAPQBuDAAAAgAmAAAA.',
['Cæ']='Cærus:BAAALgAECgYJBgABLgAFFAYJDwAHAD4VAA==.',
Da='Daedrina:BAAALgADCgMJAwAAAA==.Dalkrim:BAABLgAECn8eAAIKAAgJJhwtCwDkAQhoDAAABQBfAGkMAAAFAFIAawwAAAUATQBqDAAABABHAGwMAAADAEkAbQwAAAEAJQDqDAAABQBWAG4MAAACADMACgAICSYcLQsA5AEIaAwAAAUAXwBpDAAABQBSAGsMAAAFAE0AagwAAAQARwBsDAAAAwBJAG0MAAABACUA6gwAAAUAVgBuDAAAAgAzAAAA.',
De='Deadblanchy:BAAALgADCgIJAgAAAA==.Debboi:BAAALgADCgUJBQAAAA==.Denzel:BAAALgAECgYJBQAAAA==.Derrick:BAAALgAECgYJEgAAAA==.Desol:BAAALgADCgEJAQAAAA==.Destrya:BAABLgAECn8hAAIOAAgJMSDtBABxAghoDAAABQBYAGkMAAAFAFUAawwAAAUAUABqDAAABAA3AGwMAAAEAFQAbQwAAAIARwDqDAAABQBdAG4MAAADAEkADgAICTEg7QQAcQIIaAwAAAUAWABpDAAABQBVAGsMAAAFAFAAagwAAAQANwBsDAAABABUAG0MAAACAEcA6gwAAAUAXQBuDAAAAwBJAAAA.',
Di='Diamondhoof:BAAALgADCgcJBgAAAA==.Dibbsette:BAABLgAECn8fAAMFAAgJUR0FGADdAQhoDAAABQBQAGkMAAAFAFAAawwAAAUARABqDAAABABHAGwMAAADAEIAbQwAAAEATADqDAAABgBMAG4MAAACAFAABQAICVEdBRgA3QEIaAwAAAQAUABpDAAABABQAGsMAAAEAEQAagwAAAMARwBsDAAAAgBCAG0MAAABAEwA6gwAAAUATABuDAAAAgBQAAcABglBDZwmACoBBmgMAAABABoAaQwAAAEAKABrDAAAAQAhAGoMAAABADsAbAwAAAEAEwDqDAAAAQAyAAAA.',
Do='Douber:BAAALgADCgYJCAAAAA==.',
Dr='Drosera:BAAALgADCgcJBgAAAA==.',
Ds='Dshiznit:BAAALgAECgEJAQABLgAECgYJEQACAAAAAA==.',
Dw='Dwamli:BAAALgAECgQJDAAAAA==.',
Dy='Dynamitedave:BAAALgAECgUJDAABLgAECgYJEQACAAAAAA==.',
['Dø']='Dømino:BAAALgAECgQJEAAAAA==.',
Eb='Ebolabeef:BAABLgAECn8gAAIIAAgJPCWwCgDSAghoDAAABQBcAGkMAAAFAGEAawwAAAUAXgBqDAAAAwBZAGwMAAAEAGAAbQwAAAIAWgDqDAAABQBhAG4MAAADAGMACAAICTwlsAoA0gIIaAwAAAUAXABpDAAABQBhAGsMAAAFAF4AagwAAAMAWQBsDAAABABgAG0MAAACAFoA6gwAAAUAYQBuDAAAAwBjAAAA.',
Ei='Eirlys:BAAALgAECgYJEAAAAA==.',
El='Elky:BAAALgADCgkJHAABLgAECgMJBgACAAAAAA==.Elìyon:BAABLgAECn8oAAMPAAgJZQ2+PwBVAQhoDAAABgAkAGkMAAAGACUAawwAAAYAMABqDAAABQA0AGwMAAAFACkAbQwAAAMAFgDqDAAABgAaAG4MAAADABwADwAICWUNvj8AVQEIaAwAAAYAJABpDAAABgAlAGsMAAAGADAAagwAAAUANABsDAAABQApAG0MAAADABYA6gwAAAUAGgBuDAAAAwAcABAAAQmhATF9ACIAAeoMAAABAAQAAAA=.',
Es='Espyvon:BAAALgADCgQJBAAAAA==.',
Et='Eternalay:BAAALgAECgYJBwAAAA==.Eternshot:BAAALgADCgEJAQAAAA==.Eternsword:BAAALgADCgYJBgAAAA==.',
Ev='Evelanara:BAAALgADCgUJBQAAAA==.Evelinnia:BAAALgADCgMJAwAAAA==.Evilmurkii:BAAALgAECgEJBgABLgAECgYJEAACAAAAAA==.Evilssoul:BAAALgAECgQJBAAAAA==.',
Fe='Feltsmer:BAAALgADCgYJCQAAAA==.Fenira:BAAALgADCgUJBQAAAA==.Ferguz:BAABLgAECn8ZAAIRAAgJqxr1HgD/AQhoDAAABABRAGkMAAAEAFAAawwAAAQAWQBqDAAABABKAGwMAAADADwAbQwAAAEAMQDqDAAABABCAG4MAAABADIAEQAICasa9R4A/wEIaAwAAAQAUQBpDAAABABQAGsMAAAEAFkAagwAAAQASgBsDAAAAwA8AG0MAAABADEA6gwAAAQAQgBuDAAAAQAyAAAA.',
Fo='Foscora:BAAALgAECgEJAQAAAA==.',
Fr='Frushy:BAAALgADCgcJBwAAAA==.',
Fu='Fugu:BAAALgADCggJEQAAAA==.',
Ga='Gannicûs:BAAALgAECgEJAQAAAA==.Garlando:BAAALgAECgEJAQAAAA==.',
Go='Goatmommy:BAAALgAECgQJDgAAAA==.Goph:BAAALgADCgMJBQAAAA==.Goremnar:BAAALgADCgYJBgAAAA==.',
Gr='Grimmfury:BAAALgAECgMJCQAAAA==.Grimmtide:BAAALgADCgYJBgAAAA==.Grolgor:BAAALgADCgQJBAAAAA==.Grïffïth:BAACLgAFFH8gAAMBAAcJPxp6BgC8AQdoDAAABwBcAGkMAAAFAFkAawwAAAYALgBqDAAABABCAGwMAAADAGAAbQwAAAEADQDqDAAABgBBAAEABgn3F3oGALwBBmgMAAAHAFwAaQwAAAUAWQBrDAAABgAuAGoMAAAEAEIAbQwAAAEADQDqDAAABgBBAAsAAQnYAMEcAEYAAWwMAAADAAIALgAECn8rAAMBAAkJjSEaDwAVAwABAAkJjSEaDwAVAwALAAYJSw9pRwBaAQAAAA==.',
Gu='Gunjir:BAAALgAECgMJCQAAAA==.',
Gw='Gwyneira:BAAALgAECgYJCgABLgAECgYJEAACAAAAAA==.',
Ha='Haranbush:BAAALgADCgYJBgAAAA==.',
Hi='Hipidipi:BAAALgADCgUJBQAAAA==.',
Ho='Honeysuckles:BAAALgAECgEJAQAAAA==.',
Hu='Hucklebeary:BAAALgAECgQJBgAAAA==.Hugcubs:BAAALgADCgUJBQAAAA==.',
['Hí']='Hítgirl:BAAALgAECgQJCQAAAA==.',
Ic='Icylilith:BAAALgADCgYJCQAAAA==.',
Im='Imugi:BAABLgAECn8eAAISAAgJjAehEgAwAQhoDAAABQAlAGkMAAAFAAoAawwAAAUADgBqDAAABAAiAGwMAAADABIAbQwAAAEADgDqDAAABQASAG4MAAACAAYAEgAICYwHoRIAMAEIaAwAAAUAJQBpDAAABQAKAGsMAAAFAA4AagwAAAQAIgBsDAAAAwASAG0MAAABAA4A6gwAAAUAEgBuDAAAAgAGAAAA.',
Ir='Irithia:BAAALgADCgEJAQAAAA==.',
Is='Ishamael:BAAALgADCgcJBwABLgAECgYJEQACAAAAAA==.Issavanos:BAAALgAECgYJEAAAAA==.',
Ja='Jazmane:BAAALgADCgYJBgAAAA==.',
Je='Jenhoney:BAAALgAECgMJCQAAAA==.Jes:BAAALgADCgEJAQAAAA==.Jessdarklord:BAAALgAECgQJAwAAAA==.',
Jo='Josh:BAAALgAECgYJCQABLgAFFAYJDAATAOcTAA==.',
Ka='Kaliya:BAAALgAECgQJCQAAAA==.Kashar:BAAALgADCgMJAwAAAA==.',
Ke='Kevdog:BAABLgAECn8eAAIUAAgJMRDqBwBzAQhoDAAABQAnAGkMAAAFADIAawwAAAUAQABqDAAABAAqAGwMAAADACoAbQwAAAEAEADqDAAABQA1AG4MAAACABcAFAAICTEQ6gcAcwEIaAwAAAUAJwBpDAAABQAyAGsMAAAFAEAAagwAAAQAKgBsDAAAAwAqAG0MAAABABAA6gwAAAUANQBuDAAAAgAXAAAA.',
Kh='Khelemarth:BAAALgAECgEJBAAAAA==.',
Ki='Kire:BAABLgAECn8hAAMOAAkJvx9oAgDRAgloDAAABAA1AGkMAAAEAF4AawwAAAQAWABqDAAABQBVAGwMAAAFAF8AbQwAAAMAQgDqDAAABQBbAG4MAAACAFYAbwwAAAEASAAOAAkJvx9oAgDRAgloDAAABAA1AGkMAAAEAF4AawwAAAQAWABqDAAABQBVAGwMAAAFAF8AbQwAAAMAQgDqDAAABABbAG4MAAACAFYAbwwAAAEASAAVAAEJ0Q7MQAA3AAHqDAAAAQAlAAAA.Kirohan:BAAALgADCgcJCgAAAA==.',
Ko='Kobellr:BAAALgADCgUJBQAAAA==.Koldov:BAAALgAECgEJAQAAAA==.Kosmik:BAAALgADCgcJCwAAAA==.',
Kr='Krimzin:BAAALgAECgEJAgABLgAFFAQJDAARAHIbAA==.',
Ku='Kuiu:BAAALgADCgEJAQAAAA==.Kulnurayne:BAAALgADCgcJDAAAAA==.Kuna:BAAALgAECgQJCAAAAA==.Kushta:BAABLgAECn8YAAIBAAgJix0NGQDTAghoDAAABgBVAGkMAAAEAGEAawwAAAQATQBqDAAAAwBeAGwMAAADAFYAbQwAAAEADwDqDAAAAQBKAG4MAAACAFsAAQAICYsdDRkA0wIIaAwAAAYAVQBpDAAABABhAGsMAAAEAE0AagwAAAMAXgBsDAAAAwBWAG0MAAABAA8A6gwAAAEASgBuDAAAAgBbAAAA.',
La='Lackjaw:BAABLgAECn8aAAIUAAgJUA73EQC8AQhoDAAAAwAiAGkMAAAEACwAawwAAAUAJABqDAAABAAiAGwMAAAEADAAbQwAAAIAFQDqDAAAAgAmAG4MAAACACAAFAAICVAO9xEAvAEIaAwAAAMAIgBpDAAABAAsAGsMAAAFACQAagwAAAQAIgBsDAAABAAwAG0MAAACABUA6gwAAAIAJgBuDAAAAgAgAAAA.Landrick:BAACLgAFFH8IAAIKAAMJ+grmFwCuAANoDAAABAAVAGkMAAADADAA6gwAAAEADgAKAAMJ+grmFwCuAANoDAAABAAVAGkMAAADADAA6gwAAAEADgAuAAQKfzEAAgoACQlIGgIHAEcCAAoACQlIGgIHAEcCAAAA.Lanejack:BAAALgADCgQJBwAAAA==.Larissah:BAEALgAECgkJEgAAAA==.Lava:BAAALgAECggJDwAAAA==.',
Lg='Lgang:BAABLgAECn8VAAIQAAYJ5gqIPAANAQZoDAAABgAsAGkMAAAGAB4AawwAAAUAHQBqDAAAAQAFAGwMAAABABMA6gwAAAIADwAQAAYJ5gqIPAANAQZoDAAABgAsAGkMAAAGAB4AawwAAAUAHQBqDAAAAQAFAGwMAAABABMA6gwAAAIADwAAAA==.',
Li='Lifeblõõm:BAABLgAECn8UAAMMAAcJUSE4DwB+AgdoDAAAAwBfAGkMAAADAFwAawwAAAMAWwBqDAAABABZAGwMAAADAEkA6gwAAAMAWABuDAAAAQBDAAwABwlRITgPAH4CB2gMAAADAF8AaQwAAAMAXABrDAAAAwBbAGoMAAADAFkAbAwAAAIASQDqDAAAAwBYAG4MAAABAEMAAwACCYwOE2EAMwACagwAAAEANwBsDAAAAQAlAAAA.Lilium:BAAALgAECgYJBgAAAA==.',
Ll='Llau:BAABLgAECn8eAAIWAAgJrxqfCgBjAghoDAAABABAAGkMAAAEAFEAawwAAAQATABqDAAAAwA5AGwMAAAFAE8AbQwAAAIAJwDqDAAABQBTAG4MAAADAD8AFgAICa8anwoAYwIIaAwAAAQAQABpDAAABABRAGsMAAAEAEwAagwAAAMAOQBsDAAABQBPAG0MAAACACcA6gwAAAUAUwBuDAAAAwA/AAAA.',
Lo='Losia:BAAALgAECgMJCQAAAA==.Loveinvain:BAAALgAECgMJAgAAAA==.',
Lu='Lunabun:BAAALgADCgcJEwAAAA==.',
['Lû']='Lûffy:BAAALgAECgkJCQAAAA==.',
Ma='Malorn:BAABLgAECn8gAAQXAAgJlBVtEQDFAQhoDAAABQAvAGkMAAAEAD4AawwAAAUAOgBqDAAABAA4AGwMAAADADcAbQwAAAIANgDqDAAABwA7AG4MAAACADEAFwAICZQVbREAxQEIaAwAAAEALwBpDAAAAQA+AGsMAAABADoAagwAAAEAEgBsDAAAAQA3AG0MAAABADYA6gwAAAIAOwBuDAAAAgAxABgABgntDthDADMBBmgMAAAEABgAaQwAAAMANgBrDAAABAAuAGoMAAADADgAbAwAAAIAEADqDAAABAAxABYAAgloDKhTAFkAAm0MAAABACQA6gwAAAEAGwAAAA==.Manaaddict:BAAALgAECgYJBgAAAA==.',
Mi='Midníght:BAAALgAECgEJAQABLgAECgMJBgACAAAAAA==.',
Mo='Moltencarl:BAAALgAECgEJAgAAAA==.',
My='Myrna:BAAALgAECgMJAwAAAA==.',
Ni='Niege:BAAALgAECgYJCgAAAA==.Niiso:BAAALgAECgMJAwAAAA==.Nivina:BAAALgADCgcJBwAAAA==.',
Nk='Nkagnyto:BAABLgAECn8VAAMYAAUJCBCFNgDRAAVoDAAABgA5AGkMAAAFADcAawwAAAUAFgBqDAAAAgAuAOoMAAADAB0AGAAFCQgQhTYA0QAFaAwAAAUAOQBpDAAABAA3AGsMAAAEABYAagwAAAEAGwDqDAAAAwAdABcABAnHDDBAAJcABGgMAAABAB4AaQwAAAEAMgBrDAAAAQARAGoMAAABAC4AAAA=.Nkanue:BAAALgADCgIJAgABLgAECgUJFQAYAAgQAA==.',
No='Noonstalker:BAAALgAECgUJCwAAAA==.',
Or='Oric:BAAALgADCgMJAwABLgAECgYJEwACAAAAAA==.Orintaar:BAAALgADCgMJAwAAAA==.Ormac:BAAALgAECgYJEwAAAA==.Ororoe:BAABLgAECn8kAAMYAAgJ9xprFABrAghoDAAABgBYAGkMAAAGAFIAawwAAAYAOgBqDAAABABJAGwMAAAEAEQAbQwAAAIASwDqDAAABgA1AG4MAAACADcAGAAICc0aaxQAawIIaAwAAAMAWABpDAAAAwBSAGsMAAADADoAagwAAAEASQBsDAAAAgBEAG0MAAABAEsA6gwAAAMAMwBuDAAAAgA3ABcABwn1EGMeAEcBB2gMAAADADYAaQwAAAMAKgBrDAAAAwArAGoMAAADACIAbAwAAAIAJwBtDAAAAQAZAOoMAAADADUAAAA=.Orphancalf:BAAALgAECgIJAgAAAA==.',
Pa='Palapo:BAAALgAECgMJBwAAAA==.Panrocktar:BAAALgADCgEJAQAAAA==.Paudrig:BAAALgAECgYJDQAAAA==.',
Pe='Perfect:BAAALgAECgQJBgAAAA==.',
Ph='Phagetouched:BAAALgAECgYJBAAAAA==.Phaydre:BAAALgAECgYJEgABLgAFFAUJCwASANgPAA==.',
Pi='Picklenick:BAABLgAECn8dAAIZAAgJbBClEgCdAQhoDAAABQAmAGkMAAAFADoAawwAAAUANgBqDAAAAwAfAGwMAAADACcAbQwAAAEADwDqDAAABQAmAG4MAAACADAAGQAICWwQpRIAnQEIaAwAAAUAJgBpDAAABQA6AGsMAAAFADYAagwAAAMAHwBsDAAAAwAnAG0MAAABAA8A6gwAAAUAJgBuDAAAAgAwAAAA.',
Po='Ponytree:BAAALgAECggJEQAAAA==.Porani:BAAALgAECgEJAQAAAA==.',
Pr='Prismo:BAAALgAECgcJDgAAAA==.',
Pw='Pwnbuggy:BAABLgAECn8dAAIIAAgJpBfFKgDvAQhoDAAABQAoAGkMAAAEAFUAawwAAAQAOwBqDAAAAwA5AGwMAAACACoAbQwAAAIALwDqDAAABwBOAG4MAAACAEYACAAICaQXxSoA7wEIaAwAAAUAKABpDAAABABVAGsMAAAEADsAagwAAAMAOQBsDAAAAgAqAG0MAAACAC8A6gwAAAcATgBuDAAAAgBGAAAA.',
Qa='Qartoga:BAAALgADCgEJAQABLgAECgQJCAACAAAAAA==.',
Ql='Qlue:BAAALgADCgcJBwAAAA==.',
Ra='Rabellious:BAAALgAECgEJAQAAAA==.Rabin:BAAALgADCgIJAgAAAA==.Racistgreen:BAAALgAECgIJAgAAAA==.Raethys:BAAALgADCgUJBQAAAA==.Rafikibull:BAAALgAECgIJBQAAAA==.Raindrop:BAABLgAECn8dAAIMAAgJHRdiJQC9AQhoDAAABQBYAGkMAAAFAD4AawwAAAUARwBqDAAABAAvAGwMAAADADsAbQwAAAIAHgDqDAAABABEAG4MAAABAC0ADAAICR0XYiUAvQEIaAwAAAUAWABpDAAABQA+AGsMAAAFAEcAagwAAAQALwBsDAAAAwA7AG0MAAACAB4A6gwAAAQARABuDAAAAQAtAAAA.Ramah:BAAALgAECgMJCQAAAA==.Ramen:BAAALgADCgEJAQAAAA==.',
Re='Reignstorm:BAABLgAECn8eAAIJAAgJzAsnCgAkAQhoDAAABQAjAGkMAAAFACcAawwAAAUAIwBqDAAABAAUAGwMAAADABsAbQwAAAEAEgDqDAAABQAiAG4MAAACABQACQAICcwLJwoAJAEIaAwAAAUAIwBpDAAABQAnAGsMAAAFACMAagwAAAQAFABsDAAAAwAbAG0MAAABABIA6gwAAAUAIgBuDAAAAgAUAAAA.Reivax:BAABLgAECn8pAAIRAAgJzROxKQDFAQhoDAAABwBGAGkMAAAGAD8AawwAAAYALwBqDAAABQBBAGwMAAAFADIAbQwAAAMAEQDqDAAABgBIAG4MAAADAB8AEQAICc0TsSkAxQEIaAwAAAcARgBpDAAABgA/AGsMAAAGAC8AagwAAAUAQQBsDAAABQAyAG0MAAADABEA6gwAAAYASABuDAAAAwAfAAAA.Rethelm:BAAALgAECgYJEwAAAA==.Retreats:BAAALgADCgUJBQAAAA==.Retsella:BAAALgADCgkJIgAAAA==.Reveum:BAABLgAECn8vAAMVAAgJPgqSHAD2AAhoDAAACgAeAGkMAAAIAB0AawwAAAgAIQBqDAAABgAcAGwMAAAFACEAbQwAAAIAEQDqDAAABgAdAG4MAAACAAkADgAICW0JCBkABAEIaAwAAAQAGQBpDAAABAAbAGsMAAAEABkAagwAAAQADQBsDAAAAwAhAG0MAAACABEA6gwAAAMAHQBuDAAAAgAJABUABglfC5IcAPYABmgMAAAGAB4AaQwAAAQAHQBrDAAABAAhAGoMAAACABwAbAwAAAIAGgDqDAAAAwAZAAAA.Revân:BAAALgADCgMJAwAAAA==.',
Rh='Rhaegár:BAAALgAECgYJDgAAAA==.',
Ro='Robyerto:BAAALgADCgMJAwAAAA==.Rogl:BAACLgAFFH8MAAIMAAUJRCGpBgDuAQVoDAAAAwBRAGkMAAADAFwAawwAAAIAYABqDAAAAQA6AOoMAAADAGEADAAFCUQhqQYA7gEFaAwAAAMAUQBpDAAAAwBcAGsMAAACAGAAagwAAAEAOgDqDAAAAwBhAC4ABAp/HQACDAAHCRsgURwAWgIADAAHCRsgURwAWgIAAAA=.Rosgard:BAAALgADCggJCAAAAA==.',
Ru='Ruffruff:BAAALgAECgkJBgAAAA==.Ruhll:BAAALgAECgEJAQAAAA==.Ruminate:BAAALgADCgYJCgABLgAECgMJBgACAAAAAA==.Rustychi:BAAALgAECgYJDwAAAA==.',
['Rá']='Rámpapi:BAAALgAECgQJDgAAAA==.',
Sa='Sammaile:BAAALgAECgYJEQAAAA==.Sarahsmith:BAAALgAECgYJEwAAAA==.Saucypeach:BAAALgAECgYJDQAAAA==.',
Sc='Scamander:BAABLgAECn8WAAIRAAkJDxYTJgAiAgloDAAAAgA4AGkMAAADADQAawwAAAMATgBqDAAAAgAzAGwMAAACAEkAbQwAAAEANgDqDAAABQA0AG4MAAADADEAbwwAAAEAIQARAAkJDxYTJgAiAgloDAAAAgA4AGkMAAADADQAawwAAAMATgBqDAAAAgAzAGwMAAACAEkAbQwAAAEANgDqDAAABQA0AG4MAAADADEAbwwAAAEAIQAAAA==.Scarmouse:BAAALgAECgEJAQAAAA==.',
Se='Seifer:BAAALgADCgkJJQAAAA==.Semnickmonk:BAAALgAECgMJBAAAAA==.Senjosaku:BAAALgAFFAEJAQABLgAFFAMJCwAEAEEbAA==.Serigo:BAAALgAECgUJDgAAAA==.Serral:BAAALgAFFAEJAQAAAA==.',
Sh='Shaxx:BAAALgADCgEJAQABLgAECgUJDgACAAAAAA==.',
Sk='Skayley:BAAALgADCgUJBQAAAA==.',
Sm='Smoochy:BAAALgAECgEJAQAAAA==.',
So='Solysz:BAAALgAECgYJEwAAAA==.Sophietheone:BAAALgADCgIJAgAAAA==.Soten:BAAALgADCgcJBwABLgAECgMJCQACAAAAAA==.Soß:BAACLgAFFH8KAAIEAAQJBBrgJAAhAQRoDAAAAwBWAGkMAAACAFoAbAwAAAEAAgDqDAAABABWAAQABAkEGuAkACEBBGgMAAADAFYAaQwAAAIAWgBsDAAAAQACAOoMAAAEAFYALgAECn8fAAIEAAcJzyGcUgBAAgAEAAcJzyGcUgBAAgAAAA==.',
Sp='Spongébob:BAAALgAECgIJAgAAAA==.Spork:BAAALgAECgMJBgAAAA==.',
St='Stimcheck:BAAALgADCgcJBwABLgADCggJCAACAAAAAA==.Stmary:BAAALgADCgQJBAAAAA==.Størmzmisery:BAAALgADCgUJBQAAAA==.',
Su='Subzéro:BAABLgAECn8ZAAIEAAYJWAtIhwAXAQZoDAAABgAgAGkMAAAGAB8AawwAAAUAHQBqDAAAAgAaAGwMAAACACcA6gwAAAQADAAEAAYJWAtIhwAXAQZoDAAABgAgAGkMAAAGAB8AawwAAAUAHQBqDAAAAgAaAGwMAAACACcA6gwAAAQADAAAAA==.',
Sw='Sweetwhisper:BAAALgAECgcJEgAAAA==.',
Sy='Sylitae:BAAALgADCgcJHAAAAA==.',
['Så']='Såbëtha:BAAALgADCgMJBQAAAA==.',
Ta='Tazzen:BAAALgAECgQJBQAAAA==.',
Te='Teletern:BAAALgADCgMJBQAAAA==.Tempeststørm:BAAALgAECgUJBwAAAA==.',
Th='Thaunelian:BAAALgAECgQJBAABLgAECggJIAAXAJQVAA==.Thoristain:BAAALgAECgYJEwAAAA==.Thorshman:BAAALgADCgkJCgABLgAECgYJEwACAAAAAA==.Thrain:BAABLgAECn8dAAIBAAgJvws6UwBkAQhoDAAABQAiAGkMAAAEACsAawwAAAUAIABqDAAABAA4AGwMAAADAC0AbQwAAAEAEwDqDAAABgATAG4MAAABAA8AAQAICb8LOlMAZAEIaAwAAAUAIgBpDAAABAArAGsMAAAFACAAagwAAAQAOABsDAAAAwAtAG0MAAABABMA6gwAAAYAEwBuDAAAAQAPAAAA.Threefive:BAAALgAECgQJBQAAAA==.',
To='Torvar:BAAALgADCgEJAgAAAA==.Totemíc:BAAALgAECgQJBQAAAA==.',
Tp='Tpops:BAAALgADCgQJBAAAAA==.',
Tu='Tulku:BAAALgADCgIJBAAAAA==.',
Ty='Tyrdrea:BAAALgADCgkJCQAAAA==.',
Un='Unholypwnage:BAAALgADCgEJAQAAAA==.',
Va='Vallak:BAAALgAECgQJBAAAAA==.',
Ve='Velarion:BAAALgAECgEJAQAAAA==.Veryundead:BAABLgAECn8rAAIUAAgJdBLiBgCPAQhoDAAACABCAGkMAAAHAEIAawwAAAcAKwBqDAAABgAtAGwMAAAFACwAbQwAAAIAFADqDAAABwA4AG4MAAABACEAFAAICXQS4gYAjwEIaAwAAAgAQgBpDAAABwBCAGsMAAAHACsAagwAAAYALQBsDAAABQAsAG0MAAACABQA6gwAAAcAOABuDAAAAQAhAAAA.',
Vo='Void:BAABLgAECn8VAAIQAAYJwBftFQBWAQZoDAAABQBBAGkMAAAFAD0AawwAAAUAOABqDAAAAgBTAGwMAAACAEUA6gwAAAIAMgAQAAYJwBftFQBWAQZoDAAABQBBAGkMAAAFAD0AawwAAAUAOABqDAAAAgBTAGwMAAACAEUA6gwAAAIAMgAAAA==.Voidmara:BAAALgAECgEJAwAAAA==.Voíd:BAAALgAECgEJAQAAAA==.',
Vr='Vrylykos:BAAALgAECgYJCgAAAA==.',
Wa='Waddlez:BAAALgAECgEJAQAAAA==.Wardawg:BAAALgADCgEJAQABLgAECggJIQAFACQjAA==.Wargrylls:BAAALgADCgcJBwAAAA==.',
We='Wendrin:BAAALgAECgYJBgAAAA==.',
Wh='White:BAAALgAECgQJBQAAAA==.',
Wo='Wolvynlyfe:BAAALgADCgIJAgAAAA==.',
Xa='Xanarine:BAABLgAECn8VAAMLAAYJhRQvRABnAQZoDAAABgBCAGkMAAAGAEcAawwAAAUANABqDAAAAQASAGwMAAABACAA6gwAAAIASQALAAYJhRQvRABnAQZoDAAABQBCAGkMAAAFAEcAawwAAAUANABqDAAAAQASAGwMAAABACAA6gwAAAIASQABAAIJtQdHIQFbAAJoDAAAAQAbAGkMAAABAAsAAAA=.Xavíous:BAAALgADCgYJBgAAAA==.',
Xe='Xeeva:BAABLgAECn8VAAIaAAUJXxf3NQBVAQVoDAAABgAyAGkMAAAFAFUAawwAAAUAOgBqDAAAAgBGAOoMAAADACEAGgAFCV8X9zUAVQEFaAwAAAYAMgBpDAAABQBVAGsMAAAFADoAagwAAAIARgDqDAAAAwAhAAAA.',
Xu='Xuralxia:BAAALgAECgEJBgAAAA==.',
Zi='Zink:BAAALgAECgEJAQAAAA==.Ziyad:BAABLgAECn8XAAQDAAgJMBIbGQCNAQhoDAAABAAyAGkMAAAEADcAawwAAAQANABqDAAAAwAvAGwMAAACACYAbQwAAAEAJQDqDAAABABAAG4MAAABABoAAwAICRIQGxkAjQEIaAwAAAMALQBpDAAAAwAWAGsMAAADADQAagwAAAMALwBsDAAAAgAmAG0MAAABACUA6gwAAAMAQABuDAAAAQAaAA0AAwnDEwghAJYAA2gMAAABADIAaQwAAAEANwBrDAAAAQAtAAwAAQmIASXqABoAAeoMAAABAAMAAAA=.',
Zy='Zyn:BAAALgAECgMJAwAAAA==.',
['Zè']='Zèró:BAABLgAECn8VAAMbAAYJnByODgBpAQZoDAAABABhAGkMAAAFAEAAawwAAAUAPgBqDAAAAgBGAGwMAAACAEIA6gwAAAMASgAbAAYJnByODgBpAQZoDAAABABhAGkMAAAEAEAAawwAAAQAPgBqDAAAAgBGAGwMAAACAEIA6gwAAAMASgABAAIJPxAh0AB8AAJpDAAAAQAvAGsMAAABACQAAAA=.',
['Ðü']='Ðüß:BAAALgADCgIJAgABLgAECgMJAwACAAAAAA==.',
['Ön']='Öna:BAABLgAECn8qAAIRAAgJERYtLAC5AQhoDAAACABQAGkMAAAHAEUAawwAAAcARQBqDAAABgBPAGwMAAAEADQAbQwAAAEAHwDqDAAACABLAG4MAAABAA8AEQAICREWLSwAuQEIaAwAAAgAUABpDAAABwBFAGsMAAAHAEUAagwAAAYATwBsDAAABAA0AG0MAAABAB8A6gwAAAgASwBuDAAAAQAPAAAA.',
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
