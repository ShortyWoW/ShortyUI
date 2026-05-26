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

local lookup = {'DeathKnight-Unholy','Warlock-Affliction','Warlock-Demonology','Priest-Holy','Shaman-Elemental','Shaman-Restoration','Warlock-Destruction','Paladin-Retribution','Rogue-Assassination','Rogue-Subtlety','Priest-Shadow','Unknown-Unknown','Hunter-Survival','Paladin-Holy','DeathKnight-Blood','Priest-Discipline','Druid-Restoration','Hunter-BeastMastery','Mage-Frost','Mage-Arcane','Paladin-Protection','DemonHunter-Vengeance','DemonHunter-Havoc','Warrior-Fury','Warrior-Arms','DemonHunter-Devourer','Druid-Guardian','Monk-Mistweaver','Shaman-Enhancement','DeathKnight-Frost',}
local provider = {region='US',realm="Gul'dan",name='US',type='daily',zone=46,date='2026-05-26',data={Ae='Aeri:BAAALgAECgYJDAAAAA==.',
Al='Alastormoody:BAAALgADCgcJDAAAAA==.Alelover:BAAALgADCgUJBQAAAA==.Allaria:BAAALgAECgQJDQAAAA==.Almadíon:BAAALgADCgcJCAAAAA==.',
Am='Amosian:BAAALgADCgIJAgAAAA==.',
An='Ana:BAAALgADCgMJAwAAAA==.',
Ao='Aoemomma:BAAALgADCgcJBwAAAA==.',
Ar='Arin:BAAALgAECgIJAwABLgAFFAMJCgABAEEmAA==.',
As='Asuya:BAAALgADCgIJAwAAAA==.',
Az='Azög:BAAALgADCgUJBQAAAA==.',
Ba='Babysocks:BAAALgAECgYJBgAAAA==.',
Bc='Bc:BAACLgAFFH8HAAMCAAMJ3RmIBgDYAANsDAAAAQAVAG0MAAABAE0A6gwAAAUAYwACAAIJpSKIBgDYAAJtDAAAAQBNAOoMAAABAGMAAwACCRkXgnQAsQACbAwAAAEAFQDqDAAABABhAC4ABAp/GwACAwAICfgmMQMAjQMAAwAICfgmMQMAjQMAAAA=.',
Be='Beep:BAABLgAECn8lAAIDAAcJRh+JOgAiAgdoDAAABwBVAGkMAAAGAFMAawwAAAYAWABqDAAABgBdAGwMAAAFAE8AbQwAAAEALwDqDAAABgBgAAMABwlGH4k6ACICB2gMAAAHAFUAaQwAAAYAUwBrDAAABgBYAGoMAAAGAF0AbAwAAAUATwBtDAAAAQAvAOoMAAAGAGAAAAA=.',
Bl='Blackthunder:BAAALgAECggJDAAAAA==.',
Bo='Bobert:BAAALgADCgcJBgAAAA==.Bofadz:BAAALgADCgYJBgAAAA==.Boozecruise:BAAALgADCgIJAgAAAA==.Bowyn:BAABLgAECn8XAAIEAAYJHhNoOgBSAQZoDAAABAA3AGkMAAAFACYAawwAAAUAJgBqDAAAAwAYAGwMAAADADkA6gwAAAMAUAAEAAYJHhNoOgBSAQZoDAAABAA3AGkMAAAFACYAawwAAAUAJgBqDAAAAwAYAGwMAAADADkA6gwAAAMAUAAAAA==.',
Bu='Budleaf:BAAALgAECgUJDAAAAA==.Bunkley:BAABLgAECn8gAAMFAAcJYQuZQwD+AAdoDAAABgATAGkMAAAFABkAawwAAAYAIgBqDAAABgA7AGwMAAACACgA6gwAAAQAJABuDAAAAwARAAUABwlhC5lDAP4AB2gMAAACABMAaQwAAAIAGQBrDAAAAQAiAGoMAAACADsAbAwAAAIAKADqDAAAAwAkAG4MAAACABEABgAGCVUKEW4A5AAGaAwAAAQAOQBpDAAAAwASAGsMAAAFACMAagwAAAQAIwDqDAAAAQAIAG4MAAABAAQAAAA=.Butterknives:BAAALgAECgEJAQAAAA==.',
By='Byege:BAACLgAFFH8OAAIDAAUJBxi4PAAwAQVoDAAAAwBWAGkMAAADACUAawwAAAEAJABqDAAAAQAXAOoMAAAGAFUAAwAFCQcYuDwAMAEFaAwAAAMAVgBpDAAAAwAlAGsMAAABACQAagwAAAEAFwDqDAAABgBVAC4ABAp/JwADAwAJCccfLRMAowIAAwAJCaMfLRMAowIABwAFCc4XshsAcAEAAAA=.',
Ca='Cantfireme:BAAALgAECgMJAwABLgAECgkJOAAIAO0ZAA==.Cardhunter:BAAALgADCgYJBgAAAA==.Cash:BAABLgAECn8UAAMJAAgJNBCyCACfAQhoDAAAAwAsAGkMAAADADUAawwAAAMAPABqDAAAAwAmAGwMAAADACcAbQwAAAEAGwDqDAAAAwAkAG4MAAABABwACQAICTQQsggAnwEIaAwAAAIALABpDAAAAgA1AGsMAAACADwAagwAAAIAJgBsDAAAAwAnAG0MAAABABsA6gwAAAIAJABuDAAAAQAcAAoABQl9A9RBAIEABWgMAAABAA4AaQwAAAEAEABrDAAAAQAAAGoMAAABAA8A6gwAAAEABAAAAA==.',
Ch='Champilon:BAAALgADCgYJBgAAAA==.Chaoticus:BAAALgAECgYJDQABLgAECggJIgALAJgOAA==.Charizards:BAAALgADCgYJDQAAAA==.Charmahnder:BAAALgAECgIJAgAAAA==.',
Cr='Crunbard:BAAALgAECgcJDQAAAA==.',
Cu='Culdan:BAABLgAECn8XAAMHAAYJfwc7HgCaAAZoDAAABQAIAGkMAAAFABoAawwAAAYAFQBqDAAAAgASAGwMAAACABEA6gwAAAMAFgAHAAUJhQg7HgCaAAVpDAAAAQAaAGsMAAAEABUAagwAAAIAEgBsDAAAAgARAOoMAAACABYAAwAECR8EztMAlAAEaAwAAAUACABpDAAABAAOAGsMAAACAAoA6gwAAAEACAAAAA==.',
Da='Dalirus:BAAALgAECgQJBQABLgAECgkJOAAIAO0ZAA==.Danahe:BAAALgAECgEJAQAAAA==.Darci:BAAALgAECgcJEQABLgAECgQJCAAMAAAAAA==.Darksuaza:BAAALgAECgcJDAAAAA==.Darthwizard:BAAALgADCgIJAgAAAA==.Dasbunk:BAAALgAECgYJBwAAAA==.Dayman:BAAALgADCgYJBgAAAA==.',
De='Deadblue:BAABLgAECn8vAAIHAAkJmxkvAwBIAgloDAAABQBMAGkMAAAHAEgAawwAAAYANQBqDAAABgArAGwMAAAGADkAbQwAAAQAJgDqDAAABwBMAG4MAAAEAFYAbwwAAAIAPwAHAAkJmxkvAwBIAgloDAAABQBMAGkMAAAHAEgAawwAAAYANQBqDAAABgArAGwMAAAGADkAbQwAAAQAJgDqDAAABwBMAG4MAAAEAFYAbwwAAAIAPwAAAA==.Deekay:BAAALgADCgcJFAAAAA==.',
Di='Diogee:BAAALgAECgMJBgAAAA==.Discipline:BAAALgAECgYJDAABLgAFFAcJIwANAKkVAA==.Divinate:BAAALgAECgIJAgAAAA==.',
Dk='Dkpitador:BAAALgADCgEJAQAAAA==.',
Do='Doomhead:BAABLgAECn8YAAIBAAgJ2AjyfABMAQhoDAAABAASAGkMAAAEABgAawwAAAQAEABqDAAAAwATAGwMAAACABkAbQwAAAEAHwDqDAAABQAaAG4MAAABABAAAQAICdgI8nwATAEIaAwAAAQAEgBpDAAABAAYAGsMAAAEABAAagwAAAMAEwBsDAAAAgAZAG0MAAABAB8A6gwAAAUAGgBuDAAAAQAQAAAA.',
Dr='Drakki:BAAALgADCgUJBQAAAA==.Dreadfaith:BAAALgAECgYJBgAAAA==.',
Du='Durzii:BAACLgAFFH8FAAIOAAIJuiKUKQC7AAJoDAAAAwBVAGkMAAACAFwADgACCboilCkAuwACaAwAAAMAVQBpDAAAAgBcAC4ABAp/GQADDgAJCaogoRIAfQIADgAICd4hoRIAfQIACAABCe0ZyjsBTwAAAS4ABRQDCQMADAAAAAA=.',
Ea='Eatmybeef:BAAALgADCgYJCgAAAA==.',
Ex='Extinctionus:BAAALgAECgQJBQAAAA==.',
Fe='Fernn:BAAALgADCgQJBAAAAA==.',
Fi='Fia:BAABLgAECn84AAMBAAkJHROhSADOAQloDAAACAA5AGkMAAAIADMAawwAAAcAQQBqDAAABwAsAGwMAAAHADkAbQwAAAUAOQDqDAAABwAzAG4MAAAFACAAbwwAAAIAEgABAAkJwQ+hSADOAQloDAAABwAzAGkMAAAHADMAawwAAAYANQBqDAAABgAsAGwMAAAGACkAbQwAAAQAKwDqDAAABgAdAG4MAAAEACAAbwwAAAIAEgAPAAgJyxLAFQCXAQhoDAAAAQA5AGkMAAABACQAawwAAAEAQQBqDAAAAQArAGwMAAABADkAbQwAAAEAOQDqDAAAAQAzAG4MAAABAAsAAAA=.',
Fu='Furor:BAAALgAECgQJBAAAAA==.',
Ge='Genaro:BAAALgAECgIJBwAAAA==.',
Gi='Gibraltar:BAAALgADCgUJBQAAAA==.',
Go='Gokujang:BAAALgAECgUJCgABLgAECggJGQAQADQTAA==.Goremont:BAAALgADCgQJBQAAAA==.Gorlok:BAAALgAECgUJBQAAAA==.',
Gr='Greendot:BAACLgAFFH8HAAIRAAMJ8xTFMADXAANoDAAAAgA/AGkMAAADAC8A6gwAAAIAMQARAAMJ8xTFMADXAANoDAAAAgA/AGkMAAADAC8A6gwAAAIAMQAuAAQKfysAAhEACAkGJFAGAD8DABEACAkGJFAGAD8DAAAA.',
Gu='Gulvid:BAACLgAFFH8HAAIDAAIJlx0OdwCqAAJoDAAAAwBYAOoMAAAEAD8AAwACCZcdDncAqgACaAwAAAMAWADqDAAABAA/AC4ABAp/GAADAwAHCWQhcE8AnQEAAwAHCWQhcE8AnQEABwABCQAAqlwAWAAAAS4ABRQHCRgAAwDsFgA=.',
Ha='Haluak:BAABLgAECn8pAAIFAAkJMxg5FgASAgloDAAABwBBAGkMAAAIAEsAawwAAAcASgBqDAAABQBOAGwMAAADADsAbQwAAAIAKADqDAAABgBFAG4MAAACACwAbwwAAAEAQgAFAAkJMxg5FgASAgloDAAABwBBAGkMAAAIAEsAawwAAAcASgBqDAAABQBOAGwMAAADADsAbQwAAAIAKADqDAAABgBFAG4MAAACACwAbwwAAAEAQgAAAA==.',
He='Healthyself:BAAALgAECgYJCwAAAA==.',
Ho='Houndtamer:BAABLgAECn8rAAISAAgJ3RN9RgCpAQhoDAAABwBFAGkMAAAHACkAawwAAAcALgBqDAAABwA+AGwMAAAEAC0AbQwAAAEAGgDqDAAABwA2AG4MAAADAEgAEgAICd0TfUYAqQEIaAwAAAcARQBpDAAABwApAGsMAAAHAC4AagwAAAcAPgBsDAAABAAtAG0MAAABABoA6gwAAAcANgBuDAAAAwBIAAAA.',
Hp='Hpyflowers:BAAALgADCgQJBAAAAA==.',
Hr='Hruoth:BAAALgAECgYJBgAAAA==.',
Ic='Iceshooting:BAAALgAECgQJBwAAAA==.',
Is='Ishtar:BAABLgAECn8ZAAMTAAYJ9BzVhADIAQZoDAAABQBFAGkMAAAFAFEAawwAAAQATQBqDAAABABMAGwMAAAEAFMA6gwAAAMAOgATAAYJCRnVhADIAQZoDAAAAwAqAGkMAAAFAFEAawwAAAMATQBqDAAABABMAGwMAAAEAFMA6gwAAAIAIwAUAAMJzRkuDwDQAANoDAAAAgBFAGsMAAABAEYA6gwAAAEAOgAAAA==.',
It='Itshela:BAACLgAFFH8aAAMBAAcJfxiJEwDbAQdoDAAABgBRAGkMAAAEAFUAawwAAAMAJgBqDAAABQA2AGwMAAACACAAbQwAAAEAPgDqDAAABQBMAAEABgl/GIkTANsBBmgMAAAGAFEAaQwAAAQAVQBrDAAAAwAmAGwMAAACACAAbQwAAAEAPgDqDAAABQBMAA8AAQkAAK9DAAAAAWoMAAAFADYALgAECn8bAAIBAAcJOCPrTQAJAgABAAcJOCPrTQAJAgAAAA==.',
Ja='Jayrad:BAAALgAECgYJEAAAAA==.',
Je='Jehnovah:BAAALgADCgMJAwAAAA==.Jellybeanz:BAAALgADCggJDQAAAA==.',
Jo='Jordybear:BAAALgAECgQJBAAAAA==.Jorkoh:BAAALgAECgMJBgAAAA==.',
Ju='Juicer:BAAALgADCgMJBgAAAA==.',
Ka='Kaiige:BAAALgAECgQJBAAAAA==.Kairos:BAAALgAECgYJCgAAAA==.Kanê:BAAALgAFFAMJAwAAAA==.',
Ke='Kehlayr:BAAALgADCgMJAwAAAA==.Keiiry:BAAALgADCgMJAwAAAA==.Kenshinth:BAAALgAECgYJDwAAAA==.Kethrym:BAAALgAECgIJAgAAAA==.',
Kh='Khanor:BAAALgAECgYJEQAAAA==.',
Ki='Kiltro:BAAALgAECgQJBgAAAA==.Kimchichi:BAABLgAECn8WAAIIAAgJ9RokMAAlAghoDAAABQBHAGkMAAAEAEsAawwAAAQAPgBqDAAAAwApAGwMAAACAFAAbQwAAAIAVwDqDAAAAQA0AG4MAAABADQACAAICfUaJDAAJQIIaAwAAAUARwBpDAAABABLAGsMAAAEAD4AagwAAAMAKQBsDAAAAgBQAG0MAAACAFcA6gwAAAEANABuDAAAAQA0AAAA.Kintaro:BAAALgADCgYJDwAAAA==.',
Ko='Kogorko:BAAALgAECgIJAgAAAA==.',
Kr='Kry:BAAALgAECgIJAgAAAA==.',
['Kë']='Këarra:BAAALgAECgQJBwAAAA==.',
La='Labotimizer:BAAALgAECggJDwAAAA==.Lapriestess:BAAALgAECgYJCwAAAA==.Latoya:BAAALgAFFAIJAgAAAA==.',
Li='Lilbeemo:BAAALgAECgUJCgAAAA==.Lilyana:BAAALgAECgYJCwAAAA==.Liongs:BAAALgAECgYJBgABLgAECgYJDwAMAAAAAA==.Litdk:BAAALgADCgUJBQAAAA==.Litharidk:BAABLgAECn8cAAIBAAcJVCDeQwDcAQdoDAAABgBZAGkMAAAHAFkAawwAAAUATQBqDAAAAwBdAGwMAAACAEoAbQwAAAEATgDqDAAABABXAAEABwlUIN5DANwBB2gMAAAGAFkAaQwAAAcAWQBrDAAABQBNAGoMAAADAF0AbAwAAAIASgBtDAAAAQBOAOoMAAAEAFcAAAA=.',
Lo='Loudog:BAAALgAECgYJBwAAAA==.Loxyblue:BAAALgAECgMJAwAAAA==.',
Lu='Luckyxpain:BAABLgAECn84AAMIAAkJ7RmMLgAsAgloDAAACgBRAGkMAAAHAD0AawwAAAkARQBqDAAABwBcAGwMAAAKAD8AbQwAAAMAXgDqDAAABgBLAG4MAAADAE8AbwwAAAEABQAIAAkJ7RmMLgAsAgloDAAABwBRAGkMAAAGAD0AawwAAAcARQBqDAAABQBcAGwMAAAFAD8AbQwAAAMAXgDqDAAAAwBLAG4MAAADAE8AbwwAAAEABQAVAAYJ/AmOLgCLAAZoDAAAAwARAGkMAAABABwAawwAAAIAEQBqDAAAAgApAGwMAAAFABsA6gwAAAMAJAAAAA==.',
Ly='Lykos:BAAALgAECgEJAQAAAA==.',
Ma='Madoff:BAAALgAECgQJCAAAAA==.Makok:BAABLgAECn8aAAMWAAgJuhT5CgCLAQhoDAAABABJAGkMAAADADgAawwAAAMAJgBqDAAAAwAmAGwMAAACAB0AbQwAAAEAKgDqDAAABwA7AG4MAAADAEUAFgAICboU+QoAiwEIaAwAAAQASQBpDAAAAwA4AGsMAAADACYAagwAAAMAJgBsDAAAAgAdAG0MAAABACoA6gwAAAYAOwBuDAAAAwBFABcAAQnsCfJxADMAAeoMAAABABkAAAA=.',
Me='Melancholic:BAABLgAECn8hAAMYAAgJUiBlEwA6AghoDAAABgBWAGkMAAAGAFIAawwAAAUARwBqDAAABAAwAGwMAAADAFYAbQwAAAEASwDqDAAABgBhAG4MAAACAE8AGAAICVIgZRMAOgIIaAwAAAUAVgBpDAAABgBSAGsMAAAFAEcAagwAAAQAMABsDAAAAwBWAG0MAAABAEsA6gwAAAYAYQBuDAAAAgBPABkAAQnFBARsACgAAWgMAAABAAwAAAA=.Mellisa:BAABLgAECn8fAAMBAAkJcxF/YgCHAQloDAAABwBIAGkMAAAEADUAawwAAAUANwBqDAAAAwBEAGwMAAACABgAbQwAAAEAEgDqDAAABwBNAG4MAAABABIAbwwAAAEAJAABAAgJ2w9/YgCHAQhoDAAABgBIAGkMAAADABAAawwAAAQANwBqDAAAAwBEAGwMAAACABgAbQwAAAEAEgDqDAAABgBNAG4MAAABABIADwAFCXUTLSQADQEFaAwAAAEALgBpDAAAAQA1AGsMAAABADQA6gwAAAEAPABvDAAAAQAkAAAA.Memory:BAAALgAECgEJAgAAAA==.',
Mi='Milkingman:BAAALgAECgEJAQAAAA==.',
Mo='Mooshmoo:BAAALgAECgEJAQAAAA==.',
Mu='Murog:BAABLgAECn8XAAIGAAgJSQ0TRAB1AQhoDAAAAgAvAGkMAAACADEAawwAAAIAEQBqDAAAAwArAGwMAAAEADIAbQwAAAIAEgDqDAAABgAgAG4MAAACAAwABgAICUkNE0QAdQEIaAwAAAIALwBpDAAAAgAxAGsMAAACABEAagwAAAMAKwBsDAAABAAyAG0MAAACABIA6gwAAAYAIABuDAAAAgAMAAAA.',
Na='Nazarite:BAAALgAECgYJDwAAAA==.',
Ni='Nightdisco:BAAALgAECgMJAwAAAA==.',
No='Noctyra:BAAALgAECgQJCAAAAA==.Nomaana:BAAALgAECgMJAwAAAA==.Norael:BAAALgADCgIJAgAAAA==.',
Og='Ogthunder:BAAALgAECgEJAQAAAA==.',
Op='Ophellia:BAAALgAECgEJAQAAAA==.',
Pu='Pureformance:BAAALgADCgcJBwABLgAFFAcJHgARAIIjAA==.Purrformance:BAACLgAFFH8eAAIRAAcJgiO1AgDBAgdoDAAABgBgAGkMAAAGAGEAawwAAAQAXABqDAAABABNAGwMAAACAF0AbQwAAAEAUADqDAAABwBhABEABwmCI7UCAMECB2gMAAAGAGAAaQwAAAYAYQBrDAAABABcAGoMAAAEAE0AbAwAAAIAXQBtDAAAAQBQAOoMAAAHAGEALgAECn8iAAIRAAkJoiUMAQCnAwARAAkJoiUMAQCnAwAAAA==.',
Py='Pyrophobiac:BAACLgAFFH8WAAMDAAcJ4xWVEgBSAQdoDAAABABLAGkMAAADABgAawwAAAMALQBqDAAAAQADAGwMAAADAFgAbQwAAAIAGADqDAAABgBPAAMABwnjFZUSAFIBB2gMAAAEAEsAaQwAAAIAGABrDAAAAQAtAGoMAAABAAMAbAwAAAMAWABtDAAAAgAYAOoMAAAGAE8ABwACCVgCSg8AfwACaQwAAAEABwBrDAAAAgAEAC4ABAp/IwADAwAJCdojgAMAhwMAAwAJCZgjgAMAhwMABwAHCaEdRwcAVAIAAAA=.',
Ra='Ra:BAABLgAECn8hAAIXAAgJTx/fCQBkAghoDAAABABPAGkMAAAFAFwAawwAAAUAXABqDAAABQBQAGwMAAAEAFAAbQwAAAIARQDqDAAABQBQAG4MAAADAEIAFwAICU8f3wkAZAIIaAwAAAQATwBpDAAABQBcAGsMAAAFAFwAagwAAAUAUABsDAAABABQAG0MAAACAEUA6gwAAAUAUABuDAAAAwBCAAAA.Radagast:BAACLgAFFH8IAAIaAAMJwgU9WQC3AANoDAAAAwAPAGkMAAACAA4A6gwAAAMADQAaAAMJwgU9WQC3AANoDAAAAwAPAGkMAAACAA4A6gwAAAMADQAuAAQKfysAAxoACAlsF1QuAPQBABoACAlEF1QuAPQBABcABgl0DxYqAPwAAAAA.Radditz:BAAALgAECgYJCwAAAA==.Rafiki:BAAALgAECgEJAQAAAA==.Rand:BAAALgADCgcJDgAAAA==.',
Ri='Riv:BAAALgAECgMJAwAAAA==.',
Ro='Ronni:BAAALgAECgQJBQAAAA==.Roxyfox:BAAALgAECgYJCwAAAA==.Royvaz:BAAALgAECgUJBQAAAA==.',
Sa='Salea:BAAALgAECgIJAgAAAA==.Sarryn:BAAALgADCgcJBwAAAA==.',
Sc='Scale:BAAALgAECgMJAwAAAA==.Schwiifty:BAAALgAECgEJAQAAAA==.',
Se='Serik:BAAALgADCgEJAQAAAA==.',
Sh='Shadorodo:BAAALgADCgIJAgAAAA==.Shakaboom:BAAALgAFFAEJAQAAAA==.Shakazoom:BAAALgAECgQJBAAAAA==.Sheffurs:BAABLgAECn8vAAIbAAkJzwIgNACeAAloDAAABQAEAGkMAAAHAAQAawwAAAYABABqDAAABgAGAGwMAAAGAAkAbQwAAAQADQDqDAAABwANAG4MAAAEAAMAbwwAAAIABAAbAAkJzwIgNACeAAloDAAABQAEAGkMAAAHAAQAawwAAAYABABqDAAABgAGAGwMAAAGAAkAbQwAAAQADQDqDAAABwANAG4MAAAEAAMAbwwAAAIABAAAAA==.Shepardl:BAACLgAFFH8kAAIOAAcJNCUAAQDiAgdoDAAABwBdAGkMAAAHAGEAawwAAAUAZABqDAAABQBNAGwMAAAEAGMAbQwAAAEAYgDqDAAABwBjAA4ABwk0JQABAOICB2gMAAAHAF0AaQwAAAcAYQBrDAAABQBkAGoMAAAFAE0AbAwAAAQAYwBtDAAAAQBiAOoMAAAHAGMALgAECn8hAAIOAAgJ5CYaAQCBAwAOAAgJ5CYaAQCBAwAAAA==.Shárkbait:BAAALgADCgcJDAABLgAFFAMJBwAPAB4LAA==.',
Sk='Skadoosher:BAAALgAECgUJBQAAAA==.Skyratt:BAAALgAECgEJAgAAAA==.',
Sm='Smackemz:BAAALgAECgYJCQAAAA==.Smacmywand:BAAALgAECgIJBgAAAA==.',
So='Sollasi:BAAALgADCgMJBgAAAA==.Sortie:BAABLgAECn8vAAMOAAkJjAkILwCBAQloDAAABQAHAGkMAAAHAAwAawwAAAYAFwBqDAAABgAPAGwMAAAGACQAbQwAAAQAGQDqDAAABwA0AG4MAAAEABMAbwwAAAIAGwAOAAkJjAkILwCBAQloDAAAAgAHAGkMAAADAAwAawwAAAMAFwBqDAAAAwAPAGwMAAAEACQAbQwAAAMAGQDqDAAAAgA0AG4MAAABABMAbwwAAAIAGwAIAAgJCwqViQBEAQhoDAAAAwAvAGkMAAAEACMAawwAAAMAFABqDAAAAwAkAGwMAAACAA4AbQwAAAEAEwDqDAAABQAaAG4MAAADABAAAAA=.',
Sp='Spoons:BAAALgAECgQJBAABLgAFFAUJFgAcAEocAA==.Spyromu:BAAALgAECgQJBgAAAA==.',
St='Stealman:BAAALgADCgcJBwAAAA==.Steeleman:BAAALgADCgQJAgAAAA==.',
Su='Succinic:BAAALgAECggJEAAAAA==.Suffer:BAAALgAECgQJBAAAAA==.',
Sw='Swiss:BAABLgAECn8bAAIOAAgJrw1ONACsAQhoDAAABAA3AGkMAAAEACIAawwAAAQAKwBqDAAAAwAlAGwMAAADABoAbQwAAAMAEwDqDAAAAwA5AG4MAAADAAcADgAICa8NTjQArAEIaAwAAAQANwBpDAAABAAiAGsMAAAEACsAagwAAAMAJQBsDAAAAwAaAG0MAAADABMA6gwAAAMAOQBuDAAAAwAHAAAA.',
Sy='Sylphvaria:BAAALgADCgUJBQAAAA==.Syren:BAAALgADCgcJBgAAAA==.',
Te='Tegridy:BAAALgAECgYJDQAAAA==.Teko:BAAALgADCgYJCwAAAA==.',
Th='Thegoose:BAAALgAECgIJAgAAAA==.Themans:BAAALgAECgYJDgAAAA==.Thunderrod:BAABLgAECn8lAAISAAgJUBXOPgC0AQhoDAAABwBFAGkMAAAGAEwAawwAAAcARQBqDAAABgBRAGwMAAAFAEcAbQwAAAEAEADqDAAABAAwAG4MAAABAB0AEgAICVAVzj4AtAEIaAwAAAcARQBpDAAABgBMAGsMAAAHAEUAagwAAAYAUQBsDAAABQBHAG0MAAABABAA6gwAAAQAMABuDAAAAQAdAAAA.',
Ti='Tim:BAAALgAECgEJAQAAAA==.',
To='To:BAAALgAECgIJAgAAAA==.Tovisar:BAAALgAECgMJCQAAAA==.',
Tr='Traessa:BAAALgADCgYJBgAAAA==.',
Tu='Turkturkletn:BAAALgADCgcJEQAAAA==.',
Tw='Twogg:BAAALgAECgYJDgAAAA==.',
Ug='Ugin:BAAALgADCgYJBgAAAA==.Uglykasanova:BAAALgAECgYJEQAAAA==.',
Ul='Ulfrir:BAAALgAECgcJCAAAAA==.',
Va='Vastian:BAAALgAECgUJDgAAAA==.Vaynard:BAAALgAECgQJBAAAAA==.',
Vi='Violet:BAAALgAECgMJBQAAAA==.Vitre:BAAALgAECgUJBwAAAA==.',
Wa='Wanshi:BAAALgAECgcJBgAAAA==.',
We='Wexew:BAABLgAECn8UAAMdAAYJmhmTGAAKAQZoDAAAAwA3AGkMAAAEADYAawwAAAQARwBqDAAAAgBYAGwMAAABAFMA6gwAAAYAPgAFAAUJChW+SgAdAQVoDAAAAgA3AGkMAAABADAAawwAAAIAMABqDAAAAQAuAOoMAAADAD4AHQAGCccXkxgACgEGaAwAAAEAIQBpDAAAAwA2AGsMAAACAEcAagwAAAEAWABsDAAAAQBTAOoMAAADAD0AAS4ABRQBCQEADAAAAAA=.Wexwex:BAAALgAECgUJDwABLgAFFAEJAQAMAAAAAA==.Wexxew:BAAALgAFFAEJAQAAAA==.',
Wi='Wishing:BAABLgAECn8UAAIOAAYJXhMzMQB0AQZoDAAAAwA2AGkMAAADABwAawwAAAMAEABqDAAABABGAGwMAAADAEIA6gwAAAQAPAAOAAYJXhMzMQB0AQZoDAAAAwA2AGkMAAADABwAawwAAAMAEABqDAAABABGAGwMAAADAEIA6gwAAAQAPAAAAA==.',
Wu='Wundertot:BAAALgAECgYJBgABLgAECggJKgATACwgAA==.Wunderwazard:BAABLgAECn8qAAITAAgJLCCRLwBDAghoDAAABwBXAGkMAAAGAFYAawwAAAYAUwBqDAAABQBJAGwMAAAFAEMAbQwAAAMARADqDAAABgBdAG4MAAAEAFkAEwAICSwgkS8AQwIIaAwAAAcAVwBpDAAABgBWAGsMAAAGAFMAagwAAAUASQBsDAAABQBDAG0MAAADAEQA6gwAAAYAXQBuDAAABABZAAAA.',
Xe='Xevikan:BAABLgAECn8bAAMBAAcJDBXpdwBWAQdoDAAABgBHAGkMAAAFADYAawwAAAUASwBqDAAAAgAnAGwMAAACACkAbQwAAAIAHADqDAAABQAzAAEABwkMFel3AFYBB2gMAAAFAEcAaQwAAAUANgBrDAAABQBLAGoMAAACACcAbAwAAAIAKQBtDAAAAgAcAOoMAAAFADMAHgABCR8IkDAAKgABaAwAAAEAFAAAAA==.',
Ya='Yadead:BAAALgAECgYJCwAAAA==.',
Za='Zaylen:BAAALgAECgYJEwAAAA==.',
Ze='Zendjin:BAAALgADCgYJDQAAAA==.Zenlore:BAAALgADCgYJBgAAAA==.',
Zi='Zistormstout:BAABLgAECn8sAAIFAAgJ1hVrIgCtAQhoDAAABwAzAGkMAAAHADEAawwAAAcAQwBqDAAABwBMAGwMAAAEAEYAbQwAAAEAJgDqDAAACAAoAG4MAAADAEoABQAICdYVayIArQEIaAwAAAcAMwBpDAAABwAxAGsMAAAHAEMAagwAAAcATABsDAAABABGAG0MAAABACYA6gwAAAgAKABuDAAAAwBKAAAA.',
Zu='Zuhgonemad:BAAALgAECgQJBgAAAA==.',
['Äl']='Älektra:BAABLgAECn8fAAIaAAgJvAQEiQDrAAhoDAAABQAIAGkMAAAGAAwAawwAAAYADQBqDAAABAANAGwMAAADAAkAbQwAAAIADADqDAAABAAJAG8MAAABABIAGgAICbwEBIkA6wAIaAwAAAUACABpDAAABgAMAGsMAAAGAA0AagwAAAQADQBsDAAAAwAJAG0MAAACAAwA6gwAAAQACQBvDAAAAQASAAAA.',
['Ñe']='Ñeph:BAAALgAECgUJBQAAAA==.',
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
