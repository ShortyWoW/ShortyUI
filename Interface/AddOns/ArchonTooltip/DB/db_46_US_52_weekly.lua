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

local lookup = {'Hunter-BeastMastery','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Priest-Shadow','Priest-Holy','Shaman-Restoration','Mage-Frost','Monk-Mistweaver','Unknown-Unknown','Paladin-Holy','Druid-Restoration','DemonHunter-Vengeance','Monk-Brewmaster','Shaman-Elemental','Paladin-Retribution','DeathKnight-Unholy','DeathKnight-Blood','DemonHunter-Devourer','Paladin-Protection','Druid-Guardian','Mage-Fire','Warrior-Fury','Shaman-Enhancement','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Druid-Balance','Warrior-Arms','DemonHunter-Havoc','Hunter-Survival','Hunter-Marksmanship','Mage-Arcane','Monk-Windwalker','DeathKnight-Frost','Rogue-Subtlety','Druid-Feral','Priest-Discipline','Warrior-Protection','Rogue-Assassination',}
local provider = {region='US',realm="Cho'gall",name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abeblinken:BAAALgAECgMJAwAAAA==.',
Ad='Adym:BAABLgAECn8ZAAIBAAkJNxnzHABYAgABAAkJNxnzHABYAgAAAA==.',
Ae='Aethos:BAABLgAECn8wAAQCAAgJrxmjEAAhAgACAAgJrxmjEAAhAgADAAIJqBlHHABNAAAEAAEJ+xcTKwBJAAAAAA==.Aeyther:BAABLgAECn8WAAMFAAkJfRiIGgALAgAFAAkJfRiIGgALAgAGAAIJgBJCawB+AAAAAA==.',
Ag='Agave:BAABLgAECn8jAAIHAAgJ7hPmPwCBAQAHAAgJ7hPmPwCBAQAAAA==.Agony:BAAALgAECgEJAQAAAA==.',
Ah='Ahluethedrud:BAAALgADCgUJBQAAAA==.',
Ai='Airbnb:BAAALgADCgQJBAAAAA==.',
Al='Aleynah:BAAALgADCggJGgABLgAECggJKwADAA8JAA==.Alukarrd:BAAALgAECgMJBAAAAA==.',
Am='Amoraniel:BAABLgAECn8gAAIIAAgJHyLiDgBnAgAIAAgJHyLiDgBnAgAAAA==.Amortin:BAAALgADCgEJAQAAAA==.',
An='Anavar:BAABLgAECn8dAAIJAAkJJBrQDgBpAgAJAAkJJBrQDgBpAgAAAA==.Ancestral:BAAALgADCgEJAQABLgAECgkJFAAKAAAAAA==.Andrar:BAAALgADCgEJAQAAAA==.Andresra:BAABLgAECn8UAAIIAAcJ3RcbZwAJAgAIAAcJ3RcbZwAJAgAAAA==.Angelle:BAABLgAECn8kAAILAAgJHyTRCgDKAgALAAgJHyTRCgDKAgAAAA==.Annakin:BAABLgAECn8cAAIMAAgJyxp8IgA0AgAMAAgJyxp8IgA0AgAAAA==.Annaluna:BAAALgAECgUJBQAAAA==.Anomally:BAAALgADCgMJAwAAAA==.Anzhelika:BAAALgADCgMJAwAAAA==.',
Ar='Arararagi:BAAALgAECgUJBQAAAA==.Arawn:BAAALgADCgYJBgAAAA==.Arctica:BAABLgAECn8kAAINAAgJ5x7NAwCPAgANAAgJ5x7NAwCPAgAAAA==.Arelà:BAAALgAFFAEJAgAAAA==.Aria:BAABLgAECn8YAAIJAAYJdCIHBwBNAgAJAAYJdCIHBwBNAgAAAA==.Arron:BAAALgAECgIJAgAAAA==.Arrowsnag:BAAALgAECgQJBAAAAA==.Articdemon:BAAALgADCgkJFAAAAA==.Artics:BAAALgAECgEJAQAAAA==.Arya:BAAALgAECgkJCgAAAA==.Arylynn:BAAALgADCgYJBgABLgAECggJIQAOAHUlAA==.',
As='Astradaeus:BAAALgADCgMJAwAAAA==.Astridaya:BAAALgAECgEJAwAAAA==.',
Au='Aunumator:BAAALgADCgcJEAAAAA==.',
Av='Avâtre:BAABLgAECn8bAAIPAAgJBhWGFgBgAQAPAAgJBhWGFgBgAQAAAA==.',
Ba='Baba:BAAALgADCgcJAQAAAA==.Baccaj:BAAALgAECgEJAQAAAA==.Baeblue:BAAALgAECgYJCAABLgAECggJGQAQAB8YAA==.Bajingobomb:BAABLgAECn8gAAMRAAgJiR8MLwB8AgARAAgJiR8MLwB8AgASAAEJpREpRgAvAAAAAA==.Baked:BAAALgADCgIJAgAAAA==.Ballmelazer:BAAALgAECgEJAQAAAA==.Barasuishou:BAAALgAECgEJAQABLgAECgcJGwAEAGsgAA==.Barkruffalo:BAABLgAECn8oAAIMAAgJESBFBgCzAgAMAAgJESBFBgCzAgAAAA==.Barkwoven:BAAALgADCgcJBwAAAA==.Battleborne:BAAALgAECgEJAQAAAA==.Bayln:BAAALgADCgcJBgABLgABCgUJBQAKAAAAAA==.',
Be='Beckyoncé:BAABLgAECn8lAAITAAgJhSJkCgA1AgATAAgJhSJkCgA1AgAAAA==.Bedris:BAABLgAECn8aAAMQAAgJtg1dMgB5AQAQAAgJngxdMgB5AQAUAAUJUAthKwCyAAAAAA==.Beerticus:BAAALgAECgYJCgAAAA==.Bekkar:BAAALgAECgEJAQAAAA==.Belcebu:BAAALgAECgEJAQAAAA==.Berim:BAAALgAECgQJBQAAAA==.',
Bi='Bigdingus:BAABLgAECn8ZAAIVAAkJPR2rBQB8AgAVAAkJPR2rBQB8AgAAAA==.Binggles:BAACLgAFFH8YAAMIAAYJrSCiBQDVAQAIAAYJrSCiBQDVAQAWAAEJXQHLAQBDAAAuAAQKfx8AAggACAl+JXsSADkDAAgACAl+JXsSADkDAAAA.Bingglestwo:BAAALgAECgMJAwABLgAFFAYJGAAIAK0gAA==.',
Bl='Blanketparty:BAABLgAECn8XAAMPAAcJthtZDADVAQAPAAcJthtZDADVAQAHAAEJVw+2YQAxAAAAAA==.Blinkyshadow:BAAALgADCgMJAwAAAA==.Bloodraven:BAACLgAFFH8FAAIMAAIJJCGbGgDHAAAMAAIJJCGbGgDHAAAuAAQKfyoAAgwACQm6HjoGALUCAAwACQm6HjoGALUCAAAA.Blëwm:BAAALgADCgcJDQABLgAECggJEwAKAAAAAA==.',
Bo='Boaj:BAACLgAFFH8GAAIXAAMJdQzWFgC3AAAXAAMJdQzWFgC3AAAuAAQKfxwAAhcACQlSFgYoAB0CABcACQlSFgYoAB0CAAAA.Bobette:BAABLgAECn8UAAIYAAgJDwg2FQBpAQAYAAgJDwg2FQBpAQAAAA==.Bodyspray:BAABLgAECn8YAAIQAAgJDRyqGAD3AQAQAAgJDRyqGAD3AQAAAA==.Boolay:BAABLgAECn8XAAIUAAgJ9RtTDAACAgAUAAgJ9RtTDAACAgAAAA==.Bootyfire:BAABLgAECn8ZAAIIAAgJ9RF/aAAFAgAIAAgJ9RF/aAAFAgAAAA==.Boozing:BAAALgAECgEJAgAAAA==.Bosmina:BAACLgAFFH8FAAIGAAIJPwlaEAB0AAAGAAIJPwlaEAB0AAAuAAQKfyoAAgYACQk9ETENANABAAYACQk9ETENANABAAAA.',
Br='Braeibo:BAAALgAECgYJDQAAAA==.Breelynn:BAAALgADCgcJBwAAAA==.Breida:BAAALgAECgUJCAAAAA==.Brenmonk:BAAALgADCggJDgAAAA==.Brielle:BAAALgADCgEJAQAAAA==.Brolerion:BAAALgADCgQJBAAAAA==.',
Bu='Bubblebaddie:BAAALgAECgYJCwAAAA==.Bugenhagen:BAAALgAECgQJCgABLgAECgYJCQAKAAAAAA==.Buttpaladin:BAAALgAECggJCAAAAA==.',
['Bë']='Bëldin:BAAALgADCggJCwAAAA==.',
Ca='Canelo:BAAALgADCgUJBQAAAA==.Cantheal:BAAALgADCgYJBgAAAA==.Carademuerta:BAAALgAECgcJEAAAAA==.Cardib:BAABLgAFFH8FAAIRAAMJ9RubMAAAAQARAAMJ9RubMAAAAQAAAA==.Cavos:BAABLgAECn8oAAITAAgJ3RnvDAATAgATAAgJ3RnvDAATAgAAAA==.',
Ce='Cernsarn:BAABLgAECn8kAAISAAgJ/QxGFADhAAASAAgJ/QxGFADhAAAAAA==.',
Ch='Chandlef:BAAALgAECgQJBAAAAA==.Chantorc:BAAALgADCgYJCgAAAA==.Chickendad:BAAALgAECgUJBQAAAA==.Chigang:BAAALgADCgMJAwAAAA==.Chiri:BAEBLgAECn8bAAQZAAgJfBHnBABsAQAZAAcJXRDnBABsAQAaAAYJdQuKNQAkAQAbAAUJyQ3MGQBtAAAAAA==.Chvngus:BAABLgAECn8jAAIQAAgJsCCGBwChAgAQAAgJsCCGBwChAgAAAA==.',
Ci='Cindersam:BAAALgAECgYJCQABLgAECgcJFAARAK0UAA==.',
Cl='Clawsoh:BAAALgADCgkJCQAAAA==.Climene:BAAALgADCgYJBgABLgAECggJGQAQAB8YAA==.',
Co='Cocheeze:BAAALgAECgUJBQAAAA==.Condor:BAEBLgAECn8WAAIcAAgJZCO+AwCMAgAcAAgJZCO+AwCMAgAAAA==.Conmammoth:BAAALgAECgQJCgAAAA==.Coohwhip:BAAALgAECgcJEAAAAA==.Cowwithhorns:BAABLgAECn8cAAMXAAgJ1RRmKgAPAgAXAAgJIhJmKgAPAgAdAAQJ+BE5EQD9AAAAAA==.',
Cr='Cristobal:BAAALgAECggJDQAAAA==.Cronùs:BAAALgAECgcJCgAAAA==.Crunkshot:BAAALgAECgcJEwAAAA==.',
Cu='Curnsarn:BAAALgAECgQJBAABLgAECggJJAASAP0MAA==.Curtis:BAAALgAECgcJEwAAAA==.',
Cy='Cyalaterz:BAAALgAECgEJAQAAAA==.Cyrail:BAABLgAECn8kAAILAAgJtyTqAgDgAgALAAgJtyTqAgDgAgAAAA==.',
['Cø']='Cøven:BAABLgAECn8uAAMcAAkJ1h3LDADLAgAcAAkJ1h3LDADLAgAMAAQJiA9jnQCQAAAAAA==.',
Da='Dan:BAAALgAECgEJAQAAAA==.Darkmonks:BAAALgADCgYJBgAAAA==.Darksoulstwo:BAAALgAECgUJBQAAAA==.Darktoxi:BAABLgAECn8bAAIJAAgJ0hpSBgBgAgAJAAgJ0hpSBgBgAgAAAA==.Darthpooper:BAAALgAECgYJBgABLgAFFAIJBQAQAKMQAA==.Dastaan:BAAALgAECgEJAgAAAA==.Dauntus:BAACLgAFFH8JAAIIAAQJ3BHzIQBLAQAIAAQJ3BHzIQBLAQAuAAQKfyUAAggACQm/HFcRAFECAAgACQm/HFcRAFECAAAA.Dawnclaw:BAAALgADCgUJBQAAAA==.Daydream:BAAALgAECgEJAQAAAA==.',
De='Deathclock:BAABLgAECn8kAAIRAAkJsx0TDQAyAwARAAkJsx0TDQAyAwAAAA==.Deep:BAAALgADCgEJAQAAAA==.Degey:BAAALgAECgYJEAAAAA==.Deign:BAABLgAECn8iAAIeAAkJVwgxEAA6AQAeAAkJVwgxEAA6AQAAAA==.Delayne:BAAALgAECggJCQAAAA==.Demoncrat:BAAALgAFFAEJAQAAAA==.Demonicramen:BAAALgAECgIJAgAAAA==.Demonstroza:BAAALgAECgUJBQABLgAECggJCAAKAAAAAA==.Demontotems:BAAALgAECgMJCQAAAA==.Demotoxi:BAAALgAECgYJEwABLgAECggJGwAJANIaAA==.Deriso:BAAALgAECggJDQAAAA==.Derpthyr:BAAALgADCgMJAwAAAA==.Destrozinth:BAAALgAECggJCAAAAA==.Dethorok:BAABLgAECn8XAAQfAAcJZCIEBgARAgAfAAcJ6xwEBgARAgAgAAYJiCSRIgAPAgABAAUJfyAqJwB7AQAAAA==.Deuce:BAAALgAECgEJAQAAAA==.Deåth:BAAALgAECgUJBwAAAA==.',
Dh='Dhamon:BAAALgADCgYJBgAAAA==.',
Di='Dieworc:BAAALgADCgkJFgAAAA==.Digey:BAAALgAECggJEAAAAA==.Digitz:BAABLgAECn8cAAMIAAgJTBYGVwAzAgAIAAgJTBYGVwAzAgAhAAEJAAA/HgA1AAAAAA==.Direwolf:BAAALgAECgUJBgAAAA==.Dirtnapp:BAAALgAECgMJCAAAAA==.Divah:BAABLgAECn8rAAIDAAgJDwmJBwA6AQADAAgJDwmJBwA6AQAAAA==.',
Do='Dogehh:BAAALgADCgIJAgAAAA==.Donald:BAABLgAECn8cAAIBAAgJ3w8KHAC3AQABAAgJ3w8KHAC3AQAAAA==.Donbolo:BAAALgAECgUJCQAAAA==.Dopeaf:BAAALgAECgcJDgAAAA==.Dotpotato:BAAALgADCgIJAgAAAA==.Dotterparty:BAAALgAECgQJBAAAAA==.Dowkia:BAAALgAECgEJAgAAAA==.Downwarddog:BAAALgADCgYJBwAAAA==.',
Dr='Dragonmaas:BAAALgADCgYJBgAAAA==.Dragonwings:BAECLgAFFH8FAAIIAAIJTgPIVgCOAAAIAAIJTgPIVgCOAAAuAAQKfxgAAggABwk7Ft59ANUBAAgABwk7Ft59ANUBAAAA.Drakah:BAAALgAECgIJAgAAAA==.Drakbek:BAAALgAECgMJBwAAAA==.Dreaknite:BAAALgADCgQJBgAAAA==.Dreamshift:BAAALgAECgcJEwAAAA==.Dreco:BAABLgAECn8cAAITAAcJrh51FQC9AQATAAcJrh51FQC9AQAAAA==.Drekken:BAAALgAECgMJBQAAAA==.Drelik:BAAALgADCgIJAgAAAA==.Dronebot:BAABLgAECn8iAAMFAAgJNiDBAgCeAgAFAAgJNiDBAgCeAgAGAAMJngpbZwCPAAAAAA==.Drucifer:BAAALgAECgYJEgAAAA==.Druelf:BAAALgAECgMJAwAAAA==.Druiwny:BAAALgAECgMJAwAAAA==.Drúcifer:BAAALgADCgkJEgAAAA==.',
Du='Dud:BAABLgAECn8dAAICAAcJ/xyoFQD4AQACAAcJ/xyoFQD4AQAAAA==.Dugaa:BAAALgAECgQJBAAAAA==.Dumbdwagon:BAABLgAECn8kAAIbAAgJDAv0DQAhAQAbAAgJDAv0DQAhAQAAAA==.Dumblecrumb:BAAALgADCgQJBAAAAA==.Dumbrouge:BAAALgAECgIJAgABLgAECggJIQAUAHIUAA==.Dustyshotz:BAAALgAECgEJAQAAAA==.',
Dw='Dwall:BAAALgAECgMJAwAAAA==.Dwarriorarf:BAAALgAECgEJAwAAAA==.',
Dz='Dzieux:BAAALgADCgYJBwAAAA==.',
['Dë']='Dëadisbetter:BAAALgADCgEJAQAAAA==.',
['Dö']='Dögehh:BAAALgAECgYJBwAAAA==.',
Ee='Eeseo:BAAALgAECgEJAQAAAA==.',
Eg='Eggblack:BAAALgAECgQJBwAAAA==.',
El='Ellegryn:BAAALgADCgEJAgAAAA==.Elvebring:BAABLgAECn8bAAIeAAcJyBokGQD8AQAeAAcJyBokGQD8AQABLgAFFAMJBgALAFEaAA==.',
Em='Embody:BAABLgAECn8bAAIcAAgJaxF0DgCoAQAcAAgJaxF0DgCoAQAAAA==.',
En='Endlyss:BAAALgADCgcJBwAAAA==.',
Er='Erikira:BAAALgAECgUJCgAAAA==.Erikk:BAAALgAECgYJDgAAAA==.Eryngium:BAAALgAECgYJDAAAAA==.',
Es='Essentia:BAAALgAECgEJAQAAAA==.',
Et='Ethantherat:BAAALgAECgEJAQAAAA==.',
Eu='Euphoricx:BAABLgAECn8rAAIHAAkJQSb2AgBOAwAHAAkJQSb2AgBOAwAAAA==.',
Ev='Evildeader:BAAALgAECgcJEAAAAA==.Eviltotems:BAAALgAECgQJBAABLgAECgcJEAAKAAAAAA==.',
Ex='Exalt:BAAALgAECgYJBgAAAA==.Exes:BAAALgADCggJCAABLgAECgkJCgAKAAAAAA==.Expand:BAABLgAECn8WAAIiAAkJSRrXFQA7AgAiAAkJSRrXFQA7AgAAAA==.',
Ey='Eyeseyesbaby:BAAALgAECgcJEQAAAA==.',
Fa='Faithles:BAACLgAFFH8FAAIFAAIJ3hNMDwCqAAAFAAIJ3hNMDwCqAAAuAAQKfyYAAgUACQnfHHUCAKsCAAUACQnfHHUCAKsCAAAA.Falgur:BAACLgAFFH8FAAMPAAIJORCZFgCeAAAPAAIJORCZFgCeAAAHAAIJHAHIKABkAAAuAAQKfysAAw8ACQn4HoYCAMACAA8ACQn4HoYCAMACAAcAAwnFCS1HAIcAAAAA.Fantasma:BAAALgAECgQJBgAAAA==.Fasty:BAABLgAECn8gAAIJAAgJShTkHgC9AQAJAAgJShTkHgC9AQAAAA==.Faygochugger:BAAALgAECgQJBAAAAA==.',
Fe='Felmajik:BAAALgADCgMJBQAAAA==.',
Fi='Finley:BAAALgADCgMJAwAAAA==.Fivemagics:BAABLgAECn8VAAMCAAcJlxYNcACAAQACAAYJzRQNcACAAQADAAIJnhTMTgCBAAAAAA==.',
Fl='Flayvour:BAAALgAECgQJBAABLgAECggJEwAKAAAAAA==.Fleaboy:BAAALgAECgYJDgAAAA==.Fleshwound:BAAALgADCgYJBgAAAA==.Flist:BAABLgAECn8eAAIiAAgJJSQdDAC4AgAiAAgJJSQdDAC4AgAAAA==.',
Fo='Fongsaiyok:BAAALgAECgEJAQAAAA==.Foregord:BAAALgADCgUJBQABLgABCgUJBQAKAAAAAA==.Fortlock:BAAALgAECgQJBgAAAA==.Fotation:BAAALgAECgQJBAAAAA==.',
Fr='Frankensteyn:BAAALgADCgIJAgAAAA==.Frankyice:BAABLgAECn8ZAAIFAAgJjBCTDgCeAQAFAAgJjBCTDgCeAQAAAA==.Freesia:BAABLgAECn8VAAIQAAYJWBAbkABcAQAQAAYJWBAbkABcAQAAAA==.French:BAAALgAECggJDQAAAA==.Froggyfresh:BAAALgADCgYJCAAAAA==.Fruitjuice:BAAALgAECgUJDgAAAA==.',
Fu='Funbobby:BAAALgAECgUJBgAAAA==.',
Fx='Fxce:BAAALgAECgQJBAAAAA==.',
['Fâ']='Fâmine:BAABLgAECn8bAAICAAgJwRLqJACcAQACAAgJwRLqJACcAQAAAA==.',
Ga='Gamer:BAAALgADCgcJDAABLgAECgYJDgAKAAAAAA==.Gamergirl:BAAALgAECgYJDgAAAA==.Ganjj:BAAALgAECgEJAQAAAA==.Gawdric:BAACLgAFFH8PAAMRAAUJFR8oDQB6AQARAAQJFR8oDQB6AQASAAEJAADEIAAAAAAuAAQKfx4AAxEACAlWIZ0sAIYCABEACAlWIZ0sAIYCACMAAQnOC0oYAC4AAAAA.',
Ge='Georgesoros:BAAALgAECggJEQAAAA==.',
Gh='Ghibludgeon:BAAALgADCgIJAgAAAA==.Ghiboom:BAAALgAECgEJAgAAAA==.Ghulz:BAAALgAECgYJCQAAAA==.Ghuntarr:BAAALgADCgcJDAAAAA==.',
Gi='Gibsmedats:BAABLgAECn8cAAITAAgJkRJ0QgDqAQATAAgJkRJ0QgDqAQAAAA==.Giin:BAAALgAECgEJAwAAAA==.Gildark:BAAALgADCgEJAQAAAA==.',
Gl='Glaiven:BAABLgAECn8TAAITAAcJMiDEHgCZAgATAAcJMiDEHgCZAgAAAA==.Glasscleaner:BAAALgAECgcJEQABLgAFFAIJBgAJANYlAA==.Glenfiddich:BAABLgAECn8bAAIRAAgJQiE2DQBcAgARAAgJQiE2DQBcAgAAAA==.',
Gn='Gnartusk:BAABLgAECn8bAAISAAYJvSTgAwAOAgASAAYJvSTgAwAOAgAAAA==.Gnomett:BAAALgADCgEJAQAAAA==.',
Go='Goblinsham:BAAALgAECgEJAQAAAA==.Gordrack:BAAALgAECgEJAQAAAA==.',
Gr='Grandmapunch:BAAALgADCgIJAgABLgAECgcJEwAKAAAAAA==.Grasswizard:BAAALgAECggJEQAAAA==.Greela:BAAALgADCgIJAgAAAA==.Greens:BAAALgAECgYJDQAAAA==.Gremory:BAAALgADCgYJBwAAAA==.Gru:BAAALgAECggJDgAAAA==.Grïma:BAAALgADCgcJDQABLgAECgkJLgAcANYdAA==.',
Gu='Gueritestje:BAABLgAECn8lAAIUAAgJ2CI8AQCyAgAUAAgJ2CI8AQCyAgAAAA==.Guzzlord:BAAALgAECgkJEwAAAA==.',
Ha='Hambo:BAAALgADCgkJBwAAAA==.Hanekawa:BAAALgAECgUJBwABLgAECgcJGwAEAGsgAA==.Harddwarf:BAAALgAECgEJAQAAAA==.Haugcraneka:BAAALgADCgYJBgAAAA==.Hawts:BAAALgAECgEJAQAAAA==.',
He='Heleous:BAABLgAECn8ZAAMQAAgJHxh7KgCYAQAQAAgJHxh7KgCYAQAUAAEJHg46RAAuAAAAAA==.',
Hi='Highly:BAAALgADCgIJAgAAAA==.Hikari:BAABLgAECn8rAAIeAAgJUxKaCgCUAQAeAAgJUxKaCgCUAQAAAA==.Himalayanman:BAAALgAECgkJDgAAAA==.Hipdrop:BAAALgADCgEJAQAAAA==.Hitemup:BAAALgAECgEJAwAAAA==.Hitoshura:BAAALgAECggJEgAAAA==.',
Ho='Hobbeswerth:BAABLgAECn8UAAIJAAYJExCLNQAZAQAJAAYJExCLNQAZAQAAAA==.Holycowbun:BAAALgAECgUJBQAAAA==.Holyginger:BAAALgAECgYJBwAAAA==.Holyglizzy:BAAALgAECgcJDgAAAA==.Holysoup:BAAALgAECgEJAQAAAA==.Hornlet:BAAALgAECgEJAQABLgAECgIJBAAKAAAAAA==.Howitzerx:BAAALgAECgQJCQAAAA==.',
Hu='Huggies:BAAALgAECgMJCQAAAA==.Humdinger:BAAALgADCgYJCAAAAA==.Hush:BAAALgADCgUJBQAAAA==.',
Hy='Hypérîon:BAAALgAECgQJCgAAAA==.',
Ia='Iagging:BAACLgAFFH8GAAIJAAIJ1iV6DwDgAAAJAAIJ1iV6DwDgAAAuAAQKfygAAgkACQmhJagAAIQDAAkACQmhJagAAIQDAAAA.',
Ib='Ibodan:BAAALgAECgMJBAAAAA==.',
Ic='Iceflinger:BAABLgAECn8YAAIIAAcJtR2TKADCAQAIAAcJtR2TKADCAQAAAA==.',
Id='Idjit:BAAALgADCgcJBwABLgAECgYJCQAKAAAAAA==.Idlehand:BAAALgAECgYJCwAAAA==.',
Ie='Ieatcats:BAACLgAFFH8FAAIkAAIJMwlYFACtAAAkAAIJMwlYFACtAAAuAAQKfyoAAiQACQkSGSgEAFMCACQACQkSGSgEAFMCAAAA.',
Il='Ilidia:BAAALgAECgEJAQAAAA==.',
Im='Imarri:BAAALgADCgYJCAAAAA==.Imjustakid:BAAALgADCgMJAwAAAA==.Immahuntyou:BAAALgAECgEJBAAAAA==.Imobelle:BAABLgAECn8hAAIIAAcJOxVMQgBnAQAIAAcJOxVMQgBnAQAAAA==.Imprepared:BAAALgAECgUJCAAAAA==.',
In='Indrani:BAAALgAECgYJCgAAAA==.Infidel:BAAALgAECgMJAwABLgAFFAUJDgAIAGAQAA==.',
Ip='Ippiekiyaymf:BAABLgAECn8UAAIFAAYJxRWdEwBnAQAFAAYJxRWdEwBnAQAAAA==.',
Ir='Irishman:BAAALgADCgYJBwAAAA==.',
Is='Ishooturface:BAABLgAECn8YAAMBAAgJ3xlxJACJAQABAAgJ3xlxJACJAQAgAAYJ3g0mRQBAAQAAAA==.István:BAAALgADCgcJDQAAAA==.',
It='Itazki:BAABLgAECn8XAAMlAAgJOh4JCQBHAgAlAAgJOh4JCQBHAgAcAAEJMw0gSQAuAAAAAA==.',
Ja='Jardabeans:BAAALgAECgQJCAAAAA==.Jarjárßlinks:BAAALgAECgYJCgAAAA==.Jawz:BAAALgAECgMJBQAAAA==.',
Je='Jeff:BAAALgADCgMJAgAAAA==.Jelial:BAAALgAECgUJBQAAAA==.Jenga:BAAALgAECggJDgAAAA==.Jerriblank:BAAALgADCgcJCAAAAA==.',
Jf='Jf:BAAALgAFFAIJAgAAAA==.',
Ji='Ji:BAABLgAECn8oAAIiAAgJzBeJFgA0AgAiAAgJzBeJFgA0AgAAAA==.Jibbage:BAACLgAFFH8OAAIIAAUJYBA9DwCeAQAIAAUJYBA9DwCeAQAuAAQKfzMAAggACQlNIjsKAHIDAAgACQlNIjsKAHIDAAAA.Jitzakkal:BAACLgAFFH8XAAMCAAYJfiQ+CACRAQACAAUJ7iM+CACRAQADAAEJwCYYCQBlAAAuAAQKfx8AAwMACQmLJSgFAIgCAAIACQmNIyYVANYCAAMABgmTJSgFAIgCAAAA.',
Jo='Johnpaladin:BAABLgAECn8hAAIUAAgJgh8nBADIAgAUAAgJgh8nBADIAgAAAA==.Joshswims:BAABLgAECn8XAAMRAAgJGg9dlQBWAQARAAgJ+w5dlQBWAQAjAAQJARCvDQDRAAAAAA==.',
Ju='Jussie:BAAALgAECgEJAQAAAA==.',
Ka='Kadriel:BAAALgADCgEJAQAAAA==.Kambo:BAAALgAECgEJAgAAAA==.Kaptainkushh:BAAALgAECgQJEAAAAA==.Kaptkush:BAAALgAECgQJCQAAAA==.Kardinal:BAABLgAECn8jAAMCAAkJ+SA6EgDqAgACAAkJpSA6EgDqAgADAAMJoR/JLAALAQAAAA==.Karig:BAAALgADCgQJBQAAAA==.Karpathous:BAAALgAECgkJDgAAAA==.Karrag:BAAALgAECgEJAQAAAA==.Karzo:BAAALgADCgYJBgAAAA==.Kasawraa:BAAALgADCgYJBgAAAA==.Katena:BAAALgAECgYJDwAAAA==.Kaymir:BAABLgAECn8cAAQmAAcJdxcZDgCpAQAmAAcJ+xMZDgCpAQAGAAMJyhxbVQDhAAAFAAEJ+gmdZAAvAAAAAA==.Kazdruid:BAAALgAECgYJCgAAAA==.Kaznathi:BAABLgAECn8hAAIOAAgJdSUxAQD8AgAOAAgJdSUxAQD8AgAAAA==.',
Ke='Keladorn:BAABLgAECn8WAAIQAAYJeR9NJQCvAQAQAAYJeR9NJQCvAQAAAA==.Keloril:BAAALgAECgQJCgAAAA==.',
Kh='Khanyiso:BAABLgAECn8hAAIUAAgJchTWEQCrAQAUAAgJchTWEQCrAQAAAA==.Kharak:BAAALgAECgcJEAABLgABCgUJBAAKAAAAAA==.',
Ki='Kieran:BAABLgAECn8aAAMFAAgJsQupHgAGAQAFAAgJsQupHgAGAQAGAAIJPwFHigAiAAAAAA==.Kikimora:BAABLgAECn8dAAQEAAcJOx7aAQDbAQAEAAYJ0h/aAQDbAQACAAYJrBppZQCbAQADAAIJmxdpSACVAAAAAA==.Killsaurus:BAACLgAFFH8KAAIFAAQJPBuMBABrAQAFAAQJPBuMBABrAQAuAAQKfycAAgUACAmTIOIDAHMCAAUACAmTIOIDAHMCAAAA.Kilsaurus:BAAALgAECgMJAwAAAA==.Kismetx:BAAALgAECgMJBQAAAA==.Kittysmasher:BAAALgAECgQJBAAAAA==.Kiue:BAAALgADCgEJAQAAAA==.',
Kn='Knomtseb:BAAALgADCgcJDgAAAA==.',
Ko='Koa:BAAALgAECgIJAwAAAA==.Koey:BAAALgAECgQJBgAAAA==.Korsho:BAAALgAECgEJAQAAAA==.Kosuke:BAAALgADCgUJBQAAAA==.',
Kr='Kriep:BAAALgAECgEJAQAAAA==.Kristian:BAAALgADCgcJBwAAAA==.Krixos:BAAALgAECgIJAgABLgAFFAQJCQAIANwRAA==.Kroshka:BAAALgADCgEJAQAAAA==.',
Kw='Kwarrior:BAAALgAECgEJAQABLgAECggJFwACAAUVAA==.Kwazlock:BAABLgAECn8XAAMCAAgJBRW1nQAdAQACAAcJZhK1nQAdAQADAAMJ2A5KQgCsAAAAAA==.',
Ky='Kybalion:BAAALgAECgQJBAAAAA==.Kyoju:BAAALgAECgcJDwAAAA==.',
La='Laprimera:BAAALgAECgQJDQAAAA==.Lazyjade:BAABLgAECn8XAAIFAAgJawmjEwBmAQAFAAgJawmjEwBmAQAAAA==.',
Le='Leyskrodan:BAABLgAECn8kAAMFAAgJhRAQGwAlAQAFAAgJhRAQGwAlAQAGAAEJKQMciQAlAAAAAA==.',
Li='Lichborne:BAAALgAECgUJDQAAAA==.Lift:BAAALgADCggJCAABLgAECgkJFAAKAAAAAA==.Lightmilk:BAAALgADCggJCAAAAA==.Listel:BAAALgADCgUJBQAAAA==.Lizardos:BAAALgAECgkJCgAAAA==.',
Lm='Lmnpeprstepr:BAAALgAECgEJAgAAAA==.',
Lo='Lockrocksftw:BAAALgADCgMJAwAAAA==.Lorynn:BAAALgADCgcJBwAAAA==.',
Lu='Lucyna:BAABLgAECn8kAAQCAAgJhh9JGgDYAQACAAcJ1x1JGgDYAQADAAUJBh01EwCxAQAEAAEJAABRIABxAAAAAA==.Lueshen:BAABLgAECn8bAAIiAAcJDx6uFABHAgAiAAcJDx6uFABHAgAAAA==.Luniea:BAAALgAECgEJAQAAAA==.',
Ly='Lysergicburn:BAAALgADCgMJBAABLgAECgYJCwAKAAAAAA==.Lyshin:BAAALgADCgQJBAAAAA==.',
['Lá']='Lárz:BAAALgAECgIJAwAAAA==.',
['Lü']='Lüktar:BAAALgADCgYJBgAAAA==.',
Ma='Madmarsh:BAAALgAECgQJBwABLgAECgkJEwAKAAAAAA==.Madwe:BAAALgAECggJEwAAAA==.Maggams:BAAALgADCgEJAQAAAA==.Magnaur:BAAALgADCgcJDgAAAA==.Magturri:BAABLgAECn8gAAMBAAgJhSKwCQD8AgABAAgJhSKwCQD8AgAgAAIJihA4dgBmAAAAAA==.Maineck:BAABLgAECn8kAAIPAAgJ+BzYEgCLAgAPAAgJ+BzYEgCLAgAAAA==.Maketaori:BAAALgADCgYJDAAAAA==.Mambosauce:BAAALgADCgUJBQAAAA==.Mangosmash:BAAALgAECgMJBQAAAA==.Maraline:BAAALgADCgYJBQAAAA==.Marcusdapimp:BAACLgAFFH8OAAIGAAUJJhRrAwB7AQAGAAUJJhRrAwB7AQAuAAQKfyoAAgYACAmHIcsFAPMCAAYACAmHIcsFAPMCAAAA.Marymoocow:BAAALgAECgYJEwAAAA==.Matild:BAABLgAECn8ZAAILAAYJTCJ1CwAfAgALAAYJTCJ1CwAfAgAAAA==.Maxdiabolic:BAAALgADCgQJBAAAAA==.Maxfirepower:BAAALgADCgcJCgAAAA==.Maxfrogpower:BAAALgADCgYJBgAAAA==.Maxsunward:BAAALgAECgMJBAAAAA==.Maérline:BAAALgADCgcJDQABLgAECggJIgAFADYgAA==.',
Me='Meatslug:BAAALgAECgEJAQAAAA==.Meepasaurus:BAABLgAECn8YAAInAAYJMRtQFADHAQAnAAYJMRtQFADHAQAAAA==.Megaforce:BAAALgAECgQJBAAAAA==.Meliiodas:BAABLgAECn8rAAIeAAgJFQv7DQBbAQAeAAgJFQv7DQBbAQAAAA==.Melisandre:BAAALgADCgIJAgAAAA==.Mellky:BAABLgAECn8rAAIJAAkJtyN7BQAKAwAJAAkJtyN7BQAKAwAAAA==.Merkin:BAAALgADCgcJBwAAAA==.Merrinx:BAABLgAECn8UAAMEAAYJXiYwAwBxAgAEAAYJySUwAwBxAgADAAIJWyNcDQDRAAAAAA==.Metanoia:BAAALgAECgQJCAAAAA==.',
Mg='Mgamer:BAAALgAECgYJEgAAAA==.Mgämër:BAAALgAECgEJAQAAAA==.',
Mi='Midgetmanxl:BAAALgAECgEJAgAAAA==.Midnitetrvlr:BAAALgAECgcJDQAAAA==.Miima:BAAALgAECgEJAQAAAA==.Minji:BAAALgAECgUJBQAAAA==.Mirren:BAABLgAECn8YAAIIAAgJ5BbiigC8AQAIAAgJ5BbiigC8AQAAAA==.Missed:BAAALgADCgUJBQABLgAECgkJCgAKAAAAAA==.Misthios:BAABLgAECn8XAAIkAAgJ2RSiGgAsAgAkAAgJ2RSiGgAsAgAAAA==.Mistkeg:BAAALgAECgYJEAAAAA==.Miteux:BAAALgAECgYJEgAAAA==.Mixxlepit:BAABLgAECn8aAAMkAAgJCQe/DgCAAQAkAAgJCQe/DgCAAQAoAAEJpgMvIQAsAAAAAA==.',
Ml='Mlkchocolate:BAAALgADCgkJDwAAAA==.',
Mm='Mmhunt:BAAALgAECgMJAwAAAA==.',
Mo='Mogli:BAAALgADCgYJBgAAAA==.Molyporph:BAAALgAECgEJAQAAAA==.Momojojo:BAABLgAECn8kAAMDAAgJnBmfBACUAgADAAgJnBmfBACUAgACAAUJzBJYTQAIAQAAAA==.Monre:BAABLgAECn8WAAITAAgJqxNQSQDPAQATAAgJqxNQSQDPAQAAAA==.Moobss:BAAALgADCgEJAQAAAA==.Moohlawn:BAAALgAECgQJBQABLgAECgYJDwAKAAAAAA==.Moolock:BAAALgAECgUJBQAAAA==.Moonflame:BAABLgAECn8iAAMGAAgJ/xf8JwCvAQAGAAYJsBb8JwCvAQAFAAgJQg5VEACJAQAAAA==.Moonmajik:BAAALgADCgEJAgAAAA==.Mooriah:BAABLgAECn8XAAIcAAcJVAOqVQDOAAAcAAcJVAOqVQDOAAAAAA==.Moosty:BAAALgAECgIJAgAAAA==.Mordrakhuul:BAAALgAECgYJCAAAAA==.Morphtek:BAAALgAECgYJCgAAAA==.Morphyne:BAABLgAECn8hAAIQAAkJtBk7PgAsAgAQAAkJtBk7PgAsAgAAAA==.Moselii:BAAALgADCgEJAQABLgAECgEJAgAKAAAAAA==.Moserr:BAAALgAECgEJAgAAAA==.',
Mu='Muffin:BAAALgAECgYJEQAAAA==.',
My='Mycilya:BAAALgAECggJEgAAAA==.Mynchus:BAAALgAECgEJAgAAAA==.Mysaria:BAAALgADCgUJBQAAAA==.Mysterymonk:BAABLgAECn8kAAIJAAgJ3iRjAQA2AwAJAAgJ3iRjAQA2AwAAAA==.Mysterypala:BAABLgAECn8mAAILAAgJgCXZAABTAwALAAgJgCXZAABTAwAAAA==.Mysto:BAABLgAECn8hAAMeAAcJkBbPHADaAQAeAAcJkBbPHADaAQATAAMJHQNUzABdAAAAAA==.Mystodin:BAAALgAECgIJAgAAAA==.',
['Mä']='Mälförmïtÿ:BAABLgAECn8VAAMGAAgJgxpwFgApAgAGAAgJgxpwFgApAgAFAAUJSRJ+NwAyAQAAAA==.',
Na='Nacon:BAAALgAECgQJDwAAAA==.Naneko:BAABLgAECn8XAAIIAAgJNQkx1wBBAQAIAAgJNQkx1wBBAQAAAA==.Narrator:BAAALgAECgYJCAAAAA==.Nawwl:BAAALgADCgcJDgAAAA==.',
Ne='Neamheaglach:BAAALgADCgQJBAABLgAFFAEJAQAKAAAAAA==.Neotahr:BAACLgAFFH8FAAIgAAIJpA+lDgCMAAAgAAIJpA+lDgCMAAAuAAQKfykAAyAACQliHyYBAJICACAACQliHyYBAJICAAEAAwnOFyGbAJwAAAAA.Neroiki:BAAALgAECgEJAgAAAA==.Neurôn:BAEALgAECgUJBgAAAA==.Nezra:BAABLgAECn8ZAAImAAkJTRRxGgDEAQAmAAkJTRRxGgDEAQAAAA==.',
Ni='Nicckkcc:BAAALgADCgYJCwAAAA==.Nightquil:BAAALgADCgIJAgAAAA==.Nim:BAABLgAECn8ZAAInAAcJkQ2zHgBPAQAnAAcJkQ2zHgBPAQAAAA==.Nitehunter:BAABLgAECn8dAAIBAAcJoQ6NLwBSAQABAAcJoQ6NLwBSAQAAAA==.',
No='Nomad:BAAALgAECgQJBQAAAA==.',
Nu='Nubshock:BAAALgAECgEJAQAAAA==.',
Ny='Nyatsua:BAAALgADCgEJAQAAAA==.',
['Nô']='Nôva:BAAALgADCgkJCQAAAA==.',
['Nö']='Növacaïn:BAAALgAECgIJAgAAAA==.',
Of='Offseason:BAAALgADCgYJBgAAAA==.',
Oi='Oistos:BAAALgADCgcJCwAAAA==.',
Om='Omid:BAAALgADCgYJCgAAAA==.',
On='Ondarklena:BAAALgADCgEJAQAAAA==.Onlydans:BAABLgAECn8ZAAIUAAkJNBnVCwAMAgAUAAkJNBnVCwAMAgAAAA==.',
Oo='Oomfie:BAAALgADCgkJDAAAAA==.',
Ou='Ouch:BAAALgAECgUJCgAAAA==.',
Oy='Oyakev:BAAALgADCggJCgAAAA==.',
Pa='Pabiloneta:BAAALgAECgQJBgAAAA==.Pacho:BAAALgADCgkJCQAAAA==.Painzir:BAABLgAECn8cAAIRAAgJbR9/DwBDAgARAAgJbR9/DwBDAgAAAA==.Palamyne:BAAALgADCgYJBgAAAA==.Pallyana:BAAALgAECgcJEQAAAA==.Palosdin:BAAALgADCgIJAgAAAA==.Pandangerous:BAAALgADCgQJBQAAAA==.Parch:BAAALgADCgcJBwABLgAECggJHgAiACUkAA==.Parrandas:BAAALgAECgUJBQAAAA==.Parsleyposh:BAAALgADCgMJAgAAAA==.',
Pe='Peace:BAABLgAECn8lAAIFAAkJTRr0DwCGAgAFAAkJTRr0DwCGAgAAAA==.Pepsweat:BAAALgADCgUJBQAAAA==.Perilc:BAAALgADCgQJBAAAAA==.Perimones:BAAALgAECgQJCAAAAA==.',
Ph='Phteve:BAAALgADCgUJBwAAAA==.',
Pi='Pigfeet:BAAALgADCgcJCwAAAA==.Pillows:BAAALgADCgYJCgAAAA==.',
Pl='Plapper:BAAALgADCgMJAwABLgAECgYJDgAKAAAAAA==.',
Po='Ponytale:BAAALgADCgYJBgAAAA==.Popaheal:BAABLgAECn8eAAMGAAUJ5iGqIQDWAQAGAAUJ5iGqIQDWAQAFAAEJHAhnYwAyAAAAAA==.Portali:BAAALgADCgkJFAAAAA==.',
Pr='Praystatiøn:BAAALgADCgcJBwAAAA==.Profitlord:BAAALgAECgYJBgAAAA==.Proticus:BAAALgAECgMJAwAAAA==.',
Ps='Psychodad:BAAALgAECgEJAQAAAA==.',
Pu='Purplepain:BAAALgAFFAMJAwAAAA==.Purplod:BAABLgAECn8YAAIRAAkJtg9GhAB6AQARAAkJtg9GhAB6AQAAAA==.',
Py='Pyatpree:BAAALgAECgQJBgAAAA==.',
['Pä']='Päntera:BAABLgAECn8eAAIfAAgJCBltCADdAQAfAAgJCBltCADdAQAAAA==.',
Qi='Qing:BAAALgAECggJEwAAAA==.',
Qt='Qtrpounder:BAAALgAFFAIJAgAAAA==.',
Qy='Qybxboogied:BAAALgAECgIJAgAAAA==.',
Ra='Raensong:BAAALgADCgEJAQAAAA==.Rafterman:BAAALgAECgEJAwAAAA==.Rahdric:BAAALgAECgYJDQAAAA==.Raisa:BAABLgAECn8aAAMCAAgJlx50IwCkAQACAAUJUh10IwCkAQADAAQJ1B8rHABtAQAAAA==.Rakarum:BAABLgAECn8WAAInAAYJWBJ/DwAoAQAnAAYJWBJ/DwAoAQAAAA==.Rasar:BAABLgAECn8cAAIIAAgJVyAZIwDmAgAIAAgJVyAZIwDmAgAAAA==.Rayleena:BAAALgAECgEJAQAAAA==.Rayo:BAAALgAECgQJBAAAAA==.',
Re='Reginald:BAAALgADCgcJDgAAAA==.Reigh:BAAALgADCgQJBAAAAA==.Rektington:BAABLgAECn8bAAIRAAgJHiCsCgB5AgARAAgJHiCsCgB5AgAAAA==.Remmag:BAABLgAECn8sAAIIAAgJZSTnCACuAgAIAAgJZSTnCACuAgAAAA==.Rett:BAAALgADCgcJEQAAAA==.Rexxy:BAAALgAECgYJDgAAAA==.',
Ri='Riott:BAAALgADCggJDwAAAA==.Rippednstiff:BAAALgADCgYJBgAAAA==.',
Ro='Roflmeister:BAABLgAECn8WAAIfAAYJkBUBEQCyAQAfAAYJkBUBEQCyAQAAAA==.Romoko:BAACLgAFFH8GAAIPAAQJZgbAEAD5AAAPAAQJZgbAEAD5AAAuAAQKfx4AAg8ACAmkFusgAAgCAA8ACAmkFusgAAgCAAAA.Rorshk:BAAALgAECgYJEAAAAA==.Royal:BAAALgAECgEJAQAAAA==.Roysham:BAAALgAECgYJEwAAAA==.Roywar:BAAALgAECgEJAwAAAA==.',
Ru='Rubianne:BAABLgAECn8hAAIMAAcJbAl2NAAHAQAMAAcJbAl2NAAHAQAAAA==.Rumrunner:BAAALgAECggJDAAAAA==.',
Ry='Rycicle:BAAALgADCgYJBQABLgAECgEJAQAKAAAAAA==.Rynhardt:BAAALgAECgEJAQAAAA==.Ryolith:BAAALgADCgMJAwAAAA==.',
['Rø']='Rønea:BAAALgAECgEJAQAAAA==.',
['Rý']='Rýfle:BAAALgADCgEJAQABLgAECgEJAQAKAAAAAA==.',
Sa='Sacrus:BAAALgAECgYJEAAAAA==.Santoss:BAAALgADCgYJEQAAAA==.Sarah:BAABLgAECn8pAAMfAAgJ3SEfAgCZAgAfAAgJlSEfAgCZAgAgAAEJuCIXdwBjAAABLgAECgkJIAAFAKMfAA==.',
Sc='Scottscrx:BAAALgADCgUJBQAAAA==.Scrotes:BAAALgAECgYJDQAAAA==.',
Se='Seer:BAABLgAECn8XAAITAAgJ0BaOXACMAQATAAgJ0BaOXACMAQAAAA==.Seilah:BAAALgADCgcJCgAAAA==.Selbi:BAABLgAECn8aAAIDAAgJwBQBAwDMAQADAAgJwBQBAwDMAQAAAA==.Senjougahara:BAACLgAFFH8RAAIjAAQJNx1YAAB0AQAjAAQJNx1YAAB0AQAuAAQKfy4AAyMABwnCJUcBAPcCACMABwnCJUcBAPcCABEAAQnCB+cqASsAAAAA.Serav:BAAALgADCgIJAgAAAA==.Seravonas:BAAALgADCgcJBwAAAA==.Seravonta:BAAALgAECgEJAgAAAA==.Serial:BAABLgAECn8kAAIPAAgJkCH6AgCtAgAPAAgJkCH6AgCtAgAAAA==.Seriyah:BAACLgAFFH8KAAIlAAMJxArAAwDwAAAlAAMJxArAAwDwAAAuAAQKfxcAAiUABwntGKYKABwCACUABwntGKYKABwCAAAA.Serph:BAAALgAECgcJBgAAAA==.',
Sh='Shabane:BAABLgAECn8bAAIOAAYJLBb6FQBRAQAOAAYJLBb6FQBRAQAAAA==.Shaggyspaggy:BAAALgAECgUJBQAAAA==.Shambulañcé:BAAALgAECgYJEAAAAA==.Shanbubu:BAAALgAECgEJBgAAAA==.Shekari:BAAALgAECgEJAQAAAA==.Shenanigins:BAAALgADCgUJBQAAAA==.Shiftey:BAAALgADCggJCAABLgAECggJHAARAG0fAA==.Shilera:BAAALgADCgYJDwAAAA==.Shiminy:BAAALgAECgcJCwAAAA==.Shinobi:BAABLgAECn8bAAIiAAgJqRiwCgDLAQAiAAgJqRiwCgDLAQAAAA==.Shiol:BAACLgAFFH8HAAMCAAMJxRgAMACzAAACAAIJ4xcAMACzAAADAAEJiho+EgBaAAAuAAQKfxcAAwIACAlRHlAkAIICAAIABwkVHlAkAIICAAMABAlvHsAhAEcBAAAA.Shirls:BAABLgAECn8ZAAMQAAkJYBptRwANAgAQAAkJYBptRwANAgALAAYJCRRPWAAaAQAAAA==.Shivak:BAACLgAFFH8FAAIaAAIJiggRJACMAAAaAAIJiggRJACMAAAuAAQKfyoAAhoACQlUFgEFAGACABoACQlUFgEFAGACAAAA.Shivanie:BAAALgAECgYJEwAAAA==.Shock:BAABLgAECn8hAAMPAAgJAh/iDgC4AgAPAAgJAh/iDgC4AgAHAAEJ2RBklwBBAAABLgAECgkJCgAKAAAAAA==.Shocknorris:BAAALgAECgUJBQAAAA==.Shîftycent:BAABLgAECn8bAAQMAAcJbQkpYgArAQAMAAcJbQkpYgArAQAcAAcJQwymGgAnAQAlAAEJ0wDiOwAKAAAAAA==.',
Si='Siccem:BAAALgAECgcJDgABLgAECggJKQAcAK4eAA==.Sienfonson:BAAALgADCgMJAwAAAA==.',
Sk='Skaffos:BAAALgADCgUJBQABLgADCgYJBgAKAAAAAA==.Skaffoz:BAAALgADCgEJAQABLgADCgYJBgAKAAAAAA==.Skafz:BAAALgADCgYJBgAAAA==.Skik:BAABLgAECn8kAAInAAgJeRSWCQCUAQAnAAgJeRSWCQCUAQAAAA==.Skylines:BAAALgAECgcJDQAAAA==.Skylinez:BAACLgAFFH8LAAIPAAUJkgpuDgAWAQAPAAUJkgpuDgAWAQAuAAQKfxoAAg8ACQnSHWYWAGcCAA8ACQnSHWYWAGcCAAAA.Skïttles:BAABLgAECn8VAAMMAAcJaRdrMQDlAQAMAAcJaRdrMQDlAQAcAAMJxwvKNAB2AAAAAA==.',
Sl='Sleezball:BAAALgADCgEJAwAAAA==.Sloppyhog:BAAALgAECgkJEwAAAA==.Sloppyslice:BAAALgAECgEJAQABLgAECgMJBAAKAAAAAA==.',
Sm='Smobo:BAAALgAECgEJAQAAAA==.Smolder:BAAALgAECgUJCQABLgAECgkJFAAKAAAAAA==.',
Sn='Snoz:BAAALgADCgEJAQAAAA==.',
So='Sobek:BAAALgAECgcJCQAAAA==.Soeuphoric:BAAALgAECgcJBwAAAA==.Sonicfear:BAAALgAFFAEJAgAAAA==.Sonictide:BAAALgAECgUJCgAAAA==.Souahang:BAAALgAECgEJAgAAAA==.Soviette:BAAALgADCgcJDQAAAA==.',
Sp='Spaghetto:BAABLgAECn8jAAIcAAgJNBjcCAADAgAcAAgJNBjcCAADAgAAAA==.Sparx:BAAALgAECgEJAgAAAA==.Spicytacoo:BAAALgAECgUJBQAAAA==.',
St='Stacy:BAAALgADCgMJAwAAAA==.Stankystank:BAABLgAECn8/AAMCAAYJMw40RAAkAQACAAYJMw40RAAkAQADAAIJ2whjIQA0AAAAAA==.Stepdag:BAACLgAFFH8FAAIOAAIJ2APaJgBzAAAOAAIJ2APaJgBzAAAuAAQKfyYAAg4ACQlRC+EQAIkBAA4ACQlRC+EQAIkBAAAA.Stinkydagger:BAAALgADCgIJAgAAAA==.Stoutshrike:BAABLgAECn8UAAIJAAkJJxbRGQDsAQAJAAkJJxbRGQDsAQAAAA==.Strive:BAABLgAECn8jAAQmAAgJ4BHTCwDOAQAmAAgJhA/TCwDOAQAFAAYJDgpUNABHAQAGAAQJTRVXUwDpAAAAAA==.',
Su='Suzel:BAAALgADCgUJBQAAAA==.',
Sw='Sweetfeed:BAAALgADCgcJCgAAAA==.',
Sy='Synder:BAABLgAECn8YAAIaAAcJKAOmPwDqAAAaAAcJKAOmPwDqAAAAAA==.',
Sz='Szmata:BAABLgAECn8XAAIYAAcJvht5BADnAQAYAAcJvht5BADnAQAAAA==.',
['Só']='Sóth:BAAALgADCgEJAQAAAA==.',
Ta='Tabata:BAABLgAECn8kAAInAAgJIRU6BwDPAQAnAAgJIRU6BwDPAQAAAA==.Tahharruk:BAAALgAECgQJCwAAAA==.Tailwind:BAAALgADCgUJBAAAAA==.Talivandril:BAAALgAECgQJBwAAAA==.Talogos:BAAALgAECgMJAwAAAA==.Talvan:BAAALgADCgcJBwAAAA==.Tankowner:BAAALgADCgUJBQAAAA==.Tarkdoxicity:BAAALgADCgcJCgAAAA==.Tarynna:BAABLgAECn8bAAICAAYJ/BIrNwBPAQACAAYJ/BIrNwBPAQAAAA==.Tawxx:BAAALgAECgUJBQAAAA==.',
Te='Teagen:BAABLgAECn8aAAIPAAcJ3RZ8MQCXAQAPAAcJ3RZ8MQCXAQAAAA==.Teleprompter:BAAALgAECgYJEwAAAA==.Teleros:BAAALgADCgcJDQAAAA==.Telrissan:BAAALgAECgcJDQAAAA==.Tenyroldemon:BAABLgAECn8WAAINAAgJ2hX0BACXAQANAAgJ2hX0BACXAQAAAA==.Tenzingyatso:BAAALgAECgcJAgAAAA==.',
Th='Thald:BAABLgAECn8fAAIOAAgJ/iB7EACWAgAOAAgJ/iB7EACWAgAAAA==.Thepooper:BAACLgAFFH8FAAIQAAIJoxCHIgCnAAAQAAIJoxCHIgCnAAAuAAQKfyAAAhAACQnOHg4GALkCABAACQnOHg4GALkCAAAA.Thordun:BAAALgAECgEJAQABLgAECgcJDgAKAAAAAA==.Thunderball:BAABLgAECn8cAAIIAAgJ4xcUUQBEAgAIAAgJ4xcUUQBEAgAAAA==.',
Ti='Tinyaminals:BAAALgADCgYJBgAAAA==.Tisagosa:BAAALgADCgYJCAABLgAFFAIJBQAIAGMhAA==.Tisakna:BAACLgAFFH8FAAIIAAIJYyFMNgC+AAAIAAIJYyFMNgC+AAAuAAQKfyoAAwgACQkOJtUAAHQDAAgACQn+JdUAAHQDACEAAQnCJiwXAGEAAAAA.Tiskano:BAAALgADCgYJCwABLgAFFAIJBQAIAGMhAA==.Tissaia:BAAALgADCgcJDAABLgAFFAIJBQAIAGMhAA==.Tiszy:BAAALgADCgYJBgAAAA==.Titanx:BAAALgAECggJDQAAAA==.',
To='To:BAAALgAECgYJBgAAAA==.Tomatoes:BAAALgAECgcJEQAAAA==.Toothy:BAAALgAECgUJCAAAAA==.Torahdanyse:BAAALgAECgMJAwAAAA==.',
Tr='Trask:BAABLgAECn8ZAAIIAAkJ1BuSXgAfAgAIAAkJ1BuSXgAfAgAAAA==.Treefort:BAAALgADCgcJBwAAAA==.Trogdoor:BAAALgAECgEJAQAAAA==.Troko:BAAALgAECggJEAABLgAFFAQJCAAIAKUjAA==.Trokom:BAACLgAFFH8IAAIIAAQJpSPFDACPAQAIAAQJpSPFDACPAQAuAAQKfyIAAggACQm6JEMNAFsDAAgACQm6JEMNAFsDAAEuAAUUBAkIAAgApSMA.',
Tu='Tuakia:BAAALgADCgEJAQAAAA==.Tuggmytotem:BAAALgAECggJDgAAAA==.Turgho:BAAALgADCgMJAwAAAA==.',
Tw='Twi:BAAALgAECgcJCwAAAA==.',
Ty='Tygerfist:BAAALgAECgIJBAAAAA==.Tyrannar:BAAALgAECgcJAQAAAA==.Tytanion:BAAALgAECgEJAwAAAA==.Tython:BAAALgADCgcJBwAAAA==.',
Uc='Uch:BAAALgADCgQJBQAAAA==.',
Ul='Ultrarion:BAAALgAECgEJAgAAAA==.',
Un='Undan:BAAALgAECgEJAQAAAA==.Undercovrcow:BAAALgAECgEJAgAAAA==.Unity:BAAALgADCgYJBgAAAA==.Unmade:BAACLgAFFH8FAAIFAAIJixRRDwCqAAAFAAIJixRRDwCqAAAuAAQKfyUAAgUACQlaHIUFAD8CAAUACQlaHIUFAD8CAAAA.Unstablë:BAAALgAECgQJBAABLgAECgQJBAAKAAAAAA==.',
Ur='Urbanmech:BAABLgAECn8UAAIiAAkJEhzdEQBoAgAiAAkJEhzdEQBoAgAAAA==.',
Va='Vanderbos:BAAALgADCgMJAwAAAA==.Vanderune:BAACLgAFFH8FAAISAAIJuQ9uEgB5AAASAAIJuQ9uEgB5AAAuAAQKfykAAhIACQlaGukEAOwBABIACQlaGukEAOwBAAAA.Varastanna:BAAALgADCgYJCgAAAA==.',
Ve='Vecky:BAAALgADCgcJBwAAAA==.',
Vi='Victus:BAAALgAECgEJAQAAAA==.Vidrus:BAAALgAECgYJCwAAAA==.Vilkas:BAACLgAFFH8NAAIFAAUJnhe9BQBbAQAFAAUJnhe9BQBbAQAuAAQKfx8AAgUACAkKISQIAAIDAAUACAkKISQIAAIDAAAA.Viserion:BAAALgAECgYJEAAAAA==.Visionhorn:BAAALgADCgIJAwAAAA==.',
Vo='Voidlit:BAAALgAECgEJAQAAAA==.Voodoowhodo:BAAALgAECgYJCgAAAA==.',
Vu='Vuradra:BAAALgAECgMJAwAAAA==.Vuudrood:BAAALgADCgkJEQAAAA==.',
Wa='Waddledoo:BAAALgAECgMJBAAAAA==.Walruskíng:BAABLgAECn8bAAIFAAcJ7xvdCAD3AQAFAAcJ7xvdCAD3AQAAAA==.Wardaddy:BAAALgAECgQJBwAAAA==.Warkind:BAAALgAECgMJAwAAAA==.Warmage:BAAALgAECgIJAgAAAA==.Warmaku:BAABLgAECn8YAAMMAAcJmx3pCwBKAgAMAAcJmx3pCwBKAgAlAAEJ9QLZOQAhAAAAAA==.Wasred:BAAALgADCgkJCQAAAA==.',
We='Weezybaby:BAABLgAECn8YAAMYAAgJ5Q9lCABrAQAYAAgJ5Q9lCABrAQAHAAEJUgR0pQAqAAAAAA==.Wenjiesmom:BAAALgAECgEJAQAAAA==.',
Wh='Whitecosmos:BAAALgAECgMJBgAAAA==.Whohe:BAAALgAECgEJAQAAAA==.',
Wi='Wigwog:BAAALgAECgcJEAAAAA==.Windfury:BAACLgAFFH8PAAIYAAQJIyJPAQCPAQAYAAQJIyJPAQCPAQAuAAQKfyMAAhgACQmUJLABAEwDABgACQmUJLABAEwDAAAA.Winterfella:BAAALgADCgUJCwAAAA==.Wirantimer:BAAALgAECgYJDwAAAA==.Witfuk:BAAALgADCgUJBQAAAA==.',
Wo='Wogasaurus:BAAALgAECgcJDAAAAA==.',
Wu='Wuzo:BAAALgAECgMJAwAAAA==.',
Wy='Wykka:BAAALgAECggJDwAAAA==.Wyverynn:BAABLgAECn8UAAIRAAcJrRRJewCNAQARAAcJrRRJewCNAQAAAA==.',
['Wí']='Wínter:BAAALgADCgMJAwAAAA==.',
Xa='Xany:BAAALgAECgUJBwAAAA==.',
Xc='Xcomunicated:BAAALgADCgUJBQAAAA==.',
Xe='Xenomortis:BAAALgAECgcJDwAAAA==.Xephanie:BAAALgAECgEJAQAAAA==.',
Xi='Xinlucia:BAAALgAECggJDQAAAA==.',
Xo='Xofu:BAAALgAECgEJAwAAAA==.',
Xr='Xrxyz:BAACLgAFFH8KAAIQAAQJfxm6CQBoAQAQAAQJfxm6CQBoAQAuAAQKfxwAAhAACAnkG+QoAIECABAACAnkG+QoAIECAAAA.',
Xy='Xylus:BAAALgAECgIJAgAAAA==.',
Ya='Yabe:BAAALgAECgMJAwAAAA==.',
Ye='Yen:BAAALgADCgIJAgAAAA==.Yetibear:BAAALgAECgIJAgAAAA==.Yewna:BAAALgAECgYJCQAAAA==.',
Za='Zachdem:BAAALgAECgQJBAAAAA==.Zachdrac:BAAALgADCgQJBAAAAA==.',
Ze='Zebrabutt:BAABLgAECn8cAAMPAAgJ6Q/vEwB6AQAPAAgJtg3vEwB6AQAYAAcJ8A7OCQBKAQAAAA==.Zenstation:BAAALgADCgEJAQAAAA==.Zero:BAAALgAECgcJEgAAAA==.',
Zi='Ziccem:BAABLgAECn8pAAIcAAgJrh7QBABnAgAcAAgJrh7QBABnAgAAAA==.Ziggawâ:BAAALgAECgYJCQABLgAECggJIQAUAHIUAA==.Zildjìan:BAAALgAECgEJAQAAAA==.Zionsmender:BAAALgAECgQJBAAAAA==.',
Zo='Zolja:BAAALgAECgMJAwAAAA==.Zoney:BAAALgADCgIJAgAAAA==.Zordlon:BAAALgAECgMJBgAAAA==.',
Zu='Zukem:BAAALgAECgUJBQAAAA==.',
Zy='Zynlord:BAAALgADCgEJAQAAAA==.Zyvea:BAAALgAECgQJAwAAAA==.',
['Çr']='Çrossblesser:BAAALgAECgQJDgAAAA==.',
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
