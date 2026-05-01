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

local lookup = {'Warrior-Fury','Unknown-Unknown','Hunter-Survival','Priest-Discipline','Druid-Restoration','Monk-Mistweaver','DeathKnight-Blood','DeathKnight-Unholy','Mage-Frost','Paladin-Retribution','Hunter-BeastMastery','Warlock-Affliction','Warlock-Demonology','Paladin-Holy','Priest-Shadow','Monk-Brewmaster','Monk-Windwalker','Rogue-Subtlety','Warlock-Destruction','Shaman-Elemental','Shaman-Restoration','DemonHunter-Vengeance','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Paladin-Protection','Rogue-Assassination','Rogue-Outlaw','Druid-Guardian','Hunter-Marksmanship','Warrior-Protection','DemonHunter-Devourer','Shaman-Enhancement','Druid-Feral','Priest-Holy','Druid-Balance','Warrior-Arms','DemonHunter-Havoc','Mage-Fire',}
local provider = {region='US',realm="Eldre'Thalas",name='US',type='weekly',zone=46,date='2026-05-01',data={Ac='Acharon:BAABLgAECn8bAAIBAAcJdBDmFgB7AQABAAcJdBDmFgB7AQAAAA==.',
Ad='Adrastus:BAAALgAECgYJDQAAAA==.',
Ae='Aeslin:BAAALgAECgYJBgABLgAECgYJDgACAAAAAA==.',
Ah='Ahsoka:BAAALgAECgYJDAAAAA==.',
Ai='Ain:BAAALgAFFAEJAQAAAA==.Ainslie:BAAALgAECgYJBgAAAA==.',
Al='Alarashinu:BAAALgAECgYJEQAAAA==.Alataris:BAAALgADCgQJBAAAAA==.Alawae:BAABLgAECn8VAAIDAAYJRSDYCgApAgADAAYJRSDYCgApAgAAAA==.Altria:BAAALgADCgcJEAAAAA==.',
Am='Amarco:BAAALgAECgcJEAAAAA==.',
An='Anahit:BAAALgADCgUJBQAAAA==.Angela:BAAALgADCgcJEAABLgAECggJJAAEALgTAA==.',
Ap='Apaka:BAAALgADCgEJAQAAAA==.',
Ar='Araedia:BAAALgAECgYJCAABLgAECggJGQAFAMoVAA==.Arahant:BAACLgAFFH8JAAIGAAQJsxfACgAvAQAGAAQJsxfACgAvAQAuAAQKfyMAAgYACAlPHvwMAIMCAAYACAlPHvwMAIMCAAAA.Aretas:BAABLgAECn8bAAMHAAcJfSBrBQDcAQAHAAYJdiJrBQDcAQAIAAEJoha+sgA9AAABLgAECggJCgACAAAAAA==.Arriånna:BAAALgADCgkJFAAAAA==.Arrowpeen:BAAALgAECgQJBwAAAA==.',
As='Ashuffle:BAAALgAECgQJCAAAAA==.Asifa:BAAALgAECgUJCQAAAA==.Astinds:BAAALgADCgMJBQABLgAECgMJBQACAAAAAA==.',
At='Atherion:BAABLgAECn8ZAAIJAAgJig8GMACjAQAJAAgJig8GMACjAQAAAA==.',
Au='Aurod:BAAALgADCgMJBAAAAA==.',
Av='Avareh:BAAALgADCgIJAQAAAA==.Averix:BAAALgAECgEJAQAAAA==.Avranarada:BAABLgAECn8ZAAIFAAgJyhVuEQACAgAFAAgJyhVuEQACAgAAAA==.',
Az='Azung:BAABLgAECn8fAAIKAAgJdR9nEgAnAgAKAAgJdR9nEgAnAgAAAA==.',
Ba='Babaisyaga:BAACLgAFFH8NAAILAAQJcxnJCgBZAQALAAQJcxnJCgBZAQAuAAQKfyUAAgsACAkjI9YIAAUDAAsACAkjI9YIAAUDAAAA.Baelia:BAAALgAECgEJAQAAAA==.Baimes:BAABLgAECn8aAAMMAAcJJBElAwCRAQAMAAcJJBElAwCRAQANAAEJXwFXNAEUAAAAAA==.Baka:BAABLgAECn8mAAMOAAgJ2SJUAQAtAwAOAAgJ2SJUAQAtAwAKAAYJNBCkkQBZAQAAAA==.Balance:BAAALgADCgIJAgAAAA==.Balinse:BAAALgAECgYJEQAAAA==.Bandruì:BAAALgAECgMJAwAAAA==.Bankpoo:BAACLgAFFH8KAAIIAAQJvBDdHgA/AQAIAAQJvBDdHgA/AQAuAAQKfyAAAwgACAkeHwcuAIACAAgABwntIgcuAIACAAcAAQlICAAAAAAAAAAA.Baragohn:BAAALgADCggJCAAAAA==.Barb:BAAALgADCgMJBgAAAA==.Barrelrollin:BAAALgAECgUJBQAAAA==.Batrito:BAABLgAECn8kAAMEAAgJuBMXHAC1AQAEAAgJuBMXHAC1AQAPAAcJMxKIDwCSAQAAAA==.Bawchu:BAAALgADCgYJBgAAAA==.',
Be='Bealzebubbà:BAAALgAECgUJCgAAAA==.Beastfodays:BAAALgAECgcJEgAAAA==.Beaviss:BAAALgADCgUJBQAAAA==.Benn:BAABLgAECn8VAAMOAAYJ1hXAMgCzAQAOAAYJ1hXAMgCzAQAKAAYJFwiAWgACAQAAAA==.Bethlahammer:BAAALgADCgQJBAABLgAECgQJBAACAAAAAA==.',
Bi='Bigboom:BAAALgADCgQJBAAAAA==.Billcosbrew:BAABLgAECn8hAAIQAAgJRCVyAgC5AgAQAAgJRCVyAgC5AgAAAA==.Biomechan:BAAALgAECgQJDQAAAA==.',
Bj='Bjorinn:BAAALgAECgIJAgAAAA==.',
Bl='Blackleaf:BAAALgAECgMJAwAAAA==.Blankshot:BAAALgADCgMJAwAAAA==.Blightsides:BAAALgAECgMJAwABLgAECgcJEgACAAAAAA==.Blizzcon:BAABLgAECn8mAAMEAAcJCxZbEgBtAQAEAAcJCxZbEgBtAQAPAAMJWAcVLQCZAAAAAA==.',
Bo='Borrgar:BAAALgAECgYJEwAAAA==.',
Br='Brackle:BAABLgAECn8eAAILAAcJjyHmDAA3AgALAAcJjyHmDAA3AgAAAA==.Bracori:BAACLgAFFH8HAAIGAAQJfBAbDAAZAQAGAAQJfBAbDAAZAQAuAAQKfyMAAwYACAkKEAkoAHQBAAYACAkKEAkoAHQBABEABgn0DP83AD4BAAAA.Brandywynne:BAABLgAECn8kAAILAAgJ0Q6iIwCOAQALAAgJ0Q6iIwCOAQAAAA==.Brick:BAABLgAECn8gAAISAAgJ1x2NAwBmAgASAAgJ1x2NAwBmAgAAAA==.Briggsie:BAAALgADCgQJBgAAAA==.Brightfame:BAABLgAECn8nAAMTAAgJrBu8AQAcAgATAAgJxhm8AQAcAgAMAAYJ8huYCAC/AQAAAA==.Bronny:BAAALgADCgMJAwAAAA==.Brownpepperz:BAAALgADCgEJAQAAAA==.',
Bu='Bubblebull:BAAALgADCgcJDAAAAA==.Buffalox:BAAALgADCgUJBQAAAA==.Butterbllz:BAABLgAECn8UAAIKAAgJ5hYBaACvAQAKAAgJ5hYBaACvAQAAAA==.',
Ca='Caius:BAAALgADCgUJDAAAAA==.Calaine:BAAALgADCgcJBwAAAA==.Calypsio:BAAALgAECgYJEwAAAA==.Camany:BAAALgAECgYJDwAAAA==.Cantread:BAAALgAECgcJBwABLgAFFAMJCAAPAKUMAA==.Caretakerz:BAAALgAECgYJDwAAAA==.Cartus:BAABLgAECn8YAAMUAAcJzQsvIAAZAQAUAAcJzQsvIAAZAQAVAAQJ+gSrSwBvAAAAAA==.',
Ce='Cedre:BAAALgADCgQJEAAAAA==.Celidoria:BAABLgAECn8WAAIKAAgJNx4/KwB3AgAKAAgJNx4/KwB3AgAAAA==.',
Ch='Chainfrost:BAAALgADCgEJAQAAAA==.Cheesepuff:BAABLgAECn8UAAINAAYJigngUwD1AAANAAYJigngUwD1AAAAAA==.Chikara:BAAALgAECgQJBQAAAA==.Chittypalli:BAAALgADCgcJBwAAAA==.',
Ci='Cindera:BAAALgADCgcJBwABLgAFFAQJCwAJAPEXAA==.Cinnibar:BAAALgADCgYJBgAAAA==.Cirï:BAAALgAECgYJDAAAAA==.Cisbick:BAAALgAECgYJEAAAAA==.',
Cl='Clamshell:BAABLgAECn8hAAIIAAgJEyIsCgB/AgAIAAgJEyIsCgB/AgAAAA==.Clayier:BAAALgAECgQJCAAAAA==.',
Cn='Cntendr:BAAALgAECgMJBQAAAA==.Cntendrthree:BAAALgADCgMJAwAAAA==.',
Co='Codenike:BAAALgAECgYJDwAAAA==.Companionbea:BAAALgAECgEJAQAAAA==.Corbanite:BAAALgAECgEJAQAAAA==.Corelheals:BAAALgADCgMJAwAAAA==.Corpsè:BAAALgAECgYJDgAAAA==.Covertyqt:BAABLgAECn8hAAIJAAgJuSBpCgCYAgAJAAgJuSBpCgCYAgAAAA==.Coyote:BAAALgAECgkJAgAAAA==.',
Cp='Cptnhuman:BAABLgAECn8hAAIIAAgJ8hdvGwDjAQAIAAgJ8hdvGwDjAQAAAA==.',
Cr='Crunk:BAAALgAECgQJCAAAAA==.Cryptis:BAAALgADCgEJAQAAAA==.',
Da='Daboof:BAAALgADCgkJFwAAAA==.Daddydragon:BAAALgADCgQJBAAAAA==.Daemandred:BAAALgADCgcJBwAAAA==.Daggere:BAAALgAECgEJAgAAAA==.Damaged:BAAALgAECgQJBAAAAA==.Damian:BAAALgAECgUJBwABLgAECgYJCgACAAAAAA==.Danfu:BAAALgADCgEJAQAAAA==.Danke:BAAALgAECgYJDQAAAA==.Dankrazor:BAAALgADCggJDAAAAA==.Dankz:BAAALgADCgEJAQAAAA==.Darcpawz:BAAALgAECgQJBAAAAA==.Darkenmicky:BAABLgAECn8YAAIQAAcJRA1NFwBFAQAQAAcJRA1NFwBFAQAAAA==.Darkmickyz:BAAALgAECgQJBgAAAA==.Darkqueenx:BAAALgADCgIJAgAAAA==.Darksev:BAAALgADCgIJAgAAAA==.Darthbobula:BAACLgAFFH8KAAIKAAQJ9ge0FgAjAQAKAAQJ9ge0FgAjAQAuAAQKfyMAAgoACAnfIGsYANYCAAoACAnfIGsYANYCAAAA.Darthceril:BAAALgAECgUJBgAAAA==.Daswar:BAAALgAECgYJBgABLgAECgkJCAACAAAAAA==.Dayloc:BAABLgAECn8hAAINAAgJWRAUJACgAQANAAgJWRAUJACgAQAAAA==.',
De='Deataria:BAAALgADCgUJBQAAAA==.Deathrho:BAAALgADCgkJFQAAAA==.Delryth:BAAALgAECgMJAgAAAA==.Delyne:BAAALgADCgYJCAAAAA==.Demontyk:BAAALgADCgkJEAAAAA==.Denareas:BAAALgAECgYJCgAAAA==.Detox:BAAALgADCgQJBAAAAA==.',
Di='Diablõ:BAEBLgAECn8hAAIWAAgJiB+dAQBZAgAWAAgJiB+dAQBZAgAAAA==.Dirtyd:BAAALgAECgEJAwAAAA==.Dirtydeeds:BAABLgAECn8hAAIIAAgJTBCVJwCfAQAIAAgJTBCVJwCfAQAAAA==.Divinetism:BAAALgAECgYJDAAAAA==.',
Dl='Dl:BAABLgAECn8pAAIPAAgJdx5VBABkAgAPAAgJdx5VBABkAgAAAA==.',
Dr='Draccarys:BAAALgAECgcJCAAAAA==.Draekbee:BAABLgAECn8kAAQXAAgJFxXbEgBvAQAYAAYJZBiSFACfAQAXAAgJkBHbEgBvAQAZAAEJwwdhSgAtAAAAAA==.Dragkohn:BAAALgAECgQJBAABLgAECgcJFgAOABMlAA==.Dragonaged:BAAALgADCgMJAwAAAA==.Drakkarr:BAAALgADCgUJCQAAAA==.Drannek:BAAALgAECgEJAQAAAA==.Drimbirt:BAAALgADCgkJGgAAAA==.Drinkmormilk:BAAALgAECgQJBQAAAA==.Drogman:BAAALgAECgEJAQAAAA==.Droowin:BAAALgAECgEJAQABLgAECgUJBQACAAAAAA==.Drshockaloo:BAAALgADCgYJCgAAAA==.',
Du='Duvori:BAAALgAECgEJAQAAAA==.',
Dy='Dyspepsia:BAAALgADCgMJCAAAAA==.',
Eb='Ebullition:BAAALgAECgYJCwAAAA==.',
Ed='Edensfury:BAAALgAECgQJBAAAAA==.',
Ei='Eightyhd:BAAALgADCgkJCQAAAA==.Eigi:BAAALgAECgcJDwAAAA==.',
Ek='Ekthelion:BAABLgAECn8YAAIaAAcJMBgeBwCsAQAaAAcJMBgeBwCsAQAAAA==.',
El='Elavelin:BAAALgADCgUJCgAAAA==.Eldanon:BAABLgAECn8XAAITAAYJzh8zCgAbAgATAAYJzh8zCgAbAgAAAA==.Eleyert:BAABLgAECn8eAAIUAAgJkCTDAQDoAgAUAAgJkCTDAQDoAgAAAA==.Elwe:BAAALgAECgYJEgAAAA==.',
Em='Emmaga:BAAALgAECgYJDQAAAA==.Emrhakul:BAAALgADCgEJAQAAAA==.',
En='Enkidu:BAAALgAECgYJEwAAAA==.Enseth:BAABLgAECn8VAAQXAAgJyA68EQB8AQAXAAgJyA68EQB8AQAYAAQJNQfcLQCsAAAZAAIJpAYMQwBVAAAAAA==.',
Er='Erotikzombie:BAAALgAECgQJDwAAAA==.',
Es='Esme:BAAALgAECgYJDQAAAA==.',
Eu='Eulogy:BAAALgAECgMJBwABLgAECgcJJgAEAAsWAA==.',
Ex='Exene:BAAALgAECggJEgAAAA==.',
Fa='Faelwen:BAAALgAECgIJAgAAAA==.Fairious:BAABLgAECn8aAAMbAAgJkBMeBQB3AQASAAcJ2BGgKwChAQAbAAcJaRAeBQB3AQAAAA==.Fangrell:BAAALgADCgEJAgABLgAECggJIAALAJURAA==.Faror:BAAALgAECgEJAQAAAA==.',
Fe='Feethunter:BAAALgAECgEJAQABLgAFFAYJGgASAIsXAA==.Felcon:BAAALgADCgMJBAAAAA==.Fellivath:BAAALgAECgYJBwAAAA==.Fet:BAACLgAFFH8aAAMSAAYJixecAQCtAQASAAYJORacAQCtAQAcAAQJag5zAQA+AQAuAAQKfycAAxIACAlnItoIAAQDABIACAlnItoIAAQDABwABgmpIfwBAOcBAAAA.Feyu:BAEALgAECgYJCQABLgAECggJGAAVAD4ZAA==.',
Fh='Fhatbashtud:BAAALgADCgkJHgAAAA==.',
Fi='Fireflies:BAAALgAFFAMJAwAAAA==.Firelore:BAAALgAECgcJAwABLgAECgkJCAACAAAAAA==.',
Fl='Flatline:BAAALgAECgQJCgAAAA==.Flattymatty:BAAALgADCgYJBgAAAA==.Flöti:BAEBLgAECn8YAAIVAAgJPhkhHQAxAgAVAAgJPhkhHQAxAgAAAA==.',
Fo='Four:BAABLgAECn8YAAIKAAcJAg9mSgArAQAKAAcJAg9mSgArAQAAAA==.',
Fr='Frostnips:BAAALgAECgYJCQAAAA==.Frysky:BAABLgAECn8UAAIdAAYJ+Q2BGQDkAAAdAAYJ+Q2BGQDkAAAAAA==.',
Fu='Furytotem:BAAALgADCgMJAwABLgAECgUJBwACAAAAAA==.Futz:BAAALgAECgYJDgAAAA==.Fuzzymage:BAAALgADCgYJBgAAAA==.',
Ga='Gadrolicus:BAAALgADCgEJAQAAAA==.Galadriell:BAABLgAECn8aAAMLAAgJMhp2FQDmAQALAAgJMhp2FQDmAQAeAAYJmQ8VQwBKAQAAAA==.Gargahmell:BAAALgADCgUJBQAAAA==.',
Ge='Gengarr:BAAALgAECgEJAQAAAA==.',
Gn='Gnomes:BAAALgADCgcJBwAAAA==.',
Go='Gooberz:BAAALgADCgYJBgAAAA==.Goobs:BAAALgADCgcJDwAAAA==.Goonxoxo:BAAALgADCgUJCAAAAA==.Gordoe:BAAALgADCgUJBQAAAA==.Gothberry:BAAALgADCgUJBgAAAA==.',
Gr='Graveborne:BAAALgADCgkJGwAAAA==.Gravess:BAABLgAECn8tAAMcAAkJXxuvAACDAgAcAAkJXxuvAACDAgAbAAIJThSVDQCTAAAAAA==.Gravewin:BAAALgADCgIJAgABLgAECgUJBQACAAAAAA==.Grendelheim:BAAALgADCgkJFwAAAA==.Grogar:BAAALgADCgMJAwAAAA==.',
Gu='Gurg:BAAALgAECgYJCwAAAA==.',
Gw='Gwynath:BAAALgAECgYJEQAAAA==.',
Ha='Hagrok:BAAALgADCgEJAQAAAA==.Haldael:BAAALgAECgMJAwAAAA==.Hammerfists:BAAALgAECgIJAQAAAA==.Hanbil:BAAALgAECgYJCwAAAA==.Handace:BAAALgAECgUJBQAAAA==.Hangezoe:BAAALgAECgIJAwABLgAECgcJEAACAAAAAA==.Hantak:BAAALgAECgIJAgAAAA==.Hathaendron:BAAALgADCgEJAQAAAA==.Hatsunemiku:BAAALgADCgcJDQAAAA==.Hawginmaw:BAAALgADCgMJAwAAAA==.',
He='Hemorrhagic:BAAALgADCgIJAgAAAA==.Heretic:BAAALgAECgMJAwAAAA==.',
Hi='Hiromi:BAABLgAECn8dAAIfAAgJSxF1EAAaAQAfAAgJSxF1EAAaAQAAAA==.',
Ho='Hoisin:BAABLgAECn8aAAIQAAgJ2RXdDgChAQAQAAgJ2RXdDgChAQAAAA==.Holyyballs:BAAALgAECgYJEgAAAA==.Hotrodbob:BAAALgAECgEJAgAAAA==.Hotshot:BAAALgADCgQJAwAAAA==.Howlymandel:BAAALgAECgMJAwABLgAECggJIAALAJURAA==.Hoytx:BAAALgAECgQJBAAAAA==.',
Hu='Huntstokill:BAAALgAECgMJBAAAAA==.Huskerfister:BAABLgAECn8lAAIRAAgJhiGNAwCFAgARAAgJhiGNAwCFAgAAAA==.Hussion:BAAALgADCgMJAwAAAA==.',
['Hì']='Hìroko:BAAALgAECgQJCQAAAA==.',
Ia='Iaaryn:BAAALgAECgQJBAAAAA==.',
Ic='Icedemon:BAAALgAECgEJAgAAAA==.Icey:BAAALgADCgEJAgAAAA==.',
Il='Illiderp:BAAALgAECgQJCAABLgAECgQJDQACAAAAAA==.',
Im='Imananji:BAAALgAECgMJBAABLgAFFAQJCQAdAJ4OAA==.Imasurvivor:BAAALgADCgYJBgAAAA==.Imblind:BAABLgAECn8YAAIgAAYJOyLFGgCUAQAgAAYJOyLFGgCUAQAAAA==.Imperius:BAAALgADCgMJAwABLgAECgYJDgACAAAAAA==.',
In='Infernodruid:BAAALgAECgIJAgABLgAECgUJBwACAAAAAA==.Infinitie:BAAALgAECgEJAQAAAA==.Insillico:BAAALgAECgQJCwAAAA==.',
Io='Iog:BAAALgAECgYJBgAAAA==.',
Ip='Iplaydead:BAABLgAECn8WAAILAAYJiBb7LwBQAQALAAYJiBb7LwBQAQAAAA==.',
Ir='Iroh:BAAALgAECgYJEQAAAA==.Irondali:BAAALgADCgYJBgAAAA==.',
Is='Ismokeprot:BAAALgAECgEJAQAAAA==.',
Ja='Jakub:BAAALgAECgYJBwAAAA==.Jarinduva:BAAALgADCgcJFAAAAA==.Jawnson:BAABLgAECn8hAAMSAAgJtRPuBwDxAQASAAgJtRPuBwDxAQAbAAIJ8RK3GABqAAAAAA==.',
Je='Jeffo:BAAALgAECgMJBQAAAA==.Jenefer:BAACLgAFFH8LAAMHAAQJYxMyBwAnAQAHAAQJYxMyBwAnAQAIAAEJRgc/VgBNAAAuAAQKfyIAAgcACAl9IZ0GAMwCAAcACAl9IZ0GAMwCAAAA.Jerzak:BAAALgADCgYJCwAAAA==.',
Jo='Joemomo:BAAALgAECgYJDwAAAA==.Joethebull:BAAALgADCgQJBAAAAA==.Johnbasilone:BAAALgAECgEJAgABLgAECgMJBAACAAAAAA==.Johnmoo:BAAALgADCgIJAgAAAA==.Johnthick:BAAALgADCgcJFAAAAA==.Jokerninja:BAAALgAECgYJCgAAAA==.Jondooss:BAAALgADCgkJEwAAAA==.Jonsholo:BAAALgAECgIJAwAAAA==.Josefina:BAAALgAECgMJBQAAAA==.',
Ju='Jubelum:BAAALgADCgQJBAAAAA==.',
Ka='Kailback:BAAALgAECgYJBgAAAA==.Kait:BAABLgAECn8kAAMVAAgJAB2QDgAIAgAVAAgJAB2QDgAIAgAhAAMJ3gdAJACVAAAAAA==.Kakarotto:BAAALgAECgMJAwABLgAECgUJBQACAAAAAA==.Kaladin:BAAALgAECgUJCgAAAA==.Kalcifur:BAACLgAFFH8KAAIOAAQJzArCDQAgAQAOAAQJzArCDQAgAQAuAAQKfyMAAg4ACAm0FD8qAOABAA4ACAm0FD8qAOABAAAA.Kaseofbeer:BAAALgAECgEJAgAAAA==.Kashisht:BAAALgADCgIJAgAAAA==.Kassanovva:BAAALgADCgIJAgABLgAFFAQJCwAHAGMTAA==.Kasstigate:BAAALgAECgYJEAABLgAFFAQJCwAHAGMTAA==.Kastiel:BAAALgAECgQJBQABLgAECgYJEQACAAAAAA==.Kathtel:BAAALgAECgYJEgAAAA==.Katstrider:BAABLgAECn8ZAAILAAYJMBMuMQBMAQALAAYJMBMuMQBMAQAAAA==.Kattarea:BAAALgADCgkJGQABLgAECgYJGQALADATAA==.Kavica:BAAALgAECgYJCwABLgAECggJKAAFAM8jAA==.Kayotic:BAAALgADCgUJBQAAAA==.',
Ke='Kekw:BAAALgAECgUJDAAAAA==.Keldean:BAABLgAECn8bAAIfAAYJ6BtUCgCFAQAfAAYJ6BtUCgCFAQAAAA==.Kenji:BAAALgAECgEJAgAAAA==.Keryka:BAACLgAFFH8GAAIIAAMJzBugLgAGAQAIAAMJzBugLgAGAQAuAAQKfx8AAggACAlfIWEWAPYCAAgACAlfIWEWAPYCAAAA.Keybomb:BAAALgAECgYJBgAAAA==.',
Kh='Khall:BAAALgAFFAEJAQAAAA==.Khere:BAAALgAECgEJAQAAAA==.',
Ki='Kirigiri:BAABLgAECn8UAAMFAAcJTwzrbwAFAQAFAAcJTwzrbwAFAQAdAAEJAAA9NAAlAAABLgAFFAQJCgAOAMwKAA==.Kirøs:BAAALgAECgUJBQAAAA==.Kitanâ:BAAALgADCgMJBAAAAA==.Kiwi:BAAALgADCgcJDAAAAA==.',
Kn='Knom:BAAALgAECgQJAwAAAA==.',
Ko='Kohn:BAABLgAECn8WAAIOAAcJEyULCQDfAgAOAAcJEyULCQDfAgAAAA==.Kovalo:BAAALgAECgMJBAAAAA==.',
Kp='Kpegz:BAAALgADCgcJBwABLgAECgkJIwAKAOkeAA==.',
Kr='Krisjian:BAAALgADCgUJBQAAAA==.Kroh:BAACLgAFFH8KAAIiAAQJnBCeAQBjAQAiAAQJnBCeAQBjAQAuAAQKfx4AAiIACQlOIusEAMYCACIACQlOIusEAMYCAAAA.',
Ku='Kungfugriff:BAAALgAECgMJBAAAAA==.',
Ky='Kytana:BAAALgADCgQJBAAAAA==.',
La='Laisidhiel:BAAALgAECgQJBAAAAA==.Lateo:BAABLgAECn8lAAISAAgJrwzDKQCtAQASAAgJrwzDKQCtAQAAAA==.Lawz:BAABLgAECn8WAAQTAAcJIwZJDgDGAAATAAcJIwZJDgDGAAANAAYJHQM5gwB0AAAMAAEJuQOWEQAwAAAAAA==.',
Le='Leafz:BAABLgAECn8YAAIFAAgJ6RTdHACZAQAFAAgJ6RTdHACZAQAAAA==.Leaonissa:BAAALgAECgEJAQAAAA==.Learn:BAAALgADCgYJBgAAAA==.Leleb:BAAALgAECgUJDAAAAA==.Lelianna:BAAALgADCgkJGQAAAA==.Lemonruss:BAABLgAECn8hAAIKAAkJExhpLABxAgAKAAkJExhpLABxAgAAAA==.Leshafrierne:BAAALgAECgQJBAABLgAECgUJBgACAAAAAA==.Leshen:BAAALgAECgUJCAAAAA==.Lexia:BAABLgAECn8XAAMTAAcJdgV6DQDPAAATAAcJdgV6DQDPAAANAAUJVgIKfACJAAAAAA==.',
Li='Lilturtz:BAAALgAECgEJAQABLgAECgYJEwACAAAAAA==.Linnea:BAAALgAECgMJAwAAAA==.',
Lo='Loabones:BAAALgADCgcJDwAAAA==.Longhorn:BAAALgAECgYJDwAAAA==.Loni:BAAALgAECgYJDQAAAA==.Lookitsopz:BAAALgADCgQJBAAAAA==.Lorrenna:BAAALgAECgIJBQAAAA==.Lorrien:BAAALgAECgQJBAAAAA==.Lorré:BAAALgAECgYJBgABLgAECgQJBAACAAAAAA==.Lortpegsalot:BAABLgAECn8jAAIKAAkJ6R7HCwBrAgAKAAkJ6R7HCwBrAgAAAA==.Lostcause:BAAALgAECgEJAQAAAA==.',
Lu='Lucena:BAABLgAECn8XAAIjAAYJ7SARFwAjAgAjAAYJ7SARFwAjAgAAAA==.',
['Lö']='Lörö:BAAALgADCgQJBAAAAA==.',
Ma='Madamkluck:BAABLgAECn8YAAIFAAcJGB1JDgApAgAFAAcJGB1JDgApAgAAAA==.Maglubiyet:BAAALgAECgUJDwAAAA==.Magoz:BAAALgADCgYJCQAAAA==.Manhole:BAAALgAECgUJCQAAAA==.Markyb:BAABLgAECn8gAAIKAAgJyw2/NABwAQAKAAgJyw2/NABwAQAAAA==.Masamura:BAACLgAFFH8NAAIJAAUJNx1UFQBsAQAJAAUJNx1UFQBsAQAuAAQKfykAAgkACAkEITotAL0CAAkACAkEITotAL0CAAAA.Mattor:BAAALgADCgYJBgABLgAECgcJEAACAAAAAA==.Maureanna:BAABLgAECn8sAAIFAAcJ0hsDEgD7AQAFAAcJ0hsDEgD7AQAAAA==.Mavralle:BAAALgAECgUJBQAAAA==.',
Me='Medari:BAEBLgAECn8WAAIZAAgJGxflAwBIAgAZAAgJGxflAwBIAgAAAA==.Melorm:BAAALgAECgIJAgAAAA==.',
Mi='Minipig:BAAALgAECgIJAgAAAA==.Mirasharu:BAAALgADCgkJEgAAAA==.Mireille:BAAALgADCgkJEwAAAA==.Miseria:BAAALgADCgIJAgAAAA==.Mitsuri:BAAALgAECgcJCQAAAA==.',
Mn='Mnkyman:BAAALgAECgQJBAAAAA==.',
Mo='Mommamoon:BAAALgAECgYJBgABLgAECgcJDwACAAAAAA==.Monachier:BAAALgAECgUJBgAAAA==.Moonkin:BAAALgAECgUJCAAAAA==.Moonlïght:BAAALgAECgcJDwAAAA==.Moonrage:BAAALgADCgcJCwABLgAECgcJDwACAAAAAA==.Moose:BAAALgAECgYJEQAAAA==.Morganlefay:BAABLgAECn8bAAINAAYJmgGkhgBuAAANAAYJmgGkhgBuAAAAAA==.Morgona:BAAALgADCgEJAQAAAA==.Morlyn:BAAALgAECgYJEgAAAA==.Mosho:BAAALgAECgEJAQABLgAFFAYJGgASAIsXAA==.Mousemist:BAABLgAECn8dAAMRAAYJTx2KEQBpAQARAAYJTx2KEQBpAQAGAAUJ1ARtTACkAAAAAA==.',
Mu='Mulangar:BAAALgADCgEJAQAAAA==.',
My='Mynameiskase:BAAALgAECgYJEQAAAA==.Mystìc:BAAALgAECgQJCwAAAA==.',
['Má']='Májorrobot:BAAALgAECgMJBQAAAA==.',
['Mä']='Mänjo:BAAALgAECgcJDwAAAA==.',
['Mó']='Móldy:BAAALgAECgEJAgAAAA==.',
['Mö']='Mönkey:BAAALgADCgQJBAAAAA==.',
Na='Nale:BAAALgADCgcJFwAAAA==.Namesgambit:BAAALgAECgEJAQABLgAECggJIQAQAEQlAA==.Namor:BAAALgADCgYJBgAAAA==.Nasforatu:BAAALgADCgUJBgAAAA==.Nattisca:BAAALgAECgIJAgAAAA==.Navani:BAAALgAECgUJCgAAAA==.',
Ne='Nedtusk:BAEALgADCgYJCQABLgAECggJIgAPAKYSAA==.Nedvox:BAEBLgAECn8iAAIPAAgJphKMDwCSAQAPAAgJphKMDwCSAQAAAA==.Nervous:BAAALgAECgQJCwABLgAECgkJCAACAAAAAA==.Nessà:BAAALgAECgMJBQAAAA==.Neveenn:BAABLgAECn8eAAMFAAgJcBakJwAXAgAFAAgJcBakJwAXAgAkAAEJfAWESwApAAAAAA==.Neverbakdown:BAAALgAECgMJAwAAAA==.Neverclaws:BAAALgADCgEJAQAAAA==.Nevernoctis:BAAALgADCggJEwAAAA==.',
Ni='Nightpigas:BAAALgADCgIJAgABLgAECgUJDAACAAAAAA==.',
No='Nohatcat:BAAALgAECgYJEwAAAA==.Notoom:BAAALgAECgYJCgAAAA==.Noxle:BAAALgADCgIJAgAAAA==.',
Ny='Nyxara:BAABLgAECn8UAAINAAcJhA4RNABbAQANAAcJhA4RNABbAQAAAA==.',
['Nè']='Nèzukõ:BAAALgAECgYJEAAAAA==.',
['Nø']='Nøtfuriøus:BAAALgADCgYJBQABLgAECgYJCgACAAAAAA==.',
['Nÿ']='Nÿte:BAAALgADCgYJDwAAAA==.',
Oc='Octavius:BAAALgAECgEJAQABLgAECgQJBAACAAAAAA==.',
Od='Oddbrew:BAAALgADCgEJAQAAAA==.Oddsaga:BAAALgADCgYJBgAAAA==.',
Oj='Ojore:BAEALgAECgYJDgAAAA==.Ojoverde:BAACLgAFFH8FAAINAAMJpwLNOQC9AAANAAMJpwLNOQC9AAAuAAQKfyMAAg0ACAlzHHYkAIECAA0ACAlzHHYkAIECAAAA.',
On='Ontahli:BAAALgADCgUJBQABLgAECggJJAAEALgTAA==.',
Or='Orian:BAAALgAECgEJAQAAAA==.Orleron:BAAALgADCgEJAQAAAA==.',
Ov='Overflare:BAAALgADCgMJBAAAAA==.',
Ow='Ow:BAAALgADCgUJCQAAAA==.',
Oz='Ozmà:BAAALgAECgUJDAAAAA==.Ozzfu:BAAALgAECgQJBwAAAA==.Ozzsamdi:BAAALgAECgEJAQAAAA==.Ozzskelmir:BAAALgADCgYJDAAAAA==.',
Pa='Pajamas:BAAALgAECgYJEAAAAA==.Pallanquin:BAAALgAECgMJBQAAAA==.Pallywacker:BAAALgAECgQJCwAAAA==.Papichili:BAAALgADCgEJAQAAAA==.Pashnir:BAAALgADCggJCQAAAA==.',
Pe='Peachey:BAABLgAECn8WAAIVAAcJ/xUOFgC3AQAVAAcJ/xUOFgC3AQAAAA==.',
Ph='Phrantic:BAAALgAECgMJBAAAAA==.Phö:BAAALgADCgcJBwAAAA==.',
Pi='Pigas:BAAALgAECgUJDAAAAA==.Pikkel:BAAALgADCgIJAgAAAA==.Pillory:BAAALgADCgYJBgAAAA==.',
Pl='Platinïum:BAAALgAECgYJBgAAAA==.Playdoh:BAAALgADCgEJAQAAAA==.',
Pr='Priestling:BAAALgADCgkJDAAAAA==.Prncess:BAAALgAECgQJCAAAAA==.Prncsspuddlz:BAAALgAECgYJCwABLgAECgQJCAACAAAAAA==.',
Ps='Psychosix:BAABLgAECn8mAAIJAAgJSSO1BwC+AgAJAAgJSSO1BwC+AgAAAA==.Psychros:BAAALgAECgUJBQAAAA==.',
Pu='Puzzledmind:BAAALgAECgMJAwAAAA==.',
['Pø']='Pøintblank:BAAALgADCgEJAQAAAA==.',
Qi='Qimiao:BAAALgADCgYJDQAAAA==.',
Qu='Quinberos:BAAALgADCgQJBAABLgAECgMJBAACAAAAAA==.',
Ra='Radchad:BAAALgAECgMJBAAAAA==.Raiola:BAAALgAECgQJBQAAAA==.Rakuumn:BAAALgAECgEJAQABLgAECgEJAgACAAAAAA==.Ramdel:BAAALgADCgkJHgABLgAECgcJGwADABUbAA==.Ramstryder:BAABLgAECn8bAAIDAAcJFRsECgA8AgADAAcJFRsECgA8AgAAAA==.Rancidgravy:BAAALgADCgUJBgAAAA==.Rancor:BAAALgADCgEJAQAAAA==.Rapture:BAAALgADCgQJBAAAAA==.Rastabastion:BAACLgAFFH8OAAIfAAQJwCJuAgCLAQAfAAQJwCJuAgCLAQAuAAQKfxwAAh8ACAk6JdgCADYDAB8ACAk6JdgCADYDAAAA.',
Re='Rejuvanator:BAAALgADCgIJAgAAAA==.Rekmortal:BAABLgAFFH8HAAMlAAUJEBOGBABIAQAlAAUJEBOGBABIAQABAAEJiRIuIQBTAAAAAA==.Rekoj:BAAALgADCgQJBAAAAA==.Rengell:BAABLgAECn8gAAILAAgJlRF3GgDCAQALAAgJlRF3GgDCAQAAAA==.Resinya:BAAALgAECgYJBwAAAA==.Retnuh:BAAALgAECgEJAQAAAA==.',
Rh='Rheagall:BAAALgAECgYJDAAAAA==.Rheagnar:BAAALgADCgIJAgAAAA==.',
Rm='Rmeech:BAAALgAECgYJDAAAAA==.',
Ro='Rowena:BAABLgAECn8rAAIkAAkJfRo4FQBnAgAkAAkJfRo4FQBnAgAAAA==.Rowynna:BAAALgAECgMJBAAAAA==.Roxydk:BAAALgAECgcJCQAAAA==.Roxymonk:BAAALgAECgcJCQAAAA==.',
Ru='Ruxspin:BAAALgAECgUJCQAAAA==.',
Ry='Ryzedvoid:BAAALgAECgYJEAAAAA==.Ryzinneko:BAABLgAECn8jAAIFAAkJ6x+ACQBzAgAFAAkJ6x+ACQBzAgAAAA==.',
Sa='Sabend:BAACLgAFFH8SAAINAAYJ7RCiCACNAQANAAYJ7RCiCACNAQAuAAQKfx8AAw0ACAmfHVopAGsCAA0ACAmfHVopAGsCABMAAQkAAFtmAEMAAAAA.Sablewolfe:BAAALgAECgIJAwAAAA==.Safaria:BAAALgAECgUJEQAAAA==.Sarlyssa:BAAALgADCgkJEQAAAA==.Saucymac:BAACLgAFFH8IAAIPAAMJpQzWDQDpAAAPAAMJpQzWDQDpAAAuAAQKfyQAAg8ACAkJIe4KANQCAA8ACAkJIe4KANQCAAAA.',
Sc='Scofflaw:BAAALgADCgYJBgAAAA==.',
Se='Senath:BAABLgAECn8YAAMSAAcJXhwWDwB8AQASAAYJPxwWDwB8AQAbAAEJ+Bw6EQBVAAAAAA==.Sephrenia:BAAALgADCgUJCQAAAA==.Serandipity:BAAALgAECgYJBwABLgAFFAQJCwAHAGMTAA==.Seraphina:BAAALgAECgEJAQAAAA==.',
Sh='Shalorath:BAAALgAECgcJEgAAAA==.Shamanagans:BAAALgADCggJCAAAAA==.Shamanigans:BAAALgAECgcJEgAAAA==.Shammygoat:BAAALgAECgYJEQAAAA==.Shamncheese:BAAALgAECgQJAwAAAA==.Shania:BAAALgADCgUJBQAAAA==.Shaosun:BAAALgAECgYJDgAAAA==.Shaqattack:BAACLgAFFH8FAAIRAAMJjxDhCwDkAAARAAMJjxDhCwDkAAAuAAQKfxoAAhEACAkYI0wGABwDABEACAkYI0wGABwDAAAA.Shaqattaq:BAAALgAECgYJCgABLgAFFAMJBQARAI8QAA==.Sharkmeat:BAABLgAECn8dAAIPAAYJXx6kDgCdAQAPAAYJXx6kDgCdAQAAAA==.Sharktide:BAAALgADCgkJCQAAAA==.Shauriena:BAAALgADCgUJBwAAAA==.Shawnellie:BAAALgAECgcJDAAAAA==.Shawntelle:BAABLgAECn8VAAIDAAcJ7yOpBQCvAgADAAcJ7yOpBQCvAgAAAA==.Shenlune:BAAALgAECgMJBQAAAA==.Sheutka:BAAALgAECgUJCQAAAA==.Shinaie:BAABLgAECn8YAAIPAAcJNApTGQA0AQAPAAcJNApTGQA0AQAAAA==.Shockanduwu:BAAALgAECgYJEgAAAA==.Shruikan:BAAALgADCgYJDAABLgAECgcJEAACAAAAAA==.Shtylez:BAAALgADCgYJBgAAAA==.',
Si='Sigzil:BAAALgADCgUJCQAAAA==.Silth:BAAALgADCgkJFgAAAA==.Silvermisst:BAAALgAECgQJBAAAAA==.Silvermist:BAAALgADCgUJBQAAAA==.Silvertouch:BAAALgAECgEJAQABLgAECgUJBwACAAAAAA==.Sinariel:BAABLgAECn8VAAMGAAYJxRu1DADbAQAGAAYJxRu1DADbAQARAAYJWRXRKgCHAQAAAA==.Sirdank:BAAALgADCgMJAwAAAA==.Sithus:BAAALgADCgQJBAAAAA==.',
Sl='Sliko:BAAALgAECgcJEAAAAA==.',
Sm='Smmoke:BAABLgAECn8hAAILAAgJMRsuFwDZAQALAAgJMRsuFwDZAQAAAA==.Smorko:BAAALgADCgYJBgAAAA==.',
Sn='Sneekypally:BAAALgAECgMJAwAAAA==.Sniperart:BAAALgAECgcJEwABLgAECggJCgACAAAAAA==.',
So='Soull:BAABLgAECn8ZAAIFAAgJeBrsFQDUAQAFAAgJeBrsFQDUAQAAAA==.',
Sp='Spacemoo:BAABLgAECn8XAAIIAAcJhh2nFgAFAgAIAAcJhh2nFgAFAgAAAA==.',
Sq='Squall:BAAALgADCgcJCAAAAA==.',
St='Starface:BAACLgAFFH8JAAIdAAQJng7UAwDiAAAdAAQJng7UAwDiAAAuAAQKfyMAAx0ACAkYH7IEAKACAB0ACAkYH7IEAKACAAUAAQk9AerpABsAAAAA.Starrlyte:BAAALgADCgUJBQAAAA==.Steelytree:BAAALgAECgEJAQAAAA==.Stefane:BAAALgAECgYJCAAAAA==.Steverogers:BAAALgAECgEJBQABLgAECggJIQAQAEQlAA==.Stocktonrush:BAAALgAECgEJAgABLgAECggJIQAQAEQlAA==.Stonewillow:BAAALgADCgUJBQAAAA==.Stormoond:BAAALgADCgEJAQAAAA==.Strongbad:BAAALgAECgQJDAAAAA==.Sturmx:BAABLgAECn8hAAImAAgJihm7BQANAgAmAAgJihm7BQANAgAAAA==.',
Su='Subaaâ:BAABLgAECn8gAAMWAAgJTiMGAQAzAwAWAAgJTiMGAQAzAwAgAAUJIhQuhgAaAQABLgAECgYJJQABADggAA==.Subby:BAAALgADCgUJDQAAAA==.Subedei:BAABLgAECn8mAAMHAAkJbiFDBgDTAgAHAAgJcyFDBgDTAgAIAAUJ5Bow1ADYAAAAAA==.Sukati:BAAALgADCgMJAwAAAA==.Sunderhorn:BAAALgAECgUJCQAAAA==.Sutherman:BAAALgAECgEJAQAAAA==.',
Sv='Svictis:BAABLgAECn8eAAIIAAcJ0xLnQAA7AQAIAAcJ0xLnQAA7AQAAAA==.Sviictis:BAAALgADCggJEgAAAA==.',
Sw='Swab:BAAALgADCgEJAQABLgADCgcJFwACAAAAAA==.Swami:BAAALgADCgQJBAAAAA==.',
Sy='Syluxs:BAAALgAECgcJEQAAAA==.Syrony:BAAALgADCgMJAwAAAA==.',
['Sû']='Sûshealä:BAAALgAECgYJEAAAAA==.',
Ta='Tadryth:BAAALgADCgQJBQAAAA==.Talila:BAABLgAECn8ZAAIdAAYJ8h2gCgDtAQAdAAYJ8h2gCgDtAQAAAA==.Tamashi:BAAALgADCgIJAgAAAA==.Taxter:BAAALgADCgEJAQAAAA==.',
Te='Tealzitaz:BAAALgAECgEJAgAAAA==.Terrya:BAAALgADCgYJBgAAAA==.Teryail:BAAALgADCgEJAQAAAA==.',
Th='Thallion:BAAALgAECgMJBAAAAA==.Thalorian:BAAALgADCgIJAgAAAA==.Tharaa:BAAALgAECgUJBwAAAA==.',
Ti='Tickle:BAAALgAECgcJEgAAAA==.Tiermorthius:BAAALgADCgYJBgABLgAECgUJBgACAAAAAA==.Tirithor:BAABLgAECn8hAAIKAAgJEBZ7VADkAQAKAAgJEBZ7VADkAQAAAA==.',
To='Tockell:BAAALgADCggJDQAAAA==.Tonakai:BAAALgAFFAIJAwAAAA==.Tony:BAAALgAECgYJCgAAAA==.Torbin:BAAALgAECgYJDQAAAA==.Touchmywave:BAAALgADCgUJCAABLgAECgcJEgACAAAAAA==.',
Tr='Tricks:BAAALgAECgcJEAAAAA==.Trilleon:BAAALgAECgUJBQAAAA==.Trillis:BAAALgAECgIJAgABLgAECgUJBQACAAAAAA==.Tryjincks:BAAALgAECgYJDAAAAA==.Tryjinks:BAAALgAECgUJBgABLgAECgYJDAACAAAAAA==.',
Ts='Tserendolgor:BAAALgADCgEJAQAAAA==.',
Tu='Turgà:BAAALgADCgEJAgABLgAECgMJBQACAAAAAA==.',
Ty='Tykahndrius:BAAALgAECgEJAQAAAA==.Tys:BAAALgADCgQJBAAAAA==.',
['Tú']='Túsk:BAAALgAECgYJBgAAAA==.',
['Tý']='Týlïus:BAAALgAECgYJEgAAAA==.',
Ud='Uddergrace:BAAALgADCgEJAQAAAA==.',
Un='Unspokenword:BAAALgADCgcJFwAAAA==.',
Ut='Uthilon:BAABLgAECn8gAAIaAAgJWSKJAQCcAgAaAAgJWSKJAQCcAgAAAA==.',
Va='Vaeredor:BAAALgADCgIJAgAAAA==.Valdare:BAAALgAECgYJEwAAAA==.',
Ve='Vedillian:BAABLgAECn8VAAIcAAgJRwnFBQB8AQAcAAgJRwnFBQB8AQAAAA==.Velyndrenis:BAAALgADCgEJAgAAAA==.Vennaya:BAABLgAECn8UAAIjAAgJSgiLIAD9AAAjAAgJSgiLIAD9AAAAAA==.Vethinrel:BAAALgADCgYJBgAAAA==.',
Vi='Victorr:BAAALgAECgEJAQAAAA==.Viktorius:BAAALgADCgYJBgAAAA==.Violentpanda:BAAALgAECgUJCwAAAA==.Vite:BAAALgADCgcJGAAAAA==.Vixious:BAAALgADCgcJCwAAAA==.Vizigoth:BAABLgAECn8bAAMNAAgJugtNLQB3AQANAAcJWwpNLQB3AQATAAIJCxHvVwBnAAAAAA==.',
Vo='Voladon:BAAALgAECgcJEwAAAA==.Voyana:BAAALgAECgUJEQABLgAECgUJEQACAAAAAA==.',
Vy='Vydragon:BAAALgAFFAIJAgABLgAFFAQJCwAJAPEXAA==.Vymage:BAACLgAFFH8LAAIJAAQJ8Rc1FwBnAQAJAAQJ8Rc1FwBnAQAuAAQKfyEAAwkACAkaJEMSADoDAAkACAkaJEMSADoDACcAAQngDnEIADkAAAAA.',
['Vá']='Válidüs:BAACLgAFFH8OAAIjAAUJow6SAwB2AQAjAAUJow6SAwB2AQAuAAQKfxwAAiMACQkJGMwLAJQCACMACQkJGMwLAJQCAAAA.',
['Vã']='Vãsh:BAAALgAECgQJBwAAAA==.',
Wa='Wanitou:BAAALgADCgMJAwAAAA==.Warninja:BAAALgAECgYJCwAAAA==.Waterloo:BAAALgADCgkJGQAAAA==.',
We='Weejas:BAAALgADCgMJAwAAAA==.Werwick:BAAALgAECgEJAQAAAA==.',
Wh='Whatsnail:BAABLgAECn8cAAIJAAgJpAlFaQAIAQAJAAgJpAlFaQAIAQAAAA==.',
Wi='Wizdom:BAAALgADCgQJBAAAAA==.',
Wr='Wrathidan:BAAALgAECgYJDAAAAA==.',
['Wì']='Wìccka:BAAALgAECgYJDgAAAA==.',
Xi='Xifan:BAAALgAECgEJAgAAAA==.',
Ya='Yalper:BAAALgADCgcJCwAAAA==.',
Yo='Youngwokongs:BAAALgADCgIJAgAAAA==.',
Yu='Yudie:BAABLgAECn8UAAIGAAYJoA6rNQAYAQAGAAYJoA6rNQAYAQAAAA==.',
Yz='Yz:BAAALgAECgYJBwAAAA==.',
Za='Zalysi:BAABLgAECn8WAAMOAAgJHBLfJwDtAQAOAAgJHBLfJwDtAQAKAAIJkQdGHwFeAAAAAA==.Zam:BAABLgAECn8dAAMBAAcJ5B3WHwBSAgABAAcJsRrWHwBSAgAlAAMJwBhIGgCoAAAAAA==.Zamantha:BAAALgADCgIJAgAAAA==.Zanny:BAAALgADCgMJAwAAAA==.Zashawa:BAAALgADCgUJBgAAAA==.Zashen:BAAALgAECgYJDAAAAA==.',
Ze='Zebb:BAAALgADCgcJDQAAAA==.Zelix:BAAALgADCgEJAQAAAA==.Zenmist:BAAALgAECgUJBwAAAA==.Zeylanica:BAAALgAECgEJAQABLgAFFAQJCQAdAJ4OAA==.',
Zh='Zhastr:BAAALgAECgMJAwAAAA==.',
Zl='Zllusion:BAAALgADCgMJAwAAAA==.Zlucu:BAAALgAECgMJAwABLgAFFAQJCAANAKATAA==.Zlufernal:BAACLgAFFH8IAAINAAQJoBOwLQDsAAANAAQJoBOwLQDsAAAuAAQKfyQAAg0ACAkIJVYNAA8DAA0ACAkIJVYNAA8DAAAA.',
Zy='Zyn:BAABLgAECn8bAAIBAAcJDA6nGgBaAQABAAcJDA6nGgBaAQAAAA==.',
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
