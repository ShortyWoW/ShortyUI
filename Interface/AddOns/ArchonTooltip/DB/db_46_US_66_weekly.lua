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

local lookup = {'Unknown-Unknown','DemonHunter-Devourer','Warrior-Protection','Paladin-Protection','Shaman-Enhancement','Hunter-BeastMastery','Mage-Frost','Monk-Windwalker','DeathKnight-Unholy','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','DemonHunter-Havoc','DemonHunter-Vengeance','Rogue-Assassination','Warrior-Fury','DeathKnight-Blood','Paladin-Retribution','Hunter-Marksmanship','Warrior-Arms','Priest-Shadow','Priest-Discipline','Priest-Holy','Paladin-Holy','Monk-Mistweaver','Druid-Restoration','Druid-Feral','Druid-Guardian','Hunter-Survival','Mage-Arcane','Shaman-Restoration','Monk-Brewmaster','Shaman-Elemental','Rogue-Subtlety','Mage-Fire','DeathKnight-Frost',}
local provider = {region='US',realm='Dentarg',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abaddôn:BAAALgAECgEJAQABLgAECgEJAQABAAAAAA==.Abelard:BAAALgAECgUJCwAAAA==.',
Ad='Adevourer:BAAALgADCgEJAQAAAA==.',
Ae='Aeeguariar:BAAALgADCgIJAgAAAA==.Aenlorie:BAAALgADCgMJAwABLgAFFAcJDAACAB0NAA==.Aezyndreth:BAAALgADCgQJBQAAAA==.',
Af='Aflickted:BAAALgAECgcJDAAAAA==.',
Ag='Agesilaus:BAAALgADCgcJDwAAAA==.Agesipolis:BAAALgADCgYJEQAAAA==.Aggathon:BAEBLgAECn8bAAIDAAgJ/wsjEgBCAQADAAgJ/wsjEgBCAQAAAA==.',
Ai='Aittuu:BAAALgADCgkJEAABLgAECgcJIwAEAPMkAA==.',
Ak='Akusai:BAAALgAECgMJAwABLgAECgcJGQAFALEIAA==.',
Al='Aldebaran:BAAALgAECgcJBwAAAA==.Aleksandar:BAAALgAECgMJAwAAAA==.',
Am='Amage:BAAALgADCgcJDgAAAA==.Amonk:BAAALgADCgIJAgAAAA==.',
An='Ansur:BAAALgAECgIJAgAAAA==.',
Ar='Aradoria:BAAALgAECgMJAwAAAA==.Arlonar:BAAALgADCgIJAgABLgADCgQJBQABAAAAAA==.Arohgue:BAAALgADCgIJAgAAAA==.',
As='Asenturius:BAAALgADCgUJBQAAAA==.Ashke:BAABLgAECn8YAAIGAAYJlhIEQQBKAQAGAAYJlhIEQQBKAQAAAA==.',
Av='Avarice:BAAALgAECgEJAQABLgAECggJIgAHAEUXAA==.',
Ax='Axetoface:BAAALgADCgYJCAAAAA==.Axetomouth:BAAALgAECgEJAQAAAA==.',
Az='Azraeon:BAAALgAECgYJDgAAAA==.Azurehorn:BAAALgADCgYJBgABLgAECggJDgABAAAAAA==.',
Ba='Badlucklouie:BAAALgAECgYJCgAAAA==.Badpenny:BAAALgADCgYJCwAAAA==.Bajenkas:BAAALgAECgQJBgAAAA==.Balfas:BAAALgADCgcJDAAAAA==.',
Be='Beaupeep:BAABLgAECn8ZAAIFAAcJsQi3DQAqAQAFAAcJsQi3DQAqAQAAAA==.Beepbop:BAAALgAECgEJAwAAAA==.Benedictine:BAABLgAECn8aAAIIAAkJ0RlLBwBUAgAIAAkJ0RlLBwBUAgAAAA==.',
Bi='Bigrick:BAAALgADCgYJBgAAAA==.',
Bo='Boogieman:BAAALgADCgIJAgAAAA==.Boyacky:BAAALgADCgMJAwAAAA==.',
Br='Braiglock:BAAALgAECgYJCgAAAA==.Brambletime:BAAALgADCgQJBAAAAA==.Brigit:BAAALgAECgIJAgAAAA==.',
Bu='Buudha:BAAALgADCgEJAQAAAA==.',
By='Bygz:BAAALgAFFAIJAgABLgAFFAcJFgAJAMMiAA==.',
['Bä']='Bärnowl:BAAALgAECgQJBAAAAA==.',
Ca='Caarjack:BAACLgAFFH8KAAQKAAQJNw3GAwDlAAAKAAMJDQnGAwDlAAALAAMJRg1EIgDhAAAMAAEJ6ASvHABEAAAuAAQKfygABAwACAluFpQUAP4BAAwACAluFpQUAP4BAAsABAktHPQdAE8BAAoAAgnIDqsQAHcAAAAA.Caicedo:BAAALgAECgcJCQAAAA==.Callmemeg:BAAALgAECgUJCAAAAA==.Catadelic:BAABLgAECn8jAAIGAAgJdwpmNwBvAQAGAAgJdwpmNwBvAQAAAA==.',
Ce='Celektra:BAAALgAECgYJCgAAAA==.Celestial:BAABLgAECn8bAAQNAAgJ2g+/HwBUAQANAAgJKg6/HwBUAQAOAAMJphDdHQCCAAAPAAEJWgRs6QArAAAAAA==.',
Ch='Chewmatter:BAABLgAECn8eAAMCAAgJsx+SDwBJAgACAAgJsx+SDwBJAgAQAAEJAABOSwAAAAAAAA==.Chewwbacca:BAAALgAECgUJBQAAAA==.Chud:BAAALgADCggJCAAAAA==.Chyse:BAAALgAECgEJAQAAAA==.',
Ci='Cindroz:BAAALgAECgUJCAAAAA==.',
Cl='Claus:BAAALgADCgQJBQAAAA==.Cleanname:BAABLgAECn8bAAMRAAkJ8hvPAQCCAgARAAkJ8hvPAQCCAgACAAUJaQ6wZQDSAAAAAA==.Clurichaun:BAABLgAECn8eAAISAAcJrgV1CgAfAQASAAcJrgV1CgAfAQAAAA==.',
Cr='Crak:BAAALgADCgUJCgAAAA==.Crusade:BAAALgADCggJCAAAAA==.Crùros:BAAALgAECgYJCwAAAA==.',
Cu='Cucuchara:BAABLgAECn8UAAMTAAYJzBQwPQDNAAATAAQJQBMwPQDNAAADAAIJ+xotOACIAAAAAA==.',
Da='Daemonna:BAAALgAECgYJBgAAAA==.Darkestdude:BAAALgADCgMJAwAAAA==.',
De='Deathdab:BAAALgADCgEJAQAAAA==.Deathphish:BAABLgAECn8cAAIUAAgJWBOJDwB6AQAUAAgJWBOJDwB6AQAAAA==.Demonish:BAAALgAECgIJBAAAAA==.Denntarg:BAAALgAECgQJBwABLgAECgkJJgAVAPIgAA==.Desdemona:BAABLgAECn8ZAAIWAAYJdRCaDQARAQAWAAYJdRCaDQARAQAAAA==.Deshler:BAAALgAECgkJEQAAAA==.',
Di='Dice:BAAALgADCgIJAgAAAA==.Dirtyblonde:BAAALgAECgUJCQAAAA==.Ditlutz:BAABLgAECn8jAAIEAAcJ8yQ8AwBxAgAEAAcJ8yQ8AwBxAgAAAA==.',
Dj='Djskyfallx:BAABLgAECn8UAAIHAAcJoxy4dADpAQAHAAcJoxy4dADpAQAAAA==.',
Do='Dom:BAACLgAFFH8SAAMTAAUJcxdVDABDAQATAAUJcxdVDABDAQAXAAIJaQQHDQBMAAAuAAQKfyAAAhMACAnxH/AYAIQCABMACAnxH/AYAIQCAAAA.Doraf:BAAALgADCgcJDQAAAA==.Dormammu:BAAALgAECgEJAgAAAA==.',
Dr='Druken:BAAALgAECgQJCwAAAA==.Drûid:BAAALgADCgEJAQAAAA==.',
Du='Dumbledore:BAAALgAECgEJAQAAAA==.',
Dw='Dwarfussy:BAABLgAECn8XAAIDAAcJqBT+FQCuAQADAAcJqBT+FQCuAQAAAA==.',
Dy='Dybby:BAAALgAECgcJEwAAAA==.',
El='Elderoth:BAAALgAECgUJCQAAAA==.Eledork:BAAALgADCgMJAwAAAA==.Elrondus:BAAALgAECggJDAAAAA==.',
Em='Emridion:BAAALgAECgYJDwAAAA==.',
En='Endlessnight:BAABLgAECn8hAAIUAAgJexxtBgAzAgAUAAgJexxtBgAzAgAAAA==.',
Ey='Eyeinfection:BAAALgADCgIJBAAAAA==.',
['Eä']='Eärendil:BAAALgADCgUJBQAAAA==.',
Fa='Faearia:BAACLgAFFH8HAAIYAAUJ2QzxDAA6AQAYAAUJ2QzxDAA6AQAuAAQKfyAAAhgACQmnG+UMALUCABgACQmnG+UMALUCAAAA.Faebryn:BAABLgAECn8jAAITAAcJhSTuBgB/AgATAAcJhSTuBgB/AgAAAA==.Faenza:BAAALgADCgkJEAAAAA==.',
Fe='Felmaiden:BAAALgADCgQJBQAAAA==.Fenirean:BAAALgAECgUJCAAAAA==.Fettylock:BAAALgAECgEJBAAAAA==.',
Fi='Fintaylor:BAAALgAECgcJBwAAAA==.',
Fl='Flirts:BAAALgAECgMJBAAAAA==.',
Fo='Foodstamp:BAAALgAECgMJAwAAAA==.Forcas:BAABLgAECn8fAAMQAAYJ8xxsDwCLAQAQAAYJaxtsDwCLAQARAAMJPx2SFwDmAAAAAA==.',
Fr='Frijõle:BAAALgAECgQJBAAAAA==.',
Fu='Furysmite:BAAALgADCgYJCgAAAA==.Fuzebox:BAAALgAECgcJEQAAAA==.',
Ga='Gallifrey:BAABLgAECn8iAAIHAAgJRRetMADeAQAHAAgJRRetMADeAQAAAA==.Gamarrick:BAABLgAECn8iAAIYAAgJxA26FwCBAQAYAAgJxA26FwCBAQAAAA==.Ganyin:BAAALgADCgkJHAAAAA==.Gaul:BAAALgAECgEJAQAAAA==.',
Ge='Germain:BAAALgAECgcJDwAAAA==.',
Gi='Gimick:BAAALgAECgEJAQAAAA==.',
Gn='Gnometzu:BAABLgAECn8mAAIIAAgJURScDwDCAQAIAAgJURScDwDCAQAAAA==.',
Go='Golddicmove:BAAALgAECgMJBAAAAA==.Goth:BAAALgAECgYJCwAAAA==.Gothicc:BAAALgAECgMJAwAAAA==.',
Gr='Greeva:BAAALgADCgcJCAAAAA==.Griever:BAEALgAECgUJDAAAAA==.Grimdrood:BAAALgADCgYJBgAAAA==.',
Gu='Guilladot:BAABLgAECn8bAAIPAAcJhhSSTwA7AQAPAAcJhhSSTwA7AQAAAA==.Guillak:BAABLgAECn8fAAMPAAYJUxVqSABPAQAPAAUJABRqSABPAQANAAQJaRNoMgDuAAAAAA==.Gurdbi:BAAALgAECgEJAQAAAA==.',
Ha='Harafar:BAAALgAECgcJEAAAAA==.Harmonic:BAAALgADCgkJEQABLgADCgkJEAABAAAAAA==.Harxx:BAAALgADCgMJAwAAAA==.Hatka:BAAALgAECgUJCAAAAA==.',
He='Healtards:BAABLgAECn8aAAMZAAkJZwqOEADMAQAZAAkJZwqOEADMAQAaAAYJLgLVVwDWAAAAAA==.Hematose:BAAALgADCgQJBAABLgAECgUJCQABAAAAAA==.',
Hi='Hitmonleë:BAAALgAECgIJAgABLgAECgYJCQABAAAAAA==.',
Ho='Holyfyer:BAAALgAECgMJAwAAAA==.Holyshift:BAABLgAECn8ZAAIbAAgJ8RpvGABPAgAbAAgJ8RpvGABPAgAAAA==.Homgal:BAAALgAECgYJDAAAAA==.Hoofingit:BAAALgADCgkJLQAAAA==.',
Hu='Hullstorm:BAAALgADCgcJCgAAAA==.Hume:BAAALgAECgMJAgAAAA==.',
Ib='Ibull:BAAALgADCgEJAQAAAA==.',
Ic='Icyifu:BAABLgAECn8UAAIcAAgJIx6RBQC1AgAcAAgJIx6RBQC1AgAAAA==.',
If='Iffy:BAAALgAECggJDgAAAA==.',
Ih='Ihys:BAAALgADCgEJAQAAAA==.',
Il='Ilian:BAABLgAECn8WAAIIAAkJpRpsBQCGAgAIAAkJpRpsBQCGAgAAAA==.',
In='Ingward:BAAALgAECgEJAQAAAA==.Iniquity:BAABLgAECn8jAAMaAAgJLhf3IQDUAQAaAAgJLhf3IQDUAQAYAAUJExlRKQD9AAAAAA==.',
Ja='Jabiso:BAAALgAECgEJAQAAAA==.Jackthebeast:BAABLgAFFH8LAAMGAAMJ+hoRIAAWAQAGAAMJ+hoRIAAWAQAWAAEJKAW5KwBDAAAAAA==.Jaida:BAABLgAECn8fAAICAAkJrw3ZXADnAAACAAkJrw3ZXADnAAAAAA==.Jamesxd:BAAALgAECgEJAQABLgAECggJGQAdAKogAA==.Jang:BAAALgADCgcJBwAAAA==.',
Jd='Jdmagisdruid:BAABLgAECn8jAAMeAAcJNybtAQCoAgAeAAcJNybtAQCoAgAfAAEJ5yOQKQBUAAAAAA==.Jdmagisrogue:BAAALgADCgMJAwABLgAECgcJIwAeADcmAA==.',
Je='Jeanne:BAABLgAECn8dAAMYAAcJ5AbFKAABAQAYAAcJ5AbFKAABAQAaAAYJ7wU0MwC4AAAAAA==.Jedoniah:BAABLgAECn8jAAIVAAcJVyUSDwCEAgAVAAcJVyUSDwCEAgAAAA==.Jeffrey:BAAALgAECgMJBgAAAA==.',
Jo='Jorhmont:BAAALgAECgYJBgAAAA==.Jowyy:BAAALgADCgEJAQAAAA==.',
Ju='Juan:BAABLgAECn8XAAIdAAYJkxTLLgBnAQAdAAYJkxTLLgBnAQAAAA==.Jumbo:BAABLgAECn8dAAITAAcJ2hvDFADFAQATAAcJ2hvDFADFAQAAAA==.Jumpeor:BAACLgAFFH8UAAIVAAYJRCGtAgDzAQAVAAYJRCGtAgDzAQAuAAQKfxgAAhUACQkQIuYDAJADABUACQkQIuYDAJADAAAA.',
Ka='Kael:BAAALgAECgMJAwAAAA==.Kassey:BAAALgADCgYJCwAAAA==.Katacola:BAACLgAFFH8jAAIdAAgJ5xycAAC9AgAdAAgJ5xycAAC9AgAuAAQKfywAAh0ACQlvJswCAGoDAB0ACQlvJswCAGoDAAAA.Kathloken:BAAALgADCgYJCQAAAA==.',
Ke='Kenaf:BAAALgADCgEJAQAAAA==.Kevesebal:BAABLgAECn8eAAMPAAkJWyJeBQBmAwAPAAkJWyJeBQBmAwANAAEJAAA+cAA2AAAAAA==.',
Kh='Khronic:BAAALgAECgYJEgAAAA==.',
Ki='Kikiliki:BAAALgAECgcJEQAAAA==.Kilthgar:BAABLgAECn8iAAIEAAcJ6BizCQCqAQAEAAcJ6BizCQCqAQAAAA==.',
Ko='Koa:BAABLgAECn8YAAIdAAcJuRQTRgCJAQAdAAcJuRQTRgCJAQAAAA==.Kobeni:BAAALgAECgYJEAAAAA==.Kodiak:BAAALgAECgYJDAAAAA==.Kolar:BAAALgAECgYJDAAAAA==.Koravellia:BAAALgAECgEJBAAAAA==.Kord:BAAALgADCgcJCgAAAA==.',
Kr='Kraph:BAAALgAECgIJAwAAAA==.Krillin:BAAALgAECgcJEgAAAA==.',
Ku='Kurau:BAABLgAECn8ZAAIgAAcJYgw6FQBqAQAgAAcJYgw6FQBqAQAAAA==.',
Ky='Kyrinra:BAAALgAECgQJBAAAAA==.',
La='Lacie:BAAALgAECgYJEQAAAA==.',
Le='Leela:BAAALgADCgMJAwABLgAECggJGgAHAAQNAA==.',
Li='Littletoot:BAAALgADCgUJBwAAAA==.',
Lo='Lockybleier:BAAALgADCgYJDAAAAA==.Logìc:BAAALgADCgIJAgAAAA==.Lokiel:BAABLgAECn8eAAIbAAgJSBRQEgAEAgAbAAgJSBRQEgAEAgAAAA==.Lonescyther:BAAALgADCgMJAwAAAA==.Lorithen:BAAALgADCgYJBgAAAA==.',
Lu='Lunula:BAABLgAECn8tAAIfAAgJrRunBAAmAgAfAAgJrRunBAAmAgAAAA==.Luxörd:BAABLgAECn8iAAIbAAgJRh9nBwChAgAbAAgJRh9nBwChAgAAAA==.',
Ly='Lyaenna:BAAALgAECggJEwAAAA==.Lydius:BAABLgAECn8jAAIdAAgJsRBBKgCCAQAdAAgJsRBBKgCCAQAAAA==.Lymn:BAAALgADCgQJBAAAAA==.',
Ma='Macguffins:BAAALgAECgQJBAAAAA==.Maddex:BAAALgAECgMJAwAAAA==.Madeng:BAAALgAECgUJCwABLgAECgYJDAABAAAAAA==.Mageshir:BAABLgAECn8bAAMHAAgJlw8nPgCtAQAHAAgJUA8nPgCtAQAhAAEJ8wo0DQA9AAAAAA==.Maletherion:BAABLgAECn8cAAIWAAYJaCEDBgC9AQAWAAYJaCEDBgC9AQAAAA==.Malhoon:BAAALgADCgQJBAAAAA==.Maltherion:BAABLgAECn8cAAIQAAgJFx4LCQD+AQAQAAgJFx4LCQD+AQAAAA==.Maolestromz:BAAALgAECgcJAwAAAA==.Margareetah:BAAALgAECgEJAQAAAA==.Marisal:BAAALgADCgYJBgAAAA==.Mayaeyes:BAAALgAFFAIJAgABLgAFFAcJFgAJAMMiAA==.',
Mi='Mikokahuna:BAAALgAECgUJCQAAAA==.Minglo:BAAALgAECgUJCAAAAA==.Minireaper:BAAALgAECgUJDQAAAA==.Mistaeko:BAAALgADCgMJAwAAAA==.',
Mj='Mjolnir:BAABLgAECn8jAAIVAAcJkiPuEwBaAgAVAAcJkiPuEwBaAgAAAA==.',
Mo='Moggren:BAAALgAECggJDgAAAA==.Moirbidia:BAAALgADCgcJCgAAAA==.Mongke:BAAALgADCgYJBwAAAA==.',
['Mî']='Mîsh:BAAALgAECgMJAwAAAA==.',
Na='Namôr:BAAALgADCgYJCwAAAA==.Narzel:BAAALgAECgQJDAAAAA==.Nazgul:BAAALgAFFAEJAQAAAA==.',
Ne='Necronias:BAAALgAECgYJEAAAAA==.Nehen:BAAALgAECgIJAgABLgAECggJHgAHAB0XAA==.Nelelish:BAAALgAECgEJAQAAAA==.Nequins:BAABLgAECn8iAAIdAAgJbR1bDgBrAgAdAAgJbR1bDgBrAgAAAA==.Nequinss:BAABLgAECn8cAAIiAAgJbCP5AgAnAwAiAAgJbCP5AgAnAwABLgAECggJIgAdAG0dAA==.Nevermore:BAAALgAECgUJBwAAAA==.',
Ni='Nicabar:BAABLgAECn8nAAIPAAgJlwqvRABbAQAPAAgJlwqvRABbAQAAAA==.Nitemare:BAAALgADCgcJCAAAAA==.',
No='Noaman:BAAALgAECgEJAwAAAA==.Noapandman:BAAALgAECgEJAQAAAA==.Noie:BAAALgAECgMJBAAAAA==.Nooamann:BAAALgADCgEJAQAAAA==.Noodles:BAAALgAECgYJBgAAAA==.Normademon:BAAALgAECgEJAQAAAA==.Noztalgia:BAAALgAECgcJEQAAAA==.',
Nt='Nthx:BAAALgADCgMJAwAAAA==.',
Nu='Nullbringer:BAAALgADCgEJAQAAAA==.',
Nx='Nxttuesday:BAAALgADCgUJBQAAAA==.',
['Nå']='Nåndo:BAAALgAECgEJAQAAAA==.',
['Në']='Nëklaüs:BAAALgAECgYJEgAAAA==.',
Oa='Oakily:BAABLgAECn8WAAIdAAYJ9AkxcgD/AAAdAAYJ9AkxcgD/AAAAAA==.',
Od='Oditte:BAAALgADCgYJBgAAAA==.',
Oi='Oilliphéist:BAAALgAECgQJCQAAAA==.',
Om='Omegatanker:BAABLgAECn8mAAIjAAkJ7yVuAABoAwAjAAkJ7yVuAABoAwAAAA==.',
Or='Ornot:BAABLgAECn8ZAAIiAAgJUA5bMQBKAQAiAAgJUA5bMQBKAQAAAA==.',
Os='Oshdruid:BAABLgAECn8ZAAIdAAgJqiDODwBYAgAdAAgJqiDODwBYAgAAAA==.',
Ow='Owo:BAAALgADCgYJDAAAAA==.',
Pa='Pacfritanda:BAAALgADCgQJBAAAAA==.Pandurbear:BAAALgADCgYJCwAAAA==.Paws:BAAALgAECgEJAQAAAA==.',
Pe='Pequin:BAAALgAECgYJBgABLgAECggJIgAdAG0dAA==.Pergatory:BAABLgAECn8aAAIYAAYJ5glBKAAFAQAYAAYJ5glBKAAFAQAAAA==.',
Ph='Pho:BAAALgAFFAIJAgAAAA==.Phuule:BAAALgADCgQJCQAAAA==.Phuulmojo:BAAALgADCgIJAgAAAA==.',
Pi='Piruletras:BAAALgAECgYJDwAAAA==.',
Pr='Priechwhirl:BAABLgAECn8fAAIXAAkJshUgBABNAgAXAAkJshUgBABNAgAAAA==.Provost:BAABLgAECn8dAAIVAAgJBCGEDgCKAgAVAAgJBCGEDgCKAgAAAA==.',
Pu='Pumpkinpîe:BAAALgAECgIJAwAAAA==.',
Qu='Quanx:BAABLgAECn8VAAMkAAcJQxX8IwA1AQAFAAYJZxYnEgCUAQAkAAcJVxP8IwA1AQAAAA==.',
Ra='Radiantmist:BAAALgADCgMJAwABLgAECgEJAQABAAAAAA==.Rakiko:BAAALgAFFAEJAQABLgAFFAcJFgAJAMMiAA==.Raydora:BAAALgADCgQJBwAAAA==.',
Re='Rednecklock:BAAALgADCgEJAQAAAA==.Remulüs:BAABLgAECn8dAAQCAAgJXxoJFAAcAgACAAgJXxoJFAAcAgARAAMJ3AP1FwBgAAAQAAEJAADAbwA1AAAAAA==.',
Ri='Riah:BAAALgADCgkJCQAAAA==.Rickyböbby:BAAALgADCgQJBQAAAA==.Riilyn:BAABLgAECn8nAAIlAAgJ3hn7CQAAAgAlAAgJ3hn7CQAAAgAAAA==.Riolu:BAAALgAECgEJAQAAAA==.',
Ru='Ruith:BAAALgAECgUJCAAAAA==.',
['Rø']='Røean:BAAALgAECgYJCAAAAA==.',
Sa='Saina:BAAALgAECgEJAQAAAA==.Satanshelpa:BAAALgADCgUJBQAAAA==.',
Sb='Sb:BAAALgADCgUJBQAAAA==.',
Sc='Scalebeard:BAABLgAECn8aAAQMAAgJ9gmQFAD4AAAMAAgJ9gmQFAD4AAAKAAUJvhnmCwDWAAALAAEJ7AxCYwAwAAAAAA==.Scecretzs:BAAALgAECgQJBwAAAA==.Screnry:BAAALgAECgEJAQAAAA==.',
Se='Secretz:BAAALgADCgYJCgAAAA==.Sedrelari:BAABLgAECn8aAAIgAAYJih/2DAD7AQAgAAYJih/2DAD7AQAAAA==.Seizethesol:BAAALgADCgIJAgAAAA==.Sepsis:BAAALgAECgYJCgAAAA==.Sesamo:BAACLgAFFH8RAAIVAAQJLBiwFABVAQAVAAQJLBiwFABVAQAuAAQKfycAAhUACQl/IzgGAGoDABUACQl/IzgGAGoDAAAA.',
Sh='Shocks:BAAALgAECgEJAgAAAA==.Shroomin:BAABLgAECn8aAAIkAAcJ1CB9EwC8AQAkAAcJ1CB9EwC8AQAAAA==.',
Si='Sixseven:BAAALgADCgkJGQAAAA==.',
Sk='Skass:BAAALgADCgcJEAAAAA==.',
Sl='Slok:BAAALgADCgcJCwAAAA==.Slyndara:BAAALgAECgYJEAAAAA==.',
Sm='Smarthen:BAABLgAECn8eAAQHAAgJHRezLADvAQAHAAgJHRezLADvAQAmAAIJJwFbEAAzAAAhAAEJPgEQIwANAAAAAA==.',
Sn='Sniffums:BAABLgAECn8aAAIgAAkJEhBZCQAQAgAgAAkJEhBZCQAQAgAAAA==.',
So='Sokto:BAAALgAECgUJBQAAAA==.Solarian:BAABLgAECn8fAAICAAYJ3RBsVQD7AAACAAYJ3RBsVQD7AAAAAA==.Soule:BAAALgADCgkJKwAAAA==.',
Sp='Spacewalrus:BAAALgADCgIJAgABLgAECggJIgAbAEYfAA==.',
Sq='Squirtlë:BAAALgADCgcJBwABLgAECgYJCQABAAAAAA==.',
St='Startle:BAAALgADCgcJGgAAAA==.Steelbreeze:BAAALgAECgMJBAAAAA==.Stoutbringer:BAAALgADCgkJIwAAAA==.Størmzkurse:BAAALgAECgEJAQAAAA==.',
Sy='Sylvaedir:BAAALgADCgcJBgAAAA==.Systran:BAAALgADCgYJBwAAAA==.',
Ta='Tailrazen:BAAALgAECgUJBwAAAA==.Talyn:BAABLgAECn8aAAIHAAgJBA1DRwCRAQAHAAgJBA1DRwCRAQAAAA==.Taomi:BAABLgAECn8jAAIiAAcJRhbEHgC8AQAiAAcJRhbEHgC8AQAAAA==.Taylorswift:BAAALgAECgkJDQAAAA==.',
Te='Tengri:BAAALgAECgIJBQAAAA==.Tenspeed:BAABLgAECn8ZAAICAAcJ7ROeMwBnAQACAAcJ7ROeMwBnAQAAAA==.',
Th='Thire:BAAALgAECgYJCgAAAA==.Thisrogue:BAAALgAECgEJAQAAAA==.Throwglaive:BAAALgAECgQJBAABLgAFFAcJFgAJAMMiAA==.',
Ti='Tidereign:BAAALgAECgcJDgAAAA==.Timka:BAAALgAECgYJEwAAAA==.Tiriell:BAABLgAECn8mAAIVAAkJ8iCkBwDWAgAVAAkJ8iCkBwDWAgAAAA==.',
Tr='Tracixs:BAAALgAECgEJAQAAAA==.Trenity:BAAALgADCgIJAgAAAA==.Trinanah:BAACLgAFFH8JAAIYAAQJqAV1DwAYAQAYAAQJqAV1DwAYAQAuAAQKfygAAhgACAnnEssbAP4BABgACAnnEssbAP4BAAAA.',
['Tô']='Tôrunn:BAABLgAECn8jAAIEAAgJLg00EgAdAQAEAAgJLg00EgAdAQAAAA==.',
Un='Undeadots:BAAALgAECgEJAQAAAA==.',
Ut='Uthandric:BAAALgADCgIJAgABLgAECgcJIwAEAPMkAA==.',
Va='Vallock:BAABLgAECn8XAAINAAYJXAYEEgDGAAANAAYJXAYEEgDGAAAAAA==.Valmyr:BAAALgADCgEJAQAAAA==.Valor:BAAALgADCggJCAABLgAECggJHQAVAAQhAA==.Vanarn:BAAALgADCgQJBQAAAA==.',
Ve='Velidori:BAAALgAECgEJAQAAAA==.Velrez:BAAALgAECgQJBgAAAA==.Vengence:BAAALgADCgYJBwAAAA==.Venusäur:BAAALgAECgYJCQAAAA==.',
Vi='Viital:BAAALgAECgMJBQAAAA==.',
Vo='Voidblade:BAAALgAECgIJBQAAAA==.Voidbourne:BAAALgAECgMJBgAAAA==.',
Wa='Wammus:BAAALgAECgYJCgAAAA==.Warglaive:BAAALgADCgMJBQAAAA==.Wayden:BAAALgAECggJEwAAAA==.Waz:BAAALgAECgQJBAAAAA==.',
We='Wef:BAABLgAECn8dAAIGAAcJ5QuTPQBXAQAGAAcJ5QuTPQBXAQAAAA==.Welath:BAAALgAECggJCAAAAA==.',
Wh='Whobit:BAAALgADCgUJBQAAAA==.',
Wi='Wimbly:BAAALgAECgMJAwAAAA==.Windwalker:BAABLgAECn8gAAIIAAcJliBiCAA7AgAIAAcJliBiCAA7AgAAAA==.Wings:BAAALgAECggJDgAAAA==.Wintel:BAAALgADCgQJBAAAAA==.Wizzinmapant:BAAALgAECgUJCgAAAA==.',
Xa='Xanza:BAAALgADCgYJCAAAAA==.',
Yl='Ylva:BAAALgADCgcJCAAAAA==.',
Yo='Yo:BAABLgAECn8UAAIVAAUJKw7OggDmAAAVAAUJKw7OggDmAAAAAA==.Yozomiria:BAAALgADCgYJDgAAAA==.',
Ys='Yste:BAAALgADCgYJBQABLgADCgYJDgABAAAAAA==.',
Yu='Yummybuttons:BAAALgAECgQJBAAAAA==.',
Za='Zandk:BAAALgADCgkJEAABLgAFFAUJCwALAOYHAA==.Zanju:BAAALgAECgQJDAAAAA==.Zanvoker:BAACLgAFFH8LAAILAAUJ5ge5HAACAQALAAUJ5ge5HAACAQAuAAQKfxsAAgsABwm5GKEWACICAAsABwm5GKEWACICAAAA.',
Ze='Zerc:BAABLgAECn80AAInAAkJLyCdAADeAgAnAAkJLyCdAADeAgAAAA==.',
Zi='Zinkie:BAABLgAECn8WAAINAAYJABY6CgAyAQANAAYJABY6CgAyAQAAAA==.',
Zo='Zorttok:BAAALgAECgMJBgAAAA==.',
Zy='Zyp:BAAALgADCgMJAwAAAA==.',
['Æn']='Ænlora:BAACLgAFFH8MAAICAAYJHQ2ZCwB5AQACAAYJHQ2ZCwB5AQAuAAQKfxcAAgIACQmPIkMUAN4CAAIACQmPIkMUAN4CAAAA.',
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
