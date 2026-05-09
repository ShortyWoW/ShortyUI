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

local lookup = {'Rogue-Assassination','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Evoker-Devastation','Priest-Holy','DeathKnight-Frost','DeathKnight-Blood','Druid-Feral','Druid-Guardian','Paladin-Holy','Monk-Windwalker','Warrior-Fury','Paladin-Protection','Paladin-Retribution','DemonHunter-Devourer','Mage-Frost','Mage-Fire','Unknown-Unknown','DeathKnight-Unholy','Warlock-Affliction','Warlock-Destruction','Priest-Shadow','Druid-Restoration','Monk-Mistweaver','Druid-Balance','Warlock-Demonology','Shaman-Elemental','DemonHunter-Havoc','Evoker-Preservation','Evoker-Augmentation','Warrior-Arms','Priest-Discipline','DemonHunter-Vengeance','Shaman-Restoration','Mage-Arcane','Monk-Brewmaster','Rogue-Subtlety','Warrior-Protection','Shaman-Enhancement',}
local provider = {region='US',realm='Crushridge',name='US',type='weekly',zone=46,date='2026-05-08',data={Ac='Acheniris:BAAALgAECgUJCgAAAA==.',
Ad='Adeaino:BAAALgAECgEJAwAAAA==.Adrenaline:BAAALgAECgUJCAAAAA==.',
Ae='Aeviee:BAAALgADCgUJBgAAAA==.Aevisandra:BAAALgADCgIJAgAAAA==.',
Ag='Agrippa:BAABLgAECn8bAAIBAAcJjQ+OCQCjAQABAAcJjQ+OCQCjAQAAAA==.',
Ah='Ahndhrez:BAAALgAECgQJAwAAAA==.',
Ai='Aicton:BAAALgAECgIJAgAAAA==.Aidric:BAAALgAECgUJCgAAAA==.Aioli:BAABLgAECn8cAAQCAAkJDxpsDwCyAQACAAkJ9BZsDwCyAQADAAYJ7hdVRwCUAQAEAAUJcRouSAAzAQAAAA==.Airwavez:BAAALgAECgcJBwAAAA==.',
Al='Alchemorph:BAAALgAECgYJDgAAAA==.Aldormu:BAABLgAECn8VAAIFAAcJkgrKCQAFAQAFAAcJkgrKCQAFAQAAAA==.Aliyah:BAEALgADCgIJAgABLgAECggJIwAGAJkbAA==.Allura:BAACLgAFFH8KAAIGAAMJ0BUcEADSAAAGAAMJ0BUcEADSAAAuAAQKfx8AAgYACQkFFwwWACwCAAYACQkFFwwWACwCAAAA.Altra:BAACLgAFFH8HAAIHAAMJKwrVBADfAAAHAAMJKwrVBADfAAAuAAQKfyYAAwcACAkoG1YCAJ8CAAcACAkoG1YCAJ8CAAgABwl7A1YrAOQAAAAA.Alyvia:BAAALgADCgEJAgAAAA==.',
Am='Amoeta:BAABLgAECn8jAAMJAAgJqBOABwC/AQAJAAgJjhKABwC/AQAKAAcJEg/VDwAKAQAAAA==.Amorma:BAAALgADCgcJDAAAAA==.Amzod:BAAALgAECgMJAwAAAA==.',
An='Andarian:BAAALgAECgYJCgAAAA==.Andor:BAAALgADCggJCgAAAA==.Angelique:BAAALgAECgQJCgAAAA==.Angryapples:BAAALgAECgQJCQAAAA==.Antinous:BAABLgAECn8mAAIEAAYJeQ/RDgAAAQAEAAYJeQ/RDgAAAQAAAA==.',
Ar='Arcstorm:BAAALgAECgQJBAAAAA==.Arkimedez:BAAALgADCgMJAwAAAA==.',
As='Ashenback:BAAALgAECgUJBQABLgAFFAUJCQALAAkNAA==.Asomyrh:BAABLgAECn8aAAILAAkJphBZOwCMAQALAAkJphBZOwCMAQAAAA==.',
At='Atchilis:BAAALgADCgIJAgAAAA==.Atrophy:BAAALgAECgUJBgAAAA==.',
Au='Auliehealz:BAAALgADCgYJBgAAAA==.Aurial:BAAALgADCgEJAQAAAA==.',
Aw='Awakenrobin:BAABLgAECn8iAAIMAAgJLApmKgCKAQAMAAgJLApmKgCKAQAAAA==.',
Az='Azenith:BAAALgAECgYJEAAAAA==.Azzatec:BAAALgADCgcJBwAAAA==.',
Ba='Bahablast:BAAALgAECgEJAQAAAA==.Bakan:BAAALgADCgEJAQAAAA==.Baklava:BAAALgAECgIJAgAAAA==.Bananer:BAABLgAECn8iAAINAAkJeRTRCgA7AgANAAkJeRTRCgA7AgAAAA==.Banonzarath:BAAALgAECgQJBwAAAA==.Banonzath:BAAALgAECgEJAQAAAA==.Banonzii:BAAALgADCgMJBQAAAA==.Barrysoetoro:BAAALgADCgYJBgAAAA==.Batfred:BAAALgADCgYJBwAAAA==.Batukhan:BAAALgAECggJCgAAAA==.Baulie:BAAALgAECgQJBgAAAA==.',
Be='Beebler:BAAALgAECgcJEwAAAA==.Beebs:BAAALgADCgcJFwAAAA==.Beefstick:BAAALgADCgUJBQAAAA==.Bekroh:BAAALgADCgcJDgAAAA==.Bestt:BAAALgAECgQJBwAAAA==.Bewear:BAAALgADCgcJCgAAAA==.Bezerk:BAAALgADCgEJAQAAAA==.',
Bi='Biceps:BAAALgADCgEJAQAAAA==.Biggestpete:BAAALgAECgUJBgAAAA==.Bigknight:BAAALgADCgcJCgAAAA==.Bigolchungus:BAABLgAECn8dAAMOAAgJhBlrCQA7AgAOAAgJeBlrCQA7AgAPAAQJRRawlQDDAAAAAA==.Bigpapadots:BAAALgADCgYJBgAAAA==.Bippysmasher:BAABLgAECn8kAAIQAAkJIRJJIADHAQAQAAkJIRJJIADHAQAAAA==.Biridie:BAAALgAECgUJCgAAAA==.',
Bl='Blacblood:BAABLgAECn8eAAIHAAgJuhGCBQB3AQAHAAgJuhGCBQB3AQAAAA==.Blade:BAAALgADCgEJAQAAAA==.Blastemis:BAAALgAECgcJDgAAAA==.Bliccy:BAAALgAECgQJCAAAAA==.Blindweiss:BAAALgADCgcJBwABLgAFFAQJDQARAE4YAA==.Blinkies:BAABLgAECn8YAAMSAAcJPRyOAQD0AQASAAcJPRyOAQD0AQARAAUJlg9RcAAwAQAAAA==.Blinkster:BAAALgAECgEJBAAAAA==.',
Bn='Bnr:BAAALgADCgIJAgABLgAECgMJAwATAAAAAA==.',
Bo='Bobby:BAAALgADCgEJAQAAAA==.Bontao:BAACLgAFFH8JAAIDAAUJLB2NCgBwAQADAAUJLB2NCgBwAQAuAAQKfyIAAgMACQn7IXcIAAoDAAMACQn7IXcIAAoDAAAA.Borstenne:BAACLgAFFH8GAAIUAAMJqRsjQAARAQAUAAMJqRsjQAARAQAuAAQKfyYAAhQACAn8H38TAAYDABQACAn8H38TAAYDAAAA.',
Br='Brake:BAACLgAFFH8HAAIUAAMJEg1VVgDfAAAUAAMJEg1VVgDfAAAuAAQKfyMAAhQACAlEHmseABICABQACAlEHmseABICAAAA.Brese:BAAALgAECgIJAgABLgAFFAMJBwAQAAcaAQ==.Breseayaya:BAACLgAFFH8HAAIQAAMJBxreKwACAQAQAAMJBxreKwACAQAuAAQKfyYAAhAACAmTIdwLACIDABAACAmTIdwLACIDAAAA.Breseshh:BAAALgAECgYJDAABLgAFFAMJBwAQAAcaAA==.Brickbeard:BAABLgAECn8hAAMVAAgJRhCOBQBsAQAWAAcJog3kGQB9AQAVAAcJfRKOBQBsAQAAAA==.Brickbow:BAAALgADCgcJDQAAAA==.Brickette:BAAALgAECgYJEgABLgAFFAUJDwAPAOoXAA==.Bricksquad:BAAALgAECgMJAwABLgAECggJEwATAAAAAA==.Brickthrow:BAACLgAFFH8PAAMPAAUJ6hfVEgBbAQAPAAUJ6hfVEgBbAQALAAEJEgbyGwBNAAAuAAQKfyoAAw8ACQnBIfwmAIoCAA8ACAmYIfwmAIoCAAsABQlyBJJJAIAAAAAA.',
Bu='Burgerburn:BAAALgADCgYJBwAAAA==.',
By='Bytheway:BAABLgAECn8UAAIXAAcJoxOfHABXAQAXAAcJoxOfHABXAQAAAA==.',
['Bä']='Bärett:BAAALgADCgcJDgAAAA==.',
Ca='Cadilak:BAACLgAFFH8HAAIYAAMJ7BPQHwDbAAAYAAMJ7BPQHwDbAAAuAAQKfyUAAxgACAmkIiUOAMgCABgABwmOJCUOAMgCAAoAAQlKAac3ABkAAAAA.Cadsune:BAAALgAECgEJAQAAAA==.Caelesti:BAAALgAECgUJDAAAAA==.Calledtowild:BAAALgADCgEJAQAAAA==.Campesino:BAAALgAECgIJAQAAAA==.',
Ch='Chamificador:BAAALgADCgYJBgAAAA==.Chard:BAAALgADCgcJCQAAAA==.Cherrÿ:BAAALgADCgQJBAAAAA==.Chinbearpig:BAAALgADCgEJAQAAAA==.Chowderhead:BAABLgAECn8UAAIWAAYJYRzhDgDcAQAWAAYJYRzhDgDcAQAAAA==.',
Ci='Cileb:BAACLgAFFH8FAAIRAAUJcxfqKQBVAQARAAUJcxfqKQBVAQAuAAQKfyAAAhEACQlnIxoOAFUDABEACQlnIxoOAFUDAAAA.Civik:BAABLgAECn8vAAIDAAkJriGbBgDIAgADAAkJriGbBgDIAgAAAA==.',
Cl='Cloosaun:BAAALgAECgYJDAABLgAECggJEwATAAAAAA==.',
Co='Coachstahp:BAAALgADCgcJBwAAAA==.Conchsniffer:BAACLgAFFH8FAAIPAAQJkQQoLQD9AAAPAAQJkQQoLQD9AAAuAAQKfzAAAg8ACQlZGgsUAFoCAA8ACQlZGgsUAFoCAAAA.Conrack:BAAALgADCgcJDQAAAA==.Coobs:BAAALgADCgcJCgABLgAECgUJCgATAAAAAA==.Coppercrusad:BAAALgADCgEJAQABLgAECgkJJwAIAAkjAA==.Copperit:BAABLgAECn8nAAIIAAkJCSNiAQAJAwAIAAkJCSNiAQAJAwAAAA==.Cornburglar:BAABLgAECn8rAAINAAgJVyQjBQCnAgANAAgJVyQjBQCnAgAAAA==.Cowtaclysmic:BAAALgAECgYJEgAAAA==.',
Cr='Crackersz:BAAALgAFFAEJAQAAAA==.Cranjis:BAABLgAECn8mAAIZAAkJniC8AgAfAwAZAAkJniC8AgAfAwAAAA==.Crazydemon:BAAALgAECgcJCwAAAA==.Crazylock:BAAALgAECgEJAQAAAA==.Crunchwrap:BAABLgAECn8VAAIaAAcJsgpmIgAlAQAaAAcJsgpmIgAlAQAAAA==.Crusaide:BAAALgADCgUJBQAAAA==.Cryola:BAAALgADCgEJAQAAAA==.',
Cu='Cursereflect:BAABLgAECn8WAAIbAAcJUxGIPQByAQAbAAcJUxGIPQByAQAAAA==.Curseus:BAAALgADCgUJBgAAAA==.',
Cy='Cyberwin:BAAALgAECgEJAQAAAA==.',
Da='Damncats:BAABLgAECn8cAAINAAcJfwgOLQAcAQANAAcJfwgOLQAcAQAAAA==.Dandinn:BAAALgAECgMJAwAAAA==.Danielsboone:BAAALgAECgYJEAAAAA==.Darkangor:BAAALgADCgcJBwAAAA==.Darkansic:BAAALgADCgQJBAAAAA==.Darkmare:BAAALgAECgQJBwABLgAECggJHgAcAFscAA==.Darknemesis:BAAALgADCggJDgAAAA==.Dawnhaven:BAAALgADCgcJBgAAAA==.Daysubb:BAAALgAECgEJAQABLgAFFAUJGgAWALEhAA==.',
De='Deadhippocow:BAAALgAECgUJCQAAAA==.Deathwavez:BAACLgAFFH8JAAIUAAMJkwtJVQDiAAAUAAMJkwtJVQDiAAAuAAQKfxoAAhQABwkwF/dkAMUBABQABwkwF/dkAMUBAAAA.Decurse:BAABLgAECn8ZAAIbAAcJexUBOgB+AQAbAAcJexUBOgB+AQAAAA==.Deldrin:BAABLgAECn8XAAIRAAcJMBCxWgBfAQARAAcJMBCxWgBfAQAAAA==.Demayy:BAABLgAECn8UAAIZAAkJxgSBIwAqAQAZAAkJxgSBIwAqAQAAAA==.Demona:BAABLgAECn8jAAMWAAgJTBXtKQAaAQAbAAcJ4RHubgCCAQAWAAQJ4BPtKQAaAQAAAA==.Demonix:BAAALgAECgYJDgAAAA==.Demonstdfred:BAAALgADCgEJAQAAAA==.Derptron:BAABLgAECn8iAAIRAAcJXA3qWQBhAQARAAcJXA3qWQBhAQAAAA==.Devira:BAAALgAECgQJBAAAAA==.',
Di='Diisco:BAAALgADCgcJDgAAAA==.Dillydally:BAAALgAECgQJBAAAAA==.Dilutedret:BAAALgAECgYJDgAAAA==.Dinobrass:BAABLgAECn8dAAIEAAcJEQ7eCgBCAQAEAAcJEQ7eCgBCAQAAAA==.Dirtylöbster:BAACLgAFFH8MAAIRAAMJTCHQJwAUAQARAAMJTCHQJwAUAQAuAAQKfy0AAhEACQlBJMoDAD4DABEACQlBJMoDAD4DAAAA.Disabel:BAAALgAECgUJDQAAAA==.Distracto:BAAALgAECgkJCQAAAA==.',
Dl='Dltdjr:BAAALgAECgYJCgABLgAECgYJDgATAAAAAA==.',
Do='Dochollíday:BAAALgADCgEJAQAAAA==.Doolittle:BAAALgAECgUJEAAAAA==.Dorose:BAAALgADCggJCgAAAA==.Doublepop:BAAALgAECgYJBwAAAA==.',
Dr='Drewmee:BAABLgAECn8UAAIPAAcJDgqUagAYAQAPAAcJDgqUagAYAQAAAA==.Dronar:BAAALgADCgEJAQABLgAECgkJDwATAAAAAA==.Drublood:BAAALgAECgYJBgABLgAECgcJFAAPAA4KAA==.Drunkinmasta:BAAALgAECgEJAQABLgAFFAMJCAAPAPEQAA==.Drwut:BAAALgAECggJDQAAAA==.',
Du='Dune:BAAALgADCgcJBwAAAA==.Duwork:BAAALgAECgYJDgAAAA==.',
Ee='Eekany:BAAALgAECgMJAwAAAA==.',
El='Eladus:BAAALgAECgYJCQAAAA==.Elemnt:BAAALgAECgUJCAABLgAFFAMJCAAPAPEQAA==.Elladon:BAAALgAECgQJAwAAAA==.Elmster:BAAALgAECgEJAgAAAA==.',
Em='Emblaze:BAAALgAECgYJCwAAAA==.',
En='Enhshaman:BAAALgAFFAMJBAAAAA==.',
Er='Eremith:BAAALgADCgEJAQAAAA==.',
Es='Essentials:BAAALgAECgMJBAAAAA==.',
Ev='Evacadrabra:BAAALgADCgUJBQAAAA==.',
Ez='Ezkal:BAACLgAFFH8LAAIUAAQJmRkmJQBVAQAUAAQJmRkmJQBVAQAuAAQKfywAAxQACQnsGZwYAOgCABQACQnsGZwYAOgCAAgABgkoFagUADEBAAAA.',
Fa='Faithastray:BAAALgAECgMJAwAAAA==.Faithpasse:BAABLgAECn8VAAMZAAYJtBBmJQAcAQAZAAYJtBBmJQAcAQAMAAEJ9gPXhgApAAAAAA==.Falcorne:BAABLgAECn8hAAIDAAcJZh7CHQDqAQADAAcJZh7CHQDqAQAAAA==.',
Fe='Felondar:BAABLgAECn8bAAMdAAgJFgrIEwBQAQAdAAgJFgrIEwBQAQAQAAYJsASpmwDhAAAAAA==.Felshen:BAAALgADCgUJBQAAAA==.Ferarro:BAABLgAECn8ZAAMIAAkJhBsvDABOAgAIAAcJsBsvDABOAgAUAAgJvhh9agC3AQAAAA==.',
Fi='Finnadin:BAAALgAECgcJEQAAAA==.Finns:BAAALgAECgcJDQAAAA==.Firalyn:BAAALgAECgYJDgAAAA==.Firulais:BAABLgAECn8UAAIDAAcJmRkhIADbAQADAAcJmRkhIADbAQAAAA==.Fistobeef:BAAALgAECgEJAQAAAA==.',
Fl='Fleable:BAAALgADCgUJBQAAAA==.Flysky:BAACLgAFFH8RAAIeAAUJnhnEBwChAQAeAAUJnhnEBwChAQAuAAQKfyMABB4ACQnGI4kCAEcDAB4ACQnGI4kCAEcDAB8AAgnZHPNQAFQAAAUAAQl3DxpBAC4AAAAA.',
Fo='Forrest:BAAALgAECgEJAgAAAA==.Foxsake:BAAALgAECggJDQAAAA==.',
Fr='Freakmeout:BAAALgADCgkJFQAAAA==.Frostadin:BAAALgADCgEJAQAAAA==.Frostbones:BAAALgAECgUJBgAAAA==.Frostuss:BAAALgAECgEJAQAAAA==.Frözenflames:BAAALgAFFAEJAQAAAA==.',
Fu='Fur:BAAALgADCggJCAAAAA==.Future:BAAALgAECgUJDQAAAA==.Futuredragoo:BAAALgAECgIJAgAAAA==.Fuzzydeeps:BAAALgADCgQJBAAAAA==.',
Ga='Gabriella:BAAALgAECgEJAQAAAA==.Gallardo:BAAALgADCgUJBQABLgAECgUJDQATAAAAAA==.Galnannix:BAAALgAECgcJDAAAAA==.Gardrake:BAABLgAECn8jAAMfAAkJYhcPCQA+AgAfAAkJYhcPCQA+AgAeAAcJUQ+nHQCWAQAAAA==.Gastapha:BAABLgAECn8UAAIQAAcJBQalaQDJAAAQAAcJBQalaQDJAAAAAA==.',
Ge='Gearth:BAAALgADCgMJAwAAAA==.Geel:BAABLgAECn8dAAMNAAgJBxMbMADvAQANAAgJBxMbMADvAQAgAAEJAACrSAAAAAAAAA==.Gehennas:BAAALgAECggJEwAAAA==.Gereck:BAAALgADCgIJAgAAAA==.Gerthsham:BAAALgADCgUJBQAAAA==.',
Go='Goofykirby:BAAALgADCgcJFQAAAA==.Googoogagaa:BAACLgAFFH8MAAIXAAQJkhAEDABDAQAXAAQJkhAEDABDAQAuAAQKf0IAAxcACQkEHigDAM0CABcACQkEHigDAM0CAAYABwnyEgEqAKIBAAAA.Gotlieb:BAAALgAECgYJBwAAAA==.',
Gr='Griffith:BAAALgADCgEJAgAAAA==.Grimghor:BAAALgADCgYJBgAAAA==.Groggasan:BAAALgADCgYJBgABLgADCgcJDQATAAAAAA==.Groggfather:BAAALgADCgcJDQAAAA==.Gronhal:BAAALgADCgQJBAAAAA==.Groundz:BAAALgADCgYJBgAAAA==.Grrahtahtah:BAACLgAFFH8XAAMEAAcJCRRQBwCnAQAEAAcJCRRQBwCnAQACAAMJQgwyFgCkAAAuAAQKfxQAAgQABwkJJNgRAKoCAAQABwkJJNgRAKoCAAAA.Grävyy:BAAALgAECggJEgAAAA==.',
Gy='Gyrozug:BAAALgAECggJEwAAAA==.',
Ha='Hamatza:BAAALgAECgEJAQAAAA==.Hammerinfred:BAAALgAECgMJAwAAAA==.',
He='Healingisfun:BAAALgAECgMJAwAAAA==.Helhunter:BAABLgAECn8eAAIQAAgJ9xGXNQBfAQAQAAgJ9xGXNQBfAQAAAA==.Hellock:BAAALgAECgIJAgAAAA==.',
Hi='Hippysmasher:BAAALgAECgIJAgAAAA==.',
Ho='Hohk:BAAALgAECgIJAgAAAA==.Holden:BAAALgAECgMJBQAAAA==.Holyapostle:BAAALgAECgEJAQAAAA==.Holyhooters:BAABLgAECn8oAAIPAAgJaSIYCwCrAgAPAAgJaSIYCwCrAgAAAA==.Holypablo:BAAALgADCgcJDQABLgAECgkJMwAhABEfAA==.Homefries:BAAALgADCgYJBgAAAA==.Honkytonk:BAABLgAECn8aAAMFAAgJKAs5IgAYAQAFAAYJ7Qk5IgAYAQAfAAcJcQmoOAATAQAAAA==.Honour:BAABLgAECn8nAAIPAAkJJyBgCQDAAgAPAAkJJyBgCQDAAgAAAA==.',
Hr='Hrathdemon:BAACLgAFFH8GAAIQAAMJfhOdMQDqAAAQAAMJfhOdMQDqAAAuAAQKfyYAAhAACAlYHaISACgCABAACAlYHaISACgCAAAA.Hrathid:BAAALgADCgUJDAABLgAFFAMJBgAQAH4TAA==.',
Hu='Huntermik:BAAALgADCgcJBwAAAA==.Hupa:BAACLgAFFH8IAAIPAAMJiiBREgATAQAPAAMJiiBREgATAQAuAAQKfyQAAg8ACQkHI7cFAHIDAA8ACQkHI7cFAHIDAAAA.Husk:BAAALgADCgEJAQAAAA==.',
Ia='Iamheyo:BAAALgAECggJEQAAAA==.',
Ib='Ibleedorange:BAAALgAECgUJCQAAAA==.',
Ic='Ickeetard:BAABLgAECn8VAAMhAAcJJw8qFwB/AQAhAAcJEw8qFwB/AQAGAAMJWwrxagCAAAAAAA==.',
Id='Idiot:BAAALgAECgMJBAAAAA==.Idiotbreath:BAABLgAECn8uAAMfAAkJIx5JAwDjAgAfAAkJIx5JAwDjAgAFAAMJmQl5MACTAAAAAA==.',
Ie='Ieatcheeks:BAAALgAECgEJAQAAAA==.',
Ig='Iglooshocker:BAEBLgAFFH8FAAIcAAMJewbLEQDbAAAcAAMJewbLEQDbAAAAAA==.',
Im='Immorlich:BAAALgADCgcJBwAAAA==.Imonaship:BAAALgADCgcJBwAAAA==.',
In='Infari:BAAALgADCgYJCQAAAA==.Inflexi:BAABLgAECn8ZAAMEAAgJKR3oGABkAgAEAAgJyxroGABkAgADAAQJiSFHMgCEAQAAAA==.Inky:BAAALgADCgYJCgAAAA==.',
Ip='Ipriest:BAAALgADCgYJBgAAAA==.',
Is='Is:BAABLgAECn8UAAIMAAYJdhjDFwBoAQAMAAYJdhjDFwBoAQAAAA==.',
It='Itsmagharszn:BAAALgADCgQJBAAAAA==.Itsthereaper:BAABLgAECn8uAAQYAAkJSRzZCwCMAgAYAAkJSRzZCwCMAgAaAAgJ6h0uFQBnAgAKAAMJ0haQFADHAAAAAA==.',
Iv='Iver:BAAALgAECgEJAQABLgAECgcJEAATAAAAAA==.',
Ja='Jangle:BAAALgADCgYJBwAAAA==.',
Jh='Jhana:BAAALgADCgIJAgABLgAECgMJBgATAAAAAA==.',
Jj='Jjooaacchhim:BAAALgADCgIJAgAAAA==.',
Jy='Jyve:BAABLgAECn8iAAIDAAkJfBvPCwCBAgADAAkJfBvPCwCBAgAAAA==.',
Ka='Kaelira:BAAALgADCgIJAgAAAA==.Kairei:BAAALgAECgUJCwAAAA==.Kalda:BAAALgAECgEJAgAAAA==.Kalor:BAAALgADCgQJBAAAAA==.Kamadan:BAAALgAECgUJBQAAAA==.Kamanactali:BAAALgAECgUJCgAAAA==.Kaneko:BAAALgAFFAMJAwAAAA==.Katalina:BAABLgAECn8nAAMiAAgJjg8fCABkAQAiAAgJjg8fCABkAQAdAAYJpwsNOAAlAQAAAA==.Kawer:BAAALgAECgQJCAAAAA==.',
Ke='Kelstormhoof:BAAALgADCgcJFgABLgADCggJDgATAAAAAA==.Kernel:BAAALgAECgEJAQABLgAECggJKwANAFckAA==.',
Kh='Kham:BAACLgAFFH8JAAINAAMJnR+vFQACAQANAAMJnR+vFQACAQAuAAQKfzQAAg0ACQkyI30BAB8DAA0ACQkyI30BAB8DAAAA.',
Ki='Killmaim:BAABLgAECn8ZAAINAAgJwRlqIABPAgANAAgJwRlqIABPAgAAAA==.Kitsuko:BAABLgAECn8sAAMcAAkJxhCYEQDRAQAcAAkJxhCYEQDRAQAjAAkJKQxJJwCEAQAAAA==.',
Kl='Klais:BAAALgAECgQJBAAAAA==.',
Ku='Kuani:BAAALgADCgkJCQAAAA==.Kuraishin:BAAALgADCgcJBwABLgAFFAQJDQARAE4YAA==.',
['Kë']='Këltön:BAAALgAECgIJAgAAAA==.',
La='Lavashiza:BAAALgAECgIJAgAAAA==.Lazycouch:BAAALgADCgUJBQAAAA==.',
Le='Leadzorz:BAAALgAECgUJEAAAAA==.Learingcentr:BAAALgAECgMJAwAAAA==.Lechuza:BAAALgAECgEJAQAAAA==.Leedaddydk:BAAALgAECgMJBgAAAA==.Leroyjenkins:BAABLgAECn8XAAIkAAcJ8BvoAgBVAgAkAAcJ8BvoAgBVAgAAAA==.Lesaelia:BAAALgADCgYJBgAAAA==.',
Li='Lightstorm:BAAALgAECgYJCgAAAA==.Linaria:BAAALgADCgEJAQAAAA==.Linø:BAAALgAECgEJAQAAAA==.Lissara:BAAALgAECgYJDAAAAA==.Liv:BAAALgAECgMJBAAAAA==.Lizzymonk:BAACLgAFFH8HAAIlAAMJrROXHwDiAAAlAAMJrROXHwDiAAAuAAQKfyAAAiUACAlaH2MOAK8CACUACAlaH2MOAK8CAAAA.',
Lo='Loa:BAAALgADCgYJBwAAAA==.Lockwerk:BAAALgAECgcJBQABLgAECggJGQADAOMjAA==.',
Lu='Luckfist:BAAALgAECgYJCQABLgAFFAMJBwAVACMVAA==.Luminouslexi:BAAALgADCgUJBwAAAA==.',
Ma='Macoub:BAAALgAECgUJCgAAAA==.Macuahuitl:BAAALgADCgYJBgAAAA==.Maddog:BAABLgAECn8ZAAMWAAgJfAWeDQD4AAAWAAgJUAWeDQD4AAAbAAQJywOSoAB7AAAAAA==.Mageslayer:BAABLgAECn8UAAMmAAcJwRN4FQBhAQAmAAYJKRN4FQBhAQABAAMJPhDBDwC1AAAAAA==.Magicichin:BAAALgADCgcJCgAAAA==.Magistaer:BAAALgADCgMJAwAAAA==.Magmanuts:BAAALgAECgUJBQABLgAECgYJBgATAAAAAA==.Makkideez:BAAALgAFFAEJAQAAAA==.Manabuns:BAABLgAECn8jAAIRAAgJSRf8LADtAQARAAgJSRf8LADtAQAAAA==.Mandrro:BAAALgADCgkJDAAAAA==.Marfa:BAABLgAECn8fAAIPAAgJ6RVIQgAeAgAPAAgJ6RVIQgAeAgAAAA==.Markruffalo:BAAALgADCgIJAgAAAA==.Mathias:BAAALgAECgMJAwAAAA==.Mavrik:BAABLgAECn8iAAINAAkJyRcECgBIAgANAAkJyRcECgBIAgAAAA==.',
Mc='Mckay:BAAALgAECggJEwAAAA==.Mckáy:BAAALgADCgYJBAAAAA==.Mckäy:BAAALgAECgQJBAAAAA==.Mckåy:BAAALgADCgQJBAAAAA==.',
Me='Meatmagic:BAABLgAECn8mAAIkAAgJOhQWAgDiAQAkAAgJOhQWAgDiAQAAAA==.Megapunk:BAAALgADCgkJIQAAAA==.Mellmaan:BAAALgADCgYJBgAAAA==.Melys:BAAALgAECgYJCwAAAA==.Mercenar:BAAALgADCgEJAQAAAA==.Meteorite:BAAALgAECgYJCAAAAA==.Meudayr:BAAALgAECgkJDwAAAA==.Mevoker:BAAALgADCgcJBwAAAA==.',
Mi='Millarolly:BAAALgADCgUJBQAAAA==.Mindkawntrol:BAAALgAECgQJBAAAAA==.Mirari:BAABLgAECn8eAAIcAAgJWxwgEgCSAgAcAAgJWxwgEgCSAgAAAA==.',
Mo='Moistblanket:BAAALgAECgIJAgAAAA==.Mojorisin:BAABLgAECn8aAAICAAkJnxq5BwB1AgACAAkJnxq5BwB1AgAAAA==.Moonchiken:BAAALgAECgEJBQAAAA==.Moozlock:BAABLgAECn8eAAIbAAgJCRIENwCJAQAbAAgJCRIENwCJAQAAAA==.Moscovio:BAAALgAFFAIJBAAAAA==.Mosspaws:BAABLgAECn8uAAMYAAkJDCRqBAAbAwAYAAkJDCRqBAAbAwAaAAQJXx/zGgBeAQAAAA==.',
Mt='Mtndewyou:BAAALgADCgIJAgAAAA==.',
Mu='Murderinc:BAAALgADCgMJAwAAAA==.',
My='Myeyes:BAAALgAECgYJCgAAAA==.',
Na='Narfiy:BAAALgADCgEJAQAAAA==.',
Ni='Nickimihoj:BAAALgAECgQJBQAAAA==.',
Nm='Nme:BAABLgAECn8dAAMRAAgJDA4XRgCVAQARAAgJ7g0XRgCVAQAkAAYJbQ9LCQBWAQAAAA==.',
No='Nocturnos:BAABLgAECn8iAAMbAAgJ+R3nFgArAgAbAAgJ+R3nFgArAgAVAAEJUB93LABGAAAAAA==.Noggin:BAABLgAECn8jAAILAAkJRyHeAgAdAwALAAkJRyHeAgAdAwAAAA==.Nonform:BAABLgAECn80AAQaAAkJGRmHCABIAgAaAAkJGRmHCABIAgAJAAEJwRXLIwBDAAAYAAEJdAEB7AAXAAAAAA==.Noodles:BAAALgADCgYJFAABLgAECgYJBgATAAAAAA==.Noskillidan:BAAALgADCgMJAwABLgAECgUJCQATAAAAAA==.Novamancer:BAAALgADCgIJAgAAAA==.Noxta:BAAALgAECgYJDgAAAA==.',
Nu='Numonixx:BAACLgAFFH8TAAMFAAUJZQ0gAwAJAQAfAAUJxgyjGAAhAQAFAAQJ6gcgAwAJAQAuAAQKfyUAAwUACAnzHKcJAEUCAAUACAl7G6cJAEUCAB8ABwkvGzUOAOsBAAAA.Nutlessfred:BAAALgADCgYJBgAAAA==.',
Ny='Nymage:BAABLgAECn8/AAIRAAkJRhqVEQCNAgARAAkJRhqVEQCNAgAAAA==.',
Og='Ogg:BAAALgADCgMJAwAAAA==.Ogmund:BAAALgADCgIJAgAAAA==.',
Oh='Ohnospiders:BAABLgAECn8bAAIUAAkJWBERJgDoAQAUAAkJWBERJgDoAQAAAA==.Ohpig:BAAALgAECgMJAwAAAA==.',
Ok='Okaerisan:BAAALgAECgcJEQAAAA==.',
Om='Omgbbqq:BAAALgAECgIJAgABLgAECgkJKgADANkjAA==.',
Oo='Oomi:BAAALgAECgEJAQAAAA==.',
Op='Ophil:BAAALgAECgQJBAAAAA==.',
Or='Orack:BAAALgAECgYJCQAAAA==.Orcrot:BAAALgAECgYJBgAAAA==.',
Ou='Outlast:BAACLgAFFH8IAAIPAAMJ8RA0LwD4AAAPAAMJ8RA0LwD4AAAuAAQKfyoAAg8ACQk7HbERAAQDAA8ACQk7HbERAAQDAAAA.',
Pa='Paants:BAABLgAECn8YAAInAAcJdw3XGAD5AAAnAAcJdw3XGAD5AAAAAA==.Pacidlol:BAAALgADCgMJBAAAAA==.Pakal:BAAALgADCgQJBAAAAA==.Palebull:BAAALgADCgQJBQAAAA==.Palonixx:BAAALgAECgEJAQAAAA==.Panblind:BAACLgAFFH8OAAIQAAUJ5yIkCgCjAQAQAAUJ5yIkCgCjAQAuAAQKfyoAAhAACQmrI4wQAPoCABAACQmrI4wQAPoCAAAA.Parmigiano:BAAALgADCgEJAQABLgAFFAMJAwATAAAAAA==.Parmrageiano:BAAALgAFFAMJAwAAAA==.Parms:BAABLgAECn8ZAAQCAAgJ8xPpEACfAQACAAgJ4xHpEACfAQAEAAYJhQw8TQAcAQADAAIJORAOowCFAAABLgAFFAMJAwATAAAAAA==.',
Pe='Peanought:BAABLgAECn8bAAMHAAgJIBcBBgDJAQAHAAgJIBcBBgDJAQAUAAYJWAiqvQAHAQAAAA==.Peidro:BAABLgAECn8UAAIPAAcJqwsvZwAfAQAPAAcJqwsvZwAfAQAAAA==.Pentacles:BAABLgAECn8lAAIKAAkJrSCDAgCJAgAKAAkJrSCDAgCJAgAAAA==.',
Pi='Pijak:BAAALgAECgUJEAAAAA==.Pinkpaw:BAAALgAECgcJDQAAAA==.',
Pl='Pleo:BAAALgAECgcJBwAAAA==.',
Po='Poah:BAABLgAFFH8IAAMlAAMJ3iTvCABGAQAlAAMJ3iTvCABGAQAMAAEJZwsuIABKAAAAAA==.Poahsham:BAAALgAECgEJAgABLgAFFAMJCAAlAN4kAA==.Postscalone:BAAALgAECgEJAQAAAA==.Potatoes:BAABLgAECn8VAAMWAAgJBgiVHABpAQAWAAgJBgiVHABpAQAbAAIJCQJGFAE6AAAAAA==.',
Pr='Pruflas:BAABLgAECn8ZAAIUAAgJZAtaQQB5AQAUAAgJZAtaQQB5AQAAAA==.',
Ps='Psycodk:BAAALgAECgYJDwAAAA==.',
Pu='Pumpin:BAABLgAECn8XAAIMAAUJFCTtEwCSAQAMAAUJFCTtEwCSAQAAAA==.Purplemonstr:BAAALgADCgUJBQAAAA==.',
Qk='Qkn:BAAALgAECgUJCgAAAA==.',
Qu='Quickswipe:BAAALgAECgcJDAABLgAFFAUJGgAWALEhAA==.',
Qx='Qx:BAAALgAECgIJAgAAAA==.',
Ra='Raballa:BAAALgADCgUJBQAAAA==.Rafraff:BAAALgADCgUJBQAAAA==.Ralee:BAAALgADCgIJAgAAAA==.Randomhero:BAAALgADCgkJCQAAAA==.Rannt:BAAALgADCgcJBwAAAA==.Rashek:BAAALgADCgEJAQAAAA==.Raynne:BAAALgAECgIJAgAAAA==.',
Re='Reaperjoe:BAAALgAECgQJBAAAAA==.Rehab:BAAALgAECgkJEwAAAA==.Rehna:BAAALgAECgYJBgABLgAFFAMJCgAGANAVAA==.Rektributio:BAACLgAFFH8YAAIPAAcJOR+BAAB6AgAPAAcJOR+BAAB6AgAuAAQKfzEAAg8ACQkfJR8BAGkDAA8ACQkfJR8BAGkDAAAA.Revalation:BAABLgAECn8ZAAIYAAkJDR3eHgBIAgAYAAkJDR3eHgBIAgAAAA==.',
Rh='Rhisis:BAAALgADCgUJBQABLgAECgQJCgATAAAAAA==.Rhyss:BAAALgAECgMJAwAAAA==.',
Ri='Rigorpumpis:BAAALgAECgQJBQAAAA==.',
Ro='Roadblock:BAAALgAECgUJEQAAAA==.Roadtrip:BAAALgAECgMJBAAAAA==.Roadtripsx:BAAALgAECgMJAwAAAA==.Roadtripxxds:BAAALgAECgEJAgAAAA==.Roboorc:BAAALgAECgEJAwAAAA==.Rottingslow:BAAALgAECgIJAwABLgAFFAcJEAAIAJAeAA==.',
Sa='Saragos:BAAALgADCgcJBgABLgAFFAQJDQARAE4YAA==.Saucerdote:BAABLgAECn8XAAMXAAkJEwmQFQCUAQAXAAkJEwmQFQCUAQAhAAIJ2wC2XQAnAAAAAA==.',
Sc='Schnee:BAAALgADCgYJBgABLgAFFAQJDQARAE4YAA==.Scythefrah:BAAALgAECgUJBAAAAA==.',
Se='Selinfinite:BAABLgAECn8ZAAIQAAkJwxuqDABoAgAQAAkJwxuqDABoAgAAAA==.Selkie:BAABLgAECn8YAAIoAAgJuQpXCgBwAQAoAAgJuQpXCgBwAQAAAA==.Seragosa:BAAALgAFFAEJAQABLgAFFAQJDQARAE4YAA==.',
Sh='Shakakhan:BAAALgAECgUJBQABLgAECgYJDgATAAAAAA==.Shambeau:BAAALgADCgQJBAAAAA==.Shamshielder:BAEBLgAECn8jAAMIAAcJHiEkCwDEAQAIAAcJHiEkCwDEAQAUAAEJvAnl9AAtAAABLgAFFAMJBQAcAHsGAA==.Sharick:BAAALgAECgMJAwAAAA==.Shawlee:BAABLgAECn8rAAMjAAgJzBDZLwBSAQAjAAgJzBDZLwBSAQAcAAgJCAgsPQC3AAAAAA==.Sheezie:BAABLgAECn8fAAIjAAgJ5RdFFgABAgAjAAgJ5RdFFgABAgAAAA==.Shellter:BAAALgAECgEJAgABLgAECgcJGAASAD0cAA==.Shellwit:BAAALgAECgMJBgABLgAECgcJGAASAD0cAA==.Sheph:BAAALgAECgQJBAAAAA==.Shetmage:BAACLgAFFH8OAAIRAAUJDwnNIwAoAQARAAUJDwnNIwAoAQAuAAQKfyAAAhEACQkSHrgqAMgCABEACQkSHrgqAMgCAAAA.Shettrah:BAAALgAECgYJEQABLgAFFAUJDgARAA8JAA==.Shockybalboa:BAAALgADCgcJBwAAAA==.Shorttbuss:BAABLgAECn8XAAIPAAcJMhJ7TwBXAQAPAAcJMhJ7TwBXAQAAAA==.Shuck:BAAALgAECgQJBAABLgAECggJKwANAFckAA==.Shunsui:BAAALgAECgEJAQAAAA==.',
Si='Siickboy:BAAALgAECgMJBQAAAA==.Sijious:BAAALgAECgEJAQAAAA==.Silveah:BAAALgADCgEJAQAAAA==.Simperhi:BAAALgAECgEJAQAAAA==.Sinclear:BAAALgADCgYJCQAAAA==.',
Sk='Skora:BAAALgADCgIJAgABLgAECggJHwAPAOkVAA==.Skyland:BAAALgADCgcJDQAAAA==.Skyli:BAAALgAECgUJCAABLgAECgkJGAAjAGodAA==.',
Sl='Slush:BAAALgAECgIJAgAAAA==.',
Sn='Snuph:BAAALgAECgQJCgAAAA==.',
So='Somi:BAACLgAFFH8HAAILAAMJVBwUFgD6AAALAAMJVBwUFgD6AAAuAAQKfyUAAgsACAlbILwIAOMCAAsACAlbILwIAOMCAAAA.Sorrie:BAAALgAECgEJAQAAAA==.',
Sp='Spud:BAAALgADCgcJBwABLgAECgQJCAATAAAAAA==.Spyroh:BAABLgAECn8bAAQfAAYJzxJJIgAyAQAFAAYJcBDnGQBlAQAfAAUJ/BFJIgAyAQAeAAEJ2wAxTwAeAAAAAA==.',
Ss='Ssohl:BAAALgAECgUJDgABLgAFFAMJCgAGANAVAA==.',
St='Stankydk:BAACLgAFFH8LAAMUAAUJ1hZqGgA8AQAUAAQJ1hZqGgA8AQAIAAEJAACfMwAAAAAuAAQKfykAAhQACQlmIX4nAJ0CABQACQlmIX4nAJ0CAAAA.Stankyeyes:BAAALgAECgYJBgAAAA==.Stankyleg:BAAALgADCgcJDQAAAA==.Stankymage:BAAALgADCgUJBAAAAA==.Steakhead:BAAALgAECgUJDgAAAA==.Stinkbombs:BAABLgAFFH8HAAIRAAQJJwM4QAAMAQARAAQJJwM4QAAMAQAAAA==.Stinkerz:BAAALgAECgIJAgABLgAECgcJGAASAD0cAA==.Stunanddone:BAAALgAECgQJCAAAAA==.',
Su='Sumdragon:BAAALgADCgEJAQAAAA==.Sunlest:BAAALgADCgcJCwAAAA==.Supreme:BAACLgAFFH8IAAIQAAMJXhplLQD7AAAQAAMJXhplLQD7AAAuAAQKfxkAAhAACAl4I2oYAMMCABAACAl4I2oYAMMCAAAA.',
Sw='Swaayshooter:BAAALgAFFAMJAwAAAA==.',
Sy='Sydios:BAAALgADCgUJBQABLgAFFAUJCQALAAkNAA==.Sylphrena:BAACLgAFFH8HAAIGAAMJKRQoDwDdAAAGAAMJKRQoDwDdAAAuAAQKfyUAAgYACAkqIIkIAMMCAAYACAkqIIkIAMMCAAAA.',
['Sí']='Sínful:BAABLgAECn8mAAIEAAgJRh9aAgBcAgAEAAgJRh9aAgBcAgAAAA==.',
Ta='Tahwe:BAAALgADCgcJBwAAAA==.Talethen:BAAALgAECgcJEwAAAA==.Talla:BAABLgAECn8YAAIjAAkJah2nGgBCAgAjAAkJah2nGgBCAgAAAA==.Tammey:BAAALgADCgcJBwAAAA==.',
Te='Telaragehoof:BAAALgADCgkJIQAAAA==.Tellus:BAAALgADCgcJCQAAAA==.Tewshort:BAAALgAECgQJCQABLgAFFAMJCAAPAPEQAA==.',
Th='Thatbox:BAAALgAECgEJAQAAAA==.Thdon:BAAALgADCgIJAgAAAA==.Thedrood:BAAALgAECgQJCQAAAA==.Themlgyeet:BAAALgADCgEJAQAAAA==.Thiccfists:BAABLgAECn8UAAMMAAgJAwWYMADDAAAlAAcJQQRVWQDeAAAMAAcJQQSYMADDAAAAAA==.Thorfyna:BAABLgAECn8YAAIiAAcJExJjCwAVAQAiAAcJExJjCwAVAQAAAA==.Threzk:BAABLgAECn8eAAIWAAkJdA5FBgCOAQAWAAkJdA5FBgCOAQAAAA==.Thunderclap:BAAALgADCgIJAgAAAA==.',
Ti='Tiderias:BAAALgAECgEJAQAAAA==.',
To='Toekin:BAAALgAECgUJBQAAAA==.Tohk:BAACLgAFFH8KAAIQAAQJaRYuHQA2AQAQAAQJaRYuHQA2AQAuAAQKfyYAAhAACQkpIcQSAOkCABAACQkpIcQSAOkCAAAA.Tontiamat:BAABLgAECn8oAAMfAAkJkBb5CABAAgAfAAkJkBb5CABAAgAFAAYJawozIAAsAQAAAA==.Tontier:BAAALgAECgUJDAABLgAECgkJKAAfAJAWAA==.Totembeans:BAAALgAECgQJCwAAAA==.',
Tr='Tralidoris:BAAALgADCgEJAQAAAA==.Trashen:BAACLgAFFH8JAAILAAUJCQ0hCwBxAQALAAUJCQ0hCwBxAQAuAAQKfxQABAsACAmoGGYMAE4CAAsACAmoGGYMAE4CAA8ABglODTq3ABcBAA4AAQl9Frk/AD8AAAAA.Trashfire:BAACLgAFFH8KAAMGAAQJVg6XCQAsAQAGAAQJVg6XCQAsAQAhAAIJwgFxFgB7AAAuAAQKfx0ABAYACAkWHSUQAGUCAAYACAkWHSUQAGUCABcABQknFXg2ADkBACEAAwluEWdAAK0AAAEuAAUUBQkJAAsACQ0A.Treeple:BAABLgAECn8YAAIYAAcJFxNGMABfAQAYAAcJFxNGMABfAQAAAA==.Treily:BAAALgAECgMJBQAAAA==.Tresleches:BAABLgAECn8bAAIPAAcJTg8fXQA1AQAPAAcJTg8fXQA1AQAAAA==.Tricket:BAABLgAECn8uAAMgAAgJihrsBgBWAgAgAAgJ9RnsBgBWAgANAAYJKBlBLQAbAQAAAA==.Trousers:BAAALgAECgYJBgABLgAECggJFQAWAAYIAQ==.Truestorm:BAABLgAECn8jAAIPAAgJmgubSwBjAQAPAAgJmgubSwBjAQAAAA==.Truheals:BAAALgADCgkJEwAAAA==.',
Tu='Tuchi:BAACLgAFFH8RAAIRAAUJ/heoKgBUAQARAAUJ/heoKgBUAQAuAAQKfxwAAxEABwliIrUyAKgCABEABwliIrUyAKgCACQAAglBBa4YAFMAAAAA.Tussin:BAAALgADCgEJAQAAAA==.',
Tw='Tweedlepan:BAAALgADCgcJDQABLgAFFAUJDgAQAOciAA==.',
['Tà']='Tàcobelle:BAAALgADCgYJBwABLgAECggJIwARAEkXAA==.',
Up='Uptownpimp:BAAALgAECgEJAgAAAA==.',
Va='Valandral:BAAALgADCgEJAQAAAA==.Valdor:BAAALgADCgEJAQABLgAECgIJAgATAAAAAA==.Valyarn:BAAALgADCgcJBwAAAA==.Vanicton:BAACLgAFFH8HAAIjAAMJsSI6FgAXAQAjAAMJsSI6FgAXAQAuAAQKfyoAAyMACAmGHUESAIQCACMACAmGHUESAIQCABwABAmZGHUmACYBAAAA.Varanis:BAACLgAFFH8IAAIDAAMJlhZvDAD/AAADAAMJlhZvDAD/AAAuAAQKfxcAAgMACAkLImQLAOgCAAMACAkLImQLAOgCAAAA.',
Ve='Vegh:BAABLgAECn81AAIiAAkJWBtCAgBhAgAiAAkJWBtCAgBhAgAAAA==.Vem:BAABLgAECn8aAAIfAAkJDh0gEAB2AgAfAAkJDh0gEAB2AgAAAA==.Veriale:BAAALgAECgUJCgAAAA==.Verra:BAABLgAECn8bAAIPAAcJtBZONQCoAQAPAAcJtBZONQCoAQAAAA==.',
Vi='Vitriol:BAABLgAECn8VAAINAAYJhBQpSgB8AQANAAYJhBQpSgB8AQAAAA==.',
Vo='Voidbeaver:BAAALgAECgUJCAAAAA==.Voidfent:BAAALgADCgEJAQAAAA==.Voidluck:BAACLgAFFH8HAAMVAAMJIxUSAgDsAAAVAAMJIxUSAgDsAAAWAAEJYQdqFQBJAAAuAAQKfxcAAhUABwnUI6sBAMoCABUABwnUI6sBAMoCAAAA.',
Vy='Vynlaeron:BAAALgADCgkJEgABLgAECgYJCQATAAAAAA==.Vyrros:BAAALgADCgUJBQAAAA==.',
Wa='Walji:BAABLgAECn8eAAMjAAgJzhtzFwBaAgAjAAgJzhtzFwBaAgAcAAEJVQubZgAwAAAAAA==.Wampa:BAAALgADCgcJDgAAAA==.Wanderblue:BAAALgAECgEJAQAAAA==.Wandy:BAABLgAECn8eAAIbAAcJVxCFaQCQAQAbAAcJVxCFaQCQAQAAAA==.Wangstah:BAABLgAECn8ZAAIDAAgJ4yM4BgDOAgADAAgJ4yM4BgDOAgAAAA==.Warblades:BAAALgADCgEJAQAAAA==.Wargloves:BAABLgAECn8bAAINAAYJMRQzLQAbAQANAAYJMRQzLQAbAQAAAA==.Warmslippers:BAAALgAECgYJCgAAAA==.Wataa:BAAALgADCgQJBAAAAA==.Wavez:BAAALgAECgcJDAAAAA==.Wawatesi:BAAALgAECgMJAwAAAA==.Waytogoteam:BAABLgAECn8qAAIDAAkJ2SOVAQBBAwADAAkJ2SOVAQBBAwAAAA==.',
We='Weeabooster:BAAALgAECgUJCQAAAA==.Weiss:BAACLgAFFH8NAAMRAAQJThirKABXAQARAAQJThirKABXAQASAAIJBw6RAQChAAAuAAQKfyoABBEACQldJAcZABUDABEACQmZIwcZABUDABIABgm9I3wDANkBACQAAQmPIMcWAGQAAAAA.Werkz:BAAALgAECgEJAQAAAA==.',
Wi='Wigglebee:BAAALgAECgEJAQAAAA==.',
Wo='Woodyy:BAABLgAECn8UAAIUAAgJ7AUbVABBAQAUAAgJ7AUbVABBAQAAAA==.Woog:BAAALgADCgIJAgAAAA==.Wox:BAAALgAECgUJCAAAAA==.',
Wr='Wreckfest:BAAALgADCgcJCwAAAA==.',
Wy='Wyldspirit:BAAALgAECgYJEAAAAA==.Wyreless:BAAALgADCgYJBgABLgAECggJIwAJAKgTAA==.',
['Wê']='Wêsleypipes:BAAALgADCgYJBwAAAA==.',
Xa='Xampu:BAAALgADCgEJAQAAAA==.',
Ya='Yaass:BAAALgAECgMJAwAAAA==.',
Ye='Yem:BAACLgAFFH8aAAQWAAUJsSGQAQBnAQAWAAQJkRqQAQBnAQAbAAQJ/h9SFABlAQAVAAIJYSLCBQBeAAAuAAQKfzYAAxYACQmjIzcGAGwCABYABgncIzcGAGwCABsABgljI0tJAO4BAAAA.',
Yo='Yoshikawa:BAABLgAECn8YAAIKAAcJvxm2CAAfAgAKAAcJvxm2CAAfAgABLgAFFAMJAwATAAAAAA==.',
Za='Zamoxis:BAAALgAECgMJAwAAAA==.Zant:BAAALgAECgEJAQABLgAECgMJBAATAAAAAA==.Zanzabar:BAAALgAECggJDgAAAA==.Zaraelitha:BAAALgAECgEJAQAAAA==.Zawmbee:BAAALgADCgEJAQAAAA==.',
Ze='Zeldá:BAAALgAECgMJBAAAAA==.Zenhira:BAAALgAECgIJAgAAAA==.Zeodrik:BAABLgAECn8cAAINAAcJXhnxFwCnAQANAAcJXhnxFwCnAQAAAA==.',
Zh='Zhenya:BAACLgAFFH8HAAIRAAMJgRRVRQD/AAARAAMJgRRVRQD/AAAuAAQKfyQAAxEABwlvHRk7ALcBABEABwlvHRk7ALcBACQABAkvD+cOANUAAAAA.',
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
