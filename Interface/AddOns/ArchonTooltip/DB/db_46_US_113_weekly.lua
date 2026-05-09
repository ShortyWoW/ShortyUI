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

local lookup = {'Monk-Windwalker','Mage-Frost','Monk-Brewmaster','Hunter-BeastMastery','Unknown-Unknown','Druid-Restoration','Paladin-Protection','Warrior-Fury','Shaman-Elemental','Shaman-Restoration','Priest-Discipline','Warlock-Destruction','Paladin-Holy','Warlock-Demonology','Paladin-Retribution','Monk-Mistweaver','Evoker-Devastation','DeathKnight-Unholy','DeathKnight-Blood','Druid-Balance','Druid-Feral','Shaman-Enhancement','Warrior-Arms','DemonHunter-Devourer','Priest-Shadow','Priest-Holy','Evoker-Augmentation','Evoker-Preservation','Druid-Guardian','Warlock-Affliction','Mage-Fire','Mage-Arcane','Hunter-Marksmanship','Rogue-Subtlety','Hunter-Survival','Rogue-Outlaw','Warrior-Protection','DemonHunter-Havoc',}
local provider = {region='US',realm='GrizzlyHills',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abramz:BAAALgADCgMJAwAAAA==.',
Ad='Adely:BAAALgAECgEJAQAAAA==.Adelymon:BAAALgAECgYJCwAAAA==.Adelymonk:BAAALgAECgQJBAAAAA==.Adrahil:BAAALgADCgIJAgAAAA==.',
Ae='Aeonra:BAAALgADCgIJAgAAAA==.',
Ag='Agronak:BAAALgAECgQJBgAAAA==.',
Al='Aldan:BAAALgADCgMJAwAAAA==.Aldazen:BAABLgAECn8uAAIBAAgJ8COkAwC+AgABAAgJ8COkAwC+AgAAAA==.Alenara:BAAALgAECgYJCQABLgAECggJFgACAOYFAA==.Aletheìa:BAAALgAECgEJAQAAAA==.Alovan:BAAALgADCgEJAQABLgAECgcJHAADACMGAA==.Alyssandra:BAAALgAECgYJDgAAAA==.',
Am='Amarella:BAABLgAECn8UAAIEAAcJqSAqIgDQAQAEAAcJqSAqIgDQAQAAAA==.Amarrite:BAAALgAECgEJAgAAAA==.Ammalane:BAAALgADCgkJDQABLgAECgEJAgAFAAAAAA==.Amunzo:BAAALgAECgEJAQABLgAECgYJCwAFAAAAAA==.',
An='Angler:BAAALgAECgMJAwAAAA==.Angyrolaj:BAAALgAECgYJEAAAAA==.',
Aq='Aquadora:BAAALgADCgMJAwAAAA==.',
Ar='Arangarr:BAABLgAECn8rAAIGAAgJPB8CCQC6AgAGAAgJPB8CCQC6AgAAAA==.Arcin:BAAALgADCgEJAQAAAA==.Areyana:BAAALgAECgYJCQAAAA==.Areyoudead:BAAALgAECgQJBAABLgADCgYJCwAFAAAAAA==.Aristoi:BAAALgAECgEJAQAAAA==.Arkand:BAAALgADCgUJBAAAAA==.Arkandra:BAAALgAECgMJBgAAAA==.Arkara:BAAALgADCgEJAQAAAA==.Arrietty:BAAALgAECgUJEQAAAA==.Arthues:BAAALgAECgQJBAAAAA==.Arthâs:BAAALgAECgYJBQAAAA==.Arumathe:BAABLgAECn8XAAIHAAkJwRL8BwDRAQAHAAkJwRL8BwDRAQAAAA==.',
As='Asura:BAACLgAFFH8HAAIIAAMJKyASFgD+AAAIAAMJKyASFgD+AAAuAAQKfx8AAggACAlJIt8IAB4DAAgACAlJIt8IAB4DAAAA.',
Au='Aurelian:BAAALgAECgEJAgAAAA==.',
Az='Az:BAAALgAECgYJEAAAAA==.Azeriall:BAABLgAECn8uAAMJAAgJjAxVHwBUAQAJAAgJjAxVHwBUAQAKAAQJSgFVhgB7AAAAAA==.Azerowolf:BAAALgADCggJCAAAAA==.Azráèl:BAAALgADCgMJAwAAAA==.',
Ba='Babyboom:BAAALgAECgEJAQAAAA==.Baconhammr:BAAALgAECgYJCwAAAA==.Badazmf:BAAALgADCgcJDAABLgAECggJIAALAOAXAA==.Baddream:BAAALgAECgYJCgAAAA==.Balenciagosa:BAAALgADCgUJBQABLgAECggJFgACAOYFAA==.Banshiï:BAABLgAECn8cAAIMAAgJahBiBgCKAQAMAAgJahBiBgCKAQAAAA==.Bax:BAAALgADCgIJAgAAAA==.Baxar:BAAALgAECgIJAgAAAA==.',
Bb='Bbd:BAAALgAECggJCQABLgAECgYJDgAFAAAAAA==.',
Be='Beeftard:BAABLgAECn8XAAINAAgJzRhhKgDfAQANAAgJzRhhKgDfAQAAAA==.Bellavix:BAAALgADCgMJBAAAAA==.Benafflic:BAAALgAECgEJAQAAAA==.Berserrk:BAAALgADCgYJBgAAAA==.Bershale:BAAALgAECgEJAQABLgAECgYJBwAFAAAAAA==.',
Bi='Bifficus:BAAALgAECgUJCAAAAA==.Big:BAAALgADCgMJBAAAAA==.',
Bl='Blackscorn:BAAALgADCgEJAQAAAA==.Blackthôrne:BAAALgADCgUJCQAAAA==.Blucki:BAABLgAECn8YAAIOAAgJsQlBcwDjAAAOAAgJsQlBcwDjAAAAAA==.',
Bo='Bobfu:BAAALgADCgYJCAAAAA==.',
Br='Brieze:BAAALgADCgIJAgAAAA==.Brige:BAAALgAECggJBgAAAA==.Brightstar:BAAALgADCgEJAQAAAA==.Brimaz:BAAALgADCgEJAQAAAA==.',
Bu='Buhhead:BAAALgADCgUJBgAAAA==.Bunana:BAAALgADCgEJAQAAAA==.Bunbear:BAAALgAECgIJAgAAAA==.Bunette:BAAALgADCgEJAQAAAA==.',
Bw='Bwamsamdi:BAAALgADCgYJBgAAAA==.',
By='Byzantium:BAAALgAECgYJEwAAAA==.',
['Bô']='Bônebeard:BAAALgAECgEJAQAAAA==.',
Ca='Cabledryer:BAAALgAECgQJEAAAAA==.Caelidpackx:BAAALgADCgYJBwAAAA==.Caluu:BAAALgADCgEJAQAAAA==.Carnry:BAAALgADCgQJBAAAAA==.Catboy:BAABLgAECn8aAAICAAgJ3xSlawA5AQACAAgJ3xSlawA5AQAAAA==.Catnips:BAABLgAECn8cAAIPAAgJRxibKwDPAQAPAAgJRxibKwDPAQAAAA==.Catpow:BAAALgAECgkJAgAAAA==.',
Ch='Chanaranach:BAAALgAECgYJCgAAAA==.Cheelo:BAAALgAECgcJDQAAAA==.Chknnugget:BAAALgAECgMJBQAAAA==.Chromatic:BAABLgAECn8aAAMKAAgJng6RJACUAQAKAAgJng6RJACUAQAJAAQJXQ5JOQDIAAAAAA==.',
Ci='Cindrethresh:BAAALgAECgEJAQAAAA==.',
Co='Coffeeblak:BAABLgAECn8ZAAMBAAgJBRNBJgCmAQABAAcJlxNBJgCmAQAQAAUJFQ62PwDkAAAAAA==.Coldstorm:BAAALgAECgYJCgAAAA==.Compensating:BAAALgADCgYJBgAAAA==.Connor:BAAALgADCgcJBwAAAA==.Connsumption:BAAALgAECgYJCgAAAA==.Corrine:BAAALgADCgQJBwAAAA==.',
Cr='Crazybatt:BAAALgAECgYJDQAAAA==.Crypt:BAAALgAECgYJCgAAAA==.',
Cu='Cuckchairpov:BAACLgAFFH8KAAMDAAMJzxMzIADeAAADAAMJsREzIADeAAABAAIJQg1zDACgAAAuAAQKfysAAwEACAm8H2MKANICAAEACAl4HWMKANICAAMACAnrEwUPANgBAAAA.',
Cy='Cynderleena:BAAALgAECgQJBAAAAA==.Cynyia:BAABLgAECn8uAAIEAAgJnBU3IgDPAQAEAAgJnBU3IgDPAQAAAA==.',
Cz='Czk:BAAALgADCgYJBgABLgAECggJGQABAAUTAA==.',
Da='Daddyelessar:BAAALgAECgQJBwAAAA==.Dafattyup:BAABLgAECn8aAAIOAAYJlRy9SABOAQAOAAYJlRy9SABOAQAAAA==.Dagon:BAAALgAECgMJAwAAAA==.Dakotarain:BAAALgADCgIJAgAAAA==.Dalerontwo:BAAALgADCgEJAQAAAA==.Darruin:BAAALgAECgcJCwABLgAFFAYJFgARAM8cAA==.Dayrun:BAAALgAECgUJDQAAAA==.',
De='Deadicee:BAAALgAECgIJAgABLgAECgYJEwAFAAAAAA==.Deathturtle:BAABLgAECn8eAAISAAgJLxBaRgBoAQASAAgJLxBaRgBoAQAAAA==.Deavaos:BAAALgAECgQJBwAAAA==.Dedmartigan:BAAALgADCgUJBQAAAA==.Deeanndra:BAAALgAECgcJEAAAAA==.Deevz:BAAALgAECgIJAgAAAA==.Demiz:BAABLgAECn8mAAMKAAgJ4xAKLABnAQAKAAgJ4xAKLABnAQAJAAYJnQ36LAADAQAAAA==.Deredris:BAAALgAECgQJBAABLgAECgYJCgAFAAAAAA==.Dertka:BAAALgAECgYJDAAAAA==.',
Di='Discodruid:BAAALgAECgYJEwAAAA==.Dishsoap:BAAALgAECgMJAwABLgAFFAQJCgAIAH0SAA==.Dixie:BAAALgAECgEJAQAAAA==.',
Dj='Djall:BAAALgAECgUJBQAAAA==.',
Do='Dommy:BAAALgAECgEJAwABLgAECgcJHgADAMomAA==.Domw:BAAALgAECgYJCgABLgAECgcJHgADAMomAA==.Donham:BAACLgAFFH8SAAMSAAYJxhuKCQC8AQASAAUJxhuKCQC8AQATAAEJAAA7EwBZAAAuAAQKfx0AAhIACAnLHzYeAMsCABIACAnLHzYeAMsCAAAA.Dorkimedes:BAAALgAECgQJCgAAAA==.Dottie:BAABLgAECn8oAAMMAAgJJhM1FwCQAQAOAAgJ2xEhLAC0AQAMAAcJJQ81FwCQAQAAAA==.Dotvinci:BAAALgAECgYJBgAAAA==.',
Dr='Draelesh:BAABLgAECn8dAAIUAAgJPxHXFACZAQAUAAgJPxHXFACZAQAAAA==.Draenk:BAAALgADCgUJBQAAAA==.Dragún:BAAALgAECgYJCwAAAA==.Drakari:BAAALgADCgYJBgAAAA==.Drewit:BAABLgAECn8VAAIVAAYJPxAzFQBiAQAVAAYJPxAzFQBiAQAAAA==.',
Du='Ducan:BAAALgADCgQJBwAAAA==.Duskmane:BAAALgAECgIJAwAAAA==.',
Dw='Dwadler:BAAALgAECgYJEgAAAA==.',
Dy='Dyrkonian:BAAALgAECgQJBwAAAA==.',
Ei='Eireann:BAAALgADCgcJCQAAAA==.',
El='Elerrak:BAAALgAECgEJAQABLgAFFAYJFAAWAAodAA==.Elindalia:BAAALgAECgMJAwAAAA==.',
Em='Emberash:BAAALgADCgcJBwAAAA==.Embre:BAAALgAFFAMJAwAAAA==.Emorri:BAAALgAECgYJBgAAAA==.Empyrea:BAAALgAECgQJBQAAAA==.',
Er='Eraina:BAAALgADCgIJAgAAAA==.Ericles:BAABLgAECn8ZAAMXAAcJ5h3LBwDYAQAXAAcJ5h3LBwDYAQAIAAIJlAVllwBkAAAAAA==.Erys:BAAALgAECgYJCQAAAA==.Erébus:BAABLgAECn8iAAIYAAkJ7hgXDgBYAgAYAAkJ7hgXDgBYAgAAAA==.',
Ev='Ev:BAAALgAECgQJBAAAAA==.Evergreene:BAAALgADCggJCAABLgAECgEJAgAFAAAAAA==.Evlpotato:BAABLgAECn8gAAQLAAgJ4BdqDgDqAQALAAcJNBpqDgDqAQAZAAYJ8B5TGAB7AQAaAAEJlAdOfwAzAAAAAA==.Evojak:BAAALgAECgYJDgAAAA==.',
Fa='Faevelia:BAAALgAECgEJAQAAAA==.Fairaday:BAABLgAECn8lAAIEAAgJSgoDPQBZAQAEAAgJSgoDPQBZAQAAAA==.Fanshen:BAAALgAECgEJAgAAAA==.Fauchi:BAAALgADCgEJAQAAAA==.Faxqueenmage:BAAALgAECgYJDwAAAA==.',
Fe='Felador:BAAALgADCgUJCgAAAA==.Feldo:BAAALgAECgYJBgAAAA==.Felmès:BAAALgADCgYJBgABLgAECggJFgACAOYFAA==.Fennec:BAAALgAECgUJDAAAAA==.Feralarak:BAAALgAECgQJDAABLgAFFAYJFAAWAAodAA==.',
Fi='Firebrandd:BAACLgAFFH8WAAMRAAYJzxyQAACRAQARAAUJnyCQAACRAQAbAAIJOg4kNQBZAAAuAAQKfzIAAxEACAk3JmACAA8DABEACAkrImACAA8DABsACAnQJA0FAKACAAAA.Fizehbubbleh:BAEALgADCgYJBgABLgAECggJHwAJANsaAA==.Fizehtotems:BAEBLgAECn8fAAMJAAgJ2xr8EgDBAQAJAAgJ2xr8EgDBAQAKAAQJHhcbPQAQAQAAAA==.',
Fl='Fleshoracle:BAAALgAECgQJBAAAAA==.Fluctuates:BAAALgAECgQJCAAAAA==.',
Fo='Foron:BAAALgAECgIJAgAAAA==.',
Fr='Frankkastle:BAAALgAECgYJDwAAAA==.Frazelia:BAAALgADCgkJDgABLgAECgYJFQAVAD8QAA==.Fribble:BAAALgAECgcJDwAAAA==.Froggierlynx:BAAALgAFFAQJBAAAAA==.Froznfate:BAABLgAECn8cAAIHAAgJlCXfAAD1AgAHAAgJlCXfAAD1AgAAAA==.Fryes:BAAALgAECgkJDAAAAA==.',
Fu='Fuzziebutt:BAAALgADCgMJBAAAAA==.',
Fw='Fwibble:BAAALgAECgEJAQABLgAECgcJDwAFAAAAAA==.',
Fy='Fyrelady:BAAALgADCggJDgABLgAECgEJAgAFAAAAAA==.Fyrestone:BAAALgAECgEJAgAAAA==.',
['Fæ']='Fæder:BAAALgADCgYJBgAAAA==.',
Ga='Gabarnak:BAAALgADCgIJAgABLgAECgYJEAAFAAAAAA==.Galencharred:BAAALgAECgUJEQAAAA==.Garagon:BAABLgAECn8dAAIcAAgJFBThCADVAQAcAAgJFBThCADVAQAAAA==.Gauss:BAAALgAECgYJEwABLgAECgcJDwAFAAAAAA==.Gaîîa:BAABLgAECn8cAAIEAAgJBBp2JQC/AQAEAAgJBBp2JQC/AQAAAA==.',
Ge='Gerva:BAABLgAECn8aAAISAAgJUQ6/NwCaAQASAAgJUQ6/NwCaAQAAAA==.',
Gh='Ghlain:BAAALgAECgQJBAAAAA==.Ghorfindor:BAAALgAECgYJDwAAAA==.Ghostlybrew:BAACLgAFFH8UAAIDAAYJTBpOBgCUAQADAAYJTBpOBgCUAQAuAAQKfxYAAgMACAmoH94TAHECAAMACAmoH94TAHECAAAA.',
Gi='Gigastorm:BAAALgADCgIJAQAAAA==.Gilas:BAAALgAECgYJEgAAAA==.',
Gl='Glaivemstake:BAAALgADCgcJBwAAAA==.',
Gn='Gnik:BAAALgAECgcJDQAAAA==.',
Gr='Graahak:BAAALgADCgMJAwAAAA==.Graydenton:BAAALgAECgkJCQABLgAECggJBgAFAAAAAA==.Gruuven:BAAALgADCgUJBwAAAA==.',
Gu='Gutmtmon:BAAALgAECgYJDwAAAA==.',
Gw='Gwenivive:BAABLgAECn8YAAIEAAgJ3RQkIwDLAQAEAAgJ3RQkIwDLAQAAAA==.',
['Gí']='Gízmo:BAAALgADCgUJBQAAAA==.',
Ha='Haenus:BAABLgAECn8dAAIYAAgJfhPNPQBAAQAYAAgJfhPNPQBAAQAAAA==.Hamor:BAAALgAECgkJAQAAAA==.Harrynear:BAAALgADCgMJAwABLgAECgYJEAAFAAAAAA==.Haunt:BAAALgAECgUJBQAAAA==.Havark:BAAALgAECgMJAwAAAA==.',
He='Healbilly:BAAALgADCgEJAQAAAA==.Hellzknîght:BAABLgAECn8VAAISAAYJCRIoZAAbAQASAAYJCRIoZAAbAQAAAA==.',
Ho='Holek:BAAALgAECgYJDwAAAA==.Holgo:BAAALgAFFAEJAQAAAA==.Holgy:BAACLgAFFH8XAAIdAAYJFR/iAADYAQAdAAYJFR/iAADYAQAuAAQKfyQAAh0ACQlVI0wBAEkDAB0ACQlVI0wBAEkDAAAA.Holybeard:BAABLgAECn8nAAIPAAgJvhsPFwBDAgAPAAgJvhsPFwBDAgAAAA==.Hooks:BAAALgADCggJEgAAAA==.',
Hu='Hunterturtle:BAAALgADCgUJBQAAAA==.',
Ic='Icia:BAAALgAECgEJAQAAAA==.',
Id='Idontmiss:BAAALgAECgIJBwAAAA==.',
Il='Ilickboody:BAAALgADCgQJBAAAAA==.Illustra:BAAALgAECgcJEQABLgAECggJFgACAOYFAA==.',
Im='Imcaldo:BAAALgADCgYJBgAAAA==.Imcaldoo:BAAALgADCgUJCgAAAA==.',
In='Interrupt:BAAALgAECgUJDQAAAA==.',
Ir='Irox:BAAALgADCgMJAwAAAA==.',
Is='Isaic:BAAALgADCgIJAgAAAA==.Iseila:BAABLgAECn8YAAICAAkJ9Q0NMwDUAQACAAkJ9Q0NMwDUAQAAAA==.Isevio:BAAALgAECgMJBwAAAA==.',
It='Ithorus:BAAALgAECgUJCwAAAA==.',
Ja='Jaadb:BAAALgAECgMJAwAAAA==.Jaadd:BAAALgAECgIJAgAAAA==.Jaadi:BAAALgAECgIJAwAAAA==.Jaata:BAAALgADCgcJEAAAAA==.Jamien:BAABLgAECn8iAAMPAAgJlR0hEgBpAgAPAAgJlR0hEgBpAgANAAUJHQEmdwCdAAAAAA==.Jasnah:BAAALgAECgUJBQAAAA==.Jasnos:BAAALgAECgUJDAAAAA==.',
Jd='Jdk:BAAALgAECgUJBwAAAA==.',
Je='Jelf:BAAALgAECgQJBAAAAA==.Jenzing:BAABLgAECn8VAAMOAAgJqh0LKwBjAgAOAAcJqh0LKwBjAgAeAAEJAACsIwBjAAAAAA==.Jessemyn:BAAALgAECgEJAQAAAA==.',
Jh='Jholy:BAAALgADCggJCAAAAA==.',
Jo='Jobokenhones:BAABLgAECn8fAAIYAAgJiBg+HQDaAQAYAAgJiBg+HQDaAQAAAA==.Johadgan:BAAALgADCgEJAQAAAA==.',
Jp='Jproudmore:BAAALgADCgUJBQABLgADCgYJCwAFAAAAAA==.',
Js='Jsberg:BAABLgAECn8XAAIIAAgJwRUZEgDfAQAIAAgJwRUZEgDfAQAAAA==.',
Ka='Kaathe:BAABLgAECn8lAAMCAAYJGx7chADHAQACAAYJGx7chADHAQAfAAEJjhqYDwA4AAAAAA==.Kadance:BAAALgAECgYJCQAAAA==.Kaidiis:BAABLgAECn8cAAIPAAgJoA2KRgByAQAPAAgJoA2KRgByAQAAAA==.Kaido:BAAALgAECgEJAQAAAA==.Kalder:BAAALgADCgcJBwAAAA==.Karbonn:BAAALgAECgYJCQAAAA==.Kay:BAAALgAECgcJBwAAAA==.Kazeraz:BAAALgADCgEJAQAAAA==.',
Ke='Kegbreaker:BAABLgAECn8lAAIaAAgJVQdtIQA9AQAaAAgJVQdtIQA9AQAAAA==.',
Kh='Khanas:BAAALgAECgYJCQAAAA==.Kheru:BAAALgADCgkJDgAAAA==.Khoan:BAAALgAECgYJCgAAAA==.',
Ki='Kimbustible:BAABLgAECn82AAICAAkJfiLjBAAnAwACAAkJfiLjBAAnAwAAAA==.Kimchi:BAAALgAECgcJDAABLgAECgkJNgACAH4iAA==.',
Kn='Knockknocko:BAAALgAECgUJCwAAAA==.',
Ko='Kobir:BAAALgADCgEJAQAAAA==.Komodostyle:BAABLgAECn8cAAQcAAgJ+QcqEQAqAQAcAAcJ+ggqEQAqAQARAAIJWw6vNQBoAAAbAAEJaRBKWAA8AAAAAA==.Koobideh:BAAALgADCgEJAQAAAA==.',
Kr='Kriddler:BAAALgADCgQJBAAAAA==.Krisarugala:BAABLgAECn8VAAIUAAcJgg1EIwAfAQAUAAcJgg1EIwAfAQAAAA==.',
Ku='Kujoluvsmilf:BAAALgAECgYJBgAAAA==.Kunuku:BAAALgADCgUJBQAAAA==.Kurash:BAAALgADCgcJBwAAAA==.Kurion:BAAALgAECgkJBAAAAA==.Kurogami:BAAALgADCggJDQAAAA==.',
Ky='Kylesxmom:BAABLgAECn81AAMSAAgJcCGpDQCWAgASAAgJtCCpDQCWAgATAAgJzxWrIQA1AQAAAA==.Kymal:BAABLgAECn8sAAIYAAgJshc3IADHAQAYAAgJshc3IADHAQAAAA==.Kymbria:BAAALgADCgUJCAAAAA==.Kymora:BAAALgADCgcJBwAAAA==.Kyndrissa:BAAALgADCgUJBQAAAA==.',
['Kë']='Këy:BAABLgAECn8nAAISAAgJ0h2uGAA4AgASAAgJ0h2uGAA4AgAAAA==.',
La='Latrice:BAACLgAFFH8WAAICAAYJpBwbCgDWAQACAAYJpBwbCgDWAQAuAAQKfyAAAwIACQkAI9wJAHYDAAIACQkAI9wJAHYDACAAAQltGNwYAFEAAAAA.Lavynder:BAABLgAECn8XAAIYAAgJ6xURWgCTAQAYAAgJ6xURWgCTAQAAAA==.Laërtes:BAAALgAECgMJAwAAAA==.',
Le='Leiamirage:BAAALgAECgUJCQAAAA==.Leviscus:BAAALgAECgEJAgAAAA==.',
Li='Lifetap:BAAALgADCgMJAwAAAA==.Lightbàne:BAAALgAECggJEwAAAA==.Lightningrod:BAAALgAECgYJBwAAAA==.Lightshaolin:BAAALgADCgUJBQAAAA==.Lildruidz:BAAALgAECgcJEgAAAA==.Lillivarak:BAAALgAECgYJCwAAAA==.Lilzdrlockz:BAAALgADCgEJAQAAAA==.Lithedra:BAAALgADCgcJDwAAAA==.',
Lu='Lucavi:BAAALgAECgMJAwAAAA==.Luke:BAAALgADCgUJBwAAAA==.Luma:BAAALgAECgMJBQAAAA==.Luther:BAABLgAECn8XAAIDAAkJNw9VJQDYAQADAAkJNw9VJQDYAQAAAA==.',
Ly='Lyla:BAAALgADCgQJBgAAAA==.',
Ma='Magnux:BAAALgADCgYJBgAAAA==.Malríus:BAAALgAECgQJEQAAAA==.Manales:BAAALgAECgcJBgAAAA==.Marhukai:BAABLgAECn8eAAIPAAgJXxwnFwBCAgAPAAgJXxwnFwBCAgAAAA==.Marotal:BAABLgAECn8XAAICAAYJZhb8WABjAQACAAYJZhb8WABjAQAAAA==.Martysparty:BAABLgAECn8bAAIHAAgJUR3nBQAOAgAHAAgJUR3nBQAOAgAAAA==.Mavaena:BAAALgAECgMJBQAAAA==.Mavrane:BAAALgADCgEJAgAAAA==.',
Me='Meashakegs:BAAALgAECggJEAAAAA==.Mechaboomer:BAABLgAECn8cAAIEAAgJTBoFGAAPAgAEAAgJTBoFGAAPAgAAAA==.Megafire:BAAALgADCggJDAAAAA==.Melcanthet:BAAALgADCggJCAAAAA==.Mellowrock:BAAALgAECgUJBgABLgAECgYJBQAFAAAAAA==.',
Mi='Mickhaggis:BAAALgADCgIJAgAAAA==.Micktarogar:BAAALgAECgcJEwAAAA==.Mickwutang:BAAALgAFFAEJAQAAAA==.Miklaga:BAAALgAECgEJAgAAAA==.Milince:BAAALgADCgMJAgAAAA==.Minikloon:BAAALgAECgYJDgAAAA==.Minphoria:BAAALgADCgQJBgAAAA==.Missylock:BAAALgADCgYJBgAAAA==.Mistilinn:BAABLgAECn8YAAIhAAcJWAMCFAC7AAAhAAcJWAMCFAC7AAAAAA==.Miyri:BAAALgADCgYJBgABLgAFFAIJAgAFAAAAAA==.',
Mo='Mollyporph:BAAALgAECgEJAQAAAA==.Monoco:BAAALgAECgYJDQAAAA==.Moopandax:BAACLgAFFH8LAAIUAAMJURNDDgD8AAAUAAMJURNDDgD8AAAuAAQKfysAAhQACQkZIOEBABQDABQACQkZIOEBABQDAAEuAAUUBQkPABQASBkA.Mortrum:BAAALgADCgQJBAAAAA==.Moxestime:BAAALgAECgEJAgAAAA==.Moxsdeaths:BAAALgADCgcJBwAAAA==.',
Mu='Mushaboom:BAAALgAECgYJCQAAAA==.Muzzler:BAABLgAECn8vAAICAAgJQR7nGQBPAgACAAgJQR7nGQBPAgAAAA==.',
My='Myeyes:BAAALgAECgEJAgAAAA==.Mylinkah:BAAALgADCgQJBAAAAA==.Mynamefizz:BAEALgAECggJCwABLgAECggJHwAJANsaAA==.Myotonic:BAAALgADCgQJBAAAAA==.Mythlok:BAAALgAECgMJAwAAAA==.Mythreiel:BAAALgAECgUJBgAAAA==.Mythykal:BAAALgAECgIJAgAAAA==.',
Na='Nadis:BAEALgAECgIJAwAAAA==.Narcessa:BAAALgADCgQJBAAAAA==.Nawk:BAAALgAECgEJAQAAAA==.',
Ne='Nennerb:BAAALgADCgQJBAAAAA==.',
Ni='Nicola:BAAALgAECgQJBwAAAA==.Nightxwish:BAAALgAECgUJEQAAAA==.Niranye:BAAALgADCgEJAQAAAA==.',
No='Noisemarine:BAAALgAFFAIJAgAAAA==.Nokk:BAAALgADCgEJAQAAAA==.Nokkco:BAAALgAECgEJAgAAAA==.Northleo:BAAALgADCgcJCwAAAA==.Northspirit:BAAALgAECgQJCgAAAA==.',
Nu='Nuit:BAAALgADCgUJBQABLgAECgYJCwAFAAAAAA==.',
Ny='Nyarlothep:BAAALgADCgkJIwAAAA==.',
Oa='Oakenshièld:BAAALgAECgQJBQAAAA==.',
Od='Odindh:BAAALgAECgYJCgAAAA==.Odins:BAAALgADCgEJAQABLgAECgYJCgAFAAAAAA==.',
Oh='Ohwhelp:BAABLgAFFH8FAAIbAAMJYBXKHQD7AAAbAAMJYBXKHQD7AAABLgAFFAYJFwAUADsmAA==.Ohyikers:BAACLgAFFH8XAAIUAAYJOyb2AAA8AgAUAAYJOyb2AAA8AgAuAAQKfygAAhQACAnsJSwGADYDABQACAnsJSwGADYDAAAA.',
Ok='Oken:BAAALgADCgUJBQAAAA==.',
Om='Om:BAAALgADCgcJCQAAAA==.',
Or='Orklock:BAAALgADCgMJAwAAAA==.',
Pa='Pallek:BAAALgADCggJCgABLgAECgYJDwAFAAAAAA==.Palli:BAAALgAECgUJEQAAAA==.Paogao:BAAALgAECgIJAwAAAA==.Parry:BAAALgADCgQJBAAAAA==.Pasghetti:BAAALgADCgMJAwAAAA==.Pasta:BAABLgAECn8gAAIiAAcJVBtmEQCTAQAiAAcJVBtmEQCTAQAAAA==.',
Pe='Pewpewbite:BAAALgAECgYJCQAAAA==.',
Ph='Phantomarrow:BAACLgAFFH8NAAQhAAUJ8AttDgDRAAAjAAMJJgXgEQDVAAAhAAUJMwttDgDRAAAEAAEJzQFcVABAAAAuAAQKfxUABAQABgk8IANOAH8BAAQABgkbHgNOAH8BACEABQmzGaJCAE0BACMAAQkAABNEAAAAAAAA.Phatcow:BAABLgAECn8mAAMKAAgJ4Rl8FwBaAgAKAAgJ4Rl8FwBaAgAWAAcJcBLGCQB+AQAAAA==.Phoseidon:BAAALgADCgcJCQAAAA==.Phude:BAABLgAECn8yAAIPAAgJqBkjJwDkAQAPAAgJqBkjJwDkAQAAAA==.',
Pi='Pinch:BAAALgAECgMJAwAAAA==.',
Po='Pohl:BAAALgAECgYJCQAAAA==.Poohynok:BAABLgAECn8qAAICAAgJyyQmCgDVAgACAAgJyyQmCgDVAgAAAA==.',
Pu='Pukefeast:BAAALgAECgYJDAAAAA==.',
Py='Pyramys:BAACLgAFFH8QAAIiAAUJOx0yCABoAQAiAAUJOx0yCABoAQAuAAQKfyEAAiIACAm3IP8QAJkCACIACAm3IP8QAJkCAAAA.',
['Pè']='Pèrce:BAAALgAECgYJCQAAAA==.',
Qu='Quepaoka:BAAALgADCgIJAgAAAA==.',
Ra='Raklem:BAAALgAECgMJAwABLgAECgYJCgAFAAAAAA==.Ramble:BAAALgADCgQJBAABLgAECgQJBgAFAAAAAA==.Ramstein:BAAALgAECgMJAwAAAA==.Raphînîty:BAAALgADCgMJBQAAAA==.Rashari:BAAALgADCgYJCAAAAA==.Rawhawk:BAAALgAECgMJAwABLgAECgYJDwAFAAAAAA==.Razgrizz:BAAALgAECgEJAgAAAA==.',
Re='Retro:BAAALgAECgIJBAAAAA==.Revelatus:BAAALgAECgQJBgAAAA==.Reythanas:BAAALgAECgQJBwAAAA==.Rezzin:BAAALgAECgEJAQAAAA==.',
Ri='Rileyann:BAABLgAECn8YAAMaAAgJEQaMKwDxAAAaAAgJEQaMKwDxAAAZAAYJAwNHRADaAAAAAA==.',
Ro='Roozer:BAAALgAECgEJAQAAAA==.',
['Rå']='Råphå:BAAALgAECgMJBAAAAA==.',
Sa='Saelyria:BAAALgAFFAIJAgAAAA==.Saga:BAAALgADCgUJBQABLgAECgkJIgAHALYQAA==.Sagethepally:BAAALgAECgcJAgAAAA==.Saintfail:BAAALgAECgcJEwAAAA==.Sainthymn:BAAALgAECgcJCQABLgAECgcJEwAFAAAAAA==.Saintmist:BAABLgAECn8dAAIQAAcJhh/JCABnAgAQAAcJhh/JCABnAgAAAA==.Salero:BAAALgADCgIJAQAAAA==.Sandiera:BAABLgAECn8WAAMCAAgJ5gVAqgCGAQACAAgJ5gVAqgCGAQAgAAMJPAOnFwBcAAAAAA==.Saxtön:BAAALgADCggJEwAAAA==.',
Sc='Scoreboard:BAACLgAFFH8WAAIkAAYJiR8qAAABAgAkAAYJiR8qAAABAgAuAAQKfyEAAyQACQkgJg0AAOsDACQACQkgJg0AAOsDACIAAQnwFJNaAE8AAAAA.Scorn:BAAALgAECgYJDAAAAA==.Scottx:BAAALgAECgYJDwAAAA==.',
Se='Sebas:BAAALgAECgEJAQAAAA==.Sedric:BAAALgAECgYJCAAAAA==.Selkz:BAAALgAECgcJDQAAAA==.Selsonblue:BAAALgADCggJGwABLgAECgEJAQAFAAAAAA==.Sesskaa:BAAALgAECgYJCQAAAA==.',
Sh='Shadowcursed:BAAALgADCgcJCgAAAA==.Shadowstorm:BAAALgADCgQJBAAAAA==.Shadøws:BAAALgAECgEJAQAAAA==.Shathos:BAAALgADCgEJAQAAAA==.Sheebá:BAAALgADCgYJCwAAAA==.Shishkbob:BAAALgADCgkJCQAAAA==.Shivax:BAAALgAECgQJCQAAAA==.Shünúkh:BAAALgADCgYJBgAAAA==.',
Si='Signal:BAAALgAECgEJAQAAAA==.Singbow:BAAALgADCgYJBgABLgAECggJHQAGAKYNAA==.Sinogad:BAAALgAECggJEAAAAA==.Sinol:BAAALgAECgYJDwABLgAECggJEAAFAAAAAA==.Sioux:BAAALgADCgEJAQAAAA==.Sixosix:BAAALgADCgIJAgAAAA==.',
Sk='Skaro:BAAALgAECgYJCQAAAA==.Skyborn:BAAALgAECgYJCQAAAA==.',
Sl='Slamahoochee:BAAALgAECgQJBQAAAA==.Slay:BAACLgAFFH8GAAIUAAIJLBTEHgCcAAAUAAIJLBTEHgCcAAAuAAQKfyYABBQACAmNIVoGAHkCABQACAmNIVoGAHkCABUABglkG40TAHgBAAYAAQk/A0OtAB4AAAAA.',
Sm='Smokedademon:BAAALgAECgMJBQAAAA==.Smokiebear:BAAALgAECgQJBwAAAA==.Smunkie:BAABLgAECn8eAAIDAAcJyiZ0BAClAgADAAcJyiZ0BAClAgAAAA==.',
Sn='Snickeers:BAAALgAECgEJAQAAAA==.',
So='Somogyi:BAAALgADCgIJAgAAAA==.',
Sp='Spopovich:BAAALgADCggJCAABLgAECgMJAwAFAAAAAA==.Sprints:BAAALgAECgQJBAAAAA==.',
St='Stinko:BAAALgADCgEJAgAAAA==.Stitchlock:BAAALgAECgIJAgAAAA==.Stitchofevil:BAABLgAECn8WAAQeAAcJuBoEBgACAgAeAAYJUB8EBgACAgAOAAQJmQlanwB+AAAMAAIJtQ8YYQBMAAAAAA==.Stonedshaman:BAAALgADCgYJBgABLgAECgIJAgAFAAAAAA==.Stormhands:BAAALgAECgYJDwAAAA==.Stormhugger:BAAALgAFFAEJAQAAAA==.Stoutnholy:BAAALgAECgYJCAAAAA==.Stratichnut:BAABLgAECn8dAAIGAAgJpg1ELQBwAQAGAAgJpg1ELQBwAQAAAA==.Stromar:BAAALgADCgcJDAAAAA==.Stwampadin:BAABLgAECn8YAAINAAgJtCFMCACPAgANAAgJtCFMCACPAgAAAA==.Stwevoker:BAAALgAECgMJAwABLgAECggJGAANALQhAA==.Stwonkfu:BAAALgAECggJCAABLgAECggJGAANALQhAA==.',
Su='Sumire:BAAALgADCggJDgABLgAECgYJCgAFAAAAAA==.',
Sv='Sveny:BAAALgAECgEJAQAAAA==.',
Sw='Swampert:BAACLgAFFH8KAAIIAAQJfRIoEAAwAQAIAAQJfRIoEAAwAQAuAAQKfx8AAggACQnKH88MAPACAAgACQnKH88MAPACAAAA.Swamperting:BAAALgAECgcJEQABLgAFFAQJCgAIAH0SAA==.Swaye:BAABLgAECn8mAAIZAAkJWBJgDQDzAQAZAAkJWBJgDQDzAQAAAA==.Sweetfox:BAAALgADCgMJAwAAAA==.Switched:BAAALgADCgcJBwABLgAECgcJHgADAMomAA==.Swizzle:BAAALgAECgQJBAAAAA==.',
Sy='Syllvanas:BAAALgAECgUJDQAAAA==.Sythia:BAAALgAECgEJAQABLgAECggJKQAOALcfAA==.',
Ta='Taltost:BAAALgAECgYJDwAAAA==.Tantrik:BAAALgADCgEJAQAAAA==.Tartin:BAAALgAECgMJAwAAAA==.Tarv:BAAALgADCgMJAQAAAA==.Tashamirage:BAAALgAECgMJBAAAAA==.Tauriel:BAAALgAECgUJBwAAAA==.',
Te='Teex:BAAALgADCgYJBwAAAA==.Teksuo:BAABLgAECn81AAIBAAgJnx3DBwBJAgABAAgJnx3DBwBJAgAAAA==.Telamontay:BAAALgADCgkJFQAAAA==.Telferas:BAAALgAECgYJEQABLgAFFAYJFgARAM8cAA==.Tenithon:BAACLgAFFH8FAAINAAMJPBzAFAAKAQANAAMJPBzAFAAKAQAuAAQKfyQAAg0ACQkHIX0FABQDAA0ACQkHIX0FABQDAAAA.Tenshenzen:BAAALgAECggJDAAAAA==.',
Th='Therandis:BAAALgADCgUJBQAAAA==.Thetombo:BAAALgAECgIJAgAAAA==.Thierry:BAAALgADCgUJBQAAAA==.Thierrye:BAABLgAECn8VAAIYAAYJBxtkTQC/AQAYAAYJBxtkTQC/AQAAAA==.Tholaren:BAABLgAECn8cAAMEAAgJQBFoKACwAQAEAAgJQBFoKACwAQAhAAUJUgcAFgCkAAAAAA==.Threed:BAAALgAECgYJCwAAAA==.Threewar:BAAALgAECgIJAgABLgAECgYJCwAFAAAAAA==.Thrissa:BAAALgAECgYJCQAAAA==.',
To='Torrque:BAAALgADCgkJCQABLgADCgYJCwAFAAAAAA==.Totemlicker:BAAALgAECgEJAQAAAA==.',
Tr='Trandeath:BAAALgAECgQJBAAAAA==.Trangon:BAABLgAECn8XAAIPAAgJzgnmVQBHAQAPAAgJzgnmVQBHAQAAAA==.Traveler:BAAALgADCgEJAQAAAA==.Trillion:BAAALgADCgMJAwAAAA==.',
Tu='Tunzoffun:BAAALgAECgIJAwAAAA==.',
Un='Underbyte:BAAALgADCggJDwAAAA==.Unknownname:BAAALgADCgMJAwAAAA==.',
Ur='Urholiness:BAAALgADCgkJDwAAAA==.',
Va='Vaeleia:BAAALgAECgQJBgAAAA==.Vahnkar:BAAALgADCgQJBwAAAA==.Valentinu:BAAALgADCgcJDwAAAA==.Valkyrie:BAAALgAECgEJAQAAAA==.Vaneshk:BAAALgADCgEJAQAAAA==.Varchemical:BAAALgAECgcJBwAAAA==.Varithal:BAABLgAECn8vAAIcAAgJ8x88AwCgAgAcAAgJ8x88AwCgAgABLgABCgYJCQAFAAAAAA==.Varri:BAAALgAECgMJBQAAAA==.Vastectomy:BAAALgAECgcJCQAAAA==.',
Ve='Vegasana:BAAALgADCgMJBAAAAA==.Velwing:BAAALgAECgUJBwAAAA==.Venawyn:BAAALgAECgYJEwAAAA==.Verakhaa:BAAALgAECgQJBAAAAA==.',
Vi='Vibepriest:BAAALgADCgEJAQAAAA==.Vindfaramaðr:BAABLgAECn8cAAIDAAcJIwZQLwDeAAADAAcJIwZQLwDeAAAAAA==.Vixin:BAAALgAECgYJDAAAAA==.',
Vo='Voidsaack:BAAALgADCgkJFgAAAA==.Voidz:BAAALgAECgEJAQAAAA==.Volfguar:BAAALgAECgQJAQAAAA==.Vortan:BAAALgAECgcJDAAAAA==.',
Vr='Vreya:BAAALgADCgkJFQABLgAECgEJAgAFAAAAAA==.',
Vy='Vynthus:BAAALgAECgQJCAAAAA==.',
['Vä']='Värys:BAAALgAECgEJAQAAAA==.',
Wa='Warhundin:BAEALgAECgUJBQABLgAECgkJIwAPAAERAA==.Warwan:BAAALgADCgIJAgAAAA==.Wazzdh:BAAALgADCgQJBAAAAA==.Wazzdot:BAAALgAECgQJBAAAAA==.Wazzhunnah:BAABLgAECn8dAAMjAAgJ3BFIDQDRAQAjAAgJ3BFIDQDRAQAhAAQJZAlaZQCqAAAAAA==.',
We='Werg:BAAALgAECggJCQABLgAFFAEJAQAFAAAAAA==.',
Wh='Whatmyname:BAABLgAECn8fAAIdAAgJegpqEQDwAAAdAAgJegpqEQDwAAAAAA==.Whispp:BAAALgAECgYJCAAAAA==.',
Wo='Wonsok:BAAALgAECgcJDgAAAA==.',
Wy='Wyvoker:BAABLgAECn8aAAIcAAgJ/hYmBwAGAgAcAAgJ/hYmBwAGAgABLgAECgkJCAAFAAAAAA==.',
['Wì']='Wìllow:BAAALgADCgIJAgAAAA==.',
['Wÿ']='Wÿm:BAAALgAECgkJCAAAAA==.',
Xe='Xenorion:BAAALgAECgMJAwAAAA==.Xephora:BAAALgAECgEJBQAAAA==.',
Xr='Xrinch:BAAALgADCgYJBgAAAA==.',
Xu='Xunadin:BAAALgADCggJCAAAAA==.Xuny:BAAALgAECgMJBgAAAA==.',
Yo='Yordi:BAAALgAECgUJCgAAAA==.',
Yu='Yuzuriha:BAABLgAECn8wAAIEAAgJESQZCAAPAwAEAAgJESQZCAAPAwAAAA==.',
Za='Zaelia:BAAALgADCgYJBgABLgAECggJIgAPAJUdAA==.Zamaze:BAABLgAECn8hAAIlAAgJ1SBRBABwAgAlAAgJ1SBRBABwAgAAAA==.Zannah:BAAALgAECgMJAwAAAA==.Zant:BAAALgAECgIJAQAAAA==.',
Ze='Zeekielle:BAEBLgAECn8iAAImAAgJpxG+DQClAQAmAAgJpxG+DQClAQABLgAECgkJIwAPAAERAA==.Zenius:BAAALgAECgMJAwAAAA==.Zerithrielle:BAABLgAECn8eAAImAAgJRRVHDwCMAQAmAAgJRRVHDwCMAQAAAA==.',
Zi='Zippii:BAAALgAECgYJBwAAAA==.Zipy:BAABLgAECn8dAAIaAAgJCx0WBwCDAgAaAAgJCx0WBwCDAgAAAA==.',
Zo='Zof:BAAALgAECgYJDgAAAA==.Zorathar:BAAALgADCgYJBgAAAA==.',
Zu='Zugtag:BAABLgAECn8lAAISAAgJlh8gEQB0AgASAAgJlh8gEQB0AgAAAA==.',
Zy='Zyllo:BAAALgAECgEJAQAAAA==.',
['Zá']='Závier:BAAALgAECgUJDAAAAA==.',
['Zõ']='Zõf:BAAALgAECgEJAQABLgAECgYJDgAFAAAAAA==.',
['Äe']='Äemond:BAAALgADCgMJAwAAAA==.',
['Ål']='Ålïce:BAABLgAECn8yAAIPAAgJVhi8IQAAAgAPAAgJVhi8IQAAAgAAAA==.',
['Ëd']='Ëdward:BAAALgADCgcJCgABLgAECgMJAwAFAAAAAA==.',
['Ôh']='Ôhmyn:BAAALgADCgMJAwABLgAECgYJCwAFAAAAAA==.',
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
