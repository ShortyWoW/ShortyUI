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

local lookup = {'Unknown-Unknown','Mage-Frost','Druid-Guardian','Monk-Mistweaver','Druid-Restoration','Warlock-Affliction','Warlock-Demonology','Hunter-BeastMastery','Shaman-Enhancement','Shaman-Restoration','Monk-Windwalker','Monk-Brewmaster','Warrior-Protection','Priest-Shadow','Priest-Holy','DeathKnight-Blood','DemonHunter-Devourer','DemonHunter-Havoc','Hunter-Survival','Hunter-Marksmanship','DemonHunter-Vengeance','Warrior-Fury','DeathKnight-Unholy','Rogue-Assassination','Paladin-Holy','Paladin-Retribution','Mage-Arcane','Druid-Balance','Priest-Discipline','Paladin-Protection','Warrior-Arms','Evoker-Devastation','Warlock-Destruction','Druid-Feral','Evoker-Preservation','Rogue-Subtlety','Rogue-Outlaw',}
local provider = {region='US',realm='Bloodhoof',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abarlton:BAAALgAECgYJCQABLgAECgUJBQABAAAAAA==.',
Ad='Adabeam:BAAALgADCgcJCwAAAA==.Adagio:BAABLgAECn8gAAICAAgJdBrlDQDaAQACAAgJdBrlDQDaAQAAAA==.Adetalo:BAABLgAECn8VAAIDAAcJehrFCwDRAQADAAcJehrFCwDRAQAAAA==.Adiara:BAAALgAECgMJAwAAAA==.Aditu:BAAALgAECgMJBQAAAA==.',
Ae='Aelis:BAAALgADCgcJCAAAAA==.Aemulo:BAAALgAECgUJBgAAAA==.Aerith:BAAALgADCgcJBwAAAA==.',
Ag='Agasonex:BAAALgADCgMJAwAAAA==.',
Ai='Airent:BAAALgAECgEJAQAAAA==.Aiyana:BAAALgAECgYJDgAAAA==.',
Ak='Akiirii:BAAALgADCgMJAwAAAA==.',
Al='Alaestel:BAAALgAECgQJBwAAAA==.Alkaraho:BAAALgAECgMJAwAAAA==.Alleyways:BAABLgAECn8WAAIEAAgJOCGjBwDeAgAEAAgJOCGjBwDeAgAAAA==.Alzey:BAAALgAECgYJDgAAAA==.',
Am='Ambeon:BAAALgADCgUJBQAAAA==.Amplers:BAAALgADCgUJBwAAAA==.',
An='Angelbane:BAAALgADCgQJBAAAAA==.Angina:BAAALgADCgQJBwAAAA==.Annarcis:BAAALgADCgcJGQAAAA==.Anthiell:BAAALgADCgEJAQAAAA==.Antiman:BAAALgAECgQJCwAAAA==.',
Ap='Aplcyder:BAABLgAECn8eAAIFAAgJiAzoEgA0AQAFAAgJiAzoEgA0AQAAAA==.',
Ar='Arachnid:BAABLgAECn8gAAICAAcJkCL5DgDNAQACAAcJkCL5DgDNAQAAAA==.Aragorn:BAAALgADCgMJAwAAAA==.Aratyn:BAAALgAECgUJBQAAAA==.',
At='Ati:BAAALgADCgIJAgAAAA==.',
Au='Audxo:BAAALgADCgMJAwAAAA==.',
Ay='Ayayron:BAAALgADCgQJBAAAAA==.',
Ba='Backhawk:BAAALgADCgcJEAAAAA==.Baerrn:BAAALgAECgMJBQAAAA==.Bamboo:BAAALgAECgYJCQAAAA==.Baricia:BAAALgAECgcJEAAAAA==.Barix:BAAALgAECgEJAQAAAA==.Barnd:BAAALgADCggJDwAAAA==.Barrin:BAABLgAECn8WAAIGAAYJJRs5BwDhAQAGAAYJJRs5BwDhAQAAAA==.Bastim:BAAALgADCggJGAAAAA==.Baussassbich:BAAALgADCgYJBgABLgAECgYJGgAHAAMkAA==.Bawnchu:BAAALgADCggJGAAAAA==.',
Be='Beastmaster:BAABLgAECn8bAAIIAAgJCyKXAwBSAgAIAAgJCyKXAwBSAgAAAA==.Becket:BAAALgADCgIJAwABLgAECgIJAgABAAAAAA==.Beefcakell:BAAALgADCgcJDQAAAA==.Beiki:BAAALgAECgMJBgAAAA==.Belthar:BAAALgAECgQJCQAAAA==.Bently:BAAALgAECgYJEAAAAA==.Berexis:BAAALgAECgYJBwAAAA==.',
Bi='Bissafiyah:BAACLgAFFH8PAAIJAAUJfiM7AACMAQAJAAUJfiM7AACMAQAuAAQKfzsAAgkACQlpJQUAAH8DAAkACQlpJQUAAH8DAAAA.Biznasty:BAAALgADCgUJBQAAAA==.',
Bl='Bloodgon:BAAALgAECgQJCgAAAA==.Bluetuesday:BAAALgADCggJDwAAAA==.',
Bo='Bohica:BAABLgAECn8eAAIKAAgJ7A5aDQBoAQAKAAgJ7A5aDQBoAQAAAA==.Bonechop:BAAALgADCgYJBgAAAA==.Bootymeat:BAAALgADCgEJAQAAAA==.Bowtox:BAAALgAECgEJAQAAAA==.Boyakasha:BAAALgAECgEJAQAAAA==.',
Br='Brewfu:BAAALgADCgIJAgAAAA==.Brewpub:BAAALgADCgQJBAAAAA==.Brewsome:BAABLgAECn8eAAMLAAgJIRn2BgBuAQAMAAgJChi7HAAdAgALAAYJMhj2BgBuAQAAAA==.Bruceprime:BAAALgAECgcJAQAAAA==.Bryycelest:BAABLgAECn8UAAIMAAYJZR0iHwAIAgAMAAYJZR0iHwAIAgAAAA==.Brådòn:BAAALgAECgYJCwAAAA==.',
Bu='Bucket:BAABLgAECn8bAAINAAgJmBFoBQBdAQANAAgJmBFoBQBdAQAAAA==.Bunkiee:BAAALgADCgkJGAAAAA==.Bunnybane:BAAALgAECgQJCQAAAA==.Burny:BAABLgAECn8YAAICAAcJ6CRFJgDZAgACAAcJ6CRFJgDZAgAAAA==.Buttadogg:BAAALgAECgUJCAAAAA==.',
['Bè']='Bèth:BAAALgADCgYJCAAAAA==.',
['Bë']='Bëckey:BAAALgADCgIJAgAAAA==.',
Ca='Calyx:BAAALgAECgEJAQAAAA==.Canadani:BAAALgAECgcJDQAAAA==.Candorite:BAAALgAECgUJBQAAAA==.Caphriel:BAAALgAECggJDQAAAA==.Capita:BAAALgAECgYJCwAAAA==.Carsinegan:BAAALgADCgMJBgAAAA==.Cassica:BAABLgAECn8bAAMOAAYJyxhRJwCdAQAOAAYJyxhRJwCdAQAPAAIJ2gleGgBZAAAAAA==.Catskin:BAAALgAECgQJCwAAAA==.',
Ce='Celivalasha:BAAALgADCgUJBQAAAA==.Cell:BAABLgAECn8eAAIMAAgJSyQqBQA3AwAMAAgJSyQqBQA3AwAAAA==.Cet:BAAALgADCgUJBQAAAA==.',
Ch='Chadvader:BAAALgADCgIJAgAAAA==.Chanpagne:BAAALgADCgUJBQAAAA==.Charkle:BAAALgAECgEJAQAAAA==.Chayea:BAAALgADCgEJAQAAAA==.Chillylilly:BAABLgAECn8bAAIQAAgJwCRrAADSAgAQAAgJwCRrAADSAgAAAA==.Chlorophyll:BAAALgAECgQJBAAAAA==.Chocola:BAAALgADCgEJAQAAAA==.Chummie:BAABLgAECn8YAAMGAAcJmBxFCADHAQAGAAYJnBlFCADHAQAHAAYJwBnHEQCCAQAAAA==.',
Ci='Cielcin:BAAALgAECgUJCwAAAA==.Ciremiih:BAAALgAECgEJAQAAAA==.Citymage:BAABLgAECn8VAAICAAgJqxYmXAAmAgACAAgJqxYmXAAmAgAAAA==.Cixelsyd:BAAALgADCgYJBwAAAA==.',
Cl='Clamchowda:BAABLgAECn8bAAMRAAgJYxrTDACtAQARAAgJ0hDTDACtAQASAAUJUh5lIwCiAQAAAA==.',
Co='Codê:BAAALgAECgQJCwAAAA==.Coffeecup:BAAALgADCgIJAgAAAA==.Corride:BAABLgAECn8XAAITAAYJaSLPCQBAAgATAAYJaSLPCQBAAgAAAA==.',
Cr='Crazyeyes:BAAALgADCgMJAwAAAA==.Crimsondeath:BAAALgAECgEJAQAAAA==.Crutch:BAAALgAECgYJDAAAAA==.',
Cu='Cuckenjoyer:BAAALgAECgYJCQAAAA==.',
Cy='Cyprus:BAAALgAECgEJAQAAAA==.',
Da='Daddytrump:BAAALgAECgUJBQAAAA==.Daelric:BAAALgADCgIJAwAAAA==.Daender:BAABLgAECn8bAAMIAAgJsyEJBABFAgAIAAgJsyEJBABFAgAUAAEJmw5TiAAzAAAAAA==.Daenor:BAAALgAECgEJAgAAAA==.Dairydemon:BAABLgAECn8cAAIVAAgJxgw9BAAWAQAVAAgJxgw9BAAWAQAAAA==.Damageus:BAABLgAECn8UAAICAAcJ9CM3JADiAgACAAcJ9CM3JADiAgAAAA==.Daniryl:BAEALgAECgYJDAAAAA==.Darcness:BAAALgAECgUJDgAAAA==.Darcside:BAAALgAECgEJAQAAAA==.Darkclouds:BAAALgADCgIJAgAAAA==.Darksoul:BAAALgAECgUJCgABLgAECgYJEQABAAAAAA==.Darkxwraith:BAAALgAECgIJAgAAAA==.Dashtoolite:BAAALgAECgYJBwAAAA==.Datsumbeech:BAAALgAECgYJCgAAAA==.',
De='Deajer:BAAALgADCgYJBwAAAA==.Deathsabeach:BAAALgAECgEJAQAAAA==.Deathvìxen:BAAALgAECgMJBQAAAA==.Debit:BAAALgAECgYJDAAAAA==.Demonhunter:BAACLgAFFH8FAAIRAAIJmyMEIADWAAARAAIJmyMEIADWAAAuAAQKfx0AAhEACAk/JKsKAC4DABEACAk/JKsKAC4DAAAA.Demonwoogie:BAAALgADCgYJBgABLgAECgQJBwABAAAAAA==.Dendrophilia:BAAALgADCgIJAgAAAA==.Densamin:BAAALgAECgQJCwAAAA==.Deviyn:BAAALgADCgIJAgAAAA==.Devra:BAAALgADCggJCAAAAA==.Deàdly:BAAALgAECgIJAgAAAA==.',
Di='Dietchrist:BAAALgAECgcJEgAAAA==.Dilligaf:BAAALgADCggJCAAAAA==.',
Dk='Dkanabiss:BAAALgAECgEJAQAAAA==.',
Do='Doist:BAAALgAECgEJAQABLgAECgUJDgABAAAAAA==.Donngaz:BAAALgADCgEJAQAAAA==.',
Dr='Drewnei:BAAALgADCgkJCQAAAA==.Drewserk:BAABLgAECn8bAAIWAAgJwRWeBQDSAQAWAAgJwRWeBQDSAQAAAA==.Drkxmaniac:BAAALgAECgIJAgABLgAECgUJBQABAAAAAA==.Drpiscisphd:BAABLgAECn8sAAMXAAkJtiDtDgAkAwAXAAkJtiDtDgAkAwAQAAcJwwWCKQDzAAABLgAFFAEJAQABAAAAAA==.Drsaltyballz:BAABLgAECn8YAAIYAAgJOhm8AAAgAgAYAAgJOhm8AAAgAgAAAA==.Drugpala:BAAALgAECgIJAgAAAA==.Druji:BAAALgADCgIJAgAAAA==.Drumuss:BAAALgADCgEJAQAAAA==.',
Du='Dudesk:BAAALgAECgQJBAAAAA==.Duffuna:BAAALgADCgEJAQABLgAECggJIAATADUlAA==.Duffunha:BAABLgAECn8gAAITAAgJNSVwAAC4AgATAAgJNSVwAAC4AgAAAA==.',
Dy='Dye:BAABLgAECn8ZAAIZAAgJORtMAwBRAgAZAAgJORtMAwBRAgAAAA==.Dyre:BAAALgAECgQJCwAAAA==.Dyslexic:BAAALgAECgQJCwAAAA==.Dyspepsia:BAACLgAFFH8GAAIaAAQJ4gMJEQAdAQAaAAQJ4gMJEQAdAQAuAAQKfxYAAhoACQnjFBI2AEoCABoACQnjFBI2AEoCAAAA.',
['Dô']='Dôngus:BAAALgADCgMJAwABLgAECgIJAgABAAAAAA==.',
['Dõ']='Dõngus:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.',
['Dö']='Döngus:BAAALgADCgEJAQABLgAECgIJAgABAAAAAA==.',
Ed='Edie:BAAALgADCgcJEQAAAA==.',
El='Elenaura:BAAALgAECgMJAwAAAA==.Eleren:BAAALgAECgYJCwAAAA==.Elimee:BAABLgAECn8nAAICAAkJViBEDgBUAwACAAkJViBEDgBUAwAAAA==.Ellasia:BAAALgAECgEJAQAAAA==.Elric:BAABLgAECn8bAAIaAAgJ7hKIEgCOAQAaAAgJ7hKIEgCOAQAAAA==.Elsie:BAAALgAECgQJBgAAAA==.Elunea:BAAALgADCgcJDQAAAA==.Elunemittens:BAAALgADCgYJBgAAAA==.',
Em='Emart:BAAALgAECgQJCAAAAA==.Emozella:BAAALgAECgEJAQAAAA==.',
Ep='Epsilon:BAAALgAECgkJCQAAAA==.',
Er='Erayna:BAABLgAECn8cAAIFAAgJQg/sDgBoAQAFAAgJQg/sDgBoAQAAAA==.Ereillea:BAAALgAECgYJDQAAAA==.',
Es='Essence:BAABLgAECn8WAAMCAAgJmxTwagAAAgACAAgJDBHwagAAAgAbAAQJ1xoXDAARAQAAAA==.',
Eu='Euko:BAABLgAECn8bAAMcAAgJbRkyHQAXAgAcAAYJpSAyHQAXAgAFAAgJchUaFgATAQAAAA==.',
Ev='Evepriest:BAAALgADCgMJAQAAAA==.',
Fa='Failrogue:BAAALgADCgUJBQAAAA==.Falconclaw:BAAALgADCgkJGAAAAA==.Falkensnoman:BAAALgAECgQJCwAAAA==.Fayedra:BAAALgAECgUJBQAAAA==.',
Fc='Fcawfe:BAAALgADCgkJEQABLgAECgIJBQABAAAAAA==.',
Fe='Febee:BAAALgADCgcJAQAAAA==.Feenii:BAABLgAECn8fAAIJAAgJcBc0AgDbAQAJAAgJcBc0AgDbAQAAAA==.Felburst:BAAALgAECgMJAwAAAA==.Felfireqt:BAAALgAECgEJAgAAAA==.',
Fi='Figgyandrii:BAAALgADCgcJBwAAAA==.Fionar:BAAALgADCgIJAgAAAA==.Fizzlelich:BAAALgADCgQJBAAAAA==.',
Fl='Flamesters:BAAALgAECgEJAgAAAA==.Fluffpuff:BAAALgADCgMJAwAAAA==.',
Fo='Foxdeer:BAAALgAECgMJBQAAAA==.',
Ga='Gambachii:BAAALgAECgcJDQAAAA==.Gankss:BAAALgAFFAEJAgAAAA==.Garakddon:BAAALgADCgkJDgABLgAECgYJCQABAAAAAA==.Garryy:BAAALgAECgIJAgAAAA==.',
Ge='Geegandolm:BAAALgADCgkJEwAAAA==.Genjaru:BAAALgADCgYJBgAAAA==.Genndalf:BAAALgADCgcJBwAAAA==.Geostorm:BAAALgAECgEJAQAAAA==.',
Gi='Giramar:BAAALgAECgUJBgAAAA==.',
Go='Gobbyshamm:BAAALgAECgEJAQAAAA==.Gobsmackers:BAAALgADCgUJBQAAAA==.Gomklin:BAAALgADCgcJCAABLgAECggJIgAaAGcjAA==.Goteem:BAAALgAECggJEwAAAA==.',
Gr='Griffhud:BAAALgAECgIJAgAAAA==.Grimrox:BAAALgAECgYJCQAAAA==.Grixx:BAAALgADCgUJBQAAAA==.Groupie:BAAALgADCgUJCgABLgAECgcJGAAUAMgPAA==.',
Gt='Gtatedk:BAAALgAECgEJAQAAAA==.',
Gu='Guntera:BAAALgAECgYJDgAAAA==.Guts:BAAALgADCgMJAwAAAA==.',
Gw='Gwendalyn:BAAALgAECgQJBAAAAA==.',
['Gä']='Gäz:BAAALgADCgEJAQAAAA==.',
Ha='Halexion:BAAALgADCgIJAgAAAA==.Haomaru:BAAALgAECgMJAwAAAA==.Hardcandy:BAABLgAECn8YAAIUAAcJyA8fBQA4AQAUAAcJyA8fBQA4AQAAAA==.Hawkìns:BAAALgAECgEJAQAAAA==.',
He='Heartsoul:BAAALgAECgYJCQAAAA==.Heavyarm:BAAALgADCgcJDwAAAA==.Hellork:BAAALgADCgQJBAAAAA==.Hermosura:BAAALgADCgUJBwAAAA==.Hex:BAAALgAECgUJBQAAAA==.',
Hi='Hiccups:BAAALgAECgMJAwAAAA==.Himawarí:BAAALgAECgUJBQAAAA==.Hiyank:BAAALgAECgYJDgAAAA==.',
Ho='Hoffmin:BAAALgAECgYJEwAAAA==.Holemeister:BAABLgAECn8iAAIaAAgJ4yLeDQAfAwAaAAgJ4yLeDQAfAwAAAA==.Holyfresh:BAAALgADCgEJAQAAAA==.Holymann:BAABLgAECn8UAAIOAAYJ0wtsNQA/AQAOAAYJ0wtsNQA/AQAAAA==.Holyschnikey:BAAALgAECgQJCwAAAA==.Holyz:BAAALgAECgYJCgAAAA==.Hozaki:BAAALgADCgcJCwABLgAECgUJBQABAAAAAA==.',
Hu='Hudfin:BAAALgADCgUJBQAAAA==.Hundred:BAAALgADCgUJBQABLgAECgEJAQABAAAAAA==.',
['Hí']='Hílthaen:BAABLgAECn8UAAIPAAYJNhOQDAAoAQAPAAYJNhOQDAAoAQAAAA==.',
Ic='Icebones:BAAALgADCgcJDAABLgAECgQJCQABAAAAAA==.Icelight:BAAALgAECgQJCQAAAA==.Ichigokisu:BAAALgAECgMJAwAAAA==.',
Il='Illiduji:BAAALgADCgMJAwAAAA==.Illy:BAAALgAECggJCQAAAA==.',
Im='Imposed:BAAALgAECgUJCQAAAA==.',
In='Instantdeath:BAAALgAECgUJBQAAAA==.Invali:BAAALgAECgMJAwAAAA==.',
Ir='Irônhide:BAAALgADCgUJCAAAAA==.',
Iv='Ivranda:BAAALgADCgkJEgABLgAECgUJBQABAAAAAA==.',
Ja='Jaapp:BAAALgAECgMJBgAAAA==.Jahan:BAABLgAECn8dAAMdAAgJ4SAQFAAMAgAdAAgJ4SAQFAAMAgAOAAMJ/xK1EgDOAAAAAA==.Jamie:BAAALgADCgUJBQAAAA==.Jaydine:BAAALgADCgYJBgABLgAECgkJJwACAFYgAA==.',
Je='Jeri:BAAALgADCgcJFAAAAA==.',
Jh='Jhie:BAAALgADCgkJGgAAAA==.',
Ju='Jud:BAAALgAECgYJCAAAAA==.Juxtaposed:BAAALgADCgUJBAAAAA==.',
Ka='Kaerei:BAABLgAECn8aAAIaAAgJPRvVCQDvAQAaAAgJPRvVCQDvAQAAAA==.Kaleb:BAAALgAECgYJDAAAAA==.Kalfalah:BAAALgAECgQJBwAAAA==.Kalirkaz:BAABLgAECn8WAAIFAAcJYRk3LAD+AQAFAAcJYRk3LAD+AQAAAA==.Kallipsa:BAAALgAECgEJAQAAAA==.Karasu:BAAALgAECgIJAgABLgAECggJGAALAGYNAA==.Kathria:BAAALgAECgYJCAAAAA==.',
Ke='Keládry:BAAALgAECgMJAwAAAA==.Keskiyö:BAAALgADCgkJFQABLgAECggJGAALAGYNAA==.',
Kh='Khallock:BAAALgAECgYJEgAAAA==.Khamael:BAAALgAECgEJAQAAAA==.',
Ki='Kiemen:BAAALgAECggJEwAAAA==.Killko:BAAALgAECgUJCwAAAA==.Kinki:BAAALgAECgMJAwABLgAECgcJGAAUAMgPAA==.Kirisen:BAAALgAECgQJBAAAAA==.Kitan:BAAALgAECgQJBQAAAA==.',
Ko='Konno:BAAALgAECgQJBAABLgAFFAUJDwAJAH4jAA==.Kooterr:BAAALgADCgUJBQAAAA==.',
Kr='Kragsloor:BAAALgADCgYJBgAAAA==.Kredorin:BAAALgAECgYJCgAAAA==.Krewella:BAAALgADCgcJBwAAAA==.Krovmar:BAAALgADCgUJBQAAAA==.',
Ks='Kspanxx:BAAALgAECgMJAwAAAA==.',
Kt='Kthanx:BAAALgADCgYJBgAAAA==.',
Ku='Kungpowgazer:BAAALgAECgUJCgAAAA==.Kunls:BAAALgAECgYJCQAAAA==.Kuraki:BAAALgAECgUJBQAAAA==.Kurasa:BAABLgAECn8YAAMLAAgJZg3yCwARAQALAAgJZg3yCwARAQAEAAQJowHIWgBkAAAAAA==.Kutraz:BAAALgAECgQJBQAAAA==.',
La='Ladrar:BAAALgADCgMJBQAAAA==.Laelina:BAAALgADCgcJBgAAAA==.Lanadiel:BAABLgAECn8bAAIeAAgJwRwNAQBOAgAeAAgJwRwNAQBOAgAAAA==.Lazz:BAAALgAECgUJBAAAAA==.',
Le='Legend:BAACLgAFFH8FAAIRAAIJdRyDEQC7AAARAAIJdRyDEQC7AAAuAAQKfyQAAhEACQkfIBwDAHYCABEACQkfIBwDAHYCAAAA.Letsyoudie:BAAALgADCgMJAwAAAA==.',
Li='Lian:BAAALgAECgQJCAAAAA==.Lichbane:BAABLgAECn8bAAIXAAgJVhcWDQC2AQAXAAgJVhcWDQC2AQAAAA==.Licun:BAAALgAECgYJDQAAAA==.Lifexdeath:BAAALgAECgYJDAAAAA==.Lightcell:BAAALgAECgMJAwAAAA==.Liliara:BAABLgAECn8bAAIIAAgJKg2GNgDUAQAIAAgJKg2GNgDUAQAAAA==.Lillyirl:BAAALgAECgQJBAAAAA==.Lillymae:BAAALgADCgYJCAAAAA==.Lillyslight:BAAALgADCgYJBgAAAA==.Lillysneak:BAAALgADCgUJCgAAAA==.Lillytae:BAAALgADCgUJBQAAAA==.Lillyzard:BAAALgADCgUJCAAAAA==.Lilmoo:BAAALgAECgQJCAAAAA==.Linkhunter:BAAALgAECgYJBgABLgAECggJGgAdAHcSAA==.Linni:BAAALgAECgIJBAABLgAECgQJBgABAAAAAA==.Lizardwizard:BAAALgADCgkJGQAAAA==.',
Lo='Lodise:BAAALgAECgYJDgAAAA==.Lonful:BAAALgADCgEJAQAAAA==.Lorzz:BAABLgAECn8dAAIPAAgJFCE4AQCgAgAPAAgJFCE4AQCgAgAAAA==.Lothe:BAAALgAECgUJBQAAAA==.',
Lu='Lucrio:BAABLgAECn8YAAIXAAgJrQoaFwBZAQAXAAgJrQoaFwBZAQAAAA==.Ludoe:BAAALgADCggJKAAAAA==.Luna:BAAALgAECgQJBAAAAA==.Lunalai:BAABLgAECn8eAAIDAAgJmCDAAABmAgADAAgJmCDAAABmAgAAAA==.',
Ly='Lylineth:BAAALgADCgYJBgAAAA==.Lylinette:BAAALgAECgcJEgAAAA==.Lyssandra:BAAALgADCgUJBQAAAA==.',
['Lí']='Lízandor:BAAALgAFFAEJAQAAAA==.',
['Lû']='Lûsøn:BAAALgAECgEJAQAAAA==.',
Ma='Madruskee:BAAALgAECgUJDAAAAA==.Magahpt:BAAALgAECgMJBAAAAA==.Mageofdeath:BAAALgADCgQJBAABLgAECgUJBQABAAAAAA==.Magistroll:BAAALgAECgcJEAAAAA==.Malevohaynk:BAAALgADCgcJBgABLgAECgYJDgABAAAAAA==.Manerva:BAAALgADCgcJCAAAAA==.Maniacal:BAAALgADCgcJEQAAAA==.Matoo:BAAALgADCgEJAQAAAA==.Maurin:BAAALgAECgUJBQAAAA==.Maximumhonk:BAAALgAECgQJCwAAAA==.',
Me='Mendelia:BAAALgAECgMJBQAAAA==.Mercus:BAAALgAECgcJEgAAAA==.Merkstrasza:BAAALgAECgMJBAAAAA==.Mervenious:BAAALgAECgQJBAAAAA==.Meu:BAAALgAECgYJBgAAAA==.',
Mi='Midasdh:BAABLgAECn8XAAMRAAgJKBmTPgD6AQARAAgJThWTPgD6AQASAAYJjhf9LwBPAQABLgAFFAIJBQAfAG4MAA==.Midasdk:BAABLgAECn8WAAIXAAcJvRlwTwAEAgAXAAcJvRlwTwAEAgABLgAFFAIJBQAfAG4MAA==.Midasmonk:BAAALgAECgEJAQABLgAFFAIJBQAfAG4MAA==.Miladepollo:BAAALgADCgMJAwAAAA==.Mindblank:BAAALgAECgQJBAAAAA==.Mindplague:BAAALgAECgUJDgAAAA==.Minisicwidit:BAAALgADCgMJAwAAAA==.Mistdeeznuts:BAAALgAECgYJBgAAAA==.',
Mo='Mogwaï:BAAALgAECgUJBgAAAA==.Moonde:BAAALgAECgQJCQAAAA==.Moonscale:BAABLgAECn8aAAIgAAgJxBuRAAAwAgAgAAgJxBuRAAAwAgAAAA==.Moosayer:BAAALgAECgQJBgAAAA==.Mossed:BAAALgADCgMJAwAAAA==.',
Ms='Mskelsier:BAAALgAECgUJBQAAAA==.',
Mt='Mtaur:BAAALgADCggJDwAAAA==.',
Mu='Muclor:BAAALgADCgcJBwABLgAECgUJCwABAAAAAA==.Mustang:BAAALgADCgcJCQAAAA==.',
My='Mythalis:BAAALgAECgQJBAAAAA==.',
['Mä']='Märändus:BAAALgADCgEJAQAAAA==.',
['Må']='Måzikeen:BAAALgADCgMJAwAAAA==.',
Na='Nardena:BAAALgADCgcJCQAAAA==.Narse:BAAALgAECgYJBwAAAA==.Narz:BAAALgAECgYJEwAAAA==.Nastianna:BAAALgAECgMJBAAAAA==.Nazumi:BAAALgAECgQJCwAAAA==.',
Nd='Ndiz:BAAALgAECgYJEQAAAA==.',
Ne='Necronomikon:BAAALgADCgEJAQAAAA==.Neeva:BAAALgADCgYJCwAAAA==.Negasi:BAAALgADCgUJBQAAAA==.Nelrya:BAAALgADCgcJDQABLgAECggJIwAaAEUbAA==.Neruphuyt:BAABLgAECn8UAAIcAAYJFgoOEADzAAAcAAYJFgoOEADzAAAAAA==.',
Ni='Niath:BAAALgADCgcJEQAAAA==.Nightsniper:BAAALgAECgYJCwAAAA==.Ninfassins:BAAALgADCgIJAgAAAA==.',
No='Norintha:BAAALgADCgEJAQAAAA==.Norolen:BAAALgADCgIJAgAAAA==.',
Oa='Oak:BAAALgADCgYJCgABLgAECgIJAgABAAAAAA==.',
Oc='Occo:BAAALgADCgEJAQAAAA==.',
Ok='Okioak:BAAALgAECgYJDgAAAA==.',
Ol='Olgon:BAABLgAECn8YAAIIAAgJlQ+vEQBvAQAIAAgJlQ+vEQBvAQAAAA==.Olstinkyboot:BAAALgAECgEJAQAAAA==.',
On='Onehotdruid:BAAALgAECgcJDwABLgAFFAIJBQAfAG4MAA==.',
Op='Oprhawinfury:BAABLgAECn8UAAIXAAYJJg5mIgASAQAXAAYJJg5mIgASAQAAAA==.',
Or='Orgodemir:BAAALgADCgkJDwAAAA==.',
Ot='Otemoto:BAAALgAECgEJAQAAAA==.',
Pa='Paigor:BAAALgADCggJGAAAAA==.Pakswagger:BAAALgAECgMJBgAAAA==.Pallyberry:BAABLgAECn8XAAIZAAgJjxmSAwBIAgAZAAgJjxmSAwBIAgAAAA==.Pancake:BAAALgAECgEJAQAAAA==.Pandemonia:BAABLgAECn8oAAMhAAkJ9wstFgCYAQAhAAgJHgwtFgCYAQAHAAkJSAlhbgCDAQAAAA==.Paprika:BAAALgADCgkJDQAAAA==.Parselizard:BAAALgAECgUJCQAAAA==.Parsie:BAAALgAECgEJAQAAAA==.Pathibas:BAAALgADCgEJAQABLgAECggJIAAWAO4fAA==.Pattycakes:BAABLgAECn8ZAAIXAAgJbxMGFwBZAQAXAAgJbxMGFwBZAQAAAA==.',
Pe='Pencil:BAABLgAECn8WAAQHAAgJuxW1QAALAgAHAAgJuxW1QAALAgAhAAIJ4gYtXQBXAAAGAAEJAADPLABFAAAAAA==.Pewpewlvltwo:BAAALgAECggJEQAAAA==.Pewthree:BAAALgAECgYJCAABLgAECggJEQABAAAAAA==.',
Ph='Pherocious:BAAALgAECgQJCgAAAA==.',
Pi='Pintsize:BAAALgADCgEJAQAAAA==.',
Pl='Plaguelis:BAAALgADCgEJAQABLgAECggJHwAJAHAXAA==.Plexy:BAAALgAECgcJCgAAAA==.',
Po='Pobble:BAAALgADCgcJBwAAAA==.Pokitz:BAAALgAECgYJDgAAAA==.Poprock:BAAALgADCgIJAgAAAA==.Potus:BAAALgADCgQJBAAAAA==.',
Pr='Primordinor:BAAALgAECgYJDgAAAA==.Probnotalive:BAAALgAECgYJDgAAAA==.Probnoturmom:BAAALgAECgcJEwAAAA==.',
Ra='Raevyn:BAAALgAECgEJAQAAAA==.Rakan:BAABLgAECn8eAAIfAAgJOxXmAQDeAQAfAAgJOxXmAQDeAQAAAA==.Rakasha:BAAALgADCgkJCQAAAA==.Rallick:BAABLgAECn8cAAIZAAgJDBVhBQAKAgAZAAgJDBVhBQAKAgAAAA==.Ranì:BAABLgAECn8bAAINAAgJuhQwBQBmAQANAAgJuhQwBQBmAQAAAA==.Rathger:BAAALgAECgIJAgAAAA==.Ravenscythe:BAAALgADCgEJAQAAAA==.',
Re='Reb:BAAALgAECgcJDAAAAA==.Redic:BAAALgAECgMJAwAAAA==.Regis:BAAALgAECgYJBgABLgAECgcJGQAEADIXAA==.Rellix:BAAALgADCgUJBQAAAA==.Rendkick:BAAALgADCgcJBwAAAA==.Rendwee:BAABLgAECn8bAAIiAAgJgh3nAAA9AgAiAAgJgh3nAAA9AgAAAA==.Reuel:BAAALgAECgMJBAAAAA==.Rewolf:BAAALgAECgUJCgAAAA==.',
Rh='Rheemus:BAAALgADCgYJBgAAAA==.Rhul:BAAALgADCgkJDQAAAA==.',
Ri='Rimuru:BAAALgADCgEJAQABLgAECgIJAgABAAAAAA==.',
Ro='Roadrunner:BAABLgAECn8aAAIIAAgJ4w03MgDnAQAIAAgJ4w03MgDnAQAAAA==.Rodcet:BAABLgAECn8iAAIaAAgJZyPyAQCuAgAaAAgJZyPyAQCuAgAAAA==.Roflcopterr:BAAALgAECgYJEAAAAA==.Rognan:BAAALgADCgUJBQAAAA==.Romina:BAAALgADCgEJAgAAAA==.Ronkin:BAAALgADCgcJCAAAAA==.Rookgue:BAABLgAECn8VAAIYAAYJlBOIAwA3AQAYAAYJlBOIAwA3AQAAAA==.Rookoker:BAAALgAECgUJDAAAAA==.Rootsafarian:BAAALgADCgcJBwAAAA==.Rossa:BAAALgADCgEJAQAAAA==.Rossdair:BAAALgAECgMJAwABLgADCgUJCQABAAAAAA==.Rossperot:BAAALgAECggJDQAAAA==.Rothschild:BAAALgADCgEJAQAAAA==.',
Sa='Sabako:BAAALgADCgcJCAAAAA==.Sacra:BAAALgADCgUJBQABLgAECggJHQAdAOEgAA==.Saelara:BAAALgADCgcJCgAAAA==.Saelis:BAAALgADCgQJBAAAAA==.Sakaru:BAAALgAECgYJDAABLgAECggJGAALAGYNAA==.Samgee:BAACLgAFFH8FAAIaAAMJ/A0UFwD1AAAaAAMJ/A0UFwD1AAAuAAQKfzEAAhoACQmQHmYRAAYDABoACQmQHmYRAAYDAAAA.Sandormu:BAAALgADCgkJCQAAAA==.Saphas:BAAALgADCgMJBgAAAA==.Saynar:BAABLgAECn8gAAIRAAgJcyAGAwB5AgARAAgJcyAGAwB5AgAAAA==.',
Sc='Scattered:BAAALgAECgYJCwAAAA==.Scooter:BAAALgAECgUJCgAAAA==.Scyx:BAAALgADCgEJAQAAAA==.',
Se='Seba:BAABLgAECn8YAAICAAgJ4xUsEQC5AQACAAgJ4xUsEQC5AQAAAA==.Sefastet:BAAALgAECgEJAwAAAA==.Selesne:BAAALgAECgUJBQAAAA==.Seraphicktwo:BAAALgAECgQJDQAAAA==.Seriana:BAAALgAECgYJBwAAAA==.Sermidas:BAACLgAFFH8FAAMfAAIJbgzTBwCPAAAWAAIJ3AepGwCYAAAfAAIJ9gjTBwCPAAAuAAQKfxsAAx8ACQnzHLkCAPACAB8ACQlkHLkCAPACABYABwnOFFk0ANgBAAAA.',
Sh='Shadowcutter:BAAALgADCgkJDgABLgAECgUJBQABAAAAAA==.Shaggmz:BAAALgAECgEJAQAAAA==.Shinakuma:BAAALgAECgMJAwAAAA==.Shinma:BAAALgAECgEJAQAAAA==.Shrubbery:BAAALgAECgcJDgAAAA==.Shymary:BAAALgAECgEJAQAAAA==.',
Si='Siete:BAAALgAECgEJAQABLgAECgQJCQABAAAAAA==.Silvertip:BAAALgADCggJFQAAAA==.Silëx:BAAALgAECgMJBQAAAA==.Siouxiesioux:BAAALgADCgYJCgAAAA==.Siyona:BAAALgADCgYJBgAAAA==.',
Sk='Skits:BAAALgAECgIJAgAAAA==.Skyrah:BAAALgAECgYJBgAAAA==.Skyrie:BAAALgADCgIJAgAAAA==.',
Sl='Slohine:BAAALgAECgUJBQAAAA==.Sludgecrush:BAAALgAECgYJCwAAAA==.Slugondeez:BAAALgAFFAEJAQAAAA==.',
Sm='Smitefist:BAAALgAECgIJAgAAAA==.Smokiee:BAAALgAECgQJCgAAAA==.',
Sn='Snailtrail:BAAALgAECgYJDAAAAA==.Snarkkin:BAAALgAECgQJCwAAAA==.Snowkim:BAAALgAECgYJDAAAAA==.Snuzzle:BAABLgAECn8UAAIDAAYJIB1bDADEAQADAAYJIB1bDADEAQAAAA==.',
So='Soniic:BAAALgAECgIJAgAAAA==.Soullessfros:BAAALgAECgYJEgAAAA==.Soullessman:BAAALgADCgQJBAAAAA==.Sourmash:BAAALgADCgkJCgAAAA==.',
Sp='Spaghet:BAAALgAECgcJEwAAAA==.Spillthetea:BAAALgAECgUJCgAAAA==.',
Sr='Srasjet:BAAALgAECgQJCQAAAA==.',
Ss='Ssimba:BAAALgADCgkJDwAAAA==.',
St='Stabytha:BAAALgAECgMJAwAAAA==.Stark:BAAALgADCgYJCgAAAA==.Stormae:BAAALgADCgMJAgAAAA==.Stormcall:BAAALgAECgEJAQAAAA==.Stratusfied:BAAALgADCggJGAAAAA==.',
Su='Susbandaid:BAAALgADCgYJBgAAAA==.',
Sw='Swiss:BAAALgAECgUJBQAAAA==.',
Sy='Syllai:BAAALgAECgYJBgAAAA==.Syphus:BAAALgADCgQJBAAAAA==.',
['Sá']='Sáëgárón:BAAALgAECgQJCAAAAA==.',
Ta='Tacyon:BAAALgADCgcJBwAAAA==.Taliden:BAAALgADCgkJHQAAAA==.Tallera:BAAALgADCgEJAgAAAA==.Taniyah:BAAALgAECgIJAgAAAA==.Taraylda:BAAALgAECgYJEQAAAA==.Tarful:BAAALgADCgQJBAAAAA==.Tarzand:BAAALgADCgEJAQABLgADCgcJDwABAAAAAA==.Tazo:BAAALgAECgYJCAAAAA==.',
Te='Tearek:BAAALgAECgEJAQAAAA==.Temla:BAABLgAECn8bAAIIAAgJkRNgCgDDAQAIAAgJkRNgCgDDAQAAAA==.Tenga:BAAALgAECgQJBAAAAA==.Teronfiggy:BAAALgAECgYJDAAAAA==.',
Tf='Tfirs:BAABLgAECn8iAAIDAAgJnhkqBwBLAgADAAgJnhkqBwBLAgAAAA==.',
Th='Thartilidan:BAAALgAECgYJCQAAAA==.Theokoles:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.Thepaladin:BAAALgADCgMJAwAAAA==.',
To='Tona:BAAALgADCgMJAwAAAA==.Toospookie:BAAALgADCgQJAgAAAA==.Tophu:BAAALgADCgcJBwAAAA==.Torkz:BAAALgADCgEJAQAAAA==.',
Tr='Tramplip:BAAALgAECgUJDAAAAA==.Treecloud:BAABLgAECn8bAAIcAAgJ7yL5AACcAgAcAAgJ7yL5AACcAgAAAA==.Trevian:BAAALgAECgUJBQAAAA==.',
Tu='Tub:BAAALgAECgQJBAABLgAFFAMJBQAMAGcMAA==.Tuluxxi:BAABLgAECn8gAAIKAAgJ2hlQBgD0AQAKAAgJ2hlQBgD0AQAAAA==.Turborunic:BAAALgADCgkJGwAAAA==.Turiae:BAABLgAECn8WAAMgAAgJVxi+EADRAQAgAAcJ3Ba+EADRAQAjAAQJHAeiNADIAAAAAA==.Tusobrinna:BAAALgAECgUJBQAAAA==.Tutter:BAAALgADCgIJAgAAAA==.',
Tw='Twunk:BAAALgAECgYJDQAAAA==.',
Ty='Typhlotic:BAAALgADCgMJAwAAAA==.Tyrianis:BAABLgAECn8ZAAMkAAYJ6BxDBgCIAQAkAAYJKBpDBgCIAQAYAAMJzh6pEwDFAAAAAA==.',
Ug='Uglymancer:BAAALgAECgUJBQAAAA==.',
Uj='Ujimas:BAAALgAECgMJBQAAAA==.',
Va='Vaenira:BAAALgADCgUJBgAAAA==.Valdara:BAAALgADCgkJEgAAAA==.Valemon:BAAALgAECgEJAQAAAA==.Vampireshade:BAABLgAECn8UAAIlAAYJOgXSAgDnAAAlAAYJOgXSAgDnAAAAAA==.Vanimao:BAABLgAECn8bAAMFAAgJqRCoPACxAQAFAAgJqRCoPACxAQAcAAEJwgYFJAAuAAAAAA==.Vankman:BAAALgADCgcJBwAAAA==.Vannaka:BAAALgADCgEJAQAAAA==.',
Vb='Vbull:BAAALgAECgEJAQAAAA==.',
Ve='Vedrolan:BAAALgADCgUJDgAAAA==.Velifya:BAAALgADCgMJAwAAAA==.Velindon:BAAALgADCgYJBgAAAA==.Velissari:BAAALgADCgkJHwAAAA==.Velonar:BAAALgADCgEJAQAAAA==.Velouria:BAABLgAECn8gAAQcAAgJjB8ODQDIAgAcAAgJjB8ODQDIAgADAAIJdxdaCQCLAAAFAAIJ9QSNwABGAAAAAA==.Venatra:BAAALgAECgEJAQAAAA==.Verudora:BAAALgADCgcJBwAAAA==.Vexira:BAAALgADCgcJBwAAAA==.',
Vi='Violet:BAABLgAECn8YAAIjAAYJgBqiAgDjAQAjAAYJgBqiAgDjAQAAAA==.Violette:BAAALgAECgQJDQAAAA==.',
Vo='Voidchacha:BAAALgADCgEJAQAAAA==.Voidlink:BAABLgAECn8aAAIdAAgJdxK2BQCsAQAdAAgJdxK2BQCsAQAAAA==.Voidmistress:BAAALgAECgYJEwAAAA==.Voidpup:BAABLgAECn8UAAIRAAYJkQzZgQAlAQARAAYJkQzZgQAlAQAAAA==.Volgrimm:BAAALgAECgYJDAAAAA==.Volitaire:BAAALgADCgYJBgAAAA==.',
Vy='Vynethan:BAAALgADCgEJAQAAAA==.',
Wa='Wabalabalosh:BAAALgADCgkJCQAAAA==.Wabgucci:BAAALgADCgUJBQAAAA==.Wabwum:BAAALgAECgMJAwAAAA==.Wakaekwondo:BAAALgAECgEJAQAAAA==.Wakarisma:BAAALgAECgEJAQAAAA==.Wangao:BAAALgAFFAEJAQAAAA==.Warbluster:BAAALgADCgIJAgAAAA==.Warchylde:BAAALgADCgkJCQAAAA==.Warolderoy:BAABLgAECn8gAAIWAAgJ7h/CAQBfAgAWAAgJ7h/CAQBfAgAAAA==.',
We='Weedshaman:BAAALgAECgEJAwAAAA==.Weedwax:BAAALgADCgUJBQAAAA==.Weil:BAAALgADCgIJAgAAAA==.',
Wh='Whiinuss:BAABLgAECn8UAAIaAAcJlw25fwB7AQAaAAcJlw25fwB7AQAAAA==.Whytrabbit:BAAALgAECgIJAgAAAA==.',
Wi='Wigglesdeath:BAAALgADCgQJBAAAAA==.',
Wl='Wldeagle:BAAALgAECgQJBAAAAA==.',
Wo='Woker:BAAALgADCgEJAgABLgAECggJHwAJAHAXAA==.Woodpig:BAABLgAECn8dAAMFAAcJSyXnAgCCAgAFAAcJSyXnAgCCAgAcAAEJcANtgwAtAAAAAA==.Woogie:BAAALgAECgQJBwAAAA==.',
Wy='Wyldshade:BAAALgADCgYJCAAAAA==.Wyrm:BAAALgAECgUJBQABLgAECgUJCgABAAAAAA==.',
Xa='Xaladin:BAAALgAECgQJBAAAAA==.',
Xe='Xenna:BAAALgAECgQJBAAAAA==.',
Xi='Xiu:BAAALgADCgIJAQAAAA==.',
Ye='Yeoman:BAAALgAECgMJBQAAAA==.',
Yg='Yggdralith:BAAALgAECgcJDAAAAQ==.',
Yo='Yourdeath:BAAALgAECgkJAgAAAA==.',
Yu='Yunosmart:BAAALgAECgIJAgAAAA==.',
Za='Zaen:BAABLgAECn8dAAMHAAgJkhpVDAC1AQAHAAgJkhpVDAC1AQAhAAMJ1AurQwCmAAAAAA==.Zagreus:BAAALgADCgcJCAAAAA==.Zarkir:BAAALgAECggJCwABLgAECgYJFAACAKciAA==.Zarkìr:BAABLgAECn8UAAICAAYJpyKPZwAIAgACAAYJpyKPZwAIAgAAAA==.Zaues:BAAALgAECgMJBAAAAA==.',
Ze='Zelily:BAAALgAECgYJDAAAAA==.Zenarri:BAAALgADCgYJBwAAAA==.Zepha:BAAALgAECgUJBgAAAA==.',
Zl='Zlyandien:BAAALgADCggJDwABLgAECgYJEQABAAAAAA==.',
Zo='Zornov:BAABLgAECn8VAAIeAAcJdh/QAgC7AQAeAAcJdh/QAgC7AQAAAA==.',
Zu='Zulrich:BAAALgADCgYJBgAAAA==.',
Zv='Zvirax:BAAALgADCgcJCAAAAA==.',
['Ëu']='Ëuni:BAAALgAECgMJBQAAAA==.',
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
