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

local lookup = {'Unknown-Unknown','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Elemental','Shaman-Restoration','Paladin-Retribution','Druid-Balance','Rogue-Subtlety','Rogue-Assassination','DemonHunter-Devourer','DemonHunter-Havoc','Warlock-Demonology','DeathKnight-Unholy','Hunter-Survival','Monk-Brewmaster','DeathKnight-Blood','Monk-Mistweaver','Warlock-Affliction','Warlock-Destruction','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Priest-Holy','Druid-Guardian','Paladin-Holy','Paladin-Protection','Warrior-Fury','Mage-Frost','Druid-Feral','Mage-Arcane','Druid-Restoration','Monk-Windwalker','Shaman-Enhancement','DeathKnight-Frost','DemonHunter-Vengeance','Priest-Discipline','Priest-Shadow','Warrior-Protection','Warrior-Arms',}
local provider = {region='US',realm='Fizzcrank',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abandonhope:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.',
Ac='Accuser:BAAALgADCgEJAQAAAA==.Acky:BAAALgADCgUJBQAAAA==.',
Ad='Adwen:BAAALgAECgUJDAAAAA==.',
Ae='Aeronemon:BAAALgAECgEJAgAAAA==.',
Ai='Airill:BAAALgADCgQJBQAAAA==.',
Ak='Akforty:BAABLgAECn8fAAMCAAkJJCHPCgDvAgACAAkJJCHPCgDvAgADAAIJoBVreABfAAAAAA==.Akittymeow:BAABLgAECn8ZAAMEAAgJARCQIgAKAQAEAAcJYg+QIgAKAQAFAAMJjwViSQB6AAAAAA==.',
Al='Aldredevon:BAAALgAECgEJAQAAAA==.Aleshock:BAAALgAECgYJCwAAAA==.Alidar:BAAALgAECgcJEgAAAA==.Alphaboner:BAAALgADCgEJAQAAAA==.Altairis:BAAALgAECgEJAgAAAA==.Altartoy:BAAALgAECggJDgAAAA==.Althunter:BAABLgAECn8XAAIDAAgJWyASAwAFAgADAAgJWyASAwAFAgAAAA==.',
Am='Amelina:BAAALgAECgMJBAAAAA==.Amorir:BAABLgAECn8mAAIGAAgJ2hDjKgCWAQAGAAgJ2hDjKgCWAQAAAA==.Amorydalias:BAAALgAECgUJBgAAAA==.Amozon:BAAALgADCgEJAQAAAA==.',
An='Anastala:BAABLgAECn8VAAIHAAcJwBNiFgBNAQAHAAcJwBNiFgBNAQAAAA==.Angchu:BAAALgADCgQJBAAAAA==.Angelmàker:BAAALgAECgMJBAABLgADCgcJEwABAAAAAA==.Annesta:BAABLgAECn8ZAAMIAAgJPRiyDwBzAQAIAAgJ/xeyDwBzAQAJAAEJ+xaoEgBGAAAAAA==.',
Ap='Apostus:BAAALgADCgcJDgAAAA==.Apothica:BAAALgAECgUJBgAAAA==.',
Aq='Aquafox:BAAALgAECgYJDwAAAA==.',
Ar='Archontas:BAAALgAECgYJEwAAAA==.Ariodh:BAABLgAECn8eAAMKAAgJCSb5BACVAgAKAAgJCSb5BACVAgALAAUJpB9WJACaAQAAAA==.Arkaline:BAAALgAECgEJAQAAAA==.Artuarry:BAACLgAFFH8MAAIMAAQJPgx6HQAsAQAMAAQJPgx6HQAsAQAuAAQKfyIAAgwACQnpHgwRAB0CAAwACQnpHgwRAB0CAAAA.Aryndus:BAAALgAECggJDQAAAA==.',
At='Athenà:BAAALgAECgQJBAAAAA==.',
Av='Avocado:BAABLgAECn8fAAMCAAgJLSOKCgBVAgACAAcJ6yCKCgBVAgADAAcJQyKmAgAcAgAAAA==.',
Ax='Axelaw:BAAALgADCgQJBAAAAA==.',
Ay='Ayrz:BAAALgAECgIJAgAAAA==.',
Az='Azaria:BAAALgADCgIJAgAAAA==.',
Ba='Baileyhowl:BAAALgAECgEJAgAAAA==.Bammie:BAAALgADCgQJBAAAAA==.Bananuth:BAAALgAECgIJAgABLgAFFAQJCwANAD8cAA==.Banthr:BAAALgAECggJDwAAAA==.Barkert:BAAALgADCgEJAQAAAA==.Baroke:BAAALgAECgMJBwABLgAECggJDgABAAAAAA==.Barokoshama:BAAALgAECgcJEQAAAA==.Basaltytaco:BAAALgADCgEJAQAAAA==.Battleworm:BAAALgADCgkJEwABLgAECgYJBgABAAAAAA==.',
Bb='Bbalrd:BAAALgAECgcJEwAAAA==.',
Be='Bearglie:BAAALgAECgYJBgAAAA==.Beepers:BAAALgAECgYJBgAAAA==.',
Bi='Bigcow:BAAALgAECgEJAgAAAA==.',
Bl='Blackolives:BAAALgAECgYJCgAAAA==.Blondefu:BAAALgAECgUJCwAAAA==.Bloodybonne:BAAALgADCgcJBwAAAA==.Bloodyell:BAAALgAECgEJAQAAAA==.Bloore:BAAALgAECgMJAwABLgAECggJIwADAO0hAA==.Bluejuly:BAAALgAECgQJBAAAAA==.Blutø:BAAALgAECgEJAgAAAA==.',
Bo='Boflex:BAAALgADCgQJBQAAAA==.Bomboclat:BAAALgAECgUJCwAAAA==.Bonesknows:BAAALgADCgEJAQAAAA==.Boofy:BAAALgAECgIJAgABLgAECggJFAAMAFoWAA==.Bowwie:BAACLgAFFH8GAAMCAAMJZBBfHADyAAACAAMJZBBfHADyAAAOAAIJxgS+EACUAAAuAAQKfyIABAIACQkQHi8GACsDAAIACQkQHi8GACsDAA4AAgnhDfUiAIQAAAMAAQkVAwaTACcAAAAA.',
Br='Britney:BAAALgADCgkJCQAAAA==.Bronzé:BAAALgAECgUJEAAAAA==.Brotherfrey:BAAALgAECgYJCgAAAA==.Bruish:BAABLgAFFH8MAAIPAAQJtwzBDQAWAQAPAAQJtwzBDQAWAQAAAA==.',
Bu='Bubbadoo:BAAALgAECgcJEAAAAA==.Buddy:BAAALgAECgUJDQABLgAECgYJFgAQAJYhAA==.Bulan:BAABLgAECn8lAAIRAAgJFyREAQBAAwARAAgJFyREAQBAAwAAAA==.',
Bw='Bweninger:BAAALgADCgcJBwAAAA==.',
['Bô']='Bôôsted:BAABLgAECn8WAAIEAAgJyRbdIAAIAgAEAAgJyRbdIAAIAgAAAA==.',
Ca='Caistan:BAAALgADCgYJCAAAAA==.Candypants:BAAALgAECgcJCgAAAA==.Caoth:BAAALgAECgYJEwAAAA==.Cappilon:BAAALgAECgYJCwAAAA==.Carcus:BAAALgAECgEJAQAAAA==.Cayleedah:BAABLgAECn8YAAIDAAcJWAYYDAANAQADAAcJWAYYDAANAQAAAA==.Cayssaris:BAAALgAECgUJCQAAAA==.',
Cc='Cc:BAABLgAECn8WAAQSAAYJOxPsDgBCAQASAAUJ9BPsDgBCAQATAAYJKwsxIwA+AQAMAAQJzRPptQDtAAAAAA==.',
Ce='Ceeti:BAABLgAECn8mAAMUAAgJOCCPBABsAgAUAAgJOCCPBABsAgAVAAIJeAYYQABpAAAAAA==.Celandrelia:BAAALgAECgUJBQABLgAECggJIwAWAI8VAA==.',
Ch='Chaoticoreo:BAABLgAECn8lAAMLAAgJkR2EAwBfAgALAAgJkR2EAwBfAgAKAAQJ4w9crQCzAAAAAA==.Chappedlips:BAAALgAECgkJBgAAAA==.Chareyne:BAABLgAECn8ZAAIXAAgJ5BFtJgC5AQAXAAgJ5BFtJgC5AQAAAA==.Cheetor:BAAALgAECgMJAwABLgAECgkJKgAOADYhAA==.Cheezytaco:BAAALgAECgUJBwABLgAECggJGQAGAOscAA==.Chidge:BAAALgADCggJCwAAAA==.Chikila:BAAALgAECgYJDgAAAA==.Chilliflakez:BAAALgAECgUJDAAAAA==.Chro:BAAALgADCgcJBwAAAA==.',
Ci='Cindezar:BAAALgADCgMJAwAAAA==.',
Cl='Clementyn:BAAALgAECgYJEQAAAA==.Cleyi:BAABLgAECn8dAAIXAAgJtQopFQBnAQAXAAgJtQopFQBnAQAAAA==.',
Co='Coldpasta:BAAALgAECgYJDQABLgAFFAIJAgABAAAAAA==.Colonoscopy:BAAALgAECgEJAQAAAA==.Coreyy:BAAALgADCgUJBwAAAA==.Corva:BAACLgAFFH8FAAIMAAMJjQ51LgDqAAAMAAMJjQ51LgDqAAAuAAQKfyYAAgwACAmHF6ggALEBAAwACAmHF6ggALEBAAAA.Cosairi:BAAALgADCgQJBAAAAA==.Cougztroll:BAABLgAECn8gAAIYAAgJMRZ0BwB0AQAYAAgJMRZ0BwB0AQAAAA==.',
Cr='Crazaki:BAAALgADCgEJAQAAAA==.',
Cu='Curfluffin:BAAALgADCgEJAQAAAA==.Cuttercupx:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.',
Da='Dakadin:BAABLgAECn8fAAMZAAgJUyIGGABSAgAZAAgJUyIGGABSAgAGAAQJ5xduVQAOAQAAAA==.Daranne:BAABLgAECn8kAAIGAAgJMBoXPwApAgAGAAgJMBoXPwApAgAAAA==.Darksoulstwo:BAAALgADCgMJAwAAAA==.Dasbeans:BAAALgAFFAIJAwAAAA==.Dashy:BAAALgAECgYJCQAAAA==.Datran:BAAALgADCgUJBQABLgAECgEJAQABAAAAAA==.',
De='Deaduglie:BAABLgAECn8gAAMMAAgJRBY9GgDYAQAMAAgJRBY9GgDYAQATAAEJMQjlcQA0AAAAAA==.Deliandora:BAAALgADCgUJBQAAAA==.Delusional:BAAALgAECgEJAQAAAA==.Delynique:BAAALgADCgEJAQABLgAECggJIwADAO0hAA==.Demonx:BAAALgAECgEJAQAAAA==.Denaric:BAAALgAECgUJCwAAAA==.Destroyevsky:BAAALgAECgQJCQAAAA==.Detonate:BAAALgAECgQJCwAAAA==.',
Dh='Dhvecx:BAAALgAECgUJBgABLgAECgYJDQABAAAAAA==.',
Di='Dilbo:BAAALgAECgEJAQAAAA==.Diomed:BAAALgAECgEJAQAAAA==.Diqon:BAABLgAECn8mAAMNAAgJIxcVJQCsAQANAAgJIxcVJQCsAQAQAAYJyBMgIwAoAQAAAA==.Disturbedtwo:BAAALgAECgQJBAAAAA==.',
Do='Dolphinz:BAACLgAFFH8HAAIGAAIJxxTnIgCnAAAGAAIJxxTnIgCnAAAuAAQKfyMAAwYACAn6IB0PAEYCAAYACAn6IB0PAEYCABoAAgnpCiA8AE4AAAAA.Doryadni:BAAALgADCgcJBgAAAA==.',
Dr='Dragonpede:BAABLgAECn8wAAIUAAkJnx1UAgDUAgAUAAkJnx1UAgDUAgAAAA==.Dragonwarior:BAABLgAECn8bAAIbAAcJORz4GQBgAQAbAAcJORz4GQBgAQAAAA==.Drakindees:BAAALgADCgYJDQABLgAECgcJIwAcAPQhAA==.Drakkyn:BAAALgAECgUJDQAAAA==.Dread:BAAALgADCgQJBAAAAA==.Drosuu:BAAALgAECgEJAQAAAA==.Druish:BAACLgAFFH8QAAIYAAQJDh52AQBtAQAYAAQJDh52AQBtAQAuAAQKfyQAAxgACQkyJqwBADUDABgACQkyJqwBADUDAB0AAgkOD5YsAGEAAAAA.Drykkr:BAABLgAECn8fAAIPAAgJnhSpDQCxAQAPAAgJnhSpDQCxAQAAAA==.',
Du='Dullahan:BAAALgAECgUJBQAAAA==.Durrik:BAAALgADCgcJBwAAAA==.',
['Dà']='Dàsh:BAAALgAECgYJBgABLgAECgYJCQABAAAAAA==.',
Ea='Eatrocks:BAAALgADCggJCAAAAA==.',
Ed='Edorn:BAAALgADCgIJAgAAAA==.',
Ef='Efn:BAAALgAECgYJEwAAAA==.',
El='Elcrys:BAAALgAECgcJEAAAAA==.Elion:BAAALgAECgEJAQAAAA==.Elpollo:BAABLgAECn8jAAMcAAcJ9CGVQgBwAgAcAAcJ9CGVQgBwAgAeAAEJshezHAA6AAAAAA==.Elvar:BAAALgAECgMJAwAAAA==.',
Em='Emmdwemm:BAAALgAECgIJAwAAAA==.',
En='Enoki:BAAALgAECgQJBAAAAA==.',
Ep='Ephelia:BAABLgAECn8WAAMFAAgJRhqLIgAPAgAFAAgJRhqLIgAPAgAEAAEJjAPzlAAgAAAAAA==.Epitome:BAAALgAECgcJCgAAAA==.',
Er='Erid:BAAALgAECgYJCgAAAA==.',
Es='Estrogen:BAAALgADCgQJBAAAAA==.',
Et='Etude:BAAALgADCgEJAQAAAA==.',
Ev='Evelyndel:BAAALgAECgIJAgAAAA==.Evergrey:BAAALgADCgcJBwAAAA==.Evermoons:BAABLgAECn8fAAIfAAgJxRkdCgBoAgAfAAgJxRkdCgBoAgAAAA==.',
Fa='Falaria:BAAALgAECgQJBAAAAA==.Falasdaer:BAAALgAECggJEAAAAA==.Falstaff:BAABLgAECn8UAAIPAAgJ+RIYDgCrAQAPAAgJ+RIYDgCrAQAAAA==.Fartshooter:BAAALgAECgYJEQAAAA==.Fatterblunt:BAACLgAFFH8MAAIHAAQJKRGrCgA/AQAHAAQJKRGrCgA/AQAuAAQKfyMAAgcACQmEHz4HACQCAAcACQmEHz4HACQCAAAA.',
Fe='Fedner:BAABLgAECn8XAAIFAAcJQg9cHwBpAQAFAAcJQg9cHwBpAQAAAA==.Feldar:BAABLgAECn8ZAAIGAAgJYB3jEgAjAgAGAAgJYB3jEgAjAgAAAA==.Fend:BAAALgADCgQJBAAAAA==.Feyredarling:BAAALgAECgMJAwAAAA==.',
Fi='Fists:BAACLgAFFH8MAAIPAAQJhhzQBwBbAQAPAAQJhhzQBwBbAQAuAAQKfyoAAw8ABgmEI44WAFQCAA8ABgmEI44WAFQCACAABAk3EqJUAL4AAAAA.Fizzbeard:BAAALgADCgcJCgAAAA==.Fizzical:BAAALgADCgYJBgAAAA==.Fizzleclaw:BAAALgAECgUJCQAAAA==.Fizzleded:BAAALgAECgQJBQABLgAECgUJCQABAAAAAA==.',
Fl='Flightrisk:BAAALgAECgMJAwABLgAECgIJAgABAAAAAA==.Florisa:BAABLgAECn8iAAIGAAgJPBzHEQAsAgAGAAgJPBzHEQAsAgAAAA==.',
Fo='Fordi:BAABLgAECn8dAAMEAAgJfxdWCgD2AQAEAAgJVBdWCgD2AQAhAAIJLRFEJgBzAAAAAA==.Fourdy:BAABLgAECn8lAAIFAAcJCRnAGACeAQAFAAcJCRnAGACeAQAAAA==.',
Fr='Fragdoll:BAAALgAECgQJCgAAAA==.Freakinlarry:BAAALgADCgEJAQAAAA==.Freakinoak:BAABLgAECn8UAAIfAAgJFA6EIAB9AQAfAAgJFA6EIAB9AQAAAA==.Free:BAAALgAECgYJDAAAAA==.Froost:BAABLgAECn8WAAINAAgJ0BzuTAAMAgANAAgJ0BzuTAAMAgAAAA==.',
Fu='Funkflex:BAAALgADCgcJCgABLgAECgYJDAABAAAAAA==.Furvert:BAAALgAECgIJAgAAAA==.Fushi:BAAALgAECgEJAQAAAA==.',
Ga='Gandis:BAAALgAECggJEQAAAA==.Gapper:BAABLgAECn8qAAIOAAkJNiGOAQC7AgAOAAkJNiGOAQC7AgAAAA==.',
Gi='Gimbó:BAAALgADCgQJBAAAAA==.',
Gl='Glamour:BAAALgADCgEJAgAAAA==.Glestaar:BAABLgAECn8fAAMCAAgJSRj5HwBFAgACAAgJSRj5HwBFAgADAAIJPQt3fABSAAAAAA==.Glyr:BAAALgAECgYJCgAAAA==.',
Go='Goingrouge:BAAALgAECgEJAgAAAA==.Goldabelle:BAAALgAECgYJCgAAAA==.Gorlami:BAAALgAFFAEJAQAAAA==.Gothelf:BAAALgAFFAIJAgAAAA==.Gothri:BAAALgAECgIJAgABLgAECgYJEgABAAAAAA==.Gothstraza:BAAALgAECgYJEgAAAA==.Gottemgood:BAAALgADCgUJBQAAAA==.',
Gr='Grimli:BAABLgAECn8WAAIFAAgJ9w40IgBVAQAFAAgJ9w40IgBVAQAAAA==.Growth:BAAALgAECgcJDgAAAA==.',
Gu='Gurthcaptian:BAAALgAECgQJBAAAAA==.',
['Gá']='Gárròsh:BAAALgAECgYJBgAAAA==.',
Ha='Haerin:BAAALgAECgIJAgABLgAFFAQJCQAXABQcAA==.Harnel:BAABLgAECn8XAAIGAAYJSgMaeQC7AAAGAAYJSgMaeQC7AAAAAA==.Haseo:BAAALgAECgIJAgAAAA==.Hattorihanzo:BAAALgAECgQJBAAAAA==.',
He='Healeymonstr:BAAALgADCgIJAgAAAA==.Healmart:BAAALgAECgQJCAAAAA==.Heartëater:BAAALgADCgYJBgAAAA==.Hellinyoface:BAAALgADCgUJBQAAAA==.',
Hi='Himothyy:BAAALgAECgQJBAAAAA==.',
Ho='Holypeetch:BAAALgADCgYJBgAAAA==.Hoofpics:BAAALgADCgcJCAAAAA==.Hordedefect:BAAALgADCgQJBAABLgAECgIJAgABAAAAAA==.Hoyer:BAAALgAECggJEQAAAA==.',
Im='Impact:BAAALgADCgcJCgAAAA==.',
Io='Iove:BAABLgAECn8YAAIRAAgJuBbjEQCPAQARAAgJuBbjEQCPAQAAAA==.',
Ja='Jahsahm:BAAALgAECgcJEQAAAA==.Jajung:BAAALgADCgMJAwAAAA==.Jakub:BAAALgAECggJEwABLgAFFAMJBgACAGQQAA==.Jakuren:BAAALgADCgYJBgAAAA==.Jamjam:BAAALgADCgYJCQAAAA==.',
Je='Jesit:BAAALgAECgYJEAAAAA==.',
Ji='Jingles:BAAALgADCgYJBgAAAA==.',
Jj='Jjada:BAAALgAECgcJEQAAAA==.',
Jo='Johnwolf:BAAALgAECgUJDAAAAA==.',
Jy='Jyade:BAAALgAECgcJEwAAAA==.Jynoria:BAAALgADCgcJDAAAAA==.',
Ka='Kainlok:BAAALgADCgIJAgAAAA==.Kaiserice:BAAALgAECgYJDwAAAA==.Kamarra:BAABLgAECn8UAAIUAAYJkga4JwDQAAAUAAYJkga4JwDQAAAAAA==.Kamencider:BAABLgAECn8aAAIcAAYJ6hBUUABAAQAcAAYJ6hBUUABAAQAAAA==.Kamidala:BAAALgADCgcJCAAAAA==.Kankles:BAABLgAECn8kAAIHAAcJ6CLhBABlAgAHAAcJ6CLhBABlAgAAAA==.Katabetta:BAAALgADCgMJAwAAAA==.',
Ke='Kernelpanic:BAACLgAFFH8LAAMNAAQJPxyIEgBlAQANAAQJPxyIEgBlAQAiAAEJ9wWWBwBIAAAuAAQKfyMAAg0ACQnKIfIXAPsBAA0ACQnKIfIXAPsBAAAA.Kessho:BAAALgAECgYJDwABLgAFFAMJBgACAGQQAA==.Kevynn:BAAALgADCgMJAgAAAA==.Keyoshi:BAAALgAECgYJBgAAAA==.',
Ki='Kickrocks:BAAALgADCgUJBwAAAA==.Kilerforlife:BAAALgAECgYJCwAAAA==.Kilowog:BAAALgADCgUJCAAAAA==.Kilpally:BAAALgAECgYJBwAAAA==.Kintra:BAAALgADCgIJAgAAAA==.Kirin:BAAALgADCgEJAQAAAA==.Kirkle:BAABLgAECn8XAAITAAcJxBaoBACLAQATAAcJxBaoBACLAQAAAA==.Kithara:BAAALgAECgEJAwAAAA==.',
Ko='Kovy:BAAALgAFFAIJAgAAAA==.Kovya:BAAALgADCgYJBwAAAA==.',
Kr='Krelel:BAAALgADCgIJAgAAAA==.Krukar:BAAALgADCgYJDAAAAA==.',
Ky='Kydroga:BAAALgAECgYJEAAAAA==.Kynaria:BAAALgADCgMJAwAAAA==.Kynsia:BAAALgADCgQJBQAAAA==.',
La='Lamörak:BAABLgAECn8ZAAIGAAcJVRsaHwDPAQAGAAcJVRsaHwDPAQAAAA==.Landrick:BAABLgAECn8fAAINAAgJ9hWpGwDiAQANAAgJ9hWpGwDiAQAAAA==.Lastotem:BAAALgADCgEJAQAAAA==.Lastshot:BAAALgAECgMJAwAAAA==.Latest:BAAALgADCgQJBAAAAA==.Lavasaurus:BAAALgAECgYJEQAAAA==.',
Le='Leafstorm:BAAALgAECgUJDQAAAA==.Lehala:BAAALgADCgQJBAAAAA==.Lektar:BAAALgAECgQJBAABLgAECgYJEwABAAAAAA==.Leloosh:BAAALgADCgkJDAABLgAFFAIJAgABAAAAAA==.Lemon:BAABLgAECn8UAAITAAYJnQjkCwDiAAATAAYJnQjkCwDiAAAAAA==.Leokenoso:BAABLgAECn8UAAIjAAYJqBCNCAAkAQAjAAYJqBCNCAAkAQAAAA==.Lessalia:BAAALgADCgMJBgAAAA==.Lewd:BAAALgAECgIJAgAAAA==.',
Li='Lifebloomz:BAABLgAECn8UAAIfAAcJ6wmKMQAVAQAfAAcJ6wmKMQAVAQAAAA==.Lifesabeach:BAAALgAECgEJAQAAAA==.Lilfluffcc:BAAALgAECgQJBAAAAA==.Lissana:BAAALgADCgUJBQAAAA==.',
Lo='Lockward:BAAALgAECgIJAQAAAA==.Lorblor:BAAALgAECgQJBAAAAA==.Lorerun:BAAALgADCgUJCAAAAA==.Lowang:BAABLgAECn8ZAAIPAAgJ4BM3FwBGAQAPAAgJ4BM3FwBGAQAAAA==.Lowmein:BAAALgAECgYJDQAAAA==.',
Lu='Lucÿfer:BAAALgAECgIJAwAAAA==.Lumie:BAAALgAECgEJAQAAAA==.Luminisx:BAAALgADCgMJAwAAAA==.Lunafox:BAABLgAECn8XAAIFAAYJqCGeDwD8AQAFAAYJqCGeDwD8AQAAAA==.Lunamae:BAAALgAECgYJDwAAAA==.Lupacho:BAAALgAECgQJBwAAAA==.Luvvyyaa:BAABLgAECn8lAAMXAAkJ/B22CADAAgAXAAkJ/B22CADAAgAkAAIJzwULLwBaAAAAAA==.Luvyya:BAAALgAECgUJDQABLgAECgkJJQAXAPwdAA==.Luvyyaa:BAAALgADCgQJBAABLgAECgkJJQAXAPwdAA==.',
Ly='Lyrinaku:BAABLgAECn8UAAIXAAcJUxVCFwBSAQAXAAcJUxVCFwBSAQAAAA==.Lythomancer:BAABLgAECn8UAAITAAYJeBAPDADgAAATAAYJeBAPDADgAAAAAA==.',
Ma='Maddeena:BAAALgAECgUJDQAAAA==.Maddy:BAAALgAECgcJEgAAAA==.Maelyssa:BAAALgADCgMJAwAAAA==.Magicmangge:BAAALgADCgYJBgABLgAFFAEJAQABAAAAAA==.Makeitclap:BAAALgAECgYJBgABLgAECgYJGgAcAOoQAA==.Malidian:BAABLgAECn8WAAIKAAgJ/Q5+LgAqAQAKAAgJ/Q5+LgAqAQAAAA==.Matchadaddy:BAAALgAECgEJAQAAAA==.Maxohlx:BAACLgAFFH8LAAIMAAQJWwixIAAfAQAMAAQJWwixIAAfAQAuAAQKfyMAAgwACQlFF9oZALoCAAwACQlFF9oZALoCAAAA.',
Mc='Mcmercie:BAAALgAECgMJAwAAAA==.',
Me='Mechacooter:BAAALgAECgYJBgAAAA==.Meeko:BAAALgADCgUJBQABLgAFFAYJDQAVAAUZAA==.Megahertz:BAAALgADCgEJAQAAAA==.Megg:BAAALgADCgcJDAAAAA==.Meilia:BAAALgADCgUJBwAAAA==.Mekari:BAABLgAECn8eAAIOAAgJ1xtzBgCZAgAOAAgJ1xtzBgCZAgAAAA==.Melchiorr:BAABLgAECn8cAAISAAYJwBvGBgDsAQASAAYJwBvGBgDsAQAAAA==.Melignant:BAAALgADCgEJAQAAAA==.Melosia:BAAALgADCgQJBwAAAA==.Melynne:BAABLgAECn8lAAMFAAgJXBQIDwACAgAFAAgJXBQIDwACAgAEAAIJeATBgQBBAAAAAA==.Memmel:BAAALgADCgMJAwAAAA==.Meredeath:BAAALgAECgcJDQAAAA==.',
Mi='Micro:BAAALgAECggJEAAAAA==.Microslash:BAAALgADCgMJAwABLgAECggJEAABAAAAAA==.Minsoo:BAAALgAECgYJEQAAAA==.Mistblade:BAAALgAECgQJBQABLgAECgYJDAABAAAAAA==.Miststriker:BAAALgAECgUJCQAAAA==.',
Ml='Mlrglett:BAABLgAECn8iAAMYAAgJ6CBRAQCNAgAYAAgJ6CBRAQCNAgAHAAEJihMShgAqAAAAAA==.Mlrglo:BAAALgADCgYJBgAAAA==.',
Mo='Moisturizeme:BAAALgADCgkJDQAAAA==.Mojomaker:BAAALgAECgUJDAAAAA==.Moojitsu:BAAALgADCgMJAwAAAA==.Mormegil:BAABLgAECn8WAAIQAAYJliENCACaAQAQAAYJliENCACaAQAAAA==.Moshimoshi:BAACLgAFFH8IAAIFAAMJJg4YGwC6AAAFAAMJJg4YGwC6AAAuAAQKfxsAAwQACAmXG2MbADcCAAQABwkQHWMbADcCAAUABwlFB3hRAD8BAAAA.',
Mu='Muffinlord:BAAALgAECgYJEQAAAA==.Munkeebutt:BAABLgAECn8ZAAQOAAgJxgfMFQAWAQAOAAcJ5QTMFQAWAQADAAcJVQcLUwD/AAACAAEJsQsp1QAwAAAAAA==.Munkeefase:BAAALgADCgEJAQAAAA==.',
Na='Naberius:BAAALgAECgEJAQAAAA==.Naillil:BAAALgAECgEJAQAAAA==.Namiiswan:BAAALgADCgMJBQAAAA==.Natsuki:BAAALgADCgUJBwAAAA==.',
Ne='Nefarius:BAAALgAECgUJBQAAAA==.Neflite:BAABLgAECn8UAAITAAcJcwYMMgDwAAATAAcJcwYMMgDwAAAAAA==.Nelfie:BAAALgAECgEJAQAAAA==.Nessará:BAAALgAECgMJBAAAAA==.',
Ni='Nineõseven:BAABLgAECn8YAAIlAAcJixN9IADVAQAlAAcJixN9IADVAQABLgAECgEJAQABAAAAAA==.Ninjapro:BAAALgAECgEJAQAAAA==.Nixia:BAAALgAECgQJBAAAAA==.',
No='Nodiddy:BAAALgADCgYJBgABLgAECgcJIwAcAPQhAA==.',
Nu='Nuraga:BAABLgAECn8eAAImAAcJ+iPVBwCpAgAmAAcJ+iPVBwCpAgAAAA==.',
Ob='Obeeone:BAAALgAECgEJAQAAAA==.',
On='Onasta:BAABLgAECn8aAAINAAcJ2B8YIgC7AQANAAcJ2B8YIgC7AQAAAA==.Onelastkiss:BAAALgAECgEJAQAAAA==.',
Op='Oprahheals:BAAALgAECgYJDAAAAA==.',
Or='Oreobeer:BAAALgAECgEJAQAAAA==.Oreomonster:BAAALgAECgQJBQAAAA==.Orquesta:BAAALgAECgEJAgAAAA==.',
Pa='Paccer:BAAALgAECgEJAQAAAA==.Pacerx:BAAALgADCgYJBgAAAA==.Pandaemonia:BAABLgAECn8dAAIjAAgJXgmOEgApAQAjAAgJXgmOEgApAQAAAA==.Pandakyle:BAAALgAECgUJEQAAAA==.Pandexander:BAAALgADCgMJAwAAAA==.Parts:BAABLgAECn8iAAIcAAgJtCHwEQBMAgAcAAgJtCHwEQBMAgAAAA==.Patchmen:BAAALgAECgQJBAAAAA==.Pattilicious:BAABLgAECn8eAAIGAAgJyArJWwD/AAAGAAgJyArJWwD/AAAAAA==.',
Pe='Pepsizero:BAAALgAECgMJBgAAAA==.',
Ph='Phlesh:BAAALgAECgEJAQAAAA==.Phlvrabies:BAAALgADCgMJBQAAAA==.Phonedin:BAABLgAECn8jAAMWAAkJERmbBgCIAgAWAAkJERmbBgCIAgAUAAMJBhcWSQCyAAAAAA==.Phoënix:BAAALgAFFAEJAgAAAA==.',
Pi='Pieglaive:BAABLgAECn8eAAMLAAgJRiGZAgCHAgALAAgJRiGZAgCHAgAKAAIJuhZYwwB2AAAAAA==.Pierres:BAAALgAECgYJBwAAAA==.Piondelth:BAAALgAECgcJEQAAAA==.',
Pl='Plantman:BAAALgAECgMJBAAAAA==.',
Po='Poofort:BAAALgADCgEJAQAAAA==.Pooner:BAAALgADCgMJAwAAAA==.Postoak:BAAALgAECgUJCgAAAA==.Powerochrist:BAABLgAECn8bAAIZAAgJsQ6SFQCmAQAZAAgJsQ6SFQCmAQAAAA==.',
Pr='Proxzy:BAAALgAECgcJBwAAAA==.',
Pu='Pubessalad:BAAALgAECgkJCgAAAA==.Puddin:BAAALgADCgQJBgAAAA==.Puffytaco:BAAALgADCgEJAgABLgAECggJGQAGAOscAA==.',
Qu='Qualek:BAABLgAECn8XAAImAAkJMRJcEAADAgAmAAkJMRJcEAADAgAAAA==.Quilue:BAAALgAECggJEwAAAA==.',
Ra='Rannmagnison:BAABLgAECn8aAAIGAAYJPweoYgDtAAAGAAYJPweoYgDtAAAAAA==.Raquoon:BAAALgAECgUJDAAAAA==.Ratfu:BAAALgADCgcJDQAAAA==.Razjin:BAABLgAECn8YAAIFAAgJ7CPuCQDaAgAFAAgJ7CPuCQDaAgAAAA==.',
Re='Reapér:BAAALgAECgkJBQAAAA==.Reze:BAABLgAFFH8KAAIgAAMJphbuCQD8AAAgAAMJphbuCQD8AAABLgAFFAgJIQALAE8fAA==.',
Rh='Rhaeynera:BAABLgAECn8WAAIWAAYJZgWkCQDbAAAWAAYJZgWkCQDbAAAAAA==.',
Ri='Riezen:BAAALgAECgEJAgAAAA==.Ringol:BAAALgAECgQJCgABLgAECgYJDgABAAAAAA==.Rinorik:BAABLgAECn8mAAMMAAgJZhwiDwAwAgAMAAgJ+BsiDwAwAgATAAYJCRn3FACjAQAAAA==.Rizzdor:BAAALgADCgcJCAABLgAECggJEQABAAAAAA==.',
Ro='Rockbiter:BAAALgAECgEJAgAAAA==.Rockhhard:BAABLgAECn8ZAAIFAAgJLh/+CwArAgAFAAgJLh/+CwArAgAAAA==.Roeken:BAABLgAECn8ZAAIbAAgJlw1YFgCAAQAbAAgJlw1YFgCAAQAAAA==.Rollingman:BAAALgAECgUJCQAAAA==.',
Ru='Rudyrots:BAAALgAECgEJAQABLgAFFAEJAgABAAAAAA==.Rudyshoots:BAAALgAFFAEJAgAAAA==.',
Ry='Rygaard:BAABLgAECn8mAAImAAgJsB50BAAoAgAmAAgJsB50BAAoAgAAAA==.Ryutiz:BAABLgAECn8jAAIDAAgJ7SFcAgAuAgADAAgJ7SFcAgAuAgAAAA==.Ryward:BAAALgADCgcJBwAAAA==.Ryyuk:BAAALgAECgYJBgABLgAECgYJDAABAAAAAA==.',
Sa='Sacridas:BAAALgAECgEJAQABLgAECggJIwADAO0hAA==.Sako:BAAALgADCgUJCgAAAA==.Samsó:BAAALgAECggJEAAAAA==.Sapharina:BAABLgAECn8oAAIkAAgJbxjNBQBXAgAkAAgJbxjNBQBXAgAAAA==.Sassgrip:BAAALgADCgEJAQABLgAECgYJDAABAAAAAA==.Sassier:BAAALgAECgYJDAAAAA==.',
Sc='Scarcy:BAACLgAFFH8IAAIIAAMJBhFtDgAIAQAIAAMJBhFtDgAIAQAuAAQKfygAAggACQlYGa4QAJ0CAAgACQlYGa4QAJ0CAAAA.',
Se='Seacotton:BAAALgAECgYJCgAAAA==.Searfang:BAACLgAFFH8HAAIEAAMJgQ2wEwDfAAAEAAMJgQ2wEwDfAAAuAAQKfyIAAwQACQncGngUAHsCAAQACQncGngUAHsCAAUAAQleE9BeADkAAAAA.Seariel:BAAALgAECgUJBgAAAA==.Selestra:BAAALgAFFAIJAgAAAA==.Seraphymm:BAAALgADCgEJAQAAAA==.',
Sh='Shadowjacker:BAACLgAFFH8HAAIKAAMJyBsEHQD3AAAKAAMJyBsEHQD3AAAuAAQKfy8AAgoACQmMIIYHAFEDAAoACQmMIIYHAFEDAAAA.Shadowmidget:BAABLgAECn8UAAIMAAgJWhacVwDBAQAMAAgJWhacVwDBAQAAAA==.Shadrielis:BAABLgAECn8fAAMkAAgJkRwxBACSAgAkAAgJkRwxBACSAgAXAAIJVQ3FbgBsAAAAAA==.Shanlao:BAAALgAECgIJAgABLgAFFAQJDAAMAD4MAA==.Shirkka:BAAALgADCgMJBAAAAA==.Shurihito:BAABLgAECn8YAAIGAAgJ8hlBMQBeAgAGAAgJ8hlBMQBeAgAAAA==.',
Si='Sieron:BAABLgAECn8UAAINAAYJ/RzHKgCQAQANAAYJ/RzHKgCQAQAAAA==.Silaslunark:BAAALgAECgcJCAAAAA==.Sixpack:BAAALgAECggJEgAAAA==.',
Sk='Skarigar:BAAALgADCggJCwAAAA==.Skeeterson:BAAALgADCgUJBwAAAA==.Skiððles:BAAALgAECgYJBgABLgAECggJFgAEAMkWAA==.Skytec:BAAALgADCgMJAwAAAA==.Skëëts:BAAALgAECgYJEgAAAA==.Skùrvypete:BAAALgADCgEJAQABLgAECggJFgAEAMkWAA==.',
Sl='Slampoof:BAAALgAECgEJAgAAAA==.Slamslayer:BAAALgADCgIJAwAAAA==.Sleez:BAAALgAECgYJDAAAAA==.Sloodraga:BAAALgADCgYJBgAAAA==.',
Sm='Smallgregory:BAAALgAECgYJDAAAAA==.',
Sn='Sneakdead:BAAALgAECgQJBAABLgAECgYJCgABAAAAAA==.Sneakerzz:BAAALgADCgQJBAAAAA==.Sneakfury:BAAALgAECgYJCgAAAA==.Sneeler:BAAALgAECgEJAQAAAA==.Snowscayia:BAABLgAECn8oAAMHAAgJMhYqJwDFAQAHAAgJMhYqJwDFAQAfAAcJ9RQ9OwC4AQAAAA==.',
So='Solanar:BAABLgAECn8dAAIZAAcJryLuEgB7AgAZAAcJryLuEgB7AgAAAA==.Solmina:BAABLgAECn8eAAIcAAgJyRtcGAAbAgAcAAgJyRtcGAAbAgAAAA==.Somniatis:BAAALgAECgEJAQAAAA==.Soulciopath:BAAALgAECgUJCAAAAA==.',
Sp='Spicypants:BAAALgADCgMJAwAAAA==.Spicytaco:BAAALgAECgIJBQABLgAECggJGQAGAOscAA==.Spookuleli:BAAALgADCgQJBAAAAA==.Sprinklewiz:BAAALgADCgMJAwAAAA==.',
Sq='Squadie:BAABLgAECn8bAAICAAgJJAaBLwBTAQACAAgJJAaBLwBTAQAAAA==.Squanchs:BAACLgAFFH8JAAIFAAMJVBtvEwD0AAAFAAMJVBtvEwD0AAAuAAQKfx0AAwUACQlgH7YDAM4CAAUACQlgH7YDAM4CAAQAAQkGAPJcAAEAAAEuAAQKBwkcAB8AkxsA.Squanchy:BAABLgAECn8cAAIfAAcJkxsKIgBxAQAfAAcJkxsKIgBxAQAAAA==.Squisquee:BAAALgADCgcJBwAAAA==.',
Sr='Srbojangles:BAAALgADCgYJBwABLgAECgcJIwAcAPQhAA==.Srry:BAABLgAECn8VAAIbAAcJrxrQKQATAgAbAAcJrxrQKQATAgAAAA==.',
St='Stinkvile:BAAALgAECgEJAQAAAA==.Stonebraid:BAAALgADCgEJAQAAAA==.Sturdy:BAAALgADCgEJAQAAAA==.',
Su='Sukuna:BAAALgAECgYJCAAAAA==.Sundance:BAAALgAECgYJCwAAAA==.Surmise:BAACLgAFFH8NAAIcAAQJsh4YEgB3AQAcAAQJsh4YEgB3AQAuAAQKfx8AAxwACAnmI8sYABYDABwACAlrIssYABYDAB4ABAlSIDsEACcBAAAA.Sust:BAAALgAECgUJBQABLgAFFAQJDQAcALIeAA==.',
Sw='Swayzeetrain:BAABLgAECn8UAAMGAAcJ7RgmZgC0AQAGAAcJ7RgmZgC0AQAZAAYJRB/cNgCfAQAAAA==.',
Ta='Tabius:BAABLgAECn8fAAMdAAgJsR3XBADXAQAdAAgJsR3XBADXAQAHAAMJvw7mKwCvAAAAAA==.Talkingtaco:BAABLgAECn8ZAAIGAAgJ6xw9GQDzAQAGAAgJ6xw9GQDzAQAAAA==.Taln:BAAALgADCgUJBQABLgAECgYJFgAQAJYhAA==.Talìa:BAAALgADCgIJAgAAAA==.Tareul:BAAALgADCgIJAgAAAA==.Tarn:BAAALgAECgkJCgAAAA==.',
Te='Temok:BAAALgAECgUJDQAAAA==.',
Th='Theabyss:BAAALgADCgIJAgABLgADCgcJEwABAAAAAA==.Thiccbush:BAAALgADCgEJAQAAAA==.Thirielnet:BAAALgAECgEJAQAAAA==.Thorisdead:BAAALgADCgMJAwABLgAECgUJCQABAAAAAA==.Thorkell:BAAALgADCgUJBQAAAA==.',
Ti='Tinkaballah:BAAALgAECgcJDgAAAA==.Tipy:BAAALgADCgUJBQAAAA==.',
To='Tore:BAACLgAFFH8GAAICAAMJBhYuFQCwAAACAAMJBhYuFQCwAAAuAAQKfyQAAgIACAk8IqoJAPwCAAIACAk8IqoJAPwCAAAA.Totemangge:BAAALgAFFAEJAQAAAA==.',
Tr='Trifectas:BAAALgADCgcJCwAAAA==.Trinadel:BAABLgAECn8dAAIHAAgJpx0sDwCtAgAHAAgJpx0sDwCtAgAAAA==.Träitors:BAAALgADCgcJEwAAAA==.Tråitors:BAABLgAECn8jAAMMAAYJmiDrHADGAQAMAAYJmiDrHADGAQATAAEJAAAqZQBFAAABLgADCgcJEwABAAAAAA==.',
Ts='Tsarevich:BAAALgAECgUJDAAAAA==.',
Tu='Tugtheshaman:BAABLgAECn8dAAIFAAgJohgoGgBGAgAFAAgJohgoGgBGAgAAAA==.',
Tw='Twileaf:BAABLgAECn8aAAIfAAYJ0wcSQwDEAAAfAAYJ0wcSQwDEAAAAAA==.Twoinchisbig:BAABLgAECn8zAAImAAgJ9RjKBgDcAQAmAAgJ9RjKBgDcAQAAAA==.',
Ty='Typhoidmary:BAABLgAECn8XAAMMAAgJhAl+ggBVAQAMAAcJhAl+ggBVAQATAAEJAAADdgAuAAABLgAECgYJBgABAAAAAA==.',
['Té']='Térror:BAAALgAECgcJDwAAAA==.',
Un='Uncool:BAAALgADCgEJAQABLgAECgEJAQABAAAAAA==.Unholyz:BAAALgAECgQJBAAAAA==.',
Ur='Ursoc:BAABLgAECn8nAAMfAAgJEhXmKgA3AQAfAAYJSBHmKgA3AQAHAAcJkg7QHQAOAQAAAA==.Urteg:BAAALgADCgYJCwAAAA==.',
Uu='Uub:BAAALgAECgIJAgAAAA==.',
Va='Vairekor:BAAALgADCggJDgABLgAFFAQJDAAMAD4MAA==.Valdria:BAAALgADCgUJBQAAAA==.Vanillaçake:BAAALgAECgEJAgAAAA==.Vanishja:BAAALgAECgYJCgAAAA==.Varkbyte:BAAALgAECgUJDAAAAA==.Varrik:BAACLgAFFH8FAAMbAAIJ0xuOFQC6AAAbAAIJ0xuOFQC6AAAnAAIJ4wiZDACWAAAuAAQKfyYAAxsACAnjIpIJABUDABsACAnjIpIJABUDACcABgmYG1AHAJ0BAAAA.',
Ve='Vec:BAAALgAECgYJDQAAAA==.Velamor:BAABLgAECn8VAAMjAAYJIwvwCwDWAAAjAAYJ3grwCwDWAAALAAMJygkzVQCTAAAAAA==.',
Vo='Volieu:BAABLgAECn8VAAIeAAcJjxAMAwBrAQAeAAcJjxAMAwBrAQAAAA==.Volklin:BAAALgAECggJEgAAAA==.Voyageurs:BAAALgAECgYJDwAAAA==.',
Vy='Vyrka:BAAALgAECgMJBwAAAA==.',
Wa='Wallstreet:BAAALgAECgUJBQAAAA==.Waterdweller:BAAALgAECgEJAQAAAA==.',
We='Wegl:BAAALgAECgUJBwAAAA==.Werewithal:BAAALgADCgUJBQABLgAECgcJFQAOAPYRAA==.Wesleypipes:BAAALgAECgEJAQAAAA==.Wetfloorsign:BAAALgAECgYJEQAAAA==.',
Wh='Wholeymilk:BAAALgADCgMJAwAAAA==.',
Wi='Wiindsslashh:BAAALgADCgUJBwAAAA==.Wilbur:BAAALgADCgQJBQAAAA==.Windslash:BAAALgADCgYJAwAAAA==.',
Wo='Wonderx:BAAALgADCgIJAgAAAA==.Wonyoung:BAACLgAFFH8JAAIXAAQJFBwHBQBSAQAXAAQJFBwHBQBSAQAuAAQKfyUAAhcACQkTItkBAFgDABcACQkTItkBAFgDAAAA.',
Wu='Wuthrad:BAAALgADCgQJBAAAAA==.',
Xa='Xala:BAAALgAECgYJBgAAAA==.Xalaz:BAACLgAFFH8KAAMMAAQJjAxfHwAkAQAMAAQJgAxfHwAkAQATAAEJVwJUGgBGAAAuAAQKfx0AAwwACQlYHG42ADICAAwACAlYHG42ADICABMAAgkLFF5SAHcAAAAA.Xanaris:BAAALgADCgEJAQABLgAFFAIJCQANACYmAA==.Xandumbra:BAAALgADCgEJAQAAAA==.Xarosea:BAACLgAFFH8JAAIGAAQJyREiEQBBAQAGAAQJyREiEQBBAQAuAAQKfykAAgYABwk4JPcYANMCAAYABwk4JPcYANMCAAAA.',
Xe='Xelojr:BAAALgADCgkJHAAAAA==.',
Xh='Xhael:BAAALgADCgEJAQAAAA==.',
Xi='Xia:BAABLgAECn8iAAIXAAgJVxvnCAAaAgAXAAgJVxvnCAAaAgAAAA==.',
Xo='Xoilkick:BAAALgAECgUJBQAAAA==.Xoilwings:BAAALgAECgEJAQAAAA==.Xooiill:BAAALgAECgcJDQAAAA==.',
Xp='Xpacer:BAAALgAECgYJCwAAAA==.',
Ye='Yekira:BAAALgADCgEJAgAAAA==.Yellowsnøw:BAABLgAECn8ZAAIcAAgJ3hD2LACwAQAcAAgJ3hD2LACwAQAAAA==.',
Yu='Yumeshade:BAAALgAECgUJCQAAAA==.',
Za='Zal:BAAALgAECgYJBgAAAA==.Zamari:BAAALgADCgYJFQAAAA==.Zanzabar:BAABLgAECn8VAAIdAAkJwwrDEACgAQAdAAkJwwrDEACgAQAAAA==.Zathmage:BAAALgADCgMJAwAAAA==.Zaxin:BAAALgAECgYJDwAAAA==.',
Ze='Zelfie:BAAALgADCgUJBQAAAA==.Zellda:BAAALgAECgQJBAAAAA==.Zeros:BAAALgAECgYJDwAAAA==.',
Zo='Zoerina:BAAALgAECgUJCAAAAA==.Zoobilong:BAAALgAECgUJDwAAAA==.',
Zx='Zxak:BAABLgAECn8jAAILAAgJmiNKAQDfAgALAAgJmiNKAQDfAgAAAA==.',
Zy='Zyahk:BAAALgADCgQJBQAAAA==.Zynn:BAAALgAECgEJAgAAAA==.',
['Zë']='Zën:BAAALgAECgEJAQABLgAECggJIAAKAAsVAA==.',
['Ða']='Ðashÿ:BAAALgAECgMJAwABLgAECgYJCQABAAAAAA==.',
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
