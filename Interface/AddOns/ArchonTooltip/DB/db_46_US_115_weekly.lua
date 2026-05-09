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

local lookup = {'Priest-Discipline','Unknown-Unknown','Priest-Holy','Mage-Frost','Monk-Mistweaver','Priest-Shadow','Warrior-Fury','Paladin-Holy','Monk-Windwalker','Druid-Restoration','Warlock-Demonology','DeathKnight-Unholy','DeathKnight-Frost','Mage-Arcane','Paladin-Retribution','Monk-Brewmaster','Druid-Feral','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Blood','Warrior-Arms','DemonHunter-Devourer','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Enhancement','Shaman-Restoration','Shaman-Elemental','DemonHunter-Vengeance','Evoker-Preservation','Druid-Guardian','Druid-Balance','Mage-Fire','Warrior-Protection','Paladin-Protection',}
local provider = {region='US',realm='Gundrak',name='US',type='weekly',zone=46,date='2026-05-08',data={Ad='Adelyne:BAAALgAECgQJCAABLgAFFAUJDgABAG0SAA==.Adera:BAAALgAECgYJBwAAAA==.Adria:BAAALgAECgEJAgAAAA==.',
Af='Aff:BAAALgADCgYJBgAAAA==.',
Ag='Agony:BAAALgAECgEJAQAAAA==.',
Ah='Ahkanon:BAAALgADCgEJAQAAAA==.',
Ai='Aiden:BAAALgAECgEJAgABLgAECgIJAgACAAAAAA==.Aidendk:BAAALgADCgIJAgABLgAECgIJAgACAAAAAA==.Aidenp:BAAALgADCgIJAgABLgAECgIJAgACAAAAAA==.Air:BAAALgADCgcJBwABLgAFFAYJGQADAP0dAA==.',
Ak='Aku:BAAALgADCgIJBAAAAA==.',
Al='Aleniastra:BAAALgAECgUJCgAAAA==.Alexyss:BAAALgAECgUJDgAAAA==.Alykard:BAABLgAECn8lAAIEAAkJNQ5NMADfAQAEAAkJNQ5NMADfAQAAAA==.',
Am='Amyara:BAAALgADCgEJAQAAAA==.',
An='Andronicas:BAAALgAECgcJDgAAAA==.Aneira:BAAALgAFFAEJAgAAAA==.',
Ap='Apexis:BAAALgADCgYJCQAAAA==.',
Ar='Ariaa:BAAALgAECgIJAwAAAA==.Arieyri:BAAALgADCgcJBwAAAA==.Artpop:BAAALgAFFAEJAQABLgAFFAUJDQAFAKETAA==.',
As='Ash:BAAALgADCgcJCwAAAA==.Aspect:BAAALgADCgcJDgABLgAECgEJAQACAAAAAA==.Astarael:BAABLgAECn8hAAMGAAgJGBZADQD1AQAGAAgJGBZADQD1AQADAAYJYw/aWgDIAAAAAA==.',
Av='Avi:BAABLgAECn8VAAIBAAcJ6BAgFQCWAQABAAcJ6BAgFQCWAQABLgAECgkJaQAHABceAA==.',
Ba='Babygurl:BAABLgAECn9tAAIIAAkJ7SVcAACzAwAIAAkJ7SVcAACzAwAAAA==.Baragas:BAAALgAECgUJCQAAAA==.Barney:BAAALgADCgEJAQAAAA==.Battosaî:BAAALgAECgQJBAAAAA==.',
Be='Beeny:BAACLgAFFH8sAAIFAAYJKCPuAQBVAgAFAAYJKCPuAQBVAgAuAAQKfz8AAwUACAmUI4QIAMwCAAUABwmlJIQIAMwCAAkAAQljEGVYADoAAAAA.Berat:BAAALgADCgIJAgAAAA==.Berzerker:BAAALgADCgcJEwAAAA==.',
Bg='Bgc:BAAALgADCgUJBQAAAA==.',
Bi='Binari:BAAALgAECgMJAwABLgAFFAMJBQAHACoUAA==.Binlock:BAAALgAECgQJBAABLgAFFAMJBQAHACoUAA==.',
Bl='Bl:BAAALgAECgMJAwAAAA==.Bladebear:BAABLgAECn82AAIEAAkJUhVAHwAvAgAEAAkJUhVAHwAvAgAAAA==.',
Bo='Boose:BAAALgAECgYJBgAAAA==.Bootybreaker:BAAALgADCgcJBwAAAA==.',
Br='Brat:BAAALgAECgEJAgABLgAECggJNgADAOMUAA==.Bréwmaster:BAAALgAECgEJAQABLgAECggJIQAGABgWAA==.',
Bu='Bubbleez:BAAALgADCgUJBQAAAA==.Bucklord:BAABLgAECn8iAAMGAAgJjRn7FgAuAgAGAAgJjRn7FgAuAgADAAEJ7xiCSABDAAAAAA==.Budin:BAAALgAECggJEgAAAA==.Bullmann:BAAALgADCgQJBAAAAA==.',
Ca='Cannibal:BAABLgAECn8dAAIKAAgJ0hvzDQBxAgAKAAgJ0hvzDQBxAgAAAA==.Caplock:BAABLgAECn8VAAILAAYJnBFehABRAQALAAYJnBFehABRAQAAAA==.Capri:BAAALgAECgUJDQAAAA==.',
Ce='Cellun:BAAALgAECgUJDwAAAA==.Ceredis:BAAALgAECgUJCwAAAA==.',
Ch='Choomoo:BAAALgADCgcJCwABLgAFFAMJCAAFAOEJAA==.',
Cl='Cleankarma:BAAALgADCgEJAwAAAA==.',
Co='Comet:BAAALgAECgEJAQAAAA==.Cool:BAAALgAFFAIJAgAAAA==.Corwiggs:BAAALgAECgYJCwAAAA==.',
Cr='Crikey:BAAALgAECgUJBwAAAA==.Crimínal:BAAALgADCgcJCwAAAA==.Cripsee:BAAALgADCgIJAgAAAA==.',
Cu='Curbie:BAAALgAECgIJAwAAAA==.',
['Cô']='Cônvict:BAAALgADCgYJBgAAAA==.',
De='Deacknight:BAABLgAECn8cAAMMAAgJwRuJLgB+AgAMAAgJwRuJLgB+AgANAAEJig1+FwAyAAABLgADCgYJBwACAAAAAA==.Deacmonk:BAAALgADCgYJBgABLgADCgYJBwACAAAAAA==.Definitely:BAACLgAFFH8IAAIEAAIJOh9ZNgC+AAAEAAIJOh9ZNgC+AAAuAAQKfyoAAwQACAkIIxINALYCAAQACAkIIxINALYCAA4AAQkPICkbAD8AAAAA.Deki:BAEALgAECgYJBgAAAA==.Dementiaous:BAAALgAECgIJAwAAAA==.Desariana:BAABLgAECn8fAAIPAAgJ8xDMXAA2AQAPAAgJ8xDMXAA2AQAAAA==.',
Di='Diggitie:BAAALgAECgEJAQAAAA==.',
Do='Dormas:BAAALgAECgYJEQAAAA==.Doug:BAAALgADCgEJAQAAAA==.',
Dr='Drakeon:BAAALgAECgQJBQABLgAECgkJaQAHABceAA==.',
Ee='Eeryxx:BAAALgAECgEJAQAAAA==.',
El='Eldh:BAABLgAECn8ZAAIQAAgJVAtGHABRAQAQAAgJVAtGHABRAQAAAA==.Eleison:BAAALgADCgMJAwAAAA==.Elendrial:BAAALgAECgIJAgAAAA==.Elendril:BAAALgADCgcJFQAAAA==.Elisoly:BAABLgAECn8WAAIIAAYJohlpHQCbAQAIAAYJohlpHQCbAQAAAA==.',
Em='Emrald:BAAALgAECgYJEwAAAA==.',
En='Endlessly:BAACLgAFFH8JAAIRAAMJpBZIBAAVAQARAAMJpBZIBAAVAQAuAAQKfyIAAhEACAmfIukDAOsCABEACAmfIukDAOsCAAAA.Enerchi:BAAALgADCgMJAwAAAA==.',
Er='Erivoker:BAAALgAECgYJBwABLgAECgYJEgACAAAAAA==.Errimage:BAAALgAECgYJEgAAAA==.Errishoot:BAAALgAECgUJBwABLgAECgYJEgACAAAAAA==.Ervinia:BAAALgADCgYJCgABLgAECgUJCgACAAAAAA==.',
Ev='Evelinar:BAAALgAECgMJAwAAAA==.Evoslex:BAABLgAECn8wAAMSAAkJwSNSAQBHAwASAAkJwSNSAQBHAwATAAYJzx1pEwCsAQAAAA==.',
Ex='Exo:BAECLgAFFH8ZAAIUAAUJbhoeCABJAQAUAAUJbhoeCABJAQAuAAQKfyIAAhQACQn7HC4GANYCABQACQn7HC4GANYCAAAA.',
Fa='Facerolleh:BAACLgAFFH8pAAMVAAYJjCI1AQDmAQAVAAYJGiI1AQDmAQAHAAQJZiGJBgCGAQAuAAQKfz8AAwcACAlIJs0EAFwDAAcACAn2Jc0EAFwDABUABwkaIYsIACsCAAAA.Fatedx:BAAALgADCgEJAQAAAA==.',
Fe='Feelgoodinc:BAAALgADCgkJFAAAAA==.',
Fi='Fidah:BAAALgADCgEJAQAAAA==.Firemagemain:BAAALgADCgUJBQABLgAFFAMJBQAHACoUAA==.',
Fl='Flop:BAAALgAECgQJBAABLgAECggJFwAEAOUeAA==.',
Fr='Frostmere:BAAALgADCggJGQAAAA==.',
Fu='Fuknazum:BAAALgAECgEJAQAAAA==.Furcht:BAAALgAECgYJCwAAAA==.',
Ga='Galadar:BAAALgADCgUJBQAAAA==.',
Gi='Gitèff:BAAALgAFFAIJAwAAAA==.',
Go='Gourdin:BAAALgAECgQJBQABLgAECgYJCAACAAAAAA==.',
Gr='Gramnpa:BAAALgADCgUJBQAAAA==.Gravepriest:BAAALgAECgEJAQAAAA==.Grimtysha:BAAALgAECgQJBQAAAA==.Grimveil:BAAALgAECgYJBgAAAA==.Gromit:BAAALgAECgQJCQAAAA==.',
Ha='Harafar:BAAALgAFFAEJAQAAAA==.',
He='Hellbourne:BAABLgAECn8XAAIWAAYJ5RgaMgBtAQAWAAYJ5RgaMgBtAQAAAA==.',
Hi='Himmel:BAAALgADCgcJCAAAAA==.',
Ho='Hopnhorsé:BAAALgADCgEJAQAAAA==.Hotchoq:BAAALgAECgIJBQAAAA==.',
Hu='Huntchoq:BAABLgAFFH8IAAQXAAQJJA82CgA5AQAXAAQJbAo2CgA5AQAYAAIJSgieQACWAAAZAAEJiRGrGwBMAAAAAA==.Huxley:BAAALgADCgMJAwAAAA==.',
Ik='Ikan:BAAALgAECgQJBAAAAA==.',
In='Infest:BAAALgAECgQJCAAAAA==.Inzolethys:BAAALgADCgcJBwAAAA==.',
It='Itchy:BAAALgADCgEJAgAAAA==.Itskiohte:BAABLgAECn8YAAIaAAgJIA1BDQAzAQAaAAgJIA1BDQAzAQAAAA==.',
Ja='Jaggernut:BAAALgADCgUJBQAAAA==.',
Jo='Johnny:BAAALgAECgIJAgABLgAECgkJMAASAMEjAA==.',
Ju='Judeau:BAAALgADCgEJAQAAAA==.',
Ka='Kaelthuzzad:BAAALgADCgEJAQAAAA==.Kaitza:BAAALgAECgYJCwAAAA==.Kalzaketh:BAABLgAECn80AAMSAAcJlQvxIgAuAQASAAcJlQvxIgAuAQATAAMJ5QR/MwB5AAAAAA==.Kashari:BAAALgAECgEJAgABLgAECgkJaQAGAAgbAA==.Katali:BAAALgAECgEJAQAAAA==.Kazuggar:BAACLgAFFH8NAAIbAAQJNB+2DgBOAQAbAAQJNB+2DgBOAQAuAAQKfyoAAxsACAlRJW4CAFwDABsACAlRJW4CAFwDABwAAwleGktdAM4AAAAA.Kazzn:BAAALgAECgYJBgAAAA==.',
Ke='Kedar:BAAALgAECgYJCwAAAA==.Keg:BAAALgAECgIJAgAAAA==.Kelabar:BAAALgADCgQJBAAAAA==.',
Ki='Kick:BAAALgADCgQJBAABLgAFFAUJDwAEAOcOAA==.Kiffs:BAAALgAECgcJCgAAAA==.Kill:BAAALgAECgIJAgABLgAECggJBAACAAAAAA==.Kirâ:BAAALgAECggJEAAAAA==.',
Kr='Kregnar:BAABLgAECn8WAAIVAAYJhRVLDwBRAQAVAAYJhRVLDwBRAQAAAA==.Kresh:BAAALgAECgcJCwAAAA==.',
Ku='Kucabara:BAAALgAECgEJAQAAAA==.Kuraiwiggs:BAAALgADCgYJDAAAAA==.',
Kw='Kwichang:BAABLgAECn8UAAIEAAcJlg4zeQAeAQAEAAcJlg4zeQAeAQAAAA==.',
['Ké']='Kélpo:BAAALgADCgMJBAAAAA==.',
La='Lasagne:BAAALgADCgMJAwAAAA==.',
Li='Lickynose:BAABLgAECn8hAAIEAAgJFSE4EACYAgAEAAgJFSE4EACYAgAAAA==.Lips:BAAALgAECgEJAQAAAA==.',
Ls='Ls:BAABLgAECn8aAAMdAAgJmiENBwCEAQAWAAgJmiGRJwCdAQAdAAcJYRUNBwCEAQAAAA==.',
Ma='Madarabia:BAAALgAECgYJDQAAAA==.Magellann:BAAALgAECgMJAwAAAA==.Mamut:BAAALgAECgEJAQAAAA==.Mantisar:BAABLgAECn8ZAAIPAAYJVB1kLwC/AQAPAAYJVB1kLwC/AQAAAA==.Maxsm:BAABLgAECn8XAAIcAAgJrhmPIQACAgAcAAgJrhmPIQACAgAAAA==.',
Me='Melanippe:BAABLgAECn8XAAIKAAYJDhtrPQCuAQAKAAYJDhtrPQCuAQAAAA==.Meleefox:BAAALgADCgUJBQAAAA==.Melethron:BAABLgAECn81AAIPAAkJWxwPCgC5AgAPAAkJWxwPCgC5AgAAAA==.Melioknky:BAAALgAECgYJBgAAAA==.',
Mi='Mid:BAAALgADCgYJBgAAAA==.Mightymage:BAABLgAECn8hAAIEAAgJ3Q2jRACZAQAEAAgJ3Q2jRACZAQAAAA==.Milliondruid:BAAALgAECgMJBAAAAA==.Millionsm:BAAALgADCgQJBQAAAA==.Mirrorimage:BAAALgAECgMJBQABLgAFFAUJDwAGALIUAA==.Mirrorx:BAACLgAFFH8PAAIGAAUJshRTCgBRAQAGAAUJshRTCgBRAQAuAAQKfyoAAgYACAkLIAwHAGACAAYACAkLIAwHAGACAAAA.Miy:BAAALgAECgEJAQAAAA==.',
Mo='Mongon:BAAALgAECgYJBgAAAA==.Moogle:BAAALgAECgIJBAAAAA==.Moomie:BAABLgAECn8cAAIKAAgJzhTQOwC1AQAKAAgJzhTQOwC1AQAAAA==.Moosfel:BAABLgAECn8UAAIRAAYJVRa8FwBDAQARAAYJVRa8FwBDAQAAAA==.',
Mt='Mtzz:BAAALgAECgUJBQABLgAECgYJCAACAAAAAA==.',
My='Mygravebroke:BAAALgADCggJCQAAAA==.Mystdragon:BAACLgAFFH8OAAIeAAQJCB/vCgBoAQAeAAQJCB/vCgBoAQAuAAQKfygAAh4ACAlTIP4FAOYCAB4ACAlTIP4FAOYCAAEuAAUUBwkeAAUAMR4A.Mystweaverr:BAACLgAFFH8eAAIFAAcJMR5UAQB7AgAFAAcJMR5UAQB7AgAuAAQKfywAAwUACAksIXwJALkCAAUACAksIXwJALkCAAkAAgkjIvEvAMYAAAAA.',
['Mö']='Mörae:BAAALgADCgEJAQABLgAECgYJFwAKAA4bAA==.',
Na='Naddar:BAACLgAFFH8MAAIIAAQJ+hWPEAAwAQAIAAQJ+hWPEAAwAQAuAAQKfy0AAggACAmlH8cEAOMCAAgACAmlH8cEAOMCAAAA.Namadgi:BAABLgAECn8ZAAIKAAgJ+hkNEwAyAgAKAAgJ+hkNEwAyAgAAAA==.Nathria:BAAALgAECgIJAwAAAA==.',
Ne='Netalis:BAABLgAECn8eAAIKAAgJshEBJQChAQAKAAgJshEBJQChAQAAAA==.',
Ni='Nikonii:BAAALgADCgQJBAAAAA==.',
Nu='Nurckers:BAAALgAECgcJCAAAAA==.',
Oa='Oakinelf:BAAALgADCgcJAQAAAA==.',
Om='Omnishifts:BAAALgADCgQJBAAAAA==.',
Or='Oramo:BAABLgAECn8aAAMUAAgJCSMmBQDxAgAUAAgJwyImBQDxAgAMAAYJ4R3pkgBaAQAAAA==.',
Pa='Paradisya:BAAALgADCggJDgAAAA==.',
Pe='Perceptor:BAAALgAECgEJAQABLgAECgkJKQAfAJMhAA==.Pets:BAAALgAECgEJAQABLgAECggJNgADAOMUAA==.',
Pl='Placebo:BAAALgAECgUJBQABLgAFFAMJCQARAKQWAA==.',
Pr='Prothero:BAABLgAFFH8NAAMEAAQJoR80FwCDAQAEAAQJoR80FwCDAQAOAAEJZRngAQBbAAAAAA==.Proyo:BAAALgADCgUJBQAAAA==.',
['På']='Påthor:BAABLgAECn8XAAIgAAcJFRo3IQDzAQAgAAcJFRo3IQDzAQAAAA==.',
Ra='Raikonnen:BAAALgAECgEJAQAAAA==.Rawtoor:BAACLgAFFH8VAAIWAAUJth1KDABxAQAWAAUJth1KDABxAQAuAAQKfxsAAhYACAn8IMwnAGUCABYACAn8IMwnAGUCAAAA.',
Re='Rebelsister:BAAALgADCgcJEAAAAA==.Refridgerate:BAAALgADCgUJBwAAAA==.',
Ri='Riddagain:BAAALgAECgYJDgAAAA==.Ridgemonk:BAABLgAECn8gAAMQAAgJsh5BCQAyAgAQAAgJsh5BCQAyAgAFAAQJQAGWYABMAAAAAA==.Riggsdk:BAAALgADCgcJBwABLgAFFAcJGAAXAP8jAA==.Riggse:BAAALgAECggJCgABLgAFFAcJGAAXAP8jAA==.Riggshunt:BAACLgAFFH8YAAQXAAcJ/yOKAAD9AQAXAAYJFSSKAAD9AQAYAAUJPyLTAACrAQAZAAEJAACyKABKAAAuAAQKfxoABBgACAmrJr4IAAcDABgABwmYJr4IAAcDABcACAlsJJEDAOwCABkAAQmCHGB9AE8AAAAA.',
Ro='Roadkill:BAABLgAECn8gAAIUAAgJnSM4BAALAwAUAAgJnSM4BAALAwAAAA==.Rolltoor:BAAALgAFFAIJAwAAAA==.Roonate:BAAALgADCgUJBQAAAA==.Rosemary:BAAALgAECgQJBAAAAA==.',
Ry='Ryujin:BAAALgAECgQJCQAAAA==.',
Sa='Saiko:BAAALgAFFAMJBAAAAA==.Sansa:BAACLgAFFH8QAAIXAAUJWiDfAwB8AQAXAAUJWiDfAwB8AQAuAAQKfyEAAhcACAlmJF0CABwDABcACAlmJF0CABwDAAAA.Saso:BAACLgAFFH8QAAIEAAUJFBsrIABoAQAEAAUJFBsrIABoAQAuAAQKfyoABAQACAnVI7YRAIwCAAQACAnVI7YRAIwCAA4AAwkDH0YMAA0BACEAAgnECLALAHcAAAAA.Sastroll:BAAALgAECgUJBQAAAA==.',
Sc='Scorn:BAAALgADCgcJCAAAAA==.Scroll:BAAALgAECggJEgAAAA==.',
Se='Seluvis:BAAALgAECgYJEQAAAA==.Sentai:BAAALgADCgcJBwAAAA==.Serapayne:BAAALgAECgcJAQAAAA==.',
Sh='Shadow:BAACLgAFFH8GAAIWAAUJ7A4ZIwAiAQAWAAUJ7A4ZIwAiAQAuAAQKfzoAAhYACAnBIncGAMICABYACAnBIncGAMICAAAA.Shandrilah:BAAALgADCgQJBAAAAA==.Shapeshift:BAAALgADCgUJBQABLgAECgIJAgACAAAAAA==.Shialebuff:BAABLgAECn8pAAQDAAgJ3yCdFwAfAgADAAgJ3yCdFwAfAgAGAAcJ3xnjDwDRAQABAAEJkwYNRgA0AAAAAA==.Shijin:BAAALgAECgQJBQAAAA==.Shortfuze:BAAALgAECgYJCwAAAA==.',
Si='Sindar:BAAALgADCgUJBQAAAA==.Sinfall:BAAALgAECgUJBwAAAA==.Siscomp:BAABLgAECn9pAAIHAAkJFx5fBQChAgAHAAkJFx5fBQChAgAAAA==.Sixth:BAAALgAECgYJEQAAAA==.Sizzle:BAAALgADCgMJAwAAAA==.',
Sk='Skateboard:BAAALgADCgEJAQAAAA==.Sky:BAACLgAFFH8WAAIBAAcJVA4iBAAgAgABAAcJVA4iBAAgAgAuAAQKfxQAAwEACAlxE40cALABAAEABwlZEo0cALABAAMABQnyD4RMAAYBAAAA.',
Sl='Sleck:BAAALgAECgYJDAAAAA==.',
Sn='Snappa:BAAALgADCgYJCwAAAA==.Sniped:BAAALgAFFAEJAQAAAA==.Snugglepuff:BAAALgAECggJDQAAAA==.',
So='Soapfidas:BAAALgADCggJCgAAAA==.Sonarius:BAABLgAECn8XAAMEAAgJ5R4iPACHAgAEAAgJ5R4iPACHAgAhAAEJshIQDwA8AAAAAA==.',
Su='Su:BAABLgAECn8yAAIFAAcJ4yVjBwDiAgAFAAcJ4yVjBwDiAgAAAA==.Sudno:BAAALgAECgQJCAAAAA==.Sundae:BAABLgAECn8mAAQDAAgJHSPIAgAMAwADAAgJHSPIAgAMAwABAAQJFBm9LQAwAQAGAAMJ5RYAAAAAAAAAAA==.Sunwukong:BAAALgAECgMJBAAAAA==.Supersinpe:BAAALgAECgIJAgAAAA==.',
Sv='Svendlefyre:BAAALgADCgcJDgABLgAECggJLQARAMIZAA==.Svholydrag:BAAALgADCgEJAQAAAA==.Svmishima:BAAALgAECgEJAQAAAA==.',
Sy='Sylvie:BAAALgAECggJEgAAAA==.',
['Sý']='Sýlvanas:BAAALgAECgQJDQAAAA==.',
Te='Tealç:BAABLgAECn8gAAIiAAcJphfwEQBFAQAiAAcJphfwEQBFAQABLgAFFAQJDAAiAOgXAA==.Tekk:BAAALgAECgEJAQAAAA==.Tekkys:BAAALgAECgEJAgAAAA==.Tertle:BAAALgADCgUJBQAAAA==.',
Ti='Tiafinia:BAAALgAECgEJAgAAAA==.Tiggerstripe:BAAALgADCgEJAQABLgAECggJJAAaAEoMAA==.Timur:BAAALgAECgEJAgAAAA==.Tinara:BAAALgADCgUJBQAAAA==.',
Tr='Trigger:BAAALgAECgIJAgAAAA==.',
Tu='Turlesblows:BAABLgAECn8dAAMHAAcJKSFdJAA0AgAHAAcJKSFdJAA0AgAiAAEJOxWYRAA7AAAAAA==.',
Tw='Twityy:BAAALgADCgEJAgAAAA==.Twofiveyd:BAAALgAECgkJCQABLgAFFAYJFAAVAGoYAA==.',
Ty='Tyladrhas:BAABLgAECn8qAAIdAAgJfh8XAgBsAgAdAAgJfh8XAgBsAgAAAA==.Tyrismaximus:BAAALgAECgMJAwAAAA==.',
Ul='Ulkina:BAAALgADCgYJCQAAAA==.',
Va='Vaelith:BAAALgAECgIJAgAAAA==.Valerine:BAABLgAECn8YAAIEAAcJlg1WZABJAQAEAAcJlg1WZABJAQAAAA==.Vanoran:BAAALgAECgMJBAAAAA==.Varang:BAAALgAECgIJAgAAAA==.Varina:BAAALgAECgcJEgAAAA==.',
Ve='Venki:BAAALgADCgcJDAAAAA==.',
Vo='Voidnova:BAABLgAFFH8GAAIEAAIJoxKIRQClAAAEAAIJoxKIRQClAAAAAA==.Voidphayze:BAAALgAECgUJDAABLgAECgkJHAAMAG8YAA==.',
Vu='Vulken:BAABLgAECn9iAAIYAAkJECWnAQA+AwAYAAkJECWnAQA+AwAAAA==.',
['Vê']='Vê:BAAALgAECgkJEQAAAA==.',
Wa='Wallace:BAAALgAECgcJDAAAAA==.Walterlight:BAAALgAECgYJDgAAAA==.Watto:BAAALgAFFAEJAQAAAA==.',
We='Wemongin:BAAALgADCgUJBQAAAA==.',
Wh='Whimsical:BAAALgAECgYJCwAAAA==.',
Wi='Winnìng:BAABLgAECn8eAAIjAAgJ1wrlFAD7AAAjAAgJ1wrlFAD7AAAAAA==.',
Wu='Wugong:BAAALgADCgEJAQAAAA==.',
['Wó']='Wórkwórk:BAACLgAFFH8FAAIHAAMJKhRpHQDHAAAHAAMJKhRpHQDHAAAuAAQKfxsAAwcACQk6GxM3AMsBAAcABwnRGRM3AMsBABUAAwnsGr8fAO8AAAAA.',
Zi='Zich:BAAALgADCgMJAwAAAA==.Zihon:BAAALgAECgQJEwAAAA==.',
Zo='Zodiiak:BAABLgAECn88AAIaAAgJJh3RBgDLAQAaAAgJJh3RBgDLAQAAAA==.',
Zu='Zuhh:BAAALgAECgEJAQABLgAECggJEAACAAAAAA==.Zupp:BAAALgAECggJEAAAAA==.',
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
