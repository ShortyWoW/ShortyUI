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

local lookup = {'Monk-Windwalker','Shaman-Elemental','Monk-Mistweaver','Paladin-Retribution','Unknown-Unknown','Druid-Feral','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','Warrior-Fury','Warrior-Protection','Paladin-Holy','Mage-Arcane','Paladin-Protection','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Mage-Frost','Warlock-Demonology','Warlock-Destruction','DemonHunter-Havoc','Priest-Discipline','Shaman-Restoration','Shaman-Enhancement',}
local provider = {region='US',realm='Dalaran',name='US',type='subscribers',zone=46,date='2026-05-01',data={Ad='Adansso:BAEBLgAECn8eAAIBAAgJggwnEgBiAQhoDAAABgAYAGkMAAAFACsAawwAAAUAQwBqDAAAAwAlAGwMAAADABcAbQwAAAEAFgDqDAAABQAXAG4MAAACABMAAQAICYIMJxIAYgEIaAwAAAYAGABpDAAABQArAGsMAAAFAEMAagwAAAMAJQBsDAAAAwAXAG0MAAABABYA6gwAAAUAFwBuDAAAAgATAAAA.',
An='Anoncrusade:BAEALgAECgYJDAABLgAFFAUJCwACAKkKAA==.',
Ap='Apawcowlypse:BAEALgADCgcJDAABLgAFFAQJCQADAPQLAA==.',
As='Ashko:BAEBLgAECn8VAAIEAAYJghr+LwCCAQZoDAAABQBBAGkMAAAEAFMAawwAAAQAUQBqDAAAAwBGAGwMAAACADcA6gwAAAMANQAEAAYJghr+LwCCAQZoDAAABQBBAGkMAAAEAFMAawwAAAQAUQBqDAAAAwBGAGwMAAACADcA6gwAAAMANQABLgAECgcJAQAFAAAAAA==.',
Az='Azurlia:BAEALgAECgYJEAAAAA==.',
Ba='Babycora:BAEALgAECgUJBgABLgAECggJHQAGAF8YAA==.Bagelandlox:BAEALgADCgEJAQABLgAECgYJDAAFAAAAAA==.Barrui:BAECLgAFFH8ZAAMHAAcJ5RQ+AQDAAQdoDAAABQBAAGkMAAAFAGAAawwAAAQAOwBqDAAAAwA+AGwMAAABAAQAbQwAAAEAKADqDAAABgA3AAcABglOFz4BAMABBmgMAAAFAEAAaQwAAAQATgBrDAAAAwA7AGoMAAADAD4AbQwAAAEAKADqDAAABgA3AAgAAwlZEG4CABUBA2kMAAABAGAAawwAAAEAGABsDAAAAQAEAC4ABAp/LgADBwAJCQAi5wUAMwMABwAJCY8g5wUAMwMACAAGCQshLQQAcAIAAAA=.',
Be='Belynila:BAEBLgAECn8eAAIJAAgJ6xmwFQA8AghoDAAABABNAGkMAAAEADwAawwAAAQAQQBqDAAABABFAGwMAAAEADoAbQwAAAIAKQDqDAAABQBNAG4MAAADAFIACQAICesZsBUAPAIIaAwAAAQATQBpDAAABAA8AGsMAAAEAEEAagwAAAQARQBsDAAABAA6AG0MAAACACkA6gwAAAUATQBuDAAAAwBSAAAA.',
Ca='Carbonarra:BAEBLgAECn8aAAIKAAYJNxgzGQBmAQZoDAAABgBbAGkMAAAFADoAawwAAAUALwBqDAAAAwA+AGwMAAADAC0A6gwAAAQAQwAKAAYJNxgzGQBmAQZoDAAABgBbAGkMAAAFADoAawwAAAUALwBqDAAAAwA+AGwMAAADAC0A6gwAAAQAQwAAAA==.Catcam:BAEALgAECgYJBgAAAA==.',
Ch='Chetegos:BAEALgADCgYJBgABLgAECggJKAALANUiAA==.Chíefsquirel:BAEALgAECgYJDAAAAA==.',
Da='Dadbanger:BAECLgAFFH8cAAMBAAcJuB42AABxAgdoDAAABABiAGkMAAAFAGAAawwAAAUASgBqDAAABQBXAGwMAAADAEMAbQwAAAEAJQDqDAAABQBhAAEABgmXHzYAAHECBmgMAAAEAGIAaQwAAAUAYABrDAAABQBKAGoMAAAFAFcAbQwAAAEAJQDqDAAABQBhAAMAAQmSBTcWAEkAAWwMAAADAA4ALgAECn8iAAIBAAgJaSYKAgCEAwABAAgJaSYKAgCEAwAAAA==.Daeke:BAEALgADCgUJBQABLgAECgQJBwAFAAAAAA==.Daekeypoo:BAEALgAECgQJBwAAAA==.Darkvirgo:BAEALgAECgYJEQABLgAFFAYJEwAJAAAQAA==.',
De='Deathbeaver:BAEALgAECgQJBQABLgAECgcJKQAEAPobAA==.Destrom:BAEALgAECgUJCQAAAA==.',
Ep='Epilepticc:BAEBLgAECn80AAIEAAkJ2CEUBQDJAgloDAAACABjAGkMAAAKAFUAawwAAAgAUwBqDAAABgBZAGwMAAAFAE0AbQwAAAMAQgDqDAAACABjAG4MAAADAFUAbwwAAAEAYAAEAAkJ2CEUBQDJAgloDAAACABjAGkMAAAKAFUAawwAAAgAUwBqDAAABgBZAGwMAAAFAE0AbQwAAAMAQgDqDAAACABjAG4MAAADAFUAbwwAAAEAYAAAAA==.',
Et='Ethalon:BAEBLgAECn8iAAMMAAkJHRooGABRAgloDAAABQBFAGkMAAAFAFgAawwAAAUAWABqDAAAAwBTAGwMAAAFAFEAbQwAAAIARwDqDAAABgBXAG4MAAACAAcAbwwAAAEAFwAMAAkJHRooGABRAgloDAAABQBFAGkMAAAEAFgAawwAAAUAWABqDAAAAwBTAGwMAAAFAFEAbQwAAAIARwDqDAAABgBXAG4MAAABAAcAbwwAAAEAFwAEAAIJjxNougBDAAJpDAAAAQAvAG4MAAABADQAAAA=.',
Fa='Fallhp:BAEALgADCgYJBgABLgAFFAYJDgAMAFsUAA==.Fallill:BAEALgAECgIJAgABLgAFFAYJDgAMAFsUAA==.Falosso:BAECLgAFFH8OAAIMAAYJWxRuAgDtAQZoDAAAAgA0AGkMAAACADUAawwAAAIAPwBqDAAAAgBLAGwMAAADAA0A6gwAAAMANgAMAAYJWxRuAgDtAQZoDAAAAgA0AGkMAAACADUAawwAAAIAPwBqDAAAAgBLAGwMAAADAA0A6gwAAAMANgAuAAQKfykAAwwACQn/HH4PAJgCAAwACQn/HH4PAJgCAAQAAQkUCkzCADwAAAAA.',
Ga='Garlooth:BAEBLgAECn8VAAINAAgJCRnBBgCkAQhoDAAABABTAGkMAAAEAEoAawwAAAQAPgBqDAAAAgAyAGwMAAACAEMAbQwAAAEAOwDqDAAAAwA+AG4MAAABACcADQAICQkZwQYApAEIaAwAAAQAUwBpDAAABABKAGsMAAAEAD4AagwAAAIAMgBsDAAAAgBDAG0MAAABADsA6gwAAAMAPgBuDAAAAQAnAAAA.',
Gl='Glizzygary:BAEALgAFFAMJBAAAAQ==.',
Gr='Grimvalor:BAEBLgAECn8pAAMEAAcJ+hu6HQDXAQdoDAAACABcAGkMAAAGAEAAawwAAAcAUgBqDAAABgA1AGwMAAAFAEsAbQwAAAEAIADqDAAACABSAAQABwn6G7odANcBB2gMAAAHAFwAaQwAAAYAQABrDAAABgBSAGoMAAAFADUAbAwAAAQASwBtDAAAAQAgAOoMAAAHAFIADgAFCbgKmR4AaAAFaAwAAAEADwBrDAAAAQAsAGoMAAABACsAbAwAAAEAIgDqDAAAAQAPAAAA.Grunsy:BAEALgAECgcJAQAAAA==.',
Ha='Haf:BAEBLgAECn8oAAIOAAgJNxM0CQB4AQhoDAAABwA9AGkMAAAGAEIAawwAAAYARwBqDAAABQAjAGwMAAAFADYAbQwAAAMAFQDqDAAABgAvAG4MAAACABYADgAICTcTNAkAeAEIaAwAAAcAPQBpDAAABgBCAGsMAAAGAEcAagwAAAUAIwBsDAAABQA2AG0MAAADABUA6gwAAAYALwBuDAAAAgAWAAAA.',
He='Hertzmuch:BAEALgADCgYJDgABLgAFFAQJCQADAPQLAA==.',
Ho='Holeighfuk:BAEALgAECgYJBgAAAA==.',
Jo='Joicountdown:BAEBLgAFFH8jAAIGAAcJ9CYCAACwAgdoDAAABgBjAGkMAAAGAGQAawwAAAYAYgBqDAAABQBkAGwMAAADAGQAbQwAAAIAZADqDAAABwBkAAYABwn0JgIAALACB2gMAAAGAGMAaQwAAAYAZABrDAAABgBiAGoMAAAFAGQAbAwAAAMAZABtDAAAAgBkAOoMAAAHAGQAAS4ABAoGCQYABQAAAAA=.',
Ka='Kautheros:BAEBLgAECn8VAAQPAAgJtAddMADuAAhoDAAAAwAHAGkMAAADAAcAawwAAAMAEQBqDAAAAwAGAGwMAAACADQAbQwAAAMACQDqDAAAAwAhAG4MAAABABYADwAHCd8FXTAA7gAHaAwAAAEABwBpDAAAAQAHAGsMAAABABEAagwAAAEABgBtDAAAAwAJAOoMAAACACEAbgwAAAEAFgAQAAYJUQlOIwDrAAZoDAAAAQAdAGkMAAABABgAawwAAAIAHABqDAAAAQAkAGwMAAACABcA6gwAAAEADAARAAMJewYeDwBgAANoDAAAAQAIAGkMAAABABgAagwAAAEAGgAAAA==.',
Kr='Kroxychi:BAEALgAECgcJCQAAAA==.Kroxypurple:BAEALgADCgIJAgABLgAECgcJCQAFAAAAAA==.',
Ku='Kungfused:BAECLgAFFH8JAAIDAAQJ9AtmDQAFAQRoDAAABAAqAGkMAAADACUAawwAAAEAFwDqDAAAAQATAAMABAn0C2YNAAUBBGgMAAAEACoAaQwAAAMAJQBrDAAAAQAXAOoMAAABABMALgAECn8zAAIDAAgJ+R+7CgClAgADAAgJ+R+7CgClAgAAAA==.',
Le='Lennather:BAEBLgAECn8mAAIBAAkJ0CJrAQDtAgloDAAABgBjAGkMAAAGAGEAawwAAAUAWwBqDAAABQBOAGwMAAAEAFsAbQwAAAMAVwDqDAAABQBbAG4MAAADAEsAbwwAAAEATwABAAkJ0CJrAQDtAgloDAAABgBjAGkMAAAGAGEAawwAAAUAWwBqDAAABQBOAGwMAAAEAFsAbQwAAAMAVwDqDAAABQBbAG4MAAADAEsAbwwAAAEATwAAAA==.',
Li='Lidrunka:BAEALgAFFAEJAQAAAA==.',
['Lé']='Lépewpew:BAEBLgAECn8XAAISAAYJHBVJDwBqAQZoDAAABQA+AGkMAAAFADMAawwAAAUAOwBqDAAAAwBNAGwMAAABACYA6gwAAAQAOgASAAYJHBVJDwBqAQZoDAAABQA+AGkMAAAFADMAawwAAAUAOwBqDAAAAwBNAGwMAAABACYA6gwAAAQAOgAAAA==.',
Ma='Mattimus:BAEBLgAECn8UAAMTAAYJOg4nOwAmAQZoDAAABAA9AGkMAAAEACUAawwAAAQAGABqDAAAAwAkAGwMAAACABQA6gwAAAMAJgATAAYJOg4nOwAmAQZoDAAABAA9AGkMAAADACUAawwAAAMAGABqDAAAAgAkAGwMAAACABQA6gwAAAIAJgAUAAQJ+QKfcAB8AARpDAAAAQABAGsMAAABAAkAagwAAAEACQDqDAAAAQAMAAAA.',
['Má']='Mákí:BAEALgAECgYJDwAAAA==.',
Na='Natebanger:BAEALgAECgYJDAABLgAFFAcJHAABALgeAA==.',
Ne='Nethertank:BAEALgADCgEJAQABLgAECgYJFAAVAHcSAA==.',
No='Noeyednuck:BAEALgAECgQJCQABLgAECgkJIgATAM8ZAA==.',
Nu='Nuckshott:BAEBLgAECn8iAAITAAkJzxkkDQA1AgloDAAABQBFAGkMAAAFAEgAawwAAAUASQBqDAAABABGAGwMAAAEAFgAbQwAAAMAFgDqDAAABABWAG4MAAADAC4AbwwAAAEARQATAAkJzxkkDQA1AgloDAAABQBFAGkMAAAFAEgAawwAAAUASQBqDAAABABGAGwMAAAEAFgAbQwAAAMAFgDqDAAABABWAG4MAAADAC4AbwwAAAEARQAAAA==.',
Ol='Olgass:BAEALgADCgIJAgABLgAECggJHgAWAIgiAA==.',
Pl='Ploots:BAEALgAECgcJAQAAAA==.Plut:BAEALgADCgEJAQABLgAECgcJAQAFAAAAAA==.',
Qu='Quinet:BAEBLgAECn8eAAMWAAgJiCJhCACHAghoDAAABgBhAGkMAAAFAFsAawwAAAUAXABqDAAABABRAGwMAAADAFYAbQwAAAEAVADqDAAABQBeAG4MAAABAEcAFgAICQUiYQgAhwIIaAwAAAYAYQBpDAAABABbAGsMAAAFAFwAagwAAAEAEABsDAAAAQBNAG0MAAABAFQA6gwAAAUAXgBuDAAAAQBHABcAAwm8HmwvAP0AA2kMAAABAEYAagwAAAMAUQBsDAAAAgBWAAAA.',
Ru='Rufio:BAEBLgAECn8dAAIYAAgJ6Rv3CwChAghoDAAABABeAGkMAAAFAFkAawwAAAUAWgBqDAAABQAzAGwMAAADAFQAbQwAAAEAEgDqDAAABQBSAG4MAAABACcAGAAICekb9wsAoQIIaAwAAAQAXgBpDAAABQBZAGsMAAAFAFoAagwAAAUAMwBsDAAAAwBUAG0MAAABABIA6gwAAAUAUgBuDAAAAQAnAAAA.',
Ry='Rytiou:BAECLgAFFH8QAAIQAAUJDBxOBQCuAQVoDAAABABSAGkMAAAEAEsAawwAAAQALQBqDAAAAQArAOoMAAADAFIAEAAFCQwcTgUArgEFaAwAAAQAUgBpDAAABABLAGsMAAAEAC0AagwAAAEAKwDqDAAAAwBSAC4ABAp/LQACEAAJCeckWQIAjAMAEAAJCeckWQIAjAMAAAA=.',
Sa='Saadxevok:BAEBLgAECn8YAAMRAAgJQRFCEADYAQhoDAAAAwA7AGkMAAADADEAawwAAAMARQBqDAAAAwAwAGwMAAAEAEgAbQwAAAMACADqDAAAAwAkAG4MAAACAAwAEQAICUERQhAA2AEIaAwAAAMAOwBpDAAAAwAxAGsMAAACAEUAagwAAAIAMABsDAAAAwBIAG0MAAABAAgA6gwAAAEAJABuDAAAAQAMAA8ABglTCDopACkBBmsMAAABABAAagwAAAEAEQBsDAAAAQARAG0MAAACAB4A6gwAAAIAJwBuDAAAAQAGAAEuAAUUBwkdAAkATSAA.Saadxm:BAEALgAECgcJDwABLgAFFAcJHQAJAE0gAA==.Saadxp:BAECLgAFFH8dAAMJAAcJTSDJAABZAgdoDAAABABiAGkMAAAFAF0AawwAAAUAYABqDAAABQBYAGwMAAADACAAbQwAAAEAVADqDAAABgBbAAkABglCJMkAAFkCBmgMAAADAGIAaQwAAAQAXQBrDAAABABgAGoMAAAEAFgAbQwAAAEAVADqDAAABABbABkABgncGe0BAA4CBmgMAAABAEkAaQwAAAEAHQBrDAAAAQBaAGoMAAABAE4AbAwAAAMAMwDqDAAAAgBKAC4ABAp/JQADCQAICX4mXAEA7wIACQAICX4mXAEA7wIAGQAFCQsfPCAAkQEAAAA=.Sanityvanish:BAEALgADCgYJBgABLgAECgIJAgAFAAAAAA==.',
Sg='Sgtgigachad:BAEALgADCgYJBgABLgAFFAMJBAAFAAAAAQ==.',
Sp='Spilt:BAECLgAFFH8YAAIVAAcJqhmqAQCMAgdoDAAABQBaAGkMAAAFAFQAawwAAAQALwBqDAAAAwAaAGwMAAABABAAbQwAAAEARgDqDAAABQBTABUABwmqGaoBAIwCB2gMAAAFAFoAaQwAAAUAVABrDAAABAAvAGoMAAADABoAbAwAAAEAEABtDAAAAQBGAOoMAAAFAFMALgAECn8dAAIVAAkJySThCgBtAwAVAAkJySThCgBtAwAAAA==.Spiltmonk:BAEBLgAECn8YAAIBAAYJWB8uHAD6AQZoDAAABABGAGkMAAAEAFEAawwAAAQAUgBqDAAABABMAGwMAAADAFIA6gwAAAUAVAABAAYJWB8uHAD6AQZoDAAABABGAGkMAAAEAFEAawwAAAQAUgBqDAAABABMAGwMAAADAFIA6gwAAAUAVAABLgAFFAcJGAAVAKoZAA==.',
Ta='Taku:BAEALgAECgYJBgABLgAECggJFQAPALQHAA==.Tatamagouche:BAECLgAFFH8LAAMCAAUJqQqtDQASAQVoDAAAAwAwAGkMAAACAAwAawwAAAIAEABqDAAAAQAJAOoMAAADACAAAgAFCakKrQ0AEgEFaAwAAAMAMABpDAAAAQAMAGsMAAACABAAagwAAAEACQDqDAAAAgAgABoAAgm2ABcdAHoAAmkMAAABAAEA6gwAAAEAAQAuAAQKfxYAAgIACAmCHKwQAKICAAIACAmCHKwQAKICAAAA.Taymeean:BAEALgAECgMJBAABLgAFFAMJBQAQAGQJAA==.Tayvok:BAECLgAFFH8FAAIQAAMJZAkyGgDXAANoDAAAAgAOAGkMAAACADAA6gwAAAEACQAQAAMJZAkyGgDXAANoDAAAAgAOAGkMAAACADAA6gwAAAEACQAuAAQKfycAAhAACAkvHbkFAEwCABAACAkvHbkFAEwCAAAA.',
Te='Tentickles:BAECLgAFFH8MAAIJAAQJjB/QAgCNAQRoDAAAAwBIAGkMAAADAFsAawwAAAIAYQDqDAAABAA9AAkABAmMH9ACAI0BBGgMAAADAEgAaQwAAAMAWwBrDAAAAgBhAOoMAAAEAD0ALgAECn8UAAIJAAgJcSJvCAD9AgAJAAgJcSJvCAD9AgABLgAFFAcJHAABALgeAA==.',
Th='Thecheatt:BAEBLgAECn8oAAMLAAgJ1SJBBgDOAghoDAAABgBXAGkMAAAGAGEAawwAAAcAYgBqDAAABgBdAGwMAAAGAFkAbQwAAAIAWgDqDAAABgBfAG4MAAABAEAACwAICdUiQQYAzgIIaAwAAAUAVwBpDAAABABhAGsMAAAFAGIAagwAAAQAXQBsDAAAAwBZAG0MAAACAFoA6gwAAAMAXwBuDAAAAQBAAAoABgmfFuVJAH0BBmgMAAABABAAaQwAAAIASgBrDAAAAgA2AGoMAAACADIAbAwAAAMATwDqDAAAAwA/AAAA.',
Vi='Vigiz:BAEALgAECgUJBQAAAA==.Vilexie:BAEALgADCgUJBQAAAA==.',
Wa='Wafflé:BAEALgAECgIJAgAAAA==.',
Wh='Whitecrosses:BAEALgAECgEJAQABLgAECgYJFwASABwVAA==.',
Za='Zargan:BAEALgAECgUJBgABLgAECggJFQAPALQHAA==.',
Ze='Zertzz:BAEALgAECgUJCAABLgAFFAQJDAAJAIofAA==.',
Zi='Zinia:BAEBLgAECn8XAAIbAAYJmxl4DwDCAQZoDAAABQBXAGkMAAAFAEYAawwAAAUAOQBqDAAAAgA4AGwMAAACAEcA6gwAAAQAKQAbAAYJmxl4DwDCAQZoDAAABQBXAGkMAAAFAEYAawwAAAUAOQBqDAAAAgA4AGwMAAACAEcA6gwAAAQAKQAAAA==.',
Zz='Zzertz:BAECLgAFFH8MAAIJAAQJih/oAgCLAQRoDAAABABcAGkMAAADAFMAawwAAAIAUgDqDAAAAwBAAAkABAmKH+gCAIsBBGgMAAAEAFwAaQwAAAMAUwBrDAAAAgBSAOoMAAADAEAALgAECn8rAAIJAAgJ/yI7BgApAwAJAAgJ/yI7BgApAwAAAA==.',
['Àb']='Àbeel:BAEALgAECgMJAwABLgAECggJKAAIAFsaAA==.Àbel:BAEBLgAECn8oAAMIAAgJWxpjBgASAghoDAAABwBXAGkMAAAIAFQAawwAAAYAWgBqDAAABQBeAGwMAAADADAAbQwAAAIAIwDqDAAACABZAG4MAAABACQACAAHCWwcYwYAEgIHaAwAAAcAVwBpDAAACABUAGsMAAAFAFoAagwAAAUAXgBsDAAAAwAwAOoMAAAIAFkAbgwAAAEAJAAHAAIJPBSgUgCWAAJrDAAAAQBDAG0MAAACACMAAAA=.Àble:BAEALgADCgQJCQABLgAECggJKAAIAFsaAA==.',
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
