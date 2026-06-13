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

local lookup = {'Monk-Windwalker','Shaman-Enhancement','Monk-Mistweaver','Paladin-Retribution','Paladin-Holy','Mage-Frost','Priest-Holy','Unknown-Unknown','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','Warrior-Arms','Warrior-Fury','Warrior-Protection','DeathKnight-Unholy','Mage-Arcane','Paladin-Protection','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Monk-Brewmaster','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Warlock-Demonology','Druid-Guardian','Warlock-Destruction','Druid-Feral','DemonHunter-Havoc','Priest-Discipline','Shaman-Elemental','DeathKnight-Blood','DemonHunter-Devourer',}
local provider = {region='US',realm='Dalaran',name='US',type='subscribers',zone=46,date='2026-06-12',data={Ad='Adansso:BAEBLgAECn80AAIBAAkJFxK0HQC7AQloDAAACQArAGkMAAAIADoAawwAAAcAQwBqDAAABQA0AGwMAAAGADEAbQwAAAMAHADqDAAACAA7AG4MAAAFACUAbwwAAAEAGgABAAkJFxK0HQC7AQloDAAACQArAGkMAAAIADoAawwAAAcAQwBqDAAABQA0AGwMAAAGADEAbQwAAAMAHADqDAAACAA7AG4MAAAFACUAbwwAAAEAGgAAAA==.',
Al='Aliastei:BAEALgADCggJDAABLgAECgkJLwACALsZAA==.',
Ap='Apawcowlypse:BAEALgADCgcJDAABLgAFFAYJFgADAJsOAA==.',
As='Ashko:BAEBLgAECn8yAAMEAAgJDBtVOgAWAghoDAAACgBLAGkMAAAJAFcAawwAAAgAUQBqDAAABwBSAGwMAAAFAFEAbQwAAAMAKwDqDAAABgBHAG4MAAACACkABAAICQwbVToAFgIIaAwAAAkASwBpDAAACABXAGsMAAAGAFEAagwAAAYAUgBsDAAABQBRAG0MAAADACsA6gwAAAUARwBuDAAAAgApAAUABQlwDzJLAAsBBWgMAAABACYAaQwAAAEAHQBrDAAAAgBPAGoMAAABABcA6gwAAAEAGwAAAA==.',
Ay='Ayodele:BAEBLgAECn84AAIGAAkJtBu7HQCoAgloDAAACQBSAGkMAAAHAEcAawwAAAUAQwBqDAAACABWAGwMAAAGAEkAbQwAAAQAPwDqDAAACABTAG4MAAAGAFYAbwwAAAMAJwAGAAkJtBu7HQCoAgloDAAACQBSAGkMAAAHAEcAawwAAAUAQwBqDAAACABWAGwMAAAGAEkAbQwAAAQAPwDqDAAACABTAG4MAAAGAFYAbwwAAAMAJwAAAA==.',
Az='Azurlia:BAEALgAFFAEJAQAAAA==.',
Ba='Babycora:BAEALgAFFAMJAwABLgAFFAQJEAAHACwhAA==.Bagelandlox:BAEALgADCgEJAQABLgAECgYJDAAIAAAAAA==.Barrui:BAECLgAFFH8qAAMJAAkJGht9AwCMAgloDAAABwBfAGkMAAAIAGAAawwAAAcAWQBqDAAABwBgAGwMAAABAAQAbQwAAAEAJADqDAAACQBdAG4MAAABAGEAbwwAAAEAKAAJAAgJ8h19AwCMAghoDAAABwBfAGkMAAAHAFIAawwAAAYAWQBqDAAABwBgAG0MAAABACQA6gwAAAkAXQBuDAAAAQBhAG8MAAABACgACgADCVkQcAIAFQEDaQwAAAEAYABrDAAAAQAYAGwMAAABAAQALgAECn85AAMJAAkJcCTpBQAzAwAJAAkJ8SLpBQAzAwAKAAYJHyEvBABwAgAAAA==.',
Be='Belynila:BAECLgAFFH8PAAILAAQJ4xqZEQBVAQRoDAAABwBVAGkMAAAFAD4AawwAAAEAGwDqDAAAAgBjAAsABAnjGpkRAFUBBGgMAAAHAFUAaQwAAAUAPgBrDAAAAQAbAOoMAAACAGMALgAECn9AAAILAAkJoCENBQAFAwALAAkJoCENBQAFAwAAAA==.Bestiavera:BAEBLgAECn8+AAIMAAgJvRZSEQDbAQhoDAAACgBFAGkMAAAJAE4AawwAAAkAOgBqDAAACAA8AGwMAAAIACUAbQwAAAQAOQDqDAAACAA+AG4MAAAGACsADAAICb0WUhEA2wEIaAwAAAoARQBpDAAACQBOAGsMAAAJADoAagwAAAgAPABsDAAACAAlAG0MAAAEADkA6gwAAAgAPgBuDAAABgArAAAA.',
Br='Briggoker:BAEALgAECgQJBwAAAA==.Brigmahf:BAEALgAECgQJCQABLgAECgQJBwAIAAAAAA==.',
Ca='Carbonarra:BAEBLgAECn88AAINAAkJohjtFABGAgloDAAACwBbAGkMAAAKAEcAawwAAAoAUgBqDAAACABYAGwMAAAIAEgAbQwAAAIALADqDAAABwBDAG4MAAADADEAbwwAAAEAGQANAAkJohjtFABGAgloDAAACwBbAGkMAAAKAEcAawwAAAoAUgBqDAAACABYAGwMAAAIAEgAbQwAAAIALADqDAAABwBDAG4MAAADADEAbwwAAAEAGQAAAA==.',
Ch='Chetegos:BAEALgADCgYJBgABLgAECgkJOgAOAPEjAA==.Chíefsquirel:BAEALgAECgYJDAAAAA==.',
Da='Dadbanger:BAECLgAFFH8nAAMBAAkJQyA4AABxAgloDAAABgBiAGkMAAAGAGAAawwAAAUASgBqDAAABwBfAGwMAAAEAEQAbQwAAAEAJQDqDAAABwBhAG4MAAACAF0AbwwAAAEAXgABAAgJEiE4AABxAghoDAAABgBiAGkMAAAGAGAAawwAAAUASgBqDAAABwBfAG0MAAABACUA6gwAAAcAYQBuDAAAAgBdAG8MAAABAF4AAwABCSAKBloAQgABbAwAAAQAGQAuAAQKfyoAAgEACAlxJgkCAIQDAAEACAlxJgkCAIQDAAAA.Daeke:BAEALgADCgUJBQABLgAECgQJBwAIAAAAAA==.Daekeypoo:BAEALgAECgQJBwAAAA==.Darkvirgo:BAEBLgAFFH8QAAIGAAQJzQhhcgD9AARoDAAABQAiAGkMAAAFAB4AawwAAAEAAgDqDAAABQAVAAYABAnNCGFyAP0ABGgMAAAFACIAaQwAAAUAHgBrDAAAAQACAOoMAAAFABUAAS4ABRQICSUACwCkGQA=.',
De='Deathbeaver:BAEALgAECgYJCwABLgAECgkJUQAEAF8eAA==.Destrom:BAEBLgAECn8UAAIPAAkJuBFbfwBhAQloDAAAAwAwAGkMAAADADAAawwAAAMASABqDAAAAgA2AGwMAAABAB4AbQwAAAEAKADqDAAAAwAXAG4MAAACAC0AbwwAAAIANQAPAAkJuBFbfwBhAQloDAAAAwAwAGkMAAADADAAawwAAAMASABqDAAAAgA2AGwMAAABAB4AbQwAAAEAKADqDAAAAwAXAG4MAAACAC0AbwwAAAIANQAAAA==.',
Ep='Epilepticc:BAECLgAFFH8PAAIEAAQJSB4ENQA9AQRoDAAABQBCAGkMAAAEAFUAawwAAAMAUADqDAAAAwBNAAQABAlIHgQ1AD0BBGgMAAAFAEIAaQwAAAQAVQBrDAAAAwBQAOoMAAADAE0ALgAECn88AAIEAAkJ6yItGQCpAgAEAAkJ6yItGQCpAgAAAA==.',
Et='Ethalon:BAECLgAFFH8TAAMFAAQJ1Bl0GQBPAQRoDAAABgBOAGkMAAAFAFoAawwAAAMAEwDqDAAABQBMAAUABAnUGXQZAE8BBGgMAAAFAE4AaQwAAAUAWgBrDAAAAwATAOoMAAAFAEwABAABCbcC7r8AOQABaAwAAAEABgAuAAQKfyUAAwUACQkdGicYAFECAAUACQkdGicYAFECAAQAAgnJFLtyAUEAAAAA.',
Fa='Fallhp:BAEALgADCgYJBgABLgAFFAgJFgAFALwUAA==.Fallill:BAEALgAECgIJAgABLgAFFAgJFgAFALwUAA==.Falosso:BAECLgAFFH8WAAIFAAgJvBQ6BwBEAghoDAAAAwA1AGkMAAADAEcAawwAAAMAQABqDAAAAwBLAGwMAAADAA0AbQwAAAEAHwDqDAAABQBQAG4MAAABACIABQAICbwUOgcARAIIaAwAAAMANQBpDAAAAwBHAGsMAAADAEAAagwAAAMASwBsDAAAAwANAG0MAAABAB8A6gwAAAUAUABuDAAAAQAiAC4ABAp/MwADBQAJCY8gHw0AvQIABQAJCY8gHw0AvQIABAACCRMOskkBXgAAAAA=.',
Ga='Garlooth:BAECLgAFFH8KAAIQAAMJThUhAgDeAANoDAAABQAzAGkMAAADAE4A6gwAAAIAIQAQAAMJThUhAgDeAANoDAAABQAzAGkMAAADAE4A6gwAAAIAIQAuAAQKfzUAAhAACQkVJSwAAGMDABAACQkVJSwAAGMDAAAA.',
Gl='Glizzygary:BAEALgAFFAUJEgAAAQ==.',
Gr='Grimvalor:BAEBLgAECn9RAAMEAAkJXx75GwCZAgloDAAACwBcAGkMAAAKAEwAawwAAAsAUgBqDAAACQBYAGwMAAAKAFkAbQwAAAcASwDqDAAADABSAG4MAAAHAD0AbwwAAAQAPQAEAAkJXx75GwCZAgloDAAACgBcAGkMAAAKAEwAawwAAAoAUgBqDAAACABYAGwMAAAJAFkAbQwAAAcASwDqDAAACwBSAG4MAAAHAD0AbwwAAAQAPQARAAUJzwotPwBdAAVoDAAAAQAPAGsMAAABACwAagwAAAEALABsDAAAAQAiAOoMAAABAA8AAAA=.Grunclaws:BAEALgAECgcJEgABLgAECgkJMgAEAAwbAA==.Grunjo:BAEALgAECgkJCQABLgAECgkJMgAEAAwbAA==.Grunsy:BAEALgAECgcJBQABLgAECgkJMgAEAAwbAA==.',
Ha='Haf:BAEBLgAECn8qAAIRAAkJ8hGmFACBAQloDAAABwA9AGkMAAAGAEIAawwAAAYARwBqDAAABQAjAGwMAAAFADYAbQwAAAMAFQDqDAAABgAvAG4MAAACABYAbwwAAAIAFwARAAkJ8hGmFACBAQloDAAABwA9AGkMAAAGAEIAawwAAAYARwBqDAAABQAjAGwMAAAFADYAbQwAAAMAFQDqDAAABgAvAG4MAAACABYAbwwAAAIAFwAAAA==.',
He='Hertzmuch:BAEALgADCgYJDgABLgAFFAYJFgADAJsOAA==.',
Ho='Holeighfuk:BAEALgAECgYJBgAAAA==.',
Ka='Kautheros:BAEBLgAECn8eAAQSAAkJ+AxxEQCuAQloDAAABAAIAGkMAAAEABkAawwAAAQAOwBqDAAABAAfAGwMAAADACIAbQwAAAMACQDqDAAABQBDAG4MAAACAB0AbwwAAAEAHwASAAkJ+AxxEQCuAQloDAAAAgAIAGkMAAACABkAawwAAAIAOwBqDAAAAgAfAGwMAAABACIAbQwAAAMACQDqDAAABABDAG4MAAACAB0AbwwAAAEAHwATAAYJUglVWgDFAAZoDAAAAQAdAGkMAAABABgAawwAAAIAHABqDAAAAQAkAGwMAAACABcA6gwAAAEADAAUAAMJmgYDIABOAANoDAAAAQAJAGkMAAABABgAagwAAAEAGgAAAA==.',
Ke='Kelo:BAEALgAECgkJAQABLgAECgkJMgAEAAwbAA==.',
Kr='Kroxychi:BAEALgAECgcJDgAAAA==.Kroxypurple:BAEALgADCgIJAgABLgAECgcJDgAIAAAAAA==.',
Ku='Kungfused:BAECLgAFFH8WAAIDAAYJmw7SHwBdAQZoDAAABgAqAGkMAAAGADoAawwAAAQALwBqDAAAAQAaAGwMAAABABYA6gwAAAQAGgADAAYJmw7SHwBdAQZoDAAABgAqAGkMAAAGADoAawwAAAQALwBqDAAAAQAaAGwMAAABABYA6gwAAAQAGgAuAAQKf3EABAMACQkWHsAKAKUCAAMACQkWHsAKAKUCAAEACQmYFEkXAPUBABUABAn/CERZAKEAAAAA.',
Le='Lennather:BAEBLgAECn9DAAIBAAkJtCVYAQBmAwloDAAACABjAGkMAAAIAGEAawwAAAcAYABqDAAABwBOAGwMAAAJAGEAbQwAAAgAXgDqDAAACgBfAG4MAAAIAGMAbwwAAAIAWgABAAkJtCVYAQBmAwloDAAACABjAGkMAAAIAGEAawwAAAcAYABqDAAABwBOAGwMAAAJAGEAbQwAAAgAXgDqDAAACgBfAG4MAAAIAGMAbwwAAAIAWgAAAA==.',
Li='Lidomi:BAEALgAECgUJCwABLgAFFAQJCwASAP8PAA==.Lidrunka:BAECLgAFFH8FAAMVAAIJNRfoQQCWAAJoDAAAAwAwAOoMAAACAEUAFQACCTUX6EEAlgACaAwAAAIAMADqDAAAAgBFAAEAAQkMAp4UAD0AAWgMAAABAAUALgAECn8YAAMBAAgJdBXVGwD9AQABAAgJ0BTVGwD9AQAVAAQJFhTNSQDSAAABLgAFFAQJCwASAP8PAA==.',
['Lé']='Lépewpew:BAEBLgAECn8YAAIWAAcJSRKEJwBiAQdoDAAABQA+AGkMAAAFADMAawwAAAUAOwBqDAAAAwBNAGwMAAABACYA6gwAAAQAOgBuDAAAAQAKABYABwlJEoQnAGIBB2gMAAAFAD4AaQwAAAUAMwBrDAAABQA7AGoMAAADAE0AbAwAAAEAJgDqDAAABAA6AG4MAAABAAoAAAA=.',
Ma='Mattimus:BAEBLgAECn8iAAMXAAcJjw7teABJAQdoDAAABgA9AGkMAAAGACUAawwAAAcAGgBqDAAABQA1AGwMAAADACYA6gwAAAYAJQBuDAAAAQAVABcABwmPDu14AEkBB2gMAAAGAD0AaQwAAAUAJQBrDAAABgAaAGoMAAAEADUAbAwAAAMAJgDqDAAABQAlAG4MAAABABUAGAAECfkCtnAAfAAEaQwAAAEAAQBrDAAAAQAJAGoMAAABAAkA6gwAAAEADAAAAA==.',
['Má']='Mákí:BAEBLgAECn8hAAQBAAkJThVjIgCZAQloDAAABQBIAGkMAAAEADQAawwAAAUALwBqDAAABABIAGwMAAADAEEAbQwAAAEAFgDqDAAABwBQAG4MAAADADUAbwwAAAEAKgABAAgJHRdjIgCZAQhoDAAABABIAGkMAAADADQAawwAAAQALwBqDAAAAgBIAGwMAAADAEEA6gwAAAQAUABuDAAAAwA1AG8MAAABACoAFQAFCYIWTjsACwEFaAwAAAEAQABpDAAAAQAyAGsMAAABACUAagwAAAEAPQDqDAAAAgBOAAMAAwn4DumAAJEAA2oMAAABACsAbQwAAAEAHQDqDAAAAQApAAAA.',
Na='Natebanger:BAEALgAECgYJDAABLgAFFAkJJwABAEMgAA==.',
Ne='Nethertank:BAEALgAECgYJBgABLgAECggJHwAGAJAWAA==.',
No='Noeyednuck:BAEALgAECgYJEAABLgAFFAMJDAAXAJoQAA==.',
Nu='Nuckshott:BAECLgAFFH8MAAIXAAMJmhBFXADiAANoDAAABQAmAGkMAAADAB0A6gwAAAQAOwAXAAMJmhBFXADiAANoDAAABQAmAGkMAAADAB0A6gwAAAQAOwAuAAQKfzQAAhcACQnWH90YAIwCABcACQnWH90YAIwCAAAA.',
Og='Ogx:BAEALgAECgQJEQABLgAECgkJMgAEAAwbAA==.',
Ol='Olgass:BAEALgADCgIJAgABLgAECgkJNAAZAGUjAA==.',
Pu='Purlok:BAEALgAECgkJAwABLgAECgkJMgAEAAwbAA==.',
Qu='Quindrox:BAEBLgAECn8aAAITAAkJRSF9BQAFAwloDAAAAgBdAGkMAAACAFMAawwAAAMAVgBqDAAAAwBTAGwMAAADAFoAbQwAAAMATADqDAAABABQAG4MAAADAFoAbwwAAAMATwATAAkJRSF9BQAFAwloDAAAAgBdAGkMAAACAFMAawwAAAMAVgBqDAAAAwBTAGwMAAADAFoAbQwAAAMATADqDAAABABQAG4MAAADAFoAbwwAAAMATwABLgAFFAMJBgAaAB0YAA==.Quinet:BAEBLgAECn80AAMZAAkJZSN4CwDwAgloDAAABwBhAGkMAAAHAFwAawwAAAcAXABqDAAABwBRAGwMAAAGAFwAbQwAAAQAWADqDAAABwBeAG4MAAAFAEcAbwwAAAIAYAAZAAkJZSN4CwDwAgloDAAABwBhAGkMAAAGAFwAawwAAAcAXABqDAAAAQAQAGwMAAAEAFwAbQwAAAQAWADqDAAABwBeAG4MAAAFAEcAbwwAAAIAYAAbAAMJyh5xLwD9AANpDAAAAQBGAGoMAAAGAFEAbAwAAAIAVwAAAA==.Quinman:BAEBLgAECn8aAAQWAAkJRRr4EwAGAgloDAAABQBBAGkMAAAEADMAawwAAAQATwBqDAAAAgAnAGwMAAACAGEAbQwAAAIAOwDqDAAABABBAG4MAAACAD0AbwwAAAEAOgAWAAkJixf4EwAGAgloDAAAAQA8AGkMAAABAAAAawwAAAEATwBqDAAAAgAnAGwMAAACAGEAbQwAAAIAOwDqDAAAAwBBAG4MAAACAD0AbwwAAAEAOgAYAAQJWhWQWQDfAARoDAAAAwBBAGkMAAADADMAawwAAAMAMQDqDAAAAQA0ABcAAQkVGAcfAToAAWgMAAABAD0AAS4ABRQDCQYAGgAdGAA=.Quinmanbear:BAEBLgAFFH8GAAMaAAMJHRiFFADVAANoDAAAAgA8AGkMAAACAEIA6gwAAAIAOgAaAAMJHRiFFADVAANoDAAAAgA8AGkMAAACAEIA6gwAAAEAOgAcAAEJeguZHgA4AAHqDAAAAQAdAAAA.Quinroxx:BAEBLgAECn8gAAIGAAgJXiN8KwDFAghoDAAABQBiAGkMAAAFAFsAawwAAAUAXwBqDAAABQBeAGwMAAADAFoAbQwAAAIAUwDqDAAABgBhAG4MAAABAE0ABgAICV4jfCsAxQIIaAwAAAUAYgBpDAAABQBbAGsMAAAFAF8AagwAAAUAXgBsDAAAAwBaAG0MAAACAFMA6gwAAAYAYQBuDAAAAQBNAAEuAAUUAwkGABoAHRgA.Quinvinvin:BAEALgAECgcJDQABLgAFFAMJBgAaAB0YAA==.',
Ra='Ragsnak:BAEALgAECgkJEQABLgAECgkJMgAEAAwbAA==.',
Ro='Ronimus:BAEALgAECgEJAQAAAA==.',
Ru='Rufio:BAECLgAFFH8NAAIdAAMJJQyGGwC7AANoDAAABgA2AGkMAAAEABMA6gwAAAMAEwAdAAMJJQyGGwC7AANoDAAABgA2AGkMAAAEABMA6gwAAAMAEwAuAAQKfywAAh0ACQldHHYJAI8CAB0ACQldHHYJAI8CAAAA.',
Ry='Rytiou:BAECLgAFFH8YAAITAAcJbRhXBQCuAQdoDAAABABSAGkMAAAFAFYAawwAAAQALgBqDAAABABJAGwMAAABADUA6gwAAAUAUgBuDAAAAQAXABMABwltGFcFAK4BB2gMAAAEAFIAaQwAAAUAVgBrDAAABAAuAGoMAAAEAEkAbAwAAAEANQDqDAAABQBSAG4MAAABABcALgAECn8yAAITAAkJ6iRZAgCMAwATAAkJ6iRZAgCMAwAAAA==.',
Sa='Saadxevok:BAEBLgAECn8YAAMUAAgJQRFLEADYAQhoDAAAAwA7AGkMAAADADEAawwAAAMARQBqDAAAAwAwAGwMAAAEAEgAbQwAAAMACADqDAAAAwAkAG4MAAACAAwAFAAICUERSxAA2AEIaAwAAAMAOwBpDAAAAwAxAGsMAAACAEUAagwAAAIAMABsDAAAAwBIAG0MAAABAAgA6gwAAAEAJABuDAAAAQAMABIABglTCD0pACkBBmsMAAABABAAagwAAAEAEQBsDAAAAQARAG0MAAACAB4A6gwAAAIAJwBuDAAAAQAGAAEuAAUUCAkjAAsAZB4A.Saadxm:BAEALgAECgcJDwABLgAFFAgJIwALAGQeAA==.Saadxp:BAECLgAFFH8jAAMLAAgJZB7JAABZAghoDAAABQBjAGkMAAAGAGAAawwAAAYAYABqDAAABgBYAGwMAAADACAAbQwAAAEAVADqDAAABwBeAG4MAAABACkACwAHCV0hyQAAWQIHaAwAAAQAYwBpDAAABQBgAGsMAAAFAGAAagwAAAUAWABtDAAAAQBUAOoMAAAFAF4AbgwAAAEAKQAeAAYJ5RnxAQANAgZoDAAAAQBJAGkMAAABAB0AawwAAAEAWgBqDAAAAQBOAGwMAAADADMA6gwAAAIASgAuAAQKfyUAAwsACAmRJrcDAGADAAsACAmRJrcDAGADAB4ABQkLHz4gAJEBAAAA.',
Se='Sendrys:BAEALgAECgEJAQABLgAECgkJLwACALsZAA==.',
Sg='Sgtgigachad:BAEALgAECgUJBQABLgAFFAUJEgAIAAAAAQ==.',
Sp='Spilt:BAECLgAFFH8zAAIGAAkJ+BivAQCMAgloDAAACQBaAGkMAAAJAFQAawwAAAYAPwBqDAAABgA0AGwMAAAEAEIAbQwAAAMARgDqDAAACQBTAG4MAAADACgAbwwAAAIACwAGAAkJ+BivAQCMAgloDAAACQBaAGkMAAAJAFQAawwAAAYAPwBqDAAABgA0AGwMAAAEAEIAbQwAAAMARgDqDAAACQBTAG4MAAADACgAbwwAAAIACwAuAAQKfx0AAgYACQnJJOMKAG0DAAYACQnJJOMKAG0DAAAA.Spilthen:BAEBLgAFFH8JAAIfAAUJyhgoGwA5AQVoDAAAAgBJAGkMAAACAEQAawwAAAIAJwBqDAAAAQANAOoMAAACAEcAHwAFCcoYKBsAOQEFaAwAAAIASQBpDAAAAgBEAGsMAAACACcAagwAAAEADQDqDAAAAgBHAAEuAAUUCQkzAAYA+BgA.Spiltmonk:BAEBLgAECn8YAAIBAAYJWh80HAD6AQZoDAAABABGAGkMAAAEAFEAawwAAAQAUgBqDAAABABMAGwMAAADAFIA6gwAAAUAVAABAAYJWh80HAD6AQZoDAAABABGAGkMAAAEAFEAawwAAAQAUgBqDAAABABMAGwMAAADAFIA6gwAAAUAVAABLgAFFAkJMwAGAPgYAA==.',
Su='Sunjo:BAEALgAECgkJBwABLgAECgkJMgAEAAwbAA==.',
Ta='Taku:BAEALgAECgcJDQABLgAECgkJHgASAPgMAA==.Taymeean:BAEALgAECgMJBAABLgAFFAQJBwATAEAJAA==.Tayvok:BAECLgAFFH8HAAITAAQJQAkFOQDdAARoDAAAAgAOAGkMAAADADAAawwAAAEAFgDqDAAAAQAJABMABAlACQU5AN0ABGgMAAACAA4AaQwAAAMAMABrDAAAAQAWAOoMAAABAAkALgAECn8vAAITAAkJkRxkDwBuAgATAAkJkRxkDwBuAgAAAA==.',
Te='Tentickles:BAECLgAFFH8NAAILAAQJlx/7EgBIAQRoDAAAAwBIAGkMAAADAFsAawwAAAIAYQDqDAAABQA9AAsABAmXH/sSAEgBBGgMAAADAEgAaQwAAAMAWwBrDAAAAgBhAOoMAAAFAD0ALgAECn8UAAILAAgJiCJyCAD9AgALAAgJiCJyCAD9AgABLgAFFAkJJwABAEMgAA==.',
Th='Thecheatt:BAEBLgAECn86AAMOAAkJ8SMMBwCSAgloDAAACQBjAGkMAAAJAGEAawwAAAoAYwBqDAAACABhAGwMAAAIAF0AbQwAAAIAWgDqDAAACABfAG4MAAACAEcAbwwAAAIAWQAOAAkJ3iMMBwCSAgloDAAABwBhAGkMAAAGAGEAawwAAAgAYwBqDAAABgBhAGwMAAAFAF0AbQwAAAIAWgDqDAAABABfAG4MAAACAEcAbwwAAAIAWQANAAYJCB7qSQB9AQZoDAAAAgBjAGkMAAADAFEAawwAAAIANgBqDAAAAgAyAGwMAAADAE8A6gwAAAQARQAAAA==.Therelore:BAEALgAECgkJEwABLgAECgkJFAAPALgRAA==.',
Ty='Tyära:BAEBLgAECn8dAAMPAAgJTAs/tAAKAQhoDAAABgAYAGkMAAAGACQAawwAAAUAPgBqDAAAAwAXAGwMAAACAB4AbQwAAAEADQDqDAAABQAUAG4MAAABAA4ADwAHCUEJP7QACgEHaAwAAAUAEgBpDAAABQAZAGsMAAAEACYAagwAAAIAEwBsDAAAAQAeAOoMAAAEAA0AbgwAAAEADgAgAAcJtgokMgDQAAdoDAAAAQAYAGkMAAABACQAawwAAAEAPgBqDAAAAQAXAGwMAAABAAcAbQwAAAEADQDqDAAAAQAUAAEuAAUUAwkMAAYA3QsA.',
Vi='Vilexie:BAEALgAECggJEwAAAA==.',
Wa='Wafflé:BAEALgAECgIJAgAAAA==.',
Wh='Whitecrosses:BAEALgAECgEJAQABLgAECgcJGAAWAEkSAA==.',
Wi='Wiskystagger:BAEALgADCgEJAgAAAA==.',
Za='Zanea:BAEALgADCgkJEgABLgAECgkJLwACALsZAA==.Zargan:BAEALgAECgcJCAABLgAECgkJHgASAPgMAA==.',
Ze='Zertzz:BAEALgAFFAEJAQABLgAFFAYJIAALANUfAA==.',
Zi='Zibbz:BAECLgAFFH8KAAITAAQJIx5vIABRAQRoDAAAAwBHAGkMAAADAFAAawwAAAEAVwDqDAAAAwBEABMABAkjHm8gAFEBBGgMAAADAEcAaQwAAAMAUABrDAAAAQBXAOoMAAADAEQALgAECn8/AAMTAAkJgiUVAgBeAwATAAkJgiUVAgBeAwAUAAcJyxp9BwC/AQAAAA==.Zinia:BAEBLgAECn8vAAICAAkJuxlhBwBSAgloDAAACABXAGkMAAAIAFIAawwAAAgAOQBqDAAABQA6AGwMAAAFAE8AbQwAAAIAMQDqDAAABwBCAG4MAAADACsAbwwAAAEAPAACAAkJuxlhBwBSAgloDAAACABXAGkMAAAIAFIAawwAAAgAOQBqDAAABQA6AGwMAAAFAE8AbQwAAAIAMQDqDAAABwBCAG4MAAADACsAbwwAAAEAPAAAAA==.',
Zo='Zoan:BAEALgAECgQJCAABLgAECgkJNAAZAGUjAA==.',
Zu='Zubbfist:BAEALgADCgcJBwABLgAFFAQJCgATACMeAA==.Zubbrael:BAEBLgAECn8sAAMLAAgJHhuTHwDGAQhoDAAACQBUAGkMAAAHAEMAawwAAAYARQBqDAAABgBQAGwMAAAGAEMAbQwAAAEAUgDqDAAACABHAG4MAAABACoACwAHCUMakx8AxgEHaAwAAAcAVABpDAAABQBDAGsMAAAEAEUAagwAAAQAUABsDAAABABDAOoMAAAGAEcAbgwAAAEAKgAeAAcJgwlDNgA5AQdoDAAAAgAOAGkMAAACABUAawwAAAIAIwBqDAAAAgArAGwMAAACABIAbQwAAAEAEgDqDAAAAgATAAEuAAUUBAkKABMAIx4A.Zubbz:BAECLgAFFH8FAAMdAAQJtxF3EQATAQRoDAAAAgAmAGkMAAABAD0AawwAAAEAGADqDAAAAQA4AB0ABAm3EXcRABMBBGgMAAABACYAaQwAAAEAPQBrDAAAAQAYAOoMAAABADgAIQABCU8Ie50AOAABaAwAAAEAFQAuAAQKfzQAAyEACAkuH5MeAJoCACEACAksHpMeAJoCAB0ABwmWHnYSAAECAAEuAAUUBAkKABMAIx4A.',
Zz='Zzertz:BAECLgAFFH8gAAILAAYJ1R+7BwDrAQZoDAAACABhAGkMAAAHAGIAawwAAAYAVABqDAAAAwBcAGwMAAABACcA6gwAAAcAWAALAAYJ1R+7BwDrAQZoDAAACABhAGkMAAAHAGIAawwAAAYAVABqDAAAAwBcAGwMAAABACcA6gwAAAcAWAAuAAQKfysAAgsACAn/IjoGACkDAAsACAn/IjoGACkDAAAA.',
['Àb']='Àbeel:BAEALgAECgUJBgABLgAECgkJPAAKAE8cAA==.Àbel:BAEBLgAECn88AAMKAAkJTxxjBgASAgloDAAACgBXAGkMAAALAFQAawwAAAgAWgBqDAAABwBeAGwMAAAFAD0AbQwAAAIAIwDqDAAADABZAG4MAAAEAFkAbwwAAAEAKQAKAAcJKx5jBgASAgdoDAAACABXAGkMAAAJAFQAawwAAAUAWgBqDAAABQBeAGwMAAAFAD0A6gwAAAkAWQBuDAAAAgAyAAkACAnkGWQZAMoBCGgMAAACAEkAaQwAAAIATwBrDAAAAwBOAGoMAAACAF0AbQwAAAIAIwDqDAAAAwBBAG4MAAACAFkAbwwAAAEAKQAAAA==.Àble:BAEALgAECggJDQABLgAECgkJPAAKAE8cAA==.',
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
