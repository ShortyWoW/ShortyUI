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

local lookup = {'Mage-Frost','Paladin-Retribution','DemonHunter-Vengeance','Warlock-Demonology','Warrior-Fury','Unknown-Unknown','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-BeastMastery','Warlock-Affliction','Shaman-Restoration','Shaman-Elemental','Warrior-Protection','Druid-Feral','Druid-Balance','Warlock-Destruction','Monk-Mistweaver','Paladin-Protection','Priest-Holy','Druid-Restoration','Hunter-Marksmanship','Priest-Shadow','Monk-Brewmaster','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Priest-Discipline','Paladin-Holy','Shaman-Enhancement','Monk-Windwalker','DeathKnight-Unholy','Druid-Guardian','Hunter-Survival','Rogue-Subtlety',}
local provider = {region='US',realm='Agamaggan',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abeblinkin:BAABLgAECn8wAAIBAAkJpx/6BADtAgABAAkJpx/6BADtAgAAAA==.',
Ac='Accursed:BAAALgAECgEJAQAAAA==.',
Ae='Aegrias:BAABLgAECn8gAAICAAkJNhw4JwCJAgACAAkJNhw4JwCJAgAAAA==.Aeledron:BAAALgADCgQJBQAAAA==.Aerodria:BAABLgAECn8xAAICAAkJKhOhFQANAgACAAkJKhOhFQANAgAAAA==.',
Aj='Ajm:BAAALgAECgQJBgAAAA==.',
Ak='Akarii:BAAALgAECgMJAgAAAA==.Akeno:BAABLgAECn8VAAIDAAgJQCNZAQAYAwADAAgJQCNZAQAYAwAAAA==.Akiaura:BAAALgAECgYJEgAAAA==.Akime:BAAALgAECgYJDwAAAA==.Akudama:BAAALgAECgcJEAABLgAFFAUJDwAEAPAaAA==.',
Al='Albince:BAAALgADCgIJAgAAAA==.Aldanil:BAAALgAECggJCQAAAA==.Alisae:BAAALgADCgMJAwAAAA==.Alma:BAAALgAECgUJBQAAAA==.Alye:BAAALgAECgcJEAAAAA==.',
An='Ananac:BAAALgADCgEJAQAAAA==.Andreasham:BAAALgADCgEJAQAAAA==.Andrius:BAAALgAECgEJAQAAAA==.Annisseda:BAACLgAFFH8JAAIFAAQJphLvCABNAQAFAAQJphLvCABNAQAuAAQKfyMAAgUACAkGIz0JABkDAAUACAkGIz0JABkDAAAA.',
Ar='Arrhythmia:BAAALgAECgcJEAABLgAFFAUJDQAGAAAAAQ==.Articuno:BAAALgAECgMJAwAAAA==.',
As='Ashrak:BAAALgAECgQJBAAAAA==.Astaulis:BAAALgADCgUJCAAAAA==.',
Ax='Axelle:BAAALgAECgMJBgAAAA==.',
Az='Azzy:BAACLgAFFH8SAAIFAAUJfBxnBQBpAQAFAAUJfBxnBQBpAQAuAAQKfy8AAgUACQkhJHoCAJQDAAUACQkhJHoCAJQDAAAA.',
Ba='Babyboomie:BAAALgAECgEJAQAAAA==.Bagagwa:BAAALgADCgcJCAAAAA==.Bal:BAABLgAECn8dAAMHAAgJ7hJdCwCGAQAHAAgJ7hJdCwCGAQAIAAYJjQ06OwD4AAAAAA==.Balam:BAAALgADCgEJAQAAAA==.Balana:BAAALgAECgUJCAAAAA==.Bananski:BAAALgAECgYJEwAAAA==.Bandu:BAAALgADCgEJAgAAAA==.Barkeep:BAABLgAECn8ZAAIJAAgJaRCPOADMAQAJAAgJaRCPOADMAQAAAA==.',
Be='Beeflocks:BAABLgAECn8XAAIKAAYJOBdSCADFAQAKAAYJOBdSCADFAQAAAA==.Bekarn:BAABLgAECn8YAAMLAAcJeAogUwA5AQALAAcJeAogUwA5AQAMAAMJ6ghyegBaAAAAAA==.Bennafflock:BAAALgAECgQJBwAAAA==.Bergz:BAAALgAECgMJAgAAAA==.',
Bh='Bhp:BAAALgADCgMJAwABLgAECgMJAwAGAAAAAA==.',
Bi='Bigbleu:BAAALgAECgUJCQABLgAECggJHwANAHwcAA==.Bigpapapump:BAAALgAECgEJAQAAAA==.Bigxthaplug:BAAALgAECgYJCQAAAA==.Bilboswagins:BAABLgAECn8UAAIFAAcJyxwKIwA9AgAFAAcJyxwKIwA9AgAAAA==.Billski:BAAALgAECgcJBgAAAA==.Billyspike:BAABLgAECn8YAAMOAAYJyxrfDQDVAQAOAAYJyxrfDQDVAQAPAAEJuhKyRAA4AAAAAA==.Billyspiked:BAAALgAECgIJAgABLgAECgYJGAAOAMsaAA==.Billyspikeev:BAAALgADCgYJBgABLgAECgYJGAAOAMsaAA==.Billyspikepd:BAAALgADCgMJAwABLgAECgYJGAAOAMsaAA==.Billyspikepr:BAAALgAECgIJAgABLgAECgYJGAAOAMsaAA==.',
Bl='Blammo:BAAALgADCgYJCAAAAA==.Blobcat:BAAALgAFFAEJAQAAAA==.Blobknight:BAAALgADCgEJAQAAAA==.Blobpally:BAACLgAFFH8JAAICAAQJzRSmFwDxAAACAAQJzRSmFwDxAAAuAAQKfyAAAgIABwm6IW8dALoCAAIABwm6IW8dALoCAAAA.Bloodhase:BAAALgAECgcJEwAAAA==.Bluecard:BAACLgAFFH8IAAIEAAQJFhHRGQA5AQAEAAQJFhHRGQA5AQAuAAQKfyQABAQACAkqH/YeAJ4CAAQACAm0HvYeAJ4CABAAAwnVGMg5AM0AAAoAAQkXIY0nAFMAAAAA.',
Bo='Bokunh:BAAALgAECgYJEgAAAA==.Boomywhoomy:BAAALgADCgEJAQAAAA==.Bothenheim:BAACLgAFFH8JAAICAAQJuSNQBACaAQACAAQJuSNQBACaAQAuAAQKfx4AAgIACAkhIcMaAMkCAAIACAkhIcMaAMkCAAAA.Bowdaddy:BAAALgADCgcJBwAAAA==.',
Br='Brewsimmons:BAABLgAFFH8HAAIRAAYJ9wjGCwAdAQARAAYJ9wjGCwAdAQAAAA==.Brüisér:BAABLgAECn8eAAISAAgJBBHaCgBUAQASAAgJBBHaCgBUAQAAAA==.',
Ca='Callamsvoid:BAAALgADCgIJAgAAAA==.Camazotz:BAAALgADCgkJCgAAAA==.Capie:BAAALgAECgkJBwAAAA==.Carathea:BAABLgAECn8bAAITAAgJ4R+HDACLAgATAAgJ4R+HDACLAgAAAA==.Carrotbear:BAAALgADCgQJBAAAAA==.Cassiopeià:BAAALgAECgMJAwAAAA==.Caylen:BAACLgAFFH8IAAIUAAMJxh1QEgALAQAUAAMJxh1QEgALAQAuAAQKfyAAAhQACAm3HkURAK0CABQACAm3HkURAK0CAAAA.Caytheles:BAABLgAECn8kAAMEAAkJeiCrBQBiAwAEAAkJeiCrBQBiAwAQAAIJCwMbVQBvAAAAAA==.',
Ce='Cemie:BAAALgADCgcJBwAAAA==.Centralia:BAAALgADCgYJBwAAAA==.Centri:BAACLgAFFH8MAAIBAAUJlxrmCgDHAQABAAUJlxrmCgDHAQAuAAQKfxsAAgEACQmrJBMaAA8DAAEACQmrJBMaAA8DAAAA.Cerestus:BAAALgADCgMJAwAAAA==.',
Ch='Chadbear:BAAALgAECgYJBwAAAA==.Chadtones:BAAALgAECgQJBAAAAA==.Chimueloh:BAAALgADCgQJBAAAAA==.Chiron:BAAALgADCgIJAgAAAA==.Chowa:BAAALgADCgUJCAAAAA==.Chu:BAAALgAECgEJAQAAAA==.',
Cl='Cleverlev:BAAALgAECgYJBwABLgAECgYJBgAGAAAAAA==.',
Co='Colivism:BAABLgAECn8dAAIBAAgJeBOleQDeAQABAAgJeBOleQDeAQAAAA==.Colívis:BAAALgAECgQJBQAAAA==.Commodorecdx:BAAALgADCgcJBwAAAA==.Cotali:BAAALgADCgUJBQABLgAECggJGwATAOEfAA==.',
Cr='Crackfiend:BAAALgADCgUJBwAAAA==.Crispi:BAAALgADCgYJBAAAAA==.Cruellev:BAAALgADCgcJDQABLgAECgYJBgAGAAAAAA==.Crymbrulay:BAAALgAECgYJCAAAAA==.',
Cz='Czernobog:BAAALgADCggJFwAAAA==.',
Da='Daedrenda:BAAALgADCgQJBAAAAA==.Daeland:BAABLgAECn8UAAIFAAcJ/AgxJAAZAQAFAAcJ/AgxJAAZAQAAAA==.',
De='Deathtolife:BAAALgAECgQJCAAAAA==.Decima:BAABLgAECn8WAAIPAAYJaQpCJwDMAAAPAAYJaQpCJwDMAAAAAA==.Degrance:BAAALgAECgUJBQAAAA==.Demeter:BAACLgAFFH8KAAIJAAUJCx6jEADDAAAJAAUJCx6jEADDAAAuAAQKfyEAAwkACQlWIuQSAKACAAkACAk4HuQSAKACABUABglxIE0oAOQBAAAA.Demonpunter:BAAALgAECgYJDwAAAA==.Dewussi:BAACLgAFFH8FAAICAAMJLgjWJADcAAACAAMJLgjWJADcAAAuAAQKfyQAAwIABwncHfIcANwBABIABwk4GYINAO8BAAIABwlhG/IcANwBAAAA.',
Di='Dinoscarr:BAAALgAECgQJBgAAAA==.',
Dj='Djholy:BAAALgAECgUJBgAAAA==.',
Do='Dotsndash:BAAALgAECgUJBQAAAA==.',
Dp='Dpsshaman:BAAALgAECgUJCQABLgAECgkJGAAVAKEbAA==.',
Dr='Dreadingfate:BAAALgAECgQJBAAAAA==.Drscholar:BAAALgADCgYJDQAAAA==.Druidpwnz:BAAALgADCgMJAwAAAA==.',
Du='Dungorogue:BAAALgAFFAIJAgAAAA==.Dustln:BAAALgAECgEJAQAAAA==.',
Dy='Dyonne:BAAALgADCgEJAgAAAA==.',
El='Elbone:BAAALgADCgUJBQAAAA==.Elidia:BAAALgADCgcJBwAAAA==.Elinia:BAABLgAECn8pAAMTAAgJGgz8OABXAQATAAgJGgz8OABXAQAWAAYJjgVnIwDgAAAAAA==.Elivoker:BAAALgADCgkJCQAAAA==.Elmdor:BAAALgAECgcJBwAAAA==.Elyndra:BAAALgAECgEJAQAAAA==.',
En='Enlag:BAAALgAECgMJAwAAAA==.',
Et='Etriganna:BAAALgAECgEJAQAAAA==.',
Ev='Evilwitch:BAAALgADCgEJAQAAAA==.',
Ex='Excentric:BAABLgAECn8ZAAICAAgJaR6jDABhAgACAAgJaR6jDABhAgABLgAFFAUJDAABAJcaAA==.Excerpt:BAAALgAECgMJAwABLgAFFAUJDAABAJcaAA==.',
Fa='Farëeya:BAAALgADCgcJCwAAAA==.Fayne:BAAALgADCgUJCgAAAA==.',
Fe='Fernsama:BAAALgAECgEJAQAAAA==.',
Fi='Fishton:BAAALgADCgUJCwAAAA==.',
Fl='Flauros:BAAALgAECgYJCgAAAA==.',
Fr='Fraternite:BAAALgAECgcJCAAAAA==.Froackie:BAAALgAECgYJDgAAAA==.Fruto:BAABLgAECn8iAAIXAAgJHBT1DQCtAQAXAAgJHBT1DQCtAQAAAA==.',
Ga='Garzislao:BAAALgAECgQJBwAAAA==.',
Gh='Ghostfox:BAAALgAECgMJAwAAAA==.',
Gi='Giterdonee:BAACLgAFFH8IAAIFAAUJkBhDFwCzAAAFAAUJkBhDFwCzAAAuAAQKfyEAAgUACQn9IKMEAF8DAAUACQn9IKMEAF8DAAAA.',
Gl='Gleymoulleon:BAAALgAECgQJBwAAAA==.',
Go='Goblinbeans:BAACLgAFFH8LAAILAAUJlQiPBQBzAQALAAUJlQiPBQBzAQAuAAQKfxcAAgsACAlLFqkkAAMCAAsACAlLFqkkAAMCAAEuAAUUBgkHABEA9wgA.Goku:BAAALgAECgQJBAAAAA==.',
Gr='Greenbeans:BAAALgAECgUJCQABLgAFFAYJBwARAPcIAA==.Grence:BAAALgAECgUJDAABLgAECgcJEgAGAAAAAA==.Grimreaper:BAAALgAECgYJDgAAAA==.Groldin:BAAALgAECgQJBAAAAA==.Groshkar:BAAALgADCgcJCwAAAA==.',
['Gõ']='Gõtchoo:BAAALgADCgUJCgAAAA==.',
Ha='Hairball:BAAALgAECgcJEAAAAA==.Hallona:BAAALgADCgMJAwAAAA==.Hammerthumb:BAAALgADCgEJAQABLgAECggJFwAOAMkMAA==.',
Ho='Hotdoggin:BAAALgADCgYJDAAAAA==.',
Hy='Hyara:BAABLgAECn8rAAIJAAkJghzmDwC8AgAJAAkJghzmDwC8AgAAAA==.',
['Hì']='Hìm:BAAALgAECgMJBAAAAA==.',
Ic='Icecreammen:BAAALgADCgQJBAAAAA==.Icobal:BAAALgADCgYJCAAAAA==.',
Il='Illisa:BAAALgADCgMJAwAAAA==.',
Ja='Jabdis:BAAALgADCgEJAQAAAA==.Jacopo:BAAALgAECgYJDwAAAA==.',
Jo='Jocko:BAAALgAECgMJAwAAAA==.Jordi:BAABLgAECn8aAAIJAAgJXRovGgBrAgAJAAgJXRovGgBrAgAAAA==.',
Ju='Jutti:BAAALgAECgEJAQAAAA==.',
Ka='Kahnman:BAAALgADCgUJBQAAAA==.Kaka:BAAALgAECgcJEgAAAA==.Kandinsky:BAAALgADCgIJAgAAAA==.Kanree:BAACLgAFFH8QAAIRAAQJCwgnCgAMAQARAAQJCwgnCgAMAQAuAAQKfy8AAhEACQnRGUcLAJwCABEACQnRGUcLAJwCAAAA.Kartiri:BAACLgAFFH8JAAMYAAQJ4xvVBwBfAQAYAAQJ4xvVBwBfAQAZAAIJyAphJACKAAAuAAQKfx8ABBgACAldHloGAN4CABgACAldHloGAN4CABoABAkjFMolAPUAABkAAwmBEMUqAL8AAAAA.Kawhi:BAAALgAFFAEJAQAAAA==.',
Ke='Kea:BAABLgAECn8XAAIbAAgJmCQqAQBBAwAbAAgJmCQqAQBBAwAAAA==.Keicelinis:BAAALgAECgYJCwAAAA==.Keratos:BAAALgADCggJCQAAAA==.',
Kh='Khaalid:BAAALgADCgcJBwAAAA==.Khran:BAAALgADCgIJAgAAAA==.',
Ki='Kickingfluff:BAAALgADCgIJAgAAAA==.Kittyboy:BAAALgADCgUJBQAAAA==.',
Ko='Korxin:BAACLgAFFH8HAAIJAAUJ6BUcFACzAAAJAAUJ6BUcFACzAAAuAAQKfyUAAgkACQkpI+oEAD8DAAkACQkpI+oEAD8DAAAA.',
Kr='Kreizikat:BAABLgAECn8qAAIUAAgJVSBtCACFAgAUAAgJVSBtCACFAgAAAA==.Krinn:BAAALgAECgYJBwAAAA==.',
Ku='Kurquaan:BAAALgAECgQJBgAAAA==.',
Le='Leilar:BAAALgAECgEJAQAAAA==.Levitticus:BAABLgAECn8gAAIcAAgJFBcTHgAmAgAcAAgJFBcTHgAmAgABLgAECgYJBgAGAAAAAA==.',
Li='Liale:BAAALgAECgMJBAAAAA==.Lidrel:BAAALgAECgYJBgAAAA==.',
Lo='Loinari:BAAALgAECgUJCQAAAA==.Lokano:BAAALgAECgQJBAAAAA==.',
Lu='Luaru:BAAALgAECgEJAQAAAA==.Ludmylha:BAAALgAECgIJAgAAAA==.Luisda:BAAALgADCgUJBQAAAA==.Lulak:BAAALgAECgIJBQAAAA==.Lull:BAAALgAECgcJEAAAAA==.Luthin:BAAALgADCgUJBgAAAA==.',
Ly='Lyadre:BAAALgAECgIJAgAAAA==.Lynai:BAAALgADCgIJAgAAAA==.Lyndis:BAAALgAECgQJBAAAAA==.',
Ma='Madness:BAAALgAECgMJAwAAAA==.Magejaf:BAAALgADCgcJDQABLgAECggJEgAGAAAAAA==.Magidragon:BAAALgAECgMJBAAAAA==.Magoraga:BAAALgADCgYJBgAAAA==.',
Me='Melt:BAACLgAFFH8PAAIEAAUJ8BqzDQBuAQAEAAUJ8BqzDQBuAQAuAAQKfy8AAwQACQmyIgAOAAkDAAQACQmyIgAOAAkDABAABAmoEngsAAwBAAAA.Metons:BAAALgAECgMJBAAAAA==.',
Mi='Midei:BAAALgADCgkJFgAAAA==.Midriffluvr:BAAALgAECgQJBAAAAA==.Mikasa:BAAALgADCgEJAQAAAA==.Mike:BAAALgADCgcJCAAAAA==.Mimosa:BAAALgADCgYJCgABLgAECgEJAQAGAAAAAA==.Mistfox:BAAALgAECgMJAwAAAA==.',
Mo='Mobiouse:BAAALgADCgYJBgAAAA==.Mollieann:BAAALgAECgIJAgAAAA==.Mommon:BAAALgAECgIJAgAAAA==.Moonraisin:BAAALgADCgkJCwAAAA==.Morrighan:BAAALgADCgQJBQAAAA==.',
Mu='Mukdron:BAAALgADCgIJAgAAAA==.',
Na='Nadra:BAAALgAECgcJDAAAAA==.Naminé:BAAALgADCgMJAwAAAA==.Nattyrav:BAABLgAECn8oAAMdAAkJCx/AAwDuAgAdAAkJZx7AAwDuAgAMAAYJoBvIEQCSAQAAAA==.Nawari:BAAALgAECgIJAwAAAA==.',
Ne='Nemonk:BAABLgAECn8lAAIeAAkJ2hM8CwDBAQAeAAkJ2hM8CwDBAQAAAA==.Neryssa:BAACLgAFFH8MAAIEAAUJix26DQBuAQAEAAUJix26DQBuAQAuAAQKfywAAwQACQmwI34kAIECAAQACAknI34kAIECABAABAkpJPcYAIMBAAAA.',
Ni='Nipz:BAAALgADCgYJBgABLgAECgIJAgAGAAAAAA==.',
No='Nocter:BAABLgAECn8eAAQEAAkJsxxhNwAuAgAEAAcJVhxhNwAuAgAKAAUJUiCSCwCBAQAQAAMJ9g3/PQC8AAAAAA==.Noqtir:BAAALgAECgUJBQAAAA==.Not:BAAALgADCgcJAgAAAA==.Noyoo:BAAALgADCgEJAQAAAA==.',
Ny='Nymura:BAAALgAECgMJBwAAAA==.',
['Nä']='Näesthra:BAABLgAECn8iAAITAAgJcxgyDADgAQATAAgJcxgyDADgAQAAAA==.',
Oa='Oakhugger:BAABLgAECn8XAAIOAAgJyQyiCQBNAQAOAAgJyQyiCQBNAQAAAA==.',
Ob='Obelisk:BAAALgADCgYJBgAAAA==.Obelix:BAAALgAECgEJAQAAAA==.',
Ok='Okarun:BAABLgAECn8WAAIIAAYJhh1lQQDuAQAIAAYJhh1lQQDuAQAAAA==.',
Ol='Oldeone:BAAALgAECgMJBAAAAA==.',
Om='Omgega:BAABLgAECn8kAAICAAcJOhvWKACfAQACAAcJOhvWKACfAQAAAA==.',
On='Onimeek:BAABLgAECn8sAAMHAAkJIh7JAQC1AgAHAAkJIh7JAQC1AgAIAAIJIgiVgQBCAAAAAA==.',
Or='Oryn:BAAALgAECgcJDAABLgAECgkJEQAGAAAAAA==.Oryx:BAAALgADCggJEQAAAA==.',
Pa='Pallywahwah:BAAALgADCgQJBAAAAA==.Palpitations:BAAALgAECgYJDAAAAA==.Paper:BAAALgAFFAUJDQAAAQ==.Paudetunia:BAAALgADCgIJAgAAAA==.',
Pe='Peacefullev:BAAALgAECgYJBgAAAA==.Penance:BAAALgAECgEJAQAAAA==.Pestilence:BAAALgAECggJDQAAAA==.',
Ph='Phantomthief:BAAALgAECgUJAQAAAA==.',
Pi='Pipeleto:BAAALgAECgcJEAAAAA==.',
Po='Poochimus:BAAALgAECggJEwAAAA==.Pookong:BAAALgADCgYJBwAAAA==.Poonslayerxx:BAAALgADCgMJAwAAAA==.',
Pr='Previdius:BAAALgAECgUJBQAAAA==.Priestpwnz:BAAALgAECgUJDAAAAA==.Protomán:BAAALgAECgQJBwAAAA==.Proximity:BAAALgADCgQJBQABLgADCgUJBQAGAAAAAA==.',
Ps='Psychmike:BAAALgAECgEJAQAAAA==.',
Pw='Pwrbttm:BAAALgAECgEJAQABLgAFFAEJAQAGAAAAAA==.',
['Pé']='Pépega:BAAALgAECgIJAgAAAA==.',
Ra='Rafferno:BAAALgAECgEJAQAAAA==.',
Re='Redeemedlev:BAACLgAFFH8LAAIbAAQJ2xMuDABGAQAbAAQJ2xMuDABGAQAuAAQKfyYAAhsACAlvIf4JAJkCABsACAlvIf4JAJkCAAEuAAQKBgkGAAYAAAAA.Reds:BAAALgAECgEJAQAAAA==.Relax:BAABLgAECn8TAAIIAAYJ+h2FRQDdAQAIAAYJ+h2FRQDdAQAAAA==.',
Rh='Rhesand:BAAALgAECgYJCgAAAA==.Rhëa:BAAALgAECgIJAQAAAA==.',
Ri='Riellus:BAAALgADCgkJFQAAAA==.Riiu:BAABLgAECn8aAAIeAAYJOxt4EwBUAQAeAAYJOxt4EwBUAQAAAA==.Rinkelle:BAAALgAECgYJBgAAAA==.Rixin:BAECLgAFFH8MAAIfAAQJeBbMFwBGAQAfAAQJeBbMFwBGAQAuAAQKfy0AAh8ACQmEIegPAB4DAB8ACQmEIegPAB4DAAAA.Rixryu:BAEALgADCgkJFgABLgAFFAQJDAAfAHgWAA==.',
Ro='Roaka:BAAALgADCggJCAAAAA==.Rokom:BAABLgAECn8kAAIFAAgJ1x93EwCyAgAFAAgJ1x93EwCyAgAAAA==.Rotandroll:BAAALgADCgYJBgABLgAECgEJAQAGAAAAAA==.',
Ru='Ruwey:BAAALgADCgYJCAAAAA==.',
Ry='Ryuk:BAAALgAECgYJEQAAAA==.',
['Rè']='Rèzurrect:BAAALgAECgUJDQAAAA==.',
Sa='Saaratharaxx:BAAALgAECgUJDAAAAA==.Sackhunter:BAABLgAECn8aAAIIAAcJcA0oMwAWAQAIAAcJcA0oMwAWAQAAAA==.Saero:BAAALgAECgYJDAAAAA==.Saluuknir:BAABLgAECn8iAAMZAAgJSQusFABbAQAZAAgJ/gqsFABbAQAaAAYJaAeKIwAMAQAAAA==.Saphh:BAAALgAECgcJDgABLgAFFAEJAQAGAAAAAA==.',
Se='Seekae:BAAALgAECgEJAQAAAA==.Sepidasprite:BAAALgADCgEJAQAAAA==.',
Sh='Shaddoot:BAAALgAECgUJBQAAAA==.Shadowbladez:BAAALgAECgEJAQAAAA==.Sheepforfree:BAAALgAECgIJAgAAAA==.Shinishamy:BAAALgADCgEJAQAAAA==.Shirokuma:BAABLgAFFH8JAAIgAAQJ/B5qAQByAQAgAAQJ/B5qAQByAQABLgAECggJFQADAEAjAA==.',
Si='Siera:BAAALgADCgYJBgABLgAECgMJBAAGAAAAAA==.Sigrun:BAAALgADCgIJAgAAAA==.Sipz:BAAALgAECgIJAgAAAA==.',
Sk='Skinbone:BAAALgADCgQJBAAAAA==.',
Sl='Slingshotz:BAABLgAECn8ZAAIhAAkJrhnFBgCQAgAhAAkJrhnFBgCQAgAAAA==.Slootbag:BAAALgAECggJDgAAAA==.',
Sn='Sneux:BAAALgADCgcJDQAAAA==.Snuuze:BAACLgAFFH8FAAICAAIJxBv2KgCyAAACAAIJxBv2KgCyAAAuAAQKfxwAAgIACAmhIXAlAJECAAIACAmhIXAlAJECAAAA.Snuuzi:BAAALgADCgEJAQABLgAFFAIJBQACAMQbAA==.',
So='Soberloki:BAAALgADCgUJCgAAAA==.Solari:BAAALgAECgcJEAAAAA==.Solvi:BAAALgAECgYJCgAAAA==.Sophispapa:BAABLgAECn8uAAICAAcJ1B9uEwAfAgACAAcJ1B9uEwAfAgAAAA==.Souprage:BAAALgAECgQJBgAAAA==.',
Sp='Spellmaden:BAAALgADCgMJBgAAAA==.Spywar:BAAALgADCgkJGAABLgAECggJHwAMACIXAA==.',
St='Starlighter:BAABLgAECn8jAAMWAAgJRAosEgB1AQAWAAgJRAosEgB1AQATAAYJGAXnJADWAAAAAA==.',
Su='Supressor:BAAALgADCgQJCAABLgADCgUJCgAGAAAAAA==.',
Sy='Sylvester:BAAALgADCgIJAgAAAA==.',
['Sé']='Sérolis:BAAALgADCgEJAQAAAA==.',
Ta='Taehausx:BAACLgAFFH8aAAIXAAcJTSEuAABcAgAXAAcJTSEuAABcAgAuAAQKfx4AAhcACQm/IiEGACUDABcACQm/IiEGACUDAAAA.Tarmo:BAAALgADCgYJFgAAAA==.',
Te='Telesto:BAAALgAECgIJAgABLgAFFAQJCQACALkjAA==.Templeton:BAAALgADCgMJAwAAAA==.Tenath:BAAALgAECgcJEAAAAA==.',
Th='Thaleon:BAAALgAECgEJAQAAAA==.Tharella:BAAALgAECgMJAwAAAA==.Thauriel:BAAALgADCgMJAwAAAA==.Thrumple:BAAALgADCgYJCgAAAA==.',
Ti='Tinyterror:BAAALgADCgcJCwAAAA==.Titania:BAABLgAECn8YAAIcAAkJrwW7QAB1AQAcAAkJrwW7QAB1AQAAAA==.',
To='Toe:BAACLgAFFH8LAAIfAAQJQiFnEABtAQAfAAQJQiFnEABtAQAuAAQKfxsAAh8ACAm0HosYAOgCAB8ACAm0HosYAOgCAAAA.',
Tu='Tuulk:BAAALgADCgIJAgAAAA==.',
Ty='Typical:BAAALgADCgUJBQAAAA==.',
Ug='Uggoorc:BAAALgAFFAEJAQAAAA==.',
Va='Vacalocà:BAAALgAECgYJBgAAAA==.Van:BAAALgADCgcJDgAAAA==.Vaultkey:BAAALgADCgIJAwAAAA==.',
Ve='Vegesha:BAAALgAECgEJAgAAAA==.Venin:BAAALgAECgYJBgAAAA==.Vessarind:BAAALgADCgEJAgAAAA==.',
Vi='Vitora:BAAALgAECgYJEQAAAA==.',
Vo='Voidkurn:BAAALgADCgYJCQAAAA==.Von:BAAALgADCgIJAgAAAA==.',
Vy='Vyse:BAAALgADCgYJBgAAAA==.',
Wa='Waally:BAAALgAECgcJEgAAAA==.Wahgwan:BAAALgAECgIJAgAAAA==.Waleran:BAAALgADCgIJAgAAAA==.Warriorbp:BAAALgADCgkJFwAAAA==.Wattz:BAAALgAECgUJBQAAAA==.',
We='Weebsora:BAAALgAECgIJAQAAAA==.',
Wo='Worldtree:BAAALgAECgMJAgAAAA==.',
Xa='Xaelthira:BAAALgAECgQJBAAAAA==.',
Xe='Xerath:BAAALgADCgYJCAAAAA==.',
Xi='Xips:BAAALgADCgMJAwABLgAECgIJAgAGAAAAAA==.',
Xo='Xoru:BAAALgADCgYJBgAAAA==.Xoruk:BAAALgADCgQJBAAAAA==.Xorun:BAAALgAECgEJAQAAAA==.',
Xz='Xzarrion:BAAALgADCgIJAgAAAA==.',
Ya='Yadhi:BAAALgAECgQJBgAAAA==.',
Ye='Yetkin:BAAALgAECgYJDQAAAA==.',
Yi='Yifftron:BAAALgAECgYJBgAAAA==.Yimomo:BAAALgAFFAEJAQAAAA==.',
Yo='Yoshira:BAAALgADCgQJBgABLgAECgMJBAAGAAAAAA==.',
Za='Zalconn:BAABLgAECn8iAAIiAAgJISU8AwBsAwAiAAgJISU8AwBsAwAAAA==.Zarrona:BAAALgAECgQJBAAAAA==.Zayah:BAAALgAECgUJCAAAAA==.',
Zn='Znasty:BAAALgAECgYJEAAAAA==.',
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
