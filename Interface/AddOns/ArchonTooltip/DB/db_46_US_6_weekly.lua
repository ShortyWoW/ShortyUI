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

local lookup = {'Unknown-Unknown','Druid-Restoration','Evoker-Preservation','Monk-Brewmaster','Priest-Discipline','Priest-Holy','Shaman-Restoration','Shaman-Elemental','Druid-Balance','Paladin-Protection','DeathKnight-Blood','Priest-Shadow','Hunter-Marksmanship','Mage-Frost','DeathKnight-Unholy','Hunter-BeastMastery','Monk-Mistweaver','Warlock-Demonology','DemonHunter-Devourer','DemonHunter-Havoc','Evoker-Augmentation','Evoker-Devastation','Monk-Windwalker','Paladin-Holy','Paladin-Retribution','Warlock-Affliction','Shaman-Enhancement','Warrior-Fury','Hunter-Survival','Warlock-Destruction','DemonHunter-Vengeance','Warrior-Protection','DeathKnight-Frost','Druid-Feral',}
local provider = {region='US',realm='Alexstrasza',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abhanfnahwa:BAAALgADCgUJBQAAAA==.Abort:BAAALgAECgcJEgAAAA==.',
Ac='Acbabcaa:BAAALgADCgQJBwAAAA==.Acefighter:BAAALgADCgMJAwAAAA==.Aceon:BAAALgAECgYJDQAAAA==.Aceonarcher:BAAALgADCgMJAwAAAA==.',
Ad='Adfectia:BAAALgAECgcJDwAAAA==.',
Ae='Aelinjr:BAAALgAECgEJAQAAAA==.Aelsa:BAAALgADCgQJBAABLgAECgMJBgABAAAAAA==.Aelyt:BAAALgADCgkJMQAAAA==.Aesirkin:BAAALgAECgIJBAAAAA==.Aeth:BAAALgAECggJEgAAAA==.Aethér:BAAALgAECgEJAQABLgAFFAUJEwACAA4ZAA==.',
Ag='Agiel:BAAALgADCgYJBgAAAA==.Agilities:BAAALgADCgYJBgAAAA==.',
Ah='Ahsokä:BAAALgAECgQJBAAAAA==.',
Al='Alcool:BAAALgAECgIJAgAAAA==.Alderaan:BAAALgAECgMJAwAAAA==.Alexhya:BAAALgAECgEJAQAAAA==.Alexjones:BAAALgADCgUJBwAAAA==.Aliand:BAAALgAECgIJAgAAAA==.Aliande:BAAALgADCgUJBQAAAA==.Alnethir:BAAALgAECgEJAQAAAA==.Aloray:BAAALgADCgcJCgAAAA==.Alordis:BAAALgADCgMJAwAAAA==.Alpharetta:BAAALgAECgcJBgAAAA==.Alsou:BAAALgADCgUJBQAAAA==.Alvarah:BAAALgADCgMJAwAAAA==.Alynas:BAABLgAECn8aAAICAAkJBwxnSgB5AQACAAkJBwxnSgB5AQAAAA==.Alysona:BAAALgAECgUJEwAAAA==.',
Am='Amahra:BAAALgAECgQJBwAAAA==.Amelio:BAAALgADCgIJAgAAAA==.Amewow:BAAALgAECggJEAAAAA==.',
An='Anadoria:BAAALgADCgYJBgAAAA==.Analferret:BAAALgAECgMJCAAAAA==.Anastæsia:BAAALgADCgYJBwABLgAECgMJAwABAAAAAA==.Anitabidet:BAAALgADCgcJBwAAAA==.',
Ap='Apepi:BAAALgADCgcJBwAAAA==.Apolion:BAAALgADCgQJBAAAAA==.Apoundofcake:BAAALgAECgEJAQAAAA==.Appauling:BAAALgADCgYJBgAAAA==.',
Ar='Arclore:BAAALgAECgYJEgAAAA==.Argenor:BAAALgAECgUJCgAAAA==.Aricict:BAAALgAECgMJAwAAAA==.Arlý:BAAALgAECgEJAgAAAA==.Aruneza:BAABLgAECn8YAAIDAAcJ1Q6ZCwBTAQADAAcJ1Q6ZCwBTAQAAAA==.',
As='Asajj:BAAALgAECgQJCgAAAA==.Asharie:BAAALgADCgEJAQAAAA==.Ashcatchm:BAAALgADCgMJAwAAAA==.Ashergon:BAAALgADCgMJAwABLgAECgcJEwABAAAAAA==.Asheriz:BAAALgAECgEJAQABLgAECgcJEwABAAAAAA==.Asherous:BAAALgAECgcJEwAAAA==.Ashiashi:BAAALgAECgEJAQABLgAFFAEJAQABAAAAAA==.Ashomá:BAAALgADCgcJCAAAAA==.Ashèr:BAAALgAECgYJBgABLgAECgcJEwABAAAAAA==.Aszura:BAAALgADCgUJBQAAAA==.',
Au='Auntieshaman:BAAALgADCgEJAQAAAA==.Auranhis:BAAALgADCgQJAwAAAA==.Auriailas:BAAALgADCgcJCQAAAA==.Autoignition:BAAALgADCgMJAwAAAA==.',
Av='Avidel:BAAALgAECgcJDgAAAA==.Avryn:BAAALgAECgUJEQAAAA==.',
Ay='Ayilime:BAAALgAECgMJBAAAAA==.',
Ba='Balør:BAAALgAECgMJAwABLgAECgcJFwAEAPcPAA==.',
Be='Beanvoid:BAAALgADCgYJBgAAAA==.Beardsaint:BAAALgADCgUJBQAAAA==.Beenah:BAAALgAECgUJEgAAAA==.Belethiel:BAAALgADCgEJAQAAAA==.Bellinopher:BAAALgADCggJCAABLgAECgcJFQAFAEwRAA==.Benafflock:BAAALgAECgYJBwAAAA==.Bence:BAAALgAECgMJBAABLgAECggJDgABAAAAAA==.Benefitheals:BAAALgAECgIJAgAAAA==.Benefitsham:BAAALgADCgYJBgAAAA==.',
Bi='Bigbibble:BAABLgAECn8WAAIGAAgJuRJkFQBkAQAGAAgJuRJkFQBkAQAAAA==.Birdien:BAAALgAECgYJBgAAAA==.',
Bl='Blackrose:BAAALgADCgIJAgAAAA==.Blamson:BAAALgADCgYJCgAAAA==.Bloodrain:BAAALgAECgkJDgAAAA==.',
Bo='Boomie:BAAALgAFFAUJBAAAAA==.Booptyboop:BAAALgAECgQJCAAAAA==.Booptydo:BAAALgADCgYJBgAAAA==.Boris:BAAALgADCgYJBQAAAA==.Bowhawk:BAAALgAECgQJCwAAAA==.Bozag:BAAALgADCgIJAgAAAA==.',
Br='Braiin:BAAALgAECgUJBgABLgAFFAUJEwACAA4ZAA==.Brakken:BAAALgADCgQJBAAAAA==.Bravebolt:BAAALgAECgQJBAAAAA==.Brawll:BAAALgAECgEJAQAAAA==.Brazyn:BAAALgADCgYJBgAAAA==.Brevarda:BAABLgAECn8dAAMHAAYJHiHuHQAsAgAHAAYJHiHuHQAsAgAIAAYJZg0gIQASAQAAAA==.Brubble:BAAALgADCgMJAwAAAA==.Brugg:BAAALgADCgYJBgAAAA==.',
Bu='Bubblzmgee:BAABLgAECn8aAAIFAAcJkA11FABTAQAFAAcJkA11FABTAQAAAA==.',
Ca='Cadence:BAAALgAECgEJAgAAAA==.Cadin:BAABLgAECn8VAAMHAAkJSxmSDQCvAgAHAAkJSxmSDQCvAgAIAAcJYhdeLwCkAQAAAA==.Cakeman:BAAALgADCgEJAQAAAA==.Calehunter:BAAALgADCgEJAQAAAA==.Capone:BAAALgAECgIJAQAAAA==.Carahz:BAAALgAECgUJEwAAAA==.Carindria:BAAALgAECgEJAQAAAA==.Caylavana:BAAALgAECggJDQAAAA==.',
Ce='Celaylria:BAAALgAECgYJCgAAAA==.',
Ch='Chabz:BAAALgAECgQJAwAAAA==.Chai:BAABLgAECn8WAAMJAAcJZxiqHwABAgAJAAcJZxiqHwABAgACAAYJzRh5OQDAAQAAAA==.Charmed:BAAALgAECgcJDgAAAA==.Charmíng:BAAALgAECgUJCwAAAA==.Cheryll:BAAALgAECgUJBQAAAA==.',
Ci='Cint:BAAALgAECgQJBwAAAA==.',
Cl='Cloudedjade:BAABLgAECn8UAAIKAAYJFAqdFQC9AAAKAAYJFAqdFQC9AAAAAA==.',
Co='Coleybear:BAAALgAECgUJDAAAAA==.Copedk:BAABLgAECn8ZAAILAAYJFR0HBwCxAQALAAYJFR0HBwCxAQAAAA==.Copedogg:BAAALgADCgcJDgAAAA==.Corrode:BAAALgAECgcJBwAAAA==.Covertm:BAAALgAECgcJEgAAAA==.Covertw:BAAALgADCgEJAQAAAA==.Covertx:BAABLgAECn8VAAMFAAYJdRJGFwA0AQAFAAYJdRJGFwA0AQAMAAEJbAe9QwAwAAAAAA==.',
Cr='Crashedout:BAAALgADCgEJAgAAAA==.Crashknight:BAAALgADCgUJBQAAAA==.Crew:BAAALgAECgMJAwAAAA==.Crims:BAAALgAECggJEwAAAA==.',
Cu='Culture:BAAALgAECgYJEAAAAA==.',
Cy='Cybeldin:BAABLgAECn8aAAINAAcJewcHDAAOAQANAAcJewcHDAAOAQAAAA==.Cyberdemonxd:BAAALgADCgUJCQABLgAECgYJDwABAAAAAA==.',
Da='Daadeedaa:BAACLgAFFH8GAAIOAAMJdBxgKwAdAQAOAAMJdBxgKwAdAQAuAAQKfycAAg4ACAkqJBccAAMCAA4ACAkqJBccAAMCAAAA.Daddysparey:BAAALgAECgUJDwAAAA==.Dagoba:BAAALgAECgMJAgAAAA==.Dakk:BAABLgAECn8hAAIOAAgJdhNDKQDAAQAOAAgJdhNDKQDAAQAAAA==.Dardeathicus:BAACLgAFFH8JAAIPAAMJRyCuMgC+AAAPAAMJRyCuMgC+AAAuAAQKfx8AAg8ACAnIIIkoAJgCAA8ACAnIIIkoAJgCAAAA.Darderyag:BAAALgAECggJDQAAAA==.Darek:BAAALgAECgQJDAAAAA==.Dariara:BAAALgAECgEJAQAAAA==.Darkbud:BAAALgADCggJEQAAAA==.Darkfeazer:BAAALgADCgEJAQAAAA==.Darkforge:BAAALgAECgYJBQAAAA==.Darmonkicus:BAAALgAECgcJCgAAAA==.Dazzan:BAAALgADCgUJBQAAAA==.',
De='Deadlocks:BAAALgADCgEJAQAAAA==.Deathhold:BAAALgAECgYJBgAAAA==.Debilitation:BAAALgADCgIJAgAAAA==.Dedrys:BAAALgAECgEJAQAAAA==.Deklan:BAAALgAECgEJAgAAAA==.Delsid:BAAALgAECgMJAwAAAA==.Demonsteven:BAAALgADCgcJCgAAAA==.Dependabull:BAAALgADCgYJCQABLgADCgcJBwABAAAAAA==.Dernis:BAAALgADCgMJAwAAAA==.Deshaman:BAABLgAECn8VAAIIAAgJTQYRHgAnAQAIAAgJTQYRHgAnAQABLgAFFAMJCQAQAEgSAA==.Devilbeast:BAAALgAECgQJCQAAAA==.',
Dh='Dhargo:BAAALgADCgcJBwAAAA==.',
Di='Dirte:BAAALgADCgYJDQAAAA==.Dirty:BAABLgAECn8eAAIIAAgJ5BOHJQDlAQAIAAgJ5BOHJQDlAQAAAA==.',
Dk='Dkbygorm:BAAALgADCgQJBgAAAA==.',
Do='Dolfi:BAAALgADCggJDAAAAA==.Dorlesette:BAABLgAECn8jAAMRAAgJFQjgGwAjAQARAAgJFQjgGwAjAQAEAAIJ7AITRgBLAAAAAA==.',
Dr='Dravindil:BAAALgAECgcJBgAAAA==.Dreamlesnite:BAABLgAECn8XAAISAAcJCwYbSQAVAQASAAcJCwYbSQAVAQAAAA==.Dreidelman:BAAALgAECgIJAgAAAA==.Drkstar:BAAALgAECgYJCQAAAA==.',
Du='Dunthur:BAAALgADCgYJBgAAAA==.Durto:BAAALgADCgkJEgABLgAECgQJBQABAAAAAA==.',
Dy='Dylora:BAABLgAECn8aAAIRAAcJhBhxEQCUAQARAAcJhBhxEQCUAQAAAA==.',
['Dï']='Dïesel:BAAALgAECgIJAgAAAA==.',
['Dó']='Dólores:BAAALgADCgYJBgAAAA==.',
Eg='Egregore:BAAALgAECgUJCwAAAA==.',
El='Eliwena:BAAALgAECggJDwAAAA==.Ellaria:BAABLgAECn8YAAMTAAcJHxcbIwBhAQAUAAYJVhjcJQCQAQATAAcJmREbIwBhAQAAAA==.Elyselyia:BAAALgAECgUJBQAAAA==.Elysindrall:BAABLgAECn8XAAIDAAcJSRAsCQCOAQADAAcJSRAsCQCOAQAAAA==.',
Em='Emokins:BAABLgAECn8aAAIIAAcJLyI1BgBIAgAIAAcJLyI1BgBIAgAAAA==.',
En='Endesh:BAABLgAECn8aAAMVAAcJJwYwIgDyAAAVAAcJnAUwIgDyAAAWAAMJ6gXFDwBWAAAAAA==.Enolah:BAAALgADCgMJAwAAAA==.',
Er='Eradica:BAAALgADCgYJDQAAAA==.Erubus:BAACLgAFFH8FAAMEAAIJLBbfGQCbAAAEAAIJLBbfGQCbAAAXAAEJQwGSFAA9AAAuAAQKfxUABAQACQlSIEQWAFcCAAQACQlSIEQWAFcCABEAAgk2E/dWAHMAABcAAQm/DsJ5ADcAAAAA.Eryss:BAAALgAECgUJEwAAAA==.',
Es='Escånor:BAAALgAECgYJBgAAAA==.Esmeraldita:BAAALgADCgYJDwAAAA==.',
Ev='Evercleâr:BAAALgADCgkJAgAAAA==.Evilblixz:BAAALgADCgYJAQAAAA==.Evoked:BAAALgAECgUJEwAAAA==.',
Ex='Excentric:BAAALgAECgYJCgABLgAFFAUJDAAOAJcaAA==.Expiraman:BAAALgADCgYJBgAAAA==.',
Fa='Faeliel:BAAALgADCgYJBgABLgADCgYJDQABAAAAAA==.Faelýn:BAAALgAECgUJDAAAAA==.Faessa:BAAALgADCgIJAgAAAA==.Fanden:BAAALgADCgYJCQAAAA==.Fartimer:BAAALgADCgYJBgABLgAECggJGgACALYVAA==.',
Fd='Fdk:BAAALgADCgMJAwAAAA==.',
Fe='Feathering:BAAALgAECgYJEgAAAA==.Fellariene:BAAALgADCgcJCAAAAA==.Feoralaure:BAAALgADCgEJAQAAAA==.',
Fl='Fluoria:BAAALgAECgQJBgAAAA==.Fláreon:BAABLgAECn8UAAIYAAcJDRg+HQAsAgAYAAcJDRg+HQAsAgAAAA==.',
Fr='Fragarach:BAAALgAECgEJAQAAAA==.Frostynipie:BAAALgADCgMJAwAAAA==.Frutypebblz:BAAALgAECgYJEAAAAA==.',
Fu='Fuzznn:BAAALgAECgMJAwABLgABCgIJAgABAAAAAA==.',
['Fà']='Fàmous:BAABLgAECn8VAAMFAAgJbRirCgDjAQAFAAgJAxSrCgDjAQAGAAIJvB7+YQCoAAAAAA==.',
Ga='Galabris:BAABLgAECn8aAAILAAcJeCKeBAD2AQALAAcJeCKeBAD2AQAAAA==.Galen:BAAALgAECgEJAQAAAA==.',
Ge='Geranin:BAAALgADCgUJCAAAAA==.Gervire:BAAALgADCgcJCAAAAA==.',
Gh='Ghouldân:BAAALgADCgMJBQAAAA==.Ghoulmania:BAAALgAECgkJCwAAAA==.',
Gi='Gimligrimes:BAAALgADCgEJAQAAAA==.Gitchusum:BAAALgAECgEJAQAAAA==.',
Gl='Glaedry:BAAALgAECgEJAwAAAA==.',
Go='Goose:BAAALgAECgcJDwAAAA==.Gormladin:BAAALgAECgUJEwAAAA==.',
Gr='Greenbahamut:BAAALgAECgEJAQAAAA==.Gregamesh:BAAALgADCgcJDgAAAA==.Grill:BAAALgAECgMJAwAAAA==.Grimsreaper:BAAALgADCgkJDgAAAA==.Grizzlypouch:BAAALgADCgYJBgAAAA==.',
Gu='Guillimus:BAAALgADCgcJBgAAAA==.',
['Gï']='Gïzmö:BAAALgAECgUJDAAAAA==.',
Ha='Halfang:BAAALgADCgYJDAAAAA==.Handham:BAAALgAECgUJCAAAAA==.Hasheth:BAAALgAECgYJCQAAAA==.Havocfang:BAAALgADCgIJAQAAAA==.Hawkiing:BAAALgADCgQJBAAAAA==.Hazuki:BAAALgAECgMJAwAAAA==.',
He='Helouise:BAAALgADCgQJBAAAAA==.Herbalxur:BAAALgAECgQJCAAAAA==.',
Hi='Hibikase:BAAALgAECgYJBgAAAA==.Hildegarde:BAAALgAECgEJAQABLgAECgYJBgABAAAAAA==.Hitpoints:BAAALgAECgUJDgAAAA==.',
Ho='Hobbikeen:BAABLgAECn8ZAAMDAAcJXxfcHACeAQADAAcJXxfcHACeAQAVAAcJag+uFgBJAQAAAA==.Holyhope:BAABLgAECn8WAAIYAAYJWhTkGgB1AQAYAAYJWhTkGgB1AQAAAA==.Holymana:BAABLgAECn8WAAIZAAcJ9xW2LwCDAQAZAAcJ9xW2LwCDAQAAAA==.Hoshea:BAAALgADCgMJAwAAAA==.Hottyoreo:BAAALgADCgYJCwAAAA==.Howcom:BAAALgADCgcJBwAAAA==.',
Hu='Huffingpaint:BAAALgAECgYJBgAAAA==.Hundrakor:BAAALgADCgYJCQAAAA==.Huntinghawk:BAAALgAECgEJAQABLgAECgQJCwABAAAAAA==.Hutzil:BAABLgAECn8XAAMSAAcJzxcbLAB9AQASAAcJIRcbLAB9AQAaAAIJCBaTGwCXAAAAAA==.',
['Hÿ']='Hÿpothermia:BAAALgAECgMJAwAAAA==.',
Il='Illidianna:BAABLgAECn8WAAMTAAgJehaBGgCWAQATAAgJehaBGgCWAQAUAAIJixJcXABvAAAAAA==.',
Im='Imitlol:BAAALgAECgEJAQAAAA==.',
In='Inception:BAAALgADCgkJCgAAAA==.',
Ir='Irrefutable:BAAALgADCgQJBAAAAA==.',
Ja='Jackatak:BAAALgADCgMJAwAAAA==.Jacoblack:BAAALgADCgMJAwAAAA==.Jadin:BAAALgADCgEJAQAAAA==.Jaefury:BAABLgAECn8WAAIbAAcJOhuaBADiAQAbAAcJOhuaBADiAQAAAA==.',
Ji='Jimadler:BAAALgADCgMJAwABLgADCgkJJAABAAAAAA==.Jiminybilini:BAAALgAECgcJBQAAAA==.Jimmybull:BAAALgADCgEJAQAAAA==.Jinrop:BAEALgADCgcJBwAAAA==.',
Jo='Jobuu:BAAALgAECgEJAQAAAA==.Johnnypopoff:BAABLgAECn8ZAAIOAAYJAhbJTgBEAQAOAAYJAhbJTgBEAQAAAA==.Jojohunts:BAAALgAECgYJCQAAAA==.',
Jp='Jpðc:BAAALgAECgYJCgAAAA==.',
Ju='Juanjo:BAAALgADCgcJBwABLgAECggJIgAOALAXAA==.Junyubych:BAAALgAECgMJBgAAAA==.Justylln:BAAALgADCgMJAgAAAA==.Justzach:BAABLgAECn8lAAIEAAgJHh3nBABgAgAEAAgJHh3nBABgAgAAAA==.',
['Jà']='Jàccuse:BAAALgAECgUJDAAAAA==.Jàrnsaxa:BAAALgADCgEJAQAAAA==.',
Ka='Kadywompus:BAAALgADCgcJBwAAAA==.Kaeladra:BAAALgADCgcJDgAAAA==.Kailm:BAAALgADCgIJAgABLgAFFAQJCAAcADcaAA==.Kait:BAAALgAECgEJAQAAAA==.Kalniel:BAAALgADCgUJBQAAAA==.Kassaalaa:BAAALgADCgYJBgAAAA==.Kasume:BAAALgAECgMJAwAAAA==.Kaylastrasza:BAAALgADCgEJAQAAAA==.Kazurend:BAACLgAFFH8MAAIMAAQJSyEjAwCEAQAMAAQJSyEjAwCEAQAuAAQKfxoAAgwACAnQI78FADMDAAwACAnQI78FADMDAAAA.',
Ke='Keleira:BAAALgAECgUJDwAAAA==.Kelemvore:BAAALgADCgMJBgAAAA==.Kericcandere:BAAALgADCgIJAwAAAA==.Kerm:BAEALgAECgEJAQAAAA==.Keyaielenst:BAAALgADCgcJBwAAAA==.',
Kh='Khristina:BAAALgADCgMJAwAAAA==.',
Ki='Kiel:BAAALgAECgcJCAABLgAECgYJDAABAAAAAA==.Kindos:BAAALgADCgQJBwAAAA==.Kippo:BAEALgAECgEJAQABLgAFFAQJBwAOAIsFAA==.Kiramman:BAAALgAECgMJBgAAAA==.Kirsute:BAAALgADCgYJBgAAAA==.Kithiri:BAAALgAECgQJBgAAAA==.',
Kn='Knarn:BAABLgAECn8dAAIdAAgJoxxABgALAgAdAAgJoxxABgALAgAAAA==.',
Ko='Koralie:BAACLgAFFH8XAAIQAAUJtRbWAACrAQAQAAUJtRbWAACrAQAuAAQKfxkAAxAACAk6HXEbAGICABAACAk6HXEbAGICAA0ABAmsDYlcANAAAAAA.',
Kr='Krillaxx:BAAALgAECgcJDwAAAA==.Krimzin:BAAALgAECgYJBgABLgAFFAMJBQAQAKcbAA==.Krolg:BAAALgAECgQJCQAAAA==.Kromvar:BAAALgAECgQJBwAAAA==.',
Ku='Kungfused:BAAALgADCgUJCAAAAA==.Kurisux:BAAALgAFFAEJAQAAAA==.',
Ky='Kyliekat:BAAALgAECgUJBgAAAA==.Kyndlynn:BAAALgAECgQJCwAAAA==.',
La='Lanceelot:BAAALgAECgIJAgAAAA==.Lanel:BAAALgAECgUJCQAAAA==.Lathelous:BAABLgAECn8dAAIKAAgJtSINAQDAAgAKAAgJtSINAQDAAgAAAA==.',
Ld='Ldt:BAAALgADCgMJAwAAAA==.',
Le='Leintheir:BAAALgAECgMJAwAAAA==.Leththol:BAAALgADCgkJJQAAAA==.Letyoudie:BAAALgAECgQJCwAAAA==.Levenza:BAAALgAECgYJDQAAAA==.',
Li='Lideina:BAABLgAECn8VAAIPAAYJMRbUXgDqAAAPAAYJMRbUXgDqAAAAAA==.Lightt:BAABLgAECn8qAAMGAAgJtBXQCQALAgAGAAgJtBXQCQALAgAMAAUJNQEKVQBvAAAAAA==.Liightt:BAAALgAECgUJCgAAAA==.Lilnug:BAAALgAECgQJCgAAAA==.Lindsey:BAAALgADCgkJDQABLgAECgQJBQABAAAAAA==.Littlenyne:BAAALgAECgEJAQAAAA==.',
Ll='Llando:BAAALgADCgYJBgAAAA==.Llars:BAABLgAECn8dAAIHAAgJHxfMDQARAgAHAAgJHxfMDQARAgAAAA==.',
Lo='Lockkjaw:BAAALgADCgEJAQAAAA==.Locknorris:BAAALgADCgUJBgAAAA==.Loghrif:BAAALgAECgQJBAABLgAECgUJBgABAAAAAA==.Loptear:BAAALgAECgEJAQAAAA==.Loryanna:BAAALgADCgUJCgAAAA==.Louie:BAAALgAECgMJBAAAAA==.Lovehandless:BAAALgADCgEJAQAAAA==.Lovespell:BAAALgADCgUJBQAAAA==.',
Lu='Lucavian:BAAALgAECgUJCQAAAA==.Lucavias:BAAALgAECgMJBQAAAA==.Luckydruidh:BAAALgAECgYJCAAAAA==.Luckyevoker:BAAALgADCgcJDAABLgAECgYJCAABAAAAAA==.Lurien:BAAALgAECggJDgAAAA==.Luxilejo:BAAALgADCgYJBgAAAA==.',
Ly='Lyfebane:BAABLgAECn8dAAMYAAcJ9RnXFwCRAQAYAAYJmxjXFwCRAQAZAAcJYhAmNgBrAQAAAA==.',
['Ló']='Lórien:BAAALgADCgEJAQAAAA==.',
['Lø']='Lørs:BAABLgAECn8YAAIOAAUJkRBo1wBBAQAOAAUJkRBo1wBBAQAAAA==.',
Ma='Machorn:BAAALgADCgcJBwAAAA==.Magetree:BAAALgAECgQJBAABLgAFFAMJBgAZAPIUAA==.Mageyoucream:BAAALgADCgEJAQAAAA==.Magnai:BAAALgADCgcJBwAAAA==.Main:BAABLgAECn8iAAIZAAgJgAppWAAHAQAZAAgJgAppWAAHAQAAAA==.Malec:BAAALgADCggJCAAAAA==.Malicemech:BAAALgADCgEJAQAAAA==.Maliceone:BAAALgAECgQJBQAAAA==.Malicepaly:BAAALgADCgkJFwAAAA==.Mansmilk:BAAALgAECgQJBAAAAA==.Max:BAABLgAECn8XAAISAAgJ2x5YHgC+AQASAAgJ2x5YHgC+AQAAAA==.',
Mb='Mbaku:BAAALgAECgYJBgABLgAECggJJAAMAI8ZAA==.',
Me='Melinoe:BAAALgAECgUJDAAAAA==.Merc:BAAALgAECgUJBQAAAA==.Merithrá:BAAALgAECgIJAgAAAA==.',
Mi='Micah:BAACLgAFFH8TAAIDAAYJhhJqBQChAQADAAYJhhJqBQChAQAuAAQKfxgAAwMACAnkGgUOAFYCAAMACAnkGgUOAFYCABUABQm/GpcyADUBAAAA.Mishosuki:BAAALgAECgUJCgAAAA==.Misky:BAAALgADCgEJAQAAAA==.Misscleo:BAABLgAECn8XAAIOAAcJ/Q5EPwBwAQAOAAcJ/Q5EPwBwAQAAAA==.Mizzyboii:BAAALgADCgMJAwAAAA==.',
Mk='Mk:BAAALgAECggJDAAAAA==.',
Mn='Mnesarte:BAAALgAECgkJEgAAAA==.',
Mo='Moi:BAAALgAFFAQJBAABLgAFFAQJDQAOAIsdAA==.Monkilha:BAAALgADCgEJAQAAAA==.Moonkist:BAAALgAECgUJEQAAAA==.Moose:BAABLgAECn8oAAIPAAcJByJMIADGAQAPAAcJByJMIADGAQAAAA==.Morpheos:BAABLgAECn8aAAMCAAgJthXtSAB/AQACAAgJthXtSAB/AQAJAAQJfAfQKwCwAAAAAA==.Moxci:BAAALgAECgQJBQAAAA==.',
Mu='Mudamudamuda:BAAALgADCgYJDQAAAA==.',
My='Mysticforest:BAAALgAECgQJBAAAAA==.',
Na='Naedise:BAAALgADCgcJFgAAAA==.Narue:BAAALgAECgIJAgAAAA==.Natureswild:BAABLgAECn8gAAMJAAkJjRitDgClAQAJAAgJ3RetDgClAQACAAMJbQrUuQBSAAAAAA==.Navariis:BAAALgAECgQJBgAAAA==.Navillus:BAAALgAECgMJBgABLgAFFAUJFAADAHQSAA==.',
Ne='Necrophyliac:BAAALgAECgYJBgAAAA==.Nelrehim:BAAALgADCgQJBgAAAA==.Nephz:BAAALgADCgUJBQAAAA==.Nephzz:BAAALgAECgQJAgAAAA==.Nethery:BAAALgADCgcJCQAAAA==.Nex:BAAALgAECgEJAQAAAA==.Nezrin:BAAALgAECgUJDQAAAA==.',
Ni='Nidon:BAAALgADCgUJBQAAAA==.Niixxi:BAAALgADCgUJBQAAAA==.',
Nm='Nmbrs:BAABLgAECn8XAAMMAAYJLxzyEACCAQAMAAYJLxzyEACCAQAFAAEJ7AK4XAApAAAAAA==.',
No='Noirheffer:BAACLgAFFH8GAAIZAAMJ8hSoHAADAQAZAAMJ8hSoHAADAQAuAAQKfyAAAxkACAlDIvcXANkCABkACAlDIvcXANkCAAoABAlWEOMoAMMAAAAA.Noobishdad:BAAALgADCgEJAQAAAA==.',
Nu='Nulannatoo:BAAALgAECgUJBQAAAA==.Nuukeasaur:BAAALgADCgEJAQAAAA==.',
Ny='Nyadari:BAAALgAECgEJAQAAAA==.Nyrrhi:BAAALgAECgQJBAAAAA==.Nyxiro:BAAALgAECgUJBQAAAA==.',
Od='Odysseus:BAAALgADCgkJFgAAAA==.',
Ol='Olgann:BAAALgAECgYJCQAAAA==.Olguita:BAAALgAECgMJBQAAAA==.Olivertwìst:BAAALgADCgcJBwAAAA==.',
Om='Omgowned:BAAALgAECgUJBgABLgAECgcJDgABAAAAAA==.',
On='Onehothealer:BAABLgAECn8XAAIMAAgJAhTrGQAQAgAMAAgJAhTrGQAQAgAAAA==.',
Oo='Oorua:BAAALgADCggJCgAAAA==.',
Op='Opheliastar:BAABLgAECn8lAAIMAAgJbxTYCwDCAQAMAAgJbxTYCwDCAQAAAA==.',
Pa='Pad:BAAALgAECgUJEgAAAA==.Paintballerr:BAAALgADCgEJAQAAAA==.Paladerp:BAABLgAECn8nAAMYAAgJtAt3GQCBAQAYAAgJtAt3GQCBAQAZAAIJHQtdwwA7AAAAAA==.Pallyown:BAABLgAFFH8GAAIYAAIJvh/+EwCiAAAYAAIJvh/+EwCiAAAAAA==.Paprika:BAAALgADCgQJBgAAAA==.Pastorbedtym:BAAALgAECgcJEQAAAA==.Pat:BAAALgAECgMJAwAAAA==.Paulybricks:BAAALgAECgUJBgAAAA==.',
Pe='Pecan:BAAALgAECgcJDgAAAA==.Pewpewbang:BAAALgADCgIJAgAAAA==.',
Ph='Pharla:BAAALgADCgkJEAAAAA==.',
Pi='Pichon:BAAALgADCgQJBAAAAA==.Pin:BAAALgAECgcJBgAAAA==.Pirozhki:BAAALgADCgYJBgAAAA==.',
Pl='Plagueborn:BAAALgAECgEJAQAAAA==.Plentar:BAAALgADCgEJAQAAAA==.',
Po='Popcorntea:BAAALgAECgEJAQAAAA==.Porgoon:BAAALgAECgQJBQAAAA==.',
Pr='Preserved:BAAALgADCgIJAgAAAA==.',
Ps='Psaul:BAAALgAECgUJCgAAAA==.',
Py='Pyramys:BAAALgADCgYJBgAAAA==.',
Qe='Qedeshah:BAAALgADCgQJBwAAAA==.Qesem:BAAALgADCgUJBQAAAA==.',
Qu='Qualaribou:BAAALgADCgQJBAAAAA==.',
Ra='Raal:BAAALgADCgkJHgAAAA==.Raenostra:BAAALgAECgUJDAAAAA==.Raenya:BAAALgADCgIJAgAAAA==.Ragefather:BAAALgADCgEJAQAAAA==.Rageye:BAAALgADCgcJBwAAAA==.Rainydaze:BAAALgAECgUJBgAAAA==.Rambotank:BAAALgADCgUJBwAAAA==.Ramcharger:BAAALgAECgYJCAAAAA==.Ranen:BAABLgAECn8aAAIXAAgJxB9qBQBEAgAXAAgJxB9qBQBEAgAAAA==.Rashun:BAAALgAECgYJDQAAAA==.',
Re='Redcinnabar:BAAALgADCgcJFwAAAA==.Rehtilox:BAAALgADCgMJAwABLgAECgcJFQAFAEwRAA==.Reilly:BAAALgADCggJFQAAAA==.Rev:BAAALgAECgQJBAAAAA==.Rexxy:BAAALgAECgQJBAAAAA==.',
Ri='Riju:BAAALgAECgcJDAAAAA==.Rikashae:BAAALgADCgkJHgAAAA==.Rillan:BAAALgADCgMJAwAAAA==.Rinzler:BAAALgAECgIJBAAAAA==.',
Rn='Rng:BAAALgAECgQJCwAAAA==.',
Ro='Roachcentral:BAAALgADCgUJBgAAAA==.Rollforpi:BAAALgAECgIJAgABLgAFFAUJEwACAA4ZAA==.Ropebunnyana:BAABLgAECn8lAAIRAAkJ1R8aAQBQAwARAAkJ1R8aAQBQAwAAAA==.Rowkani:BAAALgADCgkJCQAAAA==.',
Ru='Ruki:BAAALgAECgQJCgABLgAECgYJBgABAAAAAA==.',
Ry='Ryand:BAAALgAECgUJCQAAAA==.',
Sa='Sacra:BAAALgAECgEJAQAAAA==.Salarcyn:BAAALgAECgUJDAAAAA==.Samiracy:BAABLgAECn8aAAIeAAcJyxfZAwCpAQAeAAcJyxfZAwCpAQAAAA==.Sannrin:BAAALgAECgYJDAAAAA==.Sapprot:BAAALgADCgcJCQAAAA==.Sarkress:BAAALgADCgkJCQAAAA==.',
Se='Seagal:BAAALgADCgEJAgAAAA==.Senbatorii:BAAALgAECgUJDAAAAA==.Seredala:BAAALgADCgUJCwAAAA==.Sethrow:BAAALgAECgcJDgAAAA==.Severa:BAAALgADCgIJAgAAAA==.',
Sh='Shalia:BAAALgADCgMJAwABLgADCgMJBgABAAAAAA==.Sharas:BAAALgAECgEJAgAAAA==.Sheltatha:BAAALgAECgEJAQAAAA==.Shengari:BAABLgAECn8aAAIGAAgJPxG1MAB+AQAGAAgJPxG1MAB+AQAAAA==.Shotcallà:BAAALgADCgIJAgAAAA==.Shuna:BAAALgAECgUJCwAAAA==.Shyly:BAAALgAECgYJCwAAAA==.Shâbs:BAAALgAECgIJAgAAAA==.',
Si='Sikkly:BAAALgADCgcJEQAAAA==.Siley:BAABLgAECn84AAIPAAkJLRKXJgCkAQAPAAkJLRKXJgCkAQAAAA==.Sin:BAAALgAECgcJCAAAAA==.Siphon:BAAALgADCgYJBgAAAA==.',
Sk='Skarletfaith:BAAALgAECgUJDQAAAA==.',
Sl='Sloanya:BAABLgAECn8oAAMRAAgJRBwMBgBnAgARAAgJRBwMBgBnAgAXAAYJKxqdJQCqAQAAAA==.',
Sn='Snarffie:BAAALgAECgYJCgAAAA==.',
So='Solanar:BAAALgADCgUJBQAAAA==.Somedruid:BAABLgAECn8dAAIJAAgJ2iB/AwCVAgAJAAgJ2iB/AwCVAgAAAA==.',
Sp='Spiarmf:BAAALgADCgUJBQAAAA==.Spicynes:BAAALgADCgMJAwAAAA==.Spicyness:BAAALgAECgIJAgAAAA==.Spiderdk:BAAALgAECgUJCAABLgAFFAMJCQAQAEgSAA==.Spidermonk:BAAALgADCgcJDgABLgAFFAMJCQAQAEgSAA==.Spëcter:BAAALgAECgUJBQABLgAECgcJDgABAAAAAA==.Spëcthyr:BAAALgAECgcJDgAAAA==.',
Sq='Squishypoo:BAAALgADCgEJAQAAAA==.',
St='Stache:BAAALgAECgEJAQAAAA==.Stoneyfoam:BAAALgAECgYJBgAAAA==.Stormrider:BAAALgADCgkJCQAAAA==.',
Su='Sugrace:BAAALgAECgYJBgAAAA==.Superdemonzz:BAACLgAFFH8DAAITAAMJ1gxFKQCeAAATAAMJ1gxFKQCeAAAuAAQKfxQAAxMACAlZG78vAD0CABMACAlZG78vAD0CAB8AAgmNCjknAEwAAAAA.Superevokerz:BAAALgADCgcJDgABLgAFFAMJAwATANYMAA==.Superlockz:BAAALgADCgkJCQABLgAFFAMJAwATANYMAA==.Superpallyz:BAABLgAECn8kAAMYAAcJgBl3JwDvAQAYAAcJgBl3JwDvAQAKAAQJEQmMMACQAAABLgAFFAMJAwATANYMAA==.Supershamanz:BAAALgAECgYJCgABLgAFFAMJAwATANYMAA==.Superspidey:BAAALgADCgIJAgAAAA==.Sushiroll:BAAALgAECgYJDwAAAA==.',
Sy='Sydnysweeney:BAAALgADCgMJAwAAAA==.Sylentslit:BAAALgADCggJGgAAAA==.Sylveslem:BAAALgAECgkJDAAAAA==.Syphon:BAAALgADCgMJAwAAAA==.',
['Sô']='Sôlmyr:BAAALgADCgIJAgAAAA==.',
Ta='Tacowarr:BAAALgADCgUJBQAAAA==.Taldazlian:BAAALgADCgMJAwAAAA==.Taliesin:BAAALgADCgQJBAAAAA==.Tallon:BAAALgAECgEJAQABLgAFFAMJBgAVAG4bAA==.Tantalus:BAAALgAECgcJCgAAAA==.Tarogen:BAAALgADCgUJBQAAAA==.Tashaler:BAAALgADCgEJAQAAAA==.',
Te='Tealet:BAAALgADCgkJCgAAAA==.Tellinor:BAAALgAECgYJDAAAAA==.Temporal:BAAALgAECgEJAQAAAA==.',
Th='Thanamoros:BAAALgAECgUJBgABLgAFFAMJBQAVALcOAA==.Thassarian:BAAALgAECgQJBAAAAA==.Thechosenone:BAAALgADCgIJAgAAAA==.Theroach:BAAALgAECgIJAwAAAA==.Throfin:BAAALgAECgUJCgAAAA==.',
Ti='Tinc:BAAALgADCgEJAgAAAA==.Tinkerballa:BAAALgADCgUJBQAAAA==.Tinonova:BAAALgAECgEJAgAAAA==.Titsmgee:BAAALgAECgIJAgAAAA==.',
To='Toeren:BAACLgAFFH8JAAIQAAMJSBJBGQABAQAQAAMJSBJBGQABAQAuAAQKfx8AAhAACAk7H6IVAIsCABAACAk7H6IVAIsCAAAA.Tomate:BAAALgADCgQJBAAAAA==.Toph:BAAALgAECgEJAQAAAA==.Tormented:BAAALgAECgYJEwAAAA==.Townsley:BAAALgAECgYJDQAAAA==.',
Tp='Tpain:BAAALgADCgIJAgAAAA==.',
Tr='Traitoros:BAAALgADCgYJBgAAAA==.Tralectra:BAAALgAECgcJDAAAAA==.Tranquilfist:BAAALgADCgQJBAABLgAECgUJDQABAAAAAA==.Treemonk:BAAALgADCgYJCgABLgAECgkJIAAJAI0YAA==.Trolvere:BAAALgAECgQJBwAAAA==.Trïsh:BAAALgADCgYJBgAAAA==.',
Tu='Tummy:BAAALgADCgcJEwAAAA==.Turtlesoup:BAAALgADCgYJBgAAAA==.',
Ty='Tygragon:BAAALgAECgQJBQAAAA==.',
Tz='Tzipporah:BAAALgAECgUJBQAAAA==.',
Ub='Ubee:BAABLgAECn8VAAITAAcJTxIoJABcAQATAAcJTxIoJABcAQAAAA==.',
Ul='Ultimakitty:BAAALgAECgUJCAAAAA==.',
Un='Unholymana:BAAALgADCgcJBwAAAA==.',
Va='Vaellin:BAAALgAECgEJAQAAAA==.Valanyr:BAAALgADCgEJAQAAAA==.Vantrix:BAAALgAECgEJAQABLgAFFAMJBQAVALcOAA==.Varabo:BAAALgAECgYJCQAAAA==.Varolina:BAAALgADCgcJCwAAAA==.',
Ve='Vehemencê:BAAALgADCgEJAQAAAA==.Velements:BAAALgAECgMJAwABLgAECggJDwABAAAAAA==.Velemon:BAABLgAECn8UAAIgAAgJSxLwEQDpAQAgAAgJSxLwEQDpAQAAAA==.Velisen:BAAALgAECgQJCAAAAA==.Velthala:BAAALgAECggJDwAAAA==.Velystiri:BAAALgADCgcJBgAAAA==.Venedictus:BAAALgADCgMJAwAAAA==.',
Vi='Virasdruid:BAAALgAECgIJBAAAAA==.Virusmonk:BAAALgAECgEJAwAAAA==.Vitner:BAAALgAECgcJEQAAAA==.',
Vo='Vosaleana:BAAALgADCgMJAwAAAA==.',
Vr='Vraak:BAACLgAFFH8TAAICAAUJDhl8BwCIAQACAAUJDhl8BwCIAQAuAAQKfycAAwIACAncG7crAAECAAIABwmBHbcrAAECAAkABwmZIwsgAP4BAAAA.',
Vu='Vulcus:BAAALgADCgEJAwABLgAFFAUJEwACAA4ZAA==.Vulpii:BAAALgADCgYJBQABLgAECggJIwAfALMgAA==.',
Vy='Vyndarien:BAAALgADCgIJAgAAAA==.Vyse:BAAALgADCgEJAQAAAA==.Vyttra:BAAALgADCgMJAwAAAA==.',
Wa='Walak:BAAALgADCgMJAwAAAA==.Warpulse:BAAALgADCgYJBgAAAA==.Warwizard:BAAALgADCgMJAwAAAA==.Watcherseye:BAAALgADCggJDwABLgADCgkJCQABAAAAAA==.',
Wc='Wcreator:BAAALgAECgQJCQAAAA==.',
We='Weapònized:BAAALgAECgUJDAAAAA==.',
Wh='Whitestain:BAABLgAECn8UAAINAAYJLQnFDwDPAAANAAYJLQnFDwDPAAAAAA==.',
Wi='Windyskie:BAAALgADCgEJAQAAAA==.Wingman:BAACLgAFFH8JAAIWAAMJryYWAQBZAQAWAAMJryYWAQBZAQAuAAQKfycAAhYACAmTJpgAAIsDABYACAmTJpgAAIsDAAAA.',
Wo='Womdalie:BAAALgADCgQJBgAAAA==.',
Xa='Xanthös:BAAALgAFFAEJAQABLgAFFAUJEwACAA4ZAA==.',
Xe='Xemnastrasza:BAACLgAFFH8FAAMVAAMJtw4kGADoAAAVAAMJtw4kGADoAAAWAAEJ0QNcCwBLAAAuAAQKfxYABBUACAkdFMIhALEBABUACAnSEcIhALEBABYABAmmCOotAKsAAAMAAQlrBX5LACsAAAAA.Xenonne:BAACLgAFFH8HAAITAAQJKxK4EQAyAQATAAQJKxK4EQAyAQAuAAQKfxsAAxMABgmPIPowAB8BABMABgmPIPowAB8BABQABQl3D2tGANsAAAAA.',
Xo='Xolither:BAABLgAECn8VAAMFAAcJTBH6EwBZAQAFAAYJQxH6EwBZAQAGAAQJ1ROrTgD9AAAAAA==.',
Xp='Xpireedk:BAACLgAFFH8JAAMPAAQJ3x9fDgB1AQAPAAQJIh5fDgB1AQAhAAIJdiNAAQDVAAAuAAQKfxoAAyEACAk8JUMDAF8CACEACAn3JEMDAF8CAA8ABQnnHqp1AJoBAAAA.',
Yo='Yorakk:BAAALgADCgIJAgAAAA==.Yorgo:BAAALgAECgIJAgAAAA==.',
Za='Zariala:BAAALgAECgUJBgAAAA==.Zatana:BAAALgAECgUJBQAAAA==.',
Ze='Zephymoo:BAABLgAECn8sAAMiAAkJAxz8AQBmAgAiAAkJAxz8AQBmAgAJAAEJfAPOggAtAAAAAA==.Zeromus:BAAALgAECgkJCQAAAA==.Zerri:BAAALgADCgIJAgAAAA==.Zeyana:BAABLgAECn8WAAQfAAcJYRjdCADnAQAfAAcJYRjdCADnAQAUAAQJlQVIUQClAAATAAIJPQCv9wAPAAABLgAECggJJwAQAHEhAA==.',
Zh='Zhengshi:BAABLgAECn8XAAIEAAcJ9w/fEwBnAQAEAAcJ9w/fEwBnAQAAAA==.',
Zo='Zoder:BAAALgAECgUJDgAAAA==.Zoose:BAABLgAECn8aAAIcAAcJ5RpWCwD2AQAcAAcJ5RpWCwD2AQAAAA==.Zoser:BAABLgAECn8bAAIXAAcJAybyAgCeAgAXAAcJAybyAgCeAgAAAA==.',
['Æl']='Ælthan:BAAALgADCgUJBgAAAA==.',
['Ér']='Érubus:BAAALgAECgEJAQAAAA==.',
['ßu']='ßugs:BAABLgAECn8VAAIQAAYJEhWfLwBSAQAQAAYJEhWfLwBSAQAAAA==.',
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
