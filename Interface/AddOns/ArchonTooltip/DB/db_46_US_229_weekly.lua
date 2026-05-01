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

local lookup = {'Paladin-Retribution','DeathKnight-Blood','DemonHunter-Devourer','Shaman-Elemental','Rogue-Outlaw','Paladin-Protection','Paladin-Holy','Unknown-Unknown','Druid-Feral','Mage-Frost','Monk-Windwalker','Monk-Mistweaver','Druid-Balance','Druid-Guardian','Druid-Restoration','DeathKnight-Unholy','Shaman-Restoration','Evoker-Preservation','Evoker-Augmentation','Priest-Holy','Evoker-Devastation','Hunter-Survival','Warlock-Destruction','Warlock-Demonology','Warrior-Fury','DemonHunter-Havoc','DemonHunter-Vengeance','Shaman-Enhancement','Hunter-BeastMastery','Mage-Arcane','Monk-Brewmaster','Rogue-Subtlety','Rogue-Assassination','Warrior-Arms','Mage-Fire','Hunter-Marksmanship','Warrior-Protection','Priest-Discipline','DeathKnight-Frost',}
local provider = {region='US',realm='Uldum',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abmikaze:BAAALgAECgMJAwAAAA==.',
Ad='Adorean:BAABLgAECn8cAAIBAAYJ0xztJgCnAQABAAYJ0xztJgCnAQAAAA==.',
Ae='Aeginau:BAAALgAECgMJAwAAAA==.Aenymbria:BAABLgAECn8UAAIBAAcJJxpcWQAFAQABAAcJJxpcWQAFAQAAAA==.Aerbear:BAAALgADCgUJCAAAAA==.',
Ag='Age:BAAALgAECgUJEgAAAA==.',
Ai='Aimnskin:BAAALgADCggJEgAAAA==.',
Ak='Akuaa:BAAALgADCgMJAwAAAA==.',
Al='Alburm:BAAALgAECgYJCQAAAA==.Alexstraxsa:BAAALgADCgkJJwAAAA==.Aliine:BAABLgAECn8aAAICAAcJ0xHMEQAAAQACAAcJ0xHMEQAAAQAAAA==.Ally:BAAALgAECgIJAgABLgAECgYJFAADADUaAA==.Althaea:BAAALgAECgYJDwAAAA==.',
Am='Ameiisaa:BAAALgADCgcJCgAAAA==.Amytiel:BAABLgAECn8oAAIEAAgJGhw1FwBeAgAEAAgJGhw1FwBeAgAAAA==.',
An='Anahana:BAAALgAECgYJDQAAAA==.Anali:BAAALgADCggJEAAAAA==.Andi:BAAALgAECgcJDwAAAA==.Andorelia:BAABLgAECn8YAAIBAAcJow0LQwBBAQABAAcJow0LQwBBAQAAAA==.Andronocus:BAAALgADCggJFQAAAA==.Anko:BAAALgADCgQJAwAAAA==.Anxie:BAAALgAECgcJBAAAAA==.Anìtamaxwynn:BAAALgAECgYJCwABLgAFFAYJDAAFAHUXAA==.',
Ap='Apally:BAAALgAECgQJCQAAAA==.Apexmaster:BAAALgAECgYJCwAAAA==.Appleborne:BAAALgADCgcJBwAAAA==.Appleseed:BAAALgADCgMJBQAAAA==.Apprentice:BAABLgAECn8VAAIGAAcJCQKzGQCVAAAGAAcJCQKzGQCVAAAAAA==.',
Ar='Aragorn:BAAALgAECgYJCQAAAA==.Aramos:BAABLgAECn8gAAIHAAgJyBVFEgDJAQAHAAgJyBVFEgDJAQAAAA==.Aramôs:BAAALgAECgUJEgAAAA==.Ares:BAAALgADCgYJDwAAAA==.Arinathia:BAAALgAECgcJAQABLgAECgkJDAAIAAAAAA==.Arta:BAAALgAECgUJEgAAAA==.Artachoke:BAAALgADCgIJAgAAAA==.Aruncusdio:BAABLgAECn8cAAIJAAgJaQYACwAxAQAJAAgJaQYACwAxAQAAAA==.',
As='Ashhealz:BAAALgAECgYJDwAAAA==.Ashlei:BAAALgADCgEJAQAAAA==.Asteroid:BAAALgAECgQJBQAAAA==.',
At='Atelwen:BAAALgAECgYJDAAAAA==.',
Av='Aveme:BAABLgAECn8wAAIKAAkJCSNSBAD6AgAKAAkJCSNSBAD6AgAAAA==.',
Aw='Awartedpeen:BAAALgAECgUJEQAAAA==.',
Az='Azael:BAAALgAECgEJAQABLgAECgIJBAAIAAAAAA==.Azuleon:BAABLgAECn8WAAMLAAYJ6B1SHQDwAQALAAYJ6B1SHQDwAQAMAAYJMhADGwArAQAAAA==.',
Ba='Bagelmancer:BAAALgADCgUJBQAAAA==.Bageluwu:BAAALgADCgYJBgAAAA==.Bamber:BAAALgADCggJDQAAAA==.Battar:BAAALgAECgEJAQAAAA==.Bayraktar:BAAALgADCgkJDgAAAA==.',
Bb='Bbads:BAAALgADCgIJAgAAAA==.',
Be='Beaker:BAABLgAECn8gAAMNAAcJ7BwpFQBZAQANAAYJAh4pFQBZAQAOAAEJfxfCGwBDAAAAAA==.Beastmode:BAABLgAECn8jAAIPAAgJPRpODwAcAgAPAAgJPRpODwAcAgAAAA==.Bedlem:BAABLgAECn8UAAIQAAYJ0ghtVwD9AAAQAAYJ0ghtVwD9AAAAAA==.Beerchaplain:BAAALgADCgcJFgABLgAECgcJBwAIAAAAAA==.Bernard:BAABLgAECn8eAAMRAAcJ2gaDXwAOAQARAAcJ2gaDXwAOAQAEAAQJowZ9OgCBAAAAAA==.',
Bi='Bidoof:BAABLgAECn8bAAMSAAcJkhRpBwC+AQASAAcJkhRpBwC+AQATAAYJQw+vJwDRAAAAAA==.Bigolman:BAAALgAECgEJAQAAAA==.Biochemguy:BAAALgAECgUJAQAAAA==.Birgitte:BAAALgAECgcJDgAAAA==.',
Bl='Blackelvis:BAAALgADCgcJBwABLgAECgkJHQAUAHAUAA==.Blackgrace:BAAALgAECgEJAQABLgAECgYJDAAIAAAAAA==.Blacklisted:BAABLgAECn8dAAIUAAkJcBTaCAAbAgAUAAkJcBTaCAAbAgAAAA==.Blackup:BAAALgAECgMJAwAAAA==.Blackvortex:BAAALgADCggJCgAAAA==.Bloodybloodz:BAAALgAECgQJBQABLgAECgcJDwAIAAAAAA==.Bloodyburst:BAAALgADCgYJBgABLgAECgcJDwAIAAAAAA==.Bloodyfistz:BAAALgAECgcJDwAAAA==.Blueshift:BAABLgAECn8VAAIDAAgJfhg6QwDnAQADAAgJfhg6QwDnAQAAAA==.Bluethreetwo:BAAALgAECgMJCgAAAA==.Blurry:BAAALgADCgQJBQAAAA==.',
Bo='Bookofzeref:BAAALgAECgYJEgAAAA==.',
Br='Brahruhanu:BAEALgADCgUJCAAAAA==.Braile:BAAALgAECgQJCgAAAA==.Brayend:BAAALgAECgYJEgAAAA==.Brewbelly:BAAALgADCgIJAgAAAA==.Brimscythe:BAABLgAECn8lAAIVAAgJLR5NAQBRAgAVAAgJLR5NAQBRAgAAAA==.',
Bu='Bubbleup:BAAALgADCgUJBQAAAA==.',
Ca='Caliandis:BAAALgAECgYJCwAAAA==.Calvey:BAAALgAECgQJCAAAAA==.Cambrai:BAAALgAECgYJDgAAAA==.Cannabelle:BAABLgAECn8nAAIWAAgJJyX+AABmAwAWAAgJJyX+AABmAwAAAA==.Carclias:BAABLgAECn8YAAMXAAgJZRouBwBXAgAXAAgJZRouBwBXAgAYAAIJPgW4BQFRAAAAAA==.Carmenere:BAAALgADCgUJCQAAAA==.Carthrix:BAAALgAECgYJDAAAAA==.Cattlerage:BAAALgAECgEJAQAAAA==.',
Ce='Cedo:BAAALgADCgUJBQAAAA==.Celéste:BAAALgADCgcJBwAAAA==.',
Ch='Chaoscookies:BAABLgAECn8lAAMXAAkJERYSHgBfAQAXAAUJXBcSHgBfAQAYAAUJNxSqRQAfAQAAAA==.Chaotik:BAAALgADCgcJDAAAAA==.Chaplain:BAAALgAECgcJBwAAAA==.Chartkov:BAAALgAECgQJCwAAAA==.Cheechee:BAAALgAECgYJCwAAAA==.Cheekichik:BAAALgADCgQJBAAAAA==.Cheeseballer:BAAALgAFFAQJBAAAAA==.Cheesebur:BAAALgADCgcJBwAAAA==.Chighas:BAAALgADCgQJBwAAAA==.Choofi:BAABLgAECn8bAAIPAAcJHhQSHACfAQAPAAcJHhQSHACfAQAAAA==.Chubbytoyboy:BAAALgADCgUJBQABLgAECgYJFwAKAMoPAA==.',
Ci='Ciená:BAAALgAECgQJBAAAAA==.Cin:BAAALgAECgYJCgAAAA==.Cinderpetal:BAAALgAECgEJAQAAAA==.',
Co='Comlock:BAAALgAECgQJCQAAAA==.Complacent:BAABLgAECn8YAAIOAAcJTQEcGQBVAAAOAAcJTQEcGQBVAAAAAA==.Coomtheory:BAAALgAECgYJCAAAAA==.Coriander:BAAALgAECgIJAwAAAA==.Corik:BAAALgADCgMJAwAAAA==.',
Cr='Cragn:BAAALgAECgIJBgAAAA==.Crownman:BAAALgADCgUJCAAAAA==.Crunchyblue:BAAALgADCgUJBgAAAA==.',
Cu='Cuddilz:BAAALgAECgYJEAAAAA==.Cursedchild:BAAALgAECgQJBAAAAA==.',
Cy='Cyclonic:BAAALgADCgYJBwAAAA==.Cyonicus:BAABLgAECn8cAAIYAAYJzRyyIQCsAQAYAAYJzRyyIQCsAQAAAA==.Cyradis:BAAALgADCgEJAQAAAA==.Cyska:BAABLgAECn8nAAICAAkJwxffAwAOAgACAAkJwxffAwAOAgAAAA==.',
['Cé']='Cécé:BAABLgAECn8YAAIBAAcJjyJPLwCEAQABAAcJjyJPLwCEAQAAAA==.',
Da='Daciana:BAAALgAECgUJEgAAAA==.Dagaroonie:BAAALgAECgcJCAAAAA==.Dagevas:BAABLgAECn8cAAIYAAgJBRKAJgCVAQAYAAgJBRKAJgCVAQAAAA==.Darkeznite:BAAALgAECgYJDwAAAA==.Darksoldier:BAAALgAFFAEJAQAAAA==.Darthqueso:BAAALgADCgMJAwAAAA==.Dartoy:BAABLgAECn8lAAIZAAgJvAbQKAD+AAAZAAgJvAbQKAD+AAAAAA==.Davriell:BAAALgADCgcJDQAAAA==.Dax:BAAALgAECgYJDwAAAA==.Dazling:BAAALgAECgQJBAAAAA==.',
De='Deathkess:BAAALgAECgcJBwAAAA==.Deathlokk:BAAALgAECgYJDwAAAA==.Deeppurple:BAAALgAECgQJCwAAAA==.Deezmons:BAABLgAECn8hAAIaAAcJvhFcEQApAQAaAAcJvhFcEQApAQAAAA==.Deholybagel:BAAALgAECgQJBQAAAA==.Del:BAABLgAECn8gAAIbAAcJwCNUAQBvAgAbAAcJwCNUAQBvAgAAAA==.Demoncheese:BAAALgADCgYJCAAAAA==.Demondag:BAAALgADCgcJDAAAAA==.Demoniaca:BAAALgAECgIJAgAAAA==.Demonkirby:BAAALgADCgUJBQAAAA==.Demonlarrik:BAAALgADCgIJAgAAAA==.Derale:BAABLgAECn8aAAMTAAgJiw3+JQCNAQATAAgJiA3+JQCNAQAVAAcJXQQwIgAZAQAAAA==.',
Dh='Dhargal:BAACLgAFFH8FAAIEAAMJ6RglEAAAAQAEAAMJ6RglEAAAAQAuAAQKfyUAAgQACAnnI4EFAF0CAAQACAnnI4EFAF0CAAAA.',
Di='Dial:BAAALgADCgkJGQAAAA==.Dichotomy:BAAALgADCgQJBAAAAA==.Divinebi:BAAALgAECgUJBQAAAA==.Divus:BAAALgAECgYJEAAAAA==.',
Dk='Dkfaros:BAABLgAECn8VAAIQAAYJPCOFHADcAQAQAAYJPCOFHADcAQAAAA==.',
Do='Donko:BAAALgADCggJCAABLgAECgQJCAAIAAAAAA==.Dontcarebear:BAAALgAECgUJDgAAAA==.Doofnshmirtz:BAABLgAECn8fAAIcAAgJeBjQAwACAgAcAAgJeBjQAwACAgAAAA==.Dorow:BAAALgAECgcJBwAAAA==.Dotpocket:BAABLgAECn8cAAIYAAgJDRZeGwDQAQAYAAgJDRZeGwDQAQAAAA==.',
Dr='Drakenn:BAAALgAECgcJDgAAAA==.Draéne:BAAALgAECgUJCgAAAA==.Dreadly:BAAALgADCgUJCAAAAA==.Dreadp:BAAALgADCgIJAgAAAA==.Dreamfyre:BAAALgAECgEJAQAAAA==.Dremmy:BAAALgAECgYJEQAAAA==.Dripdasini:BAAALgADCgUJBQAAAA==.Droki:BAABLgAECn8aAAIcAAYJ0yDMBADaAQAcAAYJ0yDMBADaAQAAAA==.',
Du='Dunsel:BAAALgAECgEJAQABLgAECggJJQAVAC0eAA==.Dunwich:BAAALgADCgcJIAAAAA==.',
Dv='Dvali:BAAALgADCgcJCAAAAA==.',
Dy='Dyorra:BAAALgAECgUJCQAAAA==.',
Eb='Ebonshade:BAAALgAECgMJAwAAAA==.',
Ed='Edgardapoe:BAAALgADCgYJBgABLgAECgIJAgAIAAAAAA==.Edginglord:BAAALgAECgUJBgAAAA==.',
Eh='Ehmill:BAABLgAECn8YAAIQAAYJLRr1QAA7AQAQAAYJLRr1QAA7AQAAAA==.',
El='Elesrya:BAAALgADCgUJCwABLgAECgcJFAABACcaAA==.Elventhing:BAAALgAECgYJCQAAAA==.',
Em='Emmå:BAAALgADCgEJAQAAAA==.Emshady:BAAALgADCgcJBwAAAA==.',
Eo='Eomær:BAAALgAECgEJAgAAAA==.',
Ep='Epsilòn:BAEALgAECgcJAQABLgAECgcJAQAIAAAAAA==.',
Er='Ernest:BAAALgADCgUJBgAAAA==.Errani:BAAALgAECgQJCQAAAA==.',
Es='Eskers:BAAALgAECgYJEAAAAA==.Estralla:BAAALgADCgQJBAAAAA==.',
Eu='Eureki:BAABLgAECn8YAAIDAAcJyA0gMwAWAQADAAcJyA0gMwAWAQAAAA==.',
Ev='Evilkarma:BAABLgAECn8VAAIKAAYJQAJ5kwCoAAAKAAYJQAJ5kwCoAAAAAA==.Evocatis:BAACLgAFFH8KAAMBAAQJEho3DABZAQABAAQJEho3DABZAQAHAAEJPgsEJAA+AAAuAAQKfx8AAwEACQkYITYeALYCAAEACAl4IzYeALYCAAcAAwkOCwV2AKIAAAAA.Evoorc:BAAALgADCgEJAQAAAA==.',
Ex='Ex:BAABLgAECn8YAAIXAAYJuA3RCQAIAQAXAAYJuA3RCQAIAQAAAA==.',
Fa='Faasht:BAAALgADCgkJEAAAAA==.Fayde:BAAALgADCgUJBAAAAA==.',
Fe='Felzbirt:BAAALgADCgYJCwAAAA==.Fenehdis:BAAALgAECgYJCwAAAA==.Ferg:BAAALgADCgcJBwAAAA==.Ferula:BAAALgADCgEJAgABLgAECgUJDgAIAAAAAA==.',
Fi='Fiftycaliber:BAAALgAECgQJBAAAAA==.Firebirdxx:BAAALgADCgcJBwABLgAFFAQJBgAPAJoTAA==.Firebirdz:BAACLgAFFH8GAAIPAAQJmhM9HwCnAAAPAAQJmhM9HwCnAAAuAAQKfx8AAw8ACQnVIbQIAAMDAA8ACQnVIbQIAAMDAA0AAQksAv9OACEAAAAA.Firebirdzx:BAAALgADCgYJBwABLgAFFAQJBgAPAJoTAA==.Firebirdzz:BAAALgAECgQJBwAAAA==.Fizzystomps:BAAALgAECgEJAQAAAA==.',
Fl='Fleabàg:BAAALgAECggJBwAAAA==.',
Fo='Forque:BAAALgADCgQJAwAAAA==.Fortybelow:BAAALgAECgQJCAAAAA==.',
Fr='Frostypaw:BAAALgADCgYJCgAAAA==.',
Fu='Fuzzybut:BAAALgAECgUJCQAAAA==.',
Ga='Gandalph:BAAALgAECgMJAwAAAA==.Gark:BAAALgAECgQJBwAAAA==.Garkk:BAAALgADCgcJCAAAAA==.Gazzi:BAAALgAECggJEQAAAA==.',
Gi='Gióvanna:BAAALgADCgkJKQAAAA==.',
Gl='Glaivedigger:BAAALgADCgIJAwABLgAECgQJCgAIAAAAAA==.',
Go='Goobo:BAABLgAECn8kAAIQAAkJOBgYCgCAAgAQAAkJOBgYCgCAAgAAAA==.Goodheavens:BAAALgAECgQJBAAAAA==.Goonlock:BAAALgADCgYJCwAAAA==.Gorbb:BAAALgADCgQJBAAAAA==.Gotenk:BAAALgAECgQJBAAAAA==.Goudafel:BAAALgADCgcJDgAAAA==.Goyim:BAABLgAECn8iAAIKAAgJiA7LdwDiAQAKAAgJiA7LdwDiAQAAAA==.',
Gr='Gr:BAAALgAECgYJDwAAAA==.Graveconvert:BAAALgADCgMJAwAAAA==.Grewbacca:BAAALgADCgMJAwAAAA==.Grimkrieg:BAABLgAECn8jAAIOAAgJtxmzAwD+AQAOAAgJtxmzAwD+AQAAAA==.Grody:BAAALgADCgYJBgAAAA==.Grumpias:BAAALgAECgIJAgABLgAECgcJGgAJAGUbAA==.',
Gu='Guroo:BAABLgAECn8eAAIdAAcJSRM3JgCAAQAdAAcJSRM3JgCAAQAAAA==.',
['Gá']='Gárp:BAAALgAECgMJBAAAAA==.',
['Gø']='Gødoth:BAABLgAECn8fAAMEAAcJgyBjCAAaAgAEAAcJgyBjCAAaAgARAAUJDiLwOwCSAQAAAA==.',
Ha='Hagarn:BAABLgAECn8hAAIBAAkJgA7gHwDKAQABAAkJgA7gHwDKAQAAAA==.Halimah:BAAALgADCgMJAwAAAA==.Halloffame:BAAALgAECgIJAQAAAA==.Hamsham:BAAALgAECgEJAQAAAA==.Harleypaw:BAAALgADCgQJBAAAAA==.Harleypuddin:BAAALgAECgkJBwAAAA==.Harlydorable:BAAALgAECgkJBwAAAA==.Hazystar:BAAALgAECgcJCgAAAA==.',
He='Healmemaybe:BAAALgAECgYJDgAAAA==.Hemour:BAAALgAECgYJCwAAAA==.Hexmachine:BAAALgAECgkJBAAAAA==.',
Hi='Hirak:BAAALgADCgIJAgABLgAFFAYJGgAUAJUWAA==.',
Ho='Hogarth:BAAALgADCgEJAQAAAA==.Holdmyshock:BAAALgADCgEJAQAAAA==.Holmstein:BAAALgAECgMJAwAAAA==.Hotnsoursoup:BAAALgADCgcJCgAAAA==.',
Hu='Hunkules:BAAALgAECgYJCAAAAA==.',
['Hë']='Hëllsoldier:BAAALgADCgMJAwAAAA==.',
Ia='Iamahriman:BAABLgAECn8gAAIEAAgJzgo6GQBIAQAEAAgJzgo6GQBIAQAAAA==.Iamthanatos:BAAALgADCgYJDAAAAA==.',
Id='Idblastdat:BAABLgAECn8dAAIKAAcJqxhALwCmAQAKAAcJqxhALwCmAQAAAA==.',
Ig='Ignite:BAAALgAECgYJCAAAAA==.',
Il='Iliana:BAAALgAECgIJAQAAAA==.Illestria:BAABLgAECn8iAAIBAAcJvxcfOABkAQABAAcJvxcfOABkAQAAAA==.Illumiscotty:BAABLgAECn8hAAMKAAkJRSI7AgA8AwAKAAkJHCI7AgA8AwAeAAIJBh8ZEQCxAAAAAA==.Ilwey:BAAALgAECgcJCwAAAA==.',
Im='Immortamonk:BAABLgAECn8XAAIfAAYJPB9LJgDSAQAfAAYJPB9LJgDSAQAAAA==.Immórtál:BAAALgADCgUJBQABLgAECgYJFwAfADwfAA==.',
In='Insania:BAABLgAECn8UAAIRAAcJzhwEDQAcAgARAAcJzhwEDQAcAgAAAA==.Invisagal:BAAALgAECgQJBgAAAA==.',
Io='Ionni:BAAALgADCgUJCAAAAA==.Iosefka:BAAALgADCgQJBAAAAA==.',
Ir='Ironhands:BAAALgAECgEJAQAAAA==.',
Iz='Izara:BAAALgADCgkJGQAAAA==.',
Ja='Jarlmaxim:BAAALgAECgYJDAAAAA==.Jasindra:BAAALgAECgcJCgABLgAECggJJwARAPMbAA==.',
Ji='Jin:BAAALgADCgEJAQAAAA==.',
Jo='Jolinascrubs:BAABLgAECn8gAAIGAAcJxBPrDAAxAQAGAAcJxBPrDAAxAQABLgAFFAQJCwAdAOwJAA==.Jonjee:BAABLgAECn8XAAIBAAgJXx1RMQBdAgABAAgJXx1RMQBdAgAAAA==.',
Ju='Juicez:BAAALgADCgQJBAAAAA==.Jurkee:BAABLgAECn8eAAIBAAYJRSB4HQDZAQABAAYJRSB4HQDZAQAAAA==.',
Ka='Kahekili:BAAALgAECgEJAgAAAA==.Kain:BAAALgAECgkJCwAAAA==.Kalagren:BAABLgAECn8UAAIdAAUJuQb9WQC8AAAdAAUJuQb9WQC8AAAAAA==.Kaleielin:BAAALgAECgIJAgAAAA==.Kathring:BAAALgADCgQJBAAAAA==.Katio:BAABLgAECn8eAAMgAAgJJh+eFQBjAgAgAAcJkh6eFQBjAgAhAAIJGRILFwCFAAAAAA==.Kavaria:BAAALgAECgIJAgAAAA==.Kaydra:BAAALgADCgUJCAAAAA==.Kayhless:BAAALgAECgYJCwAAAA==.',
Ke='Keerah:BAABLgAECn8ZAAMDAAkJnQOIPQDwAAADAAkJWQOIPQDwAAAbAAUJkwGnEgBnAAAAAA==.Kelirra:BAAALgADCgEJAgAAAA==.Kendoraa:BAAALgAECgEJAQAAAA==.Kessala:BAAALgAECgQJBgAAAA==.Kessandra:BAACLgAFFH8UAAIYAAUJDBzoEABaAQAYAAUJDBzoEABaAQAuAAQKfyoAAhgACQkQJFIEAHYDABgACQkQJFIEAHYDAAAA.Kexkan:BAAALgAECgQJBgAAAA==.Kezzia:BAAALgADCgMJAwAAAA==.',
Kh='Kharilan:BAAALgAECgYJDAAAAA==.Khitai:BAAALgADCgcJDgAAAA==.Khurri:BAABLgAECn8UAAIJAAgJEB47BgCaAgAJAAgJEB47BgCaAgAAAA==.',
Ki='Kiarah:BAAALgAECgUJCQAAAA==.Kirwyn:BAAALgADCgcJBwAAAA==.Kisor:BAAALgAECgYJCAAAAA==.Kitchenstink:BAABLgAECn8XAAIiAAgJlB4WBAC0AgAiAAgJlB4WBAC0AgAAAA==.',
Kl='Klys:BAABLgAECn8aAAIDAAcJyhdLIQBrAQADAAcJyhdLIQBrAQAAAA==.',
Ko='Kordh:BAABLgAECn8nAAQEAAcJKg8AHAA1AQAcAAcJew5DEQCjAQAEAAcJGQ4AHAA1AQARAAYJrwtjVAA0AQAAAA==.Kordiza:BAAALgAECgUJCAABLgAECgcJJwAEACoPAA==.',
Kr='Kritanta:BAABLgAECn8gAAICAAgJagtmEQAEAQACAAgJagtmEQAEAQAAAA==.Krrsantan:BAAALgADCgYJDQAAAA==.Krystallus:BAABLgAECn8UAAINAAYJGhDeHwD+AAANAAYJGhDeHwD+AAAAAA==.',
Ku='Kurnea:BAAALgAECgYJDwAAAA==.',
Ky='Kyandur:BAAALgADCgQJBAAAAA==.',
['Kó']='Kórrá:BAAALgADCgEJAQAAAA==.',
La='Laidy:BAAALgADCgYJBgAAAA==.Lakartó:BAACLgAFFH8KAAITAAQJERPJDQBBAQATAAQJERPJDQBBAQAuAAQKfxwABBUACAkaFWgXAH8BABMABwlPEGQmAIkBABUABglRE2gXAH8BABIAAQkaFIgfAEAAAAAA.Larzuk:BAAALgADCgcJBwAAAA==.Lathril:BAAALgADCgYJBgAAAA==.',
Ld='Ldritch:BAACLgAFFH8JAAMFAAQJ/CFcAACcAQAFAAQJ/CFcAACcAQAhAAIJ+RWhAwC9AAAuAAQKfyQABAUACAm8Jd8AABEDAAUACAmEJd8AABEDACAABwmqI2ELAN8CACEABwlWJUgCANgCAAEuAAUUBQkOAAIASyIA.',
Le='Leanfro:BAAALgADCgEJAQAAAA==.Leifson:BAAALgAECgYJEAAAAA==.Leonedis:BAAALgAECgYJEgAAAA==.Leothor:BAAALgAECgQJBAAAAA==.Lernen:BAABLgAECn8UAAQKAAcJSQsCZQARAQAKAAcJSQsCZQARAQAjAAEJkQGtCQAiAAAeAAEJdQH3IgARAAAAAA==.Lesein:BAAALgAECgQJCQAAAA==.Lethea:BAAALgAECgQJCAAAAA==.',
Li='Liain:BAAALgADCgQJBAAAAA==.Lianara:BAAALgADCggJFQABLgAECgYJEgAIAAAAAA==.Litenkuk:BAACLgAFFH8GAAIkAAMJzw50FgDnAAAkAAMJzw50FgDnAAAuAAQKfyEAAyQACAnYH/MQALECACQACAnYH/MQALECABYAAgkJD5AiAIgAAAAA.Lithiel:BAAALgADCgYJCgAAAA==.Liuna:BAAALgADCgEJAQABLgAFFAMJBQAEAOkYAA==.',
Lo='Lonelycougar:BAAALgADCgcJDwAAAA==.Lore:BAAALgAECggJLQAAAQ==.Lothstein:BAAALgAECgQJBQAAAA==.Lovely:BAAALgAECgcJDQAAAA==.',
Lu='Lukri:BAAALgAECgEJAQAAAA==.Luminate:BAABLgAECn8gAAIRAAcJWSEZCgBIAgARAAcJWSEZCgBIAgAAAA==.Lunalah:BAAALgADCgcJBwAAAA==.Lunarray:BAAALgAECgEJAwAAAA==.Luxurious:BAABLgAECn8XAAIbAAcJYANrDQC8AAAbAAcJYANrDQC8AAAAAA==.',
Ly='Lyndea:BAAALgADCgYJBgAAAA==.',
['Lí']='Líllsnorre:BAAALgAECgMJBAAAAA==.',
Ma='Maaca:BAAALgADCgQJBAAAAA==.Madkow:BAAALgAECgQJBAAAAA==.Magichronic:BAAALgADCgQJBAAAAA==.Magnomonk:BAAALgAECgYJDQAAAA==.Majesticelf:BAAALgADCgcJCQAAAA==.Majuhstee:BAAALgADCgcJCAABLgAFFAEJAQAIAAAAAA==.Malachor:BAAALgAECgUJCQAAAA==.Maligned:BAABLgAECn8fAAICAAYJHR/4CACIAQACAAYJHR/4CACIAQAAAA==.Marsilea:BAAALgADCgcJCgAAAA==.Martichoux:BAABLgAECn8VAAIKAAgJnhyyPwB6AgAKAAgJnhyyPwB6AgAAAA==.Marvyy:BAAALgADCggJCAAAAA==.Mash:BAAALgAECgEJAQAAAA==.Mathas:BAABLgAECn8gAAIHAAkJhR0nEQCJAgAHAAkJhR0nEQCJAgAAAA==.Mathilda:BAAALgADCgEJAQAAAA==.Mazes:BAAALgAECgUJEQAAAA==.',
Mc='Mccholock:BAAALgAECgUJCQAAAA==.Mcmach:BAAALgAECgYJEwAAAA==.',
Me='Mediocrepaly:BAAALgAECgcJCQAAAA==.Mehaoloka:BAAALgADCgYJBgAAAA==.Mekanthis:BAACLgAFFH8OAAICAAUJSyIfAwCRAQACAAUJSiIfAwCRAQAuAAQKfyEAAgIACAmgJTsCAFEDAAIACAmgJTsCAFEDAAAA.Menoah:BAAALgAECgYJCwAAAA==.Merdoc:BAAALgAECgYJDAAAAA==.Meredith:BAAALgAECgYJCwAAAA==.Mesilana:BAAALgADCgkJCwAAAA==.Metalhoof:BAAALgAECgQJBwAAAA==.',
Mi='Michelangelo:BAAALgAECgEJAQAAAA==.Mikak:BAAALgAECgIJAQAAAA==.Milanova:BAAALgADCgYJDQABLgAECgcJEQAIAAAAAA==.Mirenna:BAAALgAECgYJCwAAAA==.Mirra:BAAALgAECgEJAQAAAA==.Misseymiss:BAAALgAECgMJBAAAAA==.',
Mo='Mogwhy:BAABLgAECn8dAAIhAAYJYxNKBgBPAQAhAAYJYxNKBgBPAQAAAA==.Monichan:BAAALgAECgQJBwAAAA==.Monkeypocket:BAAALgADCgQJBAAAAA==.Moonstrikex:BAAALgADCgUJBQAAAA==.Mooseknuckle:BAAALgAECgcJDQAAAA==.Moralekillas:BAAALgAECggJCgAAAA==.Morganna:BAAALgAECgEJAQAAAA==.Morior:BAAALgAECgYJCgAAAA==.Motorcade:BAABLgAECn8VAAIfAAcJqwGhKgDAAAAfAAcJqwGhKgDAAAAAAA==.',
Mu='Muchoblades:BAAALgAECgYJCwAAAA==.Murazor:BAAALgADCgUJBAAAAA==.Murples:BAAALgAFFAEJAQAAAA==.',
My='Myronastus:BAAALgADCgEJAQAAAA==.',
Ne='Neather:BAAALgAECgcJEgAAAA==.Neels:BAAALgADCgMJAwAAAA==.Neodke:BAAALgAECgEJAQAAAA==.Neodken:BAAALgADCgYJCgAAAA==.Neron:BAAALgAECgEJAQAAAA==.Nestlee:BAAALgADCgcJBwAAAA==.Nevvermore:BAAALgAECgMJAwAAAA==.Nexeon:BAAALgADCgEJAQABLgAECgYJFgALAOgdAA==.',
Ni='Niare:BAAALgAECgIJAgAAAA==.Ninfami:BAAALgADCggJCAAAAA==.Ninfamy:BAAALgADCgQJBQAAAA==.Ninfinite:BAABLgAECn8gAAIDAAgJehtRDAAaAgADAAgJehtRDAAaAgAAAA==.Nira:BAAALgAECgYJBgAAAA==.',
No='Nockturne:BAAALgADCgMJAwAAAA==.Norasmina:BAAALgAECgEJAQAAAA==.Norr:BAABLgAECn8ZAAIBAAcJsyLnEAA1AgABAAcJsyLnEAA1AgAAAA==.Northpaul:BAAALgADCgQJBAAAAA==.Notdeadyet:BAAALgAECgUJCQAAAA==.Notneels:BAAALgAECgQJBQAAAA==.',
Ny='Nyceria:BAAALgAECgUJCQAAAA==.Nyseria:BAAALgADCgEJAQAAAA==.',
Oa='Oakarm:BAAALgAECgYJAgAAAA==.',
Ob='Obpwnkenobi:BAAALgAECgQJCwAAAA==.',
Od='Odyssius:BAAALgAECgUJDgAAAA==.',
Og='Ogden:BAAALgAECgIJAgABLgAECgcJHgARANoGAA==.',
Ol='Oldandblind:BAAALgAECgYJCQAAAA==.',
On='Ontherun:BAAALgADCgQJBQAAAA==.',
Op='Oprawinfury:BAAALgAECgYJEgAAAA==.',
Or='Oralia:BAAALgAECgYJBgAAAA==.Ordun:BAAALgAECgMJAwAAAA==.Orphani:BAAALgADCgIJAgAAAA==.',
Os='Oscarguydude:BAABLgAECn8ZAAMdAAcJexxQYABHAQAdAAUJLB1QYABHAQAkAAUJMBecSgAnAQAAAA==.',
Ou='Ourus:BAABLgAECn8gAAMlAAkJzCGZAAAUAwAlAAkJzCGZAAAUAwAZAAgJIw9yMwDdAQAAAA==.',
Ow='Owlpha:BAAALgAECgUJBQAAAA==.',
Ox='Oxlob:BAABLgAECn8VAAIBAAgJThGWLwCDAQABAAgJThGWLwCDAQAAAA==.',
Pa='Pallaminnow:BAAALgAECgIJAgAAAA==.Pallychef:BAAALgADCgQJBAABLgAECgUJEgAIAAAAAA==.Panax:BAAALgADCgcJBwAAAA==.Pawtyr:BAAALgAECgEJAQABLgAECgcJGAAIAAAAAQ==.',
Pe='Peachieriest:BAAALgAECgMJAQAAAA==.Pele:BAAALgAECgQJCwAAAA==.Perpetrator:BAAALgAECgYJEgAAAA==.',
Ph='Pheonix:BAAALgADCgYJBgAAAA==.Phyre:BAAALgADCggJDQAAAA==.',
Pi='Pikahboo:BAAALgADCgYJBgAAAA==.',
Po='Poepwn:BAABLgAECn8bAAIMAAcJshFlFwBOAQAMAAcJshFlFwBOAQAAAA==.',
Pr='Priestbot:BAAALgADCgcJCwAAAA==.Promo:BAAALgADCgIJAgAAAA==.Prydae:BAAALgADCgQJBwAAAA==.',
Py='Pynelope:BAAALgADCgMJAwAAAA==.',
['Pû']='Pûrplehaze:BAAALgAECgMJAwAAAA==.',
Qu='Quelude:BAAALgAECgcJDQAAAA==.Quill:BAABLgAECn8UAAMPAAgJwxfzKQAKAgAPAAgJwxfzKQAKAgAOAAMJwRMWIgCNAAAAAA==.',
Ra='Raeris:BAEALgAECgcJAQAAAA==.Raicleach:BAAALgAECgkJCAAAAA==.Rainbow:BAAALgADCgcJDAAAAA==.Raktan:BAAALgAECgIJAgAAAA==.Rancidgreen:BAAALgADCgIJAgAAAA==.Rannick:BAAALgAECgYJCgAAAA==.Ranua:BAABLgAECn8nAAMRAAgJ8xvaHQAtAgARAAgJ8xvaHQAtAgAEAAYJiwwDIwAHAQAAAA==.Ratio:BAABLgAECn8UAAIDAAYJNRqLOAABAQADAAYJNRqLOAABAQAAAA==.Ravenhunt:BAAALgAECgQJBAAAAA==.Ravenreaper:BAAALgADCgMJBAAAAA==.Rawmanu:BAAALgADCgcJBwAAAA==.',
Re='Reania:BAAALgADCgUJCAAAAA==.Rectified:BAAALgAECgQJBgAAAA==.Redbreastman:BAAALgAECgQJCwAAAA==.Rekka:BAAALgAECgQJBAAAAA==.Reoshe:BAAALgAECgEJAQAAAA==.',
Ri='Ripdvanwinkl:BAAALgAECgUJEgAAAA==.',
Ro='Roachpocket:BAAALgADCgQJBAAAAA==.Ronyn:BAAALgAECgYJDgAAAA==.',
Ru='Rudolf:BAAALgAECgQJBQAAAA==.',
Rw='Rwarar:BAAALgADCgUJCAAAAA==.Rwqr:BAAALgADCgYJBwAAAA==.',
['Rä']='Räiden:BAAALgAECgQJBAAAAA==.',
['Rö']='Rötthgard:BAAALgADCgcJBwAAAA==.',
Sa='Salacakei:BAABLgAECn8fAAMgAAgJTxLvCQDLAQAgAAgJLBLvCQDLAQAhAAQJBwv5EwC/AAAAAA==.Salin:BAAALgAECgYJCgAAAA==.Salithril:BAAALgADCgMJBQAAAA==.Sanzo:BAAALgADCgMJAwABLgAECgYJCgAIAAAAAA==.Sarthiy:BAAALgAECgcJDgABLgAFFAUJFAAGAPojAA==.Sarthy:BAACLgAFFH8UAAIGAAUJ+iOOAACVAQAGAAUJ+iOOAACVAQAuAAQKfy8AAgYACQkQJGYAAJcDAAYACQkQJGYAAJcDAAAA.Sassaphras:BAABLgAECn8VAAIUAAcJNx/mEQBSAgAUAAcJNx/mEQBSAgAAAA==.Satheron:BAAALgAECgYJCAAAAA==.Satyric:BAAALgAECgIJAgAAAA==.Saxifon:BAAALgADCgQJBAAAAA==.',
Sc='Scarletpaw:BAAALgAECgUJCAAAAA==.Scoobie:BAAALgADCgUJAQAAAA==.Scoobydo:BAAALgAECgEJAQABLgAECgYJDQAIAAAAAA==.Screwwithme:BAAALgADCgYJBgAAAA==.Scrubs:BAACLgAFFH8LAAIdAAQJ7AnMEAA1AQAdAAQJ7AnMEAA1AQAuAAQKfyIAAh0ACAkVHFUfAEkCAB0ACAkVHFUfAEkCAAAA.',
Se='Seriadrina:BAAALgADCgIJAgAAAA==.',
Sh='Shaadow:BAAALgAECgEJAQAAAA==.Shallabal:BAAALgAECgcJAgAAAA==.Shamyaltak:BAAALgAECgkJDAAAAA==.Shandralore:BAAALgAECgYJCwAAAA==.Shauranna:BAAALgAECgMJAwAAAA==.Shiel:BAAALgAECgUJCQAAAA==.Shockdoctor:BAABLgAECn8cAAIRAAcJHiRCBgCKAgARAAcJHiRCBgCKAgAAAA==.Shogunasasin:BAABLgAECn8bAAMMAAgJBQ2xKQBnAQAMAAgJBQ2xKQBnAQALAAMJuxqMTQDbAAAAAA==.Shortrange:BAAALgAECgYJDAAAAA==.Shuzui:BAAALgADCgQJBAAAAA==.',
Si='Sicarion:BAAALgAECgQJBwAAAA==.Silentwalkr:BAAALgAECgIJAgAAAA==.',
Sl='Sleples:BAAALgAECgYJDQAAAA==.Slufgor:BAAALgAECgQJBwAAAA==.',
Sm='Smolder:BAAALgADCgkJFAAAAA==.',
Sn='Snoo:BAAALgAECgQJCgAAAA==.Snoogon:BAAALgAECgIJAgABLgAECgQJCgAIAAAAAA==.Snorrehunter:BAAALgAECgQJBgAAAA==.',
So='Solarlite:BAAALgAECgEJAQAAAA==.Solek:BAAALgADCgIJAgAAAA==.Solorion:BAAALgAECgYJCQAAAA==.Sorovar:BAABLgAECn8UAAImAAgJPSEDCAC/AgAmAAgJPSEDCAC/AgAAAA==.',
Sp='Spamm:BAAALgAECgQJBAAAAA==.Spony:BAAALgAECgQJBwAAAA==.',
St='Starbrow:BAAALgAECgQJCAABLgAECgYJFQAQADwjAA==.Stein:BAAALgADCgYJBgAAAA==.Steinn:BAAALgADCgEJAQAAAA==.Stevewinwood:BAAALgAECgYJBwAAAA==.Stormlight:BAAALgAECgYJCwAAAA==.',
Su='Sushistryke:BAAALgAECgUJCAAAAA==.',
Sy='Syland:BAAALgAECgUJCQAAAA==.Sylanis:BAAALgADCgEJAQAAAA==.Sylissa:BAAALgADCgUJCAAAAA==.Sylvanäs:BAAALgAECgUJEAAAAA==.Sylvenna:BAAALgAECgYJDAAAAA==.Sypress:BAAALgADCgcJDgAAAA==.Syrelastus:BAAALgAECgEJAQAAAA==.Sysna:BAAALgAECgYJEwAAAA==.',
Ta='Tachyon:BAAALgAECgEJAQAAAA==.Talley:BAABLgAECn8fAAIRAAgJdBUXFgC3AQARAAgJdBUXFgC3AQAAAA==.Targis:BAAALgAECgYJEwAAAA==.Tauran:BAAALgAECgQJCAAAAA==.Tazanaz:BAAALgAECgQJBQABLgAECggJJwARAPMbAA==.',
Te='Templeton:BAAALgAECgUJBQABLgAECgcJHgARANoGAA==.Tendai:BAAALgADCgkJGAAAAA==.Tenloth:BAAALgAECgUJCAAAAA==.Teozr:BAAALgADCgMJAwAAAA==.Teufelshund:BAAALgADCgcJBwAAAA==.',
Th='Thaeldrin:BAAALgADCgEJAQAAAA==.Thaleas:BAABLgAECn8VAAIGAAYJ8Bl8FgBrAQAGAAYJ8Bl8FgBrAQAAAA==.Thorizine:BAAALgADCgMJAwAAAA==.Thorlas:BAAALgAECgYJDwAAAA==.Thorsham:BAAALgAECgYJBgAAAA==.',
Ti='Timadin:BAAALgADCgEJAQAAAA==.Timmúk:BAAALgAECgMJAwAAAA==.',
To='Tomma:BAABLgAECn8VAAICAAgJpCF+BgDOAgACAAgJpCF+BgDOAgAAAA==.Totem:BAAALgADCggJCAAAAA==.Totembi:BAACLgAFFH8JAAIRAAQJZwzQCwAcAQARAAQJZwzQCwAcAQAuAAQKfzIAAhEACQmrFwQMACsCABEACQmrFwQMACsCAAAA.',
Tr='Trailerpark:BAAALgAECgYJCQAAAA==.Tratre:BAABLgAECn8nAAQTAAkJhBZ3BgA1AgATAAkJhBZ3BgA1AgASAAYJawqxEADyAAAVAAEJYxITPQA6AAAAAA==.Treynof:BAAALgAECgcJEwAAAA==.Truewill:BAAALgADCgEJAQAAAA==.Trupeti:BAAALgAECgUJEgAAAA==.',
Tu='Tulsiice:BAAALgAECgYJDgAAAA==.',
Tw='Twoglaivez:BAAALgAECgUJBQABLgAFFAcJFgAZAH8cAA==.',
Ty='Tytaniormu:BAAALgAECggJEQAAAA==.',
['Tê']='Tês:BAAALgADCgEJAQAAAA==.',
Ug='Ugless:BAAALgADCgYJBgABLgADCgcJCAAIAAAAAA==.Uglify:BAAALgADCgcJCAAAAA==.',
Ul='Ulanmonk:BAAALgADCgMJAwAAAA==.Ulridan:BAAALgAECgEJAQABLgAFFAMJBQAEAOkYAA==.',
Un='Undeathtwoy:BAABLgAECn8eAAMQAAcJzhljaAC9AQAQAAcJaRZjaAC9AQACAAYJOROIEwDqAAAAAA==.Undos:BAAALgADCgUJBQAAAA==.Unholyveri:BAAALgAECgYJBgAAAA==.',
Va='Vaelraen:BAAALgAECgYJDgAAAA==.Valcher:BAAALgAECgMJBgAAAA==.Valendera:BAABLgAECn8UAAIYAAgJ2gsAYACpAQAYAAgJ2gsAYACpAQAAAA==.Valhri:BAAALgAECgIJBAAAAA==.Valifadin:BAAALgAECgYJCwAAAA==.Valith:BAAALgAECgQJCQAAAA==.Valmoria:BAAALgADCgkJEQAAAA==.Valndrevy:BAAALgADCgUJDAAAAA==.Vansan:BAAALgAECgYJCAABLgAECggJJwARAPMbAA==.',
Ve='Vellas:BAAALgAECgEJAQAAAA==.Venngennce:BAABLgAECn8hAAMnAAkJAB5AAAD1AgAnAAkJAB5AAAD1AgAQAAMJ4Ar1+wCDAAAAAA==.',
Vi='Vintage:BAACLgAFFH8LAAIFAAMJhA4UAQDsAAAFAAMJhA4UAQDsAAAuAAQKfyIAAgUACQnlGfYAAAMDAAUACQnlGfYAAAMDAAAA.Visage:BAAALgADCgYJBgAAAA==.',
Vo='Voided:BAAALgAECgcJDAAAAA==.Volkareth:BAABLgAECn8UAAIVAAgJIRTLDQD9AQAVAAgJIRTLDQD9AQAAAA==.Vorkath:BAABLgAECn8gAAQVAAcJziIyAQBfAgAVAAcJziIyAQBfAgASAAYJIyDRBwCyAQATAAEJmx+SWABcAAAAAA==.Vormette:BAAALgADCgkJEwAAAA==.',
Vt='Vtae:BAAALgAECgYJDwAAAA==.',
Wa='Waka:BAAALgADCgkJCQABLgAECggJFQABAE4RAA==.Waryndor:BAAALgADCgYJBgAAAA==.',
We='Werehamster:BAABLgAECn8VAAIPAAYJJxm1JQBXAQAPAAYJJxm1JQBXAQAAAA==.',
Wi='Wilderbeast:BAABLgAECn8XAAIPAAcJcwMIeQDtAAAPAAcJcwMIeQDtAAAAAA==.Wildlife:BAAALgADCgEJAQAAAA==.',
Wo='Woodrow:BAAALgADCgcJDgABLgAECgcJHgARANoGAA==.Woxkal:BAABLgAECn8YAAMCAAcJhQalGgCmAAACAAcJhQalGgCmAAAQAAEJ0AGhNwEhAAAAAA==.',
Wu='Wubblebubble:BAAALgAECgcJEQAAAA==.',
Xa='Xaelin:BAAALgAECgQJBgAAAA==.',
Xy='Xynelle:BAAALgADCgcJCwAAAA==.',
Yi='Yisús:BAAALgAECgIJAwAAAA==.',
Yl='Ylvis:BAABLgAECn8aAAIdAAYJmRieKgBqAQAdAAYJmRieKgBqAQAAAA==.',
Yo='Yoshymi:BAAALgAECgcJGAAAAQ==.',
Yu='Yuná:BAAALgADCgMJAwAAAA==.',
Yv='Yvetal:BAAALgAECgIJAgAAAA==.',
Za='Zacco:BAAALgAECgQJCQAAAA==.Zaleth:BAACLgAFFH8KAAISAAYJ1wt1CQA8AQASAAYJ1wt1CQA8AQAuAAQKfyUAAhIABwkYIacIALACABIABwkYIacIALACAAAA.Zamazenta:BAAALgADCgcJCwAAAA==.Zaranne:BAAALgAECgkJEQAAAA==.Zargar:BAAALgADCgYJBgAAAA==.Zarion:BAAALgAECgYJBwABLgAFFAYJCgASANcLAA==.Zarra:BAAALgAECgMJBAAAAA==.Zathuera:BAAALgADCgQJBAAAAA==.',
Ze='Zeroz:BAAALgAECgcJCwAAAA==.',
Zh='Zhath:BAAALgAECgIJBAAAAA==.',
Zi='Zilik:BAAALgAFFAEJAQABLgAFFAYJCgASANcLAA==.',
Zo='Zocorro:BAAALgAECgQJCgAAAA==.Zodiack:BAAALgAECgcJCQAAAA==.Zombe:BAAALgAECggJEgAAAA==.',
Zu='Zuelmst:BAAALgAECgIJAgAAAA==.',
['Ân']='Ângel:BAAALgAFFAEJAQAAAA==.',
['Ðe']='Ðecision:BAABLgAECn8dAAIBAAkJfyOrEQAEAwABAAkJfyOrEQAEAwAAAA==.',
['Øn']='Ønslaught:BAAALgADCgUJBQABLgAECggJFQABAE4RAA==.',
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
