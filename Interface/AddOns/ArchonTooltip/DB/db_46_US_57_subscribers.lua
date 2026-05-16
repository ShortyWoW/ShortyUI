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

local lookup = {'Monk-Windwalker','Shaman-Enhancement','Monk-Mistweaver','Paladin-Retribution','Paladin-Holy','Mage-Frost','Unknown-Unknown','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','Warrior-Fury','Warrior-Protection','Mage-Arcane','Paladin-Protection','Druid-Feral','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Monk-Brewmaster','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Warlock-Demonology','Warlock-Destruction','DemonHunter-Havoc','Priest-Discipline','DeathKnight-Unholy','DeathKnight-Blood','DemonHunter-Devourer',}
local provider = {region='US',realm='Dalaran',name='US',type='subscribers',zone=46,date='2026-05-14',data={Ad='Adansso:BAEBLgAECn8rAAIBAAgJfg9SGwBvAQhoDAAACAAoAGkMAAAHADoAawwAAAYAQwBqDAAABAAlAGwMAAAFABcAbQwAAAIAFgDqDAAABwAcAG4MAAAEACUAAQAICX4PUhsAbwEIaAwAAAgAKABpDAAABwA6AGsMAAAGAEMAagwAAAQAJQBsDAAABQAXAG0MAAACABYA6gwAAAcAHABuDAAABAAlAAAA.',
Al='Aliastei:BAEALgADCgQJBAABLgAECggJJwACAN4ZAA==.',
Ap='Apawcowlypse:BAEALgADCgcJDAABLgAFFAQJDgADAPcLAA==.',
As='Ashko:BAEBLgAECn8gAAMEAAgJNBnNKgD6AQhoDAAABgBBAGkMAAAFAFMAawwAAAQAUQBqDAAABQBGAGwMAAAEAFEAbQwAAAIAKwDqDAAABQA1AG4MAAABACkABAAICTQZzSoA+gEIaAwAAAYAQQBpDAAABQBTAGsMAAAEAFEAagwAAAUARgBsDAAABABRAG0MAAACACsA6gwAAAQANQBuDAAAAQApAAUAAQmpClNxAC0AAeoMAAABABsAAAA=.',
Ay='Ayodele:BAEBLgAECn8XAAIGAAgJIBVJOQDgAQhoDAAABABLAGkMAAACAC4AawwAAAIAPQBqDAAABABFAGwMAAADADcAbQwAAAEAGwDqDAAABABIAG4MAAADACgABgAICSAVSTkA4AEIaAwAAAQASwBpDAAAAgAuAGsMAAACAD0AagwAAAQARQBsDAAAAwA3AG0MAAABABsA6gwAAAQASABuDAAAAwAoAAAA.',
Az='Azurlia:BAEALgAECgYJEQAAAA==.',
Ba='Babycora:BAEALgAECgYJBwAAAA==.Bagelandlox:BAEALgADCgEJAQABLgAECgYJDAAHAAAAAA==.Barrui:BAECLgAFFH8fAAMIAAgJRBlTAQAyAghoDAAABgBBAGkMAAAGAGAAawwAAAUAOwBqDAAABABOAGwMAAABAAQAbQwAAAEAJADqDAAABwBcAG4MAAABAGEACAAHCUccUwEAMgIHaAwAAAYAQQBpDAAABQBSAGsMAAAEADsAagwAAAQATgBtDAAAAQAkAOoMAAAHAFwAbgwAAAEAYQAJAAMJWRBwAgAVAQNpDAAAAQBgAGsMAAABABgAbAwAAAEABAAuAAQKfzgAAwgACQlwJOkFADMDAAgACQnwIukFADMDAAkABgkfIS8EAHACAAAA.',
Be='Belynila:BAECLgAFFH8GAAIKAAIJRxbIGwClAAJoDAAABABEAGkMAAACAC0ACgACCUcWyBsApQACaAwAAAQARABpDAAAAgAtAC4ABAp/LwACCgAJCdodQQUAuQIACgAJCdodQQUAuQIAAAA=.',
Br='Briggoker:BAEALgAECgMJAwAAAA==.Brigmahf:BAEALgAECgQJCQABLgAECgMJAwAHAAAAAA==.',
Ca='Carbonarra:BAEBLgAECn8lAAILAAYJiB3LIACHAQZoDAAACABbAGkMAAAHAEAAawwAAAcAUgBqDAAABQBUAGwMAAAFAEgA6gwAAAUAQwALAAYJiB3LIACHAQZoDAAACABbAGkMAAAHAEAAawwAAAcAUgBqDAAABQBUAGwMAAAFAEgA6gwAAAUAQwAAAA==.Catcam:BAEALgAECgYJBgAAAA==.',
Ch='Chetegos:BAEALgADCgYJBgABLgAECgkJMwAMAM4jAA==.Chíefsquirel:BAEALgAECgYJDAAAAA==.',
Da='Dadbanger:BAECLgAFFH8jAAMBAAgJCR44AABxAghoDAAABgBiAGkMAAAGAGAAawwAAAUASgBqDAAABgBfAGwMAAADAEQAbQwAAAEAJQDqDAAABwBhAG4MAAABAEEAAQAHCZweOAAAcQIHaAwAAAYAYgBpDAAABgBgAGsMAAAFAEoAagwAAAYAXwBtDAAAAQAlAOoMAAAHAGEAbgwAAAEAQQADAAEJkgVBFgBJAAFsDAAAAwAOAC4ABAp/IgACAQAICWkmCQIAhAMAAQAICWkmCQIAhAMAAAA=.Daeke:BAEALgADCgUJBQABLgAECgQJBwAHAAAAAA==.Daekeypoo:BAEALgAECgQJBwAAAA==.Darkvirgo:BAEALgAFFAMJAwABLgAFFAYJHQAKAIgXAA==.',
De='Deathbeaver:BAEALgAECgQJBQABLgAECggJOwAEACkdAA==.Destrom:BAEALgAECgkJEgAAAA==.',
Ep='Epilepticc:BAECLgAFFH8LAAIEAAQJTRsIFgBfAQRoDAAABABCAGkMAAADAFUAawwAAAEAMgDqDAAAAwBNAAQABAlNGwgWAF8BBGgMAAAEAEIAaQwAAAMAVQBrDAAAAQAyAOoMAAADAE0ALgAECn87AAIEAAkJ6yL6CQDZAgAEAAkJ6yL6CQDZAgAAAA==.',
Et='Ethalon:BAECLgAFFH8IAAIFAAQJiwzSFQAeAQRoDAAAAwBIAGkMAAACABkAawwAAAEADwDqDAAAAgAOAAUABAmLDNIVAB4BBGgMAAADAEgAaQwAAAIAGQBrDAAAAQAPAOoMAAACAA4ALgAECn8jAAMFAAkJHRonGABRAgAFAAkJHRonGABRAgAEAAIJlBMgGgE4AAAAAA==.',
Fa='Fallhp:BAEALgADCgYJBgABLgAFFAcJFQAFAMAVAA==.Fallill:BAEALgAECgIJAgABLgAFFAcJFQAFAMAVAA==.Falosso:BAECLgAFFH8VAAIFAAcJwBVUAgBFAgdoDAAAAwA1AGkMAAADAEcAawwAAAMAQABqDAAAAwBLAGwMAAADAA0AbQwAAAEAHwDqDAAABQBQAAUABwnAFVQCAEUCB2gMAAADADUAaQwAAAMARwBrDAAAAwBAAGoMAAADAEsAbAwAAAMADQBtDAAAAQAfAOoMAAAFAFAALgAECn8yAAMFAAkJjyBCBgDfAgAFAAkJjyBCBgDfAgAEAAEJPQqTKwEyAAAAAA==.',
Ga='Garlooth:BAEBLgAECn8hAAINAAgJqR5KAQBZAghoDAAABQBTAGkMAAAFAFMAawwAAAUATQBqDAAAAwAyAGwMAAAEAEkAbQwAAAMAXgDqDAAABQA+AG4MAAADAEoADQAICakeSgEAWQIIaAwAAAUAUwBpDAAABQBTAGsMAAAFAE0AagwAAAMAMgBsDAAABABJAG0MAAADAF4A6gwAAAUAPgBuDAAAAwBKAAAA.',
Gl='Glizzygary:BAEALgAFFAQJCAAAAQ==.',
Gr='Grimvalor:BAEBLgAECn87AAMEAAgJKR3AIAAsAghoDAAACQBcAGkMAAAIAEAAawwAAAkAUgBqDAAACABYAGwMAAAIAFIAbQwAAAUASwDqDAAACQBSAG4MAAADACoABAAICSkdwCAALAIIaAwAAAgAXABpDAAACABAAGsMAAAIAFIAagwAAAcAWABsDAAABwBSAG0MAAAFAEsA6gwAAAgAUgBuDAAAAwAqAA4ABQnPCswrAGQABWgMAAABAA8AawwAAAEALABqDAAAAQAsAGwMAAABACIA6gwAAAEADwAAAA==.Grunclaws:BAEALgAECgYJBgABLgAECgkJIAAEADQZAA==.Grunjitsu:BAEALgAECgkJBQABLgAECgkJIAAEADQZAA==.Grunsy:BAEALgAECgcJAgABLgAECgkJIAAEADQZAA==.',
Ha='Haf:BAEBLgAECn8pAAIOAAkJ8hGoDACUAQloDAAABwA9AGkMAAAGAEIAawwAAAYARwBqDAAABQAjAGwMAAAFADYAbQwAAAMAFQDqDAAABgAvAG4MAAACABYAbwwAAAEAFwAOAAkJ8hGoDACUAQloDAAABwA9AGkMAAAGAEIAawwAAAYARwBqDAAABQAjAGwMAAAFADYAbQwAAAMAFQDqDAAABgAvAG4MAAACABYAbwwAAAEAFwAAAA==.',
He='Hertzmuch:BAEALgADCgYJDgABLgAFFAQJDgADAPcLAA==.',
Ho='Holeighfuk:BAEALgAECgYJBgAAAA==.',
Jo='Joicountdown:BAEBLgAFFH8qAAIPAAgJ+CYGAAAbAwhoDAAABwBjAGkMAAAHAGQAawwAAAcAYgBqDAAABgBkAGwMAAADAGQAbQwAAAIAZADqDAAACQBkAG4MAAABAGQADwAICfgmBgAAGwMIaAwAAAcAYwBpDAAABwBkAGsMAAAHAGIAagwAAAYAZABsDAAAAwBkAG0MAAACAGQA6gwAAAkAZABuDAAAAQBkAAEuAAQKBgkGAAcAAAAA.',
Ka='Kautheros:BAEBLgAECn8cAAQQAAgJpwvGDwBuAQhoDAAABAAIAGkMAAAEABkAawwAAAQAOwBqDAAABAAfAGwMAAADACIAbQwAAAMACQDqDAAABAAmAG4MAAACAB0AEAAICacLxg8AbgEIaAwAAAIACABpDAAAAgAZAGsMAAACADsAagwAAAIAHwBsDAAAAQAiAG0MAAADAAkA6gwAAAMAJgBuDAAAAgAdABEABglSCX86ANYABmgMAAABAB0AaQwAAAEAGABrDAAAAgAcAGoMAAABACQAbAwAAAIAFwDqDAAAAQAMABIAAwmaBk0WAFgAA2gMAAABAAkAaQwAAAEAGABqDAAAAQAaAAAA.',
Kr='Kroxychi:BAEALgAECgcJDQAAAA==.Kroxypurple:BAEALgADCgIJAgABLgAECgcJDQAHAAAAAA==.',
Ku='Kungfused:BAECLgAFFH8OAAIDAAQJ9wsGGAD4AARoDAAABQAqAGkMAAAFACUAawwAAAIAFwDqDAAAAgATAAMABAn3CwYYAPgABGgMAAAFACoAaQwAAAUAJQBrDAAAAgAXAOoMAAACABMALgAECn9JAAMDAAkJQx3ACgClAgADAAkJQx3ACgClAgABAAgJWhNGFgChAQAAAA==.',
Le='Leenfiey:BAECLgAFFH8KAAMTAAMJXCPiEgAzAQNoDAAAAwBfAGkMAAADAFEA6gwAAAQAXQATAAMJXCPiEgAzAQNoDAAAAgBfAGkMAAACAFEA6gwAAAIAXQABAAMJGA2sGACuAANoDAAAAQAAAGkMAAABADEA6gwAAAIAMgAuAAQKfxkAAxMABglMJd0UAGUCABMABgkrJd0UAGUCAAEAAQkdJVFOAGsAAAAA.Lennather:BAEBLgAECn8zAAIBAAkJHCUbAQBTAwloDAAABwBjAGkMAAAHAGEAawwAAAYAWwBqDAAABgBOAGwMAAAGAGAAbQwAAAUAXgDqDAAABwBdAG4MAAAFAF8AbwwAAAIAWgABAAkJHCUbAQBTAwloDAAABwBjAGkMAAAHAGEAawwAAAYAWwBqDAAABgBOAGwMAAAGAGAAbQwAAAUAXgDqDAAABwBdAG4MAAAFAF8AbwwAAAIAWgAAAA==.',
Li='Lidrunka:BAEBLgAECn8WAAMBAAgJbhTVGwD9AQhoDAAABABKAGkMAAAEAD8AawwAAAMARABqDAAAAgAjAGwMAAACADYAbQwAAAEAHADqDAAABQA/AG4MAAABAAwAAQAICcoT1RsA/QEIaAwAAAMASgBpDAAAAwA0AGsMAAACAEQAagwAAAIAIwBsDAAAAgA2AG0MAAABABwA6gwAAAQAPwBuDAAAAQAMABMABAkWFIUzAOUABGgMAAABACwAaQwAAAEAPwBrDAAAAQA7AOoMAAABACUAAAA=.',
['Lé']='Lépewpew:BAEBLgAECn8YAAIUAAcJSRLzFwB7AQdoDAAABQA+AGkMAAAFADMAawwAAAUAOwBqDAAAAwBNAGwMAAABACYA6gwAAAQAOgBuDAAAAQAKABQABwlJEvMXAHsBB2gMAAAFAD4AaQwAAAUAMwBrDAAABQA7AGoMAAADAE0AbAwAAAEAJgDqDAAABAA6AG4MAAABAAoAAAA=.',
Ma='Mattimus:BAEBLgAECn8VAAMVAAYJXg4dYgAPAQZoDAAABAA9AGkMAAAEACUAawwAAAUAGgBqDAAAAwAkAGwMAAACABQA6gwAAAMAJQAVAAYJXg4dYgAPAQZoDAAABAA9AGkMAAADACUAawwAAAQAGgBqDAAAAgAkAGwMAAACABQA6gwAAAIAJQAWAAQJ+QK2cAB8AARpDAAAAQABAGsMAAABAAkAagwAAAEACQDqDAAAAQAMAAAA.',
['Má']='Mákí:BAEALgAECgcJEgAAAA==.',
Na='Natebanger:BAEALgAECgYJDAABLgAFFAgJIwABAAkeAA==.',
Ne='Nethertank:BAEALgAECgQJBAABLgAECggJHgAGAJAWAA==.',
No='Noeyednuck:BAEALgAECgQJCQABLgAECgkJLAAVAIseAA==.',
Nu='Nuckshott:BAEBLgAECn8sAAIVAAkJix52DgCKAgloDAAABgBFAGkMAAAGAFgAawwAAAYASwBqDAAABQBZAGwMAAAFAFgAbQwAAAQATgDqDAAABgBWAG4MAAAEAEQAbwwAAAIARQAVAAkJix52DgCKAgloDAAABgBFAGkMAAAGAFgAawwAAAYASwBqDAAABQBZAGwMAAAFAFgAbQwAAAQATgDqDAAABgBWAG4MAAAEAEQAbwwAAAIARQAAAA==.',
Og='Ogx:BAEALgAECgQJBQABLgAECgkJIAAEADQZAA==.',
Ol='Olgass:BAEALgADCgIJAgABLgAECggJLQAXABMjAA==.',
Pu='Purlok:BAEALgAECgkJAwABLgAECgkJIAAEADQZAA==.',
Qu='Quindrox:BAEALgAECgkJCQABLgAECgkJGgAUAEQaAA==.Quinet:BAEBLgAECn8tAAMXAAgJEyNFDACtAghoDAAABwBhAGkMAAAHAFwAawwAAAcAXABqDAAABgBRAGwMAAAFAFwAbQwAAAMAWADqDAAABwBeAG4MAAADAEcAFwAICRMjRQwArQIIaAwAAAcAYQBpDAAABgBcAGsMAAAHAFwAagwAAAEAEABsDAAAAwBcAG0MAAADAFgA6gwAAAcAXgBuDAAAAwBHABgAAwnKHnEvAP0AA2kMAAABAEYAagwAAAUAUQBsDAAAAgBXAAAA.Quinman:BAEBLgAECn8aAAQUAAkJRBraCQAtAgloDAAABQBBAGkMAAAEADMAawwAAAQATwBqDAAAAgAnAGwMAAACAGEAbQwAAAIAOwDqDAAABABBAG4MAAACAD0AbwwAAAEAOgAUAAkJixfaCQAtAgloDAAAAQA8AGkMAAABAAAAawwAAAEATwBqDAAAAgAnAGwMAAACAGEAbQwAAAIAOwDqDAAAAwBBAG4MAAACAD0AbwwAAAEAOgAWAAQJWhWQWQDfAARoDAAAAwBBAGkMAAADADMAawwAAAMAMQDqDAAAAQA0ABUAAQkVGH/DAEAAAWgMAAABAD0AAAA=.Quinroxx:BAEBLgAECn8gAAIGAAgJXCN8KwDFAghoDAAABQBiAGkMAAAFAFsAawwAAAUAXwBqDAAABQBeAGwMAAADAFoAbQwAAAIAUwDqDAAABgBhAG4MAAABAE0ABgAICVwjfCsAxQIIaAwAAAUAYgBpDAAABQBbAGsMAAAFAF8AagwAAAUAXgBsDAAAAwBaAG0MAAACAFMA6gwAAAYAYQBuDAAAAQBNAAEuAAQKCQkaABQARBoA.Quinvinvin:BAEALgAECgcJDQABLgAECgkJGgAUAEQaAA==.',
Ri='Rispirvoke:BAEALgADCgUJBgABLgAFFAgJDQAWAIIYAA==.',
Ro='Ronimus:BAEALgAECgEJAQAAAA==.',
Ru='Rufio:BAECLgAFFH8IAAIZAAIJeQ7qEQCWAAJoDAAABQA2AGkMAAADABMAGQACCXkO6hEAlgACaAwAAAUANgBpDAAAAwATAC4ABAp/HwACGQAICekb9gsAoQIAGQAICekb9gsAoQIAAAA=.',
Ry='Rytiou:BAECLgAFFH8SAAIRAAUJKx1XBQCuAQVoDAAABABSAGkMAAAFAFYAawwAAAQALgBqDAAAAgBHAOoMAAADAFIAEQAFCSsdVwUArgEFaAwAAAQAUgBpDAAABQBWAGsMAAAEAC4AagwAAAIARwDqDAAAAwBSAC4ABAp/LQACEQAJCeckWQIAjAMAEQAJCeckWQIAjAMAAAA=.',
Sa='Saadxevok:BAEBLgAECn8YAAMSAAgJQRFLEADYAQhoDAAAAwA7AGkMAAADADEAawwAAAMARQBqDAAAAwAwAGwMAAAEAEgAbQwAAAMACADqDAAAAwAkAG4MAAACAAwAEgAICUERSxAA2AEIaAwAAAMAOwBpDAAAAwAxAGsMAAACAEUAagwAAAIAMABsDAAAAwBIAG0MAAABAAgA6gwAAAEAJABuDAAAAQAMABAABglTCD0pACkBBmsMAAABABAAagwAAAEAEQBsDAAAAQARAG0MAAACAB4A6gwAAAIAJwBuDAAAAQAGAAEuAAUUCAkjAAoAZB4A.Saadxm:BAEALgAECgcJDwABLgAFFAgJIwAKAGQeAA==.Saadxp:BAECLgAFFH8jAAMKAAgJZB7JAABZAghoDAAABQBjAGkMAAAGAGAAawwAAAYAYABqDAAABgBYAGwMAAADACAAbQwAAAEAVADqDAAABwBeAG4MAAABACkACgAHCV0hyQAAWQIHaAwAAAQAYwBpDAAABQBgAGsMAAAFAGAAagwAAAUAWABtDAAAAQBUAOoMAAAFAF4AbgwAAAEAKQAaAAYJ5RnxAQANAgZoDAAAAQBJAGkMAAABAB0AawwAAAEAWgBqDAAAAQBOAGwMAAADADMA6gwAAAIASgAuAAQKfyUAAwoACAmHJrcDAGADAAoACAmHJrcDAGADABoABQkLHz4gAJEBAAAA.Sanityvanish:BAEALgAECgIJAwABLgAECgMJBAAHAAAAAA==.',
Sg='Sgtgigachad:BAEALgADCgYJBgABLgAFFAQJCAAHAAAAAQ==.',
Sp='Spilt:BAECLgAFFH8ZAAIGAAcJoBmvAQCMAgdoDAAABQBaAGkMAAAFAFQAawwAAAQALwBqDAAAAwAaAGwMAAABABAAbQwAAAEARgDqDAAABgBTAAYABwmgGa8BAIwCB2gMAAAFAFoAaQwAAAUAVABrDAAABAAvAGoMAAADABoAbAwAAAEAEABtDAAAAQBGAOoMAAAGAFMALgAECn8dAAIGAAkJySTjCgBtAwAGAAkJySTjCgBtAwAAAA==.Spiltmonk:BAEBLgAECn8YAAIBAAYJWh80HAD6AQZoDAAABABGAGkMAAAEAFEAawwAAAQAUgBqDAAABABMAGwMAAADAFIA6gwAAAUAVAABAAYJWh80HAD6AQZoDAAABABGAGkMAAAEAFEAawwAAAQAUgBqDAAABABMAGwMAAADAFIA6gwAAAUAVAABLgAFFAcJGQAGAKAZAA==.',
Su='Sunjo:BAEALgAECgkJBAABLgAECgkJIAAEADQZAA==.',
Ta='Taku:BAEALgAECgcJDQABLgAECggJHAAQAKcLAA==.Taymeean:BAEALgAECgMJBAABLgAFFAMJBgARAGQJAA==.Tayvok:BAECLgAFFH8GAAIRAAMJZAktKwDJAANoDAAAAgAOAGkMAAADADAA6gwAAAEACQARAAMJZAktKwDJAANoDAAAAgAOAGkMAAADADAA6gwAAAEACQAuAAQKfy8AAhEACQmQHH8HAI4CABEACQmQHH8HAI4CAAAA.',
Te='Tentickles:BAECLgAFFH8MAAIKAAQJlx9nBwB/AQRoDAAAAwBIAGkMAAADAFsAawwAAAIAYQDqDAAABAA9AAoABAmXH2cHAH8BBGgMAAADAEgAaQwAAAMAWwBrDAAAAgBhAOoMAAAEAD0ALgAECn8UAAIKAAgJeiJyCAD9AgAKAAgJeiJyCAD9AgABLgAFFAgJIwABAAkeAA==.Tetakoawara:BAEALgAECgUJCwABLgAFFAMJCgATAFwjAA==.',
Th='Thecheatt:BAEBLgAECn8zAAMMAAkJziNGAwC1AgloDAAACABhAGkMAAAIAGEAawwAAAkAYgBqDAAABwBdAGwMAAAHAF0AbQwAAAIAWgDqDAAABwBfAG4MAAACAEcAbwwAAAEAWQAMAAkJziNGAwC1AgloDAAABwBhAGkMAAAGAGEAawwAAAcAYgBqDAAABQBdAGwMAAAEAF0AbQwAAAIAWgDqDAAABABfAG4MAAACAEcAbwwAAAEAWQALAAYJnxbqSQB9AQZoDAAAAQAQAGkMAAACAEoAawwAAAIANgBqDAAAAgAyAGwMAAADAE8A6gwAAAMAPwAAAA==.',
Ty='Tyära:BAEBLgAECn8dAAMbAAgJSwsmbwAiAQhoDAAABgAYAGkMAAAGACQAawwAAAUAPgBqDAAAAwAXAGwMAAACAB4AbQwAAAEADQDqDAAABQAUAG4MAAABAA4AGwAHCUEJJm8AIgEHaAwAAAUAEgBpDAAABQAZAGsMAAAEACYAagwAAAIAEwBsDAAAAQAeAOoMAAAEAA0AbgwAAAEADgAcAAcJtQrOHwDwAAdoDAAAAQAYAGkMAAABACQAawwAAAEAPgBqDAAAAQAXAGwMAAABAAcAbQwAAAEADQDqDAAAAQAUAAEuAAQKCAkpAAYAshgA.',
Vi='Vigiz:BAEALgAECgYJBgAAAA==.Vilexie:BAEALgAECggJDwAAAA==.',
['Vì']='Vìgïz:BAEALgAECgEJAQABLgAECgYJBgAHAAAAAA==.',
Wa='Wafflé:BAEALgAECgIJAgAAAA==.',
Wh='Whitecrosses:BAEALgAECgEJAQABLgAECgcJGAAUAEkSAA==.',
Wi='Wiskystagger:BAEALgADCgEJAgAAAA==.',
Za='Zargan:BAEALgAECgcJCAABLgAECggJHAAQAKcLAA==.',
Ze='Zertzz:BAEALgAFFAEJAQABLgAFFAUJFQAKACIgAA==.',
Zi='Zibbz:BAEBLgAECn8xAAMRAAkJlCPIAQBBAwloDAAABgBgAGkMAAAGAGMAawwAAAYAYgBqDAAABQBZAGwMAAAHAF8AbQwAAAYAXwDqDAAABgBbAG4MAAAGAFsAbwwAAAEAOwARAAkJlCPIAQBBAwloDAAABQBgAGkMAAAFAGMAawwAAAUAYgBqDAAABABZAGwMAAAGAF8AbQwAAAYAXwDqDAAABQBbAG4MAAAFAFsAbwwAAAEAOwASAAcJyxomBADoAQdoDAAAAQBOAGkMAAABAFAAawwAAAEARwBqDAAAAQBGAGwMAAABAEcA6gwAAAEAUwBuDAAAAQAZAAEuAAQKCQktAB0ALB4A.Zinia:BAEBLgAECn8nAAICAAgJ3hn/BgDuAQhoDAAABwBXAGkMAAAHAFIAawwAAAcAOQBqDAAABAA6AGwMAAAEAEwAbQwAAAIAMQDqDAAABgBCAG4MAAACACsAAgAICd4Z/wYA7gEIaAwAAAcAVwBpDAAABwBSAGsMAAAHADkAagwAAAQAOgBsDAAABABMAG0MAAACADEA6gwAAAYAQgBuDAAAAgArAAAA.',
Zu='Zubbfist:BAEALgADCgcJBwABLgAECgkJLQAdACweAA==.Zubbrael:BAEBLgAECn8fAAMKAAgJYRliIwC9AQhoDAAABwBKAGkMAAAFAEMAawwAAAQAQgBqDAAAAwA3AGwMAAAEADYAbQwAAAEAUgDqDAAABgBCAG4MAAABACoACgAHCTwYYiMAvQEHaAwAAAUASgBpDAAAAwBDAGsMAAACAEIAagwAAAEANwBsDAAAAgA2AOoMAAAEAEIAbgwAAAEAKgAaAAcJgwnoIABSAQdoDAAAAgAOAGkMAAACABUAawwAAAIAIwBqDAAAAgArAGwMAAACABIAbQwAAAEAEgDqDAAAAgATAAEuAAQKCQktAB0ALB4A.Zubbz:BAEBLgAECn8tAAMdAAgJLB6THgCaAghoDAAABwBeAGkMAAAIAFgAawwAAAgAUwBqDAAABQA9AGwMAAAFAFcAbQwAAAIAJQDqDAAACABYAG4MAAACADoAHQAICSwekx4AmgIIaAwAAAYAXgBpDAAABwBYAGsMAAAHAFMAagwAAAQAPQBsDAAABABXAG0MAAACACUA6gwAAAcAWABuDAAAAgA6ABkABgkhHJcQAKMBBmgMAAABAEoAaQwAAAEAUABrDAAAAQBQAGoMAAABADoAbAwAAAEAOwDqDAAAAQBBAAAA.',
Zz='Zzertz:BAECLgAFFH8VAAIKAAUJIiDdBgCHAQVoDAAABgBhAGkMAAAFAFMAawwAAAQAVABqDAAAAQBYAOoMAAAFAEAACgAFCSIg3QYAhwEFaAwAAAYAYQBpDAAABQBTAGsMAAAEAFQAagwAAAEAWADqDAAABQBAAC4ABAp/KwACCgAICf8iOgYAKQMACgAICf8iOgYAKQMAAAA=.',
['Àb']='Àbeel:BAEALgAECgMJAwABLgAECggJMAAJABYbAA==.Àbel:BAEBLgAECn8wAAMJAAgJFhtjBgASAghoDAAACABXAGkMAAAJAFQAawwAAAcAWgBqDAAABgBeAGwMAAAEAD0AbQwAAAIAIwDqDAAACgBZAG4MAAACACQACQAHCUYdYwYAEgIHaAwAAAcAVwBpDAAACABUAGsMAAAFAFoAagwAAAUAXgBsDAAABAA9AOoMAAAJAFkAbgwAAAEAJAAIAAcJkhYtGQBdAQdoDAAAAQBJAGkMAAABAE8AawwAAAIATgBqDAAAAQBdAG0MAAACACMA6gwAAAEAOwBuDAAAAQAUAAAA.Àble:BAEALgADCgQJCQABLgAECggJMAAJABYbAA==.',
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
