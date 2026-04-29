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

local lookup = {'Rogue-Assassination','Hunter-BeastMastery','Hunter-Survival','Hunter-Marksmanship','Priest-Holy','DeathKnight-Frost','DeathKnight-Blood','Monk-Windwalker','Warrior-Fury','Paladin-Protection','Paladin-Retribution','DemonHunter-Devourer','Unknown-Unknown','DeathKnight-Unholy','Warlock-Destruction','Warlock-Affliction','Paladin-Holy','Druid-Restoration','Druid-Guardian','Mage-Frost','Monk-Mistweaver','Shaman-Elemental','Warlock-Demonology','DemonHunter-Havoc','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Warrior-Arms','Priest-Shadow','Priest-Discipline','Druid-Balance','DemonHunter-Vengeance','Shaman-Restoration','Mage-Arcane','Monk-Brewmaster','Rogue-Subtlety','Mage-Fire',}
local provider = {region='US',realm='Crushridge',name='US',type='weekly',zone=46,date='2026-04-24',data={Ac='Acheniris:BAAALgAECgUJBQAAAA==.',
Ad='Adeaino:BAAALgAECgEJAwAAAA==.Adrenaline:BAAALgAECgUJCAAAAA==.',
Ae='Aeviee:BAAALgADCgUJBgAAAA==.Aevisandra:BAAALgADCgEJAQAAAA==.',
Ag='Agrippa:BAABLgAECn8YAAIBAAcJjQ+QCQCjAQABAAcJjQ+QCQCjAQAAAA==.',
Ah='Ahndhrez:BAAALgAECgMJAgAAAA==.',
Ai='Aicton:BAAALgAECgIJAgAAAA==.Aidric:BAAALgAECgUJCgAAAA==.Aioli:BAABLgAECn8VAAQCAAgJIhxdRwCUAQADAAUJwR4gEQCwAQACAAYJ7hddRwCUAQAEAAUJcRoLSAAzAQAAAA==.Airwavez:BAAALgADCgMJBAAAAA==.',
Al='Alchemorph:BAAALgAECgUJCAAAAA==.Aldormu:BAAALgAECgYJDQAAAA==.Aliyah:BAEALgADCgIJAgABLgAECggJGwAFAIEaAA==.Allura:BAABLgAECn8dAAIFAAkJnhYJFgAsAgAFAAkJnhYJFgAsAgAAAA==.Altra:BAABLgAECn8hAAMGAAgJBhpVAgCfAgAGAAgJBhpVAgCfAgAHAAcJewNaKwDkAAAAAA==.',
Am='Amoeta:BAAALgAECgYJEwAAAA==.Amorma:BAAALgADCgcJDAAAAA==.Amzod:BAAALgAECgEJAQAAAA==.',
An='Andarian:BAAALgAECgYJCgAAAA==.Andor:BAAALgADCgIJAgAAAA==.Angelique:BAAALgAECgQJCgAAAA==.Angryapples:BAAALgAECgQJCQAAAA==.Antinous:BAABLgAECn8aAAIEAAYJRwxBSgApAQAEAAYJRwxBSgApAQAAAA==.',
Ar='Arcstorm:BAAALgADCgYJBgAAAA==.Arkimedez:BAAALgADCgMJAwAAAA==.',
As='Asomyrh:BAAALgAECgcJEwAAAA==.',
At='Atchilis:BAAALgADCgIJAgAAAA==.',
Au='Auliehealz:BAAALgADCgYJBgAAAA==.Aurial:BAAALgADCgEJAQAAAA==.',
Aw='Awakenrobin:BAABLgAECn8fAAIIAAgJLApnKgCKAQAIAAgJLApnKgCKAQAAAA==.',
Az='Azenith:BAAALgADCgQJBAAAAA==.Azzatec:BAAALgADCgcJBwAAAA==.',
Ba='Bahablast:BAAALgAECgEJAQAAAA==.Baklava:BAAALgAECgIJAgAAAA==.Bananer:BAABLgAECn8XAAIJAAcJyhNrNgDOAQAJAAcJyhNrNgDOAQAAAA==.Banonzarath:BAAALgAECgQJBwAAAA==.Banonzath:BAAALgAECgEJAQAAAA==.Banonzii:BAAALgADCgMJBQAAAA==.Barrysoetoro:BAAALgADCgYJBgAAAA==.Batfred:BAAALgADCgYJBgAAAA==.Batukhan:BAAALgAECgIJAgAAAA==.Baulie:BAAALgAECgQJBgAAAA==.',
Be='Beebler:BAAALgAECgUJBwAAAA==.Beebs:BAAALgADCgcJEQAAAA==.Beefstick:BAAALgADCgUJBQAAAA==.Bekroh:BAAALgADCgcJDgAAAA==.Bestt:BAAALgAECgQJBgAAAA==.Bewear:BAAALgADCgcJCgAAAA==.Bezerk:BAAALgADCgEJAQAAAA==.',
Bi='Biceps:BAAALgADCgEJAQAAAA==.Biggestpete:BAAALgAECgUJBQAAAA==.Bigknight:BAAALgADCgcJCgAAAA==.Bigolchungus:BAABLgAECn8dAAMKAAgJhBlsCQA7AgAKAAgJeBlsCQA7AgALAAQJRRZKMgDRAAAAAA==.Bigpapadots:BAAALgADCgYJBgAAAA==.Bippysmasher:BAABLgAECn8gAAIMAAkJhRA1GgAvAQAMAAkJhRA1GgAvAQAAAA==.Biridie:BAAALgAECgMJAwAAAA==.',
Bl='Blacblood:BAABLgAECn8bAAIGAAgJOBDLBQDSAQAGAAgJOBDLBQDSAQAAAA==.Blade:BAAALgADCgEJAQAAAA==.Blastemis:BAAALgAECgQJBQAAAA==.Blindweiss:BAAALgADCgcJBwAAAA==.Blinkies:BAAALgAECgYJCwAAAA==.Blinkster:BAAALgAECgEJBAAAAA==.',
Bn='Bnr:BAAALgADCgIJAgABLgADCggJEQANAAAAAA==.',
Bo='Bobby:BAAALgADCgEJAQAAAA==.Bontao:BAABLgAECn8fAAICAAgJ9CF3CAAKAwACAAgJ9CF3CAAKAwAAAA==.Borstenne:BAABLgAECn8hAAIOAAgJ+h+6AgCGAgAOAAgJ+h+6AgCGAgAAAA==.',
Br='Brake:BAACLgAFFH8FAAIOAAMJfAWgEQDhAAAOAAMJfAWgEQDhAAAuAAQKfyAAAg4ACAnXG+81AF8CAA4ACAnXG+81AF8CAAAA.Breseayaya:BAABLgAECn8hAAIMAAgJjCHOAwBcAgAMAAgJjCHOAwBcAgAAAA==.Breseshh:BAAALgAECgQJBAABLgAECggJIQAMAIwhAA==.Brickbeard:BAABLgAECn8ZAAMPAAgJ2gvqGQB9AQAPAAcJog3qGQB9AQAQAAcJngiIAgA0AQAAAA==.Brickbow:BAAALgADCgcJDQAAAA==.Brickette:BAAALgAECgYJBgABLgAFFAQJCQALAKIPAA==.Bricksquad:BAAALgAECgMJAwABLgAECggJEwANAAAAAA==.Brickthrow:BAACLgAFFH8JAAMLAAQJog8+DQBBAQALAAQJog8+DQBBAQARAAEJEgboGwBNAAAuAAQKfyYAAwsACAk0IgAnAIoCAAsABwkWIgAnAIoCABEABAnWA7Z4AJYAAAAA.',
Bu='Burgerburn:BAAALgADCgMJAgAAAA==.',
By='Bytheway:BAAALgAECgYJDQAAAA==.',
['Bä']='Bärett:BAAALgADCgcJDgAAAA==.',
Ca='Cadilak:BAABLgAECn8gAAMSAAgJmyKEAgCUAgASAAcJhCSEAgCUAgATAAEJSgGeNwAZAAAAAA==.Cadsune:BAAALgADCgUJBQAAAA==.Caelesti:BAAALgAECgMJAwAAAA==.Calledtowild:BAAALgADCgEJAQAAAA==.Campesino:BAAALgADCgYJCgAAAA==.',
Ch='Chamificador:BAAALgADCgYJBgAAAA==.Chard:BAAALgADCgcJCQAAAA==.Cherrÿ:BAAALgADCgQJBAAAAA==.Chowderhead:BAAALgAECgYJDgAAAA==.',
Ci='Cileb:BAABLgAECn8ZAAIUAAgJYyQVDgBVAwAUAAgJYyQVDgBVAwAAAA==.Civik:BAABLgAECn8iAAICAAcJ1yMGEwCfAgACAAcJ1yMGEwCfAgAAAA==.',
Cl='Cloosaun:BAAALgAECgYJDAABLgAECggJEwANAAAAAA==.',
Co='Coachstahp:BAAALgADCgcJBwAAAA==.Conchsniffer:BAABLgAECn8pAAILAAgJphp0EAChAQALAAgJphp0EAChAQAAAA==.Conrack:BAAALgADCgcJCQAAAA==.Coobs:BAAALgADCgcJCgAAAA==.Coppercrusad:BAAALgADCgEJAQABLgAECgkJHwAHAAkjAA==.Copperit:BAABLgAECn8fAAIHAAkJCSONAgBDAwAHAAkJCSONAgBDAwAAAA==.Cornburglar:BAABLgAECn8eAAIJAAgJ0iLxCQAQAwAJAAgJ0iLxCQAQAwAAAA==.Cowtaclysmic:BAAALgAECgYJDAAAAA==.',
Cr='Crackersz:BAAALgAECgcJEAAAAA==.Cranjis:BAABLgAECn8WAAIVAAgJAyH7BgDtAgAVAAgJAyH7BgDtAgAAAA==.Crazydemon:BAAALgAECgcJCwAAAA==.Crunchwrap:BAAALgAECgYJCwAAAA==.Crusaide:BAAALgADCgUJBQAAAA==.Cryola:BAAALgADCgEJAQAAAA==.',
Cu='Cursereflect:BAAALgAECgUJCgAAAA==.Curseus:BAAALgADCgUJBgAAAA==.',
Da='Damncats:BAAALgAECgYJEgAAAA==.Danielsboone:BAAALgAECgQJBAAAAA==.Darkangor:BAAALgADCgcJBwAAAA==.Darkansic:BAAALgADCgQJBAAAAA==.Darkmare:BAAALgAECgQJBQABLgAECggJGwAWAFscAA==.Darknemesis:BAAALgADCggJCQAAAA==.Dawnhaven:BAAALgADCgcJBgAAAA==.Daysubb:BAAALgADCgMJAwABLgAFFAQJCAAXAEMbAA==.',
De='Deadhippocow:BAAALgAECgUJCQAAAA==.Deathwavez:BAABLgAECn8WAAIOAAcJMBf8ZADFAQAOAAcJMBf8ZADFAQAAAA==.Decurse:BAAALgAECgYJEQAAAA==.Deldrin:BAAALgAECgYJDAAAAA==.Demona:BAABLgAECn8aAAMPAAgJ5RTxKQAaAQAXAAYJeRHobgCCAQAPAAQJ4BPxKQAaAQAAAA==.Demonix:BAAALgAECgYJDQAAAA==.Derptron:BAABLgAECn8aAAIUAAcJswwLHQBlAQAUAAcJswwLHQBlAQAAAA==.Devira:BAAALgAECgQJBAAAAA==.',
Di='Diisco:BAAALgADCgcJDgAAAA==.Dillydally:BAAALgAECgQJBAAAAA==.Dilutedret:BAAALgAECgYJCQAAAA==.Dinobrass:BAAALgAECgYJEgAAAA==.Dirtylöbster:BAACLgAFFH8IAAIUAAMJqxvPJwAUAQAUAAMJqxvPJwAUAQAuAAQKfyQAAhQACAkgJQ8CAMcCABQACAkgJQ8CAMcCAAAA.Disabel:BAAALgAECgUJDQAAAA==.Distracto:BAAALgAECgkJCQAAAA==.',
Dl='Dltdjr:BAAALgAECgQJBgABLgAECgYJCQANAAAAAA==.',
Do='Dochollíday:BAAALgADCgEJAQAAAA==.Doolittle:BAAALgAECgUJBwAAAA==.Dorose:BAAALgADCggJCQAAAA==.Doublepop:BAAALgAECgYJBgAAAA==.',
Dr='Drewmee:BAAALgAECgYJDQAAAA==.Dronar:BAAALgADCgEJAQABLgAECgcJCAANAAAAAA==.Drublood:BAAALgADCgEJAQABLgAECgYJDQANAAAAAA==.Drunkinmasta:BAAALgADCgYJBgABLgAECgkJIgALALscAA==.Drwut:BAAALgAECggJDQAAAA==.',
Du='Dune:BAAALgADCgcJBwAAAA==.Duwork:BAAALgAECgYJDQAAAA==.',
Ee='Eekany:BAAALgAECgMJAwAAAA==.',
El='Eladus:BAAALgAECgYJBgAAAA==.Elladon:BAAALgAECgEJAQAAAA==.Elmster:BAAALgAECgEJAgAAAA==.',
Em='Emblaze:BAAALgAECgYJCwAAAA==.',
En='Enhshaman:BAAALgAFFAMJAwAAAA==.',
Er='Eremith:BAAALgADCgEJAQAAAA==.',
Es='Essentials:BAAALgAECgMJBAAAAA==.',
Ev='Evacadrabra:BAAALgADCgUJBQAAAA==.',
Ez='Ezkal:BAACLgAFFH8FAAIOAAMJ8A/QDgABAQAOAAMJ8A/QDgABAQAuAAQKfx8AAg4ACQnsGZsYAOgCAA4ACQnsGZsYAOgCAAAA.',
Fa='Faithpasse:BAAALgAECgQJCQAAAA==.Falcorne:BAABLgAECn8UAAICAAYJDBl7MwDhAQACAAYJDBl7MwDhAQAAAA==.',
Fe='Felondar:BAABLgAECn8VAAMMAAYJxwWemwDhAAAMAAYJsASemwDhAAAYAAMJqQYxEgBaAAAAAA==.Ferarro:BAAALgAECgcJEgAAAA==.',
Fi='Finnadin:BAAALgADCggJCAAAAA==.Finns:BAAALgAECgYJDAAAAA==.Firalyn:BAAALgAECgYJDgAAAA==.Firulais:BAAALgAECgYJDQAAAA==.Fistobeef:BAAALgAECgEJAQAAAA==.',
Fl='Fleable:BAAALgADCgMJAwAAAA==.Flysky:BAACLgAFFH8JAAIZAAQJAxr4BwBrAQAZAAQJAxr4BwBrAQAuAAQKfyAABBkACAk9JIwCAEcDABkACAk9JIwCAEcDABoAAQkWHaBgADgAABsAAQl3DxJBAC4AAAAA.',
Fo='Foxsake:BAAALgAECgYJCQAAAA==.',
Fr='Freakmeout:BAAALgADCgkJEgAAAA==.Frostadin:BAAALgADCgEJAQAAAA==.Frostbones:BAAALgAECgQJBQAAAA==.Frostuss:BAAALgADCgUJBQAAAA==.',
Fu='Fur:BAAALgADCggJCAAAAA==.Future:BAAALgAECgUJCgAAAA==.Fuzzydeeps:BAAALgADCgQJBAAAAA==.',
Ga='Gabriella:BAAALgADCgQJBQAAAA==.Gallardo:BAAALgADCgUJBQABLgAECgUJDQANAAAAAA==.Galnannix:BAAALgAECgYJCwAAAA==.Gardrake:BAABLgAECn8aAAMZAAkJIw6iHQCWAQAZAAcJUQ+iHQCWAQAaAAkJoxUPCABrAQAAAA==.Gastapha:BAAALgAECgYJDQAAAA==.',
Ge='Gearth:BAAALgADCgMJAwAAAA==.Geel:BAABLgAECn8aAAMJAAgJVBIcMADvAQAJAAgJVBIcMADvAQAcAAEJAABzFwAAAAAAAA==.Gehennas:BAAALgAECggJEwAAAA==.Gereck:BAAALgADCgIJAgAAAA==.Gerthsham:BAAALgADCgUJBQAAAA==.',
Go='Goofykirby:BAAALgADCgcJFQAAAA==.Googoogagaa:BAACLgAFFH8HAAIdAAMJgwWCBgDJAAAdAAMJgwWCBgDJAAAuAAQKfzEAAx0ACQlYFzkEAN4BAB0ACAkpGDkEAN4BAAUABwnyEv0pAKIBAAAA.Gotlieb:BAAALgADCgEJAQAAAA==.',
Gr='Griffith:BAAALgADCgEJAgAAAA==.Grimghor:BAAALgADCgYJBgAAAA==.Groggasan:BAAALgADCgYJBgABLgADCgcJDQANAAAAAA==.Groggfather:BAAALgADCgcJDQAAAA==.Gronhal:BAAALgADCgMJAwAAAA==.Groundz:BAAALgADCgYJBgAAAA==.Grrahtahtah:BAACLgAFFH8PAAIEAAUJgBVHBwCnAQAEAAUJgBVHBwCnAQAuAAQKfxQAAgQABwkJJLERAKgCAAQABwkJJLERAKgCAAAA.Grävyy:BAAALgAECggJEAAAAA==.',
Gy='Gyrozug:BAAALgAECggJEwAAAA==.',
Ha='Hammerinfred:BAAALgADCgQJBgAAAA==.',
He='Healingisfun:BAAALgADCgcJCwAAAA==.Heeple:BAAALgAECgEJAgAAAA==.Helhunter:BAABLgAECn8bAAIMAAcJkxH0GgAqAQAMAAcJkxH0GgAqAQAAAA==.Hellock:BAAALgAECgIJAgAAAA==.',
Hi='Hippysmasher:BAAALgAECgIJAgAAAA==.',
Ho='Hohk:BAAALgAECgIJAgAAAA==.Holyhooters:BAABLgAECn8XAAILAAYJDx/XFAB6AQALAAYJDx/XFAB6AQAAAA==.Holypablo:BAAALgADCgcJDQABLgAECggJIQAeACAdAA==.Homefries:BAAALgADCgYJBgAAAA==.Honkytonk:BAABLgAECn8YAAMbAAgJKAs3IgAYAQAbAAYJ7Qk3IgAYAQAaAAcJcQmjOAATAQAAAA==.Honour:BAABLgAECn8ZAAILAAcJHhwERgASAgALAAcJHhwERgASAgAAAA==.',
Hr='Hrathdemon:BAABLgAECn8hAAIMAAgJMh3CBwD3AQAMAAgJMh3CBwD3AQAAAA==.Hrathid:BAAALgADCgUJDAABLgAECggJIQAMADIdAA==.',
Hu='Huntermik:BAAALgADCgcJBwAAAA==.Hupa:BAACLgAFFH8HAAILAAMJiiD6BQAvAQALAAMJiiD6BQAvAQAuAAQKfyMAAgsACAm3JbMFAHIDAAsACAm3JbMFAHIDAAAA.Husk:BAAALgADCgEJAQAAAA==.',
Ia='Iamheyo:BAAALgAECgcJDwAAAA==.',
Ib='Ibleedorange:BAAALgADCgkJDAAAAA==.',
Ic='Ickeetard:BAAALgAECgYJCgAAAA==.',
Id='Idiot:BAAALgADCgIJAgAAAA==.Idiotbreath:BAABLgAECn8lAAMaAAgJvR8QAQCSAgAaAAgJvR8QAQCSAgAbAAMJmQl3MACTAAAAAA==.',
Ie='Ieatcheeks:BAAALgADCgYJBgAAAA==.',
Ig='Iglooshocker:BAABLgAFFH8FAAIWAAMJewbGEQDbAAAWAAMJewbGEQDbAAAAAA==.',
Im='Immorlich:BAAALgADCgcJBwAAAA==.Imonaship:BAAALgADCgcJBwAAAA==.',
In='Infari:BAAALgADCgUJBQAAAA==.Inflexi:BAAALgAECggJDAAAAA==.Inky:BAAALgADCgYJBwAAAA==.',
Ip='Ipriest:BAAALgADCgYJBgAAAA==.',
Is='Is:BAAALgAECgQJCAAAAA==.',
It='Itsmagharszn:BAAALgADCgQJBAAAAA==.Itsthereaper:BAABLgAECn8lAAMSAAgJnR11AwBpAgASAAgJnR11AwBpAgAfAAgJnBo0FQBnAgAAAA==.',
Iv='Iver:BAAALgAECgEJAQAAAA==.',
Ja='Jangle:BAAALgADCgYJBwAAAA==.',
Jh='Jhana:BAAALgADCgIJAgABLgAECgMJAwANAAAAAA==.',
Jj='Jjooaacchhim:BAAALgADCgIJAgAAAA==.',
Jy='Jyve:BAABLgAECn8WAAICAAgJyBcgIgA5AgACAAgJyBcgIgA5AgAAAA==.',
Ka='Kairei:BAAALgAECgUJBwAAAA==.Kalda:BAAALgAECgEJAgAAAA==.Kalor:BAAALgADCgQJBAAAAA==.Kamadan:BAAALgAECgUJBQAAAA==.Kamanactali:BAAALgAECgUJBgAAAA==.Kaneko:BAAALgAECgUJCgABLgAFFAIJAgANAAAAAA==.Katalina:BAABLgAECn8XAAMYAAcJdgoLOAAlAQAYAAYJUwoLOAAlAQAgAAYJIQlYBgC/AAAAAA==.Kawer:BAAALgAECgQJBgAAAA==.',
Ke='Kelstormhoof:BAAALgADCgcJDgABLgADCggJCQANAAAAAA==.Kernel:BAAALgADCgUJCAABLgAECggJHgAJANIiAA==.',
Kh='Kham:BAABLgAECn8pAAIJAAgJfCEVAQCNAgAJAAgJfCEVAQCNAgAAAA==.',
Ki='Killmaim:BAABLgAECn8ZAAIJAAgJwRloIABPAgAJAAgJwRloIABPAgAAAA==.Kitsuko:BAABLgAECn8bAAMWAAgJqg6nCQBiAQAWAAgJqg6nCQBiAQAhAAcJpwnxSgBXAQAAAA==.',
Kl='Klais:BAAALgAECgQJBAAAAA==.',
Ku='Kuani:BAAALgADCgkJCQAAAA==.Kuraishin:BAAALgADCgcJBwABLgAFFAQJBwAUAEEUAA==.',
['Kë']='Këltön:BAAALgAECgEJAQAAAA==.',
La='Lazycouch:BAAALgADCgUJBQAAAA==.',
Le='Leadzorz:BAAALgAECgUJBwAAAA==.Leaok:BAAALgADCgEJAQAAAA==.Learingcentr:BAAALgAECgMJAwAAAA==.Lechuza:BAAALgADCgYJDAAAAA==.Leedaddydk:BAAALgAECgMJAwAAAA==.Leroyjenkins:BAABLgAECn8XAAIiAAcJ8BvrAgBVAgAiAAcJ8BvrAgBVAgAAAA==.Lesaelia:BAAALgADCgYJBgAAAA==.',
Li='Linø:BAAALgAECgEJAQAAAA==.Liv:BAAALgAECgMJBAAAAA==.Lizzymonk:BAABLgAECn8bAAIjAAgJWh8FBADpAQAjAAgJWh8FBADpAQAAAA==.',
Lo='Loa:BAAALgADCgYJBwAAAA==.Lockwerk:BAAALgAECgcJBQABLgAECgcJEAANAAAAAA==.',
Lu='Luckfist:BAAALgAECgYJCQABLgAECgcJFwAQANQjAA==.Luminouslexi:BAAALgADCgUJBwAAAA==.',
Ma='Macoub:BAAALgADCgIJAgABLgADCgcJCgANAAAAAA==.Macuahuitl:BAAALgADCgYJBgAAAA==.Maddog:BAAALgAECgYJDgAAAA==.Mageslayer:BAAALgAECgYJDQAAAA==.Magicichin:BAAALgADCgcJCgAAAA==.Magistaer:BAAALgADCgMJAwAAAA==.Magmanuts:BAAALgAECgUJBQABLgAECgYJBgANAAAAAA==.Manabuns:BAABLgAECn8VAAIUAAgJdROxZwAHAgAUAAgJdROxZwAHAgAAAA==.Mandrro:BAAALgADCgkJDAAAAA==.Marfa:BAABLgAECn8cAAILAAgJzhVJEQCZAQALAAgJzhVJEQCZAQAAAA==.Mathias:BAAALgAECgMJAwAAAA==.Mavrik:BAABLgAECn8VAAIJAAcJNQ9FEQAdAQAJAAcJNQ9FEQAdAQAAAA==.',
Mc='Mckay:BAAALgAECgYJCQAAAA==.Mckáy:BAAALgADCgYJBAAAAA==.Mckäy:BAAALgAECgQJBAAAAA==.Mckåy:BAAALgADCgQJBAAAAA==.',
Me='Meatmagic:BAABLgAECn8WAAIiAAYJgBIjCAB3AQAiAAYJgBIjCAB3AQAAAA==.Megapunk:BAAALgADCggJFQAAAA==.Mellmaan:BAAALgADCgMJAwAAAA==.Melys:BAAALgAECgYJBgAAAA==.Mercenar:BAAALgADCgEJAQAAAA==.Meteorite:BAAALgADCgkJEgAAAA==.Meudayr:BAAALgAECgcJCAAAAA==.Mevoker:BAAALgADCgcJBwAAAA==.',
Mi='Millarolly:BAAALgADCgUJBQAAAA==.Mindkawntrol:BAAALgAECgQJBAAAAA==.Mirari:BAABLgAECn8bAAIWAAgJWxyLBADfAQAWAAgJWxyLBADfAQAAAA==.',
Mo='Mojorisin:BAAALgAECgcJEwAAAA==.Moonchiken:BAAALgAECgEJAwAAAA==.Mooserohdah:BAAALgAECgIJAgAAAA==.Moozlock:BAABLgAECn8bAAIXAAgJmxAVSwDoAQAXAAgJmxAVSwDoAQAAAA==.Moscovio:BAAALgAECgYJBwAAAA==.Mosspaws:BAABLgAECn8lAAMSAAgJpiRjBgAmAwASAAgJpiRjBgAmAwAfAAQJXx/ACABlAQAAAA==.',
Mu='Murderinc:BAAALgADCgMJAwAAAA==.',
My='Myeyes:BAAALgAECgYJCgAAAA==.',
Na='Narfiy:BAAALgADCgEJAQAAAA==.',
Ni='Nickimihoj:BAAALgAECgQJBAAAAA==.',
Nm='Nme:BAABLgAECn8UAAIiAAYJVA9HCQBWAQAiAAYJVA9HCQBWAQAAAA==.',
No='Nocturnos:BAABLgAECn8aAAMXAAgJxh0UHQCnAgAXAAgJxh0UHQCnAgAQAAEJUB93LABGAAAAAA==.Noggin:BAABLgAECn8aAAIRAAgJeyTSAADpAgARAAgJeyTSAADpAgAAAA==.Nonform:BAABLgAECn8iAAMfAAgJxhjzBADIAQAfAAgJxhjzBADIAQASAAEJdAH46wAXAAAAAA==.Noodles:BAAALgADCgYJFAABLgAECgUJDQANAAAAAA==.Noskillidan:BAAALgADCgMJAwABLgAECgUJCQANAAAAAA==.Noxta:BAAALgAECgYJCAAAAA==.',
Nu='Numonixx:BAACLgAFFH8KAAIbAAQJ5Qe6AAAaAQAbAAQJ5Qe6AAAaAQAuAAQKfxwAAhsACAmEG6UJAEUCABsACAmEG6UJAEUCAAAA.Nutlessfred:BAAALgADCgYJBgAAAA==.',
Ny='Nymage:BAABLgAECn8hAAIUAAgJ0RIYEwCpAQAUAAgJ0RIYEwCpAQAAAA==.',
Oh='Ohnospiders:BAAALgAECgcJEQAAAA==.',
Ok='Okaerisan:BAAALgAECgUJCQAAAA==.',
Om='Omgbbqq:BAAALgAECgIJAgABLgAECggJIQACAFYkAA==.',
Oo='Oomi:BAAALgAECgEJAQAAAA==.',
Op='Ophil:BAAALgADCgMJAwAAAA==.',
Or='Orack:BAAALgAECgYJCQAAAA==.Orcrot:BAAALgAECgYJBgAAAA==.',
Ou='Outlast:BAABLgAECn8iAAILAAkJuxyvEQAEAwALAAkJuxyvEQAEAwAAAA==.',
Pa='Paants:BAAALgAECgYJEQAAAA==.Palonixx:BAAALgAECgEJAQAAAA==.Panblind:BAACLgAFFH8HAAIMAAQJcRReDAD7AAAMAAQJcRReDAD7AAAuAAQKfyYAAgwACAmRI4cQAPoCAAwACAmRI4cQAPoCAAAA.Parmigiano:BAAALgADCgEJAQABLgAECggJGQADAPMTAA==.Parms:BAABLgAECn8ZAAQDAAgJ8xPBAwC7AQADAAgJ4xHBAwC7AQAEAAYJhQwjTQAcAQACAAIJORANowCFAAAAAA==.',
Pe='Peanought:BAABLgAECn8aAAMGAAgJRBb/BQDJAQAGAAcJXBn/BQDJAQAOAAYJWAitvQAHAQAAAA==.Peidro:BAAALgAECgYJCgAAAA==.Pentacles:BAABLgAECn8kAAITAAgJnCIqAwDiAgATAAgJnCIqAwDiAgAAAA==.',
Pi='Pijak:BAAALgAECgUJBwAAAA==.',
Pl='Pleo:BAAALgAECgcJBwAAAA==.',
Po='Poah:BAABLgAFFH8GAAIjAAMJ3iTrCABGAQAjAAMJ3iTrCABGAQAAAA==.Poahsham:BAAALgAECgEJAgABLgAFFAMJBgAjAN4kAA==.Potatoes:BAABLgAECn8VAAMPAAgJBgiZHABpAQAPAAgJBgiZHABpAQAXAAIJCQIqFAE6AAAAAA==.',
Pr='Pruflas:BAAALgAECggJEQAAAA==.',
Ps='Psycodk:BAAALgAECgYJDwAAAA==.',
Pu='Pumpin:BAAALgAECgQJDgAAAA==.Purplemonstr:BAAALgADCgUJBQAAAA==.',
Qk='Qkn:BAAALgAECgIJAgAAAA==.',
Qu='Quickswipe:BAAALgAECgcJDAABLgAFFAQJCAAXAEMbAA==.',
Qx='Qx:BAAALgAECgIJAgAAAA==.',
Ra='Raballa:BAAALgADCgUJBQAAAA==.Rafraff:BAAALgADCgUJBQAAAA==.Ralee:BAAALgADCgIJAgAAAA==.Randomhero:BAAALgADCgkJCQAAAA==.Rannt:BAAALgADCgcJBwAAAA==.Rashek:BAAALgADCgEJAQAAAA==.Raynne:BAAALgAECgIJAgAAAA==.',
Re='Reaperjoe:BAAALgAECgMJAwAAAA==.Rehab:BAAALgAECgcJDgAAAA==.Rehna:BAAALgAECgYJBgABLgAECgkJHQAFAJ4WAA==.Rektributio:BAACLgAFFH8QAAILAAYJShwXAQCZAQALAAYJShwXAQCZAQAuAAQKfycAAgsACAkSJeQBALICAAsACAkSJeQBALICAAAA.Revalation:BAAALgAECgcJEgAAAA==.',
Rh='Rhisis:BAAALgADCgUJBQABLgAECgQJCgANAAAAAA==.Rhyss:BAAALgADCgkJCQAAAA==.',
Ri='Rigorpumpis:BAAALgAECgQJBQAAAA==.',
Ro='Roadblock:BAAALgAECgUJDQAAAA==.Roadtripsx:BAAALgAECgIJAgAAAA==.Roadtripxxds:BAAALgAECgEJAgAAAA==.Roboorc:BAAALgADCgEJAQAAAA==.Rottingslow:BAAALgAECgEJAgABLgAFFAYJDQAHAH0hAA==.',
Sa='Saragos:BAAALgADCgcJBgABLgAFFAQJBwAUAEEUAA==.Saucerdote:BAAALgAECgcJDwAAAA==.',
Sc='Schnee:BAAALgADCgYJBgAAAA==.',
Se='Selinfinite:BAAALgAECgcJDAAAAA==.Selkie:BAAALgAECgYJDwAAAA==.',
Sh='Shambeau:BAAALgADCgQJBAAAAA==.Shamshielder:BAAALgAECgcJEQABLgAFFAMJBQAWAHsGAA==.Sharick:BAAALgAECgEJAQAAAA==.Shawlee:BAABLgAECn8eAAMhAAcJxBGBEQAuAQAhAAcJxBGBEQAuAQAWAAUJIwZFXgDKAAAAAA==.Sheezie:BAAALgAECgYJEQAAAA==.Shellter:BAAALgAECgEJAQABLgAECgYJCwANAAAAAA==.Shellwit:BAAALgAECgMJBgABLgAECgYJCwANAAAAAA==.Shetmage:BAACLgAFFH8IAAIUAAQJxgfKIwAoAQAUAAQJxgfKIwAoAQAuAAQKfxwAAhQACAkSH7YqAMgCABQACAkSH7YqAMgCAAAA.Shettrah:BAAALgAECgYJBgABLgAFFAQJCAAUAMYHAA==.Shockybalboa:BAAALgADCgcJBwAAAA==.Shorttbuss:BAAALgAECgYJDAAAAA==.Shunsui:BAAALgAECgEJAQAAAA==.',
Si='Siickboy:BAAALgAECgEJAgAAAA==.Sijious:BAAALgAECgEJAQAAAA==.Simperhi:BAAALgAECgEJAQAAAA==.',
Sk='Skora:BAAALgADCgIJAgABLgAECggJHAALAM4VAA==.Skyland:BAAALgADCgcJDQAAAA==.Skyli:BAAALgAECgUJCAABLgAECgkJEwANAAAAAA==.',
Sl='Slush:BAAALgAECgIJAgAAAA==.',
Sn='Snuph:BAAALgAECgQJCgAAAA==.',
So='Somi:BAABLgAECn8gAAIRAAgJWCCeAQCkAgARAAgJWCCeAQCkAgAAAA==.Sorrie:BAAALgAECgEJAQAAAA==.',
Sp='Spud:BAAALgADCgcJBwAAAA==.Spyroh:BAABLgAECn8bAAQaAAYJzxKECgA8AQAbAAYJcBDkGQBlAQAaAAUJ/BGECgA8AQAZAAEJ2wAkTwAeAAAAAA==.',
Ss='Ssohl:BAAALgAECgUJDgABLgAECgkJHQAFAJ4WAA==.',
St='Stankydk:BAACLgAFFH8IAAIOAAQJPBFYGgA8AQAOAAQJPBFYGgA8AQAuAAQKfyUAAg4ACAlXIH4nAJ0CAA4ACAlXIH4nAJ0CAAAA.Stankyleg:BAAALgADCgcJDQAAAA==.Stankymage:BAAALgADCgUJBAAAAA==.Steakhead:BAAALgAECgEJAQAAAA==.Stinkbombs:BAAALgAFFAMJAwAAAA==.Stinkerz:BAAALgAECgIJAgABLgAECgYJCwANAAAAAA==.Stunanddone:BAAALgAECgQJBwAAAA==.',
Su='Sumdragon:BAAALgADCgEJAQAAAA==.Sunlest:BAAALgADCgcJCQAAAA==.Supreme:BAABLgAECn8bAAIMAAgJnCJsGADDAgAMAAgJnCJsGADDAgAAAA==.',
Sw='Swaayshooter:BAAALgAECgUJBQABLgAECgcJGwAkAFscAA==.',
Sy='Sydios:BAAALgADCgUJBQABLgAFFAQJCgAFAFYOAA==.Sylphrena:BAABLgAECn8gAAIFAAgJKCCNCADDAgAFAAgJKCCNCADDAgAAAA==.',
['Sí']='Sínful:BAABLgAECn8XAAIEAAcJ4RtYAgC0AQAEAAcJ4RtYAgC0AQAAAA==.',
Ta='Tahwe:BAAALgADCgcJBwAAAA==.Talethen:BAAALgAECgYJEQAAAA==.Talla:BAAALgAECgkJEwAAAA==.Tammey:BAAALgADCgcJBwAAAA==.',
Te='Telaragehoof:BAAALgADCgkJHQAAAA==.Tellus:BAAALgADCgEJAQAAAA==.Tewshort:BAAALgAECgQJCQABLgAECgkJIgALALscAA==.',
Th='Thatbox:BAAALgAECgEJAQAAAA==.Thdon:BAAALgADCgIJAgAAAA==.Thedrood:BAAALgAECgQJCAAAAA==.Themlgyeet:BAAALgADCgEJAQAAAA==.Thiccfists:BAAALgAECgcJEgAAAA==.Thorfyna:BAAALgAECgYJEQAAAA==.Threzk:BAABLgAECn8dAAIPAAgJSw6fAgBeAQAPAAgJSw6fAgBeAQAAAA==.Thunderclap:BAAALgADCgIJAgAAAA==.',
Ti='Tiderias:BAAALgAECgEJAQAAAA==.',
To='Toekin:BAAALgAECgUJBQAAAA==.Tohk:BAACLgAFFH8JAAIMAAMJJxblDAD2AAAMAAMJJxblDAD2AAAuAAQKfyUAAgwACAktJMMSAOkCAAwACAktJMMSAOkCAAAA.Tontiamat:BAABLgAECn8bAAMaAAgJVg6vCQBLAQAaAAgJVg6vCQBLAQAbAAYJawoxIAAsAQAAAA==.Tontier:BAAALgAECgMJAwABLgAECggJGwAaAFYOAA==.Totembeans:BAAALgAECgQJCwAAAA==.',
Tr='Tralidoris:BAAALgADCgEJAQAAAA==.Trashen:BAAALgAECgYJBgABLgAFFAQJCgAFAFYOAA==.Trashfire:BAACLgAFFH8KAAMFAAQJVg77AQBAAQAFAAQJVg77AQBAAQAeAAIJwgFvFgB7AAAuAAQKfx0ABAUACAkWHSIQAGUCAAUACAkWHSIQAGUCAB0ABQknFWw2ADkBAB4AAwluEWNAAK0AAAAA.Treeple:BAAALgAECgYJEQAAAA==.Treily:BAAALgAECgEJAgAAAA==.Tresleches:BAAALgAECgYJEQAAAA==.Tricket:BAABLgAECn8aAAMcAAgJbhfqBgBWAgAcAAgJCRfqBgBWAgAJAAUJfxlAVQBWAQAAAA==.Trousers:BAAALgAECgYJBgABLgAECggJFQAPAAYIAQ==.Truestorm:BAABLgAECn8XAAILAAYJSQs+JgANAQALAAYJSQs+JgANAQAAAA==.Truheals:BAAALgADCgcJEAAAAA==.',
Tu='Tuchi:BAACLgAFFH8NAAIUAAUJzBdIBwBmAQAUAAUJzBdIBwBmAQAuAAQKfxwAAxQABwliIrQyAKgCABQABwliIrQyAKgCACIAAglBBa0YAFMAAAAA.Tussin:BAAALgADCgEJAQAAAA==.',
Tw='Tweedlepan:BAAALgADCgcJDQABLgAFFAQJBwAMAHEUAA==.',
['Tà']='Tàcobelle:BAAALgADCgYJBwABLgAECggJFQAUAHUTAA==.',
Up='Uptownpimp:BAAALgAECgEJAgAAAA==.',
Va='Valandral:BAAALgADCgEJAQAAAA==.Valdor:BAAALgADCgEJAQABLgAECgIJAgANAAAAAA==.Valyarn:BAAALgADCgcJBwAAAA==.Vanicton:BAACLgAFFH8FAAIhAAIJ2SCZFAC1AAAhAAIJ2SCZFAC1AAAuAAQKfyUAAyEACAmGHUUSAIQCACEACAmGHUUSAIQCABYAAwm+G4URAPkAAAAA.Varanis:BAACLgAFFH8GAAICAAMJlhZqDAD/AAACAAMJlhZqDAD/AAAuAAQKfxcAAgIACAkLImYLAOgCAAIACAkLImYLAOgCAAAA.',
Ve='Vegh:BAABLgAECn8dAAIgAAgJjxnNBABoAgAgAAgJjxnNBABoAgAAAA==.Vem:BAAALgAECgcJEwAAAA==.Veriale:BAAALgAECgUJBQAAAA==.Verra:BAAALgAECgYJCwAAAA==.',
Vi='Vitriol:BAAALgAECgYJEAAAAA==.',
Vo='Voidbeaver:BAAALgADCgIJAgAAAA==.Voidfent:BAAALgADCgEJAQAAAA==.Voidluck:BAABLgAECn8XAAIQAAcJ1COrAQDKAgAQAAcJ1COrAQDKAgAAAA==.',
Vy='Vynlaeron:BAAALgADCgkJCQABLgAECgYJBgANAAAAAA==.Vyrros:BAAALgADCgUJBQAAAA==.',
Wa='Walji:BAABLgAECn8cAAMhAAgJBBp5FwBaAgAhAAgJBBp5FwBaAgAWAAEJVQsQKQAyAAAAAA==.Wampa:BAAALgADCgcJDgAAAA==.Wanderblue:BAAALgADCgQJBQAAAA==.Wandy:BAABLgAECn8eAAIXAAcJVxB/aQCQAQAXAAcJVxB/aQCQAQAAAA==.Wangstah:BAAALgAECgcJEAAAAA==.Warblades:BAAALgADCgEJAQAAAA==.Wargloves:BAABLgAECn8bAAIJAAYJMRTjDwAuAQAJAAYJMRTjDwAuAQAAAA==.Warmslippers:BAAALgAECgYJCgAAAA==.Wataa:BAAALgADCgQJBAAAAA==.Wavez:BAAALgAECgcJCAAAAA==.Wawatési:BAAALgAECgMJAwAAAA==.Waytogoteam:BAABLgAECn8hAAICAAgJViQLAQDQAgACAAgJViQLAQDQAgAAAA==.',
We='Weeabooster:BAAALgAECgUJCQAAAA==.Weiss:BAACLgAFFH8HAAIUAAQJQRTyKwAGAQAUAAQJQRTyKwAGAQAuAAQKfyYABBQACAliJAUZABUDABQACAnTIwUZABUDACUABQnNI34DANkBACIAAQmPIMcWAGQAAAAA.Werkz:BAAALgAECgEJAQAAAA==.',
Wi='Wigglebee:BAAALgAECgEJAQAAAA==.',
Wo='Woodyy:BAAALgAECgkJAwAAAA==.Wox:BAAALgADCgkJDAAAAA==.',
Wr='Wreckfest:BAAALgADCgcJCwAAAA==.',
Wy='Wyldspirit:BAAALgAECgQJBAAAAA==.Wyreless:BAAALgADCgYJBgABLgAECgYJEwANAAAAAA==.',
['Wê']='Wêsleypipes:BAAALgADCgYJBwAAAA==.',
Xa='Xampu:BAAALgADCgEJAQAAAA==.',
Ye='Yem:BAACLgAFFH8IAAMXAAQJQxuOCgAiAQAXAAMJHR2OCgAiAQAPAAEJtBUhBABeAAAuAAQKfzIAAw8ACQnYIjYGAGwCAA8ABgncIzYGAGwCABcABglUIlNJAO4BAAAA.',
Yo='Yoshikawa:BAABLgAECn8YAAITAAcJvxmzCAAfAgATAAcJvxmzCAAfAgABLgAFFAIJAgANAAAAAA==.',
Za='Zamoxis:BAAALgAECgMJAwAAAA==.Zant:BAAALgAECgEJAQABLgAECgMJAwANAAAAAA==.Zanzabar:BAAALgAECggJDgAAAA==.Zaraelitha:BAAALgAECgEJAQAAAA==.Zawmbee:BAAALgADCgEJAQAAAA==.',
Ze='Zeldá:BAAALgAECgMJAwAAAA==.Zeodrik:BAAALgAECgYJDwAAAA==.',
Zh='Zhenya:BAABLgAECn8fAAMUAAcJ6Rv8GAB/AQAUAAcJ6Rv8GAB/AQAiAAQJLw/nDgDVAAAAAA==.',
Zi='Zidguard:BAAALgAECgYJBwAAAA==.Zigzauer:BAAALgAECgQJBAAAAA==.Ziroken:BAAALgADCgUJBQAAAA==.',
Zo='Zombeaver:BAAALgADCgcJCgAAAA==.',
['Ña']='Ñajana:BAAALgADCgcJCAAAAA==.',
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
