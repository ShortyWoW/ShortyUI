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

local lookup = {'Shaman-Elemental','Warrior-Fury','Warlock-Destruction','Priest-Discipline','Priest-Holy','Monk-Brewmaster','Monk-Windwalker','DemonHunter-Devourer','Evoker-Preservation','Hunter-BeastMastery','Paladin-Retribution','Priest-Shadow','Evoker-Augmentation','Druid-Balance','Mage-Frost','Mage-Arcane','Evoker-Devastation','DeathKnight-Unholy','DeathKnight-Blood','Warlock-Demonology','Unknown-Unknown','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','DemonHunter-Havoc','Warrior-Arms','Shaman-Restoration','DemonHunter-Vengeance','Hunter-Marksmanship','Druid-Restoration','Shaman-Enhancement','Warrior-Protection','Hunter-Survival','Paladin-Holy','Druid-Guardian','Monk-Mistweaver','Paladin-Protection','Druid-Feral','Mage-Fire','Warlock-Affliction',}
local provider = {region='US',realm='Magtheridon',name='US',type='weekly',zone=46,date='2026-05-08',data={Ad='Adayssa:BAAALgAECgEJAQAAAA==.',
Ag='Agave:BAAALgAECgYJEAAAAA==.',
Ai='Aimwee:BAAALgAECgYJEQAAAA==.Aiur:BAAALgADCgkJKgAAAA==.',
Ak='Akunzed:BAAALgADCgEJAQAAAA==.',
Al='Alaena:BAAALgADCgYJBgAAAA==.Alandivyn:BAAALgAECgMJBAAAAA==.Alarm:BAAALgADCgYJBgABLgAECggJGAABADIgAA==.Alcuard:BAAALgAECgYJCAAAAA==.Aldenfire:BAAALgAECgEJAgAAAA==.Alesce:BAACLgAFFH8WAAICAAUJ/grZCABiAQACAAUJ/grZCABiAQAuAAQKfyYAAgIACQk6GuUSALcCAAIACQk6GuUSALcCAAAA.Alii:BAAALgAECgQJBQAAAA==.Alisinchains:BAAALgADCgcJCQAAAA==.',
Am='Amarauku:BAABLgAECn8gAAIDAAgJihAiCABbAQADAAgJihAiCABbAQAAAA==.Amenadiel:BAABLgAECn8cAAMEAAgJQR/vDQBbAgAEAAgJQR/vDQBbAgAFAAEJ4gpRfwAzAAAAAA==.America:BAAALgADCgYJCQAAAA==.Amyntas:BAAALgAECgMJBQAAAA==.Amythistle:BAABLgAECn8cAAIGAAcJ7x02DAD/AQAGAAcJ7x02DAD/AQAAAA==.',
An='Andrü:BAABLgAECn8mAAICAAkJ8RtKBQCjAgACAAkJ8RtKBQCjAgAAAA==.Andy:BAABLgAECn8WAAIHAAgJ3CBrBACjAgAHAAgJ3CBrBACjAgAAAA==.Angeredx:BAAALgAECgEJAQAAAA==.Anguscon:BAAALgADCgMJAwAAAA==.Anol:BAAALgAECgUJBQABLgAFFAYJEgAIANwkAA==.Antihero:BAAALgAFFAMJAwAAAA==.Antioch:BAAALgADCgkJKwAAAA==.',
Ar='Archael:BAAALgAECgYJDgAAAA==.Archimainos:BAABLgAECn8aAAIJAAcJTRZcFQD1AQAJAAcJTRZcFQD1AQAAAA==.Argorok:BAAALgAECgYJEQAAAA==.Argôroth:BAAALgADCgYJBgAAAA==.Arthz:BAAALgADCgcJBwAAAA==.',
As='Asheeus:BAABLgAECn8WAAIKAAkJdxW0OABqAQAKAAkJdxW0OABqAQAAAA==.Ashtana:BAAALgADCgMJAwAAAA==.Ashtar:BAABLgAECn8uAAILAAgJgRoSHgATAgALAAgJgRoSHgATAgAAAA==.Assiasins:BAAALgAECgEJAQAAAA==.Asterok:BAAALgAECgYJDAAAAA==.Astravianda:BAAALgAECgUJBQAAAA==.Aszune:BAAALgADCgUJBQAAAA==.',
At='Atheria:BAECLgAFFH8GAAIMAAMJHxJXCwAAAQAMAAMJHxJXCwAAAQAuAAQKfxkAAgwACAk0HPYRAGsCAAwACAk0HPYRAGsCAAAA.Athetaz:BAAALgAECgEJAQAAAA==.Atrumvesica:BAAALgADCgEJAQAAAA==.',
Au='Auggers:BAABLgAFFH8FAAMJAAIJ3RYnEQCwAAAJAAIJ3RYnEQCwAAANAAEJxAgFOABNAAAAAA==.Augthyr:BAAALgAECgQJCAABLgAFFAMJBQALACoaAA==.',
Av='Avalen:BAABLgAECn8eAAIOAAcJHyN3DQDCAgAOAAcJHyN3DQDCAgAAAA==.Avarich:BAAALgAECgQJBAAAAA==.Avez:BAAALgADCgkJMAAAAA==.Aviee:BAACLgAFFH8MAAIPAAQJZB1cGAB+AQAPAAQJZB1cGAB+AQAuAAQKfxwAAg8ABwlaH65FAGcCAA8ABwlaH65FAGcCAAAA.Avishun:BAAALgAECgYJCgAAAA==.Avreel:BAABLgAECn8fAAMQAAcJfhbvAgCfAQAQAAcJfhbvAgCfAQAPAAEJqA8zYwE9AAAAAA==.',
Az='Azazi:BAACLgAFFH8ZAAIPAAYJ2CCYBgABAgAPAAYJ2CCYBgABAgAuAAQKfzMAAg8ACQkpJkgDAMsDAA8ACQkpJkgDAMsDAAAA.Azonia:BAAALgADCgYJDAABLgAECggJGQARAEkbAA==.Azushi:BAAALgAECgYJDAABLgAECgkJKgACADcfAA==.',
Ba='Babymage:BAACLgAFFH8NAAIPAAQJfwlPOwAiAQAPAAQJfwlPOwAiAQAuAAQKfzAAAg8ACQkzG58QAJUCAA8ACQkzG58QAJUCAAAA.Badform:BAAALgAECgMJBAAAAA==.Badkitteh:BAAALgAECgQJBQAAAA==.Baelstrom:BAAALgAFFAMJAwAAAA==.Baendron:BAABLgAECn8hAAMSAAkJwRjoPgA8AgASAAkJOxfoPgA8AgATAAUJgxLIFAAvAQAAAA==.Bahnna:BAABLgAECn8hAAMEAAcJ3BfoDQDyAQAEAAcJ3BfoDQDyAQAFAAIJSwvqcQBfAAAAAA==.Bananana:BAAALgADCgcJBwAAAA==.Barbarik:BAAALgAECgUJBQABLgAFFAMJCgAUAGYVAA==.Barberry:BAAALgAECgEJAgABLgAECgEJAQAVAAAAAA==.Baretwallace:BAAALgAFFAIJBAABLgAFFAMJBQALACoaAA==.',
Be='Beardsmite:BAEALgAECgcJEgABLgAECgIJAgAVAAAAAA==.Beerbeeotch:BAAALgADCgcJDQAAAA==.Beerus:BAABLgAECn8PAAIIAAYJCBYnXgCGAQAIAAYJCBYnXgCGAQAAAA==.Bellawaifu:BAAALgAECgYJBgAAAA==.Bellaynia:BAAALgADCgcJDQAAAA==.Belle:BAAALgAECgEJAQABLgAFFAIJAgAVAAAAAA==.Belmuerto:BAAALgAECgYJDAAAAA==.Benzopatrol:BAAALgAECgQJCAAAAA==.Besnel:BAAALgAECgQJBwAAAA==.',
Bi='Bigtuna:BAAALgADCgIJAgAAAA==.',
Bl='Blackbolt:BAAALgADCgMJAwAAAA==.Blackhaus:BAAALgADCgcJBwAAAA==.Blixxy:BAAALgADCgQJBAAAAA==.Blorgin:BAACLgAFFH8UAAMWAAYJPxnjBwBpAQAWAAUJVRjjBwBpAQAXAAIJkxZCBQC7AAAuAAQKfyUABBYACQlWI5MCAIADABYACQn7IpMCAIADABcAAglwI94OAMYAABgAAQlgAA4QABcAAAAA.Bluntmàn:BAAALgAECgMJBQAAAA==.Bléssed:BAAALgAECgEJAwAAAA==.',
Bo='Boinky:BAABLgAECn8XAAIKAAYJSQ6UUAAcAQAKAAYJSQ6UUAAcAQAAAA==.Boneham:BAAALgAECgQJBAAAAA==.Bookers:BAABLgAECn8kAAIZAAkJSBEkHADfAQAZAAkJSBEkHADfAQAAAA==.Booplzs:BAABLgAECn8pAAIPAAkJ1BobEgCIAgAPAAkJ1BobEgCIAgAAAA==.Borgo:BAAALgADCgkJDwABLgAFFAIJBQAPAIcdAA==.Boulangerie:BAACLgAFFH8XAAIMAAYJ3h/KAgDJAQAMAAYJ3h/KAgDJAQAuAAQKfygAAgwACQnAJhsAAAsEAAwACQnAJhsAAAsEAAAA.Boulezen:BAAALgAECgEJAgAAAA==.Boulidan:BAAALgAECgYJEQAAAA==.Boulight:BAAALgAECgIJAgAAAA==.Boulior:BAAALgADCgcJEgAAAA==.Bounceonit:BAABLgAECn8YAAIIAAgJCxqKFwAAAgAIAAgJCxqKFwAAAgAAAA==.Boyd:BAACLgAFFH8VAAMCAAYJpBgDCQBgAQACAAUJXR4DCQBgAQAaAAEJwQGkGwBCAAAuAAQKfyYAAwIACQkKIeUbAG4CAAIACQkKIeUbAG4CABoAAQklCT5EADAAAAAA.',
Br='Breeding:BAAALgAECgcJDQABLgAFFAIJBwAGACUdAA==.Brent:BAAALgADCgUJBQAAAA==.Brewm:BAAALgAECgMJAwAAAA==.Brewmungandr:BAABLgAECn8XAAIGAAgJPhaODwDQAQAGAAgJPhaODwDQAQAAAA==.Brightnight:BAAALgADCgEJAQABLgAECgYJEAAVAAAAAA==.Brinner:BAAALgADCgYJBgAAAA==.Brokenbone:BAAALgAECgYJDAAAAA==.Bromayzo:BAAALgAECgYJCQAAAA==.Brujo:BAAALgAECgMJAwAAAA==.Brylen:BAAALgAECgYJBwAAAA==.',
Bu='Budweis:BAAALgADCgIJAgAAAA==.Bullkkake:BAAALgAECgIJAwAAAA==.Bumii:BAAALgAFFAIJAgAAAA==.',
By='Byfryasbeard:BAAALgADCgcJEwAAAA==.',
Ca='Canadatrash:BAAALgADCgcJBwABLgAFFAMJBQALACoaAA==.Carltonbanks:BAAALgAECgcJBwAAAA==.Cashewz:BAAALgAECgkJEQAAAA==.Casterella:BAAALgADCgEJAQAAAA==.Caylithia:BAABLgAECn8gAAISAAcJ1hXQMgCuAQASAAcJ1hXQMgCuAQAAAA==.',
Ce='Ceasarsalad:BAABLgAECn8sAAMDAAkJtBQJBQCxAQADAAgJYxUJBQCxAQAUAAgJbAyqXAAZAQAAAA==.Ceazitt:BAAALgADCgcJBwABLgAECggJGAAPAB8XAA==.Ceazyweasley:BAABLgAECn8YAAIPAAgJHxdJNADQAQAPAAgJHxdJNADQAQAAAA==.Ceci:BAAALgAFFAMJAwAAAA==.Celestriå:BAABLgAECn8fAAMDAAcJhBNZBwBvAQADAAcJhBNZBwBvAQAUAAMJkgft+wBiAAAAAA==.Cernnuunnos:BAAALgADCgUJBQAAAA==.Cetana:BAAALgADCgUJBQABLgAFFAMJBQALACoaAA==.',
Ch='Chadlockb:BAACLgAFFH8aAAMUAAcJAx6yBADcAQAUAAYJLSKyBADcAQADAAEJLQkgDgBeAAAuAAQKfy4AAxQACQk5JFAFAPECABQACQk5JFAFAPECAAMAAwkwFAE5ANAAAAAA.Cheesee:BAABLgAECn8qAAIbAAkJICDpBgDCAgAbAAkJICDpBgDCAgAAAA==.Christlike:BAAALgAECgEJAgAAAA==.Chronite:BAACLgAFFH8FAAIPAAIJhx1RVgDAAAAPAAIJhx1RVgDAAAAuAAQKfyYAAg8ACQl8FtMaAEkCAA8ACQl8FtMaAEkCAAAA.Chuffy:BAAALgAECgYJDAAAAA==.',
Ci='Cindr:BAACLgAFFH8SAAINAAYJpiP3AwAIAgANAAYJpiP3AwAIAgAuAAQKfyYAAw0ACQlHJqIAAN0DAA0ACQlHJqIAAN0DABEABwnvG9kNAPwBAAAA.Circumstance:BAACLgAFFH8NAAMFAAQJfQzgDAACAQAFAAQJRQrgDAACAQAEAAIJogxpHwCWAAAuAAQKfzoABAUACQluHXIFAPgCAAUACQmTG3IFAPgCAAQACQmCGk4FAK4CAAwAAgmbDU9VAG0AAAAA.Cirice:BAAALgADCgIJAwAAAA==.',
Cl='Claylock:BAABLgAECn8lAAIUAAkJGB3KCAC6AgAUAAkJGB3KCAC6AgAAAA==.Cleattus:BAABLgAECn8dAAMUAAgJAg2JOACEAQAUAAgJAg2JOACEAQADAAEJcQWfeQApAAAAAA==.Cleric:BAAALgAECgQJBAAAAA==.',
Co='Coarseblood:BAAALgAECgEJAQAAAA==.Cody:BAACLgAFFH8OAAIMAAUJwSOUBACYAQAMAAUJwSOUBACYAQAuAAQKfyUAAgwACQnPJYgBALEDAAwACQnPJYgBALEDAAAA.Codyh:BAAALgAECgYJBgAAAA==.Codyp:BAAALgAECgYJBgAAAA==.Colddblooded:BAAALgAECgUJDwAAAA==.Coldoyazda:BAAALgAECgEJAQAAAA==.Cololol:BAACLgAFFH8SAAIIAAYJ3CRDBAD8AQAIAAYJ3CRDBAD8AQAuAAQKf0EABAgACQnWJdYAANwDAAgACQnWJdYAANwDABwABwkNH4cDABMCABkAAwmzHXlJAMwAAAAA.Conjurous:BAAALgADCgYJCQABLgAECgQJBQAVAAAAAA==.Cooper:BAABLgAECn8mAAIdAAkJgiOVAAAhAwAdAAkJgiOVAAAhAwAAAA==.Corbis:BAAALgADCgYJBgABLgAECgcJFgAeANIeAA==.Corruptica:BAAALgADCggJFwAAAA==.Cosmos:BAABLgAECn8mAAIeAAkJrhzIBgDjAgAeAAkJrhzIBgDjAgAAAA==.Cowlvlislie:BAAALgAECgUJBQAAAA==.',
Cr='Creami:BAAALgADCgEJBAAAAA==.Creastos:BAAALgAECgEJBAAAAA==.Crew:BAACLgAFFH8XAAIZAAYJpRyXAADUAQAZAAYJpRyXAADUAQAuAAQKfzMAAxkACQm7Jd0AADMDABkACQm7Jd0AADMDAAgAAQkAAGLbAAAAAAAA.Crispy:BAAALgAECgEJAgAAAA==.Cronozret:BAAALgADCgEJAQAAAA==.',
Cu='Cucokai:BAABLgAECn8lAAMbAAgJrx6PDQBdAgAbAAgJrx6PDQBdAgAfAAEJ5wDyIgAOAAAAAA==.Cuddlekaren:BAABLgAECn8ZAAMMAAcJwBd2EgC0AQAMAAcJwBd2EgC0AQAFAAIJPhFPbgBuAAABLgAFFAYJFgAdAN8aAA==.Cuddlestomp:BAACLgAFFH8WAAIdAAYJ3xpXAwCtAQAdAAYJ3xpXAwCtAQAuAAQKfyYAAh0ACQkVJOgDAGYDAB0ACQkVJOgDAGYDAAAA.',
['Cä']='Cämulos:BAABLgAECn8gAAIgAAgJrRIlDgCAAQAgAAgJrRIlDgCAAQAAAA==.',
['Cí']='Círí:BAECLgAFFH8FAAIKAAMJjiStEwBNAQAKAAMJjiStEwBNAQAuAAQKfxYABB0ABwlNJeweAC8CAB0ABwlDHuweAC8CAAoABQnhJbw6AMMBACEAAQkmI4IsAEIAAAEuAAQKAgkCABUAAAAA.',
Da='Dabudtanka:BAAALgAECgEJAQAAAA==.Dacat:BAAALgAECgQJBAAAAA==.Daddylongleg:BAAALgADCgEJAQAAAA==.Daenleran:BAAALgADCggJDgAAAA==.Damnhammer:BAABLgAFFH8MAAIiAAQJDhTSDgBCAQAiAAQJDhTSDgBCAQAAAA==.Dandie:BAAALgAECgcJCAAAAA==.Dantalian:BAABLgAECn8gAAMEAAgJjRbdCgAmAgAEAAgJAhbdCgAmAgAFAAQJ/wuqNQCnAAABLgAFFAYJFAAPAAYaAA==.Darthahsoka:BAAALgADCgYJBgAAAA==.Darthimu:BAAALgAECgEJAQABLgAECggJJQAPANcWAA==.Darthmerlin:BAABLgAECn8lAAIPAAgJ1xYRNQDNAQAPAAgJ1xYRNQDNAQAAAA==.Darthpanda:BAAALgADCgMJAgABLgAECggJJQAPANcWAA==.Darthsanguis:BAAALgAECgEJAQABLgAECggJJQAPANcWAA==.Darthvaper:BAAALgADCgEJAQAAAA==.Dasakko:BAACLgAFFH8NAAIFAAQJOBwOBwBSAQAFAAQJOBwOBwBSAQAuAAQKfy8AAwUACQmjITYBAF4DAAUACQmjITYBAF4DAAwAAQlTB1hTADMAAAAA.Dasmonko:BAAALgAECgEJAgABLgAFFAQJDQAFADgcAA==.',
Db='Dbowz:BAAALgAECgUJBQAAAA==.',
De='Deathbeeotch:BAABLgAECn8iAAISAAgJigvJPwB+AQASAAgJigvJPwB+AQAAAA==.Deathcaller:BAAALgAECgcJEAAAAA==.Deblacksheep:BAAALgADCgMJAwABLgAECgcJHgAiAF8kAA==.Deliscera:BAAALgADCgYJBgAAAA==.Delithsong:BAAALgADCggJCAAAAA==.Demonhunterl:BAAALgAECgYJEwAAAA==.Demonishall:BAAALgAECgYJDQAAAA==.Demontim:BAABLgAECn8WAAIZAAgJ/xz9BQBLAgAZAAgJ/xz9BQBLAgAAAA==.Denjin:BAAALgADCgEJAgAAAA==.Destile:BAAALgAECgQJBAABLgAECgcJFAAIAEMaAA==.Dethe:BAAALgAECgUJEAAAAA==.Dewme:BAAALgADCgYJBgAAAA==.',
Dh='Dhbowz:BAACLgAFFH8QAAIIAAUJzh7eEQBrAQAIAAUJzh7eEQBrAQAuAAQKfyAAAwgACAkKJJkUANwCAAgACAnfIpkUANwCABwAAgkJI8YZAMgAAAAA.',
Di='Dinkyfu:BAAALgADCggJAgAAAA==.Dipndots:BAAALgADCgYJBgAAAA==.',
Dn='Dnok:BAAALgADCgEJAQAAAA==.',
Do='Doc:BAAALgAECgYJBgAAAA==.Doguntarth:BAABLgAECn8qAAICAAkJNx8QAwDjAgACAAkJNx8QAwDjAgAAAA==.Domerneth:BAAALgAECgUJDwAAAA==.Doomfury:BAABLgAECn8UAAMBAAcJlRXuGwBuAQABAAcJlRXuGwBuAQAfAAMJDghDJACVAAAAAA==.Dotsfired:BAAALgAECgYJBwABLgAECgYJGQAgAC8jAA==.Doylescars:BAAALgADCgIJAgAAAA==.',
Dr='Dragonboi:BAAALgAECgYJBgAAAA==.Dragonbutt:BAAALgAECgMJAwAAAA==.Dragson:BAAALgADCgEJAQAAAA==.Drakkarus:BAAALgAECgUJDQAAAA==.Drankincup:BAACLgAFFH8SAAIBAAYJbRv1AwDAAQABAAYJbRv1AwDAAQAuAAQKfzQAAgEACQn/IocEALMCAAEACQn/IocEALMCAAAA.Drchinstraps:BAAALgAECgEJAQAAAA==.Dreamscape:BAAALgAECgUJBgAAAA==.Drstagger:BAECLgAFFH8IAAIGAAMJYCYeDABVAQAGAAMJYCYeDABVAQAuAAQKfyUAAgYACAkhJtsBAIcDAAYACAkhJtsBAIcDAAAA.',
Du='Duskflower:BAACLgAFFH8UAAIeAAYJTBMYBwDHAQAeAAYJTBMYBwDHAQAuAAQKfyoAAh4ACQnwG9UZAGoCAB4ACQnwG9UZAGoCAAAA.',
Eb='Ebonessences:BAAALgAECgEJAQAAAA==.',
Ec='Echochaser:BAAALgADCggJFQAAAA==.Eclaire:BAAALgADCgYJBgAAAA==.',
Ed='Eddard:BAAALgADCgYJCwAAAA==.',
Ej='Eject:BAAALgAECgQJBQAAAA==.',
El='Elexandur:BAABLgAECn8dAAIfAAgJFBynBQDzAQAfAAgJFBynBQDzAQAAAA==.Ellenarna:BAAALgAECgUJBwAAAA==.Elleri:BAABLgAECn8fAAILAAgJHhH1NwCfAQALAAgJHhH1NwCfAQAAAA==.Ellyse:BAAALgAECgEJAwAAAA==.',
En='Entrøpy:BAACLgAFFH8FAAILAAMJKhqNKQAHAQALAAMJKhqNKQAHAQAuAAQKfyAAAgsACAlRJCcVAFACAAsACAlRJCcVAFACAAAA.',
Ep='Epnodk:BAAALgAFFAEJAwABLgAFFAUJFwAGAHAbAA==.Epnokicks:BAACLgAFFH8XAAIGAAUJcBtlAwDBAQAGAAUJcBtlAwDBAQAuAAQKfy0AAgYACQnqI0cDAGADAAYACQnqI0cDAGADAAAA.Epnopal:BAAALgADCgMJAwABLgAFFAUJFwAGAHAbAA==.',
Er='Eroicel:BAAALgAECgMJAwABLgAFFAYJGgATAKMQAA==.',
Ev='Evarielle:BAACLgAFFH8aAAITAAYJoxBdCABGAQATAAYJoxBdCABGAQAuAAQKfzkAAhMACQmUHogFAOcCABMACQmUHogFAOcCAAAA.Evelis:BAAALgAECgYJEwAAAA==.Evilina:BAAALgADCgIJAwAAAA==.Evillmaster:BAAALgAECgEJAQAAAA==.',
Fa='Fadedhalo:BAAALgAECgQJCgAAAA==.Falaya:BAACLgAFFH8ZAAMDAAYJTiEgAQCKAQADAAUJgSEgAQCKAQAUAAMJBx9CLAC+AAAuAAQKfy0AAwMACQnXJDoBACADAAMACAkiIjoBACADABQABgkFIeFFAPkBAAAA.Fallinorion:BAAALgADCgYJBgAAAA==.Fancy:BAAALgAECgYJCgAAAA==.Farion:BAAALgAECgYJEQAAAA==.',
Fe='Fearlite:BAAALgAECgEJAQAAAA==.Feldoyle:BAAALgAECgQJCQAAAA==.Felel:BAAALgADCgEJAQAAAA==.Felfi:BAAALgAECgIJAgAAAA==.Felroc:BAAALgAECgEJAQAAAA==.Fenix:BAABLgAECn8UAAIgAAcJ+BtOCgDLAQAgAAcJ+BtOCgDLAQAAAA==.Fersos:BAABLgAECn8bAAILAAgJZgqtjwBcAQALAAgJZgqtjwBcAQAAAA==.',
Fi='Firefaux:BAAALgAECgQJBAAAAA==.',
Fl='Flawlessxi:BAAALgAECgYJDAABLgAECgkJJQAUAHUhAA==.Flyntflosy:BAACLgAFFH8YAAIBAAUJ4hpZCwBOAQABAAUJ4hpZCwBOAQAuAAQKfy4AAgEACQnnIaAFADsDAAEACQnnIaAFADsDAAAA.',
Fo='Fowl:BAAALgAECgUJBQABLgAECgkJHgAaANcKAA==.Fowlher:BAAALgAECgUJCAAAAA==.Foxreich:BAABLgAECn8gAAIKAAcJmhdoMQCIAQAKAAcJmhdoMQCIAQAAAA==.',
Fr='Fragment:BAABLgAECn8VAAMTAAcJChNwEwA+AQATAAcJChNwEwA+AQASAAMJIwrImACvAAAAAA==.Frozoevoko:BAAALgAECgQJBgABLgAFFAYJGgAPANcgAA==.',
Fu='Fulgan:BAAALgAECgEJAQAAAA==.Fungame:BAAALgAECgQJBAAAAA==.Funstar:BAAALgAECgYJCwABLgAECgkJFgAbANELAA==.Furyess:BAAALgAECgEJAgAAAA==.',
['Fé']='Félicity:BAEALgAECgIJAgAAAA==.',
['Fî']='Fîrebolt:BAAALgADCgMJAwAAAA==.',
Ga='Gabeuttsecks:BAAALgAECgEJAQAAAA==.Gaelsi:BAABLgAECn8eAAMHAAgJbx9kBwBSAgAHAAgJbx9kBwBSAgAGAAEJPBWMiwAuAAAAAA==.Galactic:BAAALgADCgkJCQABLgAFFAMJCgAjALAlAA==.Galgore:BAABLgAECn8UAAIiAAgJkAsSOQCWAQAiAAgJkAsSOQCWAQAAAA==.Ganvvitch:BAAALgAECgEJAQAAAA==.Garolok:BAABLgAECn8mAAIaAAkJSRy6BQB6AgAaAAkJSRy6BQB6AgAAAA==.Gartiss:BAAALgAECgQJCwAAAA==.Gate:BAAALgADCgkJJQAAAA==.Gazelle:BAEBLgAECn8mAAIGAAkJ0BWwCwAGAgAGAAkJ0BWwCwAGAgAAAA==.Gazerakhan:BAAALgADCgcJDAABLgAFFAMJBQAIAOwOAA==.Gazerielle:BAACLgAFFH8FAAIIAAMJ7A5YNgDZAAAIAAMJ7A5YNgDZAAAuAAQKfykABAgACQm1FX4bAOQBAAgACQltFX4bAOQBABwABgm4FH8QAEkBABkAAQmwBzd4ACwAAAAA.Gazerizard:BAAALgADCgQJBAABLgAFFAMJBQAIAOwOAA==.',
Gh='Gherthquakes:BAAALgADCgIJAgAAAA==.',
Gi='Ginsoda:BAAALgADCgcJCwAAAA==.Ginthril:BAAALgAECgIJAwABLgAECgcJFQATAHQkAA==.Ginwine:BAABLgAFFH8IAAMiAAMJ4yVbDgBIAQAiAAMJ4yVbDgBIAQALAAEJ4h9FLABhAAABLgAFFAYJFwAUAFEkAA==.Gitzsum:BAAALgADCgUJBQAAAA==.',
Gl='Glizzylizzy:BAACLgAFFH8NAAIfAAQJVSIdAQCQAQAfAAQJVSIdAQCQAQAuAAQKfykAAh8ACQnLIpcAACADAB8ACQnLIpcAACADAAAA.',
Gn='Gnaeus:BAAALgAECgMJBwAAAA==.',
Go='Goldilockes:BAAALgAECgMJBAAAAA==.Gorca:BAAALgAECgEJAQABLgAECgEJAQAVAAAAAA==.Gothbaddie:BAAALgADCgEJAQAAAA==.Gourmando:BAAALgADCgYJDAABLgAECgEJAQAVAAAAAA==.Gowownage:BAACLgAFFH8KAAIjAAMJsCWPAgBOAQAjAAMJsCWPAgBOAQAuAAQKfykAAiMACAmgJCIBAOwCACMACAmgJCIBAOwCAAAA.',
Gr='Gradius:BAACLgAFFH8LAAMTAAUJxRnKCABAAQATAAUJxRnKCABAAQASAAEJnguWlQBMAAAuAAQKfyMAAxIACQmtHKspAJMCABIACQlVHKspAJMCABMABwmhFs8aAPAAAAAA.Granddh:BAAALgAECgcJBwAAAA==.Grandmage:BAABLgAECn8VAAIPAAgJFBF4ewDaAQAPAAgJFBF4ewDaAQAAAA==.Graydius:BAAALgAFFAEJAQAAAA==.Greenpanda:BAABLgAECn8bAAIGAAgJmhZ0FwB8AQAGAAgJmhZ0FwB8AQAAAA==.Greenwarrior:BAAALgAECgYJCQAAAA==.Greydeus:BAAALgAFFAIJAwABLgAFFAUJCwATAMUZAA==.Grimeclipse:BAABLgAECn8UAAMOAAcJFRMaKQD6AAAOAAYJgBAaKQD6AAAeAAUJdR5wSgDpAAAAAA==.Groves:BAABLgAECn8WAAMFAAcJlBpLDAAhAgAFAAcJhxpLDAAhAgAEAAEJYBdaQQBFAAABLgAECgkJMgAkAFwaAA==.Grumple:BAAALgAECgUJBQAAAA==.Grumpoo:BAAALgAECgUJCgAAAA==.',
Gu='Gurt:BAABLgAECn8eAAMCAAkJpA4cQwCYAQACAAkJ4g0cQwCYAQAaAAYJWgrxIQDdAAAAAA==.Gurtok:BAAALgAECgcJDQAAAA==.',
['Gø']='Gøøn:BAABLgAECn8bAAIPAAgJYhgkUABHAgAPAAgJYhgkUABHAgAAAA==.',
Ha='Halestorm:BAABLgAECn8YAAILAAYJMwhOegD3AAALAAYJMwhOegD3AAAAAA==.Halfachuby:BAAALgAECgEJAQAAAA==.Halfmast:BAAALgAECgEJAQABLgAFFAMJDAAIAE4hAA==.Halk:BAACLgAFFH8VAAILAAYJyh8yAwDgAQALAAYJyh8yAwDgAQAuAAQKfyYAAgsACQkmJO0GAGEDAAsACQkmJO0GAGEDAAAA.Haonao:BAAALgADCgYJCwAAAA==.Harris:BAAALgAFFAIJBAABLgAFFAYJFwAMAN4fAA==.Havefun:BAABLgAECn8WAAMbAAkJ0QsnPwCEAQAbAAkJ0QsnPwCEAQABAAQJewz0RwCHAAAAAA==.',
He='Hedonist:BAAALgAECggJEgABLgAFFAMJCgAUAGYVAA==.Hellquack:BAABLgAECn8eAAQaAAkJ1wo1GAA3AQAaAAkJ3wg1GAA3AQAgAAUJMgsQLQDZAAACAAMJOQVqjQCJAAAAAA==.Hellsbringer:BAABLgAECn8cAAIIAAcJcRcyLwB6AQAIAAcJcRcyLwB6AQAAAA==.Hellzard:BAAALgADCgYJBwAAAA==.Hemlocke:BAAALgAECgIJAgAAAA==.Hermito:BAAALgAECgYJBgABLgAECggJKAAYAHgeAA==.',
Ho='Hollowed:BAAALgAECgQJBAAAAA==.Holloweds:BAAALgAECgIJAgAAAA==.Holycandi:BAAALgAECgIJBAAAAA==.Holydoyle:BAABLgAECn8XAAIlAAgJniEqAgCfAgAlAAgJniEqAgCfAgAAAA==.Holyho:BAAALgAECgEJAQAAAA==.Holytrident:BAABLgAECn8VAAIPAAYJkhF13gA2AQAPAAYJkhF13gA2AQAAAA==.Homelessman:BAAALgAECgYJBgAAAA==.Hotpøcket:BAACLgAFFH8RAAIeAAUJAQ4EEABUAQAeAAUJAQ4EEABUAQAuAAQKfygAAx4ACQmxIesFAPYCAB4ACQmxIesFAPYCAA4AAglEG+dHAGAAAAAA.Hottz:BAAALgAECgcJBQAAAA==.',
Hu='Hugebowels:BAAALgAFFAEJAQAAAA==.Hugefeet:BAABLgAECn8bAAMXAAgJZBQBBgAfAgAXAAcJLhcBBgAfAgAYAAUJRAXyCQDYAAABLgAFFAEJAQAVAAAAAA==.Humorous:BAAALgAECggJEgAAAA==.',
Hy='Hyperìen:BAACLgAFFH8bAAIlAAYJ7CJAAADrAQAlAAYJ7CJAAADrAQAuAAQKfyMAAiUACQnaJEYAALIDACUACQnaJEYAALIDAAAA.',
Ic='Icanmoonu:BAAALgAECgQJCgAAAA==.Icedoggi:BAABLgAECn8jAAMjAAgJmxzmBgDTAQAjAAcJ7RvmBgDTAQAmAAMJHxJ1FgDDAAAAAA==.',
Il='Illzilla:BAAALgADCgcJFAAAAA==.',
Im='Immortalmage:BAAALgAFFAMJAwAAAA==.Imnosuperman:BAAALgAECgEJAQAAAA==.Imsopro:BAAALgADCgIJAgAAAA==.',
In='Inferna:BAAALgADCgcJBgAAAA==.Inferno:BAAALgADCggJDgAAAA==.Intiq:BAAALgADCgkJDwAAAA==.Invisibul:BAAALgAECgQJBQAAAA==.',
Ip='Ipmanz:BAAALgAECgIJBQAAAA==.',
Ir='Irbaboon:BAAALgAECgQJBQABLgAECgYJCAAVAAAAAA==.Irreletaur:BAACLgAFFH8QAAICAAUJ3hb5EQD2AAACAAUJ3hb5EQD2AAAuAAQKfykAAgIACQlAIZcYAIcCAAIACQlAIZcYAIcCAAAA.',
Is='Isitovernow:BAAALgADCgkJDQABLgAECgcJHgAiAF8kAA==.Ismitethee:BAAALgADCgcJDQAAAA==.',
It='Ithilwen:BAAALgADCgEJAQAAAA==.Itsovernow:BAABLgAECn8eAAIiAAcJXyS2CwBXAgAiAAcJXyS2CwBXAgAAAA==.Itzqt:BAAALgADCgcJEQAAAA==.',
Iz='Izimir:BAABLgAECn8XAAIiAAkJ3BhXJwDwAQAiAAkJ3BhXJwDwAQAAAA==.',
Ja='Jackiechin:BAAALgAECgEJAQABLgAFFAMJDAAIAE4hAA==.Jackiechàn:BAAALgAECgUJBgABLgAFFAMJBQALACoaAA==.Jacosta:BAABLgAECn8wAAIPAAkJKBqcEwB8AgAPAAkJKBqcEwB8AgAAAA==.Jadeazul:BAAALgADCgcJCAAAAA==.Jadis:BAABLgAECn8SAAIIAAgJ0gkSQwAvAQAIAAgJ0gkSQwAvAQAAAA==.Jamgirl:BAABLgAECn8VAAITAAcJdCTMBgDHAgATAAcJdCTMBgDHAgAAAA==.Jampu:BAAALgADCgEJAQAAAA==.Jangokin:BAACLgAFFH8WAAIOAAUJIBTuBwBiAQAOAAUJIBTuBwBiAQAuAAQKfyYAAg4ACQl0IccEAFUDAA4ACQl0IccEAFUDAAAA.Jaskvoid:BAABLgAECn8TAAIIAAcJXwSFcwCyAAAIAAcJXwSFcwCyAAAAAA==.Jasminepesto:BAAALgADCgkJDgAAAA==.Jatloo:BAAALgADCgQJBAABLgAECgQJCwAVAAAAAA==.Jaysis:BAABLgAECn8UAAIIAAcJQxqMKQCTAQAIAAcJQxqMKQCTAQAAAA==.',
Je='Jermz:BAAALgAECgQJCAAAAA==.',
Jg='Jgrass:BAABLgAECn8aAAIBAAcJxQoLKAAdAQABAAcJxQoLKAAdAQAAAA==.',
Ji='Jimba:BAACLgAFFH8NAAIKAAQJ+x3WDQBiAQAKAAQJ+x3WDQBiAQAuAAQKfy4AAgoACQmhH98HALMCAAoACQmhH98HALMCAAAA.Jinks:BAAALgAECgQJCgAAAA==.',
Jo='Joelrobuchon:BAAALgAECgIJAgAAAA==.Jorin:BAAALgADCgUJBQAAAA==.Jorres:BAAALgADCgMJAwAAAA==.Joslynn:BAAALgAECgIJAgAAAA==.Joytoy:BAAALgAECgQJBAAAAA==.',
Ju='Judgments:BAAALgAECgYJEQAAAA==.Jumalauta:BAABLgAECn8VAAIHAAYJ/R2KEQCsAQAHAAYJ/R2KEQCsAQAAAA==.Junglejooce:BAAALgADCgYJBgAAAA==.',
['Jè']='Jèrmz:BAAALgADCgEJAQAAAA==.',
['Jí']='Jím:BAAALgAECgcJEwABLgAECggJDwAVAAAAAA==.',
Ka='Kabang:BAAALgAECgQJBQABLgAECgkJHwAUAFsVAA==.Kabonk:BAAALgADCggJCAABLgAECgkJHwAUAFsVAA==.Kadia:BAAALgADCgIJAgAAAA==.Kaelstryna:BAAALgADCgQJBAAAAA==.Kaer:BAAALgAECgQJBAABLgAFFAUJEQAKAEoRAA==.Kaerbear:BAAALgADCgcJBwAAAA==.Kaige:BAAALgAFFAIJAgAAAA==.Kala:BAAALgAECgYJCgAAAA==.Kalithor:BAAALgAECggJDwAAAA==.Kalrodomes:BAAALgAECgYJBgAAAA==.Kasey:BAAALgAECgEJAQAAAA==.Kathery:BAAALgAECgQJDgAAAA==.Kathoes:BAAALgAECgUJDwAAAA==.Kazen:BAAALgAECgUJEAAAAA==.Kazhunter:BAAALgADCgYJBgAAAA==.',
Ke='Keeky:BAAALgADCgEJAQAAAA==.Keili:BAAALgAECgEJAQAAAA==.Kellandron:BAAALgAECgEJAQAAAA==.Kellwildfire:BAABLgAECn8lAAMCAAgJRw5wIABoAQACAAcJfxBwIABoAQAgAAgJWQMCGgDtAAAAAA==.Kethrin:BAAALgADCgYJBgAAAA==.',
Kh='Khamael:BAACLgAFFH8UAAIPAAYJBhruDAC/AQAPAAYJBhruDAC/AQAuAAQKfzMAAg8ACQl/JekCAFQDAA8ACQl/JekCAFQDAAAA.Kheiron:BAACLgAFFH8JAAMKAAMJ5xkwIwAJAQAKAAMJ5xkwIwAJAQAdAAIJWQu8HgCbAAAuAAQKfxkAAx0ACAkpH60cAEICAB0ACAnFHa0cAEICAAoAAwlDJQ9DAEQBAAAA.',
Ki='Kilimanjaro:BAAALgADCgkJDgABLgAECgQJCwAVAAAAAA==.Kinu:BAACLgAFFH8FAAIbAAMJLhXcIgDLAAAbAAMJLhXcIgDLAAAuAAQKfy0AAhsACQkJH5QDABIDABsACQkJH5QDABIDAAAA.Kitane:BAABLgAECn8fAAIHAAgJLxyfDQDeAQAHAAgJLxyfDQDeAQAAAA==.Kitsunibi:BAABLgAECn8jAAMOAAcJvRKVHABPAQAOAAcJvRKVHABPAQAeAAYJ9QYoewDnAAAAAA==.Kittyneko:BAAALgAECgYJDgAAAA==.',
Kl='Klump:BAAALgADCgEJAQAAAA==.',
Ko='Kobieta:BAABLgAFFH8FAAIeAAIJahCxMQCDAAAeAAIJahCxMQCDAAAAAA==.Kolei:BAAALgADCgQJBAAAAA==.Konica:BAABLgAECn8hAAMbAAgJmw9uKgBxAQAbAAgJmw9uKgBxAQABAAEJbQGUlwAYAAAAAA==.Kookykraving:BAAALgAECgYJCQAAAA==.Korgesh:BAAALgADCgkJFgAAAA==.Kotharsevant:BAAALgAECgEJAQAAAA==.',
Kr='Kraypoe:BAABLgAECn8aAAIIAAgJBAsfaABqAQAIAAgJBAsfaABqAQAAAA==.Kreepindeath:BAAALgAECgUJBQABLgAECggJHAABAJYcAA==.Krondys:BAAALgAECgQJBAAAAA==.Krìeg:BAAALgAECgIJAgABLgAECgQJCwAVAAAAAA==.',
Ku='Kunngfoo:BAAALgAECgEJAgAAAA==.Kurohail:BAAALgADCgYJBgABLgAECgkJLwAgAPYjAA==.Kurolion:BAAALgAECgYJDAAAAA==.Kurosong:BAABLgAECn8vAAIgAAkJ9iOZAABQAwAgAAkJ9iOZAABQAwAAAA==.Kurzon:BAAALgAECgEJAQAAAA==.',
Kw='Kwanrbless:BAABLgAECn8YAAILAAYJ4RHlWAA/AQALAAYJ4RHlWAA/AQAAAA==.',
Ky='Kyblade:BAABLgAECn8nAAIMAAkJ7CK3AQARAwAMAAkJ7CK3AQARAwAAAA==.Kyogre:BAAALgAECgUJBgAAAA==.Kyrr:BAABLgAECn8YAAIWAAgJGBuAFwBNAgAWAAgJGBuAFwBNAgAAAA==.',
['Kù']='Kùrupt:BAAALgAECgcJCgABLgAFFAUJEgAWAJ0kAA==.',
La='Labombah:BAAALgADCgMJBgAAAA==.Ladrogue:BAAALgAECgcJCgAAAA==.Landdragon:BAAALgAECgIJAgAAAA==.Landslide:BAAALgAECgEJAgAAAA==.Lasaruz:BAABLgAECn8hAAIGAAgJ0QXNJAAZAQAGAAgJ0QXNJAAZAQAAAA==.Lavajato:BAAALgADCgUJCAABLgAECggJJAASAFwbAA==.',
Le='Leemius:BAAALgAECgcJDAAAAA==.Legionearth:BAAALgAECgMJBAAAAA==.Leosbryn:BAABLgAECn8eAAIDAAkJ2xNHAwD3AQADAAkJ2xNHAwD3AQAAAA==.Levie:BAAALgAECgYJDAAAAA==.',
Lh='Lhaxorp:BAEBLgAECn8gAAMhAAgJHBZ5CwDsAQAhAAgJHBZ5CwDsAQAdAAMJzgd9bgCFAAABLgAECgkJMQALAPUjAA==.',
Li='Liable:BAAALgAECgcJDAABLgAECgcJFgAeANIeAA==.Lighthammer:BAAALgAECgYJDQABLgADCgMJAwAVAAAAAA==.Liiadrin:BAAALgADCgIJAgAAAA==.Liltazzvert:BAAALgAECgcJCQAAAA==.Linkdead:BAAALgAECgYJBgAAAA==.Listerfyne:BAAALgAECgYJCgAAAA==.Lithariel:BAAALgAECgUJBgAAAA==.',
Lo='Loumis:BAAALgAECgQJDQAAAA==.',
Lu='Lubefirst:BAAALgADCgYJBgAAAA==.Lucero:BAABLgAECn8lAAIiAAgJJhtWDQBAAgAiAAgJJhtWDQBAAgAAAA==.Lupii:BAAALgAECgkJEAAAAA==.Luxun:BAAALgAFFAIJAgAAAA==.',
Ma='Mabey:BAAALgAECgQJCAAAAA==.Mackinnon:BAAALgADCgQJBAAAAA==.Maerron:BAABLgAECn8fAAMFAAgJbAgwIABGAQAFAAgJbAgwIABGAQAMAAcJrgbsOgAbAQAAAA==.Mageblprows:BAAALgADCgkJHwAAAA==.Magness:BAAALgAECgMJAwAAAA==.Maiday:BAAALgAECgMJAwAAAA==.Mailescort:BAAALgAECgEJAQAAAA==.Makiavelik:BAAALgADCgcJBwAAAA==.Martireaper:BAAALgADCgUJBQAAAA==.Mastachißoyd:BAAALgAECgUJCAAAAA==.Matikz:BAACLgAFFH8UAAIWAAUJhB1UCQBfAQAWAAUJhB1UCQBfAQAuAAQKfyUAAxYACQliHjAJAP0CABYACQliHjAJAP0CABcABAkvDkAQAKwAAAAA.Mauradin:BAAALgADCgcJCgAAAA==.Mawdrin:BAAALgADCgcJCAAAAA==.Mayachampion:BAAALgAECgcJEQAAAA==.Maylla:BAAALgAECgIJAgAAAA==.',
Me='Meddle:BAACLgAFFH8eAAMFAAYJSiNRAABmAgAFAAYJSiNRAABmAgAEAAEJUQDgHAArAAAuAAQKfycAAgUACQmXJikAAN8DAAUACQmXJikAAN8DAAAA.Megarayquaza:BAAALgAECgYJBgAAAA==.Mehrunesd:BAAALgAECgQJDgAAAA==.Melictá:BAAALgAECgYJBgAAAA==.Melìcta:BAAALgADCgQJAwABLgAECgYJBgAVAAAAAA==.Melínoë:BAAALgAECgEJAgAAAA==.Mep:BAAALgAECggJCgAAAA==.Merenkor:BAAALgADCgQJBAAAAA==.Merrydeath:BAAALgADCgYJBgAAAA==.Merthulion:BAAALgAECgQJCQAAAA==.Meyea:BAACLgAFFH8MAAISAAUJjCISDgCeAQASAAUJjCISDgCeAQAuAAQKfygAAhIACQkXI+0HAGADABIACQkXI+0HAGADAAAA.',
Mh='Mhega:BAAALgAECgcJEQAAAA==.',
Mi='Miio:BAAALgADCgUJBAAAAA==.Mikuji:BAAALgAECgQJBwAAAA==.Miller:BAABLgAECn8jAAIKAAcJhyT5DQBqAgAKAAcJhyT5DQBqAgAAAA==.Mingsui:BAAALgADCgQJBwAAAA==.Mirra:BAACLgAFFH8NAAIIAAQJVR5KEAB0AQAIAAQJVR5KEAB0AQAuAAQKfy4AAggACQnjISkGAMcCAAgACQnjISkGAMcCAAAA.Miru:BAABLgAECn8XAAIDAAcJ6QbLDQD2AAADAAcJ6QbLDQD2AAAAAA==.Mizadra:BAABLgAECn8lAAMNAAkJnhHlEQC/AQANAAkJ8RDlEQC/AQARAAQJeREDKADgAAAAAA==.Mizdems:BAAALgAECgIJAwAAAA==.',
Ml='Mlindeli:BAAALgAECgEJAQABLgAECggJIwAOAJodAA==.',
Mo='Moistjustice:BAAALgAECgIJAgAAAA==.Monning:BAABLgAFFH8HAAMGAAIJJR0EGQCkAAAGAAIJJR0EGQCkAAAHAAEJvxMbHgBRAAAAAA==.Moonfun:BAAALgAECgUJCAABLgAECgkJFgAbANELAA==.Moonskin:BAAALgAECgQJBQAAAA==.Mothric:BAAALgAECgYJBQAAAA==.',
My='Mynados:BAAALgADCgQJBAAAAA==.Myronoriss:BAAALgAECggJDwAAAA==.Mysticfate:BAABLgAECn8bAAIPAAcJeyM3FQBwAgAPAAcJeyM3FQBwAgAAAA==.Mythicfritz:BAABLgAECn8WAAIIAAgJfQ8QVACnAQAIAAgJfQ8QVACnAQAAAA==.',
['Mé']='Mércy:BAABLgAECn8oAAMeAAcJpBxQHwDKAQAeAAcJpBxQHwDKAQAOAAMJngr1RQBnAAAAAA==.',
Na='Nahboo:BAABLgAECn8oAAIfAAkJcBOJBQD3AQAfAAkJcBOJBQD3AQAAAA==.Nakbu:BAABLgAECn8cAAITAAcJKw0RGQACAQATAAcJKw0RGQACAQAAAA==.Nandayo:BAAALgADCgIJAgAAAA==.Nani:BAABLgAECn8UAAMTAAgJcREjGACZAQATAAcJ7xMjGACZAQASAAcJOwpEjQBmAQAAAA==.',
Ne='Neandratroll:BAAALgAECgQJBAAAAA==.Neane:BAAALgAECgEJAQAAAA==.Necksus:BAAALgAECgYJEQAAAA==.Necridfashiz:BAAALgAECgcJEQAAAA==.Neinzen:BAAALgAECgcJDQAAAA==.Nemsy:BAABLgAECn8VAAIGAAgJXw+8FQCMAQAGAAgJXw+8FQCMAQAAAA==.Neralya:BAAALgADCgMJAwAAAA==.Neroth:BAAALgAFFAIJAgAAAA==.',
Ni='Niall:BAAALgAECgYJEAAAAA==.Nivai:BAAALgADCgkJHAAAAA==.Nivix:BAAALgADCgEJAQABLgAECggJDwAVAAAAAA==.',
No='Nogardz:BAABLgAECn8ZAAILAAkJqxhPGQAxAgALAAkJqxhPGQAxAgAAAA==.Nogi:BAAALgAECgMJAwAAAA==.Noi:BAAALgAECgYJDgAAAA==.Nojhelm:BAAALgAECgYJEgAAAA==.Norot:BAAALgADCgQJBAAAAA==.Notpetya:BAAALgAECgQJBwAAAA==.Nottills:BAAALgAECgQJBAAAAA==.Nox:BAAALgAECgMJBQAAAA==.',
Nu='Nuulruk:BAAALgAECgEJAQAAAA==.',
Ny='Nylaehh:BAAALgAECgEJAgAAAA==.Nyvix:BAAALgAECgUJCAABLgAECggJDwAVAAAAAA==.Nyxtro:BAAALgAECgEJAQAAAA==.',
['Nä']='Näla:BAAALgAECgIJAwAAAA==.',
Oa='Oathbreakër:BAAALgAECgMJBAAAAA==.',
Of='Offline:BAAALgAECgQJBAAAAA==.',
Ol='Oligoclase:BAAALgAECgEJAQAAAA==.',
Om='Ombrure:BAAALgAECgIJAgAAAA==.',
On='Onornu:BAACLgAFFH8XAAIbAAYJFiK5AABbAgAbAAYJFiK5AABbAgAuAAQKfzIAAxsACQmjJbABAHcDABsACQmjJbABAHcDAAEAAQnuFyhcAEQAAAAA.Onyxondra:BAAALgADCgEJAQAAAA==.',
Op='Ophiir:BAAALgAECgYJDwAAAA==.',
Or='Orlidan:BAABLgAECn8uAAIlAAkJiSHKAAD9AgAlAAkJiSHKAAD9AgAAAA==.Orlireloaded:BAAALgADCgcJDAABLgAECgkJLgAlAIkhAA==.',
Ox='Oxycut:BAABLgAECn8ZAAIgAAYJLyNCCwBbAgAgAAYJLyNCCwBbAgAAAA==.',
Pa='Panambi:BAAALgAECgEJAQAAAA==.Pandabearian:BAAALgADCgIJAgAAAA==.Paramorevil:BAAALgADCggJFgAAAA==.Parodia:BAABLgAECn8mAAMIAAkJYxcyEwAkAgAIAAkJYxcyEwAkAgAZAAEJ5wa2awA6AAAAAA==.',
Pe='Peka:BAABLgAFFH8GAAIbAAMJFg+DEADkAAAbAAMJFg+DEADkAAABLgAFFAYJHAAkAH8XAA==.Pekapeck:BAAALgAFFAMJAwAAAA==.Pekapow:BAACLgAFFH8cAAIkAAYJfxcWBACpAQAkAAYJfxcWBACpAQAuAAQKfx8AAyQACQkcIogCAGADACQACQkcIogCAGADAAcAAQloEqNWAD0AAAAA.',
Ph='Phearsome:BAAALgADCgcJBwAAAA==.Phobius:BAACLgAFFH8NAAISAAQJXA1KNQAzAQASAAQJXA1KNQAzAQAuAAQKfy8AAxIACQnoHHkLAK4CABIACQnoHHkLAK4CABMAAgkkCZBDADsAAAAA.',
Pi='Pigbumper:BAABLgAECn8sAAMcAAgJdSQ6AQAjAwAcAAgJRCQ6AQAjAwAIAAQJBiNnfAAzAQAAAA==.Pilihp:BAABLgAECn8aAAICAAgJgwSGNAD3AAACAAgJgwSGNAD3AAAAAA==.Pinkmango:BAAALgADCgkJCQABLgAFFAQJDQAFADgcAA==.Pippapjappin:BAAALgAECgYJEQAAAA==.Pireyne:BAAALgAECgcJCwAAAA==.Pistachioz:BAAALgADCgUJBQAAAA==.',
Pl='Plaguetaco:BAABLgAECn8hAAISAAcJ8QYncgD+AAASAAcJ8QYncgD+AAAAAA==.Plz:BAAALgAECgEJAgABLgAFFAQJDQAIAFUeAA==.',
Po='Polymorphine:BAAALgAECgEJAgABLgAECgYJBgAVAAAAAA==.Pontego:BAAALgADCgkJCQAAAA==.Pooinashoe:BAAALgAECgEJAQABLgAECgYJCAAVAAAAAA==.Pooky:BAABLgAECn8XAAIOAAgJmw5HNgBjAQAOAAgJmw5HNgBjAQAAAA==.Poonzer:BAEBLgAECn8xAAILAAkJ9SOyCgA6AwALAAkJ9SOyCgA6AwAAAA==.Popebenedikt:BAAALgAECgIJAgAAAA==.Popkwizz:BAAALgADCgMJAwAAAA==.Porosity:BAABLgAECn8iAAMBAAgJ6wuwLgD6AAABAAcJOQmwLgD6AAAbAAEJVgGqiQAkAAAAAA==.Pouches:BAAALgADCgMJAwAAAA==.',
Pr='Prescripts:BAAALgADCgMJAwAAAA==.Prisscus:BAAALgADCgcJEwAAAA==.Proudclod:BAABLgAECn8jAAIOAAgJmh3HBwBXAgAOAAgJmh3HBwBXAgAAAA==.Prunes:BAAALgAECgcJBwABLgAECgEJAQAVAAAAAA==.Pruning:BAAALgAECgQJBgABLgAECgEJAQAVAAAAAA==.Pruningz:BAAALgAECgEJAwABLgAECgEJAQAVAAAAAA==.',
Pu='Puffjiggly:BAABLgAECn8XAAMIAAcJvBHrQgAwAQAIAAcJvBHrQgAwAQAcAAEJVgauLQApAAAAAA==.Purrfecto:BAAALgADCgIJAgAAAA==.',
Py='Pynk:BAAALgAECgMJBQAAAA==.Pyridon:BAAALgADCgcJBwAAAA==.Pyriena:BAAALgAECgYJBwAAAA==.',
Qe='Qetesh:BAABLgAECn8jAAIDAAgJYh3uAQBJAgADAAgJYh3uAQBJAgAAAA==.',
Ra='Rabidfire:BAAALgAECgEJAQAAAA==.Rableman:BAABLgAECn8hAAIkAAkJ+Bq9BwB7AgAkAAkJ+Bq9BwB7AgAAAA==.Radiocity:BAAALgADCgEJAQAAAA==.Ragnár:BAAALgAECgMJBAAAAA==.Railzz:BAAALgADCgEJAQAAAA==.Rain:BAABLgAECn8lAAIkAAkJdg//EwC+AQAkAAkJdg//EwC+AQAAAA==.Raktavira:BAAALgAECgEJAwAAAA==.Ralinis:BAAALgAECgQJDQAAAA==.Rasson:BAAALgADCgcJBwAAAA==.Rathi:BAAALgAECgQJCQABLgAECgYJCAAVAAAAAA==.Ravarox:BAABLgAECn8qAAQOAAkJ+h3ZBQCGAgAOAAkJ+h3ZBQCGAgAmAAIJqAcKLwBPAAAjAAEJBQTHOQATAAAAAA==.Ravicavasar:BAAALgAECgEJAgAAAA==.Rawwr:BAABLgAECn8VAAIeAAcJPh/9IwArAgAeAAcJPh/9IwArAgAAAA==.Raynesong:BAAALgADCgYJBgAAAA==.Razfu:BAAALgAECgEJAgAAAA==.Razul:BAACLgAFFH8NAAIWAAQJayCABQCBAQAWAAQJayCABQCBAQAuAAQKfy8AAhYACQnhHssCAL4CABYACQnhHssCAL4CAAAA.',
Re='Redharvest:BAABLgAECn8gAAIIAAgJGBi/HADdAQAIAAgJGBi/HADdAQAAAA==.Redoofhealer:BAAALgAFFAEJAQAAAA==.Relentless:BAAALgAECgYJEQAAAA==.Relosaurus:BAAALgADCgEJAQAAAA==.Reportmypie:BAAALgAECgIJAgAAAA==.Restnpiece:BAABLgAECn8VAAMbAAYJEhVNKgByAQAbAAYJEhVNKgByAQABAAIJsAi2ewBWAAAAAA==.Reznoop:BAEALgAECgIJAgABLgAECgkJMQALAPUjAA==.',
Rh='Rhownin:BAAALgAECgcJEwABLgAFFAUJFgACAP4KAA==.',
Ri='Rinekraki:BAAALgADCgUJBQAAAA==.Rishal:BAAALgADCgMJAwABLgAECgYJCgAVAAAAAA==.Rispy:BAAALgAECgMJAwAAAA==.',
Rk='Rkoo:BAAALgAECggJEAAAAA==.',
Ro='Rob:BAAALgAECgEJAQAAAA==.Robstinks:BAAALgAECgEJAQAAAA==.Rotambo:BAAALgADCgEJAgAAAA==.Royawn:BAAALgAECgYJBgAAAA==.Royok:BAABLgAECn8fAAIgAAgJbB08CgBxAgAgAAgJbB08CgBxAgAAAA==.Royork:BAAALgADCgcJBwABLgAECggJHwAgAGwdAA==.',
Ru='Rudania:BAAALgAECgYJCwAAAA==.',
Ry='Rymjerb:BAAALgAECgYJCQAAAA==.',
['Rë']='Rënd:BAAALgADCgMJAwAAAA==.',
Sa='Sabarr:BAAALgADCgMJAwAAAA==.Saberwulf:BAAALgAECgYJDAAAAA==.Sabrewolf:BAAALgAECgMJBwAAAA==.Sabroen:BAAALgADCgYJBgABLgAECgQJDgAVAAAAAA==.Sacfusious:BAABLgAECn8VAAIGAAYJ+A3QQQA8AQAGAAYJ+A3QQQA8AQAAAA==.Saendnueds:BAAALgAECgUJBQAAAA==.Sakardi:BAAALgAECgIJAwAAAA==.Sannta:BAAALgADCgcJDAAAAA==.Sawedoff:BAABLgAECn8hAAMKAAgJIR78EABLAgAKAAgJIR78EABLAgAdAAYJ5xK3QwBIAQAAAA==.Sazeon:BAABLgAECn8hAAIIAAgJzhTLKQCSAQAIAAgJzhTLKQCSAQAAAA==.',
Sc='Scamall:BAECLgAFFH8eAAIeAAYJOiYdAQCOAgAeAAYJOiYdAQCOAgAuAAQKfzAAAh4ACQnFJhoAAPsDAB4ACQnFJhoAAPsDAAAA.Schizophreni:BAABLgAFFH8IAAIPAAMJhhrDPAAbAQAPAAMJhhrDPAAbAQABLgAFFAYJFwAMAN4fAA==.Schokowitz:BAABLgAECn8YAAIBAAgJMiCZBgB7AgABAAgJMiCZBgB7AgAAAA==.Scionoffury:BAAALgAECgEJAQAAAA==.Scorpeon:BAAALgAECgYJDwAAAA==.Scotcolumbus:BAABLgAECn8ZAAIlAAgJiiLOAgD9AgAlAAgJiiLOAgD9AgAAAA==.',
Se='Secsywood:BAAALgAECgUJBQAAAA==.Sefu:BAAALgADCgUJBQAAAA==.Seraius:BAAALgAECgYJEAAAAA==.Seresis:BAACLgAFFH8VAAMSAAUJiRzuGQA+AQASAAUJiRzuGQA+AQATAAEJAADEMAAAAAAuAAQKfyYAAhIACQnDIwoOACsDABIACQnCIwoOACsDAAAA.Sero:BAAALgAECgIJAgAAAA==.',
Sh='Shaankspec:BAAALgAECgYJEQAAAA==.Shade:BAACLgAFFH8NAAIWAAQJuguVDgA5AQAWAAQJuguVDgA5AQAuAAQKfy8AAxYACQlCF8YKAPQBABYACQlPFcYKAPQBABcAAQm6EpUYAD8AAAAA.Shadoewolfe:BAAALgAECgMJBwAAAA==.Shadowbindr:BAAALgAECgEJAwAAAA==.Shadowfallz:BAABLgAECn8fAAIZAAkJLB9BBgAFAwAZAAkJLB9BBgAFAwAAAA==.Shageron:BAACLgAFFH8WAAMdAAUJ1xsIAwC6AQAdAAUJ1xsIAwC6AQAKAAIJCRtzNACzAAAuAAQKfygAAh0ACQkLIiEFAE0DAB0ACQkLIiEFAE0DAAAA.Shagmeblind:BAAALgAECgcJEQAAAA==.Shammwoww:BAAALgADCggJGgAAAA==.Shampóóp:BAAALgAECgQJBQAAAA==.Shandoe:BAAALgAECgEJAQAAAA==.Shankspec:BAACLgAFFH8OAAIXAAUJWhzCAAC+AQAXAAUJWhzCAAC+AQAuAAQKfy0AAxcACQkTI2UAACQDABcACQkTI2UAACQDABYAAQkfGKNbAEYAAAAA.Shayu:BAAALgADCgYJCgAAAA==.Shifthappens:BAAALgAECgEJAQABLgAFFAMJBwAiAPARAA==.Shikaca:BAAALgAECgMJBAAAAA==.Shinseina:BAABLgAECn8oAAMLAAkJtRyoDQCSAgALAAkJtRyoDQCSAgAiAAUJXBXrZQDkAAAAAA==.Shivx:BAAALgAECgQJCQAAAA==.Shockblessed:BAAALgAECgEJAQAAAA==.Shockdh:BAAALgADCgkJCQABLgAFFAQJDQAOANoKAA==.Shockinawe:BAAALgAECgQJBwAAAA==.Shoeboo:BAAALgADCgcJCQAAAA==.Shoriuken:BAAALgAECgMJAwAAAA==.Shtiq:BAAALgAECgEJAwABLgAFFAQJDAAUADkkAA==.Shämash:BAABLgAECn8jAAIaAAkJBxXqCAC+AQAaAAkJBxXqCAC+AQAAAA==.Shízz:BAAALgADCgkJDQAAAA==.Shöck:BAAALgAECgYJBQAAAA==.',
Si='Sicc:BAAALgADCgIJAgAAAA==.Siccness:BAABLgAECn8cAAMKAAcJNCA9JwAcAgAKAAcJNCA9JwAcAgAhAAYJzBC8GwAmAQAAAA==.Sieben:BAAALgAECgEJAgAAAA==.Siella:BAABLgAECn8jAAIFAAgJ2RBIFQCrAQAFAAgJ2RBIFQCrAQAAAA==.Sileve:BAAALgAECgEJAgABLgAECgYJEwAVAAAAAA==.Silive:BAAALgADCgYJCQABLgAECgYJEwAVAAAAAA==.Sindrex:BAACLgAFFH8NAAIJAAQJ4CEZCQCIAQAJAAQJ4CEZCQCIAQAuAAQKfy8AAgkACQlMJIIAAKIDAAkACQlMJIIAAKIDAAEuAAQKAQkBABUAAAAA.Sinestus:BAABLgAECn8hAAIlAAgJ1CLCAQC1AgAlAAgJ1CLCAQC1AgAAAA==.',
Sk='Skoody:BAAALgAECgIJAwAAAA==.Skrrt:BAAALgAECgcJCAAAAA==.Skwerl:BAAALgAECgUJEwAAAA==.',
Sl='Slick:BAAALgAECgYJEgAAAA==.Slickarus:BAABLgAECn8rAAMNAAkJJSQVBgAhAwANAAkJuSMVBgAhAwARAAcJlR56AgAjAgAAAA==.Slumdawg:BAAALgADCgcJDAAAAA==.Slurmage:BAABLgAECn8nAAIPAAgJnCEHGABbAgAPAAgJnCEHGABbAgAAAA==.',
Sm='Smittywerben:BAAALgADCgUJBQAAAA==.Smooshi:BAACLgAFFH8QAAIbAAQJGiGrCwBuAQAbAAQJGiGrCwBuAQAuAAQKfzQAAxsACQmuIfwHAPUCABsACQmuIfwHAPUCAAEAAQnmHOtVAFUAAAAA.',
Sn='Snoke:BAAALgAECgEJAgAAAA==.',
So='Soleirel:BAABLgAECn8XAAIWAAYJqRziEACaAQAWAAYJqRziEACaAQAAAA==.Solfury:BAAALgADCgMJAwAAAA==.Solidjen:BAACLgAFFH8NAAILAAQJZAzzHQA2AQALAAQJZAzzHQA2AQAuAAQKfyAAAwsACQkQGgEUAFoCAAsACQkQGgEUAFoCACUAAwlECKU0AHQAAAAA.Solwalker:BAAALgADCgUJBQAAAA==.Soulfiend:BAAALgAECgIJAwAAAA==.',
Sp='Sparklefarts:BAAALgADCgYJDgAAAA==.Sparks:BAAALgAFFAIJAwAAAA==.Spearhead:BAAALgADCgEJAQAAAA==.Speedlings:BAACLgAFFH8TAAIWAAUJyB2QBwBtAQAWAAUJyB2QBwBtAQAuAAQKfyYAAhYACAm0IRUOAL4CABYACAm0IRUOAL4CAAAA.Spewky:BAAALgADCgUJBQAAAA==.Spicedale:BAAALgAECgUJBwAAAA==.',
Sq='Squiggles:BAAALgAECgEJAQAAAA==.',
St='Star:BAAALgAFFAIJAgAAAA==.Starfun:BAAALgAECgYJBgABLgAECgkJFgAbANELAA==.Stealthven:BAAALgAECgQJBAAAAA==.Steelheals:BAAALgAECgEJAQAAAA==.Stenzwar:BAABLgAFFH8HAAICAAMJmwqwHQDDAAACAAMJmwqwHQDDAAABLgAFFAUJDAASAIwiAA==.Stiq:BAACLgAFFH8MAAIUAAQJOSSDCgCeAQAUAAQJOSSDCgCeAQAuAAQKfy4AAhQACQnXI2kCADwDABQACQnXI2kCADwDAAAA.Stlux:BAAALgAECgcJDQAAAA==.Stojkette:BAAALgAECgYJEQAAAA==.Stormbless:BAABLgAECn8sAAIGAAkJ0RebCABAAgAGAAkJ0RebCABAAgAAAA==.Storminmycup:BAAALgAECgQJBgABLgAFFAYJEgABAG0bAA==.',
Su='Sukongdeez:BAAALgAECgEJAQABLgAECgEJAQAVAAAAAA==.Sulzire:BAAALgADCgQJAwAAAA==.Sumx:BAABLgAFFH8IAAILAAMJRiURFgBQAQALAAMJRiURFgBQAQAAAA==.Superarrows:BAAALgADCgQJBAAAAA==.Supersquirel:BAAALgAECgEJAwAAAA==.Superstabs:BAAALgADCgMJAwAAAA==.',
Sw='Sweeger:BAABLgAECn8qAAMbAAgJehnrGADqAQAbAAgJehnrGADqAQABAAMJBBRkPAC6AAAAAA==.Sweegie:BAAALgADCgYJBgAAAA==.Sweetlou:BAAALgADCgkJGgAAAA==.Swego:BAAALgAECgEJAQAAAA==.',
Sy='Syds:BAABLgAECn8fAAISAAgJWxzzFgBEAgASAAgJWxzzFgBEAgAAAA==.Sylaraa:BAAALgAECgcJEQAAAA==.Synapticzion:BAAALgAECggJDAAAAA==.Synatra:BAAALgAECgQJBQAAAA==.Syndra:BAAALgADCgEJAQABLgADCgUJBQAVAAAAAA==.',
['Sä']='Säpandtäp:BAAALgAECgcJBAAAAA==.',
['Sí']='Sílk:BAAALgAECgMJBgAAAA==.',
Ta='Taara:BAACLgAFFH8FAAMfAAMJJRwcBAAcAQAfAAMJJRwcBAAcAQAbAAEJagWKQAA+AAAuAAQKfy0AAh8ACQn6JSIAAHcDAB8ACQn6JSIAAHcDAAAA.Taarat:BAAALgAECgIJAgABLgAFFAMJBQAfACUcAA==.Tacobelf:BAAALgAECgQJBAAAAA==.Takkana:BAAALgAECgEJAgABLgAECgkJKwANACUkAA==.Talellianis:BAAALgAECgYJDQAAAA==.Tanjiro:BAAALgAECgMJAwABLgAECggJGwAPAGIYAA==.Tanneleer:BAAALgAECgEJAQAAAA==.Tarzo:BAAALgAECgIJAwAAAA==.Taucetiluna:BAAALgADCgYJBgAAAA==.Tazzyshmurda:BAAALgAECggJCAAAAA==.',
Tc='Tchaikovsky:BAAALgADCgQJBAAAAA==.',
Te='Tehdazzler:BAAALgADCgMJAwAAAA==.Tehdymare:BAAALgADCgYJBgAAAA==.Tehrains:BAAALgAECgEJAQAAAA==.Telenn:BAAALgAECgQJDQAAAA==.Terk:BAACLgAFFH8VAAIfAAUJ1SOZAADRAQAfAAUJ1SOZAADRAQAuAAQKfyYAAx8ACQlYJjQAAN0DAB8ACQlYJjQAAN0DABsAAQllBEmcADUAAAAA.Termina:BAABLgAECn8gAAMTAAgJRCJVAwCiAgATAAgJRCJVAwCiAgASAAYJRRnQgQB/AQAAAA==.',
Th='Thaatguy:BAAALgADCgEJAQAAAA==.Thalrymere:BAABLgAECn8hAAIdAAkJ7hgdBQDbAQAdAAkJ7hgdBQDbAQAAAA==.Thanirn:BAAALgAECgEJAwAAAA==.Thepruning:BAAALgAECgEJAQAAAA==.Thiccerlegs:BAABLgAECn8cAAMOAAcJIQfxKQD1AAAOAAcJIQfxKQD1AAAeAAUJdgYFXQCpAAAAAA==.Thiccwnr:BAABLgAECn8aAAQQAAcJUiO+AQAFAgAQAAYJCiS+AQAFAgAPAAMJVCCDqwC9AAAnAAMJKAvTBgClAAAAAA==.Thiccycheeks:BAACLgAFFH8MAAIIAAMJTiFCIwAiAQAIAAMJTiFCIwAiAQAuAAQKfxcAAggACQk8Hu8cAKQCAAgACQk8Hu8cAKQCAAAA.Thiccyquicki:BAAALgAECgQJBwABLgAFFAMJDAAIAE4hAA==.',
Ti='Ticklock:BAAALgADCgcJCAAAAA==.Tidelizard:BAACLgAFFH8UAAIJAAYJ6BD2BQCWAQAJAAYJ6BD2BQCWAQAuAAQKfx0AAgkACQmAHKUHAMMCAAkACQmAHKUHAMMCAAAA.Tigolbittys:BAABLgAECn8WAAMLAAcJIggicAANAQALAAcJHwcicAANAQAlAAYJTwUOKgC7AAAAAA==.Tikz:BAABLgAECn8oAAIUAAkJtA8hKQDBAQAUAAkJtA8hKQDBAQAAAA==.Tills:BAAALgADCgcJDgABLgAECgQJBAAVAAAAAA==.Tinycomp:BAAALgADCgIJAgAAAA==.',
To='Tock:BAACLgAFFH8JAAIfAAQJywxoBAANAQAfAAQJywxoBAANAQAuAAQKfyoAAh8ACQl+IRABAOQCAB8ACQl+IRABAOQCAAAA.Tockella:BAAALgADCgQJBAABLgAFFAQJCQAfAMsMAA==.Tockstar:BAAALgADCgcJBwAAAA==.Toe:BAAALgADCgcJDAAAAA==.Tokenwarrior:BAAALgAECgcJDQAAAA==.Tokodomo:BAAALgAECgYJBgABLgAFFAIJBgASANweAA==.Tollinyou:BAAALgADCgEJAQAAAA==.Torvï:BAAALgAECgYJDAAAAA==.',
Tr='Tralina:BAAALgADCgcJCQABLgAFFAUJGAAPABIcAA==.Trapstâr:BAABLgAFFH8MAAQKAAQJuRKsGgAyAQAKAAQJywysGgAyAQAdAAMJ1REtFQDzAAAhAAIJbw6MFQCoAAAAAA==.Treechicken:BAABLgAECn8aAAIeAAcJciWvBwDSAgAeAAcJciWvBwDSAgAAAA==.Tricky:BAABLgAECn8aAAMIAAgJbB+sJwBlAgAIAAgJ2B6sJwBlAgAZAAMJ1xyJSADRAAAAAA==.Trill:BAACLgAFFH8SAAIWAAUJnSQ/AwCoAQAWAAUJnSQ/AwCoAQAuAAQKfyUAAxYACAlMJFgGACsDABYACAlMJFgGACsDABgAAQl7GsoQAEoAAAAA.Tripotley:BAAALgAECgQJBAAAAA==.Trivalence:BAABLgAECn8WAAIeAAcJ0h5ZEQBGAgAeAAcJ0h5ZEQBGAgAAAA==.Truegrit:BAAALgADCgUJBQAAAA==.Trëspin:BAAALgAECgEJAQAAAA==.',
Ts='Tsarfun:BAAALgAECgcJEwABLgAECgkJFgAbANELAA==.Tseon:BAAALgAECgYJBgABLgAECggJIQAKACEeAA==.',
Tu='Tuor:BAAALgAECgQJCgAAAA==.Turaco:BAAALgADCgIJAgABLgAECgkJHgAaANcKAA==.',
Tw='Twizzurp:BAAALgAECgEJAQABLgAFFAIJAwAVAAAAAA==.',
Ty='Tywin:BAAALgADCgcJCgAAAA==.Tyèll:BAABLgAECn8XAAIMAAgJZQVqNgA6AQAMAAgJZQVqNgA6AQAAAA==.',
['Tá']='Tái:BAAALgAECgYJDQAAAA==.',
['Tÿ']='Tÿlope:BAAALgADCgYJBgAAAA==.',
Uj='Ujio:BAAALgAECgQJBQAAAA==.',
Un='Undeadwaifu:BAAALgADCgQJBAAAAA==.Unkledeath:BAAALgAECgQJAQAAAA==.',
Up='Upmysleeves:BAACLgAFFH8GAAIPAAMJvBddQgAGAQAPAAMJvBddQgAGAQAuAAQKfx4AAg8ABwmpInQXAF8CAA8ABwmpInQXAF8CAAAA.',
Va='Vance:BAAALgAECgQJBAAAAA==.Vaughn:BAACLgAFFH8QAAICAAYJlg7IBQCVAQACAAYJlg7IBQCVAQAuAAQKfyoAAgIACAk9HicMACgCAAIACAk9HicMACgCAAAA.Vaust:BAAALgAECgMJAwAAAA==.',
Ve='Vecerna:BAAALgAECgMJAwAAAA==.Vedekur:BAAALgADCgIJAgAAAA==.Veggieboi:BAACLgAFFH8GAAIUAAMJexU9IgD7AAAUAAMJexU9IgD7AAAuAAQKfykAAxQACAnRIYANAIACABQACAnRIYANAIACAAMAAQkAAFtjAEgAAAAA.Vellast:BAAALgAECgQJBQAAAA==.Velocathyr:BAABLgAECn8eAAMNAAkJARYVDQD6AQANAAkJARYVDQD6AQARAAEJ7A/6PQA3AAAAAA==.Venthunt:BAABLgAECn8fAAQdAAkJ3BtoDwDEAgAdAAkJtRtoDwDEAgAhAAYJRB5PFQByAQAKAAMJDyPSZQA2AQABLgAECgcJFAAGADsjAA==.Verellia:BAABLgAECn8XAAIIAAgJcRjCFwD+AQAIAAgJcRjCFwD+AQAAAA==.',
Vi='Victory:BAABLgAECn8WAAIiAAcJDCEdFwBZAgAiAAcJDCEdFwBZAgAAAA==.Vigilo:BAACLgAFFH8XAAIHAAUJsh9dBAB2AQAHAAUJsh9dBAB2AQAuAAQKfyQAAgcACQlwIzYCAIADAAcACQlwIzYCAIADAAAA.Vilhelmina:BAABLgAECn8VAAMWAAYJERqOGgAsAQAWAAUJVBqOGgAsAQAXAAIJBBnwFgBLAAAAAA==.Viruzdk:BAABLgAECn8kAAMTAAcJ/iGwDwB4AQASAAcJeh8tTgAIAgATAAUJyyKwDwB4AQAAAA==.',
Vo='Voidwalker:BAABLgAECn8SAAIIAAYJ3BUVYQB+AQAIAAYJ3BUVYQB+AQAAAA==.Voidwench:BAABLgAECn8kAAIIAAgJUCCvCQCMAgAIAAgJUCCvCQCMAgAAAA==.Volrog:BAACLgAFFH8SAAIfAAUJaBhJAgBhAQAfAAUJaBhJAgBhAQAuAAQKfy4AAh8ACQkGJrwBAEkDAB8ACQkGJrwBAEkDAAAA.Vosduo:BAAALgAECgMJAwAAAA==.',
Vr='Vritarah:BAAALgADCgcJCQAAAA==.',
Wa='Wafio:BAAALgADCgQJBAABLgAECgIJAgAVAAAAAA==.Warcheif:BAABLgAECn8jAAIKAAcJ6A29PABaAQAKAAcJ6A29PABaAQAAAA==.Warwonka:BAACLgAFFH8NAAIdAAQJlRRpCAA6AQAdAAQJlRRpCAA6AQAuAAQKfy8AAh0ACQl6HIwBAKACAB0ACQl6HIwBAKACAAAA.Warzan:BAAALgAECgQJCgAAAA==.Watchurbeard:BAABLgAECn8nAAIhAAkJWhTGDQDJAQAhAAkJWhTGDQDJAQAAAA==.Waviowi:BAABLgAECn8cAAIPAAgJJAveTACCAQAPAAgJJAveTACCAQAAAA==.',
We='Weatherdwarf:BAABLgAECn8YAAIbAAgJ0QltNwArAQAbAAgJ0QltNwArAQAAAA==.',
Wh='Whammer:BAABLgAECn8VAAIhAAkJ/Qe/EwCIAQAhAAkJ/Qe/EwCIAQAAAA==.Whiiplash:BAAALgAECgEJAQAAAA==.Whippy:BAAALgAECgEJAQABLgAECgEJAQAVAAAAAA==.Whooped:BAAALgAECgUJBgABLgAECggJKQAkACIcAA==.Whysolittle:BAAALgADCgUJBQAAAA==.',
Wi='Windfûrry:BAAALgAFFAIJAgABLgAFFAMJBQALACoaAA==.',
Wl='Wlntercamo:BAAALgAECgUJDgAAAA==.',
Wr='Wrapfire:BAAALgAECggJEgAAAA==.Wrapps:BAAALgAECgIJAgAAAA==.',
['Wí']='Wíldspirit:BAAALgADCgIJAgAAAA==.',
Xe='Xeroxed:BAABLgAECn8mAAISAAkJ+xn9FgBEAgASAAkJ+xn9FgBEAgAAAA==.',
Xi='Xiangmei:BAAALgAECggJDwAAAA==.',
Xo='Xon:BAAALgADCgQJBAAAAA==.',
Ya='Yacob:BAACLgAFFH8WAAIPAAYJgCE9BgD9AQAPAAYJgCE9BgD9AQAuAAQKfyYAAg8ACQnpJcsCANIDAA8ACQnpJcsCANIDAAAA.Yamarahj:BAACLgAFFH8KAAMUAAMJZhV8PADkAAAUAAMJZhV8PADkAAAoAAEJogYHCgBKAAAuAAQKfyMABCgACQkwH4QIAMEBABQACAmFG3dLAOcBACgABQnrHIQIAMEBAAMABAkJEo0uAAEBAAAA.Yavari:BAAALgAECgcJBwABLgAECgkJKgACADcfAA==.',
Ye='Yenna:BAAALgADCgEJAQAAAA==.',
Yo='Yorikk:BAABLgAECn8YAAMDAAgJpxR7FACnAQADAAgJegx7FACnAQAUAAUJZBVAWQAiAQAAAA==.Youngtwerk:BAAALgAECgUJBwAAAA==.',
Za='Zaeleane:BAABLgAECn8cAAIPAAgJXwiwTQCAAQAPAAgJXwiwTQCAAQAAAA==.Zanrak:BAAALgADCgYJCAABLgAECgQJCwAVAAAAAA==.Zard:BAABLgAECn8UAAIKAAYJ9wnPWAAFAQAKAAYJ9wnPWAAFAQAAAA==.Zardrelin:BAAALgADCgYJBgABLgADCgYJBwAVAAAAAA==.Zareynne:BAAALgAECgcJEgAAAA==.Zarmaku:BAAALgAECgQJBwAAAA==.Zathyr:BAAALgADCgQJBAAAAA==.Zauber:BAACLgAFFH8XAAQUAAYJUSR/AwDqAQAUAAYJVyJ/AwDqAQAoAAMJ+ST+AAA/AQADAAEJ+ByDEgBaAAAuAAQKfycABBQACQmAJokAAOEDABQACQk8JokAAOEDACgABwmvJtEAABgDAAMABwmLI4QGAGYCAAAA.Zazie:BAABLgAECn8mAAMcAAkJRRoEAgByAgAcAAkJRRoEAgByAgAIAAEJVRue4QAwAAAAAA==.Zazu:BAAALgAECgEJAQAAAA==.',
Ze='Zelani:BAAALgAECgYJCgAAAA==.Zensei:BAAALgAECgEJAQAAAA==.',
Zi='Zirraj:BAACLgAFFH8RAAICAAYJjR4UAQDWAQACAAYJjR4UAQDWAQAuAAQKfyUAAwIACQlrIqUFAEwDAAIACQlrIqUFAEwDABoAAQmdIBgxAFwAAAAA.',
Zm='Zmaj:BAAALgAECgcJCAABLgAFFAMJAwAVAAAAAA==.',
Zn='Zn:BAAALgAECgEJAQAAAA==.',
Zo='Zocalo:BAAALgAECgYJDQABLgAFFAUJFwAHALIfAA==.Zodiac:BAAALgAFFAEJAwABLgAFFAMJCgAjALAlAA==.Zoldyck:BAAALgAECggJCgAAAA==.Zorø:BAABLgAECn8mAAIcAAgJJg4BDQCIAQAcAAgJJg4BDQCIAQAAAA==.Zovinox:BAAALgAECgQJCwAAAA==.',
Zu='Zulrok:BAAALgADCgYJBgAAAA==.Zurk:BAAALgADCgEJAwAAAA==.',
Zy='Zygon:BAAALgAECgEJAwABLgAFFAMJCgAjALAlAA==.',
['Ãr']='Ãrthz:BAAALgAECgcJDAAAAA==.',
['Ôa']='Ôaf:BAAALgADCgEJAQAAAA==.',
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
