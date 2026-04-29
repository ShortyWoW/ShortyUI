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

local lookup = {'Shaman-Enhancement','Hunter-Marksmanship','Unknown-Unknown','DemonHunter-Havoc','DemonHunter-Devourer','Druid-Restoration','Evoker-Augmentation','Evoker-Devastation','Priest-Shadow','Priest-Discipline','Hunter-Survival','Hunter-BeastMastery','Rogue-Subtlety','Mage-Frost','DeathKnight-Unholy','Warrior-Fury','Paladin-Protection','Shaman-Restoration','Shaman-Elemental','Mage-Fire','Warrior-Arms','Druid-Balance','Warrior-Protection','Warlock-Destruction','Warlock-Demonology','Paladin-Holy','DeathKnight-Blood','Rogue-Assassination','Druid-Guardian','DeathKnight-Frost','Paladin-Retribution','Monk-Mistweaver','Monk-Windwalker','Monk-Brewmaster','Warlock-Affliction','Rogue-Outlaw','Priest-Holy','Druid-Feral','Evoker-Preservation',}
local provider = {region='US',realm='Moonrunner',name='US',type='weekly',zone=46,date='2026-04-24',data={Ac='Acense:BAAALgAECgMJBQAAAA==.Acewing:BAAALgADCgkJCgAAAA==.Acidlock:BAAALgAECgEJAQAAAA==.Acidpriest:BAAALgAECgYJCQAAAA==.Acidshaman:BAAALgADCgYJBwAAAA==.',
Ad='Adacey:BAAALgAECgEJAQAAAA==.Adragon:BAAALgAECgYJCgAAAA==.',
Ae='Aedryll:BAAALgAECgYJDQAAAA==.Aeriden:BAAALgAECgEJAQAAAA==.Aesuga:BAABLgAECn8jAAIBAAgJmCDIAABjAgABAAgJmCDIAABjAgAAAA==.Aethelflaed:BAAALgAECgQJDgAAAA==.',
Ag='Agnolotti:BAAALgAECgUJCAAAAA==.',
Ai='Aimedjupiter:BAAALgAECgYJEQABLgAFFAMJBQACAL0ZAA==.Air:BAAALgADCgcJBwABLgAECgYJEgADAAAAAA==.Airlyn:BAAALgAECgQJBAAAAA==.',
Ak='Aktras:BAAALgAECgUJCgAAAA==.',
Al='Alaunu:BAAALgADCgkJBgAAAA==.Aleas:BAAALgADCgcJGAAAAA==.Alkaid:BAAALgAECgEJAQAAAA==.Alndvia:BAAALgAECgYJCgAAAA==.Alponknuts:BAAALgAECgUJCQAAAA==.Alponkster:BAAALgADCggJEwABLgAECgUJCQADAAAAAA==.Alunia:BAAALgAECgEJAQAAAA==.Alytheal:BAAALgAECgEJAQAAAA==.',
Am='Americow:BAAALgADCggJCwAAAA==.',
An='Anarky:BAAALgAECgkJEAAAAA==.Andarnah:BAAALgADCgQJBAAAAA==.Annunaki:BAAALgAECgIJAwAAAA==.Anthrfinpete:BAAALgAECgIJBQABLgAECgcJCwADAAAAAA==.',
Ar='Arathenes:BAAALgADCgcJCQAAAA==.Archae:BAAALgADCgEJAQAAAA==.Archdemon:BAAALgAECgMJBAAAAA==.Ariannette:BAAALgAECgMJAwAAAA==.Arilyn:BAAALgADCgMJAwAAAA==.Arkhanx:BAAALgAECgMJAwAAAA==.Artemisia:BAAALgADCggJDgAAAA==.Artichoke:BAABLgAECn8UAAMEAAcJKxDzKwBpAQAEAAYJ+hHzKwBpAQAFAAMJLAV11QBGAAAAAA==.',
As='Ashamane:BAAALgADCgQJBwABLgAECgMJAwADAAAAAA==.Ashanara:BAAALgADCgEJAQABLgAECgYJDgADAAAAAA==.Ashy:BAAALgADCgUJBQAAAA==.Astrov:BAAALgAECgcJDgAAAA==.',
At='Athera:BAAALgADCggJCAAAAA==.',
Au='Auani:BAABLgAECn8aAAIGAAgJViPSAAASAwAGAAgJViPSAAASAwAAAA==.Augtistic:BAABLgAECn8gAAMHAAgJDxqXEgBVAgAHAAgJDxqXEgBVAgAIAAMJwRfOKwC+AAAAAA==.Aurani:BAAALgAECgEJAQAAAA==.',
Ay='Ayanna:BAAALgADCgkJFAAAAA==.',
Az='Azale:BAAALgAECgMJAwAAAA==.Azulagos:BAAALgADCgYJBgAAAA==.Azzeus:BAABLgAECn8VAAMJAAgJHBZQBQC9AQAJAAgJHBZQBQC9AQAKAAEJmxMeVwAzAAAAAA==.',
Ba='Babyrinsjr:BAAALgAECgQJCQAAAA==.Bagel:BAABLgAECn8gAAQLAAgJxho6AwDSAQALAAcJBBw6AwDSAQACAAUJARe8OgB0AQAMAAYJ/QxVVQBoAQABLgAFFAUJEwABAO4eAA==.Baile:BAAALgADCgEJAQAAAA==.Bakon:BAAALgAECgUJDAAAAA==.Balin:BAAALgADCgYJDgAAAA==.Ballerin:BAAALgADCggJDwABLgAECgMJAwADAAAAAA==.Barrada:BAAALgAECgYJCgAAAA==.Barricay:BAAALgAECgYJBwAAAA==.',
Be='Bearcane:BAAALgADCgUJBQABLgAECggJHwAFACseAA==.Beardheals:BAAALgADCgQJBAAAAA==.Bellamira:BAAALgADCgIJAgAAAA==.Berea:BAAALgAECgYJDAAAAA==.',
Bi='Bigmeatyclaw:BAAALgADCgEJAQABLgAECgEJAQADAAAAAA==.Billywitchdr:BAAALgADCgEJAQAAAA==.',
Bl='Blankdemonic:BAAALgADCgYJCwAAAA==.Bleedblue:BAABLgAECn8ZAAINAAcJtxEmBQCpAQANAAcJtxEmBQCpAQAAAA==.Blueballmonk:BAAALgAECgUJBgAAAA==.Bluerare:BAABLgAECn8dAAIOAAgJzBdGCwD6AQAOAAgJzBdGCwD6AQAAAA==.',
Bo='Bobsgrundle:BAAALgAECgQJBAAAAA==.Bowlinna:BAAALgAECgQJBwAAAA==.',
Br='Briiki:BAAALgAECgEJAQAAAA==.Brinnohms:BAAALgADCgYJCQAAAA==.Broadsnatl:BAAALgADCgEJAQAAAA==.Bryxi:BAAALgADCgYJBgABLgAECggJGwAPAJwXAA==.Brünhilde:BAABLgAECn8ZAAIKAAcJWhTMBgCIAQAKAAcJWhTMBgCIAQAAAA==.',
Bs='Bstbll:BAACLgAFFH8IAAIGAAQJLhCeCwAnAQAGAAQJLhCeCwAnAQAuAAQKfxYAAgYACQmUHgIKAPQCAAYACQmUHgIKAPQCAAAA.Bstwaves:BAAALgAECgQJBQAAAA==.',
Bu='Bubbleban:BAAALgADCgUJBQAAAA==.Bungxi:BAAALgADCgUJBgABLgAECggJGwAPAJwXAA==.Burrata:BAAALgADCgkJCQAAAA==.Buttsnacks:BAABLgAECn8SAAIQAAgJdRlkCwBpAQAQAAgJdRlkCwBpAQAAAA==.',
Ca='Cairebear:BAAALgADCgEJAQAAAA==.Callistrah:BAAALgAECgYJCQAAAA==.Caltaa:BAABLgAECn8hAAIRAAgJGiMVAgAgAwARAAgJGiMVAgAgAwAAAA==.Camael:BAAALgAECgQJCAAAAA==.Canarah:BAAALgADCgUJBQABLgAFFAMJBgASACwSAA==.Canverian:BAAALgAECgQJCQAAAA==.Carmedic:BAAALgADCgcJDQAAAA==.',
Ch='Chapi:BAAALgAECgYJCQAAAA==.Chasseurfool:BAAALgAECgQJBwAAAA==.Chat:BAACLgAFFH8IAAITAAMJEhhwBQAHAQATAAMJEhhwBQAHAQAuAAQKfycAAhMACQl2GXADAAYCABMACQl2GXADAAYCAAAA.Chewi:BAAALgADCgEJAQAAAA==.Chickenlitle:BAAALgADCgUJBQAAAA==.Chickenwing:BAABLgAECn8ZAAIUAAcJlxxxAADvAQAUAAcJlxxxAADvAQAAAA==.Chilinevoke:BAAALgADCgYJCgABLgAECgEJAQADAAAAAA==.Christano:BAAALgAECggJDQAAAA==.Christhecold:BAABLgAECn8gAAMVAAgJ9xkWAwCSAQAQAAYJRBYTOQDCAQAVAAYJnxYWAwCSAQAAAA==.Chrollo:BAAALgAECgQJBAAAAA==.Chunt:BAAALgAECgQJCQAAAA==.',
Cl='Clarke:BAAALgADCgMJAwAAAA==.Cloudcrack:BAACLgAFFH8PAAITAAUJARSdCgA7AQATAAUJARSdCgA7AQAuAAQKfyEAAhMACQmQHf0KAOcCABMACQmQHf0KAOcCAAAA.',
Co='Codemon:BAAALgAECgYJEAAAAA==.Coldfusion:BAAALgADCgEJAQAAAA==.Condemn:BAAALgADCgEJAgAAAA==.Cortar:BAAALgAECgcJBgAAAA==.',
Cy='Cylrhea:BAAALgAECgYJDQAAAA==.Cyntrill:BAAALgAECgQJBAAAAA==.',
Da='Dadderz:BAAALgADCggJCAAAAA==.Daddydruid:BAAALgAECgMJBAAAAA==.Dahunter:BAAALgAECgYJCAAAAA==.Dajoel:BAAALgAECgMJAwAAAA==.Dakinna:BAAALgADCgMJAwAAAA==.Dakotawolfe:BAAALgADCgUJBQAAAA==.Dalacia:BAAALgAECgcJEAAAAA==.Dannyrojas:BAAALgAECgEJAQAAAA==.Darknature:BAABLgAECn8cAAMGAAgJABNwCwCfAQAGAAgJABNwCwCfAQAWAAEJIg5yggAuAAAAAA==.Darkodin:BAAALgAECgYJEAAAAA==.Darkomen:BAAALgADCgcJDAABLgAECgYJFgAPAE8NAA==.Darkvlad:BAABLgAECn8WAAIPAAYJTw1gnwBCAQAPAAYJTw1gnwBCAQAAAA==.Datnagadrake:BAACLgAFFH8FAAMXAAIJXxURCwCWAAAQAAIJ2gfNCgChAAAXAAIJXxURCwCWAAAuAAQKfykAAxAACAlOINoCACsCABAACAlOINoCACsCABcAAQmJIWs/AFUAAAAA.Dawinchy:BAABLgAECn8gAAIGAAgJpBU/NADXAQAGAAgJpBU/NADXAQAAAA==.',
Dc='Dchalla:BAAALgADCgcJDAAAAA==.',
De='Deadlypsycho:BAAALgAECgUJDQAAAA==.Deadmanrise:BAAALgADCgUJBQAAAA==.Deathawakens:BAAALgAECgMJAwAAAA==.Deathlyill:BAAALgAECgQJBgAAAA==.Deathtouch:BAAALgADCgcJDAAAAA==.Decembër:BAABLgAECn8VAAIOAAYJzgZHOgDaAAAOAAYJzgZHOgDaAAAAAA==.Decimious:BAAALgAECgQJBwAAAA==.Dekutree:BAAALgAECgYJEgAAAA==.Dellistia:BAAALgAECgMJBAAAAA==.Delvan:BAAALgADCgYJBgAAAA==.Demonkilla:BAAALgAECgYJDgAAAA==.Denadan:BAAALgADCgkJFQABLgAECgcJGAAYAJcIAA==.Desdamona:BAAALgAECgUJCwAAAA==.Destrodemon:BAABLgAECn8cAAIFAAgJTRBFEwBkAQAFAAgJTRBFEwBkAQAAAA==.Devorick:BAABLgAECn8fAAMZAAgJ5BcJCQDhAQAZAAgJ5BcJCQDhAQAYAAIJQxCfUQB5AAAAAA==.',
Di='Diadem:BAAALgAECgMJBAABLgAECggJIgAZAIAfAA==.Diathian:BAAALgADCgQJBAABLgAFFAQJDAAOAPMTAA==.Diaval:BAAALgAECgMJBgAAAA==.Dih:BAAALgADCgcJDAABLgAECggJFQALAJMRAA==.Dihlngthepal:BAAALgAECgEJAQAAAA==.Dirtyzealot:BAAALgADCgkJFwAAAA==.Disenchanted:BAAALgADCgYJBgABLgAECgcJGQAHAFAbAA==.Divineknight:BAAALgADCgkJFQAAAA==.Diyiya:BAAALgAECgYJCAAAAA==.',
Do='Doorki:BAAALgAECgcJCgAAAA==.Doubleott:BAAALgADCgkJFQAAAA==.',
Dr='Drael:BAAALgADCgkJFwAAAA==.Draickin:BAABLgAECn8WAAIaAAYJlQpnEgAaAQAaAAYJlQpnEgAaAQAAAA==.Drekle:BAAALgADCgcJGAABLgAECgYJEgADAAAAAA==.Drelian:BAAALgAECgEJAQAAAA==.Drenzel:BAAALgADCgYJCQAAAA==.Drevy:BAAALgAECgcJDAAAAA==.Drewsguy:BAAALgADCgkJEwAAAA==.Drexen:BAAALgADCgQJBAAAAA==.Drumroleplz:BAABLgAECn8ZAAMHAAcJUBszCQBVAQAIAAUJWSCQEwCrAQAHAAYJeRUzCQBVAQAAAA==.',
Ds='Dsanatrestk:BAABLgAECn8hAAMPAAgJmiGxAQC1AgAPAAgJmiGxAQC1AgAbAAcJ1RpXEAAFAgAAAA==.',
['Dà']='Dàddybear:BAAALgAECgUJDAAAAA==.',
Ea='Earthsangel:BAAALgAECgEJAQAAAA==.',
Ec='Eclair:BAAALgAECgQJBgAAAA==.',
Ed='Edralyia:BAAALgAECgMJBAAAAA==.',
Ei='Eilaurosa:BAABLgAECn8eAAIcAAgJ8xHEAQCrAQAcAAgJ8xHEAQCrAQAAAA==.',
El='Eldrinne:BAAALgAECgUJCwAAAA==.Elftuah:BAAALgADCggJCAAAAA==.Elfö:BAAALgAECgcJCwAAAA==.Elizawrath:BAABLgAECn8ZAAMRAAgJ+B5tBQCgAgARAAgJ+B5tBQCgAgAaAAUJlBHhWgAQAQAAAA==.Elthiss:BAABLgAECn8XAAIdAAcJgxLJBAAlAQAdAAcJgxLJBAAlAQAAAA==.',
Em='Emariel:BAAALgAECgEJAQAAAA==.',
En='Enchäntress:BAAALgAECgYJDAAAAA==.Enfer:BAAALgADCgYJCAABLgAFFAMJCAATABIYAA==.Enogg:BAAALgAECgEJAQAAAA==.Envi:BAABLgAECn8cAAIOAAgJihRVEQC3AQAOAAgJihRVEQC3AQAAAA==.',
Ep='Ephraìm:BAAALgADCgQJCAAAAA==.',
Er='Erianthe:BAABLgAECn8hAAIPAAgJ3QVbGgBDAQAPAAgJ3QVbGgBDAQAAAA==.Erophien:BAAALgADCgYJDwAAAA==.Erovael:BAAALgADCgQJBAABLgADCgYJDwADAAAAAA==.Erovynael:BAAALgAECgQJBAAAAA==.',
Ev='Eversong:BAAALgAECgYJDgAAAA==.Evhi:BAAALgAECgYJCQAAAA==.',
Ex='Exmar:BAAALgAECgEJAQAAAA==.',
Fa='Faewhisker:BAAALgADCgQJBAAAAA==.Falnor:BAAALgADCgkJCQAAAA==.Famine:BAABLgAECn8fAAMPAAgJbhvpMQBwAgAPAAgJbhvpMQBwAgAeAAEJAAC3CgAAAAAAAA==.Fancyfeet:BAAALgADCgQJBAABLgAFFAUJCQANACsLAA==.',
Fe='Fearios:BAAALgAECgYJEAAAAA==.Febronia:BAAALgAECgUJBQAAAA==.Felbeast:BAAALgAECgYJBQAAAA==.Felbound:BAAALgAECgEJAQAAAA==.Felltheburn:BAAALgADCgEJAQAAAA==.',
Fi='Figmênt:BAAALgAECgUJDgABLgAECgYJCwADAAAAAA==.Finatic:BAAALgAECgMJAwAAAA==.Fireproof:BAABLgAECn8bAAMRAAcJjiKOCABPAgARAAcJOiCOCABPAgAfAAcJyBsHOgA7AgAAAA==.Fistedwaffle:BAAALgAECgEJAQABLgAFFAIJAgADAAAAAA==.',
Fj='Fjorskin:BAAALgADCgEJAQAAAA==.',
Fl='Flairdragin:BAAALgAECgMJAwAAAA==.Flare:BAAALgAECggJEgAAAA==.',
Fo='Forix:BAAALgADCggJDAAAAA==.',
Fr='Fries:BAAALgADCggJCAAAAA==.Frosttbyte:BAAALgAECggJEAAAAA==.Frostytute:BAAALgADCgcJCQAAAA==.',
Fu='Funsies:BAAALgADCgEJAQAAAA==.',
Fy='Fyrrstorm:BAAALgADCgcJCgAAAA==.',
['Fë']='Fëiróx:BAAALgADCgYJBgAAAA==.',
Ga='Gallum:BAAALgADCgEJAQAAAA==.',
Ge='Getzi:BAABLgAECn8ZAAIfAAgJYCL6FQDlAgAfAAgJYCL6FQDlAgAAAA==.',
Gh='Ghavinflip:BAAALgAECgYJCgAAAA==.',
Gi='Gil:BAABLgAECn8fAAIFAAgJFSJdAgCTAgAFAAgJFSJdAgCTAgAAAA==.Gimlita:BAAALgAECgIJAgABLgAECggJGwAPAJwXAA==.',
Go='Goatspace:BAAALgADCgcJDgABLgAECgcJGAAYAJcIAA==.Goettel:BAAALgAECgUJBQAAAA==.Gogmazios:BAAALgADCgEJAQAAAA==.Gogofisco:BAAALgAECgEJAgAAAA==.Gongagà:BAAALgAECgYJDAAAAA==.Goodnoodle:BAAALgADCgEJAQAAAA==.Goyum:BAAALgADCgQJBAAAAA==.',
Gr='Grankino:BAAALgAECgcJEgAAAA==.Grayves:BAAALgAECgUJBAAAAA==.Greenthumbs:BAAALgAECgYJCgAAAA==.Greyhulk:BAAALgAECgQJBwAAAA==.',
Gu='Guldanshower:BAAALgADCgIJAgAAAA==.Gurni:BAAALgADCgYJCAAAAA==.Guthan:BAAALgAECgEJAQAAAA==.',
Gw='Gwaelphypha:BAABLgAECn8bAAIPAAgJnBf4RAAmAgAPAAgJnBf4RAAmAgAAAA==.',
Ha='Hakarii:BAAALgADCgYJDAAAAA==.Halliax:BAAALgADCgYJBgABLgAECggJIgAZAIAfAA==.Hamburglar:BAAALgADCgYJCAAAAA==.Hapkido:BAABLgAECn8iAAMgAAgJeB/lCgCkAgAgAAgJeB/lCgCkAgAhAAEJbQQPJQAqAAAAAA==.Hardsus:BAAALgADCgYJCgAAAA==.Hawfmave:BAAALgAECgQJBAAAAA==.',
He='Heals:BAAALgAECgMJAwAAAA==.Healthpotion:BAAALgAECgMJAwAAAA==.Heartbroken:BAAALgAECgkJBwAAAA==.Hecate:BAAALgAECgUJCAAAAA==.Heidnik:BAAALgADCgIJAgAAAA==.Helvetica:BAAALgADCggJDwAAAA==.Heretic:BAAALgAECgMJAwAAAA==.',
Hi='Hillboy:BAAALgAECgYJBgAAAA==.Hippiehulk:BAAALgAECgEJAQAAAA==.',
Ho='Holydes:BAAALgADCggJDgABLgAECgUJCwADAAAAAA==.Holyshrimp:BAABLgAECn8cAAIJAAgJshczBQDAAQAJAAgJshczBQDAAQAAAA==.Honeydew:BAAALgADCgcJBAAAAA==.Hordor:BAAALgAECgEJAQAAAA==.Hotndot:BAAALgADCgcJCgAAAA==.',
Hu='Hulem:BAAALgADCgEJAQAAAA==.Hummakavulä:BAAALgAECgQJBwAAAA==.Hunkahunka:BAAALgAECgMJBAAAAA==.Huunaron:BAAALgAECgYJEgAAAA==.',
Id='Idylwilde:BAAALgAECgQJBwAAAA==.',
Ie='Ienzo:BAAALgADCgUJBQAAAA==.',
If='Ifunny:BAAALgAECgcJCgAAAA==.',
Ih='Iheartoreos:BAABLgAECn8WAAMbAAYJxRCJCAAEAQAbAAYJpBCJCAAEAQAeAAQJLwnsDgCzAAAAAA==.',
In='Inferna:BAAALgADCgQJBAAAAA==.Ink:BAAALgAFFAIJAgAAAA==.Instakill:BAAALgADCgYJCQAAAA==.Insulin:BAAALgADCgkJCQAAAA==.Invictae:BAAALgAECgQJBgAAAA==.',
Io='Iobo:BAACLgAFFH8NAAIFAAUJthmLBgBDAQAFAAUJthmLBgBDAQAuAAQKfxkAAgUACQl4IhYHAFYDAAUACQl4IhYHAFYDAAAA.',
Ir='Iradori:BAABLgAFFH8MAAIOAAQJ8xO1CABbAQAOAAQJ8xO1CABbAQAAAA==.Irønbane:BAAALgAECgEJAQAAAA==.',
Is='Iskandar:BAAALgAECgQJBwAAAA==.Isparian:BAAALgAECgYJEQAAAA==.Issior:BAAALgAECgIJAgAAAA==.',
Ja='Jamal:BAAALgADCgkJGwAAAA==.Jarco:BAEALgAFFAIJAgAAAA==.Jasmyn:BAAALgADCgEJAQAAAA==.Jasseca:BAAALgADCggJCAABLgAECggJGwAPAJwXAA==.Java:BAAALgAECgcJDwAAAA==.',
Jo='Joedakilla:BAAALgAECgEJAQAAAA==.Jonorin:BAAALgADCgEJAQAAAA==.',
Js='Jshaman:BAAALgAECgQJBQAAAA==.',
Ju='Judoken:BAABLgAECn8VAAMNAAYJHQdpCwAdAQANAAYJGAdpCwAdAQAcAAUJUwLkFACsAAAAAA==.Jupiterr:BAABLgAFFH8FAAICAAMJvRkXEwAKAQACAAMJvRkXEwAKAQAAAA==.Juplter:BAAALgAFFAEJAQAAAA==.',
Ka='Kaelgen:BAAALgADCgcJBwAAAA==.Kaelkin:BAAALgAECgEJAgABLgAECgYJEgADAAAAAA==.Kaelthlar:BAAALgADCgYJDAAAAA==.Kaelun:BAAALgAECgQJBQABLgAECgYJEgADAAAAAA==.Kaelundrus:BAAALgAECgYJEgAAAA==.Kainis:BAAALgAECgMJBQAAAA==.Kairia:BAAALgADCgEJAQAAAA==.Kalvinakri:BAAALgADCgkJDgAAAA==.Karmus:BAAALgAECgUJCQAAAA==.Kastaspella:BAAALgAECgYJDQAAAA==.Kau:BAAALgAECgUJCQAAAA==.Kawant:BAAALgAECgIJAwAAAA==.Kaylnee:BAAALgAECgQJBwAAAA==.',
Ke='Kearra:BAAALgADCgkJCQAAAA==.Keatonrsmith:BAAALgAECgMJBAAAAA==.Kehayne:BAAALgADCgQJBAAAAA==.Keilas:BAAALgAECgYJDQAAAA==.Kerro:BAAALgAECgIJAwAAAA==.Kerron:BAAALgADCgMJAwAAAA==.Keyes:BAACLgAFFH8SAAIiAAYJABqXAQD8AQAiAAYJABqXAQD8AQAuAAQKfycAAiIACQlTIYkAANwCACIACQlTIYkAANwCAAAA.Keylala:BAAALgAECgQJCgAAAA==.',
Ki='Kiafera:BAAALgADCgMJAwAAAA==.Kickenmage:BAAALgADCgcJBwABLgAECgYJDwADAAAAAA==.Kickentail:BAAALgAECgYJDwAAAA==.Kidx:BAAALgAECgMJAwAAAA==.Kirisham:BAAALgAECgQJBAAAAA==.Kirlia:BAAALgAECgMJAwAAAA==.Kishenia:BAAALgAECgEJAQAAAA==.',
Kl='Klymax:BAAALgADCgUJBQAAAA==.',
Ko='Kongor:BAAALgAECgUJBgAAAA==.Korathazan:BAAALgADCgEJAQAAAA==.Korithelse:BAAALgAECgEJAQAAAA==.Korthea:BAAALgAECgIJAgAAAA==.',
Kr='Krispitreat:BAAALgAECgYJCwAAAA==.Kritnespears:BAAALgAECgYJDgAAAA==.Krobelus:BAABLgAECn8hAAMfAAgJMgn8IgAeAQAfAAcJUgr8IgAeAQAaAAUJBQbgZADoAAAAAA==.',
Kv='Kvedaheillr:BAAALgAECgMJAwAAAA==.Kvedaroðull:BAAALgADCgYJBwAAAA==.Kvedathulr:BAAALgADCgYJBgAAAA==.',
Ky='Kyluna:BAAALgAECgEJAQAAAA==.',
['Kè']='Kères:BAAALgAECgMJAwAAAA==.Kèrónos:BAAALgADCgkJFwAAAA==.',
['Kì']='Kìllstheweak:BAABLgAECn8fAAMeAAgJlRAvAgBnAQAeAAgJmQ8vAgBnAQAbAAYJ3QwKJwAGAQAAAA==.',
La='Lauralai:BAAALgADCgcJCAAAAA==.Lavendra:BAAALgADCgcJDwAAAA==.Lawkz:BAAALgAECgcJCAAAAA==.Layliah:BAACLgAFFH8LAAIWAAQJDiFfAQCBAQAWAAQJDiFfAQCBAQAuAAQKfysAAhYACAkqJYAAAPoCABYACAkqJYAAAPoCAAAA.',
Le='Leaftemplar:BAAALgADCgYJBgAAAA==.Leedragoon:BAAALgADCgMJAwAAAA==.Legaia:BAAALgADCgYJCQAAAA==.Legendknewl:BAAALgAECgIJAgAAAA==.Lemmesapthat:BAAALgADCgEJAQAAAA==.',
Li='Lillinna:BAAALgADCgQJBAAAAA==.Lisithen:BAAALgADCgEJAQAAAA==.',
Lo='Loafai:BAABLgAECn8YAAQYAAcJlwiEBQDsAAAYAAYJ5geEBQDsAAAjAAUJLwZ4GAC3AAAZAAUJqAP21ACwAAAAAA==.Lockrocks:BAAALgAECgYJEgAAAA==.Lorcán:BAAALgAECgMJBAAAAA==.Lormazlezrax:BAACLgAFFH8GAAISAAMJLBJNBwDgAAASAAMJLBJNBwDgAAAuAAQKfyEAAhIABwmtHxwZAE0CABIABwmtHxwZAE0CAAAA.',
Lu='Luis:BAAALgAECgQJBAAAAA==.Lumaron:BAAALgADCgEJAgAAAA==.Lunamizka:BAAALgADCgIJAgAAAA==.Lunethira:BAAALgAECgUJCQAAAA==.Lustdeeznuts:BAAALgAECgYJEQAAAA==.',
Ly='Lylat:BAAALgAECgIJAgAAAA==.',
['Ló']='Lórdelrond:BAAALgADCgUJCgAAAA==.',
['Lú']='Lúpo:BAAALgAECgMJAwAAAA==.',
Ma='Machezemo:BAABLgAECn8cAAIOAAcJiiGeDADoAQAOAAcJiiGeDADoAQAAAA==.Madhatter:BAAALgAECgQJBgAAAA==.Mahalka:BAAALgAECgEJAQAAAA==.Maki:BAAALgAECgYJEAAAAA==.Malegar:BAAALgADCgcJGAAAAA==.Malendor:BAABLgAECn8YAAIhAAcJ8yUIAQCDAgAhAAcJ8yUIAQCDAgAAAA==.Mammajamma:BAAALgAECgEJAwAAAA==.Manbearcat:BAAALgAECgEJAQAAAA==.Marcydaghoul:BAAALgADCgUJBQAAAA==.Marivoker:BAAALgADCgkJFQABLgAECgYJCwADAAAAAA==.Marsvolta:BAAALgADCgYJBgAAAA==.Maruxus:BAABLgAECn8eAAMcAAcJoxI4CADTAQAcAAcJoxI4CADTAQAkAAYJfg9MBgBhAQAAAA==.Marvilla:BAAALgAECgcJDwAAAA==.Marwen:BAAALgADCgkJFAAAAA==.Mathbrew:BAABLgAECn8fAAIiAAgJvSHaAQBUAgAiAAgJvSHaAQBUAgAAAA==.',
Mc='Mcchicken:BAAALgADCgIJAgAAAA==.Mclardragos:BAAALgAECgYJEwAAAA==.',
Me='Melindria:BAAALgAECgYJDgAAAA==.Mendicine:BAAALgAECgMJBQAAAA==.Menmoe:BAAALgAECgEJAQAAAA==.',
Mi='Miacyn:BAAALgADCggJDAAAAA==.Miladybast:BAAALgAECgUJBwAAAA==.Mirra:BAAALgAECgYJEgAAAA==.Misha:BAAALgADCgUJBQAAAA==.Missdorei:BAAALgADCgcJFAAAAA==.',
Mo='Mogged:BAAALgAECgYJDwAAAA==.Mojocity:BAAALgADCgUJBQAAAA==.Molai:BAAALgAECgcJAwAAAA==.Monkdangit:BAAALgAECgYJCQAAAA==.Morionso:BAAALgAECgUJCQAAAA==.Mortarion:BAABLgAECn8ZAAIPAAgJhx07IgC3AgAPAAgJhx07IgC3AgAAAA==.Moxxulae:BAAALgADCgkJCAAAAA==.Moõn:BAABLgAECn8WAAIHAAgJ9QvmBgCFAQAHAAgJ9QvmBgCFAQAAAA==.',
Mu='Murcié:BAABLgAECn8pAAMFAAgJ8RUjFABcAQAFAAgJ0xUjFABcAQAEAAYJHwkKOgAZAQAAAA==.Murdiûs:BAAALgAECggJEgAAAA==.',
My='Myregards:BAAALgADCgYJBwAAAA==.Myspaceshria:BAAALgAECgUJDgABLgAECggJGwAPAJwXAA==.Mythbruh:BAAALgAECgEJAQABLgAECggJHwAiAL0hAA==.Mythis:BAAALgAECgMJBAAAAA==.',
['Mó']='Mósh:BAAALgAECgYJBgAAAA==.',
Na='Nahane:BAAALgAECgEJAQAAAA==.Nahlur:BAAALgAECgMJAwAAAA==.Naoko:BAAALgAECgEJAQAAAA==.Nayrlock:BAABLgAECn8iAAQZAAgJgB9KGgC3AgAZAAgJgB9KGgC3AgAjAAUJtRdhEQAXAQAYAAQJuBCjQACyAAAAAA==.Nayuta:BAAALgADCgYJBQAAAA==.',
Nc='Nc:BAAALgADCgIJAgAAAA==.Nctee:BAAALgAECgYJBwAAAA==.',
Ne='Necropally:BAAALgADCggJEQAAAA==.Necrotizor:BAABLgAECn8VAAIZAAcJDBd0ZACdAQAZAAcJDBd0ZACdAQAAAA==.Neonsalmandr:BAAALgADCgkJEQAAAA==.',
Ni='Nialliv:BAAALgADCgcJCQAAAA==.Nidvin:BAAALgAECgQJEAAAAA==.Nightsmoke:BAAALgAECgQJBQAAAA==.',
Nk='Nkb:BAAALgAECgIJAgAAAA==.',
Nn='Nnoitra:BAAALgADCgcJBwAAAA==.',
No='Noceman:BAAALgADCgEJAQAAAA==.Nock:BAAALgAECgUJBgAAAA==.Noll:BAAALgADCgUJBQAAAA==.Nonattarius:BAAALgAECgQJCQAAAA==.Norezfou:BAABLgAECn8hAAMlAAgJTxxbCwCaAgAlAAgJTxxbCwCaAgAJAAEJ2xfrWwBFAAAAAA==.Nornir:BAAALgAECgIJAgAAAA==.Norran:BAAALgAECgYJCwAAAA==.Norvera:BAAALgAECgIJAgAAAA==.Notmywife:BAAALgAECgYJDQAAAA==.Novakri:BAAALgADCgMJAwAAAA==.',
Nu='Nuker:BAAALgAECgUJBwAAAA==.Nurobi:BAABLgAECn8bAAIWAAgJYhM5BgChAQAWAAgJYhM5BgChAQAAAA==.',
Ny='Nysel:BAAALgAECgkJAQAAAA==.Nysera:BAAALgADCggJCAAAAA==.Nyxy:BAAALgAECgMJAwAAAA==.',
Oc='Ocey:BAAALgADCgUJBQABLgAECgYJBwADAAAAAA==.',
Od='Odyn:BAAALgAECgUJCwAAAA==.',
Oo='Ooyu:BAAALgAECgUJCwAAAA==.',
Or='Orangepeel:BAAALgADCgUJBQAAAA==.Oridk:BAAALgAECgUJDQABLgAECggJHAALALQeAA==.Orimage:BAAALgADCgkJDAABLgAECggJHAALALQeAA==.Oripal:BAAALgAECgUJBQABLgAECggJHAALALQeAA==.Oríon:BAABLgAECn8cAAMLAAgJtB6dBQCwAgALAAgJtB6dBQCwAgACAAUJahbxUgAAAQAAAA==.',
Ou='Outofmyele:BAAALgADCgQJBAAAAA==.',
Ow='Owoker:BAAALgAECggJDwAAAA==.',
Pa='Pablo:BAAALgAECgcJDgAAAA==.Pancaked:BAAALgAECgEJAQABLgAFFAUJEwABAO4eAA==.Pancakedup:BAAALgAECgcJDAABLgAFFAUJEwABAO4eAA==.Pandozer:BAAALgAECggJDwAAAA==.Pankratos:BAAALgAECgcJDwAAAA==.Papaspud:BAABLgAECn8cAAIlAAgJhQ1/CQBlAQAlAAgJhQ1/CQBlAQAAAA==.Paradias:BAACLgAFFH8JAAINAAUJKwtZBgAAAQANAAUJKwtZBgAAAQAuAAQKfyAAAw0ACAkYIPIMAMoCAA0ACAn8H/IMAMoCABwABgmxFzAMAGIBAAAA.Patpat:BAAALgADCgcJBgAAAA==.Paxxfist:BAAALgAECgcJEwAAAA==.',
Pe='Peachdevil:BAAALgADCgMJAwAAAA==.Penryn:BAAALgAECgEJAQAAAA==.Pentive:BAAALgAFFAIJAgAAAA==.Peppersham:BAAALgAECgQJCQAAAA==.Perff:BAAALgADCgYJBQAAAA==.Perhaps:BAABLgAECn8ZAAIiAAgJJyGLBwANAwAiAAgJJyGLBwANAwAAAA==.Petesdragin:BAAALgAECgcJCwAAAA==.',
Pf='Pfftpfft:BAAALgAECgMJBAAAAA==.',
Ph='Phatdanny:BAABLgAECn8VAAIfAAgJZBgcCAAJAgAfAAgJZBgcCAAJAgAAAA==.Phatdumpy:BAABLgAECn8VAAQLAAgJkxGiBACbAQAMAAcJcROxOgDEAQALAAcJFweiBACbAQACAAQJ7wrrXADOAAAAAA==.Phattphatt:BAABLgAECn8bAAImAAcJ+Rk6AgDDAQAmAAcJ+Rk6AgDDAQAAAA==.Phonycheese:BAAALgAECgUJCgAAAA==.Phur:BAAALgAECgYJBgAAAA==.',
Pi='Pinbal:BAAALgAECgQJBAAAAA==.',
Pl='Plagueiss:BAABLgAECn8cAAIPAAgJjhrJPABEAgAPAAgJjhrJPABEAgAAAA==.',
Po='Pocalypse:BAAALgAECgYJBQAAAA==.Portstar:BAAALgAECgYJDgAAAA==.',
Pr='Precast:BAAALgADCgUJCgAAAA==.Prestoresto:BAAALgAECgEJAQAAAA==.Prieske:BAAALgAECgUJDAAAAA==.Primed:BAABLgAECn8hAAImAAgJeA1zAwCAAQAmAAgJeA1zAwCAAQAAAA==.Privxd:BAAALgAFFAQJBAAAAA==.Prunesa:BAAALgADCgcJBQAAAA==.',
Pu='Pungla:BAAALgAECgIJAQAAAA==.',
['Pî']='Pîper:BAAALgADCgYJBgAAAA==.',
['Pï']='Pït:BAAALgAECgYJCwAAAA==.',
Qp='Qprawindfury:BAAALgAECgMJAwAAAA==.',
Qu='Quadtwat:BAAALgAECgQJBwAAAA==.Quahogger:BAAALgAECgQJBAAAAA==.',
Ra='Radical:BAAALgAECgIJAgAAAA==.Railyard:BAAALgADCgMJAwABLgAECgIJAgADAAAAAA==.Raivn:BAAALgADCgEJAQAAAA==.Rajasta:BAAALgAECgIJAgAAAA==.Rajzova:BAAALgADCgcJCgABLgAECgYJDAADAAAAAA==.Randomclown:BAAALgADCgYJCgAAAA==.Rapi:BAAALgAECgMJAwAAAA==.Rashii:BAAALgAECgUJCwAAAA==.Rawor:BAAALgAECgYJEAAAAA==.',
Re='Rebaderchi:BAABLgAECn8fAAIFAAgJKx6hGQC6AgAFAAgJKx6hGQC6AgAAAA==.Relyne:BAAALgADCgYJBgAAAA==.Remo:BAAALgADCgcJCQAAAA==.Remoria:BAAALgAECgUJBQAAAA==.Renildan:BAAALgAECgQJBQAAAA==.Resala:BAAALgADCgYJBgAAAA==.Rev:BAAALgADCgMJAwAAAA==.Revanhawk:BAAALgADCgkJEQAAAA==.Revna:BAAALgADCgcJBwAAAA==.Rezputan:BAAALgAECgcJDAAAAA==.',
Rh='Rholand:BAAALgAECgIJBAAAAA==.',
Ri='Rind:BAAALgAECgUJBQAAAA==.Rioken:BAABLgAECn8UAAMZAAgJoxQwNQA3AgAZAAgJoxQwNQA3AgAYAAEJgxBwbgA4AAAAAA==.Riolobo:BAAALgADCgIJAgAAAA==.Riorage:BAAALgAECgUJCgAAAA==.Ritz:BAAALgAECgEJAQAAAA==.Rizzoy:BAAALgAECgYJEAAAAA==.',
Ro='Rollo:BAAALgADCgUJCgAAAA==.Rolor:BAAALgADCgYJBgAAAA==.Rookiefister:BAAALgADCgEJAgAAAA==.Ross:BAECLgAFFH8FAAIgAAMJ0SERDgC9AAAgAAMJ0SERDgC9AAAuAAQKfxQAAiAABgnbJMkOAGsCACAABgnbJMkOAGsCAAAA.Rovyr:BAABLgAECn8aAAMnAAgJdhvpAACKAgAnAAgJdhvpAACKAgAIAAEJuAHYRQAeAAAAAA==.',
Ru='Ruckabis:BAAALgAECggJEwAAAA==.',
Ry='Rylos:BAAALgAECgYJBwAAAA==.Rytotem:BAAALgAECgMJBAAAAA==.Ryumi:BAAALgADCgkJCwAAAA==.Ryvington:BAAALgADCgYJCAAAAA==.',
Sa='Saansula:BAAALgAECgMJAwAAAA==.Sabian:BAAALgAECggJCAAAAA==.Saintjeb:BAAALgAFFAIJAgAAAA==.Saitami:BAAALgAECgEJAQAAAA==.Saitamå:BAAALgAECgYJDAAAAA==.Salinity:BAABLgAECn8VAAMYAAcJmCNtBwBRAgAYAAYJHCNtBwBRAgAZAAYJsR80EACQAQAAAA==.Samanaras:BAAALgAECgUJDAAAAA==.Santiago:BAAALgAECgQJBgAAAA==.Saratoga:BAAALgAECgcJCwAAAA==.Sarkana:BAAALgAECggJEQAAAA==.Sarticor:BAAALgAECgEJAQAAAA==.Sassquatch:BAAALgAECgYJDgAAAA==.Saxonn:BAABLgAECn8XAAMTAAcJZgwHDwAWAQATAAcJZgwHDwAWAQASAAMJaQM8iABzAAAAAA==.Saydis:BAAALgAECgMJBgAAAA==.',
Sc='Schuftt:BAAALgAECgUJDAAAAA==.',
Se='Seafoodtower:BAAALgAECgEJAQAAAA==.Sebattan:BAAALgADCgYJCAAAAA==.Seleine:BAAALgADCgEJAQABLgAECggJHAAOAIoUAA==.Sello:BAAALgAECgEJAgAAAA==.Seltzers:BAAALgADCgQJCgAAAA==.Selunella:BAAALgADCgEJAQABLgAECgUJCQADAAAAAA==.Selvester:BAAALgAECgYJEAAAAA==.Senadria:BAAALgAECgUJDQAAAA==.Senseishifu:BAABLgAECn8WAAIiAAcJdA3cPgBKAQAiAAcJdA3cPgBKAQAAAA==.Seorsen:BAAALgADCgcJEAAAAA==.Sevalandre:BAAALgADCgYJBgABLgAECggJGwAPAJwXAA==.',
Sh='Shamatrest:BAAALgAECgEJAgABLgAECggJIQAPAJohAA==.Shamina:BAABLgAECn8VAAIBAAcJqw4jEAC1AQABAAcJqw4jEAC1AQAAAA==.Shamite:BAAALgAECgMJAwABLgAECgUJBgADAAAAAA==.Shammalin:BAABLgAECn8XAAMTAAYJwAkTEgDxAAATAAYJwAkTEgDxAAASAAIJigWQjQBfAAAAAA==.Shamminator:BAAALgADCgMJAwAAAA==.Shamorex:BAABLgAECn8cAAITAAYJNRcVNQCCAQATAAYJNRcVNQCCAQAAAA==.Sharkbones:BAAALgAECgEJAQAAAA==.Shatter:BAAALgAECgcJCgAAAA==.Shax:BAAALgAECgUJBQABLgAECgcJFQAYAJgjAA==.Shiftyy:BAAALgAECgIJAgAAAA==.Shogun:BAAALgADCgQJCAAAAA==.Shteph:BAAALgADCgYJBgAAAA==.Shîftfaced:BAAALgADCgkJEAAAAA==.',
Si='Siaerosia:BAAALgADCgEJAQAAAA==.',
Sk='Skaarr:BAAALgAECgcJDQAAAA==.',
Sl='Slayn:BAAALgAECgUJCQAAAA==.Slowhealsboi:BAAALgAECgQJBAAAAA==.Slushpuppie:BAAALgADCgYJBgAAAA==.Slyrak:BAABLgAECn8WAAMIAAcJIxf2AQCMAQAIAAcJIxf2AQCMAQAnAAIJ3waEEAA0AAAAAA==.',
Sm='Smithbruh:BAAALgAECgMJAwABLgAECggJHwAiAL0hAA==.Smitus:BAAALgAECgIJAgAAAA==.Smokescale:BAAALgADCgcJCAAAAA==.',
Sn='Snackie:BAAALgAECgYJBgAAAA==.Snotpig:BAAALgAECggJBwAAAA==.',
So='Solarious:BAAALgAECgEJAQAAAA==.Sorscrasus:BAAALgADCgUJCAAAAA==.Soulcolektor:BAAALgADCgcJCAAAAA==.',
Sp='Sparroh:BAAALgADCgEJAQAAAA==.Spikedriver:BAAALgAECgYJEQAAAA==.Spradwurd:BAAALgAECgUJCAAAAA==.',
St='Stantonio:BAAALgAECgYJBgAAAA==.Stariane:BAAALgAECggJEwAAAA==.Startaster:BAAALgAECgYJBwAAAA==.Starvoid:BAAALgAECgEJAQAAAA==.Steaktartare:BAAALgAECgYJCwAAAA==.Steelfist:BAAALgAECgYJCgAAAA==.Steelpunch:BAAALgAECgMJAwAAAA==.Steelwill:BAAALgAECgIJAgAAAA==.Stonii:BAAALgADCgUJBQAAAA==.Stony:BAAALgAECgUJDwAAAA==.Stonyy:BAAALgADCgkJDwAAAA==.Strelizia:BAAALgAECgIJAgAAAA==.Stressful:BAAALgADCgQJBAAAAA==.',
Su='Summers:BAAALgAECgMJBAAAAA==.Sumonmyface:BAAALgAECgQJBgABLgAECggJFQALAJMRAA==.Sunshield:BAAALgADCgkJCwAAAA==.Suraug:BAAALgADCgcJBwAAAA==.',
Sw='Swampraught:BAAALgAECgYJEAAAAA==.',
Sy='Syd:BAAALgADCgYJBgAAAA==.Syletage:BAAALgAECgIJAgAAAA==.Syral:BAAALgAECgMJBAAAAA==.Syrion:BAAALgAECgQJBAAAAA==.Sythrane:BAAALgADCgcJBwAAAA==.',
Ta='Taarii:BAAALgADCggJCAAAAA==.Talisoudwave:BAAALgAECgMJBwABLgAECgYJDQADAAAAAA==.Talomeo:BAAALgAECgIJAgAAAA==.Taradan:BAAALgAECgEJAQAAAA==.Tateraider:BAABLgAECn8cAAIXAAgJhhr0AQAUAgAXAAgJhhr0AQAUAgAAAA==.Taylorswift:BAAALgAECgMJBgAAAA==.Tayven:BAAALgADCgEJAQAAAA==.',
Te='Telain:BAABLgAECn8ZAAMaAAcJCQ6AEQAmAQAaAAcJCQ6AEQAmAQAfAAQJJQq54QDKAAAAAA==.Tensuki:BAAALgADCgEJAgAAAA==.Teslah:BAAALgADCgQJBAAAAA==.',
Th='Thakilla:BAABLgAECn8aAAIWAAgJSBGpBgCXAQAWAAgJSBGpBgCXAQAAAA==.Thanosonmage:BAAALgADCgcJBwAAAA==.Thavik:BAAALgADCgEJAwAAAA==.Theolodin:BAAALgAECgEJAQAAAA==.Thorix:BAAALgAECgYJBgAAAA==.Thotmir:BAAALgAECgMJAwAAAA==.Thícc:BAAALgADCgkJCgAAAA==.',
Ti='Tikibiki:BAAALgADCgMJAwAAAA==.Timberreaper:BAAALgAECgEJAQAAAA==.Tinyz:BAAALgAECgQJCAAAAA==.',
To='Tolua:BAAALgAECgMJAwAAAA==.Tonata:BAAALgAECggJDgAAAA==.Tonythetiger:BAAALgADCgkJEAABLgAECgYJEAADAAAAAA==.Tootsie:BAAALgADCgYJEAAAAA==.',
Tr='Trenton:BAAALgADCgUJBwAAAA==.Trexlot:BAAALgAECgIJAgAAAA==.Trinjal:BAABLgAECn8VAAIgAAcJ2BoiBQDXAQAgAAcJ2BoiBQDXAQAAAA==.Trishift:BAAALgAECgMJAwAAAA==.Trueshru:BAAALgAECgEJAgAAAA==.',
Tu='Tubular:BAAALgAECgMJBQAAAA==.Tuskadin:BAABLgAECn8mAAIfAAgJsCKvGwDEAgAfAAgJsCKvGwDEAgAAAA==.',
Ty='Tyjan:BAAALgAECgQJBwAAAA==.Tyrana:BAAALgAECgMJAwAAAA==.Tyriq:BAAALgADCgYJBgAAAA==.',
Un='Unclothed:BAAALgAECgQJBwAAAA==.',
Va='Valentine:BAAALgADCgIJAgAAAA==.Valitymage:BAAALgADCgEJAQAAAA==.Varyusha:BAAALgAECgMJBAAAAA==.',
Ve='Velene:BAAALgADCgEJAQABLgAECggJHAAOAIoUAA==.Venzallow:BAAALgAECgUJBwAAAA==.Veralynn:BAAALgADCgcJBwAAAA==.Veravibes:BAAALgAECgQJCAAAAA==.Vermagnus:BAAALgAECgcJEgAAAA==.Vespor:BAAALgAECgYJEwAAAA==.',
Vi='Viktorya:BAABLgAECn8eAAInAAcJDBeYFgDlAQAnAAcJDBeYFgDlAQAAAA==.Vilelyn:BAAALgAECgMJBAABLgAECgUJCQADAAAAAA==.Viloria:BAAALgAECgYJEAAAAA==.Vincent:BAAALgADCgIJAgAAAA==.Virrard:BAABLgAECn8YAAMMAAcJlxoUMQDsAQAMAAcJlxoUMQDsAQACAAIJYA+AdQBoAAAAAA==.Vitalyellow:BAAALgADCgYJBgAAAA==.',
Vl='Vladimor:BAAALgAECgYJEgAAAA==.Vladimyrr:BAAALgAECgYJDgAAAA==.',
Vo='Vodan:BAAALgADCgEJAQAAAA==.Voidplague:BAAALgAECgMJAwAAAA==.Voidscarred:BAAALgAECgQJDAAAAA==.Vozrezz:BAAALgAECgYJDAAAAA==.',
Vu='Vualake:BAAALgADCgYJCgAAAA==.',
['Vë']='Vëda:BAAALgAECgcJEgAAAA==.',
Wa='Wardragon:BAAALgADCgYJBgAAAA==.Wasical:BAAALgADCgEJAQAAAA==.',
Wi='Wicker:BAABLgAECn8YAAIdAAgJoSHTAABbAgAdAAgJoSHTAABbAgAAAA==.Wintin:BAAALgAECgEJAQAAAA==.',
Wo='Wolford:BAAALgAECgYJEAAAAA==.Woogie:BAAALgADCgYJCgAAAA==.',
Wr='Wras:BAAALgAECgQJCQAAAA==.Wretched:BAAALgAECgcJBQAAAA==.',
['Wò']='Wòbbles:BAAALgAECgQJBQAAAA==.',
Xa='Xandrah:BAAALgAECgMJBQAAAA==.Xanslash:BAABLgAECn8ZAAIFAAgJsxyFCgDLAQAFAAgJsxyFCgDLAQAAAA==.Xari:BAACLgAFFH8MAAIOAAQJihLcGwBcAQAOAAQJihLcGwBcAQAuAAQKfyQAAg4ACQluIv8RADsDAA4ACQluIv8RADsDAAAA.',
Xh='Xhalo:BAAALgADCggJCAAAAA==.',
Xi='Xiansai:BAAALgAECggJEgAAAA==.',
Ya='Yappey:BAABLgAECn8XAAIiAAYJICPEBADNAQAiAAYJICPEBADNAQAAAA==.',
Ye='Yehni:BAABLgAECn8oAAIlAAgJwiHaAwAaAwAlAAgJwiHaAwAaAwAAAA==.',
Za='Zalarii:BAAALgADCgEJAgAAAA==.Zarox:BAAALgAECggJEgAAAA==.',
Ze='Zeroelement:BAAALgAECgUJEQAAAA==.',
Zi='Zimgir:BAAALgADCgEJAQAAAA==.',
Zo='Zombiehippo:BAABLgAECn8aAAIOAAcJhxlZEAC/AQAOAAcJhxlZEAC/AQAAAA==.Zorcons:BAAALgAECgEJAQAAAA==.',
Zu='Zuuzuu:BAAALgADCgEJAQAAAA==.',
['Áu']='Áutarch:BAAALgAECgUJBgAAAA==.',
['Èl']='Èlty:BAAALgAECgMJAwAAAA==.',
['Ðe']='Ðemøn:BAAALgADCgkJHwAAAA==.',
['Ðr']='Ðrexy:BAAALgADCgUJBQAAAA==.',
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
