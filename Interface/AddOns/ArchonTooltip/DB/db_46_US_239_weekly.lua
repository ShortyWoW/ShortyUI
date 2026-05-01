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

local lookup = {'Paladin-Retribution','Paladin-Protection','Hunter-Survival','Warrior-Protection','DemonHunter-Devourer','Hunter-Marksmanship','Hunter-BeastMastery','Shaman-Restoration','Shaman-Elemental','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','DeathKnight-Unholy','DemonHunter-Havoc','Druid-Feral','Monk-Brewmaster','Warrior-Arms','Monk-Mistweaver','Druid-Restoration','Druid-Guardian','Druid-Balance','Unknown-Unknown','DeathKnight-Blood','Paladin-Holy','Warlock-Demonology','Priest-Holy','Warrior-Fury','Priest-Discipline','DeathKnight-Frost','Mage-Frost','Mage-Arcane','Warlock-Destruction','Rogue-Subtlety','Warlock-Affliction','Monk-Windwalker','DemonHunter-Vengeance','Priest-Shadow','Shaman-Enhancement','Rogue-Outlaw','Mage-Fire',}
local provider = {region='US',realm='Windrunner',name='US',type='weekly',zone=46,date='2026-05-01',data={Ac='Acari:BAAALgADCgYJBgAAAA==.Actionjaxson:BAABLgAECn8hAAIBAAgJ4CKLBQDBAgABAAgJ4CKLBQDBAgAAAA==.',
Ad='Adiais:BAAALgAECgEJBAAAAA==.Admiration:BAAALgADCgkJCQAAAA==.Admore:BAAALgAECgUJEAAAAA==.',
Ae='Aeriith:BAAALgAECgMJAwAAAA==.Aethmourne:BAAALgADCgEJAQAAAA==.',
Ag='Agameden:BAABLgAECn8UAAICAAYJah9rEAC/AQACAAYJah9rEAC/AQAAAA==.Agogg:BAAALgAECgMJBQAAAA==.Agronak:BAAALgADCgEJAQAAAA==.',
Ai='Aishi:BAAALgAECgcJEAAAAA==.',
Ak='Akadiak:BAABLgAECn8fAAIDAAkJlhUsCgA4AgADAAkJlhUsCgA4AgAAAA==.Akitsuki:BAAALgAECgEJAgAAAA==.',
Al='Albertenzyme:BAAALgAECgEJAQAAAA==.Alivron:BAAALgAECggJDwAAAA==.Alko:BAAALgAECgEJAQABLgAECgcJGQAEAEojAA==.Alkoren:BAAALgAECgMJBgABLgAECgcJGQAEAEojAA==.Alkorin:BAABLgAECn8ZAAIEAAcJSiOOBQACAgAEAAcJSiOOBQACAgAAAA==.Allestra:BAABLgAECn8fAAIFAAgJSx1oCABTAgAFAAgJSx1oCABTAgAAAA==.',
Am='Amanojaku:BAAALgADCgQJBAAAAA==.Amarilis:BAAALgAECgYJCgAAAA==.Amarÿah:BAAALgADCgMJAgAAAA==.Amethcrow:BAACLgAFFH8GAAIGAAIJiBF2DQCdAAAGAAIJiBF2DQCdAAAuAAQKfxgAAgYACAnQHcQUAIoCAAYACAnQHcQUAIoCAAAA.Amoxil:BAAALgAECgYJEAAAAA==.',
An='Anasztaizia:BAAALgAECgYJCwAAAA==.Andarrathan:BAAALgADCgQJBAAAAA==.Andurael:BAAALgAECgcJCAAAAA==.Andwin:BAAALgADCgkJCQAAAA==.Angarock:BAAALgAECgcJEQAAAA==.Angelclaw:BAABLgAECn8ZAAIHAAgJDgprKAB1AQAHAAgJDgprKAB1AQAAAA==.Angora:BAAALgAECgUJCgAAAA==.Animussadow:BAAALgADCgEJAQAAAA==.Anorah:BAAALgAECgYJDwAAAA==.Anunitu:BAABLgAECn8bAAMIAAcJiBIaIgBWAQAIAAcJiBIaIgBWAQAJAAIJ8AklfABUAAAAAA==.',
Ao='Aoibheann:BAAALgAECgYJEAAAAA==.',
Aq='Aqualeta:BAAALgADCgEJAgAAAA==.',
Ar='Arath:BAABLgAECn8cAAQKAAgJWRE+BgA6AQAKAAcJmA8+BgA6AQALAAYJFg46OQAPAQAMAAMJcQTnPQB8AAAAAA==.Arazuren:BAAALgADCgEJAQABLgAFFAMJBQANAPoXAA==.Archegonia:BAAALgADCgcJDAAAAA==.Arcona:BAAALgAECgYJDwAAAA==.Arslette:BAAALgADCgkJEAAAAA==.Artemîs:BAAALgADCgUJBgAAAA==.Arthuel:BAAALgADCgIJAgAAAA==.Arthus:BAAALgAECgYJEwAAAA==.Arynkyr:BAAALgADCgIJAgAAAA==.',
As='Asar:BAAALgAECgMJCgAAAA==.Ashora:BAAALgADCgYJCQAAAA==.Aspun:BAAALgADCgEJAQAAAA==.Astora:BAABLgAECn8XAAMFAAcJEiJ4CQBCAgAFAAcJEiJ4CQBCAgAOAAEJAABYagA9AAAAAA==.Astralis:BAAALgADCgMJAwAAAA==.',
At='Atherasil:BAAALgADCgYJDQAAAA==.Athuzad:BAAALgAECgYJCgAAAA==.',
Au='Audie:BAAALgAECgEJAQAAAA==.Auquroe:BAAALgADCggJDgAAAA==.Aurelìa:BAAALgADCgMJAwAAAA==.Auroraalysia:BAABLgAECn8VAAIHAAYJ8BwKIAChAQAHAAYJ8BwKIAChAQAAAA==.Auroran:BAAALgAECgMJCQAAAA==.Autumnmoon:BAABLgAECn8hAAIPAAgJAg30BwB2AQAPAAgJAg30BwB2AQAAAA==.',
Av='Avaarion:BAAALgADCgEJAQAAAA==.Avalotus:BAAALgAECgYJCAAAAA==.Avrilenv:BAAALgAECgIJAwAAAA==.Avä:BAAALgADCgEJAQAAAA==.',
Ay='Ayeroh:BAABLgAECn8WAAIQAAYJrRqLEQCBAQAQAAYJrRqLEQCBAQAAAA==.Ayhika:BAACLgAFFH8MAAIIAAQJaSISBwB0AQAIAAQJaSISBwB0AQAuAAQKfxYAAggACAkgIfQKAM4CAAgACAkgIfQKAM4CAAAA.',
Az='Azehyrus:BAACLgAFFH8HAAIBAAMJ7SDpEAAeAQABAAMJ7SDpEAAeAQAuAAQKfx4AAgEACAkcJqYGAGUDAAEACAkcJqYGAGUDAAEuAAUUBQkRABEAOCIA.Azhenhydra:BAAALgADCggJCAAAAA==.Azkabras:BAAALgADCgkJCQABLgAECgYJHQAJAEsWAA==.',
Ba='Baddiebrat:BAAALgAECgkJBgAAAA==.Badoink:BAAALgADCgUJBQABLgAECgcJGwASAMsjAA==.Baggedmilk:BAAALgADCgcJBwAAAA==.Baidin:BAAALgAECgMJAwAAAA==.Balorous:BAABLgAECn8eAAQTAAcJKRkMKwAFAgATAAcJKRkMKwAFAgAUAAUJbRWmDADuAAAVAAIJbweVcgBXAAAAAA==.Bansheelen:BAAALgADCgkJGwABLgAECgQJDgAWAAAAAA==.Bansheetrack:BAAALgADCgYJCwABLgAECgQJDgAWAAAAAA==.Banthis:BAABLgAECn8ZAAIFAAcJ5xlUOwAHAgAFAAcJ5xlUOwAHAgAAAA==.Barbarus:BAAALgAECgcJCwAAAA==.Bareclaw:BAAALgADCgYJBgAAAA==.Barillios:BAAALgAECgQJBAAAAA==.Barkcamon:BAABLgAECn8WAAISAAYJfBopEACmAQASAAYJfBopEACmAQAAAA==.Barthelo:BAABLgAECn8hAAIXAAgJOSGHAwAZAgAXAAgJOSGHAwAZAgAAAA==.Battlebeastt:BAAALgADCgYJBgAAAA==.',
Be='Beardedwiz:BAAALgADCgcJDwAAAA==.Beardhero:BAABLgAECn8sAAIYAAkJXSH1AABLAwAYAAkJXSH1AABLAwAAAA==.Beardrood:BAAALgADCgYJAwAAAA==.Beastylad:BAAALgAECgYJEAAAAA==.Bekahsama:BAAALgAECgQJCgAAAA==.Beld:BAAALgADCgYJDwAAAA==.Beldaran:BAAALgAECgYJEAAAAA==.Bellabubbles:BAAALgAECgQJDAAAAA==.Belladawna:BAABLgAECn8cAAIZAAgJpQm3PgA2AQAZAAgJpQm3PgA2AQAAAA==.Belldândy:BAAALgAECgEJAQAAAA==.Bennder:BAAALgAECgQJCAABLgAECgcJCgAWAAAAAA==.Beoffended:BAAALgAECgEJAgAAAA==.Bernal:BAAALgAECgYJDwAAAA==.',
Bh='Bhature:BAAALgADCgYJCwAAAA==.',
Bi='Bidtiddiedot:BAAALgADCgEJAQAAAA==.Bigmapletree:BAABLgAECn8gAAIaAAcJoBcxEQCXAQAaAAcJoBcxEQCXAQAAAA==.Bigpumper:BAAALgADCgIJAgABLgAFFAUJDwAJAP4hAA==.Bigsteppah:BAAALgAECgUJCAAAAA==.Bigëmu:BAAALgAECgMJAwAAAA==.Bingbängpow:BAAALgAECgkJBQAAAA==.',
Bl='Blackblader:BAAALgAECgUJCwAAAA==.Bladekraft:BAAALgADCgUJCAAAAA==.Bladrick:BAAALgADCgEJAQAAAA==.Blindndumb:BAAALgADCgIJAgAAAA==.Blondeshaman:BAAALgAECgUJBQABLgAFFAQJCwAIAIwOAA==.',
Bo='Boarggon:BAAALgAECgQJBAABLgAECgcJEQAWAAAAAA==.Boggart:BAAALgAECgQJBAAAAA==.Bonk:BAAALgAECgQJCAAAAA==.Bonkboi:BAAALgAECgUJCAAAAA==.Bonkitty:BAAALgADCgcJDgAAAA==.Bonku:BAAALgADCgcJBwAAAA==.Bonnie:BAAALgAECgIJAgAAAA==.Bonnéy:BAAALgADCgYJCQABLgAECgUJCAAWAAAAAA==.Boog:BAAALgADCgEJAQAAAA==.Borealus:BAAALgAECggJCAAAAA==.Bowl:BAAALgAECgUJCQAAAA==.',
Br='Bratakk:BAAALgAECggJCQAAAA==.Brillina:BAAALgAECgYJBgAAAA==.Bris:BAABLgAECn8eAAITAAcJ6RA1LAAwAQATAAcJ6RA1LAAwAQAAAA==.Bruby:BAAALgAECggJEwAAAA==.Brugamen:BAABLgAECn8dAAIbAAgJtBNIEgClAQAbAAgJtBNIEgClAQAAAA==.Brugg:BAAALgADCgYJBgABLgAECggJHQAbALQTAA==.Bruugg:BAAALgADCgEJAQABLgAECggJHQAbALQTAA==.Brád:BAABLgAECn8hAAIcAAgJ3RiBBQBgAgAcAAgJ3RiBBQBgAgAAAA==.',
Bu='Bubdly:BAAALgAECgQJBwAAAA==.Bunnylajoya:BAAALgADCgcJBwAAAA==.Burntha:BAAALgAECgEJAQAAAA==.',
['Bä']='Bäldur:BAABLgAECn8hAAIdAAgJaxOWAgDLAQAdAAgJaxOWAgDLAQAAAA==.',
Ca='Cainan:BAAALgAECgUJBgAAAA==.Calestel:BAAALgAECgQJBAAAAA==.Captinblye:BAAALgADCgEJAQAAAA==.Carmelita:BAABLgAECn8WAAIZAAYJeAXIWwDeAAAZAAYJeAXIWwDeAAAAAA==.Caroweaven:BAAALgADCgcJFAAAAA==.Cassienne:BAABLgAECn8gAAIJAAcJxhBmGgBAAQAJAAcJxhBmGgBAAQAAAA==.Catpounce:BAAALgADCgkJFwAAAA==.',
Ce='Cedaver:BAABLgAECn8hAAIbAAgJAB2BBgBKAgAbAAgJAB2BBgBKAgAAAA==.Cellphoneguy:BAABLgAECn8cAAMBAAYJ8gzRYgDtAAABAAYJ8gzRYgDtAAAYAAQJiQKVhQBiAAAAAA==.Celtigar:BAAALgAECgQJBQAAAA==.',
Ch='Chaan:BAABLgAECn8YAAMIAAcJLh2AEgDbAQAIAAcJLh2AEgDbAQAJAAQJHQYkbgCKAAAAAA==.Chaddicus:BAAALgADCgUJBQAAAA==.Chaitea:BAAALgADCgQJBAAAAA==.Chamael:BAAALgAECgIJAwAAAA==.Champo:BAAALgAECgEJAQAAAA==.Chance:BAAALgADCgYJBgAAAA==.Chereth:BAAALgAECgYJDwAAAA==.Cherwin:BAAALgADCgQJBAAAAA==.Cheshire:BAABLgAECn8nAAIDAAgJeBwNBQAtAgADAAgJeBwNBQAtAgAAAA==.Chiers:BAAALgAECgMJAwAAAA==.Chikkaboom:BAAALgAECgcJCgAAAA==.Chillhawg:BAAALgADCgcJBwAAAA==.Chionee:BAAALgADCgEJAQAAAA==.Chiweave:BAAALgAECgYJCQAAAA==.Chlorin:BAAALgAECgUJBgAAAA==.Chocolate:BAACLgAFFH8GAAIeAAUJFwzzOADwAAAeAAUJFwzzOADwAAAuAAQKfxQAAx4ACAmwHLlZACwCAB4ACAl1GrlZACwCAB8ABAljFw0NAPoAAAAA.Chucklehead:BAAALgADCgkJDgAAAA==.Chumchum:BAAALgAECggJEAAAAA==.Chunala:BAAALgADCgcJFgABLgAECgYJEAAWAAAAAA==.',
Ci='Cirah:BAAALgAECgMJAwAAAA==.Cityofrivers:BAAALgAECggJEwAAAA==.',
Cl='Classyfied:BAABLgAECn8cAAISAAYJkiBxDADgAQASAAYJkiBxDADgAQAAAA==.Clennse:BAAALgADCgYJCAAAAA==.Clickbait:BAAALgAECgUJBQAAAA==.Clob:BAAALgAFFAEJAQAAAA==.Cloudcrasher:BAABLgAECn8cAAMbAAgJvx6aBAB3AgAbAAgJvx6aBAB3AgARAAIJTRIVLwB9AAAAAA==.Cloudsayer:BAAALgADCgYJBQAAAA==.Cloudseeker:BAAALgADCgUJBQAAAA==.Cloudspeaker:BAAALgAECgYJBwAAAA==.',
Co='Coldblades:BAAALgAECgEJAQAAAA==.Coldblow:BAABLgAECn8ZAAICAAgJkBFwCACKAQACAAgJkBFwCACKAQAAAA==.Coldfrostshk:BAAALgAECgIJAgAAAA==.Coldslayer:BAABLgAECn8hAAIHAAgJ7RpREgAAAgAHAAgJ7RpREgAAAgAAAA==.Corbeau:BAAALgADCgkJCQAAAA==.Cordorana:BAAALgADCgkJEQAAAA==.Coronax:BAAALgADCgEJAQAAAA==.Cosetti:BAAALgADCgQJBAAAAA==.',
Cr='Crackzap:BAABLgAECn8UAAIZAAgJBRN6TwDaAQAZAAgJBRN6TwDaAQAAAA==.Crazyrd:BAABLgAECn8VAAIgAAYJdAt3DQDPAAAgAAYJdAt3DQDPAAAAAA==.Crittydps:BAAALgADCgEJAQAAAA==.Crocs:BAAALgADCgcJDwABLgAECgUJEQAWAAAAAA==.Crotgustus:BAAALgADCgIJAgABLgAFFAIJAgAWAAAAAA==.Crummbly:BAAALgAECgQJBAAAAA==.Crìtorís:BAAALgADCgcJFgAAAA==.',
Ct='Ctrlc:BAAALgAECgMJAwAAAA==.Ctrlshot:BAAALgAECgcJEAABLgAECgkJBQAWAAAAAA==.',
Cu='Cursedsoulz:BAAALgADCgUJBQAAAA==.',
Cy='Cyber:BAAALgAECgEJAQAAAA==.Cyndelle:BAAALgAECgUJCwAAAA==.Cyndro:BAAALgAECgQJCwAAAA==.Cyntaria:BAABLgAECn8WAAITAAYJYwW/QgDGAAATAAYJYwW/QgDGAAAAAA==.',
Da='Dafrostmon:BAAALgAECgIJAwABLgAECgYJDgAWAAAAAA==.Dagardugg:BAAALgAECgEJAQAAAA==.Dajmibuzi:BAABLgAECn8bAAIFAAgJnRRvIwBfAQAFAAgJnRRvIwBfAQAAAA==.Dalari:BAAALgADCgYJBwAAAA==.Danamor:BAABLgAECn8ZAAIBAAcJqhGIPABUAQABAAcJqhGIPABUAQAAAA==.Dandanx:BAAALgAECgMJBAAAAA==.Darciaa:BAABLgAECn8UAAIhAAcJTw6nKAC1AQAhAAcJTw6nKAC1AQAAAA==.Darnel:BAABLgAECn8hAAICAAgJXhiBBQDbAQACAAgJXhiBBQDbAQAAAA==.Darnokk:BAAALgAECgYJDQAAAA==.Darrek:BAAALgADCgMJAwAAAA==.Darthvenom:BAAALgADCgMJBAAAAA==.Dawnshield:BAAALgAECgQJDgAAAA==.',
De='Deathbyfel:BAAALgAECgEJAQABLgAECggJHQAJAOMhAA==.Deathbyshock:BAABLgAECn8dAAIJAAgJ4yH2BgA4AgAJAAgJ4yH2BgA4AgAAAA==.Deathstrokee:BAAALgAECgEJAwAAAA==.Deceez:BAAALgADCgUJBQABLgAECgYJFgAFAA4iAA==.Dedlok:BAAALgADCgIJAgAAAA==.Delgiadamar:BAAALgADCgMJAwAAAA==.Demoncelt:BAABLgAECn8WAAIUAAgJAQ76CwD+AAAUAAgJAQ76CwD+AAAAAA==.Demongotha:BAAALgADCgcJBwAAAA==.Demovaj:BAAALgAECgYJDQAAAA==.Demulos:BAAALgADCgYJCAAAAA==.Denarror:BAAALgADCgEJAQAAAA==.Denrukhan:BAABLgAECn8tAAQVAAkJ3CEfCAAUAwAVAAkJ3CEfCAAUAwATAAgJWyHtBwCPAgAPAAIJRxeEKACJAAAAAA==.Deschain:BAAALgAECgQJBwAAAA==.',
Di='Diin:BAABLgAECn8YAAIeAAcJigWQZAASAQAeAAcJigWQZAASAQAAAA==.Dillypoo:BAAALgADCgEJBAAAAA==.',
Dj='Djinger:BAAALgADCgUJBQAAAA==.',
Dk='Dklord:BAAALgAECgcJDQAAAA==.',
Do='Donkedixkek:BAAALgAECgEJAQAAAA==.Donkedixlol:BAAALgAECgEJAQAAAA==.Donkedixlul:BAAALgADCgEJAQAAAA==.Donkedixon:BAAALgAECgcJEgAAAA==.Doobzers:BAAALgADCgYJBwABLgAFFAMJBgAaALAIAA==.Dowe:BAAALgADCgQJBAAAAA==.Doxtorprote:BAAALgAECgcJDAAAAA==.',
Dr='Dragonite:BAABLgAECn8iAAILAAgJcBbPCwDLAQALAAgJcBbPCwDLAQAAAA==.Dragoonred:BAABLgAECn8ZAAIiAAgJfRIHAgDOAQAiAAgJfRIHAgDOAQAAAA==.Dreadknightx:BAAALgADCgEJAQAAAA==.Dreamfyre:BAAALgAECgYJDAABLgAFFAYJEAAGALIUAA==.Dredd:BAAALgAECgYJEQAAAA==.Droko:BAAALgADCgUJBQAAAA==.Drom:BAAALgADCgYJBgAAAA==.Drougoss:BAAALgAECgQJBgAAAA==.Drraxx:BAABLgAECn8hAAMTAAgJ6RG1FQDWAQATAAgJ6RG1FQDWAQAVAAEJjQJsiAAnAAAAAA==.Drunk:BAABLgAECn8gAAQjAAgJjxRjCgDQAQAjAAgJjxRjCgDQAQAQAAYJ6gmJTgAJAQASAAUJNA2cQQDZAAAAAA==.Drïzzt:BAAALgADCgEJAQAAAA==.',
Du='Duskshield:BAAALgAECgEJAQABLgAECgQJDgAWAAAAAA==.',
Ea='Earthotome:BAAALgADCgUJBQAAAA==.',
Ec='Eckshin:BAAALgAECgYJCgAAAA==.',
Ed='Eddiemarz:BAAALgAECgEJAQAAAA==.Eddiezenchi:BAABLgAECn8aAAISAAgJAgYLHgAQAQASAAgJAgYLHgAQAQAAAA==.',
Ek='Ekateryn:BAAALgAECgEJAQAAAA==.Ekkaia:BAABLgAECn8cAAIHAAYJohcUNwA2AQAHAAYJohcUNwA2AQAAAA==.',
El='Eldanky:BAAALgAECgUJBgAAAA==.Elecraft:BAABLgAECn8YAAMcAAgJXxh/FAAGAgAcAAgJXxh/FAAGAgAaAAMJLBPTYgCkAAAAAA==.Eleminohpee:BAAALgAECgIJAwABLgAECggJGwAeAIQdAA==.Elephant:BAACLgAFFH8IAAMaAAQJrxfGBgAwAQAaAAQJfxPGBgAwAQAcAAIJ9BcZEwCdAAAuAAQKfx0AAxwACQnMHQcGAOsCABwACQmCHQcGAOsCABoABAmmDr8oALcAAAEuAAUUCAkhABwAlx4A.Elfypriestly:BAAALgADCgYJBgAAAA==.Eliminater:BAABLgAECn8XAAITAAcJhBo0EwDvAQATAAcJhBo0EwDvAQABLgAECgkJKwAZALUZAA==.Elythe:BAAALgAECgYJDgABLgAECgcJDQAWAAAAAA==.',
Em='Emeralis:BAAALgAECgQJBAAAAA==.',
En='Encana:BAABLgAECn8nAAIkAAgJaBNWBQCHAQAkAAgJaBNWBQCHAQAAAA==.Ender:BAAALgAECgUJCwAAAA==.Enoby:BAAALgAECgIJAQAAAA==.Enragedhïppo:BAAALgAECgYJDAAAAA==.',
Er='Erebseth:BAAALgADCgcJCgAAAA==.Erling:BAAALgADCgkJCQAAAA==.Errzza:BAAALgAECgYJDQAAAA==.Erunar:BAAALgAECgEJAwAAAA==.Eruptnghïppo:BAAALgADCgYJBgAAAA==.Eruuruu:BAAALgAECgQJDAAAAA==.',
Es='Eshà:BAABLgAECn8hAAIIAAcJLw8PJQBCAQAIAAcJLw8PJQBCAQAAAA==.',
Et='Etsupriest:BAABLgAECn8ZAAIlAAkJMR2zAQDWAgAlAAkJMR2zAQDWAgAAAA==.',
Eu='Eula:BAAALgADCgQJBAAAAA==.',
Ev='Evelynn:BAAALgAECgEJAgAAAA==.',
Ex='Exelia:BAAALgADCgYJBgABLgAFFAgJGwASAGUjAA==.Exqui:BAABLgAECn8aAAIZAAcJNyAgFAAEAgAZAAcJNyAgFAAEAgAAAA==.',
Ez='Ezral:BAAALgAECgEJAgABLgAECgUJBwAWAAAAAA==.Ezékiel:BAABLgAECn8cAAMCAAgJNQ2vEAD3AAACAAgJ0QmvEAD3AAABAAUJpgs30QDnAAAAAA==.',
['Eí']='Eíko:BAABLgAECn8fAAQaAAcJyBQ4IQDZAQAaAAcJvBQ4IQDZAQAlAAYJ7QeePAAOAQAcAAUJBw4TNAADAQAAAA==.',
Fa='Fad:BAAALgAECgYJCwAAAA==.Fadedhope:BAAALgADCgcJDQABLgAECgcJEQAWAAAAAA==.Faelwynn:BAAALgAECgEJAQAAAA==.Fafnar:BAABLgAECn8hAAITAAgJwRVAGgCuAQATAAgJwRVAGgCuAQAAAA==.Fafnie:BAABLgAECn8cAAIJAAcJmQROJwDsAAAJAAcJmQROJwDsAAAAAA==.Fallénlegacy:BAAALgADCgUJBQABLgAECgYJGAARAAARAA==.Fan:BAAALgAECggJEAAAAA==.Faunus:BAAALgADCgcJDAAAAA==.Fauxy:BAAALgAECgUJBQAAAA==.',
Fe='Feared:BAAALgAECgIJAwAAAA==.Felath:BAABLgAECn8YAAIkAAcJ5BtWAwDkAQAkAAcJ5BtWAwDkAQAAAA==.Feldspar:BAABLgAECn8eAAIYAAcJoBKgEwC6AQAYAAcJoBKgEwC6AQAAAA==.Fenyr:BAAALgAECgUJCAAAAA==.',
Fi='Fil:BAABLgAECn8YAAMjAAcJJh2ACAD2AQAjAAcJJh2ACAD2AQAQAAYJBAgoJADlAAAAAA==.Firepowr:BAAALgAECgQJBAAAAA==.Fishswife:BAAALgAECgUJCQAAAA==.Fissal:BAAALgAECgYJEwABLgAFFAIJBwASAG0YAA==.Fistoflurry:BAAALgAECgcJEQAAAA==.Fistymisty:BAAALgADCgEJAgAAAA==.',
Fl='Flemel:BAABLgAECn8XAAMlAAYJqBxoDQCuAQAlAAYJqBxoDQCuAQAcAAUJtwxhMwAIAQAAAA==.Floatingbush:BAAALgAECgcJEwAAAA==.Flompy:BAAALgAECgIJAgAAAA==.Floreil:BAAALgADCgUJDQAAAA==.',
Fo='Foofighter:BAAALgADCgUJAwAAAA==.Foopy:BAABLgAECn8cAAMNAAgJlBvrFwD7AQANAAgJTBrrFwD7AQAdAAQJ4hF4DADqAAAAAA==.Footoo:BAAALgAECgYJCgAAAA==.Forestsong:BAAALgADCgIJAgABLgAECgQJBQAWAAAAAA==.Foxyfife:BAAALgADCgUJBQAAAA==.',
Fr='Franksuba:BAAALgAECgQJEQAAAA==.Fringilla:BAAALgADCgMJAwAAAA==.Frogaloger:BAAALgADCgMJAwAAAA==.Frostitutë:BAAALgAECgEJAQAAAA==.Frostyshade:BAAALgAECgEJAQAAAA==.',
Fu='Funk:BAABLgAECn8rAAIZAAkJTh3uBADJAgAZAAkJTh3uBADJAgAAAA==.Futurama:BAAALgADCgcJCwAAAA==.',
Fz='Fzoul:BAABLgAECn8bAAMTAAcJ8w6eXwAzAQATAAYJsw+eXwAzAQAVAAMJnAv5LwCWAAAAAA==.',
Ga='Gabdragon:BAAALgAECgQJBAAAAA==.Gabfam:BAAALgAECgIJAwAAAA==.Gadgett:BAABLgAECn8YAAMRAAYJABECDQAzAQARAAYJABECDQAzAQAbAAIJQwJTmQBcAAAAAA==.Galdademon:BAAALgAECggJDwAAAA==.Galiophobia:BAABLgAECn8UAAIYAAYJuBSTHABmAQAYAAYJuBSTHABmAQAAAA==.Garrethul:BAAALgAECgQJEAAAAA==.Gathercow:BAAALgADCgcJCgAAAA==.Gavalar:BAAALgAECgUJEQAAAA==.Gawleywood:BAAALgAECgYJDwAAAA==.',
Ge='Gellidus:BAABLgAECn8XAAMKAAYJ0g25CQDZAAALAAYJ4QmlIwDpAAAKAAYJRwy5CQDZAAAAAA==.Genhooves:BAEBLgAECn8ZAAINAAgJOx0+EAA8AgANAAgJOx0+EAA8AgAAAA==.Genoesis:BAAALgADCgcJCgAAAA==.Gentleshadow:BAAALgADCgQJBAAAAA==.',
Gh='Ghenka:BAABLgAECn8UAAQHAAcJRBtfGADQAQAHAAYJRBtfGADQAQAGAAYJ/A4CRwA3AQADAAEJsBngLQA7AAABLgAFFAUJEQARADgiAA==.Ghosteagle:BAAALgADCgcJBgAAAA==.',
Gl='Gloomreaver:BAAALgAECgIJAwAAAA==.',
Gn='Gnarlysnarly:BAAALgADCgYJDAAAAA==.Gnomejodas:BAAALgAECgUJCgAAAA==.',
Go='Gobfather:BAAALgAECgIJAgAAAA==.Goldcity:BAACLgAFFH8KAAIkAAQJ6wztAQABAQAkAAQJ6wztAQABAQAuAAQKfxsAAiQACAm2Hb0DAJECACQACAm2Hb0DAJECAAAA.Goob:BAAALgAECgQJBwAAAA==.Goodfaith:BAAALgAECgQJBQAAAA==.',
Gr='Grimlocke:BAABLgAECn8bAAMZAAcJWhNXLQB3AQAZAAcJWhNXLQB3AQAgAAEJAADlZQBEAAAAAA==.Gromit:BAAALgAECggJEwABLgAFFAUJDgAaAN0UAA==.Grovewarden:BAAALgADCgEJAQAAAA==.',
Gu='Gug:BAAALgADCgcJCAAAAA==.Gullibull:BAABLgAECn8mAAImAAgJ0wfuBwB4AQAmAAgJ0wfuBwB4AQAAAA==.',
Gw='Gwynne:BAAALgAECgYJBgAAAA==.',
['Gí']='Gírthquake:BAAALgAECgQJBQABLgAFFAEJAQAWAAAAAA==.',
Ha='Halanad:BAAALgAECgYJEAAAAA==.Halcyone:BAAALgADCgUJBQAAAA==.Halfsumo:BAAALgAECgUJEQAAAA==.Halobender:BAAALgADCgcJBwAAAA==.Hamer:BAAALgADCgEJAQAAAA==.Hanamora:BAAALgADCgkJCQAAAA==.Harkonnen:BAAALgADCgYJEQAAAA==.Hassindiir:BAABLgAECn8fAAIUAAgJlgP9HgCoAAAUAAgJlgP9HgCoAAAAAA==.Hawgelf:BAAALgAECgcJEAAAAA==.Hawmahcide:BAAALgAECgYJCQAAAA==.Hayles:BAAALgAECgYJDQAAAA==.',
He='Heall:BAAALgAECgEJAQAAAA==.Hecklerkoch:BAABLgAECn8mAAIBAAgJTAm/OABhAQABAAgJTAm/OABhAQAAAA==.Helathra:BAABLgAECn8UAAMBAAYJYQ+kkABbAQABAAYJYQ+kkABbAQACAAMJwQfLNwBiAAAAAA==.Hellie:BAAALgAECgUJBgAAAA==.Hellmage:BAAALgADCgQJBAAAAA==.Hellward:BAAALgAECgMJAwAAAA==.Herevoker:BAAALgAECgYJCgABLgAFFAMJBAAWAAAAAA==.Hermaeuss:BAAALgADCgkJDQAAAA==.Herrogue:BAAALgAFFAMJBAAAAA==.',
Hi='Hishunter:BAABLgAECn8dAAIHAAgJDCLwCAAFAwAHAAgJDCLwCAAFAwAAAA==.',
Ho='Hobosam:BAABLgAECn8XAAMaAAYJZRIXOwBOAQAaAAYJiw8XOwBOAQAcAAUJZwfoHQDtAAAAAA==.Hollowarden:BAAALgADCgEJAgAAAA==.',
Hr='Hräfn:BAAALgADCgYJBgAAAA==.',
Hu='Huntarr:BAAALgAECgcJDgAAAA==.Hunterdamon:BAABLgAECn8YAAIFAAcJHgj+SADLAAAFAAcJHgj+SADLAAAAAA==.',
Hy='Hycinna:BAAALgAECgYJEQAAAQ==.Hydraashen:BAABLgAECn8WAAMfAAcJoQKcBwCKAAAeAAYJZAKGCQHpAAAfAAUJWwKcBwCKAAAAAA==.Hyndrix:BAAALgADCgEJAwAAAA==.',
Ia='Iamafish:BAABLgAECn8YAAIHAAcJxxytFQDkAQAHAAcJxxytFQDkAQAAAA==.Iamthestorm:BAAALgADCgUJBQAAAA==.',
Ic='Iceris:BAAALgAECgEJAgAAAA==.',
In='Incendemus:BAAALgAECgEJAwAAAA==.Insidae:BAABLgAECn8nAAIhAAgJtRJuCQDUAQAhAAgJtRJuCQDUAQAAAA==.',
Ir='Iraegin:BAAALgAECgIJAQAAAA==.',
Is='Iscreamloud:BAAALgAECgMJAwAAAA==.Ismirea:BAAALgAECgIJAwAAAA==.Isoldella:BAAALgADCgkJEgAAAA==.',
It='Itsben:BAAALgADCgEJAQAAAA==.',
Ja='Jalencarter:BAACLgAFFH8FAAINAAIJNCaIOwDhAAANAAIJNCaIOwDhAAAuAAQKfxgAAg0ACQmHJJACABYDAA0ACQmHJJACABYDAAAA.Jamirchaman:BAAALgAECgMJBQAAAA==.Jantasir:BAABLgAECn8dAAIBAAgJXxq1OABAAgABAAgJXxq1OABAAgAAAA==.Jarred:BAAALgAECgEJAwABLgAFFAEJAQAWAAAAAA==.Javalyn:BAAALgAECgYJDQAAAA==.Jaydonar:BAAALgADCgkJCQAAAA==.',
Je='Jerbo:BAAALgAECgMJBAAAAA==.',
Ji='Jinda:BAAALgADCggJIQAAAA==.',
Jo='Jobergas:BAABLgAECn8aAAMHAAYJKhFVOgApAQAHAAYJKhFVOgApAQAGAAEJ5gEfmQAcAAAAAA==.Johallas:BAABLgAECn8eAAIeAAcJDQyWUwA5AQAeAAcJDQyWUwA5AQAAAA==.Johnnyhotbod:BAAALgAECgEJAQAAAA==.Joleiste:BAAALgADCgYJCwAAAA==.Josrius:BAAALgAECgUJBQAAAA==.',
Ju='Juansnowe:BAAALgADCgkJCQAAAA==.Juf:BAAALgAECgUJDQAAAA==.Jufster:BAAALgADCgYJBgAAAA==.Julio:BAABLgAECn8aAAINAAcJKhqPVQDxAQANAAcJKhqPVQDxAQAAAA==.Jumpingbear:BAAALgAECggJCAAAAA==.',
Ka='Kaeir:BAAALgADCgUJBQAAAA==.Kaho:BAABLgAECn8dAAIdAAkJ6R6cAABGAwAdAAkJ6R6cAABGAwAAAA==.Kainazzo:BAAALgADCgkJKgAAAA==.Kaladïn:BAAALgAECgIJAgAAAA==.Kalaris:BAAALgAECgYJDwAAAA==.Kalda:BAABLgAECn8mAAIeAAcJFBxrPAB5AQAeAAcJFBxrPAB5AQABLgAFFAIJAgAWAAAAAA==.Kallisto:BAAALgAECgUJCgAAAA==.Kalthoz:BAAALgAECggJEgAAAA==.Karor:BAAALgAECgIJAgAAAA==.Kathrathryn:BAAALgAECgIJAgAAAA==.Kazuhiro:BAACLgAFFH8RAAMRAAUJOCIZAQCcAQARAAUJOCIZAQCcAQAbAAEJaB+7HgBZAAAuAAQKf1EAAxEACQlCJWoAACsDABsACAkqJVYFAFIDABEACQnFJGoAACsDAAAA.',
Ke='Keagan:BAAALgAECgYJBwAAAA==.Keevah:BAAALgAECggJDQAAAA==.Kegeratorr:BAAALgAECgYJEAAAAA==.Keinestina:BAAALgADCggJCgAAAA==.Kekg:BAAALgADCgkJCQABLgAECgcJGwASAMsjAA==.Kelric:BAAALgADCgQJBAAAAA==.Kenpomaster:BAAALgADCgIJAgAAAA==.Kerciel:BAAALgAECgMJAwABLgAECggJKgALAHQbAA==.Kerebos:BAAALgADCgEJAQAAAA==.Kexin:BAAALgADCgEJAQAAAA==.',
Kh='Khaluha:BAAALgAECgQJBAAAAA==.Khaymaan:BAAALgAECgUJEAAAAA==.Khitryy:BAAALgAECgYJDgAAAA==.',
Ki='Killdorei:BAABLgAECn8WAAIFAAYJDiKIJwBKAQAFAAYJDiKIJwBKAQAAAA==.Killios:BAAALgAECgMJAwAAAA==.',
Ko='Kozal:BAAALgADCgYJCgAAAA==.',
Kr='Krabskooter:BAAALgADCgYJCQAAAA==.Krionys:BAABLgAECn8fAAIYAAcJPBz5HQAnAgAYAAcJPBz5HQAnAgAAAA==.Krisha:BAABLgAECn8YAAIJAAcJbQ+eIwADAQAJAAcJbQ+eIwADAQAAAA==.Krisphobos:BAABLgAECn8WAAIHAAYJew9MOAAxAQAHAAYJew9MOAAxAQAAAA==.Krugzy:BAAALgADCgQJBAAAAA==.',
Kt='Ktrevious:BAABLgAECn8eAAIeAAgJyBkEKADFAQAeAAgJyBkEKADFAQAAAA==.',
Ku='Kuang:BAAALgAECgQJBAAAAA==.Kubael:BAAALgAECgUJBwAAAA==.Kulgutbuster:BAABLgAECn8dAAIHAAcJgR1rGADPAQAHAAcJgR1rGADPAQAAAA==.Kungpow:BAABLgAECn8hAAMjAAcJVBoeEAB8AQAjAAcJVBoeEAB8AQASAAMJXwOnOwBTAAAAAA==.Kuraash:BAAALgAECgUJCQAAAA==.Kuroken:BAAALgAECgIJAgAAAA==.Kuromatsu:BAABLgAECn8hAAITAAgJTR+GCgBgAgATAAgJTR+GCgBgAgAAAA==.',
Ky='Kyria:BAABLgAECn8UAAIFAAYJFAQpZwBxAAAFAAYJFAQpZwBxAAAAAA==.',
['Kì']='Kìngpin:BAAALgAECgQJBQABLgAECgcJGwATAPMOAA==.',
['Kÿ']='Kÿt:BAAALgAECgYJDgAAAA==.',
La='Lacedon:BAABLgAECn8XAAIbAAcJMA6OGABsAQAbAAcJMA6OGABsAQAAAA==.Laissa:BAAALgADCgkJIgAAAA==.Lancerdrake:BAAALgAECgQJBwAAAA==.Laquisha:BAABLgAECn8WAAIDAAcJyhtNBwD0AQADAAcJyhtNBwD0AQAAAA==.Larfleeze:BAAALgADCgkJHwAAAA==.Largewagon:BAAALgAECgIJBAAAAA==.Larque:BAAALgAECgYJAgABLgAECgkJBQAWAAAAAA==.Larryy:BAAALgADCgUJBQAAAA==.Latronia:BAAALgAECgcJAQAAAA==.Lauriena:BAAALgADCgcJBwAAAA==.',
Le='Lethaldx:BAAALgAECgQJBgAAAA==.Lettuceman:BAAALgADCgEJAQAAAA==.',
Li='Lialune:BAAALgAECgcJDwAAAA==.Liarae:BAAALgAECgIJAgABLgAECggJIwAIAH8hAA==.Lilgup:BAAALgAECgQJBgAAAA==.Lilÿ:BAAALgADCgYJCQAAAA==.Linadrea:BAAALgADCgkJGwAAAA==.Liqudblu:BAAALgADCgcJCgAAAA==.Liqudfury:BAAALgAECgQJBAAAAA==.Lishan:BAABLgAECn8qAAQLAAgJdBs9CAAMAgALAAgJ2hg9CAAMAgAKAAYJpRzTDwDeAQAMAAUJ3xVYJwA5AQAAAA==.Literein:BAAALgAECgcJDQAAAA==.Lizora:BAAALgAECgEJAwAAAA==.',
Ll='Llamasmol:BAAALgADCgUJBQAAAA==.Llanfear:BAAALgADCgYJBgAAAA==.Llight:BAAALgAECgYJBgABLgAECgcJFAALAPoeAA==.',
Lo='Lockwar:BAAALgADCgkJCQAAAA==.Locria:BAAALgAECgMJBAAAAA==.Lokki:BAAALgAECgYJEgAAAA==.Loreguy:BAAALgAECgEJAwAAAA==.Lorenei:BAABLgAECn8aAAINAAcJjR5AFgAIAgANAAcJjR5AFgAIAgAAAA==.Loriol:BAAALgADCgUJBQABLgAECgcJDgAWAAAAAA==.Lorrith:BAAALgADCgcJCwAAAA==.Los:BAAALgAECgYJDQAAAA==.',
Lu='Lucìd:BAAALgAECgYJCwAAAA==.Ludopatika:BAAALgAECgMJAwAAAA==.Lunaala:BAAALgAECgYJDgAAAA==.Lunhzae:BAABLgAECn8jAAMMAAcJgSCxAgCFAgAMAAcJgSCxAgCFAgAKAAMJUQpAMQCMAAAAAA==.Lustallo:BAAALgAECgYJDwAAAA==.',
Ly='Lynxx:BAAALgADCgYJCgAAAA==.Lyressa:BAAALgADCgEJAgAAAA==.',
Ma='Mack:BAAALgAECgcJBwAAAA==.Mad:BAABLgAECn8bAAISAAcJyyN8AwC7AgASAAcJyyN8AwC7AgAAAA==.Madchickenz:BAABLgAECn8ZAAIVAAcJExpiDgCpAQAVAAcJExpiDgCpAQAAAA==.Madrina:BAAALgAECgMJBAAAAA==.Maelstrom:BAAALgADCgQJBAAAAA==.Magicwithin:BAAALgAECgYJGQAAAQ==.Magut:BAAALgADCgMJAwAAAA==.Maim:BAAALgADCgYJCQAAAA==.Maira:BAAALgAECgUJCwAAAA==.Malevolens:BAABLgAECn8aAAINAAYJSwxAUwAIAQANAAYJSwxAUwAIAQAAAA==.Malkinish:BAAALgAECgMJAwABLgAECgcJHgAHAKYmAA==.Maraella:BAAALgAECgUJDAAAAA==.Marche:BAABLgAECn8dAAIZAAcJKQwQPwA1AQAZAAcJKQwQPwA1AQAAAA==.Marcrutzou:BAAALgAFFAEJAQAAAA==.Mavar:BAABLgAECn8VAAIkAAcJlSLBAwCQAgAkAAcJlSLBAwCQAgAAAA==.Mavrar:BAAALgAECgEJAQABLgAECgcJFQAkAJUiAA==.Mazzikin:BAAALgADCgQJBAAAAA==.',
Me='Meatslapper:BAAALgADCgYJBgAAAA==.Megito:BAAALgAECgEJAgAAAA==.Menoboo:BAAALgADCgQJBAAAAA==.Mephïsto:BAAALgAECgcJEQAAAA==.Messdupllama:BAABLgAECn8eAAQHAAcJpiaqBQCeAgAHAAcJvyWqBQCeAgAGAAIJ4CBEZgCmAAADAAEJcSPsJQBnAAAAAA==.Metamorfasis:BAABLgAECn8YAAIPAAYJkwbrDwDaAAAPAAYJkwbrDwDaAAAAAA==.',
Mi='Microburst:BAABLgAECn8bAAIeAAgJhB3zMQCcAQAeAAgJhB3zMQCcAQAAAA==.Microlight:BAAALgADCgcJCAABLgAECggJGwAeAIQdAA==.Midgethealz:BAAALgADCgcJCwABLgAECggJGQAiAH0SAA==.Mightynite:BAAALgAECgUJBQAAAA==.Miischief:BAAALgAECgYJDAAAAA==.Millene:BAAALgAECgYJEAABLgAECgMJBQAWAAAAAA==.Mimikyu:BAAALgADCgQJBQAAAA==.Miraclesz:BAAALgAECgQJBAABLgAECgUJCAAWAAAAAA==.Missmoodý:BAAALgAECgQJBAAAAA==.Missqwerty:BAAALgAECgEJAQAAAA==.',
Mo='Mongargiss:BAAALgAECgYJEwAAAA==.Montaro:BAAALgAECgYJDwAAAA==.Moochew:BAAALgADCgUJBQAAAA==.Moonz:BAAALgAECgYJCQAAAA==.Morbidi:BAAALgAECgYJEQAAAA==.Morsmordre:BAAALgADCgYJDgAAAA==.',
Mu='Mudkip:BAACLgAFFH8QAAIlAAYJtg5aAgCbAQAlAAYJtg5aAgCbAQAuAAQKfycAAiUACQlKHy4BAPwCACUACQlKHy4BAPwCAAAA.Mushinomad:BAAALgAECgYJCwAAAA==.Mushrumpizza:BAAALgADCgQJBAAAAA==.',
My='Mylanara:BAABLgAECn8aAAIbAAcJQxlPEQCvAQAbAAcJQxlPEQCvAQAAAA==.Mysticah:BAAALgAECgYJDgAAAA==.Myvrth:BAAALgADCgUJCAAAAA==.',
['Mø']='Møød:BAAALgADCgQJBAAAAA==.',
Na='Nadashilth:BAAALgADCgIJAgABLgAECggJIwAIAH8hAA==.Namednott:BAAALgADCgcJFQAAAA==.Namya:BAAALgAECggJDgAAAA==.Nanr:BAAALgAECgYJEQAAAA==.Nasdan:BAAALgAFFAIJAgAAAA==.Nathi:BAAALgAECgYJEAAAAA==.Navori:BAAALgAECgQJBwABLgAFFAYJEAAGALIUAA==.',
Ne='Nedia:BAAALgADCgEJAQAAAA==.Nefarioso:BAAALgAECgEJAQAAAA==.Nerve:BAABLgAECn8fAAIeAAcJ+RlDQwBlAQAeAAcJ+RlDQwBlAQAAAA==.Nesiryn:BAAALgADCgMJAwAAAA==.Newkers:BAAALgADCgIJAgAAAA==.',
Ni='Niamber:BAACLgAFFH8QAAMGAAYJshSXBwChAQAGAAYJMBOXBwChAQAHAAIJ3RTwFQCtAAAuAAQKfxYAAwYACAmRHbUkAP8BAAYABwnkG7UkAP8BAAcABAl7GvNhAEEBAAAA.Nightràven:BAAALgAECgcJEQAAAA==.Nillawaffer:BAAALgAECgcJEgAAAA==.Nimrodd:BAAALgAECgIJAgAAAA==.Ninjava:BAAALgADCgkJEwAAAA==.Nirale:BAAALgADCgEJAQABLgAECgQJBwAWAAAAAA==.',
No='Noobzy:BAAALgADCgYJBwAAAA==.Noraldori:BAAALgADCgkJCQABLgAECgYJEwAWAAAAAA==.Nordimont:BAAALgAECgUJCQAAAA==.Nothotdog:BAAALgADCgUJBQAAAA==.Novacat:BAABLgAECn8hAAITAAgJACDiDADWAgATAAgJACDiDADWAgAAAA==.November:BAAALgAECgUJEQAAAA==.',
Nu='Nubriss:BAABLgAECn8UAAIUAAcJnhAREwBAAQAUAAcJnhAREwBAAQAAAA==.Nuff:BAAALgADCgYJCAAAAA==.Nuttrbutterz:BAAALgAECgQJDAAAAA==.',
Ny='Nyaboron:BAAALgAECgUJDQAAAA==.Nyv:BAAALgADCgcJDgAAAA==.',
['Nè']='Nèaner:BAABLgAECn8fAAIaAAgJmwfQOgBPAQAaAAgJmwfQOgBPAQAAAA==.',
['Nó']='Nó:BAAALgADCgQJBAAAAA==.',
Ob='Obex:BAAALgADCgcJDwAAAA==.',
Od='Odethia:BAAALgAECgMJBAAAAA==.',
Og='Ogrebane:BAABLgAECn8hAAIhAAgJawScEgBMAQAhAAgJawScEgBMAQAAAA==.',
Oi='Oiheg:BAABLgAECn8dAAIEAAcJwx6BBAAmAgAEAAcJwx6BBAAmAgAAAA==.Oilchickenjr:BAAALgADCgEJAQAAAA==.',
Ol='Oldracks:BAAALgAECgUJBwAAAA==.Ollipop:BAAALgADCgUJBQAAAA==.',
Oo='Oonjaya:BAAALgAECgkJBQAAAA==.',
Or='Orangez:BAAALgAECgIJAgAAAA==.Orderic:BAAALgADCgYJBgAAAA==.',
Ov='Overcast:BAACLgAFFH8HAAISAAIJbRifFQCMAAASAAIJbRifFQCMAAAuAAQKfyAAAhIACAlPHe0HADoCABIACAlPHe0HADoCAAAA.',
Ow='Owlclaw:BAAALgAECgMJBQAAAA==.',
Oz='Ozzlo:BAAALgAECgYJEgAAAA==.',
Pa='Paako:BAAALgAECgIJAwAAAA==.Pad:BAAALgAECgYJEwAAAA==.Palavaj:BAAALgAECgIJAwAAAA==.Pandawyngz:BAAALgAECgYJCQAAAA==.Pangho:BAAALgADCgcJCAAAAA==.Park:BAAALgAECgYJBgAAAA==.Parttimebear:BAAALgADCgkJCQABLgAECgcJEgAWAAAAAA==.',
Pe='Percent:BAAALgADCgUJBQAAAA==.',
Ph='Phaaryn:BAAALgAECgYJDAAAAA==.Phatfriend:BAAALgAECgIJAgAAAA==.Pheare:BAAALgADCgkJCQABLgAECgMJBQAWAAAAAA==.Phiis:BAAALgAECgYJCwAAAA==.Phonix:BAAALgADCgYJBgAAAA==.Photos:BAABLgAECn8hAAIYAAgJ7yOuAQAXAwAYAAgJ7yOuAQAXAwAAAA==.Phyxus:BAAALgADCgkJCQABLgAECgMJBQAWAAAAAA==.',
Pi='Pigums:BAAALgAECgYJDAABLgAECgcJEgAWAAAAAA==.Pilon:BAAALgAECgYJBgAAAA==.Pilupi:BAAALgAECgYJCQABLgAFFAIJBgAGAIgRAA==.Pineapplez:BAAALgADCgMJAwABLgAECgIJAgAWAAAAAA==.Pirraa:BAAALgAECgYJEgAAAA==.Pitifulworhm:BAAALgAECgEJAQABLgAECgcJGgANAI0eAA==.Pixelpuffs:BAAALgAECgIJAwAAAA==.',
Pl='Platekini:BAAALgAECgMJBgAAAA==.Pluug:BAABLgAECn8dAAIeAAgJJhmjMgCaAQAeAAgJJhmjMgCaAQAAAA==.',
Po='Poceidon:BAAALgAECgcJCAAAAA==.Pochi:BAAALgADCgkJEAABLgAECgYJFgASAHwaAA==.Pongo:BAEALgADCgEJAQABLgAECggJGQANADsdAA==.Pookiebear:BAAALgAECgQJCQAAAA==.Poptartyummy:BAAALgADCgcJBwAAAA==.Potaetoew:BAAALgAECgQJBAAAAA==.',
Pp='Pp:BAAALgAECgUJEQAAAA==.',
Pr='Propofheal:BAAALgAECgQJCAAAAA==.Prîde:BAAALgAECgIJAgAAAA==.',
Ps='Psycopath:BAAALgAECgcJEQAAAA==.Psynide:BAAALgADCgUJBQABLgAECggJIQAXADkhAA==.',
Pt='Ptra:BAAALgAECgYJCwAAAA==.',
Pu='Puddingfarts:BAAALgAECgYJDgAAAA==.Puffcookies:BAAALgADCgcJDAAAAA==.Pumpy:BAACLgAFFH8PAAIJAAUJ/iGqAwCRAQAJAAUJ/iGqAwCRAQAuAAQKfyAAAgkACQneI8YCAH8DAAkACQneI8YCAH8DAAAA.',
Py='Pyraeline:BAAALgADCgYJBgAAAA==.Pyriana:BAAALgADCgEJAQAAAA==.Pywacket:BAABLgAECn8cAAMaAAgJ+wNGIQD3AAAaAAgJ0ANGIQD3AAAcAAgJBgGeKACJAAAAAA==.',
Qu='Quendia:BAAALgADCgEJAQABLgAFFAYJBwASAHAQAA==.Quendwings:BAACLgAFFH8NAAIYAAUJTyJUBwBfAQAYAAUJTyJUBwBfAQAuAAQKfygABBgACQk6IkMGAAcDABgACQk6IkMGAAcDAAEABwnwF5lWAN4BAAIAAgmzGEojAEsAAAEuAAUUBgkHABIAcBAA.Quenn:BAAALgAECgUJBQABLgAFFAYJBwASAHAQAA==.',
Ra='Rabern:BAAALgAECgMJBAAAAA==.Randòn:BAAALgADCgEJAQAAAA==.Ranorah:BAABLgAECn8gAAMHAAgJVR+dEwCaAgAHAAcJpyCdEwCaAgAGAAUJ8w9lVgDuAAAAAA==.Rasmatazz:BAAALgADCgMJAwAAAA==.Ratley:BAAALgADCgMJBAAAAA==.Rayleighh:BAAALgAECgEJAgAAAA==.Razzaksa:BAAALgADCgkJDAAAAA==.',
Re='Redemptio:BAAALgAECgUJCQAAAA==.Regg:BAAALgADCgkJDAAAAA==.Regoros:BAAALgAECgEJAQAAAA==.Reinstorm:BAAALgAECgMJAwABLgAECgcJDQAWAAAAAA==.Rekien:BAAALgADCgYJCAAAAA==.Rentsu:BAAALgAECgEJAQAAAA==.Repentthis:BAAALgADCgEJAQAAAA==.Reuben:BAAALgAECgEJAQABLgAECgEJAQAWAAAAAA==.Revolution:BAAALgAECgEJAQAAAA==.',
Rh='Rhoorisa:BAAALgAECgMJBgAAAA==.',
Ri='Rickrossin:BAAALgAECgQJBgAAAA==.Rikaza:BAAALgAECgUJEQAAAA==.',
Ro='Roguehuman:BAAALgAECgQJCgABLgAECggJGwAEABkTAA==.Rootwarden:BAAALgADCgYJBgAAAA==.Rosefang:BAAALgADCgkJDAAAAA==.Rozzluz:BAAALgAECgYJCAAAAA==.',
Ru='Runiczeal:BAAALgADCgcJDAAAAA==.Rutira:BAABLgAECn8fAAMOAAgJHiRIBgAFAwAOAAgJHiRIBgAFAwAFAAYJPhX1ZABzAQAAAA==.Ruzz:BAAALgAECgEJAQAAAA==.',
Ry='Ryân:BAAALgAECgMJBQAAAA==.',
['Rú']='Rúmi:BAAALgADCgkJDwAAAA==.',
Sa='Saana:BAAALgADCgcJCgABLgAFFAUJCQAhAAAUAA==.Saccharïn:BAAALgAECgYJBgABLgAECgYJGgALAP0OAA==.Saiyun:BAAALgAECgQJBwAAAA==.Sakkara:BAAALgADCgMJAwAAAA==.Saldaria:BAAALgAECgQJBwAAAA==.Salder:BAAALgADCgUJBQAAAA==.Sallyslsmshr:BAAALgAECgQJBwAAAA==.Sapling:BAAALgADCgEJAQAAAA==.Sapphiwrath:BAAALgAECgQJCAAAAA==.Sarbif:BAAALgADCgUJBQAAAA==.Sarkress:BAAALgADCgIJAgAAAA==.Sartara:BAAALgAECgEJAQAAAA==.Sassybadassy:BAAALgADCgIJAgAAAA==.Sathenoth:BAAALgAECgUJEAAAAA==.',
Se='Seacow:BAAALgAECgUJBQAAAA==.Selinnaria:BAAALgADCgUJBQAAAA==.Selyana:BAAALgADCgcJBwAAAA==.Serakor:BAAALgAECgEJAQAAAA==.Seylena:BAAALgAECgMJBgABLgAECggJIQAjAGUYAA==.',
Sh='Shadowdyn:BAAALgADCgUJBQAAAA==.Shalona:BAAALgAECgEJAQAAAA==.Shamamma:BAAALgADCgMJAwAAAA==.Shammywammy:BAAALgADCgYJBgAAAA==.Shamuelâdams:BAAALgADCgEJAQABLgAECggJHQABAF8aAA==.Shamæn:BAAALgAECgQJBAAAAA==.Shanto:BAAALgAECgQJBQAAAA==.Shaxia:BAAALgAECgcJBwAAAA==.Shieldon:BAAALgAECgEJAgABLgAECggJIQATAE0fAA==.Shiftyy:BAAALgADCgcJCgAAAA==.Shikamarú:BAAALgAECgQJBAAAAA==.Shiverusnape:BAAALgAECgYJDAAAAA==.Shroomiez:BAAALgAECgEJAQAAAA==.Shåmpon:BAAALgAECgUJDgAAAA==.',
Si='Silvernleaf:BAAALgAECgUJCwAAAA==.Sinai:BAABLgAECn8eAAITAAcJOA8DKABIAQATAAcJOA8DKABIAQAAAA==.Sinny:BAAALgAECgQJBAAAAA==.Sirlancer:BAAALgADCgYJBgAAAA==.Sizzurp:BAAALgAECggJDQABLgAECgYJEAAWAAAAAA==.',
Sk='Skaudi:BAAALgADCgYJCwAAAA==.Skept:BAABLgAECn8ZAAIhAAgJywq/EgBLAQAhAAgJywq/EgBLAQAAAA==.',
Sl='Sleepingbear:BAAALgADCgkJCQABLgAECggJHAAnACgcAA==.Slinkydog:BAAALgAECgYJEwAAAA==.Slobster:BAAALgAECgcJEwAAAA==.Slomp:BAAALgADCgYJBgABLgAFFAMJBwAIAFEbAA==.Slosh:BAACLgAFFH8HAAIIAAMJURsPEgD/AAAIAAMJURsPEgD/AAAuAAQKfyIAAwgACAlbJM4KANACAAgACAlbJM4KANACAAkAAwmLDZw1AJ4AAAAA.Slumbers:BAAALgADCgYJCwAAAA==.Slêep:BAAALgAECgYJBgAAAA==.',
Sm='Smerffy:BAABLgAECn8dAAQIAAgJ3gnQMQD2AAAIAAcJGAnQMQD2AAAmAAQJfQ6kHgDlAAAJAAQJkwgIQwBcAAAAAA==.Smites:BAAALgAECgMJBgABLgAECggJIQABAOAiAA==.',
Sn='Sneha:BAAALgADCgkJGQAAAA==.Snorlax:BAAALgADCgcJCgAAAA==.',
So='Solammallama:BAAALgADCgIJAgAAAA==.Sonistris:BAAALgADCgUJBQAAAA==.Sonny:BAABLgAECn8bAAIeAAYJmBuongCZAQAeAAYJmBuongCZAQAAAA==.Sorshalynne:BAABLgAECn8aAAIZAAYJYwVkXQDaAAAZAAYJYwVkXQDaAAAAAA==.Soulblast:BAAALgADCgMJAwAAAA==.Soulhorror:BAABLgAECn8aAAMNAAcJSRnfVgDtAQANAAcJSRnfVgDtAQAXAAMJVA0VKwA0AAAAAA==.Southernco:BAAALgADCgYJCgAAAA==.',
Sp='Spacephoenix:BAABLgAECn8jAAMaAAgJ8hV3HwDlAQAaAAgJUhV3HwDlAQAcAAcJ+w7oFABOAQAAAA==.Spiccolii:BAAALgAECgMJBAAAAA==.Spitefury:BAAALgAECgYJBgABLgAECgYJFgASAHwaAA==.Spriggs:BAEALgAECgYJCAABLgAECggJGQANADsdAA==.',
St='Starrfîre:BAABLgAECn8rAAIZAAkJtRl9CACFAgAZAAkJtRl9CACFAgAAAA==.Stellaris:BAAALgADCgcJDAAAAA==.Stonecurse:BAAALgADCgMJAwABLgAECgYJEQAWAAAAAA==.Stonedread:BAAALgAECgYJEQAAAA==.Stonedzilla:BAAALgADCgQJBwAAAA==.',
Su='Sullyboy:BAABLgAECn8VAAITAAcJQR+gMQDkAQATAAcJQR+gMQDkAQABLgAFFAUJBgAeABcMAA==.Sunaril:BAAALgAECgIJAwAAAA==.Sunntzu:BAAALgAECgUJCAAAAA==.Supevoker:BAAALgADCgUJBQABLgADCgYJBgAWAAAAAA==.',
Sw='Swindlle:BAABLgAECn8YAAICAAcJaQrMEgDbAAACAAcJaQrMEgDbAAAAAA==.',
Sy='Syber:BAABLgAECn8bAAITAAgJsxuJFQDXAQATAAgJsxuJFQDXAQAAAA==.Sylvá:BAAALgADCgcJEAAAAA==.Sympathy:BAAALgADCgYJBgAAAA==.Symphonica:BAAALgAECgYJEQAAAA==.Synthesize:BAAALgAECgMJBQAAAA==.',
['Sî']='Sîccness:BAABLgAECn8hAAISAAcJEBg9EwB+AQASAAcJEBg9EwB+AQAAAA==.',
Ta='Tachelia:BAAALgADCgYJBgABLgAECgcJHgATACkZAA==.Tacticalshot:BAAALgADCggJFgAAAA==.Taerielle:BAAALgAECgEJAQAAAA==.Tageren:BAAALgADCgMJAwAAAA==.Taldim:BAAALgAECgMJBgABLgAECggJIQAXADkhAA==.Tarecgosa:BAAALgAECgMJBwAAAA==.Tarhos:BAAALgADCgcJCQAAAA==.Tarò:BAACLgAFFH8JAAIaAAUJXAZlCAASAQAaAAUJXAZlCAASAQAuAAQKfygAAhoACQllDUAeAO0BABoACQllDUAeAO0BAAAA.Tazark:BAAALgAECgQJCwABLgAECggJKgALAHQbAA==.Tazmoden:BAAALgADCgUJBQAAAA==.',
Te='Teacupps:BAACLgAFFH8MAAMZAAQJkw8XJADzAAAZAAMJXxIXJADzAAAgAAIJAwvwFABVAAAuAAQKfyAAAyAACQmJGX8cAGoBABkABwlGFz9RANQBACAABQkcGn8cAGoBAAAA.Teatree:BAAALgADCgUJBQABLgAECggJGwAEABkTAA==.Telvissra:BAACLgAFFH8FAAINAAMJ+hdUMgD9AAANAAMJ+hdUMgD9AAAuAAQKfycAAg0ACQmzHeURACsCAA0ACQmzHeURACsCAAAA.Tempesta:BAAALgADCgkJCwAAAA==.Tempyst:BAAALgAECgYJDAAAAA==.Tens:BAAALgAECgIJAgAAAA==.Teoritta:BAABLgAECn8jAAMZAAgJTxmJQAAMAgAZAAgJTxmJQAAMAgAgAAIJJhYvTwCAAAAAAA==.Terminus:BAAALgADCgkJCQABLgAECgcJFwAFABIiAA==.Terrisher:BAABLgAECn8WAAIBAAYJwAjZYwDrAAABAAYJwAjZYwDrAAAAAA==.',
Th='Thal:BAAALgADCgYJBgAAAA==.Thalja:BAAALgAECgQJBAAAAA==.Thenezar:BAAALgAECgYJEAAAAA==.Theodore:BAAALgAECgUJBQAAAA==.Thermopalea:BAAALgAECgMJBgAAAA==.Thi:BAAALgAECgYJBwAAAA==.Thorald:BAABLgAECn8XAAIbAAcJSARpKAABAQAbAAcJSARpKAABAQAAAA==.Thorggon:BAAALgAECgYJDgABLgAECgcJEQAWAAAAAA==.Thornbeast:BAABLgAECn8eAAIUAAcJFwq7DwC+AAAUAAcJFwq7DwC+AAAAAA==.Thttrashtank:BAAALgADCgEJAQAAAA==.Thunderbuns:BAAALgADCgMJAwAAAA==.Thundermayne:BAAALgAECgQJBQAAAA==.Thád:BAABLgAECn8eAAIUAAgJmBjnBADIAQAUAAgJmBjnBADIAQAAAA==.',
Ti='Tinisilber:BAAALgAFFAIJAgAAAA==.Tinklestein:BAEALgADCgEJAQABLgAECggJGQANADsdAA==.',
To='Tokedaddy:BAAALgAECgQJBgAAAA==.Tokemaster:BAAALgAECgEJAQAAAA==.Toxique:BAAALgAECgYJDwAAAA==.',
Tr='Travelocitee:BAAALgADCggJDgABLgAECgcJCgAWAAAAAA==.Tresor:BAAALgADCgYJBgAAAA==.Trkstir:BAAALgAECgYJCAAAAA==.Trojanhorse:BAAALgADCggJDgAAAA==.Tromaz:BAAALgADCgUJBgAAAA==.Tronshandbag:BAAALgAECgEJAQAAAA==.Truepatriot:BAACLgAFFH8FAAIYAAMJzg39EgDbAAAYAAMJzg39EgDbAAAuAAQKfyAAAxgACAlUGmUsANQBABgABwmKGWUsANQBAAIAAglDGY01AG8AAAAA.Trustissues:BAAALgAECgUJBgAAAA==.Try:BAACLgAFFH8bAAMmAAcJfx8TAACrAQAmAAYJGCMTAACrAQAJAAEJgQ3FHwBXAAAuAAQKfyEAAiYACQkBJkoAANADACYACQkBJkoAANADAAAA.Trybu:BAACLgAFFH8JAAIeAAQJMw+hOgDpAAAeAAQJMw+hOgDpAAAuAAQKfzoAAx4ACQn9H0AHAMQCAB4ACQn9H0AHAMQCACgAAgmzHQUKAKgAAAAA.Tryiss:BAAALgAECgUJDgAAAA==.',
Ts='Tsarimea:BAAALgAECgYJDgAAAA==.',
Tt='Ttryss:BAAALgAECgYJCwAAAA==.',
Tu='Tubslumpkin:BAAALgAECgEJAgAAAA==.Tuketu:BAABLgAECn8nAAIVAAgJIgtPFQBYAQAVAAgJIgtPFQBYAQAAAA==.Tumbleweed:BAAALgADCgcJBwAAAA==.Turtlelord:BAABLgAECn8UAAIZAAYJ1hJjbAC0AAAZAAYJ1hJjbAC0AAAAAA==.',
Tw='Twistediron:BAAALgADCgQJBQAAAA==.',
Ty='Tylendal:BAABLgAECn8ZAAILAAgJixGDDgCjAQALAAgJixGDDgCjAQAAAA==.Tylenols:BAAALgAECgUJCAAAAA==.Tylenolz:BAAALgAECgMJAwAAAA==.Tylenulz:BAAALgAECgMJAwAAAA==.Tylheras:BAAALgAECgYJEAAAAA==.Tyliera:BAAALgADCgcJDAAAAA==.Tylvarion:BAAALgADCgEJAQAAAA==.Typhinnia:BAAALgADCgcJCwAAAA==.Tyrlizard:BAAALgADCgMJAwABLgAECgcJFQAkAJUiAA==.Tyyraant:BAAALgADCgYJBgAAAA==.',
['Tä']='Tämer:BAAALgAECgIJAgABLgAECggJHgAhAIIaAA==.',
Ui='Uinen:BAAALgADCgYJBgAAAA==.',
Un='Uncrune:BAAALgADCgYJBgAAAA==.Unfleshed:BAAALgAECgMJAwAAAA==.Unholyy:BAAALgAECgEJAQAAAA==.Unseencrow:BAAALgADCgYJBgAAAA==.',
Ur='Urnotpreped:BAAALgADCgMJBAAAAA==.',
Va='Vakyu:BAAALgAECgQJBwAAAA==.Valizari:BAAALgADCgEJAQABLgAECggJHQABAF8aAA==.Valrian:BAAALgAECgYJCgAAAA==.Valtaran:BAAALgAECgQJBQAAAA==.Valtarr:BAABLgAECn8ZAAIHAAgJUhq4FQDkAQAHAAgJUhq4FQDkAQAAAA==.Vampirism:BAABLgAECn8cAAIXAAcJuxdBDABNAQAXAAcJuxdBDABNAQAAAA==.Vanadis:BAAALgADCgYJBgAAAA==.Varcius:BAABLgAECn8aAAMLAAYJ/Q6fHAAaAQALAAYJ/Q6fHAAaAQAMAAIJsxBFGQBzAAAAAA==.Varik:BAAALgAECgMJAwAAAA==.Vaulthunter:BAABLgAECn8YAAMFAAYJRRNALQAvAQAFAAYJRRNALQAvAQAOAAEJsQf+dwAsAAAAAA==.Vaylz:BAAALgAECgYJBgABLgAECgkJIAAeAEQKAA==.',
Ve='Vehemenz:BAAALgAECgQJBwAAAA==.Velatha:BAAALgAFFAEJAQABLgAFFAIJAgAWAAAAAA==.Velcro:BAAALgADCgIJAgAAAA==.Vellarel:BAAALgAECgMJCQAAAA==.Veloril:BAAALgAECgMJBgAAAA==.Veritana:BAAALgAECgEJAQAAAA==.Verzy:BAAALgAECgQJBQAAAA==.Vespidae:BAAALgAECgYJBgAAAA==.Vezahk:BAAALgADCgcJCgAAAA==.',
Vi='Vidu:BAABLgAECn8hAAMjAAgJZRgHCQDqAQAjAAgJZRgHCQDqAQASAAYJQg9YNAAgAQAAAA==.Vivitrix:BAAALgAECgQJBQAAAA==.Viví:BAACLgAFFH8JAAIeAAMJPgjxOQDsAAAeAAMJPgjxOQDsAAAuAAQKfy4AAh4ACQn8FgofAPIBAB4ACQn8FgofAPIBAAAA.',
Vo='Vorayus:BAAALgADCggJEAAAAA==.Vordis:BAAALgADCgkJCQABLgAECggJEwAWAAAAAA==.Voxis:BAAALgADCgUJBgAAAA==.Voøid:BAABLgAECn8WAAIFAAkJGCL/AgDOAgAFAAkJGCL/AgDOAgAAAA==.',
Vu='Vulchan:BAAALgADCgEJAQAAAA==.Vulpis:BAAALgADCgkJCQAAAA==.',
Vv='Vv:BAAALgADCgIJAgAAAA==.',
Vy='Vyrstal:BAAALgADCgEJAQABLgAECgkJIAAeAEQKAA==.',
Wa='Walberg:BAAALgADCgkJCQAAAA==.Wardan:BAABLgAECn8WAAMbAAYJsQpYJAAZAQAbAAYJRwlYJAAZAQAEAAEJ+AvMSwAlAAAAAA==.Wargisao:BAAALgAECggJEwAAAA==.',
We='Weavile:BAABLgAECn8oAAMSAAkJARbRDwBcAgASAAgJhRjRDwBcAgAjAAgJGhc6FgA3AgAAAA==.Wef:BAAALgAECgMJAwAAAA==.Weirdtotem:BAABLgAECn8jAAMIAAgJfyFKCADwAgAIAAgJfyFKCADwAgAmAAEJygbHLQAvAAAAAA==.Westylad:BAABLgAECn8jAAIbAAgJ2CR5AQDwAgAbAAgJ2CR5AQDwAgAAAA==.',
Wh='Whartonius:BAAALgAECgMJAwAAAA==.Whatthefunk:BAAALgADCgYJBgAAAA==.Whohitme:BAAALgAECgMJBAAAAA==.',
Wi='Widebodycast:BAAALgADCgEJAQABLgAECggJHgAGAIMYAA==.Winfreya:BAAALgAECgYJBgAAAA==.Winters:BAACLgAFFH8FAAIeAAMJkwwVNwD3AAAeAAMJkwwVNwD3AAAuAAQKfx0AAh4ACQkEGcVGAGMCAB4ACQkEGcVGAGMCAAAA.Wirechaser:BAAALgADCgEJAQAAAA==.',
Wu='Wubalubadbdb:BAAALgADCgIJAgAAAA==.',
Xa='Xad:BAAALgADCgMJAwAAAA==.Xanesin:BAAALgAECgQJBAAAAA==.Xanlein:BAAALgADCgcJDAAAAA==.Xannaa:BAAALgAECgMJAwAAAA==.Xantcha:BAAALgAECgMJAwAAAA==.Xaralla:BAAALgADCgUJBQAAAA==.',
Xe='Xenovira:BAAALgADCgUJBQAAAA==.',
Xr='Xrystal:BAABLgAECn8gAAIeAAkJRArcigC8AQAeAAkJRArcigC8AQAAAA==.',
Xu='Xujian:BAAALgAECgYJDgAAAA==.',
Ya='Yakiki:BAACLgAFFH8eAAISAAYJdSLpAABdAgASAAYJdSLpAABdAgAuAAQKfyEAAxIACQlSJf0AAKUDABIACQlSJf0AAKUDACMABAmKF/FFAP4AAAAA.',
Yo='Yorshkaa:BAAALgAECgMJAwAAAA==.',
Yu='Yuma:BAAALgAECgYJBgABLgAECgYJDgAWAAAAAA==.',
['Yë']='Yëët:BAAALgAECggJCQABLgAECgYJEAAWAAAAAA==.',
Za='Zalee:BAAALgAECgQJCwAAAA==.Zalen:BAABLgAECn8dAAMJAAYJSxaBHgAkAQAJAAYJSxaBHgAkAQAIAAEJIw8DYgAxAAAAAA==.Zaose:BAABLgAECn8WAAIBAAYJ/g+bRwAzAQABAAYJ/g+bRwAzAQAAAA==.Zappylad:BAAALgAECgEJAgAAAA==.Zarine:BAAALgADCgMJAwAAAA==.Zartrack:BAAALgADCgQJBAAAAA==.Zaruia:BAAALgAECgYJDQAAAA==.Zaster:BAAALgAECgEJAwAAAA==.',
Ze='Zeichan:BAAALgAECgYJBgAAAA==.Zelrath:BAAALgADCgYJBgABLgAECgQJDgAWAAAAAA==.Zevarya:BAAALgAECgIJAgAAAA==.Zevronso:BAAALgADCgIJAgABLgAECggJHQAJAOMhAA==.',
Zi='Ziluna:BAAALgAECgEJAQAAAA==.Zimaquibi:BAAALgADCgMJAwAAAA==.Zire:BAAALgADCgEJAQAAAA==.',
Zo='Zoltun:BAAALgADCgcJCQAAAA==.Zonksdruid:BAAALgAECgYJEgAAAA==.Zonksmoose:BAAALgAECgEJAQAAAA==.Zonkspaladin:BAABLgAECn8jAAIYAAgJ6BIIGgB8AQAYAAgJ6BIIGgB8AQAAAA==.Zornac:BAAALgAECgYJEwAAAA==.',
Zu='Zugzugkiller:BAACLgAFFH8GAAINAAMJewTDPgDQAAANAAMJewTDPgDQAAAuAAQKfxMAAg0ABwknFH1nANQAAA0ABwknFH1nANQAAAAA.Zumiez:BAAALgAECgEJAQAAAA==.Zunova:BAAALgAECgEJAgAAAA==.Zurä:BAAALgAECgQJBAAAAA==.',
Zy='Zykxoz:BAAALgAECgYJCgAAAA==.Zynskie:BAABLgAECn8WAAIMAAgJYxnWAwBKAgAMAAgJYxnWAwBKAgAAAA==.',
['Êc']='Êclîpsê:BAAALgAECgMJAgAAAA==.Êclïpsê:BAAALgAECgMJAwAAAA==.',
['Îm']='Îmmortal:BAABLgAECn8eAAIhAAgJghpOBgAUAgAhAAgJghpOBgAUAgAAAA==.',
['ßl']='ßluechew:BAAALgADCgUJBQABLgAECgYJEAAWAAAAAA==.',
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
