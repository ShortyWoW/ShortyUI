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

local lookup = {'Monk-Mistweaver','Shaman-Enhancement','Warlock-Demonology','Warlock-Destruction','Rogue-Subtlety','Hunter-Marksmanship','Shaman-Restoration','Paladin-Retribution','Druid-Balance','Monk-Brewmaster','Mage-Frost','Priest-Discipline','Priest-Shadow','DeathKnight-Unholy','DeathKnight-Blood','DeathKnight-Frost','Hunter-BeastMastery','Druid-Restoration','Evoker-Augmentation','Druid-Guardian','Unknown-Unknown','Warrior-Arms','Warrior-Fury','Rogue-Assassination','Shaman-Elemental','Druid-Feral','Evoker-Preservation','Evoker-Devastation','Mage-Arcane','DemonHunter-Devourer','Warrior-Protection','DemonHunter-Havoc','Hunter-Survival','Priest-Holy','Monk-Windwalker','DemonHunter-Vengeance','Paladin-Holy','Paladin-Protection',}
local provider = {region='US',realm='Duskwood',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abominasven:BAAALgADCgkJFQAAAA==.',
Ad='Adhira:BAAALgAECgMJAwAAAA==.',
Ae='Aedrias:BAABLgAECn8YAAIBAAcJAw0uIgA0AQABAAcJAw0uIgA0AQAAAA==.Aegennai:BAABLgAECn8WAAICAAcJHAV+DwALAQACAAcJHAV+DwALAQAAAA==.Aegon:BAECLgAFFH8VAAIDAAUJ8SGjEwBpAQADAAUJ8SGjEwBpAQAuAAQKfx0AAwMACQn9HygdAAECAAMABgkfISgdAAECAAQAAwmUHL0pABsBAAAA.Aeli:BAAALgADCgQJBAABLgAECgcJGAABAAMNAA==.Aethelios:BAAALgAECgEJAQAAAA==.Aevaela:BAABLgAECn8tAAIFAAkJchyPAwChAgAFAAkJchyPAwChAgAAAA==.',
Ag='Agilaz:BAABLgAECn8hAAIGAAgJjhmpAwAWAgAGAAgJjhmpAwAWAgAAAA==.Aguas:BAAALgAECgMJBwAAAA==.',
Ah='Ahnzure:BAAALgAECgYJBgABLgAFFAYJFAAHANsZAA==.',
Ak='Akey:BAAALgAECgMJBwAAAQ==.Akhae:BAABLgAECn8cAAIHAAkJExYHFQALAgAHAAkJExYHFQALAgAAAA==.Akrihail:BAAALgADCgEJAQAAAA==.',
Al='Albinism:BAABLgAECn8hAAICAAcJrBR/CACeAQACAAcJrBR/CACeAQAAAA==.Alcadeias:BAABLgAECn8eAAIIAAcJ8xVoSwBjAQAIAAcJ8xVoSwBjAQAAAA==.Alexandros:BAAALgADCgIJAgAAAA==.Allastor:BAAALgADCggJFgAAAA==.Alupindat:BAABLgAECn8hAAIJAAkJfhdQHgANAgAJAAkJfhdQHgANAgAAAA==.',
Am='Amehnet:BAAALgAECgYJBgAAAA==.Amuria:BAAALgADCgQJBAAAAA==.',
An='Anaeda:BAABLgAECn8UAAIIAAgJMAttrgAmAQAIAAgJMAttrgAmAQAAAA==.Angryjim:BAAALgADCgQJAwAAAA==.Angusmcduck:BAAALgADCgUJBQAAAA==.Anubisre:BAAALgAECgYJCQAAAA==.',
Ap='Apparèntly:BAAALgAECgIJAgABLgAECgcJGAABAAMNAA==.',
Aq='Aquindra:BAAALgADCggJDQAAAA==.',
Ar='Arccane:BAAALgAECgQJBgAAAA==.Arthar:BAAALgADCgYJDAAAAA==.',
As='Ashvyth:BAABLgAECn8dAAIKAAgJlR1OBwBdAgAKAAgJlR1OBwBdAgAAAA==.Asmodeus:BAAALgADCgUJBQAAAA==.',
Aw='Awwyeah:BAAALgAECgQJCAABLgAFFAUJGAALANAOAA==.',
Ba='Baeyik:BAAALgAFFAIJAwAAAA==.Baldrr:BAAALgADCgcJEgAAAA==.Balomdruid:BAAALgADCgYJDAAAAA==.Barnabus:BAAALgAECgIJAwAAAA==.',
Be='Beachbecrazy:BAAALgAECgMJBQABLgAECggJHAAHAJYcAA==.Bearforce:BAAALgAECgYJCwAAAA==.Beastcat:BAAALgADCgYJDAAAAA==.Beastlypläyä:BAAALgAECgEJAgAAAA==.Beiral:BAAALgADCgkJEAAAAA==.Berey:BAAALgADCgEJAgABLgAECggJHwALAAgiAA==.',
Bi='Bigblingaxe:BAAALgADCgkJMAAAAA==.Billymayss:BAAALgADCgUJBQAAAA==.Bimbosuzi:BAAALgADCgYJCQAAAA==.',
Bl='Blacksabbth:BAAALgADCgcJDwAAAA==.Blindhealz:BAABLgAECn8cAAMMAAgJXxNsEgC1AQAMAAcJmxVsEgC1AQANAAQJrAkQMwDDAAAAAA==.Blinkzy:BAAALgAECgIJAgAAAA==.',
Bo='Bonerblast:BAAALgAECgIJAgAAAA==.Boston:BAABLgAECn8rAAQOAAgJriT/CwCoAgAOAAgJriT/CwCoAgAPAAcJzA7SFAAvAQAQAAEJAACOGgAAAAAAAA==.',
Br='Brewtholomew:BAABLgAECn8gAAIRAAgJUhEOKwCkAQARAAgJUhEOKwCkAQAAAA==.Briggsey:BAABLgAECn8bAAIDAAcJAAkSVgAqAQADAAcJAAkSVgAqAQAAAA==.Briznot:BAAALgAECgcJDwAAAA==.Brounies:BAABLgAECn8XAAISAAcJmAicQwAEAQASAAcJmAicQwAEAQAAAA==.Bryce:BAABLgAECn8UAAIIAAcJqhRxPQCOAQAIAAcJqhRxPQCOAQAAAA==.Brèanna:BAAALgADCgkJEgAAAA==.',
Bu='Bubbachi:BAAALgAECgYJCwAAAA==.Bubbadubya:BAAALgADCggJBQAAAA==.Bucciarati:BAAALgADCgYJBgAAAA==.Bunnyfu:BAAALgAECgYJCgABLgAECgcJHgATAB8VAA==.Buray:BAAALgADCgEJAQAAAA==.Burningwolf:BAABLgAECn8lAAIHAAgJjCIABgDWAgAHAAgJjCIABgDWAgAAAA==.Burr:BAAALgAECgcJBwAAAA==.Bushmomma:BAABLgAECn8ZAAIUAAcJahbFCQCDAQAUAAcJahbFCQCDAQAAAA==.',
['Bâ']='Bâbygirl:BAABLgAECn8dAAIRAAcJ5wTpWAAFAQARAAcJ5wTpWAAFAQAAAA==.',
Ca='Caitlyn:BAAALgAECgQJBgAAAA==.Caleesia:BAAALgADCggJCQAAAA==.Camdingo:BAAALgAECgcJCwAAAA==.Campana:BAAALgAECgUJBQAAAA==.Capthunder:BAAALgADCgYJDAABLgAECgUJBwAVAAAAAA==.Carnìfex:BAABLgAECn8bAAMWAAYJ7BeNDQBpAQAWAAYJ7BeNDQBpAQAXAAYJJA98VwBOAQAAAA==.Caskaerta:BAAALgAECgMJAwAAAA==.Catbrin:BAAALgAECgcJEAAAAA==.',
Ce='Celáena:BAABLgAECn8gAAIYAAgJGwxwBgCHAQAYAAgJGwxwBgCHAQAAAA==.Cerà:BAAALgAECgQJBAAAAA==.',
Ch='Champkind:BAAALgAECgMJAwAAAA==.Chapslop:BAAALgADCgQJBAAAAA==.Charcoal:BAAALgAECgEJAQAAAA==.Cheetah:BAAALgAECgIJAgAAAA==.',
Cl='Cleos:BAAALgAECgIJAwAAAA==.Clobberben:BAAALgAECgYJEAAAAA==.Cloudbreaker:BAAALgAECgEJAQAAAA==.Cloudkeg:BAAALgAECgMJAwAAAA==.',
Co='Constellate:BAAALgAECgYJBgAAAA==.',
Cr='Crunchyjim:BAAALgADCgMJAgAAAA==.',
Cu='Cuppicake:BAAALgADCgEJAQAAAA==.Cute:BAAALgADCgYJDgAAAA==.',
Cz='Cztalone:BAAALgAECgcJEQAAAA==.',
['Cè']='Cèlane:BAABLgAECn8cAAMZAAkJ8huJHABpAQAZAAcJsRyJHABpAQAHAAMJWgoLWwCRAAAAAA==.',
Da='Dadeeps:BAAALgAECgUJBwAAAA==.Damitsu:BAEBLgAECn8gAAMYAAYJohTgBwBdAQAYAAYJohTgBwBdAQAFAAYJBg11HAAbAQAAAA==.Damnitsu:BAEALgAECgYJCQABLgAECgYJIAAYAKIUAA==.Darkcat:BAABLgAECn8aAAIaAAcJgQUVEgD8AAAaAAcJgQUVEgD8AAAAAA==.Darktrial:BAAALgADCgYJCAAAAA==.Darnaya:BAAALgADCgkJEQAAAA==.Datemike:BAAALgADCgEJAQAAAA==.Dazen:BAAALgAECgIJAgAAAA==.',
De='Deadflexy:BAABLgAECn8UAAIPAAcJwxj+DgCCAQAPAAcJwxj+DgCCAQAAAA==.Deathberry:BAABLgAECn8oAAIDAAgJMxtpHQAAAgADAAgJMxtpHQAAAgAAAA==.Deathdoodles:BAACLgAFFH8GAAIOAAIJHgmyfACWAAAOAAIJHgmyfACWAAAuAAQKfxsAAg4ACAmUFTAwALgBAA4ACAmUFTAwALgBAAAA.Deathvoker:BAAALgAECgMJAwAAAA==.Deekan:BAAALgAECggJEwAAAA==.Degrade:BAAALgAECgMJAwAAAA==.Dejai:BAAALgADCgUJBQAAAA==.Dejavù:BAAALgAECgUJBgAAAA==.Demise:BAAALgADCgYJCQAAAA==.Demonb:BAAALgADCgUJBgAAAA==.Demonicmac:BAAALgADCgMJAwAAAA==.Derick:BAAALgAECgMJBgAAAA==.Deräth:BAAALgAECgYJDAAAAA==.Deviltrigger:BAAALgADCgcJCQABLgADCgkJEQAVAAAAAA==.Devlik:BAAALgAECgEJAQAAAA==.',
Df='Dfresh:BAABLgAECn8aAAIIAAcJEwfdbgAPAQAIAAcJEwfdbgAPAQAAAA==.',
Di='Dinkalopogis:BAAALgADCggJCAAAAA==.Ditsie:BAAALgAECgEJAQAAAA==.Dizzyizzy:BAAALgAECgcJBwAAAA==.',
Do='Dobby:BAAALgAECgMJBwAAAA==.',
Dr='Dragondude:BAABLgAECn8VAAMbAAcJ0xq1CgCmAQAbAAcJ0xq1CgCmAQAcAAEJLQ7yFgA5AAAAAA==.Druidhealer:BAAALgAECgEJAQAAAA==.Druidia:BAAALgAECgUJBwAAAA==.',
Du='Durango:BAABLgAECn8bAAIWAAgJoh26AwBeAgAWAAgJoh26AwBeAgAAAA==.Durgan:BAAALgADCgMJAwAAAA==.',
Dy='Dyelin:BAABLgAECn8dAAMDAAgJlxtWFwAnAgADAAgJlxtWFwAnAgAEAAIJyhN8SQCSAAAAAA==.',
Ea='Eagleballz:BAAALgADCgMJAwAAAA==.',
Ee='Eephus:BAABLgAECn8XAAMYAAgJixIMBQCzAQAYAAgJixIMBQCzAQAFAAYJPAopOQBMAQAAAA==.',
El='Elylle:BAAALgAECgIJBAAAAA==.Elyron:BAABLgAECn8dAAMLAAgJ1xhGJwAGAgALAAgJ1xhGJwAGAgAdAAEJog+YHQA3AAAAAA==.',
Em='Emovision:BAAALgAECgEJAQAAAA==.',
En='Enchantress:BAAALgAECgMJAwAAAA==.Ennoaleh:BAAALgAECgIJAgAAAA==.',
Er='Erlandis:BAAALgADCgIJAgAAAA==.',
Et='Ethelwulf:BAAALgADCgYJCwABLgAECgMJAwAVAAAAAA==.Etheri:BAAALgADCgYJBgAAAA==.',
Ev='Evilorc:BAAALgADCgUJAwAAAA==.Eviltoo:BAAALgADCgEJAQAAAA==.Evozker:BAAALgADCgEJAQAAAA==.Evêlyn:BAAALgADCgQJBAAAAA==.',
Ex='Exerphus:BAAALgAECgUJDQAAAA==.',
Ez='Ezren:BAAALgADCgMJAwAAAA==.',
Fa='Faedove:BAAALgAECgQJBAAAAA==.Fakename:BAABLgAECn8VAAMSAAgJmhu8JQCdAQASAAgJmhu8JQCdAQAJAAEJEhDFgAAwAAAAAA==.Fakesaint:BAABLgAECn8qAAIHAAgJNyKoBAD0AgAHAAgJNyKoBAD0AgAAAA==.Fangstorm:BAABLgAECn8YAAIaAAgJbAkLDwAnAQAaAAgJbAkLDwAnAQAAAA==.Farorê:BAAALgAECgYJCwAAAA==.',
Fe='Felbane:BAABLgAECn8fAAIeAAkJaxfdFwD9AQAeAAkJaxfdFwD9AQAAAA==.Felpally:BAAALgAECgIJAgAAAA==.',
Fl='Fleekjuice:BAAALgADCgcJCgAAAA==.Flexecute:BAABLgAECn8cAAIfAAgJUAVLGAD9AAAfAAgJUAVLGAD9AAAAAA==.',
Fu='Fujimoto:BAAALgAECgUJCgAAAA==.Fujitora:BAAALgAECgEJAQAAAA==.Furpunch:BAAALgADCggJCwAAAA==.',
Ga='Gaiathra:BAAALgAECgEJAQAAAA==.Galaxzia:BAAALgAECgYJDwAAAA==.Gallivia:BAAALgAECgYJCgAAAA==.',
Ge='Gehn:BAAALgAECgEJAQAAAA==.',
Gh='Ghostprodigy:BAAALgADCgcJBwAAAA==.',
Gi='Gideòn:BAAALgAECgYJDAAAAA==.Ginzi:BAABLgAECn8hAAMOAAgJ1QjhUwBCAQAOAAgJVAXhUwBCAQAQAAYJYQpdCgAoAQAAAA==.',
Gl='Glard:BAAALgADCgcJBwAAAA==.',
Go='Gonto:BAAALgADCgYJBgAAAA==.Gopao:BAAALgADCgYJCQABLgAECgcJFAADABsbAA==.',
Gr='Graxus:BAAALgADCgkJIAAAAA==.Greatchez:BAAALgAECgcJDAAAAA==.Greth:BAAALgADCgYJBwAAAA==.Gronky:BAAALgAECgIJAgAAAA==.',
Gu='Gudge:BAABLgAECn8eAAITAAcJHxXPFgCLAQATAAcJHxXPFgCLAQAAAA==.Gummypenguin:BAABLgAECn8VAAMRAAgJGhqZTACDAQARAAcJiBmZTACDAQAGAAYJTQzHVQDyAAABLgAFFAUJFwARAK4gAA==.',
Ha='Hadhox:BAABLgAECn8VAAIXAAgJCAw4HQB/AQAXAAgJCAw4HQB/AQAAAA==.Hakano:BAAALgAECgYJEwAAAA==.Harbiin:BAAALgAECgEJAgAAAA==.Hathdox:BAAALgAECgYJDwABLgAECggJFQAXAAgMAA==.Hawkulees:BAAALgADCgcJBQAAAA==.Hazelnoot:BAABLgAECn8gAAIIAAkJzxsdDACiAgAIAAkJzxsdDACiAgAAAA==.Haûnt:BAAALgADCgUJBwAAAA==.',
He='Hexcist:BAABLgAECn8aAAIgAAgJcQ5CEQByAQAgAAgJcQ5CEQByAQAAAA==.',
Hi='Hitsuryu:BAABLgAECn8VAAIbAAUJGgqhFgDaAAAbAAUJGgqhFgDaAAAAAA==.',
Ho='Hollyanne:BAABLgAECn8ZAAIEAAcJxQaYDQD4AAAEAAcJxQaYDQD4AAAAAA==.Holyfawn:BAAALgADCgEJAQABLgADCgYJBgAVAAAAAA==.Holystrike:BAAALgAECgMJBAAAAA==.Hoonicorn:BAAALgAECgMJCgABLgAECgEJAgAVAAAAAA==.Hornsnap:BAABLgAECn8dAAMHAAcJYR36DwBAAgAHAAcJYR36DwBAAgAZAAEJ+QwhhQA3AAAAAA==.',
Hu='Huanying:BAAALgADCgQJBAAAAA==.Hunalli:BAAALgAECgUJBQABLgAECgcJHgATAB8VAA==.Hunterb:BAAALgADCgkJCQAAAA==.Huuken:BAAALgADCgkJDgAAAA==.',
Hy='Hydropump:BAAALgADCgYJBgAAAA==.Hyst:BAACLgAFFH8JAAQGAAMJdxxKGADQAAAGAAIJ0CNKGADQAAAhAAIJQBeFEwC2AAARAAEJqiZoRABzAAAuAAQKfzUABAYACQmDJaIDAGsDAAYACAnDJaIDAGsDACEACAk4I24CAMoCABEAAwn5I0mTALIAAAAA.',
Ic='Iconius:BAAALgAECgIJAgAAAA==.',
Ie='Ieatsomeshoe:BAAALgAECgYJBgAAAA==.Ieatsomesock:BAAALgADCgYJBwAAAA==.Ieatwetsocks:BAABLgAECn8bAAMHAAYJIBnmNACwAQAHAAYJIBnmNACwAQAZAAYJJRHSKAAZAQAAAA==.',
Il='Illuminatie:BAAALgAECgEJAgABLgAECgMJAwAVAAAAAA==.',
In='Innexdruid:BAAALgADCgUJBQABLgAECggJHgAOAP8dAA==.Insaint:BAABLgAECn8rAAIIAAkJYRUqHwANAgAIAAkJYRUqHwANAgAAAA==.',
Is='Isabellë:BAABLgAECn8WAAMNAAYJCgjLLgDbAAANAAYJCgjLLgDbAAAiAAIJnQMdRwBJAAAAAA==.Isadorra:BAAALgADCgYJBgAAAA==.Iskandar:BAAALgADCgMJAwAAAA==.',
Ja='Jackboy:BAAALgAECgMJAwAAAA==.Jaker:BAAALgAECgEJAgAAAA==.Jalu:BAAALgAECgYJEwAAAA==.Jatia:BAAALgADCgEJAQABLgAECgkJMAAXAIwjAA==.',
Je='Jessamine:BAABLgAECn8hAAILAAkJXxjMFwBdAgALAAkJXxjMFwBdAgAAAA==.Jessicafelba:BAABLgAECn8UAAMDAAcJGxvKJQDSAQADAAYJGxvKJQDSAQAEAAIJVAvacAA1AAAAAA==.Jetta:BAABLgAECn8hAAIaAAcJORHtCgBuAQAaAAcJORHtCgBuAQAAAA==.Jezzak:BAABLgAECn8ZAAIRAAgJQxn4IwDGAQARAAgJQxn4IwDGAQABLgAECggJIAARAEMaAA==.',
Jo='John:BAAALgAECgcJAQAAAA==.Jorien:BAABLgAECn8vAAIRAAkJ9Ra9FAAqAgARAAkJ9Ra9FAAqAgAAAA==.',
Jp='Jp:BAAALgAECgEJAQABLgAECgYJCAAVAAAAAA==.Jps:BAAALgAECgYJCAAAAA==.',
Ka='Kaboonski:BAAALgADCgUJBQAAAA==.Kaboonsky:BAABLgAECn8dAAIiAAgJHxlFGAAaAgAiAAgJHxlFGAAaAgAAAA==.Kabvoker:BAAALgADCgUJBQAAAA==.Kaeamani:BAAALgAECgYJBgAAAA==.Kamikori:BAABLgAECn8UAAIXAAUJEBotKQAyAQAXAAUJEBotKQAyAQAAAA==.Kardels:BAAALgAECgYJEAAAAA==.Karnn:BAACLgAFFH8NAAMjAAQJdh4oBQBrAQAjAAQJdh4oBQBrAQAKAAEJHQFOKgArAAAuAAQKfyEAAyMACAnUI48KAM8CACMACAnUI48KAM8CAAEAAQnIAWl1ABsAAAAA.',
Ke='Keho:BAAALgAECgUJBwAAAA==.',
Ki='Kiascendance:BAAALgAECgUJBgAAAA==.Kiplet:BAABLgAECn8YAAIiAAcJ8xgOGwByAQAiAAcJ8xgOGwByAQAAAA==.',
Ko='Korxon:BAABLgAECn8YAAMMAAgJ5hUoGQDQAQAMAAgJ5hUoGQDQAQAiAAQJDg4IWgDMAAAAAA==.Kotus:BAAALgAECgEJAQAAAA==.',
Kr='Krazilec:BAAALgADCgYJBgABLgADCgYJBgAVAAAAAA==.Krazz:BAAALgADCgYJCQABLgAECgcJFAAPAMMYAA==.',
Ks='Ksyusha:BAAALgAECgMJBwAAAA==.',
['Kä']='Kämi:BAAALgADCgYJCwABLgAECgYJHwALAOUUAA==.',
La='Lahabrea:BAABLgAECn8fAAMDAAgJBA0kSABQAQADAAgJwAokSABQAQAEAAYJ2w3vKwAPAQAAAA==.Lanuadra:BAAALgADCgYJBgABLgAECgkJFwATABscAA==.Lasagne:BAAALgAECgMJBQAAAA==.Lawry:BAAALgAECgUJBgAAAA==.',
Le='Leeara:BAABLgAECn8WAAIeAAgJ3hfCLQCAAQAeAAgJ3hfCLQCAAQAAAA==.Legitpoopoo:BAAALgAECgUJBQABLgAECgcJGgALAA8aAA==.Lem:BAAALgAECgUJBQAAAA==.Lethalbimbo:BAAALgAECgIJAgAAAA==.',
Li='Liammairi:BAAALgAECgIJAwAAAA==.Lichplease:BAAALgAECgEJAQAAAA==.Lillié:BAAALgAECgQJBAAAAA==.Lilpeep:BAAALgADCgMJAwAAAA==.Lilysham:BAACLgAFFH8UAAIHAAYJ2xmOAgAIAgAHAAYJ2xmOAgAIAgAuAAQKfxwAAwcACAlTIUwQAJUCAAcABwmSIEwQAJUCABkAAQnnESSFADcAAAAA.Linddrel:BAAALgAECgYJCwAAAA==.',
Lo='Lomea:BAAALgAECgQJBQAAAA==.Lonristyn:BAAALgADCgYJCgAAAA==.',
Ly='Lyv:BAAALgADCgEJAQAAAA==.',
['Lø']='Løllîe:BAAALgAECgMJBwAAAA==.Løllïe:BAAALgADCgYJDAABLgAECgMJBwAVAAAAAA==.',
Ma='Magatai:BAAALgAECgYJDgAAAA==.Mageless:BAAALgAECgEJAQAAAA==.Magifizzle:BAAALgADCgcJBwAAAA==.Malenrhen:BAAALgADCgkJFgAAAA==.Malotan:BAAALgADCgUJBQABLgADCgkJDgAVAAAAAA==.Mandhos:BAAALgADCgIJAgAAAA==.Marlie:BAAALgAECgkJCQAAAA==.Martlok:BAABLgAECn8fAAMOAAcJ5hjTMgCuAQAOAAcJ5hjTMgCuAQAQAAIJEBbZFABGAAAAAA==.Matalue:BAAALgAECgcJEAAAAA==.Maynis:BAAALgADCgMJAwAAAA==.',
Mc='Mcbrynhammer:BAAALgAECgEJAQAAAA==.',
Me='Methallica:BAAALgAECgUJBgAAAA==.',
Mi='Micflinigan:BAABLgAECn8eAAMXAAgJhBLMHACCAQAXAAcJExPMHACCAQAfAAEJKA8ZNgA0AAAAAA==.Millanne:BAAALgADCgUJBAAAAA==.Minmo:BAAALgADCgUJBQABLgAECgcJGAAiAPMYAA==.Misahaviran:BAAALgADCgQJBAAAAA==.Mishelö:BAAALgADCgMJAwAAAA==.Mistynite:BAAALgADCgQJBAAAAA==.',
Mo='Mochimochi:BAAALgADCgYJDAAAAA==.Moduur:BAAALgAECgYJCgAAAA==.Moonshae:BAABLgAECn8hAAIBAAkJjRKBDwD1AQABAAkJjRKBDwD1AQAAAA==.Mooshata:BAAALgAECgQJBAAAAA==.Morninghunt:BAAALgADCgEJAQABLgAECgkJIQAJAH4XAA==.Mornings:BAAALgAECgYJDQABLgAECgkJIQAJAH4XAA==.Mouse:BAAALgAECgYJDwAAAA==.Moze:BAAALgADCgMJAwAAAA==.',
Mu='Murf:BAAALgADCgMJAwAAAA==.',
My='Mystiquè:BAAALgADCgYJCAAAAA==.',
Na='Naboo:BAAALgADCgIJAgABLgAFFAIJBgAOAB4JAA==.Nails:BAABLgAECn8UAAIFAAcJLRGJEgCFAQAFAAcJLRGJEgCFAQAAAA==.Naithin:BAAALgAECgIJAgAAAA==.Nalarah:BAAALgAECgEJAQAAAA==.Narmaz:BAAALgADCgEJAQAAAA==.Naviriel:BAAALgADCgYJCQABLgAECgcJFAAjACYLAA==.',
Ni='Nightdragon:BAAALgADCgQJBAAAAA==.Nivvix:BAAALgADCgYJBgAAAA==.',
No='Noethra:BAAALgADCgEJAQAAAA==.Noknik:BAAALgADCgUJCAABLgADCgkJDgAVAAAAAA==.Nootloops:BAAALgADCgcJCgABLgAECgkJIAAIAM8bAA==.Noriisa:BAABLgAECn8gAAIRAAgJQxqVIABBAgARAAgJQxqVIABBAgAAAA==.Noudders:BAAALgAECggJEQAAAA==.',
Nu='Nutsandberri:BAAALgADCggJCgAAAA==.',
Od='Odinhand:BAABLgAECn8hAAIJAAkJjQg2GQBvAQAJAAkJjQg2GQBvAQAAAA==.',
Ol='Oliissa:BAAALgADCggJCAAAAA==.',
On='Onepunchman:BAAALgAECgEJAQABLgAECgMJAwAVAAAAAA==.Onibeef:BAAALgAECgIJAgAAAA==.',
Or='Oregar:BAAALgADCgYJBgAAAA==.',
Ou='Ouch:BAAALgADCgEJAQAAAA==.',
Oz='Ozwäld:BAABLgAECn8fAAILAAgJCCJmDgCpAgALAAgJCCJmDgCpAgAAAA==.',
Pa='Paladinb:BAAALgADCgYJBgAAAA==.Pandapí:BAAALgADCgcJFAAAAA==.Panduh:BAACLgAFFH8RAAILAAUJqRSQDQCvAQALAAUJqRSQDQCvAQAuAAQKfy4AAgsACQn5IIwMALsCAAsACQn5IIwMALsCAAAA.Pandóra:BAAALgAECgYJDgAAAA==.Pariousa:BAACLgAFFH8JAAMYAAMJTR1iAwAeAQAYAAMJ0RxiAwAeAQAFAAIJcB74EADBAAAuAAQKfzQAAxgACQnAJSkAAGoDAAUACAmVJUkDAGsDABgACQkzJSkAAGoDAAAA.Patty:BAAALgADCgkJCgAAAA==.',
Pe='Perceval:BAAALgAECgYJCgAAAA==.Pewpewboo:BAACLgAFFH8YAAILAAUJ0A52NgA3AQALAAUJ0A52NgA3AQAuAAQKfygAAgsACQm5HL0zAKQCAAsACQm5HL0zAKQCAAAA.',
Pi='Pigeonhole:BAAALgADCgYJBgABLgAECgQJBAAVAAAAAA==.Pinkeepink:BAAALgAECgYJDwAAAA==.',
Pl='Plates:BAAALgAECgIJAwAAAA==.',
Pr='Pray:BAAALgADCgYJBgAAAA==.',
Qu='Quarantina:BAAALgAECgIJAQAAAA==.',
Ra='Ragnor:BAAALgADCgQJBAAAAA==.Ralganor:BAABLgAECn8hAAIPAAkJ+SCGAgDHAgAPAAkJ+SCGAgDHAgAAAA==.Ramanash:BAAALgADCgYJEgAAAA==.Ravenstrider:BAAALgAECgYJEgAAAA==.Raylerya:BAAALgADCgYJCQAAAA==.Raylish:BAAALgAECgcJDgAAAA==.',
Re='Ren:BAAALgADCgQJBgAAAA==.Retacus:BAAALgADCgEJAQAAAA==.',
Rh='Rhm:BAAALgAECgMJBAAAAA==.Rhylen:BAAALgADCgYJCQABLgAECgcJFAAPAMMYAA==.',
Ri='Rina:BAACLgAFFH8VAAIkAAUJahvgAAA7AQAkAAUJahvgAAA7AQAuAAQKfyQAAiQACAlPIBUCAOoCACQACAlPIBUCAOoCAAAA.Rineli:BAABLgAECn8XAAILAAcJZAxWYABRAQALAAcJZAxWYABRAQAAAA==.Ringadingg:BAABLgAECn8cAAIOAAgJByDkGADnAgAOAAgJByDkGADnAgAAAA==.Riniching:BAAALgAECgEJAQABLgAECggJHAAOAAcgAA==.Rivets:BAAALgADCgMJAwABLgAECgcJFAAFAC0RAA==.',
Ro='Roastduck:BAABLgAECn8bAAIiAAgJ7Bq+CABiAgAiAAgJ7Bq+CABiAgAAAA==.Rosequartz:BAAALgAECgEJAgAAAA==.Rosetas:BAAALgADCggJDgAAAA==.',
Ru='Runeytoon:BAAALgAECgYJDAAAAA==.',
Sa='Sacamano:BAAALgAECgMJAwAAAA==.Sarazah:BAACLgAFFH8JAAIIAAQJlB9xCgCFAQAIAAQJlB9xCgCFAQAuAAQKfywAAggACQkgJSsBAGcDAAgACQkgJSsBAGcDAAAA.',
Sc='Scony:BAAALgAECgcJCgAAAA==.Scribs:BAAALgAECgYJBgAAAA==.',
Sd='Sdiybt:BAABLgAECn8aAAMLAAcJDxrDUAB4AQALAAYJ4hzDUAB4AQAdAAQJ8hcSDAARAQAAAA==.',
Se='Seegon:BAAALgAECgEJAQAAAA==.Selysse:BAAALgAECgUJCQAAAA==.Sephi:BAAALgAECgEJAQAAAA==.Seramis:BAAALgAECgEJAQAAAA==.Servis:BAAALgADCgYJBgAAAA==.Setharoth:BAAALgAECgEJAgAAAA==.Sethena:BAAALgAECgcJAgAAAA==.Severalforms:BAAALgADCgIJAgABLgAECgkJLwAlAEoVAA==.Severautism:BAAALgAECgMJAwABLgAECgkJLwAlAEoVAA==.Severànce:BAAALgADCgQJBAABLgAECgkJLwAlAEoVAA==.Sevotion:BAABLgAECn8vAAQlAAkJShUTCwBgAgAlAAkJShUTCwBgAgAIAAgJKB0lNgBKAgAmAAUJlREmLQClAAAAAA==.',
Sh='Shablammy:BAABLgAECn8VAAIHAAUJDSYQEgAoAgAHAAUJDSYQEgAoAgAAAA==.Shadownome:BAAALgAECgIJBAAAAA==.Shadowolves:BAAALgAECgEJAQAAAA==.Shamandroid:BAAALgADCgUJBQAAAA==.Shanker:BAAALgAECgEJAQAAAA==.Shaolinchii:BAAALgADCgkJEAAAAA==.Shayden:BAAALgAECgIJAgAAAA==.Shinkickerr:BAAALgADCgYJBgAAAA==.Shirø:BAAALgAECgEJAQAAAA==.Shizamthebam:BAAALgAECgQJBAAAAA==.Shäzu:BAAALgAECgEJAQAAAA==.',
Si='Sihtric:BAAALgADCggJDQAAAA==.Silvanosh:BAABLgAECn8aAAIRAAkJVgzjJADCAQARAAkJVgzjJADCAQAAAA==.Silverflame:BAAALgAECgEJAQAAAA==.Sinveil:BAABLgAECn8yAAQhAAkJnBn5BABuAgAhAAkJGRj5BABuAgAGAAcJfRdzKADmAQARAAQJfRH8cgC8AAAAAA==.',
Sk='Skendr:BAAALgAECgMJAwAAAA==.Skullshadow:BAAALgADCgMJAwAAAA==.Skydragon:BAAALgADCgYJDgAAAA==.',
Sl='Slash:BAAALgADCgMJAwAAAA==.Sleepydwarf:BAAALgAECgEJAgAAAA==.Sludgekicker:BAAALgADCgIJAgAAAA==.',
Sm='Smerknd:BAAALgADCgUJCAAAAA==.',
Sp='Spiritly:BAAALgADCggJDgAAAA==.Sprynt:BAAALgAECgcJDAAAAA==.Spudz:BAAALgADCgIJAgAAAA==.',
St='Starlighter:BAAALgADCgEJAQAAAA==.Starmist:BAAALgADCggJBgAAAA==.Stendo:BAAALgAECgMJBAABLgAFFAUJDAAgANsgAA==.Steviewonder:BAAALgAECgYJDAAAAA==.Stfuillhealu:BAAALgAECgcJCwABLgAECgkJLwAlAEoVAA==.Stonemother:BAAALgAECgMJBwAAAA==.Stormbane:BAAALgAECgkJEgAAAA==.Stormcrest:BAAALgADCgkJFAAAAA==.Stormseer:BAAALgAECgIJAgABLgAECgkJEgAVAAAAAA==.',
Su='Sunae:BAAALgADCgkJCQAAAA==.Sunfyrie:BAAALgAECgcJCwAAAA==.Sunn:BAAALgADCgYJBgABLgAECgcJFAAIAP8fAA==.',
Sw='Swampmonster:BAAALgAECgIJAwABLgAECgYJDwAVAAAAAA==.Sweèt:BAAALgAECgQJBwAAAA==.Swockwickdus:BAACLgAFFH8EAAIeAAMJnhuDIgC7AAAeAAMJnhuDIgC7AAAuAAQKfyQAAx4ACAnJIwIRAPYCAB4ACAmRIgIRAPYCACAAAwk/JU4/AP8AAAAA.Swooze:BAAALgADCgUJBQAAAA==.',
Sy='Sylvaria:BAAALgAECgUJBQAAAA==.',
Ta='Tarouhorn:BAAALgAECgIJAwAAAA==.Taurasthunt:BAAALgAECgUJCgABLgAECgcJFgAfAGobAA==.Taurastrage:BAABLgAECn8WAAIfAAcJahulCgDDAQAfAAcJahulCgDDAQAAAA==.Taurdk:BAAALgAECgYJCQABLgAECgcJFgAfAGobAA==.Taurenator:BAAALgADCgEJAwAAAA==.Taursroot:BAAALgADCgIJAgAAAA==.Taylorshift:BAABLgAECn8YAAIJAAcJLB4kDwDdAQAJAAcJLB4kDwDdAQAAAA==.Tazarakk:BAAALgADCgMJAwABLgAECgcJFAAfAAwhAA==.Tazbeard:BAAALgADCgYJCQABLgAECgcJFAAfAAwhAA==.',
Te='Teedos:BAAALgAECggJDQAAAA==.Teetau:BAABLgAECn8dAAIUAAgJqQOPGACbAAAUAAgJqQOPGACbAAAAAA==.',
Th='Thaddaios:BAAALgAECgEJAQABLgAECggJIwAcACsRAA==.Thadregosa:BAABLgAECn8jAAMcAAgJKxHlBACdAQAcAAgJgBDlBACdAQATAAcJvwrEOAC8AAAAAA==.Thander:BAAALgADCgMJAwABLgAECgMJAwAVAAAAAA==.Thannicus:BAAALgAECgYJCwAAAA==.Thedarkskull:BAAALgAECgEJAQAAAA==.Thugnugget:BAAALgADCgEJAQAAAA==.',
Ti='Tibbotanical:BAABLgAECn8cAAISAAgJLxmaIgCyAQASAAgJLxmaIgCyAQAAAA==.Tiblessed:BAAALgADCgEJAQABLgAECggJHAASAC8ZAA==.Tiffy:BAAALgADCggJIgAAAA==.Tintreach:BAAALgAECgQJBQAAAA==.Tirnotham:BAAALgAECgMJBwAAAA==.',
To='Tokalu:BAABLgAECn8UAAIjAAcJJgtvHwAoAQAjAAcJJgtvHwAoAQAAAA==.Tonjudsonson:BAACLgAFFH8SAAIUAAQJniJ7AQCWAQAUAAQJniJ7AQCWAQAuAAQKfyYAAhQACAnkJfcAAGQDABQACAnkJfcAAGQDAAAA.Tonopah:BAABLgAECn8UAAIZAAcJpgqyKQAUAQAZAAcJpgqyKQAUAQAAAA==.Toxix:BAAALgAECgcJEQAAAA==.',
Tr='Travesura:BAAALgADCgIJAgAAAA==.',
Ts='Tsu:BAAALgAECggJDAAAAA==.',
Tu='Tuggsondix:BAAALgAECgUJBQAAAA==.',
Tw='Twiki:BAABLgAECn8WAAIEAAcJ6QV2DwDeAAAEAAcJ6QV2DwDeAAAAAA==.',
Ty='Tyrssana:BAAALgAECgMJBwABLgAFFAMJBQAcAIgCAA==.',
Ug='Uglykitten:BAAALgAECgYJEwAAAA==.',
Un='Uncas:BAAALgAECgEJAQAAAA==.',
Ur='Urdeadtoo:BAAALgAECgcJEAAAAA==.',
Va='Vaererelor:BAAALgAECgEJAgAAAA==.Varnzdort:BAAALgAECgkJCQABLgAFFAYJFAAHANsZAA==.Vassiliki:BAAALgADCgYJCQAAAA==.Vaterunser:BAAALgAECgMJBwAAAA==.Vayleen:BAAALgADCgYJBgAAAA==.',
Ve='Verlynna:BAAALgAECgQJBAAAAA==.',
Vi='Vicky:BAAALgADCgYJCQABLgAECgcJDwAVAAAAAA==.Vierth:BAAALgADCgYJBwAAAA==.Vincenzo:BAACLgAFFH8MAAIjAAQJaSOyAgCXAQAjAAQJaSOyAgCXAQAuAAQKfxoAAiMACAk9I0MEAEgDACMACAk9I0MEAEgDAAAA.Vinhar:BAAALgAECgQJBAAAAA==.Vinlight:BAAALgAECgUJBQAAAA==.Vinsteam:BAAALgAECgcJEQAAAA==.Viridiana:BAAALgAECgEJAQAAAA==.Visea:BAAALgAECgMJBAAAAA==.',
Vl='Vlarett:BAAALgAECgMJBQAAAA==.',
Vo='Voidsavage:BAAALgAECgMJAwAAAA==.Volfson:BAAALgAECgEJAQAAAA==.Volic:BAAALgAECggJHQAAAQ==.',
Vu='Vulpixa:BAAALgADCgkJGgAAAA==.',
Wa='Waps:BAAALgAECgEJAQAAAA==.Warsyeaa:BAAALgADCgQJAwAAAA==.Watevr:BAEALgAECgYJBgABLgAECgYJIAAYAKIUAA==.',
We='Weeniehutjr:BAAALgADCgEJAQABLgAECgEJAQAVAAAAAA==.Wesleypriest:BAABLgAECn8dAAMMAAgJrAnQGQBjAQAMAAgJhwnQGQBjAQAiAAMJCwhqaQCHAAAAAA==.Wesleyswipes:BAAALgADCgEJAQAAAA==.',
Wy='Wybieboy:BAAALgAECgEJAQAAAA==.',
Xa='Xalabro:BAAALgAECgUJEQAAAA==.Xarcus:BAAALgAECgEJAQABLgAECgcJGgALAEkXAA==.',
Xe='Xehorn:BAAALgAECgYJBgABLgAFFAYJFAAHANsZAA==.Xeros:BAAALgADCgcJDwAAAA==.',
Xo='Xousa:BAAALgADCgYJCAABLgAFFAMJCQAYAE0dAA==.',
Xy='Xyknight:BAAALgADCgUJBwAAAA==.Xylas:BAABLgAECn8aAAILAAcJSRcxXwBUAQALAAcJSRcxXwBUAQAAAA==.',
Ya='Yashe:BAABLgAECn8cAAMHAAgJlhygCwB1AgAHAAgJlhygCwB1AgAZAAEJWAjYkQAlAAAAAA==.',
Yi='Yinoa:BAAALgADCgUJBQABLgAECgcJFgAXAJ0XAA==.',
Yo='Yokuni:BAAALgAECgQJBAAAAA==.',
Yu='Yuefei:BAAALgADCgUJBQAAAA==.',
Za='Zakoor:BAAALgAECgMJAwAAAA==.Zareena:BAAALgADCgMJAwAAAA==.Zarnia:BAAALgAECgMJAwAAAA==.Zarrock:BAAALgAECgMJBQAAAA==.Zaurra:BAAALgAECgYJCgAAAA==.',
Ze='Zebbyzebzeb:BAAALgAECgMJAwAAAA==.Zebrow:BAAALgADCgQJBgAAAA==.Zebzap:BAAALgADCgEJAQAAAA==.Zed:BAAALgADCgkJEgAAAA==.Zehorn:BAAALgAECgYJBgABLgAFFAYJFAAHANsZAA==.Zekia:BAAALgAECgQJBQAAAA==.Zenwaldo:BAAALgAECgEJAQAAAA==.Zeratule:BAAALgADCgYJBgAAAA==.Zerm:BAABLgAECn8xAAIIAAkJXRhUFQBPAgAIAAkJXRhUFQBPAgAAAA==.',
Zi='Zinnkura:BAAALgAECgMJBwAAAA==.Zizzix:BAAALgAECgUJCgAAAA==.',
Zo='Zorsa:BAAALgAECgYJDgAAAA==.',
Zu='Zulfrito:BAABLgAECn8dAAMGAAgJOxraBADlAQAGAAgJ7xfaBADlAQAhAAUJ9x62EAC4AQAAAA==.',
['Ñô']='Ñôg:BAAALgADCggJCAAAAA==.',
['Ød']='Ødis:BAAALgADCgcJHQAAAA==.',
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
