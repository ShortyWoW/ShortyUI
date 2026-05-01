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

local lookup = {'DeathKnight-Unholy','Druid-Feral','Druid-Restoration','Druid-Balance','Shaman-Enhancement','Priest-Holy','Priest-Shadow','Shaman-Restoration','Warrior-Protection','Hunter-Survival','Hunter-BeastMastery','Evoker-Preservation','Evoker-Augmentation','Hunter-Marksmanship','Paladin-Retribution','Paladin-Holy','Paladin-Protection','Mage-Frost','Unknown-Unknown','DemonHunter-Havoc','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Shaman-Elemental','Monk-Windwalker','DemonHunter-Devourer','DeathKnight-Blood','Warrior-Arms','Warrior-Fury','Rogue-Subtlety','Priest-Discipline','Rogue-Assassination',}
local provider = {region='US',realm='Shandris',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abyssara:BAAALgAECgYJDQAAAA==.',
Ac='Acebets:BAAALgAECgEJAQAAAA==.Acedk:BAABLgAECn8aAAIBAAkJTyGcCwA+AwABAAkJTyGcCwA+AwAAAA==.',
Ad='Adorie:BAAALgAECgIJAwAAAA==.Adun:BAAALgADCgQJBAAAAA==.',
Ae='Aelphe:BAABLgAECn8fAAQCAAkJryHuAAB8AwACAAkJryHuAAB8AwADAAEJSgdSdwAzAAAEAAEJLgIVjgAfAAAAAA==.Aelusius:BAABLgAECn8XAAIFAAcJUhvvBQCyAQAFAAcJUhvvBQCyAQAAAA==.Aeón:BAAALgAECgUJCQAAAA==.',
Ag='Aggen:BAAALgAECgUJDAAAAA==.',
Ak='Akashá:BAAALgADCgUJBQAAAA==.',
Al='Al:BAABLgAECn8iAAMGAAgJbBI7KwCbAQAGAAcJaRE7KwCbAQAHAAgJ+hHMEgBvAQAAAA==.Alandarus:BAAALgADCgEJAQAAAA==.Alexanderath:BAAALgAECgQJBwAAAA==.Alexânderson:BAAALgAECgUJDQAAAA==.Alkaline:BAAALgADCggJCAAAAA==.Alkatractite:BAAALgAECgYJEgAAAA==.Alzul:BAAALgADCgUJBQAAAA==.',
Am='Amanita:BAAALgADCgkJIAABLgAECggJIgAIALkYAA==.Amasham:BAAALgAECgYJBgAAAA==.Amberness:BAAALgAFFAEJAQAAAA==.Ambersoul:BAAALgADCgMJAwAAAA==.',
An='Anixa:BAAALgADCgMJAwAAAA==.Anyi:BAAALgAECgYJDAAAAA==.',
Ao='Aoi:BAAALgAECgYJDwAAAA==.',
Ar='Arrisia:BAAALgAECgYJDgAAAA==.Artemissy:BAAALgADCgQJBAAAAA==.Arthedain:BAACLgAFFH8IAAIJAAMJhRygBwAMAQAJAAMJhRygBwAMAQAuAAQKfykAAgkACQnOInsBAHIDAAkACQnOInsBAHIDAAAA.Arthedaine:BAACLgAFFH8JAAIKAAMJ/xxZAgARAQAKAAMJ/xxZAgARAQAuAAQKfyUAAgoACQn4IZgCABMDAAoACQn4IZgCABMDAAEuAAUUAwkIAAkAhRwA.',
As='Asiea:BAAALgADCgQJBAAAAA==.',
Au='Augmentmyass:BAAALgAFFAEJAQAAAA==.Aushahin:BAAALgAECgYJBgABLgAECgYJFQAEAIYSAA==.Autumni:BAABLgAECn8YAAILAAcJ1xVLIwCQAQALAAcJ1xVLIwCQAQAAAA==.Auvry:BAABLgAECn8aAAMMAAcJVRkaEAA5AgAMAAcJVRkaEAA5AgANAAIJnwlISgAtAAAAAA==.',
Ay='Aymus:BAAALgAECgYJEAAAAA==.',
Az='Azliain:BAAALgAECgcJBgAAAA==.',
Ba='Bahamutfang:BAAALgAECgYJEQAAAA==.Bakala:BAAALgAECgYJEAAAAA==.Bangbang:BAABLgAECn8kAAILAAgJ5RQsHgCrAQALAAgJ5RQsHgCrAQAAAA==.',
Be='Beeyou:BAAALgADCgEJAQAAAA==.Belegaer:BAAALgAECgYJDQAAAA==.Bellamy:BAAALgAECgEJAQAAAA==.Beltway:BAAALgADCgcJCgAAAA==.Bendini:BAABLgAECn8dAAIOAAkJDBP/KgDSAQAOAAkJDBP/KgDSAQAAAA==.Benmaverick:BAAALgAECgYJEAAAAA==.',
Bh='Bhe:BAAALgAECgYJEQAAAA==.',
Bi='Billymayzz:BAAALgADCgIJAgAAAA==.Bishop:BAAALgAECgYJEQAAAA==.',
Bo='Bobe:BAABLgAECn8fAAIJAAcJEhvCBwC/AQAJAAcJEhvCBwC/AQAAAA==.Bordok:BAAALgAECgUJDAAAAA==.Bowfléx:BAAALgAECgEJAQAAAA==.',
Br='Brunco:BAABLgAECn8XAAMLAAcJKBh3JgB/AQALAAYJ0Bd3JgB/AQAOAAYJuhONCQA8AQAAAA==.Brxndxn:BAAALgADCgUJBQAAAA==.Brëw:BAAALgADCgUJBQAAAA==.Brütäl:BAAALgADCgIJAgAAAA==.',
Bu='Bubbleyo:BAAALgADCgcJCAAAAA==.Bustaheals:BAAALgAECgYJDQAAAA==.',
Bw='Bwasamdi:BAAALgAFFAEJAQAAAA==.',
Ca='Calypsa:BAAALgADCgMJBAAAAA==.Captplanet:BAAALgAECgYJBgAAAA==.Cashartea:BAAALgAECgUJBQAAAA==.Cattleclysm:BAAALgADCgMJAwAAAA==.',
Ce='Ceindra:BAAALgAFFAEJAQAAAA==.Celiñ:BAABLgAECn8aAAQPAAkJuxunOABAAgAPAAgJFx2nOABAAgAQAAMJ7wQGPQB2AAARAAMJRBKYOABeAAAAAA==.Celîn:BAAALgAECgQJBAABLgAECgkJGgAPALsbAA==.Ceronia:BAAALgADCgEJAQAAAA==.',
Ch='Chainstormer:BAAALgAECgUJCQAAAA==.Cherry:BAAALgAECgQJBAAAAA==.Chibby:BAAALgAECgQJBAAAAA==.Chuladk:BAAALgAECgMJBAAAAA==.',
Cl='Cleymour:BAAALgADCgcJDgAAAA==.Cløudstrife:BAAALgAECgEJAQAAAA==.',
Co='Colbalt:BAABLgAECn8UAAIHAAcJdwfIIgDkAAAHAAcJdwfIIgDkAAAAAA==.Cor:BAAALgADCgYJBgAAAA==.Corrosive:BAAALgAECgYJBQAAAA==.Cotilion:BAAALgADCgMJAwAAAA==.',
Cr='Creation:BAAALgAECgUJCgABLgAECgcJFwAFAFIbAA==.Crunky:BAAALgAECgYJDwAAAA==.',
Cu='Cuddlymethod:BAAALgADCgUJBgAAAA==.',
['Có']='Cól:BAABLgAECn8nAAISAAkJLx5qMgCpAgASAAkJLx5qMgCpAgAAAA==.',
Da='Dahealzrhere:BAAALgAECgQJBAAAAA==.Dalel:BAAALgAECgYJEwAAAA==.Dameond:BAAALgAECgEJAQAAAA==.Dannyketch:BAAALgADCgEJAQAAAA==.',
De='Deadisdead:BAAALgAECgYJCwAAAA==.Deadlyglow:BAAALgADCgcJDAABLgAECgYJCAATAAAAAA==.Deathkratos:BAAALgADCgYJCQAAAA==.Demayy:BAAALgAECgcJDgAAAA==.Demiurgos:BAAALgAECgcJBwAAAA==.Demonicteli:BAABLgAECn8WAAIUAAkJlRmZEABdAgAUAAkJlRmZEABdAgAAAA==.Demonopii:BAAALgAECgQJCAAAAA==.Dermot:BAABLgAECn8mAAQVAAcJMiN1AwC6AgAVAAcJOyJ1AwC6AgAWAAQJIiDWdAB0AQAXAAEJCyYGIQBuAAAAAA==.',
Di='Dippindots:BAABLgAECn8dAAMEAAcJkhAhFQBZAQAEAAcJkhAhFQBZAQADAAEJZQF/7AAVAAAAAA==.Dixmen:BAAALgAECgQJBAAAAA==.',
Dk='Dkäri:BAAALgAECgYJDAAAAA==.',
Do='Dolemen:BAAALgAECgYJEwAAAA==.Domaon:BAABLgAECn8XAAIUAAcJ6B4CBQAiAgAUAAcJ6B4CBQAiAgAAAA==.Doombunny:BAAALgAECgUJCAABLgAECggJGwALANwSAA==.Doubt:BAAALgAECgYJBgAAAA==.',
Dr='Dranthrax:BAAALgAECgUJCAAAAA==.',
Du='Dunigan:BAABLgAECn8WAAIPAAgJAAo4NQBuAQAPAAgJAAo4NQBuAQAAAA==.Dunstan:BAAALgAECgYJCQAAAA==.Durmet:BAAALgAECgUJBQAAAA==.Dustos:BAAALgADCgIJAgAAAA==.',
Eb='Ebeast:BAABLgAECn8jAAIKAAgJRRB5CQDKAQAKAAgJRRB5CQDKAQAAAA==.Ebingus:BAAALgADCgYJBgAAAA==.',
Ei='Eifaun:BAEALgAECgUJCQAAAA==.',
El='Elexidor:BAAALgAECgcJBgAAAA==.Elorrna:BAAALgADCgYJBgAAAA==.',
Er='Erathen:BAAALgADCgUJBQAAAA==.',
Ey='Eyeet:BAAALgADCgkJEAAAAA==.',
Fa='Facade:BAAALgAECgQJBQAAAA==.Facepalm:BAAALgAECgYJCQAAAA==.Faked:BAAALgADCgEJAQABLgAECgYJDAATAAAAAA==.Falion:BAAALgAECgYJBgAAAA==.Fallensaints:BAAALgAECgYJCwAAAA==.Falshalad:BAABLgAECn8YAAIDAAcJIhPxVQBRAQADAAcJIhPxVQBRAQAAAA==.Falyy:BAAALgADCgQJBAAAAA==.',
Fe='Fentak:BAAALgAECgYJEAAAAA==.',
Fi='Fierytotes:BAAALgADCgYJEgAAAA==.Finka:BAAALgAECgMJAwAAAA==.',
Fl='Flamedaddy:BAAALgAECgYJDgAAAA==.',
Fo='Fog:BAAALgAECgEJAgAAAA==.Forgotmymeds:BAABLgAECn8cAAIIAAYJ5xhCGQCZAQAIAAYJ5xhCGQCZAQAAAA==.Foxmccloud:BAAALgAECgYJDwAAAA==.',
Fr='Fruitloop:BAAALgAECgYJDQAAAA==.',
Fy='Fyznen:BAAALgAECgQJBAAAAA==.',
Ga='Garim:BAAALgADCgcJBwAAAA==.Gaviriard:BAAALgADCgMJAwAAAA==.',
Ge='Gebran:BAAALgAECgEJAQAAAA==.Gellywoo:BAAALgAECgYJEQAAAA==.',
Gh='Ghostofonyx:BAAALgADCgcJFQAAAA==.',
Gi='Girlypop:BAAALgAECgQJBgAAAA==.',
Go='Golaoth:BAAALgAECgYJEAAAAA==.Gooftoo:BAAALgAECgcJEwAAAA==.',
Gr='Greycie:BAAALgADCgkJEwAAAA==.Greyfax:BAAALgADCgcJDQAAAA==.Greymoon:BAAALgAECgYJDwAAAA==.',
Gu='Guigondk:BAAALgAECgcJBgAAAA==.',
Gy='Gyre:BAAALgAECgQJBQAAAA==.',
Ha='Happyendings:BAAALgAECgUJBgAAAA==.',
He='Helbafx:BAAALgADCggJGAAAAA==.',
Hi='Hiroshì:BAAALgAECgEJAQAAAA==.',
Ho='Homewrecker:BAAALgAECgYJCwAAAA==.',
Hu='Hunnee:BAAALgADCgYJCwAAAA==.',
Ic='Icelace:BAAALgAECgEJAQAAAA==.',
If='Ifearnobeer:BAABLgAECn8cAAIYAAcJWgobIgAMAQAYAAcJWgobIgAMAQAAAA==.',
Ii='Iifelike:BAAALgAECgUJBgABLgAECgcJDgATAAAAAA==.',
In='Inters:BAAALgAECgUJBQAAAA==.',
Ir='Ironspark:BAAALgAECgQJBwAAAA==.',
Is='Isabel:BAABLgAFFH8HAAIDAAMJjgrTHAC4AAADAAMJjgrTHAC4AAAAAA==.Isaetr:BAAALgAECgEJAQAAAA==.',
Ja='Jackôdaniels:BAAALgADCgkJDgAAAA==.Jaiantobea:BAAALgAECgQJEQAAAA==.Jake:BAAALgADCgMJBAAAAA==.Jakulista:BAAALgADCgcJFQAAAA==.Jashugan:BAAALgADCgQJBAAAAA==.Jawn:BAABLgAECn8VAAIZAAcJVg56FwAtAQAZAAcJVg56FwAtAQAAAA==.',
Je='Jessuss:BAAALgAECgYJDAAAAA==.',
Ju='Jude:BAAALgAECgMJBwAAAA==.Juggernàut:BAAALgAECgYJDQAAAA==.',
Ka='Kajas:BAAALgAECgMJAwAAAA==.Kalahandra:BAABLgAECn8hAAIDAAkJFAsBRwCGAQADAAkJFAsBRwCGAQAAAA==.Kalebeesd:BAAALgAECgYJCgAAAA==.Karthdh:BAAALgADCgMJAwABLgADCggJCAATAAAAAA==.Kasey:BAAALgADCgEJAQAAAA==.Katithianna:BAAALgADCgQJAwAAAA==.Katotan:BAABLgAECn8XAAIDAAcJeBXdGgCpAQADAAcJeBXdGgCpAQAAAA==.Kawk:BAABLgAECn8nAAIRAAkJGB6MBAC7AgARAAkJGB6MBAC7AgAAAA==.Kazatreshan:BAAALgADCgcJDgAAAA==.Kazragor:BAABLgAECn8lAAIYAAgJ+SP4DgC3AgAYAAgJ+SP4DgC3AgAAAA==.',
Ke='Kebob:BAAALgAECgcJDgAAAA==.Kenziedadght:BAAALgAECgIJBQAAAA==.Keyboärd:BAABLgAECn8XAAIJAAcJyhmyBwDCAQAJAAcJyhmyBwDCAQAAAA==.',
Ki='Kilo:BAAALgADCgEJAgAAAA==.Kippo:BAECLgAFFH8HAAISAAQJhgUHMwDRAAASAAQJhgUHMwDRAAAuAAQKfyMAAhIACAmWF0dKAFgCABIACAmWF0dKAFgCAAAA.',
Kl='Klazarth:BAABLgAECn8dAAIHAAkJmR2JDQCqAgAHAAkJmR2JDQCqAgAAAA==.',
Ko='Kombat:BAAALgAECgMJBQAAAA==.Korllan:BAAALgAECgEJAQAAAA==.Kossnen:BAAALgAECgUJCwAAAA==.',
Kr='Krelivus:BAAALgAECgUJBgAAAA==.',
Ku='Kuda:BAAALgAECgUJEAAAAA==.',
Kw='Kwanu:BAAALgADCgYJCgAAAA==.',
['Kó']='Kóñä:BAAALgADCgkJDAABLgAECgUJCQATAAAAAA==.',
La='Lantern:BAAALgADCgUJBQAAAA==.Larke:BAAALgADCgEJAgAAAA==.Lasa:BAAALgAECgYJBwAAAA==.Lasloo:BAAALgAECgQJCgAAAA==.Laylani:BAAALgAECgMJBAAAAA==.Layllis:BAAALgADCgQJBgAAAA==.',
Le='Legiondary:BAABLgAECn8bAAIaAAgJOho6LgBEAgAaAAgJOho6LgBEAgAAAA==.Lesabor:BAAALgADCgYJBgAAAA==.',
Li='Licknstick:BAAALgAECgMJBgAAAA==.Lir:BAAALgADCgIJAgAAAA==.Lisan:BAAALgAECgcJDgAAAA==.Lisanalgaib:BAAALgAECgEJAgAAAA==.Littledicey:BAAALgADCgcJCwAAAA==.',
Lo='Lothan:BAAALgADCgkJCQABLgAECgYJFQAEAIYSAA==.',
Lu='Lucien:BAAALgAECgQJCAAAAA==.Luciä:BAAALgAECgYJEgAAAA==.Lucymoon:BAAALgAECgYJBQAAAA==.',
Ly='Lynex:BAAALgAECgQJBgAAAA==.',
Ma='Machoman:BAAALgADCgcJBwAAAA==.Magdeth:BAAALgADCgYJCwAAAA==.Magiann:BAAALgADCgEJAQAAAA==.Maiama:BAAALgAECgYJBwAAAA==.Marabelle:BAAALgAECgYJDAAAAA==.Massack:BAAALgAECgYJDQAAAA==.',
Me='Merex:BAAALgADCgEJAQAAAA==.Mero:BAAALgAECgYJBgAAAA==.Mew:BAAALgADCgEJAQABLgAECggJHwAQAJ0XAA==.',
Mi='Midgetmàniàc:BAAALgAECgMJBAAAAA==.Mikebeard:BAAALgADCgEJAQAAAA==.',
Mo='Moktar:BAAALgAECgYJBwAAAA==.Moobear:BAAALgADCgQJBAAAAA==.',
Mu='Muldoinit:BAAALgAECgYJDQAAAA==.',
My='Myroslava:BAAALgADCgkJEwAAAA==.',
Na='Nadorian:BAAALgAECgEJAQAAAA==.',
Ne='Neb:BAAALgAECgYJEgAAAA==.Nehemia:BAAALgAECgYJEAAAAA==.Nerilestis:BAAALgADCgQJBAAAAA==.Netherrogue:BAAALgAECgcJBwAAAA==.',
Ni='Nicage:BAAALgAECgQJBAABLgAFFAMJBQASABsYAA==.Nightdreams:BAAALgADCgcJCQAAAA==.',
Ny='Nytelytë:BAAALgAECgYJCQABLgAECgkJIwAWAAAdAA==.Nytemayer:BAABLgAECn8jAAQWAAkJAB3iMgBBAgAWAAcJUhziMgBBAgAVAAMJmB+MMwDpAAAXAAEJAAAxKQBNAAAAAA==.',
Ob='Obmakare:BAAALgAECgYJDwAAAA==.Oboñ:BAAALgAECgYJBgAAAA==.Obsfuyung:BAABLgAECn8VAAIZAAYJkhGuGgAPAQAZAAYJkhGuGgAPAQAAAA==.',
Or='Orcc:BAAALgADCgQJBAAAAA==.',
Pa='Paley:BAAALgAECgYJBgAAAA==.',
Pe='Peopleperson:BAAALgADCgQJAQAAAA==.',
Pi='Pinji:BAAALgAECgIJAgAAAA==.Pinkypoo:BAABLgAECn8UAAMBAAYJbBO/UwAGAQAbAAUJkRavIwAjAQABAAYJ7BC/UwAGAQAAAA==.',
Pl='Plato:BAAALgAECgcJDQAAAA==.',
Po='Poiet:BAAALgAECgEJAgAAAA==.Poîsonivy:BAAALgAECgYJEQAAAA==.',
Py='Pyrokos:BAABLgAECn8hAAISAAgJ6yAmJgDOAQASAAgJ6yAmJgDOAQAAAA==.Pyrö:BAAALgAECgkJCQAAAA==.',
Qu='Qu:BAABLgAECn8hAAMcAAkJaxxwBgBlAgAcAAkJaxxwBgBlAgAdAAIJTQoilQBrAAAAAA==.Quellia:BAACLgAFFH8KAAIQAAQJ6R0dCABsAQAQAAQJ6R0dCABsAQAuAAQKfxwAAhAACAmVINMMALMCABAACAmVINMMALMCAAAA.',
Ra='Rangel:BAABLgAECn8XAAIdAAcJwRKkGgBaAQAdAAcJwRKkGgBaAQAAAA==.Rattlesnake:BAAALgADCgYJBgAAAA==.',
Re='Redacted:BAAALgADCgMJAwAAAA==.Renägäde:BAAALgAECgYJDwAAAA==.Rexulti:BAAALgAECgEJAQAAAA==.',
Ri='Ricodadawg:BAAALgADCgEJAQAAAA==.Rizen:BAAALgADCgQJBAAAAA==.',
Ro='Roija:BAACLgAFFH8FAAISAAMJGxiALQATAQASAAMJGxiALQATAQAuAAQKfxwAAhIACAnXI7oGAMwCABIACAnXI7oGAMwCAAAA.',
Ru='Runningbearr:BAAALgADCgYJBgAAAA==.Runningmage:BAAALgADCgcJDAAAAA==.Rurahk:BAACLgAFFH8FAAIPAAIJ3RQxLACuAAAPAAIJ3RQxLACuAAAuAAQKfykAAg8ACAkEIaMVAOgCAA8ACAkEIaMVAOgCAAAA.',
['Rõ']='Rõbb:BAABLgAECn8jAAIPAAkJqh+bDgAZAwAPAAkJqh+bDgAZAwAAAA==.',
Sa='Sabaak:BAAALgAECgYJDwAAAA==.Sacerdote:BAAALgADCgUJBQAAAA==.Saeriin:BAAALgAECgUJBgAAAA==.Saithis:BAAALgAECgQJCwAAAA==.Sanorasong:BAEALgAECgYJDQAAAA==.Saphaa:BAAALgADCgEJAQAAAA==.Sarylin:BAAALgAECgYJDAAAAA==.Satanshealer:BAAALgADCgYJCQAAAA==.Satsuki:BAAALgAECgYJCgAAAA==.',
Sc='Schio:BAAALgAECgYJDwAAAA==.',
Se='Sean:BAAALgADCgYJBgAAAA==.Seananagíns:BAAALgADCgUJBQAAAA==.Sections:BAAALgADCgkJHAAAAA==.Severussnape:BAAALgAECgYJDQAAAA==.',
Sh='Shambs:BAABLgAECn8bAAIIAAkJzx4nBgAPAwAIAAkJzx4nBgAPAwABLgAFFAEJAQATAAAAAA==.Shamrorag:BAAALgAECgUJCgAAAA==.Shinron:BAAALgADCgYJDwAAAA==.Shökan:BAAALgADCggJDQAAAA==.',
Si='Sighah:BAAALgAECgcJCAAAAA==.Sinensis:BAAALgAECgcJDQAAAA==.Singood:BAAALgAECgcJBwAAAA==.Sinnecro:BAABLgAECn8aAAIBAAkJ4R5iIADAAgABAAkJ4R5iIADAAgAAAA==.Sinshift:BAAALgADCgUJBQAAAA==.',
Sk='Skadoosh:BAAALgADCgYJCQABLgAECgYJEwATAAAAAA==.Skarletflame:BAAALgAECgYJCgAAAA==.',
Sl='Slather:BAABLgAECn8aAAIMAAgJcBACGADVAQAMAAgJcBACGADVAQAAAA==.Slaycie:BAAALgAECgYJDwAAAA==.Slofinger:BAAALgADCgYJCgAAAA==.',
Sn='Sneeb:BAAALgAECgEJAQAAAA==.',
So='Songli:BAEALgADCgEJAQABLgAECgYJDQATAAAAAA==.Sorne:BAAALgAECgEJAQAAAA==.',
Sp='Spaghett:BAAALgAECgcJEwAAAA==.Springtotem:BAABLgAECn8VAAIEAAYJhhKNMwByAQAEAAYJhhKNMwByAQAAAA==.',
St='Stachel:BAAALgAECgIJAgAAAA==.Stanger:BAAALgADCgcJDQAAAA==.Storaxota:BAAALgAFFAUJAgAAAA==.Stormdk:BAAALgADCgcJCQAAAA==.',
Su='Sugondese:BAAALgAECgYJEQABLgAFFAMJCQAeAJ0WAA==.Superneo:BAAALgAECgYJBgABLgAFFAMJCQAEAJkiAA==.Suvion:BAAALgAECgcJEwAAAA==.',
Sy='Sylinial:BAAALgAECgEJAQAAAA==.Sylvanis:BAAALgAECgUJBwAAAA==.Syrden:BAAALgAECggJCAAAAA==.',
['Sÿ']='Sÿphallus:BAABLgAECn8RAAIUAAgJehPMCQCkAQAUAAgJehPMCQCkAQAAAA==.',
Ta='Tael:BAABLgAECn8aAAIdAAgJbx0ZFACUAQAdAAgJbx0ZFACUAQAAAA==.Tagreth:BAAALgADCgQJBAAAAA==.Tangylizard:BAABLgAECn8qAAMfAAgJ6xlQDQC0AQAfAAgJ6xlQDQC0AQAGAAEJBRanewA6AAAAAA==.Tattoospyder:BAABLgAECn8aAAIDAAcJTwinOgDoAAADAAcJTwinOgDoAAAAAA==.Tatyanafour:BAAALgADCgIJAQAAAA==.Tatyanathirt:BAAALgADCgYJBgAAAA==.',
Te='Tessla:BAABLgAECn8TAAIYAAYJRBnTGQBEAQAYAAYJRBnTGQBEAQABLgAECgcJEwATAAAAAA==.',
Th='Thafrggnpope:BAAALgADCgEJAQAAAA==.Thelarï:BAAALgAECgYJDQAAAA==.Thellany:BAAALgAECgEJAQAAAA==.Theshiznitz:BAAALgAECgMJAwAAAA==.Thors:BAAALgAECgcJEQAAAA==.Thundertoes:BAAALgAECgYJDQAAAA==.Thÿsucc:BAAALgADCgcJBwAAAA==.',
Ti='Tia:BAAALgADCgcJFAAAAA==.Timmy:BAAALgAECgEJAgABLgAECgYJDgATAAAAAA==.',
To='Tommychong:BAAALgAECgIJAgAAAA==.Tonik:BAAALgAECgQJBwAAAA==.Torgoth:BAAALgAECgYJEQAAAA==.Toshido:BAAALgAECgIJAgAAAA==.',
Tr='Traetor:BAAALgAECgYJDQAAAA==.Trakker:BAAALgADCgQJBAAAAA==.Trevize:BAAALgAECgQJBwAAAA==.',
Tt='Ttelloc:BAAALgADCgIJAgAAAA==.',
Tu='Tusiny:BAAALgAECgEJAQAAAA==.',
Ty='Tyraelara:BAAALgADCgEJAQAAAA==.',
Ub='Ubully:BAAALgADCgQJBAAAAA==.',
Ul='Ultane:BAAALgAECgIJBAAAAA==.',
Un='Unreal:BAAALgADCgQJBAAAAA==.',
Va='Vaera:BAAALgADCgEJAQAAAA==.Valastae:BAAALgAECgYJDQAAAA==.Valiantaine:BAABLgAECn8mAAMPAAkJbh9xKgB6AgAPAAgJ/B9xKgB6AgAQAAkJgQ2wPQCCAQAAAA==.Valiantaint:BAABLgAECn8iAAIaAAgJ9h5uLQBIAgAaAAgJ9h5uLQBIAgABLgAECgkJJgAPAG4fAA==.Valiantrain:BAAALgAECgEJAgABLgAECgkJJgAPAG4fAA==.Valyulon:BAAALgADCgMJAwABLgAECgkJJgAPAG4fAA==.Vanjin:BAAALgADCgUJBQAAAA==.',
Ve='Velherun:BAAALgAECgUJBwAAAA==.Vendeldh:BAABLgAECn8lAAIaAAkJUiOuCQA/AgAaAAkJUiOuCQA/AgAAAA==.Veni:BAAALgAECgYJBgAAAA==.Vexxaa:BAAALgAECgYJDwAAAA==.',
Vi='Virajr:BAAALgAECgUJBQAAAA==.Vishus:BAAALgADCgUJBQAAAA==.Visiôn:BAAALgAECggJEgAAAA==.Vissiction:BAAALgAECgYJCQAAAA==.Vistine:BAABLgAECn8XAAIRAAcJewt0FADIAAARAAcJewt0FADIAAAAAA==.Vitez:BAAALgAECgcJDgAAAA==.',
Vo='Voidscar:BAAALgADCgcJBwAAAA==.',
Wa='Warhurts:BAAALgAECgMJAwAAAA==.Waterbloom:BAAALgADCgMJAwAAAA==.',
We='Weave:BAAALgAECgYJDgAAAA==.Wendy:BAABLgAECn8iAAIIAAgJuRhQEADzAQAIAAgJuRhQEADzAQAAAA==.',
Wi='Winkster:BAABLgAECn8iAAIPAAkJVCS3CwAwAwAPAAkJVCS3CwAwAwAAAA==.',
Xa='Xanadu:BAABLgAECn8XAAIfAAcJYhobFgDyAQAfAAcJYhobFgDyAQAAAA==.Xarinia:BAABLgAECn8VAAMMAAYJDQuQMQDjAAAMAAUJ4weQMQDjAAANAAYJUg0jKQDIAAAAAA==.',
Xd='Xdynasty:BAACLgAFFH8JAAIeAAMJnRZEDgADAQAeAAMJnRZEDgADAQAuAAQKfyIAAx4ACAnMIyoMANUCAB4ACAnJIyoMANUCACAABgnDG+UNADwBAAAA.',
Xo='Xo:BAABLgAECn8kAAQVAAkJBhF+JQAxAQAVAAUJHRN+JQAxAQAWAAgJ4g2VRgAcAQAXAAEJAABDMAA9AAAAAA==.',
Xy='Xyfarion:BAAALgADCgYJBgAAAA==.Xyril:BAAALgAECgEJAQAAAA==.',
Ya='Yaasnah:BAAALgADCggJCAAAAA==.',
Za='Zabazz:BAABLgAECn8YAAIIAAcJQxKVIQBZAQAIAAcJQxKVIQBZAQAAAA==.Zabenir:BAAALgAECgUJDAAAAA==.Zané:BAAALgAECgEJAQAAAA==.Zapan:BAAALgADCgUJBQAAAA==.',
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
