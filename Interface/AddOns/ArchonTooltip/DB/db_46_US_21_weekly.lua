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

local lookup = {'Warrior-Fury','Warrior-Arms','Paladin-Holy','Paladin-Retribution','Evoker-Augmentation','Mage-Frost','DeathKnight-Unholy','Priest-Holy','Monk-Mistweaver','DemonHunter-Devourer','Druid-Guardian','Monk-Brewmaster','Druid-Restoration','Monk-Windwalker','Priest-Discipline','Hunter-BeastMastery','Warrior-Protection','Unknown-Unknown','DemonHunter-Havoc','DeathKnight-Blood','Shaman-Restoration','Shaman-Elemental','Druid-Balance','Hunter-Marksmanship','Evoker-Preservation','Rogue-Outlaw','Priest-Shadow','Rogue-Subtlety','Warlock-Destruction','Warlock-Demonology','Evoker-Devastation','Warlock-Affliction','Paladin-Protection','Rogue-Assassination',}
local provider = {region='US',realm='Arygos',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aava:BAAALgADCgEJAQAAAA==.',
Ad='Adivion:BAAALgAECgEJAQAAAA==.Adrenelian:BAAALgAECgYJBgAAAA==.',
Ah='Ahgro:BAAALgADCgcJBwAAAA==.',
Ak='Akroma:BAAALgAECgYJDQAAAA==.',
Al='Alecwar:BAABLgAECn8gAAIBAAgJ0RkNBAAAAgABAAgJ0RkNBAAAAgAAAA==.Altezio:BAABLgAECn8WAAICAAgJqxZLAQASAgACAAgJqxZLAQASAgAAAA==.',
An='Andransonis:BAAALgADCgUJBQAAAA==.Ankarna:BAAALgAECgEJAQAAAA==.Annegwish:BAABLgAECn8bAAMDAAkJcAzuRABkAQADAAcJpwnuRABkAQAEAAcJ0wgrtAAcAQAAAA==.Anonymous:BAAALgAECgQJBAAAAA==.Antashaman:BAAALgAECgQJBAAAAA==.',
Ap='Apokalypsis:BAAALgADCgUJCgAAAA==.',
Ar='Archodreki:BAABLgAECn8XAAIFAAYJOBAOMgA4AQAFAAYJOBAOMgA4AQAAAA==.Ardithan:BAABLgAECn8cAAIGAAkJ0iDhJADfAgAGAAkJ0iDhJADfAgAAAA==.Arilm:BAAALgADCgMJAwAAAA==.Arthuur:BAABLgAECn8dAAIHAAgJThnPOwBIAgAHAAgJThnPOwBIAgAAAA==.Arynthyan:BAABLgAECn8ZAAIIAAkJDxnCEABeAgAIAAkJDxnCEABeAgAAAA==.Arystrasza:BAAALgADCgUJBQABLgAECgkJHwAJAJAgAA==.Aryzhuque:BAABLgAECn8fAAIJAAkJkCA2BAAtAwAJAAkJkCA2BAAtAwAAAA==.',
As='Ashana:BAAALgADCgYJBgAAAA==.Ashmandious:BAAALgADCgcJEwAAAA==.Asparavoid:BAABLgAECn8kAAIKAAkJ1x/DCABDAwAKAAkJ1x/DCABDAwAAAA==.Aspyn:BAAALgADCgEJAgAAAA==.Assandros:BAABLgAECn8fAAILAAkJ4SROAADEAwALAAkJ4SROAADEAwAAAA==.',
At='Ataraxia:BAAALgADCgEJAQAAAA==.Athleta:BAEALgAECggJCAABLgAFFAUJDwAMAJsMAA==.',
Au='Aurilian:BAAALgADCgQJBAAAAA==.',
Av='Average:BAAALgADCggJGQAAAA==.',
Ay='Ayku:BAAALgAECgEJAQAAAA==.',
Az='Azrox:BAAALgADCgUJBQAAAA==.Azurien:BAAALgAECgMJAwAAAA==.',
Ba='Baboo:BAAALgAECgEJAQAAAA==.Balgrim:BAAALgADCgQJBAAAAA==.Banthum:BAABLgAECn8XAAINAAcJkRTOCgCrAQANAAcJkRTOCgCrAQAAAA==.',
Be='Bearlough:BAAALgAECgQJBwAAAA==.Beerhelmet:BAABLgAECn8YAAMOAAYJkRY0KwCEAQAOAAYJkRY0KwCEAQAJAAYJtQM3SAC6AAAAAA==.Beryl:BAAALgAECgYJEQAAAA==.',
Bi='Biggyword:BAABLgAECn8VAAMPAAcJPCEhAgBOAgAPAAcJJSEhAgBOAgAIAAMJEyEeSgAQAQAAAA==.',
Bl='Bleddyn:BAAALgADCgYJBgAAAA==.Blorbusdorp:BAAALgAECgYJCgAAAA==.',
Bo='Bobsgirl:BAABLgAECn8UAAIQAAkJHQ+xIwAwAgAQAAkJHQ+xIwAwAgAAAA==.Boodrios:BAAALgAECgcJEQAAAA==.',
Br='Braleanna:BAAALgAECgEJAgAAAA==.Brewmaster:BAAALgADCgIJAgABLgAECggJGgAPAIwfAA==.Bruke:BAABLgAECn8VAAIRAAkJLxylCACVAgARAAkJLxylCACVAgAAAA==.',
Bu='Buffsyou:BAAALgAECgUJCgAAAA==.Bugge:BAAALgAECgYJEwAAAA==.Bulldozzer:BAAALgADCgYJBwAAAA==.Bus:BAABLgAFFH8IAAILAAcJQR8bAAAJAgALAAcJQR8bAAAJAgAAAA==.',
Ca='Catastrophe:BAAALgAECgYJEwAAAA==.',
Cb='Cbat:BAABLgAECn8WAAILAAcJOBsjAgC9AQALAAcJOBsjAgC9AQAAAA==.',
Cd='Cdicepalta:BAAALgAECgEJAgABLgAECgYJEQASAAAAAA==.',
Ce='Celes:BAAALgAECgMJBAAAAA==.',
Ch='Chapulín:BAAALgAECggJCQABLgAECggJFgAMAJMeAA==.',
Ci='Cindér:BAAALgADCgMJAwAAAA==.Cinimist:BAAALgAECgYJCQAAAA==.',
Co='Coinlock:BAAALgAECgYJCwAAAA==.Coinslot:BAAALgAECgMJBAABLgAECgYJCwASAAAAAA==.Compact:BAAALgADCgYJBgABLgAECggJGgAPAIwfAA==.Concubine:BAABLgAECn8ZAAITAAcJSgwHLABoAQATAAcJSgwHLABoAQAAAA==.Confettii:BAAALgAECgMJAwABLgAECgQJBwASAAAAAA==.Conän:BAAALgADCgMJAwAAAA==.Cordie:BAAALgADCgcJDQAAAA==.Cowdrogo:BAAALgAECgEJAQAAAA==.',
Cr='Crippled:BAAALgADCgEJAQAAAA==.Crosis:BAAALgADCgcJBwAAAA==.Cryhard:BAAALgAECgYJAQAAAA==.',
Cu='Cuchulainn:BAAALgADCgIJAgAAAA==.',
Da='Dagal:BAAALgADCgcJCwABLgAECgUJCQASAAAAAA==.Dalaran:BAAALgAECgYJEwAAAA==.Dalus:BAAALgADCgIJAgAAAA==.Danea:BAAALgAECgUJCwAAAA==.Dankzìlla:BAABLgAECn8ZAAIUAAgJ1Rs4CwBiAgAUAAgJ1Rs4CwBiAgAAAA==.Danmonk:BAAALgAECgEJAQAAAA==.Darach:BAAALgAECgEJAQAAAA==.Dawny:BAABLgAECn8hAAMVAAkJoRWHIQAWAgAVAAkJoRWHIQAWAgAWAAUJ4BgAQQBFAQAAAA==.',
De='Dealain:BAAALgADCggJCAAAAA==.Deathtrash:BAAALgADCgQJBAAAAA==.Decaran:BAABLgAECn8cAAIGAAkJ0RlcLADBAgAGAAkJ0RlcLADBAgAAAA==.Dectodraco:BAAALgADCgIJAgAAAA==.Dedpool:BAAALgAECgYJDQAAAA==.Delinara:BAAALgAECgUJCAAAAA==.Dethndk:BAAALgAECgYJBgAAAA==.',
Do='Doorjob:BAABLgAECn8cAAITAAkJCh+aCADZAgATAAkJCh+aCADZAgAAAA==.',
Dr='Dreamily:BAABLgAECn8XAAIXAAkJDw+3HQASAgAXAAkJDw+3HQASAgAAAA==.Driamn:BAAALgADCggJEAAAAA==.Drunkard:BAABLgAECn8WAAMJAAkJsR2ECgCqAgAJAAkJsR2ECgCqAgAOAAEJQQGPjQAYAAAAAA==.',
Dy='Dydy:BAAALgAECgEJAQAAAA==.',
Ea='Eame:BAAALgAECgYJEAABLgAECgcJFwAGALIQAA==.',
Eh='Ehnder:BAAALgADCgEJAQAAAA==.',
El='Elandron:BAAALgAECgIJAgAAAA==.Elenyia:BAAALgAECgYJDQAAAA==.Elfredo:BAAALgADCgEJAQAAAA==.Elia:BAABLgAECn8fAAMQAAkJlR25CwDkAgAQAAkJlR25CwDkAgAYAAYJYgfoUwD7AAAAAA==.Elisandre:BAAALgAECgMJAwAAAA==.Elmo:BAABLgAECn8eAAIHAAkJCh1cLwB6AgAHAAkJCh1cLwB6AgAAAA==.Elzä:BAABLgAECn8UAAIQAAcJ+BTyFgBEAQAQAAcJ+BTyFgBEAQAAAA==.',
Em='Emaria:BAAALgAECgQJBQAAAA==.',
En='Ennead:BAAALgAECgcJEQAAAA==.Entranced:BAABLgAECn8XAAITAAYJuSOWDwBsAgATAAYJuSOWDwBsAgAAAA==.Entropius:BAABLgAECn8WAAIHAAcJIhJCEwB4AQAHAAcJIhJCEwB4AQAAAA==.',
Er='Eranica:BAAALgADCgEJAQAAAA==.Ereinion:BAABLgAECn8bAAIBAAcJaRWGNQDSAQABAAcJaRWGNQDSAQAAAA==.Erkromerr:BAAALgAECgEJAgAAAA==.',
Ey='Eyb:BAAALgADCgcJDAAAAA==.',
Ez='Ezayle:BAABLgAECn8YAAIEAAkJsQjRYwC6AQAEAAkJsQjRYwC6AQAAAA==.Ezsolator:BAAALgAECgQJBAAAAA==.',
['Eï']='Eïs:BAABLgAECn8cAAIZAAgJrg92AwCwAQAZAAgJrg92AwCwAQAAAA==.',
Fe='Fearsmage:BAAALgADCgMJAwAAAA==.Fenris:BAAALgADCgYJCAAAAA==.',
Fo='Fonzie:BAABLgAECn8eAAIWAAkJGhWlGwA1AgAWAAkJGhWlGwA1AgAAAA==.Foregotten:BAABLgAECn8bAAIXAAgJaBoNFQBpAgAXAAgJaBoNFQBpAgAAAA==.',
Fr='Fragile:BAAALgAECgQJCAAAAA==.Freezee:BAAALgADCgYJCAAAAA==.Frostietute:BAAALgAECgYJCgAAAA==.',
Fu='Fudd:BAAALgADCgQJBwAAAA==.',
Ga='Galen:BAAALgADCgEJAgAAAA==.Galsin:BAAALgAECgUJCQAAAA==.Gamboa:BAAALgAECgYJBgAAAA==.Gandulfgray:BAAALgADCgMJAwAAAA==.Gauche:BAABLgAECn8UAAMOAAYJXiC7FgAxAgAOAAYJXiC7FgAxAgAJAAYJTRrvDQAEAQAAAA==.Gazreiale:BAABLgAECn8bAAIaAAgJNRLQAwD2AQAaAAgJNRLQAwD2AQAAAA==.',
Gi='Giddie:BAABLgAECn8fAAMVAAgJdg8FNwCnAQAVAAgJdg8FNwCnAQAWAAUJ4Q/NVADyAAAAAA==.Giddygos:BAAALgADCgIJAgAAAA==.Girthquake:BAAALgADCggJDgAAAA==.',
Go='Goldylocks:BAAALgADCgcJBwAAAA==.',
Gr='Grass:BAAALgAECgYJCQAAAA==.Grimtree:BAAALgAECgIJAgAAAA==.Gromnash:BAAALgADCgcJDQABLgAFFAUJDQAQACkeAA==.',
Gu='Guldanica:BAAALgADCggJFgAAAA==.',
Gw='Gwaine:BAAALgAECgYJCgAAAA==.Gwyndolín:BAAALgAECgMJBQAAAA==.',
Gy='Gyaatso:BAAALgADCgEJAQAAAA==.',
He='Helgrund:BAAALgADCgcJBwAAAA==.Hellfyrê:BAAALgADCgkJFwAAAA==.Heritikyl:BAABLgAECn8bAAINAAgJ1SJbCQD8AgANAAgJ1SJbCQD8AgAAAA==.Heritikyldin:BAAALgAECgQJBAAAAA==.',
Hi='Hibou:BAAALgADCgEJAQAAAA==.Hiim:BAABLgAECn8UAAIXAAgJvRC6KAC5AQAXAAgJvRC6KAC5AQAAAA==.',
Ho='Holycast:BAAALgAECgQJBAAAAA==.Holyhero:BAABLgAECn8eAAMbAAkJnB7tCQDkAgAbAAkJnB7tCQDkAgAIAAEJcQdygQAwAAAAAA==.',
Hu='Huntréss:BAAALgADCgUJBQAAAA==.',
Ic='Iceehot:BAAALgAECgEJAQAAAA==.',
Ig='Ignasio:BAAALgADCgYJBgAAAA==.',
In='Insanitii:BAAALgADCgMJBwABLgAECgQJBwASAAAAAA==.',
Ip='Iportyou:BAAALgAECgYJEAAAAA==.',
Iv='Ivysore:BAAALgAECgUJBwAAAA==.',
Ja='Jabjo:BAAALgAECgYJEwAAAA==.Jaira:BAAALgAECgcJDQAAAA==.Jastinasta:BAAALgADCgMJAwAAAA==.',
Je='Jeudeu:BAAALgADCgYJCwAAAA==.',
Ka='Kabira:BAAALgADCgYJBgAAAA==.Kaimed:BAAALgAECgEJAQAAAA==.Katalia:BAAALgAECgEJAQABLgAECgYJEgASAAAAAA==.',
Ki='Kinnick:BAAALgAECgYJCAAAAA==.Kinoloy:BAAALgADCgEJAQAAAA==.',
Ko='Konidus:BAAALgADCgMJAwAAAA==.Korna:BAAALgADCggJEgAAAA==.',
Kr='Kronosdh:BAAALgADCgQJBAABLgAECgYJBgASAAAAAA==.Kronosmonk:BAAALgAECgYJBgAAAA==.Kronospaly:BAAALgAECgQJCgABLgAECgYJBgASAAAAAA==.Kronoswarr:BAAALgAECgMJBQABLgAECgYJBgASAAAAAA==.',
Ku='Kunaee:BAAALgAECgEJAgAAAA==.Kuzcó:BAAALgAECgYJCQAAAA==.Kuzume:BAAALgADCgcJCAABLgAECgYJEgASAAAAAA==.',
Ky='Kyrius:BAAALgAECgYJEwAAAA==.',
La='Lausia:BAABLgAECn8XAAIGAAcJshCTFwCIAQAGAAcJshCTFwCIAQAAAA==.',
Ld='Ldyrose:BAAALgAECgMJBAAAAA==.',
Le='Legomaaggro:BAAALgAECgYJEgAAAA==.Lewtiefroopz:BAAALgAECgcJEwAAAA==.',
Li='Lilblade:BAAALgADCggJDAAAAA==.',
Lo='Loxiteria:BAABLgAECn8cAAIcAAkJlRHzEwB2AgAcAAkJlRHzEwB2AgAAAA==.',
Lu='Luciang:BAAALgADCgQJBAAAAA==.Lunarkitsune:BAAALgAECgYJDwAAAA==.Lusande:BAAALgADCgQJBAAAAA==.',
Ly='Lyzardwyzard:BAAALgADCgYJCQAAAA==.',
['Lì']='Lìlìth:BAABLgAECn8VAAIKAAcJaxc5FABcAQAKAAcJaxc5FABcAQAAAA==.',
Ma='Maantra:BAAALgADCgUJBgAAAA==.Magiclmao:BAAALgAECgIJAgAAAA==.Magnificò:BAABLgAECn8XAAIUAAcJlAcmCgDgAAAUAAcJlAcmCgDgAAAAAA==.Makani:BAAALgAECgYJDQAAAA==.Malarix:BAAALgAECgMJAwABLgAECgQJBgASAAAAAA==.Malory:BAABLgAECn8dAAIRAAgJmSJCAwAoAwARAAgJmSJCAwAoAwAAAA==.Malzahär:BAACLgAFFH8MAAMdAAQJwxtTAABrAQAdAAQJwxtTAABrAQAeAAEJgQ1ISwBPAAAuAAQKfxsAAx0ACAl8JNgDAKwCAB0ABwlSJNgDAKwCAB4ABQkqHiuLAEMBAAAA.',
Me='Messi:BAACLgAFFH8FAAIVAAIJxBK0FwCdAAAVAAIJxBK0FwCdAAAuAAQKfy4AAhUACQlwH04DAEUDABUACQlwH04DAEUDAAAA.',
Mi='Mielk:BAAALgADCgEJAQAAAA==.Miniraven:BAAALgADCgMJBwAAAA==.Minniedonut:BAAALgAECgEJAQAAAA==.',
Mu='Muffintop:BAABLgAECn8UAAIHAAcJehr7CwDDAQAHAAcJehr7CwDDAQAAAA==.Muki:BAAALgAECgYJEgAAAA==.',
My='Mystikal:BAAALgADCgYJBgABLgAECgYJFwAUAJAQAA==.Mythrondrir:BAAALgADCgYJBgAAAA==.',
Na='Nashumaya:BAAALgAECgYJCQAAAA==.Nathansbb:BAABLgAECn8hAAIEAAgJACahAQC9AgAEAAgJACahAQC9AgAAAA==.',
Ne='Neoamergin:BAAALgAECgcJEgABLgAECggJKgAeAP8fAA==.',
Ni='Nielic:BAAALgAECgMJBQAAAA==.Nimbus:BAACLgAFFH8KAAIFAAMJBgzUEgDoAAAFAAMJBgzUEgDoAAAuAAQKfxcAAwUABwkJIRYNAKQCAAUABwkJIRYNAKQCAB8AAgnKESU2AGQAAAEuAAUUBgkQAAUADBUA.',
No='Norrahh:BAAALgAECgEJAgAAAA==.Noteeth:BAAALgAECgcJDwAAAA==.Nozzle:BAAALgAECgEJAQAAAA==.',
Ny='Nyclon:BAAALgADCgUJBQAAAA==.Nyru:BAAALgADCgYJCgAAAA==.',
Or='Oriimis:BAAALgAECgYJDQAAAA==.Orion:BAABLgAECn8UAAIGAAcJAwayxQBbAQAGAAcJAwayxQBbAQAAAA==.',
Pa='Palanar:BAAALgADCgYJBgAAAA==.',
Pe='Penelopè:BAABLgAECn8WAAIMAAgJkx4CEwB6AgAMAAgJkx4CEwB6AgAAAA==.Penelópe:BAAALgADCgcJBwABLgAECggJFgAMAJMeAA==.Penný:BAABLgAECn8dAAIRAAgJlRTqBABzAQARAAgJlRTqBABzAQABLgAECggJFgAMAJMeAA==.Peondashaman:BAAALgAECgcJDAAAAA==.Pepino:BAAALgAECgYJDAAAAA==.',
Pf='Pflanlock:BAAALgADCgEJAQAAAA==.',
Ph='Phinx:BAABLgAECn8eAAIHAAkJ+AjfYQDOAQAHAAkJ+AjfYQDOAQAAAA==.Phocheux:BAAALgAECgMJBgAAAA==.Phulgoth:BAAALgADCgUJCwAAAA==.',
Pi='Picklericks:BAAALgADCgIJAwAAAA==.Pierogi:BAAALgAECgYJEQAAAA==.',
Po='Pockit:BAAALgADCgEJAwAAAA==.Poetrii:BAAALgAECgQJBAABLgAECgQJBwASAAAAAA==.Pomchow:BAAALgADCgQJBAAAAA==.Pomickyal:BAABLgAECn8XAAIeAAcJEAjvHgAnAQAeAAcJEAjvHgAnAQAAAA==.Pomymoth:BAAALgADCgYJBgAAAA==.Ponn:BAABLgAECn8aAAIPAAgJjB+MDwBFAgAPAAgJjB+MDwBFAgAAAA==.Poonswatter:BAAALgAECgYJEAAAAA==.Portails:BAAALgADCgMJAwAAAA==.',
Ps='Psychstorm:BAAALgAECgIJBAAAAA==.',
Qu='Quantumleaf:BAAALgADCgcJBwAAAA==.Quendeia:BAACLgAFFH8FAAIJAAQJJxB7BgDWAAAJAAQJJxB7BgDWAAAuAAQKfxsABAkACAn0HhkTADUCAAkABwmUIhkTADUCAAwABgkgA2pfAMQAAA4AAQl0BE6GACoAAAAA.',
Ra='Raeline:BAAALgADCgcJDgABLgADCgcJGgASAAAAAA==.Ragnärok:BAABLgAECn8VAAMVAAkJZAxbNACyAQAVAAkJZAxbNACyAQAWAAQJ8RQ7WADkAAAAAA==.Rats:BAAALgADCgcJBwAAAA==.',
Re='Recursion:BAABLgAECn8aAAQdAAgJnA27KwARAQAdAAYJnhC7KwARAQAeAAQJ0Qb/0gC0AAAgAAMJdgkeGgCnAAAAAA==.Reverii:BAAALgADCgMJAwABLgAECgQJBwASAAAAAA==.Rexisias:BAABLgAECn8jAAIQAAgJsiLCDADZAgAQAAgJsiLCDADZAgAAAA==.Reígn:BAABLgAECn8XAAIUAAYJkBAOJQAXAQAUAAYJkBAOJQAXAQAAAA==.',
Ri='Riaglais:BAAALgAECgEJAQAAAA==.Rinahfire:BAAALgAECgkJEQAAAA==.',
Rj='Rj:BAAALgAECgYJDQAAAA==.',
Ro='Rocky:BAAALgAECgQJBAABLgAECgYJGAAOAJEWAA==.Roomfourdy:BAAALgADCgEJAQAAAA==.Roughbbq:BAAALgAECgYJDAABLgAECgYJDQASAAAAAA==.Roundtwo:BAAALgADCgkJEgAAAA==.Roxi:BAAALgAECgYJCwAAAA==.',
Rt='Rtpopham:BAAALgAECgQJBAAAAA==.',
Sa='Saedri:BAAALgADCgEJAQAAAA==.Saikus:BAAALgAECgUJCQAAAA==.Saloman:BAAALgADCgMJBQABLgAECgYJCwASAAAAAA==.Sanguinus:BAAALgADCgkJCQAAAA==.Saphrin:BAAALgAECgYJEwAAAA==.Sarapho:BAAALgAECgYJEgAAAA==.Satoru:BAAALgADCgMJAwAAAA==.',
Sc='Scubasteve:BAAALgADCgcJCQAAAA==.Scurus:BAAALgAECgYJDAAAAA==.',
Se='Selynis:BAAALgADCgUJBQAAAA==.Selynne:BAABLgAECn8fAAIEAAkJBBs3GwDGAgAEAAkJBBs3GwDGAgAAAA==.Servingcvnt:BAAALgADCgYJDAAAAA==.',
Sh='Shadowfern:BAAALgADCgEJAgABLgAECgYJEgASAAAAAA==.Shadows:BAAALgADCgkJDQAAAA==.Shamanizeds:BAAALgAECgIJAgAAAA==.Shammeltoe:BAAALgAECgYJDwAAAA==.Sheepmogus:BAAALgADCgkJCgAAAA==.Shenn:BAAALgADCgkJEgAAAA==.Shotgirl:BAAALgADCgEJAQAAAA==.',
Si='Siello:BAAALgAECgQJBwAAAA==.Sillynda:BAAALgAECgIJAgAAAA==.Silversnipe:BAAALgADCgkJGgAAAA==.Sindorei:BAAALgAECgcJEwAAAA==.',
Sj='Sj:BAABLgAECn8WAAIDAAcJfyFTEQCIAgADAAcJfyFTEQCIAgABLgAFFAYJDgAGALMkAA==.',
Sk='Skye:BAAALgADCgkJEQABLgAECggJGwAXAGgaAA==.',
Sl='Slagathore:BAABLgAECn8XAAIeAAcJCAqAHAA1AQAeAAcJCAqAHAA1AQAAAA==.Slagathorne:BAAALgADCgYJBgABLgAECgcJFwAeAAgKAA==.Slegolas:BAABLgAECn8gAAMYAAkJhyMiCAAaAwAYAAgJ0CMiCAAaAwAQAAMJCSMAigDLAAAAAA==.Slicindomes:BAAALgADCgIJAgAAAA==.',
Sm='Smashe:BAAALgAECgQJBQAAAA==.',
So='Soggy:BAAALgADCgMJAwAAAA==.Somers:BAAALgAECgUJCgAAAA==.',
Sp='Spellbind:BAAALgAECgYJCgAAAA==.Spudnasty:BAAALgADCgYJBgAAAA==.',
St='Starstorms:BAAALgAECgcJEQAAAA==.',
Su='Summatime:BAABLgAECn8VAAIWAAgJdRY8NACHAQAWAAgJdRY8NACHAQAAAA==.',
Sw='Swiftiez:BAAALgADCgIJAgAAAA==.',
['Sö']='Sölair:BAAALgAECgYJBwAAAA==.',
Ta='Taie:BAAALgAECgQJBAAAAA==.',
Te='Terkerjobs:BAAALgADCgEJAQAAAA==.Teshala:BAAALgAECgMJBgAAAA==.Tetanei:BAAALgAECgUJBQAAAA==.',
Th='Thalandra:BAAALgAECgMJBQAAAA==.Theory:BAAALgAECggJEQAAAA==.Therapii:BAAALgAECgQJBwAAAA==.Thoraden:BAAALgADCgEJAQAAAA==.Thorgrimal:BAAALgAECgIJAgAAAA==.Thorizan:BAAALgADCgEJAQAAAA==.Thryx:BAAALgAECgQJBwAAAA==.',
Ti='Tifalockhàrt:BAABLgAECn8bAAIDAAgJswYpQQBzAQADAAgJswYpQQBzAQAAAA==.Timewarped:BAABLgAECn8UAAIGAAgJfhBfdQDnAQAGAAgJfhBfdQDnAQAAAA==.Tiriòn:BAAALgADCgIJAgAAAA==.Titlefight:BAAALgADCgUJBQAAAA==.',
To='Tossitgood:BAAALgADCgEJAQAAAA==.Totetum:BAAALgADCgYJBgABLgAECgQJCwASAAAAAA==.',
Tr='Trapsin:BAABLgAECn8bAAIGAAgJYh03LwC1AgAGAAgJYh03LwC1AgAAAA==.Trashstyle:BAAALgADCgIJAgAAAA==.Treeage:BAAALgADCgcJBwAAAA==.Treebreath:BAAALgADCgYJBwAAAA==.Treegerhappy:BAABLgAECn8cAAMQAAkJcBRiJQAmAgAQAAkJcBRiJQAmAgAYAAUJsgRRZQCqAAAAAA==.Trilldevour:BAAALgAECgcJBQAAAA==.Trubbs:BAAALgADCgMJAwAAAA==.Truffle:BAABLgAECn8WAAMeAAYJzBveFwBSAQAeAAUJzBveFwBSAQAdAAMJAA19QACzAAAAAA==.Tryniti:BAAALgAECgEJAQAAAA==.',
Tw='Twyson:BAAALgADCgMJAwAAAA==.',
Un='Uny:BAAALgAECgQJBAABLgAECgcJFwAGALIQAA==.',
Us='Usdaprime:BAAALgADCgEJAQAAAA==.',
Va='Valanya:BAAALgADCgYJBgAAAA==.Valkarie:BAABLgAECn8UAAMFAAcJ1w2lCQBMAQAFAAcJ1w2lCQBMAQAfAAEJgwl6QgAqAAAAAA==.Valtroist:BAAALgADCgkJEAABLgADCggJDgASAAAAAA==.Valzyn:BAAALgAECgYJEwAAAA==.Vancleave:BAAALgADCgYJBgABLgADCgcJDAASAAAAAA==.',
Vi='Vic:BAAALgAECgEJAQAAAA==.Vivix:BAABLgAECn8fAAIIAAkJkxd+DwBrAgAIAAkJkxd+DwBrAgAAAA==.',
Vo='Voidelfmage:BAAALgAECgEJAQABLgAECggJIQAEAAAmAA==.',
Wa='Wapoxi:BAABLgAECn8jAAMeAAkJMxqGMQBGAgAeAAgJpRqGMQBGAgAdAAQJOxbKKwAQAQAAAA==.Warisfluffy:BAABLgAECn8WAAIKAAcJkgckIgD9AAAKAAcJkgckIgD9AAAAAA==.Warwìck:BAAALgADCgMJAwAAAA==.',
Wh='Wheatswall:BAAALgADCgMJAgAAAA==.',
Wi='Windhamer:BAAALgAECgMJAwAAAA==.Wiseman:BAAALgADCgYJDgAAAA==.',
Wo='Wokman:BAACLgAFFH8FAAIMAAIJGgVuDQB4AAAMAAIJGgVuDQB4AAAuAAQKfx8AAw4ACAkREy8vAG0BAA4ABgkFGS8vAG0BAAwACAlZCqk3AG0BAAAA.Wolfso:BAAALgAECgMJAwAAAA==.Woodoo:BAABLgAECn8cAAILAAkJGBuJBQCBAgALAAkJGBuJBQCBAgAAAA==.Worldboss:BAABLgAECn8WAAIhAAYJsxovEQC1AQAhAAYJsxovEQC1AQAAAA==.Worldhorn:BAAALgAECgUJDgAAAA==.',
Wr='Wradalin:BAABLgAECn8XAAIHAAgJdAtbcACoAQAHAAgJdAtbcACoAQAAAA==.Wraithstorm:BAAALgADCgkJCgAAAA==.',
['Wó']='Wólverìne:BAAALgADCgcJBwAAAA==.',
Yr='Yric:BAABLgAECn8XAAIKAAcJYhx7BwD8AQAKAAcJYhx7BwD8AQAAAA==.',
Yu='Yugito:BAAALgAECgQJBgAAAA==.',
Za='Zariane:BAAALgADCgcJGgAAAA==.Zarila:BAAALgAECgEJAgAAAA==.Zartain:BAABLgAECn8XAAIiAAcJdgz1AgBaAQAiAAcJdgz1AgBaAQAAAA==.Zataana:BAAALgADCgMJAwAAAA==.Zazreiale:BAAALgAECgEJAgAAAA==.',
Ze='Zelfei:BAAALgADCgUJBQAAAA==.Zennamite:BAABLgAECn8XAAIWAAcJHhQfCAB+AQAWAAcJHhQfCAB+AQAAAA==.',
Zi='Zipzaps:BAAALgAECgYJDQAAAA==.',
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
