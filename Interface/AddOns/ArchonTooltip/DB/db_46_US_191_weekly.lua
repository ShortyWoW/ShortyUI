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

local lookup = {'DeathKnight-Unholy','Druid-Feral','Druid-Balance','Priest-Holy','Priest-Shadow','Shaman-Restoration','Warrior-Protection','Hunter-Survival','Unknown-Unknown','Evoker-Preservation','Evoker-Augmentation','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Retribution','Paladin-Protection','Paladin-Holy','Mage-Frost','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Druid-Restoration','Shaman-Elemental','DemonHunter-Devourer','Warrior-Arms','Warrior-Fury','Rogue-Subtlety','Priest-Discipline','Rogue-Assassination',}
local provider = {region='US',realm='Shandris',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abyssara:BAAALgAECgQJBwAAAA==.',
Ac='Acebets:BAAALgAECgEJAQAAAA==.Acedk:BAABLgAECn8aAAIBAAkJTyGbCwA+AwABAAkJTyGbCwA+AwAAAA==.',
Ad='Adorie:BAAALgAECgIJAwAAAA==.Adun:BAAALgADCgMJAwAAAA==.',
Ae='Aelphe:BAABLgAECn8aAAMCAAkJGiHuAAB8AwACAAkJGiHuAAB8AwADAAEJLgIHjgAfAAAAAA==.Aelusius:BAAALgAECgcJEgAAAA==.Aeón:BAAALgAECgQJBAAAAA==.',
Ag='Aggen:BAAALgAECgUJCAAAAA==.',
Ak='Akashá:BAAALgADCgUJBQAAAA==.Akriksdk:BAAALgAECgcJBwAAAA==.',
Al='Al:BAABLgAECn8bAAMEAAgJsxE6KwCbAQAEAAcJaRE6KwCbAQAFAAgJkgkpDwADAQAAAA==.Alandarus:BAAALgADCgEJAQAAAA==.Alexanderath:BAAALgAECgQJBwAAAA==.Alexânderson:BAAALgAECgQJCAAAAA==.Alkaline:BAAALgADCggJCAAAAA==.Alkatractite:BAAALgAECgQJBwAAAA==.Alzul:BAAALgADCgUJBQAAAA==.',
Am='Amanita:BAAALgADCgkJIAABLgAECgYJGQAGAP8cAA==.Amasham:BAAALgAECgYJBgAAAA==.Amberness:BAAALgAFFAEJAQAAAA==.Ambersoul:BAAALgADCgMJAwAAAA==.',
An='Anyi:BAAALgAECgMJBgAAAA==.',
Ao='Aoi:BAAALgAECgUJCQAAAA==.',
Ar='Arrisia:BAAALgAECgUJCAAAAA==.Artemissy:BAAALgADCgQJBAAAAA==.Arthedain:BAACLgAFFH8FAAIHAAIJcRseCgCrAAAHAAIJcRseCgCrAAAuAAQKfyMAAgcACQmDIX4BAHIDAAcACQmDIX4BAHIDAAAA.Arthedaine:BAACLgAFFH8GAAIIAAMJsRRaAgARAQAIAAMJsRRaAgARAQAuAAQKfx8AAggACAkAIpkCABMDAAgACAkAIpkCABMDAAEuAAUUAgkFAAcAcRsA.',
As='Asiea:BAAALgADCgMJAwAAAA==.',
Au='Augmentmyass:BAAALgAFFAEJAQAAAA==.Aushahin:BAAALgAECgYJBgABLgAECgYJDwAJAAAAAA==.Autumni:BAAALgAECgcJEAAAAA==.Auvry:BAABLgAECn8ZAAMKAAcJVRkXEAA5AgAKAAcJVRkXEAA5AgALAAIJnwkaIgAvAAAAAA==.',
Ay='Aymus:BAAALgAECgYJCgAAAA==.',
Ba='Bahamutfang:BAAALgAECgQJCwAAAA==.Bakala:BAAALgAECgUJCgAAAA==.Bangbang:BAABLgAECn8cAAIMAAgJyBT5CgC7AQAMAAgJyBT5CgC7AQAAAA==.',
Be='Belegaer:BAAALgAECgUJBwAAAA==.Bellamy:BAAALgAECgEJAQAAAA==.Beltway:BAAALgADCgcJCgAAAA==.Bendini:BAABLgAECn8YAAINAAgJshP5KgDSAQANAAgJshP5KgDSAQAAAA==.Benmaverick:BAAALgAECgYJCgAAAA==.',
Bh='Bhe:BAAALgAECgQJCwAAAA==.',
Bi='Billymayzz:BAAALgADCgIJAgAAAA==.Bishop:BAAALgAECgUJCwAAAA==.',
Bo='Bobe:BAAALgAECgYJEwAAAA==.Bordok:BAAALgAECgQJCwAAAA==.',
Br='Brunco:BAAALgAECgYJDwAAAA==.Brxndxn:BAAALgADCgUJBQAAAA==.Brëw:BAAALgADCgUJBQAAAA==.Brütäl:BAAALgADCgIJAgAAAA==.',
Bu='Bubbleyo:BAAALgADCgcJCAAAAA==.Bustaheals:BAAALgAECgUJBwAAAA==.',
Bw='Bwasamdi:BAAALgAFFAEJAQAAAA==.',
Ca='Calypsa:BAAALgADCgMJBAAAAA==.Captplanet:BAAALgAECgYJBgAAAA==.Cashartea:BAAALgAECgUJBQAAAA==.Cattleclysm:BAAALgADCgMJAwAAAA==.',
Ce='Ceindra:BAAALgAECgcJDAAAAA==.Celiñ:BAABLgAECn8VAAQOAAkJnBixOABAAgAOAAgJhhmxOABAAgAPAAMJRBKZOABeAAAQAAEJegi2jwBBAAAAAA==.Celîn:BAAALgAECgQJBAABLgAECgkJFQAOAJwYAA==.',
Ch='Chainstormer:BAAALgAECgUJCQAAAA==.Cherry:BAAALgAECgQJBAAAAA==.Chibby:BAAALgAECgQJBAAAAA==.Chuladk:BAAALgAECgMJBAAAAA==.',
Cl='Cleymour:BAAALgADCgcJDgAAAA==.Cløudstrife:BAAALgAECgEJAQAAAA==.',
Co='Colbalt:BAAALgAECgYJDQAAAA==.Corrosive:BAAALgAECgYJBQAAAA==.Cotilion:BAAALgADCgMJAwAAAA==.',
Cr='Creation:BAAALgAECgEJAgABLgAECgcJEgAJAAAAAA==.Crunky:BAAALgAECgUJCQAAAA==.',
Cu='Cuddlymethod:BAAALgADCgUJBgAAAA==.',
['Có']='Cól:BAABLgAECn8gAAIRAAgJPxxrMgCpAgARAAgJPxxrMgCpAgAAAA==.',
Da='Dahealzrhere:BAAALgAECgQJBAAAAA==.Dalel:BAAALgAECgQJDQAAAA==.Dameond:BAAALgADCggJCwAAAA==.Dannyketch:BAAALgADCgEJAQAAAA==.',
De='Deadisdead:BAAALgAECgMJBQAAAA==.Deadlyglow:BAAALgADCgcJDAABLgAECgUJBwAJAAAAAA==.Deathkratos:BAAALgADCgYJCQAAAA==.Demayy:BAAALgAECgcJBwAAAA==.Demonicteli:BAAALgAFFAEJAgAAAA==.Demonopii:BAAALgAECgQJCAAAAA==.Dermot:BAABLgAECn8hAAQSAAcJ+SJ3AwC6AgASAAcJAiJ3AwC6AgATAAQJIiDLdAB0AQAUAAEJCyYFIQBuAAAAAA==.',
Di='Dippindots:BAAALgAECgYJEwAAAA==.Dixmen:BAAALgADCgYJBAAAAA==.',
Dk='Dkäri:BAAALgAECgYJDAAAAA==.',
Do='Dolemen:BAAALgAECgUJCwAAAA==.Domaon:BAAALgAECgYJDwAAAA==.Doombunny:BAAALgAECgMJAwABLgAECgYJEwAJAAAAAA==.',
Dr='Dranthrax:BAAALgAECgIJAwAAAA==.',
Du='Dunigan:BAAALgAECgYJDgAAAA==.Dunstan:BAAALgAECgMJAwAAAA==.Durmet:BAAALgAECgUJBQAAAA==.Dustos:BAAALgADCgIJAgAAAA==.',
Eb='Ebeast:BAABLgAECn8WAAIIAAgJZw+LDQDwAQAIAAgJZw+LDQDwAQAAAA==.Ebingus:BAAALgADCgYJBgAAAA==.',
Ei='Eifaun:BAEALgAECgMJBAAAAA==.',
El='Elexidor:BAAALgAECgcJBgAAAA==.Elorrna:BAAALgADCgYJBgAAAA==.',
Er='Erathen:BAAALgADCgUJBQAAAA==.',
Ey='Eyeet:BAAALgADCgkJEAAAAA==.',
Fa='Facade:BAAALgAECgQJBQAAAA==.Facepalm:BAAALgAECgMJAwAAAA==.Faked:BAAALgADCgEJAQABLgAECgYJDAAJAAAAAA==.Falion:BAAALgAECgYJBgAAAA==.Fallensaints:BAAALgAECgYJCwAAAA==.Falshalad:BAAALgAECgYJEgAAAA==.Falyy:BAAALgADCgQJBAAAAA==.',
Fe='Fentak:BAAALgAECgYJCgAAAA==.',
Fi='Fierytotes:BAAALgADCgYJEgAAAA==.Finka:BAAALgAECgMJAwAAAA==.',
Fl='Flamedaddy:BAAALgAECgQJCAAAAA==.',
Fo='Fog:BAAALgAECgEJAgAAAA==.Forgotmymeds:BAAALgAECgYJDAAAAA==.Foxmccloud:BAAALgAECgUJCQAAAA==.',
Fr='Fruitloop:BAAALgAECgUJBwAAAA==.',
Fy='Fyznen:BAAALgAECgQJBAAAAA==.',
Ga='Garim:BAAALgADCgcJBwAAAA==.Gaviriard:BAAALgADCgMJAwAAAA==.',
Ge='Gebran:BAAALgADCggJFgAAAA==.Gellywoo:BAAALgAECgUJCgAAAA==.',
Gh='Ghostofonyx:BAAALgADCgcJFQAAAA==.',
Gi='Girlypop:BAAALgAECgQJBQAAAA==.',
Go='Golaoth:BAAALgAECgQJCgAAAA==.Gooftoo:BAAALgAECgcJEQAAAA==.',
Gr='Greycie:BAAALgADCgkJEwAAAA==.Greyfax:BAAALgADCgcJDQAAAA==.Greymoon:BAAALgAECgUJCQAAAA==.',
Gu='Guigondk:BAAALgAECgcJBgAAAA==.',
Gy='Gyre:BAAALgAECgQJBQAAAA==.',
Ha='Happyendings:BAAALgAECgUJBgAAAA==.',
He='Helbafx:BAAALgADCggJEgAAAA==.',
Hi='Hiroshì:BAAALgAECgEJAQAAAA==.',
Ho='Homewrecker:BAAALgAECgUJBwAAAA==.',
Hu='Hunnee:BAAALgADCgYJCwAAAA==.',
Ic='Icelace:BAAALgADCgYJBgAAAA==.',
If='Ifearnobeer:BAAALgAECgYJEwAAAA==.',
Ii='Iifelike:BAAALgAECgQJBAABLgAECgcJDgAJAAAAAA==.',
In='Inters:BAAALgADCgUJCgAAAA==.',
Ir='Ironspark:BAAALgAECgQJBwAAAA==.',
Is='Isabel:BAAALgAFFAMJBAAAAA==.Isaetr:BAAALgAECgEJAQAAAA==.',
Ja='Jackôdaniels:BAAALgADCgkJDgAAAA==.Jaiantobea:BAAALgAECgQJEQAAAA==.Jake:BAAALgADCgMJAwAAAA==.Jakulista:BAAALgADCgcJFAAAAA==.Jashugan:BAAALgADCgQJBAAAAA==.Jawn:BAAALgAECgYJDQAAAA==.Jayvlyn:BAAALgADCggJFgAAAA==.',
Je='Jessuss:BAAALgAECgQJBgAAAA==.',
Ju='Jude:BAAALgAECgIJAgAAAA==.Juggernàut:BAAALgAECgQJBwAAAA==.',
Ka='Kajas:BAAALgAECgMJAwAAAA==.Kalahandra:BAABLgAECn8cAAIVAAkJaAn5RgCGAQAVAAkJaAn5RgCGAQAAAA==.Kalebeesd:BAAALgAECgYJBwAAAA==.Katithianna:BAAALgADCgQJAwAAAA==.Katotan:BAAALgAECgYJDwAAAA==.Kawk:BAABLgAECn8gAAIPAAgJJh2LBAC7AgAPAAgJJh2LBAC7AgAAAA==.Kazatreshan:BAAALgADCgcJDgAAAA==.Kazragor:BAABLgAECn8fAAIWAAgJFiP1DgC3AgAWAAgJFiP1DgC3AgAAAA==.',
Ke='Kebob:BAAALgAECgcJDgAAAA==.Kenziedadght:BAAALgAECgIJBQAAAA==.Keyboärd:BAAALgAECgYJEQAAAA==.',
Ki='Kilo:BAAALgADCgEJAgAAAA==.Kippo:BAEBLgAECn8jAAIRAAgJlhdISgBYAgARAAgJlhdISgBYAgAAAA==.',
Kl='Klazarth:BAABLgAECn8YAAIFAAkJthuJDQCqAgAFAAkJthuJDQCqAgAAAA==.',
Ko='Kombat:BAAALgAECgIJAgAAAA==.Kossnen:BAAALgAECgQJBgAAAA==.',
Kr='Krelivus:BAAALgAECgIJAgAAAA==.',
Ku='Kuda:BAAALgAECgQJCwAAAA==.',
Kw='Kwanu:BAAALgADCgIJBAAAAA==.',
['Kó']='Kóñä:BAAALgADCgkJDAABLgAECgQJBAAJAAAAAA==.',
La='Larke:BAAALgADCgEJAgAAAA==.Lasa:BAAALgAECgYJBwAAAA==.Lasloo:BAAALgAECgMJBAAAAA==.Laylani:BAAALgAECgMJAwAAAA==.',
Le='Legiondary:BAABLgAECn8bAAIXAAgJOho3LgBEAgAXAAgJOho3LgBEAgAAAA==.Lesabor:BAAALgADCgYJBgAAAA==.',
Li='Licknstick:BAAALgAECgMJAwAAAA==.Lir:BAAALgADCgIJAgAAAA==.Lisan:BAAALgAECgcJDgAAAA==.Lisanalgaib:BAAALgAECgEJAQAAAA==.Littledicey:BAAALgADCgcJCwAAAA==.',
Lo='Lothan:BAAALgADCgkJCQABLgAECgYJDwAJAAAAAA==.',
Lu='Lucien:BAAALgAECgQJBwAAAA==.Luciä:BAAALgAECgQJDAAAAA==.Lucymoon:BAAALgAECgYJBQAAAA==.',
Ly='Lynex:BAAALgADCgEJAQAAAA==.',
Ma='Machoman:BAAALgADCgcJBwAAAA==.Magdeth:BAAALgADCgYJCgAAAA==.Maiama:BAAALgAECgYJBwAAAA==.Marabelle:BAAALgAECgUJBgAAAA==.Massack:BAAALgAECgUJBwAAAA==.',
Me='Merex:BAAALgADCgEJAQAAAA==.Mero:BAAALgAECgYJBgAAAA==.Mew:BAAALgADCgEJAQABLgAECggJHwAQAJ0XAA==.',
Mi='Midgetmàniàc:BAAALgAECgMJBAAAAA==.Mikebeard:BAAALgADCgEJAQAAAA==.',
Mo='Moktar:BAAALgAECgYJBwAAAA==.',
Mu='Muldoinit:BAAALgAECgUJBwAAAA==.',
My='Myroslava:BAAALgADCgkJEwAAAA==.',
Na='Nadorian:BAAALgAECgEJAQAAAA==.',
Ne='Neb:BAAALgAECgYJEQAAAA==.Nehemia:BAAALgAECgYJCgAAAA==.Nerilestis:BAAALgADCgQJBAAAAA==.',
Ni='Nightdreams:BAAALgADCgcJCQAAAA==.',
Ny='Nytelytë:BAAALgAECgYJCQABLgAECgkJHgATAF8cAA==.Nytemayer:BAABLgAECn8eAAQTAAkJXxzkMgBBAgATAAcJmhvkMgBBAgASAAMJmB+NMwDpAAAUAAEJAAAsKQBNAAAAAA==.',
Ob='Obmakare:BAAALgAECgUJCQAAAA==.Obsfuyung:BAAALgAECgYJDwAAAA==.',
Pa='Paley:BAAALgAECgYJBgAAAA==.',
Pe='Peopleperson:BAAALgADCgQJAQAAAA==.',
Pi='Pinji:BAAALgAECgIJAgAAAA==.Pinkypoo:BAAALgAECgYJDwAAAA==.',
Pl='Plato:BAAALgAECgEJAQAAAA==.',
Po='Poiet:BAAALgAECgEJAgAAAA==.Poîsonivy:BAAALgAECgQJCwAAAA==.',
Py='Pyrokos:BAABLgAECn8bAAIRAAgJyhzzGgBzAQARAAgJyhzzGgBzAQAAAA==.',
Qu='Qu:BAABLgAECn8aAAMYAAgJQBpvBgBlAgAYAAgJQBpvBgBlAgAZAAIJTQoQlQBrAAAAAA==.Quellia:BAACLgAFFH8GAAIQAAMJ1xsLBgD3AAAQAAMJ1xsLBgD3AAAuAAQKfxwAAhAACAmVINUMALMCABAACAmVINUMALMCAAAA.',
Ra='Rangel:BAAALgAECgYJDgAAAA==.Rattlesnake:BAAALgADCgYJBgAAAA==.',
Re='Redacted:BAAALgADCgMJAwAAAA==.Renägäde:BAAALgAECgYJDQAAAA==.',
Ri='Ricodadawg:BAAALgADCgEJAQAAAA==.Rizen:BAAALgADCgQJBAAAAA==.',
Ro='Roija:BAABLgAECn8VAAIRAAgJzCOxFwAcAwARAAgJzCOxFwAcAwAAAA==.',
Ru='Runningmage:BAAALgADCgcJDAAAAA==.Rurahk:BAABLgAECn8lAAIOAAgJmCCeFQDoAgAOAAgJmCCeFQDoAgAAAA==.',
['Rõ']='Rõbb:BAABLgAECn8eAAIOAAkJ8R6YDgAZAwAOAAkJ8R6YDgAZAwAAAA==.',
Sa='Sabaak:BAAALgAECgUJCQAAAA==.Sacerdote:BAAALgADCgUJBQAAAA==.Saeriin:BAAALgAECgUJBgAAAA==.Saithis:BAAALgAECgQJCgAAAA==.Sanorasong:BAEALgAECgQJBwAAAA==.Saphaa:BAAALgADCgEJAQAAAA==.Sarylin:BAAALgAECgUJBwAAAA==.Satanshealer:BAAALgADCgYJCQAAAA==.Satsuki:BAAALgAECgYJCgAAAA==.',
Sc='Schio:BAAALgAECgUJCQAAAA==.',
Se='Sean:BAAALgADCgYJBgAAAA==.Seananagíns:BAAALgADCgUJBQAAAA==.Sections:BAAALgADCgkJHAAAAA==.Severussnape:BAAALgAECgUJBwAAAA==.',
Sh='Shambs:BAABLgAECn8bAAIGAAkJzx4pBgAPAwAGAAkJzx4pBgAPAwABLgAFFAEJAQAJAAAAAA==.Shamrorag:BAAALgAECgMJBgAAAA==.Shinron:BAAALgADCgYJDwAAAA==.Shökan:BAAALgADCgQJBQAAAA==.',
Si='Sighah:BAAALgAECgcJCAAAAA==.Sinensis:BAAALgAECgcJDQAAAA==.Singood:BAAALgAECgcJBwAAAA==.Sinnecro:BAABLgAECn8VAAIBAAkJfh1eIADAAgABAAkJfh1eIADAAgAAAA==.Sinshift:BAAALgADCgUJBQAAAA==.',
Sk='Skadoosh:BAAALgADCgYJCQABLgAECgQJDQAJAAAAAA==.Skarletflame:BAAALgAECgQJBAAAAA==.',
Sl='Slather:BAABLgAECn8aAAIKAAgJcBABGADVAQAKAAgJcBABGADVAQAAAA==.Slaycie:BAAALgAECgUJCQAAAA==.',
Sn='Sneeb:BAAALgAECgEJAQAAAA==.',
So='Songli:BAEALgADCgEJAQABLgAECgQJBwAJAAAAAA==.Sorne:BAAALgAECgEJAQAAAA==.',
Sp='Spaghett:BAAALgAECgcJEwAAAA==.Springtotem:BAAALgAECgYJDwAAAA==.',
St='Stachel:BAAALgAECgIJAgAAAA==.Stanger:BAAALgADCgUJBQAAAA==.Storaxota:BAAALgAFFAQJAgAAAA==.Stormdk:BAAALgADCgcJCQAAAA==.',
Su='Sugondese:BAAALgAECgQJCwABLgAFFAIJBgAaAIIVAA==.Superneo:BAAALgAECgYJBgABLgAFFAMJCQADAJkiAA==.Suvion:BAAALgAECgcJEgAAAA==.',
Sy='Sylvanis:BAAALgAECgUJBwAAAA==.Syrden:BAAALgAECgYJBgAAAA==.',
['Sÿ']='Sÿphallus:BAAALgAECggJCgAAAA==.',
Ta='Tael:BAABLgAECn8WAAIZAAcJKh71KwAFAgAZAAcJKh71KwAFAgAAAA==.Tagreth:BAAALgADCgQJBAAAAA==.Tangylizard:BAABLgAECn8kAAMbAAgJ6xnGBQCqAQAbAAgJ6xnGBQCqAQAEAAEJBRadewA6AAAAAA==.Tattoospyder:BAABLgAECn8ZAAIVAAcJTwgmGwDeAAAVAAcJTwgmGwDeAAAAAA==.Tatyanafour:BAAALgADCgIJAQAAAA==.Tatyanathirt:BAAALgADCgYJBgAAAA==.',
Te='Tessla:BAAALgAECgQJCgABLgAECgcJEgAJAAAAAA==.',
Th='Thafrggnpope:BAAALgADCgEJAQAAAA==.Thelarï:BAAALgAECgUJBwAAAA==.Thellany:BAAALgAECgEJAQAAAA==.Theshiznitz:BAAALgAECgMJAwAAAA==.Thors:BAAALgAECgcJDAAAAA==.Thundertoes:BAAALgAECgUJBwAAAA==.Thÿsucc:BAAALgADCgcJBwAAAA==.',
Ti='Tia:BAAALgADCgcJEwAAAA==.Timmy:BAAALgAECgEJAQABLgAECgYJDgAJAAAAAA==.',
To='Tommychong:BAAALgAECgIJAgAAAA==.Tonik:BAAALgAECgIJAgAAAA==.Torgoth:BAAALgAECgQJCwAAAA==.Toshido:BAAALgAECgEJAQAAAA==.',
Tr='Traetor:BAAALgAECgUJBwAAAA==.Trakker:BAAALgADCgQJBAAAAA==.Trevize:BAAALgAECgMJAwAAAA==.',
Tt='Ttelloc:BAAALgADCgIJAgAAAA==.',
Tu='Tusiny:BAAALgAECgEJAQAAAA==.',
Ty='Tyraelara:BAAALgADCgEJAQAAAA==.',
Ub='Ubully:BAAALgADCgQJBAAAAA==.',
Ul='Ultane:BAAALgAECgEJAQAAAA==.',
Un='Unreal:BAAALgADCgQJBAAAAA==.',
Va='Valastae:BAAALgAECgQJBwAAAA==.Valiantaine:BAABLgAECn8fAAMOAAgJiR13KgB6AgAOAAgJiR13KgB6AgAQAAcJww61PQCCAQAAAA==.Valiantaint:BAABLgAECn8cAAIXAAcJ8h1nLQBIAgAXAAcJ8h1nLQBIAgABLgAECggJHwAOAIkdAA==.Valiantrain:BAAALgAECgEJAQABLgAECggJHwAOAIkdAA==.Valyulon:BAAALgADCgMJAwABLgAECggJHwAOAIkdAA==.Vanjin:BAAALgADCgUJBQAAAA==.',
Ve='Velherun:BAAALgAECgUJBwAAAA==.Vendeldh:BAABLgAECn8eAAIXAAgJACPREgDpAgAXAAgJACPREgDpAgAAAA==.Veni:BAAALgAECgYJBgAAAA==.Vexxaa:BAAALgAECgQJCQAAAA==.',
Vi='Virajr:BAAALgAECgUJBQAAAA==.Vishus:BAAALgADCgUJBQAAAA==.Visiôn:BAAALgAECggJEgAAAA==.Vissiction:BAAALgAECgMJAwAAAA==.Vistine:BAAALgAECgcJDgAAAA==.Vitez:BAAALgAECgcJDgAAAA==.',
Wa='Warhurts:BAAALgADCgcJCAAAAA==.Waterbloom:BAAALgADCgMJAwAAAA==.',
We='Weave:BAAALgAECgQJCAAAAA==.Wendy:BAABLgAECn8ZAAIGAAYJ/xyzKwDeAQAGAAYJ/xyzKwDeAQAAAA==.',
Wi='Winkster:BAABLgAECn8bAAIOAAgJHyWzCwAwAwAOAAgJHyWzCwAwAwAAAA==.',
Xa='Xanadu:BAAALgAECgcJEgAAAA==.Xarinia:BAAALgAECgYJEAAAAA==.',
Xd='Xdynasty:BAACLgAFFH8GAAIaAAIJghXtEQC6AAAaAAIJghXtEQC6AAAuAAQKfx4AAxoACAlwISkMANUCABoACAltISkMANUCABwABgnDG+MNADwBAAAA.',
Xo='Xo:BAABLgAECn8dAAQSAAgJhxF7JQAxAQATAAYJ6g53ggBVAQASAAUJqRF7JQAxAQAUAAEJAABBMAA9AAAAAA==.',
Xy='Xyfarion:BAAALgADCgYJBgAAAA==.Xyril:BAAALgAECgEJAQAAAA==.',
Ya='Yaasnah:BAAALgADCggJCAAAAA==.',
Za='Zabazz:BAAALgAECgYJEgAAAA==.Zabenir:BAAALgAECgQJCwAAAA==.Zapan:BAAALgADCgUJBQAAAA==.',
Ze='Zeverai:BAAALgADCgYJBgAAAA==.',
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
