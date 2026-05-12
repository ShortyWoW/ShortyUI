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

local lookup = {'Monk-Windwalker','Shaman-Enhancement','Monk-Mistweaver','Paladin-Retribution','Druid-Feral','Unknown-Unknown','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','Warrior-Fury','Warrior-Protection','Paladin-Holy','Mage-Arcane','Paladin-Protection','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Monk-Brewmaster','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Mage-Frost','Warlock-Demonology','Warlock-Destruction','DemonHunter-Havoc','Priest-Discipline','DemonHunter-Devourer',}
local provider = {region='US',realm='Dalaran',name='US',type='subscribers',zone=46,date='2026-05-12',data={Ad='Adansso:BAEBLgAECn8rAAIBAAgJfg/qFwB8AQhoDAAACAAoAGkMAAAHADoAawwAAAYAQwBqDAAABAAlAGwMAAAFABcAbQwAAAIAFgDqDAAABwAcAG4MAAAEACUAAQAICX4P6hcAfAEIaAwAAAgAKABpDAAABwA6AGsMAAAGAEMAagwAAAQAJQBsDAAABQAXAG0MAAACABYA6gwAAAcAHABuDAAABAAlAAAA.',
Al='Aliastei:BAEALgADCgQJBAABLgAECggJHwACAPMXAA==.',
Ap='Apawcowlypse:BAEALgADCgcJDAABLgAFFAQJCwADAPcLAA==.',
As='Ashko:BAEBLgAECn8bAAIEAAcJqhlPMwDGAQdoDAAABgBBAGkMAAAFAFMAawwAAAQAUQBqDAAABABGAGwMAAADAFAAbQwAAAEAHQDqDAAABAA1AAQABwmqGU8zAMYBB2gMAAAGAEEAaQwAAAUAUwBrDAAABABRAGoMAAAEAEYAbAwAAAMAUABtDAAAAQAdAOoMAAAEADUAAAA=.',
Ay='Ayodele:BAEALgAECggJEgAAAA==.',
Az='Azurlia:BAEALgAECgYJEQAAAA==.',
Ba='Babycora:BAEALgAECgYJBwABLgAECggJIwAFAAcdAA==.Bagelandlox:BAEALgADCgEJAQABLgAECgYJDAAGAAAAAA==.Barrui:BAECLgAFFH8fAAMHAAgJRBnlAAA+AghoDAAABgBBAGkMAAAGAGAAawwAAAUAOwBqDAAABABOAGwMAAABAAQAbQwAAAEAJADqDAAABwBcAG4MAAABAGEABwAHCUcc5QAAPgIHaAwAAAYAQQBpDAAABQBSAGsMAAAEADsAagwAAAQATgBtDAAAAQAkAOoMAAAHAFwAbgwAAAEAYQAIAAMJWRBwAgAVAQNpDAAAAQBgAGsMAAABABgAbAwAAAEABAAuAAQKfzMAAwcACQlnJOkFADMDAAcACQnwIukFADMDAAgABgkTIS8EAHACAAAA.',
Be='Belynila:BAECLgAFFH8GAAIJAAIJRxbuGQCrAAJoDAAABABEAGkMAAACAC0ACQACCUcW7hkAqwACaAwAAAQARABpDAAAAgAtAC4ABAp/LwACCQAJCdoduwMA0QIACQAJCdoduwMA0QIAAAA=.',
Br='Briggoker:BAEALgAECgMJAwAAAA==.Brigmahf:BAEALgAECgQJCQABLgAECgMJAwAGAAAAAA==.',
Ca='Carbonarra:BAEBLgAECn8gAAIKAAYJ7BuTIQBvAQZoDAAABwBbAGkMAAAGADoAawwAAAYAQwBqDAAABAA+AGwMAAAEAEgA6gwAAAUAQwAKAAYJ7BuTIQBvAQZoDAAABwBbAGkMAAAGADoAawwAAAYAQwBqDAAABAA+AGwMAAAEAEgA6gwAAAUAQwAAAA==.Catcam:BAEALgAECgYJBgAAAA==.',
Ch='Chetegos:BAEALgADCgYJBgABLgAECgkJMwALAM4jAA==.Chíefsquirel:BAEALgAECgYJDAAAAA==.',
Da='Dadbanger:BAECLgAFFH8fAAMBAAgJCR44AABxAghoDAAABQBiAGkMAAAFAGAAawwAAAUASgBqDAAABQBXAGwMAAADAEQAbQwAAAEAJQDqDAAABgBhAG4MAAABAEEAAQAHCZweOAAAcQIHaAwAAAUAYgBpDAAABQBgAGsMAAAFAEoAagwAAAUAVwBtDAAAAQAlAOoMAAAGAGEAbgwAAAEAQQADAAEJkgVBFgBJAAFsDAAAAwAOAC4ABAp/IgACAQAICWkmCQIAhAMAAQAICWkmCQIAhAMAAAA=.Daeke:BAEALgADCgUJBQABLgAECgQJBwAGAAAAAA==.Daekeypoo:BAEALgAECgQJBwAAAA==.Darkvirgo:BAEALgAFFAMJAwABLgAFFAYJGAAJAD8VAA==.',
De='Deathbeaver:BAEALgAECgQJBQABLgAECggJOAAEACkdAA==.Destrom:BAEALgAECggJEQAAAA==.',
Ep='Epilepticc:BAECLgAFFH8IAAIEAAQJTRuEFABjAQRoDAAAAwBCAGkMAAACAFUAawwAAAEAMgDqDAAAAgBNAAQABAlNG4QUAGMBBGgMAAADAEIAaQwAAAIAVQBrDAAAAQAyAOoMAAACAE0ALgAECn87AAIEAAkJ6yKBBwDsAgAEAAkJ6yKBBwDsAgAAAA==.',
Et='Ethalon:BAECLgAFFH8IAAIMAAQJiwxPFAAfAQRoDAAAAwBIAGkMAAACABkAawwAAAEADwDqDAAAAgAOAAwABAmLDE8UAB8BBGgMAAADAEgAaQwAAAIAGQBrDAAAAQAPAOoMAAACAA4ALgAECn8jAAMMAAkJHRonGABRAgAMAAkJHRonGABRAgAEAAIJlBMJAwFAAAAAAA==.',
Fa='Fallhp:BAEALgADCgYJBgABLgAFFAcJEAAMAPcTAA==.Fallill:BAEALgAECgIJAgABLgAFFAcJEAAMAPcTAA==.Falosso:BAECLgAFFH8QAAIMAAcJ9xMBAwAdAgdoDAAAAgA0AGkMAAACADUAawwAAAIAQABqDAAAAgBLAGwMAAADAA0AbQwAAAEAHwDqDAAABABDAAwABwn3EwEDAB0CB2gMAAACADQAaQwAAAIANQBrDAAAAgBAAGoMAAACAEsAbAwAAAMADQBtDAAAAQAfAOoMAAAEAEMALgAECn8yAAMMAAkJjyDoBADwAgAMAAkJjyDoBADwAgAEAAEJPQozEwE5AAAAAA==.',
Ga='Garlooth:BAEBLgAECn8hAAINAAgJqR4QAQBmAghoDAAABQBTAGkMAAAFAFMAawwAAAUATQBqDAAAAwAyAGwMAAAEAEkAbQwAAAMAXgDqDAAABQA+AG4MAAADAEoADQAICakeEAEAZgIIaAwAAAUAUwBpDAAABQBTAGsMAAAFAE0AagwAAAMAMgBsDAAABABJAG0MAAADAF4A6gwAAAUAPgBuDAAAAwBKAAAA.',
Gl='Glizzygary:BAEALgAFFAQJCAAAAQ==.',
Gr='Grimvalor:BAEBLgAECn84AAMEAAgJKR0NGgBDAghoDAAACQBcAGkMAAAIAEAAawwAAAkAUgBqDAAACABYAGwMAAAHAFIAbQwAAAQASwDqDAAACQBSAG4MAAACACoABAAICSkdDRoAQwIIaAwAAAgAXABpDAAACABAAGsMAAAIAFIAagwAAAcAWABsDAAABgBSAG0MAAAEAEsA6gwAAAgAUgBuDAAAAgAqAA4ABQnPCsYpAGUABWgMAAABAA8AawwAAAEALABqDAAAAQAsAGwMAAABACIA6gwAAAEADwAAAA==.Grunclaws:BAEALgAECgYJBgABLgAECgkJGwAEAKoZAA==.Grunjitsu:BAEALgAECgkJAQABLgAECgkJGwAEAKoZAA==.Grunsy:BAEALgAECgcJAgABLgAECgkJGwAEAKoZAA==.',
Ha='Haf:BAEBLgAECn8pAAIOAAkJ8hEjCwCgAQloDAAABwA9AGkMAAAGAEIAawwAAAYARwBqDAAABQAjAGwMAAAFADYAbQwAAAMAFQDqDAAABgAvAG4MAAACABYAbwwAAAEAFwAOAAkJ8hEjCwCgAQloDAAABwA9AGkMAAAGAEIAawwAAAYARwBqDAAABQAjAGwMAAAFADYAbQwAAAMAFQDqDAAABgAvAG4MAAACABYAbwwAAAEAFwAAAA==.',
He='Hertzmuch:BAEALgADCgYJDgABLgAFFAQJCwADAPcLAA==.',
Ho='Holeighfuk:BAEALgAECgYJBgAAAA==.',
Jo='Joicountdown:BAEBLgAFFH8pAAIFAAgJ+CYDAAAdAwhoDAAABwBjAGkMAAAHAGQAawwAAAcAYgBqDAAABgBkAGwMAAADAGQAbQwAAAIAZADqDAAACABkAG4MAAABAGQABQAICfgmAwAAHQMIaAwAAAcAYwBpDAAABwBkAGsMAAAHAGIAagwAAAYAZABsDAAAAwBkAG0MAAACAGQA6gwAAAgAZABuDAAAAQBkAAEuAAQKBgkGAAYAAAAA.',
Ka='Kautheros:BAEBLgAECn8cAAQPAAgJpwtXDgBzAQhoDAAABAAIAGkMAAAEABkAawwAAAQAOwBqDAAABAAfAGwMAAADACIAbQwAAAMACQDqDAAABAAmAG4MAAACAB0ADwAICacLVw4AcwEIaAwAAAIACABpDAAAAgAZAGsMAAACADsAagwAAAIAHwBsDAAAAQAiAG0MAAADAAkA6gwAAAMAJgBuDAAAAgAdABAABglSCS4zAOoABmgMAAABAB0AaQwAAAEAGABrDAAAAgAcAGoMAAABACQAbAwAAAIAFwDqDAAAAQAMABEAAwmaBv0UAFgAA2gMAAABAAkAaQwAAAEAGABqDAAAAQAaAAAA.',
Kr='Kroxychi:BAEALgAECgcJCwAAAA==.Kroxypurple:BAEALgADCgIJAgABLgAECgcJCwAGAAAAAA==.',
Ku='Kungfused:BAECLgAFFH8LAAIDAAQJ9wtPFgD5AARoDAAABAAqAGkMAAAEACUAawwAAAIAFwDqDAAAAQATAAMABAn3C08WAPkABGgMAAAEACoAaQwAAAQAJQBrDAAAAgAXAOoMAAABABMALgAECn9DAAMDAAgJ+R/ACgClAgADAAgJ+R/ACgClAgABAAgJUxNTEwCsAQAAAA==.',
Le='Leenfiey:BAECLgAFFH8JAAMSAAMJXCMaEgA3AQNoDAAAAwBfAGkMAAADAFEA6gwAAAMAXQASAAMJXCMaEgA3AQNoDAAAAgBfAGkMAAACAFEA6gwAAAIAXQABAAMJRww6FwCsAANoDAAAAQAAAGkMAAABADEA6gwAAAEALAAuAAQKfxgAAhIABgkrJd0UAGUCABIABgkrJd0UAGUCAAAA.Lennather:BAEBLgAECn8zAAIBAAkJHCW+AABhAwloDAAABwBjAGkMAAAHAGEAawwAAAYAWwBqDAAABgBOAGwMAAAGAGAAbQwAAAUAXgDqDAAABwBdAG4MAAAFAF8AbwwAAAIAWgABAAkJHCW+AABhAwloDAAABwBjAGkMAAAHAGEAawwAAAYAWwBqDAAABgBOAGwMAAAGAGAAbQwAAAUAXgDqDAAABwBdAG4MAAAFAF8AbwwAAAIAWgAAAA==.',
Li='Lidrunka:BAEBLgAECn8WAAMBAAgJbhTVGwD9AQhoDAAABABKAGkMAAAEAD8AawwAAAMARABqDAAAAgAjAGwMAAACADYAbQwAAAEAHADqDAAABQA/AG4MAAABAAwAAQAICcoT1RsA/QEIaAwAAAMASgBpDAAAAwA0AGsMAAACAEQAagwAAAIAIwBsDAAAAgA2AG0MAAABABwA6gwAAAQAPwBuDAAAAQAMABIABAkWFAovAO8ABGgMAAABACwAaQwAAAEAPwBrDAAAAQA7AOoMAAABACUAAAA=.',
['Lé']='Lépewpew:BAEBLgAECn8YAAITAAcJSRL7EwCQAQdoDAAABQA+AGkMAAAFADMAawwAAAUAOwBqDAAAAwBNAGwMAAABACYA6gwAAAQAOgBuDAAAAQAKABMABwlJEvsTAJABB2gMAAAFAD4AaQwAAAUAMwBrDAAABQA7AGoMAAADAE0AbAwAAAEAJgDqDAAABAA6AG4MAAABAAoAAAA=.',
Ma='Mattimus:BAEBLgAECn8VAAMUAAYJXg7zVwAcAQZoDAAABAA9AGkMAAAEACUAawwAAAUAGgBqDAAAAwAkAGwMAAACABQA6gwAAAMAJQAUAAYJXg7zVwAcAQZoDAAABAA9AGkMAAADACUAawwAAAQAGgBqDAAAAgAkAGwMAAACABQA6gwAAAIAJQAVAAQJ+QK2cAB8AARpDAAAAQABAGsMAAABAAkAagwAAAEACQDqDAAAAQAMAAAA.',
['Má']='Mákí:BAEALgAECgYJEAAAAA==.',
Na='Natebanger:BAEALgAECgYJDAABLgAFFAgJHwABAAkeAA==.',
Ne='Nethertank:BAEALgAECgQJBAABLgAECggJGwAWAJAWAA==.',
No='Noeyednuck:BAEALgAECgQJCQABLgAECgkJKwAUAIseAA==.',
Nu='Nuckshott:BAEBLgAECn8rAAIUAAkJix79CgCfAgloDAAABgBFAGkMAAAGAFgAawwAAAYASwBqDAAABQBZAGwMAAAFAFgAbQwAAAQATgDqDAAABQBWAG4MAAAEAEQAbwwAAAIARQAUAAkJix79CgCfAgloDAAABgBFAGkMAAAGAFgAawwAAAYASwBqDAAABQBZAGwMAAAFAFgAbQwAAAQATgDqDAAABQBWAG4MAAAEAEQAbwwAAAIARQAAAA==.',
Og='Ogx:BAEALgAECgQJBQABLgAECgkJGwAEAKoZAA==.',
Ol='Olgass:BAEALgADCgIJAgABLgAECggJJgAXAMEiAA==.',
Pl='Ploots:BAEALgAECgcJAQAAAA==.Plut:BAEALgADCgEJAQABLgAECgcJAQAGAAAAAA==.',
Pu='Purlok:BAEALgAECgkJAwABLgAECgkJGwAEAKoZAA==.',
Qu='Quinet:BAEBLgAECn8mAAMXAAgJwSICDQCVAghoDAAABwBhAGkMAAAGAFsAawwAAAYAXABqDAAABQBRAGwMAAAEAFcAbQwAAAIAWADqDAAABgBeAG4MAAACAEcAFwAICToiAg0AlQIIaAwAAAcAYQBpDAAABQBbAGsMAAAGAFwAagwAAAEAEABsDAAAAgBNAG0MAAACAFgA6gwAAAYAXgBuDAAAAgBHABgAAwnKHnEvAP0AA2kMAAABAEYAagwAAAQAUQBsDAAAAgBXAAAA.Quinman:BAEBLgAECn8aAAQTAAkJRBrFBwA/AgloDAAABQBBAGkMAAAEADMAawwAAAQATwBqDAAAAgAnAGwMAAACAGEAbQwAAAIAOwDqDAAABABBAG4MAAACAD0AbwwAAAEAOgATAAkJixfFBwA/AgloDAAAAQA8AGkMAAABAAAAawwAAAEATwBqDAAAAgAnAGwMAAACAGEAbQwAAAIAOwDqDAAAAwBBAG4MAAACAD0AbwwAAAEAOgAVAAQJWhWQWQDfAARoDAAAAwBBAGkMAAADADMAawwAAAMAMQDqDAAAAQA0ABQAAQkVGBy8AEAAAWgMAAABAD0AAAA=.Quinroxx:BAEBLgAECn8gAAIWAAgJXCN8KwDFAghoDAAABQBiAGkMAAAFAFsAawwAAAUAXwBqDAAABQBeAGwMAAADAFoAbQwAAAIAUwDqDAAABgBhAG4MAAABAE0AFgAICVwjfCsAxQIIaAwAAAUAYgBpDAAABQBbAGsMAAAFAF8AagwAAAUAXgBsDAAAAwBaAG0MAAACAFMA6gwAAAYAYQBuDAAAAQBNAAEuAAQKCQkaABMARBoA.Quinvinvin:BAEALgAECgcJDQABLgAECgkJGgATAEQaAA==.',
Ri='Rispirvoke:BAEALgADCgUJBgABLgAFFAUJBwAVAHUXAA==.',
Ro='Ronimus:BAEALgAECgEJAQAAAA==.',
Ru='Rufio:BAECLgAFFH8IAAIZAAIJeQ6UEACcAAJoDAAABQA2AGkMAAADABMAGQACCXkOlBAAnAACaAwAAAUANgBpDAAAAwATAC4ABAp/HwACGQAICekb9gsAoQIAGQAICekb9gsAoQIAAAA=.',
Ry='Rytiou:BAECLgAFFH8QAAIQAAUJGxxXBQCuAQVoDAAABABSAGkMAAAEAEsAawwAAAQALgBqDAAAAQArAOoMAAADAFIAEAAFCRscVwUArgEFaAwAAAQAUgBpDAAABABLAGsMAAAEAC4AagwAAAEAKwDqDAAAAwBSAC4ABAp/LQACEAAJCeckWQIAjAMAEAAJCeckWQIAjAMAAAA=.',
Sa='Saadxevok:BAEBLgAECn8YAAMRAAgJQRFLEADYAQhoDAAAAwA7AGkMAAADADEAawwAAAMARQBqDAAAAwAwAGwMAAAEAEgAbQwAAAMACADqDAAAAwAkAG4MAAACAAwAEQAICUERSxAA2AEIaAwAAAMAOwBpDAAAAwAxAGsMAAACAEUAagwAAAIAMABsDAAAAwBIAG0MAAABAAgA6gwAAAEAJABuDAAAAQAMAA8ABglTCD0pACkBBmsMAAABABAAagwAAAEAEQBsDAAAAQARAG0MAAACAB4A6gwAAAIAJwBuDAAAAQAGAAEuAAUUCAkjAAkAZB4A.Saadxm:BAEALgAECgcJDwABLgAFFAgJIwAJAGQeAA==.Saadxp:BAECLgAFFH8jAAMJAAgJZB7JAABZAghoDAAABQBjAGkMAAAGAGAAawwAAAYAYABqDAAABgBYAGwMAAADACAAbQwAAAEAVADqDAAABwBeAG4MAAABACkACQAHCV0hyQAAWQIHaAwAAAQAYwBpDAAABQBgAGsMAAAFAGAAagwAAAUAWABtDAAAAQBUAOoMAAAFAF4AbgwAAAEAKQAaAAYJ5RnxAQANAgZoDAAAAQBJAGkMAAABAB0AawwAAAEAWgBqDAAAAQBOAGwMAAADADMA6gwAAAIASgAuAAQKfyUAAwkACAmHJkwDAOMCAAkACAmHJkwDAOMCABoABQkLHz4gAJEBAAAA.Sanityvanish:BAEALgAECgIJAwABLgAECgMJBAAGAAAAAA==.',
Sg='Sgtgigachad:BAEALgADCgYJBgABLgAFFAQJCAAGAAAAAQ==.',
Sp='Spilt:BAECLgAFFH8ZAAIWAAcJoBmvAQCMAgdoDAAABQBaAGkMAAAFAFQAawwAAAQALwBqDAAAAwAaAGwMAAABABAAbQwAAAEARgDqDAAABgBTABYABwmgGa8BAIwCB2gMAAAFAFoAaQwAAAUAVABrDAAABAAvAGoMAAADABoAbAwAAAEAEABtDAAAAQBGAOoMAAAGAFMALgAECn8dAAIWAAkJySTjCgBtAwAWAAkJySTjCgBtAwAAAA==.Spiltmonk:BAEBLgAECn8YAAIBAAYJWh80HAD6AQZoDAAABABGAGkMAAAEAFEAawwAAAQAUgBqDAAABABMAGwMAAADAFIA6gwAAAUAVAABAAYJWh80HAD6AQZoDAAABABGAGkMAAAEAFEAawwAAAQAUgBqDAAABABMAGwMAAADAFIA6gwAAAUAVAABLgAFFAcJGQAWAKAZAA==.',
Su='Sunjo:BAEALgAECgkJBAABLgAECgkJGwAEAKoZAA==.',
Ta='Taku:BAEALgAECgcJDQABLgAECggJHAAPAKcLAA==.Taymeean:BAEALgAECgMJBAABLgAFFAMJBgAQAGQJAA==.Tayvok:BAECLgAFFH8GAAIQAAMJZAnvKADJAANoDAAAAgAOAGkMAAADADAA6gwAAAEACQAQAAMJZAnvKADJAANoDAAAAgAOAGkMAAADADAA6gwAAAEACQAuAAQKfywAAhAACQmQHFwFAKoCABAACQmQHFwFAKoCAAAA.',
Te='Tentickles:BAECLgAFFH8MAAIJAAQJlx+bBgCFAQRoDAAAAwBIAGkMAAADAFsAawwAAAIAYQDqDAAABAA9AAkABAmXH5sGAIUBBGgMAAADAEgAaQwAAAMAWwBrDAAAAgBhAOoMAAAEAD0ALgAECn8UAAIJAAgJeiJyCAD9AgAJAAgJeiJyCAD9AgABLgAFFAgJHwABAAkeAA==.Tetakoawara:BAEALgAECgUJCwABLgAFFAMJCQASAFwjAA==.',
Th='Thecheatt:BAEBLgAECn8zAAMLAAkJziOSAgDCAgloDAAACABhAGkMAAAIAGEAawwAAAkAYgBqDAAABwBdAGwMAAAHAF0AbQwAAAIAWgDqDAAABwBfAG4MAAACAEcAbwwAAAEAWQALAAkJziOSAgDCAgloDAAABwBhAGkMAAAGAGEAawwAAAcAYgBqDAAABQBdAGwMAAAEAF0AbQwAAAIAWgDqDAAABABfAG4MAAACAEcAbwwAAAEAWQAKAAYJnxbqSQB9AQZoDAAAAQAQAGkMAAACAEoAawwAAAIANgBqDAAAAgAyAGwMAAADAE8A6gwAAAMAPwAAAA==.',
Vi='Vigiz:BAEALgAECgYJBgAAAA==.Vilexie:BAEALgAECggJCQAAAA==.',
Wa='Wafflé:BAEALgAECgIJAgAAAA==.',
Wh='Whitecrosses:BAEALgAECgEJAQABLgAECgcJGAATAEkSAA==.',
Wi='Wiskystagger:BAEALgADCgEJAgAAAA==.',
Za='Zargan:BAEALgAECgcJCAABLgAECggJHAAPAKcLAA==.',
Ze='Zertzz:BAEALgAFFAEJAQABLgAFFAQJEAAJALIfAA==.',
Zi='Zibbz:BAEBLgAECn8nAAMQAAkJzCC3AgAMAwloDAAABQBXAGkMAAAFAFsAawwAAAUAVABqDAAABABVAGwMAAAGAFIAbQwAAAQAVwDqDAAABQBWAG4MAAAEAFsAbwwAAAEAOwAQAAkJzCC3AgAMAwloDAAABABXAGkMAAAEAFsAawwAAAQAVABqDAAAAwBVAGwMAAAFAFIAbQwAAAQAVwDqDAAABABWAG4MAAADAFsAbwwAAAEAOwARAAcJyxqEAwD0AQdoDAAAAQBOAGkMAAABAFAAawwAAAEARwBqDAAAAQBGAGwMAAABAEcA6gwAAAEAUwBuDAAAAQAZAAAA.Zinia:BAEBLgAECn8fAAICAAgJ8xcPBwDeAQhoDAAABgBXAGkMAAAGAFIAawwAAAYAOQBqDAAAAwA6AGwMAAADAEcAbQwAAAEAMQDqDAAABQBCAG4MAAABAA4AAgAICfMXDwcA3gEIaAwAAAYAVwBpDAAABgBSAGsMAAAGADkAagwAAAMAOgBsDAAAAwBHAG0MAAABADEA6gwAAAUAQgBuDAAAAQAOAAAA.',
Zu='Zubbfist:BAEALgADCgcJBwABLgAECgkJJwAQAMwgAA==.Zubbrael:BAEBLgAECn8fAAMJAAgJYRliIwC9AQhoDAAABwBKAGkMAAAFAEMAawwAAAQAQgBqDAAAAwA3AGwMAAAEADYAbQwAAAEAUgDqDAAABgBCAG4MAAABACoACQAHCTwYYiMAvQEHaAwAAAUASgBpDAAAAwBDAGsMAAACAEIAagwAAAEANwBsDAAAAgA2AOoMAAAEAEIAbgwAAAEAKgAaAAcJgwlYHQBcAQdoDAAAAgAOAGkMAAACABUAawwAAAIAIwBqDAAAAgArAGwMAAACABIAbQwAAAEAEgDqDAAAAgATAAEuAAQKCQknABAAzCAA.Zubbz:BAEBLgAECn8nAAIbAAgJLB6THgCaAghoDAAABgBeAGkMAAAHAFgAawwAAAcAUwBqDAAABAA9AGwMAAAEAFcAbQwAAAIAJQDqDAAABwBYAG4MAAACADoAGwAICSwekx4AmgIIaAwAAAYAXgBpDAAABwBYAGsMAAAHAFMAagwAAAQAPQBsDAAABABXAG0MAAACACUA6gwAAAcAWABuDAAAAgA6AAEuAAQKCQknABAAzCAA.',
Zz='Zzertz:BAECLgAFFH8QAAIJAAQJsh9BBwB8AQRoDAAABQBcAGkMAAAEAFMAawwAAAMAVADqDAAABABAAAkABAmyH0EHAHwBBGgMAAAFAFwAaQwAAAQAUwBrDAAAAwBUAOoMAAAEAEAALgAECn8rAAIJAAgJ/yI6BgApAwAJAAgJ/yI6BgApAwAAAA==.',
['Àb']='Àbeel:BAEALgAECgMJAwABLgAECggJLwAIABYbAA==.Àbel:BAEBLgAECn8vAAMIAAgJFhtjBgASAghoDAAACABXAGkMAAAJAFQAawwAAAcAWgBqDAAABgBeAGwMAAAEAD0AbQwAAAIAIwDqDAAACQBZAG4MAAACACQACAAHCUYdYwYAEgIHaAwAAAcAVwBpDAAACABUAGsMAAAFAFoAagwAAAUAXgBsDAAABAA9AOoMAAAIAFkAbgwAAAEAJAAHAAcJkhbUFAB6AQdoDAAAAQBJAGkMAAABAE8AawwAAAIATgBqDAAAAQBdAG0MAAACACMA6gwAAAEAOwBuDAAAAQAUAAAA.Àble:BAEALgADCgQJCQABLgAECggJLwAIABYbAA==.',
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
