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

local lookup = {'Hunter-BeastMastery','Druid-Guardian','Unknown-Unknown','DemonHunter-Vengeance','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Paladin-Retribution','Monk-Mistweaver','Shaman-Restoration','DeathKnight-Blood','DemonHunter-Devourer','DeathKnight-Unholy','Druid-Restoration','Hunter-Survival','Hunter-Marksmanship','Rogue-Subtlety','Paladin-Protection','Warrior-Fury','Druid-Balance','Mage-Frost','DeathKnight-Frost','Priest-Discipline','Priest-Holy','Priest-Shadow','Shaman-Elemental','Paladin-Holy','Druid-Feral','Monk-Windwalker','Monk-Brewmaster','Evoker-Devastation','Evoker-Augmentation','Mage-Arcane',}
local provider = {region='US',realm='Hydraxis',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abberleigh:BAAALgAECgIJAgAAAA==.',
Ad='Adonya:BAAALgADCgIJAQAAAA==.',
Ae='Aelgagar:BAAALgAECgYJEAAAAA==.Aelirina:BAAALgADCgcJBwAAAA==.',
Ah='Ahamay:BAAALgADCgEJAgAAAA==.',
Ai='Ailde:BAAALgADCgkJDgAAAA==.',
Al='Alania:BAAALgADCgYJCAAAAA==.Alaraa:BAAALgAECgMJBAABLgAECgcJJAABAHQbAA==.Alarlia:BAABLgAECn8eAAICAAcJKw2vDQDdAAACAAcJKw2vDQDdAAAAAA==.Algonq:BAAALgADCgcJDAABLgAECgYJEwADAAAAAA==.Alliesofevil:BAAALgAECgYJEQAAAA==.Allsar:BAAALgAECggJDwABLgAECggJFgAEAOsUAA==.Alsar:BAAALgAECgQJBAABLgAECggJFgAEAOsUAA==.Alsisst:BAAALgADCgQJBAAAAA==.',
Am='Amathushhg:BAABLgAECn81AAQFAAgJzBezHwC3AQAFAAgJUhSzHwC3AQAGAAcJ5g+fGwBwAQAHAAIJ+wtaDwBEAAAAAA==.Amaunet:BAAALgADCgUJBQAAAA==.',
An='Anahilis:BAAALgADCgcJCAAAAA==.Andarial:BAAALgAECgUJCgAAAA==.Andreth:BAAALgAECgMJBQAAAA==.Anthe:BAAALgADCgcJDwAAAA==.Anzul:BAABLgAECn8lAAIIAAkJMh6SEAA4AgAIAAkJMh6SEAA4AgAAAA==.',
Ar='Araestirra:BAAALgAECgQJBgAAAA==.Arcanmaggy:BAAALgADCgkJHgABLgAFFAMJBQAFABYBAA==.Ardahh:BAAALgADCgQJBAAAAA==.Arnold:BAABLgAECn8WAAIEAAgJ6xSYCwCjAQAEAAgJ6xSYCwCjAQAAAA==.Arroes:BAABLgAECn8YAAIJAAcJ6B7vCAAiAgAJAAcJ6B7vCAAiAgAAAA==.',
As='Asahna:BAAALgAECgQJBAAAAA==.',
Au='Aurrell:BAAALgADCgcJBwAAAA==.',
Av='Avoid:BAAALgADCggJCQAAAA==.',
Ay='Ayroona:BAABLgAECn8fAAIKAAcJZgkQLgALAQAKAAcJZgkQLgALAQAAAA==.',
Az='Azhol:BAAALgAECgQJBAAAAA==.',
Ba='Bacontotem:BAAALgADCgMJBQAAAA==.Baelhal:BAACLgAFFH8HAAILAAMJYgxBDgC9AAALAAMJYgxBDgC9AAAuAAQKfycAAgsACAkZFskJAHgBAAsACAkZFskJAHgBAAAA.Barbaydos:BAAALgADCggJCQAAAA==.Basement:BAABLgAECn8SAAIMAAYJ7x34IABtAQAMAAYJ7x34IABtAQAAAA==.',
Be='Beastnite:BAAALgADCgcJEAABLgADCgkJEQADAAAAAA==.Bellaburger:BAAALgAFFAQJBAAAAA==.Bellissidan:BAAALgAECgEJAwAAAA==.Benedin:BAAALgAECgEJAQABLgAECggJIAAFAMoVAA==.',
Bi='Bigpapapete:BAAALgAECgYJAwAAAA==.Bigtex:BAAALgAECgYJEwAAAA==.Biped:BAABLgAECn8WAAIHAAYJCRDEBABHAQAHAAYJCRDEBABHAQAAAA==.',
Bl='Blackdeath:BAABLgAECn8hAAINAAgJThVPYgDMAQANAAgJThVPYgDMAQAAAA==.',
Bo='Bombarian:BAAALgAECgUJCwAAAA==.Boomstique:BAAALgAECgYJEwAAAA==.Boondocka:BAAALgAECgQJBgAAAA==.',
Br='Brewco:BAABLgAECn8kAAMOAAgJmx6pFACQAgAOAAgJmx6pFACQAgACAAEJ6AfXIAAmAAAAAA==.Bruda:BAAALgAECgIJAwAAAA==.Brutalís:BAAALgAECgYJDgAAAA==.',
Bt='Btrain:BAAALgAECgUJDAAAAA==.',
['Bó']='Bóunty:BAABLgAECn8UAAQPAAYJRyAaEADBAQAPAAYJ5hwaEADBAQABAAQJLB5FXgBNAQAQAAEJPgJcmAAeAAAAAA==.',
Ca='Canadia:BAAALgAECgQJBgAAAA==.Catdaddan:BAAALgADCgYJBgAAAA==.Cavisch:BAABLgAECn8gAAMFAAgJyhU9PAAcAgAFAAgJyhU9PAAcAgAHAAIJGA7/GwCTAAAAAA==.',
Ce='Cenobité:BAAALgAECgkJEQAAAA==.Cerr:BAAALgAECgMJBAAAAA==.',
Ch='Chamber:BAAALgADCgcJDQABLgAECgYJEgAMAO8dAA==.Chantilly:BAAALgADCgYJDwAAAA==.Chaosmaster:BAAALgAECgMJAwAAAA==.Chardee:BAABLgAFFH8HAAIRAAMJlBUeDQAVAQARAAMJlBUeDQAVAQAAAA==.Charmeleon:BAAALgAECggJCgAAAA==.Charmin:BAAALgADCgUJBQAAAA==.',
Ci='Cirax:BAAALgAECgUJEQAAAA==.Cirin:BAAALgADCgEJAQAAAA==.Citruscoolin:BAAALgAECgEJAQAAAA==.',
Cl='Clenton:BAABLgAECn8pAAISAAgJtgU8EQDwAAASAAgJtwU8EQDwAAAAAA==.',
Co='Cobrakai:BAAALgAECgEJAQAAAA==.Cowboyup:BAAALgADCgYJBgAAAA==.',
Cr='Crichton:BAACLgAFFH8FAAIMAAMJlxKuHgDtAAAMAAMJlxKuHgDtAAAuAAQKfyEAAgwACAkrISAiAIQCAAwACAkrISAiAIQCAAAA.Cronnan:BAAALgAECgMJAwAAAA==.Crowford:BAAALgAECgYJEQAAAA==.',
Cy='Cyris:BAAALgADCgcJFgABLgAECgYJEwADAAAAAA==.',
Da='Daemonfaust:BAAALgAECgQJBwAAAA==.Daevahna:BAAALgADCgYJBgAAAA==.Dak:BAAALgAECggJCwAAAA==.Dalsar:BAAALgADCgcJBwAAAA==.Darkbrew:BAAALgADCgYJCAABLgAECgYJEwADAAAAAA==.Darkmiza:BAACLgAFFH8FAAIFAAMJFgENRQCeAAAFAAMJFgENRQCeAAAuAAQKfywAAwUACAksER0wAGsBAAUACAksER0wAGsBAAYAAglDC0RYAGYAAAAA.Darkseer:BAAALgAECgQJBwAAAA==.Dasham:BAAALgAECgQJBAAAAA==.Daymann:BAABLgAECn8UAAIIAAYJ/RXfcQCYAQAIAAYJ/RXfcQCYAQAAAA==.',
De='Deadmangalad:BAAALgAECgYJEwAAAA==.Deedees:BAAALgAECgYJCgAAAA==.Demonbo:BAABLgAECn8UAAIMAAcJ5hKpYAB/AQAMAAcJ5hKpYAB/AQAAAA==.Demondrink:BAAALgAECgQJBgAAAA==.Demonhandler:BAAALgADCggJDwAAAA==.Deo:BAACLgAFFH8HAAITAAMJVBA/EQD9AAATAAMJVBA/EQD9AAAuAAQKfycAAhMACAk0I1IMAPYCABMACAk0I1IMAPYCAAAA.Depression:BAAALgADCgUJBQAAAA==.Derpixion:BAABLgAECn8iAAMBAAgJpxcaFQDpAQABAAgJpxcaFQDpAQAPAAUJXwvbFwD+AAAAAA==.Dessirius:BAAALgADCgEJAQAAAA==.Dethphalanax:BAAALgADCgUJCQAAAA==.',
Di='Digbie:BAAALgADCgYJBwAAAA==.Digs:BAAALgADCgMJAwAAAA==.Dirtnåp:BAAALgADCggJHQAAAA==.Diskbänk:BAAALgAECgUJBgAAAA==.',
Dk='Dkho:BAAALgAECgcJEwAAAA==.',
Do='Dogminos:BAAALgADCgIJAgAAAA==.',
Dr='Drago:BAAALgAECgEJAgAAAA==.Dragontoast:BAAALgAECgMJBQAAAA==.Dral:BAEALgADCgkJIgAAAA==.Drphilyobody:BAAALgAECgUJDQAAAA==.Drui:BAABLgAECn8WAAIUAAcJLw8ONgBkAQAUAAcJLw8ONgBkAQAAAA==.Druidïan:BAAALgAECgEJAQAAAA==.',
Du='Duelittle:BAAALgAECgYJEQAAAA==.',
Dy='Dynwor:BAAALgAECgEJAQAAAA==.',
['Dé']='Dérailed:BAAALgAECgUJEgAAAA==.',
['Dî']='Dîz:BAAALgADCgEJAQAAAA==.',
Ea='Easme:BAAALgAECgYJDwAAAA==.Eatmyfrontal:BAABLgAECn8WAAIVAAYJXREsTwBDAQAVAAYJXREsTwBDAQAAAA==.',
Eb='Ebbola:BAAALgADCgcJDgAAAA==.Ebon:BAAALgAECgIJAgABLgAECgMJAwADAAAAAA==.',
Eh='Ehsinat:BAAALgADCgYJBgAAAA==.',
El='Elaraa:BAAALgADCgYJBwAAAA==.',
Ep='Epikrate:BAABLgAECn8WAAMFAAYJchxHYgDNAAAFAAUJjxtHYgDNAAAGAAMJ4xilSACUAAAAAA==.',
Es='Escaper:BAABLgAECn8gAAIWAAcJ+wxBBQBBAQAWAAcJ+wxBBQBBAQAAAA==.',
Ex='Extrema:BAAALgAECgMJBQAAAA==.',
Fa='Faesha:BAAALgAECgEJAQAAAA==.Fallenash:BAAALgADCgMJAwABLgAFFAMJBwAVAEcaAA==.Fallenembers:BAACLgAFFH8HAAIVAAMJRxorLgARAQAVAAMJRxorLgARAQAuAAQKfyYAAhUACAkzJR0GANYCABUACAkzJR0GANYCAAAA.Famine:BAABLgAECn8bAAMNAAYJ9Qa0YQDjAAANAAYJfgW0YQDjAAAWAAUJzAf6DADfAAAAAA==.Farquaadtwo:BAAALgAECgIJAgAAAA==.',
Fe='Fearofthdark:BAAALgADCgEJAQAAAA==.',
Ff='Fflar:BAAALgADCgUJBQAAAA==.',
Fh='Fhait:BAAALgADCggJJAABLgAECgYJEwADAAAAAA==.',
Fi='Firsttimepvp:BAABLgAECn8UAAIRAAgJSAeLKwCiAQARAAgJSAeLKwCiAQAAAA==.',
Fl='Flow:BAAALgADCgYJBgAAAA==.',
Fr='Frenchtoast:BAAALgAECgIJAgAAAA==.Frostyflaker:BAAALgAECgIJAgAAAA==.',
Ga='Gaiã:BAAALgADCgEJAgAAAA==.Gaskelmarg:BAAALgADCgcJBwAAAA==.',
Gh='Ghosty:BAABLgAECn8fAAQXAAgJkBRmDQCyAQAXAAgJtRBmDQCyAQAYAAcJoQt8TgD+AAAZAAEJegEAAAAAAAAAAA==.Ghuun:BAAALgADCgEJAgABLgAECgcJGAAGAMsfAA==.',
Go='Goblinlayer:BAAALgAECgYJEwAAAA==.Goldtoof:BAAALgAECgYJCQAAAA==.Goldtusk:BAAALgAECgYJDwAAAA==.Gooey:BAAALgADCggJDgAAAA==.Gostann:BAAALgAECgYJDAAAAA==.',
Gr='Grayparser:BAAALgADCgYJCQAAAA==.Gryphone:BAAALgADCgkJDQAAAA==.',
Gu='Gurinendo:BAAALgAECgEJAQAAAA==.Gustwin:BAAALgAECgQJBgAAAA==.',
['Gà']='Gàins:BAAALgADCgUJBQABLgAECgYJEwADAAAAAA==.',
Ha='Hakmud:BAAALgADCgUJBQAAAA==.',
He='Heftydin:BAAALgAECgMJCQAAAA==.Heftymists:BAAALgAECgUJBQAAAA==.Heftystomp:BAAALgADCgUJBQAAAA==.Heftyvoid:BAAALgADCgEJAQAAAA==.Hercyderc:BAAALgAECgEJAQABLgAECgkJJgAMANgjAA==.Hettokal:BAAALgADCgcJBwAAAA==.Heyitsjimbo:BAAALgADCgUJCQAAAA==.',
Ho='Holierhtanu:BAAALgADCgQJBwAAAA==.Holyhellion:BAAALgAECgUJCwAAAA==.Hondojoe:BAACLgAFFH8HAAIYAAMJPRgxCgDsAAAYAAMJPRgxCgDsAAAuAAQKfygAAxgACAnsIVALAJsCABgACAnsIVALAJsCABcAAgnUBhUwAFUAAAAA.Honeydrake:BAAALgADCgYJBgAAAA==.Hopewell:BAAALgAECgYJEwAAAA==.',
Hu='Huginn:BAAALgADCgEJAQAAAA==.Hugnsnuggle:BAAALgAECgYJEwABLgAECgYJEwADAAAAAA==.Huhu:BAABLgAECn8WAAITAAgJEhVnDwDCAQATAAgJEhVnDwDCAQAAAA==.Huma:BAAALgAECgYJEAAAAA==.Hundreg:BAAALgADCgQJBAAAAA==.',
Ib='Ibn:BAAALgAECgYJEgAAAA==.',
Ic='Icyhot:BAAALgADCgUJCAAAAA==.',
Id='Ideal:BAAALgADCgYJDAAAAA==.',
In='Infectus:BAAALgAECgkJBAAAAA==.Infiniity:BAAALgAECgMJCQAAAA==.',
Ir='Irielle:BAAALgADCggJGwAAAA==.',
Is='Ishanllin:BAAALgADCgUJBQAAAA==.',
Iv='Ivarurngamet:BAABLgAECn8XAAIMAAcJwhiqGgCVAQAMAAcJwhiqGgCVAQAAAA==.Ivylyn:BAAALgADCgYJDAAAAA==.',
Ix='Ixiyá:BAABLgAECn8ZAAIKAAcJ7iHIDQASAgAKAAcJ7iHIDQASAgAAAA==.Ixì:BAAALgAECgYJDwAAAA==.',
Ja='Jakeyprogue:BAAALgADCgEJAQABLgAFFAIJAwADAAAAAA==.Jakota:BAAALgADCggJDAAAAA==.Jakskeleton:BAAALgAECgUJDgAAAA==.Jarobus:BAAALgAECgYJDgAAAA==.Jay:BAAALgADCgEJAQAAAA==.Jayp:BAAALgAECgMJAwAAAA==.',
Jb='Jbernn:BAAALgAECgEJAQAAAA==.',
Je='Jeamica:BAAALgADCgUJCAAAAA==.',
Jo='Joemacho:BAAALgADCgcJCAABLgAFFAMJBwAYAD0YAA==.Joslyn:BAAALgAECgIJAgAAAA==.',
Ju='Judax:BAABLgAECn8kAAIaAAgJCBXXEACdAQAaAAgJCBXXEACdAQAAAA==.Justagirl:BAAALgAECgYJEwAAAA==.Justiceboyd:BAAALgADCgMJAwAAAA==.',
Ka='Kadooka:BAABLgAECn8ZAAIBAAcJehI/VQBpAQABAAcJehI/VQBpAQAAAA==.Kahlyn:BAAALgADCgYJBgAAAA==.Kajax:BAABLgAECn8qAAIRAAgJICNpAgCbAgARAAgJICNpAgCbAgAAAA==.Kaldaran:BAAALgAECgYJCgAAAA==.Karen:BAAALgADCgcJCgAAAA==.Karne:BAAALgADCgYJBgAAAA==.Kazarath:BAAALgADCgUJBQAAAA==.',
Ke='Keeganw:BAABLgAECn8WAAILAAUJMhvBEAAMAQALAAUJMhvBEAAMAQAAAA==.Keelay:BAABLgAECn8XAAIbAAYJ3xOOIABCAQAbAAYJ3xOOIABCAQAAAA==.',
Kh='Kheegorn:BAABLgAECn8WAAIIAAgJ2hRlTwDzAQAIAAgJ2hRlTwDzAQAAAA==.Khyla:BAAALgAECgEJAQAAAA==.',
Ki='Killua:BAAALgADCgYJBgABLgADCgcJCwADAAAAAA==.Kimiko:BAAALgADCgcJBwAAAA==.',
Kl='Klaw:BAAALgAECgQJBAABLgAECggJKgARACAjAA==.',
Ko='Koffcmorbius:BAAALgADCgYJDAAAAA==.Koriban:BAABLgAECn8UAAIVAAgJKQ+XVgAyAQAVAAgJKQ+XVgAyAQAAAA==.Korreban:BAAALgAECgYJBgABLgAECggJFAAVACkPAA==.',
Kr='Kraken:BAABLgAECn8YAAIGAAcJyx82BQCGAgAGAAcJyx82BQCGAgAAAA==.',
Ku='Kubb:BAAALgAECgYJEwAAAA==.Kunst:BAAALgADCgEJAQAAAA==.',
Kw='Kweh:BAABLgAECn8hAAIcAAgJOCIaBQDAAgAcAAgJOCIaBQDAAgAAAA==.',
['Kê']='Kêlsen:BAAALgAECgMJAwAAAA==.',
La='Lachupacabra:BAAALgADCgIJBAAAAA==.Larrissa:BAAALgAECgYJEwAAAA==.Larry:BAAALgAECgcJBwAAAA==.Laurlynn:BAAALgADCggJGQAAAA==.Lavina:BAAALgADCgUJBQAAAA==.',
Le='Lettuceprey:BAAALgAECgYJEgAAAA==.',
Li='Lies:BAAALgADCgkJCQAAAA==.Lilspazz:BAAALgADCgMJAwAAAA==.',
Lo='Lockatute:BAAALgAECgMJBQAAAA==.Lockdeath:BAAALgADCgQJBAAAAA==.Loxia:BAAALgAECgQJBgAAAA==.',
Lu='Lucille:BAAALgAECgcJEAAAAA==.Lucrotia:BAAALgADCgQJBAAAAA==.Luukmosh:BAAALgAECgUJCQAAAA==.',
Ma='Maavarra:BAAALgAECgYJEAAAAA==.Madilyons:BAAALgADCgIJAgAAAA==.Magicdance:BAABLgAECn8cAAMaAAgJNQi7TwAIAQAaAAcJ7Ai7TwAIAQAKAAgJIwvFLgAHAQAAAA==.Magolthel:BAAALgADCgYJCQAAAA==.Maimgame:BAABLgAECn8WAAIcAAgJchK+CwACAgAcAAgJchK+CwACAgAAAA==.Majicbob:BAAALgAECgYJBwAAAA==.Maki:BAAALgAECgYJCwAAAA==.Mansion:BAAALgADCgMJBAABLgAECgYJEgAMAO8dAA==.Marn:BAAALgADCgQJBAAAAA==.Marthran:BAAALgADCgIJAgAAAA==.Maxlin:BAAALgADCgUJBQAAAA==.',
Mc='Mctowlie:BAAALgAECgEJAQAAAA==.',
Me='Meldo:BAAALgADCggJDQAAAA==.Mellinessa:BAAALgAECgcJEwAAAA==.Mena:BAAALgADCgUJBgAAAA==.Merixa:BAAALgADCgEJAQAAAA==.',
Mi='Midou:BAAALgAECgMJAwABLgAECggJHAAaADUIAA==.Minthraxis:BAAALgADCgEJAQAAAA==.Misaun:BAAALgADCgcJDAAAAA==.Misericorde:BAACLgAFFH8HAAIdAAMJth28BgAsAQAdAAMJth28BgAsAQAuAAQKfygAAh0ACAkIJT0BAPkCAB0ACAkIJT0BAPkCAAAA.Misstreater:BAAALgAECgYJBgAAAA==.',
Mo='Momentomori:BAABLgAECn8dAAIFAAgJawjXNABXAQAFAAgJawjXNABXAQAAAA==.Monocerotis:BAAALgADCgcJBwAAAA==.Morishima:BAACLgAFFH8HAAIRAAMJzBG6DQAIAQARAAMJzBG6DQAIAQAuAAQKfyQAAhEACAl8IQEDAH8CABEACAl8IQEDAH8CAAAA.Morthis:BAAALgAECgYJEgAAAA==.',
Mu='Multipàss:BAAALgADCgMJAwAAAA==.',
My='Mydarling:BAAALgAECggJEQAAAA==.Myris:BAABLgAECn8cAAINAAcJXxk0WQDmAQANAAcJXxk0WQDmAQAAAA==.',
Na='Naturalchi:BAABLgAECn8XAAMeAAYJzyMBCQD/AQAeAAYJ6yIBCQD/AQAdAAQJVCEiMABnAQAAAA==.',
Ne='Nefilion:BAAALgAECgMJBAAAAA==.Nemas:BAABLgAECn8WAAISAAgJjBgHBQDuAQASAAgJjBgHBQDuAQAAAA==.Neverleft:BAAALgAECgUJCAAAAA==.Nezin:BAAALgAECgYJDQAAAA==.',
Ni='Nightrun:BAAALgADCgcJCwAAAA==.Nineadin:BAACLgAFFH8GAAIbAAMJoxIFEQDwAAAbAAMJoxIFEQDwAAAuAAQKfyIAAhsACAmBHVsHAGkCABsACAmBHVsHAGkCAAAA.Nirvanas:BAAALgAECgYJEQAAAA==.Niyoko:BAAALgADCgcJBwAAAA==.',
No='Nomik:BAABLgAECn8cAAMYAAYJ2g6JGwAqAQAYAAYJ2g6JGwAqAQAZAAQJmQZTSwCsAAAAAA==.Nonah:BAAALgADCgEJAgAAAA==.',
Nu='Nuke:BAAALgAECgQJDgAAAA==.Nullspace:BAAALgAECgcJDQAAAA==.',
Ny='Nyxe:BAAALgADCgkJCQAAAA==.',
['Ní']='Níght:BAABLgAECn8vAAICAAgJFRbCBgCKAQACAAgJFRbCBgCKAQAAAA==.',
Oa='Oaken:BAAALgADCgkJCQAAAA==.',
Oc='Occultivated:BAAALgAECgQJBgAAAA==.',
Om='Ommû:BAAALgAECgMJBQAAAA==.',
Op='Op:BAAALgAECgIJAgABLgAECgcJGAAGAMsfAA==.',
Pa='Pakeydk:BAAALgAFFAIJAwAAAA==.Pancakedealr:BAAALgAECgUJDQAAAA==.',
Pe='Peerow:BAAALgADCgMJAwAAAA==.Permelia:BAAALgADCgYJBgAAAA==.Peí:BAAALgAECgEJAQAAAA==.',
Ph='Phatjake:BAAALgADCgYJBgAAAA==.',
Pi='Pintobeans:BAABLgAECn8UAAIBAAgJ9AThMQBJAQABAAgJ9AThMQBJAQAAAA==.',
Pl='Plutonix:BAAALgAECgMJAwAAAA==.',
Pr='Preachêr:BAAALgADCgcJDAABLgAECgYJEwADAAAAAA==.',
Pu='Puuhceew:BAABLgAECn8XAAIYAAYJkA/wHAAdAQAYAAYJkA/wHAAdAQAAAA==.',
Qu='Quelaag:BAAALgADCgQJBAAAAA==.Quiescent:BAAALgAECgUJEwAAAA==.',
Ra='Ragingtides:BAAALgADCgEJAQAAAA==.Rainera:BAAALgAECgYJEgABLgAFFAQJDAAEAJcmAA==.Ramanas:BAAALgAECgUJCgAAAA==.Randomizwe:BAABLgAECn8iAAIIAAcJex5iGQDyAQAIAAcJex5iGQDyAQAAAA==.Rattles:BAAALgADCgcJCwAAAA==.Raynu:BAAALgAECgEJAwAAAA==.Raín:BAAALgAECggJDwAAAA==.',
Re='Relearning:BAAALgAECgYJDwAAAA==.Resurgencê:BAAALgAECgYJEwAAAA==.Retalltheway:BAAALgADCgEJAQAAAA==.',
Ri='Riggler:BAAALgAECgcJBwAAAA==.Riordan:BAAALgAECgQJDAAAAA==.Rivfader:BAAALgAECgMJBQAAAA==.',
Ro='Rohz:BAAALgADCgIJAgABLgAECgYJEgAMAO8dAA==.Rojeton:BAAALgADCgUJBwAAAA==.Rosenth:BAAALgADCggJDQAAAA==.Rotandroll:BAAALgAECgcJDQAAAA==.Rothema:BAAALgAECgUJCgAAAA==.',
Rw='Rwlmaster:BAAALgAECgYJEAAAAA==.',
Ry='Rynzia:BAACLgAFFH8HAAMfAAMJLAzWAwCcAAAfAAIJhgjWAwCcAAAgAAIJvgtaIgCVAAAuAAQKfygAAyAACAneIBUEAHwCACAACAneIBUEAHwCAB8ABwmkFOwWAIUBAAAA.',
Sa='Sadabacus:BAAALgAECgEJAgAAAA==.Sagittarian:BAAALgADCgUJBwAAAA==.Sandwiches:BAAALgAECgMJBQAAAA==.Santose:BAAALgADCgMJAwAAAA==.',
Sc='Scalyt:BAAALgADCgYJBgAAAA==.Scerra:BAAALgAECggJEQAAAA==.Scridderz:BAAALgAECgMJBgAAAA==.',
Se='Sendia:BAAALgADCgQJBAABLgAECgcJJAABAHQbAA==.Sephiros:BAAALgADCgIJAgAAAA==.Seru:BAAALgAECgMJBQAAAA==.Seta:BAABLgAECn8bAAIMAAgJ0BNaQwDmAQAMAAgJ0BNaQwDmAQAAAA==.Seviran:BAAALgADCgIJAwAAAA==.',
Sh='Shakeyjams:BAAALgADCgYJBgABLgAFFAIJAwADAAAAAA==.Shamarha:BAAALgAECgYJDAAAAA==.Sharriavolf:BAABLgAECn8vAAQFAAgJzSAEJgCXAQAFAAYJSB4EJgCXAQAGAAQJMyMMIABSAQAHAAEJAAB6IwBkAAAAAA==.Shato:BAAALgAECgMJAwAAAA==.Sheoth:BAAALgADCgQJBAAAAA==.Shortmedic:BAAALgADCggJCwAAAA==.',
Si='Sicarius:BAAALgADCgcJCgABLgADCgcJDAADAAAAAA==.Siggismund:BAAALgAECgcJDwAAAA==.Simichaelton:BAAALgAECgcJEQABLgAECggJHgAdAA0YAA==.',
Sk='Skrobifu:BAAALgADCgQJAwAAAA==.',
Sl='Slimselect:BAAALgADCgMJAwAAAA==.Slimt:BAAALgADCgMJAwAAAA==.Sloppyshids:BAAALgADCgYJBgAAAA==.',
So='Softbakedhoj:BAABLgAECn8YAAIIAAcJaRhaSQAGAgAIAAcJaRhaSQAGAgAAAA==.',
Sp='Spartaaxd:BAABLgAECn8YAAIWAAgJqhDuBABPAQAWAAgJqhDuBABPAQAAAA==.Spookems:BAAALgAECgIJAgABLgAECggJEAADAAAAAA==.Spycy:BAAALgAECgcJDAAAAA==.',
St='Stagerrind:BAAALgADCgQJBAAAAA==.Starfall:BAAALgAECgkJAgAAAA==.Steiner:BAABLgAECn8eAAIbAAgJogy+GACIAQAbAAgJogy+GACIAQAAAA==.Stinkyfrog:BAABLgAECn8TAAIIAAcJ+Bz2IwC1AQAIAAcJ+Bz2IwC1AQAAAA==.Stovetop:BAAALgAECgEJAQABLgAECgUJBgADAAAAAA==.Stubmcbean:BAAALgADCgEJAQABLgAECgYJEwADAAAAAA==.Stunted:BAAALgAECgMJAwAAAA==.',
Su='Sugarfrost:BAABLgAECn8fAAIVAAgJvAuKTwBCAQAVAAgJvAuKTwBCAQAAAA==.Suka:BAAALgADCggJEwAAAA==.Surok:BAAALgAECgYJDQAAAA==.',
Sw='Sweetleaf:BAAALgAECgUJCAAAAA==.Swiftleaf:BAAALgAECgMJBQAAAA==.',
Sy='Sylentcurse:BAAALgAECgYJBwABLgAECgYJDgADAAAAAA==.Sylentstorm:BAAALgAECgIJAgABLgAECgYJDgADAAAAAA==.Syleta:BAABLgAECn8kAAQBAAcJdBsJMADwAQABAAcJdBsJMADwAQAQAAYJCRM1RABEAQAPAAMJDA+1GwDRAAAAAA==.',
Ta='Tagalorc:BAAALgAECgYJEQAAAA==.Takamaki:BAAALgADCggJGAAAAA==.Tanksbacon:BAAALgAECgUJDwAAAA==.Taylith:BAAALgAECgUJBQAAAA==.',
Te='Teana:BAAALgAECgcJDQAAAA==.Tempestas:BAAALgADCgYJCgAAAA==.',
Th='Tharos:BAAALgAECgUJCgAAAA==.Thebrewco:BAAALgADCgMJAwABLgAECggJJAAOAJseAA==.Thelegendáry:BAABLgAECn8WAAIKAAYJIRZDSgBZAQAKAAYJIRZDSgBZAQABLgAFFAIJAwADAAAAAA==.Thetool:BAAALgAECgMJBAAAAA==.Thraine:BAAALgAECgEJAgAAAA==.',
Ti='Tinyshadowz:BAAALgAECgEJAQAAAA==.Tione:BAAALgAECgYJEgAAAA==.',
To='Tormented:BAAALgAECgMJAwAAAA==.Totembish:BAAALgAECggJDwAAAA==.Toto:BAAALgAECgkJAgAAAA==.',
Tr='Treebear:BAAALgADCgcJDQAAAA==.Trisstan:BAAALgAECgYJEwAAAA==.Trucknly:BAAALgADCgMJAwAAAA==.',
Tu='Tundarian:BAAALgAECggJDwAAAA==.',
Tw='Twigz:BAAALgADCgcJBgAAAA==.',
Ty='Tyronicals:BAABLgAECn8eAAMVAAcJWx+UIADqAQAVAAcJLRuUIADqAQAhAAUJHyAJBgDAAQAAAA==.Tyster:BAAALgAECggJEwAAAA==.',
Uk='Ukyo:BAAALgADCgUJBgAAAA==.',
Ul='Ullidon:BAAALgAECgEJAQAAAA==.',
Um='Umbrã:BAAALgADCgEJAQAAAA==.',
Un='Unavoidably:BAAALgADCgIJAgAAAA==.Undol:BAAALgADCggJDQABLgAECgYJEwADAAAAAA==.',
Ux='Uxe:BAAALgAFFAEJAQABLgAECggJIAAeAMsZAA==.',
Uz='Uzu:BAABLgAECn8gAAIeAAgJyxk1IwDpAQAeAAgJyxk1IwDpAQAAAA==.',
Va='Valios:BAAALgADCgcJBwAAAA==.Vamp:BAABLgAECn8WAAIKAAcJUBjtLwDIAQAKAAcJUBjtLwDIAQAAAA==.Vandaldor:BAAALgAECgQJBAAAAA==.Vasalrius:BAAALgADCgIJAgAAAA==.Vasilli:BAAALgADCgYJDwAAAA==.',
Ve='Vedrix:BAAALgAECgcJBgAAAA==.Vellora:BAAALgADCgUJBQAAAA==.Veloth:BAACLgAFFH8HAAIVAAMJrQ9xNQD7AAAVAAMJrQ9xNQD7AAAuAAQKfyQAAhUACAlhINsPAF4CABUACAlhINsPAF4CAAAA.',
Vi='Vireaux:BAAALgADCgEJAQAAAA==.Viviro:BAAALgADCgcJDQAAAA==.',
Vl='Vll:BAABLgAECn8aAAMBAAgJjRiZLQD8AQABAAgJjRiZLQD8AQAPAAIJewTmKgBVAAAAAA==.',
Wa='Wanghaf:BAAALgAECgYJDQAAAA==.Warhorne:BAAALgAECgEJAQABLgAECgYJDwADAAAAAA==.Warthog:BAAALgADCgUJBQAAAA==.Waterbender:BAABLgAECn8VAAIKAAgJeRtrCQBTAgAKAAgJeRtrCQBTAgAAAA==.',
We='Weechuup:BAAALgADCggJEAAAAA==.Weleindon:BAAALgADCgMJAwAAAA==.',
Wi='Wiggle:BAAALgADCgMJAwAAAA==.Willmar:BAAALgAECgYJDwAAAA==.Window:BAAALgADCgUJBQABLgAECgYJEgAMAO8dAA==.',
Wo='Wolf:BAABLgAECn8ZAAICAAcJAxj+CwDMAQACAAcJAxj+CwDMAQAAAA==.Wolfton:BAAALgADCgQJBAAAAA==.',
Wy='Wylian:BAAALgAECgIJAgAAAA==.',
Xa='Xaeri:BAAALgADCgMJBAAAAA==.Xameris:BAAALgADCgEJAQAAAA==.Xandercruise:BAABLgAECn8UAAMBAAgJIhvAHQBTAgABAAgJIhvAHQBTAgAQAAMJrAJDdABtAAAAAA==.Xanæ:BAAALgADCgQJBwAAAA==.',
Xe='Xelgoth:BAAALgADCgcJBgAAAA==.Xelphie:BAAALgADCgUJBQAAAA==.',
Xu='Xuchilbara:BAAALgAECgYJDwAAAA==.',
Xy='Xyro:BAAALgAECgUJBQAAAA==.',
Ya='Yamato:BAAALgAECgEJAgAAAA==.',
Za='Zaledron:BAABLgAECn8WAAINAAYJuB6QNgBfAQANAAYJuB6QNgBfAQAAAA==.Zapnasty:BAAALgADCgcJBgAAAA==.',
Ze='Zenno:BAAALgAECgYJEAAAAA==.Zevorcia:BAAALgAECgMJAwAAAA==.',
Zh='Zhades:BAACLgAFFH8FAAINAAMJExpCMwD6AAANAAMJExpCMwD6AAAuAAQKfykAAg0ACAnPJCEEAOsCAA0ACAnPJCEEAOsCAAAA.Zhandaria:BAAALgAECgQJBwAAAA==.Zhort:BAAALgAECgIJAwAAAA==.Zhulodok:BAAALgADCgMJAwAAAA==.',
Zi='Zioki:BAAALgADCgcJCwABLgADCgcJDAADAAAAAA==.',
Zo='Zodgul:BAAALgAECgQJBAAAAA==.',
Zp='Zpersephone:BAAALgAECgYJCAABLgAFFAMJBQANABMaAA==.',
Zu='Zultan:BAABLgAECn8cAAMFAAgJNxJCHQDFAQAFAAcJNxJCHQDFAQAGAAEJAAC0KgAAAAAAAA==.Zurrik:BAABLgAECn8kAAIUAAgJsBBoEACPAQAUAAgJsBBoEACPAQAAAA==.',
['Çõ']='Çõîñflïp:BAAALgADCgcJHAAAAA==.',
['Ðr']='Ðream:BAACLgAFFH8FAAIeAAMJBBPSEgDjAAAeAAMJBBPSEgDjAAAuAAQKfycAAx4ACAmEHzwJAPUCAB4ACAmEHzwJAPUCAB0AAwkbGVxBAEIAAAAA.',
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
