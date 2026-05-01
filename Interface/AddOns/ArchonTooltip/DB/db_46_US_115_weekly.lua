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

local lookup = {'Unknown-Unknown','Priest-Holy','Mage-Frost','Monk-Mistweaver','Priest-Shadow','Warrior-Fury','Paladin-Holy','Monk-Windwalker','Warlock-Demonology','DeathKnight-Unholy','DeathKnight-Frost','Mage-Arcane','Paladin-Retribution','Monk-Brewmaster','Druid-Feral','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Blood','Warrior-Arms','DemonHunter-Devourer','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Restoration','Shaman-Elemental','DemonHunter-Vengeance','Druid-Restoration','Evoker-Preservation','Druid-Guardian','Druid-Balance','Mage-Fire','Priest-Discipline','Warrior-Protection','Paladin-Protection','Shaman-Enhancement',}
local provider = {region='US',realm='Gundrak',name='US',type='weekly',zone=46,date='2026-05-01',data={Ad='Adelyne:BAAALgAECgQJCAAAAA==.Adera:BAAALgAECgYJBwAAAA==.Adria:BAAALgAECgEJAQAAAA==.',
Af='Aff:BAAALgADCgYJBgAAAA==.',
Ah='Ahkanon:BAAALgADCgEJAQAAAA==.',
Ai='Aiden:BAAALgAECgEJAgABLgAECgIJAgABAAAAAA==.Aidendk:BAAALgADCgIJAgABLgAECgIJAgABAAAAAA==.Aidenp:BAAALgADCgIJAgABLgAECgIJAgABAAAAAA==.Air:BAAALgADCgcJBwABLgAFFAYJGAACAIgdAA==.',
Ak='Aku:BAAALgADCgIJBAAAAA==.',
Al='Aleniastra:BAAALgAECgUJCgAAAA==.Alexyss:BAAALgAECgQJCwAAAA==.Alykard:BAABLgAECn8kAAIDAAkJNQ4KIgDiAQADAAkJNQ4KIgDiAQAAAA==.',
Am='Amyara:BAAALgADCgEJAQAAAA==.',
An='Andronicas:BAAALgAECgcJDgAAAA==.Aneira:BAAALgAFFAEJAgAAAA==.',
Ap='Apexis:BAAALgADCgYJCQAAAA==.',
Ar='Ariaa:BAAALgAECgIJAwAAAA==.Arieyri:BAAALgADCgcJBwAAAA==.Artpop:BAAALgAFFAEJAQABLgAFFAQJDAAEAP8UAA==.',
As='Ash:BAAALgADCgcJCwAAAA==.Aspect:BAAALgADCgcJDgABLgAECgEJAQABAAAAAA==.Astarael:BAABLgAECn8bAAMFAAgJ5hZlDgCgAQAFAAcJXxRlDgCgAQACAAUJAg7TWgDIAAAAAA==.',
Av='Avi:BAAALgAECgYJDQABLgAECgkJYAAGAOsaAA==.',
Ba='Babygurl:BAABLgAECn9lAAIHAAkJyCUsAACyAwAHAAkJyCUsAACyAwAAAA==.Baragas:BAAALgAECgUJCAAAAA==.Barney:BAAALgADCgEJAQAAAA==.Battosaî:BAAALgAECgQJBAAAAA==.',
Be='Beeny:BAACLgAFFH8iAAIEAAYJHSPMAABdAgAEAAYJHSPMAABdAgAuAAQKfz4AAwQACAmUI4YIAMwCAAQABwmlJIYIAMwCAAgAAQldDwZDAD4AAAAA.Berat:BAAALgADCgIJAgAAAA==.Berzerker:BAAALgADCgcJEwAAAA==.',
Bg='Bgc:BAAALgADCgUJBQAAAA==.',
Bi='Binari:BAAALgAECgMJAwABLgAFFAMJBQAGACoUAA==.Binlock:BAAALgAECgQJBAABLgAFFAMJBQAGACoUAA==.',
Bl='Bl:BAAALgAECgMJAwAAAA==.Bladebear:BAABLgAECn8sAAIDAAkJChVXFQAxAgADAAkJChVXFQAxAgAAAA==.',
Bo='Boose:BAAALgAECgYJBgAAAA==.Bootybreaker:BAAALgADCgcJBwAAAA==.',
Br='Brat:BAAALgAECgEJAgAAAA==.',
Bu='Bubbleez:BAAALgADCgUJBQAAAA==.Bucklord:BAABLgAECn8iAAMFAAgJjRn+FgAuAgAFAAgJjRn+FgAuAgACAAEJ7xgHOgBHAAAAAA==.Budin:BAAALgAECgcJEQAAAA==.Bullmann:BAAALgADCgQJBAAAAA==.',
Ca='Cannibal:BAAALgAECgcJEAAAAA==.Caplock:BAABLgAECn8VAAIJAAYJnBFdhABRAQAJAAYJnBFdhABRAQAAAA==.Capri:BAAALgAECgUJDQAAAA==.',
Ce='Cellun:BAAALgAECgUJDwAAAA==.Ceredis:BAAALgAECgUJCwAAAA==.',
Ch='Choomoo:BAAALgADCgcJCwAAAA==.',
Cl='Cleankarma:BAAALgADCgEJAwAAAA==.',
Co='Comet:BAAALgAECgEJAQAAAA==.Cool:BAAALgAFFAIJAgAAAA==.Corwiggs:BAAALgAECgYJCwAAAA==.',
Cr='Crikey:BAAALgAECgUJBwAAAA==.Crimínal:BAAALgADCgcJCwAAAA==.Cripsee:BAAALgADCgEJAQAAAA==.',
Cu='Curbie:BAAALgAECgIJAwAAAA==.',
['Cô']='Cônvict:BAAALgADCgYJBgAAAA==.',
De='Deacknight:BAABLgAECn8cAAMKAAgJwRuQLgB+AgAKAAgJwRuQLgB+AgALAAEJig1+FwAyAAABLgADCgYJBwABAAAAAA==.Deacmonk:BAAALgADCgYJBgABLgADCgYJBwABAAAAAA==.Definitely:BAACLgAFFH8GAAIDAAIJOh9UNgC+AAADAAIJOh9UNgC+AAAuAAQKfycAAwMABwmyI00QAFoCAAMABwmyI00QAFoCAAwAAQkPICgbAD8AAAAA.Deki:BAEALgAECgYJBgAAAA==.Desariana:BAABLgAECn8XAAINAAgJIQ+deACJAQANAAgJIQ+deACJAQAAAA==.',
Di='Diggitie:BAAALgAECgEJAQAAAA==.',
Do='Dormas:BAAALgAECgYJDAAAAA==.Doug:BAAALgADCgEJAQAAAA==.',
Dr='Drakeon:BAAALgADCgYJBwABLgAECgkJYAAGAOsaAA==.',
Ee='Eeryxx:BAAALgAECgEJAQAAAA==.',
El='Eldh:BAABLgAECn8XAAIOAAcJggsuGgAtAQAOAAcJggsuGgAtAQAAAA==.Eleison:BAAALgADCgMJAwAAAA==.Elendrial:BAAALgAECgIJAgAAAA==.Elendril:BAAALgADCgcJFQAAAA==.Elisoly:BAABLgAECn8WAAIHAAYJoRk5FAC0AQAHAAYJoRk5FAC0AQAAAA==.',
Em='Emrald:BAAALgAECgYJEwAAAA==.',
En='Endlessly:BAACLgAFFH8FAAIPAAIJPBXTAwC2AAAPAAIJPBXTAwC2AAAuAAQKfyEAAg8ACAmfIukDAOsCAA8ACAmfIukDAOsCAAAA.Enerchi:BAAALgADCgMJAwAAAA==.',
Er='Erivoker:BAAALgAECgYJBgABLgAECgYJEgABAAAAAA==.Errimage:BAAALgAECgYJEgAAAA==.Errishoot:BAAALgAECgUJBQABLgAECgYJEgABAAAAAA==.Ervinia:BAAALgADCgYJCgABLgAECgUJCgABAAAAAA==.',
Ev='Evelinar:BAAALgAECgMJAwAAAA==.Evoslex:BAABLgAECn8mAAMQAAkJ9yEkAQAiAwAQAAkJ9yEkAQAiAwARAAYJzx1oEwCsAQAAAA==.',
Ex='Exo:BAECLgAFFH8UAAISAAUJkRXwBwAbAQASAAUJkRXwBwAbAQAuAAQKfyIAAhIACQn7HC0GANUCABIACQn7HC0GANUCAAAA.',
Fa='Facerolleh:BAACLgAFFH8gAAMGAAYJKSGIBgCGAQAGAAQJZiGIBgCGAQATAAQJRB4XBAD7AAAuAAQKfz4AAwYACAkAJs8EAFwDAAYACAn2Jc8EAFwDABMABwnRIIwIACsCAAAA.',
Fe='Feelgoodinc:BAAALgADCgkJFAAAAA==.',
Fi='Fidah:BAAALgADCgEJAQAAAA==.Firemagemain:BAAALgADCgUJBQABLgAFFAMJBQAGACoUAA==.',
Fl='Flop:BAAALgAECgQJBAABLgAECggJFwADAOUeAA==.',
Fr='Frostmere:BAAALgADCggJGQAAAA==.',
Fu='Fuknazum:BAAALgADCgYJBgAAAA==.Furcht:BAAALgAECgYJCwAAAA==.',
Ga='Galadar:BAAALgADCgUJBQAAAA==.',
Gi='Gitèff:BAAALgAFFAIJAwAAAA==.',
Go='Gourdin:BAAALgAECgQJBQABLgAECgUJBQABAAAAAA==.',
Gr='Gramnpa:BAAALgADCgUJBQAAAA==.Gravepriest:BAAALgAECgEJAQAAAA==.Grimtysha:BAAALgAECgQJBAAAAA==.Gromit:BAAALgAECgQJCQAAAA==.',
He='Hellbourne:BAABLgAECn8RAAIUAAYJ/xegIgBkAQAUAAYJ/xegIgBkAQAAAA==.',
Hi='Himmel:BAAALgADCgMJBAAAAA==.',
Ho='Hopnhorsé:BAAALgADCgEJAQAAAA==.Hotchoq:BAAALgAECgIJBQAAAA==.',
Hu='Huntchoq:BAABLgAFFH8HAAQVAAQJJQ/7BQBDAQAVAAQJbgr7BQBDAQAWAAIJSgg7LgCcAAAXAAEJiRHcFABQAAAAAA==.Huxley:BAAALgADCgMJAwAAAA==.',
Ik='Ikan:BAAALgAECgQJBAAAAA==.',
In='Infest:BAAALgAECgQJCAAAAA==.Inzolethys:BAAALgADCgcJBwAAAA==.',
It='Itchy:BAAALgADCgEJAgAAAA==.Itskiohte:BAAALgAECggJDwAAAA==.',
Ja='Jaggernut:BAAALgADCgUJBQAAAA==.',
Jo='Johnny:BAAALgAECgIJAgABLgAECgkJJgAQAPchAA==.',
Ju='Judeau:BAAALgADCgEJAQAAAA==.',
Ka='Kaelthuzzad:BAAALgADCgEJAQAAAA==.Kaitza:BAAALgAECgYJCwAAAA==.Kalzaketh:BAABLgAECn8mAAMQAAcJRwllIgDxAAAQAAcJRwllIgDxAAARAAMJ5QSCMwB5AAAAAA==.Kashari:BAAALgAECgEJAQAAAA==.Katali:BAAALgADCgYJBgAAAA==.Kazuggar:BAACLgAFFH8LAAIYAAQJOB+iCABcAQAYAAQJOB+iCABcAQAuAAQKfykAAxgACAlRJW0CAFwDABgACAlRJW0CAFwDABkAAwleGkddAM4AAAAA.',
Ke='Kebau:BAAALgADCgEJAQAAAA==.Kedar:BAAALgAECgYJCwAAAA==.Keg:BAAALgAECgIJAgAAAA==.Kelabar:BAAALgADCgQJBAAAAA==.',
Ki='Kick:BAAALgADCgQJBAABLgAFFAUJCgADAOIOAA==.Kiffs:BAAALgAECgcJCgAAAA==.Kirâ:BAAALgAECgYJDgAAAA==.',
Kr='Kregnar:BAAALgAECgYJEAAAAA==.Kresh:BAAALgAECgcJCwAAAA==.',
Ku='Kucabara:BAAALgADCgYJCQAAAA==.Kuraiwiggs:BAAALgADCgYJDAAAAA==.',
Kw='Kwichang:BAAALgAECgYJDQAAAA==.',
['Ké']='Kélpo:BAAALgADCgMJBAAAAA==.',
La='Lasagne:BAAALgADCgMJAwAAAA==.',
Li='Lickynose:BAABLgAECn8aAAIDAAgJEiCYCwCKAgADAAgJEiCYCwCKAgAAAA==.Lips:BAAALgAECgEJAQAAAA==.',
Ls='Ls:BAABLgAECn8TAAMaAAgJTR/IBACdAQAUAAcJkiK9MQAzAgAaAAcJXxXIBACdAQAAAA==.',
Ma='Madarabia:BAAALgAECgYJDQAAAA==.Magellann:BAAALgAECgMJAwAAAA==.Mallidan:BAAALgADCgkJCQAAAA==.Mamut:BAAALgAECgEJAQAAAA==.Mantisar:BAABLgAECn8UAAINAAYJOhosMwB2AQANAAYJOhosMwB2AQAAAA==.Maxsm:BAABLgAECn8XAAIZAAgJrhmQIQACAgAZAAgJrhmQIQACAgAAAA==.',
Me='Melanippe:BAABLgAECn8XAAIbAAYJDhtwPQCuAQAbAAYJDhtwPQCuAQAAAA==.Meleefox:BAAALgADCgUJBQAAAA==.Melethron:BAABLgAECn8rAAINAAkJIhllCgB7AgANAAkJIhllCgB7AgAAAA==.Melioknky:BAAALgAECgYJBgAAAA==.',
Mi='Mid:BAAALgADCgYJBgAAAA==.Mightymage:BAABLgAECn8eAAIDAAcJRA4NQQBrAQADAAcJRA4NQQBrAQAAAA==.Milliondruid:BAAALgAECgMJBAAAAA==.Millionsm:BAAALgADCgQJBQAAAA==.Mirrorimage:BAAALgAECgMJBQABLgAFFAQJDQAFALkTAA==.Mirrorx:BAACLgAFFH8NAAIFAAQJuROOBgBSAQAFAAQJuROOBgBSAQAuAAQKfycAAgUACAkoHWoHABECAAUACAkoHWoHABECAAAA.Miy:BAAALgAECgEJAQAAAA==.',
Mo='Mongon:BAAALgAECgYJBgAAAA==.Moogle:BAAALgAECgIJBAAAAA==.Moomie:BAABLgAECn8cAAIbAAgJzhQmIQB3AQAbAAgJzhQmIQB3AQAAAA==.Moosfel:BAAALgAECgYJEAAAAA==.',
Mt='Mtzz:BAAALgAECgUJBQAAAA==.',
My='Mygravebroke:BAAALgADCggJCQAAAA==.Mystdragon:BAACLgAFFH8LAAIcAAQJBx8xBwBuAQAcAAQJBx8xBwBuAQAuAAQKfygAAhwACAlTIP8FAOYCABwACAlTIP8FAOYCAAEuAAUUBgkZAAQAgR4A.Mystweaverr:BAACLgAFFH8ZAAIEAAYJgR4fAgAMAgAEAAYJgR4fAgAMAgAuAAQKfykAAgQACAnnIHsJALkCAAQACAnnIHsJALkCAAAA.',
['Mö']='Mörae:BAAALgADCgEJAQABLgAECgYJFwAbAA4bAA==.',
Na='Naddar:BAACLgAFFH8IAAIHAAQJswm4DQAgAQAHAAQJswm4DQAgAQAuAAQKfyIAAgcABwmdILAFAI0CAAcABwmdILAFAI0CAAAA.Namadgi:BAAALgAECgcJEgAAAA==.Nathria:BAAALgAECgIJAgAAAA==.',
Ne='Netalis:BAABLgAECn8aAAIbAAgJ2xD1HQCRAQAbAAgJ2xD1HQCRAQAAAA==.',
Ni='Nikonii:BAAALgADCgQJBAAAAA==.',
Nu='Nurckers:BAAALgAECgQJBAAAAA==.',
Oa='Oakinelf:BAAALgADCgcJAQAAAA==.',
Om='Omnishifts:BAAALgADCgQJBAAAAA==.',
Or='Oramo:BAABLgAECn8aAAMSAAgJCSMlBQDxAgASAAgJwyIlBQDxAgAKAAYJ4R3lkgBaAQAAAA==.',
Pa='Paradisya:BAAALgADCggJDgAAAA==.',
Pe='Perceptor:BAAALgAECgEJAQABLgAECgkJKQAdAJMhAA==.Pets:BAAALgAECgEJAQABLgAECgEJAgABAAAAAA==.',
Pl='Placebo:BAAALgAECgUJBQABLgAFFAIJBQAPADwVAA==.',
Pr='Prothero:BAABLgAFFH8JAAMDAAQJ6R6fDQCKAQADAAQJ6R6fDQCKAQAMAAEJIxlHAQBbAAAAAA==.Proyo:BAAALgADCgUJBQAAAA==.',
['På']='Påthor:BAABLgAECn8XAAIeAAcJFBrIEQB/AQAeAAcJFBrIEQB/AQAAAA==.',
Ra='Raikonnen:BAAALgAECgEJAQAAAA==.Rawtoor:BAACLgAFFH8QAAIUAAUJph04DgBFAQAUAAUJph04DgBFAQAuAAQKfxsAAhQACAn8INEnAGUCABQACAn8INEnAGUCAAAA.',
Re='Rebelsister:BAAALgADCgcJEAAAAA==.Refridgerate:BAAALgADCgUJBwAAAA==.',
Ri='Riddagain:BAAALgAECgYJDgAAAA==.Ridgemonk:BAABLgAECn8YAAMOAAgJwByWDADBAQAOAAgJwByWDADBAQAEAAQJQAGWYABMAAAAAA==.Riggsdk:BAAALgADCgcJBwABLgAFFAYJFwAVALUkAA==.Riggshunt:BAACLgAFFH8XAAQVAAYJtSQxAAAHAgAVAAYJFSQxAAAHAgAWAAQJtCLTAACrAQAXAAEJAACnKABKAAAuAAQKfxoABBYACAmrJsEIAAcDABYABwmYJsEIAAcDABUACAlsJJEDAOwCABcAAQmCHFd9AE8AAAAA.',
Ro='Roadkill:BAABLgAECn8gAAISAAgJnSNwAgBEAgASAAgJnSNwAgBEAgAAAA==.Rolltoor:BAAALgAFFAEJAQAAAA==.Roonate:BAAALgADCgUJBQAAAA==.Rosemary:BAAALgAECgQJBAAAAA==.',
Ry='Ryujin:BAAALgAECgQJCQAAAA==.',
Sa='Saiko:BAAALgAFFAIJAgAAAA==.Sansa:BAACLgAFFH8PAAIVAAUJJh4YAwBwAQAVAAUJJh4YAwBwAQAuAAQKfyEAAhUACAlmJF0CABwDABUACAlmJF0CABwDAAAA.Saso:BAACLgAFFH8MAAIDAAQJgBT8GgBfAQADAAQJgBT8GgBfAQAuAAQKfyoABAMACAnVI04KAJoCAAMACAnVI04KAJoCAAwAAwkDH0cMAA0BAB8AAgnECLALAHcAAAAA.Sastroll:BAAALgAECgUJBQAAAA==.',
Sc='Scorn:BAAALgADCgcJCAAAAA==.Scroll:BAAALgAECgYJCQAAAA==.',
Se='Seluvis:BAAALgAECgYJCwAAAA==.Sentai:BAAALgADCgcJBwAAAA==.Serapayne:BAAALgAECgcJAQAAAA==.',
Sh='Shadow:BAABLgAECn8pAAIUAAgJmR1pHACoAgAUAAgJmR1pHACoAgAAAA==.Shandrilah:BAAALgADCgQJBAAAAA==.Shapeshift:BAAALgADCgUJBQABLgAECgIJAgABAAAAAA==.Shialebuff:BAABLgAECn8bAAMCAAgJHiCeFwAfAgACAAcJkCCeFwAfAgAFAAUJGxPPPgD/AAAAAA==.Shijin:BAAALgAECgQJBQAAAA==.Shortfuze:BAAALgAECgYJCwAAAA==.',
Si='Sindar:BAAALgADCgUJBQAAAA==.Sinfall:BAAALgAECgUJBQAAAA==.Siscomp:BAABLgAECn9gAAIGAAkJ6xpABACBAgAGAAkJ6xpABACBAgAAAA==.Sixth:BAAALgAECgYJEAAAAA==.Sizzle:BAAALgADCgMJAwAAAA==.',
Sk='Skateboard:BAAALgADCgEJAQAAAA==.Sky:BAACLgAFFH8SAAIgAAcJegs2AwDQAQAgAAcJegs2AwDQAQAuAAQKfxQAAyAACAlxE48cALABACAABwlZEo8cALABAAIABQnyD3tMAAYBAAAA.',
Sl='Sleck:BAAALgAECgYJDAAAAA==.',
Sn='Snappa:BAAALgADCgYJCwAAAA==.Sniped:BAAALgAFFAEJAQAAAA==.Snugglepuff:BAAALgAECggJDAAAAA==.',
So='Soapfidas:BAAALgADCggJCgAAAA==.Sonarius:BAABLgAECn8XAAMDAAgJ5R4nPACHAgADAAgJ5R4nPACHAgAfAAEJshIRDwA8AAAAAA==.',
Su='Su:BAABLgAECn8yAAIEAAcJ4yVSBACaAgAEAAcJ4yVSBACaAgAAAA==.Sudno:BAAALgAECgQJCAAAAA==.Sundae:BAABLgAECn8eAAMCAAgJgSKvAQANAwACAAgJgSKvAQANAwAgAAQJFBm/LQAwAQAAAA==.Supersinpe:BAAALgAECgIJAgAAAA==.',
Sv='Svendlefyre:BAAALgADCgcJDgABLgAECgYJJAAPANMXAA==.Svholydrag:BAAALgADCgEJAQAAAA==.Svmishima:BAAALgAECgEJAQAAAA==.',
Sy='Sylvie:BAAALgAECggJCgAAAA==.',
['Sý']='Sýlvanas:BAAALgAECgMJCQAAAA==.',
Te='Tealç:BAABLgAECn8ZAAIhAAcJpRdhDQBKAQAhAAcJpRdhDQBKAQAAAA==.Tekk:BAAALgAECgEJAQAAAA==.Tekkys:BAAALgAECgEJAQAAAA==.Tertle:BAAALgADCgUJBQAAAA==.',
Ti='Tiafinia:BAAALgAECgEJAgAAAA==.Timur:BAAALgAECgEJAQAAAA==.Tinara:BAAALgADCgUJBQAAAA==.',
Tr='Trigger:BAAALgAECgIJAgAAAA==.',
Tu='Turlesblows:BAABLgAECn8VAAMGAAYJXCFeJAA0AgAGAAYJXCFeJAA0AgAhAAEJOxWbRAA7AAAAAA==.',
Tw='Twityy:BAAALgADCgEJAgAAAA==.Twofiveyd:BAAALgAECgkJCQABLgAFFAYJEwATAAEWAA==.',
Ty='Tyladrhas:BAABLgAECn8jAAIaAAgJcB82AQB5AgAaAAgJcB82AQB5AgAAAA==.Tyrismaximus:BAAALgADCgQJBgAAAA==.',
Ul='Ulkina:BAAALgADCgYJCQAAAA==.',
Va='Vaelith:BAAALgAECgIJAgAAAA==.Valerine:BAABLgAECn8YAAIDAAcJlg3SSwBMAQADAAcJlg3SSwBMAQAAAA==.Vanoran:BAAALgAECgMJAwAAAA==.Varang:BAAALgAECgIJAgAAAA==.Varina:BAAALgAECgcJEQAAAA==.',
Ve='Venki:BAAALgADCgcJDAAAAA==.',
Vo='Voidnova:BAABLgAFFH8GAAIDAAIJoxKNSwCoAAADAAIJoxKNSwCoAAAAAA==.Voidphayze:BAAALgAECgUJDAAAAA==.',
Vu='Vulken:BAABLgAECn9ZAAIWAAkJuSJcAQAgAwAWAAkJuSJcAQAgAwAAAA==.',
['Vê']='Vê:BAAALgAECggJDgAAAA==.',
Wa='Wallace:BAAALgAECgcJDAAAAA==.Walterlight:BAAALgAECgYJDgAAAA==.Watto:BAAALgAECggJDwAAAA==.',
We='Wemongin:BAAALgADCgUJBQAAAA==.',
Wh='Whimsical:BAAALgAECgYJCwAAAA==.',
Wi='Winnìng:BAABLgAECn8WAAIiAAgJkgoMEAAAAQAiAAgJkgoMEAAAAQAAAA==.',
Wu='Wugong:BAAALgADCgEJAQAAAA==.',
['Wó']='Wórkwórk:BAACLgAFFH8FAAIGAAMJKhRuFADbAAAGAAMJKhRuFADbAAAuAAQKfxkAAwYACAmeHhQ3AMsBAAYABQlkIRQ3AMsBABMAAwnsGsIfAO8AAAAA.',
Zi='Zich:BAAALgADCgMJAwAAAA==.Zihon:BAAALgAECgQJEgAAAA==.',
Zo='Zodiiak:BAABLgAECn8wAAIjAAgJJh07BQDJAQAjAAgJJh07BQDJAQAAAA==.',
Zu='Zupp:BAAALgAECgYJBwAAAA==.',
Zx='Zx:BAAALgADCgYJBgAAAA==.',
['Ér']='Ér:BAAALgAECgkJBQAAAA==.',
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
