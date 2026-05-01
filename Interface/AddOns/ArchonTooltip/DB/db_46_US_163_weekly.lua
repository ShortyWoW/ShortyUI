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

local lookup = {'Priest-Discipline','DemonHunter-Devourer','Rogue-Subtlety','Rogue-Outlaw','Hunter-BeastMastery','Hunter-Marksmanship','Warlock-Demonology','Unknown-Unknown','Warrior-Fury','Rogue-Assassination','Hunter-Survival','Warrior-Protection','Druid-Balance','Druid-Restoration','DeathKnight-Frost','Paladin-Holy','Paladin-Retribution','Druid-Guardian','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Unholy','Monk-Brewmaster','Shaman-Enhancement','Mage-Frost','DemonHunter-Havoc','Druid-Feral','Warrior-Arms','Priest-Holy','Paladin-Protection','Shaman-Restoration','DemonHunter-Vengeance','Shaman-Elemental','Evoker-Preservation','Warlock-Destruction','Priest-Shadow','Mage-Arcane','Monk-Windwalker','Monk-Mistweaver','DeathKnight-Blood','Warlock-Affliction',}
local provider = {region='US',realm='Nathrezim',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abysm:BAAALgADCgkJDQAAAA==.',
Ac='Achillios:BAAALgADCgMJAwABLgAFFAMJCQABANkRAA==.',
Ad='Adorabull:BAAALgAECgEJAQABLgAECgkJIQACAKcdAA==.',
Ae='Aemun:BAABLgAECn8kAAMDAAgJghWCBgAOAgADAAgJghWCBgAOAgAEAAYJlAmxCAD2AAAAAA==.',
Ak='Akelita:BAAALgAECgYJEwAAAA==.',
Al='Alailea:BAABLgAECn8eAAIFAAgJ2hAfHQCxAQAFAAgJ2hAfHQCxAQAAAA==.Alwysafkable:BAAALgADCgQJBAAAAA==.',
Am='Amazadin:BAAALgAFFAIJAgABLgAFFAMJCQABANkRAA==.Amazashock:BAAALgADCgUJBQABLgAFFAMJCQABANkRAA==.',
An='Andiwin:BAAALgAECgkJCQAAAA==.Andurthil:BAAALgAECgYJEwAAAA==.Anzul:BAAALgAECgUJBgAAAA==.',
Ar='Artistic:BAAALgAECggJDgAAAA==.Arylanna:BAAALgAECgYJDQAAAA==.',
As='Asure:BAABLgAECn8cAAMFAAgJFBNJFwDYAQAFAAgJFBNJFwDYAQAGAAYJTgexTwAPAQAAAA==.',
Az='Azerith:BAAALgAECgUJBgAAAA==.',
Be='Bearforceone:BAAALgADCgMJAwAAAA==.',
Bi='Bipolar:BAAALgADCgEJAQAAAA==.',
Bl='Blackheart:BAABLgAECn8YAAIHAAgJpBe8LQBWAgAHAAgJpBe8LQBWAgAAAA==.Blodreina:BAAALgADCgUJCQAAAA==.Bloodarchon:BAAALgAECgYJDwAAAA==.Bloodtemplar:BAAALgAECgYJDwAAAA==.',
Bo='Bombs:BAAALgAECgQJEAAAAA==.Bouren:BAAALgAECgEJAQAAAA==.',
Br='Bravia:BAAALgADCgUJBwAAAA==.Brewdogg:BAAALgADCgcJBwAAAA==.Brutalitops:BAAALgADCgMJAwAAAA==.Brônze:BAAALgADCgQJBAAAAA==.',
Bu='Burdomew:BAAALgADCgEJAQAAAA==.',
Ca='Cadbury:BAAALgADCgIJAgABLgAECgUJCAAIAAAAAA==.Canan:BAAALgAECgMJAwAAAA==.Canestoast:BAAALgAECgEJAQAAAA==.Casmina:BAABLgAECn8UAAIJAAkJ8BdSIQBJAgAJAAkJ8BdSIQBJAgAAAA==.Castiell:BAAALgADCgUJBgAAAA==.Catalystic:BAAALgADCgEJAQAAAA==.Catd:BAAALgADCgEJAQAAAA==.',
Ce='Celum:BAAALgAECgUJCQAAAA==.Ceola:BAAALgAECgQJBAAAAA==.',
Ch='Chamming:BAAALgADCgIJAgAAAA==.Chaquén:BAAALgAECgcJEwAAAA==.Charizard:BAAALgAECgEJAQAAAA==.Charmander:BAABLgAECn8UAAMKAAYJsheZBQBlAQAKAAYJsheZBQBlAQAEAAMJwATDCQCDAAAAAA==.Chaw:BAACLgAFFH8OAAMLAAUJTh33BwAZAQALAAQJRBr3BwAZAQAFAAEJbiabIQBdAAAuAAQKfygABAsACQknJIMEADwCAAsACQnIIoMEADwCAAYABwnWH1EiABECAAUABAk3I01IAJEBAAAA.Chenkenichi:BAAALgAECgYJDwAAAA==.Chergar:BAABLgAECn8bAAIMAAgJ5iFKBQDpAgAMAAgJ5iFKBQDpAgAAAA==.Chskie:BAAALgADCgUJBQAAAA==.Chsky:BAAALgADCgUJBQAAAA==.Chuiyi:BAAALgAECgEJAQAAAA==.',
Ci='Cinny:BAABLgAECn8vAAIFAAkJNBnGCwBFAgAFAAkJNBnGCwBFAgAAAA==.Cinnyrolls:BAABLgAECn8VAAMNAAcJIx6ECgDmAQANAAcJIx6ECgDmAQAOAAQJtBBehwDHAAAAAA==.Cityairlines:BAABLgAECn8kAAIPAAkJthSUAQAiAgAPAAkJthSUAQAiAgAAAA==.',
Cl='Clare:BAAALgAECgYJCQAAAA==.',
Co='Cooldukenuke:BAACLgAFFH8GAAIQAAMJqg/yDwDaAAAQAAMJqg/yDwDaAAAuAAQKfx8AAhAACAlZHjkTAHgCABAACAlZHjkTAHgCAAAA.',
Cr='Creepychalk:BAAALgAECgQJBwAAAA==.Criticize:BAABLgAECn8YAAIRAAYJSwbtdQDCAAARAAYJSwbtdQDCAAAAAA==.',
Cs='Csorb:BAABLgAECn8nAAISAAgJ2iF7AQCCAgASAAgJ2iF7AQCCAgAAAA==.Csoren:BAAALgADCgQJBAAAAA==.Csoro:BAAALgADCggJCAAAAA==.',
Cu='Cultivation:BAAALgAECgUJCAAAAA==.Cursedcanfly:BAACLgAFFH8PAAITAAUJ3B7sBgCFAQATAAUJ3B7sBgCFAQAuAAQKfykAAxMACQmNJeYDAFoDABMACQmNJeYDAFoDABQABQnaFG0iABcBAAAA.',
Cw='Cw:BAAALgAECgEJAQAAAA==.',
De='Deathdogg:BAACLgAFFH8JAAIVAAMJyBNzNgDyAAAVAAMJyBNzNgDyAAAuAAQKfyUAAhUACAlxHycUABgCABUACAlxHycUABgCAAAA.Dejavu:BAACLgAFFH8NAAIWAAQJog7aEQALAQAWAAQJog7aEQALAQAuAAQKfyQAAhYACAmWGZkaAC8CABYACAmWGZkaAC8CAAAA.Demivoi:BAAALgAECgYJBwAAAA==.Demona:BAAALgADCgEJAQAAAA==.Deppthcharge:BAAALgAECgYJBgAAAA==.Desdemona:BAAALgADCgUJBwAAAA==.Devimon:BAAALgADCgEJAQAAAA==.Devoi:BAAALgADCgEJAQAAAA==.',
Do='Donrain:BAAALgAECgQJBAAAAA==.Dooghammer:BAABLgAECn8YAAIXAAkJLRpiAQCZAgAXAAkJLRpiAQCZAgAAAA==.',
Dr='Dragussy:BAAALgADCgcJDQABLgAECggJIwAMABUmAA==.',
Du='Duplexity:BAABLgAECn8jAAIMAAgJFSa+AAADAwAMAAgJFSa+AAADAwAAAA==.',
Dw='Dwalin:BAAALgAECgEJAgAAAA==.',
Ec='Ecko:BAAALgAECgEJAQAAAA==.',
Eg='Egohakai:BAACLgAFFH8MAAIRAAQJ2huXCgBiAQARAAQJ2huXCgBiAQAuAAQKfycAAhEACQncIgwNACUDABEACQncIgwNACUDAAAA.',
El='Eloi:BAAALgAECgUJBQABLgAECggJIAAOAHAcAA==.',
Em='Emieretta:BAABLgAECn8rAAIVAAkJkhVOEgAoAgAVAAkJkhVOEgAoAgAAAA==.',
Eq='Eqdk:BAABLgAECn8YAAIVAAgJ9hLtIQC8AQAVAAgJ9hLtIQC8AQAAAA==.',
Er='Erret:BAACLgAFFH8JAAIYAAQJwhHAIQBMAQAYAAQJwhHAIQBMAQAuAAQKfyUAAhgACQkNICkyAKoCABgACQkNICkyAKoCAAAA.',
Ez='Ezinder:BAAALgADCgkJEAAAAA==.',
Fa='Fabius:BAAALgADCgYJBgAAAA==.Faience:BAAALgAECgYJEgAAAA==.Falorina:BAABLgAECn8UAAMZAAYJUCL5BgDsAQAZAAYJUCL5BgDsAQACAAEJAwXM6wAnAAAAAA==.Fathernature:BAABLgAECn8VAAMNAAcJBxnWKAC4AQANAAcJBxnWKAC4AQAaAAEJeQX5OAAlAAAAAA==.Fauna:BAAALgADCgMJAwAAAA==.Fazeup:BAAALgAECgcJBgAAAA==.',
Fe='Feldra:BAABLgAECn8fAAICAAgJ7huKEQDhAQACAAgJ7huKEQDhAQAAAA==.Felfaith:BAAALgADCgQJBAAAAA==.Fester:BAAALgADCgUJBQAAAA==.',
Fi='Finnin:BAABLgAECn8gAAMJAAkJTyOSAAA7AwAJAAkJTyOSAAA7AwAbAAEJ0gZ3SAAkAAAAAA==.',
Fo='Food:BAABLgAECn8jAAIFAAgJ1BvADwAZAgAFAAgJ1BvADwAZAgAAAA==.Formidabull:BAAALgAECgEJAQABLgAECgkJIQACAKcdAA==.Foxdiez:BAAALgAECggJEQAAAA==.',
Fr='Freidafondle:BAAALgAECgMJBAAAAA==.Frostbite:BAAALgAECgcJAgAAAA==.Frozenfaith:BAABLgAECn8jAAMBAAkJIwsgFABXAQABAAcJ+QwgFABXAQAcAAMJMQTbNQBaAAAAAA==.',
Ft='Fthemeta:BAAALgADCgIJAgAAAA==.',
Fu='Furioushealz:BAABLgAECn8kAAIRAAkJaRlmDABjAgARAAkJaRlmDABjAgAAAA==.',
Ga='Gardrius:BAAALgADCgYJBwAAAA==.',
Gh='Ghettomike:BAABLgAECn8iAAIVAAkJ/h31CACPAgAVAAkJ/h31CACPAgAAAA==.Ghoulbane:BAAALgADCgYJCgAAAA==.',
Gi='Gibbits:BAAALgAECgEJAQAAAA==.Giranimo:BAAALgAECgYJCgAAAA==.',
Gl='Glabados:BAAALgAECgIJAgABLgAECgkJJAAWADciAA==.Glossy:BAACLgAFFH8RAAMDAAUJ2R57AwCCAQADAAQJ2R57AwCCAQAEAAMJ8RCTAwCnAAAuAAQKfygABAMACQnfJZQDAGMDAAMACQl+JZQDAGMDAAQAAgmEIWIHANAAAAoAAgkNHysUALsAAAAA.Glossycumbus:BAAALgADCgYJBgABLgAFFAUJEQADANkeAA==.Glossydh:BAAALgAECgYJBgABLgAFFAUJEQADANkeAA==.Glossydk:BAAALgAECgQJBQABLgAFFAUJEQADANkeAA==.Glossylock:BAAALgADCgcJDQABLgAFFAUJEQADANkeAA==.',
Go='Golbigold:BAAALgAECgEJAQAAAA==.Goopy:BAAALgAECgMJAwAAAA==.',
Gr='Grayhoff:BAABLgAECn8cAAIJAAkJigvoCwDvAQAJAAkJigvoCwDvAQAAAA==.Greatclaw:BAAALgADCgMJAwAAAA==.Grewsom:BAACLgAFFH8FAAIRAAMJKB4wGAAZAQARAAMJKB4wGAAZAQAuAAQKfyUAAxEACAkCJWIJAEYDABEACAkCJWIJAEYDAB0ABAnmInUTAJQBAAAA.',
Gu='Gulmok:BAAALgADCgUJBQAAAA==.Guwugga:BAAALgAECgUJCQAAAA==.',
Ha='Halîk:BAAALgAECggJEgAAAA==.Haraka:BAAALgAECgMJBAAAAA==.Harmshock:BAABLgAECn80AAIXAAkJCR+wAADcAgAXAAkJCR+wAADcAgAAAA==.Hathina:BAACLgAFFH8LAAIJAAQJriOPCwA2AQAJAAQJriOPCwA2AQAuAAQKfykAAwkACQmjJSMEAGkDAAkACQmjJSMEAGkDABsAAwmCHyweAP4AAAAA.',
He='Heket:BAABLgAECn8kAAIRAAgJdQa0UQAYAQARAAgJdQa0UQAYAQAAAA==.Hektric:BAAALgAECgMJAwAAAA==.',
Hi='Highdra:BAAALgAECgEJAQAAAA==.Hill:BAABLgAECn8kAAIFAAkJgB9hBAC6AgAFAAkJgB9hBAC6AgAAAA==.Hive:BAABLgAECn8hAAIJAAgJnRUPDgDTAQAJAAgJnRUPDgDTAQAAAA==.',
Ho='Holygem:BAAALgAECgYJCgAAAA==.Holypower:BAAALgADCgcJDQAAAA==.Hotdogwater:BAABLgAECn8WAAIeAAcJpSPGAwDMAgAeAAcJpSPGAwDMAgAAAA==.',
Hu='Husentar:BAABLgAECn8gAAIYAAgJbx7mEgBDAgAYAAgJbx7mEgBDAgAAAA==.Huuhablo:BAABLgAECn8uAAICAAgJHR0VDAAeAgACAAgJHR0VDAAeAgAAAA==.',
Ic='Icaron:BAAALgAECgcJBgAAAA==.',
Ig='Igothots:BAAALgAECgMJAwAAAA==.',
Il='Illuminottey:BAAALgAECggJCwAAAA==.',
In='Inferium:BAAALgADCgYJBgABLgAFFAMJBwAIAAAAAA==.Infernom:BAAALgADCgMJAwABLgAFFAMJBwAIAAAAAA==.Insatiabull:BAABLgAECn8hAAMCAAkJpx3AEgDqAgACAAgJ7R7AEgDqAgAZAAEJwRRGKgBPAAAAAA==.',
Io='Iolchsk:BAAALgAECgQJDAAAAA==.',
Ja='Jacksof:BAAALgAECgkJCgAAAA==.Jackstands:BAABLgAECn8wAAMeAAkJhB8MAwDmAgAeAAkJhB8MAwDmAgAXAAgJtwSlCQBNAQAAAA==.Jagerin:BAAALgAECgYJCwABLgAECgkJJAAWADciAA==.January:BAAALgADCgkJCgABLgAFFAMJBwAFABENAA==.',
Je='Jesse:BAAALgADCgIJAgAAAA==.',
Ji='Jiffi:BAABLgAECn8ZAAIfAAgJyBrwBQA8AgAfAAgJyBrwBQA8AgAAAA==.Jinksy:BAAALgAECgMJBAAAAA==.',
Jm='Jme:BAAALgAECgcJBgAAAA==.',
Jr='Jredz:BAAALgADCgEJAQAAAA==.',
Ju='Jubag:BAAALgADCgIJAgAAAA==.Jumpercables:BAAALgAECgEJAwAAAA==.Junn:BAABLgAECn8kAAIgAAkJqRIsCgD5AQAgAAkJqRIsCgD5AQAAAA==.',
Ka='Kahayman:BAABLgAECn8hAAIYAAgJ0BaATgBLAgAYAAgJ0BaATgBLAgAAAA==.',
Kh='Khathani:BAAALgAECgEJAQAAAA==.',
Ki='Kieran:BAAALgADCgUJBQAAAA==.',
Kn='Knobgoblinn:BAAALgAECgQJBAAAAA==.',
Ko='Komojo:BAAALgAECgYJEgAAAA==.Koriggan:BAABLgAECn8UAAMFAAYJKhB3VQBoAQAFAAYJKhB3VQBoAQAGAAEJ6QBUmwAUAAAAAA==.',
Kr='Krea:BAABLgAECn8UAAIdAAYJJCUXBAARAgAdAAYJJCUXBAARAgAAAA==.Krixx:BAAALgADCgEJAQAAAA==.Krystagosa:BAABLgAECn8eAAQTAAgJbxIBHQAXAQATAAYJGQ8BHQAXAQAhAAcJlg6eDgAWAQAUAAEJhwQhRAAmAAAAAA==.',
Ku='Kuriuh:BAABLgAECn8kAAIHAAkJMhWzEQAXAgAHAAkJMhWzEQAXAgAAAA==.Kurtcobainn:BAAALgADCgkJCQAAAA==.',
La='Lang:BAABLgAECn8gAAIfAAgJzRsWAgAzAgAfAAgJzRsWAgAzAgAAAA==.',
Le='Legionslamm:BAAALgADCgUJBQAAAA==.Leonldas:BAAALgADCgEJAQAAAA==.',
Lo='Loopey:BAAALgAECgcJEAABLgAFFAQJDQAWAKIOAA==.',
Lu='Luceriss:BAAALgAECgcJDgAAAA==.',
Ma='Maeroth:BAAALgADCgUJBQABLgAFFAUJDAAHAHoNAA==.Magicboi:BAAALgAECgYJCgAAAA==.Magwar:BAACLgAFFH8JAAIJAAUJ1gyvEgDyAAAJAAUJ1gyvEgDyAAAuAAQKfygAAgkACQlnHJoZAH8CAAkACQlnHJoZAH8CAAAA.Maike:BAAALgAECgYJDwAAAA==.Marcelyne:BAAALgADCggJDgABLgAECggJHQAHAHkUAA==.Marothius:BAACLgAFFH8MAAMHAAUJeg35LwDlAAAHAAQJZQz5LwDlAAAiAAEJuhAJFABWAAAuAAQKfykAAyIACQkcHBAXAJEBACIABgl3HBAXAJEBAAcABwnVGjpsAIkBAAAA.Martaug:BAABLgAECn8cAAIeAAgJxByCCwAyAgAeAAgJxByCCwAyAgAAAA==.Marune:BAAALgAECgkJDAAAAA==.Maurice:BAAALgADCgYJCwAAAA==.Maverage:BAABLgAECn8eAAMJAAgJfR2mDADlAQAJAAgJfR2mDADlAQAbAAYJ2BOqCgBYAQAAAA==.Mawg:BAAALgAECgEJAQAAAA==.Mayfair:BAAALgAECgYJCAAAAA==.',
Mb='Mbarnes:BAAALgAECgQJBAAAAA==.',
Me='Melee:BAACLgAFFH8iAAIRAAgJBiQjAAB/AgARAAgJBiQjAAB/AgAuAAQKfxQAAhEACQmZJj0CALoDABEACQmZJj0CALoDAAAA.',
Mi='Midnightfear:BAAALgADCgcJBwAAAA==.Mikeyy:BAAALgADCgMJAwAAAA==.Mimoza:BAAALgAECgQJBAAAAA==.Minibeer:BAAALgAECgYJEgAAAA==.Miquella:BAAALgAECgUJBwAAAA==.Misohotramen:BAACLgAFFH8HAAICAAMJtxIzHgDwAAACAAMJtxIzHgDwAAAuAAQKfx8AAgIACAnwH7MzACsCAAIACAnwH7MzACsCAAAA.',
Mo='Moist:BAABLgAECn8gAAISAAgJxCLxAACsAgASAAgJxCLxAACsAgAAAA==.Moonlock:BAAALgADCgYJCgAAAA==.Moor:BAAALgAECgYJBgAAAA==.Mordakka:BAAALgAECgYJCQAAAA==.Morior:BAABLgAECn8uAAMHAAkJRxuqCQBzAgAHAAgJRxuqCQBzAgAiAAIJMBiwUQB5AAAAAA==.Motgustus:BAAALgAECgQJBAAAAA==.',
Mu='Muirfire:BAAALgADCgYJBgAAAA==.Murrda:BAABLgAECn8iAAIHAAgJth+uCgBkAgAHAAgJth+uCgBkAgAAAA==.Muskrattsam:BAABLgAECn8VAAIYAAYJCRWqVAA2AQAYAAYJCRWqVAA2AQAAAA==.',
My='Myravia:BAABLgAECn8WAAIYAAcJpxB+VAA3AQAYAAcJpxB+VAA3AQAAAA==.Myrokos:BAABLgAECn8wAAIRAAkJHx8LBgC5AgARAAkJHx8LBgC5AgAAAA==.',
['Mó']='Mónónoke:BAAALgADCgMJAwAAAA==.',
['Mö']='Möokss:BAAALgADCgQJAgAAAA==.',
Na='Nailo:BAABLgAECn8wAAISAAkJAQ70CgAUAQASAAkJAQ70CgAUAQAAAA==.Nails:BAAALgADCgcJCgAAAA==.Nathanos:BAAALgAECggJCwAAAA==.',
Ne='Nezar:BAAALgAFFAEJAgABLgAFFAEJAwAIAAAAAA==.',
Nh='Nhat:BAAALgAECgMJAwAAAA==.',
Ni='Niaah:BAAALgADCgYJAQABLgAECggJEgAIAAAAAA==.Niddy:BAABLgAECn8aAAIYAAYJ5BI1UQA+AQAYAAYJ5BI1UQA+AQAAAA==.Nisardela:BAAALgADCgMJAwAAAA==.',
No='Nobudy:BAACLgAFFH8QAAMjAAUJtB0wBQB9AQAjAAUJtB0wBQB9AQABAAQJ0QJtEAACAQAuAAQKfycABCMACQmhItoGAB0DACMACQmhItoGAB0DABwABgnIFcAuAIgBAAEAAgnLBNxZAC4AAAAA.Noel:BAAALgAECgQJBwAAAA==.Nomsayin:BAABLgAECn8kAAIHAAgJ0hkQMwBAAgAHAAgJ0hkQMwBAAgAAAA==.Nonospot:BAABLgAECn8XAAMjAAgJAA/5DQClAQAjAAgJAA/5DQClAQABAAEJvANDWgAuAAAAAA==.Noobuddy:BAAALgAECgUJBQABLgAFFAUJEAAjALQdAA==.Noraboo:BAABLgAECn8jAAMYAAgJQBrZGwAEAgAYAAgJmBjZGwAEAgAkAAYJbxyjBAD7AQAAAA==.Norannestra:BAAALgAECgQJBwAAAA==.Novalicious:BAAALgADCgIJAgAAAA==.Novasera:BAAALgAECgcJCAAAAA==.',
Nu='Nubmuffin:BAAALgADCgUJBQAAAA==.',
Nv='Nvied:BAABLgAECn8ZAAMHAAcJ2BULKgCFAQAHAAYJ2BULKgCFAQAiAAEJAADucwAxAAAAAA==.',
Ny='Nyctt:BAABLgAECn8WAAMDAAkJrxhLGQA6AgADAAkJERdLGQA6AgAKAAIJ5xdkFgCSAAAAAA==.Nyzstra:BAABLgAECn8uAAIYAAkJXCI1AwAXAwAYAAkJXCI1AwAXAwAAAA==.',
['Nì']='Nìrvana:BAAALgAECgQJCAAAAA==.',
On='Onlybeams:BAABLgAECn8cAAICAAkJSxvXBQCBAgACAAkJSxvXBQCBAgAAAA==.',
Or='Orphu:BAAALgAECgEJAQAAAA==.',
Pa='Pallyplexity:BAAALgAECgEJAQABLgAECggJIwAMABUmAA==.Palmiste:BAAALgAECgQJBgAAAA==.Pangoplexity:BAAALgADCgIJAgAAAA==.Pastrydragon:BAACLgAFFH8JAAITAAMJxBfREAD7AAATAAMJxBfREAD7AAAuAAQKfyUAAxMACAmZINUKAMgCABMACAmOHtUKAMgCABQABglCI5ILACICAAAA.',
Pi='Pistachio:BAAALgAECgYJEQAAAA==.Pitviper:BAABLgAECn8kAAIKAAkJ3x6CAADNAgAKAAkJ3x6CAADNAgAAAA==.',
Po='Pocketrokit:BAAALgAECgkJCAAAAA==.Pogaca:BAAALgAECgEJAQABLgAECgcJFQANACMeAA==.Portabull:BAAALgADCgcJBwABLgAECgkJIQACAKcdAA==.Possess:BAABLgAECn8jAAIHAAcJ6RwGFQD9AQAHAAcJ6RwGFQD9AQAAAA==.Pownora:BAABLgAECn8UAAMlAAYJsxmTFgA1AQAlAAYJsxmTFgA1AQAmAAEJLgxjaQAtAAABLgAECggJIwAYAEAaAA==.',
Ps='Psarchasm:BAABLgAECn8UAAIJAAcJ9QdHHwA6AQAJAAcJ9QdHHwA6AQAAAA==.',
Pu='Puck:BAAALgAECgEJAgAAAA==.Pugstar:BAAALgAECgMJAwAAAA==.',
Qe='Qel:BAAALgADCgYJCQAAAA==.',
Ra='Rai:BAABLgAECn8gAAIFAAgJbSDXBQCaAgAFAAgJbSDXBQCaAgAAAA==.Rancidbeef:BAAALgAECgMJAwAAAA==.Rapha:BAABLgAECn8kAAIWAAkJNyLIAAAhAwAWAAkJNyLIAAAhAwAAAA==.Rayyzer:BAABLgAECn8ZAAIDAAgJmCFeAgCdAgADAAgJmCFeAgCdAgAAAA==.',
Re='Rema:BAAALgADCgQJBAAAAA==.Reyna:BAAALgADCgUJBQAAAA==.',
Ri='Riddles:BAAALgAECggJCgAAAA==.Rincewind:BAAALgAECgEJAQAAAA==.',
Ro='Rossabella:BAABLgAECn8tAAMcAAkJ8Q9rDwCtAQAcAAkJCQxrDwCtAQABAAgJ1A5dDgClAQAAAA==.Rot:BAABLgAECn8kAAInAAkJCiZBAAD1AgAnAAkJCiZBAAD1AgAAAA==.',
Ru='Rude:BAAALgAECgYJBgABLgAFFAQJCwAJAK4jAA==.Ruzala:BAAALgADCgEJAQAAAA==.',
Sa='Samsonn:BAAALgADCgQJBAAAAA==.Sanctity:BAAALgADCgYJCgAAAA==.Santino:BAAALgAECgYJBwABLgAECggJIQAYANAWAA==.Saphlocket:BAAALgAECgMJBwAAAA==.Sathin:BAABLgAECn8ZAAICAAgJygYuNgAKAQACAAgJygYuNgAKAQAAAA==.',
Sc='Scher:BAAALgADCgkJCwAAAA==.Scufalufagus:BAAALgAECgUJBQABLgAFFAUJDAAHAHoNAA==.',
Se='Seetick:BAAALgAECgIJBAAAAA==.September:BAAALgAECgIJAgABLgAFFAMJBwAFABENAA==.Sevatar:BAAALgAECggJDgAAAA==.',
Sf='Sfcwarner:BAAALgADCgMJAwAAAA==.',
Sh='Shampooyou:BAABLgAECn8UAAIeAAYJBQZfNgDdAAAeAAYJBQZfNgDdAAAAAA==.Shockakhan:BAAALgAECgMJBAAAAA==.Shocknstone:BAAALgADCgcJBwABLgAECggJIwAMABUmAA==.',
Si='Silentmamba:BAAALgAECgEJAQAAAA==.',
Sk='Skelecopter:BAAALgADCgMJAwAAAA==.',
Sn='Snowflake:BAAALgADCgcJBwAAAA==.',
Sp='Spellsteal:BAABLgAECn8hAAIYAAgJNBrNGwAFAgAYAAgJNBrNGwAFAgAAAA==.Spicynudz:BAAALgAECgEJAQAAAA==.Splashmountn:BAEALgAECgEJAQABLgAECgYJDwAIAAAAAA==.Spring:BAACLgAFFH8HAAMFAAMJEQ16GwD3AAAFAAMJEQ16GwD3AAAGAAEJpADxLQA2AAAuAAQKfyAAAwUACAkjGN0VAOMBAAUACAneF90VAOMBAAYABgnTC+hNABgBAAAA.',
Ss='Ssgwarner:BAAALgADCgQJAQAAAA==.',
St='Stardel:BAAALgAECgYJDQAAAA==.Sting:BAAALgADCgEJAQAAAA==.Stormclaw:BAABLgAECn8gAAIOAAgJcBzDCgBcAgAOAAgJcBzDCgBcAgAAAA==.Stregoica:BAAALgADCgcJDgABLgAFFAUJDAAHAHoNAA==.',
Su='Sushiiez:BAAALgADCgMJAwAAAA==.Suwo:BAAALgADCgIJAQAAAA==.',
Ta='Tallron:BAACLgAFFH8PAAIOAAUJgBrdBgCSAQAOAAUJgBrdBgCSAQAuAAQKfyQAAw4ACQmpI7oJAPcCAA4ACQmpI7oJAPcCAA0AAQnqB3xHADAAAAAA.Tallsera:BAAALgADCgcJDQABLgAFFAUJDwAOAIAaAA==.Tallyfan:BAAALgADCgcJEwAAAA==.Tandraella:BAAALgAECgQJBAABLgAFFAMJCQABANkRAA==.Taqas:BAABLgAECn8lAAIYAAgJcRo9FwAjAgAYAAgJcRo9FwAjAgAAAA==.Taroquin:BAAALgADCgEJAQAAAA==.',
Te='Ternay:BAAALgADCgIJAQAAAA==.Teskhamen:BAAALgADCgQJBQAAAA==.Tetamesh:BAAALgADCgQJBAAAAA==.',
Th='Theskabandit:BAAALgADCgcJEQAAAA==.',
Ti='Tiamot:BAAALgADCgUJCAAAAA==.',
To='Tojikitoushi:BAABLgAECn8gAAIXAAkJPhb3AwD8AQAXAAkJPhb3AwD8AQAAAA==.Tombs:BAAALgAECgYJCAAAAA==.Totenhammer:BAAALgAECgQJCwAAAA==.Totenplage:BAAALgAECgQJBAAAAA==.',
Tr='Tristex:BAAALgADCgEJAQABLgAECgcJFQANACMeAA==.',
Tu='Tuha:BAAALgAFFAEJAQAAAA==.',
Tw='Twergstronk:BAAALgADCgEJAQAAAA==.',
Ty='Tyrolia:BAAALgAECgMJAwAAAA==.',
Va='Valliya:BAAALgADCgcJDQAAAA==.',
Ve='Velratha:BAABLgAECn8UAAIoAAgJtA9iAwCFAQAoAAgJtA9iAwCFAQAAAA==.Vesfu:BAAALgADCgEJAQAAAA==.Vesi:BAAALgADCgcJCgAAAA==.Vextt:BAABLgAECn8eAAMjAAgJ2hdlDAC6AQAjAAcJChtlDAC6AQAcAAIJeBgCOQBMAAAAAA==.',
Vi='Vicsta:BAAALgAECgYJBwAAAA==.',
Vo='Voidrend:BAAALgAECgQJBwAAAA==.Volight:BAAALgADCgYJCQAAAA==.Volke:BAABLgAECn8kAAImAAkJQxY8BwBJAgAmAAkJQxY8BwBJAgAAAA==.Volq:BAAALgADCgIJAgAAAA==.Voltarix:BAAALgAECgQJBAAAAA==.Voodoopriest:BAABLgAECn8YAAIHAAcJLgQzpAAQAQAHAAcJLgQzpAAQAQAAAA==.Voyria:BAABLgAECn8fAAQOAAgJ6QV5PADgAAAOAAcJ5AR5PADgAAANAAQJVwScNgBsAAAaAAIJwwLqHAA7AAAAAA==.',
Vs='Vs:BAAALgAECgYJBgAAAA==.',
Vy='Vynlenn:BAAALgADCgMJAwAAAA==.Vyskar:BAAALgADCgIJAgAAAA==.',
Wa='Warm:BAACLgAFFH8LAAIlAAUJNBzhAgBxAQAlAAUJNBzhAgBxAQAuAAQKfyQAAiUACQnGIGgIAPMCACUACQnGIGgIAPMCAAAA.Warmlight:BAAALgAECgYJDAAAAA==.',
We='Weewu:BAAALgAECgQJBAAAAA==.Weledish:BAACLgAFFH8HAAIYAAMJow4YNQD8AAAYAAMJow4YNQD8AAAuAAQKfyQAAhgACAlgGTNIAF8CABgACAlgGTNIAF8CAAAA.',
Wi='Wienercat:BAABLgAECn8UAAIOAAYJ8yXCBwCSAgAOAAYJ8yXCBwCSAgABLgAECgcJFgAeAKUjAA==.Windmacedu:BAAALgAECgYJCgAAAA==.',
Xt='Xtreeme:BAAALgADCgEJAQAAAA==.',
Ya='Yael:BAABLgAECn8ZAAICAAgJfR6SDQAMAgACAAgJfR6SDQAMAgAAAA==.',
Za='Zarewien:BAABLgAECn8fAAIcAAgJogdJGQA+AQAcAAgJogdJGQA+AQAAAA==.',
Zi='Ziddles:BAAALgAECgYJEAAAAA==.',
Zo='Zomgdk:BAAALgAECgEJAQABLgAECggJLwAWANAbAA==.Zomgmonk:BAABLgAECn8vAAIWAAgJ0BvHBwAZAgAWAAgJ0BvHBwAZAgAAAA==.',
Zu='Zuraq:BAAALgAECgEJAQAAAA==.Zurisdad:BAABLgAECn8fAAIWAAgJcxH5DwCUAQAWAAgJcxH5DwCUAQABLgAFFAQJCQAYAMIRAA==.Zurishmi:BAACLgAFFH8SAAIeAAUJfxwGBgCHAQAeAAUJfxwGBgCHAQAuAAQKfykAAh4ACQmvJBIEADQDAB4ACQmvJBIEADQDAAAA.',
['Äm']='Ämäteräsu:BAAALgAECgQJBAAAAA==.',
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
