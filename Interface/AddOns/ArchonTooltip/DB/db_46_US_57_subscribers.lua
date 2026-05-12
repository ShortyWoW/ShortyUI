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

local lookup = {'Monk-Windwalker','Monk-Mistweaver','Paladin-Retribution','Priest-Holy','Unknown-Unknown','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','Warrior-Fury','Warrior-Protection','Paladin-Holy','Mage-Arcane','Paladin-Protection','Druid-Feral','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Monk-Brewmaster','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Mage-Frost','Warlock-Demonology','Warlock-Destruction','DemonHunter-Havoc','Priest-Discipline','Shaman-Enhancement','DemonHunter-Devourer',}
local provider = {region='US',realm='Dalaran',name='US',type='subscribers',zone=46,date='2026-05-11',data={Ad='Adansso:BAEBLgAECn8rAAIBAAgJfg9vFwB8AQhoDAAACAAoAGkMAAAHADoAawwAAAYAQwBqDAAABAAlAGwMAAAFABcAbQwAAAIAFgDqDAAABwAcAG4MAAAEACUAAQAICX4PbxcAfAEIaAwAAAgAKABpDAAABwA6AGsMAAAGAEMAagwAAAQAJQBsDAAABQAXAG0MAAACABYA6gwAAAcAHABuDAAABAAlAAAA.',
Ap='Apawcowlypse:BAEALgADCgcJDAABLgAFFAQJCwACAPcLAA==.',
As='Ashko:BAEBLgAECn8bAAIDAAcJqhkgMgDGAQdoDAAABgBBAGkMAAAFAFMAawwAAAQAUQBqDAAABABGAGwMAAADAFAAbQwAAAEAHQDqDAAABAA1AAMABwmqGSAyAMYBB2gMAAAGAEEAaQwAAAUAUwBrDAAABABRAGoMAAAEAEYAbAwAAAMAUABtDAAAAQAdAOoMAAAEADUAAAA=.',
Ay='Ayodele:BAEALgAECgcJDgAAAA==.',
Az='Azurlia:BAEALgAECgYJEQAAAA==.',
Ba='Babycora:BAEALgAECgYJBwABLgAECgkJLQAEAOYdAA==.Bagelandlox:BAEALgADCgEJAQABLgAECgYJDAAFAAAAAA==.Barrui:BAECLgAFFH8fAAMGAAgJRBm+AABDAghoDAAABgBBAGkMAAAGAGAAawwAAAUAOwBqDAAABABOAGwMAAABAAQAbQwAAAEAJADqDAAABwBcAG4MAAABAGEABgAHCUccvgAAQwIHaAwAAAYAQQBpDAAABQBSAGsMAAAEADsAagwAAAQATgBtDAAAAQAkAOoMAAAHAFwAbgwAAAEAYQAHAAMJWRBwAgAVAQNpDAAAAQBgAGsMAAABABgAbAwAAAEABAAuAAQKfzMAAwYACQlnJOgFADMDAAYACQnwIugFADMDAAcABgkTIS8EAHACAAAA.',
Be='Belynila:BAECLgAFFH8GAAIIAAIJRxYzGQCsAAJoDAAABABEAGkMAAACAC0ACAACCUcWMxkArAACaAwAAAQARABpDAAAAgAtAC4ABAp/LwACCAAJCdodggMA1gIACAAJCdodggMA1gIAAAA=.',
Ca='Carbonarra:BAEBLgAECn8gAAIJAAYJ7BuvIAByAQZoDAAABwBbAGkMAAAGADoAawwAAAYAQwBqDAAABAA+AGwMAAAEAEgA6gwAAAUAQwAJAAYJ7BuvIAByAQZoDAAABwBbAGkMAAAGADoAawwAAAYAQwBqDAAABAA+AGwMAAAEAEgA6gwAAAUAQwAAAA==.Catcam:BAEALgAECgYJBgAAAA==.',
Ch='Chetegos:BAEALgADCgYJBgABLgAECgkJMwAKAM4jAA==.Chíefsquirel:BAEALgAECgYJDAAAAA==.',
Da='Dadbanger:BAECLgAFFH8fAAMBAAgJCR43AABxAghoDAAABQBiAGkMAAAFAGAAawwAAAUASgBqDAAABQBXAGwMAAADAEQAbQwAAAEAJQDqDAAABgBhAG4MAAABAEEAAQAHCZweNwAAcQIHaAwAAAUAYgBpDAAABQBgAGsMAAAFAEoAagwAAAUAVwBtDAAAAQAlAOoMAAAGAGEAbgwAAAEAQQACAAEJkgVAFgBJAAFsDAAAAwAOAC4ABAp/IgACAQAICWkmCQIAhAMAAQAICWkmCQIAhAMAAAA=.Daeke:BAEALgADCgUJBQABLgAECgQJBwAFAAAAAA==.Daekeypoo:BAEALgAECgQJBwAAAA==.Darkvirgo:BAEALgAECgYJEQABLgAFFAYJGAAIAD8VAA==.',
De='Deathbeaver:BAEALgAECgQJBQABLgAECggJOAADACkdAA==.Destrom:BAEALgAECggJEQAAAA==.',
Ep='Epilepticc:BAECLgAFFH8IAAIDAAQJTRu0EwBjAQRoDAAAAwBCAGkMAAACAFUAawwAAAEAMgDqDAAAAgBNAAMABAlNG7QTAGMBBGgMAAADAEIAaQwAAAIAVQBrDAAAAQAyAOoMAAACAE0ALgAECn87AAIDAAkJ6yIqBwDsAgADAAkJ6yIqBwDsAgAAAA==.',
Et='Ethalon:BAECLgAFFH8IAAILAAQJiwwmFAAiAQRoDAAAAwBIAGkMAAACABkAawwAAAEADwDqDAAAAgAOAAsABAmLDCYUACIBBGgMAAADAEgAaQwAAAIAGQBrDAAAAQAPAOoMAAACAA4ALgAECn8jAAMLAAkJHRomGABRAgALAAkJHRomGABRAgADAAIJlBO3/gBAAAAAAA==.',
Fa='Fallhp:BAEALgADCgYJBgABLgAFFAcJEAALAPcTAA==.Fallill:BAEALgAECgIJAgABLgAFFAcJEAALAPcTAA==.Falosso:BAECLgAFFH8QAAILAAcJ9xOgAgAmAgdoDAAAAgA0AGkMAAACADUAawwAAAIAQABqDAAAAgBLAGwMAAADAA0AbQwAAAEAHwDqDAAABABDAAsABwn3E6ACACYCB2gMAAACADQAaQwAAAIANQBrDAAAAgBAAGoMAAACAEsAbAwAAAMADQBtDAAAAQAfAOoMAAAEAEMALgAECn8yAAMLAAkJjyCtBADxAgALAAkJjyCtBADxAgADAAEJPQpcDgE5AAAAAA==.',
Ga='Garlooth:BAEBLgAECn8hAAIMAAgJqR4KAQBmAghoDAAABQBTAGkMAAAFAFMAawwAAAUATQBqDAAAAwAyAGwMAAAEAEkAbQwAAAMAXgDqDAAABQA+AG4MAAADAEoADAAICakeCgEAZgIIaAwAAAUAUwBpDAAABQBTAGsMAAAFAE0AagwAAAMAMgBsDAAABABJAG0MAAADAF4A6gwAAAUAPgBuDAAAAwBKAAAA.',
Gl='Glizzygary:BAEALgAFFAQJCAAAAQ==.',
Gr='Grimvalor:BAEBLgAECn84AAMDAAgJKR1DGQBEAghoDAAACQBcAGkMAAAIAEAAawwAAAkAUgBqDAAACABYAGwMAAAHAFIAbQwAAAQASwDqDAAACQBSAG4MAAACACoAAwAICSkdQxkARAIIaAwAAAgAXABpDAAACABAAGsMAAAIAFIAagwAAAcAWABsDAAABgBSAG0MAAAEAEsA6gwAAAgAUgBuDAAAAgAqAA0ABQnPCh0pAGUABWgMAAABAA8AawwAAAEALABqDAAAAQAsAGwMAAABACIA6gwAAAEADwAAAA==.Grunclaws:BAEALgAECgYJBgABLgAECgkJGwADAKoZAA==.Grunjitsu:BAEALgAECgkJAQABLgAECgkJGwADAKoZAA==.Grunsy:BAEALgAECgcJAgABLgAECgkJGwADAKoZAA==.',
Ha='Haf:BAEBLgAECn8pAAINAAkJ8hHuCgCgAQloDAAABwA9AGkMAAAGAEIAawwAAAYARwBqDAAABQAjAGwMAAAFADYAbQwAAAMAFQDqDAAABgAvAG4MAAACABYAbwwAAAEAFwANAAkJ8hHuCgCgAQloDAAABwA9AGkMAAAGAEIAawwAAAYARwBqDAAABQAjAGwMAAAFADYAbQwAAAMAFQDqDAAABgAvAG4MAAACABYAbwwAAAEAFwAAAA==.',
He='Hertzmuch:BAEALgADCgYJDgABLgAFFAQJCwACAPcLAA==.',
Ho='Holeighfuk:BAEALgAECgYJBgAAAA==.',
Jo='Joicountdown:BAEBLgAFFH8pAAIOAAgJ+CYDAAAdAwhoDAAABwBjAGkMAAAHAGQAawwAAAcAYgBqDAAABgBkAGwMAAADAGQAbQwAAAIAZADqDAAACABkAG4MAAABAGQADgAICfgmAwAAHQMIaAwAAAcAYwBpDAAABwBkAGsMAAAHAGIAagwAAAYAZABsDAAAAwBkAG0MAAACAGQA6gwAAAgAZABuDAAAAQBkAAEuAAQKBgkGAAUAAAAA.',
Ka='Kautheros:BAEBLgAECn8cAAQPAAgJpwscDgBzAQhoDAAABAAIAGkMAAAEABkAawwAAAQAOwBqDAAABAAfAGwMAAADACIAbQwAAAMACQDqDAAABAAmAG4MAAACAB0ADwAICacLHA4AcwEIaAwAAAIACABpDAAAAgAZAGsMAAACADsAagwAAAIAHwBsDAAAAQAiAG0MAAADAAkA6gwAAAMAJgBuDAAAAgAdABAABglSCU0yAOoABmgMAAABAB0AaQwAAAEAGABrDAAAAgAcAGoMAAABACQAbAwAAAIAFwDqDAAAAQAMABEAAwmaBp0UAFgAA2gMAAABAAkAaQwAAAEAGABqDAAAAQAaAAAA.',
Kr='Kroxychi:BAEALgAECgcJCwAAAA==.Kroxypurple:BAEALgADCgIJAgABLgAECgcJCwAFAAAAAA==.',
Ku='Kungfused:BAECLgAFFH8LAAICAAQJ9wuuFQD5AARoDAAABAAqAGkMAAAEACUAawwAAAIAFwDqDAAAAQATAAIABAn3C64VAPkABGgMAAAEACoAaQwAAAQAJQBrDAAAAgAXAOoMAAABABMALgAECn9DAAMCAAgJ+R+/CgClAgACAAgJ+R+/CgClAgABAAgJUxPfEgCsAQAAAA==.',
Le='Leenfiey:BAECLgAFFH8JAAMSAAMJXCN+EQA3AQNoDAAAAwBfAGkMAAADAFEA6gwAAAMAXQASAAMJXCN+EQA3AQNoDAAAAgBfAGkMAAACAFEA6gwAAAIAXQABAAMJRwyzFgCsAANoDAAAAQAAAGkMAAABADEA6gwAAAEALAAuAAQKfxgAAhIABgkrJd0UAGUCABIABgkrJd0UAGUCAAAA.Lennather:BAEBLgAECn8zAAIBAAkJHCWwAABhAwloDAAABwBjAGkMAAAHAGEAawwAAAYAWwBqDAAABgBOAGwMAAAGAGAAbQwAAAUAXgDqDAAABwBdAG4MAAAFAF8AbwwAAAIAWgABAAkJHCWwAABhAwloDAAABwBjAGkMAAAHAGEAawwAAAYAWwBqDAAABgBOAGwMAAAGAGAAbQwAAAUAXgDqDAAABwBdAG4MAAAFAF8AbwwAAAIAWgAAAA==.',
Li='Lidrunka:BAEBLgAECn8WAAMBAAgJbhTQGwD9AQhoDAAABABKAGkMAAAEAD8AawwAAAMARABqDAAAAgAjAGwMAAACADYAbQwAAAEAHADqDAAABQA/AG4MAAABAAwAAQAICcoT0BsA/QEIaAwAAAMASgBpDAAAAwA0AGsMAAACAEQAagwAAAIAIwBsDAAAAgA2AG0MAAABABwA6gwAAAQAPwBuDAAAAQAMABIABAkWFGQuAO8ABGgMAAABACwAaQwAAAEAPwBrDAAAAQA7AOoMAAABACUAAS4ABAoJCScADwCUFQA=.',
['Lé']='Lépewpew:BAEBLgAECn8YAAITAAcJSRKJEwCQAQdoDAAABQA+AGkMAAAFADMAawwAAAUAOwBqDAAAAwBNAGwMAAABACYA6gwAAAQAOgBuDAAAAQAKABMABwlJEokTAJABB2gMAAAFAD4AaQwAAAUAMwBrDAAABQA7AGoMAAADAE0AbAwAAAEAJgDqDAAABAA6AG4MAAABAAoAAAA=.',
Ma='Mattimus:BAEBLgAECn8VAAMUAAYJXg4TVgAdAQZoDAAABAA9AGkMAAAEACUAawwAAAUAGgBqDAAAAwAkAGwMAAACABQA6gwAAAMAJQAUAAYJXg4TVgAdAQZoDAAABAA9AGkMAAADACUAawwAAAQAGgBqDAAAAgAkAGwMAAACABQA6gwAAAIAJQAVAAQJ+QKzcAB8AARpDAAAAQABAGsMAAABAAkAagwAAAEACQDqDAAAAQAMAAAA.',
['Má']='Mákí:BAEALgAECgYJEAAAAA==.',
Na='Natebanger:BAEALgAECgYJDAABLgAFFAgJHwABAAkeAA==.',
Ne='Nethertank:BAEALgAECgQJBAABLgAECggJGwAWAJAWAA==.',
No='Noeyednuck:BAEALgAECgQJCQABLgAECgkJKwAUAIseAA==.',
Nu='Nuckshott:BAEBLgAECn8rAAIUAAkJix5uCgChAgloDAAABgBFAGkMAAAGAFgAawwAAAYASwBqDAAABQBZAGwMAAAFAFgAbQwAAAQATgDqDAAABQBWAG4MAAAEAEQAbwwAAAIARQAUAAkJix5uCgChAgloDAAABgBFAGkMAAAGAFgAawwAAAYASwBqDAAABQBZAGwMAAAFAFgAbQwAAAQATgDqDAAABQBWAG4MAAAEAEQAbwwAAAIARQAAAA==.',
Og='Ogx:BAEALgAECgQJBQABLgAECgkJGwADAKoZAA==.',
Ol='Olgass:BAEALgADCgIJAgABLgAECggJJgAXAMEiAA==.',
Pl='Ploots:BAEALgAECgcJAQAAAA==.Plut:BAEALgADCgEJAQABLgAECgcJAQAFAAAAAA==.',
Qu='Quinet:BAEBLgAECn8mAAMXAAgJwSKDDACWAghoDAAABwBhAGkMAAAGAFsAawwAAAYAXABqDAAABQBRAGwMAAAEAFcAbQwAAAIAWADqDAAABgBeAG4MAAACAEcAFwAICToigwwAlgIIaAwAAAcAYQBpDAAABQBbAGsMAAAGAFwAagwAAAEAEABsDAAAAgBNAG0MAAACAFgA6gwAAAYAXgBuDAAAAgBHABgAAwnKHnIvAP0AA2kMAAABAEYAagwAAAQAUQBsDAAAAgBXAAAA.Quinman:BAEBLgAECn8aAAQTAAkJRBqJBwBAAgloDAAABQBBAGkMAAAEADMAawwAAAQATwBqDAAAAgAnAGwMAAACAGEAbQwAAAIAOwDqDAAABABBAG4MAAACAD0AbwwAAAEAOgATAAkJixeJBwBAAgloDAAAAQA8AGkMAAABAAAAawwAAAEATwBqDAAAAgAnAGwMAAACAGEAbQwAAAIAOwDqDAAAAwBBAG4MAAACAD0AbwwAAAEAOgAVAAQJWhWNWQDfAARoDAAAAwBBAGkMAAADADMAawwAAAMAMQDqDAAAAQA0ABQAAQkVGNi5AEEAAWgMAAABAD0AAAA=.Quinroxx:BAEBLgAECn8gAAIWAAgJXCN8KwDFAghoDAAABQBiAGkMAAAFAFsAawwAAAUAXwBqDAAABQBeAGwMAAADAFoAbQwAAAIAUwDqDAAABgBhAG4MAAABAE0AFgAICVwjfCsAxQIIaAwAAAUAYgBpDAAABQBbAGsMAAAFAF8AagwAAAUAXgBsDAAAAwBaAG0MAAACAFMA6gwAAAYAYQBuDAAAAQBNAAEuAAQKCQkaABMARBoA.Quinvinvin:BAEALgAECgcJDQABLgAECgkJGgATAEQaAA==.',
Ri='Rispirvoke:BAEALgADCgUJBgABLgAFFAUJBwAVAHUXAA==.',
Ro='Ronimus:BAEALgAECgEJAQAAAA==.',
Ru='Rufio:BAECLgAFFH8IAAIZAAIJcw6dEACYAAJoDAAABQA2AGkMAAADABMAGQACCXMOnRAAmAACaAwAAAUANgBpDAAAAwATAC4ABAp/HwACGQAICekb9gsAoQIAGQAICekb9gsAoQIAAAA=.',
Ry='Rytiou:BAECLgAFFH8QAAIQAAUJGxxUBQCuAQVoDAAABABSAGkMAAAEAEsAawwAAAQALgBqDAAAAQArAOoMAAADAFIAEAAFCRscVAUArgEFaAwAAAQAUgBpDAAABABLAGsMAAAEAC4AagwAAAEAKwDqDAAAAwBSAC4ABAp/LQACEAAJCeckWQIAjAMAEAAJCeckWQIAjAMAAAA=.',
Sa='Saadxevok:BAEBLgAECn8YAAMRAAgJQRFMEADYAQhoDAAAAwA7AGkMAAADADEAawwAAAMARQBqDAAAAwAwAGwMAAAEAEgAbQwAAAMACADqDAAAAwAkAG4MAAACAAwAEQAICUERTBAA2AEIaAwAAAMAOwBpDAAAAwAxAGsMAAACAEUAagwAAAIAMABsDAAAAwBIAG0MAAABAAgA6gwAAAEAJABuDAAAAQAMAA8ABglTCDopACkBBmsMAAABABAAagwAAAEAEQBsDAAAAQARAG0MAAACAB4A6gwAAAIAJwBuDAAAAQAGAAEuAAUUCAkjAAgAZB4A.Saadxm:BAEALgAECgcJDwABLgAFFAgJIwAIAGQeAA==.Saadxp:BAECLgAFFH8jAAMIAAgJZB7JAABZAghoDAAABQBjAGkMAAAGAGAAawwAAAYAYABqDAAABgBYAGwMAAADACAAbQwAAAEAVADqDAAABwBeAG4MAAABACkACAAHCV0hyQAAWQIHaAwAAAQAYwBpDAAABQBgAGsMAAAFAGAAagwAAAUAWABtDAAAAQBUAOoMAAAFAF4AbgwAAAEAKQAaAAYJ5RnwAQANAgZoDAAAAQBJAGkMAAABAB0AawwAAAEAWgBqDAAAAQBOAGwMAAADADMA6gwAAAIASgAuAAQKfyUAAwgACAmHJjUDAOQCAAgACAmHJjUDAOQCABoABQkLHzsgAJEBAAAA.Sanityvanish:BAEALgAECgIJAwABLgAECgMJBAAFAAAAAA==.',
Sg='Sgtgigachad:BAEALgADCgYJBgABLgAFFAQJCAAFAAAAAQ==.',
Sp='Spilt:BAECLgAFFH8ZAAIWAAcJoBmvAQCMAgdoDAAABQBaAGkMAAAFAFQAawwAAAQALwBqDAAAAwAaAGwMAAABABAAbQwAAAEARgDqDAAABgBTABYABwmgGa8BAIwCB2gMAAAFAFoAaQwAAAUAVABrDAAABAAvAGoMAAADABoAbAwAAAEAEABtDAAAAQBGAOoMAAAGAFMALgAECn8dAAIWAAkJySTlCgBtAwAWAAkJySTlCgBtAwAAAA==.Spiltmonk:BAEBLgAECn8YAAIBAAYJWh8wHAD6AQZoDAAABABGAGkMAAAEAFEAawwAAAQAUgBqDAAABABMAGwMAAADAFIA6gwAAAUAVAABAAYJWh8wHAD6AQZoDAAABABGAGkMAAAEAFEAawwAAAQAUgBqDAAABABMAGwMAAADAFIA6gwAAAUAVAABLgAFFAcJGQAWAKAZAA==.',
Su='Sunjo:BAEALgAECgkJAwABLgAECgkJGwADAKoZAA==.',
Ta='Taku:BAEALgAECgcJDQABLgAECggJHAAPAKcLAA==.Taymeean:BAEALgAECgMJBAABLgAFFAMJBgAQAGQJAA==.Tayvok:BAECLgAFFH8GAAIQAAMJZAkAKADJAANoDAAAAgAOAGkMAAADADAA6gwAAAEACQAQAAMJZAkAKADJAANoDAAAAgAOAGkMAAADADAA6gwAAAEACQAuAAQKfywAAhAACQmQHDkFAKoCABAACQmQHDkFAKoCAAAA.',
Te='Tentickles:BAECLgAFFH8MAAIIAAQJlx9TBgCFAQRoDAAAAwBIAGkMAAADAFsAawwAAAIAYQDqDAAABAA9AAgABAmXH1MGAIUBBGgMAAADAEgAaQwAAAMAWwBrDAAAAgBhAOoMAAAEAD0ALgAECn8UAAIIAAgJeiJwCAD9AgAIAAgJeiJwCAD9AgABLgAFFAgJHwABAAkeAA==.Tetakoawara:BAEALgAECgUJCwABLgAFFAMJCQASAFwjAA==.',
Th='Thecheatt:BAEBLgAECn8zAAMKAAkJziN5AgDGAgloDAAACABhAGkMAAAIAGEAawwAAAkAYgBqDAAABwBdAGwMAAAHAF0AbQwAAAIAWgDqDAAABwBfAG4MAAACAEcAbwwAAAEAWQAKAAkJziN5AgDGAgloDAAABwBhAGkMAAAGAGEAawwAAAcAYgBqDAAABQBdAGwMAAAEAF0AbQwAAAIAWgDqDAAABABfAG4MAAACAEcAbwwAAAEAWQAJAAYJnxbrSQB9AQZoDAAAAQAQAGkMAAACAEoAawwAAAIANgBqDAAAAgAyAGwMAAADAE8A6gwAAAMAPwAAAA==.',
Vi='Vigiz:BAEALgAECgYJBgAAAA==.Vilexie:BAEALgAECggJCQAAAA==.',
Wa='Wafflé:BAEALgAECgIJAgAAAA==.',
Wh='Whitecrosses:BAEALgAECgEJAQABLgAECgcJGAATAEkSAA==.',
Wi='Wiskystagger:BAEALgADCgEJAgAAAA==.',
Za='Zargan:BAEALgAECgcJCAABLgAECggJHAAPAKcLAA==.',
Ze='Zertzz:BAEALgAFFAEJAQABLgAFFAQJEAAIALIfAA==.',
Zi='Zibbz:BAEBLgAECn8kAAMQAAkJzCCdAgAMAwloDAAABQBXAGkMAAAFAFsAawwAAAUAVABqDAAABABVAGwMAAAFAFIAbQwAAAMAVwDqDAAABQBWAG4MAAADAFsAbwwAAAEAOwAQAAkJzCCdAgAMAwloDAAABABXAGkMAAAEAFsAawwAAAQAVABqDAAAAwBVAGwMAAAEAFIAbQwAAAMAVwDqDAAABABWAG4MAAACAFsAbwwAAAEAOwARAAcJyxpyAwD0AQdoDAAAAQBOAGkMAAABAFAAawwAAAEARwBqDAAAAQBGAGwMAAABAEcA6gwAAAEAUwBuDAAAAQAZAAAA.Zinia:BAEBLgAECn8fAAIbAAgJ8xfEBgDfAQhoDAAABgBXAGkMAAAGAFIAawwAAAYAOQBqDAAAAwA6AGwMAAADAEcAbQwAAAEAMQDqDAAABQBCAG4MAAABAA4AGwAICfMXxAYA3wEIaAwAAAYAVwBpDAAABgBSAGsMAAAGADkAagwAAAMAOgBsDAAAAwBHAG0MAAABADEA6gwAAAUAQgBuDAAAAQAOAAAA.',
Zu='Zubbfist:BAEALgADCgcJBwABLgAECgkJJAAQAMwgAA==.Zubbrael:BAEBLgAECn8fAAMIAAgJYRlgIwC9AQhoDAAABwBKAGkMAAAFAEMAawwAAAQAQgBqDAAAAwA3AGwMAAAEADYAbQwAAAEAUgDqDAAABgBCAG4MAAABACoACAAHCTwYYCMAvQEHaAwAAAUASgBpDAAAAwBDAGsMAAACAEIAagwAAAEANwBsDAAAAgA2AOoMAAAEAEIAbgwAAAEAKgAaAAcJgwnLHABcAQdoDAAAAgAOAGkMAAACABUAawwAAAIAIwBqDAAAAgArAGwMAAACABIAbQwAAAEAEgDqDAAAAgATAAEuAAQKCQkkABAAzCAA.Zubbz:BAEBLgAECn8nAAIcAAgJLB6SHgCaAghoDAAABgBeAGkMAAAHAFgAawwAAAcAUwBqDAAABAA9AGwMAAAEAFcAbQwAAAIAJQDqDAAABwBYAG4MAAACADoAHAAICSwekh4AmgIIaAwAAAYAXgBpDAAABwBYAGsMAAAHAFMAagwAAAQAPQBsDAAABABXAG0MAAACACUA6gwAAAcAWABuDAAAAgA6AAEuAAQKCQkkABAAzCAA.',
Zz='Zzertz:BAECLgAFFH8QAAIIAAQJsh/uBgB9AQRoDAAABQBcAGkMAAAEAFMAawwAAAMAVADqDAAABABAAAgABAmyH+4GAH0BBGgMAAAFAFwAaQwAAAQAUwBrDAAAAwBUAOoMAAAEAEAALgAECn8rAAIIAAgJ/yI5BgApAwAIAAgJ/yI5BgApAwAAAA==.',
['Àb']='Àbeel:BAEALgAECgMJAwABLgAECggJLwAHABYbAA==.Àbel:BAEBLgAECn8vAAMHAAgJFhtjBgASAghoDAAACABXAGkMAAAJAFQAawwAAAcAWgBqDAAABgBeAGwMAAAEAD0AbQwAAAIAIwDqDAAACQBZAG4MAAACACQABwAHCUYdYwYAEgIHaAwAAAcAVwBpDAAACABUAGsMAAAFAFoAagwAAAUAXgBsDAAABAA9AOoMAAAIAFkAbgwAAAEAJAAGAAcJkhZlFAB7AQdoDAAAAQBJAGkMAAABAE8AawwAAAIATgBqDAAAAQBdAG0MAAACACMA6gwAAAEAOwBuDAAAAQAUAAAA.Àble:BAEALgADCgQJCQABLgAECggJLwAHABYbAA==.',
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
