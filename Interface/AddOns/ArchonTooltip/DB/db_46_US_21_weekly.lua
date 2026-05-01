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

local lookup = {'Paladin-Protection','Warrior-Fury','Warrior-Arms','Paladin-Retribution','Paladin-Holy','Evoker-Augmentation','Mage-Frost','DeathKnight-Unholy','Priest-Holy','Monk-Mistweaver','DemonHunter-Devourer','Druid-Guardian','Unknown-Unknown','Druid-Restoration','Monk-Windwalker','Priest-Discipline','Hunter-BeastMastery','Shaman-Elemental','Warrior-Protection','Warlock-Destruction','Monk-Brewmaster','DemonHunter-Havoc','DeathKnight-Blood','Shaman-Restoration','Druid-Balance','Hunter-Marksmanship','Warlock-Demonology','Evoker-Preservation','Rogue-Outlaw','Priest-Shadow','Rogue-Subtlety','Druid-Feral','Evoker-Devastation','Warlock-Affliction','Rogue-Assassination',}
local provider = {region='US',realm='Arygos',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aava:BAAALgADCgEJAQAAAA==.',
Ad='Adivion:BAAALgAECgcJCAAAAA==.Adrenelian:BAAALgAECgcJDQAAAA==.',
Ah='Ahgro:BAAALgAECgMJAwAAAA==.',
Ak='Akroma:BAABLgAECn8VAAIBAAYJsRueEQCuAQABAAYJsRueEQCuAQAAAA==.',
Al='Alecwar:BAABLgAECn8oAAICAAgJSxwRBwA/AgACAAgJSxwRBwA/AgAAAA==.Allyon:BAAALgADCgMJAwAAAA==.Altezio:BAABLgAECn8fAAIDAAkJAhzrAADaAgADAAkJAhzrAADaAgAAAA==.',
Am='Amorial:BAAALgAECgMJAwAAAA==.',
An='Andransonis:BAAALgADCgUJBQAAAA==.Ankarna:BAAALgAECgEJAQAAAA==.Annegwish:BAABLgAECn8kAAMEAAkJiAo2KACiAQAEAAkJiAo2KACiAQAFAAcJpwnuRABkAQAAAA==.Anonymous:BAAALgAECgQJBAAAAA==.Antashaman:BAAALgAECgUJCQAAAA==.',
Ap='Apokalypsis:BAAALgADCgUJCgAAAA==.',
Ar='Archodreki:BAABLgAECn8cAAIGAAgJIBFcJADkAAAGAAgJIBFcJADkAAAAAA==.Ardithan:BAABLgAECn8eAAIHAAkJtiDgJADfAgAHAAkJtiDgJADfAgAAAA==.Argah:BAAALgADCgMJAwAAAA==.Arilm:BAAALgADCgMJAwAAAA==.Arthuur:BAABLgAECn8hAAIIAAgJ1hvUOwBIAgAIAAgJ1hvUOwBIAgAAAA==.Arynthyan:BAABLgAECn8ZAAIJAAkJDxnIEABeAgAJAAkJDxnIEABeAgAAAA==.Arystrasza:BAAALgADCgUJBQABLgAECgkJHwAKAJAgAA==.Aryzhuque:BAABLgAECn8fAAIKAAkJkCA3BAArAwAKAAkJkCA3BAArAwAAAA==.',
As='Ashana:BAAALgADCgYJBgAAAA==.Ashmandious:BAAALgAECgcJCQAAAA==.Asparavoid:BAABLgAECn8kAAILAAkJ1x/HCABDAwALAAkJ1x/HCABDAwAAAA==.Aspyn:BAAALgADCgEJAgAAAA==.Assandros:BAABLgAECn8fAAIMAAkJ4SRPAADEAwAMAAkJ4SRPAADEAwAAAA==.',
At='Ataraxia:BAAALgADCgEJAQAAAA==.Athleta:BAEALgAECggJCAABLgAFFAYJFQAKAHIFAA==.',
Au='Aurilian:BAAALgADCgQJBAAAAA==.',
Av='Average:BAAALgADCggJGQAAAA==.',
Ay='Ayku:BAAALgAECgEJAQAAAA==.',
Az='Azrox:BAAALgADCgUJBQAAAA==.Azurien:BAAALgAECgMJAwAAAA==.',
Ba='Baboo:BAAALgAECgEJAQAAAA==.Bad:BAAALgAECgIJAQAAAA==.Baldbud:BAAALgADCgQJBAABLgAECgcJEAANAAAAAA==.Balgrim:BAAALgADCgQJBwAAAA==.Banthum:BAABLgAECn8fAAIOAAgJYBODFgDPAQAOAAgJYBODFgDPAQAAAA==.',
Be='Bearbayt:BAAALgAECgUJBQAAAA==.Bearlough:BAAALgAECgUJCQAAAA==.Beerhelmet:BAABLgAECn8ZAAMPAAYJkRY6KwCEAQAPAAYJkRY6KwCEAQAKAAYJtQOrSAC2AAAAAA==.Bertarious:BAAALgADCgQJBAAAAA==.Beryl:BAABLgAECn8XAAMQAAYJ/Q0FGwAKAQAJAAYJAQ29PwA6AQAQAAYJPAcFGwAKAQAAAA==.',
Bi='Biggyword:BAABLgAECn8dAAMQAAgJZiEHAgABAwAQAAgJUiEHAgABAwAJAAMJEyEjSgAQAQAAAA==.',
Bl='Bleddyn:BAAALgADCgYJBgAAAA==.Blorbusdorp:BAAALgAECgYJCwAAAA==.',
Bo='Bobsgirl:BAABLgAECn8UAAIRAAkJHQ+sIwAwAgARAAkJHQ+sIwAwAgAAAA==.Bolord:BAAALgADCgEJAQAAAA==.Boodrios:BAABLgAECn8ZAAISAAgJWghRGgBBAQASAAgJWghRGgBBAQAAAA==.',
Br='Braleanna:BAAALgAECgEJAgAAAA==.Brewmaster:BAAALgADCgIJAgABLgAECggJGgAQAIwfAA==.Bruke:BAABLgAECn8VAAITAAkJLxymCACVAgATAAkJLxymCACVAgAAAA==.',
Bu='Buffsyou:BAAALgAECgYJEAAAAA==.Bugge:BAABLgAECn8VAAIOAAcJbBgZEwDwAQAOAAcJbBgZEwDwAQAAAA==.Bulldozzer:BAAALgADCgYJBwAAAA==.Bus:BAABLgAFFH8NAAIMAAcJfiE7AAAaAgAMAAcJfiE7AAAaAgAAAA==.',
Ca='Catastrophe:BAABLgAECn8aAAIUAAcJxwz7BwAwAQAUAAcJxwz7BwAwAQAAAA==.',
Cb='Cbat:BAABLgAECn8eAAIMAAgJwB2ZAgA4AgAMAAgJwB2ZAgA4AgAAAA==.',
Cd='Cdicepalta:BAAALgAECgEJAgAAAA==.',
Ce='Celes:BAAALgAECgUJCQAAAA==.',
Ch='Chapulín:BAAALgAECggJCQABLgAECggJFgAVAJMeAA==.',
Ci='Cindér:BAAALgADCgMJAwAAAA==.Cinimist:BAAALgAECgYJCwAAAA==.',
Co='Coinlock:BAAALgAECgYJDAAAAA==.Coinslot:BAAALgAECgMJBAABLgAECgYJDAANAAAAAA==.Compact:BAAALgADCgYJBgABLgAECggJGgAQAIwfAA==.Concubine:BAABLgAECn8aAAIWAAcJSgwFLABoAQAWAAcJSgwFLABoAQAAAA==.Confettii:BAAALgAECgMJAwABLgAECgYJCgANAAAAAA==.Conän:BAAALgADCgMJAwAAAA==.Cordie:BAAALgADCgcJDQAAAA==.Cowdrogo:BAAALgAECgEJAQAAAA==.',
Cr='Crippled:BAAALgADCgEJAQAAAA==.Crosis:BAAALgADCgcJBwAAAA==.Cryhard:BAAALgAECgYJAQAAAA==.',
Cu='Cuchulainn:BAAALgADCgIJAgAAAA==.',
Da='Dagal:BAAALgAECgMJAwABLgAECgYJDwANAAAAAA==.Dalaran:BAABLgAECn8cAAIPAAcJTRoRDAC2AQAPAAcJTRoRDAC2AQAAAA==.Daliron:BAAALgAECgEJAQAAAA==.Dalus:BAAALgADCgIJAgAAAA==.Danea:BAAALgAECgUJCwAAAA==.Dankzìlla:BAABLgAECn8ZAAIXAAgJ1hs3CwBiAgAXAAgJ1hs3CwBiAgAAAA==.Danmonk:BAAALgAECgEJAQAAAA==.Darach:BAAALgAECgEJAQAAAA==.Dawny:BAABLgAECn8jAAMYAAkJLxmBIQAWAgAYAAkJLxmBIQAWAgASAAUJ4BgAQQBFAQAAAA==.',
De='Dealain:BAAALgADCggJEAAAAA==.Deathtrash:BAAALgADCgQJBAAAAA==.Decaran:BAABLgAECn8cAAIHAAkJ0RlbLADBAgAHAAkJ0RlbLADBAgAAAA==.Dectodraco:BAAALgADCgIJAgAAAA==.Dedpool:BAAALgAECgYJDgAAAA==.Delinara:BAAALgAECgUJCAAAAA==.Dethndk:BAAALgAECgYJBgAAAA==.',
Do='Doorjob:BAABLgAECn8fAAIWAAkJCh+dCADZAgAWAAkJCh+dCADZAgAAAA==.',
Dr='Drakemage:BAAALgAECgkJBAAAAA==.Dreamily:BAABLgAECn8ZAAIZAAkJYBG1HQASAgAZAAkJYBG1HQASAgAAAA==.Driamn:BAAALgADCggJEAAAAA==.',
Dy='Dydy:BAAALgAECgEJAQAAAA==.',
Ea='Eame:BAABLgAECn8XAAICAAgJBgwpGgBeAQACAAgJBgwpGgBeAQABLgAECggJHwAHADYUAA==.',
Eh='Ehnder:BAAALgADCgEJAQAAAA==.',
El='Elandron:BAAALgAECgIJAgAAAA==.Elenyia:BAABLgAECn8VAAIFAAYJehnZEwC4AQAFAAYJehnZEwC4AQAAAA==.Elfredo:BAAALgADCgEJAQAAAA==.Elia:BAABLgAECn8fAAMRAAkJlR24CwDkAgARAAkJlR24CwDkAgAaAAYJYgfhUwD7AAAAAA==.Elisandre:BAAALgAECgUJBQAAAA==.Elmo:BAABLgAECn8nAAIIAAkJFiG8CQCFAgAIAAkJFiG8CQCFAgAAAA==.Elzä:BAABLgAECn8cAAIRAAgJMhueDQAwAgARAAgJMhueDQAwAgAAAA==.',
Em='Emaria:BAAALgAECgQJBQAAAA==.',
En='Ennead:BAABLgAECn8ZAAMUAAgJ1AbEDwC1AAAbAAgJ8gWmUwD2AAAUAAUJXwjEDwC1AAAAAA==.Entranced:BAABLgAECn8eAAIWAAcJhiPOAwBUAgAWAAcJhiPOAwBUAgAAAA==.Entropius:BAABLgAECn8eAAIIAAgJ4xZOHADeAQAIAAgJ4hZOHADeAQAAAA==.',
Er='Eranica:BAAALgADCgEJAQAAAA==.Ereinion:BAABLgAECn8bAAICAAcJaRWGNQDSAQACAAcJaRWGNQDSAQAAAA==.Erkromerr:BAAALgAECgEJAgAAAA==.',
Ey='Eyb:BAAALgADCgcJDQAAAA==.',
Ez='Ezayle:BAABLgAECn8YAAIEAAkJsQjMYwC6AQAEAAkJsQjMYwC6AQAAAA==.Ezsolator:BAAALgAECgQJBAAAAA==.',
['Eï']='Eïs:BAABLgAECn8kAAIcAAgJ1Q+9CACZAQAcAAgJ1Q+9CACZAQAAAA==.',
Fe='Fearsmage:BAAALgADCgMJAwAAAA==.Fenris:BAAALgADCgYJCAAAAA==.',
Fo='Fonzie:BAABLgAECn8eAAISAAkJGhWmGwA1AgASAAkJGhWmGwA1AgAAAA==.Foregotten:BAABLgAECn8eAAIZAAgJaRoJFQBpAgAZAAgJaRoJFQBpAgAAAA==.',
Fr='Fragile:BAAALgAFFAEJAQAAAA==.Freezee:BAAALgADCgYJCAAAAA==.Frostietute:BAAALgAECgYJEAABLgAECgcJBwANAAAAAA==.',
Fu='Fudd:BAAALgADCgQJBwAAAA==.',
Ga='Galen:BAAALgADCgEJAgAAAA==.Galsin:BAAALgAECgYJDwAAAA==.Gamboa:BAAALgAECgYJCwAAAA==.Gandulfgray:BAAALgADCgMJAwAAAA==.Gauche:BAABLgAECn8cAAMPAAgJRB6pBQA8AgAPAAgJRB6pBQA8AgAKAAYJTRogIAD/AAAAAA==.Gazreiale:BAABLgAECn8bAAIdAAgJNRLQAwD2AQAdAAgJNRLQAwD2AQAAAA==.',
Gi='Giddie:BAABLgAECn8mAAMYAAgJUBQCHgBzAQAYAAgJUBQCHgBzAQASAAYJnQ7UVADyAAAAAA==.Giddygos:BAAALgADCgIJAgAAAA==.Girthquake:BAAALgAECgMJBAAAAA==.',
Go='Goldylocks:BAAALgADCgcJBwAAAA==.',
Gr='Grass:BAAALgAECgYJDwAAAA==.Grimtree:BAAALgAECgIJAgAAAA==.Gromnash:BAAALgADCgcJDQABLgAFFAUJEQARAH4fAA==.',
Gu='Guldanica:BAAALgADCggJFgAAAA==.',
Gw='Gwaine:BAAALgAECgYJEAAAAA==.Gwyndolín:BAAALgAFFAEJAQAAAA==.',
Gy='Gyaatso:BAAALgADCgEJAQAAAA==.',
He='Helgrund:BAAALgADCgcJBwAAAA==.Hellfyrê:BAAALgADCgkJGAAAAA==.Heritikyl:BAABLgAECn8jAAIOAAgJ1SJbCQD8AgAOAAgJ1SJbCQD8AgAAAA==.Heritikyldin:BAAALgAECgQJBAAAAA==.',
Hi='Hibou:BAAALgADCgEJAQAAAA==.Hiim:BAABLgAECn8UAAIZAAgJvRC2KAC5AQAZAAgJvRC2KAC5AQAAAA==.',
Ho='Holycast:BAAALgAECgQJBAAAAA==.Holyhero:BAABLgAECn8eAAMeAAkJnB7yCQDkAgAeAAkJnB7yCQDkAgAJAAEJcQd/gQAwAAAAAA==.',
Hu='Huntréss:BAAALgADCgUJBQAAAA==.',
Ic='Iceehot:BAAALgAECgEJAQAAAA==.',
Ig='Ignasio:BAAALgADCgYJBgAAAA==.',
Im='Imposturr:BAAALgADCgkJCwAAAA==.',
In='Insanitii:BAAALgADCgMJBwABLgAECgYJCgANAAAAAA==.',
Ip='Iportyou:BAAALgAECgYJEAAAAA==.',
Iv='Ivysore:BAAALgAECgUJBwAAAA==.',
Ja='Jabjo:BAABLgAECn8fAAIFAAcJnB9GDgD3AQAFAAcJnB9GDgD3AQAAAA==.Jaira:BAAALgAECgcJDQAAAA==.Janorune:BAAALgADCgEJAQAAAA==.Jastinasta:BAAALgADCgMJAwAAAA==.',
Je='Jeudeu:BAAALgADCgYJCwAAAA==.',
Ka='Kabira:BAAALgAECgEJAQAAAA==.Kaimed:BAAALgAECgEJAwAAAA==.Katalia:BAAALgAECgEJAQABLgAECgYJFQARAAcWAA==.Katyparry:BAAALgAECgIJAgAAAA==.',
Ke='Keljeon:BAAALgAECgEJAQAAAA==.',
Ki='Kigorr:BAAALgAECgMJAwAAAA==.Kinnick:BAAALgAECgYJDgAAAA==.Kinoloy:BAAALgADCgEJAQAAAA==.',
Ko='Konidus:BAAALgADCgMJAwAAAA==.Korna:BAAALgAECgEJAQAAAA==.',
Kr='Kronosdh:BAAALgADCgQJBAABLgAECgYJDAANAAAAAA==.Kronosmonk:BAAALgAECgYJDAAAAA==.Kronospaly:BAAALgAECgUJDwABLgAECgYJDAANAAAAAA==.Kronoswarr:BAAALgAECgQJBwABLgAECgYJDAANAAAAAA==.',
Ku='Kunaee:BAAALgAECgEJAgAAAA==.Kuzcó:BAAALgAECgYJCgAAAA==.Kuzume:BAAALgADCgcJCAABLgAECgYJFQARAAcWAA==.',
Ky='Kyrius:BAABLgAECn8bAAIYAAgJgBalDQAUAgAYAAgJgBalDQAUAgAAAA==.',
La='Lausia:BAABLgAECn8fAAIHAAgJNhS5JQDQAQAHAAgJNhS5JQDQAQAAAA==.',
Ld='Ldyrose:BAAALgAECgMJBAAAAA==.',
Le='Legomaaggro:BAAALgAECgYJEgAAAA==.Lewtiefroopz:BAABLgAECn8ZAAIRAAcJxRpOGADQAQARAAcJxRpOGADQAQAAAA==.',
Li='Lilblade:BAAALgADCggJDAAAAA==.',
Lo='Logana:BAAALgAECgYJBgAAAA==.Loxiteria:BAABLgAECn8cAAIfAAkJlRHzEwB2AgAfAAkJlRHzEwB2AgAAAA==.',
Lu='Luciang:BAAALgADCgQJBAAAAA==.Lunarkitsune:BAABLgAECn8UAAIRAAYJwATdTwDdAAARAAYJwATdTwDdAAAAAA==.Lusande:BAAALgADCgQJBAAAAA==.',
Ly='Lyzardwyzard:BAAALgADCgYJCQAAAA==.',
['Lì']='Lìlìth:BAABLgAECn8VAAILAAcJIBlXJgBQAQALAAcJIBlXJgBQAQAAAA==.',
Ma='Maantra:BAAALgADCgUJBgAAAA==.Magiclmao:BAAALgAECgMJBAAAAA==.Magnificò:BAABLgAECn8fAAIXAAgJ+wgyEwDuAAAXAAgJ+wgyEwDuAAAAAA==.Makani:BAABLgAECn8VAAIMAAYJIQg+HwCmAAAMAAYJIQg+HwCmAAAAAA==.Malarix:BAAALgAECgMJAwAAAA==.Malory:BAABLgAECn8iAAITAAkJsyJEAwAnAwATAAkJsyJEAwAnAwAAAA==.Malzahär:BAACLgAFFH8PAAMUAAQJwxs4AQBnAQAUAAQJwxs4AQBnAQAbAAEJSBZiWABVAAAuAAQKfxsAAxQACAl8JNYDAKwCABQABwlSJNYDAKwCABsABQkqHj6LAEMBAAAA.',
Me='Messi:BAACLgAFFH8JAAIYAAMJVhH7GQDBAAAYAAMJVhH7GQDBAAAuAAQKfzYAAhgACQl6H00DAEUDABgACQl6H00DAEUDAAAA.',
Mi='Mielk:BAAALgADCgEJAQAAAA==.Minara:BAAALgAECgEJAgAAAA==.Miniraven:BAAALgADCgMJBwAAAA==.Minniedonut:BAAALgAECgEJAQAAAA==.',
Mu='Muffintop:BAABLgAECn8WAAIIAAgJCxyKHADcAQAIAAgJCxyKHADcAQAAAA==.Muki:BAABLgAECn8ZAAIPAAcJEgxeFwAuAQAPAAcJEgxeFwAuAQAAAA==.',
My='Mystikal:BAAALgADCgYJBgABLgAECgcJIwAXAKAXAA==.Mythrondrir:BAAALgADCgYJBgAAAA==.Mythälus:BAAALgAECgYJBgAAAA==.',
Na='Nashumaya:BAAALgAECgYJEQAAAA==.Nathansbb:BAABLgAECn8pAAIEAAgJkyZkAgALAwAEAAgJkyZkAgALAwAAAA==.',
Ne='Neoamergin:BAABLgAECn8YAAMOAAcJexEoSwB2AQAOAAcJexEoSwB2AQAgAAYJXAupGAA4AQABLgAFFAIJBQAbADQTAA==.',
Ni='Nielic:BAAALgAECgYJCQAAAA==.Nimbus:BAACLgAFFH8NAAIGAAMJmBKWFwDsAAAGAAMJmBKWFwDsAAAuAAQKfyUAAwYABwmDIhQGAEECAAYABwmDIhQGAEECACEAAgnKESw2AGQAAAEuAAUUBgkRAAYAoRcA.Nitrin:BAAALgADCgYJBgAAAA==.',
No='Norrahh:BAAALgAECgEJAgAAAA==.Noteeth:BAAALgAECgcJEAAAAA==.Nozzle:BAAALgAECgEJAQAAAA==.',
Ny='Nyclon:BAAALgAECgUJBQAAAA==.Nyru:BAAALgADCgYJCgAAAA==.',
Or='Ori:BAAALgAECgYJAgAAAA==.Oriimis:BAAALgAECgYJDgAAAA==.Orion:BAABLgAECn8jAAIHAAcJJwgmVgAzAQAHAAcJJwgmVgAzAQAAAA==.',
Pa='Palanar:BAAALgADCgYJBgAAAA==.',
Pe='Penelopè:BAABLgAECn8WAAIVAAgJkx4CEwB6AgAVAAgJkx4CEwB6AgAAAA==.Penelópe:BAAALgADCgcJBwABLgAECggJFgAVAJMeAA==.Penný:BAABLgAECn8kAAITAAgJoBdeCACwAQATAAgJoBdeCACwAQABLgAECggJFgAVAJMeAA==.Peondashaman:BAAALgAECgcJDAAAAA==.Pepino:BAAALgAECgYJDQAAAA==.',
Pf='Pflanlock:BAAALgAECgEJAQAAAA==.',
Ph='Phinx:BAABLgAECn8eAAIIAAkJ+AjbYQDOAQAIAAkJ+AjbYQDOAQAAAA==.Phocheux:BAAALgAECgYJCwAAAA==.Phulgoth:BAAALgAECgQJBAAAAA==.',
Pi='Picklericks:BAAALgADCgMJBQAAAA==.Pierogi:BAABLgAECn8XAAISAAYJmR73EwB5AQASAAYJmR73EwB5AQAAAA==.',
Po='Pockit:BAAALgADCgcJCQAAAA==.Poetrii:BAAALgAECgYJCgAAAA==.Pomchow:BAAALgADCgQJBAAAAA==.Pomickyal:BAABLgAECn8fAAIbAAgJfAnuMgBgAQAbAAgJfAnuMgBgAQAAAA==.Pomymoth:BAAALgADCgYJBgAAAA==.Ponn:BAABLgAECn8aAAIQAAgJjB+MDwBFAgAQAAgJjB+MDwBFAgAAAA==.Poonswatter:BAAALgAECgYJEAAAAA==.Portails:BAAALgADCgMJAwAAAA==.',
Ps='Psychstorm:BAAALgAECgIJBQAAAA==.',
Qu='Quantumleaf:BAAALgADCgcJBwAAAA==.Quendeia:BAACLgAFFH8HAAIKAAYJcBCgBwBtAQAKAAYJcBCgBwBtAQAuAAQKfyAABAoACAmKHxkTADQCAAoABwlAIxkTADQCABUABgkgA2RfAMQAAA8AAQl0BFSGACoAAAAA.',
Ra='Raeline:BAAALgADCgcJDgABLgADCgcJGgANAAAAAA==.Ragnärok:BAABLgAECn8YAAMYAAkJRBBdNACyAQAYAAkJRBBdNACyAQASAAQJ8RRCWADkAAAAAA==.Rats:BAAALgADCgcJBwAAAA==.',
Re='Recursion:BAABLgAECn8dAAQUAAgJNg9KDQDRAAAUAAcJCRBKDQDRAAAbAAQJWwgP0wC0AAAiAAQJ2w4dGgCnAAAAAA==.Reverii:BAAALgAECgIJAgABLgAECgYJCgANAAAAAA==.Rexisias:BAACLgAFFH8FAAIRAAMJwRz7FwAGAQARAAMJwRz7FwAGAQAuAAQKfycAAhEACAmzIoUIAHACABEACAmzIoUIAHACAAAA.Reígn:BAABLgAECn8jAAIXAAcJoBf5BwCbAQAXAAcJoBf5BwCbAQAAAA==.',
Ri='Riaglais:BAAALgAECgEJAQAAAA==.Rinahfire:BAAALgAECgkJEQAAAA==.',
Rj='Rj:BAABLgAECn8VAAIIAAYJRBeiPgBCAQAIAAYJRBeiPgBCAQAAAA==.',
Ro='Rocky:BAAALgAECgQJBAABLgAECgYJGQAPAJEWAA==.Roomfourdy:BAAALgADCgEJAQAAAA==.Roughbbq:BAAALgAECgYJDAABLgAECgYJDgANAAAAAA==.Roundtwo:BAAALgADCgkJEgAAAA==.Roxi:BAAALgAECgYJCwAAAA==.',
Rt='Rtpopham:BAAALgAECgQJBAAAAA==.',
Sa='Saedri:BAAALgADCgEJAQAAAA==.Saikus:BAAALgAECgUJCQAAAA==.Saloman:BAAALgADCgMJBQABLgAECgYJDAANAAAAAA==.Sanguinus:BAAALgADCgkJCQAAAA==.Saphrin:BAABLgAECn8ZAAIWAAYJhRZKEAA4AQAWAAYJhRZKEAA4AQAAAA==.Sarapho:BAABLgAECn8VAAIRAAYJBxbZVwBhAQARAAYJBxbZVwBhAQAAAA==.Satoru:BAAALgADCgMJAwAAAA==.',
Sc='Scubasteve:BAAALgADCgcJCQAAAA==.Scurus:BAAALgAECgYJDAAAAA==.',
Se='Selynis:BAAALgADCgUJBQAAAA==.Selynne:BAABLgAECn8fAAIEAAkJBBs4GwDGAgAEAAkJBBs4GwDGAgAAAA==.Servingcvnt:BAAALgADCgYJDAAAAA==.',
Sh='Shadowfern:BAAALgADCgEJAgABLgAECgYJFQARAAcWAA==.Shadows:BAAALgAECgIJAgAAAA==.Shamanizeds:BAAALgAECgMJAwAAAA==.Shammeltoe:BAABLgAECn8UAAIYAAYJTRL2IgBPAQAYAAYJTRL2IgBPAQAAAA==.Sheezee:BAAALgAECgEJAQAAAA==.Shenn:BAAALgADCgkJEgAAAA==.Shotgirl:BAAALgADCgEJAQAAAA==.',
Si='Siello:BAAALgAECgQJBwAAAA==.Sillynda:BAAALgAECgIJAgAAAA==.Silversnipe:BAAALgAECgYJBgAAAA==.Sindorei:BAABLgAECn8bAAIRAAgJdgrDJwB5AQARAAgJdgrDJwB5AQAAAA==.',
Sj='Sj:BAABLgAECn8XAAIFAAcJfyFPEQCIAgAFAAcJfyFPEQCIAgABLgAFFAcJEAAHAMsiAA==.',
Sk='Skye:BAAALgADCgkJEQABLgAECggJHgAZAGkaAA==.',
Sl='Slagathore:BAABLgAECn8fAAIbAAgJiAsvKwCAAQAbAAgJiAsvKwCAAQAAAA==.Slagathorne:BAAALgADCgYJBgABLgAECggJHwAbAIgLAA==.Slegolas:BAABLgAECn8iAAMaAAkJqCMlCAAaAwAaAAgJ0CMlCAAaAwARAAQJmCH+WQC8AAAAAA==.Slicindomes:BAAALgADCgIJAgAAAA==.Slizepal:BAAALgADCgQJBAAAAA==.',
Sm='Smashe:BAAALgAECgQJBQAAAA==.',
So='Soggy:BAAALgADCgMJAwAAAA==.Somers:BAAALgAECgYJEQAAAA==.',
Sp='Spellbind:BAAALgAECgYJEAAAAA==.Spudnasty:BAAALgADCgYJBgAAAA==.',
St='Starstorms:BAABLgAECn8aAAIOAAgJ4A8YIQB4AQAOAAgJ4A8YIQB4AQAAAA==.',
Su='Summatime:BAABLgAECn8WAAISAAgJdRY9NACHAQASAAgJdRY9NACHAQAAAA==.',
Sw='Swiftiez:BAAALgADCgIJAgAAAA==.',
Sy='Syara:BAAALgAECggJCAAAAA==.',
['Sö']='Sölair:BAAALgAECgYJBwAAAA==.',
Ta='Taie:BAAALgAECgYJCgAAAA==.',
Te='Terkerjobs:BAAALgADCgEJAQAAAA==.Teshala:BAAALgAECgUJCwAAAA==.Tetanei:BAAALgAECgUJBgAAAA==.',
Th='Thalandra:BAAALgAECgUJCgAAAA==.Theory:BAAALgAECggJEQAAAA==.Therapii:BAAALgAECgUJCwABLgAECgYJCgANAAAAAA==.Thoraden:BAAALgADCgEJAQAAAA==.Thorgrimal:BAAALgAECgIJAgAAAA==.Thorizan:BAAALgADCgEJAQAAAA==.Thryx:BAAALgAECgQJBwAAAA==.',
Ti='Tifalockhàrt:BAABLgAECn8fAAMFAAgJGQgmQQBzAQAFAAgJGQgmQQBzAQABAAEJLA5gKQAqAAAAAA==.Timewarped:BAABLgAECn8aAAIHAAgJfhBYdQDnAQAHAAgJfhBYdQDnAQAAAA==.Tiriòn:BAAALgAECgQJBQAAAA==.Titlefight:BAAALgADCgUJBQAAAA==.',
To='Torvii:BAAALgADCgMJAwAAAA==.Tossitgood:BAAALgADCgEJAQAAAA==.Totetum:BAAALgADCgYJBgABLgADCgkJDQANAAAAAA==.',
Tr='Trapsin:BAABLgAECn8iAAIHAAgJqx2bGwAGAgAHAAgJqx2bGwAGAgAAAA==.Trashstyle:BAAALgADCgIJAgAAAA==.Treeage:BAAALgAECgEJAQAAAA==.Treebreath:BAAALgADCgYJBwAAAA==.Treegerhappy:BAABLgAECn8kAAMRAAkJCRaXDwAbAgARAAkJCRaXDwAbAgAaAAUJsgRHZQCqAAAAAA==.Trilldevour:BAAALgAECgcJBQAAAA==.Trubbs:BAAALgADCgMJBAAAAA==.Truffle:BAABLgAECn8eAAMbAAgJghi5HADIAQAbAAcJ7he5HADIAQAUAAMJ/R0hEACxAAAAAA==.Tryniti:BAAALgAECgEJAQAAAA==.',
Tw='Twyson:BAAALgADCgMJAwAAAA==.',
Un='Uny:BAAALgAECgQJBAABLgAECggJHwAHADYUAA==.',
Us='Usdaprime:BAAALgADCgEJAQAAAA==.',
Va='Valanya:BAAALgADCgYJBgAAAA==.Valkarie:BAABLgAECn8cAAMGAAgJ0BHsDgCeAQAGAAgJ0BHsDgCeAQAhAAEJgwmCQgAqAAAAAA==.Valtroist:BAAALgADCgkJEAABLgAECgMJBAANAAAAAA==.Valzyn:BAABLgAECn8cAAIPAAcJhh74BwADAgAPAAcJhh74BwADAgAAAA==.Vancleave:BAAALgADCgYJBgABLgADCgcJDQANAAAAAA==.',
Vi='Vic:BAAALgAECgEJAQAAAA==.Vivix:BAABLgAECn8fAAIJAAkJkxeDDwBrAgAJAAkJkxeDDwBrAgAAAA==.',
Vo='Voidelfmage:BAAALgAECgEJAQABLgAECggJKQAEAJMmAA==.',
Wa='Wapoxi:BAABLgAECn8jAAMbAAkJMxqFMQBGAgAbAAgJpRqFMQBGAgAUAAQJOxbKKwAQAQAAAA==.Warisfluffy:BAABLgAECn8dAAILAAgJgQgJMAAjAQALAAgJgQgJMAAjAQAAAA==.Warwìck:BAAALgADCgMJAwAAAA==.',
Wh='Wheatswall:BAAALgADCgMJAgAAAA==.',
Wi='Windhamer:BAAALgAECgMJAwAAAA==.Wiseman:BAAALgADCgYJDgAAAA==.',
Wo='Wokman:BAACLgAFFH8JAAIVAAQJ4AWAFAD2AAAVAAQJ4AWAFAD2AAAuAAQKfyAAAw8ACAkREy4vAG0BAA8ABgkFGS4vAG0BABUACAkpDKE3AG0BAAAA.Wolfso:BAAALgAECgMJAwAAAA==.Woodoo:BAABLgAECn8lAAIMAAkJ+h7lAQBhAgAMAAkJ+h7lAQBhAgAAAA==.Worldboss:BAABLgAECn8dAAIBAAcJ7hpYBgDCAQABAAcJ7hpYBgDCAQAAAA==.Worldhorn:BAAALgAECgYJEgAAAA==.',
Wr='Wradalin:BAABLgAECn8eAAIIAAgJdAudRwAnAQAIAAgJdAudRwAnAQAAAA==.Wraithstorm:BAAALgADCgkJCwAAAA==.',
['Wó']='Wólverìne:BAAALgADCgcJBwAAAA==.',
Ya='Yaga:BAAALgADCgYJBgAAAA==.',
Yr='Yric:BAABLgAECn8ZAAILAAgJWiBGBQCOAgALAAgJWiBGBQCOAgAAAA==.',
Yu='Yugito:BAAALgAECgQJBgAAAA==.',
Za='Zariane:BAAALgADCgcJGgAAAA==.Zarila:BAAALgAECgEJAgAAAA==.Zartain:BAABLgAECn8fAAIjAAgJxg1BBACXAQAjAAgJxg1BBACXAQAAAA==.Zataana:BAAALgADCgMJAwAAAA==.Zazreiale:BAAALgAECgEJAgAAAA==.',
Ze='Zelfei:BAAALgADCgUJBQAAAA==.Zennamite:BAABLgAECn8fAAISAAgJrBNmDgC6AQASAAgJrBNmDgC6AQAAAA==.',
Zi='Zipzaps:BAAALgAECgYJEgAAAA==.',
['Ñu']='Ñuiña:BAAALgADCgMJBAAAAA==.',
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
