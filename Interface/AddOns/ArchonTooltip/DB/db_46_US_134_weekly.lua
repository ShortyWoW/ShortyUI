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

local lookup = {'DemonHunter-Devourer','Hunter-BeastMastery','Unknown-Unknown','Mage-Frost','Paladin-Retribution','Warlock-Demonology','Warlock-Destruction','Warrior-Arms','DemonHunter-Havoc','Druid-Restoration','Druid-Balance','Warrior-Protection','Warrior-Fury','DeathKnight-Unholy','Paladin-Holy','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Hunter-Marksmanship','Druid-Feral','Monk-Mistweaver','Monk-Brewmaster','DeathKnight-Blood','Priest-Discipline','Hunter-Survival','Priest-Holy','DeathKnight-Frost','Paladin-Protection','Priest-Shadow','Shaman-Enhancement','Shaman-Restoration','Mage-Arcane','Shaman-Elemental','Mage-Fire','DemonHunter-Vengeance','Warlock-Affliction','Rogue-Subtlety','Rogue-Assassination',}
local provider = {region='US',realm='Kilrogg',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abartheris:BAAALgAECgUJEgAAAA==.',
Ac='Acanoffood:BAAALgAECgYJEAAAAA==.',
Ad='Adel:BAAALgAECgEJAQAAAA==.Ademai:BAAALgADCgIJAgAAAA==.Adeptus:BAAALgAECgYJDwAAAA==.',
Ae='Aemeath:BAABLgAECn8VAAIBAAcJJCA1OgALAgABAAcJJCA1OgALAgAAAA==.Aendres:BAAALgAECgQJBQAAAA==.',
Ag='Agriopas:BAAALgAECgUJEwABLgAECgYJFAACANAKAA==.',
Ah='Aharon:BAAALgADCgcJBwAAAA==.',
Ai='Aireas:BAAALgAECgEJAQAAAA==.Aizen:BAAALgADCgYJBgABLgAECgYJCAADAAAAAA==.',
Al='Alassomorph:BAAALgAECgQJBgAAAA==.Alazaie:BAAALgADCgMJAwAAAA==.Albus:BAABLgAECn8dAAIEAAkJNBwwGQAUAwAEAAkJNBwwGQAUAwAAAA==.Allayna:BAABLgAECn8gAAIFAAgJeyArBABgAgAFAAgJeyArBABgAgAAAA==.Almitvez:BAAALgADCgcJBwABLgAECgQJBQADAAAAAA==.Aloha:BAAALgAECggJDgAAAA==.Alysaliu:BAACLgAFFH8FAAIGAAMJFhjoDwD1AAAGAAMJFhjoDwD1AAAuAAQKfyUAAwYACAk/ID8aALcCAAYABwlHIz8aALcCAAcABAm3FXgrABIBAAAA.',
Am='Amisan:BAAALgADCgEJAQAAAA==.Amishpaladin:BAAALgAECggJEAAAAA==.Amishwarlock:BAAALgAECgYJCQABLgAECggJEAADAAAAAA==.Amonotep:BAAALgAECgMJAQAAAA==.Amorianar:BAAALgADCgMJAwABLgAECgYJCAADAAAAAA==.Amory:BAAALgADCgcJEAABLgADCgQJBAADAAAAAA==.',
An='Anchor:BAAALgAECgcJCwAAAA==.Andja:BAABLgAECn8jAAIIAAgJACVeAAC3AgAIAAgJACVeAAC3AgAAAA==.Andromedae:BAAALgAECgYJDgAAAA==.Anexa:BAAALgAECgQJBgAAAA==.Angela:BAAALgAECgEJAQAAAA==.Anurek:BAAALgADCgUJBgAAAA==.',
Ar='Argulas:BAAALgADCggJDwAAAA==.Ark:BAAALgAECgYJDgAAAA==.Arn:BAAALgAECgQJBQABLgAECgcJBwADAAAAAA==.Arthrex:BAAALgAECgMJBAAAAA==.Arthus:BAAALgAECgYJDAAAAA==.Arturias:BAAALgADCgcJEgABLgAECggJIgAJACIhAA==.',
As='Asmobob:BAAALgAECgYJDwAAAA==.',
Au='Augmentin:BAABLgAECn8XAAMKAAgJaRkBVQBUAQAKAAYJkBsBVQBUAQALAAgJSg/iCQBQAQAAAA==.Auntfranny:BAAALgADCgEJAQAAAA==.Autoshot:BAAALgADCgYJBwAAAA==.',
Av='Avina:BAAALgAECgEJAQAAAA==.Avrami:BAAALgADCgkJCgAAAA==.',
Aw='Aw:BAABLgAECn8XAAMGAAcJah06BwD+AQAGAAYJah06BwD+AQAHAAQJPhdxJAA3AQAAAA==.Awokenbigdam:BAAALgAECgEJAQAAAA==.',
Ba='Babycoffee:BAAALgADCgcJEgAAAA==.Bahamutz:BAAALgADCgUJBAAAAA==.Bahwee:BAAALgAECgYJDwAAAA==.Bangbangdou:BAAALgAECgYJDQAAAA==.Bastor:BAAALgADCgIJAgAAAA==.Bayle:BAAALgAECgQJCAAAAA==.',
Be='Bearnekkid:BAAALgADCgkJEQAAAA==.Beerthrowguy:BAAALgAECggJCAAAAA==.Bellaofroses:BAAALgADCgcJBwAAAA==.Bellatrix:BAAALgADCgYJBgAAAA==.Beneb:BAAALgAECgEJAQAAAA==.Benebeorn:BAABLgAECn8YAAIBAAgJTiGyGgCzAgABAAgJTiGyGgCzAgAAAA==.Benkinobi:BAAALgADCgIJAgAAAA==.',
Bh='Bhaer:BAAALgAECgEJAQAAAA==.',
Bi='Bichewich:BAAALgADCgYJBgAAAA==.Bigshot:BAAALgADCgYJBwAAAA==.Billyjoe:BAAALgAECgMJBAAAAA==.Binti:BAAALgADCgMJAwAAAA==.Bittronoxus:BAABLgAECn8UAAIEAAYJdw8PIgBKAQAEAAYJdw8PIgBKAQAAAA==.',
Bl='Blackryder:BAAALgAECgUJDgAAAA==.Bleys:BAAALgADCggJEwABLgAECggJIAAFAOMcAA==.',
Bo='Bobbysmerica:BAABLgAECn8ZAAMMAAcJSRhvEQDwAQAMAAcJSRhvEQDwAQAIAAEJ9At3QgA0AAAAAA==.Bobocanfly:BAAALgAECgYJDQAAAA==.Bodikhan:BAAALgAECgUJCgAAAA==.Bonezeh:BAAALgAECgMJAwAAAA==.',
Br='Braxte:BAABLgAECn8fAAMNAAgJlh7ZBADoAQANAAgJBx7ZBADoAQAIAAEJ5hxqEABVAAAAAA==.Briguydkguy:BAACLgAFFH8GAAIOAAMJmAgaLgDhAAAOAAMJmAgaLgDhAAAuAAQKfxYAAg4ACAlGFOlgANABAA4ACAlGFOlgANABAAAA.Britziola:BAAALgADCgYJCQABLgADCgQJBAADAAAAAA==.Brokenvoid:BAAALgAECgYJEwAAAA==.Brusalt:BAAALgADCggJCAAAAA==.Bryce:BAAALgAECgUJDQAAAA==.',
Bu='Buggies:BAACLgAFFH8FAAIEAAMJsBqCDwATAQAEAAMJsBqCDwATAQAuAAQKfyQAAgQACAkaJXUSADgDAAQACAkaJXUSADgDAAAA.Buggs:BAAALgAECgIJAgABLgAFFAMJBQAEALAaAA==.Buldozz:BAABLgAECn8fAAIPAAcJxBK9NQClAQAPAAcJxBK9NQClAQAAAA==.Bullit:BAAALgADCgUJBQABLgADCgkJEQADAAAAAA==.Burnination:BAABLgAECn8WAAIEAAYJtiReCAAiAgAEAAYJtiReCAAiAgAAAA==.Burnzie:BAAALgADCgEJAQAAAA==.Butterfayce:BAABLgAECn8gAAMPAAgJQxZyKQDlAQAPAAgJQxZyKQDlAQAFAAUJUQ9hOgCtAAAAAA==.',
By='Bycew:BAAALgAECgEJAwAAAA==.',
Ca='Cadastrasz:BAABLgAECn8nAAQQAAgJowoLHwCIAQAQAAgJowoLHwCIAQARAAYJbgfXOgAFAQASAAMJrAFVOQBOAAAAAA==.Cae:BAAALgADCgQJBAAAAA==.Cameocreme:BAAALgAECgEJAQAAAA==.Captfrost:BAAALgAECgEJAQAAAA==.Carsonkiller:BAAALgADCgEJAQABLgAECgcJEAADAAAAAA==.Cateurize:BAABLgAECn8WAAIRAAgJlw7GBQCjAQARAAgJlw7GBQCjAQAAAA==.',
Ce='Ceenit:BAABLgAECn8cAAIFAAgJZR0lJACXAgAFAAgJZR0lJACXAgAAAA==.Celalaliia:BAAALgADCgMJAwAAAA==.Celawyn:BAAALgAECgYJDAAAAA==.',
Ch='Chainedfire:BAAALgADCgkJFQAAAA==.Chasemon:BAAALgAECgYJCQAAAA==.Chaser:BAAALgADCgcJFQAAAA==.Chaøtical:BAAALgAECgQJBAAAAA==.Chicosan:BAAALgADCgQJBAAAAA==.Chrisolski:BAAALgADCgYJDAABLgAECgUJBQADAAAAAA==.',
Ci='Cirragos:BAAALgAECgMJBwAAAA==.',
Cl='Clamer:BAAALgADCgcJEAAAAA==.Clawdite:BAAALgADCgYJBgABLgAECgQJBQADAAAAAA==.Cleansinq:BAAALgAECgEJAQAAAA==.Cloudsmoker:BAAALgAECgcJDgAAAA==.',
Co='Corien:BAAALgAECgEJAQAAAA==.',
Cr='Crazegrippin:BAAALgAECgEJAgAAAA==.Crimsonmoon:BAABLgAECn8gAAITAAgJNw3fAgCWAQATAAgJNw3fAgCWAQAAAA==.Cryomara:BAAALgADCgYJCQAAAA==.',
Cu='Cueball:BAAALgADCgYJBgAAAA==.',
Cy='Cylasta:BAAALgADCgQJBgAAAA==.Cyndraexa:BAAALgAECgQJBQAAAA==.Cynia:BAAALgAECgIJAwAAAA==.Cynra:BAABLgAECn8bAAIKAAgJERpzAwBpAgAKAAgJERpzAwBpAgAAAA==.Cyrakos:BAAALgADCgEJAQAAAA==.',
['Cõ']='Cõwbell:BAAALgADCgEJAQAAAA==.',
Da='Dalize:BAAALgAECgcJCwAAAA==.Danarrath:BAAALgAECgYJDQAAAA==.Danger:BAAALgAECgQJBQAAAA==.Danklins:BAABLgAECn8fAAMRAAgJcRF+CABiAQARAAgJcRF+CABiAQASAAEJxQfyCQA1AAAAAA==.Dariabell:BAAALgADCggJCwAAAA==.Darkramone:BAAALgAECgEJAgAAAA==.Darthbane:BAAALgAECgMJAgAAAA==.Darthvada:BAAALgAECgQJCAAAAA==.',
De='Deadpoint:BAAALgAECgYJEgAAAA==.Deadski:BAAALgAECgQJBQAAAA==.Deathfrost:BAABLgAECn8ZAAIEAAgJ4RgRFwCMAQAEAAgJ4RgRFwCMAQAAAA==.Debz:BAAALgADCgkJCQAAAA==.Defeatzhealz:BAAALgAECgYJEwAAAA==.Defeatzhunt:BAABLgAECn8XAAMCAAgJCxnbHABZAgACAAgJCxnbHABZAgATAAEJAABZnAAJAAAAAA==.Deirdra:BAAALgADCgkJCQABLgAECggJIAAFAOMcAA==.Delarium:BAAALgADCgIJAgAAAA==.Demonaria:BAABLgAECn8iAAIJAAgJIiGgAACfAgAJAAgJIiGgAACfAgAAAA==.Denariah:BAAALgADCgcJBwAAAA==.Dendranaar:BAAALgAECgMJBAAAAA==.Dernen:BAAALgAECgYJCwABLgAECgYJDQADAAAAAA==.Derpnface:BAAALgAECgYJDwAAAA==.Desecration:BAABLgAECn8hAAIBAAcJKCOfBwD5AQABAAcJKCOfBwD5AQAAAA==.Devilhandler:BAAALgADCgEJAQAAAA==.Dezimorikko:BAAALgADCgcJBwAAAA==.',
Di='Dirgir:BAAALgAECgYJDgAAAA==.Distonia:BAAALgAECgYJDwAAAA==.',
Do='Dorothy:BAABLgAECn8WAAIOAAgJFxjGVQDwAQAOAAgJFxjGVQDwAQAAAA==.',
Dr='Dracheo:BAABLgAECn8lAAIEAAgJ5iDgLQC6AgAEAAgJ5iDgLQC6AgAAAA==.Dragonbrr:BAAALgAECgQJBgABLgAECgYJFgAPAAokAA==.Dragonwizard:BAABLgAECn8VAAIEAAYJzx+caAAFAgAEAAYJzx+caAAFAgAAAA==.Drakonna:BAAALgAECgEJAQAAAA==.Dranix:BAAALgAECgUJCwAAAA==.Dreygur:BAAALgAECgMJAwAAAA==.Droiden:BAAALgAECgQJBQAAAA==.Drotar:BAABLgAECn8UAAMLAAcJDArKTQDyAAALAAYJywrKTQDyAAAUAAUJ2gPxCQCJAAAAAA==.',
Du='Dumbdog:BAABLgAECn8qAAMKAAgJHyWHAwBaAwAKAAgJHyWHAwBaAwALAAYJmhMQPgA6AQABLgAFFAUJEAAQAMQVAA==.Dumichauch:BAABLgAECn8iAAIKAAgJeRvwFwB3AgAKAAgJeRvwFwB3AgAAAA==.Durin:BAAALgAECgYJDwAAAA==.',
['Dé']='Déâth:BAAALgADCgkJCwAAAA==.',
Ec='Echo:BAAALgAECgcJCAAAAA==.',
Eg='Eggars:BAAALgAECgYJCwAAAA==.',
Ek='Ekee:BAAALgAECgEJAQAAAA==.',
El='Elegance:BAAALgADCgIJAgAAAA==.Ellý:BAAALgADCgEJAQAAAA==.',
Em='Emberleaf:BAAALgADCgQJBAAAAA==.Emofriz:BAAALgAECgMJBAAAAA==.Emolate:BAAALgAECgcJBwABLgAFFAYJEAACALIbAA==.',
En='Enve:BAABLgAECn8gAAIBAAgJfyD4AgB7AgABAAgJfyD4AgB7AgAAAA==.',
Er='Erso:BAAALgADCgcJBwAAAA==.',
Ev='Evanorah:BAAALgAECgEJAQAAAA==.Eviltiger:BAABLgAECn8dAAITAAkJIxHlAQDQAQATAAkJIxHlAQDQAQAAAA==.',
Ew='Ewik:BAABLgAECn8XAAMQAAgJuhR3EgAYAgAQAAgJuhR3EgAYAgASAAMJEwu1BgB9AAAAAA==.',
Ex='Excalìbur:BAAALgAECgQJBAAAAA==.',
Fa='Faent:BAAALgAECgQJCQAAAA==.Falimonki:BAAALgADCgIJAgAAAA==.Falinora:BAACLgAFFH8FAAIPAAMJ7hDyBgDYAAAPAAMJ7hDyBgDYAAAuAAQKfyIAAw8ACAlkFqQiAAoCAA8ACAlkFqQiAAoCAAUABwlaDxGuACcBAAAA.Famous:BAAALgADCgkJCQAAAA==.Fantasticfox:BAABLgAECn8jAAMHAAgJlA1IMgDvAAAGAAYJcg7LfwBbAQAHAAQJSQpIMgDvAAAAAA==.',
Fe='Felixs:BAAALgAECgQJBQAAAA==.Fellhanded:BAAALgADCgcJBwAAAA==.Feloron:BAAALgAECgMJAwAAAA==.Feluria:BAAALgADCgYJBgAAAA==.Feodin:BAAALgAECgMJBQABLgAECggJHwABAK8cAA==.Feosdragon:BAAALgADCgYJBgAAAA==.Ferrovax:BAAALgADCgEJAQABLgAECggJGQABADYcAA==.',
Fi='Fitzchivalry:BAAALgAECgEJAQAAAA==.',
Fl='Fleethefield:BAAALgAECgQJBwAAAA==.Flowabridge:BAABLgAECn8VAAIEAAYJrQORAgH2AAAEAAYJrQORAgH2AAABLgAECgcJEQADAAAAAA==.',
Fo='Forcewild:BAAALgAECgYJDwAAAA==.',
Fr='Fragos:BAAALgAECgQJBAAAAA==.Friz:BAABLgAECn8bAAMHAAgJ8BlbCAA8AgAHAAcJ0RlbCAA8AgAGAAQJ9xqsngAbAQAAAA==.Frostychunks:BAAALgAECgcJEgAAAA==.',
Fu='Fuddrucker:BAAALgADCgcJCwAAAA==.Furflation:BAAALgAECgYJDwAAAA==.Furgam:BAAALgAECgEJAQAAAA==.Fury:BAAALgADCgYJCgABLgADCgkJEQADAAAAAA==.Fuzzychunks:BAAALgAECgQJBQABLgAECgcJEgADAAAAAA==.',
Ga='Gabapentin:BAAALgAECgQJBAAAAA==.Gaeren:BAAALgADCgcJEAAAAA==.Gannon:BAABLgAECn8ZAAIEAAgJhxpYCwD5AQAEAAgJhxpYCwD5AQAAAA==.Gano:BAEALgAECgIJBAABLgAECggJIgAOAMMcAA==.Garr:BAAALgAECgEJAQABLgAECgEJAQADAAAAAA==.Garuuk:BAAALgADCgEJAQAAAA==.Gazir:BAAALgAECgYJCAAAAA==.',
Ge='Geniús:BAAALgADCgYJBgAAAA==.Genji:BAAALgAECgQJCAAAAA==.',
Gi='Giliandra:BAAALgADCgUJCgAAAA==.',
Gl='Glitch:BAABLgAECn8VAAIMAAYJbgFMNgCVAAAMAAYJbgFMNgCVAAAAAA==.',
Gn='Gnxs:BAAALgADCgUJBQAAAA==.',
Go='Goonthar:BAACLgAFFH8FAAINAAMJ/QiDEwDlAAANAAMJ/QiDEwDlAAAuAAQKfxsAAg0ACAmkIQILAAQDAA0ACAmkIQILAAQDAAAA.Gorethak:BAAALgAECgQJBgAAAA==.',
Gr='Grobble:BAAALgADCgcJFQAAAA==.Grollgrr:BAAALgAECgQJBQAAAA==.Grompo:BAAALgADCgkJFwABLgAECgcJFwAGAGodAA==.Grompy:BAAALgADCgQJBAABLgAECgcJFwAGAGodAA==.Gruffbeard:BAAALgAECgIJAgABLgAECgUJBQADAAAAAA==.',
Gu='Gunghoiguana:BAAALgADCgkJCQAAAA==.',
Gy='Gyxx:BAABLgAFFH8FAAIPAAMJeBj7BQD5AAAPAAMJeBj7BQD5AAAAAA==.',
Ha='Haddice:BAAALgAECgQJCAAAAA==.Hafarti:BAAALgADCgUJBAAAAA==.Hairyteeth:BAAALgAECgQJCQAAAA==.Hajime:BAAALgAECgQJBAAAAA==.Hamburgers:BAAALgAECgEJAQAAAA==.Harriedotter:BAAALgADCgkJGgAAAA==.',
He='Heebiejeebie:BAABLgAECn8lAAMGAAgJDxjiLgBRAgAGAAgJDxjiLgBRAgAHAAIJaQt2VwBoAAAAAA==.Hellaeus:BAABLgAECn8YAAIFAAYJ+x2bTAD9AQAFAAYJ+x2bTAD9AQAAAA==.Hellsong:BAAALgAECgYJBgAAAA==.',
Hi='Hinatasan:BAAALgAECgEJAQAAAA==.Hisokä:BAABLgAECn8fAAIJAAgJwQ0RBgBcAQAJAAgJwQ0RBgBcAQAAAA==.',
Ho='Hoku:BAAALgAECgEJAQAAAA==.Holycreambar:BAABLgAECn8UAAIFAAYJ9yBeEQCYAQAFAAYJ9yBeEQCYAQAAAA==.Holyjuan:BAAALgADCgkJEgAAAA==.Hoofsbane:BAAALgADCgcJBwAAAA==.',
Hu='Huntingale:BAAALgADCgkJFgAAAA==.Huntinshift:BAAALgADCgkJGAAAAA==.Huwn:BAAALgADCgQJBAAAAA==.',
Hy='Hygelak:BAAALgAECgMJBgAAAA==.Hypaxia:BAAALgAECgMJBgABLgAECgYJEwADAAAAAA==.',
Ib='Ibpowerline:BAAALgADCgYJBgAAAA==.',
Ic='Icethorn:BAAALgAECgEJAQAAAA==.',
Ig='Iggysmalls:BAAALgAECgEJAQAAAA==.',
Ii='Iidrizztdour:BAAALgADCgEJAQAAAA==.',
Il='Iluminaughti:BAAALgAECgQJBAAAAA==.',
Im='Immoc:BAACLgAFFH8FAAIBAAMJ6BDxDQDsAAABAAMJ6BDxDQDsAAAuAAQKfyQAAgEACAkKHyIhAIoCAAEACAkKHyIhAIoCAAAA.',
In='Indy:BAABLgAECn8XAAIVAAcJsRGnJgB/AQAVAAcJsRGnJgB/AQAAAA==.Infidius:BAAALgADCggJEAAAAA==.Interés:BAAALgADCgQJBAAAAA==.',
Io='Iownyourcow:BAAALgAECgIJAgAAAA==.',
Ir='Iroha:BAAALgADCgYJBgAAAA==.Ironstag:BAAALgADCgQJBAAAAA==.',
Is='Istandalone:BAACLgAFFH8JAAIOAAQJMBc9BQBkAQAOAAQJMBc9BQBkAQAuAAQKfxkAAg4ACAm9HyYhALwCAA4ACAm9HyYhALwCAAAA.',
Ix='Ixioth:BAAALgAECgEJAQAAAA==.',
Ja='Jaglok:BAAALgADCgEJAQAAAA==.Jagons:BAAALgAECgYJCgAAAA==.Jahfar:BAAALgAECgEJAQAAAA==.Jaken:BAAALgADCgEJAgAAAA==.Janara:BAAALgAECgUJCgAAAA==.',
Je='Jehtadin:BAAALgAECgEJAQABLgAECggJHAATAJEcAA==.Jehtshot:BAABLgAECn8cAAMTAAgJkRxNAgC2AQATAAgJkRxNAgC2AQACAAMJ3hxViADPAAAAAA==.Jehtword:BAAALgAECgMJAwABLgAECggJHAATAJEcAA==.Jemjemner:BAAALgAECgEJAQAAAA==.Jesy:BAAALgAECgQJBAABLgAECggJIAACAGMcAA==.',
Ji='Jimvisible:BAAALgAFFAEJAQAAAA==.',
Jo='Joan:BAAALgAECgIJAgABLgAECgkJHQAEADQcAA==.Johadro:BAAALgADCgEJAQAAAA==.',
Jr='Jr:BAAALgAECgMJBAAAAA==.',
Ju='Judgejobrown:BAAALgAECgYJCAAAAA==.Judgenawt:BAABLgAECn8ZAAIFAAgJwBWsDADKAQAFAAgJwBWsDADKAQAAAA==.Junon:BAAALgADCgkJFgAAAA==.',
Ka='Kain:BAAALgAECgYJDgAAAA==.Kaiá:BAAALgADCgUJBQAAAA==.Kalegard:BAAALgADCgcJDgAAAA==.Kalerah:BAAALgADCgYJBgAAAA==.Kalis:BAAALgAECgYJDwAAAA==.Kallum:BAAALgAECgMJBAAAAA==.Kaltak:BAAALgAECgEJAQAAAA==.Kalvynx:BAABLgAECn8ZAAIVAAgJcRL9HgC+AQAVAAgJcRL9HgC+AQAAAA==.Karasu:BAAALgAECgMJAwAAAA==.Karn:BAABLgAECn8gAAIFAAgJchmgCAAAAgAFAAgJchmgCAAAAgAAAA==.Karti:BAAALgADCgkJFgAAAA==.Karzdormi:BAEALgAECgcJBwAAAA==.Kathell:BAAALgAECgIJBAABLgAECggJIAACAGMcAA==.Kayllynt:BAAALgADCggJCgAAAA==.Kayyllynt:BAABLgAECn8UAAIKAAYJMBb4EABMAQAKAAYJMBb4EABMAQAAAA==.',
Ke='Kegeraetor:BAACLgAFFH8FAAIWAAMJTwqpCADcAAAWAAMJTwqpCADcAAAuAAQKfyUAAhYACAlHHmMaADECABYACAlHHmMaADECAAAA.Keinthdra:BAABLgAECn8hAAMXAAkJoRjNDABDAgAXAAgJERnNDABDAgAOAAUJUA05pwAzAQAAAA==.Kelein:BAAALgAECgEJAQABLgAECgQJBAADAAAAAA==.Keliste:BAAALgAECgQJBAAAAA==.Kema:BAAALgAECgcJDgAAAA==.Kennaea:BAAALgAECgIJAgABLgAECggJJQAEAOYgAA==.Kervana:BAAALgAECgMJBAABLgAFFAQJCQAYALsWAA==.',
Kh='Khrysais:BAAALgADCgMJAwAAAA==.',
Ki='Killigula:BAABLgAECn8YAAINAAYJrxatEAAkAQANAAYJrxatEAAkAQAAAA==.Kinuye:BAAALgADCggJEwAAAA==.Kishara:BAAALgAECgMJAwABLgAECggJIAACAGMcAA==.',
Kl='Klondor:BAABLgAECn8ZAAQCAAcJ7wo8HwAGAQACAAYJHAk8HwAGAQAZAAYJFwsIHgD6AAATAAIJxwFifwBIAAAAAA==.Klutch:BAAALgADCgUJCAAAAA==.',
Ko='Korash:BAAALgAECgYJDwAAAA==.',
Kr='Kraio:BAAALgAECgYJCAAAAA==.Kraisa:BAAALgADCgQJBAAAAA==.Krak:BAAALgAECgEJAQAAAA==.Krakenbones:BAAALgADCgkJCQAAAA==.Krenolarian:BAAALgADCgUJBQAAAA==.',
Kv='Kvoke:BAAALgAECgEJAwAAAA==.',
Ky='Kyranni:BAAALgAECgEJAQAAAA==.',
La='Lamora:BAAALgAECgYJDgAAAA==.Lampard:BAAALgAECgcJEQAAAA==.Laraj:BAAALgAECgYJDQAAAA==.Larissaqt:BAEALgAECgYJDgABLgAECggJCgADAAAAAA==.Latinhunter:BAAALgAECgMJAwAAAA==.Latinmonk:BAAALgAECgQJBAAAAA==.Latinshamy:BAAALgAECgUJCAAAAA==.Lavande:BAAALgAECgQJCgAAAA==.',
Le='Leara:BAAALgAECgMJAwABLgAECggJIAACAGMcAA==.Legomyagro:BAAALgAECggJEwAAAA==.Lehaya:BAAALgADCgYJBgAAAA==.Leiasolo:BAAALgADCgYJBwAAAA==.Leonaá:BAAALgAECgEJAQABLgAECgkJIgAaAAcjAA==.',
Li='Lilbessy:BAAALgAECgQJCAAAAA==.Lishaliel:BAAALgADCgcJBwABLgAECggJIAACAGMcAA==.Lizzia:BAAALgADCgQJBAAAAA==.',
Lo='Loopysoup:BAAALgAECgEJAQABLgAECgcJDgADAAAAAA==.Loopyswoop:BAAALgAECgcJDgAAAA==.Lothriel:BAABLgAECn8bAAIbAAgJwhbWAwA7AgAbAAgJwhbWAwA7AgAAAA==.',
Lu='Lucid:BAAALgAECgEJAQAAAA==.Ludioduo:BAAALgAECgQJBAAAAA==.Luedayen:BAABLgAECn8fAAIaAAgJQhzRDwBoAgAaAAgJQhzRDwBoAgAAAA==.Lukesunwalkr:BAAALgADCgQJCAAAAA==.Lunabellz:BAAALgAECgQJCAAAAA==.Lunavia:BAAALgAECgYJDwAAAA==.Luxembourge:BAAALgAECgUJDQAAAA==.',
Ma='Maalgus:BAAALgAECgQJBQAAAA==.Mad:BAAALgAECgEJAQAAAA==.Magivyne:BAAALgAECgEJAQAAAA==.Mahota:BAAALgADCgYJDAAAAA==.Makennah:BAAALgADCgcJBwAAAA==.Maladash:BAABLgAECn8fAAMBAAgJrxx9NAAnAgABAAgJrxx9NAAnAgAJAAEJAgkWdAAxAAAAAA==.Malephar:BAAALgADCgMJAwAAAA==.Manachi:BAAALgAECgIJAgAAAA==.Margoul:BAAALgADCgIJAwAAAA==.Massfootmen:BAAALgADCgUJBQAAAA==.Matiowen:BAAALgADCgMJAwAAAA==.Mauie:BAAALgADCgEJAQAAAA==.Mayyhem:BAACLgAFFH8QAAIQAAUJxBWnAQCjAQAQAAUJxBWnAQCjAQAuAAQKfyUAAxAACQlGInoBAG8DABAACQlGInoBAG8DABIAAgneGd0vAJgAAAAA.Mazrethil:BAAALgADCgEJAQAAAA==.',
Mc='Mcjudgin:BAABLgAECn8XAAMcAAgJZiXeAABnAwAcAAgJZiXeAABnAwAFAAEJCh1BLAFIAAAAAA==.Mcsquid:BAAALgAECgEJAQAAAA==.',
Md='Mdrakeyd:BAAALgAECgUJDAAAAA==.',
Me='Meatbubble:BAAALgADCgkJDAAAAA==.Mephisston:BAAALgADCgIJAgAAAA==.Mesasneaky:BAAALgAECgUJBQAAAA==.',
Mi='Mimi:BAAALgAECgMJAwAAAA==.Mimiker:BAABLgAECn8hAAQRAAgJahxxDQCeAgARAAgJahxxDQCeAgASAAcJgRZmEgC6AQAQAAEJQwGiSQAvAAAAAA==.Minime:BAAALgAECgcJDAABLgAFFAYJEAACALIbAA==.Minininja:BAAALgADCgcJDAABLgAECgQJDQADAAAAAA==.Miniobi:BAAALgADCgYJCAAAAA==.Mirabella:BAAALgAECgQJBwAAAA==.Mistdemeanor:BAAALgAECgEJAgAAAA==.Mizahella:BAAALgAECgEJAQAAAA==.',
Mo='Mokei:BAAALgAECgQJBAAAAA==.Mokushi:BAAALgAECgQJCAAAAA==.Mollie:BAAALgADCgcJBwABLgADCgkJFAADAAAAAA==.Monkgruff:BAAALgAECgUJBQAAAA==.Monkèy:BAAALgADCgUJBQAAAA==.Moonsilver:BAAALgAECgQJBAAAAA==.Moriko:BAABLgAECn8fAAICAAgJAxoAFgCIAgACAAgJAxoAFgCIAgAAAA==.Mornak:BAAALgAECgkJCAAAAA==.',
Mu='Muertomarrow:BAAALgAECgQJBQAAAA==.Mulroth:BAAALgAECgMJAwAAAA==.Murloc:BAAALgAECgYJCgAAAA==.Musasa:BAABLgAECn8gAAIKAAgJ5xjYCADRAQAKAAgJ5xjYCADRAQAAAA==.Mustardseed:BAABLgAECn8bAAIGAAgJ5QYMGQBKAQAGAAgJ5QYMGQBKAQAAAA==.Muxaro:BAAALgADCgkJEwAAAA==.',
['Mí']='Mísery:BAAALgAECgYJDQAAAA==.',
Na='Naked:BAAALgAECgIJAwAAAA==.Nalibeefcake:BAAALgADCgcJDQAAAA==.Narkoleptick:BAAALgAECgYJCAAAAA==.Nasrith:BAABLgAECn8gAAIFAAgJ4xwvBABgAgAFAAgJ4xwvBABgAgAAAA==.Nastro:BAAALgAECgEJAQAAAA==.Nawtishot:BAAALgADCgEJAQAAAA==.Nazanath:BAAALgAECgIJAgAAAA==.',
Ne='Neeb:BAAALgAECggJEgAAAA==.Neeber:BAAALgAECgUJCAAAAA==.Nekk:BAAALgAECgYJDwAAAA==.',
Ni='Niamyau:BAAALgADCgMJAwAAAA==.Nitebrite:BAAALgAECgYJDwAAAA==.',
No='Noatak:BAAALgAECgEJAQAAAA==.Nohozis:BAAALgADCgQJBAAAAA==.Noimia:BAABLgAECn8jAAIVAAgJ4Rj8EwArAgAVAAgJ4Rj8EwArAgAAAA==.Normanosborn:BAAALgAECgQJCgAAAA==.',
Ny='Nyquiil:BAAALgADCgkJCQAAAA==.Nyssil:BAAALgADCgcJCwAAAA==.',
['Né']='Nésa:BAAALgADCgYJBgAAAA==.',
['Nï']='Nïssan:BAAALgAECgMJAwAAAA==.',
Ob='Obscûr:BAAALgAECgQJBgAAAA==.',
Oc='Ochtli:BAAALgADCgUJBQAAAA==.',
Od='Oden:BAAALgAECgQJCQAAAA==.',
Og='Oggy:BAAALgAECgIJAgAAAA==.',
Ok='Oksanabaiul:BAAALgAECgQJCwABLgAFFAMJBQAGABYYAA==.',
Ol='Oldcode:BAAALgAECgUJCgAAAA==.Oleyander:BAAALgAECgEJAQAAAA==.Olskigather:BAAALgADCgEJAQAAAA==.Olskimonk:BAAALgAECgIJAgABLgAECgUJBQADAAAAAA==.',
Or='Oronin:BAAALgADCgcJHAAAAA==.',
Os='Osanyin:BAAALgAECgYJDAAAAA==.',
Ot='Otsuka:BAAALgADCgEJAQAAAA==.',
Pa='Padray:BAACLgAFFH8FAAIdAAMJXwZzBgDNAAAdAAMJXwZzBgDNAAAuAAQKfyYAAh0ACAlhGvASAF8CAB0ACAlhGvASAF8CAAAA.Paecos:BAAALgADCgYJDQAAAA==.Palize:BAAALgADCgYJBgABLgAECgcJCwADAAAAAA==.Panhia:BAAALgAECgQJDQAAAA==.Parliament:BAAALgAECgYJCwAAAA==.',
Pe='Pekoyami:BAAALgADCgUJBQAAAA==.Pen:BAAALgAECgcJEQAAAA==.Pepenlock:BAAALgAECgQJBQAAAA==.Pepperbottom:BAAALgAECgcJEAAAAA==.',
Ph='Phantasmshot:BAABLgAECn8cAAICAAYJxQtvYABGAQACAAYJxQtvYABGAQAAAA==.Phoebere:BAAALgAECgEJAQAAAA==.Phung:BAAALgAECgcJCAAAAA==.Phungi:BAAALgAECgYJDAAAAA==.',
Po='Polymnia:BAAALgAECgEJAQAAAA==.Pomelo:BAAALgAECgIJAwAAAA==.Popeums:BAAALgAECgYJDwAAAA==.Poppiqt:BAAALgAECgYJDwAAAA==.Powlie:BAAALgADCgYJDAAAAA==.Poyoh:BAABLgAECn8gAAIKAAgJDxtzBQAlAgAKAAgJDxtzBQAlAgAAAA==.',
Pr='Pravoce:BAAALgAECgQJBAAAAA==.Prufrock:BAAALgADCgYJBgAAAA==.',
['Pí']='Pínt:BAAALgAECgYJDwAAAA==.',
Qu='Quelissa:BAAALgADCgkJCQABLgADCgkJFgADAAAAAA==.',
Ra='Radjason:BAAALgADCggJCQAAAA==.Raeagald:BAAALgAECgIJBAABLgAFFAMJBQAWAE8KAA==.Raelyni:BAABLgAECn8gAAIaAAgJ4hZCBQDTAQAaAAgJ4hZCBQDTAQAAAA==.Rageroyal:BAAALgADCgEJAQAAAA==.Rakkah:BAAALgAECgYJEQAAAA==.Rakkuh:BAAALgAECgQJBAAAAA==.Ramjam:BAAALgADCgYJCQAAAA==.Raveniss:BAAALgAECgQJCQAAAA==.Rawrie:BAAALgAECgUJDAAAAA==.Raygun:BAAALgAECgYJCgABLgADCgQJBAADAAAAAA==.Rayzorevoker:BAAALgADCgcJDQAAAA==.Raziell:BAAALgADCgMJAwAAAA==.',
Re='Redhilda:BAAALgAECgcJDAAAAA==.Redmayhem:BAAALgADCgYJBgAAAA==.Remygos:BAAALgADCgEJAQAAAA==.',
Rh='Rhymu:BAAALgADCgMJAwABLgAECgEJAQADAAAAAA==.',
Ri='Rissaria:BAAALgAECgIJAgAAAA==.',
Ro='Roshelle:BAAALgAECgIJAgAAAA==.Rotation:BAAALgAECgQJBAAAAA==.Rotblade:BAAALgAECgYJEAAAAA==.',
Ru='Rudewenn:BAAALgAECgMJAwAAAA==.Runandhide:BAABLgAECn8UAAIEAAYJmhDOuQBuAQAEAAYJmhDOuQBuAQAAAA==.',
Ry='Ryllativity:BAAALgADCgEJAQAAAA==.',
['Rø']='Røøtsftw:BAAALgAECgYJBgAAAA==.',
Sa='Sadsnap:BAABLgAECn8YAAIeAAcJxyBDCQBFAgAeAAcJxyBDCQBFAgAAAA==.Salamender:BAABLgAECn8YAAIQAAgJnxJHFQD1AQAQAAgJnxJHFQD1AQAAAA==.Sargothys:BAAALgAECgIJAgAAAA==.Sariais:BAAALgAECgEJAQAAAA==.Sassymoo:BAAALgAECgYJDAABLgAFFAMJBwAfANQQAA==.Sathenoth:BAAALgADCggJCAAAAA==.Savagejoker:BAAALgADCgYJBgABLgAECggJIQAgAL4iAA==.Sañtoro:BAAALgAECgQJBAAAAA==.',
Sc='Scalesboi:BAAALgADCgMJAwAAAA==.Scipione:BAAALgAECgQJCAAAAA==.Scy:BAAALgAECgQJBgAAAA==.',
Se='Seddona:BAAALgADCgkJCQAAAA==.Seithe:BAAALgADCgkJCQAAAA==.Seluun:BAABLgAECn8UAAIEAAUJrhB5OQDdAAAEAAUJrhB5OQDdAAAAAA==.Semandemon:BAAALgADCgEJAQAAAA==.Seraphae:BAAALgAECgQJBAAAAA==.',
Sh='Shadowmorn:BAABLgAECn8VAAIhAAgJsAEMGACzAAAhAAgJsAEMGACzAAAAAA==.Shalako:BAAALgADCgUJBwAAAA==.Shamnistic:BAABLgAECn8YAAIeAAgJux+EAACMAgAeAAgJux+EAACMAgAAAA==.Shandro:BAABLgAECn8fAAIEAAgJmwflHABmAQAEAAgJmwflHABmAQAAAA==.Shaniallon:BAAALgAECgcJEwAAAA==.Shara:BAAALgADCgMJBgAAAA==.Sharana:BAAALgADCgUJBQAAAA==.Shaunï:BAAALgADCgkJCQAAAA==.Shieldman:BAAALgADCgMJAwAAAA==.Shiftylock:BAAALgAECgQJDgAAAA==.Showong:BAAALgAECgEJAQAAAA==.',
Si='Silentaska:BAAALgAECgYJEgAAAA==.Silentbruce:BAAALgAECgYJBgAAAA==.Silentchill:BAABLgAECn8fAAMLAAgJrB32FwBKAgALAAgJrB32FwBKAgAKAAEJBQLF5AAgAAAAAA==.Silius:BAAALgAECgEJAQAAAA==.Simoncrunch:BAAALgAECgEJAgAAAA==.Sin:BAAALgAECgEJAQABLgAECgEJAQADAAAAAA==.Sinomen:BAAALgAECgYJDAABLgAFFAYJDgARAKcTAA==.Sinzilla:BAAALgAECgQJCAAAAA==.Sizzen:BAAALgADCgkJCQAAAA==.',
Sk='Skunkdrunk:BAAALgADCgYJBwAAAA==.Skyblue:BAAALgAECgUJBwAAAA==.',
Sm='Smokebull:BAAALgAECgcJDgAAAA==.',
Sn='Snoopshaman:BAAALgAECgEJAQABLgAECggJFwAcAGYlAA==.Snowcake:BAAALgAECgEJBAAAAA==.',
So='Sofiavers:BAAALgADCgkJEAAAAA==.Solarhoof:BAAALgADCgEJAQAAAA==.Sonarak:BAAALgADCgEJAQABLgAECggJFwAcAGYlAA==.Sornafayne:BAAALgADCgkJEgAAAA==.Sorrengail:BAAALgAECgMJBwAAAA==.',
Sp='Spareme:BAAALgADCgcJEgAAAA==.Specialkidd:BAAALgAECgYJBgAAAA==.Springrollz:BAAALgADCgEJAgABLgAFFAYJEAACALIbAA==.Spy:BAABLgAECn8fAAICAAgJoBghGwBkAgACAAgJoBghGwBkAgAAAA==.',
Sr='Sravoz:BAAALgADCgYJCAAAAA==.',
St='Stabbitha:BAAALgADCgkJHAAAAA==.Stampa:BAAALgAECgEJAQAAAA==.Starrie:BAABLgAECn8VAAIfAAcJ7BETDgBeAQAfAAcJ7BETDgBeAQAAAA==.Steaknshake:BAAALgAECgQJBAAAAA==.Steelhoof:BAABLgAECn8fAAITAAgJaQi1PABqAQATAAgJaQi1PABqAQAAAA==.Steil:BAAALgADCgYJBwAAAA==.Steponmyface:BAAALgAECgUJEgAAAA==.Stewie:BAAALgADCgcJCgABLgADCgkJFAADAAAAAA==.Stonesoul:BAAALgADCgkJEAAAAA==.Stories:BAAALgAECgYJEQAAAA==.Storm:BAEALgAECgMJAwABLgAECggJIgAOAMMcAA==.Stormfury:BAAALgAECgEJAQAAAA==.Strucker:BAAALgADCgcJCwABLgAECggJIAAWAHAfAA==.Struckerz:BAAALgADCgkJEAABLgAECggJIAAWAHAfAA==.Struckrucker:BAABLgAECn8gAAIWAAgJcB/dAQBTAgAWAAgJcB/dAQBTAgAAAA==.',
Su='Sudimmoc:BAAALgAECgIJAgAAAA==.Sugarbear:BAAALgADCgUJBQAAAA==.Sunchips:BAAALgAECgYJBgAAAA==.Sushie:BAAALgADCgMJAwABLgAFFAQJDQAPAMQXAA==.',
Sw='Swipe:BAAALgAECgEJAQAAAA==.',
Sy='Synn:BAAALgADCgkJEgAAAA==.Syvina:BAAALgAECgQJBQAAAA==.',
Ta='Tabby:BAAALgAECgEJAQAAAA==.Taconight:BAAALgAECgMJBwAAAA==.Tag:BAAALgAECgYJCAAAAA==.Takyon:BAAALgADCgYJBgABLgAECggJFgAOALcjAA==.Tallynz:BAAALgAECgYJBwAAAA==.Tankornot:BAAALgAECgQJDAAAAA==.Tarasque:BAAALgADCgMJAwABLgAECgEJBAADAAAAAA==.Tarlgreyhair:BAAALgADCgkJHwAAAA==.Tarnished:BAAALgAECgYJDAAAAA==.Tarria:BAAALgAECgQJCAAAAA==.Taseluk:BAAALgADCgYJBAAAAA==.Tateerfel:BAAALgAECgQJCgAAAA==.Tateertot:BAAALgADCgkJCQABLgAECgQJCgADAAAAAA==.Tawneestone:BAABLgAECn8fAAIMAAgJbyDgAAB6AgAMAAgJbyDgAAB6AgAAAA==.',
Te='Teedizzle:BAAALgAECgEJAQAAAA==.Teek:BAAALgAECgYJEgAAAA==.Telandaraa:BAABLgAECn8iAAMaAAkJByO6AQBdAwAaAAkJByO6AQBdAwAYAAMJFQn5RACRAAAAAA==.Telrae:BAABLgAECn8UAAIGAAcJOR0xDgChAQAGAAcJOR0xDgChAQAAAA==.',
Th='Theb:BAAALgAECgcJBwAAAA==.Thederpb:BAAALgAECgcJBwAAAA==.Thejuice:BAAALgADCgcJDwAAAA==.Theldara:BAABLgAECn8gAAMCAAgJYxxEKQASAgACAAgJYxxEKQASAgATAAYJExb9OgBzAQAAAA==.Themock:BAAALgAECgQJBQAAAA==.Theresjohnny:BAAALgADCgkJGwAAAA==.Theshift:BAABLgAECn8eAAIYAAgJPBCVGADXAQAYAAgJPBCVGADXAQAAAA==.Thesixtyone:BAAALgADCgcJBwAAAA==.Thisisjustin:BAABLgAECn8UAAIiAAcJNhouAwDwAQAiAAcJNhouAwDwAQAAAA==.Thoreen:BAAALgAECgEJAQAAAA==.Thotsnprayer:BAAALgADCgMJBAAAAA==.Thraiel:BAAALgADCgEJAQABLgAECgUJDQADAAAAAA==.Thrish:BAABLgAECn8lAAQCAAgJuxn1HABYAgACAAgJuxn1HABYAgAZAAQJQQw8DADCAAATAAEJBQJ0mAAeAAAAAA==.Throom:BAAALgADCgIJAgAAAA==.Thuggies:BAAALgAECgMJAwAAAA==.Thunderfist:BAAALgADCgYJBgABLgAECggJHwABAK8cAA==.',
Ti='Tizzlerizzle:BAAALgADCgkJFgAAAA==.',
To='Tomacco:BAAALgADCggJEgAAAA==.Toreto:BAAALgADCgUJBwAAAA==.Toshi:BAAALgADCgkJCQAAAA==.Totemiclord:BAAALgAECggJCQAAAA==.',
Ts='Tsukiyami:BAAALgAECgQJCgAAAA==.',
Tw='Twixaldo:BAAALgADCgcJDQABLgAECgYJFAAFAPcgAA==.',
Ty='Ty:BAAALgADCgEJAQAAAA==.Tylus:BAAALgADCgcJCgAAAA==.',
Ub='Ubpriest:BAAALgADCgkJDQAAAA==.',
Up='Upinya:BAAALgAECgcJEAAAAA==.',
Va='Vadderung:BAABLgAECn8ZAAIBAAgJNhyTKgBWAgABAAgJNhyTKgBWAgAAAA==.Valera:BAAALgAECgYJCwABLgAECggJIwAIAAAlAA==.Valkilmer:BAAALgADCgEJAQAAAA==.Vallasha:BAAALgAECgYJDQAAAA==.Valoth:BAAALgADCgEJAQAAAA==.Valtures:BAAALgAECgMJBgAAAA==.Vampyre:BAABLgAECn8UAAICAAYJQh1oDgCRAQACAAYJQh1oDgCRAQAAAA==.Vayne:BAACLgAFFH8FAAINAAMJcxVQBQAMAQANAAMJcxVQBQAMAQAuAAQKfyUAAw0ACAkRIMURAMICAA0ACAkRIMURAMICAAgAAQksE/9AADYAAAAA.',
Ve='Veloistina:BAAALgADCgUJBQABLgAECgYJFAAFAPcgAA==.Venator:BAAALgADCgQJBAAAAA==.Vezzini:BAAALgADCgcJEAAAAA==.',
Vh='Vh:BAAALgAECgQJCAAAAA==.',
Vi='Videlle:BAAALgADCgMJAwAAAA==.Vieoree:BAAALgAECgEJAQAAAA==.Vigoh:BAAALgADCgcJBwABLgAECgMJBwADAAAAAA==.Vinge:BAEBLgAECn8iAAIOAAgJwxzqLQCBAgAOAAgJwxzqLQCBAgAAAA==.Vinter:BAAALgADCgcJCgAAAA==.Violetferal:BAAALgADCggJCAAAAA==.Violetrain:BAABLgAECn8WAAIFAAYJYQOC0ADpAAAFAAYJYQOC0ADpAAAAAA==.Viralswine:BAAALgADCgcJDQAAAA==.Visarys:BAAALgAECgQJBAAAAA==.Vixipixi:BAAALgADCgYJEgAAAA==.',
Vo='Vollibear:BAAALgAECgMJAwAAAA==.Voltaic:BAAALgAECgcJEQABLgAECgcJIQABACgjAA==.Vothdomosh:BAAALgADCgcJEgABLgAECgYJFgAPAAokAA==.',
Vy='Vyrista:BAAALgAECgMJBgAAAA==.Vyrzeth:BAAALgAECgEJAQAAAA==.Vyzualize:BAACLgAFFH8NAAIPAAUJKhN6BACYAQAPAAUJKhN6BACYAQAuAAQKfxsAAg8ACQnYHa0HAPICAA8ACQnYHa0HAPICAAAA.',
Wa='Wae:BAAALgAECgYJCwAAAA==.Waferblade:BAAALgADCgcJBwAAAA==.Waknipi:BAAALgAECgYJDwAAAA==.Wauwen:BAAALgADCgQJBAAAAA==.Wavecheck:BAAALgAECgMJBQAAAA==.Way:BAAALgAECgIJAgAAAA==.Waycaps:BAACLgAFFH8FAAIjAAMJeRTXAADpAAAjAAMJeRTXAADpAAAuAAQKfyMAAiMACAlaItABAPgCACMACAlaItABAPgCAAAA.',
We='Wednesdáy:BAABLgAECn8UAAINAAcJVw9/PwCmAQANAAcJVw9/PwCmAQAAAA==.Werlock:BAAALgAECgcJCgABLgAECggJFgARAJcOAA==.',
Wh='Wheresjohnny:BAABLgAECn8gAAIXAAgJWhegAgDlAQAXAAgJWhegAgDlAQAAAA==.',
Wi='Wiccked:BAABLgAECn8XAAIkAAgJihG3BAArAgAkAAgJihG3BAArAgAAAA==.Windrange:BAABLgAECn8eAAIEAAgJmx5SKwDFAgAEAAgJmx5SKwDFAgAAAA==.Winterice:BAAALgAECgEJAQAAAA==.Wintérhoof:BAAALgADCgcJGAABLgAECgMJAwADAAAAAA==.',
Wo='Wonderpally:BAAALgADCgkJCQAAAA==.Woodscale:BAAALgAECgEJAQAAAA==.Wovenbones:BAAALgAECgQJCAAAAA==.',
Wu='Wuggs:BAAALgAECgIJAgABLgAFFAMJBQAEALAaAA==.Wumbo:BAAALgADCgYJDAAAAA==.',
Wy='Wyvarn:BAAALgAECgcJBwAAAA==.',
Xa='Xargothys:BAAALgAECgQJBwAAAA==.',
Xi='Xiisle:BAAALgAECgYJDwAAAA==.Xine:BAAALgADCgkJFAAAAA==.',
Ya='Yanya:BAAALgADCgkJFgAAAA==.',
Ye='Yergat:BAACLgAFFH8QAAMCAAYJshv3BAAuAQATAAYJbRYSDQBNAQACAAMJZSD3BAAuAQAuAAQKfy8AAxMACQmIJO8BAJwDABMACQn1Iu8BAJwDAAIAAwnwIltmADQBAAAA.',
Yu='Yupa:BAAALgAECgQJCAABLgAECggJHwACAAMaAA==.',
Za='Zafira:BAACLgAFFH8HAAIfAAMJ1BDLEQDYAAAfAAMJ1BDLEQDYAAAuAAQKfyAAAx8ACQkFGmERAIwCAB8ACQkFGmERAIwCACEAAwnmDNtxAHsAAAAA.Zainea:BAAALgADCgMJAwABLgAFFAMJBwAfANQQAA==.Zarndarg:BAAALgAECgQJBAAAAA==.Zartuu:BAAALgAECgcJCQAAAA==.Zattani:BAAALgAECgQJBgAAAA==.',
Ze='Zeel:BAAALgAECgUJBQAAAA==.Zelblades:BAAALgAECgYJDQABLgAECggJIAAlAOMbAA==.Zelrex:BAABLgAECn8gAAMlAAgJ4xtvDwCtAgAlAAgJ4xtvDwCtAgAmAAEJphQfHQBCAAAAAA==.Zerat:BAAALgAECgMJAwAAAA==.Zerazer:BAAALgAFFAEJAQAAAA==.',
Zh='Zhuntyr:BAAALgAECgMJBAAAAA==.',
Zi='Zindar:BAAALgAECgYJDwAAAA==.',
Zv='Zv:BAAALgADCgUJBQAAAA==.',
Zy='Zylos:BAAALgADCgEJAQAAAA==.Zynzz:BAAALgAECgMJBgAAAA==.',
['Zô']='Zômi:BAAALgAECgMJAwAAAA==.',
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
