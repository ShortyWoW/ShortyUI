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

local lookup = {'Unknown-Unknown','Mage-Arcane','Mage-Frost','Mage-Fire','Warrior-Protection','Shaman-Restoration','Shaman-Elemental','DeathKnight-Unholy','Hunter-Survival','Warrior-Fury','DeathKnight-Blood','Druid-Restoration','Druid-Balance','Druid-Feral','Druid-Guardian','Hunter-Marksmanship','Paladin-Holy','Hunter-BeastMastery','Priest-Holy','Warlock-Affliction','Warlock-Demonology','Paladin-Retribution','Monk-Windwalker','DemonHunter-Havoc','DemonHunter-Devourer','Warlock-Destruction','Warrior-Arms','Evoker-Augmentation','DeathKnight-Frost','Paladin-Protection','Shaman-Enhancement','Monk-Mistweaver',}
local provider = {region='US',realm='EchoIsles',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aaelless:BAAALgAECgEJAQAAAA==.',
Ab='Abeblinkin:BAAALgADCgQJBwAAAA==.Abrakadavar:BAAALgAECgQJBQAAAA==.Abräxis:BAAALgADCgkJCQAAAA==.',
Ae='Aeless:BAAALgAECgYJBgAAAA==.Aelless:BAAALgAECgMJBQAAAA==.',
Ai='Aithinne:BAAALgADCgkJHwAAAA==.',
Ak='Akanah:BAAALgADCgcJBwAAAA==.',
Al='Alfira:BAAALgAECgUJCQAAAA==.Alghul:BAAALgAECgEJAQABLgAECgMJBQABAAAAAA==.',
Am='Amalthea:BAAALgADCgcJBwAAAA==.',
An='Anklbiterkat:BAAALgADCgQJBAAAAA==.Anume:BAAALgADCgQJCgAAAA==.',
Ar='Arese:BAABLgAECn8bAAQCAAYJUyaAAwA0AgACAAUJUyaAAwA0AgADAAMJlyTfEgHYAAAEAAEJAABTDABpAAAAAA==.Aron:BAAALgADCgMJAgAAAA==.',
As='Ashandra:BAAALgADCgkJDwAAAA==.Ashlyssra:BAAALgAECgYJCwAAAA==.',
Aw='Awsomesause:BAAALgAECgQJBQAAAA==.',
Az='Azuri:BAAALgAECgQJBQAAAA==.Azzif:BAAALgAECgkJDAAAAA==.Azzraell:BAAALgADCgEJAQAAAA==.',
Ba='Babasha:BAAALgAFFAEJAQAAAA==.Babybluz:BAAALgAECgEJAQAAAA==.Baconloaf:BAAALgAECgUJCQAAAA==.Baldilocks:BAAALgADCgQJDAAAAA==.Bat:BAAALgADCgEJAQAAAA==.',
Be='Beauriley:BAABLgAECn8iAAIFAAgJ4Q2IDQBHAQAFAAgJ4Q2IDQBHAQAAAA==.Behomethan:BAABLgAECn8dAAMGAAgJ9BhJKgDlAQAGAAcJ7RhJKgDlAQAHAAUJSRFkSAAmAQAAAA==.Beyonsláy:BAAALgADCgIJAgAAAA==.',
Bh='Bhipbookie:BAAALgAECgEJAgAAAA==.',
Bl='Bluerift:BAAALgADCgEJAQAAAA==.',
Bo='Bobbyb:BAAALgAECgYJCwAAAA==.Bombchele:BAAALgAECgYJBgABLgAECggJFwAIAIgaAA==.Boneulngtime:BAAALgADCgUJBQAAAA==.Boon:BAAALgAECgIJAgAAAA==.Bowlofwrong:BAAALgAECgYJBwAAAA==.',
Br='Bratticusrex:BAAALgAECgkJEgAAAA==.Bresowar:BAAALgAECgYJBwAAAA==.',
Bu='Bunnylicious:BAABLgAECn8YAAIGAAgJ7SMOAwDmAgAGAAgJ7SMOAwDmAgAAAA==.Bunnymedic:BAAALgAECgYJBgABLgAECggJGAAGAO0jAA==.',
Ca='Caebrylla:BAABLgAECn8WAAIJAAYJ1g3BFAAjAQAJAAYJ1g3BFAAjAQAAAA==.Camigatu:BAAALgADCgQJBAAAAA==.Camil:BAAALgAECgEJAQABLgAFFAEJAQABAAAAAA==.Capulin:BAABLgAECn8cAAIKAAgJHxWIDADnAQAKAAgJHxWIDADnAQAAAA==.Catdurid:BAAALgADCgYJBgAAAA==.',
Ce='Cecimorte:BAABLgAECn8WAAILAAYJ/BdwDQA4AQALAAYJ/BdwDQA4AQAAAA==.Cephalopod:BAAALgAECgcJDQAAAA==.',
Ch='Chargeasap:BAAALgAECgMJAwAAAA==.Charttopper:BAAALgAECgMJAwAAAA==.Chibby:BAAALgADCgIJAgAAAA==.Chonker:BAABLgAECn8nAAMMAAgJaCFmAwAEAwAMAAgJaCFmAwAEAwANAAMJeQomOQBhAAAAAA==.Chorelock:BAAALgADCgEJAQAAAA==.Chronormu:BAAALgADCgEJAQAAAA==.Chuckforrest:BAAALgAECgQJBAAAAA==.Chultis:BAABLgAECn8VAAQOAAYJMBX4FQBYAQAOAAYJMBX4FQBYAQANAAEJ2wHrjgAeAAAMAAEJAgK/6QAbAAAAAA==.',
Ci='Cihato:BAABLgAECn8kAAIPAAgJCBohBADrAQAPAAgJCBohBADrAQAAAA==.',
Cl='Claxious:BAABLgAECn8VAAIQAAgJxRNiBADJAQAQAAgJxRNiBADJAQAAAA==.Claye:BAABLgAECn8gAAIGAAkJ7xFSJgD6AQAGAAkJ7xFSJgD6AQAAAA==.',
Co='Coldshoulder:BAABLgAECn8WAAIDAAYJwxviRABgAQADAAYJwxviRABgAQAAAA==.Corelas:BAAALgAECgUJDQAAAA==.Corfellyn:BAAALgAECggJBAAAAA==.Couchdad:BAAALgAECgMJBQAAAA==.',
Cr='Crazymadman:BAAALgADCgcJEQAAAA==.',
Cy='Cyon:BAAALgADCgEJAQAAAA==.',
Da='Daalaria:BAAALgADCgEJAQAAAA==.Dawnson:BAABLgAECn8YAAIRAAcJFxySDAAOAgARAAcJFxySDAAOAgAAAA==.',
De='Deadzexcs:BAAALgAECgIJAQAAAA==.Deathsnear:BAAALgAECgEJAQAAAA==.Demogless:BAAALgAECgYJBgAAAA==.Devyn:BAAALgADCgUJBQAAAA==.',
Dh='Dharknight:BAAALgADCgQJCAAAAA==.',
Di='Didimissfire:BAEBLgAECn8mAAISAAgJLhKjHQCuAQASAAgJLhKjHQCuAQAAAA==.',
Do='Donaghy:BAAALgAECgEJAQAAAA==.Dooms:BAAALgADCgcJBwAAAA==.',
Dp='Dpsmaster:BAAALgAECgQJDAAAAA==.',
Dr='Dranalis:BAAALgAECgYJBwAAAA==.Drdrake:BAAALgADCgcJFAAAAA==.Dredlok:BAAALgADCgkJFQAAAA==.',
Du='Dumonster:BAAALgAECgIJAwAAAA==.',
['Dø']='Døll:BAAALgADCgYJBgAAAA==.',
Ea='Eamishal:BAAALgADCgEJAQAAAA==.',
Ei='Eightace:BAAALgADCgIJAgAAAA==.Eirenne:BAAALgAECgYJBwAAAA==.',
Ek='Ekaru:BAAALgADCgEJAQAAAA==.',
El='Elethryia:BAAALgAECgIJAwAAAA==.Elev:BAAALgADCgMJAwAAAA==.Elindril:BAAALgAECgYJDwAAAA==.',
En='Enoth:BAAALgAECgMJAwAAAA==.',
Eo='Eowynn:BAAALgAECgcJEgAAAA==.',
Es='Estella:BAABLgAECn8ZAAIDAAYJMwkHbgD9AAADAAYJMwkHbgD9AAAAAA==.',
Ev='Eventhorizon:BAAALgAECgYJBQAAAA==.Evielli:BAAALgADCgUJBQAAAA==.',
Fa='Fanna:BAAALgADCgMJAwAAAA==.Fatbox:BAABLgAECn8YAAIKAAgJWBwDMwDfAQAKAAgJWBwDMwDfAQAAAA==.Faythh:BAABLgAECn8jAAITAAgJzx9oAwCvAgATAAgJzx9oAwCvAgAAAA==.',
Fe='Fearblade:BAAALgADCgcJBwAAAA==.Fedoran:BAABLgAECn8XAAMOAAgJ2R2lCABTAgAOAAYJqiKlCABTAgANAAYJpxpKTgDwAAAAAA==.Fenastic:BAABLgAECn8UAAMUAAYJnwcqHACRAAAVAAYJOAbEbQCxAAAUAAMJEAYqHACRAAAAAA==.Fenrisúlfur:BAAALgAECgUJDQAAAA==.',
Fi='Filthy:BAAALgAECgkJCQAAAA==.Fiobhe:BAAALgAECgUJCwAAAA==.Fixeruper:BAAALgAECggJEQAAAA==.',
Fl='Flaggedname:BAAALgADCgMJAwAAAA==.Flubberduck:BAAALgADCggJDQAAAA==.Fluffybeer:BAABLgAECn8WAAIIAAgJjhQdJACxAQAIAAgJjhQdJACxAQAAAA==.',
Fo='Fonz:BAAALgAECgUJBQABLgAECgcJFQARAHMQAA==.Footdig:BAAALgAECgYJDgAAAA==.',
Fu='Fuquan:BAAALgAECgEJAQAAAA==.',
Fw='Fwd:BAAALgADCgIJAgAAAA==.',
Ga='Gadzook:BAAALgADCggJFQAAAA==.',
Gi='Giline:BAAALgAECgEJAQAAAA==.Gimp:BAAALgADCgEJAQAAAA==.Ginja:BAAALgADCgIJAgAAAA==.',
Gl='Glenlizzo:BAEALgADCgQJBAABLgAECgMJAwABAAAAAA==.Glenroyce:BAEALgAECgMJAwAAAA==.Gless:BAAALgADCgkJLwAAAA==.',
Go='Goodfine:BAAALgADCgcJDwAAAA==.Goss:BAAALgADCgcJBwAAAA==.',
Gr='Grandcross:BAAALgADCgMJAwAAAA==.',
Gu='Gungnir:BAAALgAECgYJBgAAAA==.Gush:BAAALgADCgQJBAAAAA==.Guttertrash:BAAALgAECgIJAgAAAA==.',
Ha='Hae:BAAALgADCgEJAQAAAA==.Haenus:BAAALgADCgQJAgAAAA==.Haill:BAAALgAECgYJBwAAAA==.Hamhock:BAAALgAECgMJAwABLgAECggJGAAKAFgcAA==.Hardtobepro:BAAALgAECgcJBwAAAA==.Harleydk:BAAALgADCgIJAgAAAA==.',
He='Heartsong:BAAALgAECgcJBgAAAA==.',
Ho='Holycrusader:BAABLgAECn8XAAIWAAgJUBIaMwB2AQAWAAgJUBIaMwB2AQAAAA==.Honourz:BAAALgAECggJCgABLgAECgkJIAAXALkWAA==.',
Ih='Ihatepallys:BAAALgADCgcJEAAAAA==.',
Ii='Iikeomgikr:BAAALgADCgEJAQAAAA==.',
Il='Ilduca:BAAALgADCgQJBAAAAA==.Ilidank:BAAALgAECgMJBAAAAA==.Ilya:BAAALgADCgcJBwAAAA==.',
In='Indigo:BAABLgAECn8kAAIGAAgJbRyUBQCZAgAGAAgJbRyUBQCZAgAAAA==.Innax:BAAALgADCgEJAQAAAA==.Innron:BAABLgAECn8eAAIYAAgJbhBrCgCYAQAYAAgJbhBrCgCYAQAAAA==.',
Ir='Irisblue:BAAALgADCgQJCgAAAA==.',
Iy='Iyahli:BAAALgAECgUJCwAAAA==.',
Ja='Jarclian:BAACLgAFFH8FAAIDAAIJ/RTWRQCxAAADAAIJ/RTWRQCxAAAuAAQKfy8AAgMACQnHHSEJAKsCAAMACQnHHSEJAKsCAAAA.Jaymonk:BAAALgADCgkJCgAAAA==.',
Je='Jezzea:BAAALgADCgQJBwAAAA==.',
Ji='Jimlaheys:BAAALgAECgYJDgAAAA==.Jitt:BAAALgAECgQJBAAAAA==.',
['Jâ']='Jâtens:BAABLgAECn8ZAAIZAAgJmB0iCgA5AgAZAAgJmB0iCgA5AgAAAA==.',
Ka='Kaelía:BAAALgAECgMJAwAAAA==.Kair:BAABLgAECn8dAAIXAAgJjgaqFwAsAQAXAAgJjgaqFwAsAQAAAA==.Kairring:BAAALgAECgYJCgAAAA==.Kamehameha:BAAALgAECggJDgAAAA==.Kami:BAABLgAECn8kAAIXAAgJfxDPDQCdAQAXAAgJfxDPDQCdAQAAAA==.Kapslock:BAAALgAECgYJBwAAAA==.Karii:BAAALgADCgEJAQAAAA==.Karma:BAAALgADCgcJHAAAAA==.Katsicle:BAAALgAECgMJAwAAAA==.Katteya:BAAALgADCgkJMAAAAA==.Kattia:BAABLgAECn8hAAISAAgJwQ3GHACzAQASAAgJwQ3GHACzAQAAAA==.',
Kh='Khalico:BAAALgADCgEJAQAAAA==.Khellendros:BAAALgADCgUJBQABLgAECgYJCgABAAAAAA==.Khir:BAAALgAECgQJBAAAAA==.',
Ki='Kinomihime:BAABLgAECn8kAAIDAAgJsBAKLwCnAQADAAgJsBAKLwCnAQAAAA==.Kirajoy:BAABLgAECn8jAAIaAAgJmQTNCgD3AAAaAAgJmQTNCgD3AAAAAA==.Kirel:BAAALgADCgEJAQAAAA==.',
Kn='Knyghtt:BAABLgAECn8XAAIKAAYJ8Qt9JAAYAQAKAAYJ8Qt9JAAYAQAAAA==.',
Ko='Kogwyn:BAAALgAECggJBwAAAA==.Kogy:BAAALgADCgcJBgABLgAECggJBwABAAAAAA==.',
Kr='Kraviz:BAAALgADCgUJBQAAAA==.Krombopolous:BAAALgADCgkJGQABLgAECgcJGwASAG8MAA==.Krystle:BAAALgAECgYJEAAAAA==.',
Le='Leftyloose:BAAALgADCgkJBAAAAA==.',
Li='Lilfonz:BAABLgAECn8VAAMRAAcJcxA9GACMAQARAAcJcxA9GACMAQAWAAUJMBQSnQBEAQAAAA==.Livik:BAAALgAECgcJEAAAAA==.',
Lo='Lockofdeath:BAAALgADCgYJBwAAAA==.Lockywolf:BAAALgAECgQJBAAAAA==.Logarth:BAAALgAECgMJAwAAAA==.Longbrew:BAAALgADCgEJAQAAAA==.Loppsang:BAAALgAECgEJAQAAAA==.Lorcan:BAABLgAECn8jAAIbAAgJLxg9BQDaAQAbAAgJLxg9BQDaAQAAAA==.',
Lr='Lroye:BAAALgAFFAMJBAAAAA==.',
Ls='Lsdarko:BAAALgADCggJCQAAAA==.',
Lu='Luckyleet:BAAALgADCgQJBwAAAA==.Lucyfer:BAAALgAECgUJCgABLgAECgUJEQABAAAAAA==.Ludicrispeed:BAAALgADCgQJCgAAAA==.Luliak:BAABLgAFFH8KAAIJAAQJNSINAQClAQAJAAQJNSINAQClAQAAAA==.Lunabren:BAAALgAECgYJEQAAAA==.Lunamina:BAAALgADCgkJJgAAAA==.',
Ly='Lynvala:BAAALgADCgQJBQAAAA==.Lysdexíc:BAAALgAECggJEwAAAA==.',
['Lì']='Lìllith:BAAALgAECgYJEAABLgAECggJKAAWAOIaAA==.',
Ma='Majika:BAAALgADCgYJBQAAAA==.Mariophra:BAABLgAECn8WAAIGAAYJ8RysEADwAQAGAAYJ8RysEADwAQAAAA==.Marvelious:BAAALgAFFAEJAQAAAA==.Mattlen:BAAALgADCgYJCAAAAA==.Maxmugruith:BAAALgADCgQJBwAAAA==.',
Me='Meatshiéld:BAAALgAECgYJCgAAAA==.',
Mi='Midopamos:BAAALgADCgEJAQAAAA==.Misstorgo:BAAALgAECgMJAwAAAA==.',
Mo='Monfro:BAAALgAECgUJCgAAAA==.Moogatoo:BAAALgAECgYJBwAAAA==.Moonbane:BAABLgAECn8kAAIaAAgJaR0UAQBaAgAaAAgJaR0UAQBaAgAAAA==.Moonfanda:BAAALgADCgIJAgAAAA==.Moonmist:BAAALgADCgEJAQABLgAECgYJBwABAAAAAA==.',
Mu='Mumferd:BAAALgADCgQJBAAAAA==.',
My='Myaquean:BAAALgADCgQJCgAAAA==.Mystogan:BAAALgADCgUJCQAAAA==.Myth:BAAALgADCgUJBQAAAA==.',
Na='Nakeefa:BAAALgAECgYJEgAAAA==.Natsuu:BAABLgAECn8ZAAISAAgJkhr8FADqAQASAAgJkhr8FADqAQAAAA==.Naturewolf:BAABLgAECn8eAAIOAAgJWBbtBQCwAQAOAAgJWBbtBQCwAQAAAA==.',
Ne='Nekona:BAAALgAECgYJEAAAAA==.Neron:BAABLgAECn8oAAIWAAgJ4hr8FgADAgAWAAgJ4hr8FgADAgAAAA==.Nethertusk:BAABLgAECn8lAAMVAAgJsRXqGgDUAQAVAAgJsRXqGgDUAQAaAAIJYQPwWQBhAAAAAA==.',
Nh='Nhancecntrl:BAAALgAECgcJDgABLgAECggJGwAcAOMUAA==.',
Ni='Niany:BAAALgAECgIJAgAAAA==.Nightbréaker:BAAALgADCgcJFQAAAA==.Nilospite:BAAALgAECgYJDQABLgAFFAQJCQALAN8QAA==.Nimposter:BAABLgAECn8UAAIIAAYJwxOfSQAiAQAIAAYJwxOfSQAiAQAAAA==.',
Nj='Njoror:BAAALgADCgQJBAAAAA==.',
No='Noodle:BAAALgADCgEJAQAAAA==.Nottapally:BAAALgAECgcJCAAAAA==.',
Nu='Nullea:BAAALgAECgYJCAAAAA==.',
Ny='Nyxthos:BAAALgADCggJCAAAAA==.',
Ob='Obizi:BAAALgADCgcJBwAAAA==.',
Oc='Ocatarineta:BAAALgADCgIJAgAAAA==.',
Oo='Oopslol:BAAALgAECgYJBgAAAA==.',
Os='Osdavalmarro:BAAALgADCgYJGQAAAA==.',
Ot='Othaerion:BAABLgAECn8UAAIRAAgJtA+gEgDFAQARAAgJtA+gEgDFAQAAAA==.',
Ou='Outerlimits:BAABLgAECn8fAAIdAAcJgxqnBAANAgAdAAcJgxqnBAANAgAAAA==.',
Pa='Paindore:BAAALgAECgMJAwAAAA==.Pamboo:BAABLgAECn8mAAIRAAgJhxBPEADgAQARAAgJhxBPEADgAQAAAA==.',
Pe='Pearle:BAABLgAECn8eAAILAAgJPh25BgC6AQALAAgJPh25BgC6AQAAAA==.',
Ph='Phyg:BAAALgAECgQJBQAAAA==.',
Po='Pokimane:BAAALgADCggJDwAAAA==.Polyasap:BAAALgADCgQJBAAAAA==.',
Pr='Proximal:BAAALgAECgcJBwAAAA==.',
Pu='Pukka:BAAALgADCgcJEQABLgAECggJIAATAIIaAA==.Punk:BAAALgAFFAEJAQAAAA==.',
Qa='Qahnaarin:BAAALgADCgEJAQAAAA==.',
Ra='Rajax:BAAALgAECgEJAQAAAA==.Ramindizzle:BAABLgAECn8mAAIQAAgJxxIgBQCuAQAQAAgJxxIgBQCuAQAAAA==.Rangewolf:BAAALgADCgcJDgAAAA==.',
Re='Rejuvasap:BAABLgAECn8VAAMNAAcJ+htOKQC1AQANAAcJ+htOKQC1AQAMAAUJ3RzMGwChAQAAAA==.Reliri:BAAALgADCgMJAwAAAA==.Remlin:BAAALgADCgcJCAAAAA==.Retsall:BAAALgADCgUJBQAAAA==.Reâper:BAAALgAECgYJCgAAAA==.',
Ri='Rikal:BAAALgADCgQJCgAAAA==.',
Ro='Rook:BAABLgAECn8jAAIQAAgJyAbmCABJAQAQAAgJyAbmCABJAQAAAA==.Roye:BAACLgAFFH8JAAIWAAQJEwurFQApAQAWAAQJEwurFQApAQAuAAQKfx4AAhYACQlvHbYaAMkCABYACQlvHbYaAMkCAAAA.',
Ru='Ruffiyo:BAABLgAECn8dAAMZAAgJPRLDHQCAAQAZAAgJFxHDHQCAAQAYAAYJYhKDLQBfAQAAAA==.Rugrahfreaky:BAAALgAECgYJCwAAAA==.Rugrahh:BAABLgAECn8gAAIQAAkJdB4sDwDFAgAQAAkJdB4sDwDFAgAAAA==.Ruthen:BAAALgAECgMJAwAAAA==.Ruìn:BAAALgAECgMJAwAAAA==.',
Sa='Sabermore:BAAALgAECgQJCAAAAA==.Sabina:BAABLgAECn8kAAIHAAgJ0AbiHgAhAQAHAAgJ0AbiHgAhAQAAAA==.Sadako:BAAALgADCgkJDAABLgAECgUJEQABAAAAAA==.Sadness:BAAALgADCgkJLgAAAA==.Sadorick:BAAALgADCgkJLwAAAA==.Safira:BAAALgAECgQJBgABLgAECggJKAAWAOIaAA==.Sageguy:BAAALgADCggJGgAAAA==.Sango:BAABLgAECn8gAAMYAAgJYwynCwCCAQAYAAgJYwynCwCCAQAZAAQJ2gKAwQB8AAAAAA==.Savagelykill:BAAALgAECgQJBgAAAA==.',
Sc='Scotch:BAABLgAECn8eAAMWAAgJxBodFwACAgAWAAgJxBodFwACAgAeAAIJcRHGMQCHAAAAAA==.Scotchnwater:BAAALgAECgUJBQAAAA==.Scrubyheals:BAAALgADCgQJBwAAAA==.',
Sh='Shadowcrwlr:BAAALgAECgMJBAAAAA==.Shadowlock:BAAALgAECggJEwAAAA==.Shadowmane:BAAALgADCgQJBAAAAA==.Shamangroo:BAAALgADCgYJBgABLgADCgcJDgABAAAAAA==.Shamsham:BAAALgADCgIJAgAAAA==.Shivalry:BAAALgADCgkJCwAAAA==.Shmiggy:BAAALgAECgEJAQAAAA==.',
Si='Silverywolfe:BAAALgADCgkJLwAAAA==.Simony:BAAALgAECgUJEQAAAA==.Sinton:BAAALgADCgIJAgAAAA==.',
Sk='Skorpyoh:BAAALgADCgYJBgAAAA==.Skovak:BAAALgAECgYJDgAAAA==.',
So='Soggy:BAAALgAECgcJBwAAAA==.Sorayae:BAABLgAECn8gAAITAAgJghr0EwA/AgATAAgJghr0EwA/AgAAAA==.',
Sp='Specialk:BAAALgADCggJHwAAAA==.',
St='Stoo:BAAALgADCgkJHAAAAA==.Stormkissed:BAAALgAECgMJAwAAAA==.',
Su='Sunil:BAABLgAECn8eAAITAAgJWBNFCwDwAQATAAgJWBNFCwDwAQAAAA==.Suviqhabo:BAAALgAECgcJDQAAAA==.',
Sv='Svala:BAAALgADCgYJBgAAAA==.',
Sy='Syclone:BAABLgAECn8eAAIFAAgJNyHJAQCpAgAFAAgJNyHJAQCpAgAAAA==.Syladen:BAAALgAECgYJEgAAAA==.Syleste:BAAALgAECgQJBAABLgAECggJHgAFADchAA==.',
Ta='Tahwe:BAAALgADCgUJBQAAAA==.Tattianna:BAAALgADCgcJDgAAAA==.Tavendar:BAAALgAECgMJAwABLgAECgkJIAAGAO8RAA==.Taírn:BAAALgAECgQJDgAAAA==.',
Te='Techie:BAAALgAECgYJBgAAAA==.Terradactyl:BAAALgADCgMJAwAAAA==.',
Th='Thunderslate:BAAALgAECgUJBgAAAA==.Thôrin:BAAALgADCgkJFQAAAA==.',
Ti='Tigerlillee:BAAALgADCgcJDQAAAA==.Tigreth:BAABLgAECn8jAAMWAAgJ8BI+LgCJAQAWAAgJzxI+LgCJAQAeAAIJlhSrNgBoAAAAAA==.Timotheus:BAAALgADCgcJEAAAAA==.',
To='Tonï:BAAALgADCggJCAAAAA==.',
Tr='Tragik:BAABLgAECn8fAAIfAAgJZwz4BgCTAQAfAAgJZwz4BgCTAQAAAA==.',
Tt='Ttrouble:BAAALgADCgUJBQAAAA==.',
Tu='Tuugadark:BAABLgAECn8nAAIVAAgJYR32EAAeAgAVAAgJYR32EAAeAgAAAA==.',
Ul='Ulyaoth:BAABLgAECn8WAAIVAAYJ7gJ1hABxAAAVAAYJ7gJ1hABxAAAAAA==.',
Un='Unnerfable:BAAALgAECgQJBgAAAA==.',
Uy='Uy:BAAALgAECgYJDwAAAA==.',
Va='Valakha:BAAALgAECgQJCQAAAA==.Valkyrie:BAAALgAECgQJBQAAAA==.',
Ve='Vedros:BAAALgADCgQJBwAAAA==.Velowin:BAAALgADCgcJBwAAAA==.',
Vi='Viktoros:BAAALgAECgIJAgAAAA==.Violetra:BAAALgADCgMJAwAAAA==.',
Vo='Vorcan:BAAALgADCgQJBAAAAA==.Vorukh:BAAALgAECgYJDwAAAA==.',
Vr='Vrave:BAAALgADCgQJBQAAAA==.',
Vy='Vyhlet:BAAALgADCgkJLwABLgAECggJJAAGAG0cAA==.',
Wa='Warriorgroo:BAAALgADCgcJDgAAAA==.',
We='Wendish:BAAALgAECgEJBgAAAA==.Wertyda:BAAALgAECgcJEAAAAA==.',
Wh='Whácker:BAAALgAECggJEwABLgAECgQJDgABAAAAAA==.',
Wi='Wickedslicks:BAABLgAECn8cAAINAAcJOx6FCAAJAgANAAcJOx6FCAAJAgAAAA==.Wildthangg:BAAALgAECgIJAgAAAA==.',
Wo='Wooddchipper:BAAALgADCgYJBgAAAA==.',
Wr='Wreckshop:BAABLgAECn8XAAIIAAgJiBrSHwDIAQAIAAgJiBrSHwDIAQAAAA==.',
Wt='Wtfoxtrot:BAAALgADCgkJDAAAAA==.',
Xa='Xalafeet:BAAALgADCgYJBgAAAA==.',
Xe='Xenøcide:BAAALgAECgcJEwAAAA==.',
Xx='Xxlockz:BAAALgAECgYJDQAAAA==.Xxpallyz:BAAALgAECgEJAgABLgAECgYJDQABAAAAAA==.',
Yi='Yinger:BAAALgADCgcJEAAAAA==.Yinglang:BAAALgADCgEJAQAAAA==.Yingling:BAABLgAECn8iAAIIAAgJKRjVRwAcAgAIAAgJKRjVRwAcAgAAAA==.',
Yo='Yohh:BAAALgAECgMJBAAAAA==.',
Yu='Yukara:BAAALgADCgYJBgAAAA==.Yuriko:BAABLgAECn8kAAIgAAgJ6hEQEQCZAQAgAAgJ6hEQEQCZAQAAAA==.',
Za='Zaidan:BAAALgADCgcJDgAAAA==.Zanpaktu:BAAALgAECgEJAgAAAA==.Zaraha:BAAALgADCgEJAQAAAA==.Zata:BAAALgAECgUJBgAAAA==.',
Ze='Zeref:BAAALgAECgYJBgAAAA==.Zeur:BAAALgAECgEJAQAAAA==.Zevgrip:BAAALgAECgQJBQAAAA==.',
Zh='Zhia:BAAALgAECgQJBQAAAA==.',
Zi='Zippitydooda:BAAALgADCgQJBAABLgAECgYJBwABAAAAAA==.',
Zo='Zodiacc:BAABLgAECn8nAAIPAAgJmRr5AwDzAQAPAAgJmRr5AwDzAQAAAA==.Zornhealer:BAAALgADCggJEAABLgAECgMJBQABAAAAAA==.',
['Zö']='Zölä:BAAALgADCgMJAwABLgADCgkJCQABAAAAAA==.',
['Ât']='Âtomic:BAAALgADCgYJAgABLgAECgQJDgABAAAAAA==.',
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
