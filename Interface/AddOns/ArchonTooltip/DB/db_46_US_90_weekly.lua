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

local lookup = {'Rogue-Subtlety','Warlock-Destruction','Warlock-Demonology','Druid-Restoration','Druid-Balance','Paladin-Holy','DemonHunter-Vengeance','DemonHunter-Devourer','Priest-Shadow','Warrior-Fury','DeathKnight-Unholy','Unknown-Unknown','Mage-Frost','Rogue-Outlaw','DemonHunter-Havoc','Hunter-BeastMastery','Hunter-Survival','Hunter-Marksmanship','Monk-Mistweaver','DeathKnight-Blood','Shaman-Restoration','Shaman-Enhancement','Shaman-Elemental','Priest-Holy','Paladin-Retribution','Druid-Feral','DeathKnight-Frost','Mage-Arcane','Warrior-Arms','Priest-Discipline','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Monk-Windwalker','Mage-Fire','Warlock-Affliction',}
local provider = {region='US',realm='Eredar',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aamon:BAAALgAECgQJCgAAAA==.',
Ab='Abacus:BAABLgAECn8WAAIBAAcJTx+oFQBjAgABAAcJTx+oFQBjAgAAAA==.',
Ad='Adam:BAACLgAFFH8GAAMCAAMJLhpQDQCiAAADAAIJxBy1MwCrAAACAAIJsRNQDQCiAAAuAAQKfx4AAwMACQk2IQ4WANECAAMACQlSIA4WANECAAIABQkjJKQNAOsBAAAA.Adedruid:BAABLgAECn8eAAMEAAYJ3hr8SQB6AQAEAAYJ3hr8SQB6AQAFAAYJVB4ACwA+AQAAAA==.Adevoker:BAAALgAECgQJBAAAAA==.Adragon:BAAALgAECgcJDwAAAA==.',
Ae='Aengyl:BAAALgAECgQJBAAAAA==.Aeonne:BAAALgAECgQJCAAAAA==.',
Ak='Akshul:BAAALgAECgYJEAAAAA==.Akurama:BAAALgAECgEJAQAAAA==.',
Al='Aldrea:BAAALgAECgMJAgAAAA==.Allsmiles:BAAALgAECggJEQAAAA==.Allura:BAAALgAECgEJAQAAAA==.Alorian:BAAALgAECgIJAgAAAA==.Alyysha:BAABLgAECn8bAAIGAAcJlwn5RQBgAQAGAAcJlwn5RQBgAQAAAA==.',
Am='Amoon:BAABLgAECn8VAAMHAAYJmRZAAwBPAQAHAAYJ7hRAAwBPAQAIAAYJJhJReAA+AQAAAA==.',
An='Andoriel:BAAALgADCgcJBwAAAA==.Angelrain:BAABLgAECn8hAAIJAAgJWByLDgCaAgAJAAgJWByLDgCaAgAAAA==.',
Ar='Archymedes:BAABLgAECn8WAAIKAAQJJwoWFgDnAAAKAAQJJwoWFgDnAAAAAA==.Arckady:BAAALgAECgEJAQAAAA==.Artharius:BAAALgAECgcJEAAAAA==.',
Au='Auburnbeard:BAAALgADCgYJBgAAAA==.Aumed:BAAALgADCgEJAQAAAA==.',
Av='Averle:BAABLgAECn8rAAICAAYJJAMVCACwAAACAAYJJAMVCACwAAAAAA==.',
Az='Azrran:BAAALgADCgEJAQAAAA==.Aztharot:BAAALgAECgEJAQAAAA==.',
Ba='Badchoices:BAAALgADCgQJBAAAAA==.Badkittie:BAAALgADCgEJAQAAAA==.',
Be='Belinda:BAAALgAECgEJAQABLgAFFAMJCgALAHMfAA==.Bewater:BAAALgADCgcJBwAAAA==.',
Bo='Bobadelphia:BAAALgADCgYJBgABLgAECgYJCwAMAAAAAA==.Bofahdeez:BAAALgAECgcJDQAAAA==.Bogs:BAABLgAECn8cAAINAAgJIiG6IwDkAgANAAgJIiG6IwDkAgAAAA==.Bonedaddy:BAAALgAECgYJBgAAAA==.',
Br='Brewswayne:BAAALgADCgQJBAABLgAECggJDgAMAAAAAA==.Brolic:BAAALgAECgYJEwAAAA==.',
Ca='Cail:BAEALgAECgYJEgAAAA==.Calamìty:BAAALgADCgcJDgABLgAECggJFgAEAN0MAA==.Calisa:BAABLgAECn8ZAAIOAAcJPhquAgBPAgAOAAcJPhquAgBPAgAAAA==.Cardio:BAAALgADCgYJCAAAAA==.Carnifexx:BAAALgAECgQJBAABLgAFFAQJCwAIAIsTAA==.Cassey:BAAALgAECgEJAQAAAA==.',
Ce='Celesteus:BAAALgADCgkJFAAAAA==.',
Ch='Charis:BAAALgAECgYJCwAAAA==.Chigutotems:BAAALgAECgMJAwABLgAECggJEQAMAAAAAA==.Choi:BAAALgAECgUJDwAAAA==.Chooq:BAAALgADCgIJAgAAAA==.Chozen:BAAALgAECgUJEAAAAA==.',
Ci='Cienna:BAAALgAECgQJDAAAAA==.Cigz:BAAALgADCgEJAQAAAA==.Cinch:BAAALgAECgIJAgAAAA==.',
Co='Colinferral:BAAALgAECgYJCAAAAA==.Coulee:BAAALgAECgEJAQABLgAECgcJFQAPAKMdAA==.Cowladin:BAAALgADCgUJBQAAAA==.',
Cr='Crakzkull:BAAALgAECgUJCwAAAA==.Croar:BAAALgAECgMJBAAAAA==.Cronicpain:BAAALgADCgkJCQAAAA==.',
['Cä']='Cäntstandya:BAABLgAECn8cAAMQAAgJYhlYEgClAgAQAAgJYhlYEgClAgARAAIJtA0cKQBpAAAAAA==.',
Da='Daiko:BAAALgADCgMJAwAAAA==.Daks:BAAALgAECggJDgAAAA==.Dargo:BAAALgAECgQJCQAAAA==.Darklucrezia:BAABLgAECn8dAAISAAgJ+xAgJgD1AQASAAgJ+xAgJgD1AQAAAA==.Dazzlefraz:BAAALgAECgQJBAAAAA==.',
De='Demonklunter:BAAALgADCgYJEAAAAA==.',
Di='Dicey:BAAALgADCgMJAwABLgAECgIJAwAMAAAAAA==.',
Do='Dochunter:BAAALgAECgUJBQAAAA==.',
Dr='Dracarius:BAAALgAECgEJAQAAAA==.Drega:BAAALgAECgYJBwAAAA==.Droods:BAAALgAECgQJBQAAAA==.Drtypinkcake:BAAALgAECgYJCgAAAA==.Druskgar:BAABLgAECn8XAAILAAcJYyHhBwABAgALAAcJYyHhBwABAgAAAA==.Dryad:BAAALgAECgEJAQAAAA==.',
Du='Duckster:BAAALgADCgYJBwAAAA==.Dunce:BAABLgAECn8WAAITAAgJ1x0RDACTAgATAAgJ1x0RDACTAgAAAA==.Durkk:BAABLgAECn8ZAAIUAAcJTB+CCwBbAgAUAAcJTB+CCwBbAgAAAA==.Durza:BAAALgAECgQJCQAAAA==.',
['Dä']='Dännydevito:BAAALgADCgQJBAAAAA==.',
Ed='Eduard:BAAALgAECgQJBQAAAA==.',
El='Elanthae:BAAALgAECgIJAgAAAA==.Elysia:BAAALgAECgEJAgAAAA==.',
Er='Erzulie:BAAALgAECgUJBAAAAA==.',
Es='Estara:BAAALgAECgcJEwAAAA==.',
Et='Etali:BAABLgAECn8WAAIKAAcJlxMzDgBCAQAKAAcJlxMzDgBCAQAAAA==.',
Ez='Ezazel:BAAALgADCgUJBwAAAA==.',
Fa='Falorin:BAAALgAECgYJDQAAAA==.Fanis:BAAALgAECgcJEgAAAA==.Fatherwhig:BAAALgAECgEJAgAAAA==.',
Fi='Fidis:BAAALgADCgkJCwAAAA==.Fistsofdeath:BAAALgADCggJCgAAAA==.Fistychub:BAAALgADCgEJAQAAAA==.',
Fl='Flashis:BAAALgAECggJEwAAAA==.Florago:BAAALgAECgEJAQAAAA==.',
Fr='Frakir:BAABLgAECn8ZAAQVAAcJRxR4DwBJAQAVAAcJRxR4DwBJAQAWAAEJ5gWlLAAzAAAXAAEJkAYQkwAjAAAAAA==.Fritzz:BAAALgAECgcJEQAAAA==.Frog:BAAALgAECgEJAgAAAA==.',
Fu='Furrypaw:BAAALgAECgcJDAAAAA==.',
Fw='Fwapp:BAACLgAFFH8MAAIGAAQJtRp4AwBOAQAGAAQJtRp4AwBOAQAuAAQKfxcAAgYACAlrIc4LAL8CAAYACAlrIc4LAL8CAAAA.',
Ga='Galynisse:BAAALgAECgQJEgAAAA==.',
Ge='Gedorah:BAAALgAECgYJEAABLgAECggJHgAXALIgAA==.',
Gh='Ghaspy:BAAALgAECgEJAQAAAA==.Ghoste:BAAALgADCgMJAwAAAA==.Ghrex:BAAALgAECgEJAQAAAA==.',
Gi='Gijaick:BAABLgAECn8dAAMDAAcJYBkJFQBoAQADAAcJYBkJFQBoAQACAAEJHg7wcwAxAAAAAA==.',
Gl='Glaivethrow:BAAALgAECggJEQAAAA==.Glizzo:BAAALgAECgYJDAAAAA==.',
Go='Gochujjang:BAAALgAECgYJDQAAAA==.Goldhawk:BAAALgADCgYJCgAAAA==.Gotchá:BAAALgAECgEJAgAAAA==.Gotwiped:BAAALgAECgUJBgAAAA==.',
Gr='Grimgor:BAAALgAECgcJAQAAAA==.',
Ha='Hahaheals:BAAALgAECgMJBAAAAA==.Hakhar:BAAALgADCgMJAwAAAA==.Hatter:BAAALgAECgcJEgAAAA==.',
He='Healsus:BAAALgAECgMJAwAAAA==.Heimlish:BAAALgAECgEJAQAAAA==.Hellraiser:BAAALgAECgYJCgAAAA==.Hermione:BAAALgAECgQJCwAAAA==.Hexecution:BAAALgADCgIJAgAAAA==.',
Hi='Hiddendragon:BAAALgAECgEJAQAAAA==.',
Ho='Holydarkness:BAAALgADCgcJCQAAAA==.Hoofjob:BAAALgADCggJDgABLgAECgkJKAAYAJEaAA==.Hoplite:BAAALgADCgYJCAAAAA==.Hotot:BAAALgADCgMJAwAAAA==.',
Hu='Huffpuffle:BAAALgAECgEJAQAAAA==.',
['Hô']='Hôwl:BAAALgAECgYJBgAAAA==.',
Ic='Icdeathg:BAABLgAECn8ZAAIIAAgJoBOCUwCpAQAIAAgJoBOCUwCpAQAAAA==.',
Ik='Iktaar:BAAALgAECgMJAwAAAA==.',
Il='Illidami:BAAALgADCgYJBgAAAA==.Illidamngirl:BAAALgADCgYJBgABLgAECgYJEwAMAAAAAA==.',
Im='Imperius:BAACLgAFFH8MAAIZAAQJgAx4BQA5AQAZAAQJgAx4BQA5AQAuAAQKfyIAAhkACAnEJBYOAB0DABkACAnEJBYOAB0DAAAA.',
In='Ines:BAABLgAECn8hAAILAAgJ8yMOAwB5AgALAAgJ8yMOAwB5AgAAAA==.Insomiax:BAAALgAECgQJBQAAAA==.Insta:BAABLgAECn8fAAIKAAcJsRrYIwA3AgAKAAcJsRrYIwA3AgAAAA==.Inter:BAABLgAECn8fAAIUAAgJcCM5BAALAwAUAAgJcCM5BAALAwAAAA==.',
Ir='Iridi:BAAALgADCgEJAQAAAA==.Iritall:BAAALgADCgcJCwAAAA==.',
It='Ithamburglar:BAAALgAECgQJBQAAAA==.',
Iz='Izureka:BAAALgADCgYJBgAAAA==.',
Ja='Jackidaytona:BAAALgAECgcJBwAAAA==.Jakaru:BAAALgAECgYJEgAAAA==.Jankadish:BAAALgAECgcJEwAAAA==.Jarre:BAACLgAFFH8GAAIEAAQJrggkDgAFAQAEAAQJrggkDgAFAQAuAAQKfyYAAgQACAmzICUKAPICAAQACAmzICUKAPICAAAA.Jaspirian:BAAALgADCggJFAAAAA==.Jazzil:BAAALgADCgcJCgAAAA==.',
Jb='Jbaconcheese:BAAALgADCgcJCwAAAA==.',
Je='Jehmothy:BAAALgADCgEJAQAAAA==.Jerome:BAAALgAECgEJAQAAAA==.',
Jo='Jotabop:BAAALgAECgQJBgAAAA==.',
Ju='Juicy:BAAALgAECgYJEwAAAA==.',
Ka='Kabu:BAAALgAECgcJBwAAAA==.Kalia:BAABLgAECn8fAAINAAgJZxgSPgB/AgANAAgJZxgSPgB/AgABLgADCgEJAQAMAAAAAA==.Kalitra:BAAALgADCgMJAwABLgADCgEJAQAMAAAAAA==.Katoumae:BAACLgAFFH8FAAIaAAIJGxAEAgCyAAAaAAIJGxAEAgCyAAAuAAQKfxsAAhoACAm0GvMFAKMCABoACAm0GvMFAKMCAAAA.Katoumey:BAAALgADCgEJAQABLgAFFAIJBQAaABsQAA==.',
Ke='Keratin:BAABLgAECn8UAAIbAAcJESMDAgC2AgAbAAcJESMDAgC2AgAAAA==.',
Kh='Khumi:BAABLgAECn8XAAISAAgJYSDtEgCbAgASAAgJYSDtEgCbAgABLgAFFAcJDgAZAJ0eAA==.',
Ki='Kinan:BAABLgAECn8UAAMSAAcJZx8/FwBxAgASAAcJOx4/FwBxAgAQAAUJYh7AEQBvAQAAAA==.Kita:BAAALgAECggJDAAAAA==.',
Kk='Kkaarrkk:BAAALgAECgUJBQAAAA==.',
Kr='Krindon:BAAALgAECgYJBgAAAA==.',
Ku='Kureiji:BAAALgADCgEJAQAAAA==.',
Ky='Kythin:BAAALgADCgEJAQAAAA==.',
La='Laww:BAAALgADCgcJBwAAAA==.',
Le='Lecroix:BAAALgADCgUJBQAAAA==.Leonus:BAAALgAECgMJAwAAAA==.Lethalforce:BAAALgADCgMJAwAAAA==.',
Li='Liandri:BAAALgADCgEJAgAAAA==.Lightchild:BAAALgADCggJCAAAAA==.Lillith:BAAALgAECgMJAwAAAA==.Livewire:BAAALgAECgEJAQAAAA==.',
Lo='Lokohmojo:BAAALgADCgcJFgAAAA==.Lomponic:BAEALgAECgYJEwAAAA==.Loomadin:BAAALgADCgYJCQAAAA==.',
Lu='Lunethra:BAABLgAECn8bAAIQAAgJ5hJ/KwAGAgAQAAgJ5hJ/KwAGAgAAAA==.',
Ma='Magerag:BAABLgAECn8XAAMNAAgJfx2tLwCzAgANAAgJfx2tLwCzAgAcAAIJQBpFFQBzAAAAAA==.Manamontana:BAACLgAFFH8MAAILAAQJ2BGyBwBKAQALAAQJ2BGyBwBKAQAuAAQKfxkAAgsACAn4H3goAJkCAAsACAn4H3goAJkCAAAA.Marumo:BAAALgAECgMJBgAAAA==.',
Mc='Mcribz:BAACLgAFFH8KAAILAAMJcx+7HwAcAQALAAMJcx+7HwAcAQAuAAQKfx0AAgsACAl5IyAZAOUCAAsACAl5IyAZAOUCAAAA.',
Me='Meelonusk:BAAALgAECgQJBwAAAA==.Mess:BAAALgADCgkJDAAAAA==.Messah:BAAALgAECgEJAQAAAA==.',
Mi='Michaelcoyle:BAABLgAECn8WAAIQAAYJChgHRACgAQAQAAYJChgHRACgAQAAAA==.Midnightcrow:BAAALgADCgcJBwAAAA==.Milo:BAABLgAECn8jAAMKAAgJRiWIAADUAgAKAAgJRiWIAADUAgAdAAgJbhwVBAC0AgAAAA==.Mishra:BAAALgAECgUJBQAAAA==.Mitra:BAAALgAECgQJDAAAAA==.',
Mo='Moesko:BAAALgAECgcJDQAAAA==.Mof:BAAALgADCgEJAQAAAA==.Mohawkk:BAAALgADCgYJBgAAAA==.Monktup:BAAALgAECgYJCwAAAA==.Monnehbaggs:BAABLgAECn8eAAMYAAgJpR3+DQB7AgAYAAgJpR3+DQB7AgAeAAIJLRI+FgBIAAAAAA==.Mortalidad:BAAALgADCgQJBAAAAA==.',
Mu='Muin:BAAALgADCgYJEQAAAA==.Murdersamich:BAAALgAECgQJBwAAAA==.',
My='Mybigcrits:BAAALgAECgYJDAAAAA==.',
['Mà']='Màevë:BAAALgAECgEJAQAAAA==.',
Na='Nairdax:BAAALgADCgEJAQAAAA==.Nalmec:BAAALgAECgYJDwAAAA==.Naysayre:BAAALgAECgYJDgAAAA==.',
Ne='Nebody:BAAALgAECgEJAQAAAA==.Necriss:BAAALgAECgcJEAAAAA==.Nevin:BAAALgAECgEJAQAAAA==.',
Ni='Nilowin:BAABLgAECn8VAAIBAAcJMAzCKgCnAQABAAcJMAzCKgCnAQAAAA==.',
No='Noshards:BAAALgAECgcJDQAAAA==.Notericdh:BAAALgAECgQJCQAAAA==.',
Og='Oghom:BAAALgADCgcJCgAAAA==.',
Oh='Ohnoitzgumby:BAAALgAECgYJDQAAAA==.',
Om='Omiko:BAAALgADCgUJBwAAAA==.',
Op='Opeep:BAAALgADCgcJGQAAAA==.',
Os='Osos:BAAALgAECgYJCQAAAA==.',
Pa='Paladimdab:BAAALgADCgkJCQAAAA==.Papachance:BAAALgAECgMJAwAAAA==.Papafrank:BAAALgADCgkJEAAAAA==.Paradis:BAAALgADCgcJBwAAAA==.Pazuzu:BAAALgADCgYJBgAAAA==.',
Pe='Peepo:BAAALgAECgEJAQAAAA==.',
Pi='Pinga:BAAALgAECgIJBAABLgAECgcJIAAfAHQjAA==.Pinkberry:BAAALgAECgQJBAAAAA==.Pintcube:BAAALgADCgYJCAAAAA==.',
Pl='Pljeskavica:BAAALgAECgQJBAAAAA==.Plox:BAAALgAECgMJAwAAAA==.',
Po='Port:BAABLgAECn8YAAIEAAYJ3h5RLgD0AQAEAAYJ3h5RLgD0AQAAAA==.Potroastjr:BAAALgADCgEJAgABLgAECgEJAQAMAAAAAA==.',
Pr='Protocol:BAAALgAECgMJAwAAAA==.Prïestess:BAAALgADCgYJCwAAAA==.',
Ps='Pseriph:BAABLgAECn8ZAAICAAcJ3BZlCwAKAgACAAcJ3BZlCwAKAgAAAA==.',
Ra='Radamantis:BAAALgAECgEJAQAAAA==.Raenon:BAAALgADCgcJCgAAAA==.Raggnar:BAABLgAECn8eAAIXAAgJsiDtDgC3AgAXAAgJsiDtDgC3AgAAAA==.Ragingwaters:BAAALgADCgYJCAAAAA==.Ranvir:BAAALgADCgkJEAAAAA==.Raun:BAABLgAECn8ZAAMZAAcJJh9FMwBVAgAZAAcJJh9FMwBVAgAGAAMJIxEfcgCyAAAAAA==.',
Re='Regnarr:BAAALgADCgEJAQAAAA==.Relaire:BAAALgAECgYJEAAAAA==.Resonate:BAAALgADCgQJBAABLgAECgcJCgAMAAAAAA==.',
Ri='Rikane:BAAALgADCgcJDAABLgADCgcJEgAMAAAAAA==.Riku:BAABLgAECn8UAAIaAAcJWhwNCQBHAgAaAAcJWhwNCQBHAgAAAA==.',
Ro='Rock:BAAALgAECgYJBgAAAA==.Roguey:BAAALgAECgYJDgAAAA==.Roots:BAAALgAECgEJAgAAAA==.',
Ry='Ryveri:BAABLgAECn8cAAIKAAgJXBesHQBhAgAKAAgJXBesHQBhAgAAAA==.',
Sa='Sablehide:BAABLgAECn8XAAIgAAcJahE9CgBCAQAgAAcJahE9CgBCAQAAAA==.Sanaron:BAAALgADCgIJAgAAAA==.Sanaty:BAAALgAECgQJCQAAAA==.Saryn:BAAALgAECgYJDQAAAA==.Sathanus:BAAALgAECgEJAQAAAA==.',
Se='Searate:BAAALgADCgcJEgAAAA==.Seaside:BAACLgAFFH8HAAILAAMJXCPYHAAvAQALAAMJXCPYHAAvAQAuAAQKfxYAAwsABwk9JcwEAEMCAAsABwk9JcwEAEMCABQAAgmEC+w/AE4AAAAA.Secrett:BAAALgAECgYJCwAAAA==.Sephyxia:BAABLgAECn8eAAIUAAgJIBPWBAB5AQAUAAgJIBPWBAB5AQAAAA==.Serryon:BAAALgADCgIJAgAAAA==.',
Sh='Shadowwzz:BAAALgADCgEJAQAAAA==.Shoçknezz:BAAALgAECgIJAgAAAA==.',
Si='Silverwolf:BAABLgAECn8gAAIWAAgJEhxAAgDYAQAWAAgJEhxAAgDYAQAAAA==.Simplyunlock:BAABLgAECn8XAAMDAAgJDgwTWQC9AQADAAgJDgwTWQC9AQACAAIJ5wWFZgBDAAAAAA==.Simplyvoided:BAAALgADCgYJBgAAAA==.Sinverguenza:BAAALgAECgMJBQAAAA==.Sizzlechop:BAAALgAECgcJEwAAAA==.',
Sk='Skizzak:BAAALgADCgQJBAABLgAFFAMJCgALAHMfAA==.Skweeks:BAAALgAECgIJAgAAAA==.',
Sm='Smelvin:BAAALgAECggJEQABLgAECgQJBwAMAAAAAA==.Smoko:BAAALgAECgIJAgABLgAECgUJBQAMAAAAAA==.',
Sn='Snailslolol:BAAALgADCgUJBQAAAA==.Snakey:BAACLgAFFH8FAAIgAAIJSgjyGwCQAAAgAAIJSgjyGwCQAAAuAAQKfyEAAyAACAmmFDYaAPkBACAACAmmFDYaAPkBACEABgl5BHEmAO8AAAAA.',
So='Solara:BAABLgAECn8UAAQJAAYJRxqZIgDCAQAJAAYJRxqZIgDCAQAYAAEJQAL9hgApAAAeAAEJXgKSXgAkAAAAAA==.Soleill:BAAALgAECgcJBwAAAA==.Sondan:BAAALgADCgMJAwAAAA==.Songs:BAAALgAECgEJAQABLgAECgYJFgAiAP0gAA==.',
Sp='Spellpowa:BAAALgAECgYJCgAAAA==.',
Ss='Ssminion:BAAALgADCgEJAQAAAA==.',
St='Stormwing:BAAALgAECgYJDgAAAA==.Strecagosa:BAAALgAECgYJDQAAAA==.',
Sv='Svenn:BAAALgAECgYJBgAAAA==.',
Sy='Synni:BAAALgADCgEJAQAAAA==.',
['Sÿ']='Sÿnÿster:BAAALgADCgMJAwABLgAECggJHQASAPsQAA==.',
Ta='Talron:BAAALgAECgQJBAAAAA==.Tastytay:BAAALgADCgMJAwAAAA==.Tatertots:BAABLgAECn8YAAMbAAcJlR+xAwBEAgAbAAcJlR+xAwBEAgALAAMJ8hNo7ACmAAAAAA==.',
Te='Tea:BAABLgAECn8ZAAIQAAcJWyGZEgCiAgAQAAcJWyGZEgCiAgAAAA==.Teal:BAAALgADCgYJBgAAAA==.Templyn:BAAALgAECgQJBQAAAA==.Tenebrarum:BAAALgAECgYJEwAAAA==.Testorooni:BAABLgAECn8ZAAIQAAcJkBgtMwDjAQAQAAcJkBgtMwDjAQAAAA==.',
Th='Thakodi:BAAALgADCgkJCQAAAA==.Thannos:BAAALgADCgEJAQAAAA==.Tharvan:BAAALgADCgcJDAAAAA==.Thedeadman:BAABLgAECn8cAAILAAgJtB1hBQAyAgALAAgJtB1hBQAyAgAAAA==.Thepriestg:BAAALgAECgEJAQAAAA==.Thiccksilver:BAAALgADCgcJBwABLgAECggJFwADAHYbAA==.Thompson:BAAALgAECgQJCQAAAA==.Thunderflaps:BAAALgAECgQJBAAAAA==.Thyrus:BAABLgAECn8gAAMfAAcJdCOEBwDFAgAfAAcJdCOEBwDFAgAhAAEJqgLtRAAjAAAAAA==.',
Ti='Tirna:BAABLgAECn8YAAIjAAcJZg2wBACOAQAjAAcJZg2wBACOAQAAAA==.',
To='Tomsellock:BAABLgAECn8WAAMkAAcJjhBvBwDcAQAkAAcJjhBvBwDcAQADAAEJugMVLAEmAAAAAA==.Torvi:BAAALgADCgMJAwAAAA==.',
Tr='Transmørtuus:BAAALgAECgQJCQAAAA==.Treehug:BAAALgAECgYJEgAAAA==.Triple:BAAALgADCgUJAwABLgAECgYJCQAMAAAAAA==.',
Tu='Tullen:BAEALgAECgcJEwAAAA==.Turanos:BAAALgAECgEJAQAAAA==.',
Tw='Tweyen:BAAALgAECgEJAQAAAA==.',
Ty='Tyindaris:BAAALgAECgQJCAAAAA==.Tyloregeth:BAABLgAECn8YAAIJAAgJCREGHQDzAQAJAAgJCREGHQDzAQAAAA==.',
Ul='Ulfrunn:BAAALgADCgYJBgAAAA==.Ultrachad:BAACLgAFFH8GAAILAAQJhxCoBwBKAQALAAQJhxCoBwBKAQAuAAQKfx4AAgsACAlFI/0TAAMDAAsACAlFI/0TAAMDAAAA.',
Um='Umami:BAABLgAECn8aAAIKAAYJ4hhPDQBNAQAKAAYJ4hhPDQBNAQAAAA==.',
Un='Unggoy:BAACLgAFFH8QAAMSAAYJqBnvAgAkAgASAAYJqBnvAgAkAgAQAAEJVwz5FQBVAAAuAAQKfyAAAhIACQmLJawBAKYDABIACQmLJawBAKYDAAAA.',
Ur='Urianna:BAAALgAECgIJAwAAAA==.',
Va='Vaelthirion:BAABLgAECn8aAAINAAgJ8hJdhADJAQANAAgJ8hJdhADJAQAAAA==.Vahidamus:BAAALgAECgEJAQAAAA==.Valkaryon:BAAALgAECgcJCgAAAA==.Valmirax:BAAALgADCgcJBwAAAA==.Valton:BAABLgAECn8eAAIZAAYJQAcxMgDSAAAZAAYJQAcxMgDSAAAAAA==.',
Ve='Vegetation:BAAALgAECgIJAwAAAA==.Velenestus:BAAALgAECgMJBgAAAA==.',
Wa='Wackaman:BAAALgAECgYJEwAAAA==.Warpig:BAAALgAECgQJDAAAAA==.Wasps:BAAALgAECgYJCwAAAA==.',
We='Wegmaniac:BAAALgADCgYJCAAAAA==.Welastrexa:BAAALgADCgUJBQAAAA==.',
Wi='Wickedclöwn:BAAALgADCgMJAwAAAA==.Winchester:BAAALgADCgIJAgAAAA==.Windhorn:BAAALgADCgEJAQAAAA==.Winds:BAABLgAECn8WAAIiAAYJ/SBgFwAqAgAiAAYJ/SBgFwAqAgAAAA==.',
Wn='Wntrizcoming:BAAALgADCgMJBQAAAA==.',
Wo='Wolfquota:BAABLgAECn8eAAMXAAgJKCJCCQD+AgAXAAgJKCJCCQD+AgAWAAQJ7RNSHgDpAAAAAA==.Wolftime:BAAALgADCgUJBQAAAA==.Wombaa:BAABLgAECn8cAAILAAgJXiRdCgBIAwALAAgJXiRdCgBIAwAAAA==.',
Wr='Wrathmo:BAAALgAFFAEJAQAAAA==.Wrolie:BAAALgADCgMJAwAAAA==.',
['Wê']='Wêêdyys:BAAALgADCgMJBAAAAA==.',
Xy='Xyr:BAAALgADCgcJBwABLgAECgYJEAAMAAAAAA==.',
Za='Zandalia:BAAALgAECgMJAwAAAA==.',
Ze='Zemphoths:BAAALgAECgUJBgAAAA==.',
Zo='Zoa:BAAALgADCgYJBgAAAA==.Zolton:BAAALgADCgMJAwAAAA==.',
['Åe']='Åequitas:BAAALgAECgYJCQAAAA==.',
['ßa']='ßahamut:BAAALgAECgEJAQAAAA==.',
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
