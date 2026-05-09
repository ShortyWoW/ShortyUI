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

local lookup = {'Mage-Frost','Mage-Fire','Druid-Restoration','Priest-Discipline','Priest-Shadow','Warrior-Fury','Shaman-Restoration','Rogue-Subtlety','Evoker-Devastation','Evoker-Augmentation','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Rogue-Assassination','Monk-Mistweaver','DemonHunter-Devourer','Monk-Windwalker','Paladin-Retribution','Shaman-Elemental','Unknown-Unknown','Shaman-Enhancement','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Unholy','Rogue-Outlaw','DeathKnight-Frost','Druid-Balance','Druid-Guardian','Priest-Holy','Paladin-Holy','Paladin-Protection','Monk-Brewmaster','DemonHunter-Vengeance','Mage-Arcane','Evoker-Preservation','DemonHunter-Havoc','Druid-Feral',}
local provider = {region='US',realm='Tanaris',name='US',type='weekly',zone=46,date='2026-05-08',data={Ac='Acegoblain:BAACLgAFFH8NAAMBAAQJDxKGMQBGAQABAAQJDxKGMQBGAQACAAEJ5gOyAgBBAAAuAAQKfykAAwEACQkYHroNALACAAEACQkYHroNALACAAIAAQlEBnERACsAAAAA.',
Ad='Aderynn:BAAALgADCgMJAwAAAA==.Adind:BAABLgAECn8VAAIDAAUJExUbOQAxAQADAAUJExUbOQAxAQAAAA==.',
Ah='Aholay:BAAALgAECgcJCgAAAA==.',
Ak='Akkiba:BAAALgADCgYJFQAAAA==.',
Al='Alaval:BAABLgAECn8aAAMEAAYJEQjPJQD7AAAEAAYJEQjPJQD7AAAFAAYJUQyEKgD2AAAAAA==.Alaweth:BAAALgAECgUJCQAAAA==.Aldabaran:BAAALgAECgUJEwAAAA==.Alelros:BAAALgAECgMJAwAAAA==.Aletheïa:BAAALgADCgIJAgAAAA==.Allanonontu:BAAALgADCgcJCwAAAA==.Althamon:BAAALgAECgUJBwAAAA==.',
An='Andromedaa:BAAALgADCgMJAwAAAA==.Angelbabe:BAAALgAECgYJEgAAAA==.Antamun:BAABLgAECn82AAIGAAkJqx2vAwDOAgAGAAkJqx2vAwDOAgAAAA==.Anthuil:BAAALgADCgMJAwAAAA==.',
Ao='Aoasis:BAABLgAECn8pAAIHAAYJRSWmCgCDAgAHAAYJRSWmCgCDAgAAAA==.',
Ar='Araethea:BAAALgADCgYJBgAAAA==.Arcticwings:BAAALgAECgYJEAAAAA==.Arduinna:BAAALgAECgUJBQAAAA==.Arislynn:BAABLgAECn8iAAIIAAcJYw3AFABpAQAIAAcJYw3AFABpAQAAAA==.Artemist:BAAALgADCgYJBgAAAA==.',
As='Ashalerath:BAABLgAECn8eAAMJAAgJChbhAwDLAQAJAAgJChbhAwDLAQAKAAIJJA+vUwB4AAAAAA==.Astralz:BAAALgAECgYJDgAAAA==.',
Az='Azzazel:BAAALgAECgYJCwAAAA==.',
Ba='Badgerhollis:BAAALgADCgYJEAAAAA==.Badmojo:BAAALgADCgQJBAAAAA==.Baha:BAAALgADCgUJBQAAAA==.Bailey:BAAALgAECgYJDAAAAA==.Bankai:BAAALgAECgEJAQAAAA==.Bape:BAAALgAECgUJCQABLgAFFAMJBgALAPsVAA==.Barack:BAAALgAECgQJBwAAAA==.Barkkent:BAAALgADCgIJAgAAAA==.Baromir:BAAALgADCgYJFAAAAA==.Bathin:BAABLgAECn8kAAQMAAgJyh1hAgAJAgAMAAgJCB1hAgAJAgALAAcJEhTSRgBUAQANAAEJERUpJQBAAAAAAA==.',
Be='Beama:BAAALgAECgIJAgAAAA==.Bearbottom:BAAALgADCgQJBQAAAA==.Beetsalad:BAABLgAECn8kAAIOAAgJiCQgAQA0AwAOAAgJiCQgAQA0AwAAAA==.',
Bi='Bigboop:BAAALgAECgYJCwAAAA==.Bigpoppapump:BAAALgADCgYJBwAAAA==.',
Bl='Bloodaxe:BAAALgAECgYJDgAAAA==.',
Bo='Borgad:BAAALgADCgEJAQAAAA==.',
Br='Braer:BAAALgAECgEJAQAAAA==.Bryzxbless:BAAALgAECgYJDwABLgAFFAcJEgAPAKsUAA==.Brîsket:BAAALgADCgEJAQABLgAECgkJIgAQAHoZAA==.',
Bu='Bubblebee:BAAALgAECgMJBAAAAA==.Butterskotch:BAAALgADCgcJBwAAAA==.',
['Bô']='Bôjay:BAAALgADCgcJGAAAAA==.',
Ca='Castiel:BAAALgAECgUJCAAAAA==.',
Ch='Chaosrift:BAAALgADCgYJBgABLgAECggJIQARANgPAA==.Charmy:BAAALgADCgMJAwAAAA==.Chickimama:BAABLgAECn8ZAAIQAAcJDhPvMgBpAQAQAAcJDhPvMgBpAQAAAA==.',
Co='Coagulation:BAABLgAECn8XAAILAAYJrhvBSADwAQALAAYJrhvBSADwAQAAAA==.Corvettefour:BAAALgADCgMJAwAAAA==.Cowboybeast:BAAALgADCgUJBQAAAA==.Cowboyshorn:BAABLgAECn8XAAIQAAYJRBcvRQApAQAQAAYJRBcvRQApAQAAAA==.',
Cr='Credible:BAAALgADCgUJBQAAAA==.Crunchynuget:BAABLgAECn8fAAISAAkJ8R8UDwCEAgASAAkJ8R8UDwCEAgAAAA==.',
Ct='Cts:BAAALgAECgUJCAAAAA==.',
Cu='Cuboose:BAABLgAECn8fAAIHAAgJYyUAAgBNAwAHAAgJYyUAAgBNAwAAAA==.Cubouros:BAAALgADCgEJAQAAAA==.',
Cy='Cybelene:BAAALgAECgUJDAAAAA==.Cyione:BAABLgAECn8lAAITAAgJSwwrIQBHAQATAAgJSwwrIQBHAQAAAA==.Cynemon:BAABLgAECn8VAAIEAAYJ4g2HHABJAQAEAAYJ4g2HHABJAQAAAA==.Cynleel:BAAALgAECgYJBgABLgAECgYJFQAEAOINAA==.',
Da='Dadu:BAAALgADCgYJCwAAAA==.Dandymage:BAAALgAECgcJEQAAAA==.Daretti:BAAALgAECgUJCgAAAA==.Darthvitiate:BAAALgAECgIJAwAAAA==.Dascorupt:BAAALgAECgYJEQAAAA==.Dazzette:BAAALgADCgYJBQABLgAECgQJBAAUAAAAAA==.',
De='Decày:BAAALgAECgcJEgAAAA==.Deemin:BAAALgAECgUJBQABLgAECgcJCAAUAAAAAA==.Delsar:BAAALgADCgkJCgAAAA==.Demogotto:BAAALgADCggJCAAAAA==.Desden:BAAALgAECgYJCQAAAA==.Deåth:BAAALgADCgcJDgAAAA==.',
Di='Dijon:BAAALgADCgUJBQABLgAECgYJHwABAPUhAA==.Divinitey:BAAALgADCgcJCgAAAA==.',
Do='Dorandra:BAAALgADCgIJAgAAAA==.Dorktard:BAAALgADCgUJBgAAAA==.Dotted:BAACLgAFFH8LAAMLAAQJdBvYGAAqAQALAAMJLRvYGAAqAQAMAAEJSBy4BQBeAAAuAAQKfyQABAsACAmUI+8PAPoCAAsACAmUI+8PAPoCAA0AAgl8Iw5DAKkAAAwAAQkAAKQnAFMAAAAA.',
Dr='Drangrods:BAAALgAECgQJBwAAAA==.Draxchii:BAAALgAECgUJAgAAAA==.Draxdecorupt:BAAALgADCgIJAgAAAA==.Draxharmony:BAAALgAECgIJAQAAAA==.Drogonn:BAAALgADCgEJAQAAAA==.',
Ds='Dsypha:BAABLgAECn8iAAIBAAgJIgpxUAB5AQABAAgJIgpxUAB5AQAAAA==.',
['Dâ']='Dâddychill:BAAALgADCgYJBgAAAA==.',
['Då']='Dåmage:BAAALgAECgYJEwAAAA==.',
Ed='Edric:BAABLgAECn8bAAIVAAYJ0SMOBQAFAgAVAAYJ0SMOBQAFAgAAAA==.Edyion:BAABLgAECn8bAAIWAAYJQgcVHwAHAQAWAAYJQgcVHwAHAQAAAA==.',
Ef='Efreet:BAABLgAECn8cAAMXAAcJnCJrDwBbAgAXAAcJnCJrDwBbAgAYAAEJPxKDhQA3AAAAAA==.',
El='Elektron:BAAALgADCgMJAwAAAA==.Elimae:BAAALgAECgEJAQAAAA==.Eliqsed:BAAALgADCgkJDQAAAA==.Elisahel:BAAALgADCgcJBwAAAA==.Elizaa:BAAALgADCgYJCAAAAA==.Elorelei:BAAALgADCgYJBgAAAA==.',
En='Enochian:BAAALgADCgYJBgAAAA==.',
Eu='Eurae:BAABLgAECn8cAAIXAAYJcArwWAAEAQAXAAYJcArwWAAEAQAAAA==.',
Ev='Eviscero:BAABLgAECn8XAAIZAAcJHQuRWQAzAQAZAAcJHQuRWQAzAQAAAA==.Evoda:BAABLgAECn8YAAIaAAYJ1wjjCAD0AAAaAAYJ1wjjCAD0AAAAAA==.',
Ex='Extrodinaire:BAABLgAECn8gAAIVAAgJvhUCBgDnAQAVAAgJvhUCBgDnAQAAAA==.',
Fa='Fadedemon:BAABLgAECn8bAAIQAAgJTxN6MwBnAQAQAAgJTxN6MwBnAQAAAA==.Faedilan:BAAALgAECgEJBgAAAA==.Fallan:BAAALgAECgMJAwAAAA==.Farrahmoans:BAABLgAECn8fAAIBAAYJ9SGfLgDmAQABAAYJ9SGfLgDmAQAAAA==.',
Fe='Fellvarg:BAABLgAECn8bAAIbAAYJyhWIBgBSAQAbAAYJyhWIBgBSAQAAAA==.Felstriker:BAABLgAECn8hAAIQAAcJqhNTTgAOAQAQAAcJqhNTTgAOAQAAAA==.',
Fi='Filí:BAAALgAECgEJAQAAAA==.',
Fo='Fotiá:BAAALgAECgMJAwABLgAFFAQJCQAXAMEaAA==.',
Fr='Frostytip:BAAALgAECgUJDgAAAA==.Fròzensoul:BAAALgADCgYJDAAAAA==.Frøzen:BAAALgAECgcJEwAAAA==.',
Fu='Furiosa:BAAALgAECgYJBgAAAA==.Fuzzyren:BAAALgAECgEJAQAAAA==.',
Ga='Gahïjï:BAAALgAECgYJBgABLgAECgYJKQAHAEUlAA==.Gallium:BAAALgADCgYJDwAAAA==.Galroot:BAAALgAECgQJDAABLgAFFAQJDQABAA8SAA==.Galvakrond:BAAALgAECgYJEwAAAA==.',
Ge='Geearr:BAAALgADCgcJBwAAAA==.',
Gi='Gillfy:BAAALgAECgQJBQABLgAECgYJGgAEABEIAA==.Giltor:BAAALgAECgEJAQAAAA==.',
Go='Gomletta:BAAALgAECgYJDwAAAA==.',
Gr='Grak:BAAALgADCgkJGQABLgAECgkJLQAFAHEdAA==.Gravey:BAABLgAECn8kAAMcAAgJChs5CgAnAgAcAAgJChs5CgAnAgAdAAEJVAfbNQAeAAAAAA==.Greggor:BAAALgADCgYJBgAAAA==.Grik:BAABLgAECn8pAAIJAAgJaQ7xBQB2AQAJAAgJaQ7xBQB2AQAAAA==.Grimminhagen:BAAALgADCgEJAgAAAA==.Grêed:BAAALgADCgYJBgAAAA==.',
Gu='Guigon:BAAALgADCgEJAQAAAA==.Guldio:BAAALgADCgIJAgAAAA==.',
Gw='Gwyndora:BAABLgAECn8WAAIeAAcJ3hgZEADqAQAeAAcJ3hgZEADqAQAAAA==.',
Ha='Hashira:BAAALgAECgcJCgAAAA==.',
He='Healup:BAAALgADCgUJBQAAAA==.',
Ho='Holyoshyy:BAAALgADCgcJBwABLgAECgYJCgAUAAAAAA==.Holyvengence:BAAALgAECgIJAwABLgAECgYJEQAUAAAAAA==.',
Hr='Hroth:BAAALgADCgIJAgAAAA==.',
Hu='Hup:BAAALgADCgIJAgAAAA==.',
['Hÿ']='Hÿmpëñ:BAAALgADCgYJBgAAAA==.',
Ie='Iemanja:BAAALgAECgcJDwAAAA==.',
Ih='Iharjathinji:BAAALgADCggJCAAAAA==.',
Im='Impawster:BAAALgADCgUJBQAAAA==.',
Is='Isaacu:BAAALgADCgMJAwAAAA==.',
It='Ithaka:BAAALgAECggJCQAAAA==.Itzsavage:BAAALgADCgcJDQAAAA==.',
Ja='Jachyra:BAABLgAECn8bAAIOAAYJjxjRBgB7AQAOAAYJjxjRBgB7AQAAAA==.Jackmanss:BAAALgAECgUJEwAAAA==.Jaegersan:BAAALgAECgUJBQAAAA==.Jaell:BAAALgAECgEJAQAAAA==.Jamezon:BAABLgAECn8iAAIGAAgJhhuECwAxAgAGAAgJhhuECwAxAgAAAA==.Jarttshocks:BAABLgAECn8WAAITAAYJhRsdGwB1AQATAAYJhRsdGwB1AQAAAA==.',
Je='Jebby:BAABLgAECn8bAAMSAAYJyiLLIQAAAgASAAYJyiLLIQAAAgAfAAMJqBwdNgDwAAAAAA==.Jebraxis:BAAALgAECgEJAQAAAA==.',
Ji='Jitlok:BAABLgAECn8ZAAIVAAYJdg/vDQAnAQAVAAYJdg/vDQAnAQAAAA==.',
Ka='Kabun:BAAALgAECgIJAgAAAA==.Kahladin:BAAALgADCgMJAwAAAA==.Kahrot:BAABLgAECn8cAAIZAAkJfRoBEAB/AgAZAAkJfRoBEAB/AgAAAA==.Kaioken:BAAALgADCgUJBgAAAA==.Kalia:BAAALgAECgcJEgAAAA==.Kalibontu:BAAALgAECgcJEgAAAA==.Kalius:BAABLgAECn8bAAIgAAYJbQtUJADmAAAgAAYJbQtUJADmAAAAAA==.Kasiusa:BAAALgAECgUJCAABLgAECgYJGgAEABEIAA==.Kazgrom:BAAALgAECgUJBwAAAA==.Kazool:BAABLgAECn8YAAINAAYJex7TBAC4AQANAAYJex7TBAC4AQAAAA==.',
Ke='Keinsi:BAABLgAECn8WAAIbAAgJJAf2BwAoAQAbAAgJJAf2BwAoAQAAAA==.Kenpomonk:BAACLgAFFH8FAAIhAAMJJBFQHwDjAAAhAAMJJBFQHwDjAAAuAAQKfy8AAiEACQmoHQIEALMCACEACQmoHQIEALMCAAAA.',
Ki='Killrbkilled:BAAALgADCgYJCAAAAA==.',
Kn='Knower:BAAALgADCgYJDgAAAA==.Knucklecuffs:BAAALgAECgYJEwABLgAECgYJKQAHAEUlAA==.Knyxi:BAAALgADCgEJAQAAAA==.',
Ky='Kyran:BAAALgADCgMJBgABLgAECgYJGgAEABEIAA==.',
['Kí']='Kíli:BAAALgAECgEJAQAAAA==.',
['Kø']='Køteb:BAAALgAECgYJDgAAAA==.',
La='Lalatinna:BAAALgAECgYJBwAAAA==.Lambdah:BAAALgADCgEJAQAAAA==.Layonagosa:BAABLgAECn8kAAIBAAgJORZPKwD0AQABAAgJORZPKwD0AQAAAA==.',
Le='Leadshot:BAABLgAECn8VAAIXAAcJkwqwTwB6AQAXAAcJkwqwTwB6AQAAAA==.Letal:BAAALgAECggJCwAAAA==.Leticia:BAAALgAECgIJAgAAAA==.',
Lh='Lhost:BAAALgADCgUJCAAAAA==.',
Li='Lionel:BAAALgADCgUJBQAAAA==.',
Lo='Lostette:BAAALgAECgcJEgAAAA==.',
Lu='Luciné:BAAALgADCgEJAQAAAA==.Luigimangion:BAAALgAECgEJAQAAAA==.',
['Lï']='Lïmes:BAABLgAECn8WAAIHAAYJKRKjOgAcAQAHAAYJKRKjOgAcAQAAAA==.',
Ma='Maakha:BAABLgAECn8YAAIGAAYJdQcYNQD0AAAGAAYJdQcYNQD0AAAAAA==.Madiline:BAAALgAECgYJCgAAAA==.Madokakaname:BAAALgADCgYJBgAAAA==.Madsumo:BAAALgAECgYJDAABLgAECgYJHgASAEMVAA==.Maehko:BAAALgAECgcJEgAAAA==.Magiaßaiser:BAAALgADCgIJAwAAAA==.Magicmack:BAAALgAECgEJAQAAAA==.Magroot:BAABLgAECn8eAAIIAAgJkh4oBQBuAgAIAAgJkh4oBQBuAgAAAA==.Makel:BAAALgAECgYJDAAAAA==.Mana:BAAALgAECgYJBgAAAA==.Mannadina:BAAALgADCgMJAwAAAA==.Mapera:BAABLgAECn8aAAIPAAYJ1x1MDwD4AQAPAAYJ1x1MDwD4AQAAAA==.Marjaya:BAAALgAECgYJDAAAAA==.',
Mc='Mcc:BAAALgAECgQJBAAAAA==.',
Mi='Miandra:BAABLgAECn8kAAISAAgJhB0JFQBRAgASAAgJhB0JFQBRAgAAAA==.Michaal:BAAALgAECgcJDgAAAA==.Midnighttank:BAAALgADCgUJBQAAAA==.Miko:BAABLgAECn8hAAITAAgJqAshIABOAQATAAgJqAshIABOAQAAAA==.Mirosa:BAABLgAECn8VAAIBAAYJYwP4pADKAAABAAYJYwP4pADKAAAAAA==.Mistmuncher:BAAALgADCgIJAgAAAA==.',
Mo='Mommabeans:BAACLgAFFH8FAAIDAAMJ4AbUKgCiAAADAAMJ4AbUKgCiAAAuAAQKfzUAAgMACQmEH1EGAO0CAAMACQmEH1EGAO0CAAAA.Moogar:BAAALgAECgMJAwAAAA==.Moostorm:BAAALgAECgQJCAAAAA==.',
My='Mytdos:BAAALgADCgYJBgAAAA==.',
Na='Nangsa:BAAALgAECgYJDwAAAA==.Nautisassin:BAAALgAECgYJCgABLgAECgYJHgASAEMVAA==.Naxz:BAAALgAECgEJAQAAAA==.',
Ne='Necrodk:BAAALgAECgIJBAABLgAFFAMJCAALAHIPAA==.Necrolock:BAACLgAFFH8IAAILAAMJcg8vSQDGAAALAAMJcg8vSQDGAAAuAAQKfykAAwsACQnDH7EdAKQCAAsACAnDH7EdAKQCAAwAAQkAAEAiAGkAAAAA.Neilrodimus:BAABLgAECn8jAAIiAAcJLiJIAwAhAgAiAAcJLiJIAwAhAgAAAA==.Nessva:BAABLgAECn8cAAIYAAYJYRoaCACDAQAYAAYJYRoaCACDAQAAAA==.Neçromonger:BAACLgAFFH8FAAIXAAMJoCOmDgDXAAAXAAMJoCOmDgDXAAAuAAQKfysAAhcACQmhJlwAAIADABcACQmhJlwAAIADAAEuAAUUAwkIAAsAcg8A.',
Ni='Ninurta:BAAALgADCgQJBgAAAA==.Niratre:BAAALgADCgEJAQAAAA==.',
No='Novabloom:BAAALgAECgQJCgAAAA==.Novuri:BAABLgAECn8jAAIgAAgJeg0HEQAtAQAgAAgJeg0HEQAtAQAAAA==.Noxz:BAACLgAFFH8FAAMFAAMJJhlGEAAMAQAFAAMJJhlGEAAMAQAEAAEJ8glIKQBCAAAuAAQKfy0ABAUACAnIIusDALMCAAUACAnIIusDALMCAAQAAgkwFUM0AI4AAB4AAQkWFi97ADwAAAAA.',
Ny='Nyiais:BAAALgAECgYJDwAAAA==.',
['Nï']='Nïghtmärë:BAAALgAECgUJEwAAAA==.',
Ob='Obesity:BAAALgAECgEJAQAAAA==.Obsessedwith:BAABLgAECn8kAAIXAAgJ8CDCCQCaAgAXAAgJ8CDCCQCaAgAAAA==.',
Oh='Ohamernster:BAAALgADCgkJBQAAAA==.',
Oo='Oonspork:BAAALgADCgYJFQAAAA==.',
Or='Ortheus:BAAALgAECgYJDwAAAA==.',
Ou='Oudin:BAAALgADCgEJAQAAAA==.',
Pa='Paladinsucks:BAABLgAECn8cAAMSAAcJ3RC1cQCYAQASAAcJ3RC1cQCYAQAgAAEJpglBNwAdAAAAAA==.Pandatude:BAAALgAECgEJAQAAAA==.Pangurrban:BAAALgAECgEJAQAAAA==.Panicblink:BAAALgAECgEJAQAAAA==.',
Ph='Phoshot:BAAALgAECgYJCQAAAA==.',
Po='Poinen:BAAALgAECgQJBAABLgAECgkJLQAFAHEdAA==.Poplockvomit:BAABLgAECn8pAAIVAAkJ1RQFBAAzAgAVAAkJ1RQFBAAzAgAAAA==.',
Ps='Psyscape:BAAALgADCgkJHAAAAA==.',
Pt='Ptaak:BAAALgAECgQJDAAAAA==.',
Pu='Punkhunter:BAABLgAECn8ZAAIXAAYJxQT0YwDlAAAXAAYJxQT0YwDlAAAAAA==.',
Qi='Qijdami:BAAALgAECgYJEgAAAA==.',
Qu='Quangar:BAACLgAFFH8aAAISAAUJShd4GABJAQASAAUJShd4GABJAQAuAAQKfyIABBIABwkgHblKAAICABIABwkgHblKAAICAB8ABAm3A91GAI8AACAAAQk1D3YyAC4AAAAA.',
Ra='Raichi:BAAALgAECgUJBQAAAA==.Ralas:BAAALgAECgQJBgAAAA==.',
Re='Reallyisreal:BAAALgADCgMJAwAAAA==.Reallyreally:BAAALgAECgUJBwAAAA==.Reeally:BAAALgAECggJEwAAAA==.Ren:BAAALgADCgYJDgAAAA==.Reppitt:BAAALgAECgEJAQAAAA==.',
Ri='Riopia:BAAALgADCgYJCwAAAA==.',
Ro='Roenwyn:BAAALgAECgEJAQAAAA==.Ronetto:BAABLgAECn8kAAMBAAgJ+x4qKADSAgABAAgJ+x4qKADSAgAjAAEJnwUxIAAvAAABLgAECgkJFgAKAIwYAA==.Rons:BAAALgADCggJCwABLgAECgkJFgAKAIwYAA==.Ronsteur:BAABLgAECn8WAAMKAAkJjBgXBwBnAgAKAAkJjBgXBwBnAgAkAAEJAAieSgAtAAAAAA==.Ronwin:BAAALgADCgIJAgABLgAECgkJFgAKAIwYAA==.Roulette:BAAALgADCgMJBgAAAA==.Rozzakbeztok:BAAALgADCgUJBwAAAA==.Rozzanox:BAAALgAECgQJBAABLgAECgYJEAAlAI4VAA==.Rozzeran:BAAALgAECgUJBQABLgAECgYJEAAlAI4VAA==.Rozzinor:BAABLgAECn8QAAQlAAYJjhXCGQARAQAlAAYJjhXCGQARAQAiAAEJAAAVJwBNAAAQAAMJ9QS5pwBKAAAAAA==.',
Ru='Rubystars:BAAALgAECgUJBQABLgAFFAQJCQAXAMEaAA==.Ruslah:BAAALgAECgcJEwAAAA==.Ruslav:BAAALgADCgIJAgABLgAECgcJEwAUAAAAAA==.',
Sa='Saintos:BAAALgAECgEJAQAAAA==.Salii:BAAALgAECggJEgAAAA==.Savageslayer:BAACLgAFFH8FAAIcAAMJCguwGQDYAAAcAAMJCguwGQDYAAAuAAQKfzUAAxwACQmvH68CAPACABwACQmvH68CAPACAB0ABgmTBJEgAJoAAAAA.Savagesmonk:BAAALgAECgcJEQAAAA==.Savagespally:BAAALgAECgQJBwAAAA==.',
Se='Senshi:BAABLgAECn8bAAITAAcJRAw5JQAuAQATAAcJRAw5JQAuAQAAAA==.Seventl:BAABLgAECn8cAAMOAAgJohQWBADbAQAOAAgJohQWBADbAQAIAAUJ0hFnOwA+AQAAAA==.',
Sh='Shadowgrave:BAAALgADCgYJBwAAAA==.Shaokhan:BAABLgAECn8hAAMRAAgJ2A9OFwBtAQARAAgJ2A9OFwBtAQAhAAMJWg3zPwCXAAAAAA==.Shewolf:BAAALgADCgkJCgAAAA==.Shey:BAACLgAFFH8IAAIQAAQJuxI1IAAsAQAQAAQJuxI1IAAsAQAuAAQKfy8AAhAACAlcHY4YAPgBABAACAlcHY4YAPgBAAAA.Shino:BAAALgAECgQJBAAAAA==.Shoktopus:BAAALgADCgYJBgAAAA==.',
Si='Silentspells:BAAALgADCgUJBQAAAA==.Simbru:BAABLgAECn8bAAIHAAYJHxXbKwBpAQAHAAYJHxXbKwBpAQAAAA==.Sinuouss:BAABLgAECn8gAAMNAAYJ+xntDgDlAAALAAUJlxbiXQAWAQANAAUJhRrtDgDlAAAAAA==.',
Sk='Skipperkato:BAAALgADCgkJBgAAAA==.',
Sp='Spooderdaman:BAAALgAECgYJBgAAAA==.Sproach:BAAALgAFFAEJAQAAAA==.',
St='Stainman:BAABLgAECn8ZAAMKAAgJGBiEDgDnAQAKAAgJGBiEDgDnAQAJAAEJ7wUTQgArAAAAAA==.Starvingwolf:BAABLgAECn8hAAIYAAgJehfaBQDBAQAYAAgJehfaBQDBAQAAAA==.Stonedraek:BAAALgADCgUJBQAAAA==.Stoogatz:BAAALgAECgMJAwABLgAECgYJEAAlAI4VAA==.Strongbow:BAAALgADCgcJHAAAAA==.Stýx:BAAALgAECgIJAgAAAA==.',
Su='Sunflowersue:BAAALgADCgEJAQAAAA==.',
Sw='Swaellen:BAAALgAECgYJEAAAAA==.',
Sy='Sylaillea:BAAALgAECgMJAwAAAA==.Sylvester:BAAALgADCgYJBwAAAA==.Syrinn:BAAALgAECgUJBgAAAA==.',
['Só']='Sólutións:BAAALgADCggJCQAAAA==.',
Ta='Takerfan:BAAALgAECgIJAgAAAA==.Tallyblue:BAAALgADCgUJBQAAAA==.Tarrfashi:BAAALgAECgQJBQAAAA==.',
Te='Tega:BAAALgADCgQJBAAAAA==.Temüjin:BAABLgAECn8kAAIBAAgJKRfwKgD2AQABAAgJKRfwKgD2AQAAAA==.',
Th='Theeonlyone:BAABLgAECn8iAAMLAAgJtBodGwANAgALAAcJtBodGwANAgANAAQJTRFsNQDhAAAAAA==.Thelockrocks:BAAALgADCgQJBAAAAA==.',
Ti='Tiberlock:BAAALgAECgIJAgAAAA==.Tibernius:BAAALgADCgEJAQABLgAECgIJAgAUAAAAAA==.Tioshadow:BAAALgADCgYJBgABLgAECggJIQARANgPAA==.Tiranii:BAABLgAECn8bAAIWAAgJ8QrsEACfAQAWAAgJ8QrsEACfAQAAAA==.Titannus:BAABLgAECn8eAAISAAYJQxVMUQBTAQASAAYJQxVMUQBTAQAAAA==.',
Tr='Tralisa:BAAALgADCgMJAwAAAA==.Tribalrage:BAABLgAECn8WAAIHAAYJrwylOgAcAQAHAAYJrwylOgAcAQAAAA==.Tribulation:BAAALgADCgcJCgAAAA==.Tristramhero:BAAALgAECgMJBAAAAA==.',
Tu='Tunipps:BAAALgAECgMJAwAAAA==.',
Ty='Tymberh:BAAALgADCgkJCQABLgAECgYJHgASAEMVAA==.Tyriddikk:BAABLgAECn8lAAIdAAgJxCKHAgABAwAdAAgJxCKHAgABAwAAAA==.',
Un='Unholyhavoc:BAABLgAFFH8FAAIZAAIJJhwyYQC2AAAZAAIJJhwyYQC2AAAAAA==.',
Va='Vael:BAABLgAECn8ZAAMmAAcJtAl7DwAgAQAmAAcJtAl7DwAgAQADAAIJsQZXhABKAAAAAA==.Vaereir:BAAALgAECgEJAwABLgAFFAQJCwALAHQbAA==.Vandal:BAABLgAECn8tAAMFAAkJcR2HAwDBAgAFAAkJcR2HAwDBAgAEAAMJUgZjRQCOAAAAAA==.Varaug:BAAALgADCgMJAwAAAA==.Vartence:BAAALgAECgYJBgAAAA==.',
Ve='Veedar:BAAALgAECgYJBgAAAA==.Vezpar:BAAALgAECgQJBgAAAA==.',
Vi='Violetfoxx:BAAALgAECgEJAQAAAA==.',
Vm='Vmax:BAAALgAECgQJCQAAAA==.',
Vo='Voodoomkin:BAAALgAECgcJAQAAAA==.',
Vy='Vynllistar:BAAALgAECgYJCgAAAA==.',
Wa='Warblinox:BAAALgAECgEJAwAAAA==.Wardrel:BAABLgAECn8VAAIhAAcJkxKUIAAyAQAhAAcJkxKUIAAyAQAAAA==.',
We='Wetbread:BAAALgAECgYJCQAAAA==.',
Wi='Wiind:BAACLgAFFH8FAAIkAAMJagUqFgClAAAkAAMJagUqFgClAAAuAAQKfzUAAiQACQmPFZUGABgCACQACQmPFZUGABgCAAAA.Winger:BAAALgAECgMJAwAAAA==.',
Xe='Xelarosia:BAAALgADCgYJBgABLgAFFAIJBQAZACYcAA==.',
Xo='Xonz:BAACLgAFFH8FAAIgAAMJthMqBQDIAAAgAAMJthMqBQDIAAAuAAQKfzUAAiAACQnUIRQBAOUCACAACQnUIRQBAOUCAAAA.',
Xu='Xuljin:BAAALgADCgQJBQABLgAECggJIQARANgPAA==.',
Yo='Yomamasez:BAABLgAECn8gAAISAAYJjwxZbAAUAQASAAYJjwxZbAAUAQAAAA==.Youpoop:BAABLgAECn8WAAIXAAcJ3wnqQgBFAQAXAAcJ3wnqQgBFAQAAAA==.',
Za='Zagina:BAAALgADCggJCAAAAA==.',
Zh='Zhanrax:BAABLgAECn8kAAIgAAgJLAdpFQD1AAAgAAgJLAdpFQD1AAAAAA==.Zhenith:BAAALgADCgYJBgABLgADCgUJBgAUAAAAAA==.',
Zi='Zirnbie:BAABLgAECn8bAAIZAAYJTCHAKgDRAQAZAAYJTCHAKgDRAQAAAA==.',
Zo='Zoub:BAAALgAECgQJBwAAAA==.',
Zu='Zurael:BAAALgADCgMJAwAAAA==.',
Zx='Zxon:BAAALgADCgEJAQAAAA==.Zxonbutdrag:BAAALgAECgcJCAAAAA==.',
['Ãç']='Ãçízzlè:BAAALgADCgcJBwAAAA==.',
['Ða']='Ðark:BAABLgAECn8aAAISAAcJQRqeTwDzAQASAAcJQRqeTwDzAQAAAA==.',
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
