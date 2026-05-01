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

local lookup = {'Shaman-Elemental','Warrior-Fury','Warlock-Destruction','Priest-Discipline','Priest-Holy','Monk-Brewmaster','DemonHunter-Devourer','Evoker-Preservation','Hunter-BeastMastery','Paladin-Retribution','Priest-Shadow','Evoker-Augmentation','Unknown-Unknown','Druid-Balance','Mage-Frost','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Blood','Warlock-Demonology','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','DemonHunter-Havoc','Warrior-Arms','Shaman-Restoration','Evoker-Devastation','Hunter-Marksmanship','Druid-Restoration','Warrior-Protection','Hunter-Survival','Paladin-Holy','DemonHunter-Vengeance','Shaman-Enhancement','Monk-Windwalker','Druid-Guardian','Monk-Mistweaver','Paladin-Protection','Druid-Feral','Warlock-Affliction',}
local provider = {region='US',realm='Magtheridon',name='US',type='weekly',zone=46,date='2026-05-01',data={Ad='Adayssa:BAAALgADCgUJBQAAAA==.',
Ag='Agave:BAAALgAECgUJCgAAAA==.',
Ai='Aimwee:BAAALgAECgYJEQAAAA==.Aiur:BAAALgADCgkJIgAAAA==.',
Ak='Akunzed:BAAALgADCgEJAQAAAA==.',
Al='Alaena:BAAALgADCgYJBgAAAA==.Alandivyn:BAAALgAECgMJBAAAAA==.Alarm:BAAALgADCgYJBgABLgAECgYJFgABAF4gAA==.Alcuard:BAAALgAECgYJCAAAAA==.Alesce:BAACLgAFFH8SAAICAAUJnAnXCABiAQACAAUJnAnXCABiAQAuAAQKfyYAAgIACQk6GuwSALcCAAIACQk6GuwSALcCAAAA.Alii:BAAALgAECgMJBQAAAA==.Alisinchains:BAAALgADCgcJCQAAAA==.',
Am='Amarauku:BAABLgAECn8YAAIDAAcJKBKiBwA4AQADAAcJKBKiBwA4AQAAAA==.Amenadiel:BAABLgAECn8aAAMEAAcJpCHyDQBbAgAEAAcJpCHyDQBbAgAFAAEJ4gpOfwAzAAAAAA==.America:BAAALgADCgYJCAAAAA==.Amyntas:BAAALgAECgMJBQAAAA==.Amythistle:BAABLgAECn8WAAIGAAYJvB0NEACTAQAGAAYJvB0NEACTAQAAAA==.',
An='Andrü:BAABLgAECn8lAAICAAgJJR8RBACHAgACAAgJJR8RBACHAgAAAA==.Andy:BAAALgAECgcJEgAAAA==.Anguscon:BAAALgADCgMJAwAAAA==.Anol:BAAALgAECgUJBQABLgAFFAYJEAAHAFojAA==.Antihero:BAAALgAFFAMJAwAAAA==.Antioch:BAAALgADCgkJIgAAAA==.',
Ar='Archael:BAAALgAECgYJDgAAAA==.Archimainos:BAABLgAECn8aAAIIAAcJTRZYFQD1AQAIAAcJTRZYFQD1AQAAAA==.Argorok:BAAALgAECgYJEQAAAA==.Argôroth:BAAALgADCgYJBgAAAA==.Arthz:BAAALgADCgcJBwAAAA==.',
As='Asheeus:BAABLgAECn8UAAIJAAgJ+BOYRwCTAQAJAAgJ+BOYRwCTAQAAAA==.Ashtana:BAAALgADCgMJAwAAAA==.Ashtar:BAABLgAECn8mAAIKAAgJWRhNHgDUAQAKAAgJWRhNHgDUAQAAAA==.Assiasins:BAAALgAECgEJAQAAAA==.Asterok:BAAALgAECgYJDAAAAA==.Astravianda:BAAALgAECgUJBQAAAA==.Aszune:BAAALgADCgUJBQAAAA==.',
At='Atheria:BAECLgAFFH8GAAILAAMJHxJXCwAAAQALAAMJHxJXCwAAAQAuAAQKfxkAAgsACAk0HPgRAGsCAAsACAk0HPgRAGsCAAAA.Athetaz:BAAALgAECgEJAQAAAA==.',
Au='Auggers:BAABLgAFFH8FAAMIAAIJ3hYkEQCwAAAIAAIJ3hYkEQCwAAAMAAEJwwjmKgBNAAAAAA==.Augthyr:BAAALgAECgQJCAABLgAFFAIJAgANAAAAAA==.',
Av='Avalen:BAABLgAECn8eAAIOAAcJHyN4DQDCAgAOAAcJHyN4DQDCAgAAAA==.Avarich:BAAALgAECgQJBAAAAA==.Avez:BAAALgADCgkJLQAAAA==.Aviee:BAACLgAFFH8IAAIPAAMJPCILJwA2AQAPAAMJPCILJwA2AQAuAAQKfxsAAg8ABwlaH7hFAGcCAA8ABwlaH7hFAGcCAAAA.Avishun:BAAALgAECgYJCgAAAA==.Avreel:BAABLgAECn8ZAAMQAAYJYReOBwCJAQAQAAYJYReOBwCJAQAPAAEJqA8qYwE9AAAAAA==.',
Az='Azazi:BAACLgAFFH8TAAIPAAUJPCNeDgCGAQAPAAUJPCNeDgCGAQAuAAQKfysAAg8ACQnCJEcDAMsDAA8ACQnCJEcDAMsDAAAA.Azonia:BAAALgADCgYJDAAAAA==.Azushi:BAAALgAECgYJDAABLgAECggJIwACADwcAA==.',
Ba='Babymage:BAACLgAFFH8IAAIPAAMJ5gvhNwD0AAAPAAMJ5gvhNwD0AAAuAAQKfzAAAg8ACQkyG8sJAKICAA8ACQkyG8sJAKICAAAA.Badform:BAAALgAECgEJAQAAAA==.Badkitteh:BAAALgAECgQJBQAAAA==.Baelstrom:BAAALgAFFAMJAwAAAA==.Baendron:BAABLgAECn8fAAMRAAkJwBjqPgA8AgARAAkJORfqPgA8AgASAAQJpxB0GwCfAAAAAA==.Bahnna:BAABLgAECn8bAAMEAAYJqhpfDADEAQAEAAYJqhpfDADEAQAFAAIJSwvkcQBfAAAAAA==.Bananana:BAAALgADCgcJBwAAAA==.Barbarik:BAAALgAECgUJBQABLgAFFAMJCQATAIUPAA==.Barberry:BAAALgAECgEJAQABLgAECgEJAQANAAAAAA==.Baretwallace:BAAALgAECgQJBAABLgAFFAIJAgANAAAAAA==.',
Be='Beardsmite:BAEALgAECgcJEgABLgAECgIJAgANAAAAAA==.Beerbeeotch:BAAALgADCgcJDQAAAA==.Beerus:BAAALgAECgYJEgAAAA==.Bellawaifu:BAAALgAECgYJBgAAAA==.Bellaynia:BAAALgADCgcJDQAAAA==.Belmuerto:BAAALgAECgYJDAAAAA==.Benzopatrol:BAAALgAECgQJCAAAAA==.Besnel:BAAALgAECgQJBwAAAA==.',
Bi='Bigtuna:BAAALgADCgIJAgAAAA==.',
Bl='Blackbolt:BAAALgADCgMJAwAAAA==.Blackhaus:BAAALgADCgYJBgAAAA==.Blixxy:BAAALgADCgQJBAAAAA==.Blorgin:BAACLgAFFH8RAAMUAAYJGRngBwBpAQAUAAUJJBjgBwBpAQAVAAIJlRaTAwDBAAAuAAQKfyUABBQACQlVI5ICAIADABQACQn7IpICAIADABUAAglsI1QLAMgAABYAAQlgABAQABcAAAAA.Bluntmàn:BAAALgAECgMJAwAAAA==.Bléssed:BAAALgAECgEJAwAAAA==.',
Bo='Boinky:BAABLgAECn8XAAIJAAYJSA5wOgApAQAJAAYJSA5wOgApAQAAAA==.Boneham:BAAALgAECgQJBAAAAA==.Bookers:BAABLgAECn8iAAIXAAgJJxIjHADfAQAXAAgJJxIjHADfAQAAAA==.Booplzs:BAABLgAECn8mAAIPAAgJxhrgFAA0AgAPAAgJxhrgFAA0AgAAAA==.Borgo:BAAALgADCgkJDwABLgAECgkJJgAPAHgWAA==.Boulangerie:BAACLgAFFH8UAAILAAYJvB/KAgDJAQALAAYJvB/KAgDJAQAuAAQKfygAAgsACQnAJhsAAAsEAAsACQnAJhsAAAsEAAAA.Boulezen:BAAALgAECgEJAgAAAA==.Boulidan:BAAALgAECgYJEAAAAA==.Boulior:BAAALgADCgcJEgAAAA==.Bounceonit:BAAALgAFFAEJAQAAAA==.Boyd:BAACLgAFFH8PAAICAAUJtRYBCQBgAQACAAUJtRYBCQBgAQAuAAQKfyQAAwIACAkNHekbAG4CAAIACAkNHekbAG4CABgAAQklCT5EADAAAAAA.',
Br='Breeding:BAAALgAECgcJDQABLgAFFAIJBQAGACEdAA==.Brent:BAAALgADCgUJBQAAAA==.Brewm:BAAALgAECgMJAwAAAA==.Brewmungandr:BAABLgAECn8VAAIGAAYJIhl9EwBsAQAGAAYJIhl9EwBsAQAAAA==.Brightnight:BAAALgADCgEJAQABLgAECgYJEAANAAAAAA==.Brinner:BAAALgADCgYJBgAAAA==.Brokenbone:BAAALgAECgUJCgAAAA==.Bromayzo:BAAALgAECgYJCQAAAA==.Brujo:BAAALgADCgcJDgAAAA==.Brylen:BAAALgAECgYJBwAAAA==.',
Bu='Budweis:BAAALgADCgIJAgAAAA==.Bullkkake:BAAALgAECgIJAwAAAA==.Bumii:BAAALgAFFAIJAgAAAA==.',
By='Byfryasbeard:BAAALgADCgcJEwAAAA==.',
Ca='Canadatrash:BAAALgADCgcJBwABLgAFFAIJAgANAAAAAA==.Carltonbanks:BAAALgAECgcJBwAAAA==.Cashewz:BAAALgAECggJDwAAAA==.Casterella:BAAALgADCgEJAQAAAA==.Caylithia:BAABLgAECn8ZAAIRAAcJkxASNQBlAQARAAcJkxASNQBlAQAAAA==.',
Ce='Ceasarsalad:BAABLgAECn8kAAMDAAkJpgp9FgCWAQADAAgJfwt9FgCWAQATAAgJVAlrYwDKAAAAAA==.Ceazitt:BAAALgADCgcJBwABLgAECggJFgAPAA0XAA==.Ceazyweasley:BAABLgAECn8WAAIPAAgJDReFJADVAQAPAAgJDReFJADVAQAAAA==.Ceci:BAAALgAFFAMJAwAAAA==.Celestriå:BAABLgAECn8ZAAMDAAYJ+BLPBwA0AQADAAYJ+BLPBwA0AQATAAMJkgfg+wBiAAAAAA==.Cernnuunnos:BAAALgADCgUJBQAAAA==.Cetana:BAAALgADCgUJBQABLgAFFAIJAgANAAAAAA==.',
Ch='Chadlockb:BAACLgAFFH8YAAITAAYJLSLDAQD2AQATAAYJLSLDAQD2AQAuAAQKfy4AAxMACQkfJOUCAPwCABMACQkfJOUCAPwCAAMAAwkwFAQ5ANAAAAAA.Cheesee:BAABLgAECn8hAAIZAAgJLCHjCADoAgAZAAgJLCHjCADoAgAAAA==.Christlike:BAAALgADCgYJBwAAAA==.Chronite:BAABLgAECn8mAAIPAAkJeBZBEQBSAgAPAAkJeBZBEQBSAgAAAA==.Chuffy:BAAALgAECgYJDAAAAA==.',
Ci='Cindr:BAACLgAFFH8PAAIMAAYJxx/FAwDfAQAMAAYJxx/FAwDfAQAuAAQKfyYAAwwACQlHJqMAAN0DAAwACQlHJqMAAN0DABoABwnvG9cNAPwBAAAA.Circumstance:BAACLgAFFH8JAAMFAAQJ1AfZCAALAQAFAAQJ1AfZCAALAQAEAAIJvAMDFgCCAAAuAAQKfzQABAUACQkiHXMFAPgCAAUACQmTG3MFAPgCAAQACQlnGfMDAJoCAAsAAgmbDU9VAG0AAAAA.Cirice:BAAALgADCgIJAwAAAA==.',
Cl='Claylock:BAABLgAECn8kAAITAAgJaR4VCQB8AgATAAgJaR4VCQB8AgAAAA==.Cleattus:BAABLgAECn8XAAMTAAgJcwy1KgCCAQATAAgJcwy1KgCCAQADAAEJcQWeeQApAAAAAA==.Cleric:BAAALgAECgQJBAAAAA==.',
Co='Coarseblood:BAAALgADCgcJGwAAAA==.Cody:BAACLgAFFH8OAAILAAUJsyMYAgClAQALAAUJsyMYAgClAQAuAAQKfyUAAgsACQnPJYgBALEDAAsACQnPJYgBALEDAAAA.Codyh:BAAALgAECgYJBgAAAA==.Codyp:BAAALgAECgYJBgAAAA==.Colddblooded:BAAALgAECgQJCAAAAA==.Coldoyazda:BAAALgAECgEJAQAAAA==.Cololol:BAACLgAFFH8QAAIHAAYJWiPuBADeAQAHAAYJWiPuBADeAQAuAAQKfzoAAwcACQnQJdYAANwDAAcACQnQJdYAANwDABcAAwmzHXdJAMwAAAAA.Conjurous:BAAALgADCgYJCQABLgAECgQJBQANAAAAAA==.Cooper:BAABLgAECn8lAAIbAAgJvCOwAADZAgAbAAgJvCOwAADZAgAAAA==.Corbis:BAAALgADCgYJBgABLgAECgYJFQAcADwgAA==.Corruptica:BAAALgADCggJEAAAAA==.Cosmos:BAABLgAECn8lAAIcAAgJ5B2TBgCtAgAcAAgJ5B2TBgCtAgAAAA==.Cowlvlislie:BAAALgAECgUJBQAAAA==.',
Cr='Creami:BAAALgADCgEJBAAAAA==.Creastos:BAAALgAECgEJBAAAAA==.Crew:BAACLgAFFH8RAAIXAAUJ6x8DAgB5AQAXAAUJ6x8DAgB5AQAuAAQKfysAAhcACQkPJOEBAH8DABcACQkPJOEBAH8DAAAA.Crispy:BAAALgAECgEJAgAAAA==.Cronozret:BAAALgADCgEJAQAAAA==.',
Cu='Cucokai:BAABLgAECn8dAAIZAAgJpx7SBwBuAgAZAAgJpx7SBwBuAgAAAA==.Cuddlekaren:BAABLgAECn8ZAAMLAAcJbxeFDAC4AQALAAcJbxeFDAC4AQAFAAIJPhFFbgBuAAABLgAFFAYJEgAbAJMTAA==.Cuddlestomp:BAACLgAFFH8SAAIbAAYJkxOQCQCAAQAbAAYJkxOQCQCAAQAuAAQKfyYAAhsACQkVJOIDAGQDABsACQkVJOIDAGQDAAAA.',
['Cä']='Cämulos:BAABLgAECn8YAAIdAAcJTBKsEQALAQAdAAcJTBKsEQALAQAAAA==.',
['Cí']='Círí:BAEBLgAECn8VAAQbAAcJTSWEHgAvAgAbAAcJQx6EHgAvAgAJAAUJ4SW7OgDDAQAeAAEJJiODLABCAAABLgAECgIJAgANAAAAAA==.',
Da='Dabudtanka:BAAALgAECgEJAQAAAA==.Dacat:BAAALgAECgQJBAAAAA==.Daddylongleg:BAAALgADCgEJAQAAAA==.Daenleran:BAAALgADCggJCAAAAA==.Damnhammer:BAABLgAFFH8IAAIfAAMJeRTCEQDoAAAfAAMJeRTCEQDoAAAAAA==.Dandie:BAAALgAECgIJAgAAAA==.Dantalian:BAABLgAECn8YAAMEAAcJ/hExJAByAQAEAAcJYBExJAByAQAFAAQJ/QupKgCpAAABLgAFFAUJDwAPALEeAA==.Darthimu:BAAALgAECgEJAQABLgAECggJHQAPAP0UAA==.Darthmerlin:BAABLgAECn8dAAIPAAgJ/RSTLACyAQAPAAgJ/RSTLACyAQAAAA==.Darthpanda:BAAALgADCgMJAgABLgAECggJHQAPAP0UAA==.Darthsanguis:BAAALgADCgEJAQABLgAECggJHQAPAP0UAA==.Darthvaper:BAAALgADCgEJAQAAAA==.Dasakko:BAACLgAFFH8IAAIFAAMJth3dCAAKAQAFAAMJth3dCAAKAQAuAAQKfy8AAwUACQmhIYIAAHQDAAUACQmhIYIAAHQDAAsAAQlKB3NCADMAAAAA.Dasmonko:BAAALgAECgEJAQABLgAFFAMJCAAFALYdAA==.',
Db='Dbowz:BAAALgAECgUJBQAAAA==.',
De='Deathbeeotch:BAABLgAECn8aAAIRAAcJagt5UgAKAQARAAcJagt5UgAKAQAAAA==.Deathcaller:BAAALgAECgYJDwAAAA==.Deblacksheep:BAAALgADCgMJAwABLgAECgYJGAAfAAolAA==.Deliscera:BAAALgADCgYJBgAAAA==.Delithsong:BAAALgADCggJCAAAAA==.Demonhunterl:BAAALgAECgYJEgAAAA==.Demonishall:BAAALgAECgIJBQAAAA==.Demontim:BAABLgAECn8UAAIXAAgJFBuvBAAvAgAXAAgJFBuvBAAvAgAAAA==.Denjin:BAAALgADCgEJAgAAAA==.Destile:BAAALgAECgQJBAABLgAECgcJFAAHAIUZAA==.Dethe:BAAALgAECgQJCwAAAA==.Dewme:BAAALgADCgYJBgAAAA==.',
Dh='Dhbowz:BAACLgAFFH8MAAIHAAUJwB7aCABxAQAHAAUJwB7aCABxAQAuAAQKfyAAAwcACAkKJJwUANwCAAcACAnfIpwUANwCACAAAgkJI8QZAMgAAAAA.',
Di='Dinkyfu:BAAALgADCggJAgAAAA==.Dipndots:BAAALgADCgYJBgAAAA==.',
Dn='Dnok:BAAALgADCgEJAQAAAA==.',
Do='Doc:BAAALgAECgYJBgAAAA==.Doguntarth:BAABLgAECn8jAAICAAgJPBzXBQBaAgACAAgJPBzXBQBaAgAAAA==.Domerneth:BAAALgAECgUJDwAAAA==.Doomfury:BAAALgAECgcJEQAAAA==.Dotsfired:BAAALgAECgYJBwABLgAECgYJGQAdAC8jAA==.Doylescars:BAAALgADCgIJAgAAAA==.',
Dr='Dragonboi:BAAALgAECgYJBgAAAA==.Dragonbutt:BAAALgAECgMJAwAAAA==.Dragson:BAAALgADCgEJAQAAAA==.Drakkarus:BAAALgAECgUJDQAAAA==.Drankincup:BAACLgAFFH8SAAIBAAYJVRvYAQDQAQABAAYJVRvYAQDQAQAuAAQKfzQAAgEACQkCI5UCAL4CAAEACQkCI5UCAL4CAAAA.Drchinstraps:BAAALgADCgIJAwAAAA==.Dreamscape:BAAALgAECgUJBQAAAA==.Drstagger:BAECLgAFFH8FAAIGAAIJSSYUEwDgAAAGAAIJSSYUEwDgAAAuAAQKfyMAAgYACAkVJtsBAIcDAAYACAkVJtsBAIcDAAAA.',
Du='Duskflower:BAACLgAFFH8QAAIcAAUJKhWUBwCHAQAcAAUJKhWUBwCHAQAuAAQKfyoAAhwACQnvG9kZAGoCABwACQnvG9kZAGoCAAAA.',
Eb='Ebonessences:BAAALgAECgEJAQAAAA==.',
Ec='Echochaser:BAAALgADCggJDgAAAA==.Eclaire:BAAALgADCgYJBgAAAA==.',
Ed='Eddard:BAAALgADCgYJCwAAAA==.',
Ej='Eject:BAAALgAECgQJBQAAAA==.',
El='Elexandur:BAABLgAECn8dAAIhAAgJDRyKAwAPAgAhAAgJDRyKAwAPAgAAAA==.Ellenarna:BAAALgAECgUJBwAAAA==.Elleri:BAABLgAECn8ZAAIKAAgJyA9QKAChAQAKAAgJyA9QKAChAQAAAA==.Ellyse:BAAALgAECgEJAQAAAA==.',
En='Entrøpy:BAABLgAECn8XAAIKAAgJ5B8eLgBqAgAKAAgJ5B8eLgBqAgABLgAFFAIJAgANAAAAAA==.',
Ep='Epnodk:BAAALgAFFAEJAgABLgAFFAQJEgAGAJYZAA==.Epnokicks:BAACLgAFFH8SAAIGAAQJlhl2CABUAQAGAAQJlhl2CABUAQAuAAQKfysAAgYACQmpIkgDAGADAAYACQmpIkgDAGADAAAA.Epnopal:BAAALgADCgMJAwABLgAFFAQJEgAGAJYZAA==.',
Er='Eroicel:BAAALgAECgMJAwABLgAFFAUJFAASAHMSAA==.',
Ev='Evarielle:BAACLgAFFH8UAAISAAUJcxJ9CQADAQASAAUJcxJ9CQADAQAuAAQKfzEAAhIACQmcHogFAOcCABIACQmcHogFAOcCAAAA.Evelis:BAAALgAECgYJEQAAAA==.Evilina:BAAALgADCgIJAwAAAA==.Evillmaster:BAAALgADCgUJCgAAAA==.',
Fa='Fadedhalo:BAAALgAECgQJCQAAAA==.Falaya:BAACLgAFFH8TAAMDAAUJOx+2AACQAQADAAUJOx+2AACQAQATAAIJSR44LAC+AAAuAAQKfysAAwMACQmHJDkBACADAAMACAkhIjkBACADABMABgmbIONFAPkBAAAA.Fallinorion:BAAALgADCgYJBgAAAA==.Fancy:BAAALgAECgYJCgAAAA==.Farion:BAAALgAECgUJCwAAAA==.',
Fe='Fearlite:BAAALgAECgEJAQAAAA==.Feldoyle:BAAALgAECgQJBQAAAA==.Felel:BAAALgADCgEJAQAAAA==.Felfi:BAAALgAECgIJAgAAAA==.Felroc:BAAALgAECgEJAQAAAA==.Fenix:BAABLgAECn8UAAIdAAcJ8xsIBwDVAQAdAAcJ8xsIBwDVAQAAAA==.Fersos:BAABLgAECn8ZAAIKAAgJOQqtjwBcAQAKAAgJOQqtjwBcAQAAAA==.',
Fi='Firefaux:BAAALgAECgQJBAAAAA==.',
Fl='Flawlessxi:BAAALgAECgYJCwAAAA==.Flyntflosy:BAACLgAFFH8TAAIBAAUJzBb2CABGAQABAAUJzBb2CABGAQAuAAQKfysAAgEACQmpH6IFADsDAAEACQmpH6IFADsDAAAA.',
Fo='Fowl:BAAALgAECgQJBAABLgAECgkJHgAYANIKAA==.Foxreich:BAABLgAECn8ZAAIJAAcJZhY4NQDZAQAJAAcJZhY4NQDZAQAAAA==.',
Fr='Fragment:BAABLgAECn8VAAMSAAcJ/xK+DABEAQASAAcJ/xK+DABEAQARAAMJIwpIdgCyAAAAAA==.Frozoevoko:BAAALgAECgQJBgAAAA==.',
Fu='Fungame:BAAALgAECgIJAgAAAA==.Funstar:BAAALgAECgYJCwABLgAECggJFQAZAEMLAA==.Furyess:BAAALgAECgEJAgAAAA==.',
['Fé']='Félicity:BAEALgAECgIJAgAAAA==.',
['Fî']='Fîrebolt:BAAALgADCgMJAwAAAA==.',
Ga='Gaelsi:BAABLgAECn8cAAMiAAgJbB/NBABZAgAiAAgJbB/NBABZAgAGAAEJPBWHiwAuAAAAAA==.Galactic:BAAALgADCgkJCQABLgAFFAIJBgAjAH4mAA==.Galgore:BAABLgAECn8UAAIfAAgJkAsQOQCWAQAfAAgJkAsQOQCWAQAAAA==.Ganvvitch:BAAALgAECgEJAQAAAA==.Garolok:BAABLgAECn8kAAIYAAgJ0xu8BQB6AgAYAAgJ0xu8BQB6AgAAAA==.Gartiss:BAAALgAECgQJCwAAAA==.Gate:BAAALgADCggJIQAAAA==.Gazelle:BAEBLgAECn8lAAIGAAgJixZzCwDSAQAGAAgJixZzCwDSAQAAAA==.Gazerakhan:BAAALgADCgcJDAABLgAECggJIgAHAFsVAA==.Gazerielle:BAABLgAECn8iAAQHAAgJWxWLRgDZAQAHAAgJ1xSLRgDZAQAgAAYJuBSBEABJAQAXAAEJsAc3eAAsAAAAAA==.Gazerizard:BAAALgADCgQJBAABLgAECggJIgAHAFsVAA==.',
Gh='Gherthquakes:BAAALgADCgIJAgAAAA==.',
Gi='Ginsoda:BAAALgADCgcJCwAAAA==.Ginthril:BAAALgAECgIJAwABLgAECgcJFQASAHQkAA==.Ginwine:BAABLgAFFH8IAAMfAAMJ4yWCCQBUAQAfAAMJ4yWCCQBUAQAKAAEJ4h9ELABhAAABLgAFFAYJEwATAEcjAA==.Gitzsum:BAAALgADCgUJBQAAAA==.',
Gl='Glizzylizzy:BAACLgAFFH8IAAIhAAMJhCToAgDTAAAhAAMJhCToAgDTAAAuAAQKfykAAiEACQnEIjwAADwDACEACQnEIjwAADwDAAAA.',
Gn='Gnaeus:BAAALgAECgMJBQAAAA==.',
Go='Goldilockes:BAAALgAECgIJAgAAAA==.Gorca:BAAALgAECgEJAQABLgAECgEJAQANAAAAAA==.Gothbaddie:BAAALgADCgEJAQAAAA==.Gourmando:BAAALgADCgYJDAABLgAECgEJAQANAAAAAA==.Gowownage:BAACLgAFFH8GAAIjAAIJfibBAgDgAAAjAAIJfibBAgDgAAAuAAQKfykAAiMACAmfJCQBAJoCACMACAmfJCQBAJoCAAAA.',
Gr='Gradius:BAACLgAFFH8KAAMSAAUJtRkXBQBPAQASAAUJtRkXBQBPAQARAAEJnQs8bwBQAAAuAAQKfyMAAxEACQmtHLIpAJMCABEACQlVHLIpAJMCABIABwmpFgAoAP4AAAAA.Granddh:BAAALgAECgEJAQAAAA==.Grandmage:BAABLgAECn8VAAIPAAgJFBF7ewDaAQAPAAgJFBF7ewDaAQAAAA==.Graydius:BAAALgAFFAEJAQAAAA==.Greenpanda:BAABLgAECn8bAAIGAAgJjhZkEQCDAQAGAAgJjhZkEQCDAQAAAA==.Greenwarrior:BAAALgAECgYJCQAAAA==.Greydeus:BAAALgAFFAIJAgABLgAFFAUJCgASALUZAA==.Grimeclipse:BAAALgAECgYJEQAAAA==.Groves:BAAALgAECgUJCgABLgAECgkJJwAkAHsYAA==.Grumple:BAAALgADCgEJAQAAAA==.Grumpoo:BAAALgAECgUJCgAAAA==.',
Gu='Gurt:BAABLgAECn8aAAMCAAgJaw4bQwCYAQACAAgJjg0bQwCYAQAYAAYJUQrdFwC7AAAAAA==.Gurtok:BAAALgAECgcJBwAAAA==.',
['Gø']='Gøøn:BAABLgAECn8aAAIPAAgJwBYtUABHAgAPAAgJwBYtUABHAgAAAA==.',
Ha='Halestorm:BAABLgAECn8XAAIKAAYJMghHWwAAAQAKAAYJMghHWwAAAQAAAA==.Halfachuby:BAAALgAECgEJAQAAAA==.Halfmast:BAAALgAECgEJAQABLgAFFAMJCgAHANIdAA==.Halk:BAACLgAFFH8SAAIKAAYJ0hwZAgDJAQAKAAYJ0hwZAgDJAQAuAAQKfyYAAgoACQkmJO0GAGEDAAoACQkmJO0GAGEDAAAA.Haonao:BAAALgADCgYJCwAAAA==.Harris:BAAALgAFFAIJBAABLgAFFAYJFAALALwfAA==.Havefun:BAABLgAECn8VAAMZAAgJQwsoPwCEAQAZAAgJQwsoPwCEAQABAAQJeQwxOQCJAAAAAA==.',
He='Hedonist:BAAALgAECggJEgABLgAFFAMJCQATAIUPAA==.Hellquack:BAABLgAECn8eAAQYAAkJ0go4GAA3AQAYAAkJ2gg4GAA3AQAdAAUJMgsULQDZAAACAAMJOQVmjQCJAAAAAA==.Hellsbringer:BAABLgAECn8WAAIHAAcJyRbvLQAsAQAHAAcJyRbvLQAsAQAAAA==.Hellzard:BAAALgADCgYJBwAAAA==.Hermito:BAAALgAECgUJBQAAAA==.',
Ho='Hollowed:BAAALgAECgQJBAAAAA==.Holycandi:BAAALgAECgIJBAAAAA==.Holydoyle:BAABLgAECn8VAAIlAAYJ/SNWBAAGAgAlAAYJ/SNWBAAGAgAAAA==.Holytrident:BAABLgAECn8VAAIPAAYJkxFy3gA2AQAPAAYJkxFy3gA2AQAAAA==.Homelessman:BAAALgAECgYJBgAAAA==.Hotpøcket:BAACLgAFFH8MAAIcAAQJGQ+9EwD9AAAcAAQJGQ+9EwD9AAAuAAQKfyAAAxwACQncHbYLAOICABwACQncHbYLAOICAA4AAQnGFUt7ADsAAAAA.Hottz:BAAALgAECgYJBQAAAA==.',
Hu='Hugebowels:BAAALgAECgMJBAABLgAECggJGwAVAGQUAA==.Hugefeet:BAABLgAECn8bAAMVAAgJZBQBBgAfAgAVAAcJLhcBBgAfAgAWAAUJPwUlBwDZAAAAAA==.Humorous:BAAALgAECgYJEAAAAA==.',
Hy='Hyperìen:BAACLgAFFH8WAAIlAAYJ7SIiAADzAQAlAAYJ7SIiAADzAQAuAAQKfyMAAiUACQnaJEYAALIDACUACQnaJEYAALIDAAAA.',
Ic='Icanmoonu:BAAALgAECgQJCgAAAA==.Icedoggi:BAABLgAECn8bAAMjAAgJshpKBgCZAQAjAAcJsxlKBgCZAQAmAAMJGRL+EADIAAAAAA==.',
Il='Illzilla:BAAALgADCgcJFAAAAA==.',
Im='Immortalmage:BAAALgAECgUJBgAAAA==.Imnosuperman:BAAALgAECgEJAQAAAA==.Imsopro:BAAALgADCgIJAgAAAA==.',
In='Inferna:BAAALgADCgcJBgAAAA==.Inferno:BAAALgADCgcJCgAAAA==.Intiq:BAAALgADCgkJDwAAAA==.Invisibul:BAAALgAECgQJBQAAAA==.',
Ip='Ipmanz:BAAALgAECgIJAwAAAA==.',
Ir='Irbaboon:BAAALgAECgQJBQABLgAECgYJCAANAAAAAA==.Irreletaur:BAACLgAFFH8NAAICAAUJXhVwEQD8AAACAAUJXhVwEQD8AAAuAAQKfycAAgIACAk2IJoYAIcCAAIACAk2IJoYAIcCAAAA.',
Is='Isitovernow:BAAALgADCgkJDQABLgAECgYJGAAfAAolAA==.Ismitethee:BAAALgADCgcJDQAAAA==.',
It='Ithilwen:BAAALgADCgEJAQAAAA==.Itsovernow:BAABLgAECn8YAAIfAAYJCiVwFgBeAgAfAAYJCiVwFgBeAgAAAA==.Itzqt:BAAALgADCgcJEQAAAA==.',
Iz='Izimir:BAABLgAECn8WAAIfAAgJLBlYJwDwAQAfAAgJLBlYJwDwAQAAAA==.',
Ja='Jackiechàn:BAAALgAECgUJBgABLgAFFAIJAgANAAAAAA==.Jacosta:BAABLgAECn8nAAIPAAgJxRpyFwAhAgAPAAgJxRpyFwAhAgAAAA==.Jadeazul:BAAALgADCgcJCAAAAA==.Jadis:BAABLgAECn8QAAIHAAYJvwoEQQDjAAAHAAYJvwoEQQDjAAAAAA==.Jamgirl:BAABLgAECn8VAAISAAcJdCTMBgDHAgASAAcJdCTMBgDHAgAAAA==.Jampu:BAAALgADCgEJAQAAAA==.Jangokin:BAACLgAFFH8RAAIOAAUJPhPsBwBiAQAOAAUJPhPsBwBiAQAuAAQKfyYAAg4ACQl0IcoEAFQDAA4ACQl0IcoEAFQDAAAA.Jaskvoid:BAABLgAECn8TAAIHAAcJNATFUAC0AAAHAAcJNATFUAC0AAAAAA==.Jasminepesto:BAAALgADCgkJDgAAAA==.Jatloo:BAAALgADCgQJBAABLgAECgQJCwANAAAAAA==.Jaysis:BAABLgAECn8UAAIHAAcJhRlZGgCXAQAHAAcJhRlZGgCXAQAAAA==.',
Je='Jermz:BAAALgAECgQJBgAAAA==.',
Jg='Jgrass:BAAALgAECgcJEwAAAA==.',
Ji='Jimba:BAACLgAFFH8IAAIJAAMJbhllFwAJAQAJAAMJbhllFwAJAQAuAAQKfy4AAgkACQmgH2IDANQCAAkACQmgH2IDANQCAAAA.Jinks:BAAALgAECgQJBgAAAA==.',
Jo='Joelrobuchon:BAAALgAECgIJAgAAAA==.Jorin:BAAALgADCgMJAwAAAA==.Jorres:BAAALgADCgMJAwAAAA==.Joslynn:BAAALgAECgIJAgAAAA==.Joytoy:BAAALgAECgQJBAAAAA==.',
Ju='Judgments:BAAALgAECgYJEQAAAA==.Jumalauta:BAAALgAECgYJEAAAAA==.Junglejooce:BAAALgADCgYJBgAAAA==.',
['Jè']='Jèrmz:BAAALgADCgEJAQAAAA==.',
['Jí']='Jím:BAAALgAECgcJEwAAAA==.',
Ka='Kabang:BAAALgAECgQJBAAAAA==.Kabonk:BAAALgADCggJCAABLgAECgQJBAANAAAAAA==.Kaelstryna:BAAALgADCgQJBAAAAA==.Kaer:BAAALgAECgQJBAABLgAECgYJCAANAAAAAA==.Kaerbear:BAAALgADCgcJBwAAAA==.Kaige:BAAALgAECgUJDQAAAA==.Kala:BAAALgAECgYJCgAAAA==.Kalithor:BAAALgAECgcJDgAAAA==.Kalrodomes:BAAALgAECgYJBgAAAA==.Kasey:BAAALgAECgEJAQAAAA==.Kathery:BAAALgAECgQJCgAAAA==.Kathoes:BAAALgAECgQJCQAAAA==.Kazen:BAAALgAECgQJCwAAAA==.Kazhunter:BAAALgADCgYJBgAAAA==.',
Ke='Keili:BAAALgAECgEJAQAAAA==.Kellandron:BAAALgADCgkJCAAAAA==.Kellwildfire:BAABLgAECn8jAAMCAAgJvA1xHwA4AQACAAcJ3Q9xHwA4AQAdAAgJVwOzEwDxAAAAAA==.Kethrin:BAAALgADCgYJBgAAAA==.',
Kh='Khamael:BAACLgAFFH8PAAIPAAUJsR7ZEgB0AQAPAAUJsR7ZEgB0AQAuAAQKfysAAg8ACQk9JI4JAHkDAA8ACQk9JI4JAHkDAAAA.Kheiron:BAACLgAFFH8HAAMJAAMJ5hntFAAWAQAJAAMJ5hntFAAWAQAbAAIJUwuyHgCbAAAuAAQKfxYAAxsACAnmHnMcAEECABsACAnFHXMcAEECAAkAAwn1H8c+ABoBAAAA.',
Ki='Kilimanjaro:BAAALgADCgkJDgABLgAECgIJBAANAAAAAA==.Kinu:BAABLgAECn8qAAIZAAkJYh10AgD9AgAZAAkJYh10AgD9AgAAAA==.Kitane:BAABLgAECn8XAAIiAAgJLxwSGAAjAgAiAAgJLxwSGAAjAgAAAA==.Kitsunibi:BAABLgAECn8cAAMOAAcJUxFbFgBNAQAOAAcJUxFbFgBNAQAcAAYJ8wYrewDnAAAAAA==.Kittyneko:BAAALgAECgYJDQAAAA==.',
Kl='Klump:BAAALgADCgEJAQAAAA==.',
Ko='Kobieta:BAABLgAFFH8FAAIcAAIJaxCyJACKAAAcAAIJaxCyJACKAAAAAA==.Kolei:BAAALgADCgQJBAAAAA==.Konica:BAABLgAECn8eAAMZAAgJlw/MPwCBAQAZAAgJlw/MPwCBAQABAAEJbQGXlwAYAAAAAA==.Kookykraving:BAAALgAECgYJCAAAAA==.Korgesh:BAAALgADCgkJFQAAAA==.Kotharsevant:BAAALgAECgEJAQAAAA==.',
Kr='Kraypoe:BAABLgAECn8aAAIHAAgJuAoeaABqAQAHAAgJuAoeaABqAQAAAA==.Kreepindeath:BAAALgAECgUJBQABLgAECggJGwABACIbAA==.Krondys:BAAALgAECgQJBAAAAA==.Krìeg:BAAALgAECgIJAgABLgAECgIJBAANAAAAAA==.',
Ku='Kurohail:BAAALgADCgYJBgABLgAECggJKAAdAD8kAA==.Kurolion:BAAALgAECgYJDAAAAA==.Kurosong:BAABLgAECn8oAAIdAAgJPyQiAQDbAgAdAAgJPyQiAQDbAgAAAA==.Kurzon:BAAALgAECgEJAQAAAA==.',
Kw='Kwanrbless:BAAALgAECgYJEwAAAA==.',
Ky='Kyblade:BAABLgAECn8lAAILAAgJUyMuAgC6AgALAAgJUyMuAgC6AgAAAA==.Kyogre:BAAALgAECgUJBgAAAA==.Kyrr:BAABLgAECn8XAAIUAAgJFhuEFwBNAgAUAAgJFhuEFwBNAgAAAA==.',
['Kù']='Kùrupt:BAAALgAECgYJBgABLgAFFAUJDQAUANUbAA==.',
La='Labombah:BAAALgADCgMJBgAAAA==.Ladrogue:BAAALgAECgcJCgAAAA==.Landdragon:BAAALgAECgIJAgAAAA==.Landslide:BAAALgAECgEJAgAAAA==.Lasaruz:BAABLgAECn8ZAAIGAAgJDARyHQAVAQAGAAgJDARyHQAVAQAAAA==.Lavajato:BAAALgADCgUJCAABLgADCgkJCgANAAAAAA==.',
Le='Leemius:BAAALgAECgQJBgAAAA==.Legionearth:BAAALgAECgMJBAAAAA==.Leosbryn:BAABLgAECn8cAAIDAAgJOhX+AgDNAQADAAgJOhX+AgDNAQAAAA==.Levie:BAAALgAECgYJDAAAAA==.',
Lh='Lhaxorp:BAABLgAECn8YAAMeAAcJChZxCwCqAQAeAAcJChZxCwCqAQAbAAMJzgdxbgCFAAABLgAECgkJKwAKANUhAA==.',
Li='Liable:BAAALgAECgMJAwABLgAECgYJFQAcADwgAA==.Lighthammer:BAAALgAECgYJDQABLgADCgMJAwANAAAAAA==.Liiadrin:BAAALgADCgIJAgAAAA==.Liltazzvert:BAAALgAECgUJBQAAAA==.Listerfyne:BAAALgAECgQJBwAAAA==.Lithariel:BAAALgAECgUJBgAAAA==.',
Lo='Loumis:BAAALgAECgQJDAAAAA==.',
Lu='Lubefirst:BAAALgADCgYJBgAAAA==.Lucero:BAABLgAECn8dAAIfAAgJ1BhBCwAiAgAfAAgJ1BhBCwAiAgAAAA==.Lupii:BAAALgAECgkJCgAAAA==.Luxun:BAAALgAFFAIJAgAAAA==.',
Ma='Mabey:BAAALgAECgMJBAAAAA==.Maerron:BAABLgAECn8eAAMFAAcJEwnVGwAnAQAFAAcJEwnVGwAnAQALAAcJsgbrOgAbAQAAAA==.Mageblprows:BAAALgADCggJFgAAAA==.Magness:BAAALgAECgMJAwAAAA==.Maiday:BAAALgAECgMJAwAAAA==.Mailescort:BAAALgAECgEJAQAAAA==.Makiavelik:BAAALgADCgcJBwAAAA==.Martireaper:BAAALgADCgUJBQAAAA==.Mastachißoyd:BAAALgAECgUJCAAAAA==.Matikz:BAACLgAFFH8SAAIUAAUJkB1wBAB2AQAUAAUJkB1wBAB2AQAuAAQKfyUAAxQACQliHjEJAP0CABQACQliHjEJAP0CABUABAlEDqoMAKsAAAAA.Mauradin:BAAALgADCgcJCgAAAA==.Mawdrin:BAAALgADCgYJCAAAAA==.Mayachampion:BAAALgAECgcJDwAAAA==.Maylla:BAAALgADCgQJBAAAAA==.',
Me='Meddle:BAACLgAFFH8aAAMFAAYJuCEwAABPAgAFAAYJuCEwAABPAgAEAAEJUQDbHAArAAAuAAQKfycAAgUACQmXJikAAN8DAAUACQmXJikAAN8DAAAA.Megarayquaza:BAAALgAECgYJBgAAAA==.Mehrunesd:BAAALgAECgQJDgAAAA==.Melictá:BAAALgAECgYJBgAAAA==.Melìcta:BAAALgADCgQJAwABLgAECgYJBgANAAAAAA==.Melínoë:BAAALgAECgEJAgAAAA==.Mep:BAAALgAECggJCAAAAA==.Merenkor:BAAALgADCgQJBAAAAA==.Merthulion:BAAALgAECgQJCQAAAA==.Meyea:BAACLgAFFH8IAAIRAAMJKiZGGwBJAQARAAMJKiZGGwBJAQAuAAQKfygAAhEACQkXI+wHAGADABEACQkXI+wHAGADAAAA.',
Mh='Mhega:BAAALgAECgcJEQAAAA==.',
Mi='Miio:BAAALgADCgUJBAAAAA==.Mikuji:BAAALgAECgQJBwAAAA==.Miller:BAABLgAECn8ZAAIJAAcJQCTVCQBfAgAJAAcJQCTVCQBfAgAAAA==.Mingsui:BAAALgADCgQJBwAAAA==.Mirra:BAACLgAFFH8IAAIHAAMJERqRGQAMAQAHAAMJERqRGQAMAQAuAAQKfy4AAgcACQnEIQUDAM4CAAcACQnEIQUDAM4CAAAA.Miru:BAABLgAECn8WAAIDAAYJOAetDADZAAADAAYJOAetDADZAAAAAA==.Mizadra:BAABLgAECn8jAAMMAAgJ7xFbEwBpAQAMAAgJKRFbEwBpAQAaAAQJeREHKADgAAAAAA==.Mizdems:BAAALgAECgIJAwAAAA==.',
Ml='Mlindeli:BAAALgAECgEJAQABLgAECggJGwAOAMgcAA==.',
Mo='Moistjustice:BAAALgAECgIJAgAAAA==.Monning:BAABLgAFFH8FAAIGAAIJIR3WHAC1AAAGAAIJIR3WHAC1AAAAAA==.Moonfun:BAAALgAECgUJCAABLgAECggJFQAZAEMLAA==.Moonskin:BAAALgAECgMJAwAAAA==.Mothric:BAAALgAECgYJBQAAAA==.',
My='Mynados:BAAALgADCgQJBAAAAA==.Myronoriss:BAAALgAECgcJDQABLgAECgcJEwANAAAAAA==.Mysticfate:BAABLgAECn8UAAIPAAcJsh5wFwAhAgAPAAcJsh5wFwAhAgAAAA==.Mythicfritz:BAABLgAECn8WAAIHAAgJfQ8LVACnAQAHAAgJfQ8LVACnAQAAAA==.',
['Mé']='Mércy:BAABLgAECn8iAAMcAAcJoxwsFgDSAQAcAAcJoxwsFgDSAQAOAAEJYgnhRgAyAAAAAA==.',
Na='Nahboo:BAABLgAECn8mAAIhAAgJjxDYBgCWAQAhAAgJjxDYBgCWAQAAAA==.Nakbu:BAABLgAECn8WAAISAAYJYAteFgDLAAASAAYJYAteFgDLAAAAAA==.Nandayo:BAAALgADCgIJAgAAAA==.Nani:BAABLgAECn8UAAMSAAgJcBEiGACZAQASAAcJ7xMiGACZAQARAAcJOgpCjQBmAQAAAA==.',
Ne='Neandratroll:BAAALgADCgQJBAAAAA==.Necksus:BAAALgAECgYJEQAAAA==.Necridfashiz:BAAALgAECgUJCgAAAA==.Neinzen:BAAALgAECgYJBwAAAA==.Nemsy:BAAALgAECggJDQAAAA==.Neralya:BAAALgADCgMJAwAAAA==.Neroth:BAAALgAFFAIJAgAAAA==.',
Ni='Niall:BAAALgAECgYJEAAAAA==.Nivai:BAAALgADCgkJFQAAAA==.Nivix:BAAALgADCgEJAQABLgAECggJDwANAAAAAA==.',
No='Nogardz:BAABLgAECn8YAAIKAAgJSRqQGQDxAQAKAAgJSRqQGQDxAQAAAA==.Nogi:BAAALgAECgMJAwAAAA==.Noi:BAAALgAECgYJDgAAAA==.Nojhelm:BAAALgAECgYJEQAAAA==.Norot:BAAALgADCgQJBAAAAA==.Notpetya:BAAALgAECgMJBwAAAA==.Nottills:BAAALgAECgQJBAAAAA==.Nox:BAAALgAECgMJBQAAAA==.',
Nu='Nuulruk:BAAALgAECgEJAQAAAA==.',
Ny='Nylaehh:BAAALgAECgEJAQAAAA==.Nyvix:BAAALgAECgUJCAABLgAECggJDwANAAAAAA==.',
Oa='Oathbreakër:BAAALgAECgIJAgAAAA==.',
Of='Offline:BAAALgAECgQJBAAAAA==.',
Ol='Oligoclase:BAAALgAECgEJAQAAAA==.',
Om='Ombrure:BAAALgAECgIJAgAAAA==.',
On='Onornu:BAACLgAFFH8SAAIZAAUJbSFmAQAFAgAZAAUJbSFmAQAFAgAuAAQKfywAAxkACQnaI68BAHcDABkACQnaI68BAHcDAAEAAQlKCkRTADAAAAAA.Onyxondra:BAAALgADCgEJAQAAAA==.',
Op='Ophiir:BAAALgAECgYJDwAAAA==.',
Or='Orlidan:BAABLgAECn8mAAIlAAgJJSJNAQCrAgAlAAgJJSJNAQCrAgAAAA==.Orlireloaded:BAAALgADCgcJDAABLgAECggJJgAlACUiAA==.',
Ox='Oxycut:BAABLgAECn8ZAAIdAAYJLyNCCwBbAgAdAAYJLyNCCwBbAgAAAA==.',
Pa='Pandabearian:BAAALgADCgEJAQAAAA==.Paramorevil:BAAALgADCggJFgAAAA==.Parodia:BAABLgAECn8lAAMHAAgJBRhlEQDjAQAHAAgJBRhlEQDjAQAXAAEJ5Aa2awA6AAAAAA==.',
Pe='Peka:BAABLgAFFH8GAAIZAAMJFQ+BEADkAAAZAAMJFQ+BEADkAAABLgAFFAYJGAAkAI8XAA==.Pekapeck:BAAALgAFFAMJAwAAAA==.Pekapow:BAACLgAFFH8YAAIkAAYJjxdYBAC8AQAkAAYJjxdYBAC8AQAuAAQKfx8AAyQACQkcIooCAGADACQACQkcIooCAGADACIAAQlnEpBBAEEAAAAA.',
Ph='Phearsome:BAAALgADCgcJBwAAAA==.Phobius:BAACLgAFFH8IAAIRAAMJFgz2OADrAAARAAMJFgz2OADrAAAuAAQKfy8AAxEACQnoHKQFAMgCABEACQnoHKQFAMgCABIAAgkiCY1DADsAAAAA.',
Pi='Pigbumper:BAABLgAECn8sAAMgAAgJdCSrAADJAgAgAAgJQySrAADJAgAHAAQJBiNofAAzAQAAAA==.Pilihp:BAABLgAECn8aAAICAAgJgwQ1KAACAQACAAgJgwQ1KAACAQAAAA==.Pinkmango:BAAALgADCgkJCQABLgAFFAMJCAAFALYdAA==.Pippapjappin:BAAALgAECgYJEQAAAA==.Pireyne:BAAALgAECgEJAQAAAA==.Pistachioz:BAAALgADCgUJBQAAAA==.',
Pl='Plaguetaco:BAABLgAECn8eAAIRAAcJQQbXZwDTAAARAAcJQQbXZwDTAAAAAA==.Plz:BAAALgAECgEJAQABLgAFFAMJCAAHABEaAA==.',
Po='Polymorphine:BAAALgAECgEJAgABLgAECgYJBgANAAAAAA==.Pontego:BAAALgADCgkJCQAAAA==.Pooinashoe:BAAALgAECgEJAQABLgAECgYJCAANAAAAAA==.Pooky:BAABLgAECn8XAAIOAAgJmQ5ANgBjAQAOAAgJmQ5ANgBjAQAAAA==.Poonzer:BAABLgAECn8rAAIKAAkJ1SG0CgA6AwAKAAkJ1SG0CgA6AwAAAA==.Popebenedikt:BAAALgAECgIJAgAAAA==.Popkwizz:BAAALgADCgMJAwAAAA==.Porosity:BAABLgAECn8iAAMBAAgJ3wsbIwAHAQABAAcJLAkbIwAHAQAZAAEJVgFVagAkAAAAAA==.Pouches:BAAALgADCgMJAwAAAA==.',
Pr='Prescripts:BAAALgADCgMJAwAAAA==.Prisscus:BAAALgADCgcJEwAAAA==.Proudclod:BAABLgAECn8bAAIOAAgJyBwZBwAnAgAOAAgJyBwZBwAnAgAAAA==.Prunes:BAAALgAECgYJBgAAAA==.Pruning:BAAALgAECgEJAQABLgAECgEJAQANAAAAAA==.Pruningz:BAAALgAECgEJAQABLgAECgEJAQANAAAAAA==.',
Pu='Puffjiggly:BAABLgAECn8RAAMHAAYJCxPKQQDhAAAHAAYJCxPKQQDhAAAgAAEJVgazLQApAAAAAA==.Purrfecto:BAAALgADCgIJAgAAAA==.',
Py='Pynk:BAAALgAECgMJBQAAAA==.Pyridon:BAAALgADCgcJBwAAAA==.Pyriena:BAAALgAECgYJBwAAAA==.',
Qe='Qetesh:BAABLgAECn8YAAIDAAYJvBuKBACPAQADAAYJvBuKBACPAQAAAA==.',
Ra='Rabidfire:BAAALgAECgEJAQAAAA==.Rableman:BAABLgAECn8gAAIkAAgJkxvVBwA8AgAkAAgJkxvVBwA8AgAAAA==.Ragnár:BAAALgAECgMJAwAAAA==.Railzz:BAAALgADCgEJAQAAAA==.Rain:BAABLgAECn8kAAIkAAgJrA++EgCEAQAkAAgJrA++EgCEAQAAAA==.Raktavira:BAAALgAECgEJAwAAAA==.Ralinis:BAAALgAECgMJCQAAAA==.Rasson:BAAALgADCgcJBwAAAA==.Rathi:BAAALgAECgQJCQABLgAECgYJCAANAAAAAA==.Ravarox:BAABLgAECn8qAAQOAAkJ8h2aAwCSAgAOAAkJ8h2aAwCSAgAmAAIJqAcLLwBPAAAjAAEJBQTEOQATAAAAAA==.Ravicavasar:BAAALgAECgEJAgAAAA==.Rawwr:BAABLgAECn8VAAIcAAcJPh//IwArAgAcAAcJPh//IwArAgAAAA==.Raynesong:BAAALgADCgYJBgAAAA==.Razfu:BAAALgAECgEJAQAAAA==.Razul:BAACLgAFFH8IAAIUAAMJVhtxDAAUAQAUAAMJVhtxDAAUAQAuAAQKfy8AAhQACQngHkgBAOQCABQACQngHkgBAOQCAAAA.',
Re='Redharvest:BAABLgAECn8ZAAIHAAcJiRqQHQCBAQAHAAcJiRqQHQCBAQAAAA==.Relentless:BAAALgAECgYJCwAAAA==.Relosaurus:BAAALgADCgEJAQAAAA==.Reportmypie:BAAALgADCgMJAwAAAA==.Restnpiece:BAAALgAECgYJDwAAAA==.',
Rh='Rhownin:BAAALgAECgcJEwABLgAFFAUJEgACAJwJAA==.',
Ri='Ripjw:BAAALgADCgUJBQABLgAFFAQJCAARADIhAA==.Rishal:BAAALgADCgMJAwABLgAECgYJCgANAAAAAA==.Rispy:BAAALgAECgMJAwAAAA==.',
Rk='Rkoo:BAAALgAECgcJDgAAAA==.',
Ro='Rob:BAAALgAECgEJAQAAAA==.Robstinks:BAAALgAECgEJAQAAAA==.Rotambo:BAAALgADCgEJAgAAAA==.Royok:BAABLgAECn8eAAIdAAgJZB08CgBxAgAdAAgJZB08CgBxAgAAAA==.Royork:BAAALgADCgcJBwABLgAECggJHgAdAGQdAA==.',
Ru='Rudania:BAAALgAECgYJCgAAAA==.',
Ry='Rymjerb:BAAALgAECgYJCQAAAA==.',
['Rë']='Rënd:BAAALgADCgMJAwAAAA==.',
Sa='Sabarr:BAAALgADCgMJAwAAAA==.Saberwulf:BAAALgAECgYJDAAAAA==.Sabrewolf:BAAALgAECgMJBgAAAA==.Sabroen:BAAALgADCgYJBgABLgAECgQJDgANAAAAAA==.Sacfusious:BAABLgAECn8VAAIGAAYJ9Q3TQQA8AQAGAAYJ9Q3TQQA8AQAAAA==.Saendnueds:BAAALgAECgUJBQAAAA==.Sakardi:BAAALgAECgIJAgAAAA==.Sannta:BAAALgADCgcJDAAAAA==.Sawedoff:BAABLgAECn8hAAMJAAgJER4yCQBoAgAJAAgJER4yCQBoAgAbAAYJ5xKFQwBIAQAAAA==.Sazeon:BAABLgAECn8ZAAIHAAgJJRMJIABzAQAHAAgJJRMJIABzAQAAAA==.',
Sc='Scamall:BAECLgAFFH8aAAIcAAYJOyZmAACVAgAcAAYJOyZmAACVAgAuAAQKfykAAhwACQnFJhoAAPsDABwACQnFJhoAAPsDAAAA.Schizophreni:BAABLgAFFH8IAAIPAAMJhRrXKQAmAQAPAAMJhRrXKQAmAQABLgAFFAYJFAALALwfAA==.Schokowitz:BAABLgAECn8WAAIBAAYJXiD5DADNAQABAAYJXiD5DADNAQAAAA==.Scionoffury:BAAALgAECgEJAQAAAA==.Scorpeon:BAAALgAECgYJCQAAAA==.Scotcolumbus:BAABLgAECn8ZAAIlAAgJhiLPAgD9AgAlAAgJhiLPAgD9AgAAAA==.',
Se='Sefu:BAAALgADCgUJBQAAAA==.Seraius:BAAALgAECgYJEAAAAA==.Seresis:BAACLgAFFH8RAAIRAAUJiRzoGQA+AQARAAUJiRzoGQA+AQAuAAQKfyYAAhEACQnCIw4OACsDABEACQnCIw4OACsDAAAA.Sero:BAAALgADCgcJDQAAAA==.',
Sh='Shaankspec:BAAALgAECgYJEQAAAA==.Shade:BAACLgAFFH8IAAIUAAMJcgqBDwD3AAAUAAMJcgqBDwD3AAAuAAQKfy8AAxQACQlAF70GAAoCABQACQlMFb0GAAoCABUAAQm9EnwTAD8AAAAA.Shadoewolfe:BAAALgAECgMJBQAAAA==.Shadowbindr:BAAALgAECgEJAgAAAA==.Shadowfallz:BAABLgAECn8fAAIXAAkJKh+VAgCIAgAXAAkJKh+VAgCIAgAAAA==.Shageron:BAACLgAFFH8TAAMbAAUJvxW1DQBHAQAbAAUJtRS1DQBHAQAJAAIJABtBJAC2AAAuAAQKfygAAhsACQkIIh8FAEwDABsACQkIIh8FAEwDAAAA.Shagmeblind:BAAALgAECgYJCgAAAA==.Shammwoww:BAAALgADCggJGgAAAA==.Shampóóp:BAAALgAECgQJBQAAAA==.Shandoe:BAAALgADCgIJAgAAAA==.Shankspec:BAACLgAFFH8OAAIVAAUJVRzCAAC+AQAVAAUJVRzCAAC+AQAuAAQKfy0AAxUACQkTIzEAADMDABUACQkTIzEAADMDABQAAQkfGKRbAEYAAAAA.Shayu:BAAALgADCgYJCgAAAA==.Shifthappens:BAAALgAECgEJAQAAAA==.Shikaca:BAAALgAECgEJAQAAAA==.Shinseina:BAABLgAECn8mAAMKAAgJIR2tDwBAAgAKAAgJIR2tDwBAAgAfAAUJWhXqZQDkAAAAAA==.Shivx:BAAALgAECgMJBQAAAA==.Shockdh:BAAALgADCgkJCQAAAA==.Shockinawe:BAAALgAECgQJBgAAAA==.Shoeboo:BAAALgADCgcJCQAAAA==.Shoriuken:BAAALgAECgMJAwAAAA==.Shtiq:BAAALgAECgEJAQABLgAFFAMJBwATAOskAA==.Shämash:BAABLgAECn8iAAIYAAgJxhPZCAB4AQAYAAgJxhPZCAB4AQAAAA==.Shízz:BAAALgADCgkJDQAAAA==.',
Si='Sicc:BAAALgADCgIJAgAAAA==.Siccness:BAABLgAECn8WAAMJAAcJMyA8JwAcAgAJAAcJMyA8JwAcAgAeAAIJ2wcNJAB5AAAAAA==.Sieben:BAAALgAECgEJAgAAAA==.Siella:BAABLgAECn8ZAAIFAAgJ7A/0DgC0AQAFAAgJ7A/0DgC0AQAAAA==.Sileve:BAAALgAECgEJAQABLgAECgYJEQANAAAAAA==.Silive:BAAALgADCgYJCQABLgAECgYJEQANAAAAAA==.Sindrex:BAACLgAFFH8IAAIIAAMJ6iGpCgApAQAIAAMJ6iGpCgApAQAuAAQKfy8AAggACQlPJEkAAKsDAAgACQlPJEkAAKsDAAEuAAQKAQkBAA0AAAAA.Sinestus:BAABLgAECn8hAAIlAAgJ1iIUAQC/AgAlAAgJ1iIUAQC/AgAAAA==.',
Sk='Skoody:BAAALgAECgIJAwAAAA==.Skrrt:BAAALgAECgQJBQAAAA==.Skwerl:BAAALgAECgUJDwAAAA==.',
Sl='Slick:BAAALgAECgYJEgAAAA==.Slickarus:BAABLgAECn8rAAMMAAkJJiRFBAB2AgAMAAkJuSNFBAB2AgAaAAcJjR6UAQAvAgAAAA==.Slumdawg:BAAALgADCgcJDAAAAA==.Slurmage:BAABLgAECn8nAAIPAAgJkyGoDgBpAgAPAAgJkyGoDgBpAgAAAA==.',
Sm='Smittywerben:BAAALgADCgUJBQAAAA==.Smooshi:BAACLgAFFH8MAAIZAAQJiB/0BwBnAQAZAAQJiB/0BwBnAQAuAAQKfzIAAhkACQmkIfsHAPUCABkACQmkIfsHAPUCAAAA.',
Sn='Snoke:BAAALgAECgEJAgAAAA==.',
So='Soleirel:BAAALgAECgYJEwAAAA==.Solfury:BAAALgADCgMJAwAAAA==.Solidjen:BAACLgAFFH8IAAIKAAMJWgoLIwDoAAAKAAMJWgoLIwDoAAAuAAQKfyAAAwoACQkOGgIMAGkCAAoACQkOGgIMAGkCACUAAwlECKg0AHQAAAAA.Solwalker:BAAALgADCgUJBQAAAA==.Soulfiend:BAAALgAECgIJAgAAAA==.',
Sp='Sparklefarts:BAAALgADCgYJDgAAAA==.Sparks:BAAALgAFFAEJAQAAAA==.Spearhead:BAAALgADCgEJAQAAAA==.Speedlings:BAACLgAFFH8PAAIUAAUJ4hl6BQBsAQAUAAUJ4hl6BQBsAQAuAAQKfyYAAhQACAm0IRcOAL4CABQACAm0IRcOAL4CAAAA.Spicedale:BAAALgAECgUJBwAAAA==.',
Sq='Squiggles:BAAALgAECgEJAQAAAA==.',
St='Star:BAAALgAECgcJCgAAAA==.Starfun:BAAALgAECgYJBgABLgAECggJFQAZAEMLAA==.Stealthven:BAAALgAECgQJBAAAAA==.Stenzwar:BAABLgAFFH8GAAICAAMJmgqtFADWAAACAAMJmgqtFADWAAABLgAFFAMJCAARAComAA==.Stiq:BAACLgAFFH8HAAITAAMJ6ySLFgBEAQATAAMJ6ySLFgBEAQAuAAQKfy4AAhMACQnXIy8BAEkDABMACQnXIy8BAEkDAAAA.Stlux:BAAALgAECgYJCAAAAA==.Stojkette:BAAALgAECgYJEQAAAA==.Stormbless:BAABLgAECn8mAAIGAAgJBBjcCwDLAQAGAAgJBBjcCwDLAQAAAA==.Storminmycup:BAAALgAECgQJBgABLgAFFAYJEgABAFUbAA==.',
Su='Sulzire:BAAALgADCgQJAwAAAA==.Sumx:BAAALgAFFAMJBAAAAA==.Superarrows:BAAALgADCgQJBAAAAA==.Supersquirel:BAAALgAECgEJAgAAAA==.Superstabs:BAAALgADCgMJAwAAAA==.',
Sw='Sweeger:BAABLgAECn8kAAMZAAgJdhk/EQDqAQAZAAgJdhk/EQDqAQABAAEJDBYMSgBDAAAAAA==.Sweegie:BAAALgADCgYJBgAAAA==.Sweetlou:BAAALgADCgcJEgAAAA==.Swego:BAAALgAECgEJAQAAAA==.',
Sy='Syds:BAABLgAECn8XAAIRAAYJghtXOABYAQARAAYJghtXOABYAQAAAA==.Sylaraa:BAAALgAECgcJEQAAAA==.Synapticzion:BAAALgAECggJCwAAAA==.Synatra:BAAALgAECgEJAQAAAA==.Syndra:BAAALgADCgEJAQABLgADCgUJBQANAAAAAA==.',
['Sí']='Sílk:BAAALgAECgEJAQAAAA==.',
Ta='Taara:BAABLgAECn8mAAIhAAgJ/CStAADeAgAhAAgJ/CStAADeAgAAAA==.Taarat:BAAALgAECgIJAgABLgAECggJJgAhAPwkAA==.Tacobelf:BAAALgAECgQJBAAAAA==.Takkana:BAAALgAECgEJAQABLgAECgkJKwAMACYkAA==.Talellianis:BAAALgAECgYJBwAAAA==.Tanneleer:BAAALgAECgEJAQAAAA==.Tarzo:BAAALgAECgIJAwAAAA==.Taucetiluna:BAAALgADCgYJBgAAAA==.Tazzyshmurda:BAAALgAECggJCAAAAA==.',
Tc='Tchaikovsky:BAAALgADCgQJBAAAAA==.',
Te='Tehdazzler:BAAALgADCgMJAwAAAA==.Tehdymare:BAAALgADCgYJBgAAAA==.Tehrains:BAAALgAECgEJAQAAAA==.Telenn:BAAALgAECgQJDQAAAA==.Terk:BAACLgAFFH8SAAIhAAUJqCKCAAA/AQAhAAUJqCKCAAA/AQAuAAQKfyYAAyEACQlYJjQAAN0DACEACQlYJjQAAN0DABkAAQllBFGcADUAAAAA.Termina:BAABLgAECn8YAAMSAAcJ1R53BQDbAQASAAcJqx53BQDbAQARAAYJRRnSgQB/AQAAAA==.',
Th='Thaatguy:BAAALgADCgEJAQAAAA==.Thalrymere:BAABLgAECn8fAAIbAAgJ8xkbBQCuAQAbAAgJ8xkbBQCuAQAAAA==.Thanirn:BAAALgAECgEJAQAAAA==.Thepruning:BAAALgAECgEJAQAAAA==.Thiccerlegs:BAABLgAECn8WAAMOAAYJYAcMKADHAAAOAAYJYAcMKADHAAAcAAUJeAaPSACuAAAAAA==.Thiccwnr:BAABLgAECn8TAAMQAAcJ2iB+AQDtAQAQAAYJEyF+AQDtAQAPAAIJuh+YswBfAAAAAA==.Thiccycheeks:BAACLgAFFH8KAAIHAAMJ0h2MFgAcAQAHAAMJ0h2MFgAcAQAuAAQKfxUAAgcABwmmIfEcAKQCAAcABwmmIfEcAKQCAAAA.Thiccyquicki:BAAALgAECgQJBwABLgAFFAMJCgAHANIdAA==.',
Ti='Ticklock:BAAALgADCgcJCAAAAA==.Tidelizard:BAACLgAFFH8QAAIIAAYJpg/0BQCWAQAIAAYJpg/0BQCWAQAuAAQKfx0AAggACQmHHKYHAMMCAAgACQmHHKYHAMMCAAAA.Tigolbittys:BAABLgAECn8WAAMKAAcJIgjhUgAVAQAKAAcJHwfhUgAVAQAlAAYJTwUQKgC7AAAAAA==.Tikz:BAABLgAECn8mAAITAAgJrhCNKQCHAQATAAgJrhCNKQCHAQAAAA==.Tills:BAAALgADCgcJDgABLgAECgQJBAANAAAAAA==.Tinycomp:BAAALgADCgIJAgAAAA==.',
To='Tock:BAACLgAFFH8HAAIhAAQJIQhEAwDAAAAhAAQJIQhEAwDAAAAuAAQKfyIAAiEACQmIH+YAAMECACEACQmIH+YAAMECAAAA.Tockella:BAAALgADCgQJBAABLgAFFAQJBwAhACEIAA==.Tockstar:BAAALgADCgcJBwAAAA==.Toe:BAAALgADCgcJDAAAAA==.Tokenwarrior:BAAALgAECgQJBwAAAA==.Tokodomo:BAAALgAECgYJBgABLgAFFAIJBQARAEodAA==.Torvï:BAAALgAECgYJCwAAAA==.',
Tr='Tralina:BAAALgADCgcJCQABLgAECgYJBwANAAAAAA==.Trapstâr:BAABLgAFFH8IAAMJAAQJmxDAHQDnAAAbAAMJ1REoFQDzAAAJAAMJ4wjAHQDnAAAAAA==.Treechicken:BAAALgAECgcJEwAAAA==.Tricky:BAABLgAECn8aAAMHAAgJXR+nGQCcAQAHAAgJtB6nGQCcAQAXAAMJ1xyGSADRAAAAAA==.Trill:BAACLgAFFH8NAAIUAAUJ1RtvBQBsAQAUAAUJ1RtvBQBsAQAuAAQKfyQAAxQACAlMJFgGACsDABQACAlMJFgGACsDABYAAQl9GlwMAEsAAAAA.Tripotley:BAAALgAECgQJBAAAAA==.Trivalence:BAABLgAECn8VAAIcAAYJPCC2EAAKAgAcAAYJPCC2EAAKAgAAAA==.Truegrit:BAAALgADCgUJBQAAAA==.Trëspin:BAAALgAECgEJAQAAAA==.',
Ts='Tsarfun:BAAALgAECgcJEwABLgAECggJFQAZAEMLAA==.Tseon:BAAALgADCgcJCwABLgAECggJIQAJABEeAA==.',
Tu='Tuor:BAAALgAECgQJCAAAAA==.Turaco:BAAALgADCgIJAgABLgAECgkJHgAYANIKAA==.',
Tw='Twizzurp:BAAALgAECgEJAQABLgAECgcJBwANAAAAAA==.',
Ty='Tywin:BAAALgADCgcJCgAAAA==.Tyèll:BAABLgAECn8XAAILAAgJYwVqNgA6AQALAAgJYwVqNgA6AQAAAA==.',
['Tá']='Tái:BAAALgAECgYJDQAAAA==.',
Uj='Ujio:BAAALgAECgQJBQAAAA==.',
Un='Undeadwaifu:BAAALgADCgQJBAAAAA==.Unkledeath:BAAALgAECgQJAQAAAA==.',
Up='Upmysleeves:BAACLgAFFH8GAAIPAAMJvBeyLgAPAQAPAAMJvBeyLgAPAQAuAAQKfxgAAg8ABwl1IdYUADQCAA8ABwl1IdYUADQCAAAA.',
Va='Vance:BAAALgAECgQJBAAAAA==.Vaughn:BAACLgAFFH8PAAICAAYJKAzIBQCVAQACAAYJKAzIBQCVAQAuAAQKfyoAAgIACAk5HgIHAEECAAIACAk5HgIHAEECAAAA.Vaust:BAAALgAECgMJAwAAAA==.',
Ve='Vedekur:BAAALgADCgIJAgAAAA==.Veggieboi:BAACLgAFFH8GAAITAAMJexU4IgD7AAATAAMJexU4IgD7AAAuAAQKfycAAxMACAncIPUTAN0CABMACAncIPUTAN0CAAMAAQkAAFxjAEgAAAAA.Vellast:BAAALgAECgQJBAAAAA==.Velocathyr:BAABLgAECn8VAAMMAAgJfRbdFgAfAgAMAAgJfRbdFgAfAgAaAAEJ7A/7PQA3AAAAAA==.Venthunt:BAABLgAECn8fAAQbAAkJ3BvGDwC+AgAbAAkJtRvGDwC+AgAeAAYJRB5RFQByAQAJAAMJDyPRZQA2AQAAAA==.Verellia:BAABLgAECn8PAAIHAAcJ6BeaHACIAQAHAAcJ6BeaHACIAQAAAA==.',
Vi='Victory:BAABLgAECn8WAAIfAAcJDCEeFwBZAgAfAAcJDCEeFwBZAgAAAA==.Vigilo:BAACLgAFFH8SAAIiAAUJ/R69AwBfAQAiAAUJ/R69AwBfAQAuAAQKfyQAAiIACQlmIzcCAIADACIACQlmIzcCAIADAAAA.Vilhelmina:BAAALgAECgYJDwAAAA==.Viruzdk:BAABLgAECn8eAAMRAAcJdCEwTgAIAgARAAcJeB8wTgAIAgASAAQJoB9nIABBAQAAAA==.',
Vo='Voidwalker:BAABLgAECn8SAAIHAAYJ3BUUYQB+AQAHAAYJ3BUUYQB+AQAAAA==.Voidwench:BAABLgAECn8fAAIHAAgJwB9KDAAbAgAHAAgJwB9KDAAbAgAAAA==.Volrog:BAACLgAFFH8NAAIhAAUJVRHoAQAHAQAhAAUJVRHoAQAHAQAuAAQKfykAAiEACAmpJLwBAEkDACEACAmpJLwBAEkDAAAA.Vosduo:BAAALgAECgMJAwAAAA==.',
Vr='Vritarah:BAAALgADCgcJCQAAAA==.',
Wa='Wafio:BAAALgADCgQJBAABLgAECgIJAgANAAAAAA==.Warcheif:BAABLgAECn8aAAIJAAYJRwpyQgANAQAJAAYJRwpyQgANAQAAAA==.Warwonka:BAACLgAFFH8IAAIbAAMJRxebCAD5AAAbAAMJRxebCAD5AAAuAAQKfy8AAhsACQl5HNEAAMECABsACQl5HNEAAMECAAAA.Warzan:BAAALgAECgQJBwAAAA==.Watchurbeard:BAABLgAECn8lAAIeAAgJJhSHDQDwAQAeAAgJJhSHDQDwAQAAAA==.Waviowi:BAABLgAECn8cAAIPAAgJIQt7OACGAQAPAAgJIQt7OACGAQAAAA==.',
We='Weatherdwarf:BAABLgAECn8YAAIZAAgJ0QlSKAAtAQAZAAgJ0QlSKAAtAQAAAA==.',
Wh='Whammer:BAAALgAECggJEwAAAA==.Whiiplash:BAAALgAECgEJAQAAAA==.Whippy:BAAALgAECgEJAQABLgAECgEJAQANAAAAAA==.Whooped:BAAALgAECgUJBQABLgAECggJJAAkAPAZAA==.Whysolittle:BAAALgADCgUJBQAAAA==.',
Wi='Windfûrry:BAAALgAFFAIJAgAAAA==.',
Wl='Wlntercamo:BAAALgAECgUJDgAAAA==.',
Wr='Wrapfire:BAAALgAECgYJEAAAAA==.Wrapps:BAAALgAECgIJAgAAAA==.',
Xe='Xeroxed:BAABLgAECn8lAAIRAAgJohtFFgAIAgARAAgJohtFFgAIAgAAAA==.',
Xi='Xiangmei:BAAALgAECgcJDgAAAA==.',
Xo='Xon:BAAALgADCgQJBAAAAA==.',
Ya='Yacob:BAACLgAFFH8SAAIPAAYJQCFyBQDYAQAPAAYJQCFyBQDYAQAuAAQKfyYAAg8ACQnpJcsCANIDAA8ACQnpJcsCANIDAAAA.Yamarahj:BAACLgAFFH8JAAMTAAMJhQ+BMADjAAATAAMJ5w6BMADjAAAnAAEJowbbAwBXAAAuAAQKfyMABCcACQkxH4QIAMEBABMACAmGG31LAOcBACcABQnrHIQIAMEBAAMABAkJEowuAAEBAAAA.',
Ye='Yenna:BAAALgADCgEJAQAAAA==.',
Yo='Yorikk:BAABLgAECn8XAAMDAAgJexJ8FACnAQADAAgJfgx8FACnAQATAAUJHhJLVgDuAAAAAA==.Youngtwerk:BAAALgAECgUJBwAAAA==.',
Za='Zaeleane:BAAALgAECgcJEQAAAA==.Zanrak:BAAALgADCgYJCAABLgAECgQJCwANAAAAAA==.Zard:BAAALgAECgYJDgAAAA==.Zardrelin:BAAALgADCgYJBgABLgADCgYJBwANAAAAAA==.Zareynne:BAAALgAECgcJEgAAAA==.Zarmaku:BAAALgAECgEJAwAAAA==.Zathyr:BAAALgADCgQJBAAAAA==.Zauber:BAACLgAFFH8TAAQTAAYJRyN+AwDqAQATAAYJTiJ+AwDqAQAnAAEJuSFzAwBfAAADAAEJ+Bx/EgBaAAAuAAQKfycABBMACQmAJokAAOEDABMACQk8JokAAOEDACcABwmvJtEAABgDAAMABwmLI4QGAGYCAAAA.Zazie:BAABLgAECn8lAAMgAAgJ6BvfAQBDAgAgAAgJ6BvfAQBDAgAHAAEJVRuT4QAwAAAAAA==.Zazu:BAAALgAECgEJAQAAAA==.',
Ze='Zelani:BAAALgAECgYJCgAAAA==.Zensei:BAAALgADCgYJDQAAAA==.',
Zi='Zirraj:BAACLgAFFH8OAAICAAYJ3xt+AADaAQACAAYJ3xt+AADaAQAuAAQKfyUAAwIACQlrIqgFAEwDAAIACQlrIqgFAEwDABgAAQm1ICwkAF0AAAAA.',
Zm='Zmaj:BAAALgAECgcJCAABLgAFFAMJAwANAAAAAA==.',
Zn='Zn:BAAALgADCgcJDQAAAA==.',
Zo='Zocalo:BAAALgAECgYJDQABLgAFFAUJEgAiAP0eAA==.Zodiac:BAAALgAFFAEJAgABLgAFFAIJBgAjAH4mAA==.Zoldyck:BAAALgAECggJCAAAAA==.Zorø:BAABLgAECn8mAAIgAAgJIg4ADQCIAQAgAAgJIg4ADQCIAQAAAA==.Zovinox:BAAALgAECgIJBAAAAA==.',
Zu='Zulrok:BAAALgADCgYJBgAAAA==.Zurk:BAAALgADCgEJAwAAAA==.',
Zy='Zygon:BAAALgAECgEJAgABLgAFFAIJBgAjAH4mAA==.',
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
