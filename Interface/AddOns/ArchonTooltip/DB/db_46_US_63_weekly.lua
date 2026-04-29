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

local lookup = {'Warlock-Affliction','Warlock-Demonology','Unknown-Unknown','Druid-Restoration','DeathKnight-Unholy','Shaman-Restoration','Monk-Brewmaster','Paladin-Holy','Shaman-Elemental','Shaman-Enhancement','Monk-Windwalker','Mage-Frost','Hunter-Survival','DemonHunter-Devourer','DemonHunter-Havoc','Paladin-Retribution','Hunter-BeastMastery','Evoker-Augmentation','Evoker-Devastation','Warrior-Protection','Warrior-Fury','Warrior-Arms','Druid-Balance','Warlock-Destruction','Evoker-Preservation','Priest-Discipline','Priest-Holy','Druid-Feral','Priest-Shadow','Hunter-Marksmanship','Paladin-Protection',}
local provider = {region='US',realm='Dawnbringer',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abdalhazred:BAACLgAFFH8FAAMBAAIJ6h74AADIAAABAAIJ6h74AADIAAACAAEJhB9dHwBgAAAuAAQKfyMAAwEACAnSJFIAAGYDAAEACAnSJFIAAGYDAAIAAQk9IypBAGgAAAAA.Abilus:BAAALgAECgMJBwAAAA==.Abolis:BAAALgADCgIJAwAAAA==.',
Ae='Aeldriel:BAAALgADCgcJCAAAAA==.',
Ak='Akoa:BAAALgAECgEJAQAAAA==.',
Al='Alarak:BAAALgAECgYJDAAAAA==.Alvierearn:BAAALgAECgcJEgAAAA==.',
Am='Amoradis:BAAALgADCgQJBwAAAA==.',
An='Anaeir:BAAALgADCgYJBgAAAA==.Angriff:BAAALgADCgQJBQAAAA==.Anisette:BAAALgAECgUJCAAAAA==.Anthria:BAAALgADCgcJEgAAAA==.',
Aq='Aqurala:BAAALgAECgYJDwAAAA==.',
Ar='Aradem:BAAALgADCgcJBwABLgAECgcJEgADAAAAAA==.Aravenn:BAAALgADCgYJBgABLgAECgcJEgADAAAAAA==.Arcis:BAAALgAECgYJDwAAAA==.Arealis:BAAALgADCgcJDAAAAA==.Argatem:BAAALgAECgQJBAABLgAECgcJFwAEADEYAA==.Arkangel:BAABLgAECn8WAAIFAAcJ8xaFDwCbAQAFAAcJ8xaFDwCbAQAAAA==.Arkharon:BAAALgADCgYJCQAAAA==.Arralyon:BAAALgADCgMJBgAAAA==.Artemesia:BAAALgAECgEJAQABLgAFFAQJDQAGAB8eAA==.',
As='Asakua:BAAALgAECgMJBgAAAA==.Asiya:BAAALgAECgEJAQAAAA==.Assandra:BAAALgADCgUJBQAAAA==.',
At='Athul:BAAALgADCgUJCgAAAA==.',
Au='Aurlyn:BAAALgADCgcJDwAAAA==.',
Av='Avatartele:BAAALgAECgIJAwAAAA==.Avatartouka:BAAALgAECgYJDAAAAA==.Avianthel:BAAALgADCgMJAgAAAA==.Avraria:BAAALgADCgEJAQAAAA==.Avyl:BAAALgAECgQJCAAAAA==.Avylastorica:BAAALgADCgYJBgABLgAECgQJCAADAAAAAA==.',
Aw='Awsomninja:BAABLgAECn8UAAIHAAcJGSFYBADcAQAHAAcJGSFYBADcAQAAAA==.',
Ax='Axxain:BAAALgADCgkJGgAAAA==.',
Az='Azaralle:BAAALgADCgEJAQAAAA==.Azeazal:BAAALgAECgUJCgAAAA==.Azlifan:BAAALgADCgQJBAAAAA==.',
Ba='Baddlandss:BAAALgAECgQJCAAAAA==.Bastais:BAAALgAECgEJAQAAAA==.Batozai:BAAALgADCgEJAQAAAA==.Baumstack:BAAALgADCgUJBQAAAA==.',
Bd='Bdibz:BAAALgADCgcJDAAAAA==.',
Be='Beautifulluv:BAAALgAECgYJDwAAAA==.Bekabeka:BAACLgAFFH8FAAIIAAIJqxvIBwC6AAAIAAIJqxvIBwC6AAAuAAQKfyQAAggACAmYI+QHAPACAAgACAmYI+QHAPACAAAA.Bera:BAAALgAECgQJDAABLgAECgcJBQADAAAAAA==.Beramage:BAAALgAECgEJAQAAAA==.',
Bi='Billybobjr:BAABLgAECn8aAAIGAAcJPSHGAwA/AgAGAAcJPSHGAwA/AgAAAA==.Bippitybop:BAAALgAECgEJAQAAAA==.',
Bo='Boamere:BAAALgAECgUJCQAAAA==.Botemedel:BAAALgADCgEJAQAAAA==.',
Br='Braided:BAAALgAECgIJAwAAAA==.Brakkar:BAAALgAECgQJDQAAAA==.Brandish:BAAALgADCgcJBwAAAA==.Breadstick:BAABLgAECn8WAAIEAAYJAyMVCADiAQAEAAYJAyMVCADiAQAAAA==.Brevik:BAAALgADCgMJAwAAAA==.Brutaal:BAAALgADCgcJCwAAAA==.Brynhild:BAAALgAFFAIJAwAAAA==.Brütaal:BAAALgAECgUJCQAAAA==.',
Bu='Bubsydogo:BAAALgAECgUJCAAAAA==.Buddytheelf:BAAALgAECgYJEwAAAA==.Bumpyflea:BAAALgADCgUJBQAAAA==.',
Ca='Cairnsilvers:BAAALgADCgEJAQAAAA==.Camus:BAAALgAECgUJDAAAAA==.Capped:BAAALgADCgMJAwAAAA==.',
Ce='Cebollin:BAAALgAECgIJAgAAAA==.Celaian:BAAALgAECgUJCQABLgAECgcJDwADAAAAAA==.Celamor:BAAALgAECgEJAgAAAA==.Celasmine:BAAALgADCgYJCAAAAA==.Celpanda:BAAALgAECgcJDwAAAA==.',
Ch='Charlamayne:BAAALgADCgcJBwAAAA==.Charybdia:BAAALgAECgUJCwAAAA==.Chidõri:BAABLgAECn8iAAMJAAgJZiRHBQBDAwAJAAgJZiRHBQBDAwAKAAIJzxbkJQB5AAAAAA==.Chudlock:BAAALgAECgYJDQAAAA==.Chunna:BAABLgAECn8aAAILAAcJfBwwBADDAQALAAcJfBwwBADDAQAAAA==.Chunni:BAAALgAECgYJDwAAAA==.',
Co='Coolerfrieza:BAAALgAECgEJAQAAAA==.',
Cp='Cpr:BAABLgAECn8XAAIIAAcJiCGuDwCXAgAIAAcJiCGuDwCXAgAAAA==.',
Cr='Crepic:BAAALgAECgQJBAAAAA==.Cruelkitty:BAAALgAECgMJAwAAAA==.',
Cu='Cudibandit:BAAALgADCgcJDwAAAA==.',
Cy='Cyralai:BAACLgAFFH8UAAIEAAUJSxI7BQCHAQAEAAUJSxI7BQCHAQAuAAQKfxcAAgQACAlJIPUQALACAAQACAlJIPUQALACAAAA.',
Da='Dabofdeath:BAAALgAECgIJAgAAAA==.Dalov:BAABLgAECn8WAAIIAAcJSSb1BwDvAgAIAAcJSSb1BwDvAgAAAA==.Dankley:BAAALgAECgUJBwAAAA==.Darkestnyte:BAAALgAECgYJBgAAAA==.Darkk:BAAALgAECgQJBQAAAA==.Darkomenz:BAAALgADCgUJBQAAAA==.Darkrhaenies:BAAALgADCgcJBwAAAA==.Darkwindx:BAAALgADCgQJBAAAAA==.Datezero:BAAALgADCgQJBAAAAA==.',
De='Deadhealer:BAAALgADCgMJAwAAAA==.Deafknighte:BAAALgAECgMJAwAAAA==.Deathboi:BAAALgAECgYJEgAAAA==.Deathburgur:BAAALgAECgQJBAAAAA==.Deathfromme:BAAALgAECgYJCgAAAA==.Deathstro:BAAALgAECgQJCAABLgAECgcJFgAFAPMWAA==.Decayed:BAAALgADCgYJBwAAAA==.Dentridios:BAAALgADCgIJAgAAAA==.Deson:BAAALgAECgcJEwAAAA==.Deviantart:BAAALgADCgIJAgAAAA==.',
Di='Diana:BAAALgAECgUJCQAAAA==.Diietriich:BAABLgAECn8ZAAIMAAYJXSQrDgDXAQAMAAYJXSQrDgDXAQAAAA==.Dilligaaf:BAAALgADCgMJAwAAAA==.',
Do='Docbeanz:BAAALgADCgMJAwAAAA==.Donkypunch:BAAALgADCgQJBAAAAA==.Dontjudgemê:BAAALgADCgIJAgAAAA==.Dorcina:BAAALgADCgcJEwAAAA==.',
Dr='Dracthyr:BAAALgADCgUJDQAAAA==.Draltina:BAAALgAECgYJDwAAAA==.',
Dy='Dylghoul:BAAALgADCgUJBQAAAA==.',
Ef='Efforex:BAAALgADCgQJBAAAAA==.',
El='Elactoplasm:BAAALgAECgMJAwAAAA==.Ellistrae:BAAALgADCgEJAQAAAA==.Ellysia:BAAALgADCgEJAQAAAA==.',
Em='Emmel:BAAALgADCgUJBQAAAA==.',
Eq='Equeslucis:BAAALgAECgcJBwAAAA==.',
Er='Erodrana:BAAALgAECgYJBwAAAA==.Eromir:BAAALgAECgUJBwAAAA==.Eryi:BAAALgAECgUJCQAAAA==.',
Et='Ethan:BAAALgAECgkJEQAAAA==.',
Ev='Evonari:BAAALgADCgIJAgAAAA==.',
Ex='Exoticfrost:BAAALgADCgIJAgAAAA==.',
['Eí']='Eísheth:BAAALgADCgUJBAAAAA==.',
Fa='Faegen:BAAALgADCgEJAQAAAA==.Falkønn:BAAALgAECgIJAgAAAA==.Fangytooth:BAABLgAECn8gAAINAAcJYyNiBQC2AgANAAcJYyNiBQC2AgAAAA==.Fashaun:BAAALgAECgIJAgAAAA==.Faze:BAAALgAECgQJCAAAAA==.',
Fe='Ferrus:BAACLgAFFH8PAAMOAAUJZSKmAwD9AQAOAAUJZSKmAwD9AQAPAAEJLxMvDQBRAAAuAAQKfxkAAw8ACAkHJtANAIYCAA4ABwnDI+ocAKQCAA8ABwncJNANAIYCAAAA.',
Fr='Frostyblast:BAAALgADCgUJBgAAAA==.',
Fu='Fupacabra:BAAALgADCgEJAQAAAA==.Furiosity:BAAALgADCgIJAgAAAA==.Fuzzybear:BAAALgADCgcJBwABLgAECgcJIAANAGMjAA==.',
Ga='Gabomonk:BAAALgAECgMJBwABLgAECgcJCQADAAAAAA==.Gamalia:BAAALgADCgUJBQAAAA==.Garudekhan:BAAALgADCgUJBQAAAA==.',
Ge='Genreallee:BAAALgAECgMJBQAAAA==.Gernab:BAAALgADCgYJBgAAAA==.',
Gh='Ghost:BAAALgAECgYJDQAAAA==.',
Gi='Gianna:BAAALgAECgUJBgAAAA==.Gizzar:BAAALgADCgQJBAAAAA==.',
Gl='Glau:BAAALgADCgcJBwABLgAECgcJEAADAAAAAA==.Glimpsed:BAAALgAECgcJBAABLgAECgcJBQADAAAAAA==.Gloçk:BAAALgAECgMJBQABLgAECgYJCgADAAAAAA==.',
Go='Goofy:BAABLgAECn8eAAIQAAcJXCHGJACUAgAQAAcJXCHGJACUAgAAAA==.Gorrik:BAAALgADCgUJBQAAAA==.',
Gr='Greyfeather:BAAALgADCgEJAgAAAA==.Grimeace:BAAALgADCgQJBAAAAA==.',
Gu='Gunduin:BAABLgAECn8VAAIRAAcJpx8YHgBRAgARAAcJpx8YHgBRAgAAAA==.',
Gw='Gweb:BAAALgAECgIJAgAAAA==.',
Gy='Gyda:BAAALgAECgQJCgAAAA==.Gyuyuki:BAAALgAECgYJEQAAAA==.',
Ha='Hakuanah:BAAALgADCgEJAQAAAA==.Halvorak:BAAALgADCgcJCgAAAA==.Harryp:BAABLgAECn8aAAMSAAgJ6g1sBgCSAQASAAgJ6g1sBgCSAQATAAYJLwmPIQAfAQAAAA==.Hast:BAAALgADCgIJAgAAAA==.',
He='Hellsbow:BAAALgAECgYJDgAAAA==.Hermin:BAAALgADCgQJBQAAAA==.',
Ho='Holyhellz:BAAALgADCgEJAQAAAA==.Honeyboo:BAAALgADCgcJBwABLgAECgcJHwAEALogAA==.Hots:BAAALgADCgcJBwAAAA==.',
Hr='Hraesvelgr:BAAALgADCggJBwAAAA==.',
Hu='Huntavious:BAAALgAECggJEgAAAA==.',
['Hë']='Hëllen:BAAALgAECgYJEgAAAA==.',
Ia='Iamshinigamy:BAAALgAECgIJAgABLgAECgcJFwAMAPMaAA==.',
Il='Illidupe:BAAALgADCgMJAwAAAA==.',
Iv='Ivey:BAABLgAECn8XAAIEAAcJMRgMMADrAQAEAAcJMRgMMADrAQAAAA==.',
Iz='Izes:BAAALgADCgEJAQAAAA==.',
Ja='Jaagganug:BAAALgADCgMJAwAAAA==.Jacenne:BAAALgAECgMJBAAAAA==.',
Je='Jellytime:BAAALgAECgEJAQAAAA==.',
Jo='Josephyn:BAAALgADCgkJFAABLgAFFAQJDQAGAB8eAA==.',
Ju='Jugernaut:BAAALgADCgMJBAAAAA==.Jumpmann:BAAALgAECgMJAwAAAA==.Justdesserts:BAAALgAECgEJAQAAAA==.Justix:BAAALgADCggJCAAAAA==.',
Ka='Kadaffy:BAAALgADCgEJAQAAAA==.Kakusu:BAAALgAECgYJEQAAAA==.Kakuta:BAAALgAECgQJBAAAAA==.Kalru:BAAALgADCgQJCgAAAA==.Kargar:BAAALgADCgMJAwAAAA==.Katharsis:BAABLgAECn8aAAIQAAgJvBM/EACjAQAQAAgJvBM/EACjAQAAAA==.',
Ke='Keba:BAAALgADCggJDwABLgAFFAIJBQAIAKsbAA==.',
Kh='Khalidisi:BAAALgAECgcJDQAAAA==.Khalizar:BAAALgADCgYJBgAAAA==.Khenja:BAAALgAECgEJAQAAAA==.Khál:BAAALgADCgYJBgAAAA==.',
Ki='Killerelf:BAAALgADCgkJFgAAAA==.',
Kk='Kkiilleerr:BAAALgADCgcJBwAAAA==.',
Ko='Kobbaltcilar:BAAALgADCggJCAAAAA==.Korbo:BAAALgAECgUJCwAAAA==.Korbulo:BAAALgAECgQJBQAAAA==.Korlothel:BAAALgAECgcJEgAAAA==.',
Kr='Krumpus:BAAALgAECgYJEAAAAA==.',
Ku='Kungfuuy:BAAALgAECgUJDAAAAA==.Kurtevade:BAAALgADCgYJCAAAAA==.',
Ky='Kynsong:BAAALgAECgUJCQAAAA==.',
['Kà']='Kàlbrews:BAABLgAECn8jAAIHAAgJNyZcAAD7AgAHAAgJNyZcAAD7AgAAAA==.',
La='Lainiee:BAAALgADCgEJAQAAAA==.Lavismad:BAEBLgAECn8fAAQUAAcJ0iP8AQARAgAVAAYJACPUIQBGAgAUAAcJZB/8AQARAgAWAAEJRiVvMgBpAAAAAA==.Lavoc:BAEALgADCgcJBwABLgAECgcJHwAUANIjAA==.',
Le='Leshah:BAAALgADCgcJEAAAAA==.',
Li='Lichkingdied:BAAALgADCgUJBQAAAA==.Lilypetal:BAAALgAECgQJBwAAAA==.Littlebucket:BAAALgADCgEJAQAAAA==.',
Lo='Lockdpain:BAAALgAECgYJEgAAAQ==.Logov:BAAALgAECgQJBwAAAA==.Loraine:BAAALgADCgEJAQAAAA==.Loìsbethe:BAAALgAECgQJBAAAAA==.',
Lu='Luciferra:BAAALgAECgIJAwABLgAFFAQJDQAGAB8eAA==.Lukey:BAAALgAECgMJAwAAAA==.Lunartemis:BAAALgAECgQJBwABLgAECgYJDgADAAAAAA==.',
['Lû']='Lûnafreya:BAAALgAECgUJCgAAAA==.',
Ma='Maelera:BAAALgADCgkJDAAAAA==.Magentas:BAAALgADCgIJAgAAAA==.Magickul:BAAALgADCggJCAAAAA==.Mahlah:BAAALgAECgQJBAAAAA==.Maletsy:BAAALgAECgEJAQABLgAECgcJFQARAKcfAA==.Maliboo:BAABLgAECn8fAAMEAAcJuiCBAwBnAgAEAAcJuiCBAwBnAgAXAAEJpwJijwAcAAAAAA==.Maxamus:BAAALgAECgQJCwAAAA==.',
Mc='Mcflurry:BAAALgAECgMJAwAAAA==.',
Me='Medarisa:BAAALgADCgkJCgAAAA==.Medavia:BAAALgADCgIJAgAAAA==.Melisandr:BAAALgADCggJCAAAAA==.Merkenier:BAAALgAECgYJEwAAAA==.',
Mi='Midnitehunt:BAAALgADCgUJBQAAAA==.Miragia:BAAALgAECgMJAwAAAA==.Missmayhem:BAAALgAECgEJAQAAAA==.Missmayhemm:BAAALgADCgMJAwAAAA==.',
Mo='Modifiedmix:BAAALgAECgQJBQAAAA==.Modsabadtank:BAAALgADCgMJBAABLgAECgQJBQADAAAAAA==.Mokomohama:BAAALgAECgcJBwAAAA==.Monatazumaa:BAAALgAECgEJAgAAAA==.Moonbloom:BAAALgAECgQJBAABLgAFFAQJDQAGAB8eAA==.Mordicant:BAAALgADCgEJAQAAAA==.Morella:BAABLgAECn81AAIYAAcJmQ4JGQCDAQAYAAcJmQ4JGQCDAQAAAA==.',
Mu='Mucduck:BAAALgADCgEJAQAAAA==.Mustakrakish:BAAALgAECgEJAQAAAA==.',
My='Mym:BAAALgADCgcJBAAAAA==.Mystics:BAAALgADCgYJCwAAAA==.Mythrunduil:BAAALgADCgEJAQAAAA==.',
['Mé']='Médb:BAAALgAECgUJDwAAAA==.',
Ne='Neptune:BAACLgAFFH8NAAIGAAQJHx5MBgBiAQAGAAQJHx5MBgBiAQAuAAQKfxsAAwYACQn0HhcHAAIDAAYACQn0HhcHAAIDAAkABwkkDs40AIQBAAAA.Nerfdks:BAAALgAECgEJAQAAAA==.Nerfpaladins:BAAALgAECgYJEQAAAA==.Neruess:BAAALgADCgUJBQAAAA==.',
Ni='Nightbird:BAAALgAECgcJEAAAAA==.Ninediewatt:BAAALgADCgcJEAAAAA==.Nivella:BAAALgAECgYJCgAAAA==.Niçki:BAAALgADCgMJAwAAAA==.',
No='Notlockz:BAAALgADCgIJAgAAAA==.Novah:BAAALgADCgQJBQAAAA==.',
Nu='Nuah:BAAALgADCgYJDQAAAA==.',
Ob='Obayi:BAAALgADCgIJAgAAAA==.',
Og='Ogmadmonk:BAABLgAECn8gAAIPAAgJlR6lCwCmAgAPAAgJlR6lCwCmAgAAAA==.',
Ok='Oktobra:BAAALgAECgQJCAAAAA==.',
On='Onos:BAAALgAECgQJBAAAAA==.',
Or='Orioan:BAAALgADCgIJAgAAAA==.',
Os='Osenya:BAAALgADCgcJBwABLgAECgcJHwAXAHQiAA==.Osun:BAAALgADCgUJBQAAAA==.',
Ou='Ouroboro:BAAALgADCgUJBQAAAA==.',
Ow='Owlbat:BAAALgAECgEJAQAAAA==.',
Pa='Padremort:BAAALgADCgYJBgAAAA==.Palantyr:BAABLgAECn9GAAIJAAgJWxqWGgA+AgAJAAgJWxqWGgA+AgAAAA==.Paly:BAAALgAECgEJAQAAAA==.Para:BAAALgADCgUJBwAAAA==.Patrician:BAAALgAECgUJCwAAAA==.',
Pe='Peehat:BAAALgADCgcJCQAAAA==.Penutbutter:BAAALgADCggJCAAAAA==.Pepegasus:BAAALgADCgcJBwAAAA==.',
Ph='Phobos:BAAALgADCgQJCAAAAA==.Phyloren:BAAALgADCgUJBgAAAA==.',
Pi='Pigsticker:BAAALgAECgQJBQAAAA==.Pixyfire:BAAALgAECgQJBAABLgAECgcJHwAIAC8jAA==.',
Po='Pokingharder:BAAALgADCgYJBgAAAA==.',
Pu='Pulcherrimus:BAAALgAECgEJAQAAAA==.Purgeem:BAAALgADCgUJBQAAAA==.',
Pw='Pwiest:BAAALgADCgcJEAAAAA==.',
Qu='Quetzalcoatl:BAABLgAECn8WAAIZAAYJ9RwcAwDGAQAZAAYJ9RwcAwDGAQAAAA==.',
Ra='Raddish:BAAALgAECgQJCAAAAA==.Rahjlynn:BAAALgADCgcJBwAAAA==.Raiinn:BAAALgADCgUJBQAAAA==.Raylee:BAABLgAECn8fAAMYAAcJdyA+AQC/AQAYAAcJih8+AQC/AQACAAQJjhoFlAAwAQAAAA==.Razuki:BAABLgAECn8fAAMIAAcJLyNpAQC0AgAIAAcJLyNpAQC0AgAQAAEJ7wuYRAEyAAAAAA==.',
Re='Renarina:BAAALgADCgkJEgAAAA==.',
Rh='Rhaenies:BAAALgAECgYJEAAAAA==.Rhovanion:BAAALgAECgQJBwAAAA==.Rhuac:BAAALgAECgYJEQAAAA==.',
Ro='Rorschach:BAAALgAECgMJBAAAAA==.Rosefist:BAEALgADCgcJCAABLgAFFAQJDAAaAIwVAA==.Rosemourne:BAEALgAECgIJAgABLgAFFAQJDAAaAIwVAA==.Roseykat:BAAALgAECgUJCAAAAA==.Roshwyn:BAAALgAECgMJBgAAAA==.',
Ru='Ruckus:BAABLgAECn8bAAIQAAgJYRYUPwApAgAQAAgJYRYUPwApAgAAAA==.',
Sa='Saberwar:BAAALgAECgEJAQABLgAECgIJAgADAAAAAA==.Saintfury:BAAALgAECgQJBQAAAA==.Saintsfear:BAAALgAECgUJCwAAAA==.Saphalia:BAAALgADCgMJAwAAAA==.Saradomin:BAAALgADCgUJBAAAAA==.Sareenastar:BAABLgAECn8YAAIbAAcJoyXxBAACAwAbAAcJoyXxBAACAwAAAA==.Sasae:BAAALgAECgYJDwAAAA==.',
Sc='Scorias:BAAALgADCgIJAQAAAA==.',
Se='Selisztraza:BAAALgADCgEJAQAAAA==.Sephiróth:BAAALgADCgUJCAAAAA==.Sereni:BAAALgADCgQJBAAAAA==.Serenity:BAAALgAECgIJAgAAAA==.Serenitynow:BAAALgADCgYJBgAAAA==.Sewald:BAAALgAECgIJAgAAAA==.',
Sh='Shadowzbane:BAAALgAECgIJAgAAAA==.Shahasha:BAAALgADCgEJAQAAAA==.Shalen:BAAALgAECgcJEgAAAA==.Sharker:BAAALgADCgYJBgAAAA==.Sharpie:BAAALgADCgcJCgAAAA==.Sheer:BAAALgAECgUJBgAAAA==.Sheraa:BAAALgAECgQJBAAAAA==.Shiftystrike:BAABLgAECn8UAAIcAAYJtR/vCgAVAgAcAAYJtR/vCgAVAgAAAA==.Shrunkador:BAABLgAECn8ZAAIJAAgJlBoNFwBfAgAJAAgJlBoNFwBfAgAAAA==.',
Si='Silk:BAAALgAECgYJCAAAAA==.Silmarkthree:BAABLgAECn8fAAIMAAcJDBfaHQBhAQAMAAcJDBfaHQBhAQAAAA==.Sinbåd:BAAALgAECgUJBQAAAA==.',
Sl='Sleety:BAAALgAECgEJAQAAAA==.Slipknoth:BAACLgAFFH8JAAMdAAQJZwm3CAA3AQAdAAQJZwm3CAA3AQAaAAQJPwvABAAwAQAuAAQKfxcABB0ABwlmIIEbAAECAB0ABgnjIoEbAAECABsABwntF/cgANsBABoAAwltEbtAAKsAAAAA.',
Sn='Snekhain:BAAALgADCgMJAwAAAA==.Snuffaluffa:BAAALgAECgMJAwAAAA==.',
So='Somatra:BAAALgADCgkJCQAAAA==.Sorean:BAABLgAECn8mAAQRAAgJciBYIQA9AgARAAcJVBtYIQA9AgANAAYJRhxpAwDJAQAeAAcJUBqfMACuAQAAAA==.',
Sp='Spamtp:BAAALgAECgcJBQAAAA==.Specialmove:BAAALgAECgcJBgAAAA==.Spookydookie:BAAALgADCgkJCgAAAA==.',
St='Stifs:BAABLgAECn8aAAIfAAgJMQ3/FgBlAQAfAAgJMQ3/FgBlAQAAAA==.Stinkinglily:BAAALgAECgEJAgAAAA==.Strunrage:BAEALgADCgkJDgABLgAECgcJJwAQAHIkAA==.Stïtches:BAAALgAECgUJCwAAAA==.Stÿx:BAAALgAECgUJCwAAAA==.',
Su='Sugarbomb:BAAALgADCgMJBAAAAA==.',
Sy='Sykotyk:BAAALgAECgUJCQAAAA==.Synchestra:BAAALgADCgcJCgAAAA==.',
Ta='Tadagain:BAAALgAECgQJEAAAAA==.Tankybears:BAABLgAECn8YAAMXAAcJcBeuBgCXAQAXAAcJcBeuBgCXAQAEAAQJJxw/WwBAAQAAAA==.Tarmalok:BAAALgADCgkJCQAAAA==.Tazera:BAAALgADCgYJBgAAAA==.',
Te='Telekinesis:BAAALgAECgYJDAAAAA==.Tenbinza:BAAALgAECgEJAQAAAA==.Teos:BAABLgAECn8dAAIKAAgJkRHuAwB9AQAKAAgJkRHuAwB9AQAAAA==.',
Th='Thainé:BAAALgAECgMJBgAAAA==.Thaldrassian:BAAALgADCgQJBAAAAA==.Thehatred:BAAALgADCgYJBgAAAA==.Thromar:BAABLgAECn8VAAIMAAcJiBW9gADPAQAMAAcJiBW9gADPAQAAAA==.Thugz:BAAALgAECgUJDQAAAA==.Thunderlily:BAAALgAECgYJDQAAAA==.Thünder:BAAALgADCgcJBwAAAA==.',
Ti='Tinderbeef:BAAALgADCgcJCAAAAA==.Tinyround:BAAALgAECgEJAQAAAA==.Tirra:BAAALgAECgYJBwAAAA==.',
To='Toranth:BAABLgAECn8WAAIIAAcJBA8dCwCOAQAIAAcJBA8dCwCOAQAAAA==.Torq:BAABLgAECn8WAAIMAAYJ9xmXJAA+AQAMAAYJ9xmXJAA+AQABLgAECgcJFwAIAIghAA==.Torqumada:BAAALgAECgQJBQAAAA==.Toxian:BAAALgAECgUJEgAAAA==.Toxicelitist:BAAALgAECgYJEQAAAA==.',
Tr='Treedemon:BAABLgAECn8dAAIOAAcJCSWWBABFAgAOAAcJCSWWBABFAgAAAA==.Trymw:BAAALgADCgIJAgAAAA==.',
Ty='Tybearon:BAAALgADCgEJAQAAAA==.Tyreid:BAAALgADCgMJAwAAAA==.Tyrelitha:BAAALgADCgYJBwAAAA==.',
Ud='Udderchoad:BAAALgADCgEJAQAAAA==.',
Uh='Uhura:BAAALgADCgEJAQAAAA==.',
Ul='Ulfrir:BAABLgAECn8cAAMRAAgJVxtwFQCMAgARAAgJVxtwFQCMAgAeAAMJMQoYbwCCAAAAAA==.Ultradukes:BAAALgADCgYJDAAAAA==.',
Un='Unatural:BAAALgAECgUJBQAAAA==.Unleashed:BAAALgAECgIJAgAAAA==.',
Va='Valarea:BAAALgADCgEJAQAAAA==.Valock:BAAALgADCgkJCQAAAA==.Valris:BAAALgAECgMJBAAAAA==.Vandham:BAAALgADCgEJAQAAAA==.Vanshifty:BAABLgAECn8eAAIEAAgJnCJeAgCbAgAEAAgJnCJeAgCbAgAAAA==.',
Ve='Veilf:BAAALgADCgYJDAAAAA==.Velrus:BAAALgAECgYJDAAAAA==.Venombite:BAAALgADCgMJAwAAAA==.',
Vi='Viktorax:BAAALgAECgYJBgAAAA==.Virtueozo:BAABLgAECn8aAAIZAAgJEBfFDwA+AgAZAAgJEBfFDwA+AgAAAA==.',
Vo='Volam:BAAALgAECgQJBAAAAA==.',
Wa='Waffle:BAAALgAECgQJBwABLgAECggJFAARAD8OAA==.Wangwen:BAAALgADCgIJAgAAAA==.Wargue:BAAALgAECgYJDAAAAA==.',
We='Weebsz:BAAALgADCgQJBAAAAA==.Wetkith:BAAALgADCgQJBAAAAA==.',
Wi='Windrider:BAAALgADCgIJAgAAAA==.Windwraith:BAAALgADCgUJCwAAAA==.Wizzard:BAAALgAECgYJBgAAAQ==.',
Xa='Xaiyara:BAAALgADCgUJBQAAAA==.Xandaka:BAAALgADCgQJBAAAAA==.',
Xe='Xephir:BAAALgAECgIJAQAAAA==.',
Xi='Xidied:BAABLgAECn8fAAIHAAcJOR5ZBQC6AQAHAAcJOR5ZBQC6AQAAAA==.Xilon:BAAALgADCgcJBwABLgAECgcJHwAXAHQiAA==.Xilra:BAABLgAECn8fAAIXAAcJdCJuBADbAQAXAAcJdCJuBADbAQAAAA==.Xilzen:BAAALgAECgUJCwABLgAECgcJHwAXAHQiAA==.Xinia:BAAALgADCgEJAQAAAA==.',
Ye='Yew:BAAALgADCgMJAwAAAA==.',
Yi='Yikers:BAABLgAECn8YAAIIAAgJOBqfFgBcAgAIAAgJOBqfFgBcAgAAAA==.',
Yr='Yridai:BAAALgAECgYJCAAAAA==.',
Za='Zarsher:BAAALgADCgIJAgAAAA==.',
Ze='Zeldy:BAAALgAECgYJDwAAAA==.Zenthareal:BAAALgAECgYJDwAAAA==.Zeuc:BAAALgADCgMJAwAAAA==.Zeuus:BAAALgADCgMJBAAAAA==.',
Zh='Zhirl:BAAALgAECgcJEQAAAA==.Zhulgarosh:BAAALgADCgUJBQAAAA==.',
Zm='Zmaster:BAAALgAECgQJBQABLgAECgYJCQADAAAAAA==.',
Zo='Zobeast:BAAALgADCgQJBAAAAA==.',
Zr='Zret:BAAALgAECgYJCQAAAA==.',
['Åp']='Åpex:BAAALgADCgMJAwAAAA==.',
['Çl']='Çloudz:BAAALgADCgMJAwAAAA==.',
['Ða']='Ðark:BAABLgAECn8lAAIRAAgJmRwGFQCPAgARAAgJmRwGFQCPAgAAAA==.',
['Ðr']='Ðr:BAABLgAECn8ZAAMGAAcJThr9IgANAgAGAAcJThr9IgANAgAJAAQJLxgLEgDyAAAAAA==.',
['ßl']='ßlack:BAAALgADCgEJAQAAAA==.',
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
