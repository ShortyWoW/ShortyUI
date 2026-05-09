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

local lookup = {'Paladin-Retribution','DeathKnight-Unholy','Unknown-Unknown','Paladin-Protection','Hunter-Survival','Warlock-Destruction','Warlock-Demonology','Warrior-Protection','DemonHunter-Devourer','Hunter-Marksmanship','Hunter-BeastMastery','Mage-Frost','Shaman-Restoration','Shaman-Elemental','Druid-Balance','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Priest-Shadow','Priest-Holy','DemonHunter-Havoc','Druid-Feral','Monk-Brewmaster','Warrior-Arms','Monk-Mistweaver','Druid-Restoration','Druid-Guardian','DeathKnight-Blood','Paladin-Holy','Warlock-Affliction','Shaman-Enhancement','Warrior-Fury','Priest-Discipline','DeathKnight-Frost','Mage-Arcane','Rogue-Subtlety','Monk-Windwalker','DemonHunter-Vengeance','Rogue-Assassination','Rogue-Outlaw','Mage-Fire',}
local provider = {region='US',realm='Windrunner',name='US',type='weekly',zone=46,date='2026-05-08',data={Ac='Acari:BAAALgADCgcJBwAAAA==.Actionjaxson:BAABLgAECn8pAAIBAAgJhSRJBgDpAgABAAgJhSRJBgDpAgAAAA==.',
Ad='Adiais:BAAALgAECgEJBAABLgAFFAIJCQACACImAA==.Admiration:BAAALgADCgkJCQAAAA==.Admore:BAAALgAECgUJEgAAAA==.',
Ae='Aeriith:BAAALgAFFAEJAQAAAA==.Aethmourne:BAAALgADCgEJAQABLgAECgEJAgADAAAAAA==.',
Ag='Agameden:BAABLgAECn8aAAIEAAYJcSAuCQC0AQAEAAYJcSAuCQC0AQAAAA==.Agogg:BAAALgAECgQJBwAAAA==.Agronak:BAAALgADCgEJAQAAAA==.',
Ai='Aishi:BAAALgAECgcJEgAAAA==.',
Ak='Akadiak:BAABLgAECn8jAAIFAAkJlhUrCgA4AgAFAAkJlhUrCgA4AgAAAA==.Akigi:BAAALgAECgEJAQAAAA==.Akitsuki:BAAALgAECgIJAwAAAA==.',
Al='Albertenzyme:BAAALgAECgEJAQAAAA==.Alivron:BAABLgAECn8VAAMGAAgJiQ5fCgAwAQAHAAgJ0AWGUQA2AQAGAAYJWRNfCgAwAQAAAA==.Alko:BAAALgAECgMJAwABLgAECggJIAAIAIkhAA==.Alkoren:BAAALgAECgMJBgABLgAECggJIAAIAIkhAA==.Alkorin:BAABLgAECn8gAAIIAAgJiSFPAwCXAgAIAAgJiSFPAwCXAgAAAA==.Allestra:BAABLgAECn8lAAIJAAgJaR0lDwBNAgAJAAgJaR0lDwBNAgAAAA==.',
Am='Amanojaku:BAAALgADCgQJBAAAAA==.Amarilis:BAAALgAECgYJCwAAAA==.Amarÿah:BAAALgADCgMJAgAAAA==.Amethcrow:BAACLgAFFH8GAAIKAAIJiRHAEgCVAAAKAAIJiRHAEgCVAAAuAAQKfxgAAgoACAnTHQAVAIsCAAoACAnTHQAVAIsCAAAA.Amoxil:BAABLgAECn8WAAIBAAYJ4RtdhgBtAQABAAYJ4RtdhgBtAQAAAA==.',
An='Anasztaizia:BAAALgAECgYJEQAAAA==.Andarrathan:BAAALgADCgQJBAAAAA==.Andurael:BAAALgAECgcJCQAAAA==.Andwin:BAAALgADCgkJCQAAAA==.Angarock:BAAALgAECgcJEQAAAA==.Angelclaw:BAABLgAECn8cAAILAAgJcQwgMwCBAQALAAgJcQwgMwCBAQAAAA==.Angora:BAAALgAECgUJCgAAAA==.Animussadow:BAAALgADCgEJAQAAAA==.Anorah:BAABLgAECn8VAAIMAAYJORTxhQAGAQAMAAYJORTxhQAGAQAAAA==.Anunitu:BAABLgAECn8kAAMNAAgJkxAGKwBtAQANAAgJkxAGKwBtAQAOAAIJ8AkgfABUAAAAAA==.',
Ao='Aoibheann:BAABLgAECn8WAAIPAAYJiwTtOACmAAAPAAYJiwTtOACmAAAAAA==.',
Aq='Aqualeta:BAAALgADCgEJAgAAAA==.',
Ar='Arath:BAACLgAFFH8GAAMQAAMJoAgqJQDOAAAQAAMJ1QYqJQDOAAARAAEJuA18BwBSAAAuAAQKfyQABBEACAnoFVQDAOoBABEACAkwFVQDAOoBABAABgnJDzk5AA8BABIAAwlxBOo9AHwAAAAA.Arazuren:BAAALgADCgEJAQABLgAFFAMJCQACADkcAA==.Arcath:BAAALgADCgkJCQAAAA==.Archegonia:BAAALgADCgcJDAAAAA==.Arcona:BAABLgAECn8RAAMTAAYJmB0fEgC3AQATAAYJmB0fEgC3AQAUAAQJMw3EZgCSAAAAAA==.Arslette:BAAALgADCgkJFAAAAA==.Artemîs:BAAALgADCgUJBgAAAA==.Arthuel:BAAALgADCgQJBgAAAA==.Arthus:BAABLgAECn8ZAAICAAYJOhgMWwAwAQACAAYJOhgMWwAwAQAAAA==.Arynkyr:BAAALgADCgIJAgAAAA==.',
As='Asar:BAAALgAECgMJCgAAAA==.Ashora:BAAALgADCgYJCQAAAA==.Aspun:BAAALgADCgEJAQAAAA==.Astora:BAABLgAECn8hAAMJAAgJCCHYCQCKAgAJAAgJCCHYCQCKAgAVAAEJAABYagA9AAAAAA==.Astralis:BAAALgADCgMJAwAAAA==.',
At='Atherasil:BAAALgADCgYJDQAAAA==.Athuzad:BAAALgAECgcJEAAAAA==.',
Au='Audie:BAAALgAECgEJAQAAAA==.Auquroe:BAAALgADCggJDgAAAA==.Aurelìa:BAAALgADCgMJAwAAAA==.Auroraalysia:BAABLgAECn8cAAILAAcJ/SGkEABPAgALAAcJ/SGkEABPAgAAAA==.Auroran:BAAALgAECgQJCwAAAA==.Autumnmoon:BAABLgAECn8lAAIWAAgJAg33CgBtAQAWAAgJAg33CgBtAQAAAA==.',
Av='Avaarion:BAAALgADCgEJAQAAAA==.Avalotus:BAAALgAECgYJCAAAAA==.Avrilenv:BAAALgAECgUJCgAAAA==.Avä:BAAALgADCgEJAQAAAA==.',
Ay='Ayeroh:BAABLgAECn8cAAIXAAYJrho2FwB+AQAXAAYJrho2FwB+AQAAAA==.Ayhika:BAACLgAFFH8RAAINAAUJZCHHAwDjAQANAAUJZCHHAwDjAQAuAAQKfxYAAg0ACAkgIfQKAM4CAA0ACAkgIfQKAM4CAAAA.',
Az='Azehyrus:BAACLgAFFH8JAAIBAAMJJSLpEAAeAQABAAMJJSLpEAAeAQAuAAQKfyQAAgEACAkcJqUGAGUDAAEACAkcJqUGAGUDAAEuAAUUBQkWABgA7iUA.Azhenhydra:BAAALgADCggJCAAAAA==.Azkabras:BAAALgADCgkJCQABLgAECggJJwAOALwYAA==.',
Ba='Baddiebrat:BAAALgAECgkJBgAAAA==.Badoink:BAAALgADCgUJBQABLgAECggJHgAZAGojAA==.Baggedmilk:BAAALgADCgcJBwAAAA==.Baidin:BAAALgAECgMJAwAAAA==.Balorous:BAABLgAECn8fAAQaAAgJhRkHKwAFAgAaAAgJhRkHKwAFAgAbAAUJcxWPEQDuAAAPAAIJbweccgBXAAAAAA==.Bansheelen:BAAALgAECgYJBgABLgAECgYJGQABACoiAA==.Bansheetrack:BAAALgADCgYJCwABLgAECgYJGQABACoiAA==.Banthis:BAABLgAECn8iAAIJAAcJmBxGIADHAQAJAAcJmBxGIADHAQAAAA==.Barbarus:BAAALgAECgcJCwAAAA==.Bareclaw:BAAALgADCgYJBgAAAA==.Barillios:BAAALgAECgQJBAAAAA==.Barkcamon:BAABLgAECn8WAAIZAAYJfhrcFgCeAQAZAAYJfhrcFgCeAQAAAA==.Barthelo:BAABLgAECn8pAAIcAAgJRCEdBAB/AgAcAAgJRCEdBAB/AgAAAA==.Battlebeastt:BAAALgADCgYJBgAAAA==.',
Be='Beardedwiz:BAAALgADCgcJDwAAAA==.Beardhero:BAACLgAFFH8GAAIdAAQJHBAbEgAjAQAdAAQJHBAbEgAjAQAuAAQKfzQAAh0ACQmRIVACADADAB0ACQmRIVACADADAAAA.Beardrood:BAAALgADCgYJAwAAAA==.Beastylad:BAAALgAECgYJEAAAAA==.Bekahsama:BAAALgAECgQJDwAAAA==.Beld:BAAALgADCgcJFgAAAA==.Beldaran:BAABLgAECn8WAAMNAAYJCxoIKgBzAQANAAYJCxoIKgBzAQAOAAEJTRYDgQBEAAAAAA==.Bellabubbles:BAABLgAECn8XAAIBAAYJhQxqcgAIAQABAAYJhQxqcgAIAQAAAA==.Belladawna:BAABLgAECn8kAAMeAAgJ2Q5UCAAZAQAHAAgJpQnRUgAzAQAeAAUJhQ5UCAAZAQAAAA==.Belldândy:BAAALgAECgMJBAAAAA==.Bennder:BAAALgAECgQJCAABLgAECggJDAADAAAAAA==.Beoffended:BAAALgAECgEJAwAAAA==.Bernal:BAABLgAECn8VAAIIAAYJLCLFCADsAQAIAAYJLCLFCADsAQAAAA==.',
Bh='Bhature:BAAALgADCgYJCwAAAA==.',
Bi='Bidtiddiedot:BAAALgADCgEJAQAAAA==.Bigmapletree:BAABLgAECn8kAAIUAAcJVRluEwDAAQAUAAcJVRluEwDAAQAAAA==.Bigpumper:BAAALgADCgIJAgABLgAFFAYJFAAOAA0gAA==.Bigsteppah:BAAALgAECgUJCQAAAA==.Bigëmu:BAAALgAECgQJBwAAAA==.Bingbängpow:BAAALgAECgkJBQAAAA==.',
Bl='Blackblader:BAAALgAECgUJEgAAAA==.Bladekraft:BAAALgADCgUJCAAAAA==.Bladrick:BAAALgADCgEJAQAAAA==.Blindndumb:BAAALgADCgIJAgAAAA==.Blondeshaman:BAAALgAECgUJBQABLgAFFAUJEAANAKkNAA==.',
Bo='Boarggon:BAAALgAECgUJBQABLgAECgcJEQADAAAAAA==.Boggart:BAAALgAECgQJBAAAAA==.Bonk:BAAALgAECgQJCAAAAA==.Bonkboi:BAAALgAECgUJCAAAAA==.Bonkitty:BAAALgADCgcJDgAAAA==.Bonku:BAAALgADCgcJCwAAAA==.Bonnie:BAAALgAECgQJBQAAAA==.Bonnéy:BAAALgADCgYJCQABLgAECgUJCAADAAAAAA==.Boog:BAAALgADCgEJAQAAAA==.Borealus:BAAALgAECggJEAAAAA==.Bowl:BAAALgAECgUJCQAAAA==.',
Br='Bratakk:BAAALgAECggJCwAAAA==.Brillina:BAAALgAECgYJBgAAAA==.Bris:BAABLgAECn8oAAIaAAgJFBGVKwB6AQAaAAgJFBGVKwB6AQAAAA==.Brubdy:BAAALgAECgYJBgAAAA==.Bruby:BAABLgAECn8UAAMfAAgJEBHRBwCwAQAfAAcJfw/RBwCwAQAOAAYJuA3dPwBLAQAAAA==.Brugamen:BAABLgAECn8iAAIgAAkJjxTqDwD3AQAgAAkJjxTqDwD3AQAAAA==.Brugg:BAAALgADCgYJBgABLgAECgkJIgAgAI8UAA==.Bruhg:BAAALgAECgQJBAABLgAECgkJIgAgAI8UAA==.Bruugg:BAAALgADCgEJAQABLgAECgkJIgAgAI8UAA==.Brád:BAABLgAECn8nAAIhAAgJoB2UBADJAgAhAAgJoB2UBADJAgAAAA==.',
Bu='Bubdly:BAAALgAECgQJCAAAAA==.Bumdiddly:BAAALgAECgMJAwAAAA==.Bunnylajoya:BAAALgADCgcJBwAAAA==.Burntha:BAAALgAECgEJAQAAAA==.',
['Bä']='Bäldur:BAABLgAECn8oAAIiAAgJjhX5AwC9AQAiAAgJjhX5AwC9AQAAAA==.',
Ca='Cainan:BAAALgAECgUJBgAAAA==.Calestel:BAAALgAECgQJBgAAAA==.Captinblye:BAAALgADCgEJAQAAAA==.Carmelita:BAABLgAECn8cAAIHAAYJfAWMdgDbAAAHAAYJfAWMdgDbAAAAAA==.Caroweaven:BAAALgADCgcJFAAAAA==.Cassienne:BAABLgAECn8oAAIOAAgJaREIGwB2AQAOAAgJaREIGwB2AQAAAA==.Catpounce:BAAALgADCgkJGgAAAA==.',
Ce='Cedaver:BAABLgAECn8pAAMgAAgJch4wCQBVAgAgAAgJch4wCQBVAgAYAAEJ9RdaNgBHAAAAAA==.Cellphoneguy:BAABLgAECn8kAAMdAAgJXA4SJQBhAQAdAAcJXgsSJQBhAQABAAcJ5Q2hZAAkAQAAAA==.Celtigar:BAAALgAECgQJDAAAAA==.',
Ch='Chaan:BAABLgAECn8gAAMNAAgJPx3RDwBBAgANAAgJPx3RDwBBAgAOAAQJHQYgbgCKAAAAAA==.Chaddicus:BAAALgAECgEJAQAAAA==.Chaitea:BAAALgADCgQJBAAAAA==.Chamael:BAAALgAECgQJBwAAAA==.Champo:BAAALgAECgEJAQAAAA==.Chance:BAAALgADCgYJBgAAAA==.Chereth:BAABLgAECn8VAAIaAAYJzheHJwCSAQAaAAYJzheHJwCSAQAAAA==.Cherwin:BAAALgADCgQJBAAAAA==.Cheshire:BAABLgAECn8vAAIFAAkJnxxSAwClAgAFAAkJnxxSAwClAgAAAA==.Chiers:BAAALgAECgUJCAAAAA==.Chikkaboom:BAAALgAECggJDAAAAA==.Chillhawg:BAAALgAECgEJAQAAAA==.Chionee:BAAALgADCgEJAQAAAA==.Chiweave:BAAALgAECgYJDQAAAA==.Chlorin:BAAALgAECggJDgAAAA==.Chocolate:BAACLgAFFH8MAAIMAAYJwxBiJgBcAQAMAAYJwxBiJgBcAQAuAAQKfxQAAwwACAmwHLJZACwCAAwACAl2GrJZACwCACMABAljFwwNAPoAAAAA.Chucklehead:BAAALgADCgkJDgAAAA==.Chumchum:BAAALgAECggJEAAAAA==.Chunala:BAAALgADCgcJFgABLgAECgYJFgAcAP4PAA==.',
Ci='Cirah:BAAALgAECgMJAwAAAA==.Ciro:BAAALgADCgIJAgAAAA==.Cityofrivers:BAABLgAECn8YAAMfAAgJ8A0vCQCMAQAfAAgJgA0vCQCMAQAOAAUJOQ2sUgD7AAAAAA==.',
Cl='Classyfied:BAABLgAECn8kAAIZAAgJcCFABADhAgAZAAgJcCFABADhAgAAAA==.Clennse:BAAALgADCgYJCAAAAA==.Clickbait:BAAALgAECgUJBQAAAA==.Clob:BAAALgAFFAEJAgAAAA==.Cloudcrasher:BAABLgAECn8eAAMgAAgJZx83CABoAgAgAAgJZx83CABoAgAYAAIJTRIXLwB9AAAAAA==.Cloudsayer:BAAALgADCgcJDQAAAA==.Cloudseeker:BAAALgADCgUJBQAAAA==.Cloudspeaker:BAAALgAECgYJCwAAAA==.',
Co='Coldblades:BAAALgAECgEJAQAAAA==.Coldblow:BAABLgAECn8ZAAIEAAgJmBHOCwCAAQAEAAgJmBHOCwCAAQAAAA==.Coldfrostshk:BAAALgAECgIJAgAAAA==.Coldslayer:BAABLgAECn8pAAILAAgJax3BDgBiAgALAAgJax3BDgBiAgAAAA==.Coldtwoblade:BAAALgAECgEJAQAAAA==.Coradane:BAAALgAECgQJBAAAAA==.Corbeau:BAAALgADCgkJCgAAAA==.Cordorana:BAAALgAECgQJBAAAAA==.Coronax:BAAALgADCgEJAQAAAA==.Cosetti:BAAALgADCgQJBAAAAA==.',
Cr='Craazypete:BAAALgADCgEJAQAAAA==.Crackzap:BAABLgAECn8VAAIHAAkJjRFyTwDaAQAHAAkJjRFyTwDaAQAAAA==.Crazyrd:BAABLgAECn8cAAIGAAcJww3fCgAnAQAGAAcJww3fCgAnAQAAAA==.Crittydps:BAAALgADCgEJAQAAAA==.Crocs:BAAALgADCgcJDwABLgAECgcJFAABAP8fAA==.Crotgustus:BAAALgADCgIJAgABLgAFFAIJAgADAAAAAA==.Crummbly:BAAALgAECgQJCAAAAA==.Crìtorís:BAAALgADCgcJFgAAAA==.',
Ct='Ctrlc:BAAALgAECgMJAwAAAA==.Ctrlshot:BAAALgAECgcJEAABLgAECgkJBQADAAAAAA==.',
Cu='Cursedsoulz:BAAALgADCgUJBQAAAA==.',
Cy='Cyber:BAAALgAECgEJAQAAAA==.Cyndelle:BAAALgAECgUJDwAAAA==.Cyndro:BAAALgAECgYJEwAAAA==.Cyntaria:BAABLgAECn8cAAIaAAYJ7QVzUwDJAAAaAAYJ7QVzUwDJAAAAAA==.',
Da='Daelith:BAAALgAECgEJAQABLgAECgEJAgADAAAAAA==.Dafrostmon:BAAALgAECgQJBwABLgAECgYJDgADAAAAAA==.Dagardugg:BAAALgAECgEJAQAAAA==.Dajmibuzi:BAABLgAECn8jAAIJAAgJkxTRKQCSAQAJAAgJkxTRKQCSAQAAAA==.Dalari:BAAALgADCgYJBwAAAA==.Danamor:BAABLgAECn8hAAIBAAgJIhOVLwC+AQABAAgJIhOVLwC+AQAAAA==.Dandanx:BAAALgAECgQJBQAAAA==.Darciaa:BAABLgAECn8UAAIkAAcJUQ6nKAC1AQAkAAcJUQ6nKAC1AQAAAA==.Dariann:BAAALgAECgQJBAAAAA==.Darkladÿ:BAAALgAECgUJCgAAAA==.Darnel:BAABLgAECn8pAAIEAAgJMBr2BQALAgAEAAgJMBr2BQALAgAAAA==.Darnokk:BAAALgAECgYJEwAAAA==.Darrek:BAAALgADCgMJAwAAAA==.Darthvenom:BAAALgADCggJCQAAAA==.Dawnshield:BAABLgAECn8ZAAIBAAYJKiKhJADwAQABAAYJKiKhJADwAQAAAA==.',
De='Deathbyfel:BAAALgAECgEJAQABLgAECggJIwAOAAkiAA==.Deathbyshock:BAABLgAECn8jAAIOAAgJCSKJCgAxAgAOAAgJCSKJCgAxAgAAAA==.Deathstrokee:BAAALgAECgEJBQAAAA==.Deceez:BAAALgADCgUJBQABLgAECgYJGgAJAGgiAA==.Dedlok:BAAALgADCgIJAgAAAA==.Delgiadamar:BAAALgADCgMJAwAAAA==.Demoncelt:BAABLgAECn8bAAIbAAgJhg7yDQAqAQAbAAgJhg7yDQAqAQAAAA==.Demongotha:BAAALgADCgcJBwAAAA==.Demovaj:BAAALgAECgYJDQAAAA==.Demulos:BAAALgADCgYJCAAAAA==.Denarror:BAAALgADCgEJAQAAAA==.Denrukhan:BAABLgAECn8tAAQPAAkJ3CEcCAAUAwAPAAkJ3CEcCAAUAwAaAAgJXCEEDACKAgAWAAIJRxeEKACJAAAAAA==.Deschain:BAAALgAECgQJCwAAAA==.Dewert:BAAALgAECgQJBAAAAA==.',
Di='Diin:BAABLgAECn8aAAIMAAgJ0AUlZwBDAQAMAAgJ0AUlZwBDAQAAAA==.Dillypoo:BAAALgADCgEJBAAAAA==.',
Dj='Djinger:BAAALgADCgUJBQAAAA==.',
Dk='Dklord:BAAALgAECggJEQAAAA==.',
Do='Donkedixkek:BAAALgAECgQJBQAAAA==.Donkedixlol:BAAALgAECgEJAgAAAA==.Donkedixlul:BAAALgAECgEJAQAAAA==.Donkedixon:BAABLgAECn8WAAIHAAgJJiBkCwCXAgAHAAgJJiBkCwCXAgAAAA==.Doobzers:BAAALgADCgYJBwABLgAFFAMJBgAUALAIAA==.Dowe:BAAALgADCgQJBAAAAA==.Doxtoroso:BAAALgAECgYJCAAAAA==.Doxtorprote:BAABLgAECn8UAAMEAAcJqwwvGQDNAAAEAAUJ/hAvGQDNAAABAAcJZwUb/wCXAAAAAA==.',
Dr='Dracaryz:BAAALgAECgEJAQAAAA==.Dragonite:BAABLgAECn8kAAIQAAkJKBZNCgAlAgAQAAkJKBZNCgAlAgAAAA==.Dragoonred:BAABLgAECn8hAAIeAAgJfRb2AgDiAQAeAAgJfRb2AgDiAQAAAA==.Dreadknightx:BAAALgADCgEJAQAAAA==.Dreamfyre:BAAALgAECgYJDAABLgAFFAcJFgAKAJQaAA==.Dredd:BAABLgAECn8YAAIBAAYJ4ggefQDyAAABAAYJ4ggefQDyAAAAAA==.Droko:BAAALgADCgUJBQAAAA==.Drom:BAAALgADCgcJCAAAAA==.Drougoss:BAAALgAECgQJBgAAAA==.Drraxx:BAABLgAECn8hAAMaAAgJ6hGzHwDHAQAaAAgJ6hGzHwDHAQAPAAEJjQJyiAAnAAAAAA==.Drunk:BAABLgAECn8hAAQlAAgJmRQQDwDKAQAlAAgJmRQQDwDKAQAXAAYJ6gmHTgAJAQAZAAUJNA2eQQDZAAAAAA==.Drïzzt:BAAALgADCgEJAQAAAA==.',
Du='Duskshield:BAAALgAECgEJAQABLgAECgYJGQABACoiAA==.',
Ea='Earthotome:BAAALgADCgUJBQAAAA==.',
Ec='Eckshin:BAAALgAECggJEgAAAA==.',
Ed='Eddiemarz:BAAALgAECgEJAQAAAA==.Eddiezenchi:BAABLgAECn8aAAIZAAgJBAZfKAAJAQAZAAgJBAZfKAAJAQAAAA==.',
Ek='Ekateryn:BAAALgAECgEJAQAAAA==.Ekkaia:BAABLgAECn8mAAILAAgJTxqvGAALAgALAAgJTxqvGAALAgAAAA==.',
El='Eldanky:BAAALgAECgUJBgAAAA==.Elecraft:BAABLgAECn8YAAMhAAgJXxh/FAAGAgAhAAgJXxh/FAAGAgAUAAMJLBPfYgCkAAAAAA==.Eleminohpee:BAAALgAECgIJAwABLgAECggJHgAMAFseAA==.Elephant:BAACLgAFFH8NAAMUAAUJ1hndCgAbAQAhAAUJrBe0EABCAQAUAAQJgRPdCgAbAQAuAAQKfx4AAyEACQkcHgQGAOsCACEACQmDHQQGAOsCABQABQn4ElgnAA4BAAEuAAUUCQkoACEAQyAA.Elfypriestly:BAAALgADCgYJBgAAAA==.Eliminater:BAABLgAECn8XAAIaAAcJhhpiHADhAQAaAAcJhhpiHADhAQABLgAECgkJNAAHAIMeAA==.Elythe:BAAALgAECgYJDwABLgAECggJEQADAAAAAA==.',
Em='Emeralis:BAAALgAECgQJBAAAAA==.',
En='Encana:BAABLgAECn8vAAImAAkJqxJMBQC/AQAmAAkJqxJMBQC/AQAAAA==.Ender:BAAALgAECgUJDwAAAA==.Enoby:BAAALgAECgIJAQAAAA==.Enragedhïppo:BAABLgAECn8WAAIgAAYJxyArFADLAQAgAAYJxyArFADLAQAAAA==.',
Er='Erebseth:BAAALgADCgcJCgAAAA==.Erling:BAAALgADCgkJCQAAAA==.Errzza:BAAALgAECgYJEQAAAA==.Erunar:BAAALgAECgEJAwAAAA==.Eruptnghïppo:BAAALgADCgYJBgAAAA==.Eruuruu:BAABLgAECn8XAAIPAAYJIwq3LADkAAAPAAYJIwq3LADkAAAAAA==.',
Es='Eshà:BAABLgAECn8mAAINAAcJMxGHLgBZAQANAAcJMxGHLgBZAQAAAA==.',
Et='Etsupriest:BAABLgAECn8iAAITAAkJ4x/9AQAFAwATAAkJ4x/9AQAFAwAAAA==.',
Eu='Eula:BAAALgADCgQJBAAAAA==.',
Ev='Evelynn:BAAALgAECgEJAwAAAA==.',
Ex='Exelia:BAAALgADCgYJBgABLgAFFAgJIQAZANkjAA==.Exign:BAAALgAECgMJAwAAAA==.Exqui:BAABLgAECn8kAAIHAAgJ2SK4CAC6AgAHAAgJ2SK4CAC6AgAAAA==.',
Ez='Ezral:BAAALgAECgEJAgABLgAECgUJCQADAAAAAA==.Ezékiel:BAABLgAECn8dAAMEAAgJOw0QFgDuAAAEAAgJ1wkQFgDuAAABAAUJpgs80QDnAAAAAA==.',
['Eí']='Eíko:BAABLgAECn8fAAQUAAcJyBQ4IQDZAQAUAAcJvBQ4IQDZAQATAAYJ7QeePAAOAQAhAAUJBw4SNAADAQAAAA==.',
Fa='Fad:BAAALgAECgYJCwAAAA==.Fadedhope:BAAALgADCgkJFgABLgAECgcJGAAFAMEPAA==.Faelwynn:BAAALgAECgEJAQAAAA==.Fafnar:BAABLgAECn8pAAIaAAgJxRXYIgCwAQAaAAgJxRXYIgCwAQAAAA==.Fafnie:BAABLgAECn8iAAIOAAcJrgRWMgDoAAAOAAcJrgRWMgDoAAAAAA==.Fallénlegacy:BAAALgADCgYJBgABLgAECggJIAAYAPARAA==.Fan:BAAALgAECggJEAAAAA==.Faunus:BAAALgADCgcJDAAAAA==.Fauxy:BAAALgAECgUJBQAAAA==.',
Fe='Feared:BAAALgAECgIJAwAAAA==.Felath:BAABLgAECn8dAAImAAgJLB5LAgBfAgAmAAgJLB5LAgBfAgAAAA==.Feldspar:BAABLgAECn8fAAIdAAgJwRNkFADuAQAdAAgJwRNkFADuAQAAAA==.Fenyr:BAAALgAECgUJCAAAAA==.',
Fi='Fil:BAABLgAECn8dAAMlAAgJCxu3CAA1AgAlAAgJCxu3CAA1AgAXAAYJBAjULwDcAAAAAA==.Firepowr:BAAALgAECgQJBAAAAA==.Fishswife:BAAALgAECgYJDAAAAA==.Fissal:BAAALgAECgYJEwABLgAFFAIJBwAZAGwYAA==.Fistoflurry:BAAALgAECgcJEQAAAA==.Fistymisty:BAAALgADCgEJAgAAAA==.',
Fl='Flemel:BAABLgAECn8dAAMTAAYJPR0jEwCsAQATAAYJPR0jEwCsAQAhAAUJtwxgMwAIAQAAAA==.Floatingbush:BAABLgAECn8aAAIXAAcJghDXIQArAQAXAAcJghDXIQArAQAAAA==.Flompy:BAAALgAECgMJBAAAAA==.Floreil:BAAALgADCgYJEQAAAA==.Flurry:BAAALgADCgQJBAAAAA==.',
Fo='Foofighter:BAAALgADCgUJAwAAAA==.Foopy:BAABLgAECn8cAAMCAAgJlxtCJgDnAQACAAgJTxpCJgDnAQAiAAQJ4hF4DADqAAAAAA==.Footoo:BAAALgAECgYJDQAAAA==.Forestsong:BAAALgADCgIJAgABLgAECgQJDAADAAAAAA==.Foxyfife:BAAALgADCgUJBQAAAA==.',
Fr='Franksuba:BAAALgAFFAEJAQAAAA==.Fringilla:BAAALgADCgMJAwAAAA==.Frizzel:BAAALgADCgQJBAAAAA==.Frogaloger:BAAALgADCgMJAwAAAA==.Frostitutë:BAAALgAECgEJAQAAAA==.Frostydawn:BAAALgADCgMJAwAAAA==.Frostyshade:BAAALgAECgEJAQAAAA==.',
Fu='Funk:BAABLgAECn8zAAIHAAkJYh2bCAC8AgAHAAkJYh2bCAC8AgAAAA==.Futurama:BAAALgADCgcJCwAAAA==.',
Fz='Fzoul:BAABLgAECn8bAAMaAAcJ9A6cXwAzAQAaAAYJsw+cXwAzAQAPAAMJnAtZPACUAAAAAA==.',
Ga='Gabdragon:BAAALgAECgQJBAAAAA==.Gabfam:BAAALgAECgQJBgAAAA==.Gadgett:BAABLgAECn8gAAMYAAgJ8BG1CQCtAQAYAAgJ8BG1CQCtAQAgAAIJQwJWmQBcAAAAAA==.Gaiusmohiam:BAAALgAECgUJBQAAAA==.Galdademon:BAABLgAECn8XAAMJAAgJFAx0RQAoAQAJAAgJawp0RQAoAQAmAAMJkw+lHgCSAAAAAA==.Galiophobia:BAABLgAECn8bAAIdAAcJdhQxGgC4AQAdAAcJdhQxGgC4AQAAAA==.Garrethul:BAABLgAECn8TAAIMAAQJsBvQZABIAQAMAAQJsBvQZABIAQAAAA==.Gathercow:BAAALgADCgcJCgAAAA==.Gavalar:BAAALgAECgUJEQAAAA==.Gawleywood:BAABLgAECn8VAAIMAAYJmxhcUQB2AQAMAAYJmxhcUQB2AQAAAA==.',
Ge='Geist:BAAALgAECgEJAgAAAA==.Gellidus:BAABLgAECn8fAAMQAAgJrgwhHwBGAQAQAAgJ6wkhHwBGAQARAAYJcAzMDADEAAAAAA==.Genhooves:BAECLgAFFH8FAAICAAMJqBF9TwDwAAACAAMJqBF9TwDwAAAuAAQKfxwAAgIACQmKHfkNAJQCAAIACQmKHfkNAJQCAAAA.Genoesis:BAAALgADCgcJCgAAAA==.Gentleshadow:BAAALgAECgEJAQAAAA==.',
Gh='Ghenka:BAABLgAECn8UAAQLAAcJRhuVJgC5AQALAAYJRhuVJgC5AQAKAAYJ/A4uRwA3AQAFAAEJsBnhLQA7AAABLgAFFAUJFgAYAO4lAA==.Ghosteagle:BAAALgADCgcJBgAAAA==.Ghosthost:BAAALgADCgEJAQAAAA==.',
Gl='Gloomreaver:BAAALgAECgIJAwAAAA==.',
Gn='Gnarlysnarly:BAAALgADCgYJDAAAAA==.Gnomejodas:BAAALgAECgUJDgAAAA==.',
Go='Gobfather:BAAALgAECgIJAgAAAA==.Goldcity:BAACLgAFFH8NAAImAAQJBRNNAgAGAQAmAAQJBRNNAgAGAQAuAAQKfx0AAiYACQlxHLsDAJECACYACQlxHLsDAJECAAAA.Goob:BAAALgAECgQJBwAAAA==.Goodfaith:BAAALgAECgQJCAAAAA==.',
Gr='Grimlocke:BAABLgAECn8cAAMHAAgJGxEuNACUAQAHAAgJGxEuNACUAQAGAAEJAADlZQBEAAAAAA==.Gromit:BAAALgAECggJEwABLgAFFAUJDgAUANoUAA==.Grovewarden:BAAALgADCgEJAQAAAA==.',
Gu='Gug:BAAALgADCgkJCgAAAA==.Gullibull:BAABLgAECn8nAAIfAAkJWwejCACbAQAfAAkJWwejCACbAQAAAA==.',
Gw='Gwynne:BAAALgAECgYJBgAAAA==.',
['Gí']='Gírthquake:BAAALgAECgQJBQABLgAFFAEJAgADAAAAAA==.',
Ha='Halanad:BAABLgAECn8WAAIMAAYJ7wmjnADZAAAMAAYJ7wmjnADZAAAAAA==.Halcyone:BAAALgADCgUJBQAAAA==.Halfsumo:BAABLgAECn8VAAIcAAUJbRzwFgAYAQAcAAUJbRzwFgAYAQAAAA==.Halobender:BAAALgADCgkJEAAAAA==.Hamer:BAAALgADCgEJAQAAAA==.Hanamora:BAAALgADCgkJCQAAAA==.Harkonnen:BAAALgADCgYJEQAAAA==.Harmmony:BAAALgAECgQJBAABLgAECgQJCAADAAAAAA==.Hashknight:BAAALgADCgUJBQAAAA==.Hassindiir:BAABLgAECn8oAAIbAAkJOAVsFADKAAAbAAkJOAVsFADKAAAAAA==.Hawgelf:BAAALgAECgcJEAAAAA==.Hawmahcide:BAAALgAECgYJCQAAAA==.Hayles:BAAALgAECgYJEwAAAA==.',
He='Heall:BAAALgAECgEJAQAAAA==.Hecklerkoch:BAABLgAECn8rAAIBAAkJLAk5QACFAQABAAkJLAk5QACFAQAAAA==.Helathra:BAABLgAECn8UAAMBAAYJYg+ikABbAQABAAYJYg+ikABbAQAEAAMJwQfJNwBiAAAAAA==.Hellie:BAAALgAECgUJBgAAAA==.Hellmage:BAAALgADCgQJBAAAAA==.Hellward:BAAALgAECgMJAwAAAA==.Herevoker:BAAALgAECgYJCgABLgAFFAQJCgAnALESAA==.Hermaeuss:BAAALgADCgkJDQAAAA==.Herrogue:BAACLgAFFH8KAAMnAAQJsRJCAgBjAQAnAAQJsRJCAgBjAQAoAAMJqAAFBgCWAAAuAAQKfxQAAycABwnUGK4IAMEBACcABwkAGK4IAMEBACgAAwkEDG4OAG4AAAAA.',
Hi='Hishunter:BAACLgAFFH8HAAILAAQJTB2UCAB6AQALAAQJTB2UCAB6AQAuAAQKfyIAAgsACAkMIu0IAAUDAAsACAkMIu0IAAUDAAAA.',
Ho='Hobosam:BAABLgAECn8XAAMUAAYJcBIeOwBOAQAUAAYJiw8eOwBOAQAhAAUJdgfvJwDpAAAAAA==.Hollowarden:BAAALgADCgEJAgAAAA==.',
Hr='Hräfn:BAAALgADCgYJBgAAAA==.',
Hu='Huntarr:BAAALgAECgcJDgAAAA==.Hunterdamon:BAABLgAECn8hAAIJAAgJ+wj6SgAXAQAJAAgJ+wj6SgAXAQAAAA==.',
Hy='Hycinna:BAAALgAECgYJEQABLgAECgcJEAADAAAAAQ==.Hydraashen:BAABLgAECn8XAAMjAAcJzgJSCQCDAAAMAAYJyAKHCQHpAAAjAAUJVwJSCQCDAAAAAA==.Hyndrix:BAAALgADCgEJAwAAAA==.',
Ia='Iamafish:BAABLgAECn8dAAILAAgJHxtvGAANAgALAAgJHxtvGAANAgAAAA==.Iamthestorm:BAAALgADCgUJBQAAAA==.',
Ic='Iceris:BAAALgAECgEJAgAAAA==.',
In='Incendemus:BAAALgAECgEJAwAAAA==.Insidae:BAABLgAECn8vAAIkAAkJChoPBACRAgAkAAkJChoPBACRAgAAAA==.',
Ir='Iraegin:BAAALgAECgIJAQAAAA==.',
Is='Iscreamloud:BAAALgAECgQJBwAAAA==.Ismirea:BAAALgAECgMJBgAAAA==.Isoldella:BAAALgADCgkJEgAAAA==.',
It='Itsben:BAAALgADCgEJAQAAAA==.',
Ja='Jalencarter:BAACLgAFFH8HAAICAAIJNCatVQDhAAACAAIJNCatVQDhAAAuAAQKfxsAAgIACQmUJKkEABcDAAIACQmUJKkEABcDAAAA.Jamirchaman:BAAALgAECgYJCgAAAA==.Jantasir:BAABLgAECn8hAAIBAAgJxxpTKwDQAQABAAgJxxpTKwDQAQAAAA==.Jarred:BAAALgAFFAEJAQABLgAFFAEJAgADAAAAAA==.Javalyn:BAAALgAECgYJEwAAAA==.Jaydonar:BAAALgADCgkJCQAAAA==.',
Je='Jerbo:BAAALgAECgYJCgAAAA==.',
Ji='Jinda:BAAALgADCgkJJgAAAA==.',
Jo='Jobergas:BAABLgAECn8aAAMLAAYJKhFQUAAdAQALAAYJKhFQUAAdAQAKAAEJ5gErmQAcAAAAAA==.Johallas:BAABLgAECn8oAAIMAAgJKBD7PACxAQAMAAgJKBD7PACxAQAAAA==.Johnnyhotbod:BAAALgAECgQJBwAAAA==.Joleiste:BAAALgADCgYJDAAAAA==.Josrius:BAAALgAECgcJBwAAAA==.',
Ju='Juansnowe:BAAALgADCgkJCQAAAA==.Juf:BAABLgAECn8UAAMUAAcJpAccJgAZAQAUAAcJpAccJgAZAQATAAQJFwL8PACHAAAAAA==.Jufster:BAAALgADCgYJBgAAAA==.Julio:BAABLgAECn8aAAICAAcJKhqCVQDxAQACAAcJKhqCVQDxAQAAAA==.Jumpingbear:BAAALgAECggJCAAAAA==.',
Ka='Kaeir:BAAALgADCgUJBQAAAA==.Kagar:BAAALgADCgMJBAAAAA==.Kaho:BAABLgAECn8lAAIiAAkJHh+cAABGAwAiAAkJHh+cAABGAwAAAA==.Kainazzo:BAAALgADCgkJKgAAAA==.Kaladïn:BAAALgAECgMJAwAAAA==.Kalaris:BAAALgAECgYJDwAAAA==.Kalda:BAACLgAFFH8GAAIMAAMJxgUoVwC7AAAMAAMJxgUoVwC7AAAuAAQKfyYAAgwABwkVHCRkABACAAwABwkVHCRkABACAAAA.Kallisto:BAAALgAECgUJDgAAAA==.Kalthoz:BAABLgAECn8ZAAIJAAgJph7dDABnAgAJAAgJph7dDABnAgAAAA==.Kandrana:BAAALgADCgYJBgAAAA==.Karor:BAAALgAECgIJAgAAAA==.Kathrathryn:BAAALgAECgIJAgAAAA==.Kazuhiro:BAACLgAFFH8WAAMYAAUJ7iXeAQC5AQAYAAUJ7iXeAQC5AQAgAAEJaB/AHgBZAAAuAAQKf1kAAxgACQlOJWkAAFEDACAACAkqJVQFAFIDABgACQnwJGkAAFEDAAAA.',
Ke='Keagan:BAAALgAECgYJBwAAAA==.Keevah:BAAALgAECgkJDgAAAA==.Kegeratorr:BAABLgAECn8WAAMZAAYJ4yK4CQBTAgAZAAYJ4yK4CQBTAgAXAAUJLRQOJwALAQAAAA==.Keinestina:BAAALgADCggJCgAAAA==.Kekg:BAAALgADCgkJCQABLgAECggJHgAZAGojAA==.Kelric:BAAALgADCgQJBAAAAA==.Kenpomaster:BAAALgADCgIJAgAAAA==.Kerchunguss:BAAALgADCgIJAgAAAA==.Kerciel:BAAALgAECgMJAwABLgAECggJLgAQAGEdAA==.Kerebos:BAAALgADCgEJAQAAAA==.Kexin:BAAALgADCgEJAQAAAA==.',
Kh='Khaluha:BAAALgAECgQJCwAAAA==.Khaymaan:BAABLgAECn8UAAIHAAUJWQoNdwDaAAAHAAUJWQoNdwDaAAAAAA==.Khitryy:BAABLgAECn8WAAMYAAcJfR5qCQAWAgAYAAcJfR5qCQAWAgAgAAEJwxfsnQBIAAAAAA==.',
Ki='Killdorei:BAABLgAECn8aAAIJAAYJaCIcKQCVAQAJAAYJaCIcKQCVAQAAAA==.Killios:BAAALgAECgMJAwAAAA==.',
Ko='Kozal:BAAALgADCgcJEQAAAA==.',
Kr='Krabskooter:BAAALgADCgYJCQAAAA==.Krionys:BAABLgAECn8fAAIdAAcJPxz3HQAnAgAdAAcJPxz3HQAnAgAAAA==.Krisha:BAABLgAECn8dAAIOAAgJaA+IHABpAQAOAAgJaA+IHABpAQAAAA==.Krisphobos:BAABLgAECn8aAAILAAgJOg1uNQB3AQALAAgJOg1uNQB3AQAAAA==.Krugzy:BAAALgADCgQJBAAAAA==.',
Kt='Ktrevious:BAABLgAECn8fAAIMAAgJzhk7OADBAQAMAAgJzhk7OADBAQAAAA==.',
Ku='Kuang:BAAALgAECgQJBAAAAA==.Kubael:BAAALgAECgUJCQAAAA==.Kulgutbuster:BAABLgAECn8nAAILAAgJax+XDAB5AgALAAgJax+XDAB5AgAAAA==.Kungpow:BAABLgAECn8pAAMlAAgJjhosCwAHAgAlAAgJjhosCwAHAgAZAAMJXgOHSwBTAAAAAA==.Kuraash:BAAALgAECgUJCQAAAA==.Kuroken:BAAALgAECgIJAgAAAA==.Kuromatsu:BAABLgAECn8lAAIaAAgJTx/nDwBXAgAaAAgJTx/nDwBXAgAAAA==.',
Ky='Kyria:BAABLgAECn8aAAIJAAYJLwQagwCOAAAJAAYJLwQagwCOAAAAAA==.',
['Kì']='Kìngpin:BAAALgAECgcJCgABLgAECgcJGwAaAPQOAA==.',
['Kÿ']='Kÿt:BAABLgAECn8UAAIWAAYJRAxvGQAvAQAWAAYJRAxvGQAvAQAAAA==.',
La='Lacedon:BAABLgAECn8YAAIgAAgJPw0DGwCPAQAgAAgJPw0DGwCPAQAAAA==.Laissa:BAAALgADCgkJIgAAAA==.Lancerdrake:BAAALgAECgQJBwAAAA==.Laquisha:BAABLgAECn8YAAIFAAcJmR1nCgD9AQAFAAcJmR1nCgD9AQAAAA==.Larfleeze:BAAALgAECgQJBAAAAA==.Largewagon:BAAALgAECgIJBAAAAA==.Larque:BAAALgAECgYJAgABLgAECgkJBQADAAAAAA==.Larryy:BAAALgAECgIJAgAAAA==.Latronia:BAAALgAECgcJAQAAAA==.Lauriena:BAAALgADCggJCAAAAA==.',
Le='Lethaldx:BAAALgAECgQJBgAAAA==.Lettuceman:BAAALgADCgEJAQAAAA==.',
Li='Lialune:BAAALgAECgcJDwAAAA==.Liarae:BAAALgAECgQJBgABLgAFFAMJBQANAIkdAA==.Lilgup:BAAALgAECgQJBgAAAA==.Lilÿ:BAAALgADCgYJCQAAAA==.Linadrea:BAAALgADCgkJGwAAAA==.Linedaleiris:BAAALgADCgkJCQAAAA==.Liqudblu:BAAALgADCgcJCgAAAA==.Liqudfury:BAAALgAECgUJCQAAAA==.Lishan:BAABLgAECn8uAAQQAAgJYR02CABQAgAQAAgJKRw2CABQAgARAAYJpRzVDwDeAQASAAUJ3hVYJwA5AQAAAA==.Literein:BAAALgAFFAEJAQAAAA==.Lizora:BAAALgAECgEJBAAAAA==.',
Ll='Llamasmol:BAAALgADCgUJBQAAAA==.Llanfear:BAAALgADCgYJBgAAAA==.Llight:BAAALgAECgYJBgABLgAECgcJFAAQAPoeAA==.',
Lo='Lockwar:BAAALgADCgkJCQAAAA==.Locria:BAAALgAECgYJCgAAAA==.Lokki:BAABLgAECn8XAAILAAYJIwsUUwAVAQALAAYJIwsUUwAVAQAAAA==.Loreguy:BAAALgAECgYJDAAAAA==.Lorenei:BAABLgAECn8iAAICAAgJtByYFwA/AgACAAgJtByYFwA/AgAAAA==.Loriol:BAAALgADCgUJBQABLgAECgcJDgADAAAAAA==.Lorrith:BAAALgADCggJEAAAAA==.Los:BAAALgAECgYJEQAAAA==.',
Lu='Lucìd:BAAALgAECgkJDgAAAA==.Ludopatika:BAAALgAECgMJAwAAAA==.Lunaala:BAAALgAECgYJDgAAAA==.Lunhzae:BAACLgAFFH8IAAMSAAMJ1xUTFgCnAAASAAIJJBUTFgCnAAAQAAEJGAHcPQAxAAAuAAQKfyoAAxIACAk6HuMCALUCABIACAk6HuMCALUCABEAAwlRCjwxAIwAAAAA.Lustallo:BAAALgAECgYJDwAAAA==.',
Ly='Lynarra:BAAALgAECgcJBwAAAA==.Lynxx:BAAALgADCgYJCgAAAA==.Lyressa:BAAALgADCgEJAgAAAA==.',
Ma='Mack:BAAALgAECgcJBwAAAA==.Mad:BAABLgAECn8eAAIZAAgJaiPxAgAUAwAZAAgJaiPxAgAUAwAAAA==.Madchickenz:BAABLgAECn8ZAAIPAAcJFhpKFACgAQAPAAcJFhpKFACgAQAAAA==.Madrina:BAAALgAECgQJBgAAAA==.Maelstrom:BAAALgADCgQJBAAAAA==.Magicwithin:BAAALgAECggJJAAAAQ==.Magut:BAAALgADCgMJAwAAAA==.Maim:BAAALgADCgYJCQAAAA==.Maira:BAAALgAECgUJDwAAAA==.Malevolens:BAABLgAECn8gAAICAAYJaw0dZQAZAQACAAYJaw0dZQAZAQAAAA==.Malkinish:BAAALgAECgMJAwABLgAECggJKAALAJImAA==.Maraella:BAAALgAECgUJDAAAAA==.Marche:BAABLgAECn8nAAIHAAgJcw1LOQCBAQAHAAgJcw1LOQCBAQAAAA==.Marcrutzou:BAAALgAFFAEJAQAAAA==.Mavar:BAABLgAECn8VAAImAAcJlSK/AwCQAgAmAAcJlSK/AwCQAgAAAA==.Mavrar:BAAALgAECgEJAgABLgAECgcJFQAmAJUiAA==.Mazzikin:BAAALgAECgIJAgAAAA==.',
Me='Meatslapper:BAAALgADCgYJBgAAAA==.Megito:BAAALgAECgEJAgAAAA==.Menoboo:BAAALgADCgQJBAAAAA==.Mephïsto:BAAALgAECgcJEQAAAA==.Messdupllama:BAABLgAECn8oAAQLAAgJkiaDAwADAwALAAgJziWDAwADAwAKAAIJ4CCnHABoAAAFAAEJcSN3MgBlAAAAAA==.Metamorfasis:BAABLgAECn8gAAIWAAcJugdjDwAhAQAWAAcJugdjDwAhAQAAAA==.',
Mi='Microburst:BAABLgAECn8eAAIMAAgJWx6YJwAEAgAMAAgJWx6YJwAEAgAAAA==.Microlight:BAAALgADCgcJCAABLgAECggJHgAMAFseAA==.Midgethealz:BAAALgADCgcJCwABLgAECggJIQAeAH0WAA==.Mightynite:BAAALgAECgUJBQAAAA==.Miischief:BAAALgAECgYJEgAAAA==.Millene:BAABLgAECn8ZAAIgAAcJxhTmGgCQAQAgAAcJxhTmGgCQAQABLgAECgMJBQADAAAAAA==.Mimikyu:BAAALgADCgQJBQAAAA==.Miraclesz:BAAALgAECgQJBAABLgAECgUJCAADAAAAAA==.Missmoodý:BAAALgAECgQJCwAAAA==.Missqwerty:BAAALgAECgEJAQAAAA==.',
Mo='Mongargiss:BAABLgAECn8bAAIHAAYJBRJnUAA5AQAHAAYJBRJnUAA5AQAAAA==.Montaro:BAABLgAECn8VAAIWAAYJgwsVEQAKAQAWAAYJgwsVEQAKAQAAAA==.Moochew:BAAALgADCgUJBQAAAA==.Moonz:BAAALgAECgYJCQAAAA==.Morbidi:BAAALgAECgYJEQAAAA==.Morsmordre:BAAALgADCgYJDgAAAA==.',
Mu='Mudkip:BAACLgAFFH8WAAITAAYJnhELBAClAQATAAYJnhELBAClAQAuAAQKfy8AAhMACQlnH2wCAPECABMACQlnH2wCAPECAAAA.Mushinomad:BAAALgAECgYJCwAAAA==.Mushrumpizza:BAAALgADCgQJBAAAAA==.',
My='Mylanara:BAABLgAECn8iAAIgAAgJsCHNBACvAgAgAAgJsCHNBACvAgAAAA==.Mysticah:BAABLgAECn8UAAIGAAYJkQo1EADXAAAGAAYJkQo1EADXAAAAAA==.Myvrth:BAAALgADCgUJCAAAAA==.',
['Mø']='Møød:BAAALgADCgQJBAAAAA==.',
Na='Nadashilth:BAAALgADCgIJAgABLgAFFAMJBQANAIkdAA==.Namednott:BAAALgADCgcJFQAAAA==.Namya:BAAALgAECggJDgAAAA==.Nanr:BAABLgAECn8bAAMPAAgJLRJnFgCKAQAPAAgJLRJnFgCKAQAaAAEJ6gTu3gAlAAAAAA==.Nasdan:BAAALgAFFAIJAgAAAA==.Nathi:BAABLgAECn8WAAIcAAYJ/g9XJgAMAQAcAAYJ/g9XJgAMAQAAAA==.Navori:BAAALgAFFAEJAQABLgAFFAcJFgAKAJQaAA==.',
Ne='Nedia:BAAALgADCgEJAQAAAA==.Nefarioso:BAAALgAECgEJAgAAAA==.Nerve:BAABLgAECn8jAAIMAAcJDBs1OgC6AQAMAAcJDBs1OgC6AQAAAA==.Nesiryn:BAAALgADCgYJBwAAAA==.Newkers:BAAALgADCgIJAgAAAA==.',
Ni='Niamber:BAACLgAFFH8WAAQKAAcJlBqfBwChAQAKAAYJDxOfBwChAQALAAMJiiBFFwBBAQAFAAIJoBfAEwC0AAAuAAQKfxYAAwoACAmRHWwkAAQCAAoABwnkG2wkAAQCAAsABAl7GvVhAEEBAAAA.Nightràven:BAABLgAECn8YAAIFAAcJwQ8DGABLAQAFAAcJwQ8DGABLAQAAAA==.Nillawaffer:BAAALgAECgcJEgABLgAECggJFgANANQlAA==.Nimrodd:BAAALgAECgIJAgAAAA==.Ninjava:BAAALgADCgkJEwAAAA==.Nirale:BAAALgADCgEJAQABLgAECgQJBwADAAAAAA==.',
No='Noobzy:BAAALgADCgYJBwAAAA==.Noraldori:BAAALgADCgkJCQABLgAECgYJEwADAAAAAA==.Nordimont:BAAALgAECgUJCQAAAA==.Nothotdog:BAAALgADCgUJBQAAAA==.Novacat:BAABLgAECn8hAAIaAAgJASDeDADWAgAaAAgJASDeDADWAgAAAA==.November:BAABLgAECn8VAAIMAAUJSAw8mADiAAAMAAUJSAw8mADiAAAAAA==.',
Nu='Nubriss:BAABLgAECn8VAAIbAAgJzA4QEwBAAQAbAAgJzA4QEwBAAQAAAA==.Nuff:BAAALgADCgYJCAAAAA==.Nuttrbutterz:BAABLgAECn8XAAIMAAYJnwzhcwApAQAMAAYJnwzhcwApAQAAAA==.',
Ny='Nyaboron:BAAALgAECgcJDwAAAA==.Nycky:BAAALgADCgUJCgAAAA==.Nyv:BAAALgADCgcJDgABLgAECgUJBQADAAAAAA==.',
['Nè']='Nèaner:BAABLgAECn8oAAIUAAkJuwkrGgB7AQAUAAkJuwkrGgB7AQAAAA==.',
['Nó']='Nó:BAAALgADCgQJBAAAAA==.',
Ob='Obex:BAAALgADCgcJDwAAAA==.',
Od='Odethia:BAAALgAECgMJBAAAAA==.',
Og='Ogrebane:BAABLgAECn8pAAIkAAgJ/wUfFQBlAQAkAAgJ/wUfFQBlAQAAAA==.',
Oi='Oiheg:BAABLgAECn8nAAIIAAgJ9x+1AwCIAgAIAAgJ9x+1AwCIAgAAAA==.Oilchickenjr:BAAALgADCgEJAQAAAA==.',
Ol='Oldracks:BAAALgAECgUJBwAAAA==.Ollipop:BAAALgADCgUJBQAAAA==.',
On='Onepunchguy:BAAALgAECgUJBQAAAA==.',
Oo='Oonjaya:BAAALgAECgkJBQAAAA==.',
Or='Orangez:BAAALgAECgIJAgAAAA==.Orderic:BAAALgADCgYJBgAAAA==.Oriha:BAAALgAECgIJAgAAAA==.',
Os='Osmodeus:BAAALgADCgEJAQAAAA==.',
Ov='Overcast:BAACLgAFFH8HAAIZAAIJbBh5HQCIAAAZAAIJbBh5HQCIAAAuAAQKfyAAAhkACAlNHZwLADECABkACAlNHZwLADECAAAA.',
Ow='Owlclaw:BAAALgAECgMJBQAAAA==.',
Oz='Ozzlo:BAAALgAECgYJEgAAAA==.',
Pa='Paako:BAAALgAECgYJBwAAAA==.Pad:BAAALgAECgYJEwAAAA==.Palavaj:BAAALgAECgIJAwAAAA==.Pandawyngz:BAAALgAECgYJCQAAAA==.Pangho:BAAALgADCgcJCAAAAA==.Park:BAAALgAECgcJCAAAAA==.Parttimebear:BAAALgADCgkJCQABLgAECggJFgANANQlAA==.',
Pe='Percent:BAAALgADCgUJBQAAAA==.',
Ph='Phaaryn:BAAALgAECgYJDgAAAA==.Phatfriend:BAAALgAECgIJAgAAAA==.Pheare:BAAALgADCgkJCQABLgAECgMJBQADAAAAAA==.Phiis:BAAALgAECgYJCwAAAA==.Phonix:BAAALgADCgYJBgAAAA==.Photos:BAABLgAECn8pAAIdAAgJTSSbAgAnAwAdAAgJTSSbAgAnAwAAAA==.Phyxus:BAAALgADCgkJDQABLgAECgMJBQADAAAAAA==.',
Pi='Pigums:BAABLgAECn8WAAINAAgJ1CV4AQBmAwANAAgJ1CV4AQBmAwAAAA==.Pilon:BAAALgAECgYJBgAAAA==.Pilupi:BAAALgAFFAIJAgABLgAFFAIJBgAKAIkRAA==.Pineapplez:BAAALgADCgMJAwABLgAECgIJAgADAAAAAA==.Pirraa:BAAALgAECgYJEgAAAA==.Pitifulworhm:BAAALgAECgEJAQABLgAECggJIgACALQcAA==.Pixelpuffs:BAAALgAECgIJAwAAAA==.',
Pl='Platekini:BAAALgAECgQJCAAAAA==.Pluug:BAABLgAECn8lAAIMAAgJRR4mFgBpAgAMAAgJRR4mFgBpAgAAAA==.',
Po='Poceidon:BAAALgAECgcJDwAAAA==.Pochi:BAAALgADCgkJEAABLgAECgYJFgAZAH4aAA==.Pongo:BAEALgAECgEJAQABLgAFFAMJBQACAKgRAA==.Pookiebear:BAAALgAECgQJCQAAAA==.Poptartyummy:BAAALgADCgcJBwAAAA==.Potaetoew:BAAALgAECgQJBAAAAA==.',
Pp='Pp:BAABLgAECn8VAAIkAAUJbBVMHgAKAQAkAAUJbBVMHgAKAQAAAA==.',
Pr='Propofheal:BAAALgAECgQJCAAAAA==.Prîde:BAAALgAECgIJAgAAAA==.',
Ps='Psycopath:BAABLgAECn8ZAAIJAAgJjBeqGgDpAQAJAAgJjBeqGgDpAQAAAA==.Psygn:BAAALgAECgEJAQAAAA==.Psynide:BAAALgADCgUJBQABLgAECggJKQAcAEQhAA==.',
Pt='Ptra:BAAALgAECgcJEAAAAA==.',
Pu='Puddingfarts:BAAALgAECgYJEQAAAA==.Puffcookies:BAAALgADCgcJDAAAAA==.Pumpy:BAACLgAFFH8UAAIOAAYJDSDyAgDmAQAOAAYJDSDyAgDmAQAuAAQKfyAAAg4ACQneI8YCAH8DAA4ACQneI8YCAH8DAAAA.',
Py='Pyraeline:BAAALgADCgYJBgAAAA==.Pyriana:BAAALgADCgEJAQAAAA==.Pywacket:BAABLgAECn8kAAMUAAgJTQRPKQAAAQAUAAgJDARPKQAAAQAhAAgJhAFxLQC/AAAAAA==.',
Qu='Quendia:BAAALgADCgEJAQABLgAFFAYJCQAZAAsTAA==.Quendwings:BAACLgAFFH8OAAIdAAUJpyJWBwBfAQAdAAUJpyJWBwBfAQAuAAQKfykABB0ACQnBIkIGAAcDAB0ACQnBIkIGAAcDAAEABwnyF5hWAN4BAAQAAgnCGEAsAEkAAAEuAAUUBgkJABkACxMA.Quenn:BAAALgAECgYJCQABLgAFFAYJCQAZAAsTAA==.',
Ra='Rabern:BAAALgAECgMJBAAAAA==.Ralat:BAAALgADCgYJBgAAAA==.Randòn:BAAALgADCgEJAQAAAA==.Ranorah:BAABLgAECn8lAAMLAAkJnB8eEQBKAgALAAgJyCAeEQBKAgAKAAUJ8w9/VgDuAAAAAA==.Rasmatazz:BAAALgADCgkJCwAAAA==.Ratley:BAAALgADCgMJBAAAAA==.Rayleighh:BAAALgAECgEJAgAAAA==.Razzaksa:BAAALgAECgUJCAAAAA==.',
Re='Redemptio:BAAALgAECgUJDAAAAA==.Regg:BAAALgADCgkJDAAAAA==.Regoros:BAAALgAECgEJAQAAAA==.Reinstorm:BAAALgAECgMJAwABLgAFFAEJAQADAAAAAA==.Rekien:BAAALgADCgYJCAAAAA==.Rentsu:BAAALgAECgEJAgAAAA==.Repentthis:BAAALgADCgEJAQAAAA==.Reuben:BAAALgAECgEJAQABLgAECgEJAQADAAAAAA==.Revolution:BAAALgAECgEJAQAAAA==.',
Rh='Rhoorisa:BAAALgAECgMJBgAAAA==.',
Ri='Rickrossin:BAAALgAECgQJBgAAAA==.Rikaza:BAABLgAECn8VAAIOAAUJRB1SJwAhAQAOAAUJRB1SJwAhAQAAAA==.',
Ro='Roguehuman:BAAALgAECgQJCgABLgAFFAIJBQAIACoIAA==.Rootwarden:BAAALgADCgYJBgAAAA==.Rosefang:BAAALgADCgkJDAAAAA==.Rozzluz:BAAALgAECgYJCAAAAA==.',
Ru='Runiczeal:BAAALgADCgcJDAAAAA==.Rutira:BAABLgAECn8lAAMVAAkJmCO4AQD3AgAVAAkJmCO4AQD3AgAJAAYJPhX1ZABzAQAAAA==.Ruzz:BAAALgAECgEJAQAAAA==.',
Ry='Ryân:BAAALgAECgMJBQAAAA==.',
['Rú']='Rúmi:BAAALgADCgkJDwAAAA==.',
Sa='Saana:BAAALgADCgcJCgABLgAFFAYJGwAVANwiAA==.Saccharïn:BAAALgAECgYJBgABLgAECgYJIAARAMYRAA==.Saiyun:BAAALgAECgUJDAAAAA==.Sakkara:BAAALgADCgMJAwAAAA==.Saldaria:BAAALgAECgcJDQAAAA==.Salder:BAAALgADCgUJBQAAAA==.Sallyslsmshr:BAAALgAECgQJBwAAAA==.Saphil:BAAALgADCgIJAgAAAA==.Sapling:BAAALgADCgEJAQAAAA==.Sapphiwrath:BAAALgAECgQJCgAAAA==.Sarbif:BAAALgADCgUJBQAAAA==.Sarkress:BAAALgADCgIJAgAAAA==.Sartara:BAAALgAECgEJAQAAAA==.Sassybadassy:BAAALgADCgIJAgAAAA==.Sathenoth:BAABLgAECn8UAAISAAUJSA1NFQDuAAASAAUJSA1NFQDuAAAAAA==.',
Se='Seacow:BAAALgAECgcJBwAAAA==.Selinnaria:BAAALgADCgUJBQAAAA==.Selyana:BAAALgADCgcJBwAAAA==.Serakor:BAAALgAECgEJAQAAAA==.Seylena:BAAALgAECgQJCAABLgAECggJKQAlAFwaAA==.',
Sh='Shadowdyn:BAAALgADCgUJBQAAAA==.Shaisua:BAAALgADCgEJAQAAAA==.Shalona:BAAALgAECgEJAQAAAA==.Shamamma:BAAALgADCgkJCwAAAA==.Shammywammy:BAAALgADCgYJBgAAAA==.Shamuelâdams:BAAALgADCgEJAQABLgAECggJIQABAMcaAA==.Shamæn:BAAALgAECgYJCgAAAA==.Shanto:BAAALgAECgQJBQAAAA==.Sharphammer:BAAALgAECgQJBAAAAA==.Shaxia:BAAALgAECgcJBwAAAA==.Shieldon:BAAALgAECgIJBAABLgAECggJJQAaAE8fAA==.Shiftyy:BAAALgADCgcJCgAAAA==.Shikamarú:BAAALgAECgQJBAAAAA==.Shiverusnape:BAABLgAECn8WAAICAAYJoQK6mACvAAACAAYJoQK6mACvAAAAAA==.Shroomiez:BAAALgAECgEJAQAAAA==.Shåmpon:BAAALgAECgUJDwAAAA==.',
Si='Silvernleaf:BAAALgAECgUJDwAAAA==.Sinai:BAABLgAECn8eAAIaAAcJOQ+WNgA9AQAaAAcJOQ+WNgA9AQAAAA==.Sinny:BAAALgAECgQJBAAAAA==.Sirlancer:BAAALgADCgYJBgAAAA==.Sizzurp:BAAALgAECggJDQABLgAECgYJEAADAAAAAA==.',
Sk='Skaudi:BAAALgADCgYJCwAAAA==.Skept:BAABLgAECn8cAAIkAAkJMwxnEQCTAQAkAAkJMwxnEQCTAQAAAA==.',
Sl='Sleepingbear:BAAALgAECgEJAQABLgAECggJKAAoAHgeAA==.Sleêp:BAAALgADCgYJBgAAAA==.Slinkydog:BAAALgAECgYJEwAAAA==.Slobster:BAABLgAECn8aAAIiAAcJgxSMBwCCAQAiAAcJgxSMBwCCAQAAAA==.Slomp:BAAALgADCgYJBgABLgAFFAMJDAANAEcgAA==.Slosh:BAACLgAFFH8MAAINAAMJRyAJFwASAQANAAMJRyAJFwASAQAuAAQKfyQAAw0ACAlcJM0KANACAA0ACAlcJM0KANACAA4AAwmRDYNFAJIAAAAA.Slumbers:BAAALgADCgYJCwAAAA==.Slêep:BAAALgAECgYJDAAAAA==.',
Sm='Smerffy:BAABLgAECn8jAAQNAAgJ3wnMQwDzAAANAAcJGgnMQwDzAAAfAAQJfQ6lHgDlAAAOAAQJoAjYVABYAAAAAA==.Smites:BAAALgAECgMJBgABLgAECggJKQABAIUkAA==.',
Sn='Sneha:BAAALgADCgkJGQAAAA==.Snorlax:BAAALgADCgcJCgAAAA==.',
So='Solammallama:BAAALgADCgIJAgAAAA==.Sonistris:BAAALgADCgcJDAAAAA==.Sonny:BAABLgAECn8eAAIMAAYJmBulngCZAQAMAAYJmBulngCZAQAAAA==.Sorshalynne:BAABLgAECn8gAAIHAAYJwwXodgDaAAAHAAYJwwXodgDaAAAAAA==.Soulblast:BAAALgADCgMJAwAAAA==.Soulhorror:BAABLgAECn8jAAMCAAgJ0B0CGgAvAgACAAgJ0B0CGgAvAgAcAAMJVw1hOAAzAAAAAA==.Southernco:BAAALgADCgYJCgAAAA==.',
Sp='Spacephoenix:BAABLgAECn8lAAMUAAgJaRZ3HwDlAQAUAAgJUhV3HwDlAQAhAAcJlBDfFwB3AQAAAA==.Spiccolii:BAAALgAECgMJBAAAAA==.Spitefury:BAAALgAECgYJEgABLgAECgYJFgAZAH4aAA==.Spriggs:BAEALgAECgYJCAABLgAFFAMJBQACAKgRAA==.',
St='Starrfîre:BAABLgAECn80AAIHAAkJgx5yBwDOAgAHAAkJgx5yBwDOAgAAAA==.Stellaris:BAAALgADCgcJDAAAAA==.Stonecurse:BAAALgADCgMJAwABLgAECgcJGQAIAEgkAA==.Stonedread:BAABLgAECn8ZAAIIAAcJSCTjBABfAgAIAAcJSCTjBABfAgAAAA==.Stonedzilla:BAAALgADCgQJCwAAAA==.',
Su='Sullyboy:BAABLgAECn8VAAIaAAcJQR+aMQDkAQAaAAcJQR+aMQDkAQABLgAFFAYJDAAMAMMQAA==.Sunaril:BAAALgAECgIJAwAAAA==.Sunntzu:BAAALgAECgYJCQAAAA==.Supevoker:BAAALgADCgUJBQABLgADCgYJBgADAAAAAA==.',
Sw='Swindlle:BAABLgAECn8gAAIEAAgJxwqUEwANAQAEAAgJxwqUEwANAQAAAA==.',
Sy='Syber:BAABLgAECn8fAAIaAAgJMBxwEwAvAgAaAAgJMBxwEwAvAgAAAA==.Syberstyx:BAAALgADCgEJAQAAAA==.Sylvá:BAAALgADCgcJEAAAAA==.Sylvíe:BAAALgAECgEJAQAAAA==.Sympathy:BAAALgADCgYJBgAAAA==.Symphonica:BAABLgAECn8VAAInAAYJ4RiUCQA0AQAnAAYJ4RiUCQA0AQAAAA==.Synthesize:BAAALgAECgMJBQAAAA==.',
['Sî']='Sîccness:BAABLgAECn8kAAIZAAgJxBgBEwDJAQAZAAgJxBgBEwDJAQAAAA==.',
Ta='Tachelia:BAAALgADCgYJBgABLgAECggJHwAaAIUZAA==.Tacticalshot:BAAALgADCggJFgAAAA==.Taerielle:BAAALgAECgEJAQAAAA==.Tageren:BAAALgADCgYJBwAAAA==.Taldim:BAAALgAECgQJBwABLgAECggJKQAcAEQhAA==.Tarecgosa:BAAALgAECgQJCgAAAA==.Tarhos:BAAALgAECgEJAQAAAA==.Tarò:BAACLgAFFH8PAAIUAAYJywebBQBvAQAUAAYJywebBQBvAQAuAAQKfygAAhQACQllDUAeAO0BABQACQllDUAeAO0BAAAA.Tazark:BAAALgAECgQJCwABLgAECggJLgAQAGEdAA==.Tazmoden:BAAALgADCgUJBQAAAA==.',
Te='Teach:BAAALgAECgQJBAAAAA==.Teacupps:BAACLgAFFH8RAAMHAAUJnQ7BEgBtAQAHAAUJ5A3BEgBtAQAGAAIJBgv0FABVAAAuAAQKfyAAAwYACQmJGX0cAGoBAAcABwlGFzhRANQBAAYABQkcGn0cAGoBAAAA.Teatree:BAAALgADCgUJBQABLgAFFAIJBQAIACoIAA==.Technosniper:BAAALgADCgcJBwAAAA==.Telvissra:BAACLgAFFH8JAAICAAMJORx1PwASAQACAAMJORx1PwASAQAuAAQKfy8AAgIACQnVHasPAIICAAIACQnVHasPAIICAAAA.Tempesta:BAAALgADCgkJCwAAAA==.Tempyst:BAAALgAECgYJEgAAAA==.Tens:BAAALgAECgIJAgAAAA==.Teoritta:BAABLgAECn8oAAMHAAkJqhs+LgCqAQAHAAkJqhs+LgCqAQAGAAIJJhYwTwCAAAAAAA==.Terminus:BAAALgADCgkJCQABLgAECggJIQAJAAghAA==.Terrisher:BAABLgAECn8dAAIBAAcJfwh+ZwAeAQABAAcJfwh+ZwAeAQAAAA==.',
Th='Thal:BAAALgADCgYJBgAAAA==.Thalja:BAAALgAECgQJBAAAAA==.Thenezar:BAABLgAECn8WAAMSAAYJRQi9MQDiAAASAAUJOQi9MQDiAAAQAAYJog5GQQCVAAAAAA==.Theodore:BAAALgAECgUJBQAAAA==.Thermopalea:BAAALgAECgMJBgAAAA==.Thetanar:BAAALgADCgQJBAABLgAECggJKQAaAMUVAA==.Thi:BAAALgAECgYJBwAAAA==.Thorald:BAABLgAECn8XAAIgAAcJSQSwNAD2AAAgAAcJSQSwNAD2AAAAAA==.Thorggon:BAAALgAECgYJDgABLgAECgcJEQADAAAAAA==.Thornbeast:BAABLgAECn8lAAIbAAgJmAlOEgDkAAAbAAgJmAlOEgDkAAAAAA==.Thttrashtank:BAAALgADCgEJAQAAAA==.Thunderbuns:BAAALgADCgMJAwAAAA==.Thundermayne:BAAALgAECgQJCAAAAA==.Thád:BAABLgAECn8kAAIbAAgJwBj9BgDPAQAbAAgJwBj9BgDPAQAAAA==.',
Ti='Tinisilber:BAAALgAFFAIJAgABLgAFFAMJBgAMAMYFAA==.Tinklestein:BAEALgADCgEJAQABLgAFFAMJBQACAKgRAA==.',
To='Tokedaddy:BAAALgAECgQJBgAAAA==.Tokemaster:BAAALgAECgEJAQAAAA==.Torchedherbs:BAAALgADCgUJBQAAAA==.Toxique:BAABLgAECn8VAAMZAAYJrh59EgDQAQAZAAYJrh59EgDQAQAlAAMJdQqyOQCZAAAAAA==.',
Tr='Travelocitee:BAAALgADCggJDgABLgAECggJDAADAAAAAA==.Tresor:BAAALgADCgYJBgAAAA==.Trkstir:BAAALgAECgYJDQAAAA==.Trojanhorse:BAAALgAECgYJDgAAAA==.Tromaz:BAAALgADCgUJBgAAAA==.Tronshandbag:BAAALgAECgEJAQAAAA==.Truepatriot:BAACLgAFFH8IAAIdAAQJPBUFEQAsAQAdAAQJPBUFEQAsAQAuAAQKfyQAAx0ACAldGmgsANQBAB0ABwmVGWgsANQBAAQAAglEGYo1AG8AAAAA.Trustissues:BAAALgAECgUJBgAAAA==.Try:BAACLgAFFH8cAAMfAAcJNiAfAABTAgAfAAYJ9CMfAABTAgAOAAEJgQ0eKQBXAAAuAAQKfyEAAh8ACQkBJkoAANADAB8ACQkBJkoAANADAAAA.Trybu:BAACLgAFFH8MAAIMAAUJlw0sNAA/AQAMAAUJlw0sNAA/AQAuAAQKfz8AAwwACQkUIMcJANkCAAwACQkUIMcJANkCACkAAgmzHQQKAKgAAAAA.Tryiss:BAAALgAECgUJDgAAAA==.',
Ts='Tsarimea:BAAALgAECgYJEwAAAA==.',
Tt='Ttryss:BAAALgAECgYJEQAAAA==.',
Tu='Tubslumpkin:BAAALgAECgIJBAAAAA==.Tuketu:BAABLgAECn8vAAIPAAkJVAtJFACgAQAPAAkJVAtJFACgAQAAAA==.Tumbleweed:BAAALgADCgcJBwAAAA==.Turtlelord:BAABLgAECn8aAAIHAAcJihEvWgAfAQAHAAcJihEvWgAfAQAAAA==.',
Tw='Twistediron:BAAALgADCgQJBQAAAA==.',
Ty='Tylendal:BAABLgAECn8aAAIQAAgJlhF3FACjAQAQAAgJlhF3FACjAQAAAA==.Tylenols:BAAALgAECgcJEQAAAA==.Tylenolz:BAAALgAECgYJBgAAAA==.Tylenulz:BAAALgAECgMJAwAAAA==.Tylheras:BAABLgAECn8YAAIMAAYJjghBiQAAAQAMAAYJjghBiQAAAQAAAA==.Tyliera:BAAALgADCgcJDAAAAA==.Tylvarion:BAAALgADCgEJAQAAAA==.Typhinnia:BAAALgADCgcJCwAAAA==.Tyrlizard:BAAALgADCgMJAwABLgAECgcJFQAmAJUiAA==.Tyyraant:BAAALgADCgYJBgAAAA==.',
['Tä']='Tämer:BAAALgAECgIJAgABLgAECggJKAAkAH8bAA==.',
Ui='Uinen:BAAALgADCgYJBgAAAA==.',
Un='Uncrune:BAAALgADCgYJBgAAAA==.Unfleshed:BAAALgAECgMJAwAAAA==.Unholyy:BAAALgAECgEJAQAAAA==.Unseencrow:BAAALgADCgYJBgAAAA==.',
Ur='Urnotpreped:BAAALgADCgMJBAAAAA==.',
Us='Usefulidiot:BAAALgAECgEJAwAAAA==.',
Va='Vakyu:BAAALgAECgQJBwAAAA==.Valizari:BAAALgADCgEJAQABLgAECggJIQABAMcaAA==.Valrian:BAAALgAECgYJCgAAAA==.Valtaran:BAAALgAECgQJDAAAAA==.Valtarr:BAABLgAECn8gAAILAAgJFBxOFgAdAgALAAgJFBxOFgAdAgAAAA==.Vampirism:BAABLgAECn8mAAIcAAgJcBl8CgDRAQAcAAgJcBl8CgDRAQAAAA==.Vanadis:BAAALgADCgYJBgAAAA==.Varcius:BAABLgAECn8gAAQRAAYJxhGBCAAlAQARAAYJZA+BCAAlAQAQAAYJCA9hJgAZAQASAAIJtRDBHwBtAAAAAA==.Varik:BAAALgAECgQJBwAAAA==.Vaulthunter:BAABLgAECn8ZAAMJAAYJ4ROZQwAuAQAJAAYJ4ROZQwAuAQAVAAIJiArfPgA3AAAAAA==.Vaylz:BAAALgAECgYJBgABLgAECgkJKAAMAKQKAA==.',
Ve='Vehemenz:BAAALgAECgUJDAAAAA==.Velatha:BAAALgAFFAEJAQABLgAFFAMJBgAMAMYFAA==.Velcro:BAAALgADCgIJAgAAAA==.Vellarel:BAAALgAECgMJCQAAAA==.Veloril:BAAALgAECgQJCAAAAA==.Veritana:BAAALgAECgEJAQAAAA==.Verzy:BAAALgAECgUJBwAAAA==.Vesper:BAAALgADCgcJDQAAAA==.Vespidae:BAAALgAECgYJBgAAAA==.Vezahk:BAAALgADCgcJCgAAAA==.',
Vi='Vidu:BAABLgAECn8pAAMlAAgJXBoVCgAZAgAlAAgJXBoVCgAZAgAZAAcJBQ5ZNAAgAQAAAA==.Vivitrix:BAAALgAECgQJCwAAAA==.Viví:BAACLgAFFH8NAAIMAAQJaAriNAA9AQAMAAQJaAriNAA9AQAuAAQKfzYAAgwACQmZGCMlABACAAwACQmZGCMlABACAAAA.',
Vo='Vorayus:BAAALgADCggJEAAAAA==.Vordis:BAAALgADCgkJCQABLgAECggJEwADAAAAAA==.Voxis:BAAALgADCgUJBgAAAA==.Voøid:BAABLgAECn8WAAIJAAkJGCIGBgDKAgAJAAkJGCIGBgDKAgAAAA==.',
Vu='Vulchan:BAAALgADCgEJAQAAAA==.Vulpis:BAAALgADCgkJCQAAAA==.',
Vv='Vv:BAAALgADCgIJAgAAAA==.',
Vy='Vyrstal:BAAALgADCgEJAQABLgAECgkJKAAMAKQKAA==.',
Wa='Walberg:BAAALgADCgkJCQAAAA==.Wardan:BAABLgAECn8aAAMgAAYJfQyILQAZAQAgAAYJFAuILQAZAQAIAAEJ+AvJSwAlAAAAAA==.Wardotz:BAAALgAECgIJAgAAAA==.Wargisao:BAAALgAECggJEwAAAA==.',
We='Weavile:BAACLgAFFH8FAAMZAAIJvBOkHQCGAAAZAAIJvBOkHQCGAAAlAAEJpQsBEgBMAAAuAAQKfysAAxkACQkCFtEPAFwCABkACAmGGNEPAFwCACUACAkaFzgWADcCAAAA.Wef:BAAALgAECgQJCgAAAA==.Weirdtotem:BAACLgAFFH8FAAINAAMJiR1WFwARAQANAAMJiR1WFwARAQAuAAQKfyYAAw0ACAl/IUsIAPACAA0ACAl/IUsIAPACAB8AAQnKBsstAC8AAAAA.Westylad:BAABLgAECn8rAAIgAAgJdyVvAgD3AgAgAAgJdyVvAgD3AgAAAA==.',
Wh='Whartonius:BAAALgAECgMJAwAAAA==.Whatthefunk:BAAALgADCgYJBgAAAA==.Whohitme:BAAALgAECgMJBAAAAA==.',
Wi='Widebodycast:BAAALgADCgEJAQABLgAFFAIJAgADAAAAAA==.Winfreya:BAAALgAECgYJBgAAAA==.Winters:BAACLgAFFH8FAAIMAAMJlwyZTADvAAAMAAMJlwyZTADvAAAuAAQKfx0AAgwACQkFGbtGAGMCAAwACQkFGbtGAGMCAAAA.Wirechaser:BAAALgADCgEJAQAAAA==.',
Wu='Wubalubadbdb:BAAALgADCgIJAgAAAA==.',
Xa='Xad:BAAALgADCgMJAwAAAA==.Xanesin:BAAALgAECgYJCQAAAA==.Xanlein:BAAALgADCgcJDAAAAA==.Xannaa:BAAALgAECgMJAwAAAA==.Xantcha:BAAALgAECgMJAwAAAA==.Xaralla:BAAALgADCgUJBQAAAA==.',
Xe='Xenovira:BAAALgADCgUJBQAAAA==.',
Xi='Xityr:BAAALgADCgkJCwABLgAECggJIgACALQcAA==.',
Xr='Xrystal:BAABLgAECn8oAAIMAAkJpAquVwBmAQAMAAkJpAquVwBmAQAAAA==.',
Xu='Xujian:BAABLgAECn8UAAIZAAYJTBJGHwBMAQAZAAYJTBJGHwBMAQAAAA==.',
Ya='Yakiki:BAACLgAFFH8mAAIZAAgJehuZAAC/AgAZAAgJehuZAAC/AgAuAAQKfyEAAxkACQlOJf0AAKUDABkACQlOJf0AAKUDACUABAmKF+xFAP4AAAAA.',
Yo='Yorshkaa:BAAALgAECgMJAwAAAA==.',
Yu='Yuma:BAAALgAECgYJBgABLgAECgYJDgADAAAAAA==.',
['Yë']='Yëët:BAAALgAECggJCQABLgAECgYJEAADAAAAAA==.',
Za='Zahira:BAAALgADCgYJBgABLgAECgYJEQADAAAAAA==.Zalee:BAAALgAECgcJDwAAAA==.Zalen:BAABLgAECn8nAAMOAAgJvBhxDgD4AQAOAAgJvBhxDgD4AQANAAEJKA+EfgAxAAAAAA==.Zaose:BAABLgAECn8cAAIBAAYJ2BJYWgA8AQABAAYJ2BJYWgA8AQAAAA==.Zappylad:BAAALgAECgEJAgAAAA==.Zaraan:BAAALgAECgcJEAAAAA==.Zarine:BAAALgADCgMJAwAAAA==.Zartrack:BAAALgADCgQJBAAAAA==.Zaruia:BAAALgAECgYJEwAAAA==.Zaster:BAAALgAECgEJAwAAAA==.',
Ze='Zeichan:BAAALgAECgYJBgAAAA==.Zelrath:BAAALgADCgYJBgABLgAECgYJGQABACoiAA==.Zevarya:BAAALgAECgIJAgAAAA==.Zevronso:BAAALgADCgIJAgABLgAECggJIwAOAAkiAA==.',
Zi='Ziluna:BAAALgAECgEJAQAAAA==.Zimaquibi:BAAALgADCgMJAwAAAA==.Zire:BAAALgADCgEJAQAAAA==.',
Zo='Zoltun:BAAALgADCgcJCQAAAA==.Zonksdruid:BAAALgAECgYJEgAAAA==.Zonksmoose:BAAALgAECgEJAQAAAA==.Zonkspaladin:BAABLgAECn8mAAIdAAgJyBQWHgCWAQAdAAgJyBQWHgCWAQAAAA==.Zornac:BAABLgAECn8ZAAIMAAYJSgHUxACDAAAMAAYJSgHUxACDAAAAAA==.Zorya:BAAALgAECgEJAQAAAA==.',
Zu='Zugzugkiller:BAACLgAFFH8GAAICAAMJfARbWwDJAAACAAMJfARbWwDJAAAuAAQKfxMAAgIABwknFIecAEcBAAIABwknFIecAEcBAAAA.Zumiez:BAAALgAECgEJAQAAAA==.Zunova:BAAALgAECgEJAgAAAA==.Zurä:BAAALgAECgQJBAAAAA==.',
Zy='Zykxoz:BAAALgAECgYJCgAAAA==.Zynskie:BAABLgAECn8bAAISAAgJoRtSBABwAgASAAgJoRtSBABwAgAAAA==.',
['Äb']='Äbyssal:BAAALgAECgEJAQAAAA==.',
['Êc']='Êclîpsê:BAAALgAECgMJAgAAAA==.Êclïpsê:BAAALgAECgMJAwAAAA==.',
['Îm']='Îmmortal:BAABLgAECn8oAAIkAAgJfxv3BwAoAgAkAAgJfxv3BwAoAgAAAA==.',
['ßl']='ßluechew:BAAALgADCgUJBQABLgAECgYJEAADAAAAAA==.',
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
