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

local lookup = {'Unknown-Unknown','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Retribution','DemonHunter-Devourer','DemonHunter-Havoc','Warlock-Demonology','DeathKnight-Unholy','Hunter-Survival','Monk-Brewmaster','Monk-Mistweaver','Shaman-Elemental','Warlock-Affliction','Warlock-Destruction','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Priest-Holy','Druid-Guardian','Paladin-Holy','DeathKnight-Blood','Paladin-Protection','Mage-Frost','Druid-Feral','Mage-Arcane','Shaman-Restoration','Druid-Restoration','Druid-Balance','Monk-Windwalker','Shaman-Enhancement','DeathKnight-Frost','Priest-Shadow','Warrior-Protection','DemonHunter-Vengeance','Priest-Discipline','Rogue-Subtlety','Warrior-Fury','Warrior-Arms',}
local provider = {region='US',realm='Fizzcrank',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abandonhope:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.',
Ac='Accuser:BAAALgADCgEJAQAAAA==.Acky:BAAALgADCgUJBQAAAA==.',
Ad='Adwen:BAAALgAECgQJBwAAAA==.',
Ae='Aeronemon:BAAALgAECgEJAgAAAA==.',
Ai='Airill:BAAALgADCgQJBQAAAA==.',
Ak='Akforty:BAABLgAECn8cAAMCAAgJHCLRCgDvAgACAAgJHCLRCgDvAgADAAIJoBVleABfAAAAAA==.Akittymeow:BAAALgAECgcJEgAAAA==.',
Al='Aldredevon:BAAALgAECgEJAQAAAA==.Aleshock:BAAALgAECgUJBQAAAA==.Alidar:BAAALgAECgQJCwAAAA==.Altairis:BAAALgAECgEJAQAAAA==.Altartoy:BAAALgAECggJDgAAAA==.Althunter:BAABLgAECn8UAAIDAAgJTCBYAQABAgADAAgJTCBYAQABAgAAAA==.',
Am='Amelina:BAAALgAECgEJAQAAAA==.Amorir:BAABLgAECn8fAAIEAAgJVRALEQCbAQAEAAgJVRALEQCbAQAAAA==.Amorydalias:BAAALgAECgUJBQAAAA==.Amozon:BAAALgADCgEJAQAAAA==.',
An='Anastala:BAAALgAECgYJDgAAAA==.Angchu:BAAALgADCgQJBAAAAA==.Annesta:BAAALgAECgcJEgAAAA==.',
Ap='Apostus:BAAALgADCgcJDgAAAA==.Apothica:BAAALgAECgEJAQAAAA==.',
Aq='Aquafox:BAAALgAECgUJCQAAAA==.',
Ar='Archontas:BAAALgAECgYJDQAAAA==.Ariodh:BAABLgAECn8eAAMFAAgJ/CJGAwBvAgAFAAcJ7CVGAwBvAgAGAAUJpB9UJACaAQAAAA==.Arkaline:BAAALgAECgEJAQAAAA==.Artuarry:BAACLgAFFH8IAAIHAAQJPArFCAA4AQAHAAQJPArFCAA4AQAuAAQKfyAAAgcACAmgHjAjAIgCAAcACAmgHjAjAIgCAAAA.Aryndus:BAAALgAECgQJBAAAAA==.',
At='Athenà:BAAALgAECgQJBAAAAA==.',
Av='Avocado:BAABLgAECn8XAAIDAAcJQyL5AAAqAgADAAcJQyL5AAAqAgAAAA==.',
Ax='Axelaw:BAAALgADCgQJBAAAAA==.',
Ay='Ayrz:BAAALgAECgIJAgAAAA==.',
Az='Azaria:BAAALgADCgIJAgAAAA==.',
Ba='Baileyhowl:BAAALgAECgEJAQAAAA==.Bammie:BAAALgADCgQJBAAAAA==.Bananuth:BAAALgADCgYJBgABLgAFFAQJBwAIAM8SAA==.Banthr:BAAALgAECgYJCwAAAA==.Barkert:BAAALgADCgEJAQAAAA==.Baroke:BAAALgAECgMJBwABLgAECggJDgABAAAAAA==.Barokoshama:BAAALgAECgYJDQAAAA==.Basaltytaco:BAAALgADCgEJAQAAAA==.Battleworm:BAAALgADCgkJEwABLgABCgIJAgABAAAAAA==.',
Bb='Bbalrd:BAAALgAECgYJEQAAAA==.',
Be='Bearglie:BAAALgAECgYJBgAAAA==.Beepers:BAAALgAECgYJBgAAAA==.',
Bi='Bigcow:BAAALgADCgIJAgAAAA==.',
Bl='Blackolives:BAAALgAECgYJBQAAAA==.Blondefu:BAAALgAECgUJCwAAAA==.Bloodybonne:BAAALgADCgcJBwAAAA==.Bloodyell:BAAALgAECgEJAQAAAA==.Bloore:BAAALgAECgMJAwABLgAECgcJHgADANEjAA==.Bluejuly:BAAALgAECgQJBAAAAA==.',
Bo='Boflex:BAAALgADCgQJBQAAAA==.Bomboclat:BAAALgAECgUJCwAAAA==.Bonesknows:BAAALgADCgEJAQAAAA==.Bowwie:BAABLgAECn8hAAQCAAkJEB4uBgArAwACAAkJEB4uBgArAwAJAAIJ4Q1lDgCPAAADAAEJFQMAkwAnAAAAAA==.',
Br='Bronzé:BAAALgAECgQJCgAAAA==.Brotherfrey:BAAALgAECgYJCgAAAA==.Bruish:BAABLgAFFH8MAAIKAAQJtwzADQAWAQAKAAQJtwzADQAWAQAAAA==.',
Bu='Bubbadoo:BAAALgAECgYJCQAAAA==.Buddy:BAAALgAECgQJCAABLgAECgYJEAABAAAAAA==.Bulan:BAABLgAECn8dAAILAAgJXiG2AADyAgALAAgJXiG2AADyAgAAAA==.',
Bw='Bweninger:BAAALgADCgUJBQAAAA==.',
['Bô']='Bôôsted:BAABLgAECn8VAAIMAAgJyRbbIAAIAgAMAAgJyRbbIAAIAgAAAA==.',
Ca='Caistan:BAAALgADCgYJCAAAAA==.Candypants:BAAALgAECgQJBAAAAA==.Caoth:BAAALgAECgUJDQAAAA==.Cappilon:BAAALgAECgUJCQAAAA==.Carcus:BAAALgAECgEJAQAAAA==.Cayleedah:BAAALgAECgYJEQAAAA==.Cayssaris:BAAALgAECgMJBAAAAA==.',
Cc='Cc:BAABLgAECn8VAAQNAAYJ7hLrDgBCAQANAAUJ9BPrDgBCAQAOAAYJKwswIwA+AQAHAAQJDRPXtQDtAAAAAA==.',
Ce='Ceeti:BAABLgAECn8eAAMPAAgJyh0AAgBEAgAPAAgJyh0AAgBEAgAQAAIJeAYeQABpAAAAAA==.Celandrelia:BAAALgAECgUJBQABLgAECgYJGwARABcVAA==.',
Ch='Chaoticoreo:BAABLgAECn8dAAMGAAYJeh9hBACVAQAGAAYJeh9hBACVAQAFAAQJ4w9RrQCzAAAAAA==.Chareyne:BAABLgAECn8VAAISAAgJug9sJgC5AQASAAgJug9sJgC5AQAAAA==.Cheetor:BAAALgADCgcJCgABLgAECggJIQAJAEUfAA==.Cheezytaco:BAAALgAECgUJBgABLgAECgcJEgABAAAAAA==.Chidge:BAAALgADCggJCwAAAA==.Chikila:BAAALgAECgQJCAAAAA==.Chilliflakez:BAAALgAECgQJBwAAAA==.Chro:BAAALgADCgEJAQAAAA==.',
Ci='Cindezar:BAAALgADCgMJAwAAAA==.',
Cl='Clementyn:BAAALgAECgUJDgAAAA==.Cleyi:BAABLgAECn8VAAISAAgJqQRHDQAbAQASAAgJqQRHDQAbAQAAAA==.',
Co='Coldpasta:BAAALgAECgYJDQAAAA==.Colonoscopy:BAAALgAECgEJAQAAAA==.Coreyy:BAAALgADCgUJBwAAAA==.Corva:BAABLgAECn8lAAIHAAgJfhQwPQAYAgAHAAgJfhQwPQAYAgAAAA==.Cosairi:BAAALgADCgQJBAAAAA==.Cougztroll:BAABLgAECn8ZAAITAAgJlRW1CwDSAQATAAgJlRW1CwDSAQAAAA==.',
Cr='Crazaki:BAAALgADCgEJAQAAAA==.',
Cu='Curfluffin:BAAALgADCgEJAQAAAA==.Cuttercupx:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.',
Da='Dakadin:BAABLgAECn8XAAMUAAcJKiIEGABSAgAUAAcJKiIEGABSAgAEAAQJxRVPNgC/AAAAAA==.Daranne:BAABLgAECn8eAAIEAAgJMBocPwApAgAEAAgJMBocPwApAgAAAA==.Darksoulstwo:BAAALgADCgMJAwAAAA==.Dasbeans:BAAALgAFFAIJAwAAAA==.Dashy:BAAALgAECgMJAwABLgAECgYJBgABAAAAAA==.',
De='Deaduglie:BAABLgAECn8ZAAMHAAgJJxQWDQCtAQAHAAgJJxQWDQCtAQAOAAEJMQjgcQA0AAAAAA==.Deliandora:BAAALgADCgUJBQAAAA==.Delynique:BAAALgADCgEJAQABLgAECgcJHgADANEjAA==.Demonx:BAAALgAECgEJAQAAAA==.Denaric:BAAALgAECgQJBgAAAA==.Destroyevsky:BAAALgAECgQJCAAAAA==.Detonate:BAAALgAECgQJCAAAAA==.',
Dh='Dhvecx:BAAALgAECgUJBgABLgAECgYJDQABAAAAAA==.',
Di='Dilbo:BAAALgAECgEJAQAAAA==.Diomed:BAAALgAECgEJAQAAAA==.Diqon:BAABLgAECn8eAAMIAAgJIxdgCgDYAQAIAAgJIxdgCgDYAQAVAAYJ7xIcIwApAQAAAA==.Disturbedtwo:BAAALgAECgQJBAAAAA==.',
Do='Dolphinz:BAABLgAECn8iAAMEAAgJ+iDdBQA4AgAEAAgJ+iDdBQA4AgAWAAIJ6QogPABOAAAAAA==.Doryadni:BAAALgADCgcJBgAAAA==.',
Dr='Dragonpede:BAABLgAECn8oAAIPAAkJxBrrAACoAgAPAAkJxBrrAACoAgAAAA==.Dragonwarior:BAAALgAECgYJEwAAAA==.Drakindees:BAAALgADCgYJDQABLgAECgcJIQAXAA8eAA==.Drakkyn:BAAALgAECgQJCAAAAA==.Dread:BAAALgADCgQJBAAAAA==.Drosuu:BAAALgAECgEJAQAAAA==.Druish:BAACLgAFFH8MAAITAAQJsxqjAABaAQATAAQJsxqjAABaAQAuAAQKfyIAAxMACAmvJqwBADUDABMACAmvJqwBADUDABgAAgkOD5IsAGEAAAAA.Drykkr:BAABLgAECn8XAAIKAAcJTRY7CAB0AQAKAAcJTRY7CAB0AQAAAA==.',
Du='Durrik:BAAALgADCgcJBwAAAA==.',
['Dà']='Dàsh:BAAALgAECgYJBgAAAA==.',
Ea='Eatrocks:BAAALgADCggJCAAAAA==.',
Ed='Edorn:BAAALgADCgIJAgAAAA==.',
Ef='Efn:BAAALgAECgYJDQAAAA==.',
El='Elcrys:BAAALgAECgcJCAAAAA==.Elion:BAAALgAECgEJAQAAAA==.Elpollo:BAABLgAECn8hAAMXAAcJDx6TQgBwAgAXAAcJDx6TQgBwAgAZAAEJshe0HAA6AAAAAA==.Elvar:BAAALgADCgkJCwAAAA==.',
Em='Emmdwemm:BAAALgAECgIJAwAAAA==.',
Ep='Ephelia:BAABLgAECn8VAAMaAAgJzRmVIgAPAgAaAAgJzRmVIgAPAgAMAAEJjAPilAAgAAAAAA==.Epitome:BAAALgAECgMJAwAAAA==.',
Er='Erid:BAAALgAECgYJCQAAAA==.',
Et='Etude:BAAALgADCgEJAQAAAA==.',
Ev='Evelyndel:BAAALgAECgIJAgAAAA==.Evermoons:BAABLgAECn8XAAIbAAcJyxYpCADgAQAbAAcJyxYpCADgAQAAAA==.',
Fa='Falaria:BAAALgAECgQJBAAAAA==.Falasdaer:BAAALgAECggJCAAAAA==.Falstaff:BAAALgAECggJEQAAAA==.Fartshooter:BAAALgAECgYJEQAAAA==.Fatterblunt:BAACLgAFFH8IAAIcAAQJGw24BAAUAQAcAAQJGw24BAAUAQAuAAQKfyEAAhwACAl+IbENAMACABwACAl+IbENAMACAAAA.',
Fe='Fedner:BAAALgAECgYJDAAAAA==.Feldar:BAAALgAECggJEQAAAA==.Fend:BAAALgADCgQJBAAAAA==.Feyredarling:BAAALgAECgMJAwAAAA==.',
Fi='Fists:BAACLgAFFH8GAAIKAAIJ/SJ6FgC/AAAKAAIJ/SJ6FgC/AAAuAAQKfyoAAwoABgmEI4sWAFQCAAoABgmEI4sWAFQCAB0ABAk3EqJUAL4AAAAA.Fizzbeard:BAAALgADCgcJCgAAAA==.Fizzical:BAAALgADCgYJBgAAAA==.Fizzleclaw:BAAALgAECgQJBAABLgAECgQJBAABAAAAAA==.Fizzleded:BAAALgAECgQJBAAAAA==.',
Fl='Flightrisk:BAAALgADCgQJBAABLgAECgIJAgABAAAAAA==.Florisa:BAABLgAECn8YAAIEAAYJSB9GYADDAQAEAAYJSB9GYADDAQAAAA==.',
Fo='Fordi:BAABLgAECn8XAAMMAAgJ3xWYBQC9AQAMAAgJtBWYBQC9AQAeAAIJLRFGJgBzAAAAAA==.Fourdy:BAABLgAECn8dAAIaAAYJRhkvPgCIAQAaAAYJRhkvPgCIAQAAAA==.',
Fr='Fragdoll:BAAALgAECgQJBwAAAA==.Freakinlarry:BAAALgADCgEJAQAAAA==.Freakinoak:BAAALgAECgcJEgAAAA==.Free:BAAALgAECgYJDAAAAA==.Froost:BAABLgAECn8VAAIIAAgJ0Bz0TAAMAgAIAAgJ0Bz0TAAMAgAAAA==.',
Fu='Funkflex:BAAALgADCgcJCgAAAA==.Furvert:BAAALgAECgIJAgAAAA==.Fushi:BAAALgAECgEJAQAAAA==.',
Ga='Gandis:BAAALgAECgcJCgAAAA==.Gapper:BAABLgAECn8hAAIJAAgJRR9rBADSAgAJAAgJRR9rBADSAgAAAA==.',
Gi='Gimbó:BAAALgADCgMJAwAAAA==.',
Gl='Glamour:BAAALgADCgEJAgAAAA==.Glestaar:BAABLgAECn8fAAMCAAgJSRj6HwBFAgACAAgJSRj6HwBFAgADAAIJPQtyfABSAAAAAA==.Glyr:BAAALgAECgYJCgAAAA==.',
Go='Goingrouge:BAAALgADCgcJDQAAAA==.Goldabelle:BAAALgAECgYJCgAAAA==.Gorlami:BAAALgAECgQJCAAAAA==.Gothelf:BAAALgADCgYJEAABLgAECgYJDQABAAAAAA==.Gothri:BAAALgADCggJCAABLgAECgYJCwABAAAAAA==.Gothstraza:BAAALgAECgYJCwAAAA==.Gottemgood:BAAALgADCgUJBQAAAA==.',
Gr='Grimli:BAABLgAECn8UAAIaAAcJFw9bEAA9AQAaAAcJFw9bEAA9AQAAAA==.Growth:BAAALgAECgcJBwAAAA==.',
Gu='Gurthcaptian:BAAALgAECgQJBAAAAA==.',
['Gá']='Gárròsh:BAAALgAECgYJBgAAAA==.',
Ha='Haerin:BAAALgAECgIJAgABLgAFFAIJBQASAEoiAA==.Harnel:BAAALgAECgYJEQAAAA==.Hattorihanzo:BAAALgADCgYJEQAAAA==.',
He='Healeymonstr:BAAALgADCgIJAgAAAA==.Healmart:BAAALgAECgQJCAAAAA==.Heartëater:BAAALgADCgYJBgAAAA==.Hellinyoface:BAAALgADCgUJBQAAAA==.',
Hi='Himothyy:BAAALgAECgQJBAAAAA==.',
Ho='Holypeetch:BAAALgADCgYJBgAAAA==.Hordedefect:BAAALgADCgQJBAABLgAECgIJAgABAAAAAA==.Hoyer:BAAALgAECgcJDwAAAA==.',
Im='Impact:BAAALgADCgcJCgAAAA==.',
Io='Iove:BAAALgAECgYJEAAAAA==.',
Ja='Jahsahm:BAAALgAECgYJEAAAAA==.Jajung:BAAALgADCgMJAwAAAA==.Jakub:BAAALgAECggJDAABLgAECgkJIQACABAeAA==.Jakuren:BAAALgADCgYJBgAAAA==.Jamjam:BAAALgADCgYJCQAAAA==.',
Je='Jesit:BAAALgAECgYJDwAAAA==.',
Ji='Jingles:BAAALgADCgYJBgAAAA==.',
Jj='Jjada:BAAALgAECgcJCwAAAA==.',
Jo='Johnwolf:BAAALgAECgQJBwAAAA==.',
Jy='Jyade:BAAALgAECgYJDAAAAA==.Jynoria:BAAALgADCgcJDAAAAA==.',
Ka='Kainlok:BAAALgADCgIJAgAAAA==.Kaiserice:BAAALgAECgYJDwAAAA==.Kamarra:BAAALgAECgYJDgAAAA==.Kamencider:BAAALgAECgYJDwAAAA==.Kamidala:BAAALgADCgcJCAAAAA==.Kankles:BAABLgAECn8cAAIcAAcJYCIIEgCJAgAcAAcJYCIIEgCJAgAAAA==.Katabetta:BAAALgADCgMJAwAAAA==.',
Ke='Kernelpanic:BAACLgAFFH8HAAMIAAQJzxIbDwD/AAAIAAMJFxcbDwD/AAAfAAEJ9wWgBABIAAAuAAQKfyEAAggACAl9ISskAK0CAAgACAl9ISskAK0CAAAA.Kessho:BAAALgAECgYJDwABLgAECgkJIQACABAeAA==.Kevynn:BAAALgADCgMJAgAAAA==.Keyoshi:BAAALgAECgYJBgAAAA==.',
Ki='Kickrocks:BAAALgADCgUJBwAAAA==.Kilerforlife:BAAALgAECgYJCwAAAA==.Kilowog:BAAALgADCgUJCAAAAA==.Kilpally:BAAALgAECgYJBwAAAA==.Kintra:BAAALgADCgIJAgAAAA==.Kirkle:BAAALgAECgYJEAAAAA==.Kithara:BAAALgAECgEJAwAAAA==.',
Ko='Kovy:BAAALgAECggJDwAAAA==.Kovya:BAAALgADCgYJBwAAAA==.',
Kr='Krelel:BAAALgADCgIJAgAAAA==.Krukar:BAAALgADCgYJDAAAAA==.',
Ky='Kydroga:BAAALgAECgYJEAAAAA==.Kynaria:BAAALgADCgMJAwAAAA==.Kynsia:BAAALgADCgQJBQAAAA==.',
La='Lamörak:BAAALgAECgYJEwAAAA==.Landrick:BAABLgAECn8XAAIIAAgJaQ4YEACWAQAIAAgJaQ4YEACWAQAAAA==.Lastotem:BAAALgADCgEJAQAAAA==.Latest:BAAALgADCgQJBAAAAA==.Lavasaurus:BAAALgAECgYJEAAAAA==.',
Le='Leafstorm:BAAALgAECgQJCAAAAA==.Lehala:BAAALgADCgQJBAAAAA==.Lektar:BAAALgADCgMJAwABLgAECgUJDQABAAAAAA==.Leloosh:BAAALgADCgkJDAABLgAECgYJDQABAAAAAA==.Lemon:BAAALgAECgYJDgAAAA==.Leokenoso:BAAALgAECgYJDgAAAA==.Lessalia:BAAALgADCgMJBgAAAA==.Lewd:BAAALgADCgEJAgAAAA==.',
Li='Lifebloomz:BAAALgAECgYJDQAAAA==.Lifesabeach:BAAALgAECgEJAQAAAA==.Lilfluffcc:BAAALgAECgQJBAAAAA==.Lissana:BAAALgADCgUJBQAAAA==.',
Lo='Lockward:BAAALgAECgIJAQAAAA==.Lorblor:BAAALgAECgQJBAAAAA==.Lorerun:BAAALgADCgUJCAAAAA==.Lowang:BAAALgAECgcJEgAAAA==.Lowmein:BAAALgAECgUJCgAAAA==.',
Lu='Lucÿfer:BAAALgAECgIJAwAAAA==.Lumie:BAAALgAECgEJAQAAAA==.Lunafox:BAAALgAECgYJEQAAAA==.Lunamae:BAAALgAECgYJCQAAAA==.Lupacho:BAAALgAECgQJBgAAAA==.Luvvyyaa:BAABLgAECn8cAAISAAgJYyC1CADAAgASAAgJYyC1CADAAgAAAA==.Luvyya:BAAALgAECgQJCAABLgAECggJHAASAGMgAA==.Luvyyaa:BAAALgADCgQJBAABLgAECggJHAASAGMgAA==.',
Ly='Lyrinaku:BAAALgAECgYJDwAAAA==.Lythomancer:BAAALgAECgYJDgAAAA==.',
Ma='Maddeena:BAAALgAECgQJCAAAAA==.Maddy:BAAALgAECgYJDwAAAA==.Maelyssa:BAAALgADCgMJAwAAAA==.Magicmangge:BAAALgADCgYJBgABLgAECgcJDwABAAAAAA==.Makeitclap:BAAALgADCgEJAQABLgAECgYJDwABAAAAAA==.Malidian:BAAALgAECgYJDwAAAA==.Matchadaddy:BAAALgAECgEJAQAAAA==.Maxohlx:BAACLgAFFH8HAAIHAAMJ6wiSEgDWAAAHAAMJ6wiSEgDWAAAuAAQKfyMAAgcACQlFF90ZALoCAAcACQlFF90ZALoCAAAA.',
Mc='Mcmercie:BAAALgAECgMJAwAAAA==.',
Me='Meeko:BAAALgADCgUJBQABLgAFFAUJCwAQAHUZAA==.Megahertz:BAAALgADCgEJAQAAAA==.Meilia:BAAALgADCgUJBwAAAA==.Mekari:BAABLgAECn8eAAIJAAgJ1xsQAgASAgAJAAgJ1xsQAgASAgAAAA==.Melchiorr:BAABLgAECn8VAAINAAYJiBvHBgDsAQANAAYJiBvHBgDsAQAAAA==.Melignant:BAAALgADCgEJAQAAAA==.Melosia:BAAALgADCgQJBwAAAA==.Melynne:BAABLgAECn8eAAMaAAgJNRPdBQD/AQAaAAgJNRPdBQD/AQAMAAIJeASsgQBBAAAAAA==.Memmel:BAAALgADCgMJAwAAAA==.Meredeath:BAAALgAECgcJDQAAAA==.',
Mi='Micro:BAAALgAECgcJCQAAAA==.Microslash:BAAALgADCgMJAwABLgAECgcJCQABAAAAAA==.Minsoo:BAAALgAECgYJCwAAAA==.Mistblade:BAAALgAECgQJBAAAAA==.Miststriker:BAAALgAECgQJBAAAAA==.',
Ml='Mlrglett:BAABLgAECn8aAAMTAAgJ2h64AABqAgATAAgJ2h64AABqAgAcAAEJihMDhgAqAAAAAA==.',
Mo='Mojomaker:BAAALgAECgQJBwAAAA==.Moojitsu:BAAALgADCgMJAwAAAA==.Mormegil:BAAALgAECgYJEAAAAA==.Moshimoshi:BAACLgAFFH8FAAIaAAIJTBJUDACFAAAaAAIJTBJUDACFAAAuAAQKfxsAAwwACAmXG2IbADcCAAwABwkQHWIbADcCABoABwlFB35RAD8BAAAA.',
Mu='Muffinlord:BAAALgAECgYJCwAAAA==.Munkeebutt:BAAALgAECgcJEgAAAA==.Munkeefase:BAAALgADCgEJAQAAAA==.',
Na='Naberius:BAAALgAECgEJAQAAAA==.Naillil:BAAALgAECgEJAQAAAA==.Namiiswan:BAAALgADCgMJBQAAAA==.Natsuki:BAAALgADCgUJBwAAAA==.',
Ne='Neflite:BAAALgAECgYJDwAAAA==.Nelfie:BAAALgAECgEJAQAAAA==.Nessará:BAAALgAECgEJAQAAAA==.',
Ni='Nineõseven:BAABLgAECn8YAAIgAAcJixNzIADVAQAgAAcJixNzIADVAQABLgAECgEJAQABAAAAAA==.Ninjapro:BAAALgAECgEJAQAAAA==.Nixia:BAAALgAECgQJBAAAAA==.',
Nu='Nuraga:BAABLgAECn8dAAIhAAcJ5iPTBwCpAgAhAAcJ5iPTBwCpAgAAAA==.',
Ob='Obeeone:BAAALgAECgEJAQAAAA==.',
On='Onasta:BAAALgAECgYJEgAAAA==.Onelastkiss:BAAALgAECgEJAQAAAA==.',
Op='Oprahheals:BAAALgAECgYJBgAAAA==.',
Or='Oreobeer:BAAALgAECgEJAQAAAA==.Oreomonster:BAAALgAECgQJBQAAAA==.Orquesta:BAAALgAECgEJAQAAAA==.',
Pa='Paccer:BAAALgADCgUJBQAAAA==.Pacerx:BAAALgADCgYJBgAAAA==.Pandaemonia:BAABLgAECn8cAAIiAAgJcwaOEgApAQAiAAgJcwaOEgApAQAAAA==.Pandakyle:BAAALgAECgUJDwAAAA==.Pandexander:BAAALgADCgMJAwAAAA==.Parts:BAABLgAECn8iAAIXAAgJtCE1BQBiAgAXAAgJtCE1BQBiAgAAAA==.Patchmen:BAAALgAECgQJBAAAAA==.Pattilicious:BAABLgAECn8XAAIEAAcJugsPGQBaAQAEAAcJugsPGQBaAQAAAA==.',
Pe='Pepsizero:BAAALgAECgMJAwAAAA==.',
Ph='Phlvrabies:BAAALgADCgMJBQAAAA==.Phonedin:BAABLgAECn8gAAMRAAgJGRucBgCIAgARAAgJGRucBgCIAgAPAAMJBhcOSQCyAAAAAA==.Phoënix:BAAALgAECgYJCQAAAA==.',
Pi='Pieglaive:BAABLgAECn8WAAMGAAcJySG0AQAgAgAGAAcJySG0AQAgAgAFAAIJuhZOwwB2AAAAAA==.Pierres:BAAALgAECgYJBgAAAA==.Piondelth:BAAALgAECgcJEQAAAA==.',
Pl='Plantman:BAAALgAECgEJAQAAAA==.',
Po='Pooner:BAAALgADCgMJAwAAAA==.Postoak:BAAALgAECgUJCQAAAA==.Powerochrist:BAABLgAECn8YAAIUAAcJWhAFCwCPAQAUAAcJWhAFCwCPAQAAAA==.',
Pu='Pubessalad:BAAALgAECgkJBAAAAA==.Puddin:BAAALgADCgQJBgAAAA==.',
Qu='Qualek:BAABLgAECn8XAAIhAAkJMRJdEAADAgAhAAkJMRJdEAADAgAAAA==.Quilue:BAAALgAECggJCwAAAA==.',
Ra='Rannmagnison:BAABLgAECn8UAAIEAAYJngZoMgDRAAAEAAYJngZoMgDRAAAAAA==.Raquoon:BAAALgAECgQJBwAAAA==.Ratfu:BAAALgADCgcJDQAAAA==.Razjin:BAABLgAECn8WAAIaAAgJGiPuCQDaAgAaAAgJGiPuCQDaAgAAAA==.',
Re='Reapér:BAAALgAECgkJBQAAAA==.Reze:BAABLgAFFH8HAAIdAAMJEg+4CADqAAAdAAMJEg+4CADqAAABLgAFFAcJHAAGAJ4fAA==.',
Rh='Rhaeynera:BAAALgAECgYJEAAAAA==.',
Ri='Riezen:BAAALgAECgEJAgAAAA==.Ringol:BAAALgAECgQJCQAAAA==.Rinorik:BAABLgAECn8eAAMHAAgJZhwrBQAoAgAHAAgJ+BsrBQAoAgAOAAYJCRn4FACjAQAAAA==.Rizzdor:BAAALgADCgcJCAABLgAECgcJCgABAAAAAA==.',
Ro='Rockbiter:BAAALgAECgEJAgAAAA==.Rockhhard:BAAALgAECgcJEgAAAA==.Roeken:BAAALgAECgYJEQAAAA==.Rollingman:BAAALgAECgQJBAAAAA==.',
Ru='Rudyshoots:BAAALgAFFAEJAgAAAA==.',
Ry='Rygaard:BAABLgAECn8eAAIhAAgJpB78BwCmAgAhAAgJpB78BwCmAgAAAA==.Ryutiz:BAABLgAECn8eAAIDAAcJ0SN5AQD0AQADAAcJ0SN5AQD0AQAAAA==.Ryward:BAAALgADCgcJBwAAAA==.',
Sa='Sacridas:BAAALgAECgEJAQABLgAECgcJHgADANEjAA==.Sako:BAAALgADCgUJCgAAAA==.Samsó:BAAALgAECggJDgAAAA==.Sapharina:BAABLgAECn8aAAIjAAgJoBbCFgDrAQAjAAgJoBbCFgDrAQAAAA==.Sassgrip:BAAALgADCgEJAQABLgAECgYJDAABAAAAAA==.Sassier:BAAALgAECgYJDAAAAA==.',
Sc='Scarcy:BAACLgAFFH8FAAIkAAMJMA5uDgAIAQAkAAMJMA5uDgAIAQAuAAQKfygAAiQACQlYGbEQAJ0CACQACQlYGbEQAJ0CAAAA.',
Se='Seacotton:BAAALgAECgYJCgAAAA==.Searfang:BAABLgAECn8aAAIMAAkJBxd3FAB7AgAMAAkJBxd3FAB7AgAAAA==.Seariel:BAAALgAECgUJBQAAAA==.Selestra:BAAALgAFFAIJAgAAAA==.Seraphymm:BAAALgADCgEJAQAAAA==.',
Sh='Shadowjacker:BAACLgAFFH8GAAIFAAIJKBtPEgCwAAAFAAIJKBtPEgCwAAAuAAQKfy4AAgUACQnwH4MHAFEDAAUACQnwH4MHAFEDAAAA.Shadowmidget:BAAALgAECgcJEgAAAA==.Shadrielis:BAABLgAECn8XAAMjAAgJTRqTAgA2AgAjAAgJTRqTAgA2AgASAAIJVQ3GbgBsAAAAAA==.Shanlao:BAAALgAECgIJAgABLgAFFAQJCAAHADwKAA==.Shirkka:BAAALgADCgMJBAAAAA==.Shurihito:BAAALgAECggJEwAAAA==.',
Si='Sieron:BAAALgAECgYJDgAAAA==.Silaslunark:BAAALgAECgYJBwAAAA==.Sixpack:BAAALgAECgcJEAAAAA==.',
Sk='Skeeterson:BAAALgADCgUJBwAAAA==.Skiððles:BAAALgAECgYJBgABLgAECggJFQAMAMkWAA==.Skytec:BAAALgADCgMJAwAAAA==.Skëëts:BAAALgAECgYJCgAAAA==.',
Sl='Slampoof:BAAALgADCgQJBQAAAA==.Slamslayer:BAAALgADCgIJAwAAAA==.Sleez:BAAALgAECgMJBgAAAA==.Sloodraga:BAAALgADCgYJBgAAAA==.',
Sm='Smallgregory:BAAALgAECgQJBwAAAA==.',
Sn='Sneakerzz:BAAALgADCgQJBAAAAA==.Sneakfury:BAAALgAECgYJCgAAAA==.Sneeler:BAAALgAECgEJAQAAAA==.Snowscayia:BAABLgAECn8kAAMcAAgJ8BMtJwDFAQAcAAgJ8BMtJwDFAQAbAAcJ9RQ4OwC4AQAAAA==.',
So='Solanar:BAABLgAECn8WAAIUAAYJNiXvEgB7AgAUAAYJNiXvEgB7AgAAAA==.Solmina:BAABLgAECn8dAAIXAAgJWxu5BwAtAgAXAAgJWxu5BwAtAgAAAA==.Somniatis:BAAALgAECgEJAQAAAA==.Soulciopath:BAAALgAECgUJCAAAAA==.',
Sp='Spicypants:BAAALgADCgMJAwAAAA==.Spicytaco:BAAALgAECgIJAwABLgAECgcJEgABAAAAAA==.Sprinklewiz:BAAALgADCgMJAwAAAA==.',
Sq='Squadie:BAABLgAECn8VAAICAAgJJAbhEwBcAQACAAgJJAbhEwBcAQAAAA==.Squanchs:BAACLgAFFH8GAAIaAAIJ2xlsCgCgAAAaAAIJ2xlsCgCgAAAuAAQKfxwAAxoACQlXH2YBALICABoACQlXH2YBALICAAwAAQkGAC0tAAEAAAEuAAQKBgkVABsASh4A.Squanchy:BAABLgAECn8VAAIbAAYJSh5rPACyAQAbAAYJSh5rPACyAQAAAA==.Squisquee:BAAALgADCgcJBwAAAA==.',
Sr='Srbojangles:BAAALgADCgYJBwABLgAECgcJIQAXAA8eAA==.Srry:BAABLgAECn8VAAIlAAcJrxrNKQATAgAlAAcJrxrNKQATAgAAAA==.',
St='Stinkvile:BAAALgAECgEJAQAAAA==.Stonebraid:BAAALgADCgEJAQAAAA==.Sturdy:BAAALgADCgEJAQAAAA==.',
Su='Sukuna:BAAALgAECgYJCAAAAA==.Sundance:BAAALgAECgUJCQAAAA==.Surmise:BAACLgAFFH8JAAIXAAQJKRwNFAB6AQAXAAQJKRwNFAB6AQAuAAQKfxkAAxcACAlrIskYABYDABcACAlrIskYABYDABkAAQm9HQEZAFAAAAAA.Sust:BAAALgAECgUJBQABLgAFFAQJCQAXACkcAA==.',
Sw='Swayzeetrain:BAAALgAFFAEJAQAAAA==.',
Ta='Tabius:BAABLgAECn8XAAMYAAcJISCHDADxAQAYAAcJISCHDADxAQAcAAMJvw6bFAC4AAAAAA==.Talkingtaco:BAAALgAECgcJEgAAAA==.Taln:BAAALgADCgUJBQABLgAECgYJEAABAAAAAA==.Tareul:BAAALgADCgIJAgAAAA==.Tarn:BAAALgAECggJCQAAAA==.',
Te='Temok:BAAALgAECgQJCAAAAA==.',
Th='Theabyss:BAAALgADCgIJAgABLgADCgcJEwABAAAAAA==.Thiccbush:BAAALgADCgEJAQAAAA==.Thirielnet:BAAALgAECgEJAQAAAA==.Thorkell:BAAALgADCgUJBQAAAA==.',
Ti='Tinkaballah:BAAALgAECgcJDgAAAA==.Tipy:BAAALgADCgUJBQAAAA==.',
To='Tore:BAACLgAFFH8FAAICAAIJKxMnFQCwAAACAAIJKxMnFQCwAAAuAAQKfyAAAgIACAkjIqoJAPwCAAIACAkjIqoJAPwCAAAA.Totemangge:BAAALgAECgcJDwAAAA==.',
Tr='Trifectas:BAAALgADCgYJCgAAAA==.Trinadel:BAABLgAECn8dAAIcAAgJpx0tDwCtAgAcAAgJpx0tDwCtAgAAAA==.Träitors:BAAALgADCgcJEwAAAA==.Tråitors:BAABLgAECn8YAAMHAAYJJyDENwAtAgAHAAYJJyDENwAtAgAOAAEJAAAkZQBFAAABLgADCgcJEwABAAAAAA==.',
Ts='Tsarevich:BAAALgAECgQJBwAAAA==.',
Tu='Tugtheshaman:BAABLgAECn8dAAIaAAgJohguGgBGAgAaAAgJohguGgBGAgAAAA==.',
Tw='Twileaf:BAABLgAECn8UAAIbAAYJ1wYxIAC0AAAbAAYJ1wYxIAC0AAAAAA==.Twoinchisbig:BAABLgAECn8kAAIhAAgJyhbcAwCgAQAhAAgJyhbcAwCgAQAAAA==.',
Ty='Typhoidmary:BAABLgAECn8XAAMHAAgJhAlxggBVAQAHAAcJhAlxggBVAQAOAAEJAAD9dQAuAAABLgABCgIJAgABAAAAAA==.',
['Té']='Térror:BAAALgAECgcJDwAAAA==.',
Un='Uncool:BAAALgADCgEJAQABLgAECgEJAQABAAAAAA==.',
Ur='Ursoc:BAABLgAECn8cAAMcAAgJmA6bDQAWAQAcAAcJmA6bDQAWAQAbAAIJHg9IKQBpAAAAAA==.Urteg:BAAALgADCgYJCwAAAA==.',
Uu='Uub:BAAALgAECgEJAQAAAA==.',
Va='Vairekor:BAAALgADCggJDgABLgAFFAQJCAAHADwKAA==.Valdria:BAAALgADCgUJBQAAAA==.Vanillaçake:BAAALgAECgEJAQAAAA==.Vanishja:BAAALgAECgQJBAAAAA==.Varkbyte:BAAALgAECgQJBwAAAA==.Varrik:BAABLgAECn8gAAMlAAgJ4yKTCQAVAwAlAAgJ4yKTCQAVAwAmAAEJzxkLOQBLAAAAAA==.',
Ve='Vec:BAAALgAECgYJDQAAAA==.Velamor:BAAALgAECgYJDwAAAA==.',
Vo='Volieu:BAAALgAECgYJDgAAAA==.Volklin:BAAALgAECgYJCgAAAA==.',
Vy='Vyrka:BAAALgAECgMJBAAAAA==.',
Wa='Wallstreet:BAAALgAECgUJBQAAAA==.',
We='Wegl:BAAALgAECgUJBQAAAA==.Werewithal:BAAALgADCgUJBQABLgAECgYJDgABAAAAAA==.Wesleypipes:BAAALgAECgEJAQAAAA==.Wetfloorsign:BAAALgAECgYJEQAAAA==.',
Wh='Wholeymilk:BAAALgADCgMJAwAAAA==.',
Wi='Wiindsslashh:BAAALgADCgUJBwAAAA==.Wilbur:BAAALgADCgQJBQAAAA==.',
Wo='Wonderx:BAAALgADCgIJAgAAAA==.Wonyoung:BAACLgAFFH8FAAISAAIJSiLaCQDJAAASAAIJSiLaCQDJAAAuAAQKfyQAAhIACQkTItoBAFkDABIACQkTItoBAFkDAAAA.',
Wu='Wuthrad:BAAALgADCgQJBAAAAA==.',
Xa='Xalaz:BAACLgAFFH8GAAMHAAMJLwr1EQDeAAAHAAMJCgr1EQDeAAAOAAEJVwJUGgBGAAAuAAQKfxoAAwcACAkqH202ADICAAcABwkqH202ADICAA4AAgkLFFdSAHcAAAAA.Xanaris:BAAALgADCgEJAQABLgAFFAIJBgAIAK4kAA==.Xandumbra:BAAALgADCgEJAQAAAA==.Xarosea:BAABLgAECn8mAAIEAAcJOCTyGADTAgAEAAcJOCTyGADTAgAAAA==.',
Xe='Xelojr:BAAALgADCggJFQAAAA==.',
Xh='Xhael:BAAALgADCgEJAQAAAA==.',
Xi='Xia:BAABLgAECn8bAAISAAgJMho/BAD4AQASAAgJMho/BAD4AQAAAA==.',
Xo='Xoilwings:BAAALgAECgEJAQAAAA==.Xooiill:BAAALgAECgYJDAAAAA==.',
Xp='Xpacer:BAAALgAECgYJCgAAAA==.',
Ye='Yekira:BAAALgADCgEJAgAAAA==.Yellowsnøw:BAAALgAECggJEgAAAA==.',
Yu='Yumeshade:BAAALgAECgUJCQAAAA==.',
Za='Zal:BAAALgAECgYJBgABLgAFFAMJCAAWAO8WAA==.Zamari:BAAALgADCgYJFQAAAA==.Zanzabar:BAABLgAECn8UAAIYAAgJ6wrBEACgAQAYAAgJ6wrBEACgAQAAAA==.Zathmage:BAAALgADCgMJAwAAAA==.Zaxin:BAAALgAECgYJCQAAAA==.',
Ze='Zelfie:BAAALgADCgUJBQAAAA==.Zeros:BAAALgAECgYJCQAAAA==.',
Zo='Zoerina:BAAALgAECgUJCAAAAA==.Zoobilong:BAAALgAECgUJDQAAAA==.',
Zx='Zxak:BAABLgAECn8cAAIGAAgJiCPuAABwAgAGAAgJiCPuAABwAgAAAA==.',
Zy='Zyahk:BAAALgADCgQJBQAAAA==.Zynn:BAAALgAECgEJAQAAAA==.',
['Zë']='Zën:BAAALgADCgYJBgABLgAECggJGgAFAPsTAA==.',
['Ða']='Ðashÿ:BAAALgAECgMJAwABLgAECgYJBgABAAAAAA==.',
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
