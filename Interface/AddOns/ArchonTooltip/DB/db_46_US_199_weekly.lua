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

local lookup = {'Druid-Restoration','Shaman-Restoration','DemonHunter-Vengeance','Unknown-Unknown','Paladin-Holy','Paladin-Retribution','Warrior-Arms','Warrior-Fury','Evoker-Preservation','Warrior-Protection','Priest-Holy','DeathKnight-Blood','Mage-Fire','Hunter-BeastMastery','Hunter-Marksmanship','Hunter-Survival','Monk-Mistweaver','Monk-Windwalker','Druid-Guardian','DeathKnight-Frost','DeathKnight-Unholy','Mage-Frost','Monk-Brewmaster','Warlock-Destruction','Priest-Shadow','DemonHunter-Devourer','Warlock-Demonology','Warlock-Affliction','Evoker-Augmentation','DemonHunter-Havoc','Druid-Feral','Druid-Balance','Paladin-Protection',}
local provider = {region='US',realm='Skywall',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abigt:BAAALgAECgYJEQAAAA==.',
Ad='Adalaidê:BAAALgAECgEJAQAAAA==.',
Ae='Aelusion:BAAALgAECggJEgAAAA==.Aeluu:BAAALgAECgcJBwABLgAECggJHQABALgRAA==.Aerynne:BAAALgAECgEJAgAAAA==.',
Ai='Ailis:BAAALgAECgQJBAAAAA==.Airie:BAABLgAECn8YAAICAAYJcwodFQAFAQACAAYJcwodFQAFAQAAAA==.Aita:BAABLgAECn8aAAIDAAgJahjwBgAdAgADAAgJahjwBgAdAgAAAA==.',
Ak='Akuso:BAAALgADCgYJCAAAAA==.',
Al='Alassa:BAAALgADCgQJBAAAAA==.Alayro:BAAALgAECgcJBQAAAA==.Alejandrø:BAAALgADCgUJBgAAAA==.Allegria:BAAALgAECgEJAQAAAA==.Alondra:BAAALgAECgYJEAAAAA==.Alulà:BAAALgAECgUJBwAAAA==.Aluucard:BAAALgADCgUJBQAAAA==.',
Am='Amo:BAAALgAECgIJAgABLgAECgUJCgAEAAAAAA==.',
An='Anaeli:BAABLgAECn8cAAICAAYJiRbhQQB5AQACAAYJiRbhQQB5AQAAAA==.Anariel:BAAALgADCgUJBQABLgADCgcJDQAEAAAAAA==.Androth:BAAALgAECgYJDQAAAA==.Angita:BAAALgAECgMJAwAAAA==.Antipæn:BAACLgAFFH8FAAMFAAIJeRYOCwBhAAAFAAEJKiUOCwBhAAAGAAEJBxXKFQBZAAAuAAQKfyUAAwYACAlBJQoDAIICAAYACAlBJQoDAIICAAUABgmKH/YpAOEBAAAA.',
Ap='Apologia:BAABLgAECn8aAAIGAAcJCCMFCAAKAgAGAAcJCCMFCAAKAgAAAA==.',
Ar='Arceé:BAAALgADCgYJBgAAAA==.Archaic:BAAALgAECgcJEwAAAA==.Ardicelia:BAAALgAECgEJAQAAAA==.Ares:BAACLgAFFH8IAAMHAAMJ3iD4AgAnAQAHAAMJsCD4AgAnAQAIAAIJCB7tFgCuAAAuAAQKfx4AAwcACAlOJOQBABoDAAcACAnJIuQBABoDAAgABwlHIjsZAIICAAAA.Ariellä:BAAALgADCgEJAQAAAA==.Arilynx:BAABLgAECn8WAAIJAAcJawgRJgBGAQAJAAcJawgRJgBGAQAAAA==.Arlynn:BAAALgADCgcJBwAAAA==.Armorgorden:BAABLgAECn8aAAIKAAgJbx4RAQBhAgAKAAgJbx4RAQBhAgAAAA==.Aroviaa:BAABLgAECn8cAAILAAcJNBY9CgBWAQALAAcJNBY9CgBWAQAAAA==.Arpmek:BAAALgAECgcJEgAAAA==.Artemîs:BAAALgADCgUJBQAAAA==.Arydynn:BAAALgADCgIJAgAAAA==.',
As='Astrìd:BAAALgADCgIJAgAAAA==.',
Au='Auntmary:BAAALgADCgYJCAAAAA==.Auramaximus:BAAALgAECgQJBQAAAA==.Aurtt:BAABLgAECn8dAAIMAAcJchi6EgDgAQAMAAcJchi6EgDgAQAAAA==.',
Av='Avanel:BAAALgADCgkJGgAAAA==.Avidae:BAAALgADCgcJCAAAAA==.',
Az='Azkadelia:BAAALgADCgYJBwAAAA==.',
Ba='Bageera:BAAALgADCgkJDgAAAA==.Bahahaknight:BAABLgAECn8YAAIMAAYJxx4YEgDqAQAMAAYJxx4YEgDqAQAAAA==.Barcy:BAAALgADCgQJBAAAAA==.Barnette:BAABLgAECn8lAAINAAgJWxGlAAC+AQANAAgJWxGlAAC+AQAAAA==.Barvi:BAAALgADCgEJAQABLgADCgUJBQAEAAAAAA==.Bashdown:BAAALgADCgEJAQAAAA==.Basic:BAAALgADCgEJAQAAAA==.',
Be='Bearyy:BAAALgADCgQJBAAAAA==.Belthos:BAABLgAECn8YAAIGAAcJFxvqSgACAgAGAAcJFxvqSgACAgAAAA==.Berristan:BAABLgAECn8YAAMFAAkJ1BelDAC1AgAFAAkJ1BelDAC1AgAGAAIJqwVsLAFIAAAAAA==.Bestwingman:BAAALgAECgEJAQAAAA==.',
Bg='Bgdaddyjupes:BAAALgADCgQJBAAAAA==.',
Bi='Bigsam:BAAALgADCgcJDQAAAA==.Bittytigs:BAAALgADCgUJBQAAAA==.',
Bl='Blossom:BAAALgAFFAMJAwABLgAFFAQJBAAEAAAAAA==.Bluewitchpa:BAAALgADCggJEAAAAA==.',
Bo='Boudiicca:BAAALgAECgMJDAAAAA==.Boxmasterr:BAAALgAECgcJEgAAAA==.',
Br='Brasmir:BAAALgAECgUJCAAAAA==.Bremerton:BAAALgAECgYJEQAAAA==.',
Bu='Bubblegìrl:BAAALgADCgcJCAAAAA==.Bubblement:BAAALgAFFAMJBgAAAQ==.Bushalabong:BAAALgAECgMJBAAAAA==.',
Bw='Bwonsmashdi:BAAALgADCgUJBgAAAA==.',
['Bù']='Bùb:BAAALgADCgEJAQAAAA==.',
Ca='Cafo:BAAALgADCgYJDAAAAA==.Capy:BAABLgAECn8pAAQOAAgJKiCGIwAwAgAOAAcJBiCGIwAwAgAPAAYJiBfqMQClAQAQAAQJHh+8CAAfAQAAAA==.Cardran:BAAALgADCgEJAQABLgAECgYJDQAEAAAAAA==.Carkusw:BAAALgAECgMJBwAAAA==.Cassyn:BAABLgAECn8YAAIFAAgJ3yHZBwDwAgAFAAgJ3yHZBwDwAgAAAA==.Catamay:BAAALgAECgcJEgABLgADCgkJGgAEAAAAAA==.Catprincess:BAABLgAECn8dAAIBAAgJuBF2OwC3AQABAAgJuBF2OwC3AQAAAA==.Caylara:BAAALgAECgEJAQAAAA==.Cayssaber:BAAALgADCgEJAQAAAA==.',
Ce='Celrythis:BAAALgAECgIJAgAAAA==.',
Ch='Chewglass:BAAALgADCggJCAAAAA==.Chiji:BAAALgAECgYJDQAAAA==.',
Cl='Clayler:BAAALgADCgQJBAAAAA==.Cleõ:BAAALgADCggJCwAAAA==.Clipperz:BAAALgADCgIJAgAAAA==.',
Co='Coocoohead:BAAALgAECgIJAgAAAA==.Coralorchid:BAAALgAECgQJCAAAAA==.Corrupt:BAAALgADCgMJAwAAAA==.',
Cp='Cptdarkk:BAAALgAECgQJBAAAAA==.',
Cu='Curissan:BAAALgAECgUJCAAAAA==.',
Cy='Cyg:BAAALgADCgEJAQAAAA==.',
['Cè']='Cères:BAAALgAECggJEwAAAA==.',
Da='Daladalian:BAAALgAECgMJAwAAAA==.Dalir:BAAALgAECgQJBgAAAA==.Dalruend:BAAALgADCgYJCwABLgAFFAYJEQARAGsKAA==.Dalspin:BAACLgAFFH8RAAIRAAYJawrMAQChAQARAAYJawrMAQChAQAuAAQKfxsAAxEACQm9GrgHAN0CABEACQm9GrgHAN0CABIABwkMEVAqAIoBAAAA.Dalthepal:BAAALgAFFAEJAQABLgAFFAYJEQARAGsKAA==.Darka:BAAALgADCgYJFgAAAA==.Davidline:BAABLgAECn8nAAIGAAgJcSMGAgCrAgAGAAgJcSMGAgCrAgAAAA==.Dawnfist:BAAALgAECgQJBAAAAA==.',
De='Deathsaberss:BAABLgAECn8eAAIHAAYJLBjyAwBpAQAHAAYJLBjyAwBpAQAAAA==.Deathstealer:BAAALgAECgIJAwAAAA==.Deathszen:BAAALgAECgUJBQAAAA==.Debauch:BAAALgAECgQJBAAAAA==.Demonkayk:BAAALgADCgkJDgAAAA==.Derke:BAAALgAECgMJBQAAAA==.',
Di='Diladrin:BAABLgAECn8mAAITAAgJmhBfEABxAQATAAgJmhBfEABxAQAAAA==.Diode:BAACLgAFFH8LAAMUAAQJAQ+OAQAGAQAVAAQJxAnnHwAbAQAUAAMJdxKOAQAGAQAuAAQKfykAAxQACAlHIXAAAGMCABUACAmbIC0YAOoCABQACAlQHHAAAGMCAAAA.',
Do='Doileag:BAAALgAECgQJBgAAAA==.Domer:BAAALgAECgQJBAAAAA==.Doomsong:BAAALgADCgYJCgAAAA==.Dottmatrix:BAAALgAECgQJBgAAAA==.',
Dr='Drachnia:BAAALgADCgYJCQAAAA==.Dragønbreath:BAABLgAECn8dAAMNAAkJYRoXAgBKAgANAAgJzBcXAgBKAgAWAAgJIBVUHgBeAQAAAA==.Dreadwing:BAAALgAECgMJCwAAAA==.',
Du='Duf:BAACLgAFFH8LAAIXAAQJNg+oBAAzAQAXAAQJNg+oBAAzAQAuAAQKfykAAhcACAkHHr0EAM4BABcACAkHHr0EAM4BAAAA.Dunso:BAAALgADCgYJAQAAAA==.Dustbunny:BAABLgAECn8YAAILAAcJaB0oFwAiAgALAAcJaB0oFwAiAgAAAA==.',
['Dì']='Dìzzy:BAAALgAECgIJAgAAAA==.',
['Dó']='Dóómkin:BAAALgADCgEJAQAAAA==.',
['Dû']='Dûn:BAAALgAECgcJEgAAAA==.',
Ei='Eira:BAAALgADCggJDQAAAA==.',
El='Elaatia:BAABLgAECn8dAAIGAAcJSiOHHAC/AgAGAAcJSiOHHAC/AgAAAA==.Elidria:BAAALgADCgYJBgAAAA==.Elimental:BAAALgAECgQJBQAAAA==.Ellaring:BAAALgAECgQJBQAAAA==.Elle:BAAALgADCgcJBwAAAA==.Elleanna:BAAALgADCgcJBwAAAA==.Elrric:BAAALgAECgUJDAAAAA==.',
En='Endora:BAAALgADCggJDQAAAA==.Enezath:BAAALgADCgYJBgAAAA==.',
Er='Erakron:BAAALgAECgUJEAAAAA==.Eriko:BAAALgADCgkJEAAAAA==.Eroviaa:BAAALgAECgQJBAABLgAECgcJHAALADQWAA==.Erovvia:BAAALgAECgEJAQABLgAECgcJHAALADQWAA==.',
Et='Etali:BAAALgADCgIJAgABLgAECgIJAgAEAAAAAA==.',
Ez='Ezothen:BAAALgAECgUJDAAAAA==.',
Fa='Faedoria:BAAALgAECgQJBAAAAA==.Faeryln:BAABLgAECn8bAAILAAYJKQcqEADtAAALAAYJKQcqEADtAAAAAA==.Faewrynn:BAAALgADCgMJAwAAAA==.Falkorr:BAAALgADCgEJAQABLgAECgMJDAAEAAAAAA==.Fatesmage:BAAALgADCgUJCAAAAA==.Fatherfade:BAAALgAECgQJBAAAAA==.Fatherkarras:BAAALgADCgIJAgAAAA==.Faustion:BAAALgAECgMJBQAAAA==.Faustus:BAAALgADCgQJCgABLgAECgMJBQAEAAAAAA==.',
Fi='Filthy:BAAALgADCggJDgAAAA==.Finessed:BAAALgADCgEJAQAAAA==.Firebrande:BAAALgAECgMJAwAAAA==.Fisticuffs:BAAALgADCggJDAAAAA==.Fizzllebang:BAABLgAECn8bAAIYAAYJOhTWBAAEAQAYAAYJOhTWBAAEAQAAAA==.',
Fl='Flamewhisker:BAAALgAECgMJAwAAAQ==.Flogginrenee:BAAALgAECgQJBwAAAA==.Floggsdaddy:BAAALgAECgQJBwAAAA==.Floke:BAAALgAECgMJAwAAAA==.Flokie:BAAALgADCgYJEQAAAA==.',
Fr='Fraublucher:BAAALgAECgUJDAAAAA==.Fredrik:BAAALgAFFAEJAgAAAA==.Frewyn:BAAALgAECgQJBAAAAA==.Frostimoth:BAAALgAECgUJBgAAAA==.Frozty:BAAALgAECgMJAwAAAA==.',
Ga='Galandel:BAAALgADCggJDAAAAA==.Galial:BAACLgAFFH8GAAIDAAIJDRyWAgCkAAADAAIJDRyWAgCkAAAuAAQKfyAAAgMACQkXHzoBACIDAAMACQkXHzoBACIDAAAA.Gantar:BAAALgAECggJEQAAAA==.Garlicbread:BAAALgADCgYJBgABLgAFFAIJBgADAA0cAA==.Gaznol:BAAALgAECgUJBwAAAA==.',
Ge='Gelasera:BAAALgAECgMJAwAAAA==.',
Gh='Ghibli:BAAALgAECgUJCQAAAA==.',
Gl='Glaivethras:BAABLgAECn8bAAIDAAYJhSRhBQBSAgADAAYJhSRhBQBSAgAAAA==.Glyphix:BAAALgAECgEJAQAAAA==.',
Go='Gorgon:BAAALgAECgMJBAAAAA==.',
Gr='Grasman:BAAALgADCgYJBwAAAA==.Gremlynn:BAAALgAECgYJEgAAAA==.Gridluck:BAAALgAECgMJBAAAAA==.',
Ha='Hackdk:BAAALgADCgYJCwAAAA==.Haedlesshour:BAAALgADCgcJBwAAAA==.Hahona:BAAALgADCgEJAQABLgAECgEJAQAEAAAAAA==.Hamfist:BAAALgADCgYJBwAAAA==.Hanhealz:BAEBLgAECn8WAAIZAAgJfw9fLQBzAQAZAAgJfw9fLQBzAQAAAA==.Hannebal:BAAALgAECgYJEwAAAA==.Havenfire:BAAALgADCgUJBQABLgADCgcJBgAEAAAAAA==.',
He='Hemlock:BAAALgADCgYJCgAAAA==.Hexia:BAAALgADCgUJCwAAAA==.Heydaw:BAAALgAECgYJBgABLgAECggJFwAVAPccAA==.',
Hi='Highmountain:BAAALgADCgkJCgAAAA==.',
Ho='Hobloc:BAAALgADCgcJCwAAAA==.Hobs:BAAALgADCgEJAQAAAA==.Holyßloodelf:BAAALgAECgQJBAABLgAECgYJCwAEAAAAAA==.Hornet:BAAALgAECgcJEAAAAA==.Hotcupofjoe:BAAALgADCgYJBgAAAA==.',
Hu='Huasca:BAAALgADCgcJBwAAAA==.Humungous:BAAALgAECgYJCAAAAA==.Hunnybunz:BAAALgADCgEJAgAAAA==.',
['Hâ']='Hârkness:BAAALgAECgMJDAAAAA==.',
Ic='Icastfirebal:BAAALgADCgkJEAAAAA==.Icypants:BAAALgADCgcJBwAAAA==.',
If='Iffany:BAAALgAECgcJAwAAAA==.',
Ig='Igotahitin:BAAALgADCgMJBgAAAA==.',
Ih='Ihitstuff:BAAALgADCgUJBAAAAA==.',
Ik='Iker:BAAALgAECggJDQAAAA==.',
Il='Illida:BAAALgAECgMJAwAAAA==.',
Im='Imamalelol:BAAALgAECgIJAgAAAA==.',
In='Indira:BAAALgADCgcJDQAAAA==.Insistonfist:BAAALgADCgEJAQAAAA==.Intol:BAAALgAFFAQJBAAAAQ==.Inumimi:BAAALgAECgYJCwAAAA==.',
Ir='Irkenfox:BAECLgAFFH8HAAIKAAQJKBlCBAA8AQAKAAQJKBlCBAA8AQAuAAQKfyEAAgoACAk+I5gDABsDAAoACAk+I5gDABsDAAAA.',
Is='Issho:BAAALgAECgQJBAAAAA==.',
It='Ithran:BAAALgAECgUJDAAAAA==.',
Iw='Iwilltank:BAAALgADCgYJDQAAAA==.',
Ix='Ixitt:BAABLgAECn8YAAINAAcJ1R4jAgBEAgANAAcJ1R4jAgBEAgAAAA==.',
Ja='Jallaz:BAAALgADCgQJBAAAAA==.James:BAABLgAECn8UAAIWAAUJIxIqLQAWAQAWAAUJIxIqLQAWAQABLgAFFAEJAgAEAAAAAA==.Janderick:BAAALgAECgYJCwAAAA==.Janthara:BAAALgAECgQJBAAAAA==.',
Je='Jellacee:BAAALgAECgMJDAAAAA==.Jesterjoe:BAAALgAECgEJAQAAAA==.',
Jh='Jhonson:BAAALgADCgYJBgAAAA==.',
Ji='Jimboberjim:BAACLgAFFH8LAAIYAAQJySM2AACEAQAYAAQJySM2AACEAQAuAAQKfykAAhgACAmIJB8AAL0CABgACAmIJB8AAL0CAAAA.Jimi:BAAALgADCgUJBQAAAA==.',
Jj='Jjoosshhiiee:BAAALgADCgMJAwABLgAECggJEQAEAAAAAA==.',
Jo='Jojokiller:BAAALgADCgEJAQAAAA==.Jolio:BAAALgAECgYJCwAAAA==.Joltraxi:BAAALgADCgcJCQAAAA==.Jorlidan:BAAALgAECgYJCgAAAA==.Joshe:BAAALgAECgYJDQABLgAECggJEQAEAAAAAA==.Jovae:BAAALgADCgIJAgAAAA==.',
Ju='Juggernauht:BAAALgAECgUJCAAAAA==.Juicethevoid:BAABLgAECn8ZAAIaAAYJGQcVNACaAAAaAAYJGQcVNACaAAAAAA==.Juniornite:BAABLgAECn8bAAIWAAcJth68FACcAQAWAAcJth68FACcAQAAAA==.Justicus:BAAALgAECgUJCQABLgAECggJFgAOALYVAA==.Justthetouch:BAAALgAECgYJBwAAAA==.',
Ka='Kaeldrin:BAAALgADCgQJBAAAAA==.Kaelsanguine:BAAALgAECgEJAQAAAA==.Kagemaro:BAAALgAECgIJAgAAAA==.Kaiser:BAAALgAECgQJBgAAAA==.Kaisér:BAAALgADCgYJBgAAAA==.Kalimathath:BAAALgAECgMJBAAAAA==.Kalzod:BAABLgAECn8nAAMbAAgJwSMxAgCMAgAbAAgJwSMxAgCMAgAcAAEJAAAbJABhAAAAAA==.Kariana:BAAALgAECgYJDgAAAA==.Katett:BAAALgAECgYJBwAAAA==.Kativeria:BAAALgAECgMJAwAAAA==.Kattara:BAAALgAECgQJBAAAAA==.Kattitude:BAAALgADCgcJDAABLgAECgYJDgAEAAAAAA==.Kaysabr:BAAALgADCgkJDAAAAA==.Kayssaber:BAAALgAECgUJCgAAAA==.Kazarale:BAAALgADCgQJBAAAAA==.Kazkade:BAAALgAECgMJAwAAAA==.',
Ke='Keanuu:BAAALgADCgMJAwAAAA==.Keyn:BAAALgADCgEJAQAAAA==.Keynstolor:BAAALgAECgUJEwAAAA==.',
Kh='Khionè:BAAALgAECgEJAQAAAA==.',
Ki='Kicker:BAAALgAECgIJAwAAAA==.Killmora:BAAALgADCggJEAAAAA==.Kippars:BAAALgAECgUJBwAAAA==.Kiritsugo:BAAALgADCgUJBgAAAA==.Kissame:BAAALgADCgcJDgAAAA==.',
Ko='Kodazoff:BAABLgAECn8UAAMdAAYJgg6RDAAhAQAdAAYJgg6RDAAhAQAJAAEJyASSSgAtAAAAAA==.Korevash:BAAALgAECgYJEAABLgAECggJKQALAJUiAA==.Korupta:BAABLgAECn8gAAMaAAYJPg0SJADyAAAeAAUJ3A3zPQAFAQAaAAYJEw0SJADyAAABLgAECggJGAAIADcRAA==.Korzilius:BAAALgAECgUJBgAAAA==.',
Kr='Kraiceru:BAAALgAECgUJCgAAAA==.Krissylu:BAAALgAECgQJBgAAAA==.Krothix:BAAALgAECgYJEwAAAA==.Kryshym:BAAALgADCggJEwAAAA==.',
Ku='Kuatea:BAAALgADCgUJBQAAAA==.Kurorø:BAAALgAECgMJBAAAAA==.',
['Kü']='Kürömë:BAAALgADCgMJAwAAAA==.',
La='Ladara:BAABLgAECn8fAAIcAAgJpA4QAQCuAQAcAAgJpA4QAQCuAQAAAA==.Laima:BAAALgADCgUJBgAAAA==.Landor:BAAALgADCgEJAQAAAA==.Lanea:BAAALgAECgEJAQAAAA==.',
Le='Leheo:BAAALgAECgMJBAAAAA==.Lehua:BAAALgADCgQJBAAAAA==.Leilanii:BAAALgADCggJDAAAAA==.Lemook:BAAALgADCgcJEAAAAA==.Leonìdas:BAAALgADCgYJBgAAAA==.',
Lh='Lhei:BAAALgAECgEJAQAAAA==.',
Li='Lightstormer:BAAALgADCggJDAAAAA==.Lilarielle:BAAALgAECgYJEgAAAA==.Lildash:BAAALgADCgIJAgABLgAECgYJDQAEAAAAAA==.Lilface:BAAALgAECgYJCgAAAA==.Liobrew:BAAALgADCgEJAQABLgAECgEJAQAEAAAAAA==.Liø:BAAALgAECgEJAQAAAA==.',
Lo='Lokir:BAAALgADCgMJBAAAAA==.Lotheovian:BAEALgAECgIJAgAAAA==.Lowchin:BAAALgAECgIJAgAAAA==.',
Lu='Lumia:BAABLgAECn8dAAMZAAkJcR4rEwBcAgAZAAcJlB8rEwBcAgALAAYJPBi/SgANAQAAAA==.Lutherion:BAAALgAECgUJBgAAAA==.',
['Lí']='Líttlefoot:BAAALgADCgEJAQAAAA==.',
Ma='Mackdaddy:BAAALgADCgQJBAAAAA==.Mackshiesty:BAAALgADCgcJBQAAAA==.Macoun:BAAALgAECggJDQAAAA==.Maeledictus:BAAALgAECgMJAwAAAA==.Maga:BAAALgADCgkJHgAAAA==.Magicshowers:BAABLgAECn8cAAIWAAcJ/iTDJADfAgAWAAcJ/iTDJADfAgAAAA==.Maikiee:BAAALgADCggJCAAAAA==.Manseed:BAAALgAECgMJAwAAAA==.Marksmen:BAAALgADCgEJAQABLgAECgQJBAAEAAAAAA==.Martei:BAACLgAFFH8IAAIfAAQJVAh2AQD2AAAfAAQJVAh2AQD2AAAuAAQKfykAAh8ACAnoIkMCAC8DAB8ACAnoIkMCAC8DAAAA.Maríneth:BAAALgAECgEJAQAAAA==.Mathías:BAABLgAECn8bAAIOAAYJqBn3EgBjAQAOAAYJqBn3EgBjAQAAAA==.',
Me='Meadowfrey:BAAALgADCgIJAwAAAA==.Meowbae:BAABLgAECn8cAAMfAAcJeQ7dEQCPAQAfAAcJeQ7dEQCPAQAgAAEJLwFHJgAaAAAAAA==.Mercesdes:BAAALgADCgQJBAAAAA==.Mercina:BAAALgAECgEJAQAAAA==.',
Mi='Midnyte:BAABLgAECn8bAAMSAAcJnBfrBQCNAQASAAcJnBfrBQCNAQARAAMJngymVQB6AAAAAA==.Milkybun:BAAALgADCgkJFAAAAA==.Mini:BAAALgADCgUJBQAAAA==.Minizee:BAAALgADCgYJBAAAAA==.Mirabella:BAAALgAECgQJBgABLgAECggJHwARAIMiAA==.Mirokushan:BAAALgAECgEJAQABLgAECgMJDAAEAAAAAA==.Mistfit:BAAALgAECgIJAgAAAA==.Mistrariel:BAAALgAECgMJAwAAAA==.',
Mo='Mojo:BAAALgADCgIJAgAAAA==.Mojomarv:BAAALgAECgYJEgAAAA==.Mordemour:BAAALgADCgIJAgAAAA==.',
Mu='Mungo:BAAALgAECgIJAgAAAA==.',
['Mæ']='Mæstra:BAAALgADCgEJAQAAAA==.',
Na='Nachtmar:BAAALgAECgEJAQAAAA==.Nadaliss:BAAALgADCgkJCwAAAA==.Nahela:BAACLgAFFH8LAAIaAAQJ9xCBBwA3AQAaAAQJ9xCBBwA3AQAuAAQKfycAAhoACAmnGaIIAOgBABoACAmnGaIIAOgBAAAA.',
Ne='Nevermøre:BAAALgAECgIJAgAAAA==.',
Ni='Nimravidae:BAABLgAECn8YAAIFAAYJpRi+CgCUAQAFAAYJpRi+CgCUAQAAAA==.Ninelives:BAAALgAECgYJEQAAAA==.Nitecrawler:BAAALgAECgUJBgAAAA==.Nixus:BAAALgAECgMJAwAAAA==.',
No='Nospitfisty:BAAALgAECgUJBwAAAA==.Noxium:BAAALgAECgQJBQAAAA==.Noxolon:BAAALgAECgYJDwAAAA==.',
Nr='Nreaf:BAABLgAECn8nAAMGAAgJwRzAJACUAgAGAAgJwRzAJACUAgAhAAMJ5xkZJQDgAAAAAA==.',
Nu='Nufy:BAAALgAECgYJDwAAAA==.',
Ny='Nyctei:BAAALgAECgMJAwAAAA==.Nysca:BAAALgADCgcJBwAAAA==.',
Ob='Obijuan:BAAALgADCgUJBgAAAA==.',
Oc='Octavia:BAAALgADCgYJCAAAAA==.',
Od='Oddotter:BAAALgADCgYJBgAAAA==.',
Oi='Oili:BAAALgAECgMJAwAAAA==.',
Ot='Ottuk:BAACLgAFFH8GAAIVAAIJ4RT6GACkAAAVAAIJ4RT6GACkAAAuAAQKfx8AAxUACQnVIa4IAFgDABUACQnVIa4IAFgDAAwAAwlnHXknAAMBAAAA.',
Pa='Paksenarrion:BAABLgAECn8YAAIhAAYJaRIjHQAhAQAhAAYJaRIjHQAhAQAAAA==.Pandemoniúm:BAAALgAECgMJAwAAAA==.Pandemonîum:BAAALgAECgcJDgAAAA==.Pandemöniüm:BAAALgAECgYJDAAAAA==.Patchington:BAAALgAECgEJAQAAAA==.',
Pe='Peatmoss:BAAALgADCgQJBAAAAA==.Pendrgn:BAAALgAECgEJAQAAAA==.Peryite:BAAALgADCgMJAwAAAA==.Pezp:BAAALgAECgQJBAABLgAECgQJCQAEAAAAAA==.Pezvoker:BAAALgAECgQJCQAAAA==.',
Pi='Pienarri:BAAALgADCgQJBQAAAA==.Pixelme:BAAALgAECgMJBQAAAA==.',
Pl='Pleggster:BAAALgAECgUJDAAAAA==.',
Po='Pochula:BAABLgAECn8UAAIBAAYJaQ3HZgAeAQABAAYJaQ3HZgAeAQAAAA==.Powerlock:BAAALgAECgQJBQAAAA==.',
Pr='Primo:BAABLgAECn8ZAAIFAAcJ2RHbNwCbAQAFAAcJ2RHbNwCbAQAAAA==.Protricity:BAABLgAECn8iAAMZAAgJuR3FAQBaAgAZAAgJuR3FAQBaAgALAAEJ2AJJhAAtAAAAAA==.',
['Pæ']='Pæn:BAAALgAECgYJEAABLgAFFAIJBQAFAHkWAA==.',
Qt='Qtpi:BAAALgADCgcJCAAAAA==.',
Qu='Quan:BAAALgAECgMJAwABLgAECgYJCwAEAAAAAA==.Quantar:BAAALgAECgYJCwAAAA==.',
Qw='Qwe:BAAALgAECgQJCwAAAA==.',
Ra='Racingdead:BAAALgADCgEJAQAAAA==.Rakshine:BAAALgAECggJCQAAAA==.Rancooll:BAAALgADCggJEAAAAA==.Rasniir:BAABLgAECn8YAAIBAAYJHBtlCgCxAQABAAYJHBtlCgCxAQAAAA==.Ravenlash:BAAALgAECgEJAgAAAA==.',
Re='Regna:BAACLgAFFH8LAAIIAAQJeiRVAACpAQAIAAQJeiRVAACpAQAuAAQKfykAAggACAlgJl8AAPYCAAgACAlgJl8AAPYCAAAA.Reign:BAAALgADCgYJBwAAAA==.Relkon:BAAALgAECgQJBwAAAA==.Remaked:BAACLgAFFH8SAAIXAAUJNxx5AwCpAQAXAAUJNxx5AwCpAQAuAAQKfy8AAhcACQlJIoMAAN8CABcACQlJIoMAAN8CAAAA.Remilia:BAAALgAECgYJCwAAAA==.Requinix:BAABLgAECn8gAAIOAAcJIhY+EAB+AQAOAAcJIhY+EAB+AQAAAA==.Retro:BAAALgAECgEJAQAAAA==.Revelatiøn:BAAALgADCgIJAgAAAA==.Revunanto:BAAALgAECgcJBgAAAA==.Revwrinkle:BAAALgADCgQJBQAAAA==.Rexthedragon:BAAALgADCgEJAQAAAA==.',
Ri='Riasu:BAAALgADCgYJCwAAAA==.Rickyybobbie:BAAALgAECgQJBwAAAA==.Ricochet:BAAALgAECgcJEgAAAA==.Riptidez:BAAALgADCgUJBQAAAA==.Ririko:BAABLgAECn8YAAILAAYJaA28DgAEAQALAAYJaA28DgAEAQAAAA==.Ritzo:BAAALgAECgYJEwAAAA==.Rizzla:BAAALgAECgIJAgABLgAECgMJDAAEAAAAAA==.',
Ro='Roguebâit:BAABLgAECn8bAAQbAAcJQRpnFgBcAQAbAAUJ3hhnFgBcAQAcAAMJORvOEwDzAAAYAAMJJw3LRACiAAAAAA==.',
Ru='Rubywolf:BAAALgADCgcJBwABLgAECggJEQAEAAAAAA==.Rukkis:BAAALgAECgUJCQAAAA==.Rumi:BAABLgAECn8mAAIDAAgJXx5ZBAB4AgADAAgJXx5ZBAB4AgAAAA==.',
Ry='Ryeekan:BAAALgAECgYJCAAAAA==.',
Sa='Saaconse:BAAALgADCgcJBwAAAA==.Saata:BAAALgAECgEJAQAAAA==.Sabrosura:BAABLgAECn8UAAIGAAgJQxLbeACIAQAGAAgJQxLbeACIAQAAAA==.Saelena:BAAALgADCgEJAQAAAA==.Sancha:BAAALgADCgQJBAAAAA==.Sanosagara:BAABLgAECn8UAAIRAAYJTBZuKwBcAQARAAYJTBZuKwBcAQAAAA==.Saps:BAAALgADCgIJAgAAAA==.Saraya:BAAALgADCgMJAwAAAA==.Sarithon:BAAALgADCgEJAQAAAA==.Saru:BAAALgADCgkJCQAAAA==.Saruta:BAABLgAECn8ZAAMIAAgJ2RjyKwAFAgAIAAcJzBryKwAFAgAHAAUJtA4LFgBNAQAAAA==.Sathari:BAABLgAECn8YAAIaAAYJUBWMGQA0AQAaAAYJUBWMGQA0AQAAAA==.',
Se='Sekk:BAABLgAECn8gAAIGAAcJpR7nCgDhAQAGAAcJpR7nCgDhAQAAAA==.Selexi:BAAALgADCgYJDwAAAA==.Sereya:BAAALgADCgQJBAABLgADCgcJBgAEAAAAAA==.',
Sg='Sgáil:BAAALgADCgkJCwAAAA==.',
Sh='Shaddai:BAAALgADCgcJFwAAAA==.Shadeofdark:BAABLgAECn8dAAIeAAYJRxwbBgBaAQAeAAYJRxwbBgBaAQAAAA==.Shadoshiftt:BAAALgAECgYJDQAAAA==.Shadowstar:BAAALgADCggJBwAAAA==.Shamwowee:BAAALgADCggJEAAAAA==.Shamzee:BAABLgAECn8cAAICAAYJ7B35BgDjAQACAAYJ7B35BgDjAQAAAA==.Shandalf:BAAALgAECgMJDAAAAA==.Shuddarun:BAACLgAFFH8LAAIOAAQJNR1+AQB6AQAOAAQJNR1+AQB6AQAuAAQKfyYAAg4ACAlfJcUDAFQDAA4ACAlfJcUDAFQDAAAA.',
Si='Sidera:BAAALgADCgQJAgABLgADCgcJDQAEAAAAAA==.Sify:BAAALgADCgYJBgAAAA==.Simn:BAAALgAECgYJDQAAAA==.Sindraesong:BAAALgAECgYJCgAAAA==.Sinfulpirate:BAAALgADCgQJBAAAAA==.Siyeigon:BAAALgADCgIJAQAAAA==.',
Sk='Skrai:BAAALgAECgYJCgABLgAECggJFQAKABgdAA==.',
Sl='Slayvylora:BAACLgAFFH8LAAIGAAQJRg8ABQBFAQAGAAQJRg8ABQBFAQAuAAQKfykAAwYACAkXIpMFAD0CAAYACAkXIpMFAD0CAAUABAnOBF1uAMEAAAAA.Slughorn:BAAALgADCgMJAwAAAA==.',
Sm='Smallholy:BAAALgADCgcJFAAAAA==.Smellgripson:BAAALgAECgIJAgAAAA==.',
Sn='Sneakymoth:BAAALgAECgMJAwABLgAECgUJBgAEAAAAAA==.Sniff:BAABLgAECn8ZAAIWAAgJERuhCQAPAgAWAAgJERuhCQAPAgAAAA==.Snookums:BAAALgAECgUJEwAAAA==.',
So='Soulomon:BAAALgAECgYJDQAAAA==.Soulsarisen:BAAALgAECgYJDgAAAA==.',
Sp='Spanki:BAAALgADCgkJDgAAAA==.Spellteaser:BAABLgAECn8UAAIWAAYJOhkGLgASAQAWAAYJOhkGLgASAQAAAA==.Spicymaker:BAAALgAECgYJEAAAAA==.Spiritual:BAAALgADCgIJAgAAAA==.',
St='Starar:BAAALgAECgMJBgAAAA==.Steelheart:BAAALgAECgEJAwAAAA==.Steviathan:BAAALgADCgQJBAAAAA==.Strifewood:BAAALgAECgUJBwAAAA==.Stumper:BAAALgAECgMJDAAAAA==.',
Su='Sugondese:BAAALgAECgQJBAAAAA==.Summêr:BAAALgAECgQJBAAAAA==.Suri:BAAALgAECgUJCgAAAA==.Sux:BAAALgAECgUJDAAAAA==.',
Sy='Sybrina:BAAALgAECgUJBQAAAA==.Sylvia:BAAALgADCgcJBgAAAA==.Synevra:BAAALgADCggJFgAAAA==.Syngeance:BAAALgAECgQJCAAAAA==.Synèsterwolf:BAAALgAECgEJAQABLgAECggJEQAEAAAAAA==.',
['Sí']='Síf:BAAALgAECgEJAQAAAA==.',
Ta='Tabernacle:BAAALgADCgEJAQAAAA==.Tamamò:BAABLgAECn8VAAIRAAcJ1BFbKABzAQARAAcJ1BFbKABzAQAAAA==.Tarrok:BAAALgADCgMJBAAAAA==.',
Te='Tealleth:BAAALgADCgMJAwAAAA==.Telana:BAAALgADCggJCgAAAA==.Tepache:BAAALgADCgEJAQAAAA==.Tequitos:BAAALgAECgUJBwAAAA==.Teranin:BAABLgAECn8UAAIgAAcJLgg0DgAPAQAgAAcJLgg0DgAPAQAAAA==.',
Tf='Tfortyone:BAAALgAECgMJAwAAAA==.',
Th='Tharbad:BAAALgADCgEJBQAAAA==.Thchosen:BAAALgAECgIJAgAAAA==.Thorae:BAAALgADCgEJAQAAAA==.Thorias:BAABLgAECn8mAAIWAAgJfSODBgBFAgAWAAgJfSODBgBFAgAAAA==.',
Ti='Tiren:BAAALgAECgQJBwAAAA==.',
To='Torag:BAAALgAECgQJBAAAAA==.Torment:BAABLgAECn8gAAIMAAcJNBuiAwCuAQAMAAcJNBuiAwCuAQAAAA==.',
Tr='Trepania:BAACLgAFFH8IAAILAAQJ4QVlAwD0AAALAAQJ4QVlAwD0AAAuAAQKfygAAgsACAkKGsoWACUCAAsACAkKGsoWACUCAAAA.Tristén:BAAALgAECgIJAgAAAA==.Trollycarp:BAAALgAECgUJCAAAAA==.',
Tu='Tumbler:BAAALgAECgYJBgAAAA==.Tumbles:BAAALgAECgUJBwAAAA==.Tumni:BAAALgAECgQJCAAAAA==.',
Tw='Twinkletoes:BAAALgADCgIJAgAAAA==.Twylah:BAAALgADCgIJAgAAAA==.',
['Tá']='Táelah:BAAALgAECgUJCAAAAA==.',
Ul='Ulnuk:BAABLgAECn8eAAICAAgJ7R7fAwA8AgACAAgJ7R7fAwA8AgAAAA==.Ulster:BAAALgAECgEJAQAAAA==.',
Un='Unidus:BAAALgAECgYJBwAAAA==.',
Up='Uphellyaa:BAAALgADCgUJBQABLgAECgQJBAAEAAAAAA==.',
Va='Vadka:BAAALgAECgIJAgAAAA==.Vaexxi:BAAALgAECgUJBgAAAA==.Vaha:BAAALgAECgEJAQAAAA==.Vairian:BAAALgAECgUJCgAAAA==.Valsavis:BAABLgAECn8dAAIDAAcJkBv+BwD+AQADAAcJkBv+BwD+AQAAAA==.Vampirä:BAABLgAECn8UAAIBAAYJ5AM/iQDCAAABAAYJ5AM/iQDCAAAAAA==.Vasarah:BAAALgAECgEJAQAAAA==.Vashidan:BAABLgAECn8YAAISAAgJ7iAyCAD3AgASAAgJ7iAyCAD3AgAAAA==.',
Ve='Velenar:BAAALgADCgIJAgAAAA==.Velisandre:BAAALgADCgcJIgAAAA==.Vellagosa:BAAALgAECgMJAwAAAA==.Verulan:BAAALgAECgQJBQAAAA==.Vexeh:BAAALgAECgMJAwAAAA==.Vexomous:BAAALgAECgQJBgAAAA==.',
Vi='Vierilan:BAAALgADCgcJBwAAAA==.Vikss:BAAALgAECgcJEQAAAA==.Viledk:BAAALgAECgUJBgAAAA==.Viserian:BAAALgADCgcJEgAAAA==.Vivien:BAAALgADCgYJBgABLgADCgcJBgAEAAAAAA==.',
Vl='Vll:BAABLgAECn8gAAIfAAcJ6x9rCABYAgAfAAcJ6x9rCABYAgABLgAECggJFgAOALYVAA==.',
Vo='Voidmayne:BAABLgAECn8bAAIGAAcJwAzbgwByAQAGAAcJwAzbgwByAQAAAA==.Vongogh:BAAALgADCgEJAQAAAA==.Vonhelsing:BAAALgAECgIJAgAAAA==.Vorcan:BAAALgADCgMJBgAAAA==.Vorenius:BAAALgADCgEJAQAAAA==.',
Vy='Vyv:BAAALgAECgcJDwAAAA==.Vyvboo:BAAALgADCgcJBwAAAA==.Vyvish:BAAALgADCgUJBQAAAA==.',
['Vö']='Vöid:BAABLgAECn8ZAAIaAAYJqht/EwBiAQAaAAYJqht/EwBiAQAAAA==.',
Wa='Warlogic:BAAALgAECgQJBAAAAA==.Wayadra:BAAALgAFFAEJAgAAAA==.',
We='Weiand:BAAALgAECgIJAgAAAA==.Welil:BAAALgAECgUJCwAAAA==.',
Wh='Whachah:BAAALgAECgQJCAAAAA==.Whatami:BAABLgAECn8XAAQbAAgJqBLzRQD5AQAbAAgJqBLzRQD5AQAYAAIJ7w9wVwBoAAAcAAEJAAALMQA8AAAAAA==.Wholemilk:BAAALgAECgYJDgAAAA==.',
Wi='Wilhellena:BAABLgAECn8dAAILAAcJsh5fAwAdAgALAAcJsh5fAwAdAgAAAA==.Winariel:BAAALgAECgEJAQABLgAECgMJAwAEAAAAAA==.',
Wr='Wrëckagë:BAAALgAECgYJEQAAAA==.',
Wu='Wumbo:BAAALgAECgEJAQAAAA==.',
Xa='Xaiea:BAAALgADCgcJBwAAAA==.Xalatath:BAAALgAECgEJAQAAAA==.Xaldred:BAAALgAECgcJEAABLgAECggJGAAIADcRAA==.Xandir:BAAALgAECgQJEAAAAA==.Xarhunt:BAAALgADCgcJDQAAAA==.Xaric:BAABLgAECn8bAAIBAAYJgh0uMQDmAQABAAYJgh0uMQDmAQAAAA==.',
Xe='Xella:BAAALgAECgQJBAAAAA==.',
Xy='Xyp:BAAALgAECgEJAQABLgAECgQJBQAEAAAAAA==.',
Yi='Yiago:BAAALgAECgEJAQAAAA==.',
Yo='Youknow:BAAALgADCgUJBQAAAA==.',
Yu='Yumiisaki:BAAALgAECgQJBAAAAA==.',
Za='Zahel:BAAALgADCgYJEgAAAA==.Zangbus:BAAALgADCgcJFAAAAA==.Zaranorinn:BAAALgAECgYJDQAAAA==.Zaxhdk:BAEALgADCgkJEgABLgAECgIJAgAEAAAAAA==.',
Ze='Zedex:BAAALgADCgEJAQABLgADCgcJCwAEAAAAAA==.Zedru:BAAALgADCgcJCwAAAA==.Zenstormer:BAAALgADCgQJBAABLgADCggJDAAEAAAAAA==.Zephril:BAAALgADCgEJAQAAAA==.Zerfällt:BAAALgADCgYJCwAAAA==.Zerrus:BAAALgAECgUJBQAAAA==.',
Zh='Zhoryn:BAAALgAECgYJDQAAAA==.',
Zi='Zilvra:BAAALgAECgcJEgAAAA==.Zinrar:BAAALgAECgYJDQAAAA==.Zipagain:BAAALgADCgQJBAAAAA==.Ziparoo:BAABLgAECn8YAAIWAAYJ2QO7OgDXAAAWAAYJ2QO7OgDXAAAAAA==.Zittizle:BAAALgAECgEJAQAAAA==.',
Zr='Zraven:BAAALgAECgYJDQAAAA==.',
['Äl']='Älphawolf:BAAALgAECggJEQAAAA==.',
['Ðê']='Ðêmønicßløøð:BAAALgAECgYJCwAAAA==.',
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
