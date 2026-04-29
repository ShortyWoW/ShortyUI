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

local lookup = {'Paladin-Retribution','DemonHunter-Havoc','Unknown-Unknown','Evoker-Augmentation','Warrior-Fury','Druid-Restoration','Druid-Balance','Priest-Discipline','DemonHunter-Devourer','Paladin-Protection','Rogue-Subtlety','Monk-Windwalker','Monk-Mistweaver','DeathKnight-Unholy','Paladin-Holy','Warlock-Demonology','Warlock-Destruction','Monk-Brewmaster','Warrior-Protection','Shaman-Restoration','Shaman-Elemental','Evoker-Devastation','Mage-Frost','Mage-Arcane','Priest-Holy','Shaman-Enhancement','Hunter-BeastMastery','Priest-Shadow','DeathKnight-Blood','Druid-Guardian','Warlock-Affliction','Rogue-Outlaw','DeathKnight-Frost','DemonHunter-Vengeance','Evoker-Preservation','Warrior-Arms','Hunter-Survival','Hunter-Marksmanship',}
local provider = {region='US',realm='Draka',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Aberaht:BAABLgAECn8hAAIBAAgJ3CKjAgCRAgABAAgJ3CKjAgCRAgAAAA==.',
Ad='Adamaro:BAAALgADCgYJCQAAAA==.',
Ae='Aenastian:BAAALgADCgkJCQABLgAECggJIwACALkeAA==.',
Af='Affrica:BAAALgADCgEJAQABLgAECgMJCQADAAAAAA==.',
Ah='Ahgra:BAABLgAECn8XAAIBAAYJNQqmrgAmAQABAAYJNQqmrgAmAQAAAA==.',
Ak='Akre:BAABLgAECn8cAAIEAAYJQBO9DAAeAQAEAAYJQBO9DAAeAQAAAA==.Akumä:BAAALgADCggJFAAAAA==.',
Al='Aleannia:BAAALgAECgEJAQAAAA==.Alestria:BAAALgAECgUJCwAAAA==.Alibrexia:BAAALgAECgYJCgAAAA==.Alida:BAABLgAECn8YAAIFAAYJdwhXFQDwAAAFAAYJdwhXFQDwAAAAAA==.Allisara:BAAALgADCgkJFgAAAA==.Alysae:BAACLgAFFH8JAAIGAAQJehUbDgAGAQAGAAQJehUbDgAGAQAuAAQKfxsAAwYACAkpHeMdAE8CAAYACAkpHeMdAE8CAAcAAgliB14iADQAAAAA.',
Am='Amabear:BAAALgADCgcJEwABLgAECgQJCAADAAAAAA==.',
An='Anabug:BAAALgAECgMJBQAAAA==.Aniellas:BAAALgAECgIJAgAAAA==.Annalese:BAAALgADCgUJBQABLgAECgIJAwADAAAAAA==.',
Ap='Apushistory:BAABLgAECn8XAAIIAAgJhBrVDwBBAgAIAAgJhBrVDwBBAgAAAA==.',
Ar='Arabeli:BAAALgAECgEJAQAAAA==.Arbyss:BAAALgADCgcJDAAAAA==.Ardatha:BAAALgADCgcJBwAAAA==.',
As='Asterön:BAAALgAECgUJCQAAAA==.Astrocakes:BAAALgAECgMJAwABLgAECgkJHwAJAOcYAA==.',
At='Athenä:BAACLgAFFH8LAAIKAAQJJwpFAQDbAAAKAAQJJwpFAQDbAAAuAAQKfyUAAgoACQn8GvoFAI4CAAoACQn8GvoFAI4CAAAA.Atsuma:BAAALgAECgYJDwAAAA==.',
['Aí']='Aísling:BAAALgAECgQJBAAAAA==.',
Ba='Baboii:BAAALgADCgIJAgAAAA==.Baconmecrazy:BAAALgAECgEJAQAAAA==.Badinngo:BAAALgADCggJCAAAAA==.Bajafresh:BAAALgAECgQJBQAAAA==.Battleshaman:BAAALgADCgYJBgAAAA==.',
Bd='Bd:BAABLgAECn8dAAILAAgJJxU7GABGAgALAAgJJxU7GABGAgAAAA==.',
Be='Benjinana:BAAALgAECgMJCQAAAA==.Betterthanu:BAAALgADCgUJBQABLgADCgYJCgADAAAAAA==.',
Bg='Bg:BAAALgADCgEJAQAAAA==.',
Bi='Bige:BAAALgAECgYJDAAAAA==.Bilo:BAAALgAECgYJCAAAAA==.Bitelyus:BAAALgAECgMJAwAAAA==.',
Bo='Bobius:BAAALgAECgcJBwAAAA==.Bobohizan:BAAALgADCgQJBAAAAA==.Bohde:BAAALgAFFAMJBAAAAA==.Bolognaman:BAAALgADCgYJBgAAAA==.Bombjovi:BAAALgAECgYJEAAAAA==.Bountty:BAAALgAECgQJBAAAAA==.',
Br='Brahmsthoven:BAAALgADCgIJAwAAAA==.Branndhon:BAAALgAECgYJCAAAAA==.',
Bt='Btrflyprncss:BAAALgADCgMJAwAAAA==.',
Bu='Bubblemedic:BAAALgADCgIJAgAAAA==.',
Ca='Cairdamane:BAAALgAECggJEwAAAA==.Calidrina:BAABLgAECn8eAAIJAAcJ8BveOwAFAgAJAAcJ8BveOwAFAgAAAA==.Carm:BAAALgADCgYJEAAAAA==.Caroliná:BAAALgADCgMJAwAAAA==.',
Ce='Celiri:BAABLgAECn8WAAIMAAcJkQZlCwAbAQAMAAcJkQZlCwAbAQAAAA==.Celldrassil:BAAALgAECgYJEgAAAA==.Cereel:BAAALgAECgMJAwABLgAECgkJHwAJAOcYAA==.',
Ch='Chardaney:BAAALgAECgIJAwAAAA==.Cherryontop:BAAALgAECgYJCwAAAA==.',
Ci='Cii:BAAALgAECgQJBAAAAA==.',
Co='Coconutwater:BAAALgADCgUJBQAAAA==.Colandros:BAAALgAECgUJCQAAAA==.Colara:BAAALgAECgEJAQAAAA==.Combobreaker:BAABLgAECn8bAAINAAgJdhVMHgDFAQANAAgJdhVMHgDFAQAAAA==.Comoo:BAAALgADCgIJBQAAAA==.Cowbôy:BAAALgADCgkJEQAAAA==.',
Cr='Crassberry:BAACLgAFFH8IAAIOAAQJohsRJAAFAQAOAAQJohsRJAAFAQAuAAQKfyMAAg4ACQkdJBQFAIMDAA4ACQkdJBQFAIMDAAAA.Crazèd:BAAALgADCgQJBAAAAA==.',
Cy='Cyndal:BAAALgADCgYJBgABLgADCggJEQADAAAAAA==.Cyntu:BAAALgADCgYJBgABLgADCggJEQADAAAAAA==.',
Da='Dada:BAAALgAECgEJAQAAAA==.Dammithells:BAAALgADCgQJBAAAAA==.Dandamar:BAAALgADCggJDwAAAA==.Dankfists:BAAALgAECgUJBQABLgAECggJFwAPAMAYAA==.Dankheal:BAAALgADCgQJBAABLgAECggJFwAPAMAYAA==.Darthrevan:BAAALgAECgQJBwAAAA==.Dasharnkal:BAAALgADCgUJCAAAAA==.Dasvult:BAAALgAECgMJBAAAAA==.Dazex:BAAALgAECgMJBgAAAA==.',
De='Deadpump:BAABLgAECn8UAAMQAAYJwAtRKADvAAAQAAUJMgxRKADvAAARAAQJZwwbOQDQAAAAAA==.Demonsnotkey:BAAALgAECgQJBQAAAA==.Demoxus:BAAALgAECgQJBAAAAA==.Denker:BAAALgADCggJCAAAAA==.Denzvic:BAAALgADCgkJCQAAAA==.Destro:BAAALgAECgEJAQAAAA==.Devilah:BAAALgADCgYJCQAAAA==.',
Dh='Dharm:BAAALgAECgYJEQAAAA==.',
Di='Dialsl:BAAALgADCgUJBQAAAA==.Digbickpanda:BAAALgADCgYJBgABLgAECgkJHwAJAOcYAA==.Disowneege:BAAALgADCgkJEQABLgAFFAQJCwAFAFIgAA==.',
Do='Dotndash:BAAALgADCgIJAgAAAA==.Doubledge:BAAALgADCgIJAgAAAA==.Doublejump:BAABLgAECn8dAAIJAAgJkRixLwA9AgAJAAgJkRixLwA9AgAAAA==.',
Dr='Dragnas:BAAALgAECgYJEAAAAA==.Dragonisa:BAAALgAECgYJBgAAAA==.Dragun:BAAALgADCgIJAgAAAA==.Drakeskid:BAAALgAECgQJBwABLgAECgkJGQASACoaAA==.Drakthall:BAAALgAECgIJAwAAAA==.Dramakiller:BAAALgADCgYJDQAAAA==.Drcornbread:BAAALgAECgMJCQAAAA==.Drcornellia:BAAALgADCgcJCQABLgAECgMJCQADAAAAAA==.Drdarkskin:BAAALgAECgEJAQAAAA==.Drdreggs:BAABLgAECn8fAAMQAAgJXhiVTwDZAQAQAAcJ1RaVTwDZAQARAAQJFxOAMAD4AAAAAA==.Drizztin:BAAALgADCgEJAQAAAA==.Drprominus:BAAALgAECgYJEgAAAA==.Drthargyll:BAAALgADCgYJDgABLgAECgYJEgADAAAAAA==.',
Dy='Dykdanglr:BAAALgADCgYJBgABLgAECgQJCAADAAAAAA==.',
['Dí']='Dígífóx:BAAALgAECgQJBwAAAA==.',
Ea='Earthereal:BAAALgAECgYJEQAAAA==.',
El='Elastar:BAABLgAECn8hAAITAAgJSxmhAgDoAQATAAgJSxmhAgDoAQAAAA==.Ellimist:BAECLgAFFH8LAAIUAAQJRhIpBAAwAQAUAAQJRhIpBAAwAQAuAAQKfx8AAxQACQmJGHsXAFoCABQACQmJGHsXAFoCABUABQk0FwRQAAcBAAAA.Elsan:BAAALgADCgEJAQAAAA==.Elycee:BAAALgAECggJDAAAAA==.Elí:BAAALgAECgMJAwAAAA==.',
En='Encrid:BAAALgAECgUJBgABLgAECgYJFAAWACsjAA==.Enhasa:BAAALgAECggJDgABLgAECgYJFgABAI8fAA==.Enoeht:BAAALgAECgYJEgAAAA==.',
Er='Erazar:BAAALgAECgYJEwAAAA==.Eriah:BAAALgADCgkJCQAAAA==.Erickk:BAABLgAECn8cAAMXAAgJNhogUABHAgAXAAgJ6xYgUABHAgAYAAQJVx1NCwAkAQAAAA==.',
Es='Essense:BAABLgAECn8hAAIZAAgJgiS4AADhAgAZAAgJgiS4AADhAgAAAA==.',
Ex='Exodari:BAABLgAECn8gAAIaAAgJBREMAwCqAQAaAAgJBREMAwCqAQAAAA==.',
Fa='Fabbioh:BAAALgADCgEJAQAAAA==.Fadeddh:BAABLgAECn8fAAIJAAkJ5xhyGwCuAgAJAAkJ5xhyGwCuAgAAAA==.',
Fe='Fearnoevil:BAAALgADCgMJAwAAAA==.Fel:BAAALgAECgYJEAAAAA==.Fellkarras:BAAALgAECgYJCwABLgAECggJGwANAHYVAA==.Fent:BAAALgAECgQJBgAAAA==.',
Fi='Fiddich:BAAALgADCgEJAQAAAA==.Fillthy:BAACLgAFFH8JAAINAAQJeQ6pBAAgAQANAAQJeQ6pBAAgAQAuAAQKfyIAAg0ACQnuIUYDAEgDAA0ACQnuIUYDAEgDAAAA.Finnigann:BAAALgADCgYJCgAAAA==.Firenmylazer:BAAALgADCgMJAwAAAA==.Fizban:BAAALgAECgUJCQABLgAECgcJDAADAAAAAA==.',
Fl='Flappybird:BAAALgAECgIJAgABLgAECgkJHwAJAOcYAA==.Flazz:BAAALgADCgIJAwAAAA==.Flazzan:BAAALgADCgEJAQAAAA==.',
Fo='Four:BAAALgADCgQJBAAAAA==.',
Fr='Frejä:BAAALgAECgQJBQABLgAECgQJDAADAAAAAA==.Freyah:BAAALgADCgYJAQAAAA==.Frostmay:BAAALgAECgIJAgAAAA==.',
Fu='Furrybawlz:BAAALgAECgUJCAABLgAECgYJDQADAAAAAA==.',
Ga='Gadogear:BAAALgAECgYJEwAAAA==.Garlik:BAAALgADCgMJBAAAAA==.',
Gi='Girthrichard:BAAALgAECgYJDAAAAA==.',
Gl='Glassdragon:BAABLgAECn8UAAIBAAcJyAopLADvAAABAAcJyAopLADvAAAAAA==.Gllor:BAAALgADCgIJAgAAAA==.',
Go='Goatcheeze:BAAALgAECgcJDwAAAA==.Goatylocks:BAABLgAECn8XAAIRAAYJFRyxAQCfAQARAAYJFRyxAQCfAQAAAA==.Goldenchild:BAAALgAECgYJBwABLgAECgkJHwAJAOcYAA==.',
Gr='Greatluckydo:BAAALgADCgEJAQAAAA==.',
Gu='Gulen:BAAALgAECgMJBQAAAA==.',
['Gí']='Gíga:BAABLgAECn8XAAIbAAgJ7RPdKQAPAgAbAAgJ7RPdKQAPAgAAAA==.',
Ha='Hanhaine:BAAALgAECgYJBwAAAA==.Hazirat:BAAALgADCgIJAgAAAA==.',
He='Hedlie:BAAALgAECgEJAQAAAA==.Hellenkeller:BAAALgAECgYJEwABLgAFFAQJCwALAAcgAA==.Heloisa:BAAALgAECgMJBAAAAA==.Helrazr:BAAALgAECgYJCQAAAA==.Henshin:BAABLgAECn8iAAMGAAgJHR3XFwB4AgAGAAgJHR3XFwB4AgAHAAEJHguzhwAoAAAAAA==.',
Ho='Holdmykeg:BAAALgADCgYJBgABLgAFFAMJBwAFAEsFAA==.Holyhim:BAAALgADCgIJAgAAAA==.Hottyshmotty:BAAALgAECgEJAQAAAA==.Hourglass:BAAALgAECgYJEwAAAA==.',
Hu='Huntthejuan:BAAALgADCgUJBQAAAA==.',
Ic='Icyowneege:BAAALgADCgUJBQABLgAFFAQJCwAFAFIgAA==.Icywolfy:BAAALgAECgYJBgAAAA==.',
Ig='Igreetyou:BAAALgAECgQJBwAAAA==.',
Il='Illie:BAABLgAECn8hAAIaAAgJFh05AQAjAgAaAAgJFh05AQAjAgAAAA==.Illune:BAABLgAECn8WAAMYAAgJDBMVCQBbAQAYAAYJUg4VCQBbAQAXAAgJ/RJPIABUAQAAAA==.',
Im='Imanbearpig:BAAALgADCgIJAgAAAA==.Imleapingit:BAAALgAECgYJEAAAAA==.',
In='Intoodragons:BAABLgAECn8cAAMEAAgJFBDcHgDMAQAEAAgJFBDcHgDMAQAWAAYJWgX0JAD+AAAAAA==.Inyah:BAAALgAECgIJAgAAAA==.',
Io='Ionzz:BAABLgAECn8eAAMCAAgJ+CCgCADYAgACAAgJ+CCgCADYAgAJAAYJiRIfFwBFAQAAAA==.',
Ir='Iroann:BAAALgAECgUJCAAAAA==.',
Is='Isawarriorr:BAABLgAECn8gAAITAAgJbyODAwAfAwATAAgJbyODAwAfAwAAAA==.Ishaq:BAAALgAECgQJBQAAAA==.Ishkhan:BAAALgAECgEJAQABLgAECgQJBQADAAAAAA==.Ishmael:BAAALgAECgcJCAABLgAECgcJGQAHAEscAA==.Ishwar:BAAALgADCgYJBgAAAA==.',
Ja='Jakytreehorn:BAACLgAFFH8FAAIUAAQJZQTdCADEAAAUAAQJZQTdCADEAAAuAAQKfxgAAxQACQnWEBAoAPABABQACQnWEBAoAPABABUAAQm6A4mRACYAAAAA.Jasher:BAAALgADCgkJCQAAAA==.',
Je='Jenevelle:BAAALgAECgEJAQAAAA==.Jerisil:BAAALgADCgQJBAAAAA==.Jet:BAABLgAECn8WAAIBAAYJjx83SwABAgABAAYJjx83SwABAgAAAA==.',
Ju='Judgecalypso:BAAALgAECgQJBAAAAA==.Julthaenia:BAAALgAECgYJBgABLgAECggJIwACALkeAA==.Justeatjuan:BAAALgAECgMJAwAAAA==.',
Ka='Kagebushin:BAAALgAECgMJBAAAAA==.Kalazin:BAAALgADCggJBwAAAA==.Kalimah:BAAALgADCgMJAwAAAA==.Karnrae:BAAALgAECgUJCgAAAA==.Karynos:BAABLgAECn8cAAMQAAgJwgkoFABuAQAQAAgJoQcoFABuAQARAAcJyQkRIwA/AQAAAA==.Kazmacoryy:BAAALgADCgkJDgAAAA==.',
Ke='Keedis:BAAALgADCgQJBAAAAA==.',
Ki='Kileely:BAAALgAECgMJAwAAAA==.',
Ko='Kodian:BAAALgADCgEJAQAAAA==.Kolypso:BAAALgAECgYJBwAAAA==.Konspiracy:BAAALgAECgYJEgAAAA==.Konvict:BAAALgAECgIJAwABLgAECgYJDQADAAAAAA==.',
Kr='Krataar:BAAALgAECgcJEgAAAA==.Krousvor:BAAALgAECgQJBwAAAA==.Kryph:BAAALgAECgYJDwAAAA==.',
Ku='Kugruk:BAAALgAECgMJBAAAAA==.Kurjo:BAAALgAECgMJBAAAAA==.',
Ky='Kyleschlong:BAAALgAECgMJBQAAAA==.',
['Kä']='Kämpfer:BAABLgAECn8bAAIFAAYJSRi9PQCtAQAFAAYJSRi9PQCtAQAAAA==.',
La='Lafiel:BAABLgAECn8YAAMZAAcJDwo7PABJAQAZAAcJDwo7PABJAQAcAAEJTwXQZwApAAAAAA==.Landazar:BAAALgADCgEJAQAAAA==.Landiedoo:BAAALgAECgkJCQAAAA==.Laverna:BAAALgADCgMJBAAAAA==.',
Le='Lefay:BAAALgADCgcJDAAAAA==.Letsgetwet:BAAALgADCgYJBgAAAA==.',
Li='Liefic:BAAALgAECgYJBwAAAA==.',
Lo='Loadin:BAAALgAECgIJAgAAAA==.Lockaflockå:BAAALgADCgMJAwAAAA==.Lonoh:BAAALgAECgcJEgAAAA==.',
Lu='Lucariø:BAAALgADCgcJDAAAAA==.Lucidbonsai:BAAALgADCggJCAAAAA==.Luckykilla:BAAALgAECgcJEQAAAA==.Lucÿ:BAABLgAECn8iAAMUAAcJrBj3KADsAQAUAAcJrBj3KADsAQAVAAMJEQx6GQCjAAAAAA==.Lurith:BAABLgAECn8eAAMdAAcJzg7MCQDoAAAOAAYJagbPuAARAQAdAAYJthDMCQDoAAAAAA==.Lutreaux:BAAALgADCgEJAQAAAA==.Luxtyrannica:BAAALgAECgQJBwAAAA==.',
Ly='Lydrain:BAAALgAECgEJAQAAAA==.Lysandria:BAABLgAECn8YAAIXAAcJtQsdIgBKAQAXAAcJtQsdIgBKAQAAAA==.',
Ma='Macrosblack:BAAALgADCgMJAwAAAA==.Magearino:BAAALgAECgYJEwAAAA==.Marcopally:BAAALgAECgQJBAAAAA==.Marluxia:BAACLgAFFH8KAAIeAAQJHAazAQDWAAAeAAQJHAazAQDWAAAuAAQKfxoAAh4ACAkjE/MMALgBAB4ACAkjE/MMALgBAAAA.Materfamilia:BAAALgADCggJCAAAAA==.Mattbull:BAABLgAECn8UAAMWAAYJKyNSDQAEAgAWAAYJQiJSDQAEAgAEAAUJ8BriKAB2AQAAAA==.',
Me='Medjrab:BAABLgAECn8kAAIOAAgJeRklBgAjAgAOAAgJeRklBgAjAgAAAA==.Meristem:BAAALgAECgYJEgAAAA==.',
Mi='Miaan:BAAALgADCgYJBgAAAA==.Miette:BAAALgADCgMJAwAAAA==.Mihonk:BAAALgADCgQJBAAAAA==.Mintycrx:BAAALgAECgYJCwAAAA==.Missfist:BAAALgADCgIJAgAAAA==.Mistlocke:BAAALgADCgMJAwAAAA==.',
Mn='Mngwa:BAAALgADCgYJCQAAAA==.',
Mo='Moegu:BAAALgAECgQJBgAAAA==.Mog:BAABLgAECn8cAAQQAAgJ8SCJNAA6AgAQAAYJgCGJNAA6AgARAAMJHBHBNgDbAAAfAAEJACSnJgBXAAAAAA==.Mondgrille:BAAALgADCgkJEgABLgAECgYJDQADAAAAAA==.Monora:BAAALgAECgYJCwAAAA==.Moomoohealz:BAABLgAECn8jAAIHAAgJCiA4DQDGAgAHAAgJCiA4DQDGAgAAAA==.Moonbounds:BAACLgAFFH8LAAIUAAQJ+BuABgBeAQAUAAQJ+BuABgBeAQAuAAQKfy4AAxQACQndJFIDAEQDABQACQndJFIDAEQDABUAAQnZH3J5AF0AAAAA.Mousechief:BAAALgAECgQJCgAAAA==.Moxnix:BAAALgAECgMJAwABLgAECgYJDAADAAAAAA==.Moxxzi:BAAALgAECgQJBQAAAA==.',
Mu='Muhfookinbak:BAAALgAECgYJEAAAAA==.',
My='Myor:BAAALgADCgMJAwAAAA==.',
['Mà']='Màttbull:BAAALgAECgIJAwABLgAECgYJFAAWACsjAA==.',
Na='Naesta:BAAALgAECgIJAgABLgAECggJIQAGAAAgAA==.Naksù:BAAALgAECgIJAgAAAA==.Namal:BAAALgAECgMJBAAAAA==.Narenae:BAABLgAECn8cAAIMAAgJ4yNABABIAwAMAAgJ4yNABABIAwAAAA==.',
Ne='Nefari:BAAALgADCgMJAwAAAA==.Neifeb:BAAALgAECgcJEwAAAA==.',
Ni='Niallivdam:BAAALgAECgYJEwAAAA==.Nightsoul:BAAALgADCgEJAQAAAA==.Ninh:BAABLgAECn8jAAINAAgJAg6LJQCIAQANAAgJAg6LJQCIAQAAAA==.',
No='Nomissius:BAAALgADCgcJDQAAAA==.Notsodemon:BAAALgAECggJEwAAAA==.Notsoevoker:BAAALgADCgMJAwABLgAECggJEwADAAAAAA==.Notsomonk:BAAALgADCgMJAwABLgAECggJEwADAAAAAA==.',
Ny='Nykara:BAAALgADCgMJAwAAAA==.',
Ob='Obvinotagirl:BAAALgAECggJDgAAAA==.',
Og='Ogsikko:BAAALgAECgYJCwABLgAECggJGAAQAJAeAA==.Ogsikkotv:BAABLgAECn8XAAIXAAYJ+hmkhwDCAQAXAAYJ+hmkhwDCAQABLgAECggJGAAQAJAeAA==.',
On='Onebadmutha:BAAALgAECgYJCwAAAA==.Ontop:BAABLgAECn8hAAIbAAgJixsgHABeAgAbAAgJixsgHABeAgAAAA==.',
Or='Orb:BAAALgAECgYJDQAAAA==.Orcfreeza:BAAALgAECgQJDAAAAA==.Ortinks:BAAALgAECgIJAwAAAA==.',
Ow='Owneege:BAACLgAFFH8LAAIFAAQJUiATAQB/AQAFAAQJUiATAQB/AQAuAAQKfy0AAgUACQmsIiACAKEDAAUACQmsIiACAKEDAAAA.',
Pa='Painsaw:BAAALgADCgYJBgAAAA==.Pallinar:BAAALgAECgYJEgAAAA==.Pasquale:BAABLgAECn8eAAISAAcJ2iCxAgAiAgASAAcJ2iCxAgAiAgAAAA==.',
Pe='Pebbles:BAAALgAECgUJBQAAAA==.Pedroia:BAAALgADCgkJIQAAAA==.Pesty:BAAALgAECgMJBwAAAA==.',
Ph='Phe:BAAALgAECgcJDwAAAA==.',
Pi='Pilgrimm:BAACLgAFFH8LAAMLAAQJByDzBAAZAQALAAMJpyDzBAAZAQAgAAEJKh6mAQBiAAAuAAQKfx8AAgsACQl0IrEDAGADAAsACQl0IrEDAGADAAAA.',
Pl='Plaguerott:BAABLgAECn8dAAIhAAgJhgtCAgBhAQAhAAgJhgtCAgBhAQAAAA==.Plusultra:BAAALgADCggJCwAAAA==.',
Po='Poby:BAAALgADCgcJBwAAAA==.Polydh:BAABLgAECn8ZAAIiAAgJkx/RAwCOAgAiAAgJkx/RAwCOAgAAAA==.Poobah:BAAALgAECgYJEQAAAA==.Popscotch:BAAALgAECgcJEgAAAA==.Pouffant:BAABLgAECn8UAAIBAAcJ+BKNXADNAQABAAcJ+BKNXADNAQAAAA==.',
Pr='Pronoz:BAAALgAECgUJDgAAAA==.',
Pu='Punchy:BAAALgADCgEJAQAAAA==.',
Pw='Pwnageddon:BAAALgAECgUJCgAAAA==.Pwnjitsu:BAABLgAECn8hAAIMAAgJQR7uAgD7AQAMAAgJQR7uAgD7AQAAAA==.',
Py='Pyrothermia:BAACLgAFFH8GAAIXAAQJOgy2EwD3AAAXAAQJOgy2EwD3AAAuAAQKfx8AAhcACQmXGYgqAMkCABcACQmXGYgqAMkCAAAA.',
Qt='Qtkillz:BAAALgADCgQJBAAAAA==.',
Ra='Rawhoof:BAABLgAECn8jAAIFAAgJZiIyCgANAwAFAAgJZiIyCgANAwAAAA==.Razak:BAABLgAECn8dAAIaAAcJQh7GAQD5AQAaAAcJQh7GAQD5AQAAAA==.',
Re='Renisa:BAABLgAECn8aAAIJAAgJShlaQgDqAQAJAAgJShlaQgDqAQAAAA==.Retman:BAAALgAECgUJDwAAAA==.Reu:BAAALgAECgUJBwAAAA==.Revlyk:BAAALgAECgYJDwABLgAECggJIwACALkeAA==.',
Ri='Rintaro:BAAALgAECgkJEwAAAA==.',
Ro='Roccot:BAAALgAECgEJAwAAAA==.Roostrr:BAAALgAECgUJDgAAAA==.Rotjaw:BAAALgAECgUJCQAAAA==.Roughedge:BAAALgADCgIJAgAAAA==.',
Ru='Rurik:BAAALgADCggJFwAAAA==.',
['Rè']='Rèjuva:BAAALgAECgcJDAAAAA==.',
['Rî']='Rîcflair:BAAALgAECgcJDgAAAA==.',
Sa='Salidfingers:BAAALgADCgYJBgAAAA==.Sanyakulak:BAAALgADCgcJBwABLgAFFAUJDQAeAJQVAA==.Savathûn:BAAALgAECgQJCAAAAA==.',
Sc='Scalycat:BAABLgAECn8hAAMjAAgJTA+SGQDBAQAjAAgJTA+SGQDBAQAEAAUJnAdRTgCWAAAAAA==.Schalla:BAAALgAECgEJAQAAAA==.Scum:BAAALgAECgYJDQAAAA==.Scòrpìòn:BAAALgADCgcJBgABLgAECggJJAAbAG8YAA==.',
Se='Seancody:BAAALgADCgIJAgAAAA==.Selandria:BAAALgADCgQJBAAAAA==.Senate:BAAALgAECgQJBQAAAA==.',
Sh='Shadowbear:BAAALgAECgQJCAAAAA==.Shadygrump:BAAALgAECgYJEQAAAA==.Shaolincito:BAAALgAECgQJBQAAAA==.Sherrilyn:BAAALgADCgkJFQAAAA==.Shocklocke:BAAALgAECgMJAwAAAA==.',
Si='Sigmachad:BAAALgAECgUJCgAAAA==.Silverocean:BAABLgAECn8eAAIPAAcJZiHsDwCUAgAPAAcJZiHsDwCUAgAAAA==.Silvia:BAAALgADCgUJCQAAAA==.Singularity:BAABLgAECn8gAAITAAgJ9CE9BAAGAwATAAgJ9CE9BAAGAwAAAA==.',
Sk='Skaerx:BAABLgAECn8WAAMFAAYJVBeBQwCXAQAFAAYJ9RWBQwCXAQAkAAQJZhSRHQADAQAAAA==.Skittlez:BAABLgAECn8aAAIlAAcJpiE6AgAGAgAlAAcJpiE6AgAGAgAAAA==.',
Sl='Slootybooty:BAAALgAECgQJBQAAAA==.',
Sm='Smallz:BAAALgAECgUJBgABLgAECgcJDAADAAAAAA==.',
Sn='Snipersmash:BAAALgAECgQJBgAAAA==.Snooptrogg:BAABLgAECn8WAAIFAAcJchEQCgB+AQAFAAcJchEQCgB+AQAAAA==.Snoozumi:BAAALgAFFAEJAgAAAA==.Snuups:BAABLgAECn8gAAIQAAgJgxiGCgDLAQAQAAgJgxiGCgDLAQAAAA==.',
So='Soldiah:BAAALgAECgQJCgAAAA==.Sommbra:BAAALgAECgUJBQAAAA==.Souljax:BAAALgADCgcJBwAAAA==.',
Sp='Spacelaser:BAAALgAECgQJBAAAAA==.',
Sq='Sqwurl:BAAALgADCgQJBAAAAA==.',
St='Steakhaus:BAAALgADCgIJAgAAAA==.Stiros:BAAALgADCgUJBgAAAA==.Stonedragon:BAECLgAFFH8HAAIbAAMJ3xKVCwAGAQAbAAMJ3xKVCwAGAQAuAAQKfyMAAxsACAnNJMwFADEDABsACAnNJMwFADEDACYAAQlqB3GQACoAAAAA.Stormfist:BAAALgAECgMJBQAAAA==.Stormhaven:BAAALgADCggJGwABLgAECgQJBAADAAAAAA==.Stormrender:BAAALgAECgYJDwAAAA==.Stouty:BAAALgADCgMJAwABLgAECgcJFAAWAOkaAA==.',
Su='Sukonamí:BAABLgAECn8dAAIFAAgJyxS6BADsAQAFAAgJyxS6BADsAQAAAA==.Suzhou:BAAALgAECgYJEQAAAA==.Suzoomies:BAAALgADCgcJBwAAAA==.Suzumii:BAAALgAFFAEJAQAAAA==.',
Sw='Sweetcarolin:BAABLgAECn8VAAIOAAgJbBCFXgDXAQAOAAgJbBCFXgDXAQAAAA==.Sweetsmercy:BAAALgAECgQJBQAAAA==.Swisscheese:BAAALgAECgYJEAAAAA==.',
Sy='Syraxa:BAAALgADCggJDAAAAA==.Syril:BAAALgADCgcJDAAAAA==.',
Ta='Tatersaladin:BAAALgADCgMJAwAAAA==.',
Te='Tenlortin:BAAALgADCgIJAgAAAA==.Terragosa:BAAALgAECgYJEAAAAA==.',
Th='Thade:BAABLgAECn8WAAMFAAcJUB5YHwBWAgAFAAcJUB5YHwBWAgAkAAEJ3x11NgBWAAAAAA==.Thaeleon:BAABLgAECn8ZAAMHAAcJSxyYAwD4AQAHAAYJSxyYAwD4AQAGAAYJihz2NADUAQAAAA==.Thaneblade:BAAALgAECgIJAgAAAA==.Thickening:BAAALgAECgQJCwAAAA==.Thope:BAAALgAECgMJAwAAAA==.Thoranubran:BAAALgAECgYJEgAAAA==.Thrivia:BAAALgAECgYJBgAAAA==.',
Ti='Ticklemychin:BAAALgADCgkJFAAAAA==.Tigani:BAAALgADCgUJCQAAAA==.',
To='Tokemaddab:BAAALgADCgUJBQAAAA==.',
Tr='Trainar:BAAALgAECgQJBgAAAA==.Trickybackup:BAAALgADCgMJAwAAAA==.Trondruid:BAAALgADCgYJDQAAAA==.Trooze:BAABLgAECn8UAAIPAAYJJyNyBAAnAgAPAAYJJyNyBAAnAgAAAA==.Trr:BAABLgAECn8pAAIQAAkJmReyIwCFAgAQAAkJmReyIwCFAgAAAA==.Truckzage:BAAALgADCgcJBwABLgAECgcJEQADAAAAAA==.',
Tu='Tuba:BAAALgAECgYJEAAAAA==.Turim:BAAALgADCgQJBAAAAA==.Tusksrus:BAAALgADCgYJDQAAAA==.',
Ty='Tyrlidd:BAAALgAECgYJEQAAAA==.',
Ud='Udon:BAAALgAECgEJAQAAAA==.',
Ul='Ultimazero:BAAALgADCgEJAQAAAA==.',
Un='Unavoidable:BAAALgADCgkJDgAAAA==.Unlikelytale:BAABLgAECn8dAAIUAAgJcCAuCgDXAgAUAAgJcCAuCgDXAgAAAA==.Unmilked:BAAALgADCgYJCgAAAA==.',
Ur='Uricash:BAABLgAECn8jAAIXAAgJxxGsFwCHAQAXAAgJxxGsFwCHAQAAAA==.Urzual:BAABLgAECn8WAAIaAAcJlx2cAgDBAQAaAAcJlx2cAgDBAQAAAA==.',
Va='Vandreynna:BAABLgAECn8jAAICAAgJuR6UCQDIAgACAAgJuR6UCQDIAgAAAA==.',
Ve='Vegèta:BAAALgAECggJDAABLgAECggJJAAbAG8YAA==.Veilaura:BAAALgADCggJDgAAAA==.Velarria:BAABLgAECn8aAAMbAAgJ/SA7FQCOAgAbAAgJ/SA7FQCOAgAlAAQJjwwbIQDSAAAAAA==.Velikan:BAAALgAECgQJBwABLgAECgYJBgADAAAAAA==.Velsiana:BAAALgAECgEJAQAAAA==.Velveetah:BAAALgADCgcJCQABLgAECgMJCQADAAAAAA==.Verita:BAAALgAECgYJEwAAAA==.',
Vi='Viviann:BAABLgAECn8fAAIjAAgJKhGQAwCrAQAjAAgJKhGQAwCrAQAAAA==.',
Vo='Voiager:BAAALgADCgYJCQAAAA==.',
Vr='Vrakal:BAAALgAECgcJCwAAAA==.',
Wa='Wantabehavoc:BAAALgADCgYJBgAAAA==.Wantadeznutz:BAAALgAECgIJAgAAAA==.Warnick:BAAALgADCgQJBQAAAA==.Warraxe:BAAALgADCgUJCAAAAA==.Wayloren:BAABLgAECn8VAAIBAAcJtgXWIQAlAQABAAcJtgXWIQAlAQAAAA==.Wayverly:BAAALgADCgUJBwABLgAECgIJAwADAAAAAA==.',
Wi='Wickathy:BAABLgAECn8bAAIiAAgJ6hieBwALAgAiAAgJ6hieBwALAgAAAA==.',
Wo='Wolfcity:BAAALgADCgEJAQAAAA==.Worstdps:BAAALgADCgcJEAAAAA==.',
Wu='Wuldorr:BAABLgAECn8kAAIBAAgJux1KJACWAgABAAgJux1KJACWAgAAAA==.',
Wy='Wynnifred:BAAALgAECgQJBAAAAA==.',
Xa='Xalatoes:BAAALgAECgMJAwAAAA==.',
Xe='Xethreal:BAAALgADCgMJAwAAAA==.',
Xy='Xype:BAAALgAECgkJEQAAAA==.',
Ya='Yastoria:BAAALgAECgcJEAAAAA==.',
Yi='Yinandtonic:BAAALgADCgEJAQAAAA==.',
Yv='Yvvee:BAAALgADCgcJBwAAAA==.',
Za='Zaalim:BAAALgADCgQJBAAAAA==.Zapdôs:BAAALgAECgQJBAAAAA==.',
Ze='Zephyris:BAAALgAECgQJCwABLgAFFAMJBQABAD4fAA==.',
Zh='Zheng:BAAALgADCgkJCQAAAA==.',
Zi='Zillia:BAAALgADCgMJAwAAAA==.',
Zy='Zyphexd:BAAALgAECgYJDwAAAA==.Zyris:BAAALgADCgcJDQAAAA==.',
['Äs']='Ästro:BAAALgAECgQJBgABLgAECgYJEQADAAAAAA==.',
['Äz']='Äzrael:BAAALgAECgcJCAAAAA==.',
['Åz']='Åznos:BAAALgAECgQJCAAAAA==.',
['Çr']='Çréwüsæðèr:BAAALgAECgYJEQAAAA==.',
['Ðe']='Ðecimus:BAAALgAECgQJCQAAAA==.',
['Ðì']='Ðìaßlo:BAABLgAECn8kAAQbAAgJbxhCEQB0AQAlAAcJWBQ3EQCvAQAbAAcJfRNCEQB0AQAmAAEJXgAGmwAVAAAAAA==.',
['Öb']='Öblïvïöñ:BAAALgADCgcJEAAAAA==.',
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
