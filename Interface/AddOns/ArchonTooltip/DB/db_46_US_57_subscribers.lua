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

local lookup = {'Monk-Windwalker','Shaman-Enhancement','Monk-Mistweaver','Paladin-Retribution','Paladin-Holy','Mage-Frost','Unknown-Unknown','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','Warrior-Arms','Warrior-Fury','Warrior-Protection','DeathKnight-Unholy','Mage-Arcane','Paladin-Protection','Druid-Feral','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Monk-Brewmaster','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Warlock-Demonology','Warlock-Destruction','DemonHunter-Havoc','Priest-Discipline','DeathKnight-Blood','DemonHunter-Devourer',}
local provider = {region='US',realm='Dalaran',name='US',type='subscribers',zone=46,date='2026-06-06',data={Ad='Adansso:BAEBLgAECn80AAIBAAkJFxJ8HAC9AQloDAAACQArAGkMAAAIADoAawwAAAcAQwBqDAAABQA0AGwMAAAGADEAbQwAAAMAHADqDAAACAA7AG4MAAAFACUAbwwAAAEAGgABAAkJFxJ8HAC9AQloDAAACQArAGkMAAAIADoAawwAAAcAQwBqDAAABQA0AGwMAAAGADEAbQwAAAMAHADqDAAACAA7AG4MAAAFACUAbwwAAAEAGgAAAA==.',
Al='Aliastei:BAEALgADCggJDAABLgAECgkJLwACALsZAA==.',
Ap='Apawcowlypse:BAEALgADCgcJDAABLgAFFAUJFQADAMcPAA==.',
As='Ashko:BAEBLgAECn8uAAMEAAgJDBsLNwAaAghoDAAACQBLAGkMAAAIAFcAawwAAAcAUQBqDAAABgBSAGwMAAAFAFEAbQwAAAMAKwDqDAAABgBHAG4MAAACACkABAAICQwbCzcAGgIIaAwAAAkASwBpDAAACABXAGsMAAAGAFEAagwAAAYAUgBsDAAABQBRAG0MAAADACsA6gwAAAUARwBuDAAAAgApAAUAAgkHDRNzAF8AAmsMAAABACcA6gwAAAEAGwAAAA==.',
Ay='Ayodele:BAEBLgAECn84AAIGAAkJtBsgHACsAgloDAAACQBSAGkMAAAHAEcAawwAAAUAQwBqDAAACABWAGwMAAAGAEkAbQwAAAQAPwDqDAAACABTAG4MAAAGAFYAbwwAAAMAJwAGAAkJtBsgHACsAgloDAAACQBSAGkMAAAHAEcAawwAAAUAQwBqDAAACABWAGwMAAAGAEkAbQwAAAQAPwDqDAAACABTAG4MAAAGAFYAbwwAAAMAJwAAAA==.',
Az='Azurlia:BAEALgAFFAEJAQAAAA==.',
Ba='Babycora:BAEALgAFFAMJAwAAAA==.Bagelandlox:BAEALgADCgEJAQABLgAECgYJDAAHAAAAAA==.Barrui:BAECLgAFFH8pAAMIAAgJtByyBQAzAghoDAAABwBfAGkMAAAIAGAAawwAAAcAWQBqDAAABwBgAGwMAAABAAQAbQwAAAEAJADqDAAACQBdAG4MAAABAGEACAAHCUogsgUAMwIHaAwAAAcAXwBpDAAABwBSAGsMAAAGAFkAagwAAAcAYABtDAAAAQAkAOoMAAAJAF0AbgwAAAEAYQAJAAMJWRBwAgAVAQNpDAAAAQBgAGsMAAABABgAbAwAAAEABAAuAAQKfzkAAwgACQlwJOkFADMDAAgACQnxIukFADMDAAkABgkfIS8EAHACAAAA.',
Be='Belynila:BAECLgAFFH8OAAIKAAMJOiALFwAcAQNoDAAABwBVAGkMAAAFAD4A6gwAAAIAYwAKAAMJOiALFwAcAQNoDAAABwBVAGkMAAAFAD4A6gwAAAIAYwAuAAQKf0AAAgoACQmgIasEAAkDAAoACQmgIasEAAkDAAAA.Bestiavera:BAEBLgAECn89AAILAAgJExYuEQDWAQhoDAAACgBFAGkMAAAJAE4AawwAAAkAOgBqDAAACAA8AGwMAAAIACUAbQwAAAQAOQDqDAAACAA+AG4MAAAFACAACwAICRMWLhEA1gEIaAwAAAoARQBpDAAACQBOAGsMAAAJADoAagwAAAgAPABsDAAACAAlAG0MAAAEADkA6gwAAAgAPgBuDAAABQAgAAAA.',
Br='Briggoker:BAEALgAECgQJBwAAAA==.Brigmahf:BAEALgAECgQJCQABLgAECgQJBwAHAAAAAA==.',
Ca='Carbonarra:BAEBLgAECn80AAIMAAgJsho8HAAFAghoDAAACgBbAGkMAAAJAEcAawwAAAkAUgBqDAAABwBYAGwMAAAHAEgAbQwAAAEAKwDqDAAABwBDAG4MAAACADEADAAICbIaPBwABQIIaAwAAAoAWwBpDAAACQBHAGsMAAAJAFIAagwAAAcAWABsDAAABwBIAG0MAAABACsA6gwAAAcAQwBuDAAAAgAxAAAA.Catcam:BAEALgAECgYJBgAAAA==.',
Ch='Chetegos:BAEALgADCgYJBgABLgAECgkJOgANAPEjAA==.Chíefsquirel:BAEALgAECgYJDAAAAA==.',
Da='Dadbanger:BAECLgAFFH8mAAMBAAkJ5x44AABxAgloDAAABgBiAGkMAAAGAGAAawwAAAUASgBqDAAABwBfAGwMAAAEAEQAbQwAAAEAJQDqDAAABwBhAG4MAAABAEEAbwwAAAEAXgABAAgJhR84AABxAghoDAAABgBiAGkMAAAGAGAAawwAAAUASgBqDAAABwBfAG0MAAABACUA6gwAAAcAYQBuDAAAAQBBAG8MAAABAF4AAwABCSAKwlIAQgABbAwAAAQAGQAuAAQKfyoAAgEACAlxJgkCAIQDAAEACAlxJgkCAIQDAAAA.Daeke:BAEALgADCgUJBQABLgAECgQJBwAHAAAAAA==.Daekeypoo:BAEALgAECgQJBwAAAA==.Darkvirgo:BAEBLgAFFH8NAAIGAAQJSghpbQD7AARoDAAABAAiAGkMAAAEABkAawwAAAEAAgDqDAAABAAVAAYABAlKCGltAPsABGgMAAAEACIAaQwAAAQAGQBrDAAAAQACAOoMAAAEABUAAS4ABRQICSUACgCkGQA=.',
De='Deathbeaver:BAEALgAECgYJCwABLgAECgkJTwAEAOscAA==.Destrom:BAEBLgAECn8UAAIOAAkJuBFkeQBoAQloDAAAAwAwAGkMAAADADAAawwAAAMASABqDAAAAgA2AGwMAAABAB4AbQwAAAEAKADqDAAAAwAXAG4MAAACAC0AbwwAAAIANQAOAAkJuBFkeQBoAQloDAAAAwAwAGkMAAADADAAawwAAAMASABqDAAAAgA2AGwMAAABAB4AbQwAAAEAKADqDAAAAwAXAG4MAAACAC0AbwwAAAIANQAAAA==.',
Ep='Epilepticc:BAECLgAFFH8PAAIEAAQJSB6XLwBAAQRoDAAABQBCAGkMAAAEAFUAawwAAAMAUADqDAAAAwBNAAQABAlIHpcvAEABBGgMAAAFAEIAaQwAAAQAVQBrDAAAAwBQAOoMAAADAE0ALgAECn88AAIEAAkJ6yKXFwCsAgAEAAkJ6yKXFwCsAgAAAA==.',
Et='Ethalon:BAECLgAFFH8PAAMFAAQJlRNKHwAYAQRoDAAABQBOAGkMAAAEAC0AawwAAAIADwDqDAAABAA9AAUABAmVE0ofABgBBGgMAAAEAE4AaQwAAAQALQBrDAAAAgAPAOoMAAAEAD0ABAABCbcCBbYAOQABaAwAAAEABgAuAAQKfyUAAwUACQkdGicYAFECAAUACQkdGicYAFECAAQAAgnJFOZlAUEAAAAA.',
Fa='Fallhp:BAEALgADCgYJBgABLgAFFAgJFgAFALwUAA==.Fallill:BAEALgAECgIJAgABLgAFFAgJFgAFALwUAA==.Falosso:BAECLgAFFH8WAAIFAAgJvBSjBQBUAghoDAAAAwA1AGkMAAADAEcAawwAAAMAQABqDAAAAwBLAGwMAAADAA0AbQwAAAEAHwDqDAAABQBQAG4MAAABACIABQAICbwUowUAVAIIaAwAAAMANQBpDAAAAwBHAGsMAAADAEAAagwAAAMASwBsDAAAAwANAG0MAAABAB8A6gwAAAUAUABuDAAAAQAiAC4ABAp/MwADBQAJCY8geAwAvgIABQAJCY8geAwAvgIABAACCRMO/DwBYAAAAAA=.',
Ga='Garlooth:BAECLgAFFH8HAAIPAAMJKRTXAQDkAANoDAAABAAzAGkMAAACAE4A6gwAAAEAGAAPAAMJKRTXAQDkAANoDAAABAAzAGkMAAACAE4A6gwAAAEAGAAuAAQKfy0AAg8ACQm9IoUAAAUDAA8ACQm9IoUAAAUDAAAA.',
Gl='Glizzygary:BAEALgAFFAUJEgAAAQ==.',
Gr='Grimvalor:BAEBLgAECn9PAAMEAAkJ6xxXHwCBAgloDAAACwBcAGkMAAAKAEwAawwAAAsAUgBqDAAACQBYAGwMAAAKAFkAbQwAAAcASwDqDAAADABSAG4MAAAGACoAbwwAAAMAMgAEAAkJ6xxXHwCBAgloDAAACgBcAGkMAAAKAEwAawwAAAoAUgBqDAAACABYAGwMAAAJAFkAbQwAAAcASwDqDAAACwBSAG4MAAAGACoAbwwAAAMAMgAQAAUJzwoTPQBdAAVoDAAAAQAPAGsMAAABACwAagwAAAEALABsDAAAAQAiAOoMAAABAA8AAAA=.Grunclaws:BAEALgAECgcJEgABLgAECgkJLgAEAAwbAA==.Grunsy:BAEALgAECgcJBQABLgAECgkJLgAEAAwbAA==.',
Ha='Haf:BAEBLgAECn8qAAIQAAkJ8hHFEwCDAQloDAAABwA9AGkMAAAGAEIAawwAAAYARwBqDAAABQAjAGwMAAAFADYAbQwAAAMAFQDqDAAABgAvAG4MAAACABYAbwwAAAIAFwAQAAkJ8hHFEwCDAQloDAAABwA9AGkMAAAGAEIAawwAAAYARwBqDAAABQAjAGwMAAAFADYAbQwAAAMAFQDqDAAABgAvAG4MAAACABYAbwwAAAIAFwAAAA==.',
He='Hertzmuch:BAEALgADCgYJDgABLgAFFAUJFQADAMcPAA==.',
Ho='Holeighfuk:BAEALgAECgYJBgAAAA==.',
Jo='Joicountdown:BAEBLgAFFH8rAAIRAAkJ2SUNAAA2AwloDAAABwBjAGkMAAAHAGQAawwAAAcAYgBqDAAABgBkAGwMAAADAGQAbQwAAAIAZADqDAAACQBkAG4MAAABAGQAbwwAAAEATAARAAkJ2SUNAAA2AwloDAAABwBjAGkMAAAHAGQAawwAAAcAYgBqDAAABgBkAGwMAAADAGQAbQwAAAIAZADqDAAACQBkAG4MAAABAGQAbwwAAAEATAABLgAECgYJBgAHAAAAAA==.',
Ka='Kautheros:BAEBLgAECn8eAAQSAAkJ+AyVEAC5AQloDAAABAAIAGkMAAAEABkAawwAAAQAOwBqDAAABAAfAGwMAAADACIAbQwAAAMACQDqDAAABQBDAG4MAAACAB0AbwwAAAEAHwASAAkJ+AyVEAC5AQloDAAAAgAIAGkMAAACABkAawwAAAIAOwBqDAAAAgAfAGwMAAABACIAbQwAAAMACQDqDAAABABDAG4MAAACAB0AbwwAAAEAHwATAAYJUglDVwDIAAZoDAAAAQAdAGkMAAABABgAawwAAAIAHABqDAAAAQAkAGwMAAACABcA6gwAAAEADAAUAAMJmgYhHwBOAANoDAAAAQAJAGkMAAABABgAagwAAAEAGgAAAA==.',
Ke='Kelo:BAEALgAECgkJAQABLgAECgkJLgAEAAwbAA==.',
Kr='Kroxychi:BAEALgAECgcJDgAAAA==.Kroxypurple:BAEALgADCgIJAgABLgAECgcJDgAHAAAAAA==.',
Ku='Kungfused:BAECLgAFFH8VAAIDAAUJxw9wIwAjAQVoDAAABgAqAGkMAAAGADoAawwAAAQALwBqDAAAAQAaAOoMAAAEABoAAwAFCccPcCMAIwEFaAwAAAYAKgBpDAAABgA6AGsMAAAEAC8AagwAAAEAGgDqDAAABAAaAC4ABAp/awAEAwAJCRYewAoApQIAAwAJCRYewAoApQIAAQAJCZgUORYA+AEAFQAECf8IC1cApAAAAAA=.',
Le='Leenfiey:BAECLgAFFH8KAAMVAAMJXCNLIQAbAQNoDAAAAwBfAGkMAAADAFEA6gwAAAQAXQAVAAMJXCNLIQAbAQNoDAAAAgBfAGkMAAACAFEA6gwAAAIAXQABAAMJGA2kKQCWAANoDAAAAQAAAGkMAAABADEA6gwAAAIAMgAuAAQKfxkAAxUABglMJd0UAGUCABUABgkrJd0UAGUCAAEAAQkdJU1uAGYAAAAA.Lennather:BAEBLgAECn9DAAIBAAkJtCUvAQBpAwloDAAACABjAGkMAAAIAGEAawwAAAcAYABqDAAABwBOAGwMAAAJAGEAbQwAAAgAXgDqDAAACgBfAG4MAAAIAGMAbwwAAAIAWgABAAkJtCUvAQBpAwloDAAACABjAGkMAAAIAGEAawwAAAcAYABqDAAABwBOAGwMAAAJAGEAbQwAAAgAXgDqDAAACgBfAG4MAAAIAGMAbwwAAAIAWgAAAA==.',
Li='Lidomi:BAEALgAECgUJCwABLgAFFAQJCwASAP8PAA==.Lidrunka:BAEBLgAECn8YAAMBAAgJdBXVGwD9AQhoDAAABABKAGkMAAAEAD8AawwAAAMARABqDAAAAgAjAGwMAAACADYAbQwAAAEAHADqDAAABwBSAG4MAAABAAwAAQAICdAU1RsA/QEIaAwAAAMASgBpDAAAAwA0AGsMAAACAEQAagwAAAIAIwBsDAAAAgA2AG0MAAABABwA6gwAAAYAUgBuDAAAAQAMABUABAkWFGpIANMABGgMAAABACwAaQwAAAEAPwBrDAAAAQA7AOoMAAABACUAAS4ABRQECQsAEgD/DwA=.',
['Lé']='Lépewpew:BAEBLgAECn8YAAIWAAcJSRJIJgBnAQdoDAAABQA+AGkMAAAFADMAawwAAAUAOwBqDAAAAwBNAGwMAAABACYA6gwAAAQAOgBuDAAAAQAKABYABwlJEkgmAGcBB2gMAAAFAD4AaQwAAAUAMwBrDAAABQA7AGoMAAADAE0AbAwAAAEAJgDqDAAABAA6AG4MAAABAAoAAAA=.',
Ma='Mattimus:BAEBLgAECn8iAAMXAAcJjw7WcwBMAQdoDAAABgA9AGkMAAAGACUAawwAAAcAGgBqDAAABQA1AGwMAAADACYA6gwAAAYAJQBuDAAAAQAVABcABwmPDtZzAEwBB2gMAAAGAD0AaQwAAAUAJQBrDAAABgAaAGoMAAAEADUAbAwAAAMAJgDqDAAABQAlAG4MAAABABUAGAAECfkCtnAAfAAEaQwAAAEAAQBrDAAAAQAJAGoMAAABAAkA6gwAAAEADAAAAA==.',
['Má']='Mákí:BAEBLgAECn8hAAQBAAkJThUWIQCaAQloDAAABQBIAGkMAAAEADQAawwAAAUALwBqDAAABABIAGwMAAADAEEAbQwAAAEAFgDqDAAABwBQAG4MAAADADUAbwwAAAEAKgABAAgJHRcWIQCaAQhoDAAABABIAGkMAAADADQAawwAAAQALwBqDAAAAgBIAGwMAAADAEEA6gwAAAQAUABuDAAAAwA1AG8MAAABACoAFQAFCYIW/zkADAEFaAwAAAEAQABpDAAAAQAyAGsMAAABACUAagwAAAEAPQDqDAAAAgBOAAMAAwn4DmF5AJEAA2oMAAABACsAbQwAAAEAHQDqDAAAAQApAAAA.',
Na='Natebanger:BAEALgAECgYJDAABLgAFFAkJJgABAOceAA==.',
Ne='Nethertank:BAEALgAECgYJBgABLgAECggJHwAGAJAWAA==.',
No='Noeyednuck:BAEALgAECgYJEAABLgAFFAMJCwAXAKgMAA==.',
Nu='Nuckshott:BAECLgAFFH8LAAIXAAMJqAwKWgDdAANoDAAABQAmAGkMAAADAB0A6gwAAAMAHAAXAAMJqAwKWgDdAANoDAAABQAmAGkMAAADAB0A6gwAAAMAHAAuAAQKfzQAAhcACQnWHzAXAJACABcACQnWHzAXAJACAAAA.',
Og='Ogx:BAEALgAECgQJDAABLgAECgkJLgAEAAwbAA==.',
Ol='Olgass:BAEALgADCgIJAgABLgAECgkJMQAZAK4gAA==.',
Pu='Purlok:BAEALgAECgkJAwABLgAECgkJLgAEAAwbAA==.',
Qu='Quindrox:BAEBLgAECn8aAAITAAkJRSFFBQAHAwloDAAAAgBdAGkMAAACAFMAawwAAAMAVgBqDAAAAwBTAGwMAAADAFoAbQwAAAMATADqDAAABABQAG4MAAADAFoAbwwAAAMATwATAAkJRSFFBQAHAwloDAAAAgBdAGkMAAACAFMAawwAAAMAVgBqDAAAAwBTAGwMAAADAFoAbQwAAAMATADqDAAABABQAG4MAAADAFoAbwwAAAMATwABLgAFFAMJAwAHAAAAAA==.Quinet:BAEBLgAECn8xAAMZAAkJriD2DwDHAgloDAAABwBhAGkMAAAHAFwAawwAAAcAXABqDAAABwBRAGwMAAAGAFwAbQwAAAMAWADqDAAABwBeAG4MAAAEAEcAbwwAAAEAKAAZAAkJriD2DwDHAgloDAAABwBhAGkMAAAGAFwAawwAAAcAXABqDAAAAQAQAGwMAAAEAFwAbQwAAAMAWADqDAAABwBeAG4MAAAEAEcAbwwAAAEAKAAaAAMJyh5xLwD9AANpDAAAAQBGAGoMAAAGAFEAbAwAAAIAVwAAAA==.Quinman:BAEBLgAECn8aAAQWAAkJRRr0EgAMAgloDAAABQBBAGkMAAAEADMAawwAAAQATwBqDAAAAgAnAGwMAAACAGEAbQwAAAIAOwDqDAAABABBAG4MAAACAD0AbwwAAAEAOgAWAAkJixf0EgAMAgloDAAAAQA8AGkMAAABAAAAawwAAAEATwBqDAAAAgAnAGwMAAACAGEAbQwAAAIAOwDqDAAAAwBBAG4MAAACAD0AbwwAAAEAOgAYAAQJWhWQWQDfAARoDAAAAwBBAGkMAAADADMAawwAAAMAMQDqDAAAAQA0ABcAAQkVGMcSATwAAWgMAAABAD0AAS4ABRQDCQMABwAAAAA=.Quinmanbear:BAEALgAFFAMJAwAAAA==.Quinroxx:BAEBLgAECn8gAAIGAAgJXiN8KwDFAghoDAAABQBiAGkMAAAFAFsAawwAAAUAXwBqDAAABQBeAGwMAAADAFoAbQwAAAIAUwDqDAAABgBhAG4MAAABAE0ABgAICV4jfCsAxQIIaAwAAAUAYgBpDAAABQBbAGsMAAAFAF8AagwAAAUAXgBsDAAAAwBaAG0MAAACAFMA6gwAAAYAYQBuDAAAAQBNAAEuAAUUAwkDAAcAAAAA.Quinvinvin:BAEALgAECgcJDQABLgAFFAMJAwAHAAAAAA==.',
Ra='Ragsnak:BAEALgAECgkJDQABLgAECgkJLgAEAAwbAA==.',
Ro='Ronimus:BAEALgAECgEJAQAAAA==.',
Ru='Rufio:BAECLgAFFH8NAAIbAAMJJQwcGQC7AANoDAAABgA2AGkMAAAEABMA6gwAAAMAEwAbAAMJJQwcGQC7AANoDAAABgA2AGkMAAAEABMA6gwAAAMAEwAuAAQKfywAAhsACQldHNMIAJECABsACQldHNMIAJECAAAA.',
Ry='Rytiou:BAECLgAFFH8YAAITAAcJbRhXBQCuAQdoDAAABABSAGkMAAAFAFYAawwAAAQALgBqDAAABABJAGwMAAABADUA6gwAAAUAUgBuDAAAAQAXABMABwltGFcFAK4BB2gMAAAEAFIAaQwAAAUAVgBrDAAABAAuAGoMAAAEAEkAbAwAAAEANQDqDAAABQBSAG4MAAABABcALgAECn8yAAITAAkJ6iRZAgCMAwATAAkJ6iRZAgCMAwAAAA==.',
Sa='Saadxevok:BAEBLgAECn8YAAMUAAgJQRFLEADYAQhoDAAAAwA7AGkMAAADADEAawwAAAMARQBqDAAAAwAwAGwMAAAEAEgAbQwAAAMACADqDAAAAwAkAG4MAAACAAwAFAAICUERSxAA2AEIaAwAAAMAOwBpDAAAAwAxAGsMAAACAEUAagwAAAIAMABsDAAAAwBIAG0MAAABAAgA6gwAAAEAJABuDAAAAQAMABIABglTCD0pACkBBmsMAAABABAAagwAAAEAEQBsDAAAAQARAG0MAAACAB4A6gwAAAIAJwBuDAAAAQAGAAEuAAUUCAkjAAoAZB4A.Saadxm:BAEALgAECgcJDwABLgAFFAgJIwAKAGQeAA==.Saadxp:BAECLgAFFH8jAAMKAAgJZB7JAABZAghoDAAABQBjAGkMAAAGAGAAawwAAAYAYABqDAAABgBYAGwMAAADACAAbQwAAAEAVADqDAAABwBeAG4MAAABACkACgAHCV0hyQAAWQIHaAwAAAQAYwBpDAAABQBgAGsMAAAFAGAAagwAAAUAWABtDAAAAQBUAOoMAAAFAF4AbgwAAAEAKQAcAAYJ5RnxAQANAgZoDAAAAQBJAGkMAAABAB0AawwAAAEAWgBqDAAAAQBOAGwMAAADADMA6gwAAAIASgAuAAQKfyUAAwoACAmRJrcDAGADAAoACAmRJrcDAGADABwABQkLHz4gAJEBAAAA.',
Se='Sendrys:BAEALgAECgEJAQABLgAECgkJLwACALsZAA==.',
Sg='Sgtgigachad:BAEALgADCgYJBgABLgAFFAUJEgAHAAAAAQ==.',
Sp='Spilt:BAECLgAFFH8tAAIGAAkJRhivAQCMAgloDAAACABaAGkMAAAIAFQAawwAAAYAPwBqDAAABgA0AGwMAAADADsAbQwAAAMARgDqDAAACABTAG4MAAACACgAbwwAAAEABAAGAAkJRhivAQCMAgloDAAACABaAGkMAAAIAFQAawwAAAYAPwBqDAAABgA0AGwMAAADADsAbQwAAAMARgDqDAAACABTAG4MAAACACgAbwwAAAEABAAuAAQKfx0AAgYACQnJJOMKAG0DAAYACQnJJOMKAG0DAAAA.Spilthen:BAEALgAFFAQJBAABLgAFFAkJLQAGAEYYAA==.Spiltmonk:BAEBLgAECn8YAAIBAAYJWh80HAD6AQZoDAAABABGAGkMAAAEAFEAawwAAAQAUgBqDAAABABMAGwMAAADAFIA6gwAAAUAVAABAAYJWh80HAD6AQZoDAAABABGAGkMAAAEAFEAawwAAAQAUgBqDAAABABMAGwMAAADAFIA6gwAAAUAVAABLgAFFAkJLQAGAEYYAA==.',
Su='Sunjo:BAEALgAECgkJBwABLgAECgkJLgAEAAwbAA==.',
Ta='Taku:BAEALgAECgcJDQABLgAECgkJHgASAPgMAA==.Taymeean:BAEALgAECgMJBAABLgAFFAQJBwATAEAJAA==.Tayvok:BAECLgAFFH8HAAITAAQJQAk0NQDkAARoDAAAAgAOAGkMAAADADAAawwAAAEAFgDqDAAAAQAJABMABAlACTQ1AOQABGgMAAACAA4AaQwAAAMAMABrDAAAAQAWAOoMAAABAAkALgAECn8vAAITAAkJkRzLDgBwAgATAAkJkRzLDgBwAgAAAA==.',
Te='Tentickles:BAECLgAFFH8MAAIKAAQJlx9uEQBJAQRoDAAAAwBIAGkMAAADAFsAawwAAAIAYQDqDAAABAA9AAoABAmXH24RAEkBBGgMAAADAEgAaQwAAAMAWwBrDAAAAgBhAOoMAAAEAD0ALgAECn8UAAIKAAgJiCJyCAD9AgAKAAgJiCJyCAD9AgABLgAFFAkJJgABAOceAA==.Tetakoawara:BAEALgAECgUJCwABLgAFFAMJCgAVAFwjAA==.',
Th='Thecheatt:BAEBLgAECn86AAMNAAkJ8SOOBgCYAgloDAAACQBjAGkMAAAJAGEAawwAAAoAYwBqDAAACABhAGwMAAAIAF0AbQwAAAIAWgDqDAAACABfAG4MAAACAEcAbwwAAAIAWQANAAkJ3iOOBgCYAgloDAAABwBhAGkMAAAGAGEAawwAAAgAYwBqDAAABgBhAGwMAAAFAF0AbQwAAAIAWgDqDAAABABfAG4MAAACAEcAbwwAAAIAWQAMAAYJCB7qSQB9AQZoDAAAAgBjAGkMAAADAFEAawwAAAIANgBqDAAAAgAyAGwMAAADAE8A6gwAAAQARQAAAA==.Therelore:BAEALgAECgQJBAABLgAECgkJFAAOALgRAA==.',
Ty='Tyära:BAEBLgAECn8dAAMOAAgJTAvnrAAPAQhoDAAABgAYAGkMAAAGACQAawwAAAUAPgBqDAAAAwAXAGwMAAACAB4AbQwAAAEADQDqDAAABQAUAG4MAAABAA4ADgAHCUEJ56wADwEHaAwAAAUAEgBpDAAABQAZAGsMAAAEACYAagwAAAIAEwBsDAAAAQAeAOoMAAAEAA0AbgwAAAEADgAdAAcJtgpSMADUAAdoDAAAAQAYAGkMAAABACQAawwAAAEAPgBqDAAAAQAXAGwMAAABAAcAbQwAAAEADQDqDAAAAQAUAAEuAAUUAwkKAAYADQoA.',
Vi='Vilexie:BAEALgAECggJEwAAAA==.',
Wa='Wafflé:BAEALgAECgIJAgAAAA==.',
Wh='Whitecrosses:BAEALgAECgEJAQABLgAECgcJGAAWAEkSAA==.',
Wi='Wiskystagger:BAEALgADCgEJAgAAAA==.',
Za='Zanea:BAEALgADCgkJEgABLgAECgkJLwACALsZAA==.Zargan:BAEALgAECgcJCAABLgAECgkJHgASAPgMAA==.',
Ze='Zertzz:BAEALgAFFAEJAQABLgAFFAYJIAAKANUfAA==.',
Zi='Zibbz:BAECLgAFFH8KAAITAAQJIx79HABZAQRoDAAAAwBHAGkMAAADAFAAawwAAAEAVwDqDAAAAwBEABMABAkjHv0cAFkBBGgMAAADAEcAaQwAAAMAUABrDAAAAQBXAOoMAAADAEQALgAECn8/AAMTAAkJgiX5AQBgAwATAAkJgiX5AQBgAwAUAAcJyxokBwDCAQAAAA==.Zinia:BAEBLgAECn8vAAICAAkJuxkGBwBVAgloDAAACABXAGkMAAAIAFIAawwAAAgAOQBqDAAABQA6AGwMAAAFAE8AbQwAAAIAMQDqDAAABwBCAG4MAAADACsAbwwAAAEAPAACAAkJuxkGBwBVAgloDAAACABXAGkMAAAIAFIAawwAAAgAOQBqDAAABQA6AGwMAAAFAE8AbQwAAAIAMQDqDAAABwBCAG4MAAADACsAbwwAAAEAPAAAAA==.',
Zo='Zoan:BAEALgAECgQJCAABLgAECgkJMQAZAK4gAA==.',
Zu='Zubbfist:BAEALgADCgcJBwABLgAFFAQJCgATACMeAA==.Zubbrael:BAEBLgAECn8sAAMKAAgJHhsUHgDMAQhoDAAACQBUAGkMAAAHAEMAawwAAAYARQBqDAAABgBQAGwMAAAGAEMAbQwAAAEAUgDqDAAACABHAG4MAAABACoACgAHCUMaFB4AzAEHaAwAAAcAVABpDAAABQBDAGsMAAAEAEUAagwAAAQAUABsDAAABABDAOoMAAAGAEcAbgwAAAEAKgAcAAcJgwnkMwA7AQdoDAAAAgAOAGkMAAACABUAawwAAAIAIwBqDAAAAgArAGwMAAACABIAbQwAAAEAEgDqDAAAAgATAAEuAAUUBAkKABMAIx4A.Zubbz:BAECLgAFFH8FAAMbAAQJtxG5DwATAQRoDAAAAgAmAGkMAAABAD0AawwAAAEAGADqDAAAAQA4ABsABAm3EbkPABMBBGgMAAABACYAaQwAAAEAPQBrDAAAAQAYAOoMAAABADgAHgABCU8IwpIAPAABaAwAAAEAFQAuAAQKfzQAAx4ACAkuH5MeAJoCAB4ACAksHpMeAJoCABsABwmWHmoRAAQCAAEuAAUUBAkKABMAIx4A.',
Zz='Zzertz:BAECLgAFFH8gAAIKAAYJ1R+ABgDwAQZoDAAACABhAGkMAAAHAGIAawwAAAYAVABqDAAAAwBcAGwMAAABACcA6gwAAAcAWAAKAAYJ1R+ABgDwAQZoDAAACABhAGkMAAAHAGIAawwAAAYAVABqDAAAAwBcAGwMAAABACcA6gwAAAcAWAAuAAQKfysAAgoACAn/IjoGACkDAAoACAn/IjoGACkDAAAA.',
['Àb']='Àbeel:BAEALgAECgUJBgABLgAECggJOwAJAAYeAA==.Àbel:BAEBLgAECn87AAMJAAgJBh5jBgASAghoDAAACgBXAGkMAAALAFQAawwAAAgAWgBqDAAABwBeAGwMAAAFAD0AbQwAAAIAIwDqDAAADABZAG4MAAAEAFkACQAHCSseYwYAEgIHaAwAAAgAVwBpDAAACQBUAGsMAAAFAFoAagwAAAUAXgBsDAAABQA9AOoMAAAJAFkAbgwAAAIAMgAIAAcJfRulIACAAQdoDAAAAgBJAGkMAAACAE8AawwAAAMATgBqDAAAAgBdAG0MAAACACMA6gwAAAMAQQBuDAAAAgBZAAAA.Àble:BAEALgAECggJDQABLgAECggJOwAJAAYeAA==.',
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
