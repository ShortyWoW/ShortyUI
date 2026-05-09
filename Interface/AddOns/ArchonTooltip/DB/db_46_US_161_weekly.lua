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

local lookup = {'Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Paladin-Retribution','Rogue-Subtlety','Mage-Arcane','Druid-Balance','Unknown-Unknown','DemonHunter-Vengeance','Warrior-Fury','DemonHunter-Devourer','Priest-Holy','Shaman-Restoration','Shaman-Elemental','Warrior-Arms','Monk-Mistweaver','Hunter-Survival','Hunter-Marksmanship','Hunter-BeastMastery','Mage-Frost','Druid-Restoration','Priest-Discipline','Priest-Shadow','Warrior-Protection','Paladin-Holy','Shaman-Enhancement','DemonHunter-Havoc','Druid-Feral','DeathKnight-Unholy','Druid-Guardian','Evoker-Preservation','DeathKnight-Blood','Mage-Fire','Evoker-Augmentation','Evoker-Devastation',}
local provider = {region='US',realm='Muradin',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aandra:BAABLgAECn8qAAQBAAkJ4h7kFwDFAgABAAkJhB7kFwDFAgACAAIJGxY+HACRAAADAAEJBAP4fQAeAAAAAA==.',
Ab='Abc:BAAALgAECgYJCgAAAA==.',
Ad='Adelyy:BAAALgAECgEJAQAAAA==.',
Ae='Aeliena:BAAALgAECgIJAgAAAA==.Aenstar:BAAALgADCgMJAwAAAA==.',
Ag='Agwyon:BAABLgAECn8eAAIEAAcJqRpzTABgAQAEAAcJqRpzTABgAQAAAA==.',
Ai='Aithis:BAEALgAECgQJDgAAAA==.',
Al='Alerion:BAABLgAECn8fAAIFAAgJEhmoCQAGAgAFAAgJEhmoCQAGAgAAAA==.Allan:BAABLgAECn8iAAIGAAkJKB+KAACrAgAGAAkJKB+KAACrAgAAAA==.',
Am='Amaneeda:BAABLgAECn8cAAIHAAgJugsVGwBdAQAHAAgJugsVGwBdAQAAAA==.Amazonia:BAAALgAECgEJAQAAAA==.Aminea:BAAALgADCgQJBAAAAA==.Amphi:BAAALgADCgMJAwABLgAECgUJCAAIAAAAAA==.Amphibibi:BAAALgAECgUJCAAAAA==.Amphoo:BAAALgAECgYJCAAAAA==.',
An='Andúril:BAAALgAECgYJBgAAAA==.Angyfabio:BAABLgAECn8bAAIJAAcJOB+UAwARAgAJAAcJOB+UAwARAgAAAA==.Angyrain:BAAALgADCgUJBQAAAA==.Antagonis:BAABLgAECn8VAAIDAAYJ1QxGDQD+AAADAAYJ1QxGDQD+AAAAAA==.',
Ap='Apexchi:BAAALgAECgMJBQAAAA==.Apeximmortal:BAAALgAECgYJAwAAAA==.Apexlight:BAAALgAECgcJDgAAAA==.Apexwar:BAAALgADCgMJAwAAAA==.',
Ar='Arashe:BAAALgAECgMJAwAAAA==.Arganos:BAABLgAECn8hAAIKAAgJoCbtAQAKAwAKAAgJoCbtAQAKAwAAAA==.Arisiana:BAAALgADCgYJCwAAAA==.Arkburn:BAABLgAECn8UAAILAAYJhgUudACxAAALAAYJhgUudACxAAAAAA==.Artherus:BAAALgADCgEJAQAAAA==.',
At='Athen:BAAALgADCgkJGAAAAA==.Atheîst:BAABLgAECn8rAAIMAAgJviXMAQBaAwAMAAgJviXMAQBaAwAAAA==.Atmos:BAAALgAECgEJAQAAAA==.Atsuni:BAABLgAECn80AAMNAAgJFR5YEgAlAgANAAcJuR5YEgAlAgAOAAYJvhLXJQAqAQAAAA==.Atulash:BAAALgADCgEJAQAAAA==.',
Au='Aurite:BAAALgAFFAUJEQAAAQ==.',
Av='Aveldea:BAAALgAECggJEAAAAA==.Aventon:BAAALgADCggJDAABLgAECggJIQAKAKAmAA==.',
Az='Azalanasath:BAAALgADCgMJAwAAAA==.Azrand:BAABLgAECn8XAAMPAAYJahirDAB2AQAPAAYJURirDAB2AQAKAAIJpRDpkwBvAAAAAA==.',
Ba='Baconlittle:BAABLgAECn8eAAIQAAYJ9RWLGQCCAQAQAAYJ9RWLGQCCAQAAAA==.Baelanoth:BAAALgAECgYJEwAAAA==.Bakunarreia:BAAALgAECgEJAQAAAA==.Balkazaar:BAAALgAECgcJBwAAAA==.Bammbamm:BAABLgAECn8gAAIEAAcJjAgfaQAbAQAEAAcJjAgfaQAbAQAAAA==.Banewreak:BAABLgAECn8oAAIBAAcJHxYTOwB7AQABAAcJHxYTOwB7AQAAAA==.Banu:BAAALgADCgEJAQAAAA==.Baradin:BAAALgADCgUJBQAAAA==.Barind:BAABLgAECn8iAAQRAAkJXRsBBwA9AgARAAgJjhgBBwA9AgASAAcJIxqPJAADAgATAAIJuRrPnwCPAAAAAA==.',
Bd='Bdawg:BAAALgAECgMJBgAAAA==.',
Be='Benneel:BAAALgADCgcJBwAAAA==.Betrayer:BAAALgAECgUJCwAAAA==.Beve:BAAALgADCgUJBQAAAA==.',
Bi='Biggydtauren:BAAALgADCgUJBAAAAA==.Bigkruu:BAAALgADCgYJBgAAAA==.Biqdonk:BAAALgAECgUJCQAAAA==.',
Bl='Bleak:BAAALgADCggJCwAAAA==.Blindpenzu:BAAALgAECgMJBQAAAA==.',
Bo='Bobo:BAAALgAECgQJBQAAAA==.Boomerkillz:BAAALgAECgUJBQAAAA==.Bossbeast:BAAALgADCgcJDAABLgADCgYJCwAIAAAAAA==.Bossdk:BAAALgADCgEJAQABLgADCgYJCwAIAAAAAA==.Bossguy:BAAALgADCgYJCwAAAA==.Bossmonk:BAAALgADCgcJEAAAAA==.',
Br='Brietta:BAAALgAECgEJAQAAAA==.',
['Bú']='Búbblés:BAAALgAECgUJBwAAAA==.',
Ca='Caatia:BAAALgAECgEJAQAAAA==.Calintha:BAAALgADCgcJDwAAAA==.Carryharder:BAAALgAECgEJAQABLgAECgcJHwABAOYWAA==.Carthel:BAABLgAECn8fAAIUAAgJMCAUEwCAAgAUAAgJMCAUEwCAAgAAAA==.Carthell:BAAALgAECgIJAgAAAA==.Cathedryal:BAAALgADCgYJBgAAAA==.',
Ce='Cerrydwyn:BAAALgADCgkJCQAAAA==.',
Ch='Chasseresse:BAAALgAECgEJAQAAAA==.Cherry:BAAALgADCgQJBAAAAA==.Chimarr:BAEBLgAECn8cAAIVAAgJFSIfBwDcAgAVAAgJFSIfBwDcAgAAAA==.Chosso:BAAALgADCgUJCQAAAA==.',
Cl='Clantis:BAAALgADCgMJAwAAAA==.',
Co='Coldsploder:BAABLgAECn8aAAIUAAgJnhMuNwDFAQAUAAgJnhMuNwDFAQAAAA==.',
Cr='Crackmonkéy:BAABLgAECn8ZAAQWAAgJmBgtFACgAQAWAAcJ6hMtFACgAQAMAAQJkhlQTwD7AAAXAAQJdBAzQQDvAAAAAA==.Cranknspank:BAAALgAECgEJAQAAAA==.Cronoz:BAABLgAECn8eAAMNAAgJqwrWWQAhAQANAAcJkgfWWQAhAQAOAAcJpAfQLQD/AAAAAA==.Crotchshot:BAAALgAECgYJEAAAAA==.Crushbone:BAAALgADCgUJBQAAAA==.',
Cu='Cursess:BAABLgAECn8xAAIBAAkJYCJmAwAaAwABAAkJYCJmAwAaAwAAAA==.',
['Có']='Cózmik:BAAALgAECgUJDgAAAA==.',
Da='Dace:BAAALgAECgEJAQAAAA==.Daliela:BAAALgAECgYJDgAAAA==.Dalya:BAAALgADCgcJCQAAAA==.Dander:BAAALgADCgMJAwAAAA==.Dani:BAAALgAECgEJAgAAAA==.Darkage:BAAALgADCgEJAQAAAA==.Darkfiff:BAAALgADCgQJBAAAAA==.Darkängal:BAAALgAECgUJDgAAAA==.Dayel:BAAALgAECgUJCAAAAA==.',
De='Deathnorris:BAAALgAECgIJAQAAAA==.Dekard:BAAALgAECggJDwAAAA==.Dekariusly:BAAALgAECgEJAQABLgAECggJDwAIAAAAAA==.Demonatrixx:BAAALgADCgQJBAAAAA==.Demonhugger:BAAALgAECgEJAgAAAA==.Demonspookie:BAAALgADCgMJAwABLgAECgkJHAACADoZAA==.Destinÿ:BAABLgAECn8gAAIYAAcJHxcuDQCQAQAYAAcJHxcuDQCQAQAAAA==.Devourer:BAABLgAECn8bAAILAAcJgRrtIADDAQALAAcJgRrtIADDAQAAAA==.',
Di='Disploder:BAAALgAECgcJEAAAAA==.Dist:BAAALgAECgYJBgAAAA==.',
Do='Doctafuzz:BAAALgAECgYJCwAAAA==.',
Dr='Drakentales:BAAALgADCgUJCAAAAA==.Drawnn:BAAALgAECgEJAQAAAA==.Drawwn:BAAALgAECgEJAgAAAA==.Dreathhammer:BAABLgAECn8cAAIZAAkJ0yDRFgBbAgAZAAkJ0yDRFgBbAgAAAA==.Drogo:BAAALgADCgIJAgAAAA==.Dryad:BAAALgAECgQJBAABLgAFFAYJFwAZAE0iAA==.',
Du='Dunadin:BAAALgAECgYJEwABLgAECggJJQAJAF0mAA==.Dundyrn:BAABLgAECn8lAAIJAAgJXSaFAAABAwAJAAgJXSaFAAABAwAAAA==.',
Dy='Dynarc:BAAALgADCgEJAQABLgAECggJJQAJAF0mAA==.',
Ec='Ecks:BAAALgAECgMJAwABLgAFFAQJCwAYAEUcAA==.',
El='Elememetal:BAABLgAECn8mAAIOAAkJyRfcCQA7AgAOAAkJyRfcCQA7AgAAAA==.',
En='Enigmä:BAAALgAECgIJAwAAAA==.',
Fa='Fanmir:BAAALgADCgQJBAAAAA==.Faultless:BAAALgADCggJDQAAAA==.',
Fe='Felbrand:BAAALgAECgEJAQAAAA==.Feloth:BAAALgADCgMJBQAAAA==.Felruby:BAAALgADCgEJAQAAAA==.Fengg:BAABLgAECn8dAAINAAcJXQvmRQDqAAANAAcJXQvmRQDqAAAAAA==.Fenix:BAAALgADCgEJAgAAAA==.',
Fi='Filbert:BAABLgAECn8YAAIHAAgJUCA3BQCYAgAHAAgJUCA3BQCYAgAAAA==.',
Fl='Flyttanth:BAAALgADCgMJBgAAAA==.',
Fo='Fomy:BAAALgAECgEJAQAAAA==.Foodvendor:BAAALgAECgEJAQABLgAECgQJDQAIAAAAAA==.',
Fr='Frostynaps:BAAALgAECgYJCQAAAA==.',
Fu='Funkdooby:BAAALgAECgEJAQAAAA==.',
['Fá']='Fálola:BAABLgAECn8sAAMNAAgJkhTeKADsAQANAAgJkhTeKADsAQAOAAYJewJcRACYAAAAAA==.',
Ga='Gamblex:BAAALgAECgMJBAAAAA==.Garviel:BAAALgAECgYJDgAAAA==.',
Ge='Geethatlock:BAAALgAECgQJDAAAAA==.',
Gh='Ghlaircan:BAAALgADCgkJCQAAAA==.',
Gi='Gimleia:BAAALgAECgQJCQAAAA==.',
Gl='Glanth:BAAALgAECgcJDgAAAA==.',
Go='Gorgonzolas:BAAALgAECgUJCAAAAA==.',
Gr='Gravewake:BAAALgADCgcJDwAAAA==.Grebeci:BAAALgADCgMJAwAAAA==.Greensoul:BAAALgAECgYJEAAAAA==.Grifflyn:BAAALgAECgEJAQAAAA==.Grogu:BAABLgAECn8XAAIUAAYJugpqeQAeAQAUAAYJugpqeQAeAQAAAA==.Gromnah:BAAALgADCgIJAgAAAA==.Gruxx:BAAALgAECgEJAgAAAA==.',
Gu='Gummies:BAAALgAECgEJAQAAAA==.Gundyr:BAAALgADCgkJHgAAAA==.',
Ha='Haranir:BAAALgAECgEJAQAAAA==.',
He='Helkyrie:BAAALgADCgcJIwAAAA==.Helleer:BAAALgADCgQJBAAAAA==.Hexappeal:BAAALgADCgcJEAAAAA==.',
Hi='Hikdh:BAAALgAECgMJAwABLgAECggJHAAaACEYAA==.Hiksham:BAABLgAECn8cAAMaAAgJIRi8BQDxAQAaAAgJIRi8BQDxAQAOAAYJSQrZMQDrAAAAAA==.',
Ho='Holycheeze:BAAALgADCgcJCgAAAA==.Holyhoof:BAAALgADCgMJBAAAAA==.Honeybutter:BAAALgADCgEJAQABLgAECgcJHwABAOYWAA==.Hotsanddots:BAAALgAECgcJCAAAAA==.',
Hu='Huuan:BAAALgAECgEJAQABLgAECgYJEwAIAAAAAA==.',
Ih='Ihealzufool:BAABLgAECn8SAAIXAAYJvhCkIQAyAQAXAAYJvhCkIQAyAQAAAA==.',
Il='Illistia:BAAALgADCgYJBgAAAA==.',
Im='Imded:BAAALgAECgQJBAAAAA==.',
Ja='Jalene:BAAALgAECgUJDgAAAA==.Jargyn:BAAALgAECgYJDQABLgAECgcJEgAIAAAAAA==.Jarlyss:BAAALgAECgcJEgAAAA==.Javieraa:BAABLgAECn8aAAILAAkJ/BccFQATAgALAAkJ/BccFQATAgAAAA==.',
Jd='Jdai:BAAALgAECgYJEwAAAA==.',
Jo='Jorschwa:BAAALgAECgEJAQAAAA==.',
Ju='Juglight:BAAALgAECgUJBQAAAA==.Jugtonic:BAAALgAECgIJAgAAAA==.',
Ka='Kaelithra:BAAALgADCgYJBgAAAA==.',
Ke='Kenny:BAAALgADCgEJAQAAAA==.',
Kh='Khaiv:BAACLgAFFH8WAAILAAUJsyGxDwB5AQALAAUJsyGxDwB5AQAuAAQKfzIAAgsACQkLI2AEAIEDAAsACQkLI2AEAIEDAAAA.Khanen:BAAALgAECgMJAwAAAA==.',
Ki='Kielann:BAABLgAECn8gAAIbAAcJUQ17FgAzAQAbAAcJUQ17FgAzAQAAAA==.Kikyo:BAAALgAECgYJCgAAAA==.Kimmi:BAAALgAECgIJAgAAAA==.Kinzen:BAABLgAECn8nAAIaAAcJsh6kBgDRAQAaAAcJsh6kBgDRAQAAAA==.',
Ku='Kulthosano:BAABLgAECn8dAAIcAAYJAyEhDQDmAQAcAAYJAyEhDQDmAQAAAA==.',
La='Labubu:BAABLgAECn8WAAIUAAYJHAcqlgDmAAAUAAYJHAcqlgDmAAAAAA==.Larra:BAAALgAECgIJAgAAAA==.Lasadin:BAAALgADCgEJAQAAAA==.Lawhityy:BAAALgADCgEJAgABLgAECggJIwAWAHgVAA==.',
Le='Lechwe:BAABLgAECn8VAAINAAcJhxMKIwCdAQANAAcJhxMKIwCdAQAAAA==.Legonator:BAAALgAECgUJCAAAAA==.',
Li='Lichmajor:BAABLgAECn8eAAIdAAkJ6BjSHgAPAgAdAAkJ6BjSHgAPAgAAAA==.Lilarri:BAAALgAECgUJBQAAAA==.Lilleymage:BAAALgADCgEJAQAAAA==.',
Lo='Lopus:BAAALgADCgcJEQAAAA==.Lostchi:BAABLgAECn8ZAAIQAAYJvyEGDAApAgAQAAYJvyEGDAApAgAAAA==.Lovepet:BAABLgAECn8lAAMTAAgJjhpVFgAdAgATAAgJjhpVFgAdAgASAAYJCQdpUwD+AAAAAA==.',
Lt='Ltlesunshine:BAAALgADCgYJBgAAAA==.',
Lu='Lucy:BAAALgADCgEJAQAAAA==.Lunal:BAABLgAECn8vAAIUAAkJvh8tDAC/AgAUAAkJvh8tDAC/AgAAAA==.',
Ly='Lyda:BAABLgAECn8gAAIVAAcJdxupFwAIAgAVAAcJdxupFwAIAgAAAA==.',
Ma='Magice:BAAALgAECgMJCgAAAA==.Malibubarbie:BAABLgAECn8fAAIMAAcJUAwxHwBPAQAMAAcJUAwxHwBPAQAAAA==.Maneevent:BAABLgAECn8XAAQTAAYJGRczOgBkAQATAAYJGRczOgBkAQARAAEJ1wRcQQAwAAASAAEJVQNflQAkAAAAAA==.Mariscylla:BAAALgAECgEJAQAAAA==.Materesa:BAABLgAECn8jAAMWAAgJeBVGDgDsAQAWAAgJeBVGDgDsAQAXAAYJbgzzNQA8AQAAAA==.Maysty:BAABLgAECn8kAAITAAgJewbDSQAwAQATAAgJewbDSQAwAQAAAA==.',
Me='Melidra:BAAALgAECgEJAQAAAA==.Menapaws:BAACLgAFFH8RAAQcAAUJchopAgBrAQAcAAQJ6RkpAgBrAQAeAAEJhxPmBgA6AAAHAAEJAADgLAAAAAAuAAQKfyEABBwACAkvJPcBAD8DABwACAkvJPcBAD8DAB4AAQkxIYwpAFQAAAcAAQkqFWRRAEIAAAAA.Meraxion:BAAALgAECgYJCAAAAA==.Meriel:BAABLgAECn8lAAIMAAgJcg4FFwCZAQAMAAgJcg4FFwCZAQAAAA==.',
Mi='Midnightstar:BAAALgAECgYJBwAAAA==.Milk:BAAALgAECgEJAQABLgAECgYJCgAIAAAAAA==.Mirabel:BAAALgAECgMJAwAAAA==.',
Mo='Monika:BAAALgAECgIJAgAAAA==.Monlee:BAAALgADCgQJBAAAAA==.Moonbayne:BAABLgAECn8dAAIHAAcJbRigHQATAgAHAAcJbRigHQATAgAAAA==.Mooszer:BAAALgAECgUJDwAAAA==.Morder:BAAALgADCgYJCgAAAA==.Moritz:BAAALgADCgcJDgAAAA==.',
Mu='Muaythighs:BAAALgAECgIJBAAAAA==.Mushu:BAABLgAECn8dAAIfAAgJUBicBQA6AgAfAAgJUBicBQA6AgAAAA==.',
Mv='Mvmt:BAAALgADCgYJBgAAAA==.',
My='Mycheeksclap:BAAALgAECgEJAQAAAA==.',
['Mà']='Màc:BAAALgADCgMJAwAAAA==.',
Na='Namielle:BAAALgADCgUJDAAAAA==.Nasta:BAAALgAECgQJCwAAAA==.',
Ne='Nepharim:BAAALgAECgYJBgAAAA==.Nephlim:BAACLgAFFH8VAAMdAAUJyiFGEQCOAQAdAAQJyiFGEQCOAQAgAAEJAAATKQAAAAAuAAQKfywAAh0ACQmqIcQGAGwDAB0ACQmqIcQGAGwDAAAA.',
Ni='Ninobrown:BAAALgAECgYJDQAAAA==.Niny:BAAALgAECgEJAwABLgAECgkJLwAUAL4fAA==.Ninzerp:BAAALgAECgEJAQABLgAECgkJLwAUAL4fAA==.Nizano:BAABLgAECn8VAAIEAAYJYwzSbAATAQAEAAYJYwzSbAATAQAAAA==.',
No='Noleyprays:BAAALgAECgEJAQABLgAECgMJCAAIAAAAAA==.Noryaa:BAABLgAECn8VAAITAAYJowV5YADvAAATAAYJowV5YADvAAAAAA==.Notabat:BAAALgADCgUJBQAAAA==.Notavoidelf:BAAALgADCgMJAwAAAA==.',
Nu='Nuadå:BAABLgAECn8XAAMVAAYJmw/LNwA3AQAVAAYJmw/LNwA3AQAHAAQJbgWEagB3AAAAAA==.',
Og='Oggi:BAAALgADCgcJBwAAAA==.',
Om='Om:BAAALgAECgYJCwAAAA==.',
On='Onthrox:BAAALgADCgEJAQAAAA==.',
Oo='Oorlian:BAAALgAECgMJCgAAAA==.',
Op='Opheleia:BAAALgADCgIJAgAAAA==.',
Or='Orallius:BAEALgADCgEJAQABLgAECggJHAAVABUiAA==.',
Po='Pogo:BAABLgAECn8fAAIRAAkJcyQiAQAXAwARAAkJcyQiAQAXAwAAAA==.Pogolock:BAAALgADCgEJAgABLgAECgkJHwARAHMkAA==.',
Pr='Pricedd:BAAALgADCgUJBQAAAA==.Prosperina:BAAALgADCgEJAQAAAA==.Prozac:BAAALgAECgMJCAAAAA==.',
Ps='Psiberian:BAABLgAECn8WAAMDAAcJSwmCDgDrAAADAAYJvAqCDgDrAAABAAUJYATkmgCJAAAAAA==.',
Ra='Ranoa:BAAALgADCgkJCQAAAA==.Rastapopulos:BAAALgAECgYJBgAAAA==.',
Re='Redmage:BAAALgADCgcJDwABLgAECggJJQATAI4aAA==.Redrocket:BAAALgAECgEJAQAAAA==.Remixed:BAAALgAECgMJAwAAAA==.',
Ri='Rikaku:BAABLgAECn8iAAITAAcJhBHcPgCzAQATAAcJhBHcPgCzAQAAAA==.',
Ro='Ronananna:BAAALgADCgkJDwABLgADCgYJBgAIAAAAAA==.Rosemery:BAAALgADCgkJFgAAAA==.',
['Rä']='Räpodac:BAABLgAECn8bAAIbAAcJDgsDFwAsAQAbAAcJDgsDFwAsAQAAAA==.',
Sa='Sagaba:BAAALgAECgYJCwAAAA==.Saphil:BAAALgADCgkJFAAAAA==.Saramus:BAAALgAECgEJAQAAAA==.',
Sc='Schizo:BAACLgAFFH8GAAIdAAIJnBZ5dACeAAAdAAIJnBZ5dACeAAAuAAQKfxoAAh0ABwmsHutAADUCAB0ABwmsHutAADUCAAAA.Schmaladin:BAAALgADCgUJCAAAAA==.',
Se='Searena:BAAALgAECgEJAgAAAA==.Sefiroth:BAABLgAECn8gAAILAAcJqQ9HQQA1AQALAAcJqQ9HQQA1AQAAAA==.Selillea:BAAALgAECgIJAgAAAA==.Semarius:BAAALgAECgEJAQABLgAECggJHgAbAEAfAA==.Semdorii:BAABLgAECn8eAAIbAAgJQB9SBQBjAgAbAAgJQB9SBQBjAgAAAA==.Sephywrath:BAABLgAECn8uAAIhAAkJuhfVAABfAgAhAAkJuhfVAABfAgAAAA==.Seralith:BAABLgAECn8eAAIdAAgJACEsDgCSAgAdAAgJACEsDgCSAgAAAA==.Seranight:BAACLgAFFH8FAAIgAAMJmh9tDQAFAQAgAAMJmh9tDQAFAQAuAAQKfzEAAiAACAkKJtQBAPECACAACAkKJtQBAPECAAAA.Seven:BAAALgAECgIJBAABLgAECgcJHwABAOYWAA==.Sevenpaws:BAAALgAECgEJAQABLgAECggJKwAMAL4lAA==.',
Sh='Shadowchi:BAAALgAECgEJAQAAAA==.Shaidon:BAAALgADCgkJEAAAAQ==.Shaly:BAABLgAECn8WAAIUAAYJ/gLDqwC9AAAUAAYJ/gLDqwC9AAAAAA==.Shattwrath:BAAALgAECgEJAQAAAA==.Shirohige:BAAALgAECgMJCgAAAA==.Shylan:BAAALgAECgIJBAAAAA==.',
Si='Simmer:BAAALgADCgMJAwAAAA==.',
Sm='Smasha:BAAALgAECgQJDQAAAA==.',
Sn='Snayre:BAABLgAECn8lAAIRAAgJDhsgBgBQAgARAAgJDhsgBgBQAgAAAA==.Snipêr:BAAALgAECgYJCAAAAA==.Snowlia:BAABLgAECn8XAAINAAcJyRPsNQCrAQANAAcJyRPsNQCrAQAAAA==.',
So='Soularis:BAAALgAECgYJCAAAAA==.',
Sp='Spectrê:BAAALgADCgMJAwAAAA==.Spiralpad:BAAALgADCgYJCgABLgAECggJHgAEAKkaAA==.Spybro:BAAALgAECgYJCQAAAA==.',
Sq='Squidtechnic:BAAALgAECgUJDgAAAA==.',
St='Stalkingwolf:BAABLgAECn8XAAIgAAYJnRXuEgBFAQAgAAYJnRXuEgBFAQAAAA==.',
Su='Suz:BAAALgADCgEJAQAAAA==.Suzuya:BAAALgADCgIJAgAAAA==.',
Sy='Sylailia:BAABLgAECn8kAAIHAAgJnxrkCgAcAgAHAAgJnxrkCgAcAgAAAA==.Syleta:BAAALgADCgMJBAAAAA==.',
Ta='Tamatoa:BAAALgAECgIJAgABLgAFFAEJAQAIAAAAAA==.',
Tc='Tcon:BAAALgAECgcJDgAAAA==.',
Td='Tdragon:BAAALgADCgkJCQAAAA==.',
Te='Tearany:BAAALgADCgUJBgAAAA==.',
Th='Thissa:BAABLgAECn8mAAMHAAgJrx8cBgB/AgAHAAgJrx8cBgB/AgAcAAEJSBm2MwAzAAAAAA==.Thundarah:BAAALgADCgcJDAAAAA==.Thundruid:BAAALgADCgUJCgAAAA==.Thuniellas:BAAALgADCggJEQAAAA==.',
Ti='Tiarcis:BAABLgAECn8WAAITAAcJwA+CNwBvAQATAAcJwA+CNwBvAQAAAA==.',
To='Toeknee:BAAALgAECgMJAwAAAA==.Totemsalot:BAAALgAFFAIJAgAAAA==.',
Tr='Treesummoner:BAABLgAECn8eAAQBAAkJyxNySwBHAQABAAgJyxNySwBHAQADAAUJ6wpwLAAMAQACAAMJoQvRGgCgAAAAAA==.Trialboost:BAAALgADCggJCQAAAA==.Tritanks:BAABLgAECn8pAAIJAAgJbx5aAwAcAgAJAAgJbx5aAwAcAgAAAA==.Troy:BAAALgAECgIJAwAAAA==.',
Tu='Tutsee:BAAALgADCgcJEgAAAA==.',
['Tå']='Tåbi:BAAALgADCgcJCwABLgAECgUJBQAIAAAAAA==.',
Un='Unbantam:BAAALgAECgUJBgAAAA==.',
Va='Valeq:BAAALgADCgkJCAAAAA==.Valeyka:BAAALgAECgYJDwAAAA==.Vasilia:BAABLgAECn8gAAIgAAcJERmbDACqAQAgAAcJERmbDACqAQAAAA==.',
Ve='Velanna:BAAALgADCggJBAAAAA==.',
Vi='Viego:BAAALgAECgMJBAAAAA==.',
Vo='Voclus:BAAALgAECgQJBwAAAA==.',
Wa='Warlodshenu:BAAALgADCgYJBgAAAA==.Warptouched:BAAALgADCgYJBgAAAA==.',
Wh='Whatapal:BAAALgAECgUJBwAAAA==.',
Wi='Wightranger:BAAALgADCgYJCwAAAA==.Wightwarrior:BAAALgADCgcJCgAAAA==.',
Wu='Wuwindtang:BAAALgAECgUJBwAAAA==.',
Xa='Xalatoes:BAAALgADCgQJBAAAAA==.',
Xe='Xeniuz:BAAALgADCgMJAwAAAA==.',
Xi='Xianfei:BAAALgAECgQJBQAAAA==.Xiles:BAABLgAECn8UAAIKAAYJIwTfRACqAAAKAAYJIwTfRACqAAAAAA==.',
Za='Zachxd:BAABLgAECn8nAAILAAcJvhn3JwCbAQALAAcJvhn3JwCbAQABLgAFFAIJBgAdAJwWAA==.Zanthe:BAAALgAECgMJCgAAAA==.Zapanese:BAAALgADCgIJAgAAAA==.Zaptism:BAABLgAECn8YAAMMAAgJ5BtZCwCaAgAMAAgJ5BtZCwCaAgAWAAMJSA0tQgCiAAAAAA==.Zapunch:BAAALgADCgEJAQAAAA==.Zarissaa:BAAALgADCgkJEAAAAA==.Zatha:BAAALgADCggJDgAAAA==.',
Ze='Zerowins:BAAALgADCgcJCAAAAA==.',
Zh='Zhanbrew:BAAALgAFFAEJAQABLgAECgcJGwAJADgfAA==.Zhanfury:BAAALgAFFAEJAQABLgAECgcJGwAJADgfAA==.',
Zi='Zinder:BAABLgAECn8fAAMiAAgJGAiHIwArAQAiAAgJGAiHIwArAQAjAAEJLAOMGgAhAAAAAA==.Zipit:BAABLgAECn8eAAIDAAgJJxUCBQCyAQADAAgJJxUCBQCyAQAAAA==.',
Zy='Zyae:BAAALgAECgEJAwAAAA==.Zyrinthia:BAAALgADCgYJBgAAAA==.',
['Æn']='Ænder:BAAALgADCgMJAwABLgAECgcJEgAIAAAAAA==.',
['Öb']='Öboron:BAACLgAFFH8HAAMRAAMJygHpEgC9AAARAAMJygHpEgC9AAASAAEJywHdHgA3AAAuAAQKfyUABBIACQleESMqANoBABIACAlWECMqANoBABMABgkpFTFTAG8BABEACAnPCEIXAFcBAAAA.',
['Üz']='Üz:BAABLgAECn8XAAIbAAYJ/RpzDwCKAQAbAAYJ/RpzDwCKAQAAAA==.',
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
