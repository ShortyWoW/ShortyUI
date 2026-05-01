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

local lookup = {'Rogue-Subtlety','Warlock-Destruction','Warlock-Demonology','Druid-Restoration','Druid-Balance','Evoker-Augmentation','Shaman-Elemental','Warrior-Arms','Warrior-Fury','Warrior-Protection','Monk-Windwalker','Paladin-Holy','DemonHunter-Devourer','DemonHunter-Vengeance','Priest-Shadow','DeathKnight-Unholy','Unknown-Unknown','Priest-Holy','Mage-Frost','DemonHunter-Havoc','Rogue-Outlaw','Hunter-BeastMastery','Hunter-Survival','Hunter-Marksmanship','Monk-Mistweaver','DeathKnight-Blood','Druid-Guardian','Shaman-Restoration','Shaman-Enhancement','Priest-Discipline','Mage-Fire','Paladin-Retribution','Druid-Feral','DeathKnight-Frost','Mage-Arcane','Evoker-Preservation','Rogue-Assassination','Evoker-Devastation','Warlock-Affliction','Monk-Brewmaster',}
local provider = {region='US',realm='Eredar',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aamon:BAAALgAECgQJCgAAAA==.',
Ab='Abacus:BAABLgAECn8dAAIBAAcJ2iOeAwBkAgABAAcJ2iOeAwBkAgAAAA==.',
Ad='Adam:BAACLgAFFH8HAAMCAAMJLhpRDQCiAAADAAIJxBzCMwCrAAACAAIJsRNRDQCiAAAuAAQKfx8AAwMACQkXIV8WAM4CAAMACQkzIF8WAM4CAAIABQkjJKYNAOsBAAAA.Adedruid:BAABLgAECn8eAAMEAAYJ3hoCSgB6AQAEAAYJ3hoCSgB6AQAFAAYJVB6ZGAA5AQAAAA==.Adevoker:BAAALgAECgQJBAAAAA==.Adragon:BAABLgAECn8XAAIGAAgJjBb+CAD9AQAGAAgJjBb+CAD9AQAAAA==.',
Ae='Aengyl:BAAALgAECgQJBAAAAA==.Aeonne:BAAALgAECgYJDAAAAA==.',
Ak='Akshul:BAABLgAECn8UAAIHAAYJ3g0/RgAvAQAHAAYJ3g0/RgAvAQAAAA==.Akurama:BAAALgAECgYJBwAAAA==.',
Al='Aldrea:BAAALgAECgMJAwAAAA==.Allsmiles:BAABLgAECn8UAAQIAAkJuh3sCAAhAgAIAAgJexrsCAAhAgAJAAUJChmxTQBwAQAKAAMJ7R0kKgDvAAAAAA==.Allura:BAAALgAECgEJAQAAAA==.Alorian:BAAALgAECgIJAgAAAA==.Alttharius:BAAALgADCgQJBAABLgAECggJFAALAEcfAA==.Alyysha:BAABLgAECn8bAAIMAAcJlwn6RQBgAQAMAAcJlwn6RQBgAQAAAA==.',
Am='Amoon:BAABLgAECn8bAAMNAAYJKBqzIwBeAQANAAYJhxezIwBeAQAOAAYJ7hRgBwBFAQAAAA==.',
An='Andoriel:BAAALgADCgcJBwAAAA==.Angelrain:BAABLgAECn8lAAIPAAgJWByNDgCaAgAPAAgJWByNDgCaAgAAAA==.',
Ar='Archymedes:BAABLgAECn8ZAAIJAAUJ4A4NKQD9AAAJAAUJ4A4NKQD9AAAAAA==.Arckady:BAAALgAECgEJAQAAAA==.Artharius:BAABLgAECn8UAAILAAgJRx87EQBvAgALAAgJRx87EQBvAgAAAA==.',
Au='Auburnbeard:BAAALgADCgYJBgAAAA==.Aumed:BAAALgADCgEJAQAAAA==.',
Av='Averle:BAABLgAECn81AAICAAYJMwTtDwCzAAACAAYJMwTtDwCzAAAAAA==.',
Az='Azrran:BAAALgADCgEJAQAAAA==.Aztharot:BAAALgAECgEJAQAAAA==.',
Ba='Badchoices:BAAALgADCgQJBAAAAA==.Badkittie:BAAALgADCgEJAQAAAA==.',
Be='Belinda:BAAALgAECgEJAQABLgAFFAUJEQAQANwiAA==.Bewater:BAAALgADCgcJBwAAAA==.',
Bo='Bobadelphia:BAAALgADCgYJBgABLgAECgYJEQARAAAAAA==.Bofahdeez:BAABLgAECn8UAAMPAAgJ5wuiFQBTAQAPAAcJNAuiFQBTAQASAAcJWQ60PABHAQAAAA==.Bogs:BAACLgAFFH8GAAITAAMJMhpVLgAQAQATAAMJMhpVLgAQAQAuAAQKfxwAAhMACAkiIbojAOQCABMACAkiIbojAOQCAAAA.Bonedaddy:BAAALgAECgYJBgAAAA==.',
Br='Brewswayne:BAAALgADCgQJBAABLgAECgkJEQARAAAAAA==.Brolic:BAABLgAECn8aAAMUAAcJoB3VFgATAgAUAAcJoB3VFgATAgANAAEJ5wcYlQAqAAAAAA==.',
Ca='Cail:BAEALgAECgcJEwAAAA==.Calamìty:BAAALgADCgcJDgAAAA==.Calisa:BAABLgAECn8gAAIVAAcJFhyuAgBPAgAVAAcJFhyuAgBPAgAAAA==.Cardio:BAAALgADCgYJCAAAAA==.Carnifexx:BAAALgAECgQJBAAAAA==.Cassey:BAAALgAECgEJAQAAAA==.',
Ce='Celesteus:BAAALgADCgkJFAAAAA==.',
Ch='Charis:BAAALgAECgYJCwAAAA==.Chigutotems:BAAALgAECgYJCgABLgAECgkJFQANAFcVAA==.Choi:BAAALgAECgUJDwAAAA==.Chooq:BAAALgADCgIJAgAAAA==.Chozen:BAAALgAECgUJEAAAAA==.Chumlee:BAAALgADCgQJBAAAAA==.',
Ci='Cienna:BAAALgAECgYJDgAAAA==.Cigz:BAAALgADCgEJAQAAAA==.Cinch:BAAALgAECgIJAgAAAA==.',
Co='Colinferral:BAAALgAECgYJCAAAAA==.Coulee:BAAALgAECgEJAgABLgAECgcJFgAUAJAeAA==.Cowladin:BAAALgADCgUJBQAAAA==.',
Cr='Crakzkull:BAAALgAECgUJCwAAAA==.Croar:BAAALgAECgMJBAAAAA==.Cronicpain:BAAALgADCgkJCQAAAA==.',
['Cä']='Cäntstandya:BAACLgAFFH8GAAMWAAMJWg7XGwD1AAAWAAMJWg7XGwD1AAAXAAIJqgrPEACRAAAuAAQKfxwAAxYACAliGVoSAKUCABYACAliGVoSAKUCABcAAgm0DR8pAGkAAAAA.',
Da='Daiko:BAAALgAECgYJBgAAAA==.Daks:BAAALgAECgkJEQAAAA==.Dargo:BAAALgAECgQJDQAAAA==.Darklucrezia:BAACLgAFFH8GAAMWAAMJcxJhGQAAAQAWAAMJcxJhGQAAAQAYAAIJLQItEgBaAAAuAAQKfyIAAhgACAkOESImAPUBABgACAkOESImAPUBAAAA.Dazzlefraz:BAAALgAECgQJBAAAAA==.',
De='Demonklunter:BAAALgADCgYJEAAAAA==.Destructoid:BAAALgAECgEJAQAAAA==.',
Di='Dicey:BAAALgADCgMJAwABLgAECgMJBQARAAAAAA==.',
Do='Dochunter:BAAALgAECgUJBQAAAA==.',
Dr='Dracarius:BAAALgAECgEJAQAAAA==.Drega:BAAALgAECgYJBwAAAA==.Droods:BAAALgAECgQJBQAAAA==.Drtypinkcake:BAAALgAECgYJEAAAAA==.Druskgar:BAABLgAECn8ZAAIQAAgJwyFjEgAnAgAQAAgJwyFjEgAnAgAAAA==.Dryad:BAAALgAECgEJAQAAAA==.',
Du='Duckster:BAAALgADCgYJBwAAAA==.Dunce:BAABLgAECn8YAAIZAAgJDh4WDACRAgAZAAgJDh4WDACRAgAAAA==.Durkk:BAABLgAECn8gAAIaAAcJhx8EBwCyAQAaAAcJhx8EBwCyAQAAAA==.Durza:BAAALgAECgQJCQAAAA==.',
['Dä']='Dännydevito:BAAALgADCgQJBAAAAA==.',
Ed='Eduard:BAAALgAECgYJCQAAAA==.',
El='Elanthae:BAAALgAECgIJBAAAAA==.Elysia:BAAALgAECgEJAgAAAA==.',
Er='Erzulie:BAAALgAECgUJBAAAAA==.',
Es='Estara:BAABLgAECn8aAAIbAAcJdwzMFgAIAQAbAAcJdwzMFgAIAQAAAA==.',
Et='Etali:BAABLgAECn8XAAIJAAcJlxNOFwB4AQAJAAcJlxNOFwB4AQAAAA==.',
Ez='Ezazel:BAAALgADCgUJBwAAAA==.',
Fa='Faite:BAAALgADCgUJBQAAAA==.Falorin:BAAALgAECgYJDwAAAA==.Fanis:BAABLgAECn8YAAIYAAcJlhESDAANAQAYAAcJlhESDAANAQAAAA==.Fatherwhig:BAAALgAECgEJAgAAAA==.',
Fi='Fidis:BAAALgADCgkJCwAAAA==.Fistsofdeath:BAAALgADCggJCgAAAA==.Fistychub:BAAALgADCgEJAQAAAA==.',
Fl='Flashis:BAAALgAECggJEwAAAA==.Florago:BAAALgAECgEJAQAAAA==.',
Fr='Frakir:BAABLgAECn8gAAQcAAcJ2xS7GQCVAQAcAAcJ2xS7GQCVAQAdAAIJfASjLAAzAAAHAAEJkAYfkwAjAAAAAA==.Fritzz:BAAALgAECgcJEgAAAA==.Frog:BAAALgAECgEJAgAAAA==.',
Fu='Furrypaw:BAAALgAECgcJEwAAAA==.',
Fw='Fwapp:BAACLgAFFH8RAAIMAAUJLh6gBACrAQAMAAUJLh6gBACrAQAuAAQKfxcAAgwACAlrIcgLAL8CAAwACAlrIcgLAL8CAAAA.',
Ga='Galvanize:BAAALgAECgEJAQAAAA==.Galynisse:BAABLgAECn8bAAMeAAUJbBrTDwCRAQAeAAUJbBrTDwCRAQASAAMJ7A4MZQCZAAAAAA==.',
Ge='Gedorah:BAABLgAECn8UAAIfAAYJ+xdcAgBwAQAfAAYJ+xdcAgBwAQABLgAFFAMJBQAHABYUAA==.',
Gh='Ghaspy:BAAALgAECgUJBgAAAA==.Ghoste:BAAALgADCgMJAwAAAA==.Ghrex:BAAALgAECgEJAQAAAA==.',
Gi='Gijaick:BAABLgAECn8jAAMDAAgJMRfsJgCTAQADAAgJMRfsJgCTAQACAAEJHg71cwAxAAAAAA==.',
Gl='Glaivethrow:BAABLgAECn8VAAINAAkJVxUIQAD0AQANAAkJVxUIQAD0AQAAAA==.Glizzo:BAAALgAECgYJDAAAAA==.',
Go='Gochujjang:BAAALgAECgYJDQAAAA==.Goldhawk:BAAALgAECgMJAwAAAA==.Gotchá:BAAALgAECgEJAwAAAA==.Gotwiped:BAAALgAECgcJCAAAAA==.',
Gr='Grimgor:BAAALgAECgcJAQAAAA==.',
Ha='Hahaheals:BAAALgAECgMJBAAAAA==.Hakhar:BAAALgADCgMJAwAAAA==.Hatter:BAAALgAECgcJEwAAAA==.',
He='Healsus:BAAALgAECgMJAwAAAA==.Heimlish:BAAALgAECgEJAQAAAA==.Hellraiser:BAAALgAECgYJEAAAAA==.Hermione:BAAALgAECgYJDQAAAA==.Hexecution:BAAALgADCgIJAgAAAA==.',
Hi='Hiddendragon:BAAALgAECgEJAQAAAA==.',
Ho='Holydarkness:BAAALgADCgcJCQAAAA==.Holykiller:BAAALgAECgEJAQAAAA==.Hoofjob:BAAALgADCggJDgABLgAECgkJMQAeAEEdAA==.Hoplite:BAAALgADCgYJCAAAAA==.Hotot:BAAALgADCgMJAwAAAA==.',
Hu='Huffpuffle:BAAALgAECgUJBgAAAA==.',
['Hô']='Hôwl:BAAALgAECgYJCwAAAA==.',
Ic='Icdeathg:BAABLgAECn8bAAINAAgJRxWFUwCpAQANAAgJRxWFUwCpAQAAAA==.',
Ik='Iktaar:BAAALgAECgQJBAAAAA==.',
Il='Illidami:BAAALgADCgkJCwAAAA==.Illidamngirl:BAAALgADCgYJBgABLgAECgYJEwARAAAAAA==.',
Im='Imperius:BAACLgAFFH8RAAIgAAUJThN+DgBNAQAgAAUJThN+DgBNAQAuAAQKfyMAAiAACAnbJBwOAB0DACAACAnbJBwOAB0DAAAA.',
In='Ines:BAABLgAECn8pAAIQAAgJ6iS3BQDHAgAQAAgJ6iS3BQDHAgAAAA==.Insomiax:BAAALgAECggJDQAAAA==.Insta:BAABLgAECn8iAAIJAAcJyRraIwA3AgAJAAcJyRraIwA3AgAAAA==.Inter:BAABLgAECn8oAAIaAAkJ+iHoAQBfAgAaAAkJ+iHoAQBfAgAAAA==.',
Ir='Iridi:BAAALgADCgEJAQAAAA==.Iritall:BAAALgADCgcJCwAAAA==.',
It='Ithamburglar:BAAALgAECgQJBQAAAA==.',
Iz='Izureka:BAAALgADCgYJBgAAAA==.',
Ja='Jackidaytona:BAAALgAECgcJBwAAAA==.Jakaru:BAAALgAECgYJEgAAAA==.Jankadish:BAAALgAECgcJEwAAAA==.Jarre:BAACLgAFFH8GAAIEAAQJrggmDgAFAQAEAAQJrggmDgAFAQAuAAQKfycAAgQACAmzICUKAPICAAQACAmzICUKAPICAAAA.Jaspirian:BAAALgADCggJFAAAAA==.Jazzil:BAAALgADCgcJCgAAAA==.',
Jb='Jbaconcheese:BAAALgADCgcJCwAAAA==.',
Je='Jehmothy:BAAALgADCgEJAQAAAA==.Jerome:BAAALgAECgEJAQAAAA==.',
Jo='Jotabop:BAAALgAECgQJBgAAAA==.',
Ju='Juicy:BAABLgAECn8UAAIXAAcJ5xV8CgC5AQAXAAcJ5xV8CgC5AQAAAA==.',
Ka='Kabu:BAAALgAECgcJBwAAAA==.Kalia:BAABLgAECn8oAAITAAkJ9xeMEwA+AgATAAkJ9xeMEwA+AgABLgADCgEJAQARAAAAAA==.Kalitra:BAAALgADCgMJAwABLgADCgEJAQARAAAAAA==.Katoumae:BAACLgAFFH8JAAIhAAQJ8BRpAQBtAQAhAAQJ8BRpAQBtAQAuAAQKfxsAAiEACAm0GvUFAKMCACEACAm0GvUFAKMCAAAA.Katoumey:BAAALgAECgYJBgABLgAFFAQJCQAhAPAUAA==.',
Ke='Keratin:BAABLgAECn8cAAIiAAcJESMEAgC2AgAiAAcJESMEAgC2AgAAAA==.',
Kh='Khumi:BAABLgAECn8XAAIYAAgJYSDyEgCbAgAYAAgJYSDyEgCbAgABLgAFFAgJEgAgAOMgAA==.',
Ki='Kinan:BAABLgAECn8bAAMWAAcJvyMvCAB1AgAWAAcJeSMvCAB1AgAYAAcJOx5AFwBxAgAAAA==.Kita:BAAALgAECggJEgAAAA==.',
Kk='Kkaarrkk:BAAALgAECgUJBQAAAA==.',
Kr='Krindon:BAAALgAECgYJCwAAAA==.',
Ku='Kureiji:BAAALgADCgEJAQAAAA==.',
Ky='Kythin:BAAALgADCgEJAQAAAA==.',
Kz='Kzuon:BAAALgADCggJCAAAAA==.',
La='Laww:BAAALgADCgcJCgAAAA==.',
Le='Lecroix:BAAALgADCgUJBQAAAA==.Leonus:BAAALgAECgMJAwAAAA==.Lethalforce:BAAALgADCgMJAwAAAA==.',
Li='Liandri:BAAALgADCgEJAgAAAA==.Lightchild:BAAALgADCggJCAAAAA==.Lillith:BAAALgAECgMJAwAAAA==.Livewire:BAAALgAECgEJAQAAAA==.',
Lo='Lokohmojo:BAAALgAECgEJAQAAAA==.Lomponic:BAEBLgAECn8aAAIPAAcJmhpsCgDZAQAPAAcJmhpsCgDZAQAAAA==.Loomadin:BAAALgADCgYJCQAAAA==.',
Lu='Lunethra:BAABLgAECn8kAAIWAAkJwBFrGgDCAQAWAAkJwBFrGgDCAQAAAA==.',
Ma='Magerag:BAABLgAECn8gAAMTAAgJUR6tLwCzAgATAAgJUR6tLwCzAgAjAAIJQBpFFQBzAAAAAA==.Manamontana:BAACLgAFFH8RAAMQAAUJtxFCIQA3AQAQAAQJtxFCIQA3AQAaAAEJAAAHHQAAAAAuAAQKfxkAAhAACAn4H30oAJgCABAACAn4H30oAJgCAAAA.Marumo:BAAALgAECgMJBgAAAA==.',
Mc='Mcribz:BAACLgAFFH8RAAIQAAUJ3CJyCACXAQAQAAUJ3CJyCACXAQAuAAQKfx0AAhAACAl5IykZAOUCABAACAl5IykZAOUCAAAA.',
Me='Meelonusk:BAAALgAECgQJCAAAAA==.Mess:BAAALgAECgEJAQAAAA==.Messah:BAAALgAECgMJBAAAAA==.',
Mi='Michaelcoyle:BAABLgAECn8eAAIWAAcJIhudGQDHAQAWAAcJIhudGQDHAQAAAA==.Midnightcrow:BAAALgADCgcJBwAAAA==.Milo:BAABLgAECn8sAAMJAAkJLCKxAAAsAwAJAAkJLCKxAAAsAwAIAAgJbhwVBAC0AgAAAA==.Mishra:BAAALgAECgUJBQAAAA==.Mitra:BAABLgAECn8WAAIVAAYJEhshBABWAQAVAAYJEhshBABWAQAAAA==.',
Mo='Moesko:BAAALgAECggJDwAAAA==.Mof:BAAALgADCgEJAQAAAA==.Mohawkk:BAAALgADCgYJBgAAAA==.Monktup:BAAALgAECgYJCwAAAA==.Monnehbaggs:BAABLgAECn8eAAMSAAgJpR0CDgB7AgASAAgJpR0CDgB7AgAeAAIJLRKKMgBIAAAAAA==.Mortalidad:BAAALgADCgQJBAAAAA==.',
Mu='Muin:BAAALgAECgEJAQAAAA==.Murdersamich:BAAALgAECgQJCwAAAA==.',
My='Mybigcrits:BAAALgAECgYJDAAAAA==.',
['Mà']='Màevë:BAAALgAECgEJAgAAAA==.',
Na='Nairdax:BAAALgADCgEJAQAAAA==.Nalmec:BAABLgAECn8VAAIJAAYJ4QdDKAACAQAJAAYJ4QdDKAACAQAAAA==.Naysayre:BAAALgAECgYJEwAAAA==.',
Ne='Nebody:BAAALgAECgEJAQAAAA==.Necriss:BAABLgAECn8WAAIgAAcJwg13ewCDAQAgAAcJwg13ewCDAQAAAA==.Nevin:BAAALgAECgEJAQAAAA==.',
Ni='Nightkilla:BAAALgAECgEJAQAAAA==.Nilowin:BAABLgAECn8ZAAIBAAgJaQvDKgCnAQABAAgJaQvDKgCnAQAAAA==.',
No='Nokaj:BAAALgAECgEJAQAAAA==.Noshards:BAAALgAECgcJDQAAAA==.Notericdh:BAAALgAECgQJDQAAAA==.',
Og='Oghom:BAAALgADCgcJCgAAAA==.',
Oh='Ohnoitzgumby:BAAALgAECgYJDwAAAA==.',
Om='Omiko:BAAALgADCgUJBwAAAA==.',
Op='Opeep:BAAALgADCgcJGQAAAA==.',
Or='Orah:BAAALgADCgEJAQAAAA==.',
Os='Osos:BAAALgAECgYJCQAAAA==.',
Pa='Paladimdab:BAAALgAECgMJAwAAAA==.Papachance:BAAALgAECgMJAwAAAA==.Papafrank:BAAALgADCgkJEAAAAA==.Paradis:BAAALgADCgcJBwAAAA==.Pazuzu:BAAALgADCgYJBgAAAA==.',
Pe='Peepo:BAAALgAECgEJAQAAAA==.',
Pi='Pinga:BAAALgAECgIJBAABLgAECggJKQAkAKIjAA==.Pinkberry:BAAALgAECgQJBAAAAA==.Pintcube:BAAALgADCgYJCAAAAA==.',
Pl='Pljeskavica:BAAALgAECgUJBgAAAA==.Plox:BAAALgAECgMJAwAAAA==.',
Po='Port:BAABLgAECn8gAAIEAAgJ3BtdEQADAgAEAAgJ3BtdEQADAgAAAA==.Potroastjr:BAAALgADCgEJAgABLgAECgEJAQARAAAAAA==.',
Pr='Primordus:BAAALgADCgUJBQAAAA==.Protocol:BAAALgAECgMJAwAAAA==.',
Ps='Pseriph:BAABLgAECn8ZAAICAAcJ3BZpCwAKAgACAAcJ3BZpCwAKAgAAAA==.',
Ra='Radamantis:BAAALgAECgMJAwAAAA==.Raenon:BAAALgADCgkJEAAAAA==.Raggnar:BAACLgAFFH8FAAIHAAMJFhRIEAD+AAAHAAMJFhRIEAD+AAAuAAQKfyEAAgcACAmyIPAOALcCAAcACAmyIPAOALcCAAAA.Ragingwaters:BAAALgADCgYJCAAAAA==.Ranvir:BAAALgADCgkJGQAAAA==.Raun:BAABLgAECn8gAAMgAAcJ8B/REQAsAgAgAAcJ8B/REQAsAgAMAAMJIxEmcgCzAAAAAA==.',
Re='Regnarr:BAAALgADCgEJAQAAAA==.Relaire:BAABLgAECn8XAAIWAAcJdw1RKQBxAQAWAAcJdw1RKQBxAQAAAA==.',
Ri='Rikane:BAAALgADCgcJDAABLgADCgcJEgARAAAAAA==.Riku:BAABLgAECn8bAAIhAAcJbxwRBQDOAQAhAAcJbxwRBQDOAQAAAA==.',
Ro='Rock:BAAALgAECgYJBwAAAA==.Roguey:BAABLgAECn8VAAIlAAcJmAkGBwA5AQAlAAcJmAkGBwA5AQAAAA==.Roots:BAAALgAECgEJAwAAAA==.',
Ry='Ryveri:BAABLgAECn8lAAIJAAkJDxnYAwCOAgAJAAkJDxnYAwCOAgAAAA==.',
Sa='Sablehide:BAABLgAECn8dAAIGAAcJ/BIUGQA1AQAGAAcJ/BIUGQA1AQAAAA==.Sanaron:BAAALgADCgIJAgAAAA==.Sanaty:BAAALgAECgQJCQAAAA==.Saryn:BAAALgAECgYJDgAAAA==.Satanz:BAAALgADCgIJAgAAAA==.Sathanus:BAAALgAECgEJAQAAAA==.',
Se='Searate:BAAALgADCgcJEgAAAA==.Seaside:BAACLgAFFH8JAAIQAAMJQSTmHAAvAQAQAAMJQSTmHAAvAQAuAAQKfxYAAxAABwk9JfkRACsCABAABwk9JfkRACsCABoAAgmEC+o/AE4AAAAA.Secrett:BAAALgAECgcJDwAAAA==.Sephyxia:BAABLgAECn8kAAIaAAgJIBNFCwBcAQAaAAgJIBNFCwBcAQAAAA==.Serryon:BAAALgADCgIJAgAAAA==.',
Sh='Shadowwzz:BAAALgADCgEJAQAAAA==.Shoçknezz:BAAALgAECgMJBQAAAA==.',
Si='Silverwolf:BAABLgAECn8qAAIdAAgJShzLAgAxAgAdAAgJShzLAgAxAgAAAA==.Simplyunlock:BAABLgAECn8bAAMDAAgJ0Q0SWQC9AQADAAgJ0Q0SWQC9AQACAAIJ5wWMZgBDAAAAAA==.Simplyvoided:BAAALgADCgYJCwAAAA==.Sinverguenza:BAAALgAECgMJBQAAAA==.Sizzlechop:BAABLgAECn8ZAAIQAAcJCgenVgD/AAAQAAcJCgenVgD/AAAAAA==.',
Sk='Skizzak:BAAALgADCgQJBAABLgAFFAUJEQAQANwiAA==.Skweeks:BAAALgAECgMJBAAAAA==.',
Sm='Smelvin:BAABLgAECn8UAAIHAAkJNxlqFgBmAgAHAAkJNxlqFgBmAgABLgAECgQJCAARAAAAAA==.Smoko:BAAALgAECgIJAgABLgAECgUJBQARAAAAAA==.',
Sn='Snailslolol:BAAALgAECgEJAQAAAA==.Snakey:BAACLgAFFH8JAAMGAAMJtwaNGwDJAAAGAAMJtwaNGwDJAAAmAAEJ1gKdBgBHAAAuAAQKfyYAAwYACAmLGD0aAPkBAAYACAmLGD0aAPkBACYABgl5BHYmAO8AAAAA.',
So='Solara:BAABLgAECn8YAAQPAAYJERy3FgBJAQAPAAYJERy3FgBJAQASAAEJQAIKhwApAAAeAAEJXgKTXgAkAAAAAA==.Soleill:BAAALgAECgcJBwAAAA==.Sondan:BAAALgADCgMJAwAAAA==.Songs:BAAALgAECgEJAQABLgAECgYJGAALAP0gAA==.',
Sp='Spellpowa:BAAALgAECgYJDgAAAA==.',
Ss='Ssminion:BAAALgAECgEJAgAAAA==.',
St='Stormwing:BAABLgAECn8UAAIHAAYJHxyxFgBfAQAHAAYJHxyxFgBfAQAAAA==.Strecagosa:BAAALgAECgYJDQAAAA==.',
Sv='Svenn:BAAALgAECgYJBgAAAA==.',
Sy='Synni:BAAALgADCgEJAQAAAA==.',
['Sÿ']='Sÿnÿster:BAAALgADCgMJAwABLgAFFAMJBgAWAHMSAA==.',
Ta='Talron:BAAALgAECgQJBAAAAA==.Tastytay:BAAALgADCgMJAwAAAA==.Tatertots:BAABLgAECn8eAAMiAAcJ8R+zAwBEAgAiAAcJ8R+zAwBEAgAQAAMJ8hN97ACmAAAAAA==.',
Te='Tea:BAABLgAECn8hAAIWAAgJfB9ECQBnAgAWAAgJfB9ECQBnAgAAAA==.Teal:BAAALgADCgYJBgAAAA==.Templyn:BAAALgAECgYJBwAAAA==.Tenebrarum:BAABLgAECn8bAAIWAAgJGA2MLABgAQAWAAgJGA2MLABgAQAAAA==.Testorooni:BAABLgAECn8ZAAIWAAcJkBgmMwDjAQAWAAcJkBgmMwDjAQAAAA==.',
Th='Thakodi:BAAALgADCgkJCQAAAA==.Thannos:BAAALgADCgEJAQAAAA==.Tharvan:BAAALgADCgcJDAAAAA==.Thedeadman:BAABLgAECn8hAAIQAAkJoh/tBgCwAgAQAAkJoh/tBgCwAgAAAA==.Thepriestg:BAAALgAECgEJAQAAAA==.Thiccksilver:BAAALgADCgcJBwABLgAECgMJAwARAAAAAA==.Thompson:BAAALgAECgQJDQAAAA==.Thunderflaps:BAAALgAECgUJCQAAAA==.Thyrus:BAABLgAECn8pAAMkAAgJoiNXAwBkAgAkAAgJoiNXAwBkAgAmAAEJqgL2RAAjAAAAAA==.',
Ti='Tirna:BAABLgAECn8dAAIfAAcJog2wBACOAQAfAAcJog2wBACOAQAAAA==.',
To='Tomsellock:BAABLgAECn8WAAMnAAcJjhBuBwDcAQAnAAcJjhBuBwDcAQADAAEJugMsLAEmAAAAAA==.Torvi:BAAALgADCgMJAwAAAA==.',
Tr='Transmørtuus:BAAALgAECgQJCQAAAA==.Treehug:BAABLgAECn8VAAIhAAgJ8g4DFQBkAQAhAAgJ8g4DFQBkAQAAAA==.Triple:BAAALgAECgQJBAABLgAECgYJCQARAAAAAA==.',
Tu='Tullen:BAEBLgAECn8aAAISAAcJ3RTEEgCEAQASAAcJ3RTEEgCEAQAAAA==.Turanos:BAAALgAECgEJAQAAAA==.',
Tw='Tweyen:BAAALgAECgEJAQAAAA==.',
Ty='Tyindaris:BAAALgAECgQJCAAAAA==.Tyloregeth:BAABLgAECn8eAAIPAAgJ/xENHQDzAQAPAAgJ/xENHQDzAQAAAA==.',
['Té']='Témplýn:BAAALgADCgEJAQABLgAECgYJBwARAAAAAA==.',
['Të']='Tëmplýn:BAAALgADCgMJAwABLgAECgYJBwARAAAAAA==.',
Ul='Ulfrunn:BAAALgADCgYJBgAAAA==.Ultrachad:BAACLgAFFH8KAAIQAAQJYxdlGgBMAQAQAAQJYxdlGgBMAQAuAAQKfx4AAhAACAlFIwMUAAMDABAACAlFIwMUAAMDAAAA.',
Um='Umami:BAABLgAECn8gAAIJAAYJ4hjPGgBZAQAJAAYJ4hjPGgBZAQAAAA==.',
Un='Unggoy:BAACLgAFFH8RAAMYAAYJqBnyAgAkAgAYAAYJqBnyAgAkAgAWAAEJVwzyOgBRAAAuAAQKfyEAAhgACQmAJbQBAKUDABgACQmAJbQBAKUDAAAA.Unholywaters:BAAALgAECgIJBAAAAA==.',
Ur='Urianna:BAAALgAECgIJBgAAAA==.',
Va='Vaelthirion:BAABLgAECn8aAAITAAgJ8hJKhADJAQATAAgJ8hJKhADJAQAAAA==.Vahidamus:BAAALgAECgMJBAAAAA==.Valkaryon:BAAALgAECgcJCgAAAA==.Valmirax:BAAALgADCggJEgAAAA==.Valton:BAABLgAECn8lAAIgAAYJigijWQAEAQAgAAYJigijWQAEAQAAAA==.',
Ve='Vegetation:BAAALgAECgMJBQAAAA==.Velenestus:BAAALgAECgMJBgAAAA==.',
Wa='Wackaman:BAAALgAECgYJEwAAAA==.Warpig:BAAALgAECgYJEQAAAA==.Wasps:BAAALgAECgYJEQAAAA==.',
We='Wegmaniac:BAAALgADCgYJCAAAAA==.Welastrexa:BAAALgADCgUJBQAAAA==.',
Wi='Wickedclöwn:BAAALgADCgMJAwAAAA==.Winchester:BAAALgADCgIJAgAAAA==.Windhorn:BAAALgADCgcJCAAAAA==.Winds:BAABLgAECn8YAAILAAYJ/SBjFwAqAgALAAYJ/SBjFwAqAgAAAA==.',
Wn='Wntrizcoming:BAAALgADCgMJBQAAAA==.',
Wo='Wolfquota:BAACLgAFFH8HAAIHAAMJ5hxCDwALAQAHAAMJ5hxCDwALAQAuAAQKfx4AAwcACAkoIkYJAP4CAAcACAkoIkYJAP4CAB0ABAntE08eAOkAAAAA.Wolftime:BAAALgADCgUJBQAAAA==.Wombaa:BAACLgAFFH8HAAIQAAMJ1SH/HgA+AQAQAAMJ1SH/HgA+AQAuAAQKfxwAAhAACAleJGEKAEgDABAACAleJGEKAEgDAAAA.',
Wr='Wrathbolt:BAAALgADCgcJCQABLgAECgYJFwALADobAA==.Wrathmo:BAABLgAECn8XAAMLAAYJOhu3IADRAQALAAYJOhu3IADRAQAoAAYJegdEJADlAAAAAA==.Wrolie:BAAALgADCgMJAwAAAA==.',
['Wê']='Wêêdyys:BAAALgADCgMJBAAAAA==.',
Xy='Xyr:BAAALgAECgEJAQAAAA==.',
Za='Zandalia:BAAALgAECgMJAwAAAA==.Zark:BAEALgADCgcJBwABLgAECgcJEwARAAAAAA==.',
Ze='Zemphoths:BAAALgAECgUJCAAAAA==.',
Zo='Zoa:BAAALgADCgYJBgAAAA==.Zolton:BAAALgADCgMJAwAAAA==.Zornak:BAAALgADCgQJBAAAAA==.',
['Åe']='Åequitas:BAAALgAECgYJCQAAAA==.',
['ßa']='ßahamut:BAAALgAECgQJBQAAAA==.',
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
