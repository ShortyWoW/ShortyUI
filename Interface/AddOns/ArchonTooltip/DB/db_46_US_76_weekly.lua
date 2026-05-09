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

local lookup = {'Paladin-Retribution','DemonHunter-Havoc','Unknown-Unknown','Warrior-Fury','Monk-Windwalker','Druid-Restoration','Druid-Balance','Priest-Shadow','DemonHunter-Devourer','Paladin-Protection','Warrior-Protection','Rogue-Subtlety','DeathKnight-Unholy','DeathKnight-Blood','Paladin-Holy','Shaman-Elemental','Evoker-Preservation','Hunter-Survival','Monk-Mistweaver','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Shaman-Enhancement','Priest-Holy','Monk-Brewmaster','Shaman-Restoration','Hunter-Marksmanship','Evoker-Devastation','Mage-Frost','Mage-Arcane','Evoker-Augmentation','Warlock-Affliction','Rogue-Assassination','Druid-Guardian','Rogue-Outlaw','DeathKnight-Frost','DemonHunter-Vengeance','Warrior-Arms',}
local provider = {region='US',realm='Draka',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Aberaht:BAABLgAECn8mAAIBAAkJXyODBAAJAwABAAkJXyODBAAJAwAAAA==.',
Ad='Adamaro:BAAALgADCgYJCQAAAA==.',
Ae='Aenastian:BAAALgAECgUJCQABLgAECgkJMQACAKMgAA==.',
Af='Affrica:BAAALgADCgEJAQABLgAECgQJEwADAAAAAA==.',
Ag='Agnu:BAAALgADCgcJBwAAAA==.',
Ah='Ahgra:BAABLgAECn8mAAIBAAgJ+QoJWABBAQABAAgJ+QoJWABBAQAAAA==.',
Ak='Akre:BAAALgAFFAIJBAAAAQ==.Akumä:BAAALgAECgUJCQAAAA==.',
Al='Aleannia:BAAALgAECgUJBQAAAA==.Alestria:BAAALgAECgYJEQAAAA==.Alibrexia:BAAALgAECgYJEAAAAA==.Alida:BAABLgAECn8gAAIEAAgJeQgeIwBXAQAEAAgJeQgeIwBXAQAAAA==.Alithvia:BAAALgAECgYJBgABLgAECgkJJQAFAAskAA==.Allisara:BAAALgADCgkJFgAAAA==.Alysae:BAACLgAFFH8SAAMGAAUJVBe2DQBtAQAGAAUJVBe2DQBtAQAHAAEJSQCHLAAgAAAuAAQKfxsAAwYACAkpHeQdAE8CAAYACAkpHeQdAE8CAAcAAgliB8xaAC4AAAAA.',
Am='Amabear:BAAALgAECgEJAQABLgAECgcJGAAIAA8cAA==.Ambrosse:BAAALgADCgcJBwABLgAECgQJBgADAAAAAA==.',
An='Anabug:BAAALgAECgMJBQAAAA==.Andelwynn:BAAALgAECgIJAgABLgAECgcJDwADAAAAAA==.Aniellas:BAAALgAECgIJAgAAAA==.Annalese:BAAALgADCgUJCQABLgAECgcJDwADAAAAAA==.',
Ar='Arabeli:BAAALgAECgEJAQAAAA==.Arbyss:BAAALgADCgcJDAAAAA==.Ardatha:BAAALgADCgcJFAAAAA==.',
As='Asterön:BAAALgAECgYJDAAAAA==.Astrocakes:BAAALgAECgMJAwABLgAFFAMJBgAJAL0MAA==.',
At='Athenä:BAACLgAFFH8WAAIKAAYJSwtRAgA0AQAKAAYJSwtRAgA0AQAuAAQKfzAAAgoACQnxG/gFAI4CAAoACQnxG/gFAI4CAAAA.Atsuma:BAABLgAECn8XAAILAAYJ+QgIKgDwAAALAAYJ+QgIKgDwAAAAAA==.',
Av='Aviz:BAAALgADCgMJAwAAAA==.',
['Aí']='Aísling:BAAALgAECgYJEAAAAA==.',
Ba='Baboii:BAAALgADCgIJAgAAAA==.Baconmecrazy:BAAALgAECgEJAQAAAA==.Badinngo:BAAALgADCggJDQAAAA==.Bahiu:BAAALgAECgQJBAAAAA==.Bajafresh:BAAALgAECgQJBQAAAA==.Battleshaman:BAAALgADCgYJBgAAAA==.',
Bd='Bd:BAABLgAECn8dAAIMAAgJJxU2GABGAgAMAAgJJxU2GABGAgAAAA==.',
Be='Beardmedaddy:BAAALgADCgcJBwAAAA==.Bearstavious:BAAALgAECgcJAQAAAA==.Benjinana:BAAALgAECgQJEwAAAA==.Betterthanu:BAAALgADCgUJBQABLgADCgYJCgADAAAAAA==.',
Bg='Bg:BAAALgADCgEJAQAAAA==.',
Bi='Bige:BAAALgAECgYJDgAAAA==.Bilo:BAAALgAECgYJCAAAAA==.Bitelyus:BAAALgAECgMJAwAAAA==.',
Bo='Bobius:BAAALgAECgcJBwAAAA==.Bobohizan:BAAALgADCgQJBAAAAA==.Bohde:BAABLgAFFH8LAAMNAAUJ2CLFEACRAQANAAQJ2CLFEACRAQAOAAEJAABJKgAAAAAAAA==.Bolognaman:BAAALgAECgEJAQAAAA==.Bombjovi:BAABLgAECn8YAAMKAAgJ0hXUCwB/AQAKAAgJ0hXUCwB/AQAPAAUJkQ9/MwABAQAAAA==.Bountty:BAAALgAECgQJBAAAAA==.',
Br='Brahmsthoven:BAAALgADCgIJAwAAAA==.Branndhon:BAAALgAECgYJEwAAAA==.',
Bt='Btrflyprncss:BAAALgADCgMJAwAAAA==.',
Bu='Bubblemedic:BAAALgADCgIJAgAAAA==.Budde:BAAALgAECgUJBQAAAA==.',
Ca='Cairdamane:BAABLgAECn8hAAIQAAkJ5BFYEwC9AQAQAAkJ5BFYEwC9AQAAAA==.Calidrina:BAABLgAECn8hAAIJAAkJMhznHQDVAQAJAAkJMhznHQDVAQAAAA==.Carm:BAAALgAECgYJBgAAAA==.Caroliná:BAAALgAECgEJAgAAAA==.Catcast:BAAALgAECgMJAwABLgAECgkJKAARANgOAA==.',
Ce='Celiri:BAABLgAECn8eAAIFAAgJTQlKGwBJAQAFAAgJTQlKGwBJAQAAAA==.Celldrassil:BAABLgAECn8gAAIGAAgJ4QWNRwD1AAAGAAgJ4QWNRwD1AAAAAA==.Cereel:BAAALgAECgMJAwABLgAFFAMJBgAJAL0MAA==.',
Ch='Chadaracka:BAAALgAECgYJBwAAAA==.Chandelure:BAAALgAECgUJCwAAAA==.Chardaney:BAAALgAECgcJDwAAAA==.Cherryontop:BAABLgAECn8XAAIGAAYJChV4NABIAQAGAAYJChV4NABIAQAAAA==.Chozenone:BAAALgAECgIJAgAAAA==.Chozi:BAAALgAECgYJBgAAAA==.',
Ci='Cii:BAAALgAECgYJCgAAAA==.',
Co='Coconutwater:BAAALgAECggJCwAAAA==.Colandros:BAABLgAECn8aAAISAAcJsgojGQA/AQASAAcJsgojGQA/AQAAAA==.Colara:BAAALgAECgUJDgAAAA==.Combobreaker:BAABLgAECn8nAAITAAkJhhiFBwB/AgATAAkJhhiFBwB/AgAAAA==.Comoo:BAAALgADCgIJBQAAAA==.Cowbôy:BAAALgADCgkJEQAAAA==.',
Cr='Crassberry:BAACLgAFFH8UAAINAAYJ6SRcAwAYAgANAAYJ6SRcAwAYAgAuAAQKfyMAAg0ACQkdJBQFAIMDAA0ACQkdJBQFAIMDAAAA.Crazèd:BAAALgADCgQJBAAAAA==.',
Cy='Cyndal:BAAALgAECgEJAQABLgAECgQJBQADAAAAAA==.Cyndle:BAAALgADCgcJDQABLgAECgQJBQADAAAAAA==.Cyntu:BAAALgAECgQJBQAAAA==.',
['Cü']='Cüpid:BAAALgAECgYJBgAAAA==.',
Da='Dada:BAAALgAECgEJAQAAAA==.Dammithells:BAAALgADCgQJBAAAAA==.Dandamar:BAAALgADCggJDwAAAA==.Dankfists:BAAALgAECgUJBQABLgAECggJGAAPAK4ZAA==.Dankhaze:BAAALgAFFAIJAgAAAA==.Dark:BAAALgADCgEJAQAAAA==.Darthrevan:BAAALgAECgQJBwAAAA==.Dasharnkal:BAAALgADCgUJCAAAAA==.Dasvult:BAAALgAECgMJBAAAAA==.Dazex:BAAALgAECgUJDwAAAA==.',
De='Deadpump:BAABLgAECn8fAAMUAAcJfBLdOQB/AQAUAAcJfBLdOQB/AQAVAAQJUQ4YOQDQAAAAAA==.Demonsnotkey:BAAALgAECgYJCwAAAA==.Demoxus:BAAALgAECgQJBAAAAA==.Denker:BAAALgADCggJCAAAAA==.Denkzilla:BAAALgADCgIJAgAAAA==.Denzvic:BAAALgADCgkJCgAAAA==.Destro:BAAALgAECgEJAQAAAA==.Deusclaw:BAAALgAECgYJBwAAAA==.Devilah:BAAALgAECgEJAQAAAA==.',
Dh='Dharm:BAABLgAECn8dAAIWAAYJaxvMNwBuAQAWAAYJaxvMNwBuAQAAAA==.',
Di='Dialsl:BAAALgADCgUJBQAAAA==.Digbickpanda:BAAALgADCgYJBgABLgAFFAMJBgAJAL0MAA==.Disowneege:BAAALgAECgYJEQABLgAFFAYJFQAEAPUjAA==.',
Do='Dotndash:BAAALgADCgIJAgAAAA==.Doubledge:BAAALgADCggJCAAAAA==.Doublejump:BAACLgAFFH8GAAIJAAQJiAvdJwASAQAJAAQJiAvdJwASAQAuAAQKfyIAAgkACAkeGXshAL8BAAkACAkeGXshAL8BAAAA.',
Dr='Dragdh:BAAALgAECgQJCAABLgAECgYJHAAXAE8fAA==.Dragnas:BAABLgAECn8cAAIXAAYJTx9CBwC/AQAXAAYJTx9CBwC/AQAAAA==.Dragonisa:BAAALgAFFAEJAQAAAA==.Dragun:BAAALgADCgIJAgAAAA==.Draiocht:BAAALgADCgMJAwABLgAECgkJGgAYANQZAA==.Drakeskid:BAAALgAECgQJBwABLgAECgkJIQAZAEsaAA==.Drakthall:BAAALgAECgIJAwAAAA==.Dralionethny:BAAALgAECgIJAgAAAA==.Dramakiller:BAAALgAECgMJAwAAAA==.Drchi:BAAALgADCgIJAgABLgAECgQJEwADAAAAAA==.Drcornbread:BAAALgAECgQJEwAAAA==.Drcornellia:BAAALgAECgIJBAABLgAECgQJEwADAAAAAA==.Drdarkskin:BAAALgAECgcJDAAAAA==.Drdreggs:BAABLgAECn8mAAMVAAkJmRaFCABSAQAUAAgJuRSOTwDZAQAVAAYJnBeFCABSAQAAAA==.Drizztin:BAAALgADCgEJAQAAAA==.Drprominus:BAABLgAECn8aAAIPAAgJCyBTBADwAgAPAAgJCyBTBADwAgAAAA==.Drthargyll:BAAALgADCgYJDgABLgAECggJGgAPAAsgAA==.',
Dy='Dykdanglr:BAAALgADCgYJBgABLgAECgQJCAADAAAAAA==.',
['Dí']='Dígífóx:BAAALgAECgUJDAAAAA==.',
Ea='Earthereal:BAABLgAECn8fAAITAAgJ7A8HFgCoAQATAAgJ7A8HFgCoAQAAAA==.',
El='Elastar:BAABLgAECn8mAAILAAkJ5BbCBgAhAgALAAkJ5BbCBgAhAgAAAA==.Ellimist:BAECLgAFFH8UAAIaAAUJahs6BQDCAQAaAAUJahs6BQDCAQAuAAQKfyIAAxoACQmJGHUXAFoCABoACQmJGHUXAFoCABAABQk0FxBQAAcBAAAA.Elsan:BAAALgAECgEJAQAAAA==.Elycee:BAABLgAECn8WAAMWAAkJlyI/CACuAgAWAAgJNCE/CACuAgAbAAgJUhiOIAAhAgAAAA==.Elí:BAAALgAECgQJBAAAAA==.',
En='Encrid:BAAALgAECgcJDQABLgAFFAIJAwADAAAAAA==.Enhasa:BAABLgAECn8XAAINAAkJwRNNHQAYAgANAAkJwRNNHQAYAgABLgAECgYJGgABAOggAA==.Enoeht:BAABLgAECn8gAAICAAgJdwhkFQA+AQACAAgJdwhkFQA+AQAAAA==.Enveliria:BAAALgADCgYJBgABLgAECgkJMQACAKMgAA==.',
Er='Erazar:BAABLgAECn8kAAIcAAYJYw/RCAAdAQAcAAYJYw/RCAAdAQAAAA==.Eriah:BAAALgADCgkJCQAAAA==.Erickk:BAABLgAECn8pAAMdAAkJ3xv/IwAWAgAdAAkJlBr/IwAWAgAeAAQJVx1QCwAkAQAAAA==.',
Es='Essense:BAABLgAECn8mAAIYAAkJmyQ5AQBdAwAYAAkJmyQ5AQBdAwAAAA==.',
Ex='Exodari:BAABLgAECn8yAAIXAAkJIxePAwBIAgAXAAkJIxePAwBIAgAAAA==.',
Fa='Fabbioh:BAAALgADCgEJAQAAAA==.Fadeddh:BAACLgAFFH8GAAIJAAMJvQzfNQDbAAAJAAMJvQzfNQDbAAAuAAQKfysAAgkACQlhGwUPAE8CAAkACQlhGwUPAE8CAAAA.Faizarah:BAAALgAECgYJBgAAAA==.',
Fe='Fearnoevil:BAAALgADCgMJAwAAAA==.Fel:BAAALgAECgYJEgAAAA==.Fellkarras:BAAALgAECgYJCwABLgAECgkJJwATAIYYAA==.Fent:BAAALgAECgUJCgAAAA==.',
Fi='Fiddich:BAAALgAECgYJBgAAAA==.Fillthy:BAACLgAFFH8QAAITAAYJ4hU7BgDJAQATAAYJ4hU7BgDJAQAuAAQKfyUAAxMACQnuIUQDAEcDABMACQnuIUQDAEcDAAUAAgmZBdtVAD4AAAAA.Finnigann:BAAALgAECgYJBgAAAA==.Firenmylazer:BAAALgADCgMJAwAAAA==.Fistav:BAAALgADCgcJDgAAAA==.Fizban:BAAALgAECgYJCgABLgAECgcJEgADAAAAAA==.',
Fl='Flappybird:BAAALgAECgMJAwABLgAFFAMJBgAJAL0MAA==.Flasan:BAAALgADCgEJAQAAAA==.Flazz:BAAALgADCgIJAwAAAA==.Flazzan:BAAALgADCgEJAQAAAA==.',
Fo='Fogbringer:BAAALgAECgIJAwAAAA==.Four:BAAALgADCgQJBAAAAA==.',
Fr='Frejä:BAAALgAECgQJBQABLgAECgQJDAADAAAAAA==.Freyah:BAAALgAECgUJCgAAAA==.Frostmay:BAAALgAECgIJAgAAAA==.',
Fu='Furrybawlz:BAAALgAECgUJCgABLgAECgYJDQADAAAAAA==.',
Ga='Gadogear:BAABLgAECn8ZAAIdAAYJWhm9UQB1AQAdAAYJWhm9UQB1AQAAAA==.Garlik:BAAALgADCgMJBAAAAA==.',
Ge='Gertra:BAAALgAECgEJAgAAAA==.',
Gi='Girthrichard:BAAALgAECgYJDAAAAA==.',
Gl='Glassdragon:BAABLgAECn8hAAIBAAgJeAwYTQBeAQABAAgJeAwYTQBeAQAAAA==.Gllor:BAAALgADCgIJAgAAAA==.',
Go='Goatcheeze:BAAALgAECggJEwAAAA==.Goatylocks:BAABLgAECn8cAAMVAAgJqBU6BgCQAQAVAAYJIRw6BgCQAQAUAAQJzgY5hQC7AAAAAA==.Goldenchild:BAAALgAECgYJBwABLgAFFAMJBgAJAL0MAA==.',
Gr='Greatluckydo:BAAALgADCgEJAQAAAA==.',
Gu='Gulen:BAAALgAECgYJDwAAAA==.',
['Gí']='Gíga:BAABLgAECn8XAAIWAAgJ7RPcKQAPAgAWAAgJ7RPcKQAPAgAAAA==.',
Ha='Hafnium:BAAALgADCgkJCQAAAA==.Hanhaine:BAAALgAECggJEwAAAA==.Hazirat:BAAALgAECgEJAQAAAA==.',
He='Hedlie:BAAALgAECgcJCAAAAA==.Hellenkeller:BAACLgAFFH8HAAITAAYJhw/eBwCmAQATAAYJhw/eBwCmAQAuAAQKfxcAAhMABgk8ITATADMCABMABgk8ITATADMCAAAA.Heloisa:BAAALgAECgMJBAAAAA==.Helrazr:BAAALgAECgYJCQAAAA==.Henshin:BAABLgAECn80AAMGAAkJtxyODACCAgAGAAkJtxyODACCAgAHAAIJOA57UwA8AAAAAA==.',
Hi='Hitt:BAAALgAECgEJAgAAAA==.',
Ho='Holyhim:BAAALgADCgIJAgAAAA==.Hottyshmotty:BAAALgAECgEJAQAAAA==.Hourglass:BAABLgAECn8bAAMWAAcJuRWfPwBQAQAWAAcJKxWfPwBQAQAbAAQJ1g3gXwDBAAAAAA==.',
Hu='Huntthejuan:BAAALgADCgUJBQAAAA==.',
Ic='Icyowneege:BAAALgADCgUJBQABLgAFFAYJFQAEAPUjAA==.Icywolfy:BAAALgAECgYJCAAAAA==.',
Ig='Igreetyou:BAABLgAECn8UAAIUAAcJQRZNLQCuAQAUAAcJQRZNLQCuAQAAAA==.',
Il='Illie:BAABLgAECn8mAAIXAAkJShxEAwBXAgAXAAkJShxEAwBXAgAAAA==.Illune:BAABLgAECn8kAAMdAAkJKhctIQAlAgAdAAkJKhctIQAlAgAeAAYJUg4YCQBbAQAAAA==.',
Im='Imanbearpig:BAAALgADCgIJAgAAAA==.Imleapingit:BAABLgAECn8cAAIEAAgJ6x31BwBtAgAEAAgJ6x31BwBtAgAAAA==.',
In='Intoodragons:BAABLgAECn8mAAMfAAkJqBL6DQDuAQAfAAkJqBL6DQDuAQAcAAYJWgXzJAD+AAAAAA==.Inyah:BAAALgAECgIJAgAAAA==.',
Io='Ionzz:BAABLgAECn8ZAAICAAkJox+gCADYAgACAAkJox+gCADYAgAAAA==.',
Ir='Iroann:BAAALgAECgYJDgAAAA==.',
Is='Isawarriorr:BAABLgAECn8kAAILAAkJ/CKHAwAfAwALAAkJ/CKHAwAfAwAAAA==.Ishaq:BAAALgAECgQJBQABLgAECgcJDQADAAAAAA==.Ishdo:BAAALgADCgMJAwABLgAECgcJDQADAAAAAA==.Ishkhan:BAAALgAECgcJDQAAAA==.Ishmael:BAAALgAFFAIJAgAAAA==.Ishwar:BAAALgADCgYJBgAAAA==.',
Ja='Jakytreehorn:BAACLgAFFH8HAAMaAAUJKQVMKQCsAAAaAAQJZQRMKQCsAAAQAAIJowLiMAA2AAAuAAQKfyMAAxoACQkqEgsoAPABABoACQkqEgsoAPABABAABwmVDbQkADEBAAAA.Jasher:BAAALgAECgYJBgAAAA==.Jaydm:BAAALgAECgYJDwABLgAFFAYJDQAdAOsMAA==.',
Je='Jenevelle:BAAALgAECgQJBQAAAA==.Jerisil:BAAALgADCgQJBAAAAA==.Jet:BAABLgAECn8aAAIBAAYJ6CAwSwABAgABAAYJ6CAwSwABAgAAAA==.',
Ji='Jibbajabba:BAAALgADCgcJBwAAAA==.',
Ju='Judgecalypso:BAAALgAECgQJBQAAAA==.Julthaenia:BAABLgAECn8VAAQgAAYJgxjQBgBBAQAgAAUJXRzQBgBBAQAUAAUJbQtQmgCKAAAVAAQJFAqoHQBhAAABLgAECgkJMQACAKMgAA==.Justeatjuan:BAAALgAECgMJAwAAAA==.',
Ka='Kagebushin:BAAALgAECgMJBAAAAA==.Kalazin:BAAALgADCggJBwAAAA==.Kalimah:BAAALgADCgMJAwAAAA==.Karnrae:BAABLgAECn8WAAIBAAYJFA8ZYwAnAQABAAYJFA8ZYwAnAQAAAA==.Karynos:BAABLgAECn8iAAMUAAkJcArxLQCrAQAUAAkJPgnxLQCrAQAVAAcJyQkLIwA/AQAAAA==.Kazmacoryy:BAAALgAECgYJCQAAAA==.',
Ke='Keedis:BAAALgADCggJCwAAAA==.',
Ki='Kileely:BAAALgAECgMJAwAAAA==.Kirintore:BAAALgAECgUJCAAAAA==.',
Ko='Kodian:BAAALgADCgEJAQAAAA==.Kolypso:BAAALgAECgYJDgAAAA==.Konspiracy:BAABLgAECn8gAAIVAAgJ8xfoAgALAgAVAAgJ8xfoAgALAgAAAA==.Konvict:BAAALgAECgIJAwABLgAECgYJDQADAAAAAA==.',
Kr='Krataar:BAABLgAECn8bAAIEAAgJUR8jCgBGAgAEAAgJUR8jCgBGAgAAAA==.Kravvan:BAAALgADCgEJAQABLgAECgcJEgADAAAAAA==.Krousvor:BAAALgAECgQJBwAAAA==.Kryph:BAABLgAECn8VAAINAAYJ2AnubgAEAQANAAYJ2AnubgAEAQAAAA==.',
Ku='Kugruk:BAAALgAECgMJBAAAAA==.Kurjo:BAAALgAECgMJBAAAAA==.',
Ky='Kyleschlong:BAAALgAECgMJBQAAAA==.',
['Kä']='Kämpfer:BAABLgAECn8sAAIEAAcJ7hvfEADsAQAEAAcJ7hvfEADsAQAAAA==.',
La='Lafiel:BAABLgAECn8dAAMYAAkJHAtEPABJAQAYAAkJHAtEPABJAQAIAAIJ1QiSQwBlAAAAAA==.Landiedoo:BAAALgAECgkJCgAAAA==.Laverna:BAAALgADCgMJBAAAAA==.',
Le='Lefay:BAAALgADCgcJEwAAAA==.Leprawnjames:BAAALgAECgIJAgABLgAECgYJDAADAAAAAA==.Letsgetwet:BAAALgADCgYJBgAAAA==.',
Li='Liefic:BAAALgAECgYJCAAAAA==.',
Lo='Loadin:BAAALgAECgIJAgAAAA==.Lockaflockå:BAAALgADCgMJAwAAAA==.Locke:BAAALgAECgMJAgABLgAECgYJGgABAOggAA==.Lonoh:BAAALgAECgcJEgAAAA==.',
Lu='Lucariø:BAAALgADCgcJDAAAAA==.Lucidbonsai:BAAALgADCggJCAAAAA==.Luckykilla:BAABLgAECn8eAAIhAAgJhxmKAwD5AQAhAAgJhxmKAwD5AQAAAA==.Lucÿ:BAACLgAFFH8FAAIaAAMJ6QsNKQCtAAAaAAMJ6QsNKQCtAAAuAAQKfyIAAxoABwmsGPMoAOwBABoABwmsGPMoAOwBABAAAwkRDCtEAJkAAAAA.Lurith:BAABLgAECn8nAAMOAAgJjQ1mFAA0AQAOAAgJbg1mFAA0AQANAAYJagbNuAARAQAAAA==.Lutreaux:BAAALgADCgEJAQAAAA==.Luxtyrannica:BAAALgAECgYJDwAAAA==.',
Ly='Lydrain:BAAALgAECgEJAQAAAA==.Lysandria:BAABLgAECn8gAAIdAAgJtwyJTQCBAQAdAAgJtwyJTQCBAQAAAA==.',
Ma='Macrosblack:BAAALgADCgMJAwAAAA==.Madamerouge:BAAALgADCgEJAQABLgAECgQJEwADAAAAAA==.Magearino:BAABLgAECn8dAAIdAAYJbhmlVQBrAQAdAAYJbhmlVQBrAQAAAA==.Marcopally:BAAALgAECgQJBAAAAA==.Marluxia:BAACLgAFFH8TAAIiAAUJ5AZyBgC/AAAiAAUJ5AZyBgC/AAAuAAQKfxoAAiIACAkjE/UMALkBACIACAkjE/UMALkBAAAA.Materfamilia:BAAALgAECgQJBAAAAA==.Mattbull:BAABLgAECn8XAAMcAAYJkSNTDQAEAgAcAAYJQiJTDQAEAgAfAAUJTh7VIwApAQABLgAFFAIJAwADAAAAAA==.',
Me='Medjrab:BAACLgAFFH8JAAINAAMJqRNASwD4AAANAAMJqRNASwD4AAAuAAQKfywAAg0ACAneIBwPAIgCAA0ACAneIBwPAIgCAAAA.Meristem:BAABLgAECn8aAAIHAAgJjgnEHwA4AQAHAAgJjgnEHwA4AQAAAA==.',
Mi='Miaan:BAAALgADCgYJBgAAAA==.Miette:BAAALgADCgMJAwAAAA==.Mihonk:BAAALgADCgQJBAAAAA==.Mintycrx:BAAALgAECgcJEAAAAA==.Missfist:BAAALgADCgIJAgAAAA==.Mistlocke:BAAALgADCgMJAwAAAA==.',
Mn='Mngwa:BAAALgAECgIJAwAAAA==.',
Mo='Moegu:BAAALgAECgcJEAAAAA==.Mog:BAABLgAECn8uAAQUAAkJyiLYBwDIAgAUAAcJ4yLYBwDIAgAgAAMJliNxBwAxAQAVAAMJHBG+NgDbAAAAAA==.Moncatsera:BAAALgAECgQJBAAAAA==.Mondgrille:BAAALgAECgQJBAABLgAECgYJDQADAAAAAA==.Monora:BAAALgAECgcJEwAAAA==.Montress:BAAALgAECgcJCAAAAA==.Moomoohealz:BAABLgAECn81AAIHAAkJJiFPAgD+AgAHAAkJJiFPAgD+AgAAAA==.Moonbounds:BAACLgAFFH8VAAIaAAUJlB6xBgCqAQAaAAUJlB6xBgCqAQAuAAQKfy8AAxoACQndJFEDAEQDABoACQndJFEDAEQDABAAAQnZH4B5AF0AAAAA.Moondoggey:BAAALgAECgMJAwAAAA==.Mousechief:BAABLgAECn8WAAIQAAYJcwQoPQC3AAAQAAYJcwQoPQC3AAAAAA==.Moxnix:BAAALgAECgYJDQABLgAECgcJFAAWAJQOAA==.Moxxzi:BAAALgAECgYJCwAAAA==.',
Mu='Muhfookinbak:BAABLgAECn8XAAMaAAcJpyDREAA2AgAaAAcJpyDREAA2AgAQAAQJFRGvPwCrAAAAAA==.',
My='Myor:BAAALgADCgMJAwAAAA==.',
['Mà']='Màttbull:BAAALgAFFAIJAwAAAA==.',
Na='Naesta:BAAALgAECgIJAgABLgAECggJIQAGAAAgAA==.Naksù:BAAALgAECgUJDAAAAA==.Namal:BAAALgAECgMJBAAAAA==.Narenae:BAABLgAECn8lAAIFAAkJCyQ/BABIAwAFAAkJCyQ/BABIAwAAAA==.Nastalan:BAAALgADCgYJCgAAAA==.',
Ne='Nefari:BAAALgADCgMJAwAAAA==.Neifeb:BAABLgAECn8gAAIWAAgJbxdTHwDgAQAWAAgJbxdTHwDgAQAAAA==.Nephthys:BAAALgADCgQJBAAAAA==.',
Ni='Niallivdam:BAABLgAECn8aAAMRAAYJvBaUEAA0AQARAAYJvBaUEAA0AQAcAAUJohMCDQDAAAAAAA==.Nightsoul:BAAALgADCgEJAQAAAA==.Ninh:BAABLgAECn81AAITAAkJbw0xHABpAQATAAkJbw0xHABpAQAAAA==.',
No='Nomissius:BAAALgADCgcJDQAAAA==.Nooblè:BAAALgADCgMJAwAAAA==.Notsodemon:BAABLgAECn8YAAMJAAgJ7BPHUAAHAQAJAAgJ7BPHUAAHAQACAAIJnwrOYwBUAAAAAA==.Notsoevoker:BAAALgAECgMJAwABLgAECggJGAAJAOwTAA==.Notsomonk:BAAALgADCgMJAwABLgAECggJGAAJAOwTAA==.',
Ny='Nykara:BAAALgAECgUJBQAAAA==.',
['Nå']='Nåld:BAAALgAECgEJAQAAAA==.',
Ob='Obvinotagirl:BAAALgAECggJDwAAAA==.',
Og='Ogsikko:BAAALgAECgYJCwABLgAECggJGAAUAJAeAA==.Ogsikkotv:BAABLgAECn8YAAIdAAYJ+hmKhwDCAQAdAAYJ+hmKhwDCAQABLgAECggJGAAUAJAeAA==.',
Ok='Okathra:BAAALgAECgQJBAABLgAECggJJgAXAP4fAA==.',
On='Onebadmutha:BAAALgAECgYJDwAAAA==.Ontop:BAABLgAECn8iAAIWAAkJ5RoaHABeAgAWAAkJ5RoaHABeAgAAAA==.',
Or='Orb:BAABLgAECn8cAAQBAAgJmBh2MAC6AQABAAgJdxd2MAC6AQAPAAYJWQxELQAnAQAKAAUJQQ/CHgATAQAAAA==.Orcfreeza:BAAALgAECgQJDAAAAA==.Ortinks:BAAALgAECgYJDAAAAA==.',
Ow='Owneege:BAACLgAFFH8VAAIEAAYJ9SOHAAANAgAEAAYJ9SOHAAANAgAuAAQKfy0AAgQACQmsIh4CAKEDAAQACQmsIh4CAKEDAAAA.',
Pa='Painsaw:BAAALgADCgYJBgAAAA==.Pallinar:BAABLgAECn8gAAIBAAgJpBHROACcAQABAAgJpBHROACcAQAAAA==.Pasquale:BAABLgAECn8hAAIZAAcJQSFiCQAwAgAZAAcJQSFiCQAwAgAAAA==.',
Pe='Pebbles:BAAALgAECgUJBQAAAA==.Pedroia:BAAALgAECgYJBwAAAA==.Pesty:BAAALgAECgMJBwAAAA==.',
Ph='Phe:BAABLgAECn8XAAMHAAcJew5EHgBDAQAHAAcJew5EHgBDAQAGAAYJpQvvcAADAQAAAA==.Pheraree:BAAALgAECgEJAQAAAA==.Phooboo:BAAALgAECgkJBQAAAA==.',
Pi='Pidion:BAAALgADCgYJDAAAAA==.Pilgrimm:BAACLgAFFH8PAAMjAAUJmiDnAgAaAQAMAAMJpyAcCwA4AQAjAAQJfB7nAgAaAQAuAAQKfx8AAgwACQl0IrIDAGADAAwACQl0IrIDAGADAAEuAAUUBgkHABMAhw8A.',
Pl='Plaguerott:BAABLgAECn8uAAIkAAkJeA+GAwDUAQAkAAkJeA+GAwDUAQAAAA==.Plusultra:BAAALgADCgkJEQAAAA==.Pluto:BAAALgAECgYJCQAAAA==.',
Po='Poby:BAAALgADCgcJBwAAAA==.Polydh:BAABLgAECn8jAAIlAAkJACKdAAD2AgAlAAkJACKdAAD2AgAAAA==.Poobah:BAABLgAECn8gAAMQAAgJFwa8MADwAAAQAAcJugW8MADwAAAaAAcJCQNqTADOAAAAAA==.Popscotch:BAABLgAECn8aAAMgAAgJHA3NCQCkAQAgAAcJRg7NCQCkAQAUAAYJBwc2cADqAAAAAA==.Pouffant:BAABLgAECn8fAAIBAAgJFxWPMAC6AQABAAgJFxWPMAC6AQAAAA==.',
Pr='Pronoz:BAABLgAECn8WAAIBAAYJxQ74ZgAfAQABAAYJxQ74ZgAfAQAAAA==.',
Pu='Punchy:BAAALgADCgEJAQAAAA==.',
Pw='Pwnageddon:BAABLgAECn8WAAMKAAgJ4xm7BwDXAQAKAAcJLhy7BwDXAQABAAUJhxU3uQCCAAAAAA==.Pwnjitsu:BAABLgAECn8rAAIFAAkJHyHjAQAHAwAFAAkJHyHjAQAHAwAAAA==.',
Py='Pyrothermia:BAACLgAFFH8NAAIdAAYJ6wxTFACQAQAdAAYJ6wxTFACQAQAuAAQKfyAAAh0ACQkVGoUqAMkCAB0ACQkVGoUqAMkCAAAA.',
Qt='Qtkillz:BAAALgADCgQJBAAAAA==.',
Ra='Rancayden:BAAALgAECgEJAQAAAA==.Rawhoof:BAABLgAECn81AAIEAAkJASWBAABfAwAEAAkJASWBAABfAwAAAA==.Razak:BAABLgAECn8mAAIXAAgJ/h+SAgB+AgAXAAgJ/h+SAgB+AgAAAA==.',
Re='Renisa:BAABLgAECn8dAAIJAAgJVBlXQgDqAQAJAAgJVBlXQgDqAQAAAA==.Retman:BAAALgAECgYJEwAAAA==.Reu:BAAALgAECgUJBwAAAA==.Revlyk:BAABLgAECn8dAAIXAAcJ0iF+AwBMAgAXAAcJ0iF+AwBMAgABLgAECgkJMQACAKMgAA==.Rezloh:BAAALgADCgMJAQAAAA==.',
Ri='Rintaro:BAABLgAECn8XAAIKAAkJjwiHHwAMAQAKAAkJjwiHHwAMAQAAAA==.',
Ro='Roccot:BAAALgAECggJDgAAAA==.Roflstomp:BAAALgAECgMJBAABLgAECgYJDAADAAAAAA==.Roostrr:BAABLgAECn8XAAIBAAYJ3x1DVQBIAQABAAYJ3x1DVQBIAQAAAA==.Rotjaw:BAAALgAECgUJCwAAAA==.Roughedge:BAAALgADCgIJAgAAAA==.',
Ru='Rurik:BAAALgADCggJFwAAAA==.',
['Rè']='Rèjuva:BAAALgAECgcJDQAAAA==.',
['Rî']='Rîcflair:BAAALgAECgcJEwAAAA==.',
Sa='Salidfingers:BAAALgADCgYJBgAAAA==.Sanyakulak:BAAALgADCgcJBwABLgAFFAYJFAAiADkXAA==.Sanzo:BAAALgADCgQJBAAAAA==.Savathûn:BAAALgAECgQJCAAAAA==.',
Sc='Scalycat:BAABLgAECn8oAAQRAAkJ2A6WGQDBAQARAAkJ2A6WGQDBAQAfAAYJMAd6RACGAAAcAAIJYwc+GAAzAAAAAA==.Schalla:BAAALgAECgEJAQAAAA==.Scum:BAAALgAECgYJDQAAAA==.Scòrpìòn:BAAALgADCgcJBgABLgAECggJJwAWAF4aAA==.',
Se='Seancody:BAAALgADCgIJAgAAAA==.Selandria:BAAALgADCgQJBAAAAA==.Senate:BAAALgAECgYJCgAAAA==.',
Sh='Shadowbear:BAABLgAECn8YAAIIAAcJDxz2DQDrAQAIAAcJDxz2DQDrAQAAAA==.Shadowoss:BAAALgAECgIJAgAAAA==.Shadygrump:BAAALgAECgYJEQAAAA==.Shaolincito:BAAALgAECgQJBQAAAA==.Sherrilyn:BAAALgADCgkJFQAAAA==.Shocklocke:BAAALgAECgQJBAAAAA==.',
Si='Sigmachad:BAAALgAECgUJCgAAAA==.Silandrus:BAAALgAECgEJAQAAAA==.Silverocean:BAABLgAECn8lAAIPAAgJkB7pDwCUAgAPAAgJkB7pDwCUAgAAAA==.Silvia:BAAALgADCgUJCQAAAA==.Singularity:BAABLgAECn8yAAILAAkJAiY/AAB2AwALAAkJAiY/AAB2AwAAAA==.',
Sk='Skaerx:BAABLgAECn8WAAMEAAYJVBeJQwCXAQAEAAYJ9RWJQwCXAQAmAAQJZhSYHQADAQAAAA==.Skittlez:BAABLgAECn8dAAISAAgJUiGeBgBGAgASAAgJUiGeBgBGAgAAAA==.',
Sl='Slaykween:BAAALgAECgUJBQAAAA==.Slootybooty:BAAALgAECgYJDAAAAA==.',
Sm='Smallz:BAAALgAECgYJCwABLgAECgcJEgADAAAAAA==.',
Sn='Snipersmash:BAAALgAECgQJCAAAAA==.Snooptrogg:BAABLgAECn8jAAIEAAgJQBWNEgDaAQAEAAgJQBWNEgDaAQAAAA==.Snoozumi:BAABLgAFFH8GAAITAAMJKgY/GwCjAAATAAMJKgY/GwCjAAAAAA==.Snuups:BAABLgAECn8oAAIUAAgJ+BklIQDqAQAUAAgJ+BklIQDqAQAAAA==.',
So='Soldiah:BAAALgAECggJEgAAAA==.Sommbra:BAAALgAECgYJBgAAAA==.Souljax:BAAALgADCgcJCQAAAA==.',
Sp='Spacelaser:BAAALgAECgQJBQAAAA==.',
Sq='Sqwurl:BAAALgADCgQJBAAAAA==.',
St='Steakhaus:BAAALgADCgIJAgAAAA==.Stiros:BAAALgADCgUJBgAAAA==.Stonedragon:BAECLgAFFH8LAAIWAAQJTBv0CwBqAQAWAAQJTBv0CwBqAQAuAAQKfykAAxYACAnNJMsFADEDABYACAnNJMsFADEDABsAAgkGDyMcAGoAAAAA.Stormfist:BAAALgAECgYJDAAAAA==.Stormhaven:BAAALgADCggJIQABLgAECgYJEAADAAAAAA==.Stormrender:BAAALgAECgYJDwAAAA==.Stouty:BAAALgADCgMJAwABLgAECgcJFAAcAOkaAA==.',
Su='Sukonamí:BAABLgAECn8iAAMEAAkJexd6EgDbAQAEAAgJaBV6EgDbAQAmAAQJGRslDgBgAQAAAA==.Suzhou:BAABLgAECn8gAAIVAAgJtwgPCgA0AQAVAAgJtwgPCgA0AQAAAA==.Suzoomies:BAAALgADCgcJBwAAAA==.Suzumii:BAAALgAFFAEJAQAAAA==.',
Sw='Sweetcarolin:BAABLgAECn8WAAINAAkJRg99XgDXAQANAAkJRg99XgDXAQAAAA==.Sweetsmercy:BAAALgAECgQJBQAAAA==.Swiftleaf:BAAALgADCgcJBwAAAA==.Swisscheese:BAABLgAECn8cAAIUAAYJ7yLYIgDiAQAUAAYJ7yLYIgDiAQAAAA==.',
Sy='Syraxa:BAAALgADCggJFAABLgAECggJHwAGAC8cAA==.Syril:BAAALgADCgcJDAAAAA==.',
Ta='Tahret:BAAALgADCgQJBQAAAA==.Taquillya:BAAALgADCgYJBgAAAA==.Tarina:BAAALgADCgEJAQAAAA==.Tatersaladin:BAAALgADCgMJAwAAAA==.',
Te='Tenlortin:BAAALgAECgEJAQAAAA==.Terragosa:BAABLgAECn8dAAIdAAgJmBIzNQDNAQAdAAgJmBIzNQDNAQAAAA==.Teryail:BAAALgADCggJCAAAAA==.',
Th='Thade:BAABLgAECn8fAAMmAAkJdCCwAQDPAgAmAAgJFh6wAQDPAgAEAAcJUB5VHwBWAgAAAA==.Thaeleon:BAABLgAECn8hAAMHAAgJUR9bBgB5AgAHAAgJUR9bBgB5AgAGAAYJihz5NADUAQABLgAFFAIJAgADAAAAAA==.Thaneblade:BAAALgAECgIJAgAAAA==.Therizzler:BAAALgAECgUJBQABLgAFFAMJBgAJAL0MAA==.Thickening:BAABLgAECn8UAAITAAUJhQ25LwDZAAATAAUJhQ25LwDZAAAAAA==.Thope:BAAALgAECgUJDAAAAA==.Thoranubran:BAABLgAECn8VAAICAAYJ/w5JGgAMAQACAAYJ/w5JGgAMAQAAAA==.Thrivia:BAAALgAECgYJBgAAAA==.',
Ti='Ticklemychin:BAAALgADCgkJIwAAAA==.Tigani:BAAALgAECgUJDAAAAA==.',
To='Tokemaddab:BAAALgADCgUJBQAAAA==.',
Tr='Trainar:BAAALgAECgQJCAAAAA==.Trickybackup:BAAALgADCgMJAwAAAA==.Triggs:BAAALgAECgcJAgAAAA==.Trollbear:BAAALgAECgcJDQAAAA==.Trondruid:BAAALgADCgYJDQAAAA==.Trooze:BAABLgAECn8gAAIPAAYJkCQECwBhAgAPAAYJkCQECwBhAgAAAA==.Trr:BAABLgAECn8pAAIUAAkJmReyIwCFAgAUAAkJmReyIwCFAgAAAA==.Truckzage:BAAALgADCgcJBwABLgAECggJIQAWAB0eAA==.',
Tu='Tuba:BAAALgAECgYJEAAAAA==.Turim:BAAALgADCgQJBAAAAA==.Tusksrus:BAAALgADCgYJEwAAAA==.',
Ty='Tyrlidd:BAABLgAECn8fAAIWAAgJgA8AKwCkAQAWAAgJgA8AKwCkAQAAAA==.',
Ud='Udon:BAAALgAECgQJBQAAAA==.',
Ul='Ultimazero:BAAALgADCgEJAQAAAA==.',
Un='Unavoidable:BAAALgADCgkJEQAAAA==.Unlikelytale:BAABLgAECn8lAAIaAAkJAyG4BQDdAgAaAAkJAyG4BQDdAgAAAA==.Unmilked:BAAALgAECgIJAgAAAA==.',
Ur='Uricash:BAABLgAECn81AAIdAAkJxBT6GwBCAgAdAAkJxBT6GwBCAgAAAA==.Urzual:BAABLgAECn8jAAIXAAgJDB9LAwBWAgAXAAgJDB9LAwBWAgAAAA==.',
Ut='Utiniócast:BAAALgADCgEJAQAAAA==.',
Va='Vandreynna:BAABLgAECn8xAAICAAkJoyDUAQDwAgACAAkJoyDUAQDwAgAAAA==.',
Ve='Vegèta:BAABLgAECn8ZAAINAAkJVQqPPACIAQANAAkJVQqPPACIAQABLgAECggJJwAWAF4aAA==.Veilaura:BAAALgAECgQJBQAAAA==.Velarria:BAABLgAECn8dAAMWAAkJ4B43FQCOAgAWAAkJ4B43FQCOAgASAAQJjwwcIQDSAAAAAA==.Velikan:BAAALgAECgQJBwABLgAECgYJBgADAAAAAA==.Velsiana:BAAALgAECgQJBwAAAA==.Velveetah:BAAALgAECgIJBAABLgAECgQJEwADAAAAAA==.Verdreht:BAAALgADCgEJAQABLgAECgcJLAAEAO4bAA==.Verita:BAABLgAECn8kAAIjAAYJCiSFAgACAgAjAAYJCiSFAgACAgAAAA==.',
Vi='Viviann:BAABLgAECn8kAAIRAAkJbxGLCADdAQARAAkJbxGLCADdAQAAAA==.',
Vo='Voiager:BAAALgADCgcJCgAAAA==.',
Vr='Vrakal:BAAALgAECgkJDQAAAA==.',
Wa='Wantabehavoc:BAAALgADCgYJDQAAAA==.Wantadeznutz:BAAALgAECgIJAgAAAA==.Warnick:BAAALgADCgQJBQAAAA==.Warraxe:BAAALgADCgUJCAAAAA==.Wayloren:BAABLgAECn8iAAIBAAgJRAmYTwBXAQABAAgJRAmYTwBXAQAAAA==.Waystalker:BAAALgAECgMJAwAAAA==.Wayverly:BAAALgADCgUJBwABLgAECgcJDwADAAAAAA==.',
Wi='Wickathy:BAABLgAECn8sAAIlAAkJrh0sAQC9AgAlAAkJrh0sAQC9AgAAAA==.',
Wo='Wolfcity:BAAALgADCgEJAQAAAA==.Wondertauren:BAAALgADCgIJAgAAAA==.Worstdps:BAAALgADCgcJEwAAAA==.',
Wr='Wrkandtank:BAAALgAECgEJAQABLgAECgUJCgADAAAAAA==.',
Wu='Wuldorr:BAACLgAFFH8IAAIBAAQJGQqoIAArAQABAAQJGQqoIAArAQAuAAQKfyQAAgEACAmuH0QkAJYCAAEACAmuH0QkAJYCAAAA.',
Wy='Wynnifred:BAAALgAECgUJBQAAAA==.',
Xa='Xalatoes:BAAALgAECgMJAwAAAA==.',
Xe='Xethreal:BAAALgADCgMJAwAAAA==.',
Xy='Xype:BAAALgAECgkJEQAAAA==.',
Ya='Yastoria:BAAALgAECgcJEAAAAA==.',
Yi='Yinandtonic:BAAALgAECgEJAQAAAA==.',
Yv='Yvvee:BAAALgADCgcJBwAAAA==.',
Za='Zaalim:BAAALgADCgQJBAAAAA==.Zapdôs:BAAALgAECgQJBAAAAA==.',
Ze='Zeda:BAAALgADCgcJCAABLgAECgQJBQADAAAAAA==.Zephyris:BAAALgAECgUJDAABLgAFFAUJFgAmAO4lAA==.',
Zh='Zheng:BAAALgAECgYJBgAAAA==.',
Zi='Zillia:BAAALgADCgMJAwAAAA==.',
Zo='Zonora:BAAALgAECgYJBgAAAA==.',
Zy='Zyphexd:BAAALgAECgYJDwAAAA==.Zyris:BAAALgADCgcJDQAAAA==.',
['Äs']='Ästro:BAAALgAECgQJBgAAAA==.',
['Äz']='Äzrael:BAABLgAECn8aAAIYAAkJ1BmnBQCoAgAYAAkJ1BmnBQCoAgAAAA==.',
['Åz']='Åznos:BAAALgAECgQJCAAAAA==.',
['Çr']='Çréwüsæðèr:BAABLgAECn8gAAILAAgJZSCDAwCPAgALAAgJZSCDAwCPAgAAAA==.',
['Ðe']='Ðecimus:BAAALgAECgQJCQAAAA==.',
['Ðì']='Ðìaßlo:BAABLgAECn8nAAQWAAgJXho9OQDJAQAWAAcJJhY9OQDJAQASAAcJWBQ5EQCvAQAbAAEJXgAVmwAVAAAAAA==.',
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
