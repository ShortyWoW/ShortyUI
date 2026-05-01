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

local lookup = {'Evoker-Preservation','Evoker-Augmentation','Druid-Feral','DeathKnight-Blood','DemonHunter-Havoc','Unknown-Unknown','DemonHunter-Devourer','Druid-Guardian','Warrior-Fury','Hunter-BeastMastery','Hunter-Survival','DeathKnight-Unholy','Druid-Restoration','Monk-Brewmaster','Shaman-Enhancement','Paladin-Holy','Priest-Discipline','Priest-Shadow','Warrior-Protection','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Warlock-Affliction','Warlock-Demonology','Shaman-Restoration','Paladin-Retribution','Monk-Windwalker','DeathKnight-Frost','Warlock-Destruction','Priest-Holy','Hunter-Marksmanship','Shaman-Elemental','Monk-Mistweaver','Evoker-Devastation','Paladin-Protection','DemonHunter-Vengeance','Warrior-Arms','Mage-Frost','Druid-Balance',}
local provider = {region='US',realm='ScarletCrusade',name='US',type='weekly',zone=46,date='2026-05-01',data={Ac='Acefu:BAAALgAECgYJDAAAAA==.Acornita:BAACLgAFFH8KAAMBAAQJtQ1PEQCsAAABAAMJ5w9PEQCsAAACAAIJXQL2JQB4AAAuAAQKfygAAwEACQnlD0ERACgCAAEACQnlD0ERACgCAAIABwk9EoMYADkBAAAA.',
Ae='Aelana:BAAALgADCgkJCQAAAA==.',
Ai='Ailanthus:BAABLgAECn8YAAIDAAcJpw50CwAoAQADAAcJpw50CwAoAQAAAA==.',
Ak='Akinira:BAEBLgAECn8tAAIEAAkJNR6LAgA/AgAEAAkJNR6LAgA/AgAAAA==.',
Al='Aleinadris:BAAALgADCgQJBAAAAA==.Alikchi:BAAALgADCgEJAgAAAA==.Alloisaber:BAAALgAECgYJCAAAAA==.Alternis:BAAALgAECgMJAwAAAA==.',
An='Andrelsia:BAAALgAECgEJAQAAAA==.Andrilla:BAAALgAECgMJAwAAAA==.Ankeseth:BAAALgADCgcJBwAAAA==.',
Ap='Apôllyon:BAACLgAFFH8GAAIFAAMJLSJnBABAAQAFAAMJLSJnBABAAQAuAAQKfyUAAgUACQngJPAAAL4DAAUACQngJPAAAL4DAAAA.',
Ar='Aracelis:BAAALgAECgcJBwAAAA==.Aradius:BAAALgAECgEJAQABLgAECgIJBgAGAAAAAA==.Archertower:BAAALgADCgUJBQAAAA==.Artemiswynd:BAAALgADCgYJBgAAAA==.Arén:BAABLgAECn8QAAMHAAcJSSCHIgBkAQAFAAcJhx+WGwDkAQAHAAUJ3R6HIgBkAQAAAA==.',
As='Ashenshugär:BAAALgAECgIJAgAAAA==.',
Av='Avadda:BAABLgAECn8YAAIIAAcJsxHACwADAQAIAAcJsxHACwADAQAAAA==.',
Az='Azmar:BAAALgAECgYJEgAAAA==.',
Ba='Balain:BAAALgADCgcJBwABLgAECgUJEQAGAAAAAA==.',
Be='Bearmont:BAAALgAECgQJBAAAAA==.Bearzerk:BAABLgAECn8XAAIJAAYJqxI7JAAZAQAJAAYJqxI7JAAZAQAAAA==.Beastmonk:BAAALgADCgEJAQAAAA==.Benathar:BAAALgAECgYJEQAAAA==.',
Bi='Bifrost:BAAALgAECgMJAwAAAA==.Bionico:BAAALgAECgEJAwAAAA==.Birgir:BAAALgAECgEJAQAAAA==.',
Bl='Blackmagék:BAAALgADCgcJBwAAAA==.Bloodrager:BAAALgADCgIJAgAAAA==.Bloodthorn:BAAALgAECgcJEwAAAA==.Blortimor:BAAALgADCgcJBwAAAA==.',
Bo='Bombad:BAAALgAECgYJBwAAAA==.Boomnescient:BAAALgAECgQJBQAAAA==.Bozscaggs:BAABLgAECn8dAAMKAAgJtAwLRgCYAQAKAAgJtAwLRgCYAQALAAUJBQP6GwDOAAAAAA==.',
Br='Bramis:BAAALgADCgkJHAAAAA==.Brantu:BAAALgADCgQJCAABLgADCgkJDwAGAAAAAA==.Braultus:BAABLgAECn8cAAIEAAgJXhl/FwChAQAEAAgJXhl/FwChAQAAAA==.',
Bu='Burstangel:BAAALgAECgQJBAAAAA==.',
By='Byrddh:BAAALgADCgQJBAAAAA==.',
Ca='Cadenza:BAAALgAECgMJAwAAAA==.Caliopedk:BAACLgAFFH8FAAIMAAIJsBjYOACqAAAMAAIJsBjYOACqAAAuAAQKfxsAAwwACAlHIWEhALsCAAwACAlHIWEhALsCAAQABQlJDjQqAO0AAAAA.Capra:BAAALgADCgkJHwAAAA==.Carillanklip:BAAALgADCgUJBQAAAA==.',
Cd='Cdmickey:BAAALgADCgUJBQAAAA==.',
Ce='Celestè:BAAALgAECgcJEAAAAA==.Celéste:BAAALgAECgQJBAAAAA==.Cerdwin:BAAALgAECggJDAABLgAECggJJgANAK8XAA==.',
Ch='Charferad:BAAALgAECgMJAwAAAA==.Cheaptrick:BAAALgADCgcJCwAAAA==.Chibeard:BAABLgAECn8YAAIOAAcJZiGnBQBLAgAOAAcJZiGnBQBLAgAAAA==.Chonglin:BAAALgADCgIJAgAAAA==.',
Cl='Clearcast:BAAALgADCgkJCQAAAA==.Clubsdh:BAAALgAECgEJAQAAAA==.',
Co='Coolbro:BAAALgADCgIJAgAAAA==.Corialis:BAAALgAECgcJDwAAAA==.Counsel:BAAALgAECgUJBQAAAA==.',
Cr='Crom:BAABLgAECn8ZAAIPAAcJEAvwCQBHAQAPAAcJEAvwCQBHAQAAAA==.Crosis:BAAALgADCgYJBgAAAA==.Cruelladvoid:BAAALgAECgEJAQAAAA==.Cruush:BAAALgAECgYJBQAAAA==.',
Cu='Culerro:BAAALgAECgYJAwABLgAECgYJBQAGAAAAAA==.Cursive:BAAALgADCgUJDQAAAA==.',
Cy='Cygnes:BAABLgAECn8PAAIMAAgJjhexPQBGAQAMAAgJjhexPQBGAQAAAA==.',
Da='Daddywarrior:BAAALgADCgUJBgAAAA==.Daeva:BAAALgADCgEJAQAAAA==.Dantey:BAAALgADCgYJBgAAAA==.Dazanna:BAABLgAECn8VAAIQAAUJTRTPJQAaAQAQAAUJTRTPJQAaAQAAAA==.Dazre:BAAALgAECgUJBgAAAA==.',
De='Deeminor:BAAALgADCgkJEwAAAA==.Desktop:BAABLgAECn8cAAMRAAcJWRd+CgDmAQARAAcJWRd+CgDmAQASAAQJ3wqKIwDeAAAAAA==.',
Di='Diod:BAABLgAECn8cAAITAAcJWRVIDgA6AQATAAcJWRVIDgA6AQAAAA==.Divineßovine:BAAALgADCgcJBwAAAA==.',
Dr='Dracovoid:BAAALgADCgMJAwAAAA==.Draehton:BAAALgAECgQJBAAAAA==.Dragyns:BAACLgAFFH8HAAIUAAQJTBHAAQBVAQAUAAQJTBHAAQBVAQAuAAQKfyUABBQACQlEG4ACAMoCABQACQkQGYACAMoCABUABQmQGjosAJwBABYAAwmrFFIJANwAAAAA.Dragynseye:BAAALgADCgIJAgABLgAFFAQJBwAUAEwRAA==.Drayper:BAAALgAECgYJCwAAAA==.Druugal:BAABLgAECn8tAAMVAAgJVSJ+AgCXAgAVAAgJVSJ+AgCXAgAUAAEJegvnHwAzAAAAAA==.',
Du='Dubs:BAAALgAECgUJDwAAAA==.Dunbarke:BAAALgAECgUJDAAAAA==.',
Ef='Efishient:BAABLgAECn8aAAINAAYJVyS3CwBNAgANAAYJVyS3CwBNAgABLgAFFAUJFAANADkWAA==.',
El='Elisoria:BAAALgADCgMJAwAAAA==.Elliwynd:BAAALgAECgUJEgAAAA==.',
Eo='Eoshot:BAAALgAECgUJCAAAAA==.',
Er='Erinnys:BAAALgAECgYJEgAAAA==.Ermoril:BAAALgAECgMJAwAAAA==.Ernesta:BAAALgADCgcJCAAAAA==.',
Eu='Eufemia:BAAALgAECgEJAQAAAA==.',
['Eø']='Eøs:BAAALgAECgEJAQAAAA==.',
Fa='Famine:BAAALgAECgcJDAAAAA==.',
Fe='Felern:BAAALgAECgEJAgABLgAECgYJEgAGAAAAAA==.Feyrun:BAAALgADCgkJEwAAAA==.Feyrè:BAAALgADCgQJBQAAAA==.',
Fi='Finalomega:BAAALgAECgQJBQAAAA==.',
Fl='Flaminfalcon:BAAALgAFFAIJAgAAAA==.Flody:BAAALgAECgYJDAAAAA==.',
Fo='Foxflame:BAABLgAECn8mAAINAAgJrxf+DgAfAgANAAgJrxf+DgAfAgAAAA==.',
Fr='Franzen:BAAALgAECgEJAQAAAA==.Freakbob:BAAALgADCgYJCQAAAA==.Froglocky:BAABLgAECn8YAAMXAAcJVRQnAwCQAQAXAAcJVRQnAwCQAQAYAAMJcwRK9ABwAAAAAA==.Fronsac:BAAALgADCgQJBAAAAA==.',
Fu='Fulanita:BAAALgAECgQJCgAAAA==.',
Ga='Garzok:BAABLgAECn8XAAMXAAcJ8wmIBABSAQAXAAcJ8wmIBABSAQAYAAMJzQHWCAFLAAAAAA==.',
Ge='Genkithered:BAABLgAECn8YAAIZAAcJIRfUFQC6AQAZAAcJIRfUFQC6AQAAAA==.',
Gi='Gilernil:BAAALgAECgIJBAAAAA==.',
Gl='Gladtohelp:BAAALgAECgIJAgAAAA==.',
Gn='Gnoquarter:BAAALgADCgIJAgAAAA==.',
Gr='Gravemarks:BAABLgAECn8YAAMWAAgJjRNOAgDKAQAWAAgJjRNOAgDKAQAUAAQJzAncEQDoAAAAAA==.Grimhorn:BAAALgAECgQJBwAAAA==.Grimlie:BAAALgADCgkJDwAAAA==.Grimmrock:BAAALgAECgMJAwAAAA==.Grumblen:BAAALgADCgMJAwAAAA==.',
Gu='Guaritrice:BAAALgAECgQJBAAAAA==.Gubb:BAAALgAECgMJAwAAAA==.',
Gw='Gwenylane:BAABLgAECn8UAAIaAAgJ0wW/RAA7AQAaAAgJ0wW/RAA7AQAAAA==.Gwindor:BAAALgAECgEJAQAAAA==.Gwyndelyn:BAABLgAECn8XAAIbAAYJBgpgIADkAAAbAAYJBgpgIADkAAAAAA==.',
Ha='Hatterus:BAABLgAECn8aAAIaAAYJogk2YgDvAAAaAAYJogk2YgDvAAAAAA==.',
He='Herculeze:BAAALgAECgMJAwAAAA==.Hessian:BAAALgADCgEJAQAAAA==.',
Hi='Hillbroken:BAABLgAECn8mAAIcAAgJpRwgAQBWAgAcAAgJpRwgAQBWAgAAAA==.',
Ho='Holycross:BAAALgAECgIJAgAAAA==.Holysnow:BAAALgADCgMJAwABLgAECgYJCgAGAAAAAA==.',
Hu='Huntertidus:BAAALgAECgEJAQABLgAECgkJIAAaAB8VAA==.',
['Hà']='Hànks:BAAALgAECgcJCwAAAA==.',
Im='Imo:BAABLgAECn8VAAMdAAUJ+hQiFAB+AAAYAAUJcgzKqQAFAQAdAAQJ/xYiFAB+AAAAAA==.',
In='Intrepidz:BAAALgADCgcJCwABLgAFFAIJAgAGAAAAAA==.Inèvitable:BAABLgAECn8fAAIMAAgJTR0qDQBcAgAMAAgJTR0qDQBcAgAAAA==.',
Is='Istara:BAAALgADCgcJBwAAAA==.',
Ja='Javeech:BAAALgAECgYJEQAAAA==.',
Je='Jebib:BAAALgAECgYJBgABLgAFFAcJHgANAMYfAA==.Jeod:BAAALgAECgEJAQAAAA==.',
Jo='Jolty:BAACLgAFFH8HAAIMAAIJfyK+MgC+AAAMAAIJfyK+MgC+AAAuAAQKfycAAwwACQlWIrAMADUDAAwACQlWIrAMADUDAAQABAmcFpQRAAIBAAAA.',
Ka='Kaiou:BAAALgADCgMJBgAAAA==.Kantor:BAABLgAECn8mAAIeAAgJuhbdDADVAQAeAAgJuhbdDADVAQAAAA==.Karnstein:BAAALgAECgcJEgAAAA==.Kasenko:BAAALgAECgIJAgABLgAECgIJBAAGAAAAAA==.Kasryna:BAAALgAECgIJBAAAAA==.Kathinja:BAAALgAECgUJEgAAAA==.',
Ke='Kelumbria:BAAALgAECgcJCgAAAA==.Keta:BAAALgADCgYJBgAAAA==.Ketameanie:BAABLgAECn8UAAIHAAYJFBxeSADSAQAHAAYJFBxeSADSAQAAAA==.',
Ki='Kieran:BAAALgAECgQJBgAAAA==.Kitsunè:BAAALgAECgEJAQAAAA==.',
Km='Kmazing:BAAALgAECgYJDQAAAA==.',
Kn='Knifèparty:BAAALgAECgMJAwAAAA==.',
Ko='Konoha:BAABLgAECn8VAAMRAAUJLCNiCwDWAQARAAUJYyBiCwDWAQAeAAMJfiPeQwApAQAAAA==.',
Ku='Kultag:BAAALgAECgUJCgAAAA==.',
Ky='Kyaw:BAAALgAECgYJEgAAAA==.Kynzo:BAABLgAECn8gAAIDAAgJVRIUBwCOAQADAAgJVRIUBwCOAQAAAA==.',
La='Laykeezenith:BAACLgAFFH8SAAQfAAYJJh0eBwCrAQAfAAYJmxoeBwCrAQAKAAMJ7iKuIQDCAAALAAEJrweBFABRAAAuAAQKfxsABB8ACQmAISoVAIYCAB8ACAnqIioVAIYCAAoABAnAHrNVAMkAAAsAAgl3EgYoAHUAAAAA.Lazuli:BAABLgAECn8hAAIgAAgJnRMlNwB2AQAgAAgJnRMlNwB2AQAAAA==.',
Le='Lehann:BAABLgAECn8bAAIKAAgJcxDhGgC/AQAKAAgJcxDhGgC/AQAAAA==.',
Li='Lichtech:BAAALgAECgYJCQABLgAFFAUJDgACAKgcAA==.',
Lu='Luciselda:BAAALgADCgUJBgAAAA==.Lunariah:BAAALgADCgkJEwAAAA==.Luvtarhugar:BAAALgADCgMJAwAAAA==.',
Ma='Magdalene:BAEALgAECgEJAQAAAA==.Marenus:BAABLgAECn8kAAIKAAgJ0BCQHwCjAQAKAAgJ0BCQHwCjAQAAAA==.Masume:BAAALgADCgcJEwAAAA==.Maély:BAAALgAECgEJAgAAAA==.',
Me='Mechadead:BAAALgADCgIJAgAAAA==.Meowmix:BAAALgADCgUJCAAAAA==.',
Mi='Miantha:BAAALgAECgMJAwAAAA==.Michi:BAABLgAECn8jAAINAAgJ4iH3CAAAAwANAAgJ4iH3CAAAAwAAAA==.Midnights:BAAALgAECgYJCAAAAA==.Mightymopo:BAAALgADCgMJAwAAAA==.Mikuki:BAABLgAECn8aAAIKAAkJSiGmDQDRAgAKAAkJSiGmDQDRAgAAAA==.Milkinghands:BAABLgAECn8aAAMhAAkJvQ+tJQCFAQAhAAkJvQ+tJQCFAQAbAAEJlAILUgApAAAAAA==.Mizmonk:BAACLgAFFH8MAAIOAAQJIxURCgBCAQAOAAQJIxURCgBCAQAuAAQKfyIAAg4ACQnoHqUJAO4CAA4ACQnoHqUJAO4CAAAA.',
Mj='Mjölnir:BAAALgAECgEJAQAAAA==.',
Mo='Montfort:BAAALgADCggJDwAAAA==.Moovover:BAAALgAECggJCgAAAA==.',
Ms='Msmaho:BAAALgAECgMJAwAAAA==.',
Mu='Mushuu:BAAALgADCgcJBwAAAA==.',
My='Mykian:BAABLgAECn8YAAIiAAcJVwfaBgAoAQAiAAcJVwfaBgAoAQAAAA==.Myrwynn:BAAALgADCgcJDQABLgAECggJIAASAKQQAA==.Mythundon:BAAALgADCgUJBQAAAA==.',
Na='Nahion:BAAALgAECgEJAQAAAA==.Nashira:BAAALgAECgcJEgAAAA==.Nature:BAAALgAECgUJCwAAAA==.',
Ne='Necrana:BAAALgADCgEJAQAAAA==.Necrobyarg:BAAALgAECgYJDQAAAA==.Nemasus:BAABLgAECn8YAAINAAcJTx6yCgBdAgANAAcJTx6yCgBdAgAAAA==.Nembie:BAAALgADCgMJAwAAAA==.',
Ni='Ninjahh:BAAALgAECggJEgAAAA==.Nioshei:BAABLgAECn8YAAIZAAcJTBAoKAAuAQAZAAcJTBAoKAAuAQAAAA==.Nisara:BAABLgAECn8gAAMhAAgJZiB/CgCpAgAhAAgJZSB/CgCpAgAbAAcJRhbGIgDAAQAAAA==.',
No='Nochmuerta:BAAALgAECggJEAAAAA==.Nogrid:BAABLgAECn8mAAIjAAgJVBapBgC4AQAjAAgJVBapBgC4AQAAAA==.Notmyface:BAAALgAECgcJDAABLgAFFAMJBQAaAPgZAA==.',
Nu='Nuthar:BAABLgAECn8UAAIaAAYJmCFrOgA5AgAaAAYJmCFrOgA5AgAAAA==.',
Ny='Nyxandra:BAAALgAECgMJAwAAAA==.',
['Nò']='Nòhva:BAAALgAECgQJBAAAAA==.',
Ol='Oldeis:BAAALgAECgEJAQAAAA==.',
Om='Ominousowl:BAAALgAECgEJAgABLgAFFAIJAgAGAAAAAA==.',
Or='Oregizm:BAAALgAECgQJBAAAAA==.',
Pa='Pamburu:BAABLgAECn8jAAQKAAgJ9A0tJgCAAQAKAAgJpw0tJgCAAQAfAAYJtQXaDgDcAAALAAIJrQUOKgBgAAAAAA==.Papagrape:BAABLgAECn8aAAQBAAcJ8B/WAgB+AgABAAcJ8B/WAgB+AgACAAEJUgxvYgAyAAAiAAEJmgVkQgArAAAAAA==.Parzivàl:BAABLgAECn8kAAIQAAgJ4haaEwB1AgAQAAgJ4haaEwB1AgAAAA==.Paxa:BAAALgAECgYJEQAAAA==.',
Pe='Peacebox:BAAALgADCgcJCwABLgAECgYJDQAGAAAAAA==.Persayis:BAAALgAECgMJAwAAAA==.',
Ph='Phoebel:BAAALgADCgkJEgAAAA==.Phoenixbodhi:BAAALgAECgQJBAAAAA==.',
Po='Podnov:BAACLgAFFH8JAAMfAAQJehqABABYAQAfAAQJIxqABABYAQAKAAIJjh2iJAC0AAAuAAQKfyAAAh8ACQk6GwUOANECAB8ACQk6GwUOANECAAAA.',
Pr='Preyon:BAAALgAECgIJAwABLgAECgUJEQAGAAAAAA==.',
Py='Pyne:BAAALgADCgEJAQAAAA==.Pyrista:BAAALgAECgcJBQAAAA==.',
Qo='Qotho:BAABLgAECn8lAAIKAAgJ2hmXEgD+AQAKAAgJ2hmXEgD+AQAAAA==.',
Ra='Raistliin:BAAALgAECgYJDgAAAA==.Raithis:BAACLgAFFH8MAAIKAAQJBxR+CwBWAQAKAAQJBxR+CwBWAQAuAAQKfyYAAgoACQmmIMAEAEEDAAoACQmmIMAEAEEDAAAA.Ramhadin:BAEALgAECgEJAQABLgAECgYJCwAGAAAAAA==.',
Re='Rednaxel:BAABLgAECn8YAAIVAAcJ/CGyBAA/AgAVAAcJ/CGyBAA/AgAAAA==.Redvelvet:BAABLgAECn8XAAMhAAcJyQiSHgAMAQAhAAcJyQiSHgAMAQAbAAQJggbtWwCgAAAAAA==.Rekoner:BAABLgAECn8VAAIMAAUJJAzIYQDjAAAMAAUJJAzIYQDjAAAAAA==.Retarganator:BAABLgAECn8RAAMHAAcJmRnXHACHAQAHAAcJSBbXHACHAQAkAAQJjBjTEgAlAQAAAA==.',
Ri='Rixaa:BAAALgADCgMJAwABLgAECgUJDQAGAAAAAA==.',
Ro='Rocks:BAAALgAECgYJCAAAAA==.Romam:BAAALgAECgEJAQAAAA==.',
Ru='Rubyknight:BAAALgADCgYJCAAAAA==.',
Ry='Rykria:BAAALgADCgcJEQAAAA==.',
Sa='Samsonknight:BAAALgADCgYJBgAAAA==.Sanguinarian:BAABLgAECn8XAAIaAAgJHA2LPgBOAQAaAAgJHA2LPgBOAQAAAA==.',
Sc='Scrubtotem:BAAALgAECgMJAwAAAA==.',
Se='Secksiecutie:BAABLgAECn8VAAMcAAUJLxW+CQA6AQAcAAUJLxW+CQA6AQAEAAUJcAtBGwCgAAAAAA==.Selanda:BAAALgADCgcJEQAAAA==.Serinar:BAAALgAECgQJBgAAAA==.',
Sh='Shoshin:BAAALgAECgUJEQAAAA==.Shïvana:BAAALgAECgMJBgAAAA==.',
Si='Silversaiyan:BAABLgAECn8lAAMJAAcJZSEzCgAHAgAJAAcJZSEzCgAHAgAlAAEJXRh+OgBGAAAAAA==.',
Sl='Slade:BAABLgAECn8kAAMVAAgJaCElAgCoAgAVAAgJVyElAgCoAgAUAAMJzBpcDQCaAAAAAA==.Slap:BAAALgAECgEJAQAAAA==.Sliyce:BAAALgAECgIJBgAAAA==.',
Sm='Smóke:BAABLgAECn8mAAIHAAgJVRLMIQBoAQAHAAgJVRLMIQBoAQAAAA==.',
Sn='Snowfawn:BAAALgAECgYJCgAAAA==.',
So='Sofedan:BAABLgAECn8mAAIfAAgJnQpNBwBvAQAfAAgJnQpNBwBvAQAAAA==.Sorgath:BAAALgAECgIJAgAAAA==.Soriel:BAAALgADCgIJAgABLgAECgcJGAAIALMRAA==.Sorokwa:BAAALgAECgcJDgAAAA==.',
Sq='Squids:BAAALgADCgQJBAAAAA==.',
St='Strongstork:BAAALgAECgEJAQABLgAECgMJBwAGAAAAAA==.',
Su='Sunsword:BAAALgAECgYJEQAAAA==.Suriden:BAAALgADCgEJAQAAAA==.',
Sw='Swagidan:BAABLgAECn8ZAAIFAAgJbhb9EQBMAgAFAAgJbhb9EQBMAgAAAA==.Sweatermonk:BAAALgADCgIJAgABLgAECgYJBgAGAAAAAA==.Sweaterpally:BAAALgAECgYJBgAAAA==.Swiftera:BAABLgAECn8cAAIQAAgJURaDKADqAQAQAAgJURaDKADqAQAAAA==.Swiftlier:BAABLgAECn8hAAIOAAgJshnWDAC9AQAOAAgJshnWDAC9AQAAAA==.Swipegirl:BAAALgAECgYJCQAAAA==.',
Sy='Sylphrène:BAABLgAECn8fAAIFAAgJewanEAAzAQAFAAgJewanEAAzAQAAAA==.',
Ta='Taladan:BAAALgAECgEJAQAAAA==.Tandrana:BAAALgAECgMJAwAAAA==.Tankmepapi:BAAALgAECgMJAwAAAA==.Tanwen:BAAALgAECgYJDAAAAA==.Targypunch:BAAALgADCgcJBwABLgAECgcJEQAHAJkZAA==.Tatsunoshinn:BAAALgADCgEJAQAAAA==.',
Te='Techniqe:BAACLgAFFH8OAAICAAUJqBx9CQBjAQACAAUJqBx9CQBjAQAuAAQKfy0AAwIACAlXIhkHAAoDAAIACAlXIhkHAAoDACIABgkgIegSALMBAAAA.Techtides:BAAALgADCgUJBQABLgAFFAUJDgACAKgcAA==.Temperance:BAAALgADCgEJAQAAAA==.Temptations:BAAALgAECgEJAQAAAA==.Terminus:BAAALgAECgEJAQAAAA==.Terrylin:BAAALgAECgMJAwAAAA==.',
Th='Thaliá:BAAALgADCgkJFQAAAA==.Thomag:BAAALgADCgIJAgAAAA==.',
Ti='Ticebane:BAACLgAFFH8FAAMEAAQJ0gUFDwCxAAAEAAMJIgcFDwCxAAAMAAEJ4gG1eQA7AAAuAAQKfyMAAgQACQk0Ga8LAFgCAAQACQk0Ga8LAFgCAAAA.Tiduspullo:BAABLgAECn8gAAMaAAkJHxWQRAAWAgAaAAkJHxWQRAAWAgAjAAEJRw6mRgAnAAAAAA==.Tiduswar:BAABLgAECn8WAAITAAcJ9xczDABgAQATAAcJ9xczDABgAQABLgAECgkJIAAaAB8VAA==.Tinafay:BAAALgAECgcJDAAAAA==.Titanbeard:BAAALgADCgkJEAAAAA==.Titor:BAAALgAECgUJDgAAAA==.Tituspullo:BAAALgAECgUJBQABLgAECgkJIAAaAB8VAA==.',
To='Tolduan:BAAALgAECgUJDQAAAA==.Totemik:BAAALgADCgYJBgAAAA==.Toughturkey:BAAALgAECgMJBwAAAA==.',
Tr='Tremorhoof:BAAALgADCgIJAwAAAA==.Tresera:BAAALgADCgEJAQAAAA==.Tricarnetry:BAAALgAECgcJDwAAAA==.Trufleshufle:BAAALgAECggJEAAAAA==.',
Uh='Uhtread:BAAALgADCgYJBQAAAA==.',
Un='Unholyfury:BAAALgADCgYJBgAAAA==.',
Va='Vapor:BAAALgAECgMJAwAAAA==.Vaquinha:BAAALgADCgUJBQAAAA==.Varyel:BAAALgAECgIJAgAAAA==.',
Ve='Velianne:BAAALgADCgUJBQAAAA==.Vellinada:BAAALgADCgMJAwABLgAFFAMJCwAeAP8jAA==.Verakis:BAABLgAECn8YAAITAAcJeQ7yDwAgAQATAAcJeQ7yDwAgAQAAAA==.Verndarí:BAAALgAECgYJCgABLgAECggJIQAOALIZAA==.Vervain:BAAALgAECgUJBQAAAA==.',
Vo='Vortheus:BAAALgAECgQJCgAAAA==.Votollis:BAAALgAECgQJBQAAAA==.',
Wa='Warlanen:BAAALgAECgEJAQAAAA==.Warning:BAAALgADCgUJBQAAAA==.Warpiggies:BAAALgADCgkJCAAAAA==.',
Wi='Widdy:BAAALgAECgYJDgAAAA==.Willbur:BAABLgAECn8mAAImAAgJVBWOKQC+AQAmAAgJVBWOKQC+AQAAAA==.Wittledwagon:BAAALgADCgkJCQAAAA==.',
Wu='Wurthwhile:BAAALgAECgIJAgAAAA==.',
Wy='Wylaniris:BAAALgADCgQJBAAAAA==.Wyndywalker:BAABLgAECn8VAAInAAcJTwWVKgC3AAAnAAcJTwWVKgC3AAAAAA==.',
Xa='Xaveil:BAAALgADCgEJAQAAAA==.',
Xe='Xenosian:BAAALgAECgkJCQAAAA==.',
Xi='Xinnuo:BAAALgAECgIJAQAAAA==.',
Xy='Xydias:BAAALgAECggJCgAAAA==.Xyra:BAAALgADCgcJBwAAAA==.',
Yo='Yoku:BAAALgAECggJEwAAAA==.',
Za='Zalgarian:BAAALgAECgMJAwAAAA==.Zamønk:BAABLgAECn8XAAMOAAcJFg8bOABqAQAOAAcJFg8bOABqAQAbAAIJYAxwbgBXAAAAAA==.Zaphoidvtwo:BAAALgADCgcJBwAAAA==.Zason:BAAALgADCgMJAwAAAA==.Zatari:BAAALgADCgMJAwAAAA==.',
Ze='Zelectie:BAABLgAECn8XAAIIAAgJbhcwCgD3AQAIAAgJbhcwCgD3AQAAAA==.Zelzaikin:BAAALgAECgIJAgAAAA==.Zevon:BAAALgADCgkJCQAAAA==.',
Zi='Zinazarinara:BAAALgADCgQJDQAAAA==.Zirril:BAAALgADCgcJDwAAAA==.',
Zo='Zombiechick:BAAALgAECgMJBAAAAA==.',
['ßr']='ßrigitte:BAAALgADCgkJEQAAAA==.',
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
