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

local lookup = {'Monk-Windwalker','Shaman-Enhancement','Monk-Mistweaver','Paladin-Retribution','Paladin-Holy','Mage-Frost','Druid-Feral','Unknown-Unknown','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','Warrior-Arms','Warrior-Fury','Warrior-Protection','Mage-Arcane','Paladin-Protection','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Monk-Brewmaster','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Warlock-Demonology','Warlock-Destruction','DemonHunter-Havoc','Priest-Discipline','DeathKnight-Unholy','DeathKnight-Blood','DemonHunter-Devourer',}
local provider = {region='US',realm='Dalaran',name='US',type='subscribers',zone=46,date='2026-05-16',data={Ad='Adansso:BAEBLgAECn8rAAIBAAgJfg86IABYAQhoDAAACAAoAGkMAAAHADoAawwAAAYAQwBqDAAABAAlAGwMAAAFABcAbQwAAAIAFgDqDAAABwAcAG4MAAAEACUAAQAICX4POiAAWAEIaAwAAAgAKABpDAAABwA6AGsMAAAGAEMAagwAAAQAJQBsDAAABQAXAG0MAAACABYA6gwAAAcAHABuDAAABAAlAAAA.',
Al='Aliastei:BAEALgADCgQJBAABLgAECggJJwACAN4ZAA==.',
Ap='Apawcowlypse:BAEALgADCgcJDAABLgAFFAQJDwADAGkNAA==.',
As='Ashko:BAEBLgAECn8gAAMEAAgJNBl/MwDrAQhoDAAABgBBAGkMAAAFAFMAawwAAAQAUQBqDAAABQBGAGwMAAAEAFEAbQwAAAIAKwDqDAAABQA1AG4MAAABACkABAAICTQZfzMA6wEIaAwAAAYAQQBpDAAABQBTAGsMAAAEAFEAagwAAAUARgBsDAAABABRAG0MAAACACsA6gwAAAQANQBuDAAAAQApAAUAAQmpCnR1ACwAAeoMAAABABsAAAA=.',
Ay='Ayodele:BAEBLgAECn8XAAIGAAgJIBWmQwDOAQhoDAAABABLAGkMAAACAC4AawwAAAIAPQBqDAAABABFAGwMAAADADcAbQwAAAEAGwDqDAAABABIAG4MAAADACgABgAICSAVpkMAzgEIaAwAAAQASwBpDAAAAgAuAGsMAAACAD0AagwAAAQARQBsDAAAAwA3AG0MAAABABsA6gwAAAQASABuDAAAAwAoAAAA.',
Az='Azurlia:BAEALgAECgYJEQAAAA==.',
Ba='Babycora:BAEALgAECgYJBwABLgAECggJKwAHAAMeAA==.Bagelandlox:BAEALgADCgEJAQABLgAECgYJDAAIAAAAAA==.Barrui:BAECLgAFFH8jAAMJAAgJ+RrQAQAmAghoDAAABgBBAGkMAAAHAGAAawwAAAYAWgBqDAAABQBOAGwMAAABAAQAbQwAAAEAJADqDAAACABcAG4MAAABAGEACQAHCUUe0AEAJgIHaAwAAAYAQQBpDAAABgBSAGsMAAAFAFoAagwAAAUATgBtDAAAAQAkAOoMAAAIAFwAbgwAAAEAYQAKAAMJWRBwAgAVAQNpDAAAAQBgAGsMAAABABgAbAwAAAEABAAuAAQKfzgAAwkACQlwJOkFADMDAAkACQnwIukFADMDAAoABgkfIS8EAHACAAAA.',
Be='Belynila:BAECLgAFFH8GAAILAAIJRxb/HAClAAJoDAAABABEAGkMAAACAC0ACwACCUcW/xwApQACaAwAAAQARABpDAAAAgAtAC4ABAp/NgACCwAJCdYe3gYAoQIACwAJCdYe3gYAoQIAAAA=.Bestiavera:BAEBLgAECn8kAAIMAAgJ5g0+FgBOAQhoDAAABwA/AGkMAAAGADEAawwAAAYAJABqDAAABQA4AGwMAAAFACAAbQwAAAEAEADqDAAABQAcAG4MAAABABYADAAICeYNPhYATgEIaAwAAAcAPwBpDAAABgAxAGsMAAAGACQAagwAAAUAOABsDAAABQAgAG0MAAABABAA6gwAAAUAHABuDAAAAQAWAAAA.',
Br='Briggoker:BAEALgAECgMJAwAAAA==.Brigmahf:BAEALgAECgQJCQABLgAECgMJAwAIAAAAAA==.',
Ca='Carbonarra:BAEBLgAECn8mAAINAAYJiB3LJgB0AQZoDAAACABbAGkMAAAHAEAAawwAAAcAUgBqDAAABQBUAGwMAAAFAEgA6gwAAAYAQwANAAYJiB3LJgB0AQZoDAAACABbAGkMAAAHAEAAawwAAAcAUgBqDAAABQBUAGwMAAAFAEgA6gwAAAYAQwAAAA==.Catcam:BAEALgAECgYJBgAAAA==.',
Ch='Chetegos:BAEALgADCgYJBgABLgAECgkJOgAOAPEjAA==.Chíefsquirel:BAEALgAECgYJDAAAAA==.',
Da='Dadbanger:BAECLgAFFH8jAAMBAAgJCR44AABxAghoDAAABgBiAGkMAAAGAGAAawwAAAUASgBqDAAABgBfAGwMAAADAEQAbQwAAAEAJQDqDAAABwBhAG4MAAABAEEAAQAHCZweOAAAcQIHaAwAAAYAYgBpDAAABgBgAGsMAAAFAEoAagwAAAYAXwBtDAAAAQAlAOoMAAAHAGEAbgwAAAEAQQADAAEJkgVBFgBJAAFsDAAAAwAOAC4ABAp/KgACAQAICXAmCQIAhAMAAQAICXAmCQIAhAMAAAA=.Daeke:BAEALgADCgUJBQABLgAECgQJBwAIAAAAAA==.Daekeypoo:BAEALgAECgQJBwAAAA==.Darkvirgo:BAEALgAFFAMJAwABLgAFFAYJHgALAO0YAA==.',
De='Deathbeaver:BAEALgAECgQJBQABLgAECggJQgAEAEoeAA==.Destrom:BAEALgAECgkJEgAAAA==.',
Ep='Epilepticc:BAECLgAFFH8MAAIEAAQJxB0HFQBoAQRoDAAABABCAGkMAAADAFUAawwAAAIASwDqDAAAAwBNAAQABAnEHQcVAGgBBGgMAAAEAEIAaQwAAAMAVQBrDAAAAgBLAOoMAAADAE0ALgAECn88AAIEAAkJ6yK8DADIAgAEAAkJ6yK8DADIAgAAAA==.',
Et='Ethalon:BAECLgAFFH8IAAIFAAQJiwxpFwAcAQRoDAAAAwBIAGkMAAACABkAawwAAAEADwDqDAAAAgAOAAUABAmLDGkXABwBBGgMAAADAEgAaQwAAAIAGQBrDAAAAQAPAOoMAAACAA4ALgAECn8jAAMFAAkJHRonGABRAgAFAAkJHRonGABRAgAEAAIJlBMOKAE4AAAAAA==.',
Fa='Fallhp:BAEALgADCgYJBgABLgAFFAgJFgAFALUUAA==.Fallill:BAEALgAECgIJAgABLgAFFAgJFgAFALUUAA==.Falosso:BAECLgAFFH8WAAIFAAgJtRQRAQCbAghoDAAAAwA1AGkMAAADAEcAawwAAAMAQABqDAAAAwBLAGwMAAADAA0AbQwAAAEAHwDqDAAABQBQAG4MAAABACIABQAICbUUEQEAmwIIaAwAAAMANQBpDAAAAwBHAGsMAAADAEAAagwAAAMASwBsDAAAAwANAG0MAAABAB8A6gwAAAUAUABuDAAAAQAiAC4ABAp/MgADBQAJCY8gWwcA1QIABQAJCY8gWwcA1QIABAABCT0KgzkBMgAAAAA=.',
Ga='Garlooth:BAEBLgAECn8hAAIPAAgJqR5+AQBLAghoDAAABQBTAGkMAAAFAFMAawwAAAUATQBqDAAAAwAyAGwMAAAEAEkAbQwAAAMAXgDqDAAABQA+AG4MAAADAEoADwAICakefgEASwIIaAwAAAUAUwBpDAAABQBTAGsMAAAFAE0AagwAAAMAMgBsDAAABABJAG0MAAADAF4A6gwAAAUAPgBuDAAAAwBKAAAA.',
Gl='Glizzygary:BAEALgAFFAQJCAAAAQ==.',
Gr='Grimvalor:BAEBLgAECn9CAAMEAAgJSh6JJwAbAghoDAAACgBcAGkMAAAJAE0AawwAAAoAUgBqDAAACQBYAGwMAAAJAFkAbQwAAAYASwDqDAAACgBSAG4MAAADACoABAAICUoeiScAGwIIaAwAAAkAXABpDAAACQBNAGsMAAAJAFIAagwAAAgAWABsDAAACABZAG0MAAAGAEsA6gwAAAkAUgBuDAAAAwAqABAABQnPClAuAGEABWgMAAABAA8AawwAAAEALABqDAAAAQAsAGwMAAABACIA6gwAAAEADwAAAA==.Grunclaws:BAEALgAECgYJBgABLgAECgkJIAAEADQZAA==.Grunjitsu:BAEALgAECgkJBQABLgAECgkJIAAEADQZAA==.Grunsy:BAEALgAECgcJAgABLgAECgkJIAAEADQZAA==.',
Ha='Haf:BAEBLgAECn8pAAIQAAkJ8hHpDQCMAQloDAAABwA9AGkMAAAGAEIAawwAAAYARwBqDAAABQAjAGwMAAAFADYAbQwAAAMAFQDqDAAABgAvAG4MAAACABYAbwwAAAEAFwAQAAkJ8hHpDQCMAQloDAAABwA9AGkMAAAGAEIAawwAAAYARwBqDAAABQAjAGwMAAAFADYAbQwAAAMAFQDqDAAABgAvAG4MAAACABYAbwwAAAEAFwAAAA==.',
He='Hertzmuch:BAEALgADCgYJDgABLgAFFAQJDwADAGkNAA==.',
Ho='Holeighfuk:BAEALgAECgYJBgAAAA==.',
Jo='Joicountdown:BAEBLgAFFH8qAAIHAAgJ+CYFAAAUAwhoDAAABwBjAGkMAAAHAGQAawwAAAcAYgBqDAAABgBkAGwMAAADAGQAbQwAAAIAZADqDAAACQBkAG4MAAABAGQABwAICfgmBQAAFAMIaAwAAAcAYwBpDAAABwBkAGsMAAAHAGIAagwAAAYAZABsDAAAAwBkAG0MAAACAGQA6gwAAAkAZABuDAAAAQBkAAEuAAQKBgkGAAgAAAAA.',
Ka='Kautheros:BAEBLgAECn8cAAQRAAgJpwtQEQBqAQhoDAAABAAIAGkMAAAEABkAawwAAAQAOwBqDAAABAAfAGwMAAADACIAbQwAAAMACQDqDAAABAAmAG4MAAACAB0AEQAICacLUBEAagEIaAwAAAIACABpDAAAAgAZAGsMAAACADsAagwAAAIAHwBsDAAAAQAiAG0MAAADAAkA6gwAAAMAJgBuDAAAAgAdABIABglSCZxAANIABmgMAAABAB0AaQwAAAEAGABrDAAAAgAcAGoMAAABACQAbAwAAAIAFwDqDAAAAQAMABMAAwmaBooXAFgAA2gMAAABAAkAaQwAAAEAGABqDAAAAQAaAAAA.',
Kr='Kroxychi:BAEALgAECgcJDQAAAA==.Kroxypurple:BAEALgADCgIJAgABLgAECgcJDQAIAAAAAA==.',
Ku='Kungfused:BAECLgAFFH8PAAIDAAQJaQ07GQD6AARoDAAABQAqAGkMAAAFACUAawwAAAMAJgDqDAAAAgATAAMABAlpDTsZAPoABGgMAAAFACoAaQwAAAUAJQBrDAAAAwAmAOoMAAACABMALgAECn9QAAMDAAkJQx3ACgClAgADAAkJQx3ACgClAgABAAgJSRTPGgCJAQAAAA==.',
Le='Leenfiey:BAECLgAFFH8KAAMUAAMJXCNwFAAxAQNoDAAAAwBfAGkMAAADAFEA6gwAAAQAXQAUAAMJXCNwFAAxAQNoDAAAAgBfAGkMAAACAFEA6gwAAAIAXQABAAMJGA1HGgClAANoDAAAAQAAAGkMAAABADEA6gwAAAIAMgAuAAQKfxkAAxQABglMJd0UAGUCABQABgkrJd0UAGUCAAEAAQkdJQ5TAGoAAAAA.Lennather:BAEBLgAECn8zAAIBAAkJHCWUAQBAAwloDAAABwBjAGkMAAAHAGEAawwAAAYAWwBqDAAABgBOAGwMAAAGAGAAbQwAAAUAXgDqDAAABwBdAG4MAAAFAF8AbwwAAAIAWgABAAkJHCWUAQBAAwloDAAABwBjAGkMAAAHAGEAawwAAAYAWwBqDAAABgBOAGwMAAAGAGAAbQwAAAUAXgDqDAAABwBdAG4MAAAFAF8AbwwAAAIAWgAAAA==.',
Li='Lidrunka:BAEBLgAECn8WAAMBAAgJbhTVGwD9AQhoDAAABABKAGkMAAAEAD8AawwAAAMARABqDAAAAgAjAGwMAAACADYAbQwAAAEAHADqDAAABQA/AG4MAAABAAwAAQAICcoT1RsA/QEIaAwAAAMASgBpDAAAAwA0AGsMAAACAEQAagwAAAIAIwBsDAAAAgA2AG0MAAABABwA6gwAAAQAPwBuDAAAAQAMABQABAkWFOM4AN0ABGgMAAABACwAaQwAAAEAPwBrDAAAAQA7AOoMAAABACUAAS4ABAoJCSoAEQDVFQA=.',
['Lé']='Lépewpew:BAEBLgAECn8YAAIVAAcJSRLCGwBzAQdoDAAABQA+AGkMAAAFADMAawwAAAUAOwBqDAAAAwBNAGwMAAABACYA6gwAAAQAOgBuDAAAAQAKABUABwlJEsIbAHMBB2gMAAAFAD4AaQwAAAUAMwBrDAAABQA7AGoMAAADAE0AbAwAAAEAJgDqDAAABAA6AG4MAAABAAoAAAA=.',
Ma='Mattimus:BAEBLgAECn8VAAMWAAYJXg78XwBIAQZoDAAABAA9AGkMAAAEACUAawwAAAUAGgBqDAAAAwAkAGwMAAACABQA6gwAAAMAJQAWAAYJXg78XwBIAQZoDAAABAA9AGkMAAADACUAawwAAAQAGgBqDAAAAgAkAGwMAAACABQA6gwAAAIAJQAXAAQJ+QK2cAB8AARpDAAAAQABAGsMAAABAAkAagwAAAEACQDqDAAAAQAMAAAA.',
['Má']='Mákí:BAEALgAECggJEwAAAA==.',
Na='Natebanger:BAEALgAECgYJDAABLgAFFAgJIwABAAkeAA==.',
Ne='Nethertank:BAEALgAECgQJBAABLgAECgYJDAAIAAAAAA==.',
No='Noeyednuck:BAEALgAECgQJCQABLgAECgkJMgAWANUfAA==.',
Nu='Nuckshott:BAEBLgAECn8yAAIWAAkJ1R/CCgC+AgloDAAABwBdAGkMAAAHAFgAawwAAAcATgBqDAAABgBaAGwMAAAGAFgAbQwAAAUATgDqDAAABgBWAG4MAAAEAEQAbwwAAAIARQAWAAkJ1R/CCgC+AgloDAAABwBdAGkMAAAHAFgAawwAAAcATgBqDAAABgBaAGwMAAAGAFgAbQwAAAUATgDqDAAABgBWAG4MAAAEAEQAbwwAAAIARQAAAA==.',
Og='Ogx:BAEALgAECgQJBQABLgAECgkJIAAEADQZAA==.',
Ol='Olgass:BAEALgADCgIJAgABLgAECggJLQAYABMjAA==.',
Pu='Purlok:BAEALgAECgkJAwABLgAECgkJIAAEADQZAA==.',
Qu='Quindrox:BAEALgAECgkJCQABLgAECgkJGgAVAEQaAA==.Quinet:BAEBLgAECn8tAAMYAAgJEyOhDwCaAghoDAAABwBhAGkMAAAHAFwAawwAAAcAXABqDAAABgBRAGwMAAAFAFwAbQwAAAMAWADqDAAABwBeAG4MAAADAEcAGAAICRMjoQ8AmgIIaAwAAAcAYQBpDAAABgBcAGsMAAAHAFwAagwAAAEAEABsDAAAAwBcAG0MAAADAFgA6gwAAAcAXgBuDAAAAwBHABkAAwnKHnEvAP0AA2kMAAABAEYAagwAAAUAUQBsDAAAAgBXAAAA.Quinman:BAEBLgAECn8aAAQVAAkJRBpdDAAcAgloDAAABQBBAGkMAAAEADMAawwAAAQATwBqDAAAAgAnAGwMAAACAGEAbQwAAAIAOwDqDAAABABBAG4MAAACAD0AbwwAAAEAOgAVAAkJixddDAAcAgloDAAAAQA8AGkMAAABAAAAawwAAAEATwBqDAAAAgAnAGwMAAACAGEAbQwAAAIAOwDqDAAAAwBBAG4MAAACAD0AbwwAAAEAOgAXAAQJWhWQWQDfAARoDAAAAwBBAGkMAAADADMAawwAAAMAMQDqDAAAAQA0ABYAAQkVGCPPAD4AAWgMAAABAD0AAAA=.Quinroxx:BAEBLgAECn8gAAIGAAgJXCN8KwDFAghoDAAABQBiAGkMAAAFAFsAawwAAAUAXwBqDAAABQBeAGwMAAADAFoAbQwAAAIAUwDqDAAABgBhAG4MAAABAE0ABgAICVwjfCsAxQIIaAwAAAUAYgBpDAAABQBbAGsMAAAFAF8AagwAAAUAXgBsDAAAAwBaAG0MAAACAFMA6gwAAAYAYQBuDAAAAQBNAAEuAAQKCQkaABUARBoA.Quinvinvin:BAEALgAECgcJDQABLgAECgkJGgAVAEQaAA==.',
Ri='Rispirvoke:BAEALgADCgUJBgABLgAFFAgJDQAXAIIYAA==.',
Ro='Ronimus:BAEALgAECgEJAQAAAA==.',
Ru='Rufio:BAECLgAFFH8IAAIaAAIJeQ4SEwCWAAJoDAAABQA2AGkMAAADABMAGgACCXkOEhMAlgACaAwAAAUANgBpDAAAAwATAC4ABAp/HwACGgAICekb9gsAoQIAGgAICekb9gsAoQIAAAA=.',
Ry='Rytiou:BAECLgAFFH8SAAISAAUJKx1XBQCuAQVoDAAABABSAGkMAAAFAFYAawwAAAQALgBqDAAAAgBHAOoMAAADAFIAEgAFCSsdVwUArgEFaAwAAAQAUgBpDAAABQBWAGsMAAAEAC4AagwAAAIARwDqDAAAAwBSAC4ABAp/MgACEgAJCeckWQIAjAMAEgAJCeckWQIAjAMAAAA=.',
Sa='Saadxevok:BAEBLgAECn8YAAMTAAgJQRFLEADYAQhoDAAAAwA7AGkMAAADADEAawwAAAMARQBqDAAAAwAwAGwMAAAEAEgAbQwAAAMACADqDAAAAwAkAG4MAAACAAwAEwAICUERSxAA2AEIaAwAAAMAOwBpDAAAAwAxAGsMAAACAEUAagwAAAIAMABsDAAAAwBIAG0MAAABAAgA6gwAAAEAJABuDAAAAQAMABEABglTCD0pACkBBmsMAAABABAAagwAAAEAEQBsDAAAAQARAG0MAAACAB4A6gwAAAIAJwBuDAAAAQAGAAEuAAUUCAkjAAsAZB4A.Saadxm:BAEALgAECgcJDwABLgAFFAgJIwALAGQeAA==.Saadxp:BAECLgAFFH8jAAMLAAgJZB7JAABZAghoDAAABQBjAGkMAAAGAGAAawwAAAYAYABqDAAABgBYAGwMAAADACAAbQwAAAEAVADqDAAABwBeAG4MAAABACkACwAHCV0hyQAAWQIHaAwAAAQAYwBpDAAABQBgAGsMAAAFAGAAagwAAAUAWABtDAAAAQBUAOoMAAAFAF4AbgwAAAEAKQAbAAYJ5RnxAQANAgZoDAAAAQBJAGkMAAABAB0AawwAAAEAWgBqDAAAAQBOAGwMAAADADMA6gwAAAIASgAuAAQKfyUAAwsACAmHJrcDAGADAAsACAmHJrcDAGADABsABQkLHz4gAJEBAAAA.Sanityvanish:BAEALgAECgIJAwABLgAECgMJBAAIAAAAAA==.',
Sg='Sgtgigachad:BAEALgADCgYJBgABLgAFFAQJCAAIAAAAAQ==.',
Sp='Spilt:BAECLgAFFH8ZAAIGAAcJoBmvAQCMAgdoDAAABQBaAGkMAAAFAFQAawwAAAQALwBqDAAAAwAaAGwMAAABABAAbQwAAAEARgDqDAAABgBTAAYABwmgGa8BAIwCB2gMAAAFAFoAaQwAAAUAVABrDAAABAAvAGoMAAADABoAbAwAAAEAEABtDAAAAQBGAOoMAAAGAFMALgAECn8dAAIGAAkJySTjCgBtAwAGAAkJySTjCgBtAwAAAA==.Spiltmonk:BAEBLgAECn8YAAIBAAYJWh80HAD6AQZoDAAABABGAGkMAAAEAFEAawwAAAQAUgBqDAAABABMAGwMAAADAFIA6gwAAAUAVAABAAYJWh80HAD6AQZoDAAABABGAGkMAAAEAFEAawwAAAQAUgBqDAAABABMAGwMAAADAFIA6gwAAAUAVAABLgAFFAcJGQAGAKAZAA==.',
Su='Sunjo:BAEALgAECgkJBAABLgAECgkJIAAEADQZAA==.',
Ta='Taku:BAEALgAECgcJDQABLgAECggJHAARAKcLAA==.Taymeean:BAEALgAECgMJBAABLgAFFAMJBgASAGQJAA==.Tayvok:BAECLgAFFH8GAAISAAMJZAmTLQDGAANoDAAAAgAOAGkMAAADADAA6gwAAAEACQASAAMJZAmTLQDGAANoDAAAAgAOAGkMAAADADAA6gwAAAEACQAuAAQKfy8AAhIACQmQHB0KAHQCABIACQmQHB0KAHQCAAAA.',
Te='Tentickles:BAECLgAFFH8MAAILAAQJlx9HCAB8AQRoDAAAAwBIAGkMAAADAFsAawwAAAIAYQDqDAAABAA9AAsABAmXH0cIAHwBBGgMAAADAEgAaQwAAAMAWwBrDAAAAgBhAOoMAAAEAD0ALgAECn8UAAILAAgJeiJyCAD9AgALAAgJeiJyCAD9AgABLgAFFAgJIwABAAkeAA==.Tetakoawara:BAEALgAECgUJCwABLgAFFAMJCgAUAFwjAA==.',
Th='Thecheatt:BAEBLgAECn86AAMOAAkJ8SOgAwC6AgloDAAACQBjAGkMAAAJAGEAawwAAAoAYwBqDAAACABhAGwMAAAIAF0AbQwAAAIAWgDqDAAACABfAG4MAAACAEcAbwwAAAIAWQAOAAkJ3iOgAwC6AgloDAAABwBhAGkMAAAGAGEAawwAAAgAYwBqDAAABgBhAGwMAAAFAF0AbQwAAAIAWgDqDAAABABfAG4MAAACAEcAbwwAAAIAWQANAAYJCB51NQAiAQZoDAAAAgBjAGkMAAADAFEAawwAAAIANgBqDAAAAgAyAGwMAAADAE8A6gwAAAQARQAAAA==.',
Ty='Tyära:BAEBLgAECn8dAAMcAAgJSwvTfgAcAQhoDAAABgAYAGkMAAAGACQAawwAAAUAPgBqDAAAAwAXAGwMAAACAB4AbQwAAAEADQDqDAAABQAUAG4MAAABAA4AHAAHCUEJ034AHAEHaAwAAAUAEgBpDAAABQAZAGsMAAAEACYAagwAAAIAEwBsDAAAAQAeAOoMAAAEAA0AbgwAAAEADgAdAAcJtQrTIgDmAAdoDAAAAQAYAGkMAAABACQAawwAAAEAPgBqDAAAAQAXAGwMAAABAAcAbQwAAAEADQDqDAAAAQAUAAEuAAQKCAkwAAYAqBwA.',
Vi='Vigiz:BAEALgAECgYJBgAAAA==.Vilexie:BAEALgAECggJDwAAAA==.',
['Vì']='Vìgïz:BAEALgAECgEJAQABLgAECgYJBgAIAAAAAA==.',
Wa='Wafflé:BAEALgAECgIJAgAAAA==.',
Wh='Whitecrosses:BAEALgAECgEJAQABLgAECgcJGAAVAEkSAA==.',
Wi='Wiskystagger:BAEALgADCgEJAgAAAA==.',
Za='Zargan:BAEALgAECgcJCAABLgAECggJHAARAKcLAA==.',
Ze='Zertzz:BAEALgAFFAEJAQABLgAFFAUJFQALACIgAA==.',
Zi='Zibbz:BAEBLgAECn8zAAMSAAkJ9CTJAQBNAwloDAAABgBgAGkMAAAGAGMAawwAAAYAYgBqDAAABQBZAGwMAAAHAF8AbQwAAAYAXwDqDAAABgBbAG4MAAAHAFsAbwwAAAIAVwASAAkJ9CTJAQBNAwloDAAABQBgAGkMAAAFAGMAawwAAAUAYgBqDAAABABZAGwMAAAGAF8AbQwAAAYAXwDqDAAABQBbAG4MAAAGAFsAbwwAAAIAVwATAAcJyxrRBADZAQdoDAAAAQBOAGkMAAABAFAAawwAAAEARwBqDAAAAQBGAGwMAAABAEcA6gwAAAEAUwBuDAAAAQAZAAAA.Zinia:BAEBLgAECn8nAAICAAgJ3hlOCADcAQhoDAAABwBXAGkMAAAHAFIAawwAAAcAOQBqDAAABAA6AGwMAAAEAEwAbQwAAAIAMQDqDAAABgBCAG4MAAACACsAAgAICd4ZTggA3AEIaAwAAAcAVwBpDAAABwBSAGsMAAAHADkAagwAAAQAOgBsDAAABABMAG0MAAACADEA6gwAAAYAQgBuDAAAAgArAAAA.',
Zu='Zubbfist:BAEALgADCgcJBwABLgAECgkJMwASAPQkAA==.Zubbrael:BAEBLgAECn8kAAMLAAgJSxpiIwC9AQhoDAAABwBKAGkMAAAGAEUAawwAAAUARgBqDAAABABDAGwMAAAFADsAbQwAAAEAUgDqDAAABwBIAG4MAAABACoACwAHCU0ZYiMAvQEHaAwAAAUASgBpDAAABABFAGsMAAADAEYAagwAAAIAQwBsDAAAAwA7AOoMAAAFAEgAbgwAAAEAKgAbAAcJgwlGJABOAQdoDAAAAgAOAGkMAAACABUAawwAAAIAIwBqDAAAAgArAGwMAAACABIAbQwAAAEAEgDqDAAAAgATAAEuAAQKCQkzABIA9CQA.Zubbz:BAEBLgAECn8tAAMeAAgJLB6THgCaAghoDAAABwBeAGkMAAAIAFgAawwAAAgAUwBqDAAABQA9AGwMAAAFAFcAbQwAAAIAJQDqDAAACABYAG4MAAACADoAHgAICSwekx4AmgIIaAwAAAYAXgBpDAAABwBYAGsMAAAHAFMAagwAAAQAPQBsDAAABABXAG0MAAACACUA6gwAAAcAWABuDAAAAgA6ABoABgkhHDwTAJYBBmgMAAABAEoAaQwAAAEAUABrDAAAAQBQAGoMAAABADoAbAwAAAEAOwDqDAAAAQBBAAEuAAQKCQkzABIA9CQA.',
Zz='Zzertz:BAECLgAFFH8VAAILAAUJIiDTBwCDAQVoDAAABgBhAGkMAAAFAFMAawwAAAQAVABqDAAAAQBYAOoMAAAFAEAACwAFCSIg0wcAgwEFaAwAAAYAYQBpDAAABQBTAGsMAAAEAFQAagwAAAEAWADqDAAABQBAAC4ABAp/KwACCwAICf8iOgYAKQMACwAICf8iOgYAKQMAAAA=.',
['Àb']='Àbeel:BAEALgAECgMJAwABLgAECggJNgAKAAYeAA==.Àbel:BAEBLgAECn82AAMKAAgJBh5jBgASAghoDAAACQBXAGkMAAAKAFQAawwAAAgAWgBqDAAABwBeAGwMAAAFAD0AbQwAAAIAIwDqDAAACgBZAG4MAAADAFkACgAHCUYdYwYAEgIHaAwAAAgAVwBpDAAACQBUAGsMAAAFAFoAagwAAAUAXgBsDAAABQA9AOoMAAAJAFkAbgwAAAEAJAAJAAcJDhsMFwCMAQdoDAAAAQBJAGkMAAABAE8AawwAAAMATgBqDAAAAgBdAG0MAAACACMA6gwAAAEAOwBuDAAAAgBZAAAA.Àble:BAEALgADCgQJCQABLgAECggJNgAKAAYeAA==.',
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
