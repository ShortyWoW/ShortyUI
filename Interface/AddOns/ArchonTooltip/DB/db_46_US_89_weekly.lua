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

local lookup = {'Mage-Frost','Shaman-Restoration','Shaman-Elemental','Paladin-Holy','Unknown-Unknown','Hunter-BeastMastery','DemonHunter-Devourer','DeathKnight-Blood','Evoker-Augmentation','Evoker-Preservation','Paladin-Protection','Druid-Restoration','Hunter-Survival','Hunter-Marksmanship','Warrior-Protection','Druid-Balance','DeathKnight-Unholy','Paladin-Retribution','Druid-Feral','Evoker-Devastation','DemonHunter-Havoc','Shaman-Enhancement','Warrior-Fury','Priest-Shadow','Druid-Guardian','Rogue-Subtlety','Monk-Mistweaver','Monk-Windwalker','Priest-Holy','Monk-Brewmaster','Warlock-Demonology','Warlock-Destruction','Mage-Arcane','DemonHunter-Vengeance','Mage-Fire','Warlock-Affliction','Rogue-Outlaw','Rogue-Assassination','DeathKnight-Frost',}
local provider = {region='US',realm='Eonar',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abbazaad:BAAALgAECgQJBQAAAA==.Abreen:BAAALgADCgcJCQAAAA==.Abysseus:BAAALgADCgcJCAAAAA==.',
Ac='Acepriest:BAAALgAECgMJBAAAAA==.Achievement:BAAALgAECgQJBAAAAA==.',
Ad='Adeathfox:BAAALgADCgEJAQAAAA==.Admired:BAABLgAECn8WAAIBAAcJoB4GVwAzAgABAAcJoB4GVwAzAgAAAA==.Adyr:BAABLgAECn8gAAMCAAgJlB9rDwBFAgACAAgJlB9rDwBFAgADAAUJtxdFTQATAQAAAA==.',
Ai='Aidra:BAABLgAECn8XAAIEAAUJ5xnDIACBAQAEAAUJ5xnDIACBAQAAAA==.',
Al='Alaira:BAAALgAECgMJAwABLgAECgUJCgAFAAAAAA==.Alamora:BAAALgAECgQJCwAAAA==.Alastair:BAAALgAECgcJCAAAAA==.Alathena:BAAALgAECgcJDAAAAA==.Albinoz:BAAALgADCgIJAgAAAA==.Albrect:BAAALgADCgYJEQAAAA==.Aldrich:BAAALgADCgEJAQAAAA==.Alexandrya:BAABLgAECn8aAAIGAAgJfBY0HQDtAQAGAAgJfBY0HQDtAQAAAA==.Alicemalkin:BAABLgAECn8XAAIHAAkJHRTrPQD8AQAHAAkJHRTrPQD8AQAAAA==.Alysse:BAAALgADCgUJBwAAAA==.',
Am='Amarysia:BAAALgAECgYJCQAAAA==.Ameriixs:BAAALgAECgIJAgAAAA==.Amsip:BAAALgAECgEJAQABLgAECgcJGAAIAD8OAA==.Amsroeb:BAABLgAECn8YAAIIAAcJPw5gFwATAQAIAAcJPw5gFwATAQAAAA==.',
An='Anelavenger:BAACLgAFFH8HAAIJAAMJpw5OIgDhAAAJAAMJpw5OIgDhAAAuAAQKfy0AAwkACQnYHMcMAKkCAAkACQnYHMcMAKkCAAoAAwlaASxEAE0AAAAA.Anggar:BAAALgADCgIJAgAAAA==.',
Ao='Aomori:BAAALgAECgcJBwAAAA==.',
Aq='Aqüilés:BAAALgAECgEJAgAAAA==.',
Ar='Arathor:BAABLgAECn8dAAILAAgJIhkABwDrAQALAAgJIhkABwDrAQAAAA==.Arctorius:BAAALgADCgEJAQAAAA==.Arent:BAABLgAECn8rAAIMAAkJbxOJGwDnAQAMAAkJbxOJGwDnAQAAAA==.Arfy:BAAALgADCgMJAgABLgAECgcJDgAFAAAAAA==.Argøn:BAABLgAECn8lAAQGAAkJwRaMHQDrAQAGAAkJwRaMHQDrAQANAAUJ2AirJQDLAAAOAAEJkAYQkgAoAAAAAA==.Arkanna:BAAALgAECgEJAQAAAA==.Arrise:BAAALgAECgQJBQAAAA==.Artemislives:BAAALgAECgcJCAAAAA==.Arthuaca:BAAALgAECgYJDQAAAA==.',
As='Asharia:BAAALgAECgYJDQAAAA==.Ashog:BAAALgADCgUJBQAAAA==.Assateague:BAAALgAECgQJCgAAAA==.Astralie:BAAALgADCgcJCAAAAA==.Asuya:BAAALgADCgYJCQAAAA==.',
At='Athylan:BAAALgADCgEJAQABLgAFFAQJDgAEAHUeAA==.Atrosity:BAABLgAECn8kAAIPAAkJoSJLAQAGAwAPAAkJoSJLAQAGAwAAAA==.',
Au='Aurorabane:BAAALgADCgUJBwAAAA==.',
Av='Avelleah:BAAALgAECgEJBAAAAA==.',
Az='Azulyne:BAAALgADCgIJAgAAAA==.Azuretorrent:BAAALgADCgQJBAAAAA==.',
Ba='Bananapistol:BAAALgAECgUJBQAAAA==.Barrathfrogy:BAAALgADCgUJDAAAAA==.',
Be='Bebheishel:BAAALgADCgUJBQAAAA==.Bertelo:BAAALgADCgUJBQAAAA==.',
Bi='Bigstinky:BAAALgAECgEJAgAAAA==.Bisao:BAAALgAECgIJAgAAAA==.Biscuít:BAABLgAECn8nAAIQAAkJDQ4KFQCXAQAQAAkJDQ4KFQCXAQAAAA==.',
Bl='Blasuoff:BAAALgAECgQJBAAAAA==.Bloodrains:BAAALgAECgEJAwAAAA==.Bloodyfate:BAAALgADCgUJBQAAAA==.',
Bo='Bonesentinel:BAAALgAECgcJDgABLgAFFAQJCgARAAUYAA==.Bonës:BAAALgADCgEJAQAAAA==.Bora:BAAALgAECgQJDgAAAA==.Borzoi:BAABLgAFFH8IAAISAAMJKhwNKAAMAQASAAMJKhwNKAAMAQAAAA==.Bourgùîgnon:BAAALgADCgcJCgAAAA==.',
Br='Bragasch:BAAALgADCgkJGQAAAA==.Brakhon:BAAALgAECgEJAQAAAA==.Bruisebrews:BAAALgADCgEJAQAAAA==.',
Bu='Bullplop:BAAALgADCgUJBQAAAA==.Burekbazino:BAAALgADCgcJCQAAAA==.Burningsleet:BAAALgAECgYJBgABLgAFFAYJDQARAJQdAA==.',
['Bò']='Bò:BAABLgAECn8uAAIQAAkJ6BS7CQAxAgAQAAkJ6BS7CQAxAgAAAA==.',
Ca='Caduceus:BAAALgADCgcJEgAAAA==.Caesus:BAAALgAECgYJDwAAAA==.Cagedancer:BAABLgAECn8cAAMTAAYJiwipFADaAAATAAYJ7wapFADaAAAQAAYJyAYFOQCmAAAAAA==.Callio:BAABLgAECn8vAAIGAAkJmxFPGgAAAgAGAAkJmxFPGgAAAgAAAA==.Cantor:BAAALgAECgEJAQAAAA==.Catchclause:BAAALgADCgkJFAAAAA==.Cathillex:BAAALgAECgcJDwAAAA==.Cavagos:BAABLgAECn81AAIUAAkJVSB5AAAEAwAUAAkJVSB5AAAEAwAAAA==.Caycay:BAACLgAFFH8PAAIVAAUJ+yD1AQCMAQAVAAUJ+yD1AQCMAQAuAAQKfzoAAhUACQlqJfEAAL4DABUACQlqJfEAAL4DAAAA.',
Ce='Celebrexi:BAAALgAECgcJBgAAAA==.Celene:BAAALgADCgYJBwAAAA==.Cerrulli:BAAALgAECgYJDwAAAA==.',
Ch='Chaosknight:BAAALgAECgYJEgAAAA==.Chaostrip:BAABLgAECn8kAAIHAAgJZSIlCQCSAgAHAAgJZSIlCQCSAgAAAA==.Chillbros:BAACLgAFFH8KAAIWAAQJGR+2AgBUAQAWAAQJGR+2AgBUAQAuAAQKfyIAAxYACAmOJPkBADwDABYACAkQJPkBADwDAAMABAmqH+k5AGcBAAAA.Chilldh:BAAALgAECgUJBQABLgAFFAQJCgAWABkfAA==.Chillmage:BAAALgADCgcJCgABLgAFFAQJCgAWABkfAA==.Chindi:BAABLgAECn8oAAIXAAkJKhbwCQBJAgAXAAkJKhbwCQBJAgAAAA==.Choiminasue:BAAALgAECgEJAgAAAA==.Chunga:BAABLgAECn8UAAIDAAYJoAPSXADQAAADAAYJoAPSXADQAAAAAA==.Chungers:BAAALgAECgQJBgAAAA==.Churd:BAABLgAECn8lAAIYAAgJcRjdCgAWAgAYAAgJcRjdCgAWAgAAAA==.Churdicus:BAAALgADCgkJEQAAAA==.Chypnotic:BAAALgAECgcJAQAAAA==.Chypper:BAAALgADCgEJAQAAAA==.Chypster:BAABLgAECn8UAAIDAAUJ5wwUOADNAAADAAUJ5wwUOADNAAAAAA==.',
Ci='Ciceroe:BAAALgAECgYJBwAAAA==.Citadel:BAAALgADCgIJAwAAAA==.',
Cl='Cleft:BAAALgAECgUJCQAAAA==.',
Co='Coalystra:BAABLgAECn8sAAIHAAkJ6RoGCwB7AgAHAAkJ6RoGCwB7AgAAAA==.Cocopuffs:BAACLgAFFH8HAAIQAAIJrxGwFACfAAAQAAIJrxGwFACfAAAuAAQKfzUAAhAACQleIAUGAIECABAACQleIAUGAIECAAAA.Colostrom:BAABLgAECn8vAAILAAkJ1R8mAgCfAgALAAkJ1R8mAgCfAgAAAA==.Complicatedz:BAAALgAECgQJBAAAAA==.Comul:BAAALgADCgcJBwAAAA==.Coramage:BAABLgAECn8XAAIBAAcJWwaRdwAiAQABAAcJWwaRdwAiAQAAAA==.Corentis:BAAALgADCgYJBgAAAA==.Corliss:BAAALgAECgcJEwAAAA==.',
Cp='Cplusmc:BAAALgAECgMJAwAAAA==.',
Cr='Creightizle:BAABLgAECn8eAAIGAAgJdxS7OQDHAQAGAAgJdxS7OQDHAQAAAA==.',
['Cá']='Cátix:BAAALgADCgIJAgAAAA==.',
Da='Daicmerollin:BAAALgAECgYJCwAAAA==.Danhaüsen:BAAALgAECgIJAwAAAA==.Darkbeast:BAAALgAECgkJCQAAAA==.Darkdeeds:BAAALgADCggJEQAAAA==.Darkpallo:BAABLgAECn8YAAISAAcJPxPZbwCdAQASAAcJPxPZbwCdAQABLgAECgkJCQAFAAAAAA==.Daten:BAABLgAECn8wAAISAAkJWxIlQQCCAQASAAkJWxIlQQCCAQAAAA==.Dazshauran:BAAALgADCgEJAQAAAA==.Daîma:BAAALgADCggJCAAAAA==.',
De='Deathbycow:BAABLgAECn8jAAIZAAgJbRmnBQD+AQAZAAgJbRmnBQD+AQAAAA==.Decayed:BAABLgAECn8VAAIIAAYJqBZmEwA/AQAIAAYJqBZmEwA/AQAAAA==.Demonchalk:BAAALgAFFAEJAQABLgAFFAQJDgAWAAMmAA==.Desdeynna:BAAALgADCgEJAQAAAA==.Dewbie:BAAALgAECgEJAQAAAA==.',
Di='Diagonalli:BAABLgAECn8YAAIUAAcJMA9vBgBgAQAUAAcJMA9vBgBgAQAAAA==.Dimmadome:BAAALgADCgEJAQAAAA==.Dinojam:BAAALgADCgMJAQAAAA==.Divirian:BAAALgAECgYJDgAAAA==.',
Dj='Djdaemon:BAAALgADCgYJBgAAAA==.Djdrakshadow:BAAALgADCgYJBgAAAA==.Djpaly:BAAALgADCgYJCgAAAA==.Djpriest:BAAALgADCgYJCQAAAA==.Djshadow:BAAALgADCgUJBQAAAA==.Djshadowar:BAAALgADCgYJBgAAAA==.Djshadowhunt:BAAALgADCgYJEAAAAA==.Djshadowlock:BAAALgADCgUJBwAAAA==.Djshadowrog:BAAALgADCgUJBQAAAA==.Djshaolin:BAAALgADCgUJBwAAAA==.Djzhadow:BAAALgADCgYJCQAAAA==.Djzhadruid:BAAALgADCgUJBQAAAA==.',
Dk='Dkshadow:BAAALgADCgYJBgAAAA==.',
Dm='Dmitrì:BAAALgADCgEJAQAAAA==.',
Do='Dogno:BAAALgAECgEJAgAAAA==.Dontdieplez:BAAALgAECggJCwAAAA==.',
Dp='Dpm:BAAALgAECgEJAgAAAA==.',
Dr='Dragbuttakis:BAAALgAECgUJCAAAAA==.Drakhadir:BAAALgADCgYJBwAAAA==.Drakmon:BAAALgAECgEJAQAAAA==.Draktând:BAABLgAECn8fAAIaAAgJERH8DQDCAQAaAAgJERH8DQDCAQAAAA==.Drippysilk:BAAALgAECgQJCAABLgAECgYJGgAUAPwiAA==.Drius:BAAALgADCgMJAwAAAA==.Drunkenpanda:BAABLgAECn8fAAMbAAgJhBUUJQCKAQAbAAgJhBUUJQCKAQAcAAcJSAf/MADBAAAAAA==.Drunknoodle:BAAALgAECgQJCAAAAA==.',
Du='Duhpriest:BAAALgAECgEJAQAAAA==.Duinrane:BAAALgAECgEJAQAAAA==.Duon:BAAALgAECggJEQAAAA==.',
Dw='Dwagonfur:BAAALgAECgcJBgAAAA==.',
Ec='Echö:BAABLgAECn8bAAIVAAgJIhZpCwDNAQAVAAgJIhZpCwDNAQAAAA==.',
Ei='Eirø:BAAALgADCgkJCQABLgAECgkJMwAOAPAiAA==.',
El='Elaine:BAAALgAECgkJDQAAAA==.Elberon:BAAALgAECgIJAgAAAA==.Elmerhomero:BAAALgADCgUJBQAAAA==.Elronnd:BAAALgADCgkJGgAAAA==.Elsebeth:BAAALgADCgcJCAAAAA==.',
Em='Emilie:BAAALgADCgYJBgAAAA==.',
En='Enoch:BAABLgAECn8bAAISAAYJjRZYfwB7AQASAAYJjRZYfwB7AQAAAA==.',
Er='Eriam:BAAALgADCgIJAgABLgAECggJFQAZALMUAA==.Errane:BAACLgAFFH8QAAIMAAQJFSXhBwC6AQAMAAQJFSXhBwC6AQAuAAQKfycAAwwACAnJJowEAEYDAAwACAnJJowEAEYDABAAAQnHFUt4AEQAAAAA.Eruiluvatar:BAAALgAECgYJBgAAAA==.',
Et='Etalia:BAAALgADCgUJBQAAAA==.Etcetera:BAAALgAECgMJAwAAAA==.',
Fa='Fallenangell:BAAALgADCgUJBQAAAA==.Fandiirn:BAAALgADCgYJBgAAAA==.Fastjack:BAABLgAECn8VAAMdAAUJfhdRHwBOAQAdAAUJfhdRHwBOAQAYAAEJAABHXwAAAAAAAA==.',
Fi='Fiora:BAAALgADCgYJCwAAAA==.Firbirl:BAAALgAECgIJAgAAAA==.Fistoffury:BAABLgAECn8WAAMeAAYJPxTSJwAGAQAeAAYJPxTSJwAGAQAcAAQJOAn8WQCoAAAAAA==.Fitco:BAAALgADCgYJCwABLgAECgYJDwAFAAAAAA==.Fiènd:BAAALgADCgYJBgAAAA==.',
Fl='Flametar:BAAALgAECgEJAQAAAA==.Floppydisk:BAAALgAECgUJCwAAAA==.',
Fo='Fortiss:BAABLgAECn8iAAMCAAkJRwhXNAA6AQACAAkJRwhXNAA6AQADAAUJnhD2MwDgAAAAAA==.',
Fr='Frito:BAAALgAECgEJAQAAAA==.Frost:BAAALgAFFAIJAgABLgAFFAYJGQANADgVAA==.Frostmon:BAAALgAECgcJDwAAAA==.Frshnvrfrzn:BAAALgAECggJDwAAAA==.Frøzenblight:BAAALgAECgEJAQAAAA==.',
Fu='Fulmo:BAAALgADCgUJBQABLgAECgkJGQARALsNAA==.Furbee:BAAALgAECggJCwAAAA==.',
['Fá']='Fáde:BAAALgADCgQJBQABLgAECgMJAwAFAAAAAA==.',
Ga='Galeandra:BAAALgAECgYJCwAAAA==.Garim:BAAALgADCgEJAQABLgAECgUJFQAdAH4XAA==.',
Ge='Geraltofrvia:BAAALgAECgcJDAAAAA==.',
Gi='Giantgoose:BAAALgAECgEJAgAAAA==.Gingani:BAAALgADCgcJCQAAAA==.',
Gn='Gnar:BAAALgAECgQJDgAAAA==.',
Go='Gowtherdead:BAAALgADCgQJBAAAAA==.Gowtherpunch:BAABLgAECn8xAAIeAAkJuBVICgAfAgAeAAkJuBVICgAfAgAAAA==.',
Gr='Gregzug:BAAALgAECgEJAQAAAA==.Greyjoy:BAAALgADCgYJBQAAAA==.Grimfury:BAAALgAFFAEJAQAAAA==.Grimsy:BAAALgADCgYJBwAAAA==.Grodd:BAAALgADCgUJBQAAAA==.Groqqu:BAAALgAECgQJBAAAAA==.Grumble:BAAALgAECgIJAgAAAA==.Gruxxiron:BAAALgAECgUJBwABLgAECgkJKgARAHIdAA==.',
Gu='Gulnn:BAABLgAECn8sAAMfAAkJzxtMCgClAgAfAAkJzxtMCgClAgAgAAIJVhT2VABvAAAAAA==.',
Ha='Haelena:BAAALgAECgYJEgAAAA==.Halys:BAAALgADCgUJBQAAAA==.Hamil:BAAALgADCgEJAQAAAA==.Hawk:BAAALgADCgYJBgAAAA==.',
He='Heartsfang:BAAALgADCgUJAwAAAA==.Helfire:BAAALgADCgYJBgABLgAECgMJAwAFAAAAAA==.Hellscreems:BAAALgADCgMJAwAAAA==.Heriotza:BAABLgAECn8ZAAIRAAkJuw1SOwCNAQARAAkJuw1SOwCNAQAAAA==.',
Ia='Iamfubar:BAAALgADCgMJAwAAAA==.',
Ig='Igris:BAAALgAECgcJCgAAAA==.',
Ii='Iimit:BAABLgAECn8aAAIaAAgJ0hrBBgBDAgAaAAgJ0hrBBgBDAgAAAA==.',
Il='Illidead:BAACLgAFFH8SAAIBAAYJ7RkRDgC4AQABAAYJ7RkRDgC4AQAuAAQKfxsAAwEACAldISU7AIoCAAEACAkcHiU7AIoCACEAAQnXHxgXAGEAAAAA.',
Im='Implied:BAAALgADCgUJBQAAAA==.',
In='Indexes:BAAALgAECgQJCQAAAA==.Insrik:BAAALgAECgEJAwAAAA==.',
Io='Iompróirbáis:BAABLgAECn8ZAAIRAAgJtgaFTwBNAQARAAgJtgaFTwBNAQAAAA==.',
Ir='Irdeadohnoz:BAAALgAECgUJDwAAAA==.',
Is='Ist:BAAALgAECgEJAQAAAA==.',
It='Itchigo:BAAALgAECgYJCQAAAA==.',
Iv='Ivern:BAAALgAECgIJAgAAAA==.Ivgorod:BAABLgAECn8ZAAMUAAcJZQkaCgD8AAAUAAcJVAgaCgD8AAAJAAYJuAW0NQDKAAAAAA==.',
Ja='Jambi:BAAALgAECgYJDgAAAA==.Jardani:BAAALgAECgEJAQAAAA==.Jastrae:BAAALgAECgcJDgAAAA==.Jazilyne:BAAALgADCgkJGgAAAA==.',
Je='Jealous:BAAALgADCgUJBQABLgAECgkJIgAHAKMdAA==.Jenka:BAAALgAECgQJCQAAAA==.',
Ji='Jibbs:BAAALgADCgkJCQAAAA==.',
Jo='Joleya:BAAALgADCgEJAQAAAA==.',
Ju='Junta:BAAALgADCgcJHwAAAA==.Justine:BAAALgADCgUJBQAAAA==.Justtrolling:BAAALgAECgYJDgAAAA==.',
['Jä']='Jäkel:BAAALgADCgUJBQAAAA==.',
Ka='Kalike:BAAALgADCgcJBwAAAA==.Kambative:BAABLgAECn8UAAMMAAcJqhIMQgCZAQAMAAcJqhIMQgCZAQAQAAIJRxE4QwBxAAAAAA==.Kammunion:BAAALgADCgMJAwABLgAECgcJFAAMAKoSAA==.Kamphiyer:BAABLgAECn82AAQJAAkJABzBBgBwAgAJAAgJiB3BBgBwAgAKAAkJ6hjxBABWAgAUAAQJowz4EwBSAAABLgAECgcJFAAMAKoSAA==.Kamscendance:BAAALgADCgMJAwABLgAECgcJFAAMAKoSAA==.Kamsumerage:BAAALgADCgkJEgABLgAECgcJFAAMAKoSAA==.Kandosii:BAAALgADCgUJBQAAAA==.Kantheal:BAABLgAECn8ZAAIEAAcJfB4DCgBwAgAEAAcJfB4DCgBwAgAAAA==.Kaulana:BAAALgADCgcJDAAAAA==.',
Ke='Keirmania:BAAALgADCgQJBwAAAA==.Kekkan:BAAALgADCgUJAwAAAA==.Kellendere:BAAALgADCgYJCwAAAA==.',
Ki='Kiieedk:BAAALgAECgEJAQAAAA==.Kimgoeun:BAAALgADCgYJBgAAAA==.Kio:BAAALgAECgYJCAAAAA==.',
Kn='Knùsê:BAAALgADCgUJBgABLgAECgkJMwAOAPAiAA==.',
Ko='Komorai:BAAALgADCgYJBgAAAA==.',
Kr='Kravex:BAABLgAECn8VAAIZAAgJsxT9BwCvAQAZAAgJsxT9BwCvAQAAAA==.Krixxa:BAABLgAECn8fAAIdAAgJsSLnBAC9AgAdAAgJsSLnBAC9AgAAAA==.',
Ku='Kuula:BAAALgADCgUJBQAAAA==.',
Ky='Kylana:BAAALgADCgQJBAAAAA==.',
['Kä']='Kären:BAAALgAECgUJEgAAAA==.',
['Ké']='Kélly:BAAALgAECgcJCAAAAA==.',
La='Laochnaofa:BAAALgAECgYJBgAAAA==.Larayvia:BAABLgAECn8dAAIGAAgJIw5COwDBAQAGAAgJIw5COwDBAQAAAA==.Laurance:BAAALgADCgYJBgAAAA==.',
Le='Leesala:BAABLgAECn8wAAMCAAkJqhc4DABtAgACAAkJqhc4DABtAgAWAAEJ/gRkIQAsAAAAAA==.Lerazer:BAAALgAECgMJAwAAAA==.',
Lg='Lgidk:BAAALgADCgMJAwABLgAECgkJIgAHAKMdAA==.',
Li='Lic:BAAALgAECgEJAQAAAA==.Liliatrix:BAAALgAECgQJBQAAAA==.Lillabet:BAAALgAECgQJCAAAAA==.Lilmatty:BAAALgAECggJCgABLgAECggJCgAFAAAAAA==.Lilsneaky:BAAALgADCggJCAAAAA==.Limpydk:BAAALgADCgUJBQABLgAECgYJGgAUAPwiAA==.Limpylarva:BAAALgADCgMJAwABLgAECgYJGgAUAPwiAA==.Limpypal:BAAALgAECgQJBQABLgAECgYJGgAUAPwiAA==.Litter:BAAALgAECgUJBQAAAA==.',
Lo='Logathil:BAAALgAECgYJEAAAAA==.',
Lu='Luchulainn:BAAALgADCgYJBgAAAA==.Lucifero:BAAALgAECgUJBwAAAA==.Lucifurwild:BAAALgADCgQJBQAAAA==.Lunaaris:BAABLgAECn8rAAIMAAkJCB/cBgDiAgAMAAkJCB/cBgDiAgAAAA==.Lunastre:BAAALgADCgEJAQAAAA==.',
['Lí']='Límpy:BAABLgAECn8aAAIUAAYJ/CJ9CgA0AgAUAAYJ/CJ9CgA0AgAAAA==.Línk:BAAALgAECgYJCgAAAA==.',
['Lî']='Lîkwuid:BAAALgAECggJDwAAAA==.',
Ma='Macallan:BAAALgAECgEJAgAAAA==.Maddrox:BAAALgADCgcJDwAAAA==.Magicmarv:BAAALgADCgIJAQAAAA==.Magnagoth:BAAALgADCgkJDwAAAA==.Magnakilro:BAABLgAECn8aAAIGAAcJHRfdLgCSAQAGAAcJHRfdLgCSAQAAAA==.Mahnaz:BAAALgADCgEJAQABLgADCgcJCgAFAAAAAA==.Malanath:BAABLgAECn8XAAIJAAgJrBWeEADNAQAJAAgJrBWeEADNAQAAAA==.Malothas:BAAALgADCgQJBAAAAA==.Mareki:BAAALgADCgYJBwAAAA==.Markdfordeth:BAAALgADCgcJCQAAAA==.Mattyfu:BAAALgAECggJCgAAAA==.Mavíel:BAAALgAECgYJDQAAAA==.Maxrogue:BAAALgAECgMJBQABLgAECgUJFgAZAB0NAA==.Mazikeen:BAAALgAECgUJBgAAAA==.',
Mc='Mcscoots:BAAALgADCgcJEgAAAA==.',
Me='Meatsupreme:BAABLgAECn8lAAISAAgJ4QzJTABfAQASAAgJ4QzJTABfAQAAAA==.Meepin:BAACLgAFFH8OAAIEAAQJdR7SCwBoAQAEAAQJdR7SCwBoAQAuAAQKfyIAAgQACAkiJQMFABwDAAQACAkiJQMFABwDAAAA.Meepmorp:BAAALgADCgIJAgAAAA==.Meifeng:BAAALgADCgEJAQAAAA==.Mephala:BAAALgADCgYJBgAAAA==.Mesophistole:BAAALgADCgUJBQABLgAECgQJCwAFAAAAAA==.Mesopyro:BAAALgAECgQJCwAAAA==.',
Mi='Minimim:BAAALgADCgMJAwAAAA==.Mià:BAAALgADCgEJAQAAAA==.',
Mo='Mod:BAAALgAECgcJEwAAAA==.Mograiné:BAAALgAECgQJBgAAAA==.Mojodaemon:BAAALgADCgMJAwAAAA==.Monkaw:BAAALgAECgEJAQAAAA==.Monkchalk:BAAALgAECgQJBAABLgAFFAQJDgAWAAMmAA==.Moondevil:BAAALgADCgYJBwAAAA==.Morta:BAEALgAECgUJCwAAAA==.Mortkavaliro:BAAALgAECgQJBAAAAA==.',
Ms='Mslockness:BAAALgADCgUJCgAAAA==.',
Mu='Mugzy:BAAALgAECgkJBwAAAA==.Multipass:BAAALgAECgYJEgAAAA==.Multitool:BAAALgADCgEJAQAAAA==.',
['Mö']='Mörph:BAAALgAECgIJAgAAAA==.',
Na='Nadris:BAAALgADCgcJBwAAAA==.Nanérs:BAAALgAECgcJEQABLgAFFAUJCgAQAP0NAA==.Narrodus:BAABLgAECn8ZAAIiAAcJsSK7AgBEAgAiAAcJsSK7AgBEAgAAAA==.Nasht:BAABLgAECn8VAAIBAAYJURayXgBVAQABAAYJURayXgBVAQAAAA==.Nashty:BAAALgADCgYJBgABLgAECgYJFQABAFEWAA==.Nashxi:BAAALgADCgkJEAABLgAECgYJFQABAFEWAA==.Nasu:BAAALgAECgcJAQAAAA==.Nattymoo:BAAALgAECgYJBwABLgAECggJCgAFAAAAAA==.',
Ne='Necrô:BAAALgADCgIJAgAAAA==.Nephi:BAAALgADCgUJBQAAAA==.',
Ni='Nightraven:BAAALgADCgkJCQAAAA==.Nightreaper:BAAALgADCgkJGwAAAA==.Nimbus:BAACLgAFFH8MAAIDAAQJWhEYEAAuAQADAAQJWhEYEAAuAQAuAAQKfzoAAgMACQkiI2sBADIDAAMACQkiI2sBADIDAAEuAAUUBwkTAAkAIhQA.Nimike:BAAALgAECgcJDQAAAA==.',
No='Normul:BAAALgAECgcJAwABLgAECgkJMQARAMUhAA==.Noshoba:BAAALgAECgEJAQAAAA==.',
Nr='Nrvous:BAAALgADCgkJCQAAAA==.',
Nu='Nugzuul:BAAALgAECgEJAQAAAA==.Numbers:BAAALgAECgYJDgAAAA==.',
Ny='Nyterage:BAAALgAECgIJAgAAAA==.Nytesage:BAACLgAFFH8WAAIjAAUJgSQgAACqAQAjAAUJgSQgAACqAQAuAAQKfygAAiMACAkMJj8AAH4DACMACAkMJj8AAH4DAAAA.',
['Nä']='Näners:BAAALgAFFAEJAQABLgAFFAUJCgAQAP0NAA==.',
Oo='Ookle:BAABLgAECn8hAAMTAAgJYQdTDQBCAQATAAgJYQdTDQBCAQAMAAcJrwi4egDoAAAAAA==.',
Or='Oresh:BAABLgAECn8dAAIXAAcJTREnHACHAQAXAAcJTREnHACHAQAAAA==.Oryz:BAAALgADCgkJCAAAAA==.',
Os='Osajak:BAAALgADCgIJAgAAAA==.',
Oz='Ozo:BAAALgAECgcJDQAAAA==.',
Pa='Painavolian:BAABLgAECn8zAAIBAAkJlh7YDQCvAgABAAkJlh7YDQCvAgAAAA==.Palifur:BAAALgAECgkJCQAAAA==.Pandamonium:BAAALgAECgcJEgAAAA==.Panes:BAAALgAECgYJCgAAAA==.Paopu:BAAALgADCgYJBgABLgAECgkJIAAfAPcfAA==.',
Pe='Peeches:BAAALgAECgYJCwAAAA==.Pelor:BAAALgAECgYJCQAAAA==.',
Pi='Pisspadpanda:BAABLgAECn8oAAIfAAkJaiLsBQDlAgAfAAkJaiLsBQDlAgAAAA==.',
Po='Poggies:BAACLgAFFH8XAAIjAAYJ9SUKAAAyAgAjAAYJ9SUKAAAyAgAuAAQKfyEAAyMACAk0JjkAAIIDACMACAk0JjkAAIIDACEAAQkOIP4WAGIAAAAA.Ponmonk:BAAALgAECgEJAQABLgAECgYJFQAYALcfAA==.Pontacos:BAABLgAECn8VAAIYAAYJtx+7IADTAQAYAAYJtx+7IADTAQAAAA==.Porkinator:BAAALgADCgYJCAAAAA==.Powdur:BAAALgADCgEJAQABLgAFFAMJCgANAMIZAA==.Pozh:BAABLgAECn8UAAIfAAYJlA39kAA3AQAfAAYJlA39kAA3AQAAAA==.',
Pr='Praynes:BAABLgAECn8xAAIdAAkJ6hjIEgBKAgAdAAkJ6hjIEgBKAgAAAA==.Precedence:BAAALgADCgEJAQABLgAECgEJAQAFAAAAAA==.Prestocreamÿ:BAAALgADCgEJAQAAAA==.',
Pu='Pummel:BAAALgAECgUJBQAAAA==.Pupperputh:BAAALgADCgkJEgABLgAECgkJIgAHAKMdAA==.Puppet:BAAALgAECgEJAgAAAA==.',
['Pä']='Päroxysm:BAAALgADCgMJAwABLgAECgYJBgAFAAAAAA==.',
Ra='Randyrando:BAAALgADCgIJBAAAAA==.Ranoe:BAABLgAECn8UAAIHAAcJmBPvVAClAQAHAAcJmBPvVAClAQAAAA==.Rastrin:BAAALgADCgEJAQAAAA==.Ravyniel:BAAALgADCgEJAQAAAA==.Razji:BAABLgAECn80AAQNAAkJFSNMAQAKAwANAAkJWSFMAQAKAwAOAAcJsSEFGABtAgAGAAIJiSbNgQDjAAAAAA==.',
Re='Redrrum:BAAALgAECgcJCgAAAA==.Rekd:BAAALgADCgEJAQAAAA==.Reladiia:BAAALgADCgcJBwAAAA==.Renfro:BAAALgADCgcJBwAAAA==.Restokhan:BAAALgADCgEJAQAAAA==.Revoked:BAAALgADCgEJAQABLgAECgYJDwAFAAAAAA==.Reznick:BAABLgAECn8ZAAIXAAgJ6g4TGQCeAQAXAAgJ6g4TGQCeAQAAAA==.',
Ro='Rokd:BAAALgAECgcJBwAAAA==.Rokham:BAAALgADCgEJAQAAAA==.Rosalee:BAAALgADCgEJAQAAAA==.Rovërgalarga:BAAALgADCgMJAwAAAA==.',
Ru='Rudeboy:BAAALgAECgEJAQAAAA==.Ruibaron:BAAALgAECgQJBAAAAA==.',
Ry='Ryhunter:BAAALgADCggJDgAAAA==.',
['Rà']='Ràidèn:BAABLgAECn8dAAIRAAkJrRq6FgBGAgARAAkJrRq6FgBGAgAAAA==.',
['Rá']='Ráyne:BAAALgAECgIJAgAAAA==.',
Sa='Sadeel:BAABLgAECn8sAAMkAAkJWRoPAwDdAQAfAAkJdBKeRQD6AQAkAAcJLR0PAwDdAQAAAA==.Sadewolf:BAABLgAECn8lAAIHAAgJ/hxUDgBWAgAHAAgJ/hxUDgBWAgAAAA==.Sadpanduh:BAAALgADCgkJFQAAAA==.Saltednuts:BAAALgAECgEJAQAAAA==.Samentoni:BAABLgAECn8lAAIEAAgJHBkgDABSAgAEAAgJHBkgDABSAgAAAA==.Samgal:BAAALgAECgYJEwAAAA==.Sardothien:BAAALgAECgEJAgAAAA==.Satyra:BAAALgAECgYJCwABLgAECggJHwAdALEiAA==.Saurphang:BAACLgAFFH8PAAMRAAUJ9Q8YGABFAQARAAQJ9Q8YGABFAQAIAAEJAABuMwAAAAAuAAQKfyoAAhEACAn/Ig4VAP0CABEACAn/Ig4VAP0CAAAA.Saye:BAAALgADCgIJAgAAAA==.',
Sc='Scarletpanda:BAAALgADCgQJBgAAAA==.Scourgereap:BAAALgAECgMJAwAAAA==.',
Se='Selinna:BAAALgAECggJDwAAAA==.Senpaichill:BAAALgAECgYJDQAAAA==.Severis:BAAALgADCgIJAgAAAA==.',
Sh='Shadiepope:BAAALgAECgEJAQAAAA==.Shadora:BAABLgAECn8gAAIYAAkJLBOYCgAbAgAYAAkJLBOYCgAbAgAAAA==.Shadowwizard:BAAALgAECgMJAwAAAA==.Shadybrat:BAAALgAECgYJDQABLgAECggJGgAGAHwWAA==.Shaggylol:BAAALgADCgcJDQAAAA==.Shamlazy:BAAALgADCgkJHQAAAA==.Shidan:BAAALgAECggJDAABLgAECgkJHQARAK0aAA==.Shiroku:BAAALgAECgkJBgAAAA==.Shockchalk:BAACLgAFFH8OAAIWAAQJAyaEAADAAQAWAAQJAyaEAADAAQAuAAQKfycAAxYACAluJuUCAA8DABYACAluJuUCAA8DAAMAAglPEfdJAH0AAAAA.Shocknorris:BAAALgAECgQJBwABLgAECgYJDwAFAAAAAA==.Shrooclaw:BAABLgAECn8VAAIMAAgJGBLCQQCaAQAMAAgJGBLCQQCaAQAAAA==.',
Si='Sibbiah:BAAALgAECgMJAgAAAA==.Silanre:BAABLgAECn8XAAIBAAYJAg02dQAnAQABAAYJAg02dQAnAQAAAA==.',
Sk='Skaðï:BAABLgAECn8zAAQOAAkJ8CIlAQDQAgAOAAgJ0CMlAQDQAgANAAQJ7hnKFgBYAQAGAAMJThhQhQCJAAAAAA==.',
Sm='Smolshrapnel:BAAALgAECgcJEAAAAA==.',
Sn='Sneakchalk:BAAALgADCgcJCwABLgAFFAQJDgAWAAMmAA==.',
So='Solaraze:BAABLgAECn8bAAMSAAkJexx3PAAyAgASAAgJBR13PAAyAgAEAAEJsQxIXAA/AAAAAA==.Solinarie:BAAALgADCgIJAgAAAA==.Sorefang:BAAALgADCgEJAQAAAA==.Sorrowfang:BAAALgAECgEJAQAAAA==.Sovnightwar:BAAALgAECgQJBAABLgAFFAEJAQAFAAAAAA==.Soza:BAAALgADCgEJAQAAAA==.',
Sp='Spacespecial:BAAALgAECgYJCwAAAA==.Sparklebunny:BAAALgADCgEJAQAAAA==.Spicycurryy:BAABLgAECn8sAAQGAAkJMh98FwATAgAGAAgJeSB8FwATAgANAAcJnRH1DwCrAQAOAAIJJAzBeABeAAABLgAECgkJLAAGADIfAA==.Spicyycurryy:BAAALgADCgQJBAABLgAECgkJLAAGADIfAA==.Spiker:BAAALgAECgEJAQAAAA==.Splittail:BAAALgAECgQJBAAAAA==.',
St='Strahm:BAABLgAECn8WAAIZAAUJHQ0NIQCVAAAZAAUJHQ0NIQCVAAAAAA==.Strehm:BAAALgAECgEJAQABLgAECgUJFgAZAB0NAA==.Strohmy:BAAALgADCgEJAQABLgAECgUJFgAZAB0NAA==.Stryhm:BAAALgAECgQJBAABLgAECgUJFgAZAB0NAA==.',
Su='Sunju:BAAALgADCgMJAwAAAA==.',
Sy='Syssare:BAABLgAECn8XAAIVAAcJZSKABwAiAgAVAAcJZSKABwAiAgAAAA==.',
Ta='Tabbie:BAAALgADCgYJCQAAAA==.Talasam:BAAALgAECgUJBQAAAA==.Talien:BAAALgADCgEJAQAAAA==.Tandsonnara:BAAALgAECgkJDAAAAA==.Tastetickle:BAABLgAECn8yAAIBAAkJPh9yCQDdAgABAAkJPh9yCQDdAgAAAA==.Tazdrin:BAABLgAECn8yAAIlAAkJJBe7AQBIAgAlAAkJJBe7AQBIAgAAAA==.',
Te='Telidrus:BAACLgAFFH8TAAIBAAUJZxuoIQBlAQABAAUJZxuoIQBlAQAuAAQKfycABAEACAkqIGUxAK0CAAEABwkmI2UxAK0CACEABAmjHbwDAGsBACMAAglVE7cJAEcAAAAA.Temok:BAAALgADCgEJAQAAAA==.Teyrlis:BAAALgAECgUJBgAAAA==.',
Th='Thavryn:BAAALgADCgYJBgAAAA==.Thaz:BAAALgAECgQJBwAAAA==.Thias:BAABLgAECn8XAAIBAAgJOxPySwCFAQABAAgJOxPySwCFAQAAAA==.Thukmonk:BAAALgAECgMJAwAAAA==.Thukwarlock:BAABLgAECn8dAAIfAAcJ7xggSQDuAQAfAAcJ7xggSQDuAQAAAA==.Thunderbug:BAAALgADCgEJAQAAAA==.',
To='Todd:BAAALgAECgEJAQAAAA==.Tokain:BAAALgADCgkJEQAAAA==.Topaze:BAAALgAECgUJCAAAAA==.Torironheart:BAAALgADCgcJBwAAAA==.',
Tr='Trance:BAAALgAECgEJAQABLgAECgEJAQAFAAAAAA==.Treehuggera:BAAALgAECgYJCgAAAA==.Tribunal:BAAALgAECgEJAQAAAA==.Trilila:BAAALgADCgYJBgAAAA==.Tripx:BAAALgAECgYJDwABLgAECggJJAAHAGUiAA==.Tronko:BAABLgAECn8cAAICAAgJBBsJEwAfAgACAAgJBBsJEwAfAgAAAA==.Trumpinator:BAAALgADCgUJBgAAAA==.',
Ts='Tsireya:BAAALgADCgcJCQABLgAECgQJDgAFAAAAAA==.',
Tu='Turntsnaco:BAABLgAECn8nAAMaAAgJdxycCQAHAgAaAAgJdxycCQAHAgAmAAEJyhAVGQA9AAAAAA==.Tusk:BAAALgAECgcJEQAAAA==.',
Tw='Twigger:BAAALgADCgEJAgAAAA==.Twiztedsoul:BAAALgADCgcJBwAAAA==.Twophorb:BAAALgADCgMJAwAAAA==.',
Ua='Uake:BAAALgADCgYJBgAAAA==.',
Ud='Udgar:BAAALgAECgkJEQAAAA==.',
Un='Unafhaen:BAAALgADCgEJAQAAAA==.Unaverse:BAAALgAECgEJAQAAAA==.',
Us='Usmc:BAAALgADCgYJBgAAAA==.Usmccpl:BAAALgAECgQJDAAAAA==.Usmcsemperfi:BAAALgADCgYJCQAAAA==.',
Va='Valengarde:BAABLgAECn8ZAAISAAgJpBRANQCoAQASAAgJpBRANQCoAQAAAA==.Vanette:BAAALgAECgEJAQAAAA==.Vannix:BAABLgAECn8xAAIYAAkJRSMMAQA+AwAYAAkJRSMMAQA+AwAAAA==.Vanz:BAAALgADCgIJAgAAAA==.Varnos:BAAALgAECgEJAgAAAA==.',
Ve='Velranis:BAAALgADCgMJAwABLgAECggJEQAFAAAAAA==.Velthas:BAAALgADCggJIQAAAA==.',
Vi='Virmethir:BAAALgAECgUJEwAAAA==.Viruz:BAAALgADCgcJCgAAAA==.',
Vo='Volley:BAAALgADCgEJAQAAAA==.Voltaren:BAAALgAECgYJBgABLgAECgkJGwASAHscAA==.',
Vy='Vylaran:BAAALgADCgYJBgAAAA==.Vyndrolan:BAAALgAECgMJCAAAAA==.Vyroth:BAAALgADCgUJBQAAAA==.',
Wa='Walksonwater:BAAALgADCgEJAQABLgAECgcJGQAEAHweAA==.Waq:BAAALgAECgYJCQAAAA==.',
We='Wellamor:BAAALgADCgIJAgAAAA==.',
Wi='Wiwi:BAABLgAECn8xAAMRAAkJxSG5BAAVAwARAAkJxSG5BAAVAwAnAAIJJRsuDgCeAAAAAA==.',
Xa='Xares:BAABLgAECn8iAAIBAAkJjBcHHgA2AgABAAkJjBcHHgA2AgAAAA==.',
Xe='Xerath:BAAALgADCgcJBwAAAA==.',
Xh='Xhades:BAAALgAECgQJBwAAAA==.',
Ya='Yalda:BAAALgAECgUJBwAAAA==.',
Yf='Yfra:BAAALgAECgcJDgAAAA==.',
Yo='Yochangsvegn:BAAALgAECggJEAAAAA==.Yoseph:BAABLgAECn8VAAITAAcJsQ+gDQA9AQATAAcJsQ+gDQA9AQAAAA==.',
Yu='Yungblood:BAAALgAECgMJAwAAAA==.Yurimancer:BAABLgAECn8hAAIYAAcJwBNiFgCMAQAYAAcJwBNiFgCMAQAAAA==.',
Za='Zaen:BAAALgADCgMJAwAAAA==.Zake:BAAALgAECgMJBAAAAA==.Zalileina:BAAALgADCgMJAwAAAA==.Zallith:BAAALgADCgMJAwABLgAECgYJDgAFAAAAAA==.Zappythile:BAABLgAECn8kAAICAAgJNBoiGQDpAQACAAgJNBoiGQDpAQAAAA==.Zarkamental:BAAALgADCgYJCwABLgAECggJGQAHAJYNAA==.Zarthos:BAAALgAECgEJAQABLgAECgEJAgAFAAAAAA==.',
Ze='Zect:BAAALgAECgUJEgAAAA==.Zelinor:BAAALgADCgcJBwAAAA==.',
Zi='Ziêg:BAAALgADCgcJBwAAAA==.',
Zo='Zoz:BAAALgAECgQJCwAAAA==.',
Zu='Zulfrik:BAABLgAECn8jAAIBAAkJuxYFIQAmAgABAAkJuxYFIQAmAgAAAA==.Zullard:BAAALgAECgEJAQAAAA==.',
Zy='Zyzy:BAAALgAECgMJBAABLgAECggJFgAHAFYeAA==.',
['Zõ']='Zõke:BAAALgADCgEJAQAAAA==.',
['Òd']='Òdb:BAAALgADCgEJAQAAAA==.',
['ße']='ßeef:BAAALgADCgcJBwAAAA==.',
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
