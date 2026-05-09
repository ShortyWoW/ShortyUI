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

local lookup = {'Druid-Restoration','Mage-Frost','Hunter-BeastMastery','Unknown-Unknown','Paladin-Retribution','Druid-Balance','Monk-Mistweaver','Warrior-Arms','Warrior-Fury','Shaman-Elemental','Shaman-Restoration','Paladin-Holy','Paladin-Protection','Shaman-Enhancement','Warlock-Destruction','Warlock-Demonology','Monk-Brewmaster','Hunter-Survival','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Warrior-Protection','Druid-Feral','Priest-Holy','DemonHunter-Devourer','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','Priest-Shadow','Priest-Discipline','DemonHunter-Havoc','Hunter-Marksmanship','DemonHunter-Vengeance','Druid-Guardian',}
local provider = {region='US',realm='DarkIron',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aanx:BAAALgAECgYJEgAAAA==.',
Ab='Abadon:BAAALgAECgQJBgABLgAECgkJGQABAMQaAA==.Abdorei:BAABLgAECn8ZAAICAAgJTREdOgC7AQACAAgJTREdOgC7AQAAAA==.Absorboat:BAAALgADCgYJCAAAAA==.',
Ac='Accilatem:BAABLgAECn8UAAIDAAcJIh0mHgBRAgADAAcJIh0mHgBRAgABLgAECggJEQAEAAAAAA==.Accilatim:BAAALgAECggJEQAAAA==.',
Ad='Adonsina:BAAALgAECgEJAQABLgAECgkJCwAEAAAAAA==.',
Ag='Agrromagnet:BAABLgAECn8oAAIFAAkJaRjsHAAaAgAFAAkJaRjsHAAaAgAAAA==.',
Ai='Aiba:BAABLgAECn8ZAAIGAAgJ1hdtDAADAgAGAAgJ1hdtDAADAgAAAA==.',
Ak='Akcloud:BAAALgAFFAEJAgAAAA==.',
Al='Alaeris:BAABLgAECn8YAAIHAAgJTx6iDgABAgAHAAgJTx6iDgABAgAAAA==.Albetabeef:BAABLgAFFH8HAAMIAAQJ3xFpBwAvAQAIAAQJ3xFpBwAvAQAJAAIJJgZKHACUAAAAAA==.Aleyeah:BAAALgAECgIJBAABLgAECggJJAAKAEwbAA==.Allhopeisded:BAABLgAECn8UAAILAAYJog7IQQD8AAALAAYJog7IQQD8AAAAAA==.Alurelor:BAAALgAECgcJAQAAAA==.',
Am='Amarah:BAAALgADCgYJBgAAAA==.Amelaista:BAABLgAECn8kAAILAAgJ8AvSLgBXAQALAAgJ8AvSLgBXAQAAAA==.',
An='Anddi:BAAALgAECgEJAgAAAA==.Andii:BAABLgAECn8YAAQMAAgJyBfDJQBbAQAMAAcJ0BbDJQBbAQAFAAIJtAfKDQExAAANAAEJAAD/OwAAAAAAAA==.Andy:BAAALgAFFAIJAgAAAA==.Angusbeef:BAAALgADCgQJBAAAAA==.',
Ao='Aoibhoker:BAAALgAECgQJBAABLgAECggJIwAOALgfAA==.',
Ar='Arclo:BAAALgADCgYJBgAAAA==.Arden:BAAALgAECgQJBAABLgAECgYJFwAPANkWAA==.Ardeno:BAABLgAECn8XAAMPAAYJ2RanIwA7AQAPAAYJbwynIwA7AQAQAAUJ2RZIVAAvAQAAAA==.Ardon:BAABLgAECn8fAAMLAAkJNxggCwB8AgALAAkJNxggCwB8AgAKAAUJvRsaMQCaAQAAAA==.Armis:BAAALgADCgUJBQAAAA==.',
As='Asteruis:BAABLgAECn8iAAIDAAgJEx8ZEwA3AgADAAgJEx8ZEwA3AgAAAA==.',
Av='Avenayra:BAAALgAECgIJAwAAAA==.',
Ba='Baddhealer:BAAALgADCgUJBQAAAA==.Badfurion:BAAALgADCggJCgAAAA==.Balthamel:BAAALgAECgYJDAAAAA==.Bananafang:BAAALgAECgQJBgAAAA==.Bananashoes:BAAALgAECgMJAgAAAA==.Bangerz:BAACLgAFFH8gAAIMAAYJShJgBwCnAQAMAAYJShJgBwCnAQAuAAQKfy8AAwwACQl1H7QIAOMCAAwACQl1H7QIAOMCAAUAAQm4Ad5YASYAAAAA.Barkendremix:BAABLgAECn8lAAIRAAgJ2BXUDwDNAQARAAgJ2BXUDwDNAQAAAA==.Bathsheber:BAAALgAECgIJAgABLgAFFAUJEQACAM0iAA==.',
Be='Beanieweenie:BAAALgADCgEJAQAAAA==.Beerez:BAAALgADCgcJDQAAAA==.Belroy:BAABLgAECn8UAAISAAYJMw2qIgDmAAASAAYJMw2qIgDmAAAAAA==.',
Bj='Bjorum:BAABLgAECn8gAAMOAAgJJSK5BADJAgAOAAgJJSK5BADJAgAKAAEJ4QiwkAAnAAAAAA==.',
Bo='Bodytwodafa:BAABLgAECn8gAAQTAAgJ7SAZBgCVAgATAAgJIR4ZBgCVAgAUAAYJ+BhnCQDIAQAVAAcJaRhFEgC6AQAAAA==.Bournemaad:BAAALgADCgMJAwAAAA==.Boyafu:BAAALgAECgEJAQAAAA==.',
Br='Brucecampbel:BAAALgAECgMJCQAAAA==.',
Bu='Bubbleyou:BAAALgAECgUJDQAAAA==.',
Ca='Cantarella:BAAALgAECgcJEQAAAA==.Carlyle:BAABLgAECn8cAAMFAAgJlRZ+TgBaAQAFAAgJlRZ+TgBaAQAMAAEJPR0mVwBNAAAAAA==.Catdaddy:BAAALgADCgYJBwAAAA==.',
Ch='Checkmybio:BAAALgAECgQJBQAAAA==.Cheesecake:BAAALgADCgUJBQAAAA==.Chromehound:BAAALgADCgQJBAAAAA==.Chumdungler:BAAALgAECgMJAwAAAA==.',
Ci='Cindervis:BAAALgADCgYJBgAAAA==.',
Cl='Clonk:BAAALgAECgUJBQAAAA==.',
Co='Collossuss:BAAALgAECgYJEgAAAA==.Convik:BAAALgAECgcJBwAAAA==.',
Cr='Cregga:BAAALgADCgEJAQAAAA==.Crimsonagony:BAAALgADCgUJBQAAAA==.Crosshairs:BAAALgADCgMJAwAAAA==.',
Cu='Cuddles:BAAALgADCgUJBQAAAA==.Curacao:BAABLgAECn8YAAIJAAcJ+hO7GgCRAQAJAAcJ+hO7GgCRAQAAAA==.',
Cy='Cynnari:BAAALgAECgYJDQAAAA==.',
Da='Dabtime:BAABLgAECn8gAAIFAAcJHRbqWgA6AQAFAAcJHRbqWgA6AQAAAA==.',
De='Deathknightm:BAAALgAECgIJAgABLgAECgkJHAAWAHQVAA==.Dekaar:BAABLgAECn8UAAIXAAYJkQliEgD4AAAXAAYJkQliEgD4AAAAAA==.Demonknight:BAAALgAECgEJAQAAAA==.Deracine:BAAALgAECgYJCQAAAA==.Desdemonica:BAAALgAECgYJDwAAAA==.',
Di='Diegoknight:BAAALgADCgEJAgAAAA==.Diggle:BAAALgADCggJCAAAAA==.Dilvdrood:BAAALgADCgUJBQAAAA==.Dilvish:BAAALgAECgYJEgAAAA==.',
Do='Doctrwho:BAAALgADCgIJAgAAAA==.Dohaeris:BAABLgAECn8pAAIYAAkJ/BMxDgAEAgAYAAkJ/BMxDgAEAgAAAA==.Domain:BAABLgAECn8XAAIZAAgJJhREJgClAQAZAAgJJhREJgClAQAAAA==.Donfalprun:BAABLgAECn8aAAIFAAgJkiOmCQC9AgAFAAgJkiOmCQC9AgAAAA==.Doomstout:BAAALgAECgkJEAAAAA==.',
Dr='Draconus:BAABLgAECn8jAAMaAAgJbxAYFgAhAQAaAAgJcw4YFgAhAQAbAAMJdxy8nwChAAAAAA==.Dralas:BAAALgAECgEJAgAAAA==.',
Du='Duro:BAAALgAECgYJDAABLgAECgYJDAAEAAAAAA==.Durto:BAAALgADCgMJAwABLgAECgQJBwAEAAAAAA==.Duskshade:BAAALgADCggJDwAAAA==.',
['Dü']='Düsk:BAAALgAECgEJAQAAAA==.',
El='Elij:BAABLgAECn8XAAIQAAgJPhR1PQAWAgAQAAgJPhR1PQAWAgAAAA==.Elunaire:BAABLgAECn8ZAAIBAAkJxBqRHQBRAgABAAkJxBqRHQBRAgAAAA==.',
Em='Emelec:BAAALgAECgIJAgAAAA==.Emeraldwish:BAABLgAECn8cAAIBAAgJpSNrBgAlAwABAAgJpSNrBgAlAwAAAA==.',
Er='Erthnite:BAAALgAECgQJBAAAAA==.',
Ev='Evinco:BAAALgAECgcJEgAAAA==.Evy:BAAALgAECgEJAgAAAA==.',
Ex='Executie:BAACLgAFFH8RAAMIAAUJIA/yBwAoAQAIAAUJ6A7yBwAoAQAJAAMJHwzMEgDvAAAuAAQKfyEAAwgACQnAG3cGAGQCAAgACQmMGncGAGQCAAkABglLHFk1ANQBAAAA.',
Fa='Falin:BAAALgAECgEJAQAAAA==.',
Fe='Fey:BAABLgAECn8iAAIQAAkJ3hNXHwD1AQAQAAkJ3hNXHwD1AQAAAA==.',
Fi='Fieryember:BAAALgAECgQJBQABLgAECgUJBgAEAAAAAA==.Fistvendor:BAAALgAECggJDgAAAA==.',
Fl='Flasheals:BAABLgAECn8hAAIMAAcJoBMnIQB+AQAMAAcJoBMnIQB+AQAAAA==.Flatpak:BAAALgADCgEJAgAAAA==.Flobglop:BAAALgAECgEJAQAAAA==.Fluffybum:BAAALgADCgEJAQAAAA==.',
Fo='Foxtrot:BAAALgAECgYJBgAAAA==.',
Fr='Frostine:BAAALgAECgcJEwAAAA==.Frostwave:BAABLgAECn8mAAMcAAgJQB1HAwDjAQAcAAcJ7B5HAwDjAQAaAAgJYBAZEQBgAQAAAA==.',
Fu='Fujiyama:BAABLgAECn8kAAIKAAgJTBvoDAAOAgAKAAgJTBvoDAAOAgAAAA==.Furryweasal:BAAALgADCgEJAQAAAA==.',
Ga='Garrex:BAAALgADCgUJBQABLgAECggJFQADAL8WAA==.Garréosh:BAAALgAECgUJCQABLgAFFAIJBwAFAGwVAA==.',
Ge='Geodude:BAAALgADCgYJBwAAAA==.',
Gi='Gibborim:BAAALgAECgYJCwAAAA==.Gigilomann:BAAALgAECgEJAQAAAA==.',
Gl='Glenndanzig:BAAALgADCgYJBgAAAA==.',
Go='Goldenshield:BAAALgAECgMJCQAAAA==.Gonecrazy:BAAALgADCgMJAwAAAA==.Gorthan:BAAALgADCgQJBgAAAA==.',
Gr='Grabandgank:BAAALgADCgYJBgAAAA==.',
Gu='Guaresux:BAEALgADCgEJAQABLgAECgcJDwAEAAAAAA==.Gurnisson:BAAALgADCgUJBQAAAA==.Gusto:BAABLgAECn8lAAMVAAkJ6AuZFQCXAQAVAAkJRAuZFQCXAQATAAcJwQcDDADUAAAAAA==.',
Ha='Hadouken:BAAALgAECgkJCwAAAA==.Halppme:BAAALgADCgcJBwAAAA==.Hammerfall:BAAALgAECgQJBAAAAA==.Handsome:BAAALgAECgcJBwAAAA==.',
He='Headshotte:BAAALgAECgYJDAAAAA==.Heatindabs:BAABLgAECn8eAAIBAAgJ4w+TNABHAQABAAgJ4w+TNABHAQAAAA==.Hexed:BAAALgAECgQJBgAAAA==.',
Hi='Hinael:BAAALgAECgEJAQAAAA==.',
Ho='Holyknight:BAAALgAECgQJBAAAAA==.Holymama:BAABLgAECn8gAAMdAAgJLx3QCAA7AgAdAAcJHiDQCAA7AgAeAAIJJBO2NgB5AAAAAA==.',
Hu='Hunkwai:BAAALgAFFAIJAgAAAA==.',
Ib='Ibok:BAAALgAECgYJCgAAAA==.',
Ic='Ickma:BAABLgAECn8oAAIbAAgJfB6zGQAxAgAbAAgJfB6zGQAxAgAAAA==.',
Id='Iddou:BAAALgAECgMJAwAAAA==.',
Ik='Ikona:BAAALgADCggJDgAAAA==.',
Im='Impgobrr:BAAALgAECgEJAQAAAA==.Imu:BAAALgADCggJDAAAAA==.',
In='Incubus:BAAALgADCgEJAgAAAA==.Infari:BAAALgADCgYJDwAAAA==.',
Ir='Irdeldran:BAAALgAECgEJAQAAAA==.',
Ja='Jabjek:BAAALgADCgYJCAAAAA==.Jamaz:BAAALgAECgQJBAAAAA==.Jamwich:BAAALgADCgYJBgAAAA==.Jasonmoloa:BAAALgAECgYJDgAAAA==.',
Je='Jerazia:BAAALgAECgQJBAAAAA==.',
Jo='Johanx:BAAALgADCgMJAwAAAA==.Jordananon:BAAALgADCgIJAgAAAA==.Jordanian:BAAALgAECgMJAwAAAA==.',
['Jî']='Jînxy:BAAALgAECgEJAgAAAA==.',
Ka='Kaalli:BAAALgADCggJCQAAAA==.Kaollanna:BAABLgAECn8jAAICAAkJDRboLADuAQACAAkJDRboLADuAQAAAA==.Karik:BAAALgADCgkJHQAAAA==.Kaven:BAAALgADCgIJAgAAAA==.',
Ke='Kehma:BAAALgAECgEJAQAAAA==.Kelisa:BAABLgAECn8eAAIFAAgJuhyiGQAwAgAFAAgJuhyiGQAwAgAAAA==.Ketchuptits:BAAALgADCgYJBgAAAA==.',
Ki='Kimjunggheal:BAAALgAECgMJBgAAAA==.Kinkster:BAAALgAECgYJCgABLgAECgYJDQAEAAAAAA==.Kiwidin:BAABLgAECn8aAAIMAAgJARbjJgDzAQAMAAgJARbjJgDzAQAAAA==.',
Kr='Krinxy:BAAALgAECgUJEgAAAA==.',
Ks='Kschwev:BAAALgADCgYJBgAAAA==.',
Ku='Kuratcha:BAAALgAECgUJBgAAAA==.',
Ky='Kylee:BAAALgAECgkJAQAAAA==.Kyý:BAAALgAECgYJDwAAAA==.',
['Kí']='Kíng:BAAALgAECgIJAgABLgAECgUJBgAEAAAAAA==.',
Le='Ledgerfeign:BAABLgAECn8YAAIQAAgJMQopRABdAQAQAAgJMQopRABdAQAAAA==.',
Li='Liadan:BAAALgAECgYJCwAAAA==.Lighteye:BAABLgAECn8oAAIBAAgJwBQTGAAEAgABAAgJwBQTGAAEAgAAAA==.Lilmudatruka:BAAALgADCgEJAQABLgAECgYJFAALAKIOAA==.',
Lo='Longestibrow:BAAALgAECgMJBQAAAA==.',
Lu='Luminescence:BAAALgADCgQJBgAAAA==.Lunarqt:BAAALgAECgEJAQAAAA==.Lunchy:BAAALgAECgYJCQAAAA==.',
Ly='Lyllow:BAAALgAECgYJEgAAAA==.',
['Lø']='Løurent:BAAALgADCgQJBAAAAA==.',
Ma='Magicdorf:BAABLgAECn8oAAICAAgJ4CAREQCRAgACAAgJ4CAREQCRAgAAAA==.Malphasia:BAAALgADCgYJBgAAAA==.Manhitrogue:BAAALgAECgQJBAAAAA==.',
Mc='Mcsleuth:BAAALgAECgQJBgAAAA==.',
Me='Megarayquaza:BAABLgAECn8fAAMZAAgJBRLOLACEAQAfAAgJyAtnHgDMAQAZAAgJDxHOLACEAQAAAA==.',
Mi='Mikeyouk:BAAALgADCgYJBgAAAA==.Misties:BAAALgAECgEJAQAAAA==.',
Mo='Moargoth:BAAALgADCgUJEAAAAA==.Mooneater:BAAALgAECgMJAwAAAA==.Mordorl:BAAALgADCgcJBwAAAA==.',
Mt='Mtt:BAAALgADCgkJDgAAAA==.',
Mx='Mxx:BAAALgAECgUJEgAAAA==.',
My='Mylianne:BAAALgAECgYJEgAAAA==.Mynameiscole:BAACLgAFFH8IAAIfAAQJgx97AQCSAQAfAAQJgx97AQCSAQAuAAQKfyIAAh8ACAmYJq0BAIoDAB8ACAmYJq0BAIoDAAAA.Myrolan:BAABLgAECn8lAAIfAAgJVCPYAgC+AgAfAAgJVCPYAgC+AgAAAA==.Myrtru:BAAALgADCgkJGgAAAA==.',
['Mí']='Míyagi:BAAALgAECgYJBgAAAA==.',
Na='Naturallight:BAAALgADCgUJCAAAAA==.',
Ne='Neechka:BAAALgADCgUJBQAAAA==.Neosan:BAAALgADCgYJBgABLgAFFAMJCgAGAPMiAA==.Nevyn:BAAALgAECgYJEwAAAA==.Newface:BAAALgADCgEJAgAAAA==.Newmoo:BAAALgAECgEJAQAAAA==.',
Ni='Nightsage:BAAALgAECgQJBAAAAA==.Niji:BAAALgAECgEJAgABLgAECggJGQAGANYXAA==.Nininhp:BAAALgAECgMJAwABLgAECgUJCwAEAAAAAA==.Nithari:BAABLgAECn8mAAICAAcJ5iGfHQA4AgACAAcJ5iGfHQA4AgAAAA==.',
No='Nobel:BAAALgADCgEJAQAAAA==.Nomanai:BAAALgADCgkJAwAAAA==.Nosst:BAAALgAECgMJBQAAAA==.Nost:BAAALgADCgcJBwAAAA==.Nostu:BAABLgAECn8fAAMeAAgJVBgFDAARAgAeAAgJVBgFDAARAgAdAAEJbhCLTABCAAAAAA==.Now:BAABLgAECn8eAAMFAAgJjR/fLQBrAgAFAAgJzR3fLQBrAgANAAYJhRdwDgBRAQAAAA==.',
Nu='Nukum:BAAALgAECgYJEAAAAA==.',
Oh='Ohpa:BAAALgAECggJDwAAAA==.Ohrly:BAAALgADCgYJBgAAAA==.',
Oj='Ojikan:BAABLgAECn8WAAIXAAgJvSKkAwD2AgAXAAgJvSKkAwD2AgAAAA==.',
Pa='Papamush:BAAALgAECgMJBQAAAA==.Pathogenn:BAAALgAECgYJDwAAAA==.',
Pe='Pepecry:BAAALgAECgQJBwABLgAECgUJBgAEAAAAAA==.',
Ph='Phoblade:BAAALgAECggJEQAAAA==.Phokk:BAAALgAECgUJBQAAAA==.',
Pi='Pirotess:BAAALgAECgYJDgAAAA==.',
Po='Ponylion:BAAALgAECgYJCwABLgAECgcJEQAEAAAAAA==.Pooshka:BAABLgAECn8dAAIKAAkJRiJgCgDvAgAKAAkJRiJgCgDvAgAAAA==.Popz:BAAALgAECgEJAQAAAA==.',
Pr='Preorcthego:BAACLgAFFH8TAAISAAQJwiblAADSAQASAAQJwiblAADSAQAuAAQKfyQAAxIACAlpJpYAAIoDABIACAlpJpYAAIoDACAAAQm/JG97AFUAAAAA.Presibro:BAAALgAECgYJDQAAAA==.Presiric:BAAALgAECgMJAwAAAA==.Presisarian:BAAALgAECgUJDgAAAA==.',
Pu='Puck:BAAALgAECgYJDQAAAA==.Puppye:BAABLgAECn8VAAIDAAgJTRsJFAAvAgADAAgJTRsJFAAvAgAAAA==.',
Ra='Ranouu:BAABLgAECn8VAAICAAYJEhXwYABQAQACAAYJEhXwYABQAQAAAA==.Ratatatatt:BAAALgADCgQJBQAAAA==.',
Re='Reaoibher:BAAALgADCgMJAwABLgAECggJIwAOALgfAA==.Recision:BAABLgAECn8oAAIhAAgJtiD9AQB0AgAhAAgJtiD9AQB0AgAAAA==.Reeash:BAABLgAECn8VAAMLAAgJYxm2EgAiAgALAAgJYxm2EgAiAgAKAAMJfQqwRgCNAAAAAA==.Reeatar:BAAALgAECgYJEwABLgAECggJFQALAGMZAA==.Relindor:BAAALgADCgYJBgABLgAFFAQJCAAbAJwSAA==.Revelle:BAAALgAECgkJCwAAAA==.',
Rh='Rheizen:BAABLgAECn8eAAIWAAYJUg6iGQDxAAAWAAYJUg6iGQDxAAAAAA==.',
Ro='Ron:BAAALgADCgQJBAAAAA==.Ropopo:BAABLgAECn8aAAIeAAgJthmKCgAsAgAeAAgJthmKCgAsAgABLgAECggJFQADAE0bAA==.',
Ru='Rumnstuff:BAAALgADCgMJBwAAAA==.Runcat:BAABLgAECn8XAAMZAAgJQB5mDQBhAgAZAAgJQB5mDQBhAgAhAAQJ1QZbFACIAAAAAA==.',
['Rö']='Röyksopp:BAAALgAECgcJCgAAAA==.',
Sa='Sabo:BAAALgADCgMJAwAAAA==.Sakona:BAAALgADCgEJAQAAAA==.Samarah:BAAALgAECgQJAQAAAA==.Sandewor:BAAALgAECgYJBgABLgAECgYJEQAEAAAAAA==.Sanfrancisco:BAAALgAECgIJAwABLgAECgIJAgAEAAAAAA==.Sarafyn:BAABLgAECn8mAAIYAAcJRhjkEgDGAQAYAAcJRhjkEgDGAQAAAA==.Sauceguzzler:BAAALgAECgYJBgAAAA==.Savath:BAAALgADCgYJBgAAAA==.',
Se='Selenagomes:BAAALgAECgEJAQABLgAFFAQJCAAfAIMfAA==.Selenor:BAAALgAECgQJBwAAAA==.Seragaki:BAABLgAECn8aAAIeAAcJoxuDCgAtAgAeAAcJoxuDCgAtAgAAAA==.Seraphinna:BAAALgADCgEJAQAAAA==.',
Si='Siegrorc:BAABLgAECn8gAAIWAAcJdw4RFQAfAQAWAAcJdw4RFQAfAQAAAA==.Sillidari:BAAALgADCgQJBwAAAA==.Sionshope:BAAALgAECgUJCQAAAA==.',
Sk='Skragar:BAAALgAECgEJAgAAAA==.',
Sl='Slayerhunt:BAAALgAECgYJEQAAAA==.Slayertin:BAAALgAECgYJBwABLgAECgYJEQAEAAAAAA==.',
Sn='Snibdru:BAAALgAECgcJBgAAAA==.Snkrsotoole:BAABLgAECn8XAAIKAAYJgw5pLgD8AAAKAAYJgg5pLgD8AAAAAA==.',
So='Soobz:BAAALgADCgYJBgAAAA==.Sorian:BAAALgAECgQJBAAAAA==.Soulkings:BAAALgADCggJDwAAAA==.Soupies:BAAALgADCggJEwAAAA==.Soxa:BAAALgADCgIJAgAAAA==.',
Sp='Spiikee:BAAALgADCgQJBAAAAA==.Sprays:BAAALgAECgQJBAAAAA==.',
Sr='Sry:BAAALgAECgQJBAAAAA==.',
St='Steady:BAAALgAFFAEJAQAAAA==.Stonehand:BAABLgAECn8bAAIdAAkJTw9GDgDnAQAdAAkJTw9GDgDnAQAAAA==.Stormsurge:BAAALgAECgMJAwAAAA==.Stownt:BAAALgADCgMJAwAAAA==.Stravas:BAAALgAECgcJBwAAAA==.',
Su='Subudai:BAAALgAECgkJEAAAAA==.Sugarboi:BAABLgAECn8lAAIiAAkJZQioEAD9AAAiAAkJZQioEAD9AAAAAA==.Sugasuga:BAAALgAECgEJAwAAAA==.Sunnymuffins:BAAALgADCgYJBQAAAA==.',
Sv='Sveetka:BAAALgAECgMJBAAAAA==.',
Sx='Sxytrev:BAAALgAECgQJCQAAAA==.',
Ta='Tabi:BAAALgADCgQJBgAAAA==.Tacoy:BAABLgAECn8bAAIJAAgJxRZjEgDcAQAJAAgJxRZjEgDcAQAAAA==.Tagsy:BAABLgAECn8VAAIDAAgJvxYALgCWAQADAAgJvxYALgCWAQAAAA==.Tay:BAAALgAECgUJBQAAAA==.Tayna:BAAALgADCgYJBgAAAA==.',
Tb='Tbizkut:BAABLgAECn8oAAIPAAgJsw43BwB0AQAPAAgJsw43BwB0AQAAAA==.',
Th='Then:BAABLgAECn8hAAICAAcJSBmmNgDHAQACAAcJSBmmNgDHAQAAAA==.Threetimez:BAAALgAECgYJBwAAAA==.Thumbmage:BAAALgAECgIJAgABLgAECgkJLQAKAFkiAA==.',
Ti='Timemaster:BAABLgAECn8ZAAMfAAYJyBddEgBkAQAfAAYJyBddEgBkAQAZAAIJnQMJ1wBCAAAAAA==.Timepacifist:BAAALgAECgQJBAAAAA==.',
To='Tokido:BAAALgAFFAEJAQAAAA==.Tongpakfu:BAAALgAECgMJEQAAAA==.Topflight:BAAALgAECgcJEgAAAA==.',
Tr='Triggered:BAABLgAECn8bAAMFAAgJSBevPwCGAQAFAAgJSBevPwCGAQAMAAEJ0AqjngAqAAAAAA==.Troiikâ:BAABLgAECn8uAAQNAAkJnhQDEADFAQANAAkJnhQDEADFAQAFAAcJYQSGywDyAAAMAAUJ8gJbRACeAAAAAA==.Troikâ:BAAALgADCgYJBwAAAA==.Trroikâ:BAABLgAECn8YAAIWAAgJ0gzaHwBCAQAWAAgJ0gzaHwBCAQAAAA==.',
Tt='Tteeffinn:BAAALgADCgYJBgAAAA==.Ttevinn:BAAALgAECgMJBAABLgAECgQJBAAEAAAAAA==.Ttevoker:BAAALgAECgQJBAAAAA==.',
Tu='Tulvie:BAAALgADCgQJCAAAAA==.Tupacaroni:BAAALgAECgMJAwAAAA==.',
Ty='Tycone:BAAALgAECgcJCgAAAA==.',
Ul='Uldirtydruid:BAABLgAECn8WAAIBAAgJ0RfgEQBAAgABAAgJ0RfgEQBAAgAAAA==.',
Ur='Urukdrak:BAABLgAECn8kAAMSAAkJJA3pDADXAQASAAkJjwnpDADXAQAgAAgJhA0mDwD6AAAAAA==.',
Uw='Uwantwar:BAAALgAECgUJBwAAAA==.',
Va='Valanquishy:BAAALgADCgEJAgAAAA==.',
Ve='Velaryon:BAAALgAECgQJBAAAAA==.',
Vh='Vhagar:BAAALgAECgIJAwAAAA==.',
Vi='Vidich:BAAALgAECgQJBgAAAA==.Viralus:BAAALgADCgEJAQAAAA==.',
Vo='Voiddastard:BAAALgADCgkJFwAAAA==.Voidlight:BAAALgADCgcJBwAAAA==.Volcazzic:BAAALgADCgIJAgAAAA==.',
Vy='Vynnara:BAAALgADCgMJAQAAAA==.',
Wa='Wakkaba:BAAALgADCgYJBgAAAA==.Wanaatlarboy:BAABLgAECn8UAAMdAAYJSBJEIAA7AQAdAAYJSBJEIAA7AQAeAAEJ7gH2XgAiAAAAAA==.Waywyrd:BAAALgADCgMJAwAAAA==.',
Wh='Whack:BAAALgADCgcJCAAAAA==.',
Wi='Willowëd:BAAALgAECgkJAQAAAA==.',
Wu='Wunderbar:BAABLgAECn8eAAILAAYJKhvJJQCNAQALAAYJKhvJJQCNAQAAAA==.Wunderburger:BAAALgAECgYJEQAAAA==.Wunderground:BAAALgAECgQJBAAAAA==.',
Xa='Xannada:BAABLgAECn8kAAIFAAgJgQmBVABKAQAFAAgJgQmBVABKAQAAAA==.',
Ya='Yaoli:BAAALgAECgMJBAAAAA==.',
Ye='Yea:BAAALgADCgcJCwAAAA==.',
Yo='Yodadogownz:BAABLgAECn8LAAIdAAYJogvELADnAAAdAAYJogvELADnAAAAAA==.Yoh:BAABLgAECn8aAAIbAAgJxhqYIQAAAgAbAAgJxhqYIQAAAgAAAA==.Yourenotron:BAAALgADCgYJBgAAAA==.',
Yu='Yungdro:BAAALgAECgEJAQAAAA==.',
Za='Zarutobi:BAAALgAECgYJDgABLgAECggJGQAGANYXAA==.',
Zo='Zob:BAAALgADCgQJBAAAAA==.',
Zu='Zui:BAABLgAECn8cAAIRAAgJaBAdFwB/AQARAAgJaBAdFwB/AQAAAA==.',
['Zù']='Zùg:BAAALgADCgIJAQAAAA==.',
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
