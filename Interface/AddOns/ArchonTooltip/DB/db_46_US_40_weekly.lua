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

local lookup = {'Unknown-Unknown','Mage-Frost','Druid-Guardian','Monk-Mistweaver','Paladin-Retribution','Druid-Restoration','Warlock-Affliction','Warlock-Demonology','Hunter-BeastMastery','Evoker-Augmentation','Evoker-Devastation','Shaman-Enhancement','Shaman-Restoration','Monk-Windwalker','Monk-Brewmaster','Warrior-Protection','Warrior-Fury','Priest-Shadow','Priest-Holy','DeathKnight-Blood','DeathKnight-Frost','DemonHunter-Devourer','DemonHunter-Havoc','Hunter-Survival','Hunter-Marksmanship','DemonHunter-Vengeance','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','DeathKnight-Unholy','Paladin-Holy','Mage-Arcane','Druid-Balance','Paladin-Protection','Rogue-Outlaw','Warlock-Destruction','Shaman-Elemental','Warrior-Arms','Druid-Feral','Evoker-Preservation',}
local provider = {region='US',realm='Bloodhoof',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abarlton:BAAALgAECgYJCQABLgAECgUJBQABAAAAAA==.',
Ad='Adabeam:BAAALgADCgcJCwAAAA==.Adagio:BAABLgAECn8gAAICAAgJaBr2JwDFAQACAAgJaBr2JwDFAQAAAA==.Adetalo:BAABLgAECn8dAAIDAAgJ+RnCBADPAQADAAgJ+RnCBADPAQAAAA==.Adiara:BAAALgAECgMJAwAAAA==.Aditu:BAAALgAECgUJCgAAAA==.',
Ae='Aelis:BAAALgADCgcJCAAAAA==.Aemulo:BAAALgAECgUJBwAAAA==.Aerith:BAAALgADCgcJBwAAAA==.',
Ag='Agasonex:BAAALgADCgMJAwAAAA==.',
Ai='Airent:BAAALgAECgMJBQAAAA==.Aiyana:BAAALgAECgYJDgAAAA==.',
Ak='Akiirii:BAAALgADCgMJAwAAAA==.',
Al='Alaestel:BAAALgAECgQJBwAAAA==.Alkaraho:BAAALgAECgMJAwAAAA==.Alleyways:BAABLgAECn8ZAAIEAAgJfSGoBwDdAgAEAAgJfSGoBwDdAgAAAA==.Alzey:BAABLgAECn8WAAIFAAYJfA4NTgAiAQAFAAYJfA4NTgAiAQAAAA==.',
Am='Ambeon:BAAALgADCgUJBQAAAA==.Ammathindis:BAAALgADCgMJAgAAAA==.Amplers:BAAALgADCgUJBwAAAA==.',
An='Angelbane:BAAALgADCgQJBAAAAA==.Angina:BAAALgAECgEJAQAAAA==.Annarcis:BAAALgAECgMJBAAAAA==.Anthiell:BAAALgADCgEJAQAAAA==.Antiman:BAAALgAECgYJEgAAAA==.',
Ap='Aplcyder:BAABLgAECn8mAAIGAAgJwgzMKQA+AQAGAAgJwgzMKQA+AQAAAA==.',
Ar='Arachnid:BAABLgAECn8hAAICAAcJkCJBMQCtAgACAAcJkCJBMQCtAgAAAA==.Aragorn:BAAALgADCgMJAwAAAA==.Aratyn:BAAALgAECgYJCQAAAA==.',
At='Ati:BAAALgADCgIJAgAAAA==.',
Au='Audxo:BAAALgADCgMJAwAAAA==.',
Ay='Ayayron:BAAALgADCgQJBAAAAA==.',
Ba='Backhawk:BAAALgADCgcJEAAAAA==.Backsurgery:BAAALgAECgYJBgAAAA==.Baerrn:BAAALgAECgUJCgAAAA==.Bamboo:BAAALgAECgYJCQAAAA==.Baricia:BAAALgAECggJEgAAAA==.Barix:BAAALgAECgEJAQAAAA==.Barnd:BAAALgADCggJDwAAAA==.Barrin:BAABLgAECn8dAAMHAAcJUBc4BwDiAQAHAAYJJRs4BwDiAQAIAAUJOgjnUQD7AAAAAA==.Bastim:BAAALgAECgIJAgAAAA==.Baussassbich:BAAALgADCgYJBgAAAA==.Bawnchu:BAAALgAECgIJAgAAAA==.',
Be='Beastmaster:BAABLgAECn8iAAIJAAgJpSNUAwDWAgAJAAgJpSNUAwDWAgAAAA==.Becket:BAAALgADCgIJAwABLgAECgMJBQABAAAAAA==.Beefcakell:BAAALgADCgcJDQAAAA==.Beiki:BAAALgAECgMJBgAAAA==.Belthar:BAAALgAECgQJCQAAAA==.Bently:BAABLgAECn8XAAMKAAcJoCCQCAAFAgAKAAcJmB+QCAAFAgALAAUJmSEoEwCvAQAAAA==.Berexis:BAAALgAECgYJDAAAAA==.',
Bi='Bissafiyah:BAACLgAFFH8UAAIMAAUJ/yNsAABKAQAMAAUJ/yNsAABKAQAuAAQKfzsAAgwACQlpJREAAHcDAAwACQlpJREAAHcDAAAA.Biznasty:BAAALgAECgEJAQAAAA==.',
Bl='Bloodgon:BAAALgAFFAEJAQAAAA==.Bluetuesday:BAAALgAECgMJAwAAAA==.',
Bo='Bohica:BAABLgAECn8mAAINAAgJvRErGwCKAQANAAgJvRErGwCKAQAAAA==.Bonechop:BAAALgADCgYJBgAAAA==.Bootymeat:BAAALgADCgEJAQAAAA==.Bowtox:BAAALgAECgEJAQAAAA==.Boyakasha:BAAALgAECgMJBgAAAA==.',
Br='Brewfu:BAAALgADCgIJAgAAAA==.Brewpub:BAAALgADCgQJBAAAAA==.Brewsome:BAABLgAECn8mAAMOAAgJuBpYBgAoAgAOAAgJOhpYBgAoAgAPAAgJChi7HAAdAgAAAA==.Bruceprime:BAAALgAECgkJAQAAAA==.Bryycelest:BAABLgAECn8bAAIPAAcJFhrFDwCWAQAPAAcJFhrFDwCWAQAAAA==.Brådòn:BAAALgAECgYJCwAAAA==.',
Bu='Bucket:BAABLgAECn8jAAIQAAgJxRE3CwBzAQAQAAgJxRE3CwBzAQAAAA==.Bunkiee:BAAALgADCgkJHQAAAA==.Bunnybane:BAAALgAECgYJEAAAAA==.Burny:BAABLgAECn8aAAICAAcJVCVGJgDZAgACAAcJVCVGJgDZAgAAAA==.Buttadogg:BAAALgAECgUJCAAAAA==.',
['Bè']='Bèth:BAAALgADCgYJCAAAAA==.',
['Bë']='Bëckey:BAAALgADCgIJAgAAAA==.',
Ca='Calyx:BAAALgAECgMJBgAAAA==.Canadani:BAAALgAECgcJDQAAAA==.Candorite:BAAALgAECgYJCQAAAA==.Caphriel:BAABLgAECn8VAAIRAAgJpxmxCAAfAgARAAgJpxmxCAAfAgAAAA==.Capita:BAAALgAECgYJEwAAAA==.Carsinegan:BAAALgADCgMJBgAAAA==.Cassica:BAABLgAECn8dAAMSAAcJZxkwEwBrAQASAAcJZxkwEwBrAQATAAIJ2gmfNgBXAAAAAA==.Catskin:BAAALgAECgUJDQAAAA==.',
Ce='Celivalasha:BAAALgADCgUJBQAAAA==.Cell:BAABLgAECn8jAAIPAAgJSyQsBQA3AwAPAAgJSyQsBQA3AwAAAA==.Cet:BAAALgADCgUJBQAAAA==.',
Ch='Chadvader:BAAALgADCgIJAgAAAA==.Chainlink:BAAALgADCgYJBgAAAA==.Chanpagne:BAAALgADCgUJBQAAAA==.Charkle:BAAALgAECgIJAQAAAA==.Chayea:BAAALgADCgEJAQAAAA==.Chillylilly:BAABLgAECn8jAAMUAAgJwCS5AQBqAgAUAAgJwCS5AQBqAgAVAAQJgRmSBQA2AQAAAA==.Chlorophyll:BAAALgAECgQJBAAAAA==.Chocola:BAAALgADCgEJAQAAAA==.Chummie:BAABLgAECn8bAAMIAAgJNhyLGgDWAQAIAAcJXRqLGgDWAQAHAAYJnBlDCADHAQAAAA==.',
Ci='Cielcin:BAAALgAECgYJDQAAAA==.Ciremiih:BAAALgAECgEJAQAAAA==.Citymage:BAABLgAECn8eAAICAAkJ2xW4HwDuAQACAAkJ2xW4HwDuAQAAAA==.Cixelsyd:BAAALgADCgYJCwAAAA==.',
Cl='Clamchowda:BAABLgAECn8dAAMWAAgJoxu3DwD0AQAWAAgJQhi3DwD0AQAXAAUJUh5oIwCiAQAAAA==.',
Co='Codê:BAAALgAECgYJEgAAAA==.Coffeecup:BAAALgADCgIJAgAAAA==.Corride:BAABLgAECn8fAAIYAAYJEyPRCQBAAgAYAAYJEyPRCQBAAgAAAA==.',
Cr='Crazyeyes:BAAALgADCgMJAwAAAA==.Crimsondeath:BAAALgAECgMJBgAAAA==.Crutch:BAABLgAECn8VAAMMAAcJehMFCQBbAQAMAAUJIhQFCQBbAQANAAYJEBL7UQA9AQAAAA==.Crystanikus:BAAALgAECgEJAQAAAA==.',
Cu='Cuckenjoyer:BAAALgAECgYJCgAAAA==.',
Cy='Cyprus:BAAALgAECgEJAQAAAA==.',
Da='Daddytrump:BAAALgAECgYJCQAAAA==.Daelric:BAAALgADCgIJAwAAAA==.Daender:BAABLgAECn8jAAMJAAgJtiHyCQBeAgAJAAgJtiHyCQBeAgAZAAEJghiEHQBIAAAAAA==.Daenor:BAAALgAECgEJAgAAAA==.Dairydemon:BAABLgAECn8jAAIaAAgJ4AxYCAApAQAaAAgJ4AxYCAApAQAAAA==.Damageus:BAABLgAECn8cAAICAAgJ5CJ+DACAAgACAAgJ5CJ+DACAAgAAAA==.Daniryl:BAEALgAECgcJEwAAAA==.Darcness:BAABLgAECn8WAAMbAAUJURZ+FwAZAQAbAAUJURZ+FwAZAQAcAAIJSAt5DgB6AAAAAA==.Darcside:BAAALgAECgIJAwAAAA==.Darkclouds:BAAALgADCgIJAgAAAA==.Darksoul:BAAALgAECgcJEAABLgAECgcJFwAdAAIaAA==.Darkxwraith:BAAALgAECgYJCAAAAA==.Dashtoolite:BAAALgAECgYJDgAAAA==.Datsumbeech:BAAALgAECgYJEAAAAA==.',
De='Deajer:BAAALgADCgYJBwAAAA==.Deathsabeach:BAAALgAECgEJAQAAAA==.Deathvìxen:BAAALgAECgQJCAAAAA==.Debit:BAAALgAECgcJEwAAAA==.Demonhunter:BAACLgAFFH8KAAIWAAQJMyFtCQBsAQAWAAQJMyFtCQBsAQAuAAQKfx0AAhYACAk/JK4KAC4DABYACAk/JK4KAC4DAAAA.Demonwoogie:BAAALgADCgYJBgABLgAECgQJCwABAAAAAA==.Dendrophilia:BAAALgADCgIJAgAAAA==.Densamin:BAAALgAECgYJEgAAAA==.Deviyn:BAAALgADCgIJAgAAAA==.Devra:BAAALgADCggJCAAAAA==.Deàdly:BAAALgAECgIJAgAAAA==.',
Di='Dietchrist:BAAALgAECggJEwAAAA==.Dilligaf:BAAALgADCggJCAAAAA==.',
Dk='Dkanabiss:BAAALgAECgMJBAAAAA==.',
Do='Doist:BAAALgAECgEJAQABLgAECgUJDgABAAAAAA==.Donngaz:BAAALgAECgIJAgAAAA==.',
Dr='Drewnei:BAAALgADCgkJCQAAAA==.Drewserk:BAABLgAECn8dAAIRAAgJjha0DQDXAQARAAgJjha0DQDXAQAAAA==.Drkxmaniac:BAAALgAECgQJBgABLgAECgUJBQABAAAAAA==.Drminnowphd:BAAALgAFFAEJAQAAAA==.Drpiscisphd:BAABLgAECn8sAAMeAAkJtiDwDgAkAwAeAAkJtiDwDgAkAwAUAAcJwwV+KQDzAAABLgAFFAEJAQABAAAAAA==.Drsaltyballz:BAABLgAECn8YAAIcAAgJOhl6BgAOAgAcAAgJOhl6BgAOAgAAAA==.Drugpala:BAAALgAECgIJAgAAAA==.Druji:BAAALgADCgIJAgAAAA==.Drumuss:BAAALgADCgEJAQAAAA==.',
Du='Dudesk:BAAALgAECgQJBAAAAA==.Duffuna:BAAALgADCgEJAQABLgAECggJKAAYAMclAA==.Duffunha:BAABLgAECn8oAAIYAAgJxyXNAAD6AgAYAAgJxyXNAAD6AgAAAA==.',
Dy='Dye:BAABLgAECn8hAAIfAAgJpxtnBgB8AgAfAAgJpxtnBgB8AgAAAA==.Dyre:BAAALgAECgYJEgAAAA==.Dyslexic:BAAALgAECgYJEgAAAA==.Dyspepsia:BAACLgAFFH8HAAIFAAQJKwQNEQAdAQAFAAQJKwQNEQAdAQAuAAQKfxYAAgUACQnjFAs2AEoCAAUACQnjFAs2AEoCAAAA.',
['Dô']='Dôngus:BAAALgADCgMJAwABLgAECgIJAgABAAAAAA==.',
['Dõ']='Dõngus:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.',
['Dö']='Döngus:BAAALgADCgEJAQABLgAECgIJAgABAAAAAA==.',
Ed='Edie:BAAALgADCggJEwAAAA==.',
Ei='Eirenn:BAAALgAECgkJBgAAAA==.',
El='Elenaura:BAAALgAECgMJAwAAAA==.Eleren:BAAALgAECgYJEQAAAA==.Elimee:BAABLgAECn8nAAICAAkJXyBKDgBUAwACAAkJXyBKDgBUAwAAAA==.Ellasia:BAAALgAECgIJAwAAAA==.Elric:BAABLgAECn8jAAIFAAgJtBSdJQCtAQAFAAgJtBSdJQCtAQAAAA==.Elsie:BAAALgAECgUJCQABLgAECgYJCgABAAAAAA==.Elunea:BAAALgADCgcJDQAAAA==.Elunemittens:BAAALgADCgYJBgAAAA==.',
Em='Emart:BAAALgAECgYJDwAAAA==.Emozella:BAAALgAECgEJAQAAAA==.',
En='Enatresh:BAAALgADCgIJAwAAAA==.',
Ep='Epsilon:BAAALgAECgkJCQAAAA==.',
Er='Erayna:BAABLgAECn8cAAIGAAgJQg83JQBaAQAGAAgJQg83JQBaAQAAAA==.Ereillea:BAAALgAECgYJDQAAAA==.',
Es='Essence:BAABLgAECn8WAAMCAAgJmxTqagAAAgACAAgJDBHqagAAAgAgAAQJ1xobDAARAQAAAA==.',
Eu='Euko:BAABLgAECn8jAAMhAAgJVx5PBQBYAgAhAAgJVx5PBQBYAgAGAAgJchUpNAAIAQAAAA==.',
Ev='Evedk:BAAALgAECgkJBQAAAA==.Evepriest:BAAALgADCgMJAQAAAA==.',
Fa='Failrogue:BAAALgADCgUJCwAAAA==.Falconclaw:BAAALgADCgkJGAAAAA==.Falkensnoman:BAAALgAECgYJEgAAAA==.Fayedra:BAAALgAECgYJCQAAAA==.',
Fc='Fcawfe:BAAALgAECgMJAwABLgAECgUJCQABAAAAAA==.',
Fe='Febee:BAAALgADCgcJAQAAAA==.Feenii:BAABLgAECn8nAAIMAAgJJxlQBADtAQAMAAgJJxlQBADtAQAAAA==.Felburst:BAAALgAECgMJAwAAAA==.Felfireqt:BAAALgAECgEJAgAAAA==.',
Fi='Figgyandrii:BAAALgADCgcJBwAAAA==.Fionar:BAAALgADCgIJAgAAAA==.Fizzlelich:BAAALgADCgYJCAAAAA==.',
Fl='Flamesters:BAAALgAECgIJAwAAAA==.Fluffpuff:BAAALgADCgMJAwAAAA==.',
Fo='Foxdeer:BAAALgAECgYJCwAAAA==.',
Fr='Frenchtoast:BAAALgAECgMJAwAAAA==.',
Ga='Gambachii:BAAALgAECgcJDQAAAA==.Gankss:BAABLgAECn8aAAIfAAYJKSR4BgB6AgAfAAYJKSR4BgB6AgAAAA==.Garakddon:BAAALgADCgkJDgABLgAECgYJDwABAAAAAA==.Garryy:BAAALgAECgMJBQAAAA==.',
Ge='Geegandolm:BAAALgADCgkJEwAAAA==.Genjaru:BAAALgAECgEJAQAAAA==.Genndalf:BAAALgADCgcJBwAAAA==.Geostorm:BAAALgAECgEJAQAAAA==.',
Gh='Gharmag:BAAALgAECgEJAQAAAA==.',
Gi='Giramar:BAAALgAECgcJDAAAAA==.',
Go='Gobbyshamm:BAAALgAECgEJAQAAAA==.Gobsmackers:BAAALgAECgEJAQAAAA==.Gomklin:BAAALgADCgcJCAABLgAECggJKgAFACokAA==.Goobtastic:BAAALgADCgQJBAAAAA==.Goteem:BAAALgAECggJEwAAAA==.',
Gr='Griffhud:BAAALgAECgYJCAAAAA==.Grimrox:BAAALgAECgYJDwAAAA==.Grixx:BAAALgADCgUJBQAAAA==.Groupie:BAAALgADCgUJCgABLgAECgcJGAAZAMgPAA==.',
Gt='Gtatedk:BAAALgAECgEJAQAAAA==.',
Gu='Guntera:BAAALgAECgYJDgAAAA==.Guts:BAAALgADCgMJAwAAAA==.',
Gw='Gwendalyn:BAAALgAECgQJBQAAAA==.',
['Gä']='Gäz:BAAALgADCgEJAQAAAA==.',
Ha='Halexion:BAAALgADCgIJAgAAAA==.Haomaru:BAAALgAECgUJCQAAAA==.Hardcandy:BAABLgAECn8YAAIZAAcJyA9vCgAqAQAZAAcJyA9vCgAqAQAAAA==.Hawkìns:BAAALgAECgEJAQAAAA==.',
He='Heartsoul:BAAALgAECgYJCQAAAA==.Heavyarm:BAAALgADCgcJDwAAAA==.Hellork:BAAALgADCgQJBAAAAA==.Hermosura:BAAALgADCgUJCQAAAA==.Hex:BAAALgAECgYJBgAAAA==.',
Hi='Hiccups:BAAALgAECgMJAwAAAA==.Himawarí:BAAALgAECgYJCQAAAA==.Hiyank:BAABLgAECn8UAAIPAAYJyyOxFABoAgAPAAYJyyOxFABoAgAAAA==.',
Ho='Hoffmin:BAABLgAECn8QAAMWAAcJKhYUeAA+AQAWAAYJKhYUeAA+AQAXAAIJphKuVgCMAAAAAA==.Holemeister:BAABLgAECn8tAAIFAAgJlCSuAwDnAgAFAAgJlCSuAwDnAgAAAA==.Holyfresh:BAAALgADCgEJAQAAAA==.Holymann:BAABLgAECn8ZAAISAAYJBQ15NQA/AQASAAYJBQ15NQA/AQAAAA==.Holyschnikey:BAAALgAECgQJEAAAAA==.Holyz:BAAALgAECgcJEQAAAA==.Horgable:BAAALgADCgIJAgAAAA==.Horrorpops:BAAALgADCgUJBQAAAA==.Hozaki:BAAALgAECgQJBAABLgAECgUJBQABAAAAAA==.',
Hu='Hudfin:BAAALgADCgUJBQAAAA==.Hundred:BAAALgADCgUJBQABLgAECgEJAQABAAAAAA==.',
['Hí']='Hílthaen:BAABLgAECn8bAAITAAcJrBFUFQBlAQATAAcJrBFUFQBlAQAAAA==.',
Ic='Icebones:BAAALgADCgcJDAABLgAECgQJCQABAAAAAA==.Icelight:BAAALgAECgQJCQAAAA==.Ichigokisu:BAAALgAECgQJBgAAAA==.',
Il='Illiduji:BAAALgADCgMJAwAAAA==.Illy:BAAALgAECggJEQAAAA==.',
Im='Imposed:BAAALgAECgUJDgAAAA==.',
In='Instantdeath:BAAALgAECgUJBQAAAA==.Invali:BAAALgAECgMJAwAAAA==.',
Ir='Irônhide:BAAALgADCgYJCQAAAA==.',
Iv='Ivranda:BAAALgADCgkJEgABLgAECgYJCQABAAAAAA==.',
Iz='Iz:BAAALgADCgMJAwABLgADCgUJBQABAAAAAA==.',
Ja='Jaapp:BAAALgAECgMJBgAAAA==.Jahan:BAABLgAECn8gAAMdAAgJzyEPFAAMAgAdAAgJzyEPFAAMAgASAAMJ/xIYJQDTAAAAAA==.Jamie:BAAALgAFFAIJAgAAAA==.Jaydine:BAAALgADCgYJBgABLgAECgkJJwACAF8gAA==.',
Je='Jeri:BAAALgADCgcJFAAAAA==.',
Jh='Jhie:BAAALgAECgQJBAAAAA==.',
Ju='Jud:BAAALgAECgYJCAAAAA==.Juxtaposed:BAAALgADCgUJBAAAAA==.',
Ka='Kaerei:BAABLgAECn8gAAIFAAgJ7RvLFAAVAgAFAAgJ7RvLFAAVAgAAAA==.Kaleb:BAAALgAECgcJEwAAAA==.Kalfalah:BAAALgAECgQJCwAAAA==.Kalferno:BAAALgAECgMJBQAAAA==.Kalirkaz:BAABLgAECn8dAAIGAAcJZht7FQDYAQAGAAcJZht7FQDYAQAAAA==.Kallipsa:BAAALgAECgEJAQAAAA==.Karasu:BAAALgAECgIJAgABLgAECggJIAAOAEsOAA==.Karst:BAAALgAECgQJBAABLgAECggJIAAdAM8hAA==.Kathria:BAAALgAECgcJDAAAAA==.',
Ke='Keládry:BAAALgAECgUJCAAAAA==.Keskiyö:BAAALgADCgkJFQABLgAECggJIAAOAEsOAA==.',
Kh='Khallock:BAABLgAECn8VAAIHAAYJ0hBwDABxAQAHAAYJ0hBwDABxAQAAAA==.Khamael:BAAALgAECgEJAQAAAA==.',
Ki='Kiemen:BAABLgAECn8YAAIeAAgJ9xV1TAAOAgAeAAgJ9xV1TAAOAgAAAA==.Killko:BAAALgAECgcJEQAAAA==.Kinki:BAAALgAECgMJAwABLgAECgcJGAAZAMgPAA==.Kirisen:BAAALgAECgUJCQAAAA==.Kitan:BAAALgAECgQJBQAAAA==.',
Ko='Konno:BAAALgAECgQJBAABLgAFFAUJFAAMAP8jAA==.Kooterr:BAAALgADCgUJBQAAAA==.',
Kr='Kragsloor:BAAALgADCgYJBgAAAA==.Kredorin:BAAALgAECgYJCgAAAA==.Krewella:BAAALgADCgcJBwAAAA==.Krovmar:BAAALgADCgUJBQAAAA==.',
Ks='Kspanxx:BAAALgAECgMJAwAAAA==.',
Kt='Kthanx:BAAALgADCgYJBgAAAA==.',
Ku='Kungpowgazer:BAAALgAECgcJEAAAAA==.Kunls:BAAALgAECgcJEAAAAA==.Kuraki:BAAALgAECgYJCQAAAA==.Kurasa:BAABLgAECn8gAAMOAAgJSw4+EQBtAQAOAAgJSw4+EQBtAQAEAAQJowH2WgBjAAAAAA==.Kutraz:BAAALgAECgQJBQAAAA==.',
La='Ladrar:BAAALgADCgMJBQAAAA==.Laelina:BAAALgAECgEJAgAAAA==.Lanadiel:BAABLgAECn8jAAIiAAgJ4h8MAgB5AgAiAAgJ4h8MAgB5AgAAAA==.Lazz:BAAALgAECgYJDQAAAA==.',
Le='Legend:BAACLgAFFH8JAAIWAAQJYCDxBgCFAQAWAAQJYCDxBgCFAQAuAAQKfx8AAhYACQmeHzUJAD4DABYACQmeHzUJAD4DAAAA.Letsyoudie:BAAALgADCgMJAwAAAA==.',
Li='Lian:BAAALgAECgUJDAAAAA==.Lichbane:BAABLgAECn8jAAIeAAgJtxxqDgBPAgAeAAgJtxxqDgBPAgAAAA==.Licun:BAAALgAECgYJDQAAAA==.Lifexdeath:BAAALgAECgYJEgAAAA==.Lightcell:BAAALgAECgQJBgAAAA==.Liliara:BAABLgAECn8iAAIJAAgJ8Q6ANgDUAQAJAAgJ8Q6ANgDUAQAAAA==.Lillyirl:BAAALgAECgQJBgAAAA==.Lillymae:BAAALgADCgYJCAAAAA==.Lillyslight:BAAALgADCgYJBgAAAA==.Lillysneak:BAAALgADCgUJCgAAAA==.Lillytae:BAAALgADCgUJBQAAAA==.Lillyzard:BAAALgADCgUJCAAAAA==.Lilmoo:BAAALgAECgYJDQAAAA==.Linkhunter:BAAALgAECgYJBgABLgAECggJIgAdAFYTAA==.Linni:BAAALgAECgYJCgAAAA==.Lizardwizard:BAAALgADCgkJGQAAAA==.',
Lo='Lodise:BAABLgAECn8WAAMHAAYJegvDEQARAQAHAAYJegvDEQARAQAIAAEJ/QcFHQEyAAAAAA==.Lonful:BAAALgADCgEJAQAAAA==.Lorzz:BAABLgAECn8kAAITAAgJ3CJKAQAoAwATAAgJ3CJKAQAoAwAAAA==.Lothe:BAAALgAECgYJCQAAAA==.',
Lu='Lucrio:BAABLgAECn8gAAIeAAgJcwy6LgB/AQAeAAgJcwy6LgB/AQAAAA==.Ludoe:BAAALgADCggJKAAAAA==.Luna:BAAALgAECgQJBAAAAA==.Lunalai:BAABLgAECn8mAAIDAAgJESGDAQCAAgADAAgJESGDAQCAAgAAAA==.',
Ly='Lylineth:BAAALgADCgYJBgAAAA==.Lylinette:BAAALgAECgcJEgAAAA==.Lyssandra:BAAALgADCgUJBQAAAA==.',
['Lí']='Lízandor:BAABLgAECn8XAAIFAAgJuRcuHwDPAQAFAAgJuRcuHwDPAQAAAA==.',
['Lû']='Lûsøn:BAAALgAECgEJAQAAAA==.',
Ma='Madruskee:BAAALgAECgYJEgAAAA==.Magahpt:BAAALgAECgMJBAAAAA==.Mageofdeath:BAAALgAECgIJAgABLgAECgUJBQABAAAAAA==.Magistroll:BAAALgAECgcJEAAAAA==.Malevohaynk:BAAALgAECgQJBAABLgAECgYJFAAPAMsjAA==.Manerva:BAAALgADCggJCAAAAA==.Maniacal:BAAALgADCggJEwAAAA==.Maryshelley:BAAALgADCgMJAwAAAA==.Matoo:BAAALgADCgEJAQAAAA==.Maurin:BAAALgAECgYJBgAAAA==.Maximumhonk:BAAALgAECgQJEAAAAA==.',
Me='Mendelia:BAAALgAECgUJCgAAAA==.Mercus:BAABLgAECn8UAAMjAAgJZRghBgBqAQAjAAYJpBQhBgBqAQAbAAcJvBkuGwD1AAAAAA==.Merkstrasza:BAAALgAECgUJCQAAAA==.Mervenious:BAAALgAECgQJBAAAAA==.Meu:BAAALgAECggJBgAAAA==.',
Mi='Midasdh:BAACLgAFFH8GAAIWAAUJ7gkkJgDGAAAWAAUJ7gkkJgDGAAAuAAQKfxcAAxYACAnFFpM+APoBABYACAnrEpM+APoBABcABgmOF/svAE8BAAAA.Midasdk:BAACLgAFFH8GAAIeAAUJJBaxNwDvAAAeAAUJJBaxNwDvAAAuAAQKfxkAAx4ABwnDHGxPAAQCAB4ABwm9GWxPAAQCABUAAwkiEkAJAMYAAAEuAAUUBQkGABYA7gkA.Midasmonk:BAAALgAECgEJAQABLgAFFAUJBgAWAO4JAA==.Miladepollo:BAAALgADCgMJAwAAAA==.Mindblank:BAAALgAECgQJBAAAAA==.Mindplague:BAABLgAECn8UAAISAAYJix1DDgCiAQASAAYJix1DDgCiAQAAAA==.Minipincin:BAAALgAECgEJAQAAAA==.Minisicwidit:BAAALgADCgMJAwAAAA==.Mistdeeznuts:BAAALgAECgcJBwAAAA==.',
Mo='Mogwaï:BAAALgAECgUJBgAAAA==.Moonde:BAAALgAECgYJCwAAAA==.Moonscale:BAABLgAECn8iAAILAAgJeh0RAQBrAgALAAgJeh0RAQBrAgAAAA==.Moosayer:BAAALgAECgQJBgAAAA==.Mossed:BAAALgADCgMJAwAAAA==.',
Ms='Mskelsier:BAAALgAECgUJBQAAAA==.',
Mt='Mtaur:BAAALgADCggJDwAAAA==.',
Mu='Muclor:BAAALgADCgcJBwABLgAECgYJDQABAAAAAA==.Mustang:BAAALgADCgcJCQAAAA==.',
My='Mythalis:BAAALgAECgQJBQAAAA==.',
['Mä']='Märändus:BAAALgADCgEJAQAAAA==.',
['Må']='Måzikeen:BAAALgADCgMJAwAAAA==.',
Na='Nardena:BAAALgADCggJCQAAAA==.Narse:BAAALgAECgYJBwAAAA==.Narz:BAABLgAECn8eAAIJAAcJZhQnKQBxAQAJAAcJZhQnKQBxAQAAAA==.Nastianna:BAAALgAECgQJBQAAAA==.Nazumi:BAAALgAECgYJEgAAAA==.',
Nd='Ndiz:BAAALgAECgYJEQAAAA==.',
Ne='Necronomikon:BAAALgADCgEJAQAAAA==.Neeva:BAAALgADCgYJCwAAAA==.Nelrya:BAEALgADCgcJDQABLgAECggJKwAFABMgAA==.Neruphuyt:BAABLgAECn8UAAIhAAYJFgqaIwDkAAAhAAYJFgqaIwDkAAAAAA==.',
Ni='Niath:BAAALgADCgcJEQAAAA==.Nightsniper:BAAALgAECgYJEAAAAA==.Ninfassins:BAAALgADCgIJAgAAAA==.',
No='Norintha:BAAALgADCgEJAQAAAA==.Norolen:BAAALgADCgIJAgAAAA==.',
Oa='Oak:BAAALgAECgkJCgAAAA==.',
Oc='Occo:BAAALgADCgEJAQAAAA==.',
Ok='Okioak:BAAALgAECgYJDgAAAA==.',
Ol='Olgon:BAABLgAECn8fAAIJAAgJWRPNFwDUAQAJAAgJWRPNFwDUAQAAAA==.Olstinkyboot:BAAALgAECgEJAQAAAA==.',
On='Onehotdruid:BAAALgAECgcJDwABLgAFFAUJBgAWAO4JAA==.',
Op='Oprhawinfury:BAABLgAECn8cAAIeAAgJJwzjMAB2AQAeAAgJJwzjMAB2AQAAAA==.',
Or='Orgodemir:BAAALgADCgkJDwAAAA==.',
Ot='Otemoto:BAAALgAECgEJAQAAAA==.',
Pa='Paigor:BAAALgAECgIJAgAAAA==.Pakswagger:BAAALgAECgUJDAAAAA==.Pallyberry:BAABLgAECn8fAAIfAAgJ4Bn+CABIAgAfAAgJ4Bn+CABIAgAAAA==.Pancake:BAAALgAECgEJAQAAAA==.Pandemonia:BAABLgAECn8oAAMkAAkJ9wstFgCYAQAkAAgJHgwtFgCYAQAIAAkJSAlpbgCDAQAAAA==.Paprika:BAAALgADCgkJDQAAAA==.Parsie:BAAALgAECgYJBwAAAA==.Pathibas:BAAALgADCgEJAQABLgAECggJKAARAJ8iAA==.Pattycakes:BAABLgAECn8hAAIeAAgJmBYkGwDlAQAeAAgJmBYkGwDlAQAAAA==.',
Pe='Pencil:BAABLgAECn8bAAQIAAgJIR2lDgA1AgAIAAgJIR2lDgA1AgAkAAMJ4gY2XQBXAAAHAAEJAADRLABFAAAAAA==.Pewpewlvltwo:BAABLgAECn8YAAIMAAgJhQxnBgCjAQAMAAgJhQxnBgCjAQAAAA==.Pewthree:BAAALgAECgYJCAABLgAECggJGAAMAIUMAA==.',
Ph='Pherocious:BAAALgAECgQJEQAAAA==.',
Pi='Pintsize:BAAALgADCgIJAgAAAA==.',
Pl='Plaguelis:BAAALgADCgEJAQABLgAECggJJwAMACcZAA==.Plexy:BAAALgAECgcJCgAAAA==.',
Po='Pobble:BAAALgADCgcJBwAAAA==.Pokitz:BAABLgAECn8UAAIFAAYJ8AxwVQAOAQAFAAYJ8AxwVQAOAQAAAA==.Poprock:BAAALgADCgIJAgAAAA==.Potus:BAAALgADCgQJBAAAAA==.',
Pr='Primordinor:BAABLgAECn8WAAMlAAYJWBwbIwD3AQAlAAYJWBwbIwD3AQANAAIJ3w5gTgBmAAAAAA==.Probnotalive:BAABLgAECn8VAAIJAAcJKBXHKwBkAQAJAAcJKBXHKwBkAQAAAA==.Probnotferal:BAAALgADCgIJAgAAAA==.Probnoturmom:BAAALgAECgcJEwAAAA==.',
Ra='Raevyn:BAAALgAECgEJAQAAAA==.Rakan:BAABLgAECn8mAAImAAgJxxUqBwBOAgAmAAgJxxUqBwBOAgAAAA==.Rakasha:BAAALgADCgkJCQAAAA==.Rallick:BAABLgAECn8jAAIfAAgJjBkrBQCcAgAfAAgJjBkrBQCcAgAAAA==.Ranì:BAABLgAECn8jAAIQAAgJYhbzCACjAQAQAAgJYhbzCACjAQAAAA==.Rathger:BAAALgAECggJCgAAAA==.Ravenscythe:BAAALgADCgEJAQAAAA==.Raydor:BAAALgAECgYJBgAAAA==.',
Re='Reb:BAABLgAECn8UAAISAAgJUQMvIAD6AAASAAgJUQMvIAD6AAAAAA==.Redic:BAAALgAECgMJAwAAAA==.Regis:BAAALgAECgYJBgAAAA==.Rellix:BAAALgADCgUJBQAAAA==.Rendkick:BAAALgADCgcJBwAAAA==.Rendwee:BAABLgAECn8bAAInAAgJgh2nAgA9AgAnAAgJgh2nAgA9AgAAAA==.Reuel:BAAALgAECgMJBAAAAA==.Rewolf:BAAALgAECgcJEAAAAA==.',
Rh='Rheemus:BAAALgADCgYJBgAAAA==.Rhul:BAAALgAECgUJBQAAAA==.',
Ri='Ricflairion:BAAALgAECgYJEQAAAA==.Rimuru:BAAALgAECgEJAQABLgAECgMJBQABAAAAAA==.',
Ro='Roadrunner:BAABLgAECn8eAAIJAAgJiQ4yMgDnAQAJAAgJiQ4yMgDnAQAAAA==.Rodcet:BAABLgAECn8qAAIFAAgJKiTgAwDjAgAFAAgJKiTgAwDjAgAAAA==.Roflcopterr:BAABLgAECn8XAAMfAAcJgBUVPQCFAQAfAAcJgBUVPQCFAQAFAAYJVwbkZQDmAAAAAA==.Rognan:BAAALgADCgUJBQAAAA==.Romina:BAAALgADCgEJAwAAAA==.Ronkin:BAAALgADCggJCAAAAA==.Rookgue:BAABLgAECn8cAAIcAAcJchTmBACAAQAcAAcJchTmBACAAQAAAA==.Rookoker:BAAALgAECgUJDAAAAA==.Rootsafarian:BAAALgADCgcJBwAAAA==.Rossa:BAAALgADCgEJAQAAAA==.Rossdair:BAAALgAECgMJAwABLgADCgUJCQABAAAAAA==.Rossperot:BAABLgAECn8SAAIeAAgJBxsmFAAYAgAeAAgJBxsmFAAYAgAAAA==.Rothschild:BAAALgADCgEJAQAAAA==.',
Sa='Sabako:BAAALgADCgcJCAAAAA==.Sacra:BAAALgADCgUJBQABLgAECggJIAAdAM8hAA==.Saelara:BAAALgADCgcJCgAAAA==.Saelis:BAAALgADCgQJBAAAAA==.Sakaru:BAAALgAECgcJEwABLgAECggJIAAOAEsOAA==.Salorin:BAAALgADCgYJCQAAAA==.Samgee:BAACLgAFFH8GAAIFAAMJ/A0WFwD1AAAFAAMJ/A0WFwD1AAAuAAQKfzMAAgUACQmxHm0RAAUDAAUACQmxHm0RAAUDAAAA.Sandormu:BAAALgADCgkJCQAAAA==.Saphas:BAAALgAECgMJAwAAAA==.Saynar:BAABLgAECn8hAAIWAAgJ6yDQBACXAgAWAAgJ6yDQBACXAgAAAA==.',
Sc='Scattered:BAAALgAECgYJEAAAAA==.Scooter:BAAALgAECgUJCgAAAA==.Scyx:BAAALgADCgEJAQAAAA==.',
Se='Seba:BAABLgAECn8fAAICAAgJsRt2EgBHAgACAAgJsRt2EgBHAgAAAA==.Selesne:BAAALgAECgYJCQAAAA==.Seraphicktwo:BAABLgAECn8VAAMTAAUJRxiOIgDrAAATAAQJHxqOIgDrAAASAAUJPw2ZIgDmAAAAAA==.Seriana:BAAALgAECgYJDAAAAA==.Sermidas:BAACLgAFFH8HAAMmAAIJKRjXBwCPAAARAAIJ3AelGwCYAAAmAAIJKRjXBwCPAAAuAAQKfyIAAyYACQk6H7oCAPACACYACQk6H7oCAPACABEABwnOFFg0ANgBAAEuAAUUBQkGABYA7gkA.',
Sh='Shadowcutter:BAAALgADCgkJDgABLgAECgUJBQABAAAAAA==.Shaggmz:BAAALgAECgMJBgAAAA==.Shinakuma:BAAALgAECgUJCQAAAA==.Shinma:BAAALgAECgMJBgAAAA==.Shrubbery:BAABLgAECn8VAAIIAAcJ+gPIVgDtAAAIAAcJ+gPIVgDtAAAAAA==.Shymary:BAAALgAECgMJBgAAAA==.',
Si='Siete:BAAALgAECgEJAQABLgAECgQJCQABAAAAAA==.Silvertip:BAAALgADCggJFQAAAA==.Silëx:BAAALgAECgUJCgAAAA==.Siouxiesioux:BAAALgADCgYJCgAAAA==.Siyona:BAAALgADCgkJDAAAAA==.',
Sk='Skits:BAAALgAECgIJAgAAAA==.Skyrah:BAAALgAECgYJBgAAAA==.Skyrie:BAAALgADCgQJBQAAAA==.',
Sl='Slohine:BAAALgAECgUJBQAAAA==.Sludgecrush:BAAALgAECgYJCwAAAA==.Slugondeez:BAAALgAFFAIJAwAAAA==.',
Sm='Smitefist:BAAALgAECgIJAgAAAA==.Smokiee:BAAALgAECgYJEQAAAA==.',
Sn='Snailtrail:BAABLgAECn8UAAIaAAYJywXSDQC1AAAaAAYJywXSDQC1AAAAAA==.Snark:BAAALgAECgQJBAAAAA==.Snarkkin:BAAALgAECgQJDAAAAA==.Snowkim:BAAALgAECgcJEwAAAA==.Snuzzle:BAABLgAECn8bAAIDAAcJexwRBgCeAQADAAcJexwRBgCeAQAAAA==.',
So='Soniic:BAAALgAECgIJAgAAAA==.Soullessfros:BAABLgAECn8YAAIeAAcJ9AzLOQBTAQAeAAcJ9AzLOQBTAQAAAA==.Soullessman:BAAALgADCgQJCAAAAA==.Sourmash:BAAALgADCgkJCgAAAA==.',
Sp='Spaghet:BAABLgAECn8bAAIlAAgJYhtdCQAHAgAlAAgJYhtdCQAHAgAAAA==.Spillthetea:BAAALgAECgcJEAAAAA==.Sploot:BAAALgAECgcJDQAAAA==.',
Sr='Srasjet:BAAALgAECgYJEAAAAA==.',
Ss='Ssimba:BAAALgAECgYJBgAAAA==.',
St='Stabytha:BAAALgAECgUJCAAAAA==.Stark:BAAALgADCgYJCgAAAA==.Starlight:BAAALgAECgEJAQAAAA==.Stormae:BAAALgADCgMJAgAAAA==.Stormcall:BAAALgAECgQJBQAAAA==.Stratusfied:BAAALgAECgIJAgAAAA==.',
Su='Susbandaid:BAAALgADCgYJBgAAAA==.',
Sw='Swiss:BAAALgAECgYJCQAAAA==.',
Sy='Syllai:BAAALgAECgYJBgAAAA==.Syphus:BAAALgADCgQJBAAAAA==.',
['Sá']='Sáëgárón:BAAALgAECgYJDwAAAA==.',
Ta='Tacyon:BAAALgADCgcJBwAAAA==.Taliden:BAAALgADCgkJJgAAAA==.Tallera:BAAALgADCgEJAgAAAA==.Taniyah:BAAALgAECgIJAgAAAA==.Taraylda:BAABLgAECn8XAAMdAAcJAhoKGgDIAQAdAAcJAhoKGgDIAQASAAIJoQpSMgBwAAAAAA==.Tarful:BAAALgADCgQJBAAAAA==.Tarzand:BAAALgADCgEJAQABLgADCgcJDwABAAAAAA==.Tazo:BAAALgAECgcJDwAAAA==.',
Te='Tearek:BAAALgAECgcJDAAAAA==.Temla:BAABLgAECn8gAAIJAAgJgxSXGADOAQAJAAgJgxSXGADOAQAAAA==.Tenga:BAAALgAECgQJBAAAAA==.Teronfiggy:BAAALgAECgYJEgAAAA==.',
Tf='Tfirs:BAABLgAECn8qAAIDAAgJjBorBwBLAgADAAgJjBorBwBLAgABLgABCgkJCQABAAAAAA==.',
Th='Thartilidan:BAAALgAECgYJEQAAAA==.Theokoles:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.Thepaladin:BAAALgADCgMJAwAAAA==.Thickblòód:BAAALgAECgQJBAAAAA==.',
Ti='Tilythia:BAAALgADCgUJBQAAAA==.',
To='Tona:BAAALgADCgMJAwAAAA==.Toospookie:BAAALgADCgQJAgAAAA==.Tophu:BAAALgADCgcJBwAAAA==.Torkz:BAAALgADCgEJAgAAAA==.',
Tr='Tramplip:BAAALgAECgYJEgAAAA==.Treecloud:BAABLgAECn8jAAIhAAgJ7yI0AwChAgAhAAgJ7yI0AwChAgAAAA==.Trevian:BAAALgAECgYJCQAAAA==.',
Tu='Tub:BAAALgAECgQJBAABLgAFFAQJCQAOAD4KAA==.Tuluxxi:BAABLgAECn8oAAINAAgJHh2yBwBwAgANAAgJHh2yBwBwAgAAAA==.Turborunic:BAAALgADCgkJGwAAAA==.Turiae:BAABLgAECn8fAAQKAAgJpxhiDQC0AQALAAcJ3Ba/EADRAQAKAAcJ7hdiDQC0AQAoAAUJIQmfNADIAAAAAA==.Tuskerz:BAAALgADCgEJAQAAAA==.Tusobrinna:BAAALgAECgUJBgAAAA==.Tutter:BAAALgADCgIJAgAAAA==.',
Tw='Twunk:BAAALgAECgYJDQAAAA==.',
Ty='Typhlotic:BAAALgADCgMJAwAAAA==.Tyrennius:BAAALgAECgQJBAAAAA==.Tyrianis:BAABLgAECn8hAAMbAAgJ9BksBgAXAgAbAAgJPxgsBgAXAgAcAAMJzh6pEwDFAAAAAA==.',
Ug='Uglymancer:BAAALgAECgYJCQAAAA==.',
Uj='Ujimas:BAAALgAECgQJCAAAAA==.',
Un='Unchartedd:BAAALgADCgEJAQAAAA==.',
Va='Vaenira:BAAALgADCgUJBgAAAA==.Valdara:BAAALgADCgkJEgAAAA==.Valemon:BAAALgAECgIJAgAAAA==.Vampireshade:BAABLgAECn8bAAIjAAcJgAX/BQAEAQAjAAcJgAX/BQAEAQAAAA==.Vanimao:BAABLgAECn8hAAQGAAgJqRCsPACxAQAGAAgJqRCsPACxAQADAAQJJg49EQClAAAhAAEJwgbHRgAyAAAAAA==.Vankman:BAAALgADCgcJBwAAAA==.Vannaka:BAAALgADCgEJAQAAAA==.',
Vb='Vbull:BAAALgAECgEJAQAAAA==.',
Ve='Vedrolan:BAAALgADCgUJDgABLgAFFAIJBQAiAOcVAA==.Velifya:BAAALgADCgMJAwAAAA==.Velindon:BAAALgADCgYJBgAAAA==.Velissari:BAAALgAECgIJAgAAAA==.Velonar:BAAALgADCgEJAQAAAA==.Velouria:BAABLgAECn8oAAQhAAgJHSAODQDIAgAhAAgJ2x8ODQDIAgADAAMJWR9gCwAKAQAGAAIJ9QSRwABGAAAAAA==.Venatra:BAAALgAECgEJAQAAAA==.Verudora:BAAALgADCgcJBwAAAA==.Vexira:BAAALgADCgcJBwAAAA==.',
Vi='Violet:BAABLgAECn8gAAIoAAgJIBffAwBJAgAoAAgJIBffAwBJAgAAAA==.Violette:BAAALgAECgYJEgAAAA==.',
Vo='Voidchacha:BAAALgADCgEJAQAAAA==.Voidlink:BAABLgAECn8iAAIdAAgJVhN8CwDTAQAdAAgJVhN8CwDTAQAAAA==.Voidmistress:BAABLgAECn8aAAICAAYJGxVeTABLAQACAAYJGxVeTABLAQAAAA==.Voidpup:BAABLgAECn8bAAIWAAYJNxUSLQAwAQAWAAYJNxUSLQAwAQAAAA==.Volgrimm:BAAALgAECgcJEwAAAA==.Volitaire:BAAALgADCgYJBgAAAA==.',
Vy='Vynethan:BAAALgADCgEJAQAAAA==.',
['Vé']='Véngence:BAAALgAECgMJAwAAAA==.',
['Vê']='Vêx:BAAALgADCgYJBgAAAA==.',
Wa='Wabalabalosh:BAAALgADCgkJCQAAAA==.Wabgucci:BAAALgADCgUJBQAAAA==.Wabwum:BAAALgAECgMJAwAAAA==.Wakaekwondo:BAAALgAECgEJAQAAAA==.Wakarisma:BAAALgAECgEJAQAAAA==.Wangao:BAAALgAFFAEJAgABLgAFFAIJBQAiAOcVAA==.Warbluster:BAAALgADCgIJAgAAAA==.Warchylde:BAAALgADCgkJCQAAAA==.Warolderoy:BAABLgAECn8oAAIRAAgJnyKVAgC4AgARAAgJnyKVAgC4AgAAAA==.',
We='Weedshaman:BAAALgAECgEJAwAAAA==.Weedwax:BAAALgAECgQJBAAAAA==.Weil:BAAALgADCgIJAgAAAA==.',
Wh='Whiinuss:BAABLgAECn8UAAIFAAcJlw24fwB7AQAFAAcJlw24fwB7AQAAAA==.Whytrabbit:BAAALgAECgIJAgAAAA==.',
Wi='Wigglesdeath:BAAALgADCgQJBAAAAA==.',
Wl='Wldeagle:BAAALgAECgQJBAAAAA==.',
Wo='Woker:BAAALgAECgEJAQABLgAECggJJwAMACcZAA==.Woodpig:BAABLgAECn8lAAMGAAgJLSV5AgAqAwAGAAgJLSV5AgAqAwAhAAEJcAN7gwAtAAAAAA==.Woogie:BAAALgAECgQJCwAAAA==.',
Wy='Wyldshade:BAAALgADCgYJCAAAAA==.Wyrm:BAAALgAECgUJBQABLgAECgUJCgABAAAAAA==.',
Xa='Xaladin:BAAALgAECgYJCAAAAA==.',
Xe='Xenna:BAAALgAECgQJBAAAAA==.',
Xi='Xiata:BAAALgADCgkJCQAAAA==.Xiu:BAAALgADCgcJBgAAAA==.',
Ye='Yeoman:BAAALgAECgUJCgAAAA==.',
Yg='Yggdralith:BAAALgAECgcJEgAAAQ==.',
Yo='Yourdeath:BAAALgAECgkJAgAAAA==.',
Yu='Yunosmart:BAAALgAECgMJBAAAAA==.',
Za='Zaen:BAABLgAECn8kAAMIAAgJ7RwGDgA7AgAIAAgJ7RwGDgA7AgAkAAMJ1AutQwCmAAAAAA==.Zagreus:BAAALgADCgcJCAAAAA==.Zarkir:BAAALgAECggJEgABLgAECgYJFQACAKciAA==.Zarkìr:BAABLgAECn8VAAICAAYJpyKNZwAIAgACAAYJpyKNZwAIAgAAAA==.Zaues:BAAALgAECgMJBAAAAA==.',
Ze='Zelily:BAAALgAECgcJDQAAAA==.Zenarri:BAAALgADCgYJBwAAAA==.Zepha:BAAALgAECgYJCwAAAA==.',
Zl='Zlyandien:BAAALgADCggJDwABLgAECgcJFwAdAAIaAA==.',
Zo='Zornov:BAABLgAECn8dAAIiAAgJiB7aAgBKAgAiAAgJiB7aAgBKAgAAAA==.',
Zu='Zulrich:BAAALgADCgYJBgAAAA==.',
Zv='Zvirax:BAAALgADCggJCAAAAA==.',
['Ëu']='Ëuni:BAAALgAECgQJCAAAAA==.',
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
