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

local lookup = {'Paladin-Retribution','DemonHunter-Havoc','Unknown-Unknown','Evoker-Augmentation','Warrior-Fury','Monk-Windwalker','Druid-Restoration','Druid-Balance','Priest-Discipline','DemonHunter-Devourer','Paladin-Protection','Rogue-Subtlety','DeathKnight-Unholy','Paladin-Holy','Shaman-Elemental','Evoker-Preservation','Monk-Mistweaver','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Shaman-Enhancement','Priest-Holy','Monk-Brewmaster','Warrior-Protection','Shaman-Restoration','Hunter-Marksmanship','Evoker-Devastation','Mage-Frost','Mage-Arcane','Priest-Shadow','Rogue-Assassination','DeathKnight-Blood','Druid-Guardian','Warlock-Affliction','Rogue-Outlaw','DeathKnight-Frost','DemonHunter-Vengeance','Warrior-Arms','Hunter-Survival',}
local provider = {region='US',realm='Draka',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Aberaht:BAABLgAECn8iAAIBAAgJ5yMVBwCpAgABAAgJ5yMVBwCpAgAAAA==.',
Ad='Adamaro:BAAALgADCgYJCQAAAA==.',
Ae='Aenastian:BAAALgAECgUJCQABLgAECgkJKgACAAIfAA==.',
Af='Affrica:BAAALgADCgEJAQABLgAECgQJDwADAAAAAA==.',
Ah='Ahgra:BAABLgAECn8fAAIBAAgJswoYQABJAQABAAgJswoYQABJAQAAAA==.',
Ak='Akre:BAABLgAECn8eAAIEAAgJrRA0EwBrAQAEAAgJrRA0EwBrAQAAAA==.Akumä:BAAALgAECgUJBQAAAA==.',
Al='Aleannia:BAAALgAECgQJBAAAAA==.Alestria:BAAALgAECgYJEAAAAA==.Alibrexia:BAAALgAECgYJEAAAAA==.Alida:BAABLgAECn8eAAIFAAYJyglAJQATAQAFAAYJyglAJQATAQAAAA==.Alithvia:BAAALgAECgYJBgABLgAECgkJHQAGAPUjAA==.Allisara:BAAALgADCgkJFgAAAA==.Alysae:BAACLgAFFH8NAAMHAAQJCxggDgAFAQAHAAQJCxggDgAFAQAIAAEJSQAfIgAgAAAuAAQKfxsAAwcACAkpHecdAE8CAAcACAkpHecdAE8CAAgAAgliBxJIAC8AAAAA.',
Am='Amabear:BAAALgAECgEJAQABLgAECgYJDgADAAAAAA==.Ambrosse:BAAALgADCgcJBwABLgAECgQJBgADAAAAAA==.',
An='Anabug:BAAALgAECgMJBQAAAA==.Aniellas:BAAALgAECgIJAgAAAA==.Annalese:BAAALgADCgUJBQABLgAECgYJDQADAAAAAA==.',
Ap='Apushistory:BAACLgAFFH8GAAIJAAMJUgaiEwDTAAAJAAMJUgaiEwDTAAAuAAQKfxkAAgkACAkkHNYPAEECAAkACAkkHNYPAEECAAAA.',
Ar='Arabeli:BAAALgAECgEJAQAAAA==.Arbyss:BAAALgADCgcJDAAAAA==.Ardatha:BAAALgADCgcJDQAAAA==.',
As='Asterön:BAAALgAECgUJCgAAAA==.Astrocakes:BAAALgAECgMJAwABLgAECgkJJwAKAMEZAA==.',
At='Athenä:BAACLgAFFH8QAAILAAUJIQz8AgDkAAALAAUJIQz8AgDkAAAuAAQKfysAAgsACQn8GvoFAI4CAAsACQn8GvoFAI4CAAAA.Atsuma:BAAALgAECgYJEwAAAA==.',
Av='Aviz:BAAALgADCgMJAwAAAA==.',
['Aí']='Aísling:BAAALgAECgYJCgAAAA==.',
Ba='Baboii:BAAALgADCgIJAgAAAA==.Baconmecrazy:BAAALgAECgEJAQAAAA==.Badinngo:BAAALgADCggJCAAAAA==.Bajafresh:BAAALgAECgQJBQAAAA==.Battleshaman:BAAALgADCgYJBgAAAA==.',
Bd='Bd:BAABLgAECn8dAAIMAAgJJxU5GABGAgAMAAgJJxU5GABGAgAAAA==.',
Be='Bearstavious:BAAALgAECgcJAQAAAA==.Benjinana:BAAALgAECgQJDwAAAA==.Betterthanu:BAAALgADCgUJBQABLgADCgYJCgADAAAAAA==.',
Bg='Bg:BAAALgADCgEJAQAAAA==.',
Bi='Bige:BAAALgAECgYJDQAAAA==.Bilo:BAAALgAECgYJCAAAAA==.Bitelyus:BAAALgAECgMJAwAAAA==.',
Bo='Bobius:BAAALgAECgcJBwAAAA==.Bobohizan:BAAALgADCgQJBAAAAA==.Bohde:BAABLgAFFH8IAAINAAQJcSLnCgCGAQANAAQJcSLnCgCGAQAAAA==.Bolognaman:BAAALgAECgEJAQAAAA==.Bombjovi:BAABLgAECn8XAAMLAAcJjReoCgBYAQALAAcJjReoCgBYAQAOAAUJkQ94JwAPAQAAAA==.Bountty:BAAALgAECgQJBAAAAA==.',
Br='Brahmsthoven:BAAALgADCgIJAwAAAA==.Branndhon:BAAALgAECgYJDgAAAA==.',
Bt='Btrflyprncss:BAAALgADCgMJAwAAAA==.',
Bu='Bubblemedic:BAAALgADCgIJAgAAAA==.Budde:BAAALgADCgkJCQAAAA==.',
Ca='Cairdamane:BAABLgAECn8ZAAIPAAkJ4AyYFgBfAQAPAAkJ4AyYFgBfAQAAAA==.Calidrina:BAABLgAECn8fAAIKAAgJjhyLHACIAQAKAAgJjhyLHACIAQAAAA==.Carm:BAAALgADCgYJEAAAAA==.Caroliná:BAAALgAECgEJAQAAAA==.Catcast:BAAALgAECgMJAwABLgAECgkJJQAQAE4QAA==.',
Ce='Celiri:BAABLgAECn8cAAIGAAgJ6AgTFABNAQAGAAgJ6AgTFABNAQAAAA==.Celldrassil:BAABLgAECn8YAAIHAAYJ/wZWQQDLAAAHAAYJ/wZWQQDLAAAAAA==.Cereel:BAAALgAECgMJAwABLgAECgkJJwAKAMEZAA==.',
Ch='Chadaracka:BAAALgAECgEJAgAAAA==.Chardaney:BAAALgAECgYJDQAAAA==.Cherryontop:BAABLgAECn8WAAIHAAYJCRXdJgBPAQAHAAYJCRXdJgBPAQAAAA==.',
Ci='Cii:BAAALgAECgYJCgAAAA==.',
Co='Coconutwater:BAAALgAECgYJCQAAAA==.Colandros:BAAALgAECgcJEQAAAA==.Colara:BAAALgAECgQJBAAAAA==.Combobreaker:BAABLgAECn8iAAIRAAkJPhcfBgBmAgARAAkJPhcfBgBmAgAAAA==.Comoo:BAAALgADCgIJBQAAAA==.Cowbôy:BAAALgADCgkJEQAAAA==.',
Cr='Crassberry:BAACLgAFFH8OAAINAAUJqCQPCQCSAQANAAUJqCQPCQCSAQAuAAQKfyMAAg0ACQkdJBIFAIMDAA0ACQkdJBIFAIMDAAAA.Crazèd:BAAALgADCgQJBAAAAA==.',
Cy='Cyndal:BAAALgADCgYJBgABLgADCgcJDQADAAAAAA==.Cyndle:BAAALgADCgcJDQABLgADCgcJDQADAAAAAA==.Cyntu:BAAALgADCgcJDQAAAA==.',
['Cü']='Cüpid:BAAALgAECgYJBgAAAA==.',
Da='Dada:BAAALgAECgEJAQAAAA==.Dammithells:BAAALgADCgQJBAAAAA==.Dandamar:BAAALgADCggJDwAAAA==.Dankfists:BAAALgAECgUJBQAAAA==.Dankheal:BAAALgAECgEJAQABLgAECgUJBQADAAAAAA==.Darthrevan:BAAALgAECgQJBwAAAA==.Dasharnkal:BAAALgADCgUJCAAAAA==.Dasvult:BAAALgAECgMJBAAAAA==.Dazex:BAAALgAECgUJCwAAAA==.',
De='Deadpump:BAABLgAECn8ZAAMSAAcJIQ9TQwAnAQASAAYJLA9TQwAnAQATAAQJUg4bOQDQAAAAAA==.Demonsnotkey:BAAALgAECgYJCwAAAA==.Demoxus:BAAALgAECgQJBAAAAA==.Denker:BAAALgADCggJCAAAAA==.Denzvic:BAAALgADCgkJCQAAAA==.Destro:BAAALgAECgEJAQAAAA==.Deusclaw:BAAALgAECgYJBgAAAA==.Devilah:BAAALgADCgYJCQAAAA==.',
Dh='Dharm:BAABLgAECn8XAAIUAAYJRRijMwBCAQAUAAYJRRijMwBCAQAAAA==.',
Di='Dialsl:BAAALgADCgUJBQAAAA==.Digbickpanda:BAAALgADCgYJBgABLgAECgkJJwAKAMEZAA==.Disowneege:BAAALgAECgYJDAABLgAFFAQJDwAFAFIgAA==.',
Do='Dotndash:BAAALgADCgIJAgAAAA==.Doubledge:BAAALgADCggJCAAAAA==.Doublejump:BAABLgAECn8fAAIKAAgJkRjYGQCbAQAKAAgJkRjYGQCbAQAAAA==.',
Dr='Dragdh:BAAALgAECgIJAgABLgAECgYJFgAVAHwdAA==.Dragnas:BAABLgAECn8WAAIVAAYJfB0RBgCuAQAVAAYJfB0RBgCuAQAAAA==.Dragonisa:BAAALgAECgYJBgAAAA==.Dragun:BAAALgADCgIJAgAAAA==.Draiocht:BAAALgADCgMJAwABLgAECggJFAAWAFgWAA==.Drakeskid:BAAALgAECgQJBwABLgAECgkJIQAXAEsaAA==.Drakthall:BAAALgAECgIJAwAAAA==.Dramakiller:BAAALgAECgMJAwAAAA==.Drchi:BAAALgADCgIJAgABLgAECgQJDwADAAAAAA==.Drcornbread:BAAALgAECgQJDwAAAA==.Drcornellia:BAAALgAECgEJAQABLgAECgQJDwADAAAAAA==.Drdarkskin:BAAALgAECgcJCwAAAA==.Drdreggs:BAABLgAECn8mAAMTAAkJmRY6BgBZAQASAAgJuRSUTwDZAQATAAYJnBc6BgBZAQAAAA==.Drizztin:BAAALgADCgEJAQAAAA==.Drprominus:BAAALgAECgYJEgAAAA==.Drthargyll:BAAALgADCgYJDgABLgAECgYJEgADAAAAAA==.',
Dy='Dykdanglr:BAAALgADCgYJBgABLgAECgQJCAADAAAAAA==.',
['Dí']='Dígífóx:BAAALgAECgQJBwAAAA==.',
Ea='Earthereal:BAABLgAECn8XAAIRAAYJeA83HAAgAQARAAYJeA83HAAgAQAAAA==.',
El='Elastar:BAABLgAECn8iAAIYAAgJSxkMBgDyAQAYAAgJSxkMBgDyAQAAAA==.Ellimist:BAECLgAFFH8QAAIZAAUJ/RBrBgCAAQAZAAUJ/RBrBgCAAQAuAAQKfyIAAxkACQmJGHcXAFoCABkACQmJGHcXAFoCAA8ABQk0F68wALkAAAAA.Elsan:BAAALgAECgEJAQAAAA==.Elycee:BAABLgAECn8UAAMUAAgJ2yGpCwBGAgAUAAcJHiCpCwBGAgAaAAgJUhhOIAAgAgAAAA==.Elí:BAAALgAECgQJBAAAAA==.',
En='Encrid:BAAALgAECgUJBwABLgAFFAIJAgADAAAAAA==.Enhasa:BAABLgAECn8VAAINAAgJIhUZHQDZAQANAAgJIhUZHQDZAQABLgAECgYJGQABAOggAA==.Enoeht:BAABLgAECn8YAAICAAYJOAeAHAC2AAACAAYJOAeAHAC2AAAAAA==.',
Er='Erazar:BAABLgAECn8fAAIbAAYJSA9JBgA4AQAbAAYJSA9JBgA4AQAAAA==.Eriah:BAAALgADCgkJCQAAAA==.Erickk:BAABLgAECn8hAAMcAAkJeBreKQC9AQAcAAkJLhjeKQC9AQAdAAQJVx1PCwAkAQAAAA==.',
Es='Essense:BAABLgAECn8iAAIWAAgJpiRJAwApAwAWAAgJpiRJAwApAwAAAA==.',
Ex='Exodari:BAABLgAECn8pAAIVAAkJWRGPAwANAgAVAAkJWRGPAwANAgAAAA==.',
Fa='Fabbioh:BAAALgADCgEJAQAAAA==.Fadeddh:BAABLgAECn8nAAIKAAkJwRkKDwD8AQAKAAkJwRkKDwD8AQAAAA==.',
Fe='Fearnoevil:BAAALgADCgMJAwAAAA==.Fel:BAAALgAECgYJEgAAAA==.Fellkarras:BAAALgAECgYJCwABLgAECgkJIgARAD4XAA==.Fent:BAAALgAECgUJCgAAAA==.',
Fi='Fiddich:BAAALgAECgYJBgAAAA==.Fillthy:BAACLgAFFH8MAAIRAAUJKBKEBwBvAQARAAUJKBKEBwBvAQAuAAQKfyIAAhEACQnuIUUDAEcDABEACQnuIUUDAEcDAAAA.Finnigann:BAAALgADCgYJDwAAAA==.Firenmylazer:BAAALgADCgMJAwAAAA==.Fistav:BAAALgADCgEJAQAAAA==.Fizban:BAAALgAECgUJCQABLgAECgYJCwADAAAAAA==.',
Fl='Flappybird:BAAALgAECgMJAwABLgAECgkJJwAKAMEZAA==.Flasan:BAAALgADCgEJAQAAAA==.Flazz:BAAALgADCgIJAwAAAA==.Flazzan:BAAALgADCgEJAQAAAA==.',
Fo='Fogbringer:BAAALgAECgIJAwAAAA==.Four:BAAALgADCgQJBAAAAA==.',
Fr='Frejä:BAAALgAECgQJBQABLgAECgQJDAADAAAAAA==.Freyah:BAAALgAECgUJCgAAAA==.Frostmay:BAAALgAECgIJAgAAAA==.',
Fu='Furrybawlz:BAAALgAECgUJCAABLgAECgYJDQADAAAAAA==.',
Ga='Gadogear:BAABLgAECn8ZAAIcAAYJWhmlOgB/AQAcAAYJWhmlOgB/AQAAAA==.Garlik:BAAALgADCgMJBAAAAA==.',
Gi='Girthrichard:BAAALgAECgYJDAAAAA==.',
Gl='Glassdragon:BAABLgAECn8aAAIBAAcJcgtCSgArAQABAAcJcQtCSgArAQAAAA==.Gllor:BAAALgADCgIJAgAAAA==.',
Go='Goatcheeze:BAAALgAECggJEwAAAA==.Goatylocks:BAABLgAECn8bAAMTAAgJnxVUBACYAQATAAYJFRxUBACYAQASAAQJuQZBaAC+AAAAAA==.Goldenchild:BAAALgAECgYJBwABLgAECgkJJwAKAMEZAA==.',
Gr='Greatluckydo:BAAALgADCgEJAQAAAA==.',
Gu='Gulen:BAAALgAECgQJCQAAAA==.',
['Gí']='Gíga:BAABLgAECn8XAAIUAAgJ7RPbKQAPAgAUAAgJ7RPbKQAPAgAAAA==.',
Ha='Hanhaine:BAAALgAECgYJCgAAAA==.Hazirat:BAAALgADCgIJAgAAAA==.',
He='Hedlie:BAAALgAECgYJBwAAAA==.Hellenkeller:BAABLgAECn8WAAIRAAYJPCEwEwAzAgARAAYJPCEwEwAzAgABLgAFFAUJDQAMAJogAA==.Heloisa:BAAALgAECgMJBAAAAA==.Helrazr:BAAALgAECgYJCQAAAA==.Henshin:BAABLgAECn8qAAMHAAgJHR2jDAA/AgAHAAgJHR2jDAA/AgAIAAEJHgvBhwAoAAAAAA==.',
Hi='Hitt:BAAALgAECgEJAQAAAA==.',
Ho='Holyhim:BAAALgADCgIJAgAAAA==.Hottyshmotty:BAAALgAECgEJAQAAAA==.Hourglass:BAABLgAECn8UAAMUAAcJHxRPTQCBAQAUAAYJ/xVPTQCBAQAaAAQJ1g3MXwDBAAAAAA==.',
Hu='Huntthejuan:BAAALgADCgUJBQAAAA==.',
Ic='Icyowneege:BAAALgADCgUJBQABLgAFFAQJDwAFAFIgAA==.Icywolfy:BAAALgAECgYJBgAAAA==.',
Ig='Igreetyou:BAAALgAECgcJDQAAAA==.',
Il='Illie:BAABLgAECn8iAAIVAAgJjx0cAwAfAgAVAAgJjx0cAwAfAgAAAA==.Illune:BAABLgAECn8gAAMcAAgJIBiyJADVAQAcAAgJIBiyJADVAQAdAAYJUg4XCQBbAQAAAA==.',
Im='Imanbearpig:BAAALgADCgIJAgAAAA==.Imleapingit:BAABLgAECn8XAAIFAAcJrRbxDgDIAQAFAAcJrRbxDgDIAQAAAA==.',
In='Intoodragons:BAABLgAECn8cAAMEAAgJFBDlHgDMAQAEAAgJFBDlHgDMAQAbAAYJWgX5JAD+AAAAAA==.Inyah:BAAALgAECgIJAgAAAA==.',
Io='Ionzz:BAABLgAECn8ZAAICAAkJox+iCADYAgACAAkJox+iCADYAgAAAA==.',
Ir='Iroann:BAAALgAECgUJDAAAAA==.',
Is='Isawarriorr:BAABLgAECn8hAAIYAAkJ+yKGAwAfAwAYAAkJ+yKGAwAfAwAAAA==.Ishaq:BAAALgAECgQJBQABLgAECgYJDAADAAAAAA==.Ishdo:BAAALgADCgMJAwABLgAECgYJDAADAAAAAA==.Ishkhan:BAAALgAECgYJDAAAAA==.Ishmael:BAAALgAFFAEJAQAAAA==.Ishwar:BAAALgADCgYJBgAAAA==.',
Ja='Jakytreehorn:BAACLgAFFH8GAAMZAAQJZQSjGwC2AAAZAAQJZQSjGwC2AAAPAAEJpAI7JgA3AAAuAAQKfx4AAxkACQnWEA0oAPABABkACQnWEA0oAPABAA8ABgm4DyQgABkBAAAA.Jasher:BAAALgAECgYJBgAAAA==.Jaydm:BAAALgAECgYJDAABLgAFFAQJCAAcAP0MAA==.',
Je='Jenevelle:BAAALgAECgEJAQAAAA==.Jerisil:BAAALgADCgQJBAAAAA==.Jet:BAABLgAECn8ZAAIBAAYJ6CAwSwABAgABAAYJ6CAwSwABAgAAAA==.',
Ju='Judgecalypso:BAAALgAECgQJBQAAAA==.Julthaenia:BAAALgAECgYJEQABLgAECgkJKgACAAIfAA==.Justeatjuan:BAAALgAECgMJAwAAAA==.',
Ka='Kagebushin:BAAALgAECgMJBAAAAA==.Kalazin:BAAALgADCggJBwAAAA==.Kalimah:BAAALgADCgMJAwAAAA==.Karnrae:BAAALgAECgYJEAAAAA==.Karynos:BAABLgAECn8fAAMSAAkJuQmUIgCoAQASAAkJGQiUIgCoAQATAAcJyQkSIwA/AQAAAA==.Kazmacoryy:BAAALgAECgMJAwAAAA==.',
Ke='Keedis:BAAALgADCgQJBAAAAA==.',
Ki='Kileely:BAAALgAECgMJAwAAAA==.Kirintore:BAAALgAECgUJBgAAAA==.',
Ko='Kodian:BAAALgADCgEJAQAAAA==.Kolypso:BAAALgAECgYJCQAAAA==.Konspiracy:BAABLgAECn8YAAITAAYJoReHBQBuAQATAAYJoReHBQBuAQAAAA==.Konvict:BAAALgAECgIJAwABLgAECgYJDQADAAAAAA==.',
Kr='Krataar:BAAALgAECgcJEwAAAA==.Krousvor:BAAALgAECgQJBwAAAA==.Kryph:BAABLgAECn8VAAINAAYJ2Ak4UgAKAQANAAYJ2Ak4UgAKAQAAAA==.',
Ku='Kugruk:BAAALgAECgMJBAAAAA==.Kurjo:BAAALgAECgMJBAAAAA==.',
Ky='Kyleschlong:BAAALgAECgMJBQAAAA==.',
['Kä']='Kämpfer:BAABLgAECn8gAAIFAAcJCBcJGgBfAQAFAAcJCBcJGgBfAQAAAA==.',
La='Lafiel:BAABLgAECn8ZAAMWAAgJBQo9PABJAQAWAAgJBQo9PABJAQAeAAEJTwXdZwApAAAAAA==.Landiedoo:BAAALgAECgkJCgAAAA==.Laverna:BAAALgADCgMJBAAAAA==.',
Le='Lefay:BAAALgADCgcJDgAAAA==.Letsgetwet:BAAALgADCgYJBgAAAA==.',
Li='Liefic:BAAALgAECgYJCAAAAA==.',
Lo='Loadin:BAAALgAECgIJAgAAAA==.Lockaflockå:BAAALgADCgMJAwAAAA==.Lonoh:BAAALgAECgcJEgAAAA==.',
Lu='Lucariø:BAAALgADCgcJDAAAAA==.Lucidbonsai:BAAALgADCggJCAAAAA==.Luckykilla:BAABLgAECn8XAAIfAAcJkhVxBACQAQAfAAcJkhVxBACQAQAAAA==.Lucÿ:BAABLgAECn8iAAMZAAcJrBjzKADsAQAZAAcJrBjzKADsAQAPAAMJEQwpNQChAAAAAA==.Lurith:BAABLgAECn8fAAMgAAcJzg4LEQAIAQANAAYJagbQuAARAQAgAAcJqg4LEQAIAQAAAA==.Lutreaux:BAAALgADCgEJAQAAAA==.Luxtyrannica:BAAALgAECgUJCwAAAA==.',
Ly='Lydrain:BAAALgAECgEJAQAAAA==.Lysandria:BAABLgAECn8eAAIcAAgJ9QsNPQB3AQAcAAgJ9QsNPQB3AQAAAA==.',
Ma='Macrosblack:BAAALgADCgMJAwAAAA==.Madamerouge:BAAALgADCgEJAQABLgAECgQJDwADAAAAAA==.Magearino:BAABLgAECn8YAAIcAAYJPRk7WgApAQAcAAYJPRk7WgApAQAAAA==.Marcopally:BAAALgAECgQJBAAAAA==.Marluxia:BAACLgAFFH8OAAIhAAQJ5QZjBADJAAAhAAQJ5QZjBADJAAAuAAQKfxoAAiEACAkjE/UMALkBACEACAkjE/UMALkBAAAA.Materfamilia:BAAALgADCggJDwAAAA==.Mattbull:BAABLgAECn8UAAMbAAYJKyNTDQAEAgAbAAYJQiJTDQAEAgAEAAUJ8BrlKAB2AQABLgAFFAIJAgADAAAAAA==.',
Me='Medjrab:BAACLgAFFH8GAAINAAMJThJiNQD1AAANAAMJThJiNQD1AAAuAAQKfywAAg0ACAneIC0IAJsCAA0ACAneIC0IAJsCAAAA.Meristem:BAABLgAECn8YAAIIAAYJEAxvIAD6AAAIAAYJEAxvIAD6AAAAAA==.',
Mi='Miaan:BAAALgADCgYJBgAAAA==.Miette:BAAALgADCgMJAwAAAA==.Mihonk:BAAALgADCgQJBAAAAA==.Mintycrx:BAAALgAECgYJCwAAAA==.Missfist:BAAALgADCgIJAgAAAA==.Mistlocke:BAAALgADCgMJAwAAAA==.',
Mn='Mngwa:BAAALgAECgEJAQAAAA==.',
Mo='Moegu:BAAALgAECgUJBwAAAA==.Mog:BAABLgAECn8kAAQSAAgJRyHgEAAfAgASAAYJ5SHgEAAfAgATAAMJHBHENgDbAAAiAAEJACSnJgBXAAAAAA==.Moncatsera:BAAALgAECgQJBAAAAA==.Mondgrille:BAAALgAECgQJBAABLgAECgYJDQADAAAAAA==.Monora:BAAALgAECgYJDQAAAA==.Montress:BAAALgAECgUJCAAAAA==.Moomoohealz:BAABLgAECn8rAAIIAAgJIiHbAwCIAgAIAAgJIiHbAwCIAgAAAA==.Moonbounds:BAACLgAFFH8QAAIZAAUJ8R0NBQCaAQAZAAUJ8R0NBQCaAQAuAAQKfy4AAxkACQndJFADAEQDABkACQndJFADAEQDAA8AAQnZH4Z5AF0AAAAA.Moondoggey:BAAALgAECgMJAwAAAA==.Mousechief:BAAALgAECgYJEAAAAA==.Moxnix:BAAALgAECgYJCgABLgAECgcJEAADAAAAAA==.Moxxzi:BAAALgAECgYJCwAAAA==.',
Mu='Muhfookinbak:BAAALgAECgYJEAAAAA==.',
My='Myor:BAAALgADCgMJAwAAAA==.',
['Mà']='Màttbull:BAAALgAFFAIJAgAAAA==.',
Na='Naesta:BAAALgAECgIJAgABLgAECggJIQAHAAAgAA==.Naksù:BAAALgAECgMJBgAAAA==.Namal:BAAALgAECgMJBAAAAA==.Narenae:BAABLgAECn8dAAIGAAkJ9SNABABIAwAGAAkJ9SNABABIAwAAAA==.',
Ne='Nefari:BAAALgADCgMJAwAAAA==.Neifeb:BAABLgAECn8ZAAIUAAcJfBW7IQCYAQAUAAcJfBW7IQCYAQAAAA==.Nephthys:BAAALgADCgQJBAAAAA==.',
Ni='Niallivdam:BAAALgAECgYJEwAAAA==.Nightsoul:BAAALgADCgEJAQAAAA==.Ninh:BAABLgAECn8rAAIRAAgJAg7QJQCEAQARAAgJAg7QJQCEAQAAAA==.',
No='Nomissius:BAAALgADCgcJDQAAAA==.Nooblè:BAAALgADCgMJAwAAAA==.Notsodemon:BAABLgAECn8YAAMKAAgJ7BNnNgAJAQAKAAgJ7BNnNgAJAQACAAIJnwrKYwBUAAAAAA==.Notsoevoker:BAAALgAECgMJAwABLgAECggJGAAKAOwTAA==.Notsomonk:BAAALgADCgMJAwABLgAECggJGAAKAOwTAA==.',
Ny='Nykara:BAAALgAECgUJBQAAAA==.',
Ob='Obvinotagirl:BAAALgAECggJDwAAAA==.',
Og='Ogsikko:BAAALgAECgYJCwABLgAECggJGAASAJAeAA==.Ogsikkotv:BAABLgAECn8XAAIcAAYJ+hmUhwDCAQAcAAYJ+hmUhwDCAQABLgAECggJGAASAJAeAA==.',
On='Onebadmutha:BAAALgAECgYJCwAAAA==.Ontop:BAABLgAECn8hAAIUAAgJixsdHABeAgAUAAgJixsdHABeAgAAAA==.',
Or='Orb:BAABLgAECn8UAAQBAAgJARdObQCjAQABAAcJ8BZObQCjAQAOAAYJWQxTIgA0AQALAAUJQQ/FHgATAQAAAA==.Orcfreeza:BAAALgAECgQJDAAAAA==.Ortinks:BAAALgAECgQJBgAAAA==.',
Ow='Owneege:BAACLgAFFH8PAAIFAAQJUiCXAwB8AQAFAAQJUiCXAwB8AQAuAAQKfy0AAgUACQmsIh4CAKEDAAUACQmsIh4CAKEDAAAA.',
Pa='Painsaw:BAAALgADCgYJBgAAAA==.Pallinar:BAABLgAECn8YAAIBAAYJRBNDSAAxAQABAAYJRBNDSAAxAQAAAA==.Pasquale:BAABLgAECn8fAAIXAAcJQSHyBgAqAgAXAAcJQSHyBgAqAgAAAA==.',
Pe='Pebbles:BAAALgAECgUJBQAAAA==.Pedroia:BAAALgAECgYJBwAAAA==.Pesty:BAAALgAECgMJBwAAAA==.',
Ph='Phe:BAAALgAECgcJEQAAAA==.Pheraree:BAAALgAECgEJAQAAAA==.',
Pi='Pidion:BAAALgADCgMJAwAAAA==.Pilgrimm:BAACLgAFFH8NAAMMAAUJmiAZCwA3AQAMAAMJpyAZCwA3AQAjAAIJcyCgBABhAAAuAAQKfx8AAgwACQl0IrIDAGADAAwACQl0IrIDAGADAAAA.',
Pl='Plaguerott:BAABLgAECn8mAAIkAAkJoA16AgDUAQAkAAkJoA16AgDUAQAAAA==.Plusultra:BAAALgADCgkJEQAAAA==.Pluto:BAAALgAECgMJAwAAAA==.',
Po='Poby:BAAALgADCgcJBwAAAA==.Polydh:BAABLgAECn8aAAIlAAgJBiDRAwCOAgAlAAgJBiDRAwCOAgAAAA==.Poobah:BAABLgAECn8YAAMZAAcJuwUUPwCxAAAZAAYJ3gIUPwCxAAAPAAMJmwRbPQBvAAAAAA==.Popscotch:BAABLgAECn8YAAMiAAgJ5QzNCQCkAQAiAAcJRg7NCQCkAQASAAYJYgXVWgDhAAAAAA==.Pouffant:BAABLgAECn8YAAIBAAgJ0RCIXADNAQABAAgJ0RCIXADNAQAAAA==.',
Pr='Pronoz:BAAALgAECgUJEgAAAA==.',
Pu='Punchy:BAAALgADCgEJAQAAAA==.',
Pw='Pwnageddon:BAAALgAECgcJDwAAAA==.Pwnjitsu:BAABLgAECn8nAAIGAAgJwSDHBwAIAgAGAAgJwSDHBwAIAgAAAA==.',
Py='Pyrothermia:BAACLgAFFH8IAAIcAAQJ/QxhLwD4AAAcAAQJ/QxhLwD4AAAuAAQKfyAAAhwACQkVGoUqAMkCABwACQkVGoUqAMkCAAAA.',
Qt='Qtkillz:BAAALgADCgQJBAAAAA==.',
Ra='Rawhoof:BAABLgAECn8rAAIFAAgJ+yKgAgC3AgAFAAgJ+yKgAgC3AgAAAA==.Razak:BAABLgAECn8lAAIVAAgJpx7AAQB6AgAVAAgJpx7AAQB6AgAAAA==.',
Re='Renisa:BAABLgAECn8dAAIKAAgJVBlYQgDqAQAKAAgJVBlYQgDqAQAAAA==.Retman:BAAALgAECgYJEQAAAA==.Reu:BAAALgAECgUJBwAAAA==.Revlyk:BAABLgAECn8WAAIVAAcJ4hMXBwCPAQAVAAcJ4hMXBwCPAQABLgAECgkJKgACAAIfAA==.',
Ri='Rintaro:BAABLgAECn8UAAILAAkJMAeJHwAMAQALAAkJMAeJHwAMAQAAAA==.',
Ro='Roccot:BAAALgAECgUJBwAAAA==.Roflstomp:BAAALgAECgMJBAAAAA==.Roostrr:BAAALgAECgYJEwAAAA==.Rotjaw:BAAALgAECgUJCwAAAA==.Roughedge:BAAALgADCgIJAgAAAA==.',
Ru='Rurik:BAAALgADCggJFwAAAA==.',
['Rè']='Rèjuva:BAAALgAECgcJDAAAAA==.',
['Rî']='Rîcflair:BAAALgAECgcJEwAAAA==.',
Sa='Salidfingers:BAAALgADCgYJBgAAAA==.Sanyakulak:BAAALgADCgcJBwABLgAFFAYJEwAhAD4WAA==.Savathûn:BAAALgAECgQJCAAAAA==.',
Sc='Scalycat:BAABLgAECn8lAAQQAAkJThCUGQDBAQAQAAgJTA+UGQDBAQAEAAYJJAezNACHAAAbAAIJYwe+EwA2AAAAAA==.Schalla:BAAALgAECgEJAQAAAA==.Scum:BAAALgAECgYJDQAAAA==.Scòrpìòn:BAAALgADCgcJBgABLgAFFAIJAgADAAAAAA==.',
Se='Seancody:BAAALgADCgIJAgAAAA==.Selandria:BAAALgADCgQJBAAAAA==.Senate:BAAALgAECgUJBgAAAA==.',
Sh='Shadowbear:BAAALgAECgYJDgAAAA==.Shadygrump:BAAALgAECgYJEQAAAA==.Shaolincito:BAAALgAECgQJBQAAAA==.Sherrilyn:BAAALgADCgkJFQAAAA==.Shocklocke:BAAALgAECgQJBAAAAA==.',
Si='Sigmachad:BAAALgAECgUJCgAAAA==.Silandrus:BAAALgAECgEJAQAAAA==.Silverocean:BAABLgAECn8jAAIOAAgJkB7oDwCUAgAOAAgJkB7oDwCUAgAAAA==.Silvia:BAAALgADCgUJCQAAAA==.Singularity:BAABLgAECn8oAAIYAAgJDiXcAADzAgAYAAgJDiXcAADzAgAAAA==.',
Sk='Skaerx:BAABLgAECn8WAAMFAAYJVBeJQwCXAQAFAAYJ9RWJQwCXAQAmAAQJZhSbHQADAQAAAA==.Skittlez:BAABLgAECn8dAAInAAgJUiG5AwBYAgAnAAgJUiG5AwBYAgAAAA==.',
Sl='Slootybooty:BAAALgAECgYJBwAAAA==.',
Sm='Smallz:BAAALgAECgYJCwAAAA==.',
Sn='Snipersmash:BAAALgAECgQJCAAAAA==.Snooptrogg:BAABLgAECn8cAAIFAAcJlRNiEwCbAQAFAAcJlRNiEwCbAQAAAA==.Snoozumi:BAABLgAFFH8GAAIRAAMJKgZzEwCuAAARAAMJKgZzEwCuAAAAAA==.Snuups:BAABLgAECn8oAAISAAgJ+BkVFgD1AQASAAgJ+BkVFgD1AQAAAA==.',
So='Soldiah:BAAALgAECgQJCgAAAA==.Sommbra:BAAALgAECgYJBgAAAA==.Souljax:BAAALgADCgcJCQAAAA==.',
Sp='Spacelaser:BAAALgAECgQJBQAAAA==.',
Sq='Sqwurl:BAAALgADCgQJBAAAAA==.',
St='Steakhaus:BAAALgADCgIJAgAAAA==.Stiros:BAAALgADCgUJBgAAAA==.Stonedragon:BAECLgAFFH8HAAIUAAMJ3xKaCwAGAQAUAAMJ3xKaCwAGAQAuAAQKfyYAAxQACAnNJM0FADEDABQACAnNJM0FADEDABoAAQlqB3iQACoAAAAA.Stormfist:BAAALgAECgUJCgAAAA==.Stormhaven:BAAALgADCggJIQABLgAECgYJCgADAAAAAA==.Stormrender:BAAALgAECgYJDwAAAA==.Stouty:BAAALgADCgMJAwABLgAECgcJFAAbAOkaAA==.',
Su='Sukonamí:BAABLgAECn8eAAIFAAgJaBX0CwDuAQAFAAgJaBX0CwDuAQAAAA==.Suzhou:BAABLgAECn8YAAITAAcJHgj5CQAFAQATAAcJHgj5CQAFAQAAAA==.Suzoomies:BAAALgADCgcJBwAAAA==.Suzumii:BAAALgAFFAEJAQAAAA==.',
Sw='Sweetcarolin:BAABLgAECn8WAAINAAkJRg+FXgDXAQANAAkJRg+FXgDXAQAAAA==.Sweetsmercy:BAAALgAECgQJBQAAAA==.Swisscheese:BAABLgAECn8WAAISAAYJ7yJAHADLAQASAAYJ7yJAHADLAQAAAA==.',
Sy='Syraxa:BAAALgADCggJEgAAAA==.Syril:BAAALgADCgcJDAAAAA==.',
Ta='Tahret:BAAALgADCgEJAQAAAA==.Taquillya:BAAALgADCgYJBgAAAA==.Tarina:BAAALgADCgEJAQAAAA==.Tatersaladin:BAAALgADCgMJAwAAAA==.',
Te='Tenlortin:BAAALgADCgIJAgAAAA==.Terragosa:BAABLgAECn8WAAIcAAYJsBLXSgBOAQAcAAYJsBLXSgBOAQAAAA==.',
Th='Thade:BAABLgAECn8WAAMFAAcJUB5XHwBWAgAFAAcJUB5XHwBWAgAmAAEJ3x15NgBWAAAAAA==.Thaeleon:BAABLgAECn8hAAMIAAgJUR8DBACCAgAIAAgJUR8DBACCAgAHAAYJihz9NADUAQABLgAFFAEJAQADAAAAAA==.Thaneblade:BAAALgAECgIJAgAAAA==.Therizzler:BAAALgADCgYJBwABLgAECgkJJwAKAMEZAA==.Thickening:BAAALgAECgQJDwAAAA==.Thope:BAAALgAECgUJCAAAAA==.Thoranubran:BAAALgAECgYJEgAAAA==.Thrivia:BAAALgAECgYJBgAAAA==.',
Ti='Ticklemychin:BAAALgADCgkJHAAAAA==.Tigani:BAAALgAECgQJBAAAAA==.',
To='Tokemaddab:BAAALgADCgUJBQAAAA==.',
Tr='Trainar:BAAALgAECgQJBgAAAA==.Trickybackup:BAAALgADCgMJAwAAAA==.Triggs:BAAALgADCgEJAQAAAA==.Trondruid:BAAALgADCgYJDQAAAA==.Trooze:BAABLgAECn8aAAIOAAYJgCSCBwBmAgAOAAYJgCSCBwBmAgAAAA==.Trr:BAABLgAECn8pAAISAAkJmRezIwCFAgASAAkJmRezIwCFAgAAAA==.Truckzage:BAAALgADCgcJBwABLgAECggJGQAUAPkdAA==.',
Tu='Tuba:BAAALgAECgYJEAAAAA==.Turim:BAAALgADCgQJBAAAAA==.Tusksrus:BAAALgADCgYJDQAAAA==.',
Ty='Tyrlidd:BAABLgAECn8XAAIUAAYJvA2eOgAoAQAUAAYJvA2eOgAoAQAAAA==.',
Ud='Udon:BAAALgAECgQJBQAAAA==.',
Ul='Ultimazero:BAAALgADCgEJAQAAAA==.',
Un='Unavoidable:BAAALgADCgkJDwAAAA==.Unlikelytale:BAABLgAECn8hAAIZAAgJqCHGBQCUAgAZAAgJqCHGBQCUAgAAAA==.Unmilked:BAAALgAECgIJAgAAAA==.',
Ur='Uricash:BAABLgAECn8sAAIcAAkJyxM2FAA5AgAcAAkJyxM2FAA5AgAAAA==.Urzual:BAABLgAECn8cAAIVAAcJlx11BADnAQAVAAcJlx11BADnAQAAAA==.',
Ut='Utiniócast:BAAALgADCgEJAQAAAA==.',
Va='Vandreynna:BAABLgAECn8qAAICAAkJAh9LAgCWAgACAAkJAh9LAgCWAgAAAA==.',
Ve='Vegèta:BAAALgAFFAIJAgAAAA==.Veilaura:BAAALgAECgQJBAAAAA==.Velarria:BAABLgAECn8bAAMUAAgJNyE5FQCOAgAUAAgJNyE5FQCOAgAnAAQJjwwdIQDSAAAAAA==.Velikan:BAAALgAECgQJBwABLgAECgYJBgADAAAAAA==.Velsiana:BAAALgAECgEJAgAAAA==.Velveetah:BAAALgAECgEJAQABLgAECgQJDwADAAAAAA==.Verdreht:BAAALgADCgEJAQABLgAECgcJIAAFAAgXAA==.Verita:BAABLgAECn8fAAIjAAYJDCSLAQAKAgAjAAYJDCSLAQAKAgAAAA==.',
Vi='Viviann:BAABLgAECn8gAAIQAAgJ4hHCCACZAQAQAAgJ4hHCCACZAQAAAA==.',
Vo='Voiager:BAAALgADCgcJCgAAAA==.',
Vr='Vrakal:BAAALgAECgcJCwAAAA==.',
Wa='Wantabehavoc:BAAALgADCgYJCwAAAA==.Wantadeznutz:BAAALgAECgIJAgAAAA==.Warnick:BAAALgADCgQJBQAAAA==.Warraxe:BAAALgADCgUJCAAAAA==.Wayloren:BAABLgAECn8bAAIBAAcJ+Ae2RwAyAQABAAcJ+Ae2RwAyAQAAAA==.Wayverly:BAAALgADCgUJBwABLgAECgYJDQADAAAAAA==.',
Wi='Wickathy:BAABLgAECn8jAAIlAAgJyh9aAQBuAgAlAAgJyh9aAQBuAgAAAA==.',
Wo='Wolfcity:BAAALgADCgEJAQAAAA==.Worstdps:BAAALgADCgcJEwAAAA==.',
Wu='Wuldorr:BAABLgAECn8lAAIBAAgJrh9HJACWAgABAAgJrh9HJACWAgAAAA==.',
Wy='Wynnifred:BAAALgAECgQJBAAAAA==.',
Xa='Xalatoes:BAAALgAECgMJAwAAAA==.',
Xe='Xethreal:BAAALgADCgMJAwAAAA==.',
Xy='Xype:BAAALgAECgkJEQAAAA==.',
Ya='Yastoria:BAAALgAECgcJEAAAAA==.',
Yi='Yinandtonic:BAAALgAECgEJAQAAAA==.',
Yv='Yvvee:BAAALgADCgcJBwAAAA==.',
Za='Zaalim:BAAALgADCgQJBAAAAA==.Zapdôs:BAAALgAECgQJBAAAAA==.',
Ze='Zephyris:BAAALgAECgUJDAABLgAFFAMJBwABAO0gAA==.',
Zh='Zheng:BAAALgAECgYJBgAAAA==.',
Zi='Zillia:BAAALgADCgMJAwAAAA==.',
Zy='Zyphexd:BAAALgAECgYJDwAAAA==.Zyris:BAAALgADCgcJDQAAAA==.',
['Äs']='Ästro:BAAALgAECgQJBgAAAA==.',
['Äz']='Äzrael:BAABLgAECn8UAAIWAAgJWBY7CgAEAgAWAAgJWBY7CgAEAgAAAA==.',
['Åz']='Åznos:BAAALgAECgQJCAAAAA==.',
['Çr']='Çréwüsæðèr:BAABLgAECn8YAAIYAAcJgyBEBAAvAgAYAAcJgyBEBAAvAgAAAA==.',
['Ðe']='Ðecimus:BAAALgAECgQJCQAAAA==.',
['Ðì']='Ðìaßlo:BAABLgAECn8kAAQUAAgJbxg6OQDJAQAUAAcJfRM6OQDJAQAnAAcJWBQ4EQCvAQAaAAEJXgAKmwAVAAABLgAFFAIJAgADAAAAAA==.',
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
