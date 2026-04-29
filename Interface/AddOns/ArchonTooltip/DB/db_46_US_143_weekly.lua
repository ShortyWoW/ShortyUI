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

local lookup = {'DeathKnight-Unholy','Unknown-Unknown','Monk-Brewmaster','DeathKnight-Blood','Warrior-Fury','Warrior-Protection','Mage-Frost','Hunter-Marksmanship','Hunter-BeastMastery','Druid-Balance','Warrior-Arms','Priest-Holy','Paladin-Retribution','Evoker-Augmentation','Priest-Discipline','Evoker-Preservation','Shaman-Restoration','Druid-Feral','Rogue-Assassination','Druid-Restoration','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','DemonHunter-Devourer','Priest-Shadow','Monk-Mistweaver','Druid-Guardian','Evoker-Devastation','DemonHunter-Vengeance','Monk-Windwalker','Shaman-Elemental','Rogue-Subtlety',}
local provider = {region='US',realm='Lightninghoof',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abukuma:BAAALgADCgkJCQAAAA==.',
Ad='Adraina:BAAALgADCgEJAQAAAA==.Adrewid:BAAALgADCgQJBAAAAA==.',
Ae='Aelarya:BAAALgAECgcJEQAAAA==.Aenstalash:BAAALgAECggJEQAAAA==.Aephium:BAAALgAECgUJBwAAAA==.Aesilakaersi:BAAALgAECgYJCgAAAA==.Aeson:BAABLgAECn8bAAIBAAcJPRZqEQCJAQABAAcJPRZqEQCJAQAAAA==.',
Af='Afflictia:BAAALgADCgYJDAAAAA==.',
Ai='Aironel:BAAALgADCgMJAwAAAA==.',
Al='Alaure:BAAALgADCgIJAgAAAA==.Alida:BAAALgAECgQJBAAAAA==.Alistur:BAAALgAECgQJBwAAAA==.',
Am='Amoona:BAAALgAECgYJEgABLgAECgcJDwACAAAAAA==.',
An='Anoriia:BAAALgADCgUJBQAAAA==.',
Ar='Arthraz:BAABLgAECn8bAAIDAAcJfB5TAwAEAgADAAcJfB5TAwAEAgAAAA==.',
As='Astraa:BAAALgAECgIJAgAAAA==.Astrex:BAAALgAECgYJDQAAAA==.',
Au='Aureliá:BAAALgAECgQJCgAAAA==.',
['Aü']='Aütobot:BAAALgAECgUJBgAAAA==.',
Ba='Badgirl:BAAALgAFFAEJAQAAAA==.Balnar:BAAALgAECgUJBwABLgAECgYJCQACAAAAAA==.Balraga:BAAALgAECgYJDgAAAA==.Bayded:BAAALgADCgEJAQAAAA==.',
Be='Bega:BAACLgAFFH8NAAIBAAQJ3xRqBgBYAQABAAQJ3xRqBgBYAQAuAAQKfysAAwEACQl/Ij8HAGcDAAEACQl/Ij8HAGcDAAQABgkrFzolABUBAAAA.Benton:BAAALgAECgMJAwAAAA==.',
Bi='Bigglimpie:BAAALgAECgYJDQAAAA==.',
Bl='Bloodlustplz:BAABLgAECn8XAAMFAAgJsRM/PAC0AQAFAAYJ4Bk/PAC0AQAGAAQJFgauDACvAAAAAA==.',
Bo='Bobster:BAABLgAECn8bAAIHAAcJ9BCVHABoAQAHAAcJ9BCVHABoAQAAAA==.Booyea:BAABLgAECn8YAAIEAAcJExVwBQBhAQAEAAcJExVwBQBhAQAAAA==.',
Br='Brewwnor:BAAALgAECgMJAwAAAA==.Brickdemkeys:BAABLgAECn8ZAAIHAAYJCRz5GgByAQAHAAYJCRz5GgByAQAAAA==.Brisfloggnaw:BAAALgAECgIJAgAAAA==.',
Ca='Caladk:BAAALgADCgUJBQABLgAFFAUJDAAIAN0fAA==.Calamuelis:BAACLgAFFH8MAAMIAAUJ3R/DBwCeAQAIAAUJbx/DBwCeAQAJAAEJXx+REgBhAAAuAAQKfxgAAggACAmWJJ4NANYCAAgACAmWJJ4NANYCAAAA.Capsasin:BAAALgADCgUJBQAAAA==.Carnage:BAAALgAECgkJBgAAAA==.Cazlek:BAAALgAECgQJCwAAAA==.',
Ce='Celery:BAAALgADCgQJBwABLgAECgcJGwADAHweAA==.Celldweller:BAAALgAECgYJCgAAAA==.Cerdred:BAABLgAECn8XAAIKAAUJARC4SQAEAQAKAAUJARC4SQAEAQAAAA==.Cerelus:BAAALgAECgYJEQAAAA==.',
Ch='Chaac:BAAALgAECgMJAwABLgAECgQJBAACAAAAAA==.Chmmr:BAAALgADCgMJAwAAAA==.Chowilawu:BAAALgADCgkJCQAAAA==.Chriswilsonn:BAAALgAECgQJCAAAAA==.Chuca:BAAALgAECgYJBgAAAA==.Chucalu:BAAALgAECggJEgAAAA==.',
Cl='Clax:BAAALgAECgIJAwAAAA==.',
Co='Cobeam:BAAALgADCgcJBQAAAA==.Cowpernicus:BAAALgAECgUJEQAAAA==.',
Cr='Crungleman:BAAALgAECgYJDQAAAA==.',
Ct='Cthuwu:BAAALgAECgQJBAAAAA==.',
Cu='Curoi:BAAALgAECgYJDwAAAA==.',
['Cã']='Cãrloy:BAABLgAECn80AAMFAAkJRx0gAQCKAgAFAAkJRx0gAQCKAgALAAIJVRlhLACRAAAAAA==.',
['Cê']='Cêlestial:BAAALgAECgcJDwAAAA==.',
Da='Daedalas:BAAALgAECgQJBwAAAA==.Damonk:BAAALgADCgYJBgABLgAECgcJFwAMAL0eAA==.Danevolent:BAABLgAECn8XAAIMAAcJvR5/DQCAAgAMAAcJvR5/DQCAAgAAAA==.Danzaster:BAAALgADCgQJBAAAAA==.Darkxsoul:BAAALgAECgYJCQAAAA==.Darthknull:BAABLgAECn8dAAINAAgJ6xQITQD7AQANAAgJ6xQITQD7AQAAAA==.',
De='Deadeyedicky:BAAALgAECgkJBwAAAA==.Deathmachine:BAAALgADCgUJBQAAAA==.Deathseer:BAAALgAECgcJDgAAAA==.Deathwood:BAAALgADCgUJBQAAAA==.Deatthdecay:BAAALgAECggJBAAAAA==.Deitrichx:BAABLgAECn8aAAIIAAcJSxjUAwBpAQAIAAcJSxjUAwBpAQAAAA==.Delley:BAAALgADCgEJAQAAAA==.Deminestrea:BAAALgAECgMJAwAAAA==.Devilscreed:BAAALgAECgEJAQAAAA==.',
Di='Dippindots:BAAALgAECgEJAwAAAA==.Disshammy:BAAALgAFFAIJAgABLgAFFAUJDwAOAAQiAA==.Dittoz:BAAALgADCgUJBAAAAA==.',
Do='Donkform:BAAALgADCgkJDwAAAA==.Donniyii:BAAALgADCgcJBwABLgAECggJFQAPAEIfAA==.Doomrider:BAAALgADCgYJBgAAAA==.Dottzz:BAAALgAECgYJEQAAAA==.',
Dr='Draconith:BAABLgAECn8VAAIQAAgJuRIvBQBeAQAQAAgJuRIvBQBeAQAAAA==.Dramoo:BAAALgAECgMJAwAAAA==.Draqkmar:BAAALgAECgMJAwAAAA==.',
Du='Dunsparrow:BAABLgAECn8iAAIRAAkJbR3GBwD4AgARAAkJbR3GBwD4AgAAAA==.',
Ei='Eightyone:BAAALgADCgcJBwAAAA==.Eindraken:BAABLgAECn8YAAIQAAcJEBMHBQBjAQAQAAcJEBMHBQBjAQAAAA==.Eisis:BAABLgAECn8ZAAISAAcJvBAJFABxAQASAAcJvBAJFABxAQAAAA==.',
Er='Erixee:BAAALgAECgUJBgAAAA==.',
Es='Eshonäi:BAAALgAECgUJDgAAAA==.Espriesso:BAAALgAECgQJAwABLgAECgYJEgACAAAAAA==.',
Ev='Evodragker:BAABLgAECn8bAAMOAAcJeBRYIAC9AQAOAAcJeBRYIAC9AQAQAAEJcwm9DwA9AAAAAA==.',
Fe='Feldron:BAAALgAECgQJBwAAAA==.Felkaos:BAAALgADCgEJAQAAAA==.Fellura:BAAALgADCggJCQAAAA==.Femaledawg:BAAALgADCgcJEAAAAA==.',
Fi='Fingor:BAAALgAECgYJBwAAAA==.',
Fl='Flamecube:BAAALgADCgcJCAAAAA==.Flashx:BAAALgAECgUJBQAAAA==.',
Fo='Foxxeyineawo:BAAALgADCgcJCAAAAA==.',
Fr='Frevmk:BAAALgAECgEJAQAAAA==.Frofrohunter:BAABLgAECn8hAAMJAAgJ3x6nEgCiAgAJAAgJ3x6nEgCiAgAIAAUJAxK7TgAUAQAAAA==.Frofrolock:BAAALgAECgQJBAAAAA==.Froggie:BAAALgAECgYJDAAAAA==.',
Fu='Fuzywuuzy:BAAALgAFFAEJAQAAAA==.',
Ga='Gazdorn:BAAALgAECgUJBwAAAA==.',
Ge='Genebelcher:BAAALgAECgEJAQAAAA==.',
Gh='Ghost:BAABLgAECn8VAAITAAgJAhcECADZAQATAAgJAhcECADZAQAAAA==.',
Gi='Gigof:BAABLgAECn8bAAMKAAgJMhHQBQCsAQAKAAgJMhHQBQCsAQAUAAUJrQhMigDAAAAAAA==.',
Gl='Glissa:BAABLgAECn8UAAQVAAcJdCWRAQDTAgAVAAcJEiWRAQDTAgAWAAMJhSIzogAUAQAXAAIJjxpURACkAAAAAA==.',
Go='Gobah:BAAALgAECgYJCQAAAA==.',
Gt='Gt:BAAALgAECgMJBQAAAA==.',
Gu='Gulldan:BAAALgAECgYJBwAAAA==.',
Gw='Gwyndolin:BAAALgADCgUJBQAAAA==.',
Ha='Harrowhark:BAAALgAECgQJCgAAAA==.',
He='Hendricks:BAAALgAECgQJCgAAAA==.Hexinverter:BAAALgAECgMJBAAAAA==.',
Ho='Holeecow:BAAALgADCgIJAgABLgAECgkJIgARAG0dAA==.Holycannoli:BAAALgAECgYJBgAAAA==.Horiffic:BAAALgAECgQJCAAAAA==.Horok:BAAALgAECgIJBAAAAA==.Hotwheels:BAAALgADCgYJBgAAAA==.',
Hu='Hubert:BAAALgAECgUJCQAAAA==.Hubertdale:BAAALgAECgMJAwAAAA==.Hulkblood:BAAALgAECgEJAQAAAA==.Hummingbrook:BAAALgAECgcJDAABLgAFFAUJDgAYAIUXAA==.',
Ic='Ichaerus:BAAALgAECgEJAQABLgAECgQJBwACAAAAAA==.',
Ii='Iilli:BAABLgAECn8VAAMPAAgJQh/LAADgAgAPAAgJQh/LAADgAgAZAAMJvg3HTgCXAAAAAA==.',
In='Inari:BAAALgAECgQJBwAAAA==.Inkkubus:BAAALgAFFAMJAwAAAA==.Instagatorz:BAAALgADCgUJBgAAAA==.',
Iq='Iq:BAAALgAECgEJAQAAAA==.',
Iw='Iwkms:BAACLgAFFH8GAAISAAMJbRV1AgAXAQASAAMJbRV1AgAXAQAuAAQKfyEAAhIACAlgIzUCADIDABIACAlgIzUCADIDAAAA.',
Ja='Jade:BAAALgAECgYJEgAAAA==.Jatheo:BAAALgADCgIJAgAAAA==.',
Je='Jeronor:BAAALgAECgEJAQAAAA==.',
Ji='Jimmick:BAAALgAECgQJCgAAAA==.Jisung:BAAALgAECgEJAQAAAA==.',
Jo='Jorad:BAAALgADCgEJAQAAAA==.',
Ju='Junebugg:BAAALgADCgEJAQAAAA==.',
Ka='Kaing:BAAALgAECgMJAwAAAA==.Kalena:BAABLgAECn8YAAIHAAcJbAq8JAA9AQAHAAcJbAq8JAA9AQAAAA==.Kaos:BAABLgAECn8aAAIHAAcJmRM4GgB3AQAHAAcJmRM4GgB3AQAAAA==.Kariatyda:BAABLgAECn8fAAIJAAgJDhkLGwBlAgAJAAgJDhkLGwBlAgAAAA==.Kasai:BAAALgADCgMJAwABLgAECgMJBAACAAAAAA==.Kassandra:BAABLgAECn8YAAIHAAcJ6hLeFgCNAQAHAAcJ6hLeFgCNAQAAAA==.Kay:BAAALgAECgcJCQAAAA==.Kayden:BAABLgAECn8UAAIaAAYJIBiFJACRAQAaAAYJIBiFJACRAQAAAA==.Kayn:BAAALgAECgIJAgAAAA==.',
Ke='Keelistus:BAAALgAECgQJBAAAAA==.Kelzor:BAAALgAECgEJAQAAAA==.Keruu:BAAALgAECgcJBwAAAA==.',
Kh='Khaylorn:BAAALgAECgMJBgAAAA==.',
Ki='Kiloton:BAAALgAECgYJEwAAAA==.Kitzy:BAAALgAECgUJBgAAAA==.',
Kl='Klapso:BAAALgADCgYJDQAAAA==.Klippertdk:BAAALgAECgcJEgAAAA==.Klugamonk:BAAALgADCgUJBQAAAA==.Klutz:BAAALgAECgUJBwAAAA==.',
Ko='Korgriku:BAAALgADCgMJAwAAAA==.',
Kr='Kreznor:BAAALgADCgQJBAAAAA==.',
Ku='Kurzo:BAABLgAECn8eAAMFAAgJ3BoZAgBMAgAFAAgJ3BoZAgBMAgAGAAQJRgvnLADaAAAAAA==.',
Ky='Kylarian:BAAALgAECgQJBgAAAA==.Kyntara:BAAALgAECgEJAQAAAA==.Kyronian:BAAALgAECgUJBgAAAA==.',
['Kâ']='Kâsâi:BAAALgAECgMJBAAAAA==.',
La='Lakshmee:BAAALgAECgcJDgAAAA==.',
Le='Ledarm:BAAALgAECgcJEAAAAA==.Leigin:BAAALgADCgYJBgAAAA==.Lexxi:BAABLgAECn8ZAAINAAcJjBTQFgBpAQANAAcJjBTQFgBpAQAAAA==.',
Li='Lightbehunt:BAAALgADCgIJAgAAAA==.Lightsglory:BAAALgADCgMJAwAAAA==.',
Lu='Lucialyn:BAAALgAECgcJDAAAAA==.',
Ly='Lyllith:BAAALgAECgYJDwAAAA==.Lysende:BAAALgADCgQJBAAAAA==.',
Ma='Madamenoodle:BAAALgADCgkJCQAAAA==.Magnass:BAAALgADCgYJBgABLgAECgcJFwAMAL0eAA==.Magnius:BAAALgADCgEJAQAAAA==.Mastablasta:BAAALgAECgIJBAAAAA==.Maursaline:BAABLgAECn8ZAAIUAAcJuQdpGQDvAAAUAAcJuQdpGQDvAAAAAA==.Mawks:BAAALgAECgcJDAAAAA==.',
Mc='Mcstukes:BAAALgAECgQJCAAAAA==.',
Me='Medeas:BAAALgAECgQJCAAAAA==.Meragos:BAAALgAECgMJAwAAAA==.Meteor:BAAALgADCgQJBAAAAA==.',
Mi='Migzeviltwin:BAAALgADCgEJAQAAAA==.Mimicz:BAAALgADCgUJBQAAAA==.Mixxon:BAAALgAECgYJDAAAAA==.',
Mo='Moinion:BAAALgADCgQJCAAAAA==.Moldbreather:BAAALgAECgEJAQAAAA==.Moomooimacow:BAAALgAECgQJBAAAAA==.Moomoomonkey:BAAALgAECgYJEQAAAA==.Morhgana:BAAALgAECgMJAwAAAA==.',
Mx='Mxmlxxix:BAABLgAECn8dAAMMAAgJJgEEFACuAAAMAAgJJgEEFACuAAAZAAIJYAHGZQAtAAAAAA==.',
['Mö']='Mördecai:BAAALgADCgcJBwAAAA==.',
Na='Naija:BAAALgADCgQJBQAAAA==.Nati:BAAALgAECgUJBQAAAA==.',
Ne='Neptune:BAAALgAECgQJCAAAAA==.',
Ni='Nicholijax:BAABLgAECn8WAAIUAAkJlwAuxgA9AAAUAAkJlwAuxgA9AAAAAA==.Nilius:BAAALgADCgcJBwABLgAECgQJBwACAAAAAA==.',
No='Noodles:BAAALgADCgkJDAABLgAECgUJDQACAAAAAA==.Norgalina:BAAALgADCgUJBQAAAA==.',
Ny='Nymara:BAAALgAECgQJCgAAAA==.',
['Ní']='Níce:BAAALgAECgEJAgAAAA==.',
['Nü']='Nügs:BAAALgAECgYJDAAAAA==.',
Ol='Olei:BAAALgADCgUJBQAAAA==.',
Or='Orlick:BAAALgAECgEJAQAAAA==.Orrok:BAAALgADCgYJBwAAAA==.',
Pa='Painnkiller:BAABLgAECn8aAAIJAAcJUR1LBwD1AQAJAAcJUR1LBwD1AQAAAA==.Papyto:BAAALgADCgYJBwAAAA==.Parsley:BAAALgAECgMJAwABLgAECgcJGwADAHweAA==.Paxis:BAAALgAECgcJBwAAAA==.',
Pe='Perriwinkle:BAABLgAECn8XAAQSAAgJWhYpCwAQAgASAAgJ3hUpCwAQAgAbAAQJIw8BHwCoAAAUAAIJzAt+zAAyAAAAAA==.Perseus:BAAALgADCgMJAwAAAA==.',
Ph='Phission:BAAALgADCgEJAQAAAA==.Phobya:BAAALgAECgUJDAAAAA==.Phylloxeras:BAABLgAECn8WAAIBAAcJ6h7YCQDhAQABAAcJ6h7YCQDhAQAAAA==.',
Pl='Pleasure:BAAALgADCgMJAwAAAA==.Pleggashroom:BAAALgADCgEJAQAAAA==.',
Po='Powders:BAABLgAECn8aAAIHAAgJRRandgDlAQAHAAgJRRandgDlAQAAAA==.',
Pr='Proshot:BAAALgAECgYJCQAAAA==.',
Pu='Puddles:BAAALgADCggJCgAAAA==.',
Pz='Pzalmo:BAAALgAECgMJAwABLgAECgYJFgAcALMXAA==.',
Ra='Raccoon:BAABLgAECn8YAAIWAAcJlAx7FgBcAQAWAAcJlAx7FgBcAQAAAA==.Ravenhawk:BAAALgADCgcJGAAAAA==.Razza:BAAALgADCgYJCAAAAA==.',
Re='Remember:BAAALgADCgEJAQAAAA==.Renivatio:BAAALgAECgMJAwAAAA==.',
Rh='Rhyntix:BAAALgADCgEJAQAAAA==.',
Ro='Roronoazoro:BAACLgAFFH8OAAIYAAUJhReMBwA3AQAYAAUJhReMBwA3AQAuAAQKfyEAAxgACQkKH2MjAH0CABgACQkKH2MjAH0CAB0AAglxEwQmAFQAAAAA.',
Ry='Ryrin:BAABLgAECn8aAAIFAAcJUBMTCwBvAQAFAAcJUBMTCwBvAQAAAA==.',
Sa='Samidrac:BAAALgAECgMJAwAAAA==.Sammidormu:BAAALgAECgYJEAAAAA==.Sarzul:BAABLgAECn8UAAMXAAYJiA8XNADnAAAWAAYJ2gyimwAiAQAXAAQJqRAXNADnAAAAAA==.',
Sc='Scerevisiae:BAAALgAECgQJCAAAAA==.',
Se='Sedelis:BAAALgAECgUJBwAAAA==.Sefirbrena:BAAALgADCgkJAwAAAA==.Selaya:BAAALgADCgUJBQAAAA==.Semnai:BAAALgAECgYJCgAAAA==.Serafín:BAABLgAECn8YAAIDAAcJOQr9DgACAQADAAcJOQr9DgACAQAAAA==.Sevilicious:BAAALgADCgQJAwAAAA==.',
Sh='Shaay:BAAALgAECgQJBAAAAA==.Shadowlock:BAAALgAECgEJAgAAAA==.Shieldwall:BAABLgAECn8UAAIGAAgJbQe9HwBEAQAGAAgJbQe9HwBEAQAAAA==.',
Si='Silverhâwk:BAAALgADCgEJAQAAAA==.Sinastys:BAAALgAECgYJEAAAAA==.',
So='Solone:BAAALgADCgkJEAAAAA==.Sopidia:BAAALgAECgYJEAAAAA==.Sorvato:BAAALgAECgYJCgAAAA==.',
Sp='Spoonzz:BAABLgAECn8aAAIeAAcJCyYpBwALAwAeAAcJCyYpBwALAwAAAA==.',
St='Stamavan:BAABLgAECn8bAAIbAAcJMiW8AABoAgAbAAcJMiW8AABoAgAAAA==.Starflayer:BAABLgAECn8gAAMYAAgJeBnBDACtAQAYAAgJZRjBDACtAQAdAAIJYxr6IAB8AAAAAA==.Sterjariger:BAAALgAECgYJBgABLgAECggJEQACAAAAAA==.',
Su='Sunari:BAAALgAECgEJAQAAAA==.Supermelon:BAAALgAECgQJCAAAAA==.',
Sw='Swenior:BAAALgADCgEJAQAAAA==.',
Sy='Sylvanaria:BAABLgAECn8YAAIRAAcJaiUdAQDFAgARAAcJaiUdAQDFAgAAAA==.Sylvanaris:BAAALgADCgEJAQAAAA==.Systyx:BAABLgAECn8VAAIWAAcJpB7pBwDzAQAWAAcJpB7pBwDzAQAAAA==.',
Ta='Takura:BAAALgAECgcJBwABLgAECgkJCwACAAAAAA==.Talenel:BAAALgAECgMJAwAAAA==.Talyzien:BAAALgADCgQJBQAAAA==.',
Te='Tealan:BAABLgAECn8eAAMQAAgJvxPgHACeAQAQAAcJSBLgHACeAQAOAAcJExI5CABnAQAAAA==.Tealyn:BAAALgADCgYJCgAAAA==.Teluz:BAAALgAECgQJCgAAAA==.Tendra:BAAALgAECgYJBQAAAA==.Teronreborn:BAABLgAECn8fAAIBAAcJQyafBQAtAgABAAcJQyafBQAtAgAAAA==.',
Th='Thaneer:BAAALgAECgEJAQAAAA==.Thanos:BAABLgAECn8UAAINAAYJ7Q5+pAA3AQANAAYJ7Q5+pAA3AQAAAA==.Throstmok:BAABLgAECn8hAAIEAAgJzBsjAgADAgAEAAgJzBsjAgADAgAAAA==.Thränton:BAAALgAECgEJAQABLgAECgcJEQACAAAAAA==.Thumbalina:BAAALgAECgYJDAAAAA==.',
Tp='Tpaste:BAAALgADCgcJBwAAAA==.',
Tr='Trout:BAAALgADCgYJDAABLgAECgYJCgACAAAAAA==.Trovikk:BAAALgADCgUJBQAAAA==.',
Tu='Turg:BAAALgAECgMJAwABLgAECgQJBwACAAAAAA==.Turgress:BAAALgAECgQJBwAAAA==.',
['Tà']='Tàmber:BAAALgADCgUJBQAAAA==.',
Ul='Ulfast:BAABLgAECn8WAAIfAAcJlR6DAwADAgAfAAcJlR6DAwADAgAAAA==.',
Va='Vannhellsing:BAAALgAECgYJEQAAAA==.Vanyel:BAABLgAECn8iAAIHAAgJXg1dFgCQAQAHAAgJXg1dFgCQAQAAAA==.Vaudorka:BAABLgAECn8VAAIcAAcJ3x7EAAAKAgAcAAcJ3x7EAAAKAgAAAA==.',
Ve='Veliuz:BAAALgADCgQJBAAAAA==.Velrynth:BAAALgAECgcJEgAAAA==.Vemal:BAABLgAECn8WAAIJAAgJFA/OUwBtAQAJAAgJFA/OUwBtAQAAAA==.',
Vo='Vociferoy:BAABLgAECn8eAAIJAAcJOR/hBAAtAgAJAAcJOR/hBAAtAgAAAA==.Voidsteffan:BAAALgAECgYJDQAAAA==.',
Vr='Vryadox:BAAALgAECgcJDQABLgAFFAQJBQAWAFkMAA==.',
Vv='Vv:BAACLgAFFH8ZAAIYAAYJYyYxAAAqAgAYAAYJYyYxAAAqAgAuAAQKfyoAAhgACQkbJuMAANoDABgACQkbJuMAANoDAAAA.',
Vz='Vz:BAAALgADCgUJBQAAAA==.',
Wh='Whoppin:BAAALgAECgIJAgAAAA==.',
Wi='Wiglimparms:BAAALgAECgIJAgAAAA==.',
Wy='Wysselbow:BAAALgADCggJDQAAAA==.',
Xa='Xalzi:BAAALgADCggJCQABLgAECgYJDAACAAAAAA==.',
Xi='Xingwong:BAABLgAECn8aAAIgAAYJFSTQAgAAAgAgAAYJFSTQAgAAAgAAAA==.',
Za='Zannytoes:BAABLgAECn8aAAIaAAcJ8gqDDwDpAAAaAAcJ8gqDDwDpAAAAAA==.',
Ze='Zead:BAAALgAECgEJAQAAAA==.Zerana:BAAALgAECgUJBQAAAA==.',
Zi='Zie:BAABLgAECn8iAAIZAAgJvg/SBgCSAQAZAAgJvg/SBgCSAQAAAA==.Zikren:BAAALgAECggJCAAAAA==.',
['Ðo']='Ðonkle:BAAALgAECgQJBwAAAA==.',
['Ðr']='Ðrewid:BAAALgADCgEJAQAAAA==.',
['Ñi']='Ñice:BAAALgAECgkJDAAAAA==.',
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
