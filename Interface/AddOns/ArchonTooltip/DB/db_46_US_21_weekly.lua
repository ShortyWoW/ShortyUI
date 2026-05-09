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

local lookup = {'Warlock-Demonology','Paladin-Protection','Warrior-Fury','Warrior-Arms','Paladin-Retribution','Paladin-Holy','Evoker-Augmentation','Mage-Frost','DeathKnight-Unholy','Priest-Holy','Monk-Mistweaver','DemonHunter-Devourer','Druid-Guardian','Monk-Brewmaster','Unknown-Unknown','Druid-Restoration','Monk-Windwalker','Priest-Discipline','Hunter-BeastMastery','Shaman-Elemental','Warrior-Protection','Warlock-Destruction','DemonHunter-Havoc','DeathKnight-Blood','Shaman-Restoration','Druid-Balance','Hunter-Marksmanship','Evoker-Preservation','Rogue-Outlaw','Mage-Arcane','Priest-Shadow','Rogue-Subtlety','Druid-Feral','Evoker-Devastation','Warlock-Affliction','Rogue-Assassination',}
local provider = {region='US',realm='Arygos',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aava:BAAALgADCgEJAQAAAA==.',
Ad='Adivion:BAAALgAECgkJCwAAAA==.Adrenelian:BAABLgAECn8VAAIBAAgJOQcZSQBNAQABAAgJOQcZSQBNAQAAAA==.',
Ah='Ahgro:BAAALgAECgMJAwAAAA==.',
Ak='Akroma:BAABLgAECn8aAAICAAYJtBtfDAB2AQACAAYJtBtfDAB2AQAAAA==.',
Al='Alecwar:BAABLgAECn8wAAIDAAgJch9SBwB4AgADAAgJch9SBwB4AgAAAA==.Allyon:BAAALgADCgMJAwAAAA==.Altezio:BAABLgAECn8iAAIEAAkJ5R11AQDfAgAEAAkJ5R11AQDfAgAAAA==.',
Am='Amorial:BAAALgAECgQJBgAAAA==.',
An='Andransonis:BAAALgADCgUJBQAAAA==.Ankarna:BAAALgAECgEJAQAAAA==.Anklespanker:BAAALgAECgYJAgAAAA==.Annegwish:BAABLgAECn8nAAMFAAkJ2Qq3OQCZAQAFAAkJ2Qq3OQCZAQAGAAcJpwnvRABkAQAAAA==.Anonymous:BAAALgAECgQJBAAAAA==.Antashaman:BAAALgAECgUJCQAAAA==.',
Ap='Apah:BAAALgADCgEJAQAAAA==.Apokalypsis:BAAALgADCgUJCgAAAA==.',
Ar='Archodreki:BAABLgAECn8cAAIHAAgJFBEUMgA4AQAHAAgJFBEUMgA4AQAAAA==.Ardithan:BAABLgAECn8eAAIIAAkJtiDfJADfAgAIAAkJtiDfJADfAgAAAA==.Argah:BAAALgADCgMJAwAAAA==.Arilm:BAAALgADCgMJAwAAAA==.Arthuur:BAABLgAECn8qAAIJAAkJox0IDgCTAgAJAAkJox0IDgCTAgAAAA==.Arynthyan:BAABLgAECn8ZAAIKAAkJDxnHEABeAgAKAAkJDxnHEABeAgAAAA==.Arystrasza:BAAALgADCgUJBQABLgAECgkJHwALAJAgAA==.Aryzhuque:BAABLgAECn8fAAILAAkJkCA2BAArAwALAAkJkCA2BAArAwAAAA==.',
As='Ashana:BAAALgADCgYJBgAAAA==.Ashmandious:BAAALgAECgcJCQAAAA==.Asparavoid:BAABLgAECn8kAAIMAAkJ1x/BCABDAwAMAAkJ1x/BCABDAwAAAA==.Aspyn:BAAALgADCgEJAgAAAA==.Assandros:BAABLgAECn8fAAINAAkJ4SROAADEAwANAAkJ4SROAADEAwAAAA==.',
At='Ataraxia:BAAALgADCgEJAQAAAA==.Athleta:BAEALgAECggJCAABLgAFFAcJHAAOAFAZAA==.',
Au='Aurilian:BAAALgADCgQJBAAAAA==.',
Av='Average:BAAALgADCgkJKgAAAA==.',
Ay='Ayku:BAAALgAECgEJAQAAAA==.',
Az='Azrox:BAAALgADCgUJBQAAAA==.Azurien:BAAALgAECgMJAwAAAA==.',
Ba='Baboo:BAAALgAECgEJAQAAAA==.Bad:BAAALgAECgIJAwAAAA==.Baldbud:BAAALgADCgQJBAABLgAECgcJEAAPAAAAAA==.Balgrim:BAAALgADCgQJBwAAAA==.Banthum:BAABLgAECn8mAAIQAAgJYBPZIAC+AQAQAAgJYBPZIAC+AQAAAA==.',
Be='Bearbayt:BAAALgAECgUJBgAAAA==.Bearlough:BAAALgAECgYJCgAAAA==.Beerhelmet:BAABLgAECn8aAAMRAAYJkRY0KwCEAQARAAYJkRY0KwCEAQALAAYJtQOsSAC2AAAAAA==.Bertarious:BAAALgADCgYJCgAAAA==.Beryl:BAABLgAECn8ZAAMSAAgJlwveGgBZAQASAAgJhwbeGgBZAQAKAAYJAQ3EPwA6AQAAAA==.',
Bi='Biggyword:BAABLgAECn8gAAMSAAgJZyFdAwD4AgASAAgJUiFdAwD4AgAKAAMJEyEsSgAQAQAAAA==.',
Bl='Bleddyn:BAAALgADCgYJBgAAAA==.Blorbusdorp:BAAALgAECgcJEgAAAA==.',
Bo='Bobsgirl:BAABLgAECn8UAAITAAkJHQ+sIwAwAgATAAkJHQ+sIwAwAgAAAA==.Bolord:BAAALgAECgUJBQAAAA==.Boodrios:BAABLgAECn8gAAIUAAgJCQt+HwBTAQAUAAgJCQt+HwBTAQAAAA==.',
Br='Braleanna:BAAALgAECgEJAgAAAA==.Brewmaster:BAAALgADCgIJAgABLgAECggJGgASAIwfAA==.Bruke:BAABLgAECn8VAAIVAAkJLxymCACVAgAVAAkJLxymCACVAgAAAA==.',
Bu='Buffsyou:BAAALgAECgYJEQAAAA==.Bugge:BAABLgAECn8XAAIQAAgJFhshDwBhAgAQAAgJFhshDwBhAgAAAA==.Bulldozzer:BAAALgADCgYJBwAAAA==.Bus:BAABLgAFFH8OAAINAAgJfx8rAAB3AgANAAgJfx8rAAB3AgAAAA==.',
Ca='Catastrophe:BAABLgAECn8eAAIWAAgJZAytCABPAQAWAAgJZAytCABPAQAAAA==.',
Cb='Cbat:BAABLgAECn8mAAINAAgJ3B3hAwBIAgANAAgJ3B3hAwBIAgAAAA==.',
Cd='Cdicepalta:BAAALgAECgYJCAABLgAFFAEJAQAPAAAAAA==.',
Ce='Celes:BAAALgAECgUJDQAAAA==.',
Ch='Chapulín:BAAALgAECggJDAABLgAECggJJAAVAJwXAA==.',
Ci='Cindér:BAAALgADCgMJAwAAAA==.Cinimist:BAAALgAECgcJDgAAAA==.',
Co='Coinlock:BAAALgAECgYJDQAAAA==.Coinslot:BAAALgAECgMJBAABLgAECgYJDQAPAAAAAA==.Compact:BAAALgADCgYJBgABLgAECggJGgASAIwfAA==.Concubine:BAABLgAECn8eAAIXAAcJ1Q0ILABoAQAXAAcJ1Q0ILABoAQAAAA==.Confettii:BAAALgAECgMJAwABLgAECgYJEAAPAAAAAA==.Conän:BAAALgADCgMJAwAAAA==.Cordie:BAAALgADCgcJDQAAAA==.Cowdrogo:BAAALgAECgEJAQAAAA==.',
Cr='Crippled:BAAALgADCgEJAQAAAA==.Crosis:BAAALgADCgcJBwAAAA==.Cryhard:BAAALgAECgcJAwAAAA==.',
Cu='Cuchulainn:BAAALgADCgIJAgAAAA==.Curses:BAAALgADCgEJAQAAAA==.',
Da='Dagal:BAAALgAECgYJCAABLgAECgYJDwAPAAAAAA==.Daiju:BAAALgAECgEJAQABLgAECgYJDQAPAAAAAA==.Dalaran:BAABLgAECn8dAAIRAAgJQxgfDQDmAQARAAgJQxgfDQDmAQAAAA==.Daliron:BAAALgAECgEJAQAAAA==.Dalus:BAAALgADCgIJAgAAAA==.Danea:BAAALgAECgUJCwAAAA==.Dankzìlla:BAABLgAECn8aAAIYAAkJShs2CwBiAgAYAAkJShs2CwBiAgAAAA==.Darach:BAAALgAECgEJAQAAAA==.Dawny:BAABLgAECn8jAAMZAAkJJhmBIQAWAgAZAAkJJhmBIQAWAgAUAAUJ4BgDQQBFAQAAAA==.',
De='Dealain:BAAALgADCggJFQAAAA==.Deathtrash:BAAALgADCgQJBAAAAA==.Decaran:BAABLgAECn8cAAIIAAkJ0RldLADBAgAIAAkJ0RldLADBAgAAAA==.Dectodraco:BAAALgADCgIJAgAAAA==.Dedpool:BAAALgAECgYJDgAAAA==.Delinara:BAAALgAECgcJDgAAAA==.Dethndk:BAAALgAECgYJBgAAAA==.',
Do='Doorjob:BAABLgAECn8fAAIXAAkJCh+aCADZAgAXAAkJCh+aCADZAgAAAA==.',
Dr='Drakemage:BAAALgAECgkJBAAAAA==.Dreamily:BAABLgAECn8ZAAIaAAkJUhG7HQASAgAaAAkJUhG7HQASAgAAAA==.Driamn:BAAALgADCggJEAAAAA==.',
Dy='Dydy:BAAALgAECgEJAgAAAA==.',
Ea='Eame:BAABLgAECn8aAAIDAAgJ5Qw+IgBcAQADAAgJ5Qw+IgBcAQABLgAECggJJgAIAJwVAA==.',
Eh='Ehnder:BAAALgADCgEJAQAAAA==.',
El='Elandron:BAAALgAECgIJAgAAAA==.Elenyia:BAABLgAECn8aAAIGAAYJXBopGQDBAQAGAAYJXBopGQDBAQAAAA==.Elfredo:BAAALgADCgEJAQAAAA==.Elia:BAABLgAECn8fAAMTAAkJlR21CwDkAgATAAkJlR21CwDkAgAbAAYJYgf5UwD7AAAAAA==.Elisandre:BAAALgAECgUJBQAAAA==.Elmo:BAABLgAECn8oAAIJAAkJ5SCsEQBvAgAJAAkJ5SCsEQBvAgAAAA==.Elzä:BAABLgAECn8kAAITAAgJPiEnCQCiAgATAAgJPiEnCQCiAgAAAA==.',
Em='Emaria:BAAALgAECgQJBgAAAA==.Emergencii:BAAALgADCgIJAgABLgAECgYJEAAPAAAAAA==.',
En='Ennead:BAABLgAECn8gAAMBAAgJKgjdSABOAQABAAgJKgjdSABOAQAWAAUJbAg1FACvAAAAAA==.Entranced:BAABLgAECn8mAAIXAAgJTiP0AgC5AgAXAAgJTiP0AgC5AgAAAA==.Entropius:BAABLgAECn8lAAIJAAgJ4hYUJgDoAQAJAAgJ4hYUJgDoAQAAAA==.',
Er='Eranica:BAAALgADCgEJAQAAAA==.Ereinion:BAABLgAECn8bAAIDAAcJaRWGNQDSAQADAAcJaRWGNQDSAQAAAA==.Erkromerr:BAAALgAECgEJAgAAAA==.',
Ey='Eyb:BAAALgADCgcJDQAAAA==.',
Ez='Ezayle:BAABLgAECn8YAAIFAAkJsQjOYwC6AQAFAAkJsQjOYwC6AQAAAA==.Ezsolator:BAAALgAECgQJBAAAAA==.',
['Eï']='Eïs:BAABLgAECn8tAAIcAAkJFg+OCQDEAQAcAAkJFg+OCQDEAQAAAA==.',
Fe='Fearsmage:BAAALgAECgIJAgAAAA==.Fenris:BAAALgADCgYJCAAAAA==.',
Fo='Fonzie:BAABLgAECn8eAAIUAAkJGhWlGwA1AgAUAAkJGhWlGwA1AgAAAA==.Foregotten:BAABLgAECn8iAAIaAAgJaRoHFQBpAgAaAAgJaRoHFQBpAgAAAA==.',
Fr='Fragile:BAAALgAFFAEJAQAAAA==.Freezee:BAAALgADCgkJEQAAAA==.Frostietute:BAABLgAECn8UAAIIAAgJ4xoKJQARAgAIAAgJ4xoKJQARAgAAAA==.',
Fu='Fudd:BAAALgADCgQJBwAAAA==.',
Ga='Galen:BAAALgADCgEJAwAAAA==.Galsin:BAAALgAECgYJDwAAAA==.Gamboa:BAAALgAECgYJDwAAAA==.Gandulfgray:BAAALgADCgMJAwAAAA==.Gauche:BAABLgAECn8jAAMRAAgJqx7LBgBfAgARAAgJqx7LBgBfAgALAAYJORptKgD7AAAAAA==.Gazreiale:BAABLgAECn8eAAIdAAkJ9BO2BACFAQAdAAkJ9BO2BACFAQAAAA==.',
Gi='Giddie:BAABLgAECn8pAAMZAAkJ8BLFIgCfAQAZAAkJ8BLFIgCfAQAUAAYJnQ7bVADyAAAAAA==.Giddygos:BAAALgADCgIJAgAAAA==.Girthquake:BAAALgAECgQJCQAAAA==.',
Go='Goldylocks:BAAALgADCgcJBwAAAA==.',
Gr='Grass:BAABLgAECn8VAAIeAAYJ7RMICAB6AQAeAAYJ7RMICAB6AQAAAA==.Grimtree:BAAALgAECgIJAgAAAA==.Gromnash:BAAALgADCgcJDQABLgAFFAYJFgATAAsiAA==.',
Gu='Guldanica:BAAALgADCggJFgAAAA==.',
Gw='Gwaine:BAAALgAECgYJEAAAAA==.Gwyndolín:BAAALgAFFAEJAQAAAA==.',
Gy='Gyaatso:BAAALgADCgEJAQAAAA==.',
Ha='Halima:BAAALgADCgUJBQAAAA==.',
He='Helgrund:BAAALgADCgcJBwAAAA==.Hellfyrê:BAAALgAECgEJAgAAAA==.Heritikyl:BAABLgAECn8mAAIQAAkJ5yFVCQD8AgAQAAkJ5yFVCQD8AgAAAA==.Heritikyldin:BAAALgAECggJDAAAAA==.',
Hi='Hibou:BAAALgADCgEJAQAAAA==.Hiim:BAABLgAECn8UAAIaAAgJvRC4KAC5AQAaAAgJvRC4KAC5AQAAAA==.',
Ho='Holycast:BAAALgAECgQJBAAAAA==.Holyhero:BAABLgAECn8eAAMfAAkJnB7xCQDkAgAfAAkJnB7xCQDkAgAKAAEJcQeAgQAwAAAAAA==.',
Hu='Huntréss:BAAALgADCgUJBQAAAA==.',
Ic='Iceehot:BAAALgAECgEJAQAAAA==.',
Ig='Ignasio:BAAALgADCgYJBgAAAA==.',
Im='Imposturr:BAAALgADCgkJEQAAAA==.',
In='Insanitii:BAAALgADCgYJDQABLgAECgYJEAAPAAAAAA==.',
Ip='Iportyou:BAAALgAECgYJEAAAAA==.',
Ja='Jabjo:BAABLgAECn8gAAIGAAgJFCDlDABGAgAGAAgJFCDlDABGAgAAAA==.Jaira:BAAALgAECgcJDQAAAA==.Janorune:BAAALgADCgMJAwAAAA==.Jastinasta:BAAALgADCgMJAwAAAA==.',
Je='Jeudeu:BAAALgADCgYJCwAAAA==.',
Ka='Kabira:BAAALgAECgEJAgAAAA==.Kaimed:BAAALgAECgEJAwAAAA==.Kaji:BAAALgADCgUJBQAAAA==.Katalia:BAAALgAECgEJAQABLgAECgYJFQATAPMWAA==.Katyparry:BAAALgAECgIJAgAAAA==.',
Ke='Keign:BAAALgAECgEJAgAAAA==.Keljeon:BAAALgAECgEJAQAAAA==.',
Ki='Kigorr:BAAALgAECgMJAwAAAA==.Kinnick:BAAALgAECgYJDwAAAA==.Kinoloy:BAAALgADCgEJAQAAAA==.',
Ko='Konidus:BAAALgAECgEJAQAAAA==.Korna:BAAALgAECgEJAwAAAA==.',
Kr='Kronosdh:BAAALgADCgQJBAABLgAECgYJDwAPAAAAAA==.Kronosmonk:BAAALgAECgYJDwAAAA==.Kronoswarr:BAAALgAECgQJCQABLgAECgYJDwAPAAAAAA==.',
Ku='Kunaee:BAAALgAECgEJAgAAAA==.Kuzcó:BAAALgAECgYJCgAAAA==.Kuzume:BAAALgADCgcJCAABLgAECgYJFQATAPMWAA==.',
Ky='Kyrius:BAABLgAECn8iAAIZAAgJVBe1FAAPAgAZAAgJVBe1FAAPAgAAAA==.',
La='Lausia:BAABLgAECn8mAAIIAAgJnBWULADvAQAIAAgJnBWULADvAQAAAA==.',
Ld='Ldyrose:BAAALgAECgQJCgAAAA==.',
Le='Legomaaggro:BAAALgAECgYJEgAAAA==.Lewtiefroopz:BAABLgAECn8gAAITAAcJuxuUJADDAQATAAcJuxuUJADDAQAAAA==.',
Li='Lilaria:BAAALgAECgQJBwABLgAECgYJDwAPAAAAAA==.Lilblade:BAAALgAECgEJAQAAAA==.',
Lo='Logana:BAAALgAECgYJBgAAAA==.Loxiteria:BAABLgAECn8cAAIgAAkJlRHwEwB2AgAgAAkJlRHwEwB2AgAAAA==.',
Lu='Luciang:BAAALgADCgQJBAAAAA==.Lunarkitsune:BAABLgAECn8ZAAITAAYJMgV9ZQDhAAATAAYJMgV9ZQDhAAAAAA==.Lusande:BAAALgADCgYJCQAAAA==.',
Ly='Lyzardwyzard:BAAALgADCgYJCQAAAA==.',
['Lì']='Lìlìth:BAABLgAECn8cAAIMAAcJcho+KQCVAQAMAAcJcho+KQCVAQAAAA==.',
Ma='Maantra:BAAALgADCgUJBgAAAA==.Macabre:BAAALgADCgcJBwAAAA==.Magiclmao:BAAALgAECgQJBQAAAA==.Magnificò:BAABLgAECn8mAAIYAAgJNQnbFwAOAQAYAAgJNQnbFwAOAQAAAA==.Makani:BAABLgAECn8aAAINAAYJ0wgjGgCMAAANAAYJ0wgjGgCMAAAAAA==.Malarix:BAAALgAECgMJAwAAAA==.Malory:BAABLgAECn8mAAIVAAkJlyRFAwAnAwAVAAkJlyRFAwAnAwAAAA==.Malzahär:BAACLgAFFH8UAAMWAAUJwxvWAQBWAQAWAAQJwxvWAQBWAQABAAQJ+Q6pSgDCAAAuAAQKfx0AAxYACAl8JNUDAKwCABYABwlSJNUDAKwCAAEABQkIID6LAEMBAAAA.',
Me='Messi:BAACLgAFFH8NAAIZAAQJFQ+QGgAAAQAZAAQJFQ+QGgAAAQAuAAQKfzkAAhkACQn1IE4DAEUDABkACQn1IE4DAEUDAAAA.',
Mi='Mielk:BAAALgADCgEJAQAAAA==.Minara:BAAALgAECgEJAgAAAA==.Miniraven:BAAALgADCgMJBwAAAA==.Minniedonut:BAAALgAECgEJAQAAAA==.',
Mu='Muffintop:BAABLgAECn8cAAIJAAgJkh7UEgBlAgAJAAgJkh7UEgBlAgAAAA==.Muki:BAABLgAECn8bAAIRAAgJBQyWGABgAQARAAgJBQyWGABgAQAAAA==.',
My='Mystikal:BAAALgADCgYJBgABLgAECggJJAAYAIYUAA==.Mythrondrir:BAAALgADCgYJBgAAAA==.Mythälus:BAAALgAECggJCAAAAA==.',
Na='Nashumaya:BAABLgAECn8WAAIZAAYJKQOiVgCkAAAZAAYJKQOiVgCkAAAAAA==.Nathansbb:BAABLgAECn8yAAIFAAkJSiaGAACDAwAFAAkJSiaGAACDAwAAAA==.',
Ne='Neoamergin:BAABLgAECn8jAAMQAAcJkhucGgDuAQAQAAcJkhucGgDuAQAhAAYJXAuoGAA4AQABLgAFFAIJBgABADQTAA==.',
Ni='Nielic:BAAALgAECgYJDAAAAA==.Nimbus:BAACLgAFFH8PAAIHAAMJIxbdEgDoAAAHAAMJIxbdEgDoAAAuAAQKfy4AAwcACQnoH1oCAAwDAAcACQnoH1oCAAwDACIAAgnKESs2AGQAAAEuAAUUBwkTAAcAIhQA.Nitrin:BAAALgADCgYJBgAAAA==.',
No='Norrahh:BAAALgAECgQJBgAAAA==.Noteeth:BAAALgAECgcJEAAAAA==.Nozzle:BAAALgAECgEJAQAAAA==.',
Ny='Nyclon:BAAALgAECgYJCwAAAA==.Nyru:BAAALgADCgYJCgAAAA==.',
Or='Ori:BAAALgAECgYJAgAAAA==.Oriimis:BAABLgAECn8RAAIMAAgJZxsjGAD7AQAMAAgJZxsjGAD7AQAAAA==.Orion:BAABLgAECn8mAAIIAAgJywdRWgBgAQAIAAgJywdRWgBgAQAAAA==.',
Pa='Palanar:BAAALgADCgYJBgAAAA==.',
Pe='Penelopè:BAABLgAECn8WAAIOAAgJkx4AEwB5AgAOAAgJkx4AEwB5AgABLgAECggJJAAVAJwXAA==.Penelópe:BAAALgADCgcJBwABLgAECggJJAAVAJwXAA==.Penný:BAABLgAECn8kAAIVAAgJnBcpDACjAQAVAAgJnBcpDACjAQAAAA==.Peondashaman:BAAALgAECgcJDAAAAA==.Pepino:BAAALgAECgYJDwAAAA==.',
Pf='Pflanlock:BAAALgAECgEJAQAAAA==.',
Ph='Phinx:BAABLgAECn8eAAIJAAkJ+AjYYQDOAQAJAAkJ+AjYYQDOAQAAAA==.Phocheux:BAAALgAECgYJDQAAAA==.Phulgoth:BAAALgAECgQJBAAAAA==.',
Pi='Picklericks:BAAALgADCgMJBQAAAA==.Pierogi:BAABLgAECn8dAAIUAAgJfResDwDpAQAUAAgJfResDwDpAQAAAA==.',
Po='Pockit:BAAALgAECgEJAQAAAA==.Poetrii:BAAALgAECgYJEAAAAA==.Pomchow:BAAALgADCgQJBAAAAA==.Pomickyal:BAABLgAECn8mAAIBAAgJHQqPQQBlAQABAAgJHQqPQQBlAQAAAA==.Pomymoth:BAAALgADCgYJBgAAAA==.Ponn:BAABLgAECn8aAAISAAgJjB+JDwBFAgASAAgJjB+JDwBFAgAAAA==.Ponyo:BAAALgADCgYJBgABLgAECggJJAAVAJwXAA==.Poonswatter:BAAALgAECgYJEAAAAA==.Portails:BAAALgADCgMJAwAAAA==.',
Ps='Psychstorm:BAAALgAECgIJBQAAAA==.',
Qu='Quantumleaf:BAAALgADCgcJBwAAAA==.Quendeia:BAACLgAFFH8JAAILAAYJSxMDBgDOAQALAAYJSxMDBgDOAQAuAAQKfyAABAsACAmKHxgTADQCAAsABwlAIxgTADQCAA4ABgkgA2ZfAMQAABEAAQl0BFmGACoAAAAA.',
Ra='Raeline:BAAALgADCgcJDgABLgADCgcJGgAPAAAAAA==.Ragnärok:BAABLgAECn8YAAMZAAkJORBaNACyAQAZAAkJORBaNACyAQAUAAQJ8RRKWADkAAAAAA==.Rats:BAAALgADCgcJDAAAAA==.',
Re='Recursion:BAABLgAECn8lAAQjAAgJ7hJRBACdAQAjAAcJHBVRBACdAQAWAAcJABCXEQDKAAABAAQJWQgX0wC0AAAAAA==.Reverii:BAAALgAECgIJAgABLgAECgYJEAAPAAAAAA==.Rexisias:BAACLgAFFH8LAAITAAMJWyE1IAAVAQATAAMJWyE1IAAVAQAuAAQKfyoAAhMACQlRJIMBAEQDABMACQlRJIMBAEQDAAAA.Reígn:BAABLgAECn8kAAIYAAgJhhQZDACzAQAYAAgJhhQZDACzAQAAAA==.',
Ri='Riaglais:BAAALgAECgEJAQAAAA==.Rinahfire:BAAALgAECgkJEQAAAA==.',
Rj='Rj:BAABLgAECn8aAAIJAAYJZRkhTABXAQAJAAYJZRkhTABXAQAAAA==.',
Ro='Rocky:BAAALgAECgQJBAABLgAECgYJGgARAJEWAA==.Roomfourdy:BAAALgADCgEJAQAAAA==.Roughbbq:BAAALgAECgYJDAABLgAECgYJDgAPAAAAAA==.Roundtwo:BAAALgADCgkJEgAAAA==.Roxi:BAAALgAECgYJCwAAAA==.',
Rt='Rtpopham:BAAALgAECgQJBAAAAA==.',
Ru='Rumblebumble:BAAALgAECgUJBQAAAA==.',
Sa='Saedri:BAAALgADCgEJAQAAAA==.Saikus:BAAALgAECgYJCwAAAA==.Saloman:BAAALgADCgMJBQABLgAECgYJDQAPAAAAAA==.Sanguinus:BAAALgADCgkJCQAAAA==.Saphrin:BAABLgAECn8gAAIXAAcJeBfMDAC0AQAXAAcJeBfMDAC0AQAAAA==.Saphya:BAAALgADCgEJAQAAAA==.Sarapho:BAABLgAECn8VAAITAAYJ8xbaVwBhAQATAAYJ8xbaVwBhAQAAAA==.Satoru:BAAALgADCgMJAwAAAA==.',
Sc='Scubasteve:BAAALgADCgcJCQAAAA==.Scurus:BAAALgAECgYJDAAAAA==.',
Se='Selynis:BAAALgADCgUJBQAAAA==.Selynne:BAABLgAECn8fAAIFAAkJBBs0GwDGAgAFAAkJBBs0GwDGAgAAAA==.Servingcvnt:BAAALgADCgYJDAAAAA==.',
Sh='Shadowfern:BAAALgADCgEJAgABLgAECgYJFQATAPMWAA==.Shadowmnk:BAAALgAECgEJAQAAAA==.Shadows:BAAALgAECgIJAwAAAA==.Shamanizeds:BAAALgAECgMJAwAAAA==.Shammeltoe:BAABLgAECn8aAAIZAAYJpBuNGgDdAQAZAAYJpBuNGgDdAQAAAA==.Sheezee:BAAALgAECgcJCAAAAA==.Shenn:BAAALgADCgkJEgAAAA==.Shotgirl:BAAALgADCgEJAQAAAA==.',
Si='Siello:BAAALgAECgQJBwAAAA==.Sillynda:BAAALgAECgQJBAAAAA==.Silversnipe:BAAALgAECgYJBgAAAA==.Sindorei:BAABLgAECn8gAAITAAgJlg4LLQCaAQATAAgJlg4LLQCaAQAAAA==.',
Sj='Sj:BAABLgAECn8XAAIGAAcJfyFQEQCIAgAGAAcJfyFQEQCIAgABLgAFFAcJEQAIAMwiAA==.',
Sk='Skye:BAAALgADCgkJEQABLgAECggJIgAaAGkaAA==.',
Sl='Slagathore:BAABLgAECn8mAAIBAAgJ8Q4oMgCbAQABAAgJ8Q4oMgCbAQAAAA==.Slagathorne:BAAALgADCgYJBgABLgAECggJJgABAPEOAA==.Slegolas:BAABLgAECn8iAAMbAAkJoSMvCAAcAwAbAAgJ0CMvCAAcAwATAAQJiiFZdgCzAAAAAA==.Slicindomes:BAAALgADCgMJAwAAAA==.Slizepal:BAAALgADCgQJBAAAAA==.',
Sm='Smashe:BAAALgAECgQJBQAAAA==.',
So='Soggy:BAAALgADCgMJAwAAAA==.Somers:BAABLgAECn8dAAIDAAcJlBHwGwCIAQADAAcJlBHwGwCIAQAAAA==.',
Sp='Spellbind:BAABLgAECn8UAAIIAAYJFhygQgCfAQAIAAYJFhygQgCfAQAAAA==.Spudnasty:BAAALgADCgcJBwAAAA==.',
St='Starstorms:BAABLgAECn8hAAIQAAgJGBN6HgDQAQAQAAgJGBN6HgDQAQAAAA==.',
Su='Summatime:BAABLgAECn8WAAIUAAgJdRY9NACHAQAUAAgJdRY9NACHAQAAAA==.',
Sw='Swiftiez:BAAALgADCgMJAwAAAA==.',
Sy='Syara:BAAALgAECggJCAAAAA==.',
['Sö']='Sölair:BAAALgAECgYJBwAAAA==.',
Ta='Taie:BAAALgAECgYJEAAAAA==.',
Te='Terkerjobs:BAAALgADCgEJAQAAAA==.Teshala:BAAALgAECgUJDQAAAA==.Tetanei:BAAALgAECgUJBgAAAA==.',
Th='Thalandra:BAAALgAECgUJCgAAAA==.Theory:BAAALgAFFAEJAQAAAA==.Therapii:BAAALgAECgUJDQABLgAECgYJEAAPAAAAAA==.Thoraden:BAAALgADCgEJAQAAAA==.Thorgrimal:BAAALgAECgIJAgAAAA==.Thorizan:BAAALgADCgEJAQAAAA==.Thryx:BAAALgAECgQJBwAAAA==.',
Ti='Tifalockhàrt:BAACLgAFFH8GAAIGAAMJdQa2HQCxAAAGAAMJdQa2HQCxAAAuAAQKfyYAAwYACAkZCChBAHMBAAYACAkZCChBAHMBAAIABAnWEPcYAM4AAAAA.Timewarped:BAABLgAECn8hAAIIAAkJ5g9VdQDnAQAIAAkJ5g9VdQDnAQAAAA==.Tiriòn:BAAALgAFFAIJAgAAAA==.Titlefight:BAAALgADCgUJBQAAAA==.',
To='Torvii:BAAALgADCgMJAwAAAA==.Tossitgood:BAAALgADCgEJAQAAAA==.Totetum:BAAALgAECgEJAQABLgAECgUJDwAPAAAAAA==.',
Tr='Trapsin:BAACLgAFFH8GAAIIAAMJuhbPQgAFAQAIAAMJuhbPQgAFAQAuAAQKfyoAAggACAnhIfQRAIkCAAgACAnhIfQRAIkCAAAA.Trashstyle:BAAALgADCgIJAgAAAA==.Treeage:BAAALgAECgEJAQAAAA==.Treebreath:BAAALgADCgYJBwAAAA==.Treegerhappy:BAABLgAECn8mAAMTAAkJBhaYGQAFAgATAAkJBhaYGQAFAgAbAAUJsgRWZQCqAAAAAA==.Trilldevour:BAAALgAECgcJBQAAAA==.Trubbs:BAAALgADCgMJBAAAAA==.Truffle:BAABLgAECn8lAAMBAAgJfhpEIADvAQABAAcJ7xlEIADvAQAWAAMJ/h1wFACtAAAAAA==.Tryniti:BAAALgAECgEJAQAAAA==.',
Tw='Twyson:BAAALgADCgMJAwAAAA==.',
Un='Uny:BAAALgAECgQJBAABLgAECggJJgAIAJwVAA==.',
Us='Usdaprime:BAAALgADCgYJBgAAAA==.',
Va='Valanya:BAAALgADCgYJBgAAAA==.Valkarie:BAABLgAECn8cAAMHAAgJzRH7FACeAQAHAAgJzRH7FACeAQAiAAEJgwmBQgAqAAAAAA==.Valtroist:BAAALgADCgkJFAABLgAECgQJCQAPAAAAAA==.Valzyn:BAABLgAECn8dAAIRAAgJpRx/CAA5AgARAAgJpRx/CAA5AgAAAA==.Vancleave:BAAALgADCgYJBgABLgADCgcJDQAPAAAAAA==.Vayla:BAAALgADCggJCQABLgAECgYJEAAPAAAAAA==.',
Vi='Vic:BAAALgAECgEJAQAAAA==.Vivix:BAABLgAECn8fAAIKAAkJkxeADwBrAgAKAAkJkxeADwBrAgAAAA==.',
Vo='Voidelfmage:BAAALgAECgEJAQABLgAECgkJMgAFAEomAA==.',
Wa='Wapoxi:BAABLgAECn8jAAMBAAkJMxqDMQBGAgABAAgJpRqDMQBGAgAWAAQJOxbJKwAQAQAAAA==.Warisfluffy:BAABLgAECn8lAAIMAAgJyQg6RQAoAQAMAAgJyQg6RQAoAQAAAA==.Warwìck:BAAALgADCgMJAwAAAA==.Wayoftheurr:BAAALgADCgMJAwAAAA==.',
Wh='Wheatswall:BAAALgADCgMJAgAAAA==.',
Wi='Windhamer:BAAALgAECgMJAwAAAA==.Wiseman:BAAALgADCgYJDgAAAA==.',
Wo='Wokman:BAACLgAFFH8NAAIOAAQJxglGGQAHAQAOAAQJxglGGQAHAQAuAAQKfyIAAxEACQlvFCsvAG0BABEABgkFGSsvAG0BAA4ACQlkDpw3AG0BAAAA.Wolfso:BAAALgAECgMJAwAAAA==.Woodoo:BAABLgAECn8oAAINAAkJvR8LAgCnAgANAAkJvR8LAgCnAgAAAA==.Worldboss:BAABLgAECn8lAAICAAcJzB8ZBQAnAgACAAcJzB8ZBQAnAgAAAA==.Worldhorn:BAABLgAECn8WAAMHAAgJQA/UJQAdAQAHAAcJYQzUJQAdAQAiAAUJ/w4ICwDpAAAAAA==.',
Wr='Wradalin:BAABLgAECn8mAAIJAAgJDxBMNQCkAQAJAAgJDxBMNQCkAQAAAA==.Wraithstorm:BAAALgADCgkJFAAAAA==.',
['Wó']='Wólverìne:BAAALgADCgcJBwAAAA==.',
Ya='Yaga:BAAALgADCgYJBgABLgADCggJCQAPAAAAAA==.',
Yr='Yric:BAABLgAECn8ZAAIMAAgJTiARCgCIAgAMAAgJTiARCgCIAgAAAA==.',
Yu='Yugito:BAAALgAECgQJBgAAAA==.',
Za='Zariane:BAAALgADCgcJGgAAAA==.Zarila:BAAALgAECgEJAgAAAA==.Zartain:BAABLgAECn8mAAIkAAgJZxHQBAC8AQAkAAgJZxHQBAC8AQAAAA==.Zataana:BAAALgADCgMJAwAAAA==.Zazreiale:BAAALgAECgEJAgAAAA==.',
Ze='Zelfei:BAAALgADCgUJBQAAAA==.Zennamite:BAABLgAECn8mAAIUAAgJmBZIEADhAQAUAAgJmBZIEADhAQAAAA==.',
Zi='Zipzaps:BAABLgAECn8WAAIIAAYJIBXAoQCUAQAIAAYJIBXAoQCUAQAAAA==.',
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
