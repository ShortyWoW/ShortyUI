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

local lookup = {'Monk-Windwalker','Shaman-Enhancement','Monk-Mistweaver','Paladin-Retribution','Paladin-Holy','Priest-Holy','Unknown-Unknown','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','Warrior-Fury','Warrior-Protection','Mage-Arcane','Paladin-Protection','Druid-Feral','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Monk-Brewmaster','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Warlock-Demonology','Warlock-Destruction','Mage-Frost','DemonHunter-Havoc','Priest-Discipline','DeathKnight-Unholy','DeathKnight-Blood','DemonHunter-Devourer',}
local provider = {region='US',realm='Dalaran',name='US',type='subscribers',zone=46,date='2026-05-13',data={Ad='Adansso:BAEBLgAECn8rAAIBAAgJfg8YGQB1AQhoDAAACAAoAGkMAAAHADoAawwAAAYAQwBqDAAABAAlAGwMAAAFABcAbQwAAAIAFgDqDAAABwAcAG4MAAAEACUAAQAICX4PGBkAdQEIaAwAAAgAKABpDAAABwA6AGsMAAAGAEMAagwAAAQAJQBsDAAABQAXAG0MAAACABYA6gwAAAcAHABuDAAABAAlAAAA.',
Al='Aliastei:BAEALgADCgQJBAABLgAECggJIAACAI8ZAA==.',
Ap='Apawcowlypse:BAEALgADCgcJDAABLgAFFAQJCwADAPcLAA==.',
As='Ashko:BAEBLgAECn8gAAMEAAgJNBnfJAAGAghoDAAABgBBAGkMAAAFAFMAawwAAAQAUQBqDAAABQBGAGwMAAAEAFEAbQwAAAIAKwDqDAAABQA1AG4MAAABACkABAAICTQZ3yQABgIIaAwAAAYAQQBpDAAABQBTAGsMAAAEAFEAagwAAAUARgBsDAAABABRAG0MAAACACsA6gwAAAQANQBuDAAAAQApAAUAAQmpCs9uAC0AAeoMAAABABsAAAA=.',
Ay='Ayodele:BAEALgAECggJEgAAAA==.',
Az='Azurlia:BAEALgAECgYJEQAAAA==.',
Ba='Babycora:BAEALgAECgYJBwABLgAECgkJLwAGAOYdAA==.Bagelandlox:BAEALgADCgEJAQABLgAECgYJDAAHAAAAAA==.Barrui:BAECLgAFFH8fAAMIAAgJRBkIAQA6AghoDAAABgBBAGkMAAAGAGAAawwAAAUAOwBqDAAABABOAGwMAAABAAQAbQwAAAEAJADqDAAABwBcAG4MAAABAGEACAAHCUccCAEAOgIHaAwAAAYAQQBpDAAABQBSAGsMAAAEADsAagwAAAQATgBtDAAAAQAkAOoMAAAHAFwAbgwAAAEAYQAJAAMJWRBwAgAVAQNpDAAAAQBgAGsMAAABABgAbAwAAAEABAAuAAQKfzMAAwgACQlnJOkFADMDAAgACQnwIukFADMDAAkABgkTIS8EAHACAAAA.',
Be='Belynila:BAECLgAFFH8GAAIKAAIJRxa9GgCpAAJoDAAABABEAGkMAAACAC0ACgACCUcWvRoAqQACaAwAAAQARABpDAAAAgAtAC4ABAp/LwACCgAJCdodCQQAzAIACgAJCdodCQQAzAIAAAA=.',
Br='Briggoker:BAEALgAECgMJAwAAAA==.Brigmahf:BAEALgAECgQJCQABLgAECgMJAwAHAAAAAA==.',
Ca='Carbonarra:BAEBLgAECn8lAAILAAYJiB2AHACYAQZoDAAACABbAGkMAAAHAEAAawwAAAcAUgBqDAAABQBUAGwMAAAFAEgA6gwAAAUAQwALAAYJiB2AHACYAQZoDAAACABbAGkMAAAHAEAAawwAAAcAUgBqDAAABQBUAGwMAAAFAEgA6gwAAAUAQwAAAA==.Catcam:BAEALgAECgYJBgAAAA==.',
Ch='Chetegos:BAEALgADCgYJBgABLgAECgkJMwAMAM4jAA==.Chíefsquirel:BAEALgAECgYJDAAAAA==.',
Da='Dadbanger:BAECLgAFFH8jAAMBAAgJCR44AABxAghoDAAABgBiAGkMAAAGAGAAawwAAAUASgBqDAAABgBfAGwMAAADAEQAbQwAAAEAJQDqDAAABwBhAG4MAAABAEEAAQAHCZweOAAAcQIHaAwAAAYAYgBpDAAABgBgAGsMAAAFAEoAagwAAAYAXwBtDAAAAQAlAOoMAAAHAGEAbgwAAAEAQQADAAEJkgVBFgBJAAFsDAAAAwAOAC4ABAp/IgACAQAICWkmCQIAhAMAAQAICWkmCQIAhAMAAAA=.Daeke:BAEALgADCgUJBQABLgAECgQJBwAHAAAAAA==.Daekeypoo:BAEALgAECgQJBwAAAA==.Darkvirgo:BAEALgAFFAMJAwABLgAFFAYJGAAKAD8VAA==.',
De='Deathbeaver:BAEALgAECgQJBQABLgAECggJOwAEACkdAA==.Destrom:BAEALgAECggJEQAAAA==.',
Ep='Epilepticc:BAECLgAFFH8IAAIEAAQJTRvvFABhAQRoDAAAAwBCAGkMAAACAFUAawwAAAEAMgDqDAAAAgBNAAQABAlNG+8UAGEBBGgMAAADAEIAaQwAAAIAVQBrDAAAAQAyAOoMAAACAE0ALgAECn87AAIEAAkJ6yItCADmAgAEAAkJ6yItCADmAgAAAA==.',
Et='Ethalon:BAECLgAFFH8IAAIFAAQJiwzxFAAfAQRoDAAAAwBIAGkMAAACABkAawwAAAEADwDqDAAAAgAOAAUABAmLDPEUAB8BBGgMAAADAEgAaQwAAAIAGQBrDAAAAQAPAOoMAAACAA4ALgAECn8jAAMFAAkJHRonGABRAgAFAAkJHRonGABRAgAEAAIJlBM3FQE5AAAAAA==.',
Fa='Fallhp:BAEALgADCgYJBgABLgAFFAcJFQAFAMAVAA==.Fallill:BAEALgAECgIJAgABLgAFFAcJFQAFAMAVAA==.Falosso:BAECLgAFFH8VAAIFAAcJwBUCAgBJAgdoDAAAAwA1AGkMAAADAEcAawwAAAMAQABqDAAAAwBLAGwMAAADAA0AbQwAAAEAHwDqDAAABQBQAAUABwnAFQICAEkCB2gMAAADADUAaQwAAAMARwBrDAAAAwBAAGoMAAADAEsAbAwAAAMADQBtDAAAAQAfAOoMAAAFAFAALgAECn8yAAMFAAkJjyA7BQDsAgAFAAkJjyA7BQDsAgAEAAEJPQr5JQEyAAAAAA==.',
Ga='Garlooth:BAEBLgAECn8hAAINAAgJqR4iAQBkAghoDAAABQBTAGkMAAAFAFMAawwAAAUATQBqDAAAAwAyAGwMAAAEAEkAbQwAAAMAXgDqDAAABQA+AG4MAAADAEoADQAICakeIgEAZAIIaAwAAAUAUwBpDAAABQBTAGsMAAAFAE0AagwAAAMAMgBsDAAABABJAG0MAAADAF4A6gwAAAUAPgBuDAAAAwBKAAAA.',
Gl='Glizzygary:BAEALgAFFAQJCAAAAQ==.',
Gr='Grimvalor:BAEBLgAECn87AAMEAAgJKR1eHAA3AghoDAAACQBcAGkMAAAIAEAAawwAAAkAUgBqDAAACABYAGwMAAAIAFIAbQwAAAUASwDqDAAACQBSAG4MAAADACoABAAICSkdXhwANwIIaAwAAAgAXABpDAAACABAAGsMAAAIAFIAagwAAAcAWABsDAAABwBSAG0MAAAFAEsA6gwAAAgAUgBuDAAAAwAqAA4ABQnPCjgqAGUABWgMAAABAA8AawwAAAEALABqDAAAAQAsAGwMAAABACIA6gwAAAEADwAAAA==.Grunclaws:BAEALgAECgYJBgABLgAECgkJIAAEADQZAA==.Grunjitsu:BAEALgAECgkJBQABLgAECgkJIAAEADQZAA==.Grunsy:BAEALgAECgcJAgABLgAECgkJIAAEADQZAA==.',
Ha='Haf:BAEBLgAECn8pAAIOAAkJ8hGOCwCdAQloDAAABwA9AGkMAAAGAEIAawwAAAYARwBqDAAABQAjAGwMAAAFADYAbQwAAAMAFQDqDAAABgAvAG4MAAACABYAbwwAAAEAFwAOAAkJ8hGOCwCdAQloDAAABwA9AGkMAAAGAEIAawwAAAYARwBqDAAABQAjAGwMAAAFADYAbQwAAAMAFQDqDAAABgAvAG4MAAACABYAbwwAAAEAFwAAAA==.',
He='Hertzmuch:BAEALgADCgYJDgABLgAFFAQJCwADAPcLAA==.',
Ho='Holeighfuk:BAEALgAECgYJBgAAAA==.',
Jo='Joicountdown:BAEBLgAFFH8qAAIPAAgJ+CYDAAAcAwhoDAAABwBjAGkMAAAHAGQAawwAAAcAYgBqDAAABgBkAGwMAAADAGQAbQwAAAIAZADqDAAACQBkAG4MAAABAGQADwAICfgmAwAAHAMIaAwAAAcAYwBpDAAABwBkAGsMAAAHAGIAagwAAAYAZABsDAAAAwBkAG0MAAACAGQA6gwAAAkAZABuDAAAAQBkAAEuAAQKBgkGAAcAAAAA.',
Ka='Kautheros:BAEBLgAECn8cAAQQAAgJpwvHDgByAQhoDAAABAAIAGkMAAAEABkAawwAAAQAOwBqDAAABAAfAGwMAAADACIAbQwAAAMACQDqDAAABAAmAG4MAAACAB0AEAAICacLxw4AcgEIaAwAAAIACABpDAAAAgAZAGsMAAACADsAagwAAAIAHwBsDAAAAQAiAG0MAAADAAkA6gwAAAMAJgBuDAAAAgAdABEABglSCUI1AOMABmgMAAABAB0AaQwAAAEAGABrDAAAAgAcAGoMAAABACQAbAwAAAIAFwDqDAAAAQAMABIAAwmaBmUVAFgAA2gMAAABAAkAaQwAAAEAGABqDAAAAQAaAAAA.',
Kr='Kroxychi:BAEALgAECgcJDQAAAA==.Kroxypurple:BAEALgADCgIJAgABLgAECgcJDQAHAAAAAA==.',
Ku='Kungfused:BAECLgAFFH8LAAIDAAQJ9wvqFgD4AARoDAAABAAqAGkMAAAEACUAawwAAAIAFwDqDAAAAQATAAMABAn3C+oWAPgABGgMAAAEACoAaQwAAAQAJQBrDAAAAgAXAOoMAAABABMALgAECn9HAAMDAAkJQx3ACgClAgADAAkJQx3ACgClAgABAAgJWhPtEwCpAQAAAA==.',
Le='Leenfiey:BAECLgAFFH8KAAMTAAMJXCO6EgA2AQNoDAAAAwBfAGkMAAADAFEA6gwAAAQAXQATAAMJXCO6EgA2AQNoDAAAAgBfAGkMAAACAFEA6gwAAAIAXQABAAMJGA3FFwCuAANoDAAAAQAAAGkMAAABADEA6gwAAAIAMgAuAAQKfxkAAxMABglMJd0UAGUCABMABgkrJd0UAGUCAAEAAQkdJSNLAGsAAAAA.Lennather:BAEBLgAECn8zAAIBAAkJHCXPAABdAwloDAAABwBjAGkMAAAHAGEAawwAAAYAWwBqDAAABgBOAGwMAAAGAGAAbQwAAAUAXgDqDAAABwBdAG4MAAAFAF8AbwwAAAIAWgABAAkJHCXPAABdAwloDAAABwBjAGkMAAAHAGEAawwAAAYAWwBqDAAABgBOAGwMAAAGAGAAbQwAAAUAXgDqDAAABwBdAG4MAAAFAF8AbwwAAAIAWgAAAA==.',
Li='Lidrunka:BAEBLgAECn8WAAMBAAgJbhTVGwD9AQhoDAAABABKAGkMAAAEAD8AawwAAAMARABqDAAAAgAjAGwMAAACADYAbQwAAAEAHADqDAAABQA/AG4MAAABAAwAAQAICcoT1RsA/QEIaAwAAAMASgBpDAAAAwA0AGsMAAACAEQAagwAAAIAIwBsDAAAAgA2AG0MAAABABwA6gwAAAQAPwBuDAAAAQAMABMABAkWFGcwAO0ABGgMAAABACwAaQwAAAEAPwBrDAAAAQA7AOoMAAABACUAAAA=.',
['Lé']='Lépewpew:BAEBLgAECn8YAAIUAAcJSRLbFACOAQdoDAAABQA+AGkMAAAFADMAawwAAAUAOwBqDAAAAwBNAGwMAAABACYA6gwAAAQAOgBuDAAAAQAKABQABwlJEtsUAI4BB2gMAAAFAD4AaQwAAAUAMwBrDAAABQA7AGoMAAADAE0AbAwAAAEAJgDqDAAABAA6AG4MAAABAAoAAAA=.',
Ma='Mattimus:BAEBLgAECn8VAAMVAAYJXg7YWgAaAQZoDAAABAA9AGkMAAAEACUAawwAAAUAGgBqDAAAAwAkAGwMAAACABQA6gwAAAMAJQAVAAYJXg7YWgAaAQZoDAAABAA9AGkMAAADACUAawwAAAQAGgBqDAAAAgAkAGwMAAACABQA6gwAAAIAJQAWAAQJ+QK2cAB8AARpDAAAAQABAGsMAAABAAkAagwAAAEACQDqDAAAAQAMAAAA.',
['Má']='Mákí:BAEALgAECgYJEAAAAA==.',
Na='Natebanger:BAEALgAECgYJDAABLgAFFAgJIwABAAkeAA==.',
Ne='Nethertank:BAEALgAECgQJBAABLgAECgYJDAAHAAAAAA==.',
No='Noeyednuck:BAEALgAECgQJCQABLgAECgkJLAAVAIseAA==.',
Nu='Nuckshott:BAEBLgAECn8sAAIVAAkJix4CDACaAgloDAAABgBFAGkMAAAGAFgAawwAAAYASwBqDAAABQBZAGwMAAAFAFgAbQwAAAQATgDqDAAABgBWAG4MAAAEAEQAbwwAAAIARQAVAAkJix4CDACaAgloDAAABgBFAGkMAAAGAFgAawwAAAYASwBqDAAABQBZAGwMAAAFAFgAbQwAAAQATgDqDAAABgBWAG4MAAAEAEQAbwwAAAIARQAAAA==.',
Og='Ogx:BAEALgAECgQJBQABLgAECgkJIAAEADQZAA==.',
Ol='Olgass:BAEALgADCgIJAgABLgAECggJKgAXAAwjAA==.',
Pu='Purlok:BAEALgAECgkJAwABLgAECgkJIAAEADQZAA==.',
Qu='Quinet:BAEBLgAECn8qAAMXAAgJDCM9CwCwAghoDAAABwBhAGkMAAAGAFsAawwAAAYAXABqDAAABQBRAGwMAAAFAFwAbQwAAAMAWADqDAAABwBeAG4MAAADAEcAFwAICQwjPQsAsAIIaAwAAAcAYQBpDAAABQBbAGsMAAAGAFwAagwAAAEAEABsDAAAAwBcAG0MAAADAFgA6gwAAAcAXgBuDAAAAwBHABgAAwnKHnEvAP0AA2kMAAABAEYAagwAAAQAUQBsDAAAAgBXAAAA.Quinman:BAEBLgAECn8aAAQUAAkJRBo+CAA9AgloDAAABQBBAGkMAAAEADMAawwAAAQATwBqDAAAAgAnAGwMAAACAGEAbQwAAAIAOwDqDAAABABBAG4MAAACAD0AbwwAAAEAOgAUAAkJixc+CAA9AgloDAAAAQA8AGkMAAABAAAAawwAAAEATwBqDAAAAgAnAGwMAAACAGEAbQwAAAIAOwDqDAAAAwBBAG4MAAACAD0AbwwAAAEAOgAWAAQJWhWQWQDfAARoDAAAAwBBAGkMAAADADMAawwAAAMAMQDqDAAAAQA0ABUAAQkVGELAAEAAAWgMAAABAD0AAAA=.Quinroxx:BAEBLgAECn8gAAIZAAgJXCN8KwDFAghoDAAABQBiAGkMAAAFAFsAawwAAAUAXwBqDAAABQBeAGwMAAADAFoAbQwAAAIAUwDqDAAABgBhAG4MAAABAE0AGQAICVwjfCsAxQIIaAwAAAUAYgBpDAAABQBbAGsMAAAFAF8AagwAAAUAXgBsDAAAAwBaAG0MAAACAFMA6gwAAAYAYQBuDAAAAQBNAAEuAAQKCQkaABQARBoA.Quinvinvin:BAEALgAECgcJDQABLgAECgkJGgAUAEQaAA==.',
Ri='Rispirvoke:BAEALgADCgUJBgABLgAFFAYJCQAWABYZAA==.',
Ro='Ronimus:BAEALgAECgEJAQAAAA==.',
Ru='Rufio:BAECLgAFFH8IAAIaAAIJeQ44EQCXAAJoDAAABQA2AGkMAAADABMAGgACCXkOOBEAlwACaAwAAAUANgBpDAAAAwATAC4ABAp/HwACGgAICekb9gsAoQIAGgAICekb9gsAoQIAAAA=.',
Ry='Rytiou:BAECLgAFFH8SAAIRAAUJKx1XBQCuAQVoDAAABABSAGkMAAAFAFYAawwAAAQALgBqDAAAAgBHAOoMAAADAFIAEQAFCSsdVwUArgEFaAwAAAQAUgBpDAAABQBWAGsMAAAEAC4AagwAAAIARwDqDAAAAwBSAC4ABAp/LQACEQAJCeckWQIAjAMAEQAJCeckWQIAjAMAAAA=.',
Sa='Saadxevok:BAEBLgAECn8YAAMSAAgJQRFLEADYAQhoDAAAAwA7AGkMAAADADEAawwAAAMARQBqDAAAAwAwAGwMAAAEAEgAbQwAAAMACADqDAAAAwAkAG4MAAACAAwAEgAICUERSxAA2AEIaAwAAAMAOwBpDAAAAwAxAGsMAAACAEUAagwAAAIAMABsDAAAAwBIAG0MAAABAAgA6gwAAAEAJABuDAAAAQAMABAABglTCD0pACkBBmsMAAABABAAagwAAAEAEQBsDAAAAQARAG0MAAACAB4A6gwAAAIAJwBuDAAAAQAGAAEuAAUUCAkjAAoAZB4A.Saadxm:BAEALgAECgcJDwABLgAFFAgJIwAKAGQeAA==.Saadxp:BAECLgAFFH8jAAMKAAgJZB7JAABZAghoDAAABQBjAGkMAAAGAGAAawwAAAYAYABqDAAABgBYAGwMAAADACAAbQwAAAEAVADqDAAABwBeAG4MAAABACkACgAHCV0hyQAAWQIHaAwAAAQAYwBpDAAABQBgAGsMAAAFAGAAagwAAAUAWABtDAAAAQBUAOoMAAAFAF4AbgwAAAEAKQAbAAYJ5RnxAQANAgZoDAAAAQBJAGkMAAABAB0AawwAAAEAWgBqDAAAAQBOAGwMAAADADMA6gwAAAIASgAuAAQKfyUAAwoACAmHJpADAN8CAAoACAmHJpADAN8CABsABQkLHz4gAJEBAAAA.Sanityvanish:BAEALgAECgIJAwABLgAECgMJBAAHAAAAAA==.',
Sg='Sgtgigachad:BAEALgADCgYJBgABLgAFFAQJCAAHAAAAAQ==.',
Sp='Spilt:BAECLgAFFH8ZAAIZAAcJoBmvAQCMAgdoDAAABQBaAGkMAAAFAFQAawwAAAQALwBqDAAAAwAaAGwMAAABABAAbQwAAAEARgDqDAAABgBTABkABwmgGa8BAIwCB2gMAAAFAFoAaQwAAAUAVABrDAAABAAvAGoMAAADABoAbAwAAAEAEABtDAAAAQBGAOoMAAAGAFMALgAECn8dAAIZAAkJySTjCgBtAwAZAAkJySTjCgBtAwAAAA==.Spiltmonk:BAEBLgAECn8YAAIBAAYJWh80HAD6AQZoDAAABABGAGkMAAAEAFEAawwAAAQAUgBqDAAABABMAGwMAAADAFIA6gwAAAUAVAABAAYJWh80HAD6AQZoDAAABABGAGkMAAAEAFEAawwAAAQAUgBqDAAABABMAGwMAAADAFIA6gwAAAUAVAABLgAFFAcJGQAZAKAZAA==.',
Su='Sunjo:BAEALgAECgkJBAABLgAECgkJIAAEADQZAA==.',
Ta='Taku:BAEALgAECgcJDQABLgAECggJHAAQAKcLAA==.Taymeean:BAEALgAECgMJBAABLgAFFAMJBgARAGQJAA==.Tayvok:BAECLgAFFH8GAAIRAAMJZAnzKQDJAANoDAAAAgAOAGkMAAADADAA6gwAAAEACQARAAMJZAnzKQDJAANoDAAAAgAOAGkMAAADADAA6gwAAAEACQAuAAQKfywAAhEACQmQHLwFAKUCABEACQmQHLwFAKUCAAAA.',
Te='Tentickles:BAECLgAFFH8MAAIKAAQJlx/vBgCCAQRoDAAAAwBIAGkMAAADAFsAawwAAAIAYQDqDAAABAA9AAoABAmXH+8GAIIBBGgMAAADAEgAaQwAAAMAWwBrDAAAAgBhAOoMAAAEAD0ALgAECn8UAAIKAAgJeiJyCAD9AgAKAAgJeiJyCAD9AgABLgAFFAgJIwABAAkeAA==.Tetakoawara:BAEALgAECgUJCwABLgAFFAMJCgATAFwjAA==.',
Th='Thecheatt:BAEBLgAECn8zAAMMAAkJziPAAgC/AgloDAAACABhAGkMAAAIAGEAawwAAAkAYgBqDAAABwBdAGwMAAAHAF0AbQwAAAIAWgDqDAAABwBfAG4MAAACAEcAbwwAAAEAWQAMAAkJziPAAgC/AgloDAAABwBhAGkMAAAGAGEAawwAAAcAYgBqDAAABQBdAGwMAAAEAF0AbQwAAAIAWgDqDAAABABfAG4MAAACAEcAbwwAAAEAWQALAAYJnxbqSQB9AQZoDAAAAQAQAGkMAAACAEoAawwAAAIANgBqDAAAAgAyAGwMAAADAE8A6gwAAAMAPwAAAA==.',
Ty='Tyära:BAEBLgAECn8dAAMcAAgJSwsqZAAzAQhoDAAABgAYAGkMAAAGACQAawwAAAUAPgBqDAAAAwAXAGwMAAACAB4AbQwAAAEADQDqDAAABQAUAG4MAAABAA4AHAAHCUEJKmQAMwEHaAwAAAUAEgBpDAAABQAZAGsMAAAEACYAagwAAAIAEwBsDAAAAQAeAOoMAAAEAA0AbgwAAAEADgAdAAcJtQqYHQD1AAdoDAAAAQAYAGkMAAABACQAawwAAAEAPgBqDAAAAQAXAGwMAAABAAcAbQwAAAEADQDqDAAAAQAUAAEuAAQKCAkoABkAshgA.',
Vi='Vigiz:BAEALgAECgYJBgAAAA==.Vilexie:BAEALgAECggJCQAAAA==.',
['Vì']='Vìgïz:BAEALgAECgEJAQABLgAECgYJBgAHAAAAAA==.',
Wa='Wafflé:BAEALgAECgIJAgAAAA==.',
Wh='Whitecrosses:BAEALgAECgEJAQABLgAECgcJGAAUAEkSAA==.',
Wi='Wiskystagger:BAEALgADCgEJAgAAAA==.',
Za='Zargan:BAEALgAECgcJCAABLgAECggJHAAQAKcLAA==.',
Ze='Zertzz:BAEALgAFFAEJAQABLgAFFAUJFQAKACIgAA==.',
Zi='Zibbz:BAEBLgAECn8wAAMRAAkJlCN0AQBOAwloDAAABgBgAGkMAAAGAGMAawwAAAYAYgBqDAAABQBZAGwMAAAHAF8AbQwAAAUAXwDqDAAABgBbAG4MAAAGAFsAbwwAAAEAOwARAAkJlCN0AQBOAwloDAAABQBgAGkMAAAFAGMAawwAAAUAYgBqDAAABABZAGwMAAAGAF8AbQwAAAUAXwDqDAAABQBbAG4MAAAFAFsAbwwAAAEAOwASAAcJyxqoAwDxAQdoDAAAAQBOAGkMAAABAFAAawwAAAEARwBqDAAAAQBGAGwMAAABAEcA6gwAAAEAUwBuDAAAAQAZAAEuAAQKCQknAB4ALB4A.Zinia:BAEBLgAECn8gAAICAAgJjxnNBgDpAQhoDAAABgBXAGkMAAAGAFIAawwAAAYAOQBqDAAAAwA6AGwMAAADAEcAbQwAAAEAMQDqDAAABQBCAG4MAAACACsAAgAICY8ZzQYA6QEIaAwAAAYAVwBpDAAABgBSAGsMAAAGADkAagwAAAMAOgBsDAAAAwBHAG0MAAABADEA6gwAAAUAQgBuDAAAAgArAAAA.',
Zu='Zubbfist:BAEALgADCgcJBwABLgAECgkJJwAeACweAA==.Zubbrael:BAEBLgAECn8fAAMKAAgJYRliIwC9AQhoDAAABwBKAGkMAAAFAEMAawwAAAQAQgBqDAAAAwA3AGwMAAAEADYAbQwAAAEAUgDqDAAABgBCAG4MAAABACoACgAHCTwYYiMAvQEHaAwAAAUASgBpDAAAAwBDAGsMAAACAEIAagwAAAEANwBsDAAAAgA2AOoMAAAEAEIAbgwAAAEAKgAbAAcJgwlxHgBXAQdoDAAAAgAOAGkMAAACABUAawwAAAIAIwBqDAAAAgArAGwMAAACABIAbQwAAAEAEgDqDAAAAgATAAEuAAQKCQknAB4ALB4A.Zubbz:BAEBLgAECn8nAAIeAAgJLB6THgCaAghoDAAABgBeAGkMAAAHAFgAawwAAAcAUwBqDAAABAA9AGwMAAAEAFcAbQwAAAIAJQDqDAAABwBYAG4MAAACADoAHgAICSwekx4AmgIIaAwAAAYAXgBpDAAABwBYAGsMAAAHAFMAagwAAAQAPQBsDAAABABXAG0MAAACACUA6gwAAAcAWABuDAAAAgA6AAAA.',
Zz='Zzertz:BAECLgAFFH8VAAIKAAUJIiBeBgCLAQVoDAAABgBhAGkMAAAFAFMAawwAAAQAVABqDAAAAQBYAOoMAAAFAEAACgAFCSIgXgYAiwEFaAwAAAYAYQBpDAAABQBTAGsMAAAEAFQAagwAAAEAWADqDAAABQBAAC4ABAp/KwACCgAICf8iOgYAKQMACgAICf8iOgYAKQMAAAA=.',
['Àb']='Àbeel:BAEALgAECgMJAwABLgAECggJLwAJABYbAA==.Àbel:BAEBLgAECn8vAAMJAAgJFhtjBgASAghoDAAACABXAGkMAAAJAFQAawwAAAcAWgBqDAAABgBeAGwMAAAEAD0AbQwAAAIAIwDqDAAACQBZAG4MAAACACQACQAHCUYdYwYAEgIHaAwAAAcAVwBpDAAACABUAGsMAAAFAFoAagwAAAUAXgBsDAAABAA9AOoMAAAIAFkAbgwAAAEAJAAIAAcJkhYHFgBzAQdoDAAAAQBJAGkMAAABAE8AawwAAAIATgBqDAAAAQBdAG0MAAACACMA6gwAAAEAOwBuDAAAAQAUAAAA.Àble:BAEALgADCgQJCQABLgAECggJLwAJABYbAA==.',
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
