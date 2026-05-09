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

local lookup = {'Priest-Holy','Priest-Shadow','Priest-Discipline','Mage-Frost','Unknown-Unknown','DemonHunter-Devourer','Shaman-Restoration','DemonHunter-Vengeance','DemonHunter-Havoc','Paladin-Retribution','Warrior-Fury','Warrior-Arms','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Holy','Druid-Guardian','Warlock-Demonology','Mage-Arcane','Monk-Windwalker','Warlock-Destruction','Warlock-Affliction','DeathKnight-Unholy','Druid-Balance','Rogue-Assassination','Druid-Restoration','Monk-Brewmaster','Druid-Feral','Warrior-Protection','Shaman-Elemental','Hunter-Survival','Evoker-Preservation','Evoker-Augmentation','Paladin-Protection','Shaman-Enhancement','Evoker-Devastation','Monk-Mistweaver',}
local provider = {region='US',realm='Suramar',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aassvik:BAABLgAECn8mAAIBAAgJCCCDBADLAgABAAgJCCCDBADLAgAAAA==.',
Ab='Absolute:BAAALgAECgEJAgAAAA==.',
Ac='Accident:BAAALgAECgEJAQAAAA==.Achievless:BAAALgAECgcJDAAAAA==.Achievsome:BAACLgAFFH8VAAQCAAUJ2B+kBQCEAQACAAUJ2B+kBQCEAQADAAQJFgnSCwAdAQABAAIJOglIHQBLAAAuAAQKfyUABAIACQn5ILkIADwCAAIACAn+ILkIADwCAAEAAwnjGY5TAOkAAAMAAQm8HhxOAFkAAAAA.',
Ad='Adava:BAAALgAECgYJEQABLgAFFAYJFQAEALshAA==.Adennoko:BAAALgADCgkJCQAAAA==.',
Ae='Aery:BAAALgADCgcJBwAAAA==.Aesomx:BAAALgAECgEJBgABLgAECgIJAwAFAAAAAA==.',
Ag='Agrajag:BAAALgADCgkJCQABLgAECgkJKgAGABwZAA==.',
Ai='Aiona:BAAALgAECgUJCgAAAA==.Aithea:BAAALgAECgQJBAAAAA==.',
Ak='Akagrats:BAAALgAECgYJDAAAAA==.Aknutiak:BAAALgAECgIJAgAAAA==.',
Al='Alabelina:BAAALgADCgUJBQAAAA==.Aldenwarlock:BAAALgAECgQJCgAAAA==.Alekhine:BAAALgADCgIJAgAAAA==.Alessandro:BAAALgAECgUJBQAAAA==.Alestar:BAAALgADCgYJBgABLgAECgYJFgAHAEkkAA==.Aliengrey:BAAALgAECgUJEAAAAA==.Allimore:BAAALgAECgQJBQAAAA==.Alonsusfaol:BAAALgADCgUJBgAAAA==.Alyx:BAAALgAECgEJAQAAAA==.',
Am='Amane:BAABLgAECn8bAAMIAAgJQRh4BQC2AQAIAAgJDBd4BQC2AQAJAAYJ/xXiFQA5AQAAAA==.American:BAAALgAECgUJCwAAAA==.Amulisha:BAAALgADCgkJIQAAAA==.Amytenchi:BAAALgADCgcJDQAAAA==.',
An='Angrystake:BAAALgADCgMJAwAAAA==.Annya:BAABLgAECn8bAAIBAAgJkRRPLACWAQABAAgJkRRPLACWAQAAAA==.Anowon:BAAALgADCgcJBwABLgAECgkJCwAFAAAAAA==.',
Ar='Arassaka:BAAALgAECgYJCQAAAA==.Archdragon:BAAALgAECgUJCAAAAA==.Archtrishop:BAAALgADCgkJCQAAAA==.Arcius:BAAALgAECgYJDQAAAA==.Aristae:BAAALgAECgEJAQABLgAECgYJHgAKAAwWAA==.Arkanis:BAABLgAECn8xAAILAAkJYx3VAwDKAgALAAkJYx3VAwDKAgAAAA==.Arlestia:BAAALgADCgEJAQAAAA==.Armament:BAABLgAECn8ZAAMMAAgJGBSrEwAfAQALAAcJkgxhRACSAQAMAAYJkRGrEwAfAQAAAA==.Arrolexancas:BAAALgAECgYJEQAAAA==.Arrows:BAAALgADCgQJBAAAAA==.Arturiouss:BAABLgAECn8cAAINAAgJ0RF3DwB7AQANAAgJ0RF3DwB7AQAAAA==.Arwenn:BAAALgAECgEJAQAAAA==.Arzuul:BAAALgAECgUJDQAAAA==.',
As='Ashlenna:BAAALgAECgQJBAAAAA==.',
At='Athira:BAAALgADCgUJCAAAAA==.',
Au='Audi:BAAALgAECgEJAQAAAA==.Auid:BAAALgADCgUJBQAAAA==.Aurafiora:BAABLgAECn8xAAMOAAgJqyD3EgCfAgAOAAgJqyD3EgCfAgAPAAIJjQxrdgBlAAAAAA==.Aurelio:BAABLgAECn8aAAIQAAYJZhy2LgDIAQAQAAYJZhy2LgDIAQAAAA==.Auther:BAAALgAECgEJAQAAAA==.',
Av='Avalancha:BAABLgAECn8jAAIRAAgJBBaUBwC7AQARAAgJBBaUBwC7AQAAAA==.Avangela:BAAALgAECgYJBQAAAA==.Avanish:BAAALgADCgEJAQABLgAECgQJBQAFAAAAAA==.Avinoch:BAABLgAECn8WAAIRAAYJNQsnGQCWAAARAAYJNQsnGQCWAAAAAA==.',
Aw='Awenyedd:BAAALgAECgMJBQAAAA==.',
Ax='Axon:BAAALgADCgcJBwAAAA==.',
Az='Azaliene:BAAALgAECgQJBAAAAA==.Azambregon:BAAALgADCgcJCwAAAA==.Azenroth:BAAALgAECgEJAQAAAA==.Azulhail:BAAALgAECgQJCAAAAA==.Azurhan:BAAALgADCgMJAwAAAA==.',
Ba='Bahadir:BAAALgADCgEJAQAAAA==.Bakimono:BAAALgAECgMJBQAAAA==.Balthizer:BAAALgAECgQJBAAAAA==.Banehellborn:BAAALgAECgIJAgAAAA==.Barloran:BAAALgADCgEJAQAAAA==.Bastoosebata:BAAALgAECgcJCwAAAA==.Bazzi:BAAALgAECgMJBAAAAA==.',
Be='Bearbud:BAAALgADCggJCAABLgAFFAUJEgASAIUhAA==.Beardicuss:BAAALgAECgQJCgAAAA==.Beastdrank:BAAALgAECgMJAwAAAA==.Beauxjingles:BAAALgAECgQJBQAAAA==.Beezlebumon:BAAALgAECggJEQAAAA==.Belakor:BAAALgADCgMJAwAAAA==.Beld:BAAALgADCgYJBgAAAA==.Bellcross:BAAALgAECgYJDQAAAA==.Bewater:BAAALgAECgQJBQAAAA==.',
Bh='Bhutcheeks:BAAALgAECgEJAQAAAA==.',
Bi='Birr:BAAALgADCgUJCAAAAA==.',
Bl='Bloomflow:BAAALgAECgYJDwAAAA==.',
Bo='Bobabear:BAAALgADCgMJAwAAAA==.Bonersimpsun:BAAALgAECgcJDwAAAA==.Boomclap:BAABLgAECn8fAAIHAAgJTRouFgABAgAHAAgJTRouFgABAgAAAA==.',
Bp='Bpbreezy:BAACLgAFFH8HAAIBAAMJ0h1sDQD7AAABAAMJ0h1sDQD7AAAuAAQKfy4AAwEACQn9In0CAEIDAAEACQn9In0CAEIDAAIAAQmED/hMAEAAAAAA.',
Br='Bracknor:BAABLgAECn8lAAIOAAkJChWnJwC0AQAOAAkJChWnJwC0AQAAAA==.Brandonb:BAABLgAECn82AAMEAAkJtCClBgAFAwAEAAkJtCClBgAFAwATAAEJNhbjHAA5AAAAAA==.Brandondh:BAABLgAECn8fAAIGAAcJvRosIgC7AQAGAAcJvRosIgC7AQAAAA==.Bredock:BAABLgAECn8aAAIKAAYJYxitTABfAQAKAAYJYxitTABfAQABLgAFFAQJDgAOAIkXAA==.Brickmitts:BAAALgADCgYJBwAAAA==.Brittlehorn:BAAALgADCgEJAQAAAA==.Brotem:BAAALgAECgcJEwAAAA==.Broth:BAAALgAECgQJCgAAAA==.',
Bu='Bullshamy:BAAALgADCgIJAgAAAA==.Bulwarkk:BAAALgAECgQJBAAAAA==.Bumblbeetuna:BAAALgADCgcJEQAAAA==.Bumperdemon:BAAALgAECgQJBgAAAA==.Burkisure:BAAALgADCgYJBgAAAA==.',
By='Bysokar:BAABLgAECn8cAAIUAAgJMxdmFABKAgAUAAgJMxdmFABKAgAAAA==.',
['Bü']='Büllshift:BAAALgADCgQJBAAAAA==.',
Ca='Cainfortea:BAAALgAECgEJAQAAAA==.Cakecity:BAABLgAECn8qAAMJAAgJhh9iBgBAAgAJAAgJCR9iBgBAAgAIAAcJlRdNBgCbAQAAAA==.Calikillaoi:BAAALgAECgUJBQAAAA==.Calimage:BAAALgADCgYJCwAAAA==.Calipal:BAAALgAECgYJEwAAAA==.Caskashah:BAAALgAECgEJAwAAAA==.Catalìna:BAAALgAECgQJBQABLgAFFAUJDgAHANwbAA==.Catalïna:BAAALgADCgUJBQABLgAFFAUJDgAHANwbAA==.Catälina:BAACLgAFFH8OAAIHAAUJ3Bt0BQB1AQAHAAUJ3Bt0BQB1AQAuAAQKfy8AAgcACAnTIm4KANQCAAcACAnTIm4KANQCAAAA.',
Ce='Celebrimbjor:BAAALgAECgEJAQAAAA==.Cerberusbone:BAAALgAECgEJAgAAAA==.',
Ch='Cheddthyr:BAAALgAECgQJBAAAAA==.Cherubim:BAAALgAECgEJAQAAAA==.Chrnobog:BAABLgAECn8kAAQVAAkJTBqaEQC/AQASAAgJoBunOAApAgAVAAYJpxaaEQC/AQAWAAQJNh1TDgBNAQABLgAFFAUJEgASAIUhAA==.',
Ci='Cinderlily:BAAALgAECgIJAgAAAA==.Cinderz:BAAALgADCgYJCAAAAA==.',
Cl='Classicoil:BAAALgADCgEJAQAAAA==.Clayprincess:BAAALgAECgMJAwABLgAECgcJEgAFAAAAAA==.',
Co='Cocoyibobo:BAAALgAECgQJBQAAAA==.Colty:BAAALgADCgkJFgAAAA==.Conflagrate:BAABLgAECn8iAAISAAkJ3SKFAwAYAwASAAkJ3SKFAwAYAwAAAA==.Coolbeamz:BAAALgAECgYJCAAAAA==.Corvik:BAAALgADCgEJAQAAAA==.',
Cp='Cptcrushingb:BAAALgAECgEJAgAAAA==.',
Cr='Crazyhamster:BAAALgAECgQJBAAAAA==.Crene:BAAALgADCgIJAgAAAA==.Crithappens:BAABLgAECn8pAAIEAAgJuRsyPACGAgAEAAgJuRsyPACGAgAAAA==.Criturrpants:BAAALgAECgcJCgAAAA==.',
Cu='Curadd:BAAALgADCgYJBgAAAA==.Cute:BAAALgADCgYJBwAAAA==.',
Cy='Cybellise:BAAALgADCgEJAgAAAA==.Cynnå:BAAALgAECggJEgAAAA==.Cyp:BAAALgAECgEJAQABLgAECgkJHgAXAG8VAA==.',
['Cü']='Cüpcake:BAAALgAECggJDgAAAA==.',
Da='Daikirí:BAABLgAECn8fAAIYAAYJHwapMQDKAAAYAAYJHwapMQDKAAAAAA==.Damienator:BAAALgAECgMJBwAAAA==.Dankiferus:BAAALgADCgcJBwAAAA==.Dannyy:BAAALgAECgQJBAAAAA==.Darren:BAAALgADCgYJBwAAAA==.Dawrk:BAAALgAECgQJBgAAAA==.',
De='Deadincide:BAABLgAECn8cAAIXAAgJZBmoHQAWAgAXAAgJZBmoHQAWAgAAAA==.Dearia:BAAALgADCgIJAQAAAA==.Decree:BAABLgAECn8XAAIKAAYJjRYGTQBeAQAKAAYJjRYGTQBeAQAAAA==.Delcid:BAAALgAECgQJBgABLgAECgcJDwAFAAAAAA==.Delik:BAABLgAECn8jAAIEAAgJzAkMWABlAQAEAAgJzAkMWABlAQAAAA==.Demonarch:BAAALgADCgUJCAAAAA==.Deneol:BAABLgAECn8XAAMCAAgJ2xZPDQD0AQACAAgJ2xZPDQD0AQADAAEJRgc9WQAwAAAAAA==.Desola:BAAALgADCgEJAQAAAA==.Destrogen:BAABLgAECn8aAAQSAAgJTxncOACCAQASAAcJKxTcOACCAQAWAAQJOR4wDgBPAQAVAAIJgg2KTQCFAAAAAA==.Destïny:BAACLgAFFH8RAAIXAAUJaxgTCwCxAQAXAAUJaxgTCwCxAQAuAAQKfxcAAhcACAluIKcwAHUCABcACAluIKcwAHUCAAAA.Desìre:BAABLgAECn8jAAIDAAgJ1xXqDQDyAQADAAgJ1xXqDQDyAQAAAA==.Devastator:BAAALgAECgIJBAAAAA==.Deàthgirls:BAAALgADCgUJBQABLgAECgkJNAAKAAYlAA==.',
Di='Dinonuggies:BAAALgAECgIJAwAAAA==.Diobrandia:BAAALgADCgMJAwAAAA==.Dirty:BAABLgAECn8rAAIEAAgJWyHIDwCdAgAEAAgJWyHIDwCdAgAAAA==.Discotheque:BAAALgAECgQJCAAAAA==.Disk:BAAALgAECgQJBgAAAA==.',
Dn='Dnice:BAAALgAECgEJAQAAAA==.',
Do='Doompalm:BAAALgAECgYJBgAAAA==.Doompulse:BAAALgADCgMJAwAAAA==.Doomshield:BAAALgAECgYJEAAAAA==.Doomshroud:BAAALgADCgMJAwABLgAECgcJFAAKAGIMAA==.Doomtrain:BAAALgADCgEJAQAAAA==.Dorati:BAAALgAECgUJCAAAAA==.',
Dr='Drackiechan:BAAALgAECgMJAwABLgAFFAMJBwABANIdAA==.Dracodeez:BAABLgAECn8qAAIZAAgJ0CIXAQCuAgAZAAgJ0CIXAQCuAgAAAA==.Droobid:BAABLgAECn8gAAIaAAkJGB45BQA6AwAaAAkJGB45BQA6AwAAAA==.Drovosh:BAEALgAECgIJAgABLgAFFAYJFgAbAK0XAA==.',
Dy='Dykenasty:BAABLgAECn8YAAIGAAcJ1B6kOAASAgAGAAcJ1B6kOAASAgAAAA==.Dyxx:BAAALgAECgEJAQAAAA==.',
Dz='Dzlightning:BAAALgAECgEJAQAAAA==.',
['Dò']='Dòóm:BAAALgADCgMJAwAAAA==.',
Ea='Earendur:BAAALgAECgUJDQAAAA==.',
Ec='Eciruma:BAAALgAECgEJAgAAAA==.',
Ei='Eiseth:BAAALgADCgUJBQAAAA==.',
El='Electronvolt:BAAALgADCgMJBAABLgAECggJHAAXAGQZAA==.Elemantus:BAAALgAECgEJAQAAAA==.Elemeesel:BAAALgADCggJCQAAAA==.Eltael:BAAALgAECgUJEAAAAA==.Elæna:BAAALgADCgkJCQAAAA==.',
Em='Emilianaluz:BAAALgAECgYJCAAAAA==.',
En='Endeavor:BAAALgAECgYJDAAAAA==.Enkie:BAAALgADCgEJAQABLgAECgYJFQAEANAYAA==.Enky:BAAALgAECgUJBQABLgAECgYJFQAEANAYAA==.Enyxia:BAAALgADCggJEAAAAA==.',
Ep='Epikhotti:BAAALgAECgMJBQAAAA==.',
Er='Eradion:BAAALgAECgEJBQAAAA==.Erisson:BAAALgAECgkJBAAAAA==.Erlaandã:BAAALgADCgYJBgAAAA==.',
Es='Eszran:BAABLgAECn8UAAIcAAYJiw7PDwAcAQAcAAYJiw7PDwAcAQAAAA==.',
Eu='Euthanized:BAAALgADCgIJAgAAAA==.',
Ev='Evelleda:BAAALgADCgIJAgAAAA==.Evendell:BAAALgADCgcJBwAAAA==.',
Fa='Falys:BAAALgADCgYJCQAAAA==.Fasani:BAAALgAECgQJBAAAAA==.',
Fe='Feels:BAAALgAECgEJBwAAAA==.Feixiao:BAAALgADCgIJBAAAAA==.Felbro:BAAALgAECgMJAwAAAA==.Felraiser:BAAALgADCgkJHgAAAA==.Fendalein:BAAALgADCgUJBQAAAA==.Fennar:BAAALgAECgYJDQAAAA==.Ferosha:BAABLgAECn8eAAMNAAgJHRk9DACwAQANAAcJohg9DACwAQAXAAYJYhVdTgBRAQABLgAECggJLAAbAK0bAA==.Fexxyr:BAAALgAECgQJBAABLgAFFAYJEwACAIYZAA==.',
Fi='Fidobedo:BAAALgADCgMJAwAAAA==.Firefly:BAAALgADCgEJAQAAAA==.Firstfear:BAAALgAECgMJBAAAAA==.Fisch:BAABLgAECn8jAAIdAAgJfiXJAQDkAgAdAAgJfiXJAQDkAgAAAA==.Fizzlepow:BAAALgADCgYJBgAAAA==.',
Fl='Flagrent:BAAALgAECgQJDQAAAA==.Flashico:BAAALgAECgYJDgAAAA==.Flemingo:BAAALgAECgIJAwAAAA==.Flemruk:BAAALgAECgcJDAAAAA==.Flemta:BAAALgAECggJBAAAAA==.Flemtaur:BAAALgAECgkJAgAAAA==.Flidd:BAABLgAECn8kAAIEAAgJzgh3UwBxAQAEAAgJzgh3UwBxAQAAAA==.Flipingtiska:BAAALgAECgIJAgAAAA==.Floret:BAAALgADCgMJAwAAAA==.Flowforth:BAAALgAECgUJBQAAAA==.Fluht:BAAALgADCgYJBgAAAA==.Flynae:BAABLgAECn8jAAIBAAgJphGcGACKAQABAAgJphGcGACKAQAAAA==.',
Fr='Fragmament:BAAALgAECgYJCgAAAA==.Frearyne:BAABLgAECn8bAAMaAAkJ2SOtBgAhAwAaAAkJ2SOtBgAhAwAcAAMJJw0LFwC8AAAAAA==.Friergren:BAACLgAFFH8LAAIEAAQJghWUMQBGAQAEAAQJghWUMQBGAQAuAAQKfyMAAgQACQkOHjYbAAoDAAQACQkOHjYbAAoDAAAA.Frostfight:BAAALgADCgYJBgAAAA==.Frylôck:BAAALgADCgIJAgABLgAECgYJFQAEANAYAA==.',
Fs='Fstingnemo:BAAALgADCgUJCAAAAA==.',
Fy='Fyster:BAAALgAECgQJBQAAAA==.Fyxxer:BAABLgAECn8bAAINAAkJkBVdBwAZAgANAAkJkBVdBwAZAgABLgAFFAYJEwACAIYZAA==.Fyxxie:BAACLgAFFH8TAAICAAYJhhn8AgDBAQACAAYJhhn8AgDBAQAuAAQKfyIAAgIACQnqHGkHABIDAAIACQnqHGkHABIDAAAA.',
Ga='Galex:BAAALgADCgEJAQAAAA==.Garah:BAAALgADCgYJBwAAAA==.',
Ge='Geewonii:BAAALgADCgYJBgAAAA==.Geroesan:BAAALgADCggJCAAAAA==.Geron:BAAALgADCgMJAwAAAA==.',
Gh='Ghostchedd:BAAALgADCggJCwAAAA==.',
Gi='Gialiana:BAACLgAFFH8LAAIPAAUJRxUqCAA+AQAPAAUJRxUqCAA+AQAuAAQKfyAAAg8ACQmDFooXAHICAA8ACQmDFooXAHICAAAA.Giblar:BAAALgADCgUJBQAAAA==.Gikyounoshi:BAAALgADCgUJBwAAAA==.Girthen:BAABLgAECn8kAAMBAAgJySLHBQDzAgABAAgJySLHBQDzAgACAAMJLReCQwDfAAAAAA==.',
Gn='Gnx:BAAALgAECgQJCAAAAA==.',
Go='Goobby:BAABLgAECn8nAAIXAAgJvSPYDgCKAgAXAAgJvSPYDgCKAgAAAA==.Goonfred:BAAALgAECgQJBAAAAA==.',
Gr='Greenymeany:BAABLgAECn8jAAILAAYJriSzGwBvAgALAAYJriSzGwBvAgAAAA==.Grrimm:BAAALgADCgMJAwAAAA==.Grukk:BAAALgADCgYJCwABLgAECgQJDAAFAAAAAA==.Grully:BAACLgAFFH8FAAIHAAMJ2AZ+KwCgAAAHAAMJ2AZ+KwCgAAAuAAQKfx0AAwcACQmzEX4pAOkBAAcACQmzEX4pAOkBAB4AAQmmAUtzABsAAAAA.Gruumsh:BAAALgAECgYJDgAAAA==.',
Ha='Haggard:BAABLgAECn8dAAIGAAgJFRZjIQDAAQAGAAgJFRZjIQDAAQAAAA==.Hailsbelle:BAABLgAECn8hAAIJAAYJExSEFABIAQAJAAYJExSEFABIAQAAAA==.',
Hb='Hbic:BAAALgAECgcJDAAAAA==.',
He='Healingpanda:BAAALgAECgQJCQAAAA==.Healyboar:BAABLgAECn8VAAIQAAgJbRCuGgC0AQAQAAgJbRCuGgC0AQAAAA==.Heartstabber:BAAALgADCggJCwAAAA==.Heascha:BAAALgADCgEJAQAAAA==.Heimerdonker:BAEALgADCgcJBwABLgAFFAQJCgAEAHwIAA==.Helado:BAAALgAECgEJAQAAAA==.Hellbane:BAAALgAECgcJDgAAAA==.Herdyouleik:BAAALgAECgIJAgAAAA==.Heri:BAAALgADCgEJAQAAAA==.',
Hi='Highwayman:BAAALgAECgYJEgABLgAECgkJMwAfAP8jAA==.Himwhome:BAAALgAECgMJBQAAAA==.',
Ho='Holyteamdiff:BAABLgAECn8aAAIDAAgJsxaxFAAEAgADAAgJsxaxFAAEAgAAAA==.Holÿshut:BAAALgADCgEJAQABLgAECggJIAAHAIcXAA==.Hondurasman:BAAALgAECgEJAQAAAA==.Honkay:BAAALgAECgUJCwAAAA==.Honkhonk:BAABLgAECn8qAAIKAAgJ8xU0MgC0AQAKAAgJ8xU0MgC0AQAAAA==.',
Hu='Huahhuahhuah:BAAALgADCgcJFgABLgAECgYJFgAHAEkkAA==.Hulas:BAAALgAECgEJAQAAAA==.Hungbeazt:BAAALgAECgUJBQABLgAECgkJJwAgAAMXAA==.Hungidan:BAAALgADCgYJBgABLgAECgkJJwAgAAMXAA==.Huntdemonz:BAAALgAECgUJCAABLgAECgcJIgALAP8aAA==.',
Ic='Icelynsnow:BAAALgAECgQJBAAAAA==.Icrono:BAAALgADCgIJAgAAAA==.Icwiener:BAABLgAECn8WAAIHAAYJSSQQDwBJAgAHAAYJSSQQDwBJAgAAAA==.',
Il='Illaria:BAAALgADCgIJAgAAAA==.Illith:BAAALgADCgMJAgAAAA==.Illumis:BAAALgAECgYJBgAAAA==.',
Im='Imjustpika:BAAALgADCgcJBwABLgAFFAUJDwAhAO0IAA==.',
In='Indeathinite:BAAALgADCgIJAgAAAA==.Inferniö:BAACLgAFFH8VAAIEAAYJuyEcCADtAQAEAAYJuyEcCADtAQAuAAQKfy4AAgQACQnnJGcEALoDAAQACQnnJGcEALoDAAAA.Inkurushio:BAABLgAECn8lAAMMAAcJyRLNDAB0AQAMAAcJyRLNDAB0AQALAAYJNQwfNgDvAAAAAA==.Insector:BAAALgADCgIJAgAAAA==.Inshallah:BAAALgAECgEJBAABLgAECgIJAwAFAAAAAA==.Inyoguts:BAAALgAECgcJBwAAAA==.',
Io='Iolanie:BAAALgAECgMJAwAAAA==.',
Ip='Ipewdmyself:BAAALgADCgYJCAAAAA==.',
Is='Ismat:BAABLgAECn81AAIHAAkJph3ECwBzAgAHAAkJph3ECwBzAgAAAA==.',
Iv='Ivorybones:BAAALgAECgYJEQAAAA==.',
Ix='Ixxi:BAAALgADCgUJBQAAAA==.Ixxia:BAAALgAECgEJAQABLgAECgIJAgAFAAAAAA==.Ixxy:BAAALgAECgEJAQAAAA==.',
Iz='Izbiar:BAAALgADCgcJDAAAAA==.',
Ja='Jabahnzulash:BAAALgAECgIJAgABLgAFFAQJDQAXANAYAA==.Jabzularu:BAABLgAECn8XAAIHAAcJSAs+NgAxAQAHAAcJSAs+NgAxAQAAAA==.Jaeko:BAABLgAECn8WAAIUAAYJXw81NwBCAQAUAAYJXw81NwBCAQAAAA==.Jaekyrn:BAAALgADCgIJAgABLgAECgYJFgAUAF8PAA==.Jaeza:BAAALgAECgEJAQABLgAECgQJBQAFAAAAAA==.Jamrock:BAABLgAECn8eAAIXAAgJbxWbQQB4AQAXAAgJbxWbQQB4AQAAAA==.Jarshh:BAABLgAECn8qAAILAAgJqCDQBgCBAgALAAgJqCDQBgCBAgAAAA==.',
Je='Jethic:BAAALgADCgUJCwAAAA==.Jezabell:BAAALgAECgYJBgAAAA==.',
Ji='Jibberwhocky:BAAALgADCgYJCgABLgAECggJGgASAE8ZAA==.',
Jo='Jonald:BAABLgAECn8aAAMOAAgJyhOHIQDTAQAOAAgJyhOHIQDTAQAPAAQJTALPdQBnAAAAAA==.Jonwic:BAAALgADCgIJAgAAAA==.',
Ju='Judge:BAAALgAECgYJCQABLgAECggJLAAbAK0bAA==.',
Ka='Kaelostrasza:BAABLgAFFH8GAAIhAAQJ4BC0FQAyAQAhAAQJ4BC0FQAyAQABLgAFFAUJBwACAAcNAA==.Kallaiopi:BAAALgAECgMJAwAAAA==.Kallindrya:BAAALgAECgQJBAAAAA==.Kaly:BAAALgADCgEJAQAAAA==.Kass:BAAALgAECgEJAQAAAA==.Kasselliea:BAAALgADCgEJAQAAAA==.Kaveros:BAAALgAECgYJEwAAAA==.',
Ke='Kefurion:BAAALgAECgQJBAABLgAECgYJCAAFAAAAAA==.Kelaan:BAABLgAECn8gAAMiAAgJWiEXAgCjAgAiAAgJWiEXAgCjAgAKAAQJdhU9zwDrAAAAAA==.Kelimao:BAABLgAECn8qAAMYAAgJ1w2zFwB+AQAYAAgJ1w2zFwB+AQAaAAYJoAjZXwCfAAAAAA==.Kellin:BAAALgADCgMJAwAAAA==.Kelthannaras:BAABLgAECn8hAAMPAAgJRRpCBAD8AQAPAAgJRRpCBAD8AQAfAAIJPQj6OQBEAAAAAA==.Kendrà:BAAALgADCgMJAwAAAA==.Kerunirus:BAAALgADCgYJBgAAAA==.Kevinns:BAAALgAECgYJCwAAAA==.Kevwave:BAAALgAECgMJBQAAAA==.Keyadon:BAAALgAECgcJBwAAAA==.',
Ki='Kilian:BAABLgAECn8YAAMSAAYJoghycQDnAAASAAUJoghycQDnAAAWAAIJ9QLuJwBRAAAAAA==.Killoroc:BAAALgADCgYJEwAAAA==.Kiritos:BAAALgAECgMJCQAAAA==.Kiserys:BAAALgAECgYJCAAAAA==.Kitsuné:BAAALgADCgEJAQAAAA==.',
Ko='Kohor:BAAALgADCgUJCAAAAA==.Koko:BAAALgADCgYJDQAAAA==.Komekaka:BAAALgADCgQJCAAAAA==.Korpse:BAAALgAECgQJBQAAAA==.Kostard:BAAALgAECgIJAgAAAA==.',
Kr='Kryemhild:BAAALgADCggJEQAAAA==.Krysto:BAABLgAECn8jAAIOAAgJTxTuJgC4AQAOAAgJTxTuJgC4AQAAAA==.',
Kw='Kwatli:BAAALgAECgMJAwAAAA==.',
Ky='Kyferon:BAAALgADCggJCgAAAA==.Kyral:BAAALgADCgIJAgAAAA==.',
La='Ladiegp:BAAALgADCgEJAQAAAA==.Lanria:BAAALgAECgMJBQAAAA==.Laquisha:BAABLgAECn8iAAILAAcJ/xoCEwDWAQALAAcJ/xoCEwDWAQAAAA==.Lays:BAAALgADCgQJBAAAAA==.Lazarusgrimm:BAAALgADCgIJAgAAAA==.',
Le='Lelét:BAAALgADCgYJDwAAAA==.Lenin:BAAALgAECgEJAQAAAA==.Lexicology:BAAALgAECgQJCAABLgAECgQJCQAFAAAAAA==.',
Li='Lickithom:BAAALgAECgQJBQAAAA==.Lilgup:BAAALgADCgUJBgAAAA==.Lilydari:BAAALgAECgUJEgAAAA==.Limerick:BAAALgAECgEJAQAAAA==.Limitless:BAAALgADCgcJBwAAAA==.Linaa:BAAALgADCgEJAQAAAA==.Lishna:BAAALgADCgYJBgAAAA==.Lissathshonk:BAAALgAECgEJAQAAAA==.',
Lo='Lookforlight:BAABLgAECn80AAIKAAkJBiUpAgBFAwAKAAkJBiUpAgBFAwAAAA==.Lorenth:BAABLgAECn8qAAIBAAgJ3QeLIABEAQABAAgJ3QeLIABEAQAAAA==.',
Lu='Lucid:BAAALgADCgEJAQAAAA==.Luckyjade:BAAALgAECgYJEQAAAA==.Luunya:BAABLgAECn8mAAQCAAkJhwwwEQDCAQACAAkJhwwwEQDCAQADAAgJBw07GgBfAQABAAUJvwj2VwDVAAAAAA==.',
Ly='Lyralia:BAAALgADCgkJEQAAAA==.',
Ma='Mabi:BAAALgAECgEJAQAAAA==.Madcowburger:BAAALgAECgQJCgAAAA==.Madelyine:BAAALgADCgIJAgAAAA==.Mageyoulookk:BAAALgAECgYJEQAAAA==.Mahziir:BAAALgAECgYJBwAAAA==.Maithieran:BAAALgADCgYJDAAAAA==.Maizen:BAAALgAECgQJBQABLgAECgQJCQAFAAAAAA==.Majax:BAAALgAFFAIJBAAAAA==.Malidros:BAABLgAECn8XAAMBAAYJFx8cDgAFAgABAAYJFx8cDgAFAgACAAEJPAdDVwAsAAAAAA==.Manogawd:BAAALgAECgUJCgAAAA==.Manwathiel:BAAALgADCgMJAwAAAA==.Marhault:BAABLgAECn8zAAQfAAkJ/yPDAAA3AwAfAAkJgSLDAAA3AwAOAAgJdyJ0EAC2AgAPAAUJCxLrVQDyAAAAAA==.Marriage:BAAALgAECgQJBQAAAA==.Masitaka:BAAALgAECgQJCQAAAA==.Mathollas:BAAALgAECgUJBQAAAA==.Matt:BAAALgAECgEJAgAAAA==.Maxicat:BAAALgAECgYJCQAAAA==.Maximus:BAABLgAECn8bAAIKAAgJlhX1JwDgAQAKAAgJlhX1JwDgAQAAAA==.Mayaplc:BAAALgADCgEJAQAAAA==.Mazah:BAABLgAECn8vAAMHAAgJrh6vCgCCAgAHAAcJNSCvCgCCAgAjAAcJfRVlCQCGAQABLgAECgkJJgACAIcMAA==.Mazlo:BAABLgAECn8VAAIEAAgJzBKJIwAYAgAEAAgJzBKJIwAYAgAAAA==.',
Mc='Mckrakin:BAAALgADCgEJAQAAAA==.Mclovìns:BAAALgAECgMJAwAAAA==.',
Me='Mechanix:BAAALgAECgMJAwAAAA==.Megafrost:BAAALgAECgEJAQAAAA==.Meibao:BAABLgAECn8sAAIbAAgJrRsPCQA2AgAbAAgJrRsPCQA2AgAAAA==.Meleebrain:BAABLgAECn8qAAIGAAkJHBmBEAA/AgAGAAkJHBmBEAA/AgAAAA==.Mesaana:BAAALgADCgUJBQABLgAECggJHAAUADMXAA==.Messalina:BAAALgAECgUJBQABLgAECgYJFwABABcfAA==.Mex:BAAALgADCgYJDgAAAA==.',
Mi='Miaoyi:BAAALgADCgEJAwAAAA==.Millîe:BAAALgAECgQJBwAAAA==.Mimikay:BAAALgADCgIJAgAAAA==.Missclick:BAAALgAECgQJCAAAAA==.Missoxx:BAAALgAECgMJAwAAAA==.Mistbringer:BAAALgAECgYJEwAAAA==.Mistmaker:BAAALgAECgYJBgABLgAECggJGgASAE8ZAA==.Miwi:BAAALgAECgYJEQAAAA==.',
Mo='Moiest:BAAALgADCgcJBwABLgAECgUJEAAFAAAAAA==.Moiesttuna:BAAALgAECgUJEAAAAA==.Monfalauda:BAAALgADCgEJAgAAAA==.Monkazz:BAAALgADCgYJEAAAAA==.Monkorith:BAECLgAFFH8WAAIbAAYJrRdGBQCjAQAbAAYJrRdGBQCjAQAuAAQKfyAAAhsACQlaEJYkAN0BABsACQlaEJYkAN0BAAAA.Moongyal:BAABLgAECn8XAAIaAAgJKRjsGAD9AQAaAAgJKRjsGAD9AQAAAA==.Mordoboinik:BAAALgAECgEJAQAAAA==.Mortis:BAAALgADCgQJCgAAAA==.Mosaden:BAABLgAECn8UAAIUAAYJiR8qEQCvAQAUAAYJiR8qEQCvAQAAAA==.',
Mu='Mudahnk:BAAALgAECgEJAQAAAA==.Mullett:BAABLgAECn8aAAIKAAcJ3w8LXAA4AQAKAAcJ3w8LXAA4AQAAAA==.',
My='Mymeii:BAAALgAECgEJAgAAAA==.Mysticheart:BAAALgADCgEJAQAAAA==.Mystogaan:BAAALgAECgUJBQAAAA==.',
['Mï']='Mïra:BAAALgAECgYJDAABLgAECggJIAAiAFohAA==.',
Na='Nadrael:BAAALgAECgEJAQAAAA==.Nakiki:BAAALgAECgYJEQAAAA==.Nastyiam:BAABLgAECn8pAAIjAAgJMhOhBgDRAQAjAAgJMhOhBgDRAQAAAA==.',
Ne='Necromeany:BAAALgADCgQJBwABLgAECgYJIwALAK4kAA==.Nennya:BAAALgAECgYJCwAAAA==.Nerfornothin:BAABLgAECn8bAAIOAAcJuQdCTgAjAQAOAAcJuQdCTgAjAQAAAA==.Nethflap:BAACLgAFFH8GAAIhAAMJjwXhJQDIAAAhAAMJjwXhJQDIAAAuAAQKfx8AAyEACAl3EO0fAMIBACEACAl3EO0fAMIBACAABwntB2UxAOUAAAAA.Netsmear:BAAALgAECgYJEgAAAA==.Newdawn:BAAALgAECgIJAgAAAA==.',
Ni='Niftypackage:BAAALgADCgcJDwAAAA==.Nik:BAACLgAFFH8FAAIDAAQJfAPfFgD0AAADAAQJfAPfFgD0AAAuAAQKfyoAAwEACQmzGZkQAF8CAAEACAlVGpkQAF8CAAMACAkFFCYPAOABAAAA.',
No='Noctiss:BAAALgAECgIJAgAAAA==.Nosferato:BAAALgADCgUJBgAAAA==.',
Nu='Nutmilker:BAABLgAECn8uAAIjAAkJ7SS4AAANAwAjAAkJ7SS4AAANAwAAAA==.',
Ny='Nycterine:BAAALgAECgEJAQAAAA==.Nyxnight:BAAALgADCgYJBgAAAA==.',
Oa='Oakenhart:BAAALgAECgIJAgAAAA==.Oathtaker:BAAALgADCgQJBAAAAA==.',
Ob='Obi:BAAALgAECgUJBwAAAA==.',
Ok='Okoye:BAAALgADCggJDwAAAA==.',
Ol='Olahla:BAAALgADCgYJCwAAAA==.',
Om='Omacron:BAAALgADCggJDgAAAA==.Omroko:BAAALgADCgQJAwAAAA==.',
Op='Ophriala:BAAALgAECgQJBAAAAA==.Optimistic:BAAALgAECgEJAQAAAA==.',
Or='Oriion:BAAALgAECgEJAQAAAA==.Orthae:BAAALgADCgcJEQABLgAECgQJBQAFAAAAAA==.',
Pa='Paladio:BAAALgAECgMJBAAAAA==.Pandoosevelt:BAAALgAECgEJAQAAAA==.Panodoc:BAAALgADCgMJAwAAAA==.Parmenion:BAAALgAECgQJBAABLgAECgcJDQAFAAAAAA==.',
Pe='Pelotuda:BAAALgAECgQJCwAAAA==.Penix:BAAALgADCgEJAQAAAA==.Petrovna:BAAALgAECgIJAwAAAA==.',
Pi='Picklerickz:BAAALgADCgYJBgAAAA==.Pikagosa:BAACLgAFFH8PAAMhAAUJ7Qh7JADTAAAhAAUJ7Qh7JADTAAAkAAIJ8wNPBwCVAAAuAAQKfyoAAyEACQmOFmQSAFcCACEACQlsE2QSAFcCACQABwkKGk0NAAQCAAAA.Pilgor:BAABLgAECn8VAAIhAAgJgxHqFgCLAQAhAAgJgxHqFgCLAQAAAA==.Pils:BAAALgADCgYJBgAAAA==.Pitchief:BAAALgAECgEJAgAAAA==.',
Pl='Plopping:BAAALgADCgMJAwAAAA==.',
Po='Pocky:BAAALgADCgMJAwAAAA==.',
Pr='Priestkidx:BAAALgADCggJCgAAAA==.Primax:BAAALgAECgIJAgAAAA==.',
Pu='Punchballz:BAAALgADCgIJAgAAAA==.Punchkín:BAABLgAECn8YAAQbAAYJCiATHgASAgAbAAYJyR4THgASAgAUAAQJShsUPAAsAQAlAAQJpxlCJAAlAQAAAA==.',
['Pæ']='Pæsta:BAABLgAECn8iAAIVAAkJlReGCQAoAgAVAAkJlReGCQAoAgAAAA==.',
['Pó']='Póókie:BAAALgAECgEJAQAAAA==.',
Ra='Ragdenar:BAAALgAECgMJBAAAAA==.Ragepounce:BAAALgAECgYJDgAAAA==.Ragingblownr:BAAALgAECgQJBAABLgAECgYJDwAFAAAAAA==.Rangikü:BAAALgAECgUJCAAAAA==.Rast:BAAALgADCgYJBgABLgAECgYJEQAFAAAAAA==.Rastabout:BAABLgAECn8aAAMBAAcJZxcOJwC1AQABAAcJZxcOJwC1AQACAAQJ+ww6NwCsAAAAAA==.Rathannar:BAABLgAECn8dAAMJAAcJhxKQFABHAQAJAAcJhxKQFABHAQAGAAMJIQcwwACAAAAAAA==.Ravel:BAABLgAECn8qAAIlAAgJrB/PBQCtAgAlAAgJrB/PBQCtAgAAAA==.Raxxar:BAEALgADCgcJBwAAAA==.Razah:BAABLgAECn8VAAIhAAYJOwhDQQDgAAAhAAYJOwhDQQDgAAAAAA==.',
Re='Reahla:BAAALgADCgcJBwAAAA==.Realchad:BAAALgAECgUJBwAAAA==.Redeem:BAAALgAECgcJCAAAAA==.Reios:BAABLgAECn8ZAAISAAcJeRzqHwDxAQASAAcJeRzqHwDxAQAAAA==.Remedis:BAAALgADCgYJBgAAAA==.Remy:BAAALgAECgcJCgABLgAECgcJEwAFAAAAAA==.Renara:BAAALgAECgMJAwAAAA==.Resora:BAAALgADCgMJAwAAAA==.',
Rh='Rhaz:BAABLgAECn8bAAIQAAcJlRNlHQCcAQAQAAcJlRNlHQCcAQAAAA==.Rhoup:BAABLgAECn8VAAMcAAYJSxrBCgByAQAcAAYJSxrBCgByAQARAAEJmAgwLgAfAAAAAA==.',
Ri='Richter:BAAALgAECggJCQAAAA==.Rickyspanish:BAABLgAECn8aAAIGAAcJjRxfIADGAQAGAAcJjRxfIADGAQAAAA==.Rifter:BAAALgAECgUJDwAAAA==.',
Ro='Roarke:BAAALgADCgMJAwAAAA==.',
Ru='Rubyouraw:BAABLgAECn8XAAILAAYJjRBCKAA2AQALAAYJjRBCKAA2AQAAAA==.Rubyus:BAAALgADCgcJBwAAAA==.Ruematoid:BAAALgAECgUJDgAAAA==.Ruffneck:BAABLgAECn8cAAIOAAgJsxFJKACxAQAOAAgJsxFJKACxAQAAAA==.Ruine:BAAALgADCgYJCAAAAA==.Rumina:BAAALgAECgIJAwAAAA==.Runiic:BAAALgAECgYJAgAAAA==.Russk:BAAALgADCgUJBQAAAA==.',
Sa='Saelirria:BAAALgADCggJCAABLgAFFAUJCwAPAEcVAA==.Sailboat:BAAALgAECgEJAQABLgAECgEJAgAFAAAAAA==.Sakau:BAABLgAECn8UAAQWAAcJlQa5CAAPAQAWAAcJRwa5CAAPAQASAAYJ/wQWrwD7AAAVAAEJvgZ2eQApAAAAAA==.Sakurá:BAABLgAECn8YAAIlAAYJCA06KgD9AAAlAAYJCA06KgD9AAAAAA==.Samo:BAABLgAECn8gAAICAAgJEh0iBwBeAgACAAgJEh0iBwBeAgAAAA==.Sandarr:BAABLgAECn8gAAIiAAgJHRcYCgChAQAiAAgJHRcYCgChAQAAAA==.Sanguinne:BAABLgAECn8VAAIVAAYJug4fDQAAAQAVAAYJug4fDQAAAQAAAA==.Saphran:BAAALgAECgIJAgAAAA==.Sarah:BAAALgAECggJCQABLgAFFAQJCAACAK8UAA==.Sargemarge:BAAALgAECgIJAgAAAA==.Sauccy:BAAALgAECgEJAgAAAA==.',
Sc='Scaly:BAABLgAECn8nAAMgAAkJAxdpAwCZAgAgAAkJAxdpAwCZAgAhAAMJRw1CPQCoAAAAAA==.Scrotosaggin:BAAALgAECgUJBQAAAA==.',
Se='Seafoame:BAAALgADCgcJCAABLgAFFAEJAQAFAAAAAA==.See:BAABLgAFFH8OAAIMAAMJGCDSCAAaAQAMAAMJGCDSCAAaAQAAAA==.Selener:BAAALgAECgYJEAAAAA==.Sendisth:BAAALgADCgYJDQABLgAFFAMJBwAjADMOAA==.Sennia:BAAALgAECgYJBgAAAA==.Severus:BAAALgAECgYJBgAAAA==.',
Sh='Shadoryan:BAAALgADCgYJBgABLgAECgkJIgASAN0iAA==.Shadowrock:BAAALgADCgQJBAAAAA==.Shaggiê:BAAALgAECgYJBgAAAA==.Shamydavisjr:BAAALgADCgEJAQAAAA==.Shellenne:BAAALgADCgIJAQAAAA==.Shikamáru:BAAALgAECgcJCAAAAA==.Shirius:BAAALgADCgYJBgAAAA==.',
Si='Silentsnipe:BAAALgADCgQJAwAAAA==.Silther:BAABLgAECn8kAAIKAAgJlB0JFgBKAgAKAAgJlB0JFgBKAgAAAA==.Sinnabun:BAAALgAECgIJAgAAAA==.',
Sk='Skol:BAAALgAECgYJCwAAAA==.',
Sl='Slapslap:BAAALgAECgIJAgAAAA==.Slavka:BAAALgAECgEJAQAAAA==.Sleepyjoee:BAAALgAECgQJBwABLgAECgYJEQAFAAAAAA==.Sleepypriest:BAAALgADCgIJAgABLgAECgYJEQAFAAAAAA==.Sleepyyjoe:BAAALgAECgQJBQABLgAECgYJEQAFAAAAAA==.Slock:BAAALgAECgEJAQAAAA==.Slothymoon:BAAALgADCgcJBwAAAA==.Sluxso:BAAALgADCgYJBgAAAA==.',
Sm='Smalliam:BAAALgADCgYJDgABLgAECggJKQAjADITAA==.Smoted:BAAALgADCgUJBQAAAA==.',
Sn='Snaerbear:BAAALgAECgUJBQABLgAECgkJNAAKAAYlAA==.Snikrot:BAAALgADCgMJBgAAAA==.Snâppy:BAABLgAECn8gAAIaAAgJqwwBNABLAQAaAAgJqwwBNABLAQAAAA==.',
So='Soloron:BAABLgAECn8bAAIHAAcJmReKGwDVAQAHAAcJmReKGwDVAQAAAA==.Somebody:BAAALgADCgEJAQAAAA==.Sorceremy:BAAALgAECgcJEwAAAA==.Southvik:BAAALgAECgYJCgABLgAECggJJgABAAggAA==.',
Sp='Sparke:BAAALgAECgIJBQAAAA==.Sparrhawk:BAAALgAECgMJAwAAAA==.Spiced:BAABLgAECn8iAAIYAAkJ5yQZBQBPAwAYAAkJ5yQZBQBPAwAAAA==.Spiceweasel:BAAALgAECgEJAQAAAA==.Spiritbound:BAAALgAECgIJAwAAAA==.',
St='Starquake:BAAALgADCgQJBAABLgAECgQJCQAFAAAAAA==.Starskream:BAAALgAECgQJBwAAAA==.Steliokontos:BAAALgAECgcJCAAAAA==.Stickes:BAAALgAECgEJAQAAAA==.Stormclaw:BAAALgAECgUJCQAAAA==.Streea:BAAALgAECgEJAQABLgAECgQJBQAFAAAAAA==.Sttriker:BAABLgAECn8iAAIJAAgJ/wRmMABNAQAJAAgJ/wRmMABNAQAAAA==.',
Su='Survival:BAAALgAECgMJBgABLgAFFAYJFAAXAOkkAA==.Suzierulz:BAAALgAECgQJBAAAAA==.',
Sw='Sweetcheese:BAAALgAECgEJAQAAAA==.',
Sy='Syn:BAAALgADCgkJCgAAAA==.Synsairis:BAABLgAECn8pAAIUAAgJtx17CgASAgAUAAgJtx17CgASAgAAAA==.',
Ta='Talenelat:BAAALgADCgEJAQAAAA==.Talietha:BAAALgADCgUJBQAAAA==.Tallonk:BAAALgADCgEJAQAAAA==.Talonknight:BAABLgAECn8gAAIhAAgJsw/XGAB5AQAhAAgJsw/XGAB5AQAAAA==.Talset:BAABLgAECn8jAAIbAAgJwg0YGgBkAQAbAAgJwg0YGgBkAQAAAA==.Tatarin:BAAALgAECgEJAQAAAA==.Taurrows:BAAALgADCgMJAwAAAA==.Tazures:BAAALgADCgIJAgAAAA==.',
Tb='Tbill:BAAALgAECgUJCQAAAA==.',
Te='Teaux:BAAALgADCgQJBQAAAA==.Tellina:BAAALgAECgIJAgAAAA==.Tenson:BAAALgAECgQJCQAAAA==.',
Th='Thad:BAAALgADCgYJBgAAAA==.Thaendofyou:BAABLgAECn8VAAILAAgJFRDgFgCwAQALAAgJFRDgFgCwAQAAAA==.Thagda:BAAALgAECgcJDQAAAA==.Theevoker:BAACLgAFFH8FAAIgAAMJdQIDFgCoAAAgAAMJdQIDFgCoAAAuAAQKfyEAAyAACQnJDlQIAOMBACAACQnJDlQIAOMBACQAAQnUAcpFAB4AAAAA.Theproject:BAAALgAECgcJBgAAAA==.Thestarman:BAAALgADCgUJBQAAAA==.Thizzordie:BAAALgAECgEJAQAAAA==.Tholnar:BAAALgAECgUJDgAAAA==.Thoroughbred:BAAALgAECgUJBQAAAA==.Throwdini:BAABLgAECn8kAAIOAAkJYh2EEAC2AgAOAAkJYh2EEAC2AgAAAA==.',
Ti='Tigerboy:BAAALgAECgYJCQAAAA==.Tikva:BAAALgAECgMJBAABLgAECgkJJgACAIcMAA==.Timotthy:BAAALgAFFAIJBAAAAA==.Titant:BAAALgADCgEJAQAAAA==.Titanta:BAAALgAECgYJDwAAAA==.Tixxle:BAAALgADCgEJAQAAAA==.',
Tm='Tmate:BAAALgAECgYJCgAAAA==.',
To='Totempics:BAAALgADCgUJBQABLgAECggJIQAaAAEgAA==.Touchmé:BAAALgAECgMJAwAAAA==.',
Ts='Tsunaris:BAABLgAECn8gAAIPAAkJqhlkAgBaAgAPAAkJqhlkAgBaAgAAAA==.',
Tu='Tulanis:BAABLgAECn81AAIPAAkJeSGyAAAQAwAPAAkJeSGyAAAQAwAAAA==.Turbotax:BAAALgAECgQJBAAAAA==.',
Ty='Tyriem:BAABLgAECn8iAAIOAAgJohntGwD1AQAOAAgJohntGwD1AQAAAA==.Tyssanton:BAABLgAECn8jAAQgAAgJnwWvGQCzAAAgAAYJ+gKvGQCzAAAkAAUJqQWIDgChAAAhAAIJVwJ/WAA8AAAAAA==.',
Tz='Tziganin:BAABLgAECn8bAAIjAAcJ6BcsCgB0AQAjAAcJ6BcsCgB0AQAAAA==.',
Ug='Uggork:BAAALgAECgYJCAAAAA==.',
Um='Umi:BAAALgAECgIJAgAAAA==.',
Un='Unholybussy:BAABLgAECn8qAAIXAAgJwBqBIwD2AQAXAAgJwBqBIwD2AQAAAA==.Unicorns:BAAALgAECgEJAQAAAA==.',
Ur='Urvazlite:BAABLgAECn8gAAILAAgJGQvSHACCAQALAAgJGQvSHACCAQAAAA==.',
Ut='Utaadh:BAABLgAECn8XAAIJAAkJJRYyCQD7AQAJAAkJJRYyCQD7AQAAAA==.',
Va='Vallerin:BAABLgAECn8gAAIjAAgJxhSiBgDRAQAjAAgJxhSiBgDRAQAAAA==.Vanestor:BAAALgADCgkJCQABLgAFFAQJDgAOAIkXAA==.Varahk:BAAALgADCgMJAwAAAA==.Varus:BAAALgADCggJFAAAAA==.',
Ve='Velaar:BAABLgAECn8zAAIXAAkJOyVsAQBsAwAXAAkJOyVsAQBsAwABLgAECgYJEgAFAAAAAA==.Velamuna:BAAALgADCgQJBAAAAA==.Velindraela:BAAALgADCgMJAgABLgAECggJIQAaAAEgAA==.Verras:BAAALgADCgIJAgAAAA==.',
Vi='Vikthyr:BAAALgADCgcJDQABLgAECggJJgABAAggAA==.Villain:BAAALgADCgYJBgABLgAECgkJMwAfAP8jAA==.',
Vo='Vodlock:BAAALgADCggJCAABLgAFFAQJDgAOAIkXAA==.Vodnar:BAACLgAFFH8OAAMOAAQJiRf3FABJAQAOAAQJiRf3FABJAQAPAAEJegAKLgA1AAAuAAQKfyIAAw4ACQlrG1UZAHACAA4ACAnwHlUZAHACAA8ABglhCDtGADwBAAAA.Vohnkhar:BAAALgADCgQJBQAAAA==.Voidatfear:BAAALgAECgUJDgAAAA==.Voidhunter:BAAALgADCgkJEAAAAA==.Voodoodoo:BAAALgAECgYJDwAAAA==.Voxramus:BAAALgADCgQJBAABLgAECgQJDAAFAAAAAA==.',
Vu='Vulcos:BAAALgAECgYJBwAAAA==.',
Vy='Vyreth:BAAALgAECgIJBAAAAA==.',
Wa='Walls:BAABLgAECn8eAAIKAAYJDBYxVABLAQAKAAYJDBYxVABLAQAAAA==.Wasil:BAAALgADCgYJBgAAAA==.Waste:BAABLgAECn8XAAMSAAgJsxvsHwDxAQASAAcJIhzsHwDxAQAVAAQJTgyVHQBhAAAAAA==.Waylander:BAAALgADCgMJAwABLgAECgcJDQAFAAAAAA==.',
We='Werragan:BAAALgADCgcJBwAAAA==.',
Wh='Wham:BAAALgAECgIJAgAAAA==.Whameradetu:BAAALgAECgEJAQAAAA==.Whipps:BAAALgAECgYJBgAAAA==.',
Wi='Willîe:BAAALgAECgEJAQAAAA==.Wilt:BAAALgAECgEJAQAAAA==.',
Wo='Wompazuzu:BAAALgAECgcJEQAAAA==.',
Wr='Wraithewyn:BAAALgAECgEJAQAAAA==.Wrékt:BAAALgADCgMJAwAAAA==.',
Xa='Xanosina:BAAALgAECgQJBAAAAA==.',
Yi='Yilongma:BAAALgAECgIJAwAAAA==.',
Yl='Ylaran:BAAALgAECgMJAwAAAA==.',
Yn='Yn:BAAALgAECgYJEAAAAA==.',
Yo='Yogí:BAABLgAECn8oAAIjAAkJNhvLAQCrAgAjAAkJNhvLAQCrAgAAAA==.Yokos:BAAALgAECgUJBwAAAA==.Yonokojo:BAAALgAECgUJBgAAAA==.Yornic:BAAALgAECgYJCQABLgAECgcJEgAFAAAAAA==.',
Za='Zacksquach:BAAALgADCgMJAwAAAA==.Zahneel:BAABLgAECn8kAAIaAAgJaRm0GQD3AQAaAAgJaRm0GQD3AQAAAA==.Zalanar:BAAALgADCgkJDAAAAA==.Zaney:BAAALgAECgYJEQAAAA==.Zaps:BAAALgAECgEJAQAAAA==.Zaratul:BAACLgAFFH8MAAIKAAQJ9hm7HQA3AQAKAAQJ9hm7HQA3AQAuAAQKfzAAAgoACQlEIQsIAFQDAAoACQlEIQsIAFQDAAAA.Zaroth:BAACLgAFFH8LAAIBAAQJhSBNBQB2AQABAAQJhSBNBQB2AQAuAAQKfxwAAgEACAm2FNQnALEBAAEACAm2FNQnALEBAAAA.',
Ze='Zeleste:BAAALgAECggJDgAAAA==.Zelnorac:BAAALgAECgQJDgAAAA==.Zenma:BAAALgAECgMJAwAAAA==.Zerovii:BAACLgAFFH8HAAIjAAMJMw5pBQDrAAAjAAMJMw5pBQDrAAAuAAQKfx0AAiMACAndHSYEAOACACMACAndHSYEAOACAAAA.Zetsubou:BAAALgAECgMJAwAAAA==.Zettsuo:BAAALgAECgYJBgAAAA==.',
Zh='Zharrak:BAAALgAECgUJCAAAAA==.',
Zi='Zilyana:BAAALgAECgQJBAAAAA==.',
Zu='Zubuûuûuûuûu:BAAALgAECgUJCQAAAA==.',
Zy='Zyrian:BAAALgAECgIJAwAAAA==.',
['Zä']='Zärthan:BAAALgADCgIJAgAAAA==.',
['Éd']='Édz:BAAALgAECgQJCgAAAA==.',
['Ía']='Íamjakehill:BAAALgAECgMJBgAAAA==.',
['Îr']='Îris:BAAALgADCgcJEAAAAA==.',
['Ño']='Ñovember:BAAALgAFFAIJAgAAAA==.',
['Ör']='Örnak:BAAALgADCgUJBQAAAA==.',
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
