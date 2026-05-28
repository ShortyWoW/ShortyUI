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

local lookup = {'Monk-Windwalker','Shaman-Enhancement','Monk-Mistweaver','Paladin-Retribution','Paladin-Holy','Mage-Frost','Priest-Holy','Unknown-Unknown','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','Warrior-Arms','Warrior-Fury','Warrior-Protection','DeathKnight-Unholy','Mage-Arcane','Paladin-Protection','Druid-Feral','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Monk-Brewmaster','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Warlock-Demonology','Warlock-Destruction','DemonHunter-Havoc','Priest-Discipline','DeathKnight-Blood','DemonHunter-Devourer',}
local provider = {region='US',realm='Dalaran',name='US',type='subscribers',zone=46,date='2026-05-27',data={Ad='Adansso:BAEBLgAECn80AAIBAAkJFxJ5GQDGAQloDAAACQArAGkMAAAIADoAawwAAAcAQwBqDAAABQA0AGwMAAAGADEAbQwAAAMAHADqDAAACAA7AG4MAAAFACUAbwwAAAEAGgABAAkJFxJ5GQDGAQloDAAACQArAGkMAAAIADoAawwAAAcAQwBqDAAABQA0AGwMAAAGADEAbQwAAAMAHADqDAAACAA7AG4MAAAFACUAbwwAAAEAGgAAAA==.',
Al='Aliastei:BAEALgADCggJDAABLgAECgkJLwACALsZAA==.',
Ap='Apawcowlypse:BAEALgADCgcJDAABLgAFFAQJEAADACAOAA==.',
As='Ashko:BAEBLgAECn8rAAMEAAgJDButLwAmAghoDAAACABLAGkMAAAHAFcAawwAAAYAUQBqDAAABgBSAGwMAAAFAFEAbQwAAAMAKwDqDAAABgBHAG4MAAACACkABAAICQwbrS8AJgIIaAwAAAgASwBpDAAABwBXAGsMAAAGAFEAagwAAAYAUgBsDAAABQBRAG0MAAADACsA6gwAAAUARwBuDAAAAgApAAUAAQmpCraGACsAAeoMAAABABsAAAA=.',
Ay='Ayodele:BAEBLgAECn8oAAIGAAkJJRilKABdAgloDAAABgBQAGkMAAAEADwAawwAAAQAQABqDAAABgBIAGwMAAAFAEkAbQwAAAMAPwDqDAAABgBIAG4MAAAEACgAbwwAAAIAJwAGAAkJJRilKABdAgloDAAABgBQAGkMAAAEADwAawwAAAQAQABqDAAABgBIAGwMAAAFAEkAbQwAAAMAPwDqDAAABgBIAG4MAAAEACgAbwwAAAIAJwAAAA==.',
Az='Azurlia:BAEALgAFFAEJAQAAAA==.',
Ba='Babycora:BAEALgAECgcJCgABLgAFFAMJCgAHAAQkAA==.Bagelandlox:BAEALgADCgEJAQABLgAECgYJDAAIAAAAAA==.Barrui:BAECLgAFFH8oAAMJAAgJtBwEAwBPAghoDAAABwBfAGkMAAAIAGAAawwAAAcAWQBqDAAABgBgAGwMAAABAAQAbQwAAAEAJADqDAAACQBdAG4MAAABAGEACQAHCUogBAMATwIHaAwAAAcAXwBpDAAABwBSAGsMAAAGAFkAagwAAAYAYABtDAAAAQAkAOoMAAAJAF0AbgwAAAEAYQAKAAMJWRBwAgAVAQNpDAAAAQBgAGsMAAABABgAbAwAAAEABAAuAAQKfzgAAwkACQlwJOkFADMDAAkACQnxIukFADMDAAoABgkfIS8EAHACAAAA.',
Be='Belynila:BAECLgAFFH8LAAILAAMJOiD2FAAnAQNoDAAABgBVAGkMAAAEAD4A6gwAAAEAYwALAAMJOiD2FAAnAQNoDAAABgBVAGkMAAAEAD4A6gwAAAEAYwAuAAQKf0AAAgsACQmgIdgDAAcDAAsACQmgIdgDAAcDAAAA.Bestiavera:BAEBLgAECn81AAIMAAgJLxUmEADLAQhoDAAACQBFAGkMAAAIAE4AawwAAAgAKgBqDAAABwA4AGwMAAAHACUAbQwAAAMAOQDqDAAABwA+AG4MAAAEACAADAAICS8VJhAAywEIaAwAAAkARQBpDAAACABOAGsMAAAIACoAagwAAAcAOABsDAAABwAlAG0MAAADADkA6gwAAAcAPgBuDAAABAAgAAAA.',
Br='Briggoker:BAEALgAECgQJBwAAAA==.Brigmahf:BAEALgAECgQJCQABLgAECgQJBwAIAAAAAA==.',
Ca='Carbonarra:BAEBLgAECn8vAAINAAgJVhp/GwD3AQhoDAAACQBbAGkMAAAIAEAAawwAAAgAUgBqDAAABgBUAGwMAAAGAEgAbQwAAAEAKwDqDAAABwBDAG4MAAACADEADQAICVYafxsA9wEIaAwAAAkAWwBpDAAACABAAGsMAAAIAFIAagwAAAYAVABsDAAABgBIAG0MAAABACsA6gwAAAcAQwBuDAAAAgAxAAAA.Catcam:BAEALgAECgYJBgAAAA==.',
Ch='Chetegos:BAEALgADCgYJBgABLgAECgkJOgAOAPEjAA==.Chíefsquirel:BAEALgAECgYJDAAAAA==.',
Da='Dadbanger:BAECLgAFFH8jAAMBAAgJCR44AABxAghoDAAABgBiAGkMAAAGAGAAawwAAAUASgBqDAAABgBfAGwMAAADAEQAbQwAAAEAJQDqDAAABwBhAG4MAAABAEEAAQAHCZweOAAAcQIHaAwAAAYAYgBpDAAABgBgAGsMAAAFAEoAagwAAAYAXwBtDAAAAQAlAOoMAAAHAGEAbgwAAAEAQQADAAEJkgVBFgBJAAFsDAAAAwAOAC4ABAp/KgACAQAICXEmCQIAhAMAAQAICXEmCQIAhAMAAAA=.Daeke:BAEALgADCgUJBQABLgAECgQJBwAIAAAAAA==.Daekeypoo:BAEALgAECgQJBwAAAA==.Darkvirgo:BAEBLgAFFH8JAAIGAAMJZAhodADXAANoDAAAAwAiAGkMAAADABgA6gwAAAMABQAGAAMJZAhodADXAANoDAAAAwAiAGkMAAADABgA6gwAAAMABQABLgAFFAYJIwALAPocAA==.',
De='Deathbeaver:BAEALgAECgYJCwABLgAECgkJSAAEAOscAA==.Destrom:BAEBLgAECn8UAAIPAAkJuBF1bwBrAQloDAAAAwAwAGkMAAADADAAawwAAAMASABqDAAAAgA2AGwMAAABAB4AbQwAAAEAKADqDAAAAwAXAG4MAAACAC0AbwwAAAIANQAPAAkJuBF1bwBrAQloDAAAAwAwAGkMAAADADAAawwAAAMASABqDAAAAgA2AGwMAAABAB4AbQwAAAEAKADqDAAAAwAXAG4MAAACAC0AbwwAAAIANQAAAA==.',
Ep='Epilepticc:BAECLgAFFH8MAAIEAAQJxB1CJwBDAQRoDAAABABCAGkMAAADAFUAawwAAAIASwDqDAAAAwBNAAQABAnEHUInAEMBBGgMAAAEAEIAaQwAAAMAVQBrDAAAAgBLAOoMAAADAE0ALgAECn88AAIEAAkJ6yIIFAC0AgAEAAkJ6yIIFAC0AgAAAA==.',
Et='Ethalon:BAECLgAFFH8PAAMFAAQJlRMOGwAmAQRoDAAABQBOAGkMAAAEAC0AawwAAAIADwDqDAAABAA9AAUABAmVEw4bACYBBGgMAAAEAE4AaQwAAAQALQBrDAAAAgAPAOoMAAAEAD0ABAABCbcCdJ8AOQABaAwAAAEABgAuAAQKfyUAAwUACQkdGicYAFECAAUACQkdGicYAFECAAQAAgnJFGpJAUQAAAAA.',
Fa='Fallhp:BAEALgADCgYJBgABLgAFFAgJFgAFALwUAA==.Fallill:BAEALgAECgIJAgABLgAFFAgJFgAFALwUAA==.Falosso:BAECLgAFFH8WAAIFAAgJvBQGAwB0AghoDAAAAwA1AGkMAAADAEcAawwAAAMAQABqDAAAAwBLAGwMAAADAA0AbQwAAAEAHwDqDAAABQBQAG4MAAABACIABQAICbwUBgMAdAIIaAwAAAMANQBpDAAAAwBHAGsMAAADAEAAagwAAAMASwBsDAAAAwANAG0MAAABAB8A6gwAAAUAUABuDAAAAQAiAC4ABAp/MwADBQAJCY8gyAoAxAIABQAJCY8gyAoAxAIABAACCRMObCMBZQAAAAA=.',
Ga='Garlooth:BAEBLgAECn8pAAIQAAkJnyGUAADzAgloDAAABQBTAGkMAAAGAFsAawwAAAYAXQBqDAAABQBRAGwMAAAFAF8AbQwAAAQAXgDqDAAABQA+AG4MAAAEAEoAbwwAAAEAXQAQAAkJnyGUAADzAgloDAAABQBTAGkMAAAGAFsAawwAAAYAXQBqDAAABQBRAGwMAAAFAF8AbQwAAAQAXgDqDAAABQA+AG4MAAAEAEoAbwwAAAEAXQAAAA==.',
Gl='Glizzygary:BAEALgAFFAQJDQAAAQ==.',
Gr='Grimvalor:BAEBLgAECn9IAAMEAAkJ6xyvGQCQAgloDAAACwBcAGkMAAAKAEwAawwAAAsAUgBqDAAACQBYAGwMAAAJAFkAbQwAAAYASwDqDAAACwBSAG4MAAAEACoAbwwAAAEAMgAEAAkJ6xyvGQCQAgloDAAACgBcAGkMAAAKAEwAawwAAAoAUgBqDAAACABYAGwMAAAIAFkAbQwAAAYASwDqDAAACgBSAG4MAAAEACoAbwwAAAEAMgARAAUJzwpAOABeAAVoDAAAAQAPAGsMAAABACwAagwAAAEALABsDAAAAQAiAOoMAAABAA8AAAA=.Grunclaws:BAEALgAECgYJDAABLgAECgkJKwAEAAwbAA==.Grunsy:BAEALgAECgcJBQABLgAECgkJKwAEAAwbAA==.',
Ha='Haf:BAEBLgAECn8qAAIRAAkJ8hHCEQCIAQloDAAABwA9AGkMAAAGAEIAawwAAAYARwBqDAAABQAjAGwMAAAFADYAbQwAAAMAFQDqDAAABgAvAG4MAAACABYAbwwAAAIAFwARAAkJ8hHCEQCIAQloDAAABwA9AGkMAAAGAEIAawwAAAYARwBqDAAABQAjAGwMAAAFADYAbQwAAAMAFQDqDAAABgAvAG4MAAACABYAbwwAAAIAFwAAAA==.',
He='Hertzmuch:BAEALgADCgYJDgABLgAFFAQJEAADACAOAA==.',
Ho='Holeighfuk:BAEALgAECgYJBgAAAA==.',
Jo='Joicountdown:BAEBLgAFFH8qAAISAAgJ+CYGAACqAghoDAAABwBjAGkMAAAHAGQAawwAAAcAYgBqDAAABgBkAGwMAAADAGQAbQwAAAIAZADqDAAACQBkAG4MAAABAGQAEgAICfgmBgAAqgIIaAwAAAcAYwBpDAAABwBkAGsMAAAHAGIAagwAAAYAZABsDAAAAwBkAG0MAAACAGQA6gwAAAkAZABuDAAAAQBkAAEuAAQKBgkGAAgAAAAA.',
Ka='Kautheros:BAEBLgAECn8eAAQTAAkJ+Aw0DwDBAQloDAAABAAIAGkMAAAEABkAawwAAAQAOwBqDAAABAAfAGwMAAADACIAbQwAAAMACQDqDAAABQBDAG4MAAACAB0AbwwAAAEAHwATAAkJ+Aw0DwDBAQloDAAAAgAIAGkMAAACABkAawwAAAIAOwBqDAAAAgAfAGwMAAABACIAbQwAAAMACQDqDAAABABDAG4MAAACAB0AbwwAAAEAHwAUAAYJUgmKUQC+AAZoDAAAAQAdAGkMAAABABgAawwAAAIAHABqDAAAAQAkAGwMAAACABcA6gwAAAEADAAVAAMJmgaeHABSAANoDAAAAQAJAGkMAAABABgAagwAAAEAGgAAAA==.',
Ke='Kelo:BAEALgAECgkJAQABLgAECgkJKwAEAAwbAA==.',
Kr='Kroxychi:BAEALgAECgcJDgAAAA==.Kroxypurple:BAEALgADCgIJAgABLgAECgcJDgAIAAAAAA==.',
Ku='Kungfused:BAECLgAFFH8QAAIDAAQJIA6CJADnAARoDAAABQAqAGkMAAAFACUAawwAAAMAJgDqDAAAAwAaAAMABAkgDoIkAOcABGgMAAAFACoAaQwAAAUAJQBrDAAAAwAmAOoMAAADABoALgAECn9hAAMDAAkJlx3ACgClAgADAAkJlx3ACgClAgABAAkJmBTAEwABAgAAAA==.',
Le='Leenfiey:BAECLgAFFH8KAAMWAAMJXCPKHAAkAQNoDAAAAwBfAGkMAAADAFEA6gwAAAQAXQAWAAMJXCPKHAAkAQNoDAAAAgBfAGkMAAACAFEA6gwAAAIAXQABAAMJGA32IgCdAANoDAAAAQAAAGkMAAABADEA6gwAAAIAMgAuAAQKfxkAAxYABglMJd0UAGUCABYABgkrJd0UAGUCAAEAAQkdJR5lAGgAAAAA.Lennather:BAEBLgAECn87AAIBAAkJaCXNAQBNAwloDAAABwBjAGkMAAAHAGEAawwAAAYAWwBqDAAABgBOAGwMAAAIAGEAbQwAAAcAXgDqDAAACQBfAG4MAAAHAGMAbwwAAAIAWgABAAkJaCXNAQBNAwloDAAABwBjAGkMAAAHAGEAawwAAAYAWwBqDAAABgBOAGwMAAAIAGEAbQwAAAcAXgDqDAAACQBfAG4MAAAHAGMAbwwAAAIAWgAAAA==.',
Li='Lidomi:BAEALgAECgUJCQABLgAFFAQJCwATAP8PAA==.Lidrunka:BAEBLgAECn8WAAMBAAgJbhTVGwD9AQhoDAAABABKAGkMAAAEAD8AawwAAAMARABqDAAAAgAjAGwMAAACADYAbQwAAAEAHADqDAAABQA/AG4MAAABAAwAAQAICcoT1RsA/QEIaAwAAAMASgBpDAAAAwA0AGsMAAACAEQAagwAAAIAIwBsDAAAAgA2AG0MAAABABwA6gwAAAQAPwBuDAAAAQAMABYABAkWFOpDANUABGgMAAABACwAaQwAAAEAPwBrDAAAAQA7AOoMAAABACUAAS4ABRQECQsAEwD/DwA=.',
['Lé']='Lépewpew:BAEBLgAECn8YAAIXAAcJSRKfIwBqAQdoDAAABQA+AGkMAAAFADMAawwAAAUAOwBqDAAAAwBNAGwMAAABACYA6gwAAAQAOgBuDAAAAQAKABcABwlJEp8jAGoBB2gMAAAFAD4AaQwAAAUAMwBrDAAABQA7AGoMAAADAE0AbAwAAAEAJgDqDAAABAA6AG4MAAABAAoAAAA=.',
Ma='Mattimus:BAEBLgAECn8gAAMYAAYJyw/8XwBIAQZoDAAABgA9AGkMAAAGACUAawwAAAcAGgBqDAAABQA1AGwMAAADACYA6gwAAAUAJQAYAAYJyw/8XwBIAQZoDAAABgA9AGkMAAAFACUAawwAAAYAGgBqDAAABAA1AGwMAAADACYA6gwAAAQAJQAZAAQJ+QK2cAB8AARpDAAAAQABAGsMAAABAAkAagwAAAEACQDqDAAAAQAMAAAA.',
['Má']='Mákí:BAEBLgAECn8bAAQBAAgJXxSAKwCCAQhoDAAABABAAGkMAAAEADQAawwAAAQAJQBqDAAAAwA9AGwMAAADAEEAbQwAAAEAFgDqDAAABgBOAG4MAAACACwAAQAHCZUTgCsAggEHaAwAAAMAJQBpDAAAAwA0AGsMAAADACUAagwAAAEAMgBsDAAAAwBBAOoMAAADAD8AbgwAAAIALAAWAAUJghZeNgANAQVoDAAAAQBAAGkMAAABADIAawwAAAEAJQBqDAAAAQA9AOoMAAACAE4AAwADCfgODmkAkgADagwAAAEAKwBtDAAAAQAdAOoMAAABACkAAAA=.',
Na='Natebanger:BAEALgAECgYJDAABLgAFFAgJIwABAAkeAA==.',
Ne='Nethertank:BAEALgAECgYJBgABLgAECggJHwAGAJAWAA==.',
No='Noeyednuck:BAEALgAECgYJEAABLgAFFAMJBgAYAOoLAA==.',
Nu='Nuckshott:BAECLgAFFH8GAAIYAAMJ6gtgTQDaAANoDAAAAwAgAGkMAAACAB0A6gwAAAEAHAAYAAMJ6gtgTQDaAANoDAAAAwAgAGkMAAACAB0A6gwAAAEAHAAuAAQKfzIAAhgACQnWH/wSAJoCABgACQnWH/wSAJoCAAAA.',
Og='Ogx:BAEALgAECgQJCQABLgAECgkJKwAEAAwbAA==.',
Ol='Olgass:BAEALgADCgIJAgABLgAECgkJLwAaAK4gAA==.',
Pu='Purlok:BAEALgAECgkJAwABLgAECgkJKwAEAAwbAA==.',
Qu='Quindrox:BAEALgAFFAIJAwAAAA==.Quinet:BAEBLgAECn8vAAMaAAkJriCgDQDPAgloDAAABwBhAGkMAAAHAFwAawwAAAcAXABqDAAABgBRAGwMAAAFAFwAbQwAAAMAWADqDAAABwBeAG4MAAAEAEcAbwwAAAEAKAAaAAkJriCgDQDPAgloDAAABwBhAGkMAAAGAFwAawwAAAcAXABqDAAAAQAQAGwMAAADAFwAbQwAAAMAWADqDAAABwBeAG4MAAAEAEcAbwwAAAEAKAAbAAMJyh5xLwD9AANpDAAAAQBGAGoMAAAFAFEAbAwAAAIAVwAAAA==.Quinman:BAEBLgAECn8aAAQXAAkJRRoPEQASAgloDAAABQBBAGkMAAAEADMAawwAAAQATwBqDAAAAgAnAGwMAAACAGEAbQwAAAIAOwDqDAAABABBAG4MAAACAD0AbwwAAAEAOgAXAAkJixcPEQASAgloDAAAAQA8AGkMAAABAAAAawwAAAEATwBqDAAAAgAnAGwMAAACAGEAbQwAAAIAOwDqDAAAAwBBAG4MAAACAD0AbwwAAAEAOgAZAAQJWhWQWQDfAARoDAAAAwBBAGkMAAADADMAawwAAAMAMQDqDAAAAQA0ABgAAQkVGMP4AD4AAWgMAAABAD0AAS4ABRQCCQMACAAAAAA=.Quinmanbear:BAEALgAECgcJCQABLgAFFAIJAwAIAAAAAA==.Quinroxx:BAEBLgAECn8gAAIGAAgJXiN8KwDFAghoDAAABQBiAGkMAAAFAFsAawwAAAUAXwBqDAAABQBeAGwMAAADAFoAbQwAAAIAUwDqDAAABgBhAG4MAAABAE0ABgAICV4jfCsAxQIIaAwAAAUAYgBpDAAABQBbAGsMAAAFAF8AagwAAAUAXgBsDAAAAwBaAG0MAAACAFMA6gwAAAYAYQBuDAAAAQBNAAEuAAUUAgkDAAgAAAAA.Quinvinvin:BAEALgAECgcJDQABLgAFFAIJAwAIAAAAAA==.',
Ra='Ragsnak:BAEALgAECgkJBgABLgAECgkJKwAEAAwbAA==.',
Ro='Ronimus:BAEALgAECgEJAQAAAA==.',
Ru='Rufio:BAECLgAFFH8MAAIcAAMJJQwIFADMAANoDAAABgA2AGkMAAAEABMA6gwAAAIAEwAcAAMJJQwIFADMAANoDAAABgA2AGkMAAAEABMA6gwAAAIAEwAuAAQKfyMAAhwACAnXHPYLAKECABwACAnXHPYLAKECAAAA.',
Ry='Rytiou:BAECLgAFFH8VAAIUAAYJKxlXBQCuAQZoDAAABABSAGkMAAAFAFYAawwAAAQALgBqDAAAAwBHAOoMAAAEAFIAbgwAAAEAFwAUAAYJKxlXBQCuAQZoDAAABABSAGkMAAAFAFYAawwAAAQALgBqDAAAAwBHAOoMAAAEAFIAbgwAAAEAFwAuAAQKfzIAAhQACQnqJFkCAIwDABQACQnqJFkCAIwDAAAA.',
Sa='Saadxevok:BAEBLgAECn8YAAMVAAgJQRFLEADYAQhoDAAAAwA7AGkMAAADADEAawwAAAMARQBqDAAAAwAwAGwMAAAEAEgAbQwAAAMACADqDAAAAwAkAG4MAAACAAwAFQAICUERSxAA2AEIaAwAAAMAOwBpDAAAAwAxAGsMAAACAEUAagwAAAIAMABsDAAAAwBIAG0MAAABAAgA6gwAAAEAJABuDAAAAQAMABMABglTCD0pACkBBmsMAAABABAAagwAAAEAEQBsDAAAAQARAG0MAAACAB4A6gwAAAIAJwBuDAAAAQAGAAEuAAUUCAkjAAsAZB4A.Saadxm:BAEALgAECgcJDwABLgAFFAgJIwALAGQeAA==.Saadxp:BAECLgAFFH8jAAMLAAgJZB7JAABZAghoDAAABQBjAGkMAAAGAGAAawwAAAYAYABqDAAABgBYAGwMAAADACAAbQwAAAEAVADqDAAABwBeAG4MAAABACkACwAHCV0hyQAAWQIHaAwAAAQAYwBpDAAABQBgAGsMAAAFAGAAagwAAAUAWABtDAAAAQBUAOoMAAAFAF4AbgwAAAEAKQAdAAYJ5RnxAQANAgZoDAAAAQBJAGkMAAABAB0AawwAAAEAWgBqDAAAAQBOAGwMAAADADMA6gwAAAIASgAuAAQKfyUAAwsACAmRJrcDAGADAAsACAmRJrcDAGADAB0ABQkLHz4gAJEBAAAA.',
Se='Sendrys:BAEALgAECgEJAQABLgAECgkJLwACALsZAA==.',
Sg='Sgtgigachad:BAEALgADCgYJBgABLgAFFAQJDQAIAAAAAQ==.',
Sp='Spilt:BAECLgAFFH8kAAIGAAgJSRevAQCMAghoDAAABwBaAGkMAAAHAFQAawwAAAYAPwBqDAAABAAaAGwMAAACABAAbQwAAAIARgDqDAAABwBTAG4MAAABAAcABgAICUkXrwEAjAIIaAwAAAcAWgBpDAAABwBUAGsMAAAGAD8AagwAAAQAGgBsDAAAAgAQAG0MAAACAEYA6gwAAAcAUwBuDAAAAQAHAC4ABAp/HQACBgAJCckk4woAbQMABgAJCckk4woAbQMAAAA=.Spilthen:BAEALgAFFAQJBAABLgAFFAgJJAAGAEkXAA==.Spiltmonk:BAEBLgAECn8YAAIBAAYJWh80HAD6AQZoDAAABABGAGkMAAAEAFEAawwAAAQAUgBqDAAABABMAGwMAAADAFIA6gwAAAUAVAABAAYJWh80HAD6AQZoDAAABABGAGkMAAAEAFEAawwAAAQAUgBqDAAABABMAGwMAAADAFIA6gwAAAUAVAABLgAFFAgJJAAGAEkXAA==.',
Su='Sunjo:BAEALgAECgkJBwABLgAECgkJKwAEAAwbAA==.',
Ta='Taku:BAEALgAECgcJDQABLgAECgkJHgATAPgMAA==.Taymeean:BAEALgAECgMJBAABLgAFFAQJBwAUAEAJAA==.Tayvok:BAECLgAFFH8HAAIUAAQJQAnxLADwAARoDAAAAgAOAGkMAAADADAAawwAAAEAFgDqDAAAAQAJABQABAlACfEsAPAABGgMAAACAA4AaQwAAAMAMABrDAAAAQAWAOoMAAABAAkALgAECn8vAAIUAAkJkRw8DQBuAgAUAAkJkRw8DQBuAgAAAA==.',
Te='Tentickles:BAECLgAFFH8MAAILAAQJlx97DQBhAQRoDAAAAwBIAGkMAAADAFsAawwAAAIAYQDqDAAABAA9AAsABAmXH3sNAGEBBGgMAAADAEgAaQwAAAMAWwBrDAAAAgBhAOoMAAAEAD0ALgAECn8UAAILAAgJiCJyCAD9AgALAAgJiCJyCAD9AgABLgAFFAgJIwABAAkeAA==.Tetakoawara:BAEALgAECgUJCwABLgAFFAMJCgAWAFwjAA==.',
Th='Thecheatt:BAEBLgAECn86AAMOAAkJ8SOABQCnAgloDAAACQBjAGkMAAAJAGEAawwAAAoAYwBqDAAACABhAGwMAAAIAF0AbQwAAAIAWgDqDAAACABfAG4MAAACAEcAbwwAAAIAWQAOAAkJ3iOABQCnAgloDAAABwBhAGkMAAAGAGEAawwAAAgAYwBqDAAABgBhAGwMAAAFAF0AbQwAAAIAWgDqDAAABABfAG4MAAACAEcAbwwAAAIAWQANAAYJCB7qSQB9AQZoDAAAAgBjAGkMAAADAFEAawwAAAIANgBqDAAAAgAyAGwMAAADAE8A6gwAAAQARQAAAA==.Therelore:BAEALgADCgIJAgABLgAECgkJFAAPALgRAA==.',
Ty='Tyära:BAEBLgAECn8dAAMPAAgJTAu1ngASAQhoDAAABgAYAGkMAAAGACQAawwAAAUAPgBqDAAAAwAXAGwMAAACAB4AbQwAAAEADQDqDAAABQAUAG4MAAABAA4ADwAHCUEJtZ4AEgEHaAwAAAUAEgBpDAAABQAZAGsMAAAEACYAagwAAAIAEwBsDAAAAQAeAOoMAAAEAA0AbgwAAAEADgAeAAcJtgo/LADXAAdoDAAAAQAYAGkMAAABACQAawwAAAEAPgBqDAAAAQAXAGwMAAABAAcAbQwAAAEADQDqDAAAAQAUAAEuAAUUAwkFAAYAZwYA.',
Vi='Vigiz:BAEALgAECggJCAAAAA==.Vilexie:BAEALgAECggJEgAAAA==.',
['Vì']='Vìgïz:BAEALgAECgEJAQABLgAECggJCAAIAAAAAA==.',
Wa='Wafflé:BAEALgAECgIJAgAAAA==.',
Wh='Whitecrosses:BAEALgAECgEJAQABLgAECgcJGAAXAEkSAA==.',
Wi='Wiskystagger:BAEALgADCgEJAgAAAA==.',
Za='Zanea:BAEALgADCgkJEgABLgAECgkJLwACALsZAA==.Zargan:BAEALgAECgcJCAABLgAECgkJHgATAPgMAA==.',
Ze='Zertzz:BAEALgAFFAEJAQABLgAFFAUJGgALACIgAA==.',
Zi='Zibbz:BAECLgAFFH8GAAIUAAMJ7hioLwDiAANoDAAAAgBGAGkMAAACADQA6gwAAAIARAAUAAMJ7hioLwDiAANoDAAAAgBGAGkMAAACADQA6gwAAAIARAAuAAQKfzwAAxQACQmCJboBAFoDABQACQmCJboBAFoDABUABwnLGosGAMgBAAAA.Zinia:BAEBLgAECn8vAAICAAkJuxnvBQBdAgloDAAACABXAGkMAAAIAFIAawwAAAgAOQBqDAAABQA6AGwMAAAFAE8AbQwAAAIAMQDqDAAABwBCAG4MAAADACsAbwwAAAEAPAACAAkJuxnvBQBdAgloDAAACABXAGkMAAAIAFIAawwAAAgAOQBqDAAABQA6AGwMAAAFAE8AbQwAAAIAMQDqDAAABwBCAG4MAAADACsAbwwAAAEAPAAAAA==.',
Zu='Zubbfist:BAEALgADCgcJBwABLgAFFAMJBgAUAO4YAA==.Zubbrael:BAEBLgAECn8qAAMLAAgJpRpnHAC8AQhoDAAACQBUAGkMAAAHAEMAawwAAAYARQBqDAAABQBDAGwMAAAFADoAbQwAAAEAUgDqDAAACABHAG4MAAABACoACwAHCbYZZxwAvAEHaAwAAAcAVABpDAAABQBDAGsMAAAEAEUAagwAAAMAQwBsDAAAAwA6AOoMAAAGAEcAbgwAAAEAKgAdAAcJgwmQMAAtAQdoDAAAAgAOAGkMAAACABUAawwAAAIAIwBqDAAAAgArAGwMAAACABIAbQwAAAEAEgDqDAAAAgATAAEuAAUUAwkGABQA7hgA.Zubbz:BAECLgAFFH8FAAMcAAQJtxGXCwArAQRoDAAAAgAmAGkMAAABAD0AawwAAAEAGADqDAAAAQA4ABwABAm3EZcLACsBBGgMAAABACYAaQwAAAEAPQBrDAAAAQAYAOoMAAABADgAHwABCU8Ix4cAPAABaAwAAAEAFQAuAAQKfzQAAx8ACAkuH5MeAJoCAB8ACAksHpMeAJoCABwABwmWHhEPAA0CAAEuAAUUAwkGABQA7hgA.',
Zz='Zzertz:BAECLgAFFH8aAAILAAUJIiA+DABvAQVoDAAABwBhAGkMAAAGAFMAawwAAAUAVABqDAAAAgBaAOoMAAAGAEAACwAFCSIgPgwAbwEFaAwAAAcAYQBpDAAABgBTAGsMAAAFAFQAagwAAAIAWgDqDAAABgBAAC4ABAp/KwACCwAICf8iOgYAKQMACwAICf8iOgYAKQMAAAA=.',
['Àb']='Àbeel:BAEALgAECgUJBgABLgAECggJOwAKAAYeAA==.Àbel:BAEBLgAECn87AAMKAAgJBh5jBgASAghoDAAACgBXAGkMAAALAFQAawwAAAgAWgBqDAAABwBeAGwMAAAFAD0AbQwAAAIAIwDqDAAADABZAG4MAAAEAFkACgAHCSseYwYAEgIHaAwAAAgAVwBpDAAACQBUAGsMAAAFAFoAagwAAAUAXgBsDAAABQA9AOoMAAAJAFkAbgwAAAIAMgAJAAcJfRuLHQCIAQdoDAAAAgBJAGkMAAACAE8AawwAAAMATgBqDAAAAgBdAG0MAAACACMA6gwAAAMAQQBuDAAAAgBZAAAA.Àble:BAEALgAECgYJCwABLgAECggJOwAKAAYeAA==.',
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
