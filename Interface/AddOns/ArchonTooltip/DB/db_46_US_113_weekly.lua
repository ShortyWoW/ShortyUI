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

local lookup = {'Monk-Windwalker','Mage-Frost','Unknown-Unknown','Druid-Restoration','Warrior-Fury','Shaman-Elemental','Shaman-Restoration','Priest-Shadow','Warlock-Destruction','Paladin-Holy','Paladin-Retribution','Monk-Mistweaver','Monk-Brewmaster','Hunter-BeastMastery','Warlock-Demonology','Evoker-Devastation','DeathKnight-Unholy','DeathKnight-Blood','Druid-Balance','Shaman-Enhancement','Warrior-Arms','DemonHunter-Devourer','Priest-Discipline','Priest-Holy','Evoker-Augmentation','Paladin-Protection','Evoker-Preservation','Druid-Guardian','Warlock-Affliction','Mage-Fire','Mage-Arcane','Rogue-Subtlety','Hunter-Marksmanship','Hunter-Survival','Rogue-Outlaw','Druid-Feral','DemonHunter-Havoc','Warrior-Protection',}
local provider = {region='US',realm='GrizzlyHills',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abramz:BAAALgADCgMJAwAAAA==.',
Ad='Adely:BAAALgAECgEJAQAAAA==.Adelymon:BAAALgAECgUJCgAAAA==.Adelymonk:BAAALgAECgIJAgAAAA==.Adrahil:BAAALgADCgIJAgAAAA==.',
Ae='Aeonra:BAAALgADCgEJAQAAAA==.',
Ag='Agronak:BAAALgAECgQJBgAAAA==.',
Al='Aldan:BAAALgADCgMJAwAAAA==.Aldazen:BAABLgAECn8sAAIBAAgJQyOpAgCuAgABAAgJQyOpAgCuAgAAAA==.Alenara:BAAALgAECgIJAwABLgAECggJFgACAOYFAA==.Aletheìa:BAAALgAECgEJAQAAAA==.Alyssandra:BAAALgAECgUJCAAAAA==.',
Am='Amarella:BAAALgAECgcJEwAAAA==.Amarrite:BAAALgAECgEJAQAAAA==.Ammalane:BAAALgADCgkJDQABLgAECgEJAQADAAAAAA==.Amunzo:BAAALgAECgEJAQABLgAECgYJCwADAAAAAA==.',
An='Angyrolaj:BAAALgAECgQJCgAAAA==.',
Aq='Aquadora:BAAALgADCgMJAwAAAA==.',
Ar='Arangarr:BAABLgAECn8mAAIEAAgJRx61BgCrAgAEAAgJRx61BgCrAgAAAA==.Arcin:BAAALgADCgEJAQAAAA==.Areyana:BAAALgAECgIJAwAAAA==.Areyoudead:BAAALgAECgQJBAABLgADCgYJCwADAAAAAA==.Aristoi:BAAALgAECgEJAQAAAA==.Arkand:BAAALgADCgUJBAAAAA==.Arkandra:BAAALgAECgEJAgAAAA==.Arkara:BAAALgADCgEJAQAAAA==.Arrietty:BAAALgAECgUJDAAAAA==.Arthues:BAAALgADCgcJBwAAAA==.Arthâs:BAAALgAECgYJBQAAAA==.Arumathe:BAAALgAECgkJDwAAAA==.',
As='Asbestosis:BAAALgAECgEJAQAAAA==.Asura:BAABLgAECn8dAAIFAAgJSSLiCAAeAwAFAAgJSSLiCAAeAwAAAA==.',
Au='Aurelian:BAAALgAECgEJAgAAAA==.',
Az='Az:BAAALgAECgYJDAAAAA==.Azeriall:BAABLgAECn8oAAMGAAgJ8gu2FgBeAQAGAAgJ8gu2FgBeAQAHAAQJSgFghgB7AAAAAA==.Azráèl:BAAALgADCgMJAwAAAA==.',
Ba='Babyboom:BAAALgAECgEJAQAAAA==.Baconhammr:BAAALgAECgQJBQAAAA==.Badazmf:BAAALgADCgcJDAABLgAECggJIAAIAG0dAA==.Baddream:BAAALgAECgYJCQAAAA==.Balenciagosa:BAAALgADCgUJBQABLgAECggJFgACAOYFAA==.Banshiï:BAABLgAECn8UAAIJAAYJ9BLBBwA2AQAJAAYJ9BLBBwA2AQAAAA==.Bax:BAAALgADCgIJAgAAAA==.Baxar:BAAALgAECgIJAgAAAA==.',
Bb='Bbd:BAAALgAECggJCAABLgAECgYJDgADAAAAAA==.',
Be='Beeftard:BAABLgAECn8UAAIKAAcJtRdhKgDfAQAKAAcJtRdhKgDfAQAAAA==.Bellavix:BAAALgADCgMJBAAAAA==.Benafflic:BAAALgAECgEJAQAAAA==.Berserrk:BAAALgADCgYJBgAAAA==.Bershale:BAAALgAECgEJAQABLgAECgYJBgADAAAAAA==.',
Bi='Bifficus:BAAALgAECgIJAwAAAA==.Big:BAAALgADCgMJBAAAAA==.',
Bl='Blackscorn:BAAALgADCgEJAQAAAA==.Blackthôrne:BAAALgADCgUJCQAAAA==.Blucki:BAAALgAECgYJEgAAAA==.',
Bo='Bobfu:BAAALgADCgYJCAAAAA==.',
Br='Brieze:BAAALgADCgIJAgAAAA==.Brige:BAAALgAECggJBgAAAA==.Brightstar:BAAALgADCgEJAQAAAA==.Brimaz:BAAALgADCgEJAQAAAA==.',
Bu='Buhhead:BAAALgADCgUJBgAAAA==.Bunana:BAAALgADCgEJAQAAAA==.Bunbear:BAAALgAECgIJAgAAAA==.Bunette:BAAALgADCgEJAQAAAA==.',
Bw='Bwamsamdi:BAAALgADCgYJBgAAAA==.',
By='Byzantium:BAAALgAECgUJDQAAAA==.',
['Bô']='Bônebeard:BAAALgAECgEJAQAAAA==.',
Ca='Cabledryer:BAAALgAECgQJEAAAAA==.Caelidpackx:BAAALgADCgYJBwAAAA==.Caluu:BAAALgADCgEJAQAAAA==.Carnry:BAAALgADCgQJBAAAAA==.Catboy:BAABLgAECn8YAAICAAcJURUjpgCMAQACAAcJURUjpgCMAQAAAA==.Catnips:BAABLgAECn8cAAILAAgJRxjZKACfAQALAAgJRxjZKACfAQAAAA==.Catpow:BAAALgAECgkJAgAAAA==.',
Ch='Chanaranach:BAAALgAECgYJCgAAAA==.Cheelo:BAAALgAECgYJCwAAAA==.Chknnugget:BAAALgAECgMJBQAAAA==.Chowpally:BAABLgAECn8UAAIMAAcJbh2iBwBAAgAMAAcJbh2iBwBAAgAAAA==.Chromatic:BAAALgAECgYJEgAAAA==.',
Ci='Cindrethresh:BAAALgAECgEJAQAAAA==.',
Co='Coffeeblak:BAABLgAECn8XAAMBAAgJnhJDJgCmAQABAAcJIBNDJgCmAQAMAAUJFQ61PwDkAAAAAA==.Coldstorm:BAAALgAECgYJCgAAAA==.Compensating:BAAALgADCgYJBgAAAA==.Connor:BAAALgADCgcJBwAAAA==.Connsumption:BAAALgAECgYJCgAAAA==.Corrine:BAAALgADCgQJBwAAAA==.',
Cr='Crazybatt:BAAALgAECgQJBwAAAA==.Crypt:BAAALgAECgYJCgAAAA==.',
Cu='Cuckchairpov:BAACLgAFFH8HAAMNAAMJLhJLGADYAAANAAMJmQ5LGADYAAABAAIJQg1xDACgAAAuAAQKfycAAwEACAmDHWQKANICAAEACAl4HWQKANICAA0ACAnJEMUMAL4BAAAA.',
Cy='Cynderleena:BAAALgAECgQJBAAAAA==.Cynyia:BAABLgAECn8oAAIOAAgJrRLEGwC5AQAOAAgJrRLEGwC5AQAAAA==.',
Cz='Czk:BAAALgADCgQJBQABLgAECggJFwABAJ4SAA==.',
Da='Daddyelessar:BAAALgAECgMJBAAAAA==.Dafattyup:BAABLgAECn8aAAIPAAYJlRwDNgBTAQAPAAYJlRwDNgBTAQAAAA==.Dagon:BAAALgAECgMJAwAAAA==.Dakotarain:BAAALgADCgIJAgAAAA==.Dalerontwo:BAAALgADCgEJAQAAAA==.Darruin:BAAALgAECgUJCQABLgAFFAUJEAAQAHMfAA==.Dayrun:BAAALgAECgUJCgAAAA==.',
De='Deadicee:BAAALgADCgEJAQAAAA==.Deathturtle:BAABLgAECn8ZAAIRAAYJohIDXADxAAARAAYJohIDXADxAAAAAA==.Deavaos:BAAALgAECgMJAwAAAA==.Dedmartigan:BAAALgADCgUJBQAAAA==.Deeanndra:BAAALgAECgcJCgAAAA==.Deevz:BAAALgAECgIJAgAAAA==.Demiz:BAABLgAECn8eAAIHAAgJshBWHwBqAQAHAAgJshBWHwBqAQAAAA==.Deredris:BAAALgAECgQJBAABLgAECgYJCgADAAAAAA==.Dertka:BAAALgAECgYJCAAAAA==.',
Di='Discodruid:BAAALgAECgQJEQAAAA==.Dishsoap:BAAALgAECgMJAwABLgAFFAQJCQAFALwQAA==.Dixie:BAAALgAECgEJAQAAAA==.',
Dj='Djall:BAAALgAECgUJBQAAAA==.',
Do='Domw:BAAALgAECgYJBgABLgAECgcJGwANAMsmAA==.Donham:BAACLgAFFH8OAAMRAAUJRxzqEwBSAQARAAQJRxzqEwBSAQASAAEJAAA0EwBZAAAuAAQKfx0AAhEACAnLHzgeAMsCABEACAnLHzgeAMsCAAAA.Dorkimedes:BAAALgAECgQJCQAAAA==.Dottie:BAABLgAECn8oAAMPAAgJJhOQHgC9AQAPAAgJ2xGQHgC9AQAJAAcJJQ84FwCQAQAAAA==.',
Dr='Draelesh:BAABLgAECn8VAAITAAcJWQ98FQBWAQATAAcJWQ98FQBWAQAAAA==.Draenk:BAAALgADCgUJBQAAAA==.Dragún:BAAALgAECgYJCwAAAA==.Drakari:BAAALgADCgYJBgAAAA==.Drewit:BAAALgAECgYJEQAAAA==.',
Du='Ducan:BAAALgADCgQJBwAAAA==.Duskmane:BAAALgAECgIJAgAAAA==.',
Dw='Dwadler:BAAALgAECgQJDQAAAA==.',
Dy='Dyrkonian:BAAALgAECgMJAwAAAA==.',
Ei='Eireann:BAAALgADCgcJCQAAAA==.',
El='Elerrak:BAAALgAECgEJAQABLgAFFAYJDgAUANkcAA==.Elindalia:BAAALgAECgMJAwAAAA==.',
Em='Emberash:BAAALgADCgYJBgAAAA==.Embre:BAAALgAECgUJCgAAAA==.Emorri:BAAALgAECgYJBgAAAA==.Empyrea:BAAALgAECgQJBQAAAA==.',
Er='Eraina:BAAALgADCgIJAgAAAA==.Ericles:BAABLgAECn8ZAAMVAAcJ5h3CBADrAQAVAAcJ5h3CBADrAQAFAAIJlAVjlwBkAAAAAA==.Erys:BAAALgAECgIJAwAAAA==.Erébus:BAABLgAECn8iAAIWAAkJ7hi+BwBeAgAWAAkJ7hi+BwBeAgAAAA==.',
Ev='Ev:BAAALgAECgQJBAAAAA==.Evlpotato:BAABLgAECn8gAAQIAAgJbR0cEQCAAQAIAAYJ8B4cEQCAAQAXAAcJNBq/EwBbAQAYAAEJlAdLfwAzAAAAAA==.Evojak:BAAALgAECgUJCAAAAA==.',
Fa='Faevelia:BAAALgADCgMJAwAAAA==.Fairaday:BAABLgAECn8dAAIOAAgJXwchOAAxAQAOAAgJXwchOAAxAQAAAA==.Fanshen:BAAALgAECgEJAQAAAA==.Fauchi:BAAALgADCgEJAQAAAA==.Faxqueenmage:BAAALgAECgYJCgAAAA==.',
Fe='Felador:BAAALgADCgUJCAAAAA==.Feldo:BAAALgAECgYJBgAAAA==.Felmès:BAAALgADCgYJBgABLgAECggJFgACAOYFAA==.Fennec:BAAALgAECgUJDAAAAA==.Feralarak:BAAALgAECgQJCAABLgAFFAYJDgAUANkcAA==.',
Fi='Firebrandd:BAACLgAFFH8QAAMQAAUJcx+LAAB/AQAQAAUJcx+LAAB/AQAZAAEJ5A72IABOAAAuAAQKfzIAAxAACAk3JmACAA8DABAACAkrImACAA8DABkACAnQJDQDAKICAAAA.Fizehbubbleh:BAEALgADCgYJBgABLgAECggJGwAGANsaAA==.Fizehtotems:BAEBLgAECn8bAAIGAAgJ2xqzFAByAQAGAAgJ2xqzFAByAQAAAA==.',
Fl='Fleshoracle:BAAALgAECgQJBAAAAA==.Fluctuates:BAAALgAECgQJCAAAAA==.',
Fo='Foron:BAAALgAECgIJAgAAAA==.',
Fr='Frankkastle:BAAALgAECgYJDQAAAA==.Frazelia:BAAALgADCgkJDgABLgAECgYJEQADAAAAAA==.Fribble:BAAALgAECgUJCAABLgAECgYJEwADAAAAAA==.Froggierlynx:BAAALgAECgcJEgAAAA==.Froznfate:BAABLgAECn8VAAIaAAYJHCalAwAlAgAaAAYJHCalAwAlAgAAAA==.Fryes:BAAALgAECgcJCAAAAA==.',
Fu='Fuzziebutt:BAAALgADCgEJAQAAAA==.',
Fy='Fyrelady:BAAALgADCgQJBgABLgAECgEJAQADAAAAAA==.Fyrestone:BAAALgAECgEJAQAAAA==.',
['Fæ']='Fæder:BAAALgADCgYJBgAAAA==.',
Ga='Gabarnak:BAAALgADCgIJAgAAAA==.Galencharred:BAAALgAECgUJDAAAAA==.Garagon:BAABLgAECn8VAAIbAAcJVBKGCQCGAQAbAAcJVBKGCQCGAQAAAA==.Gauss:BAAALgAECgYJEwAAAA==.Gaîîa:BAABLgAECn8cAAIOAAgJBBqxMADtAQAOAAgJBBqxMADtAQAAAA==.',
Ge='Gerva:BAAALgAECgcJEgAAAA==.',
Gh='Ghlain:BAAALgAECgMJAwAAAA==.Ghorfindor:BAAALgAECgYJDwAAAA==.Ghostlybrew:BAACLgAFFH8TAAINAAUJAx3lBACHAQANAAUJAx3lBACHAQAuAAQKfxYAAg0ACAmoH98TAHECAA0ACAmoH98TAHECAAAA.',
Gi='Gigastorm:BAAALgADCgIJAQAAAA==.Gilas:BAAALgAECgUJDAAAAA==.',
Gl='Glaivemstake:BAAALgADCgcJBwAAAA==.',
Gn='Gnik:BAAALgAECgYJCwAAAA==.',
Gr='Graahak:BAAALgADCgMJAwAAAA==.Graydenton:BAAALgAECgkJCQABLgAECggJBgADAAAAAA==.Gruuven:BAAALgADCgUJBwAAAA==.',
Gu='Gutmtmon:BAAALgAECgMJCQAAAA==.',
Gw='Gwenivive:BAABLgAECn8VAAIOAAcJzhUTKQByAQAOAAcJzhUTKQByAQAAAA==.',
['Gí']='Gízmo:BAAALgADCgUJBQAAAA==.',
Ha='Haenus:BAABLgAECn8dAAIWAAgJfhO9KABEAQAWAAgJfhO9KABEAQAAAA==.Harrynear:BAAALgADCgMJAwABLgAECgQJCgADAAAAAA==.Haunt:BAAALgAECgQJBAAAAA==.Havark:BAAALgAECgMJAwAAAA==.',
He='Healbilly:BAAALgADCgEJAQAAAA==.Hellzknîght:BAAALgAECgYJDwAAAA==.',
Ho='Holek:BAAALgAECgYJCwAAAA==.Holgo:BAAALgAECgUJCAAAAA==.Holgy:BAACLgAFFH8TAAIcAAUJlh9wAQBxAQAcAAUJlh9wAQBxAQAuAAQKfyMAAhwACQlSI00BAEkDABwACQlSI00BAEkDAAAA.Holybeard:BAABLgAECn8hAAILAAgJ8hicFwD/AQALAAgJ8hicFwD/AQAAAA==.Hooks:BAAALgADCggJEgAAAA==.',
Hu='Hunterturtle:BAAALgADCgUJBQAAAA==.',
Ic='Icia:BAAALgAECgEJAQAAAA==.',
Id='Idontmiss:BAAALgAECgIJBgAAAA==.',
Il='Ilickboody:BAAALgADCgQJBAAAAA==.Illustra:BAAALgAECgYJCgABLgAECggJFgACAOYFAA==.',
Im='Imcaldo:BAAALgADCgYJBgAAAA==.Imcaldoo:BAAALgADCgUJCgAAAA==.',
In='Interrupt:BAAALgAECgUJDQAAAA==.',
Ir='Irox:BAAALgADCgMJAwAAAA==.',
Is='Isaic:BAAALgADCgIJAgAAAA==.Iseila:BAAALgAECgkJEAAAAA==.Isevio:BAAALgAECgMJBwAAAA==.',
It='Ithorus:BAAALgAECgUJBwAAAA==.',
Ja='Jaadb:BAAALgADCgMJBAAAAA==.Jaadd:BAAALgAECgIJAgAAAA==.Jaadi:BAAALgAECgIJAwAAAA==.Jaata:BAAALgADCgcJEAAAAA==.Jamien:BAABLgAECn8aAAMLAAcJFhvBGQDwAQALAAcJFhvBGQDwAQAKAAUJHQEedwCdAAAAAA==.Jasnos:BAAALgAECgUJDAAAAA==.',
Jd='Jdk:BAAALgAECgUJBwAAAA==.',
Je='Jelf:BAAALgADCgcJBwAAAA==.Jenzing:BAABLgAECn8VAAMPAAgJqh0LKwBjAgAPAAcJqh0LKwBjAgAdAAEJAACtIwBjAAAAAA==.Jessemyn:BAAALgADCgUJBAAAAA==.',
Jh='Jholy:BAAALgADCggJCAAAAA==.',
Jo='Jobokenhones:BAABLgAECn8XAAIWAAgJYhjuHwBzAQAWAAgJYhjuHwBzAQAAAA==.Johadgan:BAAALgADCgEJAQAAAA==.',
Jp='Jproudmore:BAAALgADCgUJBQABLgADCgYJCwADAAAAAA==.',
Js='Jsberg:BAAALgAECgYJDwAAAA==.',
Ka='Kaathe:BAABLgAECn8hAAMCAAYJGx7khADHAQACAAYJGx7khADHAQAeAAEJjhqZDwA4AAAAAA==.Kadance:BAAALgAECgIJAwAAAA==.Kaidiis:BAABLgAECn8UAAILAAYJ8BBpRwAzAQALAAYJ8BBpRwAzAQAAAA==.Kaido:BAAALgAECgEJAQAAAA==.Kalder:BAAALgADCgcJBwAAAA==.Karbonn:BAAALgAECgIJAwAAAA==.Kay:BAAALgAECgcJBwAAAA==.Kazeraz:BAAALgADCgEJAQAAAA==.',
Ke='Kegbreaker:BAABLgAECn8dAAIYAAgJHAe9GQA7AQAYAAgJHAe9GQA7AQAAAA==.',
Kh='Khanas:BAAALgAECgIJAwAAAA==.Kheru:BAAALgADCgkJDAAAAA==.Khoan:BAAALgAECgYJCgAAAA==.',
Ki='Kimbustible:BAABLgAECn8tAAICAAgJJiIPCAC5AgACAAgJJiIPCAC5AgAAAA==.Kimchi:BAAALgAECgcJDAABLgAECggJLQACACYiAA==.',
Kn='Knockknocko:BAAALgAECgQJCQAAAA==.',
Ko='Kobir:BAAALgADCgEJAQAAAA==.Komodostyle:BAABLgAECn8UAAMbAAcJvQYYDgAfAQAbAAcJvQYYDgAfAQAQAAIJWw6vNQBoAAAAAA==.Koobideh:BAAALgADCgEJAQAAAA==.',
Kr='Kriddler:BAAALgADCgQJBAAAAA==.Krisarugala:BAAALgAECgcJEwAAAA==.',
Ku='Kujoluvsmilf:BAAALgAECgYJBgAAAA==.Kunuku:BAAALgADCgUJBQAAAA==.Kurash:BAAALgADCgcJBwAAAA==.Kurion:BAAALgAECgkJBAAAAA==.Kurogami:BAAALgADCgUJBQAAAA==.',
Ky='Kylesxmom:BAABLgAECn8qAAMRAAgJLyBKCgB+AgARAAgJRB9KCgB+AgASAAcJiRWtIQA1AQAAAA==.Kymal:BAABLgAECn8nAAIWAAgJTBfREwDLAQAWAAgJTBfREwDLAQAAAA==.Kymbria:BAAALgADCgUJCAAAAA==.Kymora:BAAALgADCgcJBwAAAA==.Kyndrissa:BAAALgADCgUJBQAAAA==.',
['Kë']='Këy:BAABLgAECn8jAAIRAAgJoxqOLACGAgARAAgJoxqOLACGAgAAAA==.',
La='Latrice:BAACLgAFFH8VAAICAAYJHhyIBQDXAQACAAYJHhyIBQDXAQAuAAQKfyAAAwIACQkAI9wJAHYDAAIACQkAI9wJAHYDAB8AAQltGNsYAFEAAAAA.Lavynder:BAABLgAECn8XAAIWAAgJ6xUQWgCTAQAWAAgJ6xUQWgCTAQAAAA==.Laërtes:BAAALgAECgMJAwAAAA==.',
Le='Leiamirage:BAAALgAECgUJBgAAAA==.Leviscus:BAAALgAECgEJAQAAAA==.',
Li='Lifetap:BAAALgADCgMJAwAAAA==.Lightbàne:BAAALgAECgcJCwAAAA==.Lightningrod:BAAALgAECgYJBgAAAA==.Lildruidz:BAAALgAECgcJDQAAAA==.Lillivarak:BAAALgAECgUJCQAAAA==.Lithedra:BAAALgADCgcJDwAAAA==.',
Lu='Lucavi:BAAALgAECgMJAwAAAA==.Lucyvar:BAAALgADCgEJAQAAAA==.Luke:BAAALgADCgUJBwAAAA==.Luma:BAAALgAECgMJBQAAAA==.Luther:BAABLgAECn8XAAINAAkJNw9VJQDYAQANAAkJNw9VJQDYAQAAAA==.',
Ly='Lyla:BAAALgADCgQJBgAAAA==.',
Ma='Magnux:BAAALgADCgYJBgAAAA==.Malríus:BAAALgAECgQJEQAAAA==.Manales:BAAALgAECgcJBgAAAA==.Marhukai:BAABLgAECn8WAAILAAgJ5Bm6FAAVAgALAAgJ5Bm6FAAVAgAAAA==.Marotal:BAAALgAECgUJEQAAAA==.Martysparty:BAABLgAECn8ZAAIaAAYJhx5cDAACAgAaAAYJhx5cDAACAgAAAA==.Mavaena:BAAALgAECgIJAgAAAA==.Mavrane:BAAALgADCgEJAgAAAA==.',
Me='Meashakegs:BAAALgAECggJDAAAAA==.Mechaboomer:BAABLgAECn8UAAIOAAcJ/xcAHQCxAQAOAAcJ/xcAHQCxAQAAAA==.Megafire:BAAALgADCggJCwAAAA==.Melcanthet:BAAALgADCggJCAAAAA==.Mellowrock:BAAALgAECgUJBgABLgAECgYJBQADAAAAAA==.',
Mi='Mickhaggis:BAAALgADCgIJAgAAAA==.Micktarogar:BAAALgAECgcJEwAAAA==.Mickwutang:BAAALgAECgYJCwAAAA==.Miklaga:BAAALgAECgEJAgAAAA==.Milince:BAAALgADCgMJAgAAAA==.Minikloon:BAAALgAECgYJDgAAAA==.Minphoria:BAAALgADCgQJBgAAAA==.Missylock:BAAALgADCgYJBgAAAA==.Mistilinn:BAAALgAECgYJEQAAAA==.Miyri:BAAALgADCgYJBgABLgAECgQJBwADAAAAAA==.',
Mo='Mollyporph:BAAALgAECgEJAQAAAA==.Monoco:BAAALgAECgQJBwAAAA==.Moopandax:BAACLgAFFH8JAAITAAMJsxFADgD8AAATAAMJsxFADgD8AAAuAAQKfyIAAhMACQnrHUoFAEoDABMACQnrHUoFAEoDAAEuAAUUBQkLABMAYBUA.Mortrum:BAAALgADCgQJBAAAAA==.Moxestime:BAAALgAECgEJAgAAAA==.Moxsdeaths:BAAALgADCgcJBwAAAA==.',
Mu='Mushaboom:BAAALgAECgIJAwAAAA==.Muzzler:BAABLgAECn8jAAICAAgJQR7DHQD5AQACAAgJQR7DHQD5AQAAAA==.',
My='Myeyes:BAAALgAECgEJAQAAAA==.Mylinkah:BAAALgADCgQJBAAAAA==.Mynamefizz:BAEALgAECgcJBwABLgAECggJGwAGANsaAA==.Myotonic:BAAALgADCgQJBAAAAA==.Mythlok:BAAALgAECgMJAwAAAA==.Mythreiel:BAAALgAECgQJBQAAAA==.Mythykal:BAAALgAECgIJAgAAAA==.',
Na='Nadis:BAEALgAECgIJAwAAAA==.Narcessa:BAAALgADCgQJBAAAAA==.Nawk:BAAALgAECgEJAQAAAA==.',
Ne='Nennerb:BAAALgADCgQJBAAAAA==.',
Ni='Nicola:BAAALgAECgQJBQAAAA==.Nightxwish:BAAALgAECgUJDAAAAA==.Niranye:BAAALgADCgEJAQAAAA==.',
No='Noisemarine:BAAALgAECgIJAwAAAA==.Nokk:BAAALgADCgEJAQAAAA==.Nokkco:BAAALgAECgEJAQAAAA==.Northspirit:BAAALgAECgMJBgAAAA==.',
Nu='Nuit:BAAALgADCgUJBQABLgAECgYJCwADAAAAAA==.',
Ny='Nyarlothep:BAAALgADCggJGgAAAA==.',
Oa='Oakenshièld:BAAALgAECgQJBAAAAA==.',
Od='Odindh:BAAALgAECgYJCgAAAA==.Odins:BAAALgADCgEJAQABLgAECgYJCgADAAAAAA==.',
Oh='Ohwhelp:BAAALgAFFAIJAgABLgAFFAUJEQATAI4mAA==.Ohyikers:BAACLgAFFH8RAAITAAUJjiaGAQDPAQATAAUJjiaGAQDPAQAuAAQKfyUAAhMACAmxJS0GADYDABMACAmxJS0GADYDAAAA.',
Ok='Oken:BAAALgADCgUJBQAAAA==.',
Om='Om:BAAALgADCgcJCQAAAA==.',
Pa='Pallek:BAAALgADCgQJBAABLgAECgYJCwADAAAAAA==.Palli:BAAALgAECgUJEAAAAA==.Paogao:BAAALgAECgIJAwAAAA==.Parry:BAAALgADCgQJBAAAAA==.Pasghetti:BAAALgADCgMJAwAAAA==.Pasta:BAABLgAECn8gAAIgAAcJVBskDACmAQAgAAcJVBskDACmAQAAAA==.',
Pe='Pewpewbite:BAAALgAECgIJAwAAAA==.',
Ph='Phantomarrow:BAACLgAFFH8LAAQhAAUJ2wvICQDgAAAhAAUJHgvICQDgAAAiAAMJIwXoCwDaAAAOAAEJzQFvQABCAAAuAAQKfxUABA4ABgk8IAFOAH8BAA4ABgkbHgFOAH8BACEABQmzGXJCAE0BACIAAQkAAAg0AAAAAAAA.Phatcow:BAABLgAECn8mAAMHAAgJ4Rl9FwBaAgAHAAgJ4Rl9FwBaAgAUAAcJcBKbBgCcAQAAAA==.Phoseidon:BAAALgADCgcJCQAAAA==.Phude:BAABLgAECn8qAAILAAgJgxkoGwDnAQALAAgJgxkoGwDnAQAAAA==.',
Pi='Pinch:BAAALgAECgMJAwAAAA==.',
Po='Pohl:BAAALgAECgYJBgAAAA==.Poohynok:BAABLgAECn8jAAICAAgJIyQfDQB5AgACAAgJIyQfDQB5AgAAAA==.',
Pu='Pukefeast:BAAALgAECgYJCAAAAA==.',
Py='Pyramys:BAACLgAFFH8MAAIgAAQJYBybBQBrAQAgAAQJYBybBQBrAQAuAAQKfyEAAiAACAm3IAARAJoCACAACAm3IAARAJoCAAAA.',
['Pè']='Pèrce:BAAALgAECgIJAwAAAA==.',
Qu='Quepaoka:BAAALgADCgIJAgAAAA==.',
Ra='Raklem:BAAALgAECgMJAwABLgAECgYJCgADAAAAAA==.Ramble:BAAALgADCgQJBAABLgAECgQJBgADAAAAAA==.Ramstein:BAAALgADCgkJDgAAAA==.Raphînîty:BAAALgADCgMJBQAAAA==.Rashari:BAAALgADCgYJCAAAAA==.Razgrizz:BAAALgAECgEJAQAAAA==.',
Re='Retro:BAAALgAECgIJBAAAAA==.Revelatus:BAAALgAECgQJBgAAAA==.Reythanas:BAAALgAECgQJBwAAAA==.Rezzin:BAAALgAECgEJAQAAAA==.',
Ri='Rileyann:BAAALgAECgYJEgAAAA==.',
Ro='Roozer:BAAALgADCgkJHQAAAA==.',
['Rå']='Råphå:BAAALgAECgMJBAAAAA==.',
Sa='Saelyria:BAAALgAECgQJBwAAAA==.Saga:BAAALgADCgUJBQAAAA==.Sagethepally:BAAALgAECgcJAgAAAA==.Saintfail:BAAALgAECgcJCAABLgAECgcJFAAMAG4dAA==.Salero:BAAALgADCgIJAQAAAA==.Sandiera:BAABLgAECn8WAAMCAAgJ5gVAqgCGAQACAAgJ5gVAqgCGAQAfAAMJPAOnFwBcAAAAAA==.Saxtön:BAAALgADCggJEwAAAA==.',
Sc='Scoreboard:BAACLgAFFH8QAAIjAAYJbR8VAAD9AQAjAAYJbR8VAAD9AQAuAAQKfyEAAyMACQkgJg0AAOsDACMACQkgJg0AAOsDACAAAQnwFJRaAE8AAAAA.Scorn:BAAALgAECgQJBwAAAA==.Scottx:BAAALgAECgQJCAAAAA==.',
Se='Sebas:BAAALgAECgEJAQAAAA==.Sedric:BAAALgAECgYJCAAAAA==.Selkz:BAAALgAECgcJDQAAAA==.Selsonblue:BAAALgADCgYJEwABLgAECgEJAQADAAAAAA==.Sesskaa:BAAALgAECgQJBgAAAA==.',
Sh='Shadowcursed:BAAALgADCgcJCgAAAA==.Shadowstorm:BAAALgADCgQJBAAAAA==.Shadøws:BAAALgAECgEJAQAAAA==.Shathos:BAAALgADCgEJAQAAAA==.Sheebá:BAAALgADCgYJCwAAAA==.Shishkbob:BAAALgADCgkJCQAAAA==.Shivax:BAAALgAECgQJCQAAAA==.Shünúkh:BAAALgADCgYJBgAAAA==.',
Si='Signal:BAAALgAECgEJAQAAAA==.Sinogad:BAAALgAECggJCgAAAA==.Sinol:BAAALgAECgYJDwABLgAECggJCgADAAAAAA==.Sioux:BAAALgADCgEJAQAAAA==.',
Sk='Skaro:BAAALgAECgIJAwAAAA==.Skyborn:BAAALgAECgIJAwAAAA==.',
Sl='Slamahoochee:BAAALgAECgQJBAAAAA==.Slay:BAABLgAECn8fAAMTAAcJoh+7CQD0AQATAAcJcx+7CQD0AQAkAAYJZBuNEwB4AQAAAA==.',
Sm='Smokedademon:BAAALgAECgMJBQAAAA==.Smokiebear:BAAALgAECgIJAwAAAA==.Smunkie:BAABLgAECn8bAAINAAcJyyaHBgA0AgANAAcJyyaHBgA0AgAAAA==.',
Sn='Snickeers:BAAALgAECgEJAQAAAA==.',
So='Somogyi:BAAALgADCgIJAgAAAA==.',
Sp='Spopovich:BAAALgADCgIJAgABLgAECgMJAwADAAAAAA==.',
St='Stinko:BAAALgADCgEJAgAAAA==.Stitchlock:BAAALgAECgIJAgAAAA==.Stitchofevil:BAABLgAECn8WAAQdAAcJuBoEBgACAgAdAAYJUB8EBgACAgAPAAQJmQnOfwB+AAAJAAIJtQ8aYQBMAAAAAA==.Stonedshaman:BAAALgADCgYJBgABLgAECgIJAgADAAAAAA==.Stormhands:BAAALgAECgYJDwAAAA==.Stormhugger:BAAALgAECgUJBwAAAA==.Stoutnholy:BAAALgAECgIJAgAAAA==.Stratichnut:BAABLgAECn8VAAIEAAcJzQ1fKABGAQAEAAcJzQ1fKABGAQAAAA==.Stromar:BAAALgADCgcJDAAAAA==.Stwampadin:BAAALgAECggJEwAAAA==.Stwevoker:BAAALgAECgMJAwABLgAECggJEwADAAAAAA==.Stwonkfu:BAAALgAECggJCAABLgAECggJEwADAAAAAA==.',
Su='Sumire:BAAALgADCggJDgABLgAECgYJCgADAAAAAA==.',
Sv='Sveny:BAAALgAECgEJAQAAAA==.',
Sw='Swampert:BAACLgAFFH8JAAIFAAQJvBDKCQBHAQAFAAQJvBDKCQBHAQAuAAQKfx4AAgUACQlTH9UMAPACAAUACQlTH9UMAPACAAAA.Swamperting:BAAALgAECgYJCgABLgAFFAQJCQAFALwQAA==.Swaye:BAABLgAECn8gAAIIAAgJDhGNDgCeAQAIAAgJDhGNDgCeAQAAAA==.Sweetfox:BAAALgADCgMJAwAAAA==.Switched:BAAALgADCgcJBwABLgAECgcJGwANAMsmAA==.Swizzle:BAAALgAECgQJBAAAAA==.',
Sy='Syllvanas:BAAALgAECgQJBQAAAA==.Sythia:BAAALgAECgEJAQABLgAFFAMJAwADAAAAAA==.',
Ta='Taltost:BAAALgAECgUJDAAAAA==.Tantrik:BAAALgADCgEJAQAAAA==.Tartin:BAAALgAECgMJAwAAAA==.Tarv:BAAALgADCgMJAQAAAA==.Tashamirage:BAAALgAECgMJBAAAAA==.Tauriel:BAAALgADCgIJAgAAAA==.',
Te='Teex:BAAALgADCgYJBwAAAA==.Teksuo:BAABLgAECn8qAAIBAAgJUx0xBgAsAgABAAgJUx0xBgAsAgAAAA==.Telamontay:BAAALgADCgcJEgAAAA==.Telferas:BAAALgAECgYJEQABLgAFFAUJEAAQAHMfAA==.Tenithon:BAABLgAECn8iAAIKAAkJ2yB+BQAUAwAKAAkJ2yB+BQAUAwAAAA==.Tenshenzen:BAAALgAECgQJBAAAAA==.',
Th='Therandis:BAAALgADCgUJBQAAAA==.Thetombo:BAAALgAECgIJAgAAAA==.Thierry:BAAALgADCgUJBQAAAA==.Thierrye:BAABLgAECn8VAAIWAAYJBxv7MgAXAQAWAAYJBxv7MgAXAQAAAA==.Tholaren:BAABLgAECn8UAAMOAAcJfAwfKgBtAQAOAAcJfAwfKgBtAQAhAAUJSQfMEQC0AAAAAA==.Threed:BAAALgAECgYJCwAAAA==.Threewar:BAAALgAECgIJAgABLgAECgYJCwADAAAAAA==.Thrissa:BAAALgAECgIJAwAAAA==.',
To='Torrque:BAAALgADCgkJCQABLgADCgYJCwADAAAAAA==.Totemlicker:BAAALgAECgEJAQAAAA==.',
Tr='Trangon:BAABLgAECn8VAAILAAYJcwodXwD3AAALAAYJcwodXwD3AAAAAA==.Traveler:BAAALgADCgEJAQAAAA==.Trillion:BAAALgADCgMJAwAAAA==.',
Tu='Tunzoffun:BAAALgAECgIJAwAAAA==.',
Un='Underbyte:BAAALgADCggJDwAAAA==.Unknownname:BAAALgADCgMJAwAAAA==.',
Ur='Urholiness:BAAALgADCgkJDwAAAA==.',
Va='Vaeleia:BAAALgAECgQJBgAAAA==.Vahnkar:BAAALgADCgQJBwAAAA==.Valentinu:BAAALgADCgcJDwAAAA==.Vaneshk:BAAALgADCgEJAQAAAA==.Varchemical:BAAALgAECgcJBwAAAA==.Varithal:BAABLgAECn8oAAIbAAgJ8x8zAgCnAgAbAAgJ8x8zAgCnAgABLgABCgYJCQADAAAAAA==.Varri:BAAALgAECgMJBQAAAA==.Vastectomy:BAAALgAECgYJBwAAAA==.',
Ve='Velwing:BAAALgAECgUJBwAAAA==.Venawyn:BAAALgAECgUJDQAAAA==.Verakhaa:BAAALgAECgQJBAAAAA==.',
Vi='Vibepriest:BAAALgADCgEJAQAAAA==.Vindfaramaðr:BAABLgAECn8VAAINAAYJtAZmKwC9AAANAAYJtAZmKwC9AAAAAA==.Vixin:BAAALgAECgQJBgAAAA==.',
Vo='Voidsaack:BAAALgADCgkJFgAAAA==.Volfguar:BAAALgAECgQJAQAAAA==.Vortan:BAAALgAECgcJCwAAAA==.',
Vr='Vreya:BAAALgADCggJDQABLgAECgEJAQADAAAAAA==.',
Vy='Vynthus:BAAALgAECgQJBAAAAA==.',
['Vä']='Värys:BAAALgAECgEJAQAAAA==.',
Wa='Warhundin:BAEALgAECgUJBQABLgAECggJGgAlAHUQAA==.Warwan:BAAALgADCgIJAgAAAA==.Wazzdh:BAAALgADCgQJBAAAAA==.Wazzdot:BAAALgAECgQJBAAAAA==.Wazzhunnah:BAABLgAECn8ZAAMiAAgJxRF6CADcAQAiAAgJxRF6CADcAQAhAAQJZAlLZQCqAAAAAA==.',
We='Werg:BAAALgAECggJCQABLgAFFAEJAQADAAAAAA==.',
Wh='Whatmyname:BAABLgAECn8WAAIcAAcJ6AgAEAC6AAAcAAcJ6AgAEAC6AAAAAA==.Whispp:BAAALgAECgYJCAAAAA==.',
Wo='Wonsok:BAAALgAECgYJBwAAAA==.',
Wy='Wyvoker:BAABLgAECn8WAAIbAAcJtRgjBgDrAQAbAAcJtRgjBgDrAQABLgAECgkJBAADAAAAAA==.',
['Wì']='Wìllow:BAAALgADCgIJAgAAAA==.',
['Wÿ']='Wÿm:BAAALgAECgkJBAAAAA==.',
Xe='Xenorion:BAAALgAECgMJAwAAAA==.Xephora:BAAALgAECgEJBAAAAA==.',
Xu='Xuny:BAAALgAECgEJAgAAAA==.',
Yo='Yordi:BAAALgAECgUJBQAAAA==.',
Yu='Yuzuriha:BAABLgAECn8pAAIOAAgJXSMbCAAPAwAOAAgJXSMbCAAPAwAAAA==.',
Za='Zamaze:BAABLgAECn8dAAImAAgJdCD1BAAUAgAmAAgJdCD1BAAUAgAAAA==.Zannah:BAAALgAECgMJAwAAAA==.Zant:BAAALgAECgIJAQAAAA==.',
Ze='Zeekielle:BAEBLgAECn8aAAIlAAgJdRDiDABuAQAlAAgJdRDiDABuAQAAAA==.Zenius:BAAALgAECgMJAwAAAA==.Zerithrielle:BAABLgAECn8cAAIlAAcJyRRNDgBWAQAlAAcJyRRNDgBWAQAAAA==.',
Zi='Zippii:BAAALgAECgYJBwAAAA==.Zipy:BAABLgAECn8VAAIYAAcJ+x9XBgBUAgAYAAcJ+x9XBgBUAgAAAA==.',
Zo='Zof:BAAALgAECgYJCwAAAA==.Zorathar:BAAALgADCgYJBgAAAA==.',
Zu='Zugtag:BAABLgAECn8dAAIRAAgJVh79DABeAgARAAgJVh79DABeAgAAAA==.',
Zy='Zyllo:BAAALgADCgkJIgAAAA==.',
['Zá']='Závier:BAAALgAECgUJCgAAAA==.',
['Äe']='Äemond:BAAALgADCgMJAwAAAA==.',
['Ål']='Ålïce:BAABLgAECn8qAAILAAgJmBaxGwDkAQALAAgJmBaxGwDkAQAAAA==.',
['Ëd']='Ëdward:BAAALgADCgcJCgABLgAECgMJAwADAAAAAA==.',
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
