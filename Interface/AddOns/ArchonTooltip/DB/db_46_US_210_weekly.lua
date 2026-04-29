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

local lookup = {'Mage-Frost','Mage-Fire','Warrior-Fury','Shaman-Restoration','Rogue-Subtlety','Warlock-Demonology','Warlock-Affliction','Rogue-Assassination','Monk-Mistweaver','DemonHunter-Devourer','Paladin-Retribution','Shaman-Elemental','Unknown-Unknown','Warlock-Destruction','DeathKnight-Unholy','Priest-Shadow','Druid-Balance','Druid-Guardian','Evoker-Devastation','Monk-Brewmaster','Druid-Restoration','Hunter-BeastMastery','Priest-Discipline','Priest-Holy','Shaman-Enhancement','Mage-Arcane','Monk-Windwalker','Evoker-Augmentation','Hunter-Marksmanship','Evoker-Preservation','Paladin-Protection',}
local provider = {region='US',realm='Tanaris',name='US',type='weekly',zone=46,date='2026-04-24',data={Ac='Acegoblain:BAACLgAFFH8GAAIBAAIJtBCBGQCxAAABAAIJtBCBGQCxAAAuAAQKfx8AAwEACAlvHwcGAFACAAEACAlvHwcGAFACAAIAAQlEBm4RACsAAAAA.',
Ad='Aderynn:BAAALgADCgMJAwAAAA==.Adind:BAAALgAECgcJEAAAAA==.',
Ah='Aholay:BAAALgAECgcJCgAAAA==.',
Ak='Akkiba:BAAALgADCgUJCQAAAA==.',
Al='Alaval:BAAALgAECgYJDgAAAA==.Alaweth:BAAALgAECgUJCQAAAA==.Aldabaran:BAAALgAECgUJDAAAAA==.Alelros:BAAALgAECgMJAwAAAA==.Aletheïa:BAAALgADCgIJAgAAAA==.Allanonontu:BAAALgADCgUJBQAAAA==.Althamon:BAAALgADCgkJEwAAAA==.',
An='Andromedaa:BAAALgADCgMJAwAAAA==.Angelbabe:BAAALgAECgQJBgAAAA==.Antamun:BAABLgAECn8kAAIDAAgJIRkPGwB0AgADAAgJIRkPGwB0AgAAAA==.Anthuil:BAAALgADCgMJAwAAAA==.',
Ao='Aoasis:BAABLgAECn8dAAIEAAYJ9iI3BQASAgAEAAYJ9iI3BQASAgAAAA==.',
Ar='Arcticwings:BAAALgAECgQJBAAAAA==.Arduinna:BAAALgAECgUJBQAAAA==.Arislynn:BAABLgAECn8VAAIFAAYJ+AbODQDzAAAFAAYJ+AbODQDzAAAAAA==.',
As='Ashalerath:BAAALgAECgYJDgAAAA==.Astralz:BAAALgAECgUJCAAAAA==.',
Az='Azzazel:BAAALgAECgYJCwAAAA==.',
Ba='Badgerhollis:BAAALgADCgUJCgAAAA==.Badmojo:BAAALgADCgQJBAAAAA==.Baha:BAAALgADCgUJBQAAAA==.Bailey:BAAALgAECgYJBgAAAA==.Bankai:BAAALgADCgIJAgAAAA==.Bape:BAAALgAECgMJAwABLgAECgcJFQAGAAYhAA==.Barack:BAAALgAECgIJAgAAAA==.Barkkent:BAAALgADCgIJAgAAAA==.Baromir:BAAALgADCgUJCAAAAA==.Bathin:BAABLgAECn8UAAMHAAYJnRnGEQAQAQAGAAYJKhWNaQCQAQAHAAUJBRfGEQAQAQAAAA==.',
Be='Beama:BAAALgAECgIJAgAAAA==.Bearbottom:BAAALgADCgQJBQAAAA==.Beetsalad:BAABLgAECn8kAAIIAAgJgCQhAQA0AwAIAAgJgCQhAQA0AwAAAA==.',
Bi='Bigboop:BAAALgAECgYJCwAAAA==.Bigpoppapump:BAAALgADCgYJBwAAAA==.',
Bl='Bloodaxe:BAAALgAECgUJBQAAAA==.',
Bo='Borgad:BAAALgADCgEJAQAAAA==.',
Br='Bryzxbless:BAAALgAECgYJDAABLgAFFAYJDQAJAAcRAA==.',
Bu='Bubblebee:BAAALgAECgIJAwAAAA==.Butterskotch:BAAALgADCgUJBQAAAA==.',
['Bô']='Bôjay:BAAALgADCgcJEgAAAA==.',
Ch='Charmy:BAAALgADCgMJAwAAAA==.Chickimama:BAABLgAECn8YAAIKAAcJbQxXGAA9AQAKAAcJbQxXGAA9AQAAAA==.',
Co='Coagulation:BAAALgAECgYJDQAAAA==.Corvettefour:BAAALgADCgMJAwAAAA==.Cowboybeast:BAAALgADCgUJBQAAAA==.Cowboyshorn:BAABLgAECn8XAAIKAAYJzBcwFwBFAQAKAAYJzBcwFwBFAQAAAA==.',
Cr='Credible:BAAALgADCgUJBQAAAA==.Crunchynuget:BAABLgAECn8VAAILAAgJfh2GOQA9AgALAAgJfh2GOQA9AgAAAA==.',
Ct='Cts:BAAALgAECgUJBwAAAA==.',
Cu='Cuboose:BAABLgAECn8UAAIEAAYJjCaeAgBsAgAEAAYJjCaeAgBsAgAAAA==.',
Cy='Cybelene:BAAALgAECgUJCgAAAA==.Cyione:BAABLgAECn8XAAIMAAcJQAs+EwDjAAAMAAcJQAs+EwDjAAAAAA==.Cynemon:BAAALgAECgYJCQAAAA==.Cynleel:BAAALgAECgYJBgABLgAECgYJCQANAAAAAA==.',
Da='Dandymage:BAAALgAECgcJEQAAAA==.Darthvitiate:BAAALgAECgEJAQAAAA==.Dascorupt:BAAALgAECgYJEQAAAA==.Dazzette:BAAALgADCgYJBQABLgAECgQJBAANAAAAAA==.',
De='Decày:BAAALgAECgYJCwAAAA==.Deemin:BAAALgAECgUJBQAAAA==.Delsar:BAAALgADCgkJCgAAAA==.Demogotto:BAAALgADCggJCAAAAA==.Desden:BAAALgAECgYJCQAAAA==.Deåth:BAAALgADCgIJAgAAAA==.',
Do='Dorandra:BAAALgADCgIJAgAAAA==.Dorktard:BAAALgADCgUJBgAAAA==.Dotted:BAACLgAFFH8IAAIGAAMJKxu5CgAgAQAGAAMJKxu5CgAgAQAuAAQKfyMABAYACAnRIu8PAPoCAAYACAnRIu8PAPoCAA4AAgl8IwtDAKkAAAcAAQkAAKMnAFMAAAAA.',
Dr='Drangrods:BAAALgAECgQJBgAAAA==.Draxchii:BAAALgAECgUJAgAAAA==.Draxdecorupt:BAAALgADCgIJAgAAAA==.Draxharmony:BAAALgAECgIJAQAAAA==.',
Ds='Dsypha:BAAALgAECgYJEwAAAA==.',
['Då']='Dåmage:BAAALgAECgQJBwAAAA==.',
Ed='Edric:BAAALgAECgYJEAAAAA==.Edyion:BAAALgAECgYJDwAAAA==.',
Ef='Efreet:BAAALgAECgYJDwAAAA==.',
El='Elektron:BAAALgADCgMJAwAAAA==.Elimae:BAAALgADCgcJDgAAAA==.Eliqsed:BAAALgADCgkJDQAAAA==.Elisahel:BAAALgADCgcJBwAAAA==.Elizaa:BAAALgADCgYJCAAAAA==.',
En='Enochian:BAAALgADCgYJBgAAAA==.',
Eu='Eurae:BAAALgAECgUJEwAAAA==.',
Ev='Eviscero:BAABLgAECn8XAAIPAAcJFAspFgBgAQAPAAcJFAspFgBgAQAAAA==.Evoda:BAAALgAECgYJDAAAAA==.',
Ex='Extrodinaire:BAAALgAECgYJEQAAAA==.',
Fa='Fadedemon:BAAALgAECgYJEAAAAA==.Faedilan:BAAALgAECgEJBAAAAA==.Fallan:BAAALgAECgMJAwAAAA==.Farrahmoans:BAAALgAECgYJEwAAAA==.',
Fe='Fellvarg:BAAALgAECgYJDwAAAA==.Felstriker:BAABLgAECn8YAAIKAAcJMQ9JYgB6AQAKAAcJMQ9JYgB6AQAAAA==.',
Fi='Filí:BAAALgADCgMJBwAAAA==.',
Fo='Fotiá:BAAALgAECgEJAQABLgAFFAIJBAANAAAAAA==.',
Fr='Frostytip:BAAALgAECgUJCQAAAA==.Fròzensoul:BAAALgADCgYJDAAAAA==.Frøzen:BAAALgAECgYJDQAAAA==.',
Fu='Furiosa:BAAALgADCgcJCwAAAA==.Fuzzyren:BAAALgAECgEJAQAAAA==.',
Ga='Gahïjï:BAAALgADCgMJAwABLgAECgYJHQAEAPYiAA==.Gallium:BAAALgADCgUJCQAAAA==.Galroot:BAAALgAECgQJCAABLgAFFAIJBgABALQQAA==.Galvakrond:BAAALgAECgYJDQAAAA==.',
Gi='Gillfy:BAAALgAECgQJBQABLgAECgYJDgANAAAAAA==.Giltor:BAAALgADCgQJBAAAAA==.',
Go='Gomletta:BAAALgAECgYJCgAAAA==.',
Gr='Grak:BAAALgADCggJDQABLgAECggJJAAQANAbAA==.Gravey:BAABLgAECn8UAAMRAAYJ3BamCwAyAQARAAYJ3BamCwAyAQASAAEJVAfTNQAeAAAAAA==.Grik:BAABLgAECn8eAAITAAgJ8AtLAgBzAQATAAgJ8AtLAgBzAQAAAA==.Grimminhagen:BAAALgADCgEJAgAAAA==.Grêed:BAAALgADCgYJBgAAAA==.',
Gu='Guigon:BAAALgADCgEJAQAAAA==.Guldio:BAAALgADCgIJAgAAAA==.',
Gw='Gwyndora:BAAALgAECgUJCQAAAA==.',
Ha='Hashira:BAAALgAECgIJAgAAAA==.',
He='Healup:BAAALgADCgUJBQAAAA==.',
Ho='Holyoshyy:BAAALgADCgcJBwABLgAECgUJCAANAAAAAA==.Holyvengence:BAAALgADCgQJBAABLgAECgYJEQANAAAAAA==.',
Hr='Hroth:BAAALgADCgIJAgAAAA==.',
Hu='Hup:BAAALgADCgIJAgAAAA==.',
['Hÿ']='Hÿmpëñ:BAAALgADCgYJBgAAAA==.',
Ie='Iemanja:BAAALgAECgUJBQAAAA==.',
Ih='Iharjathinji:BAAALgADCggJCAAAAA==.',
Im='Impawster:BAAALgADCgUJBQAAAA==.',
Is='Isaacu:BAAALgADCgMJAwAAAA==.',
It='Ithaka:BAAALgAECgQJBAAAAA==.Itzsavage:BAAALgADCgcJDQAAAA==.',
Ja='Jachyra:BAAALgAECgYJDwAAAA==.Jackmanss:BAAALgAECgUJDAAAAA==.Jaegersan:BAAALgAECgUJBQAAAA==.Jaell:BAAALgADCgcJCgAAAA==.Jamezon:BAABLgAECn8UAAIDAAYJqRE9EwAIAQADAAYJqRE9EwAIAQAAAA==.Jarttshocks:BAAALgAECgYJEgAAAA==.',
Je='Jebby:BAAALgAECgYJDwAAAA==.',
Ji='Jitlok:BAAALgAECgYJDQAAAA==.',
Ka='Kahladin:BAAALgADCgMJAwAAAA==.Kahrot:BAAALgAECgkJDgAAAA==.Kaioken:BAAALgADCgUJBgAAAA==.Kalia:BAAALgAECgQJCQAAAA==.Kalibontu:BAAALgAECgYJCwAAAA==.Kalius:BAAALgAECgYJDwAAAA==.Kasiusa:BAAALgADCgYJCwABLgAECgYJDgANAAAAAA==.Kazgrom:BAAALgADCgkJEwAAAA==.Kazool:BAAALgAECgUJDQAAAA==.',
Ke='Keinsi:BAAALgAECgYJBgAAAA==.Kenpomonk:BAABLgAECn8eAAIUAAgJLRudFQBdAgAUAAgJLRudFQBdAgAAAA==.',
Ki='Killrbkilled:BAAALgADCgYJCAAAAA==.',
Kn='Knower:BAAALgADCgYJDgAAAA==.Knucklecuffs:BAAALgAECgQJBwABLgAECgYJHQAEAPYiAA==.Knyxi:BAAALgADCgEJAQAAAA==.',
Ky='Kyran:BAAALgADCgMJAwABLgAECgYJDgANAAAAAA==.',
['Kí']='Kíli:BAAALgADCgcJDgAAAA==.',
['Kø']='Køteb:BAAALgAECgYJDgAAAA==.',
La='Lalatinna:BAAALgAECgUJBgAAAA==.Lambdah:BAAALgADCgEJAQAAAA==.Layonagosa:BAABLgAECn8VAAIBAAYJ4BWZHQBiAQABAAYJ4BWZHQBiAQAAAA==.',
Le='Leadshot:BAAALgAECgcJCAAAAA==.Letal:BAAALgADCgMJAwAAAA==.',
Lh='Lhost:BAAALgADCgUJCAAAAA==.',
Li='Lionel:BAAALgADCgUJBQAAAA==.',
Lo='Lostette:BAAALgAECgYJCwAAAA==.',
Lu='Luciné:BAAALgADCgEJAQAAAA==.Luigimangion:BAAALgADCgMJAwAAAA==.',
['Lï']='Lïmes:BAAALgAECgYJDAAAAA==.',
Ma='Maakha:BAAALgAECgYJDAAAAA==.Madiline:BAAALgAECgYJCgAAAA==.Madokakaname:BAAALgADCgYJBgAAAA==.Madsumo:BAAALgAECgYJBgABLgAECgYJEgANAAAAAA==.Maehko:BAAALgAECgYJCwAAAA==.Magiaßaiser:BAAALgADCgIJAwAAAA==.Magicmack:BAAALgAECgEJAQAAAA==.Magroot:BAAALgAECgYJDgAAAA==.Makel:BAAALgAECgYJBgAAAA==.Mannadina:BAAALgADCgMJAwAAAA==.Mapera:BAAALgAECgYJDgAAAA==.Marjaya:BAAALgAECgUJBQAAAA==.',
Mc='Mcc:BAAALgADCgkJGQAAAA==.',
Mi='Miandra:BAABLgAECn8WAAILAAYJ8RzsEQCUAQALAAYJ8RzsEQCUAQAAAA==.Michaal:BAAALgAECgQJBwAAAA==.Midnighttank:BAAALgADCgUJBQAAAA==.Miko:BAAALgAECgYJEQAAAA==.Mirosa:BAAALgAECgYJDwAAAA==.Mistmuncher:BAAALgADCgEJAQAAAA==.',
Mo='Mommabeans:BAABLgAECn8kAAIVAAgJnSAkDQDTAgAVAAgJnSAkDQDTAgAAAA==.Moogar:BAAALgAECgEJAQAAAA==.Moostorm:BAAALgAECgQJCAAAAA==.',
Na='Nangsa:BAAALgAECgYJCQAAAA==.Nautisassin:BAAALgAECgYJBgABLgAECgYJEgANAAAAAA==.Naxz:BAAALgAECgEJAQAAAA==.',
Ne='Necrodk:BAAALgADCgcJDgABLgAECgcJGgAWAFgkAA==.Necrolock:BAABLgAECn8oAAMGAAgJGyN/CADpAQAGAAcJGyN/CADpAQAHAAEJAAA+IgBpAAABLgAECgcJGgAWAFgkAA==.Neilrodimus:BAAALgAECgYJEQAAAA==.Nessva:BAAALgAECgYJEQAAAA==.Neçromonger:BAABLgAECn8aAAIWAAcJWCSYCwDmAgAWAAcJWCSYCwDmAgAAAA==.',
No='Novabloom:BAAALgAECgQJCgAAAA==.Novuri:BAAALgAECgYJEwAAAA==.Noxz:BAABLgAECn8kAAQQAAgJMCFrCQDtAgAQAAgJMCFrCQDtAgAXAAIJEhVaEQCPAAAYAAEJFhYkewA8AAAAAA==.',
Ny='Nyiais:BAAALgAECgYJCQAAAA==.',
['Nï']='Nïghtmärë:BAAALgAECgUJDAAAAA==.',
Ob='Obesity:BAAALgAECgEJAQAAAA==.Obsessedwith:BAABLgAECn8VAAIWAAYJ+h0gDgCUAQAWAAYJ+h0gDgCUAQAAAA==.',
Oh='Ohamernster:BAAALgADCgUJBQAAAA==.',
Oo='Oonspork:BAAALgADCgUJCQAAAA==.',
Or='Ortheus:BAAALgAECgYJDQAAAA==.',
Ou='Oudin:BAAALgADCgEJAQAAAA==.',
Pa='Paladinsucks:BAABLgAECn8VAAILAAcJtBCycQCYAQALAAcJtBCycQCYAQAAAA==.Pandatude:BAAALgADCgMJAwAAAA==.Pangurrban:BAAALgADCgcJDwAAAA==.',
Ph='Phoshot:BAAALgAECgYJCQAAAA==.',
Po='Poplockvomit:BAABLgAECn8ZAAIZAAcJ6gsMBgAvAQAZAAcJ6gsMBgAvAQAAAA==.',
Ps='Psyscape:BAAALgADCgcJFgAAAA==.',
Pt='Ptaak:BAAALgAECgQJCAAAAA==.',
Pu='Punkhunter:BAAALgAECgYJDQAAAA==.',
Qi='Qijdami:BAAALgAECgYJEQAAAA==.',
Qu='Quangar:BAACLgAFFH8MAAILAAQJZA5oBQA7AQALAAQJZA5oBQA7AQAuAAQKfx0AAgsABwkgHcFKAAICAAsABwkgHcFKAAICAAAA.',
Ra='Raichi:BAAALgADCgMJAwAAAA==.Ralas:BAAALgAECgIJAgAAAA==.',
Re='Reeally:BAAALgAECgYJCwAAAA==.Ren:BAAALgADCgYJDgAAAA==.Reppitt:BAAALgADCgcJCgAAAA==.',
Ri='Riopia:BAAALgADCgUJBQAAAA==.',
Ro='Roenwyn:BAAALgADCgcJCwAAAA==.Ronetto:BAABLgAECn8hAAMBAAgJ+x4pKADSAgABAAgJ+x4pKADSAgAaAAEJnwUxIAAvAAAAAA==.Rons:BAAALgADCggJCwABLgAECggJIQABAPseAA==.Ronsteur:BAAALgAECgYJBwABLgAECggJIQABAPseAA==.Ronwin:BAAALgADCgIJAgABLgAECggJIQABAPseAA==.Roulette:BAAALgADCgMJBgAAAA==.Rozzakbeztok:BAAALgADCgUJBwAAAA==.Rozzanox:BAAALgADCgYJCwABLgAECgYJDQANAAAAAA==.Rozzeran:BAAALgADCgQJBAABLgAECgYJDQANAAAAAA==.Rozzinor:BAAALgAECgYJDQAAAA==.',
Ru='Ruslah:BAAALgAECgUJCQAAAA==.',
Sa='Salii:BAAALgAECgcJCwAAAA==.Savageslayer:BAABLgAECn8kAAMRAAgJIB4uEQCUAgARAAgJIB4uEQCUAgASAAYJkwSOIACaAAAAAA==.Savagesmonk:BAAALgAECgYJCwAAAA==.',
Se='Senshi:BAAALgAECgYJDgAAAA==.Seventl:BAAALgAECgYJDQAAAA==.',
Sh='Shadowgrave:BAAALgADCgYJBwAAAA==.Shaokhan:BAABLgAECn8YAAIbAAcJRQ2bLwBqAQAbAAcJRQ2bLwBqAQAAAA==.Shewolf:BAAALgADCgMJAwAAAA==.Shey:BAABLgAECn8nAAIKAAgJYRxEKQBdAgAKAAgJYRxEKQBdAgAAAA==.',
Si='Simbru:BAAALgAECgYJDwAAAA==.Sinuouss:BAABLgAECn8UAAMOAAYJ0RdrBQDvAAAOAAUJUhprBQDvAAAGAAMJgQ62PQB0AAAAAA==.',
Sp='Spellster:BAAALgAECgQJBgAAAA==.Spooderdaman:BAAALgAECgEJAQAAAA==.Sproach:BAAALgAFFAEJAQAAAA==.',
St='Stainman:BAABLgAECn8YAAMcAAgJGRfQAwDiAQAcAAgJGRfQAwDiAQATAAEJ7wULQgArAAAAAA==.Starvingwolf:BAABLgAECn8aAAIdAAcJFhqmAwBxAQAdAAcJFhqmAwBxAQAAAA==.Stonedraek:BAAALgADCgUJBQAAAA==.Stoogatz:BAAALgAECgMJAwABLgAECgYJDQANAAAAAA==.Strongbow:BAAALgADCgcJEAAAAA==.Stýx:BAAALgAECgIJAgAAAA==.',
Su='Sunflowersue:BAAALgADCgEJAQAAAA==.',
Sw='Swaellen:BAAALgAECgYJCQAAAA==.',
Sy='Sylaillea:BAAALgAECgMJAwAAAA==.Sylvester:BAAALgADCgYJBwAAAA==.',
Ta='Takerfan:BAAALgAECgEJAQAAAA==.Tallyblue:BAAALgADCgUJBQAAAA==.Tarrfashi:BAAALgAECgEJAQAAAA==.',
Te='Tega:BAAALgADCgQJBAAAAA==.Temüjin:BAABLgAECn8UAAIBAAYJ4RLKLQATAQABAAYJ4RLKLQATAQAAAA==.',
Th='Theeonlyone:BAABLgAECn8YAAMGAAYJtxiiIAAdAQAGAAUJtxiiIAAdAQAOAAQJTRFtNQDhAAAAAA==.Thelockrocks:BAAALgADCgQJBAAAAA==.',
Ti='Tiberlock:BAAALgADCgcJDwAAAA==.Tibernius:BAAALgADCgEJAQABLgADCgcJDwANAAAAAA==.Tiranii:BAAALgAECgYJDAAAAA==.Titannus:BAAALgAECgYJEgAAAA==.',
Tr='Tralisa:BAAALgADCgMJAwAAAA==.Tribalrage:BAAALgAECgQJCgAAAA==.Tristramhero:BAAALgAECgMJBAAAAA==.',
Tu='Tunipps:BAAALgAECgMJAwAAAA==.',
Ty='Tyriddikk:BAABLgAECn8lAAISAAgJxCKIAgABAwASAAgJxCKIAgABAwAAAA==.',
Un='Unholyhavoc:BAAALgAECgYJBwAAAA==.',
Va='Vael:BAAALgAECgYJEAAAAA==.Vaereir:BAAALgAECgEJAgABLgAFFAMJCAAGACsbAA==.Vandal:BAABLgAECn8kAAMQAAgJ0BszAwAIAgAQAAgJ0BszAwAIAgAXAAMJUgZiRQCOAAAAAA==.Varaug:BAAALgADCgMJAwAAAA==.Vartence:BAAALgAECgYJBgAAAA==.',
Ve='Veedar:BAAALgAECgYJBQAAAA==.Vezpar:BAAALgAECgQJBgAAAA==.',
Vm='Vmax:BAAALgAECgQJCQAAAA==.',
Vo='Voodoomkin:BAAALgAECgcJAQAAAA==.',
Vy='Vynllistar:BAAALgAECgUJCAAAAA==.',
Wa='Warblinox:BAAALgAECgEJAgAAAA==.Wardrel:BAAALgAECgYJEgAAAA==.',
We='Wetbread:BAAALgAECgYJCQAAAA==.',
Wi='Wiind:BAABLgAECn8kAAIeAAgJwxQCEgAeAgAeAAgJwxQCEgAeAgAAAA==.Winger:BAAALgAECgMJAwAAAA==.',
Xe='Xelarosia:BAAALgADCgYJBgABLgAECgYJBwANAAAAAA==.',
Xo='Xonz:BAABLgAECn8kAAIfAAgJBiM4AgAZAwAfAAgJBiM4AgAZAwAAAA==.',
Yo='Yomamasez:BAABLgAECn8UAAILAAYJrwjkMADXAAALAAYJrwjkMADXAAAAAA==.Youpoop:BAAALgAECgYJDAAAAA==.',
Za='Zagina:BAAALgADCggJCAAAAA==.',
Zh='Zhanrax:BAABLgAECn8VAAIfAAYJ0wa+KADEAAAfAAYJ0wa+KADEAAAAAA==.',
Zi='Zirnbie:BAAALgAECgYJDwAAAA==.',
Zo='Zoub:BAAALgAECgQJBwAAAA==.',
Zu='Zurael:BAAALgADCgMJAwAAAA==.',
Zx='Zxon:BAAALgADCgEJAQAAAA==.',
['Ãç']='Ãçízzlè:BAAALgADCgcJBwAAAA==.',
['Ða']='Ðark:BAABLgAECn8UAAILAAcJrxmlTwDzAQALAAcJrxmlTwDzAQABLgAECggJJQAWAJkcAA==.',
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
