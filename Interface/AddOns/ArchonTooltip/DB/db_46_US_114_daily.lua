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

local lookup = {'DeathKnight-Unholy','Warlock-Affliction','Warlock-Demonology','Priest-Holy','Druid-Feral','Druid-Guardian','Druid-Restoration','Shaman-Elemental','Shaman-Restoration','Shaman-Enhancement','Warlock-Destruction','Paladin-Retribution','Priest-Shadow','Unknown-Unknown','Rogue-Assassination','Rogue-Subtlety','Hunter-Survival','Paladin-Holy','DeathKnight-Blood','Priest-Discipline','Hunter-BeastMastery','Mage-Frost','Mage-Arcane','Paladin-Protection','DemonHunter-Vengeance','DemonHunter-Havoc','Warrior-Fury','Warrior-Arms','Monk-Windwalker','Druid-Balance','DemonHunter-Devourer','Monk-Mistweaver','DeathKnight-Frost',}
local provider = {region='US',realm="Gul'dan",name='US',type='daily',zone=46,date='2026-06-17',data={Ae='Aeri:BAAALgAECgYJDAAAAA==.',
Al='Alastormoody:BAAALgADCgcJDAAAAA==.Alelover:BAAALgADCgUJBQAAAA==.Allaria:BAAALgAECgYJEwAAAA==.Almadíon:BAAALgADCgcJCAAAAA==.',
Am='Amosian:BAAALgADCgIJAgAAAA==.',
An='Ana:BAAALgADCgMJAwAAAA==.',
Ao='Aoemomma:BAAALgADCgcJBwAAAA==.',
Ar='Arin:BAAALgAECgIJAwABLgAFFAMJCgABAEEmAA==.',
As='Asuya:BAAALgADCgIJAwAAAA==.',
Az='Azög:BAAALgADCgUJBQAAAA==.',
Ba='Babysocks:BAAALgAECgYJBgAAAA==.',
Bc='Bc:BAACLgAFFH8HAAMCAAMJ3RmNCgDTAANsDAAAAQAVAG0MAAABAE0A6gwAAAUAYwACAAIJpSKNCgDTAAJtDAAAAQBNAOoMAAABAGMAAwACCRkXDo8ApgACbAwAAAEAFQDqDAAABABhAC4ABAp/GwACAwAICfgmMQMAjQMAAwAICfgmMQMAjQMAAAA=.',
Be='Beep:BAABLgAECn8lAAIDAAcJRh+JOgAiAgdoDAAABwBVAGkMAAAGAFMAawwAAAYAWABqDAAABgBdAGwMAAAFAE8AbQwAAAEALwDqDAAABgBgAAMABwlGH4k6ACICB2gMAAAHAFUAaQwAAAYAUwBrDAAABgBYAGoMAAAGAF0AbAwAAAUATwBtDAAAAQAvAOoMAAAGAGAAAAA=.',
Bl='Blackthunder:BAAALgAECggJDAAAAA==.',
Bo='Bobert:BAAALgADCgcJBgAAAA==.Bofadz:BAAALgADCgYJBgAAAA==.Boozecruise:BAAALgADCgIJAgAAAA==.Boozedrat:BAAALgAFFAEJAwABLgAFFAYJFgADAH8WAA==.Bowyn:BAABLgAECn8XAAIEAAYJHhNoOgBSAQZoDAAABAA3AGkMAAAFACYAawwAAAUAJgBqDAAAAwAYAGwMAAADADkA6gwAAAMAUAAEAAYJHhNoOgBSAQZoDAAABAA3AGkMAAAFACYAawwAAAUAJgBqDAAAAwAYAGwMAAADADkA6gwAAAMAUAAAAA==.',
Bu='Bubblnbiotch:BAAALgADCgEJAQAAAA==.Budleaf:BAABLgAECn8aAAQFAAYJlhKHIwDtAAZoDAAABgAoAGkMAAAFADAAawwAAAUAHwBqDAAAAwA3AGwMAAADADwA6gwAAAQAOAAFAAUJ0BKHIwDtAAVoDAAAAQAaAGkMAAABADAAagwAAAEAKgBsDAAAAQA8AOoMAAABADgABgAGCRcMbjsAuAAGaAwAAAUAKABpDAAABAAVAGsMAAAFAB8AagwAAAIANwBsDAAAAgAhAOoMAAACABsABwABCdQGY+oAIwAB6gwAAAEAEQAAAA==.Bunkley:BAABLgAECn8rAAQIAAgJtRFfLwCDAQhoDAAACAA0AGkMAAAHACwAawwAAAgAMQBqDAAABwA7AGwMAAADAE8AbQwAAAEAIwDqDAAABQAnAG4MAAAEABEACAAICbURXy8AgwEIaAwAAAMANABpDAAAAwAsAGsMAAACADEAagwAAAMAOwBsDAAAAwBPAG0MAAABACMA6gwAAAQAJwBuDAAAAgARAAkABgkNDEB5APMABmgMAAAEADkAaQwAAAMAEgBrDAAABQAjAGoMAAAEACMA6gwAAAEACABuDAAAAgAeAAoAAwlNCpUsAJQAA2gMAAABABcAaQwAAAEAHABrDAAAAQAaAAAA.Butterknives:BAAALgAECgEJAQAAAA==.Buttshark:BAAALgADCgcJBwAAAA==.',
By='Byege:BAACLgAFFH8WAAIDAAYJfxYvLgCMAQZoDAAABQBWAGkMAAAEACUAawwAAAIAMwBqDAAAAQAXAOoMAAAJAFUAbgwAAAEAGwADAAYJfxYvLgCMAQZoDAAABQBWAGkMAAAEACUAawwAAAIAMwBqDAAAAQAXAOoMAAAJAFUAbgwAAAEAGwAuAAQKfycAAwMACQnHH8MYAI8CAAMACQmjH8MYAI8CAAsABQnOF7IbAHABAAAA.',
Ca='Cantfireme:BAAALgAECgYJCQABLgAECgkJQwAMADobAA==.Cardhunter:BAAALgADCgYJBgAAAA==.',
Ch='Champilon:BAAALgAECgEJAQAAAA==.Chaoticus:BAAALgAECgYJDQABLgAECggJIgANAJgOAA==.Charizards:BAAALgADCgYJDQAAAA==.Charmahnder:BAAALgAECgIJAgAAAA==.',
Co='Coma:BAAALgAECgEJAQAAAA==.',
Cr='Crunbard:BAAALgAECggJDwAAAA==.',
Cu='Culdan:BAABLgAECn8aAAMLAAYJ+Qn8HADAAAZoDAAABgAdAGkMAAAGABoAawwAAAcAIABqDAAAAgASAGwMAAACABEA6gwAAAMAFgALAAYJ+Qn8HADAAAZoDAAAAQAdAGkMAAABABoAawwAAAUAIABqDAAAAgASAGwMAAACABEA6gwAAAIAFgADAAQJlgQu5wCPAARoDAAABQAIAGkMAAAFABMAawwAAAIACgDqDAAAAQAIAAAA.',
Da='Dalirus:BAAALgAECgUJCgABLgAECgkJQwAMADobAA==.Danahe:BAAALgAFFAEJAQABLgAFFAIJBAAOAAAAAA==.Darci:BAAALgAECgcJEQABLgAECgQJCAAOAAAAAA==.Darksuaza:BAAALgAECggJEQAAAA==.Darthwizard:BAAALgADCgIJAgAAAA==.Dasbunk:BAAALgAECgYJDwAAAA==.Dayman:BAAALgADCgYJBgAAAA==.',
De='Deadblue:BAABLgAECn87AAILAAkJ+xngAwBOAgloDAAABwBMAGkMAAAIAEgAawwAAAgANwBqDAAABwAuAGwMAAAHAD8AbQwAAAUAJgDqDAAACQBMAG4MAAAFAFYAbwwAAAMAPwALAAkJ+xngAwBOAgloDAAABwBMAGkMAAAIAEgAawwAAAgANwBqDAAABwAuAGwMAAAHAD8AbQwAAAUAJgDqDAAACQBMAG4MAAAFAFYAbwwAAAMAPwAAAA==.Deathblows:BAAALgAECgUJCAAAAA==.Deekay:BAAALgADCgcJFAAAAA==.',
Di='Diogee:BAAALgAECgMJBgAAAA==.Dirge:BAABLgAECn8bAAMPAAkJphHPCQCeAQloDAAAAwAsAGkMAAADADUAawwAAAQAPABqDAAAAwAmAGwMAAAEAC4AbQwAAAIAKQDqDAAABAAkAG4MAAADADYAbwwAAAEAGAAPAAgJUBHPCQCeAQhoDAAAAgAsAGkMAAACADUAawwAAAMAPABqDAAAAgAmAGwMAAAEAC4AbQwAAAIAKQDqDAAAAwAkAG4MAAACABwAEAAHCXwHvTQABAEHaAwAAAEADgBpDAAAAQAQAGsMAAABAAAAagwAAAEADwDqDAAAAQAEAG4MAAABADYAbwwAAAEAGAAAAA==.Discipline:BAAALgAECgYJDAABLgAFFAgJJAARACwWAA==.Divinate:BAAALgAECgIJAgAAAA==.',
Dk='Dkpitador:BAAALgADCgEJAQAAAA==.',
Do='Doomhead:BAABLgAECn8YAAIBAAgJ2AjnkgBBAQhoDAAABAASAGkMAAAEABgAawwAAAQAEABqDAAAAwATAGwMAAACABkAbQwAAAEAHwDqDAAABQAaAG4MAAABABAAAQAICdgI55IAQQEIaAwAAAQAEgBpDAAABAAYAGsMAAAEABAAagwAAAMAEwBsDAAAAgAZAG0MAAABAB8A6gwAAAUAGgBuDAAAAQAQAAAA.',
Dr='Drakki:BAAALgADCgUJBQAAAA==.Dreadfaith:BAAALgAECgYJBgAAAA==.',
Du='Durzii:BAACLgAFFH8FAAISAAIJuiLTMACxAAJoDAAAAwBVAGkMAAACAFwAEgACCboi0zAAsQACaAwAAAMAVQBpDAAAAgBcAC4ABAp/GQADEgAJCaogoRIAfQIAEgAICd4hoRIAfQIADAABCe0ZEGkBTQAAAS4ABRQECQwAEwAcEAA=.',
Ea='Eatmybeef:BAAALgADCgYJCgAAAA==.',
Ex='Extinctionus:BAAALgAECgYJCwAAAA==.',
Fe='Fernn:BAAALgADCgQJBAAAAA==.',
Fi='Fia:BAABLgAECn84AAMBAAkJHROTVgDCAQloDAAACAA5AGkMAAAIADMAawwAAAcAQQBqDAAABwAsAGwMAAAHADkAbQwAAAUAOQDqDAAABwAzAG4MAAAFACAAbwwAAAIAEgABAAkJwQ+TVgDCAQloDAAABwAzAGkMAAAHADMAawwAAAYANQBqDAAABgAsAGwMAAAGACkAbQwAAAQAKwDqDAAABgAdAG4MAAAEACAAbwwAAAIAEgATAAgJyxK+GgCHAQhoDAAAAQA5AGkMAAABACQAawwAAAEAQQBqDAAAAQArAGwMAAABADkAbQwAAAEAOQDqDAAAAQAzAG4MAAABAAsAAAA=.',
Fo='Fondra:BAAALgAECgYJBgAAAA==.',
Fu='Furor:BAAALgAECgQJBAABLgAECgkJGwAPAKYRAA==.',
Ge='Genaro:BAAALgAECgIJBwAAAA==.',
Gi='Gibraltar:BAAALgADCgUJBQAAAA==.',
Go='Gokujang:BAAALgAECgcJDgABLgAECgkJJwAUAPQZAA==.Goremont:BAAALgADCgQJBQAAAA==.Gorlok:BAAALgAECgUJBQAAAA==.',
Gr='Greendot:BAACLgAFFH8SAAIHAAQJ1RUfKQAWAQRoDAAABQBGAGkMAAAGADQAawwAAAIAGQDqDAAABQBLAAcABAnVFR8pABYBBGgMAAAFAEYAaQwAAAYANABrDAAAAgAZAOoMAAAFAEsALgAECn8uAAIHAAkJlyLEAwCFAwAHAAkJlyLEAwCFAwAAAA==.',
Gu='Gulvid:BAACLgAFFH8HAAIDAAIJlx0alACZAAJoDAAAAwBYAOoMAAAEAD8AAwACCZcdGpQAmQACaAwAAAMAWADqDAAABAA/AC4ABAp/GAADAwAHCWQhLFgAlAEAAwAHCWQhLFgAlAEACwABCQAAqlwAWAAAAS4ABRQICRwAAwA+FAA=.',
Ha='Haluak:BAABLgAECn8rAAIIAAkJtRmzFQA6AgloDAAABwBBAGkMAAAIAEsAawwAAAcASgBqDAAABQBOAGwMAAADADsAbQwAAAIAKADqDAAABwBXAG4MAAADADkAbwwAAAEAQgAIAAkJtRmzFQA6AgloDAAABwBBAGkMAAAIAEsAawwAAAcASgBqDAAABQBOAGwMAAADADsAbQwAAAIAKADqDAAABwBXAG4MAAADADkAbwwAAAEAQgAAAA==.',
He='Healthyself:BAAALgAECgYJCwAAAA==.',
Ho='Hothawk:BAAALgAECgYJBwABLgAECgkJQwAMADobAA==.Houndtamer:BAABLgAECn8/AAIVAAkJ0RY7RQDSAQloDAAACgBFAGkMAAAKAEEAawwAAAkALgBqDAAACQA+AGwMAAAGAC0AbQwAAAIAJgDqDAAACgBBAG4MAAAGAEgAbwwAAAEAQAAVAAkJ0RY7RQDSAQloDAAACgBFAGkMAAAKAEEAawwAAAkALgBqDAAACQA+AGwMAAAGAC0AbQwAAAIAJgDqDAAACgBBAG4MAAAGAEgAbwwAAAEAQAAAAA==.',
Hp='Hpyflowers:BAAALgADCgQJBAAAAA==.',
Hr='Hruoth:BAAALgAECgYJBgAAAA==.',
Ic='Iceshooting:BAAALgAECgQJBwAAAA==.',
Is='Ishtar:BAABLgAECn8ZAAMWAAYJ9BzVhADIAQZoDAAABQBFAGkMAAAFAFEAawwAAAQATQBqDAAABABMAGwMAAAEAFMA6gwAAAMAOgAWAAYJCRnVhADIAQZoDAAAAwAqAGkMAAAFAFEAawwAAAMATQBqDAAABABMAGwMAAAEAFMA6gwAAAIAIwAXAAMJzRkuDwDQAANoDAAAAgBFAGsMAAABAEYA6gwAAAEAOgAAAA==.',
It='Itshela:BAACLgAFFH8bAAMBAAcJfxiOKADGAQdoDAAABgBRAGkMAAAEAFUAawwAAAMAJgBqDAAABgA2AGwMAAACACAAbQwAAAEAPgDqDAAABQBMAAEABgl/GI4oAMYBBmgMAAAGAFEAaQwAAAQAVQBrDAAAAwAmAGwMAAACACAAbQwAAAEAPgDqDAAABQBMABMAAQkAANdYAAAAAWoMAAAGADYALgAECn8bAAIBAAcJOCPrTQAJAgABAAcJOCPrTQAJAgAAAA==.',
Ja='Jayrad:BAABLgAECn8UAAMDAAgJ7QjUgQA1AQhoDAAABAAaAGkMAAADABMAawwAAAIADQBqDAAAAQA1AGwMAAABAA8AbQwAAAEAGADqDAAABwAbAG4MAAABACEAAwAICe0I1IEANQEIaAwAAAMAGgBpDAAAAgATAGsMAAABAA0AagwAAAEANQBsDAAAAQAPAG0MAAABABgA6gwAAAYAGwBuDAAAAQAhAAIABAlhBAYaAKcABGgMAAABABIAaQwAAAEADQBrDAAAAQAEAOoMAAABAAgAAAA=.',
Je='Jehnovah:BAAALgADCgMJAwAAAA==.Jellybeanz:BAAALgADCggJDQAAAA==.',
Jo='Jordybear:BAAALgAECgQJBAAAAA==.Jorkoh:BAAALgAECgMJBgAAAA==.',
Ju='Juicer:BAAALgADCgMJBgAAAA==.',
Ka='Kaiige:BAAALgAECgQJBAAAAA==.Kairos:BAAALgAECgYJCgAAAA==.Kanê:BAAALgAFFAMJAwAAAA==.',
Ke='Kehlayr:BAAALgADCgMJAwAAAA==.Keiiry:BAAALgADCgMJAwAAAA==.Kenshinth:BAABLgAECn8WAAIWAAcJERRHgAB2AQdoDAAABQA3AGkMAAADAEAAawwAAAMAOgBqDAAAAgBRAGwMAAACAC4A6gwAAAYAOgBuDAAAAQAZABYABwkRFEeAAHYBB2gMAAAFADcAaQwAAAMAQABrDAAAAwA6AGoMAAACAFEAbAwAAAIALgDqDAAABgA6AG4MAAABABkAAAA=.Kethrym:BAAALgAECgIJAgAAAA==.',
Kh='Khanor:BAAALgAECgYJEQAAAA==.',
Ki='Kiltro:BAAALgAECgQJBgAAAA==.Kimchichi:BAABLgAECn8nAAIMAAkJ2yAjDQD7AgloDAAABwBeAGkMAAAGAEsAawwAAAcAWABqDAAABQBUAGwMAAADAFQAbQwAAAIAVwDqDAAABABEAG4MAAAEAFEAbwwAAAEAXAAMAAkJ2yAjDQD7AgloDAAABwBeAGkMAAAGAEsAawwAAAcAWABqDAAABQBUAGwMAAADAFQAbQwAAAIAVwDqDAAABABEAG4MAAAEAFEAbwwAAAEAXAAAAA==.Kintaro:BAAALgADCgYJDwAAAA==.Kissmybubble:BAAALgADCgEJAQAAAA==.',
Ko='Kogorko:BAAALgAECgMJBQAAAA==.',
Kr='Kry:BAAALgAECgIJAgAAAA==.',
['Kë']='Këarra:BAAALgAECgQJBwAAAA==.',
La='Labotimizer:BAAALgAECggJDwAAAA==.Lapaladin:BAAALgADCgYJBwAAAA==.Lapriestess:BAAALgAECgYJEQAAAA==.Latoya:BAABLgAFFH8FAAIWAAMJPwdQjQC+AANoDAAAAgAVAGkMAAACAAkA6gwAAAEAGAAWAAMJPwdQjQC+AANoDAAAAgAVAGkMAAACAAkA6gwAAAEAGAAAAA==.',
Le='Lemontea:BAAALgAFFAEJAQABLgAFFAQJEgAHANUVAA==.',
Li='Lilbeemo:BAAALgAECgUJCgAAAA==.Lilyana:BAAALgAECgYJCwAAAA==.Liongs:BAAALgAECgcJCQABLgAECgcJFgAWABEUAA==.Litdk:BAAALgADCgUJBQAAAA==.Litharidk:BAABLgAECn8dAAIBAAgJ5B8gNAAvAghoDAAABgBZAGkMAAAHAFkAawwAAAUATQBqDAAAAwBdAGwMAAACAEoAbQwAAAEATgDqDAAABABXAG8MAAABAEoAAQAICeQfIDQALwIIaAwAAAYAWQBpDAAABwBZAGsMAAAFAE0AagwAAAMAXQBsDAAAAgBKAG0MAAABAE4A6gwAAAQAVwBvDAAAAQBKAAAA.',
Lo='Lolmasterr:BAAALgAECgEJAQAAAA==.Lotion:BAAALgAECgEJAgAAAA==.Loudog:BAAALgAECgYJBwAAAA==.Loxyblue:BAAALgAECgQJBAAAAA==.',
Lu='Luckyxpain:BAABLgAECn9DAAMMAAkJOhtwKgBXAgloDAAACwBRAGkMAAAIAD0AawwAAAoARQBqDAAACABcAGwMAAAMAEMAbQwAAAUAXgDqDAAABwBLAG4MAAAEAE8AbwwAAAIAGwAMAAkJBRtwKgBXAgloDAAABwBRAGkMAAAGAD0AawwAAAcARQBqDAAABQBcAGwMAAAFAD8AbQwAAAMAXgDqDAAAAwBLAG4MAAAEAE8AbwwAAAIAGwAYAAcJLBGFGwA7AQdoDAAABAAVAGkMAAACADQAawwAAAMAHwBqDAAAAwAxAGwMAAAHAEMAbQwAAAIANgDqDAAABAAkAAAA.',
Ly='Lykos:BAAALgAECgIJAgAAAA==.',
Ma='Madoff:BAAALgAECgQJCAAAAA==.Makok:BAABLgAECn8nAAMZAAkJDxkCBgA7AgloDAAABgBJAGkMAAAFAEUAawwAAAUAMwBqDAAABAA2AGwMAAADAEYAbQwAAAIAOwDqDAAACAA7AG4MAAAEAEUAbwwAAAIAPAAZAAkJDxkCBgA7AgloDAAABgBJAGkMAAAFAEUAawwAAAUAMwBqDAAABAA2AGwMAAADAEYAbQwAAAIAOwDqDAAABwA7AG4MAAAEAEUAbwwAAAIAPAAaAAEJ7AnycQAzAAHqDAAAAQAZAAAA.Malaise:BAAALgAECggJCgABLgAECgkJLQAbAHwgAA==.',
Me='Melancholic:BAABLgAECn8tAAMbAAkJfCBHCQDNAgloDAAACABhAGkMAAAIAFYAawwAAAcARwBqDAAABgBaAGwMAAAEAFYAbQwAAAEASwDqDAAACABhAG4MAAACAE8AbwwAAAEARwAbAAkJfCBHCQDNAgloDAAABwBhAGkMAAAIAFYAawwAAAcARwBqDAAABgBaAGwMAAAEAFYAbQwAAAEASwDqDAAACABhAG4MAAACAE8AbwwAAAEARwAcAAEJxQSPhAAlAAFoDAAAAQAMAAAA.Mellisa:BAABLgAECn8fAAMBAAkJcxFMcwB+AQloDAAABwBIAGkMAAAEADUAawwAAAUANwBqDAAAAwBEAGwMAAACABgAbQwAAAEAEgDqDAAABwBNAG4MAAABABIAbwwAAAEAJAABAAgJ2w9McwB+AQhoDAAABgBIAGkMAAADABAAawwAAAQANwBqDAAAAwBEAGwMAAACABgAbQwAAAEAEgDqDAAABgBNAG4MAAABABIAEwAFCXUTpSoAAwEFaAwAAAEALgBpDAAAAQA1AGsMAAABADQA6gwAAAEAPABvDAAAAQAkAAAA.Memory:BAAALgAECgEJBAAAAA==.',
Mi='Milkingman:BAAALgAECgYJBAAAAA==.',
Mo='Mooshmoo:BAAALgAECgEJAQAAAA==.Morpheus:BAAALgAECgYJBgABLgAFFAMJBgAdABUeAA==.',
Mu='Murog:BAABLgAECn8dAAMJAAgJSQ2oTwBzAQhoDAAAAwAvAGkMAAADADEAawwAAAMAEQBqDAAABAArAGwMAAAFADIAbQwAAAIAEgDqDAAABwAgAG4MAAACAAwACQAICUkNqE8AcwEIaAwAAAIALwBpDAAAAgAxAGsMAAACABEAagwAAAMAKwBsDAAABAAyAG0MAAACABIA6gwAAAYAIABuDAAAAgAMAAoABgk9A9gpAKkABmgMAAABAAgAaQwAAAEACQBrDAAAAQAKAGoMAAABAAYAbAwAAAEACADqDAAAAQAEAAAA.',
Na='Nazarite:BAAALgAECgYJDwAAAA==.',
Ne='Nephlok:BAAALgAECggJCAAAAA==.',
Ni='Nightdisco:BAAALgAECgQJBAAAAA==.',
No='Noctyra:BAAALgAECgQJCAAAAA==.Nomaana:BAAALgAECgMJAwAAAA==.Norael:BAAALgADCgIJAgAAAA==.',
Og='Ogthunder:BAAALgAECgEJAQAAAA==.',
Op='Ophellia:BAAALgAECgEJAQAAAA==.',
Pu='Pureformance:BAAALgADCgcJBwABLgAFFAgJJwAHAFUjAA==.Purrformance:BAACLgAFFH8nAAMHAAgJVSMdAgAsAwhoDAAACABgAGkMAAAIAGEAawwAAAYAXABqDAAABABNAGwMAAACAF0AbQwAAAEAUADqDAAACQBiAG4MAAABAFYABwAICVUjHQIALAMIaAwAAAcAYABpDAAACABhAGsMAAAGAFwAagwAAAQATQBsDAAAAgBdAG0MAAABAFAA6gwAAAkAYgBuDAAAAQBWAB4AAQnDBlRRADQAAWgMAAABABEALgAECn8iAAIHAAkJoiUMAQCnAwAHAAkJoiUMAQCnAwAAAA==.',
Py='Pyrophobiac:BAACLgAFFH8fAAMDAAgJDxm9EQArAghoDAAABQBLAGkMAAAEABgAawwAAAQAOgBqDAAAAgAbAGwMAAAEAFgAbQwAAAMAJwDqDAAABwBPAG4MAAACAFQAAwAICQ8ZvREAKwIIaAwAAAUASwBpDAAAAwAYAGsMAAACADoAagwAAAIAGwBsDAAABABYAG0MAAADACcA6gwAAAcATwBuDAAAAgBUAAsAAglYAkoPAH8AAmkMAAABAAcAawwAAAIABAAuAAQKfyMAAwMACQnaI4ADAIcDAAMACQmYI4ADAIcDAAsABwmhHUcHAFQCAAAA.',
Ra='Ra:BAABLgAECn8qAAIaAAgJbh/8CwBnAghoDAAABgBSAGkMAAAIAFwAawwAAAgAXABqDAAABgBQAGwMAAAEAFAAbQwAAAIARQDqDAAABQBQAG4MAAADAEIAGgAICW4f/AsAZwIIaAwAAAYAUgBpDAAACABcAGsMAAAIAFwAagwAAAYAUABsDAAABABQAG0MAAACAEUA6gwAAAUAUABuDAAAAwBCAAAA.Radagast:BAACLgAFFH8UAAIfAAQJNw0UUQD6AARoDAAABgAzAGkMAAAFACIAawwAAAMAGgDqDAAABgAXAB8ABAk3DRRRAPoABGgMAAAGADMAaQwAAAUAIgBrDAAAAwAaAOoMAAAGABcALgAECn8xAAMfAAgJEBpgMQAAAgAfAAgJMxhgMQAAAgAaAAcJjhP8IwBYAQAAAA==.Radditz:BAAALgAECgYJCwAAAA==.Rafiki:BAAALgAECgEJAQAAAA==.Rand:BAAALgADCgcJDgAAAA==.',
Ri='Riv:BAAALgAECgMJAwAAAA==.',
Ro='Ronni:BAAALgAECgUJCgAAAA==.Roxyfox:BAAALgAECgYJCwAAAA==.Royvaz:BAAALgAECgkJEgAAAA==.',
Sa='Salea:BAAALgAECgIJAgAAAA==.Sarryn:BAAALgADCgcJBwAAAA==.',
Sc='Scale:BAAALgAECgMJAwAAAA==.Schwiifty:BAAALgAECgMJDgAAAA==.',
Se='Serik:BAAALgADCgEJAQAAAA==.',
Sh='Shadorodo:BAAALgADCgIJAgAAAA==.Shakaboom:BAAALgAFFAEJAQAAAA==.Shakazoom:BAAALgAECgQJBAAAAA==.Sheffers:BAAALgADCgEJAQAAAA==.Sheffurs:BAABLgAECn87AAIGAAkJ0gN7OwC4AAloDAAABwAEAGkMAAAIAAYAawwAAAgABQBqDAAABwAGAGwMAAAHAAkAbQwAAAUADQDqDAAACQAcAG4MAAAFAAQAbwwAAAMABQAGAAkJ0gN7OwC4AAloDAAABwAEAGkMAAAIAAYAawwAAAgABQBqDAAABwAGAGwMAAAHAAkAbQwAAAUADQDqDAAACQAcAG4MAAAFAAQAbwwAAAMABQAAAA==.Shepardl:BAACLgAFFH8mAAISAAgJYyX/AAA3AwhoDAAABwBdAGkMAAAHAGEAawwAAAUAZABqDAAABgBNAGwMAAAEAGMAbQwAAAEAYgDqDAAABwBjAG4MAAABAGMAEgAICWMl/wAANwMIaAwAAAcAXQBpDAAABwBhAGsMAAAFAGQAagwAAAYATQBsDAAABABjAG0MAAABAGIA6gwAAAcAYwBuDAAAAQBjAC4ABAp/IQACEgAICeQmGgEAgQMAEgAICeQmGgEAgQMAAAA=.Shredemdown:BAAALgAECgcJCQAAAA==.Shárkbait:BAAALgAECgEJAQABLgAECgUJDAAOAAAAAA==.',
Sk='Skadoosher:BAAALgAECgUJBQAAAA==.Skyratt:BAAALgAECgEJAgAAAA==.',
Sl='Sleepielight:BAAALgAFFAIJBAAAAA==.',
Sm='Smackemz:BAAALgAECgYJCQAAAA==.Smacmywand:BAAALgAECgIJBgAAAA==.',
So='Sollasi:BAAALgADCgMJBgAAAA==.Sortie:BAABLgAECn87AAMSAAkJWA0nLQCqAQloDAAABwAhAGkMAAAIAAwAawwAAAgAMQBqDAAABwAPAGwMAAAHACQAbQwAAAUAGQDqDAAACQA0AG4MAAAFABMAbwwAAAMAPgASAAkJWA0nLQCqAQloDAAAAwAhAGkMAAADAAwAawwAAAQAMQBqDAAAAwAPAGwMAAAEACQAbQwAAAMAGQDqDAAAAwA0AG4MAAABABMAbwwAAAMAPgAMAAgJCwr0pgAtAQhoDAAABAAvAGkMAAAFACMAawwAAAQAFABqDAAABAAkAGwMAAADAA4AbQwAAAIAEwDqDAAABgAaAG4MAAAEABAAAAA=.',
Sp='Spookybolt:BAAALgAECgEJAQAAAA==.Spoons:BAAALgAECgQJBAABLgAFFAUJFgAgAEocAA==.Spyromu:BAAALgAECgUJCwAAAA==.',
St='Stealman:BAAALgADCgcJBwAAAA==.Steeleman:BAAALgADCgQJAgAAAA==.',
Su='Succinic:BAAALgAECggJEAAAAA==.Suffer:BAAALgAECgUJCAAAAA==.',
Sw='Swiss:BAABLgAECn8bAAISAAgJrw1ONACsAQhoDAAABAA3AGkMAAAEACIAawwAAAQAKwBqDAAAAwAlAGwMAAADABoAbQwAAAMAEwDqDAAAAwA5AG4MAAADAAcAEgAICa8NTjQArAEIaAwAAAQANwBpDAAABAAiAGsMAAAEACsAagwAAAMAJQBsDAAAAwAaAG0MAAADABMA6gwAAAMAOQBuDAAAAwAHAAAA.',
Sy='Sylphvaria:BAAALgADCgUJBQAAAA==.Syren:BAAALgADCgcJBgAAAA==.',
Te='Tegridy:BAABLgAECn8VAAIVAAYJpBE0hQA0AQZoDAAABAA8AGkMAAAEADIAawwAAAQAIABqDAAAAQAuAGwMAAABACEA6gwAAAcALwAVAAYJpBE0hQA0AQZoDAAABAA8AGkMAAAEADIAawwAAAQAIABqDAAAAQAuAGwMAAABACEA6gwAAAcALwAAAA==.Teko:BAAALgADCgYJCwAAAA==.',
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
We='Wexew:BAACLgAFFH8FAAMKAAIJEx4wEQC0AAJoDAAAAQBMAOoMAAAEAE0ACgACCRMeMBEAtAACaAwAAAEATADqDAAAAQBNAAgAAQmeC51ZADYAAeoMAAADAB0ALgAECn8bAAMKAAkJBhxiBwBXAgAKAAkJ7xpiBwBXAgAIAAUJChW+SgAdAQAAAA==.Wexwex:BAAALgAFFAIJAwABLgAFFAIJBQAKABMeAA==.Wexxew:BAAALgAFFAEJAQABLgAFFAIJBQAKABMeAA==.',
Wi='Wishing:BAABLgAECn8bAAISAAgJlBSPHgAOAghoDAAABABWAGkMAAAEACsAawwAAAQARwBqDAAABABGAGwMAAADAEIAbQwAAAEABQDqDAAABgA8AG4MAAABABEAEgAICZQUjx4ADgIIaAwAAAQAVgBpDAAABAArAGsMAAAEAEcAagwAAAQARgBsDAAAAwBCAG0MAAABAAUA6gwAAAYAPABuDAAAAQARAAAA.',
Wu='Wundertot:BAAALgAECgYJBgABLgAFFAQJCwAWAN8NAA==.Wunderwazard:BAACLgAFFH8LAAIWAAQJ3w37agANAQRoDAAABAA0AGkMAAADACEAawwAAAEABQDqDAAAAwAxABYABAnfDftqAA0BBGgMAAAEADQAaQwAAAMAIQBrDAAAAQAFAOoMAAADADEALgAECn8sAAIWAAkJVR9vIwCPAgAWAAkJVR9vIwCPAgAAAA==.',
Xe='Xevikan:BAABLgAECn8bAAMBAAcJDBV+iQBSAQdoDAAABgBHAGkMAAAFADYAawwAAAUASwBqDAAAAgAnAGwMAAACACkAbQwAAAIAHADqDAAABQAzAAEABwkMFX6JAFIBB2gMAAAFAEcAaQwAAAUANgBrDAAABQBLAGoMAAACACcAbAwAAAIAKQBtDAAAAgAcAOoMAAAFADMAIQABCR8I2j8AJwABaAwAAAEAFAAAAA==.',
Ya='Yadead:BAAALgAECgcJDAAAAA==.',
Za='Zangief:BAAALgADCgYJBwAAAA==.Zaylen:BAAALgAECgYJEwABLgAFFAMJBgAdABUeAA==.',
Ze='Zendjin:BAAALgADCgYJDQAAAA==.Zenlore:BAAALgADCgYJBgAAAA==.',
Zi='Zistormstout:BAABLgAECn9AAAIIAAkJ0xzCEwBOAgloDAAACgBIAGkMAAAKAD4AawwAAAkARgBqDAAACQBMAGwMAAAGAFsAbQwAAAIAOwDqDAAACwBNAG4MAAAGAFsAbwwAAAEAQQAIAAkJ0xzCEwBOAgloDAAACgBIAGkMAAAKAD4AawwAAAkARgBqDAAACQBMAGwMAAAGAFsAbQwAAAIAOwDqDAAACwBNAG4MAAAGAFsAbwwAAAEAQQAAAA==.',
Zu='Zuhgonemad:BAAALgAECgQJBgAAAA==.',
['Äl']='Älektra:BAABLgAECn8gAAIfAAgJvATdngDlAAhoDAAABQAIAGkMAAAGAAwAawwAAAYADQBqDAAABAANAGwMAAADAAkAbQwAAAIADADqDAAABAAJAG8MAAACABIAHwAICbwE3Z4A5QAIaAwAAAUACABpDAAABgAMAGsMAAAGAA0AagwAAAQADQBsDAAAAwAJAG0MAAACAAwA6gwAAAQACQBvDAAAAgASAAAA.',
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
