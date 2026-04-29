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

local lookup = {'Paladin-Retribution','Unknown-Unknown','Shaman-Elemental','Rogue-Subtlety','Paladin-Holy','Druid-Feral','Mage-Frost','Druid-Balance','Druid-Restoration','Shaman-Restoration','Evoker-Augmentation','Evoker-Preservation','Priest-Holy','DemonHunter-Devourer','Evoker-Devastation','Hunter-Survival','Warlock-Destruction','Warlock-Demonology','DeathKnight-Blood','Warrior-Fury','DemonHunter-Havoc','DemonHunter-Vengeance','Shaman-Enhancement','DeathKnight-Unholy','Druid-Guardian','Hunter-BeastMastery','Mage-Arcane','Monk-Brewmaster','Rogue-Assassination','Warrior-Arms','Rogue-Outlaw','Hunter-Marksmanship','Warrior-Protection','Monk-Mistweaver','Paladin-Protection','Monk-Windwalker','Priest-Discipline','DeathKnight-Frost',}
local provider = {region='US',realm='Uldum',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abmikaze:BAAALgADCgEJAQAAAA==.',
Ad='Adorean:BAABLgAECn8WAAIBAAYJ6RdeGwBKAQABAAYJ6RdeGwBKAQAAAA==.',
Ae='Aeginau:BAAALgAECgMJAwAAAA==.Aenymbria:BAAALgAECgYJEgAAAA==.Aerbear:BAAALgADCgQJBAAAAA==.',
Ag='Age:BAAALgAECgUJEgAAAA==.',
Ai='Aimnskin:BAAALgADCggJEgAAAA==.',
Ak='Akuaa:BAAALgADCgMJAwAAAA==.',
Al='Alburm:BAAALgAECgUJBQAAAA==.Alexstraxsa:BAAALgADCgkJJwAAAA==.Aliine:BAAALgAECgcJEwAAAA==.Ally:BAAALgADCgkJCQABLgAECgUJDgACAAAAAA==.Althaea:BAAALgAECgQJCQAAAA==.',
Am='Ameiisaa:BAAALgADCgcJCgAAAA==.Amytiel:BAABLgAECn8lAAIDAAgJGhw1FwBeAgADAAgJGhw1FwBeAgAAAA==.',
An='Anahana:BAAALgAECgYJCAAAAA==.Anali:BAAALgADCggJEAAAAA==.Andi:BAAALgAECgcJDwAAAA==.Andorelia:BAAALgAECgYJEQAAAA==.Andronocus:BAAALgADCggJFQAAAA==.Anko:BAAALgADCgQJAwAAAA==.Anxie:BAAALgAECgcJAwAAAA==.Anìtamaxwynn:BAAALgAECgYJCwABLgAFFAUJBwAEAMMRAA==.',
Ap='Apally:BAAALgAECgQJCQAAAA==.Apexmaster:BAAALgAECgUJBQAAAA==.Appleborne:BAAALgADCgcJBwAAAA==.Appleseed:BAAALgADCgMJBQAAAA==.Apprentice:BAAALgAECgYJDQAAAA==.',
Ar='Aragorn:BAAALgAECgYJCAAAAA==.Aramos:BAABLgAECn8YAAIFAAYJzhtVCwCKAQAFAAYJzhtVCwCKAQAAAA==.Aramôs:BAAALgAECgUJCAAAAA==.Ares:BAAALgADCgYJCwAAAA==.Arinathia:BAAALgAECgcJAQAAAA==.Arta:BAAALgAECgUJCAAAAA==.Aruncusdio:BAABLgAECn8cAAIGAAgJaQZVBQAyAQAGAAgJaQZVBQAyAQAAAA==.',
As='Ashhealz:BAAALgAECgYJDgAAAA==.Ashlei:BAAALgADCgEJAQAAAA==.Asteroid:BAAALgAECgEJAQAAAA==.',
At='Atelwen:BAAALgAECgUJBgAAAA==.',
Av='Aveme:BAABLgAECn8nAAIHAAkJ0yDdBABrAgAHAAkJ0yDdBABrAgAAAA==.',
Aw='Awartedpeen:BAAALgAECgUJCAAAAA==.',
Az='Azael:BAAALgAECgEJAQABLgAECgIJAwACAAAAAA==.Azuleon:BAAALgAECgYJEQAAAA==.',
Ba='Bagelmancer:BAAALgADCgUJBQAAAA==.Bamber:BAAALgADCggJDQAAAA==.Battar:BAAALgADCgcJDAAAAA==.Bayraktar:BAAALgADCgkJDgAAAA==.',
Bb='Bbads:BAAALgADCgIJAgAAAA==.',
Be='Beaker:BAABLgAECn8ZAAIIAAYJAh4uCQBcAQAIAAYJAh4uCQBcAQAAAA==.Beastmode:BAABLgAECn8bAAIJAAgJ2xnmCADQAQAJAAgJ2xnmCADQAQAAAA==.Bedlem:BAAALgAECgYJDgAAAA==.Beerchaplain:BAAALgADCgcJFgABLgAECgcJBwACAAAAAA==.Bernard:BAABLgAECn8YAAMKAAcJ1AV/XwAOAQAKAAcJ1AV/XwAOAQADAAMJFgenIQBXAAAAAA==.',
Bi='Bidoof:BAABLgAECn8UAAMLAAcJCw0XEQDeAAALAAYJQw8XEQDeAAAMAAUJcQ0hNQDDAAAAAA==.Bigolman:BAAALgAECgEJAQAAAA==.Biochemguy:BAAALgAECgUJAQAAAA==.Birgitte:BAAALgAECgYJCAAAAA==.',
Bl='Blackelvis:BAAALgADCgcJBwABLgAECgkJFQANAP0PAA==.Blacklisted:BAABLgAECn8VAAINAAkJ/Q8fBQDZAQANAAkJ/Q8fBQDZAQAAAA==.Blackup:BAAALgAECgMJAwAAAA==.Blackvortex:BAAALgADCggJCgAAAA==.Bloodybloodz:BAAALgAECgIJAgABLgAECgYJDgACAAAAAA==.Bloodyburst:BAAALgADCgYJBgABLgAECgYJDgACAAAAAA==.Bloodyfistz:BAAALgAECgYJDgAAAA==.Blueshift:BAABLgAECn8VAAIOAAgJfhg9QwDnAQAOAAgJfhg9QwDnAQAAAA==.Bluethreetwo:BAAALgAECgMJCAAAAA==.Blurry:BAAALgADCgEJAQAAAA==.',
Bo='Bookofzeref:BAAALgAECgYJDAAAAA==.',
Br='Brahruhanu:BAEALgADCgQJBAAAAA==.Braile:BAAALgAECgQJCQAAAA==.Brayend:BAAALgAECgUJDAAAAA==.Brewbelly:BAAALgADCgEJAQAAAA==.Brimscythe:BAABLgAECn8dAAIPAAgJoh2vBQCgAgAPAAgJoh2vBQCgAgAAAA==.',
Bu='Bubbleup:BAAALgADCgUJBQAAAA==.',
Ca='Caliandis:BAAALgAECgUJBQAAAA==.Calvey:BAAALgAECgMJAwAAAA==.Cambrai:BAAALgAECgUJCQAAAA==.Cannabelle:BAABLgAECn8fAAIQAAgJnyT/AABmAwAQAAgJnyT/AABmAwAAAA==.Carclias:BAABLgAECn8YAAMRAAgJZRosBwBXAgARAAgJZRosBwBXAgASAAIJPgWtBQFRAAAAAA==.Carmenere:BAAALgADCgUJCQAAAA==.Carthrix:BAAALgAECgYJDAAAAA==.Cattlerage:BAAALgAECgEJAQAAAA==.',
Ce='Cedo:BAAALgADCgUJBQAAAA==.Celéste:BAAALgADCgcJBwAAAA==.',
Ch='Chaoscookies:BAABLgAECn8iAAMRAAgJQxgQHgBfAQARAAUJXBcQHgBfAQASAAQJmBfeMwCyAAAAAA==.Chaotik:BAAALgADCgcJDAAAAA==.Chaplain:BAAALgAECgcJBwAAAA==.Chartkov:BAAALgAECgQJBwAAAA==.Cheekichik:BAAALgADCgQJBAAAAA==.Cheeseballer:BAAALgAFFAQJBAAAAA==.Cheesebur:BAAALgADCgcJBwAAAA==.Chighas:BAAALgADCgQJBwAAAA==.Choofi:BAABLgAECn8ZAAIJAAYJiRYQDQCCAQAJAAYJiRYQDQCCAQAAAA==.Chubbytoyboy:BAAALgADCgUJBQABLgAECggJIAADACIdAA==.',
Ci='Ciená:BAAALgADCgMJAwAAAA==.Cin:BAAALgAECgQJBAAAAA==.Cinderpetal:BAAALgAECgEJAQAAAA==.',
Co='Comlock:BAAALgAECgQJCAAAAA==.Complacent:BAAALgAECgYJEAAAAA==.Coomtheory:BAAALgAECgYJCAAAAA==.Corik:BAAALgADCgMJAwAAAA==.',
Cr='Cragn:BAAALgAECgIJBQAAAA==.Crownman:BAAALgADCgUJCAAAAA==.Crunchyblue:BAAALgADCgIJAgAAAA==.',
Cu='Cuddilz:BAAALgAECgUJCgAAAA==.',
Cy='Cyclonic:BAAALgADCgYJBwAAAA==.Cyonicus:BAABLgAECn8WAAISAAYJRhuEDgCeAQASAAYJRhuEDgCeAQAAAA==.Cyska:BAABLgAECn8fAAITAAkJUxTUAgDWAQATAAkJUxTUAgDWAQAAAA==.',
['Cé']='Cécé:BAABLgAECn8UAAIBAAcJjyLXBABPAgABAAcJjyLXBABPAgAAAA==.',
Da='Daciana:BAAALgAECgUJCAAAAA==.Dagaroonie:BAAALgAECgcJCAAAAA==.Dagevas:BAABLgAECn8UAAISAAYJvhTXbQCFAQASAAYJvhTXbQCFAQAAAA==.Darkeznite:BAAALgAECgYJCgAAAA==.Darksoldier:BAAALgAECgQJBAAAAA==.Darthqueso:BAAALgADCgMJAwAAAA==.Dartoy:BAABLgAECn8dAAIUAAcJKgQnFQDyAAAUAAcJKgQnFQDyAAAAAA==.Davriell:BAAALgADCgcJDQAAAA==.Dax:BAAALgAECgUJCQAAAA==.Dazling:BAAALgAECgQJBAAAAA==.',
De='Deathkess:BAAALgAECgcJBwAAAA==.Deathlokk:BAAALgAECgYJCQAAAA==.Deeppurple:BAAALgAECgQJBwAAAA==.Deezmons:BAABLgAECn8aAAIVAAcJyBDqBQBhAQAVAAcJyBDqBQBhAQAAAA==.Deholybagel:BAAALgAECgQJBQAAAA==.Del:BAABLgAECn8ZAAIWAAYJsia5AAA3AgAWAAYJsia5AAA3AgAAAA==.Demoncheese:BAAALgADCgYJCAAAAA==.Demondag:BAAALgADCgcJDAAAAA==.Demoniaca:BAAALgAECgIJAgAAAA==.Demonlarrik:BAAALgADCgIJAgAAAA==.Derale:BAABLgAECn8aAAMLAAgJiw37JQCNAQALAAgJiA37JQCNAQAPAAcJXQQpIgAZAQAAAA==.',
Dh='Dhargal:BAABLgAECn8eAAIDAAcJdyThDQDEAgADAAcJdyThDQDEAgAAAA==.',
Di='Dial:BAAALgADCgkJGQAAAA==.Dichotomy:BAAALgADCgQJBAAAAA==.Divus:BAAALgAECgYJCgAAAA==.',
Dk='Dkfaros:BAAALgAECgQJDwAAAA==.',
Do='Donko:BAAALgADCggJCAABLgAECgQJBQACAAAAAA==.Dontcarebear:BAAALgAECgMJBwAAAA==.Doofnshmirtz:BAABLgAECn8XAAIXAAYJRx0CAwCsAQAXAAYJRx0CAwCsAQAAAA==.Dotpocket:BAABLgAECn8UAAISAAYJaBgoXAC0AQASAAYJaBgoXAC0AQAAAA==.',
Dr='Drakenn:BAAALgAECgcJDgAAAA==.Draéne:BAAALgAECgQJBQAAAA==.Dreadly:BAAALgADCgUJCAAAAA==.Dreadp:BAAALgADCgIJAgAAAA==.Dreamfyre:BAAALgAECgEJAQAAAA==.Dremmy:BAAALgAECgYJEQAAAA==.Dripdasini:BAAALgADCgUJBQAAAA==.Droki:BAABLgAECn8UAAIXAAYJuh8nAwCkAQAXAAYJuh8nAwCkAQAAAA==.',
Du='Dunsel:BAAALgADCgcJCAABLgAECggJHQAPAKIdAA==.Dunwich:BAAALgADCgcJIAAAAA==.',
Dv='Dvali:BAAALgADCgcJBwAAAA==.',
Dy='Dyorra:BAAALgAECgMJBAAAAA==.',
Eb='Ebonshade:BAAALgADCgcJCgABLgAECgIJAgACAAAAAA==.',
Ed='Edgardapoe:BAAALgADCgYJBgABLgAECgEJAQACAAAAAA==.Edginglord:BAAALgAECgUJBgAAAA==.',
Eh='Ehmill:BAABLgAECn8YAAIYAAYJLRrgFABrAQAYAAYJLRrgFABrAQAAAA==.',
El='Elesrya:BAAALgADCgQJBwABLgAECgYJEgACAAAAAA==.Elventhing:BAAALgAECgYJCQAAAA==.',
Em='Emmå:BAAALgADCgEJAQAAAA==.Emshady:BAAALgADCgcJBwAAAA==.',
Eo='Eomær:BAAALgAECgEJAQAAAA==.',
Ep='Epsilòn:BAEALgAECgcJAQABLgAECgcJAQACAAAAAA==.',
Er='Ernest:BAAALgADCgUJBgAAAA==.Errani:BAAALgAECgMJBgAAAA==.',
Es='Eskers:BAAALgAECgYJCwAAAA==.Estralla:BAAALgADCgQJBAAAAA==.',
Eu='Eureki:BAAALgAECgcJEQAAAA==.',
Ev='Evilkarma:BAAALgAECgYJDwAAAA==.Evocatis:BAACLgAFFH8GAAIBAAMJWxiaCAAJAQABAAMJWxiaCAAJAQAuAAQKfx0AAwEACAlyITUeALYCAAEABwlGJDUeALYCAAUAAwkOCwB2AKIAAAAA.Evoorc:BAAALgADCgEJAQAAAA==.',
Ex='Ex:BAAALgAECgYJEgAAAA==.',
Fa='Faasht:BAAALgADCgcJDQAAAA==.Fayde:BAAALgADCgUJBAAAAA==.',
Fe='Felzbirt:BAAALgADCgYJCwAAAA==.Fenehdis:BAAALgAECgYJCwAAAA==.Ferg:BAAALgADCgcJBwAAAA==.Ferula:BAAALgADCgEJAgABLgAECgUJCAACAAAAAA==.',
Fi='Fiftycaliber:BAAALgAECgQJBAAAAA==.Firebirdxx:BAAALgADCgcJBwABLgAECggJHQAJACUjAA==.Firebirdz:BAABLgAECn8dAAIJAAgJJSO1CAADAwAJAAgJJSO1CAADAwAAAA==.Firebirdzx:BAAALgADCgYJBwABLgAECggJHQAJACUjAA==.Firebirdzz:BAAALgAECgQJBwAAAA==.Fizzystomps:BAAALgADCgYJBwAAAA==.',
Fo='Forque:BAAALgADCgQJAwAAAA==.Fortybelow:BAAALgAECgQJCAAAAA==.',
Fr='Frostypaw:BAAALgADCgQJBAAAAA==.',
Fu='Fuzzybut:BAAALgAECgMJBAAAAA==.',
Ga='Gark:BAAALgAECgMJAwAAAA==.Garkk:BAAALgADCgUJCAAAAA==.Gazzi:BAAALgAECggJEQAAAA==.',
Gi='Gióvanna:BAAALgADCgkJIQAAAA==.',
Gl='Glaivedigger:BAAALgADCgIJAwABLgAECgQJBgACAAAAAA==.',
Go='Goobo:BAABLgAECn8eAAIYAAkJSw71BwAAAgAYAAkJSw71BwAAAgAAAA==.Goodheavens:BAAALgAECgEJAQAAAA==.Goonlock:BAAALgADCgYJCwAAAA==.Gorbb:BAAALgADCgQJBAAAAA==.Gotenk:BAAALgAECgQJBAAAAA==.Goudafel:BAAALgADCgcJDgAAAA==.Goyim:BAABLgAECn8dAAIHAAgJyA3WdwDiAQAHAAgJyA3WdwDiAQAAAA==.',
Gr='Gr:BAAALgAECgYJDwAAAA==.Grewbacca:BAAALgADCgMJAwAAAA==.Grimkrieg:BAABLgAECn8iAAIZAAgJtxmIAQABAgAZAAgJtxmIAQABAgAAAA==.Grody:BAAALgADCgYJBgAAAA==.',
Gu='Guroo:BAABLgAECn8XAAIaAAYJLxUxEwBiAQAaAAYJLxUxEwBiAQAAAA==.',
['Gá']='Gárp:BAAALgAECgIJAgAAAA==.',
['Gø']='Gødoth:BAABLgAECn8cAAMDAAcJgyDUAgAfAgADAAcJgyDUAgAfAgAKAAQJDCP1OwCSAQAAAA==.',
Ha='Hagarn:BAABLgAECn8aAAIBAAgJsQ0XFwBoAQABAAgJsQ0XFwBoAQAAAA==.Halimah:BAAALgADCgMJAwAAAA==.Halloffame:BAAALgAECgIJAQAAAA==.Hamsham:BAAALgAECgEJAQAAAA==.Harleypaw:BAAALgADCgQJBAAAAA==.Harleypuddin:BAAALgAECgkJBwAAAA==.Harlydorable:BAAALgAECgkJBAAAAA==.',
He='Healmemaybe:BAAALgAECgYJDAAAAA==.Hemour:BAAALgAECgUJBQAAAA==.Hexmachine:BAAALgAECgkJAwAAAA==.',
Hi='Hirak:BAAALgADCgIJAgABLgAFFAYJFAANAH4TAA==.',
Ho='Hogarth:BAAALgADCgEJAQAAAA==.Holmstein:BAAALgAECgIJAgAAAA==.Hotnsoursoup:BAAALgADCgcJCgAAAA==.',
Hu='Hunkules:BAAALgAECgYJCAAAAA==.',
['Hë']='Hëllsoldier:BAAALgADCgMJAwAAAA==.',
Ia='Iamahriman:BAABLgAECn8YAAIDAAYJCgyaEQD4AAADAAYJCgyaEQD4AAAAAA==.Iamthanatos:BAAALgADCgYJBgAAAA==.',
Id='Idblastdat:BAABLgAECn8WAAIHAAYJSBnbGwBtAQAHAAYJSBnbGwBtAQAAAA==.',
Ig='Ignite:BAAALgAECgYJCAAAAA==.',
Il='Iliana:BAAALgAECgIJAQAAAA==.Illestria:BAABLgAECn8cAAIBAAcJvxdzFwBlAQABAAcJvxdzFwBlAQAAAA==.Illumiscotty:BAABLgAECn8ZAAMHAAkJpR+HAQDkAgAHAAkJNB6HAQDkAgAbAAIJBh8YEQCxAAAAAA==.Ilwey:BAAALgAECgcJCwAAAA==.',
Im='Immortamonk:BAABLgAECn8XAAIcAAYJPB9PJgDSAQAcAAYJPB9PJgDSAQAAAA==.Immórtál:BAAALgADCgUJBQABLgAECgYJFwAcADwfAA==.',
In='Insania:BAAALgAECgcJDQAAAA==.Invisagal:BAAALgAECgIJAwAAAA==.',
Io='Ionni:BAAALgADCgQJBAAAAA==.Iosefka:BAAALgADCgQJBAAAAA==.',
Ir='Ironhands:BAAALgAECgEJAQAAAA==.',
Iz='Izara:BAAALgADCgcJFgAAAA==.',
Ja='Jarlmaxim:BAAALgAECgUJCwAAAA==.Jasindra:BAAALgADCgcJFwABLgAECggJJQAKAPMbAA==.',
Ji='Jin:BAAALgADCgEJAQAAAA==.',
Jo='Jolinascrubs:BAAALgAECgYJEwABLgAFFAMJBwAaAKUIAA==.Jonjee:BAABLgAECn8XAAIBAAgJXx1dMQBdAgABAAgJXx1dMQBdAgAAAA==.',
Ju='Jurkee:BAABLgAECn8YAAIBAAYJdQ+pqQAuAQABAAYJdQ+pqQAuAQAAAA==.',
Ka='Kahekili:BAAALgAECgEJAQAAAA==.Kain:BAAALgAECgkJBgAAAA==.Kalagren:BAAALgAECgQJDwAAAA==.Kathring:BAAALgADCgQJBAAAAA==.Katio:BAABLgAECn8ZAAMEAAgJcxygFQBjAgAEAAcJbBugFQBjAgAdAAIJGRILFwCFAAAAAA==.Kavaria:BAAALgAECgIJAgAAAA==.Kaydra:BAAALgADCgQJBAAAAA==.Kayhless:BAAALgAECgUJBQAAAA==.',
Ke='Keerah:BAAALgAECggJEAAAAA==.Kelirra:BAAALgADCgEJAgAAAA==.Kendoraa:BAAALgAECgEJAQAAAA==.Kessala:BAAALgAECgQJBgAAAA==.Kessandra:BAACLgAFFH8PAAISAAUJXBtCBQBiAQASAAUJXBtCBQBiAQAuAAQKfyEAAhIACQlnIlAEAHYDABIACQlnIlAEAHYDAAAA.Kexkan:BAAALgAECgIJAgAAAA==.Kezzia:BAAALgADCgMJAwAAAA==.',
Kh='Kharilan:BAAALgAECgYJDAAAAA==.Khitai:BAAALgADCgcJDgAAAA==.Khurri:BAABLgAECn8UAAIGAAgJEB45BgCaAgAGAAgJEB45BgCaAgAAAA==.',
Ki='Kiarah:BAAALgAECgMJBAAAAA==.Kirwyn:BAAALgADCgcJBwAAAA==.Kisor:BAAALgAECgMJAwAAAA==.Kitchenstink:BAABLgAECn8XAAIeAAgJlB4XBAC0AgAeAAgJlB4XBAC0AgAAAA==.',
Kl='Klys:BAABLgAECn8ZAAIOAAYJBxt6GgAuAQAOAAYJBxt6GgAuAQAAAA==.',
Ko='Kordh:BAABLgAECn8gAAQDAAcJ+g4ZDAA6AQAXAAcJew5AEQCjAQADAAcJ6Q0ZDAA6AQAKAAYJCwtlVAA0AQAAAA==.Kordiza:BAAALgAECgQJBgABLgAECgcJIAADAPoOAA==.',
Kr='Kritanta:BAABLgAECn8YAAITAAYJQgxqIQA3AQATAAYJQgxqIQA3AQAAAA==.Krrsantan:BAAALgADCgYJDQAAAA==.Krystallus:BAAALgAECgYJDgAAAA==.',
Ku='Kurnea:BAAALgAECgYJCgAAAA==.',
Ky='Kyandur:BAAALgADCgQJBAAAAA==.',
['Kó']='Kórrá:BAAALgADCgEJAQAAAA==.',
La='Laidy:BAAALgADCgYJBgAAAA==.Lakartó:BAACLgAFFH8GAAILAAMJKxGnEQDzAAALAAMJKxGnEQDzAAAuAAQKfxoAAw8ACAkaFWQXAH8BAAsABwlPEGQmAIkBAA8ABglRE2QXAH8BAAAA.Lathril:BAAALgADCgYJBgAAAA==.',
Ld='Ldritch:BAACLgAFFH8IAAMfAAQJ+CEMAACwAQAfAAQJ+CEMAACwAQAdAAIJ+RWiAwC9AAAuAAQKfyIABB8ACAm8Jd8AABEDAB8ACAkrJd8AABEDAAQABwmqI2ALAN8CAB0ABwlWJUkCANgCAAEuAAUUBAkJABMASyIA.',
Le='Leanfro:BAAALgADCgEJAQAAAA==.Leifson:BAAALgAECgYJEAAAAA==.Leonedis:BAAALgAECgYJDgAAAA==.Leothor:BAAALgAECgQJBAAAAA==.Lernen:BAAALgAECgYJEQAAAA==.Lesein:BAAALgAECgQJBgAAAA==.Lethea:BAAALgAECgQJBgAAAA==.',
Li='Liain:BAAALgADCgQJBAABLgADCgYJCgACAAAAAA==.Lianara:BAAALgADCggJFQABLgAECgYJEgACAAAAAA==.Litenkuk:BAACLgAFFH8GAAIgAAMJzw5iFgDnAAAgAAMJzw5iFgDnAAAuAAQKfx8AAiAACAnYH/EQALECACAACAnYH/EQALECAAAA.Lithiel:BAAALgADCgYJCgAAAA==.Liuna:BAAALgADCgEJAQABLgAECgcJHgADAHckAA==.',
Lo='Lonelycougar:BAAALgADCgcJDwAAAA==.Lore:BAAALgAECggJJQAAAQ==.Lothstein:BAAALgADCggJDgAAAA==.Lovely:BAAALgAECgcJDQAAAA==.',
Lu='Luminate:BAABLgAECn8ZAAIKAAYJdyJQCADDAQAKAAYJdyJQCADDAQAAAA==.Lunalah:BAAALgADCgcJBwAAAA==.Lunarray:BAAALgAECgEJAwAAAA==.Luxurious:BAAALgAECgYJDgAAAA==.',
Ly='Lyndea:BAAALgADCgYJBgAAAA==.',
['Lí']='Líllsnorre:BAAALgAECgMJBAAAAA==.',
Ma='Maaca:BAAALgADCgQJBAAAAA==.Magnomonk:BAAALgAECgYJDQAAAA==.Majuhstee:BAAALgADCgcJCAABLgAFFAEJAQACAAAAAA==.Malachor:BAAALgAECgMJBAAAAA==.Maligned:BAABLgAECn8ZAAITAAYJHR/eBAB4AQATAAYJHR/eBAB4AQAAAA==.Marsilea:BAAALgADCgcJCgAAAA==.Martichoux:BAABLgAECn8UAAIHAAgJghy1PwB6AgAHAAgJghy1PwB6AgAAAA==.Marvyy:BAAALgADCggJCAAAAA==.Mathas:BAABLgAECn8fAAIFAAkJGR1HBAAsAgAFAAkJGR1HBAAsAgAAAA==.Mathilda:BAAALgADCgEJAQAAAA==.Mazes:BAAALgAECgQJDwAAAA==.',
Mc='Mccholock:BAAALgAECgMJBAAAAA==.Mcmach:BAAALgAECgYJEwAAAA==.',
Me='Mediocrepaly:BAAALgAECgcJCAAAAA==.Mehaoloka:BAAALgADCgYJBgAAAA==.Mekanthis:BAACLgAFFH8JAAITAAQJSyIgAwCRAQATAAQJSiIgAwCRAQAuAAQKfyEAAhMACAmgJTgCAFEDABMACAmgJTgCAFEDAAAA.Menoah:BAAALgAECgUJBQAAAA==.Merdoc:BAAALgAECgYJDAAAAA==.Meredith:BAAALgAECgUJBQAAAA==.Mesilana:BAAALgADCgkJCwAAAA==.Metalhoof:BAAALgAECgQJBwAAAA==.',
Mi='Michelangelo:BAAALgAECgEJAQAAAA==.Mikak:BAAALgAECgIJAQAAAA==.Milanova:BAAALgADCgYJCQABLgAECgYJCgACAAAAAA==.Mirenna:BAAALgAECgUJBQAAAA==.Mirra:BAAALgAECgEJAQAAAA==.Misseymiss:BAAALgAECgMJBAAAAA==.',
Mo='Mogwhy:BAABLgAECn8XAAIdAAYJxhIPAwBTAQAdAAYJxhIPAwBTAQAAAA==.Monichan:BAAALgAECgMJAwAAAA==.Monkeypocket:BAAALgADCgQJBAAAAA==.Moonstrikex:BAAALgADCgUJBQAAAA==.Mooseknuckle:BAAALgAECgcJDQAAAA==.Moralekillas:BAAALgAECggJCAAAAA==.Morganna:BAAALgAECgEJAQAAAA==.Morior:BAAALgAECgQJBAAAAA==.Motorcade:BAAALgAECgYJDgAAAA==.',
Mu='Muchoblades:BAAALgAECgUJBQAAAA==.Murazor:BAAALgADCgUJBAAAAA==.Murples:BAAALgAECgYJCwAAAA==.',
Ne='Neather:BAAALgAECgYJCwAAAA==.Neels:BAAALgADCgMJAwAAAA==.Neodke:BAAALgAECgEJAQAAAA==.Neodken:BAAALgADCgYJCgAAAA==.Neron:BAAALgADCgUJCAAAAA==.Nestlee:BAAALgADCgcJBwAAAA==.Nevvermore:BAAALgADCgcJEgAAAA==.',
Ni='Niare:BAAALgAECgIJAgAAAA==.Ninfami:BAAALgADCggJCAAAAA==.Ninfamy:BAAALgADCgQJBQAAAA==.Ninfinite:BAABLgAECn8cAAIOAAYJeR2QEgBsAQAOAAYJeR2QEgBsAQAAAA==.',
No='Nockturne:BAAALgADCgMJAwAAAA==.Norasmina:BAAALgAECgEJAQAAAA==.Norr:BAAALgAECgcJEgAAAA==.Northpaul:BAAALgADCgQJBAAAAA==.Notdeadyet:BAAALgAECgMJBAAAAA==.Notneels:BAAALgAECgQJBQAAAA==.',
Ny='Nyceria:BAAALgAECgUJCQAAAA==.Nyseria:BAAALgADCgEJAQAAAA==.',
Oa='Oakarm:BAAALgAECgYJAgAAAA==.',
Ob='Obpwnkenobi:BAAALgAECgQJCQAAAA==.',
Od='Odyssius:BAAALgAECgUJCQAAAA==.',
Og='Ogden:BAAALgADCgIJAgABLgAECgcJGAAKANQFAA==.',
Ol='Oldandblind:BAAALgAECgEJAQAAAA==.',
On='Ontherun:BAAALgADCgQJBQAAAA==.',
Op='Oprawinfury:BAAALgAECgYJEgAAAA==.',
Or='Oralia:BAAALgAECgEJAQAAAA==.Ordun:BAAALgAECgMJAwAAAA==.Orphani:BAAALgADCgIJAgAAAA==.',
Os='Oscarguydude:BAABLgAECn8VAAMaAAYJshxXYABHAQAaAAQJwh1XYABHAQAgAAUJMBeiSgAnAQAAAA==.',
Ou='Ourus:BAABLgAECn8XAAMUAAgJ9BZzMwDdAQAUAAgJIw9zMwDdAQAhAAQJsSKVBgA0AQAAAA==.',
Ow='Owlpha:BAAALgAECgUJBQAAAA==.',
Ox='Oxlob:BAABLgAECn8VAAIBAAgJThF1EgCPAQABAAgJThF1EgCPAQAAAA==.',
Pa='Pallaminnow:BAAALgAECgIJAgAAAA==.Panax:BAAALgADCgcJBwAAAA==.Pawtyr:BAAALgAECgEJAQABLgAECgYJEgACAAAAAQ==.',
Pe='Peachieriest:BAAALgAECgMJAQAAAA==.Pele:BAAALgAECgQJBwAAAA==.Perpetrator:BAAALgAECgYJDAAAAA==.',
Ph='Pheonix:BAAALgADCgYJBgAAAA==.Phyre:BAAALgADCggJDQAAAA==.',
Pi='Pikahboo:BAAALgADCgYJBgAAAA==.',
Po='Poepwn:BAABLgAECn8UAAIiAAYJoxC/MQAyAQAiAAYJoxC/MQAyAQAAAA==.',
Pr='Priestbot:BAAALgADCgcJCwAAAA==.Promo:BAAALgADCgIJAgAAAA==.Prydae:BAAALgADCgQJBwAAAA==.',
Py='Pynelope:BAAALgADCgMJAwAAAA==.',
['Pû']='Pûrplehaze:BAAALgAECgMJAwAAAA==.',
Qu='Quelude:BAAALgAECgcJBgAAAA==.Quill:BAABLgAECn8UAAMJAAgJwxfrKQAKAgAJAAgJwxfrKQAKAgAZAAMJwRMWIgCNAAAAAA==.',
Ra='Raeris:BAEALgAECgcJAQAAAA==.Raicleach:BAAALgAECgkJCAAAAA==.Rainbow:BAAALgADCgcJDAAAAA==.Raktan:BAAALgAECgIJAgAAAA==.Rannick:BAAALgAECgUJBQAAAA==.Ranua:BAABLgAECn8lAAMKAAgJ8xviHQAtAgAKAAgJ8xviHQAtAgADAAYJiwwSEAAKAQAAAA==.Ratio:BAAALgAECgUJDgAAAA==.Ravenhunt:BAAALgAECgQJBAAAAA==.Ravenreaper:BAAALgADCgMJBAAAAA==.Rawmanu:BAAALgADCgcJBwAAAA==.',
Re='Reania:BAAALgADCgQJBAAAAA==.Rectified:BAAALgAECgIJAgAAAA==.Redbreastman:BAAALgAECgQJBwAAAA==.Rekka:BAAALgAECgQJBAAAAA==.Reoshe:BAAALgAECgEJAQAAAA==.',
Ri='Ripdvanwinkl:BAAALgAECgUJCAAAAA==.',
Ro='Ronyn:BAAALgAECgQJBwAAAA==.',
Ru='Rudolf:BAAALgAECgQJBQAAAA==.',
Rw='Rwarar:BAAALgADCgQJBAAAAA==.Rwqr:BAAALgADCgYJBwAAAA==.',
['Rä']='Räiden:BAAALgAECgEJAQAAAA==.',
['Rö']='Rötthgard:BAAALgADCgcJBwAAAA==.',
Sa='Salacakei:BAABLgAECn8fAAMEAAgJTxLHAwDYAQAEAAgJLBLHAwDYAQAdAAQJBwv5EwC/AAAAAA==.Salin:BAAALgAECgQJBAAAAA==.Salithril:BAAALgADCgMJBQAAAA==.Sanzo:BAAALgADCgEJAQABLgAECgYJCgACAAAAAA==.Sarthiy:BAAALgAECgcJDQABLgAFFAUJDwAjAPojAA==.Sarthy:BAACLgAFFH8PAAIjAAUJ+iOOAACVAQAjAAUJ+iOOAACVAQAuAAQKfyYAAiMACQmjI2YAAJcDACMACQmjI2YAAJcDAAAA.Sassaphras:BAABLgAECn8VAAINAAcJNx/fEQBSAgANAAcJNx/fEQBSAgAAAA==.Satheron:BAAALgAECgMJAgAAAA==.Satyric:BAAALgADCgcJBwAAAA==.Saxifon:BAAALgADCgQJBAAAAA==.',
Sc='Scarletpaw:BAAALgAECgUJCAAAAA==.Scoobie:BAAALgADCgUJAQAAAA==.Scoobydo:BAAALgADCgQJBwABLgAECgYJBwACAAAAAA==.Screwwithme:BAAALgADCgYJBgAAAA==.Scrubs:BAACLgAFFH8HAAIaAAMJpQhGDQD1AAAaAAMJpQhGDQD1AAAuAAQKfx4AAhoACAmfG1ofAEkCABoACAmfG1ofAEkCAAAA.',
Se='Septhyss:BAAALgAECgQJAQAAAA==.Seriadrina:BAAALgADCgIJAgAAAA==.',
Sh='Shaadow:BAAALgAECgEJAQAAAA==.Shallabal:BAAALgAECgcJAgAAAA==.Shamyaltak:BAAALgAECgkJCgABLgAECgcJAQACAAAAAA==.Shandralore:BAAALgAECgUJBQAAAA==.Shauranna:BAAALgADCgcJCQAAAA==.Shiel:BAAALgAECgMJBAAAAA==.Shockdoctor:BAABLgAECn8cAAIKAAcJHiTKAQCVAgAKAAcJHiTKAQCVAgAAAA==.Shogunasasin:BAABLgAECn8bAAMiAAgJBQ2DKQBrAQAiAAgJBQ2DKQBrAQAkAAMJuxqNTQDbAAAAAA==.Shortrange:BAAALgAECgQJBQAAAA==.Shuzui:BAAALgADCgQJBAAAAA==.',
Si='Sicarion:BAAALgAECgQJBAAAAA==.Silentwalkr:BAAALgAECgIJAgAAAA==.',
Sl='Sleples:BAAALgAECgYJBwAAAA==.Slufgor:BAAALgAECgQJBwAAAA==.',
Sm='Smolder:BAAALgADCgkJFAAAAA==.',
Sn='Snoo:BAAALgAECgQJBgAAAA==.Snorrehunter:BAAALgAECgQJBgAAAA==.',
So='Solarlite:BAAALgADCgkJHgAAAA==.Solek:BAAALgADCgIJAgAAAA==.Solorion:BAAALgAECgYJCQAAAA==.Sorovar:BAABLgAECn8UAAIlAAgJPSH9BwC/AgAlAAgJPSH9BwC/AgAAAA==.',
Sp='Spony:BAAALgAECgMJAwAAAA==.',
St='Starbrow:BAAALgAECgQJBgABLgAECgQJDwACAAAAAA==.Stein:BAAALgADCgYJBgAAAA==.Steinn:BAAALgADCgEJAQAAAA==.Stevewinwood:BAAALgAECgYJBwAAAA==.Stormlight:BAAALgAECgUJBgAAAA==.',
Su='Sushistryke:BAAALgAECgQJBAAAAA==.',
Sy='Syland:BAAALgAECgMJBAAAAA==.Sylissa:BAAALgADCgQJBAAAAA==.Sylvanäs:BAAALgAECgQJBwAAAA==.Sylvenna:BAAALgAECgUJBwAAAA==.Sypress:BAAALgADCgcJDQAAAA==.Syrelastus:BAAALgAECgEJAQAAAA==.Sysna:BAAALgAECgYJEgAAAA==.',
Ta='Tachyon:BAAALgAECgEJAQAAAA==.Talley:BAABLgAECn8YAAIKAAYJIRqkDAByAQAKAAYJIRqkDAByAQAAAA==.Targis:BAAALgAECgYJEwAAAA==.Tauran:BAAALgAECgQJBQAAAA==.Tazanaz:BAAALgAECgIJAgABLgAECggJJQAKAPMbAA==.',
Te='Templeton:BAAALgAECgQJBAABLgAECgcJGAAKANQFAA==.Tendai:BAAALgADCgkJGAAAAA==.Tenloth:BAAALgAECgIJAwAAAA==.Teozr:BAAALgADCgMJAwAAAA==.Teufelshund:BAAALgADCgcJBwAAAA==.',
Th='Thaleas:BAAALgAECgUJDwAAAA==.Thorlas:BAAALgAECgYJDgAAAA==.Thorsham:BAAALgAECgYJBgAAAA==.',
Ti='Timmúk:BAAALgAECgMJAwAAAA==.',
To='Tomma:BAABLgAECn8VAAITAAgJpCGABgDPAgATAAgJpCGABgDPAgAAAA==.Totem:BAAALgADCggJCAAAAA==.Totembi:BAACLgAFFH8FAAIKAAQJJAjNCwAcAQAKAAQJJAjNCwAcAQAuAAQKfykAAgoACQlxFqsGAOsBAAoACQlxFqsGAOsBAAAA.',
Tr='Trailerpark:BAAALgAECgMJAwAAAA==.Tratre:BAABLgAECn8XAAQLAAgJJg8vIgCtAQALAAgJDA4vIgCtAQAPAAEJYxIKPQA6AAAMAAEJcQMeTQAmAAAAAA==.Treynof:BAAALgAECgYJDAAAAA==.Truewill:BAAALgADCgEJAQAAAA==.Trupeti:BAAALgAECgUJCAAAAA==.',
Tu='Tulsiice:BAAALgAECgYJCQAAAA==.',
Ty='Tytaniormu:BAAALgAECggJEQAAAA==.',
Ug='Ugless:BAAALgADCgYJBgABLgADCgcJCAACAAAAAA==.Uglify:BAAALgADCgcJCAAAAA==.',
Ul='Ulanmonk:BAAALgADCgMJAwAAAA==.Ulridan:BAAALgAECgEJAQABLgAECgcJHgADAHckAA==.',
Un='Undeathtwoy:BAABLgAECn8YAAMYAAcJRxZoaAC9AQAYAAcJVRVoaAC9AQATAAUJIAx6MAC8AAAAAA==.Undos:BAAALgADCgUJBQAAAA==.Unholyveri:BAAALgADCgcJBwAAAA==.',
Va='Vaelraen:BAAALgAECgUJCAAAAA==.Valcher:BAAALgAECgMJAwAAAA==.Valendera:BAABLgAECn8UAAISAAgJ2gsBYACpAQASAAgJ2gsBYACpAQAAAA==.Valhri:BAAALgAECgIJAwAAAA==.Valifadin:BAAALgAECgUJBQAAAA==.Valith:BAAALgAECgQJCQAAAA==.Valmoria:BAAALgADCgkJEQAAAA==.Valndrevy:BAAALgADCgUJDAAAAA==.Vansan:BAAALgAECgMJBQABLgAECggJJQAKAPMbAA==.',
Ve='Vellas:BAAALgAECgEJAQAAAA==.Venngennce:BAABLgAECn8ZAAMmAAkJ/xwsAAC3AgAmAAkJ/xwsAAC3AgAYAAMJ4Arc+wCDAAAAAA==.',
Vi='Vintage:BAACLgAFFH8JAAIfAAMJAAnvAADoAAAfAAMJAAnvAADoAAAuAAQKfyEAAh8ACQnMGfYAAAMDAB8ACQnMGfYAAAMDAAAA.Visage:BAAALgADCgYJBgAAAA==.',
Vo='Volkareth:BAABLgAECn8UAAIPAAgJIRTLDQD9AQAPAAgJIRTLDQD9AQAAAA==.Vorkath:BAABLgAECn8ZAAQPAAYJgSS3AAAWAgAPAAYJgSS3AAAWAgAMAAYJdx+FGQDCAQALAAEJmx+MWABcAAAAAA==.Vormette:BAAALgADCgkJEwAAAA==.',
Vt='Vtae:BAAALgAECgYJCgAAAA==.',
Wa='Waka:BAAALgADCgkJCQAAAA==.Waryndor:BAAALgADCgYJBgAAAA==.',
We='Werehamster:BAAALgAECgYJDwAAAA==.',
Wi='Wilderbeast:BAABLgAECn8XAAIJAAcJcwMKeQDtAAAJAAcJcwMKeQDtAAAAAA==.Wildlife:BAAALgADCgEJAQAAAA==.',
Wo='Woodrow:BAAALgADCgcJBwABLgAECgcJGAAKANQFAA==.Woxkal:BAAALgAECgYJEQAAAA==.',
Wu='Wubblebubble:BAAALgAECgYJCgAAAA==.',
Xa='Xaelin:BAAALgAECgMJBAAAAA==.',
Xy='Xynelle:BAAALgADCgcJCwAAAA==.',
Yi='Yisús:BAAALgAECgIJAwAAAA==.',
Yl='Ylvis:BAABLgAECn8UAAIaAAYJYRgwGgArAQAaAAYJYRgwGgArAQAAAA==.',
Yo='Yoshymi:BAAALgAECgYJEgAAAQ==.',
Yu='Yuná:BAAALgADCgMJAwAAAA==.',
Yv='Yvetal:BAAALgAECgEJAQAAAA==.',
Za='Zacco:BAAALgAECgQJCQAAAA==.Zaleth:BAACLgAFFH8IAAIMAAUJFA53BAAeAQAMAAUJFA53BAAeAQAuAAQKfyAAAgwABwkGIaMIALACAAwABwkGIaMIALACAAAA.Zamazenta:BAAALgADCgcJCwAAAA==.Zaranne:BAAALgAECggJCAAAAA==.Zarion:BAAALgAECgYJBwABLgAFFAUJCAAMABQOAA==.Zarra:BAAALgAECgMJBAAAAA==.Zathuera:BAAALgADCgQJBAAAAA==.',
Ze='Zeroz:BAAALgAECgUJCQAAAA==.',
Zh='Zhath:BAAALgAECgIJAwAAAA==.',
Zi='Zilik:BAAALgAECgQJBAABLgAFFAUJCAAMABQOAA==.',
Zo='Zocorro:BAAALgAECgQJBwAAAA==.Zodiack:BAAALgAECgcJCQAAAA==.Zombe:BAAALgAECggJEgAAAA==.',
Zu='Zuelmst:BAAALgAECgIJAgAAAA==.',
['Ân']='Ângel:BAAALgAECgYJDQAAAA==.',
['Ðe']='Ðecision:BAABLgAECn8aAAIBAAgJZSCmEQAEAwABAAgJZSCmEQAEAwAAAA==.',
['Øn']='Ønslaught:BAAALgADCgUJBQAAAA==.',
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
