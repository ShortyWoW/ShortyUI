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

local lookup = {'DeathKnight-Unholy','Warlock-Affliction','Warlock-Demonology','Priest-Holy','Druid-Feral','Druid-Guardian','Druid-Restoration','Shaman-Elemental','Shaman-Restoration','Shaman-Enhancement','Warlock-Destruction','Paladin-Retribution','Priest-Shadow','Unknown-Unknown','Rogue-Assassination','Rogue-Subtlety','Hunter-Survival','Paladin-Holy','DeathKnight-Blood','Priest-Discipline','Hunter-BeastMastery','Mage-Frost','Mage-Arcane','Paladin-Protection','DemonHunter-Vengeance','DemonHunter-Havoc','Warrior-Fury','Warrior-Arms','Druid-Balance','DemonHunter-Devourer','Monk-Mistweaver','DeathKnight-Frost',}
local provider = {region='US',realm="Gul'dan",name='US',type='daily',zone=46,date='2026-06-11',data={Ae='Aeri:BAAALgAECgYJDAAAAA==.',
Al='Alastormoody:BAAALgADCgcJDAAAAA==.Alelover:BAAALgADCgUJBQAAAA==.Allaria:BAAALgAECgYJEwAAAA==.Almadíon:BAAALgADCgcJCAAAAA==.',
Am='Amosian:BAAALgADCgIJAgAAAA==.',
An='Ana:BAAALgADCgMJAwAAAA==.',
Ao='Aoemomma:BAAALgADCgcJBwAAAA==.',
Ar='Arin:BAAALgAECgIJAwABLgAFFAMJCgABAEEmAA==.',
As='Asuya:BAAALgADCgIJAwAAAA==.',
Az='Azög:BAAALgADCgUJBQAAAA==.',
Ba='Babysocks:BAAALgAECgYJBgAAAA==.',
Bc='Bc:BAACLgAFFH8HAAMCAAMJ3RnaCQDUAANsDAAAAQAVAG0MAAABAE0A6gwAAAUAYwACAAIJpSLaCQDUAAJtDAAAAQBNAOoMAAABAGMAAwACCRkXwIkApwACbAwAAAEAFQDqDAAABABhAC4ABAp/GwACAwAICfgmMQMAjQMAAwAICfgmMQMAjQMAAAA=.',
Be='Beep:BAABLgAECn8lAAIDAAcJRh+JOgAiAgdoDAAABwBVAGkMAAAGAFMAawwAAAYAWABqDAAABgBdAGwMAAAFAE8AbQwAAAEALwDqDAAABgBgAAMABwlGH4k6ACICB2gMAAAHAFUAaQwAAAYAUwBrDAAABgBYAGoMAAAGAF0AbAwAAAUATwBtDAAAAQAvAOoMAAAGAGAAAAA=.',
Bl='Blackthunder:BAAALgAECggJDAAAAA==.',
Bo='Bobert:BAAALgADCgcJBgAAAA==.Bofadz:BAAALgADCgYJBgAAAA==.Boozecruise:BAAALgADCgIJAgAAAA==.Boozedrat:BAAALgAFFAEJAgABLgAFFAYJFgADAH8WAA==.Bowyn:BAABLgAECn8XAAIEAAYJHhNoOgBSAQZoDAAABAA3AGkMAAAFACYAawwAAAUAJgBqDAAAAwAYAGwMAAADADkA6gwAAAMAUAAEAAYJHhNoOgBSAQZoDAAABAA3AGkMAAAFACYAawwAAAUAJgBqDAAAAwAYAGwMAAADADkA6gwAAAMAUAAAAA==.',
Bu='Bubblnbiotch:BAAALgADCgEJAQAAAA==.Budleaf:BAABLgAECn8aAAQFAAYJlhI9IgDuAAZoDAAABgAoAGkMAAAFADAAawwAAAUAHwBqDAAAAwA3AGwMAAADADwA6gwAAAQAOAAFAAUJ0BI9IgDuAAVoDAAAAQAaAGkMAAABADAAagwAAAEAKgBsDAAAAQA8AOoMAAABADgABgAGCRcM3TgAuQAGaAwAAAUAKABpDAAABAAVAGsMAAAFAB8AagwAAAIANwBsDAAAAgAhAOoMAAACABsABwABCdQGlOYAIwAB6gwAAAEAEQAAAA==.Bunkley:BAABLgAECn8rAAQIAAgJtRH1LQCEAQhoDAAACAA0AGkMAAAHACwAawwAAAgAMQBqDAAABwA7AGwMAAADAE8AbQwAAAEAIwDqDAAABQAnAG4MAAAEABEACAAICbUR9S0AhAEIaAwAAAMANABpDAAAAwAsAGsMAAACADEAagwAAAMAOwBsDAAAAwBPAG0MAAABACMA6gwAAAQAJwBuDAAAAgARAAkABgkNDFV2APMABmgMAAAEADkAaQwAAAMAEgBrDAAABQAjAGoMAAAEACMA6gwAAAEACABuDAAAAgAeAAoAAwlNChsrAJQAA2gMAAABABcAaQwAAAEAHABrDAAAAQAaAAAA.Butterknives:BAAALgAECgEJAQAAAA==.',
By='Byege:BAACLgAFFH8WAAIDAAYJfxZNKQCRAQZoDAAABQBWAGkMAAAEACUAawwAAAIAMwBqDAAAAQAXAOoMAAAJAFUAbgwAAAEAGwADAAYJfxZNKQCRAQZoDAAABQBWAGkMAAAEACUAawwAAAIAMwBqDAAAAQAXAOoMAAAJAFUAbgwAAAEAGwAuAAQKfycAAwMACQnHH/EXAJECAAMACQmjH/EXAJECAAsABQnOF7IbAHABAAAA.',
Ca='Cantfireme:BAAALgAECgYJCAABLgAECgkJQgAMADobAA==.Cardhunter:BAAALgADCgYJBgAAAA==.',
Ch='Champilon:BAAALgADCgcJDQAAAA==.Chaoticus:BAAALgAECgYJDQABLgAECggJIgANAJgOAA==.Charizards:BAAALgADCgYJDQAAAA==.Charmahnder:BAAALgAECgIJAgAAAA==.',
Co='Coma:BAAALgAECgEJAQAAAA==.',
Cr='Crunbard:BAAALgAECggJDwAAAA==.',
Cu='Culdan:BAABLgAECn8aAAMLAAYJ+QndGwDCAAZoDAAABgAdAGkMAAAGABoAawwAAAcAIABqDAAAAgASAGwMAAACABEA6gwAAAMAFgALAAYJ+QndGwDCAAZoDAAAAQAdAGkMAAABABoAawwAAAUAIABqDAAAAgASAGwMAAACABEA6gwAAAIAFgADAAQJlgTP4gCSAARoDAAABQAIAGkMAAAFABMAawwAAAIACgDqDAAAAQAIAAAA.',
Da='Dalirus:BAAALgAECgQJBgABLgAECgkJQgAMADobAA==.Danahe:BAAALgAFFAEJAQABLgAFFAIJBAAOAAAAAA==.Darci:BAAALgAECgcJEQABLgAECgQJCAAOAAAAAA==.Darksuaza:BAAALgAECggJDQAAAA==.Darthwizard:BAAALgADCgIJAgAAAA==.Dasbunk:BAAALgAECgYJDwAAAA==.Dayman:BAAALgADCgYJBgAAAA==.',
De='Deadblue:BAABLgAECn87AAILAAkJ+xmkAwBQAgloDAAABwBMAGkMAAAIAEgAawwAAAgANwBqDAAABwAuAGwMAAAHAD8AbQwAAAUAJgDqDAAACQBMAG4MAAAFAFYAbwwAAAMAPwALAAkJ+xmkAwBQAgloDAAABwBMAGkMAAAIAEgAawwAAAgANwBqDAAABwAuAGwMAAAHAD8AbQwAAAUAJgDqDAAACQBMAG4MAAAFAFYAbwwAAAMAPwAAAA==.Deathblows:BAAALgAECgUJCAAAAA==.Deekay:BAAALgADCgcJFAAAAA==.',
Di='Diogee:BAAALgAECgMJBgAAAA==.Dirge:BAABLgAECn8ZAAMPAAgJUBGmCQCeAQhoDAAAAwAsAGkMAAADADUAawwAAAQAPABqDAAAAwAmAGwMAAAEAC4AbQwAAAIAKQDqDAAABAAkAG4MAAACABwADwAICVARpgkAngEIaAwAAAIALABpDAAAAgA1AGsMAAADADwAagwAAAIAJgBsDAAABAAuAG0MAAACACkA6gwAAAMAJABuDAAAAgAcABAABQl9A2ZKAH0ABWgMAAABAA4AaQwAAAEAEABrDAAAAQAAAGoMAAABAA8A6gwAAAEABAAAAA==.Discipline:BAAALgAECgYJDAABLgAFFAgJJAARACwWAA==.Divinate:BAAALgAECgIJAgAAAA==.',
Dk='Dkpitador:BAAALgADCgEJAQAAAA==.',
Do='Doomhead:BAABLgAECn8YAAIBAAgJ2AixjQBGAQhoDAAABAASAGkMAAAEABgAawwAAAQAEABqDAAAAwATAGwMAAACABkAbQwAAAEAHwDqDAAABQAaAG4MAAABABAAAQAICdgIsY0ARgEIaAwAAAQAEgBpDAAABAAYAGsMAAAEABAAagwAAAMAEwBsDAAAAgAZAG0MAAABAB8A6gwAAAUAGgBuDAAAAQAQAAAA.',
Dr='Drakki:BAAALgADCgUJBQAAAA==.Dreadfaith:BAAALgAECgYJBgAAAA==.',
Du='Durzii:BAACLgAFFH8FAAISAAIJuiKqLwCzAAJoDAAAAwBVAGkMAAACAFwAEgACCboiqi8AswACaAwAAAMAVQBpDAAAAgBcAC4ABAp/GQADEgAJCaogoRIAfQIAEgAICd4hoRIAfQIADAABCe0ZdWABTQAAAS4ABRQECQgAEwDcDwA=.',
Ea='Eatmybeef:BAAALgADCgYJCgAAAA==.',
Ex='Extinctionus:BAAALgAECgQJBQAAAA==.',
Fe='Fernn:BAAALgADCgQJBAAAAA==.',
Fi='Fia:BAABLgAECn84AAMBAAkJHRNWUwDHAQloDAAACAA5AGkMAAAIADMAawwAAAcAQQBqDAAABwAsAGwMAAAHADkAbQwAAAUAOQDqDAAABwAzAG4MAAAFACAAbwwAAAIAEgABAAkJwQ9WUwDHAQloDAAABwAzAGkMAAAHADMAawwAAAYANQBqDAAABgAsAGwMAAAGACkAbQwAAAQAKwDqDAAABgAdAG4MAAAEACAAbwwAAAIAEgATAAgJyxIJGgCKAQhoDAAAAQA5AGkMAAABACQAawwAAAEAQQBqDAAAAQArAGwMAAABADkAbQwAAAEAOQDqDAAAAQAzAG4MAAABAAsAAAA=.',
Fo='Fondra:BAAALgAECgYJBgAAAA==.',
Fu='Furor:BAAALgAECgQJBAAAAA==.',
Ge='Genaro:BAAALgAECgIJBwAAAA==.',
Gi='Gibraltar:BAAALgADCgUJBQAAAA==.',
Go='Gokujang:BAAALgAECgcJDgABLgAECggJIQAUABMZAA==.Goremont:BAAALgADCgQJBQAAAA==.Gorlok:BAAALgAECgUJBQAAAA==.',
Gr='Greendot:BAACLgAFFH8SAAIHAAQJ1RXzJgAgAQRoDAAABQBGAGkMAAAGADQAawwAAAIAGQDqDAAABQBLAAcABAnVFfMmACABBGgMAAAFAEYAaQwAAAYANABrDAAAAgAZAOoMAAAFAEsALgAECn8uAAIHAAkJlyKTAwCGAwAHAAkJlyKTAwCGAwAAAA==.',
Gu='Gulvid:BAACLgAFFH8HAAIDAAIJlx3KjgCbAAJoDAAAAwBYAOoMAAAEAD8AAwACCZcdyo4AmwACaAwAAAMAWADqDAAABAA/AC4ABAp/GAADAwAHCWQhiVYAlgEAAwAHCWQhiVYAlgEACwABCQAAqlwAWAAAAS4ABRQICRwAAwA+FAA=.',
Ha='Haluak:BAABLgAECn8qAAIIAAkJExllFwAkAgloDAAABwBBAGkMAAAIAEsAawwAAAcASgBqDAAABQBOAGwMAAADADsAbQwAAAIAKADqDAAABwBXAG4MAAACACwAbwwAAAEAQgAIAAkJExllFwAkAgloDAAABwBBAGkMAAAIAEsAawwAAAcASgBqDAAABQBOAGwMAAADADsAbQwAAAIAKADqDAAABwBXAG4MAAACACwAbwwAAAEAQgAAAA==.',
He='Healthyself:BAAALgAECgYJCwAAAA==.',
Ho='Houndtamer:BAABLgAECn89AAIVAAgJfxarQgDUAQhoDAAACgBFAGkMAAAKAEEAawwAAAkALgBqDAAACQA+AGwMAAAGAC0AbQwAAAIAJgDqDAAACgBBAG4MAAAFAEgAFQAICX8Wq0IA1AEIaAwAAAoARQBpDAAACgBBAGsMAAAJAC4AagwAAAkAPgBsDAAABgAtAG0MAAACACYA6gwAAAoAQQBuDAAABQBIAAAA.',
Hp='Hpyflowers:BAAALgADCgQJBAAAAA==.',
Hr='Hruoth:BAAALgAECgYJBgAAAA==.',
Ic='Iceshooting:BAAALgAECgQJBwAAAA==.',
Is='Ishtar:BAABLgAECn8ZAAMWAAYJ9BzVhADIAQZoDAAABQBFAGkMAAAFAFEAawwAAAQATQBqDAAABABMAGwMAAAEAFMA6gwAAAMAOgAWAAYJCRnVhADIAQZoDAAAAwAqAGkMAAAFAFEAawwAAAMATQBqDAAABABMAGwMAAAEAFMA6gwAAAIAIwAXAAMJzRkuDwDQAANoDAAAAgBFAGsMAAABAEYA6gwAAAEAOgAAAA==.',
It='Itshela:BAACLgAFFH8bAAMBAAcJfxj1IwDIAQdoDAAABgBRAGkMAAAEAFUAawwAAAMAJgBqDAAABgA2AGwMAAACACAAbQwAAAEAPgDqDAAABQBMAAEABgl/GPUjAMgBBmgMAAAGAFEAaQwAAAQAVQBrDAAAAwAmAGwMAAACACAAbQwAAAEAPgDqDAAABQBMABMAAQkAAExUAAAAAWoMAAAGADYALgAECn8bAAIBAAcJOCPrTQAJAgABAAcJOCPrTQAJAgAAAA==.',
Ja='Jayrad:BAAALgAECgcJEgAAAA==.',
Je='Jehnovah:BAAALgADCgMJAwAAAA==.Jellybeanz:BAAALgADCggJDQAAAA==.',
Jo='Jordybear:BAAALgAECgQJBAAAAA==.Jorkoh:BAAALgAECgMJBgAAAA==.',
Ju='Juicer:BAAALgADCgMJBgAAAA==.',
Ka='Kaiige:BAAALgAECgQJBAAAAA==.Kairos:BAAALgAECgYJCgAAAA==.Kanê:BAAALgAFFAMJAwAAAA==.',
Ke='Kehlayr:BAAALgADCgMJAwAAAA==.Keiiry:BAAALgADCgMJAwAAAA==.Kenshinth:BAAALgAECgYJDwABLgAECgcJCAAOAAAAAA==.Kethrym:BAAALgAECgIJAgAAAA==.',
Kh='Khanor:BAAALgAECgYJEQAAAA==.',
Ki='Kiltro:BAAALgAECgQJBgAAAA==.Kimchichi:BAABLgAECn8iAAIMAAgJqB3VKABaAghoDAAABgBeAGkMAAAGAEsAawwAAAYARgBqDAAABQBUAGwMAAADAFQAbQwAAAIAVwDqDAAAAwA4AG4MAAADAD4ADAAICagd1SgAWgIIaAwAAAYAXgBpDAAABgBLAGsMAAAGAEYAagwAAAUAVABsDAAAAwBUAG0MAAACAFcA6gwAAAMAOABuDAAAAwA+AAAA.Kintaro:BAAALgADCgYJDwAAAA==.Kissmybubble:BAAALgADCgEJAQAAAA==.',
Ko='Kogorko:BAAALgAECgMJBQAAAA==.',
Kr='Kry:BAAALgAECgIJAgAAAA==.',
['Kë']='Këarra:BAAALgAECgQJBwAAAA==.',
La='Labotimizer:BAAALgAECggJDwAAAA==.Lapaladin:BAAALgADCgEJAQAAAA==.Lapriestess:BAAALgAECgYJCwAAAA==.Latoya:BAABLgAFFH8FAAIWAAMJPwcniADJAANoDAAAAgAVAGkMAAACAAkA6gwAAAEAGAAWAAMJPwcniADJAANoDAAAAgAVAGkMAAACAAkA6gwAAAEAGAAAAA==.',
Li='Lilbeemo:BAAALgAECgUJCgAAAA==.Lilyana:BAAALgAECgYJCwAAAA==.Liongs:BAAALgAECgcJCAAAAA==.Litdk:BAAALgADCgUJBQAAAA==.Litharidk:BAABLgAECn8dAAIBAAgJ5B/1MgAwAghoDAAABgBZAGkMAAAHAFkAawwAAAUATQBqDAAAAwBdAGwMAAACAEoAbQwAAAEATgDqDAAABABXAG8MAAABAEoAAQAICeQf9TIAMAIIaAwAAAYAWQBpDAAABwBZAGsMAAAFAE0AagwAAAMAXQBsDAAAAgBKAG0MAAABAE4A6gwAAAQAVwBvDAAAAQBKAAAA.',
Lo='Lotion:BAAALgAECgEJAgAAAA==.Loudog:BAAALgAECgYJBwAAAA==.Loxyblue:BAAALgAECgQJBAAAAA==.',
Lu='Luckyxpain:BAABLgAECn9CAAMMAAkJOhsVKQBZAgloDAAACwBRAGkMAAAIAD0AawwAAAoARQBqDAAACABcAGwMAAAMAEMAbQwAAAUAXgDqDAAABgBLAG4MAAAEAE8AbwwAAAIAGwAMAAkJBRsVKQBZAgloDAAABwBRAGkMAAAGAD0AawwAAAcARQBqDAAABQBcAGwMAAAFAD8AbQwAAAMAXgDqDAAAAwBLAG4MAAAEAE8AbwwAAAIAGwAYAAcJLBF4HwATAQdoDAAABAAVAGkMAAACADQAawwAAAMAHwBqDAAAAwAxAGwMAAAHAEMAbQwAAAIANgDqDAAAAwAkAAAA.',
Ly='Lykos:BAAALgAECgIJAgAAAA==.',
Ma='Madoff:BAAALgAECgQJCAAAAA==.Makok:BAABLgAECn8mAAMZAAkJ/BdLBgAtAgloDAAABgBJAGkMAAAFAEUAawwAAAUAMwBqDAAABAA2AGwMAAADAEYAbQwAAAIAOwDqDAAACAA7AG4MAAAEAEUAbwwAAAEAJgAZAAkJ/BdLBgAtAgloDAAABgBJAGkMAAAFAEUAawwAAAUAMwBqDAAABAA2AGwMAAADAEYAbQwAAAIAOwDqDAAABwA7AG4MAAAEAEUAbwwAAAEAJgAaAAEJ7AnycQAzAAHqDAAAAQAZAAAA.Malaise:BAAALgADCgcJBwABLgAECgkJLQAbAHwgAA==.',
Me='Melancholic:BAABLgAECn8tAAMbAAkJfCDgCADQAgloDAAACABhAGkMAAAIAFYAawwAAAcARwBqDAAABgBaAGwMAAAEAFYAbQwAAAEASwDqDAAACABhAG4MAAACAE8AbwwAAAEARwAbAAkJfCDgCADQAgloDAAABwBhAGkMAAAIAFYAawwAAAcARwBqDAAABgBaAGwMAAAEAFYAbQwAAAEASwDqDAAACABhAG4MAAACAE8AbwwAAAEARwAcAAEJxQQRgAAlAAFoDAAAAQAMAAAA.Mellisa:BAABLgAECn8fAAMBAAkJcxF9bwCCAQloDAAABwBIAGkMAAAEADUAawwAAAUANwBqDAAAAwBEAGwMAAACABgAbQwAAAEAEgDqDAAABwBNAG4MAAABABIAbwwAAAEAJAABAAgJ2w99bwCCAQhoDAAABgBIAGkMAAADABAAawwAAAQANwBqDAAAAwBEAGwMAAACABgAbQwAAAEAEgDqDAAABgBNAG4MAAABABIAEwAFCXUTeykABgEFaAwAAAEALgBpDAAAAQA1AGsMAAABADQA6gwAAAEAPABvDAAAAQAkAAAA.Memory:BAAALgAECgEJBAAAAA==.',
Mi='Milkingman:BAAALgAECgQJAgAAAA==.',
Mo='Mooshmoo:BAAALgAECgEJAQAAAA==.Morpheus:BAAALgADCgcJCAABLgAFFAMJAwAOAAAAAA==.',
Mu='Murog:BAABLgAECn8dAAMJAAgJSQ3OTQBzAQhoDAAAAwAvAGkMAAADADEAawwAAAMAEQBqDAAABAArAGwMAAAFADIAbQwAAAIAEgDqDAAABwAgAG4MAAACAAwACQAICUkNzk0AcwEIaAwAAAIALwBpDAAAAgAxAGsMAAACABEAagwAAAMAKwBsDAAABAAyAG0MAAACABIA6gwAAAYAIABuDAAAAgAMAAoABgk9A/8nAK0ABmgMAAABAAgAaQwAAAEACQBrDAAAAQAKAGoMAAABAAYAbAwAAAEACADqDAAAAQAEAAAA.',
Na='Nazarite:BAAALgAECgYJDwAAAA==.',
Ne='Nephlok:BAAALgAECggJCAAAAA==.',
Ni='Nightdisco:BAAALgAECgQJBAAAAA==.',
No='Noctyra:BAAALgAECgQJCAAAAA==.Nomaana:BAAALgAECgMJAwAAAA==.Norael:BAAALgADCgIJAgAAAA==.',
Og='Ogthunder:BAAALgAECgEJAQAAAA==.',
Op='Ophellia:BAAALgAECgEJAQAAAA==.',
Pu='Pureformance:BAAALgADCgcJBwABLgAFFAgJJwAHAFUjAA==.Purrformance:BAACLgAFFH8nAAMHAAgJVSPbAQAzAwhoDAAACABgAGkMAAAIAGEAawwAAAYAXABqDAAABABNAGwMAAACAF0AbQwAAAEAUADqDAAACQBiAG4MAAABAFYABwAICVUj2wEAMwMIaAwAAAcAYABpDAAACABhAGsMAAAGAFwAagwAAAQATQBsDAAAAgBdAG0MAAABAFAA6gwAAAkAYgBuDAAAAQBWAB0AAQnDBr1NADQAAWgMAAABABEALgAECn8iAAIHAAkJoiUMAQCnAwAHAAkJoiUMAQCnAwAAAA==.',
Py='Pyrophobiac:BAACLgAFFH8fAAMDAAgJDxlvDgAwAghoDAAABQBLAGkMAAAEABgAawwAAAQAOgBqDAAAAgAbAGwMAAAEAFgAbQwAAAMAJwDqDAAABwBPAG4MAAACAFQAAwAICQ8Zbw4AMAIIaAwAAAUASwBpDAAAAwAYAGsMAAACADoAagwAAAIAGwBsDAAABABYAG0MAAADACcA6gwAAAcATwBuDAAAAgBUAAsAAglYAkoPAH8AAmkMAAABAAcAawwAAAIABAAuAAQKfyMAAwMACQnaI4ADAIcDAAMACQmYI4ADAIcDAAsABwmhHUcHAFQCAAAA.',
Ra='Ra:BAABLgAECn8qAAIaAAgJbh9vCwBpAghoDAAABgBSAGkMAAAIAFwAawwAAAgAXABqDAAABgBQAGwMAAAEAFAAbQwAAAIARQDqDAAABQBQAG4MAAADAEIAGgAICW4fbwsAaQIIaAwAAAYAUgBpDAAACABcAGsMAAAIAFwAagwAAAYAUABsDAAABABQAG0MAAACAEUA6gwAAAUAUABuDAAAAwBCAAAA.Radagast:BAACLgAFFH8UAAIeAAQJNw14TAACAQRoDAAABgAzAGkMAAAFACIAawwAAAMAGgDqDAAABgAXAB4ABAk3DXhMAAIBBGgMAAAGADMAaQwAAAUAIgBrDAAAAwAaAOoMAAAGABcALgAECn8xAAMeAAgJEBo1MAAAAgAeAAgJMxg1MAAAAgAaAAcJjhPbIgBZAQAAAA==.Radditz:BAAALgAECgYJCwAAAA==.Rafiki:BAAALgAECgEJAQAAAA==.Rand:BAAALgADCgcJDgAAAA==.',
Ri='Riv:BAAALgAECgMJAwAAAA==.',
Ro='Ronni:BAAALgAECgUJCgAAAA==.Roxyfox:BAAALgAECgYJCwAAAA==.Royvaz:BAAALgAECggJEQAAAA==.',
Sa='Salea:BAAALgAECgIJAgAAAA==.Sarryn:BAAALgADCgcJBwAAAA==.',
Sc='Scale:BAAALgAECgMJAwAAAA==.Schwiifty:BAAALgAECgMJCwAAAA==.',
Se='Serik:BAAALgADCgEJAQAAAA==.',
Sh='Shadorodo:BAAALgADCgIJAgAAAA==.Shakaboom:BAAALgAFFAEJAQAAAA==.Shakazoom:BAAALgAECgQJBAAAAA==.Sheffurs:BAABLgAECn87AAIGAAkJ0gPwOAC4AAloDAAABwAEAGkMAAAIAAYAawwAAAgABQBqDAAABwAGAGwMAAAHAAkAbQwAAAUADQDqDAAACQAcAG4MAAAFAAQAbwwAAAMABQAGAAkJ0gPwOAC4AAloDAAABwAEAGkMAAAIAAYAawwAAAgABQBqDAAABwAGAGwMAAAHAAkAbQwAAAUADQDqDAAACQAcAG4MAAAFAAQAbwwAAAMABQAAAA==.Shepardl:BAACLgAFFH8mAAISAAgJYyXPAAA9AwhoDAAABwBdAGkMAAAHAGEAawwAAAUAZABqDAAABgBNAGwMAAAEAGMAbQwAAAEAYgDqDAAABwBjAG4MAAABAGMAEgAICWMlzwAAPQMIaAwAAAcAXQBpDAAABwBhAGsMAAAFAGQAagwAAAYATQBsDAAABABjAG0MAAABAGIA6gwAAAcAYwBuDAAAAQBjAC4ABAp/IQACEgAICeQmGgEAgQMAEgAICeQmGgEAgQMAAAA=.Shredemdown:BAAALgAECgcJCQAAAA==.Shárkbait:BAAALgAECgEJAQABLgAFFAMJBwATAB4LAA==.',
Sk='Skadoosher:BAAALgAECgUJBQAAAA==.Skyratt:BAAALgAECgEJAgAAAA==.',
Sl='Sleepielight:BAAALgAFFAIJAwAAAA==.',
Sm='Smackemz:BAAALgAECgYJCQAAAA==.Smacmywand:BAAALgAECgIJBgAAAA==.',
So='Sollasi:BAAALgADCgMJBgAAAA==.Sortie:BAABLgAECn87AAMSAAkJWA33KwCtAQloDAAABwAhAGkMAAAIAAwAawwAAAgAMQBqDAAABwAPAGwMAAAHACQAbQwAAAUAGQDqDAAACQA0AG4MAAAFABMAbwwAAAMAPgASAAkJWA33KwCtAQloDAAAAwAhAGkMAAADAAwAawwAAAQAMQBqDAAAAwAPAGwMAAAEACQAbQwAAAMAGQDqDAAAAwA0AG4MAAABABMAbwwAAAMAPgAMAAgJCwosogAvAQhoDAAABAAvAGkMAAAFACMAawwAAAQAFABqDAAABAAkAGwMAAADAA4AbQwAAAIAEwDqDAAABgAaAG4MAAAEABAAAAA=.',
Sp='Spookybolt:BAAALgAECgEJAQAAAA==.Spoons:BAAALgAECgQJBAABLgAFFAUJFgAfAEocAA==.Spyromu:BAAALgAECgUJCwAAAA==.',
St='Stealman:BAAALgADCgcJBwAAAA==.Steeleman:BAAALgADCgQJAgAAAA==.',
Su='Succinic:BAAALgAECggJEAAAAA==.Suffer:BAAALgAECgUJCAAAAA==.',
Sw='Swiss:BAABLgAECn8bAAISAAgJrw1ONACsAQhoDAAABAA3AGkMAAAEACIAawwAAAQAKwBqDAAAAwAlAGwMAAADABoAbQwAAAMAEwDqDAAAAwA5AG4MAAADAAcAEgAICa8NTjQArAEIaAwAAAQANwBpDAAABAAiAGsMAAAEACsAagwAAAMAJQBsDAAAAwAaAG0MAAADABMA6gwAAAMAOQBuDAAAAwAHAAAA.',
Sy='Sylphvaria:BAAALgADCgUJBQAAAA==.Syren:BAAALgADCgcJBgAAAA==.',
Te='Tegridy:BAAALgAECgYJEwAAAA==.Teko:BAAALgADCgYJCwAAAA==.',
Th='Thegoose:BAAALgAECgIJAgAAAA==.Themans:BAAALgAECgYJDgAAAA==.Thunderrod:BAABLgAECn8lAAIVAAgJUBXOPgC0AQhoDAAABwBFAGkMAAAGAEwAawwAAAcARQBqDAAABgBRAGwMAAAFAEcAbQwAAAEAEADqDAAABAAwAG4MAAABAB0AFQAICVAVzj4AtAEIaAwAAAcARQBpDAAABgBMAGsMAAAHAEUAagwAAAYAUQBsDAAABQBHAG0MAAABABAA6gwAAAQAMABuDAAAAQAdAAAA.',
Ti='Tim:BAAALgAECgIJAgAAAA==.',
To='To:BAAALgAECgIJAgAAAA==.Tovisar:BAAALgAECgMJCQAAAA==.',
Tr='Traessa:BAAALgADCgYJBgAAAA==.',
Tu='Turkturkletn:BAAALgADCgcJEQAAAA==.',
Tw='Twogg:BAAALgAECgYJDgAAAA==.',
Ug='Ugin:BAAALgADCgYJBgAAAA==.Uglykasanova:BAAALgAECgYJEQAAAA==.',
Ul='Ulfrir:BAAALgAECgcJDQAAAA==.',
Va='Vastian:BAAALgAECgUJDgAAAA==.Vaynard:BAAALgAECgQJBAAAAA==.',
Vi='Violet:BAAALgAECgMJBQAAAA==.Vitre:BAAALgAECgUJBwAAAA==.',
Wa='Walkthrew:BAAALgAECgEJAQAAAA==.Wanshi:BAAALgAECgcJBgAAAA==.Waq:BAAALgAECggJDQAAAA==.',
We='Wexew:BAABLgAECn8aAAMKAAkJBhwHBwBbAgloDAAAAwA3AGkMAAAEADYAawwAAAQARwBqDAAAAwBYAGwMAAACAFgAbQwAAAEAEQDqDAAABwBjAG4MAAABAF0AbwwAAAEAXQAKAAkJ7xoHBwBbAgloDAAAAQAhAGkMAAADADYAawwAAAIARwBqDAAAAgBYAGwMAAACAFgAbQwAAAEAEQDqDAAABABjAG4MAAABAF0AbwwAAAEAXQAIAAUJChW+SgAdAQVoDAAAAgA3AGkMAAABADAAawwAAAIAMABqDAAAAQAuAOoMAAADAD4AAS4ABRQBCQEADgAAAAA=.Wexwex:BAAALgAECgUJDwABLgAFFAEJAQAOAAAAAA==.Wexxew:BAAALgAFFAEJAQAAAA==.',
Wi='Wishing:BAABLgAECn8bAAISAAgJlBToHQAPAghoDAAABABWAGkMAAAEACsAawwAAAQARwBqDAAABABGAGwMAAADAEIAbQwAAAEABQDqDAAABgA8AG4MAAABABEAEgAICZQU6B0ADwIIaAwAAAQAVgBpDAAABAArAGsMAAAEAEcAagwAAAQARgBsDAAAAwBCAG0MAAABAAUA6gwAAAYAPABuDAAAAQARAAAA.',
Wu='Wundertot:BAAALgAECgYJBgABLgAFFAQJCwAWAN8NAA==.Wunderwazard:BAACLgAFFH8LAAIWAAQJ3w0dZgAcAQRoDAAABAA0AGkMAAADACEAawwAAAEABQDqDAAAAwAxABYABAnfDR1mABwBBGgMAAAEADQAaQwAAAMAIQBrDAAAAQAFAOoMAAADADEALgAECn8sAAIWAAkJVR9PIgCRAgAWAAkJVR9PIgCRAgAAAA==.',
Xe='Xevikan:BAABLgAECn8bAAMBAAcJDBXhhQBUAQdoDAAABgBHAGkMAAAFADYAawwAAAUASwBqDAAAAgAnAGwMAAACACkAbQwAAAIAHADqDAAABQAzAAEABwkMFeGFAFQBB2gMAAAFAEcAaQwAAAUANgBrDAAABQBLAGoMAAACACcAbAwAAAIAKQBtDAAAAgAcAOoMAAAFADMAIAABCR8IJj0AKAABaAwAAAEAFAAAAA==.',
Ya='Yadead:BAAALgAECgcJDAAAAA==.',
Za='Zangief:BAAALgADCgEJAQAAAA==.Zaylen:BAAALgAECgYJEwABLgAFFAMJAwAOAAAAAA==.',
Ze='Zendjin:BAAALgADCgYJDQAAAA==.Zenlore:BAAALgADCgYJBgAAAA==.',
Zi='Zistormstout:BAABLgAECn8+AAIIAAgJ8RxJEwBNAghoDAAACgBIAGkMAAAKAD4AawwAAAkARgBqDAAACQBMAGwMAAAGAFsAbQwAAAIAOwDqDAAACwBNAG4MAAAFAFYACAAICfEcSRMATQIIaAwAAAoASABpDAAACgA+AGsMAAAJAEYAagwAAAkATABsDAAABgBbAG0MAAACADsA6gwAAAsATQBuDAAABQBWAAAA.',
Zu='Zuhgonemad:BAAALgAECgQJBgAAAA==.',
['Äl']='Älektra:BAABLgAECn8gAAIeAAgJvAQ7mwDlAAhoDAAABQAIAGkMAAAGAAwAawwAAAYADQBqDAAABAANAGwMAAADAAkAbQwAAAIADADqDAAABAAJAG8MAAACABIAHgAICbwEO5sA5QAIaAwAAAUACABpDAAABgAMAGsMAAAGAA0AagwAAAQADQBsDAAAAwAJAG0MAAACAAwA6gwAAAQACQBvDAAAAgASAAAA.',
['Ñe']='Ñeph:BAAALgAECggJDQAAAA==.',
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
