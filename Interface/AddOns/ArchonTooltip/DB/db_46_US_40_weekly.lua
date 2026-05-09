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

local lookup = {'Unknown-Unknown','Mage-Frost','Druid-Guardian','Monk-Mistweaver','Paladin-Retribution','Paladin-Holy','Druid-Restoration','Warlock-Affliction','Warlock-Demonology','Hunter-BeastMastery','Evoker-Augmentation','Evoker-Devastation','Shaman-Enhancement','Shaman-Restoration','Monk-Windwalker','Monk-Brewmaster','Warrior-Protection','Warrior-Fury','Priest-Shadow','Priest-Holy','DeathKnight-Blood','DeathKnight-Frost','DemonHunter-Devourer','DemonHunter-Havoc','Hunter-Survival','Hunter-Marksmanship','DemonHunter-Vengeance','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','DeathKnight-Unholy','Warlock-Destruction','Mage-Arcane','Druid-Balance','Paladin-Protection','Rogue-Outlaw','Shaman-Elemental','Warrior-Arms','Druid-Feral','Evoker-Preservation',}
local provider = {region='US',realm='Bloodhoof',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abarlton:BAAALgAECgYJDAABLgAECgUJBQABAAAAAA==.',
Ad='Adabeam:BAAALgADCgcJCwAAAA==.Adagio:BAABLgAECn8sAAICAAkJvhhaGwBFAgACAAkJvhhaGwBFAgAAAA==.Adetalo:BAABLgAECn8hAAIDAAkJ7xc8BQAOAgADAAkJ7xc8BQAOAgAAAA==.Adiara:BAAALgAECgMJAwAAAA==.Aditu:BAAALgAECgUJDgAAAA==.',
Ae='Aelis:BAAALgADCgcJCAAAAA==.Aemulo:BAAALgAECgUJBwAAAA==.Aerith:BAAALgADCgcJBwAAAA==.',
Ag='Agasonex:BAAALgADCgMJAwAAAA==.',
Ai='Airent:BAAALgAECgQJCgAAAA==.Aiyana:BAAALgAECgYJDgAAAA==.',
Ak='Akiirii:BAAALgADCgUJBQAAAA==.',
Al='Alaestel:BAAALgAECgQJBwAAAA==.Aldo:BAAALgADCgYJCwAAAA==.Alkaraho:BAAALgAECgMJAwAAAA==.Alleyways:BAABLgAECn8oAAIEAAkJkCP+AACTAwAEAAkJkCP+AACTAwAAAA==.Alzey:BAABLgAECn8dAAIFAAcJmQ7iTwBWAQAFAAcJmQ7iTwBWAQAAAA==.',
Am='Ambeon:BAAALgADCgUJBQAAAA==.Ammathindis:BAAALgADCgcJCQAAAA==.Amplers:BAAALgADCgUJBwAAAA==.',
An='Angelbane:BAAALgADCgQJBAAAAA==.Angina:BAAALgAECgEJAQAAAA==.Annarcis:BAAALgAECgQJCQAAAA==.Anotherdk:BAAALgAECgYJBgABLgAECgcJGwAGAE0jAA==.Anthiell:BAAALgADCgEJAQAAAA==.Antiman:BAABLgAECn8YAAIFAAYJcQnYdAACAQAFAAYJcQnYdAACAQAAAA==.',
Ap='Aplcyder:BAABLgAECn8vAAIHAAkJEwwxLwBlAQAHAAkJEwwxLwBlAQAAAA==.',
Ar='Arachnid:BAABLgAECn8nAAICAAcJDyRBMQCtAgACAAcJDyRBMQCtAgAAAA==.Aragorn:BAAALgADCgUJCAAAAA==.Aratyn:BAAALgAECgYJDwAAAA==.',
At='Ati:BAAALgADCgIJAgAAAA==.',
Au='Audxo:BAAALgADCgMJAwAAAA==.',
Ay='Ayayron:BAAALgADCgQJBAAAAA==.',
Ba='Backhawk:BAAALgADCgcJEAAAAA==.Backsurgery:BAAALgAECgYJDAAAAA==.Baerrn:BAAALgAECgUJDgAAAA==.Bamboo:BAAALgAECgYJCQAAAA==.Baricia:BAABLgAECn8UAAICAAgJYQqfrACCAQACAAgJYQqfrACCAQAAAA==.Barix:BAAALgAECgEJAwAAAA==.Barnd:BAAALgADCggJDwAAAA==.Barrin:BAABLgAECn8iAAMIAAcJUBc4BwDiAQAIAAYJJRs4BwDiAQAJAAUJPgi4agD3AAAAAA==.Bastim:BAAALgAECgIJAgAAAA==.Baussassbich:BAAALgAECgQJBAABLgAECggJIAAJAI8iAA==.Bawnchu:BAAALgAECgIJAgAAAA==.',
Be='Beastmaster:BAABLgAECn8oAAIKAAgJTCQFBQDiAgAKAAgJTCQFBQDiAgAAAA==.Beefcakell:BAAALgADCgcJDQAAAA==.Beiki:BAAALgAECgMJBgAAAA==.Belthar:BAAALgAECgQJCQAAAA==.Bently:BAABLgAECn8cAAMLAAcJoCFsDAAFAgALAAcJmB9sDAAFAgAMAAUJGCMnEwCvAQAAAA==.Berexis:BAAALgAECggJDwAAAA==.',
Bi='Bissafiyah:BAACLgAFFH8WAAINAAYJUyQzAAADAgANAAYJUyQzAAADAgAuAAQKf0AAAg0ACQlsJSIAAOkDAA0ACQlsJSIAAOkDAAAA.Biznasty:BAAALgAECgEJAwAAAA==.',
Bl='Bloodgon:BAAALgAFFAIJAwAAAA==.Bluetuesday:BAAALgAECgMJAwAAAA==.',
Bo='Bohica:BAABLgAECn8vAAIOAAkJjBDWHwC0AQAOAAkJjBDWHwC0AQAAAA==.Bonechop:BAAALgADCgYJBgAAAA==.Bootymeat:BAAALgADCgEJAQAAAA==.Bowtox:BAAALgAECgEJAQAAAA==.Boyakasha:BAAALgAECgQJCwAAAA==.',
Br='Brewfu:BAAALgADCgIJAgAAAA==.Brewpub:BAAALgADCgQJBAAAAA==.Brewsome:BAABLgAECn8vAAMPAAkJESBIAgD3AgAPAAkJESBIAgD3AgAQAAgJDhi8HAAdAgAAAA==.Bruceprime:BAAALgAECgkJAQAAAA==.Bryybryy:BAAALgAECgQJBAABLgAECggJHQAQAOAaAA==.Bryycelest:BAABLgAECn8dAAIQAAgJ4BqhDAD5AQAQAAgJ4BqhDAD5AQAAAA==.Brådòn:BAAALgAECgYJDQAAAA==.',
Bu='Bucket:BAABLgAECn8jAAIRAAgJxRF1DwBsAQARAAgJxRF1DwBsAQAAAA==.Bunkiee:BAAALgADCgkJHQAAAA==.Bunnybane:BAAALgAECgYJEAAAAA==.Burny:BAABLgAECn8aAAICAAcJVCVHJgDZAgACAAcJVCVHJgDZAgAAAA==.Buttadogg:BAAALgAECgcJDQAAAA==.',
['Bè']='Bèth:BAAALgADCgYJCAAAAA==.',
['Bë']='Bëckey:BAAALgADCgIJAgAAAA==.',
Ca='Calyx:BAAALgAECgQJCwAAAA==.Canadani:BAAALgAECgcJDQAAAA==.Candorite:BAAALgAECgYJDwAAAA==.Caphriel:BAABLgAECn8dAAISAAkJPh0GBQCpAgASAAkJPh0GBQCpAgAAAA==.Capita:BAABLgAECn8aAAICAAcJ0QrvYgBMAQACAAcJ0QrvYgBMAQAAAA==.Carsinegan:BAAALgADCgUJCwAAAA==.Cassica:BAABLgAECn8dAAMTAAcJZxncGgBlAQATAAcJZxncGgBlAQAUAAIJ2gmGQwBXAAAAAA==.Catchdezhanz:BAAALgADCgcJBwABLgAECgYJFwAGAPQTAA==.Catskin:BAAALgAECgYJEwAAAA==.',
Ce='Celivalasha:BAAALgADCgUJBQAAAA==.Cell:BAABLgAECn8jAAIQAAgJTSQrBQA3AwAQAAgJTSQrBQA3AwAAAA==.Cet:BAAALgADCgUJBQAAAA==.',
Ch='Chadvader:BAAALgADCgIJAgAAAA==.Chainlink:BAAALgADCgYJBgAAAA==.Chanpagne:BAAALgADCgUJBQAAAA==.Charkle:BAAALgAECgQJBgAAAA==.Chayea:BAAALgADCgEJAQAAAA==.Chillylilly:BAABLgAECn8jAAMVAAgJwCSTAgDEAgAVAAgJwCSTAgDEAgAWAAQJgRkpCAAiAQAAAA==.Chlorophyll:BAAALgAECgQJBAAAAA==.Chocola:BAAALgADCgEJAQAAAA==.Chummie:BAABLgAECn8hAAMJAAkJFh4fCQC1AgAJAAkJFh4fCQC1AgAIAAYJnxlDCADHAQAAAA==.',
Ci='Cielcin:BAAALgAFFAEJAQAAAA==.Ciremiih:BAAALgAECgEJAQAAAA==.Citymage:BAABLgAECn8mAAICAAkJmRd2HgAzAgACAAkJmRd2HgAzAgAAAA==.Cixelsyd:BAAALgADCgYJCwAAAA==.',
Cl='Clamchowda:BAABLgAECn8mAAMXAAkJwRrgDgBQAgAXAAkJTBjgDgBQAgAYAAUJUh5rIwCiAQAAAA==.',
Co='Codê:BAABLgAECn8YAAIJAAYJMxfqRwBRAQAJAAYJMxfqRwBRAQAAAA==.Coffeecup:BAAALgADCgIJAgAAAA==.Corride:BAABLgAECn8mAAIZAAcJxyD+CgD0AQAZAAcJxyD+CgD0AQAAAA==.Corspar:BAAALgAECgEJAQAAAA==.',
Cr='Crazyeyes:BAAALgADCgMJAwAAAA==.Crimsondeath:BAAALgAECgQJCwAAAA==.Crutch:BAABLgAECn8bAAMOAAcJQyCQDwBEAgAOAAYJlyGQDwBEAgANAAUJJBSjDAA+AQAAAA==.Crystanikus:BAAALgAECgQJBQAAAA==.',
Cu='Cuckenjoyer:BAAALgAECgYJCgAAAA==.',
Cy='Cyclonian:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.Cyprus:BAAALgAECgEJAQAAAA==.',
Da='Daddytrump:BAAALgAECgYJDwAAAA==.Daelric:BAAALgADCgIJAwAAAA==.Daender:BAABLgAECn8jAAMKAAgJtiFiEgA+AgAKAAgJtiFiEgA+AgAaAAEJghiYIwBDAAAAAA==.Daenor:BAAALgAECgEJAwAAAA==.Dairydemon:BAABLgAECn8pAAIbAAgJJA0XCwAcAQAbAAgJJA0XCwAcAQAAAA==.Damageus:BAABLgAECn8dAAICAAgJ5CJVEgCGAgACAAgJ5CJVEgCGAgAAAA==.Daniryl:BAEBLgAECn8bAAIHAAgJfhVFGQD6AQAHAAgJfhVFGQD6AQAAAA==.Dar:BAAALgAECgQJBwAAAA==.Darcness:BAABLgAECn8XAAMcAAUJURZwHgAJAQAcAAUJURZwHgAJAQAdAAMJJQicEQCQAAAAAA==.Darcside:BAAALgAECgQJCAAAAA==.Darkclouds:BAAALgADCgIJAgAAAA==.Darksoul:BAAALgAECgcJEAABLgAECgcJFwAeAAIaAA==.Darkxwraith:BAAALgAECgYJDAAAAA==.Dashtoolite:BAABLgAECn8VAAIXAAcJcAlKVgD5AAAXAAcJcAlKVgD5AAAAAA==.Datsumbeech:BAAALgAECgcJEgAAAA==.',
De='Deajer:BAAALgADCgYJBwAAAA==.Deathsabeach:BAAALgAECgEJAQAAAA==.Deathvìxen:BAAALgAECgQJCwAAAA==.Debit:BAAALgAECgcJEwAAAA==.Demonhunter:BAACLgAFFH8KAAIXAAQJMyHMEgBkAQAXAAQJMyHMEgBkAQAuAAQKfx0AAhcACAk/JKkKAC4DABcACAk/JKkKAC4DAAAA.Demonwoogie:BAAALgADCgYJBgABLgAECgQJCwABAAAAAA==.Dendrophilia:BAAALgAECgEJAQAAAA==.Densamin:BAABLgAECn8YAAIFAAYJWRigRwBuAQAFAAYJWRigRwBuAQAAAA==.Deviyn:BAAALgADCgIJAgAAAA==.Devra:BAAALgADCggJCAAAAA==.Deàdly:BAAALgAECgQJBgAAAA==.',
Di='Dietchrist:BAAALgAECggJEwAAAA==.Dilligaf:BAAALgADCggJCAAAAA==.',
Dk='Dkanabiss:BAAALgAECgMJBAAAAA==.Dkinabox:BAAALgADCgEJAgAAAA==.',
Do='Doist:BAAALgAECgEJAQABLgAECgYJFAAPAF4OAA==.Donngaz:BAAALgAECgMJBgAAAA==.',
Dr='Drewnei:BAAALgADCgkJCQAAAA==.Drewserk:BAABLgAECn8dAAISAAgJjhYAFQDCAQASAAgJjhYAFQDCAQAAAA==.Drkxmaniac:BAAALgAECgUJCgABLgAECgUJBQABAAAAAA==.Drminnowphd:BAAALgAFFAEJAQAAAA==.Drpiscisphd:BAABLgAECn8sAAMfAAkJtiDqDgAkAwAfAAkJtiDqDgAkAwAVAAcJwwV+KQDzAAABLgAFFAEJAQABAAAAAA==.Drsaltyballz:BAABLgAECn8lAAIdAAkJZBtzAQCKAgAdAAkJZBtzAQCKAgAAAA==.Drugpala:BAAALgAECgIJAgAAAA==.Druji:BAAALgADCgIJAgAAAA==.Drumuss:BAAALgADCgEJAQAAAA==.',
Du='Ducat:BAAALgAECgUJCQAAAA==.Dudesk:BAAALgAECgQJBAAAAA==.Duffuna:BAAALgADCgEJAQABLgAECgkJMQAZAMElAA==.Duffunha:BAABLgAECn8xAAIZAAkJwSVsAABgAwAZAAkJwSVsAABgAwAAAA==.',
Dy='Dye:BAABLgAECn8hAAIGAAgJpxteCwBdAgAGAAgJpxteCwBdAgAAAA==.Dyre:BAABLgAECn8YAAIbAAYJag0UDwDPAAAbAAYJag0UDwDPAAAAAA==.Dyslexic:BAABLgAECn8YAAIgAAYJZRlVBwBwAQAgAAYJZRlVBwBwAQAAAA==.Dyspepsia:BAACLgAFFH8IAAIFAAUJKwQNEQAdAQAFAAUJKwQNEQAdAQAuAAQKfxYAAgUACQnjFAg2AEoCAAUACQnjFAg2AEoCAAAA.',
['Dô']='Dôngus:BAAALgADCgMJAwABLgAECgIJAgABAAAAAA==.',
['Dõ']='Dõngus:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.',
['Dö']='Döngus:BAAALgADCgEJAQABLgAECgIJAgABAAAAAA==.',
Ed='Edie:BAAALgAECgEJAgAAAA==.',
Ei='Eirenn:BAAALgAECgkJBgAAAA==.',
El='Elenaura:BAAALgAECgMJAwAAAA==.Eleren:BAABLgAECn8XAAIXAAYJnBLdTgAMAQAXAAYJnBLdTgAMAQAAAA==.Elimee:BAABLgAECn8nAAICAAkJXyBJDgBUAwACAAkJXyBJDgBUAwAAAA==.Ellasia:BAAALgAECgQJBwAAAA==.Elric:BAABLgAECn8sAAIFAAkJ4xTXHgAPAgAFAAkJ4xTXHgAPAgAAAA==.Elsie:BAAALgAECgUJCgABLgAECgYJDQABAAAAAA==.Elunea:BAAALgADCgcJDQAAAA==.Elunemittens:BAAALgADCgYJBgAAAA==.',
Em='Emart:BAABLgAECn8VAAIZAAYJChBVGQA9AQAZAAYJChBVGQA9AQAAAA==.Emozella:BAAALgAECgEJAQAAAA==.',
En='Enatresh:BAAALgAECgQJBwAAAA==.',
Ep='Epsilon:BAAALgAECgkJCQAAAA==.',
Er='Erayna:BAABLgAECn8lAAIHAAkJxRCQHADfAQAHAAkJxRCQHADfAQAAAA==.Ereillea:BAAALgAECgYJDQAAAA==.',
Es='Essence:BAABLgAECn8WAAMCAAgJmxTnagAAAgACAAgJDBHnagAAAgAhAAQJ1xobDAARAQAAAA==.',
Eu='Euko:BAABLgAECn8sAAMiAAkJex50AwDRAgAiAAkJex50AwDRAgAHAAgJdRXyQwADAQAAAA==.',
Ev='Evedk:BAAALgAECgkJBQAAAA==.Evepriest:BAAALgADCgMJAQAAAA==.',
Fa='Failrogue:BAAALgADCgUJCwAAAA==.Falconclaw:BAAALgADCgkJGAAAAA==.Falkensnoman:BAABLgAECn8YAAIVAAYJmRJ6FwASAQAVAAYJmRJ6FwASAQAAAA==.Fayedra:BAAALgAECgYJDwAAAA==.',
Fc='Fcawfe:BAAALgAECgMJAwABLgAECgYJCgABAAAAAA==.',
Fe='Febee:BAAALgADCgcJAQAAAA==.Feenii:BAABLgAECn8pAAINAAkJWBpjAwBRAgANAAkJWBpjAwBRAgAAAA==.Felburst:BAAALgAECgMJAwAAAA==.Felfireqt:BAAALgAECgEJAgAAAA==.',
Fi='Figgyandrii:BAAALgADCgcJBwAAAA==.Fionar:BAAALgADCgIJAgAAAA==.Fizzlelich:BAAALgADCgcJCgAAAA==.',
Fl='Flamesters:BAAALgAECgIJAwAAAA==.Fluffpuff:BAAALgADCgMJAwAAAA==.',
Fo='Foxdeer:BAAALgAECgYJCwAAAA==.',
Fr='Frenchtoast:BAAALgAECgMJAwAAAA==.',
Fu='Furyrage:BAAALgADCgEJAQAAAA==.',
Ga='Gambachii:BAAALgAECgcJDQAAAA==.Gankss:BAABLgAECn8bAAIGAAcJTSMeBgC/AgAGAAcJTSMeBgC/AgAAAA==.Garakddon:BAAALgADCgkJDgABLgAECgYJEwABAAAAAA==.Garryy:BAAALgAECgMJBgAAAA==.',
Ge='Geegandolm:BAAALgADCgkJEwAAAA==.Genjaru:BAAALgAECgMJAwAAAA==.Genndalf:BAAALgADCgcJBwAAAA==.Geostorm:BAAALgAECgEJAQAAAA==.',
Gh='Gharmag:BAAALgAECgEJAQAAAA==.',
Gi='Giramar:BAAALgAECggJEwAAAA==.',
Go='Gobbyshamm:BAAALgAECgEJAQAAAA==.Gobsmackers:BAAALgAECgYJBwAAAA==.Gomklin:BAAALgADCgcJCAABLgAECgkJMwAFAHMkAA==.Goobtastic:BAAALgADCgQJBAAAAA==.Goteem:BAAALgAECggJEwAAAA==.Gothitelle:BAAALgAECgEJAQAAAA==.',
Gr='Griffhud:BAAALgAECgYJDgAAAA==.Grimrox:BAAALgAECgYJDwAAAA==.Grixx:BAAALgADCgUJBQAAAA==.Groupie:BAAALgADCgUJCgABLgAECgcJGAAaAMgPAA==.',
Gt='Gtatedk:BAAALgAECgEJAQAAAA==.',
Gu='Guntera:BAAALgAECgYJDgAAAA==.Guts:BAAALgADCgMJAwAAAA==.',
Gw='Gwendalyn:BAAALgAECgQJBQAAAA==.',
['Gä']='Gäz:BAAALgADCgEJAQAAAA==.',
Ha='Halexion:BAAALgADCgIJAgAAAA==.Haomaru:BAAALgAECgUJEAAAAA==.Hardcandy:BAABLgAECn8YAAIaAAcJyA91DQAUAQAaAAcJyA91DQAUAQAAAA==.Hardlyevoker:BAAALgADCgEJAQABLgAFFAIJBgAGAOYQAA==.Hawkìns:BAAALgAECgEJAQAAAA==.',
He='Heartsoul:BAAALgAECgYJCQAAAA==.Heavyarm:BAAALgADCgcJDwAAAA==.Hellork:BAAALgADCgQJBAAAAA==.Hermosura:BAAALgADCgUJCQAAAA==.Hex:BAAALgAECgYJBgAAAA==.',
Hi='Hiccups:BAAALgAECgMJBAABLgAECgUJBgABAAAAAA==.Himawarí:BAAALgAECgYJDwAAAA==.Hiyank:BAABLgAECn8bAAIQAAcJgSGzCwAGAgAQAAcJgSGzCwAGAgAAAA==.',
Ho='Hoffmin:BAABLgAECn8QAAMXAAcJKhYVeAA+AQAXAAYJKhYVeAA+AQAYAAIJphKwVgCMAAAAAA==.Holemeister:BAABLgAECn8uAAIFAAgJlCQlBwDdAgAFAAgJlCQlBwDdAgAAAA==.Holyfresh:BAAALgADCgEJAQAAAA==.Holymann:BAABLgAECn8fAAITAAcJ1wyhKwDvAAATAAcJ1wyhKwDvAAAAAA==.Holyschnikey:BAABLgAECn8XAAIGAAYJ9BMzJABnAQAGAAYJ9BMzJABnAQAAAA==.Holyz:BAABLgAECn8ZAAIGAAgJYB/jBgCsAgAGAAgJYB/jBgCsAgAAAA==.Horgable:BAAALgADCgIJAgAAAA==.Horrorpops:BAAALgADCgUJBQAAAA==.Hozaki:BAAALgAECgQJBAABLgAECgUJBQABAAAAAA==.',
Hu='Hudfin:BAAALgADCgUJBQAAAA==.Hundred:BAAALgADCgUJBQABLgAECgEJAQABAAAAAA==.',
['Hí']='Hílthaen:BAABLgAECn8hAAIUAAgJThCRFgCeAQAUAAgJThCRFgCeAQAAAA==.',
Ic='Icebones:BAAALgADCgcJDAABLgAECgQJCQABAAAAAA==.Icelight:BAAALgAECgQJCQAAAA==.Ichigokisu:BAAALgAECgQJBgAAAA==.',
Il='Illiduji:BAAALgADCgMJAwAAAA==.Illy:BAABLgAECn8aAAIXAAkJ4ha0EQAyAgAXAAkJ4ha0EQAyAgAAAA==.',
Im='Imposed:BAAALgAECgUJDgAAAA==.',
In='Instantdeath:BAAALgAECgUJBQAAAA==.Invali:BAAALgAECgMJAwAAAA==.',
Io='Iorla:BAAALgADCgEJAQAAAA==.',
Ir='Irônhide:BAAALgAECgEJAQAAAA==.',
Iv='Ivranda:BAAALgADCgkJEgABLgAECgYJDwABAAAAAA==.',
Iz='Iz:BAAALgADCgMJAwABLgADCgUJBQABAAAAAA==.',
Ja='Jaapp:BAAALgAECgMJBgAAAA==.Jahan:BAABLgAECn8mAAMeAAgJIiTYAQBMAwAeAAgJIiTYAQBMAwATAAMJyBJUMQDMAAAAAA==.Jamie:BAAALgAFFAIJBAAAAA==.Jaydine:BAAALgADCgYJBgABLgAECgkJJwACAF8gAA==.',
Je='Jeri:BAAALgADCgcJFAAAAA==.',
Jh='Jhie:BAAALgAECgUJCQAAAA==.',
Ju='Jud:BAAALgAECggJDAAAAA==.Juviâ:BAAALgAECgEJAQABLgAECgYJDQABAAAAAA==.Juxtaposed:BAAALgADCgUJBQAAAA==.',
Ka='Kaelora:BAAALgADCgcJBwAAAA==.Kaerei:BAABLgAECn8gAAIFAAgJ7RumIAAGAgAFAAgJ7RumIAAGAgAAAA==.Kaleb:BAABLgAECn8bAAIYAAgJtiEyAwCvAgAYAAgJtiEyAwCvAgAAAA==.Kalfalah:BAAALgAECgYJEQAAAA==.Kalferno:BAAALgAECgQJCQAAAA==.Kalirkaz:BAABLgAECn8mAAMHAAkJMxh9EwAuAgAHAAkJMxh9EwAuAgAiAAUJOQZJOgCfAAAAAA==.Kallipsa:BAAALgAECgIJAgAAAA==.Karasu:BAAALgAECgIJAgABLgAECggJIAAPAEsOAA==.Karst:BAAALgAECgQJBAABLgAECggJJgAeACIkAA==.Kathria:BAAALgAECgcJDAAAAA==.',
Ke='Kegendary:BAAALgAECgQJBAAAAA==.Keler:BAAALgADCgIJAwAAAA==.Keládry:BAAALgAECgUJDAAAAA==.Keskiyö:BAAALgADCgkJFQABLgAECggJIAAPAEsOAA==.',
Kh='Khallock:BAABLgAECn8aAAIIAAYJ9BZwDABxAQAIAAYJ9BZwDABxAQAAAA==.Khamael:BAAALgAECgEJAQAAAA==.',
Ki='Kiemen:BAABLgAECn8ZAAIfAAgJ9xV0TAAOAgAfAAgJ9xV0TAAOAgAAAA==.Killerpoison:BAAALgAECgkJBQAAAA==.Killko:BAAALgAECggJEgAAAA==.Kinki:BAAALgAECgMJAwABLgAECgcJGAAaAMgPAA==.Kirisen:BAAALgAECgUJCQAAAA==.Kitan:BAAALgAECgQJBQAAAA==.Kitani:BAAALgADCgkJCQABLgAECgcJHQAUABwdAA==.',
Ko='Konno:BAAALgAECgQJBAABLgAFFAYJFgANAFMkAA==.Kooterr:BAAALgADCgUJBQAAAA==.Korbix:BAAALgAECgYJCwAAAA==.',
Kr='Kragsloor:BAAALgADCgYJBgAAAA==.Kredorin:BAAALgAECgYJCgAAAA==.Krewella:BAAALgADCgcJBwAAAA==.Krihl:BAAALgAECgkJBgAAAA==.Krovmar:BAAALgADCgUJBQAAAA==.',
Ks='Kspanxx:BAAALgAECgMJAwAAAA==.',
Kt='Kthanx:BAAALgADCgYJBgAAAA==.',
Ku='Kungpowgazer:BAAALgAECgcJEAAAAA==.Kunls:BAAALgAECgcJEQAAAA==.Kuraki:BAAALgAECgYJDwAAAA==.Kurasa:BAABLgAECn8gAAMPAAgJSw4eGABlAQAPAAgJSw4eGABlAQAEAAQJowH1WgBjAAAAAA==.Kutraz:BAAALgAECgQJBQAAAA==.',
La='Ladrar:BAAALgAECgYJBgAAAA==.Laelina:BAAALgAECgEJAwAAAA==.Lanadiel:BAABLgAECn8sAAIjAAkJgSD3AADtAgAjAAkJgSD3AADtAgAAAA==.Lazz:BAAALgAECgYJDQAAAA==.',
Le='Legend:BAACLgAFFH8NAAIXAAQJASHyDgB9AQAXAAQJASHyDgB9AQAuAAQKfx8AAhcACQmeHzAJAD4DABcACQmeHzAJAD4DAAAA.Lekrotar:BAAALgAECgQJBAAAAA==.Letsyoudie:BAAALgADCgMJAwAAAA==.',
Li='Lian:BAAALgAECgUJDAAAAA==.Lichbane:BAABLgAECn8sAAIfAAkJ1RwbDACnAgAfAAkJ1RwbDACnAgAAAA==.Licun:BAAALgAECgYJDQAAAA==.Lifexdeath:BAAALgAECgYJEwAAAA==.Lightcell:BAAALgAECgQJBgAAAA==.Liliara:BAABLgAECn8rAAIKAAkJQBCSHgDkAQAKAAkJQBCSHgDkAQAAAA==.Lillyirl:BAAALgAECgQJCgAAAA==.Lillymae:BAAALgADCgYJCAAAAA==.Lillyslight:BAAALgADCgYJBgAAAA==.Lillysneak:BAAALgADCgUJCgAAAA==.Lillytae:BAAALgAECgMJAwAAAA==.Lillyzard:BAAALgADCgUJCAAAAA==.Lilmoo:BAAALgAECgYJDQAAAA==.Linkhunter:BAAALgAECgYJBgABLgAECgkJJAAeAO8TAA==.Linni:BAAALgAECgYJDQAAAA==.Lizardwizard:BAAALgAECgQJBAAAAA==.',
Lo='Lodise:BAABLgAECn8dAAMIAAcJIQ/BBgBFAQAIAAcJIQ/BBgBFAQAJAAEJAAgUHQEyAAAAAA==.Lonful:BAAALgADCgEJAQAAAA==.Lorzz:BAABLgAECn8qAAIUAAgJ2SJmAgAcAwAUAAgJ2SJmAgAcAwAAAA==.Lothe:BAAALgAECgYJDwAAAA==.',
Lu='Lucrio:BAABLgAECn8pAAIfAAkJwQ/6IwD0AQAfAAkJwQ/6IwD0AQAAAA==.Ludoe:BAAALgADCgkJMQAAAA==.Luna:BAAALgAECgUJDAAAAA==.Lunalai:BAABLgAECn8vAAIDAAkJkyBWAQDaAgADAAkJkyBWAQDaAgAAAA==.Lushy:BAAALgAECgYJBgABLgAECgYJEQABAAAAAA==.',
Ly='Lylineth:BAAALgADCgYJBgAAAA==.Lylinette:BAAALgAECgcJEgAAAA==.Lyssandra:BAAALgADCgUJBQAAAA==.',
['Lí']='Lízandor:BAACLgAFFH8LAAIFAAQJVgvoHgAyAQAFAAQJVgvoHgAyAQAuAAQKfx8AAgUACAkBGv8hAP4BAAUACAkBGv8hAP4BAAAA.',
['Lû']='Lûsøn:BAAALgAECgEJAQAAAA==.',
Ma='Madruskee:BAAALgAECgYJEgAAAA==.Magahpt:BAAALgAECgMJBAAAAA==.Magdea:BAAALgADCgYJBgAAAA==.Mageofdeath:BAAALgAECgIJAgABLgAECgUJBQABAAAAAA==.Magistroll:BAABLgAECn8WAAICAAcJMgUWhQAIAQACAAcJMgUWhQAIAQAAAA==.Malevohaynk:BAAALgAECgQJBAABLgAECgcJGwAQAIEhAA==.Manerva:BAAALgADCggJCAAAAA==.Maniacal:BAAALgADCgkJFgAAAA==.Maryshelley:BAAALgADCgMJAwAAAA==.Matoo:BAAALgADCgEJAQAAAA==.Maurin:BAAALgAECgYJBgAAAA==.Maximumhonk:BAABLgAECn8XAAIOAAYJQQpgQwD1AAAOAAYJQQpgQwD1AAAAAA==.',
Me='Mendelia:BAAALgAECgUJDgAAAA==.Mercus:BAABLgAECn8UAAMkAAgJZRghBgBqAQAkAAYJpBQhBgBqAQAcAAcJvBkSIgDqAAAAAA==.Merkstrasza:BAAALgAECgUJCwAAAA==.Mervenious:BAAALgAECgYJCAAAAA==.Meu:BAAALgAECggJBgAAAA==.',
Mi='Midasdh:BAACLgAFFH8JAAIXAAUJQAvxNwDTAAAXAAUJQAvxNwDTAAAuAAQKfxcAAxcACAnFFpE+APoBABcACAnrEpE+APoBABgABgmOF/8vAE8BAAEuAAUUBQkLAB8AyRgA.Midasdk:BAACLgAFFH8LAAIfAAUJyRg+KwBKAQAfAAUJyRg+KwBKAQAuAAQKfxkAAx8ABwnDHGZPAAQCAB8ABwm9GWZPAAQCABYAAwkiErIMAL0AAAAA.Midasmonk:BAAALgAECgEJAQABLgAFFAUJCwAfAMkYAA==.Miladepollo:BAAALgADCgMJAwAAAA==.Mindblank:BAAALgAECgQJBAAAAA==.Mindplague:BAABLgAECn8WAAITAAYJKR9SEwCrAQATAAYJKR9SEwCrAQAAAA==.Minipincin:BAAALgAECgEJAQAAAA==.Minisicwidit:BAAALgADCgMJAwAAAA==.Mistdeeznuts:BAAALgAECggJDwAAAA==.',
Mo='Mogwaï:BAAALgAECgUJBgAAAA==.Moonde:BAAALgAECgYJCwAAAA==.Moonscale:BAABLgAECn8iAAIMAAgJeh3CAQBeAgAMAAgJeh3CAQBeAgAAAA==.Moosayer:BAAALgAECgQJBgAAAA==.Mossed:BAAALgADCgMJAwAAAA==.',
Ms='Mskelsier:BAAALgAECgUJBQAAAA==.',
Mt='Mtaur:BAAALgADCggJDwAAAA==.',
Mu='Muclor:BAAALgADCgcJBwABLgAFFAEJAQABAAAAAA==.Mustang:BAAALgADCgcJCQAAAA==.',
My='Mythalis:BAAALgAECgQJBQAAAA==.',
['Mä']='Märändus:BAAALgADCgEJAQAAAA==.',
['Må']='Måzikeen:BAAALgADCgMJAwAAAA==.',
Na='Nardena:BAAALgADCggJCQAAAA==.Narse:BAAALgAECgYJBwAAAA==.Narz:BAABLgAECn8fAAIKAAgJ1hLlLACbAQAKAAgJ1hLlLACbAQAAAA==.Nastianna:BAAALgAECgQJBgAAAA==.Nazumi:BAABLgAECn8YAAIPAAYJRiFNDQDkAQAPAAYJRiFNDQDkAQAAAA==.',
Nd='Ndiz:BAAALgAECgcJEgAAAA==.',
Ne='Necronomikon:BAAALgADCgEJAQAAAA==.Neeva:BAAALgADCgYJCwAAAA==.Nelrya:BAEALgADCgcJDQABLgAECggJKwAFABMgAA==.Neruphuyt:BAABLgAECn8UAAIiAAYJFgpVLgDbAAAiAAYJFgpVLgDbAAAAAA==.',
Ni='Niath:BAAALgAECgEJAQAAAA==.Nightsniper:BAAALgAECgcJEgAAAA==.Ninfassins:BAAALgADCgIJAgAAAA==.',
No='Norintha:BAAALgADCgEJAQAAAA==.Norolen:BAAALgADCgIJAgAAAA==.',
Ny='Nyxiel:BAAALgAECgQJBAAAAA==.',
Oa='Oak:BAAALgAECgkJCwAAAA==.',
Oc='Occo:BAAALgADCgEJAQAAAA==.',
Ok='Okioak:BAAALgAECgYJDgAAAA==.',
Ol='Olgon:BAABLgAECn8lAAIKAAgJlRWdHQDrAQAKAAgJlRWdHQDrAQAAAA==.Olstinkyboot:BAAALgAECgEJAQAAAA==.',
On='Onehotdruid:BAAALgAECgcJDwABLgAFFAUJCwAfAMkYAA==.',
Op='Oprhawinfury:BAABLgAECn8fAAIfAAkJPQ6cKgDRAQAfAAkJPQ6cKgDRAQAAAA==.',
Or='Orgodemir:BAAALgADCgkJDwAAAA==.',
Ot='Otemoto:BAAALgAECgEJAQAAAA==.',
Pa='Paigor:BAAALgAECgIJAgAAAA==.Pakswagger:BAAALgAECgYJEgAAAA==.Pallyberry:BAABLgAECn8oAAIGAAkJZhv0BADfAgAGAAkJZhv0BADfAgAAAA==.Pancake:BAAALgAECgEJAQAAAA==.Pandemonia:BAABLgAECn8sAAMgAAkJygwqFgCYAQAgAAgJHgwqFgCYAQAJAAkJDAz1QwBdAQAAAA==.Paprika:BAAALgADCgkJDwAAAA==.Parsie:BAAALgAECgcJCQAAAA==.Pathibas:BAAALgADCgEJAQABLgAECgkJMAASAIwjAA==.Pattycakes:BAABLgAECn8hAAIfAAgJmBbiKgDQAQAfAAgJmBbiKgDQAQAAAA==.',
Pe='Pencil:BAACLgAFFH8IAAIJAAQJrxhLGQBOAQAJAAQJrxhLGQBOAQAuAAQKfxsABAkACAkhHc8WACwCAAkACAkhHc8WACwCACAAAwniBjNdAFcAAAgAAQkAAM8sAEUAAAAA.Pewpewlvltwo:BAABLgAECn8eAAINAAgJtxbgBAAMAgANAAgJtxbgBAAMAgAAAA==.Pewthree:BAAALgAECgYJCAABLgAECggJHgANALcWAA==.',
Ph='Pherocious:BAAALgAECgQJEQAAAA==.',
Pi='Pintsize:BAAALgADCgIJAgAAAA==.',
Pl='Plaguelis:BAAALgADCgEJAQABLgAECgkJKQANAFgaAA==.Plexy:BAAALgAECgcJCgAAAA==.',
Po='Pobble:BAAALgADCgcJBwAAAA==.Pokitz:BAABLgAECn8YAAIFAAYJ8wyFcwAFAQAFAAYJ8wyFcwAFAQAAAA==.Poprock:BAAALgADCgIJAgAAAA==.Potus:BAAALgADCgQJBAAAAA==.',
Pr='Primordinor:BAABLgAECn8dAAMOAAcJ8Rt1HADNAQAOAAYJrBp1HADNAQAlAAcJsBquGgB6AQAAAA==.Probnotalive:BAABLgAECn8bAAIKAAcJKxVVMgCEAQAKAAcJKxVVMgCEAQAAAA==.Probnotferal:BAAALgADCgIJAgAAAA==.Probnoturmom:BAABLgAECn8UAAIUAAcJ3xx0GAAYAgAUAAcJ3xx0GAAYAgAAAA==.',
Ra='Raevyn:BAAALgAECgEJAQAAAA==.Rakan:BAABLgAECn8vAAImAAkJeBwyAgCtAgAmAAkJeBwyAgCtAgAAAA==.Rakasha:BAAALgADCgkJCQAAAA==.Rallick:BAABLgAECn8oAAIGAAgJjhmzCACHAgAGAAgJjhmzCACHAgAAAA==.Ranì:BAABLgAECn8sAAIRAAkJKxdgBgAuAgARAAkJKxdgBgAuAgAAAA==.Rathger:BAAALgAECggJEgAAAA==.Ravenscythe:BAAALgADCgEJAQAAAA==.Raydor:BAAALgAECggJDgAAAA==.',
Re='Reb:BAABLgAECn8dAAITAAkJnwSBHgBIAQATAAkJnwSBHgBIAQAAAA==.Redic:BAAALgAECgMJAwAAAA==.Regis:BAAALgAECgYJBgABLgAECgcJIwAEAA4cAA==.Rellix:BAAALgADCgUJBQAAAA==.Rendkick:BAAALgADCgcJBwAAAA==.Rendwee:BAABLgAECn8kAAInAAkJsiD1AAD5AgAnAAkJsiD1AAD5AgAAAA==.Reuel:BAAALgAECgMJBAAAAA==.Rewolf:BAAALgAECgcJEAAAAA==.',
Rh='Rheemus:BAAALgADCgYJBgAAAA==.Rhul:BAAALgAECgUJCQAAAA==.',
Ri='Ricflairion:BAABLgAECn8YAAILAAcJ1AjbJwARAQALAAcJ1AjbJwARAQAAAA==.Rimuru:BAAALgAECgEJAQABLgAECgMJBgABAAAAAA==.',
Ro='Roadrunner:BAABLgAECn8jAAIKAAgJdw81MgDnAQAKAAgJdw81MgDnAQAAAA==.Rodcet:BAABLgAECn8zAAIFAAkJcySrAQBUAwAFAAkJcySrAQBUAwAAAA==.Roflcopterr:BAABLgAECn8dAAMGAAgJPxQ9GgC4AQAGAAgJPxQ9GgC4AQAFAAYJWAaKhwDdAAAAAA==.Rognan:BAAALgAECgEJAQAAAA==.Romina:BAAALgADCgEJBAAAAA==.Ronkin:BAAALgADCggJCAAAAA==.Rookgue:BAABLgAECn8hAAIdAAgJsRN+BADJAQAdAAgJsRN+BADJAQAAAA==.Rookoker:BAAALgAECgYJEQAAAA==.Rootsafarian:BAAALgADCgcJBwAAAA==.Rossa:BAAALgADCgEJAQAAAA==.Rossdair:BAAALgAECgMJAwABLgADCgUJCQABAAAAAA==.Rossperot:BAABLgAECn8bAAIfAAkJjR9nCADVAgAfAAkJjR9nCADVAgAAAA==.Rothschild:BAAALgADCgEJAQAAAA==.',
Sa='Sabako:BAAALgADCgcJCAAAAA==.Sacra:BAAALgADCgUJBQABLgAECggJJgAeACIkAA==.Saelara:BAAALgADCgcJCgAAAA==.Saelis:BAAALgADCgQJBAAAAA==.Sakaru:BAABLgAECn8bAAICAAgJSg7ERQCWAQACAAgJSg7ERQCWAQABLgAECggJIAAPAEsOAA==.Salmoney:BAAALgAECgQJBAAAAA==.Salorin:BAAALgADCgYJCQAAAA==.Samgee:BAACLgAFFH8KAAIFAAQJbRLyGgBBAQAFAAQJbRLyGgBBAQAuAAQKfzkAAgUACQmOH2oRAAYDAAUACQmOH2oRAAYDAAAA.Sandormu:BAAALgADCgkJCQAAAA==.Saphas:BAAALgAECgMJAwAAAA==.Saynar:BAABLgAECn8pAAIXAAgJ+CFvBwCwAgAXAAgJ+CFvBwCwAgAAAA==.',
Sc='Scattered:BAAALgAECggJEwAAAA==.Scooter:BAAALgAECgUJCgAAAA==.Scyx:BAAALgADCgEJAQAAAA==.',
Se='Seba:BAABLgAECn8lAAICAAgJcx2SFgBmAgACAAgJcx2SFgBmAgAAAA==.Selesne:BAAALgAECgYJDwAAAA==.Seraphicktwo:BAABLgAECn8YAAMTAAUJ/Q9fLADqAAATAAUJ/Q9fLADqAAAUAAQJHxpzLQDiAAAAAA==.Seriana:BAAALgAECggJDwAAAA==.Sermidas:BAACLgAFFH8IAAMmAAMJ8xeVDADhAAAmAAMJ8xeVDADhAAASAAIJ3AepGwCYAAAuAAQKfyIAAyYACQk6H7gCAPACACYACQk6H7gCAPACABIABwnOFFg0ANgBAAEuAAUUBQkLAB8AyRgA.',
Sh='Shadowcutter:BAAALgADCgkJDgABLgAECgUJBQABAAAAAA==.Shaggmz:BAAALgAECgQJCwAAAA==.Shinakuma:BAAALgAECgUJCQAAAA==.Shinma:BAAALgAECgQJCwAAAA==.Shrubbery:BAABLgAECn8VAAIJAAcJ+gO6cQDmAAAJAAcJ+gO6cQDmAAAAAA==.Shymary:BAAALgAECgQJCwAAAA==.',
Si='Siete:BAAALgAECgEJAQABLgAECgQJCQABAAAAAA==.Silvertip:BAAALgADCggJFQAAAA==.Silëx:BAAALgAECgUJDgAAAA==.Siouxiesioux:BAAALgADCgYJCgAAAA==.Siyona:BAAALgADCgkJDAAAAA==.',
Sk='Skits:BAAALgAECgIJAgAAAA==.Skyrah:BAAALgAECgYJBgAAAA==.Skyrie:BAAALgADCgQJBQAAAA==.',
Sl='Slagbröder:BAAALgADCgYJBgAAAA==.Slohine:BAAALgAECgUJBQAAAA==.Sludgecrush:BAAALgAECgYJCwAAAA==.Slugondeez:BAABLgAFFH8GAAIGAAIJ5hBaIgCMAAAGAAIJ5hBaIgCMAAAAAA==.',
Sm='Smallmike:BAAALgAECgIJAgAAAA==.Smitefist:BAAALgAECgIJAgAAAA==.Smokiee:BAAALgAECgYJEQAAAA==.',
Sn='Snailtrail:BAABLgAECn8VAAIbAAcJ3wQPEQCxAAAbAAcJ3wQPEQCxAAAAAA==.Snark:BAAALgAECgQJBAAAAA==.Snarkkin:BAAALgAECgQJDAAAAA==.Snowkim:BAABLgAECn8bAAIjAAgJlR0zBQAkAgAjAAgJlR0zBQAkAgAAAA==.Snuzzle:BAABLgAECn8hAAIDAAgJ3RtqBQAHAgADAAgJ3RtqBQAHAgAAAA==.',
So='Soniic:BAAALgAECgIJAgAAAA==.Soullessfros:BAABLgAECn8eAAIfAAcJLxLDQAB7AQAfAAcJLxLDQAB7AQAAAA==.Soullessman:BAAALgADCgQJCAAAAA==.Sourmash:BAAALgADCgkJCgAAAA==.',
Sp='Spaghet:BAABLgAECn8fAAIlAAkJLhnVCQA8AgAlAAkJLhnVCQA8AgAAAA==.Spillthetea:BAAALgAECgcJEAAAAA==.Sploot:BAAALgAECggJEAAAAA==.',
Sq='Squibbles:BAAALgAECgEJAQAAAA==.',
Sr='Srasjet:BAABLgAECn8WAAIOAAYJsh/kEwAWAgAOAAYJsh/kEwAWAgAAAA==.',
Ss='Ssimba:BAAALgAECgYJCgAAAA==.',
St='Stabytha:BAAALgAECgUJDAAAAA==.Stark:BAAALgADCgYJCgAAAA==.Starlight:BAAALgAECgEJAQAAAA==.Stormae:BAAALgADCgMJAgAAAA==.Stormcall:BAAALgAECgUJCgAAAA==.Stratusfied:BAAALgAECgIJAgAAAA==.',
Su='Susbandaid:BAAALgADCgYJBgAAAA==.',
Sw='Sweetiefox:BAAALgAECgcJBwAAAA==.Swiss:BAAALgAECgYJDwAAAA==.',
Sy='Syllai:BAAALgAECgYJBgAAAA==.Syphus:BAAALgADCgQJBAAAAA==.',
['Sá']='Sáëgárón:BAABLgAECn8VAAMSAAYJAxYTIQBjAQASAAYJAxYTIQBjAQAmAAEJpwWDQgAqAAAAAA==.',
Ta='Tacyon:BAAALgADCggJDwAAAA==.Taliden:BAAALgAECgYJBgAAAA==.Tallera:BAAALgADCgEJAgAAAA==.Taniyah:BAAALgAECgQJBgAAAA==.Tankinstine:BAAALgADCgEJAgAAAA==.Taraylda:BAABLgAECn8XAAMeAAcJAhoKGgDIAQAeAAcJAhoKGgDIAQATAAIJoQoJQgBrAAAAAA==.Tarful:BAAALgADCgQJBAAAAA==.Tarzand:BAAALgADCgEJAQABLgADCgcJDwABAAAAAA==.Tazo:BAABLgAECn8VAAIFAAcJTQ+LUABVAQAFAAcJTQ+LUABVAQAAAA==.',
Te='Tearek:BAAALgAFFAEJAQAAAA==.Tecdor:BAAALgAECgQJBAAAAA==.Temla:BAABLgAECn8oAAIKAAkJqRU1FAAuAgAKAAkJqRU1FAAuAgAAAA==.Tenga:BAAALgAECgQJBAAAAA==.Teronfiggy:BAABLgAECn8VAAIfAAgJ9Al0SABiAQAfAAgJ9Al0SABiAQAAAA==.',
Tf='Tfirs:BAACLgAFFH8GAAIDAAMJZg0mBwCtAAADAAMJZg0mBwCtAAAuAAQKfywAAgMACAm+GywHAEsCAAMACAm+GywHAEsCAAEuAAEKCQkJAAEAAAAA.',
Th='Thartilidan:BAAALgAECgYJEQAAAA==.Theokoles:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.Thepaladin:BAAALgADCgMJAwAAAA==.Thickblòód:BAAALgAECgQJBAAAAA==.',
Ti='Tilythia:BAAALgADCgUJBQAAAA==.',
To='Tona:BAAALgADCgMJAwAAAA==.Toospookie:BAAALgADCgQJAgAAAA==.Tophu:BAAALgADCgcJBwAAAA==.Torkz:BAAALgADCgEJAgAAAA==.',
Tr='Tramplip:BAABLgAECn8XAAIgAAYJYw7oDAADAQAgAAYJYw7oDAADAQAAAA==.Treecloud:BAABLgAECn8sAAIiAAkJLyNpAQAvAwAiAAkJLyNpAQAvAwAAAA==.Trevian:BAAALgAECgYJDwAAAA==.',
Tu='Tub:BAAALgAECgQJBAABLgAFFAQJDAAPAHgLAA==.Tuluxxi:BAABLgAECn8xAAIOAAkJWh6gAwARAwAOAAkJWh6gAwARAwAAAA==.Turborunic:BAAALgADCgkJGwAAAA==.Turiae:BAACLgAFFH8FAAILAAQJNRH1FAA2AQALAAQJNRH1FAA2AQAuAAQKfx8ABAsACAmnGN0SALQBAAwABwncFsEQANEBAAsABwnuF90SALQBACgABQkhCZ80AMgAAAAA.Tuskerz:BAAALgAECgEJAQAAAA==.Tusobrinna:BAAALgAECgUJBgAAAA==.Tutter:BAAALgADCgIJAgAAAA==.',
Tw='Twunk:BAAALgAECgYJDQAAAA==.',
Ty='Typhlotic:BAAALgADCgMJAwAAAA==.Tyrennius:BAAALgAECgQJBAAAAA==.Tyrianis:BAABLgAECn8iAAMcAAkJNxlNBgBOAgAcAAkJuBdNBgBOAgAdAAMJzh6qEwDFAAAAAA==.',
Tz='Tzxdh:BAAALgAECgUJBQAAAA==.',
Ug='Uglymancer:BAAALgAECgYJDwAAAA==.',
Uj='Ujimas:BAAALgAECgQJCwAAAA==.',
Un='Unchartedd:BAAALgADCgEJAQAAAA==.',
Va='Vaenira:BAAALgADCgUJBgAAAA==.Valdara:BAAALgADCgkJEgAAAA==.Valemon:BAAALgAECgIJAgAAAA==.Vampireshade:BAABLgAECn8hAAIkAAgJdQduBgBAAQAkAAgJdQduBgBAAQAAAA==.Vanimao:BAABLgAECn8hAAQHAAgJqRCqPACxAQAHAAgJqRCqPACxAQADAAQJJg6UFwCmAAAiAAEJwgYkWQAwAAAAAA==.Vankman:BAAALgADCgcJBwAAAA==.Vannaka:BAAALgADCgEJAQAAAA==.',
Vb='Vbull:BAAALgAECgEJAQAAAA==.',
Ve='Vedrolan:BAAALgADCgUJDgABLgAFFAIJBQAQAGQNAA==.Velifya:BAAALgADCgMJAwAAAA==.Velindon:BAAALgADCgYJBgAAAA==.Velissari:BAAALgAECgQJBwAAAA==.Velonar:BAAALgADCgEJAQAAAA==.Velouria:BAABLgAECn8xAAQDAAkJDyLvAAD7AgADAAkJ/SDvAAD7AgAiAAgJ5h8NDQDIAgAHAAIJ9QSUwABGAAAAAA==.Venatra:BAAALgAECgIJAgAAAA==.Verudora:BAAALgADCgcJBwAAAA==.Vexira:BAAALgADCgcJBwAAAA==.',
Vi='Violet:BAABLgAECn8gAAIoAAgJIBe1BQA3AgAoAAgJIBe1BQA3AgAAAA==.Violette:BAABLgAECn8YAAIKAAYJPRA+RwA4AQAKAAYJPRA+RwA4AQAAAA==.Visix:BAAALgADCgMJAwAAAA==.',
Vo='Voidchacha:BAAALgADCgEJAQAAAA==.Voidlink:BAABLgAECn8kAAIeAAkJ7xOpCgAqAgAeAAkJ7xOpCgAqAgAAAA==.Voidmistress:BAABLgAECn8gAAICAAYJVRchWwBeAQACAAYJVRchWwBeAQAAAA==.Voidpup:BAABLgAECn8hAAIXAAYJzRmILgB9AQAXAAYJzRmILgB9AQAAAA==.Volgrimm:BAABLgAECn8bAAIQAAgJKwvyGwBUAQAQAAgJKwvyGwBUAQAAAA==.Volitaire:BAAALgADCgYJBgAAAA==.',
Vy='Vynethan:BAAALgAECgEJAgAAAA==.',
['Vé']='Véngence:BAAALgAECgUJCQAAAA==.',
['Vê']='Vêx:BAAALgADCgYJBgAAAA==.',
Wa='Wabalabalosh:BAAALgADCgkJCQAAAA==.Wabgucci:BAAALgADCgUJBQAAAA==.Wabwum:BAAALgAECgMJAwAAAA==.Wakaekwondo:BAAALgAECgEJAQAAAA==.Wakarisma:BAAALgAECgEJAQAAAA==.Wanda:BAAALgAECgEJAQAAAA==.Wangao:BAABLgAFFH8FAAIQAAIJZA1vLwCEAAAQAAIJZA1vLwCEAAAAAA==.Warbluster:BAAALgADCgIJAgAAAA==.Warchylde:BAAALgADCgkJCQAAAA==.Warolderoy:BAABLgAECn8wAAISAAkJjCPtAAA5AwASAAkJjCPtAAA5AwAAAA==.',
We='Weedshaman:BAAALgAECgEJAwAAAA==.Weedwax:BAAALgAECgQJBAAAAA==.Weil:BAAALgADCgIJAgAAAA==.',
Wh='Whiinuss:BAABLgAECn8UAAIFAAcJlw26fwB7AQAFAAcJlw26fwB7AQAAAA==.Whytrabbit:BAAALgAECgIJAgAAAA==.',
Wi='Wigglesdeath:BAAALgADCgQJBAAAAA==.',
Wl='Wldeagle:BAAALgAECgQJBAAAAA==.',
Wo='Woker:BAAALgAECgEJAQABLgAECgkJKQANAFgaAA==.Woodpig:BAABLgAECn8pAAMHAAkJ2SE/AgBlAwAHAAkJ2SE/AgBlAwAiAAIJXgbaVwAzAAAAAA==.Woogie:BAAALgAECgQJCwAAAA==.',
Wr='Wrangle:BAAALgADCgEJAQAAAA==.',
Wy='Wyldshade:BAAALgADCgYJCAAAAA==.Wyrm:BAAALgAECgUJBQABLgAECgUJCgABAAAAAA==.',
Xa='Xaladin:BAAALgAECgYJDgAAAA==.Xathas:BAAALgAECgQJBAAAAA==.',
Xe='Xenna:BAAALgAECgQJBAAAAA==.',
Xi='Xiata:BAAALgAECgYJBgAAAA==.Xiu:BAAALgAECgMJAwAAAA==.',
Xr='Xrp:BAAALgADCgIJAwAAAA==.',
Ye='Yeoman:BAAALgAECgUJDgAAAA==.',
Yg='Yggdralith:BAAALgAECggJFgAAAQ==.',
Yo='Yourdeath:BAAALgAECgkJAwAAAA==.',
Yu='Yunosmall:BAAALgADCgIJAgAAAA==.Yunosmart:BAAALgAECgMJBAAAAA==.',
Za='Zaen:BAABLgAECn8qAAMJAAgJ7RzaEwBCAgAJAAgJ7RzaEwBCAgAgAAMJ1AuvQwCmAAAAAA==.Zagreus:BAAALgADCgcJCAAAAA==.Zarkir:BAABLgAECn8YAAQfAAgJTSBrFwBAAgAfAAcJwCFrFwBAAgAVAAcJrxeYGQCHAQAWAAEJxwvSFgAxAAABLgAECgYJFwACAKciAA==.Zarkìr:BAABLgAECn8XAAICAAYJpyKLZwAIAgACAAYJpyKLZwAIAgAAAA==.Zaues:BAAALgAECgMJBAAAAA==.',
Ze='Zelily:BAAALgAECggJDwAAAA==.Zenarri:BAAALgADCgYJBwAAAA==.Zepha:BAAALgAECgYJCwAAAA==.',
Zl='Zlyandien:BAAALgADCggJDwABLgAECgcJFwAeAAIaAA==.',
Zo='Zornov:BAABLgAECn8gAAIjAAgJhx55BAA/AgAjAAgJhx55BAA/AgAAAA==.',
Zu='Zulrich:BAAALgADCgYJBgAAAA==.',
Zv='Zvirax:BAAALgADCggJCAAAAA==.',
['Ëu']='Ëuni:BAAALgAECgUJDAAAAA==.',
['Ðe']='Ðemôns:BAAALgAECgEJAQAAAA==.',
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
