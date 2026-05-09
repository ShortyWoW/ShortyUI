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

local lookup = {'DeathKnight-Unholy','Druid-Feral','Druid-Restoration','Druid-Balance','Shaman-Enhancement','Priest-Shadow','Priest-Holy','Paladin-Retribution','Shaman-Restoration','Monk-Mistweaver','Monk-Windwalker','Hunter-BeastMastery','Hunter-Marksmanship','Warrior-Protection','Hunter-Survival','Evoker-Preservation','Evoker-Augmentation','Warrior-Fury','Unknown-Unknown','Paladin-Protection','Paladin-Holy','Mage-Frost','DemonHunter-Devourer','DemonHunter-Havoc','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','DeathKnight-Frost','Druid-Guardian','Shaman-Elemental','DeathKnight-Blood','Warrior-Arms','Monk-Brewmaster','Rogue-Subtlety','Priest-Discipline','Rogue-Assassination',}
local provider = {region='US',realm='Shandris',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abyssara:BAAALgAECgYJDQAAAA==.',
Ac='Acebets:BAAALgAECgEJAQAAAA==.Acedk:BAACLgAFFH8GAAIBAAMJqR8oOwAgAQABAAMJqR8oOwAgAQAuAAQKfxoAAgEACQlPIZkLAD4DAAEACQlPIZkLAD4DAAAA.',
Ad='Adorie:BAAALgAECgIJAwAAAA==.Adun:BAAALgADCgQJBAAAAA==.',
Ae='Aelphe:BAACLgAFFH8GAAICAAMJwBVtBAASAQACAAMJwBVtBAASAQAuAAQKfx8ABAIACQmvIe0AAHwDAAIACQmvIe0AAHwDAAMAAQlGB5eTADMAAAQAAQkuAhqOAB8AAAAA.Aelusius:BAABLgAECn8hAAIFAAgJ0B/IAgByAgAFAAgJ0B/IAgByAgAAAA==.Aeón:BAAALgAECgYJCwAAAA==.',
Ag='Aggen:BAAALgAECgcJEgAAAA==.',
Ak='Akashá:BAAALgADCgUJBQAAAA==.',
Al='Al:BAACLgAFFH8GAAMGAAMJXgmSFADWAAAGAAMJXgmSFADWAAAHAAIJbQQ6GgBtAAAuAAQKfyIAAwcACAltEkArAJsBAAcABwlpEUArAJsBAAYACAkCEqsaAGYBAAAA.Alandarus:BAAALgADCgEJAQAAAA==.Alexanderath:BAAALgAECgQJBwAAAA==.Alexânderson:BAAALgAECgUJDQAAAA==.Alkaline:BAAALgADCggJCAAAAA==.Alkatractite:BAABLgAECn8XAAIIAAYJlhTrUgBOAQAIAAYJlhTrUgBOAQAAAA==.Allenwalker:BAAALgADCgYJBgAAAA==.Alzul:BAAALgADCgUJBQAAAA==.',
Am='Amanita:BAAALgAECgcJBwABLgAECggJIgAJALoYAA==.Amasham:BAAALgAECgYJBgAAAA==.Amberness:BAAALgAFFAEJAQABLgAFFAMJBwAJACseAA==.Ambersoul:BAAALgADCgMJAwAAAA==.Amira:BAAALgAECgEJAQAAAA==.',
An='Anixa:BAAALgADCgMJAwAAAA==.Anyi:BAAALgAECgYJEgAAAA==.',
Ao='Aoi:BAABLgAECn8VAAMKAAYJFwg0MQDRAAAKAAYJFwg0MQDRAAALAAEJAABAfQAzAAAAAA==.',
Ar='Arrisia:BAABLgAECn8UAAMMAAYJuBAlSAA1AQAMAAYJuBAlSAA1AQANAAEJ0gPaLAAjAAAAAA==.Artemissy:BAAALgADCgQJBAAAAA==.Arthedain:BAACLgAFFH8LAAIOAAMJXx9sCgAKAQAOAAMJXx9sCgAKAQAuAAQKfyoAAg4ACQnPInsBAHIDAA4ACQnPInsBAHIDAAAA.Arthedaine:BAACLgAFFH8MAAIPAAMJ/xxZAgARAQAPAAMJ/xxZAgARAQAuAAQKfyYAAg8ACQkDI5gCABMDAA8ACQkDI5gCABMDAAEuAAUUAwkLAA4AXx8A.',
As='Asiea:BAAALgADCgQJBAAAAA==.',
Au='Augmentmyass:BAAALgAFFAEJAQAAAA==.Aushahin:BAAALgAECgYJBgABLgAECgYJFQAEAIgSAA==.Autumni:BAABLgAECn8ZAAIMAAcJCRf4KQCpAQAMAAcJCRf4KQCpAQAAAA==.Auvry:BAABLgAECn8aAAMQAAcJVhkYEAA5AgAQAAcJVhkYEAA5AgARAAIJqAnxXQAtAAAAAA==.',
Ay='Aymus:BAAALgAECgYJEAAAAA==.',
Az='Azliain:BAAALgAECgcJBgAAAA==.',
Ba='Bahamutfang:BAABLgAECn8XAAIIAAYJBgfGgADrAAAIAAYJBgfGgADrAAAAAA==.Bakala:BAABLgAECn8WAAMSAAYJWRSsIQBfAQASAAYJWRSsIQBfAQAOAAQJUQYcQABRAAAAAA==.Bangbang:BAABLgAECn8qAAIMAAkJqBVNHQDsAQAMAAkJqBVNHQDsAQAAAA==.',
Be='Beeyou:BAAALgADCgEJAQAAAA==.Belegaer:BAAALgAECggJEwAAAA==.Belenos:BAAALgADCgYJCQABLgADCgYJCQATAAAAAA==.Bellamy:BAAALgAECgEJAQAAAA==.Beltway:BAAALgADCgcJCgAAAA==.Bendini:BAACLgAFFH8GAAINAAMJHwvmDQDbAAANAAMJHwvmDQDbAAAuAAQKfx4AAg0ACQnSE3IqANgBAA0ACQnSE3IqANgBAAAA.Benmaverick:BAAALgAECgYJEAAAAA==.',
Bh='Bhe:BAABLgAECn8XAAIFAAYJTgqkDwAJAQAFAAYJTgqkDwAJAQAAAA==.',
Bi='Billymayzz:BAAALgADCgIJAgAAAA==.Bishop:BAABLgAECn8XAAIHAAYJKBvQEQDUAQAHAAYJKBvQEQDUAQAAAA==.',
Bl='Blackbird:BAAALgADCgYJBgAAAA==.',
Bo='Bobe:BAABLgAECn8gAAIOAAgJrBjoCADqAQAOAAgJrBjoCADqAQAAAA==.Bordok:BAAALgAECgYJEgAAAA==.Bowfléx:BAAALgAECgEJAQAAAA==.',
Br='Bruisewayne:BAAALgADCggJCAAAAA==.Brunco:BAABLgAECn8dAAMMAAcJTiD4EwAwAgAMAAcJTiD4EwAwAgANAAYJyRMhDAAqAQAAAA==.Brxndxn:BAAALgADCgUJBQAAAA==.Brëw:BAAALgADCgUJBQAAAA==.Brütäl:BAAALgADCgIJAgAAAA==.',
Bu='Bubbleyo:BAAALgADCgcJCAAAAA==.Bustaheals:BAAALgAECggJEwAAAA==.',
Bw='Bwasamdi:BAAALgAFFAEJAQAAAA==.',
Ca='Calypsa:BAAALgADCgMJBAAAAA==.Captplanet:BAAALgAECggJDAAAAA==.Cashartea:BAAALgAECgUJBQAAAA==.Cattleclysm:BAAALgADCgMJAwAAAA==.',
Ce='Ceindra:BAABLgAECn8XAAIFAAcJdB8pBQACAgAFAAcJdB8pBQACAgAAAA==.Celiñ:BAACLgAFFH8HAAMUAAMJZxTSBgCdAAAUAAMJ7QrSBgCdAAAIAAIJ9xMxSQCbAAAuAAQKfxsABAgACQm9G6Q4AEACAAgACAkZHaQ4AEACABQABAnRE1ggAJIAABUAAwnvBNVMAG8AAAAA.Celîn:BAAALgAECgQJBAABLgAFFAMJBwAUAGcUAA==.Ceronia:BAAALgADCgEJAQAAAA==.',
Ch='Chainstormer:BAAALgAECgUJCQAAAA==.Cherry:BAAALgAECgQJBAAAAA==.Chibby:BAAALgAECgQJBAAAAA==.Chuladk:BAAALgAECgQJBQAAAA==.',
Cl='Cleymour:BAAALgADCgcJDgAAAA==.Cløudstrife:BAAALgAECgEJAQAAAA==.',
Co='Colbalt:BAABLgAECn8UAAIGAAcJdQd/LgDdAAAGAAcJdQd/LgDdAAAAAA==.Cor:BAAALgAECgIJAQAAAA==.Corrosive:BAAALgAECgYJBQAAAA==.Cotilion:BAAALgADCgMJAwAAAA==.',
Cr='Creation:BAAALgAECgYJEAABLgAECggJIQAFANAfAA==.Crunky:BAABLgAECn8VAAIKAAYJIRC8JAAhAQAKAAYJIRC8JAAhAQAAAA==.',
Cu='Cuddleybunni:BAAALgADCgMJAwAAAA==.Cuddlymethod:BAAALgADCgUJBgAAAA==.',
['Có']='Cól:BAABLgAECn8oAAIWAAkJNh5oMgCpAgAWAAkJNh5oMgCpAgAAAA==.',
Da='Dahealzrhere:BAAALgAECgQJBAAAAA==.Dalel:BAABLgAECn8ZAAIXAAYJIiAiJACwAQAXAAYJIiAiJACwAQAAAA==.Dameond:BAAALgAECgEJAQAAAA==.',
De='Deadisdead:BAAALgAECgYJDgAAAA==.Deadlyglow:BAAALgADCgcJDAABLgAECgYJCAATAAAAAA==.Deathkratos:BAAALgADCgYJCQAAAA==.Demiurgos:BAAALgAECgcJDgAAAA==.Demonicteli:BAABLgAECn8WAAIYAAkJlxmYEABdAgAYAAkJlxmYEABdAgAAAA==.Demonopii:BAAALgAECgQJCAAAAA==.Dermot:BAABLgAECn8qAAQZAAgJ6CB0AwC6AgAZAAcJZCJ0AwC6AgAaAAUJWh1hUwAxAQAbAAIJCyYHIQBuAAAAAA==.',
Dh='Dhiying:BAAALgAECgYJBwAAAA==.',
Di='Dippindots:BAABLgAECn8dAAMEAAcJlRDnHABNAQAEAAcJlRDnHABNAQADAAEJZQGH7AAVAAAAAA==.Dixmen:BAAALgAECgYJCAAAAA==.',
Dk='Dkäri:BAAALgAECgYJDQAAAA==.',
Do='Dolemen:BAABLgAECn8bAAIIAAYJVAcAhADkAAAIAAYJVAcAhADkAAAAAA==.Domaon:BAABLgAECn8eAAIYAAgJix9YBACFAgAYAAgJix9YBACFAgAAAA==.Domshammy:BAAALgADCgcJCAABLgAECggJHgAYAIsfAA==.Doombunny:BAAALgAECgUJCQABLgAECggJIwAMAAMWAA==.Doubt:BAAALgAECgYJDAAAAA==.',
Dr='Dranthrax:BAAALgAECgUJCQAAAA==.',
Du='Dunigan:BAABLgAECn8eAAIIAAgJUQ6yPwCGAQAIAAgJUQ6yPwCGAQAAAA==.Dunstan:BAAALgAECgYJDwAAAA==.Durmet:BAAALgAECgUJBQAAAA==.Dustos:BAAALgADCgIJAgAAAA==.',
Eb='Ebeast:BAABLgAECn8mAAIPAAkJXw+lCQAKAgAPAAkJXw+lCQAKAgAAAA==.Ebingus:BAAALgADCgYJBgAAAA==.',
Ei='Eifaun:BAEALgAECgUJCQAAAA==.',
El='Elexidor:BAAALgAECgcJDAAAAA==.Elorrna:BAAALgADCgYJBgAAAA==.',
Er='Erathen:BAAALgADCgUJBQAAAA==.',
Ey='Eyeet:BAAALgADCgkJEAAAAA==.',
Fa='Facade:BAAALgAECgQJBQAAAA==.Facepalm:BAAALgAECggJDwAAAA==.Faked:BAAALgADCgEJAQABLgAECgYJDAATAAAAAA==.Falion:BAAALgAECgYJBgAAAA==.Fallensaints:BAAALgAECgYJCwAAAA==.Falshalad:BAABLgAECn8YAAIDAAcJJhPxVQBRAQADAAcJJhPxVQBRAQAAAA==.Falyy:BAAALgADCgQJBAAAAA==.',
Fe='Fentak:BAABLgAECn8YAAIcAAgJzgp2BgBTAQAcAAgJzgp2BgBTAQAAAA==.',
Fi='Fierytotes:BAAALgADCgYJEgAAAA==.Finka:BAAALgAECgMJAwAAAA==.',
Fl='Flamedaddy:BAAALgAECgYJDwAAAA==.',
Fo='Fog:BAAALgAECgEJAgAAAA==.Forgotmymeds:BAABLgAECn8nAAIJAAkJBxOVFAAQAgAJAAkJBxOVFAAQAgAAAA==.Foxmccloud:BAABLgAECn8VAAIJAAYJDx8RFAAUAgAJAAYJDx8RFAAUAgAAAA==.',
Fr='Fruitloop:BAAALgAECggJEwAAAA==.',
Fu='Fuil:BAAALgADCgUJBQAAAA==.',
Fy='Fyznen:BAAALgAECgQJBAAAAA==.',
Ga='Garim:BAAALgADCgcJBwAAAA==.Gaviriard:BAAALgADCgMJAwAAAA==.',
Ge='Gebran:BAAALgAECgEJAQAAAA==.Gellywoo:BAABLgAECn8ZAAISAAYJ2BTkIQBeAQASAAYJ2BTkIQBeAQAAAA==.',
Gh='Ghostofonyx:BAAALgADCgcJFQAAAA==.',
Gi='Girlypop:BAAALgAECgQJBgAAAA==.',
Go='Golaoth:BAABLgAECn8WAAIQAAYJrhnxCQC5AQAQAAYJrhnxCQC5AQAAAA==.Gooftoo:BAABLgAECn8UAAIDAAcJJx8NLwDwAQADAAcJJx8NLwDwAQAAAA==.',
Gr='Greycie:BAAALgADCgkJEwAAAA==.Greyfax:BAAALgADCgcJDQAAAA==.Greymoon:BAABLgAECn8VAAIdAAYJ3BgPCwBmAQAdAAYJ3BgPCwBmAQAAAA==.',
Gu='Guigondk:BAAALgAECgcJBgAAAA==.',
Gy='Gyre:BAAALgAECgQJCgAAAA==.',
Ha='Happyendings:BAAALgAECgUJBwAAAA==.',
He='Helbafx:BAAALgAECgQJBAAAAA==.',
Hi='Hiroshì:BAAALgAECgEJAQAAAA==.',
Ho='Homewrecker:BAAALgAECgYJEQAAAA==.',
Hu='Hunnee:BAAALgADCgYJCwAAAA==.',
Ic='Icelace:BAAALgAECgEJAQAAAA==.',
If='Ifearnobeer:BAABLgAECn8dAAIeAAgJWwngJgAkAQAeAAgJWwngJgAkAQAAAA==.',
Ii='Iifelike:BAAALgAECgUJBQABLgAECggJEAATAAAAAA==.',
In='Inters:BAAALgAECgUJBgAAAA==.',
Ir='Ironspark:BAAALgAECgYJDQAAAA==.',
Is='Isabel:BAACLgAFFH8KAAIDAAMJCA7fJADCAAADAAMJCA7fJADCAAAuAAQKfxQAAgMACAnyFyskACoCAAMACAnyFyskACoCAAAA.Isaetr:BAAALgAECgEJAQAAAA==.',
Ja='Jackôdaniels:BAAALgADCgkJDgAAAA==.Jaiantobea:BAABLgAECn8XAAIJAAYJNBMjLABnAQAJAAYJNBMjLABnAQAAAA==.Jake:BAAALgAECgEJAQAAAA==.Jakulista:BAAALgADCgcJFQAAAA==.Jashugan:BAAALgADCgQJBAAAAA==.Jawn:BAABLgAECn8XAAILAAgJtg0nGABkAQALAAgJtg0nGABkAQAAAA==.',
Je='Jessuss:BAAALgAECgYJEgAAAA==.',
Ju='Jude:BAAALgAECgMJBwAAAA==.Juggernàut:BAAALgAECgYJEAAAAA==.Junipermoon:BAAALgADCgYJCQAAAA==.',
Ka='Kajas:BAAALgAECgMJAwAAAA==.Kalahandra:BAACLgAFFH8FAAIDAAMJqQOEKgCjAAADAAMJqQOEKgCjAAAuAAQKfyIAAgMACQkUC/xGAIYBAAMACQkUC/xGAIYBAAAA.Kalebeesd:BAAALgAECgYJEAAAAA==.Karthdh:BAAALgADCgMJAwABLgADCggJCAATAAAAAA==.Kasey:BAAALgADCgEJAQAAAA==.Katithianna:BAAALgADCgQJAwAAAA==.Katotan:BAABLgAECn8eAAIDAAgJPRR0IADBAQADAAgJPRR0IADBAQAAAA==.Kawk:BAABLgAECn8oAAIUAAkJHR6KBAC7AgAUAAkJHR6KBAC7AgAAAA==.Kazatreshan:BAAALgADCgcJDgAAAA==.Kazragor:BAABLgAECn8lAAIeAAgJ+SP7DgC3AgAeAAgJ+SP7DgC3AgABLgAFFAMJAwATAAAAAA==.',
Ke='Kebob:BAAALgAECggJEAAAAA==.Kenziedadght:BAAALgAECgIJBQAAAA==.Keyboärd:BAABLgAECn8bAAIOAAgJihtUBgAvAgAOAAgJihtUBgAvAgAAAA==.',
Ki='Kilo:BAAALgADCgEJAgAAAA==.Kippo:BAECLgAFFH8HAAIWAAQJigUJMwDRAAAWAAQJigUJMwDRAAAuAAQKfyMAAhYACAmWFz1KAFgCABYACAmWFz1KAFgCAAEuAAUUBQkHAAEAZQgA.',
Kl='Klazarth:BAACLgAFFH8HAAIGAAMJMRcIEAAPAQAGAAMJMRcIEAAPAQAuAAQKfx4AAgYACQmpHokNAKoCAAYACQmpHokNAKoCAAAA.',
Ko='Kombat:BAAALgAECgUJCwAAAA==.Korllan:BAAALgAECgEJAQAAAA==.Kossnen:BAAALgAECgYJDQAAAA==.',
Kr='Krelivus:BAAALgAECgUJBgAAAA==.',
Ku='Kuda:BAABLgAECn8WAAIWAAYJ3RANcQAvAQAWAAYJ3RANcQAvAQAAAA==.',
Kw='Kwanu:BAAALgAECgIJAgAAAA==.',
['Kó']='Kóñä:BAAALgADCgkJDAABLgAECgYJCwATAAAAAA==.',
La='Lantern:BAAALgADCgUJBQAAAA==.Larke:BAAALgAECgEJAgAAAA==.Lasa:BAAALgAECgYJBwAAAA==.Lasloo:BAAALgAECgUJDgAAAA==.Laylani:BAAALgAECgMJBAAAAA==.Layllis:BAAALgADCgQJBgAAAA==.',
Le='Legiondary:BAABLgAECn8cAAIXAAkJ8Rc1LgBEAgAXAAkJ8Rc1LgBEAgAAAA==.Lesabor:BAAALgADCgYJBgAAAA==.',
Li='Licknstick:BAAALgAECgMJBgAAAA==.Lir:BAAALgADCgIJAwAAAA==.Lisan:BAAALgAECggJEAAAAA==.Lisanalgaib:BAAALgAECgEJAgAAAA==.Littledicey:BAAALgADCgcJCwAAAA==.',
Lo='Lothan:BAAALgADCgkJCQABLgAECgYJFQAEAIgSAA==.',
Lu='Lucien:BAAALgAECgUJCgAAAA==.Luciä:BAABLgAECn8YAAIfAAYJrRI+FwAVAQAfAAYJrRI+FwAVAQAAAA==.Lucymoon:BAAALgAECgYJBQAAAA==.',
Ly='Lynex:BAAALgAECgQJBwAAAA==.',
Ma='Machoman:BAAALgADCgcJBwAAAA==.Magdeth:BAAALgADCgYJEAAAAA==.Magiann:BAAALgADCgEJAQAAAA==.Maiama:BAAALgAECgYJBwAAAA==.Marabelle:BAAALgAECggJDAAAAA==.Massack:BAAALgAECggJEwAAAA==.',
Mc='Mcknight:BAAALgAECgYJBgAAAA==.',
Me='Merex:BAAALgADCgEJAQAAAA==.Mero:BAAALgAECgYJBgAAAA==.Mew:BAAALgADCgEJAQABLgAECggJHwAVAJ0XAA==.',
Mi='Midgetmàniàc:BAAALgAECgMJBAAAAA==.Mikebeard:BAAALgADCgEJAQAAAA==.',
Mo='Moktar:BAAALgAECgYJBwAAAA==.Moobear:BAAALgADCgQJBAAAAA==.',
Mu='Muldoinit:BAAALgAECggJEwAAAA==.',
My='Myroslava:BAAALgADCgkJEwAAAA==.',
['Më']='Mërikh:BAAALgADCgMJAwABLgADCgYJBgATAAAAAA==.',
Na='Nadorian:BAAALgAECgEJAQAAAA==.',
Ne='Neb:BAAALgAECgcJEwAAAA==.Nehemia:BAAALgAECgYJEQAAAA==.Nerilestis:BAAALgAECgEJAQAAAA==.Netherrogue:BAAALgAECgcJDgAAAA==.',
Ni='Nicage:BAAALgAECgQJBAABLgAFFAMJBwAWAAkdAA==.Nightdreams:BAAALgADCgcJCQAAAA==.',
Ny='Nytelytë:BAAALgAECgYJCQABLgAFFAMJBwAaAG8TAA==.Nytemayer:BAACLgAFFH8HAAIaAAMJbxPSOQDtAAAaAAMJbxPSOQDtAAAuAAQKfyMABBoACQn/HOEyAEECABoABwlQHOEyAEECABkAAwmYH4ozAOkAABsAAQkAAC4pAE0AAAAA.',
Ob='Obmakare:BAABLgAECn8VAAICAAYJAAzjEAAMAQACAAYJAAzjEAAMAQAAAA==.Oboñ:BAAALgAECgYJDAAAAA==.Obsfuyung:BAABLgAECn8ZAAILAAYJlBGfIwAMAQALAAYJlBGfIwAMAQAAAA==.',
Or='Orcc:BAAALgADCggJBwAAAA==.',
Pa='Paley:BAAALgAECgYJBgAAAA==.Palpatine:BAAALgAECgEJAQAAAA==.',
Pe='Peopleperson:BAAALgADCgQJAQAAAA==.Performance:BAAALgAECgYJBgAAAA==.',
Pi='Pinji:BAAALgAECgIJAgAAAA==.Pinkypoo:BAABLgAECn8bAAMBAAcJQxcQUABMAQABAAYJlRUQUABMAQAfAAYJrBatIwAjAQAAAA==.',
Pl='Plato:BAABLgAECn8UAAQVAAcJnhqbDwAjAgAVAAcJnhqbDwAjAgAIAAEJ2wFQIgEXAAAUAAEJAACTPAAAAAAAAA==.',
Po='Poiet:BAAALgAECgEJAgAAAA==.Poîsonivy:BAABLgAECn8XAAMZAAYJ2hBMCwAgAQAZAAYJ2hBMCwAgAQAaAAEJNgFu8wAPAAAAAA==.',
Ps='Psyche:BAAALgADCgkJDgAAAA==.',
Py='Pyrokos:BAACLgAFFH8FAAIWAAMJUBmFQQAIAQAWAAMJUBmFQQAIAQAuAAQKfyEAAhYACAnsIGc3AMUBABYACAnsIGc3AMUBAAAA.Pyrö:BAAALgAECgkJCQAAAA==.',
Qu='Qu:BAABLgAECn8oAAMgAAkJEx5uBgBlAgAgAAkJEx5uBgBlAgASAAIJTQonlQBrAAAAAA==.Quellia:BAACLgAFFH8NAAIVAAQJMh+QCwBrAQAVAAQJMh+QCwBrAQAuAAQKfxwAAhUACAmTINMMALMCABUACAmTINMMALMCAAAA.',
Ra='Rangel:BAABLgAECn8YAAISAAgJ7BDTHQB6AQASAAgJ7BDTHQB6AQAAAA==.Rattlesnake:BAAALgADCgYJBgAAAA==.',
Re='Redacted:BAAALgADCgMJAwAAAA==.Renägäde:BAAALgAECgYJDwAAAA==.Rexulti:BAAALgAECgEJAQAAAA==.',
Ri='Ricodadawg:BAAALgADCgEJAQAAAA==.Rizen:BAAALgAECgQJBAAAAA==.',
Ro='Roija:BAACLgAFFH8HAAIWAAMJCR0QPQAZAQAWAAMJCR0QPQAZAQAuAAQKfyMAAhYACAkkJNQJANkCABYACAkkJNQJANkCAAAA.',
Ru='Runningbearr:BAAALgADCgYJBgAAAA==.Runningmage:BAAALgADCgcJDAAAAA==.Rurahk:BAACLgAFFH8JAAIIAAQJEQ9XHAA8AQAIAAQJEQ9XHAA8AQAuAAQKfyoAAggACAkEIZ4VAOgCAAgACAkEIZ4VAOgCAAAA.',
['Rõ']='Rõbb:BAACLgAFFH8HAAIIAAMJVR7OIgAiAQAIAAMJVR7OIgAiAQAuAAQKfyQAAggACQnUH5gOABkDAAgACQnUH5gOABkDAAAA.',
Sa='Sabaak:BAAALgAECgYJDwAAAA==.Sacerdote:BAAALgADCgUJBQAAAA==.Saeriin:BAAALgAECgYJDAAAAA==.Saintsnyder:BAAALgAECgkJDgAAAA==.Saithis:BAAALgAECgQJDAAAAA==.Saltycrank:BAAALgADCgUJBQAAAA==.Sanorasong:BAEALgAECgYJEwAAAA==.Saphaa:BAAALgADCgEJAQAAAA==.Sardine:BAAALgADCgMJAwAAAA==.Sarylin:BAAALgAECgcJDAAAAA==.Satanshealer:BAAALgADCgYJCQAAAA==.Satsuki:BAAALgAECgYJCgAAAA==.',
Sc='Schio:BAABLgAECn8VAAIZAAYJExKsCwAZAQAZAAYJExKsCwAZAQAAAA==.',
Se='Sean:BAAALgADCgYJBgAAAA==.Seananagíns:BAAALgADCgYJCwAAAA==.Sections:BAAALgADCgkJHAAAAA==.Severussnape:BAAALgAECgcJEwAAAA==.',
Sh='Shambs:BAACLgAFFH8HAAIJAAMJKx4PGQAIAQAJAAMJKx4PGQAIAQAuAAQKfxsAAgkACQnPHikGAA8DAAkACQnPHikGAA8DAAAA.Shamrorag:BAAALgAECgUJCwAAAA==.Shinron:BAAALgADCgYJDwAAAA==.Shökan:BAAALgADCgkJFgAAAA==.',
Si='Sighah:BAAALgAECggJCQAAAA==.Sinensis:BAAALgAECggJEwAAAA==.Singood:BAAALgAECgcJBwAAAA==.Sinnecro:BAABLgAECn8aAAIBAAkJ4R5gIADAAgABAAkJ4R5gIADAAgAAAA==.Sinshift:BAAALgADCgUJBQAAAA==.',
Sk='Skadoosh:BAAALgADCgYJCQABLgAECgYJGQAXACIgAA==.Skarletflame:BAAALgAECgYJEAAAAA==.',
Sl='Slather:BAABLgAECn8aAAIQAAgJcBAFGADVAQAQAAgJcBAFGADVAQAAAA==.Slaycie:BAABLgAECn8VAAIWAAYJnQwxdwAiAQAWAAYJnQwxdwAiAQAAAA==.Slofinger:BAAALgADCgYJCgAAAA==.',
Sn='Sneeb:BAAALgAECgEJAQAAAA==.',
So='Songli:BAEALgADCgEJAQABLgAECgYJEwATAAAAAA==.Sorne:BAAALgAECgEJAQAAAA==.',
Sp='Spaghett:BAABLgAECn8aAAMLAAgJ/xFnIgAUAQAhAAgJAg9/QQA9AQALAAYJJhNnIgAUAQAAAA==.Springtotem:BAABLgAECn8VAAIEAAYJiBKUMwByAQAEAAYJiBKUMwByAQAAAA==.',
St='Stachel:BAAALgAECgIJAgAAAA==.Stanger:BAAALgAECgQJBAAAAA==.Storaxota:BAAALgAFFAUJAgAAAA==.Stormdk:BAAALgADCgcJCQAAAA==.',
Su='Sugondese:BAABLgAECn8XAAIdAAYJCxmJCwBbAQAdAAYJCxmJCwBbAQABLgAFFAQJDAAiADIYAA==.Superneo:BAAALgAECgYJBgABLgAFFAMJCgAEAOciAA==.Suvion:BAAALgAECgcJEwABLgAECggJGgAeAAkaAA==.',
Sy='Sylinial:BAAALgAECgEJAQAAAA==.Sylvanis:BAAALgAECgUJBwAAAA==.Syrden:BAAALgAECggJCgAAAA==.',
Sz='Szadèk:BAAALgAECgYJBgAAAA==.',
['Sÿ']='Sÿphallus:BAABLgAECn8SAAIYAAgJrhReDgCbAQAYAAgJrhReDgCbAQAAAA==.',
Ta='Tael:BAABLgAECn8cAAISAAgJ3h1bFwCsAQASAAgJ3h1bFwCsAQAAAA==.Tagreth:BAAALgADCgQJBAAAAA==.Tangylizard:BAACLgAFFH8HAAIjAAMJlQs2GQDZAAAjAAMJlQs2GQDZAAAuAAQKfyoAAyMACAnuGWYVAPwBACMACAnuGWYVAPwBAAcAAQkFFql7ADoAAAAA.Tattoospyder:BAABLgAECn8aAAIDAAcJTwh0TADhAAADAAcJTwh0TADhAAAAAA==.Tatyanafour:BAAALgADCgIJAQAAAA==.Tatyanathirt:BAAALgADCgYJBgAAAA==.',
Te='Tessla:BAABLgAECn8aAAIeAAgJCRqtDQADAgAeAAgJCRqtDQADAgAAAA==.',
Th='Thafrggnpope:BAAALgADCgEJAQAAAA==.Thelarï:BAAALgAECggJEwAAAA==.Thellany:BAAALgAECgEJAQAAAA==.Theshiznitz:BAAALgAECgMJAwAAAA==.Thors:BAAALgAECgcJEQAAAA==.Thundertoes:BAAALgAECggJEwAAAA==.Thÿsucc:BAAALgADCgcJBwAAAA==.',
Ti='Tia:BAAALgADCgcJFAAAAA==.Timmy:BAAALgAECgEJAwABLgAECgYJDgATAAAAAA==.',
To='Tommychong:BAAALgAECgIJAgAAAA==.Tonik:BAAALgAECgQJCgAAAA==.Torgoth:BAABLgAECn8XAAIFAAYJBRGTDAA/AQAFAAYJBRGTDAA/AQAAAA==.Toshido:BAAALgAECgQJBgAAAA==.',
Tr='Traetor:BAAALgAECggJEwAAAA==.Trakker:BAAALgADCgQJBAAAAA==.Trevize:BAAALgAECgQJCQAAAA==.',
Tt='Ttelloc:BAAALgADCgIJAgAAAA==.',
Tu='Tusiny:BAAALgAECgEJAQAAAA==.',
Ub='Ubully:BAAALgADCgQJBAAAAA==.',
Ul='Ultane:BAAALgAECgUJCgAAAA==.',
Un='Unreal:BAAALgADCgQJBAAAAA==.',
Va='Vaera:BAAALgADCgQJBAAAAA==.Valastae:BAAALgAECgYJDQAAAA==.Valiantaine:BAABLgAECn8mAAMIAAkJdB9wKgB6AgAIAAgJ/R9wKgB6AgAVAAkJgg2xPQCCAQABLgAFFAMJBwAXAPgSAA==.Valiantaint:BAACLgAFFH8HAAIXAAMJ+BIYLgD4AAAXAAMJ+BIYLgD4AAAuAAQKfyIAAhcACAn7HmYtAEgCABcACAn7HmYtAEgCAAAA.Valiantrain:BAAALgAECgEJAgABLgAFFAMJBwAXAPgSAA==.Valyulon:BAAALgADCgMJAwABLgAFFAMJBwAXAPgSAA==.Vanjin:BAAALgADCgUJBQAAAA==.',
Ve='Velherun:BAAALgAECggJDQAAAA==.Vendeldh:BAABLgAECn8sAAIXAAkJuCPvDABmAgAXAAkJuCPvDABmAgAAAA==.Veni:BAAALgAECgYJBgAAAA==.Vexxaa:BAABLgAECn8VAAIMAAYJxAziTQAkAQAMAAYJxAziTQAkAQAAAA==.',
Vi='Virajr:BAAALgAECgYJCwAAAA==.Vishus:BAAALgADCgUJBQAAAA==.Visiôn:BAABLgAECn8bAAISAAkJ8wcvHQB/AQASAAkJ8wcvHQB/AQAAAA==.Vissiction:BAAALgAECggJDwAAAA==.Vistine:BAABLgAECn8eAAIUAAgJMwomFQD4AAAUAAgJMwomFQD4AAAAAA==.Vitez:BAAALgAECggJEQAAAA==.',
Vo='Voidscar:BAAALgADCgcJBwAAAA==.',
Wa='Warhurts:BAAALgAECgMJAwAAAA==.Waterbloom:BAAALgADCgMJAwAAAA==.',
We='Weave:BAAALgAECgYJDgAAAA==.Wendy:BAABLgAECn8iAAIJAAgJuhgVGQDpAQAJAAgJuhgVGQDpAQAAAA==.',
Wi='Win:BAAALgAECgEJAQABLgAECgkJKwAaADgTAA==.Winkster:BAABLgAECn8kAAIIAAkJWSS1CwAwAwAIAAkJWSS1CwAwAwAAAA==.',
Xa='Xanadu:BAABLgAECn8eAAIjAAgJSxs6CQBFAgAjAAgJSxs6CQBFAgAAAA==.Xarinia:BAABLgAECn8aAAMRAAYJgg7IKAAMAQARAAYJgg7IKAAMAQAQAAUJ4wePMQDjAAAAAA==.',
Xd='Xdynasty:BAACLgAFFH8MAAIiAAQJMhiECwBSAQAiAAQJMhiECwBSAQAuAAQKfyUAAyIACAk6JCkMANUCACIACAk3JCkMANUCACQABgnDG+UNADwBAAAA.',
Xo='Xo:BAABLgAECn8rAAQaAAkJOBOKPwBrAQAaAAkJIg+KPwBrAQAZAAUJGhN4JQAxAQAbAAEJAABCMAA9AAAAAA==.',
Xy='Xyfarion:BAAALgADCgYJBgAAAA==.Xyril:BAAALgAECgEJAQAAAA==.',
Ya='Yaasnah:BAAALgADCggJCAAAAA==.',
Za='Zabazz:BAABLgAECn8ZAAIJAAgJUhE+KQB4AQAJAAgJUhE+KQB4AQAAAA==.Zabenir:BAAALgAECgYJEgAAAA==.Zané:BAAALgAECgEJAgAAAA==.Zapan:BAAALgADCgUJBQAAAA==.',
Ze='Zeverai:BAAALgADCgkJCgAAAA==.',
Zi='Ziria:BAAALgADCgQJBAAAAA==.',
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
