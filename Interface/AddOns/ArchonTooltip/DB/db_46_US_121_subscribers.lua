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

local lookup = {'DeathKnight-Blood','DeathKnight-Unholy','Monk-Brewmaster','Monk-Windwalker','Hunter-BeastMastery','Rogue-Subtlety','Unknown-Unknown','Warlock-Demonology','Rogue-Outlaw','Rogue-Assassination','Shaman-Restoration','Shaman-Elemental','Warlock-Destruction','Warlock-Affliction','Evoker-Preservation','Mage-Frost','Druid-Feral','Warrior-Protection','Paladin-Holy','Priest-Shadow','Priest-Discipline','Priest-Holy','Hunter-Marksmanship','Hunter-Survival','DemonHunter-Devourer','Druid-Restoration',}
local provider = {region='US',realm='Hyjal',name='US',type='subscribers',zone=46,date='2026-05-11',data={As='Astaren:BAEALgAECgcJDAAAAA==.',
Az='Azchath:BAEALgAFFAIJAgAAAQ==.',
Br='Bryl:BAECLgAFFH8FAAIBAAMJiiFSGQCOAANoDAAAAQBLAGoMAAABADAA6gwAAAMAXwABAAMJiiFSGQCOAANoDAAAAQBLAGoMAAABADAA6gwAAAMAXwAuAAQKfyAAAwEACQnbHqsGAMoCAAEACQnbHqsGAMoCAAIABwljERdxAKUBAAEuAAUUBAkNAAMAlh8A.Brylic:BAECLgAFFH8NAAIDAAQJlh8vCQB9AQRoDAAABABYAGkMAAAFAF4AawwAAAMAWQDqDAAAAQAzAAMABAmWHy8JAH0BBGgMAAAEAFgAaQwAAAUAXgBrDAAAAwBZAOoMAAABADMALgAECn8hAAMEAAgJOSMjBgAfAwAEAAgJJiEjBgAfAwADAAgJqiIyCAACAwAAAA==.',
Ca='Camreon:BAEALgAFFAEJAQAAAA==.',
Ce='Cenitarius:BAEALgADCgcJBwABLgAECgkJLwAFAE4lAA==.',
Cm='Cmenstabber:BAEBLgAECn8eAAIGAAgJlw86EACxAQhoDAAABQAdAGkMAAAFAC0AawwAAAUAHwBqDAAABAAXAGwMAAAEAEYAbQwAAAEACQDqDAAABQA0AG4MAAABACgABgAICZcPOhAAsQEIaAwAAAUAHQBpDAAABQAtAGsMAAAFAB8AagwAAAQAFwBsDAAABABGAG0MAAABAAkA6gwAAAUANABuDAAAAQAoAAAA.',
Fi='Fishybrew:BAEBLgAECn8eAAIDAAYJeh+HEwCvAQZoDAAABwA+AGkMAAAGAFQAawwAAAUAUgBqDAAABABXAGwMAAADAFAA6gwAAAUAXQADAAYJeh+HEwCvAQZoDAAABwA+AGkMAAAGAFQAawwAAAUAUgBqDAAABABXAGwMAAADAFAA6gwAAAUAXQABLgADCgEJAQAHAAAAAA==.',
Fl='Fleasfordays:BAEALgAECgEJAQABLgAECggJHgAGAJcPAA==.',
Fo='Foxblade:BAEALgAECgUJCgABLgAECgYJEQAHAAAAAA==.Foxorcism:BAEALgAECgYJEQAAAA==.Foxox:BAEALgAECgQJEQABLgAECgYJEQAHAAAAAA==.',
Fr='Fries:BAEALgAECgcJCgABLgAFFAQJBwAIAKYPAA==.',
Ga='Gardenweed:BAEALgAECgYJEQAAAA==.',
Gu='Guthyne:BAEALgAECgMJAwABLgAECggJIQAJAMAjAA==.Guthynn:BAEBLgAECn8hAAMJAAgJwCPDAAAdAwhoDAAABwBhAGkMAAAFAFwAawwAAAUAYQBqDAAAAgBiAGwMAAABAFkAbQwAAAMAQwDqDAAABQBjAG4MAAAFAGEACQAICcAjwwAAHQMIaAwAAAUAYQBpDAAABQBcAGsMAAAFAGEAagwAAAIAYgBsDAAAAQBZAG0MAAADAEMA6gwAAAUAYwBuDAAABQBhAAoAAQnMG1wdAEAAAWgMAAACAEcAAAA=.',
Ir='Irrogenia:BAEBLgAECn8mAAMLAAgJSh80CQCpAghoDAAABwBgAGkMAAAHAFUAawwAAAYAYQBqDAAABABGAGwMAAAEAFkAbQwAAAIANQDqDAAABgBTAG4MAAACAEAACwAICUofNAkAqQIIaAwAAAcAYABpDAAABgBVAGsMAAAFAGEAagwAAAQARgBsDAAABABZAG0MAAACADUA6gwAAAYAUwBuDAAAAgBAAAwAAgn9CjZVAGYAAmkMAAABACIAawwAAAEAFQAAAA==.',
Ja='Jarik:BAEALgAECgQJCAABLgAECgkJLwAFAE4lAA==.',
Ka='Kalamazi:BAEBLgAFFH8TAAQIAAQJGh8pOQACAQRoDAAABQBbAGkMAAAFAEwAawwAAAQARQDqDAAABQBQAAgAAwmXHyk5AAIBA2gMAAAFAFsAaQwAAAEARgDqDAAABQBQAA0AAgnAFA8NAKQAAmkMAAABACQAawwAAAQARQAOAAEJxB17AwBfAAFpDAAAAwBMAAAA.',
Li='Lidariel:BAEALgAECgIJAgABLgAECgkJJwAPAJQVAA==.Lidathra:BAEBLgAECn8nAAIPAAkJlBWhBwAIAgloDAAABQAkAGkMAAAFAE4AawwAAAUAPgBqDAAABQBCAGwMAAAFAEkAbQwAAAQANQDqDAAABAAnAG4MAAAFAEIAbwwAAAEAFAAPAAkJlBWhBwAIAgloDAAABQAkAGkMAAAFAE4AawwAAAUAPgBqDAAABQBCAGwMAAAFAEkAbQwAAAQANQDqDAAABAAnAG4MAAAFAEIAbwwAAAEAFAAAAA==.Lidiosa:BAEBLgAECn8XAAIQAAYJVRH2dQA0AQZoDAAABQAyAGkMAAADADQAawwAAAQAKQBqDAAAAwASAGwMAAACADAA6gwAAAYAHAAQAAYJVRH2dQA0AQZoDAAABQAyAGkMAAADADQAawwAAAQAKQBqDAAAAwASAGwMAAACADAA6gwAAAYAHAABLgAECgkJJwAPAJQVAA==.Lidizine:BAEALgADCggJDAABLgAECgkJJwAPAJQVAA==.',
Lo='Lochru:BAEBLgAECn8pAAIRAAgJKxxgBAA8AghoDAAABwBdAGkMAAAGAFMAawwAAAcAUgBqDAAABQBSAGwMAAAEAEMAbQwAAAMALwDqDAAABgBMAG4MAAADADUAEQAICSscYAQAPAIIaAwAAAcAXQBpDAAABgBTAGsMAAAHAFIAagwAAAUAUgBsDAAABABDAG0MAAADAC8A6gwAAAYATABuDAAAAwA1AAAA.',
Ma='Makoto:BAEBLgAECn8aAAISAAcJlR3qCwBOAgdoDAAABQBaAGkMAAAFAFcAawwAAAUAWABqDAAABAA7AGwMAAADAE4AbQwAAAEAGgDqDAAAAwBTABIABwmVHeoLAE4CB2gMAAAFAFoAaQwAAAUAVwBrDAAABQBYAGoMAAAEADsAbAwAAAMATgBtDAAAAQAaAOoMAAADAFMAAAA=.',
Ne='Neodefender:BAECLgAFFH8ZAAITAAUJHyZgAwANAgVoDAAABwBjAGkMAAAGAF4AawwAAAQAYwBqDAAAAgBfAOoMAAAGAGEAEwAFCR8mYAMADQIFaAwAAAcAYwBpDAAABgBeAGsMAAAEAGMAagwAAAIAXwDqDAAABgBhAC4ABAp/KwACEwAJCUIm/AAAiAMAEwAJCUIm/AAAiAMAAAA=.',
No='Nosferratu:BAECLgAFFH8dAAIUAAcJUhyOAABXAgdoDAAABwBjAGkMAAAEACwAawwAAAQAWwBqDAAABQAcAGwMAAACAD0A6gwAAAYAYQBuDAAAAQAoABQABwlSHI4AAFcCB2gMAAAHAGMAaQwAAAQALABrDAAABABbAGoMAAAFABwAbAwAAAIAPQDqDAAABgBhAG4MAAABACgALgAECn82AAIUAAkJVCZLAACMAwAUAAkJVCZLAACMAwAAAA==.',
Ny='Nyfaria:BAECLgAFFH8NAAIDAAQJ1QYHIADvAARoDAAABQAZAGkMAAAEAAQAawwAAAEABgDqDAAAAwAgAAMABAnVBgcgAO8ABGgMAAAFABkAaQwAAAQABABrDAAAAQAGAOoMAAADACAALgAECn8XAAIDAAkJnA6jJgDPAQADAAkJnA6jJgDPAQAAAA==.',
Or='Orsp:BAECLgAFFH8TAAQUAAcJDhSJAwCxAQdoDAAAAwBLAGkMAAACAEwAawwAAAMANABqDAAAAwATAGwMAAABAAIAbQwAAAEAGgDqDAAABgBKABQABgnlF4kDALEBBmgMAAADAEsAaQwAAAIATABrDAAAAwA0AGoMAAABABMAbQwAAAEAGgDqDAAABgBKABUAAgk8ATsWAH4AAmoMAAABAAAAbAwAAAEABQAWAAEJRgHvFABBAAFqDAAAAQADAC4ABAp/JwAEFAAJCe0iOwUAPQMAFAAJCe0iOwUAPQMAFgADCcoKCGUAmQAAFQADCcEZ8T4AZAAAAAA=.Orspp:BAEBLgAECn8aAAQUAAcJOxZtIQDMAQdoDAAAAwBGAGkMAAAFAEUAawwAAAQAQQBqDAAABABPAGwMAAADAC8A6gwAAAYAPABuDAAAAQAbABQABwk7Fm0hAMwBB2gMAAACAEYAaQwAAAQARQBrDAAAAwBBAGoMAAACAE8AbAwAAAEALwDqDAAAAwA8AG4MAAABABsAFgAGCaUIIkkAFAEGaAwAAAEABwBpDAAAAQAaAGsMAAABAAgAagwAAAIAGwBsDAAAAgAvAOoMAAACAA4AFQABCbUNwVUANgAB6gwAAAEAIwABLgAFFAcJEwAUAA4UAA==.',
Pa='Pakk:BAEBLgAECn8YAAIBAAYJ9h7SDAC5AQZoDAAABgBeAGkMAAAFAE4AawwAAAQAQABqDAAAAwBJAGwMAAADAEQA6gwAAAMAWQABAAYJ9h7SDAC5AQZoDAAABgBeAGkMAAAFAE4AawwAAAQAQABqDAAAAwBJAGwMAAADAEQA6gwAAAMAWQAAAA==.Papadefensve:BAEALgADCgEJAQAAAA==.',
Pr='Priff:BAEBLgAECn8vAAQFAAkJTiV/BQDnAgloDAAABwBiAGkMAAAHAFwAawwAAAcAXQBqDAAABQBdAGwMAAAGAFQAbQwAAAUAYwDqDAAABgBgAG4MAAADAGMAbwwAAAEAYgAFAAgJnyV/BQDnAghoDAAAAwBhAGkMAAAEAFgAawwAAAMAXQBqDAAAAgBdAG0MAAAEAGMA6gwAAAIAYABuDAAAAwBjAG8MAAABAGIAFwAHCfchXRgAagIHaAwAAAMAUwBpDAAAAwBcAGsMAAADAEoAagwAAAIAKABsDAAABABUAG0MAAABAF8A6gwAAAMAWgAYAAUJ5SGjEwCPAQVoDAAAAQBiAGsMAAABAEoAagwAAAEAUwBsDAAAAgBUAOoMAAABAFkAAAA=.',
Ra='Razamon:BAEBLgAECn8rAAMLAAkJMSE0CwCNAgloDAAABgBcAGkMAAAFAFMAawwAAAUASgBqDAAABQBUAGwMAAAFAF4AbQwAAAQAVgDqDAAABQBRAG4MAAAFAF4AbwwAAAMASAALAAkJMSE0CwCNAgloDAAAAgBcAGkMAAABAFMAawwAAAIASgBqDAAAAwBUAGwMAAAEAF4AbQwAAAQAVgDqDAAAAgBRAG4MAAAEAF4AbwwAAAMASAAMAAcJgxgiJQA+AQdoDAAABABSAGkMAAAEAEsAawwAAAMAOABqDAAAAgA/AGwMAAABADYA6gwAAAMASwBuDAAAAQAfAAAA.',
Re='Recurse:BAEALgAECgQJBAABLgAFFAgJGwAIAOQTAA==.Relsham:BAEALgAECgkJAgABLgAFFAQJBwAQALEFAA==.',
Ri='Ripwwmonk:BAEALgADCgcJBwABLgAFFAQJDQADAJYfAA==.',
Ro='Roukedhh:BAECLgAFFH8NAAIZAAUJ6BQOJQAoAQVoDAAABABSAGkMAAADAEoAawwAAAIAEgBqDAAAAQADAOoMAAADACYAGQAFCegUDiUAKAEFaAwAAAQAUgBpDAAAAwBKAGsMAAACABIAagwAAAEAAwDqDAAAAwAmAC4ABAp/GgACGQAICachjxYAzwIAGQAICachjxYAzwIAAAA=.',
Ru='Runehaven:BAEALgAECgYJDAABLgAFFAcJGAAaAFMdAA==.',
Sa='Sargala:BAEBLgAECn8XAAIFAAYJTRRCSABEAQZoDAAABgBLAGkMAAAFAC0AawwAAAUAMABqDAAAAgApAGwMAAACADMA6gwAAAMAJwAFAAYJTRRCSABEAQZoDAAABgBLAGkMAAAFAC0AawwAAAUAMABqDAAAAgApAGwMAAACADMA6gwAAAMAJwAAAA==.',
Sc='Scootybooty:BAEALgAECgUJBQAAAA==.Scootyclap:BAEALgADCgQJBAABLgAECgUJBQAHAAAAAA==.Scootysnack:BAEALgADCgcJEAABLgAECgUJBQAHAAAAAA==.Scussy:BAEALgADCgcJBwABLgAECgUJBQAHAAAAAA==.',
Th='Thezdin:BAEBLgAECn8jAAISAAcJYhs9DgCLAQdoDAAABgBYAGkMAAAGAE8AawwAAAYATgBqDAAABAA+AGwMAAADAEsAbQwAAAIAEgDqDAAACABPABIABwliGz0OAIsBB2gMAAAGAFgAaQwAAAYATwBrDAAABgBOAGoMAAAEAD4AbAwAAAMASwBtDAAAAgASAOoMAAAIAE8AAAA=.Thezfu:BAEALgAECgEJAgABLgAECgcJIwASAGIbAA==.',
Ve='Velohm:BAEALgAECgUJBgAAAA==.',
Zi='Zikker:BAEALgADCgcJBwAAAA==.',
Zo='Zoe:BAECLgAFFH8XAAIDAAYJQSCKAQAWAgZoDAAABQBZAGkMAAAFAGMAawwAAAQAUgBsDAAAAQAlAG0MAAABAF8A6gwAAAcAWgADAAYJQSCKAQAWAgZoDAAABQBZAGkMAAAFAGMAawwAAAQAUgBsDAAAAQAlAG0MAAABAF8A6gwAAAcAWgAuAAQKfygAAgMACAlKJn0GAB8DAAMACAlKJn0GAB8DAAAA.Zogle:BAEALgAFFAEJBAABLgAFFAYJFwADAEEgAA==.Zoog:BAEALgAECggJEwABLgAFFAYJFwADAEEgAA==.',
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
