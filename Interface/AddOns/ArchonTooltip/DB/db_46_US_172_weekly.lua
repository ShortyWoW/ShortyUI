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

local lookup = {'Paladin-Protection','Paladin-Retribution','Warrior-Protection','DeathKnight-Unholy','Mage-Frost','Shaman-Elemental','Druid-Restoration','Unknown-Unknown','Paladin-Holy','Mage-Arcane','Druid-Balance','Druid-Guardian','Monk-Brewmaster','Monk-Windwalker','Warrior-Fury','Evoker-Preservation','Evoker-Augmentation','Priest-Shadow','DemonHunter-Havoc','Hunter-BeastMastery','Warlock-Affliction','Warlock-Demonology','DemonHunter-Devourer','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Shaman-Enhancement','Priest-Holy','DemonHunter-Vengeance','Monk-Mistweaver','Warlock-Destruction','DeathKnight-Blood','Evoker-Devastation','Hunter-Marksmanship','Shaman-Restoration','Hunter-Survival','Priest-Discipline','Warrior-Arms',}
local provider = {region='US',realm='Perenolde',name='US',type='weekly',zone=46,date='2026-05-01',data={Ad='Adrador:BAABLgAECn8WAAMBAAYJOCS3BgB6AgABAAYJOCS3BgB6AgACAAIJZxTmEwFvAAAAAA==.Adrenaline:BAACLgAFFH8FAAIDAAIJaRw8CgCoAAADAAIJaRw8CgCoAAAuAAQKfzMAAgMACQk1I3QAADMDAAMACQk1I3QAADMDAAAA.',
Ae='Aelik:BAABLgAECn8YAAIEAAcJPhw8HADeAQAEAAcJPhw8HADeAQAAAA==.',
Ah='Ahkimbo:BAAALgADCgUJBQAAAA==.',
Al='Alayssa:BAABLgAECn8ZAAIFAAcJUR6YHAAAAgAFAAcJUR6YHAAAAgAAAA==.Alda:BAAALgADCgYJCAAAAA==.Allarius:BAAALgAECgEJAQAAAA==.Allioops:BAAALgADCgUJBQAAAA==.Alnima:BAEBLgAECn8ZAAIGAAgJzgi1OQBoAQAGAAgJzgi1OQBoAQAAAA==.',
Am='Amilee:BAAALgAECgQJBQAAAA==.Amishhunter:BAAALgADCgEJAQAAAA==.Amoondai:BAAALgAFFAIJAwAAAA==.Amoondrin:BAABLgAECn8qAAIHAAkJJgm+IgBsAQAHAAkJJgm+IgBsAQAAAA==.Amplifier:BAAALgADCgUJBQAAAA==.',
An='Antichurch:BAAALgADCgEJAQAAAA==.Antregon:BAAALgADCgQJBwAAAA==.',
Ar='Araviin:BAAALgAECgYJDAAAAA==.Arazen:BAAALgAECgEJAQAAAA==.Arcillias:BAAALgADCgYJBgABLgAECgYJBgAIAAAAAA==.Arkride:BAAALgAECgEJAQAAAA==.Arnadaz:BAAALgADCgEJAQABLgAFFAIJBgAJALYgAA==.Arthia:BAAALgAECgQJDAAAAA==.Arvidpally:BAAALgADCgkJFQAAAA==.',
As='Ashmehameha:BAAALgADCgQJAgAAAA==.Asinn:BAAALgAECgEJAQAAAA==.Asoosimov:BAAALgADCgEJAQAAAA==.',
At='Atredes:BAAALgAECgIJAgAAAA==.Attima:BAABLgAECn8jAAIKAAkJRArqAQDBAQAKAAkJRArqAQDBAQAAAA==.',
Au='Aurøra:BAAALgADCgMJAwAAAA==.Auspex:BAABLgAECn8WAAMLAAcJdAdwIAD6AAALAAcJdAdwIAD6AAAMAAUJeAZPIwCCAAAAAA==.',
Av='Avaryn:BAACLgAFFH8FAAIHAAIJxRk0FwCnAAAHAAIJxRk0FwCnAAAuAAQKfzIAAgcACQnBH6cCACEDAAcACQnBH6cCACEDAAAA.',
Ba='Babavoss:BAAALgAECgkJAQAAAA==.Badarack:BAAALgAECgYJCgABLgAECggJMgANANEhAA==.Badarackie:BAABLgAECn8yAAMNAAgJ0SGfCQDvAgANAAgJ0SGfCQDvAgAOAAYJQBWqEwBSAQAAAA==.Badash:BAABLgAECn8UAAMDAAYJoxY7DQBMAQADAAYJoxY7DQBMAQAPAAEJMQSlrQAvAAAAAA==.Bahamuth:BAABLgAECn8lAAICAAkJ6hlACwByAgACAAkJ6hlACwByAgAAAA==.Barbattos:BAABLgAECn8yAAMQAAkJpSK0AABEAwAQAAkJpSK0AABEAwARAAEJ5iQuOQBsAAAAAA==.Barragon:BAAALgAECgYJBgAAAA==.',
Be='Bethollbrew:BAAALgAECgYJCwAAAA==.Bexley:BAAALgAECgkJDwAAAA==.',
Bi='Biggerbunny:BAABLgAECn8kAAISAAgJFxJ9CwDIAQASAAgJFxJ9CwDIAQAAAA==.',
Bl='Blackjax:BAAALgADCgEJAQAAAA==.Blacklok:BAAALgAECgQJBAABLgAECggJHQATAH0lAA==.Blargle:BAAALgAECgYJDwAAAA==.Bleubahlz:BAAALgADCgcJBwABLgAECgMJAwAIAAAAAA==.Bloodrake:BAABLgAECn8rAAIUAAkJIx2KCABwAgAUAAkJIx2KCABwAgAAAA==.Bloodreyne:BAAALgADCgEJAgAAAA==.',
Bo='Boahan:BAAALgAECgIJAgAAAA==.Boggart:BAAALgAECgEJAQAAAA==.Bohein:BAAALgADCgEJAQAAAA==.Bolus:BAAALgAECgEJAQAAAA==.Bownafiedba:BAAALgADCgUJBQAAAA==.',
Br='Braneour:BAABLgAECn8lAAMJAAgJ7xEODwDuAQAJAAgJ7xEODwDuAQACAAMJjAsVmwBvAAAAAA==.Browel:BAABLgAECn8VAAMVAAYJ3Rj3CAC3AQAVAAYJ3Rj3CAC3AQAWAAUJSwtmWgDiAAAAAA==.Bruen:BAAALgAECgYJBwAAAA==.',
Bu='Bubbloseven:BAAALgAECgIJAgAAAA==.Budank:BAAALgADCgMJAwAAAA==.Bumm:BAAALgAECgYJCQAAAA==.Bustybubbles:BAAALgADCgYJBgAAAA==.',
Bz='Bzspy:BAABLgAFFH8FAAIPAAMJywRNFADdAAAPAAMJywRNFADdAAAAAA==.',
Ca='Caalin:BAAALgAECgEJAgAAAA==.Cabooselul:BAAALgADCgYJBgAAAA==.Calibre:BAABLgAECn8YAAIXAAYJ0BUaMgAaAQAXAAYJ0BUaMgAaAQAAAA==.Calyptus:BAABLgAECn8WAAIWAAYJIQqtTQAHAQAWAAYJIQqtTQAHAQAAAA==.Caprious:BAACLgAFFH8FAAIEAAIJJBIXQQCfAAAEAAIJJBIXQQCfAAAuAAQKfzIAAgQACQn1I1MBAE8DAAQACQn1I1MBAE8DAAAA.Capylaura:BAAALgAECgUJDgAAAA==.Caratine:BAAALgAECgYJCwAAAA==.Cassandrar:BAABLgAECn8mAAQYAAkJkiIHAQA5AwAYAAgJMSQHAQA5AwAZAAYJlRl8OwA+AQAaAAEJphQxDQA/AAAAAA==.Cat:BAAALgADCgUJBQAAAA==.Cattlelac:BAAALgADCgUJCAAAAA==.Caymus:BAAALgAECgYJCgAAAA==.',
Ce='Celìa:BAAALgAECgYJEgAAAA==.Cess:BAAALgAECgEJAgAAAA==.',
Ch='Chema:BAAALgAFFAEJAQABLgAFFAIJBgAJALYgAA==.Chestylarue:BAAALgAECgEJAQAAAA==.Chfgaribaldi:BAAALgADCggJDgAAAA==.Chills:BAAALgAECgcJEQAAAA==.Chillymage:BAAALgADCgYJBgAAAA==.Chosen:BAABLgAECn8YAAICAAYJRBdtYgC+AQACAAYJRBdtYgC+AQABLgAFFAQJBwAEAJ0aAA==.Christy:BAAALgADCgYJCAAAAA==.Chugg:BAAALgAECgYJEwAAAA==.',
Ci='Ciaphus:BAAALgAECgkJCwAAAA==.',
Co='Coffeedemon:BAAALgADCgEJAQAAAA==.Coldslappins:BAAALgAECgIJAwAAAA==.Contagion:BAAALgAECgYJBQAAAA==.Convoke:BAABLgAECn8ZAAILAAcJDSApFgBeAgALAAcJDSApFgBeAgAAAA==.',
Cu='Curtastrophe:BAABLgAECn8rAAIFAAkJ4Rq5CwCIAgAFAAkJ4Rq5CwCIAgAAAA==.Curticus:BAAALgADCgMJAwAAAA==.Curtnought:BAAALgADCgIJAgAAAA==.',
['Cé']='Cérnùnnøs:BAAALgAECgEJAQAAAA==.',
Da='Daelanos:BAABLgAECn8cAAIPAAgJNxizCwDxAQAPAAgJNxizCwDxAQAAAA==.Dalinar:BAAALgAECgEJAQAAAA==.Darska:BAAALgADCgYJBgABLgAECgEJAQAIAAAAAA==.',
De='Deadtauren:BAAALgADCgUJBwAAAA==.Deathdemon:BAAALgAECgIJAgAAAA==.Deathfue:BAAALgAECgEJAQABLgAECgcJCAAIAAAAAA==.Deathisreal:BAAALgADCgMJAwABLgAECgIJAwAIAAAAAA==.Decimated:BAACLgAFFH8HAAIEAAQJnRpyFABeAQAEAAQJnRpyFABeAQAuAAQKfxcAAgQACQkwH9ELAGsCAAQACQkwH9ELAGsCAAAA.Demon:BAAALgAECgIJBAAAAA==.Dempkiston:BAAALgADCgcJCAAAAA==.Denable:BAAALgAECgUJCwAAAA==.Denogan:BAAALgAECgUJBQABLgAECgUJCQAIAAAAAA==.Deservis:BAAALgAECgUJCgABLgAECgYJGAAXANAVAA==.Destro:BAABLgAECn8WAAIWAAYJLwvHRgAcAQAWAAYJLwvHRgAcAQABLgAECgkJIgAbACASAA==.Dethadin:BAAALgADCgcJBwAAAA==.',
Di='Dirteemike:BAAALgADCgMJAwAAAA==.Disbeleaf:BAAALgAECgYJCAAAAA==.Discoflurry:BAAALgAECgcJCQABLgAFFAQJCgADANwhAA==.Dizzyfist:BAAALgAECgUJCAABLgAECgUJCQAIAAAAAA==.',
Do='Dogaz:BAAALgADCgYJBwAAAA==.Donori:BAAALgAECgQJDQAAAA==.Dorcath:BAAALgADCggJCAABLgAECggJHAAPADcYAA==.',
Dr='Dragonias:BAAALgAECgYJDAAAAA==.Draino:BAAALgADCgUJBQAAAA==.Dreselwings:BAAALgAECggJCAABLgAFFAYJFQAUAA8jAA==.Drinny:BAABLgAECn8dAAIcAAkJJQfiHAAdAQAcAAkJJQfiHAAdAQAAAA==.Drqueenisin:BAAALgADCggJEwAAAA==.Druido:BAAALgADCgYJCAAAAA==.',
Du='Duerek:BAAALgAECgEJAQAAAA==.Duro:BAAALgAECgkJCQAAAA==.',
['Dè']='Dèaths:BAAALgAECgYJEAAAAA==.',
Ea='Earthangel:BAAALgAECgUJCwAAAA==.',
Ed='Edlarel:BAAALgADCgQJBAABLgAECgUJBQAIAAAAAA==.',
Ei='Eine:BAABLgAECn8nAAIUAAkJuQ5WGgDCAQAUAAkJuQ5WGgDCAQAAAA==.Eitherwind:BAAALgAECgUJCQAAAA==.',
El='Eldergreen:BAABLgAECn8eAAIHAAgJtgnSMwAJAQAHAAgJtgnSMwAJAQAAAA==.Eldest:BAAALgADCgUJBQAAAA==.Elfwine:BAAALgAECgUJCgAAAA==.Elindria:BAABLgAECn8dAAQTAAgJfSVQDACcAgATAAgJfSVQDACcAgAXAAQJUhqyewA0AQAdAAIJLCC0HwCIAAAAAA==.Elminstir:BAAALgAECgYJCgAAAA==.Elynisa:BAAALgAECgEJAQAAAA==.Elysian:BAABLgAECn8cAAMOAAkJfxwgFgA4AgAOAAgJqhsgFgA4AgAeAAkJgxW3IQClAQAAAA==.',
Em='Emogo:BAAALgADCgUJCQAAAA==.',
En='Enforcer:BAAALgADCgQJBgAAAA==.Enlightened:BAAALgAECgQJBwAAAA==.',
Er='Erendora:BAABLgAECn8WAAIHAAYJJxJHLQAqAQAHAAYJJxJHLQAqAQAAAA==.Eridar:BAAALgAECgYJBgAAAA==.Erizhal:BAAALgAECgQJBwAAAA==.Erodora:BAAALgADCgEJAQAAAA==.',
Ev='Eva:BAAALgADCgEJAgAAAA==.Eviae:BAAALgAECgUJCwAAAA==.Evillure:BAAALgAECgcJDgAAAA==.',
Fa='Falan:BAAALgAECgcJDQAAAA==.Fatherjoe:BAAALgADCgYJBgAAAA==.Fayze:BAEALgAECgcJDAABLgAECgYJCgAIAAAAAA==.',
Fe='Felbreaker:BAAALgAECgYJCQAAAA==.Feår:BAABLgAECn8XAAMWAAgJRgxLVQDxAAAWAAcJdglLVQDxAAAfAAMJ3Q8MSwCMAAAAAA==.',
Fi='Finley:BAAALgAECgMJAwAAAA==.Fircane:BAAALgADCgQJBAAAAA==.',
Fl='Flane:BAAALgAECgUJBwABLgAFFAUJEwADALEhAA==.Flem:BAAALgAECgMJBAAAAA==.Flexdruid:BAAALgAECgEJAQAAAA==.',
Fo='Foog:BAAALgADCgkJDQAAAA==.',
Fr='Fragil:BAABLgAECn8XAAIZAAYJPBzkIgDiAQAZAAYJPBzkIgDiAQAAAA==.Frostmane:BAACLgAFFH8GAAIEAAMJyh28KgATAQAEAAMJyh28KgATAQAuAAQKfyQAAwQACQl4IQkEAO0CAAQACQmFHwkEAO0CACAABwn+HL8NADECAAAA.Frostynug:BAAALgADCgYJBgAAAA==.',
Fu='Furbyn:BAAALgADCgIJAgAAAA==.',
Ga='Galena:BAAALgAECgYJCwAAAA==.Gallamier:BAAALgADCgEJAQAAAA==.Gamerinator:BAAALgADCgcJCwAAAA==.',
Ge='Geshtal:BAAALgAECgQJBwAAAA==.',
Gi='Girion:BAAALgAECgUJCwAAAA==.Girliepop:BAAALgAECgEJAQAAAA==.',
Gl='Glaiven:BAECLgAFFH8FAAMXAAIJBRDDNwB9AAAXAAIJrQnDNwB9AAAdAAEJiw4pBgBAAAAuAAQKfykAAx0ACQl/IM8AALICAB0ACQmVHM8AALICABcACAmdHqEdAKACAAAA.Glyr:BAAALgADCgUJBQAAAA==.',
Go='Gorgrin:BAAALgAECgQJBQAAAA==.',
Gr='Greenback:BAAALgADCgYJCwAAAA==.Greentotes:BAABLgAECn8vAAMRAAkJ0R+FAQAGAwARAAkJ0R+FAQAGAwAhAAQJdgYuLgCoAAAAAA==.',
Gu='Gunter:BAAALgAECgMJAwABLgAFFAQJBwAEAJ0aAA==.Gura:BAAALgADCgEJAQAAAA==.Gurnee:BAAALgADCgcJDQABLgAECgcJCgAIAAAAAA==.Guthix:BAAALgAECgUJBgAAAA==.',
['Gê']='Gêm:BAABLgAECn8YAAIQAAYJyRchCQCPAQAQAAYJyRchCQCPAQAAAA==.',
['Gï']='Gïmlï:BAAALgADCgMJAwAAAA==.',
Ha='Haildydra:BAAALgAECgEJAQABLgAECgcJCAAIAAAAAA==.Halnan:BAAALgADCgEJAQABLgAECgYJGAAXANAVAA==.Harkanum:BAABLgAECn8rAAMQAAkJpQyMCgBtAQAQAAkJpQyMCgBtAQARAAQJrxNuKADMAAAAAA==.Hatebreéd:BAAALgAECgEJAQAAAA==.',
He='Healinturds:BAAALgADCgcJBwABLgAECgYJGAAXANAVAA==.Hector:BAABLgAECn8VAAICAAgJzyJIHwCwAgACAAgJzyJIHwCwAgAAAA==.Helloagain:BAACLgAFFH8JAAIFAAMJ6xRKMgAEAQAFAAMJ6xRKMgAEAQAuAAQKfxsAAgUABgm8ISBdACMCAAUABgm8ISBdACMCAAAA.Herryknutsak:BAAALgAECgEJAQAAAA==.Hestonater:BAAALgADCggJCgAAAA==.',
Hi='Hidethetotem:BAAALgAECgYJDgAAAA==.Hightops:BAAALgAECggJDgAAAA==.Hikari:BAABLgAECn8cAAICAAgJyB3gLABwAgACAAgJyB3gLABwAgAAAA==.',
Ho='Holeliness:BAAALgAECggJEwAAAA==.Holybackshot:BAAALgAECgQJBgAAAA==.Holydisco:BAAALgADCgcJCQAAAA==.Holyhide:BAAALgADCgUJBQAAAA==.Holyspike:BAAALgAECgYJCwAAAA==.Holytard:BAAALgADCgYJBgAAAA==.Holytaren:BAAALgAECgQJBAAAAA==.Holytickles:BAABLgAECn8YAAISAAgJ9RtJBwAUAgASAAgJ9RtJBwAUAgABLgAFFAYJDAAWAK4QAA==.Holytotem:BAAALgADCggJCAAAAA==.Homerr:BAAALgAECgYJCwAAAA==.Honiahaka:BAABLgAECn8lAAIUAAkJDQtDIgCVAQAUAAkJDQtDIgCVAQAAAA==.Hottcakes:BAAALgADCgIJAgABLgAFFAYJDAAWAK4QAA==.',
Hu='Huckster:BAAALgAECgYJDwAAAA==.Humanoidholy:BAABLgAECn8fAAMCAAgJXSQ5CQBIAwACAAgJXSQ5CQBIAwABAAEJbgXWTQAYAAABLgAECggJJwAXAF8hAA==.Humanoidhunt:BAAALgAECgIJAwABLgAECggJJwAXAF8hAA==.Humanoidvoid:BAABLgAECn8nAAQXAAgJXyE5BACpAgAXAAgJXyE5BACpAgAdAAcJqAayCgDvAAATAAMJOBk7TgC0AAAAAA==.',
Ic='Icicle:BAAALgADCgIJAgAAAA==.',
Id='Idunasil:BAAALgADCgIJAgAAAA==.',
Ih='Ihatemustard:BAAALgAECggJDwAAAA==.',
Il='Illethan:BAAALgADCgYJBgAAAA==.',
In='Inoru:BAAALgAECgIJAgAAAA==.Insanity:BAAALgAECgQJCAAAAA==.',
Ir='Irmaline:BAAALgAECgYJCwAAAA==.',
It='Ithurtshuh:BAAALgAECgIJAwAAAA==.Itsmaam:BAAALgAECgMJBAAAAA==.Itzcannibal:BAABLgAECn8fAAMUAAgJGhnNGgC/AQAUAAgJGhnNGgC/AQAiAAIJ1QrheQBaAAAAAA==.',
Ja='Jabbawockie:BAAALgAECgkJAgAAAA==.Jakoby:BAAALgAECgMJAwABLgAECgYJFAABANIYAA==.Jandrisel:BAAALgAECgIJAgAAAA==.Jayzich:BAAALgADCgQJBwAAAA==.',
Je='Jeffee:BAAALgAECgIJBwAAAA==.Jequalsjosh:BAABLgAECn8iAAIYAAgJQR2kAgDDAgAYAAgJQR2kAgDDAgAAAA==.Jerk:BAAALgAECgQJBAAAAA==.Jerp:BAAALgADCggJIQAAAA==.Jesper:BAABLgAECn8rAAIjAAkJ4R9rAQAxAwAjAAkJ4R9rAQAxAwAAAA==.Jetz:BAAALgAECgEJAQAAAA==.Jezelle:BAACLgAFFH8FAAIWAAMJZQy5MADjAAAWAAMJZQy5MADjAAAuAAQKfyAAAhYACAklHgk2ADQCABYACAklHgk2ADQCAAAA.',
Ji='Jilara:BAAALgAECgYJEwAAAA==.Jimmyjim:BAAALgAECgYJCgAAAA==.Jingying:BAAALgADCgMJAwAAAA==.',
Jo='Johnny:BAAALgADCgQJBAAAAA==.',
Jp='Jpepps:BAABLgAECn8hAAMWAAkJnQ/GPQA5AQAWAAkJbA/GPQA5AQAfAAMJxwjkRQCeAAAAAA==.',
Jr='Jrose:BAAALgAECgQJBAAAAA==.',
['Jæ']='Jækobÿ:BAAALgADCgcJEgABLgAECgYJFAABANIYAA==.',
Ka='Kaiatra:BAAALgAECgYJCwAAAA==.Katare:BAAALgAECgMJAwAAAA==.Kaulder:BAAALgADCgUJBQAAAA==.Kaìju:BAAALgAECgUJEgAAAA==.',
Ke='Kellytgt:BAAALgAECgYJEQAAAA==.Kev:BAAALgADCgUJBQAAAA==.',
Ki='Kilaura:BAAALgAECgUJCgAAAA==.Kilmandaros:BAAALgADCgYJCwAAAA==.Kippi:BAAALgAECgQJBwAAAA==.',
Ko='Korhina:BAABLgAECn8rAAIDAAkJHCYwAABqAwADAAkJHCYwAABqAwAAAA==.Korobas:BAAALgAECgMJAwAAAA==.Koru:BAAALgAECgQJBQABLgAECgQJBgAIAAAAAA==.Kosumi:BAAALgADCggJDQAAAA==.',
Kr='Kronic:BAAALgADCgcJDAAAAA==.',
Ku='Kuroyukihime:BAABLgAECn8kAAIFAAgJvR0/EABbAgAFAAgJvR0/EABbAgAAAA==.Kuwaii:BAAALgAECgcJEwABLgAECggJGQALAA0gAA==.',
Ky='Kyarina:BAAALgAECgEJAQABLgAECgkJGAAcACkHAA==.Kylis:BAAALgAECgMJAwAAAA==.Kyna:BAABLgAECn8YAAIcAAkJKQcaHAAlAQAcAAkJKQcaHAAlAQAAAA==.Kyross:BAAALgADCgEJAQAAAA==.',
['Ké']='Kéya:BAAALgADCgUJBQAAAA==.',
La='Lashela:BAAALgAECgYJDgAAAA==.Laughter:BAAALgAECgYJCwAAAA==.Laurana:BAAALgADCgIJAgAAAA==.Lazulie:BAAALgAECgUJBQAAAA==.',
Le='Leansipper:BAAALgAFFAEJAQAAAA==.Levoker:BAAALgAECgQJBAAAAA==.Lexapayne:BAAALgADCgEJAQABLgAECggJIQAUAC8VAA==.',
Li='Lighthammer:BAAALgADCgEJAQAAAA==.Lilandra:BAAALgADCgkJHgABLgAECgEJAQAIAAAAAA==.Lillianaxe:BAAALgAECgYJBgAAAA==.Lilyvain:BAAALgAECgEJAQAAAA==.Lireal:BAABLgAECn8iAAIJAAgJziGsAgDqAgAJAAgJziGsAgDqAgAAAA==.Listerine:BAAALgAECgUJBQAAAA==.Livnod:BAAALgAECgEJAQAAAA==.',
Lo='Lorine:BAABLgAECn8nAAIBAAkJ+xjSAwAeAgABAAkJ+xjSAwAeAgAAAA==.Lowkie:BAAALgADCgIJAgAAAA==.',
Lu='Luckside:BAAALgADCgkJDQABLgAECggJFwAWAEYMAA==.',
Ly='Lyntot:BAAALgADCgEJAQAAAA==.',
['Ló']='Lókki:BAAALgAECgUJCAAAAA==.',
Ma='Madwe:BAABLgAECn8aAAMXAAgJMQZuNgAJAQAXAAgJMQZuNgAJAQATAAEJigHKOAAeAAAAAA==.Magis:BAAALgADCgkJFAAAAA==.Malzzahar:BAAALgAECgQJBAAAAA==.Manimetal:BAAALgAECgEJAQAAAA==.',
Me='Meeralax:BAAALgAECgYJDQAAAA==.Melizza:BAAALgADCgMJAwAAAA==.Merckel:BAABLgAECn8ZAAIXAAcJ6B0QEADwAQAXAAcJ6B0QEADwAQAAAA==.',
Mi='Michello:BAAALgAECgYJCwAAAA==.Mickcowmoose:BAAALgADCgIJAgAAAA==.Millia:BAAALgAECgYJDwABLgAECggJFQACAM8iAA==.Mint:BAABLgAECn8dAAIJAAcJiyORCABPAgAJAAcJiyORCABPAgAAAA==.Misstress:BAABLgAECn8YAAMLAAcJBAv2IwDhAAALAAYJawv2IwDhAAAMAAEJ/ginIAAnAAAAAA==.Mizen:BAAALgADCgUJCAAAAA==.',
Mo='Mogdor:BAAALgADCgUJBQAAAA==.Moonhunt:BAAALgAECgEJAQAAAA==.Moonly:BAABLgAECn8bAAIkAAgJpAv3CwCfAQAkAAgJpAv3CwCfAQAAAA==.Morrag:BAAALgAECgYJDQAAAA==.',
Mu='Murdumurdu:BAAALgAECgUJCAAAAA==.Murkblade:BAAALgADCgYJBgABLgAECgYJGAAXANAVAA==.Musho:BAAALgADCgUJDAAAAA==.',
My='Myn:BAAALgAECgYJDAAAAA==.Myw:BAAALgAECgcJBwABLgAFFAUJFQAjADwXAA==.',
['Mí']='Mísfìt:BAABLgAECn8hAAMjAAkJsRfnKwDcAQAjAAkJsRfnKwDcAQAGAAEJ0wUHjwApAAAAAA==.',
Na='Nakaito:BAAALgAECgYJCwAAAA==.Narcoleptic:BAABLgAECn8iAAQQAAgJChsTAwByAgAQAAgJChsTAwByAgARAAgJ3Q8sEACOAQAhAAQJrgVNLwCdAAAAAA==.',
Ne='Neocracy:BAAALgADCgYJCwABLgAECgQJBAAIAAAAAA==.Nex:BAAALgADCgYJCAAAAA==.',
Ni='Niceshield:BAAALgAECgEJAQAAAA==.Nightmarexx:BAACLgAFFH8MAAIZAAQJ8g1lCQBJAQAZAAQJ8g1lCQBJAQAuAAQKfz0AAhkACAluH8wLANkCABkACAluH8wLANkCAAAA.Nightsawdy:BAAALgAECgYJDwAAAA==.Nightsnake:BAAALgAECgMJAwAAAA==.Niightstorm:BAAALgAECgUJCQAAAA==.Nikwillig:BAAALgAECgUJCAAAAA==.Nilveron:BAAALgADCgcJCQAAAA==.Nitefire:BAAALgADCgYJCAAAAA==.',
Nj='Njörðr:BAAALgAECgYJDAAAAA==.',
Nt='Ntadadarknes:BAAALgAECgEJAQABLgAECggJHgAHALYJAA==.',
Op='Opalinnas:BAABLgAECn8YAAMHAAgJlBf7IQByAQAHAAgJlBf7IQByAQALAAUJdQj4KADBAAAAAA==.',
Oz='Ozath:BAAALgAECgQJBgAAAA==.',
Pa='Passionfruit:BAAALgAECgQJCAAAAA==.',
Pe='Peachtea:BAAALgAECgQJCQAAAA==.',
Ph='Phatshaman:BAABLgAECn8UAAIGAAgJagchHgAmAQAGAAgJagchHgAmAQAAAA==.Phæryll:BAAALgADCgUJBgAAAA==.',
Pi='Pirodeath:BAAALgAECgcJCAAAAA==.',
Po='Poisonclaw:BAAALgAECgIJAwAAAA==.Poprotonix:BAAALgAECgYJEgAAAA==.Pozessedkaos:BAAALgAECgQJBAAAAA==.',
Pr='Praecantrix:BAAALgAECgEJAgAAAA==.Prath:BAAALgADCgEJAQAAAA==.Pray:BAABLgAECn8lAAIlAAkJSCK8AAB1AwAlAAkJSCK8AAB1AwAAAA==.Priestyballz:BAAALgAECgYJBgAAAA==.Prodarkangel:BAABLgAECn8UAAMfAAcJBwiQKwARAQAfAAcJBwiQKwARAQAWAAIJTQRimwBLAAAAAA==.',
Pu='Pubis:BAAALgAECgEJAwAAAA==.Puckllane:BAABLgAECn8aAAICAAkJ5RdfQQAhAgACAAkJ5RdfQQAhAgAAAA==.Punkbeer:BAAALgAECgEJAQAAAA==.Punkin:BAAALgAECgEJAQAAAA==.',
Py='Pyre:BAABLgAECn8mAAIlAAkJOw1yHQCpAQAlAAkJOw1yHQCpAQABLgADCgUJBQAIAAAAAA==.',
Qu='Quefstank:BAAALgADCgUJCAAAAA==.Quivver:BAAALgADCgUJBQAAAA==.',
Ra='Rabmaxx:BAAALgAECgYJDwAAAA==.Radren:BAAALgADCgEJAQAAAA==.Rajinazn:BAAALgADCgMJAwAAAA==.Rattchett:BAAALgAECgYJBgAAAA==.Ravenlight:BAAALgAFFAEJAQAAAA==.Ravenwynnd:BAABLgAECn8cAAImAAkJwhtwBACoAgAmAAkJwhtwBACoAgAAAA==.Raynelock:BAABLgAECn8oAAMfAAkJqw8KAwDKAQAfAAkJqw8KAwDKAQAWAAIJtQcICQFKAAAAAA==.Raynman:BAABLgAECn8lAAIjAAkJZBVJCgBFAgAjAAkJZBVJCgBFAgAAAA==.Razix:BAABLgAECn8lAAQRAAkJ8hBFFABfAQARAAgJvBJFFABfAQAhAAYJwAk9CwCyAAAQAAMJYwccPACJAAAAAA==.',
Re='Realist:BAAALgAECgMJBAAAAA==.Repentance:BAAALgADCgEJAQABLgAECgkJIgAbACASAA==.Revealed:BAAALgADCgEJAQAAAA==.',
Rh='Rhun:BAAALgAECgYJCQAAAA==.Rhyzer:BAAALgAECgUJCwAAAA==.',
Ri='Rileyksufan:BAABLgAECn8VAAIUAAkJhQ5DJgCAAQAUAAkJhQ5DJgCAAQAAAA==.Rinas:BAABLgAECn8YAAITAAgJ5h0nBQAfAgATAAgJ5h0nBQAfAgAAAA==.Rivendell:BAAALgAECgEJAQAAAA==.',
Ru='Rubioxis:BAAALgADCgYJBgAAAA==.',
Sa='Sabazia:BAABLgAECn8nAAIgAAgJvBsmBgDIAQAgAAgJvBsmBgDIAQAAAA==.Sacrificer:BAAALgAECgMJAwAAAA==.Sairalindë:BAAALgAECgYJDgAAAA==.Salios:BAABLgAFFH8LAAIWAAQJNR7DFgBDAQAWAAQJNR7DFgBDAQAAAA==.Sallydisco:BAAALgADCgYJCQABLgAFFAQJCgADANwhAA==.Sanctifier:BAAALgAECgQJCQAAAA==.Saraneth:BAAALgAECgEJAQABLgAECggJIgAJAM4hAA==.',
Sc='Scandrel:BAAALgAECgQJBAABLgAFFAQJBwAEAJ0aAA==.Scrept:BAAALgAECgUJEQAAAA==.Scynix:BAEBLgAECn8kAAMRAAgJXBZfDADCAQARAAgJXBZfDADCAQAQAAEJsgFUTgAiAAAAAA==.',
Se='Sedaline:BAAALgAECgQJBQAAAA==.Sephie:BAAALgADCgQJAQAAAQ==.Serenilock:BAAALgADCgMJAwAAAA==.Serfdog:BAAALgADCgQJBgAAAA==.Servoker:BAACLgAFFH8QAAIQAAUJWB18BwBnAQAQAAUJWB18BwBnAQAuAAQKfyUAAxEACAnbICMKANQCABEACAnbICMKANQCABAABwkkGrIVAPABAAAA.Seräphina:BAABLgAECn8dAAIFAAYJhgzyWgAnAQAFAAYJhgzyWgAnAQAAAA==.Setani:BAAALgADCgIJAgAAAA==.',
Sh='Shabzkaw:BAAALgADCgUJBQAAAA==.Shaienne:BAAALgAECgEJAQAAAA==.Shambussy:BAAALgADCgEJAQAAAA==.Shamfore:BAAALgADCgEJAQAAAA==.Shamrockshak:BAAALgAECgUJCgAAAA==.Shenuton:BAAALgAECgIJAwAAAA==.Shiftkicker:BAAALgADCgMJAwAAAA==.Shockthêràpy:BAACLgAFFH8FAAIjAAIJOQ6mGgCQAAAjAAIJOQ6mGgCQAAAuAAQKfzAABCMACQlaGHYZAJcBACMACQlaGHYZAJcBAAYAAwkPF+QsAM0AABsAAQlPCkErADgAAAAA.Shoes:BAABLgAECn8rAAQUAAkJkSTSBACvAgAiAAgJJR+8DQDUAgAUAAgJviLSBACvAgAkAAUJ9iCdBwDtAQAAAA==.Shyanni:BAAALgADCgMJAwAAAA==.',
Si='Siaana:BAAALgADCgUJBQABLgAECggJJwAgALwbAA==.Sibearian:BAAALgAECgYJEAAAAA==.Simi:BAABLgAECn8hAAIUAAgJLxUWHgCrAQAUAAgJLxUWHgCrAQAAAA==.',
Sk='Skrubzz:BAABLgAECn8ZAAMDAAgJIgboIAA4AQADAAgJIgboIAA4AQAPAAQJzgJ5hwChAAAAAA==.',
Sl='Sloppynachos:BAABLgAECn8pAAIZAAgJOBczCgDGAQAZAAgJOBczCgDGAQAAAA==.Slyman:BAAALgADCgUJBQABLgAECgYJBwAIAAAAAA==.',
Sm='Smokesçreen:BAABLgAECn8uAAITAAkJiRhFBAA/AgATAAkJiRhFBAA/AgAAAA==.',
Sn='Snowhoof:BAAALgADCgUJBQAAAA==.',
So='Sogerä:BAABLgAECn8XAAIQAAgJGAVvDgAaAQAQAAgJGAVvDgAaAQAAAA==.Soonerpride:BAABLgAECn8XAAICAAYJBiWoJgCLAgACAAYJBiWoJgCLAgAAAA==.Source:BAAALgAECgUJCAAAAA==.',
Sp='Spearminttea:BAAALgAECgcJBwAAAA==.Spellumgud:BAAALgAECgQJBgAAAA==.',
Sq='Squiby:BAABLgAECn8mAAMSAAkJaSCeCgDWAQASAAkJaSCeCgDWAQAcAAIJmRXqZwCNAAAAAA==.Squizzy:BAAALgAECgEJAQAAAA==.',
St='Stabfore:BAAALgAECgUJBQAAAA==.Standaside:BAAALgAECgIJAgAAAA==.Stinky:BAABLgAECn8XAAIaAAgJjwkiBABWAQAaAAgJjwkiBABWAQAAAA==.Stix:BAAALgAECgcJEQAAAA==.Stoya:BAAALgAECgEJAQABLgAECggJIgAJAM4hAA==.Stuef:BAABLgAECn8qAAIGAAkJ/R91AgDCAgAGAAkJ/R91AgDCAgAAAA==.Stuefagos:BAAALgAECgQJBwAAAA==.Stuefester:BAAALgAECgkJDgAAAA==.Stueflare:BAAALgAECggJEAAAAA==.Stueflip:BAAALgADCgIJAgAAAA==.Stunsturds:BAAALgAECgYJDgABLgAECgYJGAAXANAVAA==.Stäirs:BAABLgAECn8lAAIPAAkJfBeaBQBeAgAPAAkJfBeaBQBeAgAAAA==.',
Su='Summerlily:BAAALgADCgYJBgAAAA==.',
Sv='Svaja:BAAALgADCgYJCAABLgAECgYJCwAIAAAAAA==.',
Sy='Sylaria:BAAALgAECgEJAQAAAA==.Syreline:BAAALgAECgEJAQAAAA==.',
['Sî']='Sîn:BAAALgADCgEJAQABLgAECgUJEgAIAAAAAA==.',
['Sï']='Sïn:BAAALgAECgUJEgAAAA==.',
Ta='Taereachye:BAACLgAFFH8GAAIJAAIJtiD/FADDAAAJAAIJtiD/FADDAAAuAAQKfxcAAgkABwk5JAQKANMCAAkABwk5JAQKANMCAAAA.Tailon:BAAALgADCgYJBgAAAA==.Taintedlove:BAAALgADCgYJBgAAAA==.Talenelat:BAAALgADCgcJCwAAAA==.Tantric:BAAALgAECgIJAgABLgAECgUJBQAIAAAAAA==.Tarathiel:BAAALgADCgQJBAAAAA==.Taurne:BAACLgAFFH8LAAIHAAQJ1gqAEwAAAQAHAAQJ1gqAEwAAAQAuAAQKfx4AAgcABwmzGYIwAOkBAAcABwmzGYIwAOkBAAAA.',
Te='Technique:BAAALgADCgUJBQAAAA==.Teknoman:BAABLgAECn8nAAIPAAgJHh2NBgBJAgAPAAgJHh2NBgBJAgAAAA==.Telmarine:BAAALgAECgMJAwAAAA==.Terlemen:BAAALgAECgUJBQAAAA==.Tetsumi:BAAALgADCgYJCQABLgAECgUJCQAIAAAAAA==.',
Th='Thaitea:BAAALgAECgQJBAAAAA==.Thal:BAAALgADCgEJAQAAAA==.Thalan:BAAALgADCgEJAQAAAA==.Thalindra:BAAALgAECgUJCwAAAA==.Tharain:BAAALgADCgYJCAAAAA==.Thecurt:BAABLgAECn8lAAINAAkJuyODAABBAwANAAkJuyODAABBAwAAAA==.Thedammed:BAAALgADCgEJAQAAAA==.Thehuzz:BAAALgAECgQJBAAAAA==.Thermidor:BAABLgAECn8gAAIkAAkJXBWhCQBFAgAkAAkJXBWhCQBFAgAAAA==.Thorsamie:BAAALgAECgEJAQAAAA==.Thundercunti:BAAALgADCgYJDAAAAA==.',
Ti='Tiamatt:BAAALgADCgIJBAAAAA==.Ticktock:BAAALgAECgIJAgAAAA==.Timaeus:BAAALgAECgMJAwAAAA==.Tinytotems:BAAALgADCgEJAQAAAA==.Titanlock:BAAALgAECgEJAQAAAA==.',
To='Torvia:BAAALgAECgEJAQAAAA==.Totemix:BAAALgADCgcJEgAAAA==.',
Tr='Trisinz:BAABLgAECn8YAAILAAYJqhLtGwAcAQALAAYJqhLtGwAcAQAAAA==.Trixa:BAAALgADCgMJAwAAAA==.',
Tu='Tuerto:BAAALgAECgYJDAAAAA==.Turk:BAABLgAECn8pAAMXAAkJdhJ8EQDiAQAXAAkJdhJ8EQDiAQATAAEJCQ+/cwAxAAAAAA==.Turkish:BAABLgAECn8lAAIEAAkJGBkbEwAgAgAEAAkJGBkbEwAgAgAAAA==.Turtledisco:BAACLgAFFH8KAAIDAAQJ3CGJAgCHAQADAAQJ3CGJAgCHAQAuAAQKfyEAAgMACQnnHrgDABcDAAMACQnnHrgDABcDAAAA.',
Ty='Tychaa:BAAALgADCgYJCAAAAA==.Tylat:BAAALgADCgEJAgAAAA==.Tyranax:BAABLgAECn8rAAQlAAgJBxuZCAAMAgAlAAgJgBiZCAAMAgAcAAYJ1R9QHAD6AQASAAcJJxNnEACJAQAAAA==.Tyyregade:BAAALgADCgkJCgABLgAECgUJCQAIAAAAAA==.',
Uj='Ujimas:BAAALgADCgcJDQAAAA==.',
Ur='Urawizardtui:BAABLgAECn8yAAMFAAkJwxwZCAC4AgAFAAkJwxwZCAC4AgAKAAUJgwhlDgDdAAAAAA==.',
Us='Us:BAAALgAECggJCQAAAA==.',
Va='Vadose:BAABLgAECn8eAAIWAAcJgAppSQAUAQAWAAcJgAppSQAUAQABLgAECggJIQAUAC8VAA==.Vales:BAAALgAECgMJAwABLgAECggJHAAUAEAJAA==.Valsavis:BAAALgAECgUJDQAAAA==.Valytrois:BAAALgAECgYJDAAAAA==.Varinix:BAAALgADCgMJAwAAAA==.',
Ve='Veggiebaha:BAAALgADCgIJAgAAAA==.Veiksla:BAAALgAECgYJCwAAAA==.Velore:BAAALgADCgcJDAAAAA==.Vengerr:BAAALgAECgIJAgAAAA==.Verace:BAAALgAECgcJAQAAAA==.',
Vi='Vitur:BAABLgAECn8sAAIXAAkJoiCtCABQAgAXAAkJoiCtCABQAgAAAA==.',
Vo='Voidhunter:BAAALgAECgYJDgAAAA==.Voidweaver:BAAALgAECgIJBAAAAA==.Volaine:BAAALgAECgUJCwAAAA==.Volt:BAABLgAECn8iAAIbAAkJIBJSAwAXAgAbAAkJIBJSAwAXAgAAAA==.Volwryn:BAAALgAECgMJAwABLgAECgUJBQAIAAAAAA==.',
Vy='Vynarian:BAAALgAECgUJCwAAAA==.',
['Vâ']='Vâljean:BAAALgADCgMJAwAAAA==.',
['Vô']='Vôx:BAAALgAECgEJAQABLgAECgUJEAAIAAAAAA==.',
Wa='Warbeard:BAABLgAECn8dAAIPAAkJwgfGKQD4AAAPAAkJwgfGKQD4AAAAAA==.',
Wi='Wizwizx:BAAALgADCgUJBgAAAA==.',
Wr='Wreckd:BAAALgAECgkJBwAAAA==.',
Wy='Wyth:BAAALgAECgQJBQABLgAECgQJBgAIAAAAAA==.',
Xa='Xanthad:BAAALgADCgEJAQAAAA==.',
Xb='Xb:BAAALgADCgYJCAAAAA==.',
Xi='Xitãozinho:BAAALgAECgQJBQAAAA==.',
Xo='Xolair:BAAALgAECgUJCgAAAA==.',
Ya='Yaalia:BAAALgAECgUJCgAAAA==.Yaan:BAABLgAECn8YAAIGAAYJBAxSKQDgAAAGAAYJBAxSKQDgAAAAAA==.',
Yo='Yoba:BAAALgAECgMJAwAAAA==.Yoshira:BAAALgADCgQJBAAAAA==.',
['Yö']='Yör:BAAALgAECgEJAQAAAA==.',
Za='Zain:BAABLgAECn8rAAQmAAkJNRZoAwAjAgAmAAkJNRZoAwAjAgAPAAYJGA5YWQBIAQADAAIJIg2FIwBgAAAAAA==.Zandibar:BAAALgAECgUJCwAAAA==.Zaptoasted:BAAALgAECgEJAQAAAA==.Zaroff:BAAALgADCgcJBwAAAA==.',
Ze='Zedadiah:BAAALgADCgEJAQAAAA==.Zelah:BAAALgAECgQJBAAAAA==.Zellezugtail:BAAALgADCgYJCAABLgAECgYJCwAIAAAAAA==.Zenessa:BAAALgADCgYJBgAAAA==.',
Zi='Zinder:BAAALgAECgYJEQAAAA==.',
Zu='Zuggie:BAAALgAECgYJCwAAAA==.Zurtrinik:BAACLgAFFH8TAAIDAAUJsSFZAgCSAQADAAUJsSFZAgCSAQAuAAQKfyUAAgMACAmZJDoCAE0DAAMACAmZJDoCAE0DAAAA.',
Zz='Zzonked:BAABLgAECn8dAAMEAAkJZAdxiABwAQAEAAkJKAZxiABwAQAgAAIJ/gtBPwBSAAAAAA==.',
['Zê']='Zêp:BAAALgAECgEJAgAAAA==.',
['Zø']='Zøømies:BAABLgAECn8cAAIXAAcJfRjQGgCTAQAXAAcJfRjQGgCTAQAAAA==.',
['Äs']='Äshnärd:BAABLgAECn8nAAIjAAgJdCPkBACsAgAjAAgJdCPkBACsAgAAAA==.',
['Ða']='Ðar:BAAALgADCgEJAQAAAA==.',
['Ðo']='Ðoogle:BAAALgAECgYJCwAAAA==.',
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
