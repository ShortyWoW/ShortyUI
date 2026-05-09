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

local lookup = {'Paladin-Retribution','DeathKnight-Blood','DemonHunter-Devourer','Priest-Shadow','Shaman-Elemental','Rogue-Outlaw','Unknown-Unknown','Paladin-Protection','Paladin-Holy','Warrior-Protection','Druid-Feral','Priest-Holy','Mage-Frost','Druid-Restoration','Monk-Windwalker','Monk-Mistweaver','Druid-Balance','Druid-Guardian','DeathKnight-Unholy','Shaman-Restoration','Evoker-Preservation','Evoker-Augmentation','Priest-Discipline','Warlock-Demonology','DemonHunter-Vengeance','Evoker-Devastation','Hunter-Survival','Warlock-Destruction','Rogue-Assassination','Rogue-Subtlety','Hunter-BeastMastery','Warrior-Fury','DemonHunter-Havoc','Shaman-Enhancement','Mage-Arcane','Monk-Brewmaster','Warrior-Arms','Mage-Fire','Hunter-Marksmanship','DeathKnight-Frost',}
local provider = {region='US',realm='Uldum',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abmikaze:BAAALgAECgQJBAAAAA==.',
Ad='Adimus:BAAALgADCgIJAgAAAA==.Adorean:BAABLgAECn8iAAIBAAgJgRllGwAkAgABAAgJgRllGwAkAgAAAA==.',
Ae='Aeginau:BAAALgAECgMJAwAAAA==.Aenymbria:BAABLgAECn8YAAIBAAcJ2Br3PQCMAQABAAcJ2Br3PQCMAQAAAA==.Aerbear:BAAALgADCgUJCAAAAA==.',
Ag='Age:BAABLgAECn8XAAIBAAYJxA80YgApAQABAAYJxA80YgApAQAAAA==.',
Ai='Aimnskin:BAAALgADCggJEgAAAA==.',
Ak='Akuaa:BAAALgADCgMJAwAAAA==.',
Al='Alburm:BAAALgAECgcJCgAAAA==.Alexstraxsa:BAAALgADCgkJJwAAAA==.Aliine:BAABLgAECn8hAAICAAcJFRLxFAAuAQACAAcJFRLxFAAuAQAAAA==.Ally:BAAALgAECgIJAgABLgAECgYJGgADALwfAA==.Althaea:BAABLgAECn8VAAIEAAgJ0wHsOACgAAAEAAgJ0wHsOACgAAAAAA==.',
Am='Ameiisaa:BAAALgADCgcJCgAAAA==.Amytiel:BAABLgAECn8vAAIFAAgJMB/fCQA7AgAFAAgJMB/fCQA7AgAAAA==.',
An='Anahana:BAAALgAECgYJDQAAAA==.Anali:BAAALgADCggJGAAAAA==.Andi:BAAALgAECgcJEAAAAA==.Andorelia:BAABLgAECn8aAAIBAAgJHQ3URwBuAQABAAgJHQ3URwBuAQAAAA==.Andronocus:BAAALgADCggJFQAAAA==.Anko:BAAALgADCgQJAwAAAA==.Anxie:BAAALgAECgcJBwAAAA==.Anìtamaxwynn:BAAALgAECgYJCwABLgAFFAYJEAAGAAUeAA==.',
Ap='Apally:BAAALgAECgQJCQAAAA==.Apexmaster:BAAALgAECgYJCwAAAA==.Appleborne:BAAALgADCgcJBwABLgAECgYJBgAHAAAAAA==.Appleseed:BAAALgADCgMJBQAAAA==.Apprentice:BAABLgAECn8bAAIIAAgJAgI4HQCqAAAIAAgJAgI4HQCqAAAAAA==.',
Ar='Aragorn:BAAALgAECgYJCgAAAA==.Aramos:BAABLgAECn8oAAIJAAgJ3xlpEgADAgAJAAgJ3xlpEgADAgAAAA==.Aramôs:BAABLgAECn8WAAIJAAYJChPHJQBbAQAJAAYJChPHJQBbAQAAAA==.Ares:BAAALgADCgYJDwAAAA==.Arinathia:BAAALgAECgcJAQABLgAECgkJDAAHAAAAAA==.Arta:BAABLgAECn8WAAIKAAYJrxaIFAAlAQAKAAYJrxaIFAAlAQAAAA==.Artachoke:BAAALgADCgYJCAAAAA==.Aruncusdio:BAABLgAECn8cAAILAAgJbAbxDgAoAQALAAgJbAbxDgAoAQAAAA==.',
As='Ashhealz:BAABLgAECn8WAAIMAAcJxw7eIgAyAQAMAAcJxw7eIgAyAQAAAA==.Ashlei:BAAALgADCgEJAQAAAA==.Asteroid:BAAALgAECgUJBgAAAA==.',
At='Atelwen:BAAALgAECgYJEwAAAA==.',
Av='Aveme:BAABLgAECn8wAAINAAkJCiPoBwDyAgANAAkJCiPoBwDyAgAAAA==.',
Aw='Awartedpeen:BAABLgAECn8VAAIOAAYJaQzuUADRAAAOAAYJaQzuUADRAAAAAA==.',
Az='Azael:BAAALgAECgEJAQABLgAECgIJBAAHAAAAAA==.Azuleon:BAABLgAECn8XAAMPAAcJfxlQHQDwAQAPAAYJ6B1QHQDwAQAQAAcJQA4eIQA8AQAAAA==.Azuresky:BAAALgADCgEJAQAAAA==.',
Ba='Badsnapple:BAAALgAECgYJBgAAAA==.Bagelmancer:BAAALgADCgUJBQAAAA==.Bageluwu:BAAALgAECgEJAQAAAA==.Bamber:BAAALgADCggJDQAAAA==.Battar:BAAALgAECgEJAQAAAA==.Bayraktar:BAAALgADCgkJDgAAAA==.',
Bb='Bbads:BAAALgADCgIJAgAAAA==.',
Be='Beaker:BAABLgAECn8oAAMRAAgJJRsEHABVAQARAAYJCx4EHABVAQASAAYJ+hAKEQD3AAAAAA==.Beastmode:BAABLgAECn8oAAIOAAgJPBsaEwAyAgAOAAgJPBsaEwAyAgAAAA==.Bedlem:BAABLgAECn8WAAITAAcJTAgNXwAnAQATAAcJTAgNXwAnAQAAAA==.Beerchaplain:BAAALgADCgcJFgABLgAECgcJBwAHAAAAAA==.Bernard:BAABLgAECn8hAAMUAAgJRQYMTgDHAAAUAAgJRQYMTgDHAAAFAAQJpgaaSgB6AAAAAA==.',
Bi='Bidoof:BAABLgAECn8gAAMVAAcJGhcDCQDSAQAVAAcJGhcDCQDSAQAWAAYJQw+WNADQAAAAAA==.Bigolman:BAAALgAECgEJAQAAAA==.Biochemguy:BAAALgAECgUJAQAAAA==.Birgitte:BAAALgAECgcJDwAAAA==.',
Bl='Blackelvis:BAAALgADCgcJBwABLgAECgkJJgAMAO8ZAA==.Blackgrace:BAAALgAECggJDQAAAA==.Blacklisted:BAABLgAECn8mAAMMAAkJ7xlDBgCWAgAMAAkJ7xlDBgCWAgAXAAEJgwrCSQAuAAAAAA==.Blackup:BAAALgAECgMJAwAAAA==.Blackvortex:BAAALgADCggJCgAAAA==.Bloodybloodz:BAAALgAECgQJBQABLgAECgcJDwAHAAAAAA==.Bloodyburst:BAAALgAECgEJAQABLgAECgcJDwAHAAAAAA==.Bloodyfistz:BAAALgAECgcJDwAAAA==.Blueshift:BAABLgAECn8WAAIDAAkJChc4QwDnAQADAAkJChc4QwDnAQAAAA==.Bluethreetwo:BAAALgAECgQJDgAAAA==.Blurry:BAAALgADCgUJBgAAAA==.',
Bo='Bookofzeref:BAABLgAECn8UAAIYAAgJVxKzMwCVAQAYAAgJVxKzMwCVAQAAAA==.',
Br='Brahruhanu:BAEALgADCgUJCAAAAA==.Braile:BAABLgAECn8UAAIZAAYJexopCQBJAQAZAAYJexopCQBJAQAAAA==.Brayend:BAAALgAECgYJEgAAAA==.Brewbelly:BAAALgADCgcJCQAAAA==.Brimscythe:BAABLgAECn8oAAIaAAkJ+R0JAQCiAgAaAAkJ+R0JAQCiAgAAAA==.',
Bu='Bubbleup:BAAALgADCgUJBQAAAA==.Bulish:BAAALgADCgMJAwAAAA==.',
Ca='Caliandis:BAAALgAECgYJCwAAAA==.Calvey:BAAALgAECgQJCAAAAA==.Cambrai:BAABLgAECn8WAAIPAAcJ5BBMGABjAQAPAAcJ5BBMGABjAQAAAA==.Cannabelle:BAACLgAFFH8FAAIbAAMJxRVbFACwAAAbAAMJxRVbFACwAAAuAAQKfzAAAhsACAmcJf4AAGYDABsACAmcJf4AAGYDAAAA.Canto:BAAALgAECgQJBAAAAA==.Carclias:BAABLgAECn8aAAMcAAkJbxovBwBXAgAcAAgJdxsvBwBXAgAYAAMJ5gkJwQBJAAAAAA==.Carmenere:BAAALgADCgUJCQAAAA==.Carthrix:BAAALgAECgYJEgAAAA==.Catmove:BAAALgADCggJCQAAAA==.Cattlerage:BAAALgAECgEJAQAAAA==.',
Ce='Cedo:BAAALgADCgUJBQAAAA==.Celéste:BAAALgADCgcJBwAAAA==.',
Ch='Chaoscookies:BAABLgAECn8vAAMcAAkJWRcPHgBfAQAcAAUJtBkPHgBfAQAYAAUJgxTLUQA1AQAAAA==.Chaotik:BAAALgADCgcJDAAAAA==.Chaplain:BAAALgAECgcJBwAAAA==.Chartkov:BAAALgAECgQJCwAAAA==.Cheechee:BAAALgAECgYJEAAAAA==.Cheekichik:BAAALgADCgQJBAAAAA==.Cheeseballer:BAAALgAFFAQJBAAAAA==.Cheesebur:BAAALgADCgcJBwAAAA==.Chighas:BAAALgADCgQJBwAAAA==.Choofi:BAABLgAECn8bAAIOAAcJKBTzJwCQAQAOAAcJKBTzJwCQAQAAAA==.Chubbytoyboy:BAAALgADCgUJBQABLgAFFAQJCwAFAAwQAA==.',
Ci='Ciená:BAAALgAECgQJBQAAAA==.Cin:BAAALgAECgYJEAAAAA==.Cinderpetal:BAAALgAECgQJBQAAAA==.',
Co='Comlock:BAAALgAECgYJDgAAAA==.Complacent:BAABLgAECn8eAAISAAgJSgFsHwBgAAASAAgJSgFsHwBgAAAAAA==.Coomtheory:BAAALgAECgYJCAAAAA==.Coriander:BAAALgAECgIJAwAAAA==.Corik:BAAALgADCgMJAwAAAA==.',
Cr='Cragn:BAAALgAECgIJBwAAAA==.Crownman:BAAALgADCgUJCAAAAA==.Crunchyblue:BAAALgADCgUJBgAAAA==.',
Cu='Cuddilz:BAABLgAECn8VAAMdAAYJvROcCABLAQAdAAYJ3RKcCABLAQAeAAUJ4A0xQQAXAQAAAA==.Cursedchild:BAAALgAECggJDAABLgAECgcJKgAYADokAA==.',
Cy='Cyclonic:BAAALgADCgYJBwAAAA==.Cyonicus:BAABLgAECn8iAAIYAAgJzRxLEgBQAgAYAAgJzRxLEgBQAgAAAA==.Cyradis:BAAALgADCgEJAQAAAA==.Cyska:BAABLgAECn8wAAICAAkJZRtyBABzAgACAAkJZRtyBABzAgAAAA==.',
['Cé']='Cécé:BAABLgAECn8fAAIBAAcJkSJqFQBOAgABAAcJkSJqFQBOAgAAAA==.',
Da='Daciana:BAABLgAECn8WAAIfAAYJfB68KQCqAQAfAAYJfB68KQCqAQAAAA==.Dagaroonie:BAAALgAECgcJCAAAAA==.Dagevas:BAABLgAECn8kAAIYAAgJkhT5KgC5AQAYAAgJkhT5KgC5AQAAAA==.Darkeznite:BAABLgAECn8YAAIfAAgJghf3GwD1AQAfAAgJghf3GwD1AQAAAA==.Darksoldier:BAAALgAFFAEJAQAAAA==.Dartoy:BAABLgAECn8uAAIgAAgJMggNIQBkAQAgAAgJMggNIQBkAQAAAA==.Davriell:BAAALgADCgcJDQAAAA==.Dax:BAABLgAECn8VAAIfAAYJeBkZMgCFAQAfAAYJeBkZMgCFAQAAAA==.Dazling:BAAALgAECgcJCgAAAA==.',
De='Deathkess:BAAALgAECgcJBwAAAA==.Deathlokk:BAABLgAECn8VAAIcAAYJSh9xBADEAQAcAAYJSh9xBADEAQAAAA==.Deeppurple:BAAALgAECgYJDgAAAA==.Deezmons:BAABLgAECn8iAAIhAAgJhRAkEACBAQAhAAgJhRAkEACBAQAAAA==.Deholybagel:BAAALgAECgQJBQAAAA==.Del:BAABLgAECn8oAAIZAAgJASaLAAD/AgAZAAgJASaLAAD/AgAAAA==.Demoncheese:BAAALgADCgYJCAAAAA==.Demondag:BAAALgADCgcJDAAAAA==.Demoniaca:BAAALgAECgMJBQAAAA==.Demonkirby:BAAALgADCgUJBQAAAA==.Demonlarrik:BAAALgAECgEJAQAAAA==.Derale:BAABLgAECn8aAAMWAAgJiw38JQCNAQAWAAgJiA38JQCNAQAaAAcJXQQrIgAZAQAAAA==.',
Dh='Dhargal:BAACLgAFFH8FAAIFAAMJ6BgGFwD0AAAFAAMJ6BgGFwD0AAAuAAQKfy0AAgUACAmLJNwDAMUCAAUACAmLJNwDAMUCAAAA.',
Di='Dial:BAAALgADCgkJGQAAAA==.Dichotomy:BAAALgADCgQJBAAAAA==.Divinebi:BAAALgAECgUJBQAAAA==.Divus:BAABLgAECn8WAAIOAAYJGQPeXgCjAAAOAAYJGQPeXgCjAAAAAA==.',
Dk='Dkfaros:BAABLgAECn8bAAITAAgJHyG+DQCWAgATAAgJHyG+DQCWAgAAAA==.',
Do='Donko:BAAALgADCggJCAABLgAECgQJCAAHAAAAAA==.Dontcarebear:BAABLgAECn8UAAISAAYJGQVAHAB3AAASAAYJGQVAHAB3AAAAAA==.Doofnshmirtz:BAABLgAECn8nAAIiAAgJjh7BAgB0AgAiAAgJjh7BAgB0AgAAAA==.Dorkwiz:BAAALgADCgMJAwAAAA==.Dorow:BAAALgAECgcJBwAAAA==.Dotpocket:BAABLgAECn8gAAIYAAgJexY4JQDVAQAYAAgJexY4JQDVAQAAAA==.',
Dr='Drakenn:BAAALgAECgcJDgAAAA==.Draéne:BAAALgAECgYJDAAAAA==.Dreadly:BAAALgADCgUJCAAAAA==.Dreadp:BAAALgADCgIJAgAAAA==.Dreamfyre:BAAALgAECgEJAQAAAA==.Dremmy:BAAALgAECgYJEQAAAA==.Dripdasini:BAAALgADCgUJBQAAAA==.Droki:BAABLgAECn8iAAIiAAgJ6B+gAgB6AgAiAAgJ6B+gAgB6AgAAAA==.',
Du='Dunsel:BAAALgAECgQJBAABLgAECgkJKAAaAPkdAA==.Dunwich:BAAALgADCgcJIAAAAA==.',
Dv='Dvali:BAAALgAECgIJAgAAAA==.',
Dy='Dyorra:BAAALgAECgYJDwAAAA==.',
Eb='Ebonshade:BAAALgAECgMJBgAAAA==.',
Ed='Edgardapoe:BAAALgAECgIJAgABLgAECgQJBQAHAAAAAA==.Edginglord:BAAALgAECgYJBwAAAA==.',
Eh='Ehmill:BAABLgAECn8gAAITAAgJchpwGQAzAgATAAgJchpwGQAzAgAAAA==.',
El='Elesrya:BAAALgADCgYJEAABLgAECgcJGAABANgaAA==.Elventhing:BAAALgAECgYJCQAAAA==.',
Em='Emmå:BAAALgADCgEJAQAAAA==.Emshady:BAAALgADCgcJBwAAAA==.',
Eo='Eomær:BAAALgAECgEJAgAAAA==.',
Ep='Epsilòn:BAEALgAECgcJAQABLgAECgcJAQAHAAAAAA==.',
Er='Ernest:BAAALgADCgUJBgAAAA==.Errani:BAAALgAECgUJCwAAAA==.',
Es='Eskers:BAAALgAECgYJEAAAAA==.Estralla:BAAALgADCgQJBAAAAA==.',
Eu='Eureki:BAABLgAECn8gAAIDAAgJhA3sPQBAAQADAAgJhA3sPQBAAQAAAA==.',
Ev='Evilkarma:BAABLgAECn8WAAINAAYJPwJvtgCmAAANAAYJPwJvtgCmAAAAAA==.Evocane:BAAALgAECgYJCgAAAA==.Evocatis:BAACLgAFFH8MAAMBAAUJFhqOFABVAQABAAUJFhqOFABVAQAJAAEJRAsQLgA+AAAuAAQKfx8AAwEACQkZITMeALYCAAEACAl5IzMeALYCAAkAAwkOCwx2AKIAAAAA.Evoorc:BAAALgAECgIJAgAAAA==.',
Ex='Ex:BAABLgAECn8dAAIcAAgJqAwUCABeAQAcAAgJqAwUCABeAQAAAA==.',
Fa='Faasht:BAAALgAECgEJAQAAAA==.Fayde:BAAALgADCgUJBAAAAA==.',
Fe='Felheart:BAAALgAECgEJAQABLgAFFAMJBgABAN4SAA==.Felzbirt:BAAALgADCgYJCwAAAA==.Fenehdis:BAAALgAECgYJCwAAAA==.Ferg:BAAALgADCgcJBwAAAA==.Ferula:BAAALgADCgEJAgABLgAECgMJAwAHAAAAAA==.',
Fi='Fiftycaliber:BAAALgAECgQJBAAAAA==.Firebirdxx:BAAALgADCgcJBwABLgAFFAUJCAAOAJcQAA==.Firebirdz:BAACLgAFFH8IAAIOAAUJlxDoHQDoAAAOAAUJlxDoHQDoAAAuAAQKfx8AAw4ACQnVIbEIAAMDAA4ACQnVIbEIAAMDABEAAQkqAh5jACEAAAAA.Firebirdzx:BAAALgADCgYJBwABLgAFFAUJCAAOAJcQAA==.Firebirdzz:BAAALgAECgQJBwAAAA==.Fizzystomps:BAAALgAECgEJAQAAAA==.',
Fl='Fleabàg:BAAALgAECggJBwAAAA==.',
Fo='Forque:BAAALgADCgQJAwAAAA==.Fortybelow:BAAALgAECgQJCAAAAA==.',
Fr='Frostypaw:BAAALgADCgYJCgAAAA==.Frostzilla:BAAALgADCgYJBgAAAA==.',
Fu='Fuzzybut:BAAALgAECgYJDwAAAA==.',
Ga='Gandalph:BAAALgAECgMJAwAAAA==.Gark:BAAALgAECgQJBwAAAA==.Garkk:BAAALgADCgcJCAAAAA==.Gazzi:BAAALgAECgkJEgAAAA==.',
Gi='Gióvanna:BAAALgAECgMJAwAAAA==.',
Gl='Glaivedigger:BAAALgADCgIJAwABLgAECgYJDAAHAAAAAA==.',
Go='Goblndeznutz:BAAALgADCgIJAgAAAA==.Goobo:BAACLgAFFH8HAAITAAMJRg+PVgDeAAATAAMJRg+PVgDeAAAuAAQKfy4AAhMACQk5GHgSAGgCABMACQk5GHgSAGgCAAAA.Goodheavens:BAAALgAECgQJBwAAAA==.Goonlock:BAAALgADCgYJCwAAAA==.Gorbb:BAAALgADCgQJBAAAAA==.Gotenk:BAAALgAECgQJBAAAAA==.Goudafel:BAAALgADCgcJDgAAAA==.Goyim:BAABLgAECn8lAAINAAkJ9Q3IdwDiAQANAAkJ9Q3IdwDiAQAAAA==.',
Gr='Gr:BAABLgAECn8WAAIOAAcJGRZ7KACMAQAOAAcJGRZ7KACMAQAAAA==.Graveconvert:BAAALgADCgMJAwAAAA==.Grewbacca:BAAALgADCgMJAwAAAA==.Grimkrieg:BAABLgAECn8jAAISAAgJwxmeBQD/AQASAAgJwxmeBQD/AQAAAA==.Grody:BAAALgADCgYJBgAAAA==.Grumpias:BAAALgAECgIJAgAAAA==.',
Gu='Guroo:BAABLgAECn8mAAIfAAgJoRRfJQC/AQAfAAgJoRRfJQC/AQAAAA==.',
['Gá']='Gárp:BAAALgAECgQJBQAAAA==.',
['Gø']='Gødoth:BAABLgAECn8gAAMFAAcJiCDTDAAPAgAFAAcJiCDTDAAPAgAUAAUJECLwOwCSAQAAAA==.',
Ha='Hagarn:BAABLgAECn8qAAIBAAkJ5BO6GgApAgABAAkJ5BO6GgApAgAAAA==.Halimah:BAAALgADCgUJBQAAAA==.Halloffame:BAAALgAECgIJAQAAAA==.Hamsham:BAAALgAECgEJAQAAAA==.Harleypaw:BAAALgADCgQJBAAAAA==.Harleypuddin:BAAALgAECgkJBwAAAA==.Harlydorable:BAAALgAECgkJDQAAAA==.Hazystar:BAAALgAECgcJDAAAAA==.',
He='Healmemaybe:BAAALgAECgYJEgAAAA==.Hemour:BAAALgAECgYJEQAAAA==.Hexmachine:BAAALgAECgkJBQAAAA==.',
Hi='Hirak:BAAALgADCgIJAgABLgAFFAcJHAAMAEQXAA==.',
Ho='Hogarth:BAAALgADCgEJAQAAAA==.Holdmyshock:BAAALgADCgEJAQAAAA==.Holmstein:BAAALgAECgYJCwAAAA==.Hotnsoursoup:BAAALgADCgcJCgAAAA==.',
Hu='Hunkules:BAAALgAECgYJCAAAAA==.',
['Hë']='Hëllsoldier:BAAALgADCgMJAwAAAA==.',
Ia='Iamahriman:BAABLgAECn8oAAIFAAgJ0gu/IABKAQAFAAgJ0gu/IABKAQAAAA==.Iamthanatos:BAAALgAECgIJBAAAAA==.',
Id='Idblastdat:BAABLgAECn8lAAINAAgJORgDKwD2AQANAAgJORgDKwD2AQAAAA==.',
Ig='Ignite:BAAALgAECgYJDgAAAA==.',
Il='Iliana:BAAALgAECgIJAQAAAA==.Illestria:BAABLgAECn8qAAIBAAgJGxhcLADMAQABAAgJGxhcLADMAQAAAA==.Illumiscotty:BAABLgAECn8pAAMNAAkJSyXWAQBtAwANAAkJIiXWAQBtAwAjAAIJBh8XEQCxAAAAAA==.Ilwey:BAAALgAECgcJCwAAAA==.',
Im='Immortamonk:BAABLgAECn8XAAIkAAYJPB9JJgDSAQAkAAYJPB9JJgDSAQAAAA==.Immórtál:BAAALgADCgUJBQABLgAECgYJFwAkADwfAA==.',
In='Insania:BAABLgAECn8cAAIUAAgJuxrtDgBLAgAUAAgJuxrtDgBLAgAAAA==.Invisagal:BAAALgAECgQJBgAAAA==.',
Io='Ionni:BAAALgADCgUJCAAAAA==.Iosefka:BAAALgADCgQJBAAAAA==.',
Ir='Ironhands:BAAALgAECgYJBwAAAA==.',
Iz='Izara:BAAALgAECgEJAQAAAA==.',
Ja='Jarlmaxim:BAAALgAECgYJDAABLgAECggJDQAHAAAAAA==.Jasindra:BAAALgAECgcJCwABLgAECgkJLgAUAAYiAA==.',
Ji='Jin:BAAALgADCgEJAQAAAA==.',
Jo='Johnnycash:BAAALgADCgYJBgAAAA==.Jolinascrubs:BAABLgAECn8oAAIIAAgJkhF0DQBhAQAIAAgJkhF0DQBhAQABLgAFFAQJDwAfAOkJAA==.Jonjee:BAABLgAECn8YAAIBAAkJIR1NMQBdAgABAAkJIR1NMQBdAgAAAA==.',
Ju='Juicez:BAAALgADCgQJBAAAAA==.Jurkee:BAABLgAECn8mAAIBAAgJqB0xFABYAgABAAgJqB0xFABYAgAAAA==.',
Ka='Kahekili:BAAALgAECgEJAgAAAA==.Kain:BAAALgAECgkJCwAAAA==.Kalagren:BAABLgAECn8XAAIfAAUJHQctcwC7AAAfAAUJHQctcwC7AAAAAA==.Kaleielin:BAAALgAECgIJAgAAAA==.Kathring:BAAALgADCgQJBAAAAA==.Katio:BAABLgAECn8mAAMeAAgJMCGVCQAHAgAeAAcJeiCVCQAHAgAdAAIJgxNyEwBuAAAAAA==.Kavaria:BAAALgAECgIJAgAAAA==.Kaydra:BAAALgADCgUJCAAAAA==.Kayhless:BAAALgAECgYJEQAAAA==.',
Ke='Keerah:BAABLgAECn8aAAMDAAkJtwOmVwD1AAADAAkJtwOmVwD1AAAZAAUJmQFwGABdAAAAAA==.Kelirra:BAAALgADCgEJAgAAAA==.Kendoraa:BAAALgAECgEJAQAAAA==.Kessala:BAAALgAECgQJBgAAAA==.Kessandra:BAACLgAFFH8ZAAIYAAUJRh45FABmAQAYAAUJRh45FABmAQAuAAQKfyoAAhgACQkYJFIEAHYDABgACQkYJFIEAHYDAAAA.Kexkan:BAAALgAECgYJDgAAAA==.Kezzia:BAAALgADCgMJAwAAAA==.',
Kh='Kharilan:BAAALgAECgYJDAAAAA==.Khitai:BAAALgADCgcJDgAAAA==.Khurri:BAABLgAECn8VAAILAAkJtx46BgCaAgALAAkJtx46BgCaAgAAAA==.',
Ki='Kiarah:BAAALgAECgYJDwAAAA==.Kirwyn:BAAALgADCgcJBwAAAA==.Kisor:BAAALgAECgYJCAAAAA==.Kitchenstink:BAABLgAECn8YAAIlAAkJ4B4UBAC0AgAlAAkJ4B4UBAC0AgAAAA==.',
Kl='Klys:BAABLgAECn8iAAIDAAgJqRaQIwCzAQADAAgJqRaQIwCzAQAAAA==.',
Ko='Kordh:BAABLgAECn8sAAQFAAcJOg9wJgAmAQAiAAcJew5CEQCjAQAUAAYJrwtdVAA0AQAFAAcJKA5wJgAmAQAAAA==.Kordiza:BAAALgAECgYJDwABLgAECgcJLAAFADoPAA==.',
Kr='Kritanta:BAABLgAECn8oAAICAAgJ6AzeFAAuAQACAAgJ6AzeFAAuAQAAAA==.Krrsantan:BAAALgADCgYJDQAAAA==.Krystallus:BAABLgAECn8ZAAIRAAYJGxCtJwADAQARAAYJGxCtJwADAQAAAA==.',
Ku='Kurnea:BAABLgAECn8YAAIJAAgJsR88DQBCAgAJAAgJsR88DQBCAgAAAA==.',
Ky='Kyandur:BAAALgADCgQJBAAAAA==.',
['Kó']='Kórrá:BAAALgADCgEJAQAAAA==.',
La='Laidy:BAAALgADCgYJBgAAAA==.Lakartó:BAACLgAFFH8MAAIWAAQJFRN9FAA4AQAWAAQJFRN9FAA4AQAuAAQKfx0ABBoACAmVFmUXAH8BABYABwnKEWQmAIkBABoABglRE2UXAH8BABUAAQkcFNkmAD0AAAAA.Larzuk:BAAALgADCgcJBwAAAA==.Lathril:BAAALgADCgYJBgAAAA==.',
Ld='Ldritch:BAACLgAFFH8OAAMGAAQJNiOsAACYAQAGAAQJNiOsAACYAQAdAAIJ+RWjAwC9AAAuAAQKfyYABAYACAm9Jd8AABEDAAYACAmGJd8AABEDAB4ABwmqI2ALAN8CAB0ABwlWJUgCANgCAAEuAAUUBQkSAAIASyIA.',
Le='Leanfro:BAAALgADCgEJAQAAAA==.Leifson:BAAALgAECgYJEAAAAA==.Leonedis:BAABLgAECn8ZAAIgAAYJ0w6ZKAA1AQAgAAYJ0w6ZKAA1AQAAAA==.Leothor:BAAALgAECgQJBAAAAA==.Lernen:BAABLgAECn8bAAQNAAcJzAxXZwBCAQANAAcJzAxXZwBCAQAmAAIJZgR0CQBNAAAjAAEJdQH4IgARAAAAAA==.Lesein:BAAALgAECgQJCQAAAA==.Lethea:BAAALgAECgQJCAAAAA==.Levious:BAAALgAECgEJAgAAAA==.',
Li='Liain:BAAALgADCgQJBAABLgADCggJEwAHAAAAAA==.Lianara:BAAALgADCggJGAABLgAECgYJEgAHAAAAAA==.Litenkuk:BAACLgAFFH8GAAInAAMJzw56FgDnAAAnAAMJzw56FgDnAAAuAAQKfyEAAycACAnYHxcRALICACcACAnYHxcRALICABsAAgkPD4suAIQAAAAA.Lithiel:BAAALgADCgYJCgAAAA==.Liuna:BAAALgADCgEJAQABLgAFFAMJBQAFAOgYAA==.',
Lo='Lohin:BAAALgADCgQJBAABLgAFFAYJCgAVAMoLAA==.Lonelycougar:BAAALgADCgcJDwAAAA==.Lore:BAAALgAECgkJLgAAAQ==.Lothstein:BAAALgAECgUJCQAAAA==.Lovely:BAAALgAECgcJDQAAAA==.',
Lu='Lukri:BAAALgAECgEJAQAAAA==.Luminate:BAABLgAECn8oAAIUAAgJdiOgBAD0AgAUAAgJdiOgBAD0AgAAAA==.Lunalah:BAAALgADCgcJBwAAAA==.Lunarray:BAAALgAECgEJAwAAAA==.Luxurious:BAABLgAECn8bAAIZAAcJZQO7EQCpAAAZAAcJZQO7EQCpAAAAAA==.',
Ly='Lyndea:BAAALgADCgYJBgAAAA==.',
['Lí']='Líllsnorre:BAAALgAECgMJBAAAAA==.',
Ma='Maaca:BAAALgADCgQJBAAAAA==.Madkow:BAAALgAECgQJBAAAAA==.Magichronic:BAAALgADCgYJCgAAAA==.Magnomonk:BAAALgAECgYJDQAAAA==.Majesticelf:BAAALgADCgcJCQAAAA==.Majuhstee:BAAALgADCgcJCAABLgAFFAEJAQAHAAAAAA==.Malachor:BAAALgAECgYJDwAAAA==.Maligned:BAABLgAECn8fAAICAAYJHx8UDwCBAQACAAYJHx8UDwCBAQAAAA==.Marsilea:BAAALgADCgcJCgABLgADCggJEwAHAAAAAA==.Martichoux:BAABLgAECn8WAAINAAkJKR2oPwB6AgANAAkJKR2oPwB6AgAAAA==.Marvyy:BAAALgADCggJCAAAAA==.Mash:BAAALgAECgEJAQAAAA==.Mathas:BAABLgAECn8jAAIJAAkJxB4oEQCJAgAJAAkJxB4oEQCJAgAAAA==.Mathilda:BAAALgADCgEJAQAAAA==.Mazes:BAABLgAECn8bAAMeAAYJ5h5WDgC9AQAeAAYJ5h5WDgC9AQAdAAEJqATfIQAoAAAAAA==.',
Mc='Mccholock:BAAALgAECgYJDwAAAA==.Mcmach:BAAALgAECgYJEwAAAA==.',
Me='Mediocrepaly:BAAALgAECgcJCQAAAA==.Mehaoloka:BAAALgADCgkJCQAAAA==.Mekanthis:BAACLgAFFH8SAAICAAUJSyIhAwCRAQACAAUJSiIhAwCRAQAuAAQKfyMAAgIACQk+JTsCAFEDAAIACQk+JTsCAFEDAAAA.Menoah:BAAALgAECgYJEQAAAA==.Menotthatorc:BAAALgAECgQJBQAAAA==.Merdoc:BAAALgAECgYJDAAAAA==.Meredith:BAAALgAECgYJEQAAAA==.Mesilana:BAAALgAECgYJBgAAAA==.Metalhoof:BAAALgAECgQJBwAAAA==.',
Mi='Michelangelo:BAAALgAECgEJAQAAAA==.Mikak:BAAALgAECgIJAQAAAA==.Milanova:BAAALgADCgYJDQABLgAECgcJEgAHAAAAAA==.Mirenna:BAAALgAECgYJEQAAAA==.Mirra:BAAALgAECgIJAgAAAA==.Misseymiss:BAAALgAECgQJBQAAAA==.',
Mo='Mogwhy:BAABLgAECn8fAAIdAAgJ+g79BQCTAQAdAAgJ+g79BQCTAQAAAA==.Molbeato:BAAALgAECgEJAgAAAA==.Monichan:BAAALgAECgQJBwAAAA==.Monkeypocket:BAAALgADCgQJBAAAAA==.Monkfu:BAAALgADCgcJAQAAAA==.Moonstrikex:BAAALgADCgUJBQAAAA==.Mooseknuckle:BAAALgAECgcJDgAAAA==.Moralekillas:BAAALgAFFAMJAwAAAA==.Morganna:BAAALgAECgEJAQAAAA==.Morior:BAAALgAECgYJEAAAAA==.Motorcade:BAABLgAECn8aAAIkAAgJrwErOAC3AAAkAAgJrwErOAC3AAAAAA==.',
Mu='Muchoblades:BAAALgAECgYJCwAAAA==.Murazor:BAAALgADCgUJBAAAAA==.Murples:BAAALgAFFAEJAQAAAA==.',
My='Myronastus:BAAALgADCgEJAQAAAA==.',
Ne='Neather:BAABLgAECn8YAAINAAcJEhItWwBeAQANAAcJEhItWwBeAQAAAA==.Neels:BAAALgADCgMJAwAAAA==.Neodke:BAAALgAECgEJAQAAAA==.Neodken:BAAALgADCgYJCgAAAA==.Neron:BAAALgAECgEJAQAAAA==.Nestlee:BAAALgADCgcJBwAAAA==.Nevvermore:BAAALgAECgMJAwAAAA==.Nexeon:BAAALgAECgEJAQABLgAECgcJFwAPAH8ZAA==.',
Ni='Niare:BAAALgAECgIJAgAAAA==.Ninfami:BAAALgADCggJCAAAAA==.Ninfamy:BAAALgADCgQJBQAAAA==.Ninfinite:BAABLgAECn8gAAIDAAgJ/Rv5FAAUAgADAAgJ/Rv5FAAUAgAAAA==.Nira:BAAALgAECggJDgAAAA==.',
No='Nockturne:BAAALgADCgMJAwAAAA==.Norasmina:BAAALgAECgEJAQAAAA==.Norr:BAABLgAECn8aAAIBAAgJViBcEwBfAgABAAgJViBcEwBfAgAAAA==.Northpaul:BAAALgADCgQJBAAAAA==.Notdeadyet:BAAALgAECgUJDQAAAA==.Notneels:BAAALgAECgQJBQAAAA==.',
Ny='Nyceria:BAAALgAECgUJCQAAAA==.Nyseria:BAAALgADCgEJAQAAAA==.',
Oa='Oakarm:BAAALgAECgkJAwAAAA==.',
Ob='Obpwnkenobi:BAAALgAECgQJEgAAAA==.',
Od='Odyssius:BAAALgAECgUJEQAAAA==.',
Og='Ogden:BAAALgAECgIJAgABLgAECggJIQAUAEUGAA==.',
Ol='Oldandblind:BAAALgAECgYJCwAAAA==.',
On='Ontherun:BAAALgADCgQJBQAAAA==.',
Op='Oprawinfury:BAAALgAECgYJEgAAAA==.',
Or='Oralia:BAAALgAECgYJBgAAAA==.Ordun:BAAALgAECgMJAwAAAA==.Orphani:BAAALgADCgIJAgAAAA==.',
Os='Oscarguydude:BAABLgAECn8aAAMfAAcJfxxSYABHAQAfAAUJMR1SYABHAQAnAAUJMBe+SgAnAQAAAA==.',
Ou='Ourus:BAABLgAECn8pAAMKAAkJBSPoAAAoAwAKAAkJBSPoAAAoAwAgAAgJJg9yMwDdAQAAAA==.',
Ow='Owlpha:BAAALgAECgYJCwAAAA==.',
Ox='Oxlob:BAABLgAECn8VAAIBAAgJUxHHRAB3AQABAAgJUxHHRAB3AQAAAA==.',
Pa='Pallaminnow:BAAALgAECgIJAgAAAA==.Pallychef:BAAALgADCgYJCgABLgAECgYJFgABACUaAA==.Panax:BAAALgADCgcJBwAAAA==.Pawtyr:BAAALgAECgEJAQABLgAECggJIQAHAAAAAQ==.',
Pe='Peachieriest:BAAALgAECgMJAQAAAA==.Pele:BAAALgAECgYJDgAAAA==.Perpetrator:BAABLgAECn8aAAICAAgJbwIlIADCAAACAAgJbwIlIADCAAAAAA==.',
Ph='Pheonix:BAAALgADCgYJBgAAAA==.Phyre:BAAALgADCggJDQAAAA==.',
Pi='Pikahboo:BAAALgADCgYJBgAAAA==.',
Po='Poepwn:BAABLgAECn8hAAIQAAcJshF5HwBLAQAQAAcJshF5HwBLAQAAAA==.',
Pr='Priestbot:BAAALgADCgcJCwAAAA==.Promo:BAAALgADCgIJAgAAAA==.Prydae:BAAALgADCgQJBwAAAA==.',
Pu='Putnamehere:BAAALgAECgEJAQAAAA==.',
Py='Pynelope:BAAALgADCgMJAwAAAA==.',
['Pû']='Pûrplehaze:BAAALgAECgMJAwAAAA==.',
Qu='Quelude:BAAALgAECgcJDQAAAA==.Quill:BAABLgAECn8VAAMOAAkJxRXuKQAKAgAOAAkJxRXuKQAKAgASAAMJwRMVIgCNAAAAAA==.',
Ra='Raeris:BAEALgAECgcJAQAAAA==.Raicleach:BAAALgAECgkJCAAAAA==.Rainbow:BAAALgADCgcJDAAAAA==.Raktan:BAAALgAECgIJAgAAAA==.Rancidgreen:BAAALgADCgYJCAAAAA==.Rannick:BAAALgAECgYJEAAAAA==.Ranua:BAABLgAECn8uAAMUAAkJBiJtDQBeAgAUAAkJBiJtDQBeAgAFAAYJqwwWLgD9AAAAAA==.Ratio:BAABLgAECn8aAAIDAAYJvB/pHwDJAQADAAYJvB/pHwDJAQAAAA==.Ravenhunt:BAAALgAECgQJBAAAAA==.Ravenreaper:BAAALgADCgMJBAAAAA==.Rawmanu:BAAALgADCgcJBwAAAA==.',
Re='Reania:BAAALgADCgUJCAAAAA==.Rectified:BAAALgAECgYJCwAAAA==.Redbreastman:BAAALgAECgYJDgAAAA==.Rekka:BAAALgAECgQJBAAAAA==.Reoshe:BAAALgAECgEJAQAAAA==.',
Ri='Ripdvanwinkl:BAABLgAECn8WAAIDAAYJBRDUTgAMAQADAAYJBRDUTgAMAQAAAA==.',
Ro='Roachpocket:BAAALgADCggJCgAAAA==.Ronyn:BAABLgAECn8VAAMUAAYJUB74FwDyAQAUAAYJUB74FwDyAQAFAAEJVQhbagAsAAAAAA==.',
Ru='Rudolf:BAAALgAECgQJBQAAAA==.',
Rw='Rwarar:BAAALgADCgUJCAAAAA==.Rwqr:BAAALgADCgYJBwAAAA==.',
['Rä']='Räiden:BAAALgAECgUJCQAAAA==.',
['Rö']='Rötthgard:BAAALgADCgkJCgAAAA==.',
Sa='Salacakei:BAABLgAECn8nAAMeAAkJQRcfBQBvAgAeAAkJQRcfBQBvAgAdAAQJBwv6EwC/AAAAAA==.Salin:BAAALgAECgcJDAAAAA==.Salithril:BAAALgADCgMJBQAAAA==.Sanzo:BAAALgADCgMJAwABLgAECgcJEAAHAAAAAA==.Sarthiy:BAAALgAECgcJDwABLgAFFAUJGQAIAPojAA==.Sarthy:BAACLgAFFH8ZAAIIAAUJ+iOOAACVAQAIAAUJ+iOOAACVAQAuAAQKfzEAAggACQkeJGYAAJcDAAgACQkeJGYAAJcDAAAA.Sassaphras:BAABLgAECn8VAAIMAAcJNx/jEQBSAgAMAAcJNx/jEQBSAgAAAA==.Satheron:BAAALgAECgYJCAAAAA==.Satyric:BAAALgAECgIJAgAAAA==.Saxifon:BAAALgADCgQJBAAAAA==.',
Sc='Scarletpaw:BAAALgAECgUJCAAAAA==.Scoobie:BAAALgAECgMJAwABLgAECgcJFAAfABcXAA==.Scoobydo:BAAALgAECgEJAQABLgAECgcJFAAfABcXAA==.Screwwithme:BAAALgADCgYJBgAAAA==.Scrubs:BAACLgAFFH8PAAIfAAQJ6QlLDQD1AAAfAAQJ6QlLDQD1AAAuAAQKfyIAAh8ACAkXHFQfAEkCAB8ACAkXHFQfAEkCAAAA.',
Se='Seriadrina:BAAALgADCgIJAgAAAA==.',
Sh='Shaadow:BAAALgAECgEJAQAAAA==.Shallabal:BAAALgAECgcJAgAAAA==.Shamyaltak:BAAALgAECgkJDAAAAA==.Shandralore:BAAALgAECgYJEQAAAA==.Shauranna:BAAALgAECgMJAwAAAA==.Shiel:BAAALgAECgYJDwAAAA==.Shockdoctor:BAABLgAECn8cAAIUAAcJICTkCgB/AgAUAAcJICTkCgB/AgAAAA==.Shogunasasin:BAABLgAECn8bAAMQAAgJBQ2zKQBnAQAQAAgJBQ2zKQBnAQAPAAMJuxqLTQDbAAAAAA==.Shortrange:BAAALgAECgcJEwAAAA==.Shuzui:BAAALgADCgQJBAAAAA==.',
Si='Sicarion:BAAALgAECgQJDQAAAA==.Silentwalkr:BAAALgAECgIJAgAAAA==.',
Sl='Sleples:BAABLgAECn8UAAMfAAcJFxeVPQC4AQAfAAcJ6xWVPQC4AQAbAAYJVRXyFABsAQAAAA==.Sleyalias:BAAALgAECgEJAQAAAA==.Slufgor:BAAALgAECgQJBwAAAA==.',
Sm='Smolder:BAAALgADCgkJFAAAAA==.',
Sn='Snoo:BAAALgAECgYJDAAAAA==.Snoogon:BAAALgAECgUJBgABLgAECgYJDAAHAAAAAA==.Snorrehunter:BAAALgAECgQJBgAAAA==.',
So='Solarlite:BAAALgAECgEJAQAAAA==.Solek:BAAALgADCgIJAgAAAA==.Solorion:BAAALgAECgYJCQAAAA==.Sorovar:BAABLgAECn8VAAIXAAkJXSABCAC/AgAXAAkJXSABCAC/AgAAAA==.',
Sp='Spamm:BAAALgAECgYJCQAAAA==.Spony:BAAALgAECgQJCwAAAA==.',
St='Starbrow:BAAALgAECgQJCQABLgAECggJGwATAB8hAA==.Stein:BAAALgADCgYJBgAAAA==.Steinn:BAAALgADCgEJAQAAAA==.Stevewinwood:BAAALgAECgYJCgAAAA==.Stormlight:BAABLgAECn8UAAIOAAgJKwy4MABdAQAOAAgJKwy4MABdAQAAAA==.',
Su='Summernight:BAAALgAECgEJAgAAAA==.Sushistryke:BAAALgAECgYJDAAAAA==.',
Sy='Syland:BAAALgAECgUJDgAAAA==.Sylanis:BAAALgADCgcJBwAAAA==.Sylissa:BAAALgADCgUJCAAAAA==.Sylvanäs:BAAALgAECgUJEAAAAA==.Sylvenna:BAAALgAECgYJDAAAAA==.Sypress:BAAALgADCgcJDgAAAA==.Syrelastus:BAAALgAECgEJAQAAAA==.Sysna:BAABLgAECn8XAAIEAAYJ2SJeDAAAAgAEAAYJ2SJeDAAAAgAAAA==.',
Ta='Tachyon:BAAALgAECgEJAQAAAA==.Talley:BAABLgAECn8nAAIUAAgJZBbcHwC0AQAUAAgJZBbcHwC0AQAAAA==.Targis:BAAALgAECgYJEwAAAA==.Tauran:BAAALgAECgQJCAAAAA==.Tazanaz:BAAALgAECgQJCAABLgAECgkJLgAUAAYiAA==.',
Te='Templeton:BAAALgAECgYJCwABLgAECggJIQAUAEUGAA==.Tendai:BAAALgADCgkJGAAAAA==.Tenloth:BAAALgAECgYJDwAAAA==.Teozr:BAAALgADCgMJAwAAAA==.Teufelshund:BAAALgADCgcJBwAAAA==.',
Th='Thaeldrin:BAAALgADCgEJAQAAAA==.Thaleas:BAABLgAECn8YAAIIAAYJeBpLDwBEAQAIAAYJeBpLDwBEAQAAAA==.Thorizine:BAAALgADCgMJAwAAAA==.Thorlas:BAABLgAECn8WAAMUAAcJNx35NgCnAQAUAAYJ0x75NgCnAQAFAAYJQRjxIQBBAQAAAA==.Thorsham:BAAALgAECgYJBgAAAA==.',
Ti='Timadin:BAAALgADCgEJAQAAAA==.Timmúk:BAAALgAECgMJAwAAAA==.',
To='Tomma:BAABLgAECn8WAAICAAkJ9CB/BgDOAgACAAkJ9CB/BgDOAgAAAA==.Totem:BAAALgADCggJCAAAAA==.Totembi:BAACLgAFFH8MAAIUAAQJFBZnEQA3AQAUAAQJFBZnEQA3AQAuAAQKfzkAAhQACQlmH/gEAO4CABQACQlmH/gEAO4CAAAA.',
Tr='Trailerpark:BAAALgAECgYJDwAAAA==.Tratre:BAABLgAECn8qAAQWAAkJuhZ+CQA0AgAWAAkJuhZ+CQA0AgAVAAYJcQqIFQDqAAAaAAEJYxISPQA6AAAAAA==.Treynof:BAABLgAECn8VAAIRAAcJBgzNJAAVAQARAAcJBgzNJAAVAQAAAA==.Truewill:BAAALgADCgEJAQAAAA==.Trupeti:BAABLgAECn8WAAIhAAYJJwriHADyAAAhAAYJJwriHADyAAAAAA==.',
Tu='Tulsiice:BAABLgAECn8XAAINAAgJ2hWrLADvAQANAAgJ2hWrLADvAQAAAA==.',
Tw='Twoglaivez:BAAALgAECgUJBQABLgAFFAcJGgAgAFQfAA==.',
Ty='Tytaniormu:BAAALgAECgkJEgAAAA==.',
['Tê']='Tês:BAAALgADCgEJAQAAAA==.',
Ug='Ugless:BAAALgADCgYJBgABLgADCgcJCAAHAAAAAA==.Uglify:BAAALgADCgcJCAAAAA==.',
Ul='Ulanmonk:BAAALgADCgMJAwAAAA==.Ulridan:BAAALgAECgEJAQABLgAFFAMJBQAFAOgYAA==.',
Un='Undeathtwoy:BAABLgAECn8fAAMTAAcJpR1caAC9AQATAAcJPxpcaAC9AQACAAUJJhSpGwDnAAAAAA==.Undos:BAAALgAECgEJAQAAAA==.Unholyveri:BAAALgAECgYJBgAAAA==.',
Va='Vaelraen:BAABLgAECn8VAAIBAAcJBBSvRQB0AQABAAcJBBSvRQB0AQAAAA==.Valcher:BAAALgAECgQJCgAAAA==.Valendera:BAABLgAECn8VAAIYAAkJEQsCYACpAQAYAAkJEQsCYACpAQAAAA==.Valhri:BAAALgAECgIJBAAAAA==.Valifadin:BAAALgAECgYJEQAAAA==.Valith:BAAALgAECgQJCQAAAA==.Valmoria:BAAALgADCgkJFwAAAA==.Valndrevy:BAAALgADCgUJDAAAAA==.Vansan:BAAALgAECgYJCQABLgAECgkJLgAUAAYiAA==.Varch:BAAALgAECgYJBwAAAA==.',
Ve='Vellas:BAAALgAECgEJAQAAAA==.Venngennce:BAABLgAECn8hAAMoAAkJFB6wAADQAgAoAAkJFB6wAADQAgATAAMJ4Ar++wCDAAAAAA==.',
Vi='Vintage:BAACLgAFFH8LAAIGAAMJjQ4UAQDsAAAGAAMJjQ4UAQDsAAAuAAQKfyIAAgYACQnpGfYAAAMDAAYACQnpGfYAAAMDAAAA.Visage:BAAALgADCgYJBgAAAA==.',
Vo='Voided:BAABLgAECn8UAAITAAgJmiA7DQCbAgATAAgJmiA7DQCbAgAAAA==.Volkareth:BAABLgAECn8VAAIaAAkJyhPNDQD9AQAaAAkJyhPNDQD9AQAAAA==.Vorkath:BAABLgAECn8oAAQaAAgJzCLWAADCAgAaAAgJzCLWAADCAgAVAAcJ0h6/BQA1AgAWAAEJmx+RWABcAAAAAA==.Vormette:BAAALgADCgkJEwAAAA==.',
Vt='Vtae:BAABLgAECn8YAAIfAAgJhAyCLwCQAQAfAAgJhAyCLwCQAQAAAA==.',
Wa='Waka:BAAALgADCgkJCQABLgAECggJFQABAFMRAA==.Waryndor:BAAALgADCgYJBgAAAA==.',
We='Werehamster:BAABLgAECn8bAAIOAAYJKBn5LwBhAQAOAAYJKBn5LwBhAQAAAA==.',
Wi='Wilderbeast:BAABLgAECn8aAAIOAAkJkwQrQQAOAQAOAAkJkwQrQQAOAQAAAA==.Wildlife:BAAALgADCgEJAQAAAA==.',
Wo='Woodrow:BAAALgADCgcJDgABLgAECggJIQAUAEUGAA==.Woxkal:BAABLgAECn8eAAMCAAcJDQqfGwDoAAACAAcJDQqfGwDoAAATAAEJ0AGqNwEhAAAAAA==.',
Wu='Wubblebubble:BAABLgAECn8fAAMCAAgJCAwNFAA4AQACAAgJmgsNFAA4AQATAAQJBgYWlQC2AAAAAA==.',
Xa='Xaelin:BAAALgAECgYJDAAAAA==.',
Yi='Yisús:BAAALgAECgQJBwAAAA==.',
Yl='Ylvis:BAABLgAECn8gAAIfAAgJtBZkHgDlAQAfAAgJtBZkHgDlAQAAAA==.',
Yo='Yoshymi:BAAALgAECggJIQAAAQ==.',
Yu='Yuná:BAAALgADCgMJAwAAAA==.',
Yv='Yvetal:BAAALgAECgIJAgABLgAECgQJBQAHAAAAAA==.',
Za='Zacco:BAAALgAECgYJEgAAAA==.Zaleth:BAACLgAFFH8KAAIVAAYJyguqDQA4AQAVAAYJyguqDQA4AQAuAAQKfyUAAhUABwkYIacIALACABUABwkYIacIALACAAAA.Zamazenta:BAAALgADCgcJCwAAAA==.Zaranne:BAABLgAECn8aAAITAAkJkAq+LwC6AQATAAkJkAq+LwC6AQAAAA==.Zargar:BAAALgADCgYJBgAAAA==.Zarion:BAAALgAECgYJCAABLgAFFAYJCgAVAMoLAA==.Zarra:BAAALgAECgUJBwAAAA==.Zathuera:BAAALgADCgQJBAAAAA==.',
Ze='Zeroz:BAAALgAECgcJEAAAAA==.',
Zh='Zhath:BAAALgAECgIJBAAAAA==.',
Zi='Zilik:BAAALgAFFAIJAwABLgAFFAYJCgAVAMoLAA==.',
Zo='Zocorro:BAAALgAECgQJCgAAAA==.Zodiack:BAAALgAECgcJCQAAAA==.Zombe:BAABLgAECn8VAAITAAgJCAmtegCPAQATAAgJCAmtegCPAQAAAA==.',
Zu='Zuelmst:BAAALgAECgIJAgAAAA==.',
['Ân']='Ângel:BAAALgAFFAEJAQAAAA==.',
['Ðe']='Ðecision:BAACLgAFFH8GAAIBAAIJkyEfHQC5AAABAAIJkyEfHQC5AAAuAAQKfyAAAgEACQmPI6gRAAQDAAEACQmPI6gRAAQDAAAA.',
['Øn']='Ønslaught:BAAALgADCgUJBQABLgAECggJFQABAFMRAA==.',
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
