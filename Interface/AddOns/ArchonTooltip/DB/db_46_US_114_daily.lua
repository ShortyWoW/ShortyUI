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

local lookup = {'Paladin-Retribution','DeathKnight-Unholy','Warlock-Affliction','Warlock-Demonology','Priest-Holy','Druid-Feral','Druid-Guardian','Druid-Restoration','Shaman-Elemental','Shaman-Restoration','Shaman-Enhancement','Warlock-Destruction','Priest-Shadow','Unknown-Unknown','Rogue-Assassination','Rogue-Subtlety','Hunter-Survival','Paladin-Holy','DeathKnight-Blood','Priest-Discipline','Hunter-BeastMastery','Mage-Frost','Mage-Arcane','Paladin-Protection','DemonHunter-Vengeance','DemonHunter-Havoc','Warrior-Fury','Warrior-Arms','Monk-Windwalker','Druid-Balance','DemonHunter-Devourer','Monk-Mistweaver','DeathKnight-Frost',}
local provider = {region='US',realm="Gul'dan",name='US',type='daily',zone=46,date='2026-06-18',data={Ae='Aeri:BAAALgAECgYJDAAAAA==.',
Al='Alastormoody:BAAALgADCgcJDAAAAA==.Alelover:BAAALgADCgUJBQAAAA==.Allaria:BAABLgAECn8UAAIBAAcJPw6NvQAMAQdoDAAABQA8AGkMAAAFACcAawwAAAUALwBqDAAAAQAZAGwMAAACABYAbQwAAAEAHADqDAAAAQAUAAEABwk/Do29AAwBB2gMAAAFADwAaQwAAAUAJwBrDAAABQAvAGoMAAABABkAbAwAAAIAFgBtDAAAAQAcAOoMAAABABQAAAA=.Almadíon:BAAALgADCgcJCAAAAA==.',
Am='Amosian:BAAALgADCgIJAgAAAA==.',
An='Ana:BAAALgADCgMJAwAAAA==.',
Ao='Aoemomma:BAAALgADCgcJBwAAAA==.',
Ar='Arin:BAAALgAECgIJAwABLgAFFAMJCgACAEEmAA==.',
As='Asuya:BAAALgADCgIJAwAAAA==.',
Az='Azög:BAAALgADCgUJBQAAAA==.',
Ba='Babysocks:BAAALgAECgYJBgAAAA==.',
Bc='Bc:BAACLgAFFH8HAAMDAAMJ3RmVCgDTAANsDAAAAQAVAG0MAAABAE0A6gwAAAUAYwADAAIJpSKVCgDTAAJtDAAAAQBNAOoMAAABAGMABAACCRkXSI8ApgACbAwAAAEAFQDqDAAABABhAC4ABAp/GwACBAAICfgmMQMAjQMABAAICfgmMQMAjQMAAAA=.',
Be='Beep:BAABLgAECn8lAAIEAAcJRh+JOgAiAgdoDAAABwBVAGkMAAAGAFMAawwAAAYAWABqDAAABgBdAGwMAAAFAE8AbQwAAAEALwDqDAAABgBgAAQABwlGH4k6ACICB2gMAAAHAFUAaQwAAAYAUwBrDAAABgBYAGoMAAAGAF0AbAwAAAUATwBtDAAAAQAvAOoMAAAGAGAAAAA=.',
Bl='Blackthunder:BAAALgAECggJDAAAAA==.',
Bo='Bobert:BAAALgADCgcJBgAAAA==.Bofadz:BAAALgADCgYJBgAAAA==.Boozecruise:BAAALgADCgIJAgAAAA==.Boozedrat:BAAALgAFFAEJAwABLgAFFAYJFgAEAH8WAA==.Bowyn:BAABLgAECn8XAAIFAAYJHhNoOgBSAQZoDAAABAA3AGkMAAAFACYAawwAAAUAJgBqDAAAAwAYAGwMAAADADkA6gwAAAMAUAAFAAYJHhNoOgBSAQZoDAAABAA3AGkMAAAFACYAawwAAAUAJgBqDAAAAwAYAGwMAAADADkA6gwAAAMAUAAAAA==.',
Bu='Bubblnbiotch:BAAALgADCgEJAQAAAA==.Budleaf:BAABLgAECn8aAAQGAAYJlhKSIwDtAAZoDAAABgAoAGkMAAAFADAAawwAAAUAHwBqDAAAAwA3AGwMAAADADwA6gwAAAQAOAAGAAUJ0BKSIwDtAAVoDAAAAQAaAGkMAAABADAAagwAAAEAKgBsDAAAAQA8AOoMAAABADgABwAGCRcMeDsAuAAGaAwAAAUAKABpDAAABAAVAGsMAAAFAB8AagwAAAIANwBsDAAAAgAhAOoMAAACABsACAABCdQGgOoAIwAB6gwAAAEAEQAAAA==.Bunkley:BAABLgAECn8rAAQJAAgJtRFpLwCDAQhoDAAACAA0AGkMAAAHACwAawwAAAgAMQBqDAAABwA7AGwMAAADAE8AbQwAAAEAIwDqDAAABQAnAG4MAAAEABEACQAICbURaS8AgwEIaAwAAAMANABpDAAAAwAsAGsMAAACADEAagwAAAMAOwBsDAAAAwBPAG0MAAABACMA6gwAAAQAJwBuDAAAAgARAAoABgkNDFR5APMABmgMAAAEADkAaQwAAAMAEgBrDAAABQAjAGoMAAAEACMA6gwAAAEACABuDAAAAgAeAAsAAwlNCqgsAJQAA2gMAAABABcAaQwAAAEAHABrDAAAAQAaAAAA.Butterknives:BAAALgAECgEJAQAAAA==.Buttshark:BAAALgADCgcJBwAAAA==.',
By='Byege:BAACLgAFFH8WAAIEAAYJfxZWLgCMAQZoDAAABQBWAGkMAAAEACUAawwAAAIAMwBqDAAAAQAXAOoMAAAJAFUAbgwAAAEAGwAEAAYJfxZWLgCMAQZoDAAABQBWAGkMAAAEACUAawwAAAIAMwBqDAAAAQAXAOoMAAAJAFUAbgwAAAEAGwAuAAQKfycAAwQACQnHH8cYAI8CAAQACQmjH8cYAI8CAAwABQnOF7IbAHABAAAA.',
Ca='Cantfireme:BAAALgAECgYJCgABLgAECgkJQwABADobAA==.Cardhunter:BAAALgADCgYJBgAAAA==.',
Ch='Champilon:BAAALgAECgEJAQAAAA==.Chaoticus:BAAALgAECgYJDQABLgAECggJIgANAJgOAA==.Charizards:BAAALgADCgYJDQAAAA==.Charmahnder:BAAALgAECgIJAgAAAA==.',
Co='Coma:BAAALgAECgEJAQAAAA==.',
Cr='Crunbard:BAAALgAECggJDwAAAA==.',
Cu='Culdan:BAABLgAECn8aAAMMAAYJ+Qn9HADAAAZoDAAABgAdAGkMAAAGABoAawwAAAcAIABqDAAAAgASAGwMAAACABEA6gwAAAMAFgAMAAYJ+Qn9HADAAAZoDAAAAQAdAGkMAAABABoAawwAAAUAIABqDAAAAgASAGwMAAACABEA6gwAAAIAFgAEAAQJlgRY5wCPAARoDAAABQAIAGkMAAAFABMAawwAAAIACgDqDAAAAQAIAAAA.',
Da='Dalirus:BAAALgAECgUJCgABLgAECgkJQwABADobAA==.Danahe:BAAALgAFFAEJAQABLgAFFAIJBAAOAAAAAA==.Darci:BAAALgAECgcJEQABLgAECgQJCAAOAAAAAA==.Darksuaza:BAAALgAECggJEQAAAA==.Darthwizard:BAAALgADCgIJAgAAAA==.Dasbunk:BAAALgAECgYJEAAAAA==.Dayman:BAAALgADCgYJBgAAAA==.',
De='Deadblue:BAABLgAECn87AAIMAAkJ+xniAwBOAgloDAAABwBMAGkMAAAIAEgAawwAAAgANwBqDAAABwAuAGwMAAAHAD8AbQwAAAUAJgDqDAAACQBMAG4MAAAFAFYAbwwAAAMAPwAMAAkJ+xniAwBOAgloDAAABwBMAGkMAAAIAEgAawwAAAgANwBqDAAABwAuAGwMAAAHAD8AbQwAAAUAJgDqDAAACQBMAG4MAAAFAFYAbwwAAAMAPwAAAA==.Deathblows:BAAALgAECgUJCAAAAA==.Deekay:BAAALgADCgcJFAAAAA==.',
Di='Diogee:BAAALgAECgMJBgAAAA==.Dirge:BAABLgAECn8bAAMPAAkJphHQCQCeAQloDAAAAwAsAGkMAAADADUAawwAAAQAPABqDAAAAwAmAGwMAAAEAC4AbQwAAAIAKQDqDAAABAAkAG4MAAADADYAbwwAAAEAGAAPAAgJUBHQCQCeAQhoDAAAAgAsAGkMAAACADUAawwAAAMAPABqDAAAAgAmAGwMAAAEAC4AbQwAAAIAKQDqDAAAAwAkAG4MAAACABwAEAAHCXwHyTQABAEHaAwAAAEADgBpDAAAAQAQAGsMAAABAAAAagwAAAEADwDqDAAAAQAEAG4MAAABADYAbwwAAAEAGAAAAA==.Discipline:BAAALgAECgYJDAABLgAFFAgJJAARACwWAA==.Divinate:BAAALgAECgIJAgAAAA==.',
Dk='Dkpitador:BAAALgADCgEJAQAAAA==.',
Do='Doomhead:BAABLgAECn8YAAICAAgJ2Ah6kwBAAQhoDAAABAASAGkMAAAEABgAawwAAAQAEABqDAAAAwATAGwMAAACABkAbQwAAAEAHwDqDAAABQAaAG4MAAABABAAAgAICdgIepMAQAEIaAwAAAQAEgBpDAAABAAYAGsMAAAEABAAagwAAAMAEwBsDAAAAgAZAG0MAAABAB8A6gwAAAUAGgBuDAAAAQAQAAAA.',
Dr='Drakki:BAAALgADCgUJBQAAAA==.Dreadfaith:BAAALgAECgYJBgAAAA==.',
Du='Durzii:BAACLgAFFH8FAAISAAIJuiLlMACxAAJoDAAAAwBVAGkMAAACAFwAEgACCboi5TAAsQACaAwAAAMAVQBpDAAAAgBcAC4ABAp/GQADEgAJCaogoRIAfQIAEgAICd4hoRIAfQIAAQABCe0ZcmkBTQAAAS4ABRQECQwAEwAcEAA=.',
Ea='Eatmybeef:BAAALgADCgYJCgAAAA==.',
Ex='Extinctionus:BAAALgAECgYJCwAAAA==.',
Fe='Fernn:BAAALgADCgQJBAAAAA==.',
Fi='Fia:BAABLgAECn84AAMCAAkJHRMdVwDAAQloDAAACAA5AGkMAAAIADMAawwAAAcAQQBqDAAABwAsAGwMAAAHADkAbQwAAAUAOQDqDAAABwAzAG4MAAAFACAAbwwAAAIAEgACAAkJwQ8dVwDAAQloDAAABwAzAGkMAAAHADMAawwAAAYANQBqDAAABgAsAGwMAAAGACkAbQwAAAQAKwDqDAAABgAdAG4MAAAEACAAbwwAAAIAEgATAAgJyxLBGgCHAQhoDAAAAQA5AGkMAAABACQAawwAAAEAQQBqDAAAAQArAGwMAAABADkAbQwAAAEAOQDqDAAAAQAzAG4MAAABAAsAAAA=.',
Fo='Fondra:BAAALgAECgYJBgAAAA==.',
Fu='Furor:BAAALgAECgQJBAABLgAECgkJGwAPAKYRAA==.',
Ge='Genaro:BAAALgAECgIJBwAAAA==.',
Gi='Gibraltar:BAAALgADCgUJBQAAAA==.',
Go='Gokujang:BAAALgAECgcJDgABLgAECgkJJwAUAPQZAA==.Goremont:BAAALgADCgQJBQAAAA==.Gorlok:BAAALgAECgUJBQAAAA==.',
Gr='Greendot:BAACLgAFFH8TAAIIAAQJ1RU+KQAXAQRoDAAABgBGAGkMAAAGADQAawwAAAIAGQDqDAAABQBLAAgABAnVFT4pABcBBGgMAAAGAEYAaQwAAAYANABrDAAAAgAZAOoMAAAFAEsALgAECn8uAAIIAAkJlyLEAwCFAwAIAAkJlyLEAwCFAwAAAA==.',
Gu='Gulvid:BAACLgAFFH8HAAIEAAIJlx1XlACZAAJoDAAAAwBYAOoMAAAEAD8ABAACCZcdV5QAmQACaAwAAAMAWADqDAAABAA/AC4ABAp/GAADBAAHCWQhQVgAlAEABAAHCWQhQVgAlAEADAABCQAAqlwAWAAAAS4ABRQICRwABAA+FAA=.',
Ha='Haluak:BAABLgAECn8rAAIJAAkJtRm3FQA5AgloDAAABwBBAGkMAAAIAEsAawwAAAcASgBqDAAABQBOAGwMAAADADsAbQwAAAIAKADqDAAABwBXAG4MAAADADkAbwwAAAEAQgAJAAkJtRm3FQA5AgloDAAABwBBAGkMAAAIAEsAawwAAAcASgBqDAAABQBOAGwMAAADADsAbQwAAAIAKADqDAAABwBXAG4MAAADADkAbwwAAAEAQgAAAA==.',
He='Healthyself:BAAALgAECgYJCwAAAA==.',
Ho='Hothawk:BAAALgAECgYJBwABLgAECgkJQwABADobAA==.Houndtamer:BAABLgAECn8/AAIVAAkJ0RZRRQDRAQloDAAACgBFAGkMAAAKAEEAawwAAAkALgBqDAAACQA+AGwMAAAGAC0AbQwAAAIAJgDqDAAACgBBAG4MAAAGAEgAbwwAAAEAQAAVAAkJ0RZRRQDRAQloDAAACgBFAGkMAAAKAEEAawwAAAkALgBqDAAACQA+AGwMAAAGAC0AbQwAAAIAJgDqDAAACgBBAG4MAAAGAEgAbwwAAAEAQAAAAA==.',
Hp='Hpyflowers:BAAALgADCgQJBAAAAA==.',
Hr='Hruoth:BAAALgAECgYJBgAAAA==.',
Ic='Iceshooting:BAAALgAECgQJBwAAAA==.',
Is='Ishtar:BAABLgAECn8ZAAMWAAYJ9BzVhADIAQZoDAAABQBFAGkMAAAFAFEAawwAAAQATQBqDAAABABMAGwMAAAEAFMA6gwAAAMAOgAWAAYJCRnVhADIAQZoDAAAAwAqAGkMAAAFAFEAawwAAAMATQBqDAAABABMAGwMAAAEAFMA6gwAAAIAIwAXAAMJzRkuDwDQAANoDAAAAgBFAGsMAAABAEYA6gwAAAEAOgAAAA==.',
It='Itshela:BAACLgAFFH8bAAMCAAcJfxjJKADGAQdoDAAABgBRAGkMAAAEAFUAawwAAAMAJgBqDAAABgA2AGwMAAACACAAbQwAAAEAPgDqDAAABQBMAAIABgl/GMkoAMYBBmgMAAAGAFEAaQwAAAQAVQBrDAAAAwAmAGwMAAACACAAbQwAAAEAPgDqDAAABQBMABMAAQkAAB1ZAAAAAWoMAAAGADYALgAECn8bAAICAAcJOCPrTQAJAgACAAcJOCPrTQAJAgAAAA==.',
Ja='Jayrad:BAABLgAECn8VAAMEAAgJSgnngQA1AQhoDAAABAAaAGkMAAADABMAawwAAAIADQBqDAAAAQA1AGwMAAABAA8AbQwAAAEAGADqDAAACAAiAG4MAAABACEABAAICUoJ54EANQEIaAwAAAMAGgBpDAAAAgATAGsMAAABAA0AagwAAAEANQBsDAAAAQAPAG0MAAABABgA6gwAAAcAIgBuDAAAAQAhAAMABAlhBAYaAKcABGgMAAABABIAaQwAAAEADQBrDAAAAQAEAOoMAAABAAgAAAA=.',
Je='Jehnovah:BAAALgADCgMJAwAAAA==.Jellybeanz:BAAALgADCggJDQAAAA==.',
Jo='Jordybear:BAAALgAECgQJBAAAAA==.Jorkoh:BAAALgAECgMJBgAAAA==.',
Ju='Juicer:BAAALgADCgMJBgAAAA==.',
Ka='Kaiige:BAAALgAECgQJBAAAAA==.Kairos:BAAALgAECgYJCgAAAA==.Kanê:BAAALgAFFAMJAwAAAA==.',
Ke='Kehlayr:BAAALgADCgMJAwAAAA==.Keiiry:BAAALgADCgMJAwAAAA==.Kenshinth:BAABLgAECn8WAAIWAAcJERRfgAB2AQdoDAAABQA3AGkMAAADAEAAawwAAAMAOgBqDAAAAgBRAGwMAAACAC4A6gwAAAYAOgBuDAAAAQAZABYABwkRFF+AAHYBB2gMAAAFADcAaQwAAAMAQABrDAAAAwA6AGoMAAACAFEAbAwAAAIALgDqDAAABgA6AG4MAAABABkAAAA=.Kethrym:BAAALgAECgIJAgAAAA==.',
Kh='Khanor:BAAALgAECgYJEQAAAA==.',
Ki='Kiltro:BAAALgAECgQJBgAAAA==.Kimchichi:BAABLgAECn8nAAIBAAkJ2yAqDQD7AgloDAAABwBeAGkMAAAGAEsAawwAAAcAWABqDAAABQBUAGwMAAADAFQAbQwAAAIAVwDqDAAABABEAG4MAAAEAFEAbwwAAAEAXAABAAkJ2yAqDQD7AgloDAAABwBeAGkMAAAGAEsAawwAAAcAWABqDAAABQBUAGwMAAADAFQAbQwAAAIAVwDqDAAABABEAG4MAAAEAFEAbwwAAAEAXAAAAA==.Kintaro:BAAALgADCgYJDwAAAA==.Kissmybubble:BAAALgADCgEJAQAAAA==.',
Ko='Kogorko:BAAALgAECgMJBQAAAA==.',
Kr='Kry:BAAALgAECgIJAgAAAA==.',
['Kë']='Këarra:BAAALgAECgQJBwAAAA==.',
La='Labotimizer:BAAALgAECggJDwAAAA==.Lapaladin:BAAALgADCgYJBwAAAA==.Lapriestess:BAAALgAECgYJEQAAAA==.Latoya:BAABLgAFFH8FAAIWAAMJPweAjQC+AANoDAAAAgAVAGkMAAACAAkA6gwAAAEAGAAWAAMJPweAjQC+AANoDAAAAgAVAGkMAAACAAkA6gwAAAEAGAAAAA==.',
Le='Lemontea:BAAALgAFFAEJAQABLgAFFAQJEwAIANUVAA==.',
Li='Lilbeemo:BAAALgAECgUJCgAAAA==.Lilyana:BAAALgAECgYJCwAAAA==.Liongs:BAAALgAECgcJCgABLgAECgcJFgAWABEUAA==.Litdk:BAAALgADCgUJBQAAAA==.Litharidk:BAABLgAECn8dAAICAAgJ5B8ZNAAuAghoDAAABgBZAGkMAAAHAFkAawwAAAUATQBqDAAAAwBdAGwMAAACAEoAbQwAAAEATgDqDAAABABXAG8MAAABAEoAAgAICeQfGTQALgIIaAwAAAYAWQBpDAAABwBZAGsMAAAFAE0AagwAAAMAXQBsDAAAAgBKAG0MAAABAE4A6gwAAAQAVwBvDAAAAQBKAAAA.',
Lo='Lolmasterr:BAAALgAECgEJAQAAAA==.Lotion:BAAALgAECgEJAgAAAA==.Loudog:BAAALgAECgYJBwAAAA==.Loxyblue:BAAALgAECgQJBAAAAA==.',
Lu='Luckyxpain:BAABLgAECn9DAAMBAAkJOht8KgBXAgloDAAACwBRAGkMAAAIAD0AawwAAAoARQBqDAAACABcAGwMAAAMAEMAbQwAAAUAXgDqDAAABwBLAG4MAAAEAE8AbwwAAAIAGwABAAkJBRt8KgBXAgloDAAABwBRAGkMAAAGAD0AawwAAAcARQBqDAAABQBcAGwMAAAFAD8AbQwAAAMAXgDqDAAAAwBLAG4MAAAEAE8AbwwAAAIAGwAYAAcJLBGHGwA7AQdoDAAABAAVAGkMAAACADQAawwAAAMAHwBqDAAAAwAxAGwMAAAHAEMAbQwAAAIANgDqDAAABAAkAAAA.',
Ly='Lykos:BAAALgAECgIJAgAAAA==.',
Ma='Madoff:BAAALgAECgQJCAAAAA==.Makok:BAABLgAECn8nAAMZAAkJDxkCBgA7AgloDAAABgBJAGkMAAAFAEUAawwAAAUAMwBqDAAABAA2AGwMAAADAEYAbQwAAAIAOwDqDAAACAA7AG4MAAAEAEUAbwwAAAIAPAAZAAkJDxkCBgA7AgloDAAABgBJAGkMAAAFAEUAawwAAAUAMwBqDAAABAA2AGwMAAADAEYAbQwAAAIAOwDqDAAABwA7AG4MAAAEAEUAbwwAAAIAPAAaAAEJ7AnycQAzAAHqDAAAAQAZAAAA.Malaise:BAAALgAECggJCgABLgAECgkJLgAbAHwgAA==.',
Me='Melancholic:BAABLgAECn8uAAMbAAkJfCBICQDNAgloDAAACABhAGkMAAAIAFYAawwAAAcARwBqDAAABgBaAGwMAAAEAFYAbQwAAAEASwDqDAAACABhAG4MAAADAE8AbwwAAAEARwAbAAkJfCBICQDNAgloDAAABwBhAGkMAAAIAFYAawwAAAcARwBqDAAABgBaAGwMAAAEAFYAbQwAAAEASwDqDAAACABhAG4MAAADAE8AbwwAAAEARwAcAAEJxQTEhAAlAAFoDAAAAQAMAAAA.Mellisa:BAABLgAECn8fAAMCAAkJcxErcwB9AQloDAAABwBIAGkMAAAEADUAawwAAAUANwBqDAAAAwBEAGwMAAACABgAbQwAAAEAEgDqDAAABwBNAG4MAAABABIAbwwAAAEAJAACAAgJ2w8rcwB9AQhoDAAABgBIAGkMAAADABAAawwAAAQANwBqDAAAAwBEAGwMAAACABgAbQwAAAEAEgDqDAAABgBNAG4MAAABABIAEwAFCXUTqSoAAwEFaAwAAAEALgBpDAAAAQA1AGsMAAABADQA6gwAAAEAPABvDAAAAQAkAAAA.Memory:BAAALgAECgEJBAAAAA==.',
Mi='Milkingman:BAAALgAECgYJBAAAAA==.',
Mo='Mooshmoo:BAAALgAECgEJAQAAAA==.Morpheus:BAAALgAECgYJBgABLgAFFAMJBwAdABUeAA==.',
Mu='Murog:BAABLgAECn8dAAMKAAgJSQ20TwBzAQhoDAAAAwAvAGkMAAADADEAawwAAAMAEQBqDAAABAArAGwMAAAFADIAbQwAAAIAEgDqDAAABwAgAG4MAAACAAwACgAICUkNtE8AcwEIaAwAAAIALwBpDAAAAgAxAGsMAAACABEAagwAAAMAKwBsDAAABAAyAG0MAAACABIA6gwAAAYAIABuDAAAAgAMAAsABgk9A+spAKkABmgMAAABAAgAaQwAAAEACQBrDAAAAQAKAGoMAAABAAYAbAwAAAEACADqDAAAAQAEAAAA.',
Na='Nazarite:BAAALgAECgYJDwAAAA==.',
Ne='Nephlok:BAAALgAECggJCAAAAA==.',
Ni='Nightdisco:BAAALgAECgQJBAAAAA==.',
No='Noctyra:BAAALgAECgQJCAAAAA==.Nomaana:BAAALgAECgMJAwAAAA==.Norael:BAAALgADCgIJAgAAAA==.',
Og='Ogthunder:BAAALgAECgEJAQAAAA==.',
Op='Ophellia:BAAALgAECgEJAQAAAA==.',
Pu='Pureformance:BAAALgADCgcJBwABLgAFFAgJJwAIAFUjAA==.Purrformance:BAACLgAFFH8nAAMIAAgJVSMeAgAsAwhoDAAACABgAGkMAAAIAGEAawwAAAYAXABqDAAABABNAGwMAAACAF0AbQwAAAEAUADqDAAACQBiAG4MAAABAFYACAAICVUjHgIALAMIaAwAAAcAYABpDAAACABhAGsMAAAGAFwAagwAAAQATQBsDAAAAgBdAG0MAAABAFAA6gwAAAkAYgBuDAAAAQBWAB4AAQnDBoFRADQAAWgMAAABABEALgAECn8iAAIIAAkJoiUMAQCnAwAIAAkJoiUMAQCnAwAAAA==.',
Py='Pyrophobiac:BAACLgAFFH8fAAMEAAgJDxnsEQArAghoDAAABQBLAGkMAAAEABgAawwAAAQAOgBqDAAAAgAbAGwMAAAEAFgAbQwAAAMAJwDqDAAABwBPAG4MAAACAFQABAAICQ8Z7BEAKwIIaAwAAAUASwBpDAAAAwAYAGsMAAACADoAagwAAAIAGwBsDAAABABYAG0MAAADACcA6gwAAAcATwBuDAAAAgBUAAwAAglYAkoPAH8AAmkMAAABAAcAawwAAAIABAAuAAQKfyMAAwQACQnaI4ADAIcDAAQACQmYI4ADAIcDAAwABwmhHUcHAFQCAAAA.',
Ra='Ra:BAABLgAECn8qAAIaAAgJbh/+CwBnAghoDAAABgBSAGkMAAAIAFwAawwAAAgAXABqDAAABgBQAGwMAAAEAFAAbQwAAAIARQDqDAAABQBQAG4MAAADAEIAGgAICW4f/gsAZwIIaAwAAAYAUgBpDAAACABcAGsMAAAIAFwAagwAAAYAUABsDAAABABQAG0MAAACAEUA6gwAAAUAUABuDAAAAwBCAAAA.Radagast:BAACLgAFFH8WAAIfAAQJNw2pAwCDAARoDAAABwAzAGkMAAAGACIAawwAAAMAGgDqDAAABgAXAB8ABAk3DakDAIMABGgMAAAHADMAaQwAAAYAIgBrDAAAAwAaAOoMAAAGABcALgAECn8xAAMfAAgJEBpjMQAAAgAfAAgJMxhjMQAAAgAaAAcJjhMGJABYAQAAAA==.Radditz:BAAALgAECgYJCwAAAA==.Rafiki:BAAALgAECgEJAQAAAA==.Rand:BAAALgADCgcJDgAAAA==.',
Ri='Riv:BAAALgAECgMJAwAAAA==.',
Ro='Ronni:BAAALgAECgUJCgAAAA==.Roxyfox:BAAALgAECgYJCwAAAA==.Royvaz:BAABLgAECn8UAAMKAAkJtRV7IABMAgloDAAAAwBLAGkMAAAEAFEAawwAAAIAIwBqDAAAAwA8AGwMAAACADIAbQwAAAEAHwDqDAAAAwBGAG4MAAABADAAbwwAAAEALQAKAAkJtRV7IABMAgloDAAAAwBLAGkMAAADAFEAawwAAAEAIwBqDAAAAgA8AGwMAAABADIAbQwAAAEAHwDqDAAAAwBGAG4MAAABADAAbwwAAAEALQALAAQJWgrgLACSAARpDAAAAQALAGsMAAABAAkAagwAAAEAEgBsDAAAAQA5AAAA.',
Sa='Salea:BAAALgAECgIJAgAAAA==.Sarryn:BAAALgADCgcJBwAAAA==.',
Sc='Scale:BAAALgAECgMJAwAAAA==.Schwiifty:BAAALgAECgMJDgAAAA==.',
Se='Serik:BAAALgADCgEJAQAAAA==.',
Sh='Shadorodo:BAAALgADCgIJAgAAAA==.Shakaboom:BAAALgAFFAEJAQAAAA==.Shakazoom:BAAALgAECgQJBAAAAA==.Sheffers:BAAALgADCgEJAQAAAA==.Sheffurs:BAABLgAECn87AAIHAAkJ0gOFOwC4AAloDAAABwAEAGkMAAAIAAYAawwAAAgABQBqDAAABwAGAGwMAAAHAAkAbQwAAAUADQDqDAAACQAcAG4MAAAFAAQAbwwAAAMABQAHAAkJ0gOFOwC4AAloDAAABwAEAGkMAAAIAAYAawwAAAgABQBqDAAABwAGAGwMAAAHAAkAbQwAAAUADQDqDAAACQAcAG4MAAAFAAQAbwwAAAMABQAAAA==.Shepardl:BAACLgAFFH8mAAISAAgJYyUDAQA3AwhoDAAABwBdAGkMAAAHAGEAawwAAAUAZABqDAAABgBNAGwMAAAEAGMAbQwAAAEAYgDqDAAABwBjAG4MAAABAGMAEgAICWMlAwEANwMIaAwAAAcAXQBpDAAABwBhAGsMAAAFAGQAagwAAAYATQBsDAAABABjAG0MAAABAGIA6gwAAAcAYwBuDAAAAQBjAC4ABAp/IQACEgAICeQmGgEAgQMAEgAICeQmGgEAgQMAAAA=.Shredemdown:BAAALgAECgcJCQAAAA==.Shárkbait:BAAALgAECgEJAQABLgAFFAMJBwATAB4LAA==.',
Sk='Skadoosher:BAAALgAECgUJBQAAAA==.Skyratt:BAAALgAECgEJAgAAAA==.',
Sl='Sleepielight:BAAALgAFFAIJBAAAAA==.',
Sm='Smackemz:BAAALgAECgYJCQAAAA==.Smacmywand:BAAALgAECgIJBgAAAA==.',
So='Sollasi:BAAALgADCgMJBgAAAA==.Sortie:BAABLgAECn87AAMSAAkJWA0xLQCqAQloDAAABwAhAGkMAAAIAAwAawwAAAgAMQBqDAAABwAPAGwMAAAHACQAbQwAAAUAGQDqDAAACQA0AG4MAAAFABMAbwwAAAMAPgASAAkJWA0xLQCqAQloDAAAAwAhAGkMAAADAAwAawwAAAQAMQBqDAAAAwAPAGwMAAAEACQAbQwAAAMAGQDqDAAAAwA0AG4MAAABABMAbwwAAAMAPgABAAgJCwoZpwAtAQhoDAAABAAvAGkMAAAFACMAawwAAAQAFABqDAAABAAkAGwMAAADAA4AbQwAAAIAEwDqDAAABgAaAG4MAAAEABAAAAA=.',
Sp='Spookybolt:BAAALgAECgEJAQAAAA==.Spoons:BAAALgAECgQJBAABLgAFFAUJFgAgAEocAA==.Spyromu:BAAALgAECgUJCwAAAA==.',
St='Stealman:BAAALgADCgcJBwAAAA==.Steeleman:BAAALgADCgQJAgAAAA==.',
Su='Succinic:BAAALgAECggJEAAAAA==.Suffer:BAAALgAECgUJCAAAAA==.',
Sw='Swiss:BAABLgAECn8bAAISAAgJrw1ONACsAQhoDAAABAA3AGkMAAAEACIAawwAAAQAKwBqDAAAAwAlAGwMAAADABoAbQwAAAMAEwDqDAAAAwA5AG4MAAADAAcAEgAICa8NTjQArAEIaAwAAAQANwBpDAAABAAiAGsMAAAEACsAagwAAAMAJQBsDAAAAwAaAG0MAAADABMA6gwAAAMAOQBuDAAAAwAHAAAA.',
Sy='Sylphvaria:BAAALgADCgUJBQAAAA==.Syren:BAAALgADCgcJBgAAAA==.',
Te='Tegridy:BAABLgAECn8VAAIVAAYJpBFVhQA0AQZoDAAABAA8AGkMAAAEADIAawwAAAQAIABqDAAAAQAuAGwMAAABACEA6gwAAAcALwAVAAYJpBFVhQA0AQZoDAAABAA8AGkMAAAEADIAawwAAAQAIABqDAAAAQAuAGwMAAABACEA6gwAAAcALwAAAA==.Teko:BAAALgADCgYJCwAAAA==.',
Th='Thegoose:BAAALgAECgIJAgAAAA==.Themans:BAAALgAECgYJDgAAAA==.Thunderrod:BAABLgAECn8nAAIVAAgJtBfOPgC0AQhoDAAABwBFAGkMAAAGAEwAawwAAAcARQBqDAAABgBRAGwMAAAFAEcAbQwAAAEAEADqDAAABAAwAG4MAAADAEgAFQAICbQXzj4AtAEIaAwAAAcARQBpDAAABgBMAGsMAAAHAEUAagwAAAYAUQBsDAAABQBHAG0MAAABABAA6gwAAAQAMABuDAAAAwBIAAAA.',
Ti='Tim:BAAALgAECgMJAwAAAA==.',
To='To:BAAALgAECgIJAgAAAA==.Tovisar:BAAALgAECgMJCQAAAA==.',
Tr='Traessa:BAAALgADCgYJBgAAAA==.',
Tu='Turkturkletn:BAAALgADCgcJEQAAAA==.',
Tw='Twogg:BAAALgAECgYJDgAAAA==.',
Ug='Ugin:BAAALgADCgYJBgAAAA==.Uglykasanova:BAAALgAECgYJEQAAAA==.',
Ul='Ulfrir:BAAALgAECgcJDQAAAA==.',
Va='Vastian:BAAALgAECgUJDgAAAA==.Vaynard:BAAALgAECgQJBAAAAA==.',
Vi='Violet:BAAALgAECgMJBQAAAA==.Vitre:BAAALgAECgUJBwAAAA==.',
Wa='Walkthrew:BAAALgAECgcJBwAAAA==.Wanshi:BAAALgAECgcJBgAAAA==.Waq:BAAALgAECggJEwAAAA==.',
We='Wexew:BAACLgAFFH8FAAMLAAIJEx5FEQC0AAJoDAAAAQBMAOoMAAAEAE0ACwACCRMeRREAtAACaAwAAAEATADqDAAAAQBNAAkAAQmeC+BZADYAAeoMAAADAB0ALgAECn8bAAMLAAkJBhxiBwBXAgALAAkJ7xpiBwBXAgAJAAUJChW+SgAdAQAAAA==.Wexwex:BAAALgAFFAIJAwABLgAFFAIJBQALABMeAA==.Wexxew:BAAALgAFFAEJAQABLgAFFAIJBQALABMeAA==.',
Wi='Wishing:BAABLgAECn8bAAISAAgJlBSTHgAOAghoDAAABABWAGkMAAAEACsAawwAAAQARwBqDAAABABGAGwMAAADAEIAbQwAAAEABQDqDAAABgA8AG4MAAABABEAEgAICZQUkx4ADgIIaAwAAAQAVgBpDAAABAArAGsMAAAEAEcAagwAAAQARgBsDAAAAwBCAG0MAAABAAUA6gwAAAYAPABuDAAAAQARAAAA.',
Wu='Wundertot:BAAALgAECgYJBgABLgAFFAQJCwAWAN8NAA==.Wunderwazard:BAACLgAFFH8LAAIWAAQJ3w0uawANAQRoDAAABAA0AGkMAAADACEAawwAAAEABQDqDAAAAwAxABYABAnfDS5rAA0BBGgMAAAEADQAaQwAAAMAIQBrDAAAAQAFAOoMAAADADEALgAECn8sAAIWAAkJVR9zIwCPAgAWAAkJVR9zIwCPAgAAAA==.',
Xe='Xevikan:BAABLgAECn8bAAMCAAcJDBVFiQBSAQdoDAAABgBHAGkMAAAFADYAawwAAAUASwBqDAAAAgAnAGwMAAACACkAbQwAAAIAHADqDAAABQAzAAIABwkMFUWJAFIBB2gMAAAFAEcAaQwAAAUANgBrDAAABQBLAGoMAAACACcAbAwAAAIAKQBtDAAAAgAcAOoMAAAFADMAIQABCR8I+z8AJwABaAwAAAEAFAAAAA==.',
Ya='Yadead:BAAALgAECgcJDQAAAA==.',
Za='Zangief:BAAALgADCgYJBwAAAA==.Zaylen:BAAALgAECgYJEwABLgAFFAMJBwAdABUeAA==.',
Ze='Zendjin:BAAALgADCgYJDQAAAA==.Zenlore:BAAALgADCgYJBgAAAA==.',
Zi='Zistormstout:BAABLgAECn9AAAIJAAkJ0xzGEwBOAgloDAAACgBIAGkMAAAKAD4AawwAAAkARgBqDAAACQBMAGwMAAAGAFsAbQwAAAIAOwDqDAAACwBNAG4MAAAGAFsAbwwAAAEAQQAJAAkJ0xzGEwBOAgloDAAACgBIAGkMAAAKAD4AawwAAAkARgBqDAAACQBMAGwMAAAGAFsAbQwAAAIAOwDqDAAACwBNAG4MAAAGAFsAbwwAAAEAQQAAAA==.',
Zu='Zuhgonemad:BAAALgAECgQJBgAAAA==.',
['Äl']='Älektra:BAABLgAECn8gAAIfAAgJvATxngDlAAhoDAAABQAIAGkMAAAGAAwAawwAAAYADQBqDAAABAANAGwMAAADAAkAbQwAAAIADADqDAAABAAJAG8MAAACABIAHwAICbwE8Z4A5QAIaAwAAAUACABpDAAABgAMAGsMAAAGAA0AagwAAAQADQBsDAAAAwAJAG0MAAACAAwA6gwAAAQACQBvDAAAAgASAAAA.',
['Ñe']='Ñeph:BAAALgAECgkJDgAAAA==.',
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
