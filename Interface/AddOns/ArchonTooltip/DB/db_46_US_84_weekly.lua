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

local lookup = {'Unknown-Unknown','Mage-Arcane','Mage-Frost','Mage-Fire','Priest-Holy','Warrior-Protection','Shaman-Restoration','Shaman-Elemental','DeathKnight-Unholy','Warrior-Fury','Hunter-Survival','Hunter-BeastMastery','DeathKnight-Blood','Rogue-Outlaw','Druid-Restoration','Druid-Balance','Druid-Feral','Druid-Guardian','Hunter-Marksmanship','Paladin-Holy','DemonHunter-Devourer','Warlock-Demonology','Warlock-Affliction','Paladin-Retribution','DemonHunter-Havoc','DemonHunter-Vengeance','Monk-Windwalker','Warlock-Destruction','Warrior-Arms','Priest-Shadow','DeathKnight-Frost','Paladin-Protection','Shaman-Enhancement','Monk-Mistweaver',}
local provider = {region='US',realm='EchoIsles',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aaelless:BAAALgAECgEJAQAAAA==.',
Ab='Abeblinkin:BAAALgADCgQJBwAAAA==.Abrakadavar:BAAALgAECgQJBQAAAA==.Abräxis:BAAALgADCgkJCQABLgAECgMJAwABAAAAAA==.',
Ae='Aeless:BAAALgAECggJDgAAAA==.Aelless:BAAALgAECgMJBQAAAA==.Aenest:BAAALgADCggJCAAAAA==.',
Ai='Aithinne:BAAALgADCgkJKAAAAA==.',
Ak='Akanah:BAAALgADCgcJBwAAAA==.',
Al='Alfira:BAAALgAECgYJCgAAAA==.Alghul:BAAALgAECgEJAQABLgAECgUJCgABAAAAAA==.',
Am='Amalthea:BAAALgADCgcJBwAAAA==.Amoredis:BAAALgADCgYJBgAAAA==.',
An='Anklbiterkat:BAAALgADCgQJBAAAAA==.Anume:BAAALgADCgQJCgAAAA==.',
Ar='Arese:BAABLgAECn8bAAQCAAYJUyZ/AwA0AgACAAUJUyZ/AwA0AgADAAMJlyTiEgHYAAAEAAEJAABTDABpAAAAAA==.Aron:BAAALgADCgMJAgAAAA==.',
As='Ashandra:BAAALgADCgkJDwAAAA==.Ashlyssra:BAABLgAECn8VAAIFAAgJBB1mBQCvAgAFAAgJBB1mBQCvAgAAAA==.',
Aw='Awsomesause:BAAALgAECgQJBgAAAA==.',
Az='Azuri:BAAALgAECgQJBQAAAA==.Azzif:BAAALgAECgkJDAAAAA==.Azzraell:BAAALgADCgEJAQAAAA==.',
Ba='Babasha:BAAALgAFFAIJAgAAAA==.Babybluz:BAAALgAECgMJBAAAAA==.Baconloaf:BAAALgAECgUJCQAAAA==.Baldilocks:BAAALgADCgQJDAAAAA==.Bat:BAAALgADCgEJAQAAAA==.',
Be='Beauriley:BAABLgAECn8rAAIGAAkJJBFUCgDKAQAGAAkJJBFUCgDKAQAAAA==.Behomethan:BAABLgAECn8kAAMHAAgJNhpHKgDlAQAHAAgJNhpHKgDlAQAIAAYJuBamIgA9AQAAAA==.Beyonsláy:BAAALgADCgIJAgAAAA==.',
Bh='Bhipbookie:BAAALgAECgEJAwAAAA==.',
Bi='Billbetaray:BAAALgADCgMJAwAAAA==.',
Bl='Bluerift:BAAALgADCgEJAQAAAA==.',
Bo='Bobbyb:BAAALgAECgYJCwAAAA==.Bombchele:BAAALgAECgYJBgABLgAECggJFwAJAIgaAA==.Boneulngtime:BAAALgADCgUJCgAAAA==.Boon:BAAALgAECgIJAgAAAA==.Bowlofwrong:BAAALgAECgYJBwAAAA==.',
Br='Bratticusrex:BAABLgAECn8YAAIKAAYJnAlQMAALAQAKAAYJnAlQMAALAQAAAA==.Bresowar:BAAALgAECgYJBwAAAA==.',
Bu='Bunnylicious:BAABLgAECn8aAAIHAAgJryQABQDtAgAHAAgJryQABQDtAgAAAA==.Bunnymedic:BAAALgAECgYJDAABLgAECggJGgAHAK8kAA==.',
Ca='Caebrylla:BAABLgAECn8dAAILAAcJpAy5FQBkAQALAAcJpAy5FQBkAQAAAA==.Camigatu:BAAALgADCgQJBAAAAA==.Camil:BAAALgAECgEJAQABLgAECggJGgAMAHwWAA==.Cang:BAAALgADCgcJCgAAAA==.Capulin:BAABLgAECn8eAAIKAAgJkhW2EgDYAQAKAAgJkhW2EgDYAQAAAA==.Catdurid:BAAALgADCgYJBgAAAA==.',
Ce='Cecimorte:BAABLgAECn8dAAINAAcJpxdoDgCLAQANAAcJpxdoDgCLAQAAAA==.Cephalopod:BAABLgAECn8RAAIOAAcJphfEAwD5AQAOAAcJphfEAwD5AQAAAA==.',
Ch='Chargeasap:BAAALgAECgMJAwAAAA==.Charttopper:BAAALgAECgUJCAAAAA==.Chibby:BAAALgADCgIJAgAAAA==.Chonker:BAABLgAECn8uAAMPAAgJaSG8BQD6AgAPAAgJaSG8BQD6AgAQAAMJeQojSABfAAAAAA==.Chorelock:BAAALgADCgEJAQAAAA==.Chronormu:BAAALgADCgEJAQAAAA==.Chuckforrest:BAAALgAECgQJBAAAAA==.Chultis:BAABLgAECn8VAAQRAAYJMBX3FQBYAQARAAYJMBX3FQBYAQAQAAEJ2wHxjgAeAAAPAAEJAgLG6QAbAAAAAA==.',
Ci='Cihato:BAABLgAECn8tAAISAAkJZBgkBAA+AgASAAkJZBgkBAA+AgAAAA==.',
Cl='Claxious:BAABLgAECn8WAAITAAgJHxRIBgC1AQATAAgJHxRIBgC1AQAAAA==.Claye:BAACLgAFFH8JAAIHAAMJOQ2ZJQC+AAAHAAMJOQ2ZJQC+AAAuAAQKfyIAAgcACQl8FFAmAPoBAAcACQl8FFAmAPoBAAAA.',
Co='Coldshoulder:BAABLgAECn8dAAIDAAcJ3hpuMgDXAQADAAcJ3hpuMgDXAQAAAA==.Corelas:BAAALgAECgYJEwAAAA==.Corfellyn:BAAALgAECggJBAAAAA==.Couchdad:BAAALgAECgUJCgAAAA==.',
Cr='Crazymadman:BAAALgAECgEJAQAAAA==.',
Cy='Cyon:BAAALgADCgEJAQAAAA==.',
Da='Daalaria:BAAALgADCgEJAQAAAA==.Darkone:BAAALgADCgUJBQAAAA==.Dawnson:BAABLgAECn8fAAIUAAcJDx5jDQA/AgAUAAcJDx5jDQA/AgAAAA==.',
De='Deadzexcs:BAAALgAECgUJCwAAAA==.Deathsnear:BAAALgAECgEJAQAAAA==.Demogless:BAAALgAECgYJDAAAAA==.Devyn:BAAALgADCgUJBQAAAA==.',
Dh='Dharknight:BAAALgADCgQJCAAAAA==.',
Di='Didimissfire:BAEBLgAECn8sAAIMAAgJbBRUJADEAQAMAAgJbBRUJADEAQAAAA==.',
Do='Donaghy:BAAALgAECgEJAQAAAA==.Dooms:BAAALgADCgcJBwAAAA==.',
Dp='Dpsmaster:BAAALgAECgUJEQAAAA==.',
Dr='Dranalis:BAAALgAECgYJBwAAAA==.Drdrake:BAAALgADCgcJFAAAAA==.Dredlok:BAAALgADCgkJFQAAAA==.Drufiyo:BAAALgAECgUJBQABLgAECgkJJgAVANERAA==.',
Du='Dumonster:BAAALgAECgYJCQAAAA==.',
['Dø']='Døll:BAAALgADCgYJBgAAAA==.',
Ea='Eamishal:BAAALgADCgEJAQAAAA==.',
Ei='Eightace:BAAALgADCgIJAgAAAA==.Eirenne:BAAALgAECgYJBwAAAA==.',
Ek='Ekaru:BAAALgADCgEJAQAAAA==.',
El='Elethryia:BAAALgAECgIJBAAAAA==.Elev:BAAALgADCgYJCgAAAA==.Elindril:BAAALgAECgYJDwAAAA==.',
En='Enoth:BAAALgAECgUJCAAAAA==.',
Eo='Eowynn:BAABLgAECn8WAAIHAAgJTha0IQCmAQAHAAgJTha0IQCmAQAAAA==.',
Es='Estella:BAABLgAECn8cAAIDAAYJSgsPfgAVAQADAAYJSgsPfgAVAQAAAA==.',
Ev='Eventhorizon:BAAALgAECgkJBgAAAA==.Evielli:BAAALgADCgUJBQAAAA==.',
Fa='Faeriefire:BAAALgADCgQJBQAAAA==.Fanna:BAAALgADCgMJAwAAAA==.Fatbox:BAABLgAECn8bAAIKAAgJhhwCMwDfAQAKAAgJhhwCMwDfAQAAAA==.Faythh:BAABLgAECn8rAAIFAAgJ3B+xBQCmAgAFAAgJ3B+xBQCmAgAAAA==.',
Fe='Fearblade:BAAALgADCgcJDgAAAA==.Fedoran:BAABLgAECn8ZAAMRAAgJgx+lCABTAgARAAYJqiKlCABTAgAQAAYJmBxQTgDwAAAAAA==.Felasap:BAAALgAECgEJAQAAAA==.Fenastic:BAABLgAECn8bAAMWAAcJGAclaQD6AAAWAAcJdQYlaQD6AAAXAAMJEAYsHACRAAAAAA==.Fenrisúlfur:BAAALgAECgUJDQAAAA==.Feyrah:BAAALgAECgMJAwABLgAECggJFgAHAE4WAA==.',
Fi='Filthy:BAAALgAECgkJCQAAAA==.Fiobhe:BAAALgAECgYJEQAAAA==.Fixeruper:BAABLgAECn8XAAIFAAgJQwH9MQDAAAAFAAgJQwH9MQDAAAAAAA==.',
Fl='Flaggedname:BAAALgADCgMJAwAAAA==.Flubberduck:BAAALgADCggJEAAAAA==.Fluffybeer:BAABLgAECn8eAAIJAAgJTh0lFQBSAgAJAAgJTh0lFQBSAgAAAA==.',
Fo='Fonz:BAAALgAECgUJBQABLgAECgcJGgAUAHMQAA==.Footdig:BAABLgAECn8VAAIPAAcJ2CLyCQCpAgAPAAcJ2CLyCQCpAgAAAA==.',
Fu='Fuquan:BAAALgAECgEJAgAAAA==.',
Fw='Fwd:BAAALgADCgIJAgAAAA==.',
Ga='Gadzook:BAAALgADCggJFQAAAA==.Gatolun:BAAALgADCgUJBQAAAA==.',
Gi='Giline:BAAALgAECgEJAQAAAA==.Gimp:BAAALgADCgEJAQAAAA==.Ginja:BAAALgADCgIJAgAAAA==.',
Gl='Glenlizzo:BAEALgADCgQJBAABLgAECgQJBAABAAAAAA==.Glenroyce:BAEALgAECgQJBAAAAA==.Gless:BAAALgADCgkJOAAAAA==.',
Go='Goodfine:BAAALgADCgcJDwAAAA==.Goss:BAAALgADCgcJBwAAAA==.',
Gr='Grandcross:BAAALgADCgMJAwAAAA==.',
Gu='Gungnir:BAAALgAECgYJDAAAAA==.Gush:BAAALgADCgQJBAAAAA==.Guttertrash:BAAALgAECgIJAgAAAA==.',
Ha='Hae:BAAALgADCgEJAQAAAA==.Haenus:BAAALgADCgQJAgAAAA==.Haill:BAAALgAECgYJBwAAAA==.Hamhock:BAAALgAECgUJCAABLgAECggJGwAKAIYcAA==.Hammered:BAEALgADCgUJBQABLgAECgQJBAABAAAAAA==.Hardtobepro:BAAALgAECgcJBwAAAA==.Harleydk:BAAALgADCgUJBQAAAA==.',
He='Heartsong:BAAALgAECgcJBgAAAA==.',
Ho='Holycrusader:BAABLgAECn8YAAIYAAgJUBKUSABsAQAYAAgJUBKUSABsAQAAAA==.',
Ih='Ihatepallys:BAAALgADCgcJEAAAAA==.',
Ii='Iikeomgikr:BAAALgADCgEJAQAAAA==.',
Il='Ilduca:BAAALgADCgQJBAAAAA==.Ilidank:BAAALgAECgYJDAAAAA==.Ilya:BAAALgADCgcJBwABLgAECgcJFgAYALQaAA==.',
Im='Impotence:BAAALgADCgMJAwAAAA==.',
In='Indigo:BAABLgAECn8sAAIHAAgJ1B5gBwC4AgAHAAgJ1B5gBwC4AgAAAA==.Innax:BAAALgADCgEJAQAAAA==.Innron:BAABLgAECn8lAAIZAAgJ7hC1DgCWAQAZAAgJ7hC1DgCWAQAAAA==.',
Ir='Irisblue:BAAALgADCgQJCgAAAA==.',
Is='Isyclic:BAAALgAECgYJBgABLgAECggJIAAGADwhAA==.',
Iy='Iyahli:BAAALgAECgUJDQAAAA==.',
Ja='Jarclian:BAACLgAFFH8IAAIDAAMJvRBHSAD5AAADAAMJvRBHSAD5AAAuAAQKfzgAAgMACQnRIkIEADUDAAMACQnRIkIEADUDAAAA.Jaymonk:BAAALgAECgEJAQAAAA==.Jazmon:BAAALgAECgEJAQAAAA==.',
Je='Jezzea:BAAALgADCgQJBwAAAA==.',
Ji='Jimlaheys:BAAALgAECgYJDgAAAA==.Jitt:BAAALgAECgQJBAAAAA==.',
['Jâ']='Jâtens:BAACLgAFFH8GAAMVAAQJYxLqHgAwAQAVAAQJYxLqHgAwAQAaAAEJAgTZCQAnAAAuAAQKfxoAAhUACAmWHX4RADQCABUACAmWHX4RADQCAAAA.',
Ka='Kaelía:BAAALgAECgUJBQAAAA==.Kair:BAABLgAECn8mAAIbAAkJ/QgSGABlAQAbAAkJ/QgSGABlAQAAAA==.Kairring:BAAALgAECgcJDAAAAA==.Kamehameha:BAAALgAFFAEJAQAAAA==.Kami:BAABLgAECn8sAAIbAAgJpREtEwCaAQAbAAgJpREtEwCaAQAAAA==.Kapslock:BAAALgAECgYJBwAAAA==.Karii:BAAALgADCgEJAQAAAA==.Karma:BAAALgADCgcJHAAAAA==.Katsicle:BAAALgAECgYJCQAAAA==.Katteya:BAAALgADCgkJMQAAAA==.Kattia:BAABLgAECn8jAAIMAAgJxg20LACcAQAMAAgJxg20LACcAQAAAA==.',
Kh='Khalico:BAAALgADCgEJAQAAAA==.Khellendros:BAAALgADCgUJBQABLgAECgYJCgABAAAAAA==.Khir:BAAALgAECgQJBwAAAA==.',
Ki='Kinomihime:BAABLgAECn8tAAIDAAkJJg9LLgDoAQADAAkJJg9LLgDoAQAAAA==.Kirajoy:BAABLgAECn8rAAIcAAgJDQV3DQD7AAAcAAgJDQV3DQD7AAAAAA==.Kirel:BAAALgADCgEJAQAAAA==.',
Kn='Knyghtt:BAABLgAECn8YAAIKAAYJ8QujLgAUAQAKAAYJ8QujLgAUAQAAAA==.',
Ko='Kogwyn:BAAALgAECggJBwAAAA==.Kogy:BAAALgADCgcJBgABLgAECggJBwABAAAAAA==.',
Kr='Kraviz:BAAALgADCgUJBQAAAA==.Krombopolous:BAAALgADCgkJGQABLgAECggJHwAMAJsLAA==.Krystle:BAABLgAECn8XAAIMAAcJvBbcKACuAQAMAAcJvBbcKACuAQAAAA==.',
Ky='Kydormu:BAAALgADCgEJAQAAAA==.',
Le='Leftyloose:BAAALgADCgkJBAAAAA==.',
Li='Lilfonz:BAABLgAECn8aAAMUAAcJcxBsIgB0AQAUAAcJcxBsIgB0AQAYAAYJshgmbAAVAQAAAA==.Livik:BAAALgAECgcJEgAAAA==.',
Lo='Lockofdeath:BAAALgADCgYJBwAAAA==.Lockywolf:BAAALgAECgUJBgAAAA==.Logarth:BAAALgAECgUJBQAAAA==.Longbrew:BAAALgADCgEJAQAAAA==.Loppsang:BAAALgAECgIJAgAAAA==.Lorcan:BAABLgAECn8sAAIdAAkJsRlyAwBsAgAdAAkJsRlyAwBsAgAAAA==.',
Lr='Lroye:BAAALgAFFAMJBAAAAA==.',
Ls='Lsdarko:BAAALgAECgEJAQAAAA==.',
Lu='Luckyleet:BAAALgADCgQJBwAAAA==.Lucyfer:BAAALgAECgUJCgABLgAECggJHAAMAFMMAA==.Lucyferr:BAAALgADCggJCAABLgAECggJHAAMAFMMAA==.Ludicrispeed:BAAALgADCgQJCgAAAA==.Luliak:BAACLgAFFH8LAAILAAQJNCJpAgCWAQALAAQJNCJpAgCWAQAuAAQKfxUAAgsACAmTH6kJAEQCAAsACAmTH6kJAEQCAAAA.Lunabren:BAABLgAECn8YAAMQAAcJwwdtKAD+AAAQAAcJwwdtKAD+AAAPAAIJoQYlhgBIAAAAAA==.Lunamina:BAAALgADCgkJLwAAAA==.',
Ly='Lynvala:BAAALgADCgQJBQAAAA==.Lysdexíc:BAABLgAECn8VAAIVAAgJGBEcOABVAQAVAAgJGBEcOABVAQAAAA==.',
['Lì']='Lìllith:BAABLgAECn8XAAMFAAcJsRmPHQDyAQAFAAcJsRmPHQDyAQAeAAMJLQncTgCXAAABLgAECgkJMQAYALkZAA==.',
Ma='Majika:BAAALgADCgYJBQAAAA==.Mariophra:BAABLgAECn8dAAIHAAcJphsQEwAeAgAHAAcJphsQEwAeAgAAAA==.Marvelious:BAAALgAFFAEJAQAAAA==.Mattlen:BAAALgADCgYJCAAAAA==.Maxmugruith:BAAALgADCgQJBwAAAA==.',
Me='Meatshiéld:BAAALgAECgYJCgAAAA==.',
Mi='Midopamos:BAAALgADCgEJAQAAAA==.Mikki:BAAALgADCgQJBQAAAA==.Misstorgo:BAAALgAECgUJCAAAAA==.',
Mo='Monfro:BAAALgAECgUJCgAAAA==.Moogatoo:BAAALgAECgYJCAAAAA==.Moonbane:BAABLgAECn8sAAIcAAgJTyAZAQCPAgAcAAgJTyAZAQCPAgAAAA==.Moonfanda:BAAALgADCgIJAgAAAA==.Moonmist:BAAALgADCgEJAQABLgAECgYJBwABAAAAAA==.',
Mu='Mumferd:BAAALgADCgQJBAAAAA==.',
My='Myaquean:BAAALgADCgQJCgAAAA==.Mystogan:BAAALgADCgUJCQAAAA==.Myth:BAAALgADCgUJBQAAAA==.',
Na='Nakeefa:BAABLgAECn8bAAMWAAkJMhMyHwD2AQAWAAkJMhMyHwD2AQAcAAEJAAAzcgAzAAAAAA==.Natsuu:BAABLgAECn8aAAIMAAgJnBoWIgDQAQAMAAgJnBoWIgDQAQAAAA==.Naturewolf:BAABLgAECn8eAAIRAAgJWBZ+CAClAQARAAgJWBZ+CAClAQAAAA==.',
Ne='Nekona:BAABLgAECn8UAAQWAAcJdAx8iQBGAQAWAAcJdAx8iQBGAQAcAAIJCgmkWwBcAAAXAAEJlwWUNAAzAAAAAA==.Neron:BAABLgAECn8xAAIYAAkJuRlTEwBfAgAYAAkJuRlTEwBfAgAAAA==.Nethertusk:BAABLgAECn8pAAMWAAgJjxcBJQDWAQAWAAgJjxcBJQDWAQAcAAIJYQPtWQBhAAAAAA==.',
Nh='Nhancecntrl:BAAALgAECggJEgAAAA==.',
Ni='Niany:BAAALgAECgMJAwAAAA==.Nightbréaker:BAAALgADCgcJFQAAAA==.Nilospite:BAABLgAECn8UAAIGAAcJCRjhCwCoAQAGAAcJCRjhCwCoAQABLgAFFAQJEQANAEoVAA==.Nimposter:BAABLgAECn8bAAIJAAcJTBKiRwBkAQAJAAcJTBKiRwBkAQAAAA==.',
Nj='Njoror:BAAALgADCgQJBAAAAA==.',
No='Noodle:BAAALgADCgEJAQAAAA==.Nottapally:BAAALgAECgcJEAAAAA==.',
Nu='Nullea:BAAALgAECgYJCAAAAA==.',
Ny='Nyxthos:BAAALgADCggJCAAAAA==.',
Ob='Obizi:BAAALgADCgcJBwAAAA==.',
Oc='Ocatarineta:BAAALgADCgIJAgAAAA==.',
Od='Odito:BAAALgAECgQJBQAAAA==.',
Oo='Oopslol:BAAALgAECgYJDAAAAA==.',
Os='Osdavalmarro:BAAALgADCgYJGQAAAA==.',
Ot='Othaerion:BAABLgAECn8UAAIUAAgJtA/7GwCpAQAUAAgJtA/7GwCpAQAAAA==.',
Ou='Outerlimits:BAABLgAECn8kAAIfAAcJwhoKBAC5AQAfAAcJwhoKBAC5AQAAAA==.',
Pa='Paindore:BAAALgAECgQJBAAAAA==.Pamboo:BAABLgAECn8oAAIUAAgJhhAEGQDDAQAUAAgJhhAEGQDDAQAAAA==.',
Pe='Pearle:BAABLgAECn8gAAINAAgJPh3QCQDhAQANAAgJPh3QCQDhAQAAAA==.',
Ph='Phyg:BAAALgAECgQJBQABLgAECgUJBwABAAAAAA==.',
Po='Pokimane:BAAALgADCggJDwAAAA==.Polyasap:BAAALgADCgQJBAAAAA==.',
Pr='Proximal:BAAALgAECgcJBwAAAA==.',
Pu='Pukka:BAAALgADCgcJEQABLgAECggJIQAFAIMaAA==.Punk:BAAALgAFFAEJAQAAAA==.',
Qa='Qahnaarin:BAAALgADCgEJAQAAAA==.',
Ra='Rajax:BAAALgAECgEJAQAAAA==.Ralphthedh:BAAALgAECggJBQAAAA==.Ramindizzle:BAABLgAECn8tAAITAAgJcxXoBADjAQATAAgJcxXoBADjAQAAAA==.Rangewolf:BAAALgADCgcJDgAAAA==.',
Re='Rejuvasap:BAABLgAECn8WAAMQAAgJLxpQKQC1AQAQAAgJLxpQKQC1AQAPAAUJ3RxFJgCaAQAAAA==.Reliri:BAAALgADCgMJAwAAAA==.Remlin:BAAALgADCgcJCAAAAA==.Retsall:BAAALgADCgUJBQAAAA==.Reâper:BAAALgAECgYJCgAAAA==.',
Ri='Rikal:BAAALgADCgQJCgAAAA==.',
Ro='Rook:BAABLgAECn8sAAITAAkJNgznBgCiAQATAAkJNgznBgCiAQAAAA==.Roye:BAACLgAFFH8MAAIYAAQJpA2QHQA4AQAYAAQJpA2QHQA4AQAuAAQKfx4AAhgACQlvHbMaAMkCABgACQlvHbMaAMkCAAAA.',
Ru='Ruffiyo:BAABLgAECn8mAAMVAAkJ0RHhKwCIAQAVAAgJuhHhKwCIAQAZAAgJ3Q+HLQBfAQAAAA==.Rugrahfreaky:BAABLgAECn8eAAIPAAkJSBzABgDkAgAPAAkJSBzABgDkAgAAAA==.Rugrahh:BAABLgAECn8gAAITAAkJdB5CDwDGAgATAAkJdB5CDwDGAgAAAA==.Ruthen:BAAALgAECgQJBQAAAA==.Ruìn:BAAALgAECgMJAwAAAA==.',
Sa='Sabermore:BAAALgAECgQJCAAAAA==.Sabina:BAABLgAECn8tAAIIAAkJgAlkHgBaAQAIAAkJgAlkHgBaAQAAAA==.Sadako:BAAALgADCgkJDAABLgAECggJHAAMAFMMAA==.Sadness:BAAALgADCgkJNgAAAA==.Sadorick:BAAALgADCgkJLwAAAA==.Safira:BAAALgAECgQJBgABLgAECgkJMQAYALkZAA==.Sageguy:BAAALgADCgkJIwAAAA==.Sango:BAABLgAECn8oAAMZAAgJzxEQDgCgAQAZAAgJzxEQDgCgAQAVAAQJ2gKFwQB8AAAAAA==.Saucewalker:BAAALgAECgEJAQAAAA==.Savagelykill:BAAALgAECgQJCgAAAA==.',
Sc='Scotch:BAABLgAECn8jAAMYAAgJyRpdJADyAQAYAAgJyRpdJADyAQAgAAIJcRHDMQCHAAAAAA==.Scotchnwater:BAAALgAECgUJCAAAAA==.Scrubyheals:BAAALgADCgQJBwAAAA==.',
Se='Sendio:BAAALgAECgQJBAAAAA==.',
Sg='Sgtpayne:BAAALgADCgIJAgAAAA==.',
Sh='Shadowcrwlr:BAAALgAECgMJBgAAAA==.Shadowlock:BAAALgAECggJEwAAAA==.Shadowmane:BAAALgADCgQJBAAAAA==.Shaeixia:BAAALgADCgcJBwAAAA==.Shamangroo:BAAALgADCggJCQABLgADCgkJFwABAAAAAA==.Shammying:BAAALgAECgMJAwAAAA==.Shamsham:BAAALgADCgIJAgAAAA==.Sharaaz:BAAALgADCgUJBQAAAA==.Shivalry:BAAALgADCgkJCwAAAA==.Shmiggy:BAAALgAECgMJAwAAAA==.',
Si='Silverywine:BAAALgADCgkJCQAAAA==.Silverywolfe:BAAALgADCgkJLwAAAA==.Simony:BAABLgAECn8XAAIYAAYJ1Qa4iQDZAAAYAAYJ1Qa4iQDZAAABLgAECggJHAAMAFMMAA==.Sinton:BAAALgADCgIJAgAAAA==.',
Sk='Skorpyoh:BAAALgADCgYJBgAAAA==.Skovak:BAAALgAECgYJEAAAAA==.Skybright:BAAALgAECgEJAQAAAA==.',
So='Soggy:BAAALgAECgcJBwAAAA==.Sorayae:BAABLgAECn8hAAIFAAgJgxrzEwA/AgAFAAgJgxrzEwA/AgAAAA==.',
Sp='Specialk:BAAALgADCgkJKAAAAA==.Spinnykat:BAAALgADCggJCAAAAA==.',
St='Stoo:BAAALgADCgkJHAAAAA==.Stormkissed:BAAALgAECgUJCAAAAA==.',
Su='Sunil:BAABLgAECn8kAAIFAAgJexS5DgD8AQAFAAgJexS5DgD8AQAAAA==.Suviqhabo:BAAALgAECggJDwAAAA==.',
Sv='Svala:BAAALgADCgYJBgAAAA==.',
Sy='Syclone:BAABLgAECn8gAAIGAAgJPCEnAwCdAgAGAAgJPCEnAwCdAgAAAA==.Syladen:BAAALgAECgYJEgAAAA==.Syleste:BAAALgAECgQJBAABLgAECggJIAAGADwhAA==.Syvi:BAAALgAECgYJBQABLgAECggJBwABAAAAAA==.',
Ta='Tahwe:BAAALgADCgUJBQAAAA==.Tattianna:BAAALgADCgkJFwAAAA==.Tavendar:BAAALgAECgMJAwABLgAFFAMJCQAHADkNAA==.Taírn:BAAALgAECgYJEAAAAA==.',
Te='Techie:BAAALgAECgcJCQAAAA==.Terradactyl:BAAALgADCgMJAwAAAA==.',
Th='Thunderslate:BAAALgAECgUJBgAAAA==.Thôrin:BAAALgADCgkJFQAAAA==.',
Ti='Tigerlillee:BAAALgADCgcJDQAAAA==.Tigreth:BAABLgAECn8sAAMYAAkJxhLrJADvAQAYAAkJxhLrJADvAQAgAAIJlhSpNgBoAAAAAA==.Timotheus:BAAALgAECgQJBgAAAA==.',
To='Tonï:BAAALgADCggJCAAAAA==.',
Tr='Tragik:BAABLgAECn8fAAIhAAgJZwzSCQB8AQAhAAgJZwzSCQB8AQAAAA==.',
Tt='Ttrouble:BAAALgADCgUJBQAAAA==.',
Tu='Tuugadark:BAABLgAECn8pAAIWAAgJYx23GQAWAgAWAAgJYx23GQAWAgAAAA==.Tuugashox:BAAALgAECgUJBQAAAA==.',
Ul='Ulyaoth:BAABLgAECn8bAAIWAAYJEQaeiAC0AAAWAAYJEQaeiAC0AAAAAA==.',
Un='Unnerfable:BAAALgAECgQJBgAAAA==.',
Uy='Uy:BAAALgAECgYJDwAAAA==.',
Va='Valakha:BAAALgAECgQJCQAAAA==.Valkyrie:BAAALgAECgQJBgAAAA==.',
Ve='Vedros:BAAALgADCgQJBwAAAA==.',
Vi='Viktoros:BAAALgAECgIJAgAAAA==.Violetra:BAAALgADCgMJAwAAAA==.',
Vo='Vorcan:BAAALgADCgYJBgAAAA==.Vorukh:BAAALgAECggJEgAAAA==.',
Vr='Vrave:BAAALgADCgQJBQAAAA==.',
Vy='Vyhlet:BAAALgADCgkJOAABLgAECggJLAAHANQeAA==.',
Wa='Warriorgroo:BAAALgADCgkJFwAAAA==.',
We='Wendish:BAAALgAECgEJBgAAAA==.Wertyda:BAABLgAECn8ZAAIUAAkJsxQoEgAHAgAUAAkJsxQoEgAHAgAAAA==.',
Wh='Whácker:BAABLgAECn8UAAMdAAgJKwoTEQA8AQAdAAgJKwoTEQA8AQAGAAMJrAgrOQCBAAABLgAECgYJEAABAAAAAA==.',
Wi='Wickedslicks:BAABLgAECn8jAAIQAAgJcx90BgB3AgAQAAgJcx90BgB3AgAAAA==.Wildthangg:BAAALgAECgIJAgAAAA==.',
Wo='Wooddchipper:BAAALgADCgYJBgAAAA==.',
Wr='Wreckshop:BAABLgAECn8XAAIJAAgJiBoNMAC5AQAJAAgJiBoNMAC5AQAAAA==.',
Wt='Wtfoxtrot:BAAALgADCgkJDAAAAA==.',
Xa='Xalafeet:BAAALgAECgQJAwAAAA==.',
Xe='Xenøcide:BAAALgAECgcJEwAAAA==.',
Xx='Xxlockz:BAAALgAECgcJEwAAAA==.Xxpallyz:BAAALgAECgEJAwABLgAECgcJEwABAAAAAA==.',
Yi='Yinger:BAAALgADCgcJEAAAAA==.Yinglang:BAAALgADCgEJAQAAAA==.Yingling:BAABLgAECn8mAAIJAAgJRxnGKgDQAQAJAAgJRxnGKgDQAQAAAA==.',
Yo='Yohh:BAAALgAECgMJBQAAAA==.',
Yu='Yukara:BAAALgADCgYJBgAAAA==.Yuriko:BAABLgAECn8tAAIiAAkJkREUEQDgAQAiAAkJkREUEQDgAQAAAA==.',
Za='Zaidan:BAAALgADCgcJDgAAAA==.Zanpaktu:BAAALgAECgQJBgAAAA==.Zaraha:BAAALgADCgEJAQAAAA==.Zata:BAAALgAECgUJBwAAAA==.',
Ze='Zeref:BAAALgAECgYJDAAAAA==.Zeur:BAAALgAECgEJAQAAAA==.Zevgrip:BAAALgAECgQJBQAAAA==.',
Zh='Zhia:BAAALgAECgQJBQAAAA==.',
Zi='Zippitydooda:BAAALgADCgQJBAABLgAECgYJBwABAAAAAA==.',
Zo='Zodiacc:BAABLgAECn8uAAISAAgJbRxKBAA2AgASAAgJbRxKBAA2AgAAAA==.Zornhealer:BAAALgADCggJEAABLgAECgUJCgABAAAAAA==.',
['Zö']='Zölä:BAAALgAECgMJAwAAAA==.',
['Ât']='Âtomic:BAAALgADCgYJAgABLgAECgYJEAABAAAAAA==.',
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
