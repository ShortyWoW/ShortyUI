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

local lookup = {'Mage-Frost','Paladin-Retribution','DemonHunter-Vengeance','Evoker-Augmentation','Evoker-Devastation','Warlock-Demonology','Unknown-Unknown','Warrior-Fury','Warrior-Arms','DemonHunter-Havoc','DemonHunter-Devourer','Paladin-Protection','Hunter-BeastMastery','Warlock-Affliction','Shaman-Restoration','Shaman-Elemental','Warrior-Protection','Druid-Feral','Druid-Balance','DeathKnight-Unholy','Warlock-Destruction','Monk-Mistweaver','Priest-Holy','Druid-Restoration','Hunter-Marksmanship','Priest-Shadow','Monk-Brewmaster','Evoker-Preservation','Priest-Discipline','Paladin-Holy','Shaman-Enhancement','Monk-Windwalker','Druid-Guardian','Hunter-Survival','DeathKnight-Blood','Rogue-Subtlety','Rogue-Outlaw',}
local provider = {region='US',realm='Agamaggan',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abeblinkin:BAABLgAECn8wAAIBAAkJkh9gCQDeAgABAAkJkh9gCQDeAgAAAA==.',
Ac='Accursed:BAAALgAECgEJAQAAAA==.',
Ad='Adcrusty:BAAALgAECgEJAQAAAA==.',
Ae='Aegrias:BAABLgAECn8hAAICAAkJDB42JwCJAgACAAkJDB42JwCJAgAAAA==.Aeledron:BAAALgADCgQJBQAAAA==.Aerodria:BAABLgAECn8xAAICAAkJGRN+IQABAgACAAkJGRN+IQABAgAAAA==.',
Aj='Ajm:BAAALgAFFAEJAQAAAA==.',
Ak='Akarii:BAAALgAECgYJCQAAAA==.Akeno:BAABLgAECn8VAAIDAAgJQCNZAQAYAwADAAgJQCNZAQAYAwAAAA==.Akiaura:BAAALgAECgYJEgAAAA==.Akime:BAAALgAECgYJDwAAAA==.Akudama:BAABLgAECn8WAAMEAAcJIhjpEQC/AQAEAAcJIhjpEQC/AQAFAAIJqQn9NgBfAAABLgAFFAYJFAAGABYYAA==.',
Al='Alarm:BAAALgADCgEJAQABLgADCgcJCwAHAAAAAA==.Albince:BAAALgADCgIJAgAAAA==.Aldanil:BAAALgAECggJCQAAAA==.Alisae:BAAALgADCgMJAwAAAA==.Alma:BAAALgAECgUJBQAAAA==.Alye:BAAALgAECgcJEAAAAA==.',
An='Ananac:BAAALgADCgEJAQAAAA==.Andreasham:BAAALgADCgEJAQAAAA==.Andrius:BAAALgAECgEJAQAAAA==.Annisseda:BAACLgAFFH8MAAIIAAQJBhdqDABDAQAIAAQJBhdqDABDAQAuAAQKfysAAwgACQmKJMcAAEYDAAgACQmKJMcAAEYDAAkAAQl9ISkvAGMAAAAA.',
Ar='Arktos:BAAALgAECgEJAgAAAA==.Arrhythmia:BAAALgAECgcJFgABLgAFFAYJEwAHAAAAAQ==.Articuno:BAAALgAECgQJBQAAAA==.',
As='Ashrak:BAAALgAECgQJBAAAAA==.Astaulis:BAAALgADCgUJCAAAAA==.',
Ax='Axelle:BAAALgAECgQJCgAAAA==.',
Az='Azzy:BAACLgAFFH8WAAIIAAUJHSHYBgBsAQAIAAUJHSHYBgBsAQAuAAQKfzQAAggACQm4JXkCAJQDAAgACQm4JXkCAJQDAAAA.',
Ba='Babyboomie:BAAALgAECgEJAQAAAA==.Bagagwa:BAAALgADCgcJCAAAAA==.Bal:BAABLgAECn8eAAMKAAgJ7hIYEQB0AQAKAAgJ7hIYEQB0AQALAAYJhQ3FVgD3AAAAAA==.Balam:BAAALgADCgEJAQAAAA==.Balana:BAAALgAECgUJCAAAAA==.Bananski:BAABLgAECn8UAAMCAAYJTA2ZggDnAAACAAYJWwaZggDnAAAMAAUJIA+qJADjAAAAAA==.Bandu:BAAALgADCgEJAgAAAA==.Barkeep:BAABLgAECn8ZAAINAAgJaRCSOADMAQANAAgJaRCSOADMAQAAAA==.',
Be='Beeflocks:BAABLgAECn8ZAAIOAAcJSRlSCADFAQAOAAcJSRlSCADFAQAAAA==.Bekarn:BAABLgAECn8YAAMPAAcJeAoZUwA5AQAPAAcJeAoZUwA5AQAQAAMJ6ghtegBaAAAAAA==.Bennafflock:BAAALgAECgUJCwAAAA==.Bergz:BAAALgAECgMJAgAAAA==.',
Bh='Bhp:BAAALgADCgMJAwABLgAECgMJAwAHAAAAAA==.',
Bi='Bigbleu:BAAALgAECgUJCQABLgAECggJJwARAHEdAA==.Bigpapapump:BAAALgAECgEJAQAAAA==.Bigxthaplug:BAAALgAECgYJCQAAAA==.Bilboswagins:BAABLgAECn8UAAIIAAcJyxwJIwA9AgAIAAcJyxwJIwA9AgAAAA==.Billski:BAAALgAECgcJBwAAAA==.Billyspike:BAABLgAECn8YAAMSAAYJyxrgDQDVAQASAAYJyxrgDQDVAQATAAEJkhJqVQA4AAAAAA==.Billyspiked:BAAALgAECgIJAgABLgAECgYJGAASAMsaAA==.Billyspikeev:BAAALgADCgYJBgABLgAECgYJGAASAMsaAA==.Billyspikepd:BAAALgADCgMJAwABLgAECgYJGAASAMsaAA==.Billyspikepr:BAAALgAECgUJBwABLgAECgYJGAASAMsaAA==.',
Bl='Blammo:BAAALgADCgYJCAAAAA==.Blobcat:BAAALgAFFAEJAQAAAA==.Blobknight:BAAALgADCgEJAQAAAA==.Blobpally:BAACLgAFFH8NAAICAAQJ0RRuGQBGAQACAAQJ0RRuGQBGAQAuAAQKfyAAAgIABwm6IWsdALoCAAIABwm6IWsdALoCAAAA.Bloodhase:BAABLgAECn8YAAIUAAcJVRFtRQBsAQAUAAcJVRFtRQBsAQAAAA==.Bluecard:BAACLgAFFH8LAAIGAAQJnhFQKQAeAQAGAAQJnhFQKQAeAQAuAAQKfywABAYACQl9IQAEAA4DAAYACQl9IQAEAA4DABUAAwnVGMY5AM0AAA4AAQkXIYwnAFMAAAAA.',
Bo='Bokunh:BAAALgAECgYJEgAAAA==.Boomywhoomy:BAAALgAECgIJBAAAAA==.Bothenheim:BAACLgAFFH8MAAICAAQJoSPQCACQAQACAAQJoSPQCACQAQAuAAQKfyYAAgIACQmIIrYEAAUDAAIACQmIIrYEAAUDAAAA.Bowdaddy:BAAALgADCgcJBwAAAA==.',
Br='Brewsimmons:BAABLgAFFH8LAAIWAAcJDAxFBAD7AQAWAAcJDAxFBAD7AQAAAA==.Brüisér:BAABLgAECn8iAAIMAAgJ9hBQDgBSAQAMAAgJ9hBQDgBSAQAAAA==.',
Ca='Callamdrake:BAAALgAECgEJAQAAAA==.Callamsvoid:BAAALgADCgIJAgAAAA==.Camazotz:BAAALgADCgkJCgAAAA==.Capie:BAAALgAECgkJBwAAAA==.Carathea:BAABLgAECn8iAAIXAAgJMSCEDACLAgAXAAgJMSCEDACLAgAAAA==.Carrotbear:BAAALgADCgQJBAAAAA==.Cassiopeià:BAAALgAECgMJAwAAAA==.Caylen:BAACLgAFFH8IAAIYAAMJxh1QGgACAQAYAAMJxh1QGgACAQAuAAQKfyAAAhgACAm3HkERAK0CABgACAm3HkERAK0CAAAA.Cayth:BAABLgAECn8oAAMGAAkJDCGrBQBiAwAGAAkJDCGrBQBiAwAVAAIJCwMZVQBvAAAAAA==.',
Ce='Cemie:BAAALgADCgcJBwAAAA==.Centralia:BAAALgADCgYJBwAAAA==.Centri:BAACLgAFFH8MAAIBAAUJlxrpCgDHAQABAAUJlxrpCgDHAQAuAAQKfyEAAgEACQk7JVwPAKECAAEACQk7JVwPAKECAAAA.Cerestus:BAAALgADCgMJAwAAAA==.',
Ch='Chadbear:BAAALgAECgcJCgAAAA==.Chadtones:BAAALgAECgQJBAAAAA==.Chimueloh:BAAALgADCgQJBAAAAA==.Chiron:BAAALgADCgIJAgAAAA==.Chowa:BAAALgADCgUJCAAAAA==.Chu:BAAALgAECgEJAQAAAA==.',
Cl='Cleverlev:BAAALgAECgYJCgABLgAECggJFAAWANUcAA==.',
Co='Colivism:BAABLgAECn8kAAIBAAgJpRboQQChAQABAAgJpRboQQChAQAAAA==.Colívis:BAAALgAECgQJBQAAAA==.Commodorecdx:BAAALgADCgcJBwAAAA==.Cotali:BAAALgADCgUJBQABLgAECggJIgAXADEgAA==.',
Cr='Crackfiend:BAAALgADCgUJBwAAAA==.Crispi:BAAALgADCgYJBAAAAA==.Cruellev:BAAALgADCgcJDgABLgAECggJFAAWANUcAA==.Crymbrulay:BAAALgAECgYJCAAAAA==.',
Cz='Czernobog:BAAALgAECgMJAwAAAA==.',
Da='Daedrenda:BAAALgAECgMJBAAAAA==.Daeland:BAABLgAECn8UAAIIAAcJ/gipLwAOAQAIAAcJ/gipLwAOAQAAAA==.',
De='Deathtank:BAAALgADCgkJCQAAAA==.Deathtolife:BAAALgAECgQJCAAAAA==.Decima:BAABLgAECn8fAAITAAgJogwEGgBoAQATAAgJogwEGgBoAQAAAA==.Degrance:BAAALgAECgUJBQAAAA==.Demeter:BAACLgAFFH8OAAINAAUJKiHIDABmAQANAAUJKiHIDABmAQAuAAQKfyEAAw0ACQlWIuESAKACAA0ACAk4HuESAKACABkABglxIK8oAOQBAAAA.Demonpunter:BAAALgAECgYJDwAAAA==.Dewussi:BAACLgAFFH8LAAICAAMJRAq9NQDfAAACAAMJRAq9NQDfAAAuAAQKfyQAAwIABwncHWwqANUBAAwABwk4GYANAO8BAAIABwlhG2wqANUBAAAA.',
Di='Dinoscarr:BAAALgAECgQJBgAAAA==.',
Dj='Djholy:BAAALgAECgYJDAAAAA==.',
Do='Dotsndash:BAAALgAECgUJBQAAAA==.',
Dp='Dpsshaman:BAAALgAECgYJDgABLgAECgkJGgAZAKEbAA==.',
Dr='Dreadingfate:BAAALgAECgkJDwAAAA==.Drscholar:BAAALgAECgEJAQAAAA==.Druidpwnz:BAAALgADCgMJAwAAAA==.',
Du='Dungorogue:BAAALgAFFAIJAgAAAA==.Dustln:BAAALgAECgEJAQAAAA==.',
Dy='Dyonne:BAAALgADCgEJAgAAAA==.',
El='Elbone:BAAALgADCgUJBQAAAA==.Elidia:BAAALgADCgcJBwAAAA==.Elinia:BAABLgAECn8qAAMXAAkJ0wsDOQBXAQAXAAgJFgwDOQBXAQAaAAcJSwWEKAADAQAAAA==.Elivoker:BAAALgAECgEJAQAAAA==.Elmdor:BAAALgAECgcJDQAAAA==.Elyndra:BAAALgAECgIJAgAAAA==.',
En='Enlag:BAAALgAECgMJAwAAAA==.',
Et='Etriganna:BAAALgAECgEJAQAAAA==.',
Ev='Evilwitch:BAAALgADCgEJAQAAAA==.Evistiah:BAAALgAECgEJAQAAAA==.',
Ex='Excentric:BAABLgAECn8ZAAICAAgJaR6wFABUAgACAAgJaR6wFABUAgABLgAFFAUJDAABAJcaAA==.Excerpt:BAAALgAECgMJAwABLgAFFAUJDAABAJcaAA==.',
Fa='Farëeya:BAAALgADCgcJDAAAAA==.Fayne:BAAALgADCgUJCgAAAA==.',
Fe='Fernsama:BAAALgAECgYJBgAAAA==.',
Fi='Fishton:BAAALgADCgUJCwAAAA==.',
Fl='Flauros:BAAALgAECgYJEAAAAA==.',
Fr='Fraternite:BAAALgAECgcJCQAAAA==.Froackie:BAAALgAECgYJDwAAAA==.Fruto:BAABLgAECn8mAAIbAAgJGhR6FACZAQAbAAgJGhR6FACZAQAAAA==.',
Ga='Garzislao:BAAALgAECgQJBwAAAA==.',
Gh='Ghostfox:BAAALgAECgMJAwAAAA==.',
Gi='Giterdonee:BAACLgAFFH8NAAIIAAUJhRqzCgBOAQAIAAUJhRqzCgBOAQAuAAQKfyEAAggACQn9IKEEAF8DAAgACQn9IKEEAF8DAAAA.',
Gl='Gleymoulleon:BAAALgAECgQJBwAAAA==.',
Go='Goblinbeans:BAACLgAFFH8LAAIPAAUJlQiQBQBzAQAPAAUJlQiQBQBzAQAuAAQKfxcAAg8ACAlLFqckAAMCAA8ACAlLFqckAAMCAAEuAAUUBwkLABYADAwA.Goku:BAAALgAECgQJBAAAAA==.',
Gr='Greenbeans:BAAALgAECgUJCQABLgAFFAcJCwAWAAwMAA==.Grence:BAAALgAECgUJDAABLgAECgcJEwAHAAAAAA==.Grimreaper:BAABLgAECn8dAAMPAAcJNQ3HLwBSAQAPAAcJNQ3HLwBSAQAQAAQJPwKaXgA9AAAAAA==.Groldin:BAAALgAECgQJBAAAAA==.Groshkar:BAAALgADCgcJCwAAAA==.Grumble:BAAALgAECgEJAQAAAA==.',
['Gõ']='Gõtchoo:BAAALgAECgQJCQAAAA==.',
Ha='Hairball:BAAALgAECgcJEAAAAA==.Hallona:BAAALgADCgMJAwAAAA==.Hammerthumb:BAAALgADCgEJAQABLgAECggJFwASAMwMAA==.',
Ho='Hotdoggin:BAAALgADCgYJDAAAAA==.',
Hy='Hyara:BAABLgAECn8rAAINAAkJghzjDwC8AgANAAkJghzjDwC8AgAAAA==.',
['Hì']='Hìm:BAAALgAECgMJBAAAAA==.',
Ic='Icecreammen:BAAALgADCgQJBAAAAA==.Icobal:BAAALgADCgYJCAAAAA==.',
Il='Illisa:BAAALgADCgMJAwAAAA==.',
Ir='Irongallo:BAAALgADCgEJAQAAAA==.',
Ja='Jabdis:BAAALgADCgEJAQAAAA==.Jacopo:BAAALgAECgYJDwAAAA==.',
Jo='Jocko:BAAALgAECgMJAwAAAA==.Jordi:BAABLgAECn8hAAINAAkJyhktGgBrAgANAAkJyhktGgBrAgAAAA==.',
Ju='Jutti:BAAALgAECgEJAgAAAA==.',
Ka='Kaellen:BAAALgADCgUJBQAAAA==.Kahnman:BAAALgADCgUJBQAAAA==.Kaka:BAAALgAECgcJEwAAAA==.Kalet:BAAALgAECgMJAwAAAA==.Kandinsky:BAAALgADCgIJAgAAAA==.Kanree:BAACLgAFFH8VAAIWAAUJpQfKDgAyAQAWAAUJpQfKDgAyAQAuAAQKfzQAAhYACQkiG0cLAJwCABYACQkiG0cLAJwCAAAA.Kartiri:BAACLgAFFH8MAAMcAAQJLR0DCwBmAQAcAAQJLR0DCwBmAQAEAAIJvwq9MACGAAAuAAQKfyMABBwACQnKG1kGAN4CABwACQnKG1kGAN4CAAQABQnuEn0eAEsBAAUABQkPGMUlAPUAAAAA.Kawhi:BAAALgAFFAEJAQAAAA==.',
Ke='Kea:BAABLgAECn8dAAIdAAkJTCV3AADGAwAdAAkJTCV3AADGAwAAAA==.Keicelinis:BAAALgAECgYJCwAAAA==.Keratos:BAAALgADCggJCQAAAA==.',
Kh='Khran:BAAALgADCgIJAgAAAA==.',
Ki='Kickingfluff:BAAALgADCgIJAgAAAA==.Kipz:BAAALgADCgMJAgABLgAECgIJAgAHAAAAAA==.Kittyboy:BAAALgADCgUJBQAAAA==.',
Ko='Korxin:BAACLgAFFH8LAAINAAUJNRuxDQBjAQANAAUJNRuxDQBjAQAuAAQKfyUAAg0ACQkpI+kEAD8DAA0ACQkpI+kEAD8DAAAA.',
Kr='Kreizikat:BAACLgAFFH8FAAIYAAIJDxSwLwCJAAAYAAIJDxSwLwCJAAAuAAQKfysAAhgACAlVIDQOAMgCABgACAlVIDQOAMgCAAAA.Krinn:BAAALgAECgYJCQAAAA==.',
Ku='Kurquaan:BAAALgAECgYJCQAAAA==.',
Le='Leilar:BAAALgAECgEJAQAAAA==.Levitticus:BAABLgAECn8oAAIeAAgJiRsSHgAmAgAeAAgJiRsSHgAmAgABLgAECggJFAAWANUcAA==.',
Li='Liale:BAAALgAECgMJBAAAAA==.Lidrel:BAAALgAECgYJBgAAAA==.',
Lo='Loinari:BAAALgAECgUJCQAAAA==.Lokano:BAAALgAECgQJBQAAAA==.',
Lu='Luaru:BAAALgAECgEJAQAAAA==.Ludmylha:BAAALgAECgIJAgAAAA==.Luisda:BAAALgADCgUJBQAAAA==.Lulak:BAAALgAECgMJBgAAAA==.Lull:BAABLgAECn8WAAIVAAcJTgtOCwAgAQAVAAcJTgtOCwAgAQAAAA==.Luthin:BAAALgADCgUJBgAAAA==.',
Ly='Lyadre:BAAALgAECgIJAgAAAA==.Lynai:BAAALgADCgIJAgAAAA==.Lyndis:BAAALgAECgQJBAAAAA==.',
Ma='Madness:BAAALgAECgMJAwAAAA==.Magejaf:BAAALgADCgcJDQABLgAECggJEgAHAAAAAA==.Magidragon:BAAALgAECgQJBQAAAA==.Magoraga:BAAALgADCgYJBgAAAA==.',
Md='Mdavis:BAAALgADCgkJCQAAAA==.',
Me='Melt:BAACLgAFFH8UAAIGAAYJFhi2DQBuAQAGAAYJFhi2DQBuAQAuAAQKfzQAAwYACQn8Iv4NAAkDAAYACQn8Iv4NAAkDABUABAmoEnYsAAwBAAAA.Metons:BAAALgAECgMJBAAAAA==.',
Mi='Midei:BAAALgADCgkJFgAAAA==.Midriffluvr:BAAALgAECgQJBAAAAA==.Mikasa:BAAALgADCgEJAQAAAA==.Mike:BAAALgADCgcJCAAAAA==.Mimosa:BAAALgADCgYJCgABLgAECgYJBgAHAAAAAA==.Misfitmagi:BAAALgAECgEJAgAAAA==.Mistfox:BAAALgAECgMJAwAAAA==.',
Mo='Mobiouse:BAAALgADCgYJBgAAAA==.Mollieann:BAAALgAECgIJAgAAAA==.Mommon:BAAALgAECgIJAgAAAA==.Moonraisin:BAAALgADCgkJCwAAAA==.Morrighan:BAAALgADCgQJBQAAAA==.',
Mu='Mukdron:BAAALgADCgIJAgAAAA==.',
Na='Nadra:BAAALgAECggJEgAAAA==.Naminé:BAAALgADCgMJAwAAAA==.Nattyrav:BAACLgAFFH8JAAIfAAQJnR3sAQBtAQAfAAQJnR3sAQBtAQAuAAQKfygAAx8ACQkLH8ADAO4CAB8ACQlnHsADAO4CABAABgmgG5gYAIsBAAAA.Nawari:BAAALgAECgIJAwAAAA==.',
Ne='Nemonk:BAABLgAECn8yAAIgAAkJWBUaDAD3AQAgAAkJWBUaDAD3AQAAAA==.Neryssa:BAACLgAFFH8RAAIGAAYJhBxPCACvAQAGAAYJhBxPCACvAQAuAAQKfzEAAwYACQnWJHwkAIECAAYACAlWJHwkAIECABUABAkpJPUYAIMBAAAA.',
Ni='Nipz:BAAALgAECgEJAQABLgAECgIJAgAHAAAAAA==.',
No='Nocter:BAABLgAECn8eAAQGAAkJsxxgNwAuAgAGAAcJVhxgNwAuAgAOAAUJUiCTCwCBAQAVAAMJ9g3/PQC8AAAAAA==.Noqtir:BAAALgAECgUJBQAAAA==.Not:BAAALgADCgcJAgAAAA==.Noyoo:BAAALgADCgEJAQAAAA==.',
Ny='Nymura:BAAALgAECgYJCQAAAA==.',
['Nä']='Näesthra:BAABLgAECn8kAAIXAAgJcxg7DAAiAgAXAAgJcxg7DAAiAgAAAA==.',
Oa='Oakhugger:BAABLgAECn8XAAISAAgJzAw9DQBEAQASAAgJzAw9DQBEAQAAAA==.',
Ob='Obelisk:BAAALgADCgYJBgAAAA==.Obelix:BAAALgAECgEJAQAAAA==.',
Ok='Okarun:BAABLgAECn8iAAILAAcJTB4zJwCfAQALAAcJTB4zJwCfAQAAAA==.',
Ol='Oldeone:BAAALgAECgMJBAAAAA==.',
Om='Omgega:BAABLgAECn8lAAICAAcJdxx4NACrAQACAAcJdxx4NACrAQAAAA==.',
On='Onimeek:BAABLgAECn8sAAMKAAkJHh6OAwCjAgAKAAkJHh6OAwCjAgALAAIJIghDrQBCAAAAAA==.',
Or='Oryn:BAAALgAECgcJDAABLgAFFAEJAQAHAAAAAA==.Oryx:BAAALgAECgEJAgAAAA==.',
Pa='Pallywahwah:BAAALgADCgQJBAAAAA==.Palpitations:BAAALgAECgYJDQAAAA==.Paper:BAAALgAFFAYJEwAAAQ==.Paudetunia:BAAALgADCgIJAgAAAA==.',
Pe='Peacefullev:BAABLgAECn8UAAIWAAgJ1RyIBgCZAgAWAAgJ1RyIBgCZAgAAAA==.Penance:BAAALgAECgEJAQAAAA==.Pestilence:BAAALgAECggJDQAAAA==.',
Ph='Phantomthief:BAAALgAECgUJAQAAAA==.Phyllus:BAAALgAECgEJAQAAAA==.',
Pi='Pipeleto:BAABLgAECn8WAAIIAAgJwRPJEADtAQAIAAgJwRPJEADtAQAAAA==.',
Po='Poochimus:BAAALgAECggJEwAAAA==.Pookong:BAAALgAECgMJBAAAAA==.Poonslayerxx:BAAALgADCgMJAwAAAA==.',
Pr='Previdius:BAAALgAECgYJCwAAAA==.Priestpwnz:BAAALgAECgYJDgAAAA==.Protomán:BAAALgAECgUJCwAAAA==.Proximity:BAAALgADCgQJBQABLgADCgcJCwAHAAAAAA==.',
Ps='Psychmike:BAAALgAECgEJAQAAAA==.',
Pw='Pwrbttm:BAAALgAECgEJAQABLgAECgcJFAANACocAA==.',
['Pé']='Pépega:BAAALgAECgIJAgAAAA==.',
Ra='Rafferno:BAAALgAECgEJAQAAAA==.',
Re='Redeemedlev:BAACLgAFFH8MAAIdAAQJ/ROaEQA6AQAdAAQJ/ROaEQA6AQAuAAQKfywAAh0ACAlxIfwJAJkCAB0ACAlxIfwJAJkCAAEuAAQKCAkUABYA1RwA.Reds:BAAALgAECgEJAQAAAA==.Relax:BAABLgAECn8TAAILAAYJ+h2DRQDdAQALAAYJ+h2DRQDdAQAAAA==.',
Rh='Rhesand:BAAALgAECgYJCgAAAA==.Rhëa:BAAALgAECgIJAgAAAA==.',
Ri='Riellus:BAAALgADCgkJFQAAAA==.Riiu:BAABLgAECn8cAAIgAAYJGR0KEQCxAQAgAAYJGR0KEQCxAQAAAA==.Rinkelle:BAAALgAECgYJBgAAAA==.Rixin:BAECLgAFFH8PAAIUAAQJXxw+HwBiAQAUAAQJXxw+HwBiAQAuAAQKfzIAAhQACQlKJeQPAB4DABQACQlKJeQPAB4DAAAA.Rixryu:BAEALgADCgkJFgABLgAFFAQJDwAUAF8cAA==.',
Ro='Roaka:BAAALgADCggJCAAAAA==.Rokom:BAACLgAFFH8HAAIIAAMJLBhEFwD1AAAIAAMJLBhEFwD1AAAuAAQKfyQAAggACAnXH28TALICAAgACAnXH28TALICAAAA.Rollster:BAAALgAECgMJAwAAAA==.Rotandroll:BAAALgADCgYJBgABLgAECgEJAQAHAAAAAA==.',
Ru='Ruwey:BAAALgADCgYJCAAAAA==.',
Ry='Ryuk:BAAALgAECgYJEQAAAA==.',
['Rè']='Rèzurrect:BAAALgAECgUJDQAAAA==.',
Sa='Saaratharaxx:BAAALgAECgUJDAAAAA==.Sackhunter:BAABLgAECn8aAAILAAcJcA2kSwAVAQALAAcJcA2kSwAVAQAAAA==.Saero:BAAALgAECgYJDQAAAA==.Saluuknir:BAABLgAECn8mAAMEAAgJQgtzHABaAQAEAAgJ9wpzHABaAQAFAAYJaAeDIwAMAQAAAA==.Saphh:BAAALgAECgcJDgABLgAFFAEJAQAHAAAAAA==.',
Se='Seekae:BAAALgAECgEJAQAAAA==.Sepidasprite:BAAALgADCgEJAQAAAA==.',
Sh='Shaddoot:BAAALgAECgUJBQAAAA==.Shadowbladez:BAAALgAECgEJAQAAAA==.Sheepforfree:BAAALgAECgIJAgAAAA==.Shinishamy:BAAALgADCgEJAQAAAA==.Shirokuma:BAABLgAFFH8MAAIhAAQJZh/vAQB4AQAhAAQJZh/vAQB4AQABLgAECggJFQADAEAjAA==.',
Si='Siera:BAAALgADCgYJBgABLgAECgMJBAAHAAAAAA==.Sigrun:BAAALgADCgIJAgAAAA==.Sipz:BAAALgAECgIJAgAAAA==.',
Sk='Skinbone:BAAALgADCgQJBAAAAA==.',
Sl='Slingshotz:BAABLgAECn8ZAAIiAAkJrhnEBgCQAgAiAAkJrhnEBgCQAgAAAA==.Slootbag:BAAALgAECggJDgAAAA==.',
Sn='Sneux:BAAALgADCgcJDQAAAA==.Snuuze:BAACLgAFFH8MAAICAAMJHCHNHwAvAQACAAMJHCHNHwAvAQAuAAQKfyEAAgIACAljIrYdABUCAAIACAljIrYdABUCAAAA.Snuuzi:BAAALgAECgYJBwABLgAFFAMJDAACABwhAA==.',
So='Soberloki:BAAALgAECgIJAgAAAA==.Solari:BAABLgAECn8SAAMKAAcJ8hcRHwDGAQAKAAcJlhURHwDGAQALAAQJahY1ZgDRAAAAAA==.Solvi:BAAALgAECgYJDQAAAA==.Sophispapa:BAABLgAECn80AAICAAcJTCASGQAzAgACAAcJTCASGQAzAgAAAA==.Souprage:BAAALgAECgQJBgAAAA==.',
Sp='Spellmaden:BAAALgADCgMJBgAAAA==.Spywar:BAAALgADCgkJGAABLgAECggJHwAQACIXAA==.',
St='Starlighter:BAABLgAECn8nAAMaAAgJ9QrKGQBuAQAaAAgJ9QrKGQBuAQAXAAYJGQX5LgDVAAAAAA==.',
Su='Supressor:BAAALgADCgQJCAABLgAECgIJAgAHAAAAAA==.',
Sy='Sylvester:BAAALgADCgIJAgAAAA==.',
['Sé']='Sérolis:BAAALgADCgEJAQAAAA==.',
Ta='Taehausx:BAACLgAFFH8gAAIbAAcJ2SFbAABzAgAbAAcJ2SFbAABzAgAuAAQKfyMAAhsACQnsIiAGACUDABsACQnsIiAGACUDAAAA.Tarmo:BAAALgADCgYJFgAAAA==.',
Te='Telesto:BAAALgAECgIJAgABLgAFFAQJDAACAKEjAA==.Templeton:BAAALgADCgMJAwAAAA==.Tenath:BAABLgAECn8WAAIKAAcJsxGhEgBgAQAKAAcJsxGhEgBgAQAAAA==.',
Th='Thaleon:BAAALgAECgEJAgAAAA==.Tharella:BAAALgAECgMJAwAAAA==.Thauriel:BAAALgAECgIJAgAAAA==.Thrumple:BAAALgADCgYJCgAAAA==.',
Ti='Tinyterror:BAAALgADCgcJCwAAAA==.Titania:BAABLgAECn8dAAIeAAkJSQa8QAB1AQAeAAkJSQa8QAB1AQAAAA==.',
To='Toe:BAACLgAFFH8QAAMUAAUJmiFdFwB3AQAUAAQJmiFdFwB3AQAjAAEJAADTKAAAAAAuAAQKfxsAAhQACAm0HowYAOgCABQACAm0HowYAOgCAAAA.',
Tr='Trollztoll:BAAALgAECgEJAQAAAA==.',
Tu='Tuulk:BAAALgADCgIJAgAAAA==.',
Ty='Typical:BAAALgADCgcJCwAAAA==.',
Ug='Uggoorc:BAABLgAECn8UAAINAAcJKhyVLACdAQANAAcJKhyVLACdAQAAAA==.',
Un='Unholylord:BAAALgAECggJCAABLgAFFAUJFAAaAGgjAA==.',
Va='Vacalocà:BAAALgAECgYJDAAAAA==.Van:BAAALgADCgcJFAAAAA==.Vaultkey:BAAALgADCgIJAwAAAA==.',
Ve='Vegesha:BAAALgAECgEJAgAAAA==.Venin:BAAALgAECgYJBgAAAA==.Vessarind:BAAALgADCgEJAgAAAA==.',
Vi='Vitora:BAAALgAECgYJEQAAAA==.',
Vo='Voidkurn:BAAALgADCgYJCQAAAA==.Von:BAAALgADCgIJAgAAAA==.',
Vy='Vyse:BAAALgADCgYJBgAAAA==.',
Wa='Waally:BAAALgAECgcJEgAAAA==.Wahgwan:BAAALgAECgMJAwAAAA==.Waleran:BAAALgADCgIJAgAAAA==.Warriorbp:BAAALgADCgkJFwAAAA==.Wattz:BAAALgAECgYJBgAAAA==.',
We='Weebsora:BAAALgAECgQJBQAAAA==.',
Wo='Worldtree:BAAALgAECgMJAgAAAA==.',
Xa='Xaelthira:BAAALgAECgYJCgAAAA==.',
Xe='Xerath:BAAALgADCgYJCAAAAA==.',
Xi='Xips:BAAALgADCgMJAwABLgAECgIJAgAHAAAAAA==.',
Xo='Xoru:BAAALgADCgYJBgAAAA==.Xoruk:BAAALgADCgQJBAAAAA==.Xorun:BAAALgAECgEJAQAAAA==.',
Xz='Xzarrion:BAAALgADCgIJAgAAAA==.',
Ya='Yadhi:BAAALgAECgYJDAAAAA==.',
Ye='Yetkin:BAAALgAECgYJDQAAAA==.',
Yi='Yifftron:BAAALgAECgYJBgABLgAECggJGQANAAQgAA==.Yimomo:BAABLgAECn8ZAAMXAAgJchQYLgCMAQAXAAcJ0hQYLgCMAQAaAAcJtQcoKQD+AAAAAA==.',
Yo='Yoshira:BAAALgAECgMJAwABLgAECgMJBAAHAAAAAA==.',
Za='Zalconn:BAABLgAECn8mAAMkAAgJtCU8AwBsAwAkAAgJZyU8AwBsAwAlAAEJ3iYKDgB1AAAAAA==.Zarrona:BAAALgAECgYJEwABLgAECgcJIgALAEweAA==.Zayah:BAAALgAECgUJDQAAAA==.',
Zn='Znasty:BAABLgAECn8WAAIkAAYJNiMtCwDuAQAkAAYJNiMtCwDuAQAAAA==.',
Zo='Zombaman:BAAALgADCgMJAwAAAA==.',
Zy='Zyrap:BAAALgAECgMJAwAAAA==.',
['Öw']='Öwö:BAAALgAECgEJAQAAAA==.',
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
