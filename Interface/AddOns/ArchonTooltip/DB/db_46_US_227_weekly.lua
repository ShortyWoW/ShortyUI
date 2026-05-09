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

local lookup = {'Warlock-Demonology','Paladin-Retribution','Warlock-Destruction','DeathKnight-Unholy','DemonHunter-Devourer','Warrior-Protection','Rogue-Assassination','Paladin-Protection','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Enhancement','Shaman-Restoration','Paladin-Holy','DeathKnight-Blood','Warrior-Fury','Warrior-Arms','DemonHunter-Vengeance','DemonHunter-Havoc','Mage-Frost','Evoker-Devastation','Unknown-Unknown','Druid-Restoration','DeathKnight-Frost','Druid-Balance','Monk-Windwalker','Monk-Mistweaver','Priest-Holy','Evoker-Augmentation','Evoker-Preservation','Mage-Arcane','Mage-Fire','Priest-Discipline','Shaman-Elemental','Druid-Guardian','Hunter-Survival','Monk-Brewmaster','Rogue-Subtlety',}
local provider = {region='US',realm='TwistingNether',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abharn:BAAALgAECgUJBwAAAA==.',
Ak='Akeera:BAABLgAECn8VAAIBAAcJTw4tSwBHAQABAAcJTw4tSwBHAQAAAA==.Akkiya:BAAALgAECgYJDwABLgAFFAMJBwACAP8JAA==.',
Al='Althtar:BAAALgADCgQJBAAAAA==.',
Am='Amalyn:BAAALgAECgYJCAAAAA==.Amarantha:BAABLgAECn8VAAMDAAgJswTAEADSAAADAAcJOAXAEADSAAABAAEJmAFk8gAXAAAAAA==.',
An='Anaesthetize:BAAALgADCgYJCwAAAA==.Aness:BAAALgAECgcJEgAAAA==.Angelinalizy:BAAALgADCgkJCQAAAA==.Animagon:BAAALgADCgkJCQAAAA==.Animaker:BAABLgAECn8qAAIEAAkJ3RR+HAAeAgAEAAkJ3RR+HAAeAgAAAA==.Anngus:BAAALgADCgcJCAAAAA==.Anvilkrash:BAAALgADCgcJCwAAAA==.',
Ar='Ariese:BAAALgADCgcJCAAAAA==.',
As='Ashido:BAAALgAECgUJBwAAAA==.Astreos:BAABLgAFFH8FAAIBAAUJoBcGHgA9AQABAAUJoBcGHgA9AQABLgAFFAcJGQAFAFceAA==.Astrikin:BAAALgAECgYJDwABLgAFFAcJGQAFAFceAA==.',
Au='Auraiel:BAAALgADCgcJFAAAAA==.Aurorastar:BAAALgAECgEJAQAAAA==.',
Ba='Baultier:BAAALgADCgkJDgAAAA==.',
Be='Bel:BAABLgAECn8tAAIGAAgJliJ2AgC+AgAGAAgJliJ2AgC+AgAAAA==.Beraxes:BAAALgAECgYJDwAAAA==.',
Bl='Blasser:BAABLgAECn8WAAIHAAYJcyHPBQAoAgAHAAYJcyHPBQAoAgAAAA==.Blizizdumz:BAABLgAECn8nAAMIAAcJRx/3CQCjAQAIAAYJjyH3CQCjAQACAAYJXh6/PQCNAQAAAA==.',
Bm='Bmcgilicuddy:BAAALgAECgUJBAAAAA==.',
Br='Bralindra:BAAALgAECgEJAgAAAA==.Breadpitt:BAAALgADCgkJCgAAAA==.Brewdhism:BAAALgAECgMJAwAAAA==.Brillane:BAAALgADCgUJAwAAAA==.',
Bu='Bulsy:BAACLgAFFH8HAAMJAAMJvRhWIgAMAQAJAAMJvRhWIgAMAQAKAAEJcgHrHgA2AAAuAAQKfxsAAwkACQlbF/IhANEBAAkACQlbF/IhANEBAAoABAmQBORoAJsAAAAA.',
Ca='Calamidade:BAABLgAECn8qAAMLAAkJdQTQCwBNAQALAAkJdQTQCwBNAQAMAAMJdwHNegA4AAAAAA==.Calashlar:BAAALgAECgIJBQAAAA==.Camri:BAAALgADCgMJAwAAAA==.Capwnd:BAAALgAECgMJAwAAAA==.',
Ce='Cerryan:BAABLgAECn8eAAINAAYJphEfJgBZAQANAAYJphEfJgBZAQAAAA==.Cexar:BAAALgAECgcJDAAAAA==.',
Ch='Chaoticprime:BAAALgADCgEJAQAAAA==.Charivium:BAAALgADCgQJBAAAAA==.Chaòs:BAAALgADCgMJAwAAAA==.Chinup:BAABLgAECn8yAAIOAAkJCiDMAgC7AgAOAAkJCiDMAgC7AgAAAA==.',
Cl='Clother:BAACLgAFFH8UAAMPAAUJex5IBACwAQAPAAUJ7RhIBACwAQAQAAUJiRz3AQBkAQAuAAQKfxoAAw8ACAkEIfoKAAQDAA8ACAkEIfoKAAQDABAABgnmIF8HAEkCAAAA.',
Co='Cokenopepsi:BAABLgAECn8UAAIOAAgJExw8DACxAQAOAAgJExw8DACxAQAAAA==.',
Cr='Crackle:BAAALgADCgcJDAAAAA==.Crazyhorse:BAAALgAECgYJCwAAAA==.Cristos:BAAALgADCgYJCwAAAA==.',
Cu='Curses:BAAALgAECggJEAAAAA==.',
['Cø']='Cøløssus:BAAALgAECgEJAQAAAA==.',
Da='Daddypie:BAABLgAECn8kAAMRAAgJTSM/AQC2AgARAAgJMyM/AQC2AgASAAEJdR0QNQBTAAAAAA==.Damasscus:BAAALgAECgYJBgAAAA==.Darkdesire:BAAALgADCgUJBQAAAA==.',
Di='Disney:BAABLgAECn8WAAIHAAcJsRLOCgCDAQAHAAcJsRLOCgCDAQAAAA==.',
Dj='Djaztech:BAABLgAECn8YAAMPAAgJgh7oGQB9AgAPAAgJgh7oGQB9AgAQAAMJBhK/LABtAAAAAA==.',
Do='Donkie:BAABLgAECn8eAAIJAAcJ+R9/FgAbAgAJAAcJ+R9/FgAbAgAAAA==.',
Dr='Dracsano:BAAALgAECgEJAQABLgAECggJFAAFANkIAA==.Dreamzz:BAAALgADCgMJAwAAAA==.Drixadin:BAAALgAECgQJBwAAAA==.Drshockêr:BAABLgAECn8pAAMMAAgJ1Ri1IwCZAQAMAAYJMha1IwCZAQALAAgJ9wm4CwBPAQAAAA==.',
Ds='Dsakony:BAAALgAECggJEwAAAA==.',
Du='Duthir:BAACLgAFFH8IAAIEAAMJ6gxlUQDsAAAEAAMJ6gxlUQDsAAAuAAQKfyYAAgQACAnRGsk/ADkCAAQACAnRGsk/ADkCAAAA.',
Ea='East:BAAALgAECgYJEwAAAA==.',
Ed='Edd:BAAALgAECgEJAQAAAA==.',
Eg='Egrok:BAAALgAECgYJEQAAAA==.',
Em='Emaeel:BAAALgAECgcJCwAAAA==.',
En='Envyqt:BAAALgADCgEJAQAAAA==.',
Es='Esso:BAABLgAFFH8HAAIEAAMJmwyQUQDsAAAEAAMJmwyQUQDsAAAAAA==.',
Fa='Faelenor:BAAALgAECgYJCAAAAA==.Faelure:BAABLgAECn8XAAICAAcJiwlmgADrAAACAAcJiwlmgADrAAAAAA==.',
Fi='Fiddleoux:BAAALgAECgYJEAAAAA==.Fiending:BAAALgAECgEJAQAAAA==.Finnarius:BAAALgADCgYJBgAAAA==.Firenze:BAAALgAECgYJDQAAAA==.',
Fo='Foros:BAABLgAECn8ZAAINAAYJsCUrEACSAgANAAYJsCUrEACSAgAAAA==.',
Fr='Frozone:BAABLgAECn8aAAITAAcJYhbkVwBmAQATAAcJYhbkVwBmAQAAAA==.Fryiertuck:BAAALgAECgYJCgAAAA==.',
Ga='Gabil:BAABLgAECn8eAAIUAAcJvQmPCAAjAQAUAAcJvQmPCAAjAQAAAA==.Gaunshots:BAAALgAECgQJBwABLgAECggJEAAVAAAAAA==.',
Ge='Gendorosan:BAABLgAECn8eAAIWAAcJ8yG0DQBzAgAWAAcJ8yG0DQBzAgAAAA==.',
Gn='Gnork:BAAALgAECgcJEQAAAA==.',
Go='Goldwolf:BAAALgADCgYJBgAAAA==.Gotarrnianan:BAAALgAECgEJAgAAAA==.',
Gr='Grandmasterx:BAAALgAECgIJAwAAAA==.Gravewurm:BAAALgAECgEJAQAAAA==.Grayfoxx:BAABLgAECn8cAAIEAAcJ8BirMQCzAQAEAAcJ8BirMQCzAQAAAA==.Grayhard:BAAALgAECgYJBwAAAA==.Greenhornn:BAAALgADCgQJBAAAAA==.Grìmmgor:BAACLgAFFH8PAAIXAAMJayOqAAA2AQAXAAMJayOqAAA2AQAuAAQKfysAAhcACQmDIksAAIgDABcACQmDIksAAIgDAAAA.',
['Gô']='Gôôdbye:BAAALgAECgYJCgAAAA==.',
['Gö']='Gööse:BAAALgAECgcJBwAAAA==.',
Ha='Hado:BAAALgAECgQJBAAAAA==.Halbrand:BAACLgAFFH8FAAIEAAIJKApwfgCUAAAEAAIJKApwfgCUAAAuAAQKfxsAAgQACAm5GTkuAMEBAAQACAm5GTkuAMEBAAEuAAUUBAkHABgA4hIA.Hamburgmeat:BAAALgADCgYJBQAAAA==.',
He='Healovathyme:BAABLgAECn8ZAAIWAAgJcSJkEABRAgAWAAgJcSJkEABRAgAAAA==.Hellstomper:BAAALgAECgMJBgAAAA==.Heygrlhey:BAABLgAECn8tAAMJAAkJzR7CBADnAgAJAAkJzR7CBADnAgAKAAQJRwesYAC+AAAAAA==.',
Hi='Hidaoushi:BAAALgADCgkJCQAAAA==.',
Ho='Holdstillbro:BAAALgADCgEJAQABLgAECgkJMgAOAAogAA==.',
Hu='Hukkaluzul:BAAALgAECgEJAQAAAA==.Humaladin:BAAALgAECgEJAQAAAA==.Hungryghost:BAAALgAECgkJCwAAAA==.Hunna:BAABLgAECn8WAAIJAAgJ3hVJHgDmAQAJAAgJ3hVJHgDmAQAAAA==.Hurtzdonit:BAAALgADCgIJAgAAAA==.',
Hv='Hvtn:BAAALgAECgYJEAAAAA==.',
Ic='Icyfractals:BAAALgADCgQJBQAAAA==.',
In='Inebriated:BAABLgAECn8UAAIJAAcJzAngbAAhAQAJAAcJzAngbAAhAQAAAA==.',
Io='Iondia:BAAALgAECgQJBgAAAA==.',
Is='Iselune:BAAALgAECgIJAgAAAA==.',
Iz='Izanami:BAAALgAECgEJAQAAAA==.',
Ja='Jambi:BAAALgAECgMJBgAAAA==.Jandrina:BAAALgADCgYJCgAAAA==.Jardran:BAAALgAECgEJAgAAAA==.',
Jo='Joanchokkea:BAAALgADCgcJDgAAAA==.Joankorel:BAAALgADCgkJCQAAAA==.Jolty:BAAALgAECgEJAQABLgAFFAQJCwAEACUeAA==.',
Ka='Kael:BAAALgAECgQJBAAAAA==.Kahira:BAEALgADCgQJBAAAAA==.Kalidra:BAAALgAECgMJAwAAAA==.Kaname:BAAALgADCgYJCQABLgAECgUJEAAVAAAAAA==.',
Ke='Kermitted:BAAALgAECgEJAQABLgAECgMJBAAVAAAAAA==.',
Ki='Kirlo:BAAALgADCgcJDQAAAA==.Kittytiddies:BAAALgADCgUJBQAAAA==.',
Ko='Kobethama:BAAALgAECgEJBAAAAA==.Kohnan:BAABLgAECn8UAAIFAAgJ2QhAUAAIAQAFAAgJ2QhAUAAIAQAAAA==.Kotoko:BAAALgAECgcJEAAAAA==.',
Ks='Ksauce:BAAALgAECgcJDwAAAA==.',
Ky='Kynan:BAAALgAFFAIJBAABLgAECgQJBAAVAAAAAA==.Kynon:BAABLgAECn8ZAAMZAAYJbRTGMABkAQAZAAYJbRTGMABkAQAaAAEJLgFjdwAUAAABLgAECgQJBAAVAAAAAA==.Kyran:BAAALgAECgQJBAAAAA==.',
La='Laerai:BAAALgADCgcJDAAAAA==.Lament:BAAALgAECgcJDAAAAA==.Lamurun:BAAALgAECgQJBAAAAA==.Lancelöt:BAACLgAFFH8FAAICAAIJKiKQOADLAAACAAIJKiKQOADLAAAuAAQKfzoAAgIACQlGJBwCAEYDAAIACQlGJBwCAEYDAAAA.Lathina:BAAALgAECgMJBAAAAA==.Lavendere:BAAALgAECgYJCwABLgAFFAMJCAAEAOoMAA==.',
Le='Lectra:BAAALgADCgEJAQAAAA==.Leechang:BAAALgADCgMJAwAAAA==.',
Li='Liiam:BAAALgADCgYJBgAAAA==.Linafox:BAAALgAECgcJDAAAAA==.Linnëa:BAAALgAFFAIJAgAAAA==.Linta:BAAALgADCgcJCQAAAA==.Lizardwizard:BAAALgAECgcJDgAAAA==.',
Ll='Llonia:BAAALgADCgMJAwAAAA==.',
Lo='Lockraum:BAAALgAECgMJAwAAAA==.Lokix:BAABLgAECn8fAAIEAAYJ6CJHIgD8AQAEAAYJ6CJHIgD8AQAAAA==.',
Lu='Luexis:BAAALgADCgkJFgAAAA==.Luobo:BAAALgADCgQJBQAAAA==.Lustie:BAAALgADCgMJAwAAAA==.',
Ly='Lysistratta:BAABLgAECn8eAAIOAAcJrQk7GwDsAAAOAAcJrQk7GwDsAAAAAA==.',
Ma='Magikishi:BAABLgAECn8cAAITAAgJYR8rOwCKAgATAAgJYR8rOwCKAgAAAA==.Magimal:BAAALgAECgYJBgABLgAECgcJCwAVAAAAAA==.Mahka:BAABLgAECn80AAMWAAkJlxtVGQD6AQAWAAkJlxtVGQD6AQAYAAMJHyPqIAAvAQABLgADCgEJAQAVAAAAAA==.Maldrakesus:BAAALgADCgEJAQABLgAECgcJCwAVAAAAAA==.Malifecent:BAAALgAECgMJAwAAAA==.Manthalus:BAAALgAECgIJAgAAAA==.Marquista:BAAALgADCgkJNQAAAA==.',
Mc='Mchammer:BAAALgADCgMJAwAAAA==.',
Me='Meatball:BAAALgAECgMJAwAAAA==.Meganstoon:BAAALgAECgMJBAAAAA==.Meladaris:BAAALgAECgQJBQAAAA==.Mey:BAABLgAECn8wAAIbAAgJyhvrEQBSAgAbAAgJyhvrEQBSAgAAAA==.',
Mi='Misfortune:BAAALgADCgUJBQAAAA==.Missperfect:BAAALgAECgcJEAAAAA==.Mitenalla:BAABLgAFFH8HAAICAAMJ/wnJMwDoAAACAAMJ/wnJMwDoAAAAAA==.',
Mu='Muatahawa:BAAALgADCggJFgAAAA==.Muglackh:BAAALgAECgcJEwAAAA==.',
My='Myoue:BAAALgAECgMJBAAAAA==.Mysticraven:BAAALgAECgcJBwAAAA==.Mythbredor:BAAALgAECgYJBgAAAA==.',
Na='Naariah:BAAALgADCgcJBwAAAA==.Nagendra:BAABLgAECn8XAAIcAAkJGiDnBwD7AgAcAAkJGiDnBwD7AgAAAA==.Natharion:BAAALgADCgUJCgAAAA==.',
Ne='Neoptolemos:BAAALgAECgEJAgAAAA==.Nezpak:BAAALgADCgcJEAAAAA==.',
Ni='Nicnevin:BAAALgAECgcJEwAAAA==.Nitrochrist:BAABLgAECn8wAAIBAAkJyhQwHgD7AQABAAkJyhQwHgD7AQAAAA==.Nixxy:BAAALgADCgcJDgABLgAFFAUJEAAdAAoTAA==.',
No='Nokansee:BAAALgADCgQJBAAAAA==.Nokimi:BAAALgAECgQJBAAAAA==.Noobru:BAAALgAECgYJDwAAAA==.Nordathair:BAAALgAECgYJEgAAAA==.Nori:BAACLgAFFH8gAAITAAYJ+CaVAwA3AgATAAYJ+CaVAwA3AgAuAAQKfyMAAxMACQmeJpoAAPwDABMACQmeJpoAAPwDAB4AAwkSILcPAMcAAAAA.',
Ob='Oblivion:BAAALgADCgQJBAAAAA==.',
On='Onebuttonman:BAAALgAECgEJAQAAAA==.Onlyfoxes:BAAALgAECgIJAgAAAA==.',
Or='Original:BAAALgAECggJCwAAAA==.Originals:BAAALgAECgYJCAAAAA==.',
Ot='Otome:BAAALgAECgcJBwAAAA==.',
Pa='Painfulpoo:BAAALgAECgIJAgAAAA==.Parsemae:BAACLgAFFH8HAAITAAMJcB3PPgASAQATAAMJcB3PPgASAQAuAAQKfyMAAxMACAm2HWgvALQCABMACAm2HWgvALQCAB8AAQkdD68QADEAAAAA.Pastries:BAACLgAFFH8ZAAIFAAcJVx5KAgAyAgAFAAcJVx5KAgAyAgAuAAQKfzAAAgUACQmrIrkCAKUDAAUACQmrIrkCAKUDAAAA.',
Pb='Pbd:BAAALgAECgIJAgAAAA==.',
Pi='Pitlin:BAABLgAECn8hAAIgAAgJAyISAwAHAwAgAAgJAyISAwAHAwAAAA==.',
Pm='Pmsavenger:BAAALgADCgkJEgAAAA==.',
Po='Polynya:BAAALgAECgQJBQAAAA==.Pooshot:BAAALgAECgYJCwAAAA==.',
Pr='Priestalisha:BAACLgAFFH8WAAIbAAUJICNDAgDNAQAbAAUJICNDAgDNAQAuAAQKfy4AAhsACQngJPEAAIMDABsACQngJPEAAIMDAAAA.Prognie:BAAALgADCgcJCAAAAA==.',
Ra='Raelana:BAABLgAECn8eAAICAAYJmwmcdAADAQACAAYJmwmcdAADAQAAAA==.Ragetatertot:BAAALgAECgYJDgAAAA==.Ragingpoo:BAABLgAECn8WAAIEAAkJhBNZJQDsAQAEAAkJhBNZJQDsAQAAAA==.Rakenroll:BAAALgADCggJCAAAAA==.Rawsteak:BAAALgAECgYJEQAAAA==.Razdaz:BAABLgAECn8VAAMgAAcJfx39FQD0AQAgAAYJxhv9FQD0AQAbAAcJNxYcFAC4AQAAAA==.',
Re='Redcrow:BAAALgAECgcJDQAAAA==.Reheal:BAABLgAECn8UAAIbAAgJjR0xBQC0AgAbAAgJjR0xBQC0AgAAAA==.Reshocker:BAABLgAECn8lAAIhAAkJ5BmsEwC5AQAhAAkJ5BmsEwC5AQAAAA==.Restosexualz:BAAALgAECgMJAwAAAA==.',
Ri='Rixxy:BAACLgAFFH8QAAMdAAUJChPBCABdAQAdAAUJChPBCABdAQAcAAEJsAFUPQA4AAAuAAQKfycAAx0ACAmVIkUCAFEDAB0ACAmVIkUCAFEDABwABwmrC8E+AO8AAAAA.',
Ro='Roastbeefdr:BAABLgAECn8vAAIOAAkJySPcAAA3AwAOAAkJySPcAAA3AwAAAA==.Roderigo:BAABLgAECn8YAAIWAAgJtQ9YJwCTAQAWAAgJtQ9YJwCTAQAAAA==.Root:BAAALgAECgYJEQAAAA==.',
Ru='Runian:BAAALgAECgQJBAAAAA==.',
Sa='Sadlypink:BAABLgAECn8VAAITAAcJLBRFhwDDAQATAAcJLBRFhwDDAQAAAA==.Saisaith:BAAALgAECgYJBwABLgAFFAMJCAAEAOoMAA==.Sanarian:BAAALgADCgMJAwAAAA==.Sand:BAABLgAECn8dAAIEAAcJ9hQvaAC9AQAEAAcJ9hQvaAC9AQAAAA==.Sandy:BAAALgAECgcJAwAAAA==.Savadar:BAAALgAECgYJDAAAAA==.Saymourcox:BAAALgAECgYJCgAAAA==.',
Se='Seadra:BAAALgADCggJDQABLgAECgYJFAAIAM4ZAA==.Sealyboi:BAAALgADCgQJBAAAAA==.Serpeng:BAAALgAECgYJEgAAAA==.Setareh:BAABLgAECn8UAAITAAYJygczjwD0AAATAAYJygczjwD0AAAAAA==.Settra:BAAALgADCgcJDAAAAA==.',
Sh='Shakuru:BAABLgAECn8qAAITAAkJBw6nLQDqAQATAAkJBw6nLQDqAQAAAA==.Shanta:BAAALgADCgMJAwAAAA==.Shkar:BAABLgAECn88AAIPAAkJnhnvBwBtAgAPAAkJnhnvBwBtAgAAAA==.Shokan:BAAALgADCgQJBwAAAA==.',
Si='Silanah:BAAALgADCgEJAQAAAA==.Silandrya:BAAALgADCggJCwAAAA==.Sildin:BAAALgAECgUJCAAAAA==.Silverclaws:BAAALgADCgkJDgAAAA==.',
Sj='Sjaridin:BAEALgAECgQJDAABLgAFFAUJFAAiANsCAA==.',
Sk='Skittle:BAABLgAECn8VAAMiAAYJ8QbIGgCFAAAiAAYJ8QbIGgCFAAAWAAUJdAKxawB5AAAAAA==.Skullhunter:BAABLgAFFH8FAAQKAAUJEhwpFgBgAAAKAAMJSCEpFgBgAAAJAAEJ3BeZSQBYAAAjAAEJ2RXQGgBWAAAAAA==.',
Sl='Slenderama:BAAALgADCgYJCQAAAA==.Slenderella:BAAALgADCgUJBQAAAA==.',
Sm='Small:BAAALgADCgEJAQAAAA==.Smawbrawl:BAAALgAECgYJBgAAAA==.Smoothroller:BAAALgAECgEJAQAAAA==.',
So='Sogen:BAAALgADCgMJAwAAAA==.',
St='Staysalty:BAAALgADCgEJAQAAAA==.Stickyricky:BAAALgADCgUJCgAAAA==.Strongmandan:BAAALgAECgEJAQAAAA==.Stubs:BAAALgADCgYJDAAAAA==.',
Su='Sule:BAEBLgAECn8zAAITAAkJmhHhJwADAgATAAkJmhHhJwADAgAAAA==.',
Sw='Sweetpea:BAAALgAFFAEJAQABLgAFFAUJFAAkAB4bAA==.',
['Sä']='Sämuel:BAAALgADCgEJAQAAAA==.',
Ta='Tanks:BAAALgADCgEJAgAAAA==.',
Th='Thelorax:BAAALgAECgkJEgAAAA==.Theyeti:BAAALgADCgEJAQABLgADCgcJDQAVAAAAAA==.Thhee:BAABLgAECn8dAAIlAAcJcxReEQCTAQAlAAcJcxReEQCTAQAAAA==.Thumbelyna:BAABLgAECn8cAAMWAAcJXRxqFgASAgAWAAcJXRxqFgASAgAiAAEJMQrzNQAeAAAAAA==.',
Ts='Tsuro:BAAALgAECgUJBgAAAA==.',
Tu='Tukktukk:BAAALgAECgEJAQAAAA==.',
Ty='Tyrini:BAAALgADCgIJAgAAAA==.',
Um='Umie:BAAALgAECgEJAQAAAA==.',
Un='Unholylife:BAAALgAECgcJEQAAAA==.',
Up='Up:BAABLgAECn8VAAIRAAcJVB/nBABiAgARAAcJVB/nBABiAgAAAA==.',
Va='Valasi:BAAALgAECgEJAwAAAA==.',
Ve='Velocet:BAACLgAFFH8HAAIlAAMJjwjbFQDpAAAlAAMJjwjbFQDpAAAuAAQKfyoAAyUACAl8GnYVAGQCACUACAl8GnYVAGQCAAcAAwmICLsWAIsAAAAA.Vetlance:BAAALgAECgQJBQAAAA==.',
Vo='Voroak:BAAALgADCgYJBgAAAA==.',
Wa='Waghdaddy:BAABLgAECn8mAAICAAkJYyJFBQD7AgACAAkJYyJFBQD7AgAAAA==.Waghiechan:BAAALgAECgcJCQAAAA==.',
Wh='Whatøncewas:BAAALgAFFAEJAQAAAA==.Whitfield:BAAALgADCgUJBQAAAA==.Whordie:BAAALgAECgEJAQAAAA==.',
Wi='Wildlily:BAAALgADCgkJCQABLgAECgYJEAAVAAAAAA==.Wistful:BAAALgAECgQJBwAAAA==.',
Wo='Wobiwabi:BAAALgADCgIJAgAAAA==.',
Wr='Wratheon:BAACLgAFFH8HAAIkAAMJ5RRLHwDjAAAkAAMJ5RRLHwDjAAAuAAQKfy0AAyQACQm5GmEFAIsCACQACQm5GmEFAIsCABkAAQkAAO6NABYAAAAA.',
Wu='Wuji:BAABLgAECn8eAAIgAAYJAA+vHABHAQAgAAYJAA+vHABHAQAAAA==.',
['Wê']='Wêrewôlf:BAAALgADCgUJBQAAAA==.',
Xa='Xablau:BAAALgAECgYJBgAAAA==.',
Ye='Yeli:BAAALgAECgUJBQAAAA==.',
Ze='Zenaf:BAAALgAECgUJBwAAAA==.Zeryph:BAAALgADCgYJCwABLgAECggJIQAGAIgeAA==.',
Zi='Zimbabway:BAAALgAECgYJBgAAAA==.',
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
