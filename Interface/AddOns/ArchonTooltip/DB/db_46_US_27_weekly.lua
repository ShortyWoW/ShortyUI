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

local lookup = {'Hunter-BeastMastery','Mage-Arcane','Mage-Frost','Hunter-Survival','DeathKnight-Frost','DeathKnight-Unholy','Priest-Shadow','Paladin-Retribution','Hunter-Marksmanship','Paladin-Protection','Unknown-Unknown','DemonHunter-Devourer','Priest-Holy','Monk-Mistweaver','Monk-Windwalker','Paladin-Holy','Druid-Balance','Warlock-Destruction','Shaman-Restoration','Rogue-Subtlety','DemonHunter-Havoc','Rogue-Outlaw','Rogue-Assassination','Warlock-Demonology','Priest-Discipline','Monk-Brewmaster','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Warrior-Fury','Druid-Feral','DeathKnight-Blood','Druid-Restoration','Druid-Guardian','Warrior-Arms','Shaman-Elemental','Shaman-Enhancement',}
local provider = {region='US',realm='Azuremyst',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aaravos:BAAALgAECgYJEAAAAA==.',
Ab='Abysseon:BAAALgAECgQJCQAAAA==.',
Ac='Accretion:BAAALgAECgYJBgAAAA==.',
Ad='Adaria:BAABLgAECn8WAAIBAAcJWgWQZQA3AQABAAcJWgWQZQA3AQAAAA==.Adura:BAAALgADCgcJDwAAAA==.',
Ae='Aeirith:BAABLgAECn8jAAMCAAkJiR2CAACxAgACAAkJiR2CAACxAgADAAEJSgojAAE4AAAAAA==.Aelion:BAAALgAECgEJAQAAAA==.',
Ah='Ahheevoker:BAAALgAECgUJCAAAAA==.',
Ai='Ailsà:BAAALgADCgEJAQAAAA==.',
Al='Aladaria:BAAALgAECgMJAwAAAA==.Alias:BAAALgAECgYJBQAAAA==.Allanonn:BAAALgAECgQJBAAAAA==.Alohomora:BAAALgAECgUJDAAAAA==.Alvist:BAAALgAECgQJCAAAAA==.',
Am='Amarasu:BAABLgAECn8XAAIEAAgJbQ/CEAChAQAEAAgJbQ/CEAChAQAAAA==.Amarlly:BAABLgAECn8YAAIFAAcJ+hTrBQBoAQAFAAcJ+hTrBQBoAQAAAA==.Amenedil:BAAALgAECgMJBwAAAA==.',
An='Anbrew:BAAALgAECgQJBwABLgAFFAUJDAAGAM4dAA==.Ancelina:BAABLgAECn8WAAIHAAYJ8CIaDAADAgAHAAYJ8CIaDAADAgAAAA==.Anderton:BAABLgAECn8cAAIIAAcJnBaeMwCuAQAIAAcJnBaeMwCuAQAAAA==.Andilocks:BAAALgADCgMJAwAAAA==.Aneira:BAAALgAECgIJAwAAAA==.Anuubis:BAAALgADCgYJBgAAAA==.',
Ap='Apagon:BAAALgAECgEJAQAAAA==.Apexxd:BAAALgADCgEJAQAAAA==.Applefritter:BAAALgAECgEJAQABLgAECgcJGwAHAFUZAA==.',
Ar='Archérhiro:BAACLgAFFH8SAAMBAAUJORwYCgByAQABAAUJORwYCgByAQAJAAIJ6QPUIQCHAAAuAAQKfyMAAwEACQmIHBwYAA8CAAkACAkrGdEbAEoCAAEACAnBGhwYAA8CAAAA.Arilias:BAAALgAECgEJAQABLgAECggJIQABANgPAA==.Arillann:BAABLgAECn8tAAIKAAkJph5/AQDFAgAKAAkJph5/AQDFAgAAAA==.Arrook:BAAALgADCgMJAwAAAA==.Arte:BAABLgAECn8tAAIBAAkJbBPlGgD9AQABAAkJbBPlGgD9AQAAAA==.Arthundermis:BAAALgAECgkJEQAAAA==.Artlunarmis:BAAALgADCgEJAQABLgAECgkJEQALAAAAAA==.Arvena:BAABLgAECn8eAAIMAAkJRAYTTAAUAQAMAAkJRAYTTAAUAQAAAA==.',
As='Asclëpius:BAAALgADCgcJBgABLgAECgEJAQALAAAAAA==.Ashymage:BAACLgAFFH8HAAIDAAQJdxGqLwBKAQADAAQJdxGqLwBKAQAuAAQKfysAAgMACAloHbEpAMwCAAMACAloHbEpAMwCAAAA.Askevar:BAAALgAECgYJEQAAAA==.Aspect:BAAALgADCgEJAQABLgADCgkJDgALAAAAAA==.Asriél:BAAALgAECgQJBAAAAA==.Astrona:BAAALgADCgkJFwAAAA==.',
At='Atreus:BAAALgAECgcJEgAAAA==.Attalaguy:BAAALgAECgYJDgAAAA==.',
Au='Audra:BAAALgADCgUJBwAAAA==.',
Az='Azaleah:BAABLgAECn8iAAIIAAgJExMFOgCZAQAIAAgJExMFOgCZAQAAAA==.Azanoth:BAAALgADCgIJAgAAAA==.Azraesha:BAABLgAECn8bAAIMAAgJABEzKwCLAQAMAAgJABEzKwCLAQAAAA==.Azureflamez:BAAALgAECgEJAQAAAA==.Azzul:BAAALgADCgcJBwAAAA==.',
Ba='Baiken:BAAALgADCgEJAQABLgAECgQJCAALAAAAAA==.Banjoman:BAABLgAECn8dAAINAAYJViX4BgCHAgANAAYJViX4BgCHAgAAAA==.Baza:BAAALgADCgYJBgAAAA==.Baýlei:BAABLgAECn8WAAIOAAYJ3w0AJwASAQAOAAYJ3w0AJwASAQAAAA==.',
Be='Beary:BAAALgAECgEJAwAAAA==.Beenaughty:BAAALgAECgEJAQABLgAECgEJAQALAAAAAA==.Belaanna:BAAALgADCgYJCQAAAA==.Beliria:BAAALgADCgUJBgAAAA==.Benimaru:BAAALgAECgEJAQAAAA==.Beriko:BAAALgAECgMJAwAAAA==.Bernat:BAAALgAECgEJAQAAAA==.Beàrdfáce:BAAALgADCgQJBAAAAA==.',
Bi='Bigjuicy:BAAALgAECgYJBgAAAA==.Bimboficate:BAAALgADCgYJBwAAAA==.',
Bl='Blackadder:BAAALgAECgIJAwAAAA==.Blessthefall:BAAALgAECgYJCgAAAA==.Bloodie:BAAALgAECgMJAwAAAA==.Blue:BAABLgAECn8sAAIPAAkJaht1BQCFAgAPAAkJaht1BQCFAgAAAA==.Bluestreak:BAAALgAECgEJAQAAAA==.',
Bo='Bode:BAAALgAECgUJDAAAAA==.Bogern:BAAALgADCgcJBwAAAA==.Bolau:BAAALgADCgYJBwAAAA==.Boltz:BAAALgADCgYJBgAAAA==.Boomhauer:BAAALgADCgcJBwAAAA==.Bopdiz:BAAALgAECgEJAQABLgAECgQJCAALAAAAAA==.Borledish:BAAALgAECgEJAQABLgAECgQJCAALAAAAAA==.Bottosai:BAAALgAECgEJAQAAAA==.',
Br='Branwynn:BAAALgAECgEJAwAAAA==.Breezysha:BAAALgADCgcJCAAAAA==.Brenz:BAAALgAFFAIJAgAAAA==.Brewdaddy:BAAALgAECgQJBQABLgAECgYJHQAQAIsOAA==.Brewdude:BAAALgAECgEJAQAAAA==.Brigor:BAAALgADCgkJCQAAAA==.Brokenblade:BAAALgADCgYJBgAAAA==.Brotherblood:BAAALgADCggJCQAAAA==.',
Bu='Bulldoza:BAAALgAECgQJBAAAAA==.Butterknifeo:BAABLgAFFH8FAAIRAAMJxRRGFwDtAAARAAMJxRRGFwDtAAAAAA==.',
By='Byryja:BAAALgAECgIJAwAAAA==.',
Ca='Cahrazie:BAAALgAECgcJCAAAAA==.Caidinn:BAAALgAECgkJDAAAAA==.Calissancia:BAABLgAECn8eAAIOAAgJNxPKFAC0AQAOAAgJNxPKFAC0AQAAAA==.Calkey:BAABLgAECn8WAAISAAYJUQi4DwDbAAASAAYJUQi4DwDbAAAAAA==.Cathandris:BAAALgADCgEJAQAAAA==.',
Ce='Ceri:BAAALgAECgkJBwAAAA==.',
Ch='Channingtotm:BAACLgAFFH8PAAITAAQJghxkEgAwAQATAAQJghxkEgAwAQAuAAQKfywAAhMACAn3ID4EAP8CABMACAn3ID4EAP8CAAAA.Chantix:BAAALgADCgUJBQAAAA==.Charlemoo:BAAALgADCgUJBQABLgAECgMJAwALAAAAAA==.Cheekymonkey:BAABLgAECn8YAAICAAYJZAn1BQAEAQACAAYJZAn1BQAEAQAAAA==.Chueyé:BAAALgADCgYJBwABLgAFFAMJBgAUAMUOAA==.Chunkyy:BAAALgADCgYJBgAAAA==.Churros:BAABLgAECn8bAAMHAAcJVRkKEgC4AQAHAAcJVRkKEgC4AQANAAIJjROwRgBKAAAAAA==.',
Ci='Cincog:BAAALgAECgQJBAABLgAECgYJCQALAAAAAA==.',
Co='Cordialkylie:BAAALgADCgMJBAAAAA==.',
Cr='Crogrer:BAAALgADCgUJBQAAAA==.Crosslock:BAAALgADCggJJQAAAA==.',
Cu='Cuppycakes:BAAALgADCgcJFAAAAA==.',
Cy='Cynnari:BAAALgAECgEJAQAAAA==.',
Da='Dalaris:BAABLgAECn8WAAIVAAYJrRSoFQA8AQAVAAYJrRSoFQA8AQAAAA==.Dano:BAAALgADCgYJDQAAAA==.Darci:BAAALgAECgIJAgAAAA==.Darlenedark:BAAALgAECgEJAQAAAA==.Darling:BAAALgAECgIJAgAAAA==.Darron:BAAALgAECgEJAQABLgAECgEJAQALAAAAAA==.Darrosh:BAABLgAECn8bAAQWAAgJrhPlCADzAAAWAAYJ/w/lCADzAAAUAAcJjQ2QIQDvAAAXAAMJ9hAyEQCYAAAAAA==.Dazdot:BAAALgADCgQJBAAAAA==.',
De='Deathdevil:BAAALgAECgUJBQAAAA==.Deathlurker:BAAALgADCgQJBAAAAA==.Deathmare:BAAALgADCgMJAwAAAA==.Deathmommy:BAAALgAECgEJAQAAAA==.Deathty:BAAALgAECgMJCgABLgAECgQJCQALAAAAAA==.Dementia:BAAALgADCgMJAwAAAA==.Design:BAABLgAECn8cAAIYAAcJXBSlNwCHAQAYAAcJXBSlNwCHAQAAAA==.Desmeridian:BAAALgAECgUJBQAAAA==.Devotee:BAAALgADCgIJAgAAAA==.',
Dh='Dhish:BAAALgADCggJFwAAAA==.',
Di='Diltlish:BAAALgAECgMJAwAAAA==.Disconcern:BAAALgADCgcJBwAAAA==.Discontent:BAAALgAECgYJDgAAAA==.Discordiä:BAABLgAECn8WAAIZAAcJxRgkDwDgAQAZAAcJxRgkDwDgAQAAAA==.Discspal:BAAALgAECgYJBwAAAA==.',
Dm='Dmginc:BAAALgADCgIJAgAAAA==.',
Do='Doeblin:BAAALgAECgEJAwAAAA==.Donkedixon:BAAALgADCgYJBgAAAA==.Doubtz:BAAALgAECgQJBQABLgAECgQJCAALAAAAAA==.',
Dp='Dpalx:BAAALgAECgQJBAAAAA==.Dpxs:BAABLgAFFH8HAAITAAQJiRZaFQAcAQATAAQJiRZaFQAcAQAAAA==.',
Dr='Dracones:BAAALgAECgUJBwAAAA==.Dragondz:BAAALgADCgYJCwAAAA==.Dragonflai:BAABLgAECn8eAAIDAAgJ3hXNQgCfAQADAAgJ3hXNQgCfAQAAAA==.Dragonkin:BAAALgAECgQJCAAAAA==.Drakkari:BAAALgADCgcJBwAAAA==.Drakkei:BAABLgAECn8cAAIBAAYJWRJCSwArAQABAAYJWRJCSwArAQAAAA==.Drexxsster:BAAALgADCgQJBAAAAA==.Drshortbus:BAAALgADCgYJDQAAAA==.Drumitus:BAAALgADCgYJCAAAAA==.Drunkngrundl:BAABLgAECn8tAAIaAAkJ+SL5AQD/AgAaAAkJ+SL5AQD/AgAAAA==.Drylo:BAEBLgAECn8kAAMbAAkJgx6LAQBvAgAbAAgJxB+LAQBvAgAcAAMJ6xmSPQCmAAAAAA==.',
Du='Dunstir:BAABLgAECn8ZAAIIAAgJ6AXCXgAxAQAIAAgJ6AXCXgAxAQAAAA==.Dusktrekker:BAAALgAECgkJBwAAAA==.',
Dy='Dypshyt:BAABLgAECn8VAAQbAAYJ4xNLIgAYAQAbAAUJUBJLIgAYAQAcAAUJvRE9MwDVAAAdAAIJzARFQwBTAAAAAA==.',
Ed='Edelweíss:BAAALgADCggJGgAAAA==.',
El='Elarol:BAAALgAECgEJAQAAAA==.Eldons:BAAALgADCgIJAgAAAA==.',
Em='Embers:BAABLgAECn8WAAIeAAYJGxNpLAAgAQAeAAYJGxNpLAAgAQAAAA==.Emeralde:BAAALgAECgIJAgAAAA==.Emilia:BAAALgADCgIJAwAAAA==.Emptyheals:BAABLgAECn8kAAIZAAkJhxt5BADMAgAZAAkJhxt5BADMAgAAAA==.',
Er='Erfinden:BAAALgADCgEJAQAAAA==.',
Es='Espers:BAABLgAECn8eAAIRAAgJPRChKwDqAAARAAgJPRChKwDqAAAAAA==.',
Et='Ethellin:BAABLgAECn8XAAIIAAYJowSEjQDSAAAIAAYJowSEjQDSAAAAAA==.',
Fa='Fahrenheit:BAAALgAECgEJAgAAAA==.Farkuat:BAAALgADCgQJBAAAAA==.Fatcastle:BAAALgADCgQJBAAAAA==.',
Fe='Feildmedic:BAAALgADCgUJBQAAAA==.Felmage:BAAALgADCgYJBgAAAA==.Felraiser:BAAALgADCgIJAgABLgADCgUJBgALAAAAAA==.Felwinter:BAABLgAECn8sAAIYAAkJ5RnxDgBxAgAYAAkJ5RnxDgBxAgAAAA==.Femcelgoon:BAAALgADCgEJAQAAAA==.Fenna:BAAALgADCgYJDAAAAA==.Fetor:BAAALgAECgcJEAAAAA==.',
Fi='Finwé:BAAALgAECgMJAwAAAA==.Fistsalot:BAAALgAECgQJBAAAAA==.',
Fl='Fluxarata:BAABLgAECn8YAAIMAAcJ2wssTAAUAQAMAAcJ2wssTAAUAQAAAA==.',
Fr='Fred:BAABLgAECn8WAAIeAAYJ1ge4MwD7AAAeAAYJ1ge4MwD7AAAAAA==.Freddrick:BAAALgADCgQJBAAAAA==.Friendly:BAAALgAECgEJAQAAAA==.Frostbuddy:BAAALgAECgYJCwAAAA==.Frëya:BAAALgADCgYJDQAAAA==.Frío:BAAALgAECgEJAQAAAA==.Frøstitute:BAAALgAECgYJEAAAAA==.',
Fu='Fullmage:BAAALgADCgQJBAAAAA==.',
['Fè']='Fènrïr:BAAALgADCgQJBAAAAA==.',
Ga='Gabel:BAABLgAECn8eAAIfAAgJRRp1BAAkAgAfAAgJRRp1BAAkAgAAAA==.Gadnabit:BAAALgADCgkJCQAAAA==.Gailardia:BAAALgAECgQJBwAAAA==.Galand:BAABLgAECn8XAAMGAAYJAx1FRwBmAQAGAAYJBhtFRwBmAQAgAAEJoiFHLgBhAAAAAA==.Galladin:BAAALgADCggJDgAAAA==.Gardyson:BAAALgAECgUJBgAAAA==.',
Go='Gooblet:BAAALgADCgQJBQAAAA==.Goodfellow:BAAALgAECgEJAQABLgAFFAEJAQALAAAAAA==.Goopy:BAAALgADCgYJAwAAAA==.',
Gr='Graendal:BAAALgADCgQJBAAAAA==.Granite:BAAALgAECgIJAgAAAA==.Granted:BAAALgADCgUJBQAAAA==.Greevil:BAAALgAECgEJAwAAAA==.Gremilien:BAABLgAECn8WAAIJAAYJnw6HDwD1AAAJAAYJnw6HDwD1AAAAAA==.Grimgorr:BAAALgADCgMJAwAAAA==.Gruggrug:BAAALgADCgIJAQAAAA==.Grymdevours:BAAALgADCgYJBgAAAA==.',
Ha='Halleyscomet:BAABLgAECn8WAAIIAAcJOBpqRAAXAgAIAAcJOBpqRAAXAgAAAA==.Happyhammer:BAAALgADCgcJCAAAAA==.Harrod:BAAALgAECgIJAwAAAA==.Hawkwave:BAAALgAECgcJDgABLgAECgkJDAALAAAAAA==.Hazardzone:BAAALgAECgMJCgAAAA==.',
He='Heavyweather:BAAALgADCgcJBwAAAA==.Heftyer:BAAALgAECgMJAwAAAA==.Helioween:BAAALgADCgMJAwAAAA==.Helixon:BAAALgADCgYJBgAAAA==.Hellbad:BAABLgAFFH8IAAIaAAMJSRdbHQDwAAAaAAMJSRdbHQDwAAAAAA==.Hellbine:BAAALgADCgMJAgAAAA==.Hellsspawn:BAAALgADCgEJAQAAAA==.Hexaverse:BAAALgADCgYJBgABLgAECgQJBAALAAAAAA==.',
Ho='Hoardwither:BAAALgADCgEJAQAAAA==.Hogrog:BAAALgADCgMJAwAAAA==.Hokàge:BAACLgAFFH8GAAIUAAMJxQ6zFQDrAAAUAAMJxQ6zFQDrAAAuAAQKfywAAxQACQm5IdkDAJgCABQACQm5IdkDAJgCABcAAQnxEOMcAEMAAAAA.Homealone:BAAALgAECgUJDAAAAA==.',
Hu='Huffles:BAAALgAECgQJBwAAAA==.Hugmachine:BAAALgAECgEJAwAAAA==.Huntinfuzzy:BAAALgAECggJCwAAAA==.Huntn:BAAALgADCggJCAAAAA==.',
Ia='Iamknot:BAAALgAECgQJBgAAAA==.',
Ic='Icemommy:BAAALgADCgQJCAAAAA==.',
Ig='Igothots:BAABLgAECn8eAAMhAAkJfx4BEAC4AgAhAAkJfx4BEAC4AgAfAAEJawmUJwA1AAAAAA==.',
Il='Illariana:BAAALgAECgUJDAAAAA==.',
In='Insanitty:BAAALgAECgcJDAAAAA==.Invincible:BAAALgAECgEJAQABLgAECgIJAgALAAAAAA==.',
Ir='Ironlobo:BAAALgAECgQJBQAAAA==.Ironsolari:BAAALgADCgYJBgAAAA==.Irritable:BAAALgAECgUJDAAAAA==.',
It='Itherious:BAAALgADCgcJHQAAAA==.',
Ja='Jacham:BAAALgAECgYJCgAAAA==.Jackyll:BAAALgAECgIJAgAAAA==.Jango:BAAALgADCgQJBwABLgAECgUJBgALAAAAAA==.Jatix:BAABLgAECn8kAAIIAAgJBCJiCwCpAgAIAAgJBCJiCwCpAgAAAA==.',
Je='Jeetkundo:BAAALgADCgEJAQABLgAECgIJAgALAAAAAA==.Jellymagus:BAAALgAECgIJAgAAAA==.Jellyms:BAAALgAECgIJAgAAAA==.Jellyspinoff:BAAALgAECgMJBQAAAA==.Jellytown:BAABLgAECn8tAAIDAAkJ6hPDIQAiAgADAAkJ6hPDIQAiAgAAAA==.Jessiana:BAAALgADCgcJCgAAAA==.Jezelda:BAAALgAECgQJBgAAAA==.',
Jp='Jpeppers:BAAALgAECgEJAQAAAA==.',
Ju='Jumano:BAAALgAECgMJAwAAAA==.Jundra:BAAALgAECgEJAgAAAA==.',
Ka='Kaineh:BAAALgAECgYJEgAAAA==.Kainë:BAAALgADCgIJAgAAAA==.Kait:BAABLgAECn8uAAIBAAkJ2x8rBADzAgABAAkJ2x8rBADzAgAAAA==.Kamis:BAAALgADCgQJBAAAAA==.Kanaga:BAAALgAECgQJBQAAAA==.Kannan:BAABLgAECn8YAAMMAAgJzxv5LwA8AgAMAAgJzxv5LwA8AgAVAAEJAQdReQAqAAAAAA==.Kashmihhr:BAAALgADCgIJAgAAAA==.Kashmir:BAAALgAECgQJBAAAAA==.Kasmes:BAAALgADCggJGQAAAA==.Kasmius:BAAALgADCgcJCQAAAA==.Kasmus:BAAALgAECgMJAwAAAA==.Kawdor:BAABLgAECn8dAAQQAAYJiw5gLQAmAQAQAAYJiw5gLQAmAQAKAAYJ3A9lFQD1AAAIAAIJeQXxCwEyAAAAAA==.',
Ke='Keetsz:BAAALgAECgYJDAAAAA==.Kelaino:BAAALgADCgQJBQAAAA==.Keledish:BAAALgADCgEJAQAAAA==.',
Kh='Khansmebduke:BAACLgAFFH8FAAMVAAQJNxYfCQAFAQAVAAMJkRkfCQAFAQAMAAEJKgxtWwBJAAAuAAQKfxYAAxUACAmgHFgIAA4CABUABwlGHVgIAA4CAAwACAk1F1c+APsBAAAA.',
Ki='Kiaf:BAAALgADCgcJDQAAAA==.Kiba:BAAALgADCgEJAQAAAA==.Killanick:BAAALgAECgEJAQAAAA==.Kimia:BAAALgADCgYJCQAAAA==.Kirtthedirt:BAAALgADCgMJAwAAAA==.Kirtthehurt:BAABLgAECn8ZAAIDAAcJLxYsSACPAQADAAcJLxYsSACPAQAAAA==.',
Ko='Koldfront:BAAALgADCgMJBQAAAA==.Kollinator:BAAALgADCgYJBwAAAA==.Korso:BAAALgADCgUJCwABLgADCggJDgALAAAAAA==.',
Ky='Kylair:BAABLgAECn8kAAIHAAkJLB73AgDXAgAHAAkJLB73AgDXAgAAAA==.Kynreessa:BAAALgADCgYJCAAAAA==.Kyønshi:BAAALgADCgUJBgAAAA==.',
['Kì']='Kìrito:BAAALgAECgMJAwAAAA==.',
La='Labeya:BAAALgADCgMJAwAAAA==.Lafty:BAAALgAECgQJBgABLgAECgQJCQALAAAAAA==.Laftydh:BAAALgAECgQJCQAAAA==.Lailah:BAAALgADCgIJAgABLgAECggJIgAIABMTAA==.Laine:BAAALgADCgMJAwAAAA==.Landrra:BAAALgAECgQJBAAAAA==.Larac:BAAALgAECgYJBwAAAA==.Lathsong:BAAALgADCgYJDwAAAA==.Lavi:BAAALgADCgQJAwAAAA==.',
Le='Leadge:BAAALgADCgYJBwAAAA==.Lenik:BAABLgAECn8UAAIUAAYJDwisHQAPAQAUAAYJDwisHQAPAQAAAA==.Leskya:BAAALgADCgQJAwAAAA==.',
Li='Libras:BAAALgADCgMJAwAAAA==.Licorice:BAAALgAECgUJBQABLgAECgcJGwAHAFUZAA==.Lieree:BAAALgAECgcJDQAAAA==.Lifeguàrd:BAAALgAECgkJBwAAAA==.Lillana:BAAALgADCgcJCAAAAA==.Lilyfaye:BAAALgADCgcJBwAAAA==.Limosfire:BAAALgAECgQJCAAAAA==.Linsatha:BAAALgAECgMJAwAAAA==.',
Lo='Lockty:BAAALgAECgEJAgABLgAECgQJCQALAAAAAA==.Logi:BAAALgADCgYJCwAAAA==.Lorezever:BAAALgADCgcJDQAAAA==.Lotion:BAAALgADCgIJAgAAAA==.',
Lu='Luar:BAAALgAECgEJAQAAAA==.Lulubean:BAAALgADCgMJBAAAAA==.Lunaris:BAAALgADCgQJBAAAAA==.Lunà:BAAALgAECgUJDAAAAA==.',
Ly='Lythalle:BAAALgAECgEJAQAAAA==.Lythwynn:BAABLgAECn8dAAIIAAgJfxBdTABgAQAIAAgJfxBdTABgAQAAAA==.',
Ma='Mace:BAAALgAECgEJAQAAAA==.Madison:BAAALgAECgEJAQAAAA==.Magdolyn:BAAALgADCgMJAwAAAA==.Mageyboi:BAAALgAECgQJBgABLgAFFAMJBgAUAMUOAA==.Magickul:BAAALgAECgYJDAAAAA==.Magleon:BAAALgADCgIJAgAAAA==.Magonk:BAAALgADCgEJAQAAAA==.Mahano:BAAALgAECgQJCgABLgAECgUJBgALAAAAAA==.Makis:BAAALgAECgMJBQAAAA==.Manavoid:BAABLgAECn8WAAIMAAYJSQhnZQDTAAAMAAYJSQhnZQDTAAAAAA==.Mastor:BAAALgADCgQJBwAAAA==.Maynard:BAABLgAECn8ZAAIOAAYJTxdjHABnAQAOAAYJTxdjHABnAQAAAA==.',
Mc='Mcdouble:BAAALgADCgMJAwAAAA==.',
Me='Meri:BAABLgAECn8bAAIhAAcJoB4qJgAfAgAhAAcJoB4qJgAfAgAAAA==.',
Mi='Miande:BAAALgAECgUJBQAAAA==.Microburst:BAAALgADCgUJBQAAAA==.Minilock:BAABLgAECn8ZAAMSAAYJ5AxkEADVAAAYAAYJwglKawD1AAASAAUJTg5kEADVAAAAAA==.Misogynixy:BAAALgADCgQJBAAAAA==.Missleading:BAAALgADCgYJCwAAAA==.Missused:BAAALgAECgIJAwAAAA==.Mithos:BAAALgAECgUJBwAAAA==.Mithraxa:BAAALgADCgcJCQAAAA==.',
Mo='Mongermook:BAABLgAECn8XAAMiAAYJPQoFHQC7AAAiAAYJPQoFHQC7AAARAAEJxgFhkQAVAAAAAA==.Monnkysham:BAAALgAECgQJBgABLgAECgYJCQALAAAAAA==.Moogledragon:BAAALgADCgMJAwAAAA==.Mooglefur:BAAALgAECgMJAwAAAA==.Moonbloom:BAABLgAECn8aAAIhAAcJPx3tFQAWAgAhAAcJPx3tFQAWAgAAAA==.Morlosh:BAAALgAECgMJAwAAAA==.Moryna:BAABLgAECn8ZAAIjAAgJfgRkGAD0AAAjAAgJfgRkGAD0AAAAAA==.',
Mt='Mthrandir:BAAALgADCgUJBQAAAA==.',
Mu='Muford:BAAALgAECgQJBQABLgAFFAQJCgAaAPQdAA==.Mull:BAAALgAECgUJCAAAAA==.Muloc:BAAALgADCgEJAQAAAA==.',
My='Myaka:BAAALgADCgMJBwAAAA==.',
Na='Naatixa:BAAALgADCgYJCwAAAA==.Nacronor:BAAALgADCggJKQAAAA==.Naiika:BAAALgAECgIJAgAAAA==.Nascha:BAAALgADCgEJAQAAAA==.Nasoj:BAAALgAECgUJCAABLgAECgYJEQALAAAAAA==.',
Ne='Necrotic:BAAALgAECgQJBAAAAA==.Nedalla:BAAALgAECgEJAQAAAA==.Neeve:BAAALgADCgYJBgAAAA==.Nekrotik:BAAALgADCgcJBgAAAA==.Neobahamut:BAAALgADCgEJAQABLgAECgMJAwALAAAAAA==.Netharel:BAAALgADCgIJAgAAAA==.Newports:BAAALgAECgEJAQAAAA==.',
Ni='Nichôlasmage:BAAALgADCgUJBQAAAA==.Nickatnite:BAAALgAECgEJAgAAAA==.Nickelodeon:BAAALgAECgQJBwAAAA==.Nicksaban:BAABLgAECn8cAAIIAAcJahxhKwDQAQAIAAcJahxhKwDQAQAAAA==.Nightgear:BAACLgAFFH8kAAIBAAUJyxohBABeAQABAAUJyxohBABeAQAuAAQKf1IAAwEACAlCIQYIABADAAEACAlCIQYIABADAAkABAneEosUALUAAAAA.Nilux:BAAALgAECgYJDgAAAA==.Ninetails:BAAALgAECgUJCgAAAA==.Niteshadeth:BAAALgADCggJEwAAAA==.Nixeava:BAAALgADCgkJMQAAAA==.',
No='Nogooddruid:BAAALgADCgcJBwAAAA==.Nopetsneeded:BAABLgAECn8kAAIJAAgJVxH8BgCfAQAJAAgJVxH8BgCfAQAAAA==.Nostariel:BAAALgADCgEJAQAAAA==.Noteworthy:BAAALgAECgYJEAABLgAFFAUJDAAGAM4dAA==.',
Ny='Nysong:BAABLgAECn8dAAISAAgJxAYBDAATAQASAAgJxAYBDAATAQAAAA==.',
Od='Oddangel:BAAALgAECgYJEQAAAA==.Odex:BAABLgAECn8VAAIbAAcJjAiyCAAhAQAbAAcJjAiyCAAhAQAAAA==.',
Oh='Ohblergen:BAAALgAECgEJAQAAAA==.',
Ok='Okragren:BAABLgAECn8nAAIkAAkJGAhFHQBjAQAkAAkJGAhFHQBjAQAAAA==.',
Ol='Olehi:BAAALgADCgcJBwAAAA==.',
On='Onos:BAABLgAECn8XAAIBAAcJECQ3IABEAgABAAcJECQ3IABEAgAAAA==.',
Pa='Paleclaw:BAAALgADCgQJBAAAAA==.Pally:BAAALgAECgUJBQAAAA==.Papasmurfz:BAAALgAECgEJAwAAAA==.Paramedic:BAAALgAECgEJAQAAAA==.Pathogen:BAABLgAECn8hAAIGAAkJCx/hEwBcAgAGAAkJCx/hEwBcAgAAAA==.',
Pe='Persephoknee:BAAALgADCgEJAQAAAA==.',
Pf='Pfchen:BAAALgADCgQJBAAAAA==.',
Pl='Plinkerbell:BAAALgADCgcJBgAAAA==.Plumprnickel:BAAALgAECgEJAQAAAA==.Plxkingg:BAAALgADCgUJBQAAAA==.',
Po='Porimma:BAAALgAECgUJDAAAAA==.Pormas:BAAALgAECgYJDwAAAA==.Poseydon:BAAALgADCgQJBAABLgAECgEJAQALAAAAAA==.',
Pr='Prayerz:BAAALgADCgMJAwAAAA==.Proctology:BAAALgAECgQJBAAAAA==.Promethèus:BAAALgAECgQJBAAAAA==.Prosby:BAAALgADCgIJAgAAAA==.Prowlnfool:BAAALgADCgUJBQAAAA==.Pryto:BAAALgADCgkJDgAAAA==.',
Qu='Queedle:BAAALgAECgYJEQAAAA==.',
Ra='Raennis:BAAALgAECgIJAgAAAA==.Rahanumn:BAAALgAECgYJDQAAAA==.Rainsvoker:BAACLgAFFH8dAAIdAAUJcAuHCwBcAQAdAAUJcAuHCwBcAQAuAAQKf0QAAx0ACQnzG54HAPcBAB0ACQnzG54HAPcBABwAAwlgA/hUAEYAAAAA.Ramike:BAAALgAECgcJCAAAAA==.Ratrazarke:BAAALgADCgIJAgAAAA==.Razihel:BAAALgADCgYJCQAAAA==.',
Re='Reaver:BAAALgAECgQJBAAAAA==.Reddan:BAABLgAECn8eAAIIAAgJSQkcUgBQAQAIAAgJSQkcUgBQAQAAAA==.Replicant:BAAALgADCgEJAQAAAA==.Retman:BAAALgAECgMJAQAAAA==.Reylinn:BAAALgAECgQJBAAAAA==.Reï:BAAALgAECgYJEAAAAA==.',
Ri='Ridlei:BAAALgAECgMJBAAAAA==.Ritzon:BAABLgAECn8tAAMeAAkJwSPkAAA8AwAeAAkJwSPkAAA8AwAjAAEJmBetNgBGAAAAAA==.',
Ro='Roxydan:BAABLgAECn8dAAMSAAgJfg03KQAdAQAYAAgJfg1AZwCWAQASAAYJ8Ag3KQAdAQAAAA==.',
Ry='Ryko:BAABLgAECn8VAAIlAAcJ7hHEDwC8AQAlAAcJ7hHEDwC8AQAAAA==.',
Sa='Sanandume:BAAALgADCgEJAQAAAA==.Sanctess:BAAALgAECggJCAAAAA==.Sayomi:BAAALgADCgcJEwAAAA==.',
Se='Secretjuice:BAAALgAECgYJCQAAAA==.Senseijundra:BAAALgAECgIJAgAAAA==.',
Sh='Shabadu:BAAALgADCgQJBAAAAA==.Shadyandi:BAAALgADCgcJCAAAAA==.Shamanhack:BAAALgAECgYJBwAAAA==.Shan:BAAALgADCgYJBgAAAA==.Sheda:BAAALgAECgQJBAAAAA==.Shedia:BAAALgADCgEJAwAAAA==.Shmooves:BAEALgAECgMJAwAAAA==.Shoukei:BAAALgADCgIJAwAAAA==.',
Si='Sianna:BAAALgADCgYJBgAAAA==.Siinful:BAAALgAECgEJAQAAAA==.Simbruh:BAAALgADCgMJAwAAAA==.Sinarria:BAAALgADCgUJBQAAAA==.Sithra:BAAALgADCgEJAQAAAA==.',
Sk='Skeemer:BAAALgAECgQJBAAAAA==.Skeetro:BAAALgAECgEJAQAAAA==.Skips:BAAALgAECgQJCQAAAA==.Skullace:BAAALgAECgYJEgAAAA==.Skybreaker:BAAALgAECgUJCAAAAA==.',
Sm='Smashurfacen:BAAALgADCgcJFAAAAA==.',
Sn='Snitbit:BAAALgADCgkJGgAAAA==.Sno:BAAALgADCgEJAQABLgAECgUJBwALAAAAAA==.Snoopingas:BAAALgADCgEJAQAAAA==.Snpcrklpopu:BAAALgADCgYJCAAAAA==.',
So='Sotzi:BAAALgADCggJEQAAAA==.Souldune:BAAALgAECgYJBgAAAA==.',
Sp='Sparkplugg:BAAALgAECgEJAQAAAA==.',
Sr='Srfreaky:BAAALgADCgkJKgAAAA==.',
St='Stormcunning:BAABLgAECn8WAAIkAAYJCAxdTAAWAQAkAAYJCAxdTAAWAQAAAA==.Stormfire:BAAALgADCgcJBwAAAA==.Stormßringer:BAABLgAECn8UAAIkAAgJERDVMwCJAQAkAAgJERDVMwCJAQAAAA==.Stownr:BAAALgAECgYJBgAAAA==.Strip:BAAALgADCgUJCAAAAA==.Strongclaw:BAAALgADCgUJBQAAAA==.Stumpyborg:BAAALgAECgUJCQAAAA==.Stónéhëárt:BAAALgADCgYJBwABLgAECgkJDAALAAAAAA==.',
Su='Subverse:BAAALgAECgQJBAAAAA==.Sundance:BAAALgAECgUJCwAAAA==.Sune:BAABLgAECn8XAAIHAAYJ8AqTKAADAQAHAAYJ8AqTKAADAQAAAA==.Supplicant:BAAALgADCgQJBwAAAA==.',
Sv='Svellulfr:BAAALgAECgEJAQAAAA==.Svuca:BAAALgADCgcJBwAAAA==.',
Sy='Syldi:BAAALgAECgEJAQABLgAFFAEJAQALAAAAAA==.Sythis:BAAALgADCgUJCwAAAA==.',
['Sä']='Sästa:BAAALgADCgkJCQAAAA==.',
['Sö']='Sörren:BAAALgAECgIJAwAAAA==.',
Ta='Tacosdeasada:BAAALgAECgEJAQAAAA==.Taitertot:BAAALgADCgQJBQAAAA==.Tanelórn:BAAALgADCgcJCwAAAA==.Tanlon:BAAALgAECgEJAQAAAA==.Taykorra:BAAALgADCggJDQAAAA==.',
Te='Telandril:BAABLgAECn8nAAIhAAkJkQ+4JACjAQAhAAkJkQ+4JACjAQAAAA==.Telphin:BAAALgAECgYJBwAAAA==.Tempestira:BAAALgADCgIJCAAAAA==.Tensuken:BAABLgAECn8ZAAIIAAYJpBhLUwBNAQAIAAYJpBhLUwBNAQAAAA==.Teylonna:BAAALgAECgEJAQAAAA==.',
Th='Thadgun:BAAALgADCgkJFQAAAA==.Thadium:BAAALgADCgYJBgAAAA==.Thecword:BAAALgADCgYJBgAAAA==.Themedic:BAAALgAECgUJBwAAAA==.Thergothon:BAAALgAECgEJAQABLgAECgMJAwALAAAAAA==.Thisisdrexx:BAAALgAECgIJAwAAAA==.Thorwrath:BAAALgADCgEJAgAAAA==.Thrazoro:BAAALgAECgMJAwAAAA==.Thrazzoro:BAAALgAECgYJDQAAAA==.',
Ti='Tiarl:BAABLgAECn8kAAINAAgJXRarDgD9AQANAAgJXRarDgD9AQAAAA==.Tiia:BAAALgADCgIJAgAAAA==.Timex:BAABLgAECn8WAAIbAAYJRCD0DgDrAQAbAAYJRCD0DgDrAQAAAA==.Titañick:BAAALgAECgEJAQAAAA==.',
To='Tom:BAAALgAECgYJEAAAAA==.Toosxyfohair:BAAALgAECgIJAwAAAA==.',
Tr='Trainwrekk:BAAALgADCgYJBgAAAA==.Tranqar:BAAALgAECgQJBQAAAA==.Tresg:BAAALgAECgYJCQAAAA==.Trüth:BAAALgADCggJEAAAAA==.',
Ty='Tyrannus:BAAALgADCgYJBgAAAA==.Tyregar:BAAALgADCgYJCgAAAA==.Tyrànda:BAAALgADCgMJAwAAAA==.Tyzy:BAAALgAECgEJAgAAAA==.',
['Tö']='Tötém:BAAALgAECgEJAQAAAA==.',
Ul='Ulanhi:BAABLgAECn8VAAIfAAUJzx3yEACdAQAfAAUJzx3yEACdAQAAAA==.',
Un='Unholy:BAAALgAECgYJDwAAAA==.',
Ur='Urkzul:BAAALgADCgMJAwAAAA==.Ursoth:BAAALgADCgUJCgAAAA==.',
Ut='Uthèrsmight:BAAALgAECgYJBgAAAA==.Uti:BAAALgADCgUJBQAAAA==.',
Uu='Uubs:BAAALgADCgEJAQABLgAFFAMJCgAIAJoSAA==.',
Va='Valakk:BAAALgAECgEJAgAAAA==.Vallak:BAAALgADCgIJAwAAAA==.Valsitril:BAAALgAECgMJAwABLgAECgYJFgAVAK0UAA==.Valthaczar:BAAALgAECgMJBgAAAA==.Vanara:BAAALgADCgEJAQAAAA==.Varadun:BAAALgADCgEJAwABLgADCgkJDgALAAAAAA==.Varrosh:BAAALgADCgYJBgAAAA==.Vathan:BAAALgAECgQJBQAAAA==.',
Ve='Velmora:BAAALgAECgkJCAAAAA==.Velsetin:BAABLgAECn8dAAIDAAcJTBsxTABSAgADAAcJTBsxTABSAgABLgAFFAMJBQARAMUUAA==.Versed:BAAALgADCgUJBQABLgAECgQJBAALAAAAAA==.Veryspooky:BAABLgAECn8XAAIYAAgJLxcHHwD3AQAYAAgJLxcHHwD3AQAAAA==.Vexian:BAAALgADCgcJFgAAAA==.',
Vi='Vicas:BAAALgAECgQJBAAAAA==.',
Vo='Voidofdeath:BAAALgADCgQJBAAAAA==.Voidshiekah:BAAALgADCgEJAQAAAA==.Vorteia:BAAALgADCgYJBgAAAA==.',
['Vé']='Véngéánçé:BAAALgAECgMJBAAAAA==.',
Wa='Wald:BAAALgAECgYJDAAAAA==.Waruh:BAAALgADCgcJCQAAAA==.',
We='Webgar:BAAALgADCgEJAQAAAA==.',
Wh='Whitetoothe:BAAALgAECgQJDwAAAA==.',
Wi='Wistmeaver:BAAALgAECgIJAgAAAA==.Witherhoard:BAAALgADCgEJAQAAAA==.',
['Wå']='Wånheda:BAAALgAECggJEwAAAA==.',
Xa='Xaniana:BAAALgAECgYJBgAAAA==.Xaosin:BAAALgADCgUJBQAAAA==.',
Xe='Xenzak:BAAALgAECgEJAQAAAA==.Xephir:BAAALgADCgMJAwAAAA==.Xerxës:BAAALgAECgEJAQAAAA==.',
Xl='Xl:BAAALgAECgQJBwAAAA==.',
Xo='Xotiko:BAAALgAECgYJBgAAAA==.',
Xu='Xubris:BAAALgADCgYJCQAAAA==.',
Ya='Yaerin:BAABLgAECn8cAAIZAAgJIyLEAgAWAwAZAAgJIyLEAgAWAwAAAA==.',
Yu='Yunarä:BAAALgAECgYJBwAAAA==.Yuukon:BAAALgAECgYJDwAAAA==.',
Za='Zakuul:BAAALgADCgQJBAAAAA==.Zangetsu:BAAALgAECgcJBwAAAA==.Zaxie:BAABLgAECn8aAAIMAAcJXhhXNABkAQAMAAcJXhhXNABkAQAAAA==.',
Ze='Zenwu:BAAALgADCgkJGwAAAA==.Zephrylia:BAAALgADCggJIwAAAA==.Zerama:BAAALgAECgUJBQAAAA==.',
Zh='Zheratul:BAAALgAECgEJAQAAAA==.',
Zi='Zilphia:BAAALgAECgYJDgAAAA==.',
Zu='Zuriel:BAAALgAECgEJAQAAAA==.',
Zy='Zyku:BAAALgADCgIJAgAAAA==.Zylphie:BAAALgADCgcJBwAAAA==.',
['Àm']='Àmagezing:BAAALgAECgMJBAABLgAECgYJJgAIANciAA==.',
['Åj']='Åj:BAAALgADCgcJBwAAAA==.',
['Åp']='Åpexx:BAAALgADCgMJBwAAAA==.',
['Ór']='Órión:BAABLgAECn8VAAIBAAYJ1BLMTgAhAQABAAYJ1BLMTgAhAQAAAA==.',
['Ös']='Östara:BAAALgAECgUJDgAAAA==.',
['ßj']='ßjörn:BAAALgADCgQJBAAAAA==.',
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
