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

local lookup = {'Mage-Frost','Mage-Fire','Druid-Restoration','Priest-Discipline','Priest-Shadow','Warrior-Fury','Shaman-Restoration','Rogue-Subtlety','Evoker-Devastation','Evoker-Augmentation','Warlock-Demonology','Warlock-Affliction','Rogue-Assassination','Monk-Mistweaver','Monk-Windwalker','DemonHunter-Devourer','Paladin-Retribution','Shaman-Elemental','Unknown-Unknown','Warlock-Destruction','Shaman-Enhancement','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Unholy','DeathKnight-Frost','Druid-Balance','Druid-Guardian','Paladin-Holy','Paladin-Protection','Monk-Brewmaster','DemonHunter-Vengeance','Priest-Holy','Mage-Arcane','Druid-Feral','Evoker-Preservation',}
local provider = {region='US',realm='Tanaris',name='US',type='weekly',zone=46,date='2026-05-01',data={Ac='Acegoblain:BAACLgAFFH8JAAIBAAMJGhftLwALAQABAAMJGhftLwALAQAuAAQKfycAAwEACAn/IOsNAHACAAEACAn/IOsNAHACAAIAAQlEBnERACsAAAAA.',
Ad='Aderynn:BAAALgADCgMJAwAAAA==.Adind:BAABLgAECn8UAAIDAAUJIRNIOwDmAAADAAUJIRNIOwDmAAAAAA==.',
Ah='Aholay:BAAALgAECgcJCgAAAA==.',
Ak='Akkiba:BAAALgADCgYJDwAAAA==.',
Al='Alaval:BAABLgAECn8UAAMEAAYJBQgdHAD/AAAEAAYJBQgdHAD/AAAFAAYJYwvYIQDsAAAAAA==.Alaweth:BAAALgAECgUJCQAAAA==.Aldabaran:BAAALgAECgUJDgAAAA==.Alelros:BAAALgAECgMJAwAAAA==.Aletheïa:BAAALgADCgIJAgAAAA==.Allanonontu:BAAALgADCgcJCwAAAA==.Althamon:BAAALgAECgMJAwAAAA==.',
An='Andromedaa:BAAALgADCgMJAwAAAA==.Angelbabe:BAAALgAECgYJDAAAAA==.Antamun:BAABLgAECn8sAAIGAAkJFhujBAB3AgAGAAkJFhujBAB3AgAAAA==.Anthuil:BAAALgADCgMJAwAAAA==.',
Ao='Aoasis:BAABLgAECn8jAAIHAAYJ1SQKCABrAgAHAAYJ1SQKCABrAgAAAA==.',
Ar='Araethea:BAAALgADCgYJBgAAAA==.Arcticwings:BAAALgAECgYJCgAAAA==.Arduinna:BAAALgAECgUJBQAAAA==.Arislynn:BAABLgAECn8bAAIIAAYJ6QghFwAdAQAIAAYJ6QghFwAdAQAAAA==.',
As='Ashalerath:BAABLgAECn8UAAMJAAYJpBZoBgA0AQAJAAYJpBZoBgA0AQAKAAIJJA+xUwB4AAAAAA==.Astralz:BAAALgAECgUJCAAAAA==.',
Az='Azzazel:BAAALgAECgYJCwAAAA==.',
Ba='Badgerhollis:BAAALgADCgYJEAAAAA==.Badmojo:BAAALgADCgQJBAAAAA==.Baha:BAAALgADCgUJBQAAAA==.Bailey:BAAALgAECgYJDAAAAA==.Bankai:BAAALgADCgIJAgAAAA==.Bape:BAAALgAECgMJBAABLgAECgcJFQALAAYhAA==.Barack:BAAALgAECgQJBwAAAA==.Barkkent:BAAALgADCgIJAgAAAA==.Baromir:BAAALgADCgYJDgAAAA==.Bathin:BAABLgAECn8aAAMMAAYJBhv/BAA9AQALAAYJKhWUaQCQAQAMAAYJrRn/BAA9AQAAAA==.',
Be='Beama:BAAALgAECgIJAgAAAA==.Bearbottom:BAAALgADCgQJBQAAAA==.Beetsalad:BAABLgAECn8kAAINAAgJgCQgAQA0AwANAAgJgCQgAQA0AwAAAA==.',
Bi='Bigboop:BAAALgAECgYJCwAAAA==.Bigpoppapump:BAAALgADCgYJBwAAAA==.',
Bl='Bloodaxe:BAAALgAECgUJCgAAAA==.',
Bo='Borgad:BAAALgADCgEJAQAAAA==.',
Br='Bryzxbless:BAAALgAECgYJDAABLgAFFAYJDgAOAAcRAA==.',
Bu='Bubblebee:BAAALgAECgMJBAAAAA==.Butterskotch:BAAALgADCgUJBQAAAA==.',
['Bô']='Bôjay:BAAALgADCgcJEgAAAA==.',
Ch='Chaosrift:BAAALgADCgYJBgABLgAECgcJGQAPAEUNAA==.Charmy:BAAALgADCgMJAwAAAA==.Chickimama:BAABLgAECn8UAAIQAAcJKQ8HVACrAAAQAAcJKQ8HVACrAAAAAA==.',
Co='Coagulation:BAAALgAECgYJEQAAAA==.Corvettefour:BAAALgADCgMJAwAAAA==.Cowboybeast:BAAALgADCgUJBQAAAA==.Cowboyshorn:BAABLgAECn8WAAIQAAYJzBftPwDnAAAQAAYJzBftPwDnAAAAAA==.',
Cr='Credible:BAAALgADCgUJBQAAAA==.Crunchynuget:BAABLgAECn8cAAIRAAgJ8B85EgApAgARAAgJ8B85EgApAgAAAA==.',
Ct='Cts:BAAALgAECgUJCAAAAA==.',
Cu='Cuboose:BAABLgAECn8aAAIHAAYJjCYVBgCOAgAHAAYJjCYVBgCOAgAAAA==.',
Cy='Cybelene:BAAALgAECgUJDAAAAA==.Cyione:BAABLgAECn8eAAISAAgJ2gs2GQBIAQASAAgJ2gs2GQBIAQAAAA==.Cynemon:BAAALgAECgYJDwAAAA==.Cynleel:BAAALgAECgYJBgABLgAECgYJDwATAAAAAA==.',
Da='Dadu:BAAALgADCgYJBgAAAA==.Dandymage:BAAALgAECgcJEQAAAA==.Daretti:BAAALgAECgQJBgAAAA==.Darthvitiate:BAAALgAECgEJAQAAAA==.Dascorupt:BAAALgAECgYJEQAAAA==.Dazzette:BAAALgADCgYJBQABLgAECgQJBAATAAAAAA==.',
De='Decày:BAAALgAECgYJDQAAAA==.Deemin:BAAALgAECgUJBQABLgAECgcJBwATAAAAAA==.Delsar:BAAALgADCgkJCgAAAA==.Demogotto:BAAALgADCggJCAAAAA==.Desden:BAAALgAECgYJCQAAAA==.Deåth:BAAALgADCgQJBAAAAA==.',
Di='Dijon:BAAALgADCgUJBQABLgAECgYJGQABAMQgAA==.Divinitey:BAAALgADCgQJBAAAAA==.',
Do='Dorandra:BAAALgADCgIJAgAAAA==.Dorktard:BAAALgADCgUJBgAAAA==.Dotted:BAACLgAFFH8IAAILAAMJKxvTGAAqAQALAAMJKxvTGAAqAQAuAAQKfyQABAsACAmTI/EPAPoCAAsACAmTI/EPAPoCABQAAgl8Iw1DAKkAAAwAAQkAAKUnAFMAAAAA.',
Dr='Drangrods:BAAALgAECgQJBwAAAA==.Draxchii:BAAALgAECgUJAgAAAA==.Draxdecorupt:BAAALgADCgIJAgAAAA==.Draxharmony:BAAALgAECgIJAQAAAA==.Drogonn:BAAALgADCgEJAQAAAA==.',
Ds='Dsypha:BAABLgAECn8YAAIBAAYJ7QfCbAAAAQABAAYJ7QfCbAAAAQAAAA==.',
['Då']='Dåmage:BAAALgAECgYJDQAAAA==.',
Ed='Edric:BAABLgAECn8WAAIVAAYJbx3kBQC0AQAVAAYJbx3kBQC0AQAAAA==.Edyion:BAABLgAECn8VAAIWAAYJQwcKFwAIAQAWAAYJQwcKFwAIAQAAAA==.',
Ef='Efreet:BAABLgAECn8WAAMXAAcJnCJZCQBmAgAXAAcJnCJZCQBmAgAYAAEJPxIPhQA3AAAAAA==.',
El='Elektron:BAAALgADCgMJAwAAAA==.Elimae:BAAALgADCgcJEgAAAA==.Eliqsed:BAAALgADCgkJDQAAAA==.Elisahel:BAAALgADCgcJBwAAAA==.Elizaa:BAAALgADCgYJCAAAAA==.',
En='Enochian:BAAALgADCgYJBgAAAA==.',
Eu='Eurae:BAABLgAECn8bAAIXAAYJbgqcQQAQAQAXAAYJbgqcQQAQAQAAAA==.',
Ev='Eviscero:BAABLgAECn8XAAIZAAcJFAuKQQA5AQAZAAcJFAuKQQA5AQAAAA==.Evoda:BAAALgAECgYJEgAAAA==.',
Ex='Extrodinaire:BAABLgAECn8XAAIVAAYJmhEACgBGAQAVAAYJmhEACgBGAQAAAA==.',
Fa='Fadedemon:BAABLgAECn8RAAIQAAYJeBFFRgDTAAAQAAYJeBFFRgDTAAAAAA==.Faedilan:BAAALgAECgEJBQAAAA==.Fallan:BAAALgAECgMJAwAAAA==.Farrahmoans:BAABLgAECn8ZAAIBAAYJxCBSJADWAQABAAYJxCBSJADWAQAAAA==.',
Fe='Fellvarg:BAABLgAECn8VAAIaAAYJ4BLCBQAxAQAaAAYJ4BLCBQAxAQAAAA==.Felstriker:BAABLgAECn8eAAIQAAcJ/A9LYgB6AQAQAAcJ/A9LYgB6AQAAAA==.',
Fi='Filí:BAAALgADCgMJBwAAAA==.',
Fo='Fotiá:BAAALgAECgMJAwABLgAFFAMJCAAXAE8jAA==.',
Fr='Frostytip:BAAALgAECgUJCQAAAA==.Fròzensoul:BAAALgADCgYJDAAAAA==.Frøzen:BAAALgAECgYJDgAAAA==.',
Fu='Furiosa:BAAALgADCgcJCwAAAA==.Fuzzyren:BAAALgAECgEJAQAAAA==.',
Ga='Gahïjï:BAAALgAECgEJAQABLgAECgYJIwAHANUkAA==.Gallium:BAAALgADCgUJCQAAAA==.Galroot:BAAALgAECgQJDAABLgAFFAMJCQABABoXAA==.Galvakrond:BAAALgAECgYJEAAAAA==.',
Gi='Gillfy:BAAALgAECgQJBQABLgAECgYJFAAEAAUIAA==.Giltor:BAAALgAECgEJAQAAAA==.',
Go='Gomletta:BAAALgAECgYJCgAAAA==.',
Gr='Grak:BAAALgADCgkJEwABLgAECggJKAAFAI4eAA==.Gravey:BAABLgAECn8aAAMbAAYJCxt1EwBrAQAbAAYJCxt1EwBrAQAcAAEJVAfXNQAeAAAAAA==.Greggor:BAAALgADCgEJAQAAAA==.Grik:BAABLgAECn8iAAIJAAgJRA4zBACOAQAJAAgJRA4zBACOAQAAAA==.Grimminhagen:BAAALgADCgEJAgAAAA==.Grêed:BAAALgADCgYJBgAAAA==.',
Gu='Guigon:BAAALgADCgEJAQAAAA==.Guldio:BAAALgADCgIJAgAAAA==.',
Gw='Gwyndora:BAAALgAECgYJDwAAAA==.',
Ha='Hashira:BAAALgAECgMJAwAAAA==.',
He='Healup:BAAALgADCgUJBQAAAA==.',
Ho='Holyoshyy:BAAALgADCgcJBwABLgAECgUJCAATAAAAAA==.Holyvengence:BAAALgAECgIJAwABLgAECgYJEQATAAAAAA==.',
Hr='Hroth:BAAALgADCgIJAgAAAA==.',
Hu='Hup:BAAALgADCgIJAgAAAA==.',
['Hÿ']='Hÿmpëñ:BAAALgADCgYJBgAAAA==.',
Ie='Iemanja:BAAALgAECgYJCwAAAA==.',
Ih='Iharjathinji:BAAALgADCggJCAAAAA==.',
Im='Impawster:BAAALgADCgUJBQAAAA==.',
Is='Isaacu:BAAALgADCgMJAwAAAA==.',
It='Ithaka:BAAALgAECgQJBAAAAA==.Itzsavage:BAAALgADCgcJDQAAAA==.',
Ja='Jachyra:BAABLgAECn8VAAINAAYJRRSYBgBHAQANAAYJRRSYBgBHAQAAAA==.Jackmanss:BAAALgAECgUJDgAAAA==.Jaegersan:BAAALgAECgUJBQAAAA==.Jaell:BAAALgADCgcJDgAAAA==.Jamezon:BAABLgAECn8ZAAIGAAYJ/BG1IQApAQAGAAYJ/BG1IQApAQAAAA==.Jarttshocks:BAABLgAECn8WAAISAAYJfhuoEwB9AQASAAYJfhuoEwB9AQAAAA==.',
Je='Jebby:BAABLgAECn8VAAMRAAYJ3h17IwC3AQARAAYJ3h17IwC3AQAdAAMJqBxYKgD5AAAAAA==.',
Ji='Jitlok:BAAALgAECgYJEwAAAA==.',
Ka='Kahladin:BAAALgADCgMJAwAAAA==.Kahrot:BAAALgAECgkJEwAAAA==.Kaioken:BAAALgADCgUJBgAAAA==.Kalia:BAAALgAECgYJDgAAAA==.Kalibontu:BAAALgAECgYJDQAAAA==.Kalius:BAABLgAECn8VAAIeAAYJbApVJADmAAAeAAYJbApVJADmAAAAAA==.Kasiusa:BAAALgAECgQJBAABLgAECgYJFAAEAAUIAA==.Kazgrom:BAAALgAECgMJAwAAAA==.Kazool:BAAALgAECgYJEwAAAA==.',
Ke='Keinsi:BAAALgAECggJDgAAAA==.Kenpomonk:BAABLgAECn8mAAIfAAkJYh16AgC4AgAfAAkJYh16AgC4AgAAAA==.',
Ki='Killrbkilled:BAAALgADCgYJCAAAAA==.',
Kn='Knower:BAAALgADCgYJDgAAAA==.Knucklecuffs:BAAALgAECgYJDQABLgAECgYJIwAHANUkAA==.Knyxi:BAAALgADCgEJAQAAAA==.',
Ky='Kyran:BAAALgADCgMJBgABLgAECgYJFAAEAAUIAA==.',
['Kí']='Kíli:BAAALgADCgcJEgAAAA==.',
['Kø']='Køteb:BAAALgAECgYJDgAAAA==.',
La='Lalatinna:BAAALgAECgYJBwAAAA==.Lambdah:BAAALgADCgEJAQAAAA==.Layonagosa:BAABLgAECn8eAAIBAAgJORbCHQD5AQABAAgJORbCHQD5AQAAAA==.',
Le='Leadshot:BAAALgAECgcJDgAAAA==.Letal:BAAALgAECggJCQAAAA==.Leticia:BAAALgADCgUJBQAAAA==.',
Lh='Lhost:BAAALgADCgUJCAAAAA==.',
Li='Lionel:BAAALgADCgUJBQAAAA==.',
Lo='Lostette:BAAALgAECgYJDQAAAA==.',
Lu='Luciné:BAAALgADCgEJAQAAAA==.Luigimangion:BAAALgADCgMJAwAAAA==.',
['Lï']='Lïmes:BAAALgAECgYJEAAAAA==.',
Ma='Maakha:BAAALgAECgYJEgAAAA==.Madiline:BAAALgAECgYJCgAAAA==.Madokakaname:BAAALgADCgYJBgAAAA==.Madsumo:BAAALgAECgYJDAABLgAECgYJGAARAMISAA==.Maehko:BAAALgAECgYJDQAAAA==.Magiaßaiser:BAAALgADCgIJAwAAAA==.Magicmack:BAAALgAECgEJAQAAAA==.Magroot:BAABLgAECn8UAAIIAAYJmhmHEQBaAQAIAAYJmhmHEQBaAQAAAA==.Makel:BAAALgAECgYJCQAAAA==.Mannadina:BAAALgADCgMJAwAAAA==.Mapera:BAABLgAECn8UAAIOAAYJ5x3mCwDpAQAOAAYJ5x3mCwDpAQAAAA==.Marjaya:BAAALgAECgYJDAAAAA==.',
Mc='Mcc:BAAALgAECgQJBAAAAA==.',
Mi='Miandra:BAABLgAECn8cAAIRAAYJih2PKgCYAQARAAYJih2PKgCYAQAAAA==.Michaal:BAAALgAECgQJBwAAAA==.Midnighttank:BAAALgADCgUJBQAAAA==.Miko:BAABLgAECn8XAAISAAYJ8Ah9KADlAAASAAYJ8Ah9KADlAAAAAA==.Mirosa:BAAALgAECgYJDwAAAA==.Mistmuncher:BAAALgADCgIJAgAAAA==.',
Mo='Mommabeans:BAABLgAECn8sAAIDAAkJ0h6ABADiAgADAAkJ0h6ABADiAgAAAA==.Moogar:BAAALgAECgIJAgAAAA==.Moostorm:BAAALgAECgQJCAAAAA==.',
My='Mytdos:BAAALgADCgYJBgAAAA==.',
Na='Nangsa:BAAALgAECgYJCQAAAA==.Nautisassin:BAAALgAECgYJCgABLgAECgYJGAARAMISAA==.Naxz:BAAALgAECgEJAQAAAA==.',
Ne='Necrodk:BAAALgADCgcJDgABLgAECggJIgAXAOElAA==.Necrolock:BAABLgAECn8pAAMLAAkJwh+9DwApAgALAAgJwh+9DwApAgAMAAEJAABAIgBpAAABLgAECggJIgAXAOElAA==.Neilrodimus:BAABLgAECn8bAAIgAAcJox+cAwDWAQAgAAcJox+cAwDWAQAAAA==.Nessva:BAABLgAECn8WAAIYAAYJjxSZCABQAQAYAAYJjxSZCABQAQAAAA==.Neçromonger:BAABLgAECn8iAAIXAAgJ4SXoAQAEAwAXAAgJ4SXoAQAEAwAAAA==.',
No='Novabloom:BAAALgAECgQJCgAAAA==.Novuri:BAABLgAECn8ZAAIeAAYJEA/iHgASAQAeAAYJEA/iHgASAQAAAA==.Noxz:BAABLgAECn8lAAQFAAgJMCFwCQDtAgAFAAgJMCFwCQDtAgAEAAIJEhUKKACPAAAhAAEJFhYtewA8AAAAAA==.',
Ny='Nyiais:BAAALgAECgYJDwAAAA==.',
['Nï']='Nïghtmärë:BAAALgAECgUJDgAAAA==.',
Ob='Obesity:BAAALgAECgEJAQAAAA==.Obsessedwith:BAABLgAECn8cAAIXAAcJ3R4QEgACAgAXAAcJ3R4QEgACAgAAAA==.',
Oh='Ohamernster:BAAALgADCgUJBQAAAA==.',
Oo='Oonspork:BAAALgADCgYJDwAAAA==.',
Or='Ortheus:BAAALgAECgYJDQAAAA==.',
Ou='Oudin:BAAALgADCgEJAQAAAA==.',
Pa='Paladinsucks:BAABLgAECn8bAAMRAAcJtBCwcQCYAQARAAcJtBCwcQCYAQAeAAEJpAnJKwAgAAAAAA==.Pandatude:BAAALgAECgEJAQAAAA==.Pangurrban:BAAALgADCgcJEwAAAA==.Panicblink:BAAALgADCgQJBAAAAA==.',
Ph='Phoshot:BAAALgAECgYJCQAAAA==.',
Po='Poplockvomit:BAABLgAECn8gAAIVAAgJ9REFBQDRAQAVAAgJ9REFBQDRAQAAAA==.',
Ps='Psyscape:BAAALgADCgkJGQAAAA==.',
Pt='Ptaak:BAAALgAECgQJDAAAAA==.',
Pu='Punkhunter:BAAALgAECgYJEwAAAA==.',
Qi='Qijdami:BAAALgAECgYJEQAAAA==.',
Qu='Quangar:BAACLgAFFH8VAAIRAAUJTRSTEQA/AQARAAUJTRSTEQA/AQAuAAQKfyIABBEABwkgHbhKAAICABEABwkgHbhKAAICAB0ABAm2A084AJQAAB4AAQkpDzMoAC8AAAAA.',
Ra='Raichi:BAAALgADCgMJAwAAAA==.Ralas:BAAALgAECgQJBgAAAA==.',
Re='Reallyreally:BAAALgAECgQJBQAAAA==.Reeally:BAAALgAECgYJCwAAAA==.Ren:BAAALgADCgYJDgAAAA==.Reppitt:BAAALgADCgcJDgAAAA==.',
Ri='Riopia:BAAALgADCgYJCwAAAA==.',
Ro='Roenwyn:BAAALgADCgcJDwAAAA==.Ronetto:BAABLgAECn8hAAMBAAgJ+x4qKADSAgABAAgJ+x4qKADSAgAiAAEJnwUwIAAvAAAAAA==.Rons:BAAALgADCggJCwABLgAECggJIQABAPseAA==.Ronsteur:BAAALgAECgcJDQABLgAECggJIQABAPseAA==.Ronwin:BAAALgADCgIJAgABLgAECggJIQABAPseAA==.Roulette:BAAALgADCgMJBgAAAA==.Rozzakbeztok:BAAALgADCgUJBwAAAA==.Rozzanox:BAAALgAECgQJBAABLgAECgYJEwATAAAAAA==.Rozzeran:BAAALgADCgcJCgABLgAECgYJEwATAAAAAA==.Rozzinor:BAAALgAECgYJEwAAAA==.',
Ru='Ruslah:BAAALgAECgYJDAAAAA==.',
Sa='Salii:BAAALgAECggJEgAAAA==.Savageslayer:BAABLgAECn8sAAMbAAkJjR0WAwCnAgAbAAkJjR0WAwCnAgAcAAYJkwSQIACaAAAAAA==.Savagesmonk:BAAALgAECgYJDAAAAA==.Savagespally:BAAALgADCgEJAQAAAA==.',
Se='Senshi:BAABLgAECn8UAAISAAYJWgoOJgD1AAASAAYJWgoOJgD1AAAAAA==.Seventl:BAAALgAECgYJEwAAAA==.',
Sh='Shadowgrave:BAAALgADCgYJBwAAAA==.Shaokhan:BAABLgAECn8ZAAIPAAcJRQ2dLwBqAQAPAAcJRQ2dLwBqAQAAAA==.Shewolf:BAAALgADCgMJAwAAAA==.Shey:BAACLgAFFH8HAAIQAAQJABEsEgAwAQAQAAQJABEsEgAwAQAuAAQKfykAAhAACAlmHN0bAI0BABAACAlmHN0bAI0BAAAA.Shino:BAAALgADCgMJAwAAAA==.',
Si='Silentspells:BAAALgADCgUJBQAAAA==.Simbru:BAABLgAECn8VAAIHAAYJxBNzIQBaAQAHAAYJxBNzIQBaAQAAAA==.Sinuouss:BAABLgAECn8aAAMUAAYJgBlrCwDqAAALAAUJXBWESwAOAQAUAAUJUhprCwDqAAAAAA==.',
Sk='Skipperkato:BAAALgADCgkJBgAAAA==.',
Sp='Spellster:BAAALgAECgQJCAAAAA==.Spooderdaman:BAAALgAECgYJBgAAAA==.Sproach:BAAALgAFFAEJAQAAAA==.',
St='Stainman:BAABLgAECn8ZAAMKAAgJCRggCgDoAQAKAAgJCRggCgDoAQAJAAEJ7wUUQgArAAAAAA==.Starvingwolf:BAABLgAECn8hAAIYAAgJbhcBBADYAQAYAAgJbhcBBADYAQAAAA==.Stonedraek:BAAALgADCgUJBQAAAA==.Stoogatz:BAAALgAECgMJAwABLgAECgYJEwATAAAAAA==.Strongbow:BAAALgADCgcJFgAAAA==.Stýx:BAAALgAECgIJAgAAAA==.',
Su='Sunflowersue:BAAALgADCgEJAQAAAA==.',
Sw='Swaellen:BAAALgAECgYJDAAAAA==.',
Sy='Sylaillea:BAAALgAECgMJAwAAAA==.Sylvester:BAAALgADCgYJBwAAAA==.Syrinn:BAAALgADCgMJAwAAAA==.',
Ta='Takerfan:BAAALgAECgEJAQAAAA==.Tallyblue:BAAALgADCgUJBQAAAA==.Tarrfashi:BAAALgAECgEJAQAAAA==.',
Te='Tega:BAAALgADCgQJBAAAAA==.Temüjin:BAABLgAECn8aAAIBAAYJBBbZRgBaAQABAAYJBBbZRgBaAQAAAA==.',
Th='Theeonlyone:BAABLgAECn8hAAMLAAgJsBqaEQAYAgALAAcJsBqaEQAYAgAUAAQJTRFvNQDhAAAAAA==.Thelockrocks:BAAALgADCgQJBAAAAA==.',
Ti='Tiberlock:BAAALgADCgcJEwAAAA==.Tibernius:BAAALgADCgEJAQABLgADCgcJEwATAAAAAA==.Tiranii:BAAALgAECgcJEwAAAA==.Titannus:BAABLgAECn8YAAIRAAYJwhKaPwBLAQARAAYJwhKaPwBLAQAAAA==.',
Tr='Tralisa:BAAALgADCgMJAwAAAA==.Tribalrage:BAAALgAECgYJEQAAAA==.Tribulation:BAAALgADCgQJBAAAAA==.Tristramhero:BAAALgAECgMJBAAAAA==.',
Tu='Tunipps:BAAALgAECgMJAwAAAA==.',
Ty='Tyriddikk:BAABLgAECn8lAAIcAAgJxCKIAgABAwAcAAgJxCKIAgABAwAAAA==.',
Un='Unholyhavoc:BAAALgAFFAIJAgAAAA==.',
Va='Vael:BAABLgAECn8WAAIjAAYJXQqbDQABAQAjAAYJXQqbDQABAQAAAA==.Vaereir:BAAALgAECgEJAwABLgAFFAMJCAALACsbAA==.Vandal:BAABLgAECn8oAAMFAAgJjh5jBABiAgAFAAgJjh5jBABiAgAEAAMJUgZiRQCOAAAAAA==.Varaug:BAAALgADCgMJAwAAAA==.Vartence:BAAALgAECgYJBgAAAA==.',
Ve='Veedar:BAAALgAECgYJBgAAAA==.Vezpar:BAAALgAECgQJBgAAAA==.',
Vm='Vmax:BAAALgAECgQJCQAAAA==.',
Vo='Voodoomkin:BAAALgAECgcJAQAAAA==.',
Vy='Vynllistar:BAAALgAECgUJCAAAAA==.',
Wa='Warblinox:BAAALgAECgEJAwAAAA==.Wardrel:BAAALgAECgYJEgAAAA==.',
We='Wetbread:BAAALgAECgYJCQAAAA==.',
Wi='Wiind:BAABLgAECn8sAAIkAAkJlRQaBQAQAgAkAAkJlRQaBQAQAgAAAA==.Winger:BAAALgAECgMJAwAAAA==.',
Xe='Xelarosia:BAAALgADCgYJBgABLgAFFAIJAgATAAAAAA==.',
Xo='Xonz:BAABLgAECn8sAAIeAAkJZiE6AgAZAwAeAAkJZiE6AgAZAwAAAA==.',
Xu='Xuljin:BAAALgADCgEJAQABLgAECgcJGQAPAEUNAA==.',
Yo='Yomamasez:BAABLgAECn8aAAIRAAYJVwq2VwAJAQARAAYJVwq2VwAJAQAAAA==.Youpoop:BAAALgAECgYJEgAAAA==.',
Za='Zagina:BAAALgADCggJCAAAAA==.',
Zh='Zhanrax:BAABLgAECn8cAAIeAAcJOAa7FADFAAAeAAcJOAa7FADFAAAAAA==.',
Zi='Zirnbie:BAABLgAECn8VAAIZAAYJfyAzIgC7AQAZAAYJfyAzIgC7AQAAAA==.',
Zo='Zoub:BAAALgAECgQJBwAAAA==.',
Zu='Zurael:BAAALgADCgMJAwAAAA==.',
Zx='Zxon:BAAALgADCgEJAQAAAA==.Zxonbutdrag:BAAALgAECgcJBwAAAA==.',
['Ãç']='Ãçízzlè:BAAALgADCgcJBwAAAA==.',
['Ða']='Ðark:BAABLgAECn8aAAIRAAcJQRqeTwDzAQARAAcJQRqeTwDzAQABLgAFFAMJBwAXABoOAA==.',
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
