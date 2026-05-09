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

local lookup = {'Unknown-Unknown','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Elemental','Shaman-Restoration','Priest-Holy','Paladin-Retribution','Druid-Balance','Rogue-Subtlety','Rogue-Assassination','DemonHunter-Devourer','DemonHunter-Havoc','Warlock-Demonology','DeathKnight-Unholy','Hunter-Survival','Mage-Frost','Monk-Brewmaster','DeathKnight-Blood','Monk-Mistweaver','Warlock-Affliction','Warlock-Destruction','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Druid-Guardian','Paladin-Holy','Paladin-Protection','Warrior-Fury','Druid-Feral','Mage-Arcane','Druid-Restoration','Monk-Windwalker','Shaman-Enhancement','DemonHunter-Vengeance','Priest-Discipline','Priest-Shadow','Rogue-Outlaw','DeathKnight-Frost','Warrior-Protection','Warrior-Arms',}
local provider = {region='US',realm='Fizzcrank',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abandonhope:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.',
Ac='Accuser:BAAALgADCgEJAQAAAA==.Acky:BAAALgADCgUJBQAAAA==.',
Ad='Adwen:BAAALgAECgUJDwAAAA==.',
Ae='Aenimal:BAAALgADCgEJAQABLgADCgUJBQABAAAAAA==.Aer:BAAALgADCgkJCQAAAA==.Aeronemon:BAAALgAECgEJAgAAAA==.',
Ai='Airill:BAAALgADCgQJBQAAAA==.',
Ak='Akforty:BAABLgAECn8fAAMCAAkJJCHNCgDvAgACAAkJJCHNCgDvAgADAAIJoBV3eABfAAAAAA==.Akittymeow:BAABLgAECn8ZAAMEAAgJARBoLQABAQAEAAcJYg9oLQABAQAFAAMJjwU4YAB6AAAAAA==.',
Al='Aldredevon:BAAALgAECgEJAQAAAA==.Aleshock:BAAALgAECgYJCwAAAA==.Alidar:BAAALgAECgcJEgAAAA==.Alphaboner:BAAALgADCgIJAgAAAA==.Altairis:BAAALgAECgEJAgAAAA==.Altartoy:BAABLgAECn8WAAIGAAgJ0QrBHwBKAQAGAAgJ0QrBHwBKAQAAAA==.Althunter:BAACLgAFFH8GAAIDAAMJfBkPCwANAQADAAMJfBkPCwANAQAuAAQKfxkAAgMACAlSIfEDAAwCAAMACAlSIfEDAAwCAAAA.',
Am='Amelina:BAAALgAECgUJCQAAAA==.Amorir:BAABLgAECn8uAAIHAAgJOhJ1OwCUAQAHAAgJOhJ1OwCUAQAAAA==.Amorydalias:BAAALgAECgUJBgAAAA==.Amozon:BAAALgADCgEJAQAAAA==.',
An='Anastala:BAABLgAECn8eAAIIAAgJRRQ0EgC1AQAIAAgJRRQ0EgC1AQAAAA==.Angchu:BAAALgADCgQJBAAAAA==.Angelmàker:BAAALgAECgMJBAABLgADCgcJEwABAAAAAA==.Annesta:BAABLgAECn8bAAMJAAgJLxmGEwB4AQAJAAgJ8RiGEwB4AQAKAAEJ+xaUFwBFAAAAAA==.',
Ap='Apostus:BAAALgADCgcJDgAAAA==.Apothica:BAAALgAECgUJBgAAAA==.',
Aq='Aquafox:BAAALgAECgYJEQAAAA==.',
Ar='Archontas:BAABLgAECn8ZAAIIAAYJTh47EgC1AQAIAAYJTh47EgC1AQAAAA==.Ariodh:BAABLgAECn8lAAMLAAgJCibSCACYAgALAAgJCibSCACYAgAMAAUJpB9ZJACaAQAAAA==.Arkaline:BAAALgAECgEJAQAAAA==.Artuarry:BAACLgAFFH8QAAINAAQJng1bLQAUAQANAAQJng1bLQAUAQAuAAQKfyYAAg0ACQk/H4MJALACAA0ACQk/H4MJALACAAAA.Aryndus:BAABLgAECn8VAAIHAAkJrxxTDACfAgAHAAkJrxxTDACfAgAAAA==.',
At='Athenà:BAAALgAECgQJBAAAAA==.',
Av='Avocado:BAABLgAECn8jAAMCAAkJnCXBAQA7AwACAAkJHSPBAQA7AwADAAcJQyIdBAADAgAAAA==.',
Ax='Axelaw:BAAALgADCgQJBAAAAA==.',
Ay='Ayrz:BAAALgAECgIJAgAAAA==.',
Az='Azaria:BAAALgADCgIJAgAAAA==.',
Ba='Baddjujumon:BAAALgAECgcJBwAAAA==.Baileyhowl:BAAALgAECgEJAwAAAA==.Bammie:BAAALgADCgYJCgAAAA==.Bananuth:BAAALgAECgIJAwABLgAFFAQJDwAOAEAcAA==.Banthr:BAAALgAECggJEQAAAA==.Barkert:BAAALgADCgEJAQAAAA==.Baroke:BAAALgAECgMJBwABLgAECggJFgAGANEKAA==.Barokoshama:BAAALgAECgcJEQAAAA==.Basaltytaco:BAAALgADCgEJAQAAAA==.Battleworm:BAAALgADCgkJEwABLgAECgcJCgABAAAAAA==.',
Bb='Bbalrd:BAABLgAECn8VAAIOAAgJ7heaLgC/AQAOAAgJ7heaLgC/AQAAAA==.',
Be='Bearglie:BAAALgAECgYJBgAAAA==.Beepers:BAAALgAECgYJBgAAAA==.',
Bi='Bigcow:BAAALgAECgQJBQAAAA==.',
Bl='Blackolives:BAAALgAECgcJCgAAAA==.Blondefu:BAAALgAECgUJCwAAAA==.Bloodybonne:BAAALgADCgcJBwAAAA==.Bloodyell:BAAALgAECgEJAQAAAA==.Bloore:BAAALgAECgMJAwABLgAECggJIwADAO0hAA==.Bluejuly:BAAALgAECgQJBAAAAA==.Blutø:BAAALgAECgEJAwAAAA==.',
Bo='Boflex:BAAALgADCgQJBQAAAA==.Bomboclat:BAAALgAECgUJCwAAAA==.Bonesknows:BAAALgADCgEJAQAAAA==.Boofy:BAAALgAECgIJAgABLgAECggJFAANAFoWAA==.Bowwie:BAACLgAFFH8KAAMCAAQJPRGNKwDrAAAPAAMJGQ2pEADuAAACAAMJZRCNKwDrAAAuAAQKfyMABAIACQkTHi0GACsDAAIACQkTHi0GACsDAA8AAwmZDoQmAMQAAAMAAQkVAxGTACcAAAAA.',
Br='Britney:BAAALgADCgkJCQAAAA==.Bronzé:BAABLgAECn8bAAIQAAUJfiC0TgB+AQAQAAUJfiC0TgB+AQAAAA==.Brotherfrey:BAAALgAECgYJCgAAAA==.Bruish:BAABLgAFFH8MAAIRAAQJtwzEDQAWAQARAAQJtwzEDQAWAQAAAA==.',
Bu='Bubbadoo:BAABLgAECn8ZAAIIAAgJpw0ZGQBwAQAIAAgJpw0ZGQBwAQAAAA==.Buddy:BAAALgAECgUJEgABLgAECgYJHAASAJYhAA==.Bulan:BAABLgAECn8tAAITAAgJRiXMAQBXAwATAAgJRiXMAQBXAwAAAA==.',
Bw='Bweninger:BAAALgADCgcJBwAAAA==.',
['Bô']='Bôôsted:BAABLgAECn8WAAIEAAgJyRbcIAAIAgAEAAgJyRbcIAAIAgAAAA==.',
Ca='Caistan:BAAALgADCgYJCAAAAA==.Candypants:BAAALgAECggJEwAAAA==.Caoth:BAAALgAECgYJEwAAAA==.Cappilon:BAAALgAECggJDgAAAA==.Carcus:BAAALgAECgEJAQAAAA==.Cayleedah:BAABLgAECn8fAAIDAAcJ6QcrDgAJAQADAAcJ6QcrDgAJAQAAAA==.Cayssaris:BAAALgAECgUJDQAAAA==.',
Cc='Cc:BAABLgAECn8WAAQUAAYJOxPsDgBCAQAUAAUJ9BPsDgBCAQAVAAYJKwsrIwA+AQANAAQJzRPstQDtAAAAAA==.',
Ce='Ceeti:BAABLgAECn8vAAMWAAkJAyChAwDVAgAWAAkJAyChAwDVAgAXAAIJeAYZQABpAAAAAA==.Celandrelia:BAAALgAECgUJBQABLgAECggJKgAYAFcWAA==.',
Ch='Channeria:BAAALgAECgEJAQAAAA==.Chaoticoreo:BAABLgAECn8rAAMMAAgJYB4cBQBqAgAMAAgJYB4cBQBqAgALAAQJ4w9irQCzAAAAAA==.Chappedlips:BAAALgAECgkJBwAAAA==.Chareyne:BAABLgAECn8ZAAIGAAgJ5BFwJgC5AQAGAAgJ5BFwJgC5AQAAAA==.Cheetor:BAAALgAECgMJAwABLgAECgkJMwAPANwhAA==.Cheezytaco:BAAALgAECgUJBwABLgAECggJHQAHAE0dAA==.Chidge:BAAALgADCggJCwAAAA==.Chikila:BAABLgAECn8UAAIVAAYJLxymBQCfAQAVAAYJLxymBQCfAQAAAA==.Chilliflakez:BAAALgAECgUJEAAAAA==.Chro:BAAALgADCgcJBwAAAA==.',
Ci='Cindezar:BAAALgADCgMJAwAAAA==.',
Cl='Clementyn:BAABLgAECn8WAAIHAAcJNxB3ZAAlAQAHAAcJNxB3ZAAlAQAAAA==.Cleyi:BAABLgAECn8pAAIGAAgJxQ0iGgB7AQAGAAgJxQ0iGgB7AQAAAA==.',
Co='Coldpasta:BAAALgAECgYJDgABLgAFFAIJBAABAAAAAA==.Colonoscopy:BAAALgAECgEJAQAAAA==.Coreyy:BAAALgADCgUJBwAAAA==.Corva:BAACLgAFFH8IAAINAAMJ7w6TQgDWAAANAAMJ7w6TQgDWAAAuAAQKfyoAAg0ACQnoFVkmAM8BAA0ACQnoFVkmAM8BAAAA.Cosairi:BAAALgADCgQJBAAAAA==.Cougztroll:BAABLgAECn8gAAIZAAgJMRa3CwDSAQAZAAgJMRa3CwDSAQAAAA==.',
Cr='Crazaki:BAAALgADCgEJAQAAAA==.',
Cu='Curfluffin:BAAALgADCgEJAQAAAA==.Cuttercupx:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.',
Da='Dahn:BAAALgADCgQJBAAAAA==.Dakadin:BAABLgAECn8jAAMaAAkJ+iPUBgCtAgAaAAkJ+iPUBgCtAgAHAAQJ7Bf1cQAJAQAAAA==.Daranne:BAACLgAFFH8HAAIHAAMJmxWcKAAKAQAHAAMJmxWcKAAKAQAuAAQKfyQAAgcACAkwGhU/ACkCAAcACAkwGhU/ACkCAAAA.Darkenedstar:BAAALgADCgUJBQAAAA==.Darksoulstwo:BAAALgADCgMJAwAAAA==.Dasbeans:BAAALgAFFAIJAwAAAA==.Dashy:BAAALgAECgcJEAAAAA==.Datran:BAAALgADCgUJBQABLgAECgEJAQABAAAAAA==.',
De='Deaduglie:BAABLgAECn8oAAMNAAgJdhYXJQDWAQANAAgJdhYXJQDWAQAVAAEJMQjlcQA0AAAAAA==.Deliandora:BAAALgAECgQJBwAAAA==.Delusional:BAAALgAECgcJDAAAAA==.Delynique:BAAALgADCgEJAQABLgAECggJIwADAO0hAA==.Demonx:BAAALgAECgEJAQAAAA==.Denaric:BAAALgAECgUJDQAAAA==.Destroyevsky:BAAALgAECgQJEAAAAA==.Detonate:BAAALgAECgYJEAAAAA==.',
Dh='Dhvecx:BAAALgAECgUJBgABLgAECgYJDQABAAAAAA==.',
Di='Dilbo:BAAALgAECgEJAgAAAA==.Diomed:BAAALgAECgEJAQAAAA==.Diqon:BAABLgAECn8vAAMOAAkJaxndHgAPAgAOAAkJkhjdHgAPAgASAAcJthTwDwBzAQAAAA==.Disturbedtwo:BAAALgAECgYJCgAAAA==.',
Do='Dolphinz:BAACLgAFFH8LAAIHAAMJyBXCKgAEAQAHAAMJyBXCKgAEAQAuAAQKfygAAwcACAlKIdsTAFsCAAcACAlKIdsTAFsCABsAAgnpCh08AE4AAAAA.Doryadni:BAAALgADCgcJBgAAAA==.',
Dr='Dragonpede:BAABLgAECn85AAIWAAkJFSD2AgDvAgAWAAkJFSD2AgDvAgAAAA==.Dragonwarior:BAABLgAECn8fAAIcAAkJ6hukEADvAQAcAAkJ6hukEADvAQAAAA==.Drakindees:BAAALgAECgQJBAABLgAECgcJJAAQAPQhAA==.Drakkyn:BAAALgAECgUJEgAAAA==.Drakonus:BAAALgAECgQJBAAAAA==.Dread:BAAALgADCgQJBAAAAA==.Drosuu:BAAALgAECgEJAQAAAA==.Druish:BAACLgAFFH8UAAIZAAQJUx/zAQB3AQAZAAQJUx/zAQB3AQAuAAQKfyQAAxkACQkyJqoBADUDABkACQkyJqoBADUDAB0AAgkOD5csAGEAAAAA.Drykkr:BAABLgAECn8jAAIRAAkJkRZrCwALAgARAAkJkRZrCwALAgAAAA==.',
Du='Dullahan:BAAALgAECgUJBgAAAA==.Durrik:BAAALgADCgcJBwAAAA==.',
['Dà']='Dàsh:BAAALgAECgYJBgABLgAECgcJEAABAAAAAA==.',
Ea='Eatrocks:BAAALgADCggJCAAAAA==.',
Ed='Edorn:BAAALgADCgIJAgAAAA==.',
Ef='Efn:BAAALgAECgYJEwAAAA==.',
El='Elcrys:BAAALgAECgcJEAAAAA==.Elion:BAAALgAECgEJAQAAAA==.Ellyra:BAAALgAECgEJAQAAAA==.Elpollo:BAABLgAECn8kAAMQAAcJ9CGNQgBwAgAQAAcJ9CGNQgBwAgAeAAEJshe0HAA6AAAAAA==.Elvar:BAAALgAECgQJCAAAAA==.',
Em='Emmdwemm:BAAALgAECgIJBAAAAA==.',
En='Enoki:BAAALgAECgQJBAAAAA==.',
Ep='Ephelia:BAACLgAFFH8HAAIFAAMJ3Bx+GAALAQAFAAMJ3Bx+GAALAQAuAAQKfxYAAwUACAlGGosiAA8CAAUACAlGGosiAA8CAAQAAQmMA/GUACAAAAAA.Epitome:BAAALgAECggJEgAAAA==.',
Er='Erid:BAAALgAECgcJDgAAAA==.',
Et='Etude:BAAALgADCgEJAQAAAA==.',
Ev='Evelyndel:BAAALgAECgIJAgAAAA==.Evergrey:BAAALgAECgYJCwAAAA==.Evermoons:BAABLgAECn8jAAIfAAkJVhmECgChAgAfAAkJVhmECgChAgAAAA==.',
Fa='Falaria:BAAALgAECgQJBAAAAA==.Falasdaer:BAABLgAECn8SAAILAAgJlyHQBwCpAgALAAgJlyHQBwCpAgAAAA==.Falstaff:BAABLgAECn8WAAIRAAkJyBISDgDmAQARAAkJyBISDgDmAQAAAA==.Fartshooter:BAAALgAECgYJEQAAAA==.Fatterblunt:BAACLgAFFH8QAAIIAAQJuxJGDwA5AQAIAAQJuxJGDwA5AQAuAAQKfyMAAggACQmEH68NAMACAAgACQmEH68NAMACAAAA.',
Fe='Fedner:BAABLgAECn8XAAIFAAcJQg+ELQBfAQAFAAcJQg+ELQBfAQAAAA==.Feldar:BAABLgAECn8hAAIHAAgJsh77FABRAgAHAAgJsh77FABRAgAAAA==.Fend:BAAALgADCgQJBAAAAA==.Feyredarling:BAAALgAECgMJAwAAAA==.',
Fi='Fists:BAACLgAFFH8MAAIRAAQJhhymDABRAQARAAQJhhymDABRAQAuAAQKfyoAAxEABgmEI48WAFQCABEABgmEI48WAFQCACAABAk3EqNUAL4AAAAA.Fizzbeard:BAAALgADCgcJCgAAAA==.Fizzical:BAAALgADCgYJBgAAAA==.Fizzleclaw:BAAALgAECgUJDgAAAA==.Fizzleded:BAAALgAECgQJBQABLgAECgUJDgABAAAAAA==.Fizzleflare:BAAALgADCgkJCQAAAA==.',
Fl='Flightrisk:BAAALgAECgMJBQABLgAECgIJAgABAAAAAA==.Florisa:BAABLgAECn8iAAIHAAgJPBwuHAAeAgAHAAgJPBwuHAAeAgAAAA==.',
Fo='Fordi:BAABLgAECn8lAAMEAAgJrh0DCABdAgAEAAgJrh0DCABdAgAhAAIJLRFGJgBzAAAAAA==.Forendor:BAAALgAECgIJAgAAAA==.Fourdy:BAABLgAECn8oAAIFAAcJCRn0IwCYAQAFAAcJCRn0IwCYAQAAAA==.',
Fr='Fragdoll:BAAALgAECgQJCgAAAA==.Freakinlarry:BAAALgADCgEJAQAAAA==.Freakinoak:BAABLgAECn8aAAIfAAgJrRAvJQCgAQAfAAgJrRAvJQCgAQAAAA==.Free:BAABLgAECn8TAAMLAAgJPQ8RNgBeAQALAAcJPQ8RNgBeAQAiAAUJ9Ap2IACAAAAAAA==.Froost:BAACLgAFFH8HAAIOAAMJqRfMSAD9AAAOAAMJqRfMSAD9AAAuAAQKfxYAAg4ACAnQHOtMAAwCAA4ACAnQHOtMAAwCAAAA.',
Fu='Funkflex:BAAALgAECgEJAQABLgAECggJEwALAD0PAA==.Furvert:BAAALgAECgIJAgAAAA==.Fushi:BAAALgAECgEJAQAAAA==.',
Ga='Gandis:BAAALgAECggJEQAAAA==.Gapper:BAABLgAECn8zAAIPAAkJ3CEeAQAYAwAPAAkJ3CEeAQAYAwAAAA==.Gargodath:BAAALgAECgMJAwAAAA==.',
Gi='Gimbó:BAAALgADCgQJBgAAAA==.',
Gl='Glamour:BAAALgADCgEJAgAAAA==.Glestaar:BAABLgAECn8gAAMCAAgJyBn4HwBFAgACAAgJyBn4HwBFAgADAAIJRQuDfABSAAAAAA==.Glyr:BAAALgAECgYJCgAAAA==.',
Go='Goingrouge:BAAALgAECgEJAwAAAA==.Goldabelle:BAAALgAECgYJCgAAAA==.Gorlami:BAAALgAFFAMJBAAAAA==.Gothelf:BAAALgAFFAIJBAAAAA==.Gothri:BAAALgAECgMJAwABLgAECgYJFAAWAPEUAA==.Gothstraza:BAABLgAECn8UAAIWAAYJ8RT6IwAoAQAWAAYJ8RT6IwAoAQAAAA==.Gottemgood:BAAALgADCgUJBQAAAA==.',
Gr='Grimli:BAABLgAECn8ZAAIFAAkJ3Q0CKQB5AQAFAAkJ3Q0CKQB5AQAAAA==.Growth:BAABLgAECn8WAAMjAAgJ8g4+GwBVAQAjAAYJohA+GwBVAQAkAAcJpwrEHwA+AQAAAA==.',
Gu='Gurthcaptian:BAAALgAECgQJBAAAAA==.',
['Gá']='Gárròsh:BAAALgAECgYJBgAAAA==.',
Ha='Haerin:BAAALgAECgIJAgABLgAFFAQJDQAGAOMfAA==.Harnel:BAABLgAECn8eAAIHAAcJWQO2jgDQAAAHAAcJWQO2jgDQAAAAAA==.Haseo:BAAALgAECgIJAgAAAA==.Hattorihanzo:BAAALgAECgQJBwAAAA==.',
He='Healeymonstr:BAAALgADCgIJAgAAAA==.Healmart:BAAALgAECgUJDQAAAA==.Heartëater:BAAALgADCgYJBgAAAA==.Hellinyoface:BAAALgADCgUJBQAAAA==.',
Hi='Himothyy:BAAALgAECgQJBAAAAA==.',
Ho='Holypeetch:BAAALgADCgYJBgAAAA==.Hoofpics:BAAALgADCgcJCAAAAA==.Hordedefect:BAAALgADCgQJBAABLgAECgIJAgABAAAAAA==.Hoyer:BAAALgAECggJEQAAAA==.',
Im='Impact:BAAALgADCgcJCgAAAA==.',
In='Inflícted:BAAALgAFFAIJAgAAAA==.',
Io='Iove:BAABLgAECn8aAAITAAkJYhUFDAAqAgATAAkJYhUFDAAqAgAAAA==.',
Ja='Jahsahm:BAAALgAECgcJEQAAAA==.Jajung:BAAALgADCgMJAwAAAA==.Jakub:BAAALgAECggJEwABLgAFFAQJCgACAD0RAA==.Jakuren:BAAALgADCgYJBgAAAA==.Jamjam:BAAALgADCgYJCQAAAA==.',
Je='Jesit:BAABLgAECn8WAAIXAAYJoxM5DgBgAQAXAAYJoxM5DgBgAQAAAA==.',
Ji='Jingles:BAAALgADCgYJBgAAAA==.',
Jj='Jjada:BAABLgAECn8VAAMLAAgJmyLoCQCKAgALAAgJlSDoCQCKAgAiAAYJnCGABQBNAgAAAA==.',
Jo='Johnwolf:BAAALgAECgUJDgAAAA==.',
Jy='Jyade:BAABLgAECn8ZAAMKAAcJawriCABEAQAKAAcJDAriCABEAQAlAAUJnwieCAD6AAAAAA==.Jynoria:BAAALgADCgcJDAAAAA==.',
Ka='Kainlok:BAAALgADCgIJAgAAAA==.Kaiserice:BAAALgAECgYJDwAAAA==.Kamarra:BAABLgAECn8UAAIWAAYJkgajNADQAAAWAAYJkgajNADQAAAAAA==.Kamencider:BAABLgAECn8dAAIQAAcJ7hA7UgB0AQAQAAcJ7hA7UgB0AQAAAA==.Kamidala:BAAALgADCgcJCAAAAA==.Kankles:BAABLgAECn8qAAIIAAgJ2yJsAwDSAgAIAAgJ2yJsAwDSAgAAAA==.Katabetta:BAAALgADCgMJAwAAAA==.',
Ke='Kernelpanic:BAACLgAFFH8PAAMOAAQJQBxaIgBbAQAOAAQJQBxaIgBbAQAmAAEJ/gWYCgBDAAAuAAQKfycAAg4ACQn6Ie4MAJ4CAA4ACQn6Ie4MAJ4CAAAA.Kessho:BAAALgAECgYJDwABLgAFFAQJCgACAD0RAA==.Kevynn:BAAALgADCgMJAgAAAA==.Keyoshi:BAAALgAECgYJBgAAAA==.',
Ki='Kickrocks:BAAALgADCgUJBwAAAA==.Kilerforlife:BAAALgAECgYJCwAAAA==.Kilowog:BAAALgADCgUJCAAAAA==.Kilpally:BAAALgAECgYJBwAAAA==.Kintra:BAAALgADCgIJAgAAAA==.Kirin:BAAALgADCgEJAQAAAA==.Kirkle:BAABLgAECn8fAAIVAAgJihp5AgAiAgAVAAgJihp5AgAiAgAAAA==.Kithara:BAAALgAECgEJAwAAAA==.',
Ko='Kovie:BAAALgADCggJCAAAAA==.Kovy:BAAALgAFFAIJAgAAAA==.Kovya:BAAALgADCgYJBwAAAA==.',
Kr='Krelel:BAAALgADCgIJAgAAAA==.Krukar:BAAALgADCgYJDAAAAA==.',
Ku='Kubo:BAAALgAECgYJBgABLgAFFAQJCgACAD0RAA==.',
Ky='Kydroga:BAAALgAECgYJEAAAAA==.Kynaria:BAAALgADCgMJAwAAAA==.Kynsia:BAAALgADCgQJBQAAAA==.',
La='Lamörak:BAABLgAECn8gAAIHAAgJcxxPFgBIAgAHAAgJcxxPFgBIAgAAAA==.Landrick:BAABLgAECn8nAAIOAAgJJhohHwAOAgAOAAgJJhohHwAOAgAAAA==.Lastotem:BAAALgADCgEJAQAAAA==.Lastshot:BAAALgAECgMJAwAAAA==.Latest:BAAALgADCgQJBAAAAA==.Lavasaurus:BAABLgAECn8XAAMXAAYJ2Rn6CgChAQAXAAYJ2Rn6CgChAQAWAAEJlg/AWwAzAAAAAA==.',
Le='Leafstorm:BAAALgAECgUJDQAAAA==.Lehala:BAAALgADCgQJBAAAAA==.Lektar:BAAALgAECgUJBQABLgAECgYJEwABAAAAAA==.Leloosh:BAAALgADCgkJDAABLgAFFAIJBAABAAAAAA==.Lemon:BAABLgAECn8bAAIVAAcJWAlxDQD7AAAVAAcJWAlxDQD7AAAAAA==.Leokenoso:BAABLgAECn8UAAIiAAYJqBDJCwAMAQAiAAYJqBDJCwAMAQAAAA==.Lesclaypool:BAAALgADCgYJBgAAAA==.Lessalia:BAAALgADCgMJBgAAAA==.Lewd:BAAALgAECgIJAgAAAA==.',
Li='Lifebloomz:BAABLgAECn8cAAIfAAgJ9Ql1NgA9AQAfAAgJ9Ql1NgA9AQAAAA==.Lifesabeach:BAAALgAECgEJAQAAAA==.Lilfluffcc:BAAALgAECgQJBAAAAA==.Lissana:BAAALgADCgUJBQAAAA==.',
Lo='Lockward:BAAALgAECgIJAQAAAA==.Lorblor:BAAALgAECggJDAAAAA==.Lorerun:BAAALgADCgUJCAAAAA==.Lowang:BAABLgAECn8bAAIRAAgJMBQ+HABRAQARAAgJMBQ+HABRAQAAAA==.Lowmein:BAAALgAECgYJDgAAAA==.',
Lu='Lucÿfer:BAAALgAECgIJAwAAAA==.Lumie:BAAALgAECgUJBgAAAA==.Luminisx:BAAALgADCgMJAwAAAA==.Lunafox:BAABLgAECn8eAAIFAAgJ8h0RCQCbAgAFAAgJ8h0RCQCbAgAAAA==.Lunamae:BAAALgAECgcJEQAAAA==.Lupacho:BAAALgAECgQJBwAAAA==.Luvvyyaa:BAABLgAECn8uAAMGAAkJ+h2yCADAAgAGAAkJ+h2yCADAAgAjAAYJUQjzIQAbAQAAAA==.Luvyya:BAAALgAECgUJDQABLgAECgkJLgAGAPodAA==.Luvyyaa:BAAALgADCgQJBAABLgAECgkJLgAGAPodAA==.',
Ly='Lyrinaku:BAABLgAECn8UAAIGAAcJUxUbIABHAQAGAAcJUxUbIABHAQAAAA==.Lythomancer:BAABLgAECn8cAAIVAAgJbA4TCABeAQAVAAgJbA4TCABeAQAAAA==.',
Ma='Maddeena:BAAALgAECgUJEgAAAA==.Maddy:BAABLgAECn8XAAIgAAcJ0B9wCgATAgAgAAcJ0B9wCgATAgAAAA==.Maelyssa:BAAALgADCgMJAwAAAA==.Magicmangge:BAAALgADCgYJBgABLgAFFAEJAQABAAAAAA==.Makeitclap:BAAALgAECgMJBAABLgAECgcJHQAQAO4QAA==.Malidian:BAABLgAECn8YAAILAAgJBg/wRQAnAQALAAgJBg/wRQAnAQAAAA==.Matchadaddy:BAAALgAECgEJAwAAAA==.Maxohlx:BAACLgAFFH8PAAINAAQJQgkJMgAHAQANAAQJQgkJMgAHAQAuAAQKfyUAAg0ACQkXGNgZALoCAA0ACQkXGNgZALoCAAAA.',
Mc='Mcmercie:BAAALgAECgMJAwAAAA==.',
Me='Mechacooter:BAAALgAECgcJCgAAAA==.Meeko:BAAALgADCgUJBQABLgAFFAYJDgAXAEcZAA==.Megahertz:BAAALgADCgEJAQAAAA==.Megg:BAAALgADCgcJDAAAAA==.Meilia:BAAALgADCgUJBwAAAA==.Mekari:BAABLgAECn8nAAIPAAkJthtpBAB/AgAPAAkJthtpBAB/AgAAAA==.Melchiorr:BAABLgAECn8jAAIUAAcJVxjHBgDsAQAUAAcJVxjHBgDsAQAAAA==.Melignant:BAAALgADCgEJAQAAAA==.Melosia:BAAALgADCgQJBwAAAA==.Melynne:BAABLgAECn8tAAMFAAgJyxURFQALAgAFAAgJyxURFQALAgAEAAIJeAS9gQBBAAAAAA==.Memmel:BAAALgADCgMJAwAAAA==.Meredeath:BAABLgAECn8UAAIIAAgJKw37JAAUAQAIAAgJKw37JAAUAQAAAA==.',
Mi='Micro:BAAALgAECggJEgAAAA==.Microslash:BAAALgADCgMJAwABLgAECggJEgABAAAAAA==.Minsoo:BAABLgAECn8XAAITAAcJ4hzBDAAdAgATAAcJ4hzBDAAdAgAAAA==.Mistblade:BAAALgAECgQJCQABLgAECggJEwALAD0PAA==.Miststriker:BAAALgAECgUJCQAAAA==.',
Ml='Mlrglett:BAABLgAECn8qAAMZAAgJhiE7AgCbAgAZAAgJhiE7AgCbAgAIAAEJihMXhgAqAAAAAA==.Mlrglo:BAAALgADCgcJCQAAAA==.',
Mo='Moisturizeme:BAAALgADCgkJDgAAAA==.Mojomaker:BAAALgAECgUJEAAAAA==.Moojitsu:BAAALgADCgMJAwAAAA==.Mormegil:BAABLgAECn8cAAISAAYJliE/DwAYAgASAAYJliE/DwAYAgAAAA==.Moshimoshi:BAACLgAFFH8LAAMFAAQJqBDrGQAEAQAFAAQJqBDrGQAEAQAEAAEJIQOFLwA/AAAuAAQKfxsAAwQACAmXG2IbADcCAAQABwkQHWIbADcCAAUABwlFB29RAD8BAAAA.',
Mu='Muffinlord:BAAALgAECgYJEQAAAA==.Munkeebutt:BAABLgAECn8bAAQPAAgJ4AffHQATAQAPAAcJ/QTfHQATAQADAAcJWwchUwD/AAACAAEJsQsr1QAwAAAAAA==.Munkeefase:BAAALgADCgEJAQAAAA==.',
Na='Naberius:BAAALgAECgEJAQAAAA==.Naillil:BAAALgAECgEJAQAAAA==.Namiiswan:BAAALgADCgMJBQAAAA==.Natsuki:BAAALgADCgUJBwAAAA==.',
Ne='Nefarius:BAAALgAECgcJCQABLgAECggJEwABAAAAAA==.Neflite:BAABLgAECn8YAAIVAAcJtgYCDwDjAAAVAAcJtgYCDwDjAAAAAA==.Nelfie:BAAALgAECgEJAQAAAA==.Nessará:BAAALgAECgUJCQAAAA==.',
Ni='Nineõseven:BAABLgAECn8YAAIkAAcJixN6IADVAQAkAAcJixN6IADVAQABLgAECgEJAQABAAAAAA==.Ninjapro:BAAALgAECgEJAQAAAA==.Nixia:BAAALgAECgQJBAAAAA==.',
No='Nodiddy:BAAALgADCgcJBwABLgAECgcJJAAQAPQhAA==.',
Nu='Nuraga:BAABLgAECn8gAAInAAcJByTVBwCpAgAnAAcJByTVBwCpAgAAAA==.',
Ob='Obeeone:BAAALgAECgEJAQAAAA==.',
On='Onasta:BAABLgAECn8eAAIOAAkJqB40FQBRAgAOAAkJqB40FQBRAgAAAA==.Onelastkiss:BAAALgAECgEJAQAAAA==.',
Op='Oprahheals:BAAALgAFFAEJAQAAAA==.',
Or='Oreobeer:BAAALgAECgEJAQAAAA==.Oreomonster:BAAALgAECgUJCwAAAA==.Orquesta:BAAALgAECgQJBQAAAA==.',
Pa='Paccer:BAAALgAECgEJAQAAAA==.Pacerx:BAAALgAECgIJAgAAAA==.Pandaemonia:BAACLgAFFH8HAAIiAAMJDg19BACoAAAiAAMJDg19BACoAAAuAAQKfx4AAiIACAk2Co0SACkBACIACAk2Co0SACkBAAAA.Pandakyle:BAABLgAECn8WAAITAAYJ5RfSHgBQAQATAAYJ5RfSHgBQAQAAAA==.Pandexander:BAAALgADCgMJAwAAAA==.Parts:BAABLgAECn8iAAIQAAgJtCGEIQDtAgAQAAgJtCGEIQDtAgABLgAFFAQJCwAOAK4bAA==.Patchmen:BAAALgAECgQJBAAAAA==.Pattilicious:BAABLgAECn8hAAIHAAgJXQtkSABsAQAHAAgJXQtkSABsAQAAAA==.',
Pe='Pepsizero:BAAALgAECgUJCwAAAA==.',
Ph='Phlesh:BAAALgAECgEJAQAAAA==.Phlvrabies:BAAALgADCgMJBQAAAA==.Phonedin:BAABLgAECn8jAAMYAAkJERmdBgCIAgAYAAkJERmdBgCIAgAWAAMJBhcYSQCyAAAAAA==.Phoënix:BAABLgAFFH8HAAIFAAMJxRhFHwDhAAAFAAMJxRhFHwDhAAAAAA==.',
Pi='Pieglaive:BAABLgAECn8iAAMMAAkJzSHIAQDyAgAMAAkJzSHIAQDyAgALAAIJuhZewwB2AAAAAA==.Pierres:BAAALgAECgYJBwAAAA==.Piondelth:BAAALgAECgcJEQAAAA==.',
Pl='Plantman:BAAALgAECgUJCQAAAA==.',
Po='Poofort:BAAALgADCgEJAQAAAA==.Pooner:BAAALgADCgMJAwAAAA==.Postoak:BAAALgAECgUJCgAAAA==.Powerochrist:BAABLgAECn8gAAIaAAkJjhFqEgADAgAaAAkJjhFqEgADAgAAAA==.',
Pr='Proxzy:BAAALgAECggJCwAAAA==.',
Pu='Pubessalad:BAAALgAECgkJEAAAAA==.Puddin:BAAALgADCgQJBgAAAA==.Puffytaco:BAAALgAECgQJBQABLgAECggJHQAHAE0dAA==.',
Qu='Qualek:BAABLgAECn8XAAInAAkJMRJcEAADAgAnAAkJMRJcEAADAgAAAA==.Quilue:BAABLgAECn8ZAAIQAAgJhA76QQChAQAQAAgJhA76QQChAQAAAA==.',
Ra='Rannmagnison:BAABLgAECn8iAAIHAAgJQgbJZAAkAQAHAAgJQgbJZAAkAQAAAA==.Raquoon:BAAALgAECgUJEAAAAA==.Ratfu:BAAALgADCgcJDQAAAA==.Razjin:BAABLgAECn8ZAAMFAAgJ7CPsCQDaAgAFAAgJ7CPsCQDaAgAEAAEJ/wp0agAsAAAAAA==.',
Re='Reapér:BAAALgAECgkJBQAAAA==.Reze:BAABLgAFFH8LAAIgAAMJqBbEDgD6AAAgAAMJqBbEDgD6AAABLgAFFAgJJgAMAHgfAA==.',
Rh='Rhaeynera:BAABLgAECn8dAAIYAAcJYgUqCwDmAAAYAAcJYgUqCwDmAAAAAA==.',
Ri='Riezen:BAAALgAECgEJAgAAAA==.Ringol:BAAALgAECgQJCgABLgAECgYJDgABAAAAAA==.Rinorik:BAABLgAECn8uAAMNAAkJSx6wBwDKAgANAAkJSx6wBwDKAgAVAAYJCRn1FACjAQAAAA==.Rizzdor:BAAALgADCgcJCAABLgAECggJEQABAAAAAA==.',
Ro='Rockbiter:BAAALgAECgEJAgAAAA==.Rockhhard:BAABLgAECn8bAAIFAAgJLR/iEgAgAgAFAAgJLR/iEgAgAgAAAA==.Roeken:BAABLgAECn8iAAIcAAkJiRDjDgACAgAcAAkJiRDjDgACAgAAAA==.Rollingman:BAAALgAECgUJDgAAAA==.',
Ru='Rudyrots:BAAALgAECgEJAQABLgAFFAEJAgABAAAAAA==.Rudyshoots:BAAALgAFFAEJAgAAAA==.',
Ry='Rygaard:BAABLgAECn8vAAInAAkJQR81AgDKAgAnAAkJQR81AgDKAgAAAA==.Ryutiz:BAABLgAECn8jAAIDAAgJ7SG2AwAVAgADAAgJ7SG2AwAVAgAAAA==.Ryward:BAAALgADCgcJBwAAAA==.Ryyuk:BAAALgAECgMJBAABLgAECggJEwALAD0PAA==.',
Sa='Sacridas:BAAALgAECgEJAQABLgAECggJIwADAO0hAA==.Sako:BAAALgADCgUJCgAAAA==.Samsó:BAAALgAECggJEQAAAA==.Sapharina:BAABLgAECn8pAAIjAAkJQRdCBgCSAgAjAAkJQRdCBgCSAgAAAA==.Sassgrip:BAAALgADCgEJAQABLgAECgYJDAABAAAAAA==.Sassier:BAAALgAECgYJDAAAAA==.Sathenaz:BAAALgADCgcJCQAAAA==.',
Sc='Scarcy:BAACLgAFFH8MAAIJAAQJDxoxCQBgAQAJAAQJDxoxCQBgAQAuAAQKfysAAwkACQlYGa0QAJ0CAAkACQlYGa0QAJ0CACUAAQkAAEEWAAAAAAAA.',
Se='Seacotton:BAAALgAECgYJCgAAAA==.Searfang:BAACLgAFFH8LAAIEAAQJNhKeDwAxAQAEAAQJNhKeDwAxAQAuAAQKfyMAAwQACQndGnQUAHsCAAQACQndGnQUAHsCAAUAAQleEzp7ADgAAAAA.Seariel:BAAALgAECgUJBgAAAA==.Selestra:BAAALgAFFAIJAgAAAA==.Selinise:BAAALgAECgUJBQAAAA==.Sematic:BAAALgAFFAEJAQABLgAFFAUJEgAQAJofAA==.Senpai:BAAALgAECgQJBAAAAA==.Seraphymm:BAAALgADCgEJAQAAAA==.',
Sh='Shadowjacker:BAACLgAFFH8LAAILAAQJsxkxGQBFAQALAAQJsxkxGQBFAQAuAAQKfzEAAgsACQnOIIIHAFEDAAsACQnOIIIHAFEDAAAA.Shadowmidget:BAABLgAECn8UAAINAAgJWhaXVwDBAQANAAgJWhaXVwDBAQAAAA==.Shadrielis:BAABLgAECn8nAAMjAAgJGx0UBgCYAgAjAAgJGx0UBgCYAgAGAAIJVQ3ObgBsAAAAAA==.Shanlao:BAAALgAECgIJAgABLgAFFAQJEAANAJ4NAA==.Shirkka:BAAALgADCgMJBAAAAA==.Shurihito:BAABLgAECn8hAAIHAAkJIx7SDACaAgAHAAkJIx7SDACaAgAAAA==.',
Si='Sieron:BAABLgAECn8UAAIOAAYJ/RxgPwB/AQAOAAYJ/RxgPwB/AQAAAA==.Silaslunark:BAAALgAECgcJCQAAAA==.Sixpack:BAAALgAECggJEwAAAA==.',
Sk='Skarigar:BAAALgADCggJCwAAAA==.Skeeterson:BAAALgADCgUJBwAAAA==.Skiððles:BAAALgAECgYJBgABLgAECggJFgAEAMkWAA==.Skytec:BAAALgADCgMJAwAAAA==.Skëëts:BAABLgAECn8YAAMjAAcJ1g7HGABtAQAjAAcJrQ7HGABtAQAGAAEJ5gYSUwAoAAAAAA==.Skùrvypete:BAAALgADCgEJAQABLgAECggJFgAEAMkWAA==.',
Sl='Slampoof:BAAALgAECgEJAgAAAA==.Slamslayer:BAAALgADCgIJAwAAAA==.Sleez:BAAALgAECgYJDAAAAA==.Sloodraga:BAAALgADCgYJBgAAAA==.',
Sm='Smallgregory:BAAALgAECgYJDAAAAA==.',
Sn='Sneakdead:BAAALgAECgcJCgAAAA==.Sneakerzz:BAAALgADCgQJBAAAAA==.Sneakfury:BAAALgAECgYJCgABLgAECgcJCgABAAAAAA==.Sneeler:BAAALgAECgEJAQAAAA==.Snowscayia:BAABLgAECn8qAAQIAAkJGhguJwDFAQAIAAgJNRouJwDFAQAfAAcJ9RQ8OwC4AQAdAAEJYQl8JABAAAAAAA==.',
So='Solanar:BAABLgAECn8mAAMaAAgJMiLuEgB7AgAaAAgJMiLuEgB7AgAHAAEJAAArJgEAAAAAAA==.Solesin:BAAALgAECgUJBQABLgAFFAQJDQAXAGkXAA==.Solmina:BAABLgAECn8uAAIQAAkJzBvRDAC4AgAQAAkJzBvRDAC4AgAAAA==.Somniatis:BAAALgAECgEJAQAAAA==.Soulciopath:BAAALgAECgUJCAAAAA==.',
Sp='Spicypants:BAAALgADCgMJAwAAAA==.Spicytaco:BAAALgAECgIJBgABLgAECggJHQAHAE0dAA==.Spookuleli:BAAALgADCgQJBAAAAA==.Sprinklewiz:BAAALgADCgMJAwAAAA==.',
Sq='Squadie:BAABLgAECn8jAAICAAgJsAdbOgBjAQACAAgJsAdbOgBjAQAAAA==.Squanchs:BAACLgAFFH8NAAIFAAQJGh1LDgBSAQAFAAQJGh1LDgBSAQAuAAQKfx4AAwUACQlgH/cGAMACAAUACQlgH/cGAMACAAQAAQkGAP10AAEAAAEuAAQKBwkcAB8AkxsA.Squanchy:BAABLgAECn8cAAIfAAcJkxtuPACyAQAfAAcJkxtuPACyAQAAAA==.Squisquee:BAAALgADCgcJBwAAAA==.',
Sr='Srbojangles:BAAALgAECgYJBgABLgAECgcJJAAQAPQhAA==.Srry:BAABLgAECn8VAAIcAAcJrxrOKQATAgAcAAcJrxrOKQATAgAAAA==.',
St='Stinkvile:BAAALgAECgEJAQAAAA==.Stonebraid:BAAALgADCgEJAQAAAA==.Sturdy:BAAALgADCgEJAQAAAA==.',
Su='Sukuna:BAAALgAECgYJCAAAAA==.Sundance:BAAALgAECgYJCwAAAA==.Surmise:BAACLgAFFH8SAAIQAAUJmh/sFQCJAQAQAAUJmh/sFQCJAQAuAAQKfx8AAxAACAnmI8sYABYDABAACAlrIssYABYDAB4ABAlSIE4FACEBAAAA.Sust:BAAALgAECgUJBQABLgAFFAUJEgAQAJofAA==.',
Sw='Swayzeetrain:BAACLgAFFH8GAAMaAAMJhhsyFQAFAQAaAAMJhhsyFQAFAQAHAAEJpAxKMABUAAAuAAQKfxQAAwcABwntGClmALQBAAcABwntGClmALQBABoABglEH982AKABAAAA.',
Ta='Tabius:BAABLgAECn8jAAMdAAkJ4hzUAwA9AgAdAAkJ4hzUAwA9AgAIAAMJvw7mOACmAAAAAA==.Talkingtaco:BAABLgAECn8dAAIHAAgJTR2+JQDrAQAHAAgJTR2+JQDrAQAAAA==.Taln:BAAALgADCgUJBQABLgAECgYJHAASAJYhAA==.Talìa:BAAALgADCgIJAgABLgADCgQJBAABAAAAAA==.Tareul:BAAALgADCgIJAgAAAA==.Tarn:BAAALgAECgkJEgAAAA==.',
Te='Temok:BAAALgAECgUJEgAAAA==.',
Th='Theabyss:BAAALgAECgEJAQABLgADCgcJEwABAAAAAA==.Thiccbush:BAAALgADCgEJAQAAAA==.Thirielnet:BAAALgAECgEJAQAAAA==.This:BAAALgAECgEJAQAAAA==.Thorisdead:BAAALgADCgMJAwABLgAECgYJDwABAAAAAA==.Thorkell:BAAALgADCgUJBQAAAA==.',
Ti='Tinkaballah:BAAALgAECgcJDgAAAA==.Tipy:BAAALgADCgUJBQAAAA==.',
To='Tore:BAACLgAFFH8LAAICAAMJNxowFQCwAAACAAMJNxowFQCwAAAuAAQKfygAAgIACAlXIqcJAPwCAAIACAlXIqcJAPwCAAAA.Totemangge:BAAALgAFFAEJAQAAAA==.',
Tr='Trifectas:BAAALgADCgcJEQAAAA==.Trinadel:BAACLgAFFH8HAAIIAAQJ1AoBEwAfAQAIAAQJ1AoBEwAfAQAuAAQKfx0AAggACAmnHSoPAK0CAAgACAmnHSoPAK0CAAAA.Träitors:BAAALgADCgcJEwAAAA==.Tråitors:BAABLgAECn8tAAMNAAYJmyAUJgDRAQANAAYJmyAUJgDRAQAVAAEJAAAqZQBFAAABLgADCgcJEwABAAAAAA==.',
Ts='Tsarevich:BAAALgAECgUJEAAAAA==.',
Tu='Tugtheshaman:BAABLgAECn8dAAIFAAgJohgmGgBGAgAFAAgJohgmGgBGAgAAAA==.',
Tw='Twileaf:BAABLgAECn8hAAIfAAcJFgcAUADVAAAfAAcJFgcAUADVAAAAAA==.Twoinchisbig:BAABLgAECn8zAAInAAgJ9RgnCgDOAQAnAAgJ9RgnCgDOAQAAAA==.',
Ty='Typhoidmary:BAABLgAECn8XAAMNAAgJhAl+ggBVAQANAAcJhAl+ggBVAQAVAAEJAAADdgAuAAABLgAECgcJCgABAAAAAA==.',
['Té']='Térror:BAAALgAECgcJDwAAAA==.',
Un='Uncool:BAAALgADCgEJAQABLgAECgEJAQABAAAAAA==.Unholyz:BAAALgAECgQJBAAAAA==.',
Ur='Ursoc:BAABLgAECn8nAAMfAAgJEhUNOgAtAQAfAAYJSBENOgAtAQAIAAcJkg5XJwAFAQAAAA==.Urteg:BAAALgADCgYJCwAAAA==.',
Uu='Uub:BAAALgAECgIJAgAAAA==.',
Va='Vairekor:BAAALgADCggJDgABLgAFFAQJEAANAJ4NAA==.Valdria:BAAALgADCgUJBQAAAA==.Vanillaçake:BAAALgAECgEJAgAAAA==.Vanishja:BAAALgAECgYJDwAAAA==.Varkbyte:BAAALgAECgUJEAAAAA==.Varrik:BAACLgAFFH8IAAMoAAMJixzoCgD4AAAoAAMJ7hjoCgD4AAAcAAIJ0xuQFQC6AAAuAAQKfyYAAxwACAnjIo0JABUDABwACAnjIo0JABUDACgABgmYG+YKAJcBAAAA.',
Ve='Vec:BAAALgAECgYJDQAAAA==.Velamor:BAABLgAECn8YAAQiAAYJzQsaEAC/AAAiAAYJ4AoaEAC/AAAMAAMJygk1VQCTAAALAAMJagrjgwCNAAAAAA==.Velaria:BAAALgADCgcJBwAAAA==.',
Vo='Volieu:BAABLgAECn8cAAIeAAgJgRJ4AgDAAQAeAAgJgRJ4AgDAAQAAAA==.Volklin:BAAALgAECggJEgAAAA==.Voyageurs:BAABLgAECn8VAAIdAAcJwxQfCgCBAQAdAAcJwxQfCgCBAQAAAA==.',
Vy='Vyrka:BAAALgAECgMJCgAAAA==.',
Wa='Wallstreet:BAAALgAECgUJBQAAAA==.Waterdweller:BAAALgAECgEJAQAAAA==.',
We='Wegl:BAAALgAECgUJDgAAAA==.Werewithal:BAAALgADCgUJBQABLgAECggJHgAPAEsQAA==.Wesleypipes:BAAALgAECgEJAQAAAA==.Wetfloorsign:BAAALgAECgYJEQAAAA==.',
Wh='Wholeymilk:BAAALgADCgMJAwAAAA==.',
Wi='Wiindsslashh:BAAALgADCgUJBwAAAA==.Wilbur:BAAALgADCgQJBQAAAA==.Windslash:BAAALgADCgYJAwAAAA==.',
Wo='Wonderx:BAAALgADCgIJAgAAAA==.Wonyoung:BAACLgAFFH8NAAIGAAQJ4x88BwBQAQAGAAQJ4x88BwBQAQAuAAQKfysAAgYACQnPI9kBAFgDAAYACQnPI9kBAFgDAAAA.',
Wu='Wuthrad:BAAALgADCgQJBAAAAA==.',
Xa='Xala:BAAALgAECggJEgAAAA==.Xalaz:BAACLgAFFH8OAAMNAAQJJA1HLQAUAQANAAQJJA1HLQAUAQAVAAEJVwJZGgBGAAAuAAQKfx0AAw0ACQlYHG02ADICAA0ACAlYHG02ADICABUAAgkLFF1SAHcAAAAA.Xanaris:BAAALgADCgEJAQABLgAFFAIJCQAOACYmAA==.Xandumbra:BAAALgADCgEJAQAAAA==.Xarosea:BAACLgAFFH8MAAIHAAQJPhNAGgBDAQAHAAQJPhNAGgBDAQAuAAQKfyoAAgcABwk6JPQYANMCAAcABwk6JPQYANMCAAAA.',
Xe='Xelojr:BAAALgADCgkJHAAAAA==.',
Xh='Xhael:BAAALgADCgEJAQAAAA==.',
Xi='Xia:BAABLgAECn8qAAIGAAgJJhxpCwAwAgAGAAgJJhxpCwAwAgAAAA==.',
Xo='Xoilkick:BAAALgAECgUJCgAAAA==.Xoilwings:BAAALgAECgEJAQAAAA==.Xooiill:BAAALgAECgcJDQAAAA==.',
Xp='Xpacer:BAAALgAECgcJEwAAAA==.',
Ye='Yekira:BAAALgADCgEJAgAAAA==.Yellowsnøw:BAABLgAECn8hAAIQAAgJdxM9MgDYAQAQAAgJdxM9MgDYAQAAAA==.',
Yu='Yumeshade:BAAALgAECgUJCQAAAA==.',
Za='Zal:BAAALgAECgYJBgABLgAFFAUJEQAbAKAWAA==.Zamari:BAAALgAECgMJBQAAAA==.Zanzabar:BAABLgAECn8VAAIdAAkJwwrDEACgAQAdAAkJwwrDEACgAQAAAA==.Zathmage:BAAALgADCgMJAwAAAA==.Zaxin:BAABLgAECn8VAAMGAAcJLA+QGwBuAQAGAAcJLA+QGwBuAQAkAAUJhQQZSwCtAAAAAA==.',
Ze='Zelfie:BAAALgADCgUJBQAAAA==.Zellda:BAAALgAECgQJBQAAAA==.Zeros:BAABLgAECn8VAAIQAAcJ8xgINwDGAQAQAAcJ8xgINwDGAQAAAA==.',
Zo='Zoerina:BAAALgAECgUJCAAAAA==.Zoobilong:BAAALgAECgUJDwAAAA==.',
Zx='Zxak:BAABLgAECn8nAAIMAAgJUyZsAQAIAwAMAAgJUyZsAQAIAwAAAA==.',
Zy='Zyahk:BAAALgADCgQJBQAAAA==.Zynn:BAAALgAECgEJAgAAAA==.',
['Zë']='Zën:BAAALgAECgEJAQABLgAFFAIJAgABAAAAAA==.',
['Ða']='Ðashÿ:BAAALgAECgMJAwABLgAECgcJEAABAAAAAA==.',
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
