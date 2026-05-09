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

local lookup = {'Paladin-Holy','DemonHunter-Devourer','Rogue-Subtlety','Rogue-Outlaw','DemonHunter-Havoc','Hunter-BeastMastery','Mage-Frost','Hunter-Marksmanship','Warlock-Demonology','Paladin-Retribution','Shaman-Restoration','Unknown-Unknown','Warrior-Fury','Shaman-Enhancement','Rogue-Assassination','Hunter-Survival','Warrior-Protection','Druid-Balance','Druid-Restoration','DeathKnight-Frost','Druid-Guardian','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Unholy','Monk-Brewmaster','Mage-Arcane','Druid-Feral','Warrior-Arms','Priest-Discipline','Priest-Holy','Paladin-Protection','Priest-Shadow','DemonHunter-Vengeance','Shaman-Elemental','Evoker-Preservation','Warlock-Destruction','Warlock-Affliction','Monk-Windwalker','Monk-Mistweaver','DeathKnight-Blood',}
local provider = {region='US',realm='Nathrezim',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abysm:BAAALgADCgkJDwAAAA==.',
Ac='Achillios:BAAALgADCgMJAwABLgAFFAQJBgABAFUTAA==.',
Ad='Adorabull:BAAALgAECgIJAwABLgAECgkJIQACAKsdAA==.',
Ae='Aemun:BAABLgAECn8rAAMDAAgJqBoFBwA8AgADAAgJqBoFBwA8AgAEAAYJlAmvCAD2AAAAAA==.',
Ag='Aggfu:BAAALgADCgYJBgAAAA==.',
Ak='Akelita:BAABLgAECn8XAAIFAAYJrxgqEQBzAQAFAAYJrxgqEQBzAQAAAA==.',
Al='Alailea:BAABLgAECn8jAAIGAAkJxRIIGAAPAgAGAAkJxRIIGAAPAgAAAA==.Alwysafkable:BAAALgADCgQJBAAAAA==.',
Am='Amazadin:BAABLgAFFH8GAAIBAAQJVRPhDwA2AQABAAQJVRPhDwA2AQAAAA==.Amazashock:BAAALgAECgUJCAABLgAFFAQJBgABAFUTAA==.',
An='Andiwin:BAAALgAFFAEJAQAAAA==.Andurthil:BAABLgAECn8ZAAIHAAcJMw2bZwBCAQAHAAcJMw2bZwBCAQAAAA==.Anzul:BAAALgAECgUJBgAAAA==.',
Ar='Archive:BAAALgAECgkJCwAAAA==.Artistic:BAABLgAECn8WAAIGAAgJ3hY9HAD0AQAGAAgJ3hY9HAD0AQAAAA==.Arylanna:BAAALgAECgYJDQAAAA==.',
As='Asure:BAABLgAECn8kAAMGAAgJUxcPHQDuAQAGAAgJUxcPHQDuAQAIAAYJTgfUTwAPAQAAAA==.',
Az='Azerith:BAAALgAECgUJBgAAAA==.',
Be='Bearforceone:BAAALgADCgMJAwAAAA==.',
Bi='Bipolar:BAAALgADCgEJAQAAAA==.',
Bl='Blackheart:BAABLgAECn8YAAIJAAgJpBe7LQBWAgAJAAgJpBe7LQBWAgAAAA==.Blodreina:BAAALgADCgUJCQAAAA==.Bloodarchon:BAAALgAECgYJDwAAAA==.Bloodtemplar:BAABLgAECn8WAAIKAAcJuRYJOgCZAQAKAAcJuRYJOgCZAQAAAA==.',
Bo='Bombs:BAAALgAECgQJEAABLgAFFAMJEgALALgiAA==.Bouren:BAAALgAECgEJAQAAAA==.',
Br='Bravia:BAAALgADCgUJBwAAAA==.Brewdogg:BAAALgADCgcJBwAAAA==.Brutalitops:BAAALgADCgMJAwAAAA==.Brutusdabull:BAAALgAECgYJBgAAAA==.Brônze:BAAALgADCgQJBAAAAA==.',
Bu='Burdomew:BAAALgADCgEJAQAAAA==.',
Ca='Cadbury:BAAALgADCgIJAgABLgAECgUJCAAMAAAAAA==.Canan:BAAALgAECgMJAwAAAA==.Canestoast:BAAALgAECgEJAQAAAA==.Casmina:BAABLgAECn8WAAINAAkJ7xlQIQBJAgANAAkJ7xlQIQBJAgAAAA==.Castiell:BAAALgADCgUJBgAAAA==.Catalystic:BAAALgADCgEJAQAAAA==.Catd:BAAALgADCgEJAQAAAA==.',
Ce='Celum:BAAALgAECgYJDAAAAA==.Ceola:BAAALgAECgQJBAAAAA==.',
Ch='Chamming:BAAALgADCgIJAgAAAA==.Chaquén:BAABLgAECn8XAAIOAAgJ5xPsBgDIAQAOAAgJ5xPsBgDIAQAAAA==.Charizard:BAAALgAECgEJAQAAAA==.Charmander:BAABLgAECn8aAAMPAAYJshfBBwBhAQAPAAYJshfBBwBhAQAEAAMJ2wR+DQCCAAAAAA==.Chaw:BAACLgAFFH8RAAMQAAUJzCNPCgA3AQAQAAQJ6yJPCgA3AQAGAAEJcCaiIQBdAAAuAAQKfykABBAACQknJGoHADUCABAACQn9ImoHADUCAAgABwnWHyUiABUCAAYABAk3I01IAJEBAAAA.Chenkenichi:BAAALgAECgYJDwAAAA==.Chergar:BAABLgAECn8bAAIRAAgJ5iFKBQDpAgARAAgJ5iFKBQDpAgAAAA==.Chskie:BAAALgADCgUJBQAAAA==.Chsky:BAAALgADCgUJBQAAAA==.Chuiyi:BAAALgAECgEJAQAAAA==.',
Ci='Cinny:BAABLgAECn84AAIGAAkJlRkEEgBBAgAGAAkJlRkEEgBBAgAAAA==.Cinnyrolls:BAABLgAECn8XAAMSAAgJ/xslCwAZAgASAAgJ/xslCwAZAgATAAQJtBBchwDHAAAAAA==.Cityairlines:BAABLgAECn8nAAIUAAkJuRTgAgD9AQAUAAkJuRTgAgD9AQAAAA==.',
Cl='Clare:BAAALgAECgYJCQAAAA==.',
Cm='Cmoneyy:BAAALgADCgMJAwAAAA==.',
Co='Cooldukenuke:BAACLgAFFH8IAAIBAAMJgRb0DwDaAAABAAMJgRb0DwDaAAAuAAQKfyAAAgEACAlaHjkTAHkCAAEACAlaHjkTAHkCAAAA.',
Cr='Creepychalk:BAAALgAECgUJDAAAAA==.Criticize:BAABLgAECn8YAAIKAAYJTAavmgC6AAAKAAYJTAavmgC6AAAAAA==.',
Cs='Csorb:BAABLgAECn8uAAIVAAgJRCKOAgCIAgAVAAgJRCKOAgCIAgAAAA==.Csoren:BAAALgAECgEJAQAAAA==.Csoro:BAAALgADCggJCAAAAA==.',
Cu='Cultivation:BAAALgAECgUJCAAAAA==.Cursedcanfly:BAACLgAFFH8SAAIWAAUJFx/HCgCGAQAWAAUJFx/HCgCGAQAuAAQKfyoAAxYACQmQJeYDAFoDABYACQmQJeYDAFoDABcABQnaFGgiABcBAAAA.',
Cw='Cw:BAAALgAECgEJAQAAAA==.',
De='Deathdogg:BAACLgAFFH8NAAIYAAQJ/RaVJwBQAQAYAAQJ/RaVJwBQAQAuAAQKfycAAhgACQmaH34RAHACABgACQmaH34RAHACAAAA.Dejavu:BAACLgAFFH8RAAIZAAQJwxDoFAAdAQAZAAQJwxDoFAAdAQAuAAQKfyUAAhkACAmhGZgaAC8CABkACAmhGZgaAC8CAAAA.Demivoi:BAAALgAECgYJBwAAAA==.Demona:BAAALgAECgEJAQAAAA==.Deppthcharge:BAAALgAECgYJDAAAAA==.Desdemona:BAAALgAECgUJBQAAAA==.Devimon:BAAALgADCgEJAQAAAA==.Devoi:BAAALgADCgEJAQAAAA==.',
Do='Donrain:BAAALgAECgQJBAAAAA==.Dooghammer:BAABLgAECn8ZAAIOAAkJQhp+AgCCAgAOAAkJQhp+AgCCAgAAAA==.',
Dr='Dragussy:BAAALgADCgcJDQABLgAECgkJJgARANglAA==.',
Du='Dunkhan:BAAALgAECgEJAQABLgAECgYJCgAMAAAAAA==.Duplexity:BAABLgAECn8mAAIRAAkJ2CVhAABoAwARAAkJ2CVhAABoAwAAAA==.',
Dw='Dwalin:BAAALgAECgMJBwABLgAECgkJGQAOAEIaAA==.',
Ec='Ecko:BAAALgAECgEJAQAAAA==.',
Eg='Egohakai:BAACLgAFFH8PAAIKAAQJrx2uDgBtAQAKAAQJrx2uDgBtAQAuAAQKfycAAgoACQnjIgkNACUDAAoACQnjIgkNACUDAAAA.',
El='Eloi:BAAALgAECgUJCAABLgAECggJJQATABUdAA==.',
Em='Emieretta:BAABLgAECn80AAIYAAkJ6hURGQA2AgAYAAkJ6hURGQA2AgAAAA==.',
Eq='Eqdk:BAABLgAECn8YAAIYAAgJ9xLkMgCuAQAYAAgJ9xLkMgCuAQAAAA==.',
Er='Erret:BAACLgAFFH8MAAIHAAQJ1RJCMQBGAQAHAAQJ1RJCMQBGAQAuAAQKfyYAAwcACQk8ICkyAKoCAAcACQkQICkyAKoCABoAAQnKGdQLAEsAAAAA.',
Ez='Ezinder:BAAALgADCgkJEAAAAA==.',
Fa='Fabius:BAAALgADCgYJBgAAAA==.Faemos:BAAALgAECgkJBgAAAA==.Faience:BAABLgAECn8aAAIUAAgJYQNcDADDAAAUAAgJYQNcDADDAAAAAA==.Falorina:BAABLgAECn8bAAMFAAcJKSM6BQBnAgAFAAcJKSM6BQBnAgACAAEJAwXV6wAnAAAAAA==.Fathernature:BAABLgAECn8VAAMSAAcJCBnYKAC4AQASAAcJCBnYKAC4AQAbAAEJeQX6OAAlAAAAAA==.Fauna:BAAALgADCgMJAwAAAA==.Fazeup:BAAALgAECgcJBgAAAA==.',
Fe='Feldra:BAABLgAECn8iAAICAAkJgRqAEQA0AgACAAkJgRqAEQA0AgAAAA==.Felfaith:BAAALgADCgQJBAAAAA==.Fester:BAAALgADCgUJBQABLgAECgkJJgAJAJ0WAA==.',
Fi='Fightforbeer:BAAALgAECgEJAQAAAA==.Finnin:BAABLgAECn8jAAMNAAkJCSQDAQA1AwANAAkJCSQDAQA1AwAcAAEJ0gZ4SAAkAAAAAA==.',
Fo='Food:BAABLgAECn8mAAIGAAkJoRj+GQADAgAGAAkJoRj+GQADAgAAAA==.Formidabull:BAAALgAECgEJAQABLgAECgkJIQACAKsdAA==.Foxdiez:BAAALgAECggJEQAAAA==.',
Fr='Freidafondle:BAAALgAECgUJCAAAAA==.Frostbite:BAAALgAECgcJAwAAAA==.Frozenfaith:BAABLgAECn8mAAMdAAkJUwstFgCLAQAdAAgJ1gstFgCLAQAeAAMJMgTLRABSAAAAAA==.',
Ft='Fthemeta:BAAALgADCgIJAgAAAA==.',
Fu='Furioushealz:BAABLgAECn8nAAIKAAkJpxksFABYAgAKAAkJpxksFABYAgAAAA==.',
Ga='Gardrius:BAAALgADCgYJBwAAAA==.',
Gh='Ghettomike:BAABLgAECn8mAAIYAAkJ/x3iDwCAAgAYAAkJ/x3iDwCAAgAAAA==.Ghoulbane:BAAALgADCgYJCgAAAA==.',
Gi='Gibbits:BAAALgAECgEJAQAAAA==.Giranimo:BAAALgAECgcJEQAAAA==.',
Gl='Glabados:BAAALgAECgIJAwABLgAECgkJJwAZADYiAA==.Glossy:BAACLgAFFH8VAAMDAAUJViLdAwCaAQADAAQJViLdAwCaAQAEAAMJ4hBKBQCnAAAuAAQKfykABAMACQniJZUDAGMDAAMACQmDJZUDAGMDAAQAAgmEIVEKAMwAAA8AAgkNHywUALsAAAAA.Glossycumbus:BAAALgADCgYJBgABLgAFFAUJFQADAFYiAA==.Glossydh:BAAALgAECgYJBgABLgAFFAUJFQADAFYiAA==.Glossydk:BAAALgAECgQJBQABLgAFFAUJFQADAFYiAA==.Glossylock:BAAALgADCgcJDQABLgAFFAUJFQADAFYiAA==.',
Go='Golbigold:BAAALgAECgEJAQAAAA==.Goopy:BAAALgAECgMJAwAAAA==.',
Gr='Grayhoff:BAABLgAECn8cAAINAAkJkAslEwDUAQANAAkJkAslEwDUAQAAAA==.Greatclaw:BAAALgADCgMJAwAAAA==.Grewsom:BAACLgAFFH8JAAIKAAQJ+R1iDwBqAQAKAAQJ+R1iDwBqAQAuAAQKfycAAwoACAnaJWAJAEYDAAoACAnaJWAJAEYDAB8ABQmwH3YTAJQBAAAA.',
Gu='Gulmok:BAAALgADCgUJBQAAAA==.Guwugga:BAAALgAECgYJDAAAAA==.',
Ha='Halîk:BAAALgAECggJEgAAAA==.Haraka:BAAALgAECgMJBAAAAA==.Harmshock:BAABLgAECn89AAIOAAkJgyRVAABPAwAOAAkJgyRVAABPAwAAAA==.Hathina:BAACLgAFFH8OAAINAAQJriPCBQB3AQANAAQJriPCBQB3AQAuAAQKfyoAAw0ACQmjJSEEAGkDAA0ACQmjJSEEAGkDABwAAwmCHykeAP4AAAAA.',
He='Heket:BAABLgAECn8qAAIKAAgJlwfeXQAzAQAKAAgJlwfeXQAzAQAAAA==.Hektric:BAAALgAECgMJAwAAAA==.',
Hi='Highdra:BAAALgAECgEJAQAAAA==.Hill:BAABLgAECn8nAAIGAAkJhR+QCQCdAgAGAAkJhR+QCQCdAgAAAA==.Hive:BAABLgAECn8lAAINAAkJExT/DQANAgANAAkJExT/DQANAgAAAA==.',
Ho='Holygem:BAAALgAECgYJCgAAAA==.Holypower:BAAALgADCgcJDQAAAA==.Hotdogwater:BAABLgAECn8cAAILAAgJDyLuAwAJAwALAAgJDyLuAwAJAwABLgAECgcJHAATAOQkAA==.',
Hu='Husentar:BAABLgAECn8oAAIHAAgJyB4vFwBiAgAHAAgJyB4vFwBiAgAAAA==.Huuhablo:BAABLgAECn83AAICAAkJMRt6DQBgAgACAAkJMRt6DQBgAgAAAA==.',
Ic='Icaron:BAAALgAECgcJCQAAAA==.',
Ig='Igothots:BAAALgAECgMJAwAAAA==.',
Il='Illuminottey:BAAALgAECggJCwAAAA==.',
In='Inferium:BAAALgADCgYJBgABLgAFFAQJCwAMAAAAAA==.Infernom:BAAALgADCgMJAwABLgAFFAQJCwAMAAAAAA==.Insatiabull:BAABLgAECn8hAAMCAAkJqx28EgDqAgACAAgJ7x68EgDqAgAFAAEJyxQRNwBLAAAAAA==.',
Io='Iolchsk:BAAALgAECgQJDAAAAA==.',
Ja='Jacksof:BAABLgAECn8UAAMgAAYJ7gWWNAC7AAAgAAYJ7gWWNAC7AAAdAAQJOQQmOwBgAAAAAA==.Jackstands:BAABLgAECn85AAMLAAkJTSDdBADwAgALAAkJTSDdBADwAgAOAAgJgAV1DABBAQAAAA==.Jagerin:BAAALgAECgYJCwABLgAECgkJJwAZADYiAA==.January:BAAALgAECgYJBgABLgAFFAQJCwAGALwRAA==.Jasmyne:BAAALgADCgYJBgAAAA==.',
Je='Jeromy:BAAALgAECgEJAQAAAA==.Jesse:BAAALgADCgIJAgAAAA==.',
Ji='Jiffi:BAABLgAECn8ZAAIhAAgJyRrwBQA8AgAhAAgJyRrwBQA8AgAAAA==.Jinksy:BAAALgAECgQJCAAAAA==.',
Jm='Jme:BAAALgAECgcJCQAAAA==.',
Jr='Jredz:BAAALgADCgEJAQAAAA==.',
Ju='Jubag:BAAALgADCgIJAgAAAA==.Jumpercables:BAAALgAECgEJBAAAAA==.Junn:BAABLgAECn8nAAIiAAkJmBOADgD3AQAiAAkJmBOADgD3AQAAAA==.',
Ka='Kahayman:BAABLgAECn8oAAIHAAgJtRvmHAA9AgAHAAgJtRvmHAA9AgAAAA==.Karellen:BAAALgAECgYJBgAAAA==.',
Kh='Khathani:BAAALgAECgQJBQAAAA==.',
Ki='Kieran:BAAALgADCgUJBQAAAA==.',
Kn='Knobgoblinn:BAAALgAECgQJBAAAAA==.',
Ko='Komojo:BAABLgAECn8ZAAIKAAcJXQ3JVwBCAQAKAAcJXQ3JVwBCAQAAAA==.Koriggan:BAABLgAECn8bAAQQAAcJwBBQEgCOAQAQAAcJww9QEgCOAQAGAAYJKhB4VQBoAQAIAAEJ6QBgmwAUAAAAAA==.',
Kr='Krea:BAABLgAECn8bAAIfAAcJFSP4AwBTAgAfAAcJFSP4AwBTAgAAAA==.Krixx:BAAALgADCgEJAQAAAA==.Krystagosa:BAABLgAECn8mAAQjAAgJVw8PEAA9AQAjAAgJVw8PEAA9AQAWAAYJJg+yJgAYAQAXAAMJVAonDwCVAAAAAA==.',
Ku='Kuriuh:BAABLgAECn8mAAIJAAkJnRYZFwAqAgAJAAkJnRYZFwAqAgAAAA==.Kurtcobainn:BAAALgADCgkJCQAAAA==.',
La='Lang:BAABLgAECn8oAAIhAAgJthzwAgA4AgAhAAgJthzwAgA4AgAAAA==.',
Le='Legionslamm:BAAALgADCgUJBQAAAA==.Leonldas:BAAALgADCgEJAQAAAA==.',
Li='Lightsfaith:BAAALgADCgYJBgABLgAECgkJJgAdAFMLAA==.',
Lo='Loopey:BAAALgAECgcJEAABLgAFFAQJEQAZAMMQAA==.Lorethil:BAAALgADCgcJEAAAAA==.',
Lu='Luceriss:BAABLgAECn8WAAIDAAgJnQ/zDQDDAQADAAgJnQ/zDQDDAQAAAA==.',
Ma='Maeroth:BAAALgADCgUJBQABLgAFFAUJDgAJAHwNAA==.Magicboi:BAAALgAECgYJEAAAAA==.Magwar:BAACLgAFFH8JAAINAAUJ1Ay0EwDiAAANAAUJ1Ay0EwDiAAAuAAQKfygAAg0ACQluHJgZAH8CAA0ACQluHJgZAH8CAAAA.Maike:BAABLgAECn8WAAIPAAcJCw6xBwBiAQAPAAcJCw6xBwBiAQAAAA==.Marcelyne:BAAALgAECgMJAwABLgAECggJHwAJAC8VAA==.Marothius:BAACLgAFFH8OAAQJAAUJfA23KADTAAAJAAQJZQy3KADTAAAkAAEJvxANFABWAAAlAAEJWABcCwAfAAAuAAQKfyoAAyQACQkpHA4XAJEBACQABgmLHA4XAJEBAAkACAmFGTxsAIkBAAAA.Martaug:BAABLgAECn8fAAILAAgJgx5oDABqAgALAAgJgx5oDABqAgAAAA==.Marune:BAAALgAECgkJDwAAAA==.Maurice:BAAALgADCgYJCwAAAA==.Maverage:BAABLgAECn8mAAMNAAgJCiB5CABiAgANAAgJCiB5CABiAgAcAAYJ6xP7DwBIAQAAAA==.Mawg:BAAALgAECgYJBwAAAA==.Mayfair:BAAALgAECgYJDgAAAA==.',
Mb='Mbarnes:BAAALgAECgQJBAAAAA==.',
Me='Melee:BAACLgAFFH8nAAIKAAgJDSQjAAD2AgAKAAgJDSQjAAD2AgAuAAQKfxQAAgoACQmZJjwCALoDAAoACQmZJjwCALoDAAAA.',
Mi='Midnightfear:BAAALgADCgcJBwAAAA==.Mikeyy:BAAALgADCgMJAwAAAA==.Mimoza:BAAALgAECgQJBAAAAA==.Minibeer:BAAALgAECgYJEgAAAA==.Minimee:BAAALgAECgEJAQAAAA==.Miquella:BAAALgAECgUJCgAAAA==.Misohotramen:BAACLgAFFH8LAAICAAQJ4BipFgBQAQACAAQJ4BipFgBQAQAuAAQKfyEAAgIACQkrIK0zACsCAAIACQkrIK0zACsCAAAA.',
Mo='Moist:BAABLgAECn8oAAIVAAgJ4iLeAQCyAgAVAAgJ4iLeAQCyAgAAAA==.Moofish:BAAALgAECgQJAQAAAA==.Moonlock:BAAALgADCgYJCgAAAA==.Moor:BAAALgAECggJDgAAAA==.Mordakka:BAAALgAECgYJCQAAAA==.Morior:BAABLgAECn8wAAMJAAkJRxssEABlAgAJAAgJRxssEABlAgAkAAIJMBivUQB5AAAAAA==.Motgustus:BAAALgAECgUJBwAAAA==.',
Mu='Muirfire:BAAALgADCgYJBgAAAA==.Murrda:BAABLgAECn8kAAMJAAgJBSDjEABeAgAJAAgJBSDjEABeAgAlAAEJnwXLGQAoAAAAAA==.Musk:BAAALgAECgIJAgABLgAECgcJHAAHAHEUAA==.Muskrattsam:BAABLgAECn8cAAIHAAcJcRRmSgCJAQAHAAcJcRRmSgCJAQAAAA==.',
My='Myravia:BAABLgAECn8WAAIHAAcJrxAnkQCxAQAHAAcJrxAnkQCxAQAAAA==.Myrokos:BAABLgAECn85AAIKAAkJFiG7BQDyAgAKAAkJFiG7BQDyAgAAAA==.',
['Mó']='Mónónoke:BAAALgADCgMJAwAAAA==.',
['Mö']='Möokss:BAAALgADCgQJAgAAAA==.',
Na='Nailo:BAABLgAECn85AAIVAAkJvBCtCACeAQAVAAkJvBCtCACeAQAAAA==.Nails:BAAALgAECgIJAgAAAA==.Nathanos:BAAALgAECggJCwAAAA==.',
Ne='Nezar:BAAALgAFFAEJAwABLgAFFAEJBAAMAAAAAA==.',
Nh='Nhat:BAAALgAECgMJAwAAAA==.',
Ni='Niaah:BAAALgADCgYJAQABLgAECggJEgAMAAAAAA==.Niddy:BAABLgAECn8fAAIHAAcJKRSVSgCIAQAHAAcJKRSVSgCIAQAAAA==.Nisardela:BAAALgADCgMJAwAAAA==.',
No='Nobudy:BAACLgAFFH8UAAMgAAUJ4CE4BgB7AQAgAAUJ4CE4BgB7AQAdAAQJzAKsFgD3AAAuAAQKfygABCAACQnOItgGAB0DACAACQnOItgGAB0DAB4ABgnIFcQuAIgBAB0AAgnNBN9ZAC4AAAAA.Noel:BAAALgAECgUJDAAAAA==.Nomsayin:BAABLgAECn8uAAIJAAgJ1RlAJwDKAQAJAAgJ1RlAJwDKAQAAAA==.Nonospot:BAABLgAECn8eAAMgAAgJfhO2EADHAQAgAAgJfhO2EADHAQAdAAEJvANGWgAuAAAAAA==.Noobuddy:BAAALgAECgUJCgABLgAFFAUJFAAgAOAhAA==.Noraboo:BAABLgAECn8jAAMaAAgJQRqjBAD7AQAaAAYJbxyjBAD7AQAHAAgJmRhZKgD4AQAAAA==.Norannestra:BAAALgAECgQJBwAAAA==.Novalicious:BAAALgADCgIJAgAAAA==.Novasera:BAAALgAECgcJCAAAAA==.',
Nu='Nubmuffin:BAAALgADCgUJBQAAAA==.',
Nv='Nvied:BAABLgAECn8cAAMJAAkJpBQMHQACAgAJAAgJpBQMHQACAgAkAAEJAADucwAxAAAAAA==.',
Ny='Nyctt:BAABLgAECn8YAAMDAAkJ8BlKGQA6AgADAAkJUhhKGQA6AgAPAAIJ5xdmFgCSAAAAAA==.Nystra:BAAALgAECgYJBgAAAA==.Nyzstra:BAABLgAECn8wAAIHAAkJXiJJBgAKAwAHAAkJXiJJBgAKAwAAAA==.',
['Nê']='Nêwt:BAABLgAECn8oAAIHAAkJkxhcFgBoAgAHAAkJkxhcFgBoAgAAAA==.',
['Nì']='Nìrvana:BAAALgAECgQJCwAAAA==.',
On='Onlybeams:BAABLgAECn8fAAICAAkJQBsSCwB7AgACAAkJQBsSCwB7AgAAAA==.',
Or='Orphu:BAAALgAECgEJAQAAAA==.',
Pa='Pallyplexity:BAAALgAECgYJBgABLgAECgkJJgARANglAA==.Palmiste:BAAALgAECgQJBgAAAA==.Pangoplexity:BAAALgADCgIJAgAAAA==.Partyhard:BAAALgADCgYJCwAAAA==.Pastrydragon:BAACLgAFFH8JAAIWAAMJxBfWEAD7AAAWAAMJxBfWEAD7AAAuAAQKfyoAAxYACAmpINMKAMgCABYACAmPHtMKAMgCABcABglYI5ILACICAAAA.',
Pi='Pistachio:BAABLgAECn8UAAIFAAYJSA3AGgAHAQAFAAYJSA3AGgAHAQAAAA==.Pitviper:BAABLgAECn8mAAIPAAkJ4x75AAC8AgAPAAkJ4x75AAC8AgAAAA==.',
Po='Pocketrokit:BAAALgAECgkJCAAAAA==.Pogaca:BAAALgAECgUJBwABLgAECggJFwASAP8bAA==.Portabull:BAAALgADCgcJBwABLgAECgkJIQACAKsdAA==.Possess:BAABLgAECn8kAAIJAAcJ8RybHwDzAQAJAAcJ8RybHwDzAQAAAA==.Pownora:BAABLgAECn8bAAMmAAcJdxu8DADsAQAmAAcJdxu8DADsAQAnAAIJ/Q14VwAwAAABLgAECggJIwAaAEEaAA==.',
Ps='Psarchasm:BAABLgAECn8bAAINAAcJ6gwYIgBdAQANAAcJ6gwYIgBdAQAAAA==.',
Pu='Puck:BAAALgAECgEJAgAAAA==.Pugstar:BAAALgAECgMJAwAAAA==.',
Qe='Qel:BAAALgADCgYJCQAAAA==.',
Ra='Rai:BAABLgAECn8oAAIGAAgJxiP7BQDSAgAGAAgJxiP7BQDSAgAAAA==.Rancidbeef:BAAALgAECgMJAwAAAA==.Rapha:BAABLgAECn8nAAIZAAkJNiKJAQAXAwAZAAkJNiKJAQAXAwAAAA==.Rayyzer:BAABLgAECn8cAAIDAAkJqCGrAQD5AgADAAkJqCGrAQD5AgAAAA==.',
Re='Rema:BAAALgADCgQJBAAAAA==.Reyna:BAAALgADCgUJBQAAAA==.',
Ri='Riddles:BAAALgAECggJEgAAAA==.Rincewind:BAAALgAECgEJAQAAAA==.',
Ro='Rossabella:BAABLgAECn82AAMeAAkJMRdfCABpAgAeAAkJ+RZfCABpAgAdAAgJ0w6PFACcAQAAAA==.Rot:BAABLgAECn8nAAIoAAkJCSZpAABdAwAoAAkJCSZpAABdAwAAAA==.',
Ru='Rude:BAAALgAECgYJBgABLgAFFAQJDgANAK4jAA==.Ruzala:BAAALgADCgEJAQAAAA==.',
Sa='Samsonn:BAAALgADCgQJBAAAAA==.Sanctity:BAAALgADCgYJCgAAAA==.Santino:BAAALgAECggJCgABLgAECggJKAAHALUbAA==.Saphlocket:BAAALgAECgMJCAAAAA==.Sathin:BAABLgAECn8hAAICAAgJlAjQRQAnAQACAAgJlAjQRQAnAQAAAA==.',
Sc='Scher:BAAALgADCgkJCwAAAA==.Scufalufagus:BAAALgAECgUJBQABLgAFFAUJDgAJAHwNAA==.',
Se='Seetick:BAAALgAECgIJBAAAAA==.Sefekat:BAAALgAECgEJAQABLgAECgkJHwACAEAbAA==.September:BAAALgAECgIJAgABLgAFFAQJCwAGALwRAA==.Sevatar:BAABLgAECn8VAAIFAAgJ7woHEwBaAQAFAAgJ7woHEwBaAQAAAA==.',
Sf='Sfcwarner:BAAALgADCgMJAwAAAA==.',
Sh='Shampooyou:BAABLgAECn8UAAILAAYJCwbHSADdAAALAAYJCwbHSADdAAAAAA==.Shockakhan:BAAALgAECgUJBgAAAA==.Shocknstone:BAAALgADCgcJBwABLgAECgkJJgARANglAA==.',
Si='Silentmamba:BAAALgAECgEJAQAAAA==.Sinistra:BAAALgAECgEJAQAAAA==.',
Sk='Skelecopter:BAAALgADCgMJAwAAAA==.',
Sn='Snowflake:BAAALgADCgcJBwAAAA==.',
Sp='Spellsteal:BAABLgAECn8iAAIHAAkJ6RclGwBHAgAHAAkJ6RclGwBHAgAAAA==.Spicynudz:BAAALgAECgEJAQAAAA==.Splashmountn:BAEALgAECgEJAgABLgAECgYJDwAMAAAAAA==.Spring:BAACLgAFFH8LAAMGAAQJvBGJFABKAQAGAAQJvBGJFABKAQAIAAEJpAD7LQA2AAAuAAQKfyMAAwYACQlfHdcNAGsCAAYACQkjHdcNAGsCAAgABgnTC+1MAB0BAAAA.',
Ss='Ssgwarner:BAAALgADCgQJAQAAAA==.',
St='Stardel:BAAALgAECgYJDQAAAA==.Sting:BAAALgADCgEJAQAAAA==.Stormclaw:BAABLgAECn8lAAITAAgJFR3ADQBzAgATAAgJFR3ADQBzAgAAAA==.Stormcrash:BAAALgADCgYJBgABLgAECgkJJgAJAJ0WAA==.Stregoica:BAAALgADCgcJDgABLgAFFAUJDgAJAHwNAA==.',
Su='Suhfering:BAAALgADCgYJBgABLgAECgkJHwACAEAbAA==.Sushiiez:BAAALgADCgMJAwAAAA==.Suwo:BAAALgADCgIJAQAAAA==.',
Ta='Tallron:BAACLgAFFH8TAAITAAUJeRvjCQCdAQATAAUJeRvjCQCdAQAuAAQKfyUAAxMACQmrI7cJAPcCABMACQmrI7cJAPcCABIAAQnqBxFZADAAAAAA.Tallsera:BAAALgADCgcJDQABLgAFFAUJEwATAHkbAA==.Tallyfan:BAAALgADCgcJEwAAAA==.Tandraella:BAAALgAECgQJBAABLgAFFAQJBgABAFUTAA==.Taroquin:BAAALgADCgEJAQAAAA==.',
Te='Ternay:BAAALgADCgIJAQAAAA==.Teskhamen:BAAALgAECgQJBAAAAA==.Tetamesh:BAAALgADCgQJBAAAAA==.',
Th='Theskabandit:BAAALgADCgcJEQAAAA==.',
Ti='Tiamot:BAAALgADCgUJCAAAAA==.',
To='Tojikitoushi:BAABLgAECn8oAAIOAAkJMR5AAQDVAgAOAAkJMR5AAQDVAgAAAA==.Tombs:BAAALgAECgYJCAAAAA==.Totenhammer:BAAALgAECgQJCwAAAA==.Totenplage:BAAALgAECgQJBAAAAA==.',
Tr='Trid:BAAALgAECggJCAAAAA==.Tristex:BAAALgAECgEJAQABLgAECggJFwASAP8bAA==.',
Tu='Tuha:BAAALgAFFAEJAQAAAA==.',
Tw='Twergstronk:BAAALgADCgEJAQAAAA==.',
Ty='Tyrolia:BAAALgAECgMJAwAAAA==.',
Va='Valliya:BAAALgADCgcJEwAAAA==.',
Ve='Velratha:BAABLgAECn8UAAIlAAgJtQ/yBQBeAQAlAAgJtQ/yBQBeAQAAAA==.Vesfu:BAAALgADCgEJAQAAAA==.Vesi:BAAALgADCgcJCgAAAA==.Vextt:BAABLgAECn8eAAMgAAgJDBjSEgCwAQAgAAcJRhvSEgCwAQAeAAIJeBhlRwBIAAAAAA==.',
Vi='Vicsta:BAAALgAECgYJBwAAAA==.',
Vo='Voidrend:BAAALgAECgQJBwAAAA==.Volight:BAAALgADCgYJCQAAAA==.Volke:BAABLgAECn8nAAInAAkJNRbCCgBAAgAnAAkJNRbCCgBAAgAAAA==.Volq:BAAALgAECgEJAQAAAA==.Voltarix:BAAALgAECgQJBAAAAA==.Voodoopriest:BAABLgAECn8YAAIJAAcJMwQ5pAAQAQAJAAcJMwQ5pAAQAQAAAA==.Voyria:BAABLgAECn8nAAQTAAgJ7wQURgD7AAATAAgJ7wQURgD7AAASAAQJVwQTRgBnAAAbAAIJwQI1JgA4AAAAAA==.',
Vs='Vs:BAAALgAECgYJBgAAAA==.',
Vy='Vynlenn:BAAALgADCgMJAwAAAA==.Vyskar:BAAALgAECgMJAwAAAA==.',
Wa='Warm:BAACLgAFFH8OAAImAAUJ8hy7BABwAQAmAAUJ8hy7BABwAQAuAAQKfyUAAiYACQmVIWcIAPMCACYACQmVIWcIAPMCAAAA.Warmlight:BAAALgAECgYJDAAAAA==.',
We='Weewu:BAAALgAECgQJBAAAAA==.Weeziveli:BAAALgAECgQJBAAAAA==.Weledish:BAACLgAFFH8KAAIHAAMJpxNsRAABAQAHAAMJpxNsRAABAQAuAAQKfyYAAgcACAmaGytIAF8CAAcACAmaGytIAF8CAAAA.',
Wi='Wienercat:BAABLgAECn8cAAITAAcJ5CSWBgDnAgATAAcJ5CSWBgDnAgAAAA==.Windmacedu:BAAALgAECgYJCgAAAA==.',
Xt='Xtreeme:BAAALgAECgIJAgAAAA==.',
Ya='Yael:BAABLgAECn8hAAICAAgJex7SEwAeAgACAAgJex7SEwAeAgAAAA==.',
Za='Zarewien:BAABLgAECn8fAAIeAAgJnAcfIgA4AQAeAAgJnAcfIgA4AQAAAA==.',
Zi='Ziddles:BAAALgAECgYJEAAAAA==.',
Zo='Zomgdk:BAAALgAECgEJAgABLgAECggJNwAZAFcfAA==.Zomgmonk:BAABLgAECn83AAIZAAgJVx+SBgBuAgAZAAgJVx+SBgBuAgAAAA==.',
Zu='Zuraq:BAAALgAECgEJAgAAAA==.Zurisdad:BAABLgAECn8nAAIZAAgJixcmDAAAAgAZAAgJixcmDAAAAgABLgAFFAQJDAAHANUSAA==.Zurishmi:BAACLgAFFH8WAAILAAUJpBzRCACOAQALAAUJpBzRCACOAQAuAAQKfyoAAgsACQmuJBIEADQDAAsACQmuJBIEADQDAAAA.',
['Äm']='Ämäteräsu:BAAALgAECgYJBwAAAA==.',
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
