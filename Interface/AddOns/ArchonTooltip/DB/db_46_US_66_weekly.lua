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

local lookup = {'Unknown-Unknown','DemonHunter-Devourer','Warrior-Protection','Paladin-Protection','Shaman-Enhancement','Mage-Frost','Monk-Windwalker','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Hunter-BeastMastery','Warlock-Destruction','Warlock-Affliction','DemonHunter-Vengeance','Rogue-Assassination','Warrior-Fury','DeathKnight-Blood','Paladin-Retribution','Hunter-Marksmanship','Warrior-Arms','Priest-Shadow','DemonHunter-Havoc','Warlock-Demonology','Priest-Discipline','Priest-Holy','Paladin-Holy','Druid-Feral','Druid-Guardian','Druid-Restoration','Hunter-Survival','Shaman-Restoration','Monk-Brewmaster','Rogue-Subtlety','Shaman-Elemental','Mage-Fire','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Frost',}
local provider = {region='US',realm='Dentarg',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abaddôn:BAAALgAECgEJAQABLgAECgEJAQABAAAAAA==.Abelard:BAAALgAECgUJCwAAAA==.',
Ae='Aeeguariar:BAAALgADCgIJAgAAAA==.Aenlorie:BAAALgADCgMJAwABLgAFFAYJCgACAPYPAA==.Aezyndreth:BAAALgADCgQJBQAAAA==.',
Af='Aflickted:BAAALgAECgYJCgAAAA==.',
Ag='Agesilaus:BAAALgADCgcJDAAAAA==.Agesipolis:BAAALgADCgUJCwAAAA==.Aggathon:BAEBLgAECn8bAAIDAAgJ/wt+DQBIAQADAAgJ/wt+DQBIAQAAAA==.',
Ai='Aittuu:BAAALgADCgkJEAABLgAECgYJHAAEAJ0kAA==.',
Ak='Akusai:BAAALgADCgcJDQABLgAECgcJGQAFALEIAA==.',
Al='Aldebaran:BAAALgAECgYJBgAAAA==.Aleksandar:BAAALgAECgMJAwAAAA==.',
Am='Amage:BAAALgADCgcJDgAAAA==.Amonk:BAAALgADCgIJAgAAAA==.',
An='Ansur:BAAALgAECgIJAgAAAA==.',
Ar='Aradoria:BAAALgAECgMJAwAAAA==.Arlonar:BAAALgADCgIJAgABLgADCgQJBQABAAAAAA==.Arohgue:BAAALgADCgIJAgAAAA==.',
As='Asenturius:BAAALgADCgUJBQAAAA==.Ashke:BAAALgAECgYJEgAAAA==.',
Av='Avarice:BAAALgAECgEJAQABLgAECggJIgAGAEUXAA==.',
Ax='Axetoface:BAAALgADCgYJCAAAAA==.',
Az='Azraeon:BAAALgAECgUJCAAAAA==.Azurehorn:BAAALgADCgYJBgABLgAECggJDQABAAAAAA==.',
Ba='Badlucklouie:BAAALgAECgYJCgAAAA==.Badpenny:BAAALgADCgYJCwAAAA==.Bajenkas:BAAALgAECgQJBgAAAA==.Balfas:BAAALgADCgcJDAAAAA==.',
Be='Beaupeep:BAABLgAECn8ZAAIFAAcJsQhcCgA/AQAFAAcJsQhcCgA/AQAAAA==.Beepbop:BAAALgAECgEJAgAAAA==.Benedictine:BAABLgAECn8YAAIHAAgJiRc/CQDmAQAHAAgJiRc/CQDmAQAAAA==.',
Bi='Bigrick:BAAALgADCgYJBgAAAA==.',
Bo='Boyacky:BAAALgADCgMJAwAAAA==.',
Br='Braiglock:BAAALgAECgYJCgAAAA==.Brambletime:BAAALgADCgQJBAAAAA==.Brigit:BAAALgAECgIJAgAAAA==.',
Bu='Buudha:BAAALgADCgEJAQAAAA==.',
['Bä']='Bärnowl:BAAALgAECgQJBAAAAA==.',
Ca='Caarjack:BAACLgAFFH8GAAMIAAMJiA2UHwCiAAAIAAIJmRCUHwCiAAAJAAEJZQdABgBMAAAuAAQKfygABAoACAluFpEUAP4BAAoACAluFpEUAP4BAAgABAktHOoVAE8BAAkAAgnIDlsNAH0AAAAA.Caicedo:BAAALgAECgYJBwAAAA==.Callmemeg:BAAALgAECgQJBwAAAA==.Catadelic:BAABLgAECn8bAAILAAgJSAUrPwAZAQALAAgJSAUrPwAZAQAAAA==.',
Ce='Celektra:BAAALgAECgYJCgAAAA==.Celestial:BAABLgAECn8WAAMMAAcJVA/DHwBUAQAMAAcJXA3DHwBUAQANAAMJphCfCgCIAAAAAA==.',
Ch='Chewmatter:BAABLgAECn8WAAICAAcJBiCoGwCOAQACAAcJBiCoGwCOAQAAAA==.Chewwbacca:BAAALgAECgUJBQAAAA==.Chud:BAAALgADCggJCAAAAA==.Chyse:BAAALgADCgIJAgAAAA==.',
Ci='Cindroz:BAAALgAECgQJBwAAAA==.',
Cl='Claus:BAAALgADCgQJBQAAAA==.Cleanname:BAABLgAECn8ZAAMOAAgJNxswAgAtAgAOAAgJNxswAgAtAgACAAUJaQ5jWQCcAAAAAA==.Clurichaun:BAABLgAECn8WAAIPAAYJlwW4CQDxAAAPAAYJlwW4CQDxAAAAAA==.',
Cr='Crak:BAAALgADCgUJCgAAAA==.Crusade:BAAALgADCggJCAAAAA==.Crùros:BAAALgAECgYJCwAAAA==.',
Cu='Cucuchara:BAABLgAECn8UAAMQAAYJzBR/LwDVAAAQAAQJQBN/LwDVAAADAAIJ+xoxOACIAAAAAA==.',
Da='Daemonna:BAAALgAECgYJBgAAAA==.Darkestdude:BAAALgADCgMJAwAAAA==.',
De='Deathdab:BAAALgADCgEJAQAAAA==.Deathphish:BAABLgAECn8UAAIRAAgJgRLEDABDAQARAAgJgRLEDABDAQAAAA==.Demonish:BAAALgAECgIJBAAAAA==.Denntarg:BAAALgAECgQJBwABLgAECgkJIAASAGEgAA==.Desdemona:BAABLgAECn8VAAITAAYJKwxwDAAHAQATAAYJKwxwDAAHAQAAAA==.Deshler:BAAALgAECgcJCgAAAA==.',
Di='Dice:BAAALgADCgIJAgAAAA==.Dirtyblonde:BAAALgAECgUJCQAAAA==.Ditlutz:BAABLgAECn8cAAIEAAYJnSRdBAAGAgAEAAYJnSRdBAAGAgAAAA==.',
Dj='Djskyfallx:BAABLgAECn8UAAIGAAcJoxy7dADpAQAGAAcJoxy7dADpAQAAAA==.',
Do='Dom:BAACLgAFFH8NAAMQAAUJIxIlEAAFAQAQAAUJqxElEAAFAQAUAAIJaQQEDQBMAAAuAAQKfyAAAhAACAnxH/MYAIQCABAACAnxH/MYAIQCAAAA.Doraf:BAAALgADCgcJDQAAAA==.Dormammu:BAAALgAECgEJAQAAAA==.',
Dr='Druken:BAAALgAECgQJCwAAAA==.Drûid:BAAALgADCgEJAQAAAA==.',
Du='Dumbledore:BAAALgAECgEJAQAAAA==.',
Dw='Dwarfussy:BAAALgAECgYJEAAAAA==.',
Dy='Dybby:BAAALgAECgcJDgAAAA==.',
El='Elderoth:BAAALgAECgQJBwAAAA==.Eledork:BAAALgADCgMJAwAAAA==.Elrondus:BAAALgAECggJDAAAAA==.',
Em='Emridion:BAAALgAECgYJDwAAAA==.',
En='Endlessnight:BAABLgAECn8aAAIRAAcJ6hz8BADqAQARAAcJ6hz8BADqAQAAAA==.',
Ey='Eyeinfection:BAAALgADCgIJBAAAAA==.',
['Eä']='Eärendil:BAAALgADCgUJBQAAAA==.',
Fa='Faearia:BAACLgAFFH8HAAIVAAUJ2QwkCAA/AQAVAAUJ2QwkCAA/AQAuAAQKfyAAAhUACQmnG+MMALUCABUACQmnG+MMALUCAAAA.Faebryn:BAABLgAECn8cAAIQAAYJeCGYCwDyAQAQAAYJeCGYCwDyAQAAAA==.Faenza:BAAALgADCgkJEAAAAA==.',
Fe='Felmaiden:BAAALgADCgQJBQAAAA==.Fenirean:BAAALgAECgQJBwAAAA==.Fettylock:BAAALgAECgEJAwAAAA==.',
Fi='Fintaylor:BAAALgAECgcJBwAAAA==.',
Fl='Flirts:BAAALgAECgEJAQAAAA==.',
Fo='Foodstamp:BAAALgAECgMJAwAAAA==.Forcas:BAABLgAECn8ZAAMWAAYJ8RzwCwB+AQAWAAYJZxvwCwB+AQAOAAMJPx2SFwDlAAAAAA==.',
Fr='Frijõle:BAAALgAECgQJBAAAAA==.',
Fu='Furysmite:BAAALgADCgYJCgAAAA==.Fuzebox:BAAALgAECgcJEQAAAA==.',
Ga='Gallifrey:BAABLgAECn8iAAIGAAgJRRd0IQDlAQAGAAgJRRd0IQDlAQAAAA==.Gamarrick:BAABLgAECn8aAAIVAAYJVRAmGgAtAQAVAAYJVRAmGgAtAQAAAA==.Ganyin:BAAALgADCgkJGgAAAA==.',
Ge='Germain:BAAALgAECgcJDwAAAA==.',
Gi='Gimick:BAAALgAECgEJAQAAAA==.',
Gn='Gnometzu:BAABLgAECn8eAAIHAAgJZRNODACyAQAHAAgJZRNODACyAQAAAA==.',
Go='Golddicmove:BAAALgAECgEJAQAAAA==.Goth:BAAALgAECgYJBgAAAA==.Gothicc:BAAALgAECgMJAwAAAA==.',
Gr='Greeva:BAAALgADCgcJCAAAAA==.Griever:BAEALgAECgQJBwAAAA==.Grimdrood:BAAALgADCgYJBgAAAA==.',
Gu='Guilladot:BAABLgAECn8bAAIXAAcJhhROOwBBAQAXAAcJhhROOwBBAQAAAA==.Guillak:BAABLgAECn8ZAAMXAAYJABR2OQBHAQAXAAUJeRJ2OQBHAQAMAAQJZxNpMgDuAAAAAA==.',
Ha='Harafar:BAAALgAECgcJEAAAAA==.Harmonic:BAAALgADCgkJCQABLgADCgkJEAABAAAAAA==.Harxx:BAAALgADCgMJAwAAAA==.Hatka:BAAALgAECgQJBwAAAA==.',
He='Healtards:BAABLgAECn8YAAMYAAgJxQobEwBjAQAYAAgJxQobEwBjAQAZAAYJLgLMVwDWAAAAAA==.Hematose:BAAALgADCgQJBAAAAA==.',
Hi='Hitmonleë:BAAALgAECgIJAgABLgAECgUJBgABAAAAAA==.',
Ho='Holyfyer:BAAALgAECgMJAwAAAA==.Holyshift:BAABLgAECn8ZAAIaAAgJ8BpzGABPAgAaAAgJ8BpzGABPAgAAAA==.Homgal:BAAALgAECgIJAgAAAA==.Hoofingit:BAAALgADCgkJJgAAAA==.',
Hu='Hullstorm:BAAALgADCgcJCgAAAA==.Hume:BAAALgAECgMJAgAAAA==.',
Ic='Icyifu:BAAALgAECgcJDgAAAA==.',
If='Iffy:BAAALgAECgYJDAAAAA==.',
Ih='Ihys:BAAALgADCgEJAQAAAA==.',
Il='Ilian:BAAALgAECgkJDwAAAA==.',
In='Ingward:BAAALgAECgEJAQAAAA==.Iniquity:BAABLgAECn8dAAMZAAgJLhfPDgC2AQAZAAgJLhfPDgC2AQAVAAUJwQ9YPAAQAQAAAA==.',
Ja='Jabiso:BAAALgAECgEJAQAAAA==.Jackthebeast:BAABLgAFFH8HAAMLAAIJcBbtEwC0AAALAAIJcBbtEwC0AAATAAEJKAWuKwBDAAAAAA==.Jaida:BAABLgAECn8dAAICAAgJxQsHcQBRAQACAAgJxQsHcQBRAQAAAA==.Jang:BAAALgADCgcJBwAAAA==.',
Jd='Jdmagisdruid:BAABLgAECn8cAAMbAAYJFCbEAgA2AgAbAAYJFCbEAgA2AgAcAAEJ5yOOKQBUAAAAAA==.Jdmagisrogue:BAAALgADCgMJAwABLgAECgYJHAAbABQmAA==.',
Je='Jeanne:BAABLgAECn8WAAMVAAYJfwdAOwAZAQAVAAYJfwdAOwAZAQAZAAYJ7wVtKAC6AAAAAA==.Jedoniah:BAABLgAECn8cAAISAAYJUCYnEgApAgASAAYJUCYnEgApAgAAAA==.Jeffrey:BAAALgAECgIJAwAAAA==.',
Jo='Jorhmont:BAAALgADCgkJHwAAAA==.Jowyy:BAAALgADCgEJAQAAAA==.',
Ju='Juan:BAAALgAECgYJEwAAAA==.Jumbo:BAABLgAECn8WAAIQAAYJghuGGQBkAQAQAAYJghuGGQBkAQAAAA==.Jumpeor:BAACLgAFFH8TAAISAAYJRCHtAAAFAgASAAYJRCHtAAAFAgAuAAQKfxgAAhIACQkQIugDAJADABIACQkQIugDAJADAAAA.',
Ka='Kassey:BAAALgADCgYJCwAAAA==.Katacola:BAACLgAFFH8bAAIdAAcJMB78AABQAgAdAAcJMB78AABQAgAuAAQKfyoAAh0ACQlvJswCAGoDAB0ACQlvJswCAGoDAAAA.Kathloken:BAAALgADCgYJCQAAAA==.',
Ke='Kenaf:BAAALgADCgEJAQAAAA==.Kevesebal:BAABLgAECn8dAAMXAAkJWyJfBQBmAwAXAAkJWyJfBQBmAwAMAAEJAAA+cAA2AAAAAA==.',
Kh='Khronic:BAAALgAECgUJDAAAAA==.',
Ki='Kikiliki:BAAALgAECgYJEAAAAA==.Kilthgar:BAABLgAECn8bAAIEAAYJExiDCgBbAQAEAAYJExiDCgBbAQAAAA==.',
Ko='Koa:BAAALgAECgYJEQAAAA==.Kobeni:BAAALgAECgYJEAAAAA==.Kodiak:BAAALgAECgYJDAAAAA==.Kolar:BAAALgAECgYJCwAAAA==.Koravellia:BAAALgAECgEJBAAAAA==.Kord:BAAALgADCgMJAwAAAA==.',
Kr='Kraph:BAAALgAECgIJAwAAAA==.Krillin:BAAALgAECgcJEgAAAA==.',
Ku='Kurau:BAABLgAECn8XAAIeAAcJQQxYEgBBAQAeAAcJQQxYEgBBAQAAAA==.',
Ky='Kyrinra:BAAALgAECgQJBAAAAA==.',
La='Lacie:BAAALgAECgYJDQAAAA==.',
Le='Leela:BAAALgADCgMJAwABLgAECggJFQAGACcKAA==.',
Li='Littletoot:BAAALgADCgUJBwAAAA==.',
Lo='Logìc:BAAALgADCgIJAgAAAA==.Lokiel:BAABLgAECn8WAAIaAAgJlg/GEwC4AQAaAAgJlg/GEwC4AQAAAA==.Lonescyther:BAAALgADCgMJAwAAAA==.Lorithen:BAAALgADCgYJBgAAAA==.',
Lu='Lunula:BAABLgAECn8lAAIcAAgJKRtTAwARAgAcAAgJKRtTAwARAgAAAA==.Luxörd:BAABLgAECn8aAAIaAAYJSCMeFgBgAgAaAAYJSCMeFgBgAgAAAA==.',
Ly='Lyaenna:BAAALgAECggJEwAAAA==.Lydius:BAABLgAECn8bAAIdAAgJrhAkHgCQAQAdAAgJrhAkHgCQAQAAAA==.Lymn:BAAALgADCgQJBAAAAA==.',
Ma='Macguffins:BAAALgAECgQJBAAAAA==.Maddex:BAAALgAECgIJAgAAAA==.Madeng:BAAALgAECgUJCwAAAA==.Mageshir:BAABLgAECn8VAAIGAAgJlQs/OACGAQAGAAgJlQs/OACGAQAAAA==.Maletherion:BAABLgAECn8cAAITAAYJaCEeBADTAQATAAYJaCEeBADTAQAAAA==.Malhoon:BAAALgADCgQJBAAAAA==.Maltherion:BAABLgAECn8WAAIWAAcJkB6KFAAsAgAWAAcJkB6KFAAsAgAAAA==.Maolestromz:BAAALgAECgcJAwAAAA==.Margareetah:BAAALgAECgEJAQAAAA==.',
Mi='Mikokahuna:BAAALgAECgUJCQAAAA==.Minglo:BAAALgAECgUJCAAAAA==.Minireaper:BAAALgAECgUJDQAAAA==.Mistaeko:BAAALgADCgMJAwAAAA==.',
Mj='Mjolnir:BAABLgAECn8cAAISAAYJ9iI0GgDtAQASAAYJ9iI0GgDtAQAAAA==.',
Mo='Moggren:BAAALgAECggJDgAAAA==.Moirbidia:BAAALgADCgcJCgAAAA==.Mongke:BAAALgADCgYJBwAAAA==.',
['Mî']='Mîsh:BAAALgAECgMJAwAAAA==.',
Na='Namôr:BAAALgADCgYJCwAAAA==.Narzel:BAAALgAECgQJBQAAAA==.Nazgul:BAAALgAECgkJDwAAAA==.',
Ne='Necronias:BAAALgAECgYJEAAAAA==.Nelelish:BAAALgAECgEJAQAAAA==.Nequins:BAABLgAECn8aAAIdAAYJsR+xKQAMAgAdAAYJsR+xKQAMAgAAAA==.Nequinss:BAABLgAECn8bAAIfAAgJbCN6AQAvAwAfAAgJbCN6AQAvAwABLgAECgYJGgAdALEfAA==.Nevermore:BAAALgAECgUJBwAAAA==.',
Ni='Nicabar:BAABLgAECn8lAAIXAAgJUApiMgBiAQAXAAgJUApiMgBiAQAAAA==.Nitemare:BAAALgADCgEJAQAAAA==.',
No='Noaman:BAAALgAECgEJAgAAAA==.Noapandman:BAAALgAECgEJAQAAAA==.Noie:BAAALgAECgIJAgAAAA==.Nooamann:BAAALgADCgEJAQAAAA==.Noodles:BAAALgADCgYJCQABLgAECgYJEgABAAAAAA==.Noztalgia:BAAALgAECgYJEAAAAA==.',
Nx='Nxttuesday:BAAALgADCgUJBQAAAA==.',
['Nå']='Nåndo:BAAALgAECgEJAQAAAA==.',
['Në']='Nëklaüs:BAAALgAECgYJDgAAAA==.',
Oa='Oakily:BAABLgAECn8WAAIdAAYJ9Ak4cgD/AAAdAAYJ9Ak4cgD/AAAAAA==.',
Od='Oditte:BAAALgADCgYJBgAAAA==.',
Oi='Oilliphéist:BAAALgAECgQJCQAAAA==.',
Om='Omegatanker:BAABLgAECn8mAAIgAAkJ7yU1AAByAwAgAAkJ7yU1AAByAwAAAA==.',
Or='Ornot:BAABLgAECn8ZAAIfAAgJUA46IwBOAQAfAAgJUA46IwBOAQAAAA==.',
Os='Oshdruid:BAABLgAECn8XAAIdAAgJqyAfDwAeAgAdAAgJqyAfDwAeAgAAAA==.',
Ow='Owo:BAAALgADCgYJDAAAAA==.',
Pa='Pacfritanda:BAAALgADCgQJBAAAAA==.Pandurbear:BAAALgADCgYJCwAAAA==.Paws:BAAALgAECgEJAQAAAA==.',
Pe='Pequin:BAAALgAECgYJBgABLgAECgYJGgAdALEfAA==.Pergatory:BAAALgAECgYJEgAAAA==.',
Ph='Pho:BAAALgAFFAIJAgAAAA==.Phuule:BAAALgADCgQJCQAAAA==.Phuulmojo:BAAALgADCgIJAgAAAA==.',
Pi='Piruletras:BAAALgAECgYJCwAAAA==.',
Pr='Priechwhirl:BAABLgAECn8VAAIUAAkJCQzoBQDFAQAUAAkJCQzoBQDFAQAAAA==.Provost:BAABLgAECn8VAAISAAYJQSMjGwDnAQASAAYJQSMjGwDnAQAAAA==.',
Pu='Pumpkinpîe:BAAALgAECgEJAgAAAA==.',
Qu='Quanx:BAAALgAECgcJDQAAAA==.',
Ra='Radiantmist:BAAALgADCgMJAwABLgAECgEJAQABAAAAAA==.Raydora:BAAALgADCgQJBwAAAA==.',
Re='Remulüs:BAABLgAECn8VAAQCAAgJeBlxIwBfAQACAAgJeBlxIwBfAQAOAAMJ0wPhEQBuAAAWAAEJAADAbwA1AAAAAA==.',
Ri='Riah:BAAALgADCgkJCQAAAA==.Rickyböbby:BAAALgADCgQJBQAAAA==.Riilyn:BAABLgAECn8fAAIhAAgJyxk9CADrAQAhAAgJyxk9CADrAQAAAA==.Riolu:BAAALgAECgEJAQAAAA==.',
Ru='Ruith:BAAALgAECgQJBwAAAA==.',
['Rø']='Røean:BAAALgAECgYJCAAAAA==.',
Sa='Saina:BAAALgAECgEJAQAAAA==.Satanshelpa:BAAALgADCgUJBQAAAA==.',
Sc='Scalebeard:BAABLgAECn8ZAAQKAAgJ9gmcDwAFAQAKAAgJ9gmcDwAFAQAJAAUJvhmOCQDdAAAIAAEJ7Aw+YwAwAAAAAA==.Scecretzs:BAAALgAECgQJBwAAAA==.Screnry:BAAALgAECgEJAQAAAA==.',
Se='Secretz:BAAALgADCgYJCgAAAA==.Sedrelari:BAABLgAECn8ZAAIeAAYJKB72DAD7AQAeAAYJKB72DAD7AQAAAA==.Seizethesol:BAAALgADCgIJAgAAAA==.Sepsis:BAAALgAECgQJBAAAAA==.Sesamo:BAACLgAFFH8QAAISAAQJmxV8DQBSAQASAAQJmxV8DQBSAQAuAAQKfycAAhIACQl/IzoGAGoDABIACQl/IzoGAGoDAAAA.',
Sh='Shocks:BAAALgAECgEJAgAAAA==.Shroomin:BAABLgAECn8YAAIiAAcJPSB8DwCsAQAiAAcJPSB8DwCsAQAAAA==.',
Si='Sixseven:BAAALgADCgkJGQAAAA==.',
Sk='Skass:BAAALgADCgcJEAAAAA==.',
Sl='Slok:BAAALgADCgcJCwAAAA==.Slyndara:BAAALgAECgUJDwAAAA==.',
Sm='Smarthen:BAABLgAECn8eAAQGAAgJHRfsHQD4AQAGAAgJHRfsHQD4AQAjAAIJJwFbEAAzAAAkAAEJPgEPIwANAAAAAA==.',
Sn='Sniffums:BAABLgAECn8YAAIeAAgJPBBQCQDNAQAeAAgJPBBQCQDNAQAAAA==.',
So='Sokto:BAAALgAECgUJBQAAAA==.Solarian:BAABLgAECn8ZAAICAAYJ2hDqOQD8AAACAAYJ2hDqOQD8AAAAAA==.Soule:BAAALgADCgkJKwAAAA==.',
Sp='Spacewalrus:BAAALgADCgIJAgABLgAECgYJGgAaAEgjAA==.',
St='Startle:BAAALgADCgcJEwAAAA==.Steelbreeze:BAAALgAECgEJAQAAAA==.Stoutbringer:BAAALgADCggJHQAAAA==.Størmzkurse:BAAALgAECgEJAQAAAA==.',
Sy='Sylvaedir:BAAALgADCgcJBgAAAA==.Systran:BAAALgADCgYJBwAAAA==.',
Ta='Tailrazen:BAAALgAECgIJAgAAAA==.Talyn:BAABLgAECn8VAAIGAAgJJwr4UgA6AQAGAAgJJwr4UgA6AQAAAA==.Taomi:BAABLgAECn8cAAIfAAYJtxe6GgCOAQAfAAYJtxe6GgCOAQAAAA==.Taylorswift:BAAALgAECgQJCgAAAA==.',
Te='Tengri:BAAALgAECgEJBAAAAA==.Tenspeed:BAABLgAECn8RAAICAAYJXBSwMgAYAQACAAYJXBSwMgAYAQAAAA==.',
Th='Thire:BAAALgAECgYJCgAAAA==.Thisrogue:BAAALgAECgEJAQAAAA==.Throwglaive:BAAALgAECgQJBAABLgAFFAYJFQAlAD4jAA==.',
Ti='Tidereign:BAAALgAECgQJBwAAAA==.Timka:BAAALgAECgUJDQAAAA==.Tiriell:BAABLgAECn8gAAISAAkJYSAmBQDHAgASAAkJYSAmBQDHAgAAAA==.',
Tr='Tracixs:BAAALgAECgEJAQAAAA==.Trenity:BAAALgADCgIJAgAAAA==.Trinanah:BAACLgAFFH8FAAIVAAMJ0QV0DgDeAAAVAAMJ0QV0DgDeAAAuAAQKfygAAhUACAnnEtEbAP4BABUACAnnEtEbAP4BAAAA.',
['Tô']='Tôrunn:BAABLgAECn8cAAIEAAgJuwwsDwANAQAEAAgJuwwsDwANAQAAAA==.',
Un='Undeadots:BAAALgAECgEJAQAAAA==.',
Ut='Uthandric:BAAALgADCgIJAgABLgAECgYJHAAEAJ0kAA==.',
Va='Vallock:BAAALgAECgYJEQAAAA==.Vanarn:BAAALgADCgQJBQAAAA==.',
Ve='Velrez:BAAALgAECgMJAwAAAA==.Vengence:BAAALgADCgYJBwAAAA==.Venusäur:BAAALgAECgUJBgAAAA==.',
Vi='Viital:BAAALgAECgMJBQAAAA==.',
Vo='Voidblade:BAAALgAECgIJBQAAAA==.Voidbourne:BAAALgADCgEJAQAAAA==.',
Wa='Wammus:BAAALgAECgYJCgAAAA==.Warglaive:BAAALgADCgMJBQAAAA==.Wayden:BAAALgAECggJEwAAAA==.Waz:BAAALgAECgMJAwAAAA==.',
We='Wef:BAABLgAECn8WAAILAAcJ9AkdLQBdAQALAAcJ9AkdLQBdAQAAAA==.',
Wh='Whobit:BAAALgADCgUJBQAAAA==.',
Wi='Wimbly:BAAALgAECgMJAwAAAA==.Windwalker:BAABLgAECn8gAAIHAAcJliCIBQBAAgAHAAcJliCIBQBAAgAAAA==.Wings:BAAALgAECggJDQAAAA==.Wintel:BAAALgADCgQJBAAAAA==.Wizzinmapant:BAAALgAECgUJCgAAAA==.',
Xa='Xanza:BAAALgADCgYJCAAAAA==.',
Yl='Ylva:BAAALgADCgcJCAAAAA==.',
Yo='Yo:BAAALgAECgUJDAAAAA==.Yozomiria:BAAALgADCgYJCQAAAA==.',
Yu='Yummybuttons:BAAALgAECgQJBAAAAA==.',
Za='Zandk:BAAALgADCgkJEAABLgAFFAQJCgAIAOYHAA==.Zanju:BAAALgAECgQJCAAAAA==.Zanvoker:BAACLgAFFH8KAAIIAAQJ5gftEwAKAQAIAAQJ5gftEwAKAQAuAAQKfxsAAggABwm5GKYWACICAAgABwm5GKYWACICAAAA.',
Ze='Zerc:BAABLgAECn8tAAImAAkJjx6DAACxAgAmAAkJjx6DAACxAgAAAA==.',
Zi='Zinkie:BAABLgAECn8WAAIMAAYJABZ9BwA7AQAMAAYJABZ9BwA7AQAAAA==.',
Zo='Zorttok:BAAALgAECgMJBAAAAA==.',
Zy='Zyp:BAAALgADCgMJAwAAAA==.',
['Æn']='Ænlora:BAACLgAFFH8KAAICAAUJ9g+VCwB5AQACAAUJ9g+VCwB5AQAuAAQKfxcAAgIACQmPIkYUAN4CAAIACQmPIkYUAN4CAAAA.',
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
