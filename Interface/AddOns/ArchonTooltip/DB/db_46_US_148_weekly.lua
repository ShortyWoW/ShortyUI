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

local lookup = {'Unknown-Unknown','Warrior-Fury','Priest-Discipline','Priest-Holy','DemonHunter-Devourer','Evoker-Preservation','Paladin-Retribution','Priest-Shadow','Druid-Balance','Mage-Frost','DeathKnight-Unholy','Warlock-Affliction','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','DemonHunter-Havoc','Warrior-Arms','Warlock-Demonology','Warlock-Destruction','Shaman-Restoration','Evoker-Augmentation','Evoker-Devastation','Hunter-Marksmanship','Druid-Restoration','Paladin-Holy','DemonHunter-Vengeance','Warrior-Protection','Shaman-Elemental','Monk-Brewmaster','Shaman-Enhancement','DeathKnight-Blood','Monk-Windwalker','Druid-Guardian','Monk-Mistweaver','Paladin-Protection','Hunter-BeastMastery','Druid-Feral','Hunter-Survival',}
local provider = {region='US',realm='Magtheridon',name='US',type='weekly',zone=46,date='2026-04-24',data={Ag='Agave:BAAALgAECgQJBQAAAA==.',
Ai='Aimwee:BAAALgAECgYJEQAAAA==.Aiur:BAAALgADCggJGgAAAA==.',
Ak='Akunzed:BAAALgADCgEJAQAAAA==.',
Al='Alaena:BAAALgADCgYJBgAAAA==.Alandivyn:BAAALgAECgMJBAAAAA==.Alarm:BAAALgADCgYJBgABLgAECgUJDwABAAAAAA==.Alcuard:BAAALgAECgYJCAAAAA==.Alesce:BAACLgAFFH8OAAICAAUJUgPLCABiAQACAAUJUgPLCABiAQAuAAQKfyYAAgIACQk6Gu0SALcCAAIACQk6Gu0SALcCAAAA.Alisinchains:BAAALgADCgcJCQAAAA==.',
Am='Amarauku:BAAALgAECgYJEQAAAA==.Amenadiel:BAABLgAECn8YAAMDAAYJCSTyDQBbAgADAAYJCSTyDQBbAgAEAAEJ4gpBfwAzAAAAAA==.America:BAAALgADCgIJAgAAAA==.Amyntas:BAAALgAECgMJBAAAAA==.Amythistle:BAAALgAECgYJEAAAAA==.',
An='Andrü:BAABLgAECn8cAAICAAgJ5B1DAwAaAgACAAgJ5B1DAwAaAgAAAA==.Andy:BAAALgAECgYJDAAAAA==.Anguscon:BAAALgADCgMJAwAAAA==.Anol:BAAALgAECgUJBQABLgAFFAUJDgAFABkiAA==.Antioch:BAAALgADCgkJGQAAAA==.',
Ar='Archael:BAAALgAECgQJBwAAAA==.Archimainos:BAABLgAECn8aAAIGAAcJTRZaFQD1AQAGAAcJTRZaFQD1AQAAAA==.Argorok:BAAALgAECgYJEQAAAA==.Argôroth:BAAALgADCgYJBgAAAA==.Arthz:BAAALgADCgcJBwAAAA==.',
As='Asheeus:BAAALgAECggJDQAAAA==.Ashtana:BAAALgADCgMJAwAAAA==.Ashtar:BAABLgAECn8aAAIHAAcJwRWoZAC4AQAHAAcJwRWoZAC4AQAAAA==.Assiasins:BAAALgAECgEJAQAAAA==.Asterok:BAAALgAECgYJDAAAAA==.Astravianda:BAAALgAECgUJBQAAAA==.Aszune:BAAALgADCgUJBQAAAA==.',
At='Atheria:BAECLgAFFH8GAAIIAAMJHxJUCwAAAQAIAAMJHxJUCwAAAQAuAAQKfxkAAggACAk0HPYRAGsCAAgACAk0HPYRAGsCAAAA.Athetaz:BAAALgAECgEJAQAAAA==.',
Au='Auggers:BAAALgAFFAIJBAAAAA==.Augthyr:BAAALgAECgQJBAABLgAECgcJFQAHAPIgAA==.',
Av='Avalen:BAABLgAECn8dAAIJAAcJHyN4DQDCAgAJAAcJHyN4DQDCAgAAAA==.Avarich:BAAALgAECgQJBAAAAA==.Avez:BAAALgADCgkJJwAAAA==.Aviee:BAACLgAFFH8FAAIKAAIJGB6tNQDAAAAKAAIJGB6tNQDAAAAuAAQKfxkAAgoABwkbH7hFAGcCAAoABwkbH7hFAGcCAAAA.Avishun:BAAALgAECgYJCgAAAA==.Avreel:BAAALgAECgYJEwAAAA==.',
Az='Azazi:BAACLgAFFH8OAAIKAAUJhSKrBAB9AQAKAAUJhSKrBAB9AQAuAAQKfygAAgoACQnCJEUDAMsDAAoACQnCJEUDAMsDAAAA.Azonia:BAAALgADCgUJBgABLgAECgYJEgABAAAAAA==.Azushi:BAAALgAECgYJDAABLgAECgcJGwACAD0dAA==.',
Ba='Babymage:BAACLgAFFH8FAAIKAAMJWAkcFADzAAAKAAMJWAkcFADzAAAuAAQKfyEAAgoACAnnFIVVADgCAAoACAnnFIVVADgCAAAA.Badform:BAAALgADCgkJIAAAAA==.Badkitteh:BAAALgAECgQJAwAAAA==.Baelstrom:BAAALgAECggJEQAAAA==.Baendron:BAABLgAECn8XAAILAAgJbxfkPgA8AgALAAgJbxfkPgA8AgAAAA==.Bahnna:BAAALgAECgYJEwAAAA==.Bananana:BAAALgADCgcJBwAAAA==.Barbarik:BAAALgAECgUJBQABLgAFFAIJBQAMAMwGAA==.Barberry:BAAALgADCgkJCQABLgADCgUJBQABAAAAAA==.',
Be='Beardsmite:BAEALgAECgYJCwABLgABCgEJAQABAAAAAA==.Beerbeeotch:BAAALgADCgcJDQAAAA==.Beerus:BAAALgAECgYJEQAAAA==.Bellaynia:BAAALgADCgcJDQAAAA==.Belmuerto:BAAALgAECgYJDAAAAA==.Benzopatrol:BAAALgAECgQJCAAAAA==.Besnel:BAAALgAECgQJBwAAAA==.',
Bi='Bigtuna:BAAALgADCgIJAgAAAA==.',
Bl='Blackbolt:BAAALgADCgMJAwAAAA==.Blackhaus:BAAALgADCgYJBgAAAA==.Blixxy:BAAALgADCgEJAQAAAA==.Blorgin:BAACLgAFFH8MAAMNAAUJERffBwBpAQANAAUJOxbfBwBpAQAOAAEJlRPjAgBdAAAuAAQKfyUABA0ACQlVI5MCAIADAA0ACQn7IpMCAIADAA4AAglsI6UFAMwAAA8AAQlgAA8QABcAAAAA.Bléssed:BAAALgAECgEJAgAAAA==.',
Bo='Boinky:BAAALgAECgYJEQAAAA==.Boneham:BAAALgAECgQJBAAAAA==.Bookers:BAABLgAECn8eAAMQAAgJJxIiHADfAQAQAAgJJxIiHADfAQAFAAMJQQSVOQB3AAAAAA==.Booplzs:BAABLgAECn8dAAIKAAcJ5RXDFgCNAQAKAAcJ5RXDFgCNAQAAAA==.Borgo:BAAALgADCgkJDwABLgAECggJHgAKAH0QAA==.Boulangerie:BAACLgAFFH8QAAIIAAUJ5iHFAgDJAQAIAAUJ5iHFAgDJAQAuAAQKfygAAggACQnAJhsAAAsEAAgACQnAJhsAAAsEAAAA.Boulezen:BAAALgAECgEJAQAAAA==.Boulidan:BAAALgAECgYJDwAAAA==.Boulior:BAAALgADCgcJEgAAAA==.Bounceonit:BAAALgAECggJCAAAAA==.Boyd:BAACLgAFFH8MAAICAAUJtRb0CABgAQACAAUJtRb0CABgAQAuAAQKfyEAAwIACAnaGukbAG4CAAIACAnaGukbAG4CABEAAQklCTlEADAAAAAA.',
Br='Breeding:BAAALgAECgYJBgABLgAFFAIJBAABAAAAAA==.Brent:BAAALgADCgUJBQAAAA==.Brewm:BAAALgAECgMJAwAAAA==.Brewmungandr:BAAALgAECgUJDgAAAA==.Brightnight:BAAALgADCgEJAQABLgAECgYJEAABAAAAAA==.Brokenbone:BAAALgAECgUJBgAAAA==.Bromayzo:BAAALgAECgQJBAAAAA==.Brujo:BAAALgADCgcJCAAAAA==.Bruënor:BAAALgAECgYJDgAAAA==.Brylen:BAAALgAECgYJBgAAAA==.',
Bu='Budweis:BAAALgADCgEJAQAAAA==.Bullkkake:BAAALgAECgIJAwAAAA==.Bumii:BAAALgAECgYJDAABLgAECggJGgASADcgAA==.',
By='Byfryasbeard:BAAALgADCgcJEwAAAA==.',
Ca='Canadatrash:BAAALgADCgcJBwABLgAECgcJFQAHAPIgAA==.Carltonbanks:BAAALgAECgYJBgAAAA==.Cashewz:BAAALgAECggJCwAAAA==.Casterella:BAAALgADCgEJAQAAAA==.Caylithia:BAAALgAECgYJEgAAAA==.',
Ce='Ceasarsalad:BAABLgAECn8hAAMTAAkJhQp/FgCWAQATAAgJfwt/FgCWAQASAAYJBwqBtgDrAAAAAA==.Ceazyweasley:BAAALgAECgcJEwAAAA==.Celestriå:BAAALgAECgYJEwAAAA==.Cernnuunnos:BAAALgADCgUJBQAAAA==.Cetana:BAAALgADCgUJBQABLgAECgcJFQAHAPIgAA==.',
Ch='Chadlockb:BAACLgAFFH8SAAISAAYJrSHnAADIAQASAAYJrSHnAADIAQAuAAQKfy4AAxIACQkfJKkAAP4CABIACQkfJKkAAP4CABMAAwkwFAM5ANAAAAAA.Cheesee:BAABLgAECn8ZAAIUAAgJhCDjCADoAgAUAAgJhCDjCADoAgAAAA==.Christlike:BAAALgADCgYJBwAAAA==.Chronite:BAABLgAECn8eAAIKAAgJfRCXIwBDAQAKAAgJfRCXIwBDAQAAAA==.Chuffy:BAAALgAECgQJBgAAAA==.',
Ci='Cindr:BAACLgAFFH8LAAIVAAUJOB7BAwDfAQAVAAUJOB7BAwDfAQAuAAQKfyYAAxUACQlHJqIAAN0DABUACQlHJqIAAN0DABYABwnvG9cNAPwBAAAA.Circumstance:BAACLgAFFH8FAAMEAAMJ4QTBDwB/AAADAAIJvAMFFgCCAAAEAAIJWgbBDwB/AAAuAAQKfysABAQACQkuHHIFAPgCAAQACQmTG3IFAPgCAAMACQlkFMcPAEICAAgAAgmbDUdVAG0AAAAA.Cirice:BAAALgADCgIJAwAAAA==.',
Cl='Claylock:BAABLgAECn8bAAISAAgJ7hhHCQDcAQASAAgJ7hhHCQDcAQAAAA==.Cleattus:BAAALgAECgcJEwAAAA==.Cleric:BAAALgAECgQJBAAAAA==.',
Co='Coarseblood:BAAALgADCgcJGwAAAA==.Cody:BAACLgAFFH8KAAIIAAUJASBhBQB2AQAIAAUJASBhBQB2AQAuAAQKfyUAAggACQnPJYUBALEDAAgACQnPJYUBALEDAAAA.Codyh:BAAALgAECgYJBgAAAA==.Codyp:BAAALgAECgYJBgAAAA==.Colddblooded:BAAALgAECgQJBgAAAA==.Coldoyazda:BAAALgAECgEJAQAAAA==.Cololol:BAACLgAFFH8OAAIFAAUJGSLwBADeAQAFAAUJGSLwBADeAQAuAAQKfzYAAwUACQnmJdQAANwDAAUACQnmJdQAANwDABAAAwmzHXVJAMwAAAAA.Conjurous:BAAALgADCgYJCQABLgAECgQJBQABAAAAAA==.Cooper:BAABLgAECn8cAAIXAAgJzyCGAABnAgAXAAgJzyCGAABnAgAAAA==.Corbis:BAAALgADCgYJBgABLgAECgUJDgABAAAAAA==.Corruptica:BAAALgADCggJCgAAAA==.Cosmos:BAABLgAECn8cAAIYAAgJnRk+LwDvAQAYAAgJnRk+LwDvAQAAAA==.Cowlvlislie:BAAALgAECgUJBQAAAA==.',
Cr='Creami:BAAALgADCgEJAgAAAA==.Creastos:BAAALgAECgEJAgAAAA==.Crew:BAACLgAFFH8MAAIQAAUJlRv7AQB5AQAQAAUJlRv7AQB5AQAuAAQKfykAAxAACQnkI98BAH8DABAACQnkI98BAH8DAAUAAQkAAFReAAAAAAAA.Crispy:BAAALgAECgEJAQAAAA==.Cronozret:BAAALgADCgEJAQAAAA==.',
Cu='Cucokai:BAABLgAECn8VAAIUAAcJpx/sAwA6AgAUAAcJpx/sAwA6AgAAAA==.Cuddlekaren:BAAALgAFFAIJAgABLgAFFAUJDgAXAN0RAA==.Cuddlestomp:BAACLgAFFH8OAAIXAAUJ3RGGCQCAAQAXAAUJ3RGGCQCAAQAuAAQKfyYAAhcACQkVJOQDAGQDABcACQkVJOQDAGQDAAAA.',
['Cä']='Cämulos:BAAALgAECgYJEQAAAA==.',
['Cí']='Círí:BAEALgAECgcJEwABLgABCgEJAQABAAAAAA==.',
Da='Dabudtanka:BAAALgAECgEJAQAAAA==.Dacat:BAAALgAECgQJBAAAAA==.Daddylongleg:BAAALgADCgEJAQAAAA==.Damnhammer:BAABLgAFFH8FAAIZAAMJEBQyBgDyAAAZAAMJEBQyBgDyAAAAAA==.Dandie:BAAALgAECgIJAgAAAA==.Dantalian:BAAALgAECgYJEQABLgAFFAUJDAAKAGIcAA==.Darthmerlin:BAABLgAECn8VAAIKAAYJaBe/kQCwAQAKAAYJaBe/kQCwAQAAAA==.Darthpanda:BAAALgADCgMJAgABLgAECgYJFQAKAGgXAA==.Darthsanguis:BAAALgADCgEJAQABLgAECgYJFQAKAGgXAA==.Darthvaper:BAAALgADCgEJAQAAAA==.Dasakko:BAACLgAFFH8FAAIEAAMJ8hZaAwD1AAAEAAMJ8hZaAwD1AAAuAAQKfyEAAgQACAnNHwsHANwCAAQACAnNHwsHANwCAAAA.',
Db='Dbowz:BAAALgAECgUJBQAAAA==.',
De='Deathbeeotch:BAAALgAECgYJEwAAAA==.Deathcaller:BAAALgAECgUJCQAAAA==.Deblacksheep:BAAALgADCgIJAgABLgAECgYJEgABAAAAAA==.Deliscera:BAAALgADCgYJBgAAAA==.Delithsong:BAAALgADCggJCAAAAA==.Demonhunterl:BAAALgAECgUJDgAAAA==.Demonishall:BAAALgAECgIJAwAAAA==.Demontim:BAAALgAECgcJDQAAAA==.Denjin:BAAALgADCgEJAgAAAA==.Destile:BAAALgAECgQJBAABLgAECgYJDQABAAAAAA==.Dethe:BAAALgAECgQJBwAAAA==.Dewme:BAAALgADCgYJBgAAAA==.',
Dh='Dhbowz:BAACLgAFFH8KAAIFAAQJ9BslBABlAQAFAAQJ9BslBABlAQAuAAQKfyEAAwUACAkKJJIUANwCAAUACAktI5IUANwCABoAAgkJI8MZAMgAAAAA.',
Di='Dinkyfu:BAAALgADCggJAgAAAA==.Dipndots:BAAALgADCgYJBgAAAA==.',
Dn='Dnok:BAAALgADCgEJAQAAAA==.',
Do='Doc:BAAALgAECgYJBgAAAA==.Doguntarth:BAABLgAECn8bAAICAAcJPR0SCQCOAQACAAcJPR0SCQCOAQAAAA==.Domerneth:BAAALgAECgUJDwAAAA==.Doomfury:BAAALgAECgcJCwAAAA==.Dotsfired:BAAALgAECgYJBwABLgAECgYJGQAbAC8jAA==.Doylescars:BAAALgADCgIJAgAAAA==.',
Dr='Dragonboi:BAAALgAECgYJBgAAAA==.Dragonbutt:BAAALgAECgMJAwAAAA==.Dragson:BAAALgADCgEJAQAAAA==.Drakkarus:BAAALgAECgQJCAAAAA==.Drankincup:BAACLgAFFH8QAAIcAAUJyBq0AQBwAQAcAAUJyBq0AQBwAQAuAAQKfywAAhwACAmVJAwHACIDABwACAmVJAwHACIDAAAA.Drchinstraps:BAAALgADCgIJAgAAAA==.Drstagger:BAEBLgAECn8dAAIdAAgJFSbZAQCHAwAdAAgJFSbZAQCHAwAAAA==.',
Du='Duskflower:BAACLgAFFH8MAAIYAAUJKRRAAgCPAQAYAAUJKRRAAgCPAQAuAAQKfycAAhgACQl9G9oZAGoCABgACQl9G9oZAGoCAAAA.',
Eb='Ebonessences:BAAALgAECgEJAQAAAA==.',
Ec='Echochaser:BAAALgADCggJDgAAAA==.',
Ed='Eddard:BAAALgADCgYJCwAAAA==.',
Ej='Eject:BAAALgAECgQJBQAAAA==.',
El='Elexandur:BAABLgAECn8VAAIeAAgJ8xUtCABgAgAeAAgJ8xUtCABgAgAAAA==.Ellenarna:BAAALgAECgUJBwAAAA==.Elleri:BAAALgAECgcJEgAAAA==.Ellyse:BAAALgADCgEJAQAAAA==.',
En='Entrøpy:BAABLgAECn8VAAIHAAcJ8iAlLgBqAgAHAAcJ8iAlLgBqAgAAAA==.',
Ep='Epnodk:BAAALgAFFAEJAQABLgAFFAQJDgAdAJYZAA==.Epnokicks:BAACLgAFFH8OAAIdAAQJlhntAgBWAQAdAAQJlhntAgBWAQAuAAQKfygAAh0ACQmpIkoDAGADAB0ACQmpIkoDAGADAAAA.Epnopal:BAAALgADCgMJAwABLgAFFAQJDgAdAJYZAA==.',
Er='Eroicel:BAAALgAECgMJAwABLgAFFAUJDwAfAD8RAA==.',
Ev='Evarielle:BAACLgAFFH8PAAIfAAUJPxHWAwAGAQAfAAUJPxHWAwAGAQAuAAQKfy4AAh8ACQmcHocFAOcCAB8ACQmcHocFAOcCAAAA.Evelis:BAAALgAECgYJEAAAAA==.Evilina:BAAALgADCgIJAwAAAA==.Evillmaster:BAAALgADCgUJCgAAAA==.',
Fa='Fadedhalo:BAAALgAECgQJBQAAAA==.Falaya:BAACLgAFFH8PAAMTAAUJOx8nAACXAQATAAUJOx8nAACXAQASAAIJSR4vLAC+AAAuAAQKfygAAxMACQlJJDoBACADABMACAnaIToBACADABIABgm/HuxFAPkBAAAA.Fallinorion:BAAALgADCgYJBgAAAA==.Fancy:BAAALgAECgYJCgAAAA==.Farion:BAAALgAECgQJBgAAAA==.',
Fe='Fearlite:BAAALgAECgEJAQAAAA==.Feldoyle:BAAALgAECgIJAgAAAA==.Felel:BAAALgADCgEJAQAAAA==.Felfi:BAAALgAECgIJAgAAAA==.Felroc:BAAALgAECgEJAQAAAA==.Fenix:BAAALgAECgYJDQAAAA==.Fersos:BAAALgAECgcJEwAAAA==.',
Fi='Firefaux:BAAALgAECgQJBAAAAA==.',
Fl='Flawlessxi:BAAALgAECgYJCwAAAA==.Flyntflosy:BAACLgAFFH8OAAIcAAUJjBXGCQBEAQAcAAUJjBXGCQBEAQAuAAQKfygAAhwACQleH54FADsDABwACQleH54FADsDAAAA.',
Fo='Foxreich:BAAALgAECgYJEgAAAA==.',
Fr='Fragment:BAAALgAECgYJEQAAAA==.Frozoevoko:BAAALgAECgQJBgABLgAFFAUJDwAKAGYgAA==.',
Fu='Funstar:BAAALgAECgYJCQABLgAECggJEQABAAAAAA==.Furyess:BAAALgAECgEJAgAAAA==.',
['Fî']='Fîrebolt:BAAALgADCgMJAwAAAA==.',
Ga='Gaelsi:BAABLgAECn8UAAMgAAgJDR36AwDLAQAgAAgJDR36AwDLAQAdAAEJPBWBiwAuAAAAAA==.Galactic:BAAALgADCgkJCQABLgAECgcJHgAhAIcmAA==.Galgore:BAABLgAECn8UAAIZAAgJkAsSOQCWAQAZAAgJkAsSOQCWAQAAAA==.Ganvvitch:BAAALgADCgUJBQAAAA==.Garolok:BAABLgAECn8dAAIRAAgJ/Bm7BQB6AgARAAgJ/Bm7BQB6AgAAAA==.Gartiss:BAAALgAECgQJCwAAAA==.Gate:BAAALgADCggJGQAAAA==.Gazelle:BAEBLgAECn8cAAIdAAgJIBRdCABxAQAdAAgJIBRdCABxAQAAAA==.Gazerakhan:BAAALgADCgcJDAABLgAECggJJQAFAAYUAA==.Gazerielle:BAABLgAECn8lAAQFAAgJBhT4EgBoAQAFAAgJfBP4EgBoAQAaAAYJuBSAEABJAQAQAAEJsAcyeAAsAAAAAA==.',
Gh='Gherthquakes:BAAALgADCgIJAgAAAA==.',
Gi='Ginsoda:BAAALgADCgcJCwAAAA==.Ginthril:BAAALgAECgEJAQABLgAECgcJFQAfAHQkAA==.Ginwine:BAABLgAFFH8FAAMZAAMJWxXEBwC7AAAZAAMJWxXEBwC7AAAHAAEJ4h8+LABhAAABLgAFFAUJDwASAAUlAA==.Gitzsum:BAAALgADCgUJBQAAAA==.',
Gl='Glizzylizzy:BAACLgAFFH8FAAIeAAMJNyMLAQAwAQAeAAMJNyMLAQAwAQAuAAQKfxsAAh4ACAlUJAoCADkDAB4ACAlUJAoCADkDAAAA.',
Gn='Gnaeus:BAAALgAECgMJAwAAAA==.',
Go='Goldilockes:BAAALgADCgcJCgAAAA==.Gorca:BAAALgAECgEJAQABLgAECgEJAQABAAAAAA==.Gothbaddie:BAAALgADCgEJAQAAAA==.Gourmando:BAAALgADCgYJDAABLgAECgUJBQABAAAAAA==.Gowownage:BAABLgAECn8eAAIhAAcJhyY6AgATAwAhAAcJhyY6AgATAwAAAA==.',
Gr='Gradius:BAACLgAFFH8HAAMfAAUJKxURAgBHAQAfAAUJKxURAgBHAQALAAEJQwCzXQApAAAuAAQKfyMAAwsACQmtHKwpAJMCAAsACQlVHKwpAJMCAB8ABwmpFikJAPUAAAAA.Granddh:BAAALgAECgEJAQAAAA==.Grandmage:BAABLgAECn8VAAIKAAgJFBGEewDaAQAKAAgJFBGEewDaAQAAAA==.Graydius:BAAALgADCgUJBQAAAA==.Greenpanda:BAABLgAECn8ZAAIdAAgJORRRLgCfAQAdAAgJORRRLgCfAQAAAA==.Greenwarrior:BAAALgAECgYJCQAAAA==.Greydeus:BAAALgAFFAIJAgABLgAFFAUJBwAfACsVAA==.Grimeclipse:BAAALgAECgUJCwAAAA==.Groves:BAAALgAECgUJCgABLgAECggJHgAiAK0ZAA==.Grumpoo:BAAALgAECgQJBQAAAA==.',
Gu='Gurt:BAABLgAECn8YAAMCAAcJOw8PQwCYAQACAAcJOQ4PQwCYAQARAAYJUQrnCQDGAAAAAA==.',
['Gø']='Gøøn:BAABLgAECn8aAAIKAAgJwBYxUABHAgAKAAgJwBYxUABHAgAAAA==.',
Ha='Halestorm:BAAALgAECgYJEQAAAA==.Halk:BAACLgAFFH8OAAIHAAUJBBuTAwC6AQAHAAUJBBuTAwC6AQAuAAQKfyYAAgcACQkmJO0GAGEDAAcACQkmJO0GAGEDAAAA.Haonao:BAAALgADCgYJCwAAAA==.Harris:BAAALgAFFAIJAgABLgAFFAUJEAAIAOYhAA==.Havefun:BAAALgAECggJEQAAAA==.',
He='Hedonist:BAAALgAECgcJCgABLgAFFAIJBQAMAMwGAA==.Hellquack:BAABLgAECn8bAAQRAAgJRgs2GAA3AQARAAgJBgk2GAA3AQAbAAUJMgsPLQDZAAACAAMJOQVWjQCJAAAAAA==.Hellsbringer:BAAALgAECgcJEQAAAA==.Hellzard:BAAALgADCgYJBwAAAA==.Hermito:BAAALgAECgUJBQABLgAECgcJFwAPAM8eAA==.',
Ho='Hollowed:BAAALgAECgQJBAAAAA==.Holycandi:BAAALgAECgIJBAAAAA==.Holydoyle:BAAALgAECgUJDgAAAA==.Holytrident:BAAALgAECgUJEgAAAA==.Homelessman:BAAALgAECgYJBgAAAA==.Hotpøcket:BAACLgAFFH8IAAIYAAMJyg+0EQDcAAAYAAMJyg+0EQDcAAAuAAQKfx4AAxgACQncHbcLAOICABgACQncHbcLAOICAAkAAQnGFUJ7ADsAAAAA.',
Hu='Hugebowels:BAAALgAECgMJAwABLgAECgcJGQAOAC4XAA==.Hugefeet:BAABLgAECn8ZAAMOAAcJLhcDBgAfAgAOAAcJLhcDBgAfAgAPAAMJ6QT6AwCDAAAAAA==.Humorous:BAAALgAECgUJCQAAAA==.',
Hy='Hyperìen:BAACLgAFFH8PAAIjAAUJQyJMAADLAQAjAAUJQyJMAADLAQAuAAQKfyMAAiMACQnaJEgAALIDACMACQnaJEgAALIDAAAA.',
Ic='Icanmoonu:BAAALgAECgQJCQAAAA==.Icedoggi:BAAALgAECgYJEAAAAA==.',
Il='Illzilla:BAAALgADCgcJDwAAAA==.',
Im='Imfinnabust:BAAALgADCgIJAgAAAA==.Immortalmage:BAAALgAECgUJBgAAAA==.Imnosuperman:BAAALgAECgEJAQAAAA==.Imsopro:BAAALgADCgEJAQAAAA==.',
In='Inferna:BAAALgADCgcJBgAAAA==.Inferno:BAAALgADCgQJBAAAAA==.Intiq:BAAALgADCgkJDwAAAA==.Invisibul:BAAALgAECgEJAgAAAA==.',
Ip='Ipmanz:BAAALgAECgIJAgAAAA==.',
Ir='Irbaboon:BAAALgAECgQJBQABLgAECgYJCAABAAAAAA==.Irreletaur:BAACLgAFFH8JAAICAAQJChDABgD0AAACAAQJChDABgD0AAAuAAQKfyQAAgIACAk2H58YAIcCAAIACAk2H58YAIcCAAAA.',
Is='Isitovernow:BAAALgADCgQJBAABLgAECgYJEgABAAAAAA==.Ismitethee:BAAALgADCgcJDQAAAA==.',
It='Itsovernow:BAAALgAECgYJEgAAAA==.Itzqt:BAAALgADCgcJCwAAAA==.',
Iz='Izimir:BAABLgAECn8UAAIZAAgJyBdXJwDwAQAZAAgJyBdXJwDwAQAAAA==.',
Ja='Jackiechàn:BAAALgAECgUJBQABLgAECgcJFQAHAPIgAA==.Jacosta:BAABLgAECn8fAAIKAAgJExnbCQAMAgAKAAgJExnbCQAMAgAAAA==.Jadeazul:BAAALgADCgcJCAAAAA==.Jadis:BAAALgAECgUJDQAAAA==.Jamgirl:BAABLgAECn8VAAIfAAcJdCTNBgDHAgAfAAcJdCTNBgDHAgAAAA==.Jampu:BAAALgADCgEJAQAAAA==.Jangokin:BAACLgAFFH8NAAIJAAUJAQ7oBwBiAQAJAAUJAQ7oBwBiAQAuAAQKfyYAAgkACQl0IcoEAFQDAAkACQl0IcoEAFQDAAAA.Jaskvoid:BAAALgAECgYJEQAAAA==.Jasminepesto:BAAALgADCgkJDgAAAA==.Jatloo:BAAALgADCgQJBAABLgAECgQJCwABAAAAAA==.Jaysis:BAAALgAECgYJDQAAAA==.',
Je='Jermz:BAAALgAECgQJBAAAAA==.',
Jg='Jgrass:BAAALgAECgYJDAAAAA==.',
Ji='Jimba:BAACLgAFFH8FAAIkAAMJFBihBwAKAQAkAAMJFBihBwAKAQAuAAQKfyEAAiQACAlCH08KAPUCACQACAlCH08KAPUCAAAA.Jinks:BAAALgAECgMJAwAAAA==.',
Jo='Joelrobuchon:BAAALgAECgIJAgAAAA==.Jorres:BAAALgADCgMJAwAAAA==.Joslynn:BAAALgAECgIJAgAAAA==.Joytoy:BAAALgAECgMJAwAAAA==.',
Ju='Judgments:BAAALgAECgYJCwAAAA==.Jumalauta:BAAALgAECgQJCQAAAA==.Junglejooce:BAAALgADCgYJBgAAAA==.',
['Jè']='Jèrmz:BAAALgADCgEJAQAAAA==.',
['Jí']='Jím:BAAALgAECgcJEgAAAA==.',
Ka='Kabang:BAAALgAECgIJAQABLgAECggJGQASABQUAA==.Kabonk:BAAALgADCggJCAABLgAECggJGQASABQUAA==.Kaelstryna:BAAALgADCgQJBAAAAA==.Kaerbear:BAAALgADCgcJBwAAAA==.Kaige:BAAALgAECgQJCAAAAA==.Kala:BAAALgAECgYJCgAAAA==.Kalithor:BAAALgAECgYJDQAAAA==.Kalrodomes:BAAALgAECgYJBgAAAA==.Kasey:BAAALgAECgEJAQAAAA==.Kathery:BAAALgAECgMJBgAAAA==.Kathoes:BAAALgAECgIJAwAAAA==.Kazen:BAAALgAECgQJBwAAAA==.',
Ke='Keili:BAAALgAECgEJAQAAAA==.Kellandron:BAAALgADCgkJCAAAAA==.Kellwildfire:BAABLgAECn8VAAICAAcJIQ9rQACiAQACAAcJIQ9rQACiAQAAAA==.Kethrin:BAAALgADCgYJBgAAAA==.',
Kh='Khamael:BAACLgAFFH8MAAIKAAUJYhz/FgBtAQAKAAUJYhz/FgBtAQAuAAQKfygAAgoACQnnI40JAHkDAAoACQnnI40JAHkDAAAA.Kheiron:BAAALgAFFAIJAgAAAA==.',
Ki='Kilimanjaro:BAAALgADCgkJDgABLgAECgIJAgABAAAAAA==.Kinu:BAABLgAECn8eAAIUAAgJWx5xAwBJAgAUAAgJWx5xAwBJAgAAAA==.Kitane:BAABLgAECn8WAAIgAAcJqBsNGAAjAgAgAAcJqBsNGAAjAgAAAA==.Kitsunibi:BAABLgAECn8VAAMJAAYJHxHmPwAyAQAJAAYJHxHmPwAyAQAYAAYJ8wYsewDnAAAAAA==.Kittyneko:BAAALgAECgYJDAAAAA==.',
Kl='Klump:BAAALgADCgEJAQAAAA==.',
Ko='Kobieta:BAAALgAFFAIJBAAAAA==.Kolei:BAAALgADCgQJBAAAAA==.Konica:BAABLgAECn8WAAMUAAgJ8AnPPwCBAQAUAAgJ8AnPPwCBAQAcAAEJbQGHlwAYAAAAAA==.Kookykraving:BAAALgAECgYJBgAAAA==.Korgesh:BAAALgADCgkJEwAAAA==.Kotharsevant:BAAALgAECgEJAQAAAA==.',
Kr='Kraypoe:BAABLgAECn8WAAIFAAgJsQoZaABqAQAFAAgJsQoZaABqAQAAAA==.Krondys:BAAALgAECgQJBAAAAA==.Krìeg:BAAALgAECgIJAgABLgAECgIJAgABAAAAAA==.',
Ks='Ksiezniczka:BAAALgADCgMJBAAAAA==.',
Ku='Kurohail:BAAALgADCgYJBgABLgAECggJJAAbALgjAA==.Kurolion:BAAALgAECgYJDAAAAA==.Kurosong:BAABLgAECn8kAAIbAAgJuCNMAwAlAwAbAAgJuCNMAwAlAwAAAA==.',
Kw='Kwanrbless:BAAALgAECgYJDQAAAA==.',
Ky='Kyblade:BAABLgAECn8fAAIIAAgJKyS3AADBAgAIAAgJKyS3AADBAgAAAA==.Kyogre:BAAALgAECgUJBgAAAA==.Kyrr:BAABLgAECn8VAAINAAcJNBuCFwBNAgANAAcJNBuCFwBNAgAAAA==.',
['Kù']='Kùrupt:BAAALgAECgEJAQABLgAFFAQJCAANAKsRAA==.',
La='Labombah:BAAALgADCgMJBgAAAA==.Ladrogue:BAAALgAECgUJBQAAAA==.Landdragon:BAAALgAECgIJAgAAAA==.Landslide:BAAALgAECgEJAgAAAA==.Lasaruz:BAAALgAECgcJEQAAAA==.Lavajato:BAAALgADCgUJBQABLgAECgcJFgATAN4NAA==.',
Le='Leemius:BAAALgAECgQJBgAAAA==.Legionearth:BAAALgAECgMJBAAAAA==.Leosbryn:BAABLgAECn8VAAITAAgJpxNMAQC7AQATAAgJpxNMAQC7AQAAAA==.Levie:BAAALgAECgYJDAAAAA==.',
Lh='Lhaxorp:BAAALgAECgYJEQABLgAECgkJKAAHANUhAA==.',
Li='Liable:BAAALgAECgIJAgABLgAECgUJDgABAAAAAA==.Lighthammer:BAAALgAECgYJDQABLgADCgMJAwABAAAAAA==.Liiadrin:BAAALgADCgIJAgAAAA==.Listerfyne:BAAALgAECgQJBAAAAA==.Lithariel:BAAALgAECgUJBgAAAA==.',
Lo='Lonelybard:BAAALgAECgUJBQAAAA==.Loumis:BAAALgAECgQJCAAAAA==.',
Lu='Lubefirst:BAAALgADCgYJBgAAAA==.Lucero:BAABLgAECn8VAAIZAAcJkRrBBQD/AQAZAAcJkRrBBQD/AQAAAA==.Lupii:BAAALgAECgcJBQAAAA==.Luxun:BAAALgAFFAIJAgAAAA==.',
Ma='Mabey:BAAALgAECgEJAQAAAA==.Maerron:BAABLgAECn8XAAMIAAcJsgbcOgAbAQAIAAcJsgbcOgAbAQAEAAYJiAbjEADgAAAAAA==.Mageblprows:BAAALgADCgYJDgAAAA==.Magness:BAAALgAECgMJAwAAAA==.Maiday:BAAALgAECgMJAwAAAA==.Mailescort:BAAALgAECgEJAQAAAA==.Makiavelik:BAAALgADCgcJBwAAAA==.Martireaper:BAAALgADCgUJBQAAAA==.Mastachißoyd:BAAALgAECgUJCAAAAA==.Matikz:BAACLgAFFH8OAAINAAUJQBkSBAAvAQANAAUJQBkSBAAvAQAuAAQKfyMAAw0ACQmoHTAJAP0CAA0ACQmoHTAJAP0CAA4ABAlEDh0GALkAAAAA.Mauradin:BAAALgADCgcJCgAAAA==.Mayachampion:BAAALgAECgcJDgAAAA==.Maylla:BAAALgADCgQJBAAAAA==.',
Me='Meddle:BAACLgAFFH8UAAMEAAUJ2R9fAADQAQAEAAUJ2R9fAADQAQADAAEJUQDYHAArAAAuAAQKfyYAAgQACQmAJigAAN8DAAQACQmAJigAAN8DAAAA.Megarayquaza:BAAALgAECgYJBgAAAA==.Mehrunesd:BAAALgAECgQJDQAAAA==.Melictá:BAAALgAECgYJBgAAAA==.Melìcta:BAAALgADCgQJAwABLgAECgYJBgABAAAAAA==.Mep:BAAALgADCgYJCgAAAA==.Merenkor:BAAALgADCgQJBAAAAA==.Merthulion:BAAALgAECgMJBQAAAA==.Meyea:BAABLgAECn8oAAILAAkJFyPtBwBgAwALAAkJFyPtBwBgAwABLgAFFAIJAwABAAAAAA==.',
Mh='Mhega:BAAALgAECgcJEQAAAA==.',
Mi='Miio:BAAALgADCgUJBAAAAA==.Mikuji:BAAALgAECgQJBwAAAA==.Miller:BAAALgAECgYJEgAAAA==.Mingsui:BAAALgADCgQJBwAAAA==.Mirra:BAACLgAFFH8FAAIFAAMJTBQiDAD+AAAFAAMJTBQiDAD+AAAuAAQKfyEAAgUACAl6IWEPAAQDAAUACAl6IWEPAAQDAAAA.Miru:BAAALgAECgYJEAAAAA==.Mizadra:BAABLgAECn8fAAMVAAgJahFZBwB8AQAVAAgJpBBZBwB8AQAWAAQJeRH+JwDgAAAAAA==.Mizdems:BAAALgADCgYJCwAAAA==.',
Ml='Mlindeli:BAAALgAECgEJAQABLgAECgcJEwABAAAAAA==.',
Mo='Moistjustice:BAAALgAECgIJAgAAAA==.Monning:BAAALgAFFAIJBAAAAA==.Moonfun:BAAALgAECgUJCAABLgAECggJEQABAAAAAA==.Moonskin:BAAALgAECgEJAQAAAA==.Mothric:BAAALgAECgYJBQAAAA==.',
My='Mynados:BAAALgADCgQJBAAAAA==.Myronoriss:BAAALgAECgYJCwABLgAECgcJEgABAAAAAA==.Mysticfate:BAAALgAFFAIJBAAAAA==.Mythicfritz:BAABLgAECn8WAAIFAAgJfQ8KVACnAQAFAAgJfQ8KVACnAQAAAA==.',
['Mé']='Mércy:BAABLgAECn8ZAAIYAAYJhhwFPAC0AQAYAAYJhhwFPAC0AQAAAA==.',
Na='Nahboo:BAABLgAECn8fAAIeAAgJsQ+8AwCGAQAeAAgJsQ+8AwCGAQAAAA==.Nakbu:BAAALgAECgYJEAAAAA==.Nani:BAABLgAECn8UAAMfAAgJcBElGACZAQAfAAcJ7xMlGACZAQALAAcJOgpGjQBmAQAAAA==.',
Ne='Necksus:BAAALgAECgYJEQAAAA==.Necridfashiz:BAAALgAECgQJBQAAAA==.Neinzen:BAAALgAECgEJAQAAAA==.Nemsy:BAAALgAECgYJBgAAAA==.Neralya:BAAALgADCgMJAwAAAA==.Neroth:BAAALgAFFAIJAgAAAA==.',
Ni='Niall:BAAALgAECgYJEAAAAA==.Nivai:BAAALgADCggJEAAAAA==.Nivix:BAAALgADCgEJAQABLgAECgcJDQABAAAAAA==.',
No='Nogardz:BAAALgAECgcJDwAAAA==.Nogi:BAAALgAECgMJAwAAAA==.Noi:BAAALgAECgYJDgAAAA==.Norot:BAAALgADCgQJBAAAAA==.Notpetya:BAAALgAECgMJBQAAAA==.Nottills:BAAALgAECgQJBAAAAA==.Nox:BAAALgAECgMJBAAAAA==.',
Nu='Nuulruk:BAAALgAECgEJAQAAAA==.',
Ny='Nyvix:BAAALgAECgUJCAABLgAECgcJDQABAAAAAA==.',
['Nä']='Näla:BAAALgADCgUJBQAAAA==.',
Oa='Oathbreakër:BAAALgADCgQJAwAAAA==.',
Of='Offline:BAAALgAECgQJBAAAAA==.',
Ol='Oligoclase:BAAALgAECgEJAQAAAA==.',
Om='Ombrure:BAAALgAECgIJAgAAAA==.',
On='Onornu:BAACLgAFFH8OAAIUAAUJEx+YAADeAQAUAAUJEx+YAADeAQAuAAQKfykAAxQACQnaI7ABAHcDABQACQnaI7ABAHcDABwAAQlKCk8oADQAAAAA.Onyxondra:BAAALgADCgEJAQAAAA==.',
Op='Ophiir:BAAALgAECgYJDwAAAA==.',
Or='Orlidan:BAABLgAECn8eAAIjAAgJaB9mBADAAgAjAAgJaB9mBADAAgAAAA==.Orlireloaded:BAAALgADCgUJBQABLgAECggJHgAjAGgfAA==.',
Ox='Oxycut:BAABLgAECn8ZAAIbAAYJLyNDCwBbAgAbAAYJLyNDCwBbAgAAAA==.',
Pa='Paramorevil:BAAALgADCggJFgAAAA==.Parodia:BAABLgAECn8cAAMFAAgJLBKHFQBRAQAFAAcJDRSHFQBRAQAQAAEJ5Aa5awA6AAAAAA==.',
Pe='Peka:BAABLgAFFH8GAAIUAAMJFQ95EADkAAAUAAMJFQ95EADkAAABLgAFFAUJEgAiAPIWAA==.Pekapow:BAACLgAFFH8SAAIiAAUJ8hYSBACpAQAiAAUJ8hYSBACpAQAuAAQKfx8AAyIACQkcIokCAGEDACIACQkcIokCAGEDACAAAQlnEp8dAEEAAAAA.',
Ph='Phearsome:BAAALgADCgcJBwAAAA==.Phobius:BAACLgAFFH8FAAILAAMJIgjXEADuAAALAAMJIgjXEADuAAAuAAQKfyEAAwsACAk6GbI4AFQCAAsACAk6GbI4AFQCAB8AAgkiCZBDADsAAAAA.',
Pi='Pigbumper:BAABLgAECn8kAAMaAAgJdCRJAACwAgAaAAgJQyRJAACwAgAFAAQJBiNpfAAzAQAAAA==.Pilihp:BAAALgAECgYJEgAAAA==.Pinkmango:BAAALgADCgkJCQABLgAFFAMJBQAEAPIWAA==.Pippapjappin:BAAALgAECgYJEQAAAA==.Pireyne:BAAALgADCgcJEwAAAA==.Pistachioz:BAAALgADCgUJBQAAAA==.',
Pl='Plaguetaco:BAABLgAECn8eAAILAAcJNgaTqwAqAQALAAcJNgaTqwAqAQAAAA==.Plz:BAAALgADCgkJCQABLgAFFAMJBQAFAEwUAA==.',
Po='Polymorphine:BAAALgAECgEJAgABLgAECgYJBgABAAAAAA==.Pooinashoe:BAAALgAECgEJAQABLgAECgYJCAABAAAAAA==.Pooky:BAABLgAECn8VAAIJAAcJCA9DNgBjAQAJAAcJCA9DNgBjAQAAAA==.Poonzer:BAABLgAECn8oAAIHAAkJ1SGyCgA6AwAHAAkJ1SGyCgA6AwAAAA==.Popebenedikt:BAAALgAECgIJAgAAAA==.Popkwizz:BAAALgADCgMJAwAAAA==.Porosity:BAABLgAECn8gAAMcAAgJzAv2DwALAQAcAAcJFwn2DwALAQAUAAEJVgGEMQAlAAAAAA==.Pouches:BAAALgADCgMJAwAAAA==.',
Pr='Prescripts:BAAALgADCgMJAwAAAA==.Prisscus:BAAALgADCgcJEwAAAA==.Proudclod:BAAALgAECgcJEwAAAA==.Pruning:BAAALgAECgEJAQABLgAECgUJBQABAAAAAA==.Pruningz:BAAALgADCgMJAwABLgAECgUJBQABAAAAAA==.',
Pu='Puffjiggly:BAAALgAECgYJEAAAAA==.',
Py='Pynk:BAAALgAECgMJBQAAAA==.Pyridon:BAAALgADCgcJBwAAAA==.Pyriena:BAAALgAECgYJBgAAAA==.',
Qe='Qetesh:BAABLgAECn8YAAITAAYJvBvMAQCWAQATAAYJvBvMAQCWAQAAAA==.',
Ra='Rabidfire:BAAALgADCgQJBAAAAA==.Rableman:BAABLgAECn8YAAIiAAgJFhjRBQC7AQAiAAgJFhjRBQC7AQAAAA==.Ragnár:BAAALgAECgIJAgAAAA==.Railzz:BAAALgADCgEJAQAAAA==.Rain:BAABLgAECn8bAAIiAAgJkQ1lCgBGAQAiAAgJkQ1lCgBGAQAAAA==.Raktavira:BAAALgAECgEJAQAAAA==.Ralinis:BAAALgAECgMJCQAAAA==.Rasson:BAAALgADCgcJBwAAAA==.Rathi:BAAALgAECgQJCQABLgAECgYJCAABAAAAAA==.Ravarox:BAABLgAECn8nAAQJAAkJ8B0VAQCTAgAJAAkJ8B0VAQCTAgAlAAIJqAcCLwBPAAAhAAEJBQTAOQATAAAAAA==.Ravicavasar:BAAALgAECgEJAQAAAA==.Rawwr:BAAALgAECgYJEwAAAA==.Raynesong:BAAALgADCgYJBgAAAA==.Razfu:BAAALgADCgkJCQAAAA==.Razul:BAACLgAFFH8FAAINAAMJmhYaBQAWAQANAAMJmhYaBQAWAQAuAAQKfyEAAg0ACAncH0kIAAwDAA0ACAncH0kIAAwDAAAA.',
Re='Redharvest:BAABLgAECn8ZAAIFAAcJSBq5DQChAQAFAAcJSBq5DQChAQAAAA==.Relentless:BAAALgAECgYJCwAAAA==.Relosaurus:BAAALgADCgEJAQAAAA==.Reportmypie:BAAALgADCgMJAwAAAA==.Restnpiece:BAAALgAECgQJCQAAAA==.',
Rh='Rhownin:BAAALgAECgYJDAABLgAFFAUJDgACAFIDAA==.',
Ri='Rishal:BAAALgADCgMJAwABLgAECgYJCgABAAAAAA==.Rispy:BAAALgAECgMJAwAAAA==.',
Rk='Rkoo:BAAALgAECgYJDQAAAA==.',
Ro='Rob:BAAALgAECgEJAQAAAA==.Robstinks:BAAALgAECgEJAQAAAA==.Rotambo:BAAALgADCgEJAQAAAA==.Royok:BAABLgAECn8cAAIbAAgJZB0/CgBxAgAbAAgJZB0/CgBxAgAAAA==.Royork:BAAALgADCgcJBwABLgAECggJHAAbAGQdAA==.',
Ru='Rudania:BAAALgAECgUJBQAAAA==.',
Ry='Rymjerb:BAAALgAECgYJCQAAAA==.',
['Rë']='Rënd:BAAALgADCgMJAwAAAA==.',
Sa='Sabarr:BAAALgADCgMJAwAAAA==.Saberwulf:BAAALgAECgYJDAAAAA==.Sabrewolf:BAAALgAECgEJAgAAAA==.Sabroen:BAAALgADCgYJBgABLgAECgQJDQABAAAAAA==.Sacfusious:BAAALgAECgYJEwAAAA==.Saendnueds:BAAALgAECgUJBQAAAA==.Sakardi:BAAALgAECgIJAgAAAA==.Sannta:BAAALgADCgcJDAAAAA==.Sawedoff:BAABLgAECn8hAAMkAAgJER65AgB0AgAkAAgJER65AgB0AgAXAAYJ5xKFQwBIAQAAAA==.Sazeon:BAABLgAECn8WAAIFAAcJaRLOGAA6AQAFAAcJaRLOGAA6AQAAAA==.',
Sc='Scamall:BAECLgAFFH8UAAIYAAUJuCa/AAA/AgAYAAUJuCa/AAA/AgAuAAQKfykAAhgACQnFJhkAAPsDABgACQnFJhkAAPsDAAAA.Schizophreni:BAABLgAFFH8FAAIKAAIJtRi0GQCwAAAKAAIJtRi0GQCwAAABLgAFFAUJEAAIAOYhAA==.Schokowitz:BAAALgAECgUJDwAAAA==.Scionoffury:BAAALgAECgEJAQAAAA==.Scorpeon:BAAALgAECgEJAQAAAA==.Scotcolumbus:BAABLgAECn8WAAIjAAgJjSHOAgD9AgAjAAgJjSHOAgD9AgAAAA==.',
Se='Sefu:BAAALgADCgUJBQAAAA==.Seraius:BAAALgAECgYJEAAAAA==.Seresis:BAACLgAFFH8NAAILAAQJnhPeGQA+AQALAAQJnhPeGQA+AQAuAAQKfyYAAgsACQnCIwsOACsDAAsACQnCIwsOACsDAAAA.Sero:BAAALgADCgcJBgAAAA==.',
Sh='Shaankspec:BAAALgAECgYJEQAAAA==.Shade:BAACLgAFFH8FAAINAAMJkAnUBgDpAAANAAMJkAnUBgDpAAAuAAQKfyAAAw0ACAlDFJkaAC0CAA0ACAmlEpkaAC0CAA4AAQlsDkYdAEEAAAAA.Shadoewolfe:BAAALgAECgMJAwAAAA==.Shadowbindr:BAAALgAECgEJAgAAAA==.Shadowfallz:BAAALgAECggJEQAAAA==.Shageron:BAACLgAFFH8PAAMXAAQJ5ReuDQBHAQAXAAQJ5ReuDQBHAQAkAAIJCwcSEACZAAAuAAQKfygAAhcACQkIIh8FAEwDABcACQkIIh8FAEwDAAAA.Shagmeblind:BAAALgAECgYJCgAAAA==.Shammwoww:BAAALgADCgcJGQAAAA==.Shampóóp:BAAALgAECgQJBQAAAA==.Shandoe:BAAALgADCgIJAgAAAA==.Shankspec:BAACLgAFFH8KAAIOAAUJfw/DAAC+AQAOAAUJfw/DAAC+AQAuAAQKfycAAw4ACQliIZoAAG4DAA4ACQliIZoAAG4DAA0AAQkfGKNbAEYAAAAA.Shayu:BAAALgADCgYJCgAAAA==.Shifthappens:BAAALgAECgEJAQABLgAECgkJHQAZAF0gAA==.Shikaca:BAAALgADCggJEgAAAA==.Shinseina:BAABLgAECn8dAAMHAAgJ4RpqMgBZAgAHAAgJ4RpqMgBZAgAZAAQJkBTnZQDkAAAAAA==.Shivx:BAAALgAECgIJAgAAAA==.Shockdh:BAAALgADCgkJCQABLgAFFAMJBQAJALAFAA==.Shoeboo:BAAALgADCgcJCQAAAA==.Shoriuken:BAAALgADCgcJCgAAAA==.Shämash:BAABLgAECn8YAAIRAAgJXhEvDQDLAQARAAgJXhEvDQDLAQAAAA==.Shízz:BAAALgADCgkJDQAAAA==.',
Si='Sicc:BAAALgADCgIJAgAAAA==.Siccness:BAAALgAECgYJDwAAAA==.Sieben:BAAALgAECgEJAgAAAA==.Siella:BAABLgAECn8UAAIEAAgJhQ1FBwCXAQAEAAgJhQ1FBwCXAQAAAA==.Sileve:BAAALgADCgcJDAABLgAECgYJEAABAAAAAA==.Silive:BAAALgADCgYJCQABLgAECgYJEAABAAAAAA==.Sindrex:BAACLgAFFH8FAAIGAAMJgR+sBAAVAQAGAAMJgR+sBAAVAQAuAAQKfyEAAgYACAlvJGsCAEwDAAYACAlvJGsCAEwDAAEuAAMKBQkFAAEAAAAA.Sinestus:BAABLgAECn8dAAIjAAgJrCCOAwDgAgAjAAgJrCCOAwDgAgAAAA==.',
Sk='Skoody:BAAALgAECgIJAwAAAA==.Skrrt:BAAALgAECgQJBQAAAA==.Skwerl:BAAALgAECgUJCgAAAA==.',
Sl='Slick:BAAALgAECgYJCgAAAA==.Slickarus:BAABLgAECn8dAAMVAAgJnCISBgAhAwAVAAgJICISBgAhAwAWAAQJeB03IAAsAQAAAA==.Slumdawg:BAAALgADCgcJDAAAAA==.Slurmage:BAABLgAECn8gAAIKAAgJXSBMBgBKAgAKAAgJXSBMBgBKAgAAAA==.',
Sm='Smittywerben:BAAALgADCgUJBQAAAA==.Smooshi:BAACLgAFFH8IAAIUAAMJhRS8BwDZAAAUAAMJhRS8BwDZAAAuAAQKfy0AAhQACAlpI/oHAPUCABQACAlpI/oHAPUCAAAA.',
Sn='Snoke:BAAALgAECgEJAgAAAA==.',
So='Soleirel:BAAALgAECgQJCQAAAA==.Solfury:BAAALgADCgMJAwAAAA==.Solidjen:BAABLgAFFH8FAAIHAAMJfAeMEQCYAAAHAAMJfAeMEQCYAAAAAA==.Soulfiend:BAAALgAECgEJAQAAAA==.',
Sp='Sparklefarts:BAAALgADCgYJCgAAAA==.Sparks:BAAALgAFFAEJAQAAAA==.Speedlings:BAACLgAFFH8LAAINAAQJXxYJAgBwAQANAAQJXxYJAgBwAQAuAAQKfyYAAg0ACAm0IRUOAL4CAA0ACAm0IRUOAL4CAAAA.Spicedale:BAAALgAECgUJBgAAAA==.',
Sq='Squiggles:BAAALgAECgEJAQAAAA==.',
St='Star:BAAALgAECgcJCQAAAA==.Starfun:BAAALgAECgYJBgABLgAECggJEQABAAAAAA==.Stealthven:BAAALgAECgQJBAAAAA==.Stenzwar:BAAALgAFFAIJAwAAAA==.Stiq:BAACLgAFFH8EAAISAAMJqySGEQDlAAASAAMJqySGEQDlAAAuAAQKfyAAAhIACAmkJYsFAGMDABIACAmkJYsFAGMDAAAA.Stlux:BAAALgAECgYJBwAAAA==.Stojkette:BAAALgAECgYJEQAAAA==.Stormbless:BAABLgAECn8eAAIdAAgJkRIPCAB3AQAdAAgJkRIPCAB3AQAAAA==.Storminmycup:BAAALgAECgQJBgABLgAFFAUJEAAcAMgaAA==.',
Su='Sulzire:BAAALgADCgQJAwAAAA==.Sumx:BAAALgAFFAMJAwAAAA==.Superarrows:BAAALgADCgQJBAAAAA==.Supersquirel:BAAALgADCgQJBgAAAA==.Superstabs:BAAALgADCgMJAwAAAA==.',
Sw='Sweeger:BAABLgAECn8dAAMUAAcJhxghDQBsAQAUAAcJhxghDQBsAQAcAAEJDBbZJABCAAAAAA==.Sweegie:BAAALgADCgYJBgAAAA==.Sweetlou:BAAALgADCgYJDAAAAA==.',
Sy='Syds:BAAALgAECgYJEQAAAA==.Sylaraa:BAAALgAECgcJEQAAAA==.Synapticzion:BAAALgAECgYJCQAAAA==.Synatra:BAAALgADCgcJEQAAAA==.Syndra:BAAALgADCgEJAQABLgADCgUJBQABAAAAAA==.',
['Sí']='Sílk:BAAALgAECgEJAQAAAA==.',
Ta='Taara:BAABLgAECn8iAAIeAAgJCSOqAAB2AgAeAAgJCSOqAAB2AgAAAA==.Taarat:BAAALgAECgIJAgABLgAECggJIgAeAAkjAA==.Tacobelf:BAAALgAECgQJBAAAAA==.Takkana:BAAALgADCgYJBgAAAA==.Tanneleer:BAAALgAECgEJAQAAAA==.Tarzo:BAAALgAECgEJAQAAAA==.Taucetiluna:BAAALgADCgYJBgAAAA==.Tazzyshmurda:BAAALgAECggJCAAAAA==.',
Tc='Tchaikovsky:BAAALgADCgQJBAAAAA==.',
Te='Tehdazzler:BAAALgADCgMJAwAAAA==.Tehdymare:BAAALgADCgYJBgAAAA==.Tehrains:BAAALgAECgEJAQAAAA==.Telenn:BAAALgAECgQJDQAAAA==.Terk:BAACLgAFFH8OAAIeAAUJqCGYAADRAQAeAAUJqCGYAADRAQAuAAQKfyYAAx4ACQlYJjQAAN0DAB4ACQlYJjQAAN0DABQAAQllBFKcADUAAAAA.Termina:BAAALgAECgYJEQAAAA==.',
Th='Thaatguy:BAAALgADCgEJAQAAAA==.Thalrymere:BAABLgAECn8fAAIXAAgJ8xkOAgDCAQAXAAgJ8xkOAgDCAQAAAA==.Thanirn:BAAALgAECgEJAQAAAA==.Thiccerlegs:BAAALgAECgYJEAAAAA==.Thiccwnr:BAAALgAECgUJCwAAAA==.Thiccycheeks:BAACLgAFFH8HAAIFAAIJWxYLJgCnAAAFAAIJWxYLJgCnAAAuAAQKfxUAAgUABwmmIfEcAKQCAAUABwmmIfEcAKQCAAAA.',
Ti='Ticklock:BAAALgADCgcJCAAAAA==.Tidelizard:BAACLgAFFH8LAAIGAAUJdw/rBQCWAQAGAAUJdw/rBQCWAQAuAAQKfx0AAgYACQmHHKQHAMMCAAYACQmHHKQHAMMCAAAA.Tigolbittys:BAAALgAECgYJDwAAAA==.Tikz:BAABLgAECn8fAAISAAgJdhB5EACOAQASAAgJdhB5EACOAQAAAA==.Tills:BAAALgADCgcJDgABLgAECgQJBAABAAAAAA==.Tinycomp:BAAALgADCgIJAgAAAA==.',
To='Tock:BAABLgAECn8ZAAIeAAkJ2xw/AgAtAwAeAAkJ2xw/AgAtAwAAAA==.Tockella:BAAALgADCgQJBAABLgAECgkJGQAeANscAA==.Toe:BAAALgADCgcJDAAAAA==.Tokenwarrior:BAAALgAECgQJBwAAAA==.Tokodomo:BAAALgAECgYJBgABLgAECggJIgALABshAA==.Torvï:BAAALgAECgMJBQAAAA==.',
Tr='Tralina:BAAALgADCgQJBQABLgAFFAUJDgAKABIcAA==.Trapstâr:BAABLgAFFH8FAAIXAAMJ1REYFQDzAAAXAAMJ1REYFQDzAAAAAA==.Treechicken:BAAALgAECgYJDAAAAA==.Tricky:BAABLgAECn8UAAMFAAcJVB+qJwBlAgAFAAcJjx6qJwBlAgAQAAMJ1xyFSADRAAAAAA==.Trill:BAACLgAFFH8IAAINAAQJqxEXAwBYAQANAAQJqxEXAwBYAQAuAAQKfyMAAg0ACAlMJFgGACsDAA0ACAlMJFgGACsDAAAA.Tripotley:BAAALgAECgQJBAAAAA==.Trivalence:BAAALgAECgUJDgAAAA==.Truegrit:BAAALgADCgUJBQAAAA==.Trëspin:BAAALgAECgEJAQAAAA==.',
Ts='Tsarfun:BAAALgAECgYJDAABLgAECggJEQABAAAAAA==.Tseon:BAAALgADCgcJCwABLgAECggJIQAkABEeAA==.',
Tu='Tuor:BAAALgAECgQJBQAAAA==.Turaco:BAAALgADCgIJAgABLgAECggJGwARAEYLAA==.',
Tw='Twizzurp:BAAALgAECgEJAQAAAA==.',
Ty='Tywin:BAAALgADCgcJCgAAAA==.Tyèll:BAAALgAECgcJEgAAAA==.',
['Tá']='Tái:BAAALgAECgYJDQAAAA==.',
Uj='Ujio:BAAALgAECgQJBQAAAA==.',
Un='Undeadwaifu:BAAALgADCgQJBAAAAA==.',
Up='Upmysleeves:BAAALgAFFAIJAwAAAA==.',
Va='Vance:BAAALgAECgQJBAAAAA==.Vaughn:BAACLgAFFH8OAAICAAUJfA3BBQCVAQACAAUJfA3BBQCVAQAuAAQKfyIAAgIACAl2G6wVAKACAAIACAl2G6wVAKACAAAA.Vaust:BAAALgAECgMJAwAAAA==.',
Ve='Vedekur:BAAALgADCgIJAgAAAA==.Veggieboi:BAABLgAECn8jAAMSAAgJSB32EwDdAgASAAgJSB32EwDdAgATAAEJAABXYwBIAAAAAA==.Vellast:BAAALgAECgMJAwAAAA==.Velocathyr:BAAALgAECggJEwAAAA==.Venthunt:BAABLgAECn8fAAQXAAkJ3BvGDwC+AgAXAAkJtRvGDwC+AgAmAAYJRB5PFQByAQAkAAMJDyPSZQA2AQABLgAFFAIJAwABAAAAAA==.Verellia:BAAALgAECgYJDgAAAA==.',
Vi='Victory:BAABLgAECn8WAAIZAAcJDCEfFwBZAgAZAAcJDCEfFwBZAgAAAA==.Vigilo:BAACLgAFFH8MAAIgAAQJLB5GAwBuAQAgAAQJLB5GAwBuAQAuAAQKfyMAAiAACQlmIzYCAH8DACAACQlmIzYCAH8DAAAA.Vilhelmina:BAAALgAECgYJCwAAAA==.Viruzdk:BAABLgAECn8eAAMLAAcJdCEyTgAIAgALAAcJeB8yTgAIAgAfAAQJoB9nIABBAQAAAA==.',
Vo='Voidwalker:BAABLgAECn8VAAIFAAgJfBYSYQB+AQAFAAgJfBYSYQB+AQAAAA==.Voidwench:BAABLgAECn8aAAIFAAcJDR2OFQBRAQAFAAcJDR2OFQBRAQAAAA==.Volrog:BAACLgAFFH8JAAIeAAQJ3A4sAgBLAQAeAAQJ3A4sAgBLAQAuAAQKfyUAAh4ACAl8JLwBAEkDAB4ACAl8JLwBAEkDAAAA.Vosduo:BAAALgAECgMJAwAAAA==.',
Vr='Vritarah:BAAALgADCgcJCQAAAA==.',
Wa='Wafio:BAAALgADCgQJBAABLgAECgIJAgABAAAAAA==.Warcheif:BAABLgAECn8UAAIkAAUJiQoCcwAOAQAkAAUJiQoCcwAOAQAAAA==.Warwonka:BAACLgAFFH8FAAIXAAMJZRFuAwD0AAAXAAMJZRFuAwD0AAAuAAQKfyEAAhcACAnkGS4YAGgCABcACAnkGS4YAGgCAAAA.Warzan:BAAALgAECgEJAQAAAA==.Watchurbeard:BAABLgAECn8eAAImAAgJCBOaBQB4AQAmAAgJCBOaBQB4AQAAAA==.Waviowi:BAAALgAECgYJDgAAAA==.',
We='Weatherdwarf:BAABLgAECn8YAAIUAAgJ0QkkEABAAQAUAAgJ0QkkEABAAQAAAA==.',
Wh='Whammer:BAAALgAECggJEQAAAA==.Whiiplash:BAAALgADCgUJBQAAAA==.Whooped:BAAALgAECgUJBQABLgAECgcJHAAiAH8aAA==.Whysolittle:BAAALgADCgUJBQAAAA==.',
Wi='Windfûrry:BAAALgAECgUJCwABLgAECgcJFQAHAPIgAA==.',
Wl='Wlntercamo:BAAALgAECgUJDgAAAA==.',
Wr='Wrapfire:BAAALgAECgUJCQAAAA==.Wrapps:BAAALgAECgIJAgAAAA==.',
Xe='Xeroxed:BAABLgAECn8cAAILAAgJRRl7DAC9AQALAAgJRRl7DAC9AQAAAA==.',
Xi='Xiangmei:BAAALgAECgYJDQAAAA==.',
Xo='Xon:BAAALgADCgQJBAAAAA==.',
Ya='Yacob:BAACLgAFFH8OAAIKAAUJLyI2BgD9AQAKAAUJLyI2BgD9AQAuAAQKfyYAAgoACQnpJcoCANIDAAoACQnpJcoCANIDAAAA.Yamarahj:BAACLgAFFH8FAAMMAAIJzAZUAQBeAAASAAIJ4AUpPACaAAAMAAEJowZUAQBeAAAuAAQKfyAABAwACQm5GoYIAMEBABIABwmgGH5LAOcBAAwABQnrHIYIAMEBABMABAkJEo4uAAEBAAAA.',
Ye='Yenna:BAAALgADCgEJAQABLgADCgMJBAABAAAAAA==.',
Yo='Yorikk:BAABLgAECn8UAAMTAAgJxQ1+FACnAQATAAgJfgx+FACnAQASAAUJZwpHrAAAAQAAAA==.Youngtwerk:BAAALgAECgUJBwAAAA==.',
Za='Zaeleane:BAAALgAECgYJDwAAAA==.Zanrak:BAAALgADCgYJCAABLgAECgQJCwABAAAAAA==.Zard:BAAALgAECgYJCgAAAA==.Zardrelin:BAAALgADCgYJBgABLgADCgYJBwABAAAAAA==.Zareynne:BAAALgAECgcJEgAAAA==.Zarmaku:BAAALgADCgYJBgAAAA==.Zathyr:BAAALgADCgQJBAAAAA==.Zauber:BAACLgAFFH8PAAQSAAUJBSV8AwDqAQASAAUJziN8AwDqAQAMAAEJuSFzAwBfAAATAAEJ+ByBEgBaAAAuAAQKfycABBIACQmAJogAAOEDABIACQk8JogAAOEDAAwABwmvJtEAABgDABMABwmLI4QGAGYCAAAA.Zazie:BAABLgAECn8cAAMaAAgJfRahAgB4AQAaAAgJdBahAgB4AQAFAAEJVRuQ4QAwAAAAAA==.Zazu:BAAALgAECgEJAQAAAA==.',
Ze='Zelani:BAAALgAECgQJBAAAAA==.Zensei:BAAALgADCgYJDQAAAA==.',
Zi='Zirraj:BAACLgAFFH8KAAICAAQJOR6nCQBaAQACAAQJOR6nCQBaAQAuAAQKfyUAAwIACQlrIq4FAEwDAAIACQlrIq4FAEwDABEAAQm1IG8PAGAAAAAA.',
Zm='Zmaj:BAAALgAECgEJAQAAAA==.',
Zn='Zn:BAAALgADCgYJCwAAAA==.',
Zo='Zocalo:BAAALgAECgYJBwABLgAFFAQJDAAgACweAA==.Zodiac:BAAALgAFFAEJAQABLgAECgcJHgAhAIcmAA==.Zorø:BAABLgAECn8gAAIaAAgJTQ0BDQCIAQAaAAgJTQ0BDQCIAQAAAA==.Zovinox:BAAALgAECgIJAgAAAA==.',
Zu='Zulrok:BAAALgADCgYJBgAAAA==.Zurk:BAAALgADCgEJAwAAAA==.',
Zy='Zygon:BAAALgAECgEJAQABLgAECgcJHgAhAIcmAA==.',
['Ãr']='Ãrthz:BAAALgAECgUJCQAAAA==.',
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
