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

local lookup = {'Priest-Shadow','Paladin-Retribution','DeathKnight-Unholy','DemonHunter-Devourer','Monk-Brewmaster','Evoker-Preservation','Unknown-Unknown','DeathKnight-Blood','Warrior-Fury','Warrior-Protection','Mage-Frost','Hunter-Marksmanship','Hunter-BeastMastery','Druid-Balance','Druid-Restoration','Druid-Feral','Warrior-Arms','Priest-Holy','Evoker-Augmentation','Priest-Discipline','Shaman-Restoration','Warlock-Demonology','Monk-Mistweaver','Rogue-Assassination','Warlock-Affliction','Warlock-Destruction','Druid-Guardian','Hunter-Survival','DemonHunter-Vengeance','Evoker-Devastation','Shaman-Elemental','Monk-Windwalker','Rogue-Subtlety',}
local provider = {region='US',realm='Lightninghoof',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abukuma:BAAALgADCgkJCQAAAA==.',
Ad='Adraina:BAAALgADCgEJAQAAAA==.Adrewid:BAAALgADCgQJBAAAAA==.',
Ae='Aelarya:BAABLgAECn8PAAIBAAgJiQVKLACfAAABAAgJiQVKLACfAAAAAA==.Aenstalash:BAABLgAECn8YAAICAAcJySNKDQBZAgACAAcJySNKDQBZAgAAAA==.Aephium:BAAALgAECgYJCAAAAA==.Aesilakaersi:BAAALgAECgYJCgAAAA==.Aeson:BAABLgAECn8fAAIDAAgJtBXpIwCyAQADAAgJtBXpIwCyAQAAAA==.',
Af='Afflictia:BAAALgADCgYJEAAAAA==.',
Ai='Aironel:BAAALgADCgMJAwAAAA==.',
Al='Alaure:BAAALgADCgIJAgAAAA==.Alida:BAAALgAECgQJBAAAAA==.Alistur:BAAALgAECgYJDAAAAA==.',
Am='Amoona:BAAALgAECgYJEgABLgAECggJFgAEAFMhAA==.',
An='Anoriia:BAAALgADCgUJBQAAAA==.',
Ar='Arthraz:BAABLgAECn8fAAIFAAgJHR67BABmAgAFAAgJHR67BABmAgAAAA==.',
As='Astraa:BAAALgAECgIJAgAAAA==.Astrex:BAABLgAECn8UAAIGAAYJLQjfEADvAAAGAAYJLQjfEADvAAAAAA==.',
Au='Aureliá:BAAALgAECgYJEAAAAA==.',
['Aü']='Aütobot:BAAALgAECgYJEQAAAA==.',
Ba='Badgirl:BAAALgAFFAMJBAAAAA==.Balnar:BAAALgAECgUJCwABLgAECgYJDwAHAAAAAA==.Balraga:BAAALgAECgYJDwAAAA==.Bayded:BAAALgADCgEJAQAAAA==.',
Be='Bega:BAACLgAFFH8TAAMDAAUJGhtyFgBYAQADAAQJGhtyFgBYAQAIAAEJAAB0IAAAAAAuAAQKfy8AAwMACQndJD8HAGcDAAMACQndJD8HAGcDAAgABgkrFz0lABUBAAAA.Benton:BAAALgAECgQJBwAAAA==.',
Bi='Bigglimpie:BAAALgAECgYJDQAAAA==.',
Bl='Bloodlustplz:BAABLgAECn8aAAMJAAgJTBRFPAC0AQAJAAYJ4BlFPAC0AQAKAAUJXAojEwD5AAAAAA==.',
Bo='Bobster:BAABLgAECn8fAAILAAgJthFVMgCbAQALAAgJthFVMgCbAQAAAA==.Booyea:BAABLgAECn8gAAIIAAgJDxdVCACWAQAIAAgJDxdVCACWAQAAAA==.',
Br='Brewwnor:BAAALgAECgMJAwAAAA==.Brickdemkeys:BAABLgAECn8dAAILAAgJaRmyHgD0AQALAAgJaRmyHgD0AQAAAA==.Brisfloggnaw:BAAALgAECgQJBgAAAA==.',
Ca='Caladk:BAAALgADCgUJBQABLgAFFAYJDgAMAOUgAA==.Calamuelis:BAACLgAFFH8OAAMMAAYJ5SDFBwCeAQAMAAYJjCDFBwCeAQANAAEJXx9jNABcAAAuAAQKfxgAAgwACAmWJJ8NANYCAAwACAmWJJ8NANYCAAAA.Caliope:BAAALgAECgEJAQAAAA==.Capsasin:BAAALgADCgUJBQAAAA==.Carnage:BAAALgAECgkJBgAAAA==.Cazlek:BAAALgAECgQJCwAAAA==.',
Ce='Celery:BAAALgADCgQJBwABLgAECggJHwAFAB0eAA==.Celldweller:BAAALgAECgYJCgAAAA==.Cerdred:BAABLgAECn8XAAIOAAUJARC7SQAEAQAOAAUJARC7SQAEAQAAAA==.Cerelus:BAAALgAECgYJEgAAAA==.',
Ch='Chaac:BAAALgAECgUJBQAAAA==.Chmmr:BAAALgADCgMJAwAAAA==.Chowilawu:BAAALgADCgkJCQAAAA==.Chriswilsonn:BAAALgAECgQJCAAAAA==.Chuca:BAAALgAECgYJBgAAAA==.Chucalu:BAAALgAECggJEwAAAA==.',
Cl='Clax:BAAALgAECgIJBAAAAA==.',
Co='Cobeam:BAAALgAECgQJBAAAAA==.Cowpernicus:BAABLgAECn8WAAIPAAUJOySQEAAMAgAPAAUJOySQEAAMAgAAAA==.',
Cr='Crungleman:BAAALgAECgYJDQAAAA==.',
Ct='Cthuwu:BAAALgAECgQJBAABLgAECgUJBQAHAAAAAA==.',
Cu='Curoi:BAABLgAECn8WAAMQAAcJQQnMCgA0AQAQAAcJQQnMCgA0AQAPAAYJpQcueQDsAAAAAA==.',
['Cã']='Cãrloy:BAACLgAFFH8HAAIJAAMJCBjaDgAPAQAJAAMJCBjaDgAPAQAuAAQKfzoAAwkACQmSHZEDAJgCAAkACQmSHZEDAJgCABEAAglVGWMsAJEAAAAA.',
['Cê']='Cêlestial:BAABLgAECn8WAAIEAAcJUyHPDQAJAgAEAAcJUyHPDQAJAgAAAA==.',
Da='Daedalas:BAAALgAECgYJDQAAAA==.Damonk:BAAALgADCgYJBgABLgAECgcJHgASAPciAA==.Danevolent:BAABLgAECn8eAAMSAAcJ9yKBDQCAAgASAAcJ9yKBDQCAAgABAAIJuhGKOwBEAAAAAA==.Danzaster:BAAALgADCgQJBAAAAA==.Darkxsoul:BAAALgAECgYJDwAAAA==.Darthknull:BAABLgAECn8gAAICAAkJKxgATQD7AQACAAkJKxgATQD7AQAAAA==.',
De='Deadeyedicky:BAAALgAECgkJBwAAAA==.Deathmachine:BAAALgADCgUJBQAAAA==.Deathseer:BAAALgAECgcJDgAAAA==.Deathwood:BAAALgADCgUJBQAAAA==.Deatthdecay:BAAALgAECggJBAAAAA==.Deitrichx:BAABLgAECn8eAAIMAAgJ8xVEBADNAQAMAAgJ8xVEBADNAQAAAA==.Delley:BAAALgADCgEJAQAAAA==.Deminestrea:BAAALgAECgMJAwAAAA==.Devilscreed:BAAALgAECgEJAQAAAA==.',
Di='Dippindots:BAAALgAECgEJAwAAAA==.Disshammy:BAAALgAFFAIJAgABLgAFFAYJEwATAO8iAA==.Dittoz:BAAALgADCgUJBAAAAA==.',
Do='Donkform:BAAALgAECgUJBQAAAA==.Donniyii:BAAALgADCgcJBwABLgAECggJHQAUAFUfAA==.Doomrider:BAAALgADCgYJBgAAAA==.Dottzz:BAAALgAECgYJEgAAAA==.',
Dr='Draconith:BAABLgAECn8eAAIGAAkJPRFUBQAHAgAGAAkJPRFUBQAHAgAAAA==.Dramoo:BAAALgAECgMJAwAAAA==.Draqkmar:BAAALgAECgMJAwAAAA==.',
Du='Dunsparrow:BAABLgAECn8rAAIVAAkJlyCuAQAgAwAVAAkJlyCuAQAgAwAAAA==.Durzul:BAAALgADCggJCAAAAA==.',
Ei='Eightyone:BAAALgAECgEJAQAAAA==.Eindraken:BAABLgAECn8bAAIGAAcJEBMUDABIAQAGAAcJEBMUDABIAQAAAA==.Eisis:BAABLgAECn8hAAIQAAgJxg7LCQBKAQAQAAgJxg7LCQBKAQAAAA==.',
El='Elanalué:BAAALgAECgEJAQABLgAECgEJAQAHAAAAAA==.',
Er='Erixee:BAAALgAECgUJBgAAAA==.',
Es='Eshonäi:BAABLgAECn8UAAIWAAYJdA//QwAlAQAWAAYJdA//QwAlAQAAAA==.Espriesso:BAAALgAECgQJAwABLgAECggJGAAXAGgMAA==.',
Ev='Evodragker:BAABLgAECn8fAAMTAAgJ3BRYDQC0AQATAAgJ3BRYDQC0AQAGAAEJcwkqIAA8AAAAAA==.',
Fe='Feldron:BAAALgAECgYJDQAAAA==.Felkaos:BAAALgADCgEJAQAAAA==.Fellura:BAAALgADCggJCQAAAA==.Femaledawg:BAAALgADCgcJEAAAAA==.',
Fi='Fingor:BAAALgAECgYJBwAAAA==.',
Fl='Flamecube:BAAALgADCgcJCAAAAA==.Flashx:BAAALgAECgUJCAAAAA==.',
Fo='Foxxeyineawo:BAAALgADCgcJCAAAAA==.',
Fr='Frevmk:BAAALgAECgEJAgAAAA==.Frofrohunter:BAABLgAECn8qAAMNAAkJEB+aBwB+AgANAAkJEB+aBwB+AgAMAAUJAxK1TgAUAQAAAA==.Frofrolock:BAAALgAECgQJBAAAAA==.Froggie:BAAALgAECgYJEgAAAA==.',
Fu='Fuzywuuzy:BAABLgAECn8aAAIPAAgJ0yOsAgAgAwAPAAgJ0yOsAgAgAwAAAA==.',
Ga='Gazdorn:BAAALgAECgYJEgAAAA==.',
Ge='Genebelcher:BAAALgAECgEJAQAAAA==.',
Gh='Ghost:BAABLgAECn8VAAIYAAgJAhcBCADZAQAYAAgJAhcBCADZAQAAAA==.',
Gi='Gigof:BAABLgAECn8hAAMOAAgJWhHsDgCiAQAOAAgJWhHsDgCiAQAPAAUJrQhMigDAAAAAAA==.',
Gl='Glissa:BAABLgAECn8UAAQZAAcJdCWRAQDTAgAZAAcJEiWRAQDTAgAWAAMJhSJGogAUAQAaAAIJjxpWRACkAAAAAA==.',
Go='Gobah:BAAALgAECgYJDgAAAA==.',
Gt='Gt:BAAALgAECgMJBQAAAA==.',
Gu='Gulldan:BAAALgAECgYJDQAAAA==.',
Gw='Gwyndolin:BAAALgADCgUJBQAAAA==.',
Ha='Harrowhark:BAAALgAECgYJEAAAAA==.',
He='Hendricks:BAAALgAECgQJCgAAAA==.Hexinverter:BAAALgAECgQJBQAAAA==.',
Ho='Holeecow:BAAALgADCgIJAgABLgAECgkJKwAVAJcgAA==.Holycannoli:BAAALgAECgYJCAAAAA==.Horiffic:BAAALgAECgQJCAAAAA==.Horok:BAAALgAECgIJBAAAAA==.Hotwheels:BAAALgAECgMJAwAAAA==.',
Hu='Hubert:BAAALgAECgYJDwAAAA==.Hubertdale:BAAALgAECgMJAwAAAA==.Hulkblood:BAAALgAECgEJAQAAAA==.Hummingbrook:BAAALgAECgcJDAABLgAFFAUJEAAEAFMYAA==.',
Ic='Ichaerus:BAAALgAECgEJAQABLgAECgYJDQAHAAAAAA==.',
Ii='Iilli:BAABLgAECn8dAAMUAAgJVR+PAgDeAgAUAAgJVR+PAgDeAgABAAMJvg3KTgCXAAAAAA==.',
In='Inari:BAAALgAECgUJDAAAAA==.Inkkubus:BAABLgAFFH8GAAMaAAMJlg0rBwCVAAAWAAIJvxK7MQCvAAAaAAIJXwUrBwCVAAAAAA==.Instagatorz:BAAALgADCgUJBgAAAA==.',
Iq='Iq:BAAALgAECgEJAQAAAA==.',
Iw='Iwkms:BAACLgAFFH8KAAIQAAMJORnHAgAaAQAQAAMJORnHAgAaAQAuAAQKfyMAAhAACAlgIzQCADEDABAACAlgIzQCADEDAAAA.',
Ja='Jade:BAAALgAECgYJEgAAAA==.Jatheo:BAAALgADCgIJAgAAAA==.',
Je='Jenliz:BAAALgADCgEJAQABLgAECgYJEQAHAAAAAA==.Jeronor:BAAALgAECgEJAQAAAA==.',
Ji='Jimmick:BAAALgAECgYJEAAAAA==.Jisung:BAAALgAECgEJAQAAAA==.',
Jo='Jorad:BAAALgADCgEJAQAAAA==.',
Ju='Junebugg:BAAALgADCgEJAQAAAA==.',
Ka='Kaing:BAAALgAECgMJAwAAAA==.Kalena:BAABLgAECn8gAAILAAgJJA1uOgB/AQALAAgJJA1uOgB/AQAAAA==.Kaos:BAABLgAECn8eAAILAAgJ6REjMACjAQALAAgJ6REjMACjAQAAAA==.Kariatyda:BAABLgAECn8oAAINAAkJZhb8DAA2AgANAAkJZhb8DAA2AgAAAA==.Kasai:BAAALgADCgMJAwABLgAECgUJCQAHAAAAAA==.Kassandra:BAABLgAECn8gAAILAAgJ/hY6IQDmAQALAAgJ/hY6IQDmAQAAAA==.Kay:BAAALgAECgcJCQAAAA==.Kayden:BAABLgAECn8aAAIXAAYJgxivGABCAQAXAAYJgxivGABCAQAAAA==.Kayn:BAAALgAECgIJAgAAAA==.',
Ke='Keelistus:BAAALgAECgQJBAAAAA==.Kelzor:BAAALgAECgEJAQAAAA==.Keruu:BAAALgAECgcJBwAAAA==.',
Kh='Khaylorn:BAAALgAECgMJBgAAAA==.',
Ki='Kiloton:BAAALgAECgYJEwAAAA==.Kitzy:BAAALgAECgYJEQAAAA==.',
Kl='Klapso:BAAALgADCgYJDQAAAA==.Klippertdk:BAABLgAECn8aAAIDAAgJ4hS7IQC9AQADAAgJ4hS7IQC9AQAAAA==.Klugamonk:BAAALgADCgUJBQAAAA==.Klutz:BAAALgAECgYJEgAAAA==.',
Ko='Korgriku:BAAALgADCgMJAwAAAA==.',
Kr='Kreznor:BAAALgAECgIJAgAAAA==.',
Ku='Kurzo:BAABLgAECn8lAAMJAAgJGht5BgBLAgAJAAgJGht5BgBLAgAKAAUJqhJWGQC6AAAAAA==.',
Ky='Kylarian:BAAALgAECgYJEQAAAA==.Kyntara:BAAALgAECgYJBwAAAA==.Kyronian:BAAALgAECgUJCwAAAA==.',
['Kâ']='Kâsâi:BAAALgAECgUJCQAAAA==.',
La='Lakshmee:BAAALgAECgcJDgAAAA==.',
Le='Ledarm:BAAALgAECgcJEAAAAA==.Leigin:BAAALgADCgYJBgAAAA==.Lexxi:BAABLgAECn8hAAICAAgJnBLmJwCjAQACAAgJnBLmJwCjAQAAAA==.',
Li='Lightbehunt:BAAALgADCgIJAgAAAA==.Lightsglory:BAAALgADCgMJAwAAAA==.Livaless:BAAALgADCgQJBAABLgAECggJFQAWAL8fAA==.',
Lu='Lucialyn:BAAALgAECgcJDAAAAA==.',
Ly='Lyllith:BAABLgAECn8VAAIYAAYJhRFZBgBNAQAYAAYJhRFZBgBNAQAAAA==.Lysende:BAAALgADCgQJBAAAAA==.',
Ma='Madamenoodle:BAAALgADCgkJCQAAAA==.Magnass:BAAALgADCgYJBgABLgAECgcJHgASAPciAA==.Magnius:BAAALgADCgEJAQAAAA==.Mastablasta:BAAALgAECgIJBQAAAA==.Maursaline:BAABLgAECn8dAAIPAAgJMQiJLAAuAQAPAAgJMQiJLAAuAQAAAA==.Mawks:BAAALgAECgcJEgAAAA==.',
Mc='Mcstukes:BAAALgAECgQJCAAAAA==.',
Me='Medeas:BAAALgAECgQJCAAAAA==.Meragos:BAAALgAECgMJAwAAAA==.Meteor:BAAALgADCgQJBAAAAA==.',
Mi='Migzeviltwin:BAAALgADCgEJAQAAAA==.Mimicz:BAAALgADCgUJBQAAAA==.Mixxon:BAAALgAECgYJDQAAAA==.',
Mo='Moinion:BAAALgADCgQJCAAAAA==.Moldbreather:BAAALgAECgEJAQAAAA==.Moomooimacow:BAAALgAECgQJBAAAAA==.Moomoomonkey:BAAALgAECgYJEQAAAA==.Morhgana:BAAALgAECgMJAwAAAA==.',
Mx='Mxmlxxix:BAABLgAECn8jAAMSAAgJyQFyJADaAAASAAgJyQFyJADaAAABAAIJYAHRZQAtAAAAAA==.',
['Mö']='Mördecai:BAAALgADCgcJCgAAAA==.',
Na='Naija:BAAALgAECgEJAgAAAA==.Nati:BAAALgAECgUJBQAAAA==.',
Ne='Neptune:BAAALgAECgQJCAAAAA==.',
Ni='Nikorobin:BAAALgAECgQJBwABLgAFFAUJEAAEAFMYAA==.Nilius:BAAALgADCgcJBwABLgAECgYJDQAHAAAAAA==.',
No='Noodles:BAAALgADCgkJDAABLgAECgYJEgAHAAAAAA==.Norgalina:BAAALgADCgUJBQAAAA==.',
Ny='Nymara:BAAALgAECgYJEAAAAA==.',
['Ní']='Níce:BAAALgAECgEJAgAAAA==.',
['Nü']='Nügs:BAAALgAECgcJEQAAAA==.',
Ol='Olei:BAAALgADCgUJBQAAAA==.',
Or='Orlick:BAAALgAECgEJAQAAAA==.Orrok:BAAALgADCgYJBwAAAA==.',
Pa='Painnkiller:BAABLgAECn8iAAINAAgJgB2zCgBTAgANAAgJgB2zCgBTAgAAAA==.Papyto:BAAALgADCgYJBwAAAA==.Parsley:BAAALgAECgMJBgABLgAECggJHwAFAB0eAA==.Paxis:BAAALgAECggJCwAAAA==.',
Pe='Perriwinkle:BAABLgAECn8dAAQQAAgJWhYpCwAQAgAQAAgJ3hUpCwAQAgAbAAYJaQ6vEACvAAAPAAIJzAt+zAAyAAAAAA==.Perseus:BAAALgADCgMJAwAAAA==.',
Ph='Phission:BAAALgADCgEJAQAAAA==.Phobya:BAAALgAECgcJEgAAAA==.Phylloxeras:BAABLgAECn8eAAIDAAgJmyJyBgC4AgADAAgJmyJyBgC4AgAAAA==.',
Pl='Pleasure:BAAALgADCgMJAwAAAA==.Pleggashroom:BAAALgADCgEJAQAAAA==.',
Po='Powders:BAABLgAECn8kAAILAAgJwxe8HQD6AQALAAgJwxe8HQD6AQAAAA==.',
Pr='Proshot:BAABLgAECn8YAAIcAAYJ0x3MCQDFAQAcAAYJ0x3MCQDFAQAAAA==.',
Pu='Puddles:BAAALgADCggJDQAAAA==.',
Pz='Pzalmo:BAAALgAECgMJAwAAAA==.',
Ra='Raccoon:BAABLgAECn8gAAIWAAgJnA1KJgCWAQAWAAgJnA1KJgCWAQAAAA==.Ravenhawk:BAAALgAECgQJBAAAAA==.Razza:BAAALgADCgYJCAAAAA==.',
Re='Remember:BAAALgADCgEJAQAAAA==.Renivatio:BAAALgAECgYJCQAAAA==.',
Rh='Rhyntix:BAAALgADCgEJAQAAAA==.',
Ro='Roronoazoro:BAACLgAFFH8QAAIEAAUJUxhnFgAdAQAEAAUJUxhnFgAdAQAuAAQKfyAAAwQACQkKH2sjAH0CAAQACQkKH2sjAH0CAB0AAglxEwYmAFQAAAAA.',
Ry='Ryrin:BAABLgAECn8aAAIJAAcJUBOJGABsAQAJAAcJUBOJGABsAQAAAA==.',
Sa='Samidrac:BAAALgAECgQJBwAAAA==.Sammidormu:BAABLgAECn8WAAQeAAYJZg9XBgA2AQAeAAYJZg9XBgA2AQATAAYJNglWNgAgAQAGAAEJ2QECTgAjAAAAAA==.Sanderwoof:BAAALgAECggJCAAAAA==.Sarzul:BAABLgAECn8UAAMaAAYJiA8YNADnAAAWAAYJ2gyzmwAiAQAaAAQJqRAYNADnAAAAAA==.Satoshie:BAAALgADCgMJAwAAAA==.',
Sc='Scerevisiae:BAAALgAECgQJDAAAAA==.',
Se='Sedelis:BAAALgAECgYJDQAAAA==.Sefirbrena:BAAALgADCgkJAwAAAA==.Selaya:BAAALgADCgUJBQAAAA==.Semnai:BAAALgAECgYJEAAAAA==.Serafín:BAABLgAECn8gAAIFAAgJOwkWGgAuAQAFAAgJOwkWGgAuAQAAAA==.Sevilicious:BAAALgADCgQJAwAAAA==.',
Sh='Shaay:BAAALgAECgUJCAAAAA==.Shadowlock:BAAALgAECgEJAgAAAA==.Shamwig:BAAALgADCgUJBQAAAA==.Shieldwall:BAABLgAECn8iAAIKAAgJsghiDwAqAQAKAAgJsghiDwAqAQAAAA==.',
Si='Silanah:BAAALgADCgEJAQAAAA==.Silverhâwk:BAAALgADCgEJAQAAAA==.Sinastys:BAABLgAECn8XAAICAAcJoRDwNQBsAQACAAcJoRDwNQBsAQAAAA==.',
So='Solone:BAAALgADCgkJEAAAAA==.Sopidia:BAABLgAECn8XAAMVAAYJKBaJGwCHAQAVAAYJKBaJGwCHAQAfAAQJUwU9OgCDAAAAAA==.Sorvato:BAAALgAECgYJEAAAAA==.',
Sp='Spoonzz:BAABLgAECn8gAAIgAAcJCyYpBwALAwAgAAcJCyYpBwALAwAAAA==.',
St='Stamavan:BAABLgAECn8fAAIbAAgJMyMDAQClAgAbAAgJMyMDAQClAgAAAA==.Starflayer:BAABLgAECn8kAAMEAAgJ8Ro0EADvAQAEAAgJ3hk0EADvAQAdAAIJYxr3IAB8AAAAAA==.Sterjariger:BAAALgAECgYJBgAAAA==.',
Su='Sunari:BAAALgAECgEJAQAAAA==.Supermelon:BAAALgAECgYJDgAAAA==.',
Sw='Swenior:BAAALgADCgEJAQAAAA==.',
Sy='Sylvanaria:BAABLgAECn8gAAIVAAgJWSamAABvAwAVAAgJWSamAABvAwAAAA==.Sylvanaris:BAAALgAECgUJBQAAAA==.Systyx:BAABLgAECn8bAAIWAAcJWB8OFQD8AQAWAAcJWB8OFQD8AQAAAA==.',
Ta='Takura:BAAALgAECgcJBwABLgAECgkJCwAHAAAAAA==.Talenel:BAAALgAECgMJAwAAAA==.Talyzien:BAAALgADCgQJBQAAAA==.',
Te='Tealan:BAABLgAECn8lAAMTAAgJjhOODAC/AQATAAgJjhOODAC/AQAGAAcJSBLhHACeAQAAAA==.Tealyn:BAAALgADCgYJCgAAAA==.Teluz:BAAALgAECgQJCgAAAA==.Tendra:BAAALgAECgYJBQAAAA==.Teronreborn:BAABLgAECn8gAAIDAAgJpSSFFAAAAwADAAgJpSSFFAAAAwAAAA==.',
Th='Thaneer:BAAALgAECgYJBwAAAA==.Thanos:BAABLgAECn8aAAICAAYJ7Q6EpAA3AQACAAYJ7Q6EpAA3AQAAAA==.Thebadmage:BAAALgAECgcJBAAAAA==.Throstmok:BAABLgAECn8lAAIIAAgJzBuABgDAAQAIAAgJzBuABgDAAQAAAA==.Thränton:BAAALgAECgEJAQABLgAECgcJEgAHAAAAAA==.Thumbalina:BAAALgAECgYJEQAAAA==.',
Tp='Tpaste:BAAALgADCgcJBwAAAA==.',
Tr='Trout:BAAALgADCgYJDAABLgAECgYJCgAHAAAAAA==.Trovikk:BAAALgADCgUJBQAAAA==.',
Tu='Turg:BAAALgAECgMJAwABLgAECgQJBwAHAAAAAA==.Turgress:BAAALgAECgQJBwAAAA==.',
['Tà']='Tàmber:BAAALgADCgUJBQAAAA==.',
Ul='Ulfast:BAABLgAECn8eAAIfAAgJ/x0LBgBOAgAfAAgJ/x0LBgBOAgAAAA==.',
Va='Vannhellsing:BAABLgAECn8YAAIDAAcJiwhnRwAoAQADAAcJiwhnRwAoAQAAAA==.Vanyel:BAABLgAECn8pAAILAAgJWA5jNQCQAQALAAgJWA5jNQCQAQAAAA==.Vaudorka:BAABLgAECn8ZAAIeAAgJ1R4wAQBgAgAeAAgJ1R4wAQBgAgAAAA==.',
Ve='Vecna:BAAALgADCgMJAwABLgAECgYJEAAHAAAAAA==.Veliuz:BAAALgADCgQJBAAAAA==.Velrynth:BAABLgAECn8aAAMUAAgJIg6TGgAQAQAUAAUJ9gyTGgAQAQASAAcJ0QjvHgAKAQAAAA==.Vemal:BAABLgAECn8XAAINAAgJFA/MUwBtAQANAAgJFA/MUwBtAQAAAA==.',
Vo='Vociferoy:BAABLgAECn8mAAINAAgJfh/HBQCbAgANAAgJfh/HBQCbAgAAAA==.Voidsteffan:BAAALgAECgYJEwAAAA==.',
Vr='Vryadox:BAAALgAECgcJDQAAAA==.',
Vv='Vv:BAACLgAFFH8aAAIEAAcJ7iQgAACWAgAEAAcJ7iQgAACWAgAuAAQKfywAAgQACQkbJucAANoDAAQACQkbJucAANoDAAAA.',
Vz='Vz:BAAALgADCgUJBQAAAA==.',
Wh='Whoppin:BAAALgAECgIJAgAAAA==.',
Wi='Wiglimparms:BAAALgAECgIJAgAAAA==.',
Wr='Wry:BAAALgAECgIJAgAAAA==.',
Wy='Wysselbow:BAAALgADCggJDQAAAA==.',
Xa='Xalzi:BAAALgADCggJCQABLgAECgYJEgAHAAAAAA==.',
Xi='Xingwong:BAABLgAECn8fAAIhAAYJDSWFBgAOAgAhAAYJDSWFBgAOAgAAAA==.',
Za='Zannytoes:BAABLgAECn8eAAIXAAgJsgsgGQA9AQAXAAgJsgsgGQA9AQAAAA==.',
Ze='Zead:BAAALgAECgEJAgAAAA==.Zerana:BAAALgAECgUJBQAAAA==.',
Zi='Zie:BAABLgAECn8oAAIBAAgJghHbDAC0AQABAAgJghHbDAC0AQAAAA==.Zikren:BAAALgAECggJCAAAAA==.',
Zs='Zsinj:BAAALgADCgEJAQAAAA==.',
['Ðo']='Ðonkle:BAAALgAECgcJDQAAAA==.',
['Ðr']='Ðrewid:BAAALgADCgEJAQAAAA==.',
['Ñi']='Ñice:BAAALgAFFAMJAwAAAA==.',
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
