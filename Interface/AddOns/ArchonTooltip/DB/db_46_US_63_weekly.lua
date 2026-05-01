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

local lookup = {'Warlock-Affliction','Warlock-Demonology','Unknown-Unknown','Mage-Frost','Hunter-BeastMastery','Paladin-Protection','Druid-Restoration','DeathKnight-Unholy','Shaman-Restoration','Monk-Brewmaster','Priest-Holy','Priest-Shadow','Priest-Discipline','Paladin-Holy','Warlock-Destruction','Shaman-Elemental','Shaman-Enhancement','Monk-Windwalker','Paladin-Retribution','Warrior-Arms','Warrior-Fury','Hunter-Survival','DemonHunter-Devourer','DemonHunter-Havoc','Evoker-Augmentation','Evoker-Devastation','Hunter-Marksmanship','Warrior-Protection','Druid-Balance','Mage-Fire','Evoker-Preservation','Druid-Feral','Mage-Arcane',}
local provider = {region='US',realm='Dawnbringer',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abdalhazred:BAACLgAFFH8IAAMBAAMJtyJ4AAA0AQABAAMJtyJ4AAA0AQACAAEJhB/kVQBfAAAuAAQKfzAAAwEACQlTJFIAAGYDAAEACAloJVIAAGYDAAIAAwnOHdhMAAkBAAAA.Abilus:BAAALgAECgMJCQAAAA==.Abolis:BAAALgAECgEJAQAAAA==.',
Ae='Aeldriel:BAAALgADCgcJCAAAAA==.',
Ag='Aggar:BAAALgADCgUJBQABLgAECgYJDwADAAAAAA==.',
Ak='Akoa:BAAALgAECgEJAQAAAA==.',
Al='Alarak:BAAALgAECgcJEwAAAA==.Alvierearn:BAABLgAECn8WAAIEAAgJsRHTOgB+AQAEAAgJsRHTOgB+AQAAAA==.',
Am='Amoradis:BAAALgADCgUJCgAAAA==.',
An='Anaeir:BAAALgADCgYJBgAAAA==.Angriff:BAAALgADCgQJBQAAAA==.Anisette:BAAALgAECgYJDwAAAA==.Anthria:BAAALgADCgcJEgAAAA==.',
Aq='Aqurala:BAABLgAECn8XAAIFAAgJtRs3DwAeAgAFAAgJtRs3DwAeAgAAAA==.',
Ar='Aradem:BAAALgADCgcJBwABLgAECggJFQAGAPIFAA==.Aravenn:BAAALgADCgYJBgABLgAECggJFQAGAPIFAA==.Arcis:BAAALgAECgYJEQAAAA==.Arealis:BAAALgADCgcJDAAAAA==.Argatem:BAAALgAECgQJBAABLgAECggJHwAHAAAcAA==.Arkangel:BAABLgAECn8XAAIIAAgJYxbIJACuAQAIAAgJYxbIJACuAQAAAA==.Arkharon:BAAALgADCgYJCQAAAA==.Arralyon:BAAALgADCgMJBgAAAA==.Artemesia:BAAALgAECgEJAQABLgAFFAUJEgAJAE0aAA==.Arthäs:BAAALgAECgQJBAAAAA==.',
As='Asakua:BAAALgAECgMJBgAAAA==.Asiya:BAAALgAECgQJBQAAAA==.Assandra:BAAALgADCgUJBQAAAA==.',
At='Athul:BAAALgADCgUJCgAAAA==.',
Au='Aurlyn:BAAALgADCgcJDwAAAA==.',
Av='Avatartele:BAAALgAECgIJAwAAAA==.Avatartouka:BAABLgAECn8UAAIJAAgJPSHIBQCUAgAJAAgJPSHIBQCUAgAAAA==.Avianthel:BAAALgADCgMJAgAAAA==.Avraria:BAAALgADCgEJAQAAAA==.Avyl:BAAALgAECgUJCgAAAA==.Avylastorica:BAAALgADCgYJBgABLgAECgUJCgADAAAAAA==.',
Aw='Awsomninja:BAABLgAECn8dAAIKAAgJXyJYAwCTAgAKAAgJXyJYAwCTAgAAAA==.',
Ax='Axxain:BAAALgADCgkJGgAAAA==.',
Az='Azaralle:BAAALgADCgEJAQAAAA==.Azeazal:BAAALgAECgUJCgAAAA==.Azlifan:BAAALgADCgQJBAAAAA==.',
Ba='Baddlandss:BAAALgAECgQJCAAAAA==.Bastais:BAAALgAECgEJAQAAAA==.Batozai:BAAALgADCgEJAQAAAA==.Baumstack:BAAALgADCgUJBQAAAA==.',
Bd='Bdibz:BAAALgADCgcJDAAAAA==.',
Be='Beautifulluv:BAABLgAECn8XAAQLAAgJRSFTAgDnAgALAAgJRSFTAgDnAgAMAAMJEgxUTACmAAANAAEJkAzJUwA6AAAAAA==.Bekabeka:BAACLgAFFH8IAAIOAAMJKSIvDAAyAQAOAAMJKSIvDAAyAQAuAAQKfzEAAw4ACQk8JLoAAGEDAA4ACQk8JLoAAGEDAAYAAgkAAqotABsAAAAA.Bera:BAAALgAECgQJDAABLgAECgcJBwADAAAAAA==.Beramage:BAAALgAECgEJAQAAAA==.',
Bi='Billybobjr:BAABLgAECn8kAAIJAAcJnyS8AwDNAgAJAAcJnyS8AwDNAgAAAA==.Bippitybop:BAAALgAECgEJAQAAAA==.',
Bl='Blackbart:BAAALgADCgEJAQAAAA==.',
Bo='Boamere:BAAALgAECgYJDwAAAA==.Botemedel:BAAALgADCgEJAQAAAA==.',
Br='Braided:BAAALgAECgIJAwAAAA==.Brakkar:BAAALgAECgYJEwAAAA==.Brandish:BAAALgADCgcJBwAAAA==.Breadstick:BAABLgAECn8dAAIHAAYJCyQmCgBoAgAHAAYJCyQmCgBoAgAAAA==.Brevik:BAAALgADCgMJAwAAAA==.Brutaal:BAAALgADCgcJCwAAAA==.Brynhild:BAAALgAFFAIJAwAAAA==.Brütaal:BAAALgAECgYJDwAAAA==.',
Bu='Bubsydogo:BAAALgAECgYJCQAAAA==.Buddytheelf:BAABLgAECn8VAAMCAAYJAB8pPwA1AQACAAQJCx4pPwA1AQAPAAIJ0iJLFwBmAAAAAA==.Bumpyflea:BAAALgADCgUJBQAAAA==.',
Ca='Cairnsilvers:BAAALgADCgEJAQAAAA==.Camus:BAAALgAECgYJEwAAAA==.Capped:BAAALgADCgMJAwAAAA==.',
Ce='Cebollin:BAAALgAECgIJAgAAAA==.Celaian:BAAALgAECgUJCQABLgAECggJEAADAAAAAA==.Celamor:BAAALgAECgQJBwAAAA==.Celasmine:BAAALgADCgYJCAAAAA==.Celpanda:BAAALgAECggJEAAAAA==.',
Ch='Charlamayne:BAAALgADCgcJBwAAAA==.Charybdia:BAAALgAECgYJDgAAAA==.Chidõri:BAACLgAFFH8GAAIQAAMJSBjTEQDwAAAQAAMJSBjTEQDwAAAuAAQKfyYAAxAACQnvIksFAEMDABAACQnvIksFAEMDABEAAgnPFuIlAHkAAAAA.Chudlock:BAAALgAECgYJDgAAAA==.Chunna:BAABLgAECn8cAAISAAgJ8B14BQBCAgASAAgJ8B14BQBCAgAAAA==.Chunni:BAABLgAECn8XAAISAAgJEQf5HwDnAAASAAgJEQf5HwDnAAAAAA==.',
Co='Coolerfrieza:BAAALgAECgEJAQAAAA==.',
Cp='Cpr:BAABLgAECn8XAAIOAAcJiCGrDwCXAgAOAAcJiCGrDwCXAgAAAA==.',
Cr='Crepic:BAAALgAECgQJBAAAAA==.Cruelkitty:BAAALgAECgMJBwAAAA==.',
Cu='Cudibandit:BAAALgADCgcJDwAAAA==.',
Cy='Cyralai:BAACLgAFFH8ZAAIHAAYJABPPBAC8AQAHAAYJABPPBAC8AQAuAAQKfxkAAgcACQlOIfgQALACAAcACQlOIfgQALACAAAA.',
Da='Dabofdeath:BAAALgAECgIJAgAAAA==.Dalov:BAABLgAECn8YAAMOAAcJSSbyBwDvAgAOAAcJSSbyBwDvAgATAAEJiBqHsgBNAAAAAA==.Dankley:BAAALgAECgYJDgAAAA==.Darkestnyte:BAAALgAECgYJBgAAAA==.Darkk:BAAALgAECgQJCQAAAA==.Darkomenz:BAAALgADCgUJBQAAAA==.Darkrhaenies:BAAALgADCgcJBwAAAA==.Darkwindx:BAAALgADCggJCQABLgAECgUJBwADAAAAAA==.Datezero:BAAALgADCgQJBAAAAA==.',
De='Deadhealer:BAAALgADCgMJAwAAAA==.Deafknighte:BAAALgAECgMJAwAAAA==.Deathboi:BAABLgAECn8YAAIIAAYJpw0HSQAjAQAIAAYJpw0HSQAjAQAAAA==.Deathburgur:BAAALgAECgUJBgAAAA==.Deathfromme:BAAALgAECgYJCgAAAA==.Deathstro:BAAALgAECgQJCAABLgAECggJFwAIAGMWAA==.Decayed:BAAALgAECgIJAwAAAA==.Dentridios:BAAALgADCgIJAgAAAA==.Deson:BAABLgAECn8aAAMOAAcJuAwOQgBwAQAOAAcJuAwOQgBwAQATAAUJiAh1bwDQAAAAAA==.Deviantart:BAAALgADCgIJAgAAAA==.',
Di='Diana:BAAALgAECgYJDwAAAA==.Diietriich:BAABLgAECn8fAAIEAAYJ4iT7HAD+AQAEAAYJ4iT7HAD+AQAAAA==.Dilligaaf:BAAALgADCgMJAwAAAA==.',
Do='Docbeanz:BAAALgADCgMJAwAAAA==.Donkypunch:BAAALgADCgQJBAAAAA==.Dontjudgemê:BAAALgADCgIJAgAAAA==.Dopie:BAAALgADCgIJAgAAAA==.Dorcina:BAAALgADCgcJFwAAAA==.',
Dr='Dracthyr:BAAALgADCgUJDQAAAA==.Dragoondpain:BAAALgAECgQJBQAAAQ==.Draltina:BAABLgAECn8XAAMBAAgJNQmcBABOAQABAAgJNQmcBABOAQACAAEJywLbLwEhAAAAAA==.',
Du='Dunks:BAAALgADCgYJBgAAAA==.',
Dy='Dylghoul:BAAALgADCgUJBQAAAA==.',
['Dí']='Dírac:BAAALgADCgYJBgABLgAECgUJBgADAAAAAA==.',
Ef='Efforex:BAAALgADCgQJBAAAAA==.',
El='Elactoplasm:BAAALgAECgMJAwAAAA==.Ellistrae:BAAALgADCgEJAQAAAA==.Ellysia:BAAALgADCgEJAQAAAA==.',
Em='Emmel:BAAALgADCggJCwAAAA==.',
Eq='Equeslucis:BAAALgAECgcJBwAAAA==.',
Er='Erodrana:BAAALgAECgYJBwAAAA==.Eromir:BAAALgAECgUJCAAAAA==.Eryi:BAAALgAECgYJDwAAAA==.',
Et='Ethan:BAABLgAECn8YAAMUAAkJNxucCQBqAQAUAAYJVRScCQBqAQAVAAQJ6CIoIQAtAQAAAA==.',
Ev='Evonari:BAAALgADCgIJAgAAAA==.',
Ex='Exoticfrost:BAAALgADCgIJAgAAAA==.',
['Eí']='Eísheth:BAAALgADCgUJBAAAAA==.',
Fa='Faegen:BAAALgADCgMJAwAAAA==.Falkønn:BAAALgAECgIJAgAAAA==.Fangytooth:BAABLgAECn8jAAIWAAgJIyMIBQAtAgAWAAgJIyMIBQAtAgAAAA==.Fashaun:BAAALgAECgIJAgAAAA==.Faze:BAAALgAECgUJCgAAAA==.',
Fe='Ferrus:BAACLgAFFH8SAAMXAAYJMyKlAwD9AQAXAAYJMyKlAwD9AQAYAAEJLxMzDQBRAAAuAAQKfxsAAxgACQnrJdANAIYCABcACAn2I+ocAKQCABgABwncJNANAIYCAAAA.',
Ff='Ffleuderflam:BAAALgAECgYJBgAAAA==.',
Fr='Frose:BAAALgADCgEJAQAAAA==.Frostyblast:BAAALgADCgUJBgAAAA==.',
Fu='Fupacabra:BAAALgADCgEJAQAAAA==.Furiosity:BAAALgAECgEJAgAAAA==.Fuzzybear:BAAALgAECgEJAQABLgAECggJIwAWACMjAA==.',
Ga='Gabomonk:BAAALgAFFAEJAQAAAA==.Gamalia:BAAALgADCgUJBQAAAA==.Garudekhan:BAAALgADCgUJBQAAAA==.',
Ge='Genreallee:BAAALgAECgMJCAAAAA==.Gernab:BAAALgADCgYJBgAAAA==.',
Gh='Ghost:BAAALgAECggJDwAAAA==.',
Gi='Gianna:BAAALgAECgYJCQAAAA==.Gizzar:BAAALgADCgQJBAAAAA==.',
Gl='Glau:BAAALgADCgcJBwABLgAECgcJEAADAAAAAA==.Glimpsed:BAAALgAECgcJBwABLgAECgcJBwADAAAAAA==.Globgore:BAAALgADCgIJAgAAAA==.Gloçk:BAAALgAECgMJBwABLgAECgYJDwADAAAAAA==.',
Go='Goofy:BAABLgAECn8eAAITAAcJXCHCJACUAgATAAcJXCHCJACUAgAAAA==.Gorrik:BAAALgADCgUJBQAAAA==.',
Gr='Greyfeather:BAAALgADCgEJAgAAAA==.Grimeace:BAAALgADCgQJBAAAAA==.',
Gu='Gunduin:BAABLgAECn8VAAIFAAcJpx8WHgBRAgAFAAcJpx8WHgBRAgAAAA==.',
Gw='Gweb:BAAALgAECgIJAgAAAA==.',
Gy='Gyda:BAAALgAECgUJDAAAAA==.Gyuyuki:BAABLgAECn8eAAIQAAYJgwoXJgD0AAAQAAYJgwoXJgD0AAAAAA==.',
Ha='Hakuanah:BAAALgADCgEJAQAAAA==.Halvorak:BAAALgADCgcJCgAAAA==.Harryp:BAABLgAECn8iAAMZAAgJQxIZDQC3AQAZAAgJQxIZDQC3AQAaAAYJLwmXIQAfAQAAAA==.Hast:BAAALgAECgIJAgAAAA==.',
He='Hellsbow:BAAALgAECgYJDgAAAA==.Hermin:BAAALgADCgQJBQAAAA==.',
Ho='Holyhellz:BAAALgADCgEJAQAAAA==.Honeyboo:BAAALgADCgcJBwABLgAECggJIgAHAHMgAA==.Hots:BAAALgADCgcJBwAAAA==.Hotzz:BAAALgAECgEJAQAAAA==.',
Hr='Hraesvelgr:BAAALgADCggJBwAAAA==.',
Hu='Huntavious:BAABLgAECn8XAAQWAAgJWBsyCADiAQAWAAgJbRkyCADiAQAFAAUJGhvCXgBLAQAbAAEJyBOsigAwAAAAAA==.',
['Hë']='Hëllen:BAABLgAECn8WAAITAAYJqh93OwBYAQATAAYJqh93OwBYAQAAAA==.',
Ia='Iamshinigamy:BAAALgAECgIJAgABLgAECgcJFwAEAPMaAA==.',
Ii='Iichimaru:BAAALgAECgQJBAAAAA==.',
Il='Illidupe:BAAALgADCgMJAwAAAA==.',
Iv='Ivey:BAABLgAECn8fAAIHAAgJABxUCwBTAgAHAAgJABxUCwBTAgAAAA==.',
Iz='Izes:BAAALgADCgEJAQAAAA==.',
Ja='Jaagganug:BAAALgADCgMJAwAAAA==.Jacenne:BAAALgAECgUJCQAAAA==.',
Jd='Jdirty:BAAALgAECgQJCQAAAA==.',
Je='Jellytime:BAAALgAECgEJAQAAAA==.',
Jo='Josephyn:BAAALgAECgMJAwABLgAFFAUJEgAJAE0aAA==.',
Ju='Jugernaut:BAAALgAECgEJAQAAAA==.Jumpmann:BAAALgAECgMJAwAAAA==.Justdesserts:BAAALgAECgEJAQAAAA==.Justix:BAAALgADCggJDgAAAA==.',
Ka='Kadaffy:BAAALgADCgcJBwAAAA==.Kakusu:BAAALgAECgYJEQAAAA==.Kakuta:BAAALgAECgQJBAAAAA==.Kakutá:BAAALgADCgMJAwABLgAECgQJBAADAAAAAA==.Kalru:BAAALgADCgQJCgAAAA==.Kargar:BAAALgADCgMJAwAAAA==.Katharsis:BAABLgAECn8bAAITAAgJvBPYKACfAQATAAgJvBPYKACfAQAAAA==.',
Ke='Keba:BAAALgADCggJDwABLgAFFAMJCAAOACkiAA==.Keévs:BAAALgADCgQJBAAAAA==.',
Kh='Khalidisi:BAABLgAECn8YAAQOAAkJLxklDwDuAQAOAAkJLxklDwDuAQATAAQJVwSLggCnAAAGAAEJHh5mIQBWAAAAAA==.Khalizar:BAAALgAECgMJAwAAAA==.Khenja:BAAALgAECgEJAQAAAA==.Khál:BAAALgADCgYJBgAAAA==.',
Ki='Killerelf:BAAALgADCgkJFgAAAA==.',
Kk='Kkiilleerr:BAAALgAECgQJBAAAAA==.',
Ko='Kobbaltcilar:BAAALgAECgQJBAAAAA==.Korbo:BAAALgAECgYJEgAAAA==.Korbulo:BAAALgAECgYJCQAAAA==.Korlothel:BAABLgAECn8VAAIGAAgJ8gUGJgDYAAAGAAgJ8gUGJgDYAAAAAA==.',
Kr='Krumpus:BAAALgAECgcJEQAAAA==.',
Ku='Kungfuuy:BAAALgAECgYJEwAAAA==.Kurtevade:BAAALgADCgYJCAAAAA==.',
Ky='Kynsong:BAAALgAECgUJDAAAAA==.',
['Kà']='Kàlbrews:BAABLgAECn8sAAIKAAkJNyYbAACGAwAKAAkJNyYbAACGAwAAAA==.',
La='Lainiee:BAAALgADCgEJAQAAAA==.Lavismad:BAEBLgAECn8iAAQcAAgJTSPdBAAXAgAVAAcJiCLWIQBGAgAcAAcJZB/dBAAXAgAUAAEJRiV1MgBpAAAAAA==.Lavoc:BAEALgADCgcJBwABLgAECggJIgAcAE0jAA==.Lavv:BAEALgAECgEJAQABLgAECggJIgAcAE0jAA==.',
Le='Leshah:BAAALgADCgkJFQAAAA==.',
Li='Lichkingdied:BAAALgADCgUJBQAAAA==.Lilypetal:BAAALgAECgQJBwAAAA==.Littlebucket:BAAALgADCgEJAQAAAA==.',
Lo='Lockdpain:BAAALgAECgYJEwABLgAECgQJBQADAAAAAQ==.Logov:BAAALgAECgYJDgAAAA==.Loraine:BAAALgADCgEJAQAAAA==.Loìsbethe:BAAALgAECgQJBAAAAA==.',
Lu='Luciferra:BAAALgAECgIJAwABLgAFFAUJEgAJAE0aAA==.Lukey:BAAALgAECgMJAwAAAA==.Lunartemis:BAAALgAECgUJCAABLgAECgYJCgADAAAAAA==.',
['Lö']='Lörax:BAAALgADCgQJBQAAAA==.',
['Lû']='Lûnafreya:BAAALgAECggJEgAAAA==.',
Ma='Maelera:BAAALgADCgkJDAAAAA==.Magentas:BAAALgADCgIJAgAAAA==.Magickul:BAAALgADCggJCAAAAA==.Mahlah:BAAALgAECgQJBAAAAA==.Malaboo:BAAALgAECgEJAQABLgAECggJIgAHAHMgAA==.Maletsy:BAAALgAECgEJAQABLgAECgcJFQAFAKcfAA==.Maliboo:BAABLgAECn8iAAMHAAgJcyC6BgCqAgAHAAgJcyC6BgCqAgAdAAEJpwJwjwAcAAAAAA==.Maxamus:BAAALgAECgUJDQAAAA==.',
Mc='Mcflurry:BAAALgAECgMJBAAAAA==.',
Me='Medarisa:BAAALgAECgQJBQAAAA==.Medavia:BAAALgADCgUJBQAAAA==.Melisandr:BAAALgADCgkJEQAAAA==.Merkenier:BAABLgAECn8ZAAIdAAgJAgppGwAgAQAdAAgJAgppGwAgAQAAAA==.Merkur:BAAALgADCgkJCQABLgAECggJGQAdAAIKAA==.',
Mi='Midnitehunt:BAAALgADCgUJBQAAAA==.Miragia:BAAALgAECgUJBwAAAA==.Missmayhem:BAAALgAECgQJBwAAAA==.Missmayhemm:BAAALgADCgQJBgAAAA==.',
Mo='Modifiedmix:BAAALgAECgQJCwAAAA==.Modsabadtank:BAAALgADCgYJCgABLgAECgQJCwADAAAAAA==.Mokomohama:BAAALgAECgcJBwAAAA==.Monatazumaa:BAAALgAECgEJAgAAAA==.Moonbloom:BAAALgAECgQJBAABLgAFFAUJEgAJAE0aAA==.Mopeezie:BAAALgAECgEJAQAAAA==.Mordicant:BAAALgADCgEJAQABLgADCgQJBAADAAAAAA==.Morella:BAABLgAECn81AAIPAAcJmQ4IGQCDAQAPAAcJmQ4IGQCDAQAAAA==.',
Mu='Mucduck:BAAALgADCgEJAQAAAA==.Mustakrakish:BAAALgAECgEJAQAAAA==.',
My='Mym:BAAALgADCgcJBAAAAA==.Mystics:BAAALgADCgYJCwAAAA==.Mythrunduil:BAAALgADCgEJAQAAAA==.',
['Mé']='Médb:BAABLgAECn8WAAMEAAYJyRwFMgCcAQAEAAYJyRwFMgCcAQAeAAEJmxYmDgBFAAAAAA==.',
Na='Nathrold:BAAALgAECgIJAgABLgAECgYJDwADAAAAAA==.',
Ne='Neptune:BAACLgAFFH8SAAIJAAUJTRoxBACqAQAJAAUJTRoxBACqAQAuAAQKfx0AAwkACQnRHxYHAAIDAAkACQnRHxYHAAIDABAABwkkDs80AIQBAAAA.Nerfdks:BAAALgAECgEJAQAAAA==.Nerfpaladins:BAABLgAECn8dAAMTAAYJJRO2QABHAQATAAYJtRG2QABHAQAGAAYJWBGHEgDeAAAAAA==.Neruess:BAAALgADCgUJBQAAAA==.',
Ni='Nightbird:BAAALgAECgcJEAAAAA==.Ninediewatt:BAAALgADCgcJFgAAAA==.Nivella:BAAALgAECgYJCgAAAA==.Niçki:BAAALgADCgMJAwAAAA==.',
No='Notlockz:BAAALgADCgIJAgAAAA==.Novah:BAAALgADCgQJBQAAAA==.Noydb:BAAALgADCgYJBgABLgAECgYJDwADAAAAAA==.',
Nu='Nuah:BAAALgADCgYJDQAAAA==.',
Ob='Obayi:BAAALgADCgcJEQAAAA==.',
Og='Ogmadmonk:BAABLgAECn8kAAIYAAgJlR6mCwCmAgAYAAgJlR6mCwCmAgAAAA==.',
Ok='Oktobra:BAAALgAECgUJCgAAAA==.',
On='Onos:BAAALgAECgIJAgAAAA==.Onosm:BAAALgAECgQJBAAAAA==.',
Or='Orioan:BAAALgAECgMJBAAAAA==.',
Os='Osenya:BAAALgADCgkJCQABLgAECggJIgAdAGMhAA==.Osun:BAAALgADCggJCwAAAA==.',
Ou='Ouroboro:BAAALgADCgUJBQAAAA==.',
Ow='Owlbat:BAAALgAECgEJAQAAAA==.',
Pa='Padremort:BAAALgADCgYJBgAAAA==.Palantyr:BAABLgAECn9QAAIQAAgJrhqVGgA+AgAQAAgJrhqVGgA+AgAAAA==.Paly:BAAALgAECgEJAQAAAA==.Para:BAAALgADCgUJCQAAAA==.Patrician:BAAALgAECgYJEgAAAA==.',
Pe='Peehat:BAAALgADCgcJCQAAAA==.Penutbutter:BAAALgADCggJCAAAAA==.Pepegasus:BAAALgADCgcJBwAAAA==.',
Ph='Phobos:BAAALgADCgQJCAAAAA==.Phyloren:BAAALgADCgUJBgAAAA==.',
Pi='Pigsticker:BAAALgAECgQJBQAAAA==.Pixyfire:BAAALgAECgQJBAABLgAECggJIgAOAJ0hAA==.',
Po='Pokingharder:BAAALgADCgYJBgABLgAECgcJFwABAKoZAA==.',
Pu='Pulcherrimus:BAAALgAECgEJAQAAAA==.Purgeem:BAAALgADCgUJBQAAAA==.',
Pw='Pwiest:BAAALgADCgcJEAAAAA==.',
Qu='Quetzalcoatl:BAABLgAECn8WAAIfAAYJ9RyQBwC6AQAfAAYJ9RyQBwC6AQAAAA==.',
Ra='Raddish:BAAALgAECgUJCgAAAA==.Rahjlynn:BAAALgADCgcJBwAAAA==.Raiinn:BAAALgADCgUJBQAAAA==.Raylee:BAABLgAECn8iAAMPAAgJkx8NCABEAgAPAAcJih8NCABEAgACAAUJlxoUlAAwAQAAAA==.Razuki:BAABLgAECn8iAAMOAAgJnSGaAgDtAgAOAAgJnSGaAgDtAgATAAMJOw8jlgB5AAAAAA==.',
Re='Renarina:BAAALgAECgMJAwAAAA==.',
Rh='Rhaenies:BAAALgAECgYJEAAAAA==.Rhovanion:BAAALgAECgUJCAAAAA==.Rhuac:BAABLgAECn8YAAIHAAcJvxCCJABfAQAHAAcJvxCCJABfAQAAAA==.',
Ro='Rorschach:BAAALgAECgYJBwAAAA==.Rosefist:BAEALgADCgcJCAABLgAFFAQJDAANAIwVAA==.Rosemourne:BAEALgAECgIJAgABLgAFFAQJDAANAIwVAA==.Roseykat:BAAALgAECgYJDwAAAA==.Roshwyn:BAAALgAECgQJCgAAAA==.',
Ru='Ruckus:BAABLgAECn8nAAITAAgJuRYPPwApAgATAAgJuRYPPwApAgAAAA==.',
Sa='Saberwar:BAAALgAECgEJAQABLgAECgIJAgADAAAAAA==.Saintfury:BAAALgAECgQJBQAAAA==.Saintsfear:BAAALgAECgYJEgAAAA==.Saphalia:BAAALgADCgMJAwAAAA==.Saradomin:BAAALgADCgUJBAAAAA==.Sareenastar:BAABLgAECn8bAAILAAgJlSXyBAACAwALAAgJlSXyBAACAwAAAA==.Sasae:BAAALgAECgYJEQAAAA==.',
Sc='Scorias:BAAALgADCgQJAwAAAA==.',
Se='Selisztraza:BAAALgADCgEJAQAAAA==.Sephiróth:BAAALgADCgUJCAAAAA==.Sereni:BAAALgADCgQJBAAAAA==.Serenity:BAAALgAECgIJAgAAAA==.Serenitynow:BAAALgADCggJCQAAAA==.Sewald:BAAALgAECgIJAgAAAA==.',
Sh='Shadowzbane:BAAALgAECgIJAgAAAA==.Shahasha:BAAALgADCgEJAQAAAA==.Shalen:BAABLgAECn8aAAQZAAgJ1BLMDgCgAQAZAAgJxhLMDgCgAQAaAAYJoQ2XHQBCAQAfAAMJehI5GwBhAAAAAA==.Sharker:BAAALgADCgYJBgAAAA==.Sharpie:BAAALgADCgcJCgAAAA==.Sheer:BAAALgAECgYJCQAAAA==.Sheraa:BAAALgAECgYJCwAAAA==.Shiftystrike:BAABLgAECn8VAAIgAAYJtR/vCgAVAgAgAAYJtR/vCgAVAgAAAA==.Shifushield:BAAALgAECgYJBQAAAA==.Shireshannon:BAAALgAECgUJBQAAAA==.Shrunkador:BAACLgAFFH8FAAIQAAIJfg9UGwCUAAAQAAIJfg9UGwCUAAAuAAQKfyEAAhAACAnRHgwIAB8CABAACAnRHgwIAB8CAAAA.',
Si='Silk:BAAALgAECgYJDgAAAA==.Silmarkthree:BAABLgAECn8iAAIEAAgJ1hWNNACTAQAEAAgJ1hWNNACTAQAAAA==.Sinbåd:BAAALgAECgcJBwAAAA==.Sisterstar:BAAALgADCgMJAwAAAA==.',
Sl='Sleety:BAAALgAECgEJAwAAAA==.Slipknoth:BAACLgAFFH8PAAMNAAYJUAwrCQB2AQANAAUJZwkrCQB2AQAMAAYJ7g/1BgBNAQAuAAQKfxoABAwACQnsH4QbAAECAAwABwkcI4QbAAECAAsABwntF/ggANsBAA0ABAmZE7xAAKsAAAAA.',
Sn='Snekhain:BAAALgADCgMJAwAAAA==.Snuffaluffa:BAAALgAECgMJAwAAAA==.',
So='Somatra:BAAALgADCgkJCQAAAA==.Sorean:BAABLgAECn8qAAQWAAkJWiCZBQAdAgAFAAcJVBtXIQA9AgAWAAcJ2ByZBQAdAgAbAAcJUBqkMACuAQAAAA==.',
Sp='Spamtp:BAAALgAECgcJBwAAAA==.Specialmove:BAAALgAECgcJCAAAAA==.Spookydookie:BAAALgADCgkJCgAAAA==.',
St='Stifs:BAABLgAECn8aAAIGAAgJMQ3/FgBlAQAGAAgJMQ3/FgBlAQAAAA==.Stinkinglily:BAAALgAECgEJAgAAAA==.Strunrage:BAEALgADCgkJDgABLgAECggJMQATADIlAA==.Stÿx:BAAALgAECgYJEgAAAA==.',
Su='Sugarbomb:BAAALgADCgMJBAAAAA==.',
Sy='Sykotyk:BAAALgAECgcJDQAAAA==.Synchestra:BAAALgADCgcJCgAAAA==.',
Ta='Tadagain:BAAALgAECgQJEAAAAA==.Tagrith:BAAALgADCgMJAwAAAA==.Tankybears:BAABLgAECn8ZAAMdAAgJOxZFDADIAQAdAAgJOxZFDADIAQAHAAQJJxxAWwBAAQAAAA==.Tarmalok:BAAALgADCgkJCQAAAA==.Tazera:BAAALgAECgQJBAAAAA==.',
Te='Telekinesis:BAABLgAECn8UAAIWAAgJ8gxmDACYAQAWAAgJ8gxmDACYAQAAAA==.Tenbinza:BAAALgAECgIJAgAAAA==.Teos:BAABLgAECn8hAAIRAAgJsxN3BQDCAQARAAgJsxN3BQDCAQAAAA==.',
Th='Thainé:BAAALgAECgMJBgAAAA==.Thaldrassian:BAAALgADCgQJBAAAAA==.Thehatred:BAAALgADCgYJBgAAAA==.Therondar:BAAALgADCgEJAQAAAA==.Thromar:BAABLgAECn8VAAIEAAcJiBWvgADPAQAEAAcJiBWvgADPAQAAAA==.Thugz:BAAALgAECgUJDQAAAA==.Thunderlily:BAABLgAECn8TAAIhAAcJZhdrAgCbAQAhAAcJZhdrAgCbAQAAAA==.Thünder:BAAALgADCgcJBwABLgAECgcJFgAIAKQeAA==.',
Ti='Tinderbeef:BAAALgADCgcJCAAAAA==.Tinyround:BAAALgAECgEJAQAAAA==.Tirra:BAAALgAECgYJBwAAAA==.',
To='Toranth:BAABLgAECn8dAAIOAAcJzBR+EQDTAQAOAAcJzBR+EQDTAQAAAA==.Torq:BAABLgAECn8XAAIEAAYJ9xmShwDCAQAEAAYJ9xmShwDCAQABLgAECgcJFwAOAIghAA==.Torqumada:BAAALgAECgQJBQAAAA==.Toxian:BAABLgAECn8YAAIXAAYJFhGlWQCbAAAXAAYJFhGlWQCbAAAAAA==.Toxicelitist:BAABLgAECn8XAAIPAAYJSgxLCgAAAQAPAAYJSgxLCgAAAQAAAA==.',
Tr='Treedemon:BAABLgAECn8YAAIXAAgJQiGaFwDIAgAXAAgJQiGaFwDIAgAAAA==.Trymw:BAAALgADCgIJAgAAAA==.',
Ty='Tybearon:BAAALgADCgcJBwAAAA==.Tyreid:BAAALgADCgMJAwAAAA==.Tyrelitha:BAAALgADCgcJCAAAAA==.',
Ud='Udderchoad:BAAALgADCgEJAQAAAA==.',
Uh='Uhura:BAAALgADCgEJAQAAAA==.',
Ul='Ulfrir:BAABLgAECn8eAAMFAAgJXh1wFQCMAgAFAAgJXh1wFQCMAgAbAAMJMQoWbwCCAAAAAA==.Ultradukes:BAAALgADCgYJDwAAAA==.',
Un='Unatural:BAAALgAECgUJBQAAAA==.Unleashed:BAAALgAECgQJCQAAAA==.',
Va='Valarea:BAAALgADCgEJAQAAAA==.Valock:BAAALgADCgkJCQAAAA==.Valris:BAAALgAECgMJBAAAAA==.Vandham:BAAALgADCgEJAQAAAA==.Vanshifty:BAABLgAECn8mAAIHAAgJwSJxBADjAgAHAAgJwSJxBADjAgAAAA==.',
Ve='Veilf:BAAALgADCgYJDAAAAA==.Velf:BAAALgAECgEJAQAAAA==.Velrus:BAAALgAECgYJDAAAAA==.Venli:BAAALgAECgEJAQAAAA==.Venombite:BAAALgADCgMJAwAAAA==.',
Vi='Viktorax:BAAALgAECgYJCwAAAA==.Virtueozo:BAABLgAECn8aAAIfAAgJEBfJDwA+AgAfAAgJEBfJDwA+AgAAAA==.',
Vo='Volam:BAAALgAECgQJBAAAAA==.',
Wa='Waffle:BAAALgAECgUJCQABLgAECggJFgAFAD8OAA==.Wangwen:BAAALgADCgIJAgAAAA==.Wargue:BAAALgAECgYJEQAAAA==.',
We='Weebsz:BAAALgADCgQJBAAAAA==.Welindis:BAAALgADCgUJBQAAAA==.Wetkith:BAAALgADCgUJBQAAAA==.',
Wi='Windrider:BAAALgADCgIJAgAAAA==.Windwraith:BAAALgADCgUJCwAAAA==.Wizzard:BAAALgAECggJDgAAAQ==.',
Xa='Xaiyara:BAAALgADCgUJBQAAAA==.Xandaka:BAAALgADCgQJBAAAAA==.',
Xe='Xephir:BAAALgAECgIJAQAAAA==.',
Xi='Xidied:BAABLgAECn8lAAIKAAgJlR+aAwCMAgAKAAgJlR+aAwCMAgAAAA==.Xilon:BAAALgADCgcJBwABLgAECggJIgAdAGMhAA==.Xilra:BAABLgAECn8iAAIdAAgJYyEgBwAmAgAdAAgJYyEgBwAmAgAAAA==.Xilzen:BAAALgAECgUJDAABLgAECggJIgAdAGMhAA==.Xinia:BAAALgADCgEJAQAAAA==.',
Ye='Yew:BAAALgADCgMJAwAAAA==.',
Yi='Yikers:BAACLgAFFH8FAAIOAAIJuhtnFACeAAAOAAIJuhtnFACeAAAuAAQKfxwAAg4ACAnyHJ8WAFwCAA4ACAnyHJ8WAFwCAAAA.',
Yr='Yridai:BAAALgAECgYJCAAAAA==.',
Za='Zarsher:BAAALgADCgIJAgAAAA==.',
Zd='Zdk:BAAALgAECgEJAQABLgAECgYJCQADAAAAAA==.',
Ze='Zeldy:BAABLgAECn8XAAIFAAgJVxcVFADxAQAFAAgJVxcVFADxAQAAAA==.Zenthareal:BAAALgAECgYJEQAAAA==.Zeuc:BAAALgADCgMJAwAAAA==.Zeuus:BAAALgADCgMJBAAAAA==.',
Zh='Zhirl:BAAALgAECgcJEQAAAA==.Zhulgarosh:BAAALgADCgUJBQAAAA==.',
Zi='Zillidan:BAAALgAECgEJAQABLgAECgYJCQADAAAAAA==.',
Zm='Zmaster:BAAALgAECgYJBwABLgAECgYJCQADAAAAAA==.',
Zo='Zobeast:BAAALgADCgQJBAAAAA==.',
Zr='Zret:BAAALgAECgYJCQAAAA==.',
Zw='Zwar:BAAALgAECgEJAQABLgAECgYJCQADAAAAAA==.',
['Zö']='Zöey:BAAALgADCgQJBQAAAA==.',
['Åp']='Åpex:BAAALgADCgMJAwAAAA==.',
['Çl']='Çloudz:BAAALgADCgMJAwAAAA==.',
['Ða']='Ðark:BAACLgAFFH8HAAIFAAMJGg5kGACmAAAFAAMJGg5kGACmAAAuAAQKfyYAAgUACQluGgYVAI8CAAUACQluGgYVAI8CAAAA.',
['Ðr']='Ðr:BAABLgAECn8cAAMJAAgJkBv2IgANAgAJAAcJThr2IgANAgAQAAUJ3RgtGABRAQAAAA==.',
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
