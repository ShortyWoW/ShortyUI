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

local lookup = {'Paladin-Holy','Unknown-Unknown','Paladin-Protection','Paladin-Retribution','Warlock-Demonology','Priest-Holy','Priest-Discipline','Priest-Shadow','Druid-Balance','Shaman-Restoration','Hunter-BeastMastery','Hunter-Marksmanship','Warrior-Fury','DeathKnight-Unholy','Shaman-Enhancement','Mage-Frost','DemonHunter-Vengeance','Monk-Brewmaster','DemonHunter-Devourer','Druid-Restoration','DeathKnight-Blood','Warlock-Destruction','Shaman-Elemental','Hunter-Survival','Monk-Windwalker','DemonHunter-Havoc','Warlock-Affliction','Warrior-Arms','Rogue-Assassination','Rogue-Subtlety','Monk-Mistweaver','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Frost','Mage-Arcane','Warrior-Protection','Druid-Feral','Druid-Guardian',}
local provider = {region='US',realm='Silvermoon',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aakura:BAABLgAECn8UAAIBAAYJJRz5LQDMAQABAAYJJRz5LQDMAQAAAA==.Aarcadia:BAAALgAECgQJBQAAAA==.',
Ab='Absolutnova:BAAALgAECgQJCAABLgAECgcJDQACAAAAAA==.',
Ac='Aceoneant:BAAALgADCgcJEAAAAA==.Acktaeon:BAAALgAECgEJAQABLgAECgQJBQACAAAAAA==.',
Ad='Adamantus:BAAALgAECgYJDgAAAA==.Admetus:BAAALgADCgIJAgAAAA==.Aduckstrasza:BAAALgAECgMJAgAAAA==.',
Ae='Aedrion:BAAALgADCgIJAwAAAA==.Aelioran:BAABLgAECn8UAAMDAAYJWRkNGQBLAQAEAAYJNxi+fgB8AQADAAYJrxANGQBLAQAAAA==.Aenlor:BAAALgAECgYJCwAAAA==.Aerimes:BAAALgAECgYJEQAAAA==.Aestar:BAAALgAECgYJDQAAAA==.Aethias:BAAALgAECgMJAwAAAA==.',
Ah='Ahanitken:BAAALgAECgEJAQAAAA==.',
Ai='Ailurus:BAAALgADCgEJAQAAAA==.Airedhiel:BAAALgAECgQJBwAAAA==.Aivil:BAACLgAFFH8GAAIBAAMJPRB7BgDpAAABAAMJPRB7BgDpAAAuAAQKfxYAAwEACAliGS0kAAECAAEACAliGS0kAAECAAQAAgkxBtEfAV0AAAEuAAQKCAkeAAUAWxkA.',
Aj='Ajg:BAAALgAECgEJAQAAAA==.Ajia:BAAALgADCgcJEAABLgAECgQJCAACAAAAAA==.',
Ak='Akaishuuichi:BAAALgADCgYJBwAAAA==.Akorio:BAAALgAECgQJDAAAAA==.',
Al='Alachia:BAABLgAECn8hAAQGAAgJNiSYAQB+AgAGAAgJNiSYAQB+AgAHAAQJaRmuMAAaAQAIAAEJ7QoQHwA9AAAAAA==.Alahanna:BAAALgADCgQJBwAAAA==.Alanjackson:BAAALgAECgMJAwAAAA==.Alayssaria:BAABLgAECn8UAAIJAAYJTQn9SAAIAQAJAAYJTQn9SAAIAQAAAA==.Albedö:BAAALgAECgQJCQAAAA==.Alcya:BAAALgADCgEJAQAAAA==.Alebreath:BAAALgADCgIJAgAAAA==.Aleymental:BAAALgAECgIJAgAAAA==.Aliashan:BAAALgAECgcJEwAAAA==.Alixanya:BAAALgAECgQJBAAAAA==.Allegiant:BAAALgADCgIJAgABLgAECgUJCAACAAAAAA==.Alltaken:BAAALgAECgIJAgAAAA==.Almsivi:BAAALgADCgYJBgAAAA==.Aloram:BAAALgAECgcJDwAAAA==.Alorvoke:BAAALgAECgUJEQABLgAECgcJDwACAAAAAA==.Alpharetta:BAACLgAFFH8IAAIJAAQJWRJWCQBQAQAJAAQJWRJWCQBQAQAuAAQKfyEAAgkACAmSIsgIAAkDAAkACAmSIsgIAAkDAAAA.Alphasoldier:BAAALgAECggJEwAAAA==.Altared:BAAALgADCgEJAQAAAA==.Altia:BAAALgAFFAEJAQAAAA==.Alvya:BAAALgADCgkJEwAAAA==.',
Am='Ambrelamp:BAAALgADCgEJAQAAAA==.Amdrom:BAAALgAECgYJCgAAAA==.Amelie:BAAALgADCgcJBwAAAA==.Ameth:BAAALgAECgMJAwABLgAECgYJDwACAAAAAA==.Amorene:BAACLgAFFH8JAAIKAAMJ4h6YBQAMAQAKAAMJ4h6YBQAMAQAuAAQKfx8AAgoACAnwIlcFABwDAAoACAnwIlcFABwDAAAA.Amoryn:BAAALgAECgUJCQABLgAFFAMJCQAKAOIeAA==.Ampersand:BAAALgADCgMJAwAAAA==.Amphibiot:BAAALgAECgYJEAAAAA==.',
An='Anaraellea:BAAALgADCgkJIgAAAA==.Anarik:BAAALgAECgYJCgAAAA==.Anasaria:BAAALgADCgUJBgAAAA==.Andcheese:BAAALgAECgMJAwABLgAECgYJDQACAAAAAA==.Angellena:BAABLgAECn8UAAIGAAYJ9yOcAgBBAgAGAAYJ9yOcAgBBAgAAAA==.Anian:BAAALgADCgYJBgAAAA==.Ankøu:BAAALgADCgIJAgAAAA==.Anos:BAAALgAECgYJBwAAAA==.Antadin:BAABLgAECn8UAAIBAAYJowYWFwDUAAABAAYJowYWFwDUAAAAAA==.Anthenis:BAAALgADCgcJDgABLgAECgcJEwACAAAAAA==.',
Ap='Apothecares:BAAALgADCgUJBQAAAA==.Appoletta:BAAALgAECgUJCwAAAA==.',
Ar='Aranos:BAAALgADCgEJAQAAAA==.Arcani:BAAALgAECgQJBgAAAA==.Ardrenn:BAAALgADCgIJAgAAAA==.Aresion:BAABLgAECn8eAAMLAAgJmh/UDwC8AgALAAgJmh/UDwC8AgAMAAEJAADZlgAhAAAAAA==.Aridor:BAAALgADCgIJAgAAAA==.Arillian:BAAALgADCgcJBwAAAA==.Arkelium:BAAALgAECgUJDwAAAA==.Armagedda:BAAALgADCgMJAwAAAA==.Armas:BAAALgADCgIJAgAAAA==.Arrtemyss:BAAALgADCgYJBgAAAA==.Arthanus:BAABLgAECn8WAAINAAcJ1BKYOgC7AQANAAcJ1BKYOgC7AQAAAA==.',
As='Asenath:BAAALgAECgYJCwAAAA==.Ashadox:BAAALgADCgUJBQAAAA==.Asmodeus:BAAALgAECgYJBwABLgAECgYJEwACAAAAAA==.Astryx:BAAALgADCggJCAAAAA==.Asunna:BAAALgADCgMJAwAAAA==.Asáno:BAAALgADCgQJBAAAAA==.',
Au='Auramveyr:BAAALgADCgUJCAAAAA==.',
Aw='Awake:BAAALgAECgYJBgABLgAECgcJFgAOAIAkAA==.Awooga:BAAALgAECgMJAwAAAA==.',
Az='Azaezel:BAAALgAECgYJEwAAAA==.Azari:BAAALgAECgEJAQAAAA==.Azgalor:BAAALgAECgEJAQABLgAECgIJAwACAAAAAA==.Azurâ:BAAALgADCgYJBgAAAA==.',
Ba='Babychewie:BAABLgAECn8cAAIPAAgJdR7tAwDpAgAPAAgJdR7tAwDpAgAAAA==.Baconballs:BAAALgADCgYJBgAAAA==.Balla:BAAALgAECgUJDQAAAA==.Bambitee:BAABLgAECn8UAAMGAAYJ9AFaWADTAAAGAAYJ9AFaWADTAAAIAAEJoAOFIwAoAAAAAA==.Bambiteressa:BAAALgAECgEJAQABLgAECgYJFAAGAPQBAA==.Baravine:BAAALgAECgYJCwAAAA==.Barbarian:BAAALgAECgIJAgAAAA==.Batrazette:BAAALgADCgEJAQAAAA==.',
Be='Beamrooster:BAAALgADCgEJAQABLgAECggJHQAQABIfAA==.Beardeman:BAABLgAECn8VAAIRAAgJhB7HAgDCAgARAAgJhB7HAgDCAgAAAA==.Bearfoot:BAAALgADCgYJBgAAAA==.Beaross:BAAALgADCgUJBQAAAA==.Beeflomein:BAABLgAECn8cAAISAAgJwhXFBwB/AQASAAgJwhXFBwB/AQAAAA==.Bekzak:BAAALgADCgcJDAAAAA==.Beledros:BAAALgAECgYJBgABLgAECggJGgATAJkZAA==.Belf:BAAALgADCgcJDgAAAA==.Bellaamia:BAAALgADCgMJAwAAAA==.Benjamín:BAAALgAECgYJCQAAAA==.Benjourmind:BAABLgAECn8gAAITAAcJJh1oKQBcAgATAAcJJh1oKQBcAgAAAA==.Bennyguise:BAAALgAECgEJAQAAAA==.Bepito:BAAALgADCgMJAwAAAA==.Beset:BAAALgADCgEJAQAAAA==.Beyonder:BAAALgAECgYJBgAAAA==.',
Bi='Bibishow:BAAALgADCgYJBgAAAA==.Bigeasy:BAAALgADCgkJGQAAAA==.Birdie:BAAALgAECgEJAQAAAA==.Bitnarae:BAAALgADCgIJAQAAAA==.',
Bl='Blackkstaff:BAEBLgAECn8oAAMUAAkJTiBPBQA5AwAUAAgJRyRPBQA5AwAJAAMJPQh3HwBEAAAAAA==.Blacksong:BAAALgADCggJFgAAAA==.Blazied:BAAALgAECgUJDQAAAA==.Blinkd:BAABLgAECn8WAAIQAAYJhg2bMQACAQAQAAYJhg2bMQACAQAAAA==.Bluex:BAABLgAECn8hAAIVAAgJOyKPAAC0AgAVAAgJOyKPAAC0AgAAAA==.',
Bo='Bombad:BAAALgAECgQJBAABLgAFFAUJDAAQAKQiAQ==.Bombdots:BAABLgAECn8VAAMFAAcJpRu8NwAtAgAFAAcJpRu8NwAtAgAWAAEJmhIQawA8AAAAAA==.Bonelargeles:BAAALgAECgcJCAAAAA==.Boosh:BAABLgAECn8UAAIOAAgJCAtqdgCZAQAOAAgJCAtqdgCZAQAAAA==.Booyaah:BAACLgAFFH8MAAMKAAUJxBjZAgBaAQAKAAUJxBjZAgBaAQAXAAEJyQQxIABCAAAuAAQKfx0ABAoACQnvGSYXAF0CAAoACQnvGSYXAF0CAA8ABAmeElUgAM0AABcAAgnEEkpwAIEAAAAA.Boptimus:BAAALgAECgEJAQAAAA==.Borb:BAABLgAECn8bAAIMAAgJERz1HAA8AgAMAAgJERz1HAA8AgAAAA==.Bordem:BAABLgAECn8fAAIQAAkJWxlyBwAzAgAQAAkJWxlyBwAzAgAAAA==.',
Br='Branoria:BAAALgADCgIJAgAAAA==.Brazzadin:BAABLgAECn8cAAIBAAgJgBtIBAAsAgABAAgJgBtIBAAsAgAAAA==.Brigadester:BAACLgAFFH8JAAIYAAQJhxvdAACDAQAYAAQJhxvdAACDAQAuAAQKfxwAAhgACAnaJfQAAGgDABgACAnaJfQAAGgDAAAA.Brighthands:BAAALgAECgQJBQAAAA==.Broodin:BAAALgAECgYJBgAAAA==.Brownbearlp:BAAALgADCgQJBAAAAA==.Brøblast:BAAALgADCgcJDAABLgAECgEJAQACAAAAAA==.',
Bu='Bulgees:BAACLgAFFH8IAAIOAAMJkwHgEgDHAAAOAAMJkwHgEgDHAAAuAAQKfyMAAg4ACAldF5NPAAMCAA4ACAldF5NPAAMCAAAA.Bulgin:BAAALgAECgMJAwAAAA==.Bumblebeard:BAAALgAECgQJBAABLgAFFAUJDAAQAKQiAA==.Burritorukh:BAAALgAECgQJBAAAAA==.Buzzliteheal:BAAALgADCgEJAQAAAA==.',
['Bó']='Bób:BAAALgADCgIJAgAAAA==.',
Ca='Caladium:BAABLgAECn8WAAIWAAYJego4BQD4AAAWAAYJego4BQD4AAAAAA==.Calrisa:BAAALgAECgcJEwAAAQ==.Carltonhoot:BAAALgADCgYJBgAAAA==.Caspador:BAAALgADCgkJCQAAAA==.Cassadh:BAAALgADCgkJJQABLgAECgYJDwACAAAAAA==.Cassadk:BAAALgAECgYJCQABLgAECgYJDwACAAAAAA==.Cassawings:BAAALgAECgYJDwAAAA==.Castatic:BAAALgAECgIJAgAAAA==.Cathedral:BAAALgADCgMJAwAAAA==.Cauuk:BAAALgADCgEJAQAAAA==.Cawksnatcher:BAAALgAECgEJAQAAAA==.Caythithe:BAAALgADCgEJAQABLgADCgYJBgACAAAAAA==.',
Ce='Celaryn:BAAALgADCgEJAQAAAA==.Celestria:BAAALgAECgcJEgAAAA==.Celna:BAAALgAECgUJEwAAAA==.Celyssia:BAAALgAECgYJEgAAAA==.Cernos:BAAALgAECgIJBAAAAA==.',
Ch='Chachambre:BAAALgADCgEJAQABLgADCgEJAQACAAAAAA==.Chanceidari:BAAALgADCgEJAQAAAA==.Chaoticmaage:BAAALgADCgMJAwAAAA==.Chaox:BAAALgADCgYJCgAAAA==.Cheerio:BAAALgAECgQJBgAAAA==.Chepoof:BAAALgADCgcJBwAAAA==.Chickamuerta:BAAALgADCgEJAQAAAA==.Chigasm:BAAALgAECgEJAQAAAA==.Chilleagle:BAAALgAECgEJAQAAAA==.Chodiefoster:BAAALgADCgEJAQAAAA==.Chorale:BAAALgAECgMJAwAAAA==.Choup:BAAALgADCgUJBQAAAA==.Chronobog:BAAALgAECgYJEQAAAA==.Chronus:BAAALgAECgEJAQABLgAECggJEQACAAAAAA==.Cháncellor:BAABLgAECn8hAAIZAAgJnyRuAADcAgAZAAgJnyRuAADcAgAAAA==.Chïchï:BAAALgAECgYJDQAAAA==.',
Ci='Cindervorn:BAAALgADCgEJAQAAAA==.Cipher:BAAALgADCgEJAQAAAA==.',
Cl='Cleaveland:BAAALgAECgUJBQAAAA==.Clenton:BAAALgADCgkJDAAAAA==.Cloudstrike:BAAALgAECgEJAQAAAA==.Clömp:BAABLgAECn8VAAIJAAcJiRDvMwBwAQAJAAcJiRDvMwBwAQAAAA==.',
Co='Col:BAAALgADCgQJBQAAAA==.Concede:BAAALgAECgcJBwAAAA==.Coob:BAAALgAECgUJBQABLgAECggJGwAMABEcAA==.Corben:BAABLgAECn8hAAIQAAgJPiI+BgBLAgAQAAgJPiI+BgBLAgAAAA==.Corstus:BAAALgADCgIJAgAAAA==.Covenants:BAAALgAECgMJAwAAAA==.Cowhide:BAAALgADCggJCAAAAA==.',
Cr='Craru:BAAALgADCgIJAgAAAA==.Crusadis:BAAALgAECgEJAQAAAA==.Crusk:BAAALgAECgYJDgAAAA==.',
Cs='Csg:BAAALgAECgYJEwAAAA==.',
Cu='Cubes:BAAALgAECgYJEAAAAA==.Cutepony:BAAALgADCgcJDAAAAA==.',
Cy='Cyanred:BAABLgAECn8aAAIVAAgJTSOUAACwAgAVAAgJTSOUAACwAgAAAA==.Cyclopteryx:BAAALgAECgUJCQAAAA==.Cyndrien:BAAALgADCgEJAQAAAA==.',
['Cé']='Cérnunnos:BAABLgAECn8bAAQLAAgJTA/gRQCZAQALAAcJTA/gRQCZAQAYAAYJvgn5BwA0AQAMAAUJ8QfZWQDcAAAAAA==.',
Da='Daemonslayer:BAAALgAECgQJBgAAAA==.Dafeng:BAAALgADCgcJCgAAAA==.Daftknight:BAABLgAECn8VAAMEAAcJ6BmsfQB/AQAEAAYJ/BesfQB/AQABAAcJPwsCRABnAQAAAA==.Daisycutter:BAABLgAECn8gAAIaAAgJ/By7AQAfAgAaAAgJ/By7AQAfAgAAAA==.Dakoo:BAAALgADCgYJBgAAAA==.Daluon:BAAALgAECgMJAwABLgAECgcJFQADAIkeAA==.Damnatrix:BAAALgADCgUJBQAAAA==.Dances:BAAALgAECgYJDgAAAA==.Dandelión:BAAALgADCgQJBAAAAA==.Dansknee:BAABLgAECn8UAAIGAAYJpxxCHwDmAQAGAAYJpxxCHwDmAQAAAA==.Danzeebee:BAAALgAECgYJBgAAAA==.Darach:BAAALgADCgkJIQAAAA==.Daravanthel:BAAALgAECgYJEgAAAA==.Darkgibbsy:BAAALgADCgQJBAAAAA==.Darkisdragon:BAAALgAECgcJEAAAAA==.Darklightt:BAAALgADCgUJBQAAAA==.Darkshrine:BAAALgADCgcJEQAAAA==.Darmorg:BAABLgAECn8gAAIOAAgJlBqUNABkAgAOAAgJlBqUNABkAgAAAA==.Darthaxe:BAAALgAECgYJDwAAAA==.Datassassin:BAAALgADCgIJAgABLgAECggJEwACAAAAAA==.Dathas:BAAALgADCgEJAQAAAA==.',
De='Deadmore:BAAALgAECgQJBQABLgAECgYJCgACAAAAAA==.Deathafix:BAAALgADCgEJAgAAAA==.Deathreigns:BAAALgAECgEJAQAAAA==.Deathstone:BAAALgADCgIJAgAAAA==.Deathwood:BAAALgADCgQJBAABLgAECggJGAANAKIhAA==.Decymel:BAAALgADCgUJBQAAAA==.Deegoddaem:BAAALgADCgkJFAAAAA==.Delamaze:BAAALgADCgUJCAABLgAECgYJCgACAAAAAA==.Delimore:BAAALgAECgMJAwABLgAECgYJCgACAAAAAA==.Delmore:BAAALgAECgQJCAABLgAECgYJCgACAAAAAA==.Delmoré:BAAALgADCgIJAgABLgAECgYJCgACAAAAAA==.Dembjuicy:BAAALgADCgkJFAAAAA==.Demonstuff:BAAALgAECgcJEQAAAA==.Derangederek:BAAALgADCgEJAQAAAA==.Devoutraven:BAAALgAECgQJCQAAAA==.',
Dh='Dharenar:BAABLgAECn8gAAITAAgJ5QvsHAAdAQATAAgJ5QvsHAAdAQAAAA==.',
Di='Diago:BAAALgADCgIJAgAAAA==.Diazepam:BAAALgADCgYJCgAAAA==.Dionysius:BAAALgAECgEJAQAAAA==.Dirgedread:BAAALgADCgcJCgAAAA==.Dirkfunk:BAAALgADCgQJBQAAAA==.Dirtytickle:BAAALgADCgEJAQAAAA==.Discy:BAAALgADCgEJAQAAAA==.Dixonciderr:BAAALgADCgIJAgABLgAECgcJFwAVANwgAA==.',
Dj='Djguckie:BAAALgAECgQJBwAAAA==.',
Do='Dohpee:BAAALgAECgYJBwAAAA==.Donkmaster:BAAALgADCgMJAwABLgAECggJIgAbAPojAA==.Donswamdi:BAAALgADCgEJAwAAAA==.Dontwannadie:BAAALgAECgEJAQAAAA==.Doomcore:BAABLgAECn8VAAIDAAcJiR5yCgAnAgADAAcJiR5yCgAnAgAAAA==.Dooper:BAAALgAECgMJBAAAAA==.',
Dr='Dracfear:BAAALgAECgUJCAAAAA==.Dragongor:BAAALgAECgcJDwAAAA==.Dragonsmight:BAAALgAECgYJCgAAAA==.Drayto:BAABLgAECn8WAAIYAAYJtRHgBgBPAQAYAAYJtRHgBgBPAQAAAA==.Dreamlilone:BAAALgAECgQJDwAAAA==.Dreamvore:BAAALgAECggJDgAAAA==.Drekarma:BAAALgADCgUJDQAAAA==.Drgreenlungz:BAAALgADCgMJAwAAAA==.Droknarr:BAAALgADCgEJAQAAAA==.Druidpk:BAAALgADCgUJBQAAAA==.',
Ds='Dspøøn:BAAALgAECgMJAwAAAA==.',
Du='Dualwield:BAABLgAECn8bAAMNAAcJuwkMFAD/AAANAAcJuwkMFAD/AAAcAAIJAQScFAA3AAAAAA==.Dukrogor:BAAALgADCgcJCAAAAA==.Dulamana:BAAALgAECgYJCgAAAA==.Dustobones:BAAALgAECggJDQAAAA==.',
Dw='Dwee:BAAALgADCgEJAQAAAA==.Dweedy:BAAALgAECgQJBgAAAA==.',
['Dá']='Dánoninho:BAAALgAECgcJEAAAAA==.',
Ec='Ecnarol:BAAALgADCgEJAQAAAA==.',
Ee='Eelly:BAAALgADCgcJEwAAAA==.Eellyqt:BAAALgADCgYJBwAAAA==.',
Eh='Ehlyza:BAAALgADCgIJAgAAAA==.',
Ei='Eiddoel:BAAALgADCgEJAQAAAA==.Eirlight:BAAALgADCgUJCgAAAA==.Eirwin:BAAALgADCgcJCQAAAA==.Eiynta:BAAALgADCgQJBAAAAA==.',
El='Elekktrah:BAAALgAECggJEQAAAA==.Elfcare:BAAALgAECgUJBQAAAA==.Elftroll:BAAALgAECgcJEQAAAA==.Eliyana:BAABLgAECn8WAAIJAAYJyBGiCwAzAQAJAAYJyBGiCwAzAQAAAA==.Elsiñd:BAABLgAECn8VAAIGAAYJliKGAwAWAgAGAAYJliKGAwAWAgAAAA==.',
Em='Emberdk:BAACLgAFFH8SAAIOAAUJoxBbCACOAQAOAAUJoxBbCACOAQAuAAQKfy8AAg4ACQmTINAAAPgCAA4ACQmTINAAAPgCAAAA.Emojones:BAAALgADCgcJDwABLgAECgUJCAACAAAAAA==.',
En='Enilecram:BAAALgAECgEJAQAAAA==.',
Er='Errythang:BAAALgADCgEJAQAAAA==.Eryndorn:BAAALgAECgMJAwAAAA==.',
Es='Esarà:BAAALgADCgEJAQAAAA==.Essenne:BAAALgAECgEJAQABLgAECgYJFAAJAE0JAA==.',
Et='Ethrit:BAAALgAECgQJBQAAAA==.',
Eu='Eunys:BAAALgAECgEJAQAAAA==.',
Ev='Evonse:BAAALgADCgYJBgAAAA==.',
Ey='Eyonates:BAAALgAECgYJDAAAAA==.',
Ez='Ezzrra:BAAALgAECgYJDgAAAA==.',
Fa='Fadesweep:BAAALgADCgUJBgAAAA==.Faillock:BAACLgAFFH8JAAIFAAUJRAtICAA/AQAFAAUJRAtICAA/AQAuAAQKfx8AAwUACQlIGdxLAOUBAAUACAlAGNxLAOUBABYABQkBF9IgAE0BAAAA.Falora:BAAALgAECgQJBgAAAA==.Fangshot:BAABLgAECn8WAAILAAYJRB6dNgDUAQALAAYJRB6dNgDUAQAAAA==.Farukk:BAAALgAECgkJDQAAAA==.Fateldeath:BAAALgAECgMJBgAAAA==.Fatty:BAAALgADCgYJAQAAAA==.Faweng:BAAALgADCgUJBQAAAA==.',
Fe='Fearlily:BAAALgADCgUJBQABLgAECgcJAgACAAAAAA==.Feldwn:BAAALgADCgYJDwAAAA==.Felilly:BAAALgAECgcJAgAAAA==.Felmama:BAAALgADCgcJCAAAAA==.Felraux:BAAALgADCgkJJAAAAA==.Fengbao:BAAALgAECgYJEwAAAA==.Feyden:BAAALgADCgEJAQAAAA==.',
Fi='Finnior:BAAALgADCgcJDgAAAA==.Fionnaghuala:BAAALgADCgYJDAABLgAECgQJDwACAAAAAA==.Firedemon:BAAALgAECgMJAwAAAA==.Fireog:BAAALgAECgIJAgAAAA==.',
Fl='Flambe:BAAALgADCgEJAQAAAA==.Flute:BAABLgAECn8UAAIZAAYJNRtlIADTAQAZAAYJNRtlIADTAQAAAA==.',
Fo='Footloose:BAAALgAECgMJCAAAAA==.Forrsakiin:BAAALgAECgIJAwAAAA==.',
Fr='Frankiie:BAABLgAECn8VAAIJAAYJbQfyEQDYAAAJAAYJbQfyEQDYAAAAAA==.Franky:BAACLgAFFH8GAAIFAAQJUSEeAwCAAQAFAAQJUSEeAwCAAQAuAAQKfxsAAwUACAnQI7QmAHcCAAUABwnQI7QmAHcCABYABAksH08dAGQBAAAA.Frayden:BAAALgAECgYJDAAAAA==.Fraydinn:BAAALgADCgYJBgAAAA==.Frieren:BAAALgADCgMJAwAAAA==.Frogprincess:BAAALgADCgkJGQAAAA==.Frontdeboeuf:BAAALgAECgUJDgAAAA==.Frostwrought:BAAALgAECgEJAQAAAA==.Frozaller:BAAALgADCgcJDQAAAA==.',
Fu='Fuilsidhe:BAAALgAECgUJDAAAAA==.Furricane:BAAALgADCgcJBwAAAA==.',
Fy='Fyc:BAAALgAECgQJBwAAAA==.',
Ga='Gadios:BAACLgAFFH8FAAIRAAQJOB6PAABqAQARAAQJOB6PAABqAQAuAAQKfyoAAxEACAn9H68CAMcCABEACAn9H68CAMcCABoAAQk6DeJoAEEAAAAA.Gaivnion:BAAALgAECgQJBQAAAA==.Galagrond:BAAALgAECgEJAgAAAA==.Galdrelis:BAAALgAECgMJBQAAAA==.Gamba:BAAALgADCgUJBQAAAA==.Garfna:BAAALgAECgQJBgAAAA==.Garfrost:BAAALgAECgIJAgAAAA==.Gargag:BAAALgADCgMJAwAAAA==.Gazania:BAAALgAECgEJAgAAAA==.',
Ge='Gearlan:BAAALgADCgEJAQABLgAECgIJBAACAAAAAA==.Geayd:BAAALgADCgQJBQAAAA==.Gentsiem:BAAALgADCgMJAwAAAA==.Gequ:BAAALgAECgMJAwAAAA==.',
Gh='Ghemanis:BAAALgAECgQJBQAAAA==.Ghoulgamesh:BAAALgADCgEJAQAAAA==.Ghouliegarn:BAAALgADCgYJBgAAAA==.',
Gi='Gidget:BAAALgADCgMJAwAAAA==.Gingyclone:BAAALgADCgEJAQAAAA==.Ginsû:BAAALgAECgEJAQAAAA==.Gizzardo:BAAALgADCgkJCQABLgAECgcJCwACAAAAAA==.Gizzimo:BAAALgADCgIJAgAAAA==.',
Gl='Glaon:BAAALgAECgYJDAAAAA==.',
Go='Goldensword:BAAALgADCgUJBQAAAA==.Goleafs:BAAALgAECgEJAgAAAA==.Goobr:BAABLgAECn8XAAIOAAcJQh45CwDNAQAOAAcJQh45CwDNAQAAAA==.Goover:BAAALgAECgUJBQAAAA==.Gordy:BAAALgADCgcJEwAAAA==.Gorthiaz:BAAALgADCgUJBwAAAA==.Gothtotem:BAAALgADCgUJCAAAAA==.',
Gr='Grafvitnir:BAAALgAECgMJAwAAAA==.Grezgara:BAAALgAECgYJDgAAAA==.Grimir:BAAALgAECgMJAwAAAA==.Grimoldone:BAAALgAECgQJBgAAAA==.Grimverdict:BAAALgAECggJEwAAAA==.Grinderrg:BAABLgAECn8VAAMdAAcJvAzDDwAUAQAeAAYJ6QilOQBJAQAdAAUJHgzDDwAUAQAAAA==.Grippysock:BAAALgADCgMJAwAAAA==.Gripsalot:BAAALgADCgUJBQAAAA==.Grommashryon:BAAALgADCgEJAQAAAA==.Groundbeef:BAACLgAFFH8FAAMGAAQJJAPPDQCPAAAGAAIJMQTPDQCPAAAHAAIJFwKQFQCIAAAuAAQKfxQABAcACAn1FtoTAA4CAAcABwmdGdoTAA4CAAYABwnkCpw3AF4BAAgAAgkqDwBVAG8AAAAA.Grumbledore:BAACLgAFFH8MAAIQAAUJpCK+EwB8AQAQAAUJpCK+EwB8AQAuAAQKfx4AAhAACAk1JHURAD8DABAACAk1JHURAD8DAAAA.Grumbler:BAABLgAFFH8FAAIFAAMJIRs1DQAJAQAFAAMJIRs1DQAJAQABLgAFFAUJDAAQAKQiAA==.',
Gu='Guttzes:BAAALgAECgEJAQAAAA==.',
Gw='Gwonk:BAAALgAECgcJDgAAAA==.',
['Gó']='Góllum:BAAALgADCgYJBwAAAA==.',
Ha='Hairbend:BAAALgAECgYJEQAAAA==.Hakusorr:BAAALgAECgQJCgAAAA==.Hakzol:BAABLgAECn8cAAIIAAYJuB4pCAB1AQAIAAYJuB4pCAB1AQAAAA==.Halabrand:BAAALgADCgUJBQAAAA==.Halidril:BAABLgAECn8XAAMBAAYJeSM0BAAvAgABAAYJeSM0BAAvAgAEAAMJChtT2ADbAAAAAA==.Hanaaria:BAAALgADCgEJAQAAAA==.Hardjac:BAAALgADCgEJAQAAAA==.Haribo:BAABLgAECn8VAAIJAAgJxhSBIwDhAQAJAAgJxhSBIwDhAQAAAA==.Harmless:BAABLgAFFH8UAAIfAAcJihStAAAFAgAfAAcJihStAAAFAgAAAA==.Harpactira:BAAALgAECgIJAgAAAA==.Hasel:BAAALgAECgYJBwAAAA==.Hashbrowns:BAAALgADCgEJAQAAAA==.Hawkhunter:BAAALgAECgYJEQAAAA==.Hawkvullock:BAAALgADCgIJAQAAAA==.',
He='Heartblast:BAAALgAECgYJDQAAAA==.Hearthbunny:BAAALgADCgEJAQAAAA==.Heat:BAAALgADCgcJBwAAAA==.Heavén:BAABLgAECn8XAAIEAAkJaBnUGgDIAgAEAAkJaBnUGgDIAgAAAA==.Hegs:BAABLgAECn8eAAINAAgJKhBPLAADAgANAAgJKhBPLAADAgAAAA==.Helaku:BAABLgAECn8jAAMJAAgJvxuKAgAjAgAJAAgJvxuKAgAjAgAUAAQJ8RIIewDoAAAAAA==.Helanira:BAAALgAECgQJDgAAAA==.Hellion:BAAALgADCgYJCwAAAA==.Heneru:BAAALgAECgMJBgAAAA==.Hevharuk:BAABLgAECn8UAAIgAAYJDQ+JJABUAQAgAAYJDQ+JJABUAQAAAA==.Hewk:BAAALgADCgkJJAAAAA==.',
Ho='Hogslight:BAAALgADCgkJCQAAAA==.Holyitis:BAAALgAECgIJAQAAAA==.Holymoo:BAAALgADCgkJEwAAAA==.Horsegirl:BAAALgAECgMJAwAAAA==.',
Hu='Hudsonpally:BAAALgADCgYJBgAAAA==.Huevudo:BAAALgAECgQJBAAAAA==.Huntrhen:BAABLgAECn8UAAMMAAYJAyFFJAACAgAMAAYJ9h1FJAACAgALAAIJuiTUhADaAAAAAA==.',
['Hä']='Hälcÿon:BAAALgADCgUJBwAAAA==.',
Ia='Iamgoodforu:BAAALgADCgYJCgAAAA==.Iamsin:BAAALgADCgYJBwAAAA==.',
Ib='Ibby:BAABLgAECn8aAAQgAAcJIxPPGQC+AQAgAAcJIxPPGQC+AQAhAAQJxw5rFQCrAAAiAAIJowJGOwBBAAAAAA==.',
Ic='Icaintseeyou:BAAALgADCgkJCQAAAA==.',
Id='Idarknessl:BAAALgAECgcJEgABLgAFFAQJCQAfAA4WAA==.',
Il='Illaedra:BAAALgAECgYJDgAAAA==.Illidares:BAAALgAECgYJCgABLgAECggJHgALAJofAA==.Illusius:BAAALgADCgcJDQABLgAECggJDwACAAAAAA==.Illyria:BAAALgADCgcJBwAAAA==.Ilyssia:BAAALgADCgEJAQAAAA==.',
Im='Imwarminside:BAAALgAECgYJBgABLgAFFAMJBgAZAMsZAA==.',
In='Inneranguish:BAABLgAECn8YAAMjAAcJpBaYBgCtAQAjAAYJGRaYBgCtAQAOAAUJ2RG9rAAoAQAAAA==.Inshambles:BAAALgADCgMJAwAAAA==.Intervention:BAAALgADCgMJBgAAAA==.Introitus:BAAALgAECgIJAgAAAA==.',
Ip='Ipa:BAAALgADCgQJBQAAAA==.',
Ir='Iradicos:BAAALgAECgYJDgAAAA==.Ireliae:BAAALgAECgYJCQABLgAECggJJQAVADsbAA==.',
Is='Isaria:BAAALgAECgMJAwAAAA==.Iside:BAAALgAECgQJCgAAAA==.Isindril:BAABLgAECn8gAAIJAAgJyQ1KCABvAQAJAAgJyQ1KCABvAQAAAA==.Isnacky:BAAALgAECgUJBgAAAA==.',
Ja='Jackforever:BAAALgADCgcJCAAAAA==.Jadan:BAAALgAECgEJAQAAAA==.Jadianrogue:BAAALgAFFAEJAQAAAA==.Jamaster:BAAALgADCgcJBwAAAA==.Jameswarren:BAAALgAECgMJAwAAAA==.Jarco:BAECLgAFFH8FAAIZAAIJyiGlCQDOAAAZAAIJyiGlCQDOAAAuAAQKfyQAAhkACQljJEEBAK4DABkACQljJEEBAK4DAAAA.Jayyb:BAABLgAECn8cAAIEAAgJ2RrnBgAgAgAEAAgJ2RrnBgAgAgAAAA==.Jazaden:BAAALgAECgEJAQAAAA==.',
Je='Jehüty:BAAALgAECgEJAQAAAA==.Jeneralizer:BAAALgAECgYJCAAAAA==.Jenntly:BAABLgAECn8bAAMUAAgJqg83QQCdAQAUAAgJqg83QQCdAQAJAAcJ8ANCTgDwAAABLgAECggJJQAVADsbAA==.Jessalinda:BAAALgADCgcJBwAAAA==.Jessibel:BAAALgADCgcJDQAAAA==.',
Jg='Jgwentworth:BAABLgAECn8iAAQbAAgJ+iMZAADPAgAbAAgJTyMZAADPAgAFAAgJyyENHACtAgAWAAEJAAA2ZgBDAAAAAA==.',
Ji='Jirasia:BAABLgAECn8hAAMLAAgJuyQqAQDJAgALAAgJuyQqAQDJAgAMAAUJXxDSUwD7AAAAAA==.Jizzycooch:BAAALgADCgUJBQAAAA==.',
Jm='Jmart:BAACLgAFFH8FAAIQAAMJTg8mMAD0AAAQAAMJTg8mMAD0AAAuAAQKfxYAAhAABgkpHkIRALgBABAABgkpHkIRALgBAAAA.',
Jo='Joedalok:BAAALgAECgEJAQABLgAECgYJEwACAAAAAA==.Joedamonk:BAAALgAECgYJEwAAAA==.Johnpoggy:BAAALgADCgYJBgAAAA==.Joshtee:BAAALgADCgUJBQAAAA==.Joy:BAAALgAECgYJCQAAAA==.Joystick:BAAALgAECgIJAgAAAA==.',
Ju='Jundras:BAAALgAECgYJDgAAAA==.',
['Já']='Jádan:BAAALgADCgMJAwAAAA==.',
['Jö']='Jörd:BAAALgADCgUJBQAAAA==.',
Ka='Kaeladin:BAAALgADCgMJBgAAAA==.Kaessel:BAAALgAECgQJBAAAAA==.Kagam:BAAALgADCgMJAwAAAA==.Kageriyu:BAACLgAFFH8FAAINAAIJSxMtCQCzAAANAAIJSxMtCQCzAAAuAAQKfyUAAg0ACAnBHGUCAD4CAA0ACAnBHGUCAD4CAAAA.Kaidah:BAAALgADCgkJCQAAAA==.Kankan:BAAALgAECgYJCQAAAA==.Kankankan:BAAALgADCgMJAwAAAA==.Kanobrew:BAAALgAECgMJAwABLgAECgMJAwACAAAAAA==.Kanomoonbark:BAAALgADCgQJBwABLgAECgMJAwACAAAAAA==.Kanoslice:BAAALgADCgEJAQABLgAECgMJAwACAAAAAA==.Kanostalker:BAAALgAECgMJAwAAAA==.Kanowrath:BAAALgADCgMJAwABLgAECgMJAwACAAAAAA==.Kaokoh:BAAALgADCgcJDgAAAA==.Kaotik:BAAALgAECgEJAQAAAA==.Kaotika:BAAALgAECgQJDgAAAA==.Karaam:BAAALgADCgQJBAAAAA==.Katamune:BAABLgAECn8UAAIOAAgJpBoSEQCMAQAOAAgJpBoSEQCMAQAAAA==.Katrianna:BAAALgAECgEJAgAAAA==.Kaykat:BAAALgADCgcJCgAAAA==.Kayla:BAABLgAECn8XAAILAAcJxQ9YGwAjAQALAAcJxQ9YGwAjAQAAAA==.',
Ke='Keatøn:BAABLgAECn8UAAIfAAcJ5BWVJwB5AQAfAAcJ5BWVJwB5AQAAAA==.Kegsmash:BAAALgADCgMJAwAAAA==.Keilingg:BAAALgADCgcJAQAAAA==.Keira:BAAALgADCgEJAQAAAA==.Kelethius:BAABLgAECn8gAAMcAAgJBSROAADKAgAcAAgJpCNOAADKAgANAAUJ0iTxLAAAAgAAAA==.Kerelenn:BAAALgADCgUJBQAAAA==.Kesis:BAAALgADCgYJBwAAAA==.Kesthus:BAABLgAECn8nAAQTAAkJgRp+BgARAgATAAgJnRx+BgARAgARAAkJSRGxBwAJAgAaAAEJsR+EYQBcAAAAAA==.Kevneiros:BAAALgADCgcJBwAAAA==.Kezyah:BAAALgADCgkJDwAAAA==.',
Kh='Khatrina:BAAALgADCgYJBgAAAA==.Khârn:BAAALgADCgYJBgAAAA==.',
Ki='Kinkypinky:BAAALgADCgIJAgAAAA==.',
Kl='Kladrian:BAAALgAECggJCwAAAA==.Klassykaolok:BAAALgADCgQJBAAAAA==.Klaustralus:BAAALgAECgUJCQAAAA==.',
Ko='Kohcoh:BAAALgAECgUJDQAAAA==.Kojohaa:BAAALgAECgYJEwAAAA==.',
Kq='Kqn:BAAALgAECgcJCQAAAA==.',
Kr='Krystrasz:BAAALgAECgIJAgAAAA==.',
Ku='Kumjitsu:BAAALgADCgEJAgAAAA==.Kungflupanda:BAAALgAECgYJEgAAAA==.',
Ky='Kylø:BAAALgAECgYJBwAAAA==.Kynobi:BAAALgADCgQJBAAAAA==.Kytheria:BAAALgAECgYJDAAAAA==.',
['Kà']='Kàylee:BAAALgADCgcJDQAAAA==.',
['Kä']='Känkän:BAAALgAECgMJBAAAAA==.',
['Kï']='Kïller:BAAALgAECgEJAwAAAA==.',
La='Ladahlia:BAAALgADCgYJCQAAAA==.Ladorin:BAAALgAECgYJCgAAAA==.Lagaris:BAAALgAECgQJBgAAAA==.Lamue:BAAALgAECgkJCQAAAA==.Landregorn:BAAALgAECgkJAQAAAA==.Lastdance:BAAALgAFFAIJAgAAAA==.Laylaii:BAAALgAECgQJCgAAAA==.',
Ld='Ldycathlyn:BAAALgADCgQJAgAAAA==.',
Le='Leafmoreheal:BAAALgAECgEJAQAAAA==.Leficton:BAAALgAECgQJDAAAAA==.Levixus:BAAALgADCgEJAQAAAA==.Levola:BAAALgAECgQJCgAAAA==.Lexstrasza:BAAALgAECgYJEQAAAA==.',
Li='Licheternal:BAABLgAECn8lAAMVAAgJOxvBDgAhAgAOAAgJiRLURQAjAgAVAAcJHh7BDgAhAgAAAA==.Liesl:BAAALgAECgQJCAAAAA==.Lightwolves:BAABLgAECn8dAAMEAAkJ/CKlBACCAwAEAAkJ/CKlBACCAwABAAEJvgHolwAyAAAAAA==.Lilynuts:BAAALgAECgQJBAAAAA==.Limeaide:BAAALgAECgYJDQAAAA==.Linaelia:BAAALgAECgYJDwAAAA==.',
Lo='Lockgnome:BAAALgADCgcJDQAAAA==.Lonsoo:BAAALgAECgEJAQAAAA==.Lotharion:BAAALgAECgEJAQAAAA==.Lovelydeäth:BAABLgAECn8hAAMQAAgJAiKXBAByAgAQAAgJxx6XBAByAgAkAAcJySB1AwA3AgAAAA==.',
Lu='Lucifyr:BAAALgAECgUJBQAAAA==.Luku:BAAALgAECgQJBQAAAA==.Lunabloom:BAAALgADCgYJDAAAAA==.',
Ly='Lyandhris:BAAALgAECgYJDwAAAA==.Lyandrà:BAAALgAECgYJCgAAAA==.Lynedra:BAAALgADCgYJBgABLgAECgYJFwABAHkjAA==.',
['Lä']='Länthsä:BAAALgADCgEJAQAAAA==.',
['Lé']='Léf:BAABLgAECn8UAAIlAAYJdiSWCQCAAgAlAAYJdiSWCQCAAgAAAA==.',
['Lë']='Lëx:BAAALgAECgQJBAAAAA==.',
['Lí']='Lílyth:BAAALgADCgcJBwAAAA==.Lív:BAAALgAECgkJDQAAAA==.',
['Lï']='Lïukang:BAAALgADCgEJAQAAAA==.',
['Lü']='Lücid:BAAALgAECgIJAgAAAA==.',
Ma='Mach:BAAALgADCgUJBQAAAA==.Madussa:BAAALgADCgcJDAAAAA==.Magestika:BAAALgADCgcJCQAAAA==.Magul:BAAALgADCgEJAQAAAA==.Maimgor:BAAALgAECgYJDgAAAA==.Maioshi:BAAALgADCgYJBQAAAA==.Makellos:BAAALgADCgEJAQABLgAECgEJAQACAAAAAA==.Mako:BAAALgAECgIJAgAAAA==.Makubai:BAAALgADCgYJBgAAAA==.Malgainas:BAAALgAECgQJCAABLgAECgUJCAACAAAAAA==.Malisara:BAAALgADCgcJBwAAAA==.Maltorius:BAAALgADCgEJAgAAAA==.Malzahar:BAAALgADCgIJAgAAAA==.Mamamaya:BAAALgADCgcJBwAAAA==.Mangdragoon:BAAALgADCgUJBQAAAA==.Maniic:BAAALgADCgUJCAAAAA==.Marbgar:BAAALgADCgQJBQAAAA==.Marcëla:BAAALgAECgEJAQAAAA==.Marow:BAAALgADCgYJBgAAAA==.Mater:BAAALgADCgYJBgAAAA==.Mathirran:BAABLgAFFH8FAAIIAAMJewZNBgDTAAAIAAMJewZNBgDTAAAAAA==.Mato:BAAALgAECgcJEQAAAA==.Mattedemon:BAAALgAECgYJCQAAAA==.Mavralara:BAAALgADCgkJIgAAAA==.Mawea:BAAALgAECgcJEAAAAA==.Maxious:BAAALgAECgcJDAAAAA==.Maxverstotem:BAABLgAECn8VAAIKAAYJTSOQGQBKAgAKAAYJTSOQGQBKAgAAAA==.',
Mc='Mcfrown:BAAALgAECgIJAwAAAA==.Mchands:BAAALgAECgYJCQAAAA==.Mclight:BAABLgAECn8YAAMBAAgJ4SMxCwDGAgABAAgJ4SMxCwDGAgAEAAEJ/B0KPAE2AAAAAA==.',
Me='Mechybro:BAAALgADCgQJBAAAAA==.Medalux:BAAALgAECggJEQAAAA==.Megumïn:BAAALgAECgQJBQAAAA==.Meinfrau:BAABLgAECn8XAAISAAgJMRPJNAB7AQASAAgJMRPJNAB7AQAAAA==.Melvin:BAABLgAECn8YAAMhAAYJlx0mBgCZAQAhAAYJZBwmBgCZAQAiAAQJhByvHQBBAQABLgAECgcJFwAOAEIeAA==.Memnarc:BAAALgADCgMJAwAAAA==.Merenak:BAAALgAECgQJBAAAAA==.Metortun:BAAALgADCgYJAwAAAA==.',
Mi='Miauburger:BAACLgAFFH8GAAIZAAMJyxnmBgAKAQAZAAMJyxnmBgAKAQAuAAQKfygAAhkACQnAIdIAAJgCABkACQnAIdIAAJgCAAAA.Michaelpb:BAAALgADCgEJAQAAAA==.Mieca:BAAALgADCgEJAQAAAA==.Mildfire:BAAALgAECgIJAgAAAA==.Mimox:BAAALgADCgEJAQAAAA==.Minusfifty:BAAALgADCgQJBQAAAA==.Mirima:BAABLgAECn8VAAIUAAYJ9AloHQDLAAAUAAYJ9AloHQDLAAAAAA==.Mishona:BAAALgADCgkJFAAAAA==.Missfattits:BAAALgAECgQJBQABLgAECgYJEwACAAAAAA==.Missforcible:BAAALgAECgQJBQAAAA==.Mistchivús:BAAALgADCgcJCQAAAA==.',
Mk='Mkfilthy:BAAALgAECgMJBAAAAA==.Mkshty:BAAALgADCgUJBQABLgAECgMJBAACAAAAAA==.',
Mm='Mmizard:BAABLgAECn8WAAIQAAcJShWlFwCIAQAQAAcJShWlFwCIAQAAAA==.',
Mo='Modez:BAAALgADCgEJAQAAAA==.Mojowest:BAAALgAECgYJEwAAAA==.Molly:BAAALgAECgMJAwAAAA==.Monkness:BAABLgAFFH8JAAIfAAQJDha6AwBHAQAfAAQJDha6AwBHAQAAAA==.Moob:BAABLgAECn8UAAIJAAYJhCNnGABFAgAJAAYJhCNnGABFAgAAAA==.Mookkake:BAAALgADCgIJAwAAAA==.Moonfalls:BAAALgAECgUJCAAAAA==.Moonfyre:BAAALgADCgcJDgAAAA==.Moong:BAABLgAECn8YAAIJAAYJ2AETGQB2AAAJAAYJ2AETGQB2AAAAAA==.Moonkinn:BAACLgAFFH8GAAIJAAMJsge2BgDlAAAJAAMJsge2BgDlAAAuAAQKfyoAAwkACAkQHQ4CAEICAAkACAkQHQ4CAEICABQABwkMFsk9AKwBAAAA.Moosey:BAAALgADCgUJBQAAAA==.Moozda:BAAALgADCggJFQABLgAECggJIgAbAPojAA==.Morees:BAAALgAECgUJDwAAAA==.Moroc:BAAALgAECgEJAQAAAA==.',
Ms='Mstrjamus:BAAALgADCggJFwAAAA==.Mstrjonathan:BAAALgAECgUJCQAAAA==.',
Mu='Mungogo:BAAALgAECgYJEAAAAA==.Munke:BAAALgADCgcJDQABLgAFFAQJBQARADgeAA==.Murdermind:BAAALgAECgUJBgAAAA==.Murtagh:BAAALgADCgYJCQAAAA==.Mustybones:BAABLgAECn8hAAINAAgJHSCBAQBwAgANAAgJHSCBAQBwAgAAAA==.Mustärd:BAAALgADCgEJAQABLgAECggJIQAgAPEYAA==.',
My='Mylitledemom:BAAALgADCgMJAwAAAA==.Myree:BAAALgAECgEJAQABLgAECgcJEAACAAAAAA==.Myrolel:BAAALgAECgMJAwAAAA==.Mysteryspell:BAAALgAECgcJEgAAAA==.Mythilith:BAAALgADCgMJBQAAAA==.',
Na='Nachos:BAAALgAECgQJBwAAAA==.Nagrand:BAAALgAECgYJBwAAAA==.Nakota:BAAALgADCgMJAwAAAA==.Nakï:BAAALgADCgIJAgAAAA==.Nalaria:BAAALgADCgQJBAAAAA==.Narcoleptik:BAAALgAECgYJBwAAAA==.Nastagdan:BAAALgAECgQJBQAAAA==.Nastiee:BAAALgADCgQJBAAAAA==.Nausea:BAAALgAECgUJBwAAAA==.',
Ne='Necrofeelsya:BAABLgAECn8XAAIVAAcJ3CBCDQA6AgAVAAcJ3CBCDQA6AgAAAA==.Neelam:BAAALgADCgYJDgAAAA==.Neirit:BAAALgAECgEJAQAAAA==.Nelf:BAAALgADCgEJAQAAAA==.Neravar:BAAALgADCgYJCAAAAA==.Nezot:BAAALgADCgcJCAAAAA==.',
Ng='Ngorongoro:BAAALgAECgMJAwAAAA==.',
Ni='Niame:BAAALgAECgQJBQAAAA==.Nifty:BAABLgAECn8YAAIFAAgJChPaRgD2AQAFAAgJChPaRgD2AQAAAA==.Nightmæres:BAAALgADCgIJAgAAAA==.Nightæres:BAAALgAECgQJCAABLgAECggJHgALAJofAA==.Nindar:BAAALgAECgEJAQAAAA==.Ninjakitten:BAABLgAECn8XAAIUAAcJig16EwAuAQAUAAcJig16EwAuAQAAAA==.',
No='Noctiis:BAAALgADCgMJAwAAAA==.Noiscopiamo:BAABLgAECn8XAAIMAAcJ8hafLADHAQAMAAcJ8hafLADHAQAAAA==.Nolctum:BAAALgADCgkJDAAAAA==.Nollets:BAAALgAECgMJBAAAAA==.Noquemacuh:BAAALgAECgEJAQAAAA==.Noraviae:BAAALgADCgcJCwAAAA==.Novamage:BAAALgAECgcJDQAAAA==.Nox:BAABLgAECn8VAAIKAAcJaxjcJQD8AQAKAAcJaxjcJQD8AQAAAA==.',
Ny='Nyxiis:BAAALgAECgYJCwAAAA==.Nyxxen:BAAALgADCgUJBQAAAA==.',
['Nì']='Nìcø:BAAALgADCgIJAQAAAA==.',
Oa='Oashian:BAABLgAECn8mAAIDAAkJOh+RAACVAgADAAkJOh+RAACVAgAAAA==.',
Ob='Obeseheals:BAAALgAECgYJBwABLgAECggJHQAQABIfAA==.',
Od='Oddmaen:BAAALgADCgIJAwAAAA==.',
Ol='Oladra:BAAALgADCgMJAwAAAA==.Oldschool:BAAALgADCgcJBwAAAA==.',
On='Onepounce:BAAALgADCgcJDAAAAA==.Onesummon:BAAALgADCgcJCQAAAA==.Onlyhandz:BAAALgAECgMJBQABLgADCgYJCgACAAAAAA==.Onslaught:BAAALgADCgcJDgAAAA==.Onzo:BAAALgADCgIJAgAAAA==.',
Or='Orran:BAAALgAFFAIJAgABLgAFFAQJCwAOANMXAA==.Orrindan:BAABLgAECn8YAAISAAYJ7xdZDAArAQASAAYJ7xdZDAArAQAAAA==.',
Os='Osy:BAAALgADCgkJEgAAAA==.',
Oz='Ozempic:BAABLgAECn8hAAMgAAgJ8RiuEQAiAgAgAAgJ8RiuEQAiAgAhAAUJAQ7SCwAqAQAAAA==.',
Pa='Paimeí:BAAALgADCgcJEgAAAA==.Pallieguy:BAABLgAECn8XAAIDAAcJLBqvAwCMAQADAAcJLBqvAwCMAQAAAA==.Pandà:BAAALgAECgUJCAAAAA==.Patience:BAAALgAECgQJBwAAAA==.',
Pe='Penetrate:BAAALgAECgQJBAABLgAECgkJIgAOAHoZAQ==.Penster:BAABLgAECn8iAAIOAAkJehnzAgB8AgAOAAkJehnzAgB8AgAAAA==.Pepis:BAAALgAECgYJDAAAAA==.Pewpewrawr:BAAALgADCgYJBgAAAA==.',
Ph='Phelpz:BAAALgADCgcJCAAAAA==.Phett:BAAALgADCgYJCQAAAA==.Philippe:BAAALgAECgYJBgAAAA==.Philo:BAABLgAECn8WAAImAAgJIxDqEwByAQAmAAgJIxDqEwByAQAAAA==.Phineasflame:BAAALgAECgQJBgAAAA==.Phistadk:BAAALgAECgQJBgAAAA==.Phorsworn:BAAALgAECgYJDgAAAA==.',
Pi='Picard:BAAALgAECgEJAgABLgAECggJIQAUAGAdAA==.Piffjones:BAAALgADCggJCgAAAA==.Pikkin:BAAALgADCgkJJAAAAA==.Pincushion:BAABLgAECn8VAAIfAAcJvBjNGAD4AQAfAAcJvBjNGAD4AQAAAA==.Pine:BAAALgADCgQJBQAAAA==.Pisslopez:BAAALgADCggJCAAAAA==.Pixn:BAAALgAECgYJCgAAAA==.',
Pl='Pladin:BAAALgAECgEJAQAAAA==.Plagues:BAAALgAECgEJAQAAAA==.Plaidpally:BAAALgAECgYJEAAAAA==.Plasticmars:BAAALgAECgMJBgAAAA==.Platînum:BAABLgAECn8VAAIEAAgJKB+GHQC5AgAEAAgJKB+GHQC5AgAAAA==.',
Po='Pocketmommy:BAAALgAECgQJDAAAAA==.Postmortim:BAAALgADCgkJJQAAAA==.Potaters:BAAALgADCgkJFwAAAA==.Poundtownjr:BAAALgAECgYJDgAAAA==.',
Pr='Pryda:BAAALgAECgQJCAAAAA==.',
Pu='Pu:BAAALgAECgUJDwAAAA==.Punchypoons:BAAALgADCgYJDgABLgAECgcJCwACAAAAAA==.Purplejelly:BAAALgADCgkJEwAAAA==.',
Py='Pyroice:BAAALgADCgUJBgAAAA==.',
['Pó']='Póe:BAABLgAECn8UAAITAAYJzBniYQB7AQATAAYJzBniYQB7AQAAAA==.',
Qi='Qiteag:BAAALgAECgQJCAABLgAECgYJFwAmAPYlAA==.',
Qu='Quaxly:BAAALgADCgEJAQAAAA==.Quel:BAAALgAECgQJCAAAAA==.Quelanne:BAAALgADCgEJAQAAAA==.Quintessence:BAAALgAECgMJBAABLgAECgYJFwAmAPYlAA==.',
Qz='Qzymandia:BAABLgAECn8XAAImAAYJ9iUIBgCgAgAmAAYJ9iUIBgCgAgAAAA==.',
Ra='Raddit:BAAALgADCggJDgABLgAECgYJDAACAAAAAA==.Raeef:BAAALgADCgEJAQAAAA==.Raeorc:BAAALgAECgEJAQAAAA==.Raestra:BAAALgADCggJCgABLgAECgQJDwACAAAAAA==.Rahabuul:BAAALgADCgEJAQAAAA==.Raiovac:BAAALgADCgQJBAAAAA==.Raiset:BAAALgADCgcJDwAAAA==.Raithlyn:BAAALgADCgkJIgAAAA==.Rambling:BAAALgAECgYJDQAAAA==.Ranthorn:BAAALgAECgMJBQAAAA==.Raphael:BAABLgAECn8UAAIEAAcJcQwcHgA6AQAEAAcJcQwcHgA6AQAAAA==.Rawani:BAAALgAECgQJDwAAAA==.Rawrp:BAABLgAECn8XAAIHAAcJlRrVAgAoAgAHAAcJlRrVAgAoAgAAAA==.Raziel:BAAALgADCgEJAQAAAA==.Razormage:BAABLgAECn8WAAIQAAgJ1B2JLwC0AgAQAAgJ1B2JLwC0AgAAAA==.Raô:BAABLgAECn8XAAIXAAgJIRHzCQBdAQAXAAgJIRHzCQBdAQAAAA==.',
Re='Rekkonk:BAABLgAFFH8GAAISAAMJ9RptCADhAAASAAMJ9RptCADhAAAAAA==.Rekue:BAAALgAECgYJEAAAAA==.Renli:BAAALgADCgYJBgAAAA==.Retread:BAAALgADCgcJBwAAAA==.Rezentful:BAAALgAECgcJEgAAAA==.',
Rh='Rhiandali:BAABLgAECn8YAAIaAAYJ3RckJQCVAQAaAAYJ3RckJQCVAQAAAA==.Rhonna:BAAALgAECgYJEQAAAA==.Rhyxi:BAAALgAECgcJEwAAAA==.',
Ri='Rinadratha:BAAALgADCgEJAQAAAA==.Riskybiskit:BAAALgADCgEJAQAAAA==.Rizon:BAAALgAECgIJAgAAAA==.',
Ro='Rodastir:BAAALgADCgcJEAABLgAECgQJBAACAAAAAA==.Roidedraiden:BAAALgAECgEJAQAAAA==.Rollim:BAAALgAECgEJAQAAAA==.Rollis:BAAALgAECgYJEQAAAA==.Romuless:BAAALgAECgUJCAAAAA==.Ropes:BAACLgAFFH8GAAIEAAMJwxf1EwAIAQAEAAMJwxf1EwAIAQAuAAQKfygAAwQACAnyI3cFAEACAAQACAnyI3cFAEACAAEAAgm8CfSCAGwAAAAA.Roselyne:BAAALgADCgMJAwAAAA==.Rowwyn:BAAALgADCgYJBgAAAA==.',
Ru='Runedorgasm:BAAALgAFFAIJAgAAAA==.Runekeeper:BAAALgADCgcJDAABLgADCgkJEwACAAAAAA==.Ruskuss:BAAALgADCgUJBQABLgAECgQJBwACAAAAAA==.Rusâ:BAABLgAECn8WAAIPAAYJmRpSBABuAQAPAAYJmRpSBABuAQAAAA==.',
['Rá']='Rádágast:BAAALgADCgYJBgAAAA==.',
['Rå']='Råin:BAAALgADCgYJBgAAAA==.',
['Rè']='Rèvan:BAAALgAECgIJAgAAAA==.',
['Rì']='Rìncewind:BAAALgAECgYJDQAAAA==.',
Sa='Saintorum:BAAALgAECgEJAQAAAA==.Salandria:BAABLgAECn8hAAIEAAkJfw+DXADNAQAEAAkJfw+DXADNAQAAAA==.Saliri:BAAALgADCgQJCAAAAA==.Samalander:BAAALgADCgkJHgAAAA==.Sandbagnight:BAAALgADCgcJBwAAAA==.Sandz:BAAALgAECgQJBAAAAA==.Sane:BAAALgADCgkJGQAAAA==.Sanlien:BAAALgAECgcJEwAAAA==.Saraiya:BAAALgADCgYJBgAAAA==.Satake:BAABLgAECn8fAAMWAAgJxxxKEQDDAQAFAAcJBRyQNQA2AgAWAAYJyxtKEQDDAQAAAA==.Satakourer:BAAALgADCgcJBwABLgAECggJHwAWAMccAA==.Sather:BAAALgAECgcJDAAAAA==.Satisfactree:BAABLgAECn8hAAIUAAgJYB2ZAwBjAgAUAAgJYB2ZAwBjAgAAAA==.Satsa:BAABLgAECn8YAAIFAAgJ4xyXFwDHAgAFAAgJ4xyXFwDHAgAAAA==.Sauruman:BAAALgAECggJDgAAAA==.Saushie:BAAALgAECgMJAwAAAA==.Savagedoodle:BAACLgAFFH8PAAIFAAQJoBrbDQAFAQAFAAQJoBrbDQAFAQAuAAQKfysAAwUACQl+IVACAIYCAAUACQl+IVACAIYCABYAAgnBGEVQAH0AAAAA.Sayin:BAAALgADCgIJAgAAAA==.',
Sc='Scooters:BAAALgAECgQJCAAAAA==.Scrank:BAAALgADCgEJAQAAAA==.',
Se='Seidhra:BAABLgAECn8VAAIKAAYJuBLZDgBTAQAKAAYJuBLZDgBTAQAAAA==.Seiza:BAAALgAECgYJDgAAAA==.Selenax:BAAALgAECgEJAQABLgAECgQJDwACAAAAAA==.Seliel:BAAALgAECgYJDQAAAA==.Sendports:BAAALgADCgYJBgAAAA==.Seriola:BAAALgAECgEJAQAAAA==.Serrated:BAAALgAECgUJBwAAAA==.Seykai:BAAALgADCgQJBQAAAA==.',
Sh='Shaburger:BAAALgAECgUJDAABLgAFFAMJBgAZAMsZAA==.Shadowfénix:BAAALgAECgkJCAAAAA==.Shaienne:BAABLgAECn8ZAAMOAAgJDBaEFABuAQAOAAgJDBaEFABuAQAjAAUJ7A1oCwAIAQAAAA==.Shammyywow:BAAALgADCgYJBgAAAA==.Shamproof:BAAALgADCgQJBAAAAA==.Shandiin:BAAALgAECgYJBgABLgAECgcJEwACAAAAAA==.Sheldren:BAAALgADCgUJBQAAAA==.Shigz:BAAALgAECgcJCgAAAA==.Shinjii:BAAALgAECgYJBgAAAA==.Shinylatias:BAAALgAECgcJBwAAAA==.Shirahz:BAAALgADCgEJAQAAAA==.Shivrael:BAAALgADCgYJCAAAAA==.Shokie:BAAALgADCgYJCgAAAA==.Shootafix:BAAALgADCgEJAQAAAA==.Shortonfaith:BAAALgAECgQJCAAAAA==.Showpup:BAAALgADCgYJBgAAAA==.Shroot:BAAALgAECgQJCwAAAA==.Shåckle:BAAALgAECgYJDgAAAA==.',
Si='Sickdruid:BAAALgAECgYJCwAAAA==.Silplan:BAABLgAECn8nAAIFAAgJTCI/EQDxAgAFAAgJTCI/EQDxAgABLgABCgMJAwACAAAAAA==.Silvernightz:BAABLgAECn8rAAIEAAgJKBIlFACAAQAEAAgJKBIlFACAAQAAAA==.Silvey:BAAALgAECgYJDgAAAA==.Sinbreaker:BAAALgAECgYJEwAAAA==.Sinich:BAAALgADCgcJBwAAAA==.Sisterlily:BAABLgAECn8WAAIIAAgJ+QdEMABhAQAIAAgJ+QdEMABhAQAAAA==.Sixinchdeep:BAAALgAFFAIJAwAAAA==.Sixninechevy:BAABLgAECn8aAAIOAAcJIBkxdwCWAQAOAAcJIBkxdwCWAQAAAA==.',
Sk='Skinamarink:BAAALgAECgQJCwAAAA==.Skorg:BAAALgAECgYJCwABLgAECgkJJwAJANwhAA==.',
Sl='Sladecraven:BAAALgADCgcJDgAAAA==.Slapstic:BAAALgADCgEJAQAAAA==.Slopmelon:BAABLgAECn8XAAITAAcJlAsTHAAiAQATAAcJlAsTHAAiAQAAAA==.',
Sm='Smøkechedda:BAAALgAECgYJDgAAAA==.',
Sn='Snuffduck:BAABLgAECn8hAAIBAAgJ1SVfAAAmAwABAAgJ1SVfAAAmAwAAAA==.',
So='Sodem:BAABLgAECn8XAAMKAAcJtRRzPACPAQAKAAcJtRRzPACPAQAXAAQJhQohGgCcAAAAAA==.Solariun:BAAALgAECgYJEQAAAA==.Sollixx:BAAALgAECgYJCwABLgAECgMJAwACAAAAAA==.Solomonar:BAAALgADCgMJAwAAAA==.Sonomi:BAAALgADCgYJCwAAAA==.Sorrentoone:BAAALgADCgYJEQAAAA==.',
Sp='Spacedaisy:BAAALgADCgcJEAAAAA==.Spankinstein:BAAALgADCgUJBwABLgAECggJHgALAJofAA==.Sparkletime:BAAALgADCgYJDQAAAA==.Spellbraker:BAABLgAECn8VAAIBAAcJMh8JEgCCAgABAAcJMh8JEgCCAgAAAA==.Spelldemon:BAAALgADCggJCwAAAA==.Spookyvibes:BAAALgADCgcJDgAAAA==.Spãcegoãt:BAAALgAECgEJAgAAAA==.Spøôn:BAAALgAECgYJEQAAAA==.',
Ss='Ssixx:BAAALgADCgQJBAAAAA==.',
St='Staark:BAAALgAECggJEAAAAA==.Stackss:BAAALgADCgUJBQAAAA==.Stanojustice:BAAALgADCggJDAAAAA==.Starburstz:BAAALgAECgEJAgAAAA==.Starfira:BAABLgAECn8aAAIEAAgJ3QaakABbAQAEAAgJ3QaakABbAQAAAA==.Starknight:BAACLgAFFH8SAAIEAAUJ6hp9BACpAQAEAAUJ6hp9BACpAQAuAAQKfy8AAgQACQmIJNAAAPICAAQACQmIJNAAAPICAAAA.Steew:BAAALgADCgkJDQAAAA==.Stinkydemon:BAAALgADCgUJBQAAAA==.Stolenblight:BAAALgADCgYJBgAAAA==.Stonetower:BAAALgAECgYJDQAAAA==.Stormcrafter:BAAALgAECgYJEQAAAA==.Streamline:BAABLgAECn8VAAIlAAcJXxyYDABCAgAlAAcJXxyYDABCAgAAAA==.Strongzero:BAAALgAECgQJBgAAAA==.',
Su='Supercool:BAAALgAECgkJCgAAAA==.Suyoll:BAAALgADCgcJDQAAAA==.',
Sw='Swagnasty:BAABLgAECn8aAAMjAAgJIRo5BQDvAQAOAAgJIRTBTgAGAgAjAAcJcBo5BQDvAQAAAA==.Sweatpants:BAAALgAECgMJAwAAAA==.Swozzie:BAAALgAECgEJAQAAAA==.',
Sy='Syldaeya:BAAALgAECgQJBwAAAA==.Synapse:BAAALgADCgYJBwAAAA==.Syriina:BAAALgADCgYJDQAAAA==.',
['Sç']='Sçout:BAAALgADCgEJAQAAAA==.',
['Së']='Sërkët:BAAALgAECgEJAQABLgAECgQJCgACAAAAAA==.',
Ta='Tacoz:BAAALgADCgcJBwABLgAECgQJBwACAAAAAA==.Taeyn:BAAALgAECgUJBwABLgAECgYJEAACAAAAAA==.Taihou:BAAALgADCgkJCQAAAA==.Talanetheus:BAAALgAECgYJCgAAAA==.Talesse:BAAALgAECgEJAQAAAA==.Taleya:BAABLgAECn8XAAIKAAcJDSPZAQCTAgAKAAcJDSPZAQCTAgAAAA==.Tamachan:BAAALgAECgEJAQAAAA==.Tarryn:BAAALgAECgQJCAAAAA==.Tastetest:BAAALgADCgEJAQAAAA==.Tatsuo:BAAALgADCgUJBAAAAA==.',
Te='Teahupoo:BAAALgAECgQJBgAAAA==.Tekuteku:BAAALgADCgMJAwAAAA==.Tempis:BAAALgAECgUJBwAAAA==.Tengrixz:BAAALgAECgEJAQAAAA==.Teninchdeep:BAAALgAECgMJAwAAAA==.Tenraiyoshi:BAAALgAECgMJAwAAAA==.Tenshi:BAAALgAECgEJAQAAAA==.Terio:BAAALgAECgEJAQABLgAECggJHQAQABIfAA==.Terof:BAAALgAECgMJAwABLgAECggJHAAZAGIgAA==.Terrorblades:BAAALgAECgQJBAABLgAECggJIAAZAEkhAA==.',
Th='Thaco:BAAALgAECgUJCwAAAA==.Thaelinn:BAABLgAECn8UAAMHAAkJlg9YGwC8AQAHAAkJlg9YGwC8AQAIAAcJwhasBQCyAQAAAA==.Thaloriel:BAAALgAECgcJEgAAAA==.Thalyndis:BAAALgADCgEJAQAAAA==.Thalíá:BAAALgADCgkJEgAAAA==.Theßrush:BAAALgAECgcJCwAAAA==.Thickice:BAAALgADCgkJDgAAAA==.Thighgaap:BAAALgADCgYJBgABLgAFFAUJDAAKAMQYAA==.Thornlox:BAABLgAECn8XAAMiAAcJ7BHBAQCdAQAiAAcJ7BHBAQCdAQAhAAQJVA3KRQDFAAAAAA==.Thorwal:BAAALgADCgYJBgAAAA==.Thorzak:BAAALgAECgQJBAAAAA==.Thragerogue:BAAALgAECgMJAwAAAA==.Thuntsevelt:BAAALgAECgQJBQAAAA==.',
Ti='Tiktik:BAAALgAECgYJBwAAAA==.Tiktikdh:BAABLgAECn8aAAITAAkJOR73EgDoAgATAAkJOR73EgDoAgAAAA==.Tiktikmage:BAAALgAECgYJEgAAAA==.Timm:BAAALgAECgEJAQAAAA==.Timolinoo:BAAALgAECgMJAwAAAA==.Titanya:BAAALgADCgMJAwAAAA==.Titers:BAAALgAECgMJAwAAAA==.',
To='Toptree:BAAALgADCgYJBgAAAA==.Topétine:BAABLgAECn8WAAIQAAYJHB5UFQCYAQAQAAYJHB5UFQCYAQAAAA==.Totemfordays:BAAALgAECgEJAQAAAA==.Toxxie:BAAALgADCgcJCQAAAA==.',
Tr='Treeforce:BAAALgAECgcJEQAAAA==.Treehuggs:BAAALgAECgMJAwAAAA==.Trelani:BAAALgAECgUJDAABLgAFFAUJCQAFAEQLAA==.Trelious:BAABLgAECn8WAAIDAAYJtRWPFACFAQADAAYJtRWPFACFAQAAAA==.Trevv:BAABLgAECn8eAAMFAAgJBx4qKABwAgAFAAcJBx4qKABwAgAWAAQJehKRLAAMAQAAAA==.Triforcee:BAAALgAECgEJAQAAAA==.Trinks:BAAALgAECgYJEwAAAA==.Truth:BAAALgAECgcJBQAAAA==.Tryel:BAABLgAECn8ZAAIEAAgJmyHSAgCKAgAEAAgJmyHSAgCKAgAAAA==.Trúth:BAAALgAECgEJAQAAAA==.',
Tu='Turdsmasher:BAAALgAECgcJBwAAAA==.Turumbar:BAABLgAECn8WAAINAAYJnR6yCgB0AQANAAYJnR6yCgB0AQAAAA==.',
Tw='Twysted:BAABLgAECn8VAAIQAAcJwxGGjAC5AQAQAAcJwxGGjAC5AQAAAA==.',
Tx='Txcrazyhorse:BAAALgAECgYJCwAAAA==.',
Ty='Tylerin:BAAALgAECgkJBwAAAA==.Tyrtwo:BAAALgAECgcJEAAAAA==.',
Ul='Uller:BAAALgADCgMJAwAAAA==.',
Un='Unbearivable:BAAALgAECgEJAQAAAA==.Unholynight:BAAALgAECgEJAQAAAA==.Unmelted:BAAALgAECgQJBAAAAA==.Unwisedeath:BAAALgAECgcJCQAAAA==.Unwisedragon:BAAALgAECgUJBQAAAA==.',
Va='Valantrias:BAABLgAECn8VAAMJAAgJ0yNGGgAyAgAJAAcJ6SNGGgAyAgAUAAcJJiCDJQAiAgAAAA==.Valaura:BAABLgAECn8hAAMUAAgJZxqaGABzAgAUAAgJZxqaGABzAgAnAAEJSwgnEAAaAAAAAA==.Valdarun:BAAALgADCgIJAgAAAA==.Valianne:BAAALgADCgYJCwAAAA==.Valranor:BAAALgAECgQJDgAAAA==.Valval:BAAALgAECgYJEQAAAA==.Vampeal:BAAALgADCgcJCwAAAA==.Varirne:BAABLgAECn8jAAMBAAgJzBdGCADCAQABAAgJzBdGCADCAQAEAAMJZReG5ADFAAAAAA==.Varuguard:BAAALgAECgEJAQABLgAECgMJBQACAAAAAA==.Varynevo:BAAALgADCgYJCgAAAA==.Vaukus:BAAALgADCgUJCgAAAA==.Vaylkyrie:BAAALgADCgEJAQAAAA==.',
Ve='Velell:BAABLgAECn8dAAIQAAcJEh9vSABeAgAQAAcJEh9vSABeAgAAAA==.Veliena:BAAALgAECgEJAQAAAA==.Veloxus:BAAALgAECgUJBwAAAA==.Velynven:BAAALgADCgkJDAAAAA==.Venomsnake:BAAALgADCgkJIQAAAA==.Venura:BAAALgAECgYJEwAAAA==.Verelidaine:BAACLgAFFH8SAAILAAUJThnEAACvAQALAAUJThnEAACvAQAuAAQKfykAAgsACQn8JOsAALADAAsACQn8JOsAALADAAAA.Versiane:BAAALgADCgIJAgAAAA==.Vespra:BAABLgAECn8aAAMWAAYJ5hAAIQBMAQAWAAYJDBAAIQBMAQAFAAYJog0VKQDrAAABLgAECgEJAQACAAAAAA==.',
Vi='Viabelle:BAAALgAECgYJDQAAAA==.Vintage:BAAALgAECgYJDwAAAA==.Vivid:BAAALgADCgEJAQAAAA==.Vivizinfofin:BAAALgAECgMJAwAAAA==.',
Vl='Vll:BAAALgADCgIJAgABLgAECggJFgALALYVAA==.',
Vo='Voidcynni:BAAALgADCgYJBgAAAA==.Voidglazer:BAABLgAECn8UAAITAAYJjQt7hgAZAQATAAYJjQt7hgAZAQAAAA==.Voidthane:BAABLgAECn8VAAITAAYJxguaIwD1AAATAAYJxguaIwD1AAAAAA==.Vorb:BAAALgAECgQJBAAAAA==.Vorvadoss:BAAALgAECgQJBAAAAA==.',
Vs='Vstheworld:BAAALgAECgQJBgAAAA==.',
Vy='Vyrda:BAAALgADCgEJAQABLgADCgYJBgACAAAAAA==.',
['Và']='Vàlefor:BAAALgADCgMJAwAAAA==.',
Wa='Wagwan:BAAALgAECgYJBgAAAA==.Warbringer:BAABLgAECn8UAAITAAYJ0xTaYAB+AQATAAYJ0xTaYAB+AQAAAA==.Waskaar:BAAALgADCgEJAQAAAA==.Waterbite:BAAALgADCgMJAQAAAA==.',
We='Welenniesh:BAAALgAECgMJAwAAAA==.Wellick:BAAALgADCgQJBQAAAA==.Wetspots:BAAALgAECgYJBAAAAA==.',
Wh='Whirt:BAAALgAECgcJCwAAAA==.Whysitsticky:BAAALgADCgEJAQAAAA==.',
Wi='Wildheart:BAAALgAECgMJAwAAAA==.Wildness:BAAALgADCggJFQAAAA==.Wildraven:BAABLgAECn8cAAIUAAYJuhtpOwC3AQAUAAYJuhtpOwC3AQAAAA==.Withsauce:BAAALgAECgYJDQAAAA==.',
Wo='Woodish:BAABLgAECn8YAAINAAgJoiGeGgB3AgANAAgJoiGeGgB3AgAAAA==.',
Wr='Wraithryn:BAAALgAECgcJEwAAAA==.',
Wy='Wygüy:BAABLgAECn8XAAIQAAgJFxUiFgCSAQAQAAgJFxUiFgCSAQAAAA==.Wyldrin:BAAALgADCgIJAgAAAA==.Wynnd:BAAALgADCggJEAAAAA==.',
['Wï']='Wïtchcraft:BAAALgADCgIJAgAAAA==.',
Xa='Xanbar:BAAALgADCgEJAgAAAA==.Xandent:BAAALgAECgYJCwAAAA==.Xandreydor:BAAALgAECgIJAwAAAA==.Xanju:BAABLgAECn8gAAIZAAgJSSH4DACrAgAZAAgJSSH4DACrAgAAAA==.Xanojitsu:BAAALgADCgcJCAAAAA==.Xarc:BAAALgAECgEJAgAAAA==.Xarg:BAAALgAECgQJCAAAAA==.Xarktotem:BAAALgAECgEJBAAAAA==.',
Xi='Xidium:BAAALgADCgcJBwAAAA==.Xinkz:BAABLgAECn8YAAIQAAcJshSnHgBdAQAQAAcJshSnHgBdAQAAAA==.Xiong:BAAALgADCgIJAgAAAA==.',
Xm='Xmuze:BAAALgADCgYJBQAAAA==.',
Xq='Xqe:BAAALgAECgIJAgAAAA==.',
Xu='Xuoddam:BAAALgAECgUJBwABLgAECgUJBwACAAAAAA==.',
Ya='Yalith:BAAALgADCgkJCgAAAA==.Yayan:BAAALgADCgMJAwAAAA==.',
Ye='Yeetos:BAAALgAECgQJCQAAAA==.',
Yi='Yikers:BAAALgADCgEJAQAAAA==.',
Yo='Yolosphinx:BAABLgAECn8mAAIfAAkJXw4tBgCxAQAfAAkJXw4tBgCxAQAAAA==.Yourholyness:BAAALgADCgYJBgABLgAECgMJBQACAAAAAA==.',
Yu='Yuchan:BAAALgADCgEJAgAAAA==.Yumite:BAAALgADCgEJAQAAAA==.',
Za='Zack:BAAALgAECgQJBwAAAA==.Zaleel:BAAALgADCgYJBgAAAA==.Zalil:BAAALgAECgYJDgAAAA==.Zapbrannigan:BAAALgAECgUJBQAAAA==.Zarcyna:BAACLgAFFH8SAAMFAAUJLhfdBgC1AQAFAAUJLhfdBgC1AQAWAAEJIAU2GQBLAAAuAAQKfy8AAwUACQkaJVMAADYDAAUACAnKJFMAADYDABYABQl7IBAOAOYBAAAA.Zarik:BAAALgAECgYJEgAAAA==.Zaryk:BAAALgAECgUJBwABLgADCgkJMAACAAAAAA==.Zathoron:BAABLgAECn8hAAIlAAgJqiR1AAC9AgAlAAgJqiR1AAC9AgAAAA==.',
Ze='Zell:BAAALgADCgcJBwAAAA==.Zellven:BAAALgAECgUJCwABLgAECggJGgAaAFsgAA==.Zenfox:BAAALgAFFAEJAQAAAA==.Zenither:BAAALgAECgUJBwAAAA==.Zexos:BAAALgADCgEJAwAAAA==.',
Zi='Ziatora:BAABLgAECn8aAAITAAgJmRkQNQAkAgATAAgJmRkQNQAkAgAAAA==.Zillian:BAABLgAECn8aAAIaAAgJWyDUBgD5AgAaAAgJWyDUBgD5AgAAAA==.Zimmy:BAAALgAECgYJBwAAAA==.Zipo:BAAALgADCgQJCAAAAA==.Zirk:BAAALgAECgQJCAAAAA==.',
Zo='Zooms:BAAALgADCgUJBQABLgAFFAQJBQARADgeAA==.',
Zu='Zulamesh:BAAALgAECgQJBQAAAA==.Zultaj:BAAALgADCgkJJQAAAA==.Zumwalathas:BAAALgADCgkJHwAAAA==.Zuppa:BAAALgADCgEJAQAAAA==.',
['Àn']='Ànt:BAAALgADCggJDQABLgAECgYJFAABAKMGAA==.',
['Àr']='Àriýa:BAAALgAECgQJBQAAAA==.',
['Åc']='Åchilles:BAAALgADCgcJDQAAAA==.',
['Ëv']='Ëvan:BAABLgAECn8YAAINAAcJ3RlGBwCuAQANAAcJ3RlGBwCuAQAAAA==.',
['Ða']='Ðarrow:BAAALgADCgcJDQAAAA==.',
['Ðo']='Ðook:BAAALgADCgEJAQAAAA==.',
['Ór']='Órthan:BAAALgADCgcJDQAAAA==.',
['Öu']='Öutßreak:BAABLgAECn8YAAIOAAYJiAkBKwDfAAAOAAYJiAkBKwDfAAAAAA==.',
['Ûl']='Ûllr:BAAALgADCgcJBwAAAA==.',
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
