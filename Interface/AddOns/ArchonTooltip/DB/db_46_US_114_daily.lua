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

local lookup = {'DeathKnight-Unholy','Warlock-Affliction','Warlock-Demonology','Priest-Holy','Shaman-Elemental','Shaman-Restoration','Warlock-Destruction','Paladin-Retribution','Rogue-Assassination','Rogue-Subtlety','Priest-Shadow','Unknown-Unknown','Hunter-Survival','Paladin-Holy','Priest-Discipline','Druid-Restoration','Hunter-BeastMastery','Mage-Frost','Mage-Arcane','DeathKnight-Blood','Paladin-Protection','DemonHunter-Vengeance','DemonHunter-Havoc','Warrior-Fury','Warrior-Arms','DemonHunter-Devourer','Druid-Guardian','Shaman-Enhancement','DeathKnight-Frost','Monk-Windwalker',}
local provider = {region='US',realm="Gul'dan",name='US',type='daily',zone=46,date='2026-05-22',data={Ae='Aeri:BAAALgAECgYJDAAAAA==.',
Al='Alastormoody:BAAALgADCgcJDAAAAA==.Alelover:BAAALgADCgUJBQAAAA==.Allaria:BAAALgAECgQJDQAAAA==.Almadíon:BAAALgADCgcJCAAAAA==.',
Am='Amosian:BAAALgADCgIJAgAAAA==.',
An='Ana:BAAALgADCgMJAwAAAA==.',
Ao='Aoemomma:BAAALgADCgcJBwAAAA==.',
Ar='Arin:BAAALgAECgIJAwABLgAFFAMJCgABAEEmAA==.',
As='Asuya:BAAALgADCgIJAwAAAA==.',
Az='Azög:BAAALgADCgUJBQAAAA==.',
Ba='Babysocks:BAAALgAECgYJBgAAAA==.',
Bc='Bc:BAACLgAFFH8HAAMCAAMJ3RmXBQDdAANsDAAAAQAVAG0MAAABAE0A6gwAAAUAYwACAAIJpSKXBQDdAAJtDAAAAQBNAOoMAAABAGMAAwACCRkXBGwAtwACbAwAAAEAFQDqDAAABABhAC4ABAp/GwACAwAICfgmMQMAjQMAAwAICfgmMQMAjQMAAAA=.',
Be='Beep:BAABLgAECn8lAAIDAAcJRh+JOgAiAgdoDAAABwBVAGkMAAAGAFMAawwAAAYAWABqDAAABgBdAGwMAAAFAE8AbQwAAAEALwDqDAAABgBgAAMABwlGH4k6ACICB2gMAAAHAFUAaQwAAAYAUwBrDAAABgBYAGoMAAAGAF0AbAwAAAUATwBtDAAAAQAvAOoMAAAGAGAAAAA=.',
Bl='Blackthunder:BAAALgAECggJDAAAAA==.',
Bo='Bobert:BAAALgADCgcJBgAAAA==.Bofadz:BAAALgADCgYJBgAAAA==.Boozecruise:BAAALgADCgIJAgAAAA==.Bowyn:BAABLgAECn8XAAIEAAYJHhNoOgBSAQZoDAAABAA3AGkMAAAFACYAawwAAAUAJgBqDAAAAwAYAGwMAAADADkA6gwAAAMAUAAEAAYJHhNoOgBSAQZoDAAABAA3AGkMAAAFACYAawwAAAUAJgBqDAAAAwAYAGwMAAADADkA6gwAAAMAUAAAAA==.',
Bu='Budleaf:BAAALgAECgUJDAAAAA==.Bunkley:BAABLgAECn8gAAMFAAcJYQtyQAD+AAdoDAAABgATAGkMAAAFABkAawwAAAYAIgBqDAAABgA7AGwMAAACACgA6gwAAAQAJABuDAAAAwARAAUABwlgC3JAAP4AB2gMAAACABMAaQwAAAIAGQBrDAAAAQAiAGoMAAACADsAbAwAAAIAKADqDAAAAwAkAG4MAAACABEABgAGCVUKiWgA5AAGaAwAAAQAOQBpDAAAAwASAGsMAAAFACMAagwAAAQAIwDqDAAAAQAIAG4MAAABAAQAAAA=.Butterknives:BAAALgAECgEJAQAAAA==.',
By='Byege:BAACLgAFFH8OAAIDAAUJBxipNgA0AQVoDAAAAwBWAGkMAAADACUAawwAAAEAJABqDAAAAQAXAOoMAAAGAFUAAwAFCQcYqTYANAEFaAwAAAMAVgBpDAAAAwAlAGsMAAABACQAagwAAAEAFwDqDAAABgBVAC4ABAp/JwADAwAJCccf2REApQIAAwAJCaMf2REApQIABwAFCc4XshsAcAEAAAA=.',
Ca='Cantfireme:BAAALgADCgcJBwABLgAECggJNwAIAFkdAA==.Cardhunter:BAAALgADCgYJBgAAAA==.Cash:BAABLgAECn8UAAMJAAgJNBAmCACiAQhoDAAAAwAsAGkMAAADADUAawwAAAMAPABqDAAAAwAmAGwMAAADACcAbQwAAAEAGwDqDAAAAwAkAG4MAAABABwACQAICTQQJggAogEIaAwAAAIALABpDAAAAgA1AGsMAAACADwAagwAAAIAJgBsDAAAAwAnAG0MAAABABsA6gwAAAIAJABuDAAAAQAcAAoABQl9A8I+AIIABWgMAAABAA4AaQwAAAEAEABrDAAAAQAAAGoMAAABAA8A6gwAAAEABAAAAA==.',
Ch='Champilon:BAAALgADCgYJBgAAAA==.Chaoticus:BAAALgAECgYJDQABLgAECggJIgALAJgOAA==.Charizards:BAAALgADCgYJDQAAAA==.Charmahnder:BAAALgAECgIJAgAAAA==.',
Cr='Crunbard:BAAALgAECgcJDQAAAA==.',
Cu='Culdan:BAABLgAECn8XAAMHAAYJfwcGHQCaAAZoDAAABQAIAGkMAAAFABoAawwAAAYAFQBqDAAAAgASAGwMAAACABEA6gwAAAMAFgAHAAUJhQgGHQCaAAVpDAAAAQAaAGsMAAAEABUAagwAAAIAEgBsDAAAAgARAOoMAAACABYAAwAECR8ESMwAlAAEaAwAAAUACABpDAAABAAOAGsMAAACAAoA6gwAAAEACAAAAA==.',
Da='Dalirus:BAAALgAECgEJAQABLgAECggJNwAIAFkdAA==.Danahe:BAAALgAECgEJAQAAAA==.Darci:BAAALgAECgcJDgABLgAECgQJCAAMAAAAAA==.Darksuaza:BAAALgAECgcJDAAAAA==.Darthwizard:BAAALgADCgIJAgAAAA==.Dasbunk:BAAALgAECgEJAgAAAA==.Dayman:BAAALgADCgYJBgAAAA==.',
De='Deadblue:BAABLgAECn8vAAIHAAkJmxn7AgBJAgloDAAABQBMAGkMAAAHAEgAawwAAAYANQBqDAAABgArAGwMAAAGADkAbQwAAAQAJgDqDAAABwBMAG4MAAAEAFYAbwwAAAIAPwAHAAkJmxn7AgBJAgloDAAABQBMAGkMAAAHAEgAawwAAAYANQBqDAAABgArAGwMAAAGADkAbQwAAAQAJgDqDAAABwBMAG4MAAAEAFYAbwwAAAIAPwAAAA==.Deekay:BAAALgADCgcJFAAAAA==.',
Di='Diogee:BAAALgAECgMJBgAAAA==.Discipline:BAAALgAECgYJDAABLgAFFAcJIwANAKkVAA==.Divinate:BAAALgAECgIJAgAAAA==.',
Dk='Dkpitador:BAAALgADCgEJAQAAAA==.',
Do='Doomhead:BAABLgAECn8YAAIBAAgJ2AipdgBQAQhoDAAABAASAGkMAAAEABgAawwAAAQAEABqDAAAAwATAGwMAAACABkAbQwAAAEAHwDqDAAABQAaAG4MAAABABAAAQAICdgIqXYAUAEIaAwAAAQAEgBpDAAABAAYAGsMAAAEABAAagwAAAMAEwBsDAAAAgAZAG0MAAABAB8A6gwAAAUAGgBuDAAAAQAQAAAA.',
Dr='Drakki:BAAALgADCgUJBQAAAA==.Dreadfaith:BAAALgAECgYJBgAAAA==.',
Du='Durzii:BAACLgAFFH8FAAIOAAIJuiL2JwC8AAJoDAAAAwBVAGkMAAACAFwADgACCboi9icAvAACaAwAAAMAVQBpDAAAAgBcAC4ABAp/GQADDgAJCaogoRIAfQIADgAICd4hoRIAfQIACAABCe0ZGyoBUgAAAAA=.',
Ea='Eatmybeef:BAAALgADCgYJCgAAAA==.',
Ex='Extinctionus:BAAALgAECgQJBQAAAA==.',
Fe='Fernn:BAAALgADCgQJBAAAAA==.',
Fi='Fia:BAABLgAECn8wAAIBAAkJwQ8TRADTAQloDAAABwAzAGkMAAAHADMAawwAAAYANQBqDAAABgAsAGwMAAAGACkAbQwAAAQAKwDqDAAABgAdAG4MAAAEACAAbwwAAAIAEgABAAkJwQ8TRADTAQloDAAABwAzAGkMAAAHADMAawwAAAYANQBqDAAABgAsAGwMAAAGACkAbQwAAAQAKwDqDAAABgAdAG4MAAAEACAAbwwAAAIAEgAAAA==.',
Fu='Furor:BAAALgAECgQJBAAAAA==.',
Ge='Genaro:BAAALgAECgIJBwAAAA==.',
Gi='Gibraltar:BAAALgADCgUJBQAAAA==.',
Go='Gokujang:BAAALgAECgUJCgABLgAECggJGAAPADwRAA==.Goremont:BAAALgADCgQJBQAAAA==.Gorlok:BAAALgAECgUJBQAAAA==.',
Gr='Greendot:BAACLgAFFH8HAAIQAAMJ8xSRLQDYAANoDAAAAgA/AGkMAAADAC8A6gwAAAIAMQAQAAMJ8xSRLQDYAANoDAAAAgA/AGkMAAADAC8A6gwAAAIAMQAuAAQKfyoAAhAACAlgI8cGAC4DABAACAlgI8cGAC4DAAAA.',
Gu='Gulvid:BAACLgAFFH8GAAIDAAIJlx1fbwCuAAJoDAAAAgBYAOoMAAAEAD8AAwACCZcdX28ArgACaAwAAAIAWADqDAAABAA/AC4ABAp/GAADAwAHCWQh0ksAngEAAwAHCWQh0ksAngEABwABCQAAqlwAWAAAAS4ABRQHCRcAAwCkFQA=.',
Ha='Haluak:BAABLgAECn8oAAIFAAgJ8hejHQDEAQhoDAAABwBBAGkMAAAIAEsAawwAAAcASgBqDAAABQBOAGwMAAADADsAbQwAAAIAKADqDAAABgBFAG4MAAACACwABQAICfIXox0AxAEIaAwAAAcAQQBpDAAACABLAGsMAAAHAEoAagwAAAUATgBsDAAAAwA7AG0MAAACACgA6gwAAAYARQBuDAAAAgAsAAAA.',
He='Healthyself:BAAALgAECgYJCwAAAA==.',
Ho='Houndtamer:BAABLgAECn8rAAIRAAgJ3RMxQgCsAQhoDAAABwBFAGkMAAAHACkAawwAAAcALgBqDAAABwA+AGwMAAAEAC0AbQwAAAEAGgDqDAAABwA2AG4MAAADAEgAEQAICd0TMUIArAEIaAwAAAcARQBpDAAABwApAGsMAAAHAC4AagwAAAcAPgBsDAAABAAtAG0MAAABABoA6gwAAAcANgBuDAAAAwBIAAAA.',
Hp='Hpyflowers:BAAALgADCgQJBAAAAA==.',
Hr='Hruoth:BAAALgAECgYJBgAAAA==.',
Ic='Iceshooting:BAAALgAECgQJBwAAAA==.',
Is='Ishtar:BAABLgAECn8ZAAMSAAYJ9BzVhADIAQZoDAAABQBFAGkMAAAFAFEAawwAAAQATQBqDAAABABMAGwMAAAEAFMA6gwAAAMAOgASAAYJCRnVhADIAQZoDAAAAwAqAGkMAAAFAFEAawwAAAMATQBqDAAABABMAGwMAAAEAFMA6gwAAAIAIwATAAMJzRkuDwDQAANoDAAAAgBFAGsMAAABAEYA6gwAAAEAOgAAAA==.',
It='Itshela:BAACLgAFFH8aAAMBAAcJfxgRDwDoAQdoDAAABgBRAGkMAAAEAFUAawwAAAMAJgBqDAAABQA2AGwMAAACACAAbQwAAAEAPgDqDAAABQBMAAEABgl/GBEPAOgBBmgMAAAGAFEAaQwAAAQAVQBrDAAAAwAmAGwMAAACACAAbQwAAAEAPgDqDAAABQBMABQAAQkAAGk+AAAAAWoMAAAFADYALgAECn8bAAIBAAcJOCPrTQAJAgABAAcJOCPrTQAJAgAAAA==.',
Ja='Jayrad:BAAALgAECgYJEAAAAA==.',
Je='Jehnovah:BAAALgADCgMJAwAAAA==.Jellybeanz:BAAALgADCggJDQAAAA==.',
Jo='Jordybear:BAAALgAECgQJBAAAAA==.Jorkoh:BAAALgAECgMJBgAAAA==.',
Ju='Juicer:BAAALgADCgMJBgAAAA==.',
Ka='Kaiige:BAAALgAECgQJBAAAAA==.Kairos:BAAALgAECgYJCgAAAA==.Kanê:BAAALgAFFAMJAwAAAA==.',
Ke='Kehlayr:BAAALgADCgMJAwAAAA==.Keiiry:BAAALgADCgMJAwAAAA==.Kenshinth:BAAALgAECgYJDwAAAA==.Kethrym:BAAALgAECgIJAgAAAA==.',
Kh='Khanor:BAAALgAECgYJEQAAAA==.',
Ki='Kiltro:BAAALgAECgQJBgAAAA==.Kimchichi:BAABLgAECn8VAAIIAAcJBRxLPgDrAQdoDAAABQBHAGkMAAAEAEsAawwAAAQAPgBqDAAAAwApAGwMAAACAFAAbQwAAAIAVwDqDAAAAQA0AAgABwkFHEs+AOsBB2gMAAAFAEcAaQwAAAQASwBrDAAABAA+AGoMAAADACkAbAwAAAIAUABtDAAAAgBXAOoMAAABADQAAAA=.Kintaro:BAAALgADCgYJDwAAAA==.',
Ko='Kogorko:BAAALgAECgIJAgAAAA==.',
Kr='Kry:BAAALgAECgIJAgAAAA==.',
['Kë']='Këarra:BAAALgAECgQJBwAAAA==.',
La='Labotimizer:BAAALgAECggJDwAAAA==.Lapriestess:BAAALgAECgYJCwAAAA==.Latoya:BAAALgAFFAIJAgAAAA==.',
Li='Lilbeemo:BAAALgAECgUJCgAAAA==.Lilyana:BAAALgAECgYJCwAAAA==.Liongs:BAAALgAECgYJBgABLgAECgYJDwAMAAAAAA==.Litdk:BAAALgADCgUJBQAAAA==.Litharidk:BAABLgAECn8cAAIBAAcJVCCtQADeAQdoDAAABgBZAGkMAAAHAFkAawwAAAUATQBqDAAAAwBdAGwMAAACAEoAbQwAAAEATgDqDAAABABXAAEABwlUIK1AAN4BB2gMAAAGAFkAaQwAAAcAWQBrDAAABQBNAGoMAAADAF0AbAwAAAIASgBtDAAAAQBOAOoMAAAEAFcAAAA=.',
Lo='Loudog:BAAALgAECgYJBwAAAA==.Loxyblue:BAAALgAECgMJAwAAAA==.',
Lu='Luckyxpain:BAABLgAECn83AAMIAAgJWR0WKwAxAghoDAAACgBRAGkMAAAHAD0AawwAAAkARQBqDAAABwBcAGwMAAALAD8AbQwAAAMAXgDqDAAABgBLAG4MAAACAE8ACAAICVkdFisAMQIIaAwAAAcAUQBpDAAABgA9AGsMAAAHAEUAagwAAAUAXABsDAAABQA/AG0MAAADAF4A6gwAAAMASwBuDAAAAgBPABUABgn8CfElALQABmgMAAADABEAaQwAAAEAHABrDAAAAgARAGoMAAACACkAbAwAAAYAGwDqDAAAAwAkAAAA.',
Ly='Lykos:BAAALgAECgEJAQAAAA==.',
Ma='Madoff:BAAALgAECgQJCAAAAA==.Makok:BAABLgAECn8YAAMWAAgJuhRiCgCMAQhoDAAABABJAGkMAAADADgAawwAAAMAJgBqDAAAAwAmAGwMAAACAB0AbQwAAAEAKgDqDAAABgA7AG4MAAACAEUAFgAICboUYgoAjAEIaAwAAAQASQBpDAAAAwA4AGsMAAADACYAagwAAAMAJgBsDAAAAgAdAG0MAAABACoA6gwAAAUAOwBuDAAAAgBFABcAAQnsCfJxADMAAeoMAAABABkAAAA=.',
Me='Melancholic:BAABLgAECn8hAAMYAAgJUiAuEgA9AghoDAAABgBWAGkMAAAGAFIAawwAAAUARwBqDAAABAAwAGwMAAADAFYAbQwAAAEASwDqDAAABgBhAG4MAAACAE8AGAAICVIgLhIAPQIIaAwAAAUAVgBpDAAABgBSAGsMAAAFAEcAagwAAAQAMABsDAAAAwBWAG0MAAABAEsA6gwAAAYAYQBuDAAAAgBPABkAAQnFBDxlACgAAWgMAAABAAwAAAA=.Mellisa:BAABLgAECn8fAAMBAAkJcxFoXgCIAQloDAAABwBIAGkMAAAEADUAawwAAAUANwBqDAAAAwBEAGwMAAACABgAbQwAAAEAEgDqDAAABwBNAG4MAAABABIAbwwAAAEAJAABAAgJ2w9oXgCIAQhoDAAABgBIAGkMAAADABAAawwAAAQANwBqDAAAAwBEAGwMAAACABgAbQwAAAEAEgDqDAAABgBNAG4MAAABABIAFAAFCXUTOCIADgEFaAwAAAEALgBpDAAAAQA1AGsMAAABADQA6gwAAAEAPABvDAAAAQAkAAAA.Memory:BAAALgAECgEJAgAAAA==.',
Mi='Milkingman:BAAALgAECgEJAQAAAA==.',
Mo='Mooshmoo:BAAALgAECgEJAQAAAA==.',
Mu='Murog:BAABLgAECn8XAAIGAAgJSQ1/QAB1AQhoDAAAAgAvAGkMAAACADEAawwAAAIAEQBqDAAAAwArAGwMAAAEADIAbQwAAAIAEgDqDAAABgAgAG4MAAACAAwABgAICUkNf0AAdQEIaAwAAAIALwBpDAAAAgAxAGsMAAACABEAagwAAAMAKwBsDAAABAAyAG0MAAACABIA6gwAAAYAIABuDAAAAgAMAAAA.',
Na='Nazarite:BAAALgAECgQJCgAAAA==.',
Ni='Nightdisco:BAAALgAECgMJAwAAAA==.',
No='Noctyra:BAAALgAECgQJCAAAAA==.Nomaana:BAAALgAECgMJAwAAAA==.Norael:BAAALgADCgIJAgAAAA==.',
Og='Ogthunder:BAAALgAECgEJAQAAAA==.',
Op='Ophellia:BAAALgAECgEJAQAAAA==.',
Pu='Pureformance:BAAALgADCgcJBwABLgAFFAcJHgAQAIIjAA==.Purrformance:BAACLgAFFH8eAAIQAAcJgiMiAgDCAgdoDAAABgBgAGkMAAAGAGEAawwAAAQAXABqDAAABABNAGwMAAACAF0AbQwAAAEAUADqDAAABwBhABAABwmCIyICAMICB2gMAAAGAGAAaQwAAAYAYQBrDAAABABcAGoMAAAEAE0AbAwAAAIAXQBtDAAAAQBQAOoMAAAHAGEALgAECn8iAAIQAAkJoiUMAQCnAwAQAAkJoiUMAQCnAwAAAA==.',
Py='Pyrophobiac:BAACLgAFFH8WAAMDAAcJ4xWVEgBSAQdoDAAABABLAGkMAAADABgAawwAAAMALQBqDAAAAQADAGwMAAADAFgAbQwAAAIAGADqDAAABgBPAAMABwnjFZUSAFIBB2gMAAAEAEsAaQwAAAIAGABrDAAAAQAtAGoMAAABAAMAbAwAAAMAWABtDAAAAgAYAOoMAAAGAE8ABwACCVgCSg8AfwACaQwAAAEABwBrDAAAAgAEAC4ABAp/IwADAwAJCdojgAMAhwMAAwAJCZgjgAMAhwMABwAHCaEdRwcAVAIAAAA=.',
Ra='Ra:BAABLgAECn8gAAIXAAgJGR4hCgBUAghoDAAABABPAGkMAAAFAFwAawwAAAUAXABqDAAABQBQAGwMAAAEAFAAbQwAAAEALwDqDAAABQBQAG4MAAADAEIAFwAICRkeIQoAVAIIaAwAAAQATwBpDAAABQBcAGsMAAAFAFwAagwAAAUAUABsDAAABABQAG0MAAABAC8A6gwAAAUAUABuDAAAAwBCAAAA.Radagast:BAACLgAFFH8IAAIaAAMJwgXaUwC4AANoDAAAAwAPAGkMAAACAA4A6gwAAAMADQAaAAMJwgXaUwC4AANoDAAAAwAPAGkMAAACAA4A6gwAAAMADQAuAAQKfygAAxoACAlsF2otAPABABoACAn9FmotAPABABcABgl0DzwnAAIBAAAA.Radditz:BAAALgAECgYJCwAAAA==.Rafiki:BAAALgAECgEJAQAAAA==.Rand:BAAALgADCgcJDgAAAA==.',
Ri='Riv:BAAALgAECgMJAwAAAA==.',
Ro='Ronni:BAAALgAECgIJAgAAAA==.Roxyfox:BAAALgAECgYJCwAAAA==.Royvaz:BAAALgAECgUJBQAAAA==.',
Sa='Salea:BAAALgAECgIJAgAAAA==.Sarryn:BAAALgADCgcJBwAAAA==.',
Sc='Scale:BAAALgAECgMJAwAAAA==.',
Se='Serik:BAAALgADCgEJAQAAAA==.',
Sh='Shakaboom:BAAALgAFFAEJAQAAAA==.Sheffurs:BAABLgAECn8vAAIbAAkJzwLeLwCfAAloDAAABQAEAGkMAAAHAAQAawwAAAYABABqDAAABgAGAGwMAAAGAAkAbQwAAAQADQDqDAAABwANAG4MAAAEAAMAbwwAAAIABAAbAAkJzwLeLwCfAAloDAAABQAEAGkMAAAHAAQAawwAAAYABABqDAAABgAGAGwMAAAGAAkAbQwAAAQADQDqDAAABwANAG4MAAAEAAMAbwwAAAIABAAAAA==.Shepardl:BAACLgAFFH8kAAIOAAcJNCXKAADnAgdoDAAABwBdAGkMAAAHAGEAawwAAAUAZABqDAAABQBNAGwMAAAEAGMAbQwAAAEAYgDqDAAABwBjAA4ABwk0JcoAAOcCB2gMAAAHAF0AaQwAAAcAYQBrDAAABQBkAGoMAAAFAE0AbAwAAAQAYwBtDAAAAQBiAOoMAAAHAGMALgAECn8hAAIOAAgJ5CYaAQCBAwAOAAgJ5CYaAQCBAwAAAA==.Shárkbait:BAAALgADCgcJDAABLgAFFAMJBwAUAB4LAA==.',
Sk='Skadoosher:BAAALgAECgUJBQAAAA==.Skyratt:BAAALgAECgEJAgAAAA==.',
Sm='Smackemz:BAAALgAECgYJCQAAAA==.Smacmywand:BAAALgAECgIJBgAAAA==.',
So='Sollasi:BAAALgADCgMJBgAAAA==.Sortie:BAABLgAECn8vAAMOAAkJjAkeLQCBAQloDAAABQAHAGkMAAAHAAwAawwAAAYAFwBqDAAABgAPAGwMAAAGACQAbQwAAAQAGQDqDAAABwA0AG4MAAAEABMAbwwAAAIAGwAOAAkJjAkeLQCBAQloDAAAAgAHAGkMAAADAAwAawwAAAMAFwBqDAAAAwAPAGwMAAAEACQAbQwAAAMAGQDqDAAAAgA0AG4MAAABABMAbwwAAAIAGwAIAAgJCwpPggBGAQhoDAAAAwAvAGkMAAAEACMAawwAAAMAFABqDAAAAwAkAGwMAAACAA4AbQwAAAEAEwDqDAAABQAaAG4MAAADABAAAAA=.',
Sp='Spoons:BAAALgAECgQJBAAAAA==.Spyromu:BAAALgAECgQJBgAAAA==.',
St='Stealman:BAAALgADCgcJBwAAAA==.Steeleman:BAAALgADCgQJAgAAAA==.',
Su='Succinic:BAAALgAECggJEAAAAA==.Suffer:BAAALgAECgQJBAAAAA==.',
Sw='Swiss:BAABLgAECn8bAAIOAAgJrw1ONACsAQhoDAAABAA3AGkMAAAEACIAawwAAAQAKwBqDAAAAwAlAGwMAAADABoAbQwAAAMAEwDqDAAAAwA5AG4MAAADAAcADgAICa8NTjQArAEIaAwAAAQANwBpDAAABAAiAGsMAAAEACsAagwAAAMAJQBsDAAAAwAaAG0MAAADABMA6gwAAAMAOQBuDAAAAwAHAAAA.',
Sy='Sylphvaria:BAAALgADCgUJBQAAAA==.Syren:BAAALgADCgcJBgAAAA==.',
Te='Tegridy:BAAALgAECgQJCAAAAA==.Teko:BAAALgADCgYJCwAAAA==.',
Th='Thegoose:BAAALgAECgIJAgAAAA==.Themans:BAAALgAECgYJDgAAAA==.Thunderrod:BAABLgAECn8lAAIRAAgJUBXOPgC0AQhoDAAABwBFAGkMAAAGAEwAawwAAAcARQBqDAAABgBRAGwMAAAFAEcAbQwAAAEAEADqDAAABAAwAG4MAAABAB0AEQAICVAVzj4AtAEIaAwAAAcARQBpDAAABgBMAGsMAAAHAEUAagwAAAYAUQBsDAAABQBHAG0MAAABABAA6gwAAAQAMABuDAAAAQAdAAAA.',
Ti='Tim:BAAALgADCgYJDQAAAA==.',
To='To:BAAALgAECgIJAgAAAA==.Tovisar:BAAALgAECgMJCQAAAA==.',
Tr='Traessa:BAAALgADCgYJBgAAAA==.',
Tu='Turkturkletn:BAAALgADCgcJEQAAAA==.',
Tw='Twogg:BAAALgAECgYJDgAAAA==.',
Ug='Ugin:BAAALgADCgYJBgAAAA==.Uglykasanova:BAAALgAECgYJEQAAAA==.',
Ul='Ulfrir:BAAALgAECgYJBwAAAA==.',
Va='Vastian:BAAALgAECgUJDQAAAA==.Vaynard:BAAALgAECgQJBAAAAA==.',
Vi='Violet:BAAALgAECgMJBQAAAA==.Vitre:BAAALgAECgUJBwAAAA==.',
Wa='Wanshi:BAAALgAECgcJBgAAAA==.',
We='Wexew:BAABLgAECn8UAAMcAAYJmhnTFgALAQZoDAAAAwA3AGkMAAAEADYAawwAAAQARwBqDAAAAgBYAGwMAAABAFMA6gwAAAYAPgAFAAUJChW+SgAdAQVoDAAAAgA3AGkMAAABADAAawwAAAIAMABqDAAAAQAuAOoMAAADAD4AHAAGCccX0xYACwEGaAwAAAEAIQBpDAAAAwA2AGsMAAACAEcAagwAAAEAWABsDAAAAQBTAOoMAAADAD0AAAA=.Wexwex:BAAALgAECgUJDwABLgAECgYJFAAcAJoZAA==.Wexxew:BAAALgAFFAEJAQAAAA==.',
Wi='Wishing:BAAALgAECgYJEgAAAA==.',
Wu='Wundertot:BAAALgAECgYJBgABLgAECggJKgASACwgAA==.Wunderwazard:BAABLgAECn8qAAISAAgJLCDeLABGAghoDAAABwBXAGkMAAAGAFYAawwAAAYAUwBqDAAABQBJAGwMAAAFAEMAbQwAAAMARADqDAAABgBdAG4MAAAEAFkAEgAICSwg3iwARgIIaAwAAAcAVwBpDAAABgBWAGsMAAAGAFMAagwAAAUASQBsDAAABQBDAG0MAAADAEQA6gwAAAYAXQBuDAAABABZAAAA.',
Xe='Xevikan:BAABLgAECn8bAAMBAAcJDBXWcgBYAQdoDAAABgBHAGkMAAAFADYAawwAAAUASwBqDAAAAgAnAGwMAAACACkAbQwAAAIAHADqDAAABQAzAAEABwkMFdZyAFgBB2gMAAAFAEcAaQwAAAUANgBrDAAABQBLAGoMAAACACcAbAwAAAIAKQBtDAAAAgAcAOoMAAAFADMAHQABCR8IXywAKgABaAwAAAEAFAAAAA==.',
Ya='Yadead:BAAALgAECgYJCwAAAA==.',
Za='Zaylen:BAAALgAECgYJEwABLgAECgkJQgAeAOojAA==.',
Ze='Zendjin:BAAALgADCgYJDQAAAA==.',
Zi='Zistormstout:BAABLgAECn8sAAIFAAgJ1hWiIACtAQhoDAAABwAzAGkMAAAHADEAawwAAAcAQwBqDAAABwBMAGwMAAAEAEYAbQwAAAEAJgDqDAAACAAoAG4MAAADAEoABQAICdYVoiAArQEIaAwAAAcAMwBpDAAABwAxAGsMAAAHAEMAagwAAAcATABsDAAABABGAG0MAAABACYA6gwAAAgAKABuDAAAAwBKAAAA.',
Zu='Zuhgonemad:BAAALgAECgQJBgAAAA==.',
['Äl']='Älektra:BAABLgAECn8ZAAIaAAcJUwTkmQDBAAdoDAAABQAIAGkMAAAFAAwAawwAAAUADQBqDAAAAwANAGwMAAACAAkAbQwAAAEADADqDAAABAAJABoABwlTBOSZAMEAB2gMAAAFAAgAaQwAAAUADABrDAAABQANAGoMAAADAA0AbAwAAAIACQBtDAAAAQAMAOoMAAAEAAkAAAA=.',
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
