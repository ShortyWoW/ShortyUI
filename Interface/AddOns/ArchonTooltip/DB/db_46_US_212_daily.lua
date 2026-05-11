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

local lookup = {'Paladin-Retribution','Unknown-Unknown','Druid-Balance','Mage-Frost','Priest-Discipline','Priest-Holy','Priest-Shadow','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Paladin-Holy','Druid-Restoration','Druid-Guardian','Warrior-Protection','DemonHunter-Devourer','DemonHunter-Havoc','Hunter-BeastMastery','Evoker-Preservation','Hunter-Marksmanship','Warlock-Destruction','Warrior-Arms','Monk-Mistweaver','Monk-Windwalker','Monk-Brewmaster','Rogue-Subtlety','Shaman-Restoration',}
local provider = {region='US',realm='Terokkar',name='US',type='daily',zone=46,date='2026-05-10',data={Ab='Abuna:BAABLgAECn8dAAIBAAgJAhP5QQCJAQhoDAAABQAoAGkMAAAFADkAawwAAAUAMQBqDAAABABFAGwMAAADAD0AbQwAAAEAIgDqDAAABQA+AG4MAAABACMAAQAICQIT+UEAiQEIaAwAAAUAKABpDAAABQA5AGsMAAAFADEAagwAAAQARQBsDAAAAwA9AG0MAAABACIA6gwAAAUAPgBuDAAAAQAjAAAA.',
Ad='Adreni:BAAALgADCgUJBQAAAA==.',
Ae='Aelzia:BAAALgAECgEJAgAAAA==.Aennivan:BAAALgADCgcJBwABLgAECgMJBwACAAAAAA==.Aestia:BAAALgAECgMJAwAAAA==.',
Al='Alfarin:BAAALgAECgEJAQAAAA==.Aljern:BAAALgADCgEJAgAAAA==.Alpha:BAAALgAECgYJBwAAAA==.Alysra:BAAALgADCgUJBQABLgAFFAYJFwADAF0hAA==.',
Am='Ammogal:BAAALgAECgQJBAAAAA==.',
An='Andyson:BAAALgAECgMJBQAAAA==.Antandra:BAAALgAECgYJEwAAAA==.Anwen:BAABLgAECn8ZAAIEAAgJMRWzMgDeAQhoDAAAAwAxAGkMAAADAE0AawwAAAMALgBqDAAABAAzAGwMAAADAD4AbQwAAAIAJADqDAAABQA/AG4MAAACACsABAAICTEVszIA3gEIaAwAAAMAMQBpDAAAAwBNAGsMAAADAC4AagwAAAQAMwBsDAAAAwA+AG0MAAACACQA6gwAAAUAPwBuDAAAAgArAAAA.',
Ar='Arawen:BAAALgAECgQJBgABLgAECggJGQAEADEVAA==.',
Av='Avadrea:BAAALgADCgEJAQAAAA==.Aválánche:BAAALgADCgEJAQAAAA==.',
Ay='Ayanea:BAABLgAECn8hAAQFAAgJJCORBgCVAghoDAAABQBcAGkMAAAFAF4AawwAAAUAXQBqDAAABABeAGwMAAAEAFwAbQwAAAIAWgDqDAAABQBQAG4MAAADAFIABQAICechkQYAlQIIaAwAAAQAXABpDAAAAwBOAGsMAAADAFQAagwAAAMAXgBsDAAABABcAG0MAAACAFoA6gwAAAUAUABuDAAAAwBSAAYAAgm8JHJbAMYAAmkMAAABAF4AawwAAAEAXQAHAAQJTw8DOAC3AARoDAAAAQAdAGkMAAABADoAawwAAAEAHQBqDAAAAQAtAAAA.Aysá:BAAALgADCgMJBQAAAA==.',
Ba='Baberaham:BAABLgAECn8ZAAQIAAcJ8QKligDYAAdoDAAABgAJAGkMAAAHAAwAawwAAAQABgBqDAAAAgAOAGwMAAABAAYAbQwAAAEABQDqDAAABAAEAAgABwnxAqWKANgAB2gMAAAFAAkAaQwAAAQADABrDAAABAAGAGoMAAACAA4AbAwAAAEABgBtDAAAAQAFAOoMAAADAAQACQADCXEBVRYAOAADaAwAAAEAAgBpDAAAAgADAOoMAAABAAQACgABCYQEkz0AKAABaQwAAAEACwAAAA==.Baiford:BAABLgAECn8ZAAMLAAgJXg/1SgBMAQhoDAAABQA5AGkMAAAEACIAawwAAAQAFgBqDAAAAwAxAGwMAAABABsAbQwAAAIAHQDqDAAABQBHAG4MAAABABQACwAICV4P9UoATAEIaAwAAAMAOQBpDAAAAwAiAGsMAAADABYAagwAAAMAMQBsDAAAAQAbAG0MAAACAB0A6gwAAAUARwBuDAAAAQAUAAEAAwnyC8WvAKMAA2gMAAACACsAaQwAAAEAHgBrDAAAAQAQAAAA.Baldie:BAAALgADCgEJAQAAAA==.Batteries:BAAALgAECgEJAQAAAA==.',
Be='Bearitto:BAABLgAECn8uAAIMAAgJsiD9CQC0AghoDAAACABgAGkMAAAHAFAAawwAAAgAWgBqDAAABwBXAGwMAAAGAFgAbQwAAAIAYQDqDAAABgBUAG4MAAACAC0ADAAICbIg/QkAtAIIaAwAAAgAYABpDAAABwBQAGsMAAAIAFoAagwAAAcAVwBsDAAABgBYAG0MAAACAGEA6gwAAAYAVABuDAAAAgAtAAAA.',
Bi='Bigpony:BAAALgADCgYJCAAAAA==.',
Bl='Bloodrain:BAAALgADCgYJBgAAAA==.',
Bo='Bobsan:BAAALgAECgQJBAAAAA==.',
Br='Breyvarian:BAAALgADCgUJBQAAAA==.Broland:BAAALgAECgYJEgAAAA==.',
Bu='Burningvoker:BAAALgADCgYJBgAAAA==.',
Ca='Caitycat:BAABLgAECn8XAAIMAAgJdxV+GwD0AQhoDAAABABMAGkMAAAEAEEAawwAAAQAOABqDAAAAwA/AGwMAAACACoAbQwAAAEALQDqDAAABABIAG4MAAABABEADAAICXcVfhsA9AEIaAwAAAQATABpDAAABABBAGsMAAAEADgAagwAAAMAPwBsDAAAAgAqAG0MAAABAC0A6gwAAAQASABuDAAAAQARAAAA.Calliopê:BAAALgAECgYJEQAAAA==.Candycane:BAAALgADCgQJBAAAAA==.Carabina:BAAALgADCgIJAgAAAA==.Casseopea:BAAALgADCgYJCQABLgAECgMJCQACAAAAAA==.Catherinn:BAAALgAECgUJBQAAAA==.Cattlock:BAAALgAECgQJCwAAAA==.',
Ch='Chaltin:BAAALgAECgMJAwAAAA==.Chillhunt:BAAALgADCgIJAgAAAA==.',
Co='Coldhand:BAAALgAECgkJBgAAAA==.Colë:BAABLgAECn8aAAINAAgJFxQECgCRAQhoDAAABAAoAGkMAAAEADsAawwAAAQAQgBqDAAABAA7AGwMAAADADkAbQwAAAEAIgDqDAAABQA9AG4MAAABACYADQAICRcUBAoAkQEIaAwAAAQAKABpDAAABAA7AGsMAAAEAEIAagwAAAQAOwBsDAAAAwA5AG0MAAABACIA6gwAAAUAPQBuDAAAAQAmAAAA.',
['Cæ']='Cærus:BAAALgAECgYJBgABLgAFFAYJDwAHAD4VAA==.',
Da='Daedrina:BAAALgADCgMJAwAAAA==.Dalkrim:BAABLgAECn8dAAIKAAgJJhzdCQDqAQhoDAAABQBfAGkMAAAFAFIAawwAAAUATQBqDAAABABHAGwMAAADAEkAbQwAAAEAJQDqDAAABQBWAG4MAAABADMACgAICSYc3QkA6gEIaAwAAAUAXwBpDAAABQBSAGsMAAAFAE0AagwAAAQARwBsDAAAAwBJAG0MAAABACUA6gwAAAUAVgBuDAAAAQAzAAAA.',
De='Deadblanchy:BAAALgADCgIJAgAAAA==.Debboi:BAAALgADCgUJBQAAAA==.Denzel:BAAALgAECgYJBQAAAA==.Derrick:BAAALgAECgYJEQAAAA==.Desol:BAAALgADCgEJAQAAAA==.Destrya:BAABLgAECn8hAAIOAAgJMSAyBAB6AghoDAAABQBYAGkMAAAFAFUAawwAAAUAUABqDAAABAA3AGwMAAAEAFQAbQwAAAIARwDqDAAABQBdAG4MAAADAEkADgAICTEgMgQAegIIaAwAAAUAWABpDAAABQBVAGsMAAAFAFAAagwAAAQANwBsDAAABABUAG0MAAACAEcA6gwAAAUAXQBuDAAAAwBJAAAA.',
Di='Diamondhoof:BAAALgADCgYJBgAAAA==.Dibbsette:BAABLgAECn8eAAMFAAgJvxwEGADdAQhoDAAABQBQAGkMAAAFAFAAawwAAAUARABqDAAABABHAGwMAAADAEIAbQwAAAEATADqDAAABgBMAG4MAAABAEQABQAICb8cBBgA3QEIaAwAAAQAUABpDAAABABQAGsMAAAEAEQAagwAAAMARwBsDAAAAgBCAG0MAAABAEwA6gwAAAUATABuDAAAAQBEAAcABglBDbkjADEBBmgMAAABABoAaQwAAAEAKABrDAAAAQAhAGoMAAABADsAbAwAAAEAEwDqDAAAAQAyAAAA.',
Do='Douber:BAAALgADCgYJCAAAAA==.',
Dr='Drosera:BAAALgADCgYJBgAAAA==.',
Ds='Dshiznit:BAAALgAECgEJAQABLgAECgYJEQACAAAAAA==.',
Dw='Dwamli:BAAALgAECgMJCwAAAA==.',
Dy='Dynamitedave:BAAALgAECgUJDAABLgAECgYJDwACAAAAAA==.',
['Dø']='Dømino:BAAALgAECgQJEAAAAA==.',
Eb='Ebolabeef:BAABLgAECn8gAAIIAAgJPCULCQDXAghoDAAABQBcAGkMAAAFAGEAawwAAAUAXgBqDAAAAwBZAGwMAAAEAGAAbQwAAAIAWgDqDAAABQBhAG4MAAADAGMACAAICTwlCwkA1wIIaAwAAAUAXABpDAAABQBhAGsMAAAFAF4AagwAAAMAWQBsDAAABABgAG0MAAACAFoA6gwAAAUAYQBuDAAAAwBjAAAA.',
Ei='Eirlys:BAAALgAECgYJEAAAAA==.',
El='Elky:BAAALgADCgkJHAABLgAECgMJBgACAAAAAA==.Elìyon:BAABLgAECn8mAAMPAAgJYA0sPwBFAQhoDAAABgAkAGkMAAAGACUAawwAAAYAMABqDAAABQA0AGwMAAAEACkAbQwAAAIAFgDqDAAABgAZAG4MAAADABwADwAICWANLD8ARQEIaAwAAAYAJABpDAAABgAlAGsMAAAGADAAagwAAAUANABsDAAABAApAG0MAAACABYA6gwAAAUAGQBuDAAAAwAcABAAAQmhAS99ACIAAeoMAAABAAQAAAA=.',
Es='Espyvon:BAAALgADCgQJBAAAAA==.',
Et='Eternalay:BAAALgAECgYJBwAAAA==.Eternshot:BAAALgADCgEJAQAAAA==.Eternsword:BAAALgADCgYJBgAAAA==.',
Ev='Evelanara:BAAALgADCgUJBQAAAA==.Evelinnia:BAAALgADCgMJAwAAAA==.Evilmurkii:BAAALgAECgEJBgABLgAECgYJEAACAAAAAA==.Evilssoul:BAAALgAECgQJBAAAAA==.',
Fe='Feltsmer:BAAALgADCgYJCQAAAA==.Fenira:BAAALgADCgUJBQAAAA==.Ferguz:BAABLgAECn8YAAIRAAcJ2hsBJwC6AQdoDAAABABRAGkMAAAEAFAAawwAAAQAWQBqDAAABABKAGwMAAADADwAbQwAAAEAMQDqDAAABABCABEABwnaGwEnALoBB2gMAAAEAFEAaQwAAAQAUABrDAAABABZAGoMAAAEAEoAbAwAAAMAPABtDAAAAQAxAOoMAAAEAEIAAAA=.',
Fo='Foscora:BAAALgAECgEJAQAAAA==.',
Fr='Frushy:BAAALgADCgcJBwAAAA==.',
Fu='Fugu:BAAALgADCggJEQAAAA==.',
Ga='Gannicûs:BAAALgAECgEJAQAAAA==.Garlando:BAAALgAECgEJAQAAAA==.',
Go='Goatmommy:BAAALgAECgQJDgAAAA==.Goph:BAAALgADCgMJBQAAAA==.Goremnar:BAAALgADCgYJBgAAAA==.',
Gr='Grimmfury:BAAALgAECgMJCQAAAA==.Grimmtide:BAAALgADCgYJBgAAAA==.Grolgor:BAAALgADCgQJBAAAAA==.Grïffïth:BAACLgAFFH8cAAMBAAcJPxpgAwC/AQdoDAAABgBcAGkMAAAEAFkAawwAAAUALgBqDAAABABCAGwMAAADAGAAbQwAAAEADQDqDAAABQBBAAEABgn3F2ADAL8BBmgMAAAGAFwAaQwAAAQAWQBrDAAABQAuAGoMAAAEAEIAbQwAAAEADQDqDAAABQBBAAsAAQnYAL8cAEYAAWwMAAADAAIALgAECn8rAAMBAAkJjSEZDwAVAwABAAkJjSEZDwAVAwALAAYJSw9oRwBaAQAAAA==.',
Gu='Gunjir:BAAALgAECgMJCQAAAA==.',
Gw='Gwyneira:BAAALgAECgYJCgABLgAECgYJEAACAAAAAA==.',
Ha='Haranbush:BAAALgADCgYJBgAAAA==.',
Hi='Hipidipi:BAAALgADCgUJBQAAAA==.',
Ho='Honeysuckles:BAAALgAECgEJAQAAAA==.',
Hu='Hucklebeary:BAAALgAECgQJBgAAAA==.Hugcubs:BAAALgADCgUJBQAAAA==.',
['Hí']='Hítgirl:BAAALgAECgQJCAAAAA==.',
Ic='Icylilith:BAAALgADCgYJCQAAAA==.',
Im='Imugi:BAABLgAECn8dAAISAAgJcgeaEQAuAQhoDAAABQAlAGkMAAAFAAoAawwAAAUADgBqDAAABAAiAGwMAAADABIAbQwAAAEADgDqDAAABQASAG4MAAABAAQAEgAICXIHmhEALgEIaAwAAAUAJQBpDAAABQAKAGsMAAAFAA4AagwAAAQAIgBsDAAAAwASAG0MAAABAA4A6gwAAAUAEgBuDAAAAQAEAAAA.',
Ir='Irithia:BAAALgADCgEJAQAAAA==.',
Is='Ishamael:BAAALgADCgcJBwABLgAECgYJEQACAAAAAA==.Issavanos:BAAALgAECgYJEAAAAA==.',
Ja='Jazmane:BAAALgADCgYJBgAAAA==.',
Je='Jenhoney:BAAALgAECgMJCQAAAA==.Jes:BAAALgADCgEJAQAAAA==.Jessdarklord:BAAALgAECgQJAwAAAA==.',
Jo='Josh:BAAALgAECgYJCQABLgAFFAYJDAATAOcTAA==.',
Ka='Kaliya:BAAALgAECgQJCQAAAA==.Kashar:BAAALgADCgMJAwAAAA==.',
Ke='Kevdog:BAABLgAECn8dAAIUAAgJMRDWBgCIAQhoDAAABQAnAGkMAAAFADIAawwAAAUAQABqDAAABAAqAGwMAAADACoAbQwAAAEAEADqDAAABQA1AG4MAAABABcAFAAICTEQ1gYAiAEIaAwAAAUAJwBpDAAABQAyAGsMAAAFAEAAagwAAAQAKgBsDAAAAwAqAG0MAAABABAA6gwAAAUANQBuDAAAAQAXAAAA.',
Kh='Khelemarth:BAAALgAECgEJBAAAAA==.',
Ki='Kire:BAABLgAECn8ZAAMOAAgJ1R80BAB6AghoDAAAAwA1AGkMAAADAF4AawwAAAMAUQBqDAAABABVAGwMAAAEAF8AbQwAAAIAQgDqDAAABABbAG4MAAACAFYADgAICdUfNAQAegIIaAwAAAMANQBpDAAAAwBeAGsMAAADAFEAagwAAAQAVQBsDAAABABfAG0MAAACAEIA6gwAAAMAWwBuDAAAAgBWABUAAQnRDsxAADcAAeoMAAABACUAAAA=.Kirohan:BAAALgADCgcJCgAAAA==.',
Ko='Kobellr:BAAALgADCgUJBQAAAA==.Koldov:BAAALgAECgEJAQAAAA==.Kosmik:BAAALgADCgcJCwAAAA==.',
Kr='Krimzin:BAAALgAECgEJAQABLgAFFAQJDAARAHIbAA==.',
Ku='Kuiu:BAAALgADCgEJAQAAAA==.Kulnurayne:BAAALgADCgcJDAAAAA==.Kuna:BAAALgAECgQJCAAAAA==.Kushta:BAABLgAECn8YAAIBAAgJix0MGQDTAghoDAAABgBVAGkMAAAEAGEAawwAAAQATQBqDAAAAwBeAGwMAAADAFYAbQwAAAEADwDqDAAAAQBKAG4MAAACAFsAAQAICYsdDBkA0wIIaAwAAAYAVQBpDAAABABhAGsMAAAEAE0AagwAAAMAXgBsDAAAAwBWAG0MAAABAA8A6gwAAAEASgBuDAAAAgBbAAAA.',
La='Lackjaw:BAABLgAECn8aAAIUAAgJUA73EQC8AQhoDAAAAwAiAGkMAAAEACwAawwAAAUAJABqDAAABAAiAGwMAAAEADAAbQwAAAIAFQDqDAAAAgAmAG4MAAACACAAFAAICVAO9xEAvAEIaAwAAAMAIgBpDAAABAAsAGsMAAAFACQAagwAAAQAIgBsDAAABAAwAG0MAAACABUA6gwAAAIAJgBuDAAAAgAgAAAA.Landrick:BAACLgAFFH8IAAIKAAMJ+gr8FQCwAANoDAAABAAVAGkMAAADADAA6gwAAAEADgAKAAMJ+gr8FQCwAANoDAAABAAVAGkMAAADADAA6gwAAAEADgAuAAQKfzEAAgoACQlIGgUGAE0CAAoACQlIGgUGAE0CAAAA.Lanejack:BAAALgADCgQJBwAAAA==.Larissah:BAEALgADCgUJAgABLgAECgkJEwACAAAAAA==.Lava:BAAALgAECggJDwAAAA==.',
Lg='Lgang:BAABLgAECn8VAAIQAAYJ5gqGPAANAQZoDAAABgAsAGkMAAAGAB4AawwAAAUAHQBqDAAAAQAFAGwMAAABABMA6gwAAAIADwAQAAYJ5gqGPAANAQZoDAAABgAsAGkMAAAGAB4AawwAAAUAHQBqDAAAAQAFAGwMAAABABMA6gwAAAIADwAAAA==.',
Li='Lifeblõõm:BAABLgAECn8UAAMMAAcJUSG9DQB/AgdoDAAAAwBfAGkMAAADAFwAawwAAAMAWwBqDAAABABZAGwMAAADAEkA6gwAAAMAWABuDAAAAQBDAAwABwlRIb0NAH8CB2gMAAADAF8AaQwAAAMAXABrDAAAAwBbAGoMAAADAFkAbAwAAAIASQDqDAAAAwBYAG4MAAABAEMAAwACCYwOeVoANgACagwAAAEANwBsDAAAAQAlAAAA.Lilium:BAAALgAECgYJBgAAAA==.',
Ll='Llau:BAABLgAECn8eAAIWAAgJrxoyCQBoAghoDAAABABAAGkMAAAEAFEAawwAAAQATABqDAAAAwA5AGwMAAAFAE8AbQwAAAIAJwDqDAAABQBTAG4MAAADAD8AFgAICa8aMgkAaAIIaAwAAAQAQABpDAAABABRAGsMAAAEAEwAagwAAAMAOQBsDAAABQBPAG0MAAACACcA6gwAAAUAUwBuDAAAAwA/AAAA.',
Lo='Losia:BAAALgAECgMJCQAAAA==.Loveinvain:BAAALgAECgMJAgAAAA==.',
Lu='Lunabun:BAAALgADCgcJEwAAAA==.',
['Lû']='Lûffy:BAAALgAECgkJCQAAAA==.',
Ma='Malorn:BAABLgAECn8gAAQXAAgJlBW1DwDLAQhoDAAABQAvAGkMAAAEAD4AawwAAAUAOgBqDAAABAA4AGwMAAADADcAbQwAAAIANgDqDAAABwA7AG4MAAACADEAFwAICZQVtQ8AywEIaAwAAAEALwBpDAAAAQA+AGsMAAABADoAagwAAAEAEgBsDAAAAQA3AG0MAAABADYA6gwAAAIAOwBuDAAAAgAxABgABgntDtlDADMBBmgMAAAEABgAaQwAAAMANgBrDAAABAAuAGoMAAADADgAbAwAAAIAEADqDAAABAAxABYAAgloDHxMAFsAAm0MAAABACQA6gwAAAEAGwAAAA==.Manaaddict:BAAALgAECgYJBgAAAA==.',
Mi='Midníght:BAAALgAECgEJAQABLgAECgMJBgACAAAAAA==.',
Mo='Moltencarl:BAAALgAECgEJAgAAAA==.',
My='Myrna:BAAALgAECgMJAwAAAA==.',
Ni='Niege:BAAALgAECgYJCgAAAA==.Niiso:BAAALgAECgMJAwAAAA==.Nivina:BAAALgADCgcJBwAAAA==.',
Nk='Nkagnyto:BAABLgAECn8VAAMYAAUJCBBvMwDTAAVoDAAABgA5AGkMAAAFADcAawwAAAUAFgBqDAAAAgAuAOoMAAADAB0AGAAFCQgQbzMA0wAFaAwAAAUAOQBpDAAABAA3AGsMAAAEABYAagwAAAEAGwDqDAAAAwAdABcABAnHDAAAAAAABGgMAAABAB4AaQwAAAEAMgBrDAAAAQARAGoMAAABAC4AAAA=.Nkanue:BAAALgADCgIJAgABLgAECgUJFQAYAAgQAA==.',
No='Noonstalker:BAAALgAECgUJCwAAAA==.',
Or='Oric:BAAALgADCgMJAwABLgAECgYJEQACAAAAAA==.Orintaar:BAAALgADCgMJAwAAAA==.Ormac:BAAALgAECgYJEwAAAA==.Ororoe:BAABLgAECn8kAAMYAAgJ9xprFABrAghoDAAABgBYAGkMAAAGAFIAawwAAAYAOgBqDAAABABJAGwMAAAEAEQAbQwAAAIASwDqDAAABgA1AG4MAAACADcAGAAICc0aaxQAawIIaAwAAAMAWABpDAAAAwBSAGsMAAADADoAagwAAAEASQBsDAAAAgBEAG0MAAABAEsA6gwAAAMAMwBuDAAAAgA3ABcABwn1EI0bAFEBB2gMAAADADYAaQwAAAMAKgBrDAAAAwArAGoMAAADACIAbAwAAAIAJwBtDAAAAQAZAOoMAAADADUAAAA=.Orphancalf:BAAALgAECgIJAgAAAA==.',
Pa='Palapo:BAAALgAECgMJBwAAAA==.Panrocktar:BAAALgADCgEJAQAAAA==.Paudrig:BAAALgAECgYJDQAAAA==.',
Pe='Perfect:BAAALgAECgQJBgAAAA==.',
Ph='Phagetouched:BAAALgAECgUJAwAAAA==.Phaydre:BAAALgAECgYJEgABLgAFFAUJCgASANgPAA==.',
Pi='Picklenick:BAABLgAECn8cAAIZAAgJbBCmEACmAQhoDAAABQAmAGkMAAAFADoAawwAAAUANgBqDAAAAwAfAGwMAAADACcAbQwAAAEADwDqDAAABQAmAG4MAAABADAAGQAICWwQphAApgEIaAwAAAUAJgBpDAAABQA6AGsMAAAFADYAagwAAAMAHwBsDAAAAwAnAG0MAAABAA8A6gwAAAUAJgBuDAAAAQAwAAAA.',
Po='Ponytree:BAAALgAECggJEQAAAA==.Porani:BAAALgAECgEJAQAAAA==.',
Pr='Prismo:BAAALgAECgcJDgAAAA==.',
Pw='Pwnbuggy:BAABLgAECn8dAAIIAAgJpBdDJgD0AQhoDAAABQAoAGkMAAAEAFUAawwAAAQAOwBqDAAAAwA5AGwMAAACACoAbQwAAAIALwDqDAAABwBOAG4MAAACAEYACAAICaQXQyYA9AEIaAwAAAUAKABpDAAABABVAGsMAAAEADsAagwAAAMAOQBsDAAAAgAqAG0MAAACAC8A6gwAAAcATgBuDAAAAgBGAAAA.',
Qa='Qartoga:BAAALgADCgEJAQABLgAECgQJCAACAAAAAA==.',
Ql='Qlue:BAAALgADCgcJBwAAAA==.',
Ra='Rabellious:BAAALgAECgEJAQAAAA==.Rabin:BAAALgADCgIJAgAAAA==.Racistgreen:BAAALgAECgIJAgAAAA==.Rafikibull:BAAALgAECgIJBQAAAA==.Raindrop:BAABLgAECn8dAAIMAAgJHRfXIgC9AQhoDAAABQBYAGkMAAAFAD4AawwAAAUARwBqDAAABAAvAGwMAAADADsAbQwAAAIAHgDqDAAABABEAG4MAAABAC0ADAAICR0X1yIAvQEIaAwAAAUAWABpDAAABQA+AGsMAAAFAEcAagwAAAQALwBsDAAAAwA7AG0MAAACAB4A6gwAAAQARABuDAAAAQAtAAAA.Ramah:BAAALgAECgMJCQAAAA==.Ramen:BAAALgADCgEJAQAAAA==.',
Re='Reignstorm:BAABLgAECn8dAAIJAAgJzAuiCAAmAQhoDAAABQAjAGkMAAAFACcAawwAAAUAIwBqDAAABAAUAGwMAAADABsAbQwAAAEAEgDqDAAABQAiAG4MAAABABQACQAICcwLoggAJgEIaAwAAAUAIwBpDAAABQAnAGsMAAAFACMAagwAAAQAFABsDAAAAwAbAG0MAAABABIA6gwAAAUAIgBuDAAAAQAUAAAA.Reivax:BAABLgAECn8nAAIRAAgJ3RMfLgD6AQhoDAAABwBGAGkMAAAGAD8AawwAAAYAMABqDAAABQBBAGwMAAAEADIAbQwAAAIAEQDqDAAABgBJAG4MAAADAB8AEQAICd0THy4A+gEIaAwAAAcARgBpDAAABgA/AGsMAAAGADAAagwAAAUAQQBsDAAABAAyAG0MAAACABEA6gwAAAYASQBuDAAAAwAfAAAA.Rethelm:BAAALgAECgYJEwAAAA==.Retreats:BAAALgADCgUJBQAAAA==.Retsella:BAAALgADCgkJIgAAAA==.Reveum:BAABLgAECn8vAAMVAAgJPgq7GQD3AAhoDAAACgAeAGkMAAAIAB0AawwAAAgAIQBqDAAABgAcAGwMAAAFACEAbQwAAAIAEQDqDAAABgAdAG4MAAACAAkADgAICW0JBBcADgEIaAwAAAQAGQBpDAAABAAbAGsMAAAEABkAagwAAAQADQBsDAAAAwAhAG0MAAACABEA6gwAAAMAHQBuDAAAAgAJABUABglfC7sZAPcABmgMAAAGAB4AaQwAAAQAHQBrDAAABAAhAGoMAAACABwAbAwAAAIAGgDqDAAAAwAZAAAA.Revân:BAAALgADCgMJAwAAAA==.',
Rh='Rhaegár:BAAALgAECgQJCQAAAA==.',
Ro='Robyerto:BAAALgADCgMJAwAAAA==.Rogl:BAACLgAFFH8MAAIMAAUJRCGbBQDuAQVoDAAAAwBRAGkMAAADAFwAawwAAAIAYABqDAAAAQA6AOoMAAADAGEADAAFCUQhmwUA7gEFaAwAAAMAUQBpDAAAAwBcAGsMAAACAGAAagwAAAEAOgDqDAAAAwBhAC4ABAp/HQACDAAHCRsgUBwAWgIADAAHCRsgUBwAWgIAAAA=.Rosgard:BAAALgADCggJCAAAAA==.',
Ru='Ruhll:BAAALgADCgcJCQAAAA==.Ruminate:BAAALgADCgYJCgABLgAECgMJBgACAAAAAA==.Rustychi:BAAALgAECgYJCQAAAA==.',
['Rá']='Rámpapi:BAAALgAECgQJDgAAAA==.',
Sa='Sammaile:BAAALgAECgYJEQAAAA==.Sarahsmith:BAAALgAECgYJEQAAAA==.Saucypeach:BAAALgAECgYJDQAAAA==.',
Sc='Scamander:BAABLgAECn8WAAIRAAkJDxYTJgAiAgloDAAAAgA4AGkMAAADADQAawwAAAMATgBqDAAAAgAzAGwMAAACAEkAbQwAAAEANgDqDAAABQA0AG4MAAADADEAbwwAAAEAIQARAAkJDxYTJgAiAgloDAAAAgA4AGkMAAADADQAawwAAAMATgBqDAAAAgAzAGwMAAACAEkAbQwAAAEANgDqDAAABQA0AG4MAAADADEAbwwAAAEAIQAAAA==.Scarmouse:BAAALgAECgEJAQAAAA==.',
Se='Seifer:BAAALgADCgkJJQAAAA==.Semnickmonk:BAAALgAECgMJBAAAAA==.Senjosaku:BAAALgAFFAEJAQABLgAFFAMJCQAEAEEbAA==.Serigo:BAAALgAECgUJDgAAAA==.Serral:BAAALgAFFAEJAQAAAA==.',
Sk='Skayley:BAAALgADCgUJBQAAAA==.',
Sm='Smoochy:BAAALgAECgEJAQAAAA==.',
So='Solysz:BAAALgAECgYJEwAAAA==.Sophietheone:BAAALgADCgIJAgAAAA==.Soten:BAAALgADCgcJBwABLgAECgMJCQACAAAAAA==.Soß:BAACLgAFFH8KAAIEAAQJBBrbJAAhAQRoDAAAAwBWAGkMAAACAFoAbAwAAAEAAgDqDAAABABWAAQABAkEGtskACEBBGgMAAADAFYAaQwAAAIAWgBsDAAAAQACAOoMAAAEAFYALgAECn8fAAIEAAcJzyGZUgBAAgAEAAcJzyGZUgBAAgAAAA==.',
Sp='Spongébob:BAAALgAECgIJAgAAAA==.Spork:BAAALgAECgMJBgAAAA==.',
St='Stimcheck:BAAALgADCgcJBwABLgADCggJCAACAAAAAA==.Stmary:BAAALgADCgQJBAAAAA==.Størmzmisery:BAAALgADCgUJBQAAAA==.',
Su='Subzéro:BAABLgAECn8YAAIEAAYJuAnKhAAQAQZoDAAABgAgAGkMAAAGAB8AawwAAAUAHQBqDAAAAgAaAGwMAAABABIA6gwAAAQADAAEAAYJuAnKhAAQAQZoDAAABgAgAGkMAAAGAB8AawwAAAUAHQBqDAAAAgAaAGwMAAABABIA6gwAAAQADAAAAA==.',
Sw='Sweetwhisper:BAAALgAECgYJEQAAAA==.',
Sy='Sylitae:BAAALgADCgcJHAAAAA==.',
['Så']='Såbëtha:BAAALgADCgMJBQAAAA==.',
Ta='Tazzen:BAAALgAECgQJBQAAAA==.',
Te='Teletern:BAAALgADCgMJBQAAAA==.Tempeststørm:BAAALgAECgUJBwAAAA==.',
Th='Thaunelian:BAAALgAECgQJBAABLgAECggJIAAXAJQVAA==.Thoristain:BAAALgAECgYJEQAAAA==.Thorshman:BAAALgADCgcJBwABLgAECgYJEQACAAAAAA==.Thrain:BAABLgAECn8dAAIBAAgJvwsdSwBvAQhoDAAABQAiAGkMAAAEACsAawwAAAUAIABqDAAABAA4AGwMAAADAC0AbQwAAAEAEwDqDAAABgATAG4MAAABAA8AAQAICb8LHUsAbwEIaAwAAAUAIgBpDAAABAArAGsMAAAFACAAagwAAAQAOABsDAAAAwAtAG0MAAABABMA6gwAAAYAEwBuDAAAAQAPAAAA.Threefive:BAAALgAECgQJBQAAAA==.',
To='Torvar:BAAALgADCgEJAgAAAA==.Totemíc:BAAALgAECgQJBQAAAA==.',
Tp='Tpops:BAAALgADCgQJBAAAAA==.',
Ty='Tyrdrea:BAAALgADCgkJCQAAAA==.',
Un='Unholypwnage:BAAALgADCgEJAQAAAA==.',
Va='Vallak:BAAALgAECgQJBAAAAA==.',
Ve='Velarion:BAAALgAECgEJAQAAAA==.Veryundead:BAABLgAECn8kAAIUAAgJaQ8yCQBOAQhoDAAABgA8AGkMAAAGADYAawwAAAYAIABqDAAABQAtAGwMAAAEABcAbQwAAAIAFADqDAAABgA0AG4MAAABACEAFAAICWkPMgkATgEIaAwAAAYAPABpDAAABgA2AGsMAAAGACAAagwAAAUALQBsDAAABAAXAG0MAAACABQA6gwAAAYANABuDAAAAQAhAAAA.',
Vo='Void:BAABLgAECn8VAAIQAAYJwBc9FABYAQZoDAAABQBBAGkMAAAFAD0AawwAAAUAOABqDAAAAgBTAGwMAAACAEUA6gwAAAIAMgAQAAYJwBc9FABYAQZoDAAABQBBAGkMAAAFAD0AawwAAAUAOABqDAAAAgBTAGwMAAACAEUA6gwAAAIAMgAAAA==.Voidmara:BAAALgAECgEJAgAAAA==.Voíd:BAAALgAECgEJAQAAAA==.',
Vr='Vrylykos:BAAALgAECgYJCgAAAA==.',
Wa='Waddlez:BAAALgAECgEJAQAAAA==.Wardawg:BAAALgADCgEJAQABLgAECggJIQAFACQjAA==.Wargrylls:BAAALgADCgcJBwAAAA==.',
We='Wendrin:BAAALgAECgYJBgAAAA==.',
Wh='White:BAAALgAECgQJBQAAAA==.',
Wo='Wolvynlyfe:BAAALgADCgIJAgAAAA==.',
Xa='Xanarine:BAABLgAECn8VAAMLAAYJhRQvRABnAQZoDAAABgBCAGkMAAAGAEcAawwAAAUANABqDAAAAQASAGwMAAABACAA6gwAAAIASQALAAYJhRQvRABnAQZoDAAABQBCAGkMAAAFAEcAawwAAAUANABqDAAAAQASAGwMAAABACAA6gwAAAIASQABAAIJtQdGIQFbAAJoDAAAAQAbAGkMAAABAAsAAAA=.Xavíous:BAAALgADCgYJBgAAAA==.',
Xe='Xeeva:BAABLgAECn8VAAIaAAUJXxcpQAAUAQVoDAAABgAyAGkMAAAFAFUAawwAAAUAOgBqDAAAAgBGAOoMAAADACEAGgAFCV8XKUAAFAEFaAwAAAYAMgBpDAAABQBVAGsMAAAFADoAagwAAAIARgDqDAAAAwAhAAAA.',
Xu='Xuralxia:BAAALgAECgEJBgAAAA==.',
Zi='Zink:BAAALgAECgEJAQAAAA==.Ziyad:BAABLgAECn8WAAQDAAcJexNfHABgAQdoDAAABAAyAGkMAAAEADcAawwAAAQANABqDAAAAwAvAGwMAAACACYAbQwAAAEAJQDqDAAABABAAAMABwkEEV8cAGABB2gMAAADAC0AaQwAAAMAFgBrDAAAAwA0AGoMAAADAC8AbAwAAAIAJgBtDAAAAQAlAOoMAAADAEAADQADCcMTCyEAlQADaAwAAAEAMgBpDAAAAQA3AGsMAAABAC0ADAABCYgBKOoAGgAB6gwAAAEAAwAAAA==.',
Zy='Zyn:BAAALgAECgMJAwAAAA==.',
['Zè']='Zèró:BAAALgAECgYJEwAAAA==.',
['Ðü']='Ðüß:BAAALgADCgIJAgABLgAECgMJAwACAAAAAA==.',
['Ön']='Öna:BAABLgAECn8jAAIRAAgJ6hLoNwDOAQhoDAAABgA4AGkMAAAGAEUAawwAAAYAOgBqDAAABQBGAGwMAAAEADQAbQwAAAEAHwDqDAAABgA3AG4MAAABAA8AEQAICeoS6DcAzgEIaAwAAAYAOABpDAAABgBFAGsMAAAGADoAagwAAAUARgBsDAAABAA0AG0MAAABAB8A6gwAAAYANwBuDAAAAQAPAAAA.',
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
