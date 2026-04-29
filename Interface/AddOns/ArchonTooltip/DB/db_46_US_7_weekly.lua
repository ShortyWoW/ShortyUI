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

local lookup = {'DeathKnight-Unholy','Paladin-Retribution','Druid-Restoration','Warrior-Fury','Shaman-Enhancement','Mage-Frost','DemonHunter-Devourer','DemonHunter-Havoc','Rogue-Outlaw','Warrior-Arms','Warrior-Protection','DeathKnight-Frost','Hunter-Marksmanship','Unknown-Unknown','Priest-Holy','Priest-Shadow','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Paladin-Protection','Monk-Windwalker','Rogue-Subtlety','Druid-Balance','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Shaman-Restoration','Mage-Fire','Druid-Feral','DemonHunter-Vengeance','Rogue-Assassination','Priest-Discipline','Monk-Brewmaster','Monk-Mistweaver','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Survival','Mage-Arcane','Shaman-Elemental','Druid-Guardian','Paladin-Holy',}
local provider = {region='US',realm='Alleria',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aantoc:BAAALgADCgUJBQAAAA==.',
Ad='Adramalech:BAAALgAECgEJAgABLgAFFAQJDAABAHwcAA==.',
Ae='Aelan:BAAALgADCgQJBAAAAA==.',
Ag='Agapitus:BAAALgADCgIJAgAAAA==.',
Ai='Ailuridae:BAAALgADCgcJEwAAAA==.Aimbot:BAAALgADCgIJAgAAAA==.Aisele:BAAALgAECgQJBwAAAA==.',
Al='Alathir:BAAALgAECgUJBgAAAA==.Alenton:BAAALgADCgUJBgAAAA==.Alessia:BAAALgADCgMJBAAAAA==.Alluri:BAABLgAECn8XAAICAAcJzhZcVQDiAQACAAcJzhZcVQDiAQAAAA==.Alone:BAAALgAECgUJCwAAAA==.Althemia:BAAALgAECgQJBQAAAA==.Alunamora:BAABLgAECn8aAAIDAAgJsxd8IwAuAgADAAgJsxd8IwAuAgAAAA==.Alwind:BAAALgAECgYJEAAAAA==.',
Am='Ambient:BAAALgAECgYJDgAAAA==.Amboosted:BAABLgAECn8fAAICAAgJLha6QQAgAgACAAgJLha6QQAgAgAAAA==.Ameretat:BAEALgAFFAIJAwABLgAFFAQJCAAEABkTAA==.',
An='Analani:BAAALgAECgQJBgAAAA==.Anali:BAAALgAECgIJAgAAAA==.Ancksunamun:BAAALgADCgcJBwAAAA==.Angerr:BAAALgAECgUJDQAAAA==.Angryheals:BAAALgAECgIJAgAAAA==.Animalator:BAAALgAECgEJAQAAAA==.',
Aq='Aquamann:BAAALgADCgMJAwAAAA==.',
Ar='Aranel:BAAALgAECgEJAQAAAA==.Aratiri:BAAALgADCgUJBQAAAA==.Arcamancer:BAAALgADCggJFwAAAA==.Arcannia:BAAALgADCgEJAQAAAA==.Arek:BAAALgAECgYJBwABLgAFFAUJDgAFAEkeAA==.Arinthal:BAAALgAECgQJCAAAAA==.Arril:BAAALgAECgUJCQAAAA==.Artemissy:BAAALgADCgMJAwAAAA==.Artorias:BAAALgADCgcJBgAAAA==.',
As='Ashed:BAAALgAECgcJCgAAAA==.Ashenskye:BAAALgADCgUJBQAAAA==.Ashlieghee:BAAALgADCgcJDAAAAA==.Ashtari:BAAALgADCgEJAQAAAA==.Astien:BAAALgAECgIJAgAAAA==.Astra:BAAALgADCgMJAwAAAA==.',
Au='Aureille:BAAALgADCgEJAgAAAA==.Aurien:BAAALgADCgMJAwAAAA==.Autoaim:BAAALgAECgYJBgAAAA==.',
Av='Avelen:BAAALgAECgEJAwAAAA==.Avha:BAAALgAECgQJBQAAAA==.Avië:BAABLgAECn8XAAIGAAYJOBadnACcAQAGAAYJOBadnACcAQAAAA==.',
Ax='Axel:BAABLgAECn8ZAAIHAAcJvBNZWgCSAQAHAAcJvBNZWgCSAQAAAA==.',
Ay='Aylden:BAABLgAECn8bAAIIAAYJcx4LHgDPAQAIAAYJcx4LHgDPAQAAAA==.',
Az='Azenezith:BAAALgAECgQJBAAAAA==.Azio:BAAALgAECgYJDAAAAA==.Azriah:BAAALgADCggJDwAAAA==.',
Ba='Bailas:BAAALgAECgEJAQAAAA==.Bananabear:BAAALgAECggJEwABLgAFFAMJBQAJAFUQAA==.Barbiesresto:BAAALgADCgUJBQAAAA==.Barra:BAAALgAECgMJAwAAAA==.Bashshield:BAEALgAFFAEJAQAAAA==.',
Bb='Bb:BAAALgAECgcJBwAAAA==.',
Be='Beastm:BAAALgADCgQJBAAAAA==.Beathed:BAAALgADCggJDgAAAA==.Beaver:BAAALgADCgIJAgAAAA==.Belencina:BAAALgADCggJDgAAAA==.Beleynn:BAAALgAECgcJDwAAAA==.Belwyn:BAAALgADCgMJAwAAAA==.Benjofamin:BAAALgAECgEJAQAAAA==.',
Bi='Bigheelz:BAAALgAECgUJBgAAAA==.Bigpuffer:BAAALgADCgMJAwAAAA==.Bitesize:BAECLgAFFH8IAAMEAAQJGRPAEQD4AAAEAAMJqRTAEQD4AAAKAAEJaw6jCgBYAAAuAAQKfyEABAoACQkgIB8MAN8BAAQABgluJEsjADsCAAoABQksHh8MAN8BAAsAAgklEe06AHQAAAAA.',
Bl='Blashster:BAAALgAECgUJBwAAAA==.',
Bo='Boaw:BAAALgADCgYJEwAAAA==.Bonemilker:BAACLgAFFH8MAAMBAAQJfBzACgAfAQABAAQJfBzACgAfAQAMAAMJ2RxzAQC9AAAuAAQKfywAAwwACAk3Jm4AAGwDAAwACAn/JW4AAGwDAAEACAnXJS8IAF4DAAAA.Boosieboose:BAAALgAECgYJCAAAAA==.',
Br='Brackz:BAAALgAFFAEJAQAAAA==.Brandt:BAAALgADCgEJAgAAAA==.Brannwynn:BAAALgADCgEJAQAAAA==.Brewtangclan:BAAALgAECgYJEwAAAA==.Brighter:BAAALgADCgkJJQAAAA==.Broncopally:BAAALgADCgYJDwAAAA==.Brother:BAAALgADCgEJAQABLgAECggJIQAGAOsTAA==.',
Bu='Bullitproof:BAAALgADCgcJDgABLgAECgcJHQACAEsEAA==.Bunnkost:BAAALgADCgkJGQAAAA==.',
Ca='Caiden:BAAALgAECgMJAwAAAA==.Calari:BAAALgAECgMJAwAAAA==.Caledwar:BAAALgAECgUJCwAAAA==.Calthirstrap:BAAALgAFFAIJAgABLgAECgkJFwAGAGIYAA==.Carapace:BAABLgAECn8XAAIEAAcJbg7IEQAXAQAEAAcJbg7IEQAXAQAAAA==.Carare:BAAALgADCggJCAAAAA==.Catomaze:BAAALgAECgEJAQAAAA==.',
Ce='Ceefack:BAAALgADCgYJCgAAAA==.Celestialsky:BAAALgAECgkJAQAAAA==.Cena:BAAALgAECgYJEgAAAA==.Cethin:BAAALgAECgIJAgAAAA==.',
Ch='Chaosform:BAAALgADCgkJHQABLgAECggJIgANAE0kAA==.Chaosshot:BAABLgAECn8iAAINAAgJTSQkBgA4AwANAAgJTSQkBgA4AwAAAA==.Cherylindrea:BAAALgADCgMJBgAAAA==.Chronic:BAAALgAECgYJEAAAAA==.Chènch:BAAALgADCgEJAQABLgAECgUJDwAOAAAAAA==.',
Cl='Claydemon:BAAALgAECgUJCQAAAA==.Claytraps:BAAALgADCgkJJQAAAA==.Clayvicar:BAABLgAECn8lAAMPAAgJDhOlIQDWAQAPAAgJDhOlIQDWAQAQAAMJYAOSVwBgAAAAAA==.',
Co='Coridane:BAAALgAECgUJCgAAAA==.Corrum:BAAALgADCgIJAgAAAA==.Corwinfiron:BAAALgAECgUJBgAAAA==.Cotreyy:BAACLgAFFH8JAAMRAAQJnyUiBgC+AQARAAQJnyUiBgC+AQASAAEJIyX3DwBqAAAuAAQKfyYABBEACAmiJRcRAPICABEABwkgJRcRAPICABMABQk3JvYEACMCABIABAkRIh4XAJEBAAAA.',
Cu='Cumgar:BAABLgAECn8aAAIRAAcJAhPBWAC+AQARAAcJAhPBWAC+AQAAAA==.',
Cy='Cythera:BAACLgAFFH8OAAIFAAUJSR5WAAB/AQAFAAUJSR5WAAB/AQAuAAQKfxsAAgUACAmOI1oEANgCAAUACAmOI1oEANgCAAAA.',
['Cá']='Cámus:BAABLgAECn8VAAICAAYJXBepfwB7AQACAAYJXBepfwB7AQAAAA==.',
['Cö']='Cöffee:BAAALgAECgMJBgAAAA==.',
Da='Daammy:BAAALgADCgMJAwAAAA==.Dagran:BAAALgAECgQJCQABLgAECgcJFwAHALwfAA==.Dagren:BAAALgAECgYJCQAAAA==.Dankfrost:BAAALgADCgUJBQAAAA==.Daphine:BAAALgADCgMJBgAAAA==.Darkbeautie:BAAALgAECgMJAwAAAA==.Darkcarbon:BAAALgAECgUJBgAAAA==.Darmin:BAAALgAECgEJAQAAAA==.',
De='Deathmask:BAAALgADCgEJAQAAAA==.Deepmoanpaw:BAAALgAECgIJAgAAAA==.Defnotash:BAABLgAECn8hAAIUAAkJ1x25AQAyAwAUAAkJ1x25AQAyAwAAAA==.Dellinair:BAAALgADCgEJAQAAAA==.Dementedlock:BAAALgAECgcJEQAAAA==.Derodd:BAAALgAECgQJBQAAAA==.Desolend:BAAALgADCgIJAgAAAA==.Dewkiez:BAEALgAFFAIJAgAAAA==.',
Di='Diabolicarl:BAABLgAECn8UAAIIAAgJQA/2AwClAQAIAAgJQA/2AwClAQAAAA==.Dibsy:BAABLgAECn8gAAIVAAcJax1GFQBCAgAVAAcJax1GFQBCAgAAAA==.Diri:BAAALgADCgcJBwABLgAECgkJHgAWAGsUAA==.Dis:BAAALgADCggJDgABLgAECggJHwAXADQKAA==.Disgrace:BAAALgAECgYJEQAAAA==.',
Dm='Dmossyoak:BAAALgADCgkJAgAAAA==.',
Do='Donniedipes:BAABLgAECn8XAAIBAAgJWw6JGABPAQABAAgJWw6JGABPAQAAAA==.Dookiez:BAEBLgAECn8ZAAIFAAgJnSNpAgAmAwAFAAgJnSNpAgAmAwABLgAFFAIJAgAOAAAAAA==.Doublade:BAAALgAECgcJBwAAAA==.Doubledragin:BAABLgAECn8UAAMYAAYJ+xVjKgBrAQAYAAYJ+xVjKgBrAQAZAAMJ6gKFNgBiAAAAAA==.',
Dr='Dracantar:BAAALgADCgUJBQAAAA==.Dracotako:BAAALgAECgYJCgAAAA==.Dractini:BAABLgAECn8WAAMaAAgJvQrIJABSAQAaAAcJXAvIJABSAQAYAAcJegj4MQA4AQABLgAFFAYJFgAPAPoKAA==.Draeneiamin:BAAALgADCgMJAwABLgAECgEJAQAOAAAAAA==.Dragfan:BAAALgAECgIJAgAAAA==.Dragonsniper:BAAALgAECgQJBAAAAA==.Dragore:BAABLgAECn8ZAAIEAAYJthuyNwDIAQAEAAYJthuyNwDIAQAAAA==.Druidgirls:BAABLgAECn8lAAIDAAkJWhfHKgAGAgADAAkJWhfHKgAGAgAAAA==.Dràugluin:BAAALgAFFAEJAQAAAA==.',
Du='Duasoras:BAABLgAECn8XAAIbAAgJ8AE+WwAdAQAbAAgJ8AE+WwAdAQAAAA==.Duelist:BAAALgADCgUJBQAAAA==.Dundlen:BAAALgADCggJDwABLgAECgYJFwAcAPEfAA==.Dunvel:BAAALgAECgMJAwAAAA==.Durogdem:BAAALgAECgIJBAAAAA==.',
Dy='Dynamite:BAAALgAECgEJAQAAAA==.',
Ea='Earthaggie:BAAALgADCgMJBgAAAA==.',
Ed='Edea:BAAALgAECgEJAQAAAA==.',
El='Elaelta:BAAALgAECgMJAwAAAA==.Eleetmage:BAAALgAECgEJAQAAAA==.Elenora:BAABLgAECn8dAAIXAAcJkwSoEwDDAAAXAAcJkwSoEwDDAAAAAA==.Elesity:BAAALgADCgEJAQABLgAFFAMJBwAOAAAAAA==.Elye:BAAALgADCgYJBgABLgAECgUJEQAOAAAAAA==.',
Em='Emer:BAABLgAECn8fAAMXAAgJNAr9OgBJAQAXAAcJnwv9OgBJAQADAAcJtgF0jwCyAAAAAA==.',
En='Encore:BAABLgAECn8cAAIDAAYJcw/mXgA1AQADAAYJcw/mXgA1AQAAAA==.',
Eo='Eousphorus:BAACLgAFFH8FAAIGAAMJFQ96FADuAAAGAAMJFQ96FADuAAAuAAQKfx4AAgYACAnRHvg0AJ8CAAYACAnRHvg0AJ8CAAAA.',
Er='Erathen:BAAALgAECgUJBAAAAA==.Eridi:BAAALgADCgEJAQAAAA==.Eroenice:BAAALgAECgQJBAAAAA==.',
Et='Etile:BAAALgADCgkJFgAAAA==.',
Ev='Evelleion:BAAALgAECgQJBwAAAA==.',
Ex='Exoticlord:BAAALgAECgYJEgAAAA==.',
Fa='Failagos:BAAALgADCgMJAwAAAA==.Fallujah:BAAALgADCgUJBQAAAA==.',
Fe='Felicene:BAABLgAECn8XAAIdAAcJ0iBIBwB4AgAdAAcJ0iBIBwB4AgAAAA==.Fellynn:BAABLgAECn8lAAIeAAgJkiWfAABbAwAeAAgJkiWfAABbAwAAAA==.',
Fi='Fieperskaivu:BAABLgAECn8XAAMHAAcJvB8PIgCFAgAHAAcJvB8PIgCFAgAIAAUJMRqcNQAxAQAAAA==.Fierygrace:BAAALgADCgYJBgAAAA==.Firefalco:BAAALgADCggJCQAAAA==.',
Fl='Flameth:BAABLgAECn8ZAAIRAAgJRArZGQBFAQARAAgJRArZGQBFAQAAAA==.Flamingbunz:BAAALgAECgIJAgAAAA==.Flashblood:BAABLgAECn8gAAMEAAgJTyTWEADKAgAEAAgJTiTWEADKAgAKAAMJ8SKLGAA0AQAAAA==.Flashers:BAAALgAECggJBwAAAA==.Flavortown:BAAALgADCggJCQAAAA==.',
Fo='Forgiven:BAABLgAECn8VAAICAAcJqBrQVADjAQACAAcJqBrQVADjAQAAAA==.Foxtrót:BAAALgAECgYJCQABLgAECgcJGgALAIsgAA==.',
Fr='Freeb:BAAALgADCgUJCAABLgAECgcJHQACAEsEAA==.Freebzz:BAAALgADCgQJBwABLgAECgcJHQACAEsEAA==.Freezrorburn:BAAALgAECgQJBQAAAA==.Frostyndikit:BAAALgAECgMJAwAAAA==.',
Fu='Fu:BAAALgADCgUJBQAAAA==.Fumanchu:BAABLgAECn8aAAILAAcJiyCZCQCAAgALAAcJiyCZCQCAAgAAAA==.',
Ga='Gaamora:BAAALgADCgMJBgAAAA==.Galadore:BAAALgADCgIJAwAAAA==.Garagos:BAABLgAECn8lAAIfAAgJJx3eAAAKAgAfAAgJJx3eAAAKAgAAAA==.Gatherina:BAAALgAECgIJAgABLgAECgcJFwAHALwfAA==.',
Ge='Gebuss:BAABLgAECn8VAAIfAAcJLSWvAgDCAgAfAAcJLSWvAgDCAgAAAA==.Gempally:BAAALgADCgMJBgAAAA==.',
Gh='Ghorynv:BAAALgAECgYJBgAAAA==.',
Gi='Giah:BAAALgADCgkJEgAAAA==.Giborim:BAAALgADCgEJAQAAAA==.Gilford:BAAALgADCgUJBQAAAA==.',
Gl='Glavela:BAAALgAECgQJBwAAAA==.Gloomfist:BAAALgAECgUJEQAAAQ==.',
Go='Goochaddi:BAAALgADCgMJAwABLgAECgUJBQAOAAAAAA==.',
Gu='Gulivar:BAAALgAECgQJBAABLgAECgUJDwAOAAAAAA==.',
Ha='Halfrican:BAAALgAECgQJBAAAAA==.Halifaxx:BAABLgAECn8XAAMcAAYJ8R/QAgAKAgAcAAYJ8R/QAgAKAgAGAAEJAACWdwAAAAAAAA==.Harambee:BAAALgAECgEJAQABLgAECggJDQAOAAAAAA==.Harmaa:BAAALgAECgQJBwAAAA==.Hawknor:BAAALgAECgUJCwAAAA==.',
He='Healenya:BAAALgAECgcJBgAAAA==.Healthcare:BAAALgAECgcJDwABLgAFFAYJFgAPAPoKAA==.Healywilly:BAAALgADCggJDwAAAA==.Herm:BAABLgAECn8lAAIVAAgJRCOOBwADAwAVAAgJRCOOBwADAwAAAA==.',
Hi='Highbear:BAAALgAECgEJAQAAAA==.Hiryu:BAAALgADCgYJBgAAAA==.',
Ho='Holyfaxx:BAAALgADCgcJBwAAAA==.Holymidget:BAAALgADCggJDQAAAA==.Holysky:BAAALgAECgMJAwAAAA==.Holytim:BAABLgAECn8fAAMgAAgJDxiiBwBzAQAgAAgJcBaiBwBzAQAPAAYJ4RCJEADlAAAAAA==.Honnik:BAABLgAECn8aAAIfAAkJ6g4WBAB0AgAfAAkJ6g4WBAB0AgAAAA==.Hortance:BAAALgAECgcJBwAAAA==.Hothot:BAAALgAECgQJBQAAAA==.Hotsndots:BAAALgAECgEJAQAAAA==.Houndoom:BAABLgAECn8cAAIhAAgJ0BPUBgCSAQAhAAgJ0BPUBgCSAQAAAA==.How:BAABLgAECn8aAAMiAAgJ+xuyDQB7AgAiAAgJ+xuyDQB7AgAVAAEJBwj+gAAvAAAAAA==.',
Hu='Hugspotato:BAAALgADCggJCAAAAA==.Huyrak:BAAALgADCgUJBQAAAA==.',
Hy='Hypoxic:BAAALgAECgYJCgAAAA==.',
Ia='Iah:BAABLgAECn8hAAIFAAgJkwrrDwC5AQAFAAgJkwrrDwC5AQAAAA==.',
Ic='Icastspells:BAAALgADCggJCgAAAA==.Icyveinuser:BAAALgADCgcJHAAAAA==.',
Ig='Ignored:BAAALgAECgYJDwAAAA==.',
Il='Illidæn:BAABLgAECn8UAAIHAAYJ9hDtIgD5AAAHAAYJ9hDtIgD5AAAAAA==.Illistra:BAAALgADCgYJBgAAAA==.',
Im='Impuratus:BAAALgADCgcJDQAAAA==.',
In='Inq:BAAALgAECgUJCwAAAA==.',
Ir='Iridaceaë:BAABLgAECn8UAAMPAAcJyhNgNABtAQAPAAcJyhNgNABtAQAgAAMJHgilRQCMAAABLgAECgcJHgAiAMYjAA==.Ironpaw:BAAALgAECgMJBAAAAA==.Iryris:BAAALgAECgYJDwAAAA==.',
Is='Isedeath:BAABLgAECn8lAAQBAAgJLRycMAB1AgABAAgJLRycMAB1AgAMAAEJ2Bb9BwBMAAAjAAIJYgBqQQBGAAAAAA==.',
Ja='Jabber:BAAALgADCgMJAwAAAA==.Jabul:BAAALgADCgYJBgAAAA==.Jack:BAAALgAECgYJEgAAAA==.Jaegerr:BAAALgAECgYJDQAAAA==.Jalene:BAAALgADCgIJAgAAAA==.Jamonk:BAAALgADCgYJBwABLgADCggJCAAOAAAAAA==.Jamuul:BAAALgADCggJCAAAAA==.Janton:BAABLgAECn8UAAIEAAcJQAYJFAAAAQAEAAcJQAYJFAAAAQAAAA==.Jarrhead:BAAALgAECgQJBAAAAA==.Jastor:BAAALgADCgcJDgAAAA==.',
Je='Jenaveive:BAAALgADCgkJCwAAAA==.Jethli:BAACLgAFFH8IAAIhAAQJPgndDwADAQAhAAQJPgndDwADAQAuAAQKfx8AAiEACAlSGewpALoBACEACAlSGewpALoBAAAA.',
Ji='Jigopocalyps:BAAALgADCgEJAQAAAA==.Jinn:BAAALgADCgYJBAAAAA==.',
Jj='Jjp:BAAALgADCgYJCQAAAA==.',
Jn='Jnex:BAAALgAECgEJAQAAAA==.',
Jo='Jojobeànfire:BAAALgADCgUJBQAAAA==.Joube:BAAALgAECgcJCQAAAA==.',
Ju='Judgepain:BAAALgAECgEJAwAAAA==.Judgmental:BAAALgAECgYJDQAAAA==.Juicytootsie:BAABLgAECn8UAAIGAAYJdwNYBwHtAAAGAAYJdwNYBwHtAAAAAA==.Justifried:BAAALgAECgQJBAAAAA==.',
['Jä']='Jävel:BAAALgAECgUJBgAAAA==.',
Ka='Kaelysong:BAAALgAECgEJAQAAAA==.Kairah:BAAALgADCgkJHAAAAA==.Kairiandel:BAAALgADCgkJDwAAAA==.Kalï:BAAALgAECgYJCAAAAA==.Karaha:BAAALgADCgcJBwAAAA==.Kayllin:BAAALgADCgYJDAAAAA==.Kaysina:BAAALgADCgUJBQAAAA==.',
Ke='Keener:BAAALgAECgUJEAAAAA==.Kelenil:BAAALgAECgEJAQABLgAECgQJBAAOAAAAAA==.Kerrla:BAACLgAFFH8HAAIXAAQJERFuCgBDAQAXAAQJERFuCgBDAQAuAAQKfyYAAhcACAngI58JAPsCABcACAngI58JAPsCAAEuAAMKAQkBAA4AAAAA.Keylleth:BAAALgAECgUJCAAAAA==.',
Kh='Khamari:BAAALgADCgYJBgABLgAECgQJBAAOAAAAAA==.Khamnox:BAAALgAECgQJBAAAAA==.Khlamps:BAAALgADCgUJBQAAAA==.',
Ki='Kielnmsoftly:BAAALgAECgMJAwAAAA==.Kilaia:BAAALgAECgMJBAAAAA==.Kilda:BAAALgADCgcJBwAAAA==.Killerklown:BAAALgAECgUJCAAAAA==.Kirksñiper:BAAALgAECgYJDgAAAA==.Kirru:BAAALgAECgYJEgAAAA==.Kirsty:BAAALgADCgMJAwAAAA==.',
Kl='Klink:BAAALgAECgUJDwAAAA==.',
Kn='Knoble:BAAALgAECgEJAwAAAA==.',
Kr='Kreatan:BAAALgADCgUJBwAAAA==.Kreaton:BAAALgAECgYJCgAAAA==.Krel:BAAALgAECgEJAQAAAA==.Kryntoo:BAAALgADCggJCAAAAA==.',
Ks='Kshatriya:BAAALgADCgQJBAAAAA==.',
Ku='Kuchikix:BAAALgADCgEJAQAAAA==.Kuchíki:BAABLgAECn8YAAIiAAcJNg5nCwAxAQAiAAcJNg5nCwAxAQAAAA==.Kushynuggles:BAAALgADCgEJAQAAAA==.',
Kw='Kwag:BAAALgAECgcJBgAAAA==.',
La='Laaklem:BAAALgADCgkJHgAAAA==.Laei:BAAALgAECggJCAAAAA==.Lagerthaa:BAAALgADCgIJAgAAAA==.Laserfingies:BAAALgAECgUJBQAAAA==.Lastsun:BAAALgAECgEJAQAAAA==.Lauridana:BAAALgADCgEJAQAAAA==.Lavacakes:BAABLgAECn8jAAIbAAgJ2SS/AwA6AwAbAAgJ2SS/AwA6AwAAAA==.Lazaren:BAAALgADCgMJAwAAAA==.Lazyboy:BAABLgAECn8ZAAIEAAcJpR4EHABtAgAEAAcJpR4EHABtAgAAAA==.',
Le='Lelantoz:BAAALgAECgYJEgAAAA==.Leliel:BAAALgADCgEJAQAAAA==.Lezibean:BAAALgADCgcJBwABLgADCggJCAAOAAAAAA==.',
Li='Lidan:BAAALgAECgYJDwAAAA==.Liebli:BAAALgAECgQJBAAAAA==.Liffry:BAAALgADCgEJAQAAAA==.Lilena:BAAALgADCgkJJgAAAA==.Lilnao:BAAALgAECgYJBgAAAA==.Linaeni:BAAALgAECgQJBAAAAA==.Linaradice:BAAALgAECgYJBgAAAA==.Linkinbiox:BAAALgAECgQJBgAAAA==.',
Lo='Logyn:BAAALgADCgYJBgAAAA==.Lore:BAABLgAECn8VAAIGAAYJtxQyoQCVAQAGAAYJtxQyoQCVAQAAAA==.Lotsalock:BAAALgADCgcJCAAAAA==.',
Lu='Lululemons:BAAALgAECgMJBAAAAA==.',
Ly='Lyphysia:BAAALgAECgcJDQAAAA==.Lyrelia:BAAALgAECgUJCwAAAA==.Lyssiarose:BAAALgAECgUJCwAAAA==.',
Ma='Mack:BAAALgADCgEJAQAAAA==.Madbones:BAABLgAECn8WAAMRAAYJ+RZdFQBlAQARAAYJtBNdFQBlAQATAAMJXxqLEwD2AAAAAA==.Mado:BAAALgAECgcJDAAAAA==.Maeveracy:BAAALgADCgUJBQAAAA==.Mageijuana:BAAALgAECgYJEgAAAA==.Magicky:BAAALgAECgUJDAAAAA==.Magicsauce:BAAALgAECgYJBwAAAA==.Mahlkier:BAAALgADCgMJBgAAAA==.Maikego:BAAALgADCgcJFAAAAA==.Malchelo:BAAALgAECgQJBgAAAA==.Malfhunter:BAABLgAECn8nAAINAAkJPBhDEwCYAgANAAkJPBhDEwCYAgAAAA==.Manabender:BAAALgAECgIJAgAAAA==.Mangolassi:BAAALgADCgEJAQAAAA==.Manofwood:BAAALgAFFAIJAgAAAA==.Mantodea:BAAALgADCgkJCgAAAA==.Manus:BAAALgAECgMJBAAAAA==.Maranatha:BAAALgADCgEJAQAAAA==.Marossa:BAAALgADCgMJAwAAAA==.Marymae:BAAALgADCgMJBgAAAA==.Masskiller:BAAALgADCgIJAgAAAA==.Masumi:BAAALgADCgEJAQAAAA==.Mattikus:BAAALgADCgcJBAAAAA==.Maximilion:BAAALgAECgIJAgAAAA==.',
Me='Megrim:BAAALgADCgIJAwAAAA==.Mehrartz:BAAALgADCgYJCwAAAA==.Merdocki:BAABLgAECn8lAAMSAAgJ4SHEDwDSAQASAAUJOh/EDwDSAQARAAUJYCGrEwBzAQAAAA==.Merdre:BAABLgAECn8oAAMPAAgJTBzSAgAzAgAPAAgJTBzSAgAzAgAQAAUJAAIDSwCtAAAAAA==.Mertele:BAAALgADCggJFwAAAA==.Messörem:BAAALgADCgYJBgAAAA==.Metasavage:BAAALgAECgQJBAABLgAECgUJBQAOAAAAAA==.',
Mi='Michealhunt:BAAALgAECgEJAQAAAA==.Midory:BAAALgADCgQJBAAAAA==.Mikimukka:BAAALgADCgIJAwAAAA==.Milim:BAAALgAECgEJAQABLgAECgUJBQAOAAAAAA==.Milkymocha:BAAALgAECgYJEgAAAA==.Minus:BAAALgADCgMJAwAAAA==.Misfitjoker:BAAALgAECgEJAQAAAA==.Misscorona:BAAALgADCgQJBQAAAA==.Mistyque:BAAALgAECgQJCgAAAA==.Mithrond:BAAALgADCggJCgABLgAECgEJAQAOAAAAAA==.',
Mo='Modercai:BAAALgAECgMJAwAAAA==.Morcant:BAAALgAECgUJCQAAAA==.Morhg:BAABLgAECn8ZAAMSAAcJ/wZeBAATAQASAAcJ3QZeBAATAQARAAYJ6QV9qQAGAQAAAA==.Morianoley:BAAALgADCggJCwAAAA==.Morlu:BAABLgAECn8WAAIEAAYJUSIWIQBKAgAEAAYJUSIWIQBKAgAAAA==.',
Ms='Msdonnapally:BAAALgAECgMJAwAAAA==.',
Mu='Mugnar:BAAALgADCgcJBwAAAA==.',
My='Myn:BAAALgAECgQJBAAAAA==.',
Na='Nadirya:BAEALgAECgcJCQABLgAFFAQJCAAEABkTAA==.Nazkrul:BAAALgADCgMJAwAAAA==.',
Ne='Nellykorda:BAAALgAECgEJAQAAAA==.Neodruid:BAAALgAECgUJCgAAAA==.Nexxicus:BAAALgADCgMJAwAAAA==.',
Ni='Nightlywomen:BAAALgADCgcJDAAAAA==.Nightmehr:BAABLgAECn8gAAIGAAkJ0iF3EABFAwAGAAkJ0iF3EABFAwAAAA==.Nightphaze:BAAALgAECgEJAQAAAA==.Nihm:BAAALgADCgQJBAAAAA==.Nikolatte:BAAALgAECgEJAwAAAA==.Nimda:BAABLgAECn8aAAIBAAgJfiFgGwDZAgABAAgJfiFgGwDZAgAAAA==.',
No='Nosaj:BAAALgADCgcJCAAAAA==.',
Nu='Nullex:BAAALgAECgYJEgAAAA==.',
Ny='Nyki:BAAALgADCgMJAwAAAA==.',
Ob='Oberon:BAAALgADCgYJBgAAAA==.',
Od='Odlaw:BAAALgAECgUJBgAAAA==.',
Ol='Olaria:BAAALgAECgMJAwABLgAECgUJDQAOAAAAAA==.Oldsaggins:BAAALgAECgMJBAAAAA==.Olikel:BAAALgADCgEJAQAAAA==.Ollymay:BAAALgAECgYJBgABLgAECggJEwAOAAAAAA==.Olm:BAAALgADCggJCAAAAA==.',
On='Onedruidtion:BAAALgADCgYJBgAAAA==.',
Op='Ophekins:BAAALgADCgcJCwAAAA==.',
Or='Orcman:BAAALgAECgEJAQAAAA==.Orheo:BAAALgADCgQJBAAAAA==.Originalchip:BAAALgAECgIJAgAAAA==.Orionmoon:BAAALgADCgkJDgAAAA==.Orlos:BAAALgAECgUJDQAAAA==.Oräkk:BAABLgAECn8VAAILAAcJFB1RDQA2AgALAAcJFB1RDQA2AgAAAA==.',
Os='Osrs:BAAALgAECgMJAwAAAA==.',
Ox='Oxelmorphs:BAAALgADCgcJCAAAAA==.',
Pa='Padrin:BAAALgAECgYJDwAAAA==.Palehorsemen:BAAALgAECgUJCwAAAA==.Pandaberry:BAAALgADCgIJAQAAAA==.Pandapaws:BAABLgAECn8dAAIbAAgJqyAoDAC/AgAbAAgJqyAoDAC/AgAAAA==.Papawaas:BAAALgADCgMJAwAAAA==.Parthal:BAAALgAECgYJDQAAAA==.Partylock:BAAALgAECgMJAwABLgAECgYJBgAOAAAAAA==.Partyshooter:BAAALgAECgYJBgAAAA==.Patmage:BAABLgAECn8WAAIGAAYJ2hh0hQDHAQAGAAYJ2hh0hQDHAQABLgAFFAMJBwAXADsRAA==.',
Pd='Pdiddi:BAABLgAECn8YAAMMAAYJqCD1BAD6AQAMAAYJqCD1BAD6AQABAAYJkxf1GABMAQAAAA==.',
Pe='Peed:BAAALgAECgYJEQAAAA==.Pellaeon:BAAALgAECgkJEgAAAA==.',
Ph='Phexia:BAAALgAECgUJCAAAAA==.Phrostir:BAAALgAECgkJDAAAAA==.Phylactery:BAABLgAECn8lAAIBAAgJCRpzPQBCAgABAAgJCRpzPQBCAgAAAA==.',
Pi='Pierre:BAACLgAFFH8MAAIkAAQJUBOiBQBJAQAkAAQJUBOiBQBJAQAuAAQKfyAAAyQACAnGId8RAKkCACQACAnGId8RAKkCAA0ABgnpDXFOABYBAAAA.Pillgrimm:BAAALgAECgYJDwAAAA==.Pirotic:BAAALgADCgcJCwAAAA==.',
Po='Poisson:BAABLgAECn8eAAIWAAkJaxSGEQCUAgAWAAkJaxSGEQCUAgAAAA==.Polishdir:BAAALgAECgYJEAAAAA==.Polishduo:BAAALgAFFAEJAQAAAA==.Porzingus:BAAALgADCgcJBwAAAA==.Poxi:BAABLgAECn8WAAIYAAgJDRetEwBHAgAYAAgJDRetEwBHAgAAAA==.',
Pr='Praesidiel:BAAALgAECgcJEwAAAA==.Providence:BAABLgAECn8lAAIIAAkJ5iLkAQB+AwAIAAkJ5iLkAQB+AwAAAA==.Prsr:BAAALgAECgMJAwABLgAFFAQJDAABAHwcAA==.',
Pu='Pudgypaws:BAAALgAECgUJCQAAAA==.Puffed:BAAALgAECgIJAgABLgAECggJKAAPAEwcAA==.Punchkick:BAAALgAECgUJBwAAAA==.Purfukt:BAAALgAECgYJBgAAAA==.',
['På']='Pån:BAAALgAECgEJAQAAAA==.',
['Pè']='Pèwpéw:BAAALgAECgQJBAAAAA==.',
Qu='Quickmend:BAAALgAECgQJBgAAAA==.Quickpal:BAAALgAECgUJBgAAAA==.Quickpaw:BAABLgAECn8kAAIiAAkJOiIVAwBOAwAiAAkJOiIVAwBOAwAAAA==.Quickshot:BAAALgADCgEJAQAAAA==.',
Ra='Raccoons:BAACLgAFFH8OAAIkAAUJQxvnAgBuAQAkAAUJQxvnAgBuAQAuAAQKfxwAAyQACAmzIHkbAGICACQACAmzIHkbAGICAA0AAwkrCd1rAI4AAAAA.Rageproof:BAABLgAECn8dAAICAAcJSwQ7yQD2AAACAAcJSwQ7yQD2AAAAAA==.Ragged:BAAALgAECgkJCwAAAA==.Raidbloom:BAACLgAFFH8JAAIDAAMJhiA2DAAfAQADAAMJhiA2DAAfAQAuAAQKfxkAAgMACAl7I0oGACcDAAMACAl7I0oGACcDAAAA.Rainsinger:BAAALgADCgkJBQAAAA==.Rakroth:BAAALgAECgYJDwAAAA==.Ramook:BAAALgADCgYJCwAAAA==.Randomchar:BAABLgAECn8iAAICAAgJ6gqAGwBJAQACAAgJ6gqAGwBJAQAAAA==.Rankor:BAAALgAECgYJCwABLgAECggJJQABANscAA==.Rastann:BAABLgAECn8iAAICAAkJJyACDgAeAwACAAkJJyACDgAeAwAAAA==.Ratrun:BAAALgADCgYJBQAAAA==.Raycharles:BAAALgAECgYJAQAAAA==.',
Re='Realir:BAAALgAECgcJDgAAAA==.Reapertoo:BAACLgAFFH8NAAIBAAQJ7iCZBwCUAQABAAQJ7iCZBwCUAQAuAAQKfygAAwEACQkrI4MHAGQDAAEACQkrI4MHAGQDAAwAAQlmGZsWADYAAAAA.Recreant:BAAALgADCgYJAQAAAA==.Redbaron:BAABLgAECn8bAAIIAAgJnROlAwCxAQAIAAgJnROlAwCxAQAAAA==.Regeth:BAAALgAECgcJEwAAAA==.Repyns:BAACLgAFFH8YAAQRAAcJeh1aAwDuAQARAAYJbB5aAwDuAQASAAQJDBysBQAWAQATAAEJAADJBgBPAAAuAAQKfx4ABBEACQnwJcMIADsDABEACAnwJcMIADsDABIAAwnzIoIpABwBABMAAwlrH4gRABUBAAAA.Rethul:BAAALgAECgYJEgAAAA==.Retsü:BAAALgAECgcJCAABLgAFFAYJFgAPAPoKAA==.',
Rh='Rhhonn:BAAALgAECgYJBgAAAA==.Rhollor:BAAALgAECgMJAwAAAA==.',
Ri='Riani:BAAALgADCgUJBQAAAA==.Ridic:BAABLgAECn8lAAIBAAgJ2xzzBwAAAgABAAgJ2xzzBwAAAgAAAA==.Rimeblade:BAAALgADCgkJGAAAAA==.',
Ro='Robutinblue:BAABLgAECn8YAAIGAAgJLx9aJQDdAgAGAAgJLx9aJQDdAgAAAA==.Rocklesnar:BAAALgAECgMJAwAAAA==.Rondle:BAAALgAECgIJAgAAAA==.Rozalin:BAABLgAECn8lAAIGAAgJtCXeCgBtAwAGAAgJtCXeCgBtAwAAAA==.Rozalinamoon:BAAALgAECgIJAgAAAA==.',
Ru='Ruffprophet:BAAALgAECgEJAQAAAA==.Rugelach:BAEALgAECgEJAQAAAA==.Rumi:BAAALgAECgYJEgAAAA==.Rurouni:BAAALgADCgcJBwAAAA==.',
Ry='Ryoshi:BAABLgAECn8lAAIlAAgJDyAhAwD9AgAlAAgJDyAhAwD9AgAAAA==.',
Sa='Sabotender:BAAALgADCgkJEAAAAA==.Sacredragon:BAAALgADCgcJDgAAAA==.Sacredswords:BAABLgAECn8YAAIEAAgJIh7/FQCdAgAEAAgJIh7/FQCdAgAAAA==.Saeys:BAAALgADCgMJAwAAAA==.Sandscale:BAAALgADCggJCAAAAA==.Sannctuary:BAAALgAECgUJCgAAAA==.Sapphiremist:BAAALgAECgQJBgAAAA==.Sauerkraut:BAAALgAECgcJAQAAAA==.Savagesin:BAAALgAECggJDgABLgAECgUJBQAOAAAAAA==.Sayen:BAAALgADCgkJCQAAAA==.',
Sc='Scachity:BAAALgAECgYJEgAAAA==.Scarekroe:BAABLgAECn8VAAMVAAcJCxyRGAAeAgAVAAcJCxyRGAAeAgAhAAEJixR0iQAzAAAAAA==.Schein:BAAALgADCgMJAwAAAA==.Scratchers:BAABLgAECn8eAAIXAAgJ4iLNBgArAwAXAAgJ4iLNBgArAwAAAA==.',
Se='Seelina:BAAALgADCgYJBgAAAA==.Selanni:BAAALgADCgcJCAAAAA==.Sepulchre:BAAALgADCgkJCQAAAA==.Serlotte:BAAALgADCgcJEQAAAA==.',
Sh='Shadowish:BAAALgADCgEJAQAAAA==.Shadunx:BAAALgADCgIJAgABLgAECgMJAwAOAAAAAA==.Shamaroo:BAAALgAECgUJBQAAAA==.Shaundakul:BAAALgADCgkJJgAAAA==.Shephion:BAAALgADCgkJEgABLgAECggJJQAVAEQjAA==.Shiddydeps:BAAALgADCgIJAgAAAA==.Shiee:BAAALgADCgEJAQAAAA==.Shortnstack:BAAALgAECgQJBwAAAA==.Shãdow:BAAALgAECgYJCAAAAA==.',
Si='Sidetracked:BAAALgAECgcJEwAAAA==.Silanah:BAABLgAECn8lAAIhAAgJ2RtrBQC4AQAhAAgJ2RtrBQC4AQAAAA==.Silverheart:BAAALgAECgIJBgAAAA==.Silvershade:BAAALgADCgEJAQAAAA==.',
Sk='Skawalker:BAABLgAECn8hAAMDAAkJ2iD9BQAtAwADAAkJ2iD9BQAtAwAdAAQJwg+RCADAAAAAAA==.Skyleebaby:BAAALgADCgcJBwAAAA==.',
Sl='Slashers:BAAALgADCgkJCQABLgAECggJHgAXAOIiAA==.Slaynne:BAABLgAECn8lAAMEAAgJcSSDCAAkAwAEAAgJcSSDCAAkAwAKAAEJvQhBRAAwAAAAAA==.Sleven:BAAALgAECgUJBwABLgAFFAEJAQAOAAAAAA==.Slowfel:BAAALgADCgcJBwAAAA==.',
Sm='Smábes:BAAALgAECgQJBwAAAA==.Smäug:BAACLgAFFH8KAAMYAAUJQBe8CgBJAQAYAAQJQBe8CgBJAQAZAAEJAACfBwB1AAAuAAQKfx8ABBkACAnRI9sEALUCABkABwlbI9sEALUCABgABAmJItAkAJYBABoABwkcBakmAEABAAAA.',
Sn='Snobaws:BAAALgAECgcJBwAAAA==.',
So='Sockz:BAABLgAECn8bAAIWAAgJfBm4FABtAgAWAAgJfBm4FABtAgAAAA==.Solria:BAABLgAECn8VAAIPAAgJhBL/BQC7AQAPAAgJhBL/BQC7AQAAAA==.Solrosenborg:BAABLgAECn8bAAIBAAcJ7R1GDwCdAQABAAcJ7R1GDwCdAQAAAA==.Solrosenburg:BAAALgAECgYJBwABLgAECgcJGwABAO0dAA==.Sondreman:BAAALgAECgcJEAAAAA==.Sorcereo:BAAALgADCgIJBQAAAA==.',
Sp='Spicychip:BAAALgADCgQJBAAAAA==.Spintwowin:BAAALgADCgUJBQAAAA==.Splashers:BAAALgADCgQJBAAAAA==.Spærkle:BAAALgAECgUJBQAAAA==.',
Sq='Squirreltag:BAAALgAECgUJCQAAAA==.',
Sr='Srmorphsalot:BAAALgAECgEJAQABLgAFFAQJDAAkAFATAA==.',
St='Starnex:BAAALgADCgYJAQAAAA==.Statyrea:BAAALgADCgkJCgAAAA==.Stomped:BAAALgAECgcJDQAAAA==.Strikes:BAAALgAECgIJAgABLgAECggJJQAeAJIlAA==.Stromlac:BAAALgADCgYJBgAAAA==.Styx:BAACLgAFFH8IAAILAAMJJCEXBQAjAQALAAMJJCEXBQAjAQAuAAQKfyAAAgsACAlKJqkBAGoDAAsACAlKJqkBAGoDAAAA.',
Su='Sukfoot:BAAALgAECgMJAwAAAA==.Sumbatadh:BAAALgAECgYJDAAAAA==.Supergooner:BAAALgADCgIJAgABLgAFFAQJDAAVALoWAA==.',
Sw='Swiftsoul:BAAALgADCgEJAQAAAA==.',
Sy='Sybexia:BAAALgAECgEJAQAAAA==.Sylvestris:BAAALgAECgYJDgAAAA==.',
Ta='Tabcast:BAAALgADCgUJBQAAAA==.Tacodad:BAAALgAECgQJBAAAAA==.Tacofart:BAAALgADCgMJAwAAAA==.Tacos:BAAALgAECgYJDwAAAA==.Tacotitan:BAAALgAECgkJBgAAAA==.Tailas:BAAALgAECgIJAgAAAA==.Taiyana:BAAALgADCgcJDgAAAA==.Talanthir:BAAALgADCgMJAwAAAA==.Tangie:BAAALgADCgkJFQAAAA==.Tankjob:BAAALgAECgQJDAAAAA==.Tanklorswift:BAAALgAECgEJAQAAAA==.Taojin:BAAALgAECgYJDAAAAA==.Tapandsap:BAAALgAECgEJAQAAAA==.Tatsuyâ:BAAALgADCgYJCwAAAA==.',
Te='Teapot:BAAALgAECgEJAQAAAA==.Tedoseirum:BAABLgAECn8XAAIIAAgJuSRmAwBNAwAIAAgJuSRmAwBNAwAAAA==.Tengenthas:BAAALgAECgEJAQAAAA==.Terpu:BAAALgAECgMJBAAAAA==.Testicuhls:BAAALgAECgYJDwAAAA==.Texasbilly:BAAALgADCgYJCAAAAA==.Texasredneck:BAAALgADCgQJAwAAAA==.',
Th='Thalchy:BAAALgAECgYJDAAAAA==.Thaydel:BAAALgADCgMJAwAAAA==.Thedtwo:BAAALgAECgYJEwAAAA==.Thelizzah:BAAALgAECgcJDAAAAA==.Thelvaris:BAAALgAECgIJAgAAAA==.Thorgarrus:BAABLgAECn8hAAICAAkJoR2yGADVAgACAAkJoR2yGADVAgAAAA==.',
Ti='Tigerwoodz:BAAALgAECgMJBAAAAA==.Timfist:BAAALgAECgEJAQAAAA==.Tinytrina:BAAALgADCgYJBgAAAA==.',
To='Toddie:BAABLgAECn8aAAMkAAgJjhrSBgD/AQAkAAgJjhrSBgD/AQANAAMJugxWbQCJAAAAAA==.Tolkein:BAAALgADCgEJAQAAAA==.Tommyj:BAAALgAECgQJBAAAAA==.Torep:BAAALgAECgQJBAAAAA==.Tormod:BAAALgAECgYJEgAAAA==.Tormodd:BAAALgAECgUJDQAAAA==.Torvaldt:BAAALgADCgIJAgABLgAECggJGgAkAI4aAA==.',
Tr='Traedea:BAAALgAECgYJCQAAAA==.Traps:BAAALgAECgEJAQAAAA==.Trashypanda:BAACLgAFFH8MAAImAAQJLR4HAACGAQAmAAQJLR4HAACGAQAuAAQKfyMAAiYACAl2JHsAADQDACYACAl2JHsAADQDAAAA.Trinagirl:BAAALgADCgIJAgAAAA==.Tristanyia:BAAALgAECgYJDAAAAA==.Troolen:BAAALgADCgkJHwAAAA==.Tryana:BAAALgAECgcJEQAAAA==.Trystiania:BAAALgAECgYJBgAAAA==.',
Ts='Tseraphim:BAAALgADCgMJBAAAAA==.',
Tt='Tt:BAAALgAECggJDgAAAA==.',
Tu='Turcomund:BAAALgADCgIJAgAAAA==.',
Tw='Twentynein:BAAALgADCgkJHgAAAA==.Twentynine:BAABLgAECn8lAAMNAAgJ4x05GwBMAgANAAcJnhw5GwBMAgAkAAcJxBQcHQAXAQAAAA==.',
Ty='Tyledis:BAAALgADCgkJJQABLgAECggJJQAhANkbAA==.Tyr:BAACLgAFFH8IAAInAAMJZxbWDgAAAQAnAAMJZxbWDgAAAQAuAAQKfx8AAycACQnUHbcMANICACcACQnUHbcMANICABsAAQlwBdswACcAAAAA.Tyrandi:BAAALgAECgMJAwAAAA==.Tyrnova:BAAALgAECgQJCAAAAA==.Tyrsa:BAAALgAECgQJBwAAAA==.',
Tz='Tzneetch:BAAALgADCgEJAwAAAA==.',
['Tï']='Tïnk:BAABLgAECn8aAAIHAAgJ+xMITQDBAQAHAAgJ+xMITQDBAQAAAA==.',
['Tö']='Töshïrö:BAAALgAECgMJBQAAAA==.',
Ub='Ubel:BAAALgADCgEJAwAAAA==.',
Ud='Udderlee:BAAALgAECgYJEQAAAA==.',
Uh='Uhope:BAAALgAECgIJAgAAAA==.',
Uk='Ukog:BAAALgAECgYJEQAAAA==.',
Um='Umbravolt:BAABLgAECn8pAAIoAAkJfyEcAQBYAwAoAAkJfyEcAQBYAwAAAA==.Umineko:BAAALgAECgEJAQAAAA==.',
Un='Unravel:BAAALgADCgMJBgAAAA==.Unrealpriest:BAAALgADCgkJCwAAAA==.Unrealronin:BAAALgAECgYJCwAAAA==.',
Ur='Uruchi:BAAALgADCgEJAQAAAA==.',
Va='Vaelorn:BAABLgAECn8XAAIHAAkJMh/jFADaAgAHAAkJMh/jFADaAgAAAA==.Vaeris:BAAALgAECgEJAQAAAA==.Vakero:BAAALgAECgYJDQAAAA==.Valeriana:BAAALgADCgQJBQAAAA==.Valice:BAAALgAECgEJAQAAAA==.Vapor:BAAALgAECgEJAQAAAA==.Vatheus:BAAALgADCgYJBgAAAA==.',
Ve='Vert:BAAALgADCgYJBgABLgAECgcJGgASAEoTAA==.',
Vi='Vibrance:BAABLgAECn8cAAQaAAgJNCCIBQDwAgAaAAgJNCCIBQDwAgAYAAYJFBrNKgBpAQAZAAIJSRLzMgB+AAAAAA==.Vindicus:BAAALgADCgcJDQAAAA==.Viridesa:BAAALgADCggJCgAAAA==.Vivienne:BAABLgAECn8eAAIpAAgJahFaLADUAQApAAgJahFaLADUAQAAAA==.',
Vo='Voidcore:BAAALgAECggJDwAAAA==.',
Vv='Vv:BAAALgAECgMJAwAAAA==.',
Vy='Vyrinthial:BAAALgADCgUJBwAAAA==.Vyrnath:BAAALgAECgEJAQAAAA==.',
Wa='Walon:BAAALgADCgcJDgABLgAECgQJBAAOAAAAAA==.Warfarmer:BAAALgAECgUJCAAAAA==.Warhawke:BAAALgADCgYJCAAAAA==.',
We='Weak:BAAALgAECgUJCgAAAA==.Weakhand:BAAALgADCgIJAwAAAA==.Webs:BAAALgADCgUJBQAAAA==.Weel:BAABLgAECn8iAAIHAAgJXBwtCgDQAQAHAAgJXBwtCgDQAQAAAA==.',
Wh='Wheresdparty:BAAALgAECgEJAQAAAA==.Whilaanna:BAABLgAECn8VAAMHAAkJKRUQBABUAgAHAAkJKRUQBABUAgAeAAEJRgVWMQAeAAAAAA==.Whis:BAAALgAECgUJCwAAAA==.Whispernight:BAAALgADCgQJBwAAAA==.',
Wi='Widja:BAAALgADCgMJBgAAAA==.Wiilock:BAABLgAECn8dAAIRAAYJ4B4fRAD/AQARAAYJ4B4fRAD/AQAAAA==.Wiivinelight:BAAALgAECgYJCgABLgAECgYJHQARAOAeAA==.Wiivoker:BAAALgAECgUJBAABLgAECgYJHQARAOAeAA==.Wildwhitwlkr:BAAALgADCgIJAgAAAA==.Wilfrid:BAAALgADCgIJAgABLgAFFAEJAQAOAAAAAA==.',
['Wå']='Wåffle:BAAALgAECgEJAQABLgAECgcJFQAfAC0lAA==.',
Xa='Xandari:BAAALgADCgkJDwAAAA==.Xania:BAAALgADCgYJBwAAAA==.',
['Xû']='Xûrû:BAAALgAECgMJAwAAAA==.',
Yc='Yce:BAAALgAECgUJCwAAAA==.',
Yo='Yoker:BAAALgADCgYJCwAAAA==.Yokersen:BAAALgAECgUJBQAAAA==.',
Za='Zaeladen:BAAALgADCgYJCQAAAA==.Zalorea:BAAALgAECgEJAQAAAA==.Zamrog:BAABLgAECn8lAAIJAAkJpB3eAAARAwAJAAkJpB3eAAARAwAAAA==.Zamthyr:BAAALgAECgcJCAABLgAECgkJJQAJAKQdAA==.Zanya:BAAALgADCgYJCQAAAA==.',
Ze='Zeiko:BAAALgADCgYJBgAAAA==.Zellah:BAAALgAECgQJBAAAAA==.Zenez:BAAALgAECgUJCQAAAA==.Zexor:BAAALgADCgYJDwAAAA==.',
Zh='Zhaoyun:BAAALgAECgYJEgAAAA==.',
Zi='Zilkir:BAABLgAECn8lAAMpAAgJMSPcBAAfAwApAAgJMSPcBAAfAwACAAcJAiD0RwALAgAAAA==.Ziran:BAAALgAECgYJCAAAAA==.Zivadhim:BAAALgADCgkJCgAAAA==.',
Zk='Zkollkrusher:BAAALgADCgYJBgAAAA==.Zkullkrushur:BAAALgADCgUJBQAAAA==.Zkvllkrusher:BAAALgADCgEJAQAAAA==.',
Zl='Zlyth:BAAALgAECgEJAQAAAA==.',
Zo='Zooie:BAABLgAECn8ZAAMbAAYJNhlZMwC3AQAbAAYJNhlZMwC3AQAnAAYJUhe8CQBhAQAAAA==.Zould:BAAALgADCggJHgAAAA==.',
Zy='Zyrix:BAAALgADCgQJBAAAAA==.',
['Är']='Ärtrix:BAAALgADCgEJAQAAAA==.',
['Ät']='Ätrixx:BAAALgAECgIJAgAAAA==.',
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
