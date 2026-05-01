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

local lookup = {'DeathKnight-Unholy','DemonHunter-Devourer','Paladin-Protection','Druid-Guardian','Hunter-BeastMastery','Unknown-Unknown','Mage-Frost','Paladin-Retribution','Paladin-Holy','Warlock-Demonology','Warlock-Destruction','Warrior-Fury','Warrior-Arms','Priest-Holy','DemonHunter-Havoc','Druid-Restoration','Druid-Balance','Warrior-Protection','DemonHunter-Vengeance','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Hunter-Marksmanship','DeathKnight-Blood','Shaman-Restoration','Druid-Feral','Priest-Discipline','Monk-Mistweaver','Rogue-Subtlety','Rogue-Assassination','Monk-Brewmaster','Hunter-Survival','DeathKnight-Frost','Priest-Shadow','Rogue-Outlaw','Shaman-Enhancement','Mage-Arcane','Shaman-Elemental','Warlock-Affliction','Mage-Fire',}
local provider = {region='US',realm='Kilrogg',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aazr:BAAALgADCgQJBAAAAA==.',
Ab='Abartheris:BAABLgAECn8YAAIBAAYJwgRDdgCyAAABAAYJwgRDdgCyAAAAAA==.',
Ac='Acanoffood:BAABLgAECn8YAAICAAgJVhDPIgBjAQACAAgJVhDPIgBjAQAAAA==.',
Ad='Adel:BAAALgAECgMJAwAAAA==.Adelil:BAAALgADCgEJAQAAAA==.Ademai:BAAALgADCgIJAgAAAA==.Adeptus:BAABLgAECn8VAAIDAAYJ5A31IgDwAAADAAYJ5A31IgDwAAAAAA==.',
Ae='Aemeath:BAABLgAECn8bAAICAAgJtxs2OgALAgACAAgJtxs2OgALAgAAAA==.Aendres:BAAALgAECgQJBQAAAA==.',
Af='Afitis:BAAALgADCgEJAQAAAA==.',
Ag='Agriopas:BAABLgAECn8XAAIEAAUJdwZYJAB6AAAEAAUJdwZYJAB6AAABLgAECgYJGQAFANAKAA==.',
Ah='Aharon:BAAALgADCgkJCgAAAA==.',
Ai='Aireas:BAAALgAECgEJAQAAAA==.Aizen:BAAALgADCgYJBgABLgAECgYJCAAGAAAAAA==.',
Al='Alassomorph:BAAALgAECgUJCwAAAA==.Alazaie:BAAALgADCgMJAwAAAA==.Albus:BAABLgAECn8lAAIHAAkJKSDzCQCfAgAHAAkJKSDzCQCfAgAAAA==.Allayna:BAABLgAECn8pAAIIAAkJhCDYAgD+AgAIAAkJhCDYAgD+AgAAAA==.Almitvez:BAAALgADCgcJBwABLgAECgYJCwAGAAAAAA==.Aloha:BAABLgAECn8UAAIJAAgJWw17EwC7AQAJAAgJWw17EwC7AQAAAA==.Alysaliu:BAACLgAFFH8IAAIKAAQJbxjDFwBAAQAKAAQJbxjDFwBAAQAuAAQKfykAAwoACAmKIj0aALcCAAoACAl1Ij0aALcCAAsABAm3FXkrABIBAAAA.Alysen:BAAALgAECgMJAwABLgAECgYJFgAMAFIfAA==.',
Am='Amisan:BAAALgADCgEJAQAAAA==.Amishpaladin:BAAALgAFFAEJAQAAAA==.Amishwarlock:BAAALgAECgYJCQABLgAFFAEJAQAGAAAAAA==.Amonotep:BAAALgAECgQJAwAAAA==.Amorianar:BAAALgADCgMJAwABLgAECggJCwAGAAAAAA==.Amory:BAAALgADCggJFgABLgADCgUJCAAGAAAAAA==.',
An='Anchor:BAAALgAECgcJCwAAAA==.Andja:BAABLgAECn8qAAINAAgJUCUxAQBJAwANAAgJUCUxAQBJAwAAAA==.Andromedae:BAABLgAECn8WAAIOAAgJjg6hFABsAQAOAAgJjg6hFABsAQAAAA==.Anexa:BAAALgAECgUJCwAAAA==.Angela:BAAALgAECgIJAwAAAA==.Anurek:BAAALgAECgEJAQAAAA==.',
Ar='Argulas:BAAALgADCgkJFQAAAA==.Ark:BAAALgAECgYJEgAAAA==.Arn:BAAALgAECgQJCQABLgAECgcJBwAGAAAAAA==.Arthrex:BAAALgAECgMJBwAAAA==.Arthus:BAAALgAECgYJDAAAAA==.Arturias:BAAALgAECgMJAwABLgAECgkJKwAPAMIhAA==.',
As='Asmobob:BAABLgAECn8VAAIPAAYJCxr6CwB9AQAPAAYJCxr6CwB9AQAAAA==.',
Au='Augmentin:BAABLgAECn8YAAMQAAgJaRkCVQBUAQAQAAYJkBsCVQBUAQARAAgJSg8+FwBFAQAAAA==.Auntfranny:BAAALgADCgEJAQAAAA==.Autoshot:BAAALgADCgYJBwAAAA==.',
Av='Avanie:BAAALgADCgYJBgAAAA==.Avina:BAAALgAECgEJAQAAAA==.Avrami:BAAALgADCgkJCgAAAA==.',
Aw='Aw:BAABLgAECn8fAAMKAAcJCSGHDABMAgAKAAYJCSGHDABMAgALAAQJPhdyJAA3AQAAAA==.Awokenbigdam:BAAALgAECgEJAQAAAA==.',
Ba='Babycoffee:BAAALgADCgcJEgAAAA==.Bahamutz:BAAALgADCgUJBAAAAA==.Bahwee:BAAALgAECgYJDwAAAA==.Bangbangdou:BAABLgAECn8UAAIJAAcJ9RChHgBTAQAJAAcJ9RChHgBTAQAAAA==.Banzjo:BAAALgADCggJCAAAAA==.Bastor:BAAALgADCgIJAgAAAA==.Bayle:BAAALgAECgUJCgAAAA==.',
Be='Bearnekkid:BAAALgAECgEJAQAAAA==.Beerthrowguy:BAAALgAECggJEgAAAA==.Bellaofroses:BAAALgADCgcJDAAAAA==.Bellatrix:BAAALgADCgYJBgAAAA==.Beneb:BAAALgAECgEJAwAAAA==.Benebeorn:BAACLgAFFH8GAAICAAQJ3hc5DQBMAQACAAQJ3hc5DQBMAQAuAAQKfxUAAgIACAmXH7MaALMCAAIACAmXH7MaALMCAAAA.Benkinobi:BAAALgAECgQJBwAAAA==.',
Bh='Bhaer:BAAALgAECgEJAgAAAA==.',
Bi='Bichewich:BAAALgADCgYJBgAAAA==.Bigal:BAAALgAECgMJAwAAAA==.Bigshot:BAAALgADCgYJCQAAAA==.Billyjoe:BAAALgAECgMJBQAAAA==.Binti:BAAALgADCgMJAwAAAA==.Bittronoxus:BAABLgAECn8aAAIHAAcJOA9AQABtAQAHAAcJOA9AQABtAQAAAA==.',
Bl='Blackryder:BAAALgAECgUJDgAAAA==.Bleys:BAAALgAECgMJAwABLgAECgkJKQAIAHcbAA==.',
Bo='Bobbysmerica:BAABLgAECn8dAAMSAAgJRRhuEQDwAQASAAgJRRhuEQDwAQANAAEJ9At7QgA0AAAAAA==.Bobocanfly:BAABLgAECn8UAAMTAAcJJRQ5CQATAQATAAcJJRQ5CQATAQAPAAEJAAANdAAxAAAAAA==.Bodikhan:BAAALgAECgUJCgAAAA==.Bonezeh:BAAALgAECggJCwAAAA==.',
Br='Braxte:BAABLgAECn8nAAMMAAgJsh5pFwCRAgAMAAgJBx5pFwCRAgANAAMJSxjlEgDpAAAAAA==.Briguydkguy:BAACLgAFFH8KAAIBAAQJjgspIgA0AQABAAQJjgspIgA0AQAuAAQKfxgAAgEACAmfFuZgANABAAEACAmfFuZgANABAAAA.Britziola:BAAALgAECgEJAQABLgADCgUJCAAGAAAAAA==.Brokenvoid:BAABLgAECn8XAAICAAcJgRYHTwC5AQACAAcJgRYHTwC5AQAAAA==.Bruiser:BAAALgAFFAIJAgAAAA==.Brusalt:BAAALgADCggJCAAAAA==.Bryce:BAAALgAECgUJDwAAAA==.',
Bu='Buggies:BAACLgAFFH8JAAIHAAQJRB6EDwCBAQAHAAQJRB6EDwCBAQAuAAQKfygAAgcACAlmJX4SADgDAAcACAlmJX4SADgDAAAA.Buggs:BAAALgAECgIJAgABLgAFFAQJCQAHAEQeAA==.Buldozz:BAABLgAECn8jAAIJAAcJxBK5NQClAQAJAAcJxBK5NQClAQAAAA==.Bullit:BAAALgADCgUJBQABLgAECgEJAQAGAAAAAA==.Burnination:BAABLgAECn8cAAIHAAYJFSZGFQAxAgAHAAYJFSZGFQAxAgAAAA==.Burnzie:BAAALgADCgUJAwAAAA==.Butterfayce:BAABLgAECn8pAAMJAAkJfhYyEADiAQAJAAkJfhYyEADiAQAIAAYJ6w7eTQAiAQAAAA==.',
By='Bycew:BAAALgAECgUJCAABLgAECgUJDwAGAAAAAA==.',
Ca='Cadastrasz:BAABLgAECn80AAQUAAgJGw4tCgB1AQAUAAgJGw4tCgB1AQAVAAYJDggdJwDTAAAWAAMJrAFdOQBOAAAAAA==.Cae:BAAALgADCgUJCQAAAA==.Camachopres:BAAALgADCgYJBgAAAA==.Cameocreme:BAAALgAECgEJAQAAAA==.Captfrost:BAAALgAECgEJAQAAAA==.Carsonkiller:BAAALgADCgEJAQABLgAECgcJFAALAPcbAA==.Cateurize:BAABLgAECn8XAAIVAAkJiA2sDAC9AQAVAAkJiA2sDAC9AQAAAA==.',
Ce='Ceenit:BAABLgAECn8kAAIIAAgJpx4vEAA8AgAIAAgJpx4vEAA8AgAAAA==.Celalaliia:BAAALgADCgMJAwAAAA==.Celawyn:BAAALgAECgcJDgAAAA==.',
Ch='Chainedfire:BAAALgADCgkJHgAAAA==.Chasemon:BAAALgAECgYJDgAAAA==.Chaser:BAAALgAECgEJAQABLgAECgYJDgAGAAAAAA==.Chaøtical:BAAALgAECgQJBAAAAA==.Chicosan:BAAALgADCgcJBwAAAA==.Chrisolski:BAAALgADCgcJEwABLgAECgIJAgAGAAAAAA==.',
Ci='Cirragos:BAAALgAECgYJEAAAAA==.',
Cl='Clamer:BAAALgADCgcJEAAAAA==.Clawdite:BAAALgADCgYJBgABLgAECgYJCwAGAAAAAA==.Cleansinq:BAAALgAECgEJAQAAAA==.Cloudsmoker:BAABLgAECn8WAAMQAAgJGgyaVgBPAQAQAAgJGgyaVgBPAQARAAIJTgfJdQBMAAAAAA==.',
Co='Corien:BAAALgAECgQJBQAAAA==.',
Cr='Crazegrippin:BAAALgAECgIJAwAAAA==.Crimsonmoon:BAABLgAECn8pAAIXAAkJtw6vAwDnAQAXAAkJtw6vAwDnAQAAAA==.Cryomara:BAAALgADCgYJCQAAAA==.',
Cu='Cueball:BAAALgADCgYJDAAAAA==.',
Cy='Cylasta:BAAALgADCgQJBgAAAA==.Cyndraexa:BAAALgAECgQJCQAAAA==.Cynia:BAAALgAECgYJDAAAAA==.Cynra:BAABLgAECn8bAAIQAAgJERo/CwBUAgAQAAgJERo/CwBUAgAAAA==.Cyrakos:BAAALgADCgEJAQAAAA==.',
['Cõ']='Cõwbell:BAAALgADCgEJAQAAAA==.',
Da='Dalize:BAAALgAECgcJCwAAAA==.Danarrath:BAAALgAECgYJEQAAAA==.Danger:BAAALgAECgQJBQAAAA==.Danklins:BAABLgAECn8nAAMVAAgJCRQ/DgCoAQAVAAgJ6RI/DgCoAQAWAAcJRRFMBACIAQAAAA==.Dariabell:BAAALgADCggJCwAAAA==.Darkramone:BAAALgAECgEJAgAAAA==.Darrow:BAAALgADCgQJBAAAAA==.Darthbane:BAAALgAECgQJBQAAAA==.Darthvada:BAAALgAECgUJDQAAAA==.',
De='Deadpoint:BAABLgAECn8WAAIMAAYJUh+4GABrAQAMAAYJUh+4GABrAQAAAA==.Deadski:BAAALgAECgQJCQAAAA==.Deathfrost:BAACLgAFFH8GAAIHAAQJZg9TIABRAQAHAAQJZg9TIABRAQAuAAQKfxoAAgcACAnTGBlUADwCAAcACAnTGBlUADwCAAAA.Debz:BAAALgADCgkJCQAAAA==.Defeatzhealz:BAAALgAECgYJEwAAAA==.Defeatzhunt:BAABLgAECn8XAAMFAAgJCxnZHABZAgAFAAgJCxnZHABZAgAXAAEJAABdnAAJAAAAAA==.Deirdra:BAAALgADCgkJCQABLgAECgkJKQAIAHcbAA==.Delarium:BAAALgAECgEJAQAAAA==.Demonaria:BAABLgAECn8rAAIPAAkJwiHBAAAPAwAPAAkJwiHBAAAPAwAAAA==.Denariah:BAAALgAECgMJAwABLgAECgYJFwAEADkbAA==.Dendranaar:BAAALgAECgMJBAAAAA==.Dernen:BAAALgAECgYJDwABLgAECgYJEQAGAAAAAA==.Derpnface:BAAALgAECgYJEwAAAA==.Desecration:BAABLgAECn8nAAICAAcJySPLEADpAQACAAcJySPLEADpAQAAAA==.Devilhandler:BAAALgADCgEJAQAAAA==.Dezimorikko:BAAALgADCgcJBwAAAA==.',
Di='Dirgir:BAABLgAECn8WAAIYAAgJfSD9AwALAgAYAAgJfSD9AwALAgAAAA==.Distonia:BAABLgAECn8VAAIZAAYJPh/RDQARAgAZAAYJPh/RDQARAgAAAA==.',
Do='Dorothy:BAACLgAFFH8HAAIBAAMJqAnYLgDdAAABAAMJqAnYLgDdAAAuAAQKfx0AAgEACAkjHaUVAA0CAAEACAkjHaUVAA0CAAAA.',
Dr='Dracheo:BAACLgAFFH8IAAIHAAQJYBGlHgBVAQAHAAQJYBGlHgBVAQAuAAQKfykAAgcACAliIeEtALoCAAcACAliIeEtALoCAAAA.Dragonbrr:BAAALgAECgQJBgABLgAECgcJFwAJADYiAA==.Dragonwizard:BAABLgAECn8bAAIHAAYJzx+YaAAFAgAHAAYJzx+YaAAFAgAAAA==.Drakonna:BAAALgAECgIJAwAAAA==.Dranix:BAAALgAECgUJCwAAAA==.Dreygur:BAAALgAECgQJBQAAAA==.Droiden:BAAALgAECgUJCwAAAA==.Droidén:BAAALgADCggJCAAAAA==.Drotar:BAABLgAECn8bAAMRAAcJDArPTQDyAAARAAYJywrPTQDyAAAaAAYJJwUuEwCoAAAAAA==.',
Du='Dumbdog:BAACLgAFFH8GAAIQAAMJ1xokDAAgAQAQAAMJ1xokDAAgAQAuAAQKfzEAAxAACAl8JoYDAFoDABAACAl8JoYDAFoDABEABgmaExA+ADoBAAEuAAUUBQkVABQAeBkA.Dumichauch:BAACLgAFFH8GAAIQAAQJsAzpFADxAAAQAAQJsAzpFADxAAAuAAQKfyYAAhAACAl5G+8XAHcCABAACAl5G+8XAHcCAAAA.Durin:BAABLgAECn8VAAIIAAYJ8xQlQQBGAQAIAAYJ8xQlQQBGAQAAAA==.',
['Dé']='Déâth:BAAALgADCgkJCwAAAA==.',
Ec='Echo:BAAALgAECgcJCAAAAA==.',
Eg='Eggars:BAAALgAECgYJEQAAAA==.',
Ek='Ekee:BAAALgAECgEJAQAAAA==.',
El='Elegance:BAAALgADCgIJAgAAAA==.Ellý:BAAALgADCgEJAQAAAA==.',
Em='Emberleaf:BAAALgADCgQJCAAAAA==.Emofriz:BAAALgAECgUJCQAAAA==.Emolate:BAAALgAECggJDQABLgAFFAYJFgAFAKocAA==.',
En='Enve:BAABLgAECn8iAAICAAkJXB9qBACkAgACAAkJXB9qBACkAgAAAA==.',
Er='Erso:BAAALgADCgcJBwAAAA==.',
Ev='Evanorah:BAAALgAECgEJAQAAAA==.Eviltiger:BAABLgAECn8mAAIXAAkJnRVnAgAsAgAXAAkJnRVnAgAsAgAAAA==.',
Ew='Ewik:BAABLgAECn8ZAAMUAAgJYBd1EgAYAgAUAAgJYBd1EgAYAgAWAAMJLA0kDQCCAAAAAA==.',
Ex='Excalìbur:BAAALgAECgQJBAAAAA==.',
Ey='Eydor:BAAALgADCggJCAAAAA==.',
Fa='Faent:BAAALgAECgUJDgAAAA==.Falimonki:BAAALgAECgMJAwAAAA==.Falinora:BAACLgAFFH8GAAIJAAMJ7hBcEwDXAAAJAAMJ7hBcEwDXAAAuAAQKfygAAwkACAltGaIiAAoCAAkACAltGaIiAAoCAAgABwn/EhyuACcBAAAA.Famous:BAAALgAECgMJAwAAAA==.Fantasticfox:BAABLgAECn8tAAMKAAgJsg8bJQCcAQAKAAgJsg8bJQCcAQALAAQJSQpGMgDvAAAAAA==.',
Fe='Felbyte:BAAALgADCgMJAwAAAA==.Felixs:BAAALgAECgQJCQAAAA==.Fellhanded:BAAALgADCgcJBwAAAA==.Feloron:BAAALgAECgMJAwAAAA==.Feluria:BAAALgADCgYJBgAAAA==.Feodin:BAAALgAECgUJCgABLgAECggJHgACAFAXAA==.Feosdragon:BAAALgADCgYJBgAAAA==.Ferrovax:BAAALgADCgEJAQABLgAECggJGgACADYcAA==.',
Fi='Fistariir:BAAALgADCgIJAgABLgAFFAQJDQAbALsWAA==.Fitzchivalry:BAAALgAECgIJAwAAAA==.',
Fl='Fleethefield:BAAALgAECgUJDAAAAA==.Flowabridge:BAABLgAECn8VAAIHAAYJrQOeAgH2AAAHAAYJrQOeAgH2AAABLgAECgcJFwARAMAOAA==.',
Fo='Forcewild:BAABLgAECn8VAAIEAAYJLiGMBADZAQAEAAYJLiGMBADZAQAAAA==.',
Fr='Fragos:BAAALgAECgYJBwAAAA==.Friz:BAACLgAFFH8HAAMLAAQJgwggBwCXAAALAAMJqAcgBwCXAAAKAAIJIwtBSgCWAAAuAAQKfx8AAwsACAnXHVwIADwCAAsABwlfHlwIADwCAAoABAn3GryeABsBAAAA.Frostychunks:BAAALgAECggJEwAAAA==.',
Fu='Fuddrucker:BAAALgADCgcJCwAAAA==.Furflation:BAABLgAECn8VAAMUAAYJxxQECgB5AQAUAAYJxxQECgB5AQAWAAUJ9BhVBgA2AQAAAA==.Furgam:BAAALgAECgEJAQAAAA==.Fury:BAAALgADCgYJCgABLgAECgEJAQAGAAAAAA==.Fuzzychunks:BAAALgAECgQJCAABLgAECggJEwAGAAAAAA==.',
Ga='Gabapentin:BAAALgAECggJDwAAAA==.Gaeren:BAAALgADCgkJEwAAAA==.Gal:BAAALgAECgEJAQAAAA==.Gannon:BAABLgAECn8dAAIHAAgJ3xviGwAEAgAHAAgJ3xviGwAEAgAAAA==.Gano:BAEALgAECgIJBAABLgAFFAQJBwABANgLAA==.Garr:BAAALgAECgEJAQABLgAECgEJAgAGAAAAAA==.Garuuk:BAAALgAECgUJBQAAAA==.Gazir:BAAALgAECggJCwAAAA==.',
Ge='Geniús:BAAALgADCgYJBgAAAA==.Genji:BAAALgAECgYJDQAAAA==.',
Gi='Giliandra:BAAALgADCgUJCgAAAA==.',
Gl='Glitch:BAABLgAECn8ZAAISAAYJqwFzIQBvAAASAAYJqwFzIQBvAAAAAA==.',
Gn='Gnxs:BAAALgAECgMJAwAAAA==.',
Go='Goonthar:BAACLgAFFH8GAAIMAAMJQA+JEwDlAAAMAAMJQA+JEwDlAAAuAAQKfyMAAgwACAnAIo4CALkCAAwACAnAIo4CALkCAAAA.Gorethak:BAAALgAECgQJCgAAAA==.',
Gr='Grannykul:BAAALgADCgEJAQAAAA==.Grindrage:BAAALgADCgEJAQAAAA==.Grobble:BAAALgADCgcJGgAAAA==.Grollgrr:BAAALgAECgQJCAAAAA==.Grompo:BAAALgADCgkJFwABLgAECgcJHwAKAAkhAA==.Grompy:BAAALgADCgQJBAABLgAECgcJHwAKAAkhAA==.Gruffbeard:BAAALgAECgIJAgABLgAECgUJCQAGAAAAAA==.',
Gu='Gunghoiguana:BAAALgADCgkJEgAAAA==.',
Gy='Gyattso:BAAALgAECgUJBQAAAA==.Gyxx:BAABLgAFFH8HAAMJAAMJeBgYEQDvAAAJAAMJeBgYEQDvAAAIAAIJtg3vLgCoAAAAAA==.',
Ha='Haddice:BAAALgAECgUJDQAAAA==.Hafarti:BAAALgADCgUJBAAAAA==.Hairyteeth:BAAALgAECgUJDgAAAA==.Hajime:BAAALgAECgQJBAAAAA==.Hamburgers:BAAALgAECgEJAQAAAA==.Harriedotter:BAAALgADCgkJGgAAAA==.',
He='Heebiejeebie:BAABLgAECn8xAAMKAAgJIBhBFgDzAQAKAAgJIBhBFgDzAQALAAIJaQt9VwBoAAAAAA==.Hellaeus:BAABLgAECn8fAAIIAAcJ7xqiKACgAQAIAAcJ7xqiKACgAQAAAA==.Hellsong:BAAALgAECgYJBgAAAA==.',
Hi='Hinatasan:BAAALgAECgEJAgAAAA==.Hisokä:BAABLgAECn8nAAIPAAgJYxCzCwCBAQAPAAgJYxCzCwCBAQAAAA==.',
Ho='Hoku:BAAALgAECgMJBAAAAA==.Holycreambar:BAABLgAECn8bAAIIAAcJWiAkGQD0AQAIAAcJWiAkGQD0AQAAAA==.Holyjuan:BAAALgADCgkJEgAAAA==.Hoofsbane:BAAALgADCgcJBwAAAA==.',
Hu='Huntingale:BAAALgADCgkJFgAAAA==.Huntinshift:BAAALgAECgYJBgAAAA==.Huwn:BAAALgADCgQJBAAAAA==.',
Hy='Hygelak:BAAALgAECgYJDwAAAA==.Hypaxia:BAAALgAECgYJDwABLgAECgYJEwAGAAAAAA==.',
Ib='Ibpowerline:BAAALgADCgYJBgAAAA==.',
Ic='Icethorn:BAAALgAECgIJAwAAAA==.',
Ig='Iggysmalls:BAAALgAECggJCQAAAA==.',
Ii='Iidrizztdour:BAAALgADCgEJAQAAAA==.',
Il='Iluminaughti:BAAALgAECgQJBAAAAA==.',
Im='Immoc:BAACLgAFFH8HAAICAAQJFhl6DABRAQACAAQJFhl6DABRAQAuAAQKfyMAAwIACAmWHikhAIoCAAIACAmWHikhAIoCABMAAQnhC9MaACMAAAAA.',
In='Indy:BAABLgAECn8eAAIcAAcJxBKwFgBWAQAcAAcJxBKwFgBWAQAAAA==.Infidius:BAAALgADCggJEAAAAA==.Interés:BAAALgADCgQJBAAAAA==.',
Io='Iownyourcow:BAAALgAECgIJAgAAAA==.',
Ir='Iroha:BAAALgADCgYJBgAAAA==.Ironstag:BAAALgADCgQJBAAAAA==.',
Is='Istandalone:BAACLgAFFH8NAAIBAAQJch0TFABfAQABAAQJch0TFABfAQAuAAQKfxkAAgEACAm9HykhALwCAAEACAm9HykhALwCAAAA.',
Ix='Ixioth:BAAALgAECgEJAQAAAA==.',
Ja='Jaglok:BAAALgADCgEJAQAAAA==.Jagons:BAAALgAECgYJDwAAAA==.Jahfar:BAAALgAECgYJBwAAAA==.Jaken:BAAALgAECgEJAQAAAA==.Janara:BAAALgAECgUJCgAAAA==.',
Je='Jehtadin:BAAALgAECgQJBAABLgAECggJHAAXAJEcAA==.Jehthero:BAAALgAECgEJAQABLgAECggJHAAXAJEcAA==.Jehtshot:BAABLgAECn8cAAMXAAgJkRxQBQCoAQAXAAgJkRxQBQCoAQAFAAMJ3hxciADPAAAAAA==.Jehtword:BAAALgAECgMJAwABLgAECggJHAAXAJEcAA==.Jemjemner:BAAALgAECgEJAQAAAA==.Jesy:BAAALgAECgQJBAABLgAFFAQJBwAFAKoUAA==.',
Ji='Jimvisible:BAABLgAECn8UAAMdAAYJ8iTXEQBWAQAdAAUJvyTXEQBWAQAeAAEJviUSDwBwAAAAAA==.',
Jo='Joan:BAAALgAECgIJAgABLgAECgkJJQAHACkgAA==.Johadro:BAAALgADCgEJAQAAAA==.',
Jr='Jr:BAAALgAECgMJBAAAAA==.',
Ju='Judgejobrown:BAAALgAECgcJCgAAAA==.Judgenawt:BAABLgAECn8dAAIIAAgJThc7GgDtAQAIAAgJThc7GgDtAQAAAA==.Junon:BAAALgAECgMJAwAAAA==.',
Ka='Kain:BAABLgAECn8UAAIKAAYJawzjSAAWAQAKAAYJawzjSAAWAQAAAA==.Kaiá:BAAALgADCgUJBQAAAA==.Kalegard:BAAALgADCgcJDgAAAA==.Kalerah:BAAALgADCgYJBgAAAA==.Kalis:BAABLgAECn8VAAIHAAYJMhNrUQA+AQAHAAYJMhNrUQA+AQAAAA==.Kallum:BAAALgAECgYJBwAAAA==.Kaltak:BAAALgAECgIJAgAAAA==.Kalvynx:BAABLgAECn8hAAIcAAgJAxa4DADbAQAcAAgJAxa4DADbAQAAAA==.Karasu:BAAALgAECgMJAwAAAA==.Karn:BAABLgAECn8hAAIIAAkJMRe3EAA3AgAIAAkJMRe3EAA3AgAAAA==.Karti:BAAALgADCgkJFgAAAA==.Karzdormi:BAEALgAECgcJDAAAAA==.Kathell:BAAALgAECgIJBAABLgAFFAQJBwAFAKoUAA==.Kayllynt:BAAALgADCggJDgABLgAECgcJGgAQAMgTAA==.Kayyllynt:BAABLgAECn8aAAIQAAcJyBNOHQCWAQAQAAcJyBNOHQCWAQAAAA==.',
Ke='Kegeraetor:BAACLgAFFH8HAAIfAAQJDA98DQAnAQAfAAQJDA98DQAnAQAuAAQKfyUAAh8ACAlHHmYaADECAB8ACAlHHmYaADECAAAA.Keinthdra:BAACLgAFFH8FAAMYAAIJsA76EwBTAAAYAAEJgRv6EwBTAAABAAEJ3wF4WwBFAAAuAAQKfysAAxgACQl0Gc4MAEICABgACAkCGs4MAEICAAEABQlQDTynADMBAAAA.Kelein:BAAALgAECgEJAQABLgAECgQJBAAGAAAAAA==.Keliste:BAAALgAECgUJCQAAAA==.Kema:BAAALgAECgcJDgAAAA==.Kennaea:BAAALgAECgIJAgABLgAFFAQJCAAHAGARAA==.Kervana:BAAALgAECgMJBAABLgAFFAQJDQAbALsWAA==.',
Kh='Khrysais:BAAALgADCgMJAwAAAA==.',
Ki='Killigula:BAABLgAECn8fAAIMAAYJXhguFQCKAQAMAAYJXhguFQCKAQAAAA==.Kinuye:BAAALgADCggJEwAAAA==.Kishara:BAAALgAECgMJAwABLgAFFAQJBwAFAKoUAA==.',
Kl='Klondor:BAABLgAECn8gAAQgAAcJBAtcEgBBAQAgAAcJ8glcEgBBAQAFAAYJHAnxRwD6AAAXAAIJxwFofwBIAAAAAA==.Klutch:BAAALgADCgUJCAAAAA==.',
Ko='Korash:BAAALgAECggJEQAAAA==.',
Kr='Kraio:BAAALgAECgYJCAAAAA==.Kraisa:BAAALgADCgQJBAAAAA==.Krak:BAAALgAECgEJAQAAAA==.Krakenbones:BAAALgAECgMJAwAAAA==.Krenolarian:BAAALgADCgUJBQAAAA==.Kronax:BAAALgADCgQJBAAAAA==.',
Kv='Kvoke:BAAALgAECgIJBQAAAA==.',
Ky='Kyranni:BAAALgAECgEJAgAAAA==.',
La='Lamora:BAAALgAECgYJDgAAAA==.Lampard:BAABLgAECn8XAAIMAAgJoRJZFwB3AQAMAAgJoRJZFwB3AQAAAA==.Laraj:BAAALgAECgYJEwAAAA==.Larissaqt:BAEBLgAECn8WAAIDAAgJ0howBAAOAgADAAgJ0howBAAOAgABLgAECgkJEwAGAAAAAA==.Latindk:BAAALgADCgMJAwAAAA==.Latinhunter:BAAALgAECgMJAwAAAA==.Latinmonk:BAAALgAECgQJBAAAAA==.Latinshamy:BAAALgAECgYJEwAAAA==.Lavande:BAAALgAECgQJCgAAAA==.',
Le='Leara:BAAALgAECgMJAwABLgAFFAQJBwAFAKoUAA==.Legomyagro:BAAALgAECggJEwAAAA==.Lehaya:BAAALgADCgcJBwAAAA==.Leiasolo:BAAALgADCgYJBwAAAA==.Leonaá:BAAALgAECgEJAQABLgAECgkJKwAOACYkAA==.',
Li='Lilbessy:BAAALgAECgUJDQAAAA==.Lishaliel:BAAALgADCgcJBwABLgAFFAQJBwAFAKoUAA==.Lizzia:BAAALgADCgQJBAAAAA==.',
Lo='Loopysoup:BAAALgAECgEJAQABLgAECgcJDgAGAAAAAA==.Loopyswoop:BAAALgAECgcJDgAAAA==.Lothriel:BAABLgAECn8lAAIhAAgJuRe9AgDCAQAhAAgJuRe9AgDCAQAAAA==.',
Lu='Lucid:BAAALgAECgEJAQAAAA==.Ludioduo:BAAALgAECgUJBQAAAA==.Luedayen:BAABLgAECn8fAAIOAAgJQhzWDwBoAgAOAAgJQhzWDwBoAgAAAA==.Lukesunwalkr:BAAALgADCgQJCAAAAA==.Lunabellz:BAAALgAECgUJDQAAAA==.Lunavia:BAABLgAECn8VAAIFAAYJiB/cGQDGAQAFAAYJiB/cGQDGAQAAAA==.Luxembourge:BAAALgAECgUJDQAAAA==.',
Ma='Maalgus:BAAALgAECgYJCwAAAA==.Mad:BAAALgAECgIJAwAAAA==.Magivyne:BAAALgAECgEJAQAAAA==.Mahota:BAAALgADCggJDwAAAA==.Makennah:BAAALgADCgcJBwAAAA==.Maladash:BAABLgAECn8eAAQCAAgJUBd+NAAnAgACAAgJUBd+NAAnAgATAAMJYgcRFABYAAAPAAEJAgkVdAAxAAAAAA==.Malephar:BAAALgADCgMJAwAAAA==.Manachi:BAAALgAECgIJAgAAAA==.Margoul:BAAALgAECgEJAQAAAA==.Massfootmen:BAAALgADCgUJBQAAAA==.Matiowen:BAAALgADCgMJAwAAAA==.Mauie:BAAALgADCgEJAQAAAA==.Mayyhem:BAACLgAFFH8VAAIUAAUJeBnqBACgAQAUAAUJeBnqBACgAQAuAAQKfyUAAxQACQlGInsBAG8DABQACQlGInsBAG8DABYAAgneGeEvAJgAAAAA.Mazrethil:BAAALgADCgEJAQAAAA==.',
Mc='Mcallister:BAABLgAECn8gAAIQAAYJMRvcNgDMAQAQAAYJMRvcNgDMAQABLgADCgUJCAAGAAAAAA==.Mcjudgin:BAABLgAECn8ZAAQDAAgJZiXeAABnAwADAAgJZiXeAABnAwAJAAIJXRgqOgCJAAAIAAEJCh1WLAFIAAAAAA==.Mcsquid:BAAALgAECgEJAQAAAA==.',
Md='Mdrakeyd:BAAALgAECgYJEgAAAA==.',
Me='Meatbubble:BAAALgADCgkJFAAAAA==.Mephisston:BAAALgADCgIJAgAAAA==.Mesasneaky:BAAALgAECgUJBQAAAA==.',
Mi='Mimi:BAAALgAECgMJAwAAAA==.Mimiker:BAABLgAECn8hAAQVAAgJahx0DQCeAgAVAAgJahx0DQCeAgAWAAcJgRZpEgC6AQAUAAEJQwGlSQAvAAAAAA==.Minime:BAAALgAECgcJDAABLgAFFAYJFgAFAKocAA==.Minininja:BAAALgADCgcJDAABLgAECgQJDwAGAAAAAA==.Miniobi:BAAALgAECgEJAQAAAA==.Mirabella:BAAALgAECgQJBwAAAA==.Mistdemeanor:BAAALgAECgEJAgAAAA==.Mizahella:BAAALgAECgIJAwAAAA==.',
Mo='Mokei:BAAALgAECgQJBAAAAA==.Mokushi:BAAALgAECgYJDQAAAA==.Mollie:BAAALgADCgcJBwABLgADCgkJFAAGAAAAAA==.Monkgruff:BAAALgAECgUJCQAAAA==.Monkèy:BAAALgADCgUJBQAAAA==.Moonsilver:BAAALgAECgQJBwAAAA==.Moriko:BAABLgAECn8nAAIFAAgJ6xsBFgCIAgAFAAgJ6xsBFgCIAgAAAA==.Mornak:BAAALgAECgkJCAAAAA==.',
Mu='Muertomarrow:BAAALgAECgYJDQAAAA==.Mulroth:BAAALgAECgMJAwAAAA==.Murdermitten:BAAALgAECgEJAgABLgAECgEJAgAGAAAAAA==.Murloc:BAAALgAECgYJCgAAAA==.Musasa:BAABLgAECn8gAAIQAAgJ5xiuIAA+AgAQAAgJ5xiuIAA+AgAAAA==.Mustardseed:BAABLgAECn8jAAIKAAgJKQkpLgB0AQAKAAgJKQkpLgB0AQAAAA==.Muxaro:BAAALgADCgkJEwAAAA==.',
['Mí']='Mísery:BAAALgAECgYJDQAAAA==.',
Na='Naked:BAAALgAECgIJAwAAAA==.Nalibeefcake:BAAALgADCgcJDQAAAA==.Narkoleptick:BAAALgAECgYJCQAAAA==.Nasrith:BAABLgAECn8pAAIIAAkJdxvsBgCsAgAIAAkJdxvsBgCsAgAAAA==.Nastro:BAAALgAECgIJAwAAAA==.Nawtishot:BAAALgADCgEJAQAAAA==.Nazanath:BAAALgAECgIJAgAAAA==.',
Ne='Neeb:BAABLgAECn8XAAIDAAgJnBSvCACEAQADAAgJnBSvCACEAQAAAA==.Neeber:BAAALgAECgUJCAAAAA==.Nekk:BAABLgAECn8VAAISAAYJvBSZDQBFAQASAAYJvBSZDQBFAQAAAA==.',
Ni='Niamyau:BAAALgADCgMJAwAAAA==.Nitebrite:BAABLgAECn8VAAIOAAYJYw+FGgAzAQAOAAYJYw+FGgAzAQAAAA==.',
No='Noatak:BAAALgAECgEJAgAAAA==.Nohozis:BAAALgADCgQJBAAAAA==.Noimia:BAABLgAECn8rAAIcAAgJWB1WBQB8AgAcAAgJWB1WBQB8AgAAAA==.Normanosborn:BAAALgAECgQJCgAAAA==.',
Ny='Nyquiil:BAAALgADCgkJCQAAAA==.Nyssil:BAAALgADCgcJCwAAAA==.',
['Né']='Nésa:BAAALgADCgYJBgAAAA==.',
['Nï']='Nïssan:BAAALgAECgYJBgAAAA==.',
Ob='Obscûr:BAAALgAECgQJCgAAAA==.',
Oc='Ochtli:BAAALgADCgUJBQAAAA==.',
Od='Oden:BAAALgAECgQJCQAAAA==.',
Og='Oggy:BAAALgAECgIJAgAAAA==.',
Ok='Oksanabaiul:BAAALgAECgUJDwABLgAFFAQJCAAKAG8YAA==.',
Ol='Oldcode:BAAALgAECgUJCgAAAA==.Oleyander:BAAALgAECgIJAwAAAA==.Olskigather:BAAALgADCgMJAwAAAA==.Olskimonk:BAAALgAECgIJAgAAAA==.',
Or='Oronin:BAAALgADCgkJHwAAAA==.',
Os='Osanyin:BAAALgAECgcJDgAAAA==.',
Ot='Otsuka:BAAALgADCgEJAQAAAA==.',
Pa='Pacoesfu:BAAALgADCgUJBgAAAA==.Padray:BAACLgAFFH8HAAIiAAMJ7waqDgDZAAAiAAMJ7waqDgDZAAAuAAQKfy4AAiIACAlhGkIJAPABACIACAlhGkIJAPABAAAA.Paecos:BAAALgADCgYJDQAAAA==.Palize:BAAALgADCgYJBgABLgAECgcJCwAGAAAAAA==.Panhia:BAAALgAECgQJDwAAAA==.Parliament:BAAALgAECgYJCwAAAA==.',
Pe='Pekoyami:BAAALgADCgUJBQAAAA==.Pen:BAABLgAECn8XAAIRAAcJwA5oHQARAQARAAcJwA5oHQARAQAAAA==.Pepenlock:BAAALgAECgQJBQAAAA==.Pepperbottom:BAABLgAECn8UAAMLAAcJ9xtCDwDYAQALAAcJ9xtCDwDYAQAKAAIJYwPwrAA5AAAAAA==.',
Pf='Pfft:BAAALgADCgkJDAABLgAECgEJAQAGAAAAAA==.',
Ph='Phantasmshot:BAABLgAECn8eAAIFAAYJxQtRRgD/AAAFAAYJxQtRRgD/AAAAAA==.Phoebere:BAAALgAECgIJAwAAAA==.Phung:BAAALgAECggJDAAAAA==.Phungi:BAAALgAECgYJDAAAAA==.',
Po='Polymnia:BAAALgAECgMJBAAAAA==.Pomelo:BAAALgAECgIJBQAAAA==.Popeums:BAABLgAECn8VAAIbAAYJ9QHQIgC9AAAbAAYJ9QHQIgC9AAAAAA==.Poplock:BAAALgADCgYJBgAAAA==.Poppiqt:BAAALgAECgYJDwAAAA==.Powlie:BAAALgADCgkJFQAAAA==.Poyoh:BAABLgAECn8pAAIQAAkJSBnuBwCPAgAQAAkJSBnuBwCPAgAAAA==.',
Pr='Pravoce:BAAALgAECgQJBAAAAA==.Prolifichd:BAAALgAECgEJAQABLgAECgEJAgAGAAAAAA==.Prufrock:BAAALgADCgYJBgAAAA==.',
['Pí']='Pínt:BAABLgAECn8VAAMgAAYJQSAMDgB9AQAgAAYJtB4MDgB9AQAFAAMJtRw9XwCsAAAAAA==.',
Qu='Quelissa:BAAALgADCgkJCQABLgADCgkJFgAGAAAAAA==.',
Ra='Radjason:BAAALgADCggJCQAAAA==.Raeagald:BAAALgAECgIJBAABLgAFFAQJBwAfAAwPAA==.Raelyni:BAABLgAECn8pAAIOAAkJRxppAwCuAgAOAAkJRxppAwCuAgAAAA==.Rageroyal:BAAALgADCgEJAQAAAA==.Rakkah:BAABLgAECn8XAAMFAAYJHA5dQgANAQAXAAYJaQk1TgAXAQAFAAYJiwpdQgANAQAAAA==.Rakkuh:BAAALgAECgQJBAAAAA==.Ramjam:BAAALgADCgYJCQAAAA==.Rangwashu:BAAALgADCgIJAgABLgAECgYJEQAGAAAAAA==.Raveniss:BAAALgAECgUJDgAAAA==.Rawrie:BAAALgAECgcJEwAAAA==.Raygun:BAAALgAECgYJDwABLgADCgUJCAAGAAAAAA==.Rayzorevoker:BAAALgADCgcJDQAAAA==.Raziell:BAAALgADCgMJAwAAAA==.',
Re='Redhilda:BAAALgAECgcJEAAAAA==.Redmayhem:BAAALgADCgYJBgAAAA==.Remygos:BAAALgADCgEJAQAAAA==.',
Rh='Rhymu:BAAALgADCgMJAwABLgAECgIJAwAGAAAAAA==.',
Ri='Rissaria:BAAALgAECgIJAgAAAA==.',
Ro='Roshelle:BAAALgAECgIJAgAAAA==.Rotation:BAAALgAECgQJBAAAAA==.Rotblade:BAABLgAECn8XAAIjAAgJ0hZfAwCAAQAjAAgJ0hZfAwCAAQAAAA==.',
Ru='Rudewenn:BAAALgAECgMJAwAAAA==.Runandhide:BAABLgAECn8VAAIHAAYJmhDPuQBuAQAHAAYJmhDPuQBuAQAAAA==.',
Ry='Ryllativity:BAAALgADCgEJAQAAAA==.',
['Rø']='Røøtsftw:BAAALgAECgYJBgAAAA==.',
Sa='Sadsnap:BAABLgAECn8YAAIkAAcJxyBDCQBFAgAkAAcJxyBDCQBFAgAAAA==.Salamender:BAABLgAECn8YAAIUAAgJnxJFFQD1AQAUAAgJnxJFFQD1AQAAAA==.Sargothys:BAAALgAECgIJAgAAAA==.Sariais:BAAALgAECgEJAQAAAA==.Sassymoo:BAABLgAECn8YAAMQAAcJXxwkDABHAgAQAAcJXxwkDABHAgAEAAEJjwS+OgARAAABLgAFFAQJCQAZAMsOAA==.Sathenoth:BAAALgADCggJCAAAAA==.Savagejoker:BAAALgAECgEJAQABLgAECggJIQAlAL4iAA==.Sañtoro:BAAALgAECgQJBgAAAA==.',
Sc='Scalesboi:BAAALgADCgMJAwAAAA==.Scipione:BAAALgAECgUJCgAAAA==.Scy:BAAALgAECgUJCwAAAA==.',
Se='Seddona:BAAALgADCgkJCQAAAA==.Seithe:BAAALgADCgkJCQAAAA==.Seluun:BAABLgAECn8YAAIHAAUJrxP+YAAaAQAHAAUJrxP+YAAaAQAAAA==.Semandemon:BAAALgADCgEJAQAAAA==.Seraphae:BAAALgAECgUJCQAAAA==.',
Sh='Shadowmorn:BAABLgAECn8dAAImAAgJJAMmKADnAAAmAAgJJAMmKADnAAAAAA==.Shalako:BAAALgADCgUJBwAAAA==.Shambali:BAAALgAECgcJBwAAAA==.Shamnistic:BAABLgAECn8gAAIkAAgJiCB0AQCTAgAkAAgJiCB0AQCTAgAAAA==.Shandro:BAABLgAECn8oAAIHAAkJZAq7KADCAQAHAAkJZAq7KADCAQAAAA==.Shaniallon:BAABLgAECn8bAAIFAAgJyAmRJQCDAQAFAAgJyAmRJQCDAQAAAA==.Shara:BAAALgADCgMJBgAAAA==.Sharana:BAAALgADCgUJBQAAAA==.Shaunï:BAAALgADCgkJEgAAAA==.Shieldman:BAAALgADCgMJAwAAAA==.Shiftylock:BAABLgAECn8XAAMEAAYJORtGCABdAQAEAAYJORtGCABdAQAaAAMJYRYBIgDKAAAAAA==.Showong:BAAALgAECgEJAQAAAA==.',
Si='Silentaska:BAABLgAECn8UAAIVAAYJNBN2KAB6AQAVAAYJNBN2KAB6AQAAAA==.Silentbruce:BAAALgAECgYJBwAAAA==.Silentchill:BAABLgAECn8kAAMRAAgJrB0JCwDdAQARAAgJrB0JCwDdAQAQAAEJBQLH5AAgAAAAAA==.Silius:BAAALgAECgMJBAAAAA==.Simoncrunch:BAAALgAECgEJBAAAAA==.Sin:BAAALgAECgEJAQABLgAECgEJAgAGAAAAAA==.Sinomen:BAAALgAECgYJDAABLgAECgcJHwAnANMgAA==.Sinzilla:BAAALgAECgYJDQAAAA==.Sizzen:BAAALgADCgkJCQAAAA==.',
Sk='Skunkdrunk:BAAALgADCgYJBwAAAA==.Skyblue:BAAALgAECgUJCAAAAA==.',
Sm='Smokebull:BAABLgAECn8WAAIMAAcJ8go2HgBAAQAMAAcJ8go2HgBAAQAAAA==.',
Sn='Sneeble:BAAALgADCgkJCQAAAA==.Snoopshaman:BAAALgAECgEJAQABLgAECggJGQADAGYlAA==.Snowcake:BAAALgAECgEJBQAAAA==.',
So='Sofiavers:BAAALgAECgQJBAAAAA==.Solarhoof:BAAALgADCgEJAQAAAA==.Sonarak:BAAALgAECgEJAQABLgAECggJGQADAGYlAA==.Sornafayne:BAAALgADCgkJEgAAAA==.Sorrengail:BAAALgAECgYJEAAAAA==.',
Sp='Spareme:BAAALgADCgcJEgABLgAECgMJAwAGAAAAAA==.Specialkidd:BAAALgAECgYJBgAAAA==.Springrollz:BAAALgADCgEJAgABLgAFFAYJFgAFAKocAA==.Spy:BAABLgAECn8lAAIFAAgJWBseGwBkAgAFAAgJWBseGwBkAgAAAA==.',
Sr='Sravoz:BAAALgAECgIJAgAAAA==.',
St='Stabbitha:BAAALgADCgkJHAAAAA==.Stampa:BAAALgAECgQJBQAAAA==.Starrie:BAABLgAECn8cAAIZAAcJkRNbHwBpAQAZAAcJkRNbHwBpAQAAAA==.Steaknshake:BAAALgAECgQJBAAAAA==.Steelhoof:BAABLgAECn8nAAIXAAgJUwrmBwBhAQAXAAgJUwrmBwBhAQAAAA==.Steil:BAAALgADCgcJDQAAAA==.Steponmyface:BAABLgAECn8ZAAIBAAcJjB/LEwAbAgABAAcJjB/LEwAbAgAAAA==.Stewie:BAAALgADCgcJCgABLgADCgkJFAAGAAAAAA==.Stonesoul:BAAALgAECgkJDAAAAA==.Stories:BAABLgAECn8VAAIHAAYJzxhUXgAgAQAHAAYJzxhUXgAgAQAAAA==.Storm:BAEALgAECgMJAwABLgAFFAQJBwABANgLAA==.Stormfury:BAAALgAECgEJAgAAAA==.Strucker:BAAALgADCgcJCwABLgAECgkJKQAfAK0eAA==.Struckerz:BAAALgADCgkJEAABLgAECgkJKQAfAK0eAA==.Struckerzz:BAAALgAECgMJAwAAAA==.Struckrucker:BAABLgAECn8pAAIfAAkJrR5lAgC7AgAfAAkJrR5lAgC7AgAAAA==.',
Su='Sudimmoc:BAAALgAECgIJAgAAAA==.Sugarbear:BAAALgADCgUJBQAAAA==.Sunchips:BAAALgAECggJCQAAAA==.Sushie:BAAALgADCgMJAwABLgAFFAQJDQAJAMQXAA==.',
Sv='Svikja:BAAALgAECgMJAwAAAA==.',
Sw='Swipe:BAAALgAECgEJAQAAAA==.',
Sy='Synn:BAAALgADCgkJEgAAAA==.Syvina:BAAALgAECgQJCQAAAA==.',
Ta='Tabby:BAAALgAECgIJAwAAAA==.Taconight:BAAALgAECgYJEAAAAA==.Tacosaladin:BAAALgADCggJCAAAAA==.Tag:BAAALgAECgYJCAAAAA==.Takyon:BAAALgADCgYJBgABLgAECggJFgABALcjAA==.Tallynz:BAAALgAECgYJDQAAAA==.Tankornot:BAAALgAECgQJDAAAAA==.Tarasque:BAAALgADCgMJAwABLgAECgEJBQAGAAAAAA==.Tarlgreyhair:BAAALgADCgkJKAAAAA==.Tarnished:BAAALgAECgYJDAAAAA==.Tarria:BAAALgAECgUJCgAAAA==.Tateerfel:BAAALgAECgUJDwAAAA==.Tateertot:BAAALgADCgkJEgABLgAECgUJDwAGAAAAAA==.Tawneestone:BAABLgAECn8nAAISAAgJFyODAQC7AgASAAgJFyODAQC7AgAAAA==.',
Te='Teedizzle:BAAALgAECgMJAwAAAA==.Teek:BAABLgAECn8YAAMnAAYJvAQYFQDfAAAnAAYJnAIYFQDfAAAKAAYJvASwXQDaAAAAAA==.Telandaraa:BAABLgAECn8rAAMOAAkJJiS6AQBdAwAOAAkJJiS6AQBdAwAbAAMJFQn4RACRAAAAAA==.Telrae:BAABLgAECn8aAAIKAAcJkh2RIgCoAQAKAAcJkh2RIgCoAQAAAA==.',
Th='Theb:BAAALgAECgYJCAAAAA==.Thederpb:BAAALgAECggJCAAAAA==.Thejuice:BAAALgADCgcJDwAAAA==.Theldara:BAACLgAFFH8HAAIFAAQJqhSFCwBWAQAFAAQJqhSFCwBWAQAuAAQKfyQAAwUACAmYHEIpABICAAUACAmYHEIpABICABcABgkTFv46AHMBAAAA.Themock:BAAALgAECgQJCQAAAA==.Theresjohnny:BAAALgADCgkJGwAAAA==.Theshift:BAABLgAECn8gAAIbAAgJ8hGUGADXAQAbAAgJ8hGUGADXAQAAAA==.Thesixtyone:BAAALgADCgcJBwAAAA==.Thisisjustin:BAABLgAECn8aAAIoAAcJNhouAwDwAQAoAAcJNhouAwDwAQAAAA==.Thoreen:BAAALgAECgIJAwAAAA==.Thotsnprayer:BAAALgADCgMJBAAAAA==.Thraiel:BAAALgADCgQJBAABLgAECgUJDQAGAAAAAA==.Thrish:BAACLgAFFH8FAAIFAAMJxQxTHADyAAAFAAMJxQxTHADyAAAuAAQKfykABAUACAm7GfEcAFgCAAUACAm7GfEcAFgCACAABAlBDH8dALwAABcAAQkFAneYAB4AAAAA.Throom:BAAALgADCgIJAgAAAA==.Thuggies:BAAALgAECgUJCAAAAA==.Thunderfist:BAAALgADCggJDgABLgAECggJHgACAFAXAA==.',
Ti='Tizzlerizzle:BAAALgADCgkJFgAAAA==.',
To='Tomacco:BAAALgADCggJEgAAAA==.Toreto:BAAALgADCgUJBwAAAA==.Toshi:BAAALgAECgMJAwAAAA==.Totemiclord:BAAALgAECggJCgAAAA==.',
Ts='Tsukiyami:BAAALgAECgUJDwAAAA==.',
Tw='Twixaldo:BAAALgADCgkJEQABLgAECgcJGwAIAFogAA==.',
Ty='Ty:BAAALgADCgEJAQAAAA==.Tylus:BAAALgADCgcJCgAAAA==.',
Ub='Ubpriest:BAAALgADCgkJDQAAAA==.',
Up='Upinya:BAABLgAECn8YAAMLAAkJSwq1BgBMAQALAAkJSwq1BgBMAQAKAAEJ+QCUMgEcAAAAAA==.',
Uz='Uzumaki:BAAALgAECgQJBAAAAA==.',
Va='Vadderung:BAABLgAECn8aAAICAAgJNhyYKgBWAgACAAgJNhyYKgBWAgAAAA==.Valera:BAAALgAECgYJCwABLgAECggJKgANAFAlAA==.Valkilmer:BAAALgADCgEJAQAAAA==.Vallasha:BAABLgAECn8UAAInAAYJCA/6DABmAQAnAAYJCA/6DABmAQAAAA==.Valoth:BAAALgADCgEJAQAAAA==.Valtures:BAAALgAECgMJBgAAAA==.Vampyre:BAABLgAECn8WAAIFAAYJ1R4lIACgAQAFAAYJ1R4lIACgAQAAAA==.Vayne:BAACLgAFFH8JAAIMAAQJPhZ1BQBpAQAMAAQJPhZ1BQBpAQAuAAQKfykAAwwACAmbIsIRAMICAAwACAmbIsIRAMICAA0AAQksEwNBADYAAAAA.',
Ve='Vejek:BAAALgAECgkJAgAAAA==.Veloistina:BAAALgADCgYJCgABLgAECgcJGwAIAFogAA==.Veloria:BAAALgADCgQJBQABLgAECgEJAQAGAAAAAA==.Venator:BAAALgADCgQJBAAAAA==.Vezzini:BAAALgADCgcJEAAAAA==.',
Vh='Vh:BAAALgAECgQJCAAAAA==.',
Vi='Videlle:BAAALgADCgMJAwAAAA==.Vieoree:BAAALgAECgMJBAAAAA==.Vigoh:BAAALgADCgcJBwABLgAECgYJEAAGAAAAAA==.Vinge:BAECLgAFFH8HAAIBAAQJ2AslJgAkAQABAAQJ2AslJgAkAQAuAAQKfyYAAgEACAmyH+stAIECAAEACAmyH+stAIECAAAA.Vinter:BAAALgADCgkJEwAAAA==.Violetferal:BAAALgADCggJDgAAAA==.Violetrain:BAABLgAECn8dAAIIAAcJpgOOegC4AAAIAAcJpgOOegC4AAAAAA==.Viralswine:BAAALgAECgcJCgAAAA==.Visarys:BAAALgAECgQJBAAAAA==.Vixipixi:BAAALgADCgYJEgAAAA==.',
Vo='Vollibear:BAAALgAECgMJAwAAAA==.Voltaic:BAABLgAECn8WAAIZAAcJKCAiEgCFAgAZAAcJKCAiEgCFAgABLgAECgcJJwACAMkjAA==.Vothdomosh:BAAALgADCgcJEgABLgAECgcJFwAJADYiAA==.',
Vy='Vyrista:BAAALgAECgQJCgAAAA==.Vyrzeth:BAAALgAECgIJAwAAAA==.Vyzualize:BAACLgAFFH8NAAIJAAUJKhOCBACYAQAJAAUJKhOCBACYAQAuAAQKfyAAAgkACQlgH6sHAPICAAkACQlgH6sHAPICAAAA.',
Wa='Wae:BAAALgAECgYJCwAAAA==.Waferblade:BAAALgADCgcJBwAAAA==.Waknipi:BAABLgAECn8WAAMIAAgJ5xjUIADFAQAIAAgJ5xjUIADFAQAJAAEJIQX3mwAtAAAAAA==.Wauwen:BAAALgADCgUJCAAAAA==.Wavecheck:BAAALgAECgMJBQAAAA==.Way:BAAALgAECgIJAgAAAA==.Waycaps:BAACLgAFFH8JAAITAAQJ9RupAABfAQATAAQJ9RupAABfAQAuAAQKfycAAhMACAlaItABAPgCABMACAlaItABAPgCAAAA.',
We='Wednesdáy:BAABLgAECn8WAAIMAAcJRBGHPwCmAQAMAAcJRBGHPwCmAQAAAA==.Werlock:BAAALgAECgcJCgABLgAECgkJFwAVAIgNAA==.Wetton:BAAALgADCgYJBgAAAA==.',
Wh='Wheresjohnny:BAABLgAECn8pAAIYAAkJYxn2AgAvAgAYAAkJYxn2AgAvAgAAAA==.',
Wi='Wiccked:BAABLgAECn8XAAInAAgJihG3BAArAgAnAAgJihG3BAArAgAAAA==.Windrange:BAACLgAFFH8IAAIHAAQJzwpHJABDAQAHAAQJzwpHJABDAQAuAAQKfyIAAgcACAmbHlArAMUCAAcACAmbHlArAMUCAAAA.Winterice:BAAALgAECgQJBQAAAA==.Wintérhoof:BAAALgADCgcJGAABLgAECgQJBQAGAAAAAA==.',
Wo='Wonderpally:BAAALgADCgkJCQAAAA==.Woodscale:BAAALgAECgIJAwAAAA==.Wovenbones:BAAALgAECgQJDAAAAA==.',
Wu='Wuggs:BAAALgAECgIJAgABLgAFFAQJCQAHAEQeAA==.Wumbo:BAAALgADCgYJDAAAAA==.',
Wy='Wyvarn:BAAALgAECgcJBwAAAA==.',
Xa='Xargothys:BAAALgAECgQJBwAAAA==.',
Xi='Xiisle:BAABLgAECn8VAAIIAAYJEyU8EwAgAgAIAAYJEyU8EwAgAgAAAA==.Xine:BAAALgADCgkJFAAAAA==.',
Ya='Yanya:BAAALgADCgkJFgAAAA==.',
Ye='Yergat:BAACLgAFFH8WAAQFAAYJqhxYEQAxAQAXAAYJKRcfDQBNAQAFAAMJyyBYEQAxAQAgAAMJ6hLxCQACAQAuAAQKfy8AAxcACQmIJOwBAJwDABcACQn1IuwBAJwDAAUAAwnwIldmADQBAAAA.',
Yu='Yupa:BAAALgAECgUJDQABLgAECggJJwAFAOsbAA==.',
Za='Zafira:BAACLgAFFH8JAAIZAAQJyw6NFADoAAAZAAQJyw6NFADoAAAuAAQKfyEAAxkACQm7Gl4RAIwCABkACQm7Gl4RAIwCACYAAwnmDOZxAHsAAAAA.Zainea:BAAALgADCgMJAwABLgAFFAQJCQAZAMsOAA==.Zarndarg:BAAALgAECgQJBAAAAA==.Zartuu:BAAALgAECgcJCQAAAA==.Zattani:BAAALgAECgQJBgAAAA==.',
Ze='Zeel:BAAALgAECgUJBQAAAA==.Zelblades:BAAALgAECgYJDQABLgAECggJIAAdAOMbAA==.Zelrex:BAABLgAECn8gAAMdAAgJ4xtxDwCtAgAdAAgJ4xtxDwCtAgAeAAEJphQhHQBCAAAAAA==.Zerat:BAAALgAECgMJAwAAAA==.Zerazer:BAABLgAFFH8FAAIWAAQJQyFWAACSAQAWAAQJQyFWAACSAQAAAA==.',
Zh='Zhuntyr:BAAALgAECgYJDQAAAA==.',
Zi='Ziggedion:BAAALgAECgMJAwAAAA==.Zindar:BAABLgAECn8VAAIVAAYJvh2mDAC+AQAVAAYJvh2mDAC+AQAAAA==.',
Zv='Zv:BAAALgADCgUJBQAAAA==.',
Zy='Zylos:BAAALgADCgYJBgAAAA==.Zynzz:BAAALgAECgMJBgAAAA==.',
['Zô']='Zômi:BAAALgAECgMJBQAAAA==.',
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
