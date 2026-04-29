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

local lookup = {'Mage-Frost','Priest-Holy','Unknown-Unknown','DemonHunter-Devourer','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Vengeance','Druid-Balance','Paladin-Holy','Paladin-Retribution','DeathKnight-Unholy','Warlock-Demonology','Hunter-BeastMastery','Priest-Shadow','Warlock-Affliction','DemonHunter-Havoc','Warrior-Protection','Warrior-Arms','Warrior-Fury','Druid-Restoration','Druid-Feral','Warlock-Destruction','Monk-Windwalker','Monk-Brewmaster','Shaman-Restoration','Rogue-Subtlety','Shaman-Elemental','DeathKnight-Frost','DeathKnight-Blood','Mage-Arcane','Priest-Discipline','Monk-Mistweaver','Mage-Fire','Druid-Guardian','Shaman-Enhancement','Hunter-Survival','Hunter-Marksmanship','Paladin-Protection',}
local provider = {region='US',realm='Nordrassil',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aairidari:BAAALgAECgYJDgAAAA==.',
Ab='Abruna:BAAALgAECgUJCgABLgAFFAQJCwABAPcVAA==.Abruno:BAACLgAFFH8LAAIBAAQJ9xUOGQBmAQABAAQJ9xUOGQBmAQAuAAQKfyMAAgEACQmRIUUPAE0DAAEACQmRIUUPAE0DAAAA.Abruto:BAAALgADCgYJBgABLgAFFAQJCwABAPcVAA==.',
Ad='Adrians:BAABLgAECn8bAAIBAAcJYRQwFwCLAQABAAcJYRQwFwCLAQAAAA==.',
Ae='Aeown:BAAALgAECgYJDgABLgAECggJIQACAJMUAA==.Aerdis:BAAALgAECgEJAQABLgAECgQJBQADAAAAAA==.',
Ah='Ahsóká:BAAALgAECgQJBQAAAA==.',
Ak='Akames:BAAALgAECgQJBQABLgAECggJQAAEAE4iAA==.',
Al='Alahrî:BAABLgAECn8dAAQFAAgJLBHiFgDiAQAFAAgJLBHiFgDiAQAGAAIJVQfFBgB6AAAHAAEJAABHJQAAAAAAAA==.Alandrìas:BAABLgAECn8UAAIIAAcJig3tAwAoAQAIAAcJig3tAwAoAQAAAA==.Alphael:BAAALgADCgYJBgAAAA==.Alror:BAABLgAECn8nAAIJAAkJsB3XBQA9AwAJAAkJsB3XBQA9AwAAAA==.Altera:BAABLgAECn8XAAIFAAYJxhY1BACIAQAFAAYJxhY1BACIAQAAAA==.',
Am='Amelya:BAAALgAECgcJCQAAAA==.Amuri:BAAALgAECgUJBwAAAA==.',
An='Andere:BAAALgAECgYJBgAAAA==.Androonatorz:BAACLgAFFH8MAAIKAAQJnh3RBwBUAQAKAAQJnh3RBwBUAQAuAAQKfyEAAwoACQnTHloHAPcCAAoACQnTHloHAPcCAAsABAn+ES2+AAoBAAAA.Angelø:BAAALgADCgUJBwAAAA==.Antagony:BAAALgADCgcJBwAAAA==.Antheavari:BAAALgADCgYJBgAAAA==.',
Ar='Ardemus:BAAALgAECgkJEwAAAA==.Arkena:BAAALgAECgIJAgAAAA==.Arkenai:BAAALgADCgcJDQAAAA==.Arveiturace:BAAALgAECgEJAQAAAA==.',
As='Ashborrn:BAAALgAECgUJBgAAAA==.Ashtar:BAAALgAECgYJDwAAAA==.Ashtomouth:BAAALgAECgYJDQAAAA==.Astorath:BAAALgADCgEJAgAAAA==.Asukajo:BAAALgADCgkJCQAAAA==.',
Aw='Awaken:BAAALgAECgYJCAAAAA==.',
Az='Azorei:BAAALgADCgIJAgAAAA==.',
Ba='Baconegg:BAACLgAFFH8LAAIMAAQJIRYFBgBcAQAMAAQJIRYFBgBcAQAuAAQKfyEAAgwACAlFIVoVAPsCAAwACAlFIVoVAPsCAAAA.Balddrex:BAAALgADCgkJCQAAAA==.Balefire:BAABLgAECn8XAAINAAgJzhajCgDKAQANAAgJzhajCgDKAQAAAA==.Bamboom:BAAALgADCgQJBAAAAA==.Barma:BAAALgADCgcJBwAAAA==.Barraki:BAAALgADCgIJAgABLgAECggJFAAOAMIMAA==.Basili:BAAALgADCgUJBwAAAA==.',
Bd='Bd:BAAALgAECgEJAQAAAA==.',
Be='Beeper:BAAALgAECgYJBgAAAA==.Beldanner:BAAALgADCgkJDAAAAA==.Beltirra:BAAALgAECgMJAwAAAA==.Benan:BAAALgADCgUJBQAAAA==.Bengalnug:BAAALgADCgQJBAAAAA==.',
Bi='Bigwill:BAABLgAECn8WAAIBAAcJmRtpRwBhAgABAAcJmRtpRwBhAgAAAA==.',
Bl='Blackfeet:BAAALgAECgYJBwAAAA==.Blango:BAAALgAECgMJAwAAAA==.Blargy:BAABLgAECn8gAAIJAAgJlBjSBADMAQAJAAgJlBjSBADMAQAAAA==.Blex:BAAALgADCggJCAAAAA==.Bloodshed:BAAALgADCgcJDQAAAA==.Bluewaffles:BAAALgADCgUJCQAAAA==.',
Bo='Boudicah:BAAALgADCgEJAQAAAA==.',
Br='Braicel:BAACLgAFFH8PAAIPAAUJeB8qAQB2AQAPAAUJeB8qAQB2AQAuAAQKfyQAAg8ACAnNJIMEAE0DAA8ACAnNJIMEAE0DAAAA.Breedableram:BAAALgADCgYJBgABLgAECggJGgAQADsaAA==.Brythorn:BAAALgADCgEJAQAAAA==.',
Bu='Bucketojoy:BAAALgAECgIJAgABLgAECggJGQARAFoOAA==.',
['Bì']='Bìgred:BAAALgADCgEJAQAAAA==.',
Ca='Cacadookie:BAAALgAECgEJAQAAAA==.Calegorm:BAAALgADCgYJCwAAAA==.Caliburne:BAABLgAECn8VAAQSAAgJ0xojAgAJAgASAAcJQR0jAgAJAgATAAYJjxqODgCzAQAUAAYJGw+XUQBiAQAAAA==.Caliypso:BAAALgAECgYJCQAAAA==.Cambro:BAAALgAECgYJEAAAAA==.Candierain:BAAALgADCgEJAQAAAA==.Canoe:BAABLgAECn8iAAQJAAgJHxcxCwA6AQAJAAcJtxQxCwA6AQAVAAQJohpqfwDcAAAWAAIJ+gACOwAYAAAAAA==.Capz:BAACLgAFFH8XAAMTAAcJWh8pAABIAgATAAcJsh4pAABIAgAUAAQJ8yBIBwB3AQAuAAQKfyEAAxMACQnPIzwDANsCABMACAkWJTwDANsCABQACQlnFqAPANYCAAAA.Carcaradon:BAAALgAECgEJAgAAAA==.Carta:BAAALgAECgMJAwAAAA==.Caulfield:BAAALgAECgEJAQAAAA==.',
Ce='Ceez:BAAALgAECgQJCAAAAA==.Celebrïmbor:BAAALgAECgMJAQAAAA==.',
Ch='Chair:BAAALgAECggJDQABLgAECgcJGwABAEMYAA==.Chiyori:BAAALgADCgIJAQAAAA==.Chongy:BAAALgAECgIJAwAAAA==.Chopperr:BAAALgADCgMJBQAAAA==.Chèn:BAAALgAECgYJCwAAAA==.',
Ci='Cindrella:BAABLgAECn8bAAIBAAcJQxjYcADyAQABAAcJQxjYcADyAQAAAA==.Circa:BAAALgADCgIJAgAAAA==.',
Cl='Clani:BAAALgADCgIJAgAAAA==.Clayre:BAABLgAECn8uAAIXAAgJ9yMUAADmAgAXAAgJ9yMUAADmAgAAAA==.Clow:BAAALgAECgcJEwAAAA==.',
Co='Comparabull:BAAALgADCgcJEQAAAA==.Coolcrush:BAABLgAECn8WAAMYAAYJJR/9AwDKAQAYAAYJfh79AwDKAQAZAAIJBhhQawCVAAAAAA==.Corgnelius:BAAALgADCgQJBgAAAA==.Corven:BAACLgAFFH8KAAINAAQJ4RVNCgAkAQANAAQJ4RVNCgAkAQAuAAQKfy4AAw0ACQlFHQUGABQCAA0ACQlFHQUGABQCABAAAQkAALg0ADIAAAAA.Corvenicus:BAAALgAECgMJAwAAAA==.',
Cr='Crashbash:BAAALgADCgMJAwAAAA==.Crosis:BAAALgAECgYJDgAAAA==.Cryovox:BAAALgADCgIJAgAAAA==.',
Cu='Cumazzing:BAACLgAFFH8JAAILAAUJMyAcBgCOAQALAAUJMyAcBgCOAQAuAAQKfx0AAgsACQkwJbMCAK4DAAsACQkwJbMCAK4DAAAA.',
Da='Daedyxes:BAAALgAECgYJCgAAAA==.Daerodos:BAAALgAECgUJCgAAAA==.Daiskei:BAAALgAECgcJCgAAAA==.Dangerr:BAAALgADCgcJBwAAAA==.Darfretail:BAAALgAECgcJDwAAAA==.Darkdemon:BAAALgADCgcJDAAAAA==.Darkmagi:BAAALgAECgMJBAAAAA==.Dasherdeez:BAAALgADCggJBgAAAA==.Daygath:BAAALgAECgcJEgAAAA==.',
De='Deadlyiris:BAABLgAECn8aAAMTAAgJvhveAABIAgATAAgJvhveAABIAgAUAAYJHxCPSgB7AQABLgAECgYJFAAaAF8jAA==.Deatharin:BAAALgAECgIJAwAAAA==.Demonbulio:BAAALgAECgYJEAAAAA==.Demonisthicc:BAAALgAECgIJAwABLgAECggJGgAQADsaAA==.Demonskitten:BAABLgAECn8aAAIQAAgJOxqTAAD+AQAQAAgJOxqTAAD+AQAAAA==.Demonslayeer:BAAALgADCgEJAQAAAA==.Devlyne:BAAALgADCgMJAwAAAA==.',
Di='Ding:BAAALgAECgYJEAAAAA==.Direwolf:BAAALgAECgQJBQAAAA==.Dirtyearl:BAABLgAECn8fAAILAAcJuBQEVwDdAQALAAcJuBQEVwDdAQAAAA==.Dithehealer:BAAALgAECgcJEAAAAA==.Divain:BAAALgADCgEJAQAAAA==.',
Do='Doalina:BAAALgADCgMJAwAAAA==.Domidia:BAABLgAECn8aAAIBAAYJOh7jFgCNAQABAAYJOh7jFgCNAQAAAA==.Donkeyshot:BAAALgAECgQJCgABLgAECgYJDAADAAAAAA==.Doogie:BAAALgADCgEJAQAAAA==.',
Dr='Draconfel:BAAALgAECgMJAwAAAA==.Draglone:BAAALgADCgMJAwABLgAECgYJBgADAAAAAA==.Drbadtouch:BAAALgAECgEJAQAAAA==.Dreamfyres:BAACLgAFFH8MAAMGAAUJ2B/kAQB9AQAGAAUJ2B/kAQB9AQAHAAIJxxsxCwC4AAAuAAQKfyIAAwYACAmKJQgBAF0DAAYACAmKJQgBAF0DAAcABQlEI34cAOMBAAAA.Drenamai:BAAALgAECgUJCwAAAA==.Drewetta:BAAALgAECgYJCwAAAA==.Drmombo:BAAALgAECgQJAwAAAA==.',
Du='Duhmptruhk:BAAALgAECgYJCwABLgAECgcJBwADAAAAAA==.Durbana:BAAALgADCgUJBQAAAA==.Duskariel:BAAALgADCgMJBAAAAA==.',
Dy='Dyson:BAAALgAECgcJEgAAAA==.',
Eh='Ehmehzing:BAACLgAFFH8FAAILAAMJqiKGDgA2AQALAAMJqiKGDgA2AQAuAAQKfyQAAgsACQk9JawBAMgDAAsACQk9JawBAMgDAAEuAAUUBQkJAAsAMyAA.',
El='Elghtyelght:BAAALgAECgUJBwAAAA==.Eliicia:BAABLgAFFH8KAAIbAAQJVwQoBAAtAQAbAAQJVwQoBAAtAQAAAA==.Elvwyr:BAAALgADCgEJAQAAAA==.',
Em='Embarrassed:BAAALgADCggJFwAAAA==.Emmetcullen:BAACLgAFFH8JAAIcAAQJhhUtAwBCAQAcAAQJhhUtAwBCAQAuAAQKfyAAAxwACAkgHtUTAIACABwACAkgHtUTAIACABoABAk3Cap1ALoAAAAA.Emmy:BAAALgAECgYJDAAAAA==.Emryss:BAAALgADCgMJAwAAAA==.',
En='Endo:BAAALgAECgQJBAABLgAFFAQJDAARAFsfAA==.Endorush:BAACLgAFFH8MAAQRAAQJWx/rAQB7AQARAAQJqB3rAQB7AQAEAAMJxg2jDgDmAAAIAAEJECe2AwB2AAAuAAQKfy4AAxEACQneJVYAAPEDABEACQneJVYAAPEDAAQACAlxFhIHAAQCAAAA.Enjoyer:BAAALgAECgYJEAAAAA==.',
Er='Ereitherla:BAAALgAECgYJEwAAAA==.',
Es='Eshaia:BAAALgADCgQJBAAAAA==.Espressð:BAAALgADCgUJCgAAAA==.',
Ex='Excalibear:BAABLgAECn8iAAIKAAgJvRHACwCDAQAKAAgJvRHACwCDAQABLgAFFAQJCgABAEQaAA==.',
Ey='Eydis:BAAALgADCgUJBQAAAA==.Eyepisspeas:BAAALgADCgEJAQAAAA==.',
Ez='Ezra:BAAALgADCgkJDwAAAA==.',
Fa='Fatherjeff:BAAALgADCgkJDQAAAA==.',
Fe='Feldown:BAAALgAECgYJBwAAAA==.Feyrre:BAAALgAECgMJAwAAAA==.',
Fi='Fistbroz:BAAALgAECgQJBAABLgAFFAQJDQAZACgPAA==.',
Fl='Flawpeacok:BAABLgAECn8XAAIMAAgJUxZWCAD5AQAMAAgJUxZWCAD5AQAAAA==.Fleredil:BAABLgAECn8jAAMCAAcJlRUzIQDZAQACAAcJlRUzIQDZAQAPAAMJaw/dEwC/AAAAAA==.Floistas:BAAALgAECgQJBAAAAA==.',
Fo='Forepray:BAAALgAECgQJBgABLgAFFAQJDQAUAOQXAA==.Forger:BAABLgAECn8UAAISAAYJEQ1GCQDyAAASAAYJEQ1GCQDyAAAAAA==.Foxfireii:BAAALgADCgMJAwAAAA==.',
Fr='Freshdk:BAACLgAFFH8JAAMdAAMJcB6FAQC4AAAdAAMJ9BKFAQC4AAAMAAIJFSJgOgCnAAAuAAQKfyoABAwACQnzI+YBAKsCAAwACQnzI+YBAKsCAB0AAwmbIVwKACgBAB4AAQljDnBBAEYAAAAA.Frostgash:BAAALgADCgcJDAAAAA==.Frostycheeks:BAABLgAECn8iAAIMAAgJoR1LBQA1AgAMAAgJoR1LBQA1AgAAAA==.Frostywaffle:BAAALgADCgQJBAAAAA==.',
Fu='Fubuki:BAAALgADCgEJAQAAAA==.Fudgetracks:BAAALgADCgYJBgAAAA==.Futaccine:BAABLgAECn8eAAMEAAcJtSTMGADAAgAEAAcJLyTMGADAAgAIAAEJSSH0CABlAAAAAA==.Future:BAAALgAECgYJDQABLgAECggJJwAfAJElAA==.',
Ga='Gaerlan:BAAALgADCgYJBgAAAA==.Galvquodiyu:BAAALgAECgcJCQAAAA==.Garlic:BAAALgADCgEJAQAAAA==.',
Ge='Geekbarr:BAAALgADCgEJAQAAAA==.',
Gh='Ghostblades:BAACLgAFFH8MAAMMAAUJaRWcBgBXAQAMAAQJaRWcBgBXAQAdAAEJAADhBAAAAAAuAAQKfyEAAwwACAm4IjsbANoCAAwACAm4IjsbANoCAB0AAQnbHDAWADgAAAAA.',
Gi='Gilffy:BAAALgADCgkJCgAAAA==.',
Gl='Gloomybear:BAAALgADCgUJBQAAAA==.',
Gr='Grimzero:BAAALgADCgMJAwAAAA==.Grinny:BAABLgAECn8mAAMLAAgJ9hxhBgArAgALAAgJ9hxhBgArAgAKAAIJowMYjQBKAAAAAA==.',
Ha='Hadariel:BAAALgAECgcJCQAAAA==.Haldane:BAABLgAECn8ZAAILAAgJcApzFgBsAQALAAgJcApzFgBsAQABLgAECgYJFAAaAF8jAA==.Havochunter:BAAALgAECgMJBQAAAA==.',
He='Heidegger:BAAALgADCggJEQAAAA==.Helenkeller:BAAALgAECgIJAgAAAA==.Henderson:BAAALgADCgQJBAAAAA==.Heraois:BAAALgAECgYJDAAAAA==.Hexy:BAAALgAECgUJCAAAAA==.',
Hi='Highblood:BAAALgAECgUJBgAAAA==.',
Ho='Holytës:BAAALgADCgcJBwAAAA==.Hotea:BAAALgAECgIJBAAAAA==.',
Hp='Hpsnotdps:BAAALgAECgcJEwAAAA==.',
Hu='Hucklebeary:BAAALgADCgYJBgAAAA==.Huell:BAAALgAECgMJAwAAAA==.Hunterdh:BAAALgAECgYJDgAAAA==.',
Hy='Hynesh:BAAALgAECgQJBQAAAA==.Hynixx:BAACLgAFFH8NAAIUAAQJ5Bd3AgBbAQAUAAQJ5Bd3AgBbAQAuAAQKfyQAAhQACAnkH74OAN4CABQACAnkH74OAN4CAAAA.',
Ic='Icecandie:BAAALgAECgYJCAAAAA==.',
Il='Illidope:BAAALgAECgcJCgABLgAFFAUJDAAGANgfAA==.',
Im='Imistmypants:BAAALgAECgQJBgAAAA==.',
In='Infinitevoid:BAAALgADCgQJBAAAAA==.Innervatez:BAABLgAFFH8JAAIVAAUJKhiXAQCzAQAVAAUJKhiXAQCzAQAAAA==.Inspectda:BAABLgAECn8VAAINAAgJgwcJdgBxAQANAAgJgwcJdgBxAQAAAA==.',
Io='Ionúin:BAAALgADCgcJCgAAAA==.',
Is='Issel:BAAALgAECgYJCwAAAA==.',
Iy='Iyaasu:BAAALgAECggJEwAAAA==.Iyahliea:BAAALgAECgIJAgAAAA==.',
Ja='Jaeger:BAAALgAECggJEAAAAA==.Jaekir:BAABLgAECn8VAAIBAAYJvxFfIgBJAQABAAYJvxFfIgBJAQAAAA==.Jakey:BAAALgAECgUJCQAAAA==.Jakfrost:BAABLgAECn8fAAIBAAgJ1SPFAQDUAgABAAgJ1SPFAQDUAgAAAA==.Jarten:BAAALgAECgYJEAAAAA==.Jaylebate:BAABLgAECn8eAAIMAAgJBRYWCgDeAQAMAAgJBRYWCgDeAQAAAA==.',
Je='Jerrenn:BAAALgAECgYJDQAAAA==.Jesseatamer:BAAALgAECgYJEQAAAA==.',
Ji='Jiraiyan:BAAALgAECgIJAgAAAA==.',
Jo='Jolt:BAAALgADCgEJAQAAAA==.Jouska:BAAALgAECgEJAQABLgAECgcJBwADAAAAAA==.',
Ka='Kaera:BAAALgAECgUJCQAAAA==.Kakushin:BAAALgAECgEJAQAAAA==.Kaldór:BAAALgADCgIJAgAAAA==.Kalmek:BAAALgAECgYJDAAAAA==.Karne:BAAALgADCgEJAQAAAA==.Kartian:BAAALgAECgEJAQABLgAECgEJAQADAAAAAA==.Kastia:BAAALgAECgEJAQAAAA==.Katrynwel:BAAALgAECgQJBAAAAA==.Katsumi:BAAALgADCgkJFwAAAA==.',
Kh='Khainen:BAAALgADCgEJAQAAAA==.',
Ki='Killalltoday:BAABLgAECn8WAAIaAAYJtBLDEwAWAQAaAAYJtBLDEwAWAQAAAA==.Kilon:BAAALgAECgEJAQAAAA==.Kirkk:BAAALgADCgcJEgAAAA==.Kixarea:BAAALgADCgkJCgABLgAECggJEwADAAAAAA==.',
Kn='Kneesweak:BAAALgAECgQJBgAAAA==.Knexx:BAAALgAECgYJCgAAAA==.Knixx:BAACLgAFFH8KAAMPAAQJRgWRBgDFAAAPAAQJRgWRBgDFAAAgAAMJyAQNFgCCAAAuAAQKfykABAIACAmmGl8bAAECAAIABwk6GF8bAAECAA8ACAmbFL8HAH0BACAABQniEcItADABAAAA.Knotty:BAAALgADCgYJDQAAAA==.',
Ko='Kotalyst:BAABLgAECn8UAAIZAAgJpRLECABoAQAZAAgJpRLECABoAQAAAA==.Kotastrophe:BAAALgAECgcJBwAAAA==.Koveras:BAAALgADCgkJCwAAAA==.Koyaanis:BAABLgAECn8dAAIhAAgJZBh7AgBNAgAhAAgJZBh7AgBNAgAAAA==.Koyya:BAAALgAECgUJCgAAAA==.',
Ku='Kufoo:BAABLgAECn8WAAIUAAYJ4h9yBgC9AQAUAAYJ4h9yBgC9AQAAAA==.Kuma:BAAALgADCgcJBwABLgAECggJJwAfAJElAA==.Kuraikage:BAAALgADCgEJAQAAAA==.Kurao:BAAALgAECgMJAwAAAA==.Kurukai:BAAALgADCgUJBgAAAA==.',
Ky='Kynlerrine:BAAALgAECgYJDwAAAA==.Kyokushin:BAAALgAECgMJAwAAAA==.',
La='Layez:BAAALgADCgUJBQABLgAECgYJFgANALsaAA==.',
Le='Leguan:BAAALgADCgkJDQAAAA==.Lethe:BAAALgADCgUJBQABLgAFFAQJCgAbAFcEAA==.',
Li='Likestoflash:BAEALgAECgYJCgABLgAECggJIgAOAAscAA==.Lilgeeked:BAAALgADCgYJCwAAAA==.Liliannrose:BAAALgAECgEJAQAAAA==.',
Lo='Locklove:BAAALgADCgkJCQAAAA==.Lohal:BAABLgAECn8fAAINAAgJohe5EQCDAQANAAgJohe5EQCDAQAAAA==.Lolalashay:BAAALgAECgMJBwAAAA==.Lorilock:BAAALgADCgUJBQAAAA==.Loudawn:BAABLgAECn8XAAIJAAgJegTCQQApAQAJAAgJegTCQQApAQAAAA==.',
Lu='Luania:BAAALgAECgEJAQAAAA==.Lupo:BAAALgAECgEJAQAAAA==.Lusucio:BAAALgAFFAEJAQAAAA==.',
Ly='Lyberrath:BAAALgADCgQJBQAAAA==.Lyeth:BAAALgAECgMJAwAAAA==.Lyna:BAAALgADCgcJBwAAAA==.',
['Lé']='Lélouch:BAAALgAECgYJBgABLgAFFAQJCQAcAIYVAA==.',
Ma='Magerthat:BAAALgADCgYJBwAAAA==.Magicaltickl:BAABLgAECn8eAAMBAAgJdxEiEADBAQABAAgJdxEiEADBAQAiAAMJ/ggcCwCIAAAAAA==.Magiki:BAAALgADCgkJDwAAAA==.Mamadeezy:BAAALgADCgYJCQAAAA==.Manical:BAAALgADCgQJBAAAAA==.Mashiach:BAAALgADCgcJBwABLgAECggJFQAWAHAYAA==.Maxgoon:BAABLgAECn8WAAINAAcJwgzGcwB2AQANAAcJwgzGcwB2AQAAAA==.',
Me='Megumin:BAAALgAECgUJCgABLgAECggJHgALAOofAA==.Mellisandria:BAAALgAECgQJBAAAAA==.Melodious:BAAALgADCgYJCQAAAA==.Merek:BAABLgAECn8WAAIZAAYJWB8mBgClAQAZAAYJWB8mBgClAQAAAA==.Merriska:BAABLgAECn8WAAMLAAkJ4yCiJQCQAgALAAcJ8yGiJQCQAgAKAAcJZSGdEwB1AgAAAA==.',
Mi='Miashadow:BAAALgADCgcJDQAAAA==.Mikeysmom:BAAALgAECgcJCwAAAA==.Misseslovett:BAAALgADCgQJBAAAAA==.Missmeow:BAAALgADCgYJBgAAAA==.Mistyd:BAACLgAFFH8LAAIjAAQJ1AlhAQD9AAAjAAQJ1AlhAQD9AAAuAAQKfywAAiMACQkGGUwFAIoCACMACQkGGUwFAIoCAAAA.Mithras:BAAALgADCgIJAgAAAA==.',
Mo='Monkar:BAAALgADCgMJAwAAAA==.Monkdiluffy:BAAALgADCgUJBQAAAA==.Moocifer:BAAALgAECgIJAgAAAA==.Moonstriker:BAABLgAECn8fAAIKAAgJAyazAQBoAwAKAAgJAyazAQBoAwAAAA==.Morgause:BAAALgAECgUJCgABLgAECgYJEAADAAAAAA==.Morijinn:BAAALgAECgQJBQAAAA==.Morllan:BAAALgAECgEJAgAAAA==.Mortyxp:BAAALgADCgIJAgAAAA==.Mowenudown:BAAALgAECgEJAQAAAA==.',
Mu='Muirdin:BAAALgAECgYJEgAAAA==.',
Mv='Mvp:BAAALgADCgYJBgAAAA==.',
['Má']='Máelyss:BAAALgAECgQJBgAAAA==.',
['Må']='Mångix:BAAALgAECgIJAgAAAA==.',
['Mé']='Mélusine:BAABLgAECn8dAAMTAAgJdR47AQAYAgATAAgJXh07AQAYAgAUAAUJNRthTAB0AQAAAA==.',
['Mï']='Mïsterlovett:BAAALgADCgkJDQABLgAECggJIAANAK4eAA==.',
Na='Naanomage:BAAALgAECgIJAwAAAA==.Nagato:BAAALgADCgcJBwAAAA==.',
Ne='Necrotoxin:BAABLgAECn8gAAMNAAgJrh6uBAAzAgANAAcJrh6uBAAzAgAXAAEJAADlXABYAAAAAA==.',
Ni='Nightsever:BAABLgAECn8YAAMEAAkJ4hvaIQCGAgAEAAkJbRnaIQCGAgARAAUJBCGqJgCLAQAAAA==.Nirath:BAABLgAECn8VAAIGAAYJBAdTBADzAAAGAAYJBAdTBADzAAAAAA==.',
No='Noiire:BAAALgADCgcJDAABLgAFFAQJCgAbAFcEAA==.Nopal:BAAALgADCgcJDAAAAA==.Nopriest:BAACLgAFFH8FAAIPAAIJPyMWDQDRAAAPAAIJPyMWDQDRAAAuAAQKfykAAg8ACAkPJZYAANkCAA8ACAkPJZYAANkCAAAA.Notixx:BAAALgADCgQJBAAAAA==.Notprepared:BAABLgAECn8ZAAIRAAgJWg4oBACdAQARAAgJWg4oBACdAQAAAA==.Nottisdemon:BAAALgAECgcJDQAAAA==.',
Nu='Nullfox:BAAALgADCgUJBQABLgAFFAUJDAAbAEwVAA==.',
Oa='Oakly:BAABLgAECn8YAAIVAAcJ/xThPACwAQAVAAcJ/xThPACwAQAAAA==.',
On='Onaroll:BAAALgAFFAIJAgABLgAFFAQJCwAVAG4SAA==.',
Oo='Ooyagoddess:BAAALgAECgEJAwAAAA==.',
Oy='Oya:BAAALgADCgIJAgAAAA==.',
Pa='Pacamonk:BAAALgAECgUJEQAAAA==.Pacifer:BAAALgAECgEJAQAAAA==.Pann:BAAALgADCgYJBgABLgAECgIJAwADAAAAAA==.Pauon:BAAALgADCgcJBwAAAA==.Pawpatine:BAAALgAECgYJEwAAAA==.Pawsa:BAABLgAECn8UAAMYAAUJxhJtDQD5AAAYAAUJKhJtDQD5AAAZAAMJWQ+lagCYAAAAAA==.Pawthetic:BAACLgAFFH8LAAIVAAQJbhLSCQA6AQAVAAQJbhLSCQA6AQAuAAQKfyIAAhUACQmiID0DAGEDABUACQmiID0DAGEDAAAA.',
Pe='Peelforheals:BAABLgAECn8bAAMgAAcJuxUXHAC1AQAgAAcJuxUXHAC1AQAPAAUJ3geMQADzAAAAAA==.Penguindemic:BAABLgAECn8XAAINAAcJFSYOHACtAgANAAcJFSYOHACtAgAAAA==.Pep:BAABLgAECn8bAAMYAAgJsRoBAgAyAgAYAAgJsRoBAgAyAgAhAAEJUwMZcgAiAAAAAA==.Pepperoni:BAAALgADCgQJBAAAAA==.Petruccius:BAAALgAECgUJBQAAAA==.Pewpewlepew:BAAALgAECgYJCAAAAA==.',
Ph='Phaedesana:BAAALgADCgkJCQABLgAECgUJBgADAAAAAA==.Phaeku:BAAALgADCgcJCgABLgAECgUJBgADAAAAAA==.Phòenix:BAAALgADCgkJCQAAAA==.',
Pi='Pinksparklez:BAAALgAECgEJAQAAAA==.',
Pl='Plaguedr:BAAALgAECgEJAQAAAA==.',
Po='Porbles:BAAALgADCgcJBwAAAA==.Porklamb:BAAALgAECgEJAQAAAA==.',
Pr='Prey:BAAALgADCgEJAQAAAA==.Prospa:BAAALgADCgUJBQAAAA==.Prumper:BAABLgAECn8nAAIBAAgJwB5SBwA1AgABAAgJwB5SBwA1AgAAAA==.',
Py='Pyric:BAAALgAECgEJAgAAAA==.',
Qu='Quesoblanco:BAAALgADCgcJCgAAAA==.',
Qy='Qybxboogiedk:BAAALgAECgMJAwAAAA==.',
Ra='Raghallov:BAAALgADCggJCQAAAA==.Ramzey:BAABLgAECn8hAAIMAAgJNB2eOQBQAgAMAAgJNB2eOQBQAgAAAA==.Rawnis:BAAALgAECgEJAQAAAA==.Raylëigh:BAAALgADCgYJBgAAAA==.',
Re='Redbearon:BAAALgAECgEJAQAAAA==.Redroger:BAAALgADCgQJBQAAAA==.Regena:BAABLgAECn8hAAMCAAgJkxScBQDHAQACAAgJkxScBQDHAQAgAAUJcgUwOgDWAAAAAA==.Remorse:BAACLgAFFH8IAAISAAQJDA7sAgAKAQASAAQJDA7sAgAKAQAuAAQKfyUAAhIACQmwFrwCAN8BABIACQmwFrwCAN8BAAAA.Required:BAAALgAECgUJBwABLgAFFAYJFAAEAMYVAA==.Retro:BAAALgAECgUJCgAAAA==.',
Rh='Rhysara:BAAALgAECgEJAQAAAA==.',
Ri='Rikatree:BAAALgAECggJEwAAAA==.Rim:BAABLgAECn8fAAIaAAgJWB1gAQCzAgAaAAgJWB1gAQCzAgAAAA==.Rinaren:BAAALgADCgcJCAAAAA==.Risque:BAABLgAECn8dAAIBAAgJGB1qNAChAgABAAgJGB1qNAChAgAAAA==.',
Ro='Ronard:BAAALgAFFAIJBQAAAQ==.Ronfar:BAACLgAFFH8FAAIkAAMJfhMSAwAJAQAkAAMJfhMSAwAJAQAuAAQKfykAAiQACAkdIl8AAK8CACQACAkdIl8AAK8CAAAA.',
Ru='Rukidingme:BAAALgADCgcJDgAAAA==.Runehammer:BAAALgADCgMJAwAAAA==.Ruttisðir:BAAALgAECgYJBgAAAA==.',
Rw='Rw:BAAALgAECgEJAQAAAA==.',
Ry='Ryhorn:BAABLgAECn8ZAAILAAYJxQg0JwAIAQALAAYJxQg0JwAIAQAAAA==.Ryno:BAAALgADCgUJBQAAAA==.Ryomensukuna:BAAALgAECgMJAwAAAA==.Ryujin:BAAALgAECggJEAAAAA==.',
Sa='Salo:BAAALgAECgMJAwAAAA==.Sanazenet:BAAALgAECgQJBAAAAA==.Saronas:BAAALgADCggJCQABLgAECgYJEAADAAAAAA==.',
Sc='Scootypuffsr:BAAALgAECgUJCQAAAA==.Scootyshooty:BAAALgADCgYJBgAAAA==.Scrap:BAABLgAECn8WAAIYAAcJFxM6LAB+AQAYAAcJFxM6LAB+AQAAAA==.Scubasuiit:BAABLgAECn8dAAQVAAgJdhyxJQAiAgAVAAcJ1ByxJQAiAgAJAAYJ+R5+HwADAgAjAAEJGQaQNQAfAAAAAA==.',
Se='Segarth:BAAALgAECgEJAgAAAA==.Selen:BAABLgAECn8eAAIKAAgJ+h5zAQCwAgAKAAgJ+h5zAQCwAgAAAA==.Seleste:BAAALgADCgYJCAAAAA==.Seråphiel:BAAALgAECgQJCAAAAA==.Seswatha:BAACLgAFFH8KAAIBAAQJRBpoGwBdAQABAAQJRBpoGwBdAQAuAAQKfyAAAgEACAlQJMgCAKgCAAEACAlQJMgCAKgCAAAA.',
Sh='Shadowbaron:BAAALgADCgkJGQAAAA==.Shadowsnek:BAAALgAECgEJAQAAAA==.Shaltear:BAAALgAECgUJBQAAAA==.Shamandroo:BAAALgAECgYJCwABLgAFFAQJDAAKAJ4dAA==.Shenzu:BAAALgAECgYJDgAAAA==.Shmongus:BAAALgADCgYJBgABLgAECgYJEAADAAAAAA==.Shocktop:BAAALgAECgUJCAAAAA==.Shortfuse:BAAALgAECgEJAQABLgAECgUJDAADAAAAAA==.Shz:BAAALgAECgEJAQABLgAECgQJCAADAAAAAA==.Shådowfire:BAAALgADCgkJDQAAAA==.Shìft:BAABLgAECn8VAAIVAAcJ1RIoEABXAQAVAAcJ1RIoEABXAQAAAA==.',
Si='Siercy:BAAALgADCgMJBQAAAA==.Simplysauced:BAAALgAECgQJCwABLgAECgkJJwAJALAdAA==.',
Sk='Skylér:BAAALgADCgkJCQAAAA==.',
Sl='Slighted:BAAALgAECgMJBgABLgAECgQJBQADAAAAAA==.Slimydruid:BAAALgAECgYJEgAAAA==.Slizz:BAAALgADCgYJCwAAAA==.Slizzard:BAAALgADCgYJDAAAAA==.Slow:BAABLgAECn8nAAQfAAgJkSWiAgBmAgABAAgJjyB4LQC8AgAfAAYJsCKiAgBmAgAiAAQJXh/xAAB+AQAAAA==.',
Sm='Smaltownlock:BAAALgADCgMJAwAAAA==.Smo:BAAALgADCgYJBgAAAA==.Smokze:BAAALgAECgYJBgAAAA==.Smug:BAAALgAECgcJBwAAAA==.',
So='Sonicbergger:BAAALgADCgkJEAABLgAECgcJFwAMAIIbAA==.Sonícberger:BAABLgAECn8XAAIMAAcJghtGCwDMAQAMAAcJghtGCwDMAQAAAA==.',
St='Stain:BAAALgAECgEJAQAAAA==.Stepdragon:BAAALgADCgYJBgAAAA==.Stith:BAAALgADCgIJAgAAAA==.Stkinbck:BAAALgAECgYJEwAAAA==.Stonehenge:BAABLgAECn8UAAIaAAYJXyMwFwBcAgAaAAYJXyMwFwBcAgAAAA==.Stonepalm:BAAALgADCgMJAwAAAA==.Stratan:BAAALgADCggJCwAAAA==.',
Su='Suffer:BAAALgAECgQJCAABLgAECggJJwAfAJElAA==.Sundermere:BAAALgAECgEJAQAAAA==.Supercat:BAAALgAECgQJBwAAAA==.Surai:BAAALgADCgUJBQAAAA==.Surf:BAAALgAECgcJEwAAAA==.',
Sw='Swanky:BAAALgAECggJCwAAAA==.Swankydranky:BAACLgAFFH8NAAQZAAQJKA9EEAD+AAAZAAQJJwxEEAD+AAAYAAMJBgpLCQDcAAAhAAEJLgBcGgATAAAuAAQKfy0AAxkACQncGhESAIQCABkACQkVFxESAIQCABgACAlmG3ITAFUCAAAA.',
Sy='Sylvia:BAAALgAECgMJAwAAAA==.Symphania:BAAALgAECgQJBgAAAA==.',
['Sä']='Sätansangel:BAAALgADCgYJBgAAAA==.',
Ta='Tabbz:BAABLgAECn8eAAMcAAgJCxd8BADhAQAcAAgJCxd8BADhAQAaAAEJBQelpQAqAAAAAA==.Tahl:BAAALgADCgMJAwAAAA==.Taiils:BAAALgADCgQJBAAAAA==.Tallael:BAAALgADCgcJBwAAAA==.Tallyhochick:BAAALgAECgYJEAAAAA==.Taman:BAABLgAECn8VAAMcAAcJOBaiKADPAQAcAAcJOBaiKADPAQAaAAQJUQpneQCtAAAAAA==.Tasana:BAAALgADCgYJBgAAAA==.Taylerswift:BAAALgAECgQJBwAAAA==.',
Te='Tellesto:BAABLgAECn8iAAMlAAgJIR5cAwDLAQAlAAcJPx9cAwDLAQAOAAIJhhHaowCDAAAAAA==.',
Th='Thadox:BAAALgADCgIJAgAAAA==.Thalion:BAAALgADCgYJBgAAAA==.Thatdh:BAAALgADCgQJBAAAAA==.Thebestname:BAAALgADCgcJBwAAAA==.Thebigonion:BAAALgADCgcJEwAAAA==.',
Ti='Tinydh:BAAALgADCgYJBgAAAA==.Tinyfu:BAABLgAECn8cAAIZAAcJtRteBgCeAQAZAAcJtRteBgCeAQAAAA==.Tinymonk:BAAALgADCgIJAgABLgAECggJHAAOANYgAA==.Tinyriggo:BAAALgADCgYJBgAAAA==.Tinyshift:BAAALgAECgYJBgAAAA==.Tinytamer:BAABLgAECn8cAAMOAAgJ1iAIDwDDAgAOAAcJ3SMIDwDDAgAlAAMJqBHpDQCZAAAAAA==.',
To='Toko:BAACLgAFFH8OAAIOAAUJmR8oAQCGAQAOAAUJmR8oAQCGAQAuAAQKfyEAAw4ACAnDI+QIAAUDAA4ACAnDI+QIAAUDACYAAQmjCuWLAC8AAAAA.Tomblord:BAABLgAECn8eAAMdAAgJphuzAAAdAgAdAAgJphuzAAAdAgAeAAIJrwqNQABLAAAAAA==.Toogga:BAAALgADCgcJDgAAAA==.',
Tr='Treeheals:BAAALgAECgIJAgAAAA==.Truepatriot:BAABLgAECn8hAAMKAAgJqBMTMgC3AQAKAAgJqBMTMgC3AQAnAAUJsxL+CADkAAAAAA==.Truexlord:BAAALgAECgYJCwAAAA==.Truthez:BAAALgADCgMJBgABLgAECgYJFgANALsaAA==.Truths:BAAALgAECgIJAgABLgAECgYJFgANALsaAA==.Truthsx:BAABLgAECn8WAAMNAAYJuxolFQBnAQANAAUJcholFQBnAQAQAAIJJx/CGAC1AAAAAA==.',
Tw='Twin:BAAALgAECgIJAgAAAA==.',
Ty='Tygerkillz:BAAALgAECgIJAgAAAA==.Tylaatape:BAAALgAECgMJAwAAAA==.Tyraell:BAABLgAECn8bAAMKAAcJYx4XBAAzAgAKAAcJYx4XBAAzAgALAAQJnwc+7QC1AAAAAA==.Tyrelan:BAAALgADCgMJAwAAAA==.',
['Tõ']='Tõko:BAABLgAECn8YAAIeAAgJECFaBQDsAgAeAAgJECFaBQDsAgABLgAFFAUJDgAOAJkfAA==.',
Ud='Udor:BAAALgAECgYJCgAAAA==.',
Um='Umbrae:BAABLgAECn8ZAAICAAcJbRv7BQC7AQACAAcJbRv7BQC7AQAAAA==.',
Up='Upies:BAAALgAECgQJBQAAAA==.',
Us='Usgasdanelv:BAAALgAECgUJBgAAAA==.',
Uz='Uzala:BAAALgAECgIJAgAAAA==.',
Va='Valzanaya:BAAALgADCgYJBgAAAA==.Vanasmine:BAAALgAECgMJBAAAAA==.Vanleiden:BAAALgAECgQJBgAAAA==.Varael:BAAALgADCgIJAgAAAA==.Varielqt:BAAALgADCgEJAQAAAA==.Varilla:BAAALgAFFAEJAQAAAA==.',
Ve='Veera:BAABLgAECn8dAAIcAAgJfA48CQBrAQAcAAgJfA48CQBrAQAAAA==.Vendyr:BAABLgAECn8XAAQQAAgJoyHzBwDOAQANAAcJQx4tLQBZAgAQAAYJYhjzBwDOAQAXAAIJ8AsPYABPAAAAAA==.',
Vi='Vikadii:BAAALgADCgIJAgAAAA==.Viperjaxx:BAAALgADCgEJAQAAAA==.',
Vo='Voidbloom:BAAALgADCgYJBgAAAA==.Voodruid:BAAALgADCggJCQAAAA==.Vorgol:BAABLgAECn8XAAITAAgJFxYQCAA4AgATAAgJFxYQCAA4AgAAAA==.Voìd:BAAALgAECgQJBQAAAA==.',
Vy='Vyeria:BAABLgAECn8bAAILAAcJcxLnZAC3AQALAAcJcxLnZAC3AQAAAA==.Vyleera:BAAALgADCgEJAgAAAA==.Vynloran:BAACLgAFFH8KAAILAAQJdgo9BQA+AQALAAQJdgo9BQA+AQAuAAQKfxwAAgsACAmzHa8jAJoCAAsACAmzHa8jAJoCAAAA.',
We='Westerin:BAABLgAECn8VAAIXAAcJOBkwAgB8AQAXAAcJOBkwAgB8AQAAAA==.',
Wi='Wildchild:BAAALgADCgMJBgAAAA==.Wimateeka:BAABLgAECn8cAAQnAAcJuBxbAwCdAQAnAAcJuBxbAwCdAQAKAAUJxRIKYQD4AAALAAQJlw2R3QDRAAAAAA==.Windfury:BAAALgAECgYJCgABLgAECggJJwAfAJElAA==.Windigo:BAAALgAECgUJCgAAAA==.Winginit:BAAALgAECgUJCQABLgAFFAQJCwAVAG4SAA==.',
Wo='Wolfswarlock:BAAALgADCgMJAwAAAA==.Wooqles:BAAALgADCgcJDQAAAA==.',
Xa='Xaltorian:BAAALgADCgQJBAAAAA==.Xantus:BAAALgAECgQJBwAAAA==.',
Xi='Xiaoláng:BAAALgAECgQJBQAAAA==.Xiraxes:BAAALgAECgEJAQAAAA==.',
Ya='Yachak:BAAALgADCgcJBwABLgAECgcJHwALALgUAA==.',
Yi='Yiddosh:BAAALgAECgMJBgAAAA==.',
Yo='Yogí:BAACLgAFFH8JAAIaAAQJiR0/BgBjAQAaAAQJiR0/BgBjAQAuAAQKfxcAAxoACAk5I+AFABQDABoACAk5I+AFABQDACQAAQk+A9wuACoAAAAA.Yonamee:BAAALgADCgYJDAAAAA==.Yozomoto:BAAALgAECgQJBAAAAA==.',
Yu='Yumsumwum:BAAALgAECgEJAQABLgAECgkJFgALAOMgAA==.',
Za='Zalandria:BAAALgAECgQJBwAAAA==.Zanalia:BAAALgAECgMJAwAAAA==.',
Ze='Zeffie:BAAALgAECgQJBgAAAA==.Zelxari:BAAALgAECgYJDwAAAA==.Zensho:BAAALgAECgYJCQAAAA==.',
Zi='Zipsion:BAABLgAECn8VAAIOAAYJQyRMHwBKAgAOAAYJQyRMHwBKAgAAAA==.Zithen:BAAALgAECggJEgAAAA==.Zivver:BAABLgAECn8eAAISAAgJ1R/xAAByAgASAAgJ1R/xAAByAgAAAA==.',
Zo='Zorazig:BAAALgADCgIJAgAAAA==.',
Zx='Zxcycxz:BAAALgAECgMJAwAAAA==.',
['År']='Årikard:BAABLgAECn8VAAIKAAcJix6JBAAkAgAKAAcJix6JBAAkAgAAAA==.',
['Çh']='Çharmy:BAAALgAECggJCAAAAA==.',
['Éd']='Édelgard:BAAALgAECgEJAQAAAA==.',
['Üt']='Üther:BAABLgAECn8eAAMLAAgJ6h/qIQCiAgALAAgJlx/qIQCiAgAnAAEJgxaaEQBCAAAAAA==.',
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
