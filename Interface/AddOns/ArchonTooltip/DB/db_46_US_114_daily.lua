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

local lookup = {'DeathKnight-Unholy','Warlock-Demonology','Priest-Holy','Shaman-Elemental','Shaman-Restoration','Warlock-Destruction','Paladin-Retribution','Priest-Shadow','Unknown-Unknown','Hunter-Survival','Paladin-Holy','Druid-Restoration','Hunter-BeastMastery','Mage-Frost','Mage-Arcane','DeathKnight-Blood','Paladin-Protection','DemonHunter-Vengeance','DemonHunter-Havoc','Warrior-Fury','Warrior-Arms','DemonHunter-Devourer','Druid-Guardian','Shaman-Enhancement','DeathKnight-Frost',}
local provider = {region='US',realm="Gul'dan",name='US',type='daily',zone=46,date='2026-05-20',data={Ae='Aeri:BAAALgAECgYJDAAAAA==.',
Al='Alastormoody:BAAALgADCgcJDAAAAA==.Alelover:BAAALgADCgUJBQAAAA==.Allaria:BAAALgAECgMJCQAAAA==.Almadíon:BAAALgADCgcJCAAAAA==.',
Am='Amosian:BAAALgADCgIJAgAAAA==.',
An='Ana:BAAALgADCgMJAwAAAA==.',
Ao='Aoemomma:BAAALgADCgcJBwAAAA==.',
Ar='Arin:BAAALgAECgIJAwABLgAFFAMJCgABAEEmAA==.',
As='Asuya:BAAALgADCgIJAwAAAA==.',
Az='Azög:BAAALgADCgUJBQAAAA==.',
Ba='Babysocks:BAAALgAECgYJBgAAAA==.',
Bc='Bc:BAABLgAECn8bAAICAAgJ+CYxAwCNAwhoDAAAAwBjAGkMAAAEAGMAawwAAAQAYwBqDAAABABjAGwMAAAEAGMAbQwAAAMAYwDqDAAAAgBjAG4MAAADAGMAAgAICfgmMQMAjQMIaAwAAAMAYwBpDAAABABjAGsMAAAEAGMAagwAAAQAYwBsDAAABABjAG0MAAADAGMA6gwAAAIAYwBuDAAAAwBjAAAA.',
Be='Beep:BAABLgAECn8lAAICAAcJRh+JOgAiAgdoDAAABwBVAGkMAAAGAFMAawwAAAYAWABqDAAABgBdAGwMAAAFAE8AbQwAAAEALwDqDAAABgBgAAIABwlGH4k6ACICB2gMAAAHAFUAaQwAAAYAUwBrDAAABgBYAGoMAAAGAF0AbAwAAAUATwBtDAAAAQAvAOoMAAAGAGAAAAA=.',
Bl='Blackthunder:BAAALgAECggJDAAAAA==.',
Bo='Bobert:BAAALgADCgcJBgAAAA==.Bofadz:BAAALgADCgYJBgAAAA==.Boozecruise:BAAALgADCgIJAgAAAA==.Bowyn:BAABLgAECn8XAAIDAAYJHhNoOgBSAQZoDAAABAA3AGkMAAAFACYAawwAAAUAJgBqDAAAAwAYAGwMAAADADkA6gwAAAMAUAADAAYJHhNoOgBSAQZoDAAABAA3AGkMAAAFACYAawwAAAUAJgBqDAAAAwAYAGwMAAADADkA6gwAAAMAUAAAAA==.',
Bu='Budleaf:BAAALgAECgUJDAAAAA==.Bunkley:BAABLgAECn8dAAMEAAcJLQpnQAD1AAdoDAAABgATAGkMAAAFABkAawwAAAYAIgBqDAAABQAjAGwMAAACACgA6gwAAAMAEgBuDAAAAgARAAQABwktCmdAAPUAB2gMAAACABMAaQwAAAIAGQBrDAAAAQAiAGoMAAABACMAbAwAAAIAKADqDAAAAgASAG4MAAABABEABQAGCVUK/GQA5AAGaAwAAAQAOQBpDAAAAwASAGsMAAAFACMAagwAAAQAIwDqDAAAAQAIAG4MAAABAAQAAAA=.Butterknives:BAAALgAECgEJAQAAAA==.',
By='Byege:BAACLgAFFH8OAAICAAUJBxjOMQA2AQVoDAAAAwBWAGkMAAADACUAawwAAAEAJABqDAAAAQAXAOoMAAAGAFUAAgAFCQcYzjEANgEFaAwAAAMAVgBpDAAAAwAlAGsMAAABACQAagwAAAEAFwDqDAAABgBVAC4ABAp/JwADAgAJCcYfPhAAqgIAAgAJCaEfPhAAqgIABgAFCc4XshsAcAEAAAA=.',
Ca='Cantfireme:BAAALgADCgcJBwABLgAECggJNAAHAFsdAA==.Cardhunter:BAAALgADCgYJBgAAAA==.Cash:BAAALgAECgcJDAAAAA==.',
Ch='Champilon:BAAALgADCgYJBgAAAA==.Chaoticus:BAAALgAECgYJDQABLgAECggJIgAIAJgOAA==.Charizards:BAAALgADCgYJDQAAAA==.Charmahnder:BAAALgAECgIJAgAAAA==.',
Cr='Crunbard:BAAALgAECgcJDQAAAA==.',
Cu='Culdan:BAABLgAECn8XAAMGAAYJfwfXGwCeAAZoDAAABQAIAGkMAAAFABoAawwAAAYAFQBqDAAAAgASAGwMAAACABEA6gwAAAMAFgAGAAUJhQjXGwCeAAVpDAAAAQAaAGsMAAAEABUAagwAAAIAEgBsDAAAAgARAOoMAAACABYAAgAECR8EX8cAlAAEaAwAAAUACABpDAAABAAOAGsMAAACAAoA6gwAAAEACAAAAA==.',
Da='Dalirus:BAAALgAECgEJAQABLgAECggJNAAHAFsdAA==.Danahe:BAAALgAECgEJAQAAAA==.Darci:BAAALgAECgcJDgABLgAECgQJCAAJAAAAAA==.Darksuaza:BAAALgAECgcJDAAAAA==.Darthwizard:BAAALgADCgIJAgAAAA==.Dasbunk:BAAALgAECgEJAQAAAA==.Dayman:BAAALgADCgYJBgAAAA==.',
De='Deadblue:BAABLgAECn8uAAIGAAkJwBclAwA6AgloDAAABQBMAGkMAAAHAEgAawwAAAYANQBqDAAABgArAGwMAAAGADkAbQwAAAQAJgDqDAAABwBMAG4MAAAEAFYAbwwAAAEAGQAGAAkJwBclAwA6AgloDAAABQBMAGkMAAAHAEgAawwAAAYANQBqDAAABgArAGwMAAAGADkAbQwAAAQAJgDqDAAABwBMAG4MAAAEAFYAbwwAAAEAGQAAAA==.Deekay:BAAALgADCgcJFAAAAA==.',
Di='Diogee:BAAALgAECgMJBgAAAA==.Discipline:BAAALgAECgYJDAABLgAFFAYJIgAKAIoXAA==.Divinate:BAAALgAECgIJAgAAAA==.',
Dk='Dkpitador:BAAALgADCgEJAQAAAA==.',
Do='Doomhead:BAABLgAECn8YAAIBAAgJ2AiscQBVAQhoDAAABAASAGkMAAAEABgAawwAAAQAEABqDAAAAwATAGwMAAACABkAbQwAAAEAHwDqDAAABQAaAG4MAAABABAAAQAICdgIrHEAVQEIaAwAAAQAEgBpDAAABAAYAGsMAAAEABAAagwAAAMAEwBsDAAAAgAZAG0MAAABAB8A6gwAAAUAGgBuDAAAAQAQAAAA.',
Dr='Drakki:BAAALgADCgUJBQAAAA==.Dreadfaith:BAAALgAECgYJBgAAAA==.',
Du='Durzii:BAACLgAFFH8FAAILAAIJuiINJgC/AAJoDAAAAwBVAGkMAAACAFwACwACCboiDSYAvwACaAwAAAMAVQBpDAAAAgBcAC4ABAp/GQADCwAJCaogoRIAfQIACwAICd4hoRIAfQIABwABCe0ZIiIBUgAAAAA=.',
Ea='Eatmybeef:BAAALgADCgYJCgAAAA==.',
Ex='Extinctionus:BAAALgAECgQJBQAAAA==.',
Fe='Fernn:BAAALgADCgQJBAAAAA==.',
Fi='Fia:BAABLgAECn8wAAIBAAkJwQ8VQADaAQloDAAABwAzAGkMAAAHADMAawwAAAYANQBqDAAABgAsAGwMAAAGACkAbQwAAAQAKwDqDAAABgAdAG4MAAAEACAAbwwAAAIAEgABAAkJwQ8VQADaAQloDAAABwAzAGkMAAAHADMAawwAAAYANQBqDAAABgAsAGwMAAAGACkAbQwAAAQAKwDqDAAABgAdAG4MAAAEACAAbwwAAAIAEgAAAA==.',
Fu='Furor:BAAALgAECgQJBAAAAA==.',
Ge='Genaro:BAAALgAECgIJBwAAAA==.',
Gi='Gibraltar:BAAALgADCgUJBQAAAA==.',
Go='Gokujang:BAAALgAECgUJCgABLgAECggJEgAJAAAAAA==.Goremont:BAAALgADCgQJBQAAAA==.Gorlok:BAAALgAECgUJBQAAAA==.',
Gr='Greendot:BAACLgAFFH8GAAIMAAMJ8xRIKwDbAANoDAAAAgA/AGkMAAADAC8A6gwAAAEAMQAMAAMJ8xRIKwDbAANoDAAAAgA/AGkMAAADAC8A6gwAAAEAMQAuAAQKfykAAgwACAlfI2QGAC8DAAwACAlfI2QGAC8DAAAA.',
Gu='Gulvid:BAACLgAFFH8GAAICAAIJlx0bagCwAAJoDAAAAgBYAOoMAAAEAD8AAgACCZcdG2oAsAACaAwAAAIAWADqDAAABAA/AC4ABAp/GAADAgAHCWQheEgAoAEAAgAHCWQheEgAoAEABgABCQAAqlwAWAAAAS4ABRQHCRUAAgBlEgA=.',
Ha='Haluak:BAABLgAECn8oAAIEAAgJ8RfJGwDJAQhoDAAABwBBAGkMAAAIAEsAawwAAAcASgBqDAAABQBOAGwMAAADADsAbQwAAAIAKADqDAAABgBFAG4MAAACACwABAAICfEXyRsAyQEIaAwAAAcAQQBpDAAACABLAGsMAAAHAEoAagwAAAUATgBsDAAAAwA7AG0MAAACACgA6gwAAAYARQBuDAAAAgAsAAAA.',
He='Healthyself:BAAALgAECgYJCwAAAA==.',
Ho='Houndtamer:BAABLgAECn8rAAINAAgJ3hNkPgCwAQhoDAAABwBFAGkMAAAHACkAawwAAAcALgBqDAAABwA+AGwMAAAEAC0AbQwAAAEAGgDqDAAABwA2AG4MAAADAEgADQAICd4TZD4AsAEIaAwAAAcARQBpDAAABwApAGsMAAAHAC4AagwAAAcAPgBsDAAABAAtAG0MAAABABoA6gwAAAcANgBuDAAAAwBIAAAA.',
Hp='Hpyflowers:BAAALgADCgQJBAAAAA==.',
Hr='Hruoth:BAAALgAECgYJBgAAAA==.',
Ic='Iceshooting:BAAALgAECgQJBwAAAA==.',
Is='Ishtar:BAABLgAECn8ZAAMOAAYJ9BzVhADIAQZoDAAABQBFAGkMAAAFAFEAawwAAAQATQBqDAAABABMAGwMAAAEAFMA6gwAAAMAOgAOAAYJCRnVhADIAQZoDAAAAwAqAGkMAAAFAFEAawwAAAMATQBqDAAABABMAGwMAAAEAFMA6gwAAAIAIwAPAAMJzRkuDwDQAANoDAAAAgBFAGsMAAABAEYA6gwAAAEAOgAAAA==.',
It='Itshela:BAACLgAFFH8ZAAMBAAYJjBhVGgCdAQZoDAAABgBRAGkMAAAEAFUAawwAAAMAJgBqDAAABQA2AGwMAAACACAA6gwAAAUATAABAAUJjBhVGgCdAQVoDAAABgBRAGkMAAAEAFUAawwAAAMAJgBsDAAAAgAgAOoMAAAFAEwAEAABCQAACDsAAAABagwAAAUANgAuAAQKfxsAAgEABwk0I+tNAAkCAAEABwk0I+tNAAkCAAAA.',
Ja='Jayrad:BAAALgAECgUJDwAAAA==.',
Je='Jehnovah:BAAALgADCgMJAwAAAA==.Jellybeanz:BAAALgADCggJDQAAAA==.',
Jo='Jordybear:BAAALgAECgQJBAAAAA==.Jorkoh:BAAALgAECgMJBgAAAA==.',
Ju='Juicer:BAAALgADCgMJBgAAAA==.',
Ka='Kaiige:BAAALgAECgQJBAAAAA==.Kairos:BAAALgAECgYJCgAAAA==.Kanê:BAAALgAECgUJCQAAAA==.',
Ke='Kehlayr:BAAALgADCgMJAwAAAA==.Keiiry:BAAALgADCgMJAwAAAA==.Kenshinth:BAAALgAECgYJDwAAAA==.Kethrym:BAAALgAECgIJAgAAAA==.',
Kh='Khanor:BAAALgAECgYJEQAAAA==.',
Ki='Kiltro:BAAALgAECgQJBgAAAA==.Kimchichi:BAAALgAECgcJEgAAAA==.Kintaro:BAAALgADCgYJDAAAAA==.',
Ko='Kogorko:BAAALgAECgIJAgAAAA==.',
Kr='Kry:BAAALgAECgIJAgAAAA==.',
['Kë']='Këarra:BAAALgAECgQJBwAAAA==.',
La='Labotimizer:BAAALgAECggJDwAAAA==.Lapriestess:BAAALgAECgYJCwAAAA==.Latoya:BAAALgAECgYJDgAAAA==.',
Li='Lilbeemo:BAAALgAECgUJCgAAAA==.Lilyana:BAAALgAECgYJCwAAAA==.Liongs:BAAALgAECgUJBQABLgAECgYJDwAJAAAAAA==.Litdk:BAAALgADCgUJBQAAAA==.Litharidk:BAABLgAECn8cAAIBAAcJUyDSPADlAQdoDAAABgBZAGkMAAAHAFkAawwAAAUATQBqDAAAAwBdAGwMAAACAEoAbQwAAAEATgDqDAAABABXAAEABwlTINI8AOUBB2gMAAAGAFkAaQwAAAcAWQBrDAAABQBNAGoMAAADAF0AbAwAAAIASgBtDAAAAQBOAOoMAAAEAFcAAAA=.',
Lo='Loudog:BAAALgAECgYJBwAAAA==.Loxyblue:BAAALgAECgMJAwAAAA==.',
Lu='Luckyxpain:BAABLgAECn80AAMHAAgJWx0mKAA3AghoDAAACgBRAGkMAAAHAD0AawwAAAkARQBqDAAABwBcAGwMAAAJAD8AbQwAAAMAXgDqDAAABQBLAG4MAAACAE8ABwAICVsdJigANwIIaAwAAAcAUQBpDAAABgA9AGsMAAAHAEUAagwAAAUAXABsDAAABQA/AG0MAAADAF4A6gwAAAMASwBuDAAAAgBPABEABgmYCFcnAKIABmgMAAADABEAaQwAAAEAHABrDAAAAgARAGoMAAACACkAbAwAAAQAGwDqDAAAAgASAAAA.',
Ly='Lykos:BAAALgAECgEJAQAAAA==.',
Ma='Madoff:BAAALgAECgQJCAAAAA==.Makok:BAABLgAECn8YAAMSAAgJuhTMCQCPAQhoDAAABABJAGkMAAADADgAawwAAAMAJgBqDAAAAwAmAGwMAAACAB0AbQwAAAEAKgDqDAAABgA7AG4MAAACAEUAEgAICboUzAkAjwEIaAwAAAQASQBpDAAAAwA4AGsMAAADACYAagwAAAMAJgBsDAAAAgAdAG0MAAABACoA6gwAAAUAOwBuDAAAAgBFABMAAQnsCfJxADMAAeoMAAABABkAAAA=.',
Me='Melancholic:BAABLgAECn8hAAMUAAgJUyCzEABEAghoDAAABgBWAGkMAAAGAFIAawwAAAUARwBqDAAABAAwAGwMAAADAFYAbQwAAAEASwDqDAAABgBhAG4MAAACAE8AFAAICVMgsxAARAIIaAwAAAUAVgBpDAAABgBSAGsMAAAFAEcAagwAAAQAMABsDAAAAwBWAG0MAAABAEsA6gwAAAYAYQBuDAAAAgBPABUAAQnFBGdgACkAAWgMAAABAAwAAAA=.Mellisa:BAABLgAECn8fAAMBAAkJbhFgWQCQAQloDAAABwBIAGkMAAAEADUAawwAAAUANwBqDAAAAwBEAGwMAAACABgAbQwAAAEAEQDqDAAABwBNAG4MAAABABIAbwwAAAEAJAABAAgJ1Q9gWQCQAQhoDAAABgBIAGkMAAADABAAawwAAAQANwBqDAAAAwBEAGwMAAACABgAbQwAAAEAEQDqDAAABgBNAG4MAAABABIAEAAFCXUT1CAAEAEFaAwAAAEALgBpDAAAAQA1AGsMAAABADQA6gwAAAEAPABvDAAAAQAkAAAA.Memory:BAAALgAECgEJAgAAAA==.',
Mi='Milkingman:BAAALgAECgEJAQAAAA==.',
Mo='Mooshmoo:BAAALgAECgEJAQAAAA==.',
Mu='Murog:BAABLgAECn8VAAIFAAgJYwwnQQBoAQhoDAAAAgAvAGkMAAACADEAawwAAAIAEQBqDAAAAwArAGwMAAAEADIAbQwAAAEABQDqDAAABgAgAG4MAAABAAcABQAICWMMJ0EAaAEIaAwAAAIALwBpDAAAAgAxAGsMAAACABEAagwAAAMAKwBsDAAABAAyAG0MAAABAAUA6gwAAAYAIABuDAAAAQAHAAAA.',
Na='Nazarite:BAAALgAECgQJCgAAAA==.',
Ni='Nightdisco:BAAALgAECgMJAwAAAA==.',
No='Noctyra:BAAALgAECgQJCAAAAA==.Nomaana:BAAALgAECgMJAwAAAA==.Norael:BAAALgADCgIJAgAAAA==.',
Og='Ogthunder:BAAALgAECgEJAQAAAA==.',
Op='Ophellia:BAAALgAECgEJAQAAAA==.',
Pu='Pureformance:BAAALgADCgcJBwABLgAFFAcJHgAMAIIjAA==.Purrformance:BAACLgAFFH8eAAIMAAcJgiOuAQDFAgdoDAAABgBgAGkMAAAGAGEAawwAAAQAXABqDAAABABNAGwMAAACAF0AbQwAAAEAUADqDAAABwBhAAwABwmCI64BAMUCB2gMAAAGAGAAaQwAAAYAYQBrDAAABABcAGoMAAAEAE0AbAwAAAIAXQBtDAAAAQBQAOoMAAAHAGEALgAECn8iAAIMAAkJoiUMAQCnAwAMAAkJoiUMAQCnAwAAAA==.',
Py='Pyrophobiac:BAACLgAFFH8VAAMCAAcJ5BWVEgBSAQdoDAAABABLAGkMAAADABgAawwAAAMALQBqDAAAAQADAGwMAAADAFgAbQwAAAEAGADqDAAABgBPAAIABwnkFZUSAFIBB2gMAAAEAEsAaQwAAAIAGABrDAAAAQAtAGoMAAABAAMAbAwAAAMAWABtDAAAAQAYAOoMAAAGAE8ABgACCVgCSg8AfwACaQwAAAEABwBrDAAAAgAEAC4ABAp/IwADAgAJCdojgAMAhwMAAgAJCZgjgAMAhwMABgAHCaEdRwcAVAIAAAA=.',
Ra='Ra:BAABLgAECn8fAAITAAgJkR0JCgBNAghoDAAABABPAGkMAAAFAFwAawwAAAUAXABqDAAABQBQAGwMAAAEAFAAbQwAAAEALwDqDAAABABHAG4MAAADAEIAEwAICZEdCQoATQIIaAwAAAQATwBpDAAABQBcAGsMAAAFAFwAagwAAAUAUABsDAAABABQAG0MAAABAC8A6gwAAAQARwBuDAAAAwBCAAAA.Radagast:BAACLgAFFH8IAAIWAAMJwgX8TwC8AANoDAAAAwAPAGkMAAACAA4A6gwAAAMADQAWAAMJwgX8TwC8AANoDAAAAwAPAGkMAAACAA4A6gwAAAMADQAuAAQKfycAAxYACAlsFwkrAPMBABYACAn9FgkrAPMBABMABgl0Dx4lAAsBAAAA.Radditz:BAAALgAECgYJCwAAAA==.Rafiki:BAAALgAECgEJAQAAAA==.Rand:BAAALgADCgcJDgAAAA==.',
Ri='Riv:BAAALgAECgMJAwAAAA==.',
Ro='Ronni:BAAALgAECgIJAgAAAA==.Roxyfox:BAAALgAECgYJCwAAAA==.Royvaz:BAAALgADCgkJCwAAAA==.',
Sa='Salea:BAAALgAECgIJAgAAAA==.Sarryn:BAAALgADCgcJBwAAAA==.',
Sc='Scale:BAAALgAECgMJAwAAAA==.',
Se='Serik:BAAALgADCgEJAQAAAA==.',
Sh='Shakaboom:BAAALgAFFAEJAQAAAA==.Sheffurs:BAABLgAECn8uAAIXAAkJzgIFLQCgAAloDAAABQAEAGkMAAAHAAQAawwAAAYABABqDAAABgAGAGwMAAAGAAkAbQwAAAQADQDqDAAABwANAG4MAAAEAAMAbwwAAAEABAAXAAkJzgIFLQCgAAloDAAABQAEAGkMAAAHAAQAawwAAAYABABqDAAABgAGAGwMAAAGAAkAbQwAAAQADQDqDAAABwANAG4MAAAEAAMAbwwAAAEABAAAAA==.Shepardl:BAACLgAFFH8jAAILAAYJ/SQXAgB5AgZoDAAABwBdAGkMAAAHAGEAawwAAAUAZABqDAAABQBNAGwMAAAEAGMA6gwAAAcAYwALAAYJ/SQXAgB5AgZoDAAABwBdAGkMAAAHAGEAawwAAAUAZABqDAAABQBNAGwMAAAEAGMA6gwAAAcAYwAuAAQKfyEAAgsACAnkJhoBAIEDAAsACAnkJhoBAIEDAAAA.Shárkbait:BAAALgADCgcJDAAAAA==.',
Sk='Skadoosher:BAAALgAECgUJBQAAAA==.Skyratt:BAAALgAECgEJAgAAAA==.',
Sm='Smackemz:BAAALgAECgYJCQAAAA==.Smacmywand:BAAALgAECgIJBgAAAA==.',
So='Sollasi:BAAALgADCgMJBgAAAA==.Sortie:BAABLgAECn8uAAMLAAkJSgkCLAB/AQloDAAABQAHAGkMAAAHAAwAawwAAAYAFwBqDAAABgAPAGwMAAAGACQAbQwAAAQAGQDqDAAABwA0AG4MAAAEABMAbwwAAAEAFQALAAkJSgkCLAB/AQloDAAAAgAHAGkMAAADAAwAawwAAAMAFwBqDAAAAwAPAGwMAAAEACQAbQwAAAMAGQDqDAAAAgA0AG4MAAABABMAbwwAAAEAFQAHAAgJCgoHfABMAQhoDAAAAwAvAGkMAAAEACMAawwAAAMAFABqDAAAAwAkAGwMAAACAA4AbQwAAAEAEwDqDAAABQAaAG4MAAADABAAAAA=.',
Sp='Spoons:BAAALgAECgQJBAAAAA==.Spyromu:BAAALgAECgQJBgAAAA==.',
St='Stealman:BAAALgADCgcJBwAAAA==.Steeleman:BAAALgADCgQJAgAAAA==.',
Su='Succinic:BAAALgAECggJEAAAAA==.',
Sw='Swiss:BAABLgAECn8bAAILAAgJrw1ONACsAQhoDAAABAA3AGkMAAAEACIAawwAAAQAKwBqDAAAAwAlAGwMAAADABoAbQwAAAMAEwDqDAAAAwA5AG4MAAADAAcACwAICa8NTjQArAEIaAwAAAQANwBpDAAABAAiAGsMAAAEACsAagwAAAMAJQBsDAAAAwAaAG0MAAADABMA6gwAAAMAOQBuDAAAAwAHAAAA.',
Sy='Sylphvaria:BAAALgADCgUJBQAAAA==.Syren:BAAALgADCgcJBgAAAA==.',
Te='Tegridy:BAAALgAECgQJCAAAAA==.Teko:BAAALgADCgYJCwAAAA==.',
Th='Thegoose:BAAALgAECgIJAgAAAA==.Themans:BAAALgAECgYJDgAAAA==.Thunderrod:BAABLgAECn8lAAINAAgJUBXOPgC0AQhoDAAABwBFAGkMAAAGAEwAawwAAAcARQBqDAAABgBRAGwMAAAFAEcAbQwAAAEAEADqDAAABAAwAG4MAAABAB0ADQAICVAVzj4AtAEIaAwAAAcARQBpDAAABgBMAGsMAAAHAEUAagwAAAYAUQBsDAAABQBHAG0MAAABABAA6gwAAAQAMABuDAAAAQAdAAAA.',
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
We='Wexew:BAABLgAECn8UAAMYAAYJmhmcFQAOAQZoDAAAAwA3AGkMAAAEADYAawwAAAQARwBqDAAAAgBYAGwMAAABAFMA6gwAAAYAPgAEAAUJChW+SgAdAQVoDAAAAgA3AGkMAAABADAAawwAAAIAMABqDAAAAQAuAOoMAAADAD4AGAAGCccXnBUADgEGaAwAAAEAIQBpDAAAAwA2AGsMAAACAEcAagwAAAEAWABsDAAAAQBTAOoMAAADAD0AAAA=.Wexwex:BAAALgAECgUJDwABLgAECgYJFAAYAJoZAA==.Wexxew:BAAALgAFFAEJAQAAAA==.',
Wi='Wishing:BAAALgAECgYJEgAAAA==.',
Wu='Wundertot:BAAALgAECgYJBgABLgAECggJKgAOACkgAA==.Wunderwazard:BAABLgAECn8qAAIOAAgJKSBzKQBMAghoDAAABwBXAGkMAAAGAFYAawwAAAYAUwBqDAAABQBJAGwMAAAFAEMAbQwAAAMARADqDAAABgBdAG4MAAAEAFkADgAICSkgcykATAIIaAwAAAcAVwBpDAAABgBWAGsMAAAGAFMAagwAAAUASQBsDAAABQBDAG0MAAADAEQA6gwAAAYAXQBuDAAABABZAAAA.',
Xe='Xevikan:BAABLgAECn8bAAMBAAcJDBX8iQAlAQdoDAAABgBHAGkMAAAFADYAawwAAAUASwBqDAAAAgAnAGwMAAACACkAbQwAAAIAHADqDAAABQAzAAEABwkMFfyJACUBB2gMAAAFAEcAaQwAAAUANgBrDAAABQBLAGoMAAACACcAbAwAAAIAKQBtDAAAAgAcAOoMAAAFADMAGQABCR8IQyoAKgABaAwAAAEAFAAAAA==.',
Ya='Yadead:BAAALgAECgYJCwAAAA==.',
Za='Zaylen:BAAALgAECgYJEwAAAA==.',
Ze='Zendjin:BAAALgADCgYJDQAAAA==.',
Zi='Zistormstout:BAABLgAECn8sAAIEAAgJ1xWyHgCxAQhoDAAABwAzAGkMAAAHADEAawwAAAcAQwBqDAAABwBMAGwMAAAEAEYAbQwAAAEAJgDqDAAACAAoAG4MAAADAEoABAAICdcVsh4AsQEIaAwAAAcAMwBpDAAABwAxAGsMAAAHAEMAagwAAAcATABsDAAABABGAG0MAAABACYA6gwAAAgAKABuDAAAAwBKAAAA.',
Zu='Zuhgonemad:BAAALgAECgQJBgAAAA==.',
['Äl']='Älektra:BAABLgAECn8ZAAIWAAcJUQSblQDCAAdoDAAABQAIAGkMAAAFAAwAawwAAAUADQBqDAAAAwANAGwMAAACAAkAbQwAAAEADADqDAAABAAJABYABwlRBJuVAMIAB2gMAAAFAAgAaQwAAAUADABrDAAABQANAGoMAAADAA0AbAwAAAIACQBtDAAAAQAMAOoMAAAEAAkAAAA=.',
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
