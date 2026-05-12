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

local lookup = {'Monk-Brewmaster','Monk-Windwalker','DeathKnight-Blood','Unknown-Unknown','Warrior-Fury','Priest-Shadow','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Druid-Feral','Druid-Guardian','Druid-Restoration','Warlock-Demonology','DemonHunter-Havoc','Mage-Frost','Paladin-Retribution','Monk-Mistweaver','Hunter-BeastMastery','Warlock-Destruction','DemonHunter-Devourer','Warlock-Affliction','Shaman-Restoration','Shaman-Elemental','Hunter-Marksmanship','Paladin-Holy','DemonHunter-Vengeance','Rogue-Subtlety','Rogue-Assassination','Priest-Holy','DeathKnight-Unholy','Warrior-Protection','DeathKnight-Frost','Rogue-Outlaw','Hunter-Survival','Warrior-Arms','Paladin-Protection','Priest-Discipline','Shaman-Enhancement',}
local provider = {region='US',realm='AltarofStorms',name='US',type='daily',zone=46,date='2026-05-11',data={Ab='Abomination:BAAALgAECgYJEwAAAA==.',
Ad='Addison:BAACLgAFFH8GAAIBAAUJhCIXBwBiAQVoDAAAAQBfAGkMAAABAE8AawwAAAEATgDqDAAAAgBXAG4MAAABAGQAAQAFCYQiFwcAYgEFaAwAAAEAXwBpDAAAAQBPAGsMAAABAE4A6gwAAAIAVwBuDAAAAQBkAC4ABAp/FgADAQAHCUYmXwwAyQIAAQAHCUYmXwwAyQIAAgABCZoVQnUAQQAAAS4ABRQHCSYAAwA8JgA=.Adedine:BAAALgADCgYJBwAAAA==.Adiina:BAAALgAECgUJCgAAAA==.Adina:BAAALgAFFAEJAQAAAA==.',
Ak='Ak:BAAALgAECgcJBgABLgADCgcJCAAEAAAAAA==.',
Al='Alianicus:BAAALgADCgIJAgAAAA==.',
Am='Amalthea:BAAALgAECgEJAQAAAA==.',
An='Ancalimon:BAAALgADCggJDAAAAA==.',
Ar='Arassar:BAAALgAECgUJCgAAAA==.Arieon:BAAALgAECgIJAgAAAA==.',
As='Ashfallen:BAAALgAECgYJCwAAAA==.',
At='Athenais:BAAALgADCgMJAwAAAA==.Atthegates:BAABLgAECn8iAAIFAAgJjB9JCAByAghoDAAABgBbAGkMAAAGAGAAawwAAAYAWwBqDAAAAgBRAGwMAAADAGAAbQwAAAIAFwDqDAAABwBSAG4MAAACAFMABQAICYwfSQgAcgIIaAwAAAYAWwBpDAAABgBgAGsMAAAGAFsAagwAAAIAUQBsDAAAAwBgAG0MAAACABcA6gwAAAcAUgBuDAAAAgBTAAAA.',
Au='Audric:BAABLgAECn8gAAIGAAgJOgz8GQB/AQhoDAAABgAeAGkMAAAFABcAawwAAAYARABqDAAABAAeAGwMAAAEACQAbQwAAAEAEADqDAAABAAjAG4MAAACAAkABgAICToM/BkAfwEIaAwAAAYAHgBpDAAABQAXAGsMAAAGAEQAagwAAAQAHgBsDAAABAAkAG0MAAABABAA6gwAAAQAIwBuDAAAAgAJAAAA.Auryx:BAAALgADCgUJBwAAAA==.',
Az='Azrel:BAAALgAECgYJBgAAAA==.',
Ba='Baddragon:BAACLgAFFH8SAAQHAAUJ5B42AQBuAQVoDAAABgBUAGkMAAAEAFYAawwAAAMAUgBqDAAAAgBKAOoMAAADAD8ABwAFCfQcNgEAbgEFaAwAAAQAUwBpDAAAAgBVAGsMAAACAEEAagwAAAEASgDqDAAAAgA/AAgABAngGoAOABkBBGgMAAACAFQAaQwAAAIAVgBrDAAAAQBSAOoMAAABABUACQABCc8HmR0ASgABagwAAAEAEwAuAAQKfyIABAcACAlFJUkKADoCAAgABgmPJXUQAHECAAcABwkBHEkKADoCAAkAAQk0CY9JAC8AAAAA.Baldow:BAAALgAECgMJAwAAAA==.Balji:BAAALgAECgQJBQAAAA==.Balto:BAACLgAFFH8UAAIKAAUJeSaFAADAAQVoDAAABQBkAGkMAAAEAGIAawwAAAUAYgBqDAAAAgBfAOoMAAAEAGEACgAFCXkmhQAAwAEFaAwAAAUAZABpDAAABABiAGsMAAAFAGIAagwAAAIAXwDqDAAABABhAC4ABAp/LgADCgAJCeomFAAABQQACgAJCeomFAAABQQACwAHCVwkXQMAdwIAAAA=.Bananabread:BAAALgADCgcJBwAAAA==.Bareback:BAAALgAECggJCAAAAA==.Bayleef:BAABLgAECn8oAAIMAAkJwxmLEgBKAgloDAAABQBMAGkMAAAFADwAawwAAAUAQQBqDAAABAA/AGwMAAAEAEkAbQwAAAQASQDqDAAACABdAG4MAAAEADUAbwwAAAEAIQAMAAkJwxmLEgBKAgloDAAABQBMAGkMAAAFADwAawwAAAUAQQBqDAAABAA/AGwMAAAEAEkAbQwAAAQASQDqDAAACABdAG4MAAAEADUAbwwAAAEAIQAAAA==.',
Be='Beardik:BAAALgAECgUJCgAAAA==.Beccs:BAAALgADCgIJAgAAAA==.Belac:BAAALgADCgcJCAABLgAECggJHgANAI8TAA==.Beldr:BAAALgAECggJDgAAAA==.Benito:BAAALgAECgUJDAAAAA==.',
Bi='Bigfarma:BAAALgAECgIJAgAAAA==.Bigmediumd:BAAALgAECgQJCQAAAA==.',
Bl='Bloodelfadin:BAAALgAECgIJAgAAAA==.Bloodláce:BAAALgADCgYJBgAAAA==.Bloodylegend:BAAALgAECgQJBwAAAA==.',
Bo='Bonedoctor:BAAALgADCgcJBwAAAA==.Bowsete:BAAALgAECgUJCwAAAA==.',
Br='Brotherhood:BAAALgAECggJCAAAAA==.Brugan:BAAALgADCgUJBQAAAA==.Brujita:BAAALgADCgEJAQAAAA==.Brujochingon:BAAALgAECgcJEwAAAA==.Brèè:BAABLgAECn8qAAIOAAkJ5Rz1BwDkAgloDAAABQBWAGkMAAAEAFEAawwAAAUAUwBqDAAABgBfAGwMAAAGAFAAbQwAAAQASQDqDAAACABQAG4MAAACACsAbwwAAAIAPQAOAAkJ5Rz1BwDkAgloDAAABQBWAGkMAAAEAFEAawwAAAUAUwBqDAAABgBfAGwMAAAGAFAAbQwAAAQASQDqDAAACABQAG4MAAACACsAbwwAAAIAPQAAAA==.',
Ca='Calice:BAAALgADCgEJAQAAAA==.Carinni:BAAALgADCgcJBwAAAA==.',
Ce='Cerbmonk:BAAALgADCgMJAwAAAA==.',
Ch='Chaosmind:BAAALgAECgEJAQAAAA==.Cheeseylock:BAEALgADCgMJAwABLgAECgUJDQAEAAAAAA==.Chiz:BAABLgAECn8XAAIPAAYJPRn9iQC+AQZoDAAABgBfAGkMAAAFAD0AawwAAAQAMABqDAAAAgBAAGwMAAACAEIA6gwAAAQAMwAPAAYJPRn9iQC+AQZoDAAABgBfAGkMAAAFAD0AawwAAAQAMABqDAAAAgBAAGwMAAACAEIA6gwAAAQAMwAAAA==.',
Ci='Ciabatta:BAAALgADCgcJDQAAAA==.',
Cl='Cl:BAABLgAECn8eAAINAAgJjxOgKwDCAQhoDAAABQBCAGkMAAAFACMAawwAAAYAQwBqDAAAAwA1AGwMAAAFAEMAbQwAAAIAKgDqDAAAAwAqAG4MAAABAB0ADQAICY8ToCsAwgEIaAwAAAUAQgBpDAAABQAjAGsMAAAGAEMAagwAAAMANQBsDAAABQBDAG0MAAACACoA6gwAAAMAKgBuDAAAAQAdAAAA.',
Co='Conall:BAABLgAECn8rAAIQAAkJshheGABKAgloDAAABgBKAGkMAAAGAFAAawwAAAUAQQBqDAAABQAqAGwMAAAGAFEAbQwAAAQAPgDqDAAABwBKAG4MAAADAB0AbwwAAAEAJAAQAAkJshheGABKAgloDAAABgBKAGkMAAAGAFAAawwAAAUAQQBqDAAABQAqAGwMAAAGAFEAbQwAAAQAPgDqDAAABwBKAG4MAAADAB0AbwwAAAEAJAAAAA==.Confetti:BAAALgAECgYJEQAAAA==.Copedandcash:BAAALgADCgIJAQAAAA==.Coprophagist:BAAALgADCgcJEgAAAA==.',
Cr='Croissants:BAAALgAECgQJBAAAAA==.',
Cu='Cuckdasenpai:BAAALgAECgMJAwAAAA==.',
Da='Dajova:BAAALgAECgMJAwAAAA==.Darkentity:BAAALgADCgMJAwAAAA==.',
De='Deadfist:BAAALgADCgcJDAABLgAECgYJDgAEAAAAAA==.Deathblooms:BAAALgADCgcJBwAAAA==.Deeznts:BAAALgAECgEJAgAAAA==.Dellz:BAAALgAECgEJAgAAAA==.Demonique:BAAALgAECgkJAQAAAA==.Demonklay:BAAALgAECgUJBQAAAA==.Demonskinker:BAAALgADCgEJAwAAAA==.Detholìs:BAAALgADCgkJCQABLgAECgUJCgAEAAAAAA==.',
Di='Dimfate:BAAALgAECgUJBgAAAA==.',
Dm='Dmaw:BAABLgAECn8ZAAMCAAYJZgyuKAD7AAZoDAAABQAgAGkMAAAFACoAawwAAAUAKABqDAAABAAkAGwMAAACAA0A6gwAAAQAHAACAAYJZgyuKAD7AAZoDAAAAgAgAGkMAAADACoAawwAAAIAKABqDAAAAQAkAGwMAAABAA0A6gwAAAIAHAARAAYJdwbjQgDTAAZoDAAAAwATAGkMAAACAAkAawwAAAMAFgBqDAAAAwAdAGwMAAABAAYA6gwAAAIADAAAAA==.',
Do='Dolø:BAAALgAFFAMJAwAAAA==.Doublmisting:BAABLgAECn8oAAMRAAkJwA94JACPAQloDAAABQAkAGkMAAAFACYAawwAAAUAPABqDAAABAAoAGwMAAAEABkAbQwAAAQAMADqDAAACAAyAG4MAAAEACEAbwwAAAEAHAARAAkJwA94JACPAQloDAAABAAkAGkMAAADACYAawwAAAQAPABqDAAAAwAoAGwMAAACABkAbQwAAAQAMADqDAAABAAyAG4MAAADACEAbwwAAAEAHAACAAcJFRD9HwA0AQdoDAAAAQAdAGkMAAACAC4AawwAAAEANgBqDAAAAQAXAGwMAAACACkA6gwAAAQANABuDAAAAQAWAAAA.Doñagladys:BAAALgAECgEJAQAAAA==.',
Dr='Dracosatyr:BAAALgAECgEJAQAAAA==.Dragonsloot:BAACLgAFFH8QAAMIAAUJmRHYFwAnAQVoDAAABABLAGkMAAAEADoAawwAAAMAFgBqDAAAAQAHAOoMAAAEABgACAAFCZkR2BcAJwEFaAwAAAQASwBpDAAABAA6AGsMAAACABYAagwAAAEABwDqDAAAAwAYAAkAAglXATYbAGwAAmsMAAABAAIA6gwAAAEABAAuAAQKfywABAgACQl8GgcIAGECAAgACQl8GgcIAGECAAkABwmhBPkUAAMBAAcAAgk1GNE7AD4AAAAA.Draks:BAAALgADCgYJCgAAAA==.Drizzitt:BAAALgAECgQJCgAAAA==.Drubeastin:BAABLgAECn8WAAISAAgJXReILACtAQhoDAAABAA/AGkMAAADADgAawwAAAMATwBqDAAAAwBRAGwMAAADAE0AbQwAAAIAKADqDAAAAwA8AG8MAAABACgAEgAICV0XiCwArQEIaAwAAAQAPwBpDAAAAwA4AGsMAAADAE8AagwAAAMAUQBsDAAAAwBNAG0MAAACACgA6gwAAAMAPABvDAAAAQAoAAAA.Druidia:BAAALgADCggJCAAAAA==.',
Dt='Dtaipona:BAAALgAECgYJBgAAAA==.',
['Dó']='Dónkey:BAAALgADCgQJBAAAAA==.',
['Dô']='Dôra:BAAALgAECgUJCgAAAA==.',
Ec='Eclemage:BAAALgAECgQJDwAAAA==.',
El='Elcaris:BAAALgADCggJDAAAAA==.Elementtamer:BAAALgADCgIJAgAAAA==.',
Er='Erza:BAAALgAECgEJAQAAAA==.',
Es='Esh:BAABLgAECn8aAAMNAAgJxCEHJwB1AghoDAAABABjAGkMAAAEAGAAawwAAAQAYwBqDAAAAwBhAGwMAAAEAGAAbQwAAAEANwDqDAAABQBjAG4MAAABADkADQAGCcIjBycAdQIGaAwAAAQAYwBpDAAABABgAGsMAAACAGMAbAwAAAIAYADqDAAABQBjAG4MAAABADkAEwAECUkZXyMAPQEEawwAAAIATABqDAAAAwBhAGwMAAACAD0AbQwAAAEANwAAAA==.',
Ev='Evildarkness:BAAALgADCgEJAQAAAA==.Evilemt:BAAALgAECgEJAgAAAA==.Evilmt:BAAALgADCgEJBAAAAA==.',
Fa='Fappio:BAAALgAECgMJBAABLgAECggJJwAJAGQjAA==.Faîth:BAAALgAECgUJCAABLgAECgkJIgAPAKsdAA==.',
Fl='Flamesshadow:BAAALgAECgUJBQAAAA==.',
Fo='Forgiven:BAACLgAFFH8HAAIUAAQJdiCOEACBAQRoDAAAAgBOAGkMAAABAFUAawwAAAIASADqDAAAAgBgABQABAl2II4QAIEBBGgMAAACAE4AaQwAAAEAVQBrDAAAAgBIAOoMAAACAGAALgAECn8fAAIUAAgJdSLuCACpAgAUAAgJdSLuCACpAgAAAA==.',
Fr='Frogsbreath:BAAALgAECgYJBwAAAA==.Frostitution:BAAALgADCgQJBAAAAA==.',
Fu='Fuma:BAAALgADCgEJAQAAAA==.',
Ga='Gairmet:BAAALgADCgUJBQAAAA==.Galdrel:BAAALgADCgIJAgAAAA==.Garavar:BAAALgAECgEJAQAAAA==.Garthann:BAAALgADCgcJBwAAAA==.',
Gn='Gnomegusta:BAAALgAECgEJAgAAAA==.',
Gr='Grimwhisper:BAAALgAECgQJBAAAAA==.',
Gt='Gts:BAAALgAECgQJBQAAAA==.',
Gu='Gullar:BAAALgADCggJCQAAAA==.Gullveig:BAABLgAECn8VAAIQAAcJQxcNRwCCAQdoDAAABQBUAGkMAAADAC4AawwAAAIAMABqDAAAAQAsAGwMAAACADwA6gwAAAYAPwBuDAAAAgA1ABAABwlDFw1HAIIBB2gMAAAFAFQAaQwAAAMALgBrDAAAAgAwAGoMAAABACwAbAwAAAIAPADqDAAABgA/AG4MAAACADUAAAA=.Gumption:BAAALgADCgQJBwAAAA==.Guxxi:BAAALgAECgEJAQAAAA==.',
Gw='Gwyndolin:BAAALgAECgUJCQAAAA==.',
Ha='Hallsblack:BAAALgADCgEJAQAAAA==.Handled:BAAALgAECgcJEAAAAA==.Harami:BAAALgAECgUJBgABLgAECggJHQAOAJMVAA==.Harindvssy:BAAALgADCgcJBwAAAA==.',
He='Hechisera:BAABLgAECn8bAAIPAAcJRhKvVgB4AQdoDAAABQA9AGkMAAAFAEIAawwAAAUALQBqDAAABAAoAGwMAAACAC0A6gwAAAUAOABuDAAAAQAFAA8ABwlGEq9WAHgBB2gMAAAFAD0AaQwAAAUAQgBrDAAABQAtAGoMAAAEACgAbAwAAAIALQDqDAAABQA4AG4MAAABAAUAAAA=.Hellmagi:BAAALgAECgcJDQAAAA==.Helmon:BAAALgAECgYJCAAAAA==.Hexson:BAABLgAECn8XAAQNAAgJrBIPbQCHAQhoDAAABABGAGkMAAADADQAawwAAAMAIwBqDAAAAwBIAGwMAAADADMAbQwAAAIAHgDqDAAABAA4AG4MAAABACQADQAICawSD20AhwEIaAwAAAMARgBpDAAAAwA0AGsMAAADACMAagwAAAIASABsDAAAAQAzAG0MAAABAB4A6gwAAAQAOABuDAAAAQAkABMABAlLDS1RAHoABGgMAAABACoAagwAAAEAJQBsDAAAAQArAG0MAAABAA8AFQABCdEJMxsAOgABbAwAAAEAGQAAAA==.',
Hi='Hizø:BAABLgAECn8VAAMWAAcJJhAiQACAAQdoDAAABQA0AGkMAAAFAFsAawwAAAQANgBqDAAAAQAHAGwMAAABAAkAbQwAAAEABgDqDAAABABEABYABwkmECJAAIABB2gMAAACADQAaQwAAAMAWwBrDAAAAwA2AGoMAAABAAcAbAwAAAEACQBtDAAAAQAGAOoMAAAEAEQAFwADCfAd6TUA5wADaAwAAAMATABpDAAAAgBTAGsMAAABAEYAAAA=.',
Ho='Hordeelf:BAACLgAFFH8fAAIQAAgJ/SMxAADkAghoDAAABgBdAGkMAAAGAGEAawwAAAUAXwBqDAAABQBYAGwMAAACAFcAbQwAAAEAXwDqDAAABQBRAG4MAAABAF0AEAAICf0jMQAA5AIIaAwAAAYAXQBpDAAABgBhAGsMAAAFAF8AagwAAAUAWABsDAAAAgBXAG0MAAABAF8A6gwAAAUAUQBuDAAAAQBdAC4ABAp/HAACEAAICWsmLAUAegMAEAAICWsmLAUAegMAAAA=.Hordeforsure:BAABLgAECn8UAAMYAAYJLh6sMACxAQZoDAAAAwBDAGkMAAAEAFMAawwAAAQAVwBqDAAAAwBJAGwMAAACAEUA6gwAAAQATQAYAAYJGh6sMACxAQZoDAAAAwBDAGkMAAADAFIAawwAAAQAVwBqDAAAAwBJAGwMAAACAEUA6gwAAAQATQASAAEJbiASuABTAAFpDAAAAQBTAAEuAAUUCAkfABAA/SMA.Hornfu:BAAALgAECgYJDgAAAA==.',
Hu='Hugemistake:BAAALgAECgEJAQABLgAECgkJLQAQAN0kAA==.Humanwolf:BAAALgAECgEJAgAAAA==.',
Il='Ilkyi:BAAALgADCgYJBgAAAA==.',
In='Inovar:BAACLgAFFH8IAAINAAMJYx94OAAFAQNoDAAAAwBVAGkMAAACAEEA6gwAAAMAWQANAAMJYx94OAAFAQNoDAAAAwBVAGkMAAACAEEA6gwAAAMAWQAuAAQKfyoAAg0ACQn9IX8GAOcCAA0ACQn9IX8GAOcCAAAA.',
Ir='Irismaria:BAAALgAECgIJAgAAAA==.',
Is='Istari:BAAALgADCgEJAgAAAA==.',
Iz='Izugzug:BAAALgAFFAMJBAABLgAFFAUJFAACAKMYAA==.',
Ja='Jaffejoffer:BAAALgADCgMJAwAAAA==.Jasto:BAAALgADCgIJBAABLgAECgkJLQAQAN0kAA==.Jazzy:BAAALgADCgcJDAAAAA==.',
Ju='Judgmentjudy:BAAALgAFFAIJAgABLgAFFAMJBwAZAMkPAA==.Jugjugs:BAAALgADCgUJBQAAAA==.Junko:BAAALgAECgcJEAAAAA==.',
Jx='Jxyy:BAAALgAECgYJBwAAAA==.',
Ka='Kachowdh:BAAALgAECgQJCAAAAA==.Kaijukami:BAAALgAECgMJAwAAAA==.Kaminey:BAABLgAECn8dAAMOAAgJkxWRCwDeAQhoDAAABABGAGkMAAAEAEQAawwAAAUAOgBqDAAABQA4AGwMAAAFAEkAbQwAAAEAJwDqDAAABAA6AG4MAAABABEADgAICZMVkQsA3gEIaAwAAAQARgBpDAAABABEAGsMAAAEADoAagwAAAQAOABsDAAABQBJAG0MAAABACcA6gwAAAIAOgBuDAAAAQARABoAAwlOBJkjAGUAA2sMAAABAAYAagwAAAEAGQDqDAAAAgAPAAAA.Kangarooz:BAAALgAECgUJCgAAAA==.Karlthuzad:BAAALgAECgQJBAAAAA==.Katrint:BAABLgAECn8dAAMbAAgJDyT6BwAzAghoDAAABQBdAGkMAAAEAFMAawwAAAMAWgBqDAAAAwBcAGwMAAAEAGEAbQwAAAIAYQDqDAAABwBfAG4MAAABAFgAGwAICQ8k+gcAMwIIaAwAAAQAXQBpDAAAAwBTAGsMAAADAFoAagwAAAMAXABsDAAAAgBhAG0MAAACAGEA6gwAAAcAXwBuDAAAAQBYABwAAwncG4MVAKIAA2gMAAABAEsAaQwAAAEASABsDAAAAgBBAAAA.',
Ke='Kekson:BAAALgADCgEJAQAAAA==.',
Kh='Kheliyah:BAACLgAFFH8UAAMdAAQJGiNTBgBxAQRoDAAABwBNAGkMAAAGAFoAawwAAAMAYgDqDAAABABdAB0ABAkaI1MGAHEBBGgMAAAHAE0AaQwAAAUAWgBrDAAAAwBiAOoMAAAEAF0ABgABCT4NvxQAUQABaQwAAAEAIQAuAAQKfxoAAh0ACAmhHkYQAGMCAB0ACAmhHkYQAGMCAAAA.',
Ki='Kippo:BAEALgAECgIJAwABLgAFFAUJBwAeAGUIAA==.Kiramouse:BAABLgAFFH8OAAMNAAQJAxpbIgD7AARoDAAABABTAGkMAAAEAEoAawwAAAIAGgDqDAAABABRAA0AAwkAGVsiAPsAA2gMAAAEAFMAawwAAAIAGgDqDAAABABRABMAAQkKHaYPAFwAAWkMAAAEAEoAAAA=.Kirawrxd:BAAALgAECgMJBQAAAA==.',
Kr='Kratoz:BAAALgAFFAEJAQABLgAFFAUJFAACAKMYAA==.',
Ky='Kyrié:BAABLgAECn8eAAIdAAYJgCG/HgDqAQZoDAAABwBgAGkMAAAHAE8AawwAAAcASwBqDAAAAgBUAGwMAAACAFwA6gwAAAUAVAAdAAYJgCG/HgDqAQZoDAAABwBgAGkMAAAHAE8AawwAAAcASwBqDAAAAgBUAGwMAAACAFwA6gwAAAUAVAAAAA==.',
La='Lanzadora:BAAALgAECgQJBgAAAA==.',
Le='Leiya:BAAALgAECgQJCAAAAA==.',
Li='Liability:BAABLgAECn8nAAIfAAkJbwT+FwAKAQloDAAABgAQAGkMAAAFAAwAawwAAAQABwBqDAAABgAOAGwMAAAEAA4AbQwAAAUADwDqDAAABgANAG4MAAACAAkAbwwAAAEAAgAfAAkJbwT+FwAKAQloDAAABgAQAGkMAAAFAAwAawwAAAQABwBqDAAABgAOAGwMAAAEAA4AbQwAAAUADwDqDAAABgANAG4MAAACAAkAbwwAAAEAAgAAAA==.Linez:BAAALgADCgQJBAAAAA==.',
Lo='Lockjaw:BAAALgAECgYJBAAAAA==.',
Ly='Lynxxy:BAACLgAFFH8FAAISAAMJ/A8xLwDuAANoDAAAAwA+AGkMAAABABYA6gwAAAEAJQASAAMJ/A8xLwDuAANoDAAAAwA+AGkMAAABABYA6gwAAAEAJQAuAAQKfygAAhIACAnbIOsQAFwCABIACAnbIOsQAFwCAAAA.',
Ma='Magital:BAAALgADCgcJCwABLgAFFAUJEAAIAJkRAA==.Makisan:BAAALgAECgcJDQAAAA==.Malis:BAAALgAECgcJDQAAAA==.',
Mc='Mcwusseena:BAAALgAECgEJAQAAAA==.',
Me='Medalea:BAAALgAECgEJAQAAAA==.Melara:BAAALgAECgEJAQAAAA==.Meowmeowmeow:BAAALgADCgYJBgAAAA==.Mew:BAAALgADCgcJCgAAAA==.',
Mi='Miasmata:BAABLgAECn8oAAIgAAgJCRvTAgAZAghoDAAABwBSAGkMAAAGAFYAawwAAAYARwBqDAAABQBCAGwMAAAFAEkAbQwAAAIAIQDqDAAABgBKAG4MAAADAD4AIAAICQkb0wIAGQIIaAwAAAcAUgBpDAAABgBWAGsMAAAGAEcAagwAAAUAQgBsDAAABQBJAG0MAAACACEA6gwAAAYASgBuDAAAAwA+AAAA.Mikeoxlongg:BAAALgAECggJCQAAAA==.Minavera:BAAALgADCgkJCQAAAA==.Mixmal:BAAALgAECgcJBwABLgAECgkJDAAEAAAAAA==.Miya:BAAALgADCgMJAwAAAA==.',
Ml='Mlgtotems:BAAALgADCgcJBgAAAA==.',
Mo='Mooshake:BAAALgAECgIJAwAAAA==.',
Mu='Muzuki:BAAALgAECgMJBAAAAA==.',
Na='Naianasha:BAAALgAECgMJAwABLgAECgUJEwAEAAAAAA==.Naraku:BAAALgADCgYJCAAAAA==.Nate:BAABLgAECn82AAIMAAkJmiDYAwA7AwloDAAACABCAGkMAAAHAFcAawwAAAcAXwBqDAAABwBbAGwMAAAHAFAAbQwAAAQAVADqDAAABwBeAG4MAAAEAFYAbwwAAAMAQAAMAAkJmiDYAwA7AwloDAAACABCAGkMAAAHAFcAawwAAAcAXwBqDAAABwBbAGwMAAAHAFAAbQwAAAQAVADqDAAABwBeAG4MAAAEAFYAbwwAAAMAQAAAAA==.',
Ne='Nenizaurio:BAAALgAECgQJBgAAAA==.Netherwalker:BAAALgADCgEJAQAAAA==.',
Ni='Nirgrim:BAAALgADCgUJBQAAAA==.',
No='Nobara:BAAALgAECgUJBQAAAA==.Noma:BAAALgADCgEJAQAAAA==.',
Nu='Nuxo:BAAALgAECgMJAwAAAA==.',
Ny='Nyxthar:BAAALgAECgQJCQAAAA==.',
Ol='Olakunei:BAAALgAECgYJDAAAAA==.Olunara:BAAALgAECgQJCgAAAA==.',
On='Onepiece:BAABLgAFFH8HAAIhAAMJ5hjfAwADAQNoDAAAAwBTAGkMAAACAEQA6gwAAAIAJgAhAAMJ5hjfAwADAQNoDAAAAwBTAGkMAAACAEQA6gwAAAIAJgABLgAFFAUJFAAKAHkmAA==.',
Ox='Oxytocin:BAAALgADCgcJBwAAAA==.',
Pa='Padme:BAAALgAECgQJBgABLgAECgUJCAAEAAAAAA==.',
Pe='Peeditty:BAAALgAECgEJAQAAAA==.',
Pn='Pnkrweb:BAAALgAECggJDwAAAA==.',
Po='Poudi:BAAALgAECgEJAQABLgAECggJDwAEAAAAAA==.',
Pr='Profitt:BAABLgAECn8mAAIPAAkJQR6mDQC/AgloDAAABwBYAGkMAAAGAFYAawwAAAYAWgBqDAAABABZAGwMAAAEAFoAbQwAAAIAJQDqDAAABQBYAG4MAAADAEsAbwwAAAEAPQAPAAkJQR6mDQC/AgloDAAABwBYAGkMAAAGAFYAawwAAAYAWgBqDAAABABZAGwMAAAEAFoAbQwAAAIAJQDqDAAABQBYAG4MAAADAEsAbwwAAAEAPQAAAA==.',
Qa='Qael:BAAALgADCgYJBQAAAA==.',
Qu='Quelana:BAAALgADCgEJAQAAAA==.Quygon:BAABLgAECn8tAAIQAAkJ3SQ5AwA2AwloDAAABgBjAGkMAAAGAGIAawwAAAUAXwBqDAAABQBiAGwMAAAGAGMAbQwAAAUAXADqDAAABwBjAG4MAAAEAFkAbwwAAAEAUAAQAAkJ3SQ5AwA2AwloDAAABgBjAGkMAAAGAGIAawwAAAUAXwBqDAAABQBiAGwMAAAGAGMAbQwAAAUAXADqDAAABwBjAG4MAAAEAFkAbwwAAAEAUAAAAA==.Quâsar:BAAALgAECggJCAABLgAECgkJIgAPAKsdAA==.',
Ra='Rabbidhalo:BAAALgADCgUJBQAAAA==.Rabbidlight:BAAALgAECgYJEwAAAA==.Rahnli:BAAALgADCgMJAwAAAA==.Rainey:BAAALgADCgIJAgAAAA==.Rajabra:BAAALgADCgEJAQAAAA==.Rasim:BAAALgADCgYJBAAAAA==.Rasoon:BAAALgAECgUJBgAAAA==.',
Re='Rellana:BAAALgADCgEJAQAAAA==.',
Ri='Riannasoli:BAAALgADCgMJAwAAAA==.',
Ro='Romolus:BAAALgADCgMJAwAAAA==.',
Ru='Rudderqi:BAABLgAECn8hAAIQAAgJDBk7KQDsAQhoDAAABQBPAGkMAAAFAFQAawwAAAUAPABqDAAABQBOAGwMAAAEAE8AbQwAAAEAJADqDAAABgBVAG4MAAACABYAEAAICQwZOykA7AEIaAwAAAUATwBpDAAABQBUAGsMAAAFADwAagwAAAUATgBsDAAABABPAG0MAAABACQA6gwAAAYAVQBuDAAAAgAWAAAA.',
Ry='Ryceps:BAAALgADCgUJBQAAAA==.',
Sa='Sageoffane:BAAALgADCgcJBwABLgAECgUJCgAEAAAAAA==.Salinedione:BAAALgADCgYJDQAAAA==.Samlxe:BAAALgAECgYJEAAAAA==.Satoru:BAAALgAECgEJAQAAAA==.Saurfang:BAAALgADCgEJAQABLgAFFAcJHgANAEodAA==.',
Se='Segen:BAAALgAECgQJDAAAAA==.Semip:BAAALgAECgUJDwAAAA==.Sen:BAABLgAECn8jAAQSAAgJISR3DACKAghoDAAABgBaAGkMAAAGAF8AawwAAAQAXwBqDAAAAwBUAGwMAAAFAF4AbQwAAAMAXADqDAAABgBXAG4MAAACAFsAEgAICYgidwwAigIIaAwAAAIASABpDAAAAwBXAGsMAAAEAF8AagwAAAEAJgBsDAAAAQBbAG0MAAACAFwA6gwAAAIAVwBuDAAAAgBbABgABgnqIUEkAAYCBmgMAAAEAFoAaQwAAAMAXwBqDAAAAgBUAGwMAAADAF4AbQwAAAEAWADqDAAAAwBAACIAAgkPFckwAIoAAmwMAAABADEA6gwAAAEAOgAAAA==.Seöul:BAAALgADCgUJBQAAAA==.',
Sh='Shadowdaddy:BAAALgADCgIJAgABLgAECgUJCgAEAAAAAA==.Shadowlands:BAAALgAECgEJAQAAAA==.Shaitan:BAAALgAECgcJEAABLgAECggJHQAOAJMVAA==.Shanoth:BAAALgADCgUJBQAAAA==.Shelton:BAAALgADCgQJBQAAAA==.Shizznitt:BAAALgAECgEJAQAAAA==.Shîver:BAABLgAECn8iAAIPAAkJqx2qKQDMAgloDAAABQBbAGkMAAAEAFwAawwAAAQAUgBqDAAABABfAGwMAAAEAFgAbQwAAAIAIwDqDAAABwBZAG4MAAADAD4AbwwAAAEAQAAPAAkJqx2qKQDMAgloDAAABQBbAGkMAAAEAFwAawwAAAQAUgBqDAAABABfAGwMAAAEAFgAbQwAAAIAIwDqDAAABwBZAG4MAAADAD4AbwwAAAEAQAAAAA==.',
Sk='Skaadooshh:BAACLgAFFH8UAAICAAUJoxjoBwBIAQVoDAAABgA/AGkMAAAEAEQAawwAAAMARgBqDAAAAgBHAOoMAAAFADEAAgAFCaMY6AcASAEFaAwAAAYAPwBpDAAABABEAGsMAAADAEYAagwAAAIARwDqDAAABQAxAC4ABAp/KAADAgAJCQMdsAcAAAMAAgAJCQMdsAcAAAMAAQADCZcUs2IAtwAAAAA=.Skippitypapz:BAAALgADCgIJAwABLgADCgcJBwAEAAAAAA==.Skyhealer:BAAALgAECgMJAwAAAA==.',
Sl='Slapcheeks:BAAALgADCgMJAwAAAA==.Slayèr:BAAALgAECgQJBAAAAA==.',
Sn='Snipedyou:BAAALgAECgEJAQAAAA==.Snomed:BAABLgAFFH8GAAIVAAIJKSLWAADaAAJoDAAAAQBPAOoMAAAFAF8AFQACCSki1gAA2gACaAwAAAEATwDqDAAABQBfAAEuAAUUBQkUAAoAeSYA.',
So='Soleah:BAAALgAECgIJAwAAAA==.',
Sp='Spillgar:BAABLgAECn8dAAIRAAcJKhdHFADNAQdoDAAABgA1AGkMAAAFAFMAawwAAAQAOgBqDAAABQA6AGwMAAAEADcAbQwAAAEAPQDqDAAABAAsABEABwkqF0cUAM0BB2gMAAAGADUAaQwAAAUAUwBrDAAABAA6AGoMAAAFADoAbAwAAAQANwBtDAAAAQA9AOoMAAAEACwAAAA=.',
St='Stantic:BAACLgAFFH8MAAQSAAYJbAeaDQDvAAZoDAAABQAhAGkMAAACABYAawwAAAIAIABqDAAAAQAJAGwMAAABAAUA6gwAAAEAAAASAAQJjQuaDQDvAARoDAAAAwAhAGkMAAACABYAawwAAAIAIABqDAAAAQAJABgAAwklAUwjAGMAA2gMAAABAAIAbAwAAAEABQDqDAAAAQAAACIAAQkcAscgAEUAAWgMAAABAAUALgAECn8dAAMSAAgJoB85IABEAgASAAgJwRs5IABEAgAYAAcJnhsOIgAVAgAAAA==.Statuskwo:BAAALgAECgcJDQABLgAECggJHgANAI8TAA==.Stevethuzad:BAAALgAECgQJBQAAAA==.Stormydaniel:BAAALgAECggJCgAAAA==.',
Su='Summergale:BAAALgADCgEJAQAAAA==.',
Sw='Swagadin:BAAALgAECgcJBwAAAA==.Swaglaives:BAAALgAECgEJAQAAAA==.Sweetbunz:BAAALgADCgQJBAAAAA==.',
Ta='Taezun:BAABLgAECn8hAAIUAAgJqh2WEwAyAghoDAAABgBZAGkMAAAFAFAAawwAAAUARgBqDAAABABOAGwMAAAEAFYAbQwAAAIAOwDqDAAABQBQAG4MAAACAD8AFAAICaodlhMAMgIIaAwAAAYAWQBpDAAABQBQAGsMAAAFAEYAagwAAAQATgBsDAAABABWAG0MAAACADsA6gwAAAUAUABuDAAAAgA/AAAA.Tanda:BAAALgADCgIJAgAAAA==.Tatertots:BAAALgADCgcJBwAAAA==.',
Th='Thebujieden:BAAALgAECgYJBwAAAA==.Thunderslap:BAAALgADCgEJAQAAAA==.',
Ti='Tiberiius:BAAALgAECgcJCgAAAA==.Tintan:BAAALgAECgYJDwAAAA==.Titus:BAABLgAECn8ZAAIDAAgJjCCJBgBGAghoDAAABABeAGkMAAAEAE0AawwAAAQATABqDAAAAwBWAGwMAAADAFsAbQwAAAIAQwDqDAAABABYAG4MAAABAFcAAwAICYwgiQYARgIIaAwAAAQAXgBpDAAABABNAGsMAAAEAEwAagwAAAMAVgBsDAAAAwBbAG0MAAACAEMA6gwAAAQAWABuDAAAAQBXAAAA.',
To='Toddhoward:BAAALgADCgEJAQAAAA==.Toes:BAAALgADCgUJBgAAAA==.Tooch:BAAALgAECgYJDAAAAA==.',
Tr='Triglock:BAAALgADCgUJBQABLgAECgQJBQAEAAAAAA==.Trigodun:BAABLgAECn8iAAMFAAgJzBc5JAA1AghoDAAABAA/AGkMAAAHAEYAawwAAAUAPQBqDAAAAwBAAGwMAAAEADcAbQwAAAIALgDqDAAABgBLAG4MAAADADQABQAICeoUOSQANQIIaAwAAAQAPwBpDAAABwBGAGsMAAAFAD0AagwAAAMAQABsDAAABAA3AG0MAAABABIA6gwAAAYASwBuDAAAAQAdACMAAglxE60uAHwAAm0MAAABAC4AbgwAAAIANAAAAA==.Trismegisto:BAAALgADCgUJBQAAAA==.',
Tu='Tulsuk:BAAALgADCgIJAgABLgAECggJIQAUAKodAA==.Tumsetius:BAAALgADCgcJCgAAAA==.',
Ul='Ulala:BAAALgAECgQJCQAAAA==.',
Un='Undedagaindk:BAACLgAFFH8bAAIeAAYJKh82AgD1AQZoDAAABgBgAGkMAAAGAGMAawwAAAUAYwBqDAAAAwBPAGwMAAABAA4A6gwAAAYAWgAeAAYJKh82AgD1AQZoDAAABgBgAGkMAAAGAGMAawwAAAUAYwBqDAAAAwBPAGwMAAABAA4A6gwAAAYAWgAuAAQKfxYAAx4ACQkCJiUKAEoDAB4ACQkCJiUKAEoDAAMAAgkLIAUkALcAAAAA.',
Up='Uppercut:BAAALgAECgIJAgAAAA==.',
Va='Valsanarne:BAAALgADCgEJAQAAAA==.Vanhowlsing:BAAALgAECgcJDwAAAA==.Vanillasquid:BAAALgAECgQJCQAAAA==.Vaxis:BAAALgAECgUJEwAAAA==.',
Ve='Vector:BAAALgAECgIJAgAAAA==.',
Vi='Vincentius:BAABLgAECn8nAAQkAAgJFxPnEAA+AQhoDAAABwAqAGkMAAAGADcAawwAAAUAKwBqDAAABQA2AGwMAAAFACsAbQwAAAQAMgDqDAAABQBNAG4MAAACABwAJAAICdAQ5xAAPgEIaAwAAAQAKgBpDAAABAAoAGsMAAAEABIAagwAAAUANgBsDAAABQArAG0MAAAEADIA6gwAAAQATQBuDAAAAgAcABAABAnmDjfbANYABGgMAAADAB8AaQwAAAEANwBrDAAAAQArAOoMAAABABQAGQABCe0BJKEAJwABaQwAAAEABAAAAA==.',
Vo='Volteil:BAABLgAECn8XAAICAAgJxR3oCQAuAghoDAAAAwBaAGkMAAAEAFYAawwAAAQASgBqDAAAAwBdAGwMAAACAFIAbQwAAAEAOADqDAAABABNAG4MAAACAEAAAgAICcUd6AkALgIIaAwAAAMAWgBpDAAABABWAGsMAAAEAEoAagwAAAMAXQBsDAAAAgBSAG0MAAABADgA6gwAAAQATQBuDAAAAgBAAAAA.',
Vy='Vyrric:BAABLgAECn8bAAIRAAgJQR5QBgCyAghoDAAABABhAGkMAAAEAE8AawwAAAQAXABqDAAABABaAGwMAAAEAFIAbQwAAAEALADqDAAABABQAG4MAAACADIAEQAICUEeUAYAsgIIaAwAAAQAYQBpDAAABABPAGsMAAAEAFwAagwAAAQAWgBsDAAABABSAG0MAAABACwA6gwAAAQAUABuDAAAAgAyAAAA.',
['Vì']='Vìi:BAAALgADCgYJBgAAAA==.',
Wa='Warstomp:BAAALgAECgYJCAAAAA==.',
We='Wetdog:BAAALgAECgYJBgABLgAFFAUJFAAKAHkmAA==.',
Wh='Whitelove:BAABLgAECn8oAAMlAAgJXhpSCQBXAghoDAAABwBXAGkMAAAGAFUAawwAAAYAUgBqDAAABQBCAGwMAAAFAD0AbQwAAAIAKwDqDAAABgBIAG4MAAADACkAJQAICV4aUgkAVwIIaAwAAAYAVwBpDAAABQBVAGsMAAAGAFIAagwAAAUAQgBsDAAABQA9AG0MAAABACsA6gwAAAUASABuDAAAAwApAB0ABAlqDUtkAJ0ABGgMAAABABIAaQwAAAEAMQBtDAAAAQASAOoMAAABADIAAAA=.Whitest:BAAALgAECgcJEQAAAA==.Whixx:BAAALgADCgEJAQABLgAECggJHQAmAJcUAA==.Whý:BAAALgAECggJDgAAAA==.',
Wi='Wikm:BAAALgAECgQJCAAAAA==.Wildseeker:BAAALgAECgYJCQAAAA==.Wiseoldman:BAAALgAECgcJDwAAAA==.',
Wo='Wounded:BAAALgAECgYJBgAAAA==.',
Wr='Wrench:BAAALgADCgcJBwAAAA==.',
Wu='Wulrick:BAAALgAECgcJEQAAAA==.',
Xa='Xalithrya:BAAALgAECgUJDAABLgAECgkJLQAQAN0kAA==.Xandyr:BAAALgADCgYJCQAAAA==.',
Xd='Xdamion:BAAALgADCgEJAQAAAA==.',
Xn='Xnaisa:BAABLgAECn8hAAIWAAgJNRq/DAB5AghoDAAABQBaAGkMAAAFAFQAawwAAAUAVABqDAAABQBSAGwMAAAEADoAbQwAAAEAHADqDAAABgBYAG4MAAACABMAFgAICTUavwwAeQIIaAwAAAUAWgBpDAAABQBUAGsMAAAFAFQAagwAAAUAUgBsDAAABAA6AG0MAAABABwA6gwAAAYAWABuDAAAAgATAAAA.',
Ye='Yekjr:BAAALgADCgIJAgAAAA==.Yenna:BAAALgAECgYJCQAAAA==.',
Yo='Yorna:BAAALgADCgEJAQAAAA==.',
Za='Zapey:BAABLgAECn8dAAImAAgJlxR/BwDGAQhoDAAABgA6AGkMAAAEAD4AawwAAAMAPgBqDAAABAAuAGwMAAAEADgAbQwAAAIAFwDqDAAABAA7AG4MAAACACwAJgAICZcUfwcAxgEIaAwAAAYAOgBpDAAABAA+AGsMAAADAD4AagwAAAQALgBsDAAABAA4AG0MAAACABcA6gwAAAQAOwBuDAAAAgAsAAAA.',
Ze='Zem:BAAALgAECgYJBgAAAA==.Zenezothe:BAAALgADCgMJAwAAAA==.Zerocharisma:BAAALgADCgUJCQAAAA==.',
Zh='Zhy:BAAALgADCgUJCAAAAA==.',
Zm='Zmr:BAACLgAFFH8GAAMWAAMJThX2JgDOAANoDAAAAgA1AGkMAAACAC8A6gwAAAIAPgAWAAMJThX2JgDOAANoDAAAAgA1AGkMAAACAC8A6gwAAAEAPgAXAAEJuRgqLQBSAAHqDAAAAQA/AC4ABAp/FQADFgAICUEZoj0AigEAFgAFCccboj0AigEAFwAHCescvCoAHwEAAAA=.Zmrr:BAAALgADCgIJAgABLgAFFAMJBgAWAE4VAA==.',
Zo='Zoomies:BAAALgAECgYJBgABLgAECggJJwAJAGQjAA==.',
['Zé']='Zémzel:BAAALgAECgQJBwAAAA==.',
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
