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

local lookup = {'DeathKnight-Unholy','Warlock-Affliction','Warlock-Demonology','Priest-Holy','Shaman-Elemental','Shaman-Restoration','Shaman-Enhancement','Warlock-Destruction','Paladin-Retribution','Priest-Shadow','Unknown-Unknown','Rogue-Assassination','Rogue-Subtlety','Hunter-Survival','Paladin-Holy','DeathKnight-Blood','Priest-Discipline','Druid-Restoration','Hunter-BeastMastery','Mage-Frost','Mage-Arcane','Paladin-Protection','DemonHunter-Vengeance','DemonHunter-Havoc','Warrior-Fury','Warrior-Arms','DemonHunter-Devourer','Druid-Guardian','Monk-Mistweaver','DeathKnight-Frost',}
local provider = {region='US',realm="Gul'dan",name='US',type='daily',zone=46,date='2026-06-03',data={Ae='Aeri:BAAALgAECgYJDAAAAA==.',
Al='Alastormoody:BAAALgADCgcJDAAAAA==.Alelover:BAAALgADCgUJBQAAAA==.Allaria:BAAALgAECgUJEQAAAA==.Almadíon:BAAALgADCgcJCAAAAA==.',
Am='Amosian:BAAALgADCgIJAgAAAA==.',
An='Ana:BAAALgADCgMJAwAAAA==.',
Ao='Aoemomma:BAAALgADCgcJBwAAAA==.',
Ar='Arin:BAAALgAECgIJAwABLgAFFAMJCgABAEEmAA==.',
As='Asuya:BAAALgADCgIJAwAAAA==.',
Az='Azög:BAAALgADCgUJBQAAAA==.',
Ba='Babysocks:BAAALgAECgYJBgAAAA==.',
Bc='Bc:BAACLgAFFH8HAAMCAAMJ3Rl4CADWAANsDAAAAQAVAG0MAAABAE0A6gwAAAUAYwACAAIJpSJ4CADWAAJtDAAAAQBNAOoMAAABAGMAAwACCRkXMYAAqwACbAwAAAEAFQDqDAAABABhAC4ABAp/GwACAwAICfgmMQMAjQMAAwAICfgmMQMAjQMAAAA=.',
Be='Beep:BAABLgAECn8lAAIDAAcJRh+JOgAiAgdoDAAABwBVAGkMAAAGAFMAawwAAAYAWABqDAAABgBdAGwMAAAFAE8AbQwAAAEALwDqDAAABgBgAAMABwlGH4k6ACICB2gMAAAHAFUAaQwAAAYAUwBrDAAABgBYAGoMAAAGAF0AbAwAAAUATwBtDAAAAQAvAOoMAAAGAGAAAAA=.',
Bl='Blackthunder:BAAALgAECggJDAAAAA==.',
Bo='Bobert:BAAALgADCgcJBgAAAA==.Bofadz:BAAALgADCgYJBgAAAA==.Boozecruise:BAAALgADCgIJAgAAAA==.Boozedrat:BAAALgAFFAEJAQABLgAFFAUJEAADAAcYAA==.Bowyn:BAABLgAECn8XAAIEAAYJHhNoOgBSAQZoDAAABAA3AGkMAAAFACYAawwAAAUAJgBqDAAAAwAYAGwMAAADADkA6gwAAAMAUAAEAAYJHhNoOgBSAQZoDAAABAA3AGkMAAAFACYAawwAAAUAJgBqDAAAAwAYAGwMAAADADkA6gwAAAMAUAAAAA==.',
Bu='Budleaf:BAAALgAECgYJEQAAAA==.Bunkley:BAABLgAECn8oAAQFAAgJRA+pMQBmAQhoDAAABwAXAGkMAAAGABwAawwAAAcAMQBqDAAABwA7AGwMAAADAE8AbQwAAAEAIwDqDAAABQAnAG4MAAAEABEABQAICeIOqTEAZgEIaAwAAAIAEwBpDAAAAgAZAGsMAAACADEAagwAAAMAOwBsDAAAAwBPAG0MAAABACMA6gwAAAQAJwBuDAAAAgARAAYABgkNDM9wAPMABmgMAAAEADkAaQwAAAMAEgBrDAAABQAjAGoMAAAEACMA6gwAAAEACABuDAAAAgAeAAcAAglHChAuAGIAAmgMAAABABcAaQwAAAEAHAAAAA==.Butterknives:BAAALgAECgEJAQAAAA==.',
By='Byege:BAACLgAFFH8QAAIDAAUJBxjTHQANAQVoDAAABABWAGkMAAADACUAawwAAAEAJABqDAAAAQAXAOoMAAAHAFUAAwAFCQcY0x0ADQEFaAwAAAQAVgBpDAAAAwAlAGsMAAABACQAagwAAAEAFwDqDAAABwBVAC4ABAp/JwADAwAJCccf0RUAmgIAAwAJCaMf0RUAmgIACAAFCc4XshsAcAEAAAA=.',
Ca='Cantfireme:BAAALgAECgYJCAABLgAECgkJOwAJAAUbAA==.Cardhunter:BAAALgADCgYJBgAAAA==.',
Ch='Champilon:BAAALgADCgcJDAAAAA==.Chaoticus:BAAALgAECgYJDQABLgAECggJIgAKAJgOAA==.Charizards:BAAALgADCgYJDQAAAA==.Charmahnder:BAAALgAECgIJAgAAAA==.',
Cr='Crunbard:BAAALgAECggJDwAAAA==.',
Cu='Culdan:BAABLgAECn8aAAMIAAYJ+QnCGQDHAAZoDAAABgAdAGkMAAAGABoAawwAAAcAIABqDAAAAgASAGwMAAACABEA6gwAAAMAFgAIAAYJ+QnCGQDHAAZoDAAAAQAdAGkMAAABABoAawwAAAUAIABqDAAAAgASAGwMAAACABEA6gwAAAIAFgADAAQJlgRz2gCXAARoDAAABQAIAGkMAAAFABMAawwAAAIACgDqDAAAAQAIAAAA.',
Da='Dalirus:BAAALgAECgQJBgABLgAECgkJOwAJAAUbAA==.Danahe:BAAALgAFFAEJAQABLgAFFAIJBAALAAAAAA==.Darci:BAAALgAECgcJEQABLgAECgQJCAALAAAAAA==.Darksuaza:BAAALgAECggJDQAAAA==.Darthwizard:BAAALgADCgIJAgAAAA==.Dasbunk:BAAALgAECgYJDAAAAA==.Dayman:BAAALgADCgYJBgAAAA==.',
De='Deadblue:BAABLgAECn84AAIIAAkJ+xlNAwBVAgloDAAABgBMAGkMAAAIAEgAawwAAAcANwBqDAAABwAuAGwMAAAHAD8AbQwAAAUAJgDqDAAACABMAG4MAAAFAFYAbwwAAAMAPwAIAAkJ+xlNAwBVAgloDAAABgBMAGkMAAAIAEgAawwAAAcANwBqDAAABwAuAGwMAAAHAD8AbQwAAAUAJgDqDAAACABMAG4MAAAFAFYAbwwAAAMAPwAAAA==.Deathblows:BAAALgAECgEJAQAAAA==.Deekay:BAAALgADCgcJFAAAAA==.',
Di='Diogee:BAAALgAECgMJBgAAAA==.Dirge:BAABLgAECn8YAAMMAAgJUBETCQCgAQhoDAAAAwAsAGkMAAADADUAawwAAAMAPABqDAAAAwAmAGwMAAAEAC4AbQwAAAIAKQDqDAAABAAkAG4MAAACABwADAAICVAREwkAoAEIaAwAAAIALABpDAAAAgA1AGsMAAACADwAagwAAAIAJgBsDAAABAAuAG0MAAACACkA6gwAAAMAJABuDAAAAgAcAA0ABQl9A7tGAH8ABWgMAAABAA4AaQwAAAEAEABrDAAAAQAAAGoMAAABAA8A6gwAAAEABAAAAA==.Discipline:BAAALgAECgYJDAABLgAFFAgJJAAOACwWAA==.Divinate:BAAALgAECgIJAgAAAA==.',
Dk='Dkpitador:BAAALgADCgEJAQAAAA==.',
Do='Doomhead:BAABLgAECn8YAAIBAAgJ2AhKhgBJAQhoDAAABAASAGkMAAAEABgAawwAAAQAEABqDAAAAwATAGwMAAACABkAbQwAAAEAHwDqDAAABQAaAG4MAAABABAAAQAICdgISoYASQEIaAwAAAQAEgBpDAAABAAYAGsMAAAEABAAagwAAAMAEwBsDAAAAgAZAG0MAAABAB8A6gwAAAUAGgBuDAAAAQAQAAAA.',
Dr='Drakki:BAAALgADCgUJBQAAAA==.Dreadfaith:BAAALgAECgYJBgAAAA==.',
Du='Durzii:BAACLgAFFH8FAAIPAAIJuiKBLAC2AAJoDAAAAwBVAGkMAAACAFwADwACCboigSwAtgACaAwAAAMAVQBpDAAAAgBcAC4ABAp/GQADDwAJCaogoRIAfQIADwAICd4hoRIAfQIACQABCe0ZalABTQAAAS4ABRQDCQYAEADTDwA=.',
Ea='Eatmybeef:BAAALgADCgYJCgAAAA==.',
Ex='Extinctionus:BAAALgAECgQJBQAAAA==.',
Fe='Fernn:BAAALgADCgQJBAAAAA==.',
Fi='Fia:BAABLgAECn84AAMBAAkJHROpTgDLAQloDAAACAA5AGkMAAAIADMAawwAAAcAQQBqDAAABwAsAGwMAAAHADkAbQwAAAUAOQDqDAAABwAzAG4MAAAFACAAbwwAAAIAEgABAAkJwQ+pTgDLAQloDAAABwAzAGkMAAAHADMAawwAAAYANQBqDAAABgAsAGwMAAAGACkAbQwAAAQAKwDqDAAABgAdAG4MAAAEACAAbwwAAAIAEgAQAAgJyxIhGACRAQhoDAAAAQA5AGkMAAABACQAawwAAAEAQQBqDAAAAQArAGwMAAABADkAbQwAAAEAOQDqDAAAAQAzAG4MAAABAAsAAAA=.',
Fu='Furor:BAAALgAECgQJBAAAAA==.',
Ge='Genaro:BAAALgAECgIJBwAAAA==.',
Gi='Gibraltar:BAAALgADCgUJBQAAAA==.',
Go='Gokujang:BAAALgAECgUJCgABLgAECggJHwARAK0YAA==.Goremont:BAAALgADCgQJBQAAAA==.Gorlok:BAAALgAECgUJBQAAAA==.',
Gr='Greendot:BAACLgAFFH8OAAISAAQJ1xOOJgAbAQRoDAAABABGAGkMAAAFAC8AawwAAAEAGQDqDAAABAA8ABIABAnXE44mABsBBGgMAAAEAEYAaQwAAAUALwBrDAAAAQAZAOoMAAAEADwALgAECn8tAAISAAkJkyJkAwCDAwASAAkJkyJkAwCDAwAAAA==.',
Gu='Gulvid:BAACLgAFFH8HAAIDAAIJlx0bhQCeAAJoDAAAAwBYAOoMAAAEAD8AAwACCZcdG4UAngACaAwAAAMAWADqDAAABAA/AC4ABAp/GAADAwAHCWQh0VMAmQEAAwAHCWQh0VMAmQEACAABCQAAqlwAWAAAAS4ABRQHCRsAAwBLFwA=.',
Ha='Haluak:BAABLgAECn8qAAIFAAkJExm5FQApAgloDAAABwBBAGkMAAAIAEsAawwAAAcASgBqDAAABQBOAGwMAAADADsAbQwAAAIAKADqDAAABwBXAG4MAAACACwAbwwAAAEAQgAFAAkJExm5FQApAgloDAAABwBBAGkMAAAIAEsAawwAAAcASgBqDAAABQBOAGwMAAADADsAbQwAAAIAKADqDAAABwBXAG4MAAACACwAbwwAAAEAQgAAAA==.',
He='Healthyself:BAAALgAECgYJCwAAAA==.',
Ho='Houndtamer:BAABLgAECn8xAAITAAgJdxT2RADDAQhoDAAACABFAGkMAAAIACkAawwAAAcALgBqDAAABwA+AGwMAAAFAC0AbQwAAAEAGgDqDAAACQBBAG4MAAAEAEgAEwAICXcU9kQAwwEIaAwAAAgARQBpDAAACAApAGsMAAAHAC4AagwAAAcAPgBsDAAABQAtAG0MAAABABoA6gwAAAkAQQBuDAAABABIAAAA.',
Hp='Hpyflowers:BAAALgADCgQJBAAAAA==.',
Hr='Hruoth:BAAALgAECgYJBgAAAA==.',
Ic='Iceshooting:BAAALgAECgQJBwAAAA==.',
Is='Ishtar:BAABLgAECn8ZAAMUAAYJ9BzVhADIAQZoDAAABQBFAGkMAAAFAFEAawwAAAQATQBqDAAABABMAGwMAAAEAFMA6gwAAAMAOgAUAAYJCRnVhADIAQZoDAAAAwAqAGkMAAAFAFEAawwAAAMATQBqDAAABABMAGwMAAAEAFMA6gwAAAIAIwAVAAMJzRkuDwDQAANoDAAAAgBFAGsMAAABAEYA6gwAAAEAOgAAAA==.',
It='Itshela:BAACLgAFFH8bAAMBAAcJfxh0GwDWAQdoDAAABgBRAGkMAAAEAFUAawwAAAMAJgBqDAAABgA2AGwMAAACACAAbQwAAAEAPgDqDAAABQBMAAEABgl/GHQbANYBBmgMAAAGAFEAaQwAAAQAVQBrDAAAAwAmAGwMAAACACAAbQwAAAEAPgDqDAAABQBMABAAAQkAANdMAAAAAWoMAAAGADYALgAECn8bAAIBAAcJOCPrTQAJAgABAAcJOCPrTQAJAgAAAA==.',
Ja='Jayrad:BAAALgAECgYJEQAAAA==.',
Je='Jehnovah:BAAALgADCgMJAwAAAA==.Jellybeanz:BAAALgADCggJDQAAAA==.',
Jo='Jordybear:BAAALgAECgQJBAAAAA==.Jorkoh:BAAALgAECgMJBgAAAA==.',
Ju='Juicer:BAAALgADCgMJBgAAAA==.',
Ka='Kaiige:BAAALgAECgQJBAAAAA==.Kairos:BAAALgAECgYJCgAAAA==.Kanê:BAAALgAFFAMJAwAAAA==.',
Ke='Kehlayr:BAAALgADCgMJAwAAAA==.Keiiry:BAAALgADCgMJAwAAAA==.Kenshinth:BAAALgAECgYJDwAAAA==.Kethrym:BAAALgAECgIJAgAAAA==.',
Kh='Khanor:BAAALgAECgYJEQAAAA==.',
Ki='Kiltro:BAAALgAECgQJBgAAAA==.Kimchichi:BAABLgAECn8cAAIJAAgJAR0xKgBKAghoDAAABgBeAGkMAAAFAEsAawwAAAUAPgBqDAAABABUAGwMAAACAFAAbQwAAAIAVwDqDAAAAgA4AG4MAAACAD4ACQAICQEdMSoASgIIaAwAAAYAXgBpDAAABQBLAGsMAAAFAD4AagwAAAQAVABsDAAAAgBQAG0MAAACAFcA6gwAAAIAOABuDAAAAgA+AAAA.Kintaro:BAAALgADCgYJDwAAAA==.',
Ko='Kogorko:BAAALgAECgMJBQAAAA==.',
Kr='Kry:BAAALgAECgIJAgAAAA==.',
['Kë']='Këarra:BAAALgAECgQJBwAAAA==.',
La='Labotimizer:BAAALgAECggJDwAAAA==.Lapriestess:BAAALgAECgYJCwAAAA==.Latoya:BAABLgAFFH8FAAIUAAMJPwdMfwDKAANoDAAAAgAVAGkMAAACAAkA6gwAAAEAGAAUAAMJPwdMfwDKAANoDAAAAgAVAGkMAAACAAkA6gwAAAEAGAAAAA==.',
Li='Lilbeemo:BAAALgAECgUJCgAAAA==.Lilyana:BAAALgAECgYJCwAAAA==.Liongs:BAAALgAECgYJBwABLgAECgYJDwALAAAAAA==.Litdk:BAAALgADCgUJBQAAAA==.Litharidk:BAABLgAECn8dAAIBAAgJ5B/RLwAzAghoDAAABgBZAGkMAAAHAFkAawwAAAUATQBqDAAAAwBdAGwMAAACAEoAbQwAAAEATgDqDAAABABXAG8MAAABAEoAAQAICeQf0S8AMwIIaAwAAAYAWQBpDAAABwBZAGsMAAAFAE0AagwAAAMAXQBsDAAAAgBKAG0MAAABAE4A6gwAAAQAVwBvDAAAAQBKAAAA.',
Lo='Lotion:BAAALgAECgEJAQAAAA==.Loudog:BAAALgAECgYJBwAAAA==.Loxyblue:BAAALgAECgMJAwAAAA==.',
Lu='Luckyxpain:BAABLgAECn87AAMJAAkJBRvBJQBeAgloDAAACgBRAGkMAAAHAD0AawwAAAkARQBqDAAABwBcAGwMAAAKAD8AbQwAAAQAXgDqDAAABgBLAG4MAAAEAE8AbwwAAAIAGwAJAAkJBRvBJQBeAgloDAAABwBRAGkMAAAGAD0AawwAAAcARQBqDAAABQBcAGwMAAAFAD8AbQwAAAMAXgDqDAAAAwBLAG4MAAAEAE8AbwwAAAIAGwAWAAcJbwsJKADEAAdoDAAAAwARAGkMAAABABwAawwAAAIAEQBqDAAAAgApAGwMAAAFABsAbQwAAAEALwDqDAAAAwAkAAAA.',
Ly='Lykos:BAAALgAECgIJAgAAAA==.',
Ma='Madoff:BAAALgAECgQJCAAAAA==.Makok:BAABLgAECn8eAAMXAAkJnRTCCADRAQloDAAABQBJAGkMAAAEAEUAawwAAAQAJgBqDAAAAwAmAGwMAAACAB0AbQwAAAEAKgDqDAAABwA7AG4MAAADAEUAbwwAAAEAJgAXAAkJnRTCCADRAQloDAAABQBJAGkMAAAEAEUAawwAAAQAJgBqDAAAAwAmAGwMAAACAB0AbQwAAAEAKgDqDAAABgA7AG4MAAADAEUAbwwAAAEAJgAYAAEJ7AnycQAzAAHqDAAAAQAZAAAA.',
Me='Melancholic:BAABLgAECn8nAAMZAAkJyR9hCwClAgloDAAABwBWAGkMAAAHAFIAawwAAAYARwBqDAAABQBWAGwMAAADAFYAbQwAAAEASwDqDAAABwBhAG4MAAACAE8AbwwAAAEARwAZAAkJyR9hCwClAgloDAAABgBWAGkMAAAHAFIAawwAAAYARwBqDAAABQBWAGwMAAADAFYAbQwAAAEASwDqDAAABwBhAG4MAAACAE8AbwwAAAEARwAaAAEJxQSndQAoAAFoDAAAAQAMAAAA.Mellisa:BAABLgAECn8fAAMBAAkJcxFZagCEAQloDAAABwBIAGkMAAAEADUAawwAAAUANwBqDAAAAwBEAGwMAAACABgAbQwAAAEAEgDqDAAABwBNAG4MAAABABIAbwwAAAEAJAABAAgJ2w9ZagCEAQhoDAAABgBIAGkMAAADABAAawwAAAQANwBqDAAAAwBEAGwMAAACABgAbQwAAAEAEgDqDAAABgBNAG4MAAABABIAEAAFCXUTHCcACwEFaAwAAAEALgBpDAAAAQA1AGsMAAABADQA6gwAAAEAPABvDAAAAQAkAAAA.Memory:BAAALgAECgEJAwAAAA==.',
Mi='Milkingman:BAAALgAECgQJAgAAAA==.',
Mo='Mooshmoo:BAAALgAECgEJAQAAAA==.',
Mu='Murog:BAABLgAECn8dAAMGAAgJSQ0ySgBzAQhoDAAAAwAvAGkMAAADADEAawwAAAMAEQBqDAAABAArAGwMAAAFADIAbQwAAAIAEgDqDAAABwAgAG4MAAACAAwABgAICUkNMkoAcwEIaAwAAAIALwBpDAAAAgAxAGsMAAACABEAagwAAAMAKwBsDAAABAAyAG0MAAACABIA6gwAAAYAIABuDAAAAgAMAAcABgk9Ax4lAK4ABmgMAAABAAgAaQwAAAEACQBrDAAAAQAKAGoMAAABAAYAbAwAAAEACADqDAAAAQAEAAAA.',
Na='Nazarite:BAAALgAECgYJDwAAAA==.',
Ni='Nightdisco:BAAALgAECgMJAwAAAA==.',
No='Noctyra:BAAALgAECgQJCAAAAA==.Nomaana:BAAALgAECgMJAwAAAA==.Norael:BAAALgADCgIJAgAAAA==.',
Og='Ogthunder:BAAALgAECgEJAQAAAA==.',
Op='Ophellia:BAAALgAECgEJAQAAAA==.',
Pu='Pureformance:BAAALgADCgcJBwABLgAFFAgJIwASAFUjAA==.Purrformance:BAACLgAFFH8jAAISAAgJVSNBAQA9AwhoDAAABwBgAGkMAAAHAGEAawwAAAUAXABqDAAABABNAGwMAAACAF0AbQwAAAEAUADqDAAACABiAG4MAAABAFYAEgAICVUjQQEAPQMIaAwAAAcAYABpDAAABwBhAGsMAAAFAFwAagwAAAQATQBsDAAAAgBdAG0MAAABAFAA6gwAAAgAYgBuDAAAAQBWAC4ABAp/IgACEgAJCaIlDAEApwMAEgAJCaIlDAEApwMAAAA=.',
Py='Pyrophobiac:BAACLgAFFH8eAAMDAAgJDxnPCQA4AghoDAAABQBLAGkMAAAEABgAawwAAAQAOgBqDAAAAgAbAGwMAAAEAFgAbQwAAAMAJwDqDAAABgBPAG4MAAACAFQAAwAICQ8ZzwkAOAIIaAwAAAUASwBpDAAAAwAYAGsMAAACADoAagwAAAIAGwBsDAAABABYAG0MAAADACcA6gwAAAYATwBuDAAAAgBUAAgAAglYAkoPAH8AAmkMAAABAAcAawwAAAIABAAuAAQKfyMAAwMACQnaI4ADAIcDAAMACQmYI4ADAIcDAAgABwmhHUcHAFQCAAAA.',
Ra='Ra:BAABLgAECn8kAAIYAAgJbh9RCgBuAghoDAAABQBSAGkMAAAGAFwAawwAAAYAXABqDAAABQBQAGwMAAAEAFAAbQwAAAIARQDqDAAABQBQAG4MAAADAEIAGAAICW4fUQoAbgIIaAwAAAUAUgBpDAAABgBcAGsMAAAGAFwAagwAAAUAUABsDAAABABQAG0MAAACAEUA6gwAAAUAUABuDAAAAwBCAAAA.Radagast:BAACLgAFFH8PAAIbAAQJ8wxVRQAIAQRoDAAABQAzAGkMAAAEACIAawwAAAIAGgDqDAAABAAUABsABAnzDFVFAAgBBGgMAAAFADMAaQwAAAQAIgBrDAAAAgAaAOoMAAAEABQALgAECn8wAAMbAAgJIRmnMgDvAQAbAAgJRBenMgDvAQAYAAcJjhORIABaAQAAAA==.Radditz:BAAALgAECgYJCwAAAA==.Rafiki:BAAALgAECgEJAQAAAA==.Rand:BAAALgADCgcJDgAAAA==.',
Ri='Riv:BAAALgAECgMJAwAAAA==.',
Ro='Ronni:BAAALgAECgUJCQAAAA==.Roxyfox:BAAALgAECgYJCwAAAA==.Royvaz:BAAALgAECgUJBQAAAA==.',
Sa='Salea:BAAALgAECgIJAgAAAA==.Sarryn:BAAALgADCgcJBwAAAA==.',
Sc='Scale:BAAALgAECgMJAwAAAA==.Schwiifty:BAAALgAECgMJCAAAAA==.',
Se='Serik:BAAALgADCgEJAQAAAA==.',
Sh='Shadorodo:BAAALgADCgIJAgAAAA==.Shakaboom:BAAALgAFFAEJAQAAAA==.Shakazoom:BAAALgAECgQJBAAAAA==.Sheffurs:BAABLgAECn84AAIcAAkJEgNUNwCtAAloDAAABgAEAGkMAAAIAAYAawwAAAcABQBqDAAABwAGAGwMAAAHAAkAbQwAAAUADQDqDAAACAANAG4MAAAFAAQAbwwAAAMABQAcAAkJEgNUNwCtAAloDAAABgAEAGkMAAAIAAYAawwAAAcABQBqDAAABwAGAGwMAAAHAAkAbQwAAAUADQDqDAAACAANAG4MAAAFAAQAbwwAAAMABQAAAA==.Shepardl:BAACLgAFFH8mAAIPAAgJYyWBAABNAwhoDAAABwBdAGkMAAAHAGEAawwAAAUAZABqDAAABgBNAGwMAAAEAGMAbQwAAAEAYgDqDAAABwBjAG4MAAABAGMADwAICWMlgQAATQMIaAwAAAcAXQBpDAAABwBhAGsMAAAFAGQAagwAAAYATQBsDAAABABjAG0MAAABAGIA6gwAAAcAYwBuDAAAAQBjAC4ABAp/IQACDwAICeQmGgEAgQMADwAICeQmGgEAgQMAAAA=.Shárkbait:BAAALgAECgEJAQABLgAECgUJDAALAAAAAA==.',
Sk='Skadoosher:BAAALgAECgUJBQAAAA==.Skyratt:BAAALgAECgEJAgAAAA==.',
Sl='Sleepielight:BAAALgAECgMJAwAAAA==.',
Sm='Smackemz:BAAALgAECgYJCQAAAA==.Smacmywand:BAAALgAECgIJBgAAAA==.',
So='Sollasi:BAAALgADCgMJBgAAAA==.Sortie:BAABLgAECn84AAMPAAkJCwv5LgCRAQloDAAABgAHAGkMAAAIAAwAawwAAAcAFwBqDAAABwAPAGwMAAAHACQAbQwAAAUAGQDqDAAACAA0AG4MAAAFABMAbwwAAAMAPgAPAAkJCwv5LgCRAQloDAAAAgAHAGkMAAADAAwAawwAAAMAFwBqDAAAAwAPAGwMAAAEACQAbQwAAAMAGQDqDAAAAgA0AG4MAAABABMAbwwAAAMAPgAJAAgJCwrPmAA0AQhoDAAABAAvAGkMAAAFACMAawwAAAQAFABqDAAABAAkAGwMAAADAA4AbQwAAAIAEwDqDAAABgAaAG4MAAAEABAAAAA=.',
Sp='Spoons:BAAALgAECgQJBAABLgAFFAUJFgAdAEocAA==.Spyromu:BAAALgAECgUJCwAAAA==.',
St='Stealman:BAAALgADCgcJBwAAAA==.Steeleman:BAAALgADCgQJAgAAAA==.',
Su='Succinic:BAAALgAECggJEAAAAA==.Suffer:BAAALgAECgUJCAAAAA==.',
Sw='Swiss:BAABLgAECn8bAAIPAAgJrw1ONACsAQhoDAAABAA3AGkMAAAEACIAawwAAAQAKwBqDAAAAwAlAGwMAAADABoAbQwAAAMAEwDqDAAAAwA5AG4MAAADAAcADwAICa8NTjQArAEIaAwAAAQANwBpDAAABAAiAGsMAAAEACsAagwAAAMAJQBsDAAAAwAaAG0MAAADABMA6gwAAAMAOQBuDAAAAwAHAAAA.',
Sy='Sylphvaria:BAAALgADCgUJBQAAAA==.Syren:BAAALgADCgcJBgAAAA==.',
Te='Tegridy:BAAALgAECgYJEQAAAA==.Teko:BAAALgADCgYJCwAAAA==.',
Th='Thegoose:BAAALgAECgIJAgAAAA==.Themans:BAAALgAECgYJDgAAAA==.Thunderrod:BAABLgAECn8lAAITAAgJUBXOPgC0AQhoDAAABwBFAGkMAAAGAEwAawwAAAcARQBqDAAABgBRAGwMAAAFAEcAbQwAAAEAEADqDAAABAAwAG4MAAABAB0AEwAICVAVzj4AtAEIaAwAAAcARQBpDAAABgBMAGsMAAAHAEUAagwAAAYAUQBsDAAABQBHAG0MAAABABAA6gwAAAQAMABuDAAAAQAdAAAA.',
Ti='Tim:BAAALgAECgIJAgAAAA==.',
To='To:BAAALgAECgIJAgAAAA==.Tovisar:BAAALgAECgMJCQAAAA==.',
Tr='Traessa:BAAALgADCgYJBgAAAA==.',
Tu='Turkturkletn:BAAALgADCgcJEQAAAA==.',
Tw='Twogg:BAAALgAECgYJDgAAAA==.',
Ug='Ugin:BAAALgADCgYJBgAAAA==.Uglykasanova:BAAALgAECgYJEQAAAA==.',
Ul='Ulfrir:BAAALgAECgcJDQAAAA==.',
Va='Vastian:BAAALgAECgUJDgAAAA==.Vaynard:BAAALgAECgQJBAAAAA==.',
Vi='Violet:BAAALgAECgMJBQAAAA==.Vitre:BAAALgAECgUJBwAAAA==.',
Wa='Wanshi:BAAALgAECgcJBgAAAA==.Waq:BAAALgAECgYJBwAAAA==.',
We='Wexew:BAABLgAECn8ZAAMHAAkJQRrPCAAlAgloDAAAAwA3AGkMAAAEADYAawwAAAQARwBqDAAAAwBYAGwMAAACAFgAbQwAAAEAEQDqDAAABgA+AG4MAAABAF0AbwwAAAEAXQAHAAkJHRnPCAAlAgloDAAAAQAhAGkMAAADADYAawwAAAIARwBqDAAAAgBYAGwMAAACAFgAbQwAAAEAEQDqDAAAAwA9AG4MAAABAF0AbwwAAAEAXQAFAAUJChW+SgAdAQVoDAAAAgA3AGkMAAABADAAawwAAAIAMABqDAAAAQAuAOoMAAADAD4AAS4ABRQBCQEACwAAAAA=.Wexwex:BAAALgAECgUJDwABLgAFFAEJAQALAAAAAA==.Wexxew:BAAALgAFFAEJAQAAAA==.',
Wi='Wishing:BAABLgAECn8XAAIPAAgJnw/lJwC9AQhoDAAAAwA2AGkMAAADABwAawwAAAMAEABqDAAABABGAGwMAAADAEIAbQwAAAEABQDqDAAABQA8AG4MAAABABEADwAICZ8P5ScAvQEIaAwAAAMANgBpDAAAAwAcAGsMAAADABAAagwAAAQARgBsDAAAAwBCAG0MAAABAAUA6gwAAAUAPABuDAAAAQARAAAA.',
Wu='Wundertot:BAAALgAECgYJBgABLgAFFAMJBwAUALkRAA==.Wunderwazard:BAACLgAFFH8HAAIUAAMJuREicgDkAANoDAAAAwA0AGkMAAACACEA6gwAAAIAMQAUAAMJuREicgDkAANoDAAAAwA0AGkMAAACACEA6gwAAAIAMQAuAAQKfyoAAhQACAksIBU0AD0CABQACAksIBU0AD0CAAAA.',
Xe='Xevikan:BAABLgAECn8bAAMBAAcJDBUNgABVAQdoDAAABgBHAGkMAAAFADYAawwAAAUASwBqDAAAAgAnAGwMAAACACkAbQwAAAIAHADqDAAABQAzAAEABwkMFQ2AAFUBB2gMAAAFAEcAaQwAAAUANgBrDAAABQBLAGoMAAACACcAbAwAAAIAKQBtDAAAAgAcAOoMAAAFADMAHgABCR8IuDcAKgABaAwAAAEAFAAAAA==.',
Ya='Yadead:BAAALgAECgYJCwAAAA==.',
Za='Zaylen:BAAALgAECgYJEwABLgAFFAEJAQALAAAAAA==.',
Ze='Zendjin:BAAALgADCgYJDQAAAA==.Zenlore:BAAALgADCgYJBgAAAA==.',
Zi='Zistormstout:BAABLgAECn8yAAIFAAgJYBpSGAAQAghoDAAACABIAGkMAAAIAD4AawwAAAcAQwBqDAAABwBMAGwMAAAFAFAAbQwAAAEAJgDqDAAACgBNAG4MAAAEAEoABQAICWAaUhgAEAIIaAwAAAgASABpDAAACAA+AGsMAAAHAEMAagwAAAcATABsDAAABQBQAG0MAAABACYA6gwAAAoATQBuDAAABABKAAAA.',
Zu='Zuhgonemad:BAAALgAECgQJBgAAAA==.',
['Äl']='Älektra:BAABLgAECn8gAAIbAAgJvATckgDoAAhoDAAABQAIAGkMAAAGAAwAawwAAAYADQBqDAAABAANAGwMAAADAAkAbQwAAAIADADqDAAABAAJAG8MAAACABIAGwAICbwE3JIA6AAIaAwAAAUACABpDAAABgAMAGsMAAAGAA0AagwAAAQADQBsDAAAAwAJAG0MAAACAAwA6gwAAAQACQBvDAAAAgASAAAA.',
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
