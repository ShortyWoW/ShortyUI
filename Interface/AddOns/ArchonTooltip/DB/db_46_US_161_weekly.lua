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

local lookup = {'Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Paladin-Retribution','Rogue-Subtlety','Mage-Arcane','Druid-Balance','Unknown-Unknown','DemonHunter-Vengeance','Warrior-Fury','Priest-Holy','Shaman-Restoration','Shaman-Elemental','Monk-Mistweaver','Hunter-Survival','Hunter-Marksmanship','Hunter-BeastMastery','Mage-Frost','Druid-Restoration','Warrior-Protection','DemonHunter-Devourer','Paladin-Holy','Shaman-Enhancement','DemonHunter-Havoc','Druid-Feral','Priest-Discipline','DeathKnight-Unholy','Priest-Shadow','Druid-Guardian','Evoker-Preservation','DeathKnight-Blood','Mage-Fire','Evoker-Augmentation','Evoker-Devastation',}
local provider = {region='US',realm='Muradin',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aandra:BAABLgAECn8jAAQBAAkJ4R7mFwDFAgABAAkJgx7mFwDFAgACAAIJGxY7HACRAAADAAEJBAP2fQAeAAAAAA==.',
Ab='Abc:BAAALgAECgYJCgAAAA==.',
Ad='Adelyy:BAAALgAECgEJAQAAAA==.',
Ae='Aeliena:BAAALgADCggJIgAAAA==.Aenstar:BAAALgADCgMJAwAAAA==.',
Ag='Agwyon:BAABLgAECn8bAAIEAAcJyRiuRQA5AQAEAAcJyRiuRQA5AQAAAA==.',
Ai='Aithis:BAEALgAECgQJDgAAAA==.',
Al='Alerion:BAABLgAECn8XAAIFAAgJZBZRCADqAQAFAAgJZBZRCADqAQAAAA==.Allan:BAABLgAECn8gAAIGAAgJrSCwAABgAgAGAAgJrSCwAABgAgAAAA==.',
Am='Amaneeda:BAABLgAECn8WAAIHAAYJVgwaHwAEAQAHAAYJVgwaHwAEAQAAAA==.Amazonia:BAAALgADCgkJFAAAAA==.Amphi:BAAALgADCgMJAwABLgAECgUJCAAIAAAAAA==.Amphibibi:BAAALgAECgUJCAAAAA==.Amphoo:BAAALgAECgMJBAAAAA==.',
An='Andúril:BAAALgAECgYJBgAAAA==.Angyfabio:BAABLgAECn8UAAIJAAUJ7CPiBACaAQAJAAUJ7CPiBACaAQAAAA==.Antagonis:BAAALgAECgYJDwAAAA==.',
Ap='Apexchi:BAAALgAECgMJBQAAAA==.Apeximmortal:BAAALgAECgYJAwAAAA==.Apexlight:BAAALgAECgcJDgAAAA==.',
Ar='Arganos:BAABLgAECn8gAAIKAAgJgiYFCgAPAwAKAAgJgiYFCgAPAwAAAA==.Arisiana:BAAALgADCgYJCwAAAA==.Arkburn:BAAALgAECgUJDgAAAA==.Artherus:BAAALgADCgEJAQAAAA==.',
At='Athen:BAAALgADCgkJDwAAAA==.Atheîst:BAABLgAECn8jAAILAAgJdCXMAQBaAwALAAgJdCXMAQBaAwAAAA==.Atmos:BAAALgAECgEJAQAAAA==.Atsuni:BAABLgAECn8kAAMMAAcJuB4PDgAOAgAMAAcJuB4PDgAOAgANAAIJbRAXTAA8AAAAAA==.',
Au='Aurite:BAAALgAFFAUJEAAAAQ==.',
Av='Aveldea:BAAALgAECggJEAAAAA==.Aventon:BAAALgADCggJCwABLgAECggJIAAKAIImAA==.',
Az='Azalanasath:BAAALgADCgMJAwAAAA==.Azrand:BAAALgAECgYJEQAAAA==.',
Ba='Baconlittle:BAABLgAECn8YAAIOAAYJZBU1EwB/AQAOAAYJZBU1EwB/AQAAAA==.Baelanoth:BAAALgAECgYJDQAAAA==.Bakunarreia:BAAALgAECgEJAQAAAA==.Balkazaar:BAAALgAECgcJBwAAAA==.Bammbamm:BAABLgAECn8ZAAIEAAYJxAe3YADzAAAEAAYJxAe3YADzAAAAAA==.Banewreak:BAABLgAECn8eAAIBAAcJsxQxXgCuAQABAAcJsxQxXgCuAQAAAA==.Banu:BAAALgADCgEJAQAAAA==.Baradin:BAAALgADCgUJBQAAAA==.Barind:BAABLgAECn8gAAQPAAgJBxtJCADgAQAQAAcJIxoMJQD8AQAPAAcJrRdJCADgAQARAAIJuRrUnwCPAAAAAA==.',
Bd='Bdawg:BAAALgAECgMJBgAAAA==.',
Be='Benneel:BAAALgADCgcJBwAAAA==.Betrayer:BAAALgAECgQJBgAAAA==.Beve:BAAALgADCgUJBQAAAA==.',
Bi='Biggydtauren:BAAALgADCgUJBAAAAA==.Bigkruu:BAAALgADCgYJBgAAAA==.Biqdonk:BAAALgAECgUJCQAAAA==.',
Bl='Bleak:BAAALgADCggJCwAAAA==.Blindpenzu:BAAALgAECgMJBQAAAA==.',
Bo='Bobo:BAAALgAECgQJBQAAAA==.Boomerkillz:BAAALgAECgUJBQAAAA==.Bossbeast:BAAALgADCgcJDAABLgADCgYJCwAIAAAAAA==.Bossguy:BAAALgADCgYJCwAAAA==.Bossmonk:BAAALgADCgYJCgAAAA==.',
['Bú']='Búbblés:BAAALgAECgUJBwAAAA==.',
Ca='Caatia:BAAALgADCggJCAAAAA==.Calintha:BAAALgADCgcJDwAAAA==.Carryharder:BAAALgAECgEJAQABLgAECgYJHQABAOMXAA==.Carthel:BAABLgAECn8fAAISAAgJISBzCwCMAgASAAgJISBzCwCMAgAAAA==.Carthell:BAAALgAECgIJAgAAAA==.Cathedryal:BAAALgADCgYJBgAAAA==.',
Ce='Cerrydwyn:BAAALgADCgkJCQAAAA==.',
Ch='Chasseresse:BAAALgADCgkJDwAAAA==.Cherry:BAAALgADCgQJBAAAAA==.Chimarr:BAEBLgAECn8cAAITAAgJEiJVBADmAgATAAgJEiJVBADmAgAAAA==.Chosso:BAAALgADCgUJCQAAAA==.',
Cl='Clantis:BAAALgADCgMJAwAAAA==.',
Co='Coldsploder:BAABLgAECn8aAAISAAgJnROjJgDMAQASAAgJnROjJgDMAQAAAA==.',
Cr='Crackmonkéy:BAAALgAECgcJEQAAAA==.Cranknspank:BAAALgADCgUJBQAAAA==.Cronoz:BAABLgAECn8bAAMMAAYJfAjbWQAhAQAMAAYJfAjbWQAhAQANAAYJfAe5KQDeAAAAAA==.Crotchshot:BAAALgAECgYJCgAAAA==.Crushbone:BAAALgADCgUJBQAAAA==.',
Cu='Cursess:BAABLgAECn8rAAIBAAgJ5CFuBgCmAgABAAgJ5CFuBgCmAgAAAA==.',
['Có']='Cózmik:BAAALgAECgUJDgAAAA==.',
Da='Dace:BAAALgAECgEJAQAAAA==.Daliela:BAAALgAECgYJDgAAAA==.Dalya:BAAALgADCgcJCQAAAA==.Dander:BAAALgADCgMJAwAAAA==.Dani:BAAALgAECgEJAgAAAA==.Darkage:BAAALgADCgEJAQAAAA==.Darkfiff:BAAALgADCgQJBAAAAA==.Darkängal:BAAALgAECgUJDgAAAA==.Dayel:BAAALgAECgQJBwAAAA==.',
De='Deathnorris:BAAALgAECgEJAQAAAA==.Dekard:BAAALgAECggJDwAAAA==.Dekariusly:BAAALgADCgUJCgABLgAECggJDwAIAAAAAA==.Demonspookie:BAAALgADCgMJAwABLgAECgIJAwAIAAAAAA==.Destinÿ:BAABLgAECn8ZAAIUAAYJCRGOFADnAAAUAAYJCRGOFADnAAAAAA==.Devourer:BAABLgAECn8UAAIVAAYJJBueHQCBAQAVAAYJJBueHQCBAQAAAA==.',
Di='Disploder:BAAALgAECgcJEAAAAA==.Dist:BAAALgAECgYJAwAAAA==.',
Do='Doctafuzz:BAAALgAECgQJBQAAAA==.',
Dr='Drakentales:BAAALgADCgUJCAAAAA==.Drawnn:BAAALgAECgEJAQAAAA==.Drawwn:BAAALgAECgEJAQAAAA==.Dreathhammer:BAABLgAECn8aAAIWAAgJWiDTFgBbAgAWAAgJWiDTFgBbAgAAAA==.Dryad:BAAALgAECgQJBAABLgAFFAUJEQAWALAeAA==.',
Du='Dunadin:BAAALgAECgYJDgABLgAECgcJHQAJAMQlAA==.Dundyrn:BAABLgAECn8dAAIJAAcJxCUXAQCJAgAJAAcJxCUXAQCJAgAAAA==.',
Dy='Dynarc:BAAALgADCgEJAQABLgAECgcJHQAJAMQlAA==.',
Ec='Ecks:BAAALgAECgMJAwABLgAFFAMJBwAUAEIUAA==.',
El='Elememetal:BAABLgAECn8fAAINAAgJzxfuJwDUAQANAAgJzxfuJwDUAQAAAA==.',
En='Enigmä:BAAALgAECgEJAQAAAA==.',
Fa='Fanmir:BAAALgADCgQJBAAAAA==.Faultless:BAAALgADCggJDQAAAA==.',
Fe='Felbrand:BAAALgAECgEJAQAAAA==.Feloth:BAAALgADCgMJBQAAAA==.Felruby:BAAALgADCgEJAQAAAA==.Fengg:BAABLgAECn8YAAIMAAcJRQk/WQAjAQAMAAcJRQk/WQAjAQAAAA==.Fenix:BAAALgADCgEJAgAAAA==.',
Fi='Filbert:BAAALgAECgcJEQAAAA==.',
Fl='Flyttanth:BAAALgADCgMJBgAAAA==.',
Fo='Fomy:BAAALgAECgEJAQAAAA==.Foodvendor:BAAALgAECgEJAQABLgAECgQJBwAIAAAAAA==.',
Fr='Frostynaps:BAAALgAECgYJCQAAAA==.',
['Fá']='Fálola:BAABLgAECn8rAAMMAAgJkBTgKADsAQAMAAgJkBTgKADsAQANAAYJegKtNQCeAAAAAA==.',
Ga='Gamblex:BAAALgAECgMJBAAAAA==.Garviel:BAAALgAECgYJDgAAAA==.',
Ge='Geethatlock:BAAALgAECgQJCQAAAA==.',
Gh='Ghlaircan:BAAALgADCgkJCQAAAA==.',
Gi='Gimleia:BAAALgAECgMJBAAAAA==.',
Gl='Glanth:BAAALgAECgcJDgAAAA==.',
Go='Gorgonzolas:BAAALgAECgQJBAAAAA==.',
Gr='Gravewake:BAAALgADCgcJDwAAAA==.Grebeci:BAAALgADCgMJAwAAAA==.Greensoul:BAAALgAECgYJEAAAAA==.Grogu:BAAALgAECgYJEQAAAA==.Gromnah:BAAALgADCgIJAgAAAA==.Gruxx:BAAALgAECgEJAQAAAA==.',
Gu='Gundyr:BAAALgADCgkJHgAAAA==.',
He='Helkyrie:BAAALgADCgcJIgAAAA==.Helleer:BAAALgADCgQJBAAAAA==.Hexappeal:BAAALgADCgcJEAAAAA==.',
Hi='Hikdh:BAAALgAECgMJAwABLgAECggJFQAXAOsQAA==.Hiksham:BAABLgAECn8VAAMXAAgJ6xD3BQCxAQAXAAcJrA/3BQCxAQANAAYJPQoeJgD0AAAAAA==.',
Ho='Holycheeze:BAAALgADCgcJCgAAAA==.Holyhoof:BAAALgADCgMJAwAAAA==.Honeybutter:BAAALgADCgEJAQABLgAECgYJHQABAOMXAA==.Hotsanddots:BAAALgAECgEJAQAAAA==.',
Hu='Huuan:BAAALgADCgIJAwABLgAECgUJDwAIAAAAAA==.',
Ih='Ihealzufool:BAAALgAECgYJEAAAAA==.',
Il='Illistia:BAAALgADCgYJBgAAAA==.',
Im='Imded:BAAALgAECgQJBAAAAA==.',
Ja='Jalene:BAAALgAECgUJCgAAAA==.Jargyn:BAAALgAECgYJDQAAAA==.Jarlyss:BAAALgAECgYJCwABLgAECgYJDQAIAAAAAA==.Javieraa:BAABLgAECn8YAAIVAAgJcBhxQgDqAQAVAAgJcBhxQgDqAQAAAA==.',
Jd='Jdai:BAAALgAECgUJDwAAAA==.',
Ju='Juglight:BAAALgAECgQJBAAAAA==.Jugtonic:BAAALgAECgIJAgAAAA==.',
Ka='Kaelithra:BAAALgADCgYJBgAAAA==.',
Ke='Kenny:BAAALgADCgEJAQAAAA==.',
Kh='Khaiv:BAACLgAFFH8RAAIVAAUJBiFQBwCAAQAVAAUJBiFQBwCAAQAuAAQKfy4AAhUACQkRI2MEAIEDABUACQkRI2MEAIEDAAAA.Khanen:BAAALgAECgMJAwAAAA==.',
Ki='Kielann:BAABLgAECn8ZAAIYAAYJ7Q1CFAAIAQAYAAYJ7Q1CFAAIAQAAAA==.Kimmi:BAAALgADCggJGAAAAA==.Kinzen:BAABLgAECn8hAAIXAAcJIxywCQA6AgAXAAcJIxywCQA6AgAAAA==.',
Ku='Kulthosano:BAABLgAECn8dAAIZAAYJAyEgDQDmAQAZAAYJAyEgDQDmAQAAAA==.',
La='Labubu:BAAALgAECgYJEQAAAA==.Lasadin:BAAALgADCgEJAQAAAA==.Lawhityy:BAAALgADCgEJAgABLgAECgcJHAAaALITAA==.',
Le='Lechwe:BAAALgAECgUJDgAAAA==.Legonator:BAAALgAECgUJBgAAAA==.',
Li='Lichmajor:BAABLgAECn8cAAIbAAgJihl5HwDKAQAbAAgJihl5HwDKAQAAAA==.Lilarri:BAAALgAECgMJAwAAAA==.Lilleymage:BAAALgADCgEJAQAAAA==.',
Lo='Lopus:BAAALgADCgcJEQAAAA==.Lostchi:BAAALgAECgYJEwAAAA==.Lovepet:BAABLgAECn8dAAMRAAcJyhVLGgDDAQARAAcJyhVLGgDDAQAQAAYJCQdQUwD+AAAAAA==.',
Lt='Ltlesunshine:BAAALgADCgYJBgAAAA==.',
Lu='Lucy:BAAALgADCgEJAQAAAA==.Lunal:BAABLgAECn8mAAISAAkJyR7dKgDHAgASAAkJyR7dKgDHAgAAAA==.',
Ly='Lyda:BAABLgAECn8ZAAITAAYJixwSFgDTAQATAAYJixwSFgDTAQAAAA==.',
Ma='Magice:BAAALgAECgMJBAAAAA==.Malibubarbie:BAABLgAECn8YAAILAAYJWg0eHAAkAQALAAYJWg0eHAAkAQAAAA==.Maneevent:BAAALgAECggJEQAAAA==.Mariscylla:BAAALgAECgEJAQAAAA==.Materesa:BAABLgAECn8cAAMaAAcJshOoDwCTAQAaAAcJshOoDwCTAQAcAAYJbgzzNQA8AQAAAA==.Maysty:BAABLgAECn8cAAIRAAcJ/AbHOgAoAQARAAcJ/AbHOgAoAQAAAA==.',
Me='Melidra:BAAALgAECgEJAQAAAA==.Menapaws:BAACLgAFFH8MAAQZAAUJchp1AQBrAQAZAAQJ8Rl1AQBrAQAdAAEJhxPjBgA6AAAHAAEJAABgIgAAAAAuAAQKfxsAAxkACAkvJPgBAD4DABkACAkvJPgBAD4DAB0AAQkxIYgpAFQAAAAA.Meraxion:BAAALgAECgYJCAAAAA==.Meriel:BAABLgAECn8bAAILAAcJiQ2gFgBYAQALAAcJiQ2gFgBYAQAAAA==.',
Mi='Midnightstar:BAAALgAECgEJAQAAAA==.Milk:BAAALgAECgEJAQABLgAECgYJCgAIAAAAAA==.Mirabel:BAAALgAECgMJAwAAAA==.',
Mo='Monika:BAAALgAECgIJAgAAAA==.Monlee:BAAALgADCgQJBAAAAA==.Moonbayne:BAABLgAECn8aAAIHAAcJaBibHQATAgAHAAcJaBibHQATAgAAAA==.Mooszer:BAAALgAECgMJCgAAAA==.Morder:BAAALgADCgYJCgAAAA==.Moritz:BAAALgADCgcJDgAAAA==.',
Mu='Muaythighs:BAAALgAECgIJAwAAAA==.Mushu:BAABLgAECn8VAAIeAAgJgxIRBwDMAQAeAAgJgxIRBwDMAQAAAA==.',
Mv='Mvmt:BAAALgADCgYJBgAAAA==.',
My='Mycheeksclap:BAAALgAECgEJAQAAAA==.',
['Mà']='Màc:BAAALgADCgMJAwAAAA==.',
Na='Namielle:BAAALgADCgUJDAAAAA==.Nasta:BAAALgAECgQJBgAAAA==.',
Ne='Nepharim:BAAALgADCgkJEgAAAA==.Nephlim:BAACLgAFFH8QAAMbAAUJ+RvoEQBaAQAbAAQJ+RvoEQBaAQAfAAEJAACtHgAAAAAuAAQKfywAAhsACQmqIcMGAGwDABsACQmqIcMGAGwDAAAA.',
Ni='Ninobrown:BAAALgAECgUJCwAAAA==.Niny:BAAALgAECgEJAgABLgAECgkJJgASAMkeAA==.Ninzerp:BAAALgAECgEJAQABLgAECgkJJgASAMkeAA==.Nizano:BAAALgAECgYJDwAAAA==.',
No='Noleyprays:BAAALgAECgEJAQABLgAECgMJBgAIAAAAAA==.Noryaa:BAAALgAECgYJDwAAAA==.Notabat:BAAALgADCgUJBQAAAA==.Notavoidelf:BAAALgADCgMJAwAAAA==.',
Nu='Nuadå:BAAALgAECgYJEQAAAA==.',
Og='Oggi:BAAALgADCgcJBwAAAA==.',
Om='Om:BAAALgAECgUJCgAAAA==.',
On='Onthrox:BAAALgADCgEJAQAAAA==.',
Oo='Oorlian:BAAALgAECgMJBAAAAA==.',
Op='Opheleia:BAAALgADCgIJAgAAAA==.',
Or='Orallius:BAEALgADCgEJAQABLgAECggJHAATABIiAA==.',
Po='Pogo:BAABLgAECn8dAAIPAAgJViSSAgAUAwAPAAgJViSSAgAUAwAAAA==.Pogolock:BAAALgADCgEJAgABLgAECggJHQAPAFYkAA==.',
Pr='Pricedd:BAAALgADCgQJBAAAAA==.Prozac:BAAALgAECgMJBgAAAA==.',
Ps='Psiberian:BAAALgAECgcJEgAAAA==.',
Ra='Ranoa:BAAALgADCgkJCQAAAA==.Rastapopulos:BAAALgADCgUJBQAAAA==.',
Re='Redmage:BAAALgADCgcJDwABLgAECgcJHQARAMoVAA==.Redrocket:BAAALgADCgYJBgAAAA==.Remixed:BAAALgAECgMJAwAAAA==.',
Ri='Rikaku:BAABLgAECn8cAAIRAAcJhBHZPgCzAQARAAcJhBHZPgCzAQAAAA==.',
Ro='Ronananna:BAAALgADCgkJDwABLgADCgMJAwAIAAAAAA==.Rosemery:BAAALgADCgkJFgAAAA==.',
['Rä']='Räpodac:BAABLgAECn8UAAIYAAYJ2QmqFgDsAAAYAAYJ2QmqFgDsAAAAAA==.',
Sa='Sagaba:BAAALgAECgUJCAAAAA==.Saphil:BAAALgADCgkJFAAAAA==.Saramus:BAAALgAECgEJAQAAAA==.',
Sc='Schizo:BAACLgAFFH8FAAIbAAIJoRb7TwCnAAAbAAIJoRb7TwCnAAAuAAQKfxoAAhsABwmsHu1AADUCABsABwmsHu1AADUCAAAA.Schmaladin:BAAALgADCgUJCAAAAA==.',
Se='Searena:BAAALgAECgEJAgAAAA==.Sefiroth:BAABLgAECn8fAAIVAAcJJg90KwA3AQAVAAcJJg90KwA3AQAAAA==.Selillea:BAAALgADCgMJAwAAAA==.Semarius:BAAALgADCgkJCgABLgAECgYJFgAYAGQhAA==.Semdorii:BAABLgAECn8WAAIYAAYJZCFFEwA8AgAYAAYJZCFFEwA8AgAAAA==.Sephywrath:BAABLgAECn8nAAIgAAgJSRiNAwDTAQAgAAgJSRiNAwDTAQAAAA==.Seralith:BAABLgAECn8WAAIbAAgJqRz9DwA+AgAbAAgJqRz9DwA+AgAAAA==.Seranight:BAABLgAECn8oAAIfAAgJVCVpAQB8AgAfAAgJVCVpAQB8AgAAAA==.Seven:BAAALgAECgIJBAABLgAECgYJHQABAOMXAA==.Sevenpaws:BAAALgAECgEJAQABLgAECggJIwALAHQlAA==.',
Sh='Shadowchi:BAAALgADCgkJDwAAAA==.Shaidon:BAAALgADCgkJEAAAAQ==.Shaly:BAAALgAECgYJEQAAAA==.Shattwrath:BAAALgAECgEJAQAAAA==.Shirohige:BAAALgAECgMJBAAAAA==.Shylan:BAAALgAECgIJAwAAAA==.',
Si='Simmer:BAAALgADCgMJAwAAAA==.',
Sm='Smasha:BAAALgAECgQJBwAAAA==.',
Sn='Snayre:BAABLgAECn8cAAIPAAcJ/xpKBwD1AQAPAAcJ/xpKBwD1AQAAAA==.Snipêr:BAAALgAECgEJAgAAAA==.Snowlia:BAABLgAECn8WAAIMAAcJyBPtNQCrAQAMAAcJyBPtNQCrAQAAAA==.',
So='Soularis:BAAALgAECgIJAgAAAA==.',
Sp='Spectrê:BAAALgADCgMJAwAAAA==.Spiralpad:BAAALgADCgYJCgABLgAECggJGwAEAMkYAA==.Spybro:BAAALgAECgIJAwAAAA==.',
Sq='Squidtechnic:BAAALgAECgMJBwAAAA==.',
St='Stalkingwolf:BAAALgAECgYJEQAAAA==.',
Su='Suz:BAAALgADCgEJAQAAAA==.Suzuya:BAAALgADCgIJAgAAAA==.',
Sy='Sylailia:BAABLgAECn8cAAIHAAcJsBkjDgCsAQAHAAcJsBkjDgCsAQAAAA==.Syleta:BAAALgADCgMJBAAAAA==.',
Ta='Tamatoa:BAAALgAECgEJAQABLgAECgYJFQADAJEUAA==.',
Tc='Tcon:BAAALgAECgcJDgAAAA==.',
Te='Tearany:BAAALgADCgUJBgAAAA==.',
Th='Thissa:BAABLgAECn8eAAMHAAcJwB0kCgDtAQAHAAcJwB0kCgDtAQAZAAEJSBm0MwAzAAAAAA==.Thundarah:BAAALgADCgYJBgAAAA==.Thundruid:BAAALgADCgUJCgAAAA==.Thuniellas:BAAALgADCggJEQAAAA==.',
Ti='Tiarcis:BAABLgAECn8UAAIRAAcJ1w7pJwB4AQARAAcJ1w7pJwB4AQAAAA==.',
To='Toeknee:BAAALgAECgMJAwAAAA==.Totemsalot:BAAALgAECgcJDAAAAA==.',
Tr='Treesummoner:BAABLgAECn8bAAQDAAgJIRNyLAAMAQABAAcJrxIbmgAkAQADAAUJ6wpyLAAMAQACAAMJoQvQGgCgAAAAAA==.Trialboost:BAAALgADCggJCQAAAA==.Tritanks:BAABLgAECn8fAAIJAAcJKh/JAwDMAQAJAAcJKh/JAwDMAQAAAA==.Troy:BAAALgAECgIJAwAAAA==.',
Tu='Tutsee:BAAALgADCgcJEgAAAA==.',
['Tå']='Tåbi:BAAALgADCgcJCwABLgAECgUJBQAIAAAAAA==.',
Un='Unbantam:BAAALgAECgUJBgAAAA==.',
Va='Valeq:BAAALgADCgkJCAAAAA==.Valeyka:BAAALgAECgYJDwAAAA==.Vasilia:BAABLgAECn8ZAAIfAAYJnhwNCQCHAQAfAAYJnhwNCQCHAQAAAA==.',
Ve='Velanna:BAAALgADCggJBAAAAA==.',
Vi='Viego:BAAALgAECgMJBAAAAA==.',
Vo='Voclus:BAAALgAECgMJBgAAAA==.',
Wa='Warptouched:BAAALgADCgYJBgAAAA==.',
Wh='Whatapal:BAAALgAECgIJAgAAAA==.',
Wi='Wightranger:BAAALgADCgYJCwAAAA==.Wightwarrior:BAAALgADCgcJCgAAAA==.',
Wu='Wuwindtang:BAAALgAECgUJBQAAAA==.',
Xa='Xalatoes:BAAALgADCgQJBAAAAA==.',
Xe='Xeniuz:BAAALgADCgMJAwAAAA==.',
Xi='Xianfei:BAAALgAECgIJAwAAAA==.Xiles:BAAALgAECgUJDgAAAA==.',
Za='Zachxd:BAABLgAECn8eAAIVAAcJzRmcHACIAQAVAAcJzRmcHACIAQABLgAFFAIJBQAbAKEWAA==.Zanthe:BAAALgAECgMJBAAAAA==.Zapanese:BAAALgADCgIJAgAAAA==.Zaptism:BAABLgAECn8YAAMLAAgJ5BteCwCaAgALAAgJ5BteCwCaAgAaAAMJSA0rQgCiAAAAAA==.Zapunch:BAAALgADCgEJAQAAAA==.Zarissaa:BAAALgADCgkJEAAAAA==.Zatha:BAAALgADCgYJBgAAAA==.',
Ze='Zerowins:BAAALgADCgcJCAAAAA==.',
Zh='Zhanbrew:BAAALgADCgYJBgABLgAECgUJFAAJAOwjAA==.Zhanfury:BAAALgAFFAEJAQABLgAECgUJFAAJAOwjAA==.',
Zi='Zinder:BAABLgAECn8XAAMhAAcJ8gOnKADLAAAhAAcJ2QOnKADLAAAiAAEJJgP3FAAoAAAAAA==.Zipit:BAABLgAECn8eAAIDAAgJJBVWAwC9AQADAAgJJBVWAwC9AQAAAA==.',
Zy='Zyae:BAAALgAECgEJAgAAAA==.Zyrinthia:BAAALgADCgYJBgAAAA==.',
['Æn']='Ænder:BAAALgADCgMJAwABLgAECgYJDQAIAAAAAA==.',
['Öb']='Öboron:BAABLgAECn8lAAQQAAkJYBGQKgDUAQAQAAgJVhCQKgDUAQARAAYJKRUzUwBvAQAPAAgJ0AhFFwBXAQAAAA==.',
['Üz']='Üz:BAAALgAECgYJEgAAAA==.',
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
