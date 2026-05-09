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

local lookup = {'Monk-Windwalker','Monk-Mistweaver','Paladin-Retribution','Priest-Holy','Unknown-Unknown','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','Warrior-Fury','Warrior-Protection','Paladin-Holy','Mage-Arcane','Paladin-Protection','Druid-Feral','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Monk-Brewmaster','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Mage-Frost','Warlock-Demonology','Warlock-Destruction','DemonHunter-Havoc','Priest-Discipline','DemonHunter-Devourer','Shaman-Enhancement',}
local provider = {region='US',realm='Dalaran',name='US',type='subscribers',zone=46,date='2026-05-08',data={Ad='Adansso:BAEBLgAECn8lAAIBAAgJOA4oFwBuAQhoDAAABwAkAGkMAAAGACsAawwAAAYAQwBqDAAABAAlAGwMAAAEABcAbQwAAAEAFgDqDAAABgAXAG4MAAADACUAAQAICTgOKBcAbgEIaAwAAAcAJABpDAAABgArAGsMAAAGAEMAagwAAAQAJQBsDAAABAAXAG0MAAABABYA6gwAAAYAFwBuDAAAAwAlAAAA.',
Ap='Apawcowlypse:BAEALgADCgcJDAABLgAFFAQJCwACAPcLAA==.',
As='Ashko:BAEBLgAECn8bAAIDAAcJpxlLLQDIAQdoDAAABgBBAGkMAAAFAFMAawwAAAQAUQBqDAAABABGAGwMAAADAFAAbQwAAAEAHQDqDAAABAA1AAMABwmnGUstAMgBB2gMAAAGAEEAaQwAAAUAUwBrDAAABABRAGoMAAAEAEYAbAwAAAMAUABtDAAAAQAdAOoMAAAEADUAAAA=.',
Ay='Ayodele:BAEALgAECgcJCAAAAA==.',
Az='Azurlia:BAEALgAECgYJEQAAAA==.',
Ba='Babycora:BAEALgAECgYJBwABLgAECgkJLQAEAOsdAA==.Bagelandlox:BAEALgADCgEJAQABLgAECgYJDAAFAAAAAA==.Barrui:BAECLgAFFH8fAAMGAAgJdhp/AABPAghoDAAABgBNAGkMAAAGAGAAawwAAAUAOwBqDAAABABOAGwMAAABAAQAbQwAAAEAKADqDAAABwBiAG4MAAABAGEABgAHCawdfwAATwIHaAwAAAYATQBpDAAABQBSAGsMAAAEADsAagwAAAQATgBtDAAAAQAoAOoMAAAHAGIAbgwAAAEAYQAHAAMJWRBuAgAVAQNpDAAAAQBgAGsMAAABABgAbAwAAAEABAAuAAQKfzEAAwYACQkGIucFADMDAAYACQmPIOcFADMDAAcABgkTIS4EAHACAAAA.',
Be='Belynila:BAEBLgAECn8mAAIIAAgJDB4bBwBfAghoDAAABQBNAGkMAAAFAEgAawwAAAUAUQBqDAAABQBQAGwMAAAFAEwAbQwAAAMAPQDqDAAABgBWAG4MAAAEAFIACAAICQweGwcAXwIIaAwAAAUATQBpDAAABQBIAGsMAAAFAFEAagwAAAUAUABsDAAABQBMAG0MAAADAD0A6gwAAAYAVgBuDAAABABSAAAA.',
Ca='Carbonarra:BAEBLgAECn8gAAIJAAYJ7BswHQB/AQZoDAAABwBbAGkMAAAGADoAawwAAAYAQwBqDAAABAA+AGwMAAAEAEgA6gwAAAUAQwAJAAYJ7BswHQB/AQZoDAAABwBbAGkMAAAGADoAawwAAAYAQwBqDAAABAA+AGwMAAAEAEgA6gwAAAUAQwAAAA==.Catcam:BAEALgAECgYJBgAAAA==.',
Ch='Chetegos:BAEALgADCgYJBgABLgAECgkJLgAKAJwjAA==.Chíefsquirel:BAEALgAECgYJDAAAAA==.',
Da='Dadbanger:BAECLgAFFH8fAAMBAAgJBB43AABxAghoDAAABQBiAGkMAAAFAGAAawwAAAUASgBqDAAABQBXAGwMAAADAEQAbQwAAAEAJQDqDAAABgBhAG4MAAABAEEAAQAHCZUeNwAAcQIHaAwAAAUAYgBpDAAABQBgAGsMAAAFAEoAagwAAAUAVwBtDAAAAQAlAOoMAAAGAGEAbgwAAAEAQQACAAEJkgU8FgBJAAFsDAAAAwAOAC4ABAp/IgACAQAICWkmCQIAhAMAAQAICWkmCQIAhAMAAAA=.Daeke:BAEALgADCgUJBQABLgAECgQJBwAFAAAAAA==.Daekeypoo:BAEALgAECgQJBwAAAA==.Darkvirgo:BAEALgAECgYJEQABLgAFFAYJGAAIADsVAA==.',
De='Deathbeaver:BAEALgAECgQJBQABLgAECggJMAADAEsbAA==.Destrom:BAEALgAECggJEQAAAA==.',
Ep='Epilepticc:BAECLgAFFH8IAAIDAAQJTRuHEABlAQRoDAAAAwBCAGkMAAACAFUAawwAAAEAMgDqDAAAAgBNAAMABAlNG4cQAGUBBGgMAAADAEIAaQwAAAIAVQBrDAAAAQAyAOoMAAACAE0ALgAECn86AAIDAAkJhyLOBgDiAgADAAkJhyLOBgDiAgAAAA==.',
Et='Ethalon:BAEBLgAECn8jAAMLAAkJHRomGABRAgloDAAABQBFAGkMAAAFAFgAawwAAAUAWABqDAAAAwBTAGwMAAAFAFEAbQwAAAIARwDqDAAABwBXAG4MAAACAAcAbwwAAAEAFwALAAkJHRomGABRAgloDAAABQBFAGkMAAAEAFgAawwAAAUAWABqDAAAAwBTAGwMAAAFAFEAbQwAAAIARwDqDAAABwBXAG4MAAABAAcAbwwAAAEAFwADAAIJjxOw7QBAAAJpDAAAAQAvAG4MAAABADQAAAA=.',
Fa='Fallhp:BAEALgADCgYJBgABLgAFFAcJEAALAPETAA==.Fallill:BAEALgAECgIJAgABLgAFFAcJEAALAPETAA==.Falosso:BAECLgAFFH8QAAILAAcJ8RP4AQAtAgdoDAAAAgA0AGkMAAACADUAawwAAAIAPwBqDAAAAgBLAGwMAAADAA0AbQwAAAEAHwDqDAAABABDAAsABwnxE/gBAC0CB2gMAAACADQAaQwAAAIANQBrDAAAAgA/AGoMAAACAEsAbAwAAAMADQBtDAAAAQAfAOoMAAAEAEMALgAECn8yAAMLAAkJjyDxAwD6AgALAAkJjyDxAwD6AgADAAEJPQqg/AA5AAAAAA==.',
Ga='Garlooth:BAEBLgAECn8ZAAIMAAgJYhnBBgCkAQhoDAAABABTAGkMAAAEAEoAawwAAAQAPgBqDAAAAgAyAGwMAAADAEkAbQwAAAIAOwDqDAAABAA+AG4MAAACACcADAAICWIZwQYApAEIaAwAAAQAUwBpDAAABABKAGsMAAAEAD4AagwAAAIAMgBsDAAAAwBJAG0MAAACADsA6gwAAAQAPgBuDAAAAgAnAAAA.',
Gl='Glizzygary:BAEALgAFFAQJCAAAAQ==.',
Gr='Grimvalor:BAEBLgAECn8wAAMDAAgJSxuGGwAjAghoDAAACABcAGkMAAAHAEAAawwAAAgAUgBqDAAABwBYAGwMAAAGAFIAbQwAAAMAKQDqDAAACABSAG4MAAABACoAAwAICUsbhhsAIwIIaAwAAAcAXABpDAAABwBAAGsMAAAHAFIAagwAAAYAWABsDAAABQBSAG0MAAADACkA6gwAAAcAUgBuDAAAAQAqAA0ABQm4ClgmAGcABWgMAAABAA8AawwAAAEALABqDAAAAQArAGwMAAABACIA6gwAAAEADwAAAA==.Grunclaws:BAEALgAECgYJBQABLgAECgkJGwADAKcZAA==.Grunjitsu:BAEALgAECgkJAQABLgAECgkJGwADAKcZAA==.Grunsy:BAEALgAECgcJAQABLgAECgkJGwADAKcZAA==.',
Ha='Haf:BAEBLgAECn8pAAINAAkJ8RHDCQCoAQloDAAABwA9AGkMAAAGAEIAawwAAAYARwBqDAAABQAjAGwMAAAFADYAbQwAAAMAFQDqDAAABgAvAG4MAAACABYAbwwAAAEAFwANAAkJ8RHDCQCoAQloDAAABwA9AGkMAAAGAEIAawwAAAYARwBqDAAABQAjAGwMAAAFADYAbQwAAAMAFQDqDAAABgAvAG4MAAACABYAbwwAAAEAFwAAAA==.',
He='Hertzmuch:BAEALgADCgYJDgABLgAFFAQJCwACAPcLAA==.',
Ho='Holeighfuk:BAEALgAECgYJBgAAAA==.',
Jo='Joicountdown:BAEBLgAFFH8pAAIOAAgJ+CYCAAAeAwhoDAAABwBjAGkMAAAHAGQAawwAAAcAYgBqDAAABgBkAGwMAAADAGQAbQwAAAIAZADqDAAACABkAG4MAAABAGQADgAICfgmAgAAHgMIaAwAAAcAYwBpDAAABwBkAGsMAAAHAGIAagwAAAYAZABsDAAAAwBkAG0MAAACAGQA6gwAAAgAZABuDAAAAQBkAAEuAAQKBgkGAAUAAAAA.',
Ka='Kautheros:BAEBLgAECn8bAAQPAAgJVwtDDQByAQhoDAAABAAIAGkMAAAEABkAawwAAAQAOwBqDAAABAAfAGwMAAADACIAbQwAAAMACQDqDAAABAAmAG4MAAABABYADwAICVcLQw0AcgEIaAwAAAIACABpDAAAAgAZAGsMAAACADsAagwAAAIAHwBsDAAAAQAiAG0MAAADAAkA6gwAAAMAJgBuDAAAAQAWABAABglSCewuAOoABmgMAAABAB0AaQwAAAEAGABrDAAAAgAcAGoMAAABACQAbAwAAAIAFwDqDAAAAQAMABEAAwmaBnATAFgAA2gMAAABAAkAaQwAAAEAGABqDAAAAQAaAAAA.',
Kr='Kroxychi:BAEALgAECgcJCwAAAA==.Kroxypurple:BAEALgADCgIJAgABLgAECgcJCwAFAAAAAA==.',
Ku='Kungfused:BAECLgAFFH8LAAICAAQJ9wuEEwD5AARoDAAABAAqAGkMAAAEACUAawwAAAIAFwDqDAAAAQATAAIABAn3C4QTAPkABGgMAAAEACoAaQwAAAQAJQBrDAAAAgAXAOoMAAABABMALgAECn87AAMCAAgJ+R+8CgClAgACAAgJ+R+8CgClAgABAAYJ5BNrHABAAQAAAA==.',
Le='Leenfiey:BAECLgAFFH8JAAMSAAMJWyO2DwA5AQNoDAAAAwBfAGkMAAADAFEA6gwAAAMAXQASAAMJWyO2DwA5AQNoDAAAAgBfAGkMAAACAFEA6gwAAAIAXQABAAMJRAxBFAC1AANoDAAAAQAAAGkMAAABADEA6gwAAAEALAAuAAQKfxgAAhIABgkpJd0UAGUCABIABgkpJd0UAGUCAAAA.Lennather:BAEBLgAECn8qAAIBAAkJoSMgAQA4AwloDAAABgBjAGkMAAAGAGEAawwAAAUAWwBqDAAABQBOAGwMAAAFAGAAbQwAAAQAXgDqDAAABgBbAG4MAAAEAE8AbwwAAAEATwABAAkJoSMgAQA4AwloDAAABgBjAGkMAAAGAGEAawwAAAUAWwBqDAAABQBOAGwMAAAFAGAAbQwAAAQAXgDqDAAABgBbAG4MAAAEAE8AbwwAAAEATwAAAA==.',
Li='Lidrunka:BAEBLgAECn8WAAMBAAgJbBTLGwD9AQhoDAAABABKAGkMAAAEAD8AawwAAAMARABqDAAAAgAjAGwMAAACADYAbQwAAAEAHADqDAAABQA/AG4MAAABAAwAAQAICcgTyxsA/QEIaAwAAAMASgBpDAAAAwA0AGsMAAACAEQAagwAAAIAIwBsDAAAAgA2AG0MAAABABwA6gwAAAQAPwBuDAAAAQAMABIABAkWFOMrAPAABGgMAAABACwAaQwAAAEAPwBrDAAAAQA7AOoMAAABACUAAS4ABAoJCScADwCGFQA=.',
['Lé']='Lépewpew:BAEBLgAECn8YAAITAAcJRxK8EQCVAQdoDAAABQA+AGkMAAAFADMAawwAAAUAOwBqDAAAAwBNAGwMAAABACYA6gwAAAQAOgBuDAAAAQAKABMABwlHErwRAJUBB2gMAAAFAD4AaQwAAAUAMwBrDAAABQA7AGoMAAADAE0AbAwAAAEAJgDqDAAABAA6AG4MAAABAAoAAAA=.',
Ma='Mattimus:BAEBLgAECn8UAAMUAAYJOg49UQAaAQZoDAAABAA9AGkMAAAEACUAawwAAAQAGABqDAAAAwAkAGwMAAACABQA6gwAAAMAJgAUAAYJOg49UQAaAQZoDAAABAA9AGkMAAADACUAawwAAAMAGABqDAAAAgAkAGwMAAACABQA6gwAAAIAJgAVAAQJ+QKvcAB8AARpDAAAAQABAGsMAAABAAkAagwAAAEACQDqDAAAAQAMAAAA.',
['Má']='Mákí:BAEALgAECgYJEAAAAA==.',
Na='Natebanger:BAEALgAECgYJDAABLgAFFAgJHwABAAQeAA==.',
Ne='Nethertank:BAEALgAECgQJBAABLgAECggJGwAWAJAWAA==.',
No='Noeyednuck:BAEALgAECgQJCQABLgAECgkJKwAUAIseAA==.',
Nu='Nuckshott:BAEBLgAECn8rAAIUAAkJix7/BwCyAgloDAAABgBFAGkMAAAGAFgAawwAAAYASwBqDAAABQBZAGwMAAAFAFgAbQwAAAQATgDqDAAABQBWAG4MAAAEAEQAbwwAAAIARQAUAAkJix7/BwCyAgloDAAABgBFAGkMAAAGAFgAawwAAAYASwBqDAAABQBZAGwMAAAFAFgAbQwAAAQATgDqDAAABQBWAG4MAAAEAEQAbwwAAAIARQAAAA==.',
Og='Ogx:BAEALgAECgQJBAABLgAECgkJGwADAKcZAA==.',
Ol='Olgass:BAEALgADCgIJAgABLgAECggJJgAXAMEiAA==.',
Pl='Ploots:BAEALgAECgcJAQAAAA==.Plut:BAEALgADCgEJAQABLgAECgcJAQAFAAAAAA==.',
Qu='Quinet:BAEBLgAECn8mAAMXAAgJwSIZCwCbAghoDAAABwBhAGkMAAAGAFsAawwAAAYAXABqDAAABQBRAGwMAAAEAFcAbQwAAAIAWADqDAAABgBeAG4MAAACAEcAFwAICToiGQsAmwIIaAwAAAcAYQBpDAAABQBbAGsMAAAGAFwAagwAAAEAEABsDAAAAgBNAG0MAAACAFgA6gwAAAYAXgBuDAAAAgBHABgAAwnKHm8vAP0AA2kMAAABAEYAagwAAAQAUQBsDAAAAgBXAAAA.',
Ri='Rispirvoke:BAEALgADCgUJBgABLgAFFAUJBwAVAHMXAA==.',
Ro='Ronimus:BAEALgAECgEJAQAAAA==.',
Ru='Rufio:BAECLgAFFH8GAAIZAAIJHA2/DgCdAAJoDAAABAAxAGkMAAACABEAGQACCRwNvw4AnQACaAwAAAQAMQBpDAAAAgARAC4ABAp/HQACGQAICekb9QsAoQIAGQAICekb9QsAoQIAAAA=.',
Ry='Rytiou:BAECLgAFFH8QAAIQAAUJDBxRBQCuAQVoDAAABABSAGkMAAAEAEsAawwAAAQALQBqDAAAAQArAOoMAAADAFIAEAAFCQwcUQUArgEFaAwAAAQAUgBpDAAABABLAGsMAAAEAC0AagwAAAEAKwDqDAAAAwBSAC4ABAp/LQACEAAJCeckWQIAjAMAEAAJCeckWQIAjAMAAAA=.',
Sa='Saadxevok:BAEBLgAECn8YAAMRAAgJQRFFEADYAQhoDAAAAwA7AGkMAAADADEAawwAAAMARQBqDAAAAwAwAGwMAAAEAEgAbQwAAAMACADqDAAAAwAkAG4MAAACAAwAEQAICUERRRAA2AEIaAwAAAMAOwBpDAAAAwAxAGsMAAACAEUAagwAAAIAMABsDAAAAwBIAG0MAAABAAgA6gwAAAEAJABuDAAAAQAMAA8ABglTCDkpACkBBmsMAAABABAAagwAAAEAEQBsDAAAAQARAG0MAAACAB4A6gwAAAIAJwBuDAAAAQAGAAEuAAUUCAkjAAgAZB4A.Saadxm:BAEALgAECgcJDwABLgAFFAgJIwAIAGQeAA==.Saadxp:BAECLgAFFH8jAAMIAAgJZB77AAAfAghoDAAABQBjAGkMAAAGAGAAawwAAAYAYABqDAAABgBYAGwMAAADACAAbQwAAAEAVADqDAAABwBeAG4MAAABACkACAAHCV0h+wAAHwIHaAwAAAQAYwBpDAAABQBgAGsMAAAFAGAAagwAAAUAWABtDAAAAQBUAOoMAAAFAF4AbgwAAAEAKQAaAAYJ3BnuAQANAgZoDAAAAQBJAGkMAAABAB0AawwAAAEAWgBqDAAAAQBOAGwMAAADADMA6gwAAAIASgAuAAQKfyUAAwgACAl+JqsCAOYCAAgACAl+JqsCAOYCABoABQkLHzsgAJEBAAAA.Sanityvanish:BAEALgAECgIJAwABLgAECgMJBAAFAAAAAA==.',
Sg='Sgtgigachad:BAEALgADCgYJBgABLgAFFAQJCAAFAAAAAQ==.',
Sp='Spilt:BAECLgAFFH8YAAIWAAcJqhmtAQCMAgdoDAAABQBaAGkMAAAFAFQAawwAAAQALwBqDAAAAwAaAGwMAAABABAAbQwAAAEARgDqDAAABQBTABYABwmqGa0BAIwCB2gMAAAFAFoAaQwAAAUAVABrDAAABAAvAGoMAAADABoAbAwAAAEAEABtDAAAAQBGAOoMAAAFAFMALgAECn8dAAIWAAkJySThCgBtAwAWAAkJySThCgBtAwAAAA==.Spiltmonk:BAEBLgAECn8YAAIBAAYJWB8sHAD6AQZoDAAABABGAGkMAAAEAFEAawwAAAQAUgBqDAAABABMAGwMAAADAFIA6gwAAAUAVAABAAYJWB8sHAD6AQZoDAAABABGAGkMAAAEAFEAawwAAAQAUgBqDAAABABMAGwMAAADAFIA6gwAAAUAVAABLgAFFAcJGAAWAKoZAA==.',
Ta='Taku:BAEALgAECgcJDQABLgAECggJGwAPAFcLAA==.Taymeean:BAEALgAECgMJBAABLgAFFAMJBgAQAGQJAA==.Tayvok:BAECLgAFFH8GAAIQAAMJZAmLJADTAANoDAAAAgAOAGkMAAADADAA6gwAAAEACQAQAAMJZAmLJADTAANoDAAAAgAOAGkMAAADADAA6gwAAAEACQAuAAQKfywAAhAACQmOHMsEAKkCABAACQmOHMsEAKkCAAAA.',
Te='Tentickles:BAECLgAFFH8MAAIIAAQJjB9/BQCHAQRoDAAAAwBIAGkMAAADAFsAawwAAAIAYQDqDAAABAA9AAgABAmMH38FAIcBBGgMAAADAEgAaQwAAAMAWwBrDAAAAgBhAOoMAAAEAD0ALgAECn8UAAIIAAgJcSJvCAD9AgAIAAgJcSJvCAD9AgABLgAFFAgJHwABAAQeAA==.Tetakoawara:BAEALgAECgUJCwABLgAFFAMJCQASAFsjAA==.',
Th='Thecheatt:BAEBLgAECn8uAAMKAAkJnCPLBABiAgloDAAABwBhAGkMAAAHAGEAawwAAAgAYgBqDAAABgBdAGwMAAAGAFkAbQwAAAIAWgDqDAAABwBfAG4MAAACAEYAbwwAAAEAWQAKAAkJnCPLBABiAgloDAAABgBhAGkMAAAFAGEAawwAAAYAYgBqDAAABABdAGwMAAADAFkAbQwAAAIAWgDqDAAABABfAG4MAAACAEYAbwwAAAEAWQAJAAYJnxbmSQB9AQZoDAAAAQAQAGkMAAACAEoAawwAAAIANgBqDAAAAgAyAGwMAAADAE8A6gwAAAMAPwAAAA==.',
Vi='Vigiz:BAEALgAECgYJBgAAAA==.Vilexie:BAEALgAECgcJCAAAAA==.',
Wa='Wafflé:BAEALgAECgIJAgAAAA==.',
Wh='Whitecrosses:BAEALgAECgEJAQABLgAECgcJGAATAEcSAA==.',
Wi='Wiskystagger:BAEALgADCgEJAgAAAA==.',
Za='Zargan:BAEALgAECgUJBgABLgAECggJGwAPAFcLAA==.',
Ze='Zertzz:BAEALgAECgUJCAABLgAFFAQJEAAIALIfAA==.',
Zi='Zibbz:BAEBLgAECn8dAAIQAAkJzCBWAgAMAwloDAAABABXAGkMAAAEAFsAawwAAAQAVABqDAAAAwBVAGwMAAAEAFIAbQwAAAMAVwDqDAAABABWAG4MAAACAFsAbwwAAAEAOwAQAAkJzCBWAgAMAwloDAAABABXAGkMAAAEAFsAawwAAAQAVABqDAAAAwBVAGwMAAAEAFIAbQwAAAMAVwDqDAAABABWAG4MAAACAFsAbwwAAAEAOwABLgAECgkJJwAbACweAA==.Zinia:BAEBLgAECn8fAAIcAAgJ8xcKBgDmAQhoDAAABgBXAGkMAAAGAFIAawwAAAYAOQBqDAAAAwA6AGwMAAADAEcAbQwAAAEAMQDqDAAABQBCAG4MAAABAA4AHAAICfMXCgYA5gEIaAwAAAYAVwBpDAAABgBSAGsMAAAGADkAagwAAAMAOgBsDAAAAwBHAG0MAAABADEA6gwAAAUAQgBuDAAAAQAOAAAA.',
Zu='Zubbfist:BAEALgADCgcJBwABLgAECgkJJwAbACweAA==.Zubbrael:BAEBLgAECn8fAAMIAAgJXxleIwC9AQhoDAAABwBKAGkMAAAFAEMAawwAAAQAQgBqDAAAAwA3AGwMAAAEADYAbQwAAAEAUgDqDAAABgBCAG4MAAABACoACAAHCToYXiMAvQEHaAwAAAUASgBpDAAAAwBDAGsMAAACAEIAagwAAAEANwBsDAAAAgA2AOoMAAAEAEIAbgwAAAEAKgAaAAcJgglUGgBeAQdoDAAAAgAOAGkMAAACABUAawwAAAIAIwBqDAAAAgArAGwMAAACABIAbQwAAAEAEgDqDAAAAgATAAEuAAQKCQknABsALB4A.Zubbz:BAEBLgAECn8nAAIbAAgJLB6PHgCaAghoDAAABgBeAGkMAAAHAFgAawwAAAcAUwBqDAAABAA9AGwMAAAEAFcAbQwAAAIAJQDqDAAABwBYAG4MAAACADoAGwAICSwejx4AmgIIaAwAAAYAXgBpDAAABwBYAGsMAAAHAFMAagwAAAQAPQBsDAAABABXAG0MAAACACUA6gwAAAcAWABuDAAAAgA6AAAA.',
Zz='Zzertz:BAECLgAFFH8QAAIIAAQJsh/vBQB/AQRoDAAABQBcAGkMAAAEAFMAawwAAAMAVADqDAAABABAAAgABAmyH+8FAH8BBGgMAAAFAFwAaQwAAAQAUwBrDAAAAwBUAOoMAAAEAEAALgAECn8rAAIIAAgJ/yI4BgApAwAIAAgJ/yI4BgApAwAAAA==.',
['Àb']='Àbeel:BAEALgAECgMJAwABLgAECggJLwAHABYbAA==.Àbel:BAEBLgAECn8vAAMHAAgJFhtjBgASAghoDAAACABXAGkMAAAJAFQAawwAAAcAWgBqDAAABgBeAGwMAAAEAD0AbQwAAAIAIwDqDAAACQBZAG4MAAACACQABwAHCUYdYwYAEgIHaAwAAAcAVwBpDAAACABUAGsMAAAFAFoAagwAAAUAXgBsDAAABAA9AOoMAAAIAFkAbgwAAAEAJAAGAAcJkhY4EgCJAQdoDAAAAQBJAGkMAAABAE8AawwAAAIATgBqDAAAAQBdAG0MAAACACMA6gwAAAEAOwBuDAAAAQAUAAAA.Àble:BAEALgADCgQJCQABLgAECggJLwAHABYbAA==.',
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
