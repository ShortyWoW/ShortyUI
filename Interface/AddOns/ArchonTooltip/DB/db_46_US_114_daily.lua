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

local lookup = {'DeathKnight-Unholy','Warlock-Demonology','Priest-Holy','Shaman-Restoration','Shaman-Elemental','Warlock-Destruction','Paladin-Retribution','Priest-Shadow','Unknown-Unknown','Hunter-Survival','Paladin-Holy','Druid-Restoration','Hunter-BeastMastery','Mage-Frost','Mage-Arcane','DeathKnight-Blood','Paladin-Protection','DemonHunter-Vengeance','DemonHunter-Havoc','Warrior-Fury','Warrior-Arms','DemonHunter-Devourer','Druid-Guardian','Shaman-Enhancement','Monk-Windwalker',}
local provider = {region='US',realm="Gul'dan",name='US',type='daily',zone=46,date='2026-05-11',data={Ae='Aeri:BAAALgAECgYJDAAAAA==.',
Al='Alastormoody:BAAALgADCgcJDAAAAA==.Alelover:BAAALgADCgUJBQAAAA==.Allaria:BAAALgAECgMJBgAAAA==.Almadíon:BAAALgADCgcJCAAAAA==.',
Am='Amosian:BAAALgADCgIJAgAAAA==.',
An='Ana:BAAALgADCgMJAwAAAA==.',
Ar='Arin:BAAALgAECgIJAwABLgAFFAMJCgABAEEmAA==.',
As='Asuya:BAAALgADCgIJAwAAAA==.',
Az='Azög:BAAALgADCgUJBQAAAA==.',
Ba='Babysocks:BAAALgAECgYJBgAAAA==.',
Bc='Bc:BAEBLgAECn8YAAICAAgJ+CYwAwCNAwhoDAAAAgBjAGkMAAADAGMAawwAAAMAYwBqDAAABABjAGwMAAAEAGMAbQwAAAMAYwDqDAAAAgBjAG4MAAADAGMAAgAICfgmMAMAjQMIaAwAAAIAYwBpDAAAAwBjAGsMAAADAGMAagwAAAQAYwBsDAAABABjAG0MAAADAGMA6gwAAAIAYwBuDAAAAwBjAAAA.',
Be='Beep:BAABLgAECn8kAAICAAcJRh9EJgDcAQdoDAAABwBVAGkMAAAGAFMAawwAAAYAWABqDAAABgBdAGwMAAAFAE8AbQwAAAEALwDqDAAABQBgAAIABwlGH0QmANwBB2gMAAAHAFUAaQwAAAYAUwBrDAAABgBYAGoMAAAGAF0AbAwAAAUATwBtDAAAAQAvAOoMAAAFAGAAAAA=.',
Bl='Blackthunder:BAAALgAECgQJBAAAAA==.',
Bo='Bobert:BAAALgADCgcJBgAAAA==.Bofadz:BAAALgADCgYJBgAAAA==.Boozecruise:BAAALgADCgIJAgAAAA==.Bowyn:BAABLgAECn8XAAIDAAYJHhNnOgBSAQZoDAAABAA3AGkMAAAFACYAawwAAAUAJgBqDAAAAwAYAGwMAAADADkA6gwAAAMAUAADAAYJHhNnOgBSAQZoDAAABAA3AGkMAAAFACYAawwAAAUAJgBqDAAAAwAYAGwMAAADADkA6gwAAAMAUAAAAA==.',
Bu='Budleaf:BAAALgAECgUJCQAAAA==.Bunkley:BAABLgAECn8VAAMEAAYJVQr5SgDtAAZoDAAABQA5AGkMAAAEABIAawwAAAUAIwBqDAAAAwAjAOoMAAADAAgAbgwAAAEABAAEAAYJVQr5SgDtAAZoDAAABAA5AGkMAAADABIAawwAAAUAIwBqDAAAAwAjAOoMAAABAAgAbgwAAAEABAAFAAMJTgSdUgBtAANoDAAAAQAEAGkMAAABAAkA6gwAAAIAEgAAAA==.Butterknives:BAAALgAECgEJAQAAAA==.',
By='Byege:BAACLgAFFH8MAAICAAUJBxi5IgA7AQVoDAAAAwBWAGkMAAADACUAawwAAAEAJABqDAAAAQAXAOoMAAAEAFUAAgAFCQcYuSIAOwEFaAwAAAMAVgBpDAAAAwAlAGsMAAABACQAagwAAAEAFwDqDAAABABVAC4ABAp/JwADAgAJCcYfngcA1wIAAgAJCaEfngcA1wIABgAFCc4XshsAcAEAAAA=.',
Ca='Cantfireme:BAAALgADCgcJBwABLgAECgcJLwAHABoZAA==.Cardhunter:BAAALgADCgYJBgAAAA==.Cash:BAAALgAECgcJDAAAAA==.',
Ch='Champilon:BAAALgADCgYJBQAAAA==.Chaoticus:BAAALgAECgYJDQABLgAECggJIgAIAJgOAA==.Charizards:BAAALgADCgYJDQAAAA==.Charmahnder:BAAALgAECgIJAgAAAA==.',
Cr='Crunbard:BAAALgAECgcJDQAAAA==.',
Cu='Culdan:BAABLgAECn8XAAMGAAYJfwfAFQCuAAZoDAAABQAIAGkMAAAFABoAawwAAAYAFQBqDAAAAgASAGwMAAACABEA6gwAAAMAFgAGAAUJhQjAFQCuAAVpDAAAAQAaAGsMAAAEABUAagwAAAIAEgBsDAAAAgARAOoMAAACABYAAgAECR8EEpsAnAAEaAwAAAUACABpDAAABAAOAGsMAAACAAoA6gwAAAEACAAAAA==.',
Da='Dalirus:BAAALgADCgcJDgABLgAECgcJLwAHABoZAA==.Darci:BAAALgAECgcJCwABLgAECgQJCAAJAAAAAA==.Darksuaza:BAAALgAECgcJCwAAAA==.Darthwizard:BAAALgADCgIJAgAAAA==.Dayman:BAAALgADCgYJBgAAAA==.',
De='Deadblue:BAABLgAECn8eAAIGAAgJTxYSBADgAQhoDAAABABHAGkMAAAFADkAawwAAAQALABqDAAABAAqAGwMAAAEAC0AbQwAAAIAEgDqDAAABQBMAG4MAAACAFYABgAICU8WEgQA4AEIaAwAAAQARwBpDAAABQA5AGsMAAAEACwAagwAAAQAKgBsDAAABAAtAG0MAAACABIA6gwAAAUATABuDAAAAgBWAAAA.Deekay:BAAALgADCgcJFAAAAA==.',
Di='Diogee:BAAALgAECgMJBgAAAA==.Discipline:BAAALgAECgYJDAABLgAFFAYJGQAKADgVAA==.Divinate:BAAALgAECgIJAgAAAA==.',
Dk='Dkpitador:BAAALgADCgEJAQAAAA==.',
Do='Doomhead:BAAALgAECggJEwAAAA==.',
Dr='Drakki:BAAALgADCgUJBQAAAA==.Dreadfaith:BAAALgAECgYJBgAAAA==.',
Du='Durzii:BAABLgAECn8XAAILAAgJ3iGiEgB9AghoDAAABABjAGkMAAAEAFwAawwAAAQAWQBqDAAAAwBhAGwMAAABAFsAbQwAAAEAQQDqDAAABQBjAG4MAAABADoACwAICd4hohIAfQIIaAwAAAQAYwBpDAAABABcAGsMAAAEAFkAagwAAAMAYQBsDAAAAQBbAG0MAAABAEEA6gwAAAUAYwBuDAAAAQA6AAAA.',
Ea='Eatmybeef:BAAALgADCgYJCgAAAA==.',
Ex='Extinctionus:BAAALgAECgQJBQAAAA==.',
Fe='Fernn:BAAALgADCgQJBAAAAA==.',
Fi='Fia:BAABLgAECn8nAAIBAAkJwA4AKQDsAQloDAAABgAzAGkMAAAGADMAawwAAAUANQBqDAAABQAsAGwMAAAFACAAbQwAAAMAKwDqDAAABQATAG4MAAADACAAbwwAAAEAEAABAAkJwA4AKQDsAQloDAAABgAzAGkMAAAGADMAawwAAAUANQBqDAAABQAsAGwMAAAFACAAbQwAAAMAKwDqDAAABQATAG4MAAADACAAbwwAAAEAEAAAAA==.',
Fu='Furor:BAAALgAECgQJBAAAAA==.',
Ge='Genaro:BAAALgAECgIJBwAAAA==.',
Gi='Gibraltar:BAAALgADCgUJBQAAAA==.',
Go='Gokujang:BAAALgAECgUJCgABLgAECgcJCgAJAAAAAA==.Goremont:BAAALgADCgQJBQAAAA==.Gorlok:BAAALgAECgUJBQAAAA==.',
Gr='Greendot:BAABLgAECn8dAAIMAAgJViJJBgD9AghoDAAABgBbAGkMAAAFAF0AawwAAAQAWgBqDAAAAwBbAGwMAAACAF4AbQwAAAIAWwDqDAAABgBbAG4MAAABADsADAAICVYiSQYA/QIIaAwAAAYAWwBpDAAABQBdAGsMAAAEAFoAagwAAAMAWwBsDAAAAgBeAG0MAAACAFsA6gwAAAYAWwBuDAAAAQA7AAAA.',
Gu='Gulvid:BAAALgAFFAMJAwABLgAFFAYJEAACAO8PAA==.',
Ha='Haluak:BAABLgAECn8lAAIFAAgJ8Rf0EADpAQhoDAAABwBBAGkMAAAHAEsAawwAAAYASgBqDAAABABOAGwMAAADADsAbQwAAAIAKADqDAAABgBFAG4MAAACACwABQAICfEX9BAA6QEIaAwAAAcAQQBpDAAABwBLAGsMAAAGAEoAagwAAAQATgBsDAAAAwA7AG0MAAACACgA6gwAAAYARQBuDAAAAgAsAAAA.',
He='Healthyself:BAAALgAECgQJBQAAAA==.',
Ho='Houndtamer:BAABLgAECn8dAAINAAcJDRNoOgB0AQdoDAAABQArAGkMAAAFACkAawwAAAUAJABqDAAABQAqAGwMAAADAC0A6gwAAAUANgBuDAAAAQBGAA0ABwkNE2g6AHQBB2gMAAAFACsAaQwAAAUAKQBrDAAABQAkAGoMAAAFACoAbAwAAAMALQDqDAAABQA2AG4MAAABAEYAAAA=.',
Hp='Hpyflowers:BAAALgADCgQJBAAAAA==.',
Hr='Hruoth:BAAALgAECgYJBgAAAA==.',
Ic='Iceshooting:BAAALgAECgQJBwAAAA==.',
Is='Ishtar:BAABLgAECn8ZAAMOAAYJ9BzThADIAQZoDAAABQBFAGkMAAAFAFEAawwAAAQATQBqDAAABABMAGwMAAAEAFMA6gwAAAMAOgAOAAYJCRnThADIAQZoDAAAAwAqAGkMAAAFAFEAawwAAAMATQBqDAAABABMAGwMAAAEAFMA6gwAAAIAIwAPAAMJzRkuDwDQAANoDAAAAgBFAGsMAAABAEYA6gwAAAEAOgAAAA==.',
It='Itshela:BAACLgAFFH8QAAMBAAUJixs8KwBRAQVoDAAABQBRAGkMAAADAFUAawwAAAIAJgBqDAAAAwAqAOoMAAADAEwAAQAECYsbPCsAUQEEaAwAAAUAUQBpDAAAAwBVAGsMAAACACYA6gwAAAMATAAQAAEJAAD8MAAAAAFqDAAAAwAqAC4ABAp/GwACAQAHCTQj5k0ACQIAAQAHCTQj5k0ACQIAAAA=.',
Ja='Jayrad:BAAALgAECgQJCgAAAA==.',
Je='Jehnovah:BAAALgADCgMJAwAAAA==.Jellybeanz:BAAALgADCggJDQAAAA==.',
Jo='Jordybear:BAAALgAECgMJAwAAAA==.Jorkoh:BAAALgAECgMJBgAAAA==.',
Ju='Juicer:BAAALgADCgMJBgAAAA==.',
Ka='Kaiige:BAAALgAECgMJAwAAAA==.Kairos:BAAALgAECgYJCgAAAA==.',
Ke='Kehlayr:BAAALgADCgMJAwAAAA==.Keiiry:BAAALgADCgMJAwAAAA==.Kenshinth:BAAALgAECgQJCQAAAA==.Kethrym:BAAALgAECgIJAgAAAA==.',
Kh='Khanor:BAAALgAECgYJEQAAAA==.',
Ki='Kiltro:BAAALgAECgQJBgAAAA==.Kimchichi:BAAALgAECgYJCgAAAA==.Kintaro:BAAALgADCgUJBgAAAA==.',
Ko='Kogorko:BAAALgAECgIJAgAAAA==.',
Kr='Kry:BAAALgAECgIJAgAAAA==.',
['Kë']='Këarra:BAAALgAECgQJBwAAAA==.',
La='Labotimizer:BAAALgAECgcJDwAAAA==.Lapriestess:BAAALgAECgQJBQAAAA==.Latoya:BAAALgAECgUJCAAAAA==.',
Li='Lilbeemo:BAAALgAECgUJCgAAAA==.Lilyana:BAAALgAECgQJBQAAAA==.Litdk:BAAALgADCgUJBQAAAA==.Litharidk:BAABLgAECn8YAAIBAAYJBSDzPgCSAQZoDAAABQBQAGkMAAAGAFkAawwAAAUATQBqDAAAAwBdAGwMAAACAEoA6gwAAAMAVwABAAYJBSDzPgCSAQZoDAAABQBQAGkMAAAGAFkAawwAAAUATQBqDAAAAwBdAGwMAAACAEoA6gwAAAMAVwAAAA==.',
Lo='Loudog:BAAALgAECgYJBwAAAA==.Loxyblue:BAAALgAECgMJAwAAAA==.',
Lu='Luckyxpain:BAABLgAECn8vAAMHAAcJGhnQMwC/AQdoDAAACgBRAGkMAAAHAD0AawwAAAkARQBqDAAABwBcAGwMAAAIACwAbQwAAAIANQDqDAAABABLAAcABwkaGdAzAL8BB2gMAAAHAFEAaQwAAAYAPQBrDAAABwBFAGoMAAAFAFwAbAwAAAQALABtDAAAAgA1AOoMAAACAEsAEQAGCZgITh4AsgAGaAwAAAMAEQBpDAAAAQAcAGsMAAACABEAagwAAAIAKQBsDAAABAAbAOoMAAACABIAAAA=.',
Ma='Madoff:BAAALgAECgQJCAAAAA==.Makok:BAABLgAECn8WAAMSAAgJuhTCBgCeAQhoDAAABABJAGkMAAADADgAawwAAAMAJgBqDAAAAwAmAGwMAAACAB0AbQwAAAEAKgDqDAAABQA7AG4MAAABAEUAEgAICboUwgYAngEIaAwAAAQASQBpDAAAAwA4AGsMAAADACYAagwAAAMAJgBsDAAAAgAdAG0MAAABACoA6gwAAAQAOwBuDAAAAQBFABMAAQnsCfBxADMAAeoMAAABABkAAAA=.',
Me='Melancholic:BAABLgAECn8eAAMUAAcJiSDSDAAsAgdoDAAABgBWAGkMAAAGAFIAawwAAAUARwBqDAAABAAwAGwMAAADAFYAbQwAAAEASwDqDAAABQBhABQABwmJINIMACwCB2gMAAAFAFYAaQwAAAYAUgBrDAAABQBHAGoMAAAEADAAbAwAAAMAVgBtDAAAAQBLAOoMAAAFAGEAFQABCcUEp0cALQABaAwAAAEADAAAAA==.Mellisa:BAABLgAECn8aAAMBAAkJDBHMYgAvAQloDAAABgBEAGkMAAADADUAawwAAAQANABqDAAAAgAHAGwMAAACABgAbQwAAAEAEQDqDAAABgBNAG4MAAABABIAbwwAAAEAJAABAAgJtQ3MYgAvAQhoDAAABQBEAGkMAAACAAoAawwAAAMAGwBqDAAAAgAHAGwMAAACABgAbQwAAAEAEQDqDAAABgBNAG4MAAABABIAEAAECWYSmxwA8wAEaAwAAAEALgBpDAAAAQA1AGsMAAABADQAbwwAAAEAJAAAAA==.Memory:BAAALgAECgEJAQAAAA==.',
Mi='Milkingman:BAAALgAECgEJAQAAAA==.',
Mo='Mooshmoo:BAAALgAECgEJAQAAAA==.',
Mu='Murog:BAAALgAECggJDgAAAA==.',
Na='Nazarite:BAAALgAECgQJBAAAAA==.',
Ni='Nightdisco:BAAALgAECgMJAwAAAA==.',
No='Noctyra:BAAALgAECgQJCAAAAA==.Nomaana:BAAALgAECgMJAwAAAA==.Norael:BAAALgADCgIJAgAAAA==.',
Og='Ogthunder:BAAALgAECgEJAQAAAA==.',
Op='Ophellia:BAAALgAECgEJAQAAAA==.',
Pu='Pureformance:BAAALgADCgcJBwABLgAFFAYJFgAMAAIkAA==.Purrformance:BAACLgAFFH8WAAIMAAYJAiQ1AgBhAgZoDAAABQBgAGkMAAAFAGEAawwAAAMAXABqDAAAAwBNAGwMAAABAFoA6gwAAAUAYQAMAAYJAiQ1AgBhAgZoDAAABQBgAGkMAAAFAGEAawwAAAMAXABqDAAAAwBNAGwMAAABAFoA6gwAAAUAYQAuAAQKfyIAAgwACQmiJQ0BAKcDAAwACQmiJQ0BAKcDAAAA.',
Py='Pyrophobiac:BAACLgAFFH8SAAMCAAYJXRiSEgBSAQZoDAAABABLAGkMAAADABgAawwAAAMALQBqDAAAAQADAGwMAAACAFgA6gwAAAUATwACAAYJXRiSEgBSAQZoDAAABABLAGkMAAACABgAawwAAAEALQBqDAAAAQADAGwMAAACAFgA6gwAAAUATwAGAAIJWAJGDwB/AAJpDAAAAQAHAGsMAAACAAQALgAECn8jAAMCAAkJ2iOAAwCHAwACAAkJmCOAAwCHAwAGAAcJoR1HBwBUAgAAAA==.',
Ra='Ra:BAAALgAECgcJEgAAAA==.Radagast:BAABLgAECn8gAAMWAAgJABORMACFAQhoDAAABQBGAGkMAAAFADYAawwAAAUAPgBqDAAABAAjAGwMAAAEACkAbQwAAAMAFQDqDAAABQAtAG4MAAABAC0AFgAICecQkTAAhQEIaAwAAAQARgBpDAAABQA2AGsMAAAEACYAagwAAAMAIwBsDAAAAwApAG0MAAACABAA6gwAAAQAIwBuDAAAAQAtABMABgl0D1UbABYBBmgMAAABACoAawwAAAEAPgBqDAAAAQARAGwMAAABABsAbQwAAAEAFQDqDAAAAQAtAAAA.Radditz:BAAALgAECgYJCwAAAA==.Rafiki:BAAALgAECgEJAQAAAA==.Rand:BAAALgADCgcJDgAAAA==.',
Ri='Riv:BAAALgAECgMJAwAAAA==.',
Ro='Ronni:BAAALgAECgEJAQAAAA==.Roxyfox:BAAALgAECgQJBQAAAA==.',
Sa='Salea:BAAALgAECgIJAgAAAA==.',
Sc='Scale:BAAALgAECgMJAwAAAA==.',
Se='Serik:BAAALgADCgEJAQAAAA==.',
Sh='Shakaboom:BAAALgAFFAEJAQAAAA==.Sheffurs:BAABLgAECn8eAAIXAAgJwAJ1HwCGAAhoDAAABAADAGkMAAAFAAQAawwAAAQABABqDAAABAAGAGwMAAAEAAcAbQwAAAIADQDqDAAABQANAG4MAAACAAIAFwAICcACdR8AhgAIaAwAAAQAAwBpDAAABQAEAGsMAAAEAAQAagwAAAQABgBsDAAABAAHAG0MAAACAA0A6gwAAAUADQBuDAAAAgACAAAA.Shepardl:BAACLgAFFH8aAAILAAYJySSVAQBSAgZoDAAABgBdAGkMAAAGAGEAawwAAAQAZABqDAAAAwBLAGwMAAACAGIA6gwAAAUAYwALAAYJySSVAQBSAgZoDAAABgBdAGkMAAAGAGEAawwAAAQAZABqDAAAAwBLAGwMAAACAGIA6gwAAAUAYwAuAAQKfyEAAgsACAnkJhoBAIEDAAsACAnkJhoBAIEDAAAA.Shárkbait:BAAALgADCgcJDAABLgAFFAMJBwAQAB4LAA==.',
Sk='Skadoosher:BAAALgAECgUJBQAAAA==.Skyratt:BAAALgAECgEJAgAAAA==.',
Sm='Smackemz:BAAALgAECgYJCQAAAA==.Smacmywand:BAAALgAECgIJBgAAAA==.',
So='Sollasi:BAAALgADCgMJBgAAAA==.Sortie:BAABLgAECn8eAAMLAAgJZQnNJgBiAQhoDAAABAAHAGkMAAAFAAwAawwAAAQAFwBqDAAABAAPAGwMAAAEACQAbQwAAAIAGQDqDAAABQA0AG4MAAACABMACwAICWUJzSYAYgEIaAwAAAIABwBpDAAAAgAMAGsMAAACABcAagwAAAIADwBsDAAAAwAkAG0MAAACABkA6gwAAAIANABuDAAAAQATAAcABwlLBi2UANoAB2gMAAACAAgAaQwAAAMAIwBrDAAAAgAQAGoMAAACABUAbAwAAAEABgDqDAAAAwAPAG4MAAABAA4AAAA=.',
Sp='Spoons:BAAALgAECgQJBAAAAA==.Spyromu:BAAALgAECgQJBgAAAA==.',
St='Stealman:BAAALgADCgcJBwAAAA==.Steeleman:BAAALgADCgQJAgAAAA==.',
Su='Succinic:BAAALgAECggJEAAAAA==.',
Sw='Swiss:BAABLgAECn8bAAILAAgJrw1ONACsAQhoDAAABAA3AGkMAAAEACIAawwAAAQAKwBqDAAAAwAlAGwMAAADABoAbQwAAAMAEwDqDAAAAwA5AG4MAAADAAcACwAICa8NTjQArAEIaAwAAAQANwBpDAAABAAiAGsMAAAEACsAagwAAAMAJQBsDAAAAwAaAG0MAAADABMA6gwAAAMAOQBuDAAAAwAHAAAA.',
Sy='Sylphvaria:BAAALgADCgUJBQAAAA==.Syren:BAAALgADCgcJBgAAAA==.',
Te='Tegridy:BAAALgAECgEJBAAAAA==.Teko:BAAALgADCgYJCwAAAA==.',
Th='Thegoose:BAAALgAECgIJAgAAAA==.Themans:BAAALgAECgYJDgAAAA==.Thunderrod:BAABLgAECn8gAAINAAgJUBUcOAB9AQhoDAAABgBFAGkMAAAFAEwAawwAAAYARQBqDAAABQBRAGwMAAAEAEcAbQwAAAEAEADqDAAABAAwAG4MAAABAB0ADQAICVAVHDgAfQEIaAwAAAYARQBpDAAABQBMAGsMAAAGAEUAagwAAAUAUQBsDAAABABHAG0MAAABABAA6gwAAAQAMABuDAAAAQAdAAAA.',
Ti='Tim:BAAALgADCgYJDQAAAA==.',
To='To:BAAALgAECgIJAgAAAA==.Tovisar:BAAALgAECgMJCQAAAA==.',
Tr='Traessa:BAAALgADCgYJBgAAAA==.',
Tu='Turkturkletn:BAAALgADCgcJEQAAAA==.',
Tw='Twogg:BAAALgAECgYJCQAAAA==.',
Ug='Ugin:BAAALgADCgYJBgAAAA==.Uglykasanova:BAAALgAECgYJEQAAAA==.',
Ul='Ulfrir:BAAALgAECgYJBwAAAA==.',
Va='Vastian:BAAALgAECgUJCQAAAA==.',
Vi='Violet:BAAALgAECgMJBQAAAA==.Vitre:BAAALgAECgUJBwAAAA==.',
Wa='Wanshi:BAAALgAECgcJBgAAAA==.',
We='Wexew:BAABLgAECn8UAAMYAAYJmhkBDgA4AQZoDAAAAwA3AGkMAAAEADYAawwAAAQARwBqDAAAAgBYAGwMAAABAFMA6gwAAAYAPgAYAAYJxxcBDgA4AQZoDAAAAQAhAGkMAAADADYAawwAAAIARwBqDAAAAQBYAGwMAAABAFMA6gwAAAMAPQAFAAUJChW6SgAdAQVoDAAAAgA3AGkMAAABADAAawwAAAIAMABqDAAAAQAuAOoMAAADAD4AAAA=.Wexwex:BAAALgAECgUJDwABLgAECgYJFAAYAJoZAA==.Wexxew:BAAALgAECgEJAQAAAA==.',
Wi='Wishing:BAAALgAECgYJDQAAAA==.',
Wu='Wundertot:BAAALgAECgYJBgABLgAECggJKQAOACkgAA==.Wunderwazard:BAABLgAECn8pAAIOAAgJKSCwFQB9AghoDAAABwBXAGkMAAAGAFYAawwAAAYAUwBqDAAABQBJAGwMAAAFAEMAbQwAAAMARADqDAAABgBdAG4MAAADAFkADgAICSkgsBUAfQIIaAwAAAcAVwBpDAAABgBWAGsMAAAGAFMAagwAAAUASQBsDAAABQBDAG0MAAADAEQA6gwAAAYAXQBuDAAAAwBZAAAA.',
Xe='Xevikan:BAABLgAECn8VAAIBAAcJ2hNebgAWAQdoDAAABQBHAGkMAAAEADYAawwAAAQASwBqDAAAAQAVAGwMAAABACkAbQwAAAEACgDqDAAABQAzAAEABwnaE15uABYBB2gMAAAFAEcAaQwAAAQANgBrDAAABABLAGoMAAABABUAbAwAAAEAKQBtDAAAAQAKAOoMAAAFADMAAAA=.',
Ya='Yadead:BAAALgAECgQJBQAAAA==.',
Za='Zaylen:BAAALgAECgYJEwABLgAECgkJOgAZALMjAA==.',
Ze='Zendjin:BAAALgADCgYJDQAAAA==.',
Zi='Zistormstout:BAABLgAECn8eAAIFAAcJvw8iJABEAQdoDAAABQAsAGkMAAAFACwAawwAAAUAKQBqDAAABQA2AGwMAAADAEYA6gwAAAYAIgBuDAAAAQAGAAUABwm/DyIkAEQBB2gMAAAFACwAaQwAAAUALABrDAAABQApAGoMAAAFADYAbAwAAAMARgDqDAAABgAiAG4MAAABAAYAAAA=.',
Zu='Zuhgonemad:BAAALgAECgIJAwAAAA==.',
['Äl']='Älektra:BAABLgAECn8ZAAIWAAcJUQT4cwDCAAdoDAAABQAIAGkMAAAFAAwAawwAAAUADQBqDAAAAwANAGwMAAACAAkAbQwAAAEADADqDAAABAAJABYABwlRBPhzAMIAB2gMAAAFAAgAaQwAAAUADABrDAAABQANAGoMAAADAA0AbAwAAAIACQBtDAAAAQAMAOoMAAAEAAkAAAA=.',
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
