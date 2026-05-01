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

local lookup = {'Unknown-Unknown','Rogue-Subtlety','DeathKnight-Unholy','Druid-Restoration','Druid-Balance','Warrior-Arms','Warrior-Fury','Hunter-Marksmanship','Hunter-BeastMastery','Warlock-Destruction','Warlock-Demonology','Mage-Fire','Shaman-Elemental','Evoker-Augmentation','Priest-Shadow','Druid-Guardian','Paladin-Holy','Mage-Frost','Warrior-Protection','Druid-Feral','Paladin-Retribution','Hunter-Survival','Monk-Brewmaster','Priest-Holy','Priest-Discipline','Paladin-Protection','Shaman-Restoration','Shaman-Enhancement','DemonHunter-Devourer','DeathKnight-Blood','Warlock-Affliction','Monk-Windwalker','Monk-Mistweaver','Rogue-Assassination','Evoker-Devastation','DemonHunter-Havoc','DeathKnight-Frost','Rogue-Outlaw','Evoker-Preservation',}
local provider = {region='US',realm='Gorefiend',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abracadabra:BAAALgAECgYJCQAAAA==.Abracanoobra:BAAALgAECgYJBwABLgAECgYJCQABAAAAAA==.',
Ac='Acry:BAABLgAECn8eAAICAAgJdg1EEQBeAQACAAgJdg1EEQBeAQAAAA==.',
Ad='Adewe:BAAALgADCgcJEAAAAA==.Adry:BAAALgAECgYJDAAAAA==.',
Ae='Aelxdoox:BAAALgAECgEJAQAAAA==.',
Ag='Agartha:BAAALgADCgQJBAAAAA==.',
Ai='Ailiia:BAAALgADCgcJBwAAAA==.Airwickdin:BAAALgAECgEJAQAAAA==.',
Ak='Akagane:BAAALgADCgkJHwAAAA==.Akalla:BAAALgAECgQJCQAAAA==.',
Al='Aldele:BAAALgADCgEJAQABLgADCgYJBgABAAAAAA==.Alexiel:BAAALgADCgUJBQAAAA==.Alfuric:BAAALgAECgIJAgAAAA==.Alliautopsy:BAAALgAECgIJAwAAAA==.Althraniir:BAAALgAECgYJEwAAAA==.Altrois:BAABLgAECn8lAAIDAAgJpBv8EAA0AgADAAgJpBv8EAA0AgAAAA==.Altruis:BAAALgADCgYJCgAAAA==.Alyshira:BAABLgAECn8iAAMEAAgJAyQqCQD+AgAEAAgJAyQqCQD+AgAFAAEJwRdseABDAAAAAA==.Alystrasza:BAAALgAECgcJEwABLgAECggJIgAEAAMkAA==.',
Am='Amatsano:BAAALgAECgQJCQAAAA==.Amorsith:BAAALgAECgYJCgAAAA==.Amurai:BAAALgAECgEJAQAAAA==.Amyst:BAABLgAECn8YAAMGAAYJnyLdCgBUAQAHAAUJQR/jNwDIAQAGAAQJUyHdCgBUAQAAAA==.',
An='Aneyna:BAAALgAECgQJCQAAAA==.Angrycrack:BAAALgAECgYJEQAAAA==.Animuggus:BAEALgAECgQJCQAAAA==.Anjunabeets:BAABLgAFFH8TAAMIAAYJQQ2RCQCAAQAIAAUJKQ2RCQCAAQAJAAMJdwi1HQDoAAAAAA==.Anthran:BAABLgAECn8hAAMKAAkJvg0oHwBYAQAKAAYJzQ4oHwBYAQALAAcJGQnkPAA8AQAAAA==.',
Ap='Apexlegend:BAAALgAECgUJBQAAAA==.',
Ar='Archos:BAAALgAECgEJAQAAAA==.Arcscythe:BAABLgAECn8YAAIMAAYJhxkKBAC2AQAMAAYJhxkKBAC2AQAAAA==.Areyouscared:BAAALgAECgIJBAABLgAFFAEJAQABAAAAAA==.Arinok:BAAALgAECgEJAgAAAA==.Artoo:BAAALgAECgUJCQAAAA==.',
As='Astralpanda:BAABLgAECn8XAAINAAgJIAr8GQBDAQANAAgJIAr8GQBDAQAAAA==.',
Az='Azrayel:BAAALgAECgEJAQAAAA==.Azvar:BAABLgAECn8UAAIOAAYJQgw1MwAxAQAOAAYJQgw1MwAxAQAAAA==.',
Ba='Baconn:BAAALgAECgkJBwAAAA==.Badpwny:BAAALgADCgMJAwABLgAECgYJGAAPABEcAA==.Baer:BAABLgAECn8UAAIQAAYJwwarFAB5AAAQAAYJwwarFAB5AAAAAA==.Bakon:BAAALgAECggJAgAAAA==.Balgith:BAABLgAECn8bAAIRAAgJVwsSGACOAQARAAgJVwsSGACOAQAAAA==.Balrus:BAAALgADCgEJAQAAAA==.Baossulympis:BAAALgAECgUJDgAAAA==.Barron:BAAALgAECgYJDgABLgAECggJJgASAFokAA==.Bastid:BAAALgADCgkJDwAAAA==.Battleburger:BAABLgAECn8VAAITAAYJJxvwCgB5AQATAAYJJxvwCgB5AQAAAA==.Bauchelaine:BAABLgAECn8UAAILAAYJBg7zQQAsAQALAAYJBg7zQQAsAQAAAA==.Bavunga:BAAALgAECggJEQAAAA==.Bayle:BAAALgADCgcJCAAAAA==.',
Bc='Bchan:BAAALgAECgQJCQAAAA==.',
Be='Beanfrog:BAAALgAECgEJAwAAAA==.Beastadi:BAAALgAECgQJBAAAAA==.Beoron:BAABLgAECn8kAAIUAAkJ5CTLBADKAgAUAAkJ5CTLBADKAgAAAA==.Bettyßastion:BAABLgAECn8cAAIVAAgJzByeGgDrAQAVAAgJzByeGgDrAQAAAA==.',
Bi='Big:BAAALgAECgQJBAAAAA==.Bigcat:BAAALgAECgYJCwAAAA==.Bigdawg:BAAALgAECgUJCQAAAA==.Bio:BAAALgAECgkJAQAAAA==.Biogen:BAAALgAECgEJAQABLgAECgkJAQABAAAAAA==.Bisoncrusher:BAAALgAECgQJBAAAAA==.',
Bl='Blastrakhan:BAAALgADCgYJDQAAAA==.Bloodstone:BAAALgAECgYJCgAAAA==.',
Bo='Boneash:BAAALgADCgIJAgAAAA==.Borabora:BAABLgAECn8UAAMWAAgJQCVcAgAdAwAWAAgJQCVcAgAdAwAIAAEJ+w/+iQAxAAAAAA==.Boss:BAAALgAECgEJAQABLgAECggJHgACAHYNAA==.Bouldernar:BAAALgADCgYJBgAAAA==.',
Br='Brageus:BAAALgAECgYJBgAAAA==.Breadmaster:BAAALgADCgYJBgAAAA==.Brontag:BAAALgAECgYJDAAAAA==.Bruus:BAAALgADCgcJCwAAAA==.Bryant:BAAALgAECgcJDgAAAA==.',
Bu='Bud:BAABLgAECn8gAAIFAAgJeRYTKQC2AQAFAAgJeRYTKQC2AQAAAA==.Bugles:BAAALgAECgEJAwAAAA==.Bullessed:BAAALgAECgMJBAAAAA==.Busterbrown:BAAALgAECgYJEwAAAA==.',
By='Byrnholf:BAAALgADCgcJDgAAAA==.',
Ca='Caliboy:BAAALgADCgMJBQAAAA==.Calißoy:BAAALgAECgYJEAAAAA==.Camabell:BAAALgADCgcJBwAAAA==.Canekii:BAAALgAECgUJBQAAAA==.Cannyon:BAAALgADCgEJAQAAAA==.Cartravistus:BAAALgADCgcJBwAAAA==.Cathrîne:BAAALgADCgkJIAAAAA==.',
Ce='Celarae:BAAALgADCgcJBwABLgAECgkJMgACAL8kAA==.Ceruledge:BAAALgAECgYJCwABLgAFFAMJBgAPACkWAA==.',
Ch='Chaboomy:BAECLgAFFH8QAAIFAAUJ0xCFCwA4AQAFAAUJ0xCFCwA4AQAuAAQKfx0AAgUACAkFIOQPAKQCAAUACAkFIOQPAKQCAAAA.Changlaive:BAAALgADCgUJBQABLgAECgQJCQABAAAAAA==.Chaoscupcake:BAAALgADCgUJBQAAAA==.Chillshot:BAAALgAECgUJBgAAAA==.Chips:BAABLgAECn8fAAIHAAcJaRPKEgChAQAHAAcJaRPKEgChAQAAAA==.Chopper:BAABLgAECn8jAAIUAAkJpSBmAwABAwAUAAkJpSBmAwABAwAAAA==.Chromate:BAABLgAFFH8GAAIXAAMJEQnBGwC+AAAXAAMJEQnBGwC+AAAAAA==.',
Ci='Cindreqt:BAABLgAECn8UAAMYAAcJfBWlJgC4AQAYAAcJ5hSlJgC4AQAZAAQJBAYJQQCpAAAAAA==.Cingz:BAAALgAECgMJBAAAAA==.',
Cl='Clicidios:BAAALgADCgYJBgAAAA==.',
Co='Cobblerjr:BAAALgAECgYJCwAAAA==.Collie:BAEBLgAECn8yAAIUAAkJoSUsAABkAwAUAAkJoSUsAABkAwAAAA==.Conkerin:BAAALgAECgUJBQAAAA==.',
Cr='Croissant:BAAALgAECgQJBwAAAA==.Crusadus:BAAALgAECgkJBAAAAA==.Crusible:BAAALgAECgUJCAAAAA==.',
Cu='Curzz:BAAALgADCgcJBgAAAA==.',
Cy='Cycko:BAAALgAECgIJAgAAAA==.Cynis:BAAALgAECgEJAQAAAA==.',
Da='Dad:BAAALgADCgMJAwABLgAECgEJAQABAAAAAA==.Daddy:BAAALgAECgEJAQABLgAECgEJAQABAAAAAA==.Dapper:BAAALgADCgIJAgAAAA==.Darkis:BAABLgAECn8WAAIEAAgJVQqBTgBqAQAEAAgJVQqBTgBqAQAAAA==.Darkseph:BAAALgAECgQJCgAAAA==.',
De='Deadcoffee:BAABLgAECn8YAAMKAAgJeRhwGwByAQALAAcJMhKgLAB6AQAKAAcJXhZwGwByAQAAAA==.Deathsteak:BAAALgAECgYJBwAAAA==.Deebis:BAAALgADCgMJAwAAAA==.Deekaay:BAABLgAECn8cAAIDAAgJGxdMGQDxAQADAAgJGxdMGQDxAQAAAA==.Deepman:BAAALgAECgMJAwABLgAECggJEwABAAAAAA==.Delessia:BAAALgADCgIJAgAAAA==.Deo:BAABLgAECn8yAAMaAAkJHCQ3AABJAwAaAAkJHCQ3AABJAwARAAgJkhy7FwBUAgAAAA==.',
Di='Diabo:BAAALgADCgcJBwAAAA==.Diddleficks:BAAALgAECgYJBgAAAA==.Diggersby:BAAALgAECgEJAQAAAA==.Disastrous:BAACLgAFFH8JAAIJAAQJJBCtDQBKAQAJAAQJJBCtDQBKAQAuAAQKfysAAgkACQkbIOQCAOICAAkACQkbIOQCAOICAAAA.Distractin:BAAALgAECgYJDgAAAA==.',
Dk='Dkfive:BAAALgADCgIJAgAAAA==.',
Do='Doomangel:BAAALgAECgQJCQAAAA==.Dorá:BAAALgAFFAEJAQAAAA==.Doson:BAAALgAECgEJAQAAAA==.Doubleedge:BAAALgADCgIJAgABLgAECgcJIAASAAAZAA==.',
Dr='Dracomoose:BAAALgADCgUJBQAAAA==.Drago:BAAALgAECgUJCgABLgAECggJJQAVAP0VAA==.Dragonslock:BAAALgAECgYJDwAAAA==.Drakelord:BAAALgAECggJEwAAAA==.Drakgor:BAAALgAECgYJBgAAAA==.Drakonic:BAABLgAECn8VAAIOAAcJCBGMJQCQAQAOAAcJCBGMJQCQAQAAAA==.Draygos:BAAALgAECgYJCwAAAA==.Drbigbolt:BAAALgADCgUJAgAAAA==.Druidtime:BAAALgADCgEJAQAAAA==.Drumboppie:BAABLgAECn8ZAAMEAAcJLg4HMAAdAQAEAAYJFhAHMAAdAQAFAAYJ3wUgOQBhAAAAAA==.Drunkenmasta:BAAALgAECgQJBAABLgAECggJEwABAAAAAA==.Druzzil:BAAALgAECgEJAQAAAA==.',
Du='Dummythicc:BAAALgAECgEJAQAAAA==.Duskblade:BAACLgAFFH8OAAICAAUJQRCBCABRAQACAAUJQRCBCABRAQAuAAQKfygAAgIACQnNH+YEAEcDAAIACQnNH+YEAEcDAAAA.Duskshifter:BAAALgAECgUJBQABLgAFFAUJDgACAEEQAA==.',
['Dø']='Døc:BAABLgAECn8vAAQbAAkJYxXoGACdAQAbAAcJcBXoGACdAQANAAkJRAozFQBtAQAcAAYJzw0gFgBcAQAAAA==.',
Ed='Edalynn:BAAALgAECgMJBQAAAA==.Eddie:BAAALgAECgYJDgAAAA==.',
Eg='Eggland:BAABLgAECn8gAAMaAAgJcxv+EAC3AQAaAAcJchj+EAC3AQAVAAUJ3R4HcACcAQAAAA==.',
Ei='Eielmolate:BAACLgAFFH8QAAMLAAUJ1Q0bGwA1AQALAAUJ1Q0bGwA1AQAKAAEJagEHGwBAAAAuAAQKfyQAAwsACAmbG2w1ADYCAAsABwmbG2w1ADYCAAoAAQkAAL1fAE8AAAAA.',
El='Eldoryn:BAABLgAECn8eAAIdAAgJgxnkKgBVAgAdAAgJgxnkKgBVAgAAAA==.Elene:BAAALgADCgIJAgAAAA==.Elthius:BAAALgADCgIJAgAAAA==.',
Em='Emeraldcream:BAAALgAECgIJAgAAAA==.Emmabear:BAAALgAECgYJEAAAAA==.',
En='Enimed:BAABLgAECn8yAAIeAAkJXRoQBAAJAgAeAAkJXRoQBAAJAgAAAA==.Ennio:BAAALgAECgYJBwAAAA==.Entropi:BAAALgADCgIJAgAAAA==.',
Er='Erzascarlet:BAAALgAECgUJCAAAAA==.',
Ev='Evil:BAABLgAECn8lAAQKAAgJixzCHwBUAQALAAcJvhdYVADKAQAKAAcJohTCHwBUAQAfAAIJURrQGAC0AAABLgAECgkJIwAUAKUgAA==.',
Ex='Exile:BAAALgADCgcJCQABLgADCgcJDwABAAAAAA==.',
Ey='Eyebite:BAAALgAFFAEJAQAAAA==.',
Fa='Faelinius:BAAALgAECgQJCQAAAA==.Farfik:BAAALgADCgYJBgABLgAECgQJBwABAAAAAA==.Fatherseph:BAAALgADCgkJEQABLgAECgQJCgABAAAAAA==.',
Fe='Feleyeza:BAAALgADCgEJAQABLgAECgYJBwABAAAAAA==.',
Fi='Finntastic:BAAALgADCgYJCAABLgAECgcJGwAeAFMVAA==.Finnthehuman:BAAALgAECgYJCQAAAA==.Fisterdobble:BAABLgAECn8tAAISAAkJmxVEGgAOAgASAAkJmxVEGgAOAgAAAA==.',
Fl='Fleurdelys:BAAALgADCgkJLQAAAA==.',
Fo='Forgeddemon:BAABLgAECn8WAAMXAAcJ6wmnRQArAQAXAAcJ6wmnRQArAQAgAAMJRgYQYgCHAAAAAA==.Forkinaround:BAAALgAECggJDAAAAA==.Fortune:BAAALgADCgYJBgAAAA==.',
Fr='Fralix:BAAALgAECgMJAwAAAA==.Frankiè:BAAALgAECgEJAQAAAA==.Fray:BAAALgADCgIJAgAAAA==.Frostbanshee:BAAALgADCgcJBwABLgAECgkJHwAhADkVAA==.Frostborne:BAAALgAECgcJDgAAAA==.Frostheart:BAABLgAECn8iAAIaAAgJ0x9fAwAuAgAaAAgJ0x9fAwAuAgAAAA==.Frostina:BAAALgAECgYJEgAAAA==.Frostmorne:BAAALgADCgEJAQAAAA==.Frostqueenie:BAAALgADCgEJAQAAAA==.',
Fu='Fullsend:BAAALgADCgcJCAAAAA==.Furionik:BAABLgAECn8YAAMTAAcJDRQzGACUAQATAAcJDRQzGACUAQAHAAEJuAsKpgA5AAAAAA==.',
Fw='Fweaky:BAAALgAECgEJAQAAAA==.',
['Fé']='Féannas:BAAALgAECgkJCAAAAA==.',
Ga='Galcian:BAAALgAECgYJEwAAAA==.Gamjee:BAAALgAECgQJCQAAAA==.',
Ge='Gellis:BAAALgADCgUJCAAAAA==.Gerkinmonk:BAAALgAECgQJBQAAAA==.',
Gh='Ghidorah:BAAALgADCgQJBAAAAA==.',
Gl='Glimmawitz:BAAALgADCgIJAgAAAA==.Glo:BAAALgAECgUJCAAAAA==.',
Gn='Gnomeater:BAAALgADCgMJAwAAAA==.',
Go='Goldeen:BAAALgAECgYJCQAAAA==.Goodolrúss:BAAALgADCgUJBQAAAA==.Goombas:BAAALgAECgUJBAAAAA==.',
Gr='Gr:BAAALgADCgYJBgAAAA==.Grackalackin:BAAALgAECgUJDwAAAA==.Grinnaux:BAAALgADCgMJAwAAAA==.Grounds:BAABLgAECn8aAAIiAAgJXSQUAgDoAgAiAAgJXSQUAgDoAgABLgAFFAEJAQABAAAAAA==.Grìffith:BAAALgAECgUJCAAAAA==.Grøtesk:BAAALgAECgYJBwAAAA==.',
Gu='Gulaj:BAAALgAECgYJDAAAAA==.Gumby:BAAALgADCgIJAgAAAA==.Gunbrawl:BAAALgADCgEJAgAAAA==.',
Ha='Havixsucks:BAABLgAECn8pAAQfAAgJlxMPAwCUAQALAAgJ0RFXRQD7AQAfAAcJGRIPAwCUAQAKAAQJ3AekIAA3AAAAAA==.',
He='Healgimp:BAABLgAECn8dAAIYAAgJxxRuEQCUAQAYAAgJxxRuEQCUAQAAAA==.Healslux:BAABLgAECn8XAAIRAAgJiR09CABWAgARAAgJiR09CABWAgAAAA==.',
Hi='Highmane:BAAALgAECgYJBwAAAA==.',
Ho='Holyshot:BAAALgADCgUJCAAAAA==.Hope:BAEALgAECgEJAQABLgAFFAYJCAAZAAMPAA==.Hortzel:BAAALgAECgQJCQAAAA==.Howdoiheal:BAAALgAECgcJDQAAAA==.',
Hu='Huntus:BAABLgAECn8tAAMJAAkJzh+GBQCgAgAJAAkJzh+GBQCgAgAIAAEJlQfYkQApAAAAAA==.',
Ia='Iamdownhere:BAABLgAECn8cAAIVAAgJGRbcGQDvAQAVAAgJGRbcGQDvAQAAAA==.',
Ic='Icy:BAAALgAECgEJAgAAAA==.',
Im='Immersa:BAABLgAECn8WAAMjAAgJTBabDQAAAgAjAAgJdhWbDQAAAgAOAAcJjxKGIgCqAQAAAA==.Impostor:BAABLgAECn8XAAIPAAkJHRuuAgCiAgAPAAkJHRuuAgCiAgAAAA==.',
In='Indabow:BAAALgAECggJEgAAAA==.Indamurim:BAABLgAECn8WAAMgAAgJJxKoKQCPAQAgAAcJTxCoKQCPAQAXAAcJcwzhPgBKAQAAAA==.Inzili:BAAALgAECgkJDgAAAA==.',
Is='Isaarek:BAABLgAECn8UAAIkAAgJihRPGQD7AQAkAAgJihRPGQD7AQAAAA==.',
Ja='Jabrick:BAABLgAECn8UAAMkAAgJvBhVEQBUAgAkAAgJvBhVEQBUAgAdAAEJdgUo6wAnAAAAAA==.Jakamu:BAAALgAECgUJDAAAAA==.Janim:BAAALgAECgUJBQAAAA==.Jattin:BAAALgADCgYJBgAAAA==.Jawnski:BAAALgAECggJDgAAAA==.Jay:BAAALgAECgMJAwAAAA==.',
Ji='Jibjabjibjab:BAACLgAFFH8GAAMCAAMJuhH0DQAGAQACAAMJuhH0DQAGAQAiAAEJBwfHBwBTAAAuAAQKfxUAAwIACAk8HPQhAOkBAAIABglfH/QhAOkBACIABAnmGMENAD8BAAAA.Jimm:BAACLgAFFH8RAAIXAAUJVwuVEAATAQAXAAUJVwuVEAATAQAuAAQKfyQAAhcACAnxElchAPcBABcACAnxElchAPcBAAAA.',
Ju='Judge:BAAALgAECgYJBgAAAA==.',
['Jì']='Jìm:BAAALgADCgIJAgABLgADCgYJBwABAAAAAA==.Jìmothy:BAAALgADCgYJBwAAAA==.',
Ka='Kailthosjr:BAAALgADCgEJAQAAAA==.Kazurtrin:BAAALgADCgMJAwAAAA==.',
Ke='Kelemvor:BAABLgAECn8fAAIdAAkJeh30FQDTAgAdAAkJeh30FQDTAgAAAA==.',
Kf='Kfp:BAAALgAECgQJBQAAAA==.',
Kh='Khandak:BAACLgAFFH8GAAIeAAMJARgtDADfAAAeAAMJARgtDADfAAAuAAQKfxUAAh4ACAnWGQAPABwCAB4ACAnWGQAPABwCAAAA.',
Ki='Kidslaps:BAABLgAECn8UAAIXAAYJIw19IwDpAAAXAAYJIw19IwDpAAAAAA==.',
Kj='Kjsockeye:BAAALgADCgkJEgAAAA==.',
Kl='Kleenex:BAAALgAECggJCwAAAA==.',
Kn='Knigamortis:BAAALgADCgUJBQAAAA==.',
Ko='Kordmoridden:BAAALgADCgYJBgAAAA==.Korìe:BAAALgADCgQJBAABLgADCgYJBwABAAAAAA==.',
Ku='Kurisutina:BAABLgAECn8fAAIhAAkJORWcIACuAQAhAAkJORWcIACuAQAAAA==.',
La='Lana:BAAALgAECgMJAwAAAA==.Laokenic:BAAALgAECgUJBwAAAA==.Lariat:BAAALgAECgYJBwAAAA==.',
Le='Leadblaster:BAAALgAECggJEwAAAA==.Leethalfu:BAAALgAECgQJBQAAAA==.Legosi:BAAALgAECgcJEwAAAA==.Lemegegen:BAAALgAECgkJEgAAAA==.',
Lh='Lhux:BAABLgAECn8oAAIJAAgJ3iHADADZAgAJAAgJ3iHADADZAgAAAA==.Lhuxi:BAAALgAECgQJCwABLgAECggJKAAJAN4hAA==.',
Li='Lidean:BAAALgAECgIJAwAAAA==.Lilbokchoy:BAAALgADCgcJDQAAAA==.Lillith:BAAALgADCgYJBgAAAA==.Linkolas:BAAALgAECgcJEAAAAA==.Liny:BAAALgAECgQJBAAAAA==.',
Lo='Locrian:BAAALgADCgEJAQAAAA==.Lohotaf:BAAALgADCgcJDQAAAA==.Lorgar:BAAALgAECgQJBAAAAA==.',
Lu='Luca:BAAALgAECgcJCQAAAA==.Luceean:BAAALgADCgcJDQAAAA==.Lucon:BAAALgAECgEJAgAAAA==.Lurth:BAAALgADCgYJBgAAAA==.Lurthshots:BAAALgAECgEJBAAAAA==.Luxmunkii:BAAALgAECgIJBAAAAA==.',
Ly='Lykaboops:BAAALgADCgcJEAABLgAECgkJLwAbAGMVAA==.Lyxxie:BAABLgAECn8qAAMDAAkJYxkxIgC7AQADAAkJYxkxIgC7AQAlAAEJQAZfGQApAAAAAA==.',
Ma='Magentic:BAABLgAECn8gAAISAAcJABlMMACiAQASAAcJABlMMACiAQAAAA==.Mageus:BAAALgADCgYJBQAAAA==.Maguar:BAAALgAECggJEQAAAA==.Manimadruid:BAAALgADCgMJAwAAAA==.Manimashaman:BAAALgADCgYJBgAAAA==.Marici:BAAALgADCgMJAwAAAA==.',
Me='Melith:BAAALgADCgkJEQAAAA==.Menyin:BAAALgAECgMJBAABLgAFFAIJBQAbADMZAA==.Metsutan:BAABLgAECn8yAAICAAkJvySLAAA9AwACAAkJvySLAAA9AwAAAA==.',
Mi='Milkystream:BAAALgAECgEJAgAAAA==.Mind:BAAALgAECgMJAwAAAA==.Mixlife:BAAALgADCgMJAwAAAA==.',
Mo='Moggle:BAABLgAECn8bAAMPAAgJKA6YEgBxAQAPAAcJ+g6YEgBxAQAYAAUJAggHYACyAAAAAA==.Moistfellow:BAABLgAECn8VAAISAAYJHxb/uwBqAQASAAYJHxb/uwBqAQAAAA==.Mokey:BAABLgAECn8YAAIfAAgJSSF9AgCWAgAfAAgJSSF9AgCWAgAAAA==.Molathom:BAAALgAECgIJAgAAAA==.Monktastic:BAAALgADCgYJCgABLgAECgcJIAASAAAZAA==.Moog:BAAALgADCgkJCQAAAA==.Moohealer:BAAALgAECgUJBwAAAA==.Moppit:BAAALgAECgEJAQAAAA==.Morvster:BAAALgAECgYJCwAAAA==.Moskeebee:BAABLgAECn8UAAIJAAcJyiUUEgCnAgAJAAcJyiUUEgCnAgAAAA==.',
Mu='Muxx:BAAALgADCgEJAQAAAA==.',
['Mâ']='Mâtthêw:BAAALgAECgQJCgAAAA==.',
['Mø']='Møløtøv:BAABLgAECn8UAAILAAYJ1wfD0QC2AAALAAYJ1wfD0QC2AAAAAA==.',
Na='Nazuresh:BAAALgAECgEJAQABLgAECgYJFQAYANUUAA==.',
Ne='Nekcrotic:BAABLgAECn8XAAMLAAYJ3iDxQwAAAgALAAYJ3iDxQwAAAgAKAAEJjAm9dQAvAAAAAA==.Nekromant:BAABLgAECn8nAAIKAAgJ4BhXAgDyAQAKAAgJ4BhXAgDyAQAAAA==.Nemriel:BAAALgAECgQJBQAAAA==.',
Ni='Nictus:BAABLgAECn8UAAMkAAcJaBVHIQCyAQAkAAYJfRhHIQCyAQAdAAYJkgqgPgDsAAAAAA==.Nirith:BAAALgAECgYJCwAAAA==.',
No='Nohric:BAAALgAECgUJBwAAAA==.Norsem:BAAALgAECgYJCwAAAA==.',
Nu='Numerion:BAAALgAECgMJAwAAAA==.Nutbutter:BAAALgADCgIJAgAAAA==.',
['Nä']='Nämeless:BAAALgAECgQJBAAAAA==.',
['Nî']='Nîghtraid:BAABLgAECn8nAAIZAAgJTCDtAwCbAgAZAAgJTCDtAwCbAgAAAA==.',
Oa='Oakenmoose:BAAALgADCgMJBQAAAA==.',
Od='Odinn:BAAALgAECgIJAgABLgAECgYJCwABAAAAAA==.',
Oh='Ohlorn:BAAALgAECgIJCQAAAA==.',
On='Oneth:BAAALgAECgQJCQAAAA==.Onfleek:BAABLgAECn8WAAMYAAYJayS0BwA0AgAYAAYJayS0BwA0AgAPAAYJNQk9NgA7AQAAAA==.',
Op='Ophiline:BAAALgADCgUJBQAAAA==.Ophiri:BAAALgAECgQJBAAAAA==.Opshammi:BAACLgAFFH8FAAIbAAIJMxmkHwCaAAAbAAIJMxmkHwCaAAAuAAQKfy4AAhsACAmHGpwoAO4BABsACAmHGpwoAO4BAAAA.',
Or='Orakrak:BAABLgAECn8dAAIHAAcJhgwYIQAtAQAHAAcJhgwYIQAtAQAAAA==.',
Oz='Ozzmodius:BAAALgADCgIJAwAAAA==.',
Pa='Pakapunch:BAAALgAECgIJAgAAAA==.Pallom:BAAALgAECgEJAgAAAA==.Parsera:BAAALgADCgEJAQABLgAECgkJKwAZABwlAA==.Parseus:BAAALgADCgYJBwABLgAECgkJKwAZABwlAA==.Parseval:BAABLgAECn8rAAQZAAkJHCU8AADJAwAZAAkJHCU8AADJAwAYAAQJPxsjQwAsAQAPAAEJGRO7PAA/AAAAAA==.Pawerful:BAAALgADCgYJBgABLgAECgkJMgAHAJ8lAA==.Paws:BAABLgAECn8yAAIHAAkJnyVmAABQAwAHAAkJnyVmAABQAwAAAA==.',
Pe='Perdi:BAAALgADCgQJBwAAAA==.Pettigrew:BAAALgAECgQJBAAAAA==.Peut:BAAALgAECgYJCwAAAA==.',
Ph='Physix:BAAALgAECgQJCQAAAA==.',
Pi='Pipsqueak:BAAALgADCgMJAwAAAA==.',
Po='Poedime:BAAALgAECgQJBQAAAA==.Popped:BAAALgAECgQJCgAAAA==.Porkins:BAABLgAECn8rAAMlAAkJpx2HAACsAgAlAAkJpx2HAACsAgAeAAYJvg0IJwAGAQAAAA==.Porkçhop:BAAALgAECgEJAgAAAA==.Potterpanda:BAAALgADCgQJBAAAAA==.Powerline:BAAALgAECgQJBQAAAA==.',
Pr='Priestus:BAAALgADCgkJCQAAAA==.Promised:BAAALgAECgMJAwABLgAFFAEJAQABAAAAAA==.',
Pt='Ptolemy:BAAALgAECgEJAQAAAA==.',
Py='Pyraxx:BAABLgAECn8lAAISAAkJYRznBwC7AgASAAkJYRznBwC7AgAAAA==.',
['Pê']='Pênny:BAAALgADCgEJAQABLgADCgYJBwABAAAAAA==.',
Qu='Quakezord:BAAALgADCgYJBgAAAA==.Quesofundido:BAAALgADCgEJAQAAAA==.Quillvo:BAAALgADCgkJCQAAAA==.',
Ra='Radovan:BAAALgAECgEJAQAAAA==.Ramipril:BAAALgADCgMJAwAAAA==.Ranestari:BAAALgADCgcJBgAAAA==.Ranlor:BAAALgADCgYJBgAAAA==.Raphorath:BAABLgAECn8UAAMdAAYJchKBNwAFAQAdAAYJDBGBNwAFAQAkAAIJWwyxXgBmAAAAAA==.Rareware:BAAALgADCgEJAQAAAA==.Rax:BAAALgADCgQJBAAAAA==.Raìdèn:BAABLgAECn8VAAMYAAYJ1RTKLgCIAQAYAAYJ1RTKLgCIAQAPAAQJ4QMgMgBxAAAAAA==.',
Re='Relsdruid:BAACLgAFFH8FAAIFAAIJixDWGACVAAAFAAIJixDWGACVAAAuAAQKfyAAAgUACAmwHagRAI0CAAUACAmwHagRAI0CAAAA.Replicate:BAAALgAECgEJBQAAAA==.Resisted:BAAALgAECgEJAQABLgAFFAUJDAAOAL4cAA==.Restocrayze:BAAALgAECgIJAgAAAA==.',
Ri='Rickets:BAAALgAECgIJAwAAAA==.',
Ro='Rookeria:BAAALgADCgYJBgAAAA==.Ropesale:BAAALgADCgEJAQAAAA==.Rosaelyia:BAAALgADCgQJBAABLgAECggJHAAJAPYXAA==.',
Ry='Ryanx:BAABLgAECn8kAAIRAAkJLCPeAACSAwARAAkJLCPeAACSAwAAAA==.Ryanxx:BAAALgAECgYJBgAAAA==.Ryri:BAAALgAECgcJEQAAAA==.',
Sa='Saatana:BAAALgAECggJEwAAAA==.Sahaquiel:BAAALgAECgEJAQAAAA==.Salife:BAAALgAECgEJAgAAAA==.Samavati:BAABLgAECn8cAAMhAAgJ5Q7ELgBDAQAhAAcJ0gzELgBDAQAXAAgJUgIoIwDsAAAAAA==.Sanddragon:BAAALgADCgcJDQAAAA==.Sands:BAAALgAECgcJCwAAAA==.Santoku:BAAALgAECgQJCQAAAA==.Sarah:BAABLgAECn8sAAIZAAkJMxttBACHAgAZAAkJMxttBACHAgAAAA==.Sassyface:BAABLgAECn8qAAIKAAkJPA2OAwC0AQAKAAkJPA2OAwC0AQAAAA==.Saveena:BAAALgAECgEJAQAAAA==.Saviq:BAAALgADCgEJAgAAAA==.',
Se='Seabolt:BAAALgAECgYJBgABLgAECggJIgAEAAMkAA==.Sebbyr:BAAALgADCgMJAwAAAA==.Sellit:BAAALgADCgEJAgAAAA==.',
Sh='Shadowdin:BAAALgAECgYJDwAAAA==.Shaduw:BAACLgAFFH8RAAITAAUJTR86AwBtAQATAAUJTR86AwBtAQAuAAQKfyQAAxMACAnOIbADABkDABMACAnOIbADABkDAAcACAkBDjwyAOMBAAAA.Shanalister:BAAALgADCgUJBQAAAA==.Shari:BAAALgAECgYJDgAAAA==.Shiklah:BAAALgAECgQJBAAAAA==.',
Si='Sibbrena:BAACLgAFFH8GAAIPAAMJKRafCwAEAQAPAAMJKRafCwAEAQAuAAQKfyYAAg8ACQkMHv4FAC4DAA8ACQkMHv4FAC4DAAAA.Sixpacksorc:BAABLgAECn8mAAISAAgJWiQnFQApAwASAAgJWiQnFQApAwAAAA==.',
Sk='Skn:BAABLgAECn8hAAMRAAgJnSPMEACMAgARAAgJnSPMEACMAgAVAAQJrBg8iwCUAAAAAA==.',
Sl='Slizzard:BAAALgAECgYJDgAAAA==.',
Sm='Smutty:BAAALgAECgYJCwAAAA==.',
Sn='Snackychan:BAAALgAECgcJEQAAAA==.Sniperdoom:BAAALgADCgYJBgAAAA==.',
So='Sourdiesal:BAAALgAECgUJBQAAAA==.',
Sp='Spleen:BAABLgAECn8UAAQiAAYJPRiNBQBmAQAiAAYJ1xWNBQBmAQACAAQJ9RiLPwAhAQAmAAEJMAiuDgAyAAAAAA==.Spywo:BAAALgAECgEJAQAAAA==.',
Sq='Squirrelydan:BAAALgAECgQJCAAAAA==.',
St='Stabbý:BAAALgAECgYJBgABLgADCgYJBwABAAAAAA==.Stabinem:BAAALgADCgcJAQAAAA==.Stardria:BAAALgADCgUJCQAAAA==.Stelthme:BAAALgAECgUJCwABLgAFFAMJBQACAOEMAA==.Stormburst:BAAALgADCgIJAgABLgAFFAEJAQABAAAAAA==.Strawberries:BAABLgAECn8bAAISAAcJQyFKOgCNAgASAAcJQyFKOgCNAgABLgAECggJFAAWAEAlAA==.',
Sw='Swan:BAAALgAECgIJBAABLgAFFAMJBwASAPcHAA==.Swoleyspirit:BAAALgAECgMJBQAAAA==.',
Ta='Takamura:BAABLgAECn8dAAITAAgJHh4ZAwBkAgATAAgJHh4ZAwBkAgAAAA==.Tarle:BAAALgAECgcJCgAAAA==.Tazath:BAABLgAECn8VAAMOAAkJXBfgCgDbAQAOAAkJXBfgCgDbAQAjAAEJ0wF6RAAkAAABLgAECgkJJAAUAOQkAA==.',
Te='Techsorcist:BAAALgAECgQJBQAAAA==.',
Th='Theory:BAABLgAECn8bAAIDAAYJWxWpQgA2AQADAAYJWxWpQgA2AQAAAA==.Thessali:BAAALgAECgYJCwAAAA==.Thiccen:BAAALgADCgEJAQABLgADCgIJAgABAAAAAA==.Thoranji:BAAALgAECgUJCAAAAA==.',
Ti='Tipz:BAAALgAECgUJBwAAAA==.Tism:BAAALgADCgYJBgAAAA==.Titanpanda:BAAALgAECgEJAQAAAA==.',
To='Tomjim:BAACLgAFFH8MAAMOAAUJvhxgCQBkAQAOAAUJvhxgCQBkAQAnAAIJbgfgEwCLAAAuAAQKfyQABA4ACAkCIAwLAMUCAA4ACAkCIAwLAMUCACcABwnkEBMdAJwBACMABglrCy4iABkBAAAA.',
Tr='Trashii:BAABLgAECn8fAAIWAAgJXxv8BgD7AQAWAAgJXxv8BgD7AQAAAA==.Treevive:BAABLgAECn8YAAIEAAgJmyBAHABaAgAEAAgJmyBAHABaAgAAAA==.Trenx:BAAALgAECgUJCAAAAA==.Trystan:BAABLgAECn8cAAIVAAYJxgrlVwAIAQAVAAYJxgrlVwAIAQAAAA==.',
Ts='Tsinga:BAAALgAECgYJCgAAAA==.',
Tu='Turl:BAAALgADCggJCAABLgAECgYJFwARAFkdAA==.Turlo:BAABLgAECn8XAAIRAAYJWR04LADVAQARAAYJWR04LADVAQAAAA==.',
Tw='Tweik:BAAALgADCgcJCAAAAA==.Twoglaives:BAAALgAECgMJBgABLgAECggJJQAmAHMbAA==.Twostep:BAABLgAECn8lAAImAAgJcxsVAwAsAgAmAAgJcxsVAwAsAgAAAA==.',
['Tø']='Tøm:BAACLgAFFH8KAAIVAAQJ7RzOBgB+AQAVAAQJ7RzOBgB+AQAuAAQKfyIAAhUABwmkJTwYANgCABUABwmkJTwYANgCAAAA.',
Ul='Ullirus:BAAALgADCgYJAwAAAA==.',
Un='Unbearable:BAAALgADCgYJBgAAAA==.Unbroken:BAAALgADCgEJAQAAAA==.Undergrowth:BAAALgAFFAEJAgAAAA==.Unshookable:BAABLgAECn8pAAIhAAkJXB0EBQCEAgAhAAkJXB0EBQCEAgAAAA==.',
Ur='Ursos:BAAALgAECgUJCQAAAA==.',
Uz='Uzume:BAAALgADCgEJAQAAAA==.',
Va='Valefor:BAAALgAECggJDQAAAA==.Vallatris:BAAALgAECgQJCQAAAA==.Valsande:BAAALgADCgkJFgAAAA==.Vargr:BAAALgADCgEJAQAAAA==.',
Ve='Velton:BAAALgADCgMJAwAAAA==.Vendnmachine:BAABLgAECn8XAAISAAYJvgomYQAZAQASAAYJvgomYQAZAQAAAA==.Vermaelen:BAAALgAECgcJDAAAAA==.',
Vh='Vhyk:BAAALgADCgYJBgAAAA==.',
Vi='Viviera:BAAALgADCgcJBwABLgAECgQJCgABAAAAAA==.',
Vo='Voidh:BAAALgAECgUJBQAAAA==.Voidlockus:BAAALgAECgEJAQAAAA==.',
Wa='Wargeezer:BAAALgAECgEJAgAAAA==.Wariuus:BAAALgADCgcJDgAAAA==.Watercupp:BAAALgAECgMJBAAAAA==.',
We='Wear:BAAALgAECgYJCwAAAA==.',
Wh='Whimsy:BAAALgADCgcJDwAAAA==.',
Wi='Wisewithpet:BAAALgAECgYJCQAAAA==.Wisheni:BAABLgAECn8ZAAIZAAcJiQ+hEgBpAQAZAAcJiQ+hEgBpAQAAAA==.',
Wr='Wrathofdolph:BAAALgAECgIJAgAAAA==.Wrexx:BAAALgAFFAEJAQAAAA==.',
Xy='Xyfin:BAABLgAECn8lAAIWAAkJxxmuAgB+AgAWAAkJxxmuAgB+AgAAAA==.',
Yo='Yoruichi:BAAALgADCgEJAQAAAA==.',
Yu='Yunalescah:BAAALgAECgMJAwAAAA==.Yuno:BAAALgAECgEJAQAAAA==.',
Za='Zaboo:BAABLgAECn8UAAQfAAYJviB8DABwAQAfAAQJByJ8DABwAQALAAUJch4tOwBCAQAKAAEJAABSYABOAAAAAA==.Zandramadas:BAABLgAECn8qAAMFAAkJMiDhHAAaAgAFAAcJMR7hHAAaAgAEAAgJqBlqLAD9AQAAAA==.Zaraline:BAABLgAECn8cAAIJAAgJ9hfRFQDjAQAJAAgJ9hfRFQDjAQAAAA==.Zarasha:BAAALgAECgQJBgAAAA==.',
Ze='Zeakz:BAAALgAECgEJAQAAAA==.Zemsta:BAAALgADCgEJAQAAAA==.Zephon:BAABLgAECn8bAAIDAAcJHhn2JwCdAQADAAcJHhn2JwCdAQAAAA==.Zerksees:BAAALgADCgMJAwAAAA==.',
Zi='Zinyak:BAAALgAECgQJCQAAAA==.Zithrax:BAAALgADCgYJBgAAAA==.',
Zo='Zoomiez:BAAALgAECggJEwAAAA==.',
Zu='Zumwalmilui:BAAALgAECgEJAgAAAA==.',
Zy='Zyyn:BAABLgAECn8gAAISAAgJPBq2MQCdAQASAAgJPBq2MQCdAQAAAA==.',
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
