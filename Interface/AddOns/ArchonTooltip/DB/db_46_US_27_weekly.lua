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

local lookup = {'Hunter-BeastMastery','Mage-Arcane','Mage-Frost','Hunter-Survival','Unknown-Unknown','Paladin-Retribution','Priest-Shadow','Hunter-Marksmanship','Paladin-Protection','DemonHunter-Devourer','Priest-Holy','Monk-Windwalker','Monk-Mistweaver','Shaman-Restoration','Rogue-Subtlety','Rogue-Outlaw','Rogue-Assassination','Warlock-Demonology','Priest-Discipline','Monk-Brewmaster','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Druid-Balance','Druid-Feral','DeathKnight-Unholy','DeathKnight-Blood','Druid-Restoration','DemonHunter-Havoc','Paladin-Holy','Druid-Guardian','Warlock-Destruction','Shaman-Elemental','Warrior-Fury','Warrior-Arms',}
local provider = {region='US',realm='Azuremyst',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aaravos:BAAALgAECgYJCQAAAA==.',
Ab='Abysseon:BAAALgAECgQJBQAAAA==.',
Ad='Adaria:BAABLgAECn8WAAIBAAcJWgWOZQA3AQABAAcJWgWOZQA3AQAAAA==.Adura:BAAALgADCgcJDwAAAA==.',
Ae='Aeirith:BAABLgAECn8gAAMCAAgJAh0ZAwBLAgACAAgJAh0ZAwBLAgADAAEJSgoT1wA4AAAAAA==.',
Ah='Ahheevoker:BAAALgAECgMJAwAAAA==.',
Ai='Ailsà:BAAALgADCgEJAQAAAA==.',
Al='Aladaria:BAAALgAECgMJAwAAAA==.Alias:BAAALgAECgYJBQAAAA==.Allanonn:BAAALgAECgQJBAAAAA==.Alohomora:BAAALgAECgUJCgAAAA==.Alvist:BAAALgAECgQJBAAAAA==.',
Am='Amarasu:BAABLgAECn8VAAIEAAcJ+Q/CDwBjAQAEAAcJ+Q/CDwBjAQAAAA==.Amarlly:BAAALgAECgYJEQAAAA==.Amenedil:BAAALgAECgMJBAAAAA==.',
An='Anbrew:BAAALgAECgQJBwABLgAECgYJEAAFAAAAAA==.Ancelina:BAAALgAECgYJEAAAAA==.Anderton:BAABLgAECn8VAAIGAAcJ+RI7OgBcAQAGAAcJ+RI7OgBcAQAAAA==.Andilocks:BAAALgADCgMJAwAAAA==.Aneira:BAAALgAECgEJAQAAAA==.Anuubis:BAAALgADCgYJBgAAAA==.',
Ap='Apagon:BAAALgAECgEJAQAAAA==.Applefritter:BAAALgADCgEJAQABLgAECgcJGAAHAIIYAA==.',
Ar='Archérhiro:BAACLgAFFH8MAAMBAAQJpRglBwBsAQABAAQJpRglBwBsAQAIAAIJ6QPIIQCHAAAuAAQKfyAAAwEACAk7INYQAA8CAAgACAkrGZAbAEgCAAEABwnFHtYQAA8CAAAA.Arilias:BAAALgAECgEJAQABLgAECgYJHQABAPgOAA==.Arillann:BAABLgAECn8iAAIJAAkJ0BwJAgB6AgAJAAkJ0BwJAgB6AgAAAA==.Arrook:BAAALgADCgMJAwAAAA==.Arte:BAABLgAECn8iAAIBAAkJmBLQEAAPAgABAAkJmBLQEAAPAgAAAA==.Arthundermis:BAAALgAECggJEAAAAA==.Artlunarmis:BAAALgADCgEJAQABLgAECggJEAAFAAAAAA==.Arvena:BAABLgAECn8ZAAIKAAkJ+gPnOgD5AAAKAAkJ+gPnOgD5AAAAAA==.',
As='Asclëpius:BAAALgADCgcJBgABLgAECgEJAQAFAAAAAA==.Ashymage:BAABLgAECn8iAAIDAAgJyRyyKQDMAgADAAgJyRyyKQDMAgAAAA==.Askevar:BAAALgAECgYJCwAAAA==.Aspect:BAAALgADCgEJAQABLgADCgkJDgAFAAAAAA==.Astrona:BAAALgADCgUJDgAAAA==.',
At='Atreus:BAAALgAECgYJDQAAAA==.Attalaguy:BAAALgAECgYJDgAAAA==.',
Au='Audra:BAAALgADCgUJBwAAAA==.',
Az='Azaleah:BAABLgAECn8iAAIGAAgJExNuJwClAQAGAAgJExNuJwClAQAAAA==.Azanoth:BAAALgADCgIJAgAAAA==.Azraesha:BAAALgAECggJEwAAAA==.Azureflamez:BAAALgAECgEJAQAAAA==.Azzul:BAAALgADCgcJBwAAAA==.',
Ba='Baiken:BAAALgADCgEJAQABLgAECgQJCAAFAAAAAA==.Banjoman:BAABLgAECn8WAAILAAYJeyQ/BQByAgALAAYJeyQ/BQByAgAAAA==.Baza:BAAALgADCgYJBgAAAA==.Baýlei:BAAALgAECgYJEQAAAA==.',
Be='Beary:BAAALgAECgEJAwAAAA==.Belaanna:BAAALgADCgYJCQAAAA==.Beliria:BAAALgADCgUJBgAAAA==.Benimaru:BAAALgAECgEJAQAAAA==.Beriko:BAAALgAECgMJAwAAAA==.Bernat:BAAALgAECgEJAQAAAA==.Beàrdfáce:BAAALgADCgQJBAAAAA==.',
Bi='Bigjuicy:BAAALgAECgYJBgAAAA==.Bimboficate:BAAALgADCgYJBwAAAA==.',
Bl='Blackadder:BAAALgAECgEJAQAAAA==.Blessthefall:BAAALgAECgYJCgAAAA==.Bloodie:BAAALgAECgMJAwAAAA==.Blue:BAABLgAECn8iAAIMAAkJahuoBQA8AgAMAAkJahuoBQA8AgAAAA==.Bluestreak:BAAALgAECgEJAQAAAA==.',
Bo='Bode:BAAALgAECgMJCAAAAA==.Bogern:BAAALgADCgcJBwAAAA==.Bolau:BAAALgADCgYJBwAAAA==.Boltz:BAAALgADCgYJBgAAAA==.Bopdiz:BAAALgAECgEJAQABLgAECgQJBAAFAAAAAA==.Borledish:BAAALgAECgEJAQABLgAECgQJBAAFAAAAAA==.Bottosai:BAAALgAECgEJAQAAAA==.',
Br='Branwynn:BAAALgAECgEJAgAAAA==.Breezysha:BAAALgADCgcJCAAAAA==.Brenz:BAAALgAECgUJCQAAAA==.Brigor:BAAALgADCgkJCQAAAA==.Brokenblade:BAAALgADCgYJBgAAAA==.Brotherblood:BAAALgADCggJCQAAAA==.',
Bu='Bulldoza:BAAALgAECgQJBAAAAA==.Butterknifeo:BAAALgAFFAMJBAAAAA==.',
By='Byryja:BAAALgAECgEJAQAAAA==.',
Ca='Cahrazie:BAAALgAECgUJBgAAAA==.Caidinn:BAAALgAECgkJDAAAAA==.Calissancia:BAABLgAECn8YAAINAAcJhBMPEwCAAQANAAcJhBMPEwCAAQAAAA==.Calkey:BAAALgAECgUJDwAAAA==.Cathandris:BAAALgADCgEJAQAAAA==.',
Ce='Ceri:BAAALgAECgkJBwAAAA==.',
Ch='Channingtotm:BAACLgAFFH8LAAIOAAMJ5xsaDQAJAQAOAAMJ5xsaDQAJAQAuAAQKfyYAAg4ACAlpIFcDANsCAA4ACAlpIFcDANsCAAAA.Charlemoo:BAAALgADCgUJBQABLgAECgMJAwAFAAAAAA==.Cheekymonkey:BAAALgAECgYJEwAAAA==.Chueyé:BAAALgADCgYJBwABLgAECgkJJwAPALAhAA==.Chunkyy:BAAALgADCgYJBgAAAA==.Churros:BAABLgAECn8YAAMHAAcJghi0DAC2AQAHAAcJghi0DAC2AQALAAIJjRPPOABNAAAAAA==.',
Ci='Cincog:BAAALgAECgQJBAABLgAECgYJCQAFAAAAAA==.',
Co='Cordialkylie:BAAALgADCgMJBAAAAA==.',
Cr='Crogrer:BAAALgADCgUJBQAAAA==.Crosslock:BAAALgADCggJHgAAAA==.',
Cu='Cuppycakes:BAAALgADCgcJFAAAAA==.',
Cy='Cynnari:BAAALgAECgEJAQAAAA==.',
Da='Dalaris:BAAALgAECgYJEAAAAA==.Dano:BAAALgADCgYJDQAAAA==.Darlenedark:BAAALgAECgEJAQAAAA==.Darling:BAAALgAECgIJAgAAAA==.Darron:BAAALgAECgEJAQABLgAECgEJAQAFAAAAAA==.Darrosh:BAABLgAECn8VAAQQAAcJgxD8BwC7AAAQAAYJhw/8BwC7AAARAAMJWgt7FAC1AAAPAAYJTwtWIgCwAAAAAA==.Dazdot:BAAALgADCgQJBAAAAA==.',
De='Deathdevil:BAAALgAECgUJBQAAAA==.Deathlurker:BAAALgADCgQJBAAAAA==.Deathmare:BAAALgADCgMJAwAAAA==.Deathmommy:BAAALgAECgEJAQAAAA==.Deathty:BAAALgAECgMJBgABLgAECgQJCAAFAAAAAA==.Deeptroat:BAAALgADCgEJAQABLgAECgcJFQAEAPkPAA==.Dementia:BAAALgADCgMJAwAAAA==.Design:BAABLgAECn8XAAISAAcJWRQpJwCSAQASAAcJWRQpJwCSAQAAAA==.Desmeridian:BAAALgAECgUJBQAAAA==.Devotee:BAAALgADCgIJAgAAAA==.',
Dh='Dhish:BAAALgADCggJFwAAAA==.',
Di='Disconcern:BAAALgADCgcJBwAAAA==.Discontent:BAAALgAECgUJCAAAAA==.Discordiä:BAABLgAECn8WAAITAAcJxRguCgDsAQATAAcJxRguCgDsAQAAAA==.Discspal:BAAALgAECgYJBwAAAA==.',
Dm='Dmginc:BAAALgADCgIJAgAAAA==.',
Do='Doeblin:BAAALgAECgEJAwAAAA==.Donkedixon:BAAALgADCgYJBgAAAA==.',
Dp='Dpalx:BAAALgAECgQJBAAAAA==.Dpxs:BAABLgAFFH8GAAIOAAQJPhaMDQAlAQAOAAQJPhaMDQAlAQAAAA==.',
Dr='Dracones:BAAALgAECgQJBQAAAA==.Dragondz:BAAALgADCgYJCwAAAA==.Dragonflai:BAABLgAECn8dAAIDAAgJlhXiMACgAQADAAgJlhXiMACgAQAAAA==.Dragonkin:BAAALgAECgQJCAAAAA==.Drakkei:BAABLgAECn8WAAIBAAYJ0w6zPQAeAQABAAYJ0w6zPQAeAQAAAA==.Dranubis:BAAALgADCgEJAQAAAA==.Drexxsster:BAAALgADCgQJBAAAAA==.Drshortbus:BAAALgADCgYJDAAAAA==.Drumitus:BAAALgADCgYJCAAAAA==.Drunkngrundl:BAABLgAECn8iAAIUAAkJ8CKMAQDlAgAUAAkJ8CKMAQDlAgAAAA==.Drylo:BAEBLgAECn8VAAIVAAgJix+jBgCIAgAVAAgJix+jBgCIAgAAAA==.',
Du='Dunstir:BAAALgAECgYJEAAAAA==.Dusktrekker:BAAALgAECgkJBwAAAA==.',
Dy='Dypshyt:BAABLgAECn8VAAQWAAYJ4xN+JgDXAAAVAAUJUBJQIgAYAQAWAAUJvRF+JgDXAAAXAAIJzARFQwBTAAAAAA==.',
Ed='Edelweíss:BAAALgADCggJEwAAAA==.',
El='Elarol:BAAALgADCgEJAQAAAA==.Eldons:BAAALgADCgIJAgAAAA==.',
Em='Embers:BAAALgAECgUJCgAAAA==.Emeralde:BAAALgAECgIJAgAAAA==.Emilia:BAAALgADCgIJAwAAAA==.Emptyheals:BAABLgAECn8bAAITAAgJCRlqCAAQAgATAAgJCRlqCAAQAgAAAA==.',
Er='Erfinden:BAAALgADCgEJAQAAAA==.',
Es='Espers:BAABLgAECn8ZAAIYAAgJ5Q20QwAgAQAYAAgJ5Q20QwAgAQAAAA==.',
Et='Ethellin:BAAALgAECgYJEQAAAA==.',
Fa='Fahrenheit:BAAALgAECgEJAgAAAA==.Farkuat:BAAALgADCgQJBAAAAA==.Fatcastle:BAAALgADCgQJBAAAAA==.',
Fe='Feildmedic:BAAALgADCgUJBQAAAA==.Felmage:BAAALgADCgYJBgAAAA==.Felraiser:BAAALgADCgIJAgABLgADCgUJBgAFAAAAAA==.Felwinter:BAABLgAECn8iAAISAAkJrhZeFwDsAQASAAkJrhZeFwDsAQAAAA==.Femcelgoon:BAAALgADCgEJAQAAAA==.Fenna:BAAALgADCgYJDAAAAA==.Fetor:BAAALgAECgcJEAAAAA==.',
Fi='Finwé:BAAALgADCgUJCQAAAA==.Fistsalot:BAAALgAECgEJAQAAAA==.',
Fl='Fluxarata:BAAALgAECgYJDQAAAA==.',
Fr='Fred:BAAALgAECgYJEAAAAA==.Freddrick:BAAALgADCgQJBAAAAA==.Friendly:BAAALgAECgEJAQAAAA==.Frostbuddy:BAAALgAECgYJCwAAAA==.Frëya:BAAALgADCgYJDQAAAA==.Frío:BAAALgAECgEJAQAAAA==.Frøstitute:BAAALgAECgYJCgAAAA==.',
Fu='Fullmage:BAAALgADCgQJBAAAAA==.',
['Fè']='Fènrïr:BAAALgADCgQJBAAAAA==.',
Ga='Gabel:BAABLgAECn8dAAIZAAgJRhr+AgAqAgAZAAgJRhr+AgAqAgAAAA==.Gadnabit:BAAALgADCgkJCQAAAA==.Gailardia:BAAALgAECgEJAwAAAA==.Galand:BAABLgAECn8VAAMaAAYJAx1XNgBgAQAaAAYJUhlXNgBgAQAbAAEJoiFRIgBiAAAAAA==.Galladin:BAAALgADCggJDgAAAA==.Gardyson:BAAALgAECgUJBQAAAA==.',
Go='Gooblet:BAAALgADCgQJBQAAAA==.Goodfellow:BAAALgAECgEJAQABLgAECgYJDQAFAAAAAA==.Goopy:BAAALgADCgYJAwAAAA==.',
Gr='Graendal:BAAALgADCgQJBAAAAA==.Granite:BAAALgAECgIJAgAAAA==.Granted:BAAALgADCgUJBQAAAA==.Greevil:BAAALgAECgEJAwAAAA==.Gremilien:BAABLgAECn8WAAIIAAYJow4hDAAMAQAIAAYJow4hDAAMAQAAAA==.Grimgorr:BAAALgADCgMJAwAAAA==.Gruggrug:BAAALgADCgIJAQAAAA==.Grymdevours:BAAALgADCgYJBgAAAA==.',
Ha='Halleyscomet:BAABLgAECn8WAAIGAAcJOBpqRAAXAgAGAAcJOBpqRAAXAgAAAA==.Happyhammer:BAAALgADCgcJCAAAAA==.Harrod:BAAALgAECgIJAgAAAA==.Hawkwave:BAAALgAECgcJDgABLgAECgkJDAAFAAAAAA==.Hazardzone:BAAALgAECgMJCgAAAA==.',
He='Heavyweather:BAAALgADCgcJBwAAAA==.Heftyer:BAAALgAECgMJAwAAAA==.Helioween:BAAALgADCgMJAwAAAA==.Helixon:BAAALgADCgYJBgAAAA==.Hellbad:BAABLgAFFH8FAAIUAAMJVxbdFADzAAAUAAMJVxbdFADzAAAAAA==.Hellbine:BAAALgADCgMJAgAAAA==.Hellsspawn:BAAALgADCgEJAQAAAA==.',
Ho='Hogrog:BAAALgADCgMJAwAAAA==.Hokàge:BAABLgAECn8nAAMPAAkJsCG2AgCMAgAPAAkJsCG2AgCMAgARAAEJ8RDjHABDAAAAAA==.Homealone:BAAALgAECgUJCQAAAA==.',
Hu='Huffandpuff:BAAALgADCgIJAQAAAA==.Huffles:BAAALgAECgQJBwAAAA==.Hugmachine:BAAALgAECgEJAgAAAA==.Huntinfuzzy:BAAALgAECgYJBwAAAA==.Huntn:BAAALgADCggJCAAAAA==.',
Ia='Iamknot:BAAALgAECgQJBgAAAA==.',
Ic='Icemommy:BAAALgADCgQJCAAAAA==.',
Ig='Igothots:BAABLgAECn8bAAMcAAgJDSEGEAC4AgAcAAgJDSEGEAC4AgAZAAEJawmsHgA1AAAAAA==.',
Il='Illariana:BAAALgAECgUJBwAAAA==.',
In='Insanitty:BAAALgAECgcJCAAAAA==.Invincible:BAAALgAECgEJAQAAAA==.',
Ir='Ironlobo:BAAALgAECgEJAQAAAA==.Ironsolari:BAAALgADCgYJBgAAAA==.Irritable:BAAALgAECgUJCQAAAA==.',
It='Itherious:BAAALgADCgcJGgAAAA==.',
Ja='Jacham:BAAALgAECgYJCAAAAA==.Jackyll:BAAALgADCgIJAgAAAA==.Jango:BAAALgADCgMJAwABLgAECgUJBQAFAAAAAA==.Jatix:BAABLgAECn8jAAIGAAgJAiJABgC1AgAGAAgJAiJABgC1AgAAAA==.',
Je='Jeetkundo:BAAALgADCgEJAQABLgAECgEJAQAFAAAAAA==.Jellymagus:BAAALgAECgIJAgAAAA==.Jellyms:BAAALgADCgcJBwAAAA==.Jellyspinoff:BAAALgAECgMJBQAAAA==.Jellytown:BAABLgAECn8iAAIDAAkJhRKwGwAFAgADAAkJhRKwGwAFAgAAAA==.Jessiana:BAAALgADCgcJCgAAAA==.Jezelda:BAAALgAECgQJBgAAAA==.',
Jp='Jpeppers:BAAALgAECgEJAQAAAA==.',
Ju='Jumano:BAAALgAECgMJAwAAAA==.Jundra:BAAALgAECgEJAgAAAA==.',
Ka='Kaineh:BAAALgAECgYJEAAAAA==.Kainë:BAAALgADCgIJAgAAAA==.Kamis:BAAALgADCgMJAwAAAA==.Kanaga:BAAALgAECgQJBQAAAA==.Kannan:BAABLgAECn8YAAMKAAgJzxv/LwA7AgAKAAgJzxv/LwA7AgAdAAEJAQdReQAqAAAAAA==.Kashmihhr:BAAALgADCgIJAgAAAA==.Kashmir:BAAALgAECgQJBAAAAA==.Kasmes:BAAALgADCggJFQAAAA==.Kasmius:BAAALgADCgUJBgAAAA==.Kasmus:BAAALgAECgMJAwAAAA==.Kawdor:BAABLgAECn8XAAQeAAYJgg7/IQA3AQAeAAYJgg7/IQA3AQAJAAYJIA7vEwDOAAAGAAEJKAGuYQEWAAAAAA==.',
Ke='Keetsz:BAAALgAECgYJCQAAAA==.Kelaino:BAAALgADCgQJBQAAAA==.Keledish:BAAALgADCgEJAQAAAA==.',
Kh='Khansmebduke:BAABLgAECn8WAAMdAAgJoBxfBQAYAgAdAAcJRh1fBQAYAgAKAAgJNRdcPgD7AQAAAA==.',
Ki='Kiaf:BAAALgADCgcJDQAAAA==.Kiba:BAAALgADCgEJAQAAAA==.Killanick:BAAALgAECgEJAQAAAA==.Kimia:BAAALgADCgYJCQAAAA==.Kirtthedirt:BAAALgADCgMJAwAAAA==.Kirtthehurt:BAAALgAECgYJEgAAAA==.',
Ko='Koldfront:BAAALgADCgMJBQAAAA==.Kollinator:BAAALgADCgYJBwAAAA==.Korso:BAAALgADCgUJCwABLgADCggJDgAFAAAAAA==.',
Ky='Kylair:BAABLgAECn8ZAAIHAAkJkBrXAwB1AgAHAAkJkBrXAwB1AgAAAA==.Kynreessa:BAAALgADCgYJCAAAAA==.Kyønshi:BAAALgADCgUJBgAAAA==.',
['Kì']='Kìrito:BAAALgAECgIJAgAAAA==.',
La='Labeya:BAAALgADCgMJAwAAAA==.Lafty:BAAALgAECgQJBQABLgAECgQJCAAFAAAAAA==.Laftydh:BAAALgAECgQJCAAAAA==.Lailah:BAAALgADCgIJAgABLgAECggJIgAGABMTAA==.Landrra:BAAALgAECgQJBAAAAA==.Larac:BAAALgAECgMJBAAAAA==.Lathsong:BAAALgADCgYJDwAAAA==.Lavi:BAAALgADCgQJAwAAAA==.',
Le='Leadge:BAAALgADCgYJBwAAAA==.Lenik:BAAALgAECgYJDgAAAA==.Leskya:BAAALgADCgQJAwAAAA==.',
Li='Libras:BAAALgADCgMJAwAAAA==.Licorice:BAAALgAECgUJBQABLgAECgcJGAAHAIIYAA==.Lieree:BAAALgAECgUJCwAAAA==.Lifeguàrd:BAAALgAECgkJBwAAAA==.Lillana:BAAALgADCgcJCAAAAA==.Lilyfaye:BAAALgADCgcJBwAAAA==.Limosfire:BAAALgAECgIJBQAAAA==.Linsatha:BAAALgAECgMJAwAAAA==.',
Lo='Logi:BAAALgADCgYJCwAAAA==.Lorezever:BAAALgADCgcJDQAAAA==.Lotion:BAAALgADCgIJAgAAAA==.',
Lu='Luar:BAAALgADCgcJEQAAAA==.Lulubean:BAAALgADCgMJBAAAAA==.Lunaris:BAAALgADCgQJBAAAAA==.Lunà:BAAALgAECgUJDAAAAA==.',
Ly='Lythalle:BAAALgAECgEJAQAAAA==.Lythwynn:BAABLgAECn8ZAAIGAAgJmg+xQABHAQAGAAgJmg+xQABHAQAAAA==.',
Ma='Madison:BAAALgADCgYJCQAAAA==.Magdolyn:BAAALgADCgMJAwAAAA==.Magickul:BAAALgAECgYJDAAAAA==.Magleon:BAAALgADCgIJAgAAAA==.Magonk:BAAALgADCgEJAQAAAA==.Mahano:BAAALgAECgQJBgABLgAECgUJBQAFAAAAAA==.Makis:BAAALgAECgMJBQAAAA==.Manavoid:BAAALgAECgYJEAAAAA==.Mastor:BAAALgADCgQJBwAAAA==.Maynard:BAAALgAECgYJEwAAAA==.',
Mc='Mcdouble:BAAALgADCgMJAwAAAA==.',
Me='Meri:BAABLgAECn8YAAIcAAcJoB4sJgAfAgAcAAcJoB4sJgAfAgAAAA==.',
Mi='Miande:BAAALgAECgUJBQAAAA==.Microburst:BAAALgADCgUJBQAAAA==.Minilock:BAAALgAECgYJEwAAAA==.Misogynixy:BAAALgADCgQJBAAAAA==.Missleading:BAAALgADCgQJBQAAAA==.Missused:BAAALgAECgEJAQAAAA==.Mithos:BAAALgAECgUJBwAAAA==.Mithraxa:BAAALgADCgQJBAAAAA==.',
Mo='Mongermook:BAABLgAECn8WAAMfAAYJ8wkGHQC7AAAfAAYJ8wkGHQC7AAAYAAEJxgFbkQAVAAAAAA==.Monnkysham:BAAALgAECgQJBgABLgAECgYJCQAFAAAAAA==.Moogledragon:BAAALgADCgMJAwAAAA==.Mooglefur:BAAALgAECgMJAwAAAA==.Moonbloom:BAABLgAECn8YAAIcAAUJTB7sHwCBAQAcAAUJTB7sHwCBAQAAAA==.Morlosh:BAAALgAECgMJAwAAAA==.Moryna:BAAALgAECggJEwAAAA==.',
Mt='Mthrandir:BAAALgADCgUJBQAAAA==.',
Mu='Muford:BAAALgAECgQJBAABLgAFFAQJBgAUACYYAA==.Mull:BAAALgAECgUJBQAAAA==.',
My='Myaka:BAAALgADCgMJBwAAAA==.',
Na='Naatixa:BAAALgADCgYJCwAAAA==.Nacronor:BAAALgADCggJIgAAAA==.Naiika:BAAALgAECgIJAgAAAA==.Nascha:BAAALgADCgEJAQAAAA==.Nasoj:BAAALgAECgUJBgABLgAECgYJDQAFAAAAAA==.',
Ne='Necrotic:BAAALgAECgQJBAAAAA==.Nedalla:BAAALgADCgcJDgAAAA==.Neeve:BAAALgADCgYJBgAAAA==.Nekrotik:BAAALgADCgcJBgAAAA==.Neobahamut:BAAALgADCgEJAQABLgAECgIJAgAFAAAAAA==.Netharel:BAAALgADCgIJAgAAAA==.Newports:BAAALgAECgEJAQAAAA==.',
Ni='Nichôlasmage:BAAALgADCgUJBQAAAA==.Nickatnite:BAAALgAECgEJAgAAAA==.Nickelodeon:BAAALgAECgQJBwAAAA==.Nicksaban:BAABLgAECn8VAAIGAAcJahvcJgCoAQAGAAcJahvcJgCoAQAAAA==.Nightgear:BAACLgAFFH8aAAIBAAUJkhchBABeAQABAAUJkhchBABeAQAuAAQKf1IAAwEACAlCIQgIABADAAEACAlCIQgIABADAAgABAneEr8QAMEAAAAA.Nilux:BAAALgAECgQJCAAAAA==.Ninetails:BAAALgAECgUJCgAAAA==.Niteshadeth:BAAALgADCgYJDAAAAA==.Nixeava:BAAALgADCggJKAAAAA==.',
No='Nopetsneeded:BAABLgAECn8fAAIIAAcJAhD3CABHAQAIAAcJAhD3CABHAQAAAA==.Nostariel:BAAALgADCgEJAQAAAA==.Noteworthy:BAAALgAECgYJEAAAAA==.',
Ny='Nysong:BAABLgAECn8XAAIgAAgJWwZ4CQAQAQAgAAgJWwZ4CQAQAQAAAA==.',
Od='Oddangel:BAAALgAECgYJDQAAAA==.Odex:BAABLgAECn8UAAIVAAcJfAd/BgAyAQAVAAcJfAd/BgAyAQAAAA==.',
Oh='Ohblergen:BAAALgAECgEJAQAAAA==.',
Ok='Okragren:BAABLgAECn8gAAIhAAgJ/wclHQAtAQAhAAgJ/wclHQAtAQAAAA==.',
On='Onos:BAABLgAECn8WAAIBAAcJECQ5IABEAgABAAcJECQ5IABEAgAAAA==.',
Pa='Paleclaw:BAAALgADCgQJBAAAAA==.Pally:BAAALgAECgUJBQAAAA==.Papasmurfz:BAAALgAECgEJAwAAAA==.Pathogen:BAABLgAECn8cAAIaAAkJkR1cDgBQAgAaAAkJkR1cDgBQAgAAAA==.',
Pe='Persephoknee:BAAALgADCgEJAQAAAA==.',
Pf='Pfchen:BAAALgADCgQJBAAAAA==.',
Pl='Plinkerbell:BAAALgADCgcJBgAAAA==.Plumprnickel:BAAALgAECgEJAQAAAA==.Plxkingg:BAAALgADCgUJBQAAAA==.',
Po='Porimma:BAAALgAECgUJCQAAAA==.Pormas:BAAALgAECgYJDgAAAA==.Poseydon:BAAALgADCgQJBAABLgAECgEJAQAFAAAAAA==.',
Pr='Prayerz:BAAALgADCgMJAwAAAA==.Proctology:BAAALgAECgQJBAAAAA==.Promethèus:BAAALgAECgQJBAAAAA==.Prosby:BAAALgADCgIJAgAAAA==.Prowlnfool:BAAALgADCgEJAQAAAA==.Pryto:BAAALgADCgkJDgAAAA==.',
Qu='Queedle:BAAALgAECgYJCwAAAA==.',
Qw='Qwacker:BAAALgADCgEJAQAAAA==.',
Ra='Raennis:BAAALgAECgEJAQAAAA==.Rahanumn:BAAALgAECgYJDAAAAA==.Rainsvoker:BAACLgAFFH8dAAIXAAUJcAvJBwBgAQAXAAUJcAvJBwBgAQAuAAQKf0QAAxcACQnzG4YFAP8BABcACQnzG4YFAP8BABYAAwlgA85CAEYAAAAA.Ramike:BAAALgAECgYJBgAAAA==.Ratrazarke:BAAALgADCgIJAgAAAA==.Razihel:BAAALgADCgYJCQAAAA==.',
Re='Reaver:BAAALgAECgQJBAAAAA==.Reddan:BAABLgAECn8cAAIGAAcJNwqhQgBCAQAGAAcJNwqhQgBCAQAAAA==.Retman:BAAALgADCgIJAwAAAA==.Reylinn:BAAALgAECgQJBAAAAA==.Reï:BAAALgAECgYJDgAAAA==.',
Ri='Ridlei:BAAALgAECgMJBAAAAA==.Ritzon:BAABLgAECn8iAAMiAAkJXSBeAwCeAgAiAAgJmiFeAwCeAgAjAAEJrRd6KABHAAAAAA==.',
Ro='Roxydan:BAABLgAECn8dAAMgAAgJfg08KQAdAQASAAgJfg0/ZwCWAQAgAAYJ8Ag8KQAdAQAAAA==.',
Ry='Ryko:BAAALgAECgcJEgAAAA==.',
Sa='Sanandume:BAAALgADCgEJAQAAAA==.Sanctess:BAAALgAECggJCAAAAA==.Santadeath:BAAALgADCgIJAgAAAA==.Sayomi:BAAALgADCgcJEwAAAA==.',
Se='Secretjuice:BAAALgAECgIJAgAAAA==.Senseijundra:BAAALgAECgIJAgAAAA==.',
Sh='Shabadu:BAAALgADCgQJBAAAAA==.Shadyandi:BAAALgADCgcJCAAAAA==.Shamanhack:BAAALgAECgQJBAAAAA==.Shan:BAAALgADCgYJBgAAAA==.Sheda:BAAALgAECgQJBAAAAA==.Shedia:BAAALgADCgEJAwAAAA==.Shmooves:BAEALgADCgYJCgAAAA==.Shoukei:BAAALgADCgIJAwAAAA==.',
Si='Sianna:BAAALgADCgYJBgAAAA==.Siinful:BAAALgAECgEJAQAAAA==.Simbruh:BAAALgADCgMJAwAAAA==.Sinarria:BAAALgADCgUJBQAAAA==.Sithra:BAAALgADCgEJAQAAAA==.',
Sk='Skeemer:BAAALgAECgIJAgAAAA==.Skeetro:BAAALgAECgEJAQAAAA==.Skips:BAAALgAECgQJCQAAAA==.Skullace:BAAALgAECgYJDAAAAA==.Skybreaker:BAAALgAECgUJCAAAAA==.',
Sm='Smashurfacen:BAAALgADCgcJFAAAAA==.',
Sn='Snitbit:BAAALgADCgkJGgAAAA==.Sno:BAAALgADCgEJAQABLgAECgUJBwAFAAAAAA==.Snoopingas:BAAALgADCgEJAQAAAA==.Snpcrklpopu:BAAALgADCgYJCAAAAA==.',
So='Sotzi:BAAALgADCggJEQAAAA==.Souldune:BAAALgAECgYJBgAAAA==.',
Sp='Sparkplugg:BAAALgAECgEJAQAAAA==.',
Sr='Srfreaky:BAAALgADCggJIQAAAA==.',
St='Stormcunning:BAABLgAECn8WAAIhAAYJCAxYTAAWAQAhAAYJCAxYTAAWAQAAAA==.Stormfire:BAAALgADCgcJBwAAAA==.Stormßringer:BAABLgAECn8UAAIhAAgJERDWMwCJAQAhAAgJERDWMwCJAQAAAA==.Stownr:BAAALgAECgYJBgAAAA==.Strip:BAAALgADCgUJBwAAAA==.Strongclaw:BAAALgADCgUJBQAAAA==.Stumpyborg:BAAALgAECgMJAwAAAA==.Stónéhëárt:BAAALgADCgYJBwABLgAECgkJDAAFAAAAAA==.',
Su='Subverse:BAAALgAECgQJBAAAAA==.Sundance:BAAALgAECgMJBQAAAA==.Sune:BAAALgAECgQJDAAAAA==.Supplicant:BAAALgADCgQJBwAAAA==.',
Sv='Svellulfr:BAAALgAECgEJAQAAAA==.',
Sy='Syldi:BAAALgADCgMJAwAAAA==.Sythis:BAAALgADCgUJCwAAAA==.',
['Sä']='Sästa:BAAALgADCgkJCQAAAA==.',
['Sö']='Sörren:BAAALgAECgEJAQAAAA==.',
Ta='Tacosdeasada:BAAALgADCgIJAgAAAA==.Taitertot:BAAALgADCgQJBQAAAA==.Tanelórn:BAAALgADCgcJCAAAAA==.Tanlon:BAAALgAECgEJAQAAAA==.Taykorra:BAAALgADCggJDQAAAA==.',
Te='Telandril:BAABLgAECn8cAAIcAAkJKA9+HACcAQAcAAkJKA9+HACcAQAAAA==.Telphin:BAAALgAECgYJBgAAAA==.Tempestira:BAAALgADCgIJBgAAAA==.Tensuken:BAAALgAECgUJEgAAAA==.Teylonna:BAAALgAECgEJAQAAAA==.',
Th='Thadgun:BAAALgADCgkJFQAAAA==.Thadium:BAAALgADCgYJBgAAAA==.Thecword:BAAALgADCgYJBgAAAA==.Themedic:BAAALgAECgEJAgAAAA==.Thergothon:BAAALgAECgEJAQABLgAECgMJAwAFAAAAAA==.Thisisdrexx:BAAALgAECgIJAwAAAA==.Thrazoro:BAAALgADCgcJCwAAAA==.Thrazzoro:BAAALgAECgYJCgAAAA==.',
Ti='Tiarl:BAABLgAECn8eAAILAAgJ+RE3EgCKAQALAAgJ+RE3EgCKAQAAAA==.Tiia:BAAALgADCgIJAgAAAA==.Timex:BAABLgAECn8WAAIVAAYJRCDyDgDrAQAVAAYJRCDyDgDrAQAAAA==.Titañick:BAAALgAECgEJAQAAAA==.',
To='Tom:BAAALgAECgUJCgAAAA==.Tonn:BAAALgADCgIJAQAAAA==.Toosxyfohair:BAAALgAECgEJAQAAAA==.',
Tr='Trainwrekk:BAAALgADCgYJBgAAAA==.Tresg:BAAALgAECgYJCQAAAA==.Trüth:BAAALgADCggJEAAAAA==.',
Ty='Tyrannus:BAAALgADCgYJBgAAAA==.Tyregar:BAAALgADCgYJCgAAAA==.Tyrànda:BAAALgADCgMJAwAAAA==.Tyzy:BAAALgAECgEJAQAAAA==.',
['Tö']='Tötém:BAAALgAECgEJAQAAAA==.',
Ul='Ulanhi:BAABLgAECn8VAAIZAAUJzx3yEACdAQAZAAUJzx3yEACdAQAAAA==.',
Un='Unholy:BAAALgAECgYJDwAAAA==.',
Ur='Urkzul:BAAALgADCgMJAwAAAA==.Ursoth:BAAALgADCgUJCgAAAA==.',
Ut='Uthèrsmight:BAAALgAECgUJBQAAAA==.Uti:BAAALgADCgUJBQAAAA==.',
Uu='Uubs:BAAALgADCgEJAQABLgAECgIJAgAFAAAAAA==.',
Va='Valakk:BAAALgADCgkJEgAAAA==.Vallak:BAAALgADCgIJAwAAAA==.Valthaczar:BAAALgAECgMJBgAAAA==.Vanara:BAAALgADCgEJAQAAAA==.Varadun:BAAALgADCgEJAwABLgADCgkJDgAFAAAAAA==.Varrosh:BAAALgADCgYJBgAAAA==.Vathan:BAAALgAECgQJBQAAAA==.',
Ve='Velmora:BAAALgAECgkJCAAAAA==.Velsetin:BAABLgAECn8dAAIDAAcJTBs8TABSAgADAAcJTBs8TABSAgABLgAFFAMJBAAFAAAAAA==.Versed:BAAALgADCgUJBQABLgAECgQJBAAFAAAAAA==.Veryspooky:BAABLgAECn8XAAISAAgJLxfSFAD+AQASAAgJLxfSFAD+AQAAAA==.Vexian:BAAALgADCgcJFgAAAA==.',
Vi='Vicas:BAAALgADCggJFgAAAA==.',
Vo='Voidofdeath:BAAALgADCgQJBAAAAA==.Voidshiekah:BAAALgADCgEJAQAAAA==.Vorteia:BAAALgADCgYJBgAAAA==.',
['Vé']='Véngéánçé:BAAALgAECgMJBAAAAA==.',
Wa='Wald:BAAALgAECgYJDAAAAA==.Waruh:BAAALgADCgcJCQAAAA==.',
We='Webgar:BAAALgADCgEJAQAAAA==.',
Wh='Whitetoothe:BAAALgAECgQJCgAAAA==.',
['Wå']='Wånheda:BAAALgAECggJDwAAAA==.',
Xa='Xaniana:BAAALgAECgYJBgAAAA==.Xaosin:BAAALgADCgUJBQAAAA==.',
Xe='Xenzak:BAAALgAECgEJAQAAAA==.Xephir:BAAALgADCgMJAwAAAA==.Xerxës:BAAALgAECgEJAQAAAA==.',
Xo='Xotiko:BAAALgADCgcJBwAAAA==.',
Xu='Xubris:BAAALgADCgYJCQAAAA==.',
Ya='Yaerin:BAABLgAECn8cAAITAAgJIyKfAQAcAwATAAgJIyKfAQAcAwAAAA==.',
Yu='Yunarä:BAAALgAECgEJAQAAAA==.Yuukon:BAAALgAECgUJDQAAAA==.',
Za='Zakuul:BAAALgADCgQJBAAAAA==.Zangetsu:BAAALgAECgcJBwAAAA==.Zaxie:BAABLgAECn8XAAIKAAYJMRq+LAAxAQAKAAYJMRq+LAAxAQAAAA==.',
Ze='Zenwu:BAAALgADCgkJGwAAAA==.Zephrylia:BAAALgADCggJHAAAAA==.Zerama:BAAALgAECgQJBAAAAA==.',
Zh='Zheratul:BAAALgAECgEJAQAAAA==.',
Zi='Zilphia:BAAALgAECgYJBwAAAA==.',
Zu='Zuriel:BAAALgAECgEJAQAAAA==.',
Zy='Zyku:BAAALgADCgIJAgAAAA==.',
['Àm']='Àmagezing:BAAALgAECgMJBAABLgAECgUJCAAFAAAAAA==.',
['Åj']='Åj:BAAALgADCgcJBwAAAA==.',
['Åp']='Åpexx:BAAALgADCgMJBAAAAA==.',
['Ór']='Órión:BAAALgAECgYJEwAAAA==.',
['Ös']='Östara:BAAALgAECgQJDAAAAA==.',
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
