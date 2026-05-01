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

local lookup = {'Rogue-Assassination','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Priest-Holy','DeathKnight-Frost','DeathKnight-Blood','Druid-Feral','Paladin-Holy','Monk-Windwalker','Warrior-Fury','Paladin-Protection','Paladin-Retribution','DemonHunter-Devourer','Mage-Frost','Unknown-Unknown','DeathKnight-Unholy','Warlock-Affliction','Warlock-Destruction','Priest-Shadow','Druid-Restoration','Druid-Guardian','Monk-Mistweaver','Shaman-Elemental','Warlock-Demonology','DemonHunter-Havoc','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Warrior-Arms','Priest-Discipline','Druid-Balance','DemonHunter-Vengeance','Shaman-Restoration','Mage-Arcane','Monk-Brewmaster','Warrior-Protection','Shaman-Enhancement','Mage-Fire',}
local provider = {region='US',realm='Crushridge',name='US',type='weekly',zone=46,date='2026-05-01',data={Ac='Acheniris:BAAALgAECgUJCgAAAA==.',
Ad='Adeaino:BAAALgAECgEJAwAAAA==.Adrenaline:BAAALgAECgUJCAAAAA==.',
Ae='Aeviee:BAAALgADCgUJBgAAAA==.Aevisandra:BAAALgADCgEJAQAAAA==.',
Ag='Agrippa:BAABLgAECn8aAAIBAAcJjQ+NCQCjAQABAAcJjQ+NCQCjAQAAAA==.',
Ah='Ahndhrez:BAAALgAECgMJAgAAAA==.',
Ai='Aicton:BAAALgAECgIJAgAAAA==.Aidric:BAAALgAECgUJCgAAAA==.Aioli:BAABLgAECn8bAAQCAAgJshy2DgBzAQADAAYJ7hdURwCUAQACAAgJJhm2DgBzAQAEAAUJcRoGSAAzAQAAAA==.Airwavez:BAAALgADCgMJBAAAAA==.',
Al='Alchemorph:BAAALgAECgYJDQAAAA==.Aldormu:BAAALgAECgYJDwAAAA==.Aliyah:BAEALgADCgIJAgABLgAECggJIwAFAJkbAA==.Allura:BAACLgAFFH8HAAIFAAMJzxUeCwDaAAAFAAMJzxUeCwDaAAAuAAQKfx0AAgUACQmeFg4WACwCAAUACQmeFg4WACwCAAAA.Altra:BAABLgAECn8kAAMGAAgJBhpWAgCfAgAGAAgJBhpWAgCfAgAHAAcJewNXKwDkAAAAAA==.Alyvia:BAAALgADCgEJAQAAAA==.',
Am='Amoeta:BAABLgAECn8bAAIIAAgJkBJfBQDDAQAIAAgJkBJfBQDDAQAAAA==.Amorma:BAAALgADCgcJDAAAAA==.Amzod:BAAALgAECgMJAwAAAA==.',
An='Andarian:BAAALgAECgYJCgAAAA==.Andor:BAAALgADCgYJBgAAAA==.Angelique:BAAALgAECgQJCgAAAA==.Angryapples:BAAALgAECgQJCQAAAA==.Antinous:BAABLgAECn8mAAIEAAYJeQ9kCwAZAQAEAAYJeQ9kCwAZAQAAAA==.',
Ar='Arcstorm:BAAALgAECgQJBAAAAA==.Arkimedez:BAAALgADCgMJAwAAAA==.',
As='Asomyrh:BAABLgAECn8XAAIJAAgJ5A5YOwCMAQAJAAgJ5A5YOwCMAQAAAA==.',
At='Atchilis:BAAALgADCgIJAgAAAA==.Atrophy:BAAALgAECgUJBQAAAA==.',
Au='Auliehealz:BAAALgADCgYJBgAAAA==.Aurial:BAAALgADCgEJAQAAAA==.',
Aw='Awakenrobin:BAABLgAECn8iAAIKAAgJLAprKgCKAQAKAAgJLAprKgCKAQAAAA==.',
Az='Azenith:BAAALgAECgYJCwAAAA==.Azzatec:BAAALgADCgcJBwAAAA==.',
Ba='Bahablast:BAAALgAECgEJAQAAAA==.Bakan:BAAALgADCgEJAQAAAA==.Baklava:BAAALgAECgIJAgAAAA==.Bananer:BAABLgAECn8ZAAILAAgJVBFpNgDOAQALAAgJVBFpNgDOAQAAAA==.Banonzarath:BAAALgAECgQJBwAAAA==.Banonzath:BAAALgAECgEJAQAAAA==.Banonzii:BAAALgADCgMJBQAAAA==.Barrysoetoro:BAAALgADCgYJBgAAAA==.Batfred:BAAALgADCgYJBwAAAA==.Batukhan:BAAALgAECggJCgAAAA==.Baulie:BAAALgAECgQJBgAAAA==.',
Be='Beebler:BAAALgAECgYJDQAAAA==.Beebs:BAAALgADCgcJFwAAAA==.Beefstick:BAAALgADCgUJBQAAAA==.Bekroh:BAAALgADCgcJDgAAAA==.Bestt:BAAALgAECgQJBwAAAA==.Bewear:BAAALgADCgcJCgAAAA==.Bezerk:BAAALgADCgEJAQAAAA==.',
Bi='Biceps:BAAALgADCgEJAQAAAA==.Biggestpete:BAAALgAECgUJBgAAAA==.Bigknight:BAAALgADCgcJCgAAAA==.Bigolchungus:BAABLgAECn8dAAMMAAgJhBlsCQA7AgAMAAgJeBlsCQA7AgANAAQJRRaOcgDJAAAAAA==.Bigpapadots:BAAALgADCgYJBgAAAA==.Bippysmasher:BAABLgAECn8gAAIOAAkJJRITLQAwAQAOAAkJJRITLQAwAQAAAA==.Biridie:BAAALgAECgUJCgAAAA==.',
Bl='Blacblood:BAABLgAECn8dAAIGAAgJuhFnAwCVAQAGAAgJuhFnAwCVAQAAAA==.Blade:BAAALgADCgEJAQAAAA==.Blastemis:BAAALgAECgcJDgAAAA==.Bliccy:BAAALgAECgEJAgAAAA==.Blindweiss:BAAALgADCgcJBwABLgAFFAQJCgAPAB4WAA==.Blinkies:BAAALgAECgcJEgAAAA==.Blinkster:BAAALgAECgEJBAAAAA==.',
Bn='Bnr:BAAALgADCgIJAgABLgADCggJEQAQAAAAAA==.',
Bo='Bobby:BAAALgADCgEJAQAAAA==.Bontao:BAACLgAFFH8GAAIDAAUJVRaiCwAFAQADAAUJVRaiCwAFAQAuAAQKfyIAAgMACQn7IXkIAAoDAAMACQn7IXkIAAoDAAAA.Borstenne:BAABLgAECn8kAAIRAAgJ+h+CEwAGAwARAAgJ+h+CEwAGAwAAAA==.',
Br='Brake:BAACLgAFFH8HAAIRAAMJEg3mOQDoAAARAAMJEg3mOQDoAAAuAAQKfyMAAhEACAnKIIcNAFgCABEACAnKIIcNAFgCAAAA.Breseayaya:BAABLgAECn8kAAIOAAgJjCE0BwBoAgAOAAgJjCE0BwBoAgAAAA==.Breseshh:BAAALgAECgYJDAABLgAECggJJAAOAIwhAA==.Brickbeard:BAABLgAECn8gAAMSAAgJRBDcAgCcAQASAAcJexLcAgCcAQATAAcJog3nGQB9AQAAAA==.Brickbow:BAAALgADCgcJDQAAAA==.Brickette:BAAALgAECgYJDAABLgAFFAUJDAANAHMTAA==.Bricksquad:BAAALgAECgMJAwABLgAECggJEwAQAAAAAA==.Brickthrow:BAACLgAFFH8MAAMNAAUJcxNCDQBBAQANAAUJcxNCDQBBAQAJAAEJEgbtGwBNAAAuAAQKfykAAw0ACQnBIf8mAIoCAA0ACAmYIf8mAIoCAAkABQlyBDA7AIIAAAAA.',
Bu='Burgerburn:BAAALgADCgMJAgAAAA==.',
By='Bytheway:BAABLgAECn8UAAIUAAcJoxMrFABhAQAUAAcJoxMrFABhAQAAAA==.',
['Bä']='Bärett:BAAALgADCgcJDgAAAA==.',
Ca='Cadilak:BAABLgAECn8jAAMVAAgJmyKLCACCAgAVAAcJhCSLCACCAgAWAAEJSgGiNwAZAAAAAA==.Cadsune:BAAALgADCgYJCwAAAA==.Caelesti:BAAALgAECgUJCAAAAA==.Calledtowild:BAAALgADCgEJAQAAAA==.Campesino:BAAALgAECgIJAQAAAA==.',
Ch='Chamificador:BAAALgADCgYJBgAAAA==.Chard:BAAALgADCgcJCQAAAA==.Cherrÿ:BAAALgADCgQJBAAAAA==.Chinbearpig:BAAALgADCgEJAQAAAA==.Chowderhead:BAABLgAECn8UAAITAAYJYRwmBQB6AQATAAYJYRwmBQB6AQAAAA==.',
Ci='Cileb:BAACLgAFFH8FAAIPAAUJcxfmGQBgAQAPAAUJcxfmGQBgAQAuAAQKfx0AAg8ACAlrJRwOAFUDAA8ACAlrJRwOAFUDAAAA.Civik:BAABLgAECn8qAAIDAAgJTSDGCQBgAgADAAgJTSDGCQBgAgAAAA==.',
Cl='Cloosaun:BAAALgAECgYJDAABLgAECggJEwAQAAAAAA==.',
Co='Coachstahp:BAAALgADCgcJBwAAAA==.Conchsniffer:BAABLgAECn8wAAINAAkJWRpMFgAJAgANAAkJWRpMFgAJAgAAAA==.Conrack:BAAALgADCgcJDQAAAA==.Coobs:BAAALgADCgcJCgABLgAECgQJBQAQAAAAAA==.Coppercrusad:BAAALgADCgEJAQABLgAECgkJIwAHAAkjAA==.Copperit:BAABLgAECn8jAAIHAAkJCSOPAgBDAwAHAAkJCSOPAgBDAwAAAA==.Cornburglar:BAABLgAECn8kAAILAAgJKSPxCQAQAwALAAgJKSPxCQAQAwAAAA==.Cowtaclysmic:BAAALgAECgYJEgAAAA==.',
Cr='Crackersz:BAAALgAECgcJEAAAAA==.Cranjis:BAABLgAECn8jAAIXAAgJtyEbAwDNAgAXAAgJtyEbAwDNAgAAAA==.Crazydemon:BAAALgAECgcJCwAAAA==.Crazylock:BAAALgAECgEJAQAAAA==.Crunchwrap:BAAALgAECgYJEwAAAA==.Crusaide:BAAALgADCgUJBQAAAA==.Cryola:BAAALgADCgEJAQAAAA==.',
Cu='Cursereflect:BAAALgAECgYJEAAAAA==.Curseus:BAAALgADCgUJBgAAAA==.',
Da='Damncats:BAABLgAECn8ZAAILAAcJJAitJgAKAQALAAcJJAitJgAKAQAAAA==.Dandinn:BAAALgAECgMJAwAAAA==.Danielsboone:BAAALgAECgYJCgAAAA==.Darkangor:BAAALgADCgcJBwAAAA==.Darkansic:BAAALgADCgQJBAAAAA==.Darkmare:BAAALgAECgQJBQABLgAECggJHgAYAFscAA==.Darknemesis:BAAALgADCggJDQAAAA==.Dawnhaven:BAAALgADCgcJBgAAAA==.Daysubb:BAAALgAECgEJAQABLgAFFAQJEAAZAPofAA==.',
De='Deadhippocow:BAAALgAECgUJCQAAAA==.Deathwavez:BAABLgAECn8aAAIRAAcJMBf6ZADFAQARAAcJMBf6ZADFAQAAAA==.Decurse:BAABLgAECn8ZAAIZAAcJexXwKQCGAQAZAAcJexXwKQCGAQAAAA==.Deldrin:BAAALgAECgYJEQAAAA==.Demona:BAABLgAECn8hAAMTAAgJTBXwKQAaAQAZAAcJ4RHvbgCCAQATAAQJ4BPwKQAaAQAAAA==.Demonix:BAAALgAECgYJDgAAAA==.Demonstdfred:BAAALgADCgEJAQAAAA==.Derptron:BAABLgAECn8bAAIPAAcJswwjSQBTAQAPAAcJswwjSQBTAQAAAA==.Devira:BAAALgAECgQJBAAAAA==.',
Di='Diisco:BAAALgADCgcJDgAAAA==.Dillydally:BAAALgAECgQJBAAAAA==.Dilutedret:BAAALgAECgYJCwAAAA==.Dinobrass:BAABLgAECn8XAAIEAAYJ5gnqDAD+AAAEAAYJ5gnqDAD+AAAAAA==.Dirtylöbster:BAACLgAFFH8KAAIPAAMJwh3LJwAUAQAPAAMJwh3LJwAUAQAuAAQKfywAAg8ACAlXJR4FAOoCAA8ACAlXJR4FAOoCAAAA.Disabel:BAAALgAECgUJDQAAAA==.Distracto:BAAALgAECgkJCQAAAA==.',
Dl='Dltdjr:BAAALgAECgUJCAABLgAECgYJCwAQAAAAAA==.',
Do='Dochollíday:BAAALgADCgEJAQAAAA==.Doolittle:BAAALgAECgUJCwAAAA==.Dorose:BAAALgADCggJCgAAAA==.Doublepop:BAAALgAECgYJBwAAAA==.',
Dr='Drewmee:BAAALgAECgYJDQAAAA==.Dronar:BAAALgADCgEJAQABLgAECggJDAAQAAAAAA==.Drublood:BAAALgAECgYJBgABLgAECgYJDQAQAAAAAA==.Drunkinmasta:BAAALgADCgYJBgABLgAFFAMJBgANAHcQAA==.Drwut:BAAALgAECggJDQAAAA==.',
Du='Dune:BAAALgADCgcJBwAAAA==.Duwork:BAAALgAECgYJDQAAAA==.',
Ee='Eekany:BAAALgAECgMJAwAAAA==.',
El='Eladus:BAAALgAECgYJCQAAAA==.Elemnt:BAAALgAECgUJCAABLgAFFAMJBgANAHcQAA==.Elladon:BAAALgAECgQJAwAAAA==.Elmster:BAAALgAECgEJAgAAAA==.',
Em='Emblaze:BAAALgAECgYJCwAAAA==.',
En='Enhshaman:BAAALgAFFAMJAwAAAA==.',
Er='Eremith:BAAALgADCgEJAQAAAA==.',
Es='Essentials:BAAALgAECgMJBAAAAA==.',
Ev='Evacadrabra:BAAALgADCgUJBQAAAA==.',
Ez='Ezkal:BAACLgAFFH8JAAIRAAQJuBSNGgBMAQARAAQJuBSNGgBMAQAuAAQKfysAAxEACQnsGZ4YAOgCABEACQnsGZ4YAOgCAAcABgkoFYwNADcBAAAA.',
Fa='Faithpasse:BAAALgAECgYJDwAAAA==.Falcorne:BAABLgAECn8bAAIDAAcJWx0AFgDiAQADAAcJWx0AFgDiAQAAAA==.',
Fe='Felondar:BAABLgAECn8ZAAMaAAcJPgoqEQAsAQAaAAcJPgoqEQAsAQAOAAYJsASjmwDhAAAAAA==.Felshen:BAAALgADCgUJBQAAAA==.Ferarro:BAABLgAECn8WAAMHAAgJUxwwDABOAgAHAAcJsBswDABOAgARAAcJORmCagC3AQAAAA==.',
Fi='Finnadin:BAAALgAECgUJBwAAAA==.Finns:BAAALgAECgYJDAAAAA==.Firalyn:BAAALgAECgYJDgAAAA==.Firulais:BAAALgAECgYJDgAAAA==.Fistobeef:BAAALgAECgEJAQAAAA==.',
Fl='Fleable:BAAALgADCgMJAwAAAA==.Flysky:BAACLgAFFH8OAAIbAAUJ/Rj7BACeAQAbAAUJ/Rj7BACeAQAuAAQKfyIABBsACQnGI4sCAEcDABsACQnGI4sCAEcDABwAAgnZHCg/AFUAAB0AAQl3DxtBAC4AAAAA.',
Fo='Forrest:BAAALgAECgEJAgAAAA==.Foxsake:BAAALgAECgcJDAAAAA==.',
Fr='Freakmeout:BAAALgADCgkJFQAAAA==.Frostadin:BAAALgADCgEJAQAAAA==.Frostbones:BAAALgAECgUJBgAAAA==.Frostuss:BAAALgADCgUJBQAAAA==.Frözenflames:BAAALgAFFAEJAQAAAA==.',
Fu='Fur:BAAALgADCggJCAAAAA==.Future:BAAALgAECgUJCgAAAA==.Futuredragoo:BAAALgAECgIJAgAAAA==.Fuzzydeeps:BAAALgADCgQJBAAAAA==.',
Ga='Gabriella:BAAALgADCgQJBQAAAA==.Gallardo:BAAALgADCgUJBQABLgAECgUJDQAQAAAAAA==.Galnannix:BAAALgAECgcJDAAAAA==.Gardrake:BAABLgAECn8fAAMbAAkJeBCjHQCWAQAbAAcJUQ+jHQCWAQAcAAkJXhdaEACMAQAAAA==.Gastapha:BAABLgAECn8UAAIOAAcJBQZmSQDJAAAOAAcJBQZmSQDJAAAAAA==.',
Ge='Gearth:BAAALgADCgMJAwAAAA==.Geel:BAABLgAECn8dAAMLAAgJBxMeMADvAQALAAgJBxMeMADvAQAeAAEJAAB1NQAAAAAAAA==.Gehennas:BAAALgAECggJEwAAAA==.Gereck:BAAALgADCgIJAgAAAA==.Gerthsham:BAAALgADCgUJBQAAAA==.',
Go='Goofykirby:BAAALgADCgcJFQAAAA==.Googoogagaa:BAACLgAFFH8KAAIUAAMJGRPkCwABAQAUAAMJGRPkCwABAQAuAAQKfzoAAxQACQmtGh4DAJACABQACQmtGh4DAJACAAUABwnyEv4pAKIBAAAA.Gotlieb:BAAALgADCgEJAQAAAA==.',
Gr='Griffith:BAAALgADCgEJAgAAAA==.Grimghor:BAAALgADCgYJBgAAAA==.Groggasan:BAAALgADCgYJBgABLgADCgcJDQAQAAAAAA==.Groggfather:BAAALgADCgcJDQAAAA==.Gronhal:BAAALgADCgQJBAAAAA==.Groundz:BAAALgADCgYJBgAAAA==.Grrahtahtah:BAACLgAFFH8VAAMEAAYJFRdKBwCnAQAEAAYJFRdKBwCnAQACAAMJQgz5DgCrAAAuAAQKfxQAAgQABwkJJLERAKgCAAQABwkJJLERAKgCAAAA.Grävyy:BAAALgAECggJEgAAAA==.',
Gy='Gyrozug:BAAALgAECggJEwAAAA==.',
Ha='Hammerinfred:BAAALgAECgMJAwAAAA==.',
He='Healingisfun:BAAALgAECgMJAwAAAA==.Helhunter:BAABLgAECn8eAAIOAAgJ9xGkIgBkAQAOAAgJ9xGkIgBkAQAAAA==.Hellock:BAAALgAECgIJAgAAAA==.',
Hi='Hippysmasher:BAAALgAECgIJAgAAAA==.',
Ho='Hohk:BAAALgAECgIJAgAAAA==.Holden:BAAALgAECgIJAgAAAA==.Holyapostle:BAAALgAECgEJAQAAAA==.Holyhooters:BAABLgAECn8gAAINAAgJPCGYDABhAgANAAgJPCGYDABhAgAAAA==.Holypablo:BAAALgADCgcJDQABLgAECgkJKgAfAAQeAA==.Homefries:BAAALgADCgYJBgAAAA==.Honkytonk:BAABLgAECn8ZAAMdAAgJKAs+IgAYAQAdAAYJ7Qk+IgAYAQAcAAcJcQmpOAATAQAAAA==.Honour:BAABLgAECn8hAAINAAgJrCAwDABmAgANAAgJrCAwDABmAgAAAA==.',
Hr='Hrathdemon:BAABLgAECn8kAAIOAAgJWB0JCwAsAgAOAAgJWB0JCwAsAgAAAA==.Hrathid:BAAALgADCgUJDAABLgAECggJJAAOAFgdAA==.',
Hu='Huntermik:BAAALgADCgcJBwAAAA==.Hupa:BAACLgAFFH8HAAINAAMJiiDrFAAtAQANAAMJiiDrFAAtAQAuAAQKfyMAAg0ACAm3JbgFAHIDAA0ACAm3JbgFAHIDAAAA.Husk:BAAALgADCgEJAQAAAA==.',
Ia='Iamheyo:BAAALgAECgcJEAAAAA==.',
Ib='Ibleedorange:BAAALgAECgQJBAAAAA==.',
Ic='Ickeetard:BAAALgAECgYJDwAAAA==.',
Id='Idiot:BAAALgAECgEJAQAAAA==.Idiotbreath:BAABLgAECn8tAAMcAAgJXSA+AwCgAgAcAAgJXSA+AwCgAgAdAAMJmQl9MACTAAAAAA==.',
Ie='Ieatcheeks:BAAALgADCgYJBgAAAA==.',
Ig='Iglooshocker:BAEBLgAFFH8FAAIYAAMJewbHEQDbAAAYAAMJewbHEQDbAAAAAA==.',
Im='Immorlich:BAAALgADCgcJBwAAAA==.Imonaship:BAAALgADCgcJBwAAAA==.',
In='Infari:BAAALgADCgYJBwAAAA==.Inflexi:BAAALgAECggJEgAAAA==.Inky:BAAALgADCgYJBwAAAA==.',
Ip='Ipriest:BAAALgADCgYJBgAAAA==.',
Is='Is:BAAALgAECgYJDgAAAA==.',
It='Itsmagharszn:BAAALgADCgQJBAAAAA==.Itsthereaper:BAABLgAECn8tAAQgAAgJ+B0wFQBnAgAgAAgJ6h0wFQBnAgAVAAgJnR0ECwBYAgAWAAMJ0hYlDwDGAAAAAA==.',
Iv='Iver:BAAALgAECgEJAQABLgAECgcJDQAQAAAAAA==.',
Ja='Jangle:BAAALgADCgYJBwAAAA==.',
Jh='Jhana:BAAALgADCgIJAgABLgAECgMJBgAQAAAAAA==.',
Jj='Jjooaacchhim:BAAALgADCgIJAgAAAA==.',
Jy='Jyve:BAABLgAECn8ZAAIDAAkJ7RYgIgA4AgADAAkJ7RYgIgA4AgAAAA==.',
Ka='Kairei:BAAALgAECgUJCwAAAA==.Kalda:BAAALgAECgEJAgAAAA==.Kalor:BAAALgADCgQJBAAAAA==.Kamadan:BAAALgAECgUJBQAAAA==.Kamanactali:BAAALgAECgUJCgAAAA==.Kaneko:BAAALgAECgUJCgABLgAECgcJGAAWAL8ZAA==.Katalina:BAABLgAECn8fAAMhAAgJMg26BgBZAQAhAAgJsgu6BgBZAQAaAAYJUwoKOAAlAQAAAA==.Kawer:BAAALgAECgQJCAAAAA==.',
Ke='Kelstormhoof:BAAALgADCgcJEwABLgADCggJDQAQAAAAAA==.Kernel:BAAALgAECgEJAQABLgAECggJJAALACkjAA==.',
Kh='Kham:BAACLgAFFH8GAAILAAMJihrYDgAPAQALAAMJihrYDgAPAQAuAAQKfzEAAgsACAmcItsCAKwCAAsACAmcItsCAKwCAAAA.',
Ki='Killmaim:BAABLgAECn8ZAAILAAgJwRlpIABPAgALAAgJwRlpIABPAgAAAA==.Kitsuko:BAABLgAECn8kAAMiAAkJKAxzGwCIAQAiAAkJKAxzGwCIAQAYAAgJqg4NFwBcAQAAAA==.',
Kl='Klais:BAAALgAECgQJBAAAAA==.',
Ku='Kuani:BAAALgADCgkJCQAAAA==.Kuraishin:BAAALgADCgcJBwABLgAFFAQJCgAPAB4WAA==.',
['Kë']='Këltön:BAAALgAECgEJAQAAAA==.',
La='Lazycouch:BAAALgADCgUJBQAAAA==.',
Le='Leadzorz:BAAALgAECgUJCwAAAA==.Leaok:BAAALgADCgEJAQAAAA==.Learingcentr:BAAALgAECgMJAwAAAA==.Lechuza:BAAALgAECgEJAQAAAA==.Leedaddydk:BAAALgAECgMJAwAAAA==.Leroyjenkins:BAABLgAECn8XAAIjAAcJ8BvpAgBVAgAjAAcJ8BvpAgBVAgAAAA==.Lesaelia:BAAALgADCgYJBgAAAA==.',
Li='Linø:BAAALgAECgEJAQAAAA==.Lissara:BAAALgAECgYJBgAAAA==.Liv:BAAALgAECgMJBAAAAA==.Lizzymonk:BAABLgAECn8eAAIkAAgJWh9nDgCvAgAkAAgJWh9nDgCvAgAAAA==.',
Lo='Loa:BAAALgADCgYJBwAAAA==.Lockwerk:BAAALgAECgcJBQABLgAECgcJFwADAOkiAA==.',
Lu='Luckfist:BAAALgAECgYJCQABLgAECgcJFwASANQjAA==.Luminouslexi:BAAALgADCgUJBwAAAA==.',
Ma='Macoub:BAAALgAECgQJBQAAAA==.Macuahuitl:BAAALgADCgYJBgAAAA==.Maddog:BAABLgAECn8UAAMTAAcJ6gP7EgCPAAATAAcJcAP7EgCPAAAZAAMJvARJkgBbAAAAAA==.Mageslayer:BAAALgAECgYJDgAAAA==.Magicichin:BAAALgADCgcJCgAAAA==.Magistaer:BAAALgADCgMJAwAAAA==.Magmanuts:BAAALgAECgUJBQABLgAECgYJBgAQAAAAAA==.Makkideez:BAAALgAECgEJAQAAAA==.Manabuns:BAABLgAECn8bAAIPAAgJ7BUPMwCYAQAPAAgJ7BUPMwCYAQAAAA==.Mandrro:BAAALgADCgkJDAAAAA==.Marfa:BAABLgAECn8fAAINAAgJ6RV4KgCYAQANAAgJ6RV4KgCYAQAAAA==.Markruffalo:BAAALgADCgEJAQAAAA==.Mathias:BAAALgAECgMJAwAAAA==.Mavrik:BAABLgAECn8dAAILAAgJwhKFDgDNAQALAAgJwhKFDgDNAQAAAA==.',
Mc='Mckay:BAAALgAECggJDwAAAA==.Mckáy:BAAALgADCgYJBAAAAA==.Mckäy:BAAALgAECgQJBAAAAA==.Mckåy:BAAALgADCgQJBAAAAA==.',
Me='Meatmagic:BAABLgAECn8gAAIjAAcJcBVOAgClAQAjAAcJcBVOAgClAQAAAA==.Megapunk:BAAALgADCggJGQAAAA==.Mellmaan:BAAALgADCgYJBgAAAA==.Melys:BAAALgAECgYJCwAAAA==.Mercenar:BAAALgADCgEJAQAAAA==.Meteorite:BAAALgAECgEJAQAAAA==.Meudayr:BAAALgAECggJDAAAAA==.Mevoker:BAAALgADCgcJBwAAAA==.',
Mi='Millarolly:BAAALgADCgUJBQAAAA==.Mindkawntrol:BAAALgAECgQJBAAAAA==.Mirari:BAABLgAECn8eAAIYAAgJWxwiEgCSAgAYAAgJWxwiEgCSAgAAAA==.',
Mo='Moistblanket:BAAALgAECgIJAgAAAA==.Mojorisin:BAABLgAECn8XAAICAAgJ1hy5BwB1AgACAAgJ1hy5BwB1AgAAAA==.Moonchiken:BAAALgAECgEJBAAAAA==.Mooserohdah:BAAALgAECgIJAgAAAA==.Moozlock:BAABLgAECn8dAAIZAAgJmxAzKgCFAQAZAAgJmxAzKgCFAQAAAA==.Moscovio:BAAALgAFFAEJAgAAAA==.Mosspaws:BAABLgAECn8tAAMVAAgJsiRiBgAmAwAVAAgJsiRiBgAmAwAgAAQJXx8jFABjAQAAAA==.',
Mt='Mtndewyou:BAAALgADCgEJAQAAAA==.',
Mu='Murderinc:BAAALgADCgMJAwAAAA==.',
My='Myeyes:BAAALgAECgYJCgAAAA==.',
Na='Narfiy:BAAALgADCgEJAQAAAA==.',
Ni='Nickimihoj:BAAALgAECgQJBQAAAA==.',
Nm='Nme:BAABLgAECn8cAAMPAAgJ5Q2fNgCLAQAPAAgJVQyfNgCLAQAjAAYJVA9KCQBWAQAAAA==.',
No='Nocturnos:BAABLgAECn8hAAMZAAgJxh1SDwAuAgAZAAgJxh1SDwAuAgASAAEJUB95LABGAAAAAA==.Noggin:BAABLgAECn8iAAIJAAgJziQzAgD+AgAJAAgJziQzAgD+AgAAAA==.Nonform:BAABLgAECn8rAAMgAAkJGhmvBQBOAgAgAAkJGhmvBQBOAgAVAAEJdAH66wAXAAAAAA==.Noodles:BAAALgADCgYJFAABLgAECgYJEgAQAAAAAA==.Noskillidan:BAAALgADCgMJAwABLgAECgUJCQAQAAAAAA==.Noxta:BAAALgAECgYJCQAAAA==.',
Nu='Numonixx:BAACLgAFFH8OAAMdAAQJcAn9AQAQAQAdAAQJ5Qf9AQAQAQAcAAQJ4wWwEwANAQAuAAQKfx0AAx0ACAmEG6UJAEUCAB0ACAmEG6UJAEUCABwAAQmbB/FIADEAAAAA.Nutlessfred:BAAALgADCgYJBgAAAA==.',
Ny='Nymage:BAABLgAECn8tAAIPAAgJsxNCKQDAAQAPAAgJsxNCKQDAAQAAAA==.',
Og='Ogg:BAAALgADCgMJAwAAAA==.Ogmund:BAAALgADCgEJAQAAAA==.',
Oh='Ohnospiders:BAABLgAECn8YAAIRAAcJjxTYLwB7AQARAAcJjxTYLwB7AQAAAA==.Ohpig:BAAALgADCgYJCgAAAA==.',
Ok='Okaerisan:BAAALgAECgYJDwAAAA==.',
Om='Omgbbqq:BAAALgAECgIJAgABLgAECggJIQADAFYkAA==.',
Oo='Oomi:BAAALgAECgEJAQAAAA==.',
Op='Ophil:BAAALgAECgQJBAAAAA==.',
Or='Orack:BAAALgAECgYJCQAAAA==.Orcrot:BAAALgAECgYJBgAAAA==.',
Ou='Outlast:BAACLgAFFH8GAAINAAMJdxBiHwD5AAANAAMJdxBiHwD5AAAuAAQKfygAAg0ACQk7HbQRAAQDAA0ACQk7HbQRAAQDAAAA.',
Pa='Paants:BAABLgAECn8YAAIlAAcJdw3FEgD9AAAlAAcJdw3FEgD9AAAAAA==.Pacidlol:BAAALgADCgMJBAAAAA==.Palebull:BAAALgADCgQJBQAAAA==.Palonixx:BAAALgAECgEJAQAAAA==.Panblind:BAACLgAFFH8LAAIOAAUJuSDDDwA8AQAOAAUJuSDDDwA8AQAuAAQKfykAAg4ACQmkI1YJAEQCAA4ACQmkI1YJAEQCAAAA.Parmigiano:BAAALgADCgEJAQABLgAECggJGQACAPMTAA==.Parms:BAABLgAECn8ZAAQCAAgJ8xNQCwCsAQACAAgJ4xFQCwCsAQAEAAYJhQweTQAcAQADAAIJORASowCFAAAAAA==.',
Pe='Peanought:BAABLgAECn8bAAMGAAgJIBcABgDJAQAGAAgJIBcABgDJAQARAAYJWAitvQAHAQAAAA==.Peidro:BAABLgAECn8UAAINAAcJqwvZSwAnAQANAAcJqwvZSwAnAQAAAA==.Pentacles:BAABLgAECn8kAAIWAAgJnCIpAwDiAgAWAAgJnCIpAwDiAgAAAA==.',
Pi='Pijak:BAAALgAECgUJCwAAAA==.Pinkpaw:BAAALgAECgUJBgAAAA==.',
Pl='Pleo:BAAALgAECgcJBwAAAA==.',
Po='Poah:BAABLgAFFH8IAAMkAAMJ3iTtCABGAQAkAAMJ3iTtCABGAQAKAAEJZwt6FwBKAAAAAA==.Poahsham:BAAALgAECgEJAgABLgAFFAMJCAAkAN4kAA==.Potatoes:BAABLgAECn8VAAMTAAgJBgiZHABpAQATAAgJBgiZHABpAQAZAAIJCQI4FAE6AAAAAA==.',
Pr='Pruflas:BAABLgAECn8ZAAIRAAgJZAtJLQCGAQARAAgJZAtJLQCGAQAAAA==.',
Ps='Psycodk:BAAALgAECgYJDwAAAA==.',
Pu='Pumpin:BAAALgAECgQJEgAAAA==.Purplemonstr:BAAALgADCgUJBQAAAA==.',
Qk='Qkn:BAAALgAECgUJCgAAAA==.',
Qu='Quickswipe:BAAALgAECgcJDAABLgAFFAQJEAAZAPofAA==.',
Qx='Qx:BAAALgAECgIJAgAAAA==.',
Ra='Raballa:BAAALgADCgUJBQAAAA==.Rafraff:BAAALgADCgUJBQAAAA==.Ralee:BAAALgADCgIJAgAAAA==.Randomhero:BAAALgADCgkJCQAAAA==.Rannt:BAAALgADCgcJBwAAAA==.Rashek:BAAALgADCgEJAQAAAA==.Raynne:BAAALgAECgIJAgAAAA==.',
Re='Reaperjoe:BAAALgAECgQJBAAAAA==.Rehab:BAAALgAECggJEAAAAA==.Rehna:BAAALgAECgYJBgABLgAFFAMJBwAFAM8VAA==.Rektributio:BAACLgAFFH8WAAINAAYJ9SOCAAAwAgANAAYJ9SOCAAAwAgAuAAQKfzAAAg0ACQkeJYUAAHEDAA0ACQkeJYUAAHEDAAAA.Revalation:BAABLgAECn8WAAIVAAgJRh7gHgBIAgAVAAgJRh7gHgBIAgAAAA==.',
Rh='Rhisis:BAAALgADCgUJBQABLgAECgQJCgAQAAAAAA==.Rhyss:BAAALgAECgMJAwAAAA==.',
Ri='Rigorpumpis:BAAALgAECgQJBQAAAA==.',
Ro='Roadblock:BAAALgAECgUJEQAAAA==.Roadtrip:BAAALgAECgMJAwAAAA==.Roadtripsx:BAAALgAECgMJAwAAAA==.Roadtripxxds:BAAALgAECgEJAgAAAA==.Roboorc:BAAALgAECgEJAQAAAA==.Rottingslow:BAAALgAECgIJAwAAAA==.',
Sa='Saragos:BAAALgADCgcJBgABLgAFFAQJCgAPAB4WAA==.Saucerdote:BAABLgAECn8WAAMUAAgJVQl+FABeAQAUAAgJVQl+FABeAQAfAAIJ2wCzXQAnAAAAAA==.',
Sc='Schnee:BAAALgADCgYJBgABLgAFFAQJCgAPAB4WAA==.Scythefrah:BAAALgAECgUJBAAAAA==.',
Se='Selinfinite:BAABLgAECn8TAAIOAAgJfRgFEgDcAQAOAAgJfRgFEgDcAQAAAA==.Selkie:BAABLgAECn8WAAImAAcJjQkSCgBFAQAmAAcJjQkSCgBFAQAAAA==.',
Sh='Shambeau:BAAALgADCgQJBAAAAA==.Shamshielder:BAEBLgAECn8gAAMHAAcJHiGKBgC/AQAHAAcJHiGKBgC/AQARAAEJvAkRxQAtAAABLgAFFAMJBQAYAHsGAA==.Sharick:BAAALgAECgEJAQAAAA==.Shawlee:BAABLgAECn8mAAMiAAgJzBBVIgBUAQAiAAgJzBBVIgBUAQAYAAUJIwZNXgDKAAAAAA==.Sheezie:BAABLgAECn8XAAIiAAYJdhpFGwCJAQAiAAYJdhpFGwCJAQAAAA==.Shellter:BAAALgAECgEJAQABLgAECgcJEgAQAAAAAA==.Shellwit:BAAALgAECgMJBgABLgAECgcJEgAQAAAAAA==.Shetmage:BAACLgAFFH8LAAIPAAUJxgfIIwAoAQAPAAUJxgfIIwAoAQAuAAQKfx8AAg8ACQkSHrcqAMgCAA8ACQkSHrcqAMgCAAAA.Shettrah:BAAALgAECgYJDAABLgAFFAUJCwAPAMYHAA==.Shockybalboa:BAAALgADCgcJBwAAAA==.Shorttbuss:BAAALgAECgYJEQAAAA==.Shuck:BAAALgAECgMJAQABLgAECggJJAALACkjAA==.Shunsui:BAAALgAECgEJAQAAAA==.',
Si='Siickboy:BAAALgAECgMJBQAAAA==.Sijious:BAAALgAECgEJAQAAAA==.Silveah:BAAALgADCgEJAQAAAA==.Simperhi:BAAALgAECgEJAQAAAA==.Sinclear:BAAALgADCgYJCQAAAA==.',
Sk='Skora:BAAALgADCgIJAgABLgAECggJHwANAOkVAA==.Skyland:BAAALgADCgcJDQAAAA==.Skyli:BAAALgAECgUJCAABLgAECgkJGAAiAGodAA==.',
Sl='Slush:BAAALgAECgIJAgAAAA==.',
Sn='Snuph:BAAALgAECgQJCgAAAA==.',
So='Somi:BAABLgAECn8jAAIJAAgJWCC7CADjAgAJAAgJWCC7CADjAgAAAA==.Sorrie:BAAALgAECgEJAQAAAA==.',
Sp='Spud:BAAALgADCgcJBwAAAA==.Spyroh:BAABLgAECn8bAAQcAAYJzxJqGQAyAQAdAAYJcBDqGQBlAQAcAAUJ/BFqGQAyAQAbAAEJ2wAqTwAeAAAAAA==.',
Ss='Ssohl:BAAALgAECgUJDgABLgAFFAMJBwAFAM8VAA==.',
St='Stankydk:BAACLgAFFH8LAAMRAAUJ1hZkGgA8AQARAAQJ1hZkGgA8AQAHAAEJAACyJgAAAAAuAAQKfygAAhEACQn6IIQnAJ0CABEACQn6IIQnAJ0CAAAA.Stankyleg:BAAALgADCgcJDQAAAA==.Stankymage:BAAALgADCgUJBAAAAA==.Steakhead:BAAALgAECgUJBQAAAA==.Stinkbombs:BAABLgAFFH8HAAIPAAQJJwPqLAAWAQAPAAQJJwPqLAAWAQAAAA==.Stinkerz:BAAALgAECgIJAgABLgAECgcJEgAQAAAAAA==.Stunanddone:BAAALgAECgQJBwAAAA==.',
Su='Sumdragon:BAAALgADCgEJAQAAAA==.Sunlest:BAAALgADCgcJCgAAAA==.Supreme:BAACLgAFFH8FAAIOAAMJMRrJGwD/AAAOAAMJMRrJGwD/AAAuAAQKfxgAAg4ACAmcIm4YAMMCAA4ACAmcIm4YAMMCAAAA.',
Sw='Swaayshooter:BAAALgAFFAIJAgAAAA==.',
Sy='Sydios:BAAALgADCgUJBQABLgAFFAQJCgAFAFYOAA==.Sylphrena:BAABLgAECn8jAAIFAAgJKCCNCADDAgAFAAgJKCCNCADDAgAAAA==.',
['Sí']='Sínful:BAABLgAECn8fAAIEAAgJeBwdAgA8AgAEAAgJeBwdAgA8AgAAAA==.',
Ta='Tahwe:BAAALgADCgcJBwAAAA==.Talethen:BAAALgAECgcJEwAAAA==.Talla:BAABLgAECn8YAAIiAAkJah2qGgBCAgAiAAkJah2qGgBCAgAAAA==.Tammey:BAAALgADCgcJBwAAAA==.',
Te='Telaragehoof:BAAALgADCgkJHQAAAA==.Tellus:BAAALgADCgcJCQAAAA==.Tewshort:BAAALgAECgQJCQABLgAFFAMJBgANAHcQAA==.',
Th='Thatbox:BAAALgAECgEJAQAAAA==.Thdon:BAAALgADCgIJAgAAAA==.Thedrood:BAAALgAECgQJCQAAAA==.Themlgyeet:BAAALgADCgEJAQAAAA==.Thiccfists:BAAALgAECgcJEgAAAA==.Thorfyna:BAABLgAECn8YAAIhAAcJExIVCAAxAQAhAAcJExIVCAAxAQAAAA==.Threzk:BAABLgAECn8dAAITAAgJSw6PBgBRAQATAAgJSw6PBgBRAQAAAA==.Thunderclap:BAAALgADCgIJAgAAAA==.',
Ti='Tiderias:BAAALgAECgEJAQAAAA==.',
To='Toekin:BAAALgAECgUJBQAAAA==.Tohk:BAACLgAFFH8KAAIOAAQJaRZTEAA6AQAOAAQJaRZTEAA6AQAuAAQKfyUAAg4ACQkGIcgSAOkCAA4ACQkGIcgSAOkCAAAA.Tontiamat:BAABLgAECn8jAAMcAAgJqhT6CgDZAQAcAAgJqhT6CgDZAQAdAAYJawo6IAAsAQAAAA==.Tontier:BAAALgAECgUJCAABLgAECggJIwAcAKoUAA==.Totembeans:BAAALgAECgQJCwAAAA==.',
Tr='Tralidoris:BAAALgADCgEJAQAAAA==.Trashen:BAAALgAFFAQJBAABLgAFFAQJCgAFAFYOAA==.Trashfire:BAACLgAFFH8KAAMFAAQJVg7/BQA+AQAFAAQJVg7/BQA+AQAfAAIJwgFtFgB7AAAuAAQKfx0ABAUACAkWHSgQAGUCAAUACAkWHSgQAGUCABQABQknFXg2ADkBAB8AAwluEWNAAK0AAAAA.Treeple:BAABLgAECn8YAAIVAAcJFxMPIwBqAQAVAAcJFxMPIwBqAQAAAA==.Treily:BAAALgAECgMJBQAAAA==.Tresleches:BAABLgAECn8YAAINAAcJHQ8vRgA3AQANAAcJHQ8vRgA3AQAAAA==.Tricket:BAABLgAECn8kAAMeAAgJCRntBgBWAgAeAAgJpBjtBgBWAgALAAUJfxlEVQBWAQAAAA==.Trousers:BAAALgAECgYJBgABLgAECggJFQATAAYIAQ==.Truestorm:BAABLgAECn8gAAINAAgJRAvHNgBoAQANAAgJRAvHNgBoAQAAAA==.Truheals:BAAALgADCgkJEwAAAA==.',
Tu='Tuchi:BAACLgAFFH8NAAIPAAUJzBcxHQBZAQAPAAUJzBcxHQBZAQAuAAQKfxwAAw8ABwliIrgyAKgCAA8ABwliIrgyAKgCACMAAglBBa0YAFMAAAAA.Tussin:BAAALgADCgEJAQAAAA==.',
Tw='Tweedlepan:BAAALgADCgcJDQABLgAFFAUJCwAOALkgAA==.',
['Tà']='Tàcobelle:BAAALgADCgYJBwABLgAECggJGwAPAOwVAA==.',
Up='Uptownpimp:BAAALgAECgEJAgAAAA==.',
Va='Valandral:BAAALgADCgEJAQAAAA==.Valdor:BAAALgADCgEJAQABLgAECgIJAgAQAAAAAA==.Valyarn:BAAALgADCgcJBwAAAA==.Vanicton:BAACLgAFFH8HAAIiAAMJsSLJDQAiAQAiAAMJsSLJDQAiAQAuAAQKfyoAAyIACAmGHUQSAIQCACIACAmGHUQSAIQCABgABAmZGBUdAC0BAAAA.Varanis:BAACLgAFFH8IAAIDAAMJlhZvDAD/AAADAAMJlhZvDAD/AAAuAAQKfxcAAgMACAkLImYLAOgCAAMACAkLImYLAOgCAAAA.',
Ve='Vegh:BAABLgAECn8rAAIhAAkJVhtEAQB0AgAhAAkJVhtEAQB0AgAAAA==.Vem:BAABLgAECn8XAAIcAAgJxB4mEAB2AgAcAAgJxB4mEAB2AgAAAA==.Veriale:BAAALgAECgUJBQAAAA==.Verra:BAAALgAECgYJEwAAAA==.',
Vi='Vitriol:BAAALgAECgYJEwAAAA==.',
Vo='Voidbeaver:BAAALgAECgQJBAAAAA==.Voidfent:BAAALgADCgEJAQAAAA==.Voidluck:BAABLgAECn8XAAISAAcJ1COsAQDKAgASAAcJ1COsAQDKAgAAAA==.',
Vy='Vynlaeron:BAAALgADCgkJEgABLgAECgYJCQAQAAAAAA==.Vyrros:BAAALgADCgUJBQAAAA==.',
Wa='Walji:BAABLgAECn8eAAMiAAgJzht1FwBaAgAiAAgJzht1FwBaAgAYAAEJVQsSUgAxAAAAAA==.Wampa:BAAALgADCgcJDgAAAA==.Wanderblue:BAAALgADCgQJBQAAAA==.Wandy:BAABLgAECn8eAAIZAAcJVxCFaQCQAQAZAAcJVxCFaQCQAQAAAA==.Wangstah:BAABLgAECn8XAAIDAAcJ6SJlCQBmAgADAAcJ6SJlCQBmAgAAAA==.Warblades:BAAALgADCgEJAQAAAA==.Wargloves:BAABLgAECn8bAAILAAYJMRSIIQArAQALAAYJMRSIIQArAQAAAA==.Warmslippers:BAAALgAECgYJCgAAAA==.Wataa:BAAALgADCgQJBAAAAA==.Wavez:BAAALgAECgcJCAAAAA==.Wawatési:BAAALgAECgMJAwAAAA==.Waytogoteam:BAABLgAECn8hAAIDAAgJViT3AwDEAgADAAgJViT3AwDEAgAAAA==.',
We='Weeabooster:BAAALgAECgUJCQAAAA==.Weiss:BAACLgAFFH8KAAMPAAQJHhbwMAAIAQAPAAQJTRXwMAAIAQAnAAIJAg4KAQCmAAAuAAQKfykABA8ACQk0JAcZABUDAA8ACQlxIwcZABUDACcABgm9I30DANkBACMAAQmPIMgWAGQAAAAA.Werkz:BAAALgAECgEJAQAAAA==.',
Wi='Wigglebee:BAAALgAECgEJAQAAAA==.',
Wo='Woodyy:BAAALgAECgkJDQAAAA==.Woog:BAAALgADCgEJAQAAAA==.Wox:BAAALgAECgQJBAAAAA==.',
Wr='Wreckfest:BAAALgADCgcJCwAAAA==.',
Wy='Wyldspirit:BAAALgAECgYJCgAAAA==.Wyreless:BAAALgADCgYJBgABLgAECggJGwAIAJASAA==.',
['Wê']='Wêsleypipes:BAAALgADCgYJBwAAAA==.',
Xa='Xampu:BAAALgADCgEJAQAAAA==.',
Ye='Yem:BAACLgAFFH8QAAMZAAQJ+h8uCgCBAQAZAAQJ+h8uCgCBAQATAAEJtBXMCwBcAAAuAAQKfzYAAxMACQmjIzcGAGwCABMABgncIzcGAGwCABkABgljI1JJAO4BAAAA.',
Yo='Yoshikawa:BAABLgAECn8YAAIWAAcJvxm1CAAfAgAWAAcJvxm1CAAfAgAAAA==.',
Za='Zamoxis:BAAALgAECgMJAwAAAA==.Zant:BAAALgAECgEJAQABLgAECgMJBAAQAAAAAA==.Zanzabar:BAAALgAECggJDgAAAA==.Zaraelitha:BAAALgAECgEJAQAAAA==.Zawmbee:BAAALgADCgEJAQAAAA==.',
Ze='Zeldá:BAAALgAECgMJBAAAAA==.Zenhira:BAAALgAECgIJAgAAAA==.Zeodrik:BAABLgAECn8VAAILAAYJMBwzGABuAQALAAYJMBwzGABuAQAAAA==.',
Zh='Zhenya:BAABLgAECn8iAAMPAAcJAhw0LwCmAQAPAAcJAhw0LwCmAQAjAAQJLw/pDgDVAAAAAA==.',
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
