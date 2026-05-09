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

local lookup = {'Unknown-Unknown','Rogue-Subtlety','DeathKnight-Unholy','Druid-Restoration','Druid-Balance','Warrior-Fury','Warrior-Arms','Hunter-Marksmanship','Hunter-BeastMastery','Hunter-Survival','Warlock-Destruction','Warlock-Demonology','Mage-Fire','Shaman-Elemental','Evoker-Augmentation','Priest-Shadow','Druid-Guardian','Paladin-Holy','Mage-Frost','Warrior-Protection','Evoker-Preservation','Druid-Feral','Paladin-Retribution','Shaman-Restoration','Warlock-Affliction','Monk-Brewmaster','Priest-Holy','Priest-Discipline','Paladin-Protection','Shaman-Enhancement','DemonHunter-Devourer','DeathKnight-Blood','Rogue-Assassination','Monk-Windwalker','Monk-Mistweaver','Evoker-Devastation','DemonHunter-Havoc','DeathKnight-Frost','Rogue-Outlaw',}
local provider = {region='US',realm='Gorefiend',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abracadabra:BAAALgAECgYJCQAAAA==.Abracanoobra:BAAALgAECgYJBwABLgAECgYJCQABAAAAAA==.',
Ac='Acry:BAABLgAECn8hAAICAAkJqw1SEAChAQACAAkJqw1SEAChAQAAAA==.',
Ad='Adewe:BAAALgADCgcJEAAAAA==.Adry:BAAALgAECgYJDAAAAA==.',
Ae='Aelxdoox:BAAALgAECgMJBAAAAA==.',
Ag='Agartha:BAAALgADCgQJBAAAAA==.',
Ai='Ailiia:BAAALgADCgcJBwAAAA==.Airwickdin:BAAALgAECgEJAQAAAA==.',
Ak='Akagane:BAAALgADCgkJHwAAAA==.Akalla:BAAALgAECgUJDgAAAA==.',
Al='Alex:BAAALgAFFAQJBAAAAA==.Alexiel:BAAALgADCgUJBQAAAA==.Alfuric:BAAALgAECgYJBgAAAA==.Alliautopsy:BAAALgAECgQJBwAAAA==.Althraniir:BAAALgAECgYJEwAAAA==.Altrois:BAABLgAECn8uAAIDAAgJKR2tGAA4AgADAAgJKR2tGAA4AgAAAA==.Altruis:BAAALgADCgYJCgAAAA==.Alyshira:BAACLgAFFH8GAAIEAAMJBhmdHQDqAAAEAAMJBhmdHQDqAAAuAAQKfyMAAwQACQn8IScJAP4CAAQACQn8IScJAP4CAAUAAQnBF3J4AEMAAAAA.Alystrasza:BAAALgAECgcJEwABLgAFFAMJBgAEAAYZAA==.',
Am='Amatsano:BAAALgAECgUJDgAAAA==.Amorsith:BAAALgAECgYJCgAAAA==.Amurai:BAAALgAECgEJAQAAAA==.Amyst:BAACLgAFFH8FAAMGAAMJBROEIwCYAAAGAAIJ3AyEIwCYAAAHAAEJVh98FgBaAAAuAAQKfxsAAwcACAnAH4wHAN4BAAcABglmHowHAN4BAAYABQlFH+E3AMgBAAAA.',
An='Aneyna:BAAALgAECgQJCgAAAA==.Angrycrack:BAAALgAECggJEwAAAA==.Animuggus:BAEALgAECgUJDgAAAA==.Anjunabeets:BAABLgAFFH8VAAQIAAcJXBCWCQCAAQAIAAUJKQ2WCQCAAQAJAAQJDQ4PFABMAQAKAAEJlgjOHABOAAAAAA==.Anthran:BAABLgAECn8lAAMLAAkJhg8jHwBYAQALAAYJzQ4jHwBYAQAMAAcJ+wu9RwBRAQAAAA==.',
Ap='Apexlegend:BAAALgAECgUJBQAAAA==.',
Ar='Archos:BAAALgAECgEJAgAAAA==.Arcscythe:BAABLgAECn8bAAINAAgJ5RQVAgC5AQANAAgJ5RQVAgC5AQAAAA==.Arctron:BAAALgAECgYJBgABLgAECgkJIQACAKsNAA==.Arinok:BAAALgAECgEJAwAAAA==.Artoo:BAAALgAECgYJCgAAAA==.',
As='Astralpanda:BAABLgAECn8YAAIOAAgJKArNIwA2AQAOAAgJKArNIwA2AQAAAA==.',
Az='Azrayel:BAAALgAECgEJAQAAAA==.Azvar:BAABLgAECn8aAAIPAAYJaQ00MwAxAQAPAAYJaQ00MwAxAQAAAA==.',
Ba='Baconn:BAAALgAECgkJBwAAAA==.Badpwny:BAAALgADCgMJAwABLgAECggJGwAQAMAXAA==.Baer:BAABLgAECn8bAAIRAAcJ7wWaGgCGAAARAAcJ7wWaGgCGAAAAAA==.Bakon:BAAALgAECggJAwAAAA==.Balgith:BAABLgAECn8jAAISAAgJYA4zHQCeAQASAAgJYA4zHQCeAQAAAA==.Balrus:BAAALgADCgEJAQAAAA==.Baossulympis:BAABLgAECn8UAAIMAAYJCwlFaQD6AAAMAAYJCwlFaQD6AAAAAA==.Barron:BAAALgAECgYJDgABLgAFFAMJBgATAAcbAA==.Bastid:BAAALgADCgkJDwAAAA==.Battleburger:BAABLgAECn8WAAIUAAYJ0hy3DQCHAQAUAAYJ0hy3DQCHAQAAAA==.Bauchelaine:BAABLgAECn8YAAIMAAYJaA8zVAAvAQAMAAYJaA8zVAAvAQAAAA==.Bavunga:BAABLgAECn8aAAIVAAgJYCHSAQABAwAVAAgJYCHSAQABAwAAAA==.Bayle:BAAALgADCgcJCAAAAA==.',
Bc='Bchan:BAAALgAECgQJCQAAAA==.',
Be='Beanfrog:BAAALgAECgEJAwAAAA==.Beastadi:BAAALgAECgQJBAAAAA==.Beoron:BAACLgAFFH8GAAIWAAMJoxzGAwAlAQAWAAMJoxzGAwAlAQAuAAQKfyUAAhYACQnkJMsEAMoCABYACQnkJMsEAMoCAAAA.Bettyßastion:BAABLgAECn8kAAIXAAgJQB1wIAAHAgAXAAgJQB1wIAAHAgAAAA==.',
Bi='Big:BAAALgAECgQJBAAAAA==.Bigcat:BAAALgAECgYJCwAAAA==.Bigdawg:BAAALgAECgUJCQAAAA==.Bio:BAAALgAECgkJAQAAAA==.Biogen:BAAALgAECgEJAQABLgAECgkJAQABAAAAAA==.Bisoncrusher:BAAALgAECgUJCQAAAA==.',
Bl='Blastrakhan:BAAALgADCgYJDQAAAA==.Bloodstone:BAAALgAECgYJCgAAAA==.',
Bo='Boagrius:BAAALgADCgEJAQABLgAFFAIJCQAYAC8ZAA==.Boneash:BAAALgADCgIJAgAAAA==.Borabora:BAABLgAECn8UAAMKAAgJQCVcAgAdAwAKAAgJQCVcAgAdAwAIAAEJ+w8uigAxAAAAAA==.Boss:BAAALgAECgEJAQABLgAECgkJIQACAKsNAA==.Bouldernar:BAAALgADCgYJBgAAAA==.',
Br='Brageus:BAAALgAECgcJDQAAAA==.Breadmaster:BAAALgADCgYJBgAAAA==.Brontag:BAAALgAECggJDwAAAA==.Bruus:BAAALgAECgEJAQAAAA==.Bryant:BAAALgAECgcJDgAAAA==.',
Bu='Bud:BAABLgAECn8gAAIFAAgJeRYUKQC2AQAFAAgJeRYUKQC2AQAAAA==.Bugles:BAAALgAECgEJAwAAAA==.Bullessed:BAAALgAECgMJBAAAAA==.Busterbrown:BAABLgAECn8YAAMJAAcJZhOSNQB3AQAJAAcJZhOSNQB3AQAKAAQJBwNKJACpAAAAAA==.Butho:BAAALgADCgUJBQAAAA==.',
By='Byrnholf:BAAALgADCgcJDgAAAA==.',
Ca='Caliboy:BAAALgADCgMJBQAAAA==.Calißoy:BAABLgAECn8WAAIYAAYJYxOhOAAlAQAYAAYJYxOhOAAlAQAAAA==.Camabell:BAAALgADCgcJBwAAAA==.Canekii:BAAALgAECgUJBQAAAA==.Cannyon:BAAALgADCgEJAQAAAA==.Cartravistus:BAAALgADCgcJBwAAAA==.Cathrîne:BAAALgADCgkJIAAAAA==.',
Ce='Celarae:BAAALgADCgcJBwABLgAECgkJOwACADAlAA==.Ceruledge:BAAALgAECgYJDwABLgAFFAMJBgAQACkWAA==.',
Ch='Chaboomy:BAECLgAFFH8UAAIFAAUJeBT/DQBBAQAFAAUJeBT/DQBBAQAuAAQKfx0AAgUACAkFIOIPAKQCAAUACAkFIOIPAKQCAAAA.Changlaive:BAAALgADCgUJBQABLgAECgQJCQABAAAAAA==.Chaoscupcake:BAAALgADCgUJBQAAAA==.Chillshot:BAAALgAECgUJBgAAAA==.Chips:BAABLgAECn8kAAIGAAgJtRVCEgDdAQAGAAgJtRVCEgDdAQAAAA==.Chopper:BAABLgAECn8kAAIWAAkJpSBmAwABAwAWAAkJpSBmAwABAwABLgAFFAMJCgAZAG8JAA==.Chromate:BAABLgAFFH8HAAIaAAMJWA8MIgDUAAAaAAMJWA8MIgDUAAAAAA==.',
Ci='Cindreqt:BAABLgAECn8UAAMbAAcJfBWnJgC4AQAbAAcJ5hSnJgC4AQAcAAQJBAYMQQCpAAAAAA==.Cingz:BAAALgAECgMJBAAAAA==.',
Cl='Clicidios:BAAALgADCgYJBgAAAA==.',
Co='Cobblerjr:BAAALgAECgYJCwAAAA==.Coffeebean:BAAALgAECgQJBAAAAA==.Collie:BAEBLgAECn80AAIWAAkJoyVUAABcAwAWAAkJoyVUAABcAwAAAA==.Conkerin:BAAALgAECgYJBwAAAA==.',
Cr='Croissant:BAAALgAECgQJBwAAAA==.Crusadus:BAAALgAECgkJBAAAAA==.Crusible:BAAALgAECgUJCAAAAA==.',
Cu='Curzz:BAAALgAECggJCAAAAA==.',
Cy='Cycko:BAAALgAECgIJBAAAAA==.Cynis:BAAALgAECgEJAQAAAA==.',
Da='Dad:BAAALgAECgEJAQAAAA==.Daddy:BAAALgAECgEJAQABLgAECgEJAQABAAAAAA==.Dapper:BAAALgADCgIJAgAAAA==.Darkis:BAABLgAECn8WAAIEAAgJVQp+TgBqAQAEAAgJVQp+TgBqAQAAAA==.Darkseph:BAAALgAECgUJDwAAAA==.Daug:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.',
De='Deadcoffee:BAABLgAECn8bAAQMAAkJvhh5KwC3AQAMAAgJ+hF5KwC3AQALAAcJWRZtGwByAQAZAAIJ1RjhDgCPAAAAAA==.Deathshroud:BAAALgAFFAEJAQABLgAFFAUJEQACAGsZAA==.Deathsteak:BAAALgAECgYJBwAAAA==.Deebis:BAAALgADCgMJAwAAAA==.Deekaay:BAABLgAECn8kAAIDAAgJoxj+IQD+AQADAAgJoxj+IQD+AQAAAA==.Deepman:BAAALgAECgQJBAABLgAECggJEwABAAAAAA==.Delessia:BAAALgADCgIJAgAAAA==.Deo:BAABLgAECn82AAMdAAkJMyRfAABCAwAdAAkJMyRfAABCAwASAAgJkhy5FwBUAgAAAA==.',
Di='Diabo:BAAALgADCgcJBwAAAA==.Diddleficks:BAAALgAECgYJBgAAAA==.Diggersby:BAAALgAECgEJAQAAAA==.Disastrous:BAACLgAFFH8NAAIJAAQJfhSNEwBOAQAJAAQJfhSNEwBOAQAuAAQKfysAAgkACQkbIDQHAL4CAAkACQkbIDQHAL4CAAAA.Distractin:BAAALgAECgYJDgAAAA==.',
Dk='Dkfive:BAAALgADCgIJAgABLgADCgcJCAABAAAAAA==.',
Do='Doomangel:BAAALgAECgUJDgAAAA==.Dorá:BAAALgAFFAEJAQAAAA==.Doson:BAAALgAECgYJDAAAAA==.Doubleedge:BAAALgADCgIJAgABLgAECggJIwATAJsXAA==.',
Dr='Dracomoose:BAAALgADCgUJBQAAAA==.Drago:BAAALgAECgUJCgABLgAECgkJLgAXANMXAA==.Dragonslock:BAABLgAECn8VAAQMAAcJKQ4qWQAiAQAMAAYJcA4qWQAiAQALAAIJxAwnKgAuAAAZAAEJiwMtGgAiAAAAAA==.Drakelord:BAAALgAECggJEwAAAA==.Drakgor:BAAALgAECgYJBgAAAA==.Drakonic:BAABLgAECn8VAAIPAAcJCBGKJQCQAQAPAAcJCBGKJQCQAQAAAA==.Draygos:BAAALgAECgYJCwAAAA==.Drbigbolt:BAAALgADCgUJAgAAAA==.Druidtime:BAAALgADCgEJAQAAAA==.Drumboppie:BAABLgAECn8dAAMEAAgJ5BAvQAASAQAEAAYJFxAvQAASAQAFAAgJ9QYCNAC/AAAAAA==.Drunkenmasta:BAAALgAECgUJCgABLgAECggJEwABAAAAAA==.Druzzil:BAAALgAECgEJAQAAAA==.',
Du='Dummythicc:BAAALgAECgEJAQAAAA==.Duskblade:BAACLgAFFH8RAAICAAUJaxlLBwBvAQACAAUJaxlLBwBvAQAuAAQKfygAAgIACQnNH+UEAEcDAAIACQnNH+UEAEcDAAAA.Duskshifter:BAAALgAECgUJBQABLgAFFAUJEQACAGsZAA==.',
['Dø']='Døc:BAABLgAECn84AAQYAAkJLBbVJACSAQAYAAcJcxXVJACSAQAOAAkJHwuDHABqAQAeAAcJEAwfFgBcAQAAAA==.',
Ed='Edalynn:BAAALgAECgMJBQAAAA==.Eddie:BAAALgAECgYJDgAAAA==.',
Eg='Eggland:BAACLgAFFH8FAAIdAAMJWQ5aBQDDAAAdAAMJWQ5aBQDDAAAuAAQKfyAAAx0ACAlzG/4QALcBAB0ABwlyGP4QALcBABcABQndHgdwAJwBAAAA.',
Ei='Eielmolate:BAACLgAFFH8RAAMMAAUJbQ+KKgAbAQAMAAUJbQ+KKgAbAQALAAEJagEMGwBAAAAuAAQKfyQAAwwACAmbG2s1ADYCAAwABwmbG2s1ADYCAAsAAQkAALtfAE8AAAAA.',
El='Eldoryn:BAABLgAECn8fAAIfAAkJMBnbKgBVAgAfAAkJMBnbKgBVAgAAAA==.Elene:BAAALgADCgIJAgAAAA==.Ellyana:BAAALgAECgEJAQAAAA==.Elthius:BAAALgADCgIJAgAAAA==.',
Em='Emeraldcream:BAAALgAECgIJAgAAAA==.Emmabear:BAAALgAECgYJEAAAAA==.',
En='Enimed:BAABLgAECn87AAIgAAkJZRtiBAB1AgAgAAkJZRtiBAB1AgAAAA==.Ennio:BAAALgAECgYJBwAAAA==.Entropi:BAAALgADCgIJAgAAAA==.',
Er='Erzascarlet:BAAALgAECgUJCAAAAA==.',
Ev='Evil:BAACLgAFFH8KAAQZAAMJbwnrAwCPAAAMAAMJwQYlSwDBAAALAAIJ6AeSCQCYAAAZAAIJmgfrAwCPAAAuAAQKfycABAsACQnvGr4fAFQBAAwACAleGFJUAMoBAAsABwmiFL4fAFQBABkAAglRGtEYALQAAAAA.',
Ex='Exile:BAAALgADCgcJCQABLgADCgcJDwABAAAAAA==.',
Ey='Eyebite:BAAALgAFFAIJAwABLgAFFAMJBwAhAEwiAA==.',
Fa='Faelinius:BAAALgAECgUJDQAAAA==.Farfik:BAAALgAECgEJAQABLgAECgQJBwABAAAAAA==.Fatherseph:BAAALgADCgkJEQABLgAECgUJDwABAAAAAA==.',
Fe='Feleyeza:BAAALgADCgEJAQABLgAECgYJBwABAAAAAA==.',
Fi='Finntastic:BAAALgADCgYJCAABLgAECgcJHAAgAH4VAA==.Finnthehuman:BAAALgAECgYJCQAAAA==.Finntree:BAAALgAECgQJBAABLgAECgcJHAAgAH4VAA==.Fisterdobble:BAABLgAECn82AAITAAkJsxVUJgAKAgATAAkJsxVUJgAKAgAAAA==.',
Fl='Flawless:BAAALgADCgMJAwAAAA==.Fleurdelys:BAAALgADCgkJLQAAAA==.',
Fo='Forestpump:BAAALgAECggJCAABLgAECgcJEQABAAAAAA==.Forgeddemon:BAABLgAECn8XAAMaAAgJJgmkRQArAQAaAAcJ6wmkRQArAQAiAAQJ1wUSYgCHAAAAAA==.Forkinaround:BAAALgAECggJCwAAAA==.Fortune:BAAALgADCgYJBgAAAA==.',
Fr='Fralix:BAAALgAECgMJAwAAAA==.Frankiè:BAAALgAECgEJAQAAAA==.Fray:BAAALgADCgIJAgAAAA==.Frostbanshee:BAAALgADCgcJBwABLgAECgkJIgAjAMYWAA==.Frostborne:BAAALgAECgcJDgAAAA==.Frostheart:BAABLgAECn8kAAIdAAkJxR74AgB8AgAdAAkJxR74AgB8AgAAAA==.Frostina:BAABLgAECn8ZAAITAAcJmhQySQCMAQATAAcJmhQySQCMAQAAAA==.Frostmorne:BAAALgADCgEJAQAAAA==.Frostqueenie:BAAALgADCgEJAQAAAA==.',
Fu='Fullsend:BAAALgADCgcJCAAAAA==.Furionik:BAABLgAECn8YAAMUAAcJDRQyGACUAQAUAAcJDRQyGACUAQAGAAEJuAsMpgA5AAAAAA==.',
Fw='Fweaky:BAAALgAECgEJAQAAAA==.',
['Fé']='Féannas:BAAALgAECgkJCAAAAA==.',
Ga='Galcian:BAAALgAECgYJEwAAAA==.Gamjee:BAAALgAECgUJDgAAAA==.',
Ge='Gellis:BAAALgADCgUJCAAAAA==.Gerkinmonk:BAAALgAECgQJBQAAAA==.',
Gh='Ghidorah:BAAALgADCgQJBAAAAA==.',
Gl='Glimmawitz:BAAALgADCgIJAgAAAA==.Glo:BAAALgAECgUJCAAAAA==.Glofu:BAAALgAECgUJBQABLgAECgUJCAABAAAAAA==.',
Gn='Gnomeater:BAAALgADCgMJAwAAAA==.',
Go='Goldeen:BAAALgAECgYJCQAAAA==.Goodolrúss:BAAALgADCgUJBQAAAA==.Goombas:BAAALgAECgYJBQAAAA==.',
Gr='Gr:BAAALgADCgYJBgAAAA==.Grackalackin:BAABLgAECn8VAAIEAAYJzxBMOAA1AQAEAAYJzxBMOAA1AQAAAA==.Grinnaux:BAAALgADCgMJAwAAAA==.Grounds:BAACLgAFFH8HAAIhAAMJTCL9AgA2AQAhAAMJTCL9AgA2AQAuAAQKfxoAAiEACAldJBQCAOgCACEACAldJBQCAOgCAAAA.Grìffith:BAAALgAECgUJCAAAAA==.Grøtesk:BAAALgAECgYJEAAAAA==.',
Gu='Gulaj:BAAALgAECggJDwAAAA==.Gumby:BAAALgADCgIJAgAAAA==.Gunbrawl:BAAALgADCgEJAgAAAA==.',
['Gë']='Gënesis:BAAALgAECgQJBAAAAA==.',
Ha='Havixsucks:BAABLgAECn8pAAQZAAgJlxOdBQBrAQAMAAgJ0RFRRQD7AQAZAAcJGRKdBQBrAQALAAQJ3AdQJwA3AAAAAA==.',
He='Healgimp:BAABLgAECn8fAAIbAAgJGRYbFgCjAQAbAAgJGRYbFgCjAQAAAA==.Healslux:BAABLgAECn8eAAISAAkJvx+IAwAFAwASAAkJvx+IAwAFAwAAAA==.',
Hi='Hideyori:BAAALgAECgEJAQAAAA==.Highmane:BAAALgAECgYJBwAAAA==.',
Ho='Holyshot:BAAALgADCgUJCAAAAA==.Hope:BAEALgAECgEJAgABLgAFFAYJCQAcAAIPAA==.Hortzel:BAAALgAECgUJDgAAAA==.Howdoiheal:BAAALgAECgcJDQAAAA==.',
Hu='Humaa:BAAALgAECgIJAgAAAA==.Huntus:BAABLgAECn8vAAMJAAkJfyDOCgCNAgAJAAkJfyDOCgCNAgAIAAEJlQfokQApAAAAAA==.',
Ia='Iamdownhere:BAABLgAECn8cAAIXAAgJGRbXJwDhAQAXAAgJGRbXJwDhAQAAAA==.',
Ic='Icy:BAAALgAECgUJBgAAAA==.',
Il='Illadelf:BAAALgADCgEJAQABLgAECgUJBQABAAAAAA==.',
Im='Immersa:BAABLgAECn8WAAMkAAgJTBadDQAAAgAkAAgJdhWdDQAAAgAPAAcJjxKDIgCqAQAAAA==.Impostor:BAABLgAECn8gAAIQAAkJ+RtRBAClAgAQAAkJ+RtRBAClAgAAAA==.',
In='Indabow:BAABLgAECn8UAAIJAAgJKhooKAAXAgAJAAgJKhooKAAXAgAAAA==.Indamurim:BAABLgAECn8WAAMiAAgJJxKjKQCPAQAiAAcJTxCjKQCPAQAaAAcJcwzaPgBKAQAAAA==.Inzili:BAAALgAECgkJDgAAAA==.',
Is='Isaarek:BAABLgAECn8UAAIlAAgJihRPGQD7AQAlAAgJihRPGQD7AQAAAA==.',
Ja='Jabrick:BAABLgAECn8UAAMlAAgJvBhUEQBUAgAlAAgJvBhUEQBUAgAfAAEJdgUx6wAnAAAAAA==.Jakamu:BAAALgAECgUJDAAAAA==.Jamminmydh:BAAALgAECgYJCAABLgAFFAEJAQABAAAAAA==.Janim:BAAALgAECgUJBQAAAA==.Jattin:BAAALgADCgYJBgAAAA==.Jawnski:BAAALgAECggJDgAAAA==.Jay:BAAALgAECgQJBwAAAA==.',
Ji='Jibjabjibjab:BAACLgAFFH8KAAMCAAQJUhuWCABlAQACAAQJUhuWCABlAQAhAAEJBwe2CgBQAAAuAAQKfxUAAwIACAk8HPUhAOkBAAIABglfH/UhAOkBACEABAnmGMENAD8BAAAA.Jimm:BAACLgAFFH8WAAIaAAUJCw5bFQAbAQAaAAUJCw5bFQAbAQAuAAQKfyQAAhoACAnxElghAPcBABoACAnxElghAPcBAAAA.',
Ju='Judge:BAAALgAECgYJBgAAAA==.Juul:BAAALgAECgEJAQAAAA==.',
['Jì']='Jìm:BAAALgADCgIJAgABLgAECgIJAgABAAAAAA==.Jìmothy:BAAALgAECgIJAgAAAA==.',
Ka='Kailthosjr:BAAALgADCgEJAQAAAA==.Kazurtrin:BAAALgADCgMJAwAAAA==.',
Ke='Kelemvor:BAABLgAECn8mAAIfAAkJdB3wFQDTAgAfAAkJdB3wFQDTAgAAAA==.',
Kf='Kfp:BAAALgAECgQJBQAAAA==.',
Kh='Khandak:BAACLgAFFH8KAAIgAAQJ3BTjDAAMAQAgAAQJ3BTjDAAMAQAuAAQKfxUAAiAACAnWGf0OABwCACAACAnWGf0OABwCAAAA.',
Ki='Kibin:BAAALgAECgEJAQABLgAECgYJCAABAAAAAA==.Kidslaps:BAABLgAECn8bAAIaAAcJswwqIgApAQAaAAcJswwqIgApAQAAAA==.',
Kj='Kjsockeye:BAAALgADCgkJEgAAAA==.',
Kl='Kleenex:BAAALgAFFAEJAQAAAA==.',
Kn='Knigamortis:BAAALgADCgUJBQAAAA==.',
Ko='Kon:BAAALgAECgUJBQAAAA==.Kordmoridden:BAAALgADCgYJBgAAAA==.Korìe:BAAALgADCgQJBAABLgAECgIJAgABAAAAAA==.',
Kr='Krug:BAAALgAECgIJAgAAAA==.',
Ku='Kurisutina:BAABLgAECn8iAAIjAAkJxhacIACuAQAjAAkJxhacIACuAQAAAA==.',
La='Lana:BAAALgAECgMJAwAAAA==.Laokenic:BAAALgAECgUJBwAAAA==.Lariat:BAAALgAFFAEJAQAAAA==.',
Le='Leadblaster:BAAALgAECggJEwAAAA==.Leethalfu:BAAALgAECgQJBQAAAA==.Legosi:BAAALgAECgcJEwAAAA==.Lemegegen:BAABLgAECn8bAAIMAAkJChTtGQAVAgAMAAkJChTtGQAVAgAAAA==.',
Lh='Lhux:BAABLgAECn8oAAIJAAgJ3iG+DADZAgAJAAgJ3iG+DADZAgAAAA==.Lhuxi:BAAALgAFFAEJAQABLgAECggJKAAJAN4hAA==.',
Li='Lidean:BAAALgAECgIJAwAAAA==.Lilbokchoy:BAAALgADCgcJDQAAAA==.Lillith:BAAALgADCgYJBgAAAA==.Linkolas:BAAALgAECgcJEAAAAA==.Liny:BAAALgAECgYJCgAAAA==.',
Lo='Locrian:BAAALgADCgEJAQAAAA==.Lohotaf:BAAALgADCgcJDQAAAA==.Lorgar:BAAALgAECgQJBAAAAA==.',
Lu='Luca:BAAALgAECggJEQAAAA==.Luceean:BAAALgADCgcJDQAAAA==.Lucon:BAAALgAECgEJAgAAAA==.Lurth:BAAALgADCgYJBgAAAA==.Lurthshots:BAAALgAECgEJBAAAAA==.Luxmunkii:BAAALgAECgQJCAAAAA==.',
Ly='Lykaboops:BAAALgADCgcJEAABLgAECgkJOAAYACwWAA==.Lyxxie:BAABLgAECn8xAAMDAAkJZhnMNwBXAgADAAkJZhnMNwBXAgAmAAEJQAZfGQApAAAAAA==.',
Ma='Magentic:BAABLgAECn8jAAITAAgJmxcMMgDYAQATAAgJmxcMMgDYAQAAAA==.Mageus:BAAALgAECgEJAQAAAA==.Maguar:BAAALgAECggJEgAAAA==.Manimadruid:BAAALgADCgMJAwAAAA==.Manimashaman:BAAALgADCgYJBgAAAA==.Marek:BAAALgAECgEJAQABLgAECgUJDgABAAAAAA==.Marici:BAAALgADCgMJAwAAAA==.',
Me='Melith:BAAALgADCgkJEQAAAA==.Menthol:BAAALgADCgEJAQAAAA==.Menyin:BAAALgAECgYJCwABLgAFFAIJCQAYAC8ZAA==.Metsutan:BAABLgAECn87AAICAAkJMCWZAABUAwACAAkJMCWZAABUAwAAAA==.',
Mi='Milkystream:BAAALgAECgEJAgAAAA==.Mind:BAAALgAECgMJAwAAAA==.Mixlife:BAAALgADCgMJCQAAAA==.',
Mo='Moggle:BAABLgAECn8iAAMQAAgJERBbGAB6AQAQAAcJNRFbGAB6AQAbAAUJAggRYACyAAAAAA==.Moistfellow:BAABLgAECn8VAAITAAYJHxYDvABqAQATAAYJHxYDvABqAQAAAA==.Mokey:BAABLgAECn8aAAIZAAgJFyJ8AgCWAgAZAAgJFyJ8AgCWAgAAAA==.Molathom:BAAALgAECgIJAgAAAA==.Monktastic:BAAALgADCgYJCgABLgAECggJIwATAJsXAA==.Moog:BAAALgADCgkJCQAAAA==.Moohealer:BAAALgAECgYJDQAAAA==.Moppit:BAAALgAECgMJBAAAAA==.Morvster:BAAALgAECgYJCwAAAA==.Moskeebee:BAABLgAECn8UAAIJAAcJyiUREgCnAgAJAAcJyiUREgCnAgAAAA==.',
Mu='Muxx:BAAALgADCgEJAQAAAA==.',
['Mâ']='Mâtthêw:BAAALgAECgcJEAAAAA==.',
['Mø']='Møløtøv:BAABLgAECn8ZAAIMAAcJDQewXwASAQAMAAcJDQewXwASAQAAAA==.',
Na='Nazuresh:BAAALgAECgUJBgABLgAECgcJDwABAAAAAA==.',
Ne='Nekcrotic:BAABLgAECn8dAAMMAAgJUxseIgDlAQAMAAgJUxseIgDlAQALAAEJjAm9dQAvAAAAAA==.Nekromant:BAABLgAECn8oAAILAAgJlhoeAwD/AQALAAgJlhoeAwD/AQAAAA==.Nemriel:BAAALgAECgUJCgAAAA==.Newthilena:BAAALgADCgEJAQAAAA==.',
Ni='Nictus:BAABLgAECn8bAAMfAAkJjRadHwDKAQAfAAkJchCdHwDKAQAlAAYJfRhLIQCyAQAAAA==.Nirith:BAAALgAECgYJCwAAAA==.',
No='Nohric:BAAALgAECgUJBwAAAA==.Norsem:BAAALgAECgcJDAAAAA==.',
Nu='Numerion:BAAALgAECgMJAwAAAA==.Nutbutter:BAAALgADCgIJAgAAAA==.',
Ny='Nyagativity:BAAALgAECggJCAABLgAECgkJMwAGAJ8lAA==.',
['Nä']='Nämeless:BAAALgAECgQJBAAAAA==.',
['Nî']='Nîghtraid:BAABLgAECn8nAAIcAAgJTCBBBgCSAgAcAAgJTCBBBgCSAgAAAA==.',
Oa='Oakenmoose:BAAALgADCgMJBQAAAA==.',
Od='Odinn:BAAALgAECgIJAgABLgAECgYJCwABAAAAAA==.',
Oh='Ohlorn:BAAALgAECgIJCgAAAA==.',
On='Oneth:BAAALgAECgUJDgAAAA==.Onfleek:BAABLgAECn8cAAMbAAYJmSTPCABgAgAbAAYJmSTPCABgAgAQAAYJ9Qo9NgA7AQAAAA==.',
Op='Ophiline:BAAALgADCgUJBQAAAA==.Ophiri:BAAALgAECgQJBAAAAA==.Opladin:BAAALgAECgEJAQAAAA==.Opshammi:BAACLgAFFH8JAAIYAAIJLxnmLgCMAAAYAAIJLxnmLgCMAAAuAAQKfzIAAhgACAmHGpooAO4BABgACAmHGpooAO4BAAAA.',
Or='Orakrak:BAABLgAECn8dAAIGAAcJhgzQJQBFAQAGAAcJhgzQJQBFAQAAAA==.Oro:BAAALgADCgEJAQAAAA==.',
Oz='Ozzmodius:BAAALgADCgIJAwAAAA==.',
Pa='Pakapunch:BAAALgAECgIJAgAAAA==.Pallom:BAAALgAECgEJAgAAAA==.Parsera:BAAALgADCgIJAQABLgAECgkJKwAcABwlAA==.Parseus:BAAALgAECgkJCQABLgAECgkJKwAcABwlAA==.Parseval:BAABLgAECn8rAAQcAAkJHCWAAAC/AwAcAAkJHCWAAAC/AwAbAAQJPxspQwAsAQAQAAEJGRPwTQA+AAAAAA==.Pawerful:BAAALgADCgYJBgABLgAECgkJMwAGAJ8lAA==.Paws:BAABLgAECn8zAAIGAAkJnyW7AABJAwAGAAkJnyW7AABJAwAAAA==.',
Pe='Perdi:BAAALgADCgQJBwAAAA==.Pettigrew:BAAALgAECgQJBAAAAA==.Peut:BAAALgAECggJDgAAAA==.',
Ph='Physix:BAAALgAECgUJDgAAAA==.',
Pi='Pipsqueak:BAAALgADCgMJAwAAAA==.',
Po='Poedime:BAAALgAECgQJBQAAAA==.Popped:BAAALgAECgQJCgAAAA==.Porkins:BAABLgAECn80AAMmAAkJqh0QAQCfAgAmAAkJqh0QAQCfAgAgAAcJhhHqGgDvAAAAAA==.Porkçhop:BAAALgAECgEJAgAAAA==.Potterpanda:BAAALgADCgQJBAAAAA==.Powerline:BAAALgAECgQJBQAAAA==.',
Pr='Priestus:BAAALgADCgkJCQAAAA==.Promised:BAAALgAECgMJAwABLgAFFAEJAQABAAAAAA==.',
Pt='Ptolemy:BAAALgAECgEJAQAAAA==.',
Py='Pyraxx:BAABLgAECn8nAAITAAkJaR3CCwDDAgATAAkJaR3CCwDDAgAAAA==.',
['Pê']='Pênny:BAAALgADCgEJAQABLgAECgIJAgABAAAAAA==.',
Qu='Quakezord:BAAALgADCgYJBgAAAA==.Quesofundido:BAAALgADCgEJAQAAAA==.Quillvo:BAAALgADCgkJCQAAAA==.',
Ra='Radovan:BAAALgAECgUJCwAAAA==.Ramipril:BAAALgADCgMJAwAAAA==.Ranestari:BAAALgADCgcJBgAAAA==.Ranlor:BAAALgADCgYJBgAAAA==.Raphorath:BAABLgAECn8bAAMfAAcJVRFKQwAvAQAfAAcJnBBKQwAvAQAlAAIJWwy1XgBmAAAAAA==.Rareware:BAAALgADCgEJAQAAAA==.Rax:BAAALgAECgEJAQAAAA==.Razputan:BAAALgAECgYJBgABLgAECgYJCwABAAAAAA==.Raìdèn:BAABLgAECn8bAAMbAAYJlxXNLgCIAQAbAAYJlxXNLgCIAQAQAAQJ5gN5QQBtAAABLgAECgcJDwABAAAAAA==.',
Re='Relsdruid:BAACLgAFFH8JAAIFAAQJqw6YEQAqAQAFAAQJqw6YEQAqAQAuAAQKfyQAAgUACAnpHqcRAI4CAAUACAnpHqcRAI4CAAAA.Replicate:BAAALgAECgcJDAAAAA==.Resisted:BAAALgAECgEJAQABLgAFFAUJEQAPAEYdAA==.Restocrayze:BAAALgAECgIJAgAAAA==.',
Ri='Rickets:BAAALgAECgIJAwAAAA==.',
Ro='Rookeria:BAAALgADCgYJBgAAAA==.Ropesale:BAAALgADCgEJAQAAAA==.Rosaelyia:BAAALgADCgQJBAABLgAECggJJAAJAAQYAA==.',
Ry='Ryanx:BAACLgAFFH8JAAISAAUJPB6nBQDGAQASAAUJPB6nBQDGAQAuAAQKfycAAhIACQksI90AAJIDABIACQksI90AAJIDAAAA.Ryanxx:BAAALgAECgYJBgAAAA==.Ryanxz:BAAALgAECgQJBAAAAA==.Ryri:BAAALgAECgcJEQAAAA==.',
Sa='Saatana:BAABLgAECn8ZAAMcAAkJkwqtIgB+AQAcAAkJkwqtIgB+AQAQAAIJGQuoQQBsAAAAAA==.Sadima:BAAALgAECgEJAQAAAA==.Sahaquiel:BAAALgAECgEJAQAAAA==.Salife:BAAALgAECgEJAgAAAA==.Samavati:BAABLgAECn8kAAMjAAgJ6A7FLgBDAQAjAAcJ0gzFLgBDAQAaAAgJLweKIgAmAQAAAA==.Samrc:BAAALgADCgEJAQAAAA==.Sanddragon:BAAALgADCgcJDQAAAA==.Sands:BAAALgAECgcJDwAAAA==.Santoku:BAAALgAECgUJDgAAAA==.Sarah:BAABLgAECn8uAAIcAAkJxBuGBgCLAgAcAAkJxBuGBgCLAgAAAA==.Sassyface:BAABLgAECn8zAAILAAkJlg7RBAC4AQALAAkJlg7RBAC4AQAAAA==.Sathend:BAAALgADCgUJBQAAAA==.Saveena:BAAALgAECgEJAQAAAA==.Saviq:BAAALgADCgEJAgAAAA==.',
Se='Seabolt:BAAALgAECgYJBgABLgAFFAMJBgAEAAYZAA==.Sebbyr:BAAALgADCgMJAwAAAA==.Sellit:BAAALgADCgEJAgAAAA==.',
Sh='Shadowdin:BAAALgAECgYJDwAAAA==.Shaduw:BAACLgAFFH8WAAIUAAUJ+SDpAwB/AQAUAAUJ+SDpAwB/AQAuAAQKfyQAAxQACAnOIbEDABkDABQACAnOIbEDABkDAAYACAkBDjwyAOMBAAAA.Shanalister:BAAALgADCgUJBQAAAA==.Shari:BAABLgAECn8VAAICAAcJVg8lFABwAQACAAcJVg8lFABwAQAAAA==.Shiklah:BAAALgAECgQJBAAAAA==.',
Si='Sibbrena:BAACLgAFFH8GAAIQAAMJKRZUEQAAAQAQAAMJKRZUEQAAAQAuAAQKfyoAAhAACQkXHvwFAC4DABAACQkXHvwFAC4DAAAA.Sivanna:BAAALgAECgQJAgABLgAECgkJCAABAAAAAA==.Sixpacksorc:BAACLgAFFH8GAAITAAMJBxtvPgATAQATAAMJBxtvPgATAQAuAAQKfycAAhMACQlNIycVACkDABMACQlNIycVACkDAAAA.',
Sk='Skn:BAABLgAECn8hAAMSAAgJnSPNEACMAgASAAgJnSPNEACMAgAXAAQJrBhJsgCQAAAAAA==.',
Sl='Slizzard:BAAALgAECgYJDgAAAA==.',
Sm='Smutty:BAAALgAECggJDgAAAA==.',
Sn='Snackychan:BAAALgAECgcJEQAAAA==.Sniperdoom:BAAALgADCgYJBgAAAA==.',
So='Sourdiesal:BAAALgAECgUJBQAAAA==.',
Sp='Spleen:BAABLgAECn8bAAQhAAcJtRd6BQCjAQAhAAcJORZ6BQCjAQACAAQJ9RiHPwAhAQAnAAEJMAirDgAyAAAAAA==.Spron:BAAALgADCgEJAQAAAA==.Spywo:BAAALgAECgEJAQABLgAECgEJAQABAAAAAA==.',
Sq='Squirrelydan:BAAALgAECgQJCQAAAA==.',
St='Stabbý:BAAALgAECgYJBgABLgAECgIJAgABAAAAAA==.Stabinem:BAAALgADCgcJAQAAAA==.Stardria:BAAALgADCgUJCQAAAA==.Stelthme:BAAALgAECgYJDwABLgAFFAMJBwACAKIdAA==.Stormburst:BAAALgADCgIJAgABLgAFFAMJBwAhAEwiAA==.Strawberries:BAABLgAECn8cAAITAAcJQyFFOgCNAgATAAcJQyFFOgCNAgABLgAECggJFAAKAEAlAA==.',
Sw='Swan:BAAALgAECgIJBAABLgAFFAMJBwAKAI8IAA==.Swoleyspirit:BAAALgAECgMJBQAAAA==.',
Ta='Takamura:BAABLgAECn8dAAIUAAgJHh4rBQBUAgAUAAgJHh4rBQBUAgAAAA==.Tarle:BAAALgAECgcJCgAAAA==.Tazath:BAABLgAECn8VAAMPAAkJXBe5DwDYAQAPAAkJXBe5DwDYAQAkAAEJ0wF5RAAkAAABLgAFFAMJBgAWAKMcAA==.',
Te='Techsorcist:BAAALgAECgQJBQAAAA==.',
Th='Theory:BAABLgAECn8jAAIDAAgJQxTBMAC2AQADAAgJQxTBMAC2AQAAAA==.Thessali:BAAALgAECgYJCwAAAA==.Thiccen:BAAALgADCgEJAQABLgADCgIJAgABAAAAAA==.Thoranji:BAAALgAECgUJCAAAAA==.',
Ti='Tipz:BAAALgAECgUJBwAAAA==.Tism:BAAALgADCgYJBgAAAA==.Titanpanda:BAAALgAECgEJAQAAAA==.',
To='Tomjim:BAACLgAFFH8RAAMPAAUJRh3mDgBaAQAPAAUJRh3mDgBaAQAVAAIJbgflEwCLAAAuAAQKfyUABA8ACAkCIAcLAMUCAA8ACAkCIAcLAMUCABUABwnmEBYdAJwBACQABglrCykiABkBAAAA.',
Tr='Trashii:BAABLgAECn8mAAIKAAkJwxuiBQBcAgAKAAkJwxuiBQBcAgAAAA==.Treevive:BAACLgAFFH8IAAIEAAQJghJiFAArAQAEAAQJghJiFAArAQAuAAQKfxgAAgQACAmbID8cAFoCAAQACAmbID8cAFoCAAAA.Trenx:BAAALgAECgUJCAAAAA==.Trystan:BAABLgAECn8cAAIXAAYJxgoBdgAAAQAXAAYJxgoBdgAAAQAAAA==.',
Ts='Tsinga:BAAALgAECgYJEAAAAA==.',
Tu='Turl:BAAALgAECgQJBwABLgAECgYJGgASAGIeAA==.Turlo:BAABLgAECn8aAAISAAYJYh42LADWAQASAAYJYh42LADWAQAAAA==.',
Tw='Tweik:BAAALgADCgcJCAAAAA==.Twoglaives:BAAALgAECgMJBgABLgAFFAMJCgAnABwKAA==.Twostep:BAACLgAFFH8KAAInAAMJHAo8BADiAAAnAAMJHAo8BADiAAAuAAQKfygAAicACQnyGRUDACwCACcACQnyGRUDACwCAAAA.',
['Tø']='Tøm:BAACLgAFFH8PAAIXAAUJHR1qDAB4AQAXAAUJHR1qDAB4AQAuAAQKfyIAAhcABwmkJTkYANgCABcABwmkJTkYANgCAAAA.',
Ul='Ullirus:BAAALgADCgYJAwAAAA==.',
Un='Unbearable:BAAALgADCgYJBgAAAA==.Unbroken:BAAALgADCgEJAQAAAA==.Undergrowth:BAAALgAFFAEJAgAAAA==.Unshookable:BAABLgAECn8qAAIjAAkJXB3ABwB6AgAjAAkJXB3ABwB6AgAAAA==.',
Ur='Ursos:BAAALgAECgUJCgAAAA==.',
Uz='Uzume:BAAALgADCgEJAQAAAA==.',
Va='Valefor:BAAALgAECggJDQAAAA==.Vallatris:BAAALgAECgUJDgAAAA==.Valsande:BAAALgADCgkJFwAAAA==.Vargr:BAAALgADCgEJAQAAAA==.',
Ve='Velton:BAAALgADCgMJAwAAAA==.Vendnmachine:BAABLgAECn8XAAITAAYJvgpjfQAWAQATAAYJvgpjfQAWAQAAAA==.Vermaelen:BAAALgAECgcJDAAAAA==.',
Vh='Vhyk:BAAALgADCgYJBgAAAA==.',
Vi='Viviera:BAAALgADCgcJBwABLgAECgUJDwABAAAAAA==.',
Vo='Voidh:BAAALgAFFAIJAgAAAA==.Voidlockus:BAAALgAECgEJAQAAAA==.',
Wa='Wargeezer:BAAALgAECgEJAgAAAA==.Wariuus:BAAALgAECgEJAQAAAA==.Watercupp:BAAALgAECgMJBAAAAA==.',
We='Wear:BAAALgAECgYJDgAAAA==.',
Wh='Whimsy:BAAALgADCgcJDwAAAA==.',
Wi='Wisewithpet:BAAALgAECgYJCQAAAA==.Wisheni:BAABLgAECn8fAAIcAAcJ0hGNFwB7AQAcAAcJ0hGNFwB7AQAAAA==.',
Wr='Wrathofdolph:BAAALgAECgIJBAAAAA==.Wrexx:BAAALgAFFAEJAQAAAA==.',
Xi='Xial:BAAALgAECgEJAQABLgAECgYJEwABAAAAAA==.',
Xy='Xyfin:BAABLgAECn8mAAIKAAkJLxwzBACGAgAKAAkJLxwzBACGAgAAAA==.',
Yo='Yoruichi:BAAALgADCgEJAQAAAA==.',
Yu='Yunalescah:BAAALgAECgMJAwAAAA==.Yuno:BAAALgAECgEJAQAAAA==.',
Za='Zaboo:BAABLgAECn8UAAQZAAYJviB8DABwAQAMAAUJch6LXACzAQAZAAQJByJ8DABwAQALAAEJAABPYABOAAAAAA==.Zandramadas:BAABLgAECn8xAAMEAAkJMRpnLAD9AQAEAAgJqRlnLAD9AQAFAAgJQB5IEwCqAQAAAA==.Zaraline:BAABLgAECn8kAAIJAAgJBBimIQDTAQAJAAgJBBimIQDTAQAAAA==.Zarasha:BAAALgAECgQJBgAAAA==.',
Ze='Zeakz:BAAALgAECgEJAgAAAA==.Zemsta:BAAALgADCgEJAQAAAA==.Zephon:BAABLgAECn8bAAIDAAcJHhkbOgCRAQADAAcJHhkbOgCRAQAAAA==.Zerksees:BAAALgADCgMJAwAAAA==.',
Zi='Zinyak:BAAALgAECgUJDgAAAA==.Zithrax:BAAALgADCgYJBgAAAA==.',
Zo='Zohara:BAAALgAECgQJBAAAAA==.Zoomiez:BAAALgAECggJEgAAAA==.',
Zu='Zumwalmilui:BAAALgAECgEJAgAAAA==.',
Zy='Zyyn:BAABLgAECn8nAAITAAgJrBzTGABWAgATAAgJrBzTGABWAgAAAA==.',
['Ði']='Ðisperse:BAAALgAECgUJBQABLgAECgcJGAAQAN0YAA==.',
['Øv']='Øval:BAAALgAECgEJAQAAAA==.',
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
