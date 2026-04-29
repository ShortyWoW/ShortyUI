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

local lookup = {'Paladin-Retribution','DeathKnight-Unholy','Hunter-Survival','Unknown-Unknown','DemonHunter-Devourer','Hunter-Marksmanship','Hunter-BeastMastery','Shaman-Restoration','Shaman-Elemental','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','DemonHunter-Havoc','Druid-Feral','Warrior-Arms','Monk-Mistweaver','Druid-Restoration','Druid-Guardian','Druid-Balance','DeathKnight-Blood','Paladin-Holy','Warlock-Demonology','Priest-Holy','Warrior-Fury','Priest-Discipline','DeathKnight-Frost','Mage-Frost','Mage-Arcane','Warlock-Destruction','Rogue-Subtlety','Paladin-Protection','Warlock-Affliction','Monk-Windwalker','Monk-Brewmaster','DemonHunter-Vengeance','Priest-Shadow','Shaman-Enhancement','Warrior-Protection','Mage-Fire',}
local provider = {region='US',realm='Windrunner',name='US',type='weekly',zone=46,date='2026-04-24',data={Ac='Actionjaxson:BAABLgAECn8ZAAIBAAgJvx/gBABOAgABAAgJvx/gBABOAgAAAA==.',
Ad='Adiais:BAAALgAECgEJAwABLgAFFAIJBgACAK4kAA==.Admiration:BAAALgADCgIJAgAAAA==.Admore:BAAALgAECgQJCwAAAA==.',
Ae='Aethmourne:BAAALgADCgEJAQAAAA==.',
Ag='Agameden:BAAALgAECgYJDgAAAA==.Agogg:BAAALgAECgIJAgAAAA==.Agronak:BAAALgADCgEJAQAAAA==.',
Ai='Aishi:BAAALgAECgYJDQAAAA==.',
Ak='Akadiak:BAABLgAECn8eAAIDAAgJURcpCgA4AgADAAgJURcpCgA4AgAAAA==.Akitsuki:BAAALgAECgEJAQAAAA==.',
Al='Albertenzyme:BAAALgADCgMJBAAAAA==.Alcolyco:BAAALgADCgIJAgAAAA==.Alivron:BAAALgAECggJCAAAAA==.Alko:BAAALgADCgkJCQABLgAECgYJEgAEAAAAAA==.Alkoren:BAAALgAECgMJAwABLgAECgYJEgAEAAAAAA==.Alkorin:BAAALgAECgYJEgAAAA==.Allestra:BAABLgAECn8VAAIFAAcJbhh6PQD+AQAFAAcJbhh6PQD+AQAAAA==.',
Am='Amanojaku:BAAALgADCgQJBAAAAA==.Amarilis:BAAALgAECgEJAgAAAA==.Amarÿah:BAAALgADCgMJAgAAAA==.Amethcrow:BAABLgAECn8XAAIGAAgJZx3BFACKAgAGAAgJZx3BFACKAgAAAA==.Amoxil:BAAALgAECgYJCgAAAA==.',
An='Anasztaizia:BAAALgAECgUJBQAAAA==.Andarrathan:BAAALgADCgQJBAAAAA==.Andurael:BAAALgAECgcJCAAAAA==.Andwin:BAAALgADCgkJCQAAAA==.Angarock:BAAALgAECgcJEQAAAA==.Angelclaw:BAABLgAECn8WAAIHAAcJzwohSQCOAQAHAAcJzwohSQCOAQAAAA==.Angora:BAAALgAECgUJCgAAAA==.Animussadow:BAAALgADCgEJAQAAAA==.Anorah:BAAALgAECgUJCQAAAA==.Anunitu:BAABLgAECn8UAAMIAAYJ0hLnEQAqAQAIAAYJ0hLnEQAqAQAJAAIJ8AkRfABUAAAAAA==.',
Ao='Aoibheann:BAAALgAECgYJCgAAAA==.',
Aq='Aqualeta:BAAALgADCgEJAgAAAA==.',
Ar='Arath:BAABLgAECn8UAAQKAAcJ2Q+HGwBUAQAKAAYJCg6HGwBUAQALAAUJCA81OQAPAQAMAAMJcQTsPQB8AAAAAA==.Arazuren:BAAALgADCgEJAQABLgAECgkJHwACAO0ZAA==.Archegonia:BAAALgADCgcJDAAAAA==.Arcona:BAAALgAECgUJCQAAAA==.Arslette:BAAALgADCgkJDgAAAA==.Arthuel:BAAALgADCgEJAQAAAA==.Arthus:BAAALgAECgYJEwAAAA==.Arynkyr:BAAALgADCgIJAgAAAA==.',
As='Asar:BAAALgAECgMJCgAAAA==.Ashora:BAAALgADCgYJCQAAAA==.Aspun:BAAALgADCgEJAQAAAA==.Astora:BAABLgAECn8WAAMFAAYJYB97DQCjAQAFAAYJYB97DQCjAQANAAEJAABZagA9AAAAAA==.Astralis:BAAALgADCgMJAwAAAA==.',
At='Atherasil:BAAALgADCgYJBgAAAA==.Athuzad:BAAALgAECgUJCQAAAA==.',
Au='Audie:BAAALgAECgEJAQAAAA==.Auquroe:BAAALgADCggJDgAAAA==.Aurelìa:BAAALgADCgMJAwAAAA==.Auroraalysia:BAAALgAECgYJEQAAAA==.Auroran:BAAALgAECgMJCQAAAA==.Autumnmoon:BAABLgAECn8ZAAIOAAgJ8AydAwB5AQAOAAgJ8AydAwB5AQAAAA==.',
Av='Avaarion:BAAALgADCgEJAQAAAA==.Avalotus:BAAALgAECgYJCAAAAA==.Avrilenv:BAAALgAECgIJAwAAAA==.Avä:BAAALgADCgEJAQAAAA==.',
Ay='Ayeroh:BAAALgAECgYJEAAAAA==.Ayhika:BAACLgAFFH8IAAIIAAQJsBeiBgBcAQAIAAQJsBeiBgBcAQAuAAQKfxUAAggACAkgIfUKAM4CAAgACAkgIfUKAM4CAAAA.',
Az='Azehyrus:BAACLgAFFH8FAAIBAAMJPh/kEAAeAQABAAMJPh/kEAAeAQAuAAQKfxcAAgEACAm/JaMGAGUDAAEACAm/JaMGAGUDAAEuAAUUBAkMAA8A7x8A.Azhenhydra:BAAALgADCggJCAAAAA==.Azkabras:BAAALgADCgkJCQABLgAECgYJFwAJACcVAA==.',
Ba='Baddiebrat:BAAALgAECgkJBgAAAA==.Badoink:BAAALgADCgUJBQABLgAECgYJFAAQAAojAA==.Baggedmilk:BAAALgADCgcJBwAAAA==.Baidin:BAAALgAECgMJAwAAAA==.Balorous:BAABLgAECn8XAAQRAAcJDxkHKwAFAgARAAcJDxkHKwAFAgASAAUJFBSOBgDYAAATAAIJbweMcgBXAAAAAA==.Bansheelen:BAAALgADCgkJCQABLgAECgQJDgAEAAAAAA==.Bansheetrack:BAAALgADCgYJCwABLgAECgQJDgAEAAAAAA==.Banthis:BAAALgAECgcJEgAAAA==.Barbarus:BAAALgAECgcJCwAAAA==.Bareclaw:BAAALgADCgYJBgAAAA==.Barillios:BAAALgAECgQJBAAAAA==.Barkcamon:BAAALgAECgYJEgAAAA==.Barthelo:BAABLgAECn8ZAAIUAAgJOSFHAQBPAgAUAAgJOSFHAQBPAgAAAA==.',
Be='Beardedwiz:BAAALgADCgcJDwAAAA==.Beardhero:BAABLgAECn8jAAIVAAgJsSK2AAD5AgAVAAgJsSK2AAD5AgAAAA==.Beardrood:BAAALgADCgYJAwAAAA==.Beastylad:BAAALgAECgYJDAAAAA==.Bekahsama:BAAALgAECgMJBgAAAA==.Beld:BAAALgADCgYJCgAAAA==.Beldaran:BAAALgAECgYJCgAAAA==.Bellabubbles:BAAALgAECgQJDAAAAA==.Belladawna:BAABLgAECn8UAAIWAAgJUwnCoAAXAQAWAAgJUwnCoAAXAQAAAA==.Belldândy:BAAALgADCgkJDwAAAA==.Bennder:BAAALgAECgQJCAAAAA==.Beoffended:BAAALgADCgEJAQAAAA==.Bernal:BAAALgAECgUJCQAAAA==.',
Bh='Bhature:BAAALgADCgYJCwAAAA==.',
Bi='Bibi:BAAALgADCgEJAQAAAA==.Bidtiddiedot:BAAALgADCgEJAQAAAA==.Bigmapletree:BAABLgAECn8YAAIXAAYJsBcgLgCMAQAXAAYJsBcgLgCMAQAAAA==.Bigpumper:BAAALgADCgIJAgABLgAFFAQJCwAJAEweAA==.Bigsteppah:BAAALgAECgEJAQAAAA==.Bigëmu:BAAALgAECgMJAwAAAA==.Bingbängpow:BAAALgAECgkJAgAAAA==.',
Bl='Blackblader:BAAALgAECgUJCwAAAA==.Bladekraft:BAAALgADCgUJCAAAAA==.Bladrick:BAAALgADCgEJAQAAAA==.Blindndumb:BAAALgADCgIJAgAAAA==.Blondeshaman:BAAALgAECgUJBQABLgAFFAMJBwAIAJUQAA==.',
Bo='Boarggon:BAAALgAECgQJBAABLgAECgcJEAAEAAAAAA==.Boggart:BAAALgAECgQJBAAAAA==.Bonk:BAAALgAECgQJCAAAAA==.Bonkboi:BAAALgAECgQJBwAAAA==.Bonkitty:BAAALgADCgcJDgAAAA==.Bonnie:BAAALgAECgEJAQAAAA==.Bonnéy:BAAALgADCgYJCQABLgAECgUJBQAEAAAAAA==.Boog:BAAALgADCgEJAQAAAA==.Bowl:BAAALgAECgUJBQAAAA==.',
Br='Bratakk:BAAALgAECgYJBgAAAA==.Brillina:BAAALgAECgYJBgAAAA==.Bris:BAABLgAECn8XAAIRAAYJjhIpVwBNAQARAAYJjhIpVwBNAQAAAA==.Bruby:BAAALgAECgcJEQAAAA==.Brugamen:BAABLgAECn8VAAIYAAcJ7hSTMgDhAQAYAAcJ7hSTMgDhAQAAAA==.Brugg:BAAALgADCgYJBgABLgAECgcJFQAYAO4UAA==.Bruugg:BAAALgADCgEJAQABLgAECgcJFQAYAO4UAA==.Brád:BAABLgAECn8ZAAIZAAYJUBfeBQCnAQAZAAYJUBfeBQCnAQAAAA==.',
Bu='Bubdly:BAAALgAECgQJBwAAAA==.Bunnylajoya:BAAALgADCgcJBwAAAA==.Burntha:BAAALgAECgEJAQAAAA==.',
['Bä']='Bäldur:BAABLgAECn8ZAAIaAAgJxhFCAQDAAQAaAAgJxhFCAQDAAQAAAA==.',
Ca='Cainan:BAAALgAECgUJBQAAAA==.Calestel:BAAALgAECgMJAwAAAA==.Captinblye:BAAALgADCgEJAQAAAA==.Carmelita:BAAALgAECgYJEAAAAA==.Caroweaven:BAAALgADCgcJFAAAAA==.Cassienne:BAABLgAECn8ZAAIJAAcJRRA2DAA4AQAJAAcJRRA2DAA4AQAAAA==.Catpounce:BAAALgADCgkJFwAAAA==.',
Ce='Cedaver:BAABLgAECn8ZAAIYAAgJThxgAgA/AgAYAAgJThxgAgA/AgAAAA==.Cellphoneguy:BAABLgAECn8WAAMBAAYJ8gx7tAAbAQABAAYJ8gx7tAAbAQAVAAQJiQKThQBiAAAAAA==.Celtigar:BAAALgAECgEJAQAAAA==.',
Ch='Chaan:BAAALgAECgYJEQAAAA==.Chaddicus:BAAALgADCgUJBQAAAA==.Chaitea:BAAALgADCgQJBAAAAA==.Chamael:BAAALgAECgIJAgAAAA==.Champo:BAAALgAECgEJAQAAAA==.Chance:BAAALgADCgYJBgAAAA==.Chereth:BAAALgAECgUJCQAAAA==.Cherwin:BAAALgADCgQJBAAAAA==.Cheshire:BAABLgAECn8eAAIDAAgJBBj1BgCJAgADAAgJBBj1BgCJAgAAAA==.Chiers:BAAALgADCgYJBgAAAA==.Chikkaboom:BAAALgAECgMJAwABLgAECgQJCAAEAAAAAA==.Chillhawg:BAAALgADCgcJBwAAAA==.Chionee:BAAALgADCgEJAQAAAA==.Chiweave:BAAALgAECgYJCQAAAA==.Chlorin:BAAALgAECgEJAQAAAA==.Chocolate:BAACLgAFFH8FAAIbAAQJFgwaEwD8AAAbAAQJFgwaEwD8AAAuAAQKfxQAAxsACAmwHMdZACwCABsACAl1GsdZACwCABwABAljFwoNAPoAAAAA.Chucklehead:BAAALgADCgkJDgAAAA==.Chumchum:BAAALgAECgYJCgAAAA==.Chunala:BAAALgADCgcJEQABLgAECgYJCgAEAAAAAA==.',
Ci='Cirah:BAAALgAECgMJAwAAAA==.Cityofrivers:BAAALgAECgYJCwAAAA==.',
Cl='Classyfied:BAABLgAECn8WAAIQAAYJdiCmBADmAQAQAAYJdiCmBADmAQAAAA==.Clennse:BAAALgADCgYJCAAAAA==.Clickbait:BAAALgAECgUJBQAAAA==.Clob:BAAALgAECgUJCQAAAA==.Cloudcrasher:BAABLgAECn8ZAAMYAAcJ8B4BBAACAgAYAAcJ8B4BBAACAgAPAAIJTRISLwB9AAAAAA==.Cloudseeker:BAAALgADCgUJBQAAAA==.Cloudspeaker:BAAALgAECgEJAQAAAA==.',
Co='Coldblades:BAAALgAECgEJAQAAAA==.Coldblow:BAAALgAECgcJEAAAAA==.Coldfrostshk:BAAALgAECgIJAgAAAA==.Coldslayer:BAABLgAECn8ZAAIHAAgJnhc2CQDVAQAHAAgJnhc2CQDVAQAAAA==.Corbeau:BAAALgADCgkJCQAAAA==.Cordorana:BAAALgADCgkJEQAAAA==.Coronax:BAAALgADCgEJAQAAAA==.Cosetti:BAAALgADCgQJBAAAAA==.',
Cr='Crackzap:BAAALgAECggJEwAAAA==.Crazyrd:BAABLgAECn8VAAIdAAYJdAsmBgDcAAAdAAYJdAsmBgDcAAAAAA==.Crittydps:BAAALgADCgEJAQAAAA==.Crocs:BAAALgADCgcJDwABLgAECgUJDAAEAAAAAA==.Crummbly:BAAALgADCgkJIAAAAA==.Crìtorís:BAAALgADCgcJEQAAAA==.',
Ct='Ctrlshot:BAAALgAECgcJCgAAAA==.',
Cu='Cursedsoulz:BAAALgADCgUJBQAAAA==.',
Cy='Cyber:BAAALgAECgEJAQAAAA==.Cyndelle:BAAALgAECgMJBgAAAA==.Cyndro:BAAALgAECgMJBAAAAA==.Cyntaria:BAAALgAECgYJEAAAAA==.',
Da='Dafrostmon:BAAALgAECgEJAgABLgAECgYJDgAEAAAAAA==.Dagardugg:BAAALgAECgEJAQAAAA==.Dajmibuzi:BAABLgAECn8ZAAIFAAgJcRK4FABXAQAFAAgJcRK4FABXAQAAAA==.Dalari:BAAALgADCgYJBwAAAA==.Danamor:BAAALgAECgYJEgAAAA==.Dandanx:BAAALgAECgEJAQAAAA==.Darciaa:BAABLgAECn8UAAIeAAcJTw6oKAC1AQAeAAcJTw6oKAC1AQAAAA==.Darnel:BAABLgAECn8ZAAIfAAgJsxPgAwCCAQAfAAgJsxPgAwCCAQAAAA==.Darnokk:BAAALgAECgUJBwAAAA==.Darrek:BAAALgADCgMJAwAAAA==.Darthvenom:BAAALgADCgMJBAAAAA==.Dawnshield:BAAALgAECgQJDgAAAA==.',
De='Deathbyfel:BAAALgAECgEJAQABLgAECgcJFgAJAC8iAA==.Deathbyshock:BAABLgAECn8WAAIJAAcJLyIKBQDNAQAJAAcJLyIKBQDNAQAAAA==.Deathstrokee:BAAALgAECgEJAgAAAA==.Deceez:BAAALgADCgUJBQABLgAECgYJEgAEAAAAAA==.Dedlok:BAAALgADCgIJAgAAAA==.Delgiadamar:BAAALgADCgMJAwAAAA==.Demoncelt:BAABLgAECn8VAAISAAgJAQ7YBAAhAQASAAgJAQ7YBAAhAQAAAA==.Demongotha:BAAALgADCgcJBwAAAA==.Demovaj:BAAALgAECgYJDQAAAA==.Demulos:BAAALgADCgYJCAAAAA==.Denarror:BAAALgADCgEJAQAAAA==.Denrukhan:BAABLgAECn8nAAQTAAkJ3CEfCAAUAwATAAkJ3CEfCAAUAwARAAcJZR0IIABBAgAOAAIJRxeBKACJAAAAAA==.Deschain:BAAALgAECgMJAwAAAA==.',
Di='Diin:BAAALgAECgYJEQAAAA==.Dillypoo:BAAALgADCgEJBAAAAA==.',
Dj='Djinger:BAAALgADCgUJBQAAAA==.',
Dk='Dklord:BAAALgAECgYJBgABLgAECgYJDgAEAAAAAA==.',
Do='Donkedixkek:BAAALgAECgEJAQAAAA==.Donkedixlol:BAAALgAECgEJAQAAAA==.Donkedixon:BAAALgAECgYJCwAAAA==.Doobzers:BAAALgADCgYJBwABLgAFFAMJBgAXALAIAA==.Dowe:BAAALgADCgQJBAAAAA==.Doxtorprote:BAAALgAECgUJCgAAAA==.',
Dr='Dragonite:BAABLgAECn8hAAILAAgJbRZpBADMAQALAAgJbRZpBADMAQAAAA==.Dragoonred:BAABLgAECn8ZAAIgAAgJfRLJAADXAQAgAAgJfRLJAADXAQAAAA==.Dreadknightx:BAAALgADCgEJAQAAAA==.Dreamfyre:BAAALgAECgYJDAABLgAFFAYJEAAGALIUAA==.Dredd:BAAALgAECgYJDgAAAA==.Droko:BAAALgADCgUJBQAAAA==.Drougoss:BAAALgAECgMJAwAAAA==.Drraxx:BAABLgAECn8ZAAMRAAgJDw3/YwAmAQARAAcJhQz/YwAmAQATAAEJjQJeiAAnAAAAAA==.Drunk:BAABLgAECn8bAAQhAAYJAhTPCwAUAQAhAAUJeBXPCwAUAQAiAAYJ6gmKTgAJAQAQAAUJNA2cQQDcAAAAAA==.Drïzzt:BAAALgADCgEJAQAAAA==.',
Du='Duskshield:BAAALgAECgEJAQABLgAECgQJDgAEAAAAAA==.',
Ea='Earthotome:BAAALgADCgUJBQAAAA==.',
Ec='Eckshin:BAAALgAECgUJCQAAAA==.',
Ed='Eddiemarz:BAAALgAECgEJAQAAAA==.Eddiezenchi:BAABLgAECn8ZAAIQAAcJWAa8DQAHAQAQAAcJWAa8DQAHAQAAAA==.',
Ek='Ekkaia:BAABLgAECn8WAAIHAAYJGBbqGwAfAQAHAAYJGBbqGwAfAQAAAA==.',
El='Eldanky:BAAALgAECgMJAwAAAA==.Elecraft:BAABLgAECn8YAAMZAAgJXxh+FAAGAgAZAAgJXxh+FAAGAgAXAAMJLBPQYgCkAAAAAA==.Eleminohpee:BAAALgAECgIJAwABLgAECggJGQAbAIQdAA==.Elephant:BAABLgAECn8WAAMZAAkJKB0EBgDrAgAZAAkJKB0EBgDrAgAXAAEJ7goxfgA0AAABLgAFFAgJHAAZACMdAA==.Eliminater:BAAALgAECgYJEAABLgAECgkJIgAWAIQTAA==.Elythe:BAAALgAECgYJDgAAAA==.',
En='Encana:BAABLgAECn8eAAIjAAgJwRHKCgC3AQAjAAgJwRHKCgC3AQAAAA==.Ender:BAAALgAECgMJBgAAAA==.Enoby:BAAALgAECgIJAQAAAA==.Enragedhïppo:BAAALgAECgYJCAAAAA==.',
Er='Erebseth:BAAALgADCgcJCgAAAA==.Erling:BAAALgADCgkJCQAAAA==.Errzza:BAAALgAECgUJBwAAAA==.Erunar:BAAALgAECgEJAwAAAA==.Eruptnghïppo:BAAALgADCgYJBgAAAA==.Eruuruu:BAAALgAECgQJDAAAAA==.',
Es='Eshà:BAABLgAECn8aAAIIAAcJLQzsFQD8AAAIAAcJLQzsFQD8AAAAAA==.',
Et='Etsupriest:BAAALgAECggJEAAAAA==.',
Eu='Eula:BAAALgADCgQJBAAAAA==.',
Ev='Evelynn:BAAALgAECgEJAQAAAA==.',
Ex='Exelia:BAAALgADCgYJBgABLgAFFAcJFQAQAFcjAA==.Exqui:BAABLgAECn8VAAIWAAYJqR3EFABqAQAWAAYJqR3EFABqAQAAAA==.',
Ez='Ezral:BAAALgAECgEJAgABLgAECgUJBwAEAAAAAA==.Ezékiel:BAABLgAECn8ZAAMfAAgJNQ1GCAD3AAAfAAgJ0QlGCAD3AAABAAUJpgs40QDnAAAAAA==.',
['Eí']='Eíko:BAABLgAECn8eAAQXAAcJyBQ1IQDZAQAXAAcJvBQ1IQDZAQAkAAYJ7QeRPAAOAQAZAAUJBw4QNAADAQAAAA==.',
Fa='Fad:BAAALgAECgYJCwAAAA==.Fadedhope:BAAALgADCgYJDAABLgAECgYJEAAEAAAAAA==.Fafnar:BAABLgAECn8ZAAIRAAgJGBPuDwBbAQARAAgJGBPuDwBbAQAAAA==.Fafnie:BAABLgAECn8VAAIJAAYJywLhFwC1AAAJAAYJywLhFwC1AAAAAA==.Fan:BAAALgAECggJEAAAAA==.Faunus:BAAALgADCgUJCQAAAA==.Fauxy:BAAALgAECgUJBQAAAA==.',
Fe='Feared:BAAALgAECgIJAwAAAA==.Felath:BAAALgAECgYJEQAAAA==.Feldspar:BAABLgAECn8XAAIVAAcJihJuDAB4AQAVAAcJihJuDAB4AQAAAA==.Fenyr:BAAALgAECgUJBQAAAA==.',
Fi='Fil:BAAALgAECgYJEQAAAA==.Firepowr:BAAALgAECgQJBAAAAA==.Fishswife:BAAALgAECgUJCQAAAA==.Fissal:BAAALgAECgYJEwABLgAFFAIJBQAQADIOAA==.Fistoflurry:BAAALgAECgcJEAAAAA==.',
Fl='Flemel:BAAALgAECgYJEQAAAA==.Floatingbush:BAAALgAECgYJEgAAAA==.Flompy:BAAALgAECgIJAgAAAA==.Floreil:BAAALgADCgUJDQAAAA==.',
Fo='Foofighter:BAAALgADCgUJAwAAAA==.Foopy:BAABLgAECn8VAAMCAAgJUBZnCwDLAQACAAgJzBRnCwDLAQAaAAQJ4hF3DADqAAAAAA==.Footoo:BAAALgAECgQJBgAAAA==.Forestsong:BAAALgADCgIJAgABLgAECgEJAQAEAAAAAA==.Foxyfife:BAAALgADCgUJBQAAAA==.',
Fr='Franksuba:BAAALgAECgQJDwAAAA==.Fringilla:BAAALgADCgMJAwAAAA==.Frostitutë:BAAALgADCgkJDgAAAA==.Frostyshade:BAAALgAECgEJAQAAAA==.',
Fu='Funk:BAABLgAECn8iAAIWAAkJeRtjBQAiAgAWAAkJeRtjBQAiAgAAAA==.Futurama:BAAALgADCgcJBwAAAA==.',
Fz='Fzoul:BAABLgAECn8YAAIRAAYJsw+fXwAzAQARAAYJsw+fXwAzAQAAAA==.',
Ga='Gabdragon:BAAALgAECgQJBAAAAA==.Gadgett:BAAALgAECgYJEgAAAA==.Galdademon:BAAALgAECggJDwAAAA==.Galiophobia:BAAALgAECgYJEAAAAA==.Garrethul:BAAALgAECgQJCwAAAA==.Gathercow:BAAALgADCgcJCgAAAA==.Gavalar:BAAALgAECgUJDAAAAA==.Gawleywood:BAAALgAECgUJCQAAAA==.',
Ge='Gellidus:BAAALgAECgYJEQAAAA==.Genhooves:BAEALgAECgcJEQAAAA==.Genoesis:BAAALgADCgYJCQAAAA==.',
Gh='Ghenka:BAABLgAECn8UAAQHAAcJRBsNCQDYAQAHAAYJRBsNCQDYAQAGAAYJ/A4FRwA3AQADAAEJsBnaLQA7AAABLgAFFAQJDAAPAO8fAA==.Ghosteagle:BAAALgADCgcJBgAAAA==.',
Gl='Gloomreaver:BAAALgAECgIJAwAAAA==.',
Gn='Gnarlysnarly:BAAALgADCgYJDAAAAA==.Gnomejodas:BAAALgAECgMJBQAAAA==.',
Go='Gobfather:BAAALgAECgIJAgAAAA==.Goldcity:BAACLgAFFH8GAAIjAAMJkgouAgC/AAAjAAMJkgouAgC/AAAuAAQKfxkAAiMACAl4HL0DAJECACMACAl4HL0DAJECAAAA.Goob:BAAALgAECgQJBwAAAA==.Goodfaith:BAAALgAECgEJAQAAAA==.',
Gr='Grimlocke:BAABLgAECn8UAAMWAAcJFxL5HQAsAQAWAAYJFxL5HQAsAQAdAAEJAADeZQBEAAAAAA==.Gromit:BAAALgAECggJEwABLgAFFAQJDAAXAKYXAA==.Grovewarden:BAAALgADCgEJAQAAAA==.',
Gu='Gug:BAAALgADCgcJCAAAAA==.Gullibull:BAABLgAECn8eAAIlAAgJIAf1AwB8AQAlAAgJIAf1AwB8AQAAAA==.',
Gw='Gwynne:BAAALgAECgYJBgAAAA==.',
Ha='Halanad:BAAALgAECgYJCgAAAA==.Halcyone:BAAALgADCgUJBQAAAA==.Halfsumo:BAAALgAECgUJDAAAAA==.Halobender:BAAALgADCgYJBgAAAA==.Hamer:BAAALgADCgEJAQAAAA==.Hanamora:BAAALgADCgkJCQAAAA==.Harkonnen:BAAALgADCgYJEAAAAA==.Hassindiir:BAABLgAECn8eAAISAAgJlQP8HgCoAAASAAgJlQP8HgCoAAAAAA==.Hawgelf:BAAALgAECgUJCgAAAA==.Hawmahcide:BAAALgAECgUJBQAAAA==.Hayles:BAAALgAECgQJBwAAAA==.',
He='Heall:BAAALgAECgEJAQAAAA==.Hecklerkoch:BAABLgAECn8eAAIBAAgJTAnpFwBiAQABAAgJTAnpFwBiAQAAAA==.Helathra:BAABLgAECn8UAAMBAAYJYQ+kkABbAQABAAYJYQ+kkABbAQAfAAMJwQfMNwBiAAAAAA==.Hellie:BAAALgAECgUJBgAAAA==.Hellmage:BAAALgADCgQJBAAAAA==.Hellward:BAAALgAECgMJAwAAAA==.Herevoker:BAAALgAECgYJCgABLgAFFAQJBQACAGAUAA==.Hermaeuss:BAAALgADCgkJDQAAAA==.Herrogue:BAAALgAFFAMJBAABLgAFFAQJBQACAGAUAA==.',
Hi='Hishunter:BAABLgAECn8cAAIHAAgJDCLvCAAFAwAHAAgJDCLvCAAFAwAAAA==.',
Ho='Hobosam:BAABLgAECn8XAAMXAAYJZRIVOwBOAQAXAAYJiw8VOwBOAQAZAAUJZweGDAD4AAAAAA==.Hollowarden:BAAALgADCgEJAgAAAA==.',
Hr='Hräfn:BAAALgADCgYJBgAAAA==.',
Hu='Huntarr:BAAALgAECgYJCwAAAA==.Hunterdamon:BAABLgAECn8XAAIFAAYJtgg4KwDJAAAFAAYJtgg4KwDJAAAAAA==.',
Hy='Hycinna:BAAALgAECgYJEQAAAQ==.Hydraashen:BAABLgAECn8WAAMcAAcJoQIYBACOAAAbAAYJZAJ0CQHpAAAcAAUJWwIYBACOAAAAAA==.Hyndrix:BAAALgADCgEJAgAAAA==.',
Ia='Iamafish:BAAALgAECgYJEQAAAA==.Iamthestorm:BAAALgADCgUJBQAAAA==.',
Ic='Iceris:BAAALgAECgEJAQAAAA==.',
In='Incendemus:BAAALgAECgEJAgAAAA==.Insidae:BAABLgAECn8eAAIeAAgJ3hAkGgAxAgAeAAgJ3hAkGgAxAgAAAA==.',
Ir='Iraegin:BAAALgAECgEJAQAAAA==.',
Is='Iscreamloud:BAAALgAECgMJAwAAAA==.Ismirea:BAAALgAECgEJAQAAAA==.Isoldella:BAAALgADCgkJCgAAAA==.',
It='Itsben:BAAALgADCgEJAQAAAA==.',
Ja='Jalencarter:BAABLgAECn8WAAICAAgJJCW3AAACAwACAAgJJCW3AAACAwAAAA==.Jamirchaman:BAAALgAECgMJBQAAAA==.Jantasir:BAABLgAECn8WAAIBAAcJfRu9OABAAgABAAcJfRu9OABAAgAAAA==.Jarred:BAAALgAECgEJAwABLgAECgUJCQAEAAAAAA==.Javalyn:BAAALgAECgUJBwAAAA==.Jaydonar:BAAALgADCgkJCQAAAA==.',
Je='Jerbo:BAAALgADCgcJCgAAAA==.',
Ji='Jinda:BAAALgADCgcJGQAAAA==.',
Jo='Jobergas:BAABLgAECn8UAAMHAAYJKhHkGQAtAQAHAAYJKhHkGQAtAQAGAAEJ5gEcmQAcAAAAAA==.Johallas:BAABLgAECn8XAAIbAAYJ+QyGLgAQAQAbAAYJ+QyGLgAQAQAAAA==.Joleiste:BAAALgADCgUJBQAAAA==.Josrius:BAAALgAECgEJAQAAAA==.',
Ju='Juansnowe:BAAALgADCgkJCQAAAA==.Juf:BAAALgAECgUJDQAAAA==.Jufster:BAAALgADCgYJBgAAAA==.Julio:BAABLgAECn8aAAICAAcJKhqUVQDxAQACAAcJKhqUVQDxAQAAAA==.Jumpingbear:BAAALgAECggJCAAAAA==.',
Ka='Kaeir:BAAALgADCgUJBQAAAA==.Kaho:BAABLgAECn8XAAIaAAkJQh6cAABGAwAaAAkJQh6cAABGAwAAAA==.Kainazzo:BAAALgADCgkJIQAAAA==.Kaladïn:BAAALgAECgIJAgAAAA==.Kalaris:BAAALgAECgYJDwAAAA==.Kalda:BAABLgAECn8dAAIbAAcJZxk1ZAAQAgAbAAcJZxk1ZAAQAgABLgAFFAEJAQAEAAAAAA==.Kallisto:BAAALgAECgUJBQAAAA==.Kalthoz:BAAALgAECgUJCgAAAA==.Karor:BAAALgAECgIJAgAAAA==.Kathrathryn:BAAALgAECgIJAgAAAA==.Kazuhiro:BAACLgAFFH8MAAMPAAQJ7x8XAQCcAQAPAAQJ7x8XAQCcAQAYAAEJaB+/HgBZAAAuAAQKf0oAAw8ACQkaJcsAAG8DAA8ACQl7JMsAAG8DABgACAkqJVgFAFIDAAAA.',
Ke='Keagan:BAAALgAECgUJBQAAAA==.Keevah:BAAALgAECggJDAAAAA==.Kegeratorr:BAAALgAECgYJCwAAAA==.Keinestina:BAAALgADCggJCgAAAA==.Kekg:BAAALgADCgkJCQABLgAECgYJFAAQAAojAA==.Kelric:BAAALgADCgQJBAAAAA==.Kerciel:BAAALgADCgcJCwABLgAECgcJIwALAFAZAA==.Kerebos:BAAALgADCgEJAQAAAA==.Kexin:BAAALgADCgEJAQAAAA==.',
Kh='Khaluha:BAAALgADCgkJIgAAAA==.Khaymaan:BAAALgAECgQJCwAAAA==.Khitryy:BAAALgAECgYJDgAAAA==.',
Ki='Killdorei:BAAALgAECgYJEgAAAA==.Killios:BAAALgAECgMJAwAAAA==.',
Ko='Kozal:BAAALgADCgQJBAAAAA==.',
Kr='Krabskooter:BAAALgADCgYJCQAAAA==.Krionys:BAABLgAECn8bAAIVAAcJwhr6HQAnAgAVAAcJwhr6HQAnAgAAAA==.Krisha:BAAALgAECgYJEgAAAA==.Krisphobos:BAAALgAECgYJEAAAAA==.Krugzy:BAAALgADCgQJBAAAAA==.',
Kt='Ktrevious:BAABLgAECn8eAAIbAAgJyBnGDQDbAQAbAAgJyBnGDQDbAQAAAA==.',
Ku='Kuang:BAAALgAECgQJBAAAAA==.Kubael:BAAALgAECgUJBwAAAA==.Kulgutbuster:BAABLgAECn8WAAIHAAYJZhw7OQDJAQAHAAYJZhw7OQDJAQAAAA==.Kungpow:BAABLgAECn8aAAIhAAcJNxr7BgBuAQAhAAcJNxr7BgBuAQAAAA==.Kuraash:BAAALgAECgQJBAAAAA==.Kuroken:BAAALgAECgIJAgAAAA==.Kuromatsu:BAABLgAECn8ZAAIRAAgJ+x3XBgD/AQARAAgJ+x3XBgD/AQAAAA==.',
Ky='Kyria:BAABLgAECn8UAAIFAAYJZwTcLADBAAAFAAYJZwTcLADBAAAAAA==.',
['Kì']='Kìngpin:BAAALgAECgMJAwABLgAECgYJGAARALMPAA==.',
['Kÿ']='Kÿt:BAAALgAECgYJDAAAAA==.',
La='Lacedon:BAAALgAECgYJEAAAAA==.Laissa:BAAALgADCgkJIgAAAA==.Lancerdrake:BAAALgAECgQJBwAAAA==.Laquisha:BAAALgAECgQJCgAAAA==.Larfleeze:BAAALgADCgkJHwAAAA==.Largewagon:BAAALgAECgIJAgAAAA==.Larque:BAAALgAECgIJAgAAAA==.Latronia:BAAALgAECgcJAQAAAA==.Lauriena:BAAALgADCgIJAgAAAA==.',
Le='Lethaldx:BAAALgAECgIJAwAAAA==.Lettuceman:BAAALgADCgEJAQAAAA==.',
Li='Lialune:BAAALgAECgcJDwAAAA==.Lilgup:BAAALgAECgQJBQAAAA==.Lilÿ:BAAALgADCgYJCQAAAA==.Linadrea:BAAALgADCgkJEgAAAA==.Liqudblu:BAAALgADCgcJCgAAAA==.Lishan:BAABLgAECn8jAAQLAAcJUBnqBwBuAQAKAAYJpRzSDwDeAQALAAcJWhHqBwBuAQAMAAUJlxRaJwA5AQAAAA==.Literein:BAAALgAECgcJDQAAAA==.Lizora:BAAALgAECgEJAgAAAA==.',
Ll='Llamasmol:BAAALgADCgUJBQAAAA==.Llanfear:BAAALgADCgYJBgAAAA==.Llight:BAAALgAECgYJBgABLgAECgcJFAALAPoeAA==.',
Lo='Lockwar:BAAALgADCgkJCQAAAA==.Locria:BAAALgADCgcJDQAAAA==.Lokki:BAAALgAECgYJBgAAAA==.Loreguy:BAAALgAECgEJAgAAAA==.Lorenei:BAAALgAECgYJEgAAAA==.Loriol:BAAALgADCgUJBQABLgAECgYJCwAEAAAAAA==.Lorrith:BAAALgADCgcJCwAAAA==.Los:BAAALgAECgUJBwAAAA==.',
Lu='Lucìd:BAAALgAECgQJBQAAAA==.Lunaala:BAAALgAECgYJDgAAAA==.Lunhzae:BAABLgAECn8aAAMMAAcJ6hakFgDlAQAMAAcJ6hakFgDlAQAKAAMJUQo6MQCMAAAAAA==.Lustallo:BAAALgAECgYJCwAAAA==.',
Ly='Lynxx:BAAALgADCgYJCgAAAA==.Lyressa:BAAALgADCgEJAgAAAA==.',
Ma='Mack:BAAALgAECgcJBgAAAA==.Mad:BAABLgAECn8UAAIQAAYJCiOKAgBJAgAQAAYJCiOKAgBJAgAAAA==.Madchickenz:BAAALgAECgcJEQAAAA==.Madrina:BAAALgAECgEJAQAAAA==.Magicwithin:BAAALgAECgYJEgAAAQ==.Magut:BAAALgADCgMJAwAAAA==.Maim:BAAALgADCgYJCgAAAA==.Maira:BAAALgAECgMJBgAAAA==.Malevolens:BAABLgAECn8UAAICAAYJSwxELADZAAACAAYJSwxELADZAAAAAA==.Malkinish:BAAALgAECgMJAwABLgAECgYJFwAHAFEmAA==.Maraella:BAAALgAECgUJDAAAAA==.Marche:BAABLgAECn8WAAIWAAYJQA3IIgARAQAWAAYJQA3IIgARAQAAAA==.Marcrutzou:BAAALgAFFAEJAQAAAA==.Mavar:BAABLgAECn8VAAIjAAcJlSLBAwCQAgAjAAcJlSLBAwCQAgAAAA==.Mazzikin:BAAALgADCgQJBAAAAA==.',
Me='Meatslapper:BAAALgADCgYJBgAAAA==.Megito:BAAALgAECgEJAgAAAA==.Menoboo:BAAALgADCgQJBAAAAA==.Mephïsto:BAAALgAECgcJCgAAAA==.Messdupllama:BAABLgAECn8XAAMHAAYJUSYaBQAmAgAHAAYJPSUaBQAmAgAGAAIJ4CBMZgCmAAAAAA==.Metamorfasis:BAAALgAECgYJEgAAAA==.',
Mi='Microburst:BAABLgAECn8ZAAIbAAgJhB1+EQC2AQAbAAgJhB1+EQC2AQAAAA==.Microlight:BAAALgADCgcJCAABLgAECggJGQAbAIQdAA==.Midgethealz:BAAALgADCgcJCwABLgAECggJGQAgAH0SAA==.Mightynite:BAAALgAECgUJBQAAAA==.Miischief:BAAALgAECgQJBgAAAA==.Millene:BAAALgAECgYJDAABLgAECgIJAgAEAAAAAA==.Mimikyu:BAAALgADCgQJBQAAAA==.Miraclesz:BAAALgAECgQJBAABLgAECgUJBQAEAAAAAA==.Missmoodý:BAAALgADCgkJHwAAAA==.Missqwerty:BAAALgAECgEJAQAAAA==.',
Mo='Mongargiss:BAAALgAECgUJCwAAAA==.Montaro:BAAALgAECgUJCQAAAA==.Moochew:BAAALgADCgUJBQAAAA==.Moonz:BAAALgAECgIJAwAAAA==.Morbidi:BAAALgAECgYJCwAAAA==.Morsmordre:BAAALgADCgYJDgAAAA==.',
Mu='Mudkip:BAACLgAFFH8KAAIkAAUJ8wk3AwAwAQAkAAUJ8wk3AwAwAQAuAAQKfyEAAiQACQnLHqEAANECACQACQnLHqEAANECAAAA.Mushinomad:BAAALgAECgYJCwAAAA==.Mushrumpizza:BAAALgADCgQJBAAAAA==.',
My='Mylanara:BAABLgAECn8WAAIYAAYJlBhIDABbAQAYAAYJlBhIDABbAQAAAA==.Mysticah:BAAALgAECgQJCAAAAA==.Myvrth:BAAALgADCgUJCAAAAA==.',
['Mø']='Møød:BAAALgADCgQJBAAAAA==.',
Na='Namednott:BAAALgADCgcJFQAAAA==.Namya:BAAALgAECggJDgAAAA==.Nanr:BAAALgAECgYJEQAAAA==.Nasdan:BAAALgAFFAIJAgAAAA==.Nathi:BAAALgAECgYJCgAAAA==.Navori:BAAALgAECgQJBAABLgAFFAYJEAAGALIUAA==.',
Ne='Nedia:BAAALgADCgEJAQAAAA==.Nefarioso:BAAALgADCgIJAgAAAA==.Nerve:BAABLgAECn8bAAIbAAcJzhitcADyAQAbAAcJzhitcADyAQAAAA==.Newkers:BAAALgADCgIJAgAAAA==.',
Ni='Niamber:BAACLgAFFH8QAAMGAAYJshSVBwChAQAGAAYJMBOVBwChAQAHAAIJ3RTqFQCtAAAuAAQKfxYAAwYACAmRHbQkAP8BAAYABwnkG7QkAP8BAAcABAl7GvphAEEBAAAA.Nightràven:BAAALgAECgYJEAAAAA==.Nillawaffer:BAAALgAECgYJCwABLgAECgYJDAAEAAAAAA==.Nimrodd:BAAALgAECgIJAgAAAA==.Ninjava:BAAALgADCgkJDwAAAA==.Nirale:BAAALgADCgEJAQABLgAECgQJBwAEAAAAAA==.',
No='Noobzy:BAAALgADCgYJBwAAAA==.Noraldori:BAAALgADCgkJCQABLgAECgYJEwAEAAAAAA==.Nordimont:BAAALgAECgUJCQAAAA==.Nothotdog:BAAALgADCgUJBQAAAA==.Novacat:BAABLgAECn8hAAIRAAgJACDjDADWAgARAAgJACDjDADWAgAAAA==.November:BAAALgAECgUJDAAAAA==.',
Nu='Nubriss:BAAALgAECgcJDwAAAA==.Nuff:BAAALgADCgYJBwAAAA==.Nuttrbutterz:BAAALgAECgQJDAAAAA==.',
Ny='Nyaboron:BAAALgAECgQJCQAAAA==.Nyv:BAAALgADCgcJDgABLgADCgkJEAAEAAAAAA==.',
['Nè']='Nèaner:BAABLgAECn8eAAIXAAgJmwcuDgAMAQAXAAgJmwcuDgAMAQAAAA==.',
['Nó']='Nó:BAAALgADCgQJBAAAAA==.',
Ob='Obex:BAAALgADCgcJDwAAAA==.',
Od='Odethia:BAAALgAECgEJAQAAAA==.',
Og='Ogrebane:BAABLgAECn8ZAAIeAAgJFwPVCgAmAQAeAAgJFwPVCgAmAQAAAA==.',
Oi='Oiheg:BAABLgAECn8WAAImAAYJOh/1AgDTAQAmAAYJOh/1AgDTAQAAAA==.Oilchickenjr:BAAALgADCgEJAQAAAA==.',
Ol='Oldracks:BAAALgAECgUJBwAAAA==.Ollipop:BAAALgADCgUJBQAAAA==.',
Oo='Oonjaya:BAAALgAECgkJBAAAAA==.',
Or='Orangez:BAAALgAECgIJAgAAAA==.Orderic:BAAALgADCgYJBgAAAA==.',
Ov='Overcast:BAACLgAFFH8FAAIQAAIJMg5LCQCBAAAQAAIJMg5LCQCBAAAuAAQKfxoAAhAACAlUG0EEAPUBABAACAlUG0EEAPUBAAAA.',
Ow='Owlclaw:BAAALgAECgMJBAAAAA==.',
Oz='Ozzlo:BAAALgAECgYJDwAAAA==.',
Pa='Paako:BAAALgADCgEJAQAAAA==.Pad:BAAALgAECgYJEwAAAA==.Palavaj:BAAALgAECgIJAwAAAA==.Pandawyngz:BAAALgAECgYJCQAAAA==.Pangho:BAAALgADCgcJCAAAAA==.Park:BAAALgAECgYJBgAAAA==.Parttimebear:BAAALgADCgkJCQABLgAECgYJDAAEAAAAAA==.',
Pe='Percent:BAAALgADCgUJBQAAAA==.',
Ph='Phaaryn:BAAALgAECgYJCwAAAA==.Phatfriend:BAAALgAECgIJAgAAAA==.Pheare:BAAALgADCgkJCQABLgAECgIJAgAEAAAAAA==.Phiis:BAAALgAECgYJCAAAAA==.Phonix:BAAALgADCgYJBgAAAA==.Photos:BAABLgAECn8ZAAIVAAgJCCL7AADaAgAVAAgJCCL7AADaAgAAAA==.',
Pi='Pigums:BAAALgAECgYJDAAAAA==.Pilon:BAAALgAECgYJBgAAAA==.Pineapplez:BAAALgADCgMJAwABLgAECgIJAgAEAAAAAA==.Pirraa:BAAALgAECgYJDQAAAA==.Pitifulworhm:BAAALgAECgEJAQABLgAECgYJEgAEAAAAAA==.Pixelpuffs:BAAALgAECgIJAwAAAA==.',
Pl='Platekini:BAAALgAECgIJAwAAAA==.Pluug:BAABLgAECn8WAAIbAAgJJxfAVAA6AgAbAAgJJxfAVAA6AgAAAA==.',
Po='Poceidon:BAAALgAECgcJBwAAAA==.Pochi:BAAALgADCgkJEAABLgAECgYJEgAEAAAAAA==.Pongo:BAAALgADCgEJAQAAAA==.Pookiebear:BAAALgAECgQJCQAAAA==.Poptartyummy:BAAALgADCgcJBwAAAA==.Potaetoew:BAAALgAECgQJBAAAAA==.',
Pp='Pp:BAAALgAECgUJDAAAAA==.',
Pr='Prîde:BAAALgAECgIJAgAAAA==.',
Ps='Psycopath:BAAALgAECgYJDQAAAA==.Psynide:BAAALgADCgUJBQABLgAECggJGQAUADkhAA==.',
Pt='Ptra:BAAALgAECgYJCQAAAA==.',
Pu='Puddingfarts:BAAALgAECgQJCAAAAA==.Puffcookies:BAAALgADCgcJDAAAAA==.Pumpy:BAACLgAFFH8LAAIJAAQJTB6qAQBxAQAJAAQJTB6qAQBxAQAuAAQKfyAAAgkACQneI8ICAIADAAkACQneI8ICAIADAAAA.',
Py='Pyraeline:BAAALgADCgYJBgAAAA==.Pyriana:BAAALgADCgEJAQAAAA==.Pywacket:BAABLgAECn8UAAMXAAgJ0APqDgABAQAXAAgJ0APqDgABAQAZAAMJSgAAVwAzAAAAAA==.',
Qu='Quendia:BAAALgADCgEJAQABLgAFFAUJCwAVABIgAA==.Quendwings:BAACLgAFFH8LAAIVAAUJEiBHBwBfAQAVAAUJEiBHBwBfAQAuAAQKfyYABBUACQlkIUYGAAcDABUACQlkIUYGAAcDAAEABgmNGp5WAN4BAB8AAgmzGPkQAEoAAAAA.',
Ra='Rabern:BAAALgAECgIJAQAAAA==.Randòn:BAAALgADCgEJAQAAAA==.Ranorah:BAABLgAECn8cAAMHAAgJQh+dEwCaAgAHAAcJkSCdEwCaAgAGAAUJ8w9rVgDuAAAAAA==.Rasmatazz:BAAALgADCgIJAgAAAA==.Ratley:BAAALgADCgMJBAAAAA==.Rayleighh:BAAALgADCgcJDAAAAA==.Razzaksa:BAAALgADCgYJBgAAAA==.',
Re='Redemptio:BAAALgAECgQJBQAAAA==.Regg:BAAALgADCgMJAwAAAA==.Regoros:BAAALgAECgEJAQAAAA==.Reinstorm:BAAALgAECgMJAwABLgAECgcJDQAEAAAAAA==.Rekien:BAAALgADCgYJCAAAAA==.Repentthis:BAAALgADCgEJAQAAAA==.Reuben:BAAALgAECgEJAQAAAA==.Revolution:BAAALgAECgEJAQAAAA==.',
Rh='Rhoorisa:BAAALgAECgMJAwAAAA==.',
Ri='Rickrossin:BAAALgAECgQJBgAAAA==.Rikaza:BAAALgAECgUJDAAAAA==.',
Ro='Roguehuman:BAAALgAECgMJAwABLgAECggJGwAmABkTAA==.Rootwarden:BAAALgADCgYJBgAAAA==.Rosefang:BAAALgADCgYJCQAAAA==.Rozzluz:BAAALgAECgYJBwAAAA==.',
Ru='Runiczeal:BAAALgADCgcJDAAAAA==.Rutira:BAABLgAECn8eAAMNAAgJjCNGBgAFAwANAAgJjCNGBgAFAwAFAAYJPhXzZABzAQAAAA==.Ruzz:BAAALgAECgEJAQAAAA==.',
Ry='Ryân:BAAALgAECgIJAgAAAA==.',
['Rú']='Rúmi:BAAALgADCgkJDwAAAA==.',
Sa='Saana:BAAALgADCgcJCgABLgAFFAUJEAANADkjAA==.Saiyun:BAAALgAECgQJBwAAAA==.Sakkara:BAAALgADCgMJAwAAAA==.Saldaria:BAAALgAECgQJBwAAAA==.Salder:BAAALgADCgUJBQAAAA==.Sallyslsmshr:BAAALgAECgQJBwAAAA==.Sapling:BAAALgADCgEJAQAAAA==.Sapphiwrath:BAAALgAECgQJCAAAAA==.Sarkress:BAAALgADCgIJAgAAAA==.Sartara:BAAALgAECgEJAQAAAA==.Sassybadassy:BAAALgADCgIJAgAAAA==.Sathenoth:BAAALgAECgQJCwAAAA==.',
Se='Seacow:BAAALgAECgUJBQAAAA==.Selinnaria:BAAALgADCgUJBQAAAA==.Selyana:BAAALgADCgcJBwAAAA==.Serakor:BAAALgADCgEJAQAAAA==.Seylena:BAAALgAECgIJAwABLgAECggJGQAhAL0UAA==.',
Sh='Shadowdyn:BAAALgADCgUJBQAAAA==.Shalona:BAAALgAECgEJAQAAAA==.Shamamma:BAAALgADCgIJAgAAAA==.Shammywammy:BAAALgADCgYJBgAAAA==.Shamuelâdams:BAAALgADCgEJAQABLgAECgcJFgABAH0bAA==.Shamæn:BAAALgAECgQJBAAAAA==.Shanto:BAAALgAECgQJBQAAAA==.Shaxia:BAAALgAECgcJBwAAAA==.Shieldon:BAAALgAECgEJAQABLgAECggJGQARAPsdAA==.Shiftyy:BAAALgADCgcJCgAAAA==.Shikamarú:BAAALgAECgQJBAAAAA==.Shiverusnape:BAAALgAECgYJCAAAAA==.Shroomiez:BAAALgAECgEJAQAAAA==.Shåmpon:BAAALgAECgUJCwAAAA==.',
Si='Silvernleaf:BAAALgAECgMJBgAAAA==.Sinai:BAABLgAECn8XAAIRAAcJgQ4hEwAyAQARAAcJgQ4hEwAyAQAAAA==.Sinny:BAAALgAECgQJBAAAAA==.Sirlancer:BAAALgADCgYJBgAAAA==.Sizzurp:BAAALgAECgQJBAABLgAECgYJEAAEAAAAAA==.',
Sk='Skaudi:BAAALgADCgYJCwAAAA==.Skept:BAABLgAECn8YAAIeAAgJrQkVCQBGAQAeAAgJrQkVCQBGAQAAAA==.',
Sl='Slinkydog:BAAALgAECgYJDwAAAA==.Slobster:BAAALgAECgYJEgAAAA==.Slomp:BAAALgADCgYJBgABLgAECgcJHAAIAIojAA==.Slosh:BAABLgAECn8cAAMIAAcJiiPPCgDQAgAIAAcJiiPPCgDQAgAJAAMJiw1qGQCkAAAAAA==.Slumbers:BAAALgADCgYJCwAAAA==.Slêep:BAAALgADCgcJDAAAAA==.',
Sm='Smerffy:BAABLgAECn8WAAQIAAgJ3gkzXAAZAQAIAAcJGAkzXAAZAQAlAAQJfQ6nHgDlAAAJAAMJjQnzewBVAAAAAA==.Smites:BAAALgAECgIJAwABLgAECggJGQABAL8fAA==.',
Sn='Sneha:BAAALgADCgkJGQAAAA==.Snorlax:BAAALgADCgcJCgAAAA==.',
So='Sonistris:BAAALgADCgUJBQAAAA==.Sonny:BAABLgAECn8YAAIbAAYJmBuzngCZAQAbAAYJmBuzngCZAQAAAA==.Sorshalynne:BAABLgAECn8UAAIWAAYJYwPFNACtAAAWAAYJYwPFNACtAAAAAA==.Soulblast:BAAALgADCgMJAwAAAA==.Soulhorror:BAAALgAECgYJEwAAAA==.Southernco:BAAALgADCgYJCgAAAA==.',
Sp='Spacephoenix:BAABLgAECn8cAAMXAAgJCxVzHwDlAQAXAAgJ3hNzHwDlAQAZAAcJ+w5jCABcAQAAAA==.Spiccolii:BAAALgAECgEJAQAAAA==.Spitefury:BAAALgAECgYJBgABLgAECgYJEgAEAAAAAA==.Spriggs:BAEALgAECgMJAwABLgAECgcJEQAEAAAAAA==.',
St='Starrfîre:BAABLgAECn8iAAIWAAkJhBNdIwCHAgAWAAkJhBNdIwCHAgAAAA==.Stellaris:BAAALgADCgcJDAAAAA==.Stonecurse:BAAALgADCgMJAwABLgAECgYJEQAEAAAAAA==.Stonedread:BAAALgAECgYJEQAAAA==.Stonedzilla:BAAALgADCgQJBwAAAA==.',
Su='Sullyboy:BAABLgAECn8VAAIRAAcJQR+dMQDkAQARAAcJQR+dMQDkAQABLgAFFAQJBQAbABYMAA==.Sunaril:BAAALgAECgIJAwAAAA==.Sunntzu:BAAALgAECgQJBgAAAA==.Supevoker:BAAALgADCgUJBQABLgADCgYJBgAEAAAAAA==.',
Sw='Swindlle:BAAALgAECgYJEQAAAA==.',
Sy='Syber:BAABLgAECn8YAAIRAAcJbxwXKQAPAgARAAcJbxwXKQAPAgAAAA==.Sylveria:BAAALgAECgEJAQABLgAECgcJEwAEAAAAAA==.Sylvá:BAAALgADCgcJEQAAAA==.Sympathy:BAAALgADCgYJBgAAAA==.Symphonica:BAAALgAECgYJDAAAAA==.Synthesize:BAAALgAECgMJBQAAAA==.',
['Sî']='Sîccness:BAABLgAECn8VAAIQAAYJQRqGHgDCAQAQAAYJQRqGHgDCAQAAAA==.',
Ta='Tachelia:BAAALgADCgYJBgABLgAECgcJFwARAA8ZAA==.Tacticalshot:BAAALgADCggJFgAAAA==.Taerielle:BAAALgADCgQJBQAAAA==.Taldim:BAAALgAECgIJAwABLgAECggJGQAUADkhAA==.Tarecgosa:BAAALgAECgIJBAAAAA==.Tarhos:BAAALgADCgcJCQAAAA==.Tarò:BAACLgAFFH8FAAIXAAMJ3gSuBgB8AAAXAAMJ3gSuBgB8AAAuAAQKfyUAAhcACQllDT8eAO0BABcACQllDT8eAO0BAAAA.Tazark:BAAALgAECgQJCwABLgAECgcJIwALAFAZAA==.Tazmoden:BAAALgADCgUJBQAAAA==.',
Te='Teacupps:BAACLgAFFH8JAAMWAAQJfg4WJADzAAAWAAMJGg4WJADzAAAdAAIJAwvvFABVAAAuAAQKfyAAAx0ACQmJGYIcAGoBABYABwlGFz9RANQBAB0ABQkcGoIcAGoBAAAA.Telvissra:BAABLgAECn8fAAICAAkJ7RlVHwDFAgACAAkJ7RlVHwDFAgAAAA==.Tempesta:BAAALgADCgkJCwAAAA==.Tempyst:BAAALgAECgUJBgAAAA==.Teoritta:BAABLgAECn8gAAMWAAgJTxmNQAAMAgAWAAgJTxmNQAAMAgAdAAIJJhYoTwCAAAAAAA==.Terminus:BAAALgADCgkJCQABLgAECgYJFgAFAGAfAA==.Terrisher:BAAALgAECgYJEAAAAA==.',
Th='Thal:BAAALgADCgYJBgAAAA==.Thenezar:BAAALgAECgYJCgAAAA==.Theodore:BAAALgAECgUJBQAAAA==.Thermopalea:BAAALgAECgIJAwAAAA==.Thi:BAAALgAECgYJBwAAAA==.Thorald:BAAALgAECgYJEAAAAA==.Thorggon:BAAALgAECgUJCAABLgAECgcJEAAEAAAAAA==.Thornbeast:BAABLgAECn8WAAISAAcJQgnaGgDVAAASAAcJQgnaGgDVAAAAAA==.Thttrashtank:BAAALgADCgEJAQAAAA==.Thunderbuns:BAAALgADCgMJAwAAAA==.Thundermayne:BAAALgAECgEJAQAAAA==.Thád:BAABLgAECn8WAAISAAYJ8RpzDADDAQASAAYJ8RpzDADDAQAAAA==.',
Ti='Tinisilber:BAAALgAECgQJCQABLgAFFAEJAQAEAAAAAA==.Tinklestein:BAEALgADCgEJAQABLgAECgcJEQAEAAAAAA==.',
To='Tokedaddy:BAAALgAECgQJBgAAAA==.Tokemaster:BAAALgAECgEJAQAAAA==.Toxique:BAAALgAECgYJDwAAAA==.',
Tr='Travelocitee:BAAALgADCgcJDAABLgAECgQJCAAEAAAAAA==.Tresor:BAAALgADCgYJBgAAAA==.Trkstir:BAAALgAECgMJBAAAAA==.Trojanhorse:BAAALgADCgYJCAAAAA==.Tromaz:BAAALgADCgUJBgAAAA==.Tronshandbag:BAAALgAECgEJAQAAAA==.Truepatriot:BAABLgAECn8dAAMVAAgJ+RllLADUAQAVAAcJihllLADUAQAfAAIJqQyMNQBvAAAAAA==.Trustissues:BAAALgAECgUJBgAAAA==.Try:BAACLgAFFH8UAAIlAAYJ1yEeAABTAgAlAAYJ1yEeAABTAgAuAAQKfyEAAiUACQkBJkoAANADACUACQkBJkoAANADAAAA.Trybu:BAACLgAFFH8FAAIbAAIJ+AqJRgCjAAAbAAIJ+AqJRgCjAAAuAAQKfzMAAxsACAmsH50rAMQCABsACAmsH50rAMQCACcAAgmzHQMKAKgAAAAA.Tryiss:BAAALgAECgUJCwAAAA==.',
Ts='Tsarimea:BAAALgAECgYJDQAAAA==.',
Tt='Ttryss:BAAALgAECgYJCwAAAA==.',
Tu='Tubslumpkin:BAAALgAECgEJAQAAAA==.Tuketu:BAABLgAECn8eAAITAAgJWQrRMQB7AQATAAgJWQrRMQB7AQAAAA==.Tumbleweed:BAAALgADCgcJBwAAAA==.Turtlelord:BAAALgAECgQJEAAAAA==.',
Tw='Twistediron:BAAALgADCgQJBQAAAA==.',
Ty='Tylendal:BAABLgAECn8ZAAILAAgJixF3BQCrAQALAAgJixF3BQCrAQAAAA==.Tylenolz:BAAALgAECgMJAwAAAA==.Tylenulz:BAAALgAECgMJAwAAAA==.Tylheras:BAAALgAECgUJDwAAAA==.Tyliera:BAAALgADCgcJDAAAAA==.Typhinnia:BAAALgADCgQJBAAAAA==.Tyrlizard:BAAALgADCgMJAwABLgAECgcJFQAjAJUiAA==.Tyyraant:BAAALgADCgYJBgAAAA==.',
['Tä']='Tämer:BAAALgAECgIJAgABLgAECgcJFwAeAMcXAA==.',
Ui='Uinen:BAAALgADCgYJBgAAAA==.',
Un='Uncrune:BAAALgADCgYJBgAAAA==.Unfleshed:BAAALgAECgMJAwAAAA==.Unholyy:BAAALgAECgEJAQAAAA==.Unseencrow:BAAALgADCgYJBgAAAA==.',
Ur='Urnotpreped:BAAALgADCgMJBAAAAA==.',
Va='Vakyu:BAAALgAECgQJBwAAAA==.Valizari:BAAALgADCgEJAQABLgAECgcJFgABAH0bAA==.Valrian:BAAALgAECgYJCQAAAA==.Valtaran:BAAALgAECgEJAQAAAA==.Valtarr:BAABLgAECn8YAAIHAAgJUho9BwD2AQAHAAgJUho9BwD2AQAAAA==.Vampirism:BAABLgAECn8XAAIUAAYJYBZ7HQBeAQAUAAYJYBZ7HQBeAQAAAA==.Varcius:BAABLgAECn8UAAILAAYJkQ4VDQAYAQALAAYJkQ4VDQAYAQAAAA==.Varik:BAAALgADCgcJDAAAAA==.Vaulthunter:BAAALgAECgYJCAAAAA==.',
Ve='Vehemenz:BAAALgAECgMJAwAAAA==.Velatha:BAAALgAFFAEJAQAAAA==.Velcro:BAAALgADCgIJAgAAAA==.Vellarel:BAAALgAECgMJCQAAAA==.Veloril:BAAALgAECgIJAwAAAA==.Verzy:BAAALgAECgEJAgAAAA==.Vespidae:BAAALgAECgYJBgAAAA==.Vezahk:BAAALgADCgcJCgAAAA==.',
Vi='Vidu:BAABLgAECn8ZAAMhAAgJvRTUBwBdAQAhAAYJrhfUBwBdAQAQAAYJQg8mNAAkAQAAAA==.Vivitrix:BAAALgAECgEJAQAAAA==.Viví:BAACLgAFFH8GAAIbAAIJDgj5HACiAAAbAAIJDgj5HACiAAAuAAQKfygAAhsACQkXFe8OAM4BABsACQkXFe8OAM4BAAAA.',
Vo='Vorayus:BAAALgADCggJEAAAAA==.Voxis:BAAALgADCgUJBgAAAA==.Voøid:BAAALgAECgcJEAAAAA==.',
Vu='Vulchan:BAAALgADCgEJAQAAAA==.Vulpis:BAAALgADCgkJCQAAAA==.',
Vv='Vv:BAAALgADCgIJAgAAAA==.',
Vy='Vyrstal:BAAALgADCgEJAQABLgAECggJHwAbAFILAA==.',
Wa='Walberg:BAAALgADCgkJCQAAAA==.Wardan:BAAALgAECgYJEAAAAA==.Wargisao:BAAALgAECggJEwAAAA==.',
We='Weavile:BAABLgAECn8lAAMQAAkJyBXcDwBdAgAQAAgJRRjcDwBdAgAhAAgJGhc2FgA3AgAAAA==.Wef:BAAALgADCgkJKwAAAA==.Weirdtotem:BAABLgAECn8fAAMIAAgJfyFJCADwAgAIAAgJfyFJCADwAgAlAAEJygbKLQAvAAAAAA==.Westylad:BAABLgAECn8aAAIYAAgJqSSKAADTAgAYAAgJqSSKAADTAgAAAA==.',
Wh='Whartonius:BAAALgAECgMJAwAAAA==.Whatthefunk:BAAALgADCgYJBgAAAA==.Whohitme:BAAALgAECgMJAwAAAA==.',
Wi='Winfreya:BAAALgAECgYJBgAAAA==.Winters:BAABLgAECn8ZAAIbAAkJHRfDRgBjAgAbAAkJHRfDRgBjAgAAAA==.',
Xa='Xanesin:BAAALgAECgQJBAAAAA==.Xanlein:BAAALgADCgcJDQAAAA==.Xannaa:BAAALgAECgMJAwAAAA==.Xantcha:BAAALgAECgMJAwAAAA==.',
Xr='Xrystal:BAABLgAECn8fAAIbAAgJUgvsigC8AQAbAAgJUgvsigC8AQAAAA==.',
Xu='Xujian:BAAALgAECgQJBwAAAA==.',
Ya='Yakiki:BAACLgAFFH8YAAIQAAYJ+yB7AAAdAgAQAAYJ+yB7AAAdAgAuAAQKfyEAAxAACQlNJfoAAKYDABAACQlNJfoAAKYDACEABAmKF+tFAP4AAAAA.',
Yo='Yorshkaa:BAAALgAECgMJAwAAAA==.',
['Yë']='Yëët:BAAALgAECggJCQABLgAECgYJEAAEAAAAAA==.',
Za='Zalee:BAAALgAECgQJCwAAAA==.Zalen:BAABLgAECn8XAAMJAAYJJxUgOgBmAQAJAAYJJxUgOgBmAQAIAAEJIw99LAA1AAAAAA==.Zaose:BAAALgAECgYJEAAAAA==.Zarine:BAAALgADCgMJAwAAAA==.Zartrack:BAAALgADCgQJBAAAAA==.Zaruia:BAAALgAECgUJBwAAAA==.Zaster:BAAALgAECgEJAwAAAA==.',
Ze='Zeichan:BAAALgAECgYJBgAAAA==.Zelrath:BAAALgADCgYJBgABLgAECgQJDgAEAAAAAA==.Zevarya:BAAALgAECgIJAgAAAA==.Zevronso:BAAALgADCgIJAgABLgAECgcJFgAJAC8iAA==.',
Zi='Ziluna:BAAALgAECgEJAQAAAA==.Zimaquibi:BAAALgADCgMJAwAAAA==.Zire:BAAALgADCgEJAQAAAA==.',
Zo='Zoltun:BAAALgADCgcJCQAAAA==.Zonksdruid:BAAALgAECgUJCQAAAA==.Zonkspaladin:BAABLgAECn8dAAIVAAcJQRHSNgCgAQAVAAcJQRHSNgCgAQAAAA==.Zornac:BAAALgAECgYJDwAAAA==.',
Zu='Zugzugkiller:BAAALgAFFAIJAgAAAA==.Zumiez:BAAALgAECgEJAQAAAA==.Zunova:BAAALgAECgEJAgAAAA==.Zurä:BAAALgAECgQJBAAAAA==.',
Zy='Zykxoz:BAAALgAECgYJCgAAAA==.Zynskie:BAABLgAECn8VAAIMAAgJfhhtAQBLAgAMAAgJfhhtAQBLAgAAAA==.',
['Êc']='Êclîpsê:BAAALgAECgMJAgAAAA==.Êclïpsê:BAAALgAECgMJAwAAAA==.',
['Îm']='Îmmortal:BAABLgAECn8XAAIeAAcJxxf5BwBdAQAeAAcJxxf5BwBdAQAAAA==.',
['ßl']='ßluechew:BAAALgADCgUJBQABLgAECgYJEAAEAAAAAA==.',
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
