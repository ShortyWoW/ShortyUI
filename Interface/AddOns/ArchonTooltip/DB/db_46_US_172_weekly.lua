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

local lookup = {'Paladin-Protection','Paladin-Retribution','Warrior-Protection','DeathKnight-Unholy','Mage-Frost','Unknown-Unknown','Shaman-Elemental','Priest-Holy','Druid-Restoration','Paladin-Holy','Mage-Arcane','Druid-Guardian','Druid-Balance','Monk-Brewmaster','Monk-Windwalker','Warrior-Fury','Evoker-Preservation','Evoker-Augmentation','Priest-Shadow','DemonHunter-Havoc','Hunter-BeastMastery','Warlock-Affliction','Warlock-Demonology','DemonHunter-Devourer','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Shaman-Restoration','Shaman-Enhancement','DemonHunter-Vengeance','Monk-Mistweaver','DeathKnight-Blood','Warlock-Destruction','Evoker-Devastation','Hunter-Marksmanship','Hunter-Survival','Priest-Discipline','Warrior-Arms','Druid-Feral',}
local provider = {region='US',realm='Perenolde',name='US',type='weekly',zone=46,date='2026-05-08',data={Ad='Adrador:BAABLgAECn8eAAMBAAgJ5CIRAgClAgABAAgJ5CIRAgClAgACAAIJZxTrEwFvAAAAAA==.Adrenaline:BAACLgAFFH8KAAIDAAQJ7hurBgBBAQADAAQJ7hurBgBBAQAuAAQKfzUAAgMACQmEI9QAADEDAAMACQmEI9QAADEDAAAA.',
Ae='Aelik:BAABLgAECn8gAAIEAAgJOhtxHgASAgAEAAgJOhtxHgASAgAAAA==.',
Ah='Ahkimbo:BAAALgADCgUJBQAAAA==.',
Al='Alayssa:BAABLgAECn8hAAIFAAgJqSAjEACZAgAFAAgJqSAjEACZAgAAAA==.Alda:BAAALgADCgkJDgAAAA==.Allarius:BAAALgAECgEJAQAAAA==.Allioops:BAAALgADCgUJBQABLgAECgMJBAAGAAAAAA==.Alnima:BAEBLgAECn8ZAAIHAAgJzgi1OQBoAQAHAAgJzgi1OQBoAQAAAA==.',
Am='Amilee:BAAALgAECgQJBQAAAA==.Amishhunter:BAAALgADCgEJAQAAAA==.Amoondai:BAACLgAFFH8GAAIIAAMJeherDQD3AAAIAAMJeherDQD3AAAuAAQKfxcAAggACAlhH/sLACcCAAgACAlhH/sLACcCAAAA.Amoondrin:BAABLgAECn8zAAIJAAkJLgmqLgBoAQAJAAkJLgmqLgBoAQAAAA==.Amplifier:BAAALgADCgUJBQAAAA==.',
An='Antichurch:BAAALgADCgEJAQAAAA==.Antisnow:BAAALgAECgIJAgABLgAECgcJCQAGAAAAAA==.Antregon:BAAALgADCgQJBwAAAA==.',
Ar='Araviin:BAAALgAECgcJEQAAAA==.Arazen:BAAALgAECgIJAwAAAA==.Arcillias:BAAALgADCgYJBgABLgAECgYJBgAGAAAAAA==.Arkride:BAAALgAECgEJAQAAAA==.Arnadaz:BAAALgADCgEJAQABLgAFFAIJBgAKAK4gAA==.Arthia:BAAALgAECgQJDgAAAA==.Arvidpally:BAAALgADCgkJFQAAAA==.',
As='Ashmehameha:BAAALgADCgQJAgABLgAECggJHAADADAYAA==.Asinn:BAAALgAECgEJAQAAAA==.Asoosimov:BAAALgADCgEJAQAAAA==.',
At='Atredes:BAAALgAECgYJCAAAAA==.Attima:BAABLgAECn8vAAILAAkJ+gxDAgDTAQALAAkJ+gxDAgDTAQAAAA==.',
Au='Aurøra:BAAALgADCgMJAwAAAA==.Auspex:BAABLgAECn8dAAMMAAcJCQq+FADGAAANAAcJcwdfKgDyAAAMAAcJmgm+FADGAAAAAA==.',
Av='Avaryn:BAACLgAFFH8KAAIJAAQJ+A7xGgD+AAAJAAQJ+A7xGgD+AAAuAAQKfzQAAgkACQnCH5EEABcDAAkACQnCH5EEABcDAAAA.',
Ba='Babavoss:BAAALgAECgkJAQAAAA==.Badarack:BAAALgAECgYJDgABLgAECggJOQAOANIhAA==.Badarackie:BAABLgAECn85AAMOAAgJ0iGeCQDvAgAOAAgJ0iGeCQDvAgAPAAcJGRccEgClAQAAAA==.Badash:BAABLgAECn8cAAMDAAgJMBi1CADuAQADAAgJMBi1CADuAQAQAAEJMQSorQAvAAAAAA==.Bahamuth:BAABLgAECn8xAAICAAkJHBsJEAB8AgACAAkJHBsJEAB8AgAAAA==.Bakshi:BAAALgAECgEJAgAAAA==.Barbattos:BAACLgAFFH8IAAIRAAQJ6BUfDQBBAQARAAQJ5xUfDQBBAQAuAAQKfzQAAxEACQkEJAABAFEDABEACQkEJAABAFEDABIAAQnkJKBJAGsAAAAA.Barragon:BAAALgAECgYJBwAAAA==.',
Be='Beans:BAAALgAECgQJBAAAAA==.Bethollbrew:BAAALgAECgYJDwAAAA==.Bexley:BAABLgAECn8bAAIBAAkJVhYaBgAGAgABAAkJVhYaBgAGAgAAAA==.',
Bi='Biggerbunny:BAABLgAECn8sAAITAAgJthR1DwDWAQATAAgJthR1DwDWAQAAAA==.Binkter:BAAALgAECgIJAwABLgAECgEJAQAGAAAAAA==.',
Bl='Blackjax:BAAALgADCgEJAQAAAA==.Blacklok:BAAALgAECgUJCgABLgAECggJHwAUAH4lAA==.Blargle:BAABLgAECn8WAAIVAAcJxwbIWwD8AAAVAAcJxwbIWwD8AAAAAA==.Bleubahlz:BAAALgADCgcJBwABLgAECgMJAwAGAAAAAA==.Bloodrake:BAABLgAECn8zAAIVAAkJ1B3/CACkAgAVAAkJ1B3/CACkAgAAAA==.Bloodreyne:BAAALgADCgEJAgAAAA==.',
Bo='Boahan:BAAALgAECgIJAgAAAA==.Boggart:BAAALgAECgEJAQAAAA==.Bohein:BAAALgADCgEJAQAAAA==.Bolus:BAAALgAECgEJAQAAAA==.Botany:BAAALgAECgcJBwAAAA==.Bownafiedba:BAAALgADCgUJBQAAAA==.',
Br='Braneour:BAABLgAECn8mAAMKAAgJIRIwFwDUAQAKAAgJIRIwFwDUAQACAAMJmgtlxQBuAAAAAA==.Brassballz:BAAALgAECgkJCQAAAA==.Browel:BAABLgAECn8YAAMWAAcJVhj4CAC3AQAWAAYJ3Rj4CAC3AQAXAAYJeQ38WQAgAQAAAA==.Bruen:BAAALgAECgYJBwAAAA==.',
Bu='Bubbloseven:BAAALgAECgIJAgAAAA==.Budank:BAAALgADCgMJAwAAAA==.Bumm:BAAALgAECgYJDgAAAA==.Bustybubbles:BAAALgADCgYJBgAAAA==.',
Bz='Bzspy:BAABLgAFFH8IAAIQAAMJKgufGwDZAAAQAAMJKgufGwDZAAAAAA==.',
Ca='Caalin:BAAALgAECgEJAgAAAA==.Cabooselul:BAAALgAECgQJBQAAAA==.Calibre:BAABLgAECn8YAAIYAAYJwBYPSwAXAQAYAAYJwBYPSwAXAQAAAA==.Calyptus:BAABLgAECn8YAAIXAAYJJgqKZAAFAQAXAAYJJgqKZAAFAQAAAA==.Caprious:BAACLgAFFH8JAAIEAAQJnxiiHgBkAQAEAAQJnxiiHgBkAQAuAAQKfzQAAgQACQk7JHECAE0DAAQACQk7JHECAE0DAAAA.Capylaura:BAAALgAECgUJDgAAAA==.Caratine:BAAALgAECgYJDwAAAA==.Cassandrar:BAABLgAECn8pAAQZAAkJGSQHAQA5AwAZAAgJMiQHAQA5AwAaAAYJcCAXGwAnAQAbAAEJphTuEQA9AAAAAA==.Cassandraw:BAAALgAECgYJBgABLgAECgkJKQAZABkkAA==.Cat:BAAALgADCgUJBQAAAA==.Cattlelac:BAAALgADCgUJCAAAAA==.Caymus:BAAALgAECgYJEAAAAA==.',
Ce='Celìa:BAABLgAECn8XAAIVAAgJsQf+QABLAQAVAAgJsQf+QABLAQAAAA==.Cess:BAAALgAECgEJAgAAAA==.',
Ch='Chema:BAAALgAFFAIJAwABLgAFFAIJBgAKAK4gAA==.Chestylarue:BAAALgAECgEJAQABLgAECgQJBQAGAAAAAA==.Chfgaribaldi:BAAALgADCggJDgAAAA==.Chills:BAAALgAECgcJEQAAAA==.Chillymage:BAAALgADCgYJBgAAAA==.Chosen:BAABLgAECn8YAAICAAYJRBdtYgC+AQACAAYJRBdtYgC+AQABLgAFFAQJDAAEAGceAA==.Christy:BAAALgADCgkJDgAAAA==.Chugg:BAABLgAECn8aAAIcAAcJNAnkOwAWAQAcAAcJNAnkOwAWAQAAAA==.',
Ci='Ciaphus:BAABLgAECn8VAAICAAkJ0hEoIQADAgACAAkJ0hEoIQADAgAAAA==.',
Co='Coffeedemon:BAAALgADCgEJAQAAAA==.Coldslappins:BAAALgAECggJCgAAAA==.Contagion:BAAALgAECgYJBQAAAA==.Convoke:BAABLgAECn8eAAINAAcJDSAmFgBeAgANAAcJDSAmFgBeAgAAAA==.',
Cu='Cubcake:BAAALgADCgYJBgAAAA==.Curtastrophe:BAABLgAECn80AAIFAAkJ4ByvDgCnAgAFAAkJ4ByvDgCnAgAAAA==.Curticus:BAAALgADCgMJAwAAAA==.Curtissax:BAAALgAECgIJAgAAAA==.Curtnought:BAAALgADCgIJAgAAAA==.',
['Cé']='Cérnùnnøs:BAAALgAECgEJAQAAAA==.',
Da='Daelanos:BAABLgAECn8cAAIQAAgJOxiaEgDaAQAQAAgJOxiaEgDaAQAAAA==.Dalinar:BAAALgAECgIJAwAAAA==.Daranger:BAAALgADCgEJAQAAAA==.Darska:BAAALgADCgYJBgABLgAECgIJAgAGAAAAAA==.',
De='Deadtauren:BAAALgADCgUJCwAAAA==.Deathdemon:BAAALgAECgIJAgAAAA==.Deathfue:BAAALgAECgEJAgABLgAECgcJCQAGAAAAAA==.Deathisreal:BAAALgADCgMJAwABLgAECgIJAwAGAAAAAA==.Decimated:BAACLgAFFH8MAAIEAAQJZx5uIQBdAQAEAAQJZx5uIQBdAQAuAAQKfxgAAgQACQmCHzkTAGICAAQACQmCHzkTAGICAAAA.Demon:BAAALgAECgMJBwAAAA==.Dempkiston:BAAALgADCgcJCAAAAA==.Denable:BAAALgAECgUJEQAAAA==.Denogan:BAAALgAECgUJBQABLgAECgYJDQAGAAAAAA==.Deservis:BAAALgAECgUJDgABLgAECgYJGAAYAMAWAA==.Destro:BAABLgAECn8dAAIXAAgJhQ8yOACFAQAXAAgJhQ8yOACFAQABLgAECgkJLQAdAAgWAA==.Dethadin:BAAALgADCgcJBwAAAA==.',
Di='Dilaudyd:BAAALgAECgIJAgAAAA==.Dirteemike:BAAALgADCgMJAwAAAA==.Disbeleaf:BAAALgAECgYJCAAAAA==.Discoflurry:BAAALgAECgcJCQABLgAFFAQJCgADAN8hAA==.Dizzyfist:BAAALgAECgYJCQABLgAECgYJDQAGAAAAAA==.',
Do='Dogaz:BAAALgADCgkJDAAAAA==.Donori:BAAALgAECgQJDQAAAA==.Dorcath:BAAALgADCggJCAABLgAECggJHAAQADsYAA==.',
Dr='Dragan:BAAALgAECgQJBAAAAA==.Dragonias:BAAALgAECgYJEAAAAA==.Draino:BAAALgADCgUJBQAAAA==.Drakthorn:BAAALgADCgEJAQAAAA==.Dreselwings:BAAALgAECggJCAABLgAFFAYJFgAVANAlAA==.Drinny:BAABLgAECn8pAAIIAAkJegjrGwBrAQAIAAkJegjrGwBrAQAAAA==.Drqueenisin:BAAALgADCggJEwAAAA==.Druido:BAAALgADCgYJCAAAAA==.',
Du='Duerek:BAAALgAECgEJAgAAAA==.',
['Dè']='Dèaths:BAAALgAECgYJEAAAAA==.',
Ea='Earthangel:BAAALgAECgUJEQAAAA==.',
Ed='Edlarel:BAAALgADCgQJBAABLgAECgYJBgAGAAAAAA==.',
Ei='Eine:BAABLgAECn8wAAIVAAkJvhEgGgACAgAVAAkJvhEgGgACAgAAAA==.Eitherwind:BAAALgAECgYJDQAAAA==.',
El='Eldergreen:BAABLgAECn8iAAIJAAgJzAllQAASAQAJAAgJzAllQAASAQAAAA==.Eldest:BAAALgADCgUJBQAAAA==.Elfwine:BAAALgAECgUJEAAAAA==.Elindria:BAABLgAECn8fAAQUAAgJfiWlBQBZAgAUAAgJfiWlBQBZAgAYAAQJUhq2ewA1AQAeAAIJKyCyHwCIAAAAAA==.Eliora:BAAALgADCgkJCQAAAA==.Elminstir:BAAALgAECgcJCwAAAA==.Elyissia:BAAALgAECgYJDAAAAA==.Elynisa:BAAALgAECgEJAQAAAA==.Elysian:BAABLgAECn8mAAQPAAkJSx7qCwD5AQAPAAgJgBzqCwD5AQAfAAkJphW5IQClAQAOAAIJyh+/NwC5AAAAAA==.',
Em='Emogo:BAAALgADCgUJCQAAAA==.',
En='Enforcer:BAAALgADCgQJBgAAAA==.Enlightened:BAAALgAECgQJCQAAAA==.',
Eo='Eotech:BAAALgADCggJCAAAAA==.',
Er='Erendora:BAABLgAECn8WAAIJAAYJNhKTPAAiAQAJAAYJNhKTPAAiAQAAAA==.Erets:BAAALgAECgEJAQAAAA==.Eridar:BAAALgAECgYJBgAAAA==.Erizhal:BAAALgAECgQJCwAAAA==.Erodora:BAAALgADCgEJAQAAAA==.',
Ev='Eva:BAAALgADCgEJAgAAAA==.Eviae:BAAALgAECgUJEQAAAA==.Evillure:BAABLgAECn8VAAMEAAgJgg7hNwCaAQAEAAgJHw7hNwCaAQAgAAUJjAlBJQCeAAAAAA==.',
Fa='Falan:BAABLgAECn8WAAIcAAcJABN5JQCPAQAcAAcJABN5JQCPAQAAAA==.Fatherjoe:BAAALgADCgYJBgAAAA==.Fayze:BAEALgAFFAEJAQABLgAECgYJCgAGAAAAAA==.',
Fe='Felbreaker:BAAALgAECgYJCQAAAA==.Fentril:BAAALgADCgIJAgABLgAECgYJDQAGAAAAAA==.Feår:BAABLgAECn8cAAMXAAgJBQ1iVQAsAQAXAAcJ9gpiVQAsAQAhAAMJ3Q8NSwCMAAAAAA==.',
Fi='Finley:BAAALgAECgQJBAAAAA==.Fircane:BAAALgADCgQJBAAAAA==.',
Fl='Flane:BAAALgAFFAEJAQABLgAFFAUJFAADALEhAA==.Flem:BAAALgAECgMJBAAAAA==.Flexdruid:BAAALgAECgEJAQAAAA==.',
Fo='Foog:BAAALgAECgQJBAAAAA==.',
Fr='Fragil:BAABLgAECn8fAAIaAAcJfRu7DgC3AQAaAAcJfRu7DgC3AQAAAA==.Frostmane:BAACLgAFFH8GAAIEAAMJyB0DRAAGAQAEAAMJyB0DRAAGAQAuAAQKfycAAwQACQntI7cDAC0DAAQACQntI7cDAC0DACAABwn+HL4NADECAAAA.Frostynug:BAAALgADCgYJBgAAAA==.',
Fu='Furbyn:BAAALgADCgIJAgAAAA==.',
Ga='Galena:BAAALgAECgYJDwAAAA==.Gallamier:BAAALgADCgEJAQAAAA==.Gamerinator:BAAALgADCgcJCwAAAA==.',
Ge='Geshtal:BAAALgAECgQJBwAAAA==.',
Gi='Girion:BAAALgAECgUJEQAAAA==.Girliepop:BAAALgAECgEJAQAAAA==.',
Gl='Glaiven:BAECLgAFFH8KAAMYAAQJSws9KwAFAQAYAAQJpwg9KwAFAQAeAAIJuA94BgBpAAAuAAQKfysAAx4ACQmVIYEBAKECAB4ACQmXHIEBAKECABgACQmXHp0dAKACAAAA.Glorfinndel:BAAALgADCgQJBAAAAA==.Glyr:BAAALgADCgUJBQAAAA==.',
Go='Gorgrin:BAAALgAECgQJCQAAAA==.',
Gr='Greenback:BAAALgADCgYJCwAAAA==.Greentotes:BAABLgAECn8vAAMSAAkJ5x+PAgABAwASAAkJ5x+PAgABAwAiAAQJdgYrLgCoAAAAAA==.',
Gu='Gunter:BAAALgAECgMJAwABLgAFFAQJDAAEAGceAA==.Gura:BAAALgADCgEJAQAAAA==.Gurnee:BAAALgADCgcJDQABLgAECgcJDQAGAAAAAA==.Guthix:BAAALgAECgUJBgAAAA==.',
['Gê']='Gêm:BAABLgAECn8gAAIRAAgJQxO1CADZAQARAAgJQxO1CADZAQAAAA==.',
['Gï']='Gïmlï:BAAALgADCgMJAwAAAA==.',
Ha='Haildydra:BAAALgAECgEJAQABLgAECgcJCQAGAAAAAA==.Halnan:BAAALgADCgEJAQABLgAECgYJGAAYAMAWAA==.Harkanum:BAABLgAECn80AAQRAAkJogxmDgBdAQARAAkJogxmDgBdAQAiAAQJ1BhICAAqAQASAAQJrxOSNQDLAAAAAA==.Harvester:BAAALgAECgEJAQAAAA==.Hatebreéd:BAAALgAECgEJAQAAAA==.',
He='Healinturds:BAAALgAECgYJBgABLgAECgYJGAAYAMAWAA==.Hector:BAABLgAECn8XAAICAAgJ0yJDHwCwAgACAAgJ0yJDHwCwAgAAAA==.Heelys:BAAALgAECgUJCAAAAA==.Helloagain:BAACLgAFFH8KAAIFAAMJ7BT4LgD6AAAFAAMJ7BT4LgD6AAAuAAQKfxwAAgUABgm8IRldACMCAAUABgm8IRldACMCAAAA.Herryknutsak:BAAALgAECgEJAQAAAA==.Hestonater:BAAALgADCggJCwAAAA==.',
Hi='Hidethetotem:BAABLgAECn8VAAIcAAcJ3hxiEAA6AgAcAAcJ3hxiEAA6AgAAAA==.Hightops:BAAALgAECggJDgAAAA==.Hikari:BAACLgAFFH8HAAICAAMJOQpKNADmAAACAAMJOQpKNADmAAAuAAQKfxwAAgIACAnOHd4sAHACAAIACAnOHd4sAHACAAAA.',
Ho='Holeliness:BAAALgAECggJEwAAAA==.Holybackshot:BAAALgAECgQJBgAAAA==.Holydisco:BAAALgADCgcJCQAAAA==.Holyhide:BAAALgADCgUJBQAAAA==.Holyspike:BAAALgAECgYJDwAAAA==.Holytard:BAAALgADCgYJBgAAAA==.Holytaren:BAAALgAECggJDAAAAA==.Holytickles:BAABLgAECn8gAAMIAAkJhxleCgBBAgAIAAgJ3BheCgBBAgATAAgJ+hu+CwAIAgABLgAFFAYJDAAXAKkQAA==.Holytotem:BAAALgADCggJCAAAAA==.Homerr:BAAALgAECgYJDwAAAA==.Honiahaka:BAABLgAECn8xAAIVAAkJ+gsuJwC2AQAVAAkJ+gsuJwC2AQAAAA==.Hottcakes:BAAALgADCgIJAgABLgAFFAYJDAAXAKkQAA==.',
Hu='Huckster:BAAALgAECggJEgAAAA==.Humanoidholy:BAABLgAECn8fAAMCAAgJXSQ3CQBIAwACAAgJXSQ3CQBIAwABAAEJbgXTTQAYAAABLgAFFAIJBAAUAMwbAA==.Humanoidhunt:BAAALgAECgIJAwABLgAFFAIJBAAUAMwbAA==.Humanoidvoid:BAACLgAFFH8EAAMUAAIJzBvtDACuAAAUAAIJ2xbtDACuAAAYAAEJriKmVABjAAAuAAQKfzwABBgACAl3I9oFAM4CABgACAk6I9oFAM4CABQABQlwJBMNALABAB4ABwlZB04OANwAAAAA.',
Ic='Icedtea:BAAALgAECgcJBAAAAA==.Icicle:BAAALgADCgIJAgAAAA==.',
Id='Idunasil:BAAALgADCgIJAgAAAA==.',
Ih='Ihatemustard:BAAALgAECggJEQAAAA==.',
Il='Illethan:BAAALgADCgYJBgAAAA==.Iloveketchup:BAAALgADCgQJBAAAAA==.',
In='Inoru:BAAALgAECgUJBwAAAA==.Insanity:BAAALgAECgUJCgAAAA==.',
Ir='Irmaline:BAAALgAECgYJDwAAAA==.',
It='Ithurtshuh:BAAALgAECgIJAwAAAA==.Itsmaam:BAAALgAECgMJBAAAAA==.Itzcannibal:BAABLgAECn8nAAMVAAgJ8RquGgD+AQAVAAgJ8RquGgD+AQAjAAIJ1QrpeQBaAAAAAA==.',
Ja='Jabbawockie:BAAALgAECgkJAgAAAA==.Jaekoby:BAAALgAECgEJAQABLgAECgcJFwABAMkYAA==.Jakoby:BAAALgAECgMJAwABLgAECgcJFwABAMkYAA==.Jandrisel:BAAALgAECgYJBwAAAA==.Jayzich:BAAALgADCgQJBwAAAA==.',
Je='Jeffee:BAAALgAECgIJCQAAAA==.Jequalsjosh:BAABLgAECn8wAAIZAAgJMR4cAgBUAgAZAAgJMR4cAgBUAgAAAA==.Jerk:BAAALgAECgQJBAAAAA==.Jerp:BAAALgAECgIJAgAAAA==.Jesper:BAABLgAECn80AAIcAAkJ5B+lAgAyAwAcAAkJ5B+lAgAyAwAAAA==.Jetz:BAAALgAECgEJAQAAAA==.Jezelle:BAACLgAFFH8IAAIXAAMJFg7sQwDTAAAXAAMJFg7sQwDTAAAuAAQKfyAAAhcACAkwHgg2ADQCABcACAkwHgg2ADQCAAAA.',
Ji='Jilara:BAABLgAECn8aAAICAAcJmQStfQDxAAACAAcJmQStfQDxAAAAAA==.Jimmyjim:BAAALgAECgYJDgAAAA==.Jingying:BAAALgADCgMJAwAAAA==.',
Jo='Johnny:BAAALgADCgQJBAAAAA==.',
Jp='Jpepps:BAABLgAECn8hAAMXAAkJnw9AUwAxAQAXAAkJbg9AUwAxAQAhAAMJxwjlRQCeAAAAAA==.',
Jr='Jrose:BAAALgAECgQJBAAAAA==.',
['Jæ']='Jækobÿ:BAAALgAECgIJAgABLgAECgcJFwABAMkYAA==.',
Ka='Kaiatra:BAAALgAECgYJDwAAAA==.Katare:BAAALgAECgMJAwAAAA==.Kaulder:BAAALgADCgUJBQAAAA==.Kaìju:BAABLgAECn8YAAICAAYJkCHnJwDhAQACAAYJkCHnJwDhAQAAAA==.',
Ke='Kellytgt:BAABLgAECn8hAAIYAAgJ8hcmGwDmAQAYAAgJ8hcmGwDmAQAAAA==.Kev:BAAALgADCgUJBQAAAA==.',
Ki='Kilaura:BAAALgAECggJEwAAAA==.Kilmandaros:BAAALgADCgYJCwAAAA==.Kippi:BAAALgAECgQJCQAAAA==.',
Ko='Korhina:BAABLgAECn80AAIDAAkJcSZBAAB2AwADAAkJcSZBAAB2AwAAAA==.Korobas:BAAALgAECgMJAwAAAA==.Koru:BAAALgAECgQJBQABLgAECgQJBgAGAAAAAA==.Kosumi:BAAALgADCggJDQAAAA==.',
Kr='Kronic:BAAALgAECgQJBAAAAA==.',
Ku='Kuroyukihime:BAABLgAECn8kAAIFAAgJvR1nGgBMAgAFAAgJvR1nGgBMAgAAAA==.Kuwaii:BAABLgAECn8ZAAISAAcJeRZpEwCuAQASAAcJeRZpEwCuAQABLgAECggJHgANAA0gAA==.',
Ky='Kyarina:BAAALgAECgEJAQABLgAECgkJGQAIAEMHAA==.Kylis:BAAALgAECgMJAwAAAA==.Kyna:BAABLgAECn8ZAAIIAAkJQwf3IwAqAQAIAAkJQwf3IwAqAQAAAA==.Kyross:BAAALgADCgIJAgAAAA==.',
['Ké']='Kéya:BAAALgADCgUJCAAAAA==.',
La='Lashela:BAAALgAECgYJEAAAAA==.Laughter:BAAALgAECgYJDwAAAA==.Laurana:BAAALgADCgIJAgAAAA==.Lazulie:BAAALgAECgUJBgAAAA==.',
Le='Leansipper:BAAALgAFFAMJBAAAAA==.Levoker:BAAALgAECgQJBAAAAA==.Lexapayne:BAAALgAECgQJBAABLgAECggJIwAVALAVAA==.',
Li='Lighthammer:BAAALgADCgEJAQAAAA==.Lilandra:BAAALgADCgkJHgABLgAECgIJAgAGAAAAAA==.Lillianaxe:BAAALgAECgYJBgAAAA==.Lilyvain:BAAALgAECgEJAQAAAA==.Lireal:BAABLgAECn8lAAIKAAgJxyTJAQBGAwAKAAgJxyTJAQBGAwAAAA==.Listerine:BAAALgAECgYJBgAAAA==.Litercola:BAAALgAECgEJAQAAAA==.Livnod:BAAALgAECgIJAwAAAA==.',
Lo='Lorine:BAABLgAECn8pAAIBAAkJqRmuBQAUAgABAAkJqRmuBQAUAgAAAA==.Lowkie:BAAALgADCgIJAgAAAA==.',
Lu='Luckside:BAAALgADCgkJDQABLgAECggJHAAXAAUNAA==.Lunara:BAAALgAECgIJAwAAAA==.Lunasnow:BAAALgAECgQJBAAAAA==.Lunchtime:BAAALgAECgEJAQAAAA==.Luxe:BAAALgADCgEJAQAAAA==.',
Ly='Lyntot:BAAALgADCgEJAQAAAA==.',
['Ló']='Lókki:BAAALgAECgUJCAAAAA==.',
Ma='Madwe:BAABLgAECn8cAAMYAAgJYQaVUAAHAQAYAAgJYQaVUAAHAQAUAAEJiwHxSAAdAAAAAA==.Mageab:BAAALgAFFAEJAQAAAA==.Magis:BAAALgADCgkJFgAAAA==.Malzzahar:BAAALgAECgQJBAAAAA==.Manimetal:BAAALgAECgMJAwAAAA==.',
Me='Meeralax:BAAALgAECgYJDwAAAA==.Melizza:BAAALgADCgMJAwAAAA==.Merckel:BAABLgAECn8hAAIYAAgJsx8lCwB6AgAYAAgJsx8lCwB6AgAAAA==.Merckz:BAAALgAECgEJAQABLgAECggJIQAYALMfAA==.Metalmonkey:BAAALgADCgMJBAAAAA==.',
Mi='Michello:BAAALgAECgYJDwAAAA==.Mickcowmoose:BAAALgADCgIJAgAAAA==.Millia:BAABLgAECn8WAAIFAAcJTBfOOwC0AQAFAAcJTBfOOwC0AQABLgAECggJFwACANMiAA==.Mint:BAABLgAECn8dAAIKAAcJjCP9EQCDAgAKAAcJjCP9EQCDAgAAAA==.Misstress:BAABLgAECn8fAAMNAAgJhAu6IQAqAQANAAcJ8Au6IQAqAQAMAAEJ/ggnLAAnAAAAAA==.Mizen:BAAALgADCgUJCAAAAA==.',
Mo='Mogdor:BAAALgADCgUJBQAAAA==.Monkussy:BAAALgAECgEJAQAAAA==.Moonhunt:BAAALgAECgIJAwAAAA==.Moonly:BAABLgAECn8dAAIkAAgJ7AtcEQCaAQAkAAgJ7AtcEQCaAQAAAA==.Morrag:BAAALgAECgYJDQAAAA==.',
Mu='Murdumurdu:BAAALgAECgUJCAAAAA==.Murkblade:BAAALgADCgYJBgABLgAECgYJGAAYAMAWAA==.Musho:BAAALgADCgUJDAAAAA==.',
My='Myn:BAAALgAECgcJEwAAAA==.Myw:BAAALgAECgcJBwABLgAFFAYJGwAcAJwYAA==.',
['Mæ']='Mædenless:BAAALgAECgYJBwAAAA==.',
['Mí']='Mísfìt:BAABLgAECn8qAAMcAAkJEBkdDgBWAgAcAAkJEBkdDgBWAgAHAAEJ0wUFjwApAAAAAA==.',
Na='Nakaito:BAAALgAECgYJDwABLgAECggJJAAZAGsXAA==.Narcoleptic:BAABLgAECn8tAAQRAAkJ7RhsAwCYAgARAAkJ7RhsAwCYAgASAAgJDBNoEwCuAQAiAAQJrgVKLwCdAAAAAA==.',
Ne='Neocracy:BAAALgADCgYJCwABLgAECggJDAAGAAAAAA==.Nex:BAAALgADCgYJCAAAAA==.',
Ni='Niceshield:BAAALgAECgEJAQAAAA==.Nightmarexx:BAACLgAFFH8QAAIaAAUJqhBBDQBGAQAaAAUJqhBBDQBGAQAuAAQKfz0AAhoACAl1H8wLANkCABoACAl1H8wLANkCAAAA.Nightsawdy:BAABLgAECn8VAAMkAAYJkBI4FwBTAQAkAAYJkBA4FwBTAQAVAAQJdBXxhQDWAAAAAA==.Nightsnake:BAAALgAECgMJAwAAAA==.Niightstorm:BAAALgAECgUJDwAAAA==.Nikwillig:BAAALgAECgYJCQAAAA==.Nilveron:BAAALgADCgcJCQAAAA==.Nitefire:BAAALgADCgkJDgAAAA==.',
Nj='Njörðr:BAAALgAECgYJDAAAAA==.',
Nt='Ntadadarknes:BAAALgAECgEJAQABLgAECggJIgAJAMwJAA==.',
Op='Opalinnas:BAABLgAECn8bAAMJAAkJTxb8IgCvAQAJAAkJTxb8IgCvAQANAAUJeQj5NAC6AAAAAA==.',
Oz='Ozath:BAAALgAECgQJBgAAAA==.',
Pa='Passionfruit:BAAALgAECgQJCQAAAA==.',
Pe='Peachtea:BAAALgAECgQJDAAAAA==.',
Ph='Phatshaman:BAABLgAECn8UAAIHAAgJbQd6KAAbAQAHAAgJbQd6KAAbAQAAAA==.Phæryll:BAAALgADCgUJBgAAAA==.',
Pi='Pirodeath:BAAALgAECgcJCQAAAA==.',
Po='Poisonclaw:BAAALgAECgIJAwAAAA==.Poprotonix:BAABLgAECn8UAAICAAYJXwj+hwDcAAACAAYJXwj+hwDcAAAAAA==.Pozessedkaos:BAAALgAECgQJBAAAAA==.',
Pr='Praecantrix:BAAALgAECgEJAgAAAA==.Prath:BAAALgADCgEJAQAAAA==.Pray:BAABLgAECn8xAAIlAAkJ0SLrAACSAwAlAAkJ0SLrAACSAwAAAA==.Priestyballz:BAAALgAECgYJBgAAAA==.Prodarkangel:BAABLgAECn8bAAMhAAkJIQnFCwAYAQAhAAkJIQnFCwAYAQAXAAMJaAMzsQBgAAAAAA==.',
Pu='Pubis:BAAALgAECgQJBwAAAA==.Puckllane:BAABLgAECn8aAAICAAkJ5RdfQQAhAgACAAkJ5RdfQQAhAgAAAA==.Punkbeer:BAAALgAECgEJAQAAAA==.Punkin:BAAALgAECgIJAwAAAA==.',
Py='Pyre:BAABLgAECn8sAAIlAAkJ5w1yHQCpAQAlAAkJ5w1yHQCpAQABLgADCgUJBQAGAAAAAA==.',
Qu='Quefstank:BAAALgADCgUJCAAAAA==.Quivver:BAAALgADCgkJCwAAAA==.',
Ra='Rabmaxx:BAAALgAECgYJEAAAAA==.Radren:BAAALgADCgEJAQAAAA==.Rajinazn:BAAALgADCgMJAwAAAA==.Rattchett:BAAALgAECgYJBgAAAA==.Ravenlight:BAAALgAFFAEJAQAAAA==.Ravenwynnd:BAABLgAECn8lAAImAAkJuyKcAAAzAwAmAAkJuyKcAAAzAwAAAA==.Raynelock:BAABLgAECn8oAAMhAAkJrw91BADDAQAhAAkJrw91BADDAQAXAAIJtQcVCQFKAAAAAA==.Raynman:BAABLgAECn8xAAIcAAkJcBVKEAA8AgAcAAkJcBVKEAA8AgAAAA==.Razix:BAABLgAECn8sAAQSAAkJghOmDQDyAQASAAkJghOmDQDyAQAiAAYJ6wmhDgCfAAARAAMJYwchPACJAAAAAA==.',
Re='Realist:BAAALgAECgMJBAAAAA==.Reija:BAAALgAECgEJAQAAAA==.Repentance:BAAALgADCgEJAQABLgAECgkJLQAdAAgWAA==.Revealed:BAAALgADCgEJAQAAAA==.Rezzarn:BAAALgAECgEJAQAAAA==.',
Rh='Rhun:BAAALgAECgYJCQAAAA==.Rhyzer:BAAALgAECgUJEQAAAA==.',
Ri='Rileyksufan:BAABLgAECn8VAAIVAAkJhQ4JOABtAQAVAAkJhQ4JOABtAQAAAA==.Rinas:BAABLgAECn8hAAIUAAgJoh59BQBeAgAUAAgJoh59BQBeAgAAAA==.Rivendell:BAAALgAECgEJAgAAAA==.',
Ru='Rubioxis:BAAALgADCgYJBgAAAA==.',
Ry='Rymarri:BAAALgADCgkJCQAAAA==.',
Sa='Sabazia:BAABLgAECn8vAAIgAAgJoR24BQBJAgAgAAgJoR24BQBJAgAAAA==.Sacrificer:BAAALgAECgMJAwAAAA==.Sairalindë:BAAALgAECgYJDgAAAA==.Salios:BAABLgAFFH8NAAIXAAQJNB6LHABCAQAXAAQJNB6LHABCAQAAAA==.Sallydisco:BAAALgAECgMJAwABLgAFFAQJCgADAN8hAA==.Sanctifier:BAAALgAECgQJDQAAAA==.Saraneth:BAAALgAECgEJAQABLgAECggJJQAKAMckAA==.',
Sc='Scandrel:BAAALgAECgQJBAABLgAFFAQJDAAEAGceAA==.Scrept:BAAALgAECgUJEQAAAA==.Scynix:BAEBLgAECn8mAAMSAAgJ7BjyDgDhAQASAAgJ7BjyDgDhAQARAAEJsgFaTgAiAAAAAA==.',
Se='Sedaline:BAAALgAECgQJBQAAAA==.Sephie:BAAALgADCgQJAQAAAQ==.Serenilock:BAAALgADCgMJAwAAAA==.Serfdog:BAAALgADCgQJBgAAAA==.Servoker:BAACLgAFFH8QAAIRAAUJaB1ACQBWAQARAAUJaB1ACQBWAQAuAAQKfyUAAxIACAnbIB8KANQCABIACAnbIB8KANQCABEABwkkGrcVAPABAAAA.Setani:BAAALgADCgIJAgAAAA==.',
Sh='Shabzkaw:BAAALgADCgUJBQAAAA==.Shaienne:BAAALgAECgEJAQAAAA==.Shambussy:BAAALgAECgEJAQAAAA==.Shamfore:BAAALgADCgEJAQAAAA==.Shamrockshak:BAAALgAECgUJEAAAAA==.Shenuton:BAAALgAECgMJBAAAAA==.Shiftkicker:BAAALgADCgMJAwAAAA==.Shockthêràpy:BAACLgAFFH8GAAIcAAIJ8BCpGgCQAAAcAAIJ8BCpGgCQAAAuAAQKfzAABBwACQlbGGwnAPMBABwACQlbGGwnAPMBAAcAAwkWF8Y5AMUAAB0AAQlPCkQrADgAAAAA.Shoes:BAABLgAECn80AAQkAAkJ0CQEAQAfAwAkAAkJeyEEAQAfAwAjAAgJIx/TDQDVAgAVAAgJ9SK6CQCaAgAAAA==.Shtdruid:BAAALgAECgUJBQAAAA==.Shyanni:BAAALgADCgMJAwAAAA==.',
Si='Siaana:BAAALgADCgUJBQABLgAECggJLwAgAKEdAA==.Sibearian:BAABLgAECn8WAAQMAAYJfBiTDwAOAQAMAAYJfBiTDwAOAQAnAAYJ0Ar/EQD+AAANAAIJPwR9dQBNAAAAAA==.Simi:BAABLgAECn8jAAIVAAgJsBWuKQCqAQAVAAgJsBWuKQCqAQAAAA==.',
Sk='Skrubzz:BAABLgAECn8ZAAMDAAgJIQboIAA4AQADAAgJIQboIAA4AQAQAAQJzgJ/hwChAAAAAA==.Skôrn:BAABLgAECn8kAAIFAAYJ7AzVcwApAQAFAAYJ7AzVcwApAQAAAA==.',
Sl='Sloppynachos:BAABLgAECn8pAAIaAAgJOhfvDgC1AQAaAAgJOhfvDgC1AQAAAA==.Slyman:BAAALgADCgUJBQABLgAECgYJBwAGAAAAAA==.',
Sm='Smithnwesson:BAAALgAECgEJAQAAAA==.Smokesçreen:BAABLgAECn8xAAMUAAkJyxpxBQBfAgAUAAkJyxpxBQBfAgAYAAEJRQXEywAkAAAAAA==.',
Sn='Snowhoof:BAAALgADCgUJBQAAAA==.',
So='Sogerä:BAABLgAECn8XAAIRAAgJIQX5EgAOAQARAAgJIQX5EgAOAQAAAA==.Soonerpride:BAABLgAECn8YAAICAAYJxiWnJgCLAgACAAYJxiWnJgCLAgAAAA==.Source:BAAALgAECgUJCAAAAA==.',
Sp='Spearminttea:BAAALgAECgcJCwAAAA==.Spellumgud:BAAALgAECgQJBgAAAA==.',
Sq='Squiby:BAABLgAECn8vAAMTAAkJxyHAAQAOAwATAAkJxyHAAQAOAwAIAAIJmRX2ZwCNAAAAAA==.Squizzy:BAAALgAECgEJAQAAAA==.',
St='Stabfore:BAAALgAECggJDQAAAA==.Standaside:BAAALgAECgIJBAAAAA==.Stinky:BAABLgAECn8XAAIbAAgJjgkVBgBNAQAbAAgJjgkVBgBNAQAAAA==.Stix:BAABLgAECn8WAAIaAAcJ6hYBIAD6AQAaAAcJ6hYBIAD6AQAAAA==.Stoya:BAAALgAECgEJAgABLgAECggJJQAKAMckAA==.Stuef:BAABLgAECn82AAIHAAkJGiFRAgADAwAHAAkJGiFRAgADAwAAAA==.Stuefagos:BAAALgAECgQJBwAAAA==.Stuefester:BAABLgAECn8XAAMEAAkJah/CCgC2AgAEAAkJah/CCgC2AgAgAAcJ4AliGwDqAAAAAA==.Stueflare:BAAALgAECggJEAAAAA==.Stueflip:BAAALgADCgIJAgAAAA==.Stunsturds:BAAALgAECgYJEwABLgAECgYJGAAYAMAWAA==.Stäirs:BAABLgAECn8wAAIQAAkJRBskBwB8AgAQAAkJRBskBwB8AgAAAA==.',
Su='Summerlily:BAAALgADCgYJBgAAAA==.',
Sv='Svaja:BAAALgADCgkJDgABLgAECgYJDwAGAAAAAA==.',
Sy='Sylaria:BAAALgAECgIJAwAAAA==.Syreline:BAAALgAECgEJAgAAAA==.',
['Sá']='Sáble:BAAALgAECgYJCwAAAA==.',
['Sî']='Sîn:BAAALgADCgEJAQABLgAECgYJGAAXAJEaAA==.',
['Sï']='Sïn:BAABLgAECn8YAAIXAAYJkRoROwB7AQAXAAYJkRoROwB7AQAAAA==.',
Ta='Taereachye:BAACLgAFFH8GAAIKAAIJriCCHQCzAAAKAAIJriCCHQCzAAAuAAQKfxcAAgoABwk5JAUKANMCAAoABwk5JAUKANMCAAAA.Tailon:BAAALgADCgYJBgAAAA==.Taintedlove:BAAALgADCgYJBgAAAA==.Talenelat:BAAALgADCgcJCwAAAA==.Talikas:BAAALgADCgkJCgABLgAECggJIQAYAPIXAA==.Tantric:BAAALgAECgIJAgABLgAECgYJBgAGAAAAAA==.Tarathiel:BAAALgADCgQJBAAAAA==.Taurne:BAACLgAFFH8PAAIJAAQJ4AyIGQAHAQAJAAQJ4AyIGQAHAQAuAAQKfx4AAgkABwmzGX4wAOkBAAkABwmzGX4wAOkBAAAA.',
Te='Technique:BAAALgADCgUJBQAAAA==.Teknoman:BAABLgAECn8vAAIQAAgJnh6FBwB0AgAQAAgJnh6FBwB0AgAAAA==.Telmarine:BAAALgAECgMJAwAAAA==.Tempered:BAAALgAECgkJBQAAAA==.Terlemen:BAAALgAECgUJBQAAAA==.Tetsumi:BAAALgADCgYJCQABLgAECgYJDQAGAAAAAA==.',
Th='Thaitea:BAAALgAECgUJBgAAAA==.Thal:BAAALgAECgMJAwAAAA==.Thalan:BAAALgADCgEJAQAAAA==.Thalindra:BAAALgAECgUJEQAAAA==.Tharain:BAAALgADCgkJDgAAAA==.Thecurt:BAABLgAECn8vAAIOAAkJNCTNAABJAwAOAAkJNCTNAABJAwAAAA==.Thedammed:BAAALgADCgEJAQAAAA==.Theholylight:BAAALgAECgMJAwAAAA==.Thehuzz:BAAALgAECgYJCgAAAA==.Thermidor:BAABLgAECn8gAAIkAAkJYBWgCQBFAgAkAAkJYBWgCQBFAgAAAA==.Thorsamie:BAAALgAECgIJAgAAAA==.Thundercunti:BAAALgADCgYJDAAAAA==.',
Ti='Tiamatt:BAAALgADCgIJBAAAAA==.Ticktock:BAAALgAECgIJAgAAAA==.Timaeus:BAAALgAECgMJAwAAAA==.Tinytotems:BAAALgADCgEJAQAAAA==.Titanlock:BAAALgAECgEJAQAAAA==.',
Tk='Tkdfath:BAAALgAECgQJBQAAAA==.',
To='Torvia:BAAALgAECgIJAwAAAA==.Totemix:BAAALgADCgcJEgAAAA==.',
Tr='Trisinz:BAABLgAECn8cAAINAAgJ/hKaFACcAQANAAgJ/hKaFACcAQAAAA==.Trixa:BAAALgADCgMJAwAAAA==.',
Tu='Tuerto:BAAALgAECgYJEQAAAA==.Turk:BAABLgAECn8yAAMYAAkJ1BQ5FgAKAgAYAAkJ1BQ5FgAKAgAUAAEJCQ++cwAxAAAAAA==.Turkish:BAABLgAECn8uAAIEAAkJhRn9FQBLAgAEAAkJhRn9FQBLAgAAAA==.Turtledisco:BAACLgAFFH8KAAIDAAQJ3yFpBABwAQADAAQJ3yFpBABwAQAuAAQKfyQAAgMACQmcH7kDABcDAAMACQmcH7kDABcDAAAA.',
Ty='Tychaa:BAAALgADCgkJDgAAAA==.Tylat:BAAALgADCgEJAgAAAA==.Tyranax:BAABLgAECn8rAAQlAAgJCxvSDAADAgAlAAgJhBjSDAADAgAIAAYJ1R9QHAD6AQATAAcJMhP3FwB+AQAAAA==.Tyyregade:BAAALgADCgkJCgABLgAECgYJDQAGAAAAAA==.',
Uj='Ujimas:BAAALgAECgEJAQAAAA==.',
Ur='Urawizardtui:BAACLgAFFH8IAAIFAAQJRQbGOQApAQAFAAQJRQbGOQApAQAuAAQKfzQAAwUACQnTHesKAMwCAAUACQnTHesKAMwCAAsABQmDCGMOAN0AAAAA.',
Us='Us:BAAALgAECggJCQAAAA==.',
Va='Vadose:BAABLgAECn8eAAIXAAcJgQpjYAAQAQAXAAcJgQpjYAAQAQABLgAECggJIwAVALAVAA==.Vales:BAAALgAECgMJAwABLgAECgkJHgAVAOwIAA==.Valsavis:BAAALgAECgYJEwAAAA==.Valytrois:BAAALgAECgYJDQAAAA==.Varinix:BAAALgADCgMJAwAAAA==.',
Ve='Veggiebaha:BAAALgADCgIJAgAAAA==.Veiksla:BAAALgAECgYJDwAAAA==.Velore:BAAALgADCgcJDAAAAA==.Vengerr:BAAALgAECgQJBAAAAA==.Verace:BAAALgAECgcJAQAAAA==.Verradic:BAAALgADCggJCAABLgAECgYJFwAVACMLAA==.',
Vi='Vitur:BAABLgAECn81AAIYAAkJ+SAVCQCTAgAYAAkJ+SAVCQCTAgAAAA==.',
Vo='Voidhunter:BAABLgAECn8VAAIYAAcJGQqIUwAAAQAYAAcJGQqIUwAAAQAAAA==.Voidweaver:BAAALgAECgMJBQAAAA==.Volaine:BAAALgAECgUJEQAAAA==.Volt:BAABLgAECn8tAAIdAAkJCBZ9AwBMAgAdAAkJCBZ9AwBMAgAAAA==.Volwryn:BAAALgAECgMJAwABLgAECgYJBgAGAAAAAA==.',
Vy='Vynarian:BAAALgAECgUJEQAAAA==.',
['Vâ']='Vâljean:BAAALgADCgMJAwAAAA==.',
['Vô']='Vôx:BAAALgAECgEJAQABLgAECgYJFgAPAGYcAA==.',
Wa='Warbeard:BAABLgAECn8fAAIQAAkJPAj8UABkAQAQAAkJPAj8UABkAQAAAA==.',
Wi='Wizwizx:BAAALgADCgUJBgAAAA==.',
Wr='Wreckd:BAAALgAECgkJCwAAAA==.',
Wy='Wyth:BAAALgAECgQJBQABLgAECgQJBgAGAAAAAA==.',
Xa='Xanthad:BAAALgADCgEJAQAAAA==.',
Xb='Xb:BAAALgADCgkJDgAAAA==.',
Xi='Xitãozinho:BAAALgAECgQJBQAAAA==.',
Xo='Xolair:BAAALgAECgUJCgAAAA==.',
Ya='Yaalia:BAAALgAECgUJDAAAAA==.Yaan:BAABLgAECn8ZAAIHAAYJBwyHNQDYAAAHAAYJBwyHNQDYAAAAAA==.',
Yo='Yoba:BAAALgAECgMJAwAAAA==.Yoshira:BAAALgADCgQJBAAAAA==.',
['Yö']='Yör:BAAALgAECgEJAQAAAA==.',
Za='Zain:BAABLgAECn80AAQmAAkJgxpKAgCmAgAmAAkJgxpKAgCmAgAQAAYJGA5YWQBIAQADAAIJKA1MLQBeAAAAAA==.Zandibar:BAAALgAECgUJEQAAAA==.Zaptoasted:BAAALgAECgEJAQAAAA==.Zaroff:BAAALgADCgcJBwAAAA==.',
Ze='Zedadiah:BAAALgADCgEJAQAAAA==.Zelah:BAAALgAECgQJBAAAAA==.Zellezugtail:BAAALgADCgkJDgABLgAECgYJDwAGAAAAAA==.Zenessa:BAAALgADCgYJBgAAAA==.',
Zi='Zinder:BAAALgAECgYJEQAAAA==.',
Zu='Zuggie:BAAALgAECgYJDwAAAA==.Zurtrinik:BAACLgAFFH8UAAIDAAUJsSFbAgCSAQADAAUJsSFbAgCSAQAuAAQKfyUAAgMACAmZJDsCAE0DAAMACAmZJDsCAE0DAAAA.',
Zz='Zzonked:BAABLgAECn8mAAMEAAkJuQc1RgBpAQAEAAkJfQY1RgBpAQAgAAIJ/gtDPwBSAAAAAA==.',
['Zê']='Zêp:BAAALgAECgEJAgAAAA==.',
['Zø']='Zøømies:BAABLgAECn8eAAIYAAgJ3xdfHgDSAQAYAAgJ3xdfHgDSAQAAAA==.',
['Äs']='Äshnärd:BAABLgAECn8vAAIcAAgJTiUQBAAEAwAcAAgJTiUQBAAEAwAAAA==.',
['Ða']='Ðar:BAAALgADCgEJAQAAAA==.',
['Ðo']='Ðoogle:BAAALgAECgYJDwAAAA==.',
['Ðr']='Ðruidess:BAAALgAECgMJAwAAAA==.',
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
