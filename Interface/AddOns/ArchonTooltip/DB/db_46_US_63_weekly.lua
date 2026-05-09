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

local lookup = {'Warlock-Affliction','Warlock-Demonology','Monk-Mistweaver','Mage-Frost','Monk-Windwalker','Monk-Brewmaster','Hunter-BeastMastery','Paladin-Protection','Paladin-Retribution','Druid-Restoration','DeathKnight-Unholy','Shaman-Restoration','Unknown-Unknown','Priest-Holy','Priest-Shadow','Priest-Discipline','Paladin-Holy','Warrior-Protection','Hunter-Survival','Shaman-Elemental','Warlock-Destruction','DemonHunter-Devourer','Shaman-Enhancement','Warrior-Arms','Warrior-Fury','DemonHunter-Havoc','Rogue-Subtlety','Evoker-Augmentation','Evoker-Devastation','Hunter-Marksmanship','Druid-Balance','Mage-Fire','Rogue-Assassination','Rogue-Outlaw','Evoker-Preservation','Druid-Feral','DeathKnight-Blood','Mage-Arcane',}
local provider = {region='US',realm='Dawnbringer',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abdalhazred:BAACLgAFFH8MAAMBAAQJECNAAACgAQABAAQJECNAAACgAQACAAEJiR8ZcQBYAAAuAAQKfzQAAwEACQmYJFIAAGYDAAEACAm3JVIAAGYDAAIAAwnPHUVkAAYBAAAA.Abilus:BAAALgAECgMJCgAAAA==.Abolis:BAAALgAECgMJAwAAAA==.',
Ae='Aeldriel:BAAALgADCgcJCAAAAA==.',
Ag='Aggar:BAAALgADCgUJBQABLgAECggJFwADAJoQAA==.',
Ak='Akoa:BAAALgAECgEJAQAAAA==.',
Al='Alarak:BAABLgAECn8bAAIBAAgJbxXaAwC0AQABAAgJbxXaAwC0AQAAAA==.Alvierearn:BAABLgAECn8WAAIEAAgJsRFFUAB5AQAEAAgJsRFFUAB5AQAAAA==.',
Am='Amoradis:BAAALgADCgUJDgAAAA==.',
An='Anaeir:BAAALgADCgYJBgAAAA==.Angriff:BAAALgADCgQJBQAAAA==.Anisette:BAABLgAECn8WAAMFAAYJRhLvHQA0AQAFAAYJARLvHQA0AQAGAAQJDgo3RACFAAAAAA==.Anthria:BAAALgADCgcJEgAAAA==.',
Aq='Aqurala:BAABLgAECn8YAAIHAAgJtRvDGgD9AQAHAAgJtRvDGgD9AQAAAA==.',
Ar='Aradem:BAAALgADCgcJBwABLgAECgkJFwAIAAkGAA==.Aravenn:BAAALgADCgYJBgABLgAECgkJFwAIAAkGAA==.Arcis:BAABLgAECn8cAAIJAAYJYxCXYQArAQAJAAYJYxCXYQArAQAAAA==.Arealis:BAAALgADCgcJDAAAAA==.Argatem:BAAALgAECgQJBAABLgAECggJJQAKAEUeAA==.Arkangel:BAABLgAECn8gAAILAAkJ4RabGAA4AgALAAkJ4RabGAA4AgAAAA==.Arkharon:BAAALgADCgYJCQAAAA==.Arralyon:BAAALgADCgMJBgAAAA==.Artemesia:BAAALgAECgEJAQABLgAFFAUJFwAMAKocAA==.Arthäs:BAAALgAECgQJBAAAAA==.Aryrn:BAAALgADCgUJBQAAAA==.',
As='Asakua:BAAALgAECgMJBgAAAA==.Asiya:BAAALgAECgQJBQAAAA==.Assandra:BAAALgADCgUJBQAAAA==.',
At='Athul:BAAALgADCgUJCgAAAA==.',
Au='Aurlyn:BAAALgADCgcJDwAAAA==.',
Av='Avatartele:BAAALgAECgIJAwAAAA==.Avatartouka:BAABLgAECn8cAAIMAAgJ5SEwBQDoAgAMAAgJ5SEwBQDoAgAAAA==.Avianthel:BAAALgADCgMJAgAAAA==.Avraria:BAAALgADCgEJAQAAAA==.Avyl:BAAALgAECgYJEAAAAA==.Avylastorica:BAAALgADCgYJBgABLgAECgYJEAANAAAAAA==.',
Aw='Awsomninja:BAABLgAECn8dAAIGAAgJXyJ3BQCJAgAGAAgJXyJ3BQCJAgAAAA==.',
Ax='Axxain:BAAALgADCgkJGgAAAA==.',
Az='Azaralle:BAAALgADCgEJAQAAAA==.Azeazal:BAAALgAECgUJCgAAAA==.Azlifan:BAAALgADCgQJBAAAAA==.',
Ba='Baddlandss:BAAALgAECgQJCAAAAA==.Bagador:BAAALgAECgQJBAAAAA==.Bastais:BAAALgAECgEJAQAAAA==.Batozai:BAAALgADCgEJAQAAAA==.Baumstack:BAAALgADCgUJBQAAAA==.',
Bd='Bdibz:BAAALgADCgcJDAAAAA==.',
Be='Beautifulluv:BAABLgAECn8cAAQOAAgJRSEuBADWAgAOAAgJRSEuBADWAgAPAAUJDA4jLQDlAAAQAAEJkAzKUwA6AAAAAA==.Bekabeka:BAACLgAFFH8MAAIRAAQJOx3kCwBnAQARAAQJOx3kCwBnAQAuAAQKfzUAAxEACQk7JNUBAEQDABEACQk7JNUBAEQDAAgAAgkJAps4ABoAAAAA.Bera:BAAALgAECgQJDAABLgAECgcJCQANAAAAAA==.Beramage:BAAALgAECgEJAQAAAA==.',
Bi='Billybobjr:BAABLgAECn8tAAIMAAcJ0iRrBgDNAgAMAAcJ0iRrBgDNAgAAAA==.Bippitybop:BAAALgAECgEJAQAAAA==.',
Bl='Blackbart:BAAALgADCgEJAQAAAA==.',
Bo='Boamere:BAABLgAECn8XAAISAAgJ6RJgDwBtAQASAAgJ6RJgDwBtAQAAAA==.Botemedel:BAAALgADCgEJAQAAAA==.',
Br='Braided:BAAALgAECgIJAwAAAA==.Brakkar:BAABLgAECn8bAAITAAgJGw4REQCdAQATAAgJGw4REQCdAQAAAA==.Brandish:BAAALgADCgcJBwAAAA==.Breadstick:BAABLgAECn8kAAIKAAYJTSXcCwCMAgAKAAYJTSXcCwCMAgAAAA==.Brevik:BAAALgADCgMJAwAAAA==.Brutaal:BAAALgADCgcJCwAAAA==.Brynhild:BAAALgAFFAIJAwAAAA==.Brütaal:BAABLgAECn8VAAMMAAYJzRlTHwC4AQAMAAYJzRlTHwC4AQAUAAEJAAARkAAnAAAAAA==.',
Bu='Bubsydogo:BAAALgAECgYJCgAAAA==.Buddytheelf:BAABLgAECn8bAAMCAAYJaSPlMQCcAQACAAQJ4SLlMQCcAQAVAAIJiyV3GgBvAAAAAA==.Bumpyflea:BAAALgADCgUJBQAAAA==.',
Ca='Cairnsilvers:BAAALgADCgEJAQAAAA==.Camus:BAABLgAECn8UAAIJAAYJQRmwRwBuAQAJAAYJQRmwRwBuAQAAAA==.Capped:BAAALgADCgMJAwAAAA==.Catgirl:BAAALgAECgEJAQAAAA==.',
Ce='Cebollin:BAAALgAECgUJCAAAAA==.Celaian:BAAALgAECgUJCQABLgAECggJEAANAAAAAA==.Celamor:BAAALgAECgQJBwAAAA==.Celasmine:BAAALgADCgYJCAAAAA==.Celpanda:BAAALgAECggJEAAAAA==.',
Ch='Charlamayne:BAAALgADCgcJBwAAAA==.Charybdia:BAABLgAECn8VAAIWAAYJ0QYGaQDKAAAWAAYJ0QYGaQDKAAAAAA==.Chidõri:BAACLgAFFH8KAAIUAAQJuh28CABpAQAUAAQJuh28CABpAQAuAAQKfyoAAxQACQl8I0kFAEMDABQACQl8I0kFAEMDABcAAgnPFuQlAHkAAAAA.Chudlock:BAAALgAECgYJDgAAAA==.Chunna:BAABLgAECn8iAAIFAAgJPx9YBgBrAgAFAAgJPx9YBgBrAgAAAA==.Chunni:BAABLgAECn8XAAIFAAgJEQdIKgDiAAAFAAgJEQdIKgDiAAAAAA==.',
Co='Codap:BAAALgADCgcJBwAAAA==.Coolerfrieza:BAAALgAECgEJAgAAAA==.',
Cp='Cpr:BAABLgAECn8XAAIRAAcJiCGuDwCXAgARAAcJiCGuDwCXAgAAAA==.',
Cr='Crepic:BAAALgAECgQJBAAAAA==.Cruelkitty:BAAALgAECgUJDAAAAA==.',
Cu='Cudibandit:BAAALgADCgcJDwAAAA==.',
Cy='Cynaria:BAAALgAECgEJAgAAAA==.Cyralai:BAACLgAFFH8fAAIKAAYJKBU3BgDYAQAKAAYJKBU3BgDYAQAuAAQKfxkAAgoACQlOIfAQALACAAoACQlOIfAQALACAAAA.',
Da='Dabofdeath:BAAALgAECgIJAgAAAA==.Dalov:BAABLgAECn8aAAMRAAcJSSbyBwDvAgARAAcJSSbyBwDvAgAJAAIJbx0ZpACqAAAAAA==.Dankley:BAAALgAECgYJEwAAAA==.Darkestnyte:BAAALgAECgYJBgAAAA==.Darkk:BAAALgAECgQJDAAAAA==.Darkomenz:BAAALgADCgUJBQAAAA==.Darkrhaenies:BAAALgADCgcJBwAAAA==.Darkwindx:BAAALgADCggJCQABLgAECgUJBwANAAAAAA==.Datezero:BAAALgADCgQJBAAAAA==.',
De='Deadhealer:BAAALgADCgMJAwAAAA==.Deafknighte:BAAALgAECgMJAwAAAA==.Deathboi:BAABLgAECn8fAAILAAcJSQ/JRgBnAQALAAcJSQ/JRgBnAQAAAA==.Deathburgur:BAAALgAECggJEQAAAA==.Deathfromme:BAAALgAECgYJCgAAAA==.Deathstro:BAAALgAECgQJCAABLgAECgkJIAALAOEWAA==.Decayed:BAAALgAECgIJAwAAAA==.Dentridios:BAAALgADCgIJAgAAAA==.Deson:BAABLgAECn8aAAMRAAcJuAwOQgBwAQARAAcJuAwOQgBwAQAJAAUJiAgXlADGAAAAAA==.Deviantart:BAAALgAECgEJAQAAAA==.',
Di='Diana:BAAALgAECgYJEAAAAA==.Diietriich:BAABLgAECn8gAAIEAAYJ4iTSJgAIAgAEAAYJ4iTSJgAIAgAAAA==.Dilligaaf:BAAALgADCgMJAwAAAA==.',
Do='Docbeanz:BAAALgADCgMJAwAAAA==.Donkypunch:BAAALgADCgQJBAAAAA==.Dontjudgemê:BAAALgADCgIJAgAAAA==.Dopie:BAAALgADCgIJAgAAAA==.Dorcina:BAAALgADCgcJHgAAAA==.',
Dr='Dracthyr:BAAALgADCgUJDQAAAA==.Dragoondpain:BAAALgAECgQJBgAAAQ==.Draltina:BAABLgAECn8XAAMBAAgJNQmjDQBaAQABAAgJNQmjDQBaAQACAAEJywLoLwEhAAAAAA==.Drunkbera:BAAALgAECgcJBwAAAA==.',
Du='Dunks:BAAALgAECgcJCAAAAA==.',
Dy='Dylghoul:BAAALgADCgUJBQAAAA==.',
['Dí']='Dírac:BAAALgAECgcJCQABLgAFFAIJAgANAAAAAA==.',
Ef='Efforex:BAAALgADCgQJBAAAAA==.',
El='Elactoplasm:BAAALgAECgMJAwAAAA==.Ellistrae:BAAALgADCgEJAQAAAA==.Ellysia:BAAALgADCgEJAQAAAA==.',
Em='Emmel:BAAALgADCggJCwAAAA==.',
Eq='Equeslucis:BAAALgAECgcJBwAAAA==.',
Er='Erodrana:BAAALgAECgYJDAAAAA==.Eromir:BAAALgAECgUJCQAAAA==.Eryi:BAABLgAECn8XAAIDAAgJmhC0FgCgAQADAAgJmhC0FgCgAQAAAA==.',
Et='Ethan:BAABLgAECn8YAAMYAAkJNxuQDgBbAQAYAAYJVRSQDgBbAQAZAAQJ6CIPLAAiAQAAAA==.',
Ev='Evonari:BAAALgADCgIJAgAAAA==.',
Ex='Exoticfrost:BAAALgADCgIJAgAAAA==.',
['Eí']='Eísheth:BAAALgADCgUJBAAAAA==.',
Fa='Faegen:BAAALgAECgEJAQAAAA==.Falkønn:BAAALgAECgIJAgAAAA==.Fangytooth:BAABLgAECn8lAAITAAkJ2CIYBACJAgATAAkJ2CIYBACJAgAAAA==.Fashaun:BAAALgAECgIJAgAAAA==.Faze:BAAALgAECgYJEAAAAA==.',
Fe='Ferrus:BAACLgAFFH8WAAMWAAYJZyKnAwD9AQAWAAYJZyKnAwD9AQAaAAQJyBl4DAC3AAAuAAQKfxsAAxoACQnrJdANAIYCABYACAn2I+ccAKQCABoABwncJNANAIYCAAAA.',
Ff='Ffleuderflam:BAAALgAECgYJBgAAAA==.',
Fr='Frose:BAAALgADCgEJAQAAAA==.Frostyblast:BAAALgADCgUJBgAAAA==.',
Fu='Fupacabra:BAAALgADCgEJAQAAAA==.Furiosity:BAAALgAECgEJAgAAAA==.Fuzzybear:BAAALgAECgcJCAABLgAECgkJJQATANgiAA==.Fuzzywar:BAAALgAECgYJBgABLgAECgkJJQATANgiAA==.',
Ga='Gabomonk:BAAALgAFFAIJAwAAAA==.Gamalia:BAAALgADCgUJBQAAAA==.Garudekhan:BAAALgADCgUJBQAAAA==.',
Ge='Genreallee:BAAALgAECgUJDQAAAA==.Gernab:BAAALgADCgYJBgAAAA==.',
Gh='Ghost:BAAALgAECggJDwAAAA==.',
Gi='Gianna:BAAALgAECgkJEwAAAA==.Gizzar:BAAALgADCgYJCgAAAA==.',
Gl='Glau:BAAALgADCgcJBwABLgAECgcJHAAbALwXAA==.Glimpsed:BAAALgAECgcJCQAAAA==.Globgore:BAAALgADCgIJAgAAAA==.Gloçk:BAAALgAECgMJBwABLgAECgYJEQANAAAAAA==.',
Go='Goofy:BAABLgAECn8fAAIJAAcJXCG/JACUAgAJAAcJXCG/JACUAgAAAA==.Gorrik:BAAALgADCgUJBQAAAA==.',
Gr='Greyfeather:BAAALgADCgEJAgAAAA==.Grimeace:BAAALgADCgQJBAAAAA==.',
Gu='Gunduin:BAABLgAECn8cAAIHAAcJxiG1FAAqAgAHAAcJxiG1FAAqAgAAAA==.',
Gw='Gweb:BAAALgAECgIJAgAAAA==.',
Gy='Gyda:BAAALgAECgYJEgAAAA==.Gyuyuki:BAABLgAECn8kAAIUAAYJQQ66LAAEAQAUAAYJQQ66LAAEAQAAAA==.',
Ha='Hakuanah:BAAALgADCgEJAQAAAA==.Halvorak:BAAALgADCgcJCgAAAA==.Harryp:BAABLgAECn8iAAMcAAgJQxKSEgC2AQAcAAgJQxKSEgC2AQAdAAYJLwmSIQAfAQAAAA==.Hast:BAAALgAECgMJAwAAAA==.',
He='Hearthzilla:BAAALgAECgEJAQABLgAECgcJFQAUAPIfAA==.Hellsbow:BAAALgAECgYJDgAAAA==.Hermin:BAAALgADCgQJBQAAAA==.',
Ho='Holyhellz:BAAALgADCgEJAQAAAA==.Honeyboo:BAAALgAECgEJAQABLgAECgkJMAAKAIUgAA==.Hots:BAAALgADCgcJBwAAAA==.Hotzz:BAAALgAECgEJAQAAAA==.',
Hr='Hraesvelgr:BAAALgADCggJBwAAAA==.',
Hu='Huntavious:BAABLgAECn8fAAQTAAkJFRtyBAB+AgATAAkJcxlyBAB+AgAHAAUJGhvDXgBLAQAeAAEJyBPVigAwAAAAAA==.',
['Hë']='Hëllen:BAABLgAECn8WAAIJAAYJqh9qUgBPAQAJAAYJqh9qUgBPAQAAAA==.',
Ia='Iamshinigamy:BAAALgAECgIJAgABLgAECgcJFwAEAPMaAA==.',
Ii='Iichimaru:BAAALgAECgQJBAAAAA==.',
Il='Illidupe:BAAALgADCgMJAwAAAA==.',
Iv='Ivey:BAABLgAECn8lAAIKAAgJRR5pCQCyAgAKAAgJRR5pCQCyAgAAAA==.',
Iz='Izes:BAAALgADCgEJAQAAAA==.',
Ja='Jaagganug:BAAALgADCgMJAwAAAA==.Jacenne:BAAALgAECgUJDgAAAA==.',
Jd='Jdirty:BAAALgAECgQJCQAAAA==.',
Je='Jellytime:BAAALgAECgEJAwAAAA==.',
Jo='Josephyn:BAAALgAECgMJAwABLgAFFAUJFwAMAKocAA==.',
Ju='Jugernaut:BAAALgAECgEJAQAAAA==.Jumpmann:BAAALgAECgMJAwAAAA==.Justdesserts:BAAALgAECgEJAQAAAA==.Justix:BAAALgADCggJEwAAAA==.',
Ka='Kadaffy:BAAALgADCgcJBwAAAA==.Kakusu:BAAALgAECgYJEQAAAA==.Kakuta:BAAALgAECgQJBAABLgAECgUJCAANAAAAAA==.Kakutá:BAAALgAECgUJCAAAAA==.Kalru:BAAALgADCgQJCgAAAA==.Kargar:BAAALgAECgEJAQAAAA==.Katharsis:BAABLgAECn8fAAIJAAkJ3hSMJQDsAQAJAAkJ3hSMJQDsAQAAAA==.',
Ke='Keba:BAAALgADCggJDwABLgAFFAQJDAARADsdAA==.Keévs:BAAALgADCgQJBAAAAA==.',
Kh='Khalidisi:BAABLgAECn8YAAQRAAkJLxnVFgDXAQARAAkJLxnVFgDXAQAJAAQJVwSCqACiAAAIAAEJHh4bKgBTAAAAAA==.Khalizar:BAAALgAECgMJAwAAAA==.Kharazim:BAAALgADCgEJAQABLgAECgYJGAAWAMcVAA==.Khenja:BAAALgAECgEJAQAAAA==.Khál:BAAALgADCgYJBgAAAA==.',
Ki='Killerelf:BAAALgAECgIJAgAAAA==.',
Kk='Kkiilleerr:BAAALgAECgQJBAAAAA==.',
Ko='Kobbaltcilar:BAAALgAECgQJBAAAAA==.Koraleena:BAAALgAECgQJBAAAAA==.Korbo:BAABLgAECn8ZAAMUAAYJCh8jGgB+AQAUAAQJ6yAjGgB+AQAMAAMJOxrLTADMAAAAAA==.Korbulo:BAAALgAECgYJCQAAAA==.Korlothel:BAABLgAECn8XAAIIAAkJCQYFJgDYAAAIAAkJCQYFJgDYAAAAAA==.',
Kr='Krumpus:BAAALgAECgcJEgAAAA==.',
Ku='Kungfuuy:BAABLgAECn8ZAAIGAAYJyh+jEwCiAQAGAAYJyh+jEwCiAQAAAA==.Kurtevade:BAAALgAECgEJAQAAAA==.',
Ky='Kynsong:BAAALgAECgUJDQAAAA==.',
['Kà']='Kàlbrews:BAABLgAECn81AAIGAAkJbyYnAACFAwAGAAkJbyYnAACFAwAAAA==.',
La='Lainiee:BAAALgADCgEJAQAAAA==.Lavismad:BAEBLgAECn8rAAQSAAkJxSMyBgAzAgAZAAgJLSPTIQBGAgASAAcJniAyBgAzAgAYAAEJRiV2MgBpAAAAAA==.Lavoc:BAEALgADCgcJBwABLgAECgkJKwASAMUjAA==.Lavv:BAEALgAECgYJBwABLgAECgkJKwASAMUjAA==.',
Le='Leshah:BAAALgAECgIJAgAAAA==.',
Li='Lichkingdied:BAAALgADCgUJBQAAAA==.Lightndpain:BAAALgAECgEJAQAAAA==.Lilypetal:BAAALgAECgQJBwAAAA==.Littlebucket:BAAALgADCgEJAQAAAA==.',
Lo='Lockdpain:BAAALgAECgYJEwABLgAECgQJBgANAAAAAQ==.Logov:BAAALgAECgYJDwAAAA==.Loraine:BAAALgADCgEJAQAAAA==.Loìsbethe:BAAALgAECgQJBAAAAA==.',
Lu='Luciferra:BAAALgAECgIJAwABLgAFFAUJFwAMAKocAA==.Lukey:BAAALgAECgMJAwAAAA==.Lunartemis:BAAALgAECgUJCAABLgAECggJDAANAAAAAA==.',
['Lö']='Lörax:BAAALgADCgQJBQAAAA==.',
['Lû']='Lûnafreya:BAAALgAECggJEgAAAA==.',
Ma='Maelera:BAAALgADCgkJDAAAAA==.Maetromundo:BAAALgAECgEJAQAAAA==.Magentas:BAAALgADCgIJAgAAAA==.Magickul:BAAALgADCggJCAAAAA==.Mahlah:BAAALgAECgQJBAAAAA==.Malaboo:BAAALgAECgEJAQABLgAECgkJMAAKAIUgAA==.Maletsy:BAAALgAECgEJAQABLgAECgcJHAAHAMYhAA==.Maliboo:BAABLgAECn8wAAMKAAkJhSAxAwBDAwAKAAkJhSAxAwBDAwAfAAEJpwJ2jwAcAAAAAA==.Maxamus:BAAALgAECgUJEgAAAA==.',
Mc='Mcflurry:BAAALgAECgMJBgAAAA==.',
Me='Medarisa:BAAALgAECgYJCwAAAA==.Medavia:BAAALgADCgUJBQAAAA==.Melisandr:BAAALgAECgIJAgAAAA==.Merkenier:BAABLgAECn8bAAIfAAgJSwrxIwAaAQAfAAgJSwrxIwAaAQAAAA==.Merkur:BAAALgADCgkJCQABLgAECggJGwAfAEsKAA==.',
Mi='Midnitehunt:BAAALgAECgQJBAAAAA==.Miragia:BAAALgAECgUJBwAAAA==.Missmayhem:BAAALgAECgUJCAAAAA==.Missmayhemm:BAAALgADCgQJBgAAAA==.',
Mo='Modifiedmix:BAAALgAECgYJEgAAAA==.Modsabadtank:BAAALgAECgUJBQABLgAECgYJEgANAAAAAA==.Mokomohama:BAAALgAECgcJBwAAAA==.Monatazumaa:BAAALgAECgEJAgAAAA==.Moonbloom:BAAALgAECgQJCAABLgAFFAUJFwAMAKocAA==.Mopeezie:BAAALgAECgEJAQAAAA==.Mordicant:BAAALgADCgEJAQABLgADCgcJCAANAAAAAA==.Morella:BAABLgAECn81AAIVAAcJmQ4HGQCDAQAVAAcJmQ4HGQCDAQAAAA==.',
Mu='Mucduck:BAAALgADCgEJAQAAAA==.Mustakrakish:BAAALgAECgEJAQAAAA==.',
My='Mym:BAAALgADCgcJBAAAAA==.Mystics:BAAALgADCgYJCwAAAA==.Mythrunduil:BAAALgADCgEJAQAAAA==.',
['Mé']='Médb:BAABLgAECn8dAAMEAAYJ4x7aQAClAQAEAAYJGh3aQAClAQAgAAIJCx5lBgC1AAAAAA==.',
Na='Nathrold:BAAALgAECgIJAwABLgAECgYJEQANAAAAAA==.',
Ne='Neptune:BAACLgAFFH8XAAIMAAUJqhx1BQC9AQAMAAUJqhx1BQC9AQAuAAQKfx0AAwwACQnRHxcHAAIDAAwACQnRHxcHAAIDABQABwkkDs40AIQBAAAA.Nerfdks:BAAALgAECgcJBwAAAA==.Nerfpaladins:BAABLgAECn8dAAMJAAYJJRPMWgA7AQAJAAYJtRHMWgA7AQAIAAYJWBE+GADVAAAAAA==.Neruess:BAAALgADCgUJBQAAAA==.',
Ni='Nightbird:BAABLgAECn8cAAMbAAcJvBfFEQCOAQAbAAcJThfFEQCOAQAhAAYJ8BWfDgAsAQAAAA==.Ninediewatt:BAAALgADCgcJFwAAAA==.Nivella:BAAALgAECgYJCgAAAA==.Nixaana:BAAALgADCgYJBgAAAA==.Niçki:BAAALgADCgMJAwAAAA==.',
No='Notlockz:BAAALgADCgIJAgAAAA==.Novah:BAAALgADCgQJBQAAAA==.Noydb:BAAALgADCgYJBgABLgAECggJFwASAOkSAA==.',
Nu='Nuah:BAAALgADCgYJDQAAAA==.',
Ny='Nyxsia:BAEALgAECgEJAQABLgAFFAYJDwAZAN0UAA==.',
['Nè']='Nèo:BAAALgADCgYJBgAAAA==.',
Ob='Obayi:BAAALgADCgkJFgAAAA==.',
Og='Ogmadmonk:BAACLgAFFH8GAAIaAAIJmw41DgCiAAAaAAIJmw41DgCiAAAuAAQKfyQAAhoACAmVHqULAKYCABoACAmVHqULAKYCAAAA.',
Ok='Oktobra:BAAALgAECgYJEAAAAA==.',
On='Onos:BAAALgAECgIJAgAAAA==.Onosm:BAAALgAECgQJBAAAAA==.',
Or='Orioan:BAAALgAECgMJBAAAAA==.Orux:BAAALgAECgUJBQAAAA==.',
Os='Osenya:BAAALgAECgYJBgABLgAECgkJKwAfAAUhAA==.Osun:BAAALgADCggJCwAAAA==.',
Ou='Ouroboro:BAAALgADCgUJBQAAAA==.',
Ow='Owlbat:BAAALgAECgEJAQAAAA==.',
Pa='Padremort:BAAALgADCgYJBgAAAA==.Palantyr:BAABLgAECn9QAAIUAAgJrhqUGgA+AgAUAAgJrhqUGgA+AgAAAA==.Paly:BAAALgAECgEJAQAAAA==.Para:BAAALgAECgQJBAAAAA==.Patrician:BAABLgAECn8ZAAIiAAYJkxEEBwAtAQAiAAYJkxEEBwAtAQAAAA==.',
Pe='Peehat:BAAALgADCgcJCQAAAA==.Penutbutter:BAAALgAECgEJAQAAAA==.Pepegasus:BAAALgADCgcJBwAAAA==.',
Ph='Phobos:BAAALgADCgQJCAAAAA==.Phyloren:BAAALgADCgUJBgAAAA==.',
Pi='Pigsticker:BAAALgAECgQJBQAAAA==.Pixyfire:BAAALgAECgQJBAABLgAECgkJKwARAJcgAA==.',
Po='Pokingharder:BAAALgAECggJCAAAAA==.',
Pu='Pulcherrimus:BAAALgAECgEJAQAAAA==.Purgeem:BAAALgADCgUJBQAAAA==.Pushpop:BAAALgADCgUJBQABLgAECggJUAAUAK4aAA==.',
Pw='Pwiest:BAAALgADCgcJEAAAAA==.',
Qu='Quetzalcoatl:BAABLgAECn8WAAIjAAYJ9Rw3CgCxAQAjAAYJ9Rw3CgCxAQAAAA==.',
Ra='Raambox:BAAALgAECgQJBAAAAA==.Radak:BAAALgADCgYJBgAAAA==.Raddish:BAAALgAECgYJEAAAAA==.Rahjlynn:BAAALgADCgcJBwAAAA==.Rahken:BAAALgAECgcJBwAAAA==.Raiinn:BAAALgADCgUJBQAAAA==.Raylee:BAABLgAECn8xAAMCAAkJ9h9cBwDPAgACAAgJGB5cBwDPAgAVAAcJkR8OCABEAgAAAA==.Razuki:BAABLgAECn8rAAMRAAkJlyC+AgAiAwARAAkJlyC+AgAiAwAJAAcJyAwmYQArAQAAAA==.',
Rf='Rfd:BAAALgADCgcJBwAAAA==.',
Rh='Rhaenies:BAAALgAECgYJEAAAAA==.Rharr:BAAALgADCgQJBAAAAA==.Rhovanion:BAAALgAECgUJCAAAAA==.Rhuac:BAABLgAECn8aAAIKAAcJcxJeLQBvAQAKAAcJcxJeLQBvAQAAAA==.',
Ri='Risakah:BAAALgAECgEJAQAAAA==.',
Ro='Rorschach:BAAALgAECgYJCAAAAA==.Rosefist:BAEALgADCgcJCAABLgAFFAQJDQAQAIwVAA==.Rosemourne:BAEALgAECgIJAgABLgAFFAQJDQAQAIwVAA==.Roseykat:BAABLgAECn8WAAIHAAYJRQq6UwATAQAHAAYJRQq6UwATAQAAAA==.Roshwyn:BAAALgAECgYJDQAAAA==.',
Ru='Ruckus:BAABLgAECn8nAAIJAAgJuRYNPwApAgAJAAgJuRYNPwApAgAAAA==.',
Sa='Saberwar:BAAALgAECgEJAQABLgAECgIJAgANAAAAAA==.Saintfury:BAAALgAECgQJBQAAAA==.Saintsfear:BAABLgAECn8ZAAIZAAYJcw9jJwA8AQAZAAYJcw9jJwA8AQAAAA==.Sanchito:BAAALgADCgMJAwAAAA==.Saphalia:BAAALgADCgMJAwAAAA==.Saradomin:BAAALgADCgUJBAAAAA==.Sareenastar:BAABLgAECn8lAAMOAAkJ1yUzAADZAwAOAAkJ1yUzAADZAwAPAAEJ3wl1TwA6AAAAAA==.Sasae:BAABLgAECn8XAAIGAAYJyhC1JwAHAQAGAAYJyhC1JwAHAQAAAA==.',
Sc='Scorias:BAAALgADCgQJAwAAAA==.',
Se='Selisztraza:BAAALgADCgEJAQAAAA==.Sephiróth:BAAALgADCgUJCAAAAA==.Sereni:BAAALgADCgQJBAAAAA==.Serenity:BAAALgAECgYJCAAAAA==.Serenitynow:BAAALgAECgEJAQAAAA==.Sewald:BAAALgAECgIJBAAAAA==.',
Sh='Shadowzbane:BAAALgAECgIJAgAAAA==.Shahasha:BAAALgADCgEJAQAAAA==.Shalen:BAABLgAECn8dAAQcAAgJxRMxFACnAQAcAAgJtxMxFACnAQAdAAYJoQ2SHQBCAQAjAAMJehLiNwCtAAAAAA==.Sharker:BAAALgADCgYJBgAAAA==.Sharpie:BAAALgADCgcJCgAAAA==.Sheer:BAAALgAECgYJEAAAAA==.Sheraa:BAAALgAECgYJEgAAAA==.Shiftystrike:BAABLgAECn8VAAIkAAYJtR/wCgAVAgAkAAYJtR/wCgAVAgAAAA==.Shifushield:BAAALgAECgcJBgAAAA==.Shireshannon:BAAALgAECgUJBQAAAA==.Shrunkador:BAACLgAFFH8FAAIUAAIJfg8WJACOAAAUAAIJfg8WJACOAAAuAAQKfyYAAhQACAnUHnoMABQCABQACAnUHnoMABQCAAAA.',
Si='Silk:BAAALgAECgYJDgAAAA==.Silmarkthree:BAABLgAECn8rAAIEAAkJ/xRPKQD9AQAEAAkJ/xRPKQD9AQAAAA==.Sinbåd:BAAALgAECgcJBwAAAA==.Sisterstar:BAAALgADCgMJAwAAAA==.',
Sl='Sleety:BAAALgAECgIJBAAAAA==.Slipknoth:BAACLgAFFH8TAAMPAAYJ1RimBwBpAQAPAAYJ1RimBwBpAQAQAAUJZQk2DgBkAQAuAAQKfxsABA8ACQlYIIIbAAECAA8ABwmrI4IbAAECAA4ABwntF/ggANsBABAABAmZE71AAKsAAAAA.',
Sn='Snekhain:BAAALgADCgMJAwAAAA==.Snuffaluffa:BAAALgAECgMJAwAAAA==.',
So='Somatra:BAAALgADCgkJCQAAAA==.Sorean:BAACLgAFFH8IAAITAAQJoBEzCABRAQATAAQJoBEzCABRAQAuAAQKfy0ABBMACQm+IOgIABgCAAcABwlUG1YhAD0CABMABwldHegIABgCAB4ABwlQGvkvALUBAAAA.',
Sp='Specialmove:BAAALgAECgcJCAAAAA==.Spookydookie:BAAALgADCgkJCgAAAA==.',
St='Stifs:BAABLgAECn8aAAIIAAgJMQ0AFwBlAQAIAAgJMQ0AFwBlAQAAAA==.Stinkinglily:BAAALgAECgEJAgAAAA==.Strunrage:BAEALgAECgUJBQABLgAECggJMwAJAMQlAA==.Stÿx:BAABLgAECn8ZAAIlAAYJ6gU3JACkAAAlAAYJ6gU3JACkAAAAAA==.',
Su='Sugarbomb:BAAALgADCgMJBAAAAA==.',
Sy='Sykotyk:BAAALgAECgkJDwAAAA==.Synchestra:BAAALgADCgcJCgAAAA==.',
Ta='Tadagain:BAABLgAECn8VAAMJAAUJ8RG7eQD4AAAJAAUJ8RG7eQD4AAARAAQJ2gVxdgChAAAAAA==.Tagrith:BAAALgADCgMJAwAAAA==.Tankybears:BAABLgAECn8kAAMfAAkJfBcmCgApAgAfAAkJfBcmCgApAgAKAAYJ8xk+WwBAAQAAAA==.Tarmalok:BAAALgADCgkJCQAAAA==.Tazera:BAAALgAECgUJCQAAAA==.',
Te='Telekinesis:BAABLgAECn8cAAITAAgJxA/LDgC8AQATAAgJxA/LDgC8AQAAAA==.Tenbinza:BAAALgAECgMJBAAAAA==.Teos:BAABLgAECn8lAAIXAAgJZhU/BwC/AQAXAAgJZhU/BwC/AQAAAA==.',
Th='Thainé:BAAALgAECgMJBgAAAA==.Thaldrassian:BAAALgADCgQJBAAAAA==.Thehatred:BAAALgADCgYJBgAAAA==.Therondar:BAAALgADCgEJAQAAAA==.Thromar:BAABLgAECn8VAAIEAAcJiBWqgADPAQAEAAcJiBWqgADPAQAAAA==.Thugz:BAAALgAECgUJDQAAAA==.Thunderlily:BAABLgAECn8ZAAMmAAcJ3BjoBgCgAQAmAAcJZhfoBgCgAQAEAAYJZBdyUAB5AQAAAA==.Thünder:BAAALgADCgcJBwABLgAECgcJFgALAKQeAA==.',
Ti='Tinderbeef:BAAALgADCgcJCAAAAA==.Tinyround:BAAALgAECgEJAQAAAA==.Tirra:BAAALgAECgcJCAAAAA==.',
To='Toranth:BAABLgAECn8lAAIRAAgJphWEDwAkAgARAAgJphWEDwAkAgAAAA==.Torq:BAABLgAECn8XAAIEAAYJ9xmMhwDCAQAEAAYJ9xmMhwDCAQABLgAECgcJFwARAIghAA==.Torqumada:BAAALgAECgQJBQAAAA==.Toxian:BAABLgAECn8cAAIWAAYJVxJDUQAGAQAWAAYJVxJDUQAGAQAAAA==.Toxicelitist:BAABLgAECn8fAAMVAAcJKwz5CgAlAQAVAAcJKwz5CgAlAQACAAEJmgE48QAdAAAAAA==.',
Tr='Treedemon:BAABLgAECn8hAAIWAAkJvSDxCwBwAgAWAAkJvSDxCwBwAgAAAA==.Trymw:BAAALgADCgIJAgAAAA==.',
Tu='Tutimon:BAAALgADCgEJAQAAAA==.',
Ty='Tybearon:BAAALgADCgcJBwAAAA==.Tyreid:BAAALgADCgMJAwAAAA==.Tyrelitha:BAAALgADCgcJCAAAAA==.',
Ud='Udderchoad:BAAALgADCgEJAQAAAA==.',
Uh='Uhura:BAAALgADCgEJAQAAAA==.',
Ul='Ulfrir:BAABLgAECn8fAAMHAAkJ0xtuFQCMAgAHAAkJ0xtuFQCMAgAeAAMJMQojbwCCAAAAAA==.Ultradukes:BAAALgADCgcJFQAAAA==.',
Un='Unatural:BAAALgAECgUJBQAAAA==.Unleashed:BAAALgAECgUJCgAAAA==.',
Va='Valarea:BAAALgADCgEJAQAAAA==.Valock:BAAALgAECgYJBwAAAA==.Valris:BAAALgAECgMJBAAAAA==.Vandham:BAAALgADCgEJAQAAAA==.Vanshifty:BAABLgAECn8vAAIKAAkJ4SJWAgBhAwAKAAkJ4SJWAgBhAwAAAA==.',
Ve='Veilf:BAAALgADCgYJDAAAAA==.Velf:BAAALgAECgEJAQAAAA==.Velrus:BAAALgAECgYJDAAAAA==.Venli:BAAALgAECgEJAQAAAA==.Venombite:BAAALgADCgMJAwAAAA==.',
Vi='Viktorax:BAAALgAECgYJCwAAAA==.Virtueozo:BAABLgAECn8aAAIjAAgJEBfIDwA+AgAjAAgJEBfIDwA+AgAAAA==.',
Vo='Volam:BAAALgAECgQJBAAAAA==.',
Wa='Waffle:BAAALgAECgUJDgABLgAECggJGQAHAFAOAA==.Waldhorn:BAAALgAECgYJBgAAAA==.Wangwen:BAAALgADCgIJAgAAAA==.Wargue:BAAALgAECgYJEQAAAA==.',
We='Weebsz:BAAALgADCgQJBAAAAA==.Welindis:BAAALgAECgUJBQABLgAECggJHgAWAOAOAA==.Wetkith:BAAALgADCgUJBQAAAA==.',
Wi='Windrider:BAAALgADCgIJAgAAAA==.Windwraith:BAAALgADCgUJCwAAAA==.Wizzard:BAAALgAECggJFgAAAQ==.',
Xa='Xaiyara:BAAALgADCgUJBQAAAA==.Xandaka:BAAALgADCgQJBAAAAA==.',
Xe='Xephir:BAAALgAECgMJAgAAAA==.',
Xi='Xidied:BAABLgAECn8nAAIGAAkJnR5BAwDLAgAGAAkJnR5BAwDLAgAAAA==.Xilon:BAAALgADCgcJBwABLgAECgkJKwAfAAUhAA==.Xilra:BAABLgAECn8rAAIfAAkJBSHEBACmAgAfAAkJBSHEBACmAgAAAA==.Xilzen:BAAALgAECgUJDQABLgAECgkJKwAfAAUhAA==.Xinia:BAAALgADCgEJAQAAAA==.',
Ye='Yew:BAAALgADCgMJAwAAAA==.',
Yi='Yikers:BAACLgAFFH8IAAIRAAMJoh50FQACAQARAAMJoh50FQACAQAuAAQKfyQAAhEACAnkIf0FAMICABEACAnkIf0FAMICAAAA.',
Yr='Yridai:BAAALgAECgYJCAAAAA==.',
Za='Zarsher:BAAALgADCgIJAgAAAA==.',
Zd='Zdk:BAAALgAECgEJAQABLgAECgYJEgANAAAAAA==.',
Ze='Zeldy:BAABLgAECn8fAAIHAAgJOxiHIADZAQAHAAgJOxiHIADZAQAAAA==.Zenestraza:BAAALgADCgMJAwABLgAECgYJGAAWAMcVAA==.Zenthareal:BAABLgAECn8YAAIWAAYJxxWwPgA+AQAWAAYJxxWwPgA+AQAAAA==.Zeuc:BAAALgADCgMJAwAAAA==.Zeuus:BAAALgADCgMJBAAAAA==.',
Zh='Zhirl:BAAALgAECgcJEQAAAA==.Zhulgarosh:BAAALgADCgUJBQAAAA==.',
Zi='Zillidan:BAAALgAECgEJAQABLgAECgYJEgANAAAAAA==.',
Zm='Zmaster:BAAALgAECgYJEgAAAA==.',
Zo='Zobeast:BAAALgADCgQJBAAAAA==.',
Zr='Zret:BAAALgAECgYJCgABLgAECgYJEgANAAAAAA==.',
Zw='Zwar:BAAALgAECgEJAQABLgAECgYJEgANAAAAAA==.',
['Zö']='Zöey:BAAALgADCgQJBQAAAA==.',
['Åp']='Åpex:BAAALgADCgMJAwAAAA==.',
['Çl']='Çloudz:BAAALgADCgMJAwAAAA==.',
['Ða']='Ðark:BAACLgAFFH8IAAIHAAMJRA9nGACmAAAHAAMJRA9nGACmAAAuAAQKfyYAAgcACQluGgQVAI8CAAcACQluGgQVAI8CAAAA.',
['Ðr']='Ðr:BAABLgAECn8eAAMMAAkJ/Br1IgANAgAMAAcJThr1IgANAgAUAAYJ5hcjFwCYAQAAAA==.',
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
