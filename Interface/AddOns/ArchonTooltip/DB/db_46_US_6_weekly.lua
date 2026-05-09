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

local lookup = {'Paladin-Retribution','Unknown-Unknown','DeathKnight-Blood','Druid-Restoration','DemonHunter-Devourer','Evoker-Preservation','Shaman-Restoration','Shaman-Elemental','Monk-Brewmaster','DeathKnight-Unholy','Priest-Discipline','Priest-Holy','Druid-Guardian','Druid-Balance','Evoker-Augmentation','Paladin-Protection','Hunter-Marksmanship','Mage-Frost','Hunter-BeastMastery','Monk-Mistweaver','Warlock-Demonology','DemonHunter-Havoc','Evoker-Devastation','Monk-Windwalker','Warrior-Fury','Paladin-Holy','Warlock-Destruction','Warlock-Affliction','Shaman-Enhancement','Rogue-Subtlety','Priest-Shadow','Hunter-Survival','DemonHunter-Vengeance','Warrior-Protection','DeathKnight-Frost','Druid-Feral','Warrior-Arms',}
local provider = {region='US',realm='Alexstrasza',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abhanfnahwa:BAAALgADCgUJBQAAAA==.Abort:BAABLgAECn8YAAIBAAcJtR3YHwAKAgABAAcJtR3YHwAKAgAAAA==.',
Ac='Acbabcaa:BAAALgADCgYJCgAAAA==.Acefighter:BAAALgADCgMJAwAAAA==.Aceon:BAABLgAECn8UAAIBAAcJkBVATwBYAQABAAcJkBVATwBYAQAAAA==.Aceonarcher:BAAALgADCgMJAwAAAA==.',
Ad='Adfectia:BAAALgAECggJEwAAAA==.',
Ae='Aelinjr:BAAALgAECgEJAQAAAA==.Aelsa:BAAALgADCgYJCgABLgAECgUJCwACAAAAAA==.Aelyt:BAAALgAECgIJAgAAAA==.Aesirkin:BAAALgAECgIJBAAAAA==.Aeth:BAABLgAECn8YAAIDAAkJZR/bBQDeAgADAAkJZR/bBQDeAgAAAA==.Aethér:BAAALgAECgEJAQABLgAFFAUJGAAEAFQZAA==.',
Ag='Agiel:BAAALgADCgYJBgAAAA==.Agilities:BAAALgADCgYJBgAAAA==.',
Ah='Ahsokä:BAAALgAECgQJBwAAAA==.',
Al='Alcool:BAAALgAECgIJAgAAAA==.Alderaan:BAAALgAECgMJAwAAAA==.Alexhya:BAAALgAECgEJAQAAAA==.Alexjones:BAAALgADCgUJBwAAAA==.Aliand:BAAALgAECgIJAgAAAA==.Aliande:BAAALgADCgUJBQAAAA==.Alnethir:BAAALgAECgEJAQAAAA==.Aloray:BAAALgADCgcJCgAAAA==.Alordis:BAAALgADCgMJAwAAAA==.Alpharetta:BAAALgAECgcJBgAAAA==.Alsou:BAAALgADCgUJBQAAAA==.Alvarah:BAAALgADCgMJAwAAAA==.Alynas:BAABLgAECn8aAAIEAAkJBgxiSgB5AQAEAAkJBgxiSgB5AQAAAA==.Alysona:BAABLgAECn8PAAIFAAYJ3BkmNgBdAQAFAAYJ3BkmNgBdAQAAAA==.',
Am='Amahra:BAAALgAECgQJBwAAAA==.Amelio:BAAALgADCgIJAgAAAA==.Amewow:BAAALgAFFAIJAwAAAA==.',
An='Anadoria:BAAALgADCgYJBgAAAA==.Analferret:BAAALgAECgUJDgAAAA==.Anastæsia:BAAALgADCgYJBwABLgAECgMJAwACAAAAAA==.Anda:BAAALgAECgMJAwAAAA==.Anitabidet:BAAALgADCgcJBwAAAA==.',
Ap='Apepi:BAAALgADCgcJBwAAAA==.Apolion:BAAALgADCgQJBAAAAA==.Apoundofcake:BAAALgAECgEJAQAAAA==.Appauling:BAAALgADCgYJBgAAAA==.',
Ar='Arclore:BAAALgAFFAEJAQAAAA==.Argenor:BAAALgAECgUJCgAAAA==.Ariadni:BAAALgAECgYJDAAAAA==.Aricict:BAAALgAECgMJAwAAAA==.Arlý:BAAALgAECgEJAwAAAA==.Aruneza:BAABLgAECn8gAAIGAAgJzw5NDACDAQAGAAgJzw5NDACDAQAAAA==.',
As='Asajj:BAAALgAECgQJCgAAAA==.Ashange:BAAALgAECgMJAwAAAA==.Asharie:BAAALgADCgEJAQAAAA==.Ashcatchm:BAAALgADCgMJAwABLgAECgcJEQACAAAAAA==.Ashergon:BAAALgAECgQJBAABLgAECggJFwAHAAckAA==.Asheriz:BAAALgAECgUJCQABLgAECggJFwAHAAckAA==.Asherous:BAABLgAECn8XAAMHAAgJByRYFwBbAgAHAAgJByRYFwBbAgAIAAEJbgxLhgA0AAAAAA==.Ashiashi:BAAALgAECgEJAQABLgAECgcJFAABAAEcAA==.Ashomá:BAAALgADCgcJCAAAAA==.Ashèr:BAAALgAECgYJCwABLgAECggJFwAHAAckAA==.Aszura:BAAALgADCgUJBQAAAA==.',
Au='Auntieshaman:BAAALgADCgEJAQAAAA==.Auranhis:BAAALgAECgEJAQAAAA==.Auriailas:BAAALgADCgcJCQAAAA==.Autoignition:BAAALgADCgMJAwAAAA==.',
Av='Avidel:BAAALgAECgcJEAAAAA==.Avryn:BAAALgAECgYJEgAAAA==.',
Ay='Ayilime:BAAALgAECgQJBQAAAA==.',
Ba='Badcompanytt:BAAALgADCgIJAgAAAA==.Balør:BAAALgAECgMJAwABLgAECggJHwAJAIwQAA==.',
Be='Beanvoid:BAAALgADCgYJBgAAAA==.Beardsaint:BAAALgADCgUJBQAAAA==.Beefini:BAAALgAECgMJAwABLgAECggJIAAKADwlAA==.Beenah:BAAALgAECgYJEwAAAA==.Belethiel:BAAALgADCgEJAQAAAA==.Bellinopher:BAAALgADCggJCAABLgAECgcJHAALAHoRAA==.Benafflock:BAAALgAECgYJBwAAAA==.Bence:BAAALgAECgMJBAABLgAECggJEQACAAAAAA==.Benefitheals:BAAALgAECgIJAgAAAA==.Benefitsham:BAAALgADCgYJBgAAAA==.',
Bi='Bigbibble:BAABLgAECn8aAAIMAAgJ1RTsFwCRAQAMAAgJ1RTsFwCRAQAAAA==.Birdien:BAAALgAECgYJBgAAAA==.',
Bl='Blackrose:BAAALgADCgIJAgABLgAFFAIJAwACAAAAAA==.Blamson:BAAALgADCgYJCgAAAA==.Bloodrain:BAAALgAECgkJEAAAAA==.',
Bo='Boomie:BAAALgAFFAUJBAAAAA==.Booptyboop:BAAALgAECgQJCwAAAA==.Booptydo:BAAALgADCgYJBgAAAA==.Boris:BAAALgAECgEJAQAAAA==.Bowhawk:BAAALgAECgUJEAAAAA==.Bozag:BAAALgADCgIJAgAAAA==.',
Br='Braiin:BAAALgAECgUJBgABLgAFFAUJGAAEAFQZAA==.Brakken:BAAALgADCgQJBAAAAA==.Bravebolt:BAAALgAECgQJBAAAAA==.Brawll:BAAALgAECgEJAgAAAA==.Brazyn:BAAALgADCgYJBgAAAA==.Brevarda:BAABLgAECn8jAAMHAAYJzyGPGADtAQAHAAYJzyGPGADtAQAIAAYJaA1UKwAMAQAAAA==.Brubble:BAAALgADCgMJAwAAAA==.Brugg:BAAALgADCgYJBgAAAA==.',
Bu='Bubbles:BAAALgADCgEJAQAAAA==.Bubblzmgee:BAABLgAECn8iAAILAAgJJg4lEwCsAQALAAgJJg4lEwCsAQAAAA==.',
Ca='Cadence:BAAALgAECgEJAgAAAA==.Cadin:BAABLgAECn8VAAMHAAkJSxmQDQCvAgAHAAkJSxmQDQCvAgAIAAcJYhdeLwCkAQAAAA==.Cakeman:BAAALgADCgEJAQAAAA==.Calehunter:BAAALgADCgEJAQAAAA==.Capnblood:BAAALgAECgEJAQAAAA==.Capone:BAAALgAECgUJBQAAAA==.Carahz:BAABLgAECn8UAAINAAYJDgwtFgC0AAANAAYJDgwtFgC0AAAAAA==.Carindria:BAAALgAECgEJAQAAAA==.Caylavana:BAAALgAFFAEJAQAAAA==.',
Ce='Celaylria:BAAALgAECgYJDgAAAA==.',
Ch='Chabz:BAAALgAECgQJAwAAAA==.Chai:BAABLgAECn8dAAMOAAgJNBq+DwDWAQAOAAgJNBq+DwDWAQAEAAYJzRh5OQDAAQABLgAFFAUJEAAPAJIaAA==.Charmed:BAAALgAECgkJEgAAAA==.Charmíng:BAAALgAECgYJDAAAAA==.Cheryll:BAAALgAECgUJBQAAAA==.Chunknörris:BAAALgADCggJCAAAAA==.',
Ci='Cint:BAAALgAECgQJCwAAAA==.',
Cl='Cloudedjade:BAABLgAECn8VAAIQAAYJFApNGQDLAAAQAAYJFApNGQDLAAAAAA==.',
Co='Coleybear:BAAALgAECgYJDQAAAA==.Copedk:BAABLgAECn8gAAIDAAgJWRoEBwAjAgADAAgJWRoEBwAjAgAAAA==.Copedogg:BAAALgADCgcJDgAAAA==.Copemonkk:BAAALgADCgMJAwAAAA==.Corrode:BAAALgAECggJCAAAAA==.Covertm:BAAALgAECgcJEgAAAA==.Covertw:BAAALgADCgEJAQAAAA==.',
Cr='Craq:BAAALgAECgEJAQAAAA==.Crashedout:BAAALgADCgEJAgAAAA==.Crashknight:BAAALgAECgEJAQABLgAECgQJBwACAAAAAA==.Crew:BAAALgAECgMJAwAAAA==.Crims:BAABLgAECn8ZAAIGAAgJ4BZvBwD9AQAGAAgJ4BZvBwD9AQAAAA==.',
Cu='Culture:BAAALgAECgYJEAAAAA==.',
Cy='Cybeldin:BAABLgAECn8iAAIRAAgJqAnnCgBBAQARAAgJqAnnCgBBAQAAAA==.Cyberdemonxd:BAAALgADCgUJCQABLgAECggJFAAKAH4PAA==.',
Da='Daadeedaa:BAACLgAFFH8KAAISAAQJNhezIwBhAQASAAQJNhezIwBhAQAuAAQKfzAAAhIACAkpJDsOAKsCABIACAkpJDsOAKsCAAAA.Daddysparey:BAABLgAECn8VAAIFAAYJJg8CTwAMAQAFAAYJJg8CTwAMAQAAAA==.Dagoba:BAAALgAECgMJAgAAAA==.Dakk:BAABLgAECn8oAAISAAgJNhZ5MQDbAQASAAgJNhZ5MQDbAQAAAA==.Dardeathicus:BAACLgAFFH8MAAIKAAQJPR5OIwBZAQAKAAQJPR5OIwBZAQAuAAQKfyAAAgoACQnNIIMoAJgCAAoACQnNIIMoAJgCAAAA.Darderyag:BAAALgAECggJEgAAAA==.Darek:BAAALgAECgYJDwAAAA==.Dariara:BAAALgAECgEJAQAAAA==.Darkbud:BAAALgADCggJEQAAAA==.Darkfeazer:BAAALgADCgEJAQAAAA==.Darkforge:BAAALgAECgYJBQAAAA==.Darkrife:BAAALgADCggJCAAAAA==.Darmonkicus:BAAALgAFFAIJAgAAAA==.Dazzan:BAAALgADCgUJBQAAAA==.',
De='Deadlocks:BAAALgADCgEJAQAAAA==.Deathhold:BAAALgAECgYJBwAAAA==.Debilitation:BAAALgADCgIJAgAAAA==.Dedrys:BAAALgAECgEJAQAAAA==.Deklan:BAAALgAECgEJAwAAAA==.Delsid:BAAALgAECgMJAwAAAA==.Demonsteven:BAAALgADCgcJCgAAAA==.Dependabull:BAAALgADCgYJCQABLgADCgcJBwACAAAAAA==.Dernis:BAAALgADCgMJAwAAAA==.Deshaman:BAABLgAECn8WAAIIAAgJwwjCIwA2AQAIAAgJwwjCIwA2AQABLgAFFAQJDQATALUbAA==.Devilbeast:BAAALgAECgQJCQAAAA==.',
Dh='Dhargo:BAAALgADCgcJBwAAAA==.',
Di='Dirte:BAAALgADCgYJDQAAAA==.Dirty:BAABLgAECn8eAAIIAAgJ5BOHJQDlAQAIAAgJ5BOHJQDlAQAAAA==.',
Dk='Dkbygorm:BAAALgADCgQJBwAAAA==.',
Do='Dolfi:BAAALgADCggJDAAAAA==.Dorlesette:BAABLgAECn8kAAMUAAkJpwfcHwBHAQAUAAkJpwfcHwBHAQAJAAIJ7ALtWwBEAAAAAA==.',
Dr='Dravindil:BAAALgAECgcJBgAAAA==.Dreamlesnite:BAABLgAECn8XAAIVAAcJCwbGXwARAQAVAAcJCwbGXwARAQAAAA==.Dreidelman:BAAALgAECgIJAgAAAA==.Drkstar:BAAALgAECgYJDAAAAA==.',
Du='Dunthur:BAAALgADCgYJBgAAAA==.Duoda:BAAALgAFFAIJAwABLgAFFAYJEQAGAM8RAA==.Durto:BAAALgADCgkJGAABLgAECgQJBwACAAAAAA==.',
Dy='Dylora:BAABLgAECn8iAAIUAAgJ3RbhEwC/AQAUAAgJ3RbhEwC/AQAAAA==.',
['Dï']='Dïesel:BAAALgAECgIJAgAAAA==.',
['Dó']='Dólores:BAAALgADCgYJBgAAAA==.',
['Dö']='Dödskott:BAAALgADCgcJBwAAAA==.',
Ec='Eclipsa:BAAALgAECgcJBwAAAA==.',
Eg='Egregore:BAAALgAECgYJEQAAAA==.',
El='Elassha:BAAALgAECgEJAQAAAA==.Eliwena:BAAALgAECggJEwAAAA==.Ellaria:BAABLgAECn8gAAMFAAgJ2RStKQCSAQAFAAgJfRGtKQCSAQAWAAYJVhjhJQCQAQAAAA==.Elluna:BAAALgADCgEJAQAAAA==.Elyselyia:BAAALgAECgUJBQAAAA==.Elysindrall:BAABLgAECn8fAAIGAAcJkBHNCwCPAQAGAAcJkBHNCwCPAQAAAA==.',
Em='Emokins:BAABLgAECn8iAAIIAAgJSyPNAwDHAgAIAAgJSyPNAwDHAgAAAA==.',
En='Endesh:BAABLgAECn8iAAMPAAgJrweWIgAwAQAPAAgJrweWIgAwAQAXAAMJ7QX7EwBSAAAAAA==.Enolah:BAAALgADCgMJAwAAAA==.',
Er='Eradica:BAAALgADCgYJDQAAAA==.Erubus:BAACLgAFFH8HAAMJAAIJpB+BJQC/AAAJAAIJpB+BJQC/AAAYAAEJQwGTFAA9AAAuAAQKfxYABAkACQl9IEUWAFcCAAkACQl9IEUWAFcCABQAAgk2E/lWAHMAABgAAQm/DsV5ADcAAAAA.Eryss:BAABLgAECn8UAAITAAYJJgc/YQDsAAATAAYJJgc/YQDsAAAAAA==.',
Es='Escånor:BAAALgAECgYJBgAAAA==.Esmeraldita:BAAALgADCgYJDwAAAA==.',
Ev='Evercleâr:BAAALgADCgkJAgAAAA==.Evilblixz:BAAALgADCgYJAQAAAA==.Evoked:BAABLgAECn8UAAMGAAYJEwwgEwAMAQAGAAYJEwwgEwAMAQAXAAUJdAU9EgBkAAAAAA==.',
Ex='Excentric:BAAALgAECgYJCgABLgAFFAUJDAASAJcaAA==.Expiraman:BAAALgADCgYJBgAAAA==.',
Fa='Faeliel:BAAALgADCgYJBgABLgAFFAUJDgAZAH0YAA==.Faelýn:BAAALgAECgYJDQAAAA==.Faessa:BAAALgADCgIJAgAAAA==.Fanden:BAAALgADCgYJCQAAAA==.Fartimer:BAAALgADCgYJBgABLgAECgkJGwAEAG0VAA==.',
Fd='Fdk:BAAALgADCgMJAwAAAA==.',
Fe='Feathering:BAAALgAECgYJEgAAAA==.Fellariene:BAAALgADCgcJCAAAAA==.Fellcaster:BAAALgAECgQJBgAAAA==.Feoralaure:BAAALgADCgEJAQAAAA==.',
Fi='Figjam:BAAALgADCgcJBwAAAA==.',
Fl='Fluoria:BAAALgAECgQJCgAAAA==.Fláreon:BAABLgAECn8UAAIaAAcJDRg9HQAsAgAaAAcJDRg9HQAsAgAAAA==.',
Fr='Fragarach:BAAALgAECgEJAQAAAA==.Frostynipie:BAAALgADCgMJAwAAAA==.Frutypebblz:BAABLgAECn8XAAIbAAYJ6ghPEADWAAAbAAYJ6ghPEADWAAAAAA==.',
Fu='Fuzznn:BAAALgAECgMJAwABLgABCgIJAgACAAAAAA==.',
['Fà']='Fàmous:BAABLgAECn8YAAMLAAkJ6RYHCwAiAgALAAkJ/BIHCwAiAgAMAAIJvB4IYgCoAAAAAA==.',
Ga='Gainful:BAAALgADCgQJBAABLgAFFAEJAQACAAAAAA==.Galabris:BAABLgAECn8iAAIDAAgJVSIQAwCtAgADAAgJVSIQAwCtAgAAAA==.Galen:BAAALgAECgEJAgAAAA==.',
Ge='Geranin:BAAALgADCgUJCAAAAA==.Gervire:BAAALgADCgcJCAAAAA==.',
Gh='Ghouldân:BAAALgADCgMJBQAAAA==.Ghoulmania:BAAALgAECgkJCwAAAA==.',
Gi='Gimglich:BAAALgADCgYJAQAAAA==.Gimligrimes:BAAALgADCgEJAQAAAA==.Ginx:BAAALgADCgMJBAAAAA==.Gitchusum:BAAALgAECgEJAQAAAA==.',
Gl='Glaedry:BAAALgAECgEJAwAAAA==.',
Go='Goose:BAABLgAECn8UAAILAAgJKxNcFwB9AQALAAgJKxNcFwB9AQAAAA==.Gorefang:BAAALgAECgEJAQAAAA==.Gormladin:BAABLgAECn8UAAIaAAYJIBkmIwBuAQAaAAYJIBkmIwBuAQAAAA==.',
Gr='Greenbahamut:BAAALgAECgEJAQAAAA==.Gregamesh:BAAALgADCgcJDgAAAA==.Grill:BAAALgAECgMJAwAAAA==.Grimsreaper:BAAALgADCgkJDgAAAA==.Grizzlypouch:BAAALgADCgYJBgAAAA==.Grouchy:BAAALgAECgEJAQAAAA==.',
Gu='Guillimus:BAAALgADCgcJBgAAAA==.Gultadorn:BAAALgADCgMJAwAAAA==.',
['Gï']='Gïzmö:BAAALgAECgYJDQAAAA==.',
Ha='Halfang:BAAALgADCgYJEQAAAA==.Handham:BAAALgAECgYJCQAAAA==.Hasheth:BAAALgAECgYJCQAAAA==.Havocfang:BAAALgADCgIJAQAAAA==.Hawkiing:BAAALgADCgQJBAAAAA==.Hazuki:BAAALgAECgMJAwAAAA==.',
He='Helouise:BAAALgADCgQJBAAAAA==.Herbalxur:BAAALgAECgQJCAAAAA==.',
Hi='Hibikase:BAAALgAECgYJBgAAAA==.Hildegarde:BAAALgAECgEJAQABLgAECgYJDQACAAAAAA==.Hitpoints:BAAALgAECgUJEQAAAA==.',
Ho='Hobbikeen:BAABLgAECn8hAAMGAAgJ/hz7AgCwAgAGAAgJ/hz7AgCwAgAPAAcJag+9HgBJAQAAAA==.Holyhope:BAABLgAECn8XAAIaAAcJmxMGHwCOAQAaAAcJmxMGHwCOAQAAAA==.Holymana:BAABLgAECn8eAAIBAAcJNRi2MQC2AQABAAcJNRi2MQC2AQAAAA==.Hoshea:BAAALgADCgMJAwAAAA==.Hottyoreo:BAAALgADCgYJCwAAAA==.Howcom:BAAALgADCgcJBwAAAA==.',
Hu='Huffingpaint:BAAALgAECgYJDQAAAA==.Hundrakor:BAAALgAECgUJBQAAAA==.Huntinghawk:BAAALgAECgEJAQABLgAECgUJEAACAAAAAA==.Hutzil:BAABLgAECn8ZAAMVAAcJQRmVPAB1AQAVAAcJIReVPAB1AQAcAAMJWRnDDQCnAAAAAA==.',
['Hÿ']='Hÿpothermia:BAAALgAECgMJAwAAAA==.',
Il='Illidianna:BAABLgAECn8aAAMFAAgJzRe9GwDjAQAFAAgJzRe9GwDjAQAWAAIJixJgXABvAAAAAA==.',
Im='Imitlol:BAAALgAECgEJAQAAAA==.',
In='Inception:BAAALgADCgkJEQAAAA==.',
Ir='Irrefutable:BAAALgADCgQJBAAAAA==.',
It='Itchynyple:BAAALgADCggJCAAAAA==.',
Ja='Jackatak:BAAALgADCgMJAwAAAA==.Jacoblack:BAAALgADCgMJAwAAAA==.Jadin:BAAALgADCgEJAQAAAA==.Jaefury:BAABLgAECn8YAAIdAAgJVxtoBAAjAgAdAAgJVxtoBAAjAgAAAA==.Jakes:BAAALgADCggJCAAAAA==.Jandinga:BAAALgAECgQJBAAAAA==.',
Ji='Jimadler:BAAALgADCgMJAwABLgADCgkJJAACAAAAAA==.Jimbi:BAAALgAFFAEJAQAAAA==.Jiminybilini:BAAALgAECgcJBQAAAA==.Jimmybull:BAAALgADCgEJAQAAAA==.Jinho:BAAALgAECgEJAQABLgAECgkJFQAeADchAA==.Jinrop:BAEALgADCgcJBwABLgAECgcJFgAbACMUAA==.',
Jo='Jobuu:BAAALgAECgEJAgAAAA==.Johnnypopoff:BAABLgAECn8gAAISAAgJvhVcNgDIAQASAAgJvhVcNgDIAQAAAA==.Johnwolf:BAAALgAECgQJBQAAAA==.Jojohunts:BAAALgAECgYJCgAAAA==.',
Jp='Jpðc:BAAALgAECgYJCgAAAA==.',
Ju='Juanjo:BAAALgADCgcJBwABLgAECggJKgASALMaAA==.Junyubych:BAAALgAECgQJCgAAAA==.Justylln:BAAALgADCgMJAgAAAA==.Justzach:BAABLgAECn8uAAIJAAkJ+xlwBQCKAgAJAAkJ+xlwBQCKAgAAAA==.',
['Jà']='Jàccuse:BAAALgAECgYJDgAAAA==.Jàrnsaxa:BAAALgADCgEJAQAAAA==.',
['Jò']='Jòhnnypopo:BAAALgADCgYJBgAAAA==.',
Ka='Kadywompus:BAAALgADCgcJBwAAAA==.Kaeladra:BAAALgADCgcJDgAAAA==.Kailm:BAAALgADCgIJAgABLgAFFAQJCQAZAPkcAA==.Kait:BAAALgAECgIJAgAAAA==.Kalniel:BAAALgADCgUJBQAAAA==.Kassaalaa:BAAALgADCgYJBgAAAA==.Kasume:BAAALgAECgMJAwAAAA==.Kaylastrasza:BAAALgADCgEJAQAAAA==.Kazurend:BAACLgAFFH8SAAIfAAYJriHBAQDvAQAfAAYJriHBAQDvAQAuAAQKfxoAAh8ACAnQI7wFADMDAB8ACAnQI7wFADMDAAAA.',
Ke='Kelavax:BAAALgAECgkJBQAAAA==.Keleira:BAAALgAECgYJEAAAAA==.Kelemvore:BAAALgADCgMJBgAAAA==.Kericcandere:BAAALgADCgIJAwAAAA==.Kerm:BAEALgAECgEJAQAAAA==.Keyaielenst:BAAALgADCgcJBwAAAA==.',
Kh='Khristina:BAAALgADCgkJCgAAAA==.',
Ki='Kiel:BAAALgAFFAMJAwABLgAECgYJDAACAAAAAA==.Kindos:BAAALgADCgQJBwAAAA==.Kippo:BAEALgAECgEJAQABLgAFFAQJBwASAIYFAA==.Kiramman:BAAALgAECgUJCwAAAA==.Kirsute:BAAALgADCgYJBgAAAA==.Kirxcy:BAAALgADCgMJAwAAAA==.Kithiri:BAAALgAECgQJCgAAAA==.',
Kn='Knarn:BAABLgAECn8hAAIgAAgJtB7qCAAYAgAgAAgJtB7qCAAYAgAAAA==.',
Ko='Koralie:BAACLgAFFH8ZAAMTAAYJkxjWAACrAQATAAUJVBzWAACrAQARAAEJkAkhGQBVAAAuAAQKfxkAAxMACAk6HW8bAGICABMACAk6HW8bAGICABEABAmsDZxcANAAAAAA.',
Kr='Krillaxx:BAAALgAECgcJDwAAAA==.Krimzin:BAAALgAECgcJBwABLgAFFAQJCQATAD0bAA==.Krolg:BAAALgAECgQJCQAAAA==.Kromvar:BAAALgAECgQJBwAAAA==.',
Ku='Kungfused:BAAALgADCgUJCAABLgAECgIJAgACAAAAAA==.Kurisux:BAAALgAFFAIJAwAAAA==.',
Ky='Kyliekat:BAAALgAECgYJBwAAAA==.Kyndlynn:BAAALgAECgQJCwAAAA==.',
La='Lanceelot:BAAALgAECgIJAgAAAA==.Lanel:BAAALgAECgUJCQAAAA==.Lathelous:BAABLgAECn8hAAIQAAgJlCNxAQDKAgAQAAgJlCNxAQDKAgAAAA==.',
Ld='Ldt:BAAALgADCgMJAwAAAA==.',
Le='Leintheir:BAAALgAECgMJAwAAAA==.Leththol:BAAALgADCgkJJQAAAA==.Letyoudie:BAAALgAECgQJCwAAAA==.Levenza:BAAALgAECgcJEgAAAA==.',
Li='Lideina:BAABLgAECn8VAAIKAAYJMRbnfQDlAAAKAAYJMRbnfQDlAAAAAA==.Lielandra:BAAALgAECgEJAQAAAA==.Lightt:BAABLgAECn8vAAMMAAgJQxjMCgA6AgAMAAgJQxjMCgA6AgAfAAUJNQEKVQBvAAAAAA==.Liightt:BAAALgAECgUJDQAAAA==.Lilnug:BAAALgAECgQJDAAAAA==.Lindsey:BAAALgADCgkJDQABLgAECgQJBQACAAAAAA==.Littlenyne:BAAALgAECgQJBAAAAA==.',
Ll='Llando:BAAALgADCgYJBgAAAA==.Llars:BAABLgAECn8hAAIHAAgJyRo6DwBIAgAHAAgJyRo6DwBIAgAAAA==.Lleonardo:BAAALgADCgEJAQAAAA==.',
Lo='Lockkjaw:BAAALgADCgEJAQAAAA==.Locknorris:BAAALgADCgUJBgAAAA==.Loghrif:BAAALgAECgQJBAABLgAECgUJBgACAAAAAA==.Loptear:BAAALgAECgEJAQAAAA==.Loryanna:BAAALgADCgUJCwAAAA==.Louie:BAAALgAECgMJBAAAAA==.Lovehandless:BAAALgADCgEJAQAAAA==.Lovespell:BAAALgADCgUJBQAAAA==.',
Lu='Lucavian:BAAALgAECgYJCgAAAA==.Lucavias:BAAALgAECgMJBQAAAA==.Luckydruidh:BAAALgAECgYJDAAAAA==.Luckyevoker:BAAALgADCgcJEgABLgAECgYJDAACAAAAAA==.Lurien:BAAALgAECggJDgAAAA==.Luxilejo:BAAALgADCgYJCwAAAA==.',
Ly='Lyfebane:BAABLgAECn8lAAMaAAgJMxgDDwAqAgAaAAgJMxgDDwAqAgABAAcJbBAkTABhAQAAAA==.',
['Ló']='Lórien:BAAALgADCgEJAQAAAA==.',
['Lø']='Lørs:BAABLgAECn8dAAISAAYJnQ/3jgD1AAASAAYJnQ/3jgD1AAAAAA==.',
Ma='Machorn:BAAALgADCgcJBwAAAA==.Magetree:BAAALgAECgYJCQABLgAFFAQJCQAQAJcZAA==.Mageyoucream:BAAALgADCgEJAQAAAA==.Magnai:BAAALgADCgcJBwAAAA==.Main:BAABLgAECn8nAAIBAAgJiAoMdwD+AAABAAgJiAoMdwD+AAAAAA==.Malagore:BAAALgAECggJCAABLgAECggJFwAPAKwVAA==.Malec:BAAALgADCggJCAAAAA==.Malicemech:BAAALgADCgcJBwAAAA==.Maliceone:BAAALgAECgYJCgAAAA==.Malicepaly:BAAALgAECgEJAQAAAA==.Manek:BAAALgADCgQJBAABLgAECggJKAASADYWAA==.Mansmilk:BAAALgAECgQJBAAAAA==.Mattshamon:BAAALgADCgcJBwAAAA==.Max:BAABLgAECn8YAAIVAAgJBx//KgC5AQAVAAgJBx//KgC5AQAAAA==.',
Mb='Mbaku:BAAALgAECgYJCgABLgAECgkJJwAfAOAcAA==.',
Me='Melinoe:BAAALgAECgYJDQAAAA==.Merc:BAAALgAECgUJBQAAAA==.Merithrá:BAAALgAECgIJAgAAAA==.',
Mi='Micah:BAACLgAFFH8VAAIGAAcJThAsBQDYAQAGAAcJThAsBQDYAQAuAAQKfxgAAwYACAnkGgQOAFYCAAYACAnkGgQOAFYCAA8ABQm/GpQyADUBAAAA.Mirelia:BAAALgADCgMJAgAAAA==.Mishosuki:BAAALgAECgUJDwAAAA==.Misky:BAAALgADCgEJAQAAAA==.Misscleo:BAABLgAECn8fAAISAAgJjBAHPAC0AQASAAgJjBAHPAC0AQAAAA==.Mizzyboii:BAAALgADCgMJAwAAAA==.',
Mk='Mk:BAAALgAECggJDAAAAA==.',
Mn='Mnesarte:BAABLgAECn8VAAIBAAYJZRawUQBRAQABAAYJZRawUQBRAQAAAA==.',
Mo='Moi:BAABLgAFFH8IAAIPAAUJBxMdFAA6AQAPAAUJBxMdFAA6AQABLgAFFAQJDwASAIsdAA==.Monkilha:BAAALgAECgcJCwAAAA==.Moonkist:BAAALgAECgYJEgAAAA==.Moonsgrace:BAAALgADCggJCAAAAA==.Moose:BAABLgAECn8sAAIKAAgJciAqFgBKAgAKAAgJciAqFgBKAgAAAA==.Morpheos:BAABLgAECn8bAAMEAAkJbRVMMABfAQAEAAkJbRVMMABfAQAOAAQJfAeZOACoAAAAAA==.Morroe:BAAALgADCgEJAQAAAA==.Moxci:BAAALgAECgQJBQAAAA==.',
Mu='Mudamudamuda:BAAALgADCgYJDQABLgAFFAUJDgAZAH0YAA==.Muffintop:BAAALgADCgEJAQAAAA==.',
My='Mysticforest:BAAALgAECgQJBAAAAA==.',
Na='Naedise:BAAALgADCgcJFgAAAA==.Narue:BAAALgAECgIJAgAAAA==.Natureswild:BAABLgAECn8gAAMOAAkJjRi4FACaAQAOAAgJ3Re4FACaAQAEAAMJbQrTuQBSAAAAAA==.Navariis:BAAALgAECgQJBgAAAA==.Navillus:BAAALgAECgMJBgABLgAFFAYJGQAGAL0QAA==.',
Ne='Necrophyliac:BAAALgAECgYJCwAAAA==.Nelrehim:BAAALgADCgQJBgAAAA==.Nephy:BAAALgADCgYJBgAAAA==.Nephyrium:BAAALgADCgUJBQAAAA==.Nephz:BAAALgAECgYJBgAAAA==.Nephzz:BAAALgAECgQJAwAAAA==.Nethery:BAAALgADCgcJCQAAAA==.Nex:BAAALgAECgEJAQAAAA==.Nezrin:BAAALgAECgYJDgAAAA==.',
Ni='Nidon:BAAALgADCgUJBQAAAA==.Niixxi:BAAALgADCgUJBQAAAA==.',
Nm='Nmbrs:BAABLgAECn8YAAMfAAYJRh2rFACdAQAfAAYJRh2rFACdAQALAAEJ7AK7XAApAAAAAA==.',
No='Noirheffer:BAACLgAFFH8JAAMQAAQJlxmpBADVAAABAAMJ9RT2LAD+AAAQAAMJxRSpBADVAAAuAAQKfyIAAwEACQnXHvUXANkCAAEACAlDIvUXANkCABAABgmnDuAoAMMAAAAA.Noobishdad:BAAALgADCgEJAQAAAA==.Norio:BAAALgADCgcJBwAAAA==.',
Nu='Nulannatoo:BAAALgAECgUJBQAAAA==.Nuukeasaur:BAAALgADCgEJAQAAAA==.',
Ny='Nyadari:BAAALgAECgEJAQAAAA==.Nyrrhi:BAAALgAECgQJBAAAAA==.Nyxiro:BAAALgAECgUJBQAAAA==.',
Od='Odysseus:BAAALgADCgkJFgAAAA==.',
Ol='Olgann:BAAALgAECgYJCQAAAA==.Olguita:BAAALgAECgQJBwAAAA==.Olivertwìst:BAAALgADCgcJBwAAAA==.',
Om='Omgowned:BAAALgAECgUJBgABLgAECggJFgAVAJwTAA==.',
On='Onehothealer:BAABLgAECn8aAAIfAAkJIBbnGQAQAgAfAAkJIBbnGQAQAgAAAA==.',
Oo='Oorua:BAAALgADCgkJDwAAAA==.',
Op='Opheliastar:BAABLgAECn8mAAIfAAkJ7hKLDAD+AQAfAAkJ7hKLDAD+AQAAAA==.',
Pa='Pad:BAAALgAECgYJEwAAAA==.Pahket:BAAALgAECgQJBAAAAA==.Paintballerr:BAAALgADCgEJAQAAAA==.Paladerp:BAABLgAECn8vAAMaAAgJGA8rHgCVAQAaAAgJGA8rHgCVAQABAAYJMRF+XQA0AQAAAA==.Pallyown:BAABLgAFFH8IAAIaAAIJwR8CFACiAAAaAAIJwR8CFACiAAAAAA==.Paprika:BAAALgADCgQJBgAAAA==.Pastorbedtym:BAABLgAECn8YAAIfAAgJeA/GGgBlAQAfAAgJeA/GGgBlAQAAAA==.Pat:BAAALgAECgMJAwAAAA==.Paulybricks:BAAALgAECgUJBgAAAA==.',
Pe='Pecan:BAAALgAECgcJDgAAAA==.Pewpewbang:BAAALgADCgIJAgAAAA==.',
Ph='Pharla:BAAALgADCgkJEAAAAA==.',
Pi='Pichon:BAAALgADCgQJBAAAAA==.Pimmscup:BAAALgADCggJCAAAAA==.Pin:BAAALgAECgcJBgAAAA==.Pirozhki:BAAALgADCgYJBgAAAA==.',
Pl='Plagueborn:BAAALgAECgEJAQAAAA==.Plentar:BAAALgADCgEJAgAAAA==.',
Po='Popcorntea:BAAALgAECgEJAQAAAA==.Porgoon:BAAALgAECgQJBQAAAA==.',
Pr='Preserved:BAAALgADCgIJAgAAAA==.',
Ps='Psaul:BAAALgAECgYJCwAAAA==.',
Py='Pyramys:BAAALgADCgYJBgABLgAFFAUJEAAeADsdAA==.',
Qe='Qedeshah:BAAALgAECgYJBgAAAA==.Qesem:BAAALgADCgUJBQAAAA==.',
Qu='Qualaribou:BAAALgADCgQJBAAAAA==.',
Ra='Raal:BAAALgADCgkJHgAAAA==.Raenostra:BAAALgAECgUJDAAAAA==.Raenya:BAAALgADCgkJCQAAAA==.Ragefather:BAAALgADCgEJAQAAAA==.Rageye:BAAALgADCgcJBwAAAA==.Rainydaze:BAAALgAECgYJCwAAAA==.Ramcharger:BAAALgAECgYJDgAAAA==.Ranen:BAABLgAECn8cAAIYAAkJ9BwLBgB1AgAYAAkJ9BwLBgB1AgAAAA==.Rashun:BAAALgAECggJEQAAAA==.',
Re='Redcinnabar:BAAALgAECgQJCQAAAA==.Rehtilox:BAAALgADCgMJAwABLgAECgcJHAALAHoRAA==.Reilly:BAAALgADCggJFQAAAA==.Rev:BAAALgAECgQJBAAAAA==.Rexxy:BAAALgAECgYJCgAAAA==.',
Ri='Riju:BAAALgAECgcJDgAAAA==.Rikashae:BAAALgADCgkJHgAAAA==.Rillan:BAAALgADCgMJAwAAAA==.Rinzler:BAAALgAECgIJBAAAAA==.',
Rn='Rng:BAAALgAECgQJCwAAAA==.',
Ro='Roachcentral:BAAALgADCgUJBgAAAA==.Roachcity:BAAALgADCgUJBQAAAA==.Rockalock:BAAALgADCgYJBgAAAA==.Roleon:BAAALgADCggJCAAAAA==.Rollforpi:BAAALgAECgIJAgABLgAFFAUJGAAEAFQZAA==.Ropebunnyana:BAACLgAFFH8FAAIUAAMJsxqFFADrAAAUAAMJsxqFFADrAAAuAAQKfyUAAhQACQnVH/8BAEgDABQACQnVH/8BAEgDAAAA.Rowkani:BAAALgADCgkJCQAAAA==.',
Ru='Ruki:BAAALgAECgQJDgABLgAECgYJDQACAAAAAA==.',
Ry='Ryand:BAAALgAECgUJCQABLgAFFAQJCQAeAE4VAA==.',
Sa='Sacra:BAAALgAECgEJAQAAAA==.Salarcyn:BAAALgAECgUJDAAAAA==.Samiracy:BAABLgAECn8iAAIbAAgJWBj9AgAFAgAbAAgJWBj9AgAFAgAAAA==.Sannrin:BAAALgAECgYJDAAAAA==.Santhrin:BAAALgADCgcJBwAAAA==.Sapprot:BAAALgADCgcJCQAAAA==.Sarkress:BAAALgADCgkJCQAAAA==.',
Se='Seagal:BAAALgADCgEJAgAAAA==.Senbatorii:BAAALgAECgYJDQAAAA==.Seredala:BAAALgADCgUJCwAAAA==.Sethrow:BAABLgAECn8WAAMVAAgJnBOcJgDOAQAVAAcJnBOcJgDOAQAbAAEJAACwMwAAAAAAAA==.Severa:BAAALgADCgIJAgAAAA==.',
Sh='Shalia:BAAALgADCgMJAwABLgADCgMJBgACAAAAAA==.Sharas:BAAALgAECgQJBQAAAA==.Shawarma:BAAALgAECgUJBgAAAA==.Sheltatha:BAAALgAECgEJAQAAAA==.Shengari:BAABLgAECn8hAAIMAAgJbBK+FwCSAQAMAAgJbBK+FwCSAQAAAA==.Shotcallà:BAAALgADCgIJAgAAAA==.Shuna:BAAALgAECgUJCwAAAA==.Shyly:BAAALgAECggJEwAAAA==.Shâbs:BAAALgAECgIJAgAAAA==.',
Si='Sikkly:BAAALgADCgcJEQAAAA==.Siley:BAABLgAECn9CAAIKAAkJQBIbOACZAQAKAAkJQBIbOACZAQAAAA==.Sin:BAAALgAECgcJCAAAAA==.Siphon:BAAALgADCgYJBgAAAA==.',
Sk='Skarletfaith:BAAALgAECgUJDQAAAA==.',
Sl='Sloanya:BAABLgAECn8wAAMUAAkJ4B1VAwADAwAUAAkJ4B1VAwADAwAYAAYJKxqcJQCqAQAAAA==.',
Sn='Snarffie:BAAALgAECgYJCgAAAA==.',
So='Solanar:BAAALgADCgUJBQAAAA==.Somedruid:BAABLgAECn8hAAIOAAgJWCMDBAC9AgAOAAgJWCMDBAC9AgAAAA==.',
Sp='Spiarmf:BAAALgADCgUJBQAAAA==.Spicynes:BAAALgADCgQJBwAAAA==.Spicyness:BAAALgAECgIJAgAAAA==.Spiderdk:BAAALgAECgUJCAABLgAFFAQJDQATALUbAA==.Spidermonk:BAAALgADCgcJDgABLgAFFAQJDQATALUbAA==.Spëcter:BAAALgAECgUJBQABLgAECggJEgACAAAAAA==.Spëcthyr:BAAALgAECggJEgAAAA==.',
Sq='Squishypoo:BAAALgAECgMJAwAAAA==.',
St='Stache:BAAALgAECgEJAQAAAA==.Stoneyfoam:BAAALgAECgYJBgAAAA==.Stormrider:BAAALgADCgkJCQAAAA==.',
Su='Sugrace:BAAALgAECgYJBgAAAA==.Superdemonzz:BAACLgAFFH8IAAIFAAQJTRISHwAwAQAFAAQJTRISHwAwAQAuAAQKfxsAAwUACAlDHbgZAO8BAAUACAlDHbgZAO8BACEAAgmNCjUnAEwAAAAA.Superevokerz:BAAALgADCgcJDgABLgAFFAQJCAAFAE0SAA==.Superlockz:BAAALgADCgkJCQABLgAFFAQJCAAFAE0SAA==.Superpallyz:BAABLgAECn8lAAMaAAcJgBl3JwDvAQAaAAcJgBl3JwDvAQAQAAQJTgqKMACQAAABLgAFFAQJCAAFAE0SAA==.Supershamanz:BAAALgAECgYJCgABLgAFFAQJCAAFAE0SAA==.Superspidey:BAAALgADCgIJAgAAAA==.Sushiroll:BAAALgAECgYJDwAAAA==.',
Sy='Sydnysweeney:BAAALgADCgMJAwAAAA==.Sylentslit:BAAALgADCggJGgAAAA==.Sylveslem:BAAALgAECgkJEgAAAA==.Syphon:BAAALgADCgMJAwAAAA==.',
['Sô']='Sôlmyr:BAAALgADCgIJAgAAAA==.',
Ta='Tacowarr:BAAALgADCgUJBQAAAA==.Taldazlian:BAAALgAECgMJAwAAAA==.Taliesin:BAAALgAECgMJAwAAAA==.Tallon:BAAALgAECgEJAQABLgAFFAQJCgAPAKoXAA==.Tantalus:BAAALgAECgcJCgAAAA==.Tarogen:BAAALgADCgUJBQAAAA==.Tashaler:BAAALgADCgEJAQAAAA==.',
Te='Tealet:BAAALgADCgkJEQAAAA==.Tellinor:BAAALgAECgYJDAAAAA==.Temporal:BAAALgAECgEJAQAAAA==.Terrestra:BAAALgADCgMJAwAAAA==.Tervor:BAAALgADCgEJAQAAAA==.',
Th='Thanamoros:BAAALgAECgUJBgABLgAFFAMJBwAPAKYOAA==.Thassarian:BAAALgAECgQJBAABLgAECggJGgAhAJYcAA==.Thechosenone:BAAALgADCgIJAgAAAA==.Theroach:BAAALgAECgUJCAAAAA==.Throfin:BAAALgAECgUJCgAAAA==.',
Ti='Tinc:BAAALgADCgEJAgAAAA==.Tinkerballa:BAAALgADCgUJBQAAAA==.Tinonova:BAAALgAECgEJAgAAAA==.Titsmgee:BAAALgAECgIJAgAAAA==.',
To='Toeren:BAACLgAFFH8NAAITAAQJtRu2CAB5AQATAAQJtRu2CAB5AQAuAAQKfyIAAhMACAm/H54VAIsCABMACAm/H54VAIsCAAAA.Tomate:BAAALgADCgQJBAAAAA==.Toph:BAAALgAECgEJAQAAAA==.Tormented:BAAALgAECgYJEwAAAA==.Townsley:BAAALgAECgYJDQAAAA==.',
Tp='Tpain:BAAALgADCgIJAgAAAA==.',
Tr='Traitoros:BAAALgADCgYJBgAAAA==.Tralectra:BAAALgAECgcJDAAAAA==.Tranquilfist:BAAALgADCgQJBQABLgAECgUJDQACAAAAAA==.Treemonk:BAAALgADCgYJCgABLgAECgkJIAAOAI0YAA==.Trolvere:BAAALgAECgQJBwAAAA==.Trorim:BAAALgADCgYJBgAAAA==.Trïsh:BAAALgAECgEJAQAAAA==.',
Tu='Tummy:BAAALgADCgcJEwAAAA==.Turtlesoup:BAAALgADCgYJBgAAAA==.',
Ty='Tygragon:BAAALgAECgQJCAAAAA==.Tyinorin:BAAALgAECgIJAQAAAA==.',
Tz='Tzipporah:BAAALgAECgYJBgAAAA==.',
Ub='Ubee:BAABLgAECn8WAAIFAAgJWhE7KwCLAQAFAAgJWhE7KwCLAQAAAA==.',
Ul='Ultimakitty:BAAALgAECgYJDAAAAA==.',
Un='Unchanged:BAAALgADCgYJBgAAAA==.Unholymana:BAAALgADCgkJDgAAAA==.',
Va='Vaellin:BAAALgAECgEJAQAAAA==.Valanyr:BAAALgADCgEJAQAAAA==.Vantrix:BAAALgAECgEJAQABLgAFFAMJBwAPAKYOAA==.Varabo:BAAALgAECgYJDAAAAA==.Varolina:BAAALgADCgcJEQAAAA==.',
Ve='Vehemencê:BAAALgADCgEJAQAAAA==.Velements:BAAALgAECgMJAwABLgAECggJEAACAAAAAA==.Velemon:BAACLgAFFH8KAAIiAAQJ9AlsDADuAAAiAAQJ9AlsDADuAAAuAAQKfxQAAiIACAlLEvARAOkBACIACAlLEvARAOkBAAAA.Velisen:BAAALgAECgUJDQAAAA==.Velthala:BAAALgAECggJEAAAAA==.Velystiri:BAAALgADCgcJBgAAAA==.Venedictus:BAAALgADCgMJAwAAAA==.',
Vi='Viergryn:BAAALgADCgkJCQABLgAECgcJEQACAAAAAA==.Virasdruid:BAAALgAECgIJBAAAAA==.Virusmonk:BAAALgAECgEJBAAAAA==.Vitner:BAABLgAECn8ZAAMXAAkJvhRABQCPAQAXAAYJMBlABQCPAQAPAAgJexA7LwDpAAAAAA==.',
Vo='Vosaleana:BAAALgADCgMJAwAAAA==.',
Vr='Vraak:BAACLgAFFH8YAAIEAAUJVBmpCwCGAQAEAAUJVBmpCwCGAQAuAAQKfycAAwQACAnhG7QrAAECAAQABwmBHbQrAAECAA4ABwmZIxAgAP4BAAAA.',
Vu='Vulcus:BAAALgADCgEJAwABLgAFFAUJGAAEAFQZAA==.Vulpii:BAAALgADCgYJBQABLgAECgkJNQAbAG0lAA==.',
Vy='Vyndarien:BAAALgADCgIJAgAAAA==.Vyse:BAAALgADCgEJAQAAAA==.Vyttra:BAAALgADCgMJAwAAAA==.',
Wa='Walak:BAAALgADCgMJAwAAAA==.Warpulse:BAAALgADCgkJDQAAAA==.Warwizard:BAAALgADCgMJAwAAAA==.Watcherseye:BAAALgADCggJDwABLgADCgkJCQACAAAAAA==.',
Wc='Wcreator:BAAALgAECgQJDQAAAA==.',
We='Weapònized:BAAALgAECgYJDQAAAA==.Webaldes:BAAALgAECgEJAQAAAA==.',
Wh='Whitestain:BAABLgAECn8XAAIRAAcJ1ghwEADnAAARAAcJ1ghwEADnAAAAAA==.',
Wi='Windyskie:BAAALgADCgEJAQAAAA==.Wingman:BAACLgAFFH8NAAIXAAQJvCYiAADSAQAXAAQJvCYiAADSAQAuAAQKfycAAhcACAmTJpgAAIsDABcACAmTJpgAAIsDAAAA.',
Wo='Womdalie:BAAALgADCgQJBgAAAA==.',
Xa='Xanthös:BAAALgAFFAEJAQABLgAFFAUJGAAEAFQZAA==.',
Xe='Xemnastrasza:BAACLgAFFH8HAAQPAAMJpg7UIQDjAAAPAAMJpg7UIQDjAAAGAAIJaQN4GQBxAAAXAAEJ0QNfCwBLAAAuAAQKfxYABA8ACAkdFL0hALEBAA8ACAnSEb0hALEBABcABAmmCOctAKsAAAYAAQlrBYFLACsAAAAA.Xenonne:BAACLgAFFH8KAAIFAAQJQBLoHwAtAQAFAAQJQBLoHwAtAQAuAAQKfx8AAwUACAlRG0cjALUBAAUACAlRG0cjALUBABYABQl3D25GANsAAAAA.',
Xo='Xolither:BAABLgAECn8cAAMLAAcJehF8GgBdAQALAAYJjxF8GgBdAQAMAAQJ1ROxTgD9AAAAAA==.',
Xp='Xpireedk:BAACLgAFFH8NAAMjAAQJ3iVWAACyAQAjAAQJ1CVWAACyAQAKAAQJIR6JGgBuAQAuAAQKfxwAAyMACQnGJUMDAF8CACMACQnGJUMDAF8CAAoABQnnHqd1AJoBAAAA.',
Yo='Yorakk:BAAALgADCgIJAgAAAA==.Yorgo:BAAALgAECgQJBgAAAA==.',
Za='Zariala:BAAALgAECgUJBgAAAA==.Zatana:BAAALgAECgUJBQAAAA==.',
Ze='Zephymoo:BAABLgAECn8uAAMkAAkJdRwJAgChAgAkAAkJdRwJAgChAgAOAAEJfAPTggAtAAAAAA==.Zeromus:BAAALgAECgkJCQAAAA==.Zerri:BAAALgADCgIJAgAAAA==.Zeyana:BAABLgAECn8ZAAQhAAkJ1BrcCADnAQAhAAkJ1BrcCADnAQAWAAQJlQVKUQClAAAFAAIJPQC59wAPAAABLgAFFAMJBgATAA4XAA==.',
Zh='Zhengshi:BAABLgAECn8fAAIJAAgJjBCIFQCOAQAJAAgJjBCIFQCOAQAAAA==.',
Zo='Zoder:BAAALgAECgUJDgAAAA==.Zoose:BAABLgAECn8iAAMZAAgJeR+qBwBxAgAZAAgJ2h6qBwBxAgAlAAIJURgDJQCfAAAAAA==.Zoser:BAABLgAECn8dAAIYAAgJ9yXRAQAKAwAYAAgJ9yXRAQAKAwAAAA==.',
['Æl']='Ælthan:BAAALgADCgUJBgAAAA==.',
['Ér']='Érubus:BAAALgAECgEJAgAAAA==.',
['ßu']='ßugs:BAABLgAECn8cAAITAAgJohKBJgC6AQATAAgJohKBJgC6AQAAAA==.',
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
